-- =========================================================
-- Issue #11: Módulo de Registro de Sesiones, Propuestas,
-- Votaciones y Quórum
-- =========================================================

-- 1. CATÁLOGOS

CREATE TABLE IF NOT EXISTS tipo_sesion (
    id_tipo_sesion SERIAL PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS tipo_modalidad (
    id_tipo_modalidad SERIAL PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS estado_propuesta (
    id_estado_propuesta SERIAL PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS etapa_propuesta (
    id_etapa_propuesta SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS tipo_mayoria_requerida (
    id_tipo_mayoria_requerida SERIAL PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL UNIQUE,
    porcentaje_requerido NUMERIC(5,2) NOT NULL
);

-- 2. SEED DE CATÁLOGOS

INSERT INTO tipo_sesion (nombre) VALUES
('Ordinaria'),
('Extraordinaria')
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO tipo_modalidad (nombre) VALUES
('Presencial'),
('Virtual'),
('Híbrida')
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO estado_propuesta (nombre) VALUES
('Borrador'),
('Pendiente Revisión'),
('Agendada'),
('En Discusión'),
('Aprobada'),
('Rechazada')
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO etapa_propuesta (nombre) VALUES
('Recepción'),
('Revisión'),
('Discusión'),
('Votación'),
('Finalizada')
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO tipo_mayoria_requerida (nombre, porcentaje_requerido) VALUES
('Simple', 50.00),
('Calificada', 66.00)
ON CONFLICT (nombre) DO NOTHING;

-- 3. TABLA DE SESIONES

CREATE TABLE IF NOT EXISTS sesion (
    id_sesion SERIAL PRIMARY KEY,
    numero_sesion VARCHAR(50) NOT NULL UNIQUE,
    fecha DATE NOT NULL,
    id_tipo_sesion INT NOT NULL REFERENCES tipo_sesion(id_tipo_sesion),
    id_tipo_modalidad INT NOT NULL REFERENCES tipo_modalidad(id_tipo_modalidad),
    quorum_requerido INT NOT NULL CHECK (quorum_requerido > 0),
    observaciones TEXT,
    creada_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 4. TABLA DE PROPUESTAS

CREATE TABLE IF NOT EXISTS propuesta (
    id_propuesta SERIAL PRIMARY KEY,
    titulo VARCHAR(255) NOT NULL,
    codigo_air VARCHAR(50) UNIQUE,
    descripcion TEXT,
    id_estado_propuesta INT NOT NULL REFERENCES estado_propuesta(id_estado_propuesta),
    id_etapa_propuesta INT NOT NULL REFERENCES etapa_propuesta(id_etapa_propuesta),
    id_tipo_mayoria_requerida INT NOT NULL REFERENCES tipo_mayoria_requerida(id_tipo_mayoria_requerida),
    creada_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 5. PUNTOS DE AGENDA

CREATE TABLE IF NOT EXISTS punto_agenda (
    id_punto_agenda SERIAL PRIMARY KEY,
    id_sesion INT NOT NULL REFERENCES sesion(id_sesion) ON DELETE CASCADE,
    id_propuesta INT NOT NULL REFERENCES propuesta(id_propuesta),
    orden INT NOT NULL CHECK (orden > 0),
    titulo_punto VARCHAR(255),
    observaciones TEXT,
    UNIQUE (id_sesion, orden),
    UNIQUE (id_sesion, id_propuesta)
);

-- 6. VOTACIONES

CREATE TABLE IF NOT EXISTS votacion_acuerdo (
    id_votacion SERIAL PRIMARY KEY,
    id_punto_agenda INT NOT NULL REFERENCES punto_agenda(id_punto_agenda) ON DELETE CASCADE,
    votos_favor INT NOT NULL CHECK (votos_favor >= 0),
    votos_contra INT NOT NULL CHECK (votos_contra >= 0),
    abstenciones INT NOT NULL CHECK (abstenciones >= 0),
    resultado VARCHAR(20),
    fecha_votacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 7. TABLA TEMPORAL DE ASISTENCIA PLENARIA
-- Esta tabla también será usada por el Issue #12.
-- Se incluye aquí porque validar_quorum(id_sesion) la necesita.

CREATE TABLE IF NOT EXISTS estado_asistencia (
    id_estado_asistencia SERIAL PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL UNIQUE
);

INSERT INTO estado_asistencia (nombre) VALUES
('Presente'),
('Ausente'),
('Justificado')
ON CONFLICT (nombre) DO NOTHING;

CREATE TABLE IF NOT EXISTS asistencia_sesion_plenaria (
    id_asistencia SERIAL PRIMARY KEY,
    id_sesion INT NOT NULL REFERENCES sesion(id_sesion) ON DELETE CASCADE,
    cedula_asambleista VARCHAR(30) NOT NULL,
    id_estado_asistencia INT NOT NULL REFERENCES estado_asistencia(id_estado_asistencia),
    registrada_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (id_sesion, cedula_asambleista)
);

-- 8. FUNCIÓN PARA VALIDAR QUÓRUM

CREATE OR REPLACE FUNCTION validar_quorum(p_id_sesion INT)
RETURNS BOOLEAN AS $$
DECLARE
    presentes INT;
    minimo INT;
BEGIN
    SELECT quorum_requerido
    INTO minimo
    FROM sesion
    WHERE id_sesion = p_id_sesion;

    IF minimo IS NULL THEN
        RAISE EXCEPTION 'La sesión % no existe', p_id_sesion;
    END IF;

    SELECT COUNT(*)
    INTO presentes
    FROM asistencia_sesion_plenaria asp
    INNER JOIN estado_asistencia ea
        ON asp.id_estado_asistencia = ea.id_estado_asistencia
    WHERE asp.id_sesion = p_id_sesion
      AND ea.nombre = 'Presente';

    RETURN presentes >= minimo;
END;
$$ LANGUAGE plpgsql;

-- 9. FUNCIÓN PARA CALCULAR RESULTADO DE VOTACIÓN

CREATE OR REPLACE FUNCTION calcular_resultado_votacion(
    p_votos_favor INT,
    p_votos_contra INT,
    p_abstenciones INT,
    p_id_tipo_mayoria INT
)
RETURNS VARCHAR AS $$
DECLARE
    total_votos_validos INT;
    porcentaje_favor NUMERIC(5,2);
    porcentaje_requerido NUMERIC(5,2);
BEGIN
    total_votos_validos := p_votos_favor + p_votos_contra;

    IF total_votos_validos = 0 THEN
        RETURN 'Rechazada';
    END IF;

    SELECT tmr.porcentaje_requerido
    INTO porcentaje_requerido
    FROM tipo_mayoria_requerida tmr
    WHERE tmr.id_tipo_mayoria_requerida = p_id_tipo_mayoria;

    porcentaje_favor := (p_votos_favor::NUMERIC / total_votos_validos::NUMERIC) * 100;

    IF porcentaje_favor >= porcentaje_requerido THEN
        RETURN 'Aprobada';
    ELSE
        RETURN 'Rechazada';
    END IF;
END;
$$ LANGUAGE plpgsql;

-- 10. TRIGGER PARA ACTUALIZAR RESULTADO Y ESTADO DE PROPUESTA

CREATE OR REPLACE FUNCTION trg_actualizar_estado_propuesta()
RETURNS TRIGGER AS $$
DECLARE
    v_id_propuesta INT;
    v_id_tipo_mayoria INT;
    v_resultado VARCHAR(20);
    v_estado_id INT;
BEGIN
    SELECT 
        p.id_propuesta,
        p.id_tipo_mayoria_requerida
    INTO 
        v_id_propuesta,
        v_id_tipo_mayoria
    FROM punto_agenda pa
    INNER JOIN propuesta p
        ON pa.id_propuesta = p.id_propuesta
    WHERE pa.id_punto_agenda = NEW.id_punto_agenda;

    v_resultado := calcular_resultado_votacion(
        NEW.votos_favor,
        NEW.votos_contra,
        NEW.abstenciones,
        v_id_tipo_mayoria
    );

    NEW.resultado := v_resultado;

    SELECT id_estado_propuesta
    INTO v_estado_id
    FROM estado_propuesta
    WHERE nombre = v_resultado;

    UPDATE propuesta
    SET id_estado_propuesta = v_estado_id
    WHERE id_propuesta = v_id_propuesta;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS actualizar_estado_propuesta_votacion ON votacion_acuerdo;

CREATE TRIGGER actualizar_estado_propuesta_votacion
BEFORE INSERT OR UPDATE ON votacion_acuerdo
FOR EACH ROW
EXECUTE FUNCTION trg_actualizar_estado_propuesta();
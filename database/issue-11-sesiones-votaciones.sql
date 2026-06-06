
-- =========================================================
-- Issue #11: Módulo de Registro de Sesiones, Propuestas,
-- Votaciones y Quórum
-- CORREGIDO: alineado con modelo lógico del proyecto AIR
-- Cambios respecto a versión anterior:
--   - Nombre de tabla: sesion → sesiones (consistencia con modelo lógico)
--   - asistencia_sesion_plenaria usa id_asambleista (FK) en vez de cedula_asambleista
--   - Se elimina la redefinición de estado_asistencia (se define UNA sola vez aquí)
--   - Se agrega columna observaciones en asistencia_sesion_plenaria (requerida por Issue #12)
--   - punto_agenda referencia sesiones (no sesion)
--   - votacion_acuerdo agrega columna es_firme para control de cierre
-- =========================================================

-- =========================================================
-- 1. CATÁLOGOS DE SESIÓN Y PROPUESTA
-- =========================================================

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

-- =========================================================
-- 2. CATÁLOGO DE ESTADO DE ASISTENCIA
-- Definido UNA sola vez aquí; Issue #12 lo reutiliza.
-- =========================================================

CREATE TABLE IF NOT EXISTS estado_asistencia (
    id_estado_asistencia SERIAL PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL UNIQUE
);

-- =========================================================
-- 3. SEED DE CATÁLOGOS
-- =========================================================

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

INSERT INTO estado_asistencia (nombre) VALUES
('Presente'),
('Ausente'),
('Justificado')
ON CONFLICT (nombre) DO NOTHING;

-- =========================================================
-- 4. TABLA DE SESIONES
-- Nombre: sesiones (plural) — consistente con modelo lógico
-- =========================================================

CREATE TABLE IF NOT EXISTS sesiones (
    id_sesion       SERIAL PRIMARY KEY,
    numero_sesion   VARCHAR(50)  NOT NULL UNIQUE,
    fecha           DATE         NOT NULL,
    id_tipo_sesion  INT          NOT NULL REFERENCES tipo_sesion(id_tipo_sesion),
    id_tipo_modalidad INT        NOT NULL REFERENCES tipo_modalidad(id_tipo_modalidad),
    quorum_requerido  INT        NOT NULL CHECK (quorum_requerido > 0),
    link_acta       TEXT,
    observaciones   TEXT,
    creada_en       TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================
-- 5. TABLA DE PROPUESTAS
-- =========================================================

CREATE TABLE IF NOT EXISTS propuesta (
    id_propuesta             SERIAL PRIMARY KEY,
    titulo                   VARCHAR(255) NOT NULL,
    codigo_air               VARCHAR(50)  UNIQUE,
    descripcion              TEXT,
    id_estado_propuesta      INT NOT NULL REFERENCES estado_propuesta(id_estado_propuesta),
    id_etapa_propuesta       INT NOT NULL REFERENCES etapa_propuesta(id_etapa_propuesta),
    id_tipo_mayoria_requerida INT NOT NULL REFERENCES tipo_mayoria_requerida(id_tipo_mayoria_requerida),
    -- Propuestas conciliadas apuntan a su propuesta padre (recursivo)
    id_propuesta_padre       INT REFERENCES propuesta(id_propuesta),
    texto_sustitutivo        TEXT,
    creada_en                TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================
-- 6. PUNTOS DE AGENDA
-- Vincula sesiones con propuestas y define el orden del día
-- =========================================================

CREATE TABLE IF NOT EXISTS punto_agenda (
    id_punto_agenda  SERIAL PRIMARY KEY,
    id_sesion        INT NOT NULL REFERENCES sesiones(id_sesion) ON DELETE CASCADE,
    id_propuesta     INT NOT NULL REFERENCES propuesta(id_propuesta),
    orden            INT NOT NULL CHECK (orden > 0),
    titulo_punto     VARCHAR(255),
    observaciones    TEXT,
    UNIQUE (id_sesion, orden),
    UNIQUE (id_sesion, id_propuesta)
);

-- =========================================================
-- 7. ASISTENCIA A SESIONES PLENARIAS
-- Usa id_asambleista (FK) — integridad referencial correcta.
-- NOTA: depende de que la tabla asambleista exista (Issue #9).
--       Si se ejecuta en un entorno sin Issue #9, se puede
--       comentar la FK y agregarla con ALTER TABLE después.
-- =========================================================

CREATE TABLE IF NOT EXISTS asistencia_sesion_plenaria (
    id_asistencia        SERIAL PRIMARY KEY,
    id_sesion            INT NOT NULL REFERENCES sesiones(id_sesion) ON DELETE CASCADE,
    -- FK hacia asambleista (Issue #9). Ajustar si la tabla aún no existe.
    id_asambleista       INT NOT NULL,  -- REFERENCES asambleista(asambleista_id)
    id_estado_asistencia INT NOT NULL REFERENCES estado_asistencia(id_estado_asistencia),
    observaciones        TEXT,
    registrada_en        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (id_sesion, id_asambleista)
);

-- Comentario: Una vez que el Issue #9 (asambleista) esté ejecutado,
-- habilitar la FK con:
-- ALTER TABLE asistencia_sesion_plenaria
--   ADD CONSTRAINT fk_asp_asambleista
--   FOREIGN KEY (id_asambleista) REFERENCES asambleista(asambleista_id);

-- =========================================================
-- 8. VOTACIONES
-- =========================================================

CREATE TABLE IF NOT EXISTS votacion_acuerdo (
    id_votacion       SERIAL PRIMARY KEY,
    id_punto_agenda   INT NOT NULL REFERENCES punto_agenda(id_punto_agenda) ON DELETE CASCADE,
    votos_favor       INT NOT NULL CHECK (votos_favor >= 0),
    votos_contra      INT NOT NULL CHECK (votos_contra >= 0),
    abstenciones      INT NOT NULL CHECK (abstenciones >= 0),
    resultado         VARCHAR(20),   -- 'Aprobada' | 'Rechazada' — calculado por trigger
    es_firme          BOOLEAN NOT NULL DEFAULT FALSE, -- TRUE = acuerdo cerrado, no editable
    fecha_votacion    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================
-- 9. FUNCIÓN: VALIDAR QUÓRUM
-- Recibe id de sesión, devuelve TRUE si asistentes >= quorum_requerido
-- =========================================================

CREATE OR REPLACE FUNCTION validar_quorum(p_id_sesion INT)
RETURNS BOOLEAN AS $$
DECLARE
    v_presentes   INT;
    v_minimo      INT;
BEGIN
    SELECT quorum_requerido
      INTO v_minimo
      FROM sesiones
     WHERE id_sesion = p_id_sesion;

    IF v_minimo IS NULL THEN
        RAISE EXCEPTION 'La sesión % no existe', p_id_sesion;
    END IF;

    SELECT COUNT(*)
      INTO v_presentes
      FROM asistencia_sesion_plenaria asp
      JOIN estado_asistencia ea ON asp.id_estado_asistencia = ea.id_estado_asistencia
     WHERE asp.id_sesion = p_id_sesion
       AND ea.nombre = 'Presente';

    RETURN v_presentes >= v_minimo;
END;
$$ LANGUAGE plpgsql;

-- =========================================================
-- 10. FUNCIÓN: CALCULAR RESULTADO DE VOTACIÓN
-- Compara votos a favor vs. porcentaje requerido según tipo de mayoría
-- =========================================================

CREATE OR REPLACE FUNCTION calcular_resultado_votacion(
    p_votos_favor  INT,
    p_votos_contra INT,
    p_abstenciones INT,
    p_id_tipo_mayoria INT
)
RETURNS VARCHAR AS $$
DECLARE
    v_total_validos       INT;
    v_porcentaje_favor    NUMERIC(5,2);
    v_porcentaje_requerido NUMERIC(5,2);
BEGIN
    -- Abstenciones no cuentan para el cálculo de mayoría
    v_total_validos := p_votos_favor + p_votos_contra;

    IF v_total_validos = 0 THEN
        RETURN 'Rechazada';
    END IF;

    SELECT porcentaje_requerido
      INTO v_porcentaje_requerido
      FROM tipo_mayoria_requerida
     WHERE id_tipo_mayoria_requerida = p_id_tipo_mayoria;

    IF v_porcentaje_requerido IS NULL THEN
        RAISE EXCEPTION 'Tipo de mayoría % no existe', p_id_tipo_mayoria;
    END IF;

    v_porcentaje_favor := (p_votos_favor::NUMERIC / v_total_validos::NUMERIC) * 100;

    IF v_porcentaje_favor > v_porcentaje_requerido THEN
        RETURN 'Aprobada';
    ELSE
        RETURN 'Rechazada';
    END IF;
END;
$$ LANGUAGE plpgsql;

-- =========================================================
-- 11. TRIGGER: ACTUALIZAR RESULTADO Y ESTADO DE PROPUESTA
-- Se ejecuta BEFORE INSERT OR UPDATE en votacion_acuerdo
-- =========================================================

CREATE OR REPLACE FUNCTION trg_actualizar_estado_propuesta()
RETURNS TRIGGER AS $$
DECLARE
    v_id_propuesta    INT;
    v_id_tipo_mayoria INT;
    v_resultado       VARCHAR(20);
    v_estado_id       INT;
    v_quorum_ok       BOOLEAN;
    v_id_sesion       INT;
BEGIN
    -- Obtener la sesión para validar quórum
    SELECT pa.id_sesion, p.id_propuesta, p.id_tipo_mayoria_requerida
      INTO v_id_sesion, v_id_propuesta, v_id_tipo_mayoria
      FROM punto_agenda pa
      JOIN propuesta p ON pa.id_propuesta = p.id_propuesta
     WHERE pa.id_punto_agenda = NEW.id_punto_agenda;

    IF v_id_propuesta IS NULL THEN
        RAISE EXCEPTION 'El punto de agenda % no existe o no tiene propuesta asociada',
            NEW.id_punto_agenda;
    END IF;

    -- Validar quórum antes de registrar votación
    v_quorum_ok := validar_quorum(v_id_sesion);
    IF NOT v_quorum_ok THEN
        RAISE EXCEPTION 'No se puede registrar la votación: quórum insuficiente en la sesión %',
            v_id_sesion;
    END IF;

    -- Calcular resultado
    v_resultado := calcular_resultado_votacion(
        NEW.votos_favor,
        NEW.votos_contra,
        NEW.abstenciones,
        v_id_tipo_mayoria
    );

    NEW.resultado := v_resultado;

    -- Actualizar estado de la propuesta
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
-- =====================================================================
-- PROYECTO AIR — SPRINT 3 · PERSONA A
-- Núcleo de Sesiones, Votaciones, Asistencias y Comisiones
-- Issues: #11 (sesiones/votaciones) · #12 (asistencias) · #5 (leyendas) · #6 (comisiones)
-- Motor: PostgreSQL 14+
-- =====================================================================
-- Ejecutar DESPUÉS de proyecto-air.sql (Sprint 2). Todo en esquema public.
-- Reutiliza objetos del Sprint 2: asambleista, nombramiento (estado_activo),
-- sector, periodo_gestion, sys_usuario y la función fn_registrar_auditoria().
-- =====================================================================


-- =====================================================================
-- ISSUE #11 — GESTIÓN DE SESIONES Y VOTACIONES (crítico)
-- =====================================================================

-- 11.1 Catálogos
CREATE TABLE IF NOT EXISTS tipo_sesion (
    id_tipo_sesion SERIAL PRIMARY KEY,
    nombre         VARCHAR(60) NOT NULL UNIQUE
);
CREATE TABLE IF NOT EXISTS tipo_modalidad (
    id_tipo_modalidad SERIAL PRIMARY KEY,
    nombre            VARCHAR(60) NOT NULL UNIQUE
);
CREATE TABLE IF NOT EXISTS estado_propuesta (
    id_estado_propuesta SERIAL PRIMARY KEY,
    nombre              VARCHAR(40) NOT NULL UNIQUE
);
CREATE TABLE IF NOT EXISTS tipo_mayoria_requerida (
    id_tipo_mayoria SERIAL PRIMARY KEY,
    nombre          VARCHAR(60) NOT NULL UNIQUE,
    fraccion        NUMERIC(4,3) NOT NULL          -- 0.500 simple, 0.667 calificada
);

-- 11.2 Sesiones plenarias
CREATE TABLE IF NOT EXISTS sesion (
    id_sesion          SERIAL PRIMARY KEY,
    numero_sesion      VARCHAR(30) NOT NULL UNIQUE,
    fecha_sesion       DATE NOT NULL,
    id_tipo_sesion     INT NOT NULL REFERENCES tipo_sesion(id_tipo_sesion),
    id_tipo_modalidad  INT NOT NULL REFERENCES tipo_modalidad(id_tipo_modalidad),
    quorum_requerido   INT NOT NULL DEFAULT 0,
    cerrada            BOOLEAN NOT NULL DEFAULT FALSE,
    fecha_registro     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 11.3 Catálogo de tipos de propuesta con leyenda legal (Issue #5)
CREATE TABLE IF NOT EXISTS catalogo_tipo_propuesta (
    id_tipo_propuesta SERIAL PRIMARY KEY,
    nombre            VARCHAR(80) NOT NULL UNIQUE,
    leyenda_legal     TEXT NOT NULL,
    activo            BOOLEAN NOT NULL DEFAULT TRUE
);
COMMENT ON COLUMN catalogo_tipo_propuesta.leyenda_legal IS
'Issue #5: texto legal que la certificación (#17) inserta al citar una propuesta de este tipo.';

-- 11.4 Propuestas
CREATE TABLE IF NOT EXISTS propuesta (
    id_propuesta        SERIAL PRIMARY KEY,
    titulo              VARCHAR(255) NOT NULL,
    descripcion         TEXT,
    id_sesion           INT REFERENCES sesion(id_sesion),
    id_estado_propuesta INT NOT NULL REFERENCES estado_propuesta(id_estado_propuesta),
    id_tipo_mayoria     INT NOT NULL REFERENCES tipo_mayoria_requerida(id_tipo_mayoria),
    id_tipo_propuesta   INT REFERENCES catalogo_tipo_propuesta(id_tipo_propuesta),
    estado              VARCHAR(40) NOT NULL DEFAULT 'En trámite',
    fecha_registro      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 11.5 Votaciones
CREATE TABLE IF NOT EXISTS votacion (
    id_votacion       SERIAL PRIMARY KEY,
    id_propuesta      INT NOT NULL REFERENCES propuesta(id_propuesta),
    id_sesion         INT NOT NULL REFERENCES sesion(id_sesion),
    votos_favor       INT NOT NULL DEFAULT 0,
    votos_contra      INT NOT NULL DEFAULT 0,
    votos_abstencion  INT NOT NULL DEFAULT 0,
    total_presentes   INT NOT NULL,
    fecha_votacion    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_votos_no_negativos
        CHECK (votos_favor >= 0 AND votos_contra >= 0 AND votos_abstencion >= 0)
);

-- 11.6 Función: ¿la sesión alcanza el quórum? (usada por el controlador ANTES de votar)
CREATE OR REPLACE FUNCTION verificar_quorum(p_id_sesion INT)
RETURNS BOOLEAN AS $$
DECLARE v_presentes INT; v_requerido INT;
BEGIN
    SELECT quorum_requerido INTO v_requerido FROM sesion WHERE id_sesion = p_id_sesion;
    SELECT COUNT(*) INTO v_presentes
      FROM asistencia_sesion_plenaria asp
      JOIN estado_asistencia ea ON ea.id_estado_asistencia = asp.id_estado_asistencia
     WHERE asp.id_sesion = p_id_sesion AND ea.nombre_estado = 'Presente';
    RETURN v_presentes >= COALESCE(v_requerido, 0);
END;
$$ LANGUAGE plpgsql;

-- 11.7 Función: ¿la votación aprueba según la mayoría requerida?
CREATE OR REPLACE FUNCTION evaluar_resultado_votacion(p_id_votacion INT)
RETURNS BOOLEAN AS $$
DECLARE v_favor INT; v_total INT; v_fraccion NUMERIC(4,3);
BEGIN
    SELECT v.votos_favor, v.total_presentes, tm.fraccion
      INTO v_favor, v_total, v_fraccion
      FROM votacion v
      JOIN propuesta p               ON p.id_propuesta   = v.id_propuesta
      JOIN tipo_mayoria_requerida tm ON tm.id_tipo_mayoria = p.id_tipo_mayoria
     WHERE v.id_votacion = p_id_votacion;
    IF v_total = 0 THEN RETURN FALSE; END IF;
    RETURN (v_favor::NUMERIC / v_total) > v_fraccion;
END;
$$ LANGUAGE plpgsql;

-- 11.8 Trigger: al insertar una votación, resuelve el estado de la propuesta
CREATE OR REPLACE FUNCTION fn_resolver_propuesta_por_votacion()
RETURNS TRIGGER AS $$
DECLARE v_aprueba BOOLEAN; v_aprobada INT; v_rechazada INT;
BEGIN
    v_aprueba := evaluar_resultado_votacion(NEW.id_votacion);
    SELECT id_estado_propuesta INTO v_aprobada  FROM estado_propuesta WHERE nombre = 'Aprobada';
    SELECT id_estado_propuesta INTO v_rechazada FROM estado_propuesta WHERE nombre = 'Rechazada';
    UPDATE propuesta
       SET id_estado_propuesta = CASE WHEN v_aprueba THEN v_aprobada ELSE v_rechazada END,
           estado              = CASE WHEN v_aprueba THEN 'Aprobada'  ELSE 'Rechazada'  END
     WHERE id_propuesta = NEW.id_propuesta;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_resolver_propuesta ON votacion;
CREATE TRIGGER trg_resolver_propuesta
    AFTER INSERT ON votacion
    FOR EACH ROW EXECUTE FUNCTION fn_resolver_propuesta_por_votacion();


-- =====================================================================
-- ISSUE #12 — CONTROL DE ASISTENCIAS Y CÁLCULO DE PARTICIPACIÓN
-- =====================================================================

CREATE TABLE IF NOT EXISTS estado_asistencia (
    id_estado_asistencia SERIAL PRIMARY KEY,
    nombre_estado        VARCHAR(20) NOT NULL UNIQUE   -- Presente / Ausente / Justificado
);

CREATE TABLE IF NOT EXISTS asistencia_sesion_plenaria (
    id_asistencia        SERIAL PRIMARY KEY,
    id_sesion            INT NOT NULL REFERENCES sesion(id_sesion),
    cedula_asambleista   VARCHAR(20) NOT NULL REFERENCES asambleista(cedula),
    id_estado_asistencia INT NOT NULL REFERENCES estado_asistencia(id_estado_asistencia),
    CONSTRAINT uk_asistencia_plenaria UNIQUE (id_sesion, cedula_asambleista)
);

CREATE TABLE IF NOT EXISTS sesion_comision (
    id_sesion_comision SERIAL PRIMARY KEY,
    id_comision        INT NOT NULL,            -- FK a comision (se valida en #6)
    numero_sesion      VARCHAR(30),
    fecha_sesion       DATE NOT NULL
);

CREATE TABLE IF NOT EXISTS asistencia_sesion_comision (
    id_asistencia        SERIAL PRIMARY KEY,
    id_sesion_comision   INT NOT NULL REFERENCES sesion_comision(id_sesion_comision),
    cedula_asambleista   VARCHAR(20) NOT NULL REFERENCES asambleista(cedula),
    id_estado_asistencia INT NOT NULL REFERENCES estado_asistencia(id_estado_asistencia),
    CONSTRAINT uk_asistencia_comision UNIQUE (id_sesion_comision, cedula_asambleista)
);

-- % de asistencia plenaria en un rango
CREATE OR REPLACE FUNCTION calcular_porcentaje_asistencia_plenaria(
    p_cedula VARCHAR, p_fecha_inicio DATE, p_fecha_fin DATE
) RETURNS NUMERIC(5,2) AS $$
DECLARE v_convocadas INT; v_presentes INT;
BEGIN
    SELECT COUNT(*) INTO v_convocadas
      FROM sesion s WHERE s.fecha_sesion BETWEEN p_fecha_inicio AND p_fecha_fin;
    SELECT COUNT(*) INTO v_presentes
      FROM asistencia_sesion_plenaria asp
      JOIN sesion s             ON s.id_sesion = asp.id_sesion
      JOIN estado_asistencia ea ON ea.id_estado_asistencia = asp.id_estado_asistencia
     WHERE asp.cedula_asambleista = p_cedula AND ea.nombre_estado = 'Presente'
       AND s.fecha_sesion BETWEEN p_fecha_inicio AND p_fecha_fin;
    IF v_convocadas = 0 THEN RETURN 0; END IF;
    RETURN ROUND(100.0 * v_presentes / v_convocadas, 2);
END;
$$ LANGUAGE plpgsql;

-- % de asistencia a una comisión específica
CREATE OR REPLACE FUNCTION calcular_porcentaje_asistencia_comision(
    p_cedula VARCHAR, p_id_comision INT
) RETURNS NUMERIC(5,2) AS $$
DECLARE v_convocadas INT; v_presentes INT;
BEGIN
    SELECT COUNT(*) INTO v_convocadas
      FROM sesion_comision sc WHERE sc.id_comision = p_id_comision;
    SELECT COUNT(*) INTO v_presentes
      FROM asistencia_sesion_comision asc2
      JOIN sesion_comision sc     ON sc.id_sesion_comision = asc2.id_sesion_comision
      JOIN estado_asistencia ea   ON ea.id_estado_asistencia = asc2.id_estado_asistencia
     WHERE asc2.cedula_asambleista = p_cedula AND sc.id_comision = p_id_comision
       AND ea.nombre_estado = 'Presente';
    IF v_convocadas = 0 THEN RETURN 0; END IF;
    RETURN ROUND(100.0 * v_presentes / v_convocadas, 2);
END;
$$ LANGUAGE plpgsql;


-- =====================================================================
-- ISSUE #6 — COMISIONES Y PROPONENTES
-- =====================================================================

CREATE TABLE IF NOT EXISTS tipo_comision (
    id_tipo_comision SERIAL PRIMARY KEY,
    nombre           VARCHAR(80) NOT NULL UNIQUE
);
CREATE TABLE IF NOT EXISTS rol_comision (
    id_rol_comision SERIAL PRIMARY KEY,
    nombre          VARCHAR(60) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS comision (
    id_comision      SERIAL PRIMARY KEY,
    nombre           VARCHAR(150) NOT NULL,
    objeto           TEXT,
    fecha_creacion   DATE NOT NULL DEFAULT CURRENT_DATE,
    id_tipo_comision INT REFERENCES tipo_comision(id_tipo_comision)
);

CREATE TABLE IF NOT EXISTS integrante_comision (
    id_integrante      SERIAL PRIMARY KEY,
    id_comision        INT NOT NULL REFERENCES comision(id_comision),
    cedula_asambleista VARCHAR(20) NOT NULL REFERENCES asambleista(cedula),
    id_rol_comision    INT NOT NULL REFERENCES rol_comision(id_rol_comision),
    fecha_ingreso      DATE NOT NULL DEFAULT CURRENT_DATE,
    fecha_salida       DATE,
    estado             VARCHAR(20) NOT NULL DEFAULT 'Activo'
);

CREATE TABLE IF NOT EXISTS proponente_propuesta (
    id_proponente      SERIAL PRIMARY KEY,
    id_propuesta       INT NOT NULL REFERENCES propuesta(id_propuesta),
    cedula_asambleista VARCHAR(20) NOT NULL REFERENCES asambleista(cedula),
    rol                VARCHAR(40) NOT NULL DEFAULT 'Proponente',
    CONSTRAINT uk_proponente UNIQUE (id_propuesta, cedula_asambleista)
);

-- FK lógica sesion_comision → comision (ahora que comision existe)
ALTER TABLE sesion_comision
    DROP CONSTRAINT IF EXISTS fk_sesion_comision_comision;
ALTER TABLE sesion_comision
    ADD CONSTRAINT fk_sesion_comision_comision
    FOREIGN KEY (id_comision) REFERENCES comision(id_comision) NOT VALID;

-- Trigger: un asambleísta no puede tener dos roles ACTIVOS en la misma comisión
CREATE OR REPLACE FUNCTION fn_validar_rol_unico_comision()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM integrante_comision
         WHERE id_comision = NEW.id_comision
           AND cedula_asambleista = NEW.cedula_asambleista
           AND estado = 'Activo'
           AND id_integrante <> COALESCE(NEW.id_integrante, -1)
    ) THEN
        RAISE EXCEPTION 'ROL DUPLICADO: el asambleísta % ya tiene un rol activo en la comisión %.',
            NEW.cedula_asambleista, NEW.id_comision;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_rol_unico_comision ON integrante_comision;
CREATE TRIGGER trg_rol_unico_comision
    BEFORE INSERT OR UPDATE ON integrante_comision
    FOR EACH ROW WHEN (NEW.estado = 'Activo')
    EXECUTE FUNCTION fn_validar_rol_unico_comision();


-- =====================================================================
-- AUDITORÍA — se reutiliza la función fn_registrar_auditoria() del Sprint 2
-- =====================================================================
DROP TRIGGER IF EXISTS trg_auditoria_sesion ON sesion;
CREATE TRIGGER trg_auditoria_sesion
    AFTER INSERT OR UPDATE OR DELETE ON sesion
    FOR EACH ROW EXECUTE FUNCTION fn_registrar_auditoria();

DROP TRIGGER IF EXISTS trg_auditoria_votacion ON votacion;
CREATE TRIGGER trg_auditoria_votacion
    AFTER INSERT OR UPDATE OR DELETE ON votacion
    FOR EACH ROW EXECUTE FUNCTION fn_registrar_auditoria();

DROP TRIGGER IF EXISTS trg_auditoria_comision ON comision;
CREATE TRIGGER trg_auditoria_comision
    AFTER INSERT OR UPDATE OR DELETE ON comision
    FOR EACH ROW EXECUTE FUNCTION fn_registrar_auditoria();


-- =====================================================================
-- SEED DATA (idempotente)
-- =====================================================================
INSERT INTO estado_asistencia (nombre_estado) VALUES ('Presente'),('Ausente'),('Justificado')
    ON CONFLICT (nombre_estado) DO NOTHING;
INSERT INTO tipo_sesion (nombre) VALUES ('Ordinaria'),('Extraordinaria')
    ON CONFLICT (nombre) DO NOTHING;
INSERT INTO tipo_modalidad (nombre) VALUES ('Presencial'),('Virtual'),('Híbrida')
    ON CONFLICT (nombre) DO NOTHING;
INSERT INTO estado_propuesta (nombre) VALUES ('En trámite'),('Aprobada'),('Rechazada')
    ON CONFLICT (nombre) DO NOTHING;
INSERT INTO tipo_mayoria_requerida (nombre, fraccion) VALUES ('Simple', 0.500),('Calificada (2/3)', 0.667)
    ON CONFLICT (nombre) DO NOTHING;
INSERT INTO tipo_comision (nombre) VALUES ('Permanente'),('Especial'),('Análisis')
    ON CONFLICT (nombre) DO NOTHING;
INSERT INTO rol_comision (nombre) VALUES ('Coordinador'),('Secretario'),('Integrante')
    ON CONFLICT (nombre) DO NOTHING;

-- Issue #5 — los 4 tipos de propuesta con su leyenda legal
INSERT INTO catalogo_tipo_propuesta (nombre, leyenda_legal) VALUES
('Etapa de Procedencia por Consejo Institucional',
 'La presente propuesta fue declarada procedente por el Consejo Institucional conforme al Estatuto Orgánico, lo que habilita su conocimiento por la Asamblea Institucional Representativa.'),
('Etapa de Procedencia por 10% de Asamblea',
 'La presente propuesta fue presentada con el respaldo de al menos el diez por ciento (10%) de los miembros de la Asamblea Institucional Representativa, según el Estatuto Orgánico.'),
('Aprobación por Dictamen Técnico',
 'La presente propuesta cuenta con el respectivo dictamen técnico que respalda su procedencia para conocimiento del órgano colegiado.'),
('Reforma Estatutaria',
 'Por tratarse de una reforma al Estatuto Orgánico, la presente propuesta requiere la mayoría calificada y el doble debate establecidos en la normativa vigente.')
ON CONFLICT (nombre) DO NOTHING;

-- =====================================================================
-- FIN — SPRINT 3 PERSONA A
-- =====================================================================

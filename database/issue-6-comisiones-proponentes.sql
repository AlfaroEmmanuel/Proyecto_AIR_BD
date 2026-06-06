-- =========================================================
-- Issue #6 (Proyecto): Módulo de Gestión de Comisiones
-- y Proponentes
--
-- Propósito: Gestionar la relación N:M entre asambleístas
-- y comisiones de trabajo, registrar sesiones internas de
-- comisión, sus asistencias, e informes al Directorio.
-- Este módulo es el que certifica participación activa.
--
-- =========================================================

-- =========================================================
-- 1. CATÁLOGOS DE COMISIÓN
-- =========================================================

CREATE TABLE IF NOT EXISTS tipo_comision (
    id_tipo_comision SERIAL PRIMARY KEY,
    nombre           VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS rol_comision (
    id_rol_comision SERIAL PRIMARY KEY,
    nombre          VARCHAR(100) NOT NULL UNIQUE
);

INSERT INTO tipo_comision (nombre) VALUES
('Dictaminadora'),
('Especial'),
('Permanente'),
('Ad Hoc')
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO rol_comision (nombre) VALUES
('Coordinador'),
('Secretario'),
('Integrante'),
('Asesor')
ON CONFLICT (nombre) DO NOTHING;

-- =========================================================
-- 2. TABLA: COMISIÓN
-- =========================================================

CREATE TABLE IF NOT EXISTS comision (
    id_comision      SERIAL PRIMARY KEY,
    id_tipo_comision INT NOT NULL REFERENCES tipo_comision(id_tipo_comision),
    nombre_comision  VARCHAR(255) NOT NULL,
    descripcion      TEXT,   -- objeto de la comisión según acta de creación
    activa           BOOLEAN NOT NULL DEFAULT TRUE,
    creada_en        TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================
-- 3. TABLA: PROPÓSITOS DE COMISIÓN
-- Vincula comisiones con las propuestas que deben analizar.
-- =========================================================

CREATE TABLE IF NOT EXISTS proposito_comision (
    id_proposito_comision SERIAL PRIMARY KEY,
    id_comision           INT NOT NULL REFERENCES comision(id_comision) ON DELETE CASCADE,
    id_propuesta          INT NOT NULL REFERENCES propuesta(id_propuesta),
    texto                 TEXT,
    fecha_registro        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (id_comision, id_propuesta)
);

-- =========================================================
-- 4. TABLA: INTEGRANTES DE COMISIÓN
-- Relación N:M entre asambleista y comision con rol y fechas.
-- =========================================================

CREATE TABLE IF NOT EXISTS integrante_comision (
    id_integrante_comision   SERIAL PRIMARY KEY,
    id_comision              INT NOT NULL REFERENCES comision(id_comision),
    -- FK hacia asambleista (Issue #9). Habilitar con ALTER TABLE.
    id_asambleista           INT NOT NULL,   -- REFERENCES asambleista(asambleista_id)
    id_rol_comision          INT NOT NULL REFERENCES rol_comision(id_rol_comision),
    fecha_ingreso            DATE NOT NULL DEFAULT CURRENT_DATE,
    fecha_fin                DATE,           -- NULL = activo
    estado                   VARCHAR(20) NOT NULL DEFAULT 'Activo'
                                 CHECK (estado IN ('Activo', 'Inactivo')),
    UNIQUE (id_comision, id_asambleista, fecha_ingreso)
);

-- Habilitar FK cuando Issue #9 esté disponible:
-- ALTER TABLE integrante_comision
--   ADD CONSTRAINT fk_ic_asambleista
--   FOREIGN KEY (id_asambleista) REFERENCES asambleista(asambleista_id);

-- =========================================================
-- 5. TABLA: BITÁCORA DE CAMBIOS DE INTEGRANTE EN COMISIÓN
-- Registra cambios de rol, salidas y reincorporaciones.
-- =========================================================

CREATE TABLE IF NOT EXISTS bitacora_integrante_comision (
    id_bitacora              SERIAL PRIMARY KEY,
    id_integrante_comision   INT NOT NULL
        REFERENCES integrante_comision(id_integrante_comision),
    id_comision              INT NOT NULL,
    id_asambleista           INT NOT NULL,
    id_rol_comision          INT NOT NULL REFERENCES rol_comision(id_rol_comision),
    fecha_ingreso_nombramiento DATE NOT NULL,
    fecha_fin_nombramiento     DATE,
    estado                   VARCHAR(20),
    motivo_cambio            TEXT,
    registrada_en            TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================
-- 6. TABLA: PROPONENTES DE PROPUESTA (N:M)
-- Un asambleísta puede ser proponente de varias propuestas.
-- =========================================================

CREATE TABLE IF NOT EXISTS proponente_propuesta (
    id_proponente_propuesta SERIAL PRIMARY KEY,
    id_propuesta            INT NOT NULL REFERENCES propuesta(id_propuesta),
    -- FK hacia asambleista (Issue #9). Habilitar con ALTER TABLE.
    id_asambleista          INT NOT NULL,   -- REFERENCES asambleista(asambleista_id)
    fecha_registro          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (id_propuesta, id_asambleista)
);

-- Habilitar FK cuando Issue #9 esté disponible:
-- ALTER TABLE proponente_propuesta
--   ADD CONSTRAINT fk_pp_asambleista
--   FOREIGN KEY (id_asambleista) REFERENCES asambleista(asambleista_id);

-- =========================================================
-- 7. TABLA: INFORMES AL DIRECTORIO
-- Los informes que una comisión presenta en sesión plenaria.
-- Es lo que certifica el trabajo técnico realizado.
-- =========================================================

CREATE TABLE IF NOT EXISTS informe_directorio (
    id_informe          SERIAL PRIMARY KEY,
    id_comision         INT NOT NULL REFERENCES comision(id_comision),
    id_propuesta        INT NOT NULL REFERENCES propuesta(id_propuesta),
    -- FK hacia sesiones (Issue #11) — sesión plenaria donde se presentó
    id_sesion           INT REFERENCES sesiones(id_sesion),
    titulo              VARCHAR(255) NOT NULL,
    recomendacion       TEXT,
    fecha_presentacion  DATE,
    creado_en           TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================
-- 8. TABLA: JUSTIFICACIONES LEGALES POR INFORME
-- Considerandos y resultandos que respaldan el informe.
-- =========================================================

CREATE TABLE IF NOT EXISTS justificacion_legal (
    id_argumento       SERIAL PRIMARY KEY,
    es_considerando    BOOLEAN NOT NULL DEFAULT TRUE, -- TRUE=considerando, FALSE=resultando
    contenido          TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS justificaciones_por_informe (
    id_informe         INT NOT NULL REFERENCES informe_directorio(id_informe),
    id_argumento       INT NOT NULL REFERENCES justificacion_legal(id_argumento),
    orden_aparicion    INT NOT NULL CHECK (orden_aparicion > 0),
    PRIMARY KEY (id_informe, id_argumento)
);

-- =========================================================
-- 9. TRIGGER: BITÁCORA AUTOMÁTICA DE CAMBIOS EN INTEGRANTES
-- Al UPDATE en integrante_comision, registra el estado anterior.
-- =========================================================

CREATE OR REPLACE FUNCTION trg_bitacora_integrante()
RETURNS TRIGGER AS $$
BEGIN
    -- Solo registra si hay cambio real en estado o rol
    IF OLD.estado <> NEW.estado OR OLD.id_rol_comision <> NEW.id_rol_comision THEN
        INSERT INTO bitacora_integrante_comision (
            id_integrante_comision,
            id_comision,
            id_asambleista,
            id_rol_comision,
            fecha_ingreso_nombramiento,
            fecha_fin_nombramiento,
            estado,
            motivo_cambio
        ) VALUES (
            OLD.id_integrante_comision,
            OLD.id_comision,
            OLD.id_asambleista,
            OLD.id_rol_comision,
            OLD.fecha_ingreso,
            OLD.fecha_fin,
            OLD.estado,
            'Actualización automática de estado/rol'
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS bitacora_cambios_integrante ON integrante_comision;

CREATE TRIGGER bitacora_cambios_integrante
AFTER UPDATE ON integrante_comision
FOR EACH ROW
EXECUTE FUNCTION trg_bitacora_integrante();

-- =========================================================
-- 10. FUNCIÓN: LISTAR INTEGRANTES ACTIVOS DE UNA COMISIÓN
-- =========================================================

CREATE OR REPLACE FUNCTION listar_integrantes_comision(p_id_comision INT)
RETURNS TABLE (
    id_integrante   INT,
    id_asambleista  INT,
    rol             VARCHAR(100),
    fecha_ingreso   DATE,
    fecha_fin       DATE,
    estado          VARCHAR(20)
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        ic.id_integrante_comision,
        ic.id_asambleista,
        rc.nombre AS rol,
        ic.fecha_ingreso,
        ic.fecha_fin,
        ic.estado
    FROM integrante_comision ic
    JOIN rol_comision rc ON ic.id_rol_comision = rc.id_rol_comision
    WHERE ic.id_comision = p_id_comision
    ORDER BY rc.nombre, ic.fecha_ingreso;
END;
$$ LANGUAGE plpgsql;

-- =========================================================
-- 11. FUNCIÓN: INSERTAR INTEGRANTES EN MASA (bulk insert)
-- Recibe array de ids de asambleísta y los agrega a la comisión.
-- =========================================================

CREATE OR REPLACE FUNCTION agregar_integrantes_comision(
    p_id_comision    INT,
    p_ids_asambleista INT[],
    p_id_rol         INT DEFAULT 3   -- 3 = 'Integrante' por defecto
)
RETURNS INT AS $$
DECLARE
    v_id     INT;
    v_count  INT := 0;
BEGIN
    FOREACH v_id IN ARRAY p_ids_asambleista LOOP
        INSERT INTO integrante_comision
            (id_comision, id_asambleista, id_rol_comision)
        VALUES
            (p_id_comision, v_id, p_id_rol)
        ON CONFLICT (id_comision, id_asambleista, fecha_ingreso) DO NOTHING;
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- =========================================================
-- 12. VISTA: PARTICIPACIÓN DE ASAMBLEÍSTAS EN COMISIONES
-- Consolida para certificaciones (Issue #17).
-- =========================================================

CREATE OR REPLACE VIEW v_participacion_comisiones AS
SELECT
    ic.id_asambleista,
    c.nombre_comision,
    tc.nombre           AS tipo_comision,
    rc.nombre           AS rol,
    p.titulo            AS propuesta_analizada,
    p.codigo_air,
    id.titulo           AS informe_presentado,
    id.fecha_presentacion,
    ic.fecha_ingreso,
    ic.fecha_fin,
    ic.estado
FROM integrante_comision ic
JOIN comision             c   ON ic.id_comision        = c.id_comision
JOIN tipo_comision        tc  ON c.id_tipo_comision     = tc.id_tipo_comision
JOIN rol_comision         rc  ON ic.id_rol_comision     = rc.id_rol_comision
LEFT JOIN proposito_comision pc ON c.id_comision        = pc.id_comision
LEFT JOIN propuesta       p   ON pc.id_propuesta        = p.id_propuesta
LEFT JOIN informe_directorio id ON id.id_comision       = c.id_comision
                               AND id.id_propuesta      = p.id_propuesta;

-- =========================================================
-- PRUEBAS
-- =========================================================

-- Crear comisión
INSERT INTO comision (id_tipo_comision, nombre_comision, descripcion)
VALUES (1, 'Comisión de Reforma al Estatuto 2026', 'Análisis de propuesta AIR-05-2026');

-- Agregar integrantes en masa
SELECT agregar_integrantes_comision(1, ARRAY[1, 2, 3, 4], 3);

-- Ver integrantes activos
SELECT * FROM listar_integrantes_comision(1);

-- Vista consolidada para certificación
SELECT * FROM v_participacion_comisiones WHERE id_asambleista = 1;

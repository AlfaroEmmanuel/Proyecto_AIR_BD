-- =========================================================
-- Issue #12: Control de Asistencias y Cálculo de Participación
-- CORREGIDO: alineado con modelo lógico del proyecto AIR
-- Cambios respecto a versión anterior:
--   - Se ELIMINA la redefinición de estado_asistencia (ya existe en Issue #11)
--   - Se ELIMINA la redefinición de asistencia_sesion_plenaria (ya existe en Issue #11)
--   - asistencia_sesion_plenaria usa sesiones (plural) como FK
--   - sesion_comision ahora tiene FK correcta hacia comision (Issue #7 / #11 de proyecto)
--   - asistencia_sesion_comision usa id_asambleista (FK) en vez de cedula_asambleista
--   - Funciones de cálculo actualizadas para usar id_asambleista
-- =========================================================

-- =========================================================
-- 1. SESIONES DE COMISIÓN
-- Depende de la tabla comision (Issue #7 del proyecto).
-- FK hacia comision se habilita vía ALTER TABLE posterior.
-- =========================================================

CREATE TABLE IF NOT EXISTS sesion_comision (
    id_sesion_comision SERIAL PRIMARY KEY,
    -- FK hacia comision (Issue #7). Agregar con ALTER TABLE cuando exista.
    id_comision        INT,           -- REFERENCES comision(id_comision)
    fecha              DATE         NOT NULL,
    tema               VARCHAR(255) NOT NULL,
    observaciones      TEXT,
    creada_en          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Habilitar FK cuando comision (Issue #7) esté disponible:
-- ALTER TABLE sesion_comision
--   ADD CONSTRAINT fk_sc_comision
--   FOREIGN KEY (id_comision) REFERENCES comision(id_comision);

-- =========================================================
-- 2. ASISTENCIA A SESIONES DE COMISIÓN
-- Usa id_asambleista (FK) — consistente con modelo lógico.
-- =========================================================

CREATE TABLE IF NOT EXISTS asistencia_sesion_comision (
    id_asistencia_comision SERIAL PRIMARY KEY,
    id_sesion_comision     INT NOT NULL
        REFERENCES sesion_comision(id_sesion_comision) ON DELETE CASCADE,
    -- FK hacia asambleista (Issue #9). Agregar con ALTER TABLE cuando exista.
    id_asambleista         INT NOT NULL,  -- REFERENCES asambleista(asambleista_id)
    id_comision            INT,           -- REFERENCES comision(id_comision)
    id_estado_asistencia   INT NOT NULL
        REFERENCES estado_asistencia(id_estado_asistencia),
    observaciones          TEXT,
    registrada_en          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (id_sesion_comision, id_asambleista)
);

-- Habilitar FKs cuando las tablas padre estén disponibles:
-- ALTER TABLE asistencia_sesion_comision
--   ADD CONSTRAINT fk_asc_asambleista
--   FOREIGN KEY (id_asambleista) REFERENCES asambleista(asambleista_id);
-- ALTER TABLE asistencia_sesion_comision
--   ADD CONSTRAINT fk_asc_comision
--   FOREIGN KEY (id_comision) REFERENCES comision(id_comision);

-- =========================================================
-- 3. FUNCIÓN: CALCULAR % DE ASISTENCIA A SESIONES PLENARIAS
-- Parámetros: id del asambleísta y rango de fechas
-- =========================================================

CREATE OR REPLACE FUNCTION calcular_porcentaje_asistencia_plenaria(
    p_id_asambleista INT,
    p_fecha_inicio   DATE,
    p_fecha_fin      DATE
)
RETURNS NUMERIC(5,2) AS $$
DECLARE
    v_total_sesiones  INT;
    v_total_presentes INT;
    v_porcentaje      NUMERIC(5,2);
BEGIN
    -- Total de sesiones plenarias en el periodo
    SELECT COUNT(*)
      INTO v_total_sesiones
      FROM sesiones
     WHERE fecha BETWEEN p_fecha_inicio AND p_fecha_fin;

    IF v_total_sesiones = 0 THEN
        RETURN 0.00;
    END IF;

    -- Sesiones donde el asambleísta estuvo Presente
    SELECT COUNT(*)
      INTO v_total_presentes
      FROM asistencia_sesion_plenaria asp
      JOIN sesiones s   ON asp.id_sesion            = s.id_sesion
      JOIN estado_asistencia ea ON asp.id_estado_asistencia = ea.id_estado_asistencia
     WHERE asp.id_asambleista = p_id_asambleista
       AND s.fecha BETWEEN p_fecha_inicio AND p_fecha_fin
       AND ea.nombre = 'Presente';

    v_porcentaje := (v_total_presentes::NUMERIC / v_total_sesiones::NUMERIC) * 100;
    RETURN ROUND(v_porcentaje, 2);
END;
$$ LANGUAGE plpgsql;

-- =========================================================
-- 4. FUNCIÓN: CALCULAR % DE ASISTENCIA A SESIONES DE COMISIÓN
-- =========================================================

CREATE OR REPLACE FUNCTION calcular_porcentaje_asistencia_comision(
    p_id_asambleista INT,
    p_id_comision    INT
)
RETURNS NUMERIC(5,2) AS $$
DECLARE
    v_total_sesiones  INT;
    v_total_presentes INT;
    v_porcentaje      NUMERIC(5,2);
BEGIN
    SELECT COUNT(*)
      INTO v_total_sesiones
      FROM sesion_comision
     WHERE id_comision = p_id_comision;

    IF v_total_sesiones = 0 THEN
        RETURN 0.00;
    END IF;

    SELECT COUNT(*)
      INTO v_total_presentes
      FROM asistencia_sesion_comision asc_t
      JOIN sesion_comision sc ON asc_t.id_sesion_comision = sc.id_sesion_comision
      JOIN estado_asistencia ea ON asc_t.id_estado_asistencia = ea.id_estado_asistencia
     WHERE asc_t.id_asambleista = p_id_asambleista
       AND sc.id_comision = p_id_comision
       AND ea.nombre = 'Presente';

    v_porcentaje := (v_total_presentes::NUMERIC / v_total_sesiones::NUMERIC) * 100;
    RETURN ROUND(v_porcentaje, 2);
END;
$$ LANGUAGE plpgsql;

-- =========================================================
-- 5. FUNCIÓN: RESUMEN COMPLETO DE ASISTENCIA PLENARIA
-- Devuelve tabla con totales y porcentaje para un asambleísta
-- =========================================================

CREATE OR REPLACE FUNCTION resumen_asistencia_plenaria(
    p_id_asambleista INT,
    p_fecha_inicio   DATE,
    p_fecha_fin      DATE
)
RETURNS TABLE (
    id_asambleista      INT,
    total_sesiones      BIGINT,
    total_presentes     BIGINT,
    total_ausentes      BIGINT,
    total_justificados  BIGINT,
    porcentaje_asistencia NUMERIC(5,2)
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p_id_asambleista                                            AS id_asambleista,
        COUNT(s.id_sesion)                                          AS total_sesiones,
        COUNT(*) FILTER (WHERE ea.nombre = 'Presente')              AS total_presentes,
        COUNT(*) FILTER (WHERE ea.nombre = 'Ausente')               AS total_ausentes,
        COUNT(*) FILTER (WHERE ea.nombre = 'Justificado')           AS total_justificados,
        calcular_porcentaje_asistencia_plenaria(
            p_id_asambleista, p_fecha_inicio, p_fecha_fin
        )                                                           AS porcentaje_asistencia
    FROM sesiones s
    LEFT JOIN asistencia_sesion_plenaria asp
           ON s.id_sesion       = asp.id_sesion
          AND asp.id_asambleista = p_id_asambleista
    LEFT JOIN estado_asistencia ea
           ON asp.id_estado_asistencia = ea.id_estado_asistencia
    WHERE s.fecha BETWEEN p_fecha_inicio AND p_fecha_fin;
END;
$$ LANGUAGE plpgsql;

-- =========================================================
-- 6. FUNCIÓN: RESUMEN DE ASISTENCIA A COMISIÓN
-- =========================================================

CREATE OR REPLACE FUNCTION resumen_asistencia_comision(
    p_id_asambleista INT,
    p_id_comision    INT
)
RETURNS TABLE (
    id_asambleista        INT,
    id_comision           INT,
    total_sesiones        BIGINT,
    total_presentes       BIGINT,
    total_ausentes        BIGINT,
    total_justificados    BIGINT,
    porcentaje_asistencia NUMERIC(5,2)
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p_id_asambleista                                        AS id_asambleista,
        p_id_comision                                           AS id_comision,
        COUNT(sc.id_sesion_comision)                            AS total_sesiones,
        COUNT(*) FILTER (WHERE ea.nombre = 'Presente')          AS total_presentes,
        COUNT(*) FILTER (WHERE ea.nombre = 'Ausente')           AS total_ausentes,
        COUNT(*) FILTER (WHERE ea.nombre = 'Justificado')       AS total_justificados,
        calcular_porcentaje_asistencia_comision(
            p_id_asambleista, p_id_comision
        )                                                       AS porcentaje_asistencia
    FROM sesion_comision sc
    LEFT JOIN asistencia_sesion_comision asc_t
           ON sc.id_sesion_comision = asc_t.id_sesion_comision
          AND asc_t.id_asambleista  = p_id_asambleista
    LEFT JOIN estado_asistencia ea
           ON asc_t.id_estado_asistencia = ea.id_estado_asistencia
    WHERE sc.id_comision = p_id_comision;
END;
$$ LANGUAGE plpgsql;

-- =========================================================
-- PRUEBAS (requieren datos de Issue #9 y #11)
-- =========================================================

SELECT calcular_porcentaje_asistencia_plenaria(1, '2026-01-01', '2026-12-31');
SELECT * FROM resumen_asistencia_plenaria(1, '2026-01-01', '2026-12-31');
SELECT * FROM resumen_asistencia_comision(1, 1);
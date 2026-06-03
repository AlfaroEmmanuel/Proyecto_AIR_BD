-- =========================================================
-- Issue #12: Control de Asistencias y Cálculo de Participación
-- =========================================================

-- 1. Catálogo de estados de asistencia
CREATE TABLE IF NOT EXISTS estado_asistencia (
    id_estado_asistencia SERIAL PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL UNIQUE
);

INSERT INTO estado_asistencia (nombre) VALUES
('Presente'),
('Ausente'),
('Justificado')
ON CONFLICT (nombre) DO NOTHING;

-- 2. Asistencia a sesiones plenarias
CREATE TABLE IF NOT EXISTS asistencia_sesion_plenaria (
    id_asistencia SERIAL PRIMARY KEY,
    id_sesion INT NOT NULL REFERENCES sesion(id_sesion) ON DELETE CASCADE,
    cedula_asambleista VARCHAR(30) NOT NULL,
    id_estado_asistencia INT NOT NULL REFERENCES estado_asistencia(id_estado_asistencia),
    observaciones TEXT,
    registrada_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (id_sesion, cedula_asambleista)
);

-- 3. Sesiones de comisión
CREATE TABLE IF NOT EXISTS sesion_comision (
    id_sesion_comision SERIAL PRIMARY KEY,
    id_comision INT,
    fecha DATE NOT NULL,
    tema VARCHAR(255) NOT NULL,
    observaciones TEXT,
    creada_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 4. Asistencia a sesiones de comisión
CREATE TABLE IF NOT EXISTS asistencia_sesion_comision (
    id_asistencia_comision SERIAL PRIMARY KEY,
    id_sesion_comision INT NOT NULL REFERENCES sesion_comision(id_sesion_comision) ON DELETE CASCADE,
    cedula_asambleista VARCHAR(30) NOT NULL,
    id_estado_asistencia INT NOT NULL REFERENCES estado_asistencia(id_estado_asistencia),
    observaciones TEXT,
    registrada_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (id_sesion_comision, cedula_asambleista)
);

-- 5. Función: calcular porcentaje de asistencia plenaria
CREATE OR REPLACE FUNCTION calcular_porcentaje_asistencia_plenaria(
    p_cedula VARCHAR,
    p_fecha_inicio DATE,
    p_fecha_fin DATE
)
RETURNS NUMERIC(5,2) AS $$
DECLARE
    total_sesiones INT;
    total_presentes INT;
    porcentaje NUMERIC(5,2);
BEGIN
    SELECT COUNT(*)
    INTO total_sesiones
    FROM sesion
    WHERE fecha BETWEEN p_fecha_inicio AND p_fecha_fin;

    IF total_sesiones = 0 THEN
        RETURN 0.00;
    END IF;

    SELECT COUNT(*)
    INTO total_presentes
    FROM asistencia_sesion_plenaria asp
    INNER JOIN sesion s
        ON asp.id_sesion = s.id_sesion
    INNER JOIN estado_asistencia ea
        ON asp.id_estado_asistencia = ea.id_estado_asistencia
    WHERE asp.cedula_asambleista = p_cedula
      AND s.fecha BETWEEN p_fecha_inicio AND p_fecha_fin
      AND ea.nombre = 'Presente';

    porcentaje := (total_presentes::NUMERIC / total_sesiones::NUMERIC) * 100;

    RETURN ROUND(porcentaje, 2);
END;
$$ LANGUAGE plpgsql;

-- 6. Función: calcular porcentaje de asistencia en comisión
CREATE OR REPLACE FUNCTION calcular_porcentaje_asistencia_comision(
    p_cedula VARCHAR,
    p_id_comision INT
)
RETURNS NUMERIC(5,2) AS $$
DECLARE
    total_sesiones INT;
    total_presentes INT;
    porcentaje NUMERIC(5,2);
BEGIN
    SELECT COUNT(*)
    INTO total_sesiones
    FROM sesion_comision
    WHERE id_comision = p_id_comision;

    IF total_sesiones = 0 THEN
        RETURN 0.00;
    END IF;

    SELECT COUNT(*)
    INTO total_presentes
    FROM asistencia_sesion_comision ascx
    INNER JOIN sesion_comision sc
        ON ascx.id_sesion_comision = sc.id_sesion_comision
    INNER JOIN estado_asistencia ea
        ON ascx.id_estado_asistencia = ea.id_estado_asistencia
    WHERE ascx.cedula_asambleista = p_cedula
      AND sc.id_comision = p_id_comision
      AND ea.nombre = 'Presente';

    porcentaje := (total_presentes::NUMERIC / total_sesiones::NUMERIC) * 100;

    RETURN ROUND(porcentaje, 2);
END;
$$ LANGUAGE plpgsql;

-- 7. Función auxiliar: resumen de asistencia plenaria
CREATE OR REPLACE FUNCTION resumen_asistencia_plenaria(
    p_cedula VARCHAR,
    p_fecha_inicio DATE,
    p_fecha_fin DATE
)
RETURNS TABLE (
    cedula_asambleista VARCHAR,
    total_sesiones BIGINT,
    total_presentes BIGINT,
    total_ausentes BIGINT,
    total_justificados BIGINT,
    porcentaje_asistencia NUMERIC(5,2)
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p_cedula AS cedula_asambleista,
        COUNT(s.id_sesion) AS total_sesiones,
        COUNT(*) FILTER (WHERE ea.nombre = 'Presente') AS total_presentes,
        COUNT(*) FILTER (WHERE ea.nombre = 'Ausente') AS total_ausentes,
        COUNT(*) FILTER (WHERE ea.nombre = 'Justificado') AS total_justificados,
        calcular_porcentaje_asistencia_plenaria(
            p_cedula,
            p_fecha_inicio,
            p_fecha_fin
        ) AS porcentaje_asistencia
    FROM sesion s
    LEFT JOIN asistencia_sesion_plenaria asp
        ON s.id_sesion = asp.id_sesion
       AND asp.cedula_asambleista = p_cedula
    LEFT JOIN estado_asistencia ea
        ON asp.id_estado_asistencia = ea.id_estado_asistencia
    WHERE s.fecha BETWEEN p_fecha_inicio AND p_fecha_fin;
END;
$$ LANGUAGE plpgsql;


------- Pruebas -----------------------------------------
SELECT calcular_porcentaje_asistencia_plenaria(
    '111111111',
    '2026-01-01',
    '2026-12-31'
);

SELECT * FROM resumen_asistencia_plenaria(
    '111111111',
    '2026-01-01',
    '2026-12-31'
);


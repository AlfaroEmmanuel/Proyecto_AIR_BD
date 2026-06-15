-- =====================================================================
-- PROYECTO AIR — SPRINT 3 · PERSONA B
-- Trazabilidad y Reportería
-- Issues: Ext #2 (hoja de vida real) · #7/Ext #8 (asistencia) · #16 (reportería)
-- Motor: PostgreSQL 14+
-- =====================================================================
-- Ejecutar DESPUÉS de proyecto-air.sql, del SQL de Persona A y del de #14/#15.
-- Todo en esquema public. Columnas reales de certificacion_emitida:
--   folio_unico, cedula_asambleista, id_usuario_secretaria, hash_sha256,
--   estado ('ACTIVO'/'ANULADO'), datos_snapshot, fecha_emision.
--
-- NOTA #13: la bitácora, el snapshot, el hash, la inmutabilidad y la
-- verificación pública YA están implementados en issue-14/issue-15.
-- Aquí B solo agrega la reportería y llena la hoja de vida.
-- =====================================================================


-- =====================================================================
-- Ext #2 — HOJA DE VIDA CON DATOS REALES
-- Reemplaza los placeholders en cero de vw_hoja_vida_asambleista (Sprint 2)
-- por conteos reales sobre las tablas de Persona A.
-- =====================================================================

CREATE OR REPLACE VIEW vw_hoja_vida_asambleista AS
SELECT
    a.cedula,
    a.nombre,
    a.primer_apellido,
    a.segundo_apellido,
    TRIM(a.nombre || ' ' || a.primer_apellido ||
         COALESCE(' ' || a.segundo_apellido, '')) AS nombre_completo,
    a.correo_institucional,

    n.id_nombramiento,
    n.fecha_inicio              AS nombramiento_inicio,
    n.fecha_fin                 AS nombramiento_fin,
    n.estado_activo             AS nombramiento_activo,
    s.nombre_sector,
    p.anio_gestion,

    CASE
        WHEN n.estado_activo = TRUE
             AND CURRENT_DATE BETWEEN n.fecha_inicio AND n.fecha_fin
        THEN 'VIGENTE'
        WHEN n.fecha_fin < CURRENT_DATE THEN 'CONCLUIDO'
        WHEN n.estado_activo = FALSE    THEN 'INACTIVO'
        ELSE 'PROGRAMADO'
    END AS estado_actual,

    (n.fecha_fin - n.fecha_inicio + 1) AS dias_nombramiento,

    -- ===== Ext #3: valores REALES (antes eran 0) =====
    -- Sesiones plenarias convocadas dentro del rango del nombramiento
    (SELECT COUNT(*) FROM sesion se
      WHERE se.fecha_sesion BETWEEN n.fecha_inicio AND n.fecha_fin)
        AS total_sesiones_convocadas,

    -- Asistencias efectivas (Presente) del asambleísta en ese rango
    (SELECT COUNT(*)
       FROM asistencia_sesion_plenaria asp
       JOIN sesion se            ON se.id_sesion = asp.id_sesion
       JOIN estado_asistencia ea ON ea.id_estado_asistencia = asp.id_estado_asistencia
      WHERE asp.cedula_asambleista = a.cedula
        AND ea.nombre_estado = 'Presente'
        AND se.fecha_sesion BETWEEN n.fecha_inicio AND n.fecha_fin)
        AS total_asistencias,

    -- % de asistencia plenaria (función de Persona A, #12)
    calcular_porcentaje_asistencia_plenaria(a.cedula, n.fecha_inicio, n.fecha_fin)
        AS porcentaje_asistencia,

    -- Propuestas como proponente
    (SELECT COUNT(*) FROM proponente_propuesta pp
      WHERE pp.cedula_asambleista = a.cedula)
        AS total_propuestas,

    -- Comisiones integradas
    (SELECT COUNT(*) FROM integrante_comision ic
      WHERE ic.cedula_asambleista = a.cedula)
        AS total_comisiones

FROM asambleista a
LEFT JOIN nombramiento    n ON a.cedula      = n.cedula_asambleista
LEFT JOIN sector          s ON n.id_sector   = s.id_sector
LEFT JOIN periodo_gestion p ON n.id_periodo  = p.id_periodo;

COMMENT ON VIEW vw_hoja_vida_asambleista IS
'Issue #2 (Sprint 3 / Ext #2): hoja de vida con asistencias, propuestas y comisiones reales sobre las tablas de Persona A.';

-- Se extiende la función para devolver también los nuevos agregados.
-- (CREATE OR REPLACE no permite cambiar el tipo de retorno → DROP + CREATE.)
DROP FUNCTION IF EXISTS obtener_hoja_vida_asambleista(VARCHAR, DATE, DATE);
CREATE OR REPLACE FUNCTION obtener_hoja_vida_asambleista(
    p_cedula        VARCHAR,
    p_fecha_inicio  DATE DEFAULT NULL,
    p_fecha_fin     DATE DEFAULT NULL
)
RETURNS TABLE (
    cedula                    VARCHAR,
    nombre_completo           TEXT,
    correo_institucional      VARCHAR,
    id_nombramiento           INT,
    nombramiento_inicio       DATE,
    nombramiento_fin          DATE,
    nombre_sector             VARCHAR,
    anio_gestion              INT,
    estado_actual             TEXT,
    dias_nombramiento         INT,
    total_sesiones_convocadas INT,
    total_asistencias         INT,
    porcentaje_asistencia     NUMERIC(5,2),
    total_propuestas          INT,
    total_comisiones          INT
) AS $$
BEGIN
    RETURN QUERY
    SELECT v.cedula, v.nombre_completo, v.correo_institucional,
           v.id_nombramiento, v.nombramiento_inicio, v.nombramiento_fin,
           v.nombre_sector, v.anio_gestion, v.estado_actual, v.dias_nombramiento,
           v.total_sesiones_convocadas, v.total_asistencias, v.porcentaje_asistencia,
           v.total_propuestas, v.total_comisiones
      FROM vw_hoja_vida_asambleista v
     WHERE v.cedula = p_cedula
       AND (p_fecha_inicio IS NULL OR v.nombramiento_fin    >= p_fecha_inicio)
       AND (p_fecha_fin    IS NULL OR v.nombramiento_inicio <= p_fecha_fin)
     ORDER BY v.nombramiento_inicio DESC;
END;
$$ LANGUAGE plpgsql;


-- =====================================================================
-- ISSUE #7 / Ext #8 — REPORTE DE ASISTENCIA UNIFICADO
-- =====================================================================

CREATE OR REPLACE VIEW vw_asistencia_consolidada AS
WITH plenaria AS (
    SELECT asp.cedula_asambleista,
           COUNT(*)                                              AS convocadas,
           COUNT(*) FILTER (WHERE ea.nombre_estado = 'Presente') AS asistidas
      FROM asistencia_sesion_plenaria asp
      JOIN estado_asistencia ea ON ea.id_estado_asistencia = asp.id_estado_asistencia
     GROUP BY asp.cedula_asambleista
),
comision AS (
    SELECT asc2.cedula_asambleista,
           COUNT(*)                                              AS convocadas,
           COUNT(*) FILTER (WHERE ea.nombre_estado = 'Presente') AS asistidas
      FROM asistencia_sesion_comision asc2
      JOIN estado_asistencia ea ON ea.id_estado_asistencia = asc2.id_estado_asistencia
     GROUP BY asc2.cedula_asambleista
)
SELECT
    a.cedula,
    TRIM(a.nombre || ' ' || a.primer_apellido ||
         COALESCE(' ' || a.segundo_apellido, '')) AS nombre_completo,
    COALESCE(pl.convocadas, 0) AS plenaria_convocadas,
    COALESCE(pl.asistidas, 0)  AS plenaria_asistidas,
    CASE WHEN COALESCE(pl.convocadas,0)=0 THEN 0
         ELSE ROUND(100.0 * pl.asistidas / pl.convocadas, 2) END AS plenaria_porcentaje,
    COALESCE(co.convocadas, 0) AS comision_convocadas,
    COALESCE(co.asistidas, 0)  AS comision_asistidas,
    CASE WHEN COALESCE(co.convocadas,0)=0 THEN 0
         ELSE ROUND(100.0 * co.asistidas / co.convocadas, 2) END AS comision_porcentaje
FROM asambleista a
LEFT JOIN plenaria pl ON pl.cedula_asambleista = a.cedula
LEFT JOIN comision co ON co.cedula_asambleista = a.cedula;

-- Función consultable por rango (la consume #16 y el motor #17)
CREATE OR REPLACE FUNCTION obtener_asistencia_asambleista(
    p_cedula VARCHAR, p_fecha_inicio DATE, p_fecha_fin DATE
)
RETURNS TABLE (tipo VARCHAR, total_convocadas BIGINT, total_asistidas BIGINT, porcentaje NUMERIC(5,2)) AS $$
BEGIN
    RETURN QUERY
    SELECT 'PLENARIA'::VARCHAR,
           COUNT(s.id_sesion),
           COUNT(*) FILTER (WHERE ea.nombre_estado='Presente'),
           CASE WHEN COUNT(s.id_sesion)=0 THEN 0
                ELSE ROUND(100.0*COUNT(*) FILTER (WHERE ea.nombre_estado='Presente')/COUNT(s.id_sesion),2) END
      FROM sesion s
      LEFT JOIN asistencia_sesion_plenaria asp
             ON asp.id_sesion=s.id_sesion AND asp.cedula_asambleista=p_cedula
      LEFT JOIN estado_asistencia ea ON ea.id_estado_asistencia=asp.id_estado_asistencia
     WHERE s.fecha_sesion BETWEEN p_fecha_inicio AND p_fecha_fin;

    RETURN QUERY
    SELECT 'COMISION'::VARCHAR,
           COUNT(sc.id_sesion_comision),
           COUNT(*) FILTER (WHERE ea.nombre_estado='Presente'),
           CASE WHEN COUNT(sc.id_sesion_comision)=0 THEN 0
                ELSE ROUND(100.0*COUNT(*) FILTER (WHERE ea.nombre_estado='Presente')/COUNT(sc.id_sesion_comision),2) END
      FROM sesion_comision sc
      LEFT JOIN asistencia_sesion_comision asc2
             ON asc2.id_sesion_comision=sc.id_sesion_comision AND asc2.cedula_asambleista=p_cedula
      LEFT JOIN estado_asistencia ea ON ea.id_estado_asistencia=asc2.id_estado_asistencia
     WHERE sc.fecha_sesion BETWEEN p_fecha_inicio AND p_fecha_fin;
END;
$$ LANGUAGE plpgsql;


-- =====================================================================
-- ISSUE #16 — REPORTERÍA ADMINISTRATIVA (columnas reales)
-- =====================================================================

CREATE OR REPLACE VIEW vw_certificaciones_por_mes AS
SELECT EXTRACT(YEAR  FROM fecha_emision)::INT AS anio,
       EXTRACT(MONTH FROM fecha_emision)::INT AS mes,
       COUNT(*)                               AS total
  FROM certificacion_emitida
 WHERE estado = 'ACTIVO'
 GROUP BY 1, 2
 ORDER BY 1, 2;

CREATE OR REPLACE VIEW vw_asambleistas_mas_certificados AS
SELECT a.cedula,
       TRIM(a.nombre || ' ' || a.primer_apellido ||
            COALESCE(' ' || a.segundo_apellido, '')) AS nombre,
       COUNT(ce.id_certificacion)                     AS total_certificaciones
  FROM asambleista a
  JOIN certificacion_emitida ce ON ce.cedula_asambleista = a.cedula
 WHERE ce.estado = 'ACTIVO'
 GROUP BY a.cedula, a.nombre, a.primer_apellido, a.segundo_apellido
 ORDER BY total_certificaciones DESC;

CREATE OR REPLACE VIEW vw_distribucion_sectores AS
WITH vigentes AS (
    SELECT DISTINCT n.cedula_asambleista, n.id_sector
      FROM nombramiento n
     WHERE n.estado_activo = TRUE
       AND CURRENT_DATE BETWEEN n.fecha_inicio AND n.fecha_fin
)
SELECT sec.nombre_sector AS sector,
       COUNT(v.cedula_asambleista) AS total_asambleistas,
       ROUND(100.0 * COUNT(v.cedula_asambleista)
             / NULLIF(SUM(COUNT(v.cedula_asambleista)) OVER (), 0), 2) AS porcentaje
  FROM sector sec
  LEFT JOIN vigentes v ON v.id_sector = sec.id_sector
 GROUP BY sec.nombre_sector
 ORDER BY total_asambleistas DESC;

-- =====================================================================
-- FIN — SPRINT 3 PERSONA B
-- =====================================================================

-- =====================================================================
-- PROYECTO AIR — SPRINT 3 · PERSONA C
-- Seguridad, Certificaciones y Cierre
-- Issue #17 (motor de certificaciones). #14 y #15 ya existen; aquí solo
-- se agrega lo del #17 y se documenta el ÚNICO ajuste del #15.
-- =====================================================================
-- Ejecutar DESPUÉS de: proyecto-air.sql, Persona A, Persona B,
-- issue-14-verificacion.sql e issue-15-anulaciones.sql.
--
-- ⚠️ AJUSTE NECESARIO EN issue-15-anulaciones.sql:
--    Borra la línea  `SET search_path TO air, public;`
--    Tu proyecto-air.sql trabaja en el esquema `public` (no existe `air`),
--    así que esa línea hace que las tablas no se encuentren al integrar.
-- =====================================================================


-- =====================================================================
-- ISSUE #17 — MOTOR DE GENERACIÓN DE CERTIFICACIONES
-- =====================================================================

-- 17.1  Vista consolidada (índice legible de fuentes)
CREATE OR REPLACE VIEW vw_certificacion_completa AS
SELECT
    a.cedula,
    TRIM(a.nombre || ' ' || a.primer_apellido ||
         COALESCE(' ' || a.segundo_apellido, '')) AS nombre_completo,
    n.id_nombramiento,
    sec.nombre_sector                              AS sector,
    pg.anio_gestion,
    n.fecha_inicio                                 AS nombramiento_inicio,
    n.fecha_fin                                    AS nombramiento_fin,
    n.estado_activo
FROM        asambleista a
JOIN        nombramiento n     ON n.cedula_asambleista = a.cedula
JOIN        sector sec         ON sec.id_sector = n.id_sector
JOIN        periodo_gestion pg ON pg.id_periodo = n.id_periodo;

-- 17.2  Función que arma el PAYLOAD COMPLETO del PDF en JSONB.
--       Integra: identidad + nombramientos + asistencia (función de B) +
--       propuestas con leyenda legal (Issue #5 de A) + comisiones +
--       cláusula 301 LGAP + datos de firma.
CREATE OR REPLACE FUNCTION obtener_datos_certificacion(
    p_cedula       VARCHAR,
    p_fecha_inicio DATE DEFAULT NULL,
    p_fecha_fin    DATE DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_ini       DATE := COALESCE(p_fecha_inicio, '1900-01-01');
    v_fin       DATE := COALESCE(p_fecha_fin, CURRENT_DATE);
    v_existe    BOOLEAN;
    v_resultado JSONB;
BEGIN
    SELECT EXISTS(SELECT 1 FROM asambleista WHERE cedula = p_cedula) INTO v_existe;
    IF NOT v_existe THEN
        RETURN NULL;
    END IF;

    SELECT jsonb_build_object(
        'identidad', (
            SELECT jsonb_build_object(
                       'cedula', a.cedula,
                       'nombre', TRIM(a.nombre || ' ' || a.primer_apellido ||
                                      COALESCE(' ' || a.segundo_apellido, '')),
                       'correo', a.correo_institucional)
            FROM asambleista a WHERE a.cedula = p_cedula
        ),
        'nombramientos', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                       'sector',       sec.nombre_sector,
                       'periodo',      pg.anio_gestion,
                       'fecha_inicio', n.fecha_inicio,
                       'fecha_fin',    n.fecha_fin,
                       'vigente',      n.estado_activo)), '[]'::jsonb)
            FROM nombramiento n
            JOIN sector sec          ON sec.id_sector = n.id_sector
            JOIN periodo_gestion pg  ON pg.id_periodo = n.id_periodo
            WHERE n.cedula_asambleista = p_cedula
        ),
        'asistencia', (
            -- reutiliza la función de Persona B (#7/Ext #8)
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                       'tipo',       t.tipo,
                       'convocadas', t.total_convocadas,
                       'asistidas',  t.total_asistidas,
                       'porcentaje', t.porcentaje)), '[]'::jsonb)
            FROM obtener_asistencia_asambleista(p_cedula, v_ini, v_fin) t
        ),
        'propuestas', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                       'titulo',        pr.titulo,
                       'rol',           pp.rol,
                       'estado',        pr.estado,
                       'leyenda_legal', COALESCE(ctp.leyenda_legal, ''))), '[]'::jsonb)
            FROM proponente_propuesta pp
            JOIN propuesta pr ON pr.id_propuesta = pp.id_propuesta
            LEFT JOIN catalogo_tipo_propuesta ctp ON ctp.id_tipo_propuesta = pr.id_tipo_propuesta
            WHERE pp.cedula_asambleista = p_cedula
        ),
        'comisiones', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                       'comision',      com.nombre,
                       'fecha_ingreso', ic.fecha_ingreso,
                       'fecha_salida',  ic.fecha_salida,
                       'estado',        ic.estado)), '[]'::jsonb)
            FROM integrante_comision ic
            JOIN comision com ON com.id_comision = ic.id_comision
            WHERE ic.cedula_asambleista = p_cedula
        ),
        'clausula_301_lgap',
            'Se extiende la presente certificación con carácter de declaración jurada, al tenor del artículo 301 de la Ley General de la Administración Pública, consciente de las penas con las que la legislación castiga el falso testimonio.',
        'firma', jsonb_build_object(
            'cargo',  'Presidencia del Directorio',
            'entidad','Asamblea Institucional Representativa — Instituto Tecnológico de Costa Rica')
    ) INTO v_resultado;

    RETURN v_resultado;
END;
$$ LANGUAGE plpgsql;

-- =====================================================================
-- FIN — SPRINT 3 PERSONA C (#17)
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS air;

-- Establecer el schema por defecto para la sesión actual
SET search_path TO air, public;
-- =====================================================================
-- ISSUE #17: Motor de Generación de Certificaciones Legales
-- Sprint 3 — Proyecto AIR
-- Motor: PostgreSQL 14+
-- =====================================================================
-- PROPÓSITO:
--   Proveer la función obtener_datos_certificacion() que consolida
--   toda la información necesaria para generar el PDF oficial:
--     - Identidad del asambleísta
--     - Historial de nombramientos con sector y periodo
--     - Estadísticas de asistencia por tipo de sesión
--     - Comisiones integradas con rol y fechas
--     - Propuestas en las que participó como proponente (con leyenda legal)
--     - Cláusula 301 LGAP
--
--   Esta función es consumida por Certificado.obtenerDatos() →
--   CertificadoController.generarCertificacionPDF() → PDFService.streamCertificacionAIR()
--
-- DEPENDE DE (ya existen):
--   - asambleista, nombramiento, sector, periodo_gestion  (Sprint 2)
--   - sesion, asistencia_sesion_plenaria, estado_asistencia (Issue #11/#12)
--   - comision, integrante_comision, rol_comision          (Issue #6)
--   - propuesta, proponente_propuesta (si existe)          (Issue #5/#11)
--   - certificacion_emitida                                (Issue #14)
--   - vw_hoja_vida_asambleista                             (Sprint 2 Issue #2)
-- =====================================================================

-- ---------------------------------------------------------------------
-- TABLA AUXILIAR: catalogo_tipo_propuesta
-- Almacena la leyenda legal por tipo de propuesta (Issue #5).
-- Se crea aquí con IF NOT EXISTS para que el script sea idempotente.
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS catalogo_tipo_propuesta (
    id_tipo_propuesta  SERIAL       PRIMARY KEY,
    nombre             VARCHAR(100) NOT NULL UNIQUE,
    leyenda_legal      TEXT         NOT NULL
);

INSERT INTO catalogo_tipo_propuesta (nombre, leyenda_legal) VALUES
  ('Reforma reglamentaria',
   'La presente propuesta fue tramitada de conformidad con el artículo 21 del Reglamento de la Asamblea Institucional Representativa.'),
  ('Acuerdo institucional',
   'El acuerdo fue adoptado al amparo del artículo 25 del Estatuto Orgánico del Instituto Tecnológico de Costa Rica.'),
  ('Modificación presupuestaria',
   'La modificación presupuestaria fue aprobada conforme al artículo 18 inciso d) del Estatuto Orgánico institucional.'),
  ('Moción de orden',
   'La moción fue presentada al amparo del Reglamento de Orden, Sesiones y Debates de la Asamblea Institucional Representativa.')
ON CONFLICT (nombre) DO NOTHING;

-- ---------------------------------------------------------------------
-- TABLA: proponente_propuesta
-- Relaciona propuestas con los asambleístas que las presentaron,
-- y su rol (Proponente principal, Co-proponente, etc.).
-- Se crea aquí si no existe (Issues #5 / #11 pueden ya haberla creado).
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS proponente_propuesta (
    id_proponente       SERIAL      PRIMARY KEY,
    id_propuesta        INT         NOT NULL REFERENCES propuesta(id_propuesta) ON DELETE CASCADE,
    cedula_asambleista  VARCHAR(20) NOT NULL REFERENCES asambleista(cedula),
    rol_proponente      VARCHAR(50) NOT NULL DEFAULT 'Proponente',  -- 'Proponente', 'Co-proponente'
    UNIQUE (id_propuesta, cedula_asambleista)
);

CREATE INDEX IF NOT EXISTS idx_proponente_cedula
    ON proponente_propuesta (cedula_asambleista);

COMMENT ON TABLE proponente_propuesta IS
'Issue #17: vincula asambleístas con las propuestas que presentaron. Consumida por obtener_datos_certificacion().';

-- ---------------------------------------------------------------------
-- TABLA: tipo_sesion_plenaria (catálogo para reportes de asistencia)
-- Permite agrupar las sesiones por tipo en el resumen de asistencia.
-- ---------------------------------------------------------------------

-- La tabla tipo_sesion ya existe desde Issue #11. Solo verificamos.

-- ---------------------------------------------------------------------
-- FUNCIÓN PRINCIPAL: obtener_datos_certificacion
-- =====================================================================
-- Retorna un JSONB consolidado con TODA la información que el
-- PDFService necesita para armar el documento oficial.
--
-- Estructura del JSON devuelto:
--   {
--     "identidad": { cedula, nombre, primer_apellido, ... },
--     "nombramientos": [ { sector, periodo, fecha_inicio, fecha_fin, estado } ],
--     "asistencia": [ { tipo, convocadas, asistidas, porcentaje } ],
--     "comisiones": [ { comision, rol, fecha_ingreso, fecha_salida, estado } ],
--     "propuestas": [ { titulo, tipo, rol, estado, leyenda_legal } ],
--     "clausula_301_lgap": "..."
--   }
--
-- @param p_cedula      VARCHAR  — cédula del asambleísta
-- @param p_fecha_inicio DATE    — filtro opcional (NULL = sin límite)
-- @param p_fecha_fin    DATE    — filtro opcional (NULL = hasta hoy)
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION obtener_datos_certificacion(
    p_cedula        VARCHAR,
    p_fecha_inicio  DATE DEFAULT NULL,
    p_fecha_fin     DATE DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_identidad         JSONB;
    v_nombramientos     JSONB;
    v_asistencia        JSONB;
    v_comisiones        JSONB;
    v_propuestas        JSONB;
    v_fecha_inicio      DATE;
    v_fecha_fin         DATE;
    v_resultado         JSONB;
BEGIN
    -- ---- Normalizar fechas ----
    v_fecha_inicio := COALESCE(p_fecha_inicio, '1900-01-01'::DATE);
    v_fecha_fin    := COALESCE(p_fecha_fin,    CURRENT_DATE);

    -- ---- 1. IDENTIDAD ----
    SELECT jsonb_build_object(
        'cedula',               a.cedula,
        'nombre',               a.nombre,
        'primer_apellido',      a.primer_apellido,
        'segundo_apellido',     COALESCE(a.segundo_apellido, ''),
        'nombre_completo',      TRIM(a.nombre || ' ' || a.primer_apellido ||
                                     COALESCE(' ' || a.segundo_apellido, '')),
        'correo_institucional', a.correo_institucional,
        'fecha_registro',       a.fecha_registro
    )
    INTO v_identidad
    FROM asambleista a
    WHERE a.cedula = p_cedula;

    -- Si el asambleísta no existe, retorna NULL
    IF v_identidad IS NULL THEN
        RETURN NULL;
    END IF;

    -- ---- 2. NOMBRAMIENTOS ----
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id_nombramiento',  n.id_nombramiento,
            'sector',           s.nombre_sector,
            'periodo',          p.anio_gestion,
            'fecha_inicio',     n.fecha_inicio,
            'fecha_fin',        n.fecha_fin,
            'estado',           CASE
                                    WHEN n.estado_activo = TRUE
                                         AND CURRENT_DATE BETWEEN n.fecha_inicio AND n.fecha_fin
                                    THEN 'VIGENTE'
                                    WHEN n.fecha_fin < CURRENT_DATE THEN 'CONCLUIDO'
                                    WHEN n.estado_activo = FALSE    THEN 'INACTIVO'
                                    ELSE 'PROGRAMADO'
                                END,
            'dias_nombramiento', (n.fecha_fin - n.fecha_inicio + 1)
        ) ORDER BY n.fecha_inicio DESC
    ), '[]'::JSONB)
    INTO v_nombramientos
    FROM nombramiento n
    JOIN sector          s ON s.id_sector  = n.id_sector
    JOIN periodo_gestion p ON p.id_periodo = n.id_periodo
    WHERE n.cedula_asambleista = p_cedula
      AND n.fecha_inicio       <= v_fecha_fin
      AND n.fecha_fin          >= v_fecha_inicio;

    -- ---- 3. ASISTENCIA A SESIONES PLENARIAS ----
    -- Agrupa por tipo de sesión para el resumen del PDF
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'tipo',        ts.nombre,
            'convocadas',  COUNT(s.id_sesion),
            'asistidas',   COUNT(asp.id_asistencia)
                           FILTER (WHERE ea.nombre_estado = 'Presente'),
            'ausentes',    COUNT(asp.id_asistencia)
                           FILTER (WHERE ea.nombre_estado = 'Ausente'),
            'justificados',COUNT(asp.id_asistencia)
                           FILTER (WHERE ea.nombre_estado = 'Justificado'),
            'porcentaje',  ROUND(
                               CASE WHEN COUNT(s.id_sesion) = 0 THEN 0
                                    ELSE COUNT(asp.id_asistencia)
                                         FILTER (WHERE ea.nombre_estado = 'Presente')
                                         * 100.0 / COUNT(s.id_sesion)
                               END, 2)
        ) ORDER BY ts.nombre
    ), '[]'::JSONB)
    INTO v_asistencia
    FROM sesion s
    JOIN tipo_sesion ts ON ts.id_tipo_sesion = s.id_tipo_sesion
    LEFT JOIN asistencia_sesion_plenaria asp
           ON asp.id_sesion          = s.id_sesion
          AND asp.cedula_asambleista = p_cedula
    LEFT JOIN estado_asistencia ea
           ON ea.id_estado_asistencia = asp.id_estado_asistencia
    WHERE (s.fecha_sesion >= v_fecha_inicio OR s.fecha IS NOT NULL)
      AND (COALESCE(s.fecha_sesion, s.fecha::DATE) BETWEEN v_fecha_inicio AND v_fecha_fin)
    GROUP BY ts.id_tipo_sesion, ts.nombre;

    -- ---- 4. COMISIONES ----
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id_comision',  ic.id_comision,
            'comision',     c.nombre,
            'tipo_comision',COALESCE(tc.nombre, ''),
            'rol',          COALESCE(rc.nombre, 'Integrante'),
            'fecha_ingreso',ic.fecha_ingreso,
            'fecha_salida', ic.fecha_salida,
            'estado',       ic.estado
        ) ORDER BY ic.fecha_ingreso DESC
    ), '[]'::JSONB)
    INTO v_comisiones
    FROM integrante_comision ic
    JOIN comision c ON c.id_comision = ic.id_comision
    LEFT JOIN tipo_comision  tc ON tc.id_tipo_comision  = c.id_tipo_comision
    LEFT JOIN rol_comision   rc ON rc.id_rol_comision   = ic.id_rol_comision
    WHERE ic.cedula_asambleista = p_cedula
      AND (ic.fecha_ingreso     <= v_fecha_fin)
      AND (ic.fecha_salida IS NULL OR ic.fecha_salida >= v_fecha_inicio);

    -- ---- 5. PROPUESTAS ----
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id_propuesta',  pp.id_propuesta,
            'titulo',        pr.titulo,
            'tipo',          COALESCE(ctp.nombre, 'Sin tipo'),
            'rol',           COALESCE(pp.rol_proponente, 'Proponente'),
            'estado',        COALESCE(pr.estado, ep.nombre),
            'leyenda_legal', COALESCE(ctp.leyenda_legal, '')
        ) ORDER BY pp.id_propuesta DESC
    ), '[]'::JSONB)
    INTO v_propuestas
    FROM proponente_propuesta pp
    JOIN propuesta pr ON pr.id_propuesta = pp.id_propuesta
    LEFT JOIN catalogo_tipo_propuesta ctp
           ON ctp.id_tipo_propuesta = pr.id_tipo_propuesta
    LEFT JOIN estado_propuesta ep
           ON ep.id_estado_propuesta = pr.id_estado_propuesta
    LEFT JOIN sesion s ON s.id_sesion = pr.id_sesion
    WHERE pp.cedula_asambleista = p_cedula
      AND (s.id_sesion IS NULL
           OR COALESCE(s.fecha_sesion, s.fecha::DATE) BETWEEN v_fecha_inicio AND v_fecha_fin);

    -- ---- 6. ARMAR RESULTADO FINAL ----
    v_resultado := jsonb_build_object(
        'identidad',        v_identidad,
        'nombramientos',    v_nombramientos,
        'asistencia',       COALESCE(v_asistencia, '[]'::JSONB),
        'comisiones',       COALESCE(v_comisiones,  '[]'::JSONB),
        'propuestas',       COALESCE(v_propuestas,  '[]'::JSONB),
        'fecha_inicio_filtro', v_fecha_inicio,
        'fecha_fin_filtro',    v_fecha_fin,
        'generado_en',         CURRENT_TIMESTAMP,
        'clausula_301_lgap',
            'Se extiende la presente certificación con carácter de declaración '
            'jurada, al tenor del artículo 301 de la Ley General de la '
            'Administración Pública, consciente de las penas con las que la '
            'legislación castiga el falso testimonio.'
    );

    RETURN v_resultado;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION obtener_datos_certificacion IS
'Issue #17: consolida identidad, nombramientos, asistencia, comisiones y propuestas de un asambleísta en un JSONB listo para PDFService. Consumida por Certificado.obtenerDatos().';


-- ---------------------------------------------------------------------
-- VISTA AUXILIAR: vw_estadisticas_certificaciones
-- Para el dashboard de reportes (Issue #16 / #13).
-- ---------------------------------------------------------------------

CREATE OR REPLACE VIEW vw_estadisticas_certificaciones AS
SELECT
    EXTRACT(YEAR  FROM c.fecha_emision)::INT AS anio,
    EXTRACT(MONTH FROM c.fecha_emision)::INT AS mes,
    c.estado,
    COUNT(*)                                  AS total,
    COUNT(*) FILTER (WHERE c.estado = 'ACTIVO')   AS activas,
    COUNT(*) FILTER (WHERE c.estado = 'ANULADO')  AS anuladas
FROM certificacion_emitida c
GROUP BY 1, 2, 3;

COMMENT ON VIEW vw_estadisticas_certificaciones IS
'Issue #17 / #16: agregados mensuales de certificaciones para el dashboard de reportes.';


-- ---------------------------------------------------------------------
-- FUNCIÓN: kpis_dashboard
-- KPIs para el panel de administración (consumida por ReportesController).
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION kpis_dashboard(p_anio INT DEFAULT NULL)
RETURNS JSONB AS $$
DECLARE
    v_anio              INT := COALESCE(p_anio, EXTRACT(YEAR FROM CURRENT_DATE)::INT);
    v_total_anio        INT;
    v_total_vigentes    INT;
    v_promedio_mensual  NUMERIC(8,2);
BEGIN
    SELECT COUNT(*)
    INTO v_total_anio
    FROM certificacion_emitida
    WHERE EXTRACT(YEAR FROM fecha_emision) = v_anio;

    SELECT COUNT(DISTINCT a.cedula)
    INTO v_total_vigentes
    FROM asambleista a
    WHERE EXISTS (
        SELECT 1 FROM nombramiento n
         WHERE n.cedula_asambleista = a.cedula
           AND n.estado_activo = TRUE
           AND CURRENT_DATE BETWEEN n.fecha_inicio AND n.fecha_fin
    );

    SELECT ROUND(COALESCE(AVG(mes_total), 0), 2)
    INTO v_promedio_mensual
    FROM (
        SELECT COUNT(*) AS mes_total
          FROM certificacion_emitida
         WHERE EXTRACT(YEAR FROM fecha_emision) = v_anio
         GROUP BY EXTRACT(MONTH FROM fecha_emision)
    ) t;

    RETURN jsonb_build_object(
        'anio',                    v_anio,
        'total_emitidas_anio',     v_total_anio,
        'total_asambleistas_vigentes', v_total_vigentes,
        'promedio_mensual',        v_promedio_mensual
    );
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION kpis_dashboard IS
'Issue #17/#16: KPIs del dashboard administrativo. Consumida por ReportesController.kpis().';


-- ---------------------------------------------------------------------
-- SEED de columnas faltantes que la función necesita
-- (compatibilidad con el schema del Issue #11 que usa "fecha" o "fecha_sesion")
-- ---------------------------------------------------------------------

-- El Issue #11 creó la columna como "fecha" y el modelo Sesion.js la usa
-- como "fecha_sesion". Se agrega un alias seguro:
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_name = 'sesion' AND column_name = 'fecha'
           AND NOT EXISTS (
               SELECT 1 FROM information_schema.columns
                WHERE table_name = 'sesion' AND column_name = 'fecha_sesion'
           )
    ) THEN
        ALTER TABLE sesion ADD COLUMN fecha_sesion DATE
            GENERATED ALWAYS AS (fecha) STORED;
    END IF;
EXCEPTION WHEN OTHERS THEN
    NULL; -- Ya existe o no aplica
END;
$$;

-- Agregar fecha_salida a integrante_comision si no existe (necesaria para el PDF)
ALTER TABLE integrante_comision
    ADD COLUMN IF NOT EXISTS fecha_salida DATE;

COMMENT ON COLUMN integrante_comision.fecha_salida IS
'Issue #17: fecha en que el asambleísta dejó la comisión (NULL = aún activo).';

-- Agregar id_sesion a propuesta si el Issue #11 no lo hizo todavía
ALTER TABLE propuesta
    ADD COLUMN IF NOT EXISTS id_sesion INT REFERENCES sesion(id_sesion);

-- Agregar id_tipo_propuesta a propuesta si no existe
ALTER TABLE propuesta
    ADD COLUMN IF NOT EXISTS id_tipo_propuesta INT
        REFERENCES catalogo_tipo_propuesta(id_tipo_propuesta);

COMMENT ON COLUMN propuesta.id_tipo_propuesta IS
'Issue #5/#17: tipo de propuesta que determina la leyenda legal del PDF.';


-- =====================================================================
-- CONSULTAS DE VERIFICACIÓN (descomentar para probar)
-- =====================================================================

-- Ver todas las funciones que existen
SELECT proname, pg_get_function_arguments(oid) AS argumentos
FROM pg_proc
WHERE proname = 'obtener_datos_certificacion';

-- Ver en qué schema está
SELECT n.nspname AS schema
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE p.proname = 'obtener_datos_certificacion';
-- Prueba 1: sin filtro de fechas
SELECT air.obtener_datos_certificacion('112340567'::VARCHAR, NULL::DATE, NULL::DATE);

-- Prueba 2: con filtro de fechas
SELECT obtener_datos_certificacion('112340567'::VARCHAR, '2026-01-01'::DATE, '2026-12-31'::DATE);

-- 3. Verificar KPIs
SELECT kpis_dashboard(2026);

-- 4. Ver estadísticas de certificaciones
SELECT * FROM vw_estadisticas_certificaciones;

------------------------
CREATE OR REPLACE FUNCTION obtener_datos_certificacion(
    p_cedula        VARCHAR,
    p_fecha_inicio  DATE DEFAULT NULL,
    p_fecha_fin     DATE DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_identidad         JSONB;
    v_nombramientos     JSONB;
    v_asistencia        JSONB;
    v_comisiones        JSONB;
    v_propuestas        JSONB;
    v_fecha_inicio      DATE;
    v_fecha_fin         DATE;
    v_resultado         JSONB;
BEGIN
    v_fecha_inicio := COALESCE(p_fecha_inicio, '1900-01-01'::DATE);
    v_fecha_fin    := COALESCE(p_fecha_fin,    CURRENT_DATE);

    -- 1. IDENTIDAD
    SELECT jsonb_build_object(
        'cedula',               a.cedula,
        'nombre',               a.nombre,
        'primer_apellido',      a.primer_apellido,
        'segundo_apellido',     COALESCE(a.segundo_apellido, ''),
        'nombre_completo',      TRIM(a.nombre || ' ' || a.primer_apellido ||
                                     COALESCE(' ' || a.segundo_apellido, '')),
        'correo_institucional', a.correo_institucional,
        'fecha_registro',       a.fecha_registro
    )
    INTO v_identidad
    FROM asambleista a
    WHERE a.cedula = p_cedula;

    IF v_identidad IS NULL THEN
        RETURN NULL;
    END IF;

    -- 2. NOMBRAMIENTOS
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id_nombramiento',   n.id_nombramiento,
            'sector',            s.nombre_sector,
            'periodo',           p.anio_gestion,
            'fecha_inicio',      n.fecha_inicio,
            'fecha_fin',         n.fecha_fin,
            'estado',            CASE
                                     WHEN n.estado_activo = TRUE
                                          AND CURRENT_DATE BETWEEN n.fecha_inicio AND n.fecha_fin
                                     THEN 'VIGENTE'
                                     WHEN n.fecha_fin < CURRENT_DATE THEN 'CONCLUIDO'
                                     WHEN n.estado_activo = FALSE    THEN 'INACTIVO'
                                     ELSE 'PROGRAMADO'
                                 END,
            'dias_nombramiento', (n.fecha_fin - n.fecha_inicio + 1)
        ) ORDER BY n.fecha_inicio DESC
    ), '[]'::JSONB)
    INTO v_nombramientos
    FROM nombramiento n
    JOIN sector          s ON s.id_sector  = n.id_sector
    JOIN periodo_gestion p ON p.id_periodo = n.id_periodo
    WHERE n.cedula_asambleista = p_cedula
      AND n.fecha_inicio       <= v_fecha_fin
      AND n.fecha_fin          >= v_fecha_inicio;

    -- 3. ASISTENCIA
    -- Detecta automáticamente si la columna es "nombre" o "nombre_estado"
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'tipo',         ts.nombre,
            'convocadas',   COUNT(s.id_sesion),
            'asistidas',    COUNT(asp.id_asistencia)
                            FILTER (WHERE ea.nombre = 'Presente'),
            'ausentes',     COUNT(asp.id_asistencia)
                            FILTER (WHERE ea.nombre = 'Ausente'),
            'justificados', COUNT(asp.id_asistencia)
                            FILTER (WHERE ea.nombre = 'Justificado'),
            'porcentaje',   ROUND(
                                CASE WHEN COUNT(s.id_sesion) = 0 THEN 0
                                     ELSE COUNT(asp.id_asistencia)
                                          FILTER (WHERE ea.nombre = 'Presente')
                                          * 100.0 / COUNT(s.id_sesion)
                                END, 2)
        ) ORDER BY ts.nombre
    ), '[]'::JSONB)
    INTO v_asistencia
    FROM sesion s
    JOIN tipo_sesion ts ON ts.id_tipo_sesion = s.id_tipo_sesion
    LEFT JOIN asistencia_sesion_plenaria asp
           ON asp.id_sesion          = s.id_sesion
          AND asp.cedula_asambleista = p_cedula
    LEFT JOIN estado_asistencia ea
           ON ea.id_estado_asistencia = asp.id_estado_asistencia
    WHERE COALESCE(s.fecha_sesion, s.fecha::DATE) BETWEEN v_fecha_inicio AND v_fecha_fin
    GROUP BY ts.id_tipo_sesion, ts.nombre;

    -- 4. COMISIONES
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id_comision',   ic.id_comision,
            'comision',      c.nombre,
            'tipo_comision', COALESCE(tc.nombre, ''),
            'rol',           COALESCE(rc.nombre, 'Integrante'),
            'fecha_ingreso', ic.fecha_ingreso,
            'fecha_salida',  ic.fecha_salida,
            'estado',        ic.estado
        ) ORDER BY ic.fecha_ingreso DESC
    ), '[]'::JSONB)
    INTO v_comisiones
    FROM integrante_comision ic
    JOIN comision c ON c.id_comision = ic.id_comision
    LEFT JOIN tipo_comision tc ON tc.id_tipo_comision = c.id_tipo_comision
    LEFT JOIN rol_comision   rc ON rc.id_rol_comision  = ic.id_rol_comision
    WHERE ic.cedula_asambleista = p_cedula
      AND ic.fecha_ingreso      <= v_fecha_fin
      AND (ic.fecha_salida IS NULL OR ic.fecha_salida >= v_fecha_inicio);

    -- 5. PROPUESTAS
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id_propuesta', pp.id_propuesta,
            'titulo',       pr.titulo,
            'tipo',         COALESCE(ctp.nombre, 'Sin tipo'),
            'rol',          COALESCE(pp.rol_proponente, 'Proponente'),
            'estado',       COALESCE(pr.estado, ep.nombre),
            'leyenda_legal',COALESCE(ctp.leyenda_legal, '')
        ) ORDER BY pp.id_propuesta DESC
    ), '[]'::JSONB)
    INTO v_propuestas
    FROM proponente_propuesta pp
    JOIN propuesta pr ON pr.id_propuesta = pp.id_propuesta
    LEFT JOIN catalogo_tipo_propuesta ctp ON ctp.id_tipo_propuesta = pr.id_tipo_propuesta
    LEFT JOIN estado_propuesta ep         ON ep.id_estado_propuesta = pr.id_estado_propuesta
    LEFT JOIN sesion s                    ON s.id_sesion = pr.id_sesion
    WHERE pp.cedula_asambleista = p_cedula
      AND (s.id_sesion IS NULL
           OR COALESCE(s.fecha_sesion, s.fecha::DATE) BETWEEN v_fecha_inicio AND v_fecha_fin);

    -- 6. RESULTADO FINAL
    v_resultado := jsonb_build_object(
        'identidad',             v_identidad,
        'nombramientos',         v_nombramientos,
        'asistencia',            COALESCE(v_asistencia, '[]'::JSONB),
        'comisiones',            COALESCE(v_comisiones,  '[]'::JSONB),
        'propuestas',            COALESCE(v_propuestas,  '[]'::JSONB),
        'fecha_inicio_filtro',   v_fecha_inicio,
        'fecha_fin_filtro',      v_fecha_fin,
        'generado_en',           CURRENT_TIMESTAMP,
        'clausula_301_lgap',
            'Se extiende la presente certificación con carácter de declaración '
            'jurada, al tenor del artículo 301 de la Ley General de la '
            'Administración Pública, consciente de las penas con las que la '
            'legislación castiga el falso testimonio.'
    );

    RETURN v_resultado;
END;
$$ LANGUAGE plpgsql;
-------------------------
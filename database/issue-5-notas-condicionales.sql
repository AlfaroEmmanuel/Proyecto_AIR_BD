-- =========================================================
-- Issue #5 (Proyecto): Motor de Reglas para Notas Condicionales
-- Etapas de Proceso / Origen de Propuesta
--
-- Propósito: Insertar automáticamente notas aclaratorias
-- legales en las certificaciones según el origen y etapa
-- de cada propuesta. Esto resuelve casos como:
--   - Propuestas presentadas por el Consejo Institucional
--   - Propuestas de procedencia por el 10% de asambleístas
--   - Propuestas conciliadas sin registro de asistencia
--
-- DEPENDENCIAS: Issue #11 (sesiones, propuesta, etapa_propuesta)
-- =========================================================

-- =========================================================
-- 1. TABLA: TIPOS DE PROPUESTA (origen del trámite)
-- Cada tipo lleva su leyenda legal para la certificación.
-- =========================================================

CREATE TABLE IF NOT EXISTS tipo_propuesta (
    id_tipo_propuesta SERIAL PRIMARY KEY,
    nombre            VARCHAR(100) NOT NULL UNIQUE,
    -- Texto que se imprime en la certificación cuando aplica esta regla.
    -- Puede contener NULL si no hay nota especial.
    leyenda_certificacion TEXT,
    activo            BOOLEAN NOT NULL DEFAULT TRUE
);

-- Seed: tipos definidos según el documento de referencia
INSERT INTO tipo_propuesta (nombre, leyenda_certificacion) VALUES
(
    'Propuesta Directa',
    NULL  -- Sin nota especial; hay registros completos
),
(
    'Procedencia - Consejo Institucional',
    'La Secretaría de la AIR no dispone de registros de asistencia '
    'para esta propuesta, ya que fue presentada directamente por el '
    'Consejo Institucional en etapa de procedencia.'
),
(
    'Procedencia - 10% Asamblea',
    'La Secretaría de la AIR no dispone de registros de asistencia '
    'individuales para la etapa de procedencia de esta propuesta, '
    'presentada por iniciativa del 10% de los asambleístas.'
),
(
    'Propuesta Conciliada',
    'Esta propuesta surge de la conciliación de iniciativas previas. '
    'Los registros de participación corresponden a la propuesta base '
    'de origen.'
),
(
    'Propuesta de Comisión',
    NULL  -- Tiene registros; la asistencia se certifica desde sesion_comision
)
ON CONFLICT (nombre) DO NOTHING;

-- =========================================================
-- 2. COLUMNA EN PROPUESTA: vincular tipo
-- Se agrega id_tipo_propuesta a la tabla propuesta existente.
-- Ejecutar solo si la columna no existe.
-- =========================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_name = 'propuesta'
           AND column_name = 'id_tipo_propuesta'
    ) THEN
        ALTER TABLE propuesta
          ADD COLUMN id_tipo_propuesta INT
              REFERENCES tipo_propuesta(id_tipo_propuesta);

        -- Por defecto asignar 'Propuesta Directa' (id=1) a las existentes
        UPDATE propuesta SET id_tipo_propuesta = 1
         WHERE id_tipo_propuesta IS NULL;
    END IF;
END;
$$;

-- =========================================================
-- 3. FUNCIÓN: OBTENER NOTA CONDICIONAL DE LA PROPUESTA
-- Devuelve la leyenda legal según el tipo y etapa.
-- El Controlador (Node.js) llama a esta función al generar
-- la certificación para insertar el texto correcto.
-- =========================================================

CREATE OR REPLACE FUNCTION obtener_nota_condicional(
    p_id_propuesta INT
)
RETURNS TEXT AS $$
DECLARE
    v_tipo_nombre    VARCHAR(100);
    v_etapa_nombre   VARCHAR(100);
    v_leyenda        TEXT;
BEGIN
    SELECT
        tp.nombre,
        ep.nombre,
        tp.leyenda_certificacion
    INTO
        v_tipo_nombre,
        v_etapa_nombre,
        v_leyenda
    FROM propuesta p
    JOIN tipo_propuesta   tp ON p.id_tipo_propuesta   = tp.id_tipo_propuesta
    JOIN etapa_propuesta  ep ON p.id_etapa_propuesta  = ep.id_etapa_propuesta
    WHERE p.id_propuesta = p_id_propuesta;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Propuesta % no encontrada', p_id_propuesta;
    END IF;

    -- Regla adicional: si está en etapa Votación/Finalizada Y es de
    -- procedencia por Consejo Institucional, la nota aplica siempre.
    IF v_tipo_nombre IN ('Procedencia - Consejo Institucional',
                         'Procedencia - 10% Asamblea')
       AND v_etapa_nombre IN ('Votación', 'Finalizada') THEN
        -- La nota se mantiene incluso en etapas avanzadas
        RETURN v_leyenda;
    END IF;

    -- Para el resto: devolver la leyenda si existe, NULL si no aplica.
    RETURN v_leyenda;
END;
$$ LANGUAGE plpgsql;

-- =========================================================
-- 4. FUNCIÓN: GENERAR BLOQUE DE TEXTO PARA CERTIFICACIÓN
-- Consolida toda la información de una propuesta en un bloque
-- de texto listo para insertar en el PDF/template.
-- =========================================================

CREATE OR REPLACE FUNCTION generar_bloque_certificacion_propuesta(
    p_id_propuesta   INT,
    p_id_asambleista INT
)
RETURNS TABLE (
    titulo_propuesta     VARCHAR(255),
    codigo_air           VARCHAR(50),
    etapa                VARCHAR(100),
    estado               VARCHAR(50),
    tipo_propuesta       VARCHAR(100),
    nota_condicional     TEXT,
    porcentaje_plenaria  NUMERIC(5,2),
    proponentes          TEXT  -- lista separada por comas
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.titulo,
        p.codigo_air,
        ep.nombre                                              AS etapa,
        esp.nombre                                             AS estado,
        tp.nombre                                             AS tipo_propuesta,
        obtener_nota_condicional(p.id_propuesta)              AS nota_condicional,
        -- Porcentaje plenaria del periodo completo (sin filtro de fechas aquí;
        -- el controlador lo pasa con rango específico si lo necesita)
        NULL::NUMERIC(5,2)                                    AS porcentaje_plenaria,
        -- Lista de proponentes de esta propuesta
        (
            SELECT STRING_AGG(a.nombre, ', ' ORDER BY a.nombre)
            FROM proponente_propuesta pp2
            -- JOIN hacia asambleista cuando Issue #9 esté disponible:
            -- JOIN asambleista a ON pp2.id_asambleista = a.asambleista_id
            -- Por ahora devolvemos el id como texto:
            JOIN (SELECT id_asambleista, CAST(id_asambleista AS VARCHAR) AS nombre
                  FROM proponente_propuesta GROUP BY id_asambleista) a
              ON pp2.id_asambleista = a.id_asambleista
            WHERE pp2.id_propuesta = p.id_propuesta
        )                                                     AS proponentes
    FROM propuesta p
    JOIN etapa_propuesta  ep  ON p.id_etapa_propuesta       = ep.id_etapa_propuesta
    JOIN estado_propuesta esp ON p.id_estado_propuesta      = esp.id_estado_propuesta
    JOIN tipo_propuesta   tp  ON p.id_tipo_propuesta        = tp.id_tipo_propuesta
    WHERE p.id_propuesta = p_id_propuesta;
END;
$$ LANGUAGE plpgsql;

-- =========================================================
-- 5. VISTA: PROPUESTAS_CON_NOTAS
-- Útil para el dashboard y para el motor de certificaciones (Issue #17)
-- =========================================================

CREATE OR REPLACE VIEW v_propuestas_con_notas AS
SELECT
    p.id_propuesta,
    p.titulo,
    p.codigo_air,
    ep.nombre   AS etapa,
    esp.nombre  AS estado,
    tp.nombre   AS tipo_propuesta,
    tp.leyenda_certificacion AS nota_condicional,
    p.creada_en
FROM propuesta p
JOIN etapa_propuesta  ep  ON p.id_etapa_propuesta  = ep.id_etapa_propuesta
JOIN estado_propuesta esp ON p.id_estado_propuesta = esp.id_estado_propuesta
LEFT JOIN tipo_propuesta tp ON p.id_tipo_propuesta = tp.id_tipo_propuesta;

-- =========================================================
-- PRUEBAS
-- =========================================================

-- Ver todos los tipos con sus leyendas
SELECT * FROM tipo_propuesta;

-- Nota para una propuesta específica
SELECT obtener_nota_condicional(1);

-- Vista completa
SELECT * FROM v_propuestas_con_notas;
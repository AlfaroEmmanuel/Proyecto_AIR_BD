-- =====================================================================
-- ISSUE #15: Gestión de Anulaciones y Sustituciones
-- Sprint 3 — Proyecto AIR
-- Motor: PostgreSQL 14+
-- =====================================================================
-- PROPÓSITO:
--   Permite anular un folio emitido con justificación obligatoria
--   y emitir una certificación de sustitución que referencia al original.
--
-- DEPENDE DE (ya existen):
--   - certificacion_emitida  (Issue #14)
--   - sys_usuario            (Sprint 2)
--   - asambleista            (Sprint 2)
-- =====================================================================

-- [CORREGIDO] Se eliminó "SET search_path TO air, public;": el proyecto usa el esquema public.

-- ---------------------------------------------------------------------
-- PASO 1: Agregar columnas que faltan en certificacion_emitida
-- El campo estado ya existe (ACTIVO/ANULADO), solo falta motivo_anulacion
-- y la referencia a la certificación que la sustituye.
-- ---------------------------------------------------------------------

ALTER TABLE certificacion_emitida
    ADD COLUMN IF NOT EXISTS motivo_anulacion    TEXT,
    ADD COLUMN IF NOT EXISTS id_cert_sustituida  INT REFERENCES certificacion_emitida(id_certificacion);

COMMENT ON COLUMN certificacion_emitida.motivo_anulacion IS
'Issue #15: razón obligatoria por la que se anula este folio.';

COMMENT ON COLUMN certificacion_emitida.id_cert_sustituida IS
'Issue #15: si esta certificación sustituye a otra, aquí va el id de la original anulada.';


-- ---------------------------------------------------------------------
-- PASO 2: Tabla anulacion_certificacion
-- Registra el historial de anulaciones con quién, cuándo y por qué.
-- Es inmutable: una vez registrada la anulación no se puede borrar.
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS anulacion_certificacion (
    id_anulacion        SERIAL      PRIMARY KEY,
    id_certificacion    INT         NOT NULL REFERENCES certificacion_emitida(id_certificacion),
    id_usuario_admin    INT         NOT NULL REFERENCES sys_usuario(id_usuario),
    motivo              TEXT        NOT NULL,
    fecha_anulacion     TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    folio_anulado       VARCHAR(30) NOT NULL,   -- Copia del folio para trazabilidad rápida
    folio_sustituto     VARCHAR(30)             -- Folio del documento que lo reemplaza (si aplica)
);

COMMENT ON TABLE anulacion_certificacion IS
'Issue #15: bitácora inmutable de anulaciones. Cada anulación queda registrada con usuario, fecha y motivo.';


-- ---------------------------------------------------------------------
-- PASO 3: Modificar el trigger tg_no_repudio_cert
-- El trigger del Issue #14 bloqueaba TODO update.
-- Ahora debe permitir ÚNICAMENTE el cambio de estado a ANULADO
-- cuando viene acompañado de un motivo. Cualquier otro cambio
-- sigue bloqueado.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_no_repudio_cert()
RETURNS TRIGGER AS $$
BEGIN
    -- Permitir únicamente el cambio de estado ACTIVO → ANULADO con motivo
    IF OLD.estado = 'ACTIVO'
       AND NEW.estado = 'ANULADO'
       AND NEW.motivo_anulacion IS NOT NULL
       AND TRIM(NEW.motivo_anulacion) <> '' THEN
        RETURN NEW;
    END IF;

    -- Bloquear cualquier otro intento de modificación
    RAISE EXCEPTION
        'NO_REPUDIO: El registro de certificación con folio % es inmutable. '
        'Para anularlo use el proceso oficial de anulación (Issue #15).',
        OLD.folio_unico;
END;
$$ LANGUAGE plpgsql;


-- ---------------------------------------------------------------------
-- PASO 4: Función anular_certificacion
-- Ejecuta la anulación en una sola transacción:
--   1. Cambia estado a ANULADO en certificacion_emitida
--   2. Inserta registro en anulacion_certificacion
-- Vive en BD según la recomendación del documento (página 51).
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION anular_certificacion(
    p_folio             VARCHAR,
    p_motivo            TEXT,
    p_id_usuario_admin  INT,
    p_folio_sustituto   VARCHAR DEFAULT NULL
)
RETURNS TABLE (
    ok              BOOLEAN,
    mensaje         TEXT,
    folio_anulado   VARCHAR
) AS $$
DECLARE
    v_id_cert INT;
    v_estado  VARCHAR;
BEGIN
    -- Verificar que el folio existe y está activo
    SELECT id_certificacion, estado
    INTO v_id_cert, v_estado
    FROM certificacion_emitida
    WHERE folio_unico = p_folio;

    IF v_id_cert IS NULL THEN
        RETURN QUERY SELECT FALSE, 'El folio no existe en el sistema.'::TEXT, p_folio;
        RETURN;
    END IF;

    IF v_estado = 'ANULADO' THEN
        RETURN QUERY SELECT FALSE, 'Este folio ya fue anulado anteriormente.'::TEXT, p_folio;
        RETURN;
    END IF;

    IF p_motivo IS NULL OR TRIM(p_motivo) = '' THEN
        RETURN QUERY SELECT FALSE, 'El motivo de anulación es obligatorio.'::TEXT, p_folio;
        RETURN;
    END IF;

    -- Cambiar estado a ANULADO (el trigger ahora lo permite con motivo)
    UPDATE certificacion_emitida
    SET estado           = 'ANULADO',
        motivo_anulacion = p_motivo
    WHERE id_certificacion = v_id_cert;

    -- Registrar en bitácora de anulaciones
    INSERT INTO anulacion_certificacion
        (id_certificacion, id_usuario_admin, motivo, folio_anulado, folio_sustituto)
    VALUES
        (v_id_cert, p_id_usuario_admin, p_motivo, p_folio, p_folio_sustituto);

    RETURN QUERY SELECT TRUE, 'Certificación anulada correctamente.'::TEXT, p_folio;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION anular_certificacion IS
'Issue #15: anula un folio activo con motivo obligatorio y registra en bitácora. Consumida por AnulacionController.anular().';


-- ---------------------------------------------------------------------
-- PASO 5: Función obtener_historial_anulaciones
-- Retorna el historial de anulaciones para auditoría.
-- Accesible solo para rol Administrador.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION obtener_historial_anulaciones(
    p_folio VARCHAR DEFAULT NULL
)
RETURNS TABLE (
    id_anulacion        INT,
    folio_anulado       VARCHAR,
    folio_sustituto     VARCHAR,
    motivo              TEXT,
    fecha_anulacion     TIMESTAMP,
    usuario_admin       VARCHAR,
    nombre_asambleista  TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        an.id_anulacion,
        an.folio_anulado,
        an.folio_sustituto,
        an.motivo,
        an.fecha_anulacion,
        u.username          AS usuario_admin,
        TRIM(a.nombre || ' ' || a.primer_apellido
             || COALESCE(' ' || a.segundo_apellido, '')) AS nombre_asambleista
    FROM anulacion_certificacion an
    JOIN certificacion_emitida c ON c.id_certificacion = an.id_certificacion
    JOIN sys_usuario u           ON u.id_usuario = an.id_usuario_admin
    JOIN asambleista a           ON a.cedula = c.cedula_asambleista
    WHERE (p_folio IS NULL OR an.folio_anulado = p_folio)
    ORDER BY an.fecha_anulacion DESC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION obtener_historial_anulaciones IS
'Issue #15: retorna el historial de anulaciones. Consumida por AnulacionController.historial().';


-- =====================================================================
-- CONSULTAS DE VERIFICACIÓN (descomentar para probar)
-- =====================================================================
/*
-- 1. Anular una certificación
SELECT * FROM anular_certificacion(
    'DAIR-001-2026',
    'Error en el sector de representación del asambleísta.',
    1,
    NULL
);

-- 2. Verificar que quedó como ANULADO
SELECT folio_unico, estado, motivo_anulacion FROM certificacion_emitida
WHERE folio_unico = 'DAIR-001-2026';

-- 3. Ver historial de anulaciones
SELECT * FROM obtener_historial_anulaciones();
SELECT * FROM obtener_historial_anulaciones('DAIR-001-2026');

-- 4. Intentar anular de nuevo (debe fallar)
SELECT * FROM anular_certificacion('DAIR-001-2026', 'Segundo intento', 1, NULL);

-- 5. Intentar modificar directamente (debe lanzar excepción del trigger)
UPDATE certificacion_emitida SET hash_sha256 = 'hackeado' WHERE folio_unico = 'DAIR-001-2026';
*/

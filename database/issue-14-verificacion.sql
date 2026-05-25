-- =====================================================================
-- ISSUE #14: Módulo de Validación de Firmas y Verificación Externa
-- Sprint 3 — Proyecto AIR
-- Motor: PostgreSQL 14+
-- =====================================================================
-- PROPÓSITO:
--   Permite que cualquier tercero (RRHH, otras dependencias del TEC)
--   verifique que una certificación impresa es auténtica y no fue
--   alterada, ingresando su folio en una URL pública del sistema.
--
-- DEPENDE DE (ya existen en proyecto-air.sql):
--   - asambleista
--   - sys_usuario
--   - control_folio + generar_siguiente_folio()
--   - sys_log_auditoria
-- =====================================================================

-- ---------------------------------------------------------------------
-- TABLA: certificacion_emitida
-- Registra cada documento generado con su folio único y su hash SHA-256.
-- Una vez insertado, el trigger tg_no_repudio_cert impide cualquier
-- modificación o borrado (fe pública e inalterabilidad).
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS certificacion_emitida (
    id_certificacion    SERIAL          PRIMARY KEY,
    folio_unico         VARCHAR(30)     NOT NULL UNIQUE,   -- DAIR-001-2026
    cedula_asambleista  VARCHAR(20)     NOT NULL REFERENCES asambleista(cedula),
    id_usuario_secretaria INT           NOT NULL REFERENCES sys_usuario(id_usuario),
    hash_sha256         VARCHAR(64)     NOT NULL,           -- SHA-256 del contenido del PDF
    url_verificacion    TEXT            NOT NULL,           -- Ruta pública para terceros
    fecha_emision       TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    estado              VARCHAR(10)     NOT NULL DEFAULT 'ACTIVO'
                            CHECK (estado IN ('ACTIVO', 'ANULADO')),   -- Issue #15 usará ANULADO
    -- Snapshot JSON del contenido certificado al momento de emisión.
    -- Garantiza que cambios futuros en la BD no alteren lo ya emitido.
    datos_snapshot      JSONB           NOT NULL
);

COMMENT ON TABLE certificacion_emitida IS
'Issue #14 (Sprint 3): registra cada certificación emitida con su folio DAIR, hash SHA-256 y URL de verificación pública. Inmutable por diseño (ver trigger tg_no_repudio_cert).';

COMMENT ON COLUMN certificacion_emitida.hash_sha256 IS
'Hash SHA-256 calculado sobre el contenido textual del documento. Cualquier alteración del PDF invalida este hash.';

COMMENT ON COLUMN certificacion_emitida.url_verificacion IS
'URL pública donde terceros pueden verificar la autenticidad. Ej: https://air.itcr.ac.cr/verificar/DAIR-001-2026';

COMMENT ON COLUMN certificacion_emitida.datos_snapshot IS
'Snapshot del contenido certificado al momento de emisión (JSON). Protege contra alteraciones retroactivas en la BD.';

-- Índice para búsquedas rápidas por cédula (historial de certificaciones)
CREATE INDEX IF NOT EXISTS idx_cert_cedula
    ON certificacion_emitida (cedula_asambleista);

-- Índice para búsquedas por folio (verificación externa)
CREATE INDEX IF NOT EXISTS idx_cert_folio
    ON certificacion_emitida (folio_unico);


-- ---------------------------------------------------------------------
-- FUNCIÓN: generar_hash_verificacion
-- Genera un hash SHA-256 a partir del contenido textual del documento.
-- Según el documento del proyecto (página 51): recibe cuerpo_documento
-- y retorna una cadena SHA-256. Vive en BD para cumplir la recomendación
-- de usar funciones directamente en la base de datos.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION generar_hash_verificacion(p_contenido TEXT)
RETURNS VARCHAR(64) AS $$
BEGIN
    -- pgcrypto: digest retorna BYTEA, encode lo convierte a hex (64 chars)
    RETURN encode(digest(p_contenido, 'sha256'), 'hex');
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION generar_hash_verificacion IS
'Issue #14: genera SHA-256 del contenido del documento. Requiere extensión pgcrypto (CREATE EXTENSION IF NOT EXISTS pgcrypto).';


-- ---------------------------------------------------------------------
-- FUNCIÓN: verificar_certificacion
-- Ruta pública de verificación: recibe el folio, devuelve si el
-- documento es válido y sus metadatos. El controlador la expone en
-- GET /verificar/:folio sin requerir autenticación.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION verificar_certificacion(p_folio VARCHAR)
RETURNS TABLE (
    es_valido           BOOLEAN,
    folio_unico         VARCHAR,
    estado              VARCHAR,
    nombre_asambleista  TEXT,
    cedula              VARCHAR,
    fecha_emision       TIMESTAMP,
    hash_sha256         VARCHAR,
    mensaje             TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        (c.estado = 'ACTIVO')                           AS es_valido,
        c.folio_unico,
        c.estado,
        TRIM(a.nombre || ' ' || a.primer_apellido
             || COALESCE(' ' || a.segundo_apellido, '')) AS nombre_asambleista,
        a.cedula,
        c.fecha_emision,
        c.hash_sha256,
        CASE
            WHEN c.estado = 'ACTIVO'  THEN 'Documento válido y vigente.'
            WHEN c.estado = 'ANULADO' THEN 'Este documento ha sido anulado. Consulte a la Secretaría de la AIR.'
            ELSE 'Estado desconocido.'
        END                                             AS mensaje
    FROM certificacion_emitida c
    JOIN asambleista a ON a.cedula = c.cedula_asambleista
    WHERE c.folio_unico = p_folio;

    -- Si no encontró ninguna fila, devuelve una fila indicando que no existe
    IF NOT FOUND THEN
        RETURN QUERY
        SELECT
            FALSE,
            p_folio,
            'NO_EXISTE'::VARCHAR,
            ''::TEXT,
            ''::VARCHAR,
            NULL::TIMESTAMP,
            ''::VARCHAR,
            'El folio ingresado no existe en el sistema.'::TEXT;
    END IF;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION verificar_certificacion IS
'Issue #14: función pública de verificación. Consumida por CertificadoController.verificar() en GET /verificar/:folio.';


-- ---------------------------------------------------------------------
-- TRIGGER: tg_no_repudio_cert
-- Bloquea cualquier UPDATE o DELETE sobre certificacion_emitida.
-- Garantiza la fe pública e inalterabilidad del folio y el hash.
-- (Según tabla de triggers del documento, página 48)
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_no_repudio_cert()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION
        'NO_REPUDIO: El registro de certificación con folio % es inmutable. '
        'Para invalidarlo use el proceso de anulación (Issue #15).',
        OLD.folio_unico;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tg_no_repudio_cert ON certificacion_emitida;
CREATE TRIGGER tg_no_repudio_cert
    BEFORE UPDATE OR DELETE ON certificacion_emitida
    FOR EACH ROW
    EXECUTE FUNCTION fn_no_repudio_cert();


-- ---------------------------------------------------------------------
-- TRIGGER: tg_auditoria_certificacion
-- Extiende el trigger genérico de auditoría del Sprint 2 a esta tabla.
-- Registra en sys_log_auditoria cada INSERT (emisión) de certificaciones.
-- ---------------------------------------------------------------------

DROP TRIGGER IF EXISTS tg_auditoria_certificacion ON certificacion_emitida;
CREATE TRIGGER tg_auditoria_certificacion
    AFTER INSERT ON certificacion_emitida
    FOR EACH ROW
    EXECUTE FUNCTION fn_registrar_auditoria();


-- ---------------------------------------------------------------------
-- EXTENSIÓN REQUERIDA (ejecutar una sola vez por base de datos)
-- pgcrypto provee la función digest() usada en generar_hash_verificacion
-- ---------------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS pgcrypto;


-- =====================================================================
-- CONSULTAS DE VERIFICACIÓN (descomentar para probar)
-- =====================================================================
/*
-- 1. Verificar que la extensión pgcrypto esté activa
SELECT * FROM pg_extension WHERE extname = 'pgcrypto';

-- 2. Probar la función de hash
SELECT generar_hash_verificacion('Texto de prueba de certificación DAIR-001-2026');

-- 3. Insertar una certificación de prueba
INSERT INTO certificacion_emitida (
    folio_unico, cedula_asambleista, id_usuario_secretaria,
    hash_sha256, url_verificacion, datos_snapshot
) VALUES (
    'DAIR-001-2026',
    '3-0248-0440',
    1,
    generar_hash_verificacion('Ana Rosa Ruiz Fernández | DAIR-001-2026 | 2026-05-24'),
    'https://air.itcr.ac.cr/verificar/DAIR-001-2026',
    '{"nombre": "Ana Rosa Ruiz Fernández", "cedula": "3-0248-0440", "sector": "Oficio - Consejo Institucional"}'::JSONB
);

-- 4. Verificar por folio (función pública)
SELECT * FROM verificar_certificacion('DAIR-001-2026');
SELECT * FROM verificar_certificacion('DAIR-999-2026'); -- No existe

-- 5. Intentar modificar (debe lanzar excepción)
UPDATE certificacion_emitida SET estado = 'ANULADO' WHERE folio_unico = 'DAIR-001-2026';
-- Error esperado: NO_REPUDIO: El registro de certificación con folio DAIR-001-2026 es inmutable.
*/

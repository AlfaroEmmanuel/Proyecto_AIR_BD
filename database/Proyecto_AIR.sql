-- =====================================================================
-- PROYECTO AIR — SCRIPT CONSOLIDADO DE BASE DE DATOS
-- Sistema de Gestión Legislativa - Asamblea Institucional Representativa
-- Instituto Tecnológico de Costa Rica
-- =====================================================================
-- Sprint 2 - Cobertura: Issues #0, #1, #3, #8, #9, #10 (Parte I), #14
-- Motor: PostgreSQL 14+
-- =====================================================================
-- ORDEN DE EJECUCIÓN:
--   1. Tablas de Seguridad (RBAC)
--   2. Catálogos y Tablas de Identidad (Asambleístas)
--   3. Resoluciones y Estructura Normativa Recursiva
--   4. Control de Folios
--   5. Bitácora de Auditoría
--   6. Triggers de Integridad y Versionamiento
--   7. Funciones de Auditoría
--   8. Seed Data (datos iniciales)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. TABLAS DE SEGURIDAD Y RBAC (Issue #0)
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS sys_rol (
    id_rol       SERIAL PRIMARY KEY,
    nombre_rol   VARCHAR(50) NOT NULL UNIQUE,
    descripcion  VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS sys_usuario (
    id_usuario     SERIAL PRIMARY KEY,
    username       VARCHAR(100) NOT NULL UNIQUE,
    password_hash  VARCHAR(255) NOT NULL, -- Almacena hash BCrypt, NUNCA texto plano
    email          VARCHAR(150) UNIQUE,
    activo         BOOLEAN NOT NULL DEFAULT TRUE,
    id_rol         INT NOT NULL REFERENCES sys_rol(id_rol),
    fecha_creacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- 2. CATÁLOGOS DE NEGOCIO
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS sector (
    id_sector     SERIAL PRIMARY KEY,
    nombre_sector VARCHAR(60) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS periodo_gestion (
    id_periodo    SERIAL PRIMARY KEY,
    anio_gestion  INT NOT NULL,
    fecha_inicio  DATE NOT NULL,
    fecha_fin     DATE NOT NULL,
    CONSTRAINT chk_periodo_fechas CHECK (fecha_fin > fecha_inicio),
    CONSTRAINT uk_periodo_anio UNIQUE (anio_gestion)
);

-- ---------------------------------------------------------------------
-- 3. IDENTIDAD Y NOMBRAMIENTOS (Issue #9 / Issue #14)
-- ---------------------------------------------------------------------
-- Nota: La identidad permanente del asambleísta se separa de sus
-- nombramientos temporales para permitir trazabilidad histórica.
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS asambleista (
    cedula                VARCHAR(20) PRIMARY KEY,
    nombre                VARCHAR(100) NOT NULL,
    primer_apellido       VARCHAR(100) NOT NULL,
    segundo_apellido      VARCHAR(100),
    correo_institucional  VARCHAR(150) UNIQUE NOT NULL,
    fecha_registro        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Bitácora histórica de cambios en datos personales (TSE / nacionalizaciones)
CREATE TABLE IF NOT EXISTS bitacora_asambleista (
    id_bitacora           BIGSERIAL PRIMARY KEY,
    cedula_actual         VARCHAR(20) NOT NULL REFERENCES asambleista(cedula),
    cedula_anterior       VARCHAR(20),
    nombre_anterior       VARCHAR(300),
    razon_cambio          VARCHAR(255) NOT NULL,
    fecha_actualizacion   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Nombramientos temporales con rango de fechas (CRÍTICO para Issue #9)
CREATE TABLE IF NOT EXISTS nombramiento (
    id_nombramiento     SERIAL PRIMARY KEY,
    cedula_asambleista  VARCHAR(20) NOT NULL REFERENCES asambleista(cedula) ON DELETE CASCADE,
    id_sector           INT NOT NULL REFERENCES sector(id_sector),
    id_periodo          INT NOT NULL REFERENCES periodo_gestion(id_periodo),
    fecha_inicio        DATE NOT NULL,
    fecha_fin           DATE NOT NULL,
    estado_activo       BOOLEAN NOT NULL DEFAULT TRUE,
    fecha_registro      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_nombramiento_fechas CHECK (fecha_fin > fecha_inicio)
);

CREATE INDEX IF NOT EXISTS idx_nombramiento_cedula
    ON nombramiento (cedula_asambleista);

-- ---------------------------------------------------------------------
-- 4. RESOLUCIONES (cada cambio normativo debe tener una resolución origen)
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS resolucion (
    id_resolucion     SERIAL PRIMARY KEY,
    folio_dair        VARCHAR(30) NOT NULL UNIQUE, -- DAIR-XXX-AÑO
    fecha_aprobacion  DATE NOT NULL,
    descripcion       TEXT NOT NULL
);

-- ---------------------------------------------------------------------
-- 5. JERARQUÍA NORMATIVA RECURSIVA (Issue #10 - Parte I)
-- ---------------------------------------------------------------------
-- Soporta: Reglamento > Título > Capítulo > Artículo > Inciso > Sub-inciso
-- Cada elemento tiene un padre (autoreferencia) y un orden interno.
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS elemento_normativo (
    id_elemento            SERIAL PRIMARY KEY,
    id_padre               INT REFERENCES elemento_normativo(id_elemento) ON DELETE CASCADE,
    tipo                   VARCHAR(20) NOT NULL
                              CHECK (tipo IN ('REGLAMENTO','TITULO','CAPITULO','ARTICULO','INCISO','SUBINCISO')),
    numero                 VARCHAR(10) NOT NULL,
    texto_contenido        TEXT NOT NULL,
    orden                  INT NOT NULL CHECK (orden > 0),
    id_resolucion_origen   INT NOT NULL REFERENCES resolucion(id_resolucion),
    estado                 VARCHAR(15) NOT NULL DEFAULT 'VIGENTE'
                              CHECK (estado IN ('VIGENTE','HISTORICO','DEROGADO')),
    fecha_vigencia_inicio  DATE NOT NULL DEFAULT CURRENT_DATE,
    fecha_vigencia_fin     DATE
);

COMMENT ON TABLE  elemento_normativo IS 'Tabla recursiva para representar la jerarquía normativa: Reglamento > Título > Capítulo > Artículo > Inciso > Sub-inciso.';
COMMENT ON COLUMN elemento_normativo.id_padre IS 'Referencia recursiva al elemento normativo padre.';
COMMENT ON COLUMN elemento_normativo.orden    IS 'Orden del elemento dentro de su padre.';

-- REGLA DE ORO: No pueden existir dos versiones VIGENTES del mismo elemento (Issue #10)
CREATE UNIQUE INDEX IF NOT EXISTS idx_elemento_normativo_vigente
    ON elemento_normativo (COALESCE(id_padre, -1), tipo, numero)
    WHERE estado = 'VIGENTE' AND fecha_vigencia_fin IS NULL;

-- ---------------------------------------------------------------------
-- 6. CONTROL DE FOLIOS (Issue #1)
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS control_folio (
    anio                  INT PRIMARY KEY,
    ultimo_consecutivo    INT NOT NULL DEFAULT 0,
    fecha_actualizacion   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Función ATÓMICA para generar folio DAIR-XXX-AÑO sin colisiones concurrentes
CREATE OR REPLACE FUNCTION generar_siguiente_folio()
RETURNS VARCHAR AS $$
DECLARE
    anio_actual        INT;
    nuevo_consecutivo  INT;
    folio_formateado   VARCHAR(20);
BEGIN
    anio_actual := EXTRACT(YEAR FROM CURRENT_DATE);

    INSERT INTO control_folio (anio, ultimo_consecutivo, fecha_actualizacion)
    VALUES (anio_actual, 1, CURRENT_TIMESTAMP)
    ON CONFLICT (anio)
    DO UPDATE SET
        ultimo_consecutivo  = control_folio.ultimo_consecutivo + 1,
        fecha_actualizacion = CURRENT_TIMESTAMP
    RETURNING ultimo_consecutivo INTO nuevo_consecutivo;

    folio_formateado := 'DAIR-' || LPAD(nuevo_consecutivo::TEXT, 3, '0') || '-' || anio_actual::TEXT;
    RETURN folio_formateado;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- 7. BITÁCORA DE AUDITORÍA (Issue #13 - infraestructura)
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS sys_log_auditoria (
    id_log             BIGSERIAL PRIMARY KEY,
    nombre_tabla       VARCHAR(60) NOT NULL,
    operacion          VARCHAR(10) NOT NULL CHECK (operacion IN ('INSERT','UPDATE','DELETE')),
    usuario_db         VARCHAR(60) NOT NULL DEFAULT CURRENT_USER,
    id_usuario_app     INT,                 -- Usuario de la aplicación (SET LOCAL)
    fecha_hora         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    datos_anteriores   JSONB,
    datos_nuevos       JSONB
);

-- =====================================================================
-- TRIGGERS DE INTEGRIDAD Y VERSIONAMIENTO
-- =====================================================================

-- ---------------------------------------------------------------------
-- TRIGGER 1: Versionamiento normativo (Issue #10)
-- Al insertar un elemento VIGENTE, marca como HISTÓRICO el anterior
-- con la misma combinación (padre, tipo, numero).
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_versionar_elemento_normativo()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.estado = 'VIGENTE' THEN
        UPDATE elemento_normativo
           SET estado             = 'HISTORICO',
               fecha_vigencia_fin = CURRENT_DATE
         WHERE COALESCE(id_padre, -1) = COALESCE(NEW.id_padre, -1)
           AND tipo                   = NEW.tipo
           AND numero                 = NEW.numero
           AND estado                 = 'VIGENTE'
           AND fecha_vigencia_fin     IS NULL
           AND id_elemento            <> COALESCE(NEW.id_elemento, -1);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_versionar_elemento_normativo ON elemento_normativo;
CREATE TRIGGER trg_versionar_elemento_normativo
    BEFORE INSERT ON elemento_normativo
    FOR EACH ROW
    WHEN (NEW.estado = 'VIGENTE')
    EXECUTE FUNCTION fn_versionar_elemento_normativo();

-- ---------------------------------------------------------------------
-- TRIGGER 2: Prevención de traslape de nombramientos (Issue #9)
-- Un asambleísta NO puede tener dos nombramientos cuyos rangos
-- de fechas se traslapen y ambos estén activos.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_validar_traslape_nombramiento()
RETURNS TRIGGER AS $$
DECLARE
    v_conflictos INT;
BEGIN
    IF NEW.estado_activo = TRUE THEN
        SELECT COUNT(*) INTO v_conflictos
          FROM nombramiento
         WHERE cedula_asambleista = NEW.cedula_asambleista
           AND estado_activo      = TRUE
           AND id_nombramiento   <> COALESCE(NEW.id_nombramiento, -1)
           -- traslape real de fechas
           AND fecha_inicio       <= NEW.fecha_fin
           AND fecha_fin          >= NEW.fecha_inicio;

        IF v_conflictos > 0 THEN
            RAISE EXCEPTION
                'TRASLAPE DETECTADO: El asambleísta con cédula % ya tiene un nombramiento activo cuyo rango de fechas se traslapa con (% al %).',
                NEW.cedula_asambleista, NEW.fecha_inicio, NEW.fecha_fin;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validar_traslape_nombramiento ON nombramiento;
CREATE TRIGGER trg_validar_traslape_nombramiento
    BEFORE INSERT OR UPDATE ON nombramiento
    FOR EACH ROW
    EXECUTE FUNCTION fn_validar_traslape_nombramiento();

-- ---------------------------------------------------------------------
-- TRIGGER 3: Validar que la fecha de nombramiento esté dentro del periodo
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_validar_fecha_nombramiento()
RETURNS TRIGGER AS $$
DECLARE
    v_inicio DATE;
    v_fin    DATE;
BEGIN
    SELECT fecha_inicio, fecha_fin
      INTO v_inicio, v_fin
      FROM periodo_gestion
     WHERE id_periodo = NEW.id_periodo;

    IF NEW.fecha_inicio < v_inicio OR NEW.fecha_fin > v_fin THEN
        RAISE EXCEPTION
            'FECHA INVÁLIDA: El nombramiento (% al %) está fuera del rango del periodo de gestión (% al %).',
            NEW.fecha_inicio, NEW.fecha_fin, v_inicio, v_fin;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validar_fecha_nombramiento ON nombramiento;
CREATE TRIGGER trg_validar_fecha_nombramiento
    BEFORE INSERT OR UPDATE ON nombramiento
    FOR EACH ROW
    EXECUTE FUNCTION fn_validar_fecha_nombramiento();

-- ---------------------------------------------------------------------
-- TRIGGER GENÉRICO DE AUDITORÍA (Issue #13 - infraestructura)
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_registrar_auditoria()
RETURNS TRIGGER AS $$
DECLARE
    v_id_app INT;
BEGIN
    -- Captura el usuario de la app si el backend ejecutó SET LOCAL "app.id_usuario"
    BEGIN
        v_id_app := NULLIF(current_setting('app.id_usuario', TRUE), '')::INT;
    EXCEPTION WHEN OTHERS THEN
        v_id_app := NULL;
    END;

    INSERT INTO sys_log_auditoria (
        nombre_tabla, operacion, usuario_db, id_usuario_app,
        fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
        TG_TABLE_NAME, TG_OP, CURRENT_USER, v_id_app,
        CURRENT_TIMESTAMP,
        CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE row_to_json(OLD)::JSONB END,
        CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE row_to_json(NEW)::JSONB END
    );

    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_auditoria_asambleista ON asambleista;
CREATE TRIGGER trg_auditoria_asambleista
    AFTER INSERT OR UPDATE OR DELETE ON asambleista
    FOR EACH ROW EXECUTE FUNCTION fn_registrar_auditoria();

DROP TRIGGER IF EXISTS trg_auditoria_nombramiento ON nombramiento;
CREATE TRIGGER trg_auditoria_nombramiento
    AFTER INSERT OR UPDATE OR DELETE ON nombramiento
    FOR EACH ROW EXECUTE FUNCTION fn_registrar_auditoria();

DROP TRIGGER IF EXISTS trg_auditoria_resolucion ON resolucion;
CREATE TRIGGER trg_auditoria_resolucion
    AFTER INSERT OR UPDATE OR DELETE ON resolucion
    FOR EACH ROW EXECUTE FUNCTION fn_registrar_auditoria();

DROP TRIGGER IF EXISTS trg_auditoria_elemento_normativo ON elemento_normativo;
CREATE TRIGGER trg_auditoria_elemento_normativo
    AFTER INSERT OR UPDATE OR DELETE ON elemento_normativo
    FOR EACH ROW EXECUTE FUNCTION fn_registrar_auditoria();

-- =====================================================================
-- SEED DATA — DATOS INICIALES PARA PRUEBAS
-- =====================================================================

-- Roles (Issue #0)
INSERT INTO sys_rol (nombre_rol, descripcion) VALUES
    ('Administrador','Control total del sistema'),
    ('Secretaria',   'Edición de actas, sesiones, reglamentos y emisión de certificaciones'),
    ('Consulta',     'Solo lectura del compilador y atestados')
ON CONFLICT (nombre_rol) DO NOTHING;

-- Usuarios de prueba (password BCrypt válido — texto plano: "Admin123")
-- Hash generado con BCrypt cost 10. Reemplazar antes de pasar a producción.
INSERT INTO sys_usuario (username, password_hash, email, id_rol) VALUES
    ('admin',      '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'admin@itcr.ac.cr',      1),
    ('secretaria', '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'secretaria@itcr.ac.cr', 2),
    ('consulta',   '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'consulta@itcr.ac.cr',   3)
ON CONFLICT (username) DO NOTHING;

-- Sectores
INSERT INTO sector (nombre_sector) VALUES
    ('Docente'), ('Administrativo'), ('Estudiantil'), ('Oficio - Consejo Institucional')
ON CONFLICT (nombre_sector) DO NOTHING;

-- Periodos de gestión
INSERT INTO periodo_gestion (anio_gestion, fecha_inicio, fecha_fin) VALUES
    (2024, '2024-01-01', '2024-12-31'),
    (2025, '2025-01-01', '2025-12-31'),
    (2026, '2026-01-01', '2026-12-31')
ON CONFLICT (anio_gestion) DO NOTHING;

-- Resolución base
INSERT INTO resolucion (folio_dair, fecha_aprobacion, descripcion) VALUES
    ('DAIR-000-2026', CURRENT_DATE, 'Carga inicial del Estatuto Orgánico institucional.')
ON CONFLICT (folio_dair) DO NOTHING;

-- Asambleístas de prueba
INSERT INTO asambleista (cedula, nombre, primer_apellido, segundo_apellido, correo_institucional) VALUES
    ('3-0248-0440','Ana Rosa','Ruiz',     'Fernández','aruiz@itcr.ac.cr'),
    ('1-0987-0654','Luis',    'Gómez',    'Gutiérrez','lgomez@itcr.ac.cr'),
    ('2-0543-0876','Marta',   'Calderón', 'Ferrey',   'mcalderon@itcr.ac.cr')
ON CONFLICT (cedula) DO NOTHING;

-- Nombramientos de prueba
INSERT INTO nombramiento (cedula_asambleista, id_sector, id_periodo, fecha_inicio, fecha_fin, estado_activo)
SELECT '3-0248-0440', s.id_sector, p.id_periodo, '2026-01-01', '2026-12-31', TRUE
  FROM sector s, periodo_gestion p
 WHERE s.nombre_sector = 'Oficio - Consejo Institucional' AND p.anio_gestion = 2026
 ON CONFLICT DO NOTHING;

INSERT INTO nombramiento (cedula_asambleista, id_sector, id_periodo, fecha_inicio, fecha_fin, estado_activo)
SELECT '1-0987-0654', s.id_sector, p.id_periodo, '2026-01-01', '2026-12-31', TRUE
  FROM sector s, periodo_gestion p
 WHERE s.nombre_sector = 'Docente' AND p.anio_gestion = 2026
 ON CONFLICT DO NOTHING;

-- Carga inicial del Estatuto Orgánico (jerarquía mínima de prueba)
-- TÍTULO I
INSERT INTO elemento_normativo (id_padre, tipo, numero, texto_contenido, orden, id_resolucion_origen, estado)
SELECT NULL, 'TITULO', 'I', 'Título I: Disposiciones generales', 1, r.id_resolucion, 'VIGENTE'
  FROM resolucion r
 WHERE r.folio_dair = 'DAIR-000-2026'
   AND NOT EXISTS (
       SELECT 1 FROM elemento_normativo e
        WHERE e.id_padre IS NULL AND e.tipo = 'TITULO' AND e.numero = 'I' AND e.estado = 'VIGENTE'
   );

-- CAPÍTULO I (hijo del Título I)
INSERT INTO elemento_normativo (id_padre, tipo, numero, texto_contenido, orden, id_resolucion_origen, estado)
SELECT t.id_elemento, 'CAPITULO', 'I', 'Capítulo I: Naturaleza y fines', 1, r.id_resolucion, 'VIGENTE'
  FROM elemento_normativo t
  JOIN resolucion r ON r.folio_dair = 'DAIR-000-2026'
 WHERE t.tipo = 'TITULO' AND t.numero = 'I' AND t.estado = 'VIGENTE'
   AND NOT EXISTS (
       SELECT 1 FROM elemento_normativo e
        WHERE e.id_padre = t.id_elemento AND e.tipo = 'CAPITULO' AND e.numero = 'I' AND e.estado = 'VIGENTE'
   );

-- ARTÍCULO 1 (hijo del Capítulo I)
INSERT INTO elemento_normativo (id_padre, tipo, numero, texto_contenido, orden, id_resolucion_origen, estado)
SELECT c.id_elemento, 'ARTICULO', '1', 'Artículo 1: El Instituto Tecnológico de Costa Rica es una institución nacional autónoma de educación superior universitaria.', 1, r.id_resolucion, 'VIGENTE'
  FROM elemento_normativo c
  JOIN resolucion r ON r.folio_dair = 'DAIR-000-2026'
 WHERE c.tipo = 'CAPITULO' AND c.numero = 'I' AND c.estado = 'VIGENTE'
   AND NOT EXISTS (
       SELECT 1 FROM elemento_normativo e
        WHERE e.id_padre = c.id_elemento AND e.tipo = 'ARTICULO' AND e.numero = '1' AND e.estado = 'VIGENTE'
   );

-- INCISO a (hijo del Artículo 1)
INSERT INTO elemento_normativo (id_padre, tipo, numero, texto_contenido, orden, id_resolucion_origen, estado)
SELECT a.id_elemento, 'INCISO', 'a', 'Inciso a) Formar profesionales en el campo de la tecnología.', 1, r.id_resolucion, 'VIGENTE'
  FROM elemento_normativo a
  JOIN resolucion r ON r.folio_dair = 'DAIR-000-2026'
 WHERE a.tipo = 'ARTICULO' AND a.numero = '1' AND a.estado = 'VIGENTE'
   AND NOT EXISTS (
       SELECT 1 FROM elemento_normativo e
        WHERE e.id_padre = a.id_elemento AND e.tipo = 'INCISO' AND e.numero = 'a' AND e.estado = 'VIGENTE'
   );

-- =====================================================================
-- CONSULTA DE VERIFICACIÓN — ÁRBOL JERÁRQUICO RECURSIVO (CTE)
-- =====================================================================
-- Esta CTE demuestra que la recursividad funciona y se puede usar
-- desde el Modelo (Normativa.js) para armar el árbol completo.
-- =====================================================================
/*
WITH RECURSIVE arbol_normativo AS (
    SELECT id_elemento, id_padre, tipo, numero, texto_contenido,
           estado, orden, 1 AS nivel, numero::TEXT AS ruta
      FROM elemento_normativo
     WHERE id_padre IS NULL AND estado = 'VIGENTE'
    UNION ALL
    SELECT h.id_elemento, h.id_padre, h.tipo, h.numero, h.texto_contenido,
           h.estado, h.orden, p.nivel + 1, p.ruta || ' > ' || h.numero
      FROM elemento_normativo h
      JOIN arbol_normativo p ON h.id_padre = p.id_elemento
     WHERE h.estado = 'VIGENTE'
)
SELECT nivel, ruta, tipo, numero, texto_contenido
  FROM arbol_normativo
 ORDER BY ruta;
*/

-- =====================================================================
-- VISTA DE HOJA DE VIDA DEL ASAMBLEÍSTA (Issue #2 - Parte I)
-- =====================================================================
-- Esta vista consolida la trayectoria del asambleísta a partir de los
-- datos disponibles en el Sprint 2: identidad + todos sus nombramientos
-- históricos con sector y periodo de gestión.
--
-- En el Sprint 3 esta vista se extenderá con:
--   - LEFT JOIN a `asistencia_sesion_plenaria` para % de asistencia
--   - LEFT JOIN a `proponente_propuesta` para propuestas presentadas
--   - LEFT JOIN a `integrante_comision` para comisiones de trabajo
--
-- El Issue #17 (Sprint 3) consumirá esta vista para generar el PDF
-- de certificación oficial.
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

    -- Nombramiento
    n.id_nombramiento,
    n.fecha_inicio              AS nombramiento_inicio,
    n.fecha_fin                 AS nombramiento_fin,
    n.estado_activo             AS nombramiento_activo,
    s.nombre_sector,
    p.anio_gestion,

    -- Estado calculado contra la fecha actual
    CASE
        WHEN n.estado_activo = TRUE
             AND CURRENT_DATE BETWEEN n.fecha_inicio AND n.fecha_fin
        THEN 'VIGENTE'
        WHEN n.fecha_fin < CURRENT_DATE
        THEN 'CONCLUIDO'
        WHEN n.estado_activo = FALSE
        THEN 'INACTIVO'
        ELSE 'PROGRAMADO'
    END AS estado_actual,

    -- Duración del nombramiento en días (útil para % de asistencia en Sprint 3)
    (n.fecha_fin - n.fecha_inicio + 1) AS dias_nombramiento,

    -- Placeholders para Sprint 3
    0::INT  AS total_sesiones_convocadas,  -- TODO Sprint 3: COUNT de asistencia_sesion_plenaria
    0::INT  AS total_asistencias,           -- TODO Sprint 3
    0::NUMERIC(5,2) AS porcentaje_asistencia, -- TODO Sprint 3
    0::INT  AS total_propuestas,            -- TODO Sprint 3: COUNT de proponente_propuesta
    0::INT  AS total_comisiones             -- TODO Sprint 3: COUNT de integrante_comision

FROM asambleista a
LEFT JOIN nombramiento    n ON a.cedula      = n.cedula_asambleista
LEFT JOIN sector          s ON n.id_sector   = s.id_sector
LEFT JOIN periodo_gestion p ON n.id_periodo  = p.id_periodo;

COMMENT ON VIEW vw_hoja_vida_asambleista IS
'Issue #2 (Sprint 2 Parte I): consolida identidad + nombramientos del asambleísta. En Sprint 3 se extenderá con asistencias, propuestas y comisiones para alimentar el motor de certificaciones (Issue #17).';

-- =====================================================================
-- FUNCIÓN DE TRAZABILIDAD: obtener_hoja_vida_asambleista
-- =====================================================================
-- Devuelve la hoja de vida estructurada de un asambleísta filtrada
-- opcionalmente por rango de fechas. La función vive en BD (no en el
-- controlador) según la recomendación del PDF: "Intenten usar la mayor
-- cantidad de ellas que puedan directamente en la BD".
-- =====================================================================

CREATE OR REPLACE FUNCTION obtener_hoja_vida_asambleista(
    p_cedula        VARCHAR,
    p_fecha_inicio  DATE DEFAULT NULL,
    p_fecha_fin     DATE DEFAULT NULL
)
RETURNS TABLE (
    cedula                  VARCHAR,
    nombre_completo         TEXT,
    correo_institucional    VARCHAR,
    id_nombramiento         INT,
    nombramiento_inicio     DATE,
    nombramiento_fin        DATE,
    nombre_sector           VARCHAR,
    anio_gestion            INT,
    estado_actual           TEXT,
    dias_nombramiento       INT
) AS $$
BEGIN
    RETURN QUERY
    SELECT v.cedula,
           v.nombre_completo,
           v.correo_institucional,
           v.id_nombramiento,
           v.nombramiento_inicio,
           v.nombramiento_fin,
           v.nombre_sector,
           v.anio_gestion,
           v.estado_actual,
           v.dias_nombramiento
      FROM vw_hoja_vida_asambleista v
     WHERE v.cedula = p_cedula
       AND (p_fecha_inicio IS NULL OR v.nombramiento_fin    >= p_fecha_inicio)
       AND (p_fecha_fin    IS NULL OR v.nombramiento_inicio <= p_fecha_fin)
     ORDER BY v.nombramiento_inicio DESC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION obtener_hoja_vida_asambleista IS
'Issue #2: devuelve la hoja de vida del asambleísta con filtros opcionales por rango de fechas. Consumida por AsambleistaController.hojaDeVida.';

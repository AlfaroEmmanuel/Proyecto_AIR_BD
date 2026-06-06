-- =====================================================================
-- ISSUE #6: Módulo de Comisiones de Trabajo
-- Sprint 2 — Proyecto AIR
-- Motor: PostgreSQL 14+
-- =====================================================================
-- EJECUTAR ESTE SCRIPT ANTES DE issue-17-motor-certificaciones.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. CATÁLOGOS
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS tipo_comision (
    id_tipo_comision  SERIAL       PRIMARY KEY,
    nombre            VARCHAR(100) NOT NULL UNIQUE
);

INSERT INTO tipo_comision (nombre) VALUES
    ('Permanente'),
    ('Especial'),
    ('Ad Hoc')
ON CONFLICT (nombre) DO NOTHING;

CREATE TABLE IF NOT EXISTS rol_comision (
    id_rol_comision  SERIAL      PRIMARY KEY,
    nombre           VARCHAR(50) NOT NULL UNIQUE
);

INSERT INTO rol_comision (nombre) VALUES
    ('Coordinador'),
    ('Secretario'),
    ('Integrante')
ON CONFLICT (nombre) DO NOTHING;

-- ---------------------------------------------------------------------
-- 2. TABLA PRINCIPAL: comision
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS comision (
    id_comision       SERIAL       PRIMARY KEY,
    nombre            VARCHAR(150) NOT NULL UNIQUE,
    objeto            TEXT,
    id_tipo_comision  INT          REFERENCES tipo_comision(id_tipo_comision),
    fecha_creacion    DATE         NOT NULL DEFAULT CURRENT_DATE,
    activa            BOOLEAN      NOT NULL DEFAULT TRUE
);

COMMENT ON TABLE comision IS
'Issue #6: comisiones de trabajo de la AIR (permanentes, especiales o ad hoc).';

-- ---------------------------------------------------------------------
-- 3. TABLA: integrante_comision  (N:M entre comision y asambleista)
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS integrante_comision (
    id_integrante       SERIAL      PRIMARY KEY,
    id_comision         INT         NOT NULL REFERENCES comision(id_comision) ON DELETE CASCADE,
    cedula_asambleista  VARCHAR(20) NOT NULL REFERENCES asambleista(cedula),
    id_rol_comision     INT         NOT NULL REFERENCES rol_comision(id_rol_comision),
    fecha_ingreso       DATE        NOT NULL DEFAULT CURRENT_DATE,
    fecha_salida        DATE,
    estado              VARCHAR(20) NOT NULL DEFAULT 'Activo'
                            CHECK (estado IN ('Activo', 'Inactivo')),
    UNIQUE (id_comision, cedula_asambleista)
);

CREATE INDEX IF NOT EXISTS idx_integrante_cedula
    ON integrante_comision (cedula_asambleista);

COMMENT ON TABLE integrante_comision IS
'Issue #6: relación N:M entre comisiones y asambleístas con su rol y fechas de participación.';

-- ---------------------------------------------------------------------
-- 4. TRIGGER: evitar rol duplicado activo en la misma comisión
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_validar_rol_unico_comision()
RETURNS TRIGGER AS $$
DECLARE
    v_conflictos INT;
    v_nombre_rol VARCHAR(50);
BEGIN
    SELECT nombre INTO v_nombre_rol
      FROM rol_comision WHERE id_rol_comision = NEW.id_rol_comision;

    IF v_nombre_rol IN ('Coordinador', 'Secretario') THEN
        SELECT COUNT(*) INTO v_conflictos
          FROM integrante_comision
         WHERE id_comision     = NEW.id_comision
           AND id_rol_comision = NEW.id_rol_comision
           AND estado          = 'Activo'
           AND id_integrante  <> COALESCE(NEW.id_integrante, -1);

        IF v_conflictos > 0 THEN
            RAISE EXCEPTION
                'ROL DUPLICADO: La comisión ya tiene un % activo. '
                'Desactive el actual antes de asignar uno nuevo.',
                v_nombre_rol;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_rol_unico_comision ON integrante_comision;
CREATE TRIGGER trg_rol_unico_comision
    BEFORE INSERT OR UPDATE ON integrante_comision
    FOR EACH ROW
    EXECUTE FUNCTION fn_validar_rol_unico_comision();

-- ---------------------------------------------------------------------
-- 5. SEED: comisiones de prueba
-- ---------------------------------------------------------------------

INSERT INTO comision (nombre, objeto, id_tipo_comision) VALUES
    ('Comisión de Estatuto Orgánico',
     'Revisión y actualización del Estatuto Orgánico institucional.',
     (SELECT id_tipo_comision FROM tipo_comision WHERE nombre = 'Permanente')),
    ('Comisión de Presupuesto',
     'Estudio y dictamen de propuestas presupuestarias.',
     (SELECT id_tipo_comision FROM tipo_comision WHERE nombre = 'Permanente')),
    ('Comisión Electoral',
     'Organización y supervisión de procesos electorales internos.',
     (SELECT id_tipo_comision FROM tipo_comision WHERE nombre = 'Especial'))
ON CONFLICT (nombre) DO NOTHING;

-- ---------------------------------------------------------------------
-- 6. SEED: integrantes de prueba
-- Usa EXISTS para verificar que el asambleísta exista antes de insertar.
-- Si la cédula no está en la tabla asambleista, simplemente no inserta.
-- ---------------------------------------------------------------------

INSERT INTO integrante_comision (id_comision, cedula_asambleista, id_rol_comision, fecha_ingreso, estado)
SELECT
    c.id_comision,
    a.cedula,
    (SELECT id_rol_comision FROM rol_comision WHERE nombre = 'Coordinador'),
    '2026-01-15',
    'Activo'
FROM comision c
JOIN asambleista a ON a.cedula = (SELECT cedula FROM asambleista ORDER BY cedula LIMIT 1 OFFSET 0)
WHERE c.nombre = 'Comisión de Estatuto Orgánico'
  AND NOT EXISTS (
      SELECT 1 FROM integrante_comision ic
       WHERE ic.id_comision = c.id_comision
         AND ic.cedula_asambleista = a.cedula
  );

INSERT INTO integrante_comision (id_comision, cedula_asambleista, id_rol_comision, fecha_ingreso, estado)
SELECT
    c.id_comision,
    a.cedula,
    (SELECT id_rol_comision FROM rol_comision WHERE nombre = 'Integrante'),
    '2026-01-15',
    'Activo'
FROM comision c
JOIN asambleista a ON a.cedula = (SELECT cedula FROM asambleista ORDER BY cedula LIMIT 1 OFFSET 1)
WHERE c.nombre = 'Comisión de Estatuto Orgánico'
  AND NOT EXISTS (
      SELECT 1 FROM integrante_comision ic
       WHERE ic.id_comision = c.id_comision
         AND ic.cedula_asambleista = a.cedula
  );

INSERT INTO integrante_comision (id_comision, cedula_asambleista, id_rol_comision, fecha_ingreso, estado)
SELECT
    c.id_comision,
    a.cedula,
    (SELECT id_rol_comision FROM rol_comision WHERE nombre = 'Secretario'),
    '2026-01-15',
    'Activo'
FROM comision c
JOIN asambleista a ON a.cedula = (SELECT cedula FROM asambleista ORDER BY cedula LIMIT 1 OFFSET 2)
WHERE c.nombre = 'Comisión de Presupuesto'
  AND NOT EXISTS (
      SELECT 1 FROM integrante_comision ic
       WHERE ic.id_comision = c.id_comision
         AND ic.cedula_asambleista = a.cedula
  );

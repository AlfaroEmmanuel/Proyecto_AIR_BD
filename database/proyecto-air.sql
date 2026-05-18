-- 1. TABLAS DE SEGURIDAD Y RBAC (Issue #0)
CREATE TABLE sys_rol (
    id_rol SERIAL PRIMARY KEY,
    nombre_rol VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE sys_usuario (
    id_usuario SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    id_rol INT REFERENCES sys_rol(id_rol)
);

-- 2. TABLA PARA CONTROL DE FOLIOS (Issue #1)
CREATE TABLE control_folio (
    anio INT PRIMARY KEY,
    ultimo_consecutivo INT NOT NULL DEFAULT 0
);

-- 3. FUNCIÓN ATÓMICA PARA GENERAR FOLIO DAIR-XXX-AÑO (Issue #1)
CREATE OR REPLACE FUNCTION generar_siguiente_folio() 
RETURNS VARCHAR AS $$
DECLARE
    anio_actual INT;
    nuevo_consecutivo INT;
    folio_formateado VARCHAR(20);
BEGIN
    anio_actual := EXTRACT(YEAR FROM CURRENT_DATE);
    
    -- Insertar el año si no existe, o bloquear la fila para evitar colisiones concurrentes
    INSERT INTO control_folio (anio, ultimo_consecutivo)
    VALUES (anio_actual, 1)
    ON CONFLICT (anio) 
    DO UPDATE SET ultimo_consecutivo = control_folio.ultimo_consecutivo + 1
    RETURNING ultimo_consecutivo INTO nuevo_consecutivo;
    
    -- Formatear como DAIR-XXX-AÑO (ej: DAIR-001-2026)
    folio_formateado := 'DAIR-' || LPAD(nuevo_consecutivo::VARCHAR, 3, '0') || '-' || anio_actual::VARCHAR;
    
    RETURN folio_formateado;
END;
$$ LANGUAGE plpgsql;

-- 4. SEED DATA REAL PARA PRUEBAS (¡Cero nulos para la presentación!)
INSERT INTO sys_rol (nombre_rol) VALUES ('Administrador'), ('Secretaría'), ('Consulta');

-- Contraseñas en texto plano para el MVP funcional (puedes meter hashes luego)
INSERT INTO sys_usuario (username, password_hash, id_rol) VALUES 
('secretaria@tec.ac.cr', 'Secretaria123', 2),
('asambleista@tec.ac.cr', 'Asambleista123', 3);

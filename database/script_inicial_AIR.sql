
-- Tabla de Sectores 
CREATE TABLE sector (
    id_sector SERIAL PRIMARY KEY,
    nombre_sector VARCHAR(50) NOT NULL UNIQUE -- Ej: 'Docente', 'Administrativo', 'Estudiantil', 'Egresado'
);

-- Tabla de Periodos de Gestión 
CREATE TABLE periodo_gestion (
    id_periodo SERIAL PRIMARY KEY,
    anio_gestion INT NOT NULL,
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE NOT NULL,
    CONSTRAINT chk_fechas CHECK (fecha_fin > fecha_inicio)
);




-- Tabla de Asambleístas 
CREATE TABLE asambleista (
    cedula VARCHAR(20) PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    primer_apellido VARCHAR(100) NOT NULL,
    segundo_apellido VARCHAR(100),
    correo_institucional VARCHAR(150) UNIQUE NOT NULL
);

-- Tabla de Nombramientos Temporales 
-- NOTA: Vincula al asambleísta a un sector y a un periodo para evitar "amarrar" el sector a la cédula de por vida.
CREATE TABLE nombramiento (
    id_nombramiento SERIAL PRIMARY KEY,
    cedula_asambleista VARCHAR(20) NOT NULL REFERENCES asambleista(cedula) ON DELETE CASCADE,
    id_sector INT NOT NULL REFERENCES sector(id_sector),
    id_periodo INT NOT NULL REFERENCES periodo_gestion(id_periodo),
    fecha_nombramiento DATE DEFAULT CURRENT_DATE,
    estado_activo BOOLEAN DEFAULT TRUE
);




-- Resoluciones de la AIR 
CREATE TABLE resolucion (
    id_resolucion SERIAL PRIMARY KEY,
    folio_dair VARCHAR(30) UNIQUE NOT NULL, -- Formato estricto: DAIR-XXX-AÑO (Ej: DAIR-105-2026)
    fecha_aprobacion DATE NOT NULL,
    descripcion TEXT NOT NULL
);




-- Estructura recursiva para almacenar Títulos, Capítulos, Artículos e Incisos
CREATE TABLE elemento_normativo (
    id_elemento SERIAL PRIMARY KEY,
    id_padre INT REFERENCES elemento_normativo(id_elemento) ON DELETE CASCADE, -- Relación autoreferenciada (Recursividad)
    tipo VARCHAR(20) NOT NULL CHECK (tipo IN ('TITULO', 'CAPITULO', 'ARTICULO', 'INCISO')),
    numero VARCHAR(10) NOT NULL, -- Ej: 'I', 'II', '1', 'a'
    texto_contenido TEXT NOT NULL,
    id_resolucion_origen INT NOT NULL REFERENCES resolucion(id_resolucion), -- Vinculado a la resolución que lo aprueba
    estado VARCHAR(15) DEFAULT 'VIGENTE' CHECK (estado IN ('VIGENTE', 'HISTORICO', 'DEROGADO')),
    fecha_vigencia_inicio DATE NOT NULL DEFAULT CURRENT_DATE,
    fecha_vigencia_fin DATE -- NULL mientras esté vigente
);



-- Tabla de bitácora para registrar cualquier alteración en el sistema
CREATE TABLE sys_log_auditoria (
    id_log BIGSERIAL PRIMARY KEY,
    nombre_tabla VARCHAR(50) NOT NULL,
    operacion VARCHAR(10) NOT NULL, -- 'INSERT', 'UPDATE', 'DELETE'
    usuario_db VARCHAR(50) DEFAULT CURRENT_USER,
    fecha_hora TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    datos_anteriores JSONB, -- Captura el estado antiguo del registro en JSON
    datos_nuevos JSONB      -- Captura el nuevo estado en JSON
);

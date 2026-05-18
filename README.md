# Proyecto AIR — Sistema de Gestión Legislativa

Sistema de gestión documental y normativa para la **Asamblea Institucional Representativa** del Instituto Tecnológico de Costa Rica (TEC).

> Modernización del proceso de gestión de actas, acuerdos y certificaciones de la Secretaría de la AIR, eliminando la fragmentación de la información y garantizando la trazabilidad legal de cada decisión institucional.

---

## 📋 Tabla de Contenidos

- [Propósito](#-propósito)
- [Stack Tecnológico](#-stack-tecnológico)
- [Estructura del Repositorio](#-estructura-del-repositorio)
- [Instalación y Despliegue Local](#-instalación-y-despliegue-local)
- [Diccionario de Datos](#-diccionario-de-datos)
- [Issues por Sprint](#-issues-por-sprint)
- [Reglas de Git](#-reglas-de-git)
- [Equipo](#-equipo)

---

## 🎯 Propósito

Automatizar la trazabilidad legislativa de la AIR para que cada certificación emitida sea:

- **Veraz**: con información extraída de fuentes estructuradas.
- **Inalterable**: protegida por hashes SHA-256 y folios únicos.
- **Vigente en tiempo real**: reflejando siempre la última versión aprobada de la normativa.

---

## 🛠 Stack Tecnológico

| Capa | Tecnología |
|---|---|
| Base de datos | PostgreSQL 14+ |
| Backend | Node.js 18+ / Express |
| Frontend | HTML5 + JS vanilla (SSR mínimo) |
| Seguridad | BCrypt + RBAC (Roles: Administrador, Secretaría, Consulta) |
| PDF | PDFKit + QRCode |

---

## 📁 Estructura del Repositorio

```
/
├── .gitignore
├── README.md                  ← Este archivo (diccionario de datos)
├── REGLAS_GIT.md              ← Normativa de commits, ramas y penalizaciones
├── proyecto-air.sql           ← Script consolidado (esquema + triggers + seed)
├── package.json
├── app.js                     ← Punto de entrada del servidor Express
│
├── /database                  ← Scripts SQL desglosados (para revisión por módulo)
│   ├── 01_seguridad.sql
│   ├── 02_actores.sql
│   ├── 03_normativa.sql
│   ├── 04_folios_y_certificaciones.sql
│   ├── 05_triggers.sql
│   └── 06_seed.sql
│
├── /docs
│   ├── diccionario-datos.md
│   ├── modelo-logico.pdf
│   └── manual-tecnico.md
│
├── /src
│   ├── /config
│   │   └── db.js              ← Conexión PostgreSQL (Pool)
│   ├── /models                ← CAPA: MODELO (acceso a datos)
│   │   ├── Asambleista.js
│   │   ├── Usuario.js
│   │   ├── Folio.js
│   │   ├── Normativa.js
│   │   └── Certificacion.js
│   ├── /controllers           ← CAPA: CONTROLADOR (reglas de negocio)
│   │   ├── AuthController.js
│   │   ├── AsambleistaController.js
│   │   ├── FolioController.js
│   │   ├── NormativaController.js
│   │   └── CertificacionController.js
│   ├── /routes
│   │   └── api.js
│   ├── /services              ← Utilidades transversales (no son lógica legal)
│   │   ├── CryptoService.js   ← SHA-256
│   │   └── PDFService.js      ← Generación PDF
│   └── /views                 ← CAPA: VISTA (HTML/JS)
│       ├── login.html
│       ├── registro_asambleista.html
│       ├── listado_asambleistas.html
│       ├── hoja_vida.html
│       └── compilador_normativa.html
│
└── /public                    ← Assets estáticos (CSS, imágenes)
```

---

## 🚀 Instalación y Despliegue Local

### Requisitos previos
- Node.js ≥ 18
- PostgreSQL ≥ 14

### 1. Clonar e instalar dependencias

```bash
git clone https://github.com/<usuario>/Proyecto_AIR_BD.git
cd Proyecto_AIR_BD
npm install
```

### 2. Crear la base de datos

```bash
createdb proyecto_air
psql -d proyecto_air -f proyecto-air.sql
```

### 3. Variables de entorno

Crear archivo `.env` en la raíz:

```env
DB_USER=postgres
DB_HOST=localhost
DB_NAME=proyecto_air
DB_PASSWORD=tu_password
DB_PORT=5432
PORT=3000
JWT_SECRET=cambiar_en_produccion
```

### 4. Levantar el servidor

```bash
npm start
```

El servidor queda disponible en `http://localhost:3000`.

### 5. Credenciales de prueba

| Usuario | Contraseña | Rol |
|---|---|---|
| `admin` | `Admin123` | Administrador |
| `secretaria` | `Admin123` | Secretaría |
| `consulta` | `Admin123` | Consulta |

---

## 📚 Diccionario de Datos

### Módulo 1: Seguridad y RBAC (Issue #0)

#### `sys_rol`
| Columna | Tipo | Restricción | Descripción |
|---|---|---|---|
| `id_rol` | SERIAL | PK | Identificador único |
| `nombre_rol` | VARCHAR(50) | NOT NULL, UNIQUE | Administrador / Secretaria / Consulta |
| `descripcion` | VARCHAR(255) | — | Descripción del rol |

#### `sys_usuario`
| Columna | Tipo | Restricción | Descripción |
|---|---|---|---|
| `id_usuario` | SERIAL | PK | Identificador único |
| `username` | VARCHAR(100) | NOT NULL, UNIQUE | Nombre de usuario para login |
| `password_hash` | VARCHAR(255) | NOT NULL | **Hash BCrypt** (jamás texto plano) |
| `email` | VARCHAR(150) | UNIQUE | Correo institucional |
| `activo` | BOOLEAN | NOT NULL DEFAULT TRUE | Soft delete |
| `id_rol` | INT | FK → sys_rol | Rol asignado |
| `fecha_creacion` | TIMESTAMP | DEFAULT CURRENT_TIMESTAMP | Auditoría |

#### `sys_log_auditoria`
| Columna | Tipo | Descripción |
|---|---|---|
| `id_log` | BIGSERIAL PK | — |
| `nombre_tabla` | VARCHAR(60) | Tabla afectada |
| `operacion` | VARCHAR(10) | INSERT / UPDATE / DELETE |
| `usuario_db` | VARCHAR(60) | Usuario de PostgreSQL |
| `id_usuario_app` | INT | Usuario de aplicación (vía SET LOCAL) |
| `fecha_hora` | TIMESTAMP | Instante exacto |
| `datos_anteriores` | JSONB | Snapshot del registro antes del cambio |
| `datos_nuevos` | JSONB | Snapshot del registro después del cambio |

---

### Módulo 2: Identidad y Nombramientos (Issues #9, #14)

#### `asambleista`
| Columna | Tipo | Restricción | Descripción |
|---|---|---|---|
| `cedula` | VARCHAR(20) | PK | Cédula CR (formato `X-XXXX-XXXX`) o doc. extranjero |
| `nombre` | VARCHAR(100) | NOT NULL | Nombre(s) de pila |
| `primer_apellido` | VARCHAR(100) | NOT NULL | — |
| `segundo_apellido` | VARCHAR(100) | NULLABLE | Opcional para extranjeros |
| `correo_institucional` | VARCHAR(150) | NOT NULL, UNIQUE | Correo `@itcr.ac.cr` |
| `fecha_registro` | TIMESTAMP | DEFAULT CURRENT_TIMESTAMP | — |

#### `bitacora_asambleista`
Historial de cambios de cédula/nombre (TSE, nacionalizaciones).

| Columna | Tipo | Descripción |
|---|---|---|
| `id_bitacora` | BIGSERIAL PK | — |
| `cedula_actual` | VARCHAR(20) FK → asambleista | Cédula vigente |
| `cedula_anterior` | VARCHAR(20) | Cédula previa al cambio |
| `nombre_anterior` | VARCHAR(300) | Nombre previo al cambio |
| `razon_cambio` | VARCHAR(255) | Justificación legal |
| `fecha_actualizacion` | TIMESTAMP | — |

#### `sector`
| Columna | Tipo | Descripción |
|---|---|---|
| `id_sector` | SERIAL PK | — |
| `nombre_sector` | VARCHAR(60) UNIQUE | Docente / Administrativo / Estudiantil / Oficio |

#### `periodo_gestion`
| Columna | Tipo | Descripción |
|---|---|---|
| `id_periodo` | SERIAL PK | — |
| `anio_gestion` | INT UNIQUE | Año de gestión |
| `fecha_inicio` | DATE | Inicio del periodo |
| `fecha_fin` | DATE | Fin del periodo (CHECK > inicio) |

#### `nombramiento`
Vincula al asambleísta con su sector y periodo, **con rango de fechas explícito** para soportar la regla de no-traslape.

| Columna | Tipo | Descripción |
|---|---|---|
| `id_nombramiento` | SERIAL PK | — |
| `cedula_asambleista` | VARCHAR(20) FK → asambleista | — |
| `id_sector` | INT FK → sector | — |
| `id_periodo` | INT FK → periodo_gestion | — |
| `fecha_inicio` | DATE NOT NULL | Inicio del nombramiento |
| `fecha_fin` | DATE NOT NULL | Fin del nombramiento |
| `estado_activo` | BOOLEAN DEFAULT TRUE | — |
| `fecha_registro` | TIMESTAMP | — |

**Regla**: ningún asambleísta puede tener dos nombramientos activos cuyos rangos se traslapen (trigger `fn_validar_traslape_nombramiento`).

---

### Módulo 3: Normativa Recursiva (Issue #10 Parte I)

#### `resolucion`
| Columna | Tipo | Descripción |
|---|---|---|
| `id_resolucion` | SERIAL PK | — |
| `folio_dair` | VARCHAR(30) UNIQUE | Formato `DAIR-XXX-AÑO` |
| `fecha_aprobacion` | DATE | — |
| `descripcion` | TEXT | Resumen de la resolución |

#### `elemento_normativo` (recursiva)
| Columna | Tipo | Descripción |
|---|---|---|
| `id_elemento` | SERIAL PK | — |
| `id_padre` | INT FK → elemento_normativo | **Autoreferencia** para jerarquía |
| `tipo` | VARCHAR(20) | REGLAMENTO/TITULO/CAPITULO/ARTICULO/INCISO/SUBINCISO |
| `numero` | VARCHAR(10) | `I`, `II`, `1`, `a`, `i` |
| `texto_contenido` | TEXT | Cuerpo legal |
| `orden` | INT > 0 | Posición dentro del padre |
| `id_resolucion_origen` | INT FK → resolucion | Resolución que aprobó este elemento |
| `estado` | VARCHAR(15) | VIGENTE / HISTORICO / DEROGADO |
| `fecha_vigencia_inicio` | DATE | — |
| `fecha_vigencia_fin` | DATE NULLABLE | NULL mientras esté vigente |

**Regla de Oro (Issue #10)**: índice único parcial garantiza que **no existan dos elementos VIGENTES** con la misma combinación `(id_padre, tipo, numero)`.

---

### Módulo 4: Control de Folios (Issue #1)

#### `control_folio`
| Columna | Tipo | Descripción |
|---|---|---|
| `anio` | INT PK | Año del consecutivo |
| `ultimo_consecutivo` | INT | Último folio emitido |
| `fecha_actualizacion` | TIMESTAMP | Auditoría |

**Función `generar_siguiente_folio()`**: atómica vía `INSERT … ON CONFLICT … DO UPDATE … RETURNING`, garantizando que dos sesiones concurrentes nunca obtienen el mismo folio.

---

## 🗂 Issues por Sprint

### Sprint 2 (Entregable actual — rama `develop`)
- ✅ **#0** Gestión de Seguridad y Roles Institucionales
- ✅ **#1** Lógica de Foliado y Asignación de Consecutivo Legal
- ✅ **#2** Motor de Trazabilidad: Hoja de Vida del Asambleísta (Parte I)
- ✅ **#3** Interfaz de Filtros y Buscador Dinámico
- ✅ **#4** Visualización de Documento y Formateo Formal (PDF)
- ✅ **#8** Reporte de Asistencia Unificado (infraestructura)
- ✅ **#9** Catálogo de Asambleístas y Nombramientos
- ✅ **#10 (Parte I)** Estructura Recursiva del Reglamento
- ✅ **#14** Validación de Firmas y Verificación Externa (QR base)

### Sprint 3 (rama `main` al cierre)
- #5, #6, #7, #11, #12, #13, #15, #16, #17 — más extensión de #2 y #8 con asistencias/propuestas/comisiones

---

## 📐 Reglas de Git

Ver [REGLAS_GIT.md](./REGLAS_GIT.md).

Resumen:
- Sprint 2 → rama `develop` · Sprint 3 → rama `main`.
- Commits: `db(modulo): …`, `feat(modulo): …`, `fix(modulo): …`.
- Todo PR debe incluir `Closes #N`.

---

## 👥 Equipo

Curso de Bases de Datos — Escuela de Administración de Tecnologías de Información, ITCR.

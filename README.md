# Proyecto AIR — Sistema de Gestión Legislativa

Sistema de gestión documental y normativa para la **Asamblea Institucional Representativa** del Instituto Tecnológico de Costa Rica (TEC).

> Modernización del proceso de gestión de actas, acuerdos y certificaciones de la Secretaría de la AIR, eliminando la fragmentación de la información y garantizando la trazabilidad legal de cada decisión institucional.

**Estado:** Sprint 2 + **Sprint 3 completo** (sesiones, votaciones, asistencias, comisiones, reportería, certificaciones con verificación, anulación y motor de PDF).

---

## 🎯 Propósito

Automatizar la trazabilidad legislativa de la AIR para que cada certificación emitida sea:

- **Veraz**: con información extraída de fuentes estructuradas (asistencias, propuestas, comisiones reales).
- **Inalterable**: protegida por hashes SHA-256, folios únicos y snapshot inmutable.
- **Verificable**: por terceros mediante código QR y página pública de validación.

---

## 🛠 Stack Tecnológico

| Capa | Tecnología |
|---|---|
| Base de datos | PostgreSQL 14+ (extensión `pgcrypto`) |
| Backend | Node.js 18+ / Express |
| Frontend | HTML5 + JS vanilla (SSR mínimo) + Chart.js (CDN) |
| Seguridad | BCrypt + JWT + RBAC (Administrador, Secretaria, Consulta) |
| PDF | PDFKit + QRCode |

---

## 📁 Estructura del Repositorio (Sprint 3)

```
/
├── app.js                      ← Servidor Express (sirve vistas + /verificar público)
├── package.json
│
├── database/                   ← Scripts SQL (ejecutar EN ORDEN)
│   ├── 01_proyecto-air.sql            (base Sprint 2)
│   ├── 02_sprint3_persona_a.sql       (#11 #12 #5 #6)
│   ├── 03_issue-14-verificacion.sql   (#14 — crea certificacion_emitida, pgcrypto)
│   ├── 04_issue-15-anulaciones.sql    (#15)
│   ├── 05_sprint3_persona_b.sql       (#2 ext, #7, #8, #16)
│   ├── 06_sprint3_persona_c.sql       (#17 motor)
│   └── 07_seed_demo_sprint3.sql       (datos de prueba — opcional)
│
├── docs/
│   ├── diccionario-datos.md           (actualizado a Sprint 3)
│   └── ISSUES_SPRINT_2.md
│
└── src/
    ├── config/db.js                   ← Pool PostgreSQL (module.exports = pool)
    ├── models/                        ← Asambleista, Usuario, Folio, Normativa,
    │                                     Sesion, Propuesta, Votacion, Asistencia,
    │                                     Comision, Reporte, Certificado, Anulacion
    ├── controllers/                   ← Auth, Asambleista, Folio, Sesion, Propuesta,
    │                                     Asistencia, Comision, Reportes,
    │                                     Certificado, Anulacion
    ├── routes/api.js                  ← Todas las rutas REST
    ├── services/                      ← CryptoService, PDFService, CSVService
    └── views/                         ← login, inicio, registro/listado/hoja_vida,
                                          sesion_control, comisiones_listado/detalle,
                                          reportes_dashboard, certificacion_emitir,
                                          certificaciones_historial,
                                          validar_certificacion, anular_certificacion
```

---

## 🚀 Instalación y Despliegue Local

### Requisitos
- Node.js ≥ 18 · PostgreSQL ≥ 14

### 1. Instalar dependencias
```bash
npm install
```

### 2. Crear la base de datos y correr los scripts EN ORDEN
```bash
createdb proyecto_air
psql -d proyecto_air -f database/01_proyecto-air.sql
psql -d proyecto_air -f database/02_sprint3_persona_a.sql
psql -d proyecto_air -f database/03_issue-14-verificacion.sql
psql -d proyecto_air -f database/04_issue-15-anulaciones.sql
psql -d proyecto_air -f database/05_sprint3_persona_b.sql
psql -d proyecto_air -f database/06_sprint3_persona_c.sql
psql -d proyecto_air -f database/07_seed_demo_sprint3.sql   # opcional
```
> El orden importa: B y #17 dependen de las tablas de A y de `certificacion_emitida` (#14).

### 3. Variables de entorno (`.env`)
```env
DB_USER=postgres
DB_HOST=localhost
DB_NAME=proyecto_air
DB_PASSWORD=tu_password
DB_PORT=5432
PORT=3000
JWT_SECRET=cambiar_en_produccion
APP_URL=http://localhost:3000
```

### 4. Levantar el servidor
```bash
npm start
```
Disponible en `http://localhost:3000`. Tras el login, el menú está en `/inicio.html`.

### 5. Credenciales de prueba
| Usuario | Contraseña | Rol |
|---|---|---|
| `admin` | `Admin123` | Administrador |
| `secretaria` | `Admin123` | Secretaría |
| `consulta` | `Admin123` | Consulta |

---

## 🗂 Issues por Sprint

### Sprint 2 (rama `develop`) — ✅
#0 Seguridad/RBAC · #1 Foliado · #2 Hoja de vida (Parte I) · #3 Buscador ·
#4 PDF formal · #8 Infraestructura de asistencia · #9 Catálogo de asambleístas ·
#10 Normativa recursiva · #14 Verificación (base QR/hash).

### Sprint 3 (rama `main`) — ✅
- **#5** Leyendas legales por tipo de propuesta (`catalogo_tipo_propuesta`).
- **#6** Comisiones e integrantes (con rol único por trigger).
- **#7 / #8** Reporte de asistencia consolidado (plenaria + comisión).
- **#11** Sesiones, propuestas y votaciones (con validación de quórum y resolución automática).
- **#12** Pase de lista masivo y cálculo de % de participación.
- **#13** Bitácora, snapshot, hash e inmutabilidad de certificaciones.
- **#15** Anulación y sustitución de certificaciones (solo Administrador).
- **#16** Reportería administrativa + exportación CSV + dashboard.
- **#17** Motor de generación del PDF de certificación (datos reales + QR + hash).
- **Ext #2** Hoja de vida con asistencias, propuestas y comisiones reales.

---

## 🔌 Endpoints principales (Sprint 3)

```
# Sesiones / votaciones (#11)
GET/POST /api/sesiones · GET /api/sesiones/:id · POST /api/sesiones/:id/votacion
POST /api/propuestas · GET /api/propuestas/:id/leyenda            (#5)

# Asistencias (#12)
GET /api/asistencias/padron-vigente
POST /api/asistencias/sesion/:id_sesion
GET /api/asistencias/asambleista/:cedula[/porcentaje]

# Comisiones (#6)
GET /api/comisiones · GET /api/comisiones/:id · POST /api/comisiones
POST /api/comisiones/:id/integrantes

# Reportería (#7, #8, #16)
GET /api/reportes/asistencia/:cedula
GET /api/reportes/kpis · /certificaciones-mensuales · /asambleistas-mas-certificados
GET /api/reportes/distribucion-sectores · /certificaciones-historial   ( [?formato=csv] )

# Certificaciones (#14, #15, #17)
POST /api/certificacion/generar                         (#17 — PDF inline)
POST /api/certificaciones/emitir
GET  /api/certificaciones/verificar/:folio              (PÚBLICA)
POST /api/certificaciones/verificar/hash                (PÚBLICA)
GET  /api/certificaciones/historial/:cedula
POST /api/anulaciones/anular · /sustituir               (solo Administrador)
GET  /api/anulaciones/historial[/:folio] · /estado/:folio

# Página pública del QR (en app.js, sin auth)
GET /verificar/:folio   ·   GET /validar/:folio
```

---

## 🖥 Pantallas (vistas)

`inicio.html` (menú por rol) · `sesion_control.html` (pase de lista + votaciones) ·
`comisiones_listado.html` / `comision_detalle.html` · `reportes_dashboard.html` ·
`certificacion_emitir.html` (emite y previsualiza el PDF) ·
`certificaciones_historial.html` · `validar_certificacion.html` (verificación pública) ·
`anular_certificacion.html`.

---

## 📚 Diccionario de Datos

Ver [docs/diccionario-datos.md](./docs/diccionario-datos.md) — actualizado con todas las tablas, vistas, funciones y triggers del Sprint 3.

---

## 📐 Reglas de Git

Ver [REGLAS_GIT.md](./REGLAS_GIT.md). Resumen: Sprint 3 → rama `main`;
commits `db(...)`/`feat(...)`/`fix(...)`; toda PR con `Closes #N`.

---

## 👥 Equipo

Curso de Bases de Datos — Escuela de Administración de Tecnologías de Información, ITCR.

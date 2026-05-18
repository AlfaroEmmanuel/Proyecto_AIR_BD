# Issues del Sprint 2 — listos para copiar a GitHub

> **Cómo usar este archivo:** cada bloque `## Issue #N — Título` corresponde a un Issue de GitHub. Copia desde `## Issue #N` hasta el siguiente `---` y pégalo. El primer renglón con `# ...` no se copia, solo el título y el cuerpo. Recuerda asignar `Labels`, `Milestone: Sprint 2` y `Assignee`.

---

## Issue #0 — Gestión de Seguridad y Roles Institucionales

### 🎯 Contexto
Es el prerequisito de todo el sistema. La plataforma maneja **fe pública** y datos sensibles de asambleístas, por lo que cada acción de escritura debe quedar vinculada a un usuario con permisos específicos.

### ✅ Criterios de Aceptación
- [ ] El sistema impide el acceso a cualquier ruta interna si el usuario no está autenticado.
- [ ] Existen 3 roles funcionando en la BD y en el backend:
  - `Administrador` — control total
  - `Secretaria` — gestión de asambleístas, sesiones, reglamentos y certificaciones
  - `Consulta` — solo lectura
- [ ] Las contraseñas se almacenan con **BCrypt** (cost ≥ 10). El campo `password_hash` no contiene texto plano.
- [ ] El login emite un **JWT** con `id_usuario` y `rol`. El token expira en 8h.
- [ ] Cada endpoint protegido valida el JWT vía middleware (`requireAuth`).
- [ ] Endpoints sensibles validan el rol (`requireRole('Secretaria','Administrador')`).
- [ ] Existe una bitácora `sys_log_auditoria` que registra cada INSERT/UPDATE/DELETE en tablas sensibles con snapshot JSONB del antes/después.

### 🛠 Tareas Técnicas
- [ ] BD: tablas `sys_rol`, `sys_usuario`, `sys_log_auditoria`.
- [ ] BD: función `fn_registrar_auditoria()` genérica y triggers AFTER en `asambleista`, `nombramiento`, `resolucion`, `elemento_normativo`.
- [ ] Backend: `src/models/Usuario.js` con `encontrarPorCredenciales()` usando `bcrypt.compare`.
- [ ] Backend: `src/controllers/AuthController.js` con `login`, `requireAuth`, `requireRole`.
- [ ] Backend: el seed inserta los 3 roles y al menos un usuario por rol con hash BCrypt válido.

### 📂 Archivos involucrados
`proyecto-air.sql` · `src/models/Usuario.js` · `src/controllers/AuthController.js` · `src/routes/api.js` · `src/views/login.html`

### 🏷 Labels
`security` · `backend` · `infrastructure` · `Sprint 2`

---

## Issue #1 — Implementación de Lógica de Foliado y Asignación de Consecutivo Legal

### 🎯 Contexto
El sistema debe asignar consecutivos únicos a las certificaciones con formato **`DAIR-XXX-AÑO`** (ej. `DAIR-009-2025`). Si dos secretarias procesan certificaciones al mismo tiempo, **no puede haber colisiones ni saltos**.

### ✅ Criterios de Aceptación
- [ ] El folio sigue el formato exacto: `DAIR-` + 3 dígitos con ceros a la izquierda + `-` + año fiscal.
- [ ] La consulta del último número y su incremento ocurren en **una única transacción atómica**.
- [ ] Dos invocaciones concurrentes a `generar_siguiente_folio()` retornan números distintos.
- [ ] El contador se reinicia automáticamente al cambiar de año.
- [ ] El folio queda persistido en la tabla `control_folio` con `fecha_actualizacion`.
- [ ] Existe un endpoint protegido `GET /api/folio/nuevo` que sólo Secretaría/Administrador pueden invocar.

### 🛠 Tareas Técnicas
- [ ] BD: tabla `control_folio (anio PK, ultimo_consecutivo, fecha_actualizacion)`.
- [ ] BD: función `generar_siguiente_folio()` usando `INSERT … ON CONFLICT … DO UPDATE … RETURNING`.
- [ ] Backend: `src/models/Folio.js` con `generarSiguiente()`.
- [ ] Backend: `src/controllers/FolioController.js` con `obtenerSiguiente`.
- [ ] Pruebas: validar que invocaciones repetidas devuelven `DAIR-001-AÑO`, `DAIR-002-AÑO`, etc.

### 🏷 Labels
`backend` · `database` · `legal-requirement` · `high-priority` · `Sprint 2`

---

## Issue #2 — Motor de Trazabilidad: Hoja de Vida del Asambleísta (Parte I)

### 🎯 Contexto
La certificación final del Sprint 3 (Issue #17) necesita consumir una **vista consolidada** de la trayectoria del asambleísta. En el Sprint 2 se entrega la **Parte I**: una vista SQL + función PL/pgSQL + endpoint REST que devuelve la identidad y todos los nombramientos históricos del asambleísta, listos para ser extendidos con asistencias, propuestas y comisiones en el Sprint 3.

> **Importante**: este Issue **no inventa tablas que no existen todavía** (asistencias, propuestas, comisiones llegan en Sprint 3). Se construye sobre las tablas reales del Sprint 2 (`asambleista`, `nombramiento`, `sector`, `periodo_gestion`) y deja los placeholders documentados.

### ✅ Criterios de Aceptación
- [ ] Existe la vista `vw_hoja_vida_asambleista` que une `asambleista + nombramiento + sector + periodo_gestion`.
- [ ] La vista calcula dinámicamente el `estado_actual` de cada nombramiento contra `CURRENT_DATE`: `VIGENTE` / `CONCLUIDO` / `INACTIVO` / `PROGRAMADO`.
- [ ] La vista calcula la `dias_nombramiento` como `(fecha_fin - fecha_inicio + 1)` — insumo para el % de asistencia del Sprint 3.
- [ ] La vista incluye columnas placeholder (`total_sesiones_convocadas`, `total_asistencias`, `porcentaje_asistencia`, `total_propuestas`, `total_comisiones`) con valor `0` y comentario `TODO Sprint 3`.
- [ ] Existe la función `obtener_hoja_vida_asambleista(cedula, fecha_inicio?, fecha_fin?)` que filtra por rango.
- [ ] Si se envía sólo una de las dos fechas, el backend devuelve `400 Bad Request`.
- [ ] El endpoint `GET /api/asambleistas/:cedula/hoja-vida` está protegido por rol `Secretaria`/`Administrador` (es insumo de certificación con fe pública).
- [ ] La respuesta agrupa: un objeto raíz con identidad + un array de `nombramientos`.
- [ ] La vista web `hoja_vida.html` permite consultar por cédula con filtros de fecha opcionales y muestra un badge por estado.
- [ ] El listado de asambleístas (Issue #3) tiene un link "Ver hoja de vida →" en cada fila.
- [ ] La vista muestra una nota visible al pie indicando qué se sumará en Sprint 3.

### 🛠 Tareas Técnicas
- [ ] BD: `CREATE OR REPLACE VIEW vw_hoja_vida_asambleista` con todos los campos descritos.
- [ ] BD: `CREATE OR REPLACE FUNCTION obtener_hoja_vida_asambleista(...)` en PL/pgSQL.
- [ ] Backend: `Asambleista.hojaDeVida(cedula, fi, ff)` consume la función SQL (no embebe el SELECT).
- [ ] Backend: `AsambleistaController.hojaDeVida` valida fechas y orquesta.
- [ ] Backend: ruta `GET /api/asambleistas/:cedula/hoja-vida` con middleware RBAC.
- [ ] Vista: `src/views/hoja_vida.html` con filtros, badges por estado, manejo de error 401.
- [ ] Vista: link en `listado_asambleistas.html` que pasa la cédula por query string.
- [ ] Diccionario de datos: documentar la vista y la función.

### 📂 Archivos involucrados
`proyecto-air.sql` · `src/models/Asambleista.js` · `src/controllers/AsambleistaController.js` · `src/routes/api.js` · `src/views/hoja_vida.html` · `src/views/listado_asambleistas.html` · `docs/diccionario-datos.md`

### 🔗 Issues relacionados
- Depende de: #9 (catálogo de asambleístas y nombramientos)
- Habilita: #17 (Sprint 3 — motor de certificaciones)
- Extiende en Sprint 3: #8 (asistencias), #11 (comisiones), #12 (asistencias plenarias)

### 🏷 Labels
`backend` · `database` · `view` · `legal-requirement` · `Sprint 2`

---

## Issue #3 — Interfaz de Filtros y Buscador Dinámico

### 🎯 Contexto
Pantalla de configuración donde la Secretaría selecciona un asambleísta y, opcionalmente, un rango de fechas. Es la primera pantalla del flujo de generación de certificaciones.

### ✅ Criterios de Aceptación
- [ ] Existe un campo de búsqueda por cédula y otro por nombre/apellido.
- [ ] Los filtros por rango de fechas (`fecha_inicio`/`fecha_fin`) devuelven solo nombramientos cuyo rango se cruza con el filtro.
- [ ] El buscador valida que `fecha_fin > fecha_inicio` antes de enviar la petición.
- [ ] El frontend muestra para cada resultado: nombre completo, sector vigente, fechas del nombramiento y un badge VIGENTE/INACTIVO calculado contra `CURRENT_DATE`.
- [ ] La pantalla redirige a login si el JWT expiró o no existe.

### 🛠 Tareas Técnicas
- [ ] Backend: endpoint `GET /api/asambleistas/buscar?cedula=…&nombre=…&fecha_inicio=…&fecha_fin=…`.
- [ ] Backend: `Asambleista.buscarConHistorial()` con WHERE dinámico parametrizado (sin concatenación de strings — anti SQL injection).
- [ ] Vista: `src/views/listado_asambleistas.html` con buscador funcional y envío del header `Authorization: Bearer <token>`.
- [ ] Vista: agrupación por cédula cuando un asambleísta tiene múltiples nombramientos en el resultado.

### 🏷 Labels
`frontend` · `backend` · `Sprint 2`

---

## Issue #4 — Visualización de Documento y Formateo Formal (PDF / Previsualización)

### 🎯 Contexto
Transformar los datos del asambleísta en un PDF oficial que respete la sobriedad del formato AIR. El documento debe incluir todas las cláusulas legales obligatorias.

### ✅ Criterios de Aceptación
- [ ] El PDF generado incluye los siguientes bloques en orden:
  1. Encabezado institucional (TEC + AIR + CONSTANCIA)
  2. Folio único `DAIR-XXX-AAAA`
  3. Acreditación de identidad (nombre + cédula)
  4. Cuerpo de la representación / nombramiento
  5. **Cláusula del art. 301 LGAP** (declaración jurada)
  6. Firma del Presidente del Directorio
  7. Folio + Hash SHA-256 + Código QR de verificación
- [ ] El QR enlaza a `https://sistema-air.tec.ac.cr/validar/<folio>`.
- [ ] El motor está en `src/services/PDFService.js` (utilidad transversal — fuera del controlador).
- [ ] El controlador (`CertificacionController`) sólo orquesta: pide folio → calcula hash → llama al servicio.
- [ ] El PDF se entrega `inline` para previsualización antes de descargar.

### 🛠 Tareas Técnicas
- [ ] `npm install pdfkit qrcode`.
- [ ] `src/services/PDFService.js` con `streamCertificacionAIR(res, datos)`.
- [ ] `src/services/CryptoService.js` con `sha256(contenido)`.
- [ ] `src/controllers/CertificacionController.js` con `generarCertificacionPDF`.
- [ ] Endpoint `POST /api/certificacion/generar` protegido por rol Secretaría/Administrador.

### 🏷 Labels
`frontend` · `legal-compliance` · `reporting` · `Sprint 2`

---

## Issue #8 — Reporte de Asistencia Unificado (Infraestructura)

### 🎯 Contexto
Aunque el cálculo final de % de asistencias se cierra en el Sprint 3, en el Sprint 2 se debe dejar la **infraestructura de datos** (tablas y bitácora) que permitirá agregar `COUNT/SUM` sobre asistencias en el siguiente sprint.

### ✅ Criterios de Aceptación
- [ ] El modelo de datos contempla nombramientos con `fecha_inicio`/`fecha_fin` para poder asociar asistencias por periodo.
- [ ] El esquema reserva los nombres de tablas que llegarán en Sprint 3: `sesiones`, `asistencia_sesion_plenaria`, `asistencia_sesion_comision` (al menos como `TODO` documentado en el diccionario de datos).
- [ ] El README documenta la fórmula esperada: `% participación = asistencias / sesiones convocadas * 100`.

### 🛠 Tareas Técnicas
- [ ] Validar que `nombramiento` tiene rango de fechas explícito.
- [ ] Documentar en `README.md` el contrato de la futura agregación.

### 🏷 Labels
`database` · `logic` · `documentation` · `Sprint 2`

---

## Issue #9 — Gestión de Catálogo de Asambleístas y Nombramientos

### 🎯 Contexto
El sistema debe separar la **identidad permanente** del asambleísta (cédula, nombre, correo) de sus **nombramientos temporales** (sector + periodo + rango de fechas), permitiendo conservar la trazabilidad histórica.

> Si un docente cambia al sector estudiantil o renuncia, el histórico anterior **no se debe sobrescribir**.

### ✅ Criterios de Aceptación
- [ ] Tabla `asambleista` con `cedula` como PK, sin atributo `sector` (el sector vive en `nombramiento`).
- [ ] Tabla `nombramiento` con:
  - `cedula_asambleista` FK
  - `id_sector` FK
  - `id_periodo` FK
  - `fecha_inicio` y `fecha_fin` NOT NULL
  - `estado_activo` BOOLEAN
  - CHECK `fecha_fin > fecha_inicio`
- [ ] El sistema permite registrar múltiples nombramientos para una misma cédula a lo largo del tiempo.
- [ ] **Trigger `fn_validar_traslape_nombramiento`** impide insertar dos nombramientos activos cuyos rangos se traslapen:
  ```
  NEW.fecha_inicio <= existente.fecha_fin
  AND NEW.fecha_fin >= existente.fecha_inicio
  ```
- [ ] **Trigger `fn_validar_fecha_nombramiento`** valida que el rango del nombramiento esté dentro del rango del `periodo_gestion`.
- [ ] El formulario de registro valida cédula formato CR (`X-XXXX-XXXX`) y correo institucional.
- [ ] Existe una `bitacora_asambleista` para registrar cambios de cédula/nombre por nacionalización o resolución TSE.

### 🛠 Tareas Técnicas
- [ ] BD: tablas `asambleista`, `nombramiento`, `bitacora_asambleista`, `sector`, `periodo_gestion`.
- [ ] BD: triggers `fn_validar_traslape_nombramiento` y `fn_validar_fecha_nombramiento`.
- [ ] Backend: `src/models/Asambleista.js` con `crearConNombramiento()` (transaccional).
- [ ] Backend: `AsambleistaController.registrar` que captura las excepciones `TRASLAPE DETECTADO` y `FECHA INVÁLIDA` y devuelve 409/400 al frontend.
- [ ] Vista: `src/views/registro_asambleista.html` con campos de fechas y manejo de errores del backend.

### 🏷 Labels
`database` · `administración` · `Sprint 2` · `critical`

---

## Issue #10 — Módulo de Registro de Estructura Normativa Recursiva (Parte I)

### 🎯 Contexto
Los reglamentos del TEC tienen una estructura jerárquica profunda: `Reglamento > Título > Capítulo > Artículo > Inciso > Sub-inciso`. El sistema debe representarla con **una sola tabla autorreferencial** y soportar **versionamiento histórico** sin perder ninguna versión previa.

> **Regla de oro:** no pueden existir dos versiones VIGENTES del mismo elemento al mismo tiempo.

### ✅ Criterios de Aceptación
- [ ] Tabla `elemento_normativo` con autorreferencia `id_padre`.
- [ ] Campo `tipo` con CHECK constraint sobre los valores permitidos (`REGLAMENTO`, `TITULO`, `CAPITULO`, `ARTICULO`, `INCISO`, `SUBINCISO`).
- [ ] Campo `orden` NOT NULL > 0 que preserva la posición del elemento dentro de su padre.
- [ ] Campos `estado`, `fecha_vigencia_inicio`, `fecha_vigencia_fin` para versionamiento.
- [ ] **Partial Unique Index** que impide dos elementos VIGENTES con la misma combinación `(id_padre, tipo, numero)`:
  ```sql
  CREATE UNIQUE INDEX idx_elemento_normativo_vigente
      ON elemento_normativo (COALESCE(id_padre, -1), tipo, numero)
      WHERE estado = 'VIGENTE' AND fecha_vigencia_fin IS NULL;
  ```
- [ ] **Trigger `fn_versionar_elemento_normativo`** que, antes de insertar un VIGENTE, marca el anterior como HISTORICO y le asigna `fecha_vigencia_fin = CURRENT_DATE`.
- [ ] Cada elemento normativo está vinculado a una `resolucion` (FK `id_resolucion_origen`) que representa el acuerdo de la AIR que lo aprobó.
- [ ] El seed carga el árbol mínimo: Estatuto Orgánico > Título I > Capítulo I > Artículo 1 > Inciso a.
- [ ] Una **CTE recursiva** demuestra que se puede armar el árbol completo desde el modelo (`Normativa.obtenerArbolVigente()`).
- [ ] El sistema mantiene el historial íntegro: el texto antiguo no se borra, sólo se marca como HISTORICO.

### 🛠 Tareas Técnicas
- [ ] BD: tabla `resolucion` y `elemento_normativo`.
- [ ] BD: trigger `fn_versionar_elemento_normativo` BEFORE INSERT.
- [ ] BD: Partial Unique Index.
- [ ] Backend: `src/models/Normativa.js` con `obtenerArbolVigente`, `obtenerHistorial`, `insertar`.
- [ ] Pruebas: insertar una reforma del Artículo 1 y verificar que el original queda `HISTORICO` con `fecha_vigencia_fin` no nula.

### 🏷 Labels
`database` · `legal-requirement` · `recursion` · `Sprint 2` · `critical`

---

## Issue #14 — Módulo de Validación de Firmas y Verificación Externa (Base)

### 🎯 Contexto
Una certificación impresa o en PDF debe ser verificable por terceros. Para el Sprint 2 se entrega la **base criptográfica** (hash SHA-256 + código QR). La pantalla pública de validación se completa en el Sprint 3.

### ✅ Criterios de Aceptación
- [ ] Cada PDF generado incluye un código QR único en el pie de página.
- [ ] El QR enlaza a `https://sistema-air.tec.ac.cr/validar/<folio>`.
- [ ] El PDF imprime visiblemente el hash SHA-256 del contenido para auditoría manual.
- [ ] El servicio `CryptoService.sha256()` está separado del controlador (utilidad transversal).
- [ ] El controlador genera el hash **antes** de pasar los datos al servicio de PDF, para que el contenido firmado sea consistente con el documento renderizado.

### 🛠 Tareas Técnicas
- [ ] `npm install qrcode`.
- [ ] `src/services/CryptoService.js`.
- [ ] Integrar la generación de QR en `PDFService.streamCertificacionAIR`.
- [ ] Documentar en el README la URL del verificador público (placeholder para Sprint 3).

### 🏷 Labels
`security` · `frontend` · `public-access` · `Sprint 2`

---

# 📋 Resumen para el tablero del Project

Configura tu **Project Board** así para que la revisión semanal del docente vea claramente el avance:

| Columna | Issues actuales |
|---|---|
| **Backlog** | #2, #5, #6, #7, #11, #12, #13, #15, #16, #17 (todos del Sprint 3) |
| **Ready for Sprint** | (vacío — todo lo del Sprint 2 ya empezó) |
| **In Progress** | Issues actualmente en `feature/issue-N` sin merge |
| **In Review** | Issues con PR abierto contra `develop` |
| **Done** | Issues mergeados a `develop` con `Closes #N` |

### Milestone
Crea el milestone **Sprint 2** y asigna los Issues **#0, #1, #2, #3, #4, #8, #9, #10, #14** a él (9 issues en total).

### Labels recomendados
Crea estos labels en el repo: `database`, `backend`, `frontend`, `security`, `legal-requirement`, `recursion`, `infrastructure`, `documentation`, `critical`, `Sprint 2`, `Sprint 3`.

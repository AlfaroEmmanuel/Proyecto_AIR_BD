# Diccionario de Datos — Proyecto AIR

Última actualización: **Sprint 3** (cierre).

> Este documento es la fuente de verdad del esquema. Cualquier cambio en los
> scripts SQL debe reflejarse aquí en el mismo PR (so penalty per REGLAS_GIT.md).

**Orden de ejecución de los scripts:**
`01_proyecto-air` → `02_sprint3_persona_a` → `03_issue-14-verificacion` →
`04_issue-15-anulaciones` → `05_sprint3_persona_b` → `06_sprint3_persona_c`
(+ `07_seed_demo_sprint3` opcional para datos de prueba).

---

## Convenciones

- Prefijo `sys_` → tablas del sistema (seguridad, auditoría).
- Prefijo `bitacora_` / `_log_` → registros históricos o de auditoría.
- Prefijo `vw_` → vistas. Prefijo `fn_` / `trg_` → funciones y triggers.
- Las PKs son `SERIAL`/`BIGSERIAL` salvo `asambleista.cedula` (identificador natural).
- Fechas de vigencia en `DATE`; los `TIMESTAMP` se reservan para auditoría técnica.
- Todo el esquema vive en `public`.

---

# SPRINT 2 (base)

## Módulo: Seguridad y RBAC

### `sys_rol`
| Columna | Tipo | Nullable | Default | Notas |
|---|---|---|---|---|
| `id_rol` | SERIAL | NO | auto | PK |
| `nombre_rol` | VARCHAR(50) | NO | — | UNIQUE — `Administrador`/`Secretaria`/`Consulta` |
| `descripcion` | VARCHAR(255) | SI | — | |

### `sys_usuario`
| Columna | Tipo | Nullable | Default | Notas |
|---|---|---|---|---|
| `id_usuario` | SERIAL | NO | auto | PK |
| `username` | VARCHAR(100) | NO | — | UNIQUE |
| `password_hash` | VARCHAR(255) | NO | — | **Hash BCrypt cost 10** |
| `email` | VARCHAR(150) | SI | — | UNIQUE |
| `activo` | BOOLEAN | NO | TRUE | Soft delete |
| `id_rol` | INT | NO | — | FK → sys_rol |
| `fecha_creacion` | TIMESTAMP | NO | CURRENT_TIMESTAMP | |

### `sys_log_auditoria`
| Columna | Tipo | Nullable | Default | Notas |
|---|---|---|---|---|
| `id_log` | BIGSERIAL | NO | auto | PK |
| `nombre_tabla` | VARCHAR(60) | NO | — | Tabla afectada |
| `operacion` | VARCHAR(10) | NO | — | CHECK `INSERT/UPDATE/DELETE` |
| `usuario_db` | VARCHAR(60) | NO | CURRENT_USER | Rol PostgreSQL |
| `id_usuario_app` | INT | SI | — | Usuario de la app (vía `SET LOCAL "app.id_usuario"`) |
| `fecha_hora` | TIMESTAMP | NO | CURRENT_TIMESTAMP | |
| `datos_anteriores` | JSONB | SI | — | Snapshot antes (NULL en INSERT) |
| `datos_nuevos` | JSONB | SI | — | Snapshot después (NULL en DELETE) |

## Módulo: Identidad y Nombramientos

### `asambleista`
| Columna | Tipo | Nullable | Notas |
|---|---|---|---|
| `cedula` | VARCHAR(20) | NO | PK — formato CR `X-XXXX-XXXX` o doc. extranjero |
| `nombre` | VARCHAR(100) | NO | |
| `primer_apellido` | VARCHAR(100) | NO | |
| `segundo_apellido` | VARCHAR(100) | SI | |
| `correo_institucional` | VARCHAR(150) | NO | UNIQUE |
| `fecha_registro` | TIMESTAMP | NO | DEFAULT CURRENT_TIMESTAMP |

> No existe columna `nombre_completo`; se calcula con
> `TRIM(nombre||' '||primer_apellido||COALESCE(' '||segundo_apellido,''))`.

### `bitacora_asambleista`, `sector`, `periodo_gestion`, `nombramiento`
Sin cambios respecto al Sprint 2. `nombramiento` usa `estado_activo BOOLEAN`
(vigente = `estado_activo = TRUE AND CURRENT_DATE BETWEEN fecha_inicio AND fecha_fin`).
Triggers `fn_validar_traslape_nombramiento` y `fn_validar_fecha_nombramiento`.

## Módulo: Normativa Recursiva, Folios
`resolucion`, `elemento_normativo` (autorreferencial + índice único parcial +
`fn_versionar_elemento_normativo`), `control_folio` + `generar_siguiente_folio()`.
Sin cambios respecto al Sprint 2.

---

# SPRINT 3

## Persona A — Núcleo de Sesiones (Issues #11, #12, #5, #6)

### Catálogos
| Tabla | Columnas | Notas |
|---|---|---|
| `tipo_sesion` | `id_tipo_sesion` PK, `nombre` UNIQUE | Ordinaria / Extraordinaria |
| `tipo_modalidad` | `id_tipo_modalidad` PK, `nombre` UNIQUE | Presencial / Virtual / Híbrida |
| `estado_propuesta` | `id_estado_propuesta` PK, `nombre` UNIQUE | En trámite / Aprobada / Rechazada |
| `tipo_mayoria_requerida` | `id_tipo_mayoria` PK, `nombre` UNIQUE, `fraccion NUMERIC(4,3)` | Simple 0.500 / Calificada 0.667 |
| `estado_asistencia` | `id_estado_asistencia` PK, `nombre_estado` UNIQUE | Presente / Ausente / Justificado |
| `tipo_comision` | `id_tipo_comision` PK, `nombre` UNIQUE | Permanente / Especial / Análisis |
| `rol_comision` | `id_rol_comision` PK, `nombre` UNIQUE | Coordinador / Secretario / Integrante |
| `catalogo_tipo_propuesta` | `id_tipo_propuesta` PK, `nombre` UNIQUE, `leyenda_legal TEXT`, `activo BOOLEAN` | **Issue #5**: 4 tipos con su texto legal |

### `sesion` (Issue #11)
| Columna | Tipo | Notas |
|---|---|---|
| `id_sesion` | SERIAL | PK |
| `numero_sesion` | VARCHAR(30) | NOT NULL UNIQUE |
| `fecha_sesion` | DATE | NOT NULL |
| `id_tipo_sesion` | INT | FK → tipo_sesion |
| `id_tipo_modalidad` | INT | FK → tipo_modalidad |
| `quorum_requerido` | INT | NOT NULL DEFAULT 0 |
| `cerrada` | BOOLEAN | NOT NULL DEFAULT FALSE |
| `fecha_registro` | TIMESTAMP | DEFAULT CURRENT_TIMESTAMP |

### `propuesta` (Issue #11)
| Columna | Tipo | Notas |
|---|---|---|
| `id_propuesta` | SERIAL | PK |
| `titulo` | VARCHAR(255) | NOT NULL |
| `descripcion` | TEXT | |
| `id_sesion` | INT | FK → sesion |
| `id_estado_propuesta` | INT | FK → estado_propuesta |
| `id_tipo_mayoria` | INT | FK → tipo_mayoria_requerida |
| `id_tipo_propuesta` | INT | FK → catalogo_tipo_propuesta (NULL permitido) |
| `estado` | VARCHAR(40) | DEFAULT 'En trámite' (denormalizado para lectura) |
| `fecha_registro` | TIMESTAMP | DEFAULT CURRENT_TIMESTAMP |

### `votacion` (Issue #11)
| Columna | Tipo | Notas |
|---|---|---|
| `id_votacion` | SERIAL | PK |
| `id_propuesta` | INT | FK → propuesta |
| `id_sesion` | INT | FK → sesion |
| `votos_favor` / `votos_contra` / `votos_abstencion` | INT | CHECK ≥ 0 |
| `total_presentes` | INT | NOT NULL |
| `fecha_votacion` | TIMESTAMP | DEFAULT CURRENT_TIMESTAMP |

### `asistencia_sesion_plenaria` (Issue #12)
| Columna | Tipo | Notas |
|---|---|---|
| `id_asistencia` | SERIAL | PK |
| `id_sesion` | INT | FK → sesion |
| `cedula_asambleista` | VARCHAR(20) | FK → asambleista |
| `id_estado_asistencia` | INT | FK → estado_asistencia |
| | | UNIQUE `(id_sesion, cedula_asambleista)` |

### `sesion_comision` / `asistencia_sesion_comision` (Issue #12/#6)
- `sesion_comision`: `id_sesion_comision` PK, `id_comision` FK → comision, `numero_sesion`, `fecha_sesion`.
- `asistencia_sesion_comision`: PK, `id_sesion_comision` FK, `cedula_asambleista` FK, `id_estado_asistencia` FK, UNIQUE `(id_sesion_comision, cedula_asambleista)`.

### `comision` / `integrante_comision` / `proponente_propuesta` (Issue #6)
| Tabla | Columnas | Notas |
|---|---|---|
| `comision` | `id_comision` PK, `nombre`, `objeto TEXT`, `fecha_creacion DATE`, `id_tipo_comision` FK | |
| `integrante_comision` | `id_integrante` PK, `id_comision` FK, `cedula_asambleista` FK, `id_rol_comision` FK, `fecha_ingreso`, `fecha_salida`, `estado` ('Activo') | trigger de rol único |
| `proponente_propuesta` | `id_proponente` PK, `id_propuesta` FK, `cedula_asambleista` FK, `rol` | UNIQUE `(id_propuesta, cedula_asambleista)` |

### Funciones (Persona A)
| Función | Retorno | Descripción |
|---|---|---|
| `verificar_quorum(p_id_sesion)` | BOOLEAN | Presentes ≥ quórum requerido de la sesión |
| `evaluar_resultado_votacion(p_id_votacion)` | BOOLEAN | Aprueba si `favor/presentes > fracción` de la mayoría |
| `calcular_porcentaje_asistencia_plenaria(cedula, fi, ff)` | NUMERIC(5,2) | % de asistencia plenaria en el rango |
| `calcular_porcentaje_asistencia_comision(cedula, id_comision)` | NUMERIC(5,2) | % de asistencia a una comisión |

### Triggers (Persona A)
- `trg_resolver_propuesta` (AFTER INSERT en `votacion`) → `fn_resolver_propuesta_por_votacion`: actualiza el estado de la propuesta según el resultado.
- `trg_rol_unico_comision` (BEFORE INSERT/UPDATE en `integrante_comision`) → `fn_validar_rol_unico_comision`: impide dos roles activos del mismo asambleísta en una comisión.
- `trg_auditoria_sesion`, `trg_auditoria_votacion`, `trg_auditoria_comision`: reutilizan `fn_registrar_auditoria()`.

---

## Persona B — Trazabilidad y Reportería (Issues #2 ext, #7, #8, #16)

### Vista `vw_hoja_vida_asambleista` (Ext #2 — placeholders ahora REALES)
Los 5 campos que en Sprint 2 estaban en `0` ahora calculan datos reales sobre
las tablas de Persona A:

| Columna | Origen real |
|---|---|
| `total_sesiones_convocadas` | COUNT de `sesion` en el rango del nombramiento |
| `total_asistencias` | COUNT de `asistencia_sesion_plenaria` = 'Presente' |
| `porcentaje_asistencia` | `calcular_porcentaje_asistencia_plenaria(...)` |
| `total_propuestas` | COUNT de `proponente_propuesta` |
| `total_comisiones` | COUNT de `integrante_comision` |

La función `obtener_hoja_vida_asambleista(cedula, fi, ff)` se extendió para
devolver también esas 5 columnas.

### Otras vistas y funciones (Persona B)
| Objeto | Tipo | Descripción |
|---|---|---|
| `vw_asistencia_consolidada` | vista | Plenaria + comisión por asambleísta (convocadas, asistidas, %) |
| `obtener_asistencia_asambleista(cedula, fi, ff)` | función → TABLE(`tipo`, `total_convocadas`, `total_asistidas`, `porcentaje`) | Issue #7/#8; la consume #17 |
| `vw_certificaciones_por_mes` | vista | `anio`, `mes`, `total` (solo estado ACTIVO) |
| `vw_asambleistas_mas_certificados` | vista | `cedula`, `nombre`, `total_certificaciones` |
| `vw_distribucion_sectores` | vista | `sector`, `total_asambleistas`, `porcentaje` (nombramientos vigentes) |

---

## Persona C — Certificaciones (Issues #14, #15, #17, #13)

### `certificacion_emitida` (Issue #14)
| Columna | Tipo | Notas |
|---|---|---|
| `id_certificacion` | SERIAL | PK |
| `folio_unico` | VARCHAR(30) | NOT NULL UNIQUE — `DAIR-XXX-AÑO` |
| `cedula_asambleista` | VARCHAR(20) | FK → asambleista |
| `id_usuario_secretaria` | INT | FK → sys_usuario |
| `hash_sha256` | VARCHAR(64) | SHA-256 del contenido |
| `url_verificacion` | TEXT | Ruta pública `/verificar/<folio>` |
| `fecha_emision` | TIMESTAMP | DEFAULT CURRENT_TIMESTAMP |
| `estado` | VARCHAR(10) | CHECK `ACTIVO`/`ANULADO`, DEFAULT 'ACTIVO' |
| `datos_snapshot` | JSONB | NOT NULL — copia inmutable del contenido emitido |
| `motivo_anulacion` | TEXT | (agregada por #15) |
| `id_cert_sustituida` | INT | FK → certificacion_emitida (agregada por #15) |

Índice `idx_cert_cedula` sobre `(cedula_asambleista)`.

### `anulacion_certificacion` (Issue #15)
| Columna | Tipo | Notas |
|---|---|---|
| `id_anulacion` | SERIAL | PK |
| `id_certificacion` | INT | FK → certificacion_emitida |
| `id_usuario_admin` | INT | FK → sys_usuario |
| `motivo` | TEXT | NOT NULL |
| `fecha_anulacion` | TIMESTAMP | DEFAULT CURRENT_TIMESTAMP |
| `folio_anulado` | VARCHAR(30) | Copia del folio para trazabilidad |
| `folio_sustituto` | VARCHAR(30) | Folio que lo reemplaza (si aplica) |

### Funciones y triggers (Persona C)
| Objeto | Retorno / Tipo | Descripción |
|---|---|---|
| `generar_hash_verificacion(p_contenido)` | TEXT | SHA-256 vía `pgcrypto.digest` (requiere `CREATE EXTENSION pgcrypto`) |
| `verificar_certificacion(p_folio)` | TABLE(`es_valido`, `folio_unico`, `estado`, `nombre_asambleista`, `cedula`, `fecha_emision`, `hash_sha256`, `mensaje`) | Verificación pública (#14) |
| `anular_certificacion(p_folio, p_motivo, p_id_usuario_admin, p_folio_sustituto)` | TABLE(`ok`, `mensaje`, `folio_anulado`) | Anula y registra en bitácora (#15) |
| `obtener_historial_anulaciones(p_folio)` | TABLE(`id_anulacion`, `folio_anulado`, `folio_sustituto`, `motivo`, `fecha_anulacion`, `usuario_admin`, `nombre_asambleista`) | Historial (#15) |
| `obtener_datos_certificacion(cedula, fi, ff)` | **JSONB** | **Issue #17**: payload completo del PDF (identidad + nombramientos + asistencia [B] + propuestas con leyenda [A/#5] + comisiones + cláusula 301 LGAP + firma) |
| `vw_certificacion_completa` | vista | Índice legible de fuentes para el motor #17 |
| `fn_no_repudio_cert` / `tg_no_repudio_cert` | trigger | Inmutabilidad: solo permite ACTIVO→ANULADO con motivo |
| `tg_auditoria_certificacion` | trigger | Auditoría de la tabla de certificaciones |

> **Issue #13** (bitácora, snapshot, hash, inmutabilidad, verificación) queda
> cubierto por la combinación de `datos_snapshot`, `hash_sha256`,
> `tg_no_repudio_cert`, `sys_log_auditoria` y `verificar_certificacion`.

---

## Fórmulas de referencia

```
% participación plenaria = asistencias 'Presente' / sesiones convocadas en el rango * 100
votación aprobada        = votos_favor / total_presentes > fracción (0.5 simple, 0.667 calificada)
quórum                   = presentes 'Presente' >= sesion.quorum_requerido
```

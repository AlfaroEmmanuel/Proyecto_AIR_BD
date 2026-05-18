# Diccionario de Datos — Proyecto AIR

Última actualización: Sprint 2.

> Este documento es la fuente de verdad del esquema. Cualquier cambio en `proyecto-air.sql` debe reflejarse aquí en el mismo PR (so penalty per REGLAS_GIT.md).

---

## Convenciones

- Prefijo `sys_` → tablas del sistema (seguridad, auditoría).
- Prefijo `bitacora_` → registros históricos de cambios sensibles.
- Las PKs son `SERIAL` o `BIGSERIAL` salvo `asambleista.cedula` que usa la cédula como identificador natural.
- Todas las fechas relevantes para vigencia son `DATE`. Los `TIMESTAMP` se reservan para auditoría técnica.

---

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
| `id_usuario_app` | INT | SI | — | Usuario de la aplicación (vía `SET LOCAL "app.id_usuario"`) |
| `fecha_hora` | TIMESTAMP | NO | CURRENT_TIMESTAMP | |
| `datos_anteriores` | JSONB | SI | — | Snapshot antes del cambio (NULL en INSERT) |
| `datos_nuevos` | JSONB | SI | — | Snapshot después del cambio (NULL en DELETE) |

---

## Módulo: Identidad y Nombramientos

### `asambleista`
| Columna | Tipo | Nullable | Default | Notas |
|---|---|---|---|---|
| `cedula` | VARCHAR(20) | NO | — | PK — formato CR `X-XXXX-XXXX` o doc. extranjero |
| `nombre` | VARCHAR(100) | NO | — | |
| `primer_apellido` | VARCHAR(100) | NO | — | |
| `segundo_apellido` | VARCHAR(100) | SI | — | |
| `correo_institucional` | VARCHAR(150) | NO | — | UNIQUE |
| `fecha_registro` | TIMESTAMP | NO | CURRENT_TIMESTAMP | |

### `bitacora_asambleista`
Cambios históricos de cédula/nombre (TSE, nacionalizaciones).

| Columna | Tipo | Nullable | Default | Notas |
|---|---|---|---|---|
| `id_bitacora` | BIGSERIAL | NO | auto | PK |
| `cedula_actual` | VARCHAR(20) | NO | — | FK → asambleista |
| `cedula_anterior` | VARCHAR(20) | SI | — | |
| `nombre_anterior` | VARCHAR(300) | SI | — | |
| `razon_cambio` | VARCHAR(255) | NO | — | |
| `fecha_actualizacion` | TIMESTAMP | NO | CURRENT_TIMESTAMP | |

### `sector`
| Columna | Tipo | Notas |
|---|---|---|
| `id_sector` | SERIAL PK | |
| `nombre_sector` | VARCHAR(60) UNIQUE | |

### `periodo_gestion`
| Columna | Tipo | Notas |
|---|---|---|
| `id_periodo` | SERIAL PK | |
| `anio_gestion` | INT UNIQUE | |
| `fecha_inicio` | DATE | CHECK `fecha_fin > fecha_inicio` |
| `fecha_fin` | DATE | |

### `nombramiento`
| Columna | Tipo | Nullable | Default | Notas |
|---|---|---|---|---|
| `id_nombramiento` | SERIAL | NO | auto | PK |
| `cedula_asambleista` | VARCHAR(20) | NO | — | FK → asambleista |
| `id_sector` | INT | NO | — | FK → sector |
| `id_periodo` | INT | NO | — | FK → periodo_gestion |
| `fecha_inicio` | DATE | NO | — | Inicio del nombramiento |
| `fecha_fin` | DATE | NO | — | Fin del nombramiento |
| `estado_activo` | BOOLEAN | NO | TRUE | |
| `fecha_registro` | TIMESTAMP | NO | CURRENT_TIMESTAMP | |

**Triggers:**
- `fn_validar_traslape_nombramiento` (BEFORE INSERT/UPDATE) — bloquea rangos solapados.
- `fn_validar_fecha_nombramiento` (BEFORE INSERT/UPDATE) — exige que el rango esté dentro del `periodo_gestion`.

---

## Módulo: Normativa Recursiva

### `resolucion`
| Columna | Tipo | Nullable | Notas |
|---|---|---|---|
| `id_resolucion` | SERIAL | NO | PK |
| `folio_dair` | VARCHAR(30) | NO | UNIQUE — `DAIR-XXX-AÑO` |
| `fecha_aprobacion` | DATE | NO | |
| `descripcion` | TEXT | NO | |

### `elemento_normativo` (autorreferencial)
| Columna | Tipo | Nullable | Notas |
|---|---|---|---|
| `id_elemento` | SERIAL | NO | PK |
| `id_padre` | INT | SI | FK → elemento_normativo (NULL = raíz) |
| `tipo` | VARCHAR(20) | NO | CHECK ∈ {REGLAMENTO, TITULO, CAPITULO, ARTICULO, INCISO, SUBINCISO} |
| `numero` | VARCHAR(10) | NO | `I`, `1`, `a`, `i` |
| `texto_contenido` | TEXT | NO | |
| `orden` | INT | NO | CHECK > 0 — posición dentro del padre |
| `id_resolucion_origen` | INT | NO | FK → resolucion |
| `estado` | VARCHAR(15) | NO | CHECK ∈ {VIGENTE, HISTORICO, DEROGADO} |
| `fecha_vigencia_inicio` | DATE | NO | DEFAULT CURRENT_DATE |
| `fecha_vigencia_fin` | DATE | SI | NULL mientras esté vigente |

**Índice único parcial (Regla de Oro):**
```sql
CREATE UNIQUE INDEX idx_elemento_normativo_vigente
    ON elemento_normativo (COALESCE(id_padre, -1), tipo, numero)
    WHERE estado = 'VIGENTE' AND fecha_vigencia_fin IS NULL;
```

**Trigger `fn_versionar_elemento_normativo`** (BEFORE INSERT):
Si se inserta un elemento con estado `VIGENTE`, cierra automáticamente el anterior con la misma combinación `(id_padre, tipo, numero)`, marcándolo `HISTORICO` y asignándole `fecha_vigencia_fin = CURRENT_DATE`.

---

## Módulo: Control de Folios

### `control_folio`
| Columna | Tipo | Notas |
|---|---|---|
| `anio` | INT PK | |
| `ultimo_consecutivo` | INT | DEFAULT 0 |
| `fecha_actualizacion` | TIMESTAMP | |

**Función `generar_siguiente_folio() RETURNS VARCHAR`:**
Atómica vía `INSERT … ON CONFLICT (anio) DO UPDATE … RETURNING`. Garantiza que invocaciones concurrentes nunca colisionen.

---

## Módulo: Trazabilidad y Hoja de Vida (Issue #2)

### Vista `vw_hoja_vida_asambleista`
Consolida la identidad del asambleísta con todos sus nombramientos históricos. Sprint 2 entrega la Parte I (identidad + nombramientos). Sprint 3 extenderá la vista con asistencias, propuestas y comisiones.

| Columna | Tipo | Origen | Notas |
|---|---|---|---|
| `cedula` | VARCHAR(20) | asambleista | |
| `nombre_completo` | TEXT | calculado | `nombre + primer_apellido + segundo_apellido` |
| `correo_institucional` | VARCHAR(150) | asambleista | |
| `id_nombramiento` | INT | nombramiento | NULL si no tiene nombramientos |
| `nombramiento_inicio` | DATE | nombramiento | |
| `nombramiento_fin` | DATE | nombramiento | |
| `nombramiento_activo` | BOOLEAN | nombramiento | |
| `nombre_sector` | VARCHAR(60) | sector | |
| `anio_gestion` | INT | periodo_gestion | |
| `estado_actual` | TEXT | calculado | `VIGENTE` / `CONCLUIDO` / `INACTIVO` / `PROGRAMADO` |
| `dias_nombramiento` | INT | calculado | `fecha_fin - fecha_inicio + 1` |
| `total_sesiones_convocadas` | INT | placeholder | **TODO Sprint 3** |
| `total_asistencias` | INT | placeholder | **TODO Sprint 3** |
| `porcentaje_asistencia` | NUMERIC(5,2) | placeholder | **TODO Sprint 3** |
| `total_propuestas` | INT | placeholder | **TODO Sprint 3** |
| `total_comisiones` | INT | placeholder | **TODO Sprint 3** |

### Función `obtener_hoja_vida_asambleista(p_cedula, p_fecha_inicio, p_fecha_fin)`
Devuelve la hoja de vida del asambleísta filtrada por rango de fechas (opcional). Si se omiten las fechas, devuelve toda la trayectoria.

```sql
SELECT * FROM obtener_hoja_vida_asambleista('3-0248-0440');
SELECT * FROM obtener_hoja_vida_asambleista('3-0248-0440', '2026-01-01', '2026-12-31');
```

El backend consume esta función desde `Asambleista.hojaDeVida()` siguiendo la recomendación del PDF: *"Intenten usar la mayor cantidad de [funciones] que puedan directamente en la BD"*.

---

## TODO — Estructuras del Sprint 3

Se documentan aquí para que el equipo sepa hacia dónde se mueve el esquema:

- `sesion` (id_sesion, fecha, tipo_sesion, quorum_requerido)
- `asistencia_sesion_plenaria` (cedula_asambleista, id_sesion, estado_asistencia)
- `propuesta` (id_propuesta, titulo, id_etapa, id_estado, codigo_air)
- `proponente_propuesta` (id_propuesta, cedula_asambleista) — N:M
- `comision` (id_comision, nombre, id_tipo_comision)
- `integrante_comision` (id_comision, cedula_asambleista, id_rol_comision, fecha_ingreso)
- `votacion_acuerdo` (id_votacion, id_propuesta, votos_favor, votos_contra, abstenciones)
- `certificacion_emitida` (id_certificacion, folio, cedula, hash_seguridad, fecha_emision)

**Fórmula de % de participación (Issue #8 / Issue #12):**
```
% participación = (asistencias_efectivas / sesiones_convocadas_en_periodo) * 100
```

# Reglas de Git — Proyecto AIR

> **Cualquier código que no esté en la rama correspondiente al Sprint activo se considerará inexistente para el proceso de revisión académica.**

---

## 1. Flujo de ramas

| Sprint | Rama destino | Regla de revisión |
|---|---|---|
| Sprint 2 | `develop` | Solo se revisa lo que esté en `develop` al cierre |
| Sprint 3 | `main`    | Solo se revisa lo que esté en `main` al cierre |

### Ramas de trabajo (`feature/issue-NUMERO`)

- Toda tarea nace de su propia rama: `feature/issue-9-catalogo-asambleistas`.
- Al terminar, se abre Pull Request hacia `develop` (Sprint 2) o `main` (Sprint 3).
- La rama de Issue se elimina al hacer merge.

```
main
 └── develop
      ├── feature/issue-0-rbac
      ├── feature/issue-1-folios
      ├── feature/issue-9-catalogo-asambleistas
      └── feature/issue-10-normativa-recursiva
```

---

## 2. Notación de commits (Conventional Commits)

```
tipo(modulo): descripción breve en minúsculas
```

### Tipos permitidos

| Prefijo | Cuándo usarlo |
|---|---|
| `db(modulo):` | Cambios en scripts SQL o estructura de base de datos |
| `feat(modulo):` | Nueva funcionalidad |
| `fix(modulo):` | Corrección de un bug existente |
| `docs(modulo):` | Cambios en README, manuales o comentarios |
| `refactor(modulo):` | Reestructuración sin cambios funcionales |
| `chore(modulo):` | Tareas auxiliares (dependencias, configuración) |

### Ejemplos válidos

```
db(normativa): crear tabla recursiva con fechas de vigencia
feat(sesiones): implementar validacion de quorum legal
fix(votos): corregir conteo en mayoria calificada
docs(readme): documentar credenciales de prueba del seed
```

### Ejemplos prohibidos ❌

- `cambios`
- `arreglo`
- `subiendo archivo`
- `.`
- `update`

---

## 3. Vinculación Issue ↔ Pull Request

Toda PR debe incluir en su descripción:

```
Closes #N
```

donde `N` es el número del Issue que se cierra. Esto:
- Cierra el Issue automáticamente al aprobar el merge.
- Mueve el Issue a la columna `Done` del Project Board.

---

## 4. Tablero del Project (GitHub Projects)

Columnas obligatorias:

1. **Backlog**: Issues sin empezar.
2. **Ready for Sprint**: Issues del Sprint actual con criterios de aceptación definidos.
3. **In Progress**: En desarrollo (máximo **2 issues por persona**).
4. **In Review**: PR abierto esperando merge.
5. **Done**: Mergeado y cerrado.

### Metadatos obligatorios por Issue

- `Assignees`: una sola persona responsable.
- `Labels`: `feature`, `bug`, `database`, `security`, `legal-requirement`, etc.
- `Milestone`: `Sprint 2` o `Sprint 3`.

### Regla de la "verdad única"

> Si un Issue está en `Done` pero el código **no** está en la rama correspondiente, se considera **no entregado**.

---

## 5. Penalizaciones

| Causa | Penalización |
|---|---|
| Código fuera de la rama del Sprint activo | **Nota 0** en ese Issue |
| `proyecto-air.sql` no está en la raíz | **−10%** del Sprint |
| Diccionario de datos desactualizado en README | **−10%** del Sprint |
| Lógica de negocio en `/views` (MVC violado) | **Pérdida total del puntaje de arquitectura** |
| Commit con mensaje genérico | **−5%** por incidencia (tope **−20%**) |
| No usar prefijo `db:`/`feat:`/`fix:` | **−5%** por incidencia (tope **−20%**) |
| Commits masivos el último día | **−5%** por incidencia (tope **−20%**) |
| Issue en `Done` sin código en la rama oficial | **No entregado** |

---

## 6. Estándar de Pull Request

Cada PR debe responder:

```markdown
## Closes #N

### ¿Qué se hizo?
- Implementación de la tabla `elemento_normativo` con autoreferencia.
- Trigger de versionamiento automático.

### ¿Cómo probarlo?
1. Ejecutar `proyecto-air.sql` en una base limpia.
2. Insertar un artículo y luego una segunda versión del mismo.
3. Verificar que la primera versión queda en estado `HISTORICO`.

### Capturas / Evidencia
(Adjuntar screenshot de la prueba)

### Checklist
- [ ] El código compila / corre.
- [ ] Se actualizó el diccionario de datos en README si aplica.
- [ ] No hay lógica de negocio en `/views`.
- [ ] El commit message sigue la notación.
```

---

## 7. Cierre del Sprint

Antes de la fecha de corte:

- [ ] Todas las PR del Sprint mergeadas a la rama correspondiente.
- [ ] Tablero con todos los Issues en `Done`.
- [ ] Tag de Git: `v1.0-sprint2` o `v2.0-final`.
- [ ] README y diccionario de datos actualizados.
- [ ] Evidencia (video) cargada según se solicite.

# Checklist maestro — revisión profunda nocturna (2026-07-15)

Compilado a partir de 5 auditorías independientes corridas en paralelo esta
noche: [A — SQL/migraciones/RLS](A-sql-rls.md) ·
[B — consistencia de funciones RPC](B-rpc-consistencia.md) ·
[C — páginas admin (frontend)](C-admin-frontend.md) ·
[D — terminal de marcaje + rutas API](D-terminal-api.md) ·
[E — auditoría de seguridad](E-seguridad.md).

**Nada de esto se aplicó a producción.** Ningún archivo de código se tocó,
ninguna migración se corrió contra Supabase, no hubo deploy ni push. Es
100% análisis estático + documentación, para que decidas tú qué hacer con
cada cosa. Cuando un hallazgo lo encontraron varios agentes por separado
(sin coordinarse entre sí), lo marco — es la señal más fuerte de que es
real y no un falso positivo de un solo agente.

Prioridad: 🔴 dinero/acceso/datos comprometidos hoy · 🟡 riesgo real, impacto
acotado · 🟢 cuando haya tiempo.

---

## 🔴 Crítico

- [ ] **El PIN del terminal no protege nada — cualquiera puede marcar
  asistencia como otra persona ("buddy punching"), potencialmente de otra
  sede** — *encontrado de forma independiente por 3 de los 5 agentes (A, D,
  E)*. `fn_registrar_marcaje` (`supabase/migrations/0002_functions.sql:194-307`)
  nunca recibe ni valida ningún PIN — la verificación de PIN corre 100% en
  el navegador del kiosko contra un `pin_hash` que se descarga completo al
  dispositivo. Encima, la función tampoco valida que la persona marcada
  pertenezca a la sede del terminal, y el chequeo de "terminal autenticado"
  se salta enteramente cuando la llamada no tiene sesión (`auth.uid()` NULL).
  Cualquiera con acceso a la consola del navegador del kiosko puede marcar
  entrada/salida de cualquier persona, de cualquier sede, sin PIN. Hoy el
  impacto inmediato es bajo (las 3 sedes tienen `requiere_pin=false`), pero
  el hueco queda listo para el día que se active el PIN pensando que sí
  protege. Afecta directo planilla, provisiones y el bono de puntualidad.
  Parche propuesto: ver [`parches/01-marcaje-pin-y-sede.sql`](parches/01-marcaje-pin-y-sede.sql).

- [x] **`fn_provisiones` tenía el mismo bug de zona horaria (UTC vs. Lima)
  que ya se corrigió hoy en el bono de puntualidad** — *A y B, mismo
  hallazgo*. ✅ **RESUELTO 2026-07-16**: aplicado en producción vía SQL
  Editor de Supabase y verificado en vivo contra `pg_get_functiondef`
  (confirma que la línea nueva con `America/Lima` está activa y la vieja con
  `current_date` desnudo ya no). Migración versionada en
  [`0035_provisiones_zona_horaria.sql`](../../supabase/migrations/0035_provisiones_zona_horaria.sql).
  Detalle del hallazgo original en
  [`parches/02-provisiones-zona-horaria.sql`](parches/02-provisiones-zona-horaria.sql).

- [x] **`fn_auto_cierre` (corre cada 15 min, cron activo en producción) usaba
  un modelo de horario desactualizado y podía cerrar jornadas a la hora
  equivocada** — *B*. ✅ **RESUELTO 2026-07-16**: aplicado en producción vía
  SQL Editor de Supabase y verificado en vivo contra `pg_get_functiondef`
  (confirma que la cascada turno-del-día → horario_por_dia → legacy está
  activa). Migración versionada en
  [`0036_auto_cierre_horario.sql`](../../supabase/migrations/0036_auto_cierre_horario.sql).
  Detalle del hallazgo original en
  [`parches/03-auto-cierre-horario.sql`](parches/03-auto-cierre-horario.sql).

- [x] **El candado de "periodo ya PAGADO" faltaba en 9 funciones que
  alimentan Planilla** — *B*. ✅ **RESUELTO 2026-07-17**: aplicado en
  producción y verificado en vivo contra `pg_get_functiondef` (9/9
  funciones confirmadas). Decisiones de producto de Felipe: `fn_corregir_marcaje`/
  `fn_agregar_marcaje`/`fn_eliminar_marcaje`/`fn_set_turno`/`fn_set_descanso`/
  `fn_quitar_turno` bloquean si la fecha puntual cae en un periodo pagado
  (mismo criterio que feriados); `fn_set_horario_semanal`/`fn_set_salario`
  bloquean si existe un periodo pagado que termine en o después de la fecha
  de vigencia (por el efecto en cascada hacia adelante); `fn_set_fecha_ingreso`
  bloquea solo si esa persona en particular ya tiene jornadas trabajadas en
  un periodo pagado. **`fn_set_con_hijos` quedó deliberadamente SIN
  candado** — bloquearla mientras exista cualquier periodo pagado la
  congelaría para siempre desde el primer mes pagado; el riesgo real es
  acotado (solo importa si se reabre un periodo viejo para recalcularlo).
  Migración versionada en
  [`0037_candado_periodo_pagado.sql`](../../supabase/migrations/0037_candado_periodo_pagado.sql).

- [x] **"Días con tardanza: 0" en Perfil y Horas podía ser falso** — *C,
  mismo bug que ya se encontró y corrigió HOY en el bono de puntualidad,
  vivo en el frontend*. ✅ **RESUELTO 2026-07-17**: `perfil/page.tsx` ahora
  muestra "X de Y medidos" y `horas/page.tsx` muestra "sin medir" cuando
  nadie pudo medirse (gente por RxH o sin horario asignado aún) — ya no se
  confunde con asistencia perfecta. Verificado con `tsc --noEmit` (exit 0).
  Detalle original en
  [`parches/04-perfil-horas-null-blindness.md`](parches/04-perfil-horas-null-blindness.md).

- [x] **Fallas de carga silenciosas en 7 páginas — podían mostrar "todo
  bien" cuando la consulta en realidad falló** — *C*. ✅ **RESUELTO
  2026-07-16**: aplicado el patrón de `provisiones/page.tsx` (banner rojo +
  "Reintentar", sin pisar datos buenos con una carga fallida) en las 7
  páginas: `dashboard`, `correcciones`, `horas`, `incidencias`, `perfil`,
  `horarios`, `turnos` y `equipo` (8 en total, contando dashboard). En
  `correcciones`, `horarios` y `turnos` se reutilizó el estado de mensaje/
  error que la página ya tenía, en vez de agregar uno nuevo. Verificado con
  `tsc --noEmit` (exit 0, sin errores en los 4 workspaces) y con el
  Dashboard corriendo en `next dev` local (redirige correctamente a login
  sin sesión, sin loops ni crashes). **No se pudo probar en vivo el banner
  de error en sí** (mostrar el aviso rojo cuando la consulta realmente
  falla) — el entorno local no tiene Supabase local corriendo para simular
  una sesión autenticada; queda pendiente que Felipe lo confirme visualmente
  en producción o con Supabase local levantado. Detalle original en
  [`parches/07-fallas-carga-silenciosas.md`](parches/07-fallas-carga-silenciosas.md).

- [x] **PII real del equipo comiteada a git, fuera del patrón de gitignore
  que el proyecto ya usa** — *E*. ✅ **RESUELTO (parcial) 2026-07-16**: se
  descubrió durante la limpieza que el repo **ya tenía un remoto de GitHub
  configurado** (`github.com/felipea92p-ux/cayla-dynamic`, 26 commits
  locales por subir) — contradice lo que decía el hallazgo original ("aún no
  se sube"). Confirmado en vivo con Felipe (captura del repo en GitHub): es
  **privado**, un solo colaborador — riesgo de exposición bajo, no
  crítico. Se limpiaron los 4 archivos originales **y 2 más que el audit de
  anoche no había detectado** (`scripts/setup-horarios-prod.mjs` y
  `scripts/migracion-historica/aplicar-config.mjs`, ambos con nombres reales
  hardcodeados) — todos ahora leen de JSON en `scripts/datos-privados/`
  (gitignorado), verificado con `git grep` que no queda ningún nombre real
  en archivos trackeados fuera de `docs/`. `scripts/migracion-historica/roster-actual.json`
  se movió y se sacó del tracking (`git rm --cached`). **Pendiente, sin
  apuro dado que el repo es privado**: decidir si reescribir el historial
  viejo de git (los commits ya subidos a `origin/main` siguen teniendo los
  datos reales) — ver plan en
  [`parches/05-pii-gitignore.md`](parches/05-pii-gitignore.md). Ningún
  commit ni push nuevo se hizo — los cambios quedaron solo en el working
  tree, a la espera de que Felipe revise y decida cuándo commitear.

- [x] **La llave `service_role` de Supabase (acceso total, bypassea todo)
  se reutilizaba como "contraseña" del puente hacia Google Sheets** — *D y
  E, mismo hallazgo*. ✅ **RESUELTO 2026-07-16**: `api/espejo/route.ts` ahora
  compara contra un `ESPEJO_TOKEN` propio y aleatorio (no la llave real);
  la propiedad `SUPABASE_KEY` en Apps Script se actualizó a ese mismo
  token; verificado en vivo con "actualizarEspejo" corriendo sin error.
  Detalle en [`parches/06-espejo-secreto-propio.md`](parches/06-espejo-secreto-propio.md).
  Pendiente aparte, sin apuro: rotar la llave `service_role` real esta
  semana (se escribió en el chat de esta sesión al recuperarla, por
  higiene conviene regenerarla igual aunque nunca haya salido de aquí).

- [ ] **`fn_set_meta_cobertura` usa un patrón de permiso inseguro y falla
  ABIERTO para cualquiera sin sesión** — *A y B, mismo hallazgo*. Usa
  `fn_rol_actual() not in (...)` en vez del patrón `is not true` que el
  propio equipo adoptó como regla después de escribir esta función —
  `NULL NOT IN (...)` es NULL, no dispara la excepción. Combinado con que
  el `execute` nunca se revocó de `public`/`anon`, cualquiera sin sesión
  puede sobrescribir la meta de cobertura de cualquier sede. Impacto
  acotado (solo el número de "meta" del dashboard, no dinero), pero
  confirma que el patrón inseguro no es un caso aislado. Parche completo
  (guard corregido + revoke) al final de
  [`parches/01-marcaje-pin-y-sede.sql`](parches/01-marcaje-pin-y-sede.sql).

---

## 🟡 Importante

- [ ] **Condición de carrera en `fn_registrar_marcaje`** (check-then-insert
  sin lock) puede generar marcajes duplicados con dos llamadas casi
  simultáneas — *D*.
- [ ] **`confirmarMarcaje` sin `try/catch`** — una excepción de red (no solo
  un error de respuesta) pierde el marcaje sin encolarlo offline ni
  avisar — *D*.
- [ ] **Marcajes que fallan 6 veces en el outbox offline se descartan sin
  avisar a nadie** — *D*. El PIN se apaga solo (`requierePin: false`) si
  falla el refresh de config del terminal — mismo archivo, mismo hallazgo
  general del terminal.
- [ ] **`api/reabrir-dia` no valida que la persona pertenezca a la sede del
  terminal que llama** (corre con service role, bypassea RLS) — *D*.
- [ ] **`fn_registrar_marcaje` no valida `personas.estado = 'activo'`** —
  alguien desactivado puede seguir marcando si su UUID quedó cacheado o se
  conoce por otra vía — *D*.
- [ ] **Página Equipo sin ningún gate de rol en la UI** (a diferencia de
  Áreas/Objetivos/Turnos/Planilla) — cualquier `integrante` ve los
  controles de alta/edición/PIN, aunque el servidor sí bloquea la
  escritura — *C*.
- [ ] **`fn_provisiones` no avisa cuando a alguien le falta asignación de
  salario** (aparece con S/0.00 en todo, indistinguible de "no le toca
  nada") — a diferencia de Planilla, que sí muestra "horas sin salario" en
  rojo — *B*.
- [ ] **Redondeo: `fn_provisiones.gran_total` puede no cuadrar en ±S/0.01**
  con la suma visible de sus partes — *B*.
- [ ] **Contraseña mínima de 6 caracteres sin complejidad** para cuentas
  admin/líder (ven salarios de toda la empresa) — *E*.
- [ ] **Contraseñas temporales sin cambio forzado en el primer login** —
  *E*.
- [ ] **Varias funciones sensibles sin `revoke execute from public/anon`
  explícito** (`fn_auto_cierre`, `fn_recalcular_jornada`, y la lista más
  larga del reporte A/B) — mismo patrón de raíz que el hallazgo 🔴 del
  terminal, pero en funciones donde hoy el chequeo interno o la ausencia de
  policy de escritura ya lo cubre — *A, B, E*.
- [ ] **Valores fijos que deberían salir de `configuracion`**: el label de
  "S/113" de asignación familiar en Equipo (puede desincronizarse del
  monto real), y los umbrales 21%/12.6%/30% de objetivos, duplicados entre
  SQL y `lib/objetivos.ts` — *C*.
- [ ] **`generarClave()` usa `Math.random()`** para contraseñas de cuentas
  — no es criptográficamente seguro, bajo riesgo real pero fácil de
  corregir — *D*.
- [ ] **Las 3 rutas de API devuelven el mensaje crudo de Postgres al
  cliente** — riesgo bajo en panel interno, pero puede filtrar detalles
  internos — *D*.
- [ ] **`api/admin/cuentas` (acción "promover") no revalida que la persona
  sea `integrante` antes de escribir `supervisor_sede`** — no explotable
  hoy con el flujo normal, pero sin la validación server-side propia que sí
  tiene el resto de RPCs — *C*.

## 🟢 Cuando haya tiempo

- [ ] Migraciones 0031 y 0033 faltan como archivos versionados (existen
  solo como scripts manuales en `scripts/sql-manual/`) — riesgo de
  recuperación ante desastre, no de operación diaria — *A*.
- [ ] `fn_exigir_admin` es código muerto, sin llamadas desde 0010 — *B*.
- [ ] `createServiceRoleClient()` (helper centralizado) nunca se usa — las
  3 rutas que necesitan la llave de servicio construyen su propio cliente
  inline — *E*.
- [ ] Lógica de "tramo de salario vigente" duplicada entre
  `fn_planilla_calcular` y `fn_provisiones` — riesgo de mantenimiento, no
  bug hoy — *B*.
- [ ] Doble-envío sin `disabled` en varios botones de Equipo/Objetivos
  (regenerar PIN, marcar objetivo) — *C*.
- [ ] Fechas/horas sin etiqueta "(hora de Perú)" en toda la app — *C*.
- [ ] Sin `aria-label` en botones de celda del calendario de Turnos — *C*.
- [ ] Sin rate limiting propio en rutas API / RPC de marcaje (depende del
  default de Supabase/Vercel) — *D*.

## Investigado y resuelto esta noche (sin acción pendiente)

- **"Vigente desde" se revierte al escribir el día en Horarios** — *C, con
  diagnóstico profundo*. Se descartó re-render por polling, realtime, o
  cualquier otro `setDesde` — el archivo está limpio. Diagnóstico: es un
  quirk conocido de Chrome con `<input type="date">` controlado por React
  (el segmento activo del campo se reinicia en cada re-render mientras se
  escribe, no al usar el calendario emergente). No es un bug de esta
  página específicamente — debería reproducirse en cualquier campo de
  fecha de la app si se escribe en vez de usar el ícono de calendario.
  Sugerencia de arreglo (desacoplar el input de `value` mientras tiene
  foco) en el detalle del reporte C — no incluido como parche automático
  por ser un cambio de patrón de UI, no una corrección puntual.

---

## Para Felipe — por dónde empezar

Si solo vas a mirar 3 cosas mañana:

1. **El PIN del terminal** (arriba, primer ítem 🔴) — es el hallazgo más
   corroborado (3 agentes distintos llegaron solos a lo mismo) y el de
   mayor radio de explosión real sobre datos de asistencia/pago.
2. **La llave `service_role` reusada en el puente de Sheets** — es el que
   tiene el peor "peor caso" (acceso total a la base, no solo a un dato).
3. **PII en git antes de subir a GitHub** — bloquea un pendiente que ya
   tenías anotado; mejor limpiarlo ahora que después de subido.

El resto puede esperar una semana normal de trabajo sin drama.

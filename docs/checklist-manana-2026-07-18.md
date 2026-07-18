# Checklist para mañana (2026-07-18)

Revisión profunda hecha la noche del 2026-07-17 mientras Felipe no estaba.
**Nada de esto se aplicó ni se desplegó** — es solo análisis. El estado del
repo quedó limpio y sincronizado con GitHub.

Prioridad: 🔴 hazlo primero · 🟡 esta semana · 🟢 cuando haya tiempo.

---

## ✅ RESUELTO (2026-07-18): el botón "Sincronizar ingresos desde marcas" fue ELIMINADO

**Ya no existe.** Se quitó de la pantalla de Equipo y se hizo `drop` de la función
`fn_sembrar_ingresos` en producción (migración `0041_drop_sembrar_ingresos.sql`,
confirmado en la base: la función ya no aparece en `pg_proc`).

Motivo: la fecha de ingreso es una **decisión de negocio** ("desde cuándo le
corresponden beneficios"), no un dato calculable desde las marcas. A veces va
*antes* de la primera marca (empleadas de 2025, cuya antigüedad real es anterior
al arranque del terminal en enero 2026) y a veces *después* (Estefany/Judith).
Un botón que la igualaba a la primera marca solo podía hacer daño: retrocedía la
antigüedad de las de 2025 (borrando CTS/vacaciones/gratis) y se saltaba el candado
de periodo pagado. Ningún guard lo salvaba, porque el error era tratar una decisión
como un cálculo.

**Cómo se hace ahora:** la fecha de ingreso se edita **persona por persona** en
Equipo → editar. Se contrata de una en una; el masivo no tenía caso de uso real.

---

## 0. TUS DECISIONES (personales, no técnicas — 5 min en total)

Estas no son bugs, son datos que solo tú puedes confirmar. Todas se hacen en
**Equipo → editar a la persona**.

- [x] **Estefany Gómez (13/07) y Judith Pillaca (01/07) — SE QUEDAN ASÍ, a
  propósito.** Decisión de Felipe (2026-07-17): no les corresponde el feriado
  del 29 de junio, por eso su fecha de ingreso arranca en julio y NO en su
  primera marca real (23/06 y 26/06). La fecha de ingreso acá es la fecha desde
  la que corresponden beneficios, no la marca literal. (El botón que las habría
  regresado a junio ya fue eliminado — ver arriba. Su fecha solo se toca a mano.)
- [x] **Janis Revilla — RESUELTO 2026-07-17.** Es de confianza y actúa como
  administradora Y encargada a la vez. Se desacopló el conteo de cobertura del
  rol: nueva marca `es_encargada_piso` (migración 0040) — Janis mantiene TODOS
  sus permisos de admin y además cuenta como encargada en Turnos. Aplicado y
  desplegado. **Pendiente chico (🟢):** agregar un checkbox en Equipo para
  marcar "encargada de piso" a otra persona sin tocar SQL (por ahora solo Janis
  está marcada, vía la migración).
- [x] **Meta de operativas TRU = 8 — SE QUEDA EN 8, es correcta.** Corrección de
  Felipe (2026-07-17): 8 es su exigencia real (ese día hay más clientes, quiere
  8 en piso). El sistema muestra "faltan / 57%" porque con los turnos actuales
  el máximo simultáneo es 6 — o sea, el tablero está diciendo la verdad: **ese
  día falta personal para la exigencia**. La señal roja es correcta y accionable
  (reforzar ese día o cuadrar turnos para que coincidan más), NO bajar la meta.
  Mi consejo anterior de bajarla a 5/5 era erróneo — habría maquillado una
  necesidad real de gente.
- [x] **Roles de Melany Enriquez y Catherine Pereyra (supervisor_sede) — CONFIRMADOS
  por Felipe (2026-07-17), son a propósito.** No tocar.
- [x] **Chiara Flores** — su "02/01/2026" es su primera marca (2 de enero), fecha
  correcta. No tocar. (Fue falsa alarma mía.)

---

## 1b. 🎨 Turnos — pedido de Felipe 2026-07-17 (DESPLEGADO 2026-07-18)

- [x] **Estética de Turnos pulida** — control segmentado de 3 vistas, etiquetas
  24h, pie de página limitado a la Vista Día. (Pulido más profundo de la Vista
  Día quedó como opción abierta para otra pasada.)
- [x] **Tercera vista "Integrada"** — DESPLEGADA. Sábana hora×día (franjas de
  30 min 07:45–21:45 × 7 días); celda = nº de operativas + calor vs la meta del
  tramo; puntos taupe = encargadas; recorta horas cerradas. Clic en celda →
  panel de quién cubre + editar por persona (reusa `fn_set_turno`). Es un tercer
  botón: NO reemplaza Día ni Semana. Doble conteo (operativa+encargada): cuenta
  en ambas, por decisión de Felipe. Diseño afinado con AskUserQuestion.

## 1. 🔴 Alto valor / correctitud

- [x] **`fn_sembrar_ingresos` (el botón masivo) — ELIMINADO 2026-07-18.** Se
  retiró de la pantalla y se hizo `drop` de la función en producción (ver la
  sección "RESUELTO" arriba). Se decidió eliminarlo en vez de ponerle guards
  porque ningún guard lo arreglaba: la "opción segura" de solo-hacia-atrás igual
  habría retrocedido a Estefany/Judith de julio a junio. La fecha de ingreso se
  edita ahora solo persona por persona, con el candado de periodo pagado intacto
  (ese candado vive en `fn_set_fecha_ingreso`, que se conserva).
- [x] **Cobertura EN VIVO en el Dashboard — DESPLEGADO 2026-07-18.** Dentro de la
  tarjeta "Trabajando ahora", por sede: operativas y encargadas EN PISO (solo
  Presente, no en pausa) vs la meta del tramo vigente (corte 14:15), con semáforo
  rojo/verde y "faltan N". Degrada suave si faltan metas o función. Pendiente de
  Felipe: probarlo logueado con datos reales (yo no pude iniciar sesión).

---

## 2. 🟡 Seguridad pendiente (del audit del 15-jul, sin resolver)

Detalle completo en `docs/revision-2026-07-15/00-CHECKLIST-MAESTRO.md`.

- [ ] **PIN del terminal — mitad de servidor** (parche 01). La parte de pedir PIN
  al marcar ya la descartaste ("quita tiempo"). Pero la mitad segura —que el
  servidor valide sesión y sede del terminal— no tiene impacto de UX y sigue sin
  aplicarse. Vale aplicarla sola.
- [ ] **`generarClave()` de cuentas usa `Math.random()`**
  (`api/admin/cuentas/route.ts:13`) — no es criptográficamente seguro. Cambiar a
  `crypto.randomBytes`/`randomInt`. Fácil.
- [ ] **Contraseña mínima de 6 sin complejidad + sin cambio forzado en el primer
  login** para cuentas admin/líder (ven salarios de toda la empresa). Riesgo real.
- [ ] **Las 3 rutas de API devuelven el mensaje crudo de Postgres al cliente** —
  riesgo bajo en panel interno, pero filtra detalles. Envolver en un mensaje
  genérico.
- [ ] **`api/reabrir-dia` no valida que la persona pertenezca a la sede del
  terminal** (corre con service role, bypassa RLS). Misma familia que el PIN.

---

## 3. 🟢 Deuda técnica y pulido

- [ ] **Migraciones 0031 y 0033 no están versionadas** — existen solo como
  `scripts/sql-manual/aplicar_0031_historico_2025.sql` y `aplicar_0033_ingresos_2025.sql`.
  Si algún día reconstruyes la base desde `supabase/migrations/`, esos dos pasos
  faltarían. Copiarlos como `supabase/migrations/0031_*.sql` y `0033_*.sql`.
- [ ] **Split de mañana/tarde configurable por sede** — hoy está fijo en 14:15
  para todas (tu decisión "por ahora"). Cuando una sede necesite otro corte, hay
  que moverlo a `configuracion` o a `metas_cobertura`.
- [ ] **La sugerencia de redistribución de Turnos nombra un candidato pero no
  verifica** que moverlo no cree un hueco donde estaba. Es una pista, no un
  optimizador — está bien así, pero tenlo presente antes de confiar ciego.
- [ ] **`fn_set_horario` / `fn_quitar_horario` (0011/0015) son código muerto** —
  ningún lado del frontend las llama (todo usa `fn_set_horario_semanal`). Pero
  siguen ejecutables por cualquier sesión autenticada y escriben horarios sin el
  candado de periodo pagado. Lo más limpio: hacerles `drop function` (nadie las
  usa). Bajo riesgo, quita superficie de ataque.
- [ ] Código muerto y consistencia menor (dead code, `aria-label` en celdas de
  Turnos, etiqueta "(hora de Perú)" en fechas) — ver lista 🟢 del checklist maestro.

---

## Cómo retomar mañana

Empieza por la sección **0** (tus decisiones, 5 min, desbloquea que la cobertura
de Turnos se vea real). Luego, si quieres un solo proyecto grande, el de más
valor es la **cobertura en vivo del Dashboard** (sección 1). Lo de seguridad
(sección 2) puede ir en paralelo cualquier día tranquilo.

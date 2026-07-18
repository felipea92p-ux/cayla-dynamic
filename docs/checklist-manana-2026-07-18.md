# Checklist para mañana (2026-07-18)

Revisión profunda hecha la noche del 2026-07-17 mientras Felipe no estaba.
**Nada de esto se aplicó ni se desplegó** — es solo análisis. El estado del
repo quedó limpio y sincronizado con GitHub.

Prioridad: 🔴 hazlo primero · 🟡 esta semana · 🟢 cuando haya tiempo.

---

## ⚠️ ADVERTENCIA CRÍTICA sobre el botón "Sincronizar ingresos desde marcas"

**NO usar ese botón en modo masivo.** Reemplaza la fecha de ingreso de TODOS por
su primera marca del terminal — pero el terminal recién arrancó en enero 2026,
así que a las empleadas de 2025 (Carlos, Janis, Sandra, Melany, Danitza,
Joselyn…) les BORRA su antigüedad real: las mueve de 2025 a 2026, perdiendo CTS,
vacaciones y gratificaciones acumuladas. Es plata y derecho real.

El botón SOLO es seguro para una recién ingresada puntual cuya fecha registrada
quedó *después* de su primera marca. Para ese caso, mejor edítala a mano (Equipo
→ editar → el campo muestra la sugerencia de primera marca). **Deuda técnica
anotada abajo: al botón le falta un guard que impida retroceder una fecha de
ingreso más antigua.** Hoy (2026-07-17) todas las fechas están correctas.

---

## 0. TUS DECISIONES (personales, no técnicas — 5 min en total)

Estas no son bugs, son datos que solo tú puedes confirmar. Todas se hacen en
**Equipo → editar a la persona**.

- [x] **Estefany Gómez (13/07) y Judith Pillaca (01/07) — SE QUEDAN ASÍ, a
  propósito.** Decisión de Felipe (2026-07-17): no les corresponde el feriado
  del 29 de junio, por eso su fecha de ingreso arranca en julio y NO en su
  primera marca real (23/06 y 26/06). La fecha de ingreso acá es la fecha desde
  la que corresponden beneficios, no la marca literal. **⚠️ NO usar "Sincronizar
  ingresos desde marcas" sobre ellas** — ese botón las regresaría a junio y les
  metería el feriado que no les toca. Si algún día se corre el botón masivo,
  volver a fijar a estas dos a mano.
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

## 1. 🔴 Alto valor / correctitud

- [ ] **`fn_sembrar_ingresos` (el botón masivo) es peligroso por DOS razones —
  ver también la advertencia crítica arriba.**
  1. **Retrocede antigüedades reales**: pone fecha = primera marca del terminal,
     borrando la fecha 2025 de las empleadas viejas (el terminal arrancó en
     2026). Fix de fondo: que solo actualice cuando la primera marca sea ANTERIOR
     a la fecha registrada (nunca la mueva hacia adelante ni pise una fecha 2025
     con una marca 2026), o mejor, retirar el botón masivo y dejar solo la
     edición por persona.
  2. **Saltea el candado de periodo PAGADO** que `fn_set_fecha_ingreso` sí tiene
     desde 0037 — el día que pagues un mes, este botón podría alterar feriados de
     una planilla cerrada. Agregarle el mismo guard.
- [ ] **Cobertura EN VIVO en el Dashboard** — es el primer pendiente del checklist
  de anoche y ahora tiene todo lo necesario para hacerse bien: ya existe el
  modelo de meta por tramo (mañana/tarde) y `metas_cobertura`. El Dashboard hoy
  muestra "quién está trabajando" pero no "hay 4 operativas ahora en TRU y la
  meta de la tarde es 5". Sería el mayor salto de valor de producto: la encargada
  ve en tiempo real si su sede está corta ESTE momento, sin abrir Turnos.

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

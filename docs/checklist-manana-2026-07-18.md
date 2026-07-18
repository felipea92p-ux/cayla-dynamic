# Checklist para mañana (2026-07-18)

Revisión profunda hecha la noche del 2026-07-17 mientras Felipe no estaba.
**Nada de esto se aplicó ni se desplegó** — es solo análisis. El estado del
repo quedó limpio y sincronizado con GitHub.

Prioridad: 🔴 hazlo primero · 🟡 esta semana · 🟢 cuando haya tiempo.

---

## 0. TUS DECISIONES (personales, no técnicas — 5 min en total)

Estas no son bugs, son datos que solo tú puedes confirmar. Todas se hacen en
**Equipo → editar a la persona**.

- [ ] 🔴 **Estefany Gómez** — fecha de ingreso hoy 13/07/2026, su primera marca
  real es **23/06/2026**. Si la regla es "cuenta desde que marcó" (periodo de
  prueba incluido, que es lo legalmente correcto en Perú), cámbiala a 23/06.
- [ ] 🔴 **Judith Pillaca** — igual: hoy 01/07, primera marca **26/06/2026**.
- [ ] 🟡 **Janis Revilla** — su rol en la base es `admin`, por eso NO cuenta como
  encargada en la cobertura de Turnos. Si su función real es encargada de piso,
  cámbiale el rol a "Líder de equipo (encargada)". **Ojo:** al dejar de ser
  admin pierde acceso a planilla/salarios de toda la empresa y queda limitada a
  su sede. Solo hazlo si eso corresponde a su función.
- [ ] 🟡 **Meta de operativas de TRU = 8/8 es imposible** — tu pico real de gente
  simultánea es 6. Ponla en 5/5 (o 6/6) en la cabecera de cada día en Turnos,
  para que el "% cubierto" refleje tu realidad y no una aspiración inalcanzable.
- [ ] 🟢 **Revisar roles inesperados**: Melany Enriquez figura como
  `supervisor_sede` (en el roster original era integrante) y Catherine Pereyra
  también, con área Comercial y sin horario. Confirmar si son promociones a
  propósito.
- [ ] ✅ **Chiara Flores** — falsa alarma mía: su "02/01/2026" es su primera
  marca (2 de enero). Su fecha está bien, no la toques.

---

## 1. 🔴 Alto valor / correctitud

- [ ] **El botón "Sincronizar ingresos desde marcas" saltea el candado de
  periodo PAGADO.** `fn_sembrar_ingresos` (0027) escribe la fecha de ingreso de
  todos sin verificar `periodos_planilla.estado='pagado'` — a diferencia de
  `fn_set_fecha_ingreso` que sí lo verifica desde el parche 0037. Hoy no explotó
  porque (aparentemente) no hay ningún periodo marcado como pagado todavía. Pero
  el día que pagues un mes y alguien use ese botón, puede alterar en silencio los
  feriados de una planilla ya cerrada. **Fix:** agregar el mismo guard de
  periodo pagado dentro de `fn_sembrar_ingresos` (migración nueva). Bajo riesgo,
  cambio acotado.
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
- [ ] Código muerto y consistencia menor (dead code, `aria-label` en celdas de
  Turnos, etiqueta "(hora de Perú)" en fechas) — ver lista 🟢 del checklist maestro.

---

## Cómo retomar mañana

Empieza por la sección **0** (tus decisiones, 5 min, desbloquea que la cobertura
de Turnos se vea real). Luego, si quieres un solo proyecto grande, el de más
valor es la **cobertura en vivo del Dashboard** (sección 1). Lo de seguridad
(sección 2) puede ir en paralelo cualquier día tranquilo.

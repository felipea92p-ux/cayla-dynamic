# D — Terminal de marcaje + rutas API (revisión 2026-07-15)

Revisión estática de `apps/web/app/(terminal)/*`, `apps/web/app/api/*`,
`apps/web/lib/terminal/*`, `apps/web/lib/admin/use-rol.ts` y
`packages/database/src/client.ts`, cruzando contra las migraciones SQL que
implementan la lógica de escritura (`fn_registrar_marcaje`, RLS). No se
modificó código, no hubo testing contra producción.

Prioridad: 🔴 afecta hoy · 🟡 valioso pronto · 🟢 cuando haya tiempo.

## 🔴 Críticos

- [x] **El PIN del terminal es cosmético: el servidor nunca lo verifica.**
  ✅ **OBSOLETO desde la 0375 (2026-09-05): el PIN del terminal se retiró por
  completo** —mejor que el arreglo que este hallazgo pedía—, y
  `apps/web/lib/terminal/pin.ts` ya no existe. Se deja el hallazgo original
  sin editar, como registro de por qué se decidió así.
  `apps/web/lib/terminal/pin.ts:3-5` hacía `bcrypt.compare` en el NAVEGADOR
  contra el `pin_hash` que `apps/web/lib/terminal/roster.ts:13` descarga junto
  con todo el roster de la sede (y queda cacheado en IndexedDB vía
  `apps/web/lib/terminal/offline-db.ts:33`, store `roster`). El único camino
  real de escritura, `fn_registrar_marcaje`
  (`supabase/migrations/0002_functions.sql:194-307`), en su rama
  `p_origen = 'terminal'` (líneas 224-235) solo comprueba que la sesión sea de
  un terminal activo — nunca recibe ni compara ningún PIN.
  Escenario concreto: con la consola del navegador del kiosko (o interceptando
  la sesión del terminal, que ya está autenticada) se puede llamar
  `supabase.rpc('fn_registrar_marcaje', { p_persona_id: '<cualquier uuid>', ... })`
  directamente y marcar entrada/salida de otra persona sin teclear PIN, incluso
  en una sede con `requiere_pin = true`. Y como el hash viaja al cliente, se
  puede crackear offline sin límite de intentos (un PIN de 4 dígitos son 10,000
  combinaciones — trivial contra bcrypt sin ningún registro server-side de
  intentos fallidos).
  Arreglo: verificar el PIN dentro del RPC `security definer` (comparar server-side,
  nunca exponer `pin_hash` al cliente) y agregar un contador de intentos
  fallidos por persona/terminal en la base de datos.

- [ ] **`fn_registrar_marcaje` no valida que `p_persona_id` pertenezca a la
  sede del terminal que llama.** `supabase/migrations/0002_functions.sql:224-235`
  resuelve `v_sede_id` desde la tabla `terminales`, pero nunca cruza
  `personas.sede_base_id` contra ese valor antes de insertar. Combinado con el
  punto anterior: un terminal de Trujillo ya autenticado puede registrar
  marcajes de una persona de Lima o Arequipa con solo conocer su UUID (que
  tampoco es difícil de obtener, dado que otros endpoints los devuelven).
  Arreglo: agregar `and exists (select 1 from personas where id = p_persona_id
  and sede_base_id = v_sede_id)` en la rama `terminal`.

- [x] **El PIN se apaga solo (fail-open) si falla el refresh de info del
  terminal.** ✅ **OBSOLETO desde la 0375: no hay PIN que apagar.** El campo
  `requierePin` que este hallazgo describe ya no existe en el código —
  `apps/web/app/(terminal)/terminal/marcar/page.tsx` solo conserva un
  comentario histórico donde vivía.
  `apps/web/app/(terminal)/terminal/marcar/page.tsx:100-107` (código ya
  retirado, cita histórica):
  ```
  const fresca = ...navigator.onLine ? await refrescarInfoTerminal() : null;
  const cache = leerInfoTerminalCacheada();
  const info = fresca ?? (cache ? { ...cache, requierePin: false } : null);
  ```
  Si no se puede refrescar la config (sin conexión, o un error puntual de red),
  se usa la caché pero **forzando `requierePin: false`** sin importar el valor
  real cacheado. Una sede que activó el PIN pierde esa protección en cuanto el
  terminal tiene un hipo de red, sin ningún aviso visible. Dado el hallazgo
  anterior el PIN ya era solo cosmético, pero esto muestra que incluso esa capa
  de UI se cae sola. Arreglo: si no hay dato fresco confiable, mantener el
  `requierePin` cacheado tal cual (no forzar `false`).

## 🟡 Importantes

- [ ] **Condición de carrera en `fn_registrar_marcaje` (check-then-insert sin
  lock).** `supabase/migrations/0002_functions.sql:261-271`: la validación de
  "tipo esperado" (`fn_siguiente_tipo_esperado`) lee el estado actual del día y
  luego inserta, sin `select ... for update` ni un índice único parcial que
  impida dos `entrada` o dos `salida_final` el mismo día para la misma
  persona. Con dos llamadas casi simultáneas — doble tap accidental en el
  kiosko, o un reintento del outbox offline (`apps/web/lib/terminal/sync.ts`)
  sincronizando justo cuando la persona vuelve a marcar a mano tras ver la
  pantalla congelada (ver siguiente hallazgo) — ambas pueden pasar la
  validación antes de que la primera confirme, generando filas duplicadas.
  Esto ensucia la auditoría y puede alterar `horas_trabajadas`
  (`fn_recalcular_jornada` en `supabase/migrations/0002_functions.sql:69-172`
  toma la ÚLTIMA `salida_final` del recorrido cronológico, así que una
  duplicada espuria puede pisar la hora real). El mismo patrón, sin ninguna
  protección, existe en `apps/web/app/api/reabrir-dia/route.ts:56-71`: inserta
  directo en `marcajes` sin pasar por `fn_registrar_marcaje` y sin `client_uuid`
  de idempotencia — un doble tap en "Sí, volví a entrar" puede crear dos
  `retorno_otro`. Arreglo: `select ... for update` sobre las marcas del día
  antes de decidir, o un índice único parcial
  `(persona_id, fecha, tipo) where tipo in ('entrada','salida_final')`.

- [ ] **Sin `try/catch` alrededor del RPC online: una excepción de red pierde
  el marcaje en silencio.** `apps/web/app/(terminal)/terminal/marcar/page.tsx:282-298`
  (`confirmarMarcaje`). El estado optimista (`marcajesHoyRef.current`, líneas
  276-280) se aplica ANTES de intentar la llamada. `navigator.onLine` solo
  indica que hay una interfaz de red activa, NO que haya internet real (wifi
  de tienda con el router caído, muy plausible en las 3 sedes). Si esa
  condición es `true` pero el `fetch` interno de `supabase.rpc(...)` lanza una
  excepción en vez de devolver `{ error }`, la función se corta antes de
  `encolarMarcaje` (línea 295): el marcaje no llega al servidor NI queda en el
  outbox offline, mientras el estado local ya lo da por hecho. La pantalla
  queda congelada en "Confirmando…" sin mensaje de error; si la persona se va
  sin tocar "Cancelar" el kiosko se bloquea para el siguiente, y el marcaje se
  pierde sin dejar rastro en ningún lado. Arreglo: envolver la llamada en
  `try/catch` y, ante cualquier excepción (no solo un `error` de respuesta),
  caer al mismo camino de `encolarMarcaje` que usa el modo offline.

- [ ] **Los marcajes que fallan 6 veces en el outbox se descartan sin avisar a
  nadie.** `apps/web/lib/terminal/sync.ts:27-38`. El comentario reconoce que
  esto es "un rechazo permanente" (día ya cerrado, sesión vencida, etc.), pero
  `eliminarDeOutbox` borra la entrada sin dejar ningún rastro server-side ni
  notificar a la persona ni a la encargada. Combinado con el hallazgo anterior
  (marcajes que ni siquiera llegan a encolarse), el personal puede terminar el
  día creyendo que marcó, sin que exista registro ni en el outbox ni en el
  servidor. Arreglo: antes de descartar, insertar en la tabla `alertas` (ya
  existe, hoy sin uso — ver `docs/checklist-pendientes.md`) o loguear a un
  endpoint que la encargada pueda revisar.

- [ ] **`api/reabrir-dia` no verifica que `personaId` pertenezca a la sede del
  terminal que llama.** `apps/web/app/api/reabrir-dia/route.ts:23-30` valida
  que el token sea de un terminal activo, pero la query solo trae
  `id, activo` (no `sede_id`) y el resto del handler (líneas 33-77) usa
  `personaId` —dato puesto por el cliente en el body— sin cruzarlo contra la
  sede de ese terminal. Como corre con `SUPABASE_SERVICE_ROLE_KEY` (bypassea
  RLS por completo), un terminal de cualquier sede puede reabrir el día de una
  persona de otra sede. Afecta el cálculo de horas/planilla de gente que ese
  terminal no debería poder tocar. Arreglo: seleccionar también `sede_id` en
  la query de la línea 24-27 y comparar contra
  `select sede_base_id from personas where id = personaId`.

- [ ] **`fn_registrar_marcaje` no valida `personas.estado = 'activo'`.**
  `supabase/migrations/0002_functions.sql:194-307` no comprueba en ningún
  punto el estado de la persona. La pantalla de selección sí filtra activos
  (RLS `personas_select_terminal_roster`,
  `supabase/migrations/0003_rls.sql:74-76`), pero el roster cacheado en
  IndexedDB puede quedar desactualizado si el terminal estuvo offline durante
  una baja, y como la escritura real es `security definer` (bypassea RLS),
  alguien desactivado —o cuyo UUID quedó en el caché local o se conoce por
  otra vía— puede seguir generando marcajes válidos indefinidamente. Ensucia
  planilla/horas de alguien que ya no debería estar siendo pagado. Arreglo:
  agregar `and estado = 'activo'` al validar `p_persona_id` dentro del RPC.

- [ ] **Las 3 rutas de API devuelven el mensaje crudo de Postgres/Supabase al
  cliente.** `apps/web/app/api/admin/cuentas/route.ts:82,91,102,104,110`,
  `apps/web/app/api/reabrir-dia/route.ts:60,71,75`,
  `apps/web/app/api/espejo/route.ts:80` hacen todas `error.message` / `e.message`
  directo en la respuesta JSON. En un panel interno el riesgo es bajo, pero
  puede filtrar nombres de columnas/constraints internos, y no queda un log
  server-side separado del mensaje que ve quien usa el panel. Arreglo:
  `console.error` del detalle completo server-side, devolver un mensaje
  genérico al cliente.

- [ ] **`api/espejo` usa la propia `SUPABASE_SERVICE_ROLE_KEY` como el secreto
  compartido con Google Apps Script.** `apps/web/app/api/espejo/route.ts:15`:
  `if (!token || token !== SERVICE) ...`. La misma llave que da acceso total a
  la base de datos (bypass de RLS) tiene que vivir también dentro del script
  de Google que llama a este endpoint. Si ese script se comparte, se exporta,
  o alguien con permiso de "ver" el editor de Apps Script mira las
  propiedades del proyecto, se lleva la llave maestra completa de Supabase —no
  solo acceso de lectura al espejo de asistencia. La comparación además usa
  `!==` (no constant-time; riesgo menor dado el contexto). Arreglo: generar un
  secreto propio y aleatorio solo para este puente, guardarlo en su propia env
  var, y no reutilizar `SUPABASE_SERVICE_ROLE_KEY` fuera del servidor Next.js.

- [ ] **`generarClave()` usa `Math.random()` para contraseñas de cuentas
  admin/lider_do/supervisor_sede.** `apps/web/app/api/admin/cuentas/route.ts:11-15`.
  `Math.random()` no es un PRNG criptográfico. No es grave para una clave
  temporal de un solo uso, pero es un antipatrón fácil de evitar. Arreglo:
  `crypto.getRandomValues()` en vez de `Math.random()`.

## 🟢 Menor / cuando haya tiempo

- [ ] **Ninguna de las 3 rutas ni el RPC de marcaje tiene rate limiting
  propio** — se depende enteramente de los límites por defecto de Supabase
  Auth/Vercel. Con el PIN cosmético (hallazgo 🔴 arriba) esto importa menos
  hoy, pero conviene agregarlo si se llega a depender del PIN de verdad.
- [ ] **Roster cacheado en IndexedDB puede sobrevivir a un cambio de estado**
  — mismo trasfondo que el hallazgo de `estado activo`: si el terminal está
  offline cuando se desactiva a alguien, esa persona sigue apareciendo en la
  grilla para marcar hasta el próximo `cargarRoster()` exitoso.
  (`apps/web/lib/terminal/roster.ts:5-18`)
- [ ] **`vincular/page.tsx` depende solo del throttling nativo de Supabase
  Auth** para el login de terminal
  (`apps/web/app/(terminal)/terminal/vincular/page.tsx:22`, `signInWithPassword`)
  — no hay bloqueo ni aviso propio de la app ante intentos repetidos con la
  cuenta del dispositivo. Riesgo bajo (son credenciales de dispositivo, no de
  persona), pero sin visibilidad si alguien las está probando.

## ✅ Verificado sin hallazgos

- **Aislamiento de sesión terminal vs. admin.**
  `packages/database/src/client.ts:16-35` usa un `storageKey` distinto
  (`cayla-auth-terminal` vs `cayla-auth-admin`) por cliente Supabase, cacheado
  por key en el módulo. Grep confirma que ningún archivo bajo
  `apps/web/app/(terminal)` o `apps/web/lib/terminal` importa
  `createAdminSupabaseClient`/`createServiceRoleClient`, y ningún archivo bajo
  `apps/web/app/(admin)` importa `createTerminalSupabaseClient`. La
  separación se respeta en todo el código actual.
- **`apps/web/lib/admin/use-rol.ts` — ventana de rol stale.** El hook arranca
  en `null` y `apps/web/app/(admin)/admin/nav.tsx:44` filtra los links con
  `rol !== null && l.roles.includes(rol)`: mientras carga el rol real
  (round-trip al servidor) el menú NO muestra opciones restringidas por
  defecto — falla cerrado, no abierto. No se encontró ninguna pantalla que
  asuma un rol antes de que la consulta resuelva. La protección real de todos
  modos sigue siendo RLS en Postgres (cualquier fetch de datos falla si el rol
  no califica), así que un eventual bug de UI aquí sería cosmético, no una
  fuga de datos real.
  Nota aparte (fuera de alcance estricto, pero relacionada): `equipo/page.tsx`
  (`apps/web/app/(admin)/admin/equipo/page.tsx:208,352`) hashea el PIN con
  bcrypt costo 10 en el navegador, no en el servidor — mismo patrón de "hash
  generado del lado cliente" que el hallazgo 🔴 principal de este documento;
  vale la pena revisarlo junto con la corrección del RPC de marcaje.
- **Inyección SQL en las 3 rutas de API.** Todas usan el query builder de
  `@supabase/supabase-js` (`.eq()`, `.select()`, `.in()`, `.update()`,
  `.insert()`) con valores pasados como parámetros — no se encontró
  concatenación de strings hacia SQL crudo ni interpolación directa de input
  de usuario en ninguna consulta.
- **CORS/métodos.** Ninguna ruta define headers CORS propios: no hace falta,
  `api/admin/cuentas` y `api/reabrir-dia` los llama el propio front Next.js
  same-origin, y `api/espejo` lo llama Google Apps Script server-to-server
  (sin contexto de navegador, sin preflight). `apps/web/next.config.ts` no
  define headers ni hay middleware que abra CORS de más. Métodos no
  soportados devuelven 405 por comportamiento default del App Router (cada
  route solo exporta el método que implementa).
- **`api/admin/cuentas` sigue el patrón de referencia correctamente.**
  Bearer token → `admin.auth.getUser(token)` → chequeo de `rol` en `personas`
  en cada request (`apps/web/app/api/admin/cuentas/route.ts:33-40`) — no
  confía en ningún id que mande el cliente para decidir permisos. Es la única
  de las tres rutas que re-verifica identidad Y rol completos en cada
  llamada; las otras dos (`reabrir-dia`, `espejo`) verifican identidad pero no
  acotan recursos por sede/alcance (ver hallazgos 🟡 arriba).

---
Alcance: `apps/web/app/(terminal)/**`, `apps/web/app/api/**`,
`apps/web/lib/terminal/**`, `apps/web/lib/admin/use-rol.ts`,
`packages/database/src/client.ts`, y las migraciones
`supabase/migrations/0001_init.sql`, `0002_functions.sql`, `0003_rls.sql`,
`0012_terminal_requiere_pin.sql`. Sin cambios de código, sin testing contra
producción — análisis 100% estático.

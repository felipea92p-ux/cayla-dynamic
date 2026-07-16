# Auditoría de seguridad — límites entre roles/superficies (2026-07-15)

Revisión independiente centrada en el "perímetro" de seguridad: quién puede llamar
qué, dónde vive cada secreto, y qué pasa si algo se filtra o se llama fuera de
guion. Complementaria a la revisión de SQL/RLS y a la de frontend — no repite su
detalle fila por fila, pero cruza hallazgos donde aplica.
Formato igual que `docs/checklist-pendientes.md`. Prioridad: 🔴 arregla ya
(datos reales en riesgo hoy) · 🟡 arregla pronto · 🟢 cuando haya tiempo.
No se modificó ningún archivo del proyecto ni se corrió nada contra producción;
todo esto es lectura de código.

## 🔴 Crítico

- [ ] **El PIN del terminal no protege nada de verdad — se puede marcar
  asistencia como cualquier compañera (buddy punching), y potencialmente de
  OTRA sede.** `apps/web/lib/terminal/roster.ts:11-14` trae el `pin_hash`
  (bcrypt) de TODA la gente activa de la sede hacia el navegador del terminal
  compartido, y encima `apps/web/lib/terminal/offline-db.ts:33` lo persiste en
  IndexedDB del dispositivo (para modo offline) — el hash de cada PIN queda
  guardado en el kiosko, no solo de paso. La verificación
  (`apps/web/lib/terminal/pin.ts:3-5`, `bcrypt.compare`) corre 100% en el
  navegador; el contador de "5 intentos" (`marcar/page.tsx:157-164`) es un
  `useState` de React, no algo que el servidor exija.
  El problema de fondo: `fn_registrar_marcaje` (RPC que de verdad escribe el
  marcaje, `supabase/migrations/0002_functions.sql:194-307`) **no recibe PIN
  como parámetro** y, para `p_origen='terminal'`, solo valida que el
  `terminal_id` exista/esté activo — nunca valida que `p_persona_id`
  pertenezca a la sede de ese terminal. Es decir: el PIN es un candado de
  cartón que ni siquiera el propio backend conoce.
  **Escenario de explotación:** cualquiera con acceso al navegador del
  terminal físico (que por diseño es un kiosko compartido) abre DevTools →
  Console y llama directo `supabase.rpc('fn_registrar_marcaje', {p_persona_id:
  '<uuid de cualquier compañera, incluso de otra sede>', p_tipo: 'entrada', ...})`
  — sin PIN, sin pasar por la UI. O, más simple aún: extrae el `pin_hash` de
  IndexedDB/Network y hace fuerza bruta offline sobre 10,000 combinaciones de
  4 dígitos (trivial, sin límite de intentos del lado servidor). El resultado
  en ambos casos son marcajes falsos que alimentan directo `horas_trabajadas`
  → planilla (pago real) y `minutos_tarde` → el futuro módulo disciplinario de
  tardanzas.
  Nota de contexto: hoy `requiere_pin=false` en las 3 sedes
  (`marcar/page.tsx:145`, comentario "Hoy las 3 sedes están sin PIN"), así que
  el impacto INMEDIATO es bajo (ya se marca solo tocando el nombre). Pero el
  hueco de `fn_registrar_marcaje` sin validar sede — y el diseño de PIN
  client-side — quedan ahí listos para el día que se reactive el PIN pensando
  que sí protege.
  **Arreglo sugerido:** mover la verificación de PIN al servidor: una función
  `security definer` que reciba `p_persona_id` + `p_pin` y solo entonces deje
  llamar a `fn_registrar_marcaje` (o que el propio `fn_registrar_marcaje`
  reciba el PIN como parámetro opcional y lo verifique con `pgcrypto`/`bcrypt`
  vía extensión de Postgres cuando `terminales.requiere_pin=true`). Nunca
  enviar `pin_hash` al cliente. Además, agregar a `fn_registrar_marcaje` la
  validación de que `p_persona_id` pertenece a la sede del terminal (o tiene
  `visible_todas_sedes=true`), igual que ya se hace para el camino no-terminal
  con `supervisor_sede`.

- [ ] **La llave `service_role` de Supabase (bypassea RLS + Auth admin
  completo) vive fuera del control de Vercel/Supabase y se reusa como
  "contraseña" de un endpoint.** Dos puntos:
  1. `scripts/espejo-sheets.gs:6,16` guarda la llave real `service_role` en
     "Propiedades del script" de Google Apps Script y la manda como header
     `apikey`/`Authorization: Bearer` directo a PostgREST de Supabase, desde
     infraestructura de Google, en un disparador que corre cada hora. La única
     protección declarada es el comentario "Mantén esta hoja PRIVADA" — un
     control humano/organizacional, no técnico.
  2. `apps/web/app/api/espejo/route.ts:14-15` compara el header
     `Authorization` entrante literalmente contra `SERVICE` (la llave real) —
     esa llave hace doble función de "secreto maestro de la base" y de
     "contraseña compartida" para este puente hacia Sheets.
  **Escenario de explotación:** si esa llave se filtra por CUALQUIER vía
  (exportar/copiar el Apps Script, compartir por error el acceso al proyecto
  de Apps Script o a la hoja, una captura de pantalla, un log que la imprima),
  quien la obtenga tiene lectura/escritura TOTAL de toda la base (salarios,
  PINs hasheados, todo) sin pasar por RLS, y además puede usar
  `supabase.auth.admin.*` para crear o resetear la contraseña de CUALQUIER
  cuenta, incluida `admin`. Es un radio de explosión mucho mayor que "alguien
  vio el espejo de Sheets".
  Nota: `apps/web/app/api/espejo/route.ts` parece pensado como el puente
  oficial ("El Apps Script llama aquí"), pero el `.gs` committeado en
  `scripts/espejo-sheets.gs` en realidad llama DIRECTO a PostgREST, sin pasar
  por `/api/espejo` — vale la pena que Felipe confirme cuál de los dos está
  realmente corriendo en la hoja de producción.
  **Arreglo sugerido:** no usar la llave `service_role` real como credencial
  del puente a Sheets. Generar un secreto propio y de bajo privilegio
  (variable de entorno separada tipo `ESPEJO_TOKEN`) solo para
  `/api/espejo`, y mover `espejo-sheets.gs` a llamar exclusivamente esa ruta
  (nunca PostgREST directo con `service_role`). Rotar la llave `service_role`
  actual dado que ya circuló por Apps Script.

- [ ] **PII real de empleados committeada al repo, fuera del patrón de
  `.gitignore` que el propio proyecto ya usa para esto.** El `.gitignore`
  excluye correctamente `scripts/datos-privados/` (correos reales) y los SQL
  de histórico 2025 con datos reales — ese patrón SÍ se respeta ahí. Pero
  quedaron afuera:
  - `scripts/setup-personas-prod.mjs:21-46` — el roster COMPLETO real (~20
    personas, nombres y apellidos) de las 3 sedes, más un correo personal real
    (línea 23) y un correo corporativo (línea 35), en texto plano, en un
    archivo trackeado por git.
  - `scripts/migracion-historica/roster-actual.json` — nombres+apellidos+sede
    reales de todo el equipo, trackeado.
  - `scripts/migracion-historica/importar-turnos-tru.mjs` (y nombres también
    en `reimportar-lim-aqp.mjs`) — nombres reales atados a horarios de turno.
  No se encontraron salarios ni PINs reales committeados (esos solo se generan
  en runtime o se ingresan desde el panel — buena higiene ahí).
  **Por qué importa ahora:** `docs/checklist-pendientes.md` tiene pendiente
  "Subir el código a GitHub" — en el momento en que eso pase, estos nombres +
  ese correo personal quedan en el historial de un repo remoto para siempre
  (solo se limpia reescribiendo historia). Y, aparte de GitHub: esta carpeta
  del proyecto vive dentro de iCloud Drive
  (`.../Mobile Documents/com~apple~CloudDocs/...`), así que el `.git` con este
  contenido YA está sincronizando hacia la infraestructura de Apple y hacia
  cualquier otro dispositivo con la misma cuenta de iCloud — independiente de
  si algún día se sube a GitHub.
  El patrón correcto ya existe en el propio repo: `actualizar-correos-prod.mjs`
  y `crear-cuentas-encargadas.mjs` leen los correos desde
  `scripts/datos-privados/correos.json` (gitignorado) en vez de tenerlos en
  el código — `setup-personas-prod.mjs` y los scripts de migración histórica
  simplemente no siguieron ese mismo patrón.
  **Arreglo sugerido:** antes de subir a GitHub, mover el `ROSTER` de
  `setup-personas-prod.mjs` (y los mapas nombre→horario de los scripts de
  migración) a un JSON en `scripts/datos-privados/` como ya se hace con los
  correos, y purgar del script el correo personal hardcodeado. Si el repo ya
  tiene commits con esto y se sube tal cual, evaluar reescritura de historia
  (`git filter-repo` o similar) antes del push inicial — después de subido es
  mucho más costoso.

## 🟡 Pronto

- [ ] **Política de contraseña débil para cuentas admin/líder DO** (ven
  salarios de toda la empresa y pueden resetear la clave de cualquiera).
  `apps/web/app/(admin)/admin/nueva-clave/page.tsx:43` y
  `apps/web/app/(admin)/admin/cuentas/page.tsx:80` solo exigen
  `length >= 6`, sin ningún requisito de complejidad — "111111" o "abcdef"
  pasan. Es el único candado (Supabase Auth no impone una política más
  estricta salvo que se configure). **Sugerido:** subir el mínimo (10-12
  caracteres) y/o una validación básica de fuerza, al menos para roles
  admin/lider_do.

- [ ] **Varias funciones `security definer` (o de escritura sensible) no
  tienen `revoke execute from public` explícito**, a diferencia del patrón
  disciplinado que sí se usa desde la migración 0020 en adelante
  (`grant ... to authenticated; revoke ... from public, anon;`). Postgres
  otorga `EXECUTE` a `PUBLIC` por defecto al crear una función, así que sin el
  revoke explícito, cualquier rol autenticado (o `anon`, si hereda de
  `PUBLIC`) puede invocarlas directo por RPC:
  - `fn_auto_cierre()` (`supabase/migrations/0007_auto_cierre.sql:38-110`) —
    es `security definer` (corre con privilegios elevados, bypassea RLS) y no
    valida quién la llama ni tiene grant/revoke explícito. Hoy el impacto es
    bajo porque su lógica interna solo actúa sobre jornadas que YA cruzaron el
    umbral de horas configurado (llamarla antes de tiempo no cierra nada que
    no fuera a cerrar el cron de todos modos), pero sigue siendo una función
    con bypass de RLS alcanzable por cualquiera con sesión.
  - `fn_recalcular_jornada()` (redefinida en 0002, 0009, 0013, 0014, 0016,
    0017) — no es `security definer` pero tampoco tiene revoke; hoy es
    inofensiva porque `jornadas` no tiene policies de INSERT/UPDATE/DELETE
    para `authenticated` (deniega por defecto), así que cualquier escritura
    que intente falla por RLS. Pero esto depende de que esa ausencia de
    policy se mantenga así para siempre — el día que una migración futura le
    agregue una policy de escritura a `jornadas` por otro motivo, esta función
    vuelve a quedar abierta a cualquier usuario autenticado sin que nadie lo
    note.
  **Sugerido:** pasada de blindaje: `alter default privileges in schema
  public revoke execute on functions from public;` para que toda función
  nueva nazca cerrada por defecto, y agregar `revoke execute ... from public,
  anon;` explícito a las funciones listadas arriba (además de
  `fn_siguiente_tipo_esperado` en su forma original de 0002, aunque hoy solo
  la usa `fn_registrar_marcaje` internamente).

- [ ] **Contraseñas temporales sin expiración de uso ni cambio forzado.**
  `apps/web/app/api/admin/cuentas/route.ts` (`generarClave()`, líneas 11-15)
  genera contraseñas con buena entropía (1 mayúscula + 5 minúsculas + 4
  dígitos), y `cuentas/page.tsx:170-174` las muestra una sola vez en pantalla
  — hasta ahí razonable para el flujo "mostrar una vez para poder pasarla".
  Pero: (a) queda en el estado de React sin temporizador de auto-ocultado
  mientras la página siga abierta, (b) no hay ningún mecanismo que obligue a
  cambiarla en el primer login. Si se relaya por un canal no cifrado en texto
  plano (el propio texto de la UI sugiere "cópiala y pásasela", probablemente
  WhatsApp) y la persona nunca la cambia, esa clave queda como credencial
  permanente conocida por quien la envió. **Sugerido:** agregar un flag
  `debe_cambiar_clave` que fuerce el flujo de cambio de contraseña en el
  primer login exitoso.

## 🟢 Para cuando haya tiempo

- [ ] **`createServiceRoleClient()` (`packages/database/src/client.ts:42-47`)
  es código muerto.** Está bien documentado ("nunca importar este módulo
  desde código que corre en el navegador") pero un grep de todo el repo
  muestra CERO imports — las tres rutas que sí necesitan la llave de servicio
  (`api/admin/cuentas`, `api/espejo`, `api/reabrir-dia`) construyen su propio
  `createClient(URL, SERVICE)` inline en vez de usar el helper centralizado.
  No es un hueco de seguridad (las tres siguen siendo server-only, dentro de
  `app/api/*`), pero el "único punto auditado" que sugiere el comentario no es
  realmente el único punto — es aspiracional. Vale la pena que las 3 rutas
  importen el helper real, así hay un solo lugar que tocar/auditar si algún
  día cambia el patrón de credenciales.

- [ ] **Confirmado sin hallazgos — vars `NEXT_PUBLIC_*`:** el único uso de
  `NEXT_PUBLIC_SUPABASE_URL` y `NEXT_PUBLIC_SUPABASE_ANON_KEY` en todo
  `apps/web`/`packages` es exactamente ese (ninguno sensible por diseño:
  la anon key está sujeta a RLS). `SUPABASE_SERVICE_ROLE_KEY` nunca aparece
  con prefijo `NEXT_PUBLIC_`, y ningún archivo `"use client"` referencia una
  var de entorno no pública. Limpio.

- [ ] **Confirmado sin hallazgos — CSRF/replay:** la app deliberadamente no
  usa `@supabase/ssr` ni cookies de sesión (comentario en
  `packages/database/src/client.ts:10-11`); la sesión vive en `localStorage`
  bajo claves separadas por superficie. Toda llamada que cambia estado (RPC de
  Supabase o las 3 rutas de `app/api/*`) exige un header `Authorization:
  Bearer <token>` puesto explícitamente por JS — no hay credencial ambiental
  que un sitio malicioso pueda hacer que el navegador adjunte solo. Esto
  significa que CSRF clásico no aplica a ninguna de las superficies
  revisadas; no hace falta agregar un token CSRF encima (agregar uno sin
  necesidad solo sería trabajo extra). `fn_registrar_marcaje` además tiene
  idempotencia por `client_uuid` contra reintentos/replays de red. Único
  detalle menor: `api/espejo/route.ts` es un GET protegido solo por el header
  `Authorization` (ver hallazgo 🔴 de la llave `service_role`) y no fija
  `Cache-Control: no-store` — no es explotable por CSRF, pero conviene el
  header igual para que ningún proxy/CDN intermedio cachee por error una
  respuesta con datos de asistencia de toda la empresa.

- [ ] **Confirmado sin hallazgos — scoping por sede en funciones
  `security definer` (cruce con la revisión de RLS):** revisión completa de
  las 30 migraciones. Todo lo que es exclusivo de admin/lider_do (planilla,
  salarios, provisiones, feriados, áreas, periodos, movimientos, objetivos,
  bono de puntualidad) verifica `fn_es_admin_o_lider() is not true` antes de
  devolver o tocar nada — y como `supervisor_sede` nunca pasa ese check, no
  hace falta (ni falta) un filtro extra por sede ahí. Todo lo que SÍ debe ser
  alcanzable por `supervisor_sede` (`fn_verificar_corrector` y lo que se
  apoya en ella: corregir/agregar/eliminar marcaje, turnos, horarios;
  `fn_personas_funciones`, `fn_jornadas_extra`, el checklist de objetivos)
  filtra correctamente por `sede_base_id = fn_sede_actual_persona()`,
  replicando las policies de RLS. Mención aparte al diseño de
  `fn_planilla_calcular` (`0025_planilla_periodos.sql:346-520`): es el
  "núcleo" con `revoke execute ... from public, anon, authenticated` — nadie
  lo llama directo — y solo se accede vía dos wrappers (`fn_proyeccion_periodo`,
  `fn_simular_planilla`) que sí exigen admin/lider_do. Es un patrón sólido de
  "núcleo privado + wrapper público con guardia", vale la pena reusarlo para
  las funciones del hallazgo 🟡 de arriba.

---
Alcance cubierto: `packages/database/src/client.ts` y todos sus imports;
`NEXT_PUBLIC_*` vs. vars privadas en todo `apps/web`; las ~90 definiciones de
función en `supabase/migrations/*.sql` (con foco en las `security definer` y
en el scoping por sede); `scripts/*.mjs`, `scripts/migracion-historica/*.mjs`,
`scripts/sql-manual/*.sql` y `scripts/espejo-sheets.gs`; el flujo de
recuperación/reseteo de clave (`olvide-clave`, `nueva-clave`,
`api/admin/cuentas`, `cuentas/page.tsx`); y CSRF/replay en las 3 rutas de
`app/api/*` y en las RPC de escritura. No cubierto a fondo (fuera del
encargo): fuerza bruta sobre el login de Supabase Auth en sí, cabeceras HTTP
de seguridad (CSP/HSTS) a nivel de Vercel, ni dependencias de terceros
(`npm audit`).

# CAYLA Dynamic — App de asistencia (reemplazo del Google Form)

## Contexto

CAYLA registra la asistencia de ~20-30 integrantes (creciendo) en 3 sedes (TRU, LIM, AQP) mediante un Google Form que escribe a una hoja de cálculo ("Dynamic"). Esa asistencia alimenta directamente el cálculo de remuneraciones, así que la precisión importa mucho. El proceso actual tiene dos fallas recurrentes: la gente olvida marcar su salida, y a veces marca dos veces. Este plan reemplaza el Form por una app propia (kiosco de marcaje + panel admin + app personal opcional), pensada para eliminar estructuralmente esos dos problemas en vez de parchearlos.

Este plan surge de ~28 preguntas de descubrimiento respondidas por el founder, más una validación técnica de costos/límites vigentes (julio 2026) de Supabase, Vercel, Expo/EAS, Apple y Google Sheets API.

## Decisiones ya tomadas con el founder

- **Timeline**: versión reducida (Sprint 0+1) lista antes del cierre de planilla de fin de julio 2026; el resto (panel admin completo, alertas push, espejo Sheets, app personal) se construye en las semanas siguientes.
- **Costos**: tier gratuito de Supabase y Vercel durante desarrollo/pruebas; se sube a Supabase Pro ($25/mes) y Vercel Pro ($20/mes) recién en el lanzamiento real (coincide con el cierre de julio, cuando el sistema empieza a alimentar planilla de verdad).
- **Roster por kiosco**: acotado solo a la sede de ese kiosco (nadie más que el founder viaja entre sedes) — sin buscador cruzado entre sedes.
- **Ubicación del proyecto**: nuevo repo en `~/Proyectos/cayla-dynamic`, independiente de la carpeta de inversiones actual.
- **Sin cuenta Apple Developer todavía**: se desarrolla y prueba gratis vía Expo Go; los $99/año recién se necesitan para distribuir la versión pulida (TestFlight/App Store), no bloquea nada del desarrollo.
- Nombre de la app: se mantiene **"Dynamic"**.

## Arquitectura (3 superficies, 1 backend)

1. **Kiosco de marcaje** — web app (Next.js) corriendo en pantalla completa en el dispositivo fijo que ya tiene cada sede (Mac mini/laptop/tablet). Flujo: nombre (lista corta de su sede) → PIN de 4 dígitos → la app decide sola si es Entrada/Salida (o el tipo de salida temporal correspondiente) según el estado abierto de esa persona hoy → confirmación cancelable de 3 segundos. Sin biometría, sin GPS (confirmado innecesario). Offline-first: si no hay internet, encola local y sincroniza después.
2. **Panel de administración** — mismo Next.js, otra sección de rutas. Roles: `admin`/`lider_do` (acceso total, todas las sedes, ven tarifas) y `supervisor_sede` (solo su sede). Gestión de roster, horarios, tarifas por persona, correcciones manuales con auditoría, dashboard en vivo, reportes.
3. **App personal (opcional, Expo/iOS+Android)** — no marca asistencia; solo notificaciones push (recordatorio de salida, aviso de auto-cierre) y ver su propio historial de horas.

**Backend: Supabase** (Postgres + Auth + Realtime + Edge Functions + `pg_cron`). Un solo vendor cubre DB, roles vía RLS, cron para el auto-cierre, y Edge Functions para el espejo a Sheets. Límites free tier (verificados) sobran para 20-30 personas; se sube a Pro ($25/mes) en el lanzamiento para evitar la pausa automática por 7 días de inactividad (riesgo real en un sistema que alimenta planilla).

**Hosting web: Vercel** (Hobby durante desarrollo interno; se sube a Pro $20/mes en el lanzamiento — el ToS de Hobby excluye uso organizacional, y además Hobby tiene timeout de 10s insuficiente para generar reportes PDF/Excel).

**Monorepo**: pnpm workspaces + Turborepo, para compartir tipos y la lógica de estado de asistencia entre el web app y la app Expo.

## Modelo de datos (Postgres, zona horaria fija `America/Lima`)

- `sedes` — TRU/LIM/AQP.
- `personas` — nombres, sede_base, rol (integrante/supervisor_sede/lider_do/admin), estado (activo/inactivo), pin_hash.
- `horarios_asignados` — versionado por persona: hora_entrada, hora_salida, ventana de almuerzo (45-75 min), horas_semana_objetivo (45h full-time). Editable desde el panel admin.
- `tarifas_hora` — versionado por persona (tarifa en soles), admin-editable manualmente. Existe desde el día 1 aunque el cálculo de pago sea Fase 2.
- `kiosks` — un registro por dispositivo fijo, atado a una sede (así el sede del marcaje viene del kiosco, no del perfil de la persona — resuelve el caso del founder viajando entre sedes sin UI extra).
- `marcajes` — log crudo append-only, **fuente de verdad real**: persona, sede, kiosco, tipo (entrada/salida_final/salida_almuerzo/retorno_almuerzo/salida_personal/retorno_personal/salida_tramite/retorno_tramite/salida_medico/retorno_medico/salida_otro+motivo/retorno_otro), timestamp del cliente, `client_uuid` único (idempotencia para reintentos offline), origen (kiosco/corrección/auto_cierre/import_histórico).
- `jornadas` — resumen derivado por persona/día (mantenido por trigger sobre `marcajes`): minutos_tarde (exacto, **sin tolerancia fija** — se registra el minuto real, sin regla de gracia por sede/rol), horas_trabajadas, estado (abierta/cerrada/auto_cerrada_pendiente/revisada).
- `correcciones_auditoria` — toda edición manual: quién, qué campo, valor anterior/nuevo, motivo obligatorio.
- `push_tokens`, `alertas`, `google_sheets_sync_queue`.

Toda escritura de marcaje pasa por una única función Postgres `fn_registrar_marcaje(...)` — nunca insert directo desde el cliente. Esa función contiene la lógica de "¿es entrada o salida?" y la reconciliación de escrituras offline tardías contra un auto-cierre que ya haya corrido (ver siguiente sección).

## Reglas de negocio clave a implementar

- **Doble marcado**: se previene estructuralmente — el kiosco nunca deja elegir "entrada" o "salida" a mano, la decide el estado abierto/cerrado de esa persona. No hay un "código de detección de duplicado" aparte; es la máquina de estados la que lo resuelve.
- **Olvido de marcar salida**: push de recordatorio cerca de la hora de salida programada; si sigue sin marcar tras N horas (configurable, default 3h), auto-cierre con `estado_revision = pendiente_revision` para que un supervisor lo confirme.
- **Caso conflictivo a manejar explícitamente**: si el kiosco estuvo offline y el marcaje real de salida llega después de que el cron ya auto-cerró esa jornada, `fn_registrar_marcaje` debe **reemplazar** el registro sintético de auto-cierre con el real, no crear dos filas de salida para el mismo día.
- **Horas extra**: requieren aprobación previa del supervisor, se pagan a la misma tarifa base (sin plus) — Fase 2, pero el dato de "horas_extra_detectadas" ya se calcula en Fase 1 para no migrar el esquema después.
- **Multi-sede del founder**: resuelto por diseño (sede viene del kiosco tocado, no del perfil) — sin necesidad de un selector de sede en la UI.

## Sincronización offline del kiosco

IndexedDB con un `outbox` de marcajes no confirmados (client_uuid como idempotency key) + un `roster_cache` de la sede. Reintento por eventos `online`/`offline` más un flush periódico. La lógica de "¿qué toca marcar ahora?" vive en un módulo TypeScript compartido (`packages/shared/attendance-state-machine.ts`) usado igual en el cliente offline y reflejado en la función SQL del servidor.

## Espejo en tiempo real a Google Sheets

Un Database Webhook sobre `marcajes`/`jornadas` encola cambios; una Edge Function programada (cada 30-60s) los agrupa en **una sola llamada `batchUpdate`** por corrida — muy por debajo de la cuota de Google (60 req/min/usuario). La hoja de Sheets es solo un espejo de lectura cómodo, **nunca la fuente de verdad**. La importación histórica masiva (ver abajo) queda explícitamente excluida de este pipeline para no arriesgar la cuota.

## Migración del historial (3 archivos actuales)

Script único en `scripts/migracion-historica/`, corrido primero contra un proyecto Supabase de **staging**, nunca directo a producción:
1. Parsear los 3 archivos, normalizar nombres para detectar duplicados entre archivos.
2. Generar un CSV de coincidencias ambiguas para que el founder las confirme a mano (no auto-fusionar en silencio, dado que esto afecta reportes de pago).
3. Construir el roster canónico; quienes ya no continúan quedan `estado = inactivo` (nunca se borran), conservando su historial para reportes de periodos pasados.
4. Convertir filas históricas en `marcajes` con `origen = import_historico` (solo entrada/salida_final; las categorías de salida temporal son nuevas, no existen en el histórico — esperado).
5. Revisar un resumen en staging con el founder antes del corte final a producción.

## Roadmap por fases

**Sprint 0 (semana 1)** — scaffold del monorepo, proyecto Supabase, migraciones + RLS + `fn_registrar_marcaje`, carga de roster inicial.

**Sprint 1 (semanas 2-3, meta: listo antes del cierre de julio)** — kiosco de marcaje completo (online + offline) en las 3 sedes, con export manual a CSV/Excel para ese primer cierre de planilla. Sin panel admin completo, sin alertas push, sin espejo Sheets todavía — se resuelve cualquier corrección manual directo en la base de datos si hace falta durante este primer cierre.

**Semanas 4-6** — panel de administración completo (roster, horarios, tarifas, correcciones con auditoría, dashboard en vivo), auto-cierre por cron, alertas push (olvido de salida, tardanzas, salida sin retorno), reportes PDF/Excel/incidencias.

**Semanas 6-8** — espejo Google Sheets, app personal (Expo Go primero; build EAS temprano específicamente para probar push en Android, ya que Expo Go dejó de soportar push remoto en Android), migración del histórico, UAT en las 3 sedes.

**Fase 2 (después, fuera de este plan)** — cálculo de remuneración final en soles (tarifa × horas + horas extra a tarifa base, aplicando revisiones de tardanza), flujo de aprobación de horas extra.

## Estructura del proyecto

```
~/Proyectos/cayla-dynamic/
├── apps/
│   ├── web/                       # Next.js — kiosco + admin, un solo deploy
│   │   ├── app/(kiosk)/kiosk/[sede]/
│   │   ├── app/(admin)/admin/...
│   │   └── lib/                   # supabase client, outbox IndexedDB, sync
│   └── mobile/                    # Expo Router — app personal
├── packages/
│   ├── shared/                    # zod schemas, attendance-state-machine.ts, enums
│   └── database/                  # tipos generados de Supabase
├── supabase/
│   ├── migrations/*.sql
│   └── functions/                 # registrar-marcaje, verify-pin, auto-cierre-cron, sheets-sync
├── scripts/migracion-historica/
├── turbo.json
└── pnpm-workspace.yaml
```

## Riesgos a tener presentes (no bloquean, pero el founder debe saberlo)

- El PIN de 4 dígitos cacheado localmente para modo offline es débil como cripto (10,000 combinaciones); es la contraparte consciente de "sin biometría, mínima fricción" — el control real es que el kiosco es un dispositivo físico atendido, no la fortaleza del PIN.
- Expo Go ya no soporta push remoto en Android (sí en iOS) — se necesita un build EAS de desarrollo (gratis, dentro del límite de 15/mes) para probar esa función específica, aunque el resto de la app personal funcione bien en Expo Go.
- Vercel Hobby prohíbe por ToS uso organizacional — aceptable para desarrollo privado, pero debe subirse a Pro a más tardar en el lanzamiento de Sprint 1 (coincide con la decisión ya tomada de subir de plan en el go-live).

## Verificación

- **Sprint 0**: correr las migraciones contra el proyecto Supabase, insertar personas de prueba, verificar RLS con usuarios de cada rol (admin/lider_do/supervisor_sede) vía el SQL editor o un script de pruebas.
- **Sprint 1 (kiosco)**: probar el flujo completo en un navegador simulando las 3 sedes; forzar modo avión en el dispositivo real de una sede para validar que el marcaje se encola y sincroniza al reconectar; provocar intencionalmente un doble tap para confirmar que la máquina de estados nunca pide "elegir entrada o salida" dos veces seguidas.
- **Auto-cierre**: adelantar el reloj de prueba o insertar una jornada abierta con timestamp viejo y correr manualmente la Edge Function del cron para confirmar que auto-cierra y marca `pendiente_revision`.
- **Migración histórica**: ejecutar contra el proyecto de staging primero y revisar el resumen (conteos por sede/estado, rango de fechas) con el founder antes de tocar producción.

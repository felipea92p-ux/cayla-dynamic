# CAYLA Dynamic

App de registro de asistencia para CAYLA (sedes TRU, LIM, AQP) — reemplazo del Google Form/Sheet "Dynamic".

Ver el plan completo en `docs/plan.md`.

## Estructura

- `apps/web` — Next.js: terminal de marcaje `(terminal)` + panel de administración `(admin)`.
- `apps/mobile` — Expo: app personal (historial + notificaciones push).
- `packages/shared` — esquemas zod, máquina de estados de asistencia, enums compartidos.
- `packages/database` — tipos generados de Supabase + cliente tipado.
- `supabase/` — migraciones y Edge Functions.
- `scripts/migracion-historica/` — importación única del historial de las 3 hojas de cálculo actuales.

## Desarrollo

```bash
npx pnpm install
npx pnpm dev
```

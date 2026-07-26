# CAYLA Dynamic

Asistencia y planilla de CAYLA (sedes TRU, LIM, AQP). Reemplazó al Google
Form/Sheet "Dynamic". En producción y uso diario: **cayla-dynamic.vercel.app**.

- **Cómo se trabaja aquí** → [`CLAUDE.md`](CLAUDE.md) — reglas de SQL a producción,
  deploy, vocabulario y convención de migraciones. Léelo antes de tocar nada.
- **Dónde estamos hoy** → [`docs/estado.md`](docs/estado.md) — único archivo de estado.

## Estructura

- `apps/web` — Next.js, un solo despliegue: terminal de marcaje `(terminal)` +
  panel de administración `(admin)` con 24 pantallas.
- `packages/shared` — esquemas zod, máquina de estados de asistencia, enums.
- `packages/database` — tipos generados de Supabase + cliente tipado.
- `supabase/migrations` — el esquema, una migración por cambio.
- `supabase/tests` — pruebas pgTAP (planilla, vacaciones, tardanzas, faltas…).
- `scripts/sql-manual` — migraciones listas para pegar en el SQL Editor.
- `scripts/migracion-historica` — importación única del historial 2025.

## Desarrollo

```bash
npx pnpm install
npx pnpm dev
```

```bash
npx pnpm typecheck && npx pnpm test
```

Las migraciones **no se despliegan solas**: se pegan a mano en el SQL Editor de
Supabase (ver `CLAUDE.md`). Desplegar a producción se pregunta siempre.

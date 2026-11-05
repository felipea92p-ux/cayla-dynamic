// Enciende el entorno local y levanta la app apuntando a él. Es lo que corre `.claude/launch.json`.
//
// Es Node y no un script de bash a propósito: el lanzador del panel de Claude corre el programa como proceso
// propio, y el bash de Homebrew se queda colgado para siempre en `getcwd` esperando un permiso de macOS para leer
// un disco externo (medido el 2026-11-05: `sample` lo muestra detenido en `__open_nocancel`). Node ya tiene ese permiso.
//
// Las variables van en el proceso, no en un archivo: así nadie deja un `.env.local` olvidado apuntando aquí.

import { execFileSync, spawn, spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const aqui = dirname(fileURLToPath(import.meta.url));
const raiz = join(aqui, "..", "..");

const encendido = spawnSync("/bin/bash", [join(aqui, "arrancar.sh")], { stdio: "inherit", cwd: raiz });
if (encendido.status !== 0) process.exit(encendido.status ?? 1);

const llaves = JSON.parse(execFileSync(process.execPath, [join(aqui, "puerta.mjs"), "llaves"], { encoding: "utf8" }));
const puerto = process.env.PORT ?? "3000";
const env = {
  ...process.env,
  NEXT_PUBLIC_SUPABASE_URL: llaves.url,
  NEXT_PUBLIC_SUPABASE_ANON_KEY: llaves.publica,
  SUPABASE_SERVICE_ROLE_KEY: llaves.servicio,
  // El vidrio: encendido en esta computadora, apagado en producción (ver apps/web/lib/vidrio.ts).
  NEXT_PUBLIC_VIDRIO: process.env.NEXT_PUBLIC_VIDRIO ?? "1",
  NEXT_PUBLIC_VIDRIO_TERMINAL: process.env.NEXT_PUBLIC_VIDRIO_TERMINAL ?? "1",
};
const app = spawn("npx", ["pnpm", "--filter", "@cayla-dynamic/web", "exec", "next", "dev", "-p", puerto], { stdio: "inherit", env, cwd: raiz });
app.on("exit", (codigo) => process.exit(codigo ?? 0));
for (const senal of ["SIGINT", "SIGTERM"]) process.on(senal, () => app.kill(senal));

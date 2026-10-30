import { defineConfig } from "vitest/config";
import path from "node:path";

// Motor de pruebas del FRONTEND (el de la base de datos es pgTAP, aparte).
// Las pruebas viven en tests/ y apuntan a la lógica pura del sistema: la máquina
// de estados de asistencia, las reglas del bono y los formateadores de dinero.
const raiz = import.meta.dirname;

export default defineConfig({
  test: {
    include: ["tests/**/*.test.ts"],
    environment: "node",
  },
  resolve: {
    alias: {
      // Mismos atajos que usa la app, para que las pruebas importen igual que el código real.
      "@cayla-dynamic/shared": path.resolve(raiz, "packages/shared/src/index.ts"),
      // Sin este alias un `vi.mock("@cayla-dynamic/database")` no intercepta nada:
      // el paquete se resuelve por el enlace del workspace y la prueba y el código
      // terminan viendo dos módulos distintos (tests/sync-terminal.test.ts).
      "@cayla-dynamic/database": path.resolve(raiz, "packages/database/src/index.ts"),
      "@": path.resolve(raiz, "apps/web"),
    },
  },
});

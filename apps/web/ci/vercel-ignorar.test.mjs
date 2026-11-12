// Pruebas de «¿Vercel compila esta versión?». `node --test apps/web/ci/vercel-ignorar.test.mjs`  (corren también en el job `ui-tests` del CI).
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { baseDeComparacion, cambiadasDesde, decidir, RUTAS_QUE_COMPILA_LA_WEB, tocaLaWeb } from "./vercel-ignorar.mjs";

const WEB = join(dirname(fileURLToPath(import.meta.url)), "..");
const RAIZ = join(WEB, "..", "..");
const SCRIPT = join(WEB, "ci/vercel-ignorar.mjs");

const compila = (entorno, cambiadas) => decidir({ entorno, cambiadas }).compilar;

test("se salta solo si nada de lo que cambió es de la web, en producción y en vistas previas", () => {
  // Fusiones reales a main que no tocaban la web (#733, #725, #723, #716, #707, #704 — nov-2026).
  const soloAfuera = [
    ["docs/estado.md"],
    ["CLAUDE.md", "docs/vidrio/README.md"],
    ["CLAUDE.md", "scripts/hooks/funciones-de-plata.txt", "scripts/que-falta-pegar.sh"],
    ["scripts/sql-manual/que_falta_pegar.sql", "supabase/migrations/0607_x.sql", "supabase/tests/494_x.test.sql"],
    [".claude/skills/ultra-criterio/SKILL.md"],
    ["docs/adr/0006-tiempo-real.md", "tests/algo.test.ts", ".github/workflows/tests.yml", "vitest.config.ts"],
  ];
  for (const cambiadas of soloAfuera) {
    assert.equal(compila("production", cambiadas), false, cambiadas.join(", "));
    assert.equal(compila("preview", cambiadas), false, cambiadas.join(", "));
  }
  for (const archivo of [
    "apps/web/app/(admin)/admin/contratos/page.tsx",
    "apps/web/app/estilos/vidrio/terminal.css",
    "apps/web/vercel.json",
    "apps/web/next.config.ts",
    "apps/web/package.json",
    "apps/web/ci/vercel-ignorar.mjs",
    "packages/shared/src/permisos.ts",
    "packages/database/src/types.ts",
    "pnpm-lock.yaml",
    "pnpm-workspace.yaml",
    "package.json",
    "turbo.json",
    ".nvmrc",
    ".npmrc",
    ".vercelignore",
  ]) {
    assert.equal(compila("production", ["docs/estado.md", archivo]), true, archivo);
    assert.equal(compila("preview", ["docs/estado.md", archivo]), true, archivo);
  }
  // Un nombre que solo empieza igual no es la carpeta ni el archivo.
  assert.equal(tocaLaWeb(["apps/webhooks/x.ts", "packages-viejos/x", "package.json.bak", "apps/web-vieja/x"]), false);
});

test("ante la duda se compila: sin versión anterior, git que falla, la misma versión, otro entorno", () => {
  for (const entorno of ["production", "preview"]) {
    assert.equal(compila(entorno, null), true);
    assert.equal(compila(entorno, undefined), true);
    assert.equal(compila(entorno, []), true, "diff vacío = alguien pidió recompilar");
  }
  assert.equal(compila("development", ["docs/estado.md"]), true);
  assert.equal(compila(undefined, ["docs/estado.md"]), true);
  assert.equal(compila("", ["docs/estado.md"]), true);
});

test("la lista cubre todo lo que la web importa de fuera de su carpeta", () => {
  // Los paquetes del workspace que la web declara tienen que vivir dentro de una ruta de la lista.
  const { dependencies = {}, devDependencies = {} } = JSON.parse(readFileSync(join(WEB, "package.json"), "utf8"));
  const delWorkspace = Object.entries({ ...dependencies, ...devDependencies }).filter(([, v]) => v.startsWith("workspace:"));
  assert.ok(delWorkspace.length > 0);
  for (const [nombre] of delWorkspace) {
    const carpeta = `packages/${nombre.split("/")[1]}`;
    const { name } = JSON.parse(readFileSync(join(RAIZ, carpeta, "package.json"), "utf8"));
    assert.equal(name, nombre, `${nombre} no vive en ${carpeta}: súmalo a RUTAS_QUE_COMPILA_LA_WEB`);
    assert.equal(tocaLaWeb([`${carpeta}/src/index.ts`]), true, carpeta);
  }
  assert.ok(RUTAS_QUE_COMPILA_LA_WEB.includes("apps/web"));
});

// Un repo de verdad: lo publicado, una fusión de documentos, una de la web.
function repoDePrueba() {
  const dir = mkdtempSync(join(tmpdir(), "vercel-ignorar-"));
  const g = (...args) =>
    execFileSync("git", ["-c", "user.name=Prueba", "-c", "user.email=prueba@cayla.test", "-c", "commit.gpgsign=false", ...args], {
      cwd: dir,
      encoding: "utf8",
    }).trim();
  const escribir = (ruta, texto) => {
    mkdirSync(dirname(join(dir, ruta)), { recursive: true });
    writeFileSync(join(dir, ruta), texto);
    g("add", ruta);
    g("commit", "-q", "-m", `cambia ${ruta}`);
    return g("rev-parse", "HEAD");
  };
  g("init", "-q", "-b", "main");
  mkdirSync(join(dir, "apps/web/ci"), { recursive: true });
  copyFileSync(SCRIPT, join(dir, "apps/web/ci/vercel-ignorar.mjs"));
  g("add", ".");
  g("commit", "-q", "-m", "el filtro");
  return { dir, g, escribir };
}

// El contrato con Vercel es el código de salida: 0 = no compilar, 1 = compilar. Se corre la orden de vercel.json tal
// cual, desde apps/web, que es donde la corre Vercel.
function ordenDeVercel(dir, env) {
  const { ignoreCommand } = JSON.parse(readFileSync(join(WEB, "vercel.json"), "utf8"));
  return spawnSync("sh", ["-c", ignoreCommand], {
    cwd: join(dir, "apps/web"),
    env: { PATH: process.env.PATH, ...env },
    encoding: "utf8",
  });
}

test("cambiadasDesde en un repo de verdad", (t) => {
  const r = repoDePrueba();
  t.after(() => rmSync(r.dir, { recursive: true, force: true }));
  const publicada = r.escribir("apps/web/app/page.tsx", "uno");
  r.escribir("docs/estado.md", "nota");
  assert.deepEqual(cambiadasDesde(publicada, r.dir), { cambiadas: ["docs/estado.md"], error: null });
  assert.equal(cambiadasDesde("", r.dir).cambiadas, null);
  assert.equal(cambiadasDesde(undefined, r.dir).cambiadas, null);
  const fuera = cambiadasDesde("0123456789abcdef0123456789abcdef01234567", r.dir);
  assert.equal(fuera.cambiadas, null, "una versión que el clon corto no tiene: no se sabe");
  assert.match(fuera.error, /git no pudo comparar con 0123456/);
});

test("la orden de vercel.json, en un repo de verdad: documentos se saltan, la web se compila", (t) => {
  const r = repoDePrueba();
  t.after(() => rmSync(r.dir, { recursive: true, force: true }));
  const publicada = r.escribir("apps/web/app/page.tsx", "uno");
  const soloDocs = r.escribir("docs/estado.md", "nota");

  for (const VERCEL_ENV of ["production", "preview"]) {
    const corre = (anterior) => ordenDeVercel(r.dir, { VERCEL_ENV, VERCEL_GIT_PREVIOUS_SHA: anterior });
    const salta = corre(publicada);
    assert.equal(salta.status, 0, `${VERCEL_ENV}: ${salta.stdout}${salta.stderr}`);
    assert.match(salta.stdout, /^No se compila: .*docs\/estado\.md/);
    assert.equal(corre(soloDocs).status, 1, `${VERCEL_ENV}: misma versión que la última compilada`);
    // Sin versión anterior: producción no tiene con qué comparar; la vista previa, parada en main, no ve nada propio.
    assert.equal(corre("").status, 1, `${VERCEL_ENV}: primera versión de la rama`);
    const fuera = corre("0123456789abcdef0123456789abcdef01234567");
    assert.equal(fuera.status, 1, `${VERCEL_ENV}: versión anterior fuera del clon`);
    assert.match(fuera.stdout, /^Se compila: .*\[git no pudo comparar/);
  }
  assert.equal(ordenDeVercel(r.dir, {}).status, 1, "sin variables de Vercel");
  assert.equal(ordenDeVercel(r.dir, { VERCEL_ENV: "development", VERCEL_GIT_PREVIOUS_SHA: publicada }).status, 1);

  r.escribir("apps/web/app/page.tsx", "dos");
  assert.equal(ordenDeVercel(r.dir, { VERCEL_ENV: "production", VERCEL_GIT_PREVIOUS_SHA: soloDocs }).status, 1);
  assert.equal(ordenDeVercel(r.dir, { VERCEL_ENV: "production", VERCEL_GIT_PREVIOUS_SHA: publicada }).status, 1);
});

test("sin .git (si Vercel lo borrara antes del filtro), se compila", (t) => {
  const r = repoDePrueba();
  t.after(() => rmSync(r.dir, { recursive: true, force: true }));
  const publicada = r.escribir("apps/web/app/page.tsx", "uno");
  r.escribir("docs/estado.md", "nota");
  rmSync(join(r.dir, ".git"), { recursive: true, force: true });
  const sinGit = ordenDeVercel(r.dir, { VERCEL_ENV: "production", VERCEL_GIT_PREVIOUS_SHA: publicada, GIT_CEILING_DIRECTORIES: r.dir });
  assert.equal(sinGit.status, 1, sinGit.stdout + sinGit.stderr);
  assert.match(sinGit.stdout, /^Se compila: .*\[git no pudo comparar/);
});

test("el .vercelignore de la raíz no borra el filtro ni .git", () => {
  // Vercel aplica el .vercelignore ANTES de correr el filtro (log de la vista previa del #734). Si una línea alcanzara
  // apps/web/ci, Vercel correría `node ci/vercel-ignorar.mjs` sobre un archivo borrado; si alcanzara `.git`, el filtro no
  // tendría con qué comparar. En los dos casos compilaría siempre, en silencio. Se revisa con las reglas simples que usa
  // ese archivo.
  const lineas = readFileSync(join(RAIZ, ".vercelignore"), "utf8")
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith("#") && !l.startsWith("!"));
  const tramos = ["apps", "web", "ci", "vercel-ignorar.mjs", ".git"];
  for (const patron of lineas) {
    const limpio = patron.replace(/^\*\*\//, "").replace(/^\//, "").replace(/\/$/, "");
    const re = new RegExp(`^${limpio.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, "[^/]*")}$`);
    for (const tramo of tramos) assert.equal(re.test(tramo), false, `«${patron}» del .vercelignore borra ${tramo}`);
  }
});

test("primer push de una rama: la vista previa compara con la base común con main; producción no", (t) => {
  const r = repoDePrueba();
  t.after(() => rmSync(r.dir, { recursive: true, force: true }));
  const enMain = r.escribir("apps/web/app/page.tsx", "uno");
  r.g("checkout", "-q", "-b", "claude/solo-docs");
  r.escribir("docs/estado.md", "nota");
  const docs = ordenDeVercel(r.dir, { VERCEL_ENV: "preview", VERCEL_GIT_PREVIOUS_SHA: "" });
  assert.equal(docs.status, 0, docs.stdout + docs.stderr);
  assert.match(docs.stdout, /^No se compila: vista previa: .*base común con main \(primer push/);
  assert.deepEqual(baseDeComparacion({ entorno: "preview", anterior: "" }, r.dir), {
    base: enMain,
    desde: "la base común con main (primer push de la rama)",
  });
  // Producción sin versión anterior no usa el respaldo: compila.
  assert.equal(ordenDeVercel(r.dir, { VERCEL_ENV: "production", VERCEL_GIT_PREVIOUS_SHA: "" }).status, 1);
  assert.deepEqual(baseDeComparacion({ entorno: "production", anterior: "" }, r.dir), { base: null, desde: null });

  // Una rama que toca la web, en su primer push, se compila.
  r.g("checkout", "-q", "main");
  r.g("checkout", "-q", "-b", "claude/con-web");
  r.escribir("apps/web/app/page.tsx", "dos");
  assert.equal(ordenDeVercel(r.dir, { VERCEL_ENV: "preview", VERCEL_GIT_PREVIOUS_SHA: "" }).status, 1);

  // Si el clon no tiene main (lo normal en Vercel, que clona solo la rama), no hay base: se compila y el log lo dice.
  r.g("checkout", "-q", "claude/solo-docs");
  r.g("branch", "-q", "-D", "main", "claude/con-web");
  assert.deepEqual(baseDeComparacion({ entorno: "preview", anterior: "" }, r.dir), { base: null, desde: null });
  const sinMain = ordenDeVercel(r.dir, { VERCEL_ENV: "preview", VERCEL_GIT_PREVIOUS_SHA: "" });
  assert.equal(sinMain.status, 1, sinMain.stdout);
  assert.match(sinMain.stdout, /^Se compila: .*el clon no tiene main para comparar/);
});

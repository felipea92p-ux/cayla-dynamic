#!/usr/bin/env node
/**
 * ¿Vercel compila esta versión? — el «Ignored Build Step» del proyecto `cayla-dynamic` (`ignoreCommand` en
 * `apps/web/vercel.json`).
 *
 * EL PROBLEMA (medido el 2026-11-12). La factura de Vercel fue de US$ 102 y US$ 84 eran minutos de compilación, que se
 * cobran por minuto × núcleo. `cayla-dynamic` es ~40 % de esos minutos: ~72 s por compilación en una máquina de 4
 * núcleos, ~35 s de ellos creando y subiendo la caché. Y se compilaba TODO: cada fusión a `main` y cada push de cada
 * rama, también los que solo cambian `docs/estado.md`, `CLAUDE.md` o una migración. De las últimas 30 fusiones a `main`,
 * 7 no tocaban nada de lo que la web compila.
 *
 * QUÉ PROMETE. Sale con 0 («no compiles») SOLO si se sabe con certeza qué archivos cambiaron desde la última versión
 * compilada con éxito de esa rama (`VERCEL_GIT_PREVIOUS_SHA`) y ninguno está en `RUTAS_QUE_COMPILA_LA_WEB`: lo que ya
 * está publicado es exactamente esa web. Vale igual para producción y para las vistas previas. Todo lo demás sale con 1
 * y se compila como siempre: la primera versión de una rama cuando no hay con qué compararla (ver
 * `baseDeComparacion`), repetir la misma versión (diff vacío =
 * alguien pidió recompilar), producción sin versión anterior, un `git` que falla o no encuentra la versión anterior (clon corto), un entorno que no es
 * `production` ni `preview`, o cualquier error. Ante la duda compila: si se equivoca, se equivoca hacia gastar un
 * minuto, nunca hacia publicar una web distinta de la que está en `main`.
 *
 * LO QUE NO HACE, A PROPÓSITO. En cayla-retail las vistas previas se saltan también cuando lo único nuevo es «traer
 * `main` a la rama». Aquí no: el CI de Dynamic no corre `next build`, así que la vista previa es la ÚNICA compilación de
 * la rama junto con `main` antes de fusionar. Si `main` trae cambios de la web, esa combinación se compila.
 *
 * QUÉ ASUME. Vercel lo corre con el directorio de la web (`apps/web`) como carpeta de trabajo, antes de instalar
 * dependencias, así que solo usa Node y `git`. Entiende 0 = no compilar, 1 = compilar. `git diff --name-only` da las
 * rutas desde la raíz del repositorio aunque se corra en `apps/web`.
 *
 * POR QUÉ VIVE EN `apps/web/ci/` Y NO EN `scripts/`. El `.vercelignore` de la raíz borra `scripts/` (y cualquier carpeta
 * que se llame `scripts`) del clon de Vercel antes de compilar. Aquí no lo alcanza.
 */
import { execFileSync } from "node:child_process";
import { pathToFileURL } from "node:url";

/**
 * Lo que la web compila, en rutas desde la raíz del repositorio. Medido el 2026-11-12: `apps/web` no importa nada de
 * fuera de su carpeta salvo los dos paquetes del workspace (`@cayla-dynamic/shared`, `@cayla-dynamic/database`); el CSS
 * generado de la familia de diseño ya vive dentro de `apps/web`. Lo demás arma la instalación (`pnpm-lock.yaml`,
 * `package.json`, `.npmrc`, `.nvmrc`), la orquesta (`turbo.json`) o decide qué archivos llegan a la compilación
 * (`.vercelignore`). Si la web empieza a leer al compilar un archivo de afuera, se suma aquí, o producción no se
 * compilaría con su cambio.
 */
export const RUTAS_QUE_COMPILA_LA_WEB = [
  "apps/web",
  "packages",
  "pnpm-lock.yaml",
  "pnpm-workspace.yaml",
  "package.json",
  "turbo.json",
  ".nvmrc",
  ".npmrc",
  ".vercelignore",
];

/** ¿Alguno de estos archivos (rutas desde la raíz del repo) cambia lo que compila la web? */
export const tocaLaWeb = (archivos) =>
  archivos.some((a) => RUTAS_QUE_COMPILA_LA_WEB.some((r) => a === r || a.startsWith(`${r}/`)));

/**
 * `entorno` = VERCEL_ENV (`production` | `preview` | `development`).
 * `cambiadas` = los archivos que cambiaron desde `desde`, o `null` si no se pudo saber.
 * `desde` = contra qué se comparó, para el log.
 */
export function decidir({ entorno, cambiadas, desde = "la última versión compilada" }) {
  if (entorno !== "production" && entorno !== "preview") {
    return { compilar: true, motivo: `entorno «${entorno || "sin dato"}»: solo se saltan producción y vistas previas` };
  }
  const donde = entorno === "production" ? "producción" : "vista previa";
  if (!cambiadas) {
    return { compilar: true, motivo: `${donde}: no se sabe qué cambió desde ${desde}, ante la duda se compila` };
  }
  if (cambiadas.length === 0) {
    return { compilar: true, motivo: `${donde}: nada cambió desde ${desde}, alguien pidió repetirla` };
  }
  const deLaWeb = cambiadas.find((a) => tocaLaWeb([a]));
  if (deLaWeb) return { compilar: true, motivo: `${donde}: «${deLaWeb}» cambia lo que compila la web` };
  const n = cambiadas.length;
  return {
    compilar: false,
    motivo: `${donde}: ninguno de los ${n} archivo${n === 1 ? "" : "s"} que cambiaron desde ${desde} es de la web (${cambiadas.slice(0, 3).join(", ")}${n > 3 ? ", …" : ""})`,
  };
}

/**
 * Los archivos que cambiaron entre la última versión compilada y HEAD. `{ cambiadas: null, error }` si no hay versión
 * anterior o `git` falla: el error se imprime en el log de Vercel, que es la única forma de saber desde afuera por qué
 * el filtro no se atrevió a saltar.
 */
export function cambiadasDesde(anterior, cwd = process.cwd()) {
  if (!anterior) return { cambiadas: null, error: "no hay versión anterior compilada en esta rama" };
  try {
    const salida = execFileSync("git", ["diff", "--name-only", anterior, "HEAD"], {
      cwd,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    });
    return { cambiadas: salida.split("\n").filter(Boolean), error: null };
  } catch (e) {
    const detalle = String(e.stderr || e.message || e).trim().split("\n")[0];
    return { cambiadas: null, error: `git no pudo comparar con ${anterior.slice(0, 7)}: ${detalle}` };
  }
}

/**
 * Desde dónde comparar. Lo normal es la última versión compilada con éxito de la rama (`VERCEL_GIT_PREVIOUS_SHA`). En
 * el PRIMER push de una rama esa variable viene vacía: ahí una vista previa prueba con la base común con `main`, si el
 * clon de Vercel la tiene (lo que la rama cambió desde que salió de `main`; esa web ya pasó por producción). Si no la
 * tiene, no hay base y se compila. Producción nunca usa ese respaldo: sin versión anterior, compila.
 */
export function baseDeComparacion({ entorno, anterior }, cwd = process.cwd()) {
  if (anterior) return { base: anterior, desde: "la última versión compilada" };
  if (entorno !== "preview") return { base: null, desde: null };
  for (const rama of ["origin/main", "main"]) {
    try {
      const base = execFileSync("git", ["merge-base", "HEAD", rama], {
        cwd,
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      }).trim();
      if (base) return { base, desde: `la base común con ${rama} (primer push de la rama)` };
    } catch {
      // El clon de Vercel trae solo la rama que compila: lo normal es que no esté. Se prueba la siguiente.
    }
  }
  return { base: null, desde: null };
}

function main() {
  try {
    const entorno = process.env.VERCEL_ENV;
    let cambiadas = null;
    let error = null;
    let desde;
    if (entorno === "production" || entorno === "preview") {
      const base = baseDeComparacion({ entorno, anterior: process.env.VERCEL_GIT_PREVIOUS_SHA });
      desde = base.desde ?? undefined;
      ({ cambiadas, error } = cambiadasDesde(base.base));
      if (!base.base && entorno === "preview") error = `${error}, y el clon no tiene main para comparar`;
    }
    const { compilar, motivo } = decidir({ entorno, cambiadas, desde });
    console.log(`${compilar ? "Se compila" : "No se compila"}: ${motivo}${error ? ` [${error}]` : ""}`);
    process.exit(compilar ? 1 : 0);
  } catch (e) {
    console.log(`No se pudo decidir (${e.message}): se compila`);
    process.exit(1);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();

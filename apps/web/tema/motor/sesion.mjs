// Cómo entra un medidor a Dynamic, y el candado que le impide salir de esta computadora. Lo comparten `tema/` y `responsive/`: dos candados
// son uno de más, y en Retail el de `responsive/` no tenía ninguno.
//
// Dynamic guarda la sesión en localStorage (`cayla-auth-admin` / `cayla-auth-terminal`), no en cookies. Por eso no hace falta pasar por la
// pantalla de login: se le pide la sesión a la API local y se deja en localStorage antes de que cargue la página. No se guarda en disco.
//
// Se niega a tres cosas, y las tres se comprueban con un caso que debe fallar:
//   · una app que no esté en localhost;
//   · una API de Supabase que no esté en localhost;
//   · y lo que `exigirLocal` no puede ver: una app en localhost configurada contra el Supabase de producción. Por eso el navegador tiene la
//     red cerrada: todo pedido a un host que no sea esos dos se aborta y se anota en `fuera`, y `problemaDeRed` lo convierte en un error.

import { chromium } from "playwright";
import { CLAVE_LOCAL } from "../cuentas.mjs";

const LOCAL = /^http:\/\/(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/;

export const APP_POR_DEFECTO = "http://localhost:3000";
export const API_POR_DEFECTO = "http://127.0.0.1:55892";

export function exigirLocal(url, que = "La app") {
  let origen;
  try {
    origen = new URL(url).origin;
  } catch {
    throw new Error(`${que}: «${url}» no es una URL.`);
  }
  if (!LOCAL.test(origen)) throw new Error(`${que} tiene que estar en esta computadora (http://localhost): «${origen}» no lo está. Estos medidores nunca corren contra producción.`);
  return origen;
}

export const abrirNavegador = ({ headed = false } = {}) => chromium.launch({ headless: !headed, channel: process.env.NAVEGADOR_CANAL || "chrome" });

const sesiones = new Map();

async function sesionDe(cuenta, api) {
  const vigente = sesiones.get(cuenta.correo);
  if (vigente && vigente.expires_at - Date.now() / 1000 > 300) return vigente;
  // El entorno local de `scripts/local` no pide llave; un `supabase start` sí, y se le pasa por esta variable.
  const llave = process.env.TEMA_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  let res;
  try {
    res = await fetch(`${api}/auth/v1/token?grant_type=password`, {
      method: "POST",
      headers: { "content-type": "application/json", ...(llave ? { apikey: llave, authorization: `Bearer ${llave}` } : {}) },
      body: JSON.stringify({ email: cuenta.correo, password: CLAVE_LOCAL }),
    });
  } catch (e) {
    throw new Error(`No se pudo hablar con la API local en ${api}: ${e.cause?.code ?? e.message}. ¿Está levantado el entorno? (--api-url o TEMA_API_URL)`);
  }
  const cuerpo = await res.json().catch(() => ({}));
  if (!res.ok || !cuerpo.access_token) throw new Error(`No entró ${cuenta.correo} (HTTP ${res.status}): ${cuerpo.msg ?? cuerpo.error_description ?? "sin detalle"}. ¿Existe esa cuenta en la base local?`);
  sesiones.set(cuenta.correo, cuerpo);
  return cuerpo;
}

/**
 * Un contexto de Playwright con sesión y tema puestos desde antes de pintar, y con la red cerrada a esta computadora.
 * Bloquea el service worker: el del terminal cachearía entre corridas, y lo que él pide no pasa por el candado de la red.
 */
export async function abrirContexto(navegador, cuenta, { baseUrl, apiUrl, tema, viewport, fuera }) {
  const origen = exigirLocal(baseUrl, "La app");
  const api = exigirLocal(apiUrl, "La API de Supabase");
  const ctx = await navegador.newContext({ viewport, serviceWorkers: "block", ...(viewport.width < 700 ? { isMobile: true, hasTouch: true } : {}) });
  await ctx.route("**/*", (ruta) => {
    const url = new URL(ruta.request().url());
    if (url.origin === origen || url.origin === api) return ruta.continue();
    fuera.add(url.host);
    return ruta.abort();
  });
  const sesion = cuenta.correo ? await sesionDe(cuenta, api) : null;
  await ctx.addInitScript(
    ({ almacen, sesion, tema }) => {
      try {
        if (sesion) localStorage.setItem(almacen, JSON.stringify(sesion));
        localStorage.setItem("cayla-tema", tema);
      } catch {
        /* about:blank o ventana privada: esa página no lee nada de esto */
      }
    },
    { almacen: cuenta.almacen ?? "cayla-auth-admin", sesion, tema },
  );
  return ctx;
}

/** ¿El servidor de esa URL es Dynamic? Con varias sesiones levantando servidores, medir el de otro proyecto da un «cero hallazgos» que no vale nada. */
export async function exigirDynamic(baseUrl) {
  let html;
  try {
    html = await (await fetch(`${baseUrl}/`, { redirect: "follow" })).text();
  } catch (e) {
    throw new Error(`No se pudo hablar con ${baseUrl}: ${e.cause?.code ?? e.message}. ¿Está levantado el servidor? (--base-url)`);
  }
  if (!html.includes("cayla-tema-global")) throw new Error(`El servidor de ${baseUrl} no parece Dynamic: su HTML no trae el script del tema.`);
}

/** Lo que el candado de la red abortó: si la app quiso hablar con otro Supabase, la medición no vale. */
export function problemaDeRed(fuera) {
  const graves = [...fuera].filter((h) => /supabase|^(localhost|127\.0\.0\.1|\[::1\])(:|$)/.test(h));
  if (graves.length) return `esta app le pidió datos a ${graves.join(", ")}, que no es la API local: revisa su NEXT_PUBLIC_SUPABASE_URL. Se abortó sin llegar.`;
  return null;
}

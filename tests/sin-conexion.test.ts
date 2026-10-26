// ============================================================================
// sin-conexion.test.ts — el service worker del colibrí, ejecutado de verdad
// ============================================================================
// `sin-conexion-sw.js` promete tres cosas que, si se rompen, no fallan con
// ruido: pasan en silencio y se ven semanas después.
//   1. No guarda NINGUNA página del panel (si lo hiciera, sin internet se
//      podría mostrar una planilla vieja como si fuera de hoy).
//   2. No toca el terminal (una sede sin internet tiene que seguir viendo SU
//      pantalla de marcar, nunca un juego).
//   3. Un error del servidor NO es «sin conexión».
// Se prueba corriendo el archivo real dentro de un entorno simulado, no
// leyéndolo como texto.
// ============================================================================
import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";
import vm from "node:vm";

const PUBLIC = path.resolve(import.meta.dirname, "../apps/web/public");
const CODIGO_SW = readFileSync(path.join(PUBLIC, "sin-conexion-sw.js"), "utf8");
const HTML = readFileSync(path.join(PUBLIC, "sin-conexion.html"), "utf8");

const ORIGEN = "https://cayla-dynamic.vercel.app";

type Escuchas = Record<string, (e: unknown) => void>;
type Resp = { ok: boolean; status: number; clone: () => Resp; marca?: string };

/** Corre el service worker en un entorno simulado. `red` decide qué contesta la red (o si falla). */
function montarSw(red: (url: string) => Promise<Resp>) {
  const escuchas: Escuchas = {};
  const guardado = new Map<string, Resp>();
  const escrituras: string[] = [];
  const resp = (marca: string, status = 200): Resp => ({
    ok: status >= 200 && status < 300, status, marca, clone() { return { ...this }; },
  });
  const cacheMock = {
    addAll: async () => {},
    put: async (clave: string | { url: string }, r: Resp) => {
      const k = typeof clave === "string" ? new URL(clave, ORIGEN).pathname : new URL(clave.url).pathname;
      escrituras.push(k);
      guardado.set(k, r);
    },
  };
  const entorno: Record<string, unknown> = {
    self: {
      location: { origin: ORIGEN },
      addEventListener: (nombre: string, fn: (e: unknown) => void) => { escuchas[nombre] = fn; },
      skipWaiting: () => {},
      clients: { claim: async () => {} },
    },
    caches: {
      open: async () => cacheMock,
      keys: async () => [],
      delete: async () => true,
      match: async (clave: string) => guardado.get(new URL(clave, ORIGEN).pathname),
    },
    fetch: (req: { url: string }) => red(req.url),
    Request: class { constructor(public url: string) {} },
    Response: { error: () => resp("error-de-red", 0) },
    URL,
  };
  entorno.self = Object.assign(entorno.self as object, entorno);
  vm.runInNewContext(CODIGO_SW, entorno);

  /** Simula una petición. Devuelve lo que el service worker contestó, o `null` si dejó pasar la petición. */
  async function pedir(url: string, init: { method?: string; mode?: string } = {}): Promise<Resp | null> {
    let respondida: Promise<Resp> | null = null;
    escuchas.fetch({
      request: { url: new URL(url, ORIGEN).href, method: init.method ?? "GET", mode: init.mode ?? "navigate" },
      respondWith: (p: Promise<Resp>) => { respondida = p; },
    });
    return respondida ? await respondida : null;
  }
  return { pedir, guardado, escrituras, resp };
}

const SIN_RED = () => Promise.reject(new TypeError("Failed to fetch"));

describe("sin conexión: abrir una página del panel", () => {
  it("con red devuelve exactamente lo que contestó la red y no guarda nada", async () => {
    const sw = montarSw(async () => sw.resp("pagina-de-planilla"));
    const r = await sw.pedir("/admin/planilla");
    expect(r?.marca).toBe("pagina-de-planilla");
    expect(sw.escrituras).toEqual([]); // la promesa más importante: ninguna página del panel entra a la caché
  });

  it("sin red sirve la página del colibrí, para el panel, «Lo mío» y el login", async () => {
    const sw = montarSw(SIN_RED);
    sw.guardado.set("/sin-conexion.html", sw.resp("pagina-del-colibri"));
    for (const ruta of ["/admin/planilla", "/mio", "/admin/login", "/", "/admin/personas/abc?x=1"]) {
      expect((await sw.pedir(ruta))?.marca).toBe("pagina-del-colibri");
    }
  });

  it("nunca sirve una página vieja del panel: aunque estuviera en la caché, sin red se muestra el aviso", async () => {
    const sw = montarSw(SIN_RED);
    sw.guardado.set("/sin-conexion.html", sw.resp("pagina-del-colibri"));
    sw.guardado.set("/admin/planilla", sw.resp("planilla-de-hace-tres-dias"));
    expect((await sw.pedir("/admin/planilla"))?.marca).toBe("pagina-del-colibri");
  });

  it("un error del servidor (500) NO es «sin conexión»: pasa tal cual", async () => {
    const sw = montarSw(async () => sw.resp("error-del-servidor", 500));
    const r = await sw.pedir("/admin/planilla");
    expect(r?.marca).toBe("error-del-servidor");
    expect(r?.status).toBe(500);
  });

  it("si la caché aún no tiene la página, falla como habría fallado sin service worker (no se queda colgado)", async () => {
    const sw = montarSw(SIN_RED);
    const r = await sw.pedir("/admin/planilla");
    expect(r?.status).toBe(0);
  });
});

describe("lo que este service worker NO toca", () => {
  it("el terminal de marcaje, ni con red ni sin ella", async () => {
    for (const red of [SIN_RED, async () => montarSw(SIN_RED).resp("x")]) {
      const sw = montarSw(red);
      sw.guardado.set("/sin-conexion.html", sw.resp("pagina-del-colibri"));
      for (const ruta of ["/terminal", "/terminal/marcar", "/terminal/marcar?sede=TRU"]) {
        expect(await sw.pedir(ruta)).toBeNull();
      }
    }
  });

  it("una ruta que solo EMPIEZA parecido a /terminal no se confunde con el terminal", async () => {
    const sw = montarSw(SIN_RED);
    sw.guardado.set("/sin-conexion.html", sw.resp("pagina-del-colibri"));
    expect((await sw.pedir("/terminales-de-prueba"))?.marca).toBe("pagina-del-colibri");
  });

  it("los POST (una marca, un envío de formulario)", async () => {
    const sw = montarSw(SIN_RED);
    expect(await sw.pedir("/admin/planilla", { method: "POST" })).toBeNull();
  });

  it("lo que no es una navegación: las llamadas de la app (fetch), imágenes, scripts", async () => {
    const sw = montarSw(SIN_RED);
    for (const modo of ["cors", "no-cors", "same-origin"]) {
      expect(await sw.pedir("/api/admin/algo", { mode: modo })).toBeNull();
      expect(await sw.pedir("/_next/static/chunks/abc.js", { mode: modo })).toBeNull();
    }
  });

  it("otro origen (Supabase, fuentes)", async () => {
    const sw = montarSw(SIN_RED);
    expect(await sw.pedir("https://abc.supabase.co/rest/v1/personas", { mode: "cors" })).toBeNull();
    expect(await sw.pedir("https://abc.supabase.co/", { mode: "navigate" })).toBeNull();
  });
});

describe("los tres archivos de la página", () => {
  it("con red, se sirve lo nuevo y se guarda para la próxima", async () => {
    const sw = montarSw(async () => sw.resp("juego-nuevo"));
    const r = await sw.pedir("/colibri/juego.js", { mode: "cors" });
    expect(r?.marca).toBe("juego-nuevo");
    expect(sw.escrituras).toEqual(["/colibri/juego.js"]);
  });

  it("sin red, se sirve el guardado", async () => {
    const sw = montarSw(SIN_RED);
    sw.guardado.set("/colibri/juego.js", sw.resp("juego-guardado"));
    expect((await sw.pedir("/colibri/juego.js", { mode: "cors" }))?.marca).toBe("juego-guardado");
  });

  it("un error del servidor no pisa la copia buena", async () => {
    const sw = montarSw(async () => sw.resp("error", 503));
    await sw.pedir("/colibri/juego.js", { mode: "cors" });
    expect(sw.escrituras).toEqual([]);
  });
});

describe("la página y lo que pide coinciden con lo que el service worker guarda", () => {
  const ACTIVOS = (/const ACTIVOS = \[(.*)\];/.exec(CODIGO_SW)?.[1] ?? "")
    .replace(/PAGINA/g, '"/sin-conexion.html"')
    .split(",")
    .map((s) => s.trim().replace(/^"|"$/g, ""))
    .filter(Boolean);

  it("ACTIVOS son exactamente tres", () => {
    expect(ACTIVOS).toEqual(["/sin-conexion.html", "/colibri/juego.js", "/colibri.png"]);
  });

  it("todo archivo local que la página pide está guardado: si no, sin red se vería rota", () => {
    const pedidos = new Set<string>();
    for (const m of HTML.matchAll(/(?:src|href)="(\/[^"#?]*)"/g)) pedidos.add(m[1]);
    for (const m of HTML.matchAll(/url\((\/[^)]+)\)/g)) pedidos.add(m[1]);
    for (const m of HTML.matchAll(/import\(?\s*"(\/[^"]+)"/g)) pedidos.add(m[1]);
    expect([...pedidos].sort()).toEqual(["/colibri.png", "/colibri/juego.js"]);
    for (const p of pedidos) expect(ACTIVOS).toContain(p);
  });

  it("la página no depende de nada fuera de este origen (sin red tampoco hay fuentes de Google ni CDN)", () => {
    expect(HTML).not.toMatch(/https?:\/\//);
  });

  it("la página dice lo que es verdad en su primera línea visible: que no hay internet y que nada se guarda", () => {
    const aviso = /<p class="aviso"[^>]*>([\s\S]*?)<\/p>/.exec(HTML)?.[1] ?? "";
    expect(aviso).toMatch(/necesita internet/);
    expect(aviso).toMatch(/Nada de lo que hagas[^.]*se guarda/);
    // Y el juego va DESPUÉS del aviso, nunca antes.
    expect(HTML.indexOf('id="aviso"')).toBeLessThan(HTML.indexOf('id="juego"'));
  });
});

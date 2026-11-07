// ============================================================================
// familia-vigilante.test.ts — el vigilante de Retail y la envoltura de las recetas
// ============================================================================
// El vigilante no se puede correr de verdad hasta que su Action esté en `main`, así que todo lo que decide se prueba aquí sin red: el fetch y el disco
// son falsos y el reloj va por parámetro. La mayoría de los casos son los que DEBEN frenar: un archivo fuera de la lista, Retail caído, las tiendas
// abiertas, el interruptor apagado. Un vigilante se escribe para el día en que algo sale mal.
// ============================================================================
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { envolverRecetas, partir, RecetaRechazada, revisarContraDynamic, variablesDe } from "../scripts/familia/envolver-recetas.mjs";
import {
  avisar,
  cuerpoDelAviso,
  decidirCaida,
  decidirCorrida,
  detectar,
  firmaDe,
  fueraDeHorarioDeTienda,
  huella,
  huellaDeCarpeta,
  leerInterruptores,
  mirar,
  puedePublicar,
  RUTA_COMPARTIDOS,
  tomar,
} from "../scripts/familia/vigilante.mjs";

const RAIZ = join(__dirname, "..");
const leer = (ruta: string) => readFileSync(join(RAIZ, ruta), "utf8");

// La forma real de recetas.css, en chico.
const RECETAS = `/* el vidrio */
:root {
  --gota-fondo: color-mix(in srgb, var(--color-vidrio) 58%, transparent); /* con un ; adentro del comentario */
  --placa-sombra: inset 0 1px 0 color-mix(in srgb, var(--color-tinta) 5%, transparent), 0 6px 14px -8px var(--color-sombra);
}

@media screen {
  /* en oscuro */
  :root[data-tema="oscuro"] {
    --gota-fondo: color-mix(in srgb, var(--color-tinta) 15%, transparent);
  }
}

@media (prefers-reduced-transparency: reduce) {
  :root,
  :root[data-tema="oscuro"] {
    --gota-fondo: var(--color-papel);
  }
}
`;

describe("la envoltura de las recetas", () => {
  const salida = envolverRecetas(RECETAS, { origen: "prueba" });
  const piezas = partir(salida).filter((p: { tipo: string }) => p.tipo === "bloque") as { preludio: string; cuerpo: string }[];

  it("con el vidrio apagado no queda ningún selector vivo: todo cuelga de data-vidrio", () => {
    const sinComentarios = salida.replace(/\/\*[\s\S]*?\*\//g, "");
    const selectores = [...sinComentarios.matchAll(/([^;{}]+)\{/g)].map((m) => m[1].trim()).filter((s) => !s.startsWith("@"));
    expect(selectores.length).toBeGreaterThan(2);
    for (const s of selectores) {
      for (const parte of s.split(",")) expect(parte.trim(), `selector: ${parte}`).toMatch(/^:root\[data-vidrio\]/);
    }
  });

  it("no se pierde ni se inventa ninguna variable", () => {
    expect([...variablesDe(salida)].sort()).toEqual([...variablesDe(RECETAS)].sort());
  });

  it("responde a los dos caminos al oscuro de Dynamic: a mano y por el aparato", () => {
    expect(salida).toContain(':root[data-vidrio][data-tema="oscuro"]');
    const delAparato = piezas.find((p) => p.preludio === "@media screen and (prefers-color-scheme: dark)");
    expect(delAparato?.cuerpo).toContain(':root[data-vidrio]:not([data-tema="claro"])');
    expect(delAparato?.cuerpo).toContain("--gota-fondo");
  });

  it("el oscuro no se escapa al papel: imprimir sigue saliendo en claro", () => {
    for (const p of piezas) {
      if (p.cuerpo.includes('[data-tema="oscuro"]') && !p.preludio.includes("reduced-transparency")) expect(p.preludio).toContain("screen");
    }
    expect(piezas.map((p) => p.preludio)).not.toContain("@media (prefers-color-scheme: dark)");
  });

  it("quien pidió menos transparencia le gana a los tres temas, también al del aparato", () => {
    const i = piezas.findIndex((p) => p.preludio.includes("reduced-transparency"));
    const oscuro = piezas.findIndex((p) => p.preludio.includes("prefers-color-scheme"));
    expect(i).toBeGreaterThan(oscuro);
    expect(piezas[i].cuerpo).toContain(":root[data-vidrio],");
    expect(piezas[i].cuerpo).toContain(':root[data-vidrio][data-tema="oscuro"],');
    expect(piezas[i].cuerpo).toContain(':root[data-vidrio]:not([data-tema="claro"])');
  });

  it("dice de dónde salió", () => {
    expect(salida).toContain("GENERADO");
    expect(salida).toContain("prueba");
  });

  for (const [nombre, css] of [
    ["una regla de clase", ".btn-cayla { border-radius: 999px; }"],
    ["un @keyframes: su nombre es global y pisaría al de Dynamic", "@keyframes aletea { from { opacity: 0; } to { opacity: 1; } }"],
    ["un @layer: cambia el orden de las capas de Tailwind", "@layer components { :root { --x: 1; } }"],
    ["un @layer sin cuerpo", "@layer a, b;"],
    ["un @import", '@import "./otra.css";'],
    ["una declaración que no es variable dentro de :root", ":root { --x: 1; color: red; }"],
    ["una regla anidada dentro de :root", ":root { .x { color: red; } }"],
    ["otro selector", "html { --x: 1; }"],
    ["un :root con otro atributo", ':root[data-tema="claro"] { --x: 1; }'],
    ["otra media query", "@media (min-width: 40rem) { :root { --x: 1; } }"],
    ["una clase dentro del oscuro", "@media screen { .x { --a: 1; } }"],
    ["un :root suelto dentro de @media screen", "@media screen { :root { --a: 1; } }"],
    ["un bloque sin cerrar", ":root { --x: 1;"],
    ["texto suelto", "esto no es css"],
  ] as const) {
    it(`se niega con ${nombre}`, () => {
      expect(() => envolverRecetas(css)).toThrow(RecetaRechazada);
    });
  }

  describe("«el vidrio que aguanta» de Retail: viajan las variables y no sus reglas", () => {
    const macizo = (regla = '*, *::before, *::after { backdrop-filter: none !important; }') =>
      `@media (prefers-reduced-transparency: reduce), (prefers-contrast: more) { :root, :root[data-tema="oscuro"] { --gota-fondo: var(--color-papel); } ${regla} }`;
    const contraste = (variable = "--color-taupe", regla = '[class*="text-tinta/"] { color: var(--color-tinta); }') =>
      `@media (prefers-contrast: more) { :root, :root[data-tema="oscuro"] { ${variable}: var(--color-tinta); } ${regla} }`;

    it("cuelga las variables del atributo y deja afuera la regla sobre todo: esa la escribe piezas.css, solo para el panel", () => {
      const salida = envolverRecetas(macizo());
      expect(salida).toContain(":root[data-vidrio]");
      expect(salida).toContain("--gota-fondo");
      expect(salida).not.toContain("backdrop-filter");
    });
    it("el bloque de más contraste no deja nada: lo escribe piezas.css después de los colores de marca", () => {
      const salida = envolverRecetas(contraste());
      expect(salida).not.toContain("--color-taupe");
      expect(salida).not.toContain("text-tinta/");
    });
    it("se niega con una regla nueva adentro: alguien tiene que escribir su equivalente", () => {
      expect(() => envolverRecetas(macizo(".btn-nuevo { color: red; }"))).toThrow(RecetaRechazada);
      expect(() => envolverRecetas(contraste("--color-taupe", ".btn-nuevo { color: red; }"))).toThrow(RecetaRechazada);
    });
    it("se niega si el bloque de más contraste toca otro color", () => {
      expect(() => envolverRecetas(contraste("--color-rojo"))).toThrow(RecetaRechazada);
    });
    it("los colores que pisa el bloque de más contraste no cuentan como choque con Dynamic", () => {
      expect(revisarContraDynamic(contraste(), { cssDeDynamic: "--color-taupe: #000; --color-tinta: #111;" })).toEqual([]);
    });
    it("piezas.css tiene de verdad lo que aquí se deja afuera", () => {
      const piezas = readFileSync(join(RAIZ, "apps/web/app/estilos/vidrio/piezas.css"), "utf8");
      expect(piezas).toContain("@media (prefers-reduced-transparency: reduce), (prefers-contrast: more)");
      expect(piezas).toContain("@media (prefers-contrast: more)");
      expect(piezas).toMatch(/--color-taupe:\s*var\(--color-tinta\)/);
      expect(piezas).toMatch(/--color-borde-control:\s*var\(--color-tinta\)/);
    });
  });

  it("avisa de lo que un navegador no avisa: una variable que no existe queda en nada, en silencio", () => {
    const css = ":root { --a: var(--color-nuevo); --b: var(--color-tinta); }";
    const dynamic = "--color-tinta: #1a1a18;";
    expect(revisarContraDynamic(css, { cssDeDynamic: dynamic })).toEqual(["la receta pide --color-nuevo, que Dynamic no tiene"]);
    expect(revisarContraDynamic(css, { cssDeDynamic: dynamic, conocidas: ["--color-nuevo"] })).toEqual([]);
  });

  it("no deja redefinir algo de Dynamic ni meter un valor de marca por la receta", () => {
    expect(revisarContraDynamic(":root { --ease-salida: linear; }", { cssDeDynamic: "--ease-salida: x;" })[0]).toContain("redefine --ease-salida");
    expect(revisarContraDynamic(":root { --color-nuevo: #000; }", { cssDeDynamic: "" })[0]).toContain("valor de marca");
  });
});

describe("el horario de tienda (UTC-5 fijo)", () => {
  for (const [peru, utc, fuera] of [
    ["14:00", "2026-11-05T19:00:00Z", false],
    ["21:59", "2026-11-06T02:59:00Z", false],
    ["22:00", "2026-11-06T03:00:00Z", true],
    ["00:30", "2026-11-06T05:30:00Z", true],
    ["04:59", "2026-11-06T09:59:00Z", true],
    ["05:00", "2026-11-06T10:00:00Z", false],
  ] as const) {
    it(`a las ${peru} de Perú ${fuera ? "ya cerraron" : "están abiertas"}`, () => {
      expect(fueraDeHorarioDeTienda(new Date(utc))).toBe(fuera);
    });
  }
});

describe("los interruptores", () => {
  it("sin variables: vigila y no publica", () => {
    expect(leerInterruptores({})).toEqual({ apagado: false, publicar: false });
  });
  it("«apagado» apaga", () => {
    expect(leerInterruptores({ FAMILIA_VIGILANTE: "apagado" }).apagado).toBe(true);
  });
  it("solo «si» enciende la publicación: el lado seguro es no publicar", () => {
    expect(leerInterruptores({ FAMILIA_PUBLICAR: "si" }).publicar).toBe(true);
    for (const v of ["sí", "true", "1", "yes", ""]) expect(leerInterruptores({ FAMILIA_PUBLICAR: v }).publicar, v).toBe(false);
  });
});

const NOCHE = new Date("2026-11-06T04:00:00Z"); // 23:00 en Perú
const TARDE = new Date("2026-11-05T19:00:00Z"); // 14:00 en Perú
const COMPARTIDOS = {
  origen: { repositorio: "cayla/retail", rama: "main" },
  viajan: [
    { retail: "recetas.css", dynamic: "recetas.generado.css", forma: "envuelta", en_el_arbol: false, huella: huella(RECETAS), tomada_de: "viejo1", tomada_el: "2026-11-01" },
    { retail: "contrato.json", dynamic: "docs/familia/contrato.json", forma: "identica", en_el_arbol: true, huella: huella('{"version":4}'), tomada_de: null, tomada_el: null },
  ],
  se_miran: [{ retail: "ui", excepto: ["recetas.css"], huella: huellaDeCarpeta([{ name: "Modal.tsx", sha: "a" }]), tomada_de: "viejo1", tomada_el: "2026-11-01" }],
};
const PREPARADO = { interruptores: { apagado: false, publicar: true }, tocados: ["docs/familia/contrato.json", RUTA_COMPARTIDOS], compartidos: COMPARTIDOS, pruebas: "success", frenos: [], ahora: NOCHE };

describe("las tres condiciones para publicar", () => {
  const motivos = (cambios: object) => puedePublicar({ ...PREPARADO, ...cambios }).motivos.map((m: { clave: string }) => m.clave);

  it("las tres cumplidas y la variable encendida: se publica", () => {
    expect(puedePublicar(PREPARADO)).toEqual({ publicar: true, motivos: [] });
  });
  it("con la variable apagada no se publica, aunque se cumpla todo", () => {
    expect(puedePublicar({ ...PREPARADO, interruptores: { apagado: false, publicar: false } }).publicar).toBe(false);
  });
  for (const ajeno of ["apps/web/app/globals.css", "supabase/migrations/0600_x.sql", ".github/workflows/tests.yml", "apps/web/components/ui/boton.tsx"]) {
    it(`un archivo fuera de la lista frena: ${ajeno}`, () => {
      expect(motivos({ tocados: [...PREPARADO.tocados, ajeno] })).toEqual(["fuera-de-lista"]);
    });
  }
  it("pruebas en rojo frenan", () => {
    expect(motivos({ pruebas: "failure" })).toEqual(["pruebas"]);
  });
  it("pruebas que no llegaron a correr frenan: que no fallen no significa que pasaron", () => {
    expect(motivos({ pruebas: "skipped" })).toEqual(["pruebas"]);
  });
  it("con las tiendas abiertas no se publica", () => {
    expect(motivos({ ahora: TARDE })).toEqual(["horario"]);
  });
  it("un freno sin resolver no se publica", () => {
    expect(motivos({ frenos: [{ ruta: "x", tipo: "receta", huella: "", texto: "x" }] })).toEqual(["frenos"]);
  });
  it("sin nada tocado no hay nada que publicar", () => {
    expect(motivos({ tocados: [] })).toEqual(["nada"]);
  });
  it("dice todos los motivos, no solo el primero", () => {
    expect(motivos({ pruebas: "failure", ahora: TARDE, tocados: ["apps/web/app/layout.tsx"] })).toEqual(["fuera-de-lista", "pruebas", "horario"]);
  });
});

const LECTURA_AL_DIA = {
  cabeza: "nuevo1",
  archivos: { "recetas.css": Buffer.from(RECETAS), "contrato.json": Buffer.from('{"version":4}') },
  carpetas: { ui: [{ name: "Modal.tsx", sha: "a" }, { name: "recetas.css", sha: "ignorada" }] },
};
const CONTRATO_LOCAL = { version: 4 };
const detectarCon = (cambios = {}) => detectar({ compartidos: COMPARTIDOS, lectura: { ...LECTURA_AL_DIA, ...cambios }, contratoLocal: CONTRATO_LOCAL });

describe("qué cuenta como cambio", () => {
  it("sin cambios no hay nada, aunque Retail haya hecho cien commits de otra cosa", () => {
    const d = detectarCon({ cabeza: "otro-commit" });
    expect([d.viajan, d.tareas, d.frenos]).toEqual([[], [], []]);
  });

  it("una receta cambiada viaja", () => {
    const d = detectarCon({ archivos: { ...LECTURA_AL_DIA.archivos, "recetas.css": Buffer.from(`${RECETAS}/* otra */`) } });
    expect(d.viajan.map((v: { retail: string }) => v.retail)).toEqual(["recetas.css"]);
  });

  it("una pieza cambiada es una tarea: no se copia", () => {
    const d = detectarCon({ carpetas: { ui: [{ name: "Modal.tsx", sha: "b" }] } });
    expect(d.viajan).toEqual([]);
    expect(d.tareas.map((t: { retail: string }) => t.retail)).toEqual(["ui"]);
  });

  it("una pieza nueva también es una tarea", () => {
    expect(detectarCon({ carpetas: { ui: [{ name: "Modal.tsx", sha: "a" }, { name: "Nueva.tsx", sha: "c" }] } }).tareas).toHaveLength(1);
  });

  it("recetas.css dentro de la carpeta no cuenta dos veces: viajar no es una tarea", () => {
    expect(detectarCon({ carpetas: { ui: [{ name: "Modal.tsx", sha: "a" }, { name: "recetas.css", sha: "cambió" }] } }).tareas).toEqual([]);
  });

  it("un archivo que desaparece con Retail arriba frena y se dice: no es lo mismo que una caída", () => {
    const d = detectarCon({ archivos: { ...LECTURA_AL_DIA.archivos, "recetas.css": null } });
    expect(d.frenos.map((f: { tipo: string }) => f.tipo)).toEqual(["desaparecio"]);
  });

  it("una carpeta que desaparece, igual", () => {
    expect(detectarCon({ carpetas: { ui: null } }).frenos.map((f: { tipo: string }) => f.tipo)).toEqual(["desaparecio"]);
  });

  it("un contrato más viejo que el de Dynamic no pisa al nuevo", () => {
    const d = detectarCon({ archivos: { ...LECTURA_AL_DIA.archivos, "contrato.json": Buffer.from('{"version":3}') } });
    expect(d.viajan).toEqual([]);
    expect(d.frenos.map((f: { tipo: string }) => f.tipo)).toEqual(["retail-atras"]);
  });

  it("un contrato ilegible tampoco", () => {
    const d = detectarCon({ archivos: { ...LECTURA_AL_DIA.archivos, "contrato.json": Buffer.from("no es json") } });
    expect(d.frenos.map((f: { tipo: string }) => f.tipo)).toEqual(["retail-atras"]);
  });
});

describe("qué hace la corrida con eso", () => {
  const cambioDeReceta = detectarCon({ archivos: { ...LECTURA_AL_DIA.archivos, "recetas.css": Buffer.from(`${RECETAS}/* otra */`) } });
  const sinPublicar = { apagado: false, publicar: false };
  const conPublicar = { apagado: false, publicar: true };

  it("al día", () => {
    expect(decidirCorrida({ deteccion: detectarCon(), estado: {}, interruptores: sinPublicar, ahora: TARDE }).accion).toBe("al-dia");
  });
  it("un cambio de receta nuevo se prueba", () => {
    expect(decidirCorrida({ deteccion: cambioDeReceta, estado: {}, interruptores: sinPublicar, ahora: TARDE }).accion).toBe("probar");
  });
  it("el mismo cambio a la hora siguiente no hace nada: ni pnpm install, ni escritura, ni otro aviso", () => {
    const estado = { firma: firmaDe(cambioDeReceta) };
    expect(decidirCorrida({ deteccion: cambioDeReceta, estado, interruptores: sinPublicar, ahora: TARDE }).accion).toBe("nada");
  });
  it("un push de Retail que no toca estos archivos no cambia la firma", () => {
    const otro = { ...cambioDeReceta, cabeza: "otro-commit" };
    expect(firmaDe(otro)).toBe(firmaDe(cambioDeReceta));
  });
  it("una tarea de pieza se avisa sin correr las pruebas: no hay nada que probar", () => {
    const d = detectarCon({ carpetas: { ui: [{ name: "Modal.tsx", sha: "b" }] } });
    expect(decidirCorrida({ deteccion: d, estado: {}, interruptores: sinPublicar, ahora: TARDE }).accion).toBe("escribir");
  });

  it("LA TRAMPA: lo que no se publicó a las 14:00 por el horario, se retoma a las 23:00", () => {
    const estado = { firma: firmaDe(cambioDeReceta), solo_faltaba_permiso: true };
    expect(decidirCorrida({ deteccion: cambioDeReceta, estado, interruptores: conPublicar, ahora: TARDE }).accion).toBe("nada");
    expect(decidirCorrida({ deteccion: cambioDeReceta, estado, interruptores: conPublicar, ahora: NOCHE }).accion).toBe("probar");
  });
  it("lo que ya se publicó no se vuelve a publicar", () => {
    const firma = firmaDe(cambioDeReceta);
    const estado = { firma, solo_faltaba_permiso: true, publicada: firma };
    expect(decidirCorrida({ deteccion: cambioDeReceta, estado, interruptores: conPublicar, ahora: NOCHE }).accion).toBe("nada");
  });
  it("lo que dio rojo no se reintenta toda la noche: espera a que cambie o a que alguien lo mire", () => {
    const estado = { firma: firmaDe(cambioDeReceta), solo_faltaba_permiso: false, pruebas: "failure" };
    expect(decidirCorrida({ deteccion: cambioDeReceta, estado, interruptores: conPublicar, ahora: NOCHE }).accion).toBe("nada");
  });
});

describe("cuando Retail no responde", () => {
  const h = (horas: number) => new Date(TARDE.getTime() + horas * 3_600_000);

  it("la primera vez solo anota desde cuándo", () => {
    const d = decidirCaida({}, TARDE);
    expect(d).toMatchObject({ escribir: true, avisar: false });
    expect(d.estado.caido_desde).toBe(TARDE.toISOString());
  });
  it("a las 23 horas sigue callado, sin escribir", () => {
    expect(decidirCaida({ caido_desde: TARDE.toISOString() }, h(23))).toMatchObject({ escribir: false, avisar: false });
  });
  it("a las 24 horas avisa", () => {
    expect(decidirCaida({ caido_desde: TARDE.toISOString() }, h(24))).toMatchObject({ escribir: true, avisar: true });
  });
  it("a las 25 horas no vuelve a avisar: una sola vez", () => {
    expect(decidirCaida({ caido_desde: TARDE.toISOString(), ciego_avisado: true }, h(25))).toMatchObject({ escribir: false, avisar: false });
  });
});

// Un GitHub de mentira: registra qué se escribió, para poder afirmar lo que NO se escribió.
function githubFalso(opciones: {
  retail?: "ok" | "caido" | "http500" | "privado";
  recetas?: string | null;
  contrato?: string;
  ui?: { name: string; sha: string }[];
  issues?: object[];
  propioCaido?: boolean;
} = {}) {
  const escrituras: { metodo: string; url: string; cuerpo: Record<string, string> }[] = [];
  const pedidos: string[] = [];
  const issues = opciones.issues ?? [];
  const fetcher = async (url: string, init: { method?: string; body?: string } = {}) => {
    pedidos.push(url);
    const metodo = init.method ?? "GET";
    if (url.includes("/repos/felipea92p-ux/cayla-dynamic/")) {
      if (opciones.propioCaido) throw new Error("GitHub caído");
      if (metodo === "GET") return Response.json(issues);
      const cuerpo = JSON.parse(init.body ?? "{}");
      escrituras.push({ metodo, url, cuerpo });
      return Response.json({ number: 7 });
    }
    if (opciones.retail === "caido") throw new Error("sin red");
    if (opciones.retail === "http500") return new Response("", { status: 500 });
    if (url.endsWith("/commits/main")) return opciones.retail === "privado" ? new Response("", { status: 404 }) : Response.json({ sha: "nuevo1" });
    if (url.includes("/compare/")) return Response.json({ files: [{ filename: "ui/Modal.tsx" }, { filename: "ui/recetas.css" }, { filename: "otra/cosa.ts" }] });
    if (url.includes("/contents/ui")) return Response.json(opciones.ui ?? [{ name: "Modal.tsx", sha: "a" }]);
    if (url.endsWith("/recetas.css")) return opciones.recetas === null ? new Response("", { status: 404 }) : new Response(opciones.recetas ?? RECETAS);
    if (url.endsWith("/contrato.json")) return new Response(opciones.contrato ?? '{"version":4}');
    throw new Error(`pedido inesperado: ${url}`);
  };
  return { fetcher: fetcher as unknown as typeof fetch, escrituras, pedidos };
}

function discoFalso() {
  const archivos = new Map<string, string>([
    [RUTA_COMPARTIDOS, JSON.stringify(COMPARTIDOS)],
    ["docs/familia/contrato.json", '{"version":4}'],
    ["docs/familia/deuda.json", JSON.stringify({ deuda: [{ clave: "claro:vidrio", hoy: null }, { clave: "claro:sombra", hoy: null }] })],
    ["apps/web/app/globals.css", "@theme { --color-tinta: #1a1a18; --color-papel: #fbf8f2; }"],
  ]);
  return {
    archivos,
    leer: (r: string) => {
      const t = archivos.get(r);
      if (t === undefined) throw new Error(`no existe ${r}`);
      return t;
    },
    escribir: (r: string, t: string) => void archivos.set(r, t),
  };
}

const ENV = { GH_TOKEN: "x", GITHUB_REPOSITORY: "felipea92p-ux/cayla-dynamic", RUNNER_TEMP: "/tmp" };
const issue = (estado: object, abierto = true, numero = 7) => ({ number: numero, state: abierto ? "open" : "closed", body: `<!-- cayla:familia-vigilante ${JSON.stringify(estado)} -->\n\nCuerpo anterior.` });
const correr = (g: ReturnType<typeof githubFalso>, env: object = ENV, ahora = TARDE, disco = discoFalso()) => mirar({ fetcher: g.fetcher, env, ahora, disco, registrar: () => {} });

describe("una corrida de punta a punta", () => {
  it("con el interruptor apagado no se pide NADA a la red", async () => {
    const g = githubFalso();
    const r = await correr(g, { ...ENV, FAMILIA_VIGILANTE: "apagado" });
    expect(r.accion).toBe("apagado");
    expect(g.pedidos).toEqual([]);
    expect(g.escrituras).toEqual([]);
  });

  it("al día y sin aviso abierto: ni una escritura y no pide probar", async () => {
    const g = githubFalso();
    const r = await correr(g);
    expect(r).toMatchObject({ accion: "al-dia", salidas: { probar: "no" } });
    expect(g.escrituras).toEqual([]);
  });

  it("al día con un aviso abierto: lo cierra", async () => {
    const g = githubFalso({ issues: [issue({ firma: "vieja" })] });
    await correr(g);
    expect(g.escrituras).toHaveLength(1);
    expect(g.escrituras[0].cuerpo.state).toBe("closed");
  });

  for (const [nombre, retail] of [["sin red", "caido"], ["con un 500", "http500"], ["privado o renombrado", "privado"]] as const) {
    it(`Retail ${nombre}: termina sin fallar, no prueba nada y no abre nada`, async () => {
      const g = githubFalso({ retail });
      const r = await correr(g);
      expect(r).toMatchObject({ accion: "callar", salidas: { probar: "no" } });
      expect(g.escrituras.every((e) => e.cuerpo.state !== "open")).toBe(true);
    });
  }

  it("Retail caído hace una hora: ni una escritura", async () => {
    const g = githubFalso({ retail: "caido", issues: [issue({ caido_desde: TARDE.toISOString() }, false)] });
    await correr(g, ENV, new Date(TARDE.getTime() + 3_600_000));
    expect(g.escrituras).toEqual([]);
  });

  it("Retail caído hace 24 horas: abre el aviso una vez, conservando lo que ya decía", async () => {
    const g = githubFalso({ retail: "caido", issues: [issue({ caido_desde: TARDE.toISOString() }, false)] });
    const r = await correr(g, ENV, new Date(TARDE.getTime() + 24 * 3_600_000));
    expect(r.accion).toBe("ciego");
    expect(g.escrituras).toHaveLength(1);
    expect(g.escrituras[0].cuerpo.state).toBe("open");
    expect(g.escrituras[0].cuerpo.body).toContain("más de 24 horas");
    expect(g.escrituras[0].cuerpo.body).toContain("Cuerpo anterior.");
  });

  it("GitHub entero caído: tampoco falla", async () => {
    const g = githubFalso({ retail: "caido", propioCaido: true });
    await expect(correr(g)).resolves.toMatchObject({ accion: "callar" });
  });

  it("Retail vuelve: se olvida la caída y el aviso se cierra si no hay nada", async () => {
    const g = githubFalso({ issues: [issue({ caido_desde: TARDE.toISOString(), ciego_avisado: true })] });
    await correr(g);
    expect(g.escrituras[0].cuerpo.state).toBe("closed");
    expect(g.escrituras[0].cuerpo.body).not.toContain("caido_desde\":\"");
  });

  it("solo mira issues creados por la Action: en un repositorio público cualquiera puede abrir uno con la misma marca", async () => {
    const g = githubFalso();
    await correr(g);
    expect(g.pedidos.some((u) => u.includes("creator=github-actions%5Bbot%5D"))).toBe(true);
  });

  it("una receta que dejó de ser solo variables no llega ni a instalar: se avisa", async () => {
    const g = githubFalso({ recetas: `${RECETAS}\n.nueva { color: red; }` });
    const r = await correr(g);
    expect(r).toMatchObject({ accion: "escribir", salidas: { probar: "no" } });
    expect(g.escrituras[0].metodo).toBe("POST");
    expect(g.escrituras[0].cuerpo.body).toContain(".nueva");
  });

  it("y a la hora siguiente no repite el aviso", async () => {
    const primero = githubFalso({ recetas: `${RECETAS}\n.nueva { color: red; }` });
    await correr(primero);
    const g = githubFalso({ recetas: `${RECETAS}\n.nueva { color: red; }`, issues: [{ number: 7, state: "open", body: primero.escrituras[0].cuerpo.body }] });
    const r = await correr(g);
    expect(r.accion).toBe("nada");
    expect(g.escrituras).toEqual([]);
  });

  it("una receta que pide un color que Dynamic no tiene no viaja", async () => {
    const g = githubFalso({ recetas: ":root { --nueva: var(--color-que-no-existe); }" });
    const r = await correr(g);
    expect(r.accion).toBe("escribir");
    expect(g.escrituras[0].cuerpo.body).toContain("--color-que-no-existe");
  });

  it("un archivo que desaparece se avisa con la Retail arriba: no se calla", async () => {
    const g = githubFalso({ recetas: null });
    const r = await correr(g);
    expect(r.accion).toBe("escribir");
    expect(g.escrituras[0].cuerpo.body).toContain("ya no está en Retail");
  });

  it("una pieza cambiada abre la tarea y nombra el archivo, sin la receta ni lo de otra carpeta", async () => {
    const g = githubFalso({ ui: [{ name: "Modal.tsx", sha: "b" }] });
    await correr(g);
    const cuerpo = g.escrituras[0].cuerpo.body;
    expect(cuerpo).toContain("`Modal.tsx`");
    expect(cuerpo).toContain("no se puede copiar");
    expect(cuerpo).not.toContain("recetas.css`");
    expect(cuerpo).not.toContain("cosa.ts");
  });

  it("un contrato nuevo se prepara en el disco y pide las pruebas, sin escribir todavía el aviso", async () => {
    const g = githubFalso({ contrato: '{"version":5}' });
    const disco = discoFalso();
    const r = await correr(g, ENV, TARDE, disco);
    expect(r).toMatchObject({ accion: "probar", salidas: { probar: "si" } });
    expect(g.escrituras).toEqual([]);
    expect(disco.archivos.get("docs/familia/contrato.json")).toBe('{"version":5}');
    expect(JSON.parse(disco.archivos.get(RUTA_COMPARTIDOS) ?? "").viajan[1].huella).toBe(huella('{"version":5}'));
  });

  it("una receta cambiada, con en_el_arbol en false, no se copia al árbol de la app", async () => {
    const g = githubFalso({ recetas: `${RECETAS}/* otra */` });
    const disco = discoFalso();
    const r = await correr(g, ENV, TARDE, disco);
    expect(r.accion).toBe("probar");
    expect(disco.archivos.has("recetas.generado.css")).toBe(false);
  });

  it("modo seco: lee y dice, sin escribir y sin tocar el disco", async () => {
    const g = githubFalso({ contrato: '{"version":5}' });
    const disco = discoFalso();
    const r = await mirar({ fetcher: g.fetcher, env: ENV, ahora: TARDE, disco, seco: true, registrar: () => {} });
    expect(r.accion).toBe("probar");
    expect(r.salidas.probar).toBe("no");
    expect(g.escrituras).toEqual([]);
    expect(disco.archivos.get("docs/familia/contrato.json")).toBe('{"version":4}');
  });
});

describe("el aviso después de las pruebas", () => {
  const deteccion = { cabeza: "nuevo1", viajan: [{ retail: "contrato.json", tomada_de: null }], tareas: [], frenos: [] };
  const resultado = { firma: "f1", deteccion, estado: {}, aviso: null };
  const corridas = (env: object, tocados: string[], ahora = NOCHE) => {
    const g = githubFalso();
    return avisar({ fetcher: g.fetcher, env: { ...ENV, ...env }, ahora, disco: discoFalso(), resultado, tocados }).then((r: { salidas: Record<string, string> }) => ({ ...r, g }));
  };
  const lista = ["docs/familia/contrato.json", RUTA_COMPARTIDOS];

  it("modo solo avisa: abre un aviso, dice las pruebas, y no publica", async () => {
    const r = await corridas({ PRUEBAS: "success" }, lista);
    expect(r.salidas.publicar).toBe("no");
    expect(r.g.escrituras).toHaveLength(1);
    expect(r.g.escrituras[0].metodo).toBe("POST");
    expect(r.g.escrituras[0].cuerpo.body).toContain("**verde**");
    expect(r.g.escrituras[0].cuerpo.body).toContain("FAMILIA_PUBLICAR");
  });
  it("con la variable encendida, de noche y en verde: publica", async () => {
    const r = await corridas({ PRUEBAS: "success", FAMILIA_PUBLICAR: "si" }, lista);
    expect(r.salidas).toMatchObject({ publicar: "si", commit: "nuevo1", aviso: "7" });
  });
  it("con la variable encendida y un archivo fuera de la lista: no", async () => {
    const r = await corridas({ PRUEBAS: "success", FAMILIA_PUBLICAR: "si" }, [...lista, "apps/web/app/globals.css"]);
    expect(r.salidas.publicar).toBe("no");
    expect(r.g.escrituras[0].cuerpo.body).toContain("globals.css");
  });
  it("con la variable encendida y las tiendas abiertas: no, y queda marcado para la noche", async () => {
    const r = await corridas({ PRUEBAS: "success", FAMILIA_PUBLICAR: "si" }, lista, TARDE);
    expect(r.salidas.publicar).toBe("no");
    expect(r.g.escrituras[0].cuerpo.body).toContain('"solo_faltaba_permiso":true');
  });
  it("en rojo no queda marcado para reintentar", async () => {
    const r = await corridas({ PRUEBAS: "failure", FAMILIA_PUBLICAR: "si" }, lista);
    expect(r.salidas.publicar).toBe("no");
    expect(r.g.escrituras[0].cuerpo.body).toContain('"solo_faltaba_permiso":false');
    expect(r.g.escrituras[0].cuerpo.body).toContain("**rojo**");
  });
});

describe("tomar", () => {
  it("«piezas» da por vistas las tareas y no toca lo que viaja", async () => {
    const g = githubFalso({ ui: [{ name: "Modal.tsx", sha: "b" }], contrato: '{"version":5}' });
    const disco = discoFalso();
    await tomar({ fetcher: g.fetcher, env: ENV, disco, cuando: "2026-11-05", que: "piezas", registrar: () => {} });
    const nuevo = JSON.parse(disco.archivos.get(RUTA_COMPARTIDOS) ?? "");
    expect(nuevo.se_miran[0].huella).toBe(huellaDeCarpeta([{ name: "Modal.tsx", sha: "b" }]));
    expect(disco.archivos.get("docs/familia/contrato.json")).toBe('{"version":4}');
  });
  it("«viajan» toma lo que viaja y deja la tarea abierta", async () => {
    const g = githubFalso({ ui: [{ name: "Modal.tsx", sha: "b" }], contrato: '{"version":5}' });
    const disco = discoFalso();
    await tomar({ fetcher: g.fetcher, env: ENV, disco, cuando: "2026-11-05", que: "viajan", registrar: () => {} });
    const nuevo = JSON.parse(disco.archivos.get(RUTA_COMPARTIDOS) ?? "");
    expect(nuevo.se_miran[0].huella).toBe(COMPARTIDOS.se_miran[0].huella);
    expect(nuevo.viajan[1].tomada_de).toBe("nuevo1");
    expect(disco.archivos.get("docs/familia/contrato.json")).toBe('{"version":5}');
  });
  it("con una receta inválida frena y no da la huella por tomada", async () => {
    const g = githubFalso({ recetas: ".x { color: red; }" });
    const disco = discoFalso();
    const r = await tomar({ fetcher: g.fetcher, env: ENV, disco, cuando: "2026-11-05", que: "viajan", registrar: () => {} });
    expect(r.frenos).toHaveLength(1);
    expect(JSON.parse(disco.archivos.get(RUTA_COMPARTIDOS) ?? "").viajan[0].huella).toBe(COMPARTIDOS.viajan[0].huella);
  });
});

describe("cuerpoDelAviso", () => {
  it("lleva el enlace a lo que cambió", () => {
    const deteccion = { cabeza: "nuevo1abcdef", viajan: [{ retail: "recetas.css", tomada_de: "viejo1" }], tareas: [], frenos: [] };
    const c = cuerpoDelAviso({ compartidos: COMPARTIDOS, deteccion, tareas: [], pruebas: "success", publicacion: { publicar: false, motivos: [] }, ahora: TARDE });
    expect(c).toContain("https://github.com/cayla/retail/compare/viejo1...nuevo1abcdef");
    expect(c).toContain("14:00 (hora de Perú)");
  });
});

// Lo que de verdad está en el repositorio.
describe("docs/familia/compartidos.json", () => {
  const compartidos = JSON.parse(leer(RUTA_COMPARTIDOS));
  const sha = /^sha256:[0-9a-f]{64}$/;

  it("lee de Retail, en main", () => {
    expect(compartidos.origen).toEqual({ repositorio: "felipea92p-ux/cayla-retail", rama: "main" });
  });
  it("toda entrada tiene su huella y su motivo", () => {
    for (const a of compartidos.viajan) {
      expect(a.huella, a.retail).toMatch(sha);
      expect(a.por_que_viaja.length, a.retail).toBeGreaterThan(20);
      expect(["identica", "envuelta"], a.retail).toContain(a.forma);
    }
    for (const c of compartidos.se_miran) {
      expect(c.huella, c.retail).toMatch(sha);
      expect(c.por_que_no_viaja.length, c.retail).toBeGreaterThan(20);
    }
  });
  it("las recetas están en la lista", () => {
    expect(compartidos.viajan.map((a: { retail: string }) => a.retail)).toContain("apps/web/app/estilos/vidrio/recetas.css");
  });
  it("la huella del contrato es la del contrato que está aquí: nadie lo cambia sin que se note", () => {
    const c = compartidos.viajan.find((a: { forma: string }) => a.forma === "identica");
    expect(c.huella).toBe(huella(readFileSync(join(RAIZ, c.dynamic))));
  });
  it("lo que dice no estar en el árbol, no está; y lo que está lleva la huella de la que salió", () => {
    for (const a of compartidos.viajan) {
      expect(existsSync(join(RAIZ, a.dynamic)), a.dynamic).toBe(a.en_el_arbol);
      if (a.en_el_arbol && a.forma === "envuelta") expect(leer(a.dynamic)).toContain(a.huella);
    }
  });
});

describe("el workflow", () => {
  const texto = leer(".github/workflows/vigilante-familia.yml");
  const sinComentarios = texto.replace(/^\s*#.*$/gm, "");
  const [, vigilar, publicar] = sinComentarios.split(/^ {2}(?:vigilar|publicar):$/m);

  it("corre cada hora, fuera del minuto cero", () => {
    expect(texto).toMatch(/cron: "17 \* \* \* \*"/);
  });
  it("no usa ningún secreto: se puede subir sin crear nada", () => {
    expect(sinComentarios).not.toMatch(/secrets\./);
  });
  it("la parte de todos los días no tiene permiso de escribir código ni de abrir un PR", () => {
    expect(vigilar).toMatch(/contents: read/);
    expect(vigilar).not.toMatch(/contents: write|pull-requests: write|actions: write/);
    expect(sinComentarios).toMatch(/^permissions: \{\}$/m);
  });
  it("no instala nada si no hay qué probar: toda la preparación va condicionada", () => {
    const pasos = vigilar.split(/^ {6}- /m);
    for (const quien of ["pnpm/action-setup", "actions/setup-node", "pnpm install"]) {
      const paso = pasos.find((p) => p.includes(quien));
      expect(paso, quien).toBeDefined();
      expect(paso, quien).toMatch(/if: steps\.mirar\.outputs\.probar == 'si'/);
    }
  });
  it("publicar solo arranca con la variable encendida Y con la decisión del script", () => {
    expect(publicar).toMatch(/if: needs\.vigilar\.outputs\.publicar == 'si' && vars\.FAMILIA_PUBLICAR == 'si'/);
  });
  it("antes de publicar vuelve a mirar que no toque nada fuera de la lista, y fija el commit de Retail", () => {
    expect(publicar).toContain('tomar viajan --commit "$COMMIT"');
    expect(publicar.indexOf("revisar-tocados")).toBeLessThan(publicar.indexOf("git add"));
  });
  it("deja el comentario que exige la casa antes de fusionar, y fusiona con --merge", () => {
    expect(publicar).toContain("<!-- cayla:fusion-sesion -->");
    expect(publicar.indexOf("cayla:fusion-sesion")).toBeLessThan(publicar.indexOf("gh pr merge"));
    expect(publicar).toContain('--auto --merge');
  });
  it("dispara las pruebas sobre la rama: un PR de GITHUB_TOKEN no las dispara solo", () => {
    expect(publicar).toContain("gh workflow run tests.yml");
  });
  it("no escribe el huso con su nombre: la regla de la casa, UTC-5 fijo", () => {
    expect(texto + leer("scripts/familia/vigilante.mjs")).not.toMatch(/America\/Lima/);
  });
});

// ============================================================================
// familia.test.ts — Dynamic dice lo que el contrato de la familia dice, o lo declara como deuda
// ============================================================================
// `docs/familia/contrato.json` es el mismo archivo en CAYLA Retail y en CAYLA Dynamic. Desde la versión 4 Retail manda en diseño (Felipe,
// 2026-11-05), y Dynamic NO cumple esos valores hasta su Etapa 1: esta prueba no puede quedar en rojo, y tampoco puede mentir.
//
// Por eso cada valor del contrato cae en uno de dos lados, y los dos se miden contra `globals.css`:
//   · cumple: si mañana diverge, falla.
//   · está en `docs/familia/deuda.json`: si ya se pagó, falla hasta que se borre su línea; si lo que pinta Dynamic cambió a otro valor equivocado,
//     falla; y una deuda que no estaba el día uno, falla.
//
// El límite, para no creer de más: un archivo se puede editar, y una prueba sin memoria no ve la historia. Lo que sí hace es que meter una deuda de
// vuelta obligue a tocar DOS líneas de ESTE archivo (TOPE_DEUDA y DEUDA_DIA_UNO), que es justo lo que se busca en la revisión de un PR.
//
// CUANDO EXISTA LA CAPA `data-vidrio`, `medirMarca` es la función que hay que extender: lo que cuenta es lo que se pinta con el vidrio prendido.
// ============================================================================
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const RAIZ = join(__dirname, "..");
const leer = (ruta: string) => readFileSync(join(RAIZ, ruta), "utf8");
const sinComentarios = (css: string) => css.replace(/\/\*[\s\S]*?\*\//g, "");

type Radio = { funcion: string; px: number; retail: string | null; dynamic: string | null };
type Contrato = {
  version: number;
  quien_manda: { diseno: string; desde: string };
  marca: {
    colores_claro: Record<string, string>;
    colores_oscuro: Record<string, string>;
    tipografia: { sans: string; serif: string };
    radios: Radio[];
    tema: { atributo: string; claro: string; oscuro: string };
  };
  sistema: { id: string; regla: string }[];
  producto: { id: string; motivo: string }[];
  aplicacion_pendiente: { miembro: string; tema: string; que: string }[];
  pendientes: { id: string; estado: string; como_decidir: string; decision?: string }[];
};
type LineaDeuda = { clave: string; hoy: string | null };
type Problema = { tipo: string; clave: string; texto: string };

const contrato = JSON.parse(leer("docs/familia/contrato.json")) as Contrato;
const deuda = (JSON.parse(leer("docs/familia/deuda.json")) as { deuda: LineaDeuda[] }).deuda;

// Este número SOLO BAJA. Al pagar un valor: se borra su línea de deuda.json y se baja esto. Subirlo es la señal que se busca en un PR.
const TOPE_DEUDA = 22;
// La foto del 2026-11-05. No se le agregan claves: una deuda nueva no entra sin decidirlo a la vista de quien revise.
const DEUDA_DIA_UNO = new Set([
  "radio:boton", "radio:campo", "radio:tarjeta", "radio:cajon", "radio:hoja",
  "claro:borde-control", "claro:vidrio", "claro:sombra",
  "oscuro:crema", "oscuro:papel", "oscuro:hueso", "oscuro:sand", "oscuro:tinta", "oscuro:taupe", "oscuro:borde-control",
  "oscuro:rojo", "oscuro:rojo-profundo", "oscuro:verde", "oscuro:ambar", "oscuro:pizarra", "oscuro:vidrio", "oscuro:sombra",
]);

/** El texto entre las llaves del bloque que empieza con `cabecera`, contando llaves. */
function cuerpoDe(css: string, cabecera: string): string {
  const i = css.indexOf(cabecera);
  if (i < 0) throw new Error(`no encontré «${cabecera}» en globals.css`);
  const inicio = css.indexOf("{", i);
  let hondura = 1;
  let j = inicio + 1;
  for (; j < css.length && hondura > 0; j++) {
    if (css[j] === "{") hondura++;
    else if (css[j] === "}") hondura--;
  }
  return css.slice(inicio + 1, j - 1);
}

/** Las variables de un bloque: nombre sin los guiones → valor crudo. */
function variables(bloque: string): Record<string, string> {
  const salida: Record<string, string> = {};
  for (const m of bloque.matchAll(/--([a-z0-9-]+)\s*:\s*([^;]+);/gi)) salida[m[1]] = m[2].trim();
  return salida;
}

/** Un color ya resuelto: sigue los alias `var(--color-x)` dentro del mismo tema. Null si no existe. */
function color(nombre: string, tema: Record<string, string>, base: Record<string, string>): string | null {
  const crudo = tema[`color-${nombre}`] ?? base[`color-${nombre}`];
  if (!crudo) return null;
  const alias = /^var\(--color-([a-z0-9-]+)\)$/.exec(crudo);
  return alias ? color(alias[1], tema, base) : crudo.toLowerCase();
}

/** Un radio en píxeles, como texto para compararlo igual que un color. Null si el token no existe. */
function radio(crudo: string | undefined): string | null {
  if (!crudo) return null;
  const m = /^([\d.]+)(px|rem)$/.exec(crudo);
  if (!m) return crudo;
  return String(Number(m[1]) * (m[2] === "rem" ? 16 : 1));
}

function esperadoDe(c: Contrato): Record<string, string> {
  const salida: Record<string, string> = {};
  for (const [n, hex] of Object.entries(c.marca.colores_claro)) salida[`claro:${n}`] = hex.toLowerCase();
  for (const [n, hex] of Object.entries(c.marca.colores_oscuro)) salida[`oscuro:${n}`] = hex.toLowerCase();
  for (const r of c.marca.radios) if (r.dynamic) salida[`radio:${r.funcion}`] = String(r.px);
  return salida;
}

/** Lo que Dynamic pinta hoy, por cada clave del contrato. */
function medirMarca(cssCrudo: string, c: Contrato): Record<string, string | null> {
  const css = sinComentarios(cssCrudo);
  const base = variables(cuerpoDe(css, "@theme {"));
  const oscuro = variables(cuerpoDe(css, ':root[data-tema="oscuro"] {'));
  const salida: Record<string, string | null> = {};
  for (const n of Object.keys(c.marca.colores_claro)) salida[`claro:${n}`] = color(n, base, base);
  for (const n of Object.keys(c.marca.colores_oscuro)) salida[`oscuro:${n}`] = color(n, oscuro, base);
  for (const r of c.marca.radios) if (r.dynamic) salida[`radio:${r.funcion}`] = radio(base[r.dynamic]);
  return salida;
}

function compararMarca(args: {
  esperado: Record<string, string>;
  medido: Record<string, string | null>;
  deuda: LineaDeuda[];
  diaUno: Set<string>;
  tope: number;
}): Problema[] {
  const problemas: Problema[] = [];
  const enDeuda = new Map(args.deuda.map((l) => [l.clave, l]));
  for (const [clave, valor] of Object.entries(args.esperado)) {
    const medido = args.medido[clave] ?? null;
    const linea = enDeuda.get(clave);
    if (medido === valor && linea) {
      problemas.push({ tipo: "ya-pagada", clave, texto: `${clave} ya cumple (${valor}): borra su línea de deuda.json y baja TOPE_DEUDA` });
    } else if (medido !== valor && !linea) {
      problemas.push({ tipo: "diverge", clave, texto: `${clave}: el contrato dice ${valor} y Dynamic pinta ${medido}, sin deuda que lo declare` });
    } else if (medido !== valor && linea && linea.hoy !== medido) {
      problemas.push({ tipo: "deuda-movida", clave, texto: `${clave}: la deuda dice que hoy es ${linea.hoy} y Dynamic pinta ${medido}; ni lo viejo ni lo del contrato` });
    }
  }
  for (const l of args.deuda) {
    if (!(l.clave in args.esperado)) problemas.push({ tipo: "huerfana", clave: l.clave, texto: `${l.clave} está en la deuda y el contrato no lo pide` });
    if (!args.diaUno.has(l.clave)) problemas.push({ tipo: "deuda-nueva", clave: l.clave, texto: `${l.clave} no estaba en la deuda del 2026-11-05: una deuda nueva no entra sin decidirlo` });
  }
  if (args.deuda.length !== args.tope) {
    problemas.push({ tipo: "tope", clave: "(lista)", texto: `la deuda tiene ${args.deuda.length} líneas y TOPE_DEUDA dice ${args.tope}: este número solo baja` });
  }
  return problemas;
}

const cssCrudo = leer("apps/web/app/globals.css");
const esperado = esperadoDe(contrato);
const medido = medirMarca(cssCrudo, contrato);

describe("el contrato de la familia está bien armado", () => {
  it("es la versión 4 o posterior, y dice quién manda", () => {
    expect(contrato.version).toBeGreaterThanOrEqual(4);
    expect(contrato.quien_manda.diseno).toBe("retail");
  });

  it("cada pieza de las capas trae lo que su capa exige", () => {
    for (const s of contrato.sistema) expect(s.regla.length, `sistema ${s.id}`).toBeGreaterThan(20);
    for (const p of contrato.producto) expect(p.motivo.length, `producto ${p.id}: falta el motivo`).toBeGreaterThan(10);
  });

  it("los pendientes tienen id único y estado conocido; uno decidido dice qué se decidió", () => {
    const ids = contrato.pendientes.map((p) => p.id);
    expect(new Set(ids).size).toBe(ids.length);
    for (const p of contrato.pendientes) {
      expect(["abierto", "decidido"], `pendiente ${p.id}`).toContain(p.estado);
      expect(p.como_decidir.length, `pendiente ${p.id}`).toBeGreaterThan(10);
      if (p.estado === "decidido") expect(p.decision?.length ?? 0, `pendiente ${p.id}: falta la decisión`).toBeGreaterThan(10);
    }
  });

  it("mientras haya deuda, el contrato dice qué falta aplicar en Dynamic, y Retail no debe nada", () => {
    const deDynamic = contrato.aplicacion_pendiente.filter((a) => a.miembro === "dynamic");
    expect(deDynamic.length > 0).toBe(deuda.length > 0);
    expect(contrato.aplicacion_pendiente.filter((a) => a.miembro === "retail")).toEqual([]);
    for (const a of contrato.aplicacion_pendiente) expect(a.que.length, a.tema).toBeGreaterThan(20);
  });
});

describe("Dynamic dice lo que el contrato dice, salvo la deuda declarada", () => {
  it("el lector sí encuentra los tokens: no pasa en vacío por estar mal escrito", () => {
    expect(Object.keys(esperado).length).toBeGreaterThan(30);
    expect(medido["claro:crema"]).toMatch(/^#[0-9a-f]{6}$/);
    expect(medido["oscuro:crema"]).toMatch(/^#[0-9a-f]{6}$/);
    expect(medido["radio:pildora"]).toBe("999");
  });

  it("cada valor cumple o está en la deuda, y la deuda dice la verdad", () => {
    const problemas = compararMarca({ esperado, medido, deuda, diaUno: DEUDA_DIA_UNO, tope: TOPE_DEUDA });
    expect(problemas.map((p) => p.texto)).toEqual([]);
  });

  it("los dos caminos al oscuro —a mano y por el aparato— pintan lo mismo", () => {
    const css = sinComentarios(cssCrudo);
    const aMano = variables(cuerpoDe(css, ':root[data-tema="oscuro"] {'));
    const delAparato = variables(cuerpoDe(css, ':root:not([data-tema="claro"]) {'));
    expect(delAparato).toEqual(aMano);
    expect(Object.keys(aMano).length).toBeGreaterThan(5);
  });

  it("las dos letras de la familia son las que carga el layout", () => {
    const layout = leer("apps/web/app/layout.tsx");
    expect(layout).toContain(contrato.marca.tipografia.serif.replace(/ /g, "_"));
    expect(layout).toContain(contrato.marca.tipografia.sans.replace(/ /g, "_"));
  });

  it("el tema se llama como en la familia", () => {
    const tema = leer("apps/web/lib/use-tema.ts");
    expect(tema).toContain(`setAttribute("${contrato.marca.tema.atributo}"`);
    expect(cssCrudo).toContain(`[${contrato.marca.tema.atributo}="${contrato.marca.tema.oscuro}"]`);
    expect(cssCrudo).toContain(`[${contrato.marca.tema.atributo}="${contrato.marca.tema.claro}"]`);
  });
});

// Una prueba que siempre pasa no sirve. Cada caso rompe una cosa y exige que se note.
describe("el candado no está ciego", () => {
  const base = () => ({
    esperado: { "claro:rojo": "#b8412d", "radio:boton": "999" } as Record<string, string>,
    medido: { "claro:rojo": "#b8412d", "radio:boton": null } as Record<string, string | null>,
    deuda: [{ clave: "radio:boton", hoy: null }] as LineaDeuda[],
    diaUno: new Set(["radio:boton"]),
    tope: 1,
  });
  const tipos = (a: Parameters<typeof compararMarca>[0]) => compararMarca(a).map((p) => p.tipo);

  it("un caso sano no da problemas", () => {
    expect(tipos(base())).toEqual([]);
  });

  it("un valor ya cumplido que vuelve a divergir, falla", () => {
    const a = base();
    a.medido["claro:rojo"] = "#b8412e";
    expect(tipos(a)).toEqual(["diverge"]);
  });

  it("una deuda pagada que no se borra, falla: la lista tiene que bajar", () => {
    const a = base();
    a.medido["radio:boton"] = "999";
    expect(tipos(a)).toEqual(["ya-pagada"]);
  });

  it("borrar la deuda sin bajar el tope, falla", () => {
    const a = base();
    a.medido["radio:boton"] = "999";
    a.deuda = [];
    expect(tipos(a)).toEqual(["tope"]);
  });

  it("una deuda nueva, falla aunque se suba el tope", () => {
    const a = base();
    a.medido["claro:rojo"] = "#000000";
    a.deuda.push({ clave: "claro:rojo", hoy: "#000000" });
    a.tope = 2;
    expect(tipos(a)).toEqual(["deuda-nueva"]);
  });

  it("una deuda de algo que se movió a otro valor equivocado, falla", () => {
    const a = base();
    a.medido["radio:boton"] = "12";
    expect(tipos(a)).toEqual(["deuda-movida"]);
  });

  it("una deuda de algo que el contrato no pide, falla", () => {
    const a = base();
    a.deuda.push({ clave: "radio:inventado", hoy: null });
    a.diaUno.add("radio:inventado");
    a.tope = 2;
    expect(tipos(a)).toEqual(["huerfana"]);
  });

  it("el lector lee un alias, un rem y un token que no existe", () => {
    const css = '@theme { --color-a: #AABBCC; --color-b: var(--color-a); --radius-x: 0.5rem; --radius-y: 999px; } :root[data-tema="oscuro"] { --color-a: #000001; }';
    const c = {
      marca: {
        colores_claro: { b: "#aabbcc", falta: "#000000" },
        colores_oscuro: { b: "#000001" },
        radios: [{ funcion: "x", px: 8, retail: null, dynamic: "radius-x" }, { funcion: "y", px: 999, retail: null, dynamic: "radius-y" }, { funcion: "z", px: 1, retail: null, dynamic: "radius-z" }],
      },
    } as unknown as Contrato;
    expect(medirMarca(css, c)).toEqual({ "claro:b": "#aabbcc", "claro:falta": null, "oscuro:b": "#000001", "radio:x": "8", "radio:y": "999", "radio:z": null });
  });
});

// S4 y P2 del contrato, medidos sobre los valores del contrato: si Retail baja un contraste de marca, la toma se pone en rojo aquí y no se publica.
// Esto NO mide un texto sobre el vidrio (eso depende de lo que haya detrás y solo se mide en un navegador).
describe("el contraste de la paleta del contrato", () => {
  function luminancia(hex: string): number {
    const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255).map((c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }
  function contraste(a: string, b: string): number {
    const [x, y] = [luminancia(a), luminancia(b)].sort((p, q) => q - p);
    return (x + 0.05) / (y + 0.05);
  }

  for (const [tema, c] of [["claro", contrato.marca.colores_claro], ["oscuro", contrato.marca.colores_oscuro]] as const) {
    for (const fondo of ["crema", "papel", "hueso"]) {
      for (const texto of ["tinta", "taupe", "rojo-profundo", "verde", "ambar", "pizarra"]) {
        it(`${tema}: ${texto} sobre ${fondo} ≥ 4.5:1`, () => {
          expect(contraste(c[texto], c[fondo])).toBeGreaterThanOrEqual(4.5);
        });
      }
      it(`${tema}: borde-control sobre ${fondo} ≥ 3:1`, () => {
        expect(contraste(c["borde-control"], c[fondo])).toBeGreaterThanOrEqual(3);
      });
    }
    for (const fondo of ["crema", "papel"]) {
      it(`${tema}: rojo sobre ${fondo} ≥ 4.5:1`, () => {
        expect(contraste(c.rojo, c[fondo])).toBeGreaterThanOrEqual(4.5);
      });
    }
  }
});

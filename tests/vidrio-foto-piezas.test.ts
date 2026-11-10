import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import ts from "typescript";
import { createElement as h, type ReactElement, type ReactNode } from "../apps/web/node_modules/react";
import { renderToStaticMarkup } from "../apps/web/node_modules/react-dom/server.node.js";
import { AyudaPantalla, BotonAyuda } from "@/components/ui/ayuda-pantalla";
import { AreaTexto } from "@/components/ui/area-texto";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Boton } from "@/components/ui/boton";
import { BotonIcono } from "@/components/ui/boton-icono";
import { BuscadorPersona } from "@/components/ui/buscador-persona";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { Campo, CampoCasilla, CampoSelect } from "@/components/ui/campo";
import { CampoClave } from "@/components/ui/campo-clave";
import { Cifra } from "@/components/ui/cifra";
import { Drawer } from "@/components/ui/drawer";
import { EstadoVacio } from "@/components/ui/estado-vacio";
import { Filtro } from "@/components/ui/filtro";
import { HojaInferior } from "@/components/ui/hoja-inferior";
import { ImprimibleAparte } from "@/components/ui/imprimible-aparte";
import { Insignia } from "@/components/ui/insignia";
import { ItemObjetivo } from "@/components/ui/item-objetivo";
import { Menu, MenuItem } from "@/components/ui/menu";
import { Modal } from "@/components/ui/modal";
import { ListaPaginada, Paginas } from "@/components/ui/paginas";
import { ParaAtender } from "@/components/ui/para-atender";
import { Pestanas } from "@/components/ui/pestanas";
import { Punto } from "@/components/ui/punto";
import { Rotulo, RotuloEstado } from "@/components/ui/rotulo";
import { Fila, Tabla, TablaEncabezado, Th } from "@/components/ui/tabla";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";

// APAGADO, LAS PIEZAS SE VEN COMO HOY. Una foto de las clases de apps/web/components/ui, en dos partes:
//
//   tests/fotos/vidrio-piezas-render.txt  cada pieza con sus variantes, renderizada: lo que de verdad sale al HTML.
//   tests/fotos/vidrio-piezas-fuente.txt  las clases escritas en cada archivo, por lo que un render en el servidor no
//                                         alcanza: el menú abierto, la lista del buscador, un cajón saliendo.
//
// SI ESTO SE PUSO ROJO, hay dos caminos, y el segundo solo es válido si lo quieres cambiar TAMBIÉN para producción hoy:
//   1. El cambio es del vidrio: cuélgalo del atributo. O con una regla en app/estilos/vidrio/, que no toca las clases, o
//      con una clase que no hace nada apagado (`vidrio:…`, `[[data-vidrio]_&]:…`, un gancho `vidrio-…`): esas no cuentan.
//   2. Es un arreglo de verdad, para todo el mundo y apagado también. Se actualiza la foto y se revisa el diff:
//        npx vitest run tests/vidrio-foto-piezas.test.ts -u
//
// Lo que esto NO ve: clases escritas en una pantalla y no en una pieza, y lo que se agregue a globals.css.

/** Una clase que apagada no hace nada, porque solo existe colgada del atributo. `bg-vidrio` a secas NO cuenta. */
function cuelgaDelVidrio(clase: string): boolean {
  return /(^|:)vidrio[:-]|data-vidrio/.test(clase);
}

/** Los íconos traen sus propias clases (`lucide lucide-eye`); cambian con la librería, y no son decisión de nadie aquí. */
function esDeLaLibreriaDeIconos(clase: string): boolean {
  return /^lucide(-|$)/.test(clase);
}

function normalizarClases(clases: string): string[] {
  return clases
    .split(/\s+/)
    .filter((c) => c && !cuelgaDelVidrio(c) && !esDeLaLibreriaDeIconos(c))
    .sort();
}

const SIN_CIERRE = new Set(["input", "img", "br", "hr", "meta", "link", "source", "wbr"]);

/**
 * El HTML reducido a lo que decide cómo se ve: la forma del árbol, las clases ordenadas y el estilo en línea. Sin textos
 * ni ids (`useId` cambia) ni el trazo de los íconos. El orden no se fotografía: en CSS no decide nada y `cx` ya resolvió.
 */
function fotoDeHtml(html: string): string[] {
  const lineas: string[] = [];
  let profundidad = 0;
  let dentroDeSvg = 0;
  const etiqueta = /<(\/?)([a-zA-Z][\w-]*)((?:\s+[^\s=>/]+(?:="[^"]*")?)*)\s*(\/?)>/g;
  for (const m of html.matchAll(etiqueta)) {
    const [, cierra, nombre, atributos, autocierre] = m;
    if (cierra) {
      if (nombre === "svg") dentroDeSvg--;
      if (!dentroDeSvg) profundidad--;
      continue;
    }
    if (dentroDeSvg) {
      if (!autocierre && !SIN_CIERRE.has(nombre)) dentroDeSvg += nombre === "svg" ? 1 : 0;
      continue;
    }
    const clase = /\sclass="([^"]*)"/.exec(atributos)?.[1] ?? "";
    const estilo = /\sstyle="([^"]*)"/.exec(atributos)?.[1];
    const tokens = normalizarClases(clase);
    lineas.push(`${"  ".repeat(profundidad)}${nombre}${tokens.length ? ` ${tokens.join(" ")}` : ""}${estilo ? ` {${estilo}}` : ""}`);
    if (nombre === "svg") dentroDeSvg = 1;
    if (!autocierre && !SIN_CIERRE.has(nombre)) profundidad++;
  }
  return lineas;
}

// ── El catálogo: cada pieza con cada variante que su firma ofrece ───────────────────────────────────────────────────

const nada = () => {};
const foco = { current: null };
const X = "x";

const CASOS: { nombre: string; elemento: ReactElement }[] = [];
const PIEZAS_EN_CATALOGO = new Set<unknown>();

function caso(nombre: string, elemento: ReactElement) {
  CASOS.push({ nombre, elemento });
  PIEZAS_EN_CATALOGO.add(elemento.type);
}

function combinar<T extends Record<string, readonly unknown[]>>(opciones: T): { [K in keyof T]: T[K][number] }[] {
  return Object.entries(opciones).reduce<Record<string, unknown>[]>(
    (acumulado, [clave, valores]) => acumulado.flatMap((a) => valores.map((v) => ({ ...a, [clave]: v }))),
    [{}],
  ) as { [K in keyof T]: T[K][number] }[];
}

const etiquetar = (props: Record<string, unknown>) =>
  Object.entries(props)
    .map(([k, v]) => `${k}=${typeof v === "string" ? v : JSON.stringify(v)}`)
    .join(" ");

function variantes(nombre: string, Pieza: any, opciones: Record<string, readonly unknown[]>, fijas: Record<string, unknown> = {}, hijos: ReactNode = X) {
  for (const props of combinar(opciones)) {
    caso(`${nombre} ${etiquetar(props)}`.trim(), h(Pieza, { ...fijas, ...props }, hijos));
  }
}

const BOOLEANO = [false, true] as const;
const TONOS_PUNTO = ["alerta", "advertencia", "positivo", "informativo"] as const;
const ICONO = h("svg", { className: "size-4 lucide lucide-info" }, h("path", { d: "M0 0" }));

variantes("Boton", Boton, { variante: ["primario", "secundario", "peligro", "sutil", "enlace"], tamano: ["sm", "md", "lg"] });
variantes("Boton", Boton, { cargando: [true] });
variantes("Boton", Boton, { disabled: [true] });
variantes("BotonIcono", BotonIcono, { tamano: ["sm", "md", "lg"], activo: [undefined, false, true], contador: [undefined, 3] }, { etiqueta: X, icono: ICONO }, null);
variantes("BotonAyuda", BotonAyuda, {}, { etiqueta: X, onClick: nada }, null);
variantes("AyudaPantalla", AyudaPantalla, {}, { titulo: X, intro: X, secciones: [{ titulo: X, texto: X, referencia: X }] });

variantes("Campo", Campo, { tamano: ["md", "sm"], etiqueta: [undefined, X], error: [undefined, X] }, {}, null);
variantes("CampoCasilla", CampoCasilla, { etiqueta: [undefined, X], error: [undefined, X] }, {}, null);
variantes("CampoSelect", CampoSelect, { tamano: ["md", "sm"], etiqueta: [undefined, X], error: [undefined, X] }, {}, h("option", null, X));
variantes("CampoClave", CampoClave, { etiqueta: [undefined, X], error: [undefined, X] }, {}, null);
variantes("AreaTexto", AreaTexto, { etiqueta: [undefined, X], error: [undefined, X] }, { value: X, onChange: nada }, null);

const PERSONAS = [
  { id: "1", nombre: "Ana", sede: "TRU", detalle: X },
  { id: "2", nombre: "Bea", sede: "LIM" },
];
variantes("BuscadorPersona", BuscadorPersona, { value: ["", "1"], error: [undefined, X], disabled: BOOLEANO }, { opciones: PERSONAS, onChange: nada }, null);

variantes("TarjetaInfo", TarjetaInfo, { titulo: [undefined, X], accion: [undefined, X] });
variantes("TarjetaInfo", TarjetaInfo, { como: ["section", "li", "article", "aside", "header"] });
variantes("EstadoVacio", EstadoVacio, { accion: [undefined, X] });
variantes("BannerAviso", BannerAviso, { variante: ["neutral", "alerta", "advertencia", "positivo", "informativo"], enLinea: BOOLEANO, titulo: [undefined, X] });
variantes("CabeceraPagina", CabeceraPagina, { sobretitulo: [undefined, X], descripcion: [undefined, X], ayuda: [undefined, X], accion: [undefined, X] }, { titulo: X }, null);
variantes("Cifra", Cifra, { tamano: ["md", "sm"], activa: BOOLEANO, tono: [undefined, ...TONOS_PUNTO], detalle: [undefined, X] }, { etiqueta: X, valor: X }, null);
variantes("Cifra", Cifra, { tamano: ["md", "sm"], activa: BOOLEANO }, { etiqueta: X, valor: X, onClick: nada }, null);
variantes("Cifra", Cifra, { activa: BOOLEANO }, { etiqueta: X, valor: X, onClick: nada, controla: "region" }, null);
variantes("Cifra", Cifra, { tamano: ["md", "sm"] }, { etiqueta: X, valor: X, href: "/x" }, null);

variantes("Tabla", Tabla, { alturaMaxima: [undefined, "70vh"] });
variantes("TablaEncabezado", TablaEncabezado, {});
variantes("Th", Th, {});
variantes("Fila", Fila, {});

variantes("Insignia", Insignia, { variante: ["neutral", "alerta", "advertencia", "positivo", "informativo", "contador"], tamano: ["md", "sm"] });
variantes("Insignia", Insignia, { atenuada: [true] });
variantes("Insignia", Insignia, { punto: BOOLEANO, variante: ["neutral", "contador"] });
variantes("Punto", Punto, { tono: TONOS_PUNTO }, {}, null);
variantes("Rotulo", Rotulo, { como: ["p", "div", "span", "h3"] });
variantes("RotuloEstado", RotuloEstado, { tono: [undefined, ...TONOS_PUNTO] });
variantes("ItemObjetivo", ItemObjetivo, { cumplido: BOOLEANO, indicaciones: [undefined, X] }, { descripcion: X }, null);

variantes("Filtro", Filtro, { activo: BOOLEANO, tamano: ["md", "sm"] });
const ITEMS_ATENDER = (["pizarra", "rojo", "ambar", "neutro"] as const).map((tono) => ({ clave: tono, texto: X, n: 1, tono }));
variantes("ParaAtender", ParaAtender, { compacta: BOOLEANO, activa: [null, "rojo"], extra: [undefined, X] }, { items: ITEMS_ATENDER, alTocar: nada }, null);
variantes("ParaAtender vacía", ParaAtender, { compacta: BOOLEANO }, { items: [], activa: null, alTocar: nada }, null);
variantes("Pestanas", Pestanas, { enBarra: BOOLEANO }, { etiqueta: X, activa: "a", alElegir: nada, pestanas: [{ clave: "a", texto: X, aviso: 2 }, { clave: "b", texto: X }] }, null);
// Una sola página no dibuja la fila; en la primera, «Anterior» va apagado; en la del medio, los dos encendidos.
variantes("Paginas", Paginas, { pag: [
  { pagina: 0, paginas: 1, desde: 1, hasta: 3, total: 3 },
  { pagina: 0, paginas: 3, desde: 1, hasta: 5, total: 12 },
  { pagina: 1, paginas: 3, desde: 6, hasta: 10, total: 12 },
] }, { etiqueta: X, alCambiar: nada }, null);
// Sus hijos son una función: va como tercer argumento de `h`, que es por donde llegan los hijos.
const dibujarLista = ((n: number[]) => h("ul", null, n.map((i) => h("li", { key: i }, i)))) as unknown as ReactNode;
variantes("ListaPaginada", ListaPaginada, { items: [[1, 2, 3], [1, 2, 3, 4, 5, 6, 7]] }, { etiqueta: X }, dibujarLista);

variantes("Modal", Modal, { ancho: ["sm", "md", "lg", "xl"], titulo: [undefined, X] }, { abierto: true, onCerrar: nada });
variantes("Modal cerrado", Modal, {}, { abierto: false, onCerrar: nada });
variantes("Drawer", Drawer, { ancho: ["normal", "amplio", "extra"], titulo: [undefined, X] }, { abierto: true, onCerrar: nada, volverElFocoA: foco });
variantes("HojaInferior", HojaInferior, {}, { abierto: true, onCerrar: nada, titulo: X, accion: X, volverElFocoA: foco });

variantes("Menu", Menu, { alinear: ["derecha", "izquierda"] }, { trigger: () => h("button", null, X) });
variantes("MenuItem", MenuItem, { variante: ["normal", "peligro"], disabled: BOOLEANO });
variantes("MenuItem", MenuItem, { variante: ["normal", "peligro"] }, { href: "/x" });
// Sin navegador no dibuja nada, y es lo correcto: su clase la cuida la foto de las fuentes.
variantes("ImprimibleAparte", ImprimibleAparte, {});

const ENCABEZADO_RENDER = [
  "# Foto de las piezas de components/ui, apagado. Se genera: npx vitest run tests/vidrio-foto-piezas.test.ts -u",
  "# Si la prueba falló: lee el comentario de arriba de esa prueba antes de actualizarla.",
  "",
];

function fotoRender(): string {
  const bloques = CASOS.map(({ nombre, elemento }) => {
    const lineas = fotoDeHtml(renderToStaticMarkup(elemento));
    return [`## ${nombre}`, ...(lineas.length ? lineas : ["(no dibuja nada)"])].join("\n");
  });
  return `${[...ENCABEZADO_RENDER, ...bloques].join("\n")}\n`;
}

// ── La foto de las fuentes: las clases que un render en el servidor no alcanza ──────────────────────────────────────

const CARPETA_UI = path.resolve(import.meta.dirname, "../apps/web/components/ui");

/** Las cadenas de texto de un nodo y todo lo que lleva adentro, también las partes fijas de una plantilla. */
function textosDe(nodo: ts.Node, salida: string[]): void {
  if (ts.isStringLiteralLike(nodo) || ts.isTemplateHead(nodo) || ts.isTemplateMiddle(nodo) || ts.isTemplateTail(nodo)) {
    salida.push(nodo.text);
  }
  ts.forEachChild(nodo, (hijo) => textosDe(hijo, salida));
}

/** Lo que puede ser una clase: un `className`, los argumentos de `cx()` y las constantes de arriba del archivo (TONOS, ANCHO…). */
function clasesDeFuente(codigo: string): string[] {
  const archivo = ts.createSourceFile("pieza.tsx", codigo, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
  const textos: string[] = [];
  const visitar = (nodo: ts.Node) => {
    if (ts.isJsxAttribute(nodo) && nodo.name.getText() === "className") {
      textosDe(nodo, textos);
    } else if (ts.isCallExpression(nodo) && nodo.expression.getText() === "cx") {
      textosDe(nodo, textos);
    } else {
      ts.forEachChild(nodo, visitar);
    }
  };
  for (const sentencia of archivo.statements) {
    if (ts.isVariableStatement(sentencia)) {
      textosDe(sentencia, textos);
    } else {
      visitar(sentencia);
    }
  }
  return [...new Set(textos.flatMap((t) => normalizarClases(t)))].sort();
}

function fotoFuente(): string {
  const archivos = readdirSync(CARPETA_UI)
    .filter((f) => f.endsWith(".tsx"))
    .sort();
  const bloques = archivos.map((f) => [`## ${f}`, ...clasesDeFuente(readFileSync(path.join(CARPETA_UI, f), "utf8"))].join("\n"));
  return `${["# Las clases escritas en cada pieza, apagado. Se genera: npx vitest run tests/vidrio-foto-piezas.test.ts -u", "", ...bloques].join("\n")}\n`;
}

// ── Las pruebas ──────────────────────────────────────────────────────────────────────────────────────────────────

describe("apagado, las piezas se ven como hoy", () => {
  // Apagadas de verdad: si una pieza llegara a preguntar por el interruptor, la foto tiene que ser la de producción.
  beforeAll(() => {
    vi.stubEnv("NEXT_PUBLIC_VIDRIO", undefined as unknown as string);
    vi.stubEnv("NEXT_PUBLIC_VIDRIO_TERMINAL", undefined as unknown as string);
  });
  afterAll(() => vi.unstubAllEnvs());

  it("cada pieza sale con las mismas clases (si falla: cuélgala de vidrio, o lee el comentario de este archivo)", async () => {
    await expect(fotoRender()).toMatchFileSnapshot("./fotos/vidrio-piezas-render.txt");
  });

  it("cada archivo de piezas tiene las mismas clases, también las de estados que solo existen en el navegador", async () => {
    await expect(fotoFuente()).toMatchFileSnapshot("./fotos/vidrio-piezas-fuente.txt");
  });

  it("ninguna pieza exportada se queda fuera del catálogo", () => {
    const modulos = import.meta.glob("../apps/web/components/ui/*.tsx", { eager: true }) as Record<string, Record<string, unknown>>;
    const faltan = Object.entries(modulos).flatMap(([ruta, exportaciones]) =>
      Object.entries(exportaciones)
        .filter(([nombre, valor]) => /^[A-Z]/.test(nombre) && typeof valor === "function" && !PIEZAS_EN_CATALOGO.has(valor))
        .map(([nombre]) => `${path.basename(ruta)}: ${nombre}`),
    );
    expect(faltan, "pieza nueva: agrégala al catálogo con sus variantes").toEqual([]);
    expect(Object.keys(modulos).length).toBeGreaterThan(20);
  });
});

describe("la foto mira lo que tiene que mirar", () => {
  it("las clases colgadas del atributo no cuentan: encendidas o quitadas, la foto no cambia", () => {
    const base = fotoDeHtml(`<button class="a b"></button>`);
    expect(fotoDeHtml(`<button class="vidrio:bg-white/40 a hover:vidrio:shadow-lg b vidrio-boton [[data-vidrio]_&]:p-4"></button>`)).toEqual(base);
  });

  it.each(["bg-vidrio", "text-vidrio/50", "hover:bg-vidrio", "p-5"])("una clase que aplica apagada sí cuenta: %s", (clase) => {
    expect(fotoDeHtml(`<button class="a ${clase}"></button>`)).not.toEqual(fotoDeHtml(`<button class="a"></button>`));
  });

  it("cambiar una clase, envolver en otro elemento o poner un estilo en línea cambia la foto", () => {
    const base = fotoDeHtml(`<div class="a"><span class="b"></span></div>`);
    expect(fotoDeHtml(`<div class="a"><span class="c"></span></div>`)).not.toEqual(base);
    expect(fotoDeHtml(`<div class="a"><div><span class="b"></span></div></div>`)).not.toEqual(base);
    expect(fotoDeHtml(`<div class="a" style="color:red"><span class="b"></span></div>`)).not.toEqual(base);
  });

  it("el orden de las clases, los textos y el trazo de un ícono no cambian la foto", () => {
    const base = fotoDeHtml(`<div class="a b"><svg class="c lucide lucide-eye"><path d="M0 0"></path></svg></div>`);
    expect(fotoDeHtml(`<div class="b a">texto<svg class="lucide lucide-eye-off c"><circle r="1"></circle><path d="M1 1"></path></svg></div>`)).toEqual(base);
  });

  it("después de un ícono se sigue contando la profundidad bien", () => {
    expect(fotoDeHtml(`<div><svg class="a"><path></path></svg><span class="b"></span></div>`)).toEqual(["div", "  svg a", "  span b"]);
  });

  it("la foto de fuentes encuentra las clases de un estado que no se ve en el servidor, y no los comentarios", () => {
    const clases = clasesDeFuente(`
      // "comentario-ignorado"
      const TONOS = { a: "uno dos" };
      export function P({ abierto }) {
        return abierto ? <div className={cx("tres", abierto && "cuatro")} aria-label="Etiqueta visible" /> : <b className={\`cinco \${TONOS.a}\`} />;
      }`);
    expect(clases).toEqual(["cinco", "cuatro", "dos", "tres", "uno"].sort());
  });

  it("dos vueltas seguidas dan la misma foto", () => {
    expect(fotoRender()).toBe(fotoRender());
  });
});

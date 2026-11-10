import { resolverPlegado } from "../apps/web/lib/vidrio-lateral";
import { afterEach, describe, expect, it, vi } from "vitest";
import { readdirSync } from "node:fs";
import path from "node:path";
import { createElement, type ReactElement } from "../apps/web/node_modules/react";
import { renderToStaticMarkup } from "../apps/web/node_modules/react-dom/server.node.js";
import {
  aplicarVidrio,
  guionVidrioAntesDePintar,
  interruptoresVidrio,
  superficieDeRuta,
  valorVidrio,
  type InterruptoresVidrio,
  quienSigueElTemaGlobal,
} from "@/lib/vidrio";
import RootLayout from "@/app/layout";

// El estreno del diseño nuevo es encender una variable. Estas pruebas fijan las dos promesas que hacen eso seguro:
// sin variable no existe ni el atributo ni nada que lo ponga, y panel y terminal se encienden por separado.
// Las direcciones se le preguntan a las carpetas de `app/`, no se escriben a mano: el día que aparezca una pantalla
// del terminal fuera de /terminal, esto falla antes de que se pinte con el aspecto del panel.

vi.mock("../apps/web/node_modules/next/font/google/index.js", () => ({
  EB_Garamond: () => ({ variable: "fuente-serif" }),
  DM_Sans: () => ({ variable: "fuente-sans" }),
}));

const APP = path.resolve(import.meta.dirname, "../apps/web/app");

/** Las direcciones reales de un grupo de rutas: sus `page.tsx`, sin los paréntesis y con un valor en cada [parámetro]. */
function rutasDe(grupo: string): string[] {
  const base = path.join(APP, grupo);
  return (readdirSync(base, { recursive: true }) as string[])
    .filter((f) => path.basename(f) === "page.tsx")
    .map((f) => {
      const partes = path.dirname(f).split(path.sep).filter((p) => p !== "." && !/^\(.*\)$/.test(p));
      return `/${partes.map((p) => p.replace(/^\[.*\]$/, "valor")).join("/")}`;
    });
}

const COMBINACIONES: InterruptoresVidrio[] = [
  { panel: false, terminal: false },
  { panel: true, terminal: false },
  { panel: false, terminal: true },
  { panel: true, terminal: true },
];

/** Corre el guion tal como lo haría el navegador y devuelve lo que dejó en <html>. */
/** Corre el guion contra un documento falso y devuelve el atributo y el tema que dejó. `guardado`: lo que hay en localStorage; `null` si no hay nada, y «error» si el almacenamiento está bloqueado. */
function correrGuionCompleto(guion: string, ruta: string, guardado: string | null = null, opciones: { lateral?: string | null; ventanaAncha?: boolean } = {}) {
  const atributos = new Map<string, string>();
  const meta = new Map<string, string>();
  const documento = {
    documentElement: { setAttribute: (nombre: string, v: string) => void atributos.set(nombre, v) },
    querySelector: () => ({ setAttribute: (nombre: string, v: string) => void meta.set(nombre, v) }),
  };
  const almacenamiento = {
    getItem: (clave: string) => {
      if (guardado === "error") throw new Error("bloqueado");
      return clave === "cayla-nav-colapsado" ? (opciones.lateral ?? null) : guardado;
    },
  };
  const ventana = () => ({ matches: opciones.ventanaAncha ?? true });
  new Function("document", "location", "localStorage", "matchMedia", guion)(documento, { pathname: ruta }, almacenamiento, ventana);
  return { vidrio: atributos.get("data-vidrio") ?? null, tema: atributos.get("data-tema") ?? null, barra: meta.get("content") ?? null };
}

function lateralDelGuion(guion: string, ruta: string, opciones: { lateral?: string | null; ventanaAncha?: boolean }) {
  const atributos = new Map<string, string>();
  const documento = {
    documentElement: { setAttribute: (nombre: string, v: string) => void atributos.set(nombre, v) },
    querySelector: () => null,
  };
  const almacenamiento = { getItem: (clave: string) => (clave === "cayla-nav-colapsado" ? (opciones.lateral ?? null) : null) };
  new Function("document", "location", "localStorage", "matchMedia", guion)(documento, { pathname: ruta }, almacenamiento, () => ({ matches: opciones.ventanaAncha ?? true }));
  return atributos.get("data-lateral") ?? null;
}

function correrGuion(guion: string, ruta: string) {
  return correrGuionCompleto(guion, ruta).vidrio;
}

afterEach(() => vi.unstubAllEnvs());

describe("sin variable, sin atributo", () => {
  function apagar() {
    vi.stubEnv("NEXT_PUBLIC_VIDRIO", undefined as unknown as string);
    vi.stubEnv("NEXT_PUBLIC_VIDRIO_TERMINAL", undefined as unknown as string);
  }

  it("sin las variables, los dos interruptores están apagados", () => {
    apagar();
    expect(interruptoresVidrio()).toEqual({ panel: false, terminal: false });
    expect(valorVidrio("/admin/dashboard")).toBeNull();
    expect(valorVidrio("/mio")).toBeNull();
    expect(valorVidrio("/terminal/marcar")).toBeNull();
  });

  it.each(["0", "true", "on", "", " 1", "1 ", "01"])("solo un 1 exacto enciende: %j no", (valor) => {
    vi.stubEnv("NEXT_PUBLIC_VIDRIO", valor);
    vi.stubEnv("NEXT_PUBLIC_VIDRIO_TERMINAL", valor);
    expect(interruptoresVidrio()).toEqual({ panel: false, terminal: false });
  });

  it("apagado no hay guion que poner en la página", () => {
    apagar();
    expect(guionVidrioAntesDePintar()).toBeNull();
  });

  it("apagado, el layout raíz no lleva ni el atributo ni el guion", () => {
    apagar();
    const html = renderToStaticMarkup(createElement(RootLayout, null, "contenido"));
    expect(html).not.toContain("data-vidrio");
    expect(html).not.toContain("document.documentElement.setAttribute(\"data-vidrio");
    // Los dos guiones de siempre (el tema y el toque en Safari), y ninguno más.
    expect(html.match(/<script/g)).toHaveLength(2);
  });

  it("apagado, el árbol de <body> es el de siempre: un hueco cambiaría el HTML de todas las páginas", () => {
    apagar();
    // Un `{x && <y />}` apagado no dibuja nada, pero deja un null entre los hijos: ese null viaja en el payload de cada
    // página y corre los ids de `useId` de todo lo que viene después. Lo cazó comparar dos `next build` el 2026-11-05.
    const html = RootLayout({ children: "contenido" }) as ReactElement<{ children: ReactElement<{ children: ReactElement<{ children: unknown }>[] }> }>;
    const hijos = html.props.children.props.children;
    expect(hijos.filter((h) => !h)).toEqual([]);
    expect(hijos[hijos.length - 1].props.children).toBe("contenido");
  });

  it("encendido, el layout raíz lleva el guion antes del contenido, y aun así no escribe el atributo en el HTML", () => {
    vi.stubEnv("NEXT_PUBLIC_VIDRIO", "1");
    vi.stubEnv("NEXT_PUBLIC_VIDRIO_TERMINAL", "1");
    const html = renderToStaticMarkup(createElement(RootLayout, null, "contenido"));
    expect(html.match(/<script/g)).toHaveLength(3);
    expect(html.indexOf("setAttribute(\"data-vidrio")).toBeLessThan(html.indexOf("contenido"));
    // Si saliera en el <html> servido, una página estática lo llevaría también en la superficie apagada.
    expect(html.slice(0, html.indexOf("<body"))).not.toContain("data-vidrio");
  });
});

describe("panel y terminal se encienden por separado", () => {
  it("cada variable enciende solo su superficie", () => {
    vi.stubEnv("NEXT_PUBLIC_VIDRIO", "1");
    vi.stubEnv("NEXT_PUBLIC_VIDRIO_TERMINAL", undefined as unknown as string);
    expect(interruptoresVidrio()).toEqual({ panel: true, terminal: false });
    expect(valorVidrio("/admin/dashboard")).toBe("panel");
    expect(valorVidrio("/terminal/marcar")).toBeNull();

    vi.stubEnv("NEXT_PUBLIC_VIDRIO", undefined as unknown as string);
    vi.stubEnv("NEXT_PUBLIC_VIDRIO_TERMINAL", "1");
    expect(interruptoresVidrio()).toEqual({ panel: false, terminal: true });
    expect(valorVidrio("/admin/dashboard")).toBeNull();
    expect(valorVidrio("/terminal/marcar")).toBe("terminal");
  });

  it("las rutas de (terminal) son terminal; las de (admin) y (mio), panel", () => {
    const terminal = rutasDe("(terminal)");
    const panel = [...rutasDe("(admin)"), ...rutasDe("(mio)")];
    // Si la búsqueda de carpetas se rompe y devuelve poco, esto no puede pasar en verde por no haber mirado nada.
    expect(terminal).toEqual(expect.arrayContaining(["/terminal", "/terminal/marcar", "/terminal/vincular"]));
    expect(panel).toEqual(expect.arrayContaining(["/admin/dashboard", "/admin/login", "/mio", "/mio/bandeja"]));
    expect(panel.length).toBeGreaterThan(40);

    expect(terminal.filter((r) => superficieDeRuta(r) !== "terminal")).toEqual([]);
    expect(panel.filter((r) => superficieDeRuta(r) !== "panel")).toEqual([]);
  });

  it("una dirección que solo se parece a /terminal no es del terminal", () => {
    expect(superficieDeRuta("/terminales")).toBe("panel");
    expect(superficieDeRuta("/")).toBe("panel");
    expect(superficieDeRuta("/terminal/no-existe")).toBe("terminal");
  });
});

describe("el guion contesta igual que la función", () => {
  const rutas = [
    ...rutasDe("(terminal)"),
    ...rutasDe("(admin)"),
    ...rutasDe("(mio)"),
    "/",
    "/terminales",
    "/terminal/no-existe",
    "/admin/no-existe",
  ];

  it.each(COMBINACIONES)("con %j, en todas las rutas reales", (interruptores) => {
    const guion = guionVidrioAntesDePintar(interruptores);
    if (!guion) {
      expect(interruptores).toEqual({ panel: false, terminal: false });
      return;
    }
    for (const ruta of rutas) {
      expect([ruta, correrGuion(guion, ruta)]).toEqual([ruta, valorVidrio(ruta, interruptores)]);
    }
  });
});

describe("el tema con el vidrio encendido", () => {
  const encendido = guionVidrioAntesDePintar({ panel: true, terminal: true })!;

  it("arranca en claro: nadie se encuentra el sistema distinto, aunque su aparato esté en oscuro", () => {
    expect(correrGuionCompleto(encendido, "/admin/dashboard").tema).toBe("claro");
    expect(correrGuionCompleto(encendido, "/mio").tema).toBe("claro");
  });

  it("lo elegido con el botón se recuerda, y la barra del teléfono lo sigue", () => {
    expect(correrGuionCompleto(encendido, "/admin/dashboard", "oscuro")).toEqual({ vidrio: "panel", tema: "oscuro", barra: "#1c1a17" });
    expect(correrGuionCompleto(encendido, "/admin/dashboard", "claro")).toEqual({ vidrio: "panel", tema: "claro", barra: "#f5f0e8" });
  });

  it("lo viejo o lo roto es claro, y el almacenamiento bloqueado no rompe la página", () => {
    expect(correrGuionCompleto(encendido, "/admin/dashboard", "sistema").tema).toBe("claro");
    expect(correrGuionCompleto(encendido, "/admin/dashboard", "morado").tema).toBe("claro");
    expect(correrGuionCompleto(encendido, "/admin/dashboard", "error").tema).toBe("claro");
  });

  it("el terminal, desde su módulo, sigue la misma regla: arranca en claro y recuerda lo que eligió el botón de esa Mac", () => {
    expect(correrGuionCompleto(encendido, "/terminal/marcar").tema).toBe("claro");
    expect(correrGuionCompleto(encendido, "/terminal/marcar", "oscuro")).toEqual({ vidrio: "terminal", tema: "oscuro", barra: "#1c1a17" });
    expect(correrGuionCompleto(encendido, "/terminal/marcar", "sistema").tema).toBe("claro");
    expect(correrGuionCompleto(encendido, "/terminal/marcar", "error").tema).toBe("claro");
  });

  it("con el interruptor del terminal apagado, su tema lo sigue decidiendo /admin/apariencia: el guion no lo toca", () => {
    const soloPanel = guionVidrioAntesDePintar({ panel: true, terminal: false })!;
    expect(correrGuionCompleto(soloPanel, "/terminal/marcar", "oscuro")).toEqual({ vidrio: null, tema: null, barra: null });
  });

  it("con el panel apagado, el guion no toca el tema del panel", () => {
    const soloTerminal = guionVidrioAntesDePintar({ panel: false, terminal: true })!;
    expect(correrGuionCompleto(soloTerminal, "/admin/dashboard", "oscuro")).toEqual({ vidrio: null, tema: null, barra: null });
    expect(correrGuionCompleto(soloTerminal, "/terminal/marcar", "oscuro").tema).toBe("oscuro");
  });
});

describe("el menú plegado, antes de pintar", () => {
  const encendido = guionVidrioAntesDePintar({ panel: true, terminal: false })!;
  it.each([
    [null, true],
    [null, false],
    ["rail", true],
    ["rail", false],
    ["ancho", true],
    ["ancho", false],
    ["cualquiera", false],
  ] as const)("el guion contesta igual que resolverPlegado: guardado %j, ventana ancha %j", (lateral, ventanaAncha) => {
    expect(lateralDelGuion(encendido, "/admin/dashboard", { lateral, ventanaAncha })).toBe(resolverPlegado(lateral, ventanaAncha) ? "plegado" : null);
  });
  it("el terminal no lleva menú: nunca se le pone el atributo", () => {
    const ambos = guionVidrioAntesDePintar({ panel: true, terminal: true })!;
    expect(lateralDelGuion(ambos, "/terminal/marcar", { lateral: "rail" })).toBeNull();
  });
  it("sin matchMedia o sin almacenamiento no se rompe la página", () => {
    const documento = { documentElement: { setAttribute: () => {} }, querySelector: () => null };
    expect(() => new Function("document", "location", "localStorage", encendido)(documento, { pathname: "/admin/dashboard" }, { getItem: () => { throw new Error("bloqueado"); } })).not.toThrow();
  });
});

describe("al navegar sin recargar", () => {
  function htmlDePrueba() {
    const atributos = new Map<string, string>();
    return {
      atributos,
      setAttribute: (n: string, v: string) => void atributos.set(n, v),
      removeAttribute: (n: string) => void atributos.delete(n),
    };
  }

  it("al cruzar a una superficie apagada, el atributo desaparece; no queda vacío ni con el valor anterior", () => {
    const html = htmlDePrueba();
    const soloPanel = { panel: true, terminal: false };
    aplicarVidrio(html, valorVidrio("/", soloPanel));
    expect(html.atributos.get("data-vidrio")).toBe("panel");
    aplicarVidrio(html, valorVidrio("/terminal/marcar", soloPanel));
    expect(html.atributos.has("data-vidrio")).toBe(false);
    aplicarVidrio(html, valorVidrio("/admin/dashboard", soloPanel));
    expect(html.atributos.get("data-vidrio")).toBe("panel");
  });

  it("con las dos encendidas, cambia de valor en vez de quedarse con el de la superficie anterior", () => {
    const html = htmlDePrueba();
    const ambas = { panel: true, terminal: true };
    aplicarVidrio(html, valorVidrio("/", ambas));
    aplicarVidrio(html, valorVidrio("/terminal", ambas));
    expect(html.atributos.get("data-vidrio")).toBe("terminal");
  });
});

describe("¿/admin/apariencia cambia algo?", () => {
  // La sigue solo la superficie con el vidrio APAGADO: con el vidrio, cada aparato elige con su botón. De esto depende que la pantalla
  // esté en el menú (nav.tsx, `requiere: "tema-global"`) y lo que dice al guardar.
  it.each([
    [{ panel: false, terminal: false }, { panel: true, terminal: true }],
    [{ panel: true, terminal: false }, { panel: false, terminal: true }],
    [{ panel: false, terminal: true }, { panel: true, terminal: false }],
    [{ panel: true, terminal: true }, { panel: false, terminal: false }],
  ])("interruptores %j → la siguen %j", (interruptores, sigue) => {
    expect(quienSigueElTemaGlobal(interruptores)).toEqual(sigue);
  });
});

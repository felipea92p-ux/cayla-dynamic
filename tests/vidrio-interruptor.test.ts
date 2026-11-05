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
function correrGuion(guion: string, ruta: string): string | null {
  let valor: string | null = null;
  const documento = {
    documentElement: {
      setAttribute: (nombre: string, v: string) => {
        if (nombre === "data-vidrio") valor = v;
      },
    },
  };
  new Function("location", "document", guion)({ pathname: ruta }, documento);
  return valor;
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

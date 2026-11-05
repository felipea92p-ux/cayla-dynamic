// El marco con vidrio: qué fila lleva la marca, cuándo va plegado, cuándo se cierra el cajón con el dedo, y si la letra se lee sobre el vidrio.
// `tema:auditar` lee la página real, pero solo suma colores planos: lo que vive sobre un degradado o un vidrio se mide aquí.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import type { LucideIcon } from "lucide-react";
import { GRUPOS } from "../apps/web/app/(admin)/admin/nav-items";
import { GRUPOS_MIO } from "../apps/web/lib/mio-secciones";
import { cierraElCajon, decidirLado, posicionDelCajon } from "../apps/web/lib/use-cerrar-con-el-dedo";
import { armarFilas, claveDeLaActiva, esModulo, moduloDeLaHoja, sumaDelModulo, tituloDelModulo, type HojaMenu, type ModuloMenu } from "../apps/web/lib/vidrio-menu";
import { resolverPlegado } from "../apps/web/lib/vidrio-lateral";
import { color, contraste, peorBorde, peorLetra, temasDe, UMBRAL } from "../apps/web/tema/contraste-calculado";

const Icono = (() => null) as unknown as LucideIcon;
const hoja = (id: string, n = 0): HojaMenu => ({ id, etiqueta: id, Icon: Icono, n });
const GRUPOS_DE_PRUEBA = [
  { hojas: [hoja("info"), hoja("bandeja", 5)] },
  { label: "Asistencia", hojas: [hoja("incidencias", 2), hoja("ausencias", 1), hoja("turnos")] },
  { label: "Pago", hojas: [hoja("planilla")] },
  { label: "Vacío", hojas: [] },
];
const FILAS = armarFilas(GRUPOS_DE_PRUEBA);

describe("las filas del menú", () => {
  it("lo que no tiene título queda suelto y arriba; cada grupo con título es un módulo; un grupo vacío no dibuja nada", () => {
    expect(FILAS.map((f) => [f.id, esModulo(f)])).toEqual([["info", false], ["bandeja", false], ["Asistencia", true], ["Pago", true]]);
  });

  it("un módulo sin ícono propio usa el de su primera pantalla: nunca una fila sin dibujo", () => {
    const m = FILAS[2] as ModuloMenu;
    expect(m.Icon).toBe(Icono);
  });

  it("el número de un módulo es la suma de sus pantallas", () => {
    expect(sumaDelModulo(FILAS[2] as ModuloMenu)).toBe(3);
    expect(sumaDelModulo(FILAS[3] as ModuloMenu)).toBe(0);
  });

  it("el texto del número aclara lo que ya está contado en otra parte, y sin número no dice nada", () => {
    expect(tituloDelModulo(FILAS[2] as ModuloMenu, "Ya están contados en Bandeja")).toBe("3 por atender en Asistencia. Ya están contados en Bandeja");
    expect(tituloDelModulo(FILAS[3] as ModuloMenu, "Ya están contados en Bandeja")).toBeUndefined();
  });

  it("encuentra el módulo de una pantalla; una suelta o desconocida no tiene", () => {
    expect(moduloDeLaHoja(FILAS, "turnos")).toBe("Asistencia");
    expect(moduloDeLaHoja(FILAS, "bandeja")).toBeNull();
    expect(moduloDeLaHoja(FILAS, "no-existe")).toBeNull();
    expect(moduloDeLaHoja(FILAS, null)).toBeNull();
  });
});

describe("qué fila lleva la marca de «estás aquí»", () => {
  it("una suelta, ella misma", () => {
    expect(claveDeLaActiva(FILAS, "bandeja", null)).toBe("h:bandeja");
    expect(claveDeLaActiva(FILAS, "bandeja", "Pago")).toBe("h:bandeja");
  });
  it("con su módulo abierto, la pantalla", () => {
    expect(claveDeLaActiva(FILAS, "turnos", "Asistencia")).toBe("h:turnos");
  });
  it("con su módulo cerrado, o con otro abierto, sube a la fila del módulo: una marca escondida no le dice nada a nadie", () => {
    expect(claveDeLaActiva(FILAS, "turnos", null)).toBe("m:Asistencia");
    expect(claveDeLaActiva(FILAS, "turnos", "Pago")).toBe("m:Asistencia");
  });
  it("una pantalla que no está en este menú no marca nada", () => {
    expect(claveDeLaActiva(FILAS, "no-existe", null)).toBeNull();
    expect(claveDeLaActiva(FILAS, null, null)).toBeNull();
  });
});

describe("los menús de verdad", () => {
  const delPanel = armarFilas(GRUPOS.map((g) => ({ label: g.label, corto: g.corto, Icon: g.Icon, hojas: g.items.map((i) => ({ ...hoja(i.href), etiqueta: i.label })) })));
  const deLoMio = armarFilas(GRUPOS_MIO.map((g) => ({ label: g.label, corto: g.corto, Icon: g.Icon, hojas: g.secciones.map((s) => ({ ...hoja(s.valor), etiqueta: s.label })) })));

  it("el panel entero son 10 filas y Lo mío 5, lo que Felipe vio al decidir", () => {
    expect(delPanel).toHaveLength(10);
    expect(deLoMio).toHaveLength(5);
  });
  it("todo módulo trae su propio ícono", () => {
    expect(GRUPOS.filter((g) => g.label && !g.Icon).map((g) => g.label)).toEqual([]);
    expect(GRUPOS_MIO.filter((g) => g.label && !g.Icon).map((g) => g.label)).toEqual([]);
  });
  it("con el menú plegado, el nombre cabe bajo el ícono: 11 letras, medido a 10 px en 60 px de ancho", () => {
    for (const f of [...delPanel, ...deLoMio]) {
      const corto = f.corto ?? f.etiqueta;
      expect(corto.length, `«${corto}»`).toBeLessThanOrEqual(11);
    }
  });
  it("ninguna pantalla se pierde al pasar a módulos", () => {
    const hojas = delPanel.flatMap((f) => (esModulo(f) ? f.hojas.map((h) => h.id) : [f.id]));
    expect(hojas).toEqual(GRUPOS.flatMap((g) => g.items.map((i) => i.href)));
  });
});

describe("cuándo va plegado", () => {
  it("lo elegido a mano le gana a la ventana", () => {
    expect(resolverPlegado("rail", true)).toBe(true);
    expect(resolverPlegado("ancho", false)).toBe(false);
  });
  it("sin elección manda la ventana: bajo 1280 px, plegado", () => {
    expect(resolverPlegado(null, true)).toBe(false);
    expect(resolverPlegado(null, false)).toBe(true);
  });
  it("un valor raro cuenta como que nadie eligió", () => {
    expect(resolverPlegado("cualquiera", true)).toBe(false);
    expect(resolverPlegado("cualquiera", false)).toBe(true);
  });
});

describe("el cajón con el dedo", () => {
  it("hasta los 6 px no se sabe; de lado es de lado; de arriba abajo sigue siendo desplazar el menú", () => {
    expect(decidirLado(3, 2)).toBeNull();
    expect(decidirLado(-30, 5)).toBe("lado");
    expect(decidirLado(-10, 40)).toBe("otro");
  });
  it("se cierra pasado un tercio del ancho o de un tirón; a la derecha nunca", () => {
    expect(cierraElCajon(-101, 0, 300)).toBe(true);
    expect(cierraElCajon(-99, 0, 300)).toBe(false);
    expect(cierraElCajon(-20, -0.5, 300)).toBe(true);
    expect(cierraElCajon(120, -1, 300)).toBe(false);
    expect(cierraElCajon(0, 0, 300)).toBe(false);
  });
  it("a la izquierda sigue al dedo; a la derecha resiste y no pasa de 16 px", () => {
    expect(posicionDelCajon(-50)).toBe(-50);
    expect(posicionDelCajon(2000)).toBeLessThan(16);
    expect(posicionDelCajon(40)).toBeGreaterThan(0);
  });
});

// Las hojas de verdad, en el orden en que se cargan. `temasDe` conoce los bloques de Retail: se les quita lo del atributo para que los lea.
const leer = (ruta: string) => readFileSync(join(__dirname, "..", ruta), "utf8");
const sinAtributo = (css: string) =>
  css
    .replaceAll(':root[data-vidrio="panel"]:not([data-tema="oscuro"])', ":root")
    .replaceAll(':root[data-vidrio="panel"][data-tema="oscuro"]', ':root[data-tema="oscuro"]')
    .replace(/@media screen and \(prefers-color-scheme: dark\) \{[\s\S]*?\n\}\n/g, "")
    .replace(/@media \(prefers-reduced-transparency: reduce\) \{[\s\S]*?\n\}\n/g, "")
    .replaceAll(":root[data-vidrio][data-tema=\"oscuro\"]", ':root[data-tema="oscuro"]')
    .replaceAll(":root[data-vidrio]", ":root");
const TEMAS = temasDe(
  leer("apps/web/app/globals.css"),
  sinAtributo(leer("apps/web/app/estilos/vidrio/recetas.generado.css")),
  sinAtributo(leer("apps/web/app/estilos/vidrio/marca.css")),
);

const RIEL = ["var(--riel-fondo)"];
const PAGINA = ["var(--color-crema)", "var(--color-papel)", "var(--color-sand)"];
const tinte = (c: string, p: number) => `color-mix(in srgb, var(--color-${c}) ${p}%, transparent)`;

describe.each(["claro", "oscuro"] as const)("se lee sobre el vidrio: %s", (tema) => {
  const t = TEMAS[tema];
  const PIEZAS: Array<[nombre: string, letra: string, fondo: string | null, detras: string[], umbral?: number]> = [
    ["una fila del menú", tinte("tinta", 80), null, RIEL],
    ["la fila donde estás", "var(--color-tinta)", "var(--menu-activa-fondo)", RIEL],
    ["una pantalla dentro de la bandeja", tinte("tinta", 80), "var(--bandeja-fondo)", RIEL],
    ["el nombre bajo el DYNAMIC del logo", "var(--color-taupe)", null, RIEL],
    ["el número junto a una fila", "var(--color-ambar-profundo)", tinte("ambar", 15), RIEL],
    ["el número lleno, plegado", "var(--color-crema)", "var(--color-ambar)", RIEL],
    ["el nombre en la placa", "var(--color-tinta)", "var(--placa-fondo)", RIEL],
    ["el rol y la sede en la placa", tinte("tinta", 66), "var(--placa-fondo)", RIEL],
    ["el texto del buscador", tinte("tinta", 70), "var(--vidrio-flota-fondo)", PAGINA],
    ["la sede en la cabecera", tinte("tinta", 66), "var(--vidrio-flota-fondo)", PAGINA],
    ["una fila en el cajón del teléfono", tinte("tinta", 80), "var(--cajon-movil-fondo)", PAGINA],
    ["la línea sobre el título", "var(--color-taupe)", null, ["var(--color-crema)"]],
    ["el botón del menú en el teléfono", "var(--color-crema)", "var(--color-tinta)", PAGINA],
  ];
  it.each(PIEZAS)("%s ≥ 4.5:1", (_n, letra, fondo, detras) => {
    expect(peorLetra(letra, fondo, t, detras)).toBeGreaterThanOrEqual(UMBRAL.texto);
  });
  it("el contorno del buscador se ve: ≥ 3:1", () => {
    expect(peorBorde("var(--color-borde-control)", t, { fondo: "var(--vidrio-flota-fondo)", detras: ["var(--color-crema)", "var(--color-papel)"] })).toBeGreaterThanOrEqual(UMBRAL.bordeControl);
  });
  it("la marca roja de la fila donde estás se distingue de su ficha: ≥ 3:1", () => {
    expect(contraste(color("var(--color-rojo)", t), color("var(--menu-activa-fondo)", t))).toBeGreaterThanOrEqual(3);
  });
});

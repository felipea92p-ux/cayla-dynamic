// ============================================================================
// medidores.test.ts — lo que sostiene a `tema/` y `responsive/`, sin navegador
// ============================================================================
// Los medidores corren a mano contra un servidor local; lo que se puede comprobar sin él se comprueba aquí: que se nieguen a salir de esta computadora,
// que la matriz sea la acordada, que su lectura del menú siga siendo cierta y que lo registrado exista. Los detectores en sí los prueba
// `tema/autoprueba.mjs`, que necesita Chrome.
//
// NO mide el código de la app: ninguna prueba de aquí falla porque una pantalla tenga un color suelto o se salga. Eso es la línea base, y es un informe.
// ============================================================================
import { describe, expect, it } from "vitest";
import { GRUPOS } from "../apps/web/app/(admin)/admin/nav-items";
import { MATRIZ_VIEWPORTS, resolverViewports } from "../apps/web/responsive/matriz-viewports.mjs";
import { MODULOS, resolverSeleccion, TODAS_LAS_PANTALLAS } from "../apps/web/responsive/pantallas/registro.mjs";
import { SECCIONES_DE_LO_MIO } from "../apps/web/responsive/pantallas/lo-mio.mjs";
import { TABS } from "../apps/web/lib/mio-secciones";
import { coloresSueltosDe } from "../apps/web/tema/colores-sueltos.mjs";
import { CUENTAS, porClave } from "../apps/web/tema/cuentas.mjs";
import { ESCENARIOS } from "../apps/web/tema/escenarios/registro.mjs";
import { inventarioDeRutas, leerMenu, moduloDeRuta } from "../apps/web/tema/motor/rutas.mjs";
import { exigirLocal, problemaDeRed } from "../apps/web/tema/motor/sesion.mjs";

describe("nunca contra producción", () => {
  for (const url of ["https://cayla-dynamic.vercel.app", "https://abcdefgh.supabase.co", "http://localhost.evil.com", "http://127.0.0.1.nip.io:3000", "https://localhost:3000", "no-es-una-url"]) {
    it(`se niega a ${url}`, () => {
      expect(() => exigirLocal(url)).toThrow();
    });
  }
  for (const url of ["http://localhost:3000", "http://127.0.0.1:55892", "http://[::1]:3000"]) {
    it(`acepta ${url}`, () => {
      expect(exigirLocal(url)).toBe(url);
    });
  }

  it("una app en localhost que le pide datos a otro Supabase invalida la medición", () => {
    expect(problemaDeRed(new Set(["abcdefgh.supabase.co"]))).toMatch(/abcdefgh\.supabase\.co/);
    expect(problemaDeRed(new Set(["127.0.0.1:54321"]))).toMatch(/127\.0\.0\.1:54321/);
  });

  it("un servicio ajeno abortado (el de errores, por ejemplo) no la invalida", () => {
    expect(problemaDeRed(new Set(["o123.ingest.sentry.io"]))).toBeNull();
    expect(problemaDeRed(new Set())).toBeNull();
  });
});

describe("la matriz de responsive", () => {
  it("son exactamente estos seis anchos", () => {
    expect(MATRIZ_VIEWPORTS.map((v) => v.w)).toEqual([375, 768, 1024, 1280, 1440, 1920]);
  });

  it("una pantalla sin nada usa la matriz entera, y un id que no existe es un error", () => {
    expect(resolverViewports(undefined)).toHaveLength(6);
    expect(resolverViewports({ excluir: ["375x812"] })).toHaveLength(5);
    expect(() => resolverViewports(["320x568"])).toThrow(/no está en la matriz/);
    expect(() => resolverViewports({ excluir: ["320x568"] })).toThrow(/no está en la matriz/);
  });
});

describe("la lectura del menú sigue siendo cierta", () => {
  it("el texto de nav-items.ts dice lo mismo que su GRUPOS de verdad", () => {
    expect(leerMenu()).toEqual(GRUPOS.map((g) => ({ label: g.label, hrefs: g.items.map((i) => i.href) })));
  });

  it("si le cambian la forma al archivo, lo dice en vez de devolver un menú vacío", () => {
    expect(() => leerMenu("nada que ver")).toThrow(/GRUPOS/);
  });
});

describe("el módulo de una ruta", () => {
  const CASOS: Array<[ruta: string, modulo: string]> = [
    ["/admin/login", "entrada"],
    ["/terminal/vincular", "entrada"],
    ["/admin/dashboard", "inicio"],
    ["/admin/bandeja", "inicio"],
    ["/admin/incidencias", "asistencia"],
    ["/admin/contratos", "documentos"],
    ["/admin/equipo", "personas"],
    ["/admin/planilla", "pago"],
    ["/admin/planilla/boletas", "pago"],
    ["/admin/politica-salarial/versiones", "publicaciones"],
    ["/admin/reporte-sede", "reportes"],
    ["/admin/archivo", "empresa-y-configuracion"],
    ["/admin/sedes", "empresa-y-configuracion"],
    ["/mio", "lo-mio"],
    ["/mio/boleta", "lo-mio"],
    ["/terminal/marcar", "terminal"],
    ["/admin/perfil", "fuera-del-menu"],
  ];
  for (const [ruta, modulo] of CASOS) {
    it(`${ruta} → ${modulo}`, () => {
      expect(moduloDeRuta(ruta)).toBe(modulo);
    });
  }
});

describe("lo registrado existe", () => {
  const { estaticas } = inventarioDeRutas();

  it("hay al menos una pantalla de cada módulo de la obra", () => {
    expect([...MODULOS.keys()].sort()).toEqual(["asistencia", "documentos", "empresa-y-configuracion", "entrada", "inicio", "lo-mio", "pago", "personas", "publicaciones", "reportes", "terminal"]);
  });

  for (const p of TODAS_LAS_PANTALLAS) {
    it(`${p.id}: su ruta existe, y se abre con una cuenta que la alcanza`, () => {
      expect(estaticas).toContain(p.ruta);
      expect(porClave(p.cuenta)?.alcance(p.ruta)).toBe(true);
    });
  }

  it("Lo mío se mide sección por sección: las mismas diecisiete que tiene la pantalla", () => {
    expect(["resumen", ...SECCIONES_DE_LO_MIO].sort()).toEqual([...TABS].sort());
  });

  it("`all` no incluye el caso que debe fallar, y pedirlo por su nombre sí lo trae", () => {
    expect(resolverSeleccion({ todas: true }).some((p: { soloPorId?: boolean }) => p.soloPorId)).toBe(false);
    expect(resolverSeleccion({ ids: ["debe-fallar"] })[0].soloPorId).toBe(true);
  });

  it("los escenarios de contraste tienen id único y apuntan a una ruta real", () => {
    expect(new Set(ESCENARIOS.map((e) => e.id)).size).toBe(ESCENARIOS.length);
    for (const e of ESCENARIOS) expect(estaticas).toContain(e.ruta);
  });

  it("toda cuenta tiene una pantalla de inicio de su propio alcance", () => {
    for (const c of CUENTAS) expect(c.alcance(c.inicio), c.clave).toBe(true);
  });
});

describe("el detector de colores sueltos (solo el detector: el repositorio no se juzga aquí)", () => {
  const clases = (texto: string) => coloresSueltosDe(texto, "ts").clases;

  it("ve la paleta de Tailwind", () => {
    expect(clases('<div className="bg-white text-slate-900 border-amber-100" />')).toBe(3);
    expect(clases('<div className="bg-white/80 text-black" />')).toBe(2);
  });

  it("no cuenta el velo de un modal, que CLAUDE.md pide así", () => {
    expect(clases('<div className="bg-black/40" />')).toBe(0);
  });

  it("no cuenta los tokens de la casa ni lo que está en un comentario", () => {
    expect(clases('<div className="bg-papel text-tinta border-sand" />')).toBe(0);
    expect(clases("// antes decía bg-white\n/* y amber-100 */\nconst a = 1;")).toBe(0);
  });

  it("separa los colores crudos, y en CSS la definición de un token no es un uso", () => {
    expect(coloresSueltosDe('const c = "#12ab34";', "ts").crudos).toBe(1);
    expect(coloresSueltosDe(".x { color: #12ab34; }", "css").crudos).toBe(1);
    expect(coloresSueltosDe("  --color-crema: #f5f0e8;", "css").crudos).toBe(0);
  });
});

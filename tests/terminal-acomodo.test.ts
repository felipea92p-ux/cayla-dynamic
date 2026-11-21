// ============================================================================
// terminal-acomodo.test.ts — el equipo entra completo en la pantalla del terminal
// ============================================================================
// La regla de `lib/terminal/acomodo.ts`: de 3 a más de 20 personas, la grilla de
// retratos se acomoda sola a lo que mide la pantalla. Lo que importa probar no es
// «da tantas columnas» sino lo que promete: que NADA se corta sin avisar. Una
// última fila fuera de la pantalla es una persona que no encuentra su nombre.
// ============================================================================
import { describe, expect, it } from "vitest";
import {
  ANCHO_MAXIMO,
  ANCHO_MINIMO,
  FOTO_MAXIMA,
  RELLENO_CASILLA,
  acomodarRetratos,
  altoDeCasilla,
  altoDelTexto,
} from "@/lib/terminal/acomodo";

// El espacio que queda para los retratos en cada monitor, medido en la pantalla real
// (bajo la isla, el título y la leyenda): Mac mini a 1920×1080, a 1440×900 y a 1366×768.
const GRANDE = { ancho: 1808, alto: 744 };
const MEDIANO = { ancho: 1354, alto: 584 };
const CHICO = { ancho: 1284, alto: 509 };

const altoTotal = (a: ReturnType<typeof acomodarRetratos>) => a.filas * altoDeCasilla(a) + (a.filas - 1) * a.separacion;
const anchoTotal = (a: ReturnType<typeof acomodarRetratos>) => a.columnas * a.ancho + (a.columnas - 1) * a.separacion;

describe("acomodarRetratos, en la Mac mini a 1920×1080", () => {
  it("con 3 personas: una fila de retratos grandes, sin llenar la pantalla a la fuerza", () => {
    const a = acomodarRetratos(3, GRANDE.ancho, GRANDE.alto);
    expect(a).toMatchObject({ columnas: 3, filas: 1, desliza: false });
    expect(a.ancho).toBe(ANCHO_MAXIMO);
    expect(a.foto).toBe(FOTO_MAXIMA);
  });

  it.each([
    [8, 4, 2],
    [13, 7, 2],
    [24, 8, 3],
    [30, 10, 3],
  ])("con %i personas: %i columnas en %i filas, sin deslizar", (personas, columnas, filas) => {
    expect(acomodarRetratos(personas, GRANDE.ancho, GRANDE.alto)).toMatchObject({ columnas, filas, desliza: false });
  });

  it("de 1 a 30 personas todo entra: nada se corta por abajo ni por el costado", () => {
    for (let personas = 1; personas <= 30; personas++) {
      const a = acomodarRetratos(personas, GRANDE.ancho, GRANDE.alto);
      expect(a.desliza, `${personas} personas`).toBe(false);
      expect(altoTotal(a), `${personas} personas, alto`).toBeLessThanOrEqual(GRANDE.alto);
      expect(anchoTotal(a), `${personas} personas, ancho`).toBeLessThanOrEqual(GRANDE.ancho);
      expect(a.columnas * a.filas, `${personas} personas, lugares`).toBeGreaterThanOrEqual(personas);
    }
  });

  it("con la segunda línea reservada también entra, y el retrato cede ese alto", () => {
    const sin = acomodarRetratos(24, GRANDE.ancho, GRANDE.alto);
    const con = acomodarRetratos(24, GRANDE.ancho, GRANDE.alto, { segundaLinea: true });
    expect(con.desliza).toBe(false);
    expect(altoTotal(con)).toBeLessThanOrEqual(GRANDE.alto);
    expect(con.texto).toBeGreaterThan(sin.texto);
    expect(con.foto).toBeLessThan(sin.foto);
  });
});

describe("acomodarRetratos, en monitores más chicos", () => {
  it("a 1440×900 un equipo de 24 todavía entra completo", () => {
    const a = acomodarRetratos(24, MEDIANO.ancho, MEDIANO.alto);
    expect(a.desliza).toBe(false);
    expect(altoTotal(a)).toBeLessThanOrEqual(MEDIANO.alto);
  });

  it("a 1366×768 un equipo de 13 entra completo", () => {
    const a = acomodarRetratos(13, CHICO.ancho, CHICO.alto);
    expect(a.desliza).toBe(false);
    expect(altoTotal(a)).toBeLessThanOrEqual(CHICO.alto);
  });

  it("a 1366×768 un equipo de 24 NO entra a un tamaño que se lea: lo dice en vez de encoger los nombres", () => {
    const a = acomodarRetratos(24, CHICO.ancho, CHICO.alto);
    expect(a.desliza).toBe(true);
    expect(a.ancho).toBeGreaterThanOrEqual(ANCHO_MINIMO);
    expect(anchoTotal(a)).toBeLessThanOrEqual(CHICO.ancho);
    // Y se nota que hay más: la grilla mide más que la pantalla.
    expect(altoTotal(a)).toBeGreaterThan(CHICO.alto);
  });
});

describe("acomodarRetratos, lo que no cambia con el tamaño", () => {
  it("la casilla nunca baja del ancho en que un nombre se lee, ni el retrato deja de ser una foto", () => {
    for (const espacio of [GRANDE, MEDIANO, CHICO]) {
      for (let personas = 1; personas <= 40; personas++) {
        const a = acomodarRetratos(personas, espacio.ancho, espacio.alto);
        const interior = a.ancho - 2 * RELLENO_CASILLA;
        expect(a.ancho, `${personas} en ${espacio.ancho}`).toBeGreaterThanOrEqual(ANCHO_MINIMO);
        expect(a.ancho).toBeLessThanOrEqual(ANCHO_MAXIMO);
        expect(a.foto / interior, `${personas} en ${espacio.ancho}, proporción`).toBeGreaterThanOrEqual(0.6);
        expect(a.foto / interior).toBeLessThanOrEqual(1.25);
        expect(a.letraNombre).toBeGreaterThanOrEqual(19);
      }
    }
  });

  it("la misma pregunta da la misma respuesta: los nombres no cambian de lugar entre dos refrescos", () => {
    expect(acomodarRetratos(13, GRANDE.ancho, GRANDE.alto)).toEqual(acomodarRetratos(13, GRANDE.ancho, GRANDE.alto));
  });

  it("sin nadie o con una medida de cero no revienta", () => {
    expect(acomodarRetratos(0, GRANDE.ancho, GRANDE.alto).columnas).toBe(1);
    const sinEspacio = acomodarRetratos(12, 0, 0);
    expect(sinEspacio.columnas).toBe(1);
    expect(sinEspacio.ancho).toBeGreaterThan(0);
    expect(sinEspacio.foto).toBeGreaterThan(0);
  });

  it("el alto del texto es el de la casilla: nombre, apellidos y estado", () => {
    // 10 de aire + nombre de pila a 27 px (×1,15) + apellidos 20 + 6 + estado 20 + 4.
    expect(altoDelTexto(ANCHO_MAXIMO, false)).toBe(10 + 32 + 20 + 6 + 20 + 4);
    expect(altoDelTexto(ANCHO_MAXIMO, true) - altoDelTexto(ANCHO_MAXIMO, false)).toBe(18);
  });
});

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
  ANCHO_DE_UNA_LINEA,
  ANCHO_MAXIMO,
  ANCHO_MINIMO,
  FOTO_MAXIMA,
  MARCO_CASILLA,
  acomodarRetratos,
  altoDeCasilla,
  altoDelTexto,
} from "@/lib/terminal/acomodo";

// El espacio que queda para los retratos en cada monitor, MEDIDO en el navegador el 2026-11-21 con la pantalla
// de verdad (bajo la isla, el título y la leyenda): a 1920×1080, a 1440×900 y a 1366×768.
const GRANDE = { ancho: 1808, alto: 803 };
const MEDIANO = { ancho: 1354, alto: 576 };
const CHICO = { ancho: 1284, alto: 473 };

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

  it("de 1 a 33 personas todo entra, por la mañana y por la tarde: nada se corta por abajo ni por el costado", () => {
    // Por la tarde casi todos ya salieron y volvieron de su refrigerio: la casilla lleva un renglón más.
    for (const segundaLinea of [false, true]) {
      for (let personas = 1; personas <= 33; personas++) {
        const a = acomodarRetratos(personas, GRANDE.ancho, GRANDE.alto, { segundaLinea });
        const caso = `${personas} personas${segundaLinea ? ", por la tarde" : ""}`;
        expect(a.desliza, caso).toBe(false);
        expect(altoTotal(a), `${caso}: alto`).toBeLessThanOrEqual(GRANDE.alto);
        expect(anchoTotal(a), `${caso}: ancho`).toBeLessThanOrEqual(GRANDE.ancho);
        expect(a.columnas * a.filas, `${caso}: lugares`).toBeGreaterThanOrEqual(personas);
      }
    }
  });

  it("con más de 33 ya no entran a un tamaño que se lea, y lo dice", () => {
    expect(acomodarRetratos(36, GRANDE.ancho, GRANDE.alto).desliza).toBe(true);
  });

  it("con la segunda línea reservada también entra, y el retrato cede ese alto", () => {
    const sin = acomodarRetratos(24, GRANDE.ancho, GRANDE.alto);
    const con = acomodarRetratos(24, GRANDE.ancho, GRANDE.alto, { segundaLinea: true });
    expect(con.desliza).toBe(false);
    expect(con.renglones).toBeGreaterThan(sin.renglones);
    expect(altoTotal(con)).toBeLessThanOrEqual(GRANDE.alto);
    expect(con.texto).toBeGreaterThan(sin.texto);
    expect(con.foto).toBeLessThan(sin.foto);
  });
});

describe("acomodarRetratos, en monitores más chicos", () => {
  it("a 1440×900 un equipo de 16 entra completo, y uno de 24 se desliza y lo dice", () => {
    const a = acomodarRetratos(16, MEDIANO.ancho, MEDIANO.alto);
    expect(a.desliza).toBe(false);
    expect(altoTotal(a)).toBeLessThanOrEqual(MEDIANO.alto);
    expect(acomodarRetratos(24, MEDIANO.ancho, MEDIANO.alto).desliza).toBe(true);
  });

  it("a 1366×768 un equipo de 16 entra completo, también por la tarde", () => {
    for (const segundaLinea of [false, true]) {
      const a = acomodarRetratos(16, CHICO.ancho, CHICO.alto, { segundaLinea });
      expect(a.desliza).toBe(false);
      expect(altoTotal(a)).toBeLessThanOrEqual(CHICO.alto);
    }
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
        const interior = a.ancho - MARCO_CASILLA;
        expect(a.ancho, `${personas} en ${espacio.ancho}`).toBeGreaterThanOrEqual(ANCHO_MINIMO);
        expect(a.ancho).toBeLessThanOrEqual(ANCHO_MAXIMO);
        expect(a.foto / interior, `${personas} en ${espacio.ancho}, proporción`).toBeGreaterThanOrEqual(0.55);
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

  it("una casilla angosta reserva sola un renglón más: una hora no se corta con puntos suspensivos", () => {
    const ancha = acomodarRetratos(13, GRANDE.ancho, GRANDE.alto);
    expect(ancha.ancho - MARCO_CASILLA).toBeGreaterThanOrEqual(ANCHO_DE_UNA_LINEA);
    expect(ancha.renglones).toBe(1);
    const angosta = acomodarRetratos(30, GRANDE.ancho, GRANDE.alto);
    expect(angosta.ancho - MARCO_CASILLA).toBeLessThan(ANCHO_DE_UNA_LINEA);
    expect(angosta.renglones).toBe(2);
    expect(angosta.texto).toBe(altoDelTexto(angosta.ancho, 2));
    // Y si además alguien salió y volvió, son tres: su hora de entrada, y el «salió · volvió» partido en dos.
    expect(acomodarRetratos(30, GRANDE.ancho, GRANDE.alto, { segundaLinea: true }).renglones).toBe(3);
  });

  it("la casilla mide su retrato, su texto y su marco: relleno de 8 px y borde de 1 px por lado", () => {
    const a = acomodarRetratos(13, GRANDE.ancho, GRANDE.alto);
    expect(MARCO_CASILLA).toBe(18);
    expect(altoDeCasilla(a)).toBe(a.foto + a.texto + 18);
  });

  it("el alto del texto es el de la casilla: nombre, apellidos y estado", () => {
    // 10 de aire + nombre de pila a 27 px (×1,15) + apellidos 20 + 6 + estado 20 + 4.
    expect(altoDelTexto(ANCHO_MAXIMO, 1)).toBe(10 + 32 + 20 + 6 + 20 + 4);
    expect(altoDelTexto(ANCHO_MAXIMO, 2) - altoDelTexto(ANCHO_MAXIMO, 1)).toBe(18);
    expect(altoDelTexto(ANCHO_MAXIMO, 3) - altoDelTexto(ANCHO_MAXIMO, 1)).toBe(36);
  });
});

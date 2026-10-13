// ============================================================================
// easter-eggs.test.ts — cuándo se activa cada easter egg, y cuándo NO
// ============================================================================
// Un easter egg que se dispara por accidente deja de ser un easter egg: es un
// defecto. Lo que se prueba acá es sobre todo lo segundo —que no se active
// con lo que alguien hace de verdad— más que lo primero.
// ============================================================================
import { describe, it, expect } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import {
  CLICS_PARA_EL_HUEVO, CODIGO_KONAMI, VENTANA_DE_CLICS_MS,
  avanzarKonami, esPalabraDelColibri, registrarClic, toqueDeFecha,
} from "@/lib/easter-eggs";
import { saludoDelDia } from "@/lib/login-vuelo";

const teclear = (teclas: readonly string[]) => {
  let p = 0;
  let completo = false;
  for (const t of teclas) {
    p = avanzarKonami(p, t);
    if (p === CODIGO_KONAMI.length) { completo = true; p = 0; }
  }
  return completo;
};

describe("código Konami", () => {
  it("la secuencia completa lo activa", () => {
    expect(teclear(CODIGO_KONAMI)).toBe(true);
  });

  it("acepta B y A en mayúscula (Bloq Mayús, o Shift sin querer)", () => {
    expect(teclear([...CODIGO_KONAMI.slice(0, 8), "B", "A"])).toBe(true);
  });

  it("una tecla equivocada en medio lo reinicia", () => {
    expect(teclear(["ArrowUp", "ArrowUp", "ArrowDown", "x", "ArrowDown", "ArrowLeft", "ArrowRight", "ArrowLeft", "ArrowRight", "b", "a"])).toBe(false);
  });

  it("empezar de nuevo justo en la tecla equivocada no pierde el intento (↑↑↑↓↓… también vale)", () => {
    expect(teclear(["ArrowUp", ...CODIGO_KONAMI])).toBe(true);
  });

  it("navegar normalmente por el panel no lo activa", () => {
    // Una persona recorriendo una tabla: flechas arriba y abajo, nunca el resto de la secuencia.
    const recorrido = ["ArrowDown", "ArrowDown", "ArrowDown", "ArrowUp", "ArrowDown", "ArrowUp", "ArrowUp", "ArrowDown", "Enter", "a", "b"];
    expect(teclear(recorrido)).toBe(false);
  });

  it("completarlo dos veces seguidas lo activa dos veces", () => {
    expect(teclear([...CODIGO_KONAMI, ...CODIGO_KONAMI])).toBe(true);
    let p = 0, veces = 0;
    for (const t of [...CODIGO_KONAMI, ...CODIGO_KONAMI]) {
      p = avanzarKonami(p, t);
      if (p === CODIGO_KONAMI.length) { veces++; p = 0; }
    }
    expect(veces).toBe(2);
  });
});

describe("la palabra del buscador", () => {
  it("«colibrí» con cualquier mayúscula, tilde o espacio sobrante", () => {
    for (const q of ["colibri", "colibrí", "Colibrí", "COLIBRÍ", "  colibri  "]) expect(esPalabraDelColibri(q)).toBe(true);
  });

  it("no se activa con una persona o una pantalla que contenga la palabra", () => {
    for (const q of ["colibr", "colibris", "el colibri", "colibri azul", "", "   "]) expect(esPalabraDelColibri(q)).toBe(false);
  });
});

describe("cinco clics seguidos", () => {
  const rafaga = (tiempos: number[]) => {
    let marcas: number[] = [];
    let dispara = false;
    for (const t of tiempos) {
      const r = registrarClic(marcas, t);
      marcas = r.marcas;
      dispara = dispara || r.dispara;
    }
    return dispara;
  };

  it("cinco clics dentro de la ventana lo activan, y no antes", () => {
    expect(CLICS_PARA_EL_HUEVO).toBe(5);
    expect(rafaga([0, 200, 400, 600])).toBe(false);
    expect(rafaga([0, 200, 400, 600, 800])).toBe(true);
  });

  it("cinco clics lentos (tocando el logo con calma) no lo activan", () => {
    expect(rafaga([0, 1500, 3000, 4500, 6000])).toBe(false);
  });

  it("cuenta solo los de la ventana: los viejos se descartan", () => {
    expect(rafaga([0, 100, 5000, 5100, 5200, 5300])).toBe(false);
    expect(rafaga([0, 100, 5000, 5100, 5200, 5300, 5400])).toBe(true);
  });

  it("al dispararse arranca de cero: hacen falta otros cinco para repetirlo", () => {
    expect(registrarClic([0, 100, 200, 300], 400)).toEqual({ marcas: [], dispara: true });
    expect(registrarClic([], 500).dispara).toBe(false);
  });

  it("la ventana es de 2 segundos", () => {
    expect(VENTANA_DE_CLICS_MS).toBe(2000);
    expect(rafaga([0, 500, 1000, 1500, 2000])).toBe(true);
    expect(rafaga([0, 500, 1000, 1500, 2001])).toBe(false);
  });
});

describe("toques de fecha", () => {
  it("Fiestas Patrias el 28 y 29 de julio; Navidad el 24 y 25 de diciembre", () => {
    expect(toqueDeFecha("2026-07-28")).toBe("Felices Fiestas Patrias");
    expect(toqueDeFecha("2026-07-29")).toBe("Felices Fiestas Patrias");
    expect(toqueDeFecha("2026-12-24")).toBe("Feliz Navidad");
    expect(toqueDeFecha("2026-12-25")).toBe("Feliz Navidad");
  });

  it("cualquier otro día no lleva toque, ni el anterior ni el siguiente", () => {
    for (const f of ["2026-07-27", "2026-07-30", "2026-12-23", "2026-12-26", "2026-10-13", "2026-01-01", "2026-02-29"]) {
      expect(toqueDeFecha(f)).toBeNull();
    }
  });

  it("una fecha mal escrita no revienta: simplemente no hay toque", () => {
    for (const f of ["", "hoy", "2026-7-28", "28/07/2026", "2026-12-25T10:00"]) expect(toqueDeFecha(f)).toBeNull();
  });
});

describe("el saludo del login con el toque de fecha", () => {
  // Perú es UTC-5 todo el año. 14:00 UTC = 9:00 en Lima.
  const lima = (m: number, d: number, horaLima = 9) => new Date(Date.UTC(2026, m - 1, d, horaLima + 5, 0));

  it("en Navidad lo lleva al final, y lo demás del saludo queda igual", () => {
    expect(saludoDelDia(lima(12, 25))).toBe("Buenos días · viernes 25 de diciembre · Feliz Navidad");
  });

  it("en Fiestas Patrias también", () => {
    expect(saludoDelDia(lima(7, 28))).toBe("Buenos días · martes 28 de julio · Felices Fiestas Patrias");
  });

  it("un día cualquiera queda exactamente como estaba", () => {
    expect(saludoDelDia(lima(10, 13))).toBe("Buenos días · martes 13 de octubre");
  });

  it("manda el día de Lima, no el de UTC: a las 11 p. m. del 24 en Lima ya es 25 en UTC, y sigue siendo Navidad Eve", () => {
    // 23:00 en Lima del 23 de diciembre = 04:00 UTC del 24: el día de Lima es el 23 → sin toque.
    expect(saludoDelDia(lima(12, 23, 23))).not.toContain("Navidad");
    // 23:00 en Lima del 24 → toque, aunque en UTC ya sea 25.
    expect(saludoDelDia(lima(12, 24, 23))).toContain("Feliz Navidad");
  });
});

describe("el terminal de marcaje no tiene easter eggs: se vigila, no se confía", () => {
  // La regla número 2 de docs/easter-eggs.md. Un huevo montado en el terminal
  // dejaría que una tecla suelta, en una pantalla a la vista de toda la sede,
  // dispare algo mientras alguien marca. Como la regla es «nada se monta ahí»,
  // se comprueba mirando QUÉ importa cada archivo del terminal.
  const RAIZ = path.resolve(import.meta.dirname, "../apps/web");
  const PROHIBIDOS = ["colibri-viajero", "juego-colibri", "registrar-sin-conexion", "use-rafaga-de-clics", "lib/easter-eggs", "buscador-global"];

  function archivos(dir: string): string[] {
    return readdirSync(dir, { withFileTypes: true }).flatMap((d) =>
      d.isDirectory() ? archivos(path.join(dir, d.name)) : /\.(tsx?|css)$/.test(d.name) ? [path.join(dir, d.name)] : [],
    );
  }

  it("ningún archivo de app/(terminal) importa un huevo", () => {
    const culpables: string[] = [];
    for (const f of archivos(path.join(RAIZ, "app/(terminal)"))) {
      const texto = readFileSync(f, "utf8");
      for (const p of PROHIBIDOS) if (texto.includes(p)) culpables.push(`${path.relative(RAIZ, f)} → ${p}`);
    }
    expect(culpables).toEqual([]);
  });

  it("y los componentes del terminal tampoco (lib/terminal, y los que el terminal comparte)", () => {
    const culpables: string[] = [];
    for (const f of archivos(path.join(RAIZ, "lib/terminal"))) {
      const texto = readFileSync(f, "utf8");
      for (const p of PROHIBIDOS) if (texto.includes(p)) culpables.push(`${path.relative(RAIZ, f)} → ${p}`);
    }
    expect(culpables).toEqual([]);
  });
});

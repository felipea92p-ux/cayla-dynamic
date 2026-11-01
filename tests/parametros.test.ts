// ============================================================================
// parametros.test.ts — «Parámetros» (0552), en lo que se puede probar sin base
// ============================================================================
// Defiende tres cosas, y las tres hacen falta:
//   1. QUIÉN: DO cambia lo operativo y lo que mueve un pago; lo normativo es solo
//      de la dirección; la líder de equipo y la integrante, ni entran. Una clase
//      desconocida NIEGA.
//   2. QUÉ SE TECLEA: lo que no es un número, lo que se sale del rango y el
//      decimal en un entero se atajan antes de viajar a la base.
//   3. A QUIÉN AFECTA: la vista previa dice exactamente a quién le cambia la
//      situación, sin inventar una segunda copia de la regla de «cumplida» y
//      «vencida» (esa vive en packages/shared).
// La base tiene su propia prueba (supabase/tests/444): acá no se repite lo que
// solo ella puede decir (el candado, el historial, los límites por cualquier camino).
// ============================================================================
import { describe, it, expect } from "vitest";
import {
  CLASES_PARAMETRO,
  ETIQUETA_CLASE_PARAMETRO,
  describirCambioDeParametro,
  etiquetaQuienCambia,
  puedeCambiarParametro,
  puedeGestionarParametros,
  validarValorParametro,
  valorConUnidad,
  type LimitesParametro,
} from "@cayla-dynamic/shared";
import {
  fechaInicialDeVigencia,
  fechaMinimaDeVigencia,
  fuenteDeImpacto,
  impactoAvisoDescansoMedico,
  impactoDeVistaPrevia,
  valorAntesDelCambio,
  impactoDiasDePrueba,
  normalizarCambios,
  normalizarParametros,
  notaDeEfecto,
  repartirParametros,
} from "@/lib/admin/parametros";
import type { FilaPrueba } from "@/lib/admin/pruebas";
import { avisoDeCambioDePlata, opcionesDeVigencia } from "@/lib/admin/cambio-de-plata";

const ROLES = ["admin", "lider_do", "supervisor_sede", "integrante"] as const;

describe("quién ve y quién cambia", () => {
  it("entran a Parámetros la dirección y DO; la líder de equipo y la integrante no", () => {
    expect(puedeGestionarParametros("admin")).toBe(true);
    expect(puedeGestionarParametros("lider_do")).toBe(true);
    expect(puedeGestionarParametros("supervisor_sede")).toBe(false);
    expect(puedeGestionarParametros("integrante")).toBe(false);
  });

  it("sin rol, con rol vacío o desconocido: no entra nadie (null nunca abre)", () => {
    for (const rol of [null, undefined, "", "gerente"]) {
      expect(puedeGestionarParametros(rol), String(rol)).toBe(false);
      expect(puedeCambiarParametro(rol, "operativo"), String(rol)).toBe(false);
    }
  });

  it("DO cambia lo operativo y lo que mueve un pago (decisión del 2026-10-26)", () => {
    for (const clase of ["operativo", "plata"] as const) {
      expect(puedeCambiarParametro("admin", clase)).toBe(true);
      expect(puedeCambiarParametro("lider_do", clase)).toBe(true);
      expect(puedeCambiarParametro("supervisor_sede", clase)).toBe(false);
      expect(puedeCambiarParametro("integrante", clase)).toBe(false);
    }
  });

  it("lo normativo —ley o RIT— es solo de la dirección: DO NO lo cambia", () => {
    expect(puedeCambiarParametro("admin", "normativo")).toBe(true);
    expect(puedeCambiarParametro("lider_do", "normativo")).toBe(false);
    expect(puedeCambiarParametro("supervisor_sede", "normativo")).toBe(false);
    expect(puedeCambiarParametro("integrante", "normativo")).toBe(false);
  });

  it("una clase desconocida o ausente NIEGA, para cualquier rol", () => {
    for (const rol of ROLES) {
      for (const clase of ["secreto", "", null, undefined]) {
        expect(puedeCambiarParametro(rol, clase), `${rol} / ${String(clase)}`).toBe(false);
      }
    }
  });

  it("con roles_cambia (0571) manda la lista de la fila, no la clase", () => {
    expect(puedeCambiarParametro("admin", "plata", ["admin"])).toBe(true);
    expect(puedeCambiarParametro("lider_do", "plata", ["admin"])).toBe(false);
    expect(puedeCambiarParametro("lider_do", "plata", ["admin", "lider_do"])).toBe(true);
  });

  it("la lista no abre la puerta a quien no entra a Parámetros", () => {
    for (const rol of ["supervisor_sede", "integrante", null, undefined, ""]) {
      expect(puedeCambiarParametro(rol, "operativo", ["admin", "lider_do", "supervisor_sede"]), String(rol)).toBe(false);
    }
  });

  it("sin roles_cambia (la base aún no tiene la 0571) vale la clase de siempre", () => {
    expect(puedeCambiarParametro("lider_do", "operativo", null)).toBe(true);
    expect(puedeCambiarParametro("lider_do", "normativo", undefined)).toBe(false);
  });

  it("etiquetaQuienCambia dice quién, y calla si la lista no viene", () => {
    expect(etiquetaQuienCambia(["admin"])).toBe("Lo cambia: la dirección");
    expect(etiquetaQuienCambia(["admin", "lider_do"])).toBe("Lo cambian: la dirección y Desarrollo Organizacional");
    expect(etiquetaQuienCambia([])).toBeNull();
    expect(etiquetaQuienCambia(null)).toBeNull();
  });

  it("quien no puede ENTRAR tampoco puede cambiar algo operativo: la matriz es coherente", () => {
    for (const rol of ROLES) {
      if (puedeCambiarParametro(rol, "operativo")) expect(puedeGestionarParametros(rol), rol).toBe(true);
    }
  });

  it("cada clase tiene su etiqueta, y no hay etiquetas de más", () => {
    expect(Object.keys(ETIQUETA_CLASE_PARAMETRO).sort()).toEqual([...CLASES_PARAMETRO].sort());
  });
});

describe("validarValorParametro: lo que se teclea", () => {
  const dias: LimitesParametro = { nombre: "Días de prueba", unidad: "días", tipo_valor: "entero", valor_min: 1, valor_max: 15 };
  const tasa: LimitesParametro = { nombre: "Tasa", unidad: "%", tipo_valor: "decimal", valor_min: 0, valor_max: 1 };

  it("un entero dentro del rango pasa, también con espacios alrededor", () => {
    expect(validarValorParametro(dias, "5")).toEqual({ ok: true, valor: 5 });
    expect(validarValorParametro(dias, "  7 ")).toEqual({ ok: true, valor: 7 });
  });

  it("los dos extremos entran (el rango es inclusivo, igual que en la base)", () => {
    expect(validarValorParametro(dias, "1")).toEqual({ ok: true, valor: 1 });
    expect(validarValorParametro(dias, "15")).toEqual({ ok: true, valor: 15 });
  });

  it("fuera de rango se rechaza y el mensaje dice cuál es el rango", () => {
    expect(validarValorParametro(dias, "0")).toEqual({ ok: false, mensaje: "Va de 1 a 15 días." });
    expect(validarValorParametro(dias, "16")).toEqual({ ok: false, mensaje: "Va de 1 a 15 días." });
    expect(validarValorParametro(dias, "30")).toEqual({ ok: false, mensaje: "Va de 1 a 15 días." });
  });

  it("un decimal en un parámetro entero se rechaza", () => {
    expect(validarValorParametro(dias, "2.5")).toEqual({ ok: false, mensaje: "Tiene que ser un número entero." });
    expect(validarValorParametro(dias, "2,5")).toEqual({ ok: false, mensaje: "Tiene que ser un número entero." });
  });

  it("en un decimal se acepta la coma, como se escribe en Perú", () => {
    expect(validarValorParametro(tasa, "0,25")).toEqual({ ok: true, valor: 0.25 });
    expect(validarValorParametro(tasa, "0.25")).toEqual({ ok: true, valor: 0.25 });
  });

  it("vacío o lo que no es un número, no: tampoco notación científica ni hexadecimal", () => {
    expect(validarValorParametro(dias, "").ok).toBe(false);
    expect(validarValorParametro(dias, "   ").ok).toBe(false);
    for (const x of ["tres", "3 días", "1e1", "0x10", "--3", "3.", ".5", "Infinity", "NaN"]) {
      expect(validarValorParametro(dias, x).ok, x).toBe(false);
    }
  });

  it("sin tope máximo o sin mínimo, el mensaje lo dice con palabras que cuadran", () => {
    expect(validarValorParametro({ ...dias, valor_max: null }, "0")).toEqual({ ok: false, mensaje: "Tiene que ser de 1 días o más." });
    expect(validarValorParametro({ ...dias, valor_min: null }, "99")).toEqual({ ok: false, mensaje: "Tiene que ser de 15 días o menos." });
    expect(validarValorParametro({ ...dias, valor_min: null, valor_max: null }, "99")).toEqual({ ok: true, valor: 99 });
  });
});

describe("cómo se dice un valor y un cambio", () => {
  it("la unidad va en singular cuando el valor es 1", () => {
    expect(valorConUnidad(1, "días")).toBe("1 día");
    expect(valorConUnidad(3, "días")).toBe("3 días");
    expect(valorConUnidad(1, "horas")).toBe("1 hora");
    expect(valorConUnidad(0, "días")).toBe("0 días");
  });

  it("un cambio se dice de qué a qué, con la unidad una sola vez", () => {
    expect(describirCambioDeParametro(3, 5, "días")).toBe("3 → 5 días");
    expect(describirCambioDeParametro(5, 1, "días")).toBe("5 → 1 día");
  });
});

// Una persona de prueba, con lo que la base entrega ya contado.
function prueba(nombres: string, dias: number, plazo: number, situacion?: string): FilaPrueba {
  return {
    prueba_id: null, persona_id: nombres, nombres, apellidos: "Perez", sede_id: null, sede_codigo: "TRU",
    inicio: "2026-10-20", dias_trabajados: dias, dias_plazo: plazo,
    situacion: situacion ?? (dias > plazo ? "vencida" : dias === plazo ? "cumplida" : "en_curso"),
    ultima_jornada: null, registrada: true, horas_marcadas: 0, dni_cargado: false,
  };
}

describe("a quién afecta cambiar los días de prueba", () => {
  it("subir el plazo de 3 a 5: quien ya cumplió vuelve a «en curso»; quien iba por la mitad, no cambia", () => {
    const r = impactoDiasDePrueba([prueba("Ana", 3, 3), prueba("Beto", 1, 3)], 5);
    expect(r.filas).toEqual([{ persona: "Ana Perez", antes: "Preselección · 3 de 3", despues: "Preselección · 3 de 5" }]);
    expect(r.sinCambio).toBe(1);
  });

  it("subir el plazo rescata a quien ya estaba «vencida»", () => {
    const r = impactoDiasDePrueba([prueba("Carla", 4, 3)], 5);
    expect(r.filas).toHaveLength(1);
    expect(r.filas[0]).toMatchObject({ persona: "Carla Perez", antes: "Preselección · 4 días", despues: "Preselección · 4 de 5" });
  });

  it("bajar el plazo de 3 a 2: quien llevaba 2 pasa a «cumplida»; quien llevaba 3, a «vencida»", () => {
    const r = impactoDiasDePrueba([prueba("Dora", 2, 3), prueba("Elisa", 3, 3), prueba("Fabi", 1, 3)], 2);
    expect(r.filas.map((f) => f.persona)).toEqual(["Dora Perez", "Elisa Perez"]);
    expect(r.filas[0].despues).toBe("Preselección · 2 de 2");
    expect(r.filas[1].despues).toBe("Preselección · 3 días");
    expect(r.sinCambio).toBe(1);
  });

  it("el mismo plazo no mueve a nadie", () => {
    const r = impactoDiasDePrueba([prueba("Gabi", 3, 3), prueba("Hugo", 1, 3)], 3);
    expect(r.filas).toEqual([]);
    expect(r.sinCambio).toBe(2);
  });

  it("sin nadie de prueba, lo dice: no es lo mismo que «no hay impacto»", () => {
    const r = impactoDiasDePrueba([], 5);
    expect(r.filas).toEqual([]);
    expect(r.nota).toMatch(/nadie en preselección/);
  });

  it("confía en la situación que dijo la base, no la recalcula del plazo viejo", () => {
    // La base dice «cumplida» aunque 2 de 3 no lo sea por aritmética: manda la base.
    const r = impactoDiasDePrueba([prueba("Ines", 2, 3, "cumplida")], 3);
    expect(r.filas).toHaveLength(1);
    expect(r.filas[0].antes).toBe("Preselección · 3 de 3");
  });
});

describe("a quién afecta cambiar desde cuándo se avisa un descanso médico", () => {
  const filas = [
    { persona_id: "1", nombre: "Ana Perez", dias_calendario: 18 },
    { persona_id: "2", nombre: "Beto Ruiz", dias_calendario: 12 },
    { persona_id: "3", nombre: "Carla Soto", dias_calendario: 4 },
  ];

  it("de 15 a 10: se empieza a avisar de quien lleva 12; quien lleva 18 ya se avisaba", () => {
    const r = impactoAvisoDescansoMedico(filas, 15, 10);
    expect(r.filas).toEqual([{ persona: "Beto Ruiz", antes: "No se avisa (lleva 12)", despues: "Se avisaría" }]);
    expect(r.sinCambio).toBe(2);
  });

  it("de 15 a 20: se deja de avisar de quien lleva 18", () => {
    const r = impactoAvisoDescansoMedico(filas, 15, 20);
    expect(r.filas).toEqual([{ persona: "Ana Perez", antes: "Se avisa (lleva 18)", despues: "Dejaría de avisarse" }]);
  });

  it("aclara que solo cambia el aviso: el tope de días que paga CAYLA lo fija el RIT", () => {
    expect(impactoAvisoDescansoMedico(filas, 15, 10).nota).toMatch(/RIT/);
  });

  it("el límite es inclusivo: llevar justo el valor ya cuenta como «se avisa»", () => {
    const r = impactoAvisoDescansoMedico([{ persona_id: "9", nombre: "Dora Gil", dias_calendario: 12 }], 15, 12);
    expect(r.filas).toHaveLength(1);
  });

  it("el borde de HOY también es inclusivo: quien lleva justo 15 ya se avisa, y subir a 16 deja de avisarse", () => {
    const r = impactoAvisoDescansoMedico([{ persona_id: "9", nombre: "Dora Gil", dias_calendario: 15 }], 15, 16);
    expect(r.filas).toEqual([{ persona: "Dora Gil", antes: "Se avisa (lleva 15)", despues: "Dejaría de avisarse" }]);
    // y con el mismo umbral no se mueve nadie: el borde no se cuenta dos veces
    expect(impactoAvisoDescansoMedico([{ persona_id: "9", nombre: "Dora Gil", dias_calendario: 15 }], 15, 15).filas).toEqual([]);
  });
});

describe("qué parámetros tienen personas detrás", () => {
  it("la prueba y el aviso de descanso médico sí; el auto-cierre habla en palabras", () => {
    expect(fuenteDeImpacto("prueba_dias")).toBe("pruebas");
    expect(fuenteDeImpacto("descanso_medico_avisar_desde")).toBe("descanso_medico");
    expect(fuenteDeImpacto("auto_cierre_horas")).toBe("ninguna");
    expect(notaDeEfecto("auto_cierre_horas")).toMatch(/no reabre ni cambia/i);
    expect(notaDeEfecto("prueba_dias")).toBeNull();
  });
});

describe("los parámetros que rigen por fechas (0574)", () => {
  it("la fecha nace en hoy si la última versión ya pasó, o el día siguiente a ella si no", () => {
    expect(fechaInicialDeVigencia("2026-11-10", null)).toBe("2026-11-10");
    expect(fechaInicialDeVigencia("2026-11-10", "2026-10-01")).toBe("2026-11-10");
    expect(fechaInicialDeVigencia("2026-11-10", "2026-11-10")).toBe("2026-11-11");
    expect(fechaInicialDeVigencia("2026-11-10", "2026-12-31")).toBe("2027-01-01");
    expect(fechaInicialDeVigencia("2028-02-28", "2028-02-28")).toBe("2028-02-29");
  });

  it("nunca nace vacía: un campo de fecha que bloquea el envío no arranca en blanco", () => {
    for (const ultima of [null, "2020-01-01", "2026-11-10", "2030-06-15"]) {
      expect(fechaInicialDeVigencia("2026-11-10", ultima)).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    }
  });

  it("la fecha mínima es el día después de la última versión; sin versiones, no hay mínimo", () => {
    expect(fechaMinimaDeVigencia(null)).toBeNull();
    expect(fechaMinimaDeVigencia("2026-11-30")).toBe("2026-12-01");
  });

  it("se compara contra lo programado si hay un cambio programado, y si no contra lo de hoy", () => {
    expect(valorAntesDelCambio({ valor_actual: 30, proximo_valor: null })).toBe(30);
    expect(valorAntesDelCambio({ valor_actual: 30, proximo_valor: 24 })).toBe(24);
  });

  it("la vista previa dice a quién le toca, con su vínculo, y avisa que el monto lo calcula la planilla", () => {
    const i = impactoDeVistaPrevia(
      [{ persona: "Lab, Preprofesional", vinculo: "practicante preprofesional", detalle: "x" }],
      "30 horas",
      "24 horas desde el 01/02/2030",
    );
    expect(i.filas).toEqual([
      { persona: "Lab, Preprofesional (practicante preprofesional)", antes: "30 horas", despues: "24 horas desde el 01/02/2030" },
    ]);
    expect(i.nota).toMatch(/lo ya pagado no se toca/i);
    expect(impactoDeVistaPrevia([], "30 horas", "24 horas").filas).toEqual([]);
  });
});

describe("la lectura de lo que devuelve la base", () => {
  const cruda = {
    parametro: "prueba_dias", nombre: "Días", descripcion: "d", unidad: "días", clase: "operativo",
    tipo_valor: "entero", valor_min: "1", valor_max: 15, valor_defecto: "3", editable: true, base: null,
    valor_actual: "5", es_defecto: false, ultimo_cambio_at: null, ultimo_cambio_por: null, ultimo_motivo: null,
    ultimo_origen: null,
  };

  it("un numeric que llega como texto se vuelve número; un null se queda null", () => {
    const [f] = normalizarParametros([cruda, { ...cruda, parametro: "x", valor_min: null, valor_max: null }]);
    expect(f.valor_min).toBe(1);
    expect(f.valor_max).toBe(15);
    expect(f.valor_actual).toBe(5);
    expect(typeof f.valor_defecto).toBe("number");
    expect(normalizarParametros([{ ...cruda, valor_min: null }])[0].valor_min).toBeNull();
  });

  it("sin la 0574 en la base, la fila no rige por fechas y no inventa versiones", () => {
    const [f] = normalizarParametros([cruda]);
    expect(f.rige_por_fechas).toBe(false);
    expect(f.vigente_desde).toBeNull();
    expect(f.proximo_valor).toBeNull();
    expect(f.proximo_desde).toBeNull();
    expect(f.roles_cambia).toEqual([]);
  });

  it("con la 0574, las fechas y el próximo valor llegan, y el numeric como número", () => {
    const [f] = normalizarParametros([{ ...cruda, rige_por_fechas: true, vigente_desde: "2026-11-01",
      proximo_valor: "24", proximo_desde: "2026-12-01", roles_cambia: ["admin"] }]);
    expect(f.rige_por_fechas).toBe(true);
    expect(f.vigente_desde).toBe("2026-11-01");
    expect(f.proximo_valor).toBe(24);
    expect(f.proximo_desde).toBe("2026-12-01");
    expect(f.roles_cambia).toEqual(["admin"]);
  });

  it("un origen que no es ni «pantalla» ni «base» no se inventa", () => {
    expect(normalizarParametros([{ ...cruda, ultimo_origen: "otra cosa" }])[0].ultimo_origen).toBeNull();
    expect(normalizarParametros([{ ...cruda, ultimo_origen: "base" }])[0].ultimo_origen).toBe("base");
  });

  it("el historial: los números como número y el origen «base» se conserva; lo raro cae en «pantalla»", () => {
    const h = { id: "1", parametro: "p", nombre: "N", unidad: "días", editable: true, valor_anterior: "3", valor_nuevo: "5",
      motivo: "m", origen: "base", cambiado_por: null, cambiado_at: "2026-10-26T13:00:00Z" };
    const [a, b] = normalizarCambios([h, { ...h, origen: "rarísimo" }]);
    expect(a.valor_anterior).toBe(3);
    expect(a.origen).toBe("base");
    expect(a.cambiado_por).toBeNull();
    expect(b.origen).toBe("pantalla");
  });

  it("se reparte en lo que se cambia y lo que fija una norma, sin perder ninguno", () => {
    const filas = normalizarParametros([
      cruda,
      { ...cruda, parametro: "tope", editable: false, clase: "normativo" },
      { ...cruda, parametro: "otro" },
    ]);
    const { editables, fijos } = repartirParametros(filas);
    expect(editables.map((f) => f.parametro)).toEqual(["prueba_dias", "otro"]);
    expect(fijos.map((f) => f.parametro)).toEqual(["tope"]);
    expect(editables.length + fijos.length).toBe(filas.length);
  });
});

describe("el aviso y las fechas de un cambio de plata (0578)", () => {
  const periodos = [
    { fecha_ini: "2026-10-29", fecha_fin: "2026-11-28" },
    { fecha_ini: "2026-09-29", fecha_fin: "2026-10-28" },
  ];

  it("ofrece el inicio del ciclo actual, el del siguiente y hoy", () => {
    const o = opcionesDeVigencia("2026-10-31", periodos);
    expect(o.map((x: { clave: string; fecha: string }) => `${x.clave}:${x.fecha}`)).toEqual([
      "inicio_actual:2026-10-29",
      "inicio_siguiente:2026-11-29",
      "hoy:2026-10-31",
    ]);
  });

  it("si hoy no cae en ningún ciclo cargado, solo queda «desde hoy»", () => {
    const o = opcionesDeVigencia("2027-05-01", periodos);
    expect(o.map((x: { clave: string }) => x.clave)).toEqual(["hoy"]);
  });

  it("el aviso dice que es plata, qué módulos mueve, el historial, la demora y el comunicado", () => {
    const a = avisoDeCambioDePlata(opcionesDeVigencia("2026-10-31", periodos)[1]).join(" ");
    expect(a).toMatch(/maneja plata/);
    expect(a).toMatch(/Planilla/);
    expect(a).toMatch(/historial/);
    expect(a).toMatch(/tardan un momento/);
    expect(a).toMatch(/BORRADOR/);
    expect(a).toMatch(/ciclo siguiente/);
  });
});

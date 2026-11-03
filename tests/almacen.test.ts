// almacen.test.ts — piso o almacén, planificado por día (0579)
import { describe, expect, it } from "vitest";
import {
  PISO, almacenConLoReal, argumentosDeGuardado, esPiso, problemaDeTramos, puestoDesdeFilas, sugerirTramo, textoPuesto, tramosEnAlmacen,
} from "../apps/web/lib/admin/almacen";

describe("puestoDesdeFilas", () => {
  it("sin filas es piso; una fila sin horas es todo el turno; con horas, tramos en orden", () => {
    expect(puestoDesdeFilas([])).toEqual(PISO);
    expect(puestoDesdeFilas([{ desde: null, hasta: null }])).toEqual({ todoElTurno: true, tramos: [] });
    expect(puestoDesdeFilas([{ desde: "15:00:00", hasta: "16:30:00" }, { desde: "10:30:00", hasta: "12:00:00" }]))
      .toEqual({ todoElTurno: false, tramos: [{ desde: 10.5, hasta: 12 }, { desde: 15, hasta: 16.5 }] });
  });
});

describe("tramosEnAlmacen", () => {
  const turno = { desde: 8.5, hasta: 17 };
  it("todo el turno es el turno entero", () => {
    expect(tramosEnAlmacen({ todoElTurno: true, tramos: [] }, turno)).toEqual([turno]);
  });
  it("recorta lo que cruza el turno e ignora lo que cae fuera (el turno pudo cambiar después)", () => {
    const p = { todoElTurno: false, tramos: [{ desde: 7, hasta: 9 }, { desde: 18, hasta: 19 }] };
    expect(tramosEnAlmacen(p, turno)).toEqual([{ desde: 8.5, hasta: 9 }]);
  });
  it("piso no tiene tramos", () => {
    expect(tramosEnAlmacen(PISO, turno)).toEqual([]);
    expect(esPiso(PISO)).toBe(true);
  });
});

describe("textoPuesto — el mismo texto que fn_puesto_texto deja en el rastro", () => {
  it("dice Piso, Almacén todo el turno, o los tramos con guion largo", () => {
    expect(textoPuesto(PISO)).toBe("Piso");
    expect(textoPuesto({ todoElTurno: true, tramos: [] })).toBe("Almacén todo el turno");
    expect(textoPuesto({ todoElTurno: false, tramos: [{ desde: 10.5, hasta: 12 }, { desde: 15, hasta: 16.5 }] }))
      .toBe("Almacén 10:30–12:00, 15:00–16:30");
  });
});

describe("problemaDeTramos — las reglas que la 0579 también hace cumplir", () => {
  const turno = { desde: 8.5, hasta: 20.25 };
  it("acepta tramos en orden que se tocan pero no se cruzan", () => {
    expect(problemaDeTramos([{ desde: 10, hasta: 11 }, { desde: 11, hasta: 12 }], turno)).toBeNull();
  });
  it("rechaza tramos que se cruzan, que terminan antes de empezar, de más, o fuera del turno", () => {
    expect(problemaDeTramos([{ desde: 10, hasta: 12 }, { desde: 11.5, hasta: 13 }], turno)).toMatch(/se cruzan a las 11:30/);
    expect(problemaDeTramos([{ desde: 12, hasta: 11 }], turno)).toMatch(/termina antes de empezar/);
    expect(problemaDeTramos(Array.from({ length: 7 }, (_, i) => ({ desde: 9 + i, hasta: 9.5 + i })), turno)).toMatch(/máximo 6/);
    expect(problemaDeTramos([{ desde: 7, hasta: 9 }], turno)).toMatch(/fuera de su turno/);
    expect(problemaDeTramos([], turno)).toMatch(/al menos un tramo/);
  });
});

describe("argumentosDeGuardado", () => {
  it("todo el turno va sin tramos; los tramos van ordenados y en HH:MM", () => {
    expect(argumentosDeGuardado({ todoElTurno: true, tramos: [] })).toEqual({ p_todo_el_turno: true, p_tramos: [] });
    expect(argumentosDeGuardado({ todoElTurno: false, tramos: [{ desde: 15, hasta: 16.5 }, { desde: 10.5, hasta: 12 }] }))
      .toEqual({ p_todo_el_turno: false, p_tramos: [{ desde: "10:30", hasta: "12:00" }, { desde: "15:00", hasta: "16:30" }] });
    expect(argumentosDeGuardado(PISO)).toEqual({ p_todo_el_turno: false, p_tramos: [] });
  });
});

describe("sugerirTramo", () => {
  // Sin ella quedan 4 de 8 a 12, 2 de 12 a 14 y 5 de 14 en adelante; la meta es 3.
  const enPisoSinElla = (x: number) => (x < 12 ? 4 : x < 14 ? 2 : 5);
  const metaEn = () => 3;
  it("elige el tramo de más holgura donde el piso nunca queda bajo la meta", () => {
    expect(sugerirTramo({ turno: { desde: 8, hasta: 18 }, enPisoSinElla, metaEn })).toEqual({ desde: 14, hasta: 16 });
  });
  it("si empatan, el más temprano", () => {
    expect(sugerirTramo({ turno: { desde: 8, hasta: 12 }, enPisoSinElla, metaEn })).toEqual({ desde: 8, hasta: 10 });
  });
  it("si ningún tramo deja el piso con su meta, no sugiere nada", () => {
    expect(sugerirTramo({ turno: { desde: 12, hasta: 14 }, enPisoSinElla, metaEn })).toBeNull();
  });
  it("respeta el largo pedido y no se sale del turno", () => {
    const t = sugerirTramo({ turno: { desde: 14, hasta: 15 }, largo: 2, enPisoSinElla, metaEn });
    expect(t).toBeNull();
  });
});

describe("almacenConLoReal — Día: lo real hasta ahora y el plan después (2026-11-03)", () => {
  // Un martes cualquiera en Lima. Turno de 08:30 a 17:00.
  const medianocheIso = "2026-11-03T00:00:00-05:00";
  const a = (hhmm: string) => new Date(`2026-11-03T${hhmm}:00-05:00`);
  const iso = (hhmm: string) => a(hhmm).toISOString();
  const turno = { desde: 8.5, hasta: 17 };
  const sinMarcas = [] as const;

  it("un día que todavía no llega es solo el plan, y no hay nada marcado", () => {
    const r = almacenConLoReal({
      plan: [{ desde: 10.5, hasta: 12 }], cambios: [], marcajes: sinMarcas, medianocheIso, ahora: a("07:00"), turno,
    });
    expect(r.cobertura).toEqual([{ desde: 10.5, hasta: 12 }]);
    expect(r.marcado).toEqual([]);
  });

  it("si nadie marcó nada, el plan que ya empezó cuenta como pasado (lo mismo que el terminal)", () => {
    const r = almacenConLoReal({
      plan: [{ desde: 10.5, hasta: 12 }], cambios: [], marcajes: sinMarcas, medianocheIso, ahora: a("11:00"), turno,
    });
    expect(r.cobertura).toEqual([{ desde: 10.5, hasta: 12 }]);
  });

  it("un «Vuelvo a tienda» real corta el plan desde esa hora, y su resto no vuelve", () => {
    const r = almacenConLoReal({
      plan: [{ desde: 10.5, hasta: 12 }],
      cambios: [{ ubicacion: "tienda", timestamp: iso("11:15"), vuelvePrevisto: null }],
      marcajes: sinMarcas, medianocheIso, ahora: a("11:30"), turno,
    });
    expect(r.cobertura).toEqual([{ desde: 10.5, hasta: 11.25 }]);
  });

  it("un «Voy a almacén» real sin plan cuenta, y sigue hasta su vuelta prevista", () => {
    const r = almacenConLoReal({
      plan: [],
      cambios: [{ ubicacion: "almacen", timestamp: iso("14:00"), vuelvePrevisto: iso("15:00") }],
      marcajes: sinMarcas, medianocheIso, ahora: a("14:30"), turno,
    });
    expect(r.cobertura).toEqual([{ desde: 14, hasta: 15 }]);
    expect(r.marcado).toEqual([{ desde: 14, hasta: 14.5 }]); // lo marcado llega solo hasta ahora
  });

  it("«hasta que vuelva» sin vuelta se estira hasta el fin del turno; la salida final lo cierra", () => {
    const abierto = almacenConLoReal({
      plan: [],
      cambios: [{ ubicacion: "almacen", timestamp: iso("15:00"), vuelvePrevisto: null }],
      marcajes: sinMarcas, medianocheIso, ahora: a("15:30"), turno,
    });
    expect(abierto.cobertura).toEqual([{ desde: 15, hasta: 17 }]);
    const cerrado = almacenConLoReal({
      plan: [],
      cambios: [{ ubicacion: "almacen", timestamp: iso("15:00"), vuelvePrevisto: null }],
      marcajes: [{ tipo: "salida_final", timestamp: iso("16:00") }], medianocheIso, ahora: a("16:30"), turno,
    });
    expect(cerrado.cobertura).toEqual([{ desde: 15, hasta: 16 }]);
  });

  it("lo que empieza después de ahora es plan, junto a lo real de antes", () => {
    const r = almacenConLoReal({
      plan: [{ desde: 10.5, hasta: 12 }, { desde: 15, hasta: 16.5 }],
      cambios: [{ ubicacion: "tienda", timestamp: iso("11:00"), vuelvePrevisto: null }],
      marcajes: sinMarcas, medianocheIso, ahora: a("13:00"), turno,
    });
    expect(r.cobertura).toEqual([{ desde: 10.5, hasta: 11 }, { desde: 15, hasta: 16.5 }]);
  });

  it("todo se recorta a su turno, y lo que se toca se une", () => {
    const r = almacenConLoReal({
      plan: [{ desde: 16, hasta: 17 }],
      cambios: [{ ubicacion: "almacen", timestamp: iso("07:30"), vuelvePrevisto: iso("09:00") }],
      marcajes: sinMarcas, medianocheIso, ahora: a("12:00"), turno,
    });
    expect(r.cobertura).toEqual([{ desde: 8.5, hasta: 9 }, { desde: 16, hasta: 17 }]);
    expect(r.marcado).toEqual([{ desde: 7.5, hasta: 9 }]); // lo marcado se muestra tal cual, aunque cruce la entrada
  });
});

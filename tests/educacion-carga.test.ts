import { describe, it, expect } from "vitest";
import {
  NADA_TRAIDO, SIN_PISO, SIN_TECHO, TODA_LA_HISTORIA, constanciaDeFila, constanciasPorFamilia, familiaCompleta,
  filtroDelRango, mesCubierto, rangoCubierto, rangoDeLosFiltros, rangosQueFaltan, sumarConstancias, textoDelRango,
  todasLasPaginas, unirRangos, type FilaDeConstancia,
} from "@/lib/admin/educacion-carga";
import { FILTROS_VACIOS, mesLargo } from "@/lib/admin/educacion-meses";

// Las constancias de Educación se traen por meses (2026-10-17): lo que se pide, lo que se da por traído y
// cómo se lee cada fila. La pantalla y el hook solo arman las consultas; las decisiones viven acá.

function fila(over: Partial<FilaDeConstancia> = {}): FilaDeConstancia {
  return {
    id: "e1", asignacion_id: "a1", fecha_pago: "2026-09-15", tipo: "cuota_mensual", proxima_fecha_pago: null, nota: null,
    estado: "aprobada", origen: "colaboradora", enviada_at: "2026-09-16T00:00:00+00:00", revisada_at: "2026-09-18T00:00:00+00:00",
    retirada_at: null, motivo_categoria: null, motivo_comentario: null, reemplaza_a: null, aprobada_at: null,
    aprobacion_revertida_at: null, asignacion: { familia_id: "f1" }, archivos: [], meses: [],
    enviador: { nombres: "Sandra", apellidos: "Ramírez" }, revisor: { nombres: "Felipe", apellidos: "Álvarez" },
    aprobador: null, revertidor: null, correcciones: [],
    ...over,
  };
}

describe("tramos de meses", () => {
  it("unirRangos junta los que se solapan y los que se tocan", () => {
    expect(unirRangos([
      { desde: "2026-07", hasta: "2026-12" }, { desde: "2026-01", hasta: "2026-06" }, { desde: "2025-03", hasta: "2025-04" },
    ])).toEqual([{ desde: "2025-03", hasta: "2025-04" }, { desde: "2026-01", hasta: "2026-12" }]);
  });

  it("rangosQueFaltan pide solo lo que no está: nada si ya está todo, los huecos si hay huecos", () => {
    const traidos = [{ desde: "2026-01", hasta: "2026-06" }, { desde: "2026-09", hasta: "2026-12" }];
    expect(rangosQueFaltan(traidos, { desde: "2026-02", hasta: "2026-05" })).toEqual([]);
    expect(rangosQueFaltan(traidos, { desde: "2025-11", hasta: "2026-10" })).toEqual([
      { desde: "2025-11", hasta: "2025-12" }, { desde: "2026-07", hasta: "2026-08" },
    ]);
    expect(rangosQueFaltan([], { desde: "2026-07", hasta: "2026-12" })).toEqual([{ desde: "2026-07", hasta: "2026-12" }]);
  });

  it("la historia entera, con meses ya traídos en el medio, pide solo los dos bordes abiertos", () => {
    expect(rangosQueFaltan([{ desde: "2025-05", hasta: "2026-12" }], TODA_LA_HISTORIA)).toEqual([
      { desde: SIN_PISO, hasta: "2025-04" }, { desde: "2027-01", hasta: SIN_TECHO },
    ]);
    expect(rangoCubierto([TODA_LA_HISTORIA], { desde: "2019-01", hasta: "2031-12" })).toBe(true);
  });

  it("un extremo abierto no se rompe al sumarle un mes («10000-01» iría antes que «9999-12»)", () => {
    expect(unirRangos([{ desde: "2026-01", hasta: SIN_TECHO }, { desde: "2027-05", hasta: "2027-06" }]))
      .toEqual([{ desde: "2026-01", hasta: SIN_TECHO }]);
    expect(mesCubierto([{ desde: "2026-01", hasta: SIN_TECHO }], "2040-01")).toBe(true);
  });
});

describe("qué meses necesita cada filtro", () => {
  const f = (over: Partial<typeof FILTROS_VACIOS>) => ({ ...FILTROS_VACIOS, ...over });

  it("sin filtros que miren constancias, ninguno", () => {
    expect(rangoDeLosFiltros(f({ sede: "AQP", estado: "vencida" }))).toBeNull();
  });

  it("el mes del pago, ese mes; el rango libre, sus meses, abierto del lado que no se puso", () => {
    expect(rangoDeLosFiltros(f({ mes: "2025-08" }))).toEqual({ desde: "2025-08", hasta: "2025-08" });
    expect(rangoDeLosFiltros(f({ desde: "2026-02-10", hasta: "2026-04-01" }))).toEqual({ desde: "2026-02", hasta: "2026-04" });
    expect(rangoDeLosFiltros(f({ desde: "2026-02-10" }))).toEqual({ desde: "2026-02", hasta: SIN_TECHO });
  });

  it("«matrícula» o «quién revisó» sin fecha miran toda la historia; con mes, solo ese mes", () => {
    expect(rangoDeLosFiltros(f({ tipo: "matricula" }))).toEqual(TODA_LA_HISTORIA);
    expect(rangoDeLosFiltros(f({ revisor: "Felipe Álvarez" }))).toEqual(TODA_LA_HISTORIA);
    expect(rangoDeLosFiltros(f({ tipo: "matricula", mes: "2025-05" }))).toEqual({ desde: "2025-05", hasta: "2025-05" });
  });
});

describe("filtroDelRango — las pagadas en el tramo O las adelantadas que lo cubren", () => {
  it("un tramo cerrado", () => {
    expect(filtroDelRango({ desde: "2026-07", hasta: "2026-12" })).toBe(
      "and(fecha_pago.gte.2026-07-01,fecha_pago.lt.2027-01-01),and(cubre_hasta.gte.2026-07-01,cubre_desde.lte.2026-12-01)");
  });

  it("abierto por un lado, solo pone el otro", () => {
    expect(filtroDelRango({ desde: SIN_PISO, hasta: "2025-04" }))
      .toBe("and(fecha_pago.lt.2025-05-01),and(cubre_desde.lte.2025-04-01)");
    expect(filtroDelRango({ desde: "2027-01", hasta: SIN_TECHO }))
      .toBe("and(fecha_pago.gte.2027-01-01),and(cubre_hasta.gte.2027-01-01)");
  });

  it("toda la historia no lleva filtro", () => {
    expect(filtroDelRango(TODA_LA_HISTORIA)).toBeNull();
  });
});

describe("una fila de la tabla se lee como `fn_educacion_entregas`", () => {
  it("nombres «Nombres Apellidos», archivos por orden e id, y la familia del estudio", () => {
    const { entrega } = constanciaDeFila(fila({
      archivos: [
        { id: "b", storage_path: "x/2.pdf", nombre: "dos.pdf", tipo_mime: "application/pdf", bytes: 2, orden: 2 },
        { id: "z", storage_path: "x/1b.pdf", nombre: "uno-b.pdf", tipo_mime: null, bytes: null, orden: 1 },
        { id: "a", storage_path: "x/1a.pdf", nombre: "uno-a.pdf", tipo_mime: null, bytes: null, orden: 1 },
      ],
    }));
    expect(entrega.familia_id).toBe("f1");
    expect(entrega.enviada_por).toBe("Sandra Ramírez");
    expect(entrega.revisada_por).toBe("Felipe Álvarez");
    expect(entrega.archivos.map((a) => a.id)).toEqual(["a", "z", "b"]);
    expect(entrega.archivos[0]).toEqual({ id: "a", ruta: "x/1a.pdf", nombre: "uno-a.pdf", tipo_mime: null, bytes: null });
  });

  it("una aprobación revertida trae quién aprobó y quién revirtió (0525)", () => {
    const { entrega } = constanciaDeFila(fila({
      estado: "rechazada", aprobada_at: "2026-09-18T00:00:00+00:00", aprobacion_revertida_at: "2026-09-20T00:00:00+00:00",
      aprobador: { nombres: "Ana", apellidos: "Paz" }, revertidor: { nombres: "Luis", apellidos: "Mora" },
    }));
    expect(entrega.aprobada_por).toBe("Ana Paz");
    expect(entrega.revertida_at).toBe("2026-09-20T00:00:00+00:00");
    expect(entrega.revertida_por).toBe("Luis Mora");
  });

  it("una adelantada trae sus meses cubiertos, en orden y con su monto como número", () => {
    const { meses } = constanciaDeFila(fila({
      id: "ad", meses: [
        { mes: "2026-09-01", monto: 80, origen: "calculado", motivo: null },
        { mes: "2026-08-01", monto: "80.00" as unknown as number, origen: "calculado", motivo: null },
      ],
    }));
    expect(meses.map((m) => m.mes)).toEqual(["2026-08-01", "2026-09-01"]);
    expect(meses[0]).toEqual({ entrega_id: "ad", familia_id: "f1", mes: "2026-08-01", monto: 80, origen: "calculado", motivo: null });
  });

  it("una rechazada está «corregida» si otra constancia no retirada dice reemplazarla", () => {
    expect(constanciaDeFila(fila({ estado: "rechazada", correcciones: [{ estado: "pendiente" }] })).corregida).toBe(true);
    expect(constanciaDeFila(fila({ estado: "rechazada", correcciones: [{ estado: "retirada" }] })).corregida).toBe(false);
    expect(constanciaDeFila(fila({ estado: "rechazada", correcciones: [] })).corregida).toBe(false);
  });
});

describe("lo ya traído", () => {
  it("suma tramos, y una constancia que vuelve a llegar reemplaza a la vieja (alguien la aprobó entre medio)", () => {
    let t = sumarConstancias(NADA_TRAIDO, [fila({ id: "x", estado: "pendiente", revisada_at: null, revisor: null })], { rango: { desde: "2026-07", hasta: "2026-12" } });
    t = sumarConstancias(t, [fila({ id: "y", fecha_pago: "2026-03-15" })], { rango: { desde: "2026-01", hasta: "2026-06" } });
    expect(t.rangos).toEqual([{ desde: "2026-01", hasta: "2026-12" }]);
    t = sumarConstancias(t, [fila({ id: "x", estado: "aprobada" })], { rango: { desde: "2026-07", hasta: "2026-12" } });
    expect(t.entregas.size).toBe(2);
    expect(t.entregas.get("x")?.estado).toBe("aprobada");
  });

  it("por estudio, en el orden de `fn_educacion_entregas`: pago más reciente primero", () => {
    const t = sumarConstancias(NADA_TRAIDO, [
      fila({ id: "a", fecha_pago: "2026-08-15" }), fila({ id: "b", fecha_pago: "2026-09-15" }),
      fila({ id: "c", fecha_pago: "2026-09-15", asignacion: { familia_id: "f2" } }),
    ], {});
    const p = constanciasPorFamilia(t);
    expect(p.get("f1")?.map((e) => e.id)).toEqual(["b", "a"]);
    expect(p.get("f2")?.map((e) => e.id)).toEqual(["c"]);
  });

  it("la historia de un estudio está completa si se pidió para el visor, o si ya se trajo toda la historia", () => {
    expect(familiaCompleta(sumarConstancias(NADA_TRAIDO, [], { familias: ["f1"] }), "f1")).toBe(true);
    expect(familiaCompleta(sumarConstancias(NADA_TRAIDO, [], { rango: { desde: "2026-01", hasta: "2026-12" } }), "f1")).toBe(false);
    expect(familiaCompleta(sumarConstancias(NADA_TRAIDO, [], { rango: TODA_LA_HISTORIA }), "f1")).toBe(true);
  });

  it("los meses cubiertos y las correcciones se ponen al día con cada fila", () => {
    let t = sumarConstancias(NADA_TRAIDO, [fila({ id: "r", estado: "rechazada", correcciones: [{ estado: "pendiente" }] })], {});
    expect(t.corregidas.has("r")).toBe(true);
    t = sumarConstancias(t, [fila({ id: "r", estado: "rechazada", correcciones: [{ estado: "retirada" }] })], {});
    expect(t.corregidas.has("r")).toBe(false);
  });

  it("textoDelRango dice qué no se pudo traer", () => {
    expect(textoDelRango({ desde: "2026-01", hasta: "2026-06" }, mesLargo)).toBe("ene 2026 a jun 2026");
    expect(textoDelRango({ desde: SIN_PISO, hasta: "2025-04" }, mesLargo)).toBe("hasta abr 2025");
    expect(textoDelRango(TODA_LA_HISTORIA, mesLargo)).toBe("toda la historia");
  });
});

describe("todasLasPaginas — PostgREST corta en `max_rows` sin avisar", () => {
  // Una tabla de 1 077 filas detrás de un servidor que nunca devuelve más de `tope` por respuesta.
  const servidor = (total: number, tope: number) => {
    const pedidos: [number, number][] = [];
    const pedir = (desde: number, hasta: number) => {
      pedidos.push([desde, hasta]);
      const fin = Math.min(hasta + 1, desde + tope, total);
      const data = Array.from({ length: Math.max(0, fin - desde) }, (_, i) => desde + i);
      return Promise.resolve({ data, error: null, count: desde === 0 ? total : null });
    };
    return { pedir, pedidos };
  };

  it("trae las 1 077, no las primeras 1 000", async () => {
    const s = servidor(1077, 1000);
    const filas = await todasLasPaginas(s.pedir);
    expect(filas).toHaveLength(1077);
    expect(s.pedidos).toEqual([[0, 999], [1000, 1999]]);
  });

  it("aunque el servidor corte en menos que una página (el conteo lo nota)", async () => {
    const s = servidor(1077, 500);
    expect(await todasLasPaginas(s.pedir)).toHaveLength(1077);
  });

  it("una página que falla es «no se sabe» (null), nunca «no hay»", async () => {
    let n = 0;
    const filas = await todasLasPaginas((d) => {
      n += 1;
      return Promise.resolve(n === 1
        ? { data: Array.from({ length: 1000 }, (_, i) => d + i), error: null, count: 1500 }
        : { data: null, error: { message: "se cayó" }, count: null });
    });
    expect(filas).toBeNull();
  });

  it("una sola página corta es una sola petición", async () => {
    const s = servidor(348, 1000);
    expect(await todasLasPaginas(s.pedir)).toHaveLength(348);
    expect(s.pedidos).toHaveLength(1);
  });
});

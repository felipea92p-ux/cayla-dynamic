import { describe, it, expect } from "vitest";
import {
  agruparEstudios, casillasDeEstudio, conteoTarjetas, entregasEnOrden, FILTROS_VACIOS, filtrosAUrl, filtrosDeUrl,
  finTrasUnPaso, hayFiltros, limitesDeLaLinea, mesDe, mesesConConstancia, mesesConDatosDeLaVentana, mesesDeLaLinea,
  montoMensual, pasaFiltros, resumenPorSede, sedesDe, sumarMeses, ventanaDeMeses, ventanaParaFiltros,
  type ContextoDeFiltros, type Filtros,
} from "@/lib/admin/educacion-meses";
import { estadoParaMostrar, grupoDeEstudio } from "@/lib/admin/educacion-grupos";
import type { EntregaDeFamilia, Situacion } from "@/lib/admin/educacion-tipos";

const HOY = "2026-10-16";

function sit(over: Partial<Situacion> = {}): Situacion {
  return {
    familia_id: "f1", asignacion_id: "a1", persona_id: "p1", persona: "Sandra Ramírez", sede: "AQP", rango: "support",
    institucion: "Duolingo", beneficiario: "trabajador", beneficiario_nombre: null, monto: 100,
    vigente_desde: "2026-08-01", vigente_hasta: "2026-12-31", vigencia: "vigente", paga: true,
    frecuencia_pago: "mensual", proxima_fecha_pago: "2026-10-30", dias_para_pago: 14, pago_proximo: false,
    estado_constancia: "al_dia", fecha_pago_constancia: null, plazo: null, dias_para_plazo: null,
    entrega_id: null, entrega_estado: null, entrega_enviada_at: null, entrega_archivos: null,
    aprobadas: 1, aviso_fin_id: null, aviso_fin_motivo: null,
    ...over,
  };
}

function ent(over: Partial<EntregaDeFamilia> = {}): EntregaDeFamilia {
  return {
    id: "e1", familia_id: "f1", asignacion_id: "a1", fecha_pago: "2026-09-30", tipo: "cuota_mensual",
    proxima_fecha_pago: null, nota: null, estado: "aprobada", origen: "colaboradora",
    enviada_at: "2026-09-30T15:00:00Z", enviada_por: null, revisada_at: null, revisada_por: "Felipe",
    retirada_at: null, motivo_categoria: null, motivo_comentario: null, reemplaza_a: null, archivos: [],
    aprobada_at: null, aprobada_por: null, revertida_at: null, revertida_por: null,
    ...over,
  };
}

const ctx = (over: Partial<ContextoDeFiltros> = {}): ContextoDeFiltros => ({
  liquidadas: new Set(), familiasConPendiente: new Set(), entregasPorFamilia: null, familiasSinLeer: new Set(), personaPedida: null, ...over,
});
const filtros = (over: Partial<Filtros> = {}): Filtros => ({ ...FILTROS_VACIOS, ...over });

describe("meses", () => {
  it("mesDe y sumarMeses cruzan el cambio de año", () => {
    expect(mesDe("2026-09-30")).toBe("2026-09");
    expect(sumarMeses("2026-11", 3)).toBe("2027-02");
    expect(sumarMeses("2026-01", -1)).toBe("2025-12");
    expect(sumarMeses("2026-10", 0)).toBe("2026-10");
  });

  it("la ventana termina en el mes de hoy y mira seis meses atrás", () => {
    const v = ventanaDeMeses(HOY, ["2026-01", "2026-09"], 6);
    expect(v.meses).toEqual(["2026-05", "2026-06", "2026-07", "2026-08", "2026-09", "2026-10"]);
    expect(v.hayMas).toBe(true);
  });

  it("no dibuja meses anteriores al primero con datos, y avisa que no hay más", () => {
    const v = ventanaDeMeses(HOY, ["2026-08"], 6);
    expect(v.meses).toEqual(["2026-08", "2026-09", "2026-10"]);
    expect(v.hayMas).toBe(false);
  });

  it("nunca dibuja menos de tres columnas, aunque todo sea de este mes", () => {
    const v = ventanaDeMeses(HOY, [], 6);
    expect(v.meses).toEqual(["2026-08", "2026-09", "2026-10"]);
    expect(v.hayMas).toBe(false);
  });

  it("si alguien ya envió el pago del mes que viene, no se esconde a la derecha", () => {
    const v = ventanaDeMeses(HOY, ["2026-07", "2026-11"], 6);
    expect(v.meses.at(-1)).toBe("2026-11");
  });

  it("«ver más» suma meses hacia atrás hasta el primero con datos", () => {
    const datos = ["2026-01", "2026-09"];
    expect(ventanaDeMeses(HOY, datos, 12).meses[0]).toBe("2026-01");
    expect(ventanaDeMeses(HOY, datos, 12).hayMas).toBe(false);
  });
});

describe("la ventana se mueve hacia atrás y hacia adelante (Felipe, 2026-10-17)", () => {
  // Datos de mayo-2025 a octubre-2026, y un adelantado que cubre hasta diciembre-2026.
  const datos = ["2025-05", "2026-10", "2026-12"];
  const cols = (v: { meses: string[] }) => `${v.meses[0]} → ${v.meses.at(-1)}`;

  it("al abrir termina en el último mes con datos y dice que hay meses anteriores, no siguientes", () => {
    const v = ventanaDeMeses(HOY, datos, 6);
    expect(cols(v)).toBe("2026-07 → 2026-12");
    expect(v.hayMas).toBe(true);
    expect(v.haySiguientes).toBe(false);
  });

  it("«← Meses anteriores» retrocede seis, y «Meses siguientes →» vuelve exactamente a donde estaba", () => {
    const abierta = ventanaDeMeses(HOY, datos, 6);
    const atras = ventanaDeMeses(HOY, datos, 6, finTrasUnPaso(abierta, -1));
    expect(cols(atras)).toBe("2026-01 → 2026-06");
    expect(atras.haySiguientes).toBe(true);
    const deVuelta = ventanaDeMeses(HOY, datos, 6, finTrasUnPaso(atras, 1));
    expect(deVuelta.meses).toEqual(abierta.meses);
    expect(deVuelta.haySiguientes).toBe(false);
  });

  it("al chocar con el primer mes con datos se corre a la derecha en vez de achicarse, y apaga «anteriores»", () => {
    const v = ventanaDeMeses(HOY, datos, 6, "2025-07");
    expect(cols(v)).toBe("2025-05 → 2025-10");
    expect(v.meses).toHaveLength(6);
    expect(v.hayMas).toBe(false);
    expect(v.haySiguientes).toBe(true);
  });

  it("nunca pasa del último mes con datos, aunque se pida más allá", () => {
    const v = ventanaDeMeses(HOY, datos, 6, "2027-08");
    expect(v.meses.at(-1)).toBe("2026-12");
    expect(v.haySiguientes).toBe(false);
  });

  it("un adelantado que cubre muy lejos no saca el mes de hoy de la ventana al abrir: se llega con «siguientes»", () => {
    const v = ventanaDeMeses(HOY, ["2026-01", "2027-09"], 6);
    expect(v.meses).toContain("2026-10");
    expect(cols(v)).toBe("2026-10 → 2027-03");
    expect(v.haySiguientes).toBe(true);
    expect(ventanaDeMeses(HOY, ["2026-01", "2027-09"], 6, finTrasUnPaso(v, 1)).meses.at(-1)).toBe("2027-09");
  });

  it("un filtro de fecha mueve la ventana hasta su mes; si después se toca un botón, manda el botón", () => {
    const conFiltro = ventanaParaFiltros(HOY, datos, 6, { mes: "2025-08", desde: "" });
    expect(cols(conFiltro)).toBe("2025-08 → 2026-01");
    const tocada = ventanaParaFiltros(HOY, datos, 6, { mes: "2025-08", desde: "" }, finTrasUnPaso(conFiltro, 1));
    expect(cols(tocada)).toBe("2026-02 → 2026-07");
  });

  it("«Mes del pago» ofrece todos los meses de la línea de tiempo, del más reciente al más antiguo", () => {
    expect(limitesDeLaLinea(HOY, datos)).toEqual({ primero: "2025-05", ultimo: "2026-12" });
    const m = mesesDeLaLinea(HOY, datos);
    expect(m[0]).toBe("2026-12");
    expect(m.at(-1)).toBe("2025-05");
    expect(m).toHaveLength(20);
  });
});

describe("agruparEstudios — una fila por persona e institución", () => {
  const dos = [
    sit({ familia_id: "f1", vigente_desde: "2026-08-01", vigente_hasta: "2026-08-28", vigencia: "terminada", estado_constancia: "sin_calendario", aprobadas: 1 }),
    sit({ familia_id: "f2", vigente_desde: "2026-08-29", vigente_hasta: "2026-09-28", vigencia: "terminada", estado_constancia: "al_dia", aprobadas: 1, monto: 104.25 }),
  ];

  it("el mismo Duolingo registrado dos veces es UNA línea con los dos tramos", () => {
    const e = agruparEstudios(dos);
    expect(e).toHaveLength(1);
    expect(e[0].tramos.map((t) => t.familia_id)).toEqual(["f1", "f2"]);
    // Los dos terminaron: cuentan las constancias del tramo que habla por la fila, no la suma.
    expect(e[0].aprobadas).toBe(1);
    expect(e[0].desde).toBe("2026-08-01");
    expect(e[0].hasta).toBe("2026-09-28");
  });

  it("si todos terminaron, habla por la fila el que terminó más tarde", () => {
    expect(agruparEstudios(dos)[0].actual.familia_id).toBe("f2");
  });

  it("entre los que siguen en curso, habla el de estado más urgente: un problema no se esconde tras un «al día»", () => {
    const e = agruparEstudios([
      sit({ familia_id: "f1", estado_constancia: "vencida" }),
      sit({ familia_id: "f2", estado_constancia: "al_dia" }),
    ]);
    expect(e).toHaveLength(1);
    expect(e[0].estado_constancia).toBe("vencida");
  });

  it("dos instituciones distintas de la misma persona son dos filas", () => {
    const e = agruparEstudios([sit({ familia_id: "f1" }), sit({ familia_id: "f2", institucion: "Instituto San Ignacio" })]);
    expect(e).toHaveLength(2);
  });

  it("el estudio de la persona y el de su hijo en la MISMA institución no se mezclan", () => {
    const e = agruparEstudios([
      sit({ familia_id: "f1" }),
      sit({ familia_id: "f2", beneficiario: "hijo", beneficiario_nombre: "Lucas" }),
    ]);
    expect(e).toHaveLength(2);
  });

  it("no distingue mayúsculas, acentos ni espacios de más al comparar la institución", () => {
    const e = agruparEstudios([sit({ familia_id: "f1", institucion: "Instituto  San Ignacio" }), sit({ familia_id: "f2", institucion: "instituto san ignácio " })]);
    expect(e).toHaveLength(1);
  });

  it("lo que pide acción va primero", () => {
    const e = agruparEstudios([
      sit({ persona_id: "p2", persona: "Ana", familia_id: "f9", estado_constancia: "al_dia" }),
      sit({ persona_id: "p3", persona: "Zoe", familia_id: "f8", estado_constancia: "vencida" }),
    ]);
    expect(e.map((x) => x.persona)).toEqual(["Zoe", "Ana"]);
  });
});

describe("montoMensual — dice lo mismo que la planilla", () => {
  it("suma los tramos que se pagan hoy", () => {
    const [e] = agruparEstudios([sit({ familia_id: "f1", monto: 100 }), sit({ familia_id: "f2", monto: 40 })]);
    expect(montoMensual(e, HOY)).toEqual({ monto: 140, seEstaPagando: true });
  });

  it("un tramo que todavía no empieza no suma", () => {
    const [e] = agruparEstudios([sit({ monto: 100 }), sit({ familia_id: "f2", monto: 40, vigente_desde: "2026-11-01" })]);
    expect(montoMensual(e, HOY).monto).toBe(100);
  });

  it("si nada se paga, muestra el monto del tramo que habla, no S/ 0.00", () => {
    const [e] = agruparEstudios([sit({ monto: 80, paga: false })]);
    expect(montoMensual(e, HOY)).toEqual({ monto: 80, seEstaPagando: false });
  });
});

describe("casillasDeEstudio — la constancia de cada mes", () => {
  const [estudio] = agruparEstudios([sit({ vigente_desde: "2026-08-01", vigente_hasta: "2026-12-31" })]);
  const meses = ["2026-07", "2026-08", "2026-09", "2026-10"];

  it("un mes sin constancia es «vacía» y NUNCA una falta", () => {
    const c = casillasDeEstudio(estudio, [ent({ fecha_pago: "2026-09-30" })], meses);
    expect(c.map((x) => x.estado)).toEqual(["vacia", "vacia", "aprobada", "vacia"]);
  });

  it("distingue «aún no existía» de «vigente sin constancia» — un hecho de fechas, no una falta", () => {
    const c = casillasDeEstudio(estudio, [], meses);
    expect(c[0].fueraDeVigencia).toBe(true);
    expect(c[1].fueraDeVigencia).toBe(false);
    expect(c[3].fueraDeVigencia).toBe(false);
  });

  it("si hay una pendiente y una rechazada anterior, habla la pendiente", () => {
    const c = casillasDeEstudio(estudio, [
      ent({ id: "a", estado: "rechazada", enviada_at: "2026-09-01T10:00:00Z" }),
      ent({ id: "b", estado: "pendiente", enviada_at: "2026-09-05T10:00:00Z" }),
    ], meses);
    expect(c[2].estado).toBe("pendiente");
    expect(c[2].otras).toBe(1);
  });

  it("una aprobada manda sobre una rechazada del mismo mes", () => {
    const c = casillasDeEstudio(estudio, [
      ent({ id: "a", estado: "rechazada" }),
      ent({ id: "b", estado: "aprobada", enviada_at: "2026-10-02T10:00:00Z" }),
    ], meses);
    expect(c[2].estado).toBe("aprobada");
    expect(c[2].principal?.id).toBe("b");
  });

  it("una constancia retirada no cuenta como recibida", () => {
    const c = casillasDeEstudio(estudio, [ent({ estado: "retirada" })], meses);
    expect(c[2].estado).toBe("vacia");
  });

  it("entregasEnOrden las recorre por mes de pago y luego por envío, retiradas incluidas", () => {
    const orden = entregasEnOrden([
      ent({ id: "c", fecha_pago: "2026-10-01" }),
      ent({ id: "a", fecha_pago: "2026-08-30", enviada_at: "2026-08-30T10:00:00Z" }),
      ent({ id: "b", fecha_pago: "2026-08-30", enviada_at: "2026-09-02T00:00:00Z", estado: "retirada" }),
    ]);
    expect(orden.map((x) => x.id)).toEqual(["a", "b", "c"]);
  });

  it("mesesConConstancia ignora las retiradas", () => {
    expect(mesesConConstancia([ent({ fecha_pago: "2026-09-30" }), ent({ id: "x", fecha_pago: "2026-05-30", estado: "retirada" })])).toEqual(["2026-09"]);
  });
});

describe("pasaFiltros", () => {
  const e = agruparEstudios([sit()])[0];
  const mapa = (...es: EntregaDeFamilia[]) => new Map([["f1", es]]);

  it("sin filtros pasa", () => {
    expect(pasaFiltros(e, filtros(), ctx())).toBe(true);
  });

  it("la sede filtra, y se puede ignorar para contar cada chip de sede", () => {
    expect(pasaFiltros(e, filtros({ sede: "LIM" }), ctx())).toBe(false);
    expect(pasaFiltros(e, filtros({ sede: "LIM" }), ctx(), ["sede"])).toBe(true);
  });

  it("los terminados salen por defecto («Estado del apoyo» arranca en «Todos») y no con «vigentes»", () => {
    const t = agruparEstudios([sit({ vigencia: "terminada" })])[0];
    expect(pasaFiltros(t, filtros(), ctx())).toBe(true);
    expect(pasaFiltros(t, filtros({ vigencia: "activas" }), ctx())).toBe(false);
  });

  it("las personas ya liquidadas se ocultan salvo que se pidan", () => {
    expect(pasaFiltros(e, filtros(), ctx({ liquidadas: new Set(["p1"]) }))).toBe(false);
    expect(pasaFiltros(e, filtros({ liquidadas: true }), ctx({ liquidadas: new Set(["p1"]) }))).toBe(true);
  });

  it("?persona= manda sobre todos los demás filtros", () => {
    expect(pasaFiltros(e, filtros({ sede: "LIM", estado: "vencida" }), ctx({ personaPedida: "p1" }))).toBe(true);
    expect(pasaFiltros(e, filtros(), ctx({ personaPedida: "p2" }))).toBe(false);
  });

  it("busca por nombre sin importar acentos ni mayúsculas", () => {
    expect(pasaFiltros(e, filtros({ buscar: "ramirez" }), ctx())).toBe(true);
    expect(pasaFiltros(e, filtros({ buscar: "RAMÍR" }), ctx())).toBe(true);
    expect(pasaFiltros(e, filtros({ buscar: "lopez" }), ctx())).toBe(false);
  });

  it("«quién estudia» separa a la persona de su hijo", () => {
    const hijo = agruparEstudios([sit({ beneficiario: "hijo", beneficiario_nombre: "Lucas" })])[0];
    expect(pasaFiltros(hijo, filtros({ quien: "hijo" }), ctx())).toBe(true);
    expect(pasaFiltros(hijo, filtros({ quien: "trabajador" }), ctx())).toBe(false);
    expect(pasaFiltros(e, filtros({ quien: "trabajador" }), ctx())).toBe(true);
  });

  it("mes, tipo, revisor y rango miran las constancias", () => {
    const m = mapa(ent({ fecha_pago: "2026-09-30", tipo: "matricula", revisada_por: "Ana" }));
    const c = ctx({ entregasPorFamilia: m });
    expect(pasaFiltros(e, filtros({ mes: "2026-09" }), c)).toBe(true);
    expect(pasaFiltros(e, filtros({ mes: "2026-08" }), c)).toBe(false);
    expect(pasaFiltros(e, filtros({ tipo: "matricula" }), c)).toBe(true);
    expect(pasaFiltros(e, filtros({ tipo: "cuota_mensual" }), c)).toBe(false);
    expect(pasaFiltros(e, filtros({ revisor: "Ana" }), c)).toBe(true);
    expect(pasaFiltros(e, filtros({ revisor: "Beto" }), c)).toBe(false);
    expect(pasaFiltros(e, filtros({ desde: "2026-09-01", hasta: "2026-09-30" }), c)).toBe(true);
    expect(pasaFiltros(e, filtros({ desde: "2026-10-01" }), c)).toBe(false);
  });

  it("un rango pide que UNA misma constancia caiga adentro, no una antes y otra después", () => {
    const m = mapa(ent({ id: "a", fecha_pago: "2026-08-30" }), ent({ id: "b", fecha_pago: "2026-10-30" }));
    expect(pasaFiltros(e, filtros({ desde: "2026-09-01", hasta: "2026-10-01" }), ctx({ entregasPorFamilia: m }))).toBe(false);
  });

  it("mientras las constancias no llegan, esos filtros no esconden a nadie", () => {
    expect(pasaFiltros(e, filtros({ mes: "2026-01", tipo: "matricula", revisor: "X" }), ctx({ entregasPorFamilia: null }))).toBe(true);
  });

  it("las tarjetas filtran por el estado del estudio", () => {
    const v = agruparEstudios([sit({ estado_constancia: "vencida" })])[0];
    expect(pasaFiltros(v, filtros({ tarjeta: "vencidas" }), ctx())).toBe(true);
    expect(pasaFiltros(e, filtros({ tarjeta: "vencidas" }), ctx())).toBe(false);
    expect(pasaFiltros(e, filtros({ tarjeta: "pendientes" }), ctx({ familiasConPendiente: new Set(["f1"]) }))).toBe(true);
  });

  it("la pestaña «Al día» exige aprobadas, igual que siempre", () => {
    const nuevo = agruparEstudios([sit({ aprobadas: 0 })])[0];
    expect(pasaFiltros(nuevo, filtros({ grupo: "al_dia" }), ctx())).toBe(false);
    expect(pasaFiltros(e, filtros({ grupo: "al_dia" }), ctx())).toBe(true);
  });

  it("hayFiltros distingue lo de siempre de un filtro puesto", () => {
    expect(hayFiltros(filtros())).toBe(false);
    expect(hayFiltros(filtros({ sede: "AQP" }))).toBe(true);
    expect(hayFiltros(filtros({ vigencia: "activas" }))).toBe(true);
  });
});

describe("tarjetas y sedes cuentan lo mismo que se dibuja", () => {
  const estudios = agruparEstudios([
    sit({ familia_id: "f1", persona_id: "p1", persona: "Ana", sede: "AQP", monto: 100, estado_constancia: "vencida" }),
    sit({ familia_id: "f2", persona_id: "p2", persona: "Beto", sede: "LIM", monto: 60, estado_constancia: "pendiente_revision" }),
    sit({ familia_id: "f3", persona_id: "p3", persona: "Carla", sede: "AQP", monto: 40, estado_constancia: "al_dia", paga: false }),
  ]);
  const pend = new Set(["f2"]);

  it("conteoTarjetas", () => {
    const c = conteoTarjetas(estudios, pend);
    expect(c.vencidas).toBe(1);
    expect(c.pendientes).toBe(1);
    expect(c.rechazadas).toBe(0);
  });

  it("resumenPorSede suma solo lo que se paga hoy y ordena de la A a la Z", () => {
    const r = resumenPorSede(estudios, HOY, pend);
    expect(r.map((x) => x.sede)).toEqual(["AQP", "LIM"]);
    expect(r[0]).toMatchObject({ personas: 2, pagando: 1, montoMensual: 100, vencidas: 1, porRevisar: 0 });
    expect(r[1]).toMatchObject({ personas: 1, pagando: 1, montoMensual: 60, porRevisar: 1 });
  });

  it("las sedes salen de los datos", () => {
    expect(sedesDe(estudios)).toEqual(["AQP", "LIM"]);
  });
});

describe("el enlace reproduce la pantalla", () => {
  const params = (q: string) => new URLSearchParams(q);

  it("ida y vuelta de lo que define el conjunto que se mira", () => {
    const f = filtros({ sede: "AQP", mes: "2026-09", estado: "vencida", quien: "hijo", tipo: "matricula", revisor: "Ana", grupo: "en_falta" });
    expect(filtrosDeUrl(params(filtrosAUrl(f)))).toEqual(f);
  });

  it("un filtro de siempre no ensucia la dirección", () => {
    expect(filtrosAUrl(filtros())).toBe("");
  });

  it("la búsqueda de texto y las tarjetas NO viajan en el enlace", () => {
    expect(filtrosAUrl(filtros({ buscar: "sandra", tarjeta: "vencidas" }))).toBe("");
  });

  it("descarta lo que ya no tiene sentido", () => {
    const f = filtrosDeUrl(params("estado=inventado&mes=2026-13&tipo=otra_cosa&grupo=nada&vigencia=rara"));
    expect(f).toEqual(filtros());
  });

  it("mes y rango libre son excluyentes: si vienen los dos, manda el mes", () => {
    const f = filtrosDeUrl(params("mes=2026-09&desde=2026-01-01&hasta=2026-02-01"));
    expect(f.mes).toBe("2026-09");
    expect(f.desde).toBe("");
    expect(f.hasta).toBe("");
  });
});

// ── Lo que encontró la revisión independiente del 2026-10-16 ─────────────────

describe("el estado de la fila no esconde lo que un tramo terminado sigue debiendo", () => {
  const terminado = (estado: Situacion["estado_constancia"]) =>
    sit({ familia_id: "f1", vigente_desde: "2026-07-01", vigente_hasta: "2026-08-28", vigencia: "terminada", estado_constancia: estado, aprobadas: 2 });
  const nuevo = sit({ familia_id: "f2", vigente_desde: "2026-08-29", vigente_hasta: "2026-12-31", estado_constancia: "al_dia", aprobadas: 1 });

  it("una constancia por revisar de un tramo terminado hace que la fila diga «pendiente», no «al día»", () => {
    const [e] = agruparEstudios([terminado("pendiente_revision"), nuevo]);
    expect(e.estado_constancia).toBe("pendiente_revision");
    expect(grupoDeEstudio(e)).toBe("por_revisar");
  });

  it("lo mismo con una vencida o una rechazada de un tramo terminado", () => {
    expect(agruparEstudios([terminado("vencida"), nuevo])[0].estado_constancia).toBe("vencida");
    expect(agruparEstudios([terminado("rechazada"), nuevo])[0].estado_constancia).toBe("rechazada");
  });

  it("pero un «por vencer» o un «al día» de un tramo terminado no mueve nada", () => {
    expect(agruparEstudios([terminado("por_vencer"), nuevo])[0].estado_constancia).toBe("al_dia");
    expect(agruparEstudios([terminado("al_dia"), nuevo])[0].estado_constancia).toBe("al_dia");
  });

  it("entre el del tramo en curso y el del terminado manda el más urgente", () => {
    const vencidoNuevo = { ...nuevo, estado_constancia: "vencida" as const };
    expect(agruparEstudios([terminado("rechazada"), vencidoNuevo])[0].estado_constancia).toBe("vencida");
  });
});

describe("«al día» exige respaldo del tramo EN CURSO", () => {
  it("las constancias de un ciclo ya cerrado no tapan que el tramo nuevo no tiene ninguna", () => {
    const [e] = agruparEstudios([
      sit({ familia_id: "f1", vigente_desde: "2026-07-01", vigente_hasta: "2026-08-28", vigencia: "terminada", aprobadas: 3 }),
      sit({ familia_id: "f2", vigente_desde: "2026-08-29", vigente_hasta: "2026-12-31", estado_constancia: "al_dia", aprobadas: 0 }),
    ]);
    expect(e.aprobadas).toBe(0);
    expect(grupoDeEstudio(e)).toBe("por_completar");
    expect(estadoParaMostrar(e).etiqueta).toBe("Sin constancias aún");
  });

  it("la fila guarda por aparte las aprobadas del tramo que habla y su frecuencia (solo para las palabras de la insignia)", () => {
    const [e] = agruparEstudios([
      sit({ familia_id: "f1", vigente_desde: "2026-07-01", vigente_hasta: "2026-12-31", estado_constancia: "al_dia", aprobadas: 4 }),
      sit({ familia_id: "f2", vigente_desde: "2026-08-01", vigente_hasta: "2026-12-31", estado_constancia: "sin_calendario", frecuencia_pago: "unico", aprobadas: 0 }),
    ]);
    expect(e.actual.familia_id).toBe("f2");
    expect(e.aprobadas).toBe(4);
    expect(e.aprobadas_del_tramo).toBe(0);
    expect(e.frecuencia_pago).toBe("unico");
    expect(estadoParaMostrar(e).etiqueta).toBe("Sin fecha de pago");
  });

  it("dos registros vigentes a la vez siguen sumando", () => {
    const [e] = agruparEstudios([sit({ familia_id: "f1", aprobadas: 1 }), sit({ familia_id: "f2", aprobadas: 2 })]);
    expect(e.aprobadas).toBe(3);
  });

  it("si todos terminaron, cuentan las del tramo que habla por la fila", () => {
    const [e] = agruparEstudios([
      sit({ familia_id: "f1", vigente_desde: "2026-01-01", vigente_hasta: "2026-03-31", vigencia: "terminada", aprobadas: 5 }),
      sit({ familia_id: "f2", vigente_desde: "2026-04-01", vigente_hasta: "2026-06-30", vigencia: "terminada", aprobadas: 2 }),
    ]);
    expect(e.aprobadas).toBe(2);
  });
});

describe("una rechazada que ya tiene su corrección no queda roja para siempre", () => {
  const [estudio] = agruparEstudios([sit({ vigente_desde: "2026-07-01" })]);
  const meses = ["2026-08", "2026-09", "2026-10"];

  it("la rechazada de agosto, corregida con un pago de setiembre, deja de hablar por agosto", () => {
    const c = casillasDeEstudio(estudio, [
      ent({ id: "r", fecha_pago: "2026-08-30", estado: "rechazada" }),
      ent({ id: "n", fecha_pago: "2026-09-02", estado: "aprobada", reemplaza_a: "r" }),
    ], meses);
    expect(c[0].estado).toBe("vacia");
    expect(c[1].estado).toBe("aprobada");
  });

  it("una rechazada sin corrección sí sigue hablando", () => {
    const c = casillasDeEstudio(estudio, [ent({ id: "r", fecha_pago: "2026-08-30", estado: "rechazada" })], meses);
    expect(c[0].estado).toBe("rechazada");
  });

  it("la corrección puede no estar entre las constancias traídas (llegan por meses): la base avisa que la corrigieron", () => {
    const sola = [ent({ id: "r", fecha_pago: "2026-08-30", estado: "rechazada" })];
    expect(casillasDeEstudio(estudio, sola, meses, { corregidas: new Set(["r"]) })[0].estado).toBe("vacia");
    expect(casillasDeEstudio(estudio, sola, meses, { corregidas: new Set(["otra"]) })[0].estado).toBe("rechazada");
  });

  it("si la corrección también se rechazó, esa segunda sí queda", () => {
    const c = casillasDeEstudio(estudio, [
      ent({ id: "r", fecha_pago: "2026-08-30", estado: "rechazada" }),
      ent({ id: "n", fecha_pago: "2026-09-02", estado: "rechazada", reemplaza_a: "r" }),
    ], meses);
    expect(c[0].estado).toBe("vacia");
    expect(c[1].estado).toBe("rechazada");
  });
});

describe("la ventana de meses no la estira un estudio que todavía no empieza", () => {
  it("un estudio que empieza dentro de ocho meses no empuja el mes de hoy fuera de la ventana", () => {
    const meses = mesesConDatosDeLaVentana(HOY, [ent({ fecha_pago: "2026-09-30" })], [{ desde: "2027-06-01" }, { desde: "2026-07-01" }]);
    const v = ventanaDeMeses(HOY, meses, 6);
    expect(v.meses.at(-1)).toBe("2026-10");
    expect(v.meses[0]).toBe("2026-07");
  });

  it("pero una constancia que ya llegó del mes que viene sí la estira", () => {
    const meses = mesesConDatosDeLaVentana(HOY, [ent({ fecha_pago: "2026-11-02" })], [{ desde: "2026-07-01" }]);
    expect(ventanaDeMeses(HOY, meses, 6).meses.at(-1)).toBe("2026-11");
  });

  it("el rango libre de fechas también abre la ventana hasta su «desde»", () => {
    const datos = ["2026-01", "2026-09"];
    expect(ventanaParaFiltros(HOY, datos, 6, { mes: "", desde: "2026-02-10" }).meses[0]).toBe("2026-02");
    expect(ventanaParaFiltros(HOY, datos, 6, { mes: "2026-03", desde: "" }).meses[0]).toBe("2026-03");
    expect(ventanaParaFiltros(HOY, datos, 6, { mes: "", desde: "" }).meses[0]).toBe("2026-05");
  });
});

describe("lo que espera revisión no se esconde por un valor que nadie eligió", () => {
  const terminado = agruparEstudios([sit({ vigencia: "terminada", vigente_hasta: "2026-08-28", estado_constancia: "pendiente_revision" })])[0];
  const espera = ctx({ familiasConPendiente: new Set(["f1"]) });

  it("un estudio terminado con una constancia por revisar sale aunque se elijan solo los «vigentes»", () => {
    expect(pasaFiltros(terminado, filtros({ vigencia: "activas" }), espera)).toBe(true);
    expect(pasaFiltros(terminado, filtros({ vigencia: "activas" }), ctx())).toBe(false); // sin nada que revisar, sí se oculta
  });

  it("una persona ya liquidada con una constancia por revisar también sale", () => {
    const c = ctx({ familiasConPendiente: new Set(["f1"]), liquidadas: new Set(["p1"]) });
    const vigente = agruparEstudios([sit()])[0];
    expect(pasaFiltros(vigente, filtros(), c)).toBe(true);
    expect(pasaFiltros(vigente, filtros(), ctx({ liquidadas: new Set(["p1"]) }))).toBe(false);
  });

  it("pero si quien mira ELIGE «terminados», se respeta lo que eligió", () => {
    const vigente = agruparEstudios([sit()])[0];
    expect(pasaFiltros(vigente, filtros({ vigencia: "terminada" }), espera)).toBe(false);
  });

  it("las tarjetas cuentan ese pendiente", () => {
    const todos = [terminado].filter((e) => pasaFiltros(e, filtros(), espera, ["tarjeta", "grupo"]));
    expect(conteoTarjetas(todos, new Set(["f1"])).pendientes).toBe(1);
  });
});

describe("un estudio cuyas constancias no se pudieron leer nunca se esconde", () => {
  const e = agruparEstudios([sit()])[0];
  const mapa = new Map([["f1", [] as EntregaDeFamilia[]]]);

  it("con el filtro de mes, un estudio que falló no desaparece como si no tuviera constancias", () => {
    const sinLeer = ctx({ entregasPorFamilia: mapa, familiasSinLeer: new Set(["f1"]) });
    expect(pasaFiltros(e, filtros({ mes: "2026-09" }), sinLeer)).toBe(true);
    // Leído y de verdad sin constancias ese mes: ahí sí se queda fuera.
    expect(pasaFiltros(e, filtros({ mes: "2026-09" }), ctx({ entregasPorFamilia: mapa }))).toBe(false);
  });
});

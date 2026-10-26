// ============================================================================
// bandeja-fuentes.test.ts — Una sola lista para la pantalla, el menú y Equipo
// ============================================================================
// Lo que se defiende acá es lo que se rompió dos veces la misma semana:
//
// 1. EL NÚMERO DEL MENÚ ES LA LISTA. `cuentaDeLaBandeja` tiene que dar
//    exactamente las filas que arma `armarPendientes`, más UNA unidad por cada
//    señal de sistema (correos con problema, constancias de Normas) — y nada
//    más. Antes el menú no sumaba liquidaciones vencidas y, desde que sí suma
//    los correos, contaba 61 fallidos como 61 pendientes (96 en vez de 33).
// 2. EQUIPO CUENTA LO MISMO. `pendientesPorPersona` agrupa esa misma lista.
// 3. QUIÉN CESÓ BAJA DE GRUPO PERO SIGUE CONTANDO.
// 4. SOLO LA LIQUIDACIÓN VENCIDA CON DINERO cruza a la Bandeja.
// ============================================================================
import { describe, expect, it } from "vitest";
import {
  alertasConProblema, armarPendientes, cuentaDeLaBandeja, esEducacionParaSaber, esLiquidacionParaBandeja, FUENTES_VACIAS,
  pendientesPorPersona, type FuentesBandeja,
} from "../apps/web/lib/admin/bandeja-fuentes";

const HOY = "2026-09-15";
const ANA = "11111111-1111-1111-1111-111111111111";
const LUZ = "22222222-2222-2222-2222-222222222222";

const fuentes: FuentesBandeja = {
  ...FUENTES_VACIAS,
  revisiones: [{ id: "r1", persona_id: ANA, nombre: "Ana Prueba", sede: "TRU", fecha: "2026-09-03", comentario: "No tomó mi salida", pedida_at: "2026-09-06T15:00:00Z" }],
  solicitudesVacaciones: [{ id: "v1", persona_id: LUZ, nombre: "Luz Prueba", sede: "AQP", fecha_inicio: HOY, fecha_fin: "2026-09-19", dias: 5, comentario: null, pedida_at: "2026-09-12T15:00:00Z" }],
  liquidacionesVencidas: [{ persona_id: LUZ, persona: "Luz Prueba", sede: "AQP", fecha_cese: "2026-08-20", vence_el: "2026-09-13", dias_restantes: -2, total: 1240, pagada: false, vencido: true }],
  sinHorario: [{ persona_id: ANA, nombre: "Ana Prueba", sede: "TRU", dias: 3, primer_dia: "2026-09-08", ultimo_dia: "2026-09-10", nunca_tuvo_horario: false }],
  resumenAlertas: { despachables: 4, atascadas: 1, fallidas_definitivas: 2, caducadas: 0, ultimo_envio_at: null, motivos_definitivos: [] },
};

describe("la lista y los números salen de lo mismo", () => {
  it("la cuenta es las filas de la lista más UNA unidad por el problema de correo — liquidaciones incluidas", () => {
    const filas = armarPendientes(fuentes, { hoy: HOY });
    expect(filas).toHaveLength(4);
    expect(filas.some((p) => p.modulo === "liquidaciones")).toBe(true);
    // 2 fallidas (la atascada se reintenta sola y no cuenta) = 2 avisos con problema, pero UN problema: pesa 1.
    expect(alertasConProblema(fuentes.resumenAlertas)).toBe(2);
    expect(cuentaDeLaBandeja(fuentes, 0, HOY)).toEqual({ tareas: 4, sistema: 1, normas: 0, total: 5 });
  });

  it("Equipo agrupa esa misma lista por persona", () => {
    const mapa = pendientesPorPersona(fuentes, HOY);
    expect(mapa.get(ANA)).toHaveLength(2);
    // Mismo orden que la pantalla: la liquidación vencida antes que las vacaciones de hoy.
    expect(mapa.get(LUZ)).toEqual([
      "Liquidaciones: Liquidación pasada de plazo",
      "Ausencias: Vacaciones del 15 de setiembre al 19 de setiembre · 5 días",
    ]);
    const total = [...mapa.values()].reduce((s, xs) => s + xs.length, 0);
    expect(total).toBe(armarPendientes(fuentes, { hoy: HOY }).length);
  });

  it("sin fuentes no hay nada que contar", () => {
    expect(cuentaDeLaBandeja(FUENTES_VACIAS, 0, HOY)).toEqual({ tareas: 0, sistema: 0, normas: 0, total: 0 });
  });
});

describe("la cuenta de la Bandeja: cada señal de sistema pesa uno", () => {
  // La captura del 2026-10-25: 31 filas + 61 correos fallidos + 4 de Normas = 96 en el menú.
  const treintaYUna = Array.from({ length: 31 }, (_, i) => ({
    id: `r${i}`, persona_id: ANA, nombre: "Ana Prueba", sede: "TRU", fecha: "2026-09-03",
    comentario: "No tomó mi salida", pedida_at: "2026-09-06T15:00:00Z",
  }));
  const captura: FuentesBandeja = {
    ...FUENTES_VACIAS,
    revisiones: treintaYUna,
    resumenAlertas: { despachables: 0, atascadas: 0, fallidas_definitivas: 61, caducadas: 0, ultimo_envio_at: null, motivos_definitivos: [] },
  };

  it("61 correos fallidos y 4 constancias de Normas suman filas + 2, no filas + 65", () => {
    const filas = armarPendientes(captura, { hoy: HOY }).length;
    expect(filas).toBe(31);
    const c = cuentaDeLaBandeja(captura, 4, HOY);
    expect(c).toEqual({ tareas: 31, sistema: 1, normas: 1, total: 33 });
    expect(c.total).toBe(filas + 2);
  });

  it("sin problema de correo ni Normas, el total es solo las filas", () => {
    const limpio = { ...captura, resumenAlertas: { ...captura.resumenAlertas!, fallidas_definitivas: 0 } };
    expect(cuentaDeLaBandeja(limpio, 0, HOY)).toEqual({ tareas: 31, sistema: 0, normas: 0, total: 31 });
    // Lo que se reintenta solo (despachables) tampoco es un problema.
    const reintentando = { ...limpio, resumenAlertas: { ...limpio.resumenAlertas!, despachables: 12 } };
    expect(cuentaDeLaBandeja(reintentando, 0, HOY).total).toBe(31);
    // Sin la salud de los correos (quien no la ve) tampoco.
    expect(cuentaDeLaBandeja({ ...captura, resumenAlertas: null }, 0, HOY).total).toBe(31);
  });

  it("cada señal cuenta por separado: solo correo, solo Normas", () => {
    expect(cuentaDeLaBandeja(captura, 0, HOY).total).toBe(32);
    const sinCorreo = { ...captura, resumenAlertas: null };
    expect(cuentaDeLaBandeja(sinCorreo, 4, HOY).total).toBe(32);
  });

  it("una constancia o cuarenta de Normas pesan lo mismo; cero o negativo, nada", () => {
    expect(cuentaDeLaBandeja(FUENTES_VACIAS, 1, HOY).total).toBe(1);
    expect(cuentaDeLaBandeja(FUENTES_VACIAS, 40, HOY).total).toBe(1);
    expect(cuentaDeLaBandeja(FUENTES_VACIAS, 0, HOY).total).toBe(0);
    expect(cuentaDeLaBandeja(FUENTES_VACIAS, -3, HOY).total).toBe(0);
  });

  it("`alertasConProblema` sigue contando avisos: la tarjeta Sistema dice «61 avisos»", () => {
    expect(alertasConProblema(captura.resumenAlertas)).toBe(61);
  });

  it("las atascadas se reintentan solas: no cuentan, ni en el titular ni en el menú", () => {
    const soloAtascadas = { despachables: 0, atascadas: 2, fallidas_definitivas: 0, caducadas: 0, ultimo_envio_at: null, motivos_definitivos: [] };
    expect(alertasConProblema(soloAtascadas)).toBe(0);
    // Un corte transitorio de una hora no enciende el menú.
    expect(cuentaDeLaBandeja({ ...FUENTES_VACIAS, resumenAlertas: soloAtascadas }, 0, HOY)).toEqual({ tareas: 0, sistema: 0, normas: 0, total: 0 });
    // Y si hay un problema de verdad, las atascadas tampoco suben el número del titular.
    expect(alertasConProblema({ ...soloAtascadas, fallidas_definitivas: 3, caducadas: 1 })).toBe(4);
  });

  it("los avisos caducados sí cuentan: no salieron y nadie los va a mandar solos", () => {
    const soloCaducadas = { despachables: 0, atascadas: 0, fallidas_definitivas: 0, caducadas: 5, ultimo_envio_at: null, motivos_definitivos: [] };
    expect(alertasConProblema(soloCaducadas)).toBe(5);
    expect(cuentaDeLaBandeja({ ...FUENTES_VACIAS, resumenAlertas: soloCaducadas }, 0, HOY).sistema).toBe(1);
  });
});

describe("cese y «Nuevo»", () => {
  it("quien cesó baja a Sin plazo pero no deja de contar", () => {
    const filas = armarPendientes(fuentes, { hoy: HOY, ceses: new Map([[ANA, "2026-09-10"]]) });
    const deAna = filas.filter((p) => p.personaId === ANA);
    expect(deAna.every((p) => p.urgencia.grupo === "sin_plazo" && p.cesoEl === "2026-09-10")).toBe(true);
    expect(filas).toHaveLength(4);
  });

  it("un cese programado a futuro todavía no cuenta como cesado", () => {
    const filas = armarPendientes(fuentes, { hoy: HOY, ceses: new Map([[ANA, "2026-10-01"]]) });
    expect(filas.find((p) => p.tipo === "sin_horario")?.cesoEl).toBeNull();
  });

  it("«Nuevo» solo en lo que no está en bandeja_vistos, y nunca en lo que no se marca visto", () => {
    const filas = armarPendientes(fuentes, { hoy: HOY, vistos: new Set(["revision:r1"]) });
    expect(filas.find((p) => p.tipo === "revision")?.nuevo).toBe(false);
    expect(filas.find((p) => p.tipo === "solicitud_vacacion")?.nuevo).toBe(true);
    expect(filas.find((p) => p.tipo === "sin_horario")?.nuevo).toBe(false);
  });
});

describe("qué cruza a la Bandeja", () => {
  it("solo la liquidación vencida, sin pagar y con monto", () => {
    const base = { persona_id: LUZ, persona: "Luz", sede: "AQP", fecha_cese: "2026-08-20", vence_el: "2026-09-13", dias_restantes: -2, total: 100, pagada: false, vencido: true };
    expect(esLiquidacionParaBandeja(base)).toBe(true);
    expect(esLiquidacionParaBandeja({ ...base, pagada: true })).toBe(false);
    expect(esLiquidacionParaBandeja({ ...base, vencido: false })).toBe(false);
    expect(esLiquidacionParaBandeja({ ...base, total: 0 })).toBe(false);
  });

  it("educación: vencida, sin calendario vigente, o pago cercano", () => {
    const base = { familia_id: "f", persona_id: ANA, persona: "Ana", sede: "TRU", institucion: "X", vigencia: "vigente", estado_constancia: "al_dia", fecha_pago_constancia: null, plazo: null, pago_proximo: false, proxima_fecha_pago: null, dias_para_pago: null };
    expect(esEducacionParaSaber(base)).toBe(false);
    expect(esEducacionParaSaber({ ...base, estado_constancia: "vencida" })).toBe(true);
    expect(esEducacionParaSaber({ ...base, estado_constancia: "sin_calendario" })).toBe(true);
    expect(esEducacionParaSaber({ ...base, estado_constancia: "sin_calendario", vigencia: "terminada" })).toBe(false);
    expect(esEducacionParaSaber({ ...base, pago_proximo: true })).toBe(true);
  });
});

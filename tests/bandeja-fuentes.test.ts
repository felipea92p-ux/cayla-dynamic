// ============================================================================
// bandeja-fuentes.test.ts — Una sola lista para la pantalla, el menú y Equipo
// ============================================================================
// Lo que se defiende acá es lo que se rompió dos veces la misma semana:
//
// 1. EL NÚMERO DEL MENÚ ES LA LISTA. `contarPendientesBandeja` tiene que dar
//    exactamente las filas que arma `armarPendientes`, más los avisos por correo
//    con problema — y nada más. Antes el menú no sumaba liquidaciones vencidas.
// 2. EQUIPO CUENTA LO MISMO. `pendientesPorPersona` agrupa esa misma lista.
// 3. QUIÉN CESÓ BAJA DE GRUPO PERO SIGUE CONTANDO.
// 4. SOLO LA LIQUIDACIÓN VENCIDA CON DINERO cruza a la Bandeja.
// ============================================================================
import { describe, expect, it } from "vitest";
import {
  armarPendientes, contarPendientesBandeja, esEducacionParaSaber, esLiquidacionParaBandeja, FUENTES_VACIAS,
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
  it("el menú cuenta las filas de la lista más los correos con problema — liquidaciones incluidas", () => {
    const filas = armarPendientes(fuentes, { hoy: HOY });
    expect(filas).toHaveLength(4);
    expect(filas.some((p) => p.modulo === "liquidaciones")).toBe(true);
    expect(contarPendientesBandeja(fuentes, HOY)).toBe(4 + 3);
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
    expect(contarPendientesBandeja(FUENTES_VACIAS, HOY)).toBe(0);
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

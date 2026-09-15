// Las filas del CSV de Planilla — para el contador.
//
// Decisión del 2026-09-15: el CSV es la planilla, no la vista. Sale SIEMPRE
// completo —todos los grupos, sin filtros—, con la columna de grupo y con
// TODAS las partidas que entran al total, de modo que `total` se reconstruye
// sumando las demás columnas. Hasta ese día seguía el filtro de la pantalla y
// le faltaban movilidad, educación, pensión y los recargos: la columna `total`
// no cuadraba con sus propias columnas.
//
// Vive fuera de la página para poder probar esa promesa (tests/).

import { TIPOS_VINCULO, TIPO_VINCULO_LABEL } from "@cayla-dynamic/shared";
import { RANGO_LABEL } from "@/lib/rangos";
import { grupoDe, textoCese, type Cese } from "./revision";
import type { Fila } from "./tipos";

/** Columnas que SUMAN al total. Si una migración agrega una partida, va aquí y en `desgloseDe`. */
export const COLUMNAS_QUE_SUMAN = [
  "pago_base", "monto_feriados", "monto_plus", "asignacion_familiar", "monto_movilidad", "monto_educacion",
  "bonos", "monto_sobretiempo", "monto_descanso_semanal",
] as const;
/** Columnas que RESTAN del total. */
export const COLUMNAS_QUE_RESTAN = ["descuento_pension", "descuentos", "retencion_4ta"] as const;

export function filasCsvPlanilla(filas: Fila[], ceseDe: (personaId: string) => Cese) {
  const orden = (f: Fila) => TIPOS_VINCULO.indexOf(grupoDe(f));
  return [...filas]
    .sort((a, b) => orden(a) - orden(b) || a.nombre.localeCompare(b.nombre))
    .map((f) => ({
      grupo: TIPO_VINCULO_LABEL[grupoDe(f)],
      nombre: f.nombre,
      sede: f.sede,
      situacion_en_periodo: textoCese(ceseDe(f.persona_id)) ?? "Activa",
      rango: f.rango ? (RANGO_LABEL[f.rango] ?? f.rango) : "sin salario",
      salario_referencia: f.salario_ref ?? "",
      horas: f.horas_mes,
      dias_trabajados: f.dias_trabajados,
      dias_pendientes: f.dias_pendientes,
      horas_sin_salario: f.horas_sin_salario,
      pago_base: f.pago_base,
      monto_feriados: f.monto_feriados,
      monto_plus: f.monto_plus,
      asignacion_familiar: f.asignacion_familiar,
      monto_movilidad: f.monto_movilidad ?? 0,
      monto_educacion: f.monto_educacion ?? 0,
      bonos: f.bonos,
      monto_sobretiempo_25: f.monto_sobretiempo_25 ?? "",
      monto_sobretiempo_35: f.monto_sobretiempo_35 ?? "",
      monto_sobretiempo: f.monto_sobretiempo ?? 0,
      monto_descanso_semanal: f.monto_descanso_semanal ?? 0,
      regimen_pension: f.regimen_pension ?? "",
      descuento_pension: f.descuento_afp ?? 0,
      descuentos: f.descuentos,
      retencion_4ta_base: f.retencion_4ta_base ?? "",
      retencion_4ta: f.retencion_4ta ?? 0,
      total: f.total,
      objetivos_cumplidos: f.objetivos_cumplidos ?? "",
      objetivos_total: f.objetivos_total ?? "",
      aporte_essalud: f.aporte_essalud ?? "",
      provision_gratificacion: f.provision_gratificacion,
      provision_cts: f.provision_cts,
      provision_vacaciones: f.provision_vacaciones,
      provision_total: f.provision_total,
    }));
}

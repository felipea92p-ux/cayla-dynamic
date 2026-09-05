// El monto vigente de la asignación familiar, leído de donde vive de verdad.
//
// QUÉ PROMETE: devuelve el monto que la planilla va a pagar HOY a quien tiene
// la casilla «tiene hijos» activada, y desde cuándo rige; o `null` si no hay
// dato — y `null` significa «no se sabe», nunca «pon el de siempre».
//
// POR QUÉ EXISTE (hallazgo 24 de la auditoría del 2026-09-03/04): la casilla
// de asignación familiar en Equipo decía «S/ 113 fijos por periodo», con la
// cifra escrita a mano. El monto NO es fijo: vive versionado en
// `parametros_laborales` (clave `asignacion_familiar`, con `vigente_desde` /
// `vigente_hasta`, migración 0122) y la planilla lo lee de ahí día por día.
// Cuando el contador lo suba porque cambió la RMV, la ficha seguiría diciendo
// 113 y quien activa la casilla creería que compromete otra cifra.
//
// Es la tercera regla de la casa: nunca una lista —ni un número— escrito a
// mano de algo que vive en una tabla. Por eso este archivo NO tiene ningún
// monto de respaldo: si la consulta no trae nada, la pantalla lo dice.
//
// DE DÓNDE SE LEE, en el mismo orden que `fn_planilla_calcular` (0339):
//   1. `parametros_laborales`: la fila de clave `asignacion_familiar` vigente
//      hoy (misma condición que la planilla, sin filtro por sede — la
//      asignación es una sola para toda CAYLA). La RLS
//      `parametros_laborales_lectura_admin` (0116) solo deja leerla a admin o
//      líder; para cualquier otro rol la consulta vuelve vacía sin error.
//   2. `configuracion.asignacion_familiar` → `valor->>'monto'` (0113), el
//      respaldo que la planilla también usa. Se lee con cualquier sesión.
//   3. Si tampoco hay nada: `null`.
//
// DOS DIFERENCIAS CON LA PLANILLA, a propósito y para que nadie las tome por
// bug: (a) aquí se resuelve a HOY y `fn_planilla_calcular` resuelve a la fecha
// de cierre del periodo (`p_fin`) — solo divergen si el contador programa un
// cambio con `vigente_desde` dentro del periodo en curso pero posterior a hoy,
// y la etiqueta dice «según el monto vigente», que sigue siendo cierto; (b) la
// planilla conserva todavía un `coalesce(…, 113.00)` de respaldo (0339) para
// cuando las dos tablas están vacías, y este helper devuelve `null` en ese
// mismo caso. Ese respaldo escrito a mano es deuda de la planilla, no de esta
// pantalla; se anota aquí para que se pague en su propio lote.

import type { ClienteCayla } from "@cayla-dynamic/database";
import { hoyLima } from "@cayla-dynamic/shared";

export interface MontoAsignacionFamiliar {
  monto: number;
  /** ISO (aaaa-mm-dd) si vino de `parametros_laborales`; null si vino del respaldo. */
  vigenteDesde: string | null;
}

export async function montoAsignacionFamiliar(
  supabase: ClienteCayla,
): Promise<MontoAsignacionFamiliar | null> {
  const hoy = hoyLima();

  const { data: vigente } = await supabase
    .from("parametros_laborales")
    .select("valor, vigente_desde")
    .eq("clave", "asignacion_familiar")
    .lte("vigente_desde", hoy)
    .or(`vigente_hasta.is.null,vigente_hasta.gte.${hoy}`)
    .order("vigente_desde", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (vigente && Number.isFinite(Number(vigente.valor))) {
    return { monto: Number(vigente.valor), vigenteDesde: vigente.vigente_desde };
  }

  const { data: respaldo } = await supabase
    .from("configuracion")
    .select("valor")
    .eq("clave", "asignacion_familiar")
    .maybeSingle();

  const monto = Number((respaldo?.valor as { monto?: unknown } | null)?.monto);
  if (Number.isFinite(monto)) {
    return { monto, vigenteDesde: null };
  }

  return null;
}

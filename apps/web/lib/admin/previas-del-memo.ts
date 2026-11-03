// Las sanciones previas que un memo nombra o en las que se apoya: el escalón de
// una suspensión (primera o segunda) y la lista de la carta de imputación.
//
// UNA sola consulta para las DOS pantallas que pintan el memo —Disciplina y su
// Info—, porque el documento tiene que decir lo mismo en las dos. Hasta el
// 2026-11-03 solo la de Disciplina las pedía, con otro criterio: entraba la
// llamada verbal —que «no es sanción» (19.2 a, 54.2)— y la ventana se contaba
// desde hoy por la firma, no desde el hecho por la entrega (56.1).
//
// El criterio es el de la base (`fn_cargos_detalle`, 0581, y
// `fn_conducta_antecedentes`, 0510): entregadas, de amonestación o suspensión,
// en los doce meses anteriores al cierre del hecho, y en conducta de la misma
// falta (56.5). Lee lo que la sesión puede leer: Disciplina por su rol, ella por
// `exp_select_propia`.

import type { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { rangoDelDiaLima } from "@cayla-dynamic/shared";
import type { Previa } from "@/components/disciplina/memo-documento";

type Cliente = ReturnType<typeof createAdminSupabaseClient>;

export interface DocParaPrevias {
  id: string;
  persona_id: string;
  tipo_causal: string;
  periodo_hasta: string | null;
  falta_numeral?: string | null;
  falta_literal?: string | null;
}

const DOCE_MESES_MS = 365 * 24 * 3600 * 1000;

export async function previasDelMemo(sb: Cliente, doc: DocParaPrevias): Promise<Previa[]> {
  const ref = doc.periodo_hasta ? rangoDelDiaLima(doc.periodo_hasta).fin : new Date().toISOString();
  let q = sb.from("expediente_disciplinario")
    .select("correlativo, nivel, firmado_at, entregado_at")
    .eq("persona_id", doc.persona_id)
    .eq("tipo_causal", doc.tipo_causal)
    .eq("estado", "entregado")
    .in("nivel", ["amonestacion", "suspension"])
    .neq("id", doc.id)
    .lte("entregado_at", ref)
    .gte("entregado_at", new Date(Date.parse(ref) - DOCE_MESES_MS).toISOString());
  if (doc.tipo_causal === "conducta" && doc.falta_numeral && doc.falta_literal) {
    q = q.eq("falta_numeral", doc.falta_numeral).eq("falta_literal", doc.falta_literal);
  }
  const { data } = await q.order("entregado_at", { ascending: true });
  return (data as Previa[] | null) ?? [];
}

import type { ClienteCayla } from "@cayla-dynamic/database";

/**
 * Tu bono de cumpleaños, tal como lo contesta `fn_mi_bono_cumpleanos` (0478).
 *
 * POR QUÉ UN ARCHIVO PARA ESTO. Info (/mio), la Bandeja mía y /mio/cumpleanos
 * hacen la misma pregunta —«¿qué me toca con mi bono?»— y la base ya la
 * contesta en UNA función, que además es la puerta del pedido. Acá solo se lee
 * esa respuesta y se decide lo que es de pantalla (cuándo mostrar la tarjeta).
 * Nadie en el frontend vuelve a mirar `bono_estado` del tablero: ese no sabe
 * que el bono es de planilla, y le ofrecería a una practicante un bono que la
 * base le niega.
 */

export type EstadoMiBono =
  /** Lo pidió (firmó) y DO todavía no confirma la transferencia. */
  | "pedido"
  /** No está en planilla, o su cumpleaños de este año cayó antes del bono o de su ingreso. */
  | "no_aplica"
  /** Falta su fecha de nacimiento en la ficha. */
  | "sin_fecha"
  /** Cumple más adelante este año. */
  | "proximo"
  /** Cumple este mes: puede pedirlo. */
  | "este_mes"
  /** Ya cumplió este año y no lo pidió: todavía puede. */
  | "vencido"
  /** Ya se entregó este año: transferencia confirmada, o cargo en papel. */
  | "entregado";

export interface MiBono {
  estado: EstadoMiBono;
  mes_cumpleanos: number | null;
  anio: number;
  monto: number | null;
  documento_id: string | null;
  /** Cuándo lo pidió. Null si nunca lo pidió desde el sistema (o si fue en papel). */
  pedido_el: string | null;
  /** Cuándo se lo entregaron: la fecha que confirmó DO, o la escrita en el cargo en papel. */
  entregado_el: string | null;
}

/** Lo único que habilita el botón «Pedir mi bono». Es la misma condición que exige la base. */
export function puedePedirBono(b: MiBono | null | undefined): boolean {
  return b?.estado === "este_mes" || b?.estado === "vencido";
}

/**
 * ¿Va la tarjeta del bono en el Resumen de Info?
 *
 * Sí cuando hay algo que hacer o que esperar (pedirlo, o ver que ya lo pidió),
 * y en el mes de su cumpleaños también cuando ya se entregó: es el mes en que
 * lo va a buscar. Fuera de eso no: una tarjeta que dice «tu cumpleaños es en
 * marzo» durante once meses es ruido que enseña a no mirar el Resumen.
 */
export function mostrarBonoEnInfo(b: MiBono | null | undefined, hoy: string): boolean {
  if (!b) return false;
  if (b.estado === "este_mes" || b.estado === "vencido" || b.estado === "pedido") return true;
  return b.estado === "entregado" && b.mes_cumpleanos === Number(hoy.slice(5, 7));
}

/** Lee tu bono. Una sola fila, o null si la sesión no está enlazada con una persona. */
export async function traerMiBono(supabase: ClienteCayla): Promise<{ bono: MiBono | null; error: unknown }> {
  const { data, error } = await supabase.rpc("fn_mi_bono_cumpleanos");
  if (error) return { bono: null, error };
  const fila = ((data ?? []) as unknown as MiBono[])[0] ?? null;
  return {
    bono: fila ? { ...fila, monto: fila.monto === null ? null : Number(fila.monto) } : null,
    error: null,
  };
}

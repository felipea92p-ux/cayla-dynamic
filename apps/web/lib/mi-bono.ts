import type { ClienteCayla } from "@cayla-dynamic/database";

/**
 * Tu bono de cumpleaños, tal como lo contesta `fn_mi_bono_cumpleanos` (0478).
 *
 * POR QUÉ UN ARCHIVO PARA ESTO. Info (/mio), la Bandeja mía y /mio/cumpleanos
 * hacen la misma pregunta —«¿qué me toca con mi bono?»— y la base ya la
 * contesta en UNA función, que además es la puerta del pedido. Acá solo se lee
 * esa respuesta y se decide lo que es de pantalla (cuándo mostrar la tarjeta).
 * Nadie en el frontend vuelve a mirar `bono_estado` del tablero: ese no sabe
 * distinguir un pedido ya hecho pero todavía sin pagar de uno entregado (0478/
 * 0479): para el tablero toda constancia vigente es «entregado». Quién puede recibir el bono —en planilla o
 * practicante— lo dice la base (`fn_persona_le_corresponde_bono`, 0519).
 */

export type EstadoMiBono =
  /**
   * Lo pidió (firmó) y NO está en ninguna boleta: DO todavía no confirma la
   * transferencia. Es el respaldo —no había periodo de planilla al firmar, o
   * alguien quitó la línea (0479)—; lo normal desde la 0479 es `en_boleta`.
   */
  | "pedido"
  /** Lo firmó, ya está en su boleta y el periodo todavía no se paga (0479). */
  | "en_boleta"
  /** No le corresponde (ni en planilla ni practicante), o su cumpleaños de este año cayó antes del bono o de su ingreso. */
  | "no_aplica"
  /** Falta su fecha de nacimiento en la ficha. */
  | "sin_fecha"
  /** Cumple más adelante este año. */
  | "proximo"
  /** Cumple este mes: puede pedirlo. */
  | "este_mes"
  /** Ya cumplió este año y no lo pidió: todavía puede. */
  | "vencido"
  /** Ya se entregó este año: planilla pagada, transferencia confirmada, o cargo en papel. */
  | "entregado";

/** Por dónde le llega el bono (0479). Null mientras no hay constancia. */
export type ViaBono = "boleta" | "transferencia" | "papel";

export interface MiBono {
  estado: EstadoMiBono;
  mes_cumpleanos: number | null;
  anio: number;
  monto: number | null;
  documento_id: string | null;
  /** Cuándo lo pidió. Null si nunca lo pidió desde el sistema (o si fue en papel). */
  pedido_el: string | null;
  /**
   * Cuándo se lo entregaron: la fecha que confirmó DO, o la escrita en el cargo
   * en papel. Null cuando la vía es la boleta: la planilla no guarda el día
   * exacto en que se transfirió a cada persona, solo el periodo (`periodo_fin`).
   */
  entregado_el: string | null;
  /**
   * Por dónde le llegó o le va a llegar. Opcional en el tipo a propósito: entre
   * que se fusiona el frontend y se pega la 0479, la base todavía no lo manda,
   * y una pantalla que asume que existe se rompería. Sin `via` se lee como el
   * comportamiento de antes de la 0479 (transferencia o papel).
   */
  via?: ViaBono | null;
  /** El cierre del periodo cuya boleta lleva el bono. Solo si la vía es la boleta. */
  periodo_fin?: string | null;
}

/** Lo único que habilita el botón «Pedir mi bono». Es la misma condición que exige la base. */
export function puedePedirBono(b: MiBono | null | undefined): boolean {
  return b?.estado === "este_mes" || b?.estado === "vencido";
}

/**
 * ¿Va la tarjeta del bono en el Resumen de Info?
 *
 * Sí cuando hay algo que hacer o que esperar (pedirlo, o ver que ya lo pidió o
 * que ya está en su boleta),
 * y en el mes de su cumpleaños también cuando ya se entregó: es el mes en que
 * lo va a buscar. Fuera de eso no: una tarjeta que dice «tu cumpleaños es en
 * marzo» durante once meses es ruido que enseña a no mirar el Resumen.
 */
export function mostrarBonoEnInfo(b: MiBono | null | undefined, hoy: string): boolean {
  if (!b) return false;
  if (b.estado === "este_mes" || b.estado === "vencido" || b.estado === "pedido"
      || b.estado === "en_boleta") return true;
  return b.estado === "entregado" && b.mes_cumpleanos === Number(hoy.slice(5, 7));
}

/** Lee tu bono. Una sola fila, o null si la sesión no está enlazada con una persona. */
export async function traerMiBono(
  supabase: ClienteCayla,
): Promise<{ bono: MiBono | null; error: { message: string; code?: string } | null }> {
  const { data, error } = await supabase.rpc("fn_mi_bono_cumpleanos");
  if (error) return { bono: null, error };
  const fila = ((data ?? []) as unknown as MiBono[])[0] ?? null;
  return {
    bono: fila ? { ...fila, monto: fila.monto === null ? null : Number(fila.monto) } : null,
    error: null,
  };
}

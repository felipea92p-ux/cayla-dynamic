// CONTRATOS — en qué BANDA de urgencia cae cada persona (variante C, elegida por Felipe el 2026-10-19).
//
// `fn_contratos_tablero` ya ordena y clasifica (estado por persona); lo que esta pantalla escondía entre un
// select de 12 opciones, 4 casillas y 5 pestañas era el ORDEN. Aquí se dice una sola vez, con tres reglas que
// Felipe decidió y que NO tocan ningún estado legal (art. 77, qué cuenta como firmado, adendum…):
//
//   · «Vence pronto» es la ventana que ya cuenta la base —60 días—, no los 30 que decía la tarjeta.
//   · «En papel» (sin fila en `contratos_generados` pero con fecha de fin en la ficha: se firmó antes del
//     generador) es HISTORIA, no urgencia: va a «Al día». Mezclarlos con lo urgente llenaba el aviso de cosas
//     que no hay que hacer hoy, y un aviso así se aprende a ignorar.
//   · «Sin contrato registrado» (ni fila ni fecha) SÍ pide atención: no se sabe de ningún contrato.

export type Banda = "paso" | "pronto" | "firma" | "sin_contrato" | "al_dia";

/** De la más urgente a la menos. «al_dia» va al final y casi siempre plegada. */
export const ORDEN_BANDAS: readonly Banda[] = ["paso", "pronto", "firma", "sin_contrato", "al_dia"];

export const TEXTO_BANDA: Record<Banda, { titulo: string; ayuda: string }> = {
  paso: { titulo: "Ya pasó el plazo", ayuda: "El contrato terminó y la persona sigue marcando: el art. 77 corre solo." },
  pronto: { titulo: "Vence en los próximos 60 días", ayuda: "Hay que decidir si se renueva, y redactarlo, antes de la fecha." },
  firma: { titulo: "Falta la firma o la copia", ayuda: "El contrato existe pero no está firmado, o falta entregarle su copia." },
  sin_contrato: { titulo: "Sin contrato registrado", ayuda: "Ni un documento ni una fecha de fin anotada: no se sabe de ningún contrato." },
  al_dia: { titulo: "Al día", ayuda: "Vigentes, sin vencimiento y los firmados en papel antes del generador." },
};

export function bandaDe(f: { estado: string; fecha_fin_contrato: string | null }): Banda {
  switch (f.estado) {
    case "desnaturalizado":
    case "vencido":
      return "paso";
    case "por_vencer":
      return "pronto";
    case "sin_firmar":
    case "tramite_pendiente":
      return "firma";
    case "sin_contrato":
      // Con fecha de fin en la ficha: se firmó en papel antes del generador. Historia, no urgencia.
      return f.fecha_fin_contrato !== null ? "al_dia" : "sin_contrato";
    default:
      return "al_dia"; // ok, sin_vencimiento y cualquier estado nuevo que la base agregue (lo seguro es no gritar)
  }
}

/** Cuántos contratos vencen EL MISMO día, si son 3 o más (el racimo): `null` si no hay. */
export function racimoDeVencimientos(fechas: readonly (string | null)[], minimo = 3): { fecha: string; cuantos: number } | null {
  const m = new Map<string, number>();
  for (const f of fechas) if (f) m.set(f, (m.get(f) ?? 0) + 1);
  const mejor = [...m.entries()].sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : 1))[0];
  return mejor && mejor[1] >= minimo ? { fecha: mejor[0], cuantos: mejor[1] } : null;
}

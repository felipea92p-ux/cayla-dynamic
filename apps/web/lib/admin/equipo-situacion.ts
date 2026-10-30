// EQUIPO — las dos reglas de «qué hay que mirar» (decididas por Felipe el 2026-10-19), como funciones puras.
//
// Antes los dos avisos de la pantalla eran más anchos que lo que decían:
//   · «Sin salario asignado» contaba a TODA persona activa sin tramo vigente, incluidos dirección, honorarios
//     y quien no tiene vínculo laboral, que no deben tener uno. Una alerta que en parte nunca se resuelve se
//     aprende a ignorar, y el día que aparezca alguien que de verdad no tiene salario, se ignora también.
//   · «Fin de contrato próximo» contaba cualquier fecha anotada, sea en 3 días o en 14 meses.
//
// Lo que NO cambia: anotar un fin de contrato es un plan, no da de baja a nadie; y que el aviso no cuente a
// alguien no significa que esa persona no deba revisarse en su ficha.

/** Días hacia adelante en que un fin de contrato pasa a ser «próximo». Decidido el 2026-10-19: 60. */
export const VENTANA_FIN_CONTRATO_DIAS = 60;

/** ¿Esta persona debe tener un tramo de salario? Dirección, honorarios (rxh) y sin vínculo laboral, no. */
export function debeTenerSalario(p: { tipo_vinculo: string; personal_direccion: boolean }): boolean {
  if (p.personal_direccion) return false;
  return p.tipo_vinculo !== "rxh" && p.tipo_vinculo !== "no_trabajador";
}

function sumarDias(iso: string, n: number): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

/**
 * ¿El contrato termina dentro de la ventana, o YA terminó y sigue activa? Lo segundo es lo peor —el art. 77 ya
 * corrió—, así que cuenta aunque la fecha sea pasada. `fecha` es YYYY-MM-DD; `hoy` también (Lima).
 */
export function finDeContratoProximo(fecha: string | undefined, hoy: string, ventana = VENTANA_FIN_CONTRATO_DIAS): boolean {
  return fecha != null && fecha <= sumarDias(hoy, ventana);
}

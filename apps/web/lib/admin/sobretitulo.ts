// El sobretítulo de una pantalla de sección: «Asistencia · lunes, 19 de octubre».
//
// Dice dos cosas que quien mira necesita saber y que la pantalla no repite: en qué sección del menú
// está y de qué día es lo que ve (una captura de pantalla no se puede fechar después). La forma —la
// raya y las mayúsculas— la da <CabeceraPagina>; acá solo se arma el texto, para que las seis
// pantallas de Asistencia no escriban cada una su propia fecha.
//
// El día sale de `hoyLima()` (la regla del repo: nada de escribir la zona horaria fuera de
// fecha-lima.ts) y se formatea con `fechaConDia`, la misma que usa el Dashboard.

import { hoyLima } from "@cayla-dynamic/shared";
import { fechaConDia } from "@/lib/admin/asistencia-hoy";

export function sobretituloDeHoy(seccion: string): string {
  // «lunes 19 de octubre» → «lunes, 19 de octubre»: la coma es de Retail y se lee mejor en mayúsculas.
  const dia = fechaConDia(hoyLima()).replace(" ", ", ");
  return `${seccion} · ${dia}`;
}

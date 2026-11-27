// El sobretítulo de una pantalla de sección: «Asistencia» y, aparte, «lunes, 19 de octubre».
//
// Dice dos cosas que quien mira necesita saber y que la pantalla no repite: en qué sección del menú
// está y de qué día es lo que ve (una captura de pantalla no se puede fechar después). La forma —la
// raya y las mayúsculas— la da <CabeceraPagina>; acá solo se arma el texto, para que las seis
// pantallas de Asistencia no escriban cada una su propia fecha.
//
// El día sale de `hoyLima()` (la regla del repo: nada de escribir la zona horaria fuera de
// fecha-lima.ts) y se formatea con `fechaConDia`, la misma que usa el Dashboard.

import { createElement, type ReactNode } from "react";
import { hoyLima } from "@cayla-dynamic/shared";
import { fechaConDia } from "@/lib/admin/asistencia-hoy";
import { HoraLima } from "@/components/vidrio/hora-lima";
import { interruptoresVidrio } from "@/lib/vidrio";

export function sobretituloDeHoy(seccion: string): ReactNode {
  // «lunes 19 de octubre» → «lunes, 19 de octubre»: la coma es de Retail y se lee mejor en mayúsculas.
  const dia = fechaConDia(hoyLima()).replace(" ", ", ");
  // Dos piezas y no «Asistencia · lunes…» (Felipe, 2026-11-24: nunca «·» entre datos). La sección pesa más que la
  // fecha y, en un teléfono, la fecha baja a su propia línea en vez de partirse a la mitad.
  // Con el vidrio el saludo y la hora dejan la barra de arriba, y la hora sube aquí, dicha en la misma frase que el día
  // («lunes, 19 de octubre, 1:42 p. m.»). El nodo y no un texto: la hora cambia cada minuto.
  return createElement(
    "span",
    { className: "inline-flex flex-wrap items-baseline gap-x-3" },
    createElement("span", null, seccion),
    createElement("span", { className: "font-normal" }, dia, interruptoresVidrio().panel ? createElement(HoraLima) : null),
  );
}

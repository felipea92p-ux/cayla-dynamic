"use client";

// La hora de Lima en la línea de arriba del título: «ASISTENCIA · JUEVES, 5 DE NOVIEMBRE · 1:42 P. M.». Sale de `fecha-lima.ts`, como toda hora
// de este sistema. Arranca vacía porque el servidor no sabe a qué hora se abre la página: calcularla ahí daría un error de hidratación.

import { useEffect, useState } from "react";
import { horaLimaLegible } from "@cayla-dynamic/shared";

export function HoraLima() {
  const [hora, setHora] = useState<string | null>(null);
  useEffect(() => {
    const tic = () => setHora(horaLimaLegible());
    tic();
    // Cada 30 s y no cada 60: así el minuto nunca se queda 59 s atrasado.
    const id = window.setInterval(tic, 30_000);
    return () => window.clearInterval(id);
  }, []);
  return hora ? <span className="whitespace-nowrap tabular-nums print:hidden"> · {hora}</span> : null;
}

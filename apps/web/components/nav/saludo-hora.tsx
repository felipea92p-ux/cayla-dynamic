"use client";

// El saludo del centro de la barra superior: «Buenos días, Felipe» y debajo la
// hora de Lima.
//
// QUÉ PROMETE
//   Saluda según la hora de LIMA y la muestra al minuto. No sabe quién es la
//   persona: el nombre llega de fuera.
//
// QUÉ ASUME
//   La hora sale de `fecha-lima.ts`, nunca de `new Date().getHours()`: una Mac
//   mini de sede con la zona horaria mal puesta diría «buenas noches» a media
//   mañana, y la regla de la casa es que «qué hora es» tiene una sola versión.
//
// POR QUÉ ARRANCA VACÍO
//   El servidor no sabe la hora de quien abre la página y un saludo calculado
//   ahí saldría distinto al del navegador (error de hidratación). Antes de
//   montar se reserva el espacio sin texto, para que la barra no salte.

import { useEffect, useState } from "react";
import { horaDecimalLima, horaLimaLegible } from "@cayla-dynamic/shared";
import { cx } from "@/components/ui/cx";

// Corte del saludo, en hora de Lima: de 0 a 11:59 «Buenos días», de 12 a 18:59
// «Buenas tardes», desde las 19 «Buenas noches».
function saludoDe(hora: number): string {
  if (hora < 12) return "Buenos días";
  if (hora < 19) return "Buenas tardes";
  return "Buenas noches";
}

export function SaludoHora({
  nombreCompleto,
  className,
}: {
  /** Se saluda por el primer nombre; el completo queda en el título. */
  nombreCompleto?: string;
  className?: string;
}) {
  const [ahora, setAhora] = useState<{ saludo: string; hora: string } | null>(null);

  useEffect(() => {
    const tic = () => setAhora({ saludo: saludoDe(horaDecimalLima()), hora: horaLimaLegible() });
    tic();
    // Cada 30 s y no cada 60: así el minuto nunca se queda 59 s atrasado.
    const id = window.setInterval(tic, 30_000);
    return () => window.clearInterval(id);
  }, []);

  const primerNombre = nombreCompleto?.trim().split(/\s+/)[0];

  return (
    <div className={cx("min-w-0 text-center", className)} title={nombreCompleto}>
      <p className="truncate font-serif text-lg leading-tight text-tinta">
        {ahora && primerNombre ? `${ahora.saludo}, ${primerNombre}` : "\u00a0"}
      </p>
      <p className="text-xs tabular-nums leading-tight text-taupe">{ahora?.hora ?? "\u00a0"}</p>
    </div>
  );
}

"use client";

import { useEffect, useState } from "react";
import { TZ_LIMA } from "@cayla-dynamic/shared";

// Reloj central "estilo CAYLA": un anillo de línea fina (mismo lenguaje que el
// colibrí de una sola línea) con un indicador rojo que recorre los segundos.
// Hora en serif, fecha como etiqueta. Zona horaria fija America/Lima.

const fHora = new Intl.DateTimeFormat("es-PE", {
  timeZone: TZ_LIMA,
  hour: "2-digit",
  minute: "2-digit",
  hour12: false,
});
const fFecha = new Intl.DateTimeFormat("es-PE", {
  timeZone: TZ_LIMA,
  weekday: "long",
  day: "numeric",
  month: "short",
});
const fSeg = new Intl.DateTimeFormat("en-US", {
  timeZone: TZ_LIMA,
  second: "2-digit",
  hour12: false,
});

export function RelojCentral({ className = "" }: { className?: string }) {
  const [ahora, setAhora] = useState<Date | null>(null);

  useEffect(() => {
    setAhora(new Date());
    const t = setInterval(() => setAhora(new Date()), 1000);
    return () => clearInterval(t);
  }, []);

  const hora = ahora ? fHora.format(ahora) : "";
  const fecha = ahora ? fFecha.format(ahora).replace(", ", " · ").replace(".", "") : "";
  const seg = ahora ? Number(fSeg.formatToParts(ahora).find((p) => p.type === "second")?.value ?? 0) : 0;
  const angulo = seg * 6; // 360° / 60s

  return (
    <div className={`relative flex h-60 w-60 items-center justify-center ${className}`}>
      <svg viewBox="0 0 100 100" className="absolute inset-0 h-full w-full" aria-hidden>
        {/* anillo de línea fina */}
        <circle cx="50" cy="50" r="47" fill="none" stroke="var(--color-taupe)" strokeOpacity="0.4" strokeWidth="0.5" />
        {/* indicador rojo de los segundos */}
        <g transform={`rotate(${angulo} 50 50)`}>
          <line x1="50" y1="3.5" x2="50" y2="10.5" stroke="var(--color-rojo)" strokeWidth="1.6" strokeLinecap="round" />
        </g>
      </svg>
      <div className="flex flex-col items-center">
        <span className="font-serif text-6xl leading-none tabular-nums">{hora || " "}</span>
        <span className="etiqueta mt-3 text-taupe">{fecha}</span>
      </div>
    </div>
  );
}

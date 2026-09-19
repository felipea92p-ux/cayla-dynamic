"use client";

// Red de seguridad de la TERMINAL (donde el equipo marca asistencia). Pensada
// para pantalla táctil y para alguien sin contexto técnico: mensaje claro, botón
// grande, y si el problema sigue, que avise a su encargada.
import { useEffect } from "react";

export default function TerminalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error("Terminal con error:", error);
  }, [error]);

  return (
    <div className="flex min-h-screen flex-1 select-none flex-col items-center justify-center gap-8 bg-crema px-6 text-center text-tinta">
      <span className="colibri w-24 text-rojo/40" aria-hidden />
      <div className="space-y-3">
        <h1 className="font-serif text-4xl">Algo se detuvo</h1>
        <p className="mx-auto max-w-md text-base leading-relaxed text-taupe">
          La pantalla tuvo un problema. Toca el botón para volver a intentar. Si
          sigue igual, avisa a tu líder de equipo.
        </p>
      </div>
      <button
        onClick={reset}
        className="rounded-2xl bg-tinta px-10 py-5 text-lg font-medium text-crema transition-colors hover:bg-rojo-profundo"
      >
        Reintentar
      </button>
    </div>
  );
}

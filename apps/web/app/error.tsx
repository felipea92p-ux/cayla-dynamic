"use client";

// Red de seguridad visual: si una pantalla revienta mientras se dibuja, este
// límite la atrapa y muestra un mensaje amable en vez del pantallazo crudo de
// Next. "Reintentar" vuelve a montar la pantalla sin recargar toda la app.
import { useEffect } from "react";

export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    // Rastro en consola. Aquí engancharía después el "vigilante de errores".
    console.error("Pantalla con error:", error);
  }, [error]);

  return (
    <div className="flex min-h-screen flex-1 flex-col items-center justify-center gap-6 bg-crema px-6 text-center text-tinta">
      <span className="colibri w-20 text-rojo/40" aria-hidden />
      <div className="space-y-2">
        <h1 className="font-serif text-3xl">Algo salió mal</h1>
        <p className="mx-auto max-w-sm text-sm leading-relaxed text-taupe">
          Esta pantalla tuvo un tropiezo al cargar. No se perdió nada — puedes
          reintentar o volver al inicio.
        </p>
      </div>
      <div className="flex flex-wrap items-center justify-center gap-3">
        <button
          onClick={reset}
          className="rounded-lg bg-tinta px-5 py-2.5 font-medium text-crema transition-colors hover:bg-rojo-profundo"
        >
          Reintentar
        </button>
        <a
          href="/admin/dashboard"
          className="rounded-lg border border-sand px-5 py-2.5 font-medium text-tinta transition-colors hover:bg-papel"
        >
          Ir al inicio
        </a>
      </div>
      {error.digest && (
        <p className="text-xs text-taupe/60">Referencia: {error.digest}</p>
      )}
    </div>
  );
}

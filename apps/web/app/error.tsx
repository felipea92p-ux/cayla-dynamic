"use client";

// Red de seguridad visual: si una pantalla revienta mientras se dibuja, este
// límite la atrapa y muestra un mensaje amable en vez del pantallazo crudo de
// Next. "Reintentar" vuelve a montar la pantalla sin recargar toda la app.
import { useEffect } from "react";
import { usePathname } from "next/navigation";
import { Boton } from "@/components/ui/boton";

export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  const pathname = usePathname();
  // Ante la duda se manda a /mio, no al panel (mismo criterio que
  // admin/login/page.tsx): una integrante sin rol de panel que revienta una
  // pantalla dentro de "Lo mío" no puede aterrizar en /admin/dashboard, un
  // tablero de encargada que su propia RLS le devuelve casi vacío.
  const inicio = pathname?.startsWith("/mio") ? "/mio" : "/admin/dashboard";

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
        <Boton variante="primario" tamano="lg" onClick={reset}>
          Reintentar
        </Boton>
        <a
          href={inicio}
          className="rounded-control border border-sand px-5 py-2.5 font-medium text-tinta transition-colors hover:bg-papel"
        >
          Ir al inicio
        </a>
      </div>
      {error.digest && (
        <p className="text-xs text-taupe">Referencia: {error.digest}</p>
      )}
    </div>
  );
}

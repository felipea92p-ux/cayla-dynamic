"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { createTerminalSupabaseClient } from "@cayla-dynamic/database";
import { veredictoDeSesion } from "@/lib/terminal/sesion";

export default function TerminalIndexPage() {
  const router = useRouter();

  useEffect(() => {
    const supabase = createTerminalSupabaseClient();
    supabase.auth
      .getSession()
      // `session: null` NO quiere decir «este dispositivo no está vinculado».
      // También sale así cuando el token de acceso venció —dura una hora— y el
      // refresco no pudo salir a la red: las credenciales siguen guardadas. Esta
      // es la primera pantalla que abre la Mac mini al encender, o sea el peor
      // sitio posible para confundir «sin internet» con «sin vincular». Ver
      // `lib/terminal/sesion.ts`.
      .then(({ data, error }) =>
        veredictoDeSesion({ session: data.session, error }),
      )
      // Si ni siquiera se pudo preguntar, se sigue hacia el marcaje: esa pantalla
      // tiene su propia caché y su cola offline. Volver a pedir credenciales sería
      // dejar a la sede sin poder marcar por un corte de red.
      .catch(() => "no_se_pudo_saber" as const)
      .then((veredicto) => {
        router.replace(
          veredicto === "sin_vincular" ? "/terminal/vincular" : "/terminal/marcar",
        );
      });
  }, [router]);

  return (
    <div className="flex flex-1 items-center justify-center">
      <p className="text-taupe">Cargando…</p>
    </div>
  );
}

"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Boton } from "@/components/ui/boton";

export default function AdminIndexPage() {
  const router = useRouter();
  const [error, setError] = useState(false);
  const [intento, setIntento] = useState(0);

  useEffect(() => {
    let cancelado = false;
    setError(false);
    const supabase = createAdminSupabaseClient();
    supabase.auth
      .getSession()
      .then(({ data }) => {
        if (!cancelado) router.replace(data.session ? "/admin/dashboard" : "/admin/login");
      })
      .catch(() => {
        // Sin esto, un fallo de red (sede sin wifi, Supabase caído) dejaba el
        // "Cargando…" para siempre: no había ninguna señal de que algo falló,
        // solo un panel que nunca termina de entrar.
        if (!cancelado) setError(true);
      });
    return () => {
      cancelado = true;
    };
  }, [router, intento]);

  if (error) {
    return (
      <div className="flex flex-1 flex-col items-center justify-center gap-3 p-8 text-center">
        <p className="max-w-sm rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
          No se pudo comprobar tu sesión. Revisa la conexión e intenta de nuevo.
        </p>
        <Boton variante="enlace" onClick={() => setIntento((n) => n + 1)}>
          Reintentar
        </Boton>
      </div>
    );
  }

  return (
    <div className="flex flex-1 items-center justify-center">
      <p className="text-taupe" role="status" aria-live="polite">
        Cargando…
      </p>
    </div>
  );
}

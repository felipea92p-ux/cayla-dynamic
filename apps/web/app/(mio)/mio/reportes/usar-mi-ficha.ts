"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";

/**
 * La sesión y la ficha propia para las subpáginas de Reportes. Mismo camino que
 * /mio/boleta y /mio/bandeja: sin sesión se vuelve a /mio (que muestra el
 * ingreso); con sesión pero sin ficha enlazada, se dice por qué.
 */
export type MiFicha =
  | { estado: "cargando" }
  | { estado: "error"; mensaje: string }
  | { estado: "ok"; id: string; sedeBaseId: string | null };

export function useMiFicha() {
  const router = useRouter();
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const [ficha, setFicha] = useState<MiFicha>({ estado: "cargando" });

  useEffect(() => {
    let vivo = true;
    void (async () => {
      const { data: sesion } = await supabase.auth.getSession();
      if (!sesion.session) { router.replace("/mio"); return; }
      const { data: u } = await supabase.auth.getUser();
      const uid = u.user?.id;
      if (!uid) { if (vivo) setFicha({ estado: "error", mensaje: "No se pudo leer tu sesión. Vuelve a entrar." }); return; }
      const { data: p, error } = await supabase.from("personas")
        .select("id, sede_base_id").eq("auth_user_id", uid).maybeSingle();
      if (!vivo) return;
      if (error) { setFicha({ estado: "error", mensaje: "No se pudo comprobar tu ficha. Intenta de nuevo." }); return; }
      if (!p) {
        setFicha({ estado: "error", mensaje: "Tu cuenta todavía no está enlazada con tu ficha. Avisa a Desarrollo Organizacional." });
        return;
      }
      setFicha({ estado: "ok", id: p.id, sedeBaseId: p.sede_base_id });
    })();
    return () => { vivo = false; };
  }, [supabase, router]);

  return { supabase, ficha };
}

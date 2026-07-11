"use client";

import { useEffect, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";

/** Rol de la persona autenticada en el panel (admin/lider_do/supervisor_sede), o null mientras carga. */
export function useRolActual(): string | null {
  const [rol, setRol] = useState<string | null>(null);

  useEffect(() => {
    const supabase = createAdminSupabaseClient();
    supabase.auth.getUser().then(async ({ data }) => {
      if (!data.user) return;
      const { data: persona } = await supabase
        .from("personas")
        .select("rol")
        .eq("auth_user_id", data.user.id)
        .maybeSingle();
      if (persona) setRol(persona.rol as string);
    });
  }, []);

  return rol;
}

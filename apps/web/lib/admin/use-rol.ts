"use client";

import { useEffect, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";

export interface PersonaActual {
  id: string;
  rol: string;
  sedeBaseId: string;
  nombreCompleto: string;
  /**
   * Tiene contrato de trabajo (planilla o periodo de prueba). El rol dice qué
   * se abre; esto dice si puede ejercer poder disciplinario (RIT 2.9, 0510):
   * lo consulta `puedeTramitarDisciplina`.
   */
  enPlanilla: boolean;
}

/** Rol de la persona autenticada, o null mientras carga. */
export function useRolActual(): string | null {
  return usePersonaActual()?.rol ?? null;
}

/** Datos de la persona autenticada en el panel (id, rol, sede, nombre), o null mientras carga. */
export function usePersonaActual(): PersonaActual | null {
  const [persona, setPersona] = useState<PersonaActual | null>(null);

  useEffect(() => {
    const supabase = createAdminSupabaseClient();
    supabase.auth.getUser().then(async ({ data }) => {
      if (!data.user) return;
      const { data: p } = await supabase
        .from("personas")
        .select("id, rol, sede_base_id, nombres, apellidos, en_planilla")
        .eq("auth_user_id", data.user.id)
        .maybeSingle();
      if (p) setPersona({
        id: p.id as string,
        rol: p.rol as string,
        sedeBaseId: p.sede_base_id as string,
        nombreCompleto: `${p.nombres as string} ${p.apellidos as string}`,
        // Sin dato, NO: un vínculo desconocido no puede abrir un poder disciplinario.
        enPlanilla: p.en_planilla === true,
      });
    });
  }, []);

  return persona;
}

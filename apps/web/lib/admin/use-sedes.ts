"use client";

// Los nombres de las sedes por id, para quien necesita rotular a una persona con su sede
// (las fichas del <BuscadorPersona>). Se lee de la tabla `sedes`: nunca una lista a mano
// (regla 3 de CLAUDE.md). Si la consulta falla devuelve un mapa vacío: el buscador sigue
// sirviendo, solo sin fichas de sede.

import { useEffect, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";

export function useSedesPorId(): Map<string, string> {
  const [sedes, setSedes] = useState<Map<string, string>>(new Map());
  useEffect(() => {
    let vivo = true;
    void (async () => {
      const { data } = await createAdminSupabaseClient().from("sedes").select("id, nombre").order("nombre");
      if (vivo) setSedes(new Map(((data as { id: string; nombre: string }[] | null) ?? []).map((x) => [x.id, x.nombre])));
    })();
    return () => { vivo = false; };
  }, []);
  return sedes;
}

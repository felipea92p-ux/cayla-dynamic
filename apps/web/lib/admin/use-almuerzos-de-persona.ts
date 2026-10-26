"use client";

// Los almuerzos de UNA persona en un rango de días, para el detalle de Desempeño: cuándo salió, cuándo volvió y cuánto tiempo
// le permitía su horario. Se piden al abrir su detalle, no con la tabla de todo el equipo: son ~2 marcas por día de una sola
// persona, y para todo el equipo en «Todo el año» serían decenas de miles de filas que nadie ve.
//
// Si la consulta falla devuelve vacío: la tabla y el gráfico se dibujan como siempre, sin la columna de almuerzo. Un almuerzo
// que no se pudo traer NO se muestra como «no almorzó».

import { useEffect, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { almuerzosPorDia, llaveDia, TIPOS_DE_ALMUERZO, type AlmuerzoDelDia } from "@/lib/admin/almuerzo";

export interface AlmuerzosDePersona {
  /** Por fecha (día de Lima). */
  almuerzos: Map<string, AlmuerzoDelDia>;
  /** Minutos de refrigerio que le daba el horario aplicado ese día; solo si es mayor que 0. */
  permitido: Map<string, number>;
  cargado: boolean;
}

const VACIO: AlmuerzosDePersona = { almuerzos: new Map(), permitido: new Map(), cargado: false };

/** Un día de margen a cada lado: las marcas se guardan en UTC y el día de Lima puede caer en el siguiente. */
const sumaDias = (iso: string, n: number) => new Date(new Date(`${iso}T12:00:00Z`).getTime() + n * 86400000).toISOString().slice(0, 10);

export function useAlmuerzosDePersona(personaId: string, desde: string, hasta: string): AlmuerzosDePersona {
  const [res, setRes] = useState<{ clave: string; datos: AlmuerzosDePersona } | null>(null);
  const clave = `${personaId}|${desde}|${hasta}`;

  useEffect(() => {
    if (!personaId || !desde || !hasta) return;
    let vivo = true;
    void (async () => {
      const supabase = createAdminSupabaseClient();
      const [{ data: marcas, error: e1 }, { data: jornadas, error: e2 }] = await Promise.all([
        supabase.from("marcajes").select("persona_id, tipo, timestamp_marca")
          .eq("persona_id", personaId).in("tipo", [...TIPOS_DE_ALMUERZO]).is("anulada_at", null)
          .gte("timestamp_marca", `${sumaDias(desde, -1)}T00:00:00Z`).lte("timestamp_marca", `${sumaDias(hasta, 2)}T00:00:00Z`)
          .limit(5000),
        supabase.from("jornadas").select("fecha, horario_aplicado")
          .eq("persona_id", personaId).gte("fecha", desde).lte("fecha", hasta).limit(5000),
      ]);
      if (!vivo) return;
      const permitido = new Map<string, number>();
      if (!e2) {
        for (const j of (jornadas as { fecha: string; horario_aplicado: { refrigerio_min?: number } | null }[] | null) ?? []) {
          const r = Number(j.horario_aplicado?.refrigerio_min ?? 0);
          if (r > 0) permitido.set(j.fecha, r);
        }
      }
      const porDia = e1 ? new Map<string, AlmuerzoDelDia>() : almuerzosPorDia((marcas as { persona_id: string; tipo: string; timestamp_marca: string }[] | null) ?? []);
      // `almuerzosPorDia` llaveó por persona|fecha; el detalle es de UNA persona, así que se re-llavea por fecha sola.
      const almuerzos = new Map<string, AlmuerzoDelDia>();
      for (const [k, v] of porDia) if (k.startsWith(`${personaId}|`)) almuerzos.set(k.slice(personaId.length + 1), v);
      setRes({ clave, datos: { almuerzos, permitido, cargado: true } });
    })();
    return () => { vivo = false; };
  }, [clave, personaId, desde, hasta]);

  return res && res.clave === clave ? res.datos : VACIO;
}

export { llaveDia };

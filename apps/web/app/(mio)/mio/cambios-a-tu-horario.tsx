"use client";

import { useMemo } from "react";
import type { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { hoyLima, rangoDelDiaLima } from "@cayla-dynamic/shared";
import { sumarDias } from "@/lib/mi-semana";
import { ListaHistorial, useHistorialHorario } from "@/components/historial-horario/historial-horario";

/**
 * «Cambios a tu horario», debajo de «Tu semana» en Mis turnos: lo que le
 * cambiaron (o ella cambió) en su horario, su turno de un día, su puesto, su
 * jornada o su disponibilidad, en los últimos tres meses. Plegado: se consulta
 * de vez en cuando. No dice quién lo hizo —en «Lo mío» nunca se nombra a otra
 * persona—; el detalle completo lo tienen su líder y DO en «Cambios de horario».
 */
export function CambiosATuHorario({ supabase, personaId }: {
  supabase: ReturnType<typeof createAdminSupabaseClient>;
  personaId: string;
}) {
  const ids = useMemo(() => [personaId], [personaId]);
  const desde = rangoDelDiaLima(sumarDias(hoyLima(), -90)).inicio;
  const h = useHistorialHorario(supabase, ids, desde, "tu");
  if (h.error || h.cargando) return null;
  return (
    <details data-tour="mio-turnos-cambios" className="mt-4 border-t border-sand pt-3">
      <summary className="cursor-pointer text-sm font-medium">
        Cambios a tu horario {h.entradas.length > 0 ? `(${h.entradas.length} en los últimos 3 meses)` : "— ninguno en los últimos 3 meses"}
      </summary>
      {h.entradas.length > 0 && (
        <div className="mt-3">
          <ListaHistorial entradas={h.entradas} mostrarQuien={false} />
        </div>
      )}
    </details>
  );
}

"use client";

import { useMemo } from "react";
import type { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { hoyLima, rangoDelDiaLima, sumarDias } from "@cayla-dynamic/shared";
import { ListaHistorial, useHistorialHorario } from "@/components/historial-horario/historial-horario";
import { ListaPaginada } from "@/components/ui/paginas";

/**
 * «Cambios a tu horario», debajo de «Tu semana» en Mis turnos: lo que le
 * cambiaron (o ella cambió) en su horario, su turno de un día, su puesto, su
 * jornada o su disponibilidad, en los últimos tres meses. Plegado: se consulta
 * de vez en cuando. No dice quién lo hizo —en «Lo mío» nunca se nombra a otra
 * persona—; el detalle completo lo tienen su líder y DO en «Cambios de horario».
 *
 * De a 5 (Felipe, 2026-11-09: en el teléfono quedaba muy largo). La página se
 * corta por cambio, no por día: un día con siete cambios ocupa dos páginas y
 * su fecha se repite arriba de la segunda, que es justo lo que hace falta para
 * no leer esos cambios como del día anterior.
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
          <ListaPaginada items={h.entradas} etiqueta="Páginas de cambios a tu horario">
            {(entradas) => <ListaHistorial entradas={entradas} mostrarQuien={false} />}
          </ListaPaginada>
        </div>
      )}
    </details>
  );
}

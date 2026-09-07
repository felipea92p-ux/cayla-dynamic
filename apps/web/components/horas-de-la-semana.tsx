"use client";

import { useEffect, useMemo, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { hoyLima } from "@cayla-dynamic/shared";
import { cicloVigente, type DiaTrabajado } from "@/lib/admin/ciclo-sobretiempo";
import { comoReloj, diaYMes } from "@/lib/formato-mi-info";

/**
 * Cuántas horas lleva trabajadas en su semana (ciclo de 7 días) en curso.
 *
 * A PROPÓSITO no dice nada del tope de 48h ni usa la palabra «sobretiempo»:
 * el encabezado de `page.tsx` documenta que esta pantalla decidió (2026-08-31)
 * no mostrar el sobretiempo como horas por cobrar, porque invita a leerlo como
 * «me deben esto» antes de que se cruce el tope legal. Esta barra es un dato
 * neutro — cuántas horas ya trabajó esta semana — y nada más.
 *
 * Fetch propio, independiente del filtro Desde/Hasta de la pantalla: si
 * alguien lo angosta para mirar un mes viejo, este dato de "ahora mismo" no
 * debe romperse ni mentir — mismo motivo por el que "Cuándo te toca" pide sus
 * turnos aparte.
 */
export function HorasDeLaSemana({ personaId }: { personaId: string }) {
  const [dias, setDias] = useState<DiaTrabajado[] | null>(null);

  useEffect(() => {
    let vivo = true;
    const supabase = createAdminSupabaseClient();
    const hoy = hoyLima();
    // 10 días de sobra: un ciclo dura como mucho 7, y basta un día de hueco
    // para que `cicloVigente` decida que la racha ya se cortó.
    const [a, m, d] = hoy.split("-").map(Number);
    const desde = new Date(Date.UTC(a, m - 1, d - 9)).toISOString().slice(0, 10);
    void supabase
      .from("jornadas")
      .select("fecha, horas_trabajadas")
      .eq("persona_id", personaId)         // ← explícito, como todo lo de «Mi info»
      .gte("fecha", desde).lte("fecha", hoy)
      .then(({ data }) => {
        if (!vivo) return;
        setDias(
          ((data as { fecha: string; horas_trabajadas: number | null }[]) ?? [])
            .map((j) => ({ fecha: j.fecha, horas: j.horas_trabajadas ?? 0 }))
            // Un agregado histórico (>24h en un día) no es una jornada real —
            // mismo criterio que ya usa el resumen de arriba.
            .filter((j) => j.horas <= 24),
        );
      });
    return () => { vivo = false; };
  }, [personaId]);

  const ciclo = useMemo(() => (dias ? cicloVigente(dias, hoyLima()) : null), [dias]);

  if (!ciclo) return null;

  return (
    <section className="mb-6 rounded-2xl border border-sand p-5">
      <h2 className="mb-1 font-serif text-lg">Tu semana</h2>
      <p className="font-serif text-2xl leading-none">{comoReloj(ciclo.horas)}</p>
      <p className="mt-1 text-xs text-taupe">trabajadas desde el {diaYMes(ciclo.desde)}</p>
    </section>
  );
}

"use client";

import { useEffect, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { hoyLima } from "@cayla-dynamic/shared";
import { comoReloj } from "@/lib/formato-mi-info";
import type { Fila } from "@/app/(admin)/admin/planilla/page";

const fmtSoles = (n: number) => `S/ ${n.toFixed(2)}`;

/**
 * Un adelanto de «cómo se calculó tu pago», antes del link a la boleta
 * completa (`/mio/boleta`). La boleta ya existe entera —mismo componente que
 * usa admin, mismo desglose legal línea por línea—; lo único que faltaba era
 * que la pantalla principal no mostrara nada antes de hacer clic.
 *
 * MISMA REGLA que ya rige toda esta pantalla (ver cabecera de `page.tsx`):
 * SOLO el periodo actual, nunca uno cerrado. `fn_planilla_calcular_persona`
 * ya rechaza del lado del servidor pedir un periodo pasado (0339) — este
 * componente ni siquiera lo intenta, igual que `/mio/boleta`.
 */
export function MiBoletaResumen({ personaId }: { personaId: string }) {
  const [fila, setFila] = useState<(Fila & { sin_datos?: boolean }) | null>(null);

  useEffect(() => {
    let vivo = true;
    const supabase = createAdminSupabaseClient();
    void (async () => {
      const hoy = hoyLima();
      const { data: per } = await supabase
        .from("periodos_planilla")
        .select("id")
        .lte("fecha_ini", hoy).gte("fecha_fin", hoy)
        .maybeSingle();
      if (!vivo || !per) return;

      const { data: f } = await supabase.rpc("fn_planilla_calcular_persona", {
        p_persona_id: personaId,
        p_periodo_id: (per as { id: string }).id,
      });
      if (!vivo) return;
      setFila((f ?? null) as (Fila & { sin_datos?: boolean }) | null);
    })();
    return () => { vivo = false; };
  }, [personaId]);

  if (!fila || fila.sin_datos) return null;

  return (
    <div className="mt-3 border-t border-sand/70 pt-3">
      <p className="etiqueta text-taupe">Cómo va tu pago de este periodo</p>
      <p className="mt-1 font-serif text-2xl leading-none">{fmtSoles(fila.total)}</p>
      <dl className="mt-2 space-y-0.5 text-xs text-taupe">
        <div className="flex justify-between gap-4">
          <dt>Horas trabajadas</dt>
          <dd>{comoReloj(fila.horas_mes)}</dd>
        </div>
        <div className="flex justify-between gap-4">
          <dt>Sueldo base</dt>
          <dd>{fmtSoles(fila.pago_base)}</dd>
        </div>
        {(fila.monto_sobretiempo ?? 0) > 0 && (
          <div className="flex justify-between gap-4">
            <dt>Recargo por sobretiempo</dt>
            <dd>{fmtSoles(fila.monto_sobretiempo!)}</dd>
          </div>
        )}
        {(fila.descuento_afp ?? 0) > 0 && (
          <div className="flex justify-between gap-4">
            <dt>Descuento {fila.regimen_pension ?? "pensión"}</dt>
            <dd>−{fmtSoles(fila.descuento_afp!)}</dd>
          </div>
        )}
      </dl>
      <p className="mt-2 text-[11px] text-taupe">
        Esto es en vivo, con lo marcado hasta hoy — todavía puede cambiar antes de que cierre el periodo.
      </p>
    </div>
  );
}

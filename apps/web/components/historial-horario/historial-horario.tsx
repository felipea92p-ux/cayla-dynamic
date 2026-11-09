"use client";

import { useEffect, useState } from "react";
import type { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Insignia } from "@/components/ui/insignia";
import { diaTextoLima, horaTextoLima } from "@/lib/admin/historial-correcciones";
import { diaMes } from "@/lib/disponibilidad";
import {
  CAMPOS_DE_HORARIO, TIPOS, armarHistorial,
  type EntradaHistorial, type FilaAuditoria, type FilaDisponibilidad, type TipoCambio,
} from "@/lib/historial-horario";

/**
 * La línea de tiempo de cambios de horario (lib/historial-horario.ts). La usan
 * «Cambios de horario» en el panel y «Mis turnos» en «Lo mío». Lee lo que la
 * RLS deja ver a quien la abre: ella lo suyo, la líder su sede, DO todo.
 */

type Cliente = ReturnType<typeof createAdminSupabaseClient>;

export interface Historial {
  cargando: boolean;
  error: string | null;
  entradas: EntradaHistorial[];
}

const MAX_FILAS = 300;

export function useHistorialHorario(
  supabase: Cliente, personaIds: string[] | null, desdeIso: string, quien: "tu" | "ella",
): Historial {
  const [estado, setEstado] = useState<Historial>({ cargando: true, error: null, entradas: [] });
  const clave = personaIds?.join(",") ?? "";

  useEffect(() => {
    if (!personaIds || personaIds.length === 0) {
      return;
    }
    let vivo = true;
    void (async () => {
      const [{ data: aud, error: e1 }, disp] = await Promise.all([
        supabase.from("correcciones_auditoria")
          .select("id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_at, motivo, corregido_por")
          .in("persona_id", personaIds)
          .in("campo_modificado", Object.keys(CAMPOS_DE_HORARIO))
          .gte("corregido_at", desdeIso)
          .order("corregido_at", { ascending: false })
          .order("id", { ascending: false })
          .limit(MAX_FILAS),
        // Si la 0584 no estuviera, la tabla no existe: la disponibilidad se calla y el resto se muestra.
        supabase.from("disponibilidades")
          .select("id, persona_id, tipo, estado, vigente_desde, vigente_hasta, horario_fijo, registrada_por, creada_at, resuelta_por, resuelta_at, respuesta, registro_motivo, registro_detalle, disponibilidad_bloques(dia_semana, fecha, desde, hasta, estado)")
          .in("persona_id", personaIds)
          .gte("creada_at", desdeIso)
          .order("creada_at", { ascending: false })
          .limit(MAX_FILAS),
      ]);
      if (!vivo) return;
      if (e1) {
        setEstado({ cargando: false, error: "No se pudo leer el historial. Vuelve a intentarlo en un momento.", entradas: [] });
        return;
      }
      const disps = disp.error ? [] : ((disp.data as unknown as FilaDisponibilidad[]) ?? []);
      setEstado({
        cargando: false, error: null,
        entradas: armarHistorial((aud satisfies FilaAuditoria[]) ?? [], disps, quien),
      });
    })();
    return () => { vivo = false; };
    // `clave` resume personaIds: un arreglo nuevo con los mismos ids no vuelve a pedir.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [supabase, clave, desdeIso, quien]);

  return estado;
}

const ETIQUETA_TIPO = Object.fromEntries(TIPOS.map((t) => [t.valor, t.label])) as Record<TipoCambio, string>;

export function ListaHistorial({
  entradas, nombreDe, mostrarPersona = false, mostrarQuien = true,
}: {
  entradas: EntradaHistorial[];
  /** De id de persona a su nombre (para la persona afectada y para quien hizo el cambio). */
  nombreDe?: (id: string) => string;
  mostrarPersona?: boolean;
  mostrarQuien?: boolean;
}) {
  // Agrupado por el día en que se hizo el cambio (hora de Lima).
  const grupos: { dia: string; items: EntradaHistorial[] }[] = [];
  for (const e of entradas) {
    const dia = diaTextoLima(e.cuando) ?? "";
    const ult = grupos[grupos.length - 1];
    if (ult && ult.dia === dia) ult.items.push(e);
    else grupos.push({ dia, items: [e] });
  }

  return (
    <ol className="flex flex-col gap-4">
      {grupos.map((g) => (
        <li key={g.dia + g.items[0].clave}>
          <p className="mb-2 text-xs font-medium uppercase tracking-wide text-taupe">{g.dia}</p>
          <ul className="flex flex-col gap-2">
            {g.items.map((e) => (
              <li key={e.clave} className="flex flex-col gap-1 rounded-control bg-hueso px-3 py-2 text-sm">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="tabular-nums text-taupe">{horaTextoLima(e.cuando)}</span>
                  {mostrarPersona && nombreDe && <strong>{nombreDe(e.personaId)}</strong>}
                  <span className="font-medium">{e.accion}</span>
                  <Insignia tamano="sm" atenuada>{ETIQUETA_TIPO[e.tipo]}</Insignia>
                  {e.dia && <span className="text-taupe">· para el {diaMes(e.dia)}</span>}
                </div>
                <p>{e.detalle}</p>
                {e.motivo && <p className="text-taupe">Motivo: {e.motivo}</p>}
                {mostrarQuien && e.quien && nombreDe && <p className="text-xs text-taupe">Lo hizo {nombreDe(e.quien)}</p>}
              </li>
            ))}
          </ul>
        </li>
      ))}
    </ol>
  );
}

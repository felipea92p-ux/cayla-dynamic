"use client";

import { useEffect, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { fechasDelRango } from "@/lib/admin/jornada-esperada";
import { comoReloj, diaYMes } from "@/lib/formato-mi-info";

interface PeriodoTendencia {
  id: string;
  fecha_ini: string;
  fecha_fin: string;
  dias: number;         // largo del periodo — no son todos iguales (20 a 46 días)
  horas: number;
  diasTrabajados: number;
  tardanzas: number;
}

/**
 * Cómo vienen tus últimos periodos, uno al lado del otro.
 *
 * A PROPÓSITO no muestra ningún monto, ni siquiera del periodo actual: la
 * cabecera de `page.tsx` documenta que esta pantalla solo enseña dinero del
 * periodo EN CURSO (ver `MiBoletaResumen`), porque los periodos ya cerrados
 * arrastraron errores de cálculo reales que su foto congelada
 * (`planilla_pagada_detalle`) puede no reflejar. Mezclar esa foto con una
 * comparación de tendencia sería enseñar un número que puede estar mal sin
 * ninguna de las advertencias que sí tiene `/mio/boleta`. Horas y tardanzas
 * no tienen ese problema: salen de `jornadas`, la fuente de verdad siempre
 * vigente.
 *
 * Cada fila muestra los días del periodo al lado de las horas — los periodos
 * no duran lo mismo (20 a 46 días, CHECK de la 0025), así que comparar solo
 * horas totales compararía peras con manzanas.
 */
export function MiTendencia({ personaId }: { personaId: string }) {
  const [periodos, setPeriodos] = useState<PeriodoTendencia[] | null>(null);

  useEffect(() => {
    let vivo = true;
    const supabase = createAdminSupabaseClient();
    void (async () => {
      const { data: pers } = await supabase
        .from("periodos_planilla")
        .select("id, fecha_ini, fecha_fin, estado")
        .order("fecha_fin", { ascending: false })
        .limit(6);
      if (!vivo || !pers || pers.length === 0) { setPeriodos([]); return; }

      const lista = pers as { id: string; fecha_ini: string; fecha_fin: string; estado: string }[];
      const cerrados = lista.filter((p) => p.estado === "pagado");
      const abiertos = lista.filter((p) => p.estado !== "pagado");

      // Dos grupos, no un array de tamaño variable: mezclar la respuesta de
      // Supabase (`{data, error}`) con la de la RPC por-abierto en un solo
      // `Promise.all` de longitud dinámica le quita a TypeScript la forma de
      // saber qué trae cada posición — con dos promesas fijas sí la sabe.
      const [{ data: fotos }, calculosAbiertos] = await Promise.all([
        cerrados.length > 0
          ? supabase.from("v_planilla_pagada")
              .select("periodo_id, horas_mes, dias_trabajados")
              .eq("persona_id", personaId)
              .in("periodo_id", cerrados.map((p) => p.id))
          : Promise.resolve({ data: [] as { periodo_id: string; horas_mes: number; dias_trabajados: number }[] }),
        Promise.all(
          abiertos.map((p) =>
            supabase.rpc("fn_planilla_calcular_persona", { p_persona_id: personaId, p_periodo_id: p.id })
              .then(({ data }) => ({ periodo_id: p.id, fila: data as { horas_mes?: number; dias_trabajados?: number } | null })),
          ),
        ),
      ]);
      if (!vivo) return;

      const horasPorPeriodo = new Map<string, { horas: number; dias: number }>();
      for (const f of (fotos as { periodo_id: string; horas_mes: number; dias_trabajados: number }[] | null) ?? []) {
        horasPorPeriodo.set(f.periodo_id, { horas: f.horas_mes, dias: f.dias_trabajados });
      }
      for (const c of calculosAbiertos) {
        horasPorPeriodo.set(c.periodo_id, {
          horas: c.fila?.horas_mes ?? 0,
          dias: c.fila?.dias_trabajados ?? 0,
        });
      }

      // Tardanzas: un solo fetch sobre el rango completo de los periodos
      // pedidos, en vez de uno por periodo — mismo espíritu que ya usa
      // `cargar()` más arriba en esta pantalla.
      const desde = lista.reduce((m, p) => (p.fecha_ini < m ? p.fecha_ini : m), lista[0].fecha_ini);
      const hasta = lista.reduce((m, p) => (p.fecha_fin > m ? p.fecha_fin : m), lista[0].fecha_fin);
      const [{ data: js }, { data: perd }] = await Promise.all([
        supabase.from("jornadas").select("fecha, minutos_tarde")
          .eq("persona_id", personaId).gte("fecha", desde).lte("fecha", hasta),
        supabase.from("tardanzas_justificadas").select("fecha")
          .eq("persona_id", personaId).gte("fecha", desde).lte("fecha", hasta),
      ]);
      if (!vivo) return;
      const perdonadas = new Set(((perd as { fecha: string }[]) ?? []).map((t) => t.fecha));
      const tardes = ((js as { fecha: string; minutos_tarde: number | null }[]) ?? [])
        .filter((j) => (j.minutos_tarde ?? 0) > 0 && !perdonadas.has(j.fecha))
        .map((j) => j.fecha);

      setPeriodos(
        [...lista].reverse().map((p) => ({
          id: p.id,
          fecha_ini: p.fecha_ini,
          fecha_fin: p.fecha_fin,
          dias: fechasDelRango(p.fecha_ini, p.fecha_fin).length,
          horas: horasPorPeriodo.get(p.id)?.horas ?? 0,
          diasTrabajados: horasPorPeriodo.get(p.id)?.dias ?? 0,
          tardanzas: tardes.filter((f) => f >= p.fecha_ini && f <= p.fecha_fin).length,
        })),
      );
    })();
    return () => { vivo = false; };
  }, [personaId]);

  if (!periodos || periodos.length < 2) return null; // una tendencia necesita al menos dos puntos

  return (
    <section className="mb-6 rounded-2xl border border-sand p-5">
      <h2 className="mb-3 font-serif text-lg">Tus últimos periodos</h2>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-sand text-left">
              <th className="etiqueta pb-2 font-normal text-taupe">Periodo</th>
              <th className="etiqueta pb-2 font-normal text-taupe">Días trabajados</th>
              <th className="etiqueta pb-2 font-normal text-taupe">Horas</th>
              <th className="etiqueta pb-2 text-right font-normal text-taupe">Tardanzas</th>
            </tr>
          </thead>
          <tbody>
            {periodos.map((p) => (
              <tr key={p.id} className="border-b border-sand/60">
                <td className="py-2">{diaYMes(p.fecha_ini)} – {diaYMes(p.fecha_fin)}</td>
                <td className="py-2 text-taupe">{p.diasTrabajados} de {p.dias}</td>
                <td className="py-2">{comoReloj(p.horas)}</td>
                <td className="py-2 text-right">{p.tardanzas}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

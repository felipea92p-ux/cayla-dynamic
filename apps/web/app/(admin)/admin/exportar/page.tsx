"use client";

import { useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { descargarCsv, generarCsv } from "@/lib/admin/csv";
import { traerTodo } from "@/lib/admin/traer-todo";
import { AdminNav } from "../nav";

function fechaHoyISO() {
  return new Date().toISOString().slice(0, 10);
}

export default function ExportarPage() {
  const [desde, setDesde] = useState(fechaHoyISO());
  const [hasta, setHasta] = useState(fechaHoyISO());
  const [cargando, setCargando] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function exportar() {
    setCargando(true);
    setError(null);

    const supabase = createAdminSupabaseClient();
    // Por lotes: sin esto PostgREST cortaba en 1000 filas y, como el orden es
    // ascendente por fecha, lo que se perdía eran los días MÁS RECIENTES — y el
    // archivo se descargaba sin ninguna marca de estar incompleto.
    const [{ data, error }, extraRes] = await Promise.all([
      traerTodo<any>((ini, fin) =>
        supabase
          .from("jornadas")
          .select("fecha, persona_id, entrada_ts, salida_final_ts, minutos_tarde, horas_trabajadas, horas_extra_detectadas, estado, personas(nombres, apellidos), sedes(codigo)")
          .gte("fecha", desde)
          .lte("fecha", hasta)
          .order("fecha")
          .order("persona_id")
          .range(ini, fin),
      ),
      supabase.rpc("fn_jornadas_extra", { p_desde: desde, p_hasta: hasta }),
    ]);

    setCargando(false);

    if (error) {
      setError(error.message);
      return;
    }

    // minutos_salida_temprana llega vía RPC (el caché de PostgREST no expone la columna);
    // si la RPC falla, degradamos a columna vacía sin romper el export.
    const extras = extraRes.error
      ? []
      : ((extraRes.data as { persona_id: string; fecha: string; minutos_salida_temprana: number }[] | null) ?? []);
    const minutosPorClave = new Map(
      extras.map((e) => [e.persona_id + "|" + e.fecha, e.minutos_salida_temprana]),
    );

    const filas = (data ?? []).map((j: any) => ({
      fecha: j.fecha,
      sede: j.sedes?.codigo ?? "",
      nombres: j.personas?.nombres ?? "",
      apellidos: j.personas?.apellidos ?? "",
      entrada: j.entrada_ts ?? "",
      salida_final: j.salida_final_ts ?? "",
      minutos_tarde: j.minutos_tarde ?? "",
      minutos_salida_temprana: minutosPorClave.get(j.persona_id + "|" + j.fecha) ?? "",
      horas_trabajadas: j.horas_trabajadas ?? "",
      horas_extra: j.horas_extra_detectadas ?? "",
      estado: j.estado,
    }));

    const csv = generarCsv(filas, [
      "fecha",
      "sede",
      "nombres",
      "apellidos",
      "entrada",
      "salida_final",
      "minutos_tarde",
      "minutos_salida_temprana",
      "horas_trabajadas",
      "horas_extra",
      "estado",
    ]);

    descargarCsv(`dynamic-asistencia-${desde}_a_${hasta}.csv`, csv);
  }

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <div className="flex flex-1 flex-col items-center justify-center gap-6 p-8">
      <h1 className="font-serif text-2xl">Exportar asistencia (CSV)</h1>
      <div className="flex items-end gap-4">
        <label className="flex flex-col gap-1 text-sm">
          Desde
          <input
            type="date"
            value={desde}
            onChange={(e) => setDesde(e.target.value)}
            className="rounded-lg border px-3 py-2"
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          Hasta
          <input
            type="date"
            value={hasta}
            onChange={(e) => setHasta(e.target.value)}
            className="rounded-lg border px-3 py-2"
          />
        </label>
        <button
          onClick={exportar}
          disabled={cargando}
          className="rounded-lg bg-tinta px-5 py-2 font-medium text-crema disabled:opacity-50"
        >
          {cargando ? "Generando…" : "Descargar CSV"}
        </button>
      </div>
      {error && <p className="text-sm text-rojo">{error}</p>}
      <p className="max-w-md text-center text-xs text-taupe">
        Incluye a todas las personas y sedes visibles para tu rol. Ábrelo directamente con Excel o
        Google Sheets.
      </p>
      </div>
    </div>
  );
}

"use client";

import { useState } from "react";
import { createBrowserSupabaseClient } from "@cayla-dynamic/database";
import { descargarCsv, generarCsv } from "@/lib/admin/csv";

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

    const supabase = createBrowserSupabaseClient();
    const { data, error } = await supabase
      .from("jornadas")
      .select("fecha, entrada_ts, salida_final_ts, minutos_tarde, horas_trabajadas, estado, personas(nombres, apellidos), sedes(codigo)")
      .gte("fecha", desde)
      .lte("fecha", hasta)
      .order("fecha");

    setCargando(false);

    if (error) {
      setError(error.message);
      return;
    }

    const filas = (data ?? []).map((j: any) => ({
      fecha: j.fecha,
      sede: j.sedes?.codigo ?? "",
      nombres: j.personas?.nombres ?? "",
      apellidos: j.personas?.apellidos ?? "",
      entrada: j.entrada_ts ?? "",
      salida_final: j.salida_final_ts ?? "",
      minutos_tarde: j.minutos_tarde ?? "",
      horas_trabajadas: j.horas_trabajadas ?? "",
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
      "horas_trabajadas",
      "estado",
    ]);

    descargarCsv(`dynamic-asistencia-${desde}_a_${hasta}.csv`, csv);
  }

  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-6 p-8">
      <h1 className="text-xl font-semibold">Exportar asistencia (CSV)</h1>
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
          className="rounded-lg bg-black px-5 py-2 font-medium text-white disabled:opacity-50"
        >
          {cargando ? "Generando…" : "Descargar CSV"}
        </button>
      </div>
      {error && <p className="text-sm text-red-600">{error}</p>}
      <p className="max-w-md text-center text-xs text-neutral-500">
        Incluye a todas las personas y sedes visibles para tu rol. Ábrelo directamente con Excel o
        Google Sheets.
      </p>
    </div>
  );
}

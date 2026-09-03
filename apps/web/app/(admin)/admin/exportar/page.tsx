"use client";

import { useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { descargarCsv, generarCsv } from "@/lib/admin/csv";
import { traerTodo } from "@/lib/admin/traer-todo";
import { rangoDelDiaLima } from "@cayla-dynamic/shared";
import { AdminNav } from "../nav";

function fechaHoyISO() {
  return new Date().toISOString().slice(0, 10);
}

export default function ExportarPage() {
  const [desde, setDesde] = useState(fechaHoyISO());
  const [hasta, setHasta] = useState(fechaHoyISO());
  const [cargando, setCargando] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Fechas propias para el reporte de inspección: es un pedido distinto (evidencia de
  // un periodo cerrado, no la asistencia del momento) y compartir el rango de arriba
  // haría que mover una fecha para un export moviera sin querer la del otro.
  const [desdeInsp, setDesdeInsp] = useState(fechaHoyISO());
  const [hastaInsp, setHastaInsp] = useState(fechaHoyISO());
  const [cargandoInsp, setCargandoInsp] = useState(false);
  const [errorInsp, setErrorInsp] = useState<string | null>(null);

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

  // Reporte para inspección: el crudo de marcajes (uno por uno, con su origen y si
  // fue anulado) más la auditoría de correcciones (qué se cambió, quién y por qué).
  // Es evidencia distinta de "Exportar asistencia": ese de arriba resume horas por
  // día; esto prueba que ningún marcaje se borró — se anula, nunca se borra — y que
  // toda corrección quedó con motivo. El resumen de jornadas por día ya lo cubre el
  // export de arriba; repetirlo acá sería la misma tabla dos veces.
  async function exportarInspeccion() {
    setCargandoInsp(true);
    setErrorInsp(null);

    const supabase = createAdminSupabaseClient();
    const { inicio } = rangoDelDiaLima(desdeInsp);
    const { fin } = rangoDelDiaLima(hastaInsp);

    const [marcajesRes, correccionesRes, personasRes] = await Promise.all([
      traerTodo<any>((ini, finRango) =>
        supabase
          .from("marcajes")
          .select(
            "timestamp_marca, persona_id, tipo, motivo_otro, origen, estado_revision, " +
              "server_received_at, anulada_at, anulada_por, anulada_motivo, confirmo_sin_refrigerio",
          )
          .gte("timestamp_marca", inicio)
          .lte("timestamp_marca", fin)
          .order("timestamp_marca")
          .range(ini, finRango),
      ),
      traerTodo<any>((ini, finRango) =>
        supabase
          .from("correcciones_auditoria")
          .select("persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por, corregido_at")
          .gte("corregido_at", inicio)
          .lte("corregido_at", fin)
          .order("corregido_at")
          .range(ini, finRango),
      ),
      // Un solo mapa id → nombre/sede, para resolver tanto la persona del marcaje
      // como quién corrigió — RLS ya limita esto a lo visible para el rol de quien pide.
      supabase.from("personas").select("id, nombres, apellidos, sedes:sede_base_id(codigo)"),
    ]);

    setCargandoInsp(false);
    const err = marcajesRes.error ?? correccionesRes.error ?? personasRes.error;
    if (err) { setErrorInsp(err.message); return; }

    const nombrePorId = new Map(
      ((personasRes.data as any[]) ?? []).map((p) => [p.id as string, `${p.nombres} ${p.apellidos}`.trim()]),
    );
    const sedePorId = new Map(
      ((personasRes.data as any[]) ?? []).map((p) => [p.id as string, p.sedes?.codigo ?? ""]),
    );
    const quien = (id: string | null) => (id ? (nombrePorId.get(id) ?? id) : "");

    const filasMarcajes = ((marcajesRes.data as any[]) ?? []).map((m) => ({
      fecha_hora: m.timestamp_marca,
      persona: quien(m.persona_id),
      sede: sedePorId.get(m.persona_id) ?? "",
      tipo: m.tipo,
      motivo_otro: m.motivo_otro ?? "",
      origen: m.origen,
      estado_revision: m.estado_revision,
      recibido_por_el_servidor: m.server_received_at,
      anulada_at: m.anulada_at ?? "",
      anulada_por: quien(m.anulada_por),
      anulada_motivo: m.anulada_motivo ?? "",
      // 0350: solo tiene valor en una salida_final donde el terminal preguntó
      // por no haber refrigerio marcado ese día. Vacío no es "no aplica" y
      // "no" a la vez — por eso se distingue "sin preguntar" de "sí"/"no".
      confirmo_trabajo_sin_refrigerio:
        m.confirmo_sin_refrigerio === null ? "" : m.confirmo_sin_refrigerio ? "sí" : "no",
    }));
    const csvMarcajes = generarCsv(filasMarcajes, [
      "fecha_hora", "persona", "sede", "tipo", "motivo_otro", "origen", "estado_revision",
      "recibido_por_el_servidor", "anulada_at", "anulada_por", "anulada_motivo",
      "confirmo_trabajo_sin_refrigerio",
    ]);

    const filasCorrecciones = ((correccionesRes.data as any[]) ?? []).map((c) => ({
      persona: quien(c.persona_id),
      campo_modificado: c.campo_modificado,
      valor_anterior: c.valor_anterior ?? "",
      valor_nuevo: c.valor_nuevo ?? "",
      motivo: c.motivo,
      corregido_por: quien(c.corregido_por),
      corregido_at: c.corregido_at,
    }));
    const csvCorrecciones = generarCsv(filasCorrecciones, [
      "persona", "campo_modificado", "valor_anterior", "valor_nuevo", "motivo", "corregido_por", "corregido_at",
    ]);

    descargarCsv(`dynamic-inspeccion-marcajes-${desdeInsp}_a_${hastaInsp}.csv`, csvMarcajes);
    descargarCsv(`dynamic-inspeccion-correcciones-${desdeInsp}_a_${hastaInsp}.csv`, csvCorrecciones);
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

      <div className="mt-4 w-full max-w-lg border-t border-sand pt-6" />

      <h2 className="font-serif text-xl">Reporte para inspección</h2>
      <div className="flex items-end gap-4">
        <label className="flex flex-col gap-1 text-sm">
          Desde
          <input
            type="date"
            value={desdeInsp}
            onChange={(e) => setDesdeInsp(e.target.value)}
            className="rounded-lg border px-3 py-2"
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          Hasta
          <input
            type="date"
            value={hastaInsp}
            onChange={(e) => setHastaInsp(e.target.value)}
            className="rounded-lg border px-3 py-2"
          />
        </label>
        <button
          onClick={exportarInspeccion}
          disabled={cargandoInsp}
          className="rounded-lg bg-tinta px-5 py-2 font-medium text-crema disabled:opacity-50"
        >
          {cargandoInsp ? "Generando…" : "Descargar reporte"}
        </button>
      </div>
      {errorInsp && <p className="text-sm text-rojo">{errorInsp}</p>}
      <p className="max-w-md text-center text-xs text-taupe">
        Descarga dos archivos: el marcaje crudo del periodo (con su origen, si fue
        anulado — nunca se borra — y si la persona confirmó al marcar que trabajó sin
        refrigerio) y la auditoría de correcciones (qué se cambió, quién y por qué). Es
        la evidencia de que nada se editó sin dejar rastro. Para el resumen de horas
        por día, usa &quot;Exportar asistencia&quot; arriba.
      </p>
      </div>
    </div>
  );
}

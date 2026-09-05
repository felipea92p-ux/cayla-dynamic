"use client";

import { useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { descargarCsv, generarCsv } from "@/lib/admin/csv";
import { traerTodo } from "@/lib/admin/traer-todo";
import { fechaLima } from "@cayla-dynamic/shared";
import { AdminNav } from "../nav";

function fechaHoyISO() {
  return new Date().toISOString().slice(0, 10);
}

function sumarDiasISO(iso: string, n: number): string {
  const [y, m, d] = iso.split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  dt.setUTCDate(dt.getUTCDate() + n);
  return dt.toISOString().slice(0, 10);
}

// Cuánto más allá de `hasta` se busca una corrección hecha después del hecho
// (alguien corrige hoy un marcaje de hace tres semanas). De sobra para el uso
// real; si algún día no alcanza, se sube el número, no la lógica.
const MARGEN_CORRECCIONES_DIAS = 60;

interface MarcajeExport {
  fecha_jornada: string | null;
  timestamp_marca: string;
  tipo: string;
  origen: string;
  estado_revision: string;
  anulada_at: string | null;
  anulada_motivo: string | null;
  persona_id: string;
  personas: { nombres: string; apellidos: string } | null;
  sedes: { codigo: string } | null;
}

interface CorreccionExport {
  marcaje_id: string | null;
  persona_id: string;
  corregido_por: string;
  campo_modificado: string;
  valor_anterior: string | null;
  valor_nuevo: string | null;
  motivo: string;
  corregido_at: string;
  marcajes: { fecha_jornada: string | null } | null;
}

/**
 * El paquete de evidencia de un periodo: marcajes crudos + correcciones, para
 * completar lo que ya exporta `jornadas` (el resumen ya calculado). Nadie los
 * juntaba — ni `exportar` ni `reporte-sede` tocan `correcciones_auditoria`, y
 * es la única forma de mostrar en una inspección que nada se editó sin dejar
 * rastro, aprovechando que el diseño ya es append-only.
 */
async function exportarPaquete(
  supabase: ReturnType<typeof createAdminSupabaseClient>,
  desde: string,
  hasta: string,
): Promise<string | null> {
  const { data: marcajes, error: eM } = await traerTodo<MarcajeExport>((ini, fin) =>
    supabase
      .from("marcajes")
      // `personas!marcajes_persona_id_fkey`, no `personas(...)` a secas: desde
      // que `anulada_por` también apunta a `personas` (0081), un embed sin
      // desambiguar es un error en tiempo de ejecución, no de tipos — acá lo
      // atajó `tsc`, pero PostgREST lo habría devuelto como un 300 recién al
      // usar la pantalla.
      .select("fecha_jornada, timestamp_marca, tipo, origen, estado_revision, anulada_at, anulada_motivo, persona_id, personas!marcajes_persona_id_fkey(nombres, apellidos), sedes(codigo)")
      .gte("fecha_jornada", desde)
      .lte("fecha_jornada", hasta)
      .order("fecha_jornada")
      .order("persona_id")
      .range(ini, fin),
  );
  if (eM) return `No se pudo traer los marcajes: ${eM.message}`;

  const filasMarcajes = (marcajes ?? []).map((m) => ({
    fecha_jornada: m.fecha_jornada ?? "",
    sede: m.sedes?.codigo ?? "",
    nombres: m.personas?.nombres ?? "",
    apellidos: m.personas?.apellidos ?? "",
    tipo: m.tipo,
    timestamp_marca: m.timestamp_marca,
    origen: m.origen,
    estado_revision: m.estado_revision,
    anulada_at: m.anulada_at ?? "",
    anulada_motivo: m.anulada_motivo ?? "",
  }));
  descargarCsv(
    `dynamic-marcajes-${desde}_a_${hasta}.csv`,
    generarCsv(filasMarcajes, [
      "fecha_jornada", "sede", "nombres", "apellidos", "tipo",
      "timestamp_marca", "origen", "estado_revision", "anulada_at", "anulada_motivo",
    ]),
  );

  // Una corrección pertenece al periodo del MARCAJE que toca, no al día en que
  // se hizo — así que se trae con margen por `corregido_at` (lo único que se
  // puede acotar en la consulta) y se recorta acá por la fecha real del
  // marcaje. `.lt` con un día exclusivo de sobra, no `.lte`, porque comparar
  // un timestamptz contra una fecha pelada se mide en medianoche UTC y
  // recortaría las correcciones de la tarde de Lima del último día.
  const limiteSuperior = sumarDiasISO(hasta, MARGEN_CORRECCIONES_DIAS + 2);
  const { data: correcciones, error: eC } = await traerTodo<CorreccionExport>((ini, fin) =>
    supabase
      .from("correcciones_auditoria")
      .select("marcaje_id, persona_id, corregido_por, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_at, marcajes(fecha_jornada)")
      .gte("corregido_at", desde)
      .lt("corregido_at", limiteSuperior)
      .order("corregido_at")
      .range(ini, fin),
  );
  if (eC) return `No se pudo traer las correcciones: ${eC.message}`;

  // Sin marcaje asociado (ej. un ajuste de contrato), se cuenta por cuándo se
  // hizo la corrección — es lo único que tiene. `fechaLima`, nunca slice(0,10)
  // sobre el timestamp crudo: una corrección de las 7pm de Lima es casi
  // medianoche UTC, y el slice le pondría el día siguiente.
  const relevantes = (correcciones ?? []).filter((c) => {
    const fechaDeReferencia: string = c.marcajes?.fecha_jornada ?? fechaLima(c.corregido_at);
    return fechaDeReferencia >= desde && fechaDeReferencia <= hasta;
  });

  const idsPersonas = new Set<string>();
  for (const c of relevantes) {
    idsPersonas.add(c.persona_id);
    idsPersonas.add(c.corregido_por);
  }
  const { data: personas, error: eP } = idsPersonas.size > 0
    ? await supabase.from("personas").select("id, nombres, apellidos").in("id", Array.from(idsPersonas))
    : { data: [] as { id: string; nombres: string; apellidos: string }[], error: null };
  if (eP) return `No se pudo resolver a quién corresponde cada corrección: ${eP.message}`;
  const nombrePorId = new Map((personas ?? []).map((p) => [p.id, `${p.nombres} ${p.apellidos}`]));

  const filasCorr = relevantes.map((c) => ({
    fecha_marcaje: c.marcajes?.fecha_jornada ?? "",
    persona: nombrePorId.get(c.persona_id) ?? c.persona_id,
    campo_modificado: c.campo_modificado,
    valor_anterior: c.valor_anterior ?? "",
    valor_nuevo: c.valor_nuevo ?? "",
    motivo: c.motivo,
    corregido_por: nombrePorId.get(c.corregido_por) ?? c.corregido_por,
    corregido_at: c.corregido_at,
  }));
  descargarCsv(
    `dynamic-correcciones-${desde}_a_${hasta}.csv`,
    generarCsv(filasCorr, [
      "fecha_marcaje", "persona", "campo_modificado", "valor_anterior",
      "valor_nuevo", "motivo", "corregido_por", "corregido_at",
    ]),
  );

  return null;
}

export default function ExportarPage() {
  const [desde, setDesde] = useState(fechaHoyISO());
  const [hasta, setHasta] = useState(fechaHoyISO());
  const [incluirPaquete, setIncluirPaquete] = useState(false);
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

    if (error) {
      setError(error.message);
      setCargando(false);
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

    if (!incluirPaquete) {
      setCargando(false);
      return;
    }

    const err = await exportarPaquete(supabase, desde, hasta);
    setCargando(false);
    if (err) setError(err);
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
      <label className="flex items-center gap-2 text-sm text-taupe">
        <input
          type="checkbox"
          checked={incluirPaquete}
          onChange={(e) => setIncluirPaquete(e.target.checked)}
        />
        Incluir también los marcajes y las correcciones del periodo (paquete listo para una inspección)
      </label>
      {error && <p className="text-sm text-rojo">{error}</p>}
      <p className="max-w-md text-center text-xs text-taupe">
        Incluye a todas las personas y sedes visibles para tu rol. Ábrelo directamente con Excel o
        Google Sheets.
      </p>
      </div>
    </div>
  );
}

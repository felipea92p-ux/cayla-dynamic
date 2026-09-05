"use client";

import { useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { descargarCsv, generarCsv } from "@/lib/admin/csv";
import { traerTodo } from "@/lib/admin/traer-todo";
import { hoyLima, puedeExportarAsistencia, rangoDelDiaLima, TIPO_MARCA_LABELS, type TipoMarca } from "@cayla-dynamic/shared";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { AdminNav } from "../nav";

interface JornadaFila {
  fecha: string;
  persona_id: string;
  entrada_ts: string | null;
  salida_final_ts: string | null;
  minutos_tarde: number | null;
  horas_trabajadas: number | null;
  horas_extra_detectadas: number;
  estado: string;
  personas: { nombres: string; apellidos: string } | null;
  sedes: { codigo: string } | null;
}

interface PersonaNombre {
  id: string;
  nombres: string;
  apellidos: string;
}

interface MarcajeFila {
  persona_id: string;
  timestamp_marca: string;
  tipo: TipoMarca;
  origen: string;
  estado_revision: string;
  motivo_otro: string | null;
  anulada_at: string | null;
  anulada_motivo: string | null;
  // 0353: solo en una salida_final donde el terminal preguntó por no haber
  // refrigerio marcado ese día. null = no se le preguntó.
  confirmo_sin_refrigerio: boolean | null;
  sedes: { codigo: string } | null;
}

interface CorreccionFila {
  corregido_at: string;
  persona_id: string;
  campo_modificado: string;
  valor_anterior: string | null;
  valor_nuevo: string | null;
  corregido_por: string;
  motivo: string;
}

// Solo esta pantalla necesita leer estos dos enums en texto — si un día una
// segunda pantalla los necesita, ahí se justifica moverlos a labels.ts.
const ORIGEN_LABELS: Record<string, string> = {
  terminal: "Terminal",
  admin_correccion: "Corrección manual",
  auto_cierre: "Auto-cierre",
  import_historico: "Importado (histórico)",
};

const ESTADO_REVISION_LABELS: Record<string, string> = {
  normal: "",
  pendiente_revision: "Pendiente de revisión",
  revisada: "Revisada",
};

type Exportacion = "jornadas" | "marcajes" | "correcciones";

export default function ExportarPage() {
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const puedeExportar = puedeExportarAsistencia(rol);
  // Hoy EN LIMA, no en UTC. Iba con `new Date().toISOString()`, que a partir de
  // las 7pm de Perú ya dice el día siguiente: la encargada que cierra su día por
  // la noche pedía «hoy» y se bajaba un archivo vacío, indistinguible de uno
  // lleno. El resto de la pantalla ya convierte con `rangoDelDiaLima`.
  const [desde, setDesde] = useState(hoyLima());
  const [hasta, setHasta] = useState(hoyLima());
  const [cargando, setCargando] = useState<Exportacion | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function exportarJornadas() {
    setCargando("jornadas");
    setError(null);

    const supabase = createAdminSupabaseClient();
    // Por lotes: sin esto PostgREST cortaba en 1000 filas y, como el orden es
    // ascendente por fecha, lo que se perdía eran los días MÁS RECIENTES — y el
    // archivo se descargaba sin ninguna marca de estar incompleto.
    const [{ data, error }, extraRes] = await Promise.all([
      traerTodo<JornadaFila>((ini, fin) =>
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
      setCargando(null);
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

    const filas = (data ?? []).map((j: JornadaFila) => ({
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
    setCargando(null);
  }

  async function exportarMarcajes() {
    setCargando("marcajes");
    setError(null);

    const supabase = createAdminSupabaseClient();
    const { inicio } = rangoDelDiaLima(desde);
    const { fin } = rangoDelDiaLima(hasta);

    // El respaldo crudo: cada marca tal como quedó, con su origen y si fue
    // anulada — la pregunta que hace una inspección no es «cuánto trabajó»
    // (eso ya lo contesta Jornadas), es «¿esto se pudo haber editado?».
    //
    // `personas` NO se embebe: desde la 0081 `marcajes` referencia esa tabla
    // dos veces (persona_id y anulada_por), y PostgREST rechaza el embed por
    // ambiguo. Mismo remedio que en Correcciones — un mapa propio.
    const [{ data: personasData, error: errPersonas }, { data, error }] = await Promise.all([
      supabase.from("personas").select("id, nombres, apellidos"),
      traerTodo<MarcajeFila>((ini, r) =>
        supabase
          .from("marcajes")
          .select(
            "persona_id, timestamp_marca, tipo, origen, estado_revision, motivo_otro, anulada_at, anulada_motivo, confirmo_sin_refrigerio, sedes(codigo)",
          )
          .gte("timestamp_marca", inicio)
          .lte("timestamp_marca", fin)
          .order("timestamp_marca")
          .order("id")
          .range(ini, r),
      ),
    ]);

    if (errPersonas) {
      setError(errPersonas.message);
      setCargando(null);
      return;
    }
    if (error) {
      setError(error.message);
      setCargando(null);
      return;
    }

    const nombrePorId = new Map(
      (personasData ?? []).map((p: PersonaNombre) => [p.id, { nombres: p.nombres, apellidos: p.apellidos }]),
    );

    const filas = (data ?? []).map((m: MarcajeFila) => ({
      fecha_hora: m.timestamp_marca,
      sede: m.sedes?.codigo ?? "",
      nombres: nombrePorId.get(m.persona_id)?.nombres ?? "",
      apellidos: nombrePorId.get(m.persona_id)?.apellidos ?? "",
      tipo: TIPO_MARCA_LABELS[m.tipo] ?? m.tipo,
      motivo_otro: m.motivo_otro ?? "",
      origen: ORIGEN_LABELS[m.origen] ?? m.origen,
      estado_revision: ESTADO_REVISION_LABELS[m.estado_revision] ?? m.estado_revision,
      anulada: m.anulada_at ? "Sí" : "No",
      anulada_motivo: m.anulada_motivo ?? "",
      // 0353/0359: vacío = no se le preguntó (día sin ambigüedad de refrigerio).
      confirmo_trabajo_sin_refrigerio:
        m.confirmo_sin_refrigerio === null ? "" : m.confirmo_sin_refrigerio ? "sí" : "no",
    }));

    const csv = generarCsv(filas, [
      "fecha_hora",
      "sede",
      "nombres",
      "apellidos",
      "tipo",
      "motivo_otro",
      "origen",
      "estado_revision",
      "anulada",
      "anulada_motivo",
      "confirmo_trabajo_sin_refrigerio",
    ]);

    descargarCsv(`dynamic-marcajes-${desde}_a_${hasta}.csv`, csv);
    setCargando(null);
  }

  async function exportarCorrecciones() {
    setCargando("correcciones");
    setError(null);

    const supabase = createAdminSupabaseClient();
    const { inicio } = rangoDelDiaLima(desde);
    const { fin } = rangoDelDiaLima(hasta);

    // `correcciones_auditoria` apunta a `personas` dos veces (persona_id y
    // corregido_por): un embed de PostgREST ahí es ambiguo y exige adivinar
    // el nombre del constraint. Más simple y a prueba de eso: traer las
    // personas una vez (son ~30) y resolver el nombre a mano.
    const [{ data: personasData, error: errPersonas }, { data, error }] = await Promise.all([
      supabase.from("personas").select("id, nombres, apellidos"),
      traerTodo<CorreccionFila>((ini, r) =>
        supabase
          .from("correcciones_auditoria")
          .select("corregido_at, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo")
          .gte("corregido_at", inicio)
          .lte("corregido_at", fin)
          .order("corregido_at")
          .order("id")
          .range(ini, r),
      ),
    ]);

    if (errPersonas) {
      setError(errPersonas.message);
      setCargando(null);
      return;
    }
    if (error) {
      setError(error.message);
      setCargando(null);
      return;
    }

    const nombrePorId = new Map(
      (personasData ?? []).map((p: PersonaNombre) => [p.id, `${p.nombres} ${p.apellidos}`]),
    );

    const filas = (data ?? []).map((c: CorreccionFila) => ({
      fecha_hora: c.corregido_at,
      persona: nombrePorId.get(c.persona_id) ?? "",
      campo_modificado: c.campo_modificado,
      valor_anterior: c.valor_anterior ?? "",
      valor_nuevo: c.valor_nuevo ?? "",
      // `corregido_por` es `not null` desde la 0001, así que un nombre que no
      // está en el mapa NUNCA significa «no lo corrigió nadie»: significa que la
      // RLS de `personas` no nos devuelve a esa persona. A una encargada le pasa
      // siempre que la corrección la hizo DO —que está en Central— porque
      // `personas_select_supervisor` solo le da su propia sede. Y este archivo es
      // justo el que responde «¿quién editó esto?»: dejarlo vacío se lee como
      // «nadie», que es peor que declarar la ausencia.
      corregido_por: nombrePorId.get(c.corregido_por) ?? "(fuera de tu sede)",
      motivo: c.motivo,
    }));

    const csv = generarCsv(filas, [
      "fecha_hora",
      "persona",
      "campo_modificado",
      "valor_anterior",
      "valor_nuevo",
      "corregido_por",
      "motivo",
    ]);

    descargarCsv(`dynamic-correcciones-${desde}_a_${hasta}.csv`, csv);
    setCargando(null);
  }

  // El menú ya no pinta este renglón para quien no puede, pero el menú no es
  // seguridad: quien escriba la URL a mano llega igual. Misma forma que
  // Horarios, Feriados y Datos personales — mientras el rol carga (`null`) no
  // se decide nada, para no parpadear un «no puedes» a quien sí puede.
  if (rol !== null && !puedeExportar) {
    return (
      <div className="flex min-h-screen flex-col">
        <AdminNav />
        <main className="flex flex-1 items-center justify-center p-6">
          <p className="max-w-md text-center text-taupe">No tienes permiso para exportar datos.</p>
        </main>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <div className="flex flex-1 flex-col items-center justify-center gap-6 p-8">
        <h1 className="font-serif text-2xl">Exportar (CSV)</h1>
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
        </div>

        <div className="flex flex-wrap items-center justify-center gap-3">
          <button
            onClick={exportarJornadas}
            disabled={cargando !== null}
            className="rounded-lg bg-tinta px-5 py-2 font-medium text-crema disabled:opacity-50"
          >
            {cargando === "jornadas" ? "Generando…" : "Jornadas (resumen)"}
          </button>
          <button
            onClick={exportarMarcajes}
            disabled={cargando !== null}
            className="rounded-lg bg-tinta px-5 py-2 font-medium text-crema disabled:opacity-50"
          >
            {cargando === "marcajes" ? "Generando…" : "Marcajes (crudo)"}
          </button>
          <button
            onClick={exportarCorrecciones}
            disabled={cargando !== null}
            className="rounded-lg bg-tinta px-5 py-2 font-medium text-crema disabled:opacity-50"
          >
            {cargando === "correcciones" ? "Generando…" : "Correcciones de auditoría"}
          </button>
        </div>

        {error && <p className="text-sm text-rojo">{error}</p>}

        <p className="max-w-md text-center text-xs text-taupe">
          Incluye a todas las personas y sedes visibles para tu rol. Ábrelo directamente con Excel o
          Google Sheets.
        </p>
        <p className="max-w-md text-center text-xs text-taupe">
          «Marcajes» y «Correcciones de auditoría» son el respaldo crudo del sistema — cada marca tal
          como quedó, y cada corrección con quién la hizo y por qué. Es lo que pide una inspección para
          comprobar que nada se editó fuera de este rastro.
        </p>
      </div>
    </div>
  );
}

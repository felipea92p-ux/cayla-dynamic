"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { parseAreas, esOperativaEn, AREA_DEFAULT, AREAS_FALLBACK, type Area } from "@/lib/areas";
import { Cargando } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { Fila, Tabla, TablaEncabezado, Th } from "@/components/ui/tabla";
import { NIVEL_DISCIPLINARIO_CORTO, TZ_LIMA, esRolEncargada, hoyLima } from "@cayla-dynamic/shared";
import { esperadoDelDia, horarioVigente, type HorarioTramo, type TurnoDia } from "@/lib/admin/jornada-esperada";

const REFRESCO_MS = 30_000;
// Corte mañana/tarde de la meta de cobertura — mismo valor fijo que Turnos (14:15).
const CORTE_TARDE = 14.25;
// Margen antes de avisar que una sede entera no marcó nada. No es la tolerancia
// de tardanza (esa es cero: SIN tolerancia, por minuto, según fn_recalcular_jornada) —
// esta es una franja solo de aviso operativo, y avisar al minuto uno generaría
// más ruido que señal con cualquier desfase normal de la mañana.
const MARGEN_ALERTA_SEDE_MIN = 30;


// Día de la semana (0=domingo … 6=sábado) de un ISO — misma convención que
// metas_cobertura.dia_semana en Turnos.
function diaSemanaDe(iso: string): number {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay();
}

// Hora actual de Lima en decimal (13:30 → 13.5), para saber el tramo vigente.
function horaDecimalLimaAhora(): number {
  const p = new Intl.DateTimeFormat("en-GB", { timeZone: TZ_LIMA, hour: "2-digit", minute: "2-digit", hour12: false }).formatToParts(new Date());
  const h = Number(p.find((x) => x.type === "hour")?.value ?? 0) % 24;
  const m = Number(p.find((x) => x.type === "minute")?.value ?? 0);
  return h + m / 60;
}

interface MetaSede { man: number; tar: number; enc: number; }

// Una señal de cobertura en vivo: cuánta gente hay EN PISO ahora vs la meta del
// tramo. Sin meta = taupe neutro (no hay contra qué medir, no es alarma).
function LineaCobertura({ label, n, meta, tramo }: { label: string; n: number; meta: number; tramo?: string }) {
  const sinMeta = meta <= 0;
  const ok = !sinMeta && n >= meta;
  const color = sinMeta ? "var(--color-taupe)" : ok ? "var(--color-verde)" : "var(--color-rojo)";
  return (
    <span className="flex items-center gap-1.5">
      <span className="text-taupe">{label}</span>
      <span className="font-semibold tabular-nums" style={{ color }}>
        {n}
        {!sinMeta && <span className="font-normal text-taupe"> / meta {tramo ? tramo + " " : ""}{meta}</span>}
      </span>
      {sinMeta ? (
        <span className="text-xs text-taupe/60">sin meta</span>
      ) : (
        <span className="text-xs font-medium" style={{ color }}>{ok ? "· completo" : `· faltan ${meta - n}`}</span>
      )}
    </span>
  );
}

function horaLima(ts: string | null): string {
  if (!ts) return "—";
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA,
    hour: "2-digit",
    minute: "2-digit",
    hour12: true,
  }).format(new Date(ts));
}

interface FilaPersona {
  personaId: string;
  nombre: string;
  sede: string;
  sedeId: string;
  estado: string;
  entrada: string | null;
  salidaFinal: string | null;
  minutosTarde: number | null;
  salidaTemprana: number | null;
  enPausaSinRetorno: boolean;
  esOperativa: boolean; // cuenta contra la meta de operativas
  esEncargada: boolean; // supervisor_sede o marca es_encargada_piso
  // Vacaciones, descanso médico u otra ausencia de `ausencias` que cubre HOY.
  // Sin esto, alguien de vacaciones se ve idéntico a un "sin marcar" real en
  // la única pantalla que se mira de un vistazo — el mismo riesgo de falso
  // positivo que la 0101 ya resolvió para el semáforo disciplinario, pero acá
  // nadie lo había cerrado porque esta franja no pasa por fn_faltas_resumen.
  ausenciaHoy: { nombre: string; pendiente: boolean } | null;
  // "08:00" si el horario/turno de hoy dice que le tocaba trabajar; null si le
  // tocaba descanso o no se pudo determinar (misma cascada de jornada-esperada.ts).
  entradaEsperadaHoy: string | null;
}

// Estados: verde/ámbar cálidos para lo operativo (van por <Insignia>), Rojo
// lleno para la alerta crítica. "auto_cerrada_pendiente" se queda con su
// propio relleno sólido: es la única variante que necesita el rojo lleno
// (Insignia no tiene una "alerta crítica", solo la translúcida) para pesar
// más que las demás en la fila. "sin_marcar" tampoco pasa por Insignia: es
// texto apagado sin pastilla a propósito, y `text-taupe/50` es el mismo tono
// que usan más de diez pantallas para "sin dato" — cambiarlo aquí solo
// desentonaría con el resto, no lo arregla.
const ESTILO_ESTADO: Record<
  string,
  { label: string; variante?: "positivo" | "advertencia"; atenuada?: boolean; clase?: string }
> = {
  abierta: { label: "Presente", variante: "positivo" },
  en_pausa: { label: "En pausa", variante: "advertencia" },
  cerrada: { label: "Salió", atenuada: true },
  auto_cerrada_pendiente: { label: "Auto-cerrada ⚠", clase: "bg-rojo text-crema" },
  revisada: { label: "Salió (revisada)", atenuada: true },
  sin_marcar: { label: "Sin marcar", clase: "text-taupe/50" },
};

// La misma celda de estado, compartida entre la tabla de escritorio y las
// tarjetas de celular — para no mantener dos copias del mismo if/else.
function EstadoCelda({ f, linkCorregir }: { f: FilaPersona; linkCorregir: (personaId: string) => string }) {
  const estilo = ESTILO_ESTADO[f.estado] ?? ESTILO_ESTADO.sin_marcar;
  // "Sin marcar" es ambiguo a propósito: puede ser un no-show real o alguien de
  // vacaciones. Sin esto los dos se veían idénticos en la única pantalla que se
  // mira de un vistazo — mismo riesgo de falso positivo que la 0101 ya cerró
  // para el semáforo disciplinario.
  const ausencia = f.estado === "sin_marcar" ? f.ausenciaHoy : null;
  if (ausencia) {
    return (
      <span title={ausencia.pendiente ? "Registrada, todavía sin aprobar" : "Ausencia aprobada que cubre hoy"}>
        <Insignia variante={ausencia.pendiente ? "advertencia" : "neutral"} atenuada={!ausencia.pendiente}>
          {ausencia.nombre}{ausencia.pendiente ? " · por confirmar" : ""}
        </Insignia>
      </span>
    );
  }
  if (f.estado === "auto_cerrada_pendiente") {
    return (
      <Link href={linkCorregir(f.personaId)} className={`rounded-full px-2 py-0.5 text-xs ${estilo.clase} transition-opacity hover:opacity-80`}>
        {estilo.label} ›
      </Link>
    );
  }
  if (estilo.clase) return <span className={`rounded-full px-2 py-0.5 text-xs ${estilo.clase}`}>{estilo.label}</span>;
  return <Insignia variante={estilo.variante} atenuada={estilo.atenuada}>{estilo.label}</Insignia>;
}

// "08:00" → 8.0, para comparar contra horaDecimalLimaAhora().
function horaDecimalDe(hhmm: string): number {
  const [h, m] = hhmm.slice(0, 5).split(":").map(Number);
  return h + (m || 0) / 60;
}
// "08:00" → "8:00 a. m.", para el mensaje de la alerta.
function horaAmPmDe(hhmm: string): string {
  const [h, m] = hhmm.slice(0, 5).split(":").map(Number);
  return new Intl.DateTimeFormat("es-PE", { hour: "numeric", minute: "2-digit", hour12: true, timeZone: "UTC" }).format(
    new Date(Date.UTC(2000, 0, 1, h, m)),
  );
}
// Suma N días hábiles (salta sáb/dom) a una fecha ISO — para el plazo de inmediatez.
function masDiasHabiles(iso: string, n: number): string {
  const [y, m, d] = iso.split("-").map(Number);
  let dt = new Date(Date.UTC(y, m - 1, d));
  let sumados = 0;
  while (sumados < n) {
    dt = new Date(dt.getTime() + 86_400_000);
    const dow = dt.getUTCDay();
    if (dow !== 0 && dow !== 6) sumados++;
  }
  return dt.toISOString().slice(0, 10);
}
function fechaBonita(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "long", timeZone: "UTC" }).format(new Date(Date.UTC(y, m - 1, d)));
}

// `umbral` nombra el escalón alcanzado desde la 0200 — amonestacion ·
// suspension · imputacion · bloqueado · aviso —, no solo «amonestacion o aviso».
interface TardRow { persona_id: string; nombre: string; sede: string; tardanzas_mes: number; umbral: string; ultima_fecha: string | null; minimo: number | null }
interface FaltaRow { persona_id: string; nombre: string; sede: string; nivel: string }
/** Fila de `fn_memos_recientes_respuesta_sancionado()` (0404). */
interface RespuestaMemoRow {
  id: string; persona: string; correlativo: string | null; tipo_causal: string; nivel: string;
  firmado_at: string | null; rechazado_at: string | null;
}
// Contratos a plazo fijo con fecha de término anotada (0144). `dias_restantes` es
// negativo cuando la fecha ya pasó, y ese es el grupo que duele.
interface ContratoRow { persona_id: string; nombre: string; sede: string; fecha_fin_contrato: string; dias_restantes: number; ya_vencio: boolean }

export default function DashboardPage() {
  const router = useRouter();
  const [filas, setFilas] = useState<FilaPersona[]>([]);
  const [metasPorSede, setMetasPorSede] = useState<Map<string, MetaSede>>(new Map());
  const [actualizado, setActualizado] = useState<string>("");
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [discTard, setDiscTard] = useState<TardRow[]>([]);
  const [discFaltas, setDiscFaltas] = useState<FaltaRow[]>([]);
  const [contratos, setContratos] = useState<ContratoRow[]>([]);
  const [sinCargo, setSinCargo] = useState(0);
  // El par de consultas de abajo no respondió. Sin esta distinción, si
  // `expediente_adjuntos` falla, `conPapel` queda vacío y TODOS los memos
  // entregados pasarían el filtro de "sin cargo" — se acusaría a quien sí
  // tiene su papel archivado. Mismo riesgo que `discNoRespondio` ya cierra
  // abajo, para esta franja en particular.
  const [sinCargoNoRespondio, setSinCargoNoRespondio] = useState(false);
  /**
   * El semáforo no contestó. NO es lo mismo que «no hay nadie en escalón».
   *
   * Sin esta distinción la franja se borraba entera cuando la RPC fallaba, y la
   * portada quedaba idéntica a un mes tranquilo. Ya pasó: un `drop function` se
   * llevó por delante su GRANT (0204) y la consulta estuvo caída. Los plazos del
   * art. 25 corren igual mientras la pantalla calla, y esta franja es el único
   * sitio donde el aviso no está dentro de un panel plegado.
   */
  const [discNoRespondio, setDiscNoRespondio] = useState(false);
  const [respuestasMemo, setRespuestasMemo] = useState<RespuestaMemoRow[]>([]);

  // Semáforo disciplinario para la franja (aparte del refresco de asistencia).
  useEffect(() => {
    const sb = createAdminSupabaseClient();
    void (async () => {
      const [{ data: t, error: errT }, { data: f, error: errF }] = await Promise.all([
        sb.rpc("fn_tardanzas_resumen", {}),
        sb.rpc("fn_faltas_resumen", {}),
      ]);
      setDiscNoRespondio(Boolean(errT || errF));
      setDiscTard(Array.isArray(t) ? (t as TardRow[]) : []);
      setDiscFaltas(Array.isArray(f) ? (f as FaltaRow[]) : []);

      // Memos entregados a los que aún les falta el papel firmado.
      //
      // Un memo entregado sin su cargo archivado no se puede probar. Ante una
      // inspección o un reclamo, el expediente que este sistema arma para
      // sostener una decisión se cae justo por ahí: consta que se entregó
      // porque alguien lo marcó, no porque haya una firma de recepción.
      //
      // Vive en el Dashboard y no solo en Disciplina porque el aviso allá
      // estaba dentro de un panel plegado: había que ir a buscarlo sabiendo
      // que existía. Si cualquiera de las dos consultas falla, NO se calcula
      // un número: "0 sin cargo" con `expediente_disciplinario` caída sería
      // ocultar el aviso, y "todos sin cargo" con `expediente_adjuntos`
      // caída sería acusar a quien sí tiene su papel — los dos son peores
      // que decir, sin más, que no se pudo mirar.
      const [
        { data: entregados, error: errEntregados },
        { data: papeles, error: errPapeles },
      ] = await Promise.all([
        sb.from("expediente_disciplinario").select("id").eq("estado", "entregado"),
        sb.from("expediente_adjuntos").select("documento_id"),
      ]);
      if (errEntregados || errPapeles) {
        setSinCargoNoRespondio(true);
        setSinCargo(0);
      } else {
        setSinCargoNoRespondio(false);
        const conPapel = new Set(((papeles as Array<{ documento_id: string }>) ?? []).map((a) => a.documento_id));
        setSinCargo(((entregados as Array<{ id: string }>) ?? []).filter((d) => !conPapel.has(d.id)).length);
      }

      // Quién firmó (o prefirió no firmar) su memo en los últimos 14 días
      // (0404). Falla en silencio a propósito, igual que "Contratos a plazo
      // fijo" más abajo: es informativo, no un aviso de plazo legal corriendo
      // como el resto de esta franja — si la RPC no responde, la tarjeta
      // simplemente no aparece.
      const { data: resp } = await sb.rpc("fn_memos_recientes_respuesta_sancionado", { p_dias: 14 });
      setRespuestasMemo(Array.isArray(resp) ? (resp as RespuestaMemoRow[]) : []);
    })();
  }, []);

  // Contratos a plazo fijo: los que vencen dentro de 30 días y —lo que de verdad
  // importa— los que YA vencieron sin que nadie registrara la salida. La fecha se
  // anota en Equipo; sin este aviso, anotarla solo sirve si alguien se acuerda de
  // ir a mirarla, y el día del vencimiento no lo recuerda nadie.
  //
  // Aparte del refresco de asistencia porque no cambia cada 30 segundos, y con
  // falla silenciosa a propósito: la RPC ya devuelve vacío para quien no es admin
  // ni líder, y si la 0144 no está aplicada devuelve null. En los dos casos la
  // franja no aparece y el dashboard sigue funcionando igual que hoy.
  useEffect(() => {
    const sb = createAdminSupabaseClient();
    void (async () => {
      // NOVENTA días, no treinta. Veintiún contratos a plazo fijo y **veinte
      // vencen el mismo 31 de diciembre**: con la ventana de 30 el aviso
      // aparecía el 1 de diciembre, dejando un mes —en plena campaña de fin de
      // año— para decidir, redactar y firmar veinte renovaciones.
      //
      // Y el que se pasa no se pasa a medias: el artículo 77 del D.S. 003-97-TR
      // convierte el contrato en indefinido SOLO, sin que nadie lo decida, por
      // el hecho de que la persona siga trabajando después de la fecha.
      const { data } = await sb.rpc("fn_contratos_por_vencer", { p_dias: 90 });
      setContratos(Array.isArray(data) ? (data as ContratoRow[]) : []);
    })();
  }, []);

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) {
      router.replace("/admin/login");
      return;
    }

    const hoy = hoyLima();
    const diaHoy = diaSemanaDe(hoy);
    // minutos_salida_temprana va por RPC (fn_jornadas_extra) porque el schema cache
    // de PostgREST no expone la columna; el select directo fallaría entero.
    const [
      { data: personas, error: errPersonas },
      { data: jornadas, error: errJornadas },
      { data: extras }, // fn_jornadas_extra ya está diseñada para fallar en silencio (ver comentario abajo)
      { data: funciones }, // función + es_encargada_piso (RPC: el schema cache no expone la columna)
      { data: areasRaw, error: errAreas }, // catálogo de áreas (para saber cuáles son operativas)
      { data: metasRaw }, // metas de cobertura de hoy por sede (falla suave: sin meta = neutro)
      { data: ausenciasHoy }, // vacaciones/descanso médico/etc. que cubren HOY (falla suave: sin dato, sin badge)
      { data: tiposAusencia }, // catálogo (nombre + si exige aprobación), para no repetirlo a mano acá
      { data: turnosHoy }, // turno puntual de hoy, si alguien lo registró (falla suave: sin alerta de sede)
      { data: horariosVigentes }, // tramos de horario vigentes hoy, para la cascada de jornada-esperada.ts
    ] = await Promise.all([
      supabase
        .from("personas")
        .select("id, nombres, apellidos, rol, sede_base_id, sedes:sede_base_id(codigo)")
        .eq("estado", "activo")
        .eq("en_planilla", true)
        .eq("sueldo_fijo", false) // quien cobra fijo no marca: no se le mide asistencia
        .order("nombres"),
      supabase
        .from("jornadas")
        .select("persona_id, estado, entrada_ts, salida_final_ts, minutos_tarde, tiene_salida_no_retornada")
        .eq("fecha", hoy),
      supabase.rpc("fn_jornadas_extra", { p_desde: hoy, p_hasta: hoy }),
      supabase.rpc("fn_personas_funciones"),
      supabase.rpc("fn_areas"),
      supabase.from("metas_cobertura").select("sede_id, meta, meta_tarde, meta_encargadas").eq("dia_semana", diaHoy),
      // anulada_at is null: una ausencia anulada no cubre nada. El rango incluye
      // hoy con <= / >=, igual que el `between` que ya usa fn_faltas_resumen.
      supabase.from("ausencias").select("persona_id, tipo, aprobada_at").is("anulada_at", null).lte("fecha_inicio", hoy).gte("fecha_fin", hoy),
      supabase.from("tipos_ausencia").select("codigo, nombre, requiere_aprobacion"),
      supabase.from("turnos").select("persona_id, fecha, hora_entrada, hora_salida, es_descanso").eq("fecha", hoy),
      supabase
        .from("horarios_asignados")
        .select("persona_id, hora_entrada, hora_salida, dias_laborables, horario_por_dia, almuerzo_min_minutos, vigente_desde, vigente_hasta")
        .lte("vigente_desde", hoy)
        .or(`vigente_hasta.is.null,vigente_hasta.gte.${hoy}`),
    ]);

    if (errPersonas || errJornadas) {
      setError((errPersonas ?? errJornadas)!.message);
      setCargando(false);
      return; // no pisa `filas` con datos parciales/vacíos
    }
    setError(null);

    // Función/área/encargada: si la RPC falla, degradamos a "todos operativos"
    // (misma política que Turnos) — la cobertura puede marcar de más pero la
    // página no se cae. Las metas fallan aún más suave: sin meta = neutro.
    const areasList: Area[] = parseAreas(areasRaw, errAreas);
    const funcionPorPersona = new Map(
      ((funciones as { persona_id: string; funcion: string; es_encargada_piso?: boolean }[] | null) ?? [])
        .map((x) => [x.persona_id, { funcion: x.funcion, enc: Boolean(x.es_encargada_piso) }]),
    );
    setMetasPorSede(new Map(
      ((metasRaw as { sede_id: string; meta: number; meta_tarde: number | null; meta_encargadas: number | null }[] | null) ?? [])
        .map((m) => [m.sede_id, { man: m.meta ?? 0, tar: m.meta_tarde ?? m.meta ?? 0, enc: m.meta_encargadas ?? 0 }]),
    ));

    const jornadaPorPersona = new Map((jornadas ?? []).map((j: any) => [j.persona_id, j]));
    // Solo llegan filas con minutos > 0 y la fecha es fija (hoy), así que basta persona_id → minutos.
    // Si la RPC falla, extras es null y el map queda vacío (sin badge, la página no se rompe).
    const salidaTempranaPorPersona = new Map(
      ((extras as { persona_id: string; fecha: string; minutos_salida_temprana: number }[] | null) ?? []).map(
        (e) => [e.persona_id, e.minutos_salida_temprana],
      ),
    );
    // Nombre + si exige aprobación, por código de tipo ("vacaciones" → "Vacaciones", true/false).
    const nombrePorTipoAusencia = new Map(
      ((tiposAusencia as { codigo: string; nombre: string; requiere_aprobacion: boolean }[] | null) ?? []).map(
        (t) => [t.codigo, { nombre: t.nombre, requiereAprobacion: t.requiere_aprobacion }],
      ),
    );
    // La restricción `ausencias_sin_solape` ya impide que a una persona le
    // cubran dos ausencias el mismo día, así que basta con la última que
    // llegue — no hay que decidir cuál gana.
    const ausenciaPorPersona = new Map(
      ((ausenciasHoy as { persona_id: string; tipo: string; aprobada_at: string | null }[] | null) ?? []).map((a) => {
        const t = nombrePorTipoAusencia.get(a.tipo);
        return [a.persona_id, { nombre: t?.nombre ?? a.tipo, pendiente: Boolean(t?.requiereAprobacion) && !a.aprobada_at }];
      }),
    );

    // Misma cascada de jornada-esperada.ts que Correcciones, Incidencias y Turnos: el
    // turno puntual de hoy manda, y si no hay se cae al horario base vigente.
    const turnoPorPersona = new Map(
      ((turnosHoy as { persona_id: string; fecha: string; hora_entrada: string | null; hora_salida: string | null; es_descanso: boolean }[] | null) ?? [])
        .map((t) => [t.persona_id, t as TurnoDia]),
    );
    const horariosPorPersona = new Map<string, HorarioTramo[]>();
    for (const h of (horariosVigentes as HorarioTramo[] | null) ?? []) {
      const arr = horariosPorPersona.get(h.persona_id) ?? [];
      arr.push(h);
      horariosPorPersona.set(h.persona_id, arr);
    }

    const resultado: FilaPersona[] = (personas ?? []).map((p: any) => {
      const j = jornadaPorPersona.get(p.id);
      const f = funcionPorPersona.get(p.id);
      const turno = turnoPorPersona.get(p.id) ?? null;
      const horario = horarioVigente(horariosPorPersona.get(p.id) ?? [], hoy);
      const esperado = esperadoDelDia(hoy, turno, horario);
      return {
        personaId: p.id,
        nombre: `${p.nombres} ${p.apellidos}`,
        sede: p.sedes?.codigo ?? "?",
        sedeId: p.sede_base_id,
        estado: j?.estado ?? "sin_marcar",
        entrada: j?.entrada_ts ?? null,
        entradaEsperadaHoy: esperado.trabaja ? esperado.entrada : null,
        salidaFinal: j?.salida_final_ts ?? null,
        minutosTarde: j?.minutos_tarde ?? null,
        salidaTemprana: salidaTempranaPorPersona.get(p.id) ?? null,
        enPausaSinRetorno: j?.tiene_salida_no_retornada ?? false,
        esOperativa: esOperativaEn(areasList, f?.funcion ?? AREA_DEFAULT),
        esEncargada: esRolEncargada(p.rol) || Boolean(f?.enc),
        ausenciaHoy: ausenciaPorPersona.get(p.id) ?? null,
      };
    });

    setFilas(resultado);
    setActualizado(new Intl.DateTimeFormat("es-PE", { timeZone: TZ_LIMA, hour: "2-digit", minute: "2-digit", second: "2-digit" }).format(new Date()));
    setCargando(false);
  }, [router]);

  useEffect(() => {
    void cargar();
    const t = setInterval(() => void cargar(), REFRESCO_MS);
    // Refrescar también al volver a la pestaña (los navegadores pausan el interval en
    // segundo plano; así un cambio reciente —ej. una persona nueva— aparece al regresar).
    const alVolver = () => { if (document.visibilityState === "visible") void cargar(); };
    document.addEventListener("visibilitychange", alVolver);
    window.addEventListener("focus", alVolver);
    return () => {
      clearInterval(t);
      document.removeEventListener("visibilitychange", alVolver);
      window.removeEventListener("focus", alVolver);
    };
  }, [cargar]);

  // Agrupamos por sede_id (no por código) para poder cruzar con metas_cobertura.
  const sedes = [...new Map(filas.map((f) => [f.sedeId, f.sede])).entries()]
    .map(([sedeId, codigo]) => ({ sedeId, codigo }))
    .sort((a, b) => a.codigo.localeCompare(b.codigo));
  const tramoTarde = horaDecimalLimaAhora() >= CORTE_TARDE;
  const tramoLabel = tramoTarde ? "tarde" : "mañana";
  const hoy = hoyLima();
  // Un incidente (tardanza, auto-cierre) enlaza directo a Corregir de esa persona/fecha.
  const linkCorregir = (personaId: string) => `/admin/correcciones?persona=${personaId}&fecha=${hoy}`;

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6 sm:p-8">
        <div className="mb-8 flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 className="font-serif text-3xl leading-tight">Asistencia de hoy</h1>
            <p className="mt-1.5 flex items-center gap-2 text-xs text-taupe">
              {cargando && filas.length === 0 ? (
                "Cargando…"
              ) : (
                <>
                  <span className="relative flex h-2 w-2" aria-hidden>
                    <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-verde/60" />
                    <span className="relative inline-flex h-2 w-2 rounded-full bg-verde" />
                  </span>
                  En vivo · actualizado {actualizado} · se refresca cada 30s
                </>
              )}
            </p>
          </div>
          <a
            href="https://docs.google.com/spreadsheets/d/19jhc5IN0LpbyG00jEwqt4ZB420Ob_rVcGRAdXR88riA/edit"
            target="_blank"
            rel="noopener noreferrer"
            className="rounded-xl border border-sand bg-papel px-4 py-2 text-sm font-medium text-tinta transition-all hover:-translate-y-0.5 hover:border-taupe"
          >
            Ver en Google Sheets ↗
          </a>
        </div>

        {error && (
          <div className="mb-6 rounded-2xl border border-rojo/20 bg-rojo/[0.06] px-4 py-3 text-sm text-rojo">
            No se pudo cargar la asistencia de hoy: {error}{" "}
            <Boton variante="enlace" onClick={() => void cargar()}>
              Reintentar
            </Boton>
          </div>
        )}

        {cargando && filas.length === 0 ? (
          <Cargando texto="Cargando la asistencia de hoy…" />
        ) : (
          <>
        {(() => {
          // Cualquier escalón alcanzado va en rojo, no solo la amonestación.
          // Comparar contra "amonestacion" dejaba fuera del aviso a quien ya
          // estaba en suspensión o imputación — los casos más urgentes.
          const rojosT = discTard.filter((t) => t.umbral !== "aviso");
          const avisoT = discTard.filter((t) => t.umbral === "aviso").length;
          const rojosF = discFaltas.filter((f) => f.nivel === "rojo");
          const ambarF = discFaltas.filter((f) => f.nivel === "ambar").length;
          // Si el semáforo no contestó, la franja NO se borra: se queda diciendo
          // que no pudo mirar. «No hay nadie sancionable» y «no lo sé» se ven
          // igual de tranquilos en una portada, y solo uno de los dos es cierto.
          if (discNoRespondio) {
            return (
              <section className="mb-6 rounded-2xl border border-ambar/30 bg-ambar/[0.06] p-5">
                <div className="etiqueta text-ambar">Disciplina · no se pudo consultar</div>
                <p className="mt-2 text-sm text-tinta">
                  El semáforo de tardanzas y faltas no respondió, así que esta franja{" "}
                  <strong>no está diciendo que no haya nadie</strong>: está diciendo que no pudo mirar.
                  Vuelve a cargar, y si sigue igual ábrelo en{" "}
                  <a href="/admin/disciplina" className="underline">Disciplina</a>.
                </p>
              </section>
            );
          }
          if (!rojosT.length && !avisoT && !rojosF.length && !ambarF && !sinCargo && !sinCargoNoRespondio) return null;
          return (
            <div className="mb-10 rounded-2xl border border-sand bg-rojo/[0.04] p-5">
              <div className="mb-2 flex items-center justify-between">
                <span className="font-serif text-lg text-tinta">Disciplina — necesita tu atención</span>
                <Link href="/admin/disciplina" className="text-xs font-medium text-rojo hover:underline">Ver disciplina →</Link>
              </div>
              {rojosT.map((t) => (
                <Link key={t.persona_id} href={`/admin/disciplina#tard-${t.persona_id}`}
                  className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 border-t border-sand/60 py-2 text-sm transition-colors hover:bg-rojo/[0.06]">
                  <span><strong>{t.nombre}</strong> <span className="text-taupe">· {t.sede}</span>
                    <Insignia variante="alerta" className="ml-2">
                      {t.umbral === "bloqueado"
                        ? "imputación de cargos vigente — decide Gerencia"
                        : `corresponde ${NIVEL_DISCIPLINARIO_CORTO[t.umbral as keyof typeof NIVEL_DISCIPLINARIO_CORTO] ?? t.umbral} por tardanzas`}
                    </Insignia></span>
                  {t.ultima_fecha && <span className="text-xs font-medium text-rojo">actúa antes del {fechaBonita(masDiasHabiles(t.ultima_fecha, 10))} →</span>}
                </Link>
              ))}
              {rojosF.map((f) => (
                <Link key={f.persona_id} href={`/admin/disciplina#falta-${f.persona_id}`}
                  className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 border-t border-sand/60 py-2 text-sm transition-colors hover:bg-rojo/[0.06]">
                  <span><strong>{f.nombre}</strong> <span className="text-taupe">· {f.sede}</span>
                    <Insignia variante="alerta" className="ml-2">causal por faltas (art. 25-h)</Insignia></span>
                  <span className="text-xs font-medium text-rojo">acción inmediata →</span>
                </Link>
              ))}
              {sinCargoNoRespondio ? (
                <div className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 border-t border-sand/60 py-2 text-sm">
                  <span className="text-taupe">
                    No se pudo comprobar si hay memos entregados sin el cargo firmado archivado.
                  </span>
                  <span className="text-xs font-medium text-ambar">no se pudo mirar</span>
                </div>
              ) : sinCargo > 0 && (
                <Link href="/admin/disciplina#entregados"
                  className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 border-t border-sand/60 py-2 text-sm transition-colors hover:bg-rojo/[0.06]">
                  <span>
                    <strong>{sinCargo} {sinCargo === 1 ? "memo entregado" : "memos entregados"}</strong>{" "}
                    <span className="text-taupe">sin el cargo firmado archivado</span>
                    <Insignia variante="alerta" className="ml-2">no se puede probar la entrega</Insignia>
                  </span>
                  <span className="text-xs font-medium text-rojo">sube el papel →</span>
                </Link>
              )}
              <div className="border-t border-sand/60 pt-2.5 text-xs text-taupe">
                {avisoT > 0 && <Insignia variante="advertencia">{avisoT} en aviso (tardanzas)</Insignia>}
                {avisoT > 0 ? " · " : ""}Faltas: {rojosF.length + ambarF > 0 ? `${rojosF.length + ambarF} en alerta` : "sin alertas"}
              </div>
            </div>
          );
        })()}

        {/* QUIÉN RESPONDIÓ SU MEMO (0404). Aparte del panel de arriba porque
            no es un plazo legal corriendo — es informativo: alguien ya vio su
            documento y dejó una constancia digital, firmando o prefiriendo no
            hacerlo. Ninguna de las dos reemplaza el trámite físico. */}
        {respuestasMemo.length > 0 && (
          <div className="mb-10 rounded-2xl border border-sand bg-verde/[0.04] p-5">
            <div className="mb-2 flex items-center justify-between">
              <span className="font-serif text-lg text-tinta">Colaboradores respondieron su memo</span>
              <Link href="/admin/disciplina" className="text-xs font-medium text-taupe hover:underline">Ver disciplina →</Link>
            </div>
            {respuestasMemo.map((r) => (
              <Link key={r.id} href={`/admin/disciplina/memo/${r.id}`}
                className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 border-t border-sand/60 py-2 text-sm transition-colors hover:bg-verde/[0.06]">
                <span>
                  <strong>{r.persona}</strong> <span className="text-taupe">· {NIVEL_DISCIPLINARIO_CORTO[r.nivel as keyof typeof NIVEL_DISCIPLINARIO_CORTO] ?? r.nivel}</span>
                  <Insignia variante={r.firmado_at ? "positivo" : "neutral"} className="ml-2">
                    {r.firmado_at ? "firmó digitalmente" : "prefirió no firmar"}
                  </Insignia>
                </span>
                <span className="text-xs text-taupe">{fechaBonita((r.firmado_at ?? r.rechazado_at)!.slice(0, 10))}</span>
              </Link>
            ))}
          </div>
        )}

        {/* CONTRATOS A PLAZO FIJO. Dos grupos, y el importante es el primero:
            quien ya venció y sigue figurando activo. Ese caso no se nota en
            ninguna otra pantalla —la persona aparece normal en asistencia, en
            planilla y en provisiones— y desde la 0162 tampoco en el tablero de
            Documentación. Sin esta franja, la fecha anotada en Equipo solo sirve
            si alguien se acuerda de ir a buscarla. */}
        {(() => {
          const vencidos = contratos.filter((c) => c.ya_vencio);
          const porVencer = contratos.filter((c) => !c.ya_vencio);
          if (!vencidos.length && !porVencer.length) return null;
          const enCuantos = (dias: number) =>
            dias <= 0 ? "vence hoy" : dias === 1 ? "vence mañana" : `vence en ${dias} días`;
          // ¿Muchos caen el MISMO día? Veinte líneas seguidas con la misma fecha
          // se leen como veinte avisos sueltos, y el problema no son veinte
          // renovaciones repartidas: es que hay que hacerlas todas esa semana.
          // Se dice de una vez, arriba, antes de la lista.
          const porFecha = new Map<string, number>();
          for (const c of porVencer) porFecha.set(c.fecha_fin_contrato, (porFecha.get(c.fecha_fin_contrato) ?? 0) + 1);
          const [fechaRacimo, cuantos] = [...porFecha.entries()]
            .sort((a, b) => b[1] - a[1])[0] ?? ["", 0];
          const hayRacimo = cuantos >= 3;
          return (
            <div className="mb-10 rounded-2xl border border-sand bg-ambar/[0.05] p-5">
              <div className="mb-2 flex items-center justify-between">
                <span className="font-serif text-lg text-tinta">Contratos a plazo fijo</span>
                <Link href="/admin/equipo" className="text-xs font-medium text-rojo hover:underline">Ver equipo →</Link>
              </div>
              {hayRacimo && (
                <p className="mb-2 rounded-lg bg-rojo/10 px-3 py-2 text-sm text-rojo">
                  <strong>{cuantos} contratos vencen el mismo día</strong> ({fechaBonita(fechaRacimo)}).
                  No son {cuantos} trámites repartidos: son {cuantos} decisiones, {cuantos} redacciones
                  y {cuantos} firmas en la misma semana. Al que se pase de fecha con la persona
                  todavía trabajando, el <strong>art. 77</strong> lo vuelve indefinido solo.
                </p>
              )}
              {vencidos.map((c) => (
                <div key={c.persona_id} className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 border-t border-sand/60 py-2 text-sm">
                  <span>
                    <strong>{c.nombre}</strong> <span className="text-taupe">· {c.sede}</span>
                    <Insignia variante="alerta" className="ml-2">
                      terminó el {fechaBonita(c.fecha_fin_contrato)} y sigue activa
                    </Insignia>
                  </span>
                  <span className="text-xs font-medium text-rojo">renovar o registrar su salida →</span>
                </div>
              ))}
              {porVencer.map((c) => (
                <div key={c.persona_id} className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 border-t border-sand/60 py-2 text-sm">
                  <span>
                    <strong>{c.nombre}</strong> <span className="text-taupe">· {c.sede}</span>
                    <Insignia variante="advertencia" className="ml-2">
                      {enCuantos(c.dias_restantes)} · {fechaBonita(c.fecha_fin_contrato)}
                    </Insignia>
                  </span>
                </div>
              ))}
              <p className="border-t border-sand/60 pt-2.5 text-xs text-taupe">
                {vencidos.length > 0
                  ? "Mientras siga figurando activa sigue marcando, sigue cobrando y sigue acumulando gratificación, CTS y vacaciones. Anotar la fecha no da de baja a nadie: eso se decide y se registra a mano."
                  : "La fecha es lo previsto, no un hecho. Un contrato puede renovarse: esto solo avisa antes de que llegue el día."}
              </p>
            </div>
          );
        })()}

        {sedes.map(({ sedeId, codigo }) => {
          const deSede = filas.filter((f) => f.sedeId === sedeId);
          const activos = deSede.filter((f) => f.estado === "abierta" || f.estado === "en_pausa");
          // Cobertura EN VIVO: "en piso" = solo Presente (abierta). Quien está en
          // pausa/refrigerio no cuenta — no está físicamente cubriendo ahora.
          const meta = metasPorSede.get(sedeId) ?? { man: 0, tar: 0, enc: 0 };
          const opPiso = deSede.filter((f) => f.esOperativa && f.estado === "abierta").length;
          const encPiso = deSede.filter((f) => f.esEncargada && f.estado === "abierta").length;

          // Alerta de sede sin actividad: a alguien ya le tocaba entrar (según su
          // horario u horario), con margen, y todavía nadie de la sede marcó nada.
          // Se excluye a quien tiene una ausencia hoy — mandar de vacaciones a todo
          // el equipo de una sede no es "nadie llegó", es que nadie tenía que llegar.
          const entradasEsperadasHoy = deSede
            .filter((f) => !f.ausenciaHoy && f.entradaEsperadaHoy)
            .map((f) => f.entradaEsperadaHoy!)
            .sort();
          const nadieMarcoTodavia = deSede.every((f) => f.entrada === null);
          let alertaSinEntrada: string | null = null;
          if (entradasEsperadasHoy.length > 0 && nadieMarcoTodavia) {
            const primeraEntrada = entradasEsperadasHoy[0];
            const minutosPasados = (horaDecimalLimaAhora() - horaDecimalDe(primeraEntrada)) * 60;
            if (minutosPasados >= MARGEN_ALERTA_SEDE_MIN) alertaSinEntrada = primeraEntrada;
          }

          return (
            <section key={sedeId} className="mb-12">
              <h2 className="mb-4 font-serif text-xl">
                {codigo} <span className="text-base font-normal text-taupe">— {activos.length} trabajando de {deSede.length}</span>
              </h2>

              {/* La única alerta que se permite el rojo sagrado en esta pantalla: una
                  sede entera sin un solo marcaje, con el horario ya empezado. */}
              {alertaSinEntrada && (
                <div className="mb-5 flex items-center gap-2 rounded-2xl border border-rojo bg-rojo/[0.06] px-5 py-3 text-sm font-semibold text-rojo">
                  <span className="flex h-4 w-4 shrink-0 items-center justify-center rounded-full bg-rojo text-[10px] font-bold text-crema">!</span>
                  Sin marcajes desde las {horaAmPmDe(alertaSinEntrada)} — nadie de esta sede ha marcado entrada todavía.
                </div>
              )}

              {/* Trabajando ahora — para que la encargada verifique contra quién está físicamente */}
              <div className="mb-5 rounded-2xl border border-verde/20 bg-verde/[0.06] px-5 py-4">
                <div className="etiqueta text-verde">Trabajando ahora · {activos.length}</div>
                <div className="mt-3 flex flex-wrap gap-2">
                  {activos.length === 0 ? (
                    <span className="text-sm text-taupe">Nadie marcado todavía.</span>
                  ) : (
                    activos.map((f) => (
                      <span key={f.personaId} className="rounded-full border border-sand bg-papel px-3 py-1 text-sm transition-colors hover:border-taupe">
                        {f.nombre}
                        {f.estado === "en_pausa" && <span className="ml-1 text-ambar">· en pausa</span>}
                      </span>
                    ))
                  )}
                </div>
                {/* Cobertura del momento: cuánta gente en piso ahora vs la meta del tramo vigente */}
                <div className="mt-4 flex flex-wrap items-center gap-x-6 gap-y-1 border-t border-verde/15 pt-3 text-sm">
                  <LineaCobertura label="Operativas en piso" n={opPiso} meta={tramoTarde ? meta.tar : meta.man} tramo={tramoLabel} />
                  <LineaCobertura label="Encargadas" n={encPiso} meta={meta.enc} />
                </div>
              </div>

              {/* Escritorio: tabla completa. En celular una tabla de 5 columnas no cabe sin
                  scroll horizontal incómodo, así que de sm hacia abajo se arma la
                  versión en tarjetas de más abajo — mismos datos, sin recortar nada. */}
              <div className="hidden sm:block">
                <Tabla>
                  <TablaEncabezado>
                    <Th>Nombre</Th>
                    <Th>Estado</Th>
                    <Th>Entrada</Th>
                    <Th>Tardanza</Th>
                    <Th>Salida final</Th>
                  </TablaEncabezado>
                  <tbody>
                    {deSede.map((f) => (
                      <Fila key={f.personaId}>
                        <td className="px-4 py-2.5">{f.nombre}</td>
                        <td className="px-4 py-2.5">
                          <EstadoCelda f={f} linkCorregir={linkCorregir} />
                        </td>
                        <td className="px-4 py-2.5">{horaLima(f.entrada)}</td>
                        <td className="px-4 py-2.5">
                          {f.minutosTarde === null || f.minutosTarde === 0 ? (
                            <span className="text-taupe/40">—</span>
                          ) : (
                            <Link href={linkCorregir(f.personaId)} className="font-semibold text-rojo underline decoration-rojo/30 underline-offset-2 transition-colors hover:decoration-rojo">
                              {f.minutosTarde} min
                            </Link>
                          )}
                        </td>
                        <td className="px-4 py-2.5">
                          {horaLima(f.salidaFinal)}
                          {f.salidaTemprana ? (
                            <Link href={linkCorregir(f.personaId)} className="ml-2 transition-opacity hover:opacity-80">
                              <Insignia variante="advertencia" tamano="sm">anticip. {f.salidaTemprana}m</Insignia>
                            </Link>
                          ) : null}
                        </td>
                      </Fila>
                    ))}
                  </tbody>
                </Tabla>
              </div>

              {/* Celular: la misma información en tarjetas apiladas, una por persona. */}
              <div className="flex flex-col gap-2 sm:hidden">
                {deSede.map((f) => (
                  <div key={f.personaId} className="rounded-superficie border border-sand bg-papel p-4">
                    <div className="mb-2 flex items-center justify-between gap-2">
                      <span className="font-medium">{f.nombre}</span>
                      <span className="shrink-0">
                        <EstadoCelda f={f} linkCorregir={linkCorregir} />
                      </span>
                    </div>
                    <div className="grid grid-cols-3 gap-x-2 gap-y-1 border-t border-sand pt-2 text-xs">
                      <span className="text-taupe">Entrada</span>
                      <span className="text-taupe">Tardanza</span>
                      <span className="text-taupe">Salida final</span>
                      <span>{horaLima(f.entrada)}</span>
                      <span>
                        {f.minutosTarde === null || f.minutosTarde === 0 ? (
                          <span className="text-taupe/40">—</span>
                        ) : (
                          <Link href={linkCorregir(f.personaId)} className="font-semibold text-rojo underline decoration-rojo/30 underline-offset-2">
                            {f.minutosTarde} min
                          </Link>
                        )}
                      </span>
                      <span>
                        {horaLima(f.salidaFinal)}
                        {f.salidaTemprana ? (
                          <Link href={linkCorregir(f.personaId)} className="ml-1 inline-block">
                            <Insignia variante="advertencia" tamano="sm">+{f.salidaTemprana}m</Insignia>
                          </Link>
                        ) : null}
                      </span>
                    </div>
                  </div>
                ))}
              </div>
            </section>
          );
        })}
          </>
        )}
      </main>
    </div>
  );
}

"use client";

import { Fragment, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Search } from "lucide-react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { Cargando } from "@/components/cargando";
import { useToast } from "@/components/toast";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoSelect, CampoCasilla } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { Tabla, TablaEncabezado, Th, Fila } from "@/components/ui/tabla";
import { Insignia } from "@/components/ui/insignia";
import { Drawer } from "@/components/ui/drawer";
import { ROLES_DO, hoyLima, puedeOperarEquipo, maximoSemanalPracticante } from "@cayla-dynamic/shared";
// horasDia() reimplementaba (salida − entrada) − refrigerio a mano, sin el
// ajuste "si la salida no es posterior a la entrada, el turno cruza
// medianoche" que horasEntre() ya resuelve (turnos/page.tsx también la
// reusa). Sin eso, un horario nocturno (p. ej. 21:00–05:00) daba 0 horas en
// vez de las ocho reales, escondiendo el aviso de exceso legal semanal de
// una practicante.
import { horasEntre as horasDia, esTurnoEspejoViejo, type HorarioTramo } from "@/lib/admin/jornada-esperada";

const META_SEMANA = 45; // horas objetivo por semana (7.5h × 6 días)
// Pedido por Felipe el 2026-09-14: un motivo de verdad, no una frase de
// trámite — 250 caracteres empuja a explicar el contexto real del cambio
// (quién lo pidió, por qué, qué operativa lo justifica), no a escribir
// "cambio de horario" y seguir. El mínimo vive en el cliente; el guardián de
// la base (fn_set_horario_semanal, 0440) sigue exigiendo solo 3 como piso de
// seguridad — subirlo ahí es una migración nueva y aparte, no este cambio.
const MOTIVO_MIN = 250;

function ContadorMotivo({ texto }: { texto: string }) {
  const n = texto.trim().length;
  const falta = MOTIVO_MIN - n;
  return (
    <p className={`mt-1 text-xs ${falta > 0 ? "text-taupe" : "text-verde"}`}>
      {falta > 0 ? `Faltan ${falta} caracteres (mínimo ${MOTIVO_MIN}).` : `${n} caracteres — motivo completo.`}
    </p>
  );
}

function fmtH(h: number): string {
  return `${Math.round(h * 100) / 100} h`;
}

// "14 set. 2026", nunca "2026-09-14" — no cambia cómo se guarda, solo cómo se
// lee. Mismo molde que ya usan feriados/page.tsx (fechaCorta) y
// reporte-sede/page.tsx: parsear el ISO a mano y formatear con timeZone UTC,
// porque la cadena YA es una fecha resuelta — reaplicarle una zona horaria la
// correría un día (mismo motivo que nombreDelMesLima en fecha-lima.ts). El
// mes corto con punto ("set.", no "sep") es el que ya da Intl con es-PE — se
// deja tal cual, no "sep" sin punto: esa es la abreviatura real del Perú, y
// cambiarla habría dejado esta pantalla diciendo el mes distinto que
// feriados/page.tsx dos rutas más abajo.
function fechaCorta(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "short", year: "numeric", timeZone: "UTC" })
    .format(new Date(Date.UTC(y, m - 1, d)));
}

type Dia = { e: string; s: string; r: number };
type PorDia = Record<number, Dia>;
interface Persona {
  id: string; nombres: string; apellidos: string; rol: string; sede_base_id: string;
  // Para avisar del máximo legal de una practicante (0324) — llegan por
  // fn_personas_funciones, no por el select directo de `personas`, porque el
  // schema cache de PostgREST no expone estas columnas.
  tipo_vinculo: string;
  practicante_modalidad: string | null;
}
interface Horario {
  persona_id: string; hora_entrada: string; hora_salida: string; vigente_desde: string;
  almuerzo_min_minutos: number; almuerzo_max_minutos: number; dias_laborables: number[];
  horario_por_dia: Record<string, { e: string; s: string; r?: number }> | null;
}
// Para el historial de tramos del drawer — igual que Horario, con el cierre.
interface Tramo extends Horario {
  vigente_hasta: string | null;
}
const DIAS = [{ v: 1, l: "L" }, { v: 2, l: "M" }, { v: 3, l: "X" }, { v: 4, l: "J" }, { v: 5, l: "V" }, { v: 6, l: "S" }, { v: 0, l: "D" }];
const NOMBRE_DIA: Record<number, string> = { 0: "domingo", 1: "lunes", 2: "martes", 3: "miércoles", 4: "jueves", 5: "viernes", 6: "sábado" };

// El refrigerio real de CAYLA es 60 o 75 minutos, nunca otro número — un campo
// libre dejaba pasar un "6" en vez de un "60" sin que nada lo detectara, y eso
// se cuela directo al cálculo de jornada. Auditoría 2026-09-14.
const REFRIGERIOS_MIN = [60, 75];

// Datos viejos pueden traer un refrigerio fuera de {60, 75} (el schema
// permite 45-75, el legacy por defecto era 45). En vez de esconderlo -el
// selector no puede mostrar "seleccionado" un valor que no está en sus
// opciones sin que el estado real quede desincronizado de lo que se ve- se
// agrega como una tercera opción visible, para no pisarlo sin que quien
// edita lo note.
function opcionesRefrigerio(actual: number): number[] {
  return REFRIGERIOS_MIN.includes(actual) ? REFRIGERIOS_MIN : [...REFRIGERIOS_MIN, actual].sort((a, b) => a - b);
}

// Buscar «Ramirez» tiene que encontrar a «Ramírez». Mismo normalizador que
// /admin/contratos, /admin/horas y el buscador global.
function sinTildes(t: string): string {
  return t.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase();
}

function textoDescanso(dias: number[]): string {
  const libres = [1, 2, 3, 4, 5, 6, 0].filter((d) => !dias.includes(d));
  if (libres.length === 0) return "sin descanso";
  return libres.map((d) => NOMBRE_DIA[d]).join(", ");
}

// Extrae el horario por día (jsonb nuevo con refrigerio, o legacy de una sola hora).
function analizar(h?: Horario): { porDia: PorDia; dias: number[]; uniforme: boolean; e: string; s: string; r: number } {
  const pd: PorDia = {};
  if (h?.horario_por_dia && typeof h.horario_por_dia === "object") {
    for (const [k, v] of Object.entries(h.horario_por_dia)) {
      const d = Number(k);
      if (!Number.isNaN(d) && v && typeof v === "object") {
        pd[d] = { e: (v.e ?? "08:00").slice(0, 5), s: (v.s ?? v.e ?? "18:00").slice(0, 5), r: Number(v.r ?? 60) };
      }
    }
  } else if (h) {
    const r = h.almuerzo_min_minutos ?? 60;
    for (const d of h.dias_laborables ?? [1, 2, 3, 4, 5, 6]) pd[d] = { e: h.hora_entrada.slice(0, 5), s: h.hora_salida.slice(0, 5), r };
  } else {
    for (const d of [1, 2, 3, 4, 5, 6]) pd[d] = { e: "08:00", s: "18:00", r: 60 };
  }
  const dias = Object.keys(pd).map(Number).sort((a, b) => a - b);
  const first = dias.length ? pd[dias[0]] : { e: "08:00", s: "18:00", r: 60 };
  const uniforme = dias.every((d) => pd[d].e === first.e && pd[d].s === first.s && pd[d].r === first.r);
  return { porDia: pd, dias, uniforme, e: first.e, s: first.s, r: first.r };
}

// ────────────────────────────────────────────────────────────────────────
// Estado de un horario semanal — vive aparte porque el rediseño 2026-09-14
// lo necesita DOS veces (editar una persona y asignar a varias a la vez), y
// las dos copias tienen que comportarse idéntico o divergen con el tiempo
// como cualquier lógica pegada dos veces a mano.
// ────────────────────────────────────────────────────────────────────────
function useFormularioHorario() {
  const [modoPorDia, setModoPorDia] = useState(false);
  const [entrada, setEntrada] = useState("08:00");
  const [salida, setSalida] = useState("18:00");
  const [refri, setRefri] = useState(60);
  const [dias, setDias] = useState<number[]>([1, 2, 3, 4, 5, 6]);
  const [porDia, setPorDia] = useState<PorDia>({});

  function aplicarAnalisis(a: ReturnType<typeof analizar>) {
    setPorDia(a.porDia);
    setDias(a.dias.length ? a.dias : [1, 2, 3, 4, 5, 6]);
    setEntrada(a.e);
    setSalida(a.s);
    setRefri(a.r);
    setModoPorDia(!a.uniforme);
  }
  function toggleDia(v: number) {
    setDias((prev) => (prev.includes(v) ? prev.filter((d) => d !== v) : [...prev, v]));
  }
  function toggleDiaPorDia(d: number) {
    setPorDia((prev) => {
      const next = { ...prev };
      if (next[d]) delete next[d];
      else next[d] = { e: entrada || "08:00", s: salida || "18:00", r: refri || 60 };
      return next;
    });
  }
  function setCampoPorDia(d: number, campo: "e" | "s", val: string) {
    setPorDia((prev) => ({ ...prev, [d]: { ...prev[d], [campo]: val } }));
  }
  function setRefriPorDia(d: number, val: string) {
    const r = Math.max(0, Math.round(Number(val) || 0));
    setPorDia((prev) => ({ ...prev, [d]: { ...prev[d], r } }));
  }
  function cambiarModo(porDiaOn: boolean) {
    if (porDiaOn) {
      const pd: PorDia = {};
      for (const d of dias) pd[d] = { e: entrada, s: salida, r: refri };
      setPorDia(pd);
    } else {
      const ds = Object.keys(porDia).map(Number).sort((a, b) => a - b);
      setDias(ds.length ? ds : [1, 2, 3, 4, 5, 6]);
      const first = ds.length ? porDia[ds[0]] : { e: entrada, s: salida, r: refri };
      setEntrada(first.e); setSalida(first.s); setRefri(first.r);
    }
    setModoPorDia(porDiaOn);
  }
  function construirHorario(): Record<string, Dia> {
    const out: Record<string, Dia> = {};
    if (modoPorDia) {
      for (const [d, v] of Object.entries(porDia)) out[d] = { e: v.e, s: v.s || v.e, r: v.r ?? 0 };
    } else {
      for (const d of dias) out[String(d)] = { e: entrada, s: salida || entrada, r: refri };
    }
    return out;
  }
  const totalSemana = modoPorDia
    ? Object.values(porDia).reduce((acc, v) => acc + horasDia(v.e, v.s, v.r), 0)
    : horasDia(entrada, salida, refri) * dias.length;

  return {
    modoPorDia, entrada, salida, refri, dias, porDia, totalSemana,
    setEntrada, setSalida, setRefri,
    aplicarAnalisis, toggleDia, toggleDiaPorDia, setCampoPorDia, setRefriPorDia, cambiarModo, construirHorario,
  };
}
type FormularioHorario = ReturnType<typeof useFormularioHorario>;

// La grilla de días — toggle "misma hora todos los días" + modo rápido o por
// día. Vive fuera del componente porque las dos instancias del formulario
// (editar una persona, asignar a varias) la dibujan idéntica; solo cambia el
// estado que le pasan.
function GrillaHorario({ f }: { f: FormularioHorario }) {
  return (
    <>
      <CampoCasilla
        etiqueta="Misma hora todos los días"
        checked={!f.modoPorDia}
        onChange={(e) => f.cambiarModo(!e.target.checked)}
        className="mt-4"
      />
      {!f.modoPorDia ? (
        <>
          {/* grid-cols-1 en el teléfono: con grid-cols-3 fijo, a 375px cada
              columna quedaba en ~85px y el input[type=time] nativo (que
              necesita dibujar "--:--" y, en iOS, el indicador am/pm) se
              recortaba — justo en el campo que fija la hora de entrada,
              la que decide si a alguien se le cuenta una tardanza. */}
          <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-3">
            <Campo etiqueta="Entrada" type="time" value={f.entrada} onChange={(e) => f.setEntrada(e.target.value)} />
            <Campo etiqueta="Salida" type="time" value={f.salida} onChange={(e) => f.setSalida(e.target.value)} />
            <CampoSelect etiqueta="Refrigerio" value={f.refri} onChange={(e) => f.setRefri(Number(e.target.value))}>
              {opcionesRefrigerio(f.refri).map((m) => <option key={m} value={m}>{m} min</option>)}
            </CampoSelect>
          </div>
          <p className="mt-2 text-xs text-taupe">Cada día: <span className="text-tinta">{fmtH(horasDia(f.entrada, f.salida, f.refri))}</span></p>
          <div className="mt-3">
            <p className="mb-1.5 text-sm">Días de trabajo <span className="text-taupe">(los que no marcas son descanso)</span></p>
            <div className="flex gap-1.5">
              {DIAS.map((d) => {
                const on = f.dias.includes(d.v);
                return (
                  <button key={d.v} type="button" onClick={() => f.toggleDia(d.v)}
                    className={`h-9 w-9 rounded-control border text-sm ${on ? "border-tinta bg-tinta text-crema" : "border-sand text-taupe hover:bg-sand/40"}`}>
                    {d.l}
                  </button>
                );
              })}
            </div>
            <p className="mt-1.5 text-xs text-taupe">Descanso: {textoDescanso(f.dias)}</p>
          </div>
        </>
      ) : (
        <div className="mt-3">
          <p className="mb-2 text-sm">Horario por día <span className="text-taupe">(apaga el día para descanso)</span></p>
          <div className="flex flex-col gap-1.5">
            {DIAS.map((d) => {
              const dd = f.porDia[d.v];
              const activo = dd !== undefined;
              return (
                <div key={d.v} className="flex flex-wrap items-center gap-1.5">
                  <button type="button" onClick={() => f.toggleDiaPorDia(d.v)}
                    className={`h-8 w-14 shrink-0 rounded-control border text-xs capitalize ${activo ? "border-tinta bg-tinta text-crema" : "border-sand text-taupe hover:bg-sand/40"}`}>
                    {NOMBRE_DIA[d.v].slice(0, 3)}
                  </button>
                  {activo ? (
                    <>
                      <input type="time" value={dd.e} onChange={(e) => f.setCampoPorDia(d.v, "e", e.target.value)} className="w-[90px] rounded-control border px-1.5 py-1 text-sm" />
                      <span className="text-taupe">–</span>
                      <input type="time" value={dd.s} onChange={(e) => f.setCampoPorDia(d.v, "s", e.target.value)} className="w-[90px] rounded-control border px-1.5 py-1 text-sm" />
                      <select value={dd.r} onChange={(e) => f.setRefriPorDia(d.v, e.target.value)} title="refrigerio (min)" className="w-16 rounded-control border border-sand bg-hueso px-1 py-1 text-sm">
                        {opcionesRefrigerio(dd.r).map((m) => <option key={m} value={m}>{m}</option>)}
                      </select>
                      <span className="w-14 text-right text-xs text-tinta">{fmtH(horasDia(dd.e, dd.s, dd.r))}</span>
                    </>
                  ) : <span className="text-sm text-taupe">descanso</span>}
                </div>
              );
            })}
          </div>
          <p className="mt-1.5 text-xs text-taupe">La columna angosta es el refrigerio en minutos.</p>
        </div>
      )}
    </>
  );
}

// La semana visual de "Ver semana →" — un horario que varía por día no dice
// nada con solo la etiqueta; esto es a lo que expande, en la tabla (fila
// nueva) o en la ficha de teléfono (dentro de la misma tarjeta).
function SemanaMini({ a }: { a: ReturnType<typeof analizar> }) {
  return (
    <div className="grid grid-cols-4 gap-2 rounded-control bg-hueso p-3 text-xs sm:grid-cols-7">
      {DIAS.map((d) => {
        const dd = a.porDia[d.v];
        return (
          <div key={d.v} className="flex flex-col items-center gap-1 rounded px-1 py-1.5 text-center">
            <span className="font-medium uppercase tracking-wide text-taupe">{NOMBRE_DIA[d.v].slice(0, 3)}</span>
            {dd ? <span className="tabular-nums text-tinta">{dd.e}–{dd.s}</span> : <span className="text-taupe">Desc.</span>}
          </div>
        );
      })}
    </div>
  );
}

const TILE_CLASE = (activo: boolean) =>
  `rounded-2xl border p-3 text-left transition-colors ${activo ? "border-taupe bg-hueso" : "border-sand bg-papel hover:bg-hueso"}`;

export default function HorariosPage() {
  const router = useRouter();
  const { avisar } = useToast();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [horarios, setHorarios] = useState<Map<string, Horario>>(new Map());
  // Cuando el tramo abierto de `horarios` empieza a futuro, este mapa trae el
  // tramo que SÍ rige hoy — para no mostrar como vigente algo que todavía no
  // entró en efecto. Solo se completa para esas personas, no para las ~30 en
  // cada carga.
  const [vigentesHoy, setVigentesHoy] = useState<Map<string, Horario>>(new Map());
  const [sedes, setSedes] = useState<Record<string, string>>({});
  const [cargando, setCargando] = useState(true);

  // ── Buscador y filtros ──
  const [busca, setBusca] = useState("");
  const [filtroSede, setFiltroSede] = useState("");
  const [filtroEstado, setFiltroEstado] = useState<"" | "con_horario" | "sin_horario">("");
  const [filtroTipoHorario, setFiltroTipoHorario] = useState<"" | "fijo" | "varia">("");
  const [soloProgramados, setSoloProgramados] = useState(false);

  // ── Selección múltiple (asignación masiva) ──
  const [seleccionados, setSeleccionados] = useState<Set<string>>(new Set());

  // ── Fila con "Ver semana →" expandida (una sola a la vez) ──
  const [semanaExpandida, setSemanaExpandida] = useState<string | null>(null);

  // ── Drawer de una persona ──
  const [editando, setEditando] = useState<Persona | null>(null);
  const form = useFormularioHorario();
  const [desde, setDesde] = useState(hoyLima());
  const [motivo, setMotivo] = useState("");
  const [guardando, setGuardando] = useState(false);
  const [copiarDeId, setCopiarDeId] = useState("");
  // Tramos anteriores de la persona en edición, solo lectura (0389: el
  // historial ya vive en `horarios_asignados`, esto solo lo expone).
  const [historial, setHistorial] = useState<Tramo[]>([]);
  const focoAlAbrir = useRef<HTMLElement | null>(null);

  // ── Drawer de asignación masiva ──
  const [masivoAbierto, setMasivoAbierto] = useState(false);
  const formMasivo = useFormularioHorario();
  const [masivoDesde, setMasivoDesde] = useState(hoyLima());
  const [masivoMotivo, setMasivoMotivo] = useState("");
  const [guardandoMasivo, setGuardandoMasivo] = useState(false);
  const focoAlAbrirMasivo = useRef<HTMLElement | null>(null);

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    setCargando(true);
    const [
      { data: p, error: errP },
      { data: h, error: errH },
      { data: s, error: errS },
      { data: f, error: errF },
    ] = await Promise.all([
      supabase.from("personas").select("id, nombres, apellidos, rol, sede_base_id").eq("estado", "activo").order("nombres"),
      supabase.from("horarios_asignados").select("persona_id, hora_entrada, hora_salida, vigente_desde, almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horario_por_dia").is("vigente_hasta", null),
      supabase.from("sedes").select("id, codigo"),
      // tipo_vinculo y practicante_modalidad no viajan en el select de arriba
      // (schema cache de PostgREST): para saber contra qué máximo avisar
      // hace falta esta RPC. Tolerante: si falla, nadie ve el aviso — no se
      // cae la pantalla entera por un dato que hoy es informativo.
      supabase.rpc("fn_personas_funciones"),
    ]);
    if (errP || errH || errS) {
      avisar("error", mensajeDeError((errP ?? errH ?? errS)!, "cargar los horarios"));
      setCargando(false);
      return; // no pisa `personas`/`horarios`/`sedes` con datos parciales
    }
    const vinculos = new Map(
      (errF ? [] : ((f as { persona_id: string; tipo_vinculo?: string; practicante_modalidad?: string | null }[] | null) ?? []))
        .map((x) => [x.persona_id, { tipo_vinculo: x.tipo_vinculo ?? "planilla", practicante_modalidad: x.practicante_modalidad ?? null }] as const),
    );
    setPersonas(
      ((p as Omit<Persona, "tipo_vinculo" | "practicante_modalidad">[]) ?? []).map((x) => {
        const v = vinculos.get(x.id);
        return { ...x, tipo_vinculo: v?.tipo_vinculo ?? "planilla", practicante_modalidad: v?.practicante_modalidad ?? null };
      }),
    );
    const abiertos = (h as Horario[]) ?? [];
    setHorarios(new Map(abiertos.map((x) => [x.persona_id, x])));
    setSedes(Object.fromEntries(((s as any[]) ?? []).map((x) => [x.id, x.codigo])));

    // El tramo abierto puede empezar a futuro (alguien programó un cambio de
    // horario). Para esas personas nada más, trae el tramo que cubre HOY —
    // si no se hace esto, la pantalla muestra un horario que todavía no rige
    // como si ya rigiera (auditoría 2026-09-14).
    const hoy = hoyLima();
    const idsFuturos = abiertos.filter((x) => x.vigente_desde > hoy).map((x) => x.persona_id);
    if (idsFuturos.length > 0) {
      const { data: vh } = await supabase
        .from("horarios_asignados")
        .select("persona_id, hora_entrada, hora_salida, vigente_desde, almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horario_por_dia")
        .in("persona_id", idsFuturos)
        .lte("vigente_desde", hoy)
        .or(`vigente_hasta.is.null,vigente_hasta.gte.${hoy}`);
      setVigentesHoy(new Map(((vh as Horario[]) ?? []).map((x) => [x.persona_id, x])));
    } else {
      setVigentesHoy(new Map());
    }
    setCargando(false);
  }, [router, avisar]);

  useEffect(() => { void cargar(); }, [cargar]);

  const puedeEditar = puedeOperarEquipo(rol);
  const esSupervisor = rol === "supervisor_sede";
  const editables = useMemo(() => {
    if (!esSupervisor || !yo) return personas;
    return personas.filter((p) => p.id !== yo.id && !ROLES_DO.includes(p.rol));
  }, [personas, esSupervisor, yo]);

  const hoy = hoyLima();
  // Lo que rige HOY para una persona: el tramo abierto, salvo que ese tramo
  // empiece a futuro — ahí rige lo que trajo `vigentesHoy` (o nada, si su
  // primer horario todavía no llegó).
  function horarioDeHoy(p: Persona): Horario | undefined {
    const abierto = horarios.get(p.id);
    if (!abierto) return undefined;
    return abierto.vigente_desde > hoy ? vigentesHoy.get(p.id) : abierto;
  }
  // analizar(undefined) NO significa "sin horario": rellena una semana
  // completa 08:00-18:00 de L a S para que el formulario de "Asignar"
  // arranque con algo editable. Este guard es el que hace que "con/sin
  // horario" (filtro, resumen, alerta) signifiquen lo mismo en toda la
  // pantalla — antes de esto el filtro "sin horario" no encontraba a nadie.
  function estadoDeHoy(p: Persona): { con: boolean; tipo: "fijo" | "varia" | null } {
    const h = horarioDeHoy(p);
    const a = h ? analizar(h) : null;
    if (!a || a.dias.length === 0) return { con: false, tipo: null };
    return { con: true, tipo: a.uniforme ? "fijo" : "varia" };
  }

  // Hook: tiene que llamarse siempre, incluso en el render donde más abajo
  // se corta con "no tienes permiso" — por eso vive antes de ese return.
  const filtrados = useMemo(() => {
    const q = sinTildes(busca.trim());
    return editables.filter((p) => {
      if (filtroSede && (sedes[p.sede_base_id] ?? "?") !== filtroSede) return false;
      if (q && !sinTildes(`${p.nombres} ${p.apellidos}`).includes(q)) return false;
      if (filtroEstado || filtroTipoHorario) {
        const estado = estadoDeHoy(p);
        if (filtroEstado === "con_horario" && !estado.con) return false;
        if (filtroEstado === "sin_horario" && estado.con) return false;
        if (filtroTipoHorario && estado.tipo !== filtroTipoHorario) return false;
      }
      if (soloProgramados) {
        const abierto = horarios.get(p.id);
        if (!abierto || abierto.vigente_desde <= hoy) return false;
      }
      return true;
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps -- estadoDeHoy/horarioDeHoy leen horarios/vigentesHoy/hoy, ya listados
  }, [editables, busca, filtroSede, filtroEstado, filtroTipoHorario, soloProgramados, sedes, horarios, vigentesHoy, hoy]);

  function abrirEdicion(p: Persona, boton?: HTMLElement | null) {
    form.aplicarAnalisis(analizar(horarios.get(p.id)));
    setEditando(p);
    setDesde(hoyLima());
    setMotivo("");
    setCopiarDeId("");
    setHistorial([]);
    focoAlAbrir.current = boton ?? null;
    void cargarHistorial(p.id);
  }

  async function cargarHistorial(personaId: string) {
    const supabase = createAdminSupabaseClient();
    const { data } = await supabase
      .from("horarios_asignados")
      .select("persona_id, hora_entrada, hora_salida, vigente_desde, vigente_hasta, almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horario_por_dia")
      .eq("persona_id", personaId)
      .order("vigente_desde", { ascending: false });
    setHistorial((data as Tramo[]) ?? []);
  }

  // "Copiar horario de →": precarga el formulario con el horario vigente de
  // otra persona. Sigue llamando a fn_set_horario_semanal solo para quien se
  // está editando — no toca a la persona de la que se copia.
  function copiarDe(personaId: string) {
    setCopiarDeId(personaId);
    if (!personaId) return;
    const h = horarios.get(personaId);
    if (!h) return;
    form.aplicarAnalisis(analizar(h));
  }

  function toggleSeleccion(id: string) {
    setSeleccionados((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  }

  function abrirMasivo(boton?: HTMLElement | null) {
    formMasivo.aplicarAnalisis(analizar(undefined));
    setMasivoDesde(hoyLima());
    setMasivoMotivo("");
    focoAlAbrirMasivo.current = boton ?? null;
    setMasivoAbierto(true);
  }

  // Cambiar el horario base no toca la tabla `turnos` (fn_set_horario_semanal
  // es limpio en eso), pero puede dejar turnos puntuales VIEJOS apuntando a un
  // tramo que esta persona ya no tiene vigente — el caso de Diana (set-2026):
  // el turno del día MANDA sobre el horario base, así que un "espejo" así
  // sigue generando tardanzas falsas en silencio. Esto solo avisa; el único
  // camino para corregir sigue siendo la pantalla de Turnos, fila por fila.
  async function turnosDesactualizadosPor(supabase: ReturnType<typeof createAdminSupabaseClient>, personaId: string): Promise<string[]> {
    const { data: periodo } = await supabase.from("periodos_planilla")
      .select("fecha_ini").eq("estado", "abierto")
      .order("fecha_ini", { ascending: true }).limit(1).maybeSingle();
    // Sin periodo abierto (caso raro/borde) el piso es hoy, igual que el
    // comportamiento de siempre: no hay planilla corriendo a la que avisarle.
    const piso = periodo?.fecha_ini ?? hoyLima();
    const [{ data: turnosPersona }, { data: tramosHistoricos }] = await Promise.all([
      supabase.from("turnos").select("fecha, hora_entrada, hora_salida, es_descanso")
        .eq("persona_id", personaId).gte("fecha", piso).order("fecha"),
      // Sin filtrar vigente_hasta: hace falta el historial completo para que
      // esTurnoEspejoViejo pueda distinguir "coincide con el vigente" (nada
      // que avisar) de "coincide con uno que ya no lo es" (probable espejo).
      supabase.from("horarios_asignados")
        .select("persona_id, hora_entrada, hora_salida, dias_laborables, horario_por_dia, almuerzo_min_minutos, vigente_desde, vigente_hasta")
        .eq("persona_id", personaId),
    ]);
    const tramos = (tramosHistoricos as HorarioTramo[] | null) ?? [];
    const turnosTyped = (turnosPersona as { fecha: string; hora_entrada: string | null; hora_salida: string | null; es_descanso: boolean }[] | null) ?? [];
    return turnosTyped
      .filter((t) => esTurnoEspejoViejo(t.fecha, { hora_entrada: t.hora_entrada, hora_salida: t.hora_salida, es_descanso: t.es_descanso }, tramos))
      .map((t) => t.fecha);
  }

  async function guardar() {
    if (!editando) return;
    const horario = form.construirHorario();
    const keys = Object.keys(horario);
    if (keys.length === 0) { avisar("error", "Marca al menos un día de trabajo."); return; }
    const faltaEntrada = form.modoPorDia ? Object.values(form.porDia).some((v) => !v.e) : !form.entrada;
    const faltaSalida = form.modoPorDia ? Object.values(form.porDia).some((v) => !v.s) : !form.salida;
    if (faltaEntrada) { avisar("error", "Falta la hora de entrada de algún día."); return; }
    if (faltaSalida) { avisar("error", "Falta la hora de salida de algún día."); return; }
    if (motivo.trim().length < MOTIVO_MIN) { avisar("error", `Escribe el motivo del cambio (mínimo ${MOTIVO_MIN} caracteres).`); return; }
    const personaId = editando.id;
    setGuardando(true);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_set_horario_semanal", {
      p_persona_id: personaId, p_vigente_desde: desde, p_horario: horario, p_motivo: motivo.trim(),
    });
    setGuardando(false);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    setEditando(null);
    await cargar();
    let mensaje = "Horario guardado. Las tardanzas desde esa fecha se recalcularon.";
    try {
      const fechas = await turnosDesactualizadosPor(supabase, personaId);
      if (fechas.length > 0) {
        const esUno = fechas.length === 1;
        const turno = esUno ? "turno puntual" : "turnos puntuales";
        const coincide = esUno ? "coincide" : "coinciden";
        mensaje = `Horario guardado. Ojo: ${fechas.length} ${turno} de esta persona ya no ${coincide} con este horario (fechas: ${fechas.join(", ")}) — revísalos en la pantalla de Turnos.`;
      }
    } catch {
      // El horario ya se guardó bien; solo no se pudo avisar del cruce con turnos.
    }
    avisar("ok", mensaje);
  }

  // Asignación masiva: el mismo RPC de siempre, una vez por persona
  // seleccionada, desde el cliente — mismo patrón que ya usan "Hacer
  // permanente en lote" de Turnos y "Aprobar lote" de Incidencias. Cero
  // cambios de lógica o de esquema.
  async function guardarMasivo() {
    const ids = [...seleccionados];
    if (ids.length === 0) return;
    const horario = formMasivo.construirHorario();
    const keys = Object.keys(horario);
    if (keys.length === 0) { avisar("error", "Marca al menos un día de trabajo."); return; }
    const faltaEntrada = formMasivo.modoPorDia ? Object.values(formMasivo.porDia).some((v) => !v.e) : !formMasivo.entrada;
    const faltaSalida = formMasivo.modoPorDia ? Object.values(formMasivo.porDia).some((v) => !v.s) : !formMasivo.salida;
    if (faltaEntrada) { avisar("error", "Falta la hora de entrada de algún día."); return; }
    if (faltaSalida) { avisar("error", "Falta la hora de salida de algún día."); return; }
    if (masivoMotivo.trim().length < MOTIVO_MIN) { avisar("error", `Escribe el motivo del cambio (mínimo ${MOTIVO_MIN} caracteres).`); return; }
    setGuardandoMasivo(true);
    const supabase = createAdminSupabaseClient();
    const fallidos: string[] = [];
    for (const id of ids) {
      const { error } = await supabase.rpc("fn_set_horario_semanal", {
        p_persona_id: id, p_vigente_desde: masivoDesde, p_horario: horario, p_motivo: masivoMotivo.trim(),
      });
      if (error) {
        const persona = editables.find((x) => x.id === id);
        fallidos.push(persona ? `${persona.nombres} ${persona.apellidos}` : id);
      }
    }
    setGuardandoMasivo(false);
    setMasivoAbierto(false);
    setSeleccionados(new Set());
    await cargar();
    if (fallidos.length === 0) {
      avisar("ok", `Horario asignado a ${ids.length} persona${ids.length === 1 ? "" : "s"}.`);
    } else {
      avisar("error", `No se pudo asignar a: ${fallidos.join(", ")}. El resto sí se guardó.`);
    }
  }

  if (rol !== null && !puedeEditar) {
    return (
      <div className="flex flex-1 flex-col">
        <main className="flex flex-1 items-center justify-center p-6">
          <p className="max-w-md text-center text-taupe">No tienes permiso para editar horarios.</p>
        </main>
      </div>
    );
  }

  const todasLasSedes = [...new Set(editables.map((p) => sedes[p.sede_base_id] ?? "?"))].sort();
  const sinHorarioLista = filtrados.filter((p) => !estadoDeHoy(p).con);
  const porSede = [...new Set(filtrados.map((p) => sedes[p.sede_base_id] ?? "?"))].sort();

  // Resumen superior: sobre `editables` (todo lo que puedes ver), no sobre
  // `filtrados` — si no, los números cambiarían con el filtro que ellos
  // mismos activan, y dejarían de servir como ancla.
  const totalPersonas = editables.length;
  const conHorarioHoy = editables.filter((p) => estadoDeHoy(p).con).length;
  const sinHorarioHoy = totalPersonas - conHorarioHoy;
  const programadosCount = editables.filter((p) => {
    const abierto = horarios.get(p.id);
    return !!abierto && abierto.vigente_desde > hoy;
  }).length;
  const sinFiltrosDeEstado = !filtroEstado && !filtroTipoHorario && !soloProgramados;
  const hayFiltrosActivos = !!busca || !!filtroSede || !sinFiltrosDeEstado;

  function limpiarFiltros() {
    setBusca(""); setFiltroSede(""); setFiltroEstado(""); setFiltroTipoHorario(""); setSoloProgramados(false);
  }
  function toggleEstado(v: "con_horario" | "sin_horario") {
    setFiltroEstado((prev) => (prev === v ? "" : v));
  }

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        <h1 className="mb-1 font-serif text-2xl">Horarios base</h1>
        <div className="mb-5 flex max-w-2xl items-start gap-1.5">
          <p className="text-sm text-taupe">
            Define la jornada semanal y descansos de cada colaborador. Los cambios conservan el historial y pueden
            aplicarse desde una fecha determinada.
          </p>
          <button
            type="button"
            title="El horario de cada persona puede tener una hora distinta por día (martes 8:00, miércoles 14:00…), con su refrigerio, y se repite cada semana. La hora de entrada define la tardanza."
            aria-label="Más información sobre cómo funciona el horario"
            className="mt-0.5 shrink-0 text-taupe hover:text-tinta"
          >
            ⓘ
          </button>
        </div>

        {!cargando && personas.length > 0 && (
          <>
            {/* ── Resumen: sirve para actuar, cada tile es también un filtro ── */}
            <div className="mb-5 grid grid-cols-2 gap-2 sm:grid-cols-4">
              <button type="button" onClick={limpiarFiltros} className={TILE_CLASE(sinFiltrosDeEstado)}>
                <span className="block text-xs text-taupe">Total</span>
                <span className="block font-serif text-2xl tabular-nums text-tinta">{totalPersonas}</span>
              </button>
              <button type="button" onClick={() => toggleEstado("con_horario")} className={TILE_CLASE(filtroEstado === "con_horario")}>
                <span className="block text-xs text-taupe">Con horario</span>
                <span className="block font-serif text-2xl tabular-nums text-verde">{conHorarioHoy}</span>
              </button>
              <button type="button" onClick={() => toggleEstado("sin_horario")} className={TILE_CLASE(filtroEstado === "sin_horario")}>
                <span className="block text-xs text-taupe">Sin horario</span>
                <span className="block font-serif text-2xl tabular-nums text-rojo">{sinHorarioHoy}</span>
              </button>
              <button type="button" onClick={() => setSoloProgramados((v) => !v)} className={TILE_CLASE(soloProgramados)}>
                <span className="block text-xs text-taupe">Programados</span>
                <span className="block font-serif text-2xl tabular-nums text-pizarra">{programadosCount}</span>
              </button>
            </div>

            {/* ── Buscador y filtros ── */}
            <div className="mb-4 grid grid-cols-1 gap-2 sm:grid-cols-[1fr_auto_auto_auto_auto] sm:items-center">
              <div className="relative">
                <Search size={15} strokeWidth={1.8} aria-hidden className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-taupe" />
                <input
                  value={busca}
                  onChange={(e) => setBusca(e.target.value)}
                  placeholder="Buscar persona…"
                  aria-label="Buscar persona"
                  className="w-full rounded-lg border border-sand bg-hueso py-2 pl-9 pr-9 text-sm placeholder:text-taupe/60"
                />
                {busca && (
                  <button onClick={() => setBusca("")} aria-label="Limpiar búsqueda" className="absolute right-2 top-1/2 -translate-y-1/2 px-1 leading-none text-taupe hover:text-tinta">
                    ×
                  </button>
                )}
              </div>
              <CampoSelect value={filtroSede} onChange={(e) => setFiltroSede(e.target.value)} aria-label="Filtrar por sede">
                <option value="">Todas las sedes</option>
                {todasLasSedes.map((sd) => <option key={sd} value={sd}>{sd}</option>)}
              </CampoSelect>
              <CampoSelect value={filtroEstado} onChange={(e) => setFiltroEstado(e.target.value as typeof filtroEstado)} aria-label="Filtrar por estado">
                <option value="">Cualquier estado</option>
                <option value="con_horario">Con horario</option>
                <option value="sin_horario">Sin horario</option>
              </CampoSelect>
              <CampoSelect value={filtroTipoHorario} onChange={(e) => setFiltroTipoHorario(e.target.value as typeof filtroTipoHorario)} aria-label="Filtrar por tipo de horario">
                <option value="">Cualquier tipo</option>
                <option value="fijo">Rango fijo</option>
                <option value="varia">Varía por día</option>
              </CampoSelect>
              {hayFiltrosActivos && (
                <Boton variante="secundario" tamano="sm" onClick={limpiarFiltros}>Limpiar filtros</Boton>
              )}
            </div>
          </>
        )}

        {/* ── Selección múltiple: solo aparece cuando hay algo elegido ── */}
        {seleccionados.size > 0 && (
          <div className="mb-4 flex flex-wrap items-center gap-3 rounded-control border border-taupe/30 bg-hueso px-4 py-2.5 text-sm">
            <span className="font-medium text-tinta">{seleccionados.size} seleccionada{seleccionados.size === 1 ? "" : "s"}</span>
            <Boton variante="primario" tamano="sm" onClick={(e) => abrirMasivo(e.currentTarget)}>Asignar horario →</Boton>
            <Boton variante="secundario" tamano="sm" onClick={() => setSeleccionados(new Set())}>Cancelar selección</Boton>
          </div>
        )}

        {/* Cruza las 4 sedes: sin esto, alguien "sin horario" se pierde bajando
            entre AQP/CCO/LIM/TRU y puede marcar días sin que ninguna tardanza
            se calcule (auditoría 2026-09-14). Compacta: nombres clicables en
            vez de un botón "Asignar" por persona. */}
        {!cargando && sinHorarioLista.length > 0 && (
          <div className="mb-6 rounded-control border border-rojo/30 bg-rojo/10 px-4 py-3">
            <p className="mb-1.5 text-sm font-medium text-rojo-profundo">
              ⚠ {sinHorarioLista.length} persona{sinHorarioLista.length === 1 ? "" : "s"} necesita{sinHorarioLista.length === 1 ? "" : "n"} horario
            </p>
            <div className="flex flex-wrap gap-x-1 gap-y-1 text-sm">
              {sinHorarioLista.map((p, i) => (
                <span key={p.id}>
                  <button type="button" onClick={(e) => abrirEdicion(p, e.currentTarget)} className="text-tinta underline decoration-rojo/40 underline-offset-2 hover:text-rojo-profundo">
                    {p.nombres} {p.apellidos}
                  </button>
                  {i < sinHorarioLista.length - 1 && <span className="text-taupe">, </span>}
                </span>
              ))}
            </div>
          </div>
        )}

        {cargando ? <Cargando /> : porSede.length === 0 ? (
          <p className="text-sm text-taupe">Ninguna persona coincide con la búsqueda o los filtros.</p>
        ) : porSede.map((sede) => {
          const deSede = filtrados.filter((p) => (sedes[p.sede_base_id] ?? "?") === sede);
          return (
            <section key={sede} className="mb-8">
              <h2 className="mb-2 font-serif text-lg">{sede}</h2>

              {/* Escritorio y tablet: tabla. Cabecera fija dentro de su propia
                  sede si crece lo suficiente (alturaMaxima es lo que activa
                  el sticky de TablaEncabezado — ver components/ui/tabla.tsx).
                  Con ~30 personas en 4 sedes esto casi nunca llega a hacer
                  scroll propio; cuando una sede sí crezca, ya está listo. */}
              <div className="hidden sm:block">
                <Tabla className="[font-variant-numeric:tabular-nums]" alturaMaxima="60vh">
                  <TablaEncabezado>
                    <Th className="w-9">{null}</Th>
                    <Th>Nombre</Th>
                    <Th>Horario</Th>
                    <Th>Horas semanales</Th>
                    <Th>Descanso</Th>
                    <Th>Vigente desde</Th>
                    <Th>{null}</Th>
                  </TablaEncabezado>
                  <tbody>
                    {deSede.map((p) => {
                      const abierto = horarios.get(p.id);
                      const programado = !!abierto && abierto.vigente_desde > hoy;
                      const h = horarioDeHoy(p);
                      const a = h ? analizar(h) : null;
                      const semana = a ? a.dias.reduce((acc, d) => acc + horasDia(a.porDia[d].e, a.porDia[d].s, a.porDia[d].r), 0) : 0;
                      // Máximo legal de una practicante (0324, art. 44 Ley 28518). `null`
                      // para cualquiera que no sea practicante, o que lo sea pero sin
                      // modalidad fijada todavía — en los dos casos no hay contra qué avisar.
                      const maxLegal = maximoSemanalPracticante(p.tipo_vinculo, p.practicante_modalidad);
                      const seExcede = maxLegal !== null && a && a.dias.length > 0 && semana > maxLegal + 0.01;
                      const aFuturo = programado ? analizar(abierto) : null;
                      const resumenFuturo = aFuturo
                        ? (aFuturo.dias.length === 0 ? "sin días" : aFuturo.uniforme ? `${aFuturo.e}–${aFuturo.s}` : "varía por día")
                        : "";
                      const expandida = semanaExpandida === p.id;
                      return (
                        <Fragment key={p.id}>
                          <Fila>
                            <td className="px-2 py-2">
                              <input
                                type="checkbox"
                                checked={seleccionados.has(p.id)}
                                onChange={() => toggleSeleccion(p.id)}
                                className="size-4 accent-tinta"
                                aria-label={`Seleccionar a ${p.nombres} ${p.apellidos}`}
                              />
                            </td>
                            <td className="px-4 py-2">{p.nombres} {p.apellidos}</td>
                            <td className="px-4 py-2">
                              {!a || a.dias.length === 0 ? (
                                <span className="text-taupe">sin horario{programado ? " hoy" : ""}</span>
                              ) : a.uniforme ? (
                                `${a.e}–${a.s}`
                              ) : (
                                <button
                                  type="button"
                                  onClick={() => setSemanaExpandida((x) => (x === p.id ? null : p.id))}
                                  className="text-pizarra hover:text-tinta"
                                >
                                  varía por día · {expandida ? "Ocultar" : "Ver semana →"}
                                </button>
                              )}
                              {programado && (
                                <p className="mt-1 flex items-center gap-1.5 text-xs text-taupe">
                                  <Insignia variante="informativo" tamano="sm">Programado</Insignia>
                                  <span>desde {fechaCorta(abierto!.vigente_desde)} → {resumenFuturo}</span>
                                </p>
                              )}
                            </td>
                            <td className="px-4 py-2 text-taupe">
                              {a && a.dias.length ? fmtH(semana) : "—"}
                              {seExcede && (
                                // El título con la cita legal se conserva envolviendo la
                                // Insignia: el primitivo no reenvía props sueltas como
                                // `title` (ver components/ui/insignia.tsx).
                                <span title={`Supera el máximo legal de ${maxLegal} h/semana de una practicante ${p.practicante_modalidad} (art. 44, Ley 28518)`}>
                                  <Insignia variante="alerta" className="ml-1.5">supera {maxLegal} h legales</Insignia>
                                </span>
                              )}
                              {maxLegal === null && p.tipo_vinculo === "practicante" && !p.practicante_modalidad && (
                                <span title="Sin modalidad fijada en Equipo, no se puede avisar de su máximo legal">
                                  <Insignia variante="advertencia" className="ml-1.5">falta su modalidad</Insignia>
                                </span>
                              )}
                            </td>
                            <td className="px-4 py-2 text-taupe">{a ? textoDescanso(a.dias) : "—"}</td>
                            <td className="px-4 py-2 text-taupe">{h ? fechaCorta(h.vigente_desde) : "—"}</td>
                            <td className="px-4 py-2">
                              <Boton variante="secundario" tamano="sm" onClick={(e) => abrirEdicion(p, e.currentTarget)}>
                                {abierto ? "Cambiar" : "Asignar"}
                              </Boton>
                            </td>
                          </Fila>
                          {expandida && a && (
                            <tr className="border-t border-sand bg-hueso/50">
                              <td colSpan={7} className="px-4 py-3">
                                <SemanaMini a={a} />
                              </td>
                            </tr>
                          )}
                        </Fragment>
                      );
                    })}
                  </tbody>
                </Tabla>
              </div>

              {/* Teléfono: cada persona como ficha, no una tabla comprimida —
                  mismo criterio que ya usan Contratos y Dashboard. */}
              <div className="flex flex-col divide-y divide-sand border-t border-sand sm:hidden">
                {deSede.map((p) => {
                  const abierto = horarios.get(p.id);
                  const programado = !!abierto && abierto.vigente_desde > hoy;
                  const h = horarioDeHoy(p);
                  const a = h ? analizar(h) : null;
                  const semana = a ? a.dias.reduce((acc, d) => acc + horasDia(a.porDia[d].e, a.porDia[d].s, a.porDia[d].r), 0) : 0;
                  const aFuturo = programado ? analizar(abierto) : null;
                  const resumenFuturo = aFuturo
                    ? (aFuturo.dias.length === 0 ? "sin días" : aFuturo.uniforme ? `${aFuturo.e}–${aFuturo.s}` : "varía por día")
                    : "";
                  const expandida = semanaExpandida === p.id;
                  return (
                    <div key={p.id} className="flex flex-col gap-2 p-4">
                      <div className="flex items-start justify-between gap-2">
                        <label className="flex items-start gap-2">
                          <input
                            type="checkbox"
                            checked={seleccionados.has(p.id)}
                            onChange={() => toggleSeleccion(p.id)}
                            className="mt-0.5 size-4 accent-tinta"
                            aria-label={`Seleccionar a ${p.nombres} ${p.apellidos}`}
                          />
                          <span>
                            <span className="block text-sm font-medium text-tinta">{p.nombres} {p.apellidos}</span>
                            <span className="block text-xs text-taupe">{sede}</span>
                          </span>
                        </label>
                        <Boton variante="secundario" tamano="sm" onClick={(e) => abrirEdicion(p, e.currentTarget)}>
                          {abierto ? "Cambiar" : "Asignar"}
                        </Boton>
                      </div>
                      <p className="text-sm">
                        {!a || a.dias.length === 0 ? (
                          <span className="text-taupe">sin horario{programado ? " hoy" : ""}</span>
                        ) : a.uniforme ? (
                          `${a.e}–${a.s}`
                        ) : (
                          <button type="button" onClick={() => setSemanaExpandida((x) => (x === p.id ? null : p.id))} className="text-pizarra">
                            varía por día · {expandida ? "Ocultar" : "Ver semana →"}
                          </button>
                        )}
                      </p>
                      <p className="text-xs text-taupe">
                        {a && a.dias.length ? fmtH(semana) : "—"} · Descanso {a ? textoDescanso(a.dias) : "—"}
                      </p>
                      <p className="text-xs text-taupe">Vigente desde {h ? fechaCorta(h.vigente_desde) : "—"}</p>
                      {programado && (
                        <p className="flex items-center gap-1.5 text-xs text-taupe">
                          <Insignia variante="informativo" tamano="sm">Programado</Insignia>
                          <span>desde {fechaCorta(abierto!.vigente_desde)} → {resumenFuturo}</span>
                        </p>
                      )}
                      {expandida && a && <SemanaMini a={a} />}
                    </div>
                  );
                })}
              </div>
            </section>
          );
        })}

        {/* ── Drawer: editar / asignar una persona ── */}
        <Drawer
          abierto={editando !== null}
          onCerrar={() => setEditando(null)}
          bloqueado={guardando}
          titulo={editando ? `Horario de ${editando.nombres} ${editando.apellidos}` : undefined}
          volverElFocoA={focoAlAbrir}
        >
          <p className="mb-4 text-sm text-taupe">
            Este horario será válido desde la fecha que elijas. El horario anterior se conserva para fechas
            anteriores.
          </p>

          <div className="grid grid-cols-1 gap-3">
            <Campo etiqueta="Vigente desde" type="date" value={desde} onChange={(e) => setDesde(e.target.value)} />
            <CampoSelect etiqueta="Copiar horario de →" value={copiarDeId} onChange={(e) => copiarDe(e.target.value)}>
              <option value="">(elegir a alguien)</option>
              {editables
                .filter((x) => x.id !== editando?.id && horarios.has(x.id))
                .map((x) => (
                  <option key={x.id} value={x.id}>{x.nombres} {x.apellidos}</option>
                ))}
            </CampoSelect>
          </div>

          {historial.length > 1 && (
            <details className="mt-3 rounded-control bg-hueso px-3 py-2 text-sm">
              <summary className="cursor-pointer text-taupe">Historial de horario ({historial.length})</summary>
              <ul className="mt-2 flex flex-col gap-1.5">
                {historial.map((t, i) => {
                  const at = analizar(t);
                  const resumen = at.dias.length === 0 ? "sin días"
                    : at.uniforme ? `${at.e}–${at.s}, ${textoDescanso(at.dias)}` : "varía por día";
                  const esActual = i === 0;
                  return (
                    <li key={`${t.vigente_desde}-${t.vigente_hasta ?? "abierto"}`} className="flex items-center justify-between gap-2 text-xs text-taupe">
                      <span>
                        <span className="text-tinta">{fechaCorta(t.vigente_desde)}</span>
                        {" — "}{esActual ? "actual" : (t.vigente_hasta ? fechaCorta(t.vigente_hasta) : "hoy")} · {resumen}
                      </span>
                      {!esActual && (
                        <button type="button" onClick={() => form.aplicarAnalisis(at)} className="shrink-0 text-pizarra underline hover:text-tinta">
                          Volver a usar este
                        </button>
                      )}
                    </li>
                  );
                })}
              </ul>
            </details>
          )}

          <GrillaHorario f={form} />

          {(() => {
            // Para una practicante, "meta 45h" no significa nada: lo que
            // importa es si se pasa del MÁXIMO LEGAL de su modalidad
            // (0324, art. 44 Ley 28518) — un número muy distinto de la
            // meta genérica de jornada del resto del equipo, y que si se
            // cruza no es un objetivo de más, es una jornada que no le
            // corresponde por ley.
            const maxLegal = editando ? maximoSemanalPracticante(editando.tipo_vinculo, editando.practicante_modalidad) : null;
            if (maxLegal !== null) {
              const seExcede = form.totalSemana > maxLegal + 0.01;
              return (
                <div className={`mt-4 rounded-control px-3 py-2 text-sm ${seExcede ? "bg-rojo/10" : "bg-sand/30"}`}>
                  Total semana: <span className="font-medium text-tinta">{fmtH(form.totalSemana)}</span>
                  <span className="text-taupe"> · máximo legal {maxLegal} h ({editando?.practicante_modalidad})</span>
                  {seExcede && (
                    <span className="text-rojo"> — supera el máximo del art. 44, Ley 28518, por {fmtH(form.totalSemana - maxLegal)}</span>
                  )}
                </div>
              );
            }
            if (editando?.tipo_vinculo === "practicante") {
              return (
                <div className="mt-4 rounded-control bg-ambar/10 px-3 py-2 text-sm text-ambar">
                  Total semana: {fmtH(form.totalSemana)} — falta fijarle la modalidad en Equipo (preprofesional o
                  profesional) para poder avisar si esto supera su máximo legal.
                </div>
              );
            }
            return (
              <div className="mt-4 rounded-control bg-sand/30 px-3 py-2 text-sm">
                Total semana: <span className="font-medium text-tinta">{fmtH(form.totalSemana)}</span>
                <span className="text-taupe"> · meta {META_SEMANA} h</span>
                {form.totalSemana > META_SEMANA + 0.01 && <span className="text-ambar"> (te pasas {fmtH(form.totalSemana - META_SEMANA)})</span>}
                {form.totalSemana < META_SEMANA - 0.01 && <span className="text-taupe"> (faltan {fmtH(META_SEMANA - form.totalSemana)})</span>}
              </div>
            );
          })()}

          <div className="mt-4">
            <AreaTexto
              etiqueta="Motivo del cambio"
              value={motivo}
              onChange={(e) => setMotivo(e.target.value)}
              placeholder="Por qué cambia — quién lo pidió, para qué, qué operativa lo justifica…"
              rows={4}
            />
            <ContadorMotivo texto={motivo} />
          </div>

          <div className="mt-5 flex justify-end gap-3">
            <Boton variante="secundario" onClick={() => setEditando(null)} disabled={guardando}>Cancelar</Boton>
            <Boton variante="primario" onClick={guardar} cargando={guardando}>Guardar horario</Boton>
          </div>
        </Drawer>

        {/* ── Drawer: asignación masiva ── */}
        <Drawer
          abierto={masivoAbierto}
          onCerrar={() => setMasivoAbierto(false)}
          bloqueado={guardandoMasivo}
          titulo={`Asignar horario a ${seleccionados.size} persona${seleccionados.size === 1 ? "" : "s"}`}
          volverElFocoA={focoAlAbrirMasivo}
        >
          <p className="mb-4 text-sm text-taupe">
            Este horario será válido desde la fecha que elijas, para cada una de las personas seleccionadas. El
            horario anterior de cada una se conserva para fechas anteriores.
          </p>

          <Campo etiqueta="Vigente desde" type="date" value={masivoDesde} onChange={(e) => setMasivoDesde(e.target.value)} />

          <GrillaHorario f={formMasivo} />

          {(() => {
            const practicantes = [...seleccionados]
              .map((id) => editables.find((p) => p.id === id))
              .filter((p): p is Persona => !!p && p.tipo_vinculo === "practicante");
            if (practicantes.length === 0) return null;
            const excedidas = practicantes.filter((p) => {
              const max = maximoSemanalPracticante(p.tipo_vinculo, p.practicante_modalidad);
              return max !== null && formMasivo.totalSemana > max + 0.01;
            });
            return (
              <div className={`mt-4 rounded-control px-3 py-2 text-sm ${excedidas.length ? "bg-rojo/10 text-rojo" : "bg-ambar/10 text-ambar"}`}>
                {excedidas.length > 0
                  ? `Supera el máximo legal de ${excedidas.length} practicante${excedidas.length === 1 ? "" : "s"} seleccionada${excedidas.length === 1 ? "" : "s"}: ${excedidas.map((p) => `${p.nombres} ${p.apellidos}`).join(", ")}.`
                  : `${practicantes.length} de las seleccionadas ${practicantes.length === 1 ? "es practicante" : "son practicantes"} — verifica su máximo legal por separado.`}
              </div>
            );
          })()}

          <div className="mt-4 rounded-control bg-sand/30 px-3 py-2 text-sm">
            Total semana: <span className="font-medium text-tinta">{fmtH(formMasivo.totalSemana)}</span>
          </div>

          <div className="mt-4">
            <AreaTexto
              etiqueta="Motivo del cambio"
              value={masivoMotivo}
              onChange={(e) => setMasivoMotivo(e.target.value)}
              placeholder="Por qué cambia — qué operativa lo justifica, por qué a este grupo…"
              rows={4}
            />
            <ContadorMotivo texto={masivoMotivo} />
          </div>

          <div className="mt-5 flex justify-end gap-3">
            <Boton variante="secundario" onClick={() => setMasivoAbierto(false)} disabled={guardandoMasivo}>Cancelar</Boton>
            <Boton variante="primario" onClick={guardarMasivo} cargando={guardandoMasivo}>Guardar para {seleccionados.size}</Boton>
          </div>
        </Drawer>
      </main>
    </div>
  );
}

"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Search } from "lucide-react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { Cargando } from "@/components/cargando";
import { useToast } from "@/components/toast";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { Tabla, TablaEncabezado, Th, Fila } from "@/components/ui/tabla";
import { Insignia } from "@/components/ui/insignia";
import { Modal } from "@/components/ui/modal";
import { ROLES_DO, hoyLima, puedeOperarEquipo, maximoSemanalPracticante } from "@cayla-dynamic/shared";
// horasDia() reimplementaba (salida − entrada) − refrigerio a mano, sin el
// ajuste "si la salida no es posterior a la entrada, el turno cruza
// medianoche" que horasEntre() ya resuelve (turnos/page.tsx también la
// reusa). Sin eso, un horario nocturno (p. ej. 21:00–05:00) daba 0 horas en
// vez de las ocho reales, escondiendo el aviso de exceso legal semanal de
// una practicante.
import { horasEntre as horasDia } from "@/lib/admin/jornada-esperada";

const META_SEMANA = 45; // horas objetivo por semana (7.5h × 6 días)

function fmtH(h: number): string {
  return `${Math.round(h * 100) / 100} h`;
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
// Para el historial de tramos del modal — igual que Horario, con el cierre.
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

export default function HorariosPage() {
  const router = useRouter();
  const { avisar } = useToast();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [horarios, setHorarios] = useState<Map<string, Horario>>(new Map());
  // Cuando el tramo abierto de `horarios` empieza a futuro (badge "Programado"),
  // este mapa trae el tramo que SÍ rige hoy — para no mostrar como vigente algo
  // que todavía no entró en efecto. Solo se completa para esas personas, no
  // para las ~30 en cada carga.
  const [vigentesHoy, setVigentesHoy] = useState<Map<string, Horario>>(new Map());
  const [sedes, setSedes] = useState<Record<string, string>>({});
  const [cargando, setCargando] = useState(true);
  const [busca, setBusca] = useState("");
  const [filtroSede, setFiltroSede] = useState("");
  const [filtroTipo, setFiltroTipo] = useState<"" | "sin_horario" | "fijo" | "varia">("");

  const [editando, setEditando] = useState<Persona | null>(null);
  const [modoPorDia, setModoPorDia] = useState(false);
  const [entrada, setEntrada] = useState("08:00");   // modo rápido
  const [salida, setSalida] = useState("18:00");     // modo rápido
  const [refri, setRefri] = useState(60);            // modo rápido (min)
  const [dias, setDias] = useState<number[]>([1, 2, 3, 4, 5, 6]);
  const [porDia, setPorDia] = useState<PorDia>({});  // modo por día
  const [desde, setDesde] = useState(hoyLima());
  const [motivo, setMotivo] = useState("");
  const [guardando, setGuardando] = useState(false);
  const [copiarDeId, setCopiarDeId] = useState("");
  // Tramos anteriores de la persona en edición, solo lectura (0389: el
  // historial ya vive en `horarios_asignados`, esto solo lo expone).
  const [historial, setHistorial] = useState<Tramo[]>([]);

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

  // Hook: tiene que llamarse siempre, incluso en el render donde más abajo
  // se corta con "no tienes permiso" — por eso vive antes de ese return.
  const filtrados = useMemo(() => {
    const q = sinTildes(busca.trim());
    return editables.filter((p) => {
      if (filtroSede && (sedes[p.sede_base_id] ?? "?") !== filtroSede) return false;
      if (q && !sinTildes(`${p.nombres} ${p.apellidos}`).includes(q)) return false;
      if (filtroTipo) {
        // analizar(undefined) NO significa "sin horario": rellena una semana
        // completa 08:00-18:00 de L a S para que el formulario de "Asignar"
        // arranque con algo editable. Sin este guard (el mismo que ya usa la
        // fila de la tabla), este filtro nunca encontraba a nadie.
        const h = horarioDeHoy(p);
        const a = h ? analizar(h) : null;
        const tipo = !a || a.dias.length === 0 ? "sin_horario" : a.uniforme ? "fijo" : "varia";
        if (tipo !== filtroTipo) return false;
      }
      return true;
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps -- horarioDeHoy lee horarios/vigentesHoy/hoy, ya listados
  }, [editables, busca, filtroSede, filtroTipo, sedes, horarios, vigentesHoy, hoy]);

  function aplicarAnalisis(a: ReturnType<typeof analizar>) {
    setPorDia(a.porDia);
    setDias(a.dias.length ? a.dias : [1, 2, 3, 4, 5, 6]);
    setEntrada(a.e);
    setSalida(a.s);
    setRefri(a.r);
    setModoPorDia(!a.uniforme);
  }

  function abrirEdicion(p: Persona) {
    aplicarAnalisis(analizar(horarios.get(p.id)));
    setEditando(p);
    setDesde(hoyLima());
    setMotivo("");
    setCopiarDeId("");
    setHistorial([]);
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
    aplicarAnalisis(analizar(h));
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

  async function guardar() {
    if (!editando) return;
    const horario = construirHorario();
    const keys = Object.keys(horario);
    if (keys.length === 0) { avisar("error", "Marca al menos un día de trabajo."); return; }
    const faltaEntrada = modoPorDia ? Object.values(porDia).some((v) => !v.e) : !entrada;
    const faltaSalida = modoPorDia ? Object.values(porDia).some((v) => !v.s) : !salida;
    if (faltaEntrada) { avisar("error", "Falta la hora de entrada de algún día."); return; }
    if (faltaSalida) { avisar("error", "Falta la hora de salida de algún día."); return; }
    if (motivo.trim().length < 3) { avisar("error", "Escribe el motivo del cambio (mínimo 3 caracteres)."); return; }
    setGuardando(true);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_set_horario_semanal", {
      p_persona_id: editando.id, p_vigente_desde: desde, p_horario: horario, p_motivo: motivo.trim(),
    });
    setGuardando(false);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    setEditando(null);
    await cargar();
    avisar("ok", "Horario guardado. Las tardanzas desde esa fecha se recalcularon.");
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
  const sinHorario = filtrados.filter((p) => !horarios.has(p.id));
  const porSede = [...new Set(filtrados.map((p) => sedes[p.sede_base_id] ?? "?"))].sort();

  // total semanal del formulario abierto
  const totalSemana = modoPorDia
    ? Object.values(porDia).reduce((acc, v) => acc + horasDia(v.e, v.s, v.r), 0)
    : horasDia(entrada, salida, refri) * dias.length;

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        <h1 className="mb-1 font-serif text-2xl">Horarios base</h1>
        <p className="mb-5 max-w-2xl text-sm text-taupe">
          El horario de cada persona puede tener una hora distinta por día (martes 8:00, miércoles 14:00…),
          con su refrigerio, y se repite cada semana. La hora de entrada define la tardanza. Al cambiar un
          horario, elige la fecha desde la que aplica — el anterior se conserva y no altera tardanzas pasadas.
        </p>

        {!cargando && personas.length > 0 && (
          <div className="mb-5 grid grid-cols-1 gap-2 sm:grid-cols-[1fr_auto_auto]">
            <div className="relative">
              <Search size={15} strokeWidth={1.8} aria-hidden className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-taupe" />
              <input
                value={busca}
                onChange={(e) => setBusca(e.target.value)}
                placeholder="Buscar por nombre…"
                aria-label="Buscar por nombre"
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
            <CampoSelect value={filtroTipo} onChange={(e) => setFiltroTipo(e.target.value as typeof filtroTipo)} aria-label="Filtrar por tipo de horario">
              <option value="">Cualquier tipo</option>
              <option value="sin_horario">Sin horario hoy</option>
              <option value="fijo">Rango fijo</option>
              <option value="varia">Varía por día</option>
            </CampoSelect>
          </div>
        )}

        {/* Cruza las 4 sedes: sin esto, alguien "sin horario" se pierde bajando
            entre AQP/CCO/LIM/TRU y puede marcar días sin que ninguna tardanza
            se calcule (auditoría 2026-09-14). */}
        {!cargando && sinHorario.length > 0 && (
          <div className="mb-6 rounded-control border border-rojo/30 bg-rojo/10 px-4 py-3">
            <p className="mb-2 text-sm font-medium text-rojo-profundo">
              Sin horario asignado ({sinHorario.length})
            </p>
            <ul className="flex flex-wrap gap-x-4 gap-y-1.5">
              {sinHorario.map((p) => (
                <li key={p.id} className="flex items-center gap-2 text-sm text-tinta">
                  {p.nombres} {p.apellidos}
                  <Boton variante="secundario" tamano="sm" onClick={() => abrirEdicion(p)}>Asignar</Boton>
                </li>
              ))}
            </ul>
          </div>
        )}

        {cargando ? <Cargando /> : porSede.length === 0 ? (
          <p className="text-sm text-taupe">Ninguna persona coincide con la búsqueda o los filtros.</p>
        ) : porSede.map((sede) => {
          const deSede = filtrados.filter((p) => (sedes[p.sede_base_id] ?? "?") === sede);
          return (
            <section key={sede} className="mb-8">
              <h2 className="mb-2 font-serif text-lg">{sede}</h2>
              <Tabla className="[font-variant-numeric:tabular-nums]">
                <TablaEncabezado>
                  <Th>Nombre</Th>
                  <Th>Horario</Th>
                  <Th>Semana</Th>
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
                    return (
                      <Fila key={p.id}>
                        <td className="px-4 py-2">{p.nombres} {p.apellidos}</td>
                        <td className="px-4 py-2">
                          {!a || a.dias.length === 0 ? <span className="text-taupe">sin horario{programado ? " hoy" : ""}</span>
                            : a.uniforme ? `${a.e}–${a.s}` : <span className="text-taupe">varía por día</span>}
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
                        <td className="px-4 py-2 text-taupe">
                          {abierto ? abierto.vigente_desde : "—"}
                          {programado && (
                            <span title={`Este horario recién rige desde el ${abierto!.vigente_desde}. Hasta entonces sigue aplicando el de arriba.`}>
                              <Insignia variante="informativo" className="ml-1.5">Programado</Insignia>
                            </span>
                          )}
                        </td>
                        <td className="px-4 py-2">
                          <Boton variante="secundario" tamano="sm" onClick={() => abrirEdicion(p)}>
                            {abierto ? "Cambiar" : "Asignar"}
                          </Boton>
                        </td>
                      </Fila>
                    );
                  })}
                </tbody>
              </Tabla>
            </section>
          );
        })}

        <Modal
          abierto={editando !== null}
          onCerrar={() => setEditando(null)}
          bloqueado={guardando}
          titulo={editando ? `Horario de ${editando.nombres} ${editando.apellidos}` : undefined}
        >
          <p className="mb-4 text-sm text-taupe">El nuevo horario aplica desde la fecha que elijas en adelante.</p>

          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
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
              {/* El primer tramo de `historial` (orden desc por vigente_desde) es
                  siempre el vigente — ya está a la vista en el formulario de
                  arriba, por eso la lista arranca en el segundo. */}
              <summary className="cursor-pointer text-taupe">Ver horarios anteriores ({historial.length - 1})</summary>
              <ul className="mt-2 flex flex-col gap-1.5">
                {historial.slice(1).map((t) => {
                  const at = analizar(t);
                  const resumen = at.dias.length === 0 ? "sin días"
                    : at.uniforme ? `${at.e}–${at.s}, ${textoDescanso(at.dias)}` : "varía por día";
                  return (
                    <li key={`${t.vigente_desde}-${t.vigente_hasta ?? "abierto"}`} className="text-xs text-taupe">
                      <span className="text-tinta">{t.vigente_desde}</span> – {t.vigente_hasta ?? "hoy"} · {resumen}
                    </li>
                  );
                })}
              </ul>
            </details>
          )}

          <label className="mt-4 flex items-center gap-2 text-sm">
            {/* Casilla suelta: todavía no existe <CampoCasilla> en
                components/ui/campo.tsx (Fase A no la agregó pese a lo
                anunciado) — se deja con las clases que ese primitivo va a
                necesitar (accent-tinta, size-4) para que migrar sea trivial
                en cuanto exista. */}
            <input type="checkbox" checked={!modoPorDia} onChange={(e) => cambiarModo(!e.target.checked)} className="size-4 rounded border-sand accent-tinta" />
            Misma hora todos los días
          </label>

          {!modoPorDia ? (
            <>
              {/* grid-cols-1 en el teléfono: con grid-cols-3 fijo, a 375px cada
                  columna quedaba en ~85px y el input[type=time] nativo (que
                  necesita dibujar "--:--" y, en iOS, el indicador am/pm) se
                  recortaba — justo en el campo que fija la hora de entrada,
                  la que decide si a alguien se le cuenta una tardanza. */}
              <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-3">
                <Campo etiqueta="Entrada" type="time" value={entrada} onChange={(e) => setEntrada(e.target.value)} />
                <Campo etiqueta="Salida" type="time" value={salida} onChange={(e) => setSalida(e.target.value)} />
                <CampoSelect etiqueta="Refrigerio" value={refri} onChange={(e) => setRefri(Number(e.target.value))}>
                  {opcionesRefrigerio(refri).map((m) => <option key={m} value={m}>{m} min</option>)}
                </CampoSelect>
              </div>
              <p className="mt-2 text-xs text-taupe">Cada día: <span className="text-tinta">{fmtH(horasDia(entrada, salida, refri))}</span></p>
              <div className="mt-3">
                <p className="mb-1.5 text-sm">Días de trabajo <span className="text-taupe">(los que no marcas son descanso)</span></p>
                <div className="flex gap-1.5">
                  {DIAS.map((d) => {
                    const on = dias.includes(d.v);
                    return (
                      <button key={d.v} type="button" onClick={() => toggleDia(d.v)}
                        className={`h-9 w-9 rounded-control border text-sm ${on ? "border-tinta bg-tinta text-crema" : "border-sand text-taupe hover:bg-sand/40"}`}>
                        {d.l}
                      </button>
                    );
                  })}
                </div>
                <p className="mt-1.5 text-xs text-taupe">Descanso: {textoDescanso(dias)}</p>
              </div>
            </>
          ) : (
            <div className="mt-3">
              <p className="mb-2 text-sm">Horario por día <span className="text-taupe">(apaga el día para descanso)</span></p>
              <div className="flex flex-col gap-1.5">
                {DIAS.map((d) => {
                  const dd = porDia[d.v];
                  const activo = dd !== undefined;
                  return (
                    <div key={d.v} className="flex flex-wrap items-center gap-1.5">
                      <button type="button" onClick={() => toggleDiaPorDia(d.v)}
                        className={`h-8 w-14 shrink-0 rounded-control border text-xs capitalize ${activo ? "border-tinta bg-tinta text-crema" : "border-sand text-taupe hover:bg-sand/40"}`}>
                        {NOMBRE_DIA[d.v].slice(0, 3)}
                      </button>
                      {activo ? (
                        <>
                          <input type="time" value={dd.e} onChange={(e) => setCampoPorDia(d.v, "e", e.target.value)} className="w-[90px] rounded-control border px-1.5 py-1 text-sm" />
                          <span className="text-taupe">–</span>
                          <input type="time" value={dd.s} onChange={(e) => setCampoPorDia(d.v, "s", e.target.value)} className="w-[90px] rounded-control border px-1.5 py-1 text-sm" />
                          <select value={dd.r} onChange={(e) => setRefriPorDia(d.v, e.target.value)} title="refrigerio (min)" className="w-16 rounded-control border border-sand bg-hueso px-1 py-1 text-sm">
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

          {(() => {
            // Para una practicante, "meta 45h" no significa nada: lo que
            // importa es si se pasa del MÁXIMO LEGAL de su modalidad
            // (0324, art. 44 Ley 28518) — un número muy distinto de la
            // meta genérica de jornada del resto del equipo, y que si se
            // cruza no es un objetivo de más, es una jornada que no le
            // corresponde por ley.
            const maxLegal = editando ? maximoSemanalPracticante(editando.tipo_vinculo, editando.practicante_modalidad) : null;
            if (maxLegal !== null) {
              const seExcede = totalSemana > maxLegal + 0.01;
              return (
                <div className={`mt-4 rounded-control px-3 py-2 text-sm ${seExcede ? "bg-rojo/10" : "bg-sand/30"}`}>
                  Total semana: <span className="font-medium text-tinta">{fmtH(totalSemana)}</span>
                  <span className="text-taupe"> · máximo legal {maxLegal} h ({editando?.practicante_modalidad})</span>
                  {seExcede && (
                    <span className="text-rojo"> — supera el máximo del art. 44, Ley 28518, por {fmtH(totalSemana - maxLegal)}</span>
                  )}
                </div>
              );
            }
            if (editando?.tipo_vinculo === "practicante") {
              return (
                <div className="mt-4 rounded-control bg-ambar/10 px-3 py-2 text-sm text-ambar">
                  Total semana: {fmtH(totalSemana)} — falta fijarle la modalidad en Equipo (preprofesional o
                  profesional) para poder avisar si esto supera su máximo legal.
                </div>
              );
            }
            return (
              <div className="mt-4 rounded-control bg-sand/30 px-3 py-2 text-sm">
                Total semana: <span className="font-medium text-tinta">{fmtH(totalSemana)}</span>
                <span className="text-taupe"> · meta {META_SEMANA} h</span>
                {totalSemana > META_SEMANA + 0.01 && <span className="text-ambar"> (te pasas {fmtH(totalSemana - META_SEMANA)})</span>}
                {totalSemana < META_SEMANA - 0.01 && <span className="text-taupe"> (faltan {fmtH(META_SEMANA - totalSemana)})</span>}
              </div>
            );
          })()}

          <div className="mt-4">
            <AreaTexto
              etiqueta="Motivo del cambio"
              value={motivo}
              onChange={(e) => setMotivo(e.target.value)}
              placeholder="Por qué cambia — ej. lo pidió para estudiar, ajuste operativo de la sede…"
            />
          </div>

          <div className="mt-5 flex justify-end gap-3">
            <Boton variante="secundario" onClick={() => setEditando(null)} disabled={guardando}>Cancelar</Boton>
            <Boton variante="primario" onClick={guardar} cargando={guardando}>Guardar horario</Boton>
          </div>
        </Modal>
      </main>
    </div>
  );
}

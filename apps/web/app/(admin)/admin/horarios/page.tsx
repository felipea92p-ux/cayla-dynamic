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
import { EtiquetaPrueba, usePruebasPorPersona } from "@/components/pruebas/etiqueta-prueba";
import { Drawer } from "@/components/ui/drawer";
// Drawer y Modal son hermanos, no uno el reemplazo del otro (lo dice la
// cabecera de modal.tsx). El drawer de 460px es el sitio correcto para editar
// UN horario; la corrección retroactiva enseña antes una tabla comparativa de
// cinco columnas por jornada, y esa no se lee en una columna estrecha con
// scroll horizontal — va en Modal ancho="lg".
import { Modal } from "@/components/ui/modal";
import { ROLES_DO, hoyLima, puedeOperarEquipo, maximoSemanalPracticante, leCorrespondeHorario } from "@cayla-dynamic/shared";
// horasDia() reimplementaba (salida − entrada) − refrigerio a mano, sin el
// ajuste "si la salida no es posterior a la entrada, el turno cruza
// medianoche" que horasEntre() ya resuelve (turnos/page.tsx también la
// reusa). Sin eso, un horario nocturno (p. ej. 21:00–05:00) daba 0 horas en
// vez de las ocho reales, escondiendo el aviso de exceso legal semanal de
// una practicante.
import { horasEntre as horasDia, esTurnoEspejoViejo, type HorarioTramo } from "@/lib/admin/jornada-esperada";
import { opcionesRefrigerio, etiquetaRefrigerio, yaLlegaAlmorzada, diasQueYaLlegaAlmorzada } from "@/lib/admin/refrigerio";

const META_SEMANA = 45; // horas objetivo por semana (7.5h × 6 días)
// El 2026-09-14 se pidió un mínimo de 250 caracteres para forzar un motivo
// de verdad; el 2026-09-15 Felipe lo invirtió: 250 es el TOPE y el mínimo es
// 3. El mínimo coincide ahora con el guardián de la base (fn_set_horario_semanal 0440/0444 y el
// camino retroactivo 0447, los tres en 3), así que pantalla y base dicen lo
// mismo. El tope vive solo en el cliente: la base no lo exige.
const MOTIVO_MIN = 3;
const MOTIVO_MAX = 250;

function ContadorMotivo({ texto }: { texto: string }) {
  const n = texto.trim().length;
  const falta = MOTIVO_MIN - n;
  return (
    <p className={`mt-1 text-xs ${falta > 0 ? "text-taupe" : "text-verde"}`}>
      {falta > 0 ? `Mínimo ${MOTIVO_MIN} caracteres · ${n}/${MOTIVO_MAX}` : `${n}/${MOTIVO_MAX} caracteres`}
    </p>
  );
}

// Más allá de esto, corregir el pasado deja de ser "hace unos días" y empieza
// a oler a fecha mal puesta: el candado de verdad es el motivo obligatorio y
// el preview, pero un rango de años recorrería un día a la vez sin necesidad.
const MAX_DIAS_RETROACTIVO = 120;

// Qué se está mirando exactamente en la vista previa: el horario y la fecha.
// Si cualquiera de los dos cambia, la previa deja de valer.
function huellaRetro(horario: Record<string, Dia>, desde: string): string {
  return JSON.stringify({ desde, horario });
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

/** El día de ayer en Lima, como `2026-09-13` — el valor más probable al abrir
 * la corrección retroactiva: casi siempre el cambio real fue "hace poco". */
function ayerLima(): string {
  const [y, m, d] = hoyLima().split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  dt.setUTCDate(dt.getUTCDate() - 1);
  return dt.toISOString().slice(0, 10);
}

/** Días de calendario entre dos fechas ISO de Lima (positivo si `hasta` es posterior). */
function diasEntreLima(desde: string, hasta: string): number {
  const [y1, m1, d1] = desde.split("-").map(Number);
  const [y2, m2, d2] = hasta.split("-").map(Number);
  return Math.round((Date.UTC(y2, m2 - 1, d2) - Date.UTC(y1, m1 - 1, d1)) / 86_400_000);
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
  // Con tipo_vinculo, decide si le corresponde horario (leCorrespondeHorario).
  // Viaja en el select directo, igual que en Correcciones.
  personal_direccion: boolean;
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
// Una fila de fn_horario_retroactivo_preview (0447): el antes y el después de
// una jornada ya calculada, para poder mirar qué cambiaría ANTES de tocarla.
interface FilaPreview {
  fecha: string;
  minutos_tarde_actual: number | null; minutos_tarde_nuevo: number | null;
  minutos_salida_temprana_actual: number | null; minutos_salida_temprana_nuevo: number | null;
  horas_extra_actual: number | null; horas_extra_nuevo: number | null;
  tiene_expediente_formal: boolean;
}
const DIAS = [{ v: 1, l: "L" }, { v: 2, l: "M" }, { v: 3, l: "X" }, { v: 4, l: "J" }, { v: 5, l: "V" }, { v: 6, l: "S" }, { v: 0, l: "D" }];
const NOMBRE_DIA: Record<number, string> = { 0: "domingo", 1: "lunes", 2: "martes", 3: "miércoles", 4: "jueves", 5: "viernes", 6: "sábado" };

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
      else next[d] = { e: entrada || "08:00", s: salida || "18:00", r: refri };
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

  // Quien entra pasada la hora de almuerzo ya suele llegar almorzada, y un
  // refrigerio puesto de más le resta una hora que nunca tomó. Es una SUGERENCIA
  // que se aplica con un clic, nunca un cambio solo: quitar el refrigerio
  // cambia cómo se miden las horas de esa persona. Cada caso se mira en su
  // propio modo — en "misma hora" es una sola pregunta; por día, una por día.
  const diasSinRefrigerioSugerido = modoPorDia
    ? diasQueYaLlegaAlmorzada(porDia)
    : yaLlegaAlmorzada({ e: entrada, s: salida, r: refri }) ? dias : [];
  function ponerSinRefrigerio() {
    if (modoPorDia) {
      setPorDia((prev) => {
        const next = { ...prev };
        for (const d of diasQueYaLlegaAlmorzada(prev)) next[d] = { ...next[d], r: 0 };
        return next;
      });
    } else {
      setRefri(0);
    }
  }

  return {
    modoPorDia, entrada, salida, refri, dias, porDia, totalSemana, diasSinRefrigerioSugerido,
    setEntrada, setSalida, setRefri,
    aplicarAnalisis, toggleDia, toggleDiaPorDia, setCampoPorDia, setRefriPorDia, cambiarModo, construirHorario,
    ponerSinRefrigerio,
  };
}
type FormularioHorario = ReturnType<typeof useFormularioHorario>;

// El aviso de «¿ya llega almorzada?». No aparece si el refrigerio ya está en 0
// ni si nadie entra después de las 13:00, así que quien trabaja de mañana nunca
// lo ve. El botón es el único camino: la pantalla propone, no decide.
function SugerenciaSinRefrigerio({ f }: { f: FormularioHorario }) {
  const dias = f.diasSinRefrigerioSugerido;
  if (dias.length === 0) return null;
  const texto = f.modoPorDia
    ? `${dias.map((d) => NOMBRE_DIA[d]).join(", ").replace(/^./, (c) => c.toUpperCase())} ${dias.length === 1 ? "entra" : "entran"} después de las 13:00.`
    : `Entra a las ${f.entrada}, ya pasada la hora de almuerzo.`;
  return (
    <div className="mt-3 flex flex-wrap items-center justify-between gap-2 rounded-control bg-hueso px-3 py-2">
      <p className="min-w-0 flex-1 text-xs text-taupe">
        {texto} Si llega almorzada, no le toca refrigerio: esas horas sí cuentan en su jornada.
      </p>
      <Boton variante="secundario" tamano="sm" onClick={f.ponerSinRefrigerio}>Poner sin refrigerio</Boton>
    </div>
  );
}

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
              {opcionesRefrigerio(f.refri).map((m) => <option key={m} value={m}>{etiquetaRefrigerio(m)}</option>)}
            </CampoSelect>
          </div>
          <p className="mt-2 text-xs text-taupe">Cada día: <span className="text-tinta">{fmtH(horasDia(f.entrada, f.salida, f.refri))}</span></p>
          <SugerenciaSinRefrigerio f={f} />
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
                      <select value={dd.r} onChange={(e) => f.setRefriPorDia(d.v, e.target.value)} title="refrigerio (min) — 0 = sin refrigerio" className="w-16 rounded-control border border-sand bg-hueso px-1 py-1 text-sm">
                        {opcionesRefrigerio(dd.r).map((m) => <option key={m} value={m}>{etiquetaRefrigerio(m, true)}</option>)}
                      </select>
                      <span className="w-14 text-right text-xs text-tinta">{fmtH(horasDia(dd.e, dd.s, dd.r))}</span>
                    </>
                  ) : <span className="text-sm text-taupe">descanso</span>}
                </div>
              );
            })}
          </div>
          <p className="mt-1.5 text-xs text-taupe">La columna angosta es el refrigerio en minutos (0 = sin refrigerio).</p>
          <SugerenciaSinRefrigerio f={f} />
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
  const pruebas = usePruebasPorPersona();
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

  // ── Corrección retroactiva (0447): aparte del cambio normal a propósito —
  // ver CLAUDE.md y la 0444, "un horario normal no puede pisar el pasado". El
  // formulario en sí es el MISMO que el del drawer normal, así que usa el
  // mismo hook en vez de una segunda copia de las mismas seis funciones: esa
  // duplicación es justo lo que useFormularioHorario vino a cerrar.
  const formRetro = useFormularioHorario();
  const [retro, setRetro] = useState<Persona | null>(null);
  const [retroDesde, setRetroDesde] = useState(ayerLima());
  const [retroMotivo, setRetroMotivo] = useState("");
  const [retroPreview, setRetroPreview] = useState<FilaPreview[] | null>(null);
  const [retroPreviewCargando, setRetroPreviewCargando] = useState(false);
  // De QUÉ horario y fecha es la vista previa que está en pantalla. Sin esto,
  // editar la grilla DESPUÉS de mirar el preview dejaba el botón de confirmar
  // activo con una previa que ya no corresponde — y confirmaba otra cosa
  // distinta de la que se enseñó. El preview es la única garantía que tiene
  // quien aprueba; tiene que ser del horario que se va a aplicar.
  const [retroPreviewDe, setRetroPreviewDe] = useState<string | null>(null);
  const [retroConfirmando, setRetroConfirmando] = useState(false);

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
      supabase.from("personas").select("id, nombres, apellidos, rol, sede_base_id, personal_direccion").eq("estado", "activo").eq("cuenta_de_servicio", false).order("nombres"),
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
        if (filtroEstado === "sin_horario" && (estado.con || !leCorrespondeHorario(p.tipo_vinculo, p.personal_direccion))) return false;
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

  // ── Corrección retroactiva (0447) ────────────────────────────────────────
  // Siembra el formulario con el tramo abierto, igual que abrirEdicion: se
  // corrige "hacia lo que de verdad regía", y lo que casi siempre se quiere
  // escribir es el horario que ya está puesto hoy, con la fecha movida atrás.
  function abrirRetro(p: Persona) {
    formRetro.aplicarAnalisis(analizar(horarios.get(p.id)));
    setRetro(p);
    setRetroDesde(ayerLima());
    setRetroMotivo("");
    setRetroPreview(null);
    setRetroPreviewDe(null);
  }
  function cerrarRetro() {
    setRetro(null);
    setRetroPreview(null);
    setRetroPreviewDe(null);
    setRetroMotivo("");
  }

  const retroFaltaEntrada = formRetro.modoPorDia
    ? Object.values(formRetro.porDia).some((v) => !v.e)
    : !formRetro.entrada;
  const retroFaltaSalida = formRetro.modoPorDia
    ? Object.values(formRetro.porDia).some((v) => !v.s)
    : !formRetro.salida;
  const rangoRetroDemasiadoLargo = diasEntreLima(retroDesde, hoy) > MAX_DIAS_RETROACTIVO;

  async function verQueCambiaria() {
    if (!retro) return;
    const horario = formRetro.construirHorario();
    if (Object.keys(horario).length === 0) { avisar("error", "Marca al menos un día de trabajo."); return; }
    if (retroFaltaEntrada) { avisar("error", "Falta la hora de entrada de algún día."); return; }
    if (retroFaltaSalida) { avisar("error", "Falta la hora de salida de algún día."); return; }
    if (rangoRetroDemasiadoLargo) { avisar("error", `Elige una fecha dentro de los últimos ${MAX_DIAS_RETROACTIVO} días — revisa que sea la correcta.`); return; }
    setRetroPreviewCargando(true);
    setRetroPreview(null);
    const supabase = createAdminSupabaseClient();
    const { data, error } = await supabase.rpc("fn_horario_retroactivo_preview", {
      p_persona_id: retro.id, p_horario: horario, p_vigente_desde: retroDesde,
    });
    setRetroPreviewCargando(false);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    setRetroPreview((data as FilaPreview[]) ?? []);
    setRetroPreviewDe(huellaRetro(horario, retroDesde));
  }

  async function confirmarRetro() {
    if (!retro) return;
    // El mismo listón que el camino normal (MOTIVO_MIN/MOTIVO_MAX). Sería
    // incoherente que el camino que REESCRIBE días ya juzgados pidiera menos
    // explicación que el que solo mira hacia adelante. El piso de la base
    // (0447) es 3, igual que el de fn_set_horario_semanal.
    if (retroMotivo.trim().length < MOTIVO_MIN) { avisar("error", `Escribe el motivo de la corrección (mínimo ${MOTIVO_MIN} caracteres).`); return; }
    const horario = formRetro.construirHorario();
    setRetroConfirmando(true);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_corregir_horario_retroactivo", {
      p_persona_id: retro.id, p_horario: horario, p_vigente_desde: retroDesde, p_motivo: retroMotivo.trim(),
    });
    setRetroConfirmando(false);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    cerrarRetro();
    await cargar();
    avisar("ok", "Días ya trabajados corregidos. Las jornadas del rango se volvieron a calcular y el cambio quedó auditado.");
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
  // RxH y dirección (Gerencia General) no llevan horario: no tenerlo es lo
  // correcto, así que ni cuentan como "sin horario" ni entran al aviso.
  const leCorresponde = (p: Persona) => leCorrespondeHorario(p.tipo_vinculo, p.personal_direccion);
  const sinHorarioLista = filtrados.filter((p) => !estadoDeHoy(p).con && leCorresponde(p));
  const porSede = [...new Set(filtrados.map((p) => sedes[p.sede_base_id] ?? "?"))].sort();

  // Resumen superior: sobre `editables` (todo lo que puedes ver), no sobre
  // `filtrados` — si no, los números cambiarían con el filtro que ellos
  // mismos activan, y dejarían de servir como ancla.
  const totalPersonas = editables.length;
  const conHorarioHoy = editables.filter((p) => estadoDeHoy(p).con).length;
  const sinHorarioHoy = editables.filter((p) => !estadoDeHoy(p).con && leCorresponde(p)).length;
  const noRequierenHorario = totalPersonas - conHorarioHoy - sinHorarioHoy;
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

  // Un solo día con expediente firmado basta para bloquear todo el rango: la
  // 0447 lo rechaza en la base, esto solo lo dice antes y con la fecha exacta.
  const bloqueadoPorExpediente = (retroPreview ?? []).find((f) => f.tiene_expediente_formal);
  const retroPreviewAlDia =
    retroPreview !== null && retroPreviewDe === huellaRetro(formRetro.construirHorario(), retroDesde);
  const filasConCambio = (retroPreview ?? []).filter(
    (f) => f.minutos_tarde_actual !== f.minutos_tarde_nuevo
      || f.minutos_salida_temprana_actual !== f.minutos_salida_temprana_nuevo
      || f.horas_extra_actual !== f.horas_extra_nuevo,
  );

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
                {noRequierenHorario > 0 && (
                  <span className="block text-xs text-taupe">{noRequierenHorario} no lo requiere{noRequierenHorario === 1 ? "" : "n"}</span>
                )}
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
                            <td className="px-4 py-2">{p.nombres} {p.apellidos}<EtiquetaPrueba fila={pruebas.get(p.id)} className="ml-2" /></td>
                            <td className="px-4 py-2">
                              {(!a || a.dias.length === 0) && !leCorresponde(p) ? (
                                <span className="text-taupe" title="RxH o personal de dirección: no le corresponde horario">no requiere horario</span>
                              ) : !a || a.dias.length === 0 ? (
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
                              <div className="flex items-center justify-end gap-3">
                                {/* «corregir pasado» hasta el 2026-09-15: no decía que
                                    vuelve a medir días ya pagados. Al lado de «Cambiar»
                                    (de hoy en adelante), el nombre tiene que marcar la
                                    diferencia sin que nadie la explique. */}
                                {h && (
                                  <Boton variante="enlace" tamano="sm" onClick={() => abrirRetro(p)}>
                                    Corregir días ya trabajados
                                  </Boton>
                                )}
                                <Boton variante="secundario" tamano="sm" onClick={(e) => abrirEdicion(p, e.currentTarget)}>
                                  {abierto ? "Cambiar" : "Asignar"}
                                </Boton>
                              </div>
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
                            <span className="block text-sm font-medium text-tinta">{p.nombres} {p.apellidos}<EtiquetaPrueba fila={pruebas.get(p.id)} className="ml-2" /></span>
                            <span className="block text-xs text-taupe">{sede}</span>
                          </span>
                        </label>
                        <Boton variante="secundario" tamano="sm" onClick={(e) => abrirEdicion(p, e.currentTarget)}>
                          {abierto ? "Cambiar" : "Asignar"}
                        </Boton>
                      </div>
                      <p className="text-sm">
                        {(!a || a.dias.length === 0) && !leCorresponde(p) ? (
                          <span className="text-taupe">no requiere horario</span>
                        ) : !a || a.dias.length === 0 ? (
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
                      <p className="text-xs text-taupe">
                        Vigente desde {h ? fechaCorta(h.vigente_desde) : "—"}
                        {h && (
                          <Boton variante="enlace" tamano="sm" className="ml-2" onClick={() => abrirRetro(p)}>
                            Corregir días ya trabajados
                          </Boton>
                        )}
                      </p>
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
            <Campo etiqueta="Vigente desde" type="date" min={hoy} value={desde} onChange={(e) => setDesde(e.target.value)} />
            <CampoSelect etiqueta="Copiar horario de →" value={copiarDeId} onChange={(e) => copiarDe(e.target.value)}>
              <option value="">(elegir a alguien)</option>
              {editables
                .filter((x) => x.id !== editando?.id && horarios.has(x.id))
                .map((x) => (
                  <option key={x.id} value={x.id}>{x.nombres} {x.apellidos}</option>
                ))}
            </CampoSelect>
          </div>

          <p className="mt-2 text-xs text-taupe">
            Un horario nuevo rige desde hoy en adelante. No se puede fechar
            hacia atrás: eso recalcularía tardanzas de días ya juzgados con el
            horario que de verdad regía entonces. Si el cambio ocurrió de
            verdad hace unos días y recién se registra, cierra esto y usa
            <span className="text-tinta"> Corregir días ya trabajados</span> — enseña antes
            qué jornadas cambiarían.
          </p>

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
              maxLength={MOTIVO_MAX}
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

          <Campo etiqueta="Vigente desde" type="date" min={hoy} value={masivoDesde} onChange={(e) => setMasivoDesde(e.target.value)} />

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
              maxLength={MOTIVO_MAX}
            />
            <ContadorMotivo texto={masivoMotivo} />
          </div>

          <div className="mt-5 flex justify-end gap-3">
            <Boton variante="secundario" onClick={() => setMasivoAbierto(false)} disabled={guardandoMasivo}>Cancelar</Boton>
            <Boton variante="primario" onClick={guardarMasivo} cargando={guardandoMasivo}>Guardar para {seleccionados.size}</Boton>
          </div>
        </Drawer>

        {/* ── Corregir un horario pasado (0447): aparte del cambio normal ──
            Va en Modal y no en Drawer a propósito: la tabla comparativa de
            abajo tiene cinco columnas por jornada, y esa es la única garantía
            que tiene quien aprueba de qué está a punto de reescribir. En una
            columna de 460 px se leería con scroll horizontal. */}
        <Modal
          abierto={retro !== null}
          onCerrar={cerrarRetro}
          bloqueado={retroPreviewCargando || retroConfirmando}
          ancho="lg"
          titulo={retro ? `Corregir días ya trabajados de ${retro.nombres} ${retro.apellidos}` : undefined}
        >
          <p className="mb-4 text-sm text-taupe">
            Para cuando el cambio de horario <strong className="text-tinta">de verdad ocurrió hace días</strong> y
            recién se registra hoy. Antes de guardar, revisa qué jornadas cambiarían — esto queda auditado con tu
            motivo.
          </p>

          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <Campo
              etiqueta="Vigente desde (una fecha pasada)"
              type="date"
              max={ayerLima()}
              value={retroDesde}
              onChange={(e) => { setRetroDesde(e.target.value); setRetroPreview(null); }}
            />
          </div>
          {rangoRetroDemasiadoLargo && (
            <p className="mt-1.5 text-xs text-rojo">
              Eso es más de {MAX_DIAS_RETROACTIVO} días atrás — revisa que la fecha sea la correcta.
            </p>
          )}

          <div className="mt-4">
            <GrillaHorario f={formRetro} />
          </div>

          <div className="mt-4 rounded-control bg-sand/30 px-3 py-2 text-sm">
            Total semana: <span className="font-medium text-tinta">{fmtH(formRetro.totalSemana)}</span>
            <span className="text-taupe"> · meta {META_SEMANA} h</span>
          </div>

          <div className="mt-4">
            <AreaTexto
              etiqueta="Motivo (obligatorio)"
              value={retroMotivo}
              onChange={(e) => { setRetroMotivo(e.target.value); }}
              placeholder="Por qué se corrige con vigencia pasada — por ejemplo: el horario cambió el lunes en la sede, recién se registra hoy."
              maxLength={MOTIVO_MAX}
            />
            <ContadorMotivo texto={retroMotivo} />
          </div>

          <div className="mt-4 flex justify-end">
            <Boton variante="secundario" onClick={verQueCambiaria} cargando={retroPreviewCargando} disabled={rangoRetroDemasiadoLargo}>
              Ver qué cambiaría
            </Boton>
          </div>

          {retroPreview && (
            <div className="mt-4 border-t border-sand pt-4">
              {retroPreview.length === 0 ? (
                <p className="text-sm text-taupe">No hay ninguna jornada en ese rango — no hay nada que recalcular.</p>
              ) : (
                <>
                  <p className="mb-2 text-sm">
                    <span className="font-medium text-tinta">{filasConCambio.length}</span> de {retroPreview.length}
                    {" "}día(s) del rango cambiarían.
                  </p>
                  {bloqueadoPorExpediente && (
                    <div className="mb-3 rounded-control bg-rojo/10 px-3 py-2 text-sm text-rojo">
                      El {fechaCorta(bloqueadoPorExpediente.fecha)} ya tiene un expediente disciplinario firmado o
                      entregado. No se puede confirmar esta corrección mientras ese expediente siga así — resuélvelo
                      o anúlalo en Disciplina primero.
                    </div>
                  )}
                  {filasConCambio.length > 0 && (
                    <div className="mb-3 overflow-x-auto">
                      <Tabla className="[font-variant-numeric:tabular-nums]">
                        <TablaEncabezado>
                          <Th>Fecha</Th>
                          <Th>Tardanza</Th>
                          <Th>Salida antic.</Th>
                          <Th>Tiempo extra</Th>
                          <Th>{null}</Th>
                        </TablaEncabezado>
                        <tbody>
                          {filasConCambio.map((f) => (
                            <Fila key={f.fecha}>
                              <td className="px-4 py-2">{fechaCorta(f.fecha)}</td>
                              <td className="px-4 py-2">{f.minutos_tarde_actual ?? 0} → <span className="text-tinta">{f.minutos_tarde_nuevo ?? 0} min</span></td>
                              <td className="px-4 py-2">{f.minutos_salida_temprana_actual ?? 0} → <span className="text-tinta">{f.minutos_salida_temprana_nuevo ?? 0} min</span></td>
                              <td className="px-4 py-2">{f.horas_extra_actual ?? 0} → <span className="text-tinta">{f.horas_extra_nuevo ?? 0} h</span></td>
                              <td className="px-4 py-2">
                                {f.tiene_expediente_formal && <Insignia variante="alerta">expediente formal</Insignia>}
                              </td>
                            </Fila>
                          ))}
                        </tbody>
                      </Tabla>
                    </div>
                  )}
                </>
              )}
            </div>
          )}

          {retroPreview !== null && !retroPreviewAlDia && (
            <p className="mt-3 text-xs text-ambar">
              Cambiaste el horario o la fecha después de mirar la vista previa, así que lo de arriba ya no es lo
              que se aplicaría. Vuelve a pulsar «Ver qué cambiaría».
            </p>
          )}

          <div className="mt-5 flex justify-end gap-3">
            <Boton variante="secundario" onClick={cerrarRetro} disabled={retroConfirmando}>Cancelar</Boton>
            <Boton
              variante="primario"
              onClick={confirmarRetro}
              cargando={retroConfirmando}
              disabled={!retroPreviewAlDia || !!bloqueadoPorExpediente || retroMotivo.trim().length < MOTIVO_MIN}
            >
              Confirmar corrección
            </Boton>
          </div>
        </Modal>
      </main>
    </div>
  );
}

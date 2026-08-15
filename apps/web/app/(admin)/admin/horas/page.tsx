"use client";

// ─────────────────────────────────────────────────────────────────────────────
// Desempeño del equipo — todas las personas en una sola tabla, con el detalle
// de cada una a un clic.
//
// QUÉ PROMETE: los mismos números que la pestaña «Desempeño» de una ficha
//   (/admin/personas/[id]), pero para todo el equipo a la vez y sin entrar a
//   nadie. El camino viejo eran cuatro pasos: Equipo → persona → ficha →
//   pestaña Desempeño, y solo se podía mirar a una persona por vez.
// QUÉ ASUME: que las jornadas del periodo caben en memoria (~30 personas × ~30
//   días). Por eso el panel lateral no vuelve a consultar la base: el detalle
//   diario ya vino en la misma carga que la tabla, que es lo que hace que
//   abrirlo sea instantáneo.
// CÓMO SE VUELVE ATRÁS: esta pantalla no escribe nada. Es lectura pura.
//
// La ruta sigue siendo /admin/horas aunque el título ya no diga «horas»: hay
// enlaces vivos (la ficha de cada persona, marcadores del navegador) y romper
// una URL para cambiar un nombre no lo vale.
//
// DECISIONES QUE NO SON OBVIAS
//
// · Una sola tabla, no una sección por sede. El orden por defecto es «lo que
//   necesita atención», y eso cruza sedes: quien tiene tres faltas en AQP tiene
//   que salir arriba aunque estés mirando también TRU. La sede pasa a ser una
//   columna y un filtro.
//
// · Las tardanzas JUSTIFICADAS no cuentan. Esta pantalla no lo hacía y la ficha
//   sí, así que la misma persona salía con dos cifras distintas según por dónde
//   la miraras. Ganó la ficha: acusar de tardanza a quien ya presentó su motivo
//   es exactamente el falso positivo que este sistema evita a propósito.
//
// · Las faltas vienen de fn_faltas, nunca contadas acá. Esa función ya sabe que
//   no es falta el día de vacaciones, el de descanso sustitutorio por feriado,
//   el de suspensión ni el que tiene justificación registrada. Contar «días sin
//   marcaje» en el navegador se vería igual de bien y estaría mal.
//
// · Los objetivos son MENSUALES y el rango puede cruzar meses. Se muestran los
//   del mes de la fecha «hasta», y la columna lo dice con el nombre del mes —
//   promediar dos meses de checklists distintos no significaría nada.
//
// · Las personas inactivas salen ocultas. Su historial sostiene los reportes de
//   periodos pasados, así que se pueden traer con la casilla; pero el uso
//   normal es mirar a quien está trabajando hoy.
// ─────────────────────────────────────────────────────────────────────────────

import { Suspense, useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { AdminNav } from "../nav";
import { Cargando } from "@/components/cargando";
import { traerTodo } from "@/lib/admin/traer-todo";
import { hoyLima } from "@cayla-dynamic/shared";
import { GraficoHoras, type DiaGrafico } from "@/components/grafico-horas";
import { type Area, AREAS_FALLBACK, parseAreas, areaCorto, areaNombre } from "@/lib/areas";
import { MESES, lecturaObjetivos, type ObjetivoItem } from "@/lib/objetivos";
import { X, Search } from "lucide-react";

const META_DIA = 7.5; // horas objetivo por día (45 h/semana) — igual que en la ficha

function primerDiaDelMes(iso = hoyLima()): string {
  return iso.slice(0, 8) + "01";
}
function rango(preset: "mes" | "mesPasado" | "anio"): { desde: string; hasta: string } {
  const hoy = hoyLima();
  const [y, m] = hoy.split("-").map(Number);
  if (preset === "mes") return { desde: primerDiaDelMes(hoy), hasta: hoy };
  if (preset === "anio") return { desde: `${y}-01-01`, hasta: hoy };
  const mp = m === 1 ? 12 : m - 1;
  const yp = m === 1 ? y - 1 : y;
  const ultimo = new Date(Date.UTC(yp, mp, 0)).getUTCDate();
  return { desde: `${yp}-${String(mp).padStart(2, "0")}-01`, hasta: `${yp}-${String(mp).padStart(2, "0")}-${ultimo}` };
}
function fmtHoras(h: number): string {
  const hh = Math.floor(h);
  const mm = Math.round((h - hh) * 60);
  return `${hh}h ${String(mm).padStart(2, "0")}m`;
}
function fechaCorta(iso: string): string {
  const [y, m, d] = iso.slice(0, 10).split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "short", weekday: "short", timeZone: "UTC" })
    .format(new Date(Date.UTC(y, m - 1, d)));
}
// Sin acentos ni mayúsculas, para que "chavez" encuentre a "Chávez".
// El rango va escrito con escapes \u a propósito: son marcas combinantes
// invisibles en el editor, y este repo ya perdió una hora por acentos que un
// copiado rompió sin que se notara.
function plano(s: string): string {
  return s.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
}

const MOTIVO_FALTA: Record<string, string> = {
  suspension: "suspensión",
  vacaciones: "vacaciones",
  descanso_sustitutorio: "descanso sustitutorio",
};

interface Fila {
  personaId: string;
  nombre: string;
  sede: string;
  area: string;
  activa: boolean;
  // Horas
  horasTotales: number;   // incluye los agregados históricos de 2025
  horasReales: number;    // sin agregados — es la que divide el promedio
  horasAgregadas: number;
  agregados: number;
  diasTrabajados: number;
  // Puntualidad
  tardanzas: number;
  tardanzasJustificadas: number;
  diasTardeMedidos: number;
  minutosTarde: number;
  salidasTempranas: number;
  horasExtra: number;
  // Asistencia
  faltas: { fecha: string; motivo: string | null }[];
  faltasJustificadas: number;
  // Marcajes que alguien tiene que arreglar
  incompletas: number;
  pendientesRevision: number;
  // Objetivos del mes de `hasta`
  objCumplidos: number;
  objTotal: number;
  objetivos: ObjetivoItem[];
  // Detalle diario, para el panel lateral (sin volver a consultar la base)
  dias: DiaGrafico[];
}

const porRevisar = (f: Fila) => f.incompletas + f.pendientesRevision;
const promedio = (f: Fila) => (f.diasTrabajados > 0 ? f.horasReales / f.diasTrabajados : 0);
const objPct = (f: Fila) => (f.objTotal > 0 ? f.objCumplidos / f.objTotal : -1); // -1 = sin checklist, va al final

type Columna =
  | "atencion" | "nombre" | "sede" | "area" | "dias" | "horas" | "promedio"
  | "tardanzas" | "minutos" | "faltas" | "revisar" | "objetivos";

// El orden por defecto NO es una puntuación inventada: es una comparación en
// cascada — primero faltas, luego tardanzas, luego marcajes por arreglar. Una
// fórmula que pesara las tres en un número diría cosas que nadie pidió.
function comparar(a: Fila, b: Fila, col: Columna, asc: boolean): number {
  const signo = asc ? 1 : -1;
  const nombre = () => a.nombre.localeCompare(b.nombre, "es");
  switch (col) {
    case "atencion":
      return (
        b.faltas.length - a.faltas.length ||
        b.tardanzas - a.tardanzas ||
        porRevisar(b) - porRevisar(a) ||
        nombre()
      );
    // El desempate por nombre va SIEMPRE ascendente, fuera del `signo`: dentro
    // de una misma sede, invertir el orden de la columna no tiene por qué dar
    // vuelta también los nombres.
    case "nombre": return signo * nombre();
    case "sede": return signo * a.sede.localeCompare(b.sede) || nombre();
    case "area": return signo * a.area.localeCompare(b.area) || nombre();
    case "dias": return signo * (a.diasTrabajados - b.diasTrabajados) || nombre();
    case "horas": return signo * (a.horasTotales - b.horasTotales) || nombre();
    case "promedio": return signo * (promedio(a) - promedio(b)) || nombre();
    case "tardanzas": return signo * (a.tardanzas - b.tardanzas) || nombre();
    case "minutos": return signo * (a.minutosTarde - b.minutosTarde) || nombre();
    case "faltas": return signo * (a.faltas.length - b.faltas.length) || nombre();
    case "revisar": return signo * (porRevisar(a) - porRevisar(b)) || nombre();
    case "objetivos": return signo * (objPct(a) - objPct(b)) || nombre();
  }
}

type Orden = { col: Columna; asc: boolean };

// Tile y Th viven FUERA del componente a propósito. Definidos adentro, cada
// tecla escrita en el buscador los convierte en un tipo de componente nuevo y
// React desmonta y vuelve a montar toda la cabecera y los recuadros.
function Tile({ label, valor, tono = "neutral" }: { label: string; valor: string; tono?: "neutral" | "alerta" }) {
  return (
    <div className="rounded-xl border border-sand bg-papel px-4 py-3">
      <div className="text-xs uppercase tracking-wide text-taupe">{label}</div>
      <div className={`mt-1 text-2xl font-semibold [font-variant-numeric:tabular-nums] ${tono === "alerta" && valor !== "0" ? "text-rojo" : ""}`}>{valor}</div>
    </div>
  );
}

function Th({ col, orden, setOrden, num = false, children }: {
  col: Columna;
  orden: Orden;
  setOrden: (o: Orden) => void;
  num?: boolean;
  children: React.ReactNode;
}) {
  const activa = orden.col === col;
  // Las columnas de texto empiezan de la A a la Z; las de números, de mayor a
  // menor — quien ordena por «faltas» quiere ver las faltas, no los ceros.
  const primerSentido = col === "nombre" || col === "sede" || col === "area";
  return (
    <th className={`px-3 py-2 font-normal ${num ? "text-right" : "text-left"}`}>
      <button
        onClick={() => setOrden(activa ? { col, asc: !orden.asc } : { col, asc: primerSentido })}
        className={`inline-flex items-center gap-1 rounded px-1 py-0.5 transition-colors hover:text-tinta ${activa ? "font-medium text-tinta" : ""}`}
        title="Ordenar por esta columna"
      >
        {children}
        <span aria-hidden className={activa ? "" : "opacity-0"}>{orden.asc ? "▲" : "▼"}</span>
      </button>
    </th>
  );
}

function DesempenoContenido() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const personaEnlace = searchParams.get("persona"); // la ficha enlaza acá con ?persona=id

  const [desde, setDesde] = useState(primerDiaDelMes());
  const [hasta, setHasta] = useState(hoyLima());
  const [filas, setFilas] = useState<Fila[]>([]);
  const [areas, setAreas] = useState<Area[]>(AREAS_FALLBACK);
  const [periodo, setPeriodo] = useState<{ fecha_ini: string; fecha_fin: string } | null>(null);
  const [sinActividad, setSinActividad] = useState(0);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Filtros
  const [fSede, setFSede] = useState("");
  const [fArea, setFArea] = useState("");
  const [fBusca, setFBusca] = useState("");
  const [verInactivas, setVerInactivas] = useState(false);

  // Orden y panel
  const [orden, setOrden] = useState<Orden>({ col: "atencion", asc: true });
  const [abierta, setAbierta] = useState<string | null>(personaEnlace);

  const mesObjetivos = `${MESES[Number(hasta.slice(5, 7)) - 1]} ${hasta.slice(0, 4)}`;

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    setCargando(true);

    const [
      { data: personas, error: errPersonas },
      { data: jornadas, error: errJornadas },
      { data: salidasData },
      { data: faltasData },
      { data: objetivosData },
      { data: levData },
      { data: areasData, error: areasError },
    ] = await Promise.all([
      supabase.from("personas")
        .select("id, nombres, apellidos, estado, funcion, sedes:sede_base_id(codigo)")
        .order("nombres"),
      // Por lotes: esta consulta no tenía tope ni orden, así que PostgREST
      // devolvía 1000 filas arbitrarias y el total de horas de gente al azar
      // salía corto. El botón «Todo el año» era el camino directo al problema.
      // El order por fecha+persona no es cosmético: sin un orden estable, dos
      // lotes pueden repetir una fila y perder otra.
      traerTodo<{ persona_id: string; fecha: string; horas_trabajadas: number | null; minutos_tarde: number | null; horas_extra_detectadas: number | null; estado: string }>(
        (ini, fin) =>
          supabase
            .from("jornadas")
            .select("persona_id, fecha, horas_trabajadas, minutos_tarde, horas_extra_detectadas, estado")
            .gte("fecha", desde)
            .lte("fecha", hasta)
            .order("fecha")
            .order("persona_id")
            .range(ini, fin),
      ),
      supabase.rpc("fn_jornadas_extra", { p_desde: desde, p_hasta: hasta }),
      supabase.rpc("fn_faltas", { p_desde: desde, p_hasta: hasta }),
      // Los objetivos son de un mes, no de un rango: se piden los del mes en que
      // cae `hasta` y la columna lo dice con nombre y año.
      supabase.rpc("fn_objetivos_checklist", { p_anio: Number(hasta.slice(0, 4)), p_mes: Number(hasta.slice(5, 7)) }),
      supabase.from("tardanzas_justificadas").select("persona_id, fecha").gte("fecha", desde).lte("fecha", hasta),
      supabase.rpc("fn_areas"),
    ]);

    if (errPersonas || errJornadas) {
      setError((errPersonas ?? errJornadas)!.message);
      setCargando(false);
      return; // no pisa `filas` con datos parciales/vacíos
    }
    setError(null);
    setAreas(parseAreas(areasData, areasError));

    const acc = new Map<string, Fila>();
    for (const p of personas ?? []) {
      acc.set(p.id, {
        personaId: p.id,
        nombre: `${p.nombres} ${p.apellidos}`,
        sede: (p as unknown as { sedes?: { codigo: string } }).sedes?.codigo ?? "?",
        area: (p as unknown as { funcion: string }).funcion ?? "",
        activa: (p as unknown as { estado: string }).estado === "activo",
        horasTotales: 0, horasReales: 0, horasAgregadas: 0, agregados: 0, diasTrabajados: 0,
        tardanzas: 0, tardanzasJustificadas: 0, diasTardeMedidos: 0, minutosTarde: 0,
        salidasTempranas: 0, horasExtra: 0,
        faltas: [], faltasJustificadas: 0,
        incompletas: 0, pendientesRevision: 0,
        objCumplidos: 0, objTotal: 0, objetivos: [],
        dias: [],
      });
    }

    // Tardanzas levantadas: se descuentan del conteo, igual que en la ficha.
    const levantadas = new Set(
      ((levData as { persona_id: string; fecha: string }[] | null) ?? []).map((t) => `${t.persona_id}|${t.fecha}`),
    );

    for (const j of jornadas ?? []) {
      const r = acc.get(j.persona_id);
      if (!r) continue;
      const horas = j.horas_trabajadas === null ? null : Number(j.horas_trabajadas);
      // Un día no puede tener más de 24 h: si las tiene, es un AGREGADO del
      // histórico 2025 (un mes entero guardado en una sola fecha). Suma al
      // total —la planilla lo usó para CTS y gratificación— pero no cuenta
      // como día, así que queda fuera del promedio y del gráfico.
      const esAgregado = (horas ?? 0) > 24;

      if (horas === null) {
        r.incompletas++;
      } else {
        r.horasTotales += horas;
        if (esAgregado) { r.horasAgregadas += horas; r.agregados++; }
        else {
          r.horasReales += horas;
          if (horas > 0) r.diasTrabajados++;
        }
      }
      if (j.minutos_tarde !== null) r.diasTardeMedidos++;
      if ((j.minutos_tarde ?? 0) > 0) {
        if (levantadas.has(`${j.persona_id}|${j.fecha}`)) r.tardanzasJustificadas++;
        else { r.tardanzas++; r.minutosTarde += j.minutos_tarde!; }
      }
      if ((j.horas_extra_detectadas ?? 0) > 0) r.horasExtra += Number(j.horas_extra_detectadas);
      if (j.estado === "auto_cerrada_pendiente") r.pendientesRevision++;

      if (!esAgregado) {
        r.dias.push({
          fecha: j.fecha,
          horas: horas ?? 0,
          problema: horas === null || j.estado === "auto_cerrada_pendiente" ||
            ((j.minutos_tarde ?? 0) > 0 && !levantadas.has(`${j.persona_id}|${j.fecha}`)),
        });
      }
    }

    // Salidas tempranas vía RPC (bypass del schema cache); solo devuelve filas con minutos > 0.
    for (const s of ((salidasData as { persona_id: string }[] | null) ?? [])) {
      const r = acc.get(s.persona_id);
      if (r) r.salidasTempranas++;
    }

    // Faltas: fn_faltas ya excluye vacaciones, descanso sustitutorio, suspensión
    // y justificaciones registradas. Las que llegan marcadas como justificadas
    // se cuentan aparte, para poder decir «2 faltas · 1 justificada» sin que la
    // justificada engorde la columna.
    for (const f of ((faltasData as { persona_id: string; fecha: string; justificada: boolean; motivo: string | null }[] | null) ?? [])) {
      const r = acc.get(f.persona_id);
      if (!r) continue;
      if (f.justificada) r.faltasJustificadas++;
      else r.faltas.push({ fecha: f.fecha, motivo: f.motivo });
    }

    for (const o of ((objetivosData as unknown as ObjetivoItem[] | null) ?? [])) {
      const r = acc.get(o.persona_id);
      if (!r) continue;
      r.objetivos.push(o);
      r.objTotal++;
      if (o.cumplido) r.objCumplidos++;
    }

    // Quien no tiene ni una jornada ni una falta en el rango no aparece: son
    // vacaciones completas, ingresos posteriores o gente sin horario cargado.
    // No desaparece en silencio — se dice cuánta gente quedó fuera al pie.
    const todas = [...acc.values()];
    // `agregados` va en la lista a propósito: un registro histórico de 2025 no
    // entra en `dias` (no es un día), pero sí son horas trabajadas. Sin esta
    // condición, con el rango «Todo el año» desaparecía de la tabla quien en el
    // periodo solo tuviera ese registro.
    const conAlgo = todas.filter((r) =>
      r.dias.length > 0 || r.agregados > 0 || r.incompletas > 0 || r.faltas.length > 0 || r.faltasJustificadas > 0);
    setSinActividad(todas.filter((r) => r.activa).length - conAlgo.filter((r) => r.activa).length);
    setFilas(conAlgo);
    setCargando(false);
  }, [router, desde, hasta]);

  useEffect(() => { void cargar(); }, [cargar]);

  // El periodo de planilla NO se calcula acá. Va del 29 al 28, pero eso es un
  // hecho de `periodos_planilla`, no una regla que se pueda escribir en código:
  // si un periodo se cierra distinto, el atajo tiene que seguirlo.
  useEffect(() => {
    void createAdminSupabaseClient()
      .from("periodos_planilla")
      .select("fecha_ini, fecha_fin")
      .lte("fecha_ini", hoyLima())
      .order("fecha_ini", { ascending: false })
      .limit(1)
      .then(({ data, error: e }) => { if (!e && data && data.length > 0) setPeriodo(data[0]); });
  }, []);

  const sedes = useMemo(() => [...new Set(filas.map((f) => f.sede))].sort(), [filas]);
  const areasPresentes = useMemo(() => [...new Set(filas.map((f) => f.area))].filter(Boolean).sort(), [filas]);

  const vista = useMemo(() => {
    const q = plano(fBusca.trim());
    return filas
      .filter((f) => (verInactivas || f.activa))
      .filter((f) => (!fSede || f.sede === fSede))
      .filter((f) => (!fArea || f.area === fArea))
      .filter((f) => (!q || plano(f.nombre).includes(q)))
      .sort((a, b) => comparar(a, b, orden.col, orden.asc));
  }, [filas, verInactivas, fSede, fArea, fBusca, orden]);

  const totales = useMemo(() => ({
    horas: vista.reduce((s, f) => s + f.horasTotales, 0),
    personas: vista.length,
    tardanzas: vista.reduce((s, f) => s + f.tardanzas, 0),
    faltas: vista.reduce((s, f) => s + f.faltas.length, 0),
    salidasTempranas: vista.reduce((s, f) => s + f.salidasTempranas, 0),
    horasExtra: vista.reduce((s, f) => s + f.horasExtra, 0),
    porRevisar: vista.reduce((s, f) => s + porRevisar(f), 0),
  }), [vista]);

  const detalle = useMemo(() => vista.find((f) => f.personaId === abierta) ?? filas.find((f) => f.personaId === abierta) ?? null, [vista, filas, abierta]);

  // Esc cierra el panel — es la tecla que la mano busca sola.
  useEffect(() => {
    if (!abierta) return;
    const alPulsar = (e: KeyboardEvent) => { if (e.key === "Escape") setAbierta(null); };
    window.addEventListener("keydown", alPulsar);
    return () => window.removeEventListener("keydown", alPulsar);
  }, [abierta]);

  const aplicarPreset = (p: "mes" | "mesPasado" | "anio") => { const r = rango(p); setDesde(r.desde); setHasta(r.hasta); };
  const hayFiltro = Boolean(fSede || fArea || fBusca.trim() || verInactivas);

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <div className="mb-4 flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 className="font-serif text-2xl">Desempeño del equipo</h1>
            <p className="mt-0.5 text-sm text-taupe">Toca una fila para ver sus días, su gráfico y sus objetivos, sin salir de acá.</p>
          </div>
          <div className="flex flex-wrap items-end gap-3">
            <div className="flex gap-1 rounded-lg border p-1 text-sm">
              <button onClick={() => aplicarPreset("mes")} className="rounded-md px-2.5 py-1 hover:bg-sand/60">Este mes</button>
              <button onClick={() => aplicarPreset("mesPasado")} className="rounded-md px-2.5 py-1 hover:bg-sand/60">Mes pasado</button>
              {periodo && (
                <button
                  onClick={() => { setDesde(periodo.fecha_ini); setHasta(periodo.fecha_fin); }}
                  className="rounded-md px-2.5 py-1 hover:bg-sand/60"
                  title={`Periodo de planilla en curso: ${periodo.fecha_ini} a ${periodo.fecha_fin}`}
                >
                  Periodo de planilla
                </button>
              )}
              <button onClick={() => aplicarPreset("anio")} className="rounded-md px-2.5 py-1 hover:bg-sand/60">Todo el año</button>
            </div>
            <label className="flex flex-col gap-1 text-sm">Desde
              <input type="date" value={desde} onChange={(e) => setDesde(e.target.value)} className="rounded-lg border px-3 py-2" /></label>
            <label className="flex flex-col gap-1 text-sm">Hasta
              <input type="date" value={hasta} onChange={(e) => setHasta(e.target.value)} className="rounded-lg border px-3 py-2" /></label>
          </div>
        </div>

        {/* Filtros: no vuelven a consultar la base, recortan lo ya cargado. */}
        <div className="mb-5 flex flex-wrap items-center gap-3 rounded-xl border border-sand bg-papel px-4 py-3 text-sm">
          <div className="relative">
            <Search size={15} strokeWidth={1.8} aria-hidden className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-taupe" />
            <input
              value={fBusca}
              onChange={(e) => setFBusca(e.target.value)}
              placeholder="Buscar por nombre…"
              aria-label="Buscar por nombre"
              className="w-56 rounded-lg border py-1.5 pl-8 pr-3"
            />
          </div>
          <label className="flex items-center gap-2">Sede
            <select value={fSede} onChange={(e) => setFSede(e.target.value)} className="rounded-lg border px-2.5 py-1.5">
              <option value="">Todas</option>
              {sedes.map((s) => <option key={s} value={s}>{s}</option>)}
            </select>
          </label>
          <label className="flex items-center gap-2">Área
            <select value={fArea} onChange={(e) => setFArea(e.target.value)} className="rounded-lg border px-2.5 py-1.5">
              <option value="">Todas</option>
              {areasPresentes.map((a) => <option key={a} value={a}>{areaNombre(areas, a)}</option>)}
            </select>
          </label>
          <label className="flex items-center gap-2" title="Su historial sostiene los reportes de periodos pasados; por eso se pueden traer.">
            <input type="checkbox" checked={verInactivas} onChange={(e) => setVerInactivas(e.target.checked)} className="size-4" />
            Incluir inactivas
          </label>
          <div className="ml-auto flex items-center gap-4">
            {/* Sin esto, ordenar por una columna era un camino de ida: no hay
                encabezado «atención» al que volver a hacerle clic. */}
            {orden.col !== "atencion" && (
              <button onClick={() => setOrden({ col: "atencion", asc: true })} className="text-taupe underline hover:text-tinta">
                Volver al orden por atención
              </button>
            )}
            {hayFiltro && (
              <button
                onClick={() => { setFSede(""); setFArea(""); setFBusca(""); setVerInactivas(false); }}
                className="text-taupe underline hover:text-tinta"
              >
                Quitar filtros
              </button>
            )}
          </div>
        </div>

        {/* La ficha de una persona enlaza acá con ?persona=id para abrir su
            panel. Si en este rango no tiene ni jornadas ni faltas, no hay fila
            que abrir — y callarlo haría que el enlace pareciera roto. */}
        {personaEnlace && abierta === personaEnlace && !cargando && !error && !detalle && (
          <div className="mb-4 rounded-lg border border-rojo/30 bg-rojo/5 px-4 py-2.5 text-sm">
            La persona que venías a ver no registra jornadas ni faltas en este periodo — prueba a ampliar el rango de fechas.
          </div>
        )}

        <div className="mb-6 grid grid-cols-2 gap-3 sm:grid-cols-4 xl:grid-cols-7">
          <Tile label="Horas totales" valor={`${totales.horas.toFixed(0)} h`} />
          <Tile label="Tiempo adicional" valor={`${totales.horasExtra.toFixed(1)} h`} />
          <Tile label="Tardanzas" valor={String(totales.tardanzas)} tono="alerta" />
          <Tile label="Faltas" valor={String(totales.faltas)} tono="alerta" />
          <Tile label="Salidas anticipadas" valor={String(totales.salidasTempranas)} tono="alerta" />
          <Tile label="Jornadas por revisar" valor={String(totales.porRevisar)} tono="alerta" />
          <Tile label="Personas" valor={String(totales.personas)} />
        </div>

        {error && (
          <div className="mb-4 rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
            No se pudo cargar el desempeño del equipo: {error}{" "}
            <button onClick={() => void cargar()} className="font-medium underline">Reintentar</button>
          </div>
        )}

        {cargando && <Cargando />}
        {!cargando && !error && filas.length === 0 && <p className="text-sm text-taupe">Sin marcajes ni faltas en este periodo.</p>}
        {!cargando && !error && filas.length > 0 && vista.length === 0 && (
          <p className="text-sm text-taupe">Ninguna persona coincide con estos filtros.</p>
        )}

        {vista.length > 0 && (
          <div className="overflow-x-auto rounded-2xl border border-sand bg-papel">
            <table className="w-full text-sm [font-variant-numeric:tabular-nums]">
              <thead className="bg-sand/70 text-taupe">
                <tr>
                  <Th col="nombre" orden={orden} setOrden={setOrden}>Nombre</Th>
                  <Th col="sede" orden={orden} setOrden={setOrden}>Sede</Th>
                  <Th col="area" orden={orden} setOrden={setOrden}>Área</Th>
                  <Th col="dias" orden={orden} setOrden={setOrden} num>Días</Th>
                  <Th col="horas" orden={orden} setOrden={setOrden} num>Horas</Th>
                  <Th col="promedio" orden={orden} setOrden={setOrden} num>Prom./día</Th>
                  <Th col="tardanzas" orden={orden} setOrden={setOrden} num>Tardanzas</Th>
                  <Th col="minutos" orden={orden} setOrden={setOrden} num>Min. tarde</Th>
                  <Th col="faltas" orden={orden} setOrden={setOrden} num>Faltas</Th>
                  <Th col="revisar" orden={orden} setOrden={setOrden} num>Por revisar</Th>
                  <Th col="objetivos" orden={orden} setOrden={setOrden} num>Objetivos</Th>
                </tr>
              </thead>
              <tbody>
                {vista.map((f) => (
                  <tr
                    key={f.personaId}
                    onClick={() => setAbierta(f.personaId)}
                    className={`cursor-pointer border-t transition-colors hover:bg-crema ${abierta === f.personaId ? "bg-crema" : ""}`}
                  >
                    <td className="px-3 py-2">
                      {f.nombre}
                      {!f.activa && <span className="ml-2 rounded-full bg-taupe/15 px-2 py-0.5 text-[10px] text-taupe">inactiva</span>}
                    </td>
                    <td className="px-3 py-2 text-taupe">{f.sede}</td>
                    <td className="px-3 py-2 text-taupe">{f.area ? areaCorto(areas, f.area) : "—"}</td>
                    <td className="px-3 py-2 text-right">{f.diasTrabajados}</td>
                    <td className="px-3 py-2 text-right font-medium">{f.horasTotales.toFixed(1)}</td>
                    <td className="px-3 py-2 text-right">{f.diasTrabajados > 0 ? fmtHoras(promedio(f)) : <span className="text-taupe/50">—</span>}</td>
                    <td className="px-3 py-2 text-right">
                      {f.diasTardeMedidos === 0
                        ? <span className="text-taupe/50">sin medir</span>
                        : f.tardanzas > 0
                          ? <span className="text-ambar">{f.tardanzas} <span className="text-taupe/50">/ {f.diasTardeMedidos}</span></span>
                          : <span className="text-taupe/50">0 / {f.diasTardeMedidos}</span>}
                    </td>
                    <td className="px-3 py-2 text-right">{f.minutosTarde ? `${f.minutosTarde} min` : <span className="text-taupe/50">—</span>}</td>
                    <td className="px-3 py-2 text-right">
                      {f.faltas.length > 0
                        ? <span className="font-medium text-rojo">{f.faltas.length}</span>
                        : <span className="text-taupe/50">—</span>}
                      {f.faltasJustificadas > 0 && (
                        <span className="ml-1 text-xs text-taupe/70" title="Faltas con motivo registrado — no cuentan">+{f.faltasJustificadas} just.</span>
                      )}
                    </td>
                    <td className="px-3 py-2 text-right">
                      {porRevisar(f) > 0 ? <span className="text-ambar">{porRevisar(f)}</span> : <span className="text-taupe/50">—</span>}
                    </td>
                    <td className="px-3 py-2 text-right">
                      {f.objTotal === 0
                        ? <span className="text-taupe/50">sin checklist</span>
                        : <span className={objPct(f) < 0.3 ? "text-rojo" : ""}>{f.objCumplidos}/{f.objTotal}</span>}
                    </td>
                  </tr>
                ))}
                <tr className="border-t bg-sand/50 font-medium">
                  <td className="px-3 py-2">Total ({vista.length})</td>
                  <td className="px-3 py-2" />
                  <td className="px-3 py-2" />
                  <td className="px-3 py-2 text-right">{vista.reduce((s, f) => s + f.diasTrabajados, 0)}</td>
                  <td className="px-3 py-2 text-right">{totales.horas.toFixed(1)}</td>
                  <td className="px-3 py-2" />
                  <td className="px-3 py-2 text-right">{totales.tardanzas || "—"}</td>
                  <td className="px-3 py-2 text-right">{vista.reduce((s, f) => s + f.minutosTarde, 0) || "—"}</td>
                  <td className="px-3 py-2 text-right">{totales.faltas || "—"}</td>
                  <td className="px-3 py-2 text-right">{totales.porRevisar || "—"}</td>
                  <td className="px-3 py-2" />
                </tr>
              </tbody>
            </table>
          </div>
        )}

        <p className="mt-5 max-w-3xl text-xs text-taupe">
          Ordenado por lo que necesita atención: primero faltas, luego tardanzas, luego marcajes por
          revisar. Toca cualquier encabezado para ordenar por esa columna. Las horas descuentan almuerzos
          y pausas. La tardanza, la salida anticipada y el tiempo adicional se calculan contra el horario
          de cada persona — mientras no haya horario cargado, esas columnas quedan en blanco. Las
          tardanzas con motivo registrado (Incidencias → Justificar) <strong>no cuentan</strong>. Las
          faltas las calcula la base: no es falta el día de vacaciones, el de descanso sustitutorio por
          feriado, el de suspensión ni el que tiene justificación. «Por revisar» son jornadas sin salida
          marcada o cerradas automáticamente por olvido. Los objetivos son los de{" "}
          <strong>{mesObjetivos.toLowerCase()}</strong> — son mensuales, así que no siguen al rango de
          fechas.
          {sinActividad > 0 && (
            <> Hay <strong>{sinActividad} persona{sinActividad === 1 ? "" : "s"} activa{sinActividad === 1 ? "" : "s"}</strong> sin
            jornadas ni faltas en este rango (vacaciones completas, ingreso posterior o sin horario
            cargado); no salen en la tabla.</>
          )}
        </p>
      </main>

      {detalle && (
        <>
          <div
            onClick={() => setAbierta(null)}
            className="fixed inset-0 z-40 bg-tinta/20"
            aria-hidden
          />
          <aside
            role="dialog"
            aria-label={`Desempeño de ${detalle.nombre}`}
            className="fixed inset-y-0 right-0 z-50 w-full max-w-[560px] overflow-y-auto border-l border-sand bg-crema shadow-xl"
          >
            <div className="sticky top-0 flex items-start justify-between gap-4 border-b border-sand bg-crema px-5 py-4">
              <div>
                <h2 className="font-serif text-xl">{detalle.nombre}</h2>
                <p className="text-sm text-taupe">
                  {detalle.area ? areaNombre(areas, detalle.area) : "Sin área"} · Sede {detalle.sede}
                  {!detalle.activa && " · inactiva"}
                </p>
                <Link href={`/admin/personas/${detalle.personaId}`} className="text-sm text-rojo hover:underline">
                  Abrir su ficha →
                </Link>
              </div>
              <button onClick={() => setAbierta(null)} aria-label="Cerrar" className="rounded-lg border border-sand p-1.5 text-taupe hover:text-tinta">
                <X size={18} strokeWidth={1.8} />
              </button>
            </div>

            <div className="space-y-5 p-5">
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
                {[
                  { label: "Total del periodo", valor: fmtHoras(detalle.horasTotales) },
                  { label: "Días trabajados", valor: String(detalle.diasTrabajados) },
                  { label: "Promedio por día", valor: detalle.diasTrabajados ? fmtHoras(promedio(detalle)) : "—" },
                  { label: "Días con tardanza", valor: `${detalle.tardanzas} de ${detalle.diasTardeMedidos} medidos` },
                  { label: "Salidas anticipadas", valor: String(detalle.salidasTempranas) },
                  { label: "Tiempo adicional", valor: detalle.horasExtra > 0 ? fmtHoras(detalle.horasExtra) : "—" },
                ].map((c) => (
                  <div key={c.label} className="rounded-2xl border border-sand bg-papel px-4 py-3">
                    <div className="text-xs uppercase tracking-wide text-taupe">{c.label}</div>
                    <div className="mt-1 font-serif text-xl">{c.valor}</div>
                  </div>
                ))}
              </div>

              {detalle.agregados > 0 && (
                <p className="text-xs text-taupe">
                  Incluye <strong>{detalle.agregados} registro{detalle.agregados === 1 ? "" : "s"} histórico{detalle.agregados === 1 ? "" : "s"} de 2025</strong>{" "}
                  ({fmtHoras(detalle.horasAgregadas)}): el total de un mes completo guardado en una sola
                  fecha, porque en 2025 todavía no había marcaje diario. Suma al total del periodo pero no
                  cuenta como día, así que queda fuera del promedio y del gráfico.
                </p>
              )}

              {detalle.tardanzasJustificadas > 0 && (
                <p className="text-xs text-taupe">
                  Además tiene <strong>{detalle.tardanzasJustificadas} tardanza{detalle.tardanzasJustificadas === 1 ? "" : "s"} con motivo registrado</strong>,
                  que no entran en el conteo.
                </p>
              )}

              {(detalle.faltas.length > 0 || detalle.faltasJustificadas > 0) && (
                <div className="rounded-2xl border border-sand bg-papel p-4">
                  <h3 className="mb-2 font-serif text-lg">
                    Faltas <span className="text-sm font-normal text-taupe">— le tocaba y no marcó</span>
                  </h3>
                  {detalle.faltas.length === 0 ? (
                    <p className="text-sm text-taupe">Ninguna sin justificar.</p>
                  ) : (
                    <ul className="space-y-1 text-sm">
                      {detalle.faltas.map((f) => (
                        <li key={f.fecha} className="flex items-center gap-2">
                          <span className="text-rojo">●</span>
                          <span className="capitalize">{fechaCorta(f.fecha)}</span>
                          {f.motivo && <span className="text-taupe">— {MOTIVO_FALTA[f.motivo] ?? f.motivo}</span>}
                        </li>
                      ))}
                    </ul>
                  )}
                  {detalle.faltasJustificadas > 0 && (
                    <p className="mt-2 text-xs text-taupe">
                      Y {detalle.faltasJustificadas} día{detalle.faltasJustificadas === 1 ? "" : "s"} con motivo registrado
                      (permiso, descanso médico, vacaciones, suspensión o descanso sustitutorio), que no cuenta{detalle.faltasJustificadas === 1 ? "" : "n"}.
                    </p>
                  )}
                  <Link href="/admin/incidencias" className="mt-2 inline-block text-sm text-rojo hover:underline">
                    Ir a Incidencias para justificar →
                  </Link>
                </div>
              )}

              {detalle.objTotal > 0 && (() => {
                const nivel = lecturaObjetivos(detalle.objCumplidos, detalle.objTotal);
                const pct = Math.round((detalle.objCumplidos / detalle.objTotal) * 100);
                return (
                  <div className="rounded-2xl border border-sand bg-papel p-4">
                    <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
                      <h3 className="font-serif text-lg">Objetivos de {mesObjetivos.toLowerCase()}</h3>
                      <span className="flex items-center gap-2 text-sm">
                        <span className="text-taupe">{detalle.objCumplidos}/{detalle.objTotal} cumplidos</span>
                        <span className="rounded-full bg-sand px-3 py-0.5 text-taupe">{nivel.etiqueta}</span>
                      </span>
                    </div>
                    <div className="mb-3 h-2 overflow-hidden rounded-full bg-sand">
                      <div className={`h-full rounded-full ${pct >= 60 ? "bg-verde" : pct >= 30 ? "bg-ambar" : "bg-rojo"}`} style={{ width: `${pct}%` }} />
                    </div>
                    <ul className="space-y-1 text-sm">
                      {detalle.objetivos.map((o) => (
                        <li key={o.id} className="flex items-start gap-2">
                          <span className={o.cumplido ? "text-verde" : "text-taupe/50"}>{o.cumplido ? "✓" : "○"}</span>
                          <span className={o.cumplido ? "text-taupe line-through" : ""}>{o.descripcion}</span>
                        </li>
                      ))}
                    </ul>
                  </div>
                );
              })()}

              <div className="rounded-2xl border border-sand bg-papel p-4">
                <h3 className="mb-3 font-serif text-lg">Horas por día</h3>
                <GraficoHoras dias={detalle.dias} meta={META_DIA} />
              </div>

              {porRevisar(detalle) > 0 && (
                <div className="rounded-2xl border border-ambar/40 bg-ambar/5 p-4 text-sm">
                  <p>
                    <strong>{porRevisar(detalle)} jornada{porRevisar(detalle) === 1 ? "" : "s"} por revisar</strong>
                    {detalle.incompletas > 0 && ` · ${detalle.incompletas} sin salida marcada`}
                    {detalle.pendientesRevision > 0 && ` · ${detalle.pendientesRevision} cerrada${detalle.pendientesRevision === 1 ? "" : "s"} automáticamente`}
                  </p>
                  <Link href="/admin/correcciones" className="mt-1 inline-block text-rojo hover:underline">
                    Ir a Correcciones →
                  </Link>
                </div>
              )}
            </div>
          </aside>
        </>
      )}
    </div>
  );
}

export default function DesempenoEquipoPage() {
  return (
    <Suspense fallback={<main className="p-6"><p className="text-sm text-taupe">Cargando…</p></main>}>
      <DesempenoContenido />
    </Suspense>
  );
}

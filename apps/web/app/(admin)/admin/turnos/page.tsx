"use client";

import { Fragment, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { AREA_DEFAULT, AREAS_FALLBACK, parseAreas, areaCorto, esOperativaEn, type Area } from "@/lib/areas";
import { Cargando, SinDatos } from "@/components/cargando";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { useFiltroGuardado } from "@/lib/admin/use-filtro-guardado";
import { useToast } from "@/components/toast";
import { AyudaPantalla } from "@/components/ui/ayuda-pantalla";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { sobretituloDeHoy } from "@/lib/admin/sobretitulo";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Boton } from "@/components/ui/boton";
import { BotonIcono } from "@/components/ui/boton-icono";
import { Pestanas } from "@/components/ui/pestanas";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { ParaAtender } from "@/components/ui/para-atender";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { Filtro } from "@/components/ui/filtro";
import { Insignia } from "@/components/ui/insignia";
import { Modal } from "@/components/ui/modal";
import { cuentaEnCobertura, fechaLima, horaLima, hoyLima, puedeOperarEquipo, puedeVerTodasLasSedes, rangoDelDiaLima, type MarcajeDelDia } from "@cayla-dynamic/shared";
import { diaDeLaSedeDe, esperadoDelDia, esTurnoEspejoViejo, horarioVigente, type HorarioTramo, type TurnoDia } from "@/lib/admin/jornada-esperada";
import { cicloVigente, type DiaTrabajado } from "@/lib/admin/ciclo-sobretiempo";
import { consecuenciaDeUsarBase as consecuenciaDeUsarBaseLib } from "@/lib/admin/revision-turnos";
import { avisarCambioDeTurnos, useTurnosAlDia } from "@/lib/admin/turnos-al-dia";
import { estiloDeHora, etiquetaCobertura, etiquetaSedeSinTurnos, type TonoCobertura } from "@/lib/admin/cobertura-turnos";
import { resumenDeLideres, resumenDelTramo, type TurnoDecimal } from "@/lib/admin/cobertura-tramos";
import { celdaConNombres, horasDeLaSemana, resumenDelDia, type TurnoConNombre } from "@/lib/admin/semana-con-nombres";
import { PISO, aHHMM, almacenConLoReal, argumentosDeGuardado, esPiso, problemaDeTramos, puestoDesdeFilas, sugerirTramo, textoPuesto, tramosEnAlmacen, type PuestoDelDia, type TramoDecimal } from "@/lib/admin/almacen";
import { avisoDeCopiar, conviveDarDescanso, cuerpoDelAviso, lineaDeSemana, TEXTO_CONFIRMAR_TRABAJO_EN_FERIADO, tituloDelAviso, type PersonaEnFeriado } from "@/lib/admin/prueba-en-feriado";
import type { FilaPrueba } from "@/lib/admin/pruebas";
import type { CambioUbicacion, Ubicacion } from "@/lib/terminal/ubicacion";
import { CampoMeta, TarjetaGrupo, TarjetaTramo, type PersonaDelDia } from "./cobertura-por-tramos";
import { RepeticionDelDia } from "./repeticion-del-dia";
import type { PersonaRepeticion } from "@/lib/admin/repeticion";

// ── Fechas (todo en ISO yyyy-mm-dd, semana de lunes a domingo) ──────────────
function parseISO(iso: string): Date {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}
function toISO(dt: Date): string {
  return dt.toISOString().slice(0, 10);
}
function addDays(iso: string, n: number): string {
  const d = parseISO(iso);
  d.setUTCDate(d.getUTCDate() + n);
  return toISO(d);
}
function diaSemana(iso: string): number {
  return parseISO(iso).getUTCDay(); // 0=domingo … 6=sábado
}
function lunesDeLaSemana(iso: string): string {
  const dow = diaSemana(iso);
  return addDays(iso, dow === 0 ? -6 : 1 - dow);
}
const DIAS_ABR = ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"];
// Para la frase "cambia su horario de los sábados…" (plural, en minúscula).
const DIAS_PLURAL = ["domingos", "lunes", "martes", "miércoles", "jueves", "viernes", "sábados"];
const MESES = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];
function etiquetaDia(iso: string): { abr: string; num: string } {
  const d = parseISO(iso);
  return { abr: DIAS_ABR[d.getUTCDay()], num: `${d.getUTCDate()} ${MESES[d.getUTCMonth()]}` };
}

interface Persona { id: string; nombres: string; apellidos: string; rol: string; funcion: string; esEncargadaPiso: boolean; tipoVinculo: string | null; }
// El tramo de horario y "quién le tocaba trabajar ese día" viven en
// jornada-esperada.ts — es la misma cascada que usa el backend
// (fn_recalcular_jornada) y que ya adoptaron incidencias/horas/correcciones.
// Escribir una copia acá sería exactamente la quinta que CLAUDE.md prohíbe.
type Horario = HorarioTramo;
type Turno = TurnoDia;
interface Sede { id: string; codigo: string; nombre: string; tipo: string }

type Celda =
  | { tipo: "turno"; entrada: string; salida: string | null; refrigerio?: number }
  | { tipo: "default"; entrada: string; salida: string | null; refrigerio?: number }
  | { tipo: "descanso" }
  | { tipo: "libre" };

const hhmm = (t?: string | null) => (t ? t.slice(0, 5) : "");

// ── Línea de tiempo / mapa de calor de cobertura (7h–21h) ───────────────────
const HORA_INICIO = 7;
const HORA_FIN = 21;
const MARCAS_HORA = [7, 9, 11, 13, 15, 17, 19, 21];
// Vista Semana: franjas de 30 min ancladas a :15/:45 (7:45, 8:15, 8:45…), igual
// que las horas de entrada reales del equipo — fijo, no automático (decisión
// de Felipe: más simple y predecible que recalcularlo cada vez).
const HORA_INICIO_SEMANA = 7.75; // 07:45
const N_FRANJAS_SEMANA = 28; // 07:45 → 21:45 (28 franjas de 30 min; la operación máxima real)
function horaADecimal(hm: string): number {
  const [h, m] = hm.split(":").map(Number);
  return (h ?? 0) + (m ?? 0) / 60;
}
// Hora decimal → "HH:MM" en formato 24h (07.75 → "07:45"). Decisión de Felipe:
// siempre 24h en Turnos, nunca a.m./p.m., para no dar lugar a confusión.
function decimalAHHMM(dec: number): string {
  const h = Math.floor(dec + 1e-9);
  const m = Math.round((dec - h) * 60);
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}
// % horizontal dentro del rango visible, recortado a [0, 100] para turnos que
// empiezan antes de las 7 o terminan después de las 21.
function pctEnRango(horaDec: number): number {
  return Math.min(100, Math.max(0, ((horaDec - HORA_INICIO) / (HORA_FIN - HORA_INICIO)) * 100));
}
// `estiloDeHora` (de qué color se pinta una hora contra su meta) vive en
// lib/admin/cobertura-turnos.ts, con su explicación y sus pruebas.
// La meta cambia a media tarde: hasta 14:15 es la meta de la MAÑANA, después la
// de la TARDE (fijo por ahora, ambas sedes — decisión de Felipe).
const CORTE_TARDE = 14.25; // 14:15
const metaDeHora = (horaFranjaIni: number, metaMan: number, metaTar: number) =>
  horaFranjaIni >= CORTE_TARDE ? metaTar : metaMan;
// Resumen de OPERATIVAS: promedio de qué tan lleno corriste vs la meta del tramo
// (topado a 100% por franja para que la tarde de sobra NO tape una mañana vacía),
// más el motor de sugerencia: redistribuir (hay gente que mover) vs falta
// personal (déficit sin sobra en ningún lado → contratar).
//
// `hayGente` = hay al menos una OPERATIVA programada ese día. Se llamaba
// `hayTurnos`, y por eso «sin turnos» salía en días que tenían turnos de sobra:
// quien está en un área que no es operativa tiene su turno y su barra, pero acá
// no cuenta. Ver etiquetaCobertura, que es lo que traduce esto a una frase.
function resumenOperativas(cov: number[], metaMan: number, metaTar: number, hi0: number, tam: number) {
  const idx = cov.map((v, i) => (v > 0 ? i : -1)).filter((i) => i >= 0);
  if (idx.length === 0) return { hayGente: false, sinMeta: false, pct: 0, supHoras: 0, sug: null as string | null, redistribuir: null as "adelantar" | "retrasar" | null };
  let suma = 0, n = 0, defMan = 0, defTar = 0, supMan = 0, supTar = 0, supFr = 0;
  for (let i = idx[0]; i <= idx[idx.length - 1]; i++) {
    const tarde = hi0 + i * tam >= CORTE_TARDE;
    const m = tarde ? metaTar : metaMan;
    if (m <= 0) continue;
    suma += Math.min(cov[i] / m, 1); n++;
    if (cov[i] < m) { if (tarde) defTar++; else defMan++; }
    else if (cov[i] > m) { if (tarde) supTar++; else supMan++; supFr++; }
  }
  if (n === 0) return { hayGente: true, sinMeta: true, pct: 0, supHoras: 0, sug: null, redistribuir: null };
  const hayDef = defMan + defTar > 0, haySup = supMan + supTar > 0;
  let sug: string | null = null;
  let redistribuir: "adelantar" | "retrasar" | null = null;
  if (hayDef && haySup) {
    if (defMan > 0 && supTar > 0) { sug = "Sobra gente en la tarde y falta en la mañana."; redistribuir = "adelantar"; }
    else if (defTar > 0 && supMan > 0) { sug = "Sobra gente en la mañana y falta en la tarde."; redistribuir = "retrasar"; }
    else sug = "Reparte mejor: hay horas con exceso y otras con falta.";
  } else if (hayDef && !haySup) {
    sug = "Te falta personal ese día — ni moviendo turnos alcanza.";
  }
  return { hayGente: true, sinMeta: false, pct: Math.round((suma / n) * 100), supHoras: Math.round(supFr * tam * 10) / 10, sug, redistribuir };
}

// Resumen de ENCARGADAS: promedio de llenado vs la meta (igual que operativas,
// con meta plana todo el día). Decisión de Felipe 2026-07-17: 1 encargada de
// una meta de 2 se lee "cubierto 50%", no piso estricto en 0%.
function resumenEncargadas(cov: number[], meta: number): { pct: number; hayGente: boolean; sinMeta: boolean } {
  const idx = cov.map((v, i) => (v > 0 ? i : -1)).filter((i) => i >= 0);
  if (idx.length === 0) return { pct: 0, hayGente: false, sinMeta: false };
  if (meta <= 0) return { pct: 0, hayGente: true, sinMeta: true };
  const ventana = cov.slice(idx[0], idx[idx.length - 1] + 1);
  const suma = ventana.reduce((s, v) => s + Math.min(v / meta, 1), 0);
  return { pct: Math.round((suma / ventana.length) * 100), hayGente: true, sinMeta: false };
}
// Verde ≥90 · ámbar 60-89 · rojo <60 (umbral elegido por Felipe).
const colorDePct = (pct: number) => (pct >= 90 ? "var(--color-verde)" : pct >= 60 ? "var(--color-ambar)" : "var(--color-rojo)");
// El color de la frase de cobertura de un día (ver etiquetaCobertura): rojo si es
// una alerta, gris si es solo un dato, y el color del porcentaje si es un número.
const colorDeTono = (tono: TonoCobertura, pct: number) =>
  tono === "alerta" ? "var(--color-rojo)" : tono === "neutro" ? "var(--color-taupe)" : colorDePct(pct);

// ── Diagnóstico: turnos que NO coinciden con el horario base ─────────────────
// Un turno del día PISA el horario base (para tardanza y cobertura). Si un turno
// quedó desactualizado respecto al horario (ej. era copia de un horario viejo y
// el horario cambió), sigue mandando en silencio. Este panel los saca a la luz
// —desde que empezó el periodo de planilla abierto— para que la encargada los
// revise: los que sean excepción real, se dejan; los que sean "espejos viejos",
// se ajustan en la Vista Día.
// Solo lectura: no toca nada.
// tE/tS = las horas REALES del turno (null = ese turno es descanso). Se guardan
// para poder promover el turno a horario base ("Hacer permanente") sin re-consultar.
//
// `yaCorrio` = ese día ya se midió: es pasado, o es hoy y ya marcó. Ahí quitar el
// turno no es cosmético: la jornada se recalcula contra el horario base, y si el
// turno era lo que de verdad le habían dicho, aparece una tardanza (o una falta,
// si el turno era descanso) que la persona nunca tuvo. `marco` = la hora a la que
// marcó su entrada ese día, para decidir con el dato delante.
interface Divergencia { fecha: string; personaId: string; persona: string; turnoTxt: string; baseTxt: string; espejo: boolean; tE: string | null; tS: string | null; baseE: string | null; yaCorrio: boolean; marco: string | null }
const rangoTxt = (e: string | null, s: string | null) => (e ? `${e}${s ? `–${s}` : ""}` : "descanso");
// El horario semanal completo de un tramo, como el jsonb que espera
// fn_set_horario_semanal ({"1":{e,s,r}, …}). Sirve para cambiar UN día sin
// perder el resto de la semana. Un tramo legacy (sin jsonb) se reconstruye
// desde dias_laborables + hora_entrada/salida.
function horarioSemanalDesdeTramo(tr: Horario | null): Record<string, { e: string; s: string; r?: number }> {
  const out: Record<string, { e: string; s: string; r?: number }> = {};
  if (tr?.horario_por_dia) {
    for (const [k, v] of Object.entries(tr.horario_por_dia)) {
      if (v?.e) out[k] = { e: hhmm(v.e), s: hhmm(v.s ?? v.e), ...(v.r != null ? { r: v.r } : {}) };
    }
  } else if (tr) {
    for (const d of tr.dias_laborables ?? []) out[String(d)] = { e: hhmm(tr.hora_entrada), s: hhmm(tr.hora_salida) };
  }
  return out;
}
// A partir de acá se avisa. 48 es el tope legal del ciclo (no de la semana
// calendario); avisar recién al llegar sería llegar tarde para reorganizar el
// turno — el sentido de esto es avisar ANTES, no contar el exceso ya pagado.
const UMBRAL_AVISO_SOBRETIEMPO = 40;
// Descanso mínimo entre el fin de una jornada y el inicio de la siguiente. No
// bloquea guardar — la encargada en piso sigue decidiendo, igual que con el
// aviso de 48h — solo avisa dentro del modal, antes de que el turno quede
// guardado, en vez de enterarse después en Incidencias.
const DESCANSO_MINIMO_HORAS = 12;

// Quién está cerca (o ya pasó) el tope de 48h de SU ciclo de 7 días vigente
// hoy — el mismo ciclo que calcula fn_planilla_calcular_nucleo, portado a
// TypeScript en ciclo-sobretiempo.ts para poder avisar antes de que la
// planilla lo cuente. Solo lee `jornadas`; no decide ni adelanta cuánto se
// va a pagar, eso lo sigue diciendo la planilla.
function AlertaSobretiempo({ sedeSel, abierto, onConteo }: {
  sedeSel: string;
  /** El detalle se abre desde «Para decidir», no desde un encabezado propio. */
  abierto: boolean;
  onConteo: (n: number | null, grave: boolean) => void;
}) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const [filas, setFilas] = useState<{ personaId: string; nombre: string; ciclo: NonNullable<ReturnType<typeof cicloVigente>> }[] | null>(null);
  const [error, setError] = useState(false);

  useEffect(() => {
    onConteo(filas === null ? null : filas.length, Boolean(filas?.some((f) => f.ciclo.horas >= 48)));
  }, [filas, onConteo]);

  useEffect(() => {
    if (!sedeSel) return;
    let vivo = true;
    void (async () => {
      setFilas(null);
      setError(false);
      const hoy = hoyLima();
      // 28 días de margen: de sobra para cubrir cualquier racha real sin
      // descanso (la ley exige uno semanal) y encontrar el inicio verdadero
      // del ciclo vigente, no solo su cola.
      const desde = addDays(hoy, -28);
      // `tipo_vinculo = 'practicante'`, no simplemente `not en_planilla`:
      // así un RxH no entra por accidente. Mismo criterio que ya usa el
      // dashboard (7afe8e5): un practicante sí marca y sí acumula horas de
      // su ciclo, y este aviso solo lee `jornadas` — no dispara disciplina.
      const { data: personas, error: eP } = await supabase.from("personas")
        .select("id, nombres, apellidos")
        .eq("sede_base_id", sedeSel).eq("estado", "activo").eq("cuenta_de_servicio", false)
        .or("en_planilla.eq.true,tipo_vinculo.eq.practicante")
        .eq("sueldo_fijo", false);
      if (eP) { if (vivo) setError(true); return; }
      const ids = (personas ?? []).map((p) => p.id);
      if (ids.length === 0) { if (vivo) setFilas([]); return; }
      const { data: jornadas, error: eJ } = await supabase.from("jornadas")
        .select("persona_id, fecha, horas_trabajadas")
        .in("persona_id", ids).gte("fecha", desde).lte("fecha", hoy);
      if (eJ) { if (vivo) setError(true); return; }
      const nombre = new Map((personas ?? []).map((p) => [p.id, `${p.nombres} ${p.apellidos}`]));
      const diasPorPersona = new Map<string, DiaTrabajado[]>();
      for (const j of (jornadas as { persona_id: string; fecha: string; horas_trabajadas: number | null }[]) ?? []) {
        const arr = diasPorPersona.get(j.persona_id) ?? [];
        arr.push({ fecha: j.fecha, horas: j.horas_trabajadas ?? 0 });
        diasPorPersona.set(j.persona_id, arr);
      }
      const res = ids
        .map((id) => ({ personaId: id, nombre: nombre.get(id) ?? "?", ciclo: cicloVigente(diasPorPersona.get(id) ?? [], hoy) }))
        .filter((f): f is { personaId: string; nombre: string; ciclo: NonNullable<ReturnType<typeof cicloVigente>> } =>
          f.ciclo !== null && f.ciclo.horas >= UMBRAL_AVISO_SOBRETIEMPO)
        .sort((a, b) => b.ciclo.horas - a.ciclo.horas);
      if (vivo) setFilas(res);
    })();
    return () => { vivo = false; };
  }, [sedeSel, supabase]);

  if (error) {
    return <BannerAviso enLinea role="alert" variante="alerta" className="mb-4">No se pudo calcular el sobretiempo del ciclo vigente.</BannerAviso>;
  }
  // Cargando, o nadie cerca del tope: la franja «Para decidir» lo dice; aquí no hay nada que dibujar.
  if (filas === null || filas.length === 0 || !abierto) return null;
  const algunoEnExceso = filas.some((f) => f.ciclo.horas >= 48);
  return (
    <TarjetaInfo className="mb-4 overflow-hidden p-0 sm:p-0">
      <ul className="divide-y divide-sand">
        {filas.map((f) => (
          <li key={f.personaId} className="flex items-center justify-between gap-3 px-4 py-2 text-sm">
            <span>{f.nombre}</span>
            <span className={`tabular-nums font-medium ${f.ciclo.horas >= 48 ? "text-rojo" : "text-ambar"}`}>
              {f.ciclo.horas.toFixed(1)}/48 h · día {f.ciclo.dia} de 7
            </span>
          </li>
        ))}
      </ul>
      <p className={`border-t border-sand px-4 py-2 text-xs ${algunoEnExceso ? "text-rojo-profundo" : "text-taupe"}`}>
        Ciclo de 7 días desde que empezó su racha sin descanso — no es la semana calendario. Reorganiza el turno de quien esté más arriba antes de que siga sumando.
      </p>
    </TarjetaInfo>
  );
}

// Qué pasa si un día que ya corrió vuelve al horario base: ver revision-turnos.ts.
function consecuenciaDeUsarBase(d: Divergencia): string {
  const { abr, num } = etiquetaDia(d.fecha);
  return consecuenciaDeUsarBaseLib({
    etiqueta: `${abr.toLowerCase()} ${num}`, turnoTxt: d.turnoTxt, baseTxt: d.baseTxt,
    turnoEntrada: d.tE, baseEntrada: d.baseE, marco: d.marco,
  });
}

function RevisionTurnos({ sedeSel, onIrADia, abierto, onConteo, alDia, onCambio }: {
  sedeSel: string;
  onIrADia: (iso: string) => void;
  /** El detalle se abre desde «Para decidir», no desde un encabezado propio. */
  abierto: boolean;
  onConteo: (n: number | null, espejos: number) => void;
  /** Sube cada vez que la grilla (o otra pestaña, u otra persona) cambió turnos u horarios: este panel vuelve a mirar. */
  alDia: number;
  /** Lo que este panel cambia (un horario base, un turno quitado) mueve la cobertura: se le avisa a la grilla. */
  onCambio: () => void;
}) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const [divs, setDivs] = useState<Divergencia[] | null>(null);
  // Turnos de días en que la persona aún no tenía horario base: no hay contra
  // qué compararlos, así que no son divergencias, solo se cuentan.
  const [sinBase, setSinBase] = useState(0);
  const [error, setError] = useState(false);
  const [procesando, setProcesando] = useState<string | null>(null); // clave de fila, o "bulk"
  const [confirmarBulk, setConfirmarBulk] = useState(false);
  // Fila (por su clave) cuyo "Usar el horario base" espera confirmación: solo
  // pasa con días que ya corrieron (ver `yaCorrio`).
  const [confirmarBase, setConfirmarBase] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  // Tramos de horario de cada persona, para poder promover un turno a horario base.
  const tramosRef = useRef<Map<string, Horario[]>>(new Map());

  // `enSilencio`: ponerse al día sin borrar la lista mientras tanto, y sin
  // cambiarla por el aviso de error si una lectura de fondo falla (se queda lo
  // último que se vio; la próxima lectura lo vuelve a intentar).
  const cargar = useCallback(async (enSilencio = false) => {
    if (!sedeSel) return;
    if (!enSilencio) { setDivs(null); setError(false); }
    // El caso de Diana (set-2026): un espejo viejo con fecha PASADA nunca lo
    // veía este panel porque el piso era "hoy". El piso correcto es el inicio
    // del periodo de planilla abierto — es informativo, no un candado, así
    // que no hace falta mirar el grupo de pago (0327/0380), solo el periodo
    // entero. Si no hay ninguno abierto (caso raro/borde), se cae a "hoy"
    // igual que antes, para no dejar la pantalla sin piso.
    const hoy = hoyLima();
    const { data: periodo } = await supabase.from("periodos_planilla")
      .select("fecha_ini, fecha_fin").eq("estado", "abierto")
      .order("fecha_ini", { ascending: true }).limit(1).maybeSingle();
    const desde = periodo?.fecha_ini ?? hoy;
    // Mismo criterio del dashboard (7afe8e5): un practicante también tiene
    // turno y horario asignados, y esta pantalla solo compara uno contra otro.
    const { data: personas, error: eP } = await supabase.from("personas")
      .select("id, nombres, apellidos").eq("sede_base_id", sedeSel).eq("estado", "activo").eq("cuenta_de_servicio", false)
      .or("en_planilla.eq.true,tipo_vinculo.eq.practicante")
      .eq("sueldo_fijo", false);
    if (eP) { if (!enSilencio) setError(true); return; }
    const ids = (personas ?? []).map((p) => p.id);
    const nombre = new Map((personas ?? []).map((p: any) => [p.id, `${p.nombres} ${p.apellidos}`]));
    if (ids.length === 0) { setDivs([]); return; }
    const [{ data: turnos, error: eT }, { data: horarios, error: eH }, { data: jornadas, error: eJ }] = await Promise.all([
      supabase.from("turnos").select("persona_id, fecha, hora_entrada, hora_salida, es_descanso").in("persona_id", ids).gte("fecha", desde).order("fecha"),
      supabase.from("horarios_asignados").select("persona_id, hora_entrada, hora_salida, dias_laborables, horario_por_dia, almuerzo_min_minutos, vigente_desde, vigente_hasta").in("persona_id", ids),
      supabase.from("jornadas").select("persona_id, fecha, entrada_ts").in("persona_id", ids).gte("fecha", desde).lte("fecha", hoy),
    ]);
    if (eT || eH || eJ) { if (!enSilencio) setError(true); return; }
    const entradaDe = new Map<string, string>();
    for (const j of (jornadas as { persona_id: string; fecha: string; entrada_ts: string | null }[]) ?? []) {
      if (j.entrada_ts) entradaDe.set(`${j.persona_id}|${j.fecha}`, horaLima(j.entrada_ts));
    }
    const hMap = new Map<string, Horario[]>();
    for (const h of (horarios as HorarioTramo[]) ?? []) {
      const arr = hMap.get(h.persona_id) ?? [];
      arr.push(h);
      hMap.set(h.persona_id, arr);
    }
    tramosRef.current = hMap;
    const res: Divergencia[] = [];
    let nSinBase = 0;
    for (const t of (turnos as any[]) ?? []) {
      const tramos = hMap.get(t.persona_id);
      const tramo = horarioVigente(tramos ?? [], t.fecha);
      const base = tramo ? esperadoDelDia(t.fecha, null, tramo) : null;
      const tE = t.es_descanso ? null : hhmm(t.hora_entrada);
      const tS = t.es_descanso ? null : hhmm(t.hora_salida);
      // ¿Coincide con algún horario ANTERIOR (ya reemplazado) de esa persona? Entonces
      // casi seguro es un "espejo viejo": era copia del horario de su momento y quedó
      // atrás cuando el horario cambió. Si no coincide con ninguno, alguien lo escribió
      // a propósito (excepción real) — por eso NO se limpian en automático.
      const espejo = esTurnoEspejoViejo(
        t.fecha,
        { hora_entrada: t.hora_entrada, hora_salida: t.hora_salida, es_descanso: t.es_descanso },
        tramos ?? []
      );
      const marco = entradaDe.get(`${t.persona_id}|${t.fecha}`) ?? null;
      const fila = {
        fecha: t.fecha, personaId: t.persona_id, persona: nombre.get(t.persona_id) ?? "?", espejo, tE, tS,
        baseE: base?.entrada ?? null, yaCorrio: t.fecha < hoy || (t.fecha === hoy && marco !== null), marco,
      };
      // Sin horario base ese día (caso TRU, set-2026: los horarios rigen desde
      // el 12 de julio y el periodo abierto arranca el 28 de junio) el turno es
      // la ÚNICA referencia de a qué hora le tocaba entrar. No diverge de nada:
      // antes se listaba con "Usar el horario base" al lado —que dejaba el día
      // sin referencia alguna— y entraba al botón de quitar espejos en bloque.
      if (!base) {
        nSinBase++;
      } else if (tE === null) {
        if (base.entrada) res.push({ ...fila, turnoTxt: "descanso", baseTxt: rangoTxt(base.entrada, base.salida) });
      } else if (!base.entrada) {
        res.push({ ...fila, turnoTxt: rangoTxt(tE, tS), baseTxt: "descanso" });
      } else if (tE !== base.entrada || (tS && base.salida && tS !== base.salida)) {
        res.push({ ...fila, turnoTxt: rangoTxt(tE, tS), baseTxt: rangoTxt(base.entrada, base.salida) });
      }
    }
    setError(false);
    setSinBase(nSinBase);
    setDivs(res);
  }, [sedeSel, supabase]);

  useEffect(() => { void cargar(); }, [cargar]);
  // Algo cambió fuera de este panel: se vuelve a mirar en silencio. Al cambiar
  // de sede no hace falta (el efecto de arriba ya carga), por eso se compara
  // contra el último `alDia` atendido y no se dispara solo porque cambió `cargar`.
  // Por un temporizador y no directo: varios avisos seguidos (guardar en la
  // grilla y el minuto de fondo a la vez) se juntan en una sola lectura.
  const alDiaVisto = useRef(alDia);
  useEffect(() => {
    if (alDia === alDiaVisto.current) return;
    alDiaVisto.current = alDia;
    const t = window.setTimeout(() => void cargar(true), 0);
    return () => window.clearTimeout(t);
  }, [alDia, cargar]);
  useEffect(() => {
    onConteo(divs === null ? null : divs.length, divs?.filter((d) => d.espejo).length ?? 0);
  }, [divs, onConteo]);

  // Quitar el turno puntual ⇒ ese día vuelve a regir el horario base. La RPC
  // recalcula la jornada de esa fecha (y el candado bloquea periodos pagados).
  async function usarHorarioBase(d: Divergencia, clave: string) {
    setProcesando(clave); setAviso(null); setConfirmarBase(null);
    const { error: e } = await supabase.rpc("fn_quitar_turno", { p_persona_id: d.personaId, p_fecha: d.fecha });
    setProcesando(null);
    if (e) { setAviso(`No se pudo quitar el turno de ${d.persona}: ${e.message}`); return; }
    onCambio();
    await cargar();
  }

  // "Hacer permanente": gana el TURNO. Su hora pasa a ser el horario base de ese
  // día de la semana desde esa fecha, y el turno puntual se retira (la regla ya
  // lo cubre). Es lo correcto cuando alguien cambió el horario de verdad y quedó
  // guardado como turno — borrarlo perdería ese cambio.
  async function hacerPermanente(d: Divergencia, clave: string) {
    setProcesando(clave); setAviso(null);
    const tramos = tramosRef.current.get(d.personaId);
    const tramo = horarioVigente(tramos ?? [], d.fecha);
    const semanal = horarioSemanalDesdeTramo(tramo);
    const dow = String(diaSemana(d.fecha));
    if (d.tE) {
      const previo = tramo?.horario_por_dia?.[dow];
      const baseS = tramo ? esperadoDelDia(d.fecha, null, tramo).salida : null;
      semanal[dow] = { e: d.tE, s: d.tS ?? baseS ?? d.tE, ...(previo?.r != null ? { r: previo.r } : {}) };
    } else {
      delete semanal[dow]; // el turno era descanso ⇒ ese día sale de su horario
    }
    if (Object.keys(semanal).length === 0) {
      setProcesando(null);
      setAviso(`No puedo dejar a ${d.persona} sin ningún día de trabajo. Ajusta su horario en la pantalla Horarios.`);
      return;
    }
    // La 0444 no deja que un horario NORMAL rija desde una fecha pasada:
    // hacerlo recalcularía jornadas ya juzgadas con el horario que de verdad
    // regía entonces, que es justo la tardanza falsa que esa migración vino a
    // cerrar. Y este panel enseña sobre todo filas pasadas —su piso es el
    // inicio del periodo abierto, no hoy—, así que sin este tope el botón
    // quedaba muerto exactamente en el caso para el que existe.
    //
    // "Hacer permanente" mira hacia adelante por definición: lo que se pide es
    // "que esto sea la norma", no "reescribe lo que ya pasó". El día de origen
    // no queda desatendido — lo cubrió su propio turno puntual, que fue lo que
    // de verdad rigió ese día.
    const desdeHoy = hoyLima();
    const desde = d.fecha > desdeHoy ? d.fecha : desdeHoy;
    const esPasado = desde !== d.fecha;
    const { error: e1 } = await supabase.rpc("fn_set_horario_semanal", {
      p_persona_id: d.personaId, p_vigente_desde: desde, p_horario: semanal,
      // Motivo fijo, no libre: esto es un clic de "hacer permanente" un turno
      // puntual ya escrito, no una persona explicando por qué cambia un
      // horario — mismo criterio que ya usan fn_set_rol/fn_set_sede_base
      // para su único llamador (ver 0440).
      p_motivo: esPasado
        ? `Turno puntual del ${d.fecha} promovido a horario base desde Revisión de Turnos, vigente desde el ${desde}: el día de origen ya pasó y un horario nuevo no reescribe días ya juzgados.`
        : `Turno puntual del ${d.fecha} promovido a horario base desde Revisión de Turnos.`,
    });
    if (e1) { setProcesando(null); setAviso(`No se pudo cambiar el horario de ${d.persona}: ${e1.message}`); return; }
    // Su `error` se comprueba igual que en `usarHorarioBase`, diez líneas más
    // arriba, que llama a ESTA MISMA función y sí lo mira. Sin comprobarlo, el
    // horario base quedaba cambiado y el turno puntual seguía ahí — y en la
    // cascada de `jornada-esperada.ts` el turno del día le gana al horario, así
    // que ese día seguía esperando la hora vieja sin que nadie lo dijera.
    // Si el día ya pasó, su turno se queda donde está. Quitarlo dejaría ese
    // día colgando del horario base ANTERIOR (el nuevo rige desde hoy), y esa
    // jornada se recalcularía contra un horario que no fue el que rigió —
    // otra vez la tardanza falsa, por la puerta de al lado.
    const { error: eQuitar } = esPasado
      ? { error: null }
      : await supabase.rpc("fn_quitar_turno", { p_persona_id: d.personaId, p_fecha: d.fecha });
    setProcesando(null);
    // El horario base ya cambió (pase lo que pase con el turno puntual): la cobertura se mueve.
    onCambio();
    if (esPasado) {
      setAviso(`El horario base de ${d.persona} rige desde hoy (${desde}), no desde el ${d.fecha}: un horario nuevo no reescribe días que ya pasaron. El ${d.fecha} se queda como estaba, con su turno puntual. Si lo que necesitas es corregir días que ya pasaron, usa "Corregir días ya trabajados" en Horarios.`);
      await cargar();
      return;
    }
    if (eQuitar) {
      setAviso(`El horario base de ${d.persona} sí cambió, pero el turno puntual de ese día no se pudo retirar: ${eQuitar.message}. Mientras siga ahí, ese día manda el turno y no el horario base.`);
      await cargar();
      return;
    }
    await cargar();
  }

  async function limpiarEspejos(lista: Divergencia[]) {
    setProcesando("bulk"); setAviso(null); setConfirmarBulk(false);
    const fallos: string[] = [];
    for (const d of lista) {
      const { error: e } = await supabase.rpc("fn_quitar_turno", { p_persona_id: d.personaId, p_fecha: d.fecha });
      if (e) fallos.push(`${d.persona} (${d.fecha})`);
    }
    setProcesando(null);
    if (fallos.length) setAviso(`No se pudieron quitar ${fallos.length}: ${fallos.join(", ")}. El resto sí.`);
    if (fallos.length < lista.length) onCambio();
    await cargar();
  }

  if (error) {
    return <BannerAviso enLinea role="alert" variante="alerta" className="mb-4">No se pudo revisar los turnos contra el horario base.</BannerAviso>;
  }
  // Cargando, o todo coincide: la franja «Para decidir» lo dice; aquí no hay nada que dibujar.
  if (divs === null || divs.length === 0) return null;
  const notaSinBase = sinBase > 0 && (
    <>
      {sinBase} turno{sinBase === 1 ? "" : "s"} {sinBase === 1 ? "cae" : "caen"} en días en que esa persona aún no tenía horario base.
      Ahí el turno es lo único que dice a qué hora le tocaba entrar, así que no hay nada que comparar ni que quitar.
    </>
  );
  // En bloque solo los que todavía no corrieron. Un espejo viejo de un día que
  // ya pasó puede estar causando una tardanza falsa… o puede haber sido lo que
  // de verdad se le indicó: eso se decide fila por fila, con su marcaje a la vista.
  const espejosTodos = divs.filter((d) => d.espejo);
  const espejos = espejosTodos.filter((d) => !d.yaCorrio);
  const espejosPasados = espejosTodos.length - espejos.length;
  if (!abierto) return null;
  return (
    <TarjetaInfo className="mb-4 overflow-hidden p-0 sm:p-0">
        <div>
          <p className="px-4 py-2 text-xs leading-relaxed text-taupe">
            El turno del día manda sobre el horario base. Decide cuál de los dos tiene la razón:{" "}
            <strong className="text-tinta">Hacer permanente</strong> = la hora del turno pasa a ser su horario base desde esa fecha (úsalo si de verdad le cambiaron el horario).{" "}
            <strong className="text-tinta">Usar el horario base</strong> = descarta el turno y vuelve a su horario (úsalo si el turno quedó viejo).
            En un día que ya pasó, eso vuelve a medir su jornada contra el horario base: antes de aplicarlo te muestra a qué hora marcó.{" "}
            Nada se borra solo: tú decides fila por fila.
          </p>
          {notaSinBase && <p className="border-t border-sand px-4 py-2 text-xs leading-relaxed text-taupe">{notaSinBase}</p>}

          {espejos.length > 0 && (
            <div className="border-t border-sand px-4 py-2">
              {confirmarBulk ? (
                <div className="flex flex-wrap items-center gap-2 text-xs">
                  <span className="text-rojo">Se quitarán {espejos.length} turnos y se recalcularán esas jornadas. ¿Confirmas?</span>
                  <Boton variante="primario" tamano="sm" onClick={() => limpiarEspejos(espejos)}>Sí, quitar {espejos.length}</Boton>
                  <Boton variante="secundario" tamano="sm" onClick={() => setConfirmarBulk(false)}>Cancelar</Boton>
                </div>
              ) : (
                <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
                  <Boton variante="peligro" tamano="sm" disabled={procesando !== null} cargando={procesando === "bulk"} onClick={() => setConfirmarBulk(true)}>
                    Quitar los {espejos.length} espejos viejos
                  </Boton>
                  <span className="text-[11px] text-taupe">
                    Esto <strong>descarta</strong> esas horas. Si a esa gente le cambiaron el horario de verdad, usa <strong>Hacer permanente</strong> fila por fila.
                    {espejosPasados > 0 && <> Los {espejosPasados} de días que ya pasaron no entran: van fila por fila, porque su jornada ya se midió.</>}
                  </span>
                </div>
              )}
            </div>
          )}

          {aviso && <div className="border-t border-sand bg-rojo/10 px-4 py-2 text-xs text-rojo">{aviso}</div>}

          <ul className="max-h-96 divide-y divide-sand overflow-y-auto border-t border-sand">
            {divs.map((d, i) => {
              const { abr, num } = etiquetaDia(d.fecha);
              const clave = `${d.personaId}-${d.fecha}-${i}`;
              return (
                <li key={clave} className="px-4 py-2">
                  <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-0.5">
                    <button onClick={() => onIrADia(d.fecha)} className="text-left text-sm hover:underline">
                      <span className="font-medium">{d.persona}</span> <span className="text-taupe">· {abr} {num}</span>
                    </button>
                    <span className="text-xs">
                      <span className="text-ambar">turno {d.turnoTxt}</span> <span className="text-taupe">· base {d.baseTxt}</span>
                      {d.yaCorrio && <span className="text-taupe"> · {d.marco ? `marcó ${d.marco}` : "sin marcaje"}</span>}
                    </span>
                  </div>
                  <div className="mt-1 flex flex-wrap items-center gap-2">
                    {d.espejo
                      ? <Insignia variante="alerta" tamano="sm">probable espejo viejo</Insignia>
                      : <Insignia variante="neutral" atenuada tamano="sm">cambio puntual</Insignia>}
                    <Boton variante="secundario" tamano="sm" onClick={() => hacerPermanente(d, clave)} disabled={procesando !== null} cargando={procesando === clave}>
                      Hacer permanente
                    </Boton>
                    <Boton variante="sutil" tamano="sm" onClick={() => (d.yaCorrio ? setConfirmarBase(clave) : usarHorarioBase(d, clave))} disabled={procesando !== null || confirmarBase === clave}>
                      Usar el horario base
                    </Boton>
                  </div>
                  {confirmarBase === clave && (
                    <div className="mt-2 rounded-lg border border-rojo/30 bg-rojo/[0.06] px-3 py-2 text-xs leading-relaxed">
                      <p className="text-tinta">{consecuenciaDeUsarBase(d)}</p>
                      <p className="mt-1 text-taupe">Si el turno era lo que de verdad se le había indicado, déjalo como está.</p>
                      <div className="mt-2 flex flex-wrap gap-2">
                        <Boton variante="peligro" tamano="sm" cargando={procesando === clave} onClick={() => usarHorarioBase(d, clave)}>Sí, medir contra el horario base</Boton>
                        <Boton variante="secundario" tamano="sm" onClick={() => setConfirmarBase(null)}>Cancelar</Boton>
                      </div>
                    </div>
                  )}
                </li>
              );
            })}
          </ul>
        </div>
    </TarjetaInfo>
  );
}

export default function TurnosPage() {
  const router = useRouter();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const esAdmin = puedeVerTodasLasSedes(rol);
  const puedeVer = puedeOperarEquipo(rol);
  const { avisar } = useToast();

  const [sedes, setSedes] = useState<Sede[]>([]);
  // Se acuerda de la última vez (useFiltroGuardado); la semana que se mira no
  // —`lunes`, abajo— porque persistirla mostraría la semana pasada al volver.
  const [sedeSel, setSedeSel] = useFiltroGuardado("turnos.sede", "");
  // «Para decidir»: cuántos hay de cada cosa (null = todavía cargando) y cuál detalle está abierto. Arranca
  // cerrado: la pantalla es la semana, y esto es lo que se mira antes de armarla.
  const [nBase, setNBase] = useState<number | null>(null);
  const [nEspejos, setNEspejos] = useState(0);
  const [nTope, setNTope] = useState<number | null>(null);
  const [topeGrave, setTopeGrave] = useState(false);
  const [decidirAbierto, setDecidirAbierto] = useState<"base" | "tope" | null>(null);
  const conteoBase = useCallback((n: number | null, espejos: number) => { setNBase(n); setNEspejos(espejos); }, []);
  const conteoTope = useCallback((n: number | null, grave: boolean) => { setNTope(n); setTopeGrave(grave); }, []);
  const [lunes, setLunes] = useState<string>(() => lunesDeLaSemana(hoyLima()));
  // Dos vistas (decisión de Felipe, 2026-11-02): Integrada = la semana hora por
  // hora con quién está en cada hora, la de entrada · Día = un día, con la línea de
  // cada persona. «Semana» (las siluetas de mañana y tarde) y la Integrada vieja
  // (la sábana de medias horas, solo con números) se retiraron: la Integrada de hoy
  // dice lo mismo con los nombres. La preferencia vive en «turnos.vista.v2» para que
  // todos arranquen una vez en la Integrada nueva; un valor viejo («semana») cae a ella.
  type Vista = "integrada" | "dia";
  const [vistaGuardada, setVista] = useFiltroGuardado<Vista>("turnos.vista.v2", "integrada");
  const vista: Vista = vistaGuardada === "dia" ? "dia" : "integrada";
  // El resumen de horas al pie de la Integrada: abierto por defecto, y cada navegador recuerda si lo plegó.
  const [resumenAbierto, setResumenAbierto] = useFiltroGuardado("turnos.resumen-abierto", true);
  // El día que se mira en la vista Día (uno a la vez: «mañana y tarde» de ese día). Se guarda como fecha; si la semana
  // cambia y esa fecha ya no está en ella, se cae a hoy (o al lunes) sin necesitar un efecto que lo corrija.
  const [diaSel, setDiaSel] = useState<string | null>(null);
  function irADia(iso: string) {
    setDiaSel(iso);
    setVista("dia");
  }
  // Desde la Integrada: el día, con la línea de cada persona ya abierta y a la vista.
  function verLineaDelDia(iso: string) {
    irADia(iso);
    window.requestAnimationFrame(() => document.getElementById(`turnos-dia-${iso}`)?.scrollIntoView({ block: "start", behavior: "smooth" }));
  }
  // Desde el diagnóstico: salta a la semana Y al día del turno a revisar.
  function irARevisar(iso: string) {
    setLunes(lunesDeLaSemana(iso));
    irADia(iso);
  }

  const [personas, setPersonas] = useState<Persona[]>([]);
  const [areas, setAreas] = useState<Area[]>(AREAS_FALLBACK);
  const [funcionesFallo, setFuncionesFallo] = useState(false);
  const [horarios, setHorarios] = useState<Map<string, Horario[]>>(new Map());
  const [turnos, setTurnos] = useState<Map<string, Turno>>(new Map());
  // Piso o almacén planificado (0579), por «persona|fecha». `null` = no se pudo leer (la tabla todavía no
  // existe en esa base, o falló la consulta): la cobertura cuenta a todas en piso y la hoja de almacén lo dice.
  const [puestos, setPuestos] = useState<Map<string, PuestoDelDia> | null>(new Map());
  // Lo marcado en el terminal (0580), por persona y día: los cambios de ubicación y la salida final, que cierra
  // un tramo abierto. null = no se pudo leer: Día sigue solo con el plan, como antes.
  const [reales, setReales] = useState<{ cambios: Map<string, CambioUbicacion[]>; marcajes: Map<string, MarcajeDelDia[]> } | null>(null);
  // La venta de cada hora (retail, 0584) para la repetición de un día cerrado: por «fecha» → hora → compras.
  // null = no se pudo leer: la repetición lo dice con palabras, nunca como cero.
  const [compras, setCompras] = useState<Map<string, Map<number, number>> | null>(new Map());
  // El ritmo y el mínimo de la tienda (Parámetros, 0584); null = no se pudieron leer.
  const [coberturaVenta, setCoberturaVenta] = useState<{ ritmo: number; minimo: number } | null>(null);
  const [metas, setMetas] = useState<Map<number, number>>(new Map()); // meta operativas MAÑANA
  const [metasTarde, setMetasTarde] = useState<Map<number, number>>(new Map()); // meta operativas TARDE
  const [metasEncargadas, setMetasEncargadas] = useState<Map<number, number>>(new Map());
  const [cargando, setCargando] = useState(true);
  // Cuántos turnos puntuales tiene la semana anterior, para el botón "Copiar
  // semana anterior" — null mientras no se sabe, 0 = no hay nada que copiar
  // (el botón ni se muestra). Copiar de verdad pasa por fn_copiar_semana_anterior;
  // esto es solo la cuenta para el texto del botón, antes de aplicar nada.
  const [copiarDisponibles, setCopiarDisponibles] = useState<number | null>(null);
  const [confirmarCopiar, setConfirmarCopiar] = useState(false);
  const [copiando, setCopiando] = useState(false);
  // Feriados de la semana en pantalla (fecha → nombre) y las pruebas abiertas por persona. Sirven SOLO para
  // recomendar descanso a quien está de prueba (prueba-en-feriado.ts); si fallan quedan vacíos y la pantalla
  // se comporta como siempre, salvo que el vínculo ya dice «prueba» y entonces se avisa igual.
  const [feriadosSemana, setFeriadosSemana] = useState<Map<string, string>>(new Map());
  const [pruebas, setPruebas] = useState<Map<string, FilaPrueba>>(new Map());
  const [confirmaFeriado, setConfirmaFeriado] = useState(false);

  // edición de celda
  const [edit, setEdit] = useState<{ personaId: string; fecha: string } | null>(null);
  const [entrada, setEntrada] = useState("");
  const [salida, setSalida] = useState("");
  const [guardando, setGuardando] = useState(false);
  // Ciclo de 48h de la persona que se está editando — mismo cálculo que
  // AlertaSobretiempo (cicloVigente sobre sus jornadas reales), pero acá solo
  // para esta persona, para poder avisar DENTRO del modal antes de guardar.
  const [cicloEdit, setCicloEdit] = useState<ReturnType<typeof cicloVigente>>(null);

  const dias = useMemo(() => Array.from({ length: 7 }, (_, i) => addDays(lunes, i)), [lunes]);
  const diaActivo = diaSel && dias.includes(diaSel) ? diaSel : (dias.includes(hoyLima()) ? hoyLima() : dias[0]);
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const reqId = useRef(0); // "última carga gana": descarta respuestas fuera de orden
  const cargaConMetas = useRef(0); // id de la carga completa o en sitio que está en curso (0 = ninguna); ver `cargar`
  // Pedir una recarga sin llamar a `cargar` desde un manejador de pantalla: así lo que se dibuja no arrastra la lectura de `reqId`.
  const [recarga, setRecarga] = useState(0);

  // Deep-link: al llegar con ?fecha=<YYYY-MM-DD> (desde Incidencias, ej. déficit
  // de encargadas), salta directo a la semana de esa fecha.
  useEffect(() => {
    const sp = new URLSearchParams(window.location.search);
    const f = sp.get("fecha");
    if (f) setLunes(lunesDeLaSemana(f));
  }, []);

  // sedes + sede inicial
  useEffect(() => {
    supabase.auth.getSession().then(async ({ data }) => {
      if (!data.session) { router.replace("/admin/login"); return; }
      const { data: s, error: eS } = await supabase.from("sedes").select("id, codigo, nombre, tipo").order("codigo");
      // Sin esto, si la consulta fallaba `sedes` se quedaba en [] en silencio:
      // el selector de sede salía vacío y la pantalla no decía por qué —
      // se leía como "no hay sedes", no como el error que de verdad era.
      if (eS) { avisar("error", mensajeDeError(eS, "cargar las sedes")); return; }
      const lista = (s as Sede[]) ?? [];
      setSedes(lista);
      // La encargada queda FIJA en su sede (su selector está oculto): forzamos su sede
      // en cuanto `yo` resuelve, sin dejar que el fallback lista[0] la ancle a otra.
      // El admin sí puede elegir, así que solo ponemos un valor inicial si no hay uno.
      if (esAdmin) setSedeSel((prev) => prev || (lista[0]?.id ?? ""));
      else if (yo) setSedeSel(yo.sedeBaseId);
    });
  }, [supabase, router, yo, esAdmin, avisar]);

  // Tres formas de leer la semana, que solo difieren en lo que se ve mientras tanto:
  //   · "completa": al entrar, cambiar de sede o de semana. Muestra «Cargando…».
  //   · "en-sitio": después de guardar algo aquí. Los números cambian en su
  //     lugar, sin borrar la grilla; si falla, se avisa.
  //   · "fondo": otra pestaña u otra persona cambió algo (useTurnosAlDia). Igual
  //     que "en-sitio", pero un error no se avisa: se queda lo último que se vio
  //     y la próxima lectura lo vuelve a intentar, sin un aviso por minuto.
  const cargar = useCallback(async (modo: "completa" | "en-sitio" | "fondo" = "completa") => {
    if (!sedeSel) return;
    // Una lectura de fondo no le gana a una que sí trae todo: con «última carga
    // gana», la de fondo descartaría la de la sede nueva y dejaría las metas de
    // la sede anterior (el fondo no lee metas). Si hay una en curso, el fondo espera al minuto siguiente.
    if (modo === "fondo" && cargaConMetas.current !== 0) return;
    const mi = ++reqId.current;
    if (modo !== "fondo") cargaConMetas.current = mi;
    if (modo === "completa") setCargando(true);
    const domingo = addDays(lunes, 6);
    const [
      { data: p, error: pErr },
      { data: h, error: hErr },
      { data: t, error: tErr },
      { data: m, error: mErr },
      { data: f, error: fErr },
      { data: ar, error: arErr },
      { data: fer },
      { data: pru },
      { data: pue, error: pueErr },
      { data: cam, error: camErr },
      { data: sal, error: salErr },
      { data: com, error: comErr },
      { data: cpv, error: cpvErr },
    ] = await Promise.all([
      // Mismo criterio del dashboard (7afe8e5): un practicante cubre piso
      // igual que cualquiera y cuenta para la meta de cobertura de la sede —
      // decisión de Felipe (2026-09-12) — así que entra a la grilla con el
      // mismo `OR` puntual, sin tocar `en_planilla` ni el escalafón
      // disciplinario, que siguen igual para las demás pantallas.
      supabase.from("personas").select("id, nombres, apellidos, rol")
        .eq("sede_base_id", sedeSel).eq("estado", "activo").eq("cuenta_de_servicio", false)
        .or("en_planilla.eq.true,tipo_vinculo.eq.practicante")
        .eq("sueldo_fijo", false).order("nombres"),
      supabase.from("horarios_asignados").select("persona_id, hora_entrada, hora_salida, dias_laborables, horario_por_dia, almuerzo_min_minutos, vigente_desde, vigente_hasta").lte("vigente_desde", domingo).or(`vigente_hasta.is.null,vigente_hasta.gte.${lunes}`),
      supabase.from("turnos").select("persona_id, fecha, hora_entrada, hora_salida, es_descanso").gte("fecha", lunes).lte("fecha", domingo),
      supabase.from("metas_cobertura").select("dia_semana, meta, meta_tarde, meta_encargadas").eq("sede_id", sedeSel),
      supabase.rpc("fn_personas_funciones"), // "funcion" vía RPC: el schema cache de PostgREST no expone la columna
      supabase.rpc("fn_areas"), // catálogo dinámico de áreas (nunca .from("areas"): schema cache trabado)
      supabase.from("feriados").select("fecha, nombre").gte("fecha", lunes).lte("fecha", domingo),
      supabase.rpc("fn_pruebas_abiertas"),
      // El almacén no frena la semana: si falla (p. ej. la 0579 todavía no está pegada), se sigue sin él.
      supabase.from("puestos_planificados").select("persona_id, fecha, desde, hasta").gte("fecha", lunes).lte("fecha", domingo),
      // Lo real del terminal (0580), solo para la vista Día. Tampoco frena la semana. `as never`: la tabla todavía
      // no está en los tipos generados (el terminal la lee igual, en lib/terminal/ubicacion-cola.ts).
      supabase.from("cambios_ubicacion" as never).select("persona_id, ubicacion, timestamp_cambio, vuelve_previsto")
        .eq("sede_id" as never, sedeSel as never).is("anulado_at" as never, null)
        .gte("timestamp_cambio" as never, rangoDelDiaLima(lunes).inicio as never).lte("timestamp_cambio" as never, rangoDelDiaLima(domingo).fin as never),
      // Lo marcado de la semana, sin anulados: la salida final cierra un tramo abierto (la misma regla del terminal y de
      // fn_ubicaciones_del_dia), y la repetición de un día cerrado usa todas las marcas.
      supabase.from("marcajes").select("persona_id, tipo, timestamp_marca, fecha_jornada")
        .is("anulada_at", null)
        .gte("timestamp_marca", rangoDelDiaLima(lunes).inicio).lte("timestamp_marca", rangoDelDiaLima(domingo).fin),
      // La venta de cada hora y los dos números de la tienda (0584). Tampoco frenan la semana.
      supabase.rpc("fn_compras_por_hora", { p_sede_id: sedeSel, p_desde: lunes, p_hasta: domingo }),
      supabase.rpc("fn_cobertura_por_venta", { p_sede_id: sedeSel }),
    ]);
    if (mi !== reqId.current) return; // llegó una carga más nueva; descarto ésta
    if (modo !== "fondo") cargaConMetas.current = 0;
    if (pErr || hErr || tErr || mErr) {
      if (modo !== "fondo") avisar("error", mensajeDeError((pErr ?? hErr ?? tErr ?? mErr)!, "cargar la semana"));
      setCargando(false);
      return; // no pisa personas/horarios/turnos/metas con datos parciales/vacíos
    }
    setAreas(parseAreas(ar, arErr));
    setFeriadosSemana(new Map(((fer as { fecha: string; nombre: string }[] | null) ?? []).map((x) => [x.fecha, x.nombre] as const)));
    setPruebas(new Map(((pru as FilaPrueba[] | null) ?? []).map((x) => [x.persona_id, x] as const)));
    // Si falla la RPC de funciones O la del catálogo de áreas, la cobertura puede
    // contar mal (degrada a defaults) — se avisa en pantalla en vez de fallar en silencio.
    setFuncionesFallo(Boolean(fErr) || Boolean(arErr));
    const mapF = new Map(((f as { persona_id: string; funcion: string; es_encargada_piso?: boolean; tipo_vinculo?: string | null }[] | null) ?? []).map((x) => [x.persona_id, { funcion: x.funcion, esEncargadaPiso: Boolean(x.es_encargada_piso), tipoVinculo: x.tipo_vinculo ?? null }]));
    setPersonas((((p as Omit<Persona, "funcion" | "esEncargadaPiso" | "tipoVinculo">[]) ?? []).map((x) => ({ ...x, funcion: mapF.get(x.id)?.funcion ?? AREA_DEFAULT, esEncargadaPiso: mapF.get(x.id)?.esEncargadaPiso ?? false, tipoVinculo: mapF.get(x.id)?.tipoVinculo ?? null }))));
    const mapH = new Map<string, Horario[]>();
    for (const x of (h as HorarioTramo[]) ?? []) {
      const arr = mapH.get(x.persona_id) ?? [];
      arr.push(x);
      mapH.set(x.persona_id, arr);
    }
    setHorarios(mapH);
    setTurnos(new Map(((t as any[]) ?? []).map((x) => [`${x.persona_id}|${x.fecha}`, { es_descanso: x.es_descanso, hora_entrada: x.hora_entrada, hora_salida: x.hora_salida }])));
    if (pueErr) {
      setPuestos(null);
    } else {
      const porDia = new Map<string, { desde: string | null; hasta: string | null }[]>();
      for (const x of pue ?? []) {
        const k = `${x.persona_id}|${x.fecha}`;
        porDia.set(k, [...(porDia.get(k) ?? []), { desde: x.desde, hasta: x.hasta }]);
      }
      setPuestos(new Map([...porDia].map(([k, filas]) => [k, puestoDesdeFilas(filas)])));
    }
    if (camErr || salErr) {
      setReales(null);
    } else {
      const cambios = new Map<string, CambioUbicacion[]>();
      for (const x of (cam ?? []) as unknown as { persona_id: string; ubicacion: Ubicacion; timestamp_cambio: string; vuelve_previsto: string | null }[]) {
        const k = `${x.persona_id}|${fechaLima(x.timestamp_cambio)}`;
        cambios.set(k, [...(cambios.get(k) ?? []), { ubicacion: x.ubicacion, timestamp: x.timestamp_cambio, vuelvePrevisto: x.vuelve_previsto }]);
      }
      const marcajes = new Map<string, MarcajeDelDia[]>();
      for (const x of (sal ?? []) as { persona_id: string; tipo: MarcajeDelDia["tipo"]; timestamp_marca: string; fecha_jornada: string | null }[]) {
        const k = `${x.persona_id}|${x.fecha_jornada ?? fechaLima(x.timestamp_marca)}`;
        marcajes.set(k, [...(marcajes.get(k) ?? []), { tipo: x.tipo, timestamp: x.timestamp_marca }]);
      }
      setReales({ cambios, marcajes });
    }
    if (comErr) {
      setCompras(null);
    } else {
      const porFecha = new Map<string, Map<number, number>>();
      for (const x of (com ?? []) as { fecha: string; hora: number; compras: number }[]) {
        const dia = porFecha.get(x.fecha) ?? new Map<number, number>();
        dia.set(x.hora, x.compras);
        porFecha.set(x.fecha, dia);
      }
      setCompras(porFecha);
    }
    const filaCpv = !cpvErr && Array.isArray(cpv) ? (cpv as { ritmo: number; minimo: number }[])[0] : undefined;
    setCoberturaVenta(filaCpv ? { ritmo: Number(filaCpv.ritmo), minimo: Number(filaCpv.minimo) } : null);
    setCargando(false);
    // Las metas solo se cambian desde esta pantalla, y se guardan al salir del
    // campo: una lectura de fondo que salió antes de ese guardado traería la
    // meta vieja y la pintaría encima de la recién tecleada. Así que el fondo
    // no las toca; se leen al entrar, al cambiar de sede o de semana, y tras guardar.
    if (modo === "fondo") return;
    setMetas(new Map(((m as any[]) ?? []).map((x) => [x.dia_semana, x.meta])));
    setMetasTarde(new Map(((m as any[]) ?? []).map((x) => [x.dia_semana, x.meta_tarde ?? x.meta ?? 0])));
    setMetasEncargadas(new Map(((m as any[]) ?? []).map((x) => [x.dia_semana, x.meta_encargadas ?? 0])));
    // `recarga` no se lee dentro: está en las dependencias para que pedir una recarga haga correr el efecto que ya llama a cargar().
  }, [supabase, sedeSel, lunes, avisar, recarga]);

  useEffect(() => { void cargar(); }, [cargar]);

  // ── Al día sin recargar (2026-11-02) ─────────────────────────────────────
  // `alDia` sube cada vez que cambiaron turnos u horarios fuera de «Para
  // decidir»: así ese panel vuelve a comparar contra lo nuevo. Lo que cambia
  // DENTRO de «Para decidir» llega por `alCambiarDesdeRevision`, que mueve la
  // grilla. Y lo que cambia en otra pestaña o lo cambia otra persona llega por
  // useTurnosAlDia (ver lib/admin/turnos-al-dia.ts).
  const [alDia, setAlDia] = useState(0);
  const cargarRef = useRef(cargar);
  useEffect(() => { cargarRef.current = cargar; });
  useTurnosAlDia(useCallback(() => {
    void cargarRef.current("fondo");
    setAlDia((n) => n + 1);
  }, []), Boolean(sedeSel));
  const alCambiarDesdeRevision = useCallback(() => {
    avisarCambioDeTurnos();
    void cargarRef.current("en-sitio");
  }, []);
  // Después de guardar algo desde la grilla: avisa a las otras pestañas y a
  // «Para decidir», y vuelve a leer sin borrar la grilla.
  async function trasGuardar() {
    avisarCambioDeTurnos();
    setAlDia((n) => n + 1);
    await cargar("en-sitio");
  }

  // Cuenta rápida de la semana anterior, solo para el botón — no filtra por
  // "ya tiene turno en el destino" ni por persona activa (eso lo decide
  // fn_copiar_semana_anterior de verdad al aplicar), así que el número del
  // botón es un techo ("hasta N"), no una promesa exacta.
  useEffect(() => {
    if (!sedeSel) return;
    let vivo = true;
    void (async () => {
      setCopiarDisponibles(null);
      const domingoAnterior = addDays(lunes, -1);
      const lunesAnterior = addDays(lunes, -7);
      // `personas!turnos_persona_id_fkey`, no `personas!inner` a secas: turnos
      // tiene DOS llaves foráneas hacia personas (persona_id y creado_por), y
      // sin nombrar cuál, PostgREST responde 300 Multiple Choices en vez de
      // filtrar — un silencio distinto al de "no hay nada que copiar".
      const { count, error } = await supabase.from("turnos")
        .select("persona_id, personas!turnos_persona_id_fkey!inner(sede_base_id, estado)", { count: "exact", head: true })
        .eq("personas.sede_base_id", sedeSel).eq("personas.estado", "activo")
        .gte("fecha", lunesAnterior).lte("fecha", domingoAnterior);
      if (!vivo) return;
      setCopiarDisponibles(error ? 0 : (count ?? 0));
    })();
    return () => { vivo = false; };
  }, [sedeSel, lunes, supabase]);

  async function copiarSemanaAnterior() {
    setCopiando(true);
    setConfirmarCopiar(false);
    const { data, error } = await supabase.rpc("fn_copiar_semana_anterior", { p_sede_id: sedeSel, p_lunes_destino: lunes });
    setCopiando(false);
    if (error) { avisar("error", mensajeDeError(error, "copiar la semana anterior")); return; }
    const filas = (data as { resultado: string }[]) ?? [];
    const copiados = filas.filter((f) => f.resultado === "copiado").length;
    const saltados = filas.filter((f) => f.resultado.startsWith("saltado")).length;
    const fallidos = filas.length - copiados - saltados;
    avisar("ok",
      `Se copiaron ${copiados} turno${copiados === 1 ? "" : "s"} de la semana pasada.`
      + (saltados > 0 ? ` ${saltados} ya tenía${saltados === 1 ? "" : "n"} turno propio esta semana y no se tocaron.` : "")
      + (fallidos > 0 ? ` ${fallidos} no se pudieron copiar (revísalos en Correcciones).` : ""));
    await trasGuardar();
  }

  // Si la semana destino tiene feriado y la sede tiene gente de prueba, la copia puede dejarle turno ese día.
  const avisoCopiar = useMemo(
    () => avisoDeCopiar([...feriadosSemana.values()], personas.some((p) => p.tipoVinculo === "prueba" && conviveDarDescanso({ tipoVinculo: p.tipoVinculo, situacion: pruebas.get(p.id)?.situacion ?? null, dias: null, plazo: null }, true))),
    [feriadosSemana, personas, pruebas],
  );

  const celda = useCallback((personaId: string, fecha: string): Celda => {
    const turno = turnos.get(`${personaId}|${fecha}`) ?? null;
    const tramo = horarioVigente(horarios.get(personaId) ?? [], fecha);
    const esp = esperadoDelDia(fecha, turno, tramo);
    if (esp.origen === "turno") {
      // El turno del día manda: si vino de acá, gana sobre el horario base sin
      // mirarlo. esp.entrada nunca es null cuando esp.trabaja es true — lo
      // garantiza el contrato de Esperado en jornada-esperada.ts.
      return esp.trabaja ? { tipo: "turno", entrada: esp.entrada!, salida: esp.salida } : { tipo: "descanso" };
    }
    if (!esp.trabaja) return { tipo: "libre" }; // sin turno y el horario base descansa (o no hay horario)
    // el refrigerio (r, en minutos) solo se conoce para el horario base con
    // jsonb explícito por día — el legacy (dias_laborables) no lo guarda, así
    // que su barra queda sin hueco (dato que no tenemos, mejor no inventarlo).
    const dow = String(diaSemana(fecha));
    return { tipo: "default", entrada: esp.entrada!, salida: esp.salida, refrigerio: tramo?.horario_por_dia?.[dow]?.r };
  }, [turnos, horarios]);

  // ¿Conviene darle descanso este día? Solo quien está de prueba, en un feriado (prueba-en-feriado.ts).
  const pruebaDeLaPersona = useCallback((personaId: string, fecha: string) => {
    const p = personas.find((x) => x.id === personaId);
    const f = pruebas.get(personaId);
    const ok = conviveDarDescanso(
      { tipoVinculo: p?.tipoVinculo ?? null, situacion: f?.situacion ?? null, dias: f?.dias_trabajados ?? null, plazo: f?.dias_plazo ?? null },
      feriadosSemana.has(fecha),
    );
    return ok ? { nombreFeriado: feriadosSemana.get(fecha) ?? null, dias: f?.dias_trabajados ?? null, plazo: f?.dias_plazo ?? null } : null;
  }, [personas, pruebas, feriadosSemana]);

  // Quién de prueba queda trabajando un feriado de esta semana, sea por turno puesto, copiado o por su horario base.
  const pruebaEnFeriado = useMemo<PersonaEnFeriado[]>(() => {
    const lista: PersonaEnFeriado[] = [];
    for (const [fecha, feriado] of feriadosSemana) {
      for (const p of personas) {
        const c = celda(p.id, fecha);
        if (c.tipo !== "turno" && c.tipo !== "default") continue;
        const a = pruebaDeLaPersona(p.id, fecha);
        if (!a) continue;
        lista.push({ personaId: p.id, nombre: `${p.nombres} ${p.apellidos}`, fecha, feriado, dias: a.dias, plazo: a.plazo });
      }
    }
    return lista.sort((x, y) => x.fecha.localeCompare(y.fecha) || x.nombre.localeCompare(y.nombre));
  }, [feriadosSemana, personas, celda, pruebaDeLaPersona]);

  // Cuántas personas (según `filtro`) cubren cada franja del día — reusada para
  // la franja de la Vista Día (operativas, 1h) y las 2 tablas de la Vista
  // Semana (operativas y encargadas, 30 min ancladas a :15/:45).
  const coberturaPorFranja = useCallback((fecha: string, horaInicio: number, nFranjas: number, tamHoras: number, filtro: (p: Persona) => boolean): number[] => {
    const franjas = Array.from({ length: nFranjas }, () => 0);
    for (const p of personas) {
      if (!filtro(p)) continue;
      const c = celda(p.id, fecha);
      if (c.tipo !== "turno" && c.tipo !== "default") continue;
      const e = horaADecimal(c.entrada);
      const s = c.salida ? horaADecimal(c.salida) : HORA_FIN;
      for (let i = 0; i < franjas.length; i++) {
        const hi = horaInicio + i * tamHoras, hf = hi + tamHoras;
        if (e < hf && s > hi) franjas[i]++;
      }
    }
    return franjas;
  }, [personas, celda]);
  // Quién cuenta como operativo y como líder es UNA definición
  // (packages/shared/src/cobertura-equipo.ts), la misma del Dashboard y del
  // Reporte de sede: depende del tipo de la sede que se está mirando. La marca
  // es_encargada_piso sigue sirviendo para un admin de confianza que además está
  // en el piso de una tienda, como Janis.
  const tipoSedeSel = sedes.find((x) => x.id === sedeSel)?.tipo ?? null;
  const cuentaEnPiso = useCallback(
    (p: Persona) => cuentaEnCobertura(
      { rol: p.rol, tipoVinculo: p.tipoVinculo, esEncargadaPiso: p.esEncargadaPiso, areaOperativa: esOperativaEn(areas, p.funcion) },
      tipoSedeSel,
    ),
    [areas, tipoSedeSel],
  );
  // «Operativa» de Turnos es quien cuenta contra la meta de la sede: en una central, cualquiera del equipo.
  const esOperativa = useCallback((p: Persona) => cuentaEnPiso(p).cuentaEnMetaOp, [cuentaEnPiso]);
  const esEncargada = (p: Persona) => cuentaEnPiso(p).lider;
  // ¿Ese día la sede simplemente no se labora? (ver etiquetaSedeSinTurnos). «Nadie
  // tiene turno» se le pregunta a jornada-esperada.ts con TODAS las personas de la
  // grilla —no solo las del grupo medido—, y las tres metas son las que están en
  // pantalla. null = el día se muestra como siempre. Sirve a las vistas Día y Semana.
  const sedeSinTurnosEn = (iso: string) => {
    const dia = diaSemana(iso);
    return etiquetaSedeSinTurnos(
      diaDeLaSedeDe(personas.map((p) => p.id), iso, (id) => turnos.get(`${id}|${iso}`) ?? null, (id) => horarios.get(id) ?? []),
      { manana: metas.get(dia) ?? 0, tarde: metasTarde.get(dia) ?? 0, lideres: metasEncargadas.get(dia) ?? 0 },
    );
  };
  const coberturaPorHora = useCallback(
    (fecha: string) => coberturaPorFranja(fecha, HORA_INICIO, HORA_FIN - HORA_INICIO, 1, esOperativa),
    [coberturaPorFranja, esOperativa],
  );
  // ── «Mañana y tarde»: la cobertura de un día dicha en dos tramos (ver lib/admin/cobertura-tramos.ts) ──
  const turnosDecimalesDe = (iso: string, filtro: (p: Persona) => boolean): TurnoDecimal[] =>
    personas.filter(filtro).flatMap((p) => {
      const c = celda(p.id, iso);
      if (c.tipo !== "turno" && c.tipo !== "default") return [];
      return [{ id: p.id, entrada: horaADecimal(c.entrada), salida: c.salida ? horaADecimal(c.salida) : HORA_FIN }];
    });
  const tramosDelDia = (iso: string) => {
    const dia = diaSemana(iso);
    const ops = turnosDecimalesDe(iso, esOperativa);
    const lid = turnosDecimalesDe(iso, esEncargada);
    return {
      manana: resumenDelTramo({ turnos: ops, tramo: "manana", meta: metas.get(dia) ?? 0, inicioDia: HORA_INICIO, finDia: HORA_FIN }),
      tarde: resumenDelTramo({ turnos: ops, tramo: "tarde", meta: metasTarde.get(dia) ?? 0, inicioDia: HORA_INICIO, finDia: HORA_FIN }),
      lideres: resumenDeLideres(lid.length, metasEncargadas.get(dia) ?? 0),
      idsLideres: new Set(lid.map((t) => t.id)),
    };
  };
  const personaDelDia = (p: Persona, iso: string): PersonaDelDia => {
    const c = celda(p.id, iso);
    const detalle = c.tipo === "turno" || c.tipo === "default" ? `${c.entrada.slice(0, 5)}–${c.salida ? c.salida.slice(0, 5) : "…"}` : c.tipo === "descanso" ? "descanso" : "sin turno";
    return { id: p.id, nombre: `${p.nombres} ${p.apellidos}`, detalle, aparte: !esOperativa(p) && !esEncargada(p) ? areaCorto(areas, p.funcion) : undefined };
  };
  const nombrePersona = (id: string) => personas.find((x) => x.id === id);
  // Un símbolo por día para el selector: lo que importa a primera vista, con su palabra.
  const simboloDelDia = (iso: string): { s: string; t: string } => {
    if (sedeSinTurnosEn(iso)) return { s: "–", t: "sin turnos" };
    const t = tramosDelDia(iso);
    const e = [t.manana.estado, t.tarde.estado];
    if (e.includes("falta") || e.includes("con_huecos") || t.lideres.estado === "falta") return { s: "▲", t: "falta gente" };
    if (e.includes("sobra")) return { s: "●", t: "sobra gente" };
    if (e.every((x) => x === "sin_meta") && t.lideres.estado === "sin_meta") return { s: "·", t: "sin meta" };
    return { s: "✓", t: "cubierto" };
  };
  // La sugerencia de siempre (redistribuir / falta personal), con el candidato concreto a mover.
  const sugerenciaDe = (iso: string): string | null => {
    const dia = diaSemana(iso);
    const r = resumenOperativas(coberturaPorFranja(iso, HORA_INICIO_SEMANA, N_FRANJAS_SEMANA, 0.5, esOperativa), metas.get(dia) ?? 0, metasTarde.get(dia) ?? 0, HORA_INICIO_SEMANA, 0.5);
    if (!r.sug) return null;
    let candidato = "";
    const operativas = personas.filter(esOperativa);
    if (r.redistribuir === "adelantar") {
      const c = operativas.find((p) => { const cel = celda(p.id, iso); return (cel.tipo === "turno" || cel.tipo === "default") && horaADecimal(cel.entrada) >= CORTE_TARDE; });
      if (c) candidato = ` Ej. adelanta a ${c.nombres}.`;
    } else if (r.redistribuir === "retrasar") {
      const c = operativas.find((p) => { const cel = celda(p.id, iso); return (cel.tipo === "turno" || cel.tipo === "default") && cel.salida !== null && cel.salida !== undefined && horaADecimal(cel.salida) <= CORTE_TARDE + 1; });
      if (c) candidato = ` Ej. retrasa la salida de ${c.nombres}.`;
    }
    return `${r.redistribuir ? "↔" : "＋"} ${r.sug}${candidato}`;
  };


  // El plan de piso/almacén de una persona un día (piso si no hay nada, o si no se pudo leer).
  const puestoDe = (personaId: string, iso: string): PuestoDelDia => puestos?.get(`${personaId}|${iso}`) ?? PISO;
  // El almacén de una persona un día. La Integrada usa SOLO el plan (planificar la semana); la vista Día usa
  // `conLoReal`: lo marcado en el terminal hasta ahora y el plan después (decisión de Felipe, 2026-11-03). Quién
  // estuvo dónde lo decide la regla del terminal (almacenConLoReal → tramosDelDia), no esta pantalla.
  const almacenDe = (personaId: string, iso: string, turno: TramoDecimal, conLoReal: boolean): TramoDecimal[] => {
    const plan = tramosEnAlmacen(puestoDe(personaId, iso), turno);
    if (!conLoReal || !reales) return plan;
    return almacenConLoReal({
      plan, turno, ahora: new Date(), medianocheIso: rangoDelDiaLima(iso).inicio,
      cambios: reales.cambios.get(`${personaId}|${iso}`) ?? [],
      marcajes: reales.marcajes.get(`${personaId}|${iso}`) ?? [],
    }).cobertura;
  };
  // Solo lo marcado en el terminal, hasta ahora: se dibuja aparte del plan en la línea del día.
  const marcadoDe = (personaId: string, iso: string, turno: TramoDecimal): TramoDecimal[] => {
    const cambios = reales?.cambios.get(`${personaId}|${iso}`);
    if (!reales || !cambios?.length) return [];
    return almacenConLoReal({
      plan: [], turno, cambios, ahora: new Date(), medianocheIso: rangoDelDiaLima(iso).inicio,
      marcajes: reales.marcajes.get(`${personaId}|${iso}`) ?? [],
    }).marcado;
  };
  // Integrada: los turnos de un día con su nombre corto y si suman (ver lib/admin/semana-con-nombres.ts).
  // Nombre y primera letra del apellido: en una casilla no cabe el completo, y dos «Diana» se distinguen igual.
  const turnosConNombreDe = (iso: string, conLoReal = false): TurnoConNombre[] =>
    personas.flatMap((p) => {
      const c = celda(p.id, iso);
      if (c.tipo !== "turno" && c.tipo !== "default") return [];
      const cuenta = esOperativa(p), lider = esEncargada(p);
      const aparte = cuenta || lider ? undefined : p.tipoVinculo === "prueba" ? "preselección" : areaCorto(areas, p.funcion);
      const corto = `${p.nombres.split(" ")[0]}${p.apellidos ? ` ${p.apellidos[0]}.` : ""}`;
      const entrada = horaADecimal(c.entrada), salida = c.salida ? horaADecimal(c.salida) : HORA_FIN;
      // El plan de almacén de un día sin turno se ignora: no hay en qué piso descontarlo.
      const almacen = almacenDe(p.id, iso, { desde: entrada, hasta: salida }, conLoReal);
      return [{ id: p.id, nombre: corto, entrada, salida, cuenta, lider, aparte, almacen }];
    });

  // ── «¿Dónde trabaja ese día?»: piso o almacén planificado (0579) ────────────
  const [almacenEdit, setAlmacenEdit] = useState<{ personaId: string; fecha: string } | null>(null);
  const [almacenSel, setAlmacenSel] = useState<PuestoDelDia>(PISO);
  const [guardandoAlmacen, setGuardandoAlmacen] = useState(false);
  function abrirAlmacen(personaId: string, fecha: string) {
    setAlmacenSel(puestoDe(personaId, fecha));
    setAlmacenEdit({ personaId, fecha });
  }
  async function guardarAlmacen() {
    if (!almacenEdit) return;
    setGuardandoAlmacen(true);
    const { error } = await supabase.rpc("fn_set_almacen_del_dia", {
      p_persona_id: almacenEdit.personaId, p_fecha: almacenEdit.fecha, ...argumentosDeGuardado(almacenSel),
    });
    setGuardandoAlmacen(false);
    if (error) { avisar("error", mensajeDeError(error, "guardar dónde trabaja ese día")); return; }
    const p = personas.find((x) => x.id === almacenEdit.personaId);
    avisar("ok", `Listo: ${p?.nombres ?? "la persona"} · ${textoPuesto(almacenSel)}.`);
    setAlmacenEdit(null);
    await trasGuardar();
  }

  function abrir(personaId: string, fecha: string) {
    const c = celda(personaId, fecha);
    setEdit({ personaId, fecha });
    setConfirmaFeriado(false);
    setEntrada(c.tipo === "turno" || c.tipo === "default" ? c.entrada : "");
    setSalida((c.tipo === "turno" || c.tipo === "default") && c.salida ? c.salida : "");
  }

  // Al abrir el modal de una persona, trae su ciclo vigente (últimos 28 días
  // de jornadas reales) para poder avisar si ya está cerca de las 48h antes de
  // guardarle otro turno. Es el estado ACTUAL de hoy, no una proyección de "si
  // guardo esto, cuánto sumaría" — cicloVigente ya es una copia de lectura de
  // fn_planilla_calcular_nucleo y simular un total futuro sobre esa copia
  // arriesgaría desincronizarse del cálculo real (mismo riesgo que ya
  // documentó CLAUDE.md para otras reglas duplicadas).
  useEffect(() => {
    if (!edit) return;
    let vivo = true;
    void (async () => {
      setCicloEdit(null);
      const hoy = hoyLima();
      const desde = addDays(hoy, -28);
      const { data, error } = await supabase.from("jornadas")
        .select("fecha, horas_trabajadas")
        .eq("persona_id", edit.personaId).gte("fecha", desde).lte("fecha", hoy);
      if (error || !vivo) return;
      const dias: DiaTrabajado[] = ((data as { fecha: string; horas_trabajadas: number | null }[]) ?? [])
        .map((j) => ({ fecha: j.fecha, horas: j.horas_trabajadas ?? 0 }));
      if (vivo) setCicloEdit(cicloVigente(dias, hoy));
    })();
    return () => { vivo = false; };
  }, [edit, supabase]);

  async function ejecutar(fn: () => PromiseLike<{ error: any }>) {
    setGuardando(true);
    const { error } = await fn();
    setGuardando(false);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    setEdit(null);
    await trasGuardar();
  }

  const guardarTurno = () => {
    if (!edit || !entrada) { avisar("error", "Pon al menos la hora de entrada."); return; }
    if (pruebaDeLaPersona(edit.personaId, edit.fecha) && !confirmaFeriado) { avisar("error", "Confirma que está de acuerdo en que trabaje el feriado, o dale descanso."); return; }
    return ejecutar(() => supabase.rpc("fn_set_turno", { p_persona_id: edit.personaId, p_fecha: edit.fecha, p_hora_entrada: entrada, p_hora_salida: salida || null }));
  };
  // "De aquí en adelante": el cambio NO es puntual, es la nueva regla. Toma el
  // horario base vigente, le cambia SOLO ese día de la semana y lo guarda con
  // vigencia desde esa fecha (fn_set_horario_semanal ya recalcula las jornadas).
  // Además quita el turno puntual, que dejaría de tener sentido: la regla lo cubre.
  const guardarDesdeAqui = async () => {
    if (!edit) return;
    if (!entrada || !salida) { avisar("error", "Para cambiar el horario base necesito entrada y salida."); return; }
    if (pruebaDeLaPersona(edit.personaId, edit.fecha) && !confirmaFeriado) { avisar("error", "Confirma que está de acuerdo en que trabaje el feriado, o dale descanso."); return; }
    const tr = horarioVigente(horarios.get(edit.personaId) ?? [], edit.fecha);
    const semanal = horarioSemanalDesdeTramo(tr);
    const dow = String(diaSemana(edit.fecha));
    const previo = tr?.horario_por_dia?.[dow];
    semanal[dow] = { e: entrada, s: salida, ...(previo?.r != null ? { r: previo.r } : {}) };
    // Mismo tope que "Hacer permanente" en Revisión de Turnos, y por la misma
    // razón (0444): un horario normal no rige desde una fecha pasada. "De aquí
    // en adelante" es, literalmente, hacia adelante; si el día que se está
    // editando ya pasó, "adelante" empieza hoy. El día editado conserva su
    // turno puntual, que es lo que de verdad rigió.
    const hoyIso = hoyLima();
    const desde = edit.fecha > hoyIso ? edit.fecha : hoyIso;
    const esPasado = desde !== edit.fecha;
    setGuardando(true);
    const { error } = await supabase.rpc("fn_set_horario_semanal", {
      p_persona_id: edit.personaId, p_vigente_desde: desde, p_horario: semanal,
      // Motivo fijo: mismo criterio que "Hacer permanente" en Revisión de
      // Turnos (ver 0440) — es un clic desde la Vista Día, no un formulario
      // donde alguien redacta por qué.
      p_motivo: esPasado
        ? `Horario de los ${DIAS_PLURAL[Number(dow)]} cambiado desde la Vista Día, vigente desde el ${desde}: el día editado (${edit.fecha}) ya pasó y un horario nuevo no reescribe días ya juzgados.`
        : `Horario de los ${DIAS_PLURAL[Number(dow)]} cambiado desde la Vista Día, vigente desde el ${edit.fecha}.`,
    });
    // El `error` de esta segunda mitad NO se miraba, y la pantalla terminaba
    // diciendo «Horario base actualizado» con el turno puntual todavía puesto.
    // En la cascada de `jornada-esperada.ts` el turno del día le gana al
    // horario, así que ese día seguía esperando la hora vieja — y de esa hora
    // esperada salen las tardanzas y las faltas de esa persona.
    // Si el día editado ya pasó, su turno NO se retira: el horario nuevo rige
    // desde hoy, así que quitarlo dejaría esa jornada midiéndose contra el
    // horario base anterior — uno que no fue el que rigió ese día.
    const celdaHoy = error || esPasado ? null : celda(edit.personaId, edit.fecha);
    const eQuitar = celdaHoy && (celdaHoy.tipo === "turno" || celdaHoy.tipo === "descanso")
      ? (await supabase.rpc("fn_quitar_turno", { p_persona_id: edit.personaId, p_fecha: edit.fecha })).error
      : null;
    setGuardando(false);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    setEdit(null);
    await trasGuardar();
    if (eQuitar) {
      avisar("error", `El horario base de los ${DIAS_PLURAL[Number(dow)]} sí cambió, pero el turno puntual de ese día no se pudo retirar: ${mensajeDeError(eQuitar)} Mientras siga ahí, ese día manda el turno y no el horario base.`);
      return;
    }
    if (esPasado) {
      avisar("ok", `Horario base actualizado: los ${DIAS_PLURAL[Number(dow)]} desde hoy (${desde}). El ${edit.fecha} ya pasó, así que se queda como estaba — un horario nuevo no reescribe días ya juzgados. Para corregir días que ya pasaron, usa "Corregir días ya trabajados" en Horarios.`);
      return;
    }
    avisar("ok", `Horario base actualizado: los ${DIAS_PLURAL[Number(dow)]} desde esa fecha.`);
  };
  const marcarDescanso = () => edit && ejecutar(() => supabase.rpc("fn_set_descanso", { p_persona_id: edit.personaId, p_fecha: edit.fecha }));
  const quitar = () => edit && ejecutar(() => supabase.rpc("fn_quitar_turno", { p_persona_id: edit.personaId, p_fecha: edit.fecha }));

  // Al teclear solo actualiza el estado local (para que el semáforo reaccione en vivo).
  function editarMeta(dia: number, tramo: "manana" | "tarde", valor: string) {
    const meta = Math.max(0, Math.round(Number(valor) || 0));
    (tramo === "manana" ? setMetas : setMetasTarde)((m) => new Map(m).set(dia, meta));
  }
  // Guarda de verdad al salir del campo — manda mañana + tarde juntas (una sola escritura).
  async function comprometerMeta(dia: number) {
    const { error } = await supabase.rpc("fn_set_meta_cobertura", {
      p_sede_id: sedeSel, p_dia_semana: dia,
      p_meta_manana: metas.get(dia) ?? 0, p_meta_tarde: metasTarde.get(dia) ?? 0,
    });
    if (error) { avisar("error", mensajeDeError(error, "guardar la meta")); setRecarga((n) => n + 1); }
  }

  function editarMetaEncargadas(dia: number, valor: string) {
    const meta = Math.max(0, Math.round(Number(valor) || 0));
    setMetasEncargadas((m) => new Map(m).set(dia, meta));
  }
  async function comprometerMetaEncargadas(dia: number, valor: string) {
    const meta = Math.max(0, Math.round(Number(valor) || 0));
    const { error } = await supabase.rpc("fn_set_meta_encargadas", { p_sede_id: sedeSel, p_dia_semana: dia, p_meta: meta });
    if (error) { avisar("error", mensajeDeError(error, "guardar la meta de líderes")); setRecarga((n) => n + 1); }
  }

  if (rol !== null && !puedeVer) {
    return (
      <div className="flex flex-1 flex-col">
        <main className="flex flex-1 items-center justify-center p-6"><p className="max-w-md text-center text-taupe">No tienes permiso para ver los turnos.</p></main>
      </div>
    );
  }

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        <CabeceraPagina
          sobretitulo={sobretituloDeHoy("Asistencia")}
          titulo="Turnos y cobertura"
          descripcion="Arma la semana por sede: toca a una persona en un día para poner su turno o marcar descanso."
          ayuda={
            <AyudaPantalla
              titulo="Cómo funcionan los turnos y la cobertura"
              intro="Un turno puntual manda sobre el horario base de esa persona ese día, y de él depende si se le cuenta tardanza o falta."
              secciones={[
                { titulo: "Poner un turno", texto: "Toca la fila de una persona en un día: eliges su hora de entrada y salida, o la marcas de descanso." },
                { titulo: "La meta", texto: "Tiene dos tramos: mañana y tarde (el corte es 14:15). La franja de abajo de cada día compara la gente de cada hora contra la meta de su tramo." },
                { titulo: "Quién suma", texto: "La cobertura solo cuenta a las áreas operativas de sede. Quien trabaja en otra área se ve en ámbar, con su área al lado, y no suma. Quien está en preselección tampoco suma hasta que deje de estarlo: da igual si es practicante o tiene otro cargo." },
                { titulo: "Las vistas", texto: "Integrada muestra la semana hora por hora y quién está en cada hora, con el resumen de horas al pie; Día, la línea de cada persona en un día." },
                { titulo: "Piso o almacén", texto: "En Día, toca la barra de una persona para decir si ese día trabaja en piso, todo el turno en almacén o unas horas en almacén (con una sugerencia de las horas en que el piso aguanta sin ella). Se planifica de hoy en adelante. Quien está en almacén no cuenta en piso, y no cambia su turno, sus horas ni su pago." },
                { titulo: "Repetición de un día cerrado", texto: "En Día, al elegir un día que ya pasó, arriba aparece su repetición: mueve la hora o dale «Reproducir» y se ve quién estaba en piso, en almacén, en refrigerio, por llegar o ya se había ido, con lo que se marcó de verdad en el terminal. En las tiendas, además, cuántas compras hubo en esa hora y cuánta gente pedía la venta: las compras ÷ el ritmo de la tienda, nunca menos que su mínimo (los dos se cambian en Parámetros)." },
                { titulo: "Lo marcado en el terminal", texto: "En Día, la línea azul bajo la barra es lo que la persona marcó en el terminal con «Voy a almacén». Hoy, la cobertura cuenta lo que pasó hasta la hora actual (la línea roja) y el plan de ahí en adelante; si alguien marca «Vuelvo a tienda» antes de tiempo, vuelve a contar en piso desde esa hora. La Integrada muestra solo el plan." },
              ]}
            />
          }
                />

        {/* LOS CONTROLES, en una sola fila bajo la cabecera: las tres vistas a la izquierda como pestañas (son la
            misma semana vista de otra manera) y, a la derecha, sede, semana y copiar. */}
        <div className="mb-5 flex flex-wrap items-stretch justify-between gap-x-4 gap-y-1 border-b border-sand">
          <Pestanas
            etiqueta="Vistas de Turnos"
            enBarra
            pestanas={[
              { clave: "integrada", texto: "Integrada" },
              { clave: "dia", texto: "Día" },
            ]}
            activa={vista}
            alElegir={setVista}
          />
          <div className="flex flex-wrap items-center gap-2 self-center">
            {esAdmin && (
              <div className="w-44">
                {/* El nombre, no el código: quien arma turnos piensa en «Tienda LIM», no en «003». */}
                <CampoSelect tamano="sm" aria-label="Sede" value={sedeSel} onChange={(e) => setSedeSel(e.target.value)}>
                  {sedes.map((s) => <option key={s.id} value={s.id}>{s.nombre}</option>)}
                </CampoSelect>
              </div>
            )}
            <div className="flex items-center gap-1">
              <BotonIcono etiqueta="Semana anterior" icono={<ChevronLeft aria-hidden />} disabled={cargando} onClick={() => setLunes(addDays(lunes, -7))} />
              <span className="min-w-28 text-center text-xs tabular-nums text-taupe">
                {etiquetaDia(lunes).num} – {etiquetaDia(addDays(lunes, 6)).num}
              </span>
              <BotonIcono etiqueta="Semana siguiente" icono={<ChevronRight aria-hidden />} disabled={cargando} onClick={() => setLunes(addDays(lunes, 7))} />
              <Boton variante="secundario" tamano="sm" disabled={cargando} onClick={() => setLunes(lunesDeLaSemana(hoyLima()))}>Hoy</Boton>
            </div>
            {/* Solo aparece si de verdad hay algo que copiar — un botón que nunca hace nada enseña a ignorarlo. El
                número es un techo («hasta N»): fn_copiar_semana_anterior salta los días que esta semana ya tiene
                editados a mano, así que lo que se aplique de verdad puede ser menos. */}
            {puedeVer && !cargando && Boolean(copiarDisponibles) && (
              confirmarCopiar ? (
                <BannerAviso enLinea className="flex flex-wrap items-center gap-2 !py-1.5 text-xs">
                  <span>¿Copiar hasta {copiarDisponibles} turno{copiarDisponibles === 1 ? "" : "s"} de la semana pasada?</span>
                  {avisoCopiar && <span className="basis-full text-[11px] text-taupe">{avisoCopiar}</span>}
                  <Boton variante="primario" tamano="sm" disabled={copiando} cargando={copiando} onClick={() => void copiarSemanaAnterior()}>Sí, copiar</Boton>
                  <Boton variante="secundario" tamano="sm" disabled={copiando} onClick={() => setConfirmarCopiar(false)}>Cancelar</Boton>
                </BannerAviso>
              ) : (
                <Boton variante="secundario" tamano="sm" onClick={() => setConfirmarCopiar(true)}>
                  Copiar semana anterior
                </Boton>
              )
            )}
          </div>
        </div>

        {/* Quien está en preselección y queda trabajando un feriado: se recomienda descanso (prueba-en-feriado.ts).
            No frena nada; cada fila abre el editor de ese día, donde está «Dar descanso». */}
        {!cargando && pruebaEnFeriado.length > 0 && (
          <BannerAviso enLinea variante="advertencia" className="mb-4 text-sm">
            <p className="mb-1 font-medium">Alguien en preselección queda trabajando un feriado.</p>
            <p className="mb-2 text-xs">Un feriado trabajado sin día libre a cambio se paga más. Lo recomendable es darle descanso; si debe venir, confírmalo al abrir el día.</p>
            <ul className="space-y-1">
              {pruebaEnFeriado.map((x) => (
                <li key={`${x.personaId}|${x.fecha}`} className="flex flex-wrap items-center gap-2 text-xs">
                  <span>{lineaDeSemana(x, `${etiquetaDia(x.fecha).abr} ${etiquetaDia(x.fecha).num}`)}</span>
                  <Boton variante="secundario" tamano="sm" onClick={() => abrir(x.personaId, x.fecha)}>Revisar ese día</Boton>
                </li>
              ))}
            </ul>
          </BannerAviso>
        )}

        {funcionesFallo && !cargando && (
          <div className="mb-4 max-w-2xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
            No se pudo cargar el área del personal: la cobertura está contando a <strong>todos</strong> como
            operativos y puede marcar de más. <Boton variante="enlace" onClick={() => void cargar()}>Reintentar</Boton>
          </div>
        )}

        {/* PARA DECIDIR: lo que pide una decisión antes de armar la semana, en una línea. Mientras carga no se
            dice «nada pendiente»: sería tranquilizar sin haber mirado. */}
        {sedeSel && nBase !== null && nTope !== null && (
          <ParaAtender
            titulo="Para decidir"
            items={[
              {
                clave: "base",
                texto: `${nBase} turno${nBase === 1 ? "" : "s"} distinto${nBase === 1 ? "" : "s"} al horario base${nEspejos > 0 ? ` · ${nEspejos} espejo${nEspejos === 1 ? "" : "s"} viejo${nEspejos === 1 ? "" : "s"}` : ""}`,
                n: nBase,
                tono: "ambar",
              },
              { clave: "tope", texto: `${nTope} cerca o sobre las 48 h`, n: nTope, tono: topeGrave ? "rojo" : "ambar" },
            ]}
            activa={decidirAbierto}
            alTocar={(clave) => setDecidirAbierto(decidirAbierto === clave ? null : (clave as "base" | "tope"))}
          />
        )}
        {sedeSel && <AlertaSobretiempo sedeSel={sedeSel} abierto={decidirAbierto === "tope"} onConteo={conteoTope} />}
        {sedeSel && <RevisionTurnos sedeSel={sedeSel} onIrADia={irARevisar} abierto={decidirAbierto === "base"} onConteo={conteoBase} alDia={alDia} onCambio={alCambiarDesdeRevision} />}

        {cargando ? <Cargando /> : vista === "integrada" ? (
          (() => {
            // ── Vista Integrada: la semana hora por hora, con quién está en cada hora ──────────────
            // La regla (quién pasa, el peor cuarto de la hora, qué no se mide, dónde arrancan las filas)
            // vive en lib/admin/semana-con-nombres.ts con sus pruebas; aquí solo se dibuja. El dibujo es el
            // de la maqueta B elegida por Felipe (2026-11-02): casillas claras con borde de su estado, la
            // cuenta arriba y los nombres como fichas.
            const porDia = dias.map((iso) => ({ iso, turnos: turnosConNombreDe(iso) }));
            const horasSemana = horasDeLaSemana(porDia.map((d) => d.turnos));
            if (personas.length === 0) {
              return <SinDatos texto="Todavía no hay nadie asignado a esta sede." pista="Ve a Equipo, abre a una persona y elige esta sede como su sede base." />;
            }
            if (horasSemana.length === 0) {
              return <SinDatos texto="Nadie tiene turno ni horario esta semana en esta sede." pista="Abre la vista Día y toca la fila de una persona para ponerle turno. Si su horario base ya está puesto en Horarios, aparece solo." />;
            }
            // Cada casilla se calcula una vez: la usan la grilla y el resumen del pie.
            const celdas = porDia.map(({ iso, turnos: delDia }) => {
              const dia = diaSemana(iso);
              return horasSemana.map((h) => celdaConNombres({
                turnos: delDia, hora: h,
                metaEn: (x) => metaDeHora(x, metas.get(dia) ?? 0, metasTarde.get(dia) ?? 0),
                metaLideres: metasEncargadas.get(dia) ?? 0,
              }));
            });
            const resumenes = porDia.map((d, di) => resumenDelDia(celdas[di], d.turnos));
            const fmtH = (x: number) => (Math.round(x * 10) / 10).toLocaleString("es-PE");
            const cols = "4.75rem repeat(7, minmax(9.5rem, 1fr))";
            // El estado de la casilla, en fondo y borde suaves (nunca un relleno pleno) y siempre con su palabra.
            const TONO: Record<string, { fondo: string; borde: string; texto: string }> = {
              falta: { fondo: "color-mix(in srgb, var(--color-rojo) 8%, var(--color-papel))", borde: "color-mix(in srgb, var(--color-rojo) 38%, transparent)", texto: "var(--color-rojo-profundo)" },
              ok: { fondo: "color-mix(in srgb, var(--color-verde) 8%, var(--color-papel))", borde: "color-mix(in srgb, var(--color-verde) 32%, transparent)", texto: "var(--color-verde)" },
              sobra: { fondo: "color-mix(in srgb, var(--color-ambar) 8%, var(--color-papel))", borde: "color-mix(in srgb, var(--color-ambar) 36%, transparent)", texto: "var(--color-ambar)" },
              neutro: { fondo: "var(--color-hueso)", borde: "var(--color-sand)", texto: "var(--color-taupe)" },
            };
            // En la leyenda el borde va con el color pleno del estado: a 12 px, el borde suave de la casilla no se distingue.
            const muestra = (t: { fondo: string; texto: string }) => (
              <span aria-hidden className="inline-block h-3 w-3 rounded-[4px] border-[1.5px]" style={{ background: t.fondo, borderColor: t.texto }} />
            );
            return (
              <div className="space-y-3">
                <div className="flex flex-wrap items-center gap-x-5 gap-y-1.5 text-xs text-taupe">
                  <span className="flex items-center gap-1.5">{muestra(TONO.ok)}Alcanza</span>
                  <span className="flex items-center gap-1.5">{muestra(TONO.falta)}Falta gente en piso</span>
                  <span className="flex items-center gap-1.5">{muestra(TONO.sobra)}Sobra</span>
                  <span className="flex items-center gap-1.5">
                    <span aria-hidden className="inline-flex h-4 w-4 items-center justify-center rounded-full bg-tinta text-[9px] font-semibold text-crema">L</span>
                    Líder de equipo
                  </span>
                  <span className="flex items-center gap-1.5">
                    <span aria-hidden className="inline-block h-3 w-3 rounded-[4px]" style={{ outline: "1.5px dashed var(--color-ambar)", outlineOffset: "-1.5px" }} />
                    Sin líder en algún momento
                  </span>
                  <span className="flex items-center gap-1.5">
                    <span aria-hidden className="inline-block h-3 w-6 rounded-full border border-dashed border-taupe/60" />
                    No suma a la meta (preselección u otra área)
                  </span>
                  <span className="flex items-center gap-1.5">
                    <span aria-hidden className="inline-block h-3 w-6 rounded-full border"
                      style={{ background: "color-mix(in srgb, var(--color-azul) 10%, var(--color-papel))", borderColor: "color-mix(in srgb, var(--color-azul) 45%, transparent)" }} />
                    En almacén: no cuenta en piso
                  </span>
                </div>
                <p className="max-w-3xl text-xs text-taupe">
                  Arriba de cada casilla, cuántas hay en piso en el peor momento de esa hora contra la meta. «entra» y «sale» marcan a
                  quien cubre solo parte de la hora. Toca la hora para ver la línea del día, o un nombre para cambiar su turno.
                </p>
                <TarjetaInfo className="overflow-x-auto !p-3">
                  <div className="grid min-w-[1080px] gap-1.5" style={{ gridTemplateColumns: cols }}>
                    <div />
                    {dias.map((iso) => {
                      const { abr, num } = etiquetaDia(iso);
                      const hoy = iso === hoyLima();
                      return (
                        <button key={iso} type="button" onClick={() => verLineaDelDia(iso)} title={`Ver la línea de cada persona el ${abr} ${num}`}
                          className={`flex items-baseline gap-1.5 px-1 pb-1 text-left transition-colors hover:text-tinta ${hoy ? "text-tinta" : "text-taupe"}`}>
                          <span className="text-[11px] font-semibold uppercase tracking-[0.08em]">{abr}</span>
                          <span className="text-[11px] tabular-nums">{num}</span>
                          {hoy && <Insignia variante="informativo" tamano="sm" punto={false}>hoy</Insignia>}
                        </button>
                      );
                    })}

                    {horasSemana.map((h, hi) => (
                      <Fragment key={h}>
                        <div className="pr-1 pt-2 text-right">
                          <span className="block text-[13px] font-medium tabular-nums">{decimalAHHMM(h)}</span>
                          <span className="block text-[11px] tabular-nums text-taupe">a {decimalAHHMM(h + 1)}</span>
                        </div>
                        {porDia.map(({ iso, turnos: delDia }, di) => {
                          const c = celdas[di][hi];
                          if (c.fuera && c.gente.length === 0) {
                            return <div key={iso} className="rounded-xl border border-dashed border-sand" aria-hidden />;
                          }
                          const est = estiloDeHora(c.enPiso, c.meta).estado;
                          const tono = c.fuera ? TONO.neutro : TONO[est === "falta" ? "falta" : est === "ok" ? "ok" : est === "sobra" ? "sobra" : "neutro"];
                          // El color nunca va solo: la palabra dice lo mismo que el fondo.
                          const dif = c.enPiso - c.meta;
                          const palabra = c.fuera ? "fuera de horario" : c.meta === 0 ? "sin meta" : dif < 0 ? `falta ${-dif}` : dif > 0 ? `sobra ${dif}` : "completo";
                          const { abr } = etiquetaDia(iso);
                          return (
                            <div key={iso} className="flex flex-col gap-1.5 rounded-xl border p-2"
                              style={{
                                background: tono.fondo,
                                borderColor: tono.borde,
                                outline: c.sinLider ? "1.5px dashed var(--color-ambar)" : "none",
                                outlineOffset: c.sinLider ? "-1.5px" : undefined,
                              }}>
                              <button type="button" onClick={() => verLineaDelDia(iso)}
                                title={`${abr} ${decimalAHHMM(h)}–${decimalAHHMM(h + 1)}: ${c.enPiso} operativa${c.enPiso === 1 ? "" : "s"} en el peor momento${c.meta > 0 ? `, meta ${c.meta}` : ""}${c.lideres > 0 ? ` · ${c.lideres} ${c.lideres === 1 ? "líder" : "líderes"}` : c.sinLider ? " · sin líder" : ""}. Ver la línea del día.`}
                                className="flex flex-wrap items-center justify-between gap-x-2 gap-y-1 text-left">
                                <span className="whitespace-nowrap text-[13.5px] font-semibold tabular-nums">{c.fuera ? "—" : `${c.enPiso} en piso`}</span>
                                <span className="whitespace-nowrap rounded-full bg-papel/80 px-1.5 text-[10.5px] font-semibold tabular-nums" style={{ color: tono.texto }}>
                                  {palabra}{c.meta > 0 && !c.fuera ? ` · meta ${c.meta}` : ""}
                                </span>
                              </button>
                              {(() => {
                                // Quien pasa TODA su presencia de esta hora en almacén va aparte y no suma al piso;
                                // quien pasa solo una parte sigue en piso, con su tramo de almacén al lado.
                                const ficha = (g: (typeof c.gente)[number]) => {
                                  const tt = delDia.find((x) => x.id === g.id);
                                  const turno = tt ? `${decimalAHHMM(tt.entrada)}–${decimalAHHMM(tt.salida)} · ${fmtH(tt.salida - tt.entrada)} h en tienda ese día` : "";
                                  const alm = g.almacen.map((x) => `${decimalAHHMM(x.desde)}–${decimalAHHMM(x.hasta)}`).join(", ");
                                  return (
                                    <li key={g.id}>
                                      <button type="button" disabled={!puedeVer} onClick={() => abrir(g.id, iso)}
                                        title={`${g.nombre}${turno ? ` · ${turno}` : ""}${alm ? ` · en almacén ${alm}` : ""}${g.aparte ? ` · ${g.aparte}: no suma a la meta` : ""}${puedeVer ? ". Toca para cambiar su turno o su puesto." : ""}`}
                                        className={`flex w-full items-center gap-1.5 rounded-full border bg-papel px-1.5 py-0.5 text-left text-[12.5px] transition-colors enabled:hover:border-taupe disabled:cursor-default ${g.cuenta || g.lider ? "border-sand" : "border-dashed border-taupe/60 text-taupe"}`}
                                        style={g.soloAlmacen ? { background: "color-mix(in srgb, var(--color-azul) 10%, var(--color-papel))", borderColor: "color-mix(in srgb, var(--color-azul) 45%, transparent)" } : undefined}>
                                        {g.lider ? (
                                          <span aria-label="Líder de equipo" className="inline-flex h-4 w-4 shrink-0 items-center justify-center rounded-full bg-tinta text-[9px] font-semibold text-crema">L</span>
                                        ) : (
                                          <span aria-hidden className="w-1" />
                                        )}
                                        <span className="min-w-0 truncate">{g.nombre}</span>
                                        {g.aparte && <span className="ml-auto max-w-[6.5rem] shrink-0 truncate text-[10px]">{g.aparte}</span>}
                                        {!g.soloAlmacen && alm && <span className="ml-auto shrink-0 text-[10.5px] tabular-nums text-azul">alm. {alm}</span>}
                                        {g.entra !== null && <span className="ml-auto shrink-0 text-[10.5px] tabular-nums text-verde">entra {decimalAHHMM(g.entra)}</span>}
                                        {g.sale !== null && <span className="ml-auto shrink-0 text-[10.5px] tabular-nums text-rojo-profundo">sale {decimalAHHMM(g.sale)}</span>}
                                      </button>
                                    </li>
                                  );
                                };
                                const enAlmacen = c.gente.filter((g) => g.soloAlmacen);
                                return (
                                  <>
                                    <ul className="flex flex-col gap-1">{c.gente.filter((g) => !g.soloAlmacen).map(ficha)}</ul>
                                    {enAlmacen.length > 0 && (
                                      <>
                                        <span className="mt-0.5 text-[10px] font-semibold uppercase tracking-[0.08em] text-azul">En almacén</span>
                                        <ul className="flex flex-col gap-1">{enAlmacen.map(ficha)}</ul>
                                      </>
                                    )}
                                  </>
                                );
                              })()}
                            </div>
                          );
                        })}
                      </Fragment>
                    ))}

                    {/* El resumen del pie: compacto, alineado con cada día y plegable. */}
                    <div className="col-span-full mt-1 border-t border-sand pt-2">
                      <button type="button" onClick={() => setResumenAbierto(!resumenAbierto)} aria-expanded={resumenAbierto}
                        className="flex items-center gap-1.5 text-xs font-medium text-taupe transition-colors hover:text-tinta">
                        <ChevronRight aria-hidden className={`h-3.5 w-3.5 transition-transform ${resumenAbierto ? "rotate-90" : ""}`} />
                        Resumen de horas
                        <span className="font-normal tabular-nums">· {fmtH(resumenes.reduce((a, r) => a + r.horasEnTienda, 0))} h en tienda la semana</span>
                      </button>
                    </div>
                    {resumenAbierto && (
                      <>
                        <div className="pr-1 text-right text-[11px] leading-5 text-taupe">
                          h en tienda<br />personas<br />prom. en piso<br />con falta
                        </div>
                        {resumenes.map((r, di) => (
                          <div key={dias[di]} className="rounded-xl bg-hueso px-2 py-1 text-[12px] leading-5 tabular-nums">
                            <span className="font-semibold">{fmtH(r.horasEnTienda)} h</span><br />
                            {r.personas}<br />
                            {r.promedioEnPiso === null ? "—" : fmtH(r.promedioEnPiso)}<br />
                            <span className={r.horasConFalta > 0 ? "text-rojo-profundo" : "text-taupe"}>
                              {r.horasConFalta > 0 ? `${r.horasConFalta} hora${r.horasConFalta === 1 ? "" : "s"}` : "ninguna"}
                            </span>
                          </div>
                        ))}
                        <p className="col-span-full max-w-4xl pt-1 text-[11px] text-taupe">
                          <strong>h en tienda</strong>: de la entrada a la salida de cada persona, sumadas, con el refrigerio adentro (no es lo que
                          se paga: eso lo descuenta la planilla). <strong>Personas</strong>: cuántas tienen turno ese día.{" "}
                          <strong>Prom. en piso</strong>: el promedio de operativas en el peor momento de cada hora, sobre las horas que se miden.{" "}
                          <strong>Con falta</strong>: horas por debajo de su meta. Pasa el mouse sobre un nombre para ver sus horas de ese día.
                        </p>
                      </>
                    )}
                  </div>
                </TarjetaInfo>
              </div>
            );
          })()
        ) : (
          <div className="space-y-4">
            {personas.length === 0 ? (
              <SinDatos texto="Todavía no hay nadie asignado a esta sede." pista="Ve a Equipo, abre a una persona y elige esta sede como su sede base." />
            ) : (
              (() => {
                // ── Vista Día: «mañana y tarde» de UN día; la hora por hora y las metas, debajo, a pedido ──
                const iso = diaActivo;
                const dia = diaSemana(iso);
                const t = tramosDelDia(iso);
                const sinTurnos = sedeSinTurnosEn(iso);
                const sug = sugerenciaDe(iso);
                const trabajan = personas.filter((p) => { const c = celda(p.id, iso); return c.tipo === "turno" || c.tipo === "default"; });
                const deLaMeta = (ids: Set<string>) => trabajan.filter((p) => ids.has(p.id));
                const opsTrabajan = trabajan.filter(esOperativa);
                const abrirChip = puedeVer ? (id: string) => abrir(id, iso) : undefined;
                const campoMeta = (tramo: "manana" | "tarde") => esAdmin ? (
                  <CampoMeta
                    valor={tramo === "manana" ? (metas.get(dia) ?? 0) : (metasTarde.get(dia) ?? 0)}
                    etiqueta={`Meta de la ${tramo === "manana" ? "mañana" : "tarde"}`}
                    titulo={`meta de la ${tramo === "manana" ? "mañana" : "tarde"} de todos los ${DIAS_PLURAL[dia]}`}
                    cuando={`todos los ${DIAS_PLURAL[dia]}`}
                    onCambio={(v) => editarMeta(dia, tramo, v)}
                    onSalir={() => comprometerMeta(dia)}
                  />
                ) : undefined;
                const lideresChips = t.lideres.n > 0 ? deLaMeta(t.idsLideres).map((p) => personaDelDia(p, iso)) : [];
                const libres = personas.filter((p) => { const c = celda(p.id, iso); return c.tipo === "descanso" || c.tipo === "libre"; }).map((p) => personaDelDia(p, iso));
                const otrasAreas = opsTrabajan.length + deLaMeta(t.idsLideres).length < trabajan.length
                  ? trabajan.filter((p) => !esOperativa(p) && !esEncargada(p)).map((p) => personaDelDia(p, iso))
                  : [];
                return (
                  <>
                    <div role="group" aria-label="Día de la semana" className="flex flex-wrap gap-1.5">
                      {dias.map((d) => {
                        const { abr, num } = etiquetaDia(d);
                        const sim = simboloDelDia(d);
                        return (
                          <Filtro key={d} activo={d === iso} onClick={() => setDiaSel(d)} title={`${abr} ${num} · ${sim.t}${d === hoyLima() ? " · hoy" : ""}`}>
                            {abr} <span className="text-[0.85em] opacity-70">{num}</span> <span aria-hidden className="ml-0.5">{sim.s}</span>
                            <span className="sr-only"> {sim.t}</span>
                          </Filtro>
                        );
                      })}
                    </div>

                    {/* LA REPETICIÓN de un día que ya cerró (2026-11-03): lo marcado de verdad, hora por hora, contra la
                        venta. Solo con lo marcado leído; un día que todavía no termina no se repite. */}
                    {iso < hoyLima() && reales && (() => {
                      const medianocheIso = rangoDelDiaLima(iso).inicio;
                      const personasRep: PersonaRepeticion[] = personas.flatMap((p) => {
                        const c = celda(p.id, iso);
                        const marcajesDia = reales.marcajes.get(`${p.id}|${iso}`) ?? [];
                        const trabaja = c.tipo === "turno" || c.tipo === "default";
                        if (!trabaja && marcajesDia.length === 0) return [];
                        const plan = trabaja ? { desde: horaADecimal(c.entrada), hasta: c.salida ? horaADecimal(c.salida) : HORA_FIN } : null;
                        return [{
                          id: p.id,
                          nombre: `${p.nombres.split(" ")[0]}${p.apellidos ? ` ${p.apellidos[0]}.` : ""}`,
                          cuenta: esOperativa(p), lider: esEncargada(p),
                          marcajes: marcajesDia,
                          almacen: plan ? almacenDe(p.id, iso, plan, true) : marcadoDe(p.id, iso, { desde: 0, hasta: 24 }),
                          plan,
                        }];
                      });
                      if (personasRep.length === 0) return null;
                      const delDia = compras?.get(iso);
                      return (
                        <RepeticionDelDia
                          key={iso}
                          personas={personasRep}
                          medianocheIso={medianocheIso}
                          esTienda={tipoSedeSel === "tienda"}
                          comprasFallo={tipoSedeSel === "tienda" && compras === null}
                          comprasDe={tipoSedeSel === "tienda" && compras !== null ? (h) => delDia?.get(h) ?? 0 : null}
                          parametros={coberturaVenta}
                        />
                      );
                    })()}

                    {/* LA LÍNEA DEL DÍA, arriba y siempre a la vista (antes vivía plegada en «Ver hora por hora»):
                        una barra por persona, con su tramo de almacén en azul, y abajo cuántas quedan en piso. */}
                    <div className="overflow-x-auto">
                        <div className="min-w-[700px] space-y-4">
                          {[iso].map((iso) => {
                const { abr, num } = etiquetaDia(iso);
                const hoy = iso === hoyLima();
                const dia = diaSemana(iso);
                const metaMan = metas.get(dia) ?? 0;
                const metaTar = metasTarde.get(dia) ?? 0;
                const metaEnc = metasEncargadas.get(dia) ?? 0;
                const horas = coberturaPorHora(iso);
                const covFr = coberturaPorFranja(iso, HORA_INICIO_SEMANA, N_FRANJAS_SEMANA, 0.5, esOperativa);
                const covFrEnc = coberturaPorFranja(iso, HORA_INICIO_SEMANA, N_FRANJAS_SEMANA, 0.5, esEncargada);
                const r = resumenOperativas(covFr, metaMan, metaTar, HORA_INICIO_SEMANA, 0.5);
                const rEnc = resumenEncargadas(covFrEnc, metaEnc);
                // Un día en que la sede no se labora (a nadie le toca y las tres metas son 0)
                // dice UNA vez «Sin turnos», en el lugar de la frase de operativas, y la de
                // líderes no se dibuja: dos frases de grupo sonaban a falla un domingo de Central.
                const sinTurnosSede = sedeSinTurnosEn(iso);
                const etOp = sinTurnosSede ?? etiquetaCobertura({ quien: "operativas", hayGente: r.hayGente, sinMeta: r.sinMeta, hayMeta: Math.max(metaMan, metaTar) > 0, pct: r.pct });
                const etEnc = etiquetaCobertura({ quien: "lideres", hayGente: rEnc.hayGente, sinMeta: rEnc.sinMeta, hayMeta: metaEnc > 0, pct: rEnc.pct });
                // ¿Alguien de un área operativa trabaja este día? Si nadie, la franja de
                // cobertura de abajo no tiene nada que contar y lo dice con palabras.
                const sinOperativasHoy = horas.every((n) => n === 0);
                // Hoy se marca con una línea la hora actual: a su izquierda la cobertura cuenta lo marcado en el
                // terminal; a su derecha, el plan.
                const ahoraEnLinea = hoy ? pctEnRango(horaADecimal(horaLima())) : null;
                const lineaAhora = ahoraEnLinea === null ? null : (
                  <span aria-hidden className="pointer-events-none absolute inset-y-0 z-20 w-px bg-rojo/70" style={{ left: `${ahoraEnLinea}%` }} />
                );
                return (
                  <section key={iso} id={`turnos-dia-${iso}`} className={`overflow-hidden rounded-2xl border bg-papel ${hoy ? "border-tinta" : "border-sand"}`}>
                    {/* Cabecera del día: fecha + resumen (las metas se editan en las tarjetas de arriba) */}
                    <div className="flex flex-wrap items-center justify-between gap-3 bg-sand/50 px-4 py-2">
                      <div className={hoy ? "text-tinta" : ""}>
                        <span className="font-serif text-lg">{abr}</span>{" "}
                        <span className="text-sm text-taupe">{num}</span>
                      </div>
                      {/* Las metas se editan arriba, en las tarjetas «Mañana», «Tarde» y «Líderes»: acá solo se lee el resumen. */}
                      <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs">
                        <span className="text-taupe">Meta operativas {metaMan}/{metaTar} <span className="opacity-70">mañana / tarde</span></span>
                        <span className="font-medium" style={{ color: colorDeTono(etOp.tono, r.pct) }}>
                          {etOp.texto}
                          {r.supHoras > 0 && <span className="text-ambar"> · sobra {r.supHoras}h</span>}
                        </span>
                        <span className="border-l border-sand pl-3 text-taupe">Líderes {metaEnc || "—"}</span>
                        {!sinTurnosSede && (
                          <span className="font-medium" style={{ color: colorDeTono(etEnc.tono, rEnc.pct) }}>
                            {etEnc.texto}
                          </span>
                        )}
                      </div>
                    </div>
                    {/* Eje de horas */}
                    <div className="relative ml-[176px] h-4 border-b border-sand/60 text-[10px] text-taupe">
                      {MARCAS_HORA.map((h) => (
                        <span key={h} className="absolute -translate-x-1/2" style={{ left: `${pctEnRango(h)}%` }}>{h}h</span>
                      ))}
                    </div>

                    {/* Una fila por persona: barra = su rango de turno ese día */}
                    {personas.map((p) => {
                      const c = celda(p.id, iso);
                      const operativa = esOperativa(p);
                      const trabajaEseDia = c.tipo === "turno" || c.tipo === "default";
                      // La barra de quien trabaja abre «¿Dónde trabaja ese día?» (de hoy en adelante: 0579); la de quien
                      // descansa o no tiene turno abre su turno, igual que su nombre.
                      const barraAlmacen = puedeVer && trabajaEseDia && iso >= hoyLima();
                      const turnoDec = trabajaEseDia ? { desde: horaADecimal(c.entrada), hasta: c.salida ? horaADecimal(c.salida) : HORA_FIN } : null;
                      const almacenDeHoy = turnoDec ? tramosEnAlmacen(puestoDe(p.id, iso), turnoDec) : [];
                      // Lo marcado en el terminal (0580): solo de hoy hacia atrás, y aunque ese día no tuviera turno.
                      const marcadoHoy = iso <= hoyLima() ? marcadoDe(p.id, iso, turnoDec ?? { desde: 0, hasta: 24 }) : [];
                      return (
                        <div key={p.id} className="flex w-full items-center border-t border-sand/60 transition-colors hover:bg-sand/20">
                          {/* Sin `truncate`: con el nombre y el área más largos que la
                              columna, el recorte se comía justo la etiqueta del área y
                              quedaba «…» —con la barra en ámbar y ninguna explicación de
                              por qué—. Ahora la etiqueta baja de renglón. */}
                          <button type="button" onClick={() => abrir(p.id, iso)} title={`Cambiar el turno de ${p.nombres}`}
                            className="flex w-[176px] shrink-0 flex-wrap items-center gap-x-1.5 gap-y-0.5 px-3 py-2 text-left text-xs">
                            <span>{p.nombres} {p.apellidos}</span>
                            {!operativa && (
                              <Insignia variante="advertencia" tamano="sm">{areaCorto(areas, p.funcion)}</Insignia>
                            )}
                          </button>
                          <button type="button" onClick={() => (barraAlmacen ? abrirAlmacen(p.id, iso) : abrir(p.id, iso))}
                            title={barraAlmacen ? `¿Piso o almacén? Toca para elegir dónde trabaja ${p.nombres} ese día` : `Cambiar el turno de ${p.nombres}`}
                            className="relative h-7 flex-1 text-left">
                            {(c.tipo === "turno" || c.tipo === "default") && (() => {
                              const left = pctEnRango(horaADecimal(c.entrada));
                              const right = pctEnRango(c.salida ? horaADecimal(c.salida) : HORA_FIN);
                              const claseColor = `${operativa ? "bg-verde" : "bg-ambar"} ${c.tipo === "default" ? "opacity-50" : ""}`;
                              const tituloBase = `${c.entrada}${c.salida ? `–${c.salida}` : ""}`;
                              // Hueco de refrigerio: no sabemos la hora exacta en que empieza (el
                              // sistema solo guarda cuántos minutos dura), así que se dibuja
                              // aproximado, centrado a la mitad del turno — no es literal.
                              if (c.refrigerio && c.refrigerio > 0) {
                                const durHoras = c.refrigerio / 60;
                                const salidaDec = c.salida ? horaADecimal(c.salida) : HORA_FIN;
                                const centro = (horaADecimal(c.entrada) + salidaDec) / 2;
                                const huecoIni = pctEnRango(centro - durHoras / 2);
                                const huecoFin = pctEnRango(centro + durHoras / 2);
                                return (
                                  <>
                                    <span className={`absolute top-1.5 h-4 rounded-l ${claseColor}`}
                                      style={{ left: `${left}%`, width: `${Math.max(0.5, huecoIni - left)}%` }}
                                      title={`${tituloBase} (refrigerio ~${c.refrigerio}min hacia la mitad)`} />
                                    <span className={`absolute top-1.5 h-4 rounded-r ${claseColor}`}
                                      style={{ left: `${huecoFin}%`, width: `${Math.max(0.5, right - huecoFin)}%` }}
                                      title={`${tituloBase} (refrigerio ~${c.refrigerio}min hacia la mitad)`} />
                                  </>
                                );
                              }
                              return (
                                <span className={`absolute top-1.5 h-4 rounded ${claseColor}`}
                                  style={{ left: `${left}%`, width: `${Math.max(1, right - left)}%` }}
                                  title={tituloBase} />
                              );
                            })()}
                            {/* El almacén planificado, encima de su barra: no cuenta en piso. */}
                            {almacenDeHoy.map((a) => (
                              <span key={a.desde} className="absolute top-1 z-10 flex h-5 items-center overflow-hidden rounded bg-azul px-1 text-[9.5px] font-semibold text-crema"
                                style={{ left: `${pctEnRango(a.desde)}%`, width: `${Math.max(1, pctEnRango(a.hasta) - pctEnRango(a.desde))}%` }}
                                title={`Almacén ${decimalAHHMM(a.desde)}–${decimalAHHMM(a.hasta)}`}>
                                alm.
                              </span>
                            ))}
                            {/* Lo marcado en el terminal, debajo de la barra: lo que pasó de verdad, aparte de lo planificado. */}
                            {marcadoHoy.map((a) => (
                              <span key={`m${a.desde}`} className="absolute bottom-0 z-10 h-[3px] rounded-full bg-azul"
                                style={{ left: `${pctEnRango(a.desde)}%`, width: `${Math.max(0.5, pctEnRango(a.hasta) - pctEnRango(a.desde))}%` }}
                                title={`Marcó almacén en el terminal: ${decimalAHHMM(a.desde)}–${decimalAHHMM(a.hasta)}`} />
                            ))}
                            {lineaAhora}
                            {c.tipo === "descanso" && <span className="absolute left-2 top-1.5 rounded bg-sand px-1.5 py-0.5 text-[10px] text-taupe">descanso</span>}
                            {c.tipo === "libre" && <span className="absolute left-2 top-1.5 text-[10px] text-taupe">+</span>}
                          </button>
                        </div>
                      );
                    })}

                    {/* Cobertura por hora: un bloque por hora, con el color de su estado (verde = cubierto, rojo = falta,
                        ámbar = sobra, gris = sin meta) y el número exacto adentro. Antes era un degradado continuo
                        que a media meta se volvía café y no decía ni «falta» ni «cubierto». */}
                    <div className="flex items-stretch border-t-2 border-sand">
                      <span className="w-[176px] shrink-0 px-3 py-2 text-xs text-taupe">Cobertura</span>
                      <div className="relative flex h-8 flex-1 gap-px overflow-hidden">
                        {(() => {
                          // La misma regla que la Integrada (semana-con-nombres.ts): el peor cuarto de cada hora,
                          // sin quien está en almacén, y sin medir lo que queda fuera de la primera entrada y la
                          // última salida del día. Así Día e Integrada dan el mismo número para la misma hora.
                          // Con lo real (decisión de Felipe, 2026-11-03): lo marcado en el terminal hasta ahora y el plan
                          // después. La Integrada sigue con el plan solo.
                          const delDia = turnosConNombreDe(iso, true);
                          return horas.map((_, i) => {
                            const cel = celdaConNombres({
                              turnos: delDia, hora: HORA_INICIO + i,
                              metaEn: (x) => metaDeHora(x, metaMan, metaTar), metaLideres: metaEnc,
                            });
                            const n = cel.fuera ? 0 : cel.enPiso;
                            const e = estiloDeHora(n, cel.fuera ? 0 : cel.meta);
                            const enAlm = cel.gente.filter((g) => g.almacen.length > 0).length;
                            return (
                              <span
                                key={i}
                                className="flex flex-1 items-center justify-center text-[11px] font-medium tabular-nums"
                                style={{ background: e.fondo, color: e.texto }}
                                title={`${HORA_INICIO + i}h–${HORA_INICIO + i + 1}h: ${n} en piso en el peor momento${cel.meta > 0 ? ` (meta ${cel.meta})` : ""}${enAlm ? ` · ${enAlm} en almacén parte o toda la hora` : ""}`}
                              >
                                {cel.fuera ? "" : n}
                              </span>
                            );
                          });
                        })()}
                        {/* Si nadie de un área operativa trabaja ese día, la franja no
                            tiene nada que contar: se dice, en vez de dejar un bloque
                            que parezca «todo cubierto». */}
                        {lineaAhora}
                        {sinOperativasHoy && (
                          <span className="absolute inset-0 flex items-center bg-papel/80 px-3 text-[11px] text-taupe">
                            Nadie de un área operativa trabaja este día: aquí no hay cobertura que medir.
                          </span>
                        )}
                      </div>
                    </div>
                  </section>
                );
              })}
                        </div>
                      </div>
                    {sinTurnos ? (
                      <TarjetaInfo>
                        <p className="text-sm text-taupe"><strong>{sinTurnos.texto}.</strong> A nadie de la sede le toca este día.</p>
                      </TarjetaInfo>
                    ) : (
                      <>
                        <div className="grid gap-4 lg:grid-cols-2">
                          <TarjetaTramo titulo="Mañana" subtitulo="hasta las 14:15" {...t.manana} gente={t.manana.gente.map((g) => personaDelDia(nombrePersona(g.id)!, iso))} metaEditable={campoMeta("manana")} onAbrir={abrirChip} />
                          <TarjetaTramo titulo="Tarde" subtitulo="desde las 14:15" {...t.tarde} gente={t.tarde.gente.map((g) => personaDelDia(nombrePersona(g.id)!, iso))} metaEditable={campoMeta("tarde")} onAbrir={abrirChip} />
                        </div>
                        <TarjetaTramo
                          titulo="Líderes" subtitulo="meta plana, todo el día" {...t.lideres} gente={lideresChips} onAbrir={abrirChip}
                          metaEditable={esAdmin ? (
                            <CampoMeta
                              valor={metasEncargadas.get(dia) ?? 0}
                              etiqueta="Meta de líderes"
                              titulo={`meta de líderes de todos los ${DIAS_PLURAL[dia]}`}
                              cuando={`todos los ${DIAS_PLURAL[dia]}`}
                              onCambio={(v) => editarMetaEncargadas(dia, v)}
                              onSalir={(v) => comprometerMetaEncargadas(dia, v)}
                            />
                          ) : undefined}
                        />
                        {sug && (
                          <p className="text-sm" style={{ color: sug.startsWith("↔") ? "var(--color-ambar)" : "var(--color-rojo)" }}>{sug}</p>
                        )}
                        <div className="grid gap-4 lg:grid-cols-2">
                          <TarjetaGrupo titulo="Sin turno ese día" nota={puedeVer ? "toca a alguien para ponerle turno" : undefined} gente={libres} onAbrir={abrirChip} vacio="Todos tienen turno." />
                          <TarjetaGrupo titulo="Otras áreas" nota="no suman a la meta" gente={otrasAreas} onAbrir={abrirChip} />
                        </div>
                      </>
                    )}

                  </>
                );
              })()
            )}
          </div>
        )}

        {vista === "dia" && !cargando && (
          <p className="mt-3 text-xs text-taupe">
            Cada barra es el rango de entrada–salida del turno de esa persona ese día (más clarita = horario por
            defecto del periodo, no se fijó turno puntual). En <strong className="text-azul">azul con «alm.»</strong>, el almacén
            planificado: toca la barra para elegir piso o almacén, y el nombre para cambiar su turno. La{" "}
            <strong className="text-azul">línea azul de abajo</strong> es lo que marcaron en el terminal con «Voy a almacén».
            La fila de abajo cuenta, en el peor momento de cada hora, a las <strong>áreas operativas de sede</strong> que
            están en piso ({areas.filter((a) => a.operativa && a.activa).map((a) => a.nombre).join(", ")}). Hoy, a la izquierda
            de la <strong className="text-rojo">línea roja</strong> (la hora actual) cuenta lo que pasó de verdad —el plan,
            salvo que alguien marcara «Vuelvo a tienda»— y a la derecha, el plan. Por eso puede no coincidir con la
            Integrada, que muestra solo el plan. El área se cambia en Equipo.
          </p>
        )}

        {/* «¿Dónde trabaja ese día?»: piso, todo el turno en almacén o tramos (0579). */}
        {almacenEdit && (() => {
          const { personaId, fecha } = almacenEdit;
          const p = personas.find((x) => x.id === personaId);
          const c = celda(personaId, fecha);
          if (!p || (c.tipo !== "turno" && c.tipo !== "default")) return null;
          const turno: TramoDecimal = { desde: horaADecimal(c.entrada), hasta: c.salida ? horaADecimal(c.salida) : HORA_FIN };
          const { abr, num } = etiquetaDia(fecha);
          const dia = diaSemana(fecha);
          const metaEn = (x: number) => metaDeHora(x, metas.get(dia) ?? 0, metasTarde.get(dia) ?? 0);
          const delDia = turnosConNombreDe(fecha);
          const otras = delDia.filter((x) => x.id !== personaId);
          const enAlm = (x: TurnoConNombre, h: number) => (x.almacen ?? []).some((a) => a.desde <= h && h < a.hasta);
          const enPisoSinElla = (h: number) => otras.filter((x) => x.cuenta && x.entrada <= h && h < x.salida && !enAlm(x, h)).length;
          const sugerido = sugerirTramo({ turno, enPisoSinElla, metaEn });
          const modo: "piso" | "todo" | "tramos" = almacenSel.todoElTurno ? "todo" : almacenSel.tramos.length > 0 ? "tramos" : "piso";
          const problema = modo === "tramos" ? problemaDeTramos(almacenSel.tramos, turno) : null;
          // Cómo queda el piso con este plan: el peor momento de su turno, con la misma cuenta de la Integrada.
          const yo = delDia.find((x) => x.id === personaId);
          const conPlan = yo ? [...otras, { ...yo, almacen: tramosEnAlmacen(almacenSel, turno) }] : otras;
          let peor: { hora: number; n: number; meta: number } | null = null;
          for (let h = Math.floor(turno.desde); h < Math.ceil(turno.hasta); h++) {
            const cel = celdaConNombres({ turnos: conPlan, hora: h, metaEn, metaLideres: 0 });
            if (cel.fuera || cel.meta === 0) continue;
            if (!peor || cel.enPiso - cel.meta < peor.n - peor.meta) peor = { hora: h, n: cel.enPiso, meta: cel.meta };
          }
          const cambiarTramo = (i: number, campo: "desde" | "hasta", valor: string) => {
            if (!valor) return;
            const [hh, mm] = valor.split(":").map(Number);
            const tramos = almacenSel.tramos.map((t, k) => (k === i ? { ...t, [campo]: (hh ?? 0) + (mm ?? 0) / 60 } : t));
            setAlmacenSel({ todoElTurno: false, tramos });
          };
          const agregarTramo = () => {
            const ultimo = almacenSel.tramos[almacenSel.tramos.length - 1];
            const base = ultimo ? { desde: ultimo.hasta, hasta: Math.min(turno.hasta, ultimo.hasta + 1) } : (sugerido ?? { desde: turno.desde, hasta: Math.min(turno.hasta, turno.desde + 2) });
            setAlmacenSel({ todoElTurno: false, tramos: [...almacenSel.tramos, base] });
          };
          return (
            <Modal abierto onCerrar={() => setAlmacenEdit(null)} bloqueado={guardandoAlmacen} ancho="sm"
              titulo={`¿Dónde trabaja ${p.nombres} el ${abr} ${num}?`}>
              <div className="space-y-4">
                <p className="text-sm text-taupe">
                  Su turno es de {decimalAHHMM(turno.desde)} a {decimalAHHMM(turno.hasta)}. Esto no cambia su turno, sus horas ni su pago:
                  solo dice si está en piso o en almacén. Lo ve en «Mis turnos».
                </p>
                {puestos === null && (
                  <BannerAviso variante="advertencia" className="text-sm">
                    No se pudo leer el plan de almacén. Si la migración 0579 todavía no está pegada, aún no se puede guardar.
                  </BannerAviso>
                )}
                <div role="group" aria-label="Dónde trabaja" className="flex flex-wrap gap-2">
                  <Filtro activo={modo === "piso"} onClick={() => setAlmacenSel(PISO)}>En piso</Filtro>
                  <Filtro activo={modo === "todo"} onClick={() => setAlmacenSel({ todoElTurno: true, tramos: [] })}>Todo el turno en almacén</Filtro>
                  <Filtro activo={modo === "tramos"} onClick={() => setAlmacenSel({ todoElTurno: false, tramos: almacenSel.tramos.length ? almacenSel.tramos : sugerido ? [sugerido] : [{ desde: turno.desde, hasta: Math.min(turno.hasta, turno.desde + 2) }] })}>
                    Unas horas en almacén
                  </Filtro>
                </div>
                {modo === "tramos" && (
                  <div className="space-y-2">
                    {almacenSel.tramos.map((t, i) => (
                      <div key={i} className="flex flex-wrap items-end gap-2">
                        <Campo etiqueta={i === 0 ? "Va al almacén" : undefined} type="time" step={900} value={aHHMM(t.desde)} onChange={(e) => cambiarTramo(i, "desde", e.target.value)} aria-label={`Tramo ${i + 1}: va al almacén`} />
                        <Campo etiqueta={i === 0 ? "Vuelve a piso" : undefined} type="time" step={900} value={aHHMM(t.hasta)} onChange={(e) => cambiarTramo(i, "hasta", e.target.value)} aria-label={`Tramo ${i + 1}: vuelve a piso`} />
                        <Boton variante="enlace" onClick={() => setAlmacenSel({ todoElTurno: false, tramos: almacenSel.tramos.filter((_, k) => k !== i) })}>Quitar</Boton>
                      </div>
                    ))}
                    <div className="flex flex-wrap items-center gap-3">
                      <Boton variante="secundario" tamano="sm" onClick={agregarTramo}>Agregar otro tramo</Boton>
                      {sugerido && !almacenSel.tramos.some((t) => t.desde === sugerido.desde && t.hasta === sugerido.hasta) && (
                        <Boton variante="enlace" onClick={() => setAlmacenSel({ todoElTurno: false, tramos: [sugerido] })}>
                          Usar el sugerido: {decimalAHHMM(sugerido.desde)}–{decimalAHHMM(sugerido.hasta)}
                        </Boton>
                      )}
                    </div>
                    <p className="text-xs text-taupe">
                      {sugerido
                        ? `Sugerido: de ${decimalAHHMM(sugerido.desde)} a ${decimalAHHMM(sugerido.hasta)}, las dos horas de su turno en que el piso queda más holgado sin ella.`
                        : "Ninguna franja de dos horas de su turno deja el piso con su meta sin ella: si va igual, el piso queda corto."}
                    </p>
                    {problema && <p role="alert" className="text-sm text-rojo-profundo">{problema}</p>}
                  </div>
                )}
                {!esPiso(almacenSel) && peor && (
                  peor.n < peor.meta ? (
                    <BannerAviso variante="advertencia" className="text-sm">
                      El piso queda corto: a las {String(peor.hora).padStart(2, "0")}:00 quedan {peor.n} en piso y la meta es {peor.meta}.
                    </BannerAviso>
                  ) : (
                    <p className="text-sm text-taupe">
                      En el peor momento de su turno quedan {peor.n} en piso (meta {peor.meta}), a las {String(peor.hora).padStart(2, "0")}:00.
                    </p>
                  )
                )}
                <div className="flex justify-end gap-2">
                  <Boton variante="secundario" disabled={guardandoAlmacen} onClick={() => setAlmacenEdit(null)}>Cancelar</Boton>
                  <Boton variante="primario" disabled={guardandoAlmacen || puestos === null || Boolean(problema)} cargando={guardandoAlmacen}
                    onClick={() => void guardarAlmacen()}>
                    Guardar
                  </Boton>
                </div>
              </div>
            </Modal>
          );
        })()}

        {edit && (() => {
          const p = personas.find((x) => x.id === edit.personaId);
          const { abr, num } = etiquetaDia(edit.fecha);
          const propio = yo && edit.personaId === yo.id && !esAdmin;

          // Aviso no bloqueante: descanso mínimo entre jornadas (con los días
          // vecinos que ya están en pantalla, sin fetch nuevo) y ciclo de 48h
          // (cicloEdit, traído al abrir el modal). Nunca deshabilita Guardar —
          // la decisión sigue siendo de quien conoce a la persona y el día.
          const cAntes = celda(edit.personaId, addDays(edit.fecha, -1));
          const cDespues = celda(edit.personaId, addDays(edit.fecha, 1));
          const entradaDec = entrada ? horaADecimal(entrada) : null;
          const salidaDec = salida ? horaADecimal(salida) : null;
          const salidaAntes = (cAntes.tipo === "turno" || cAntes.tipo === "default") && cAntes.salida ? horaADecimal(cAntes.salida) : null;
          const entradaDespues = cDespues.tipo === "turno" || cDespues.tipo === "default" ? horaADecimal(cDespues.entrada) : null;
          const descansoAntes = salidaAntes !== null && entradaDec !== null ? (24 - salidaAntes) + entradaDec : null;
          const descansoDespues = salidaDec !== null && entradaDespues !== null ? (24 - salidaDec) + entradaDespues : null;
          const avisoDescansoAntes = descansoAntes !== null && descansoAntes < DESCANSO_MINIMO_HORAS;
          const avisoDescansoDespues = descansoDespues !== null && descansoDespues < DESCANSO_MINIMO_HORAS;
          const avisoCiclo = cicloEdit !== null && cicloEdit.horas >= UMBRAL_AVISO_SOBRETIEMPO;
          const hayAviso = avisoDescansoAntes || avisoDescansoDespues || avisoCiclo;
          // Quien está en preselección en un feriado: se recomienda descanso y, para dejarlo trabajar, hay que confirmarlo.
          const avisoPrueba = pruebaDeLaPersona(edit.personaId, edit.fecha);
          const faltaConfirmar = avisoPrueba !== null && !confirmaFeriado;

          return (
            <Modal abierto onCerrar={() => setEdit(null)} bloqueado={guardando} ancho="sm">
              <h3 className="mb-1 font-serif text-lg">{p?.nombres} {p?.apellidos}</h3>
              <p className="mb-4 text-sm text-taupe">{abr} {num}</p>
              {propio ? (
                <p className="mb-2 rounded-lg bg-rojo/10 px-3 py-2 text-sm text-rojo">
                  No puedes fijar tu propio turno (la hora de entrada define tu tardanza). Pídeselo a un administrador.
                </p>
              ) : (
                <>
                  <div className="grid grid-cols-2 gap-3">
                    <Campo etiqueta="Entrada" type="time" value={entrada} onChange={(e) => setEntrada(e.target.value)} />
                    <Campo etiqueta="Salida" type="time" value={salida} onChange={(e) => setSalida(e.target.value)} />
                  </div>
                  {hayAviso && (
                    <div className="mt-3 space-y-1 rounded-lg border border-ambar/40 bg-ambar/[0.06] px-3 py-2 text-xs text-ambar">
                      {avisoDescansoAntes && (
                        <p>Deja solo {descansoAntes!.toFixed(1)} h de descanso desde la salida del día anterior (mínimo recomendado: {DESCANSO_MINIMO_HORAS} h).</p>
                      )}
                      {avisoDescansoDespues && (
                        <p>Deja solo {descansoDespues!.toFixed(1)} h de descanso hasta la entrada del día siguiente (mínimo recomendado: {DESCANSO_MINIMO_HORAS} h).</p>
                      )}
                      {avisoCiclo && (
                        <p>Esta persona ya lleva {cicloEdit!.horas.toFixed(1)}/48 h en su ciclo de 7 días vigente hoy (día {cicloEdit!.dia} de 7) — antes de guardar, revisa si le conviene más descanso.</p>
                      )}
                    </div>
                  )}
                  {avisoPrueba && (
                    <BannerAviso enLinea role="alert" variante="advertencia" className="mt-3 !py-2 text-xs">
                      <p className="mb-1 font-medium">{tituloDelAviso(avisoPrueba.nombreFeriado)}</p>
                      <p className="mb-2 leading-relaxed">{cuerpoDelAviso(avisoPrueba)}</p>
                      <Boton variante="primario" tamano="sm" disabled={guardando} onClick={marcarDescanso}>Dar descanso ese día (recomendado)</Boton>
                      <label className="mt-2 flex cursor-pointer items-start gap-2">
                        <input type="checkbox" className="mt-0.5" checked={confirmaFeriado} onChange={(e) => setConfirmaFeriado(e.target.checked)} />
                        <span>{TEXTO_CONFIRMAR_TRABAJO_EN_FERIADO}</span>
                      </label>
                    </BannerAviso>
                  )}
                  {/* La pregunta que evita que una excepción se coma la regla:
                      ¿es solo por hoy, o de ahora en adelante? Lo decide quien sabe. */}
                  <div className="mt-5 rounded-lg border border-sand p-3">
                    <p className="mb-2 text-xs text-taupe">¿Este cambio es solo por este día, o de ahora en adelante?</p>
                    <div className="flex flex-wrap gap-2">
                      <Boton variante="primario" disabled={guardando || faltaConfirmar} onClick={guardarTurno}>
                        {guardando ? "…" : "Solo este día"}
                      </Boton>
                      <Boton variante="secundario" disabled={guardando || faltaConfirmar} onClick={guardarDesdeAqui}>
                        De aquí en adelante
                      </Boton>
                    </div>
                    <p className="mt-2 text-[11px] leading-relaxed text-taupe">
                      <strong>Solo este día</strong> deja un turno puntual (no toca su horario).{" "}
                      <strong>De aquí en adelante</strong> cambia su horario base de los {DIAS_PLURAL[diaSemana(edit.fecha)]} desde esta fecha y no deja turno puntual.
                    </p>
                  </div>
                  {/* Desde la Integrada, tocar un nombre abre este editor: de aquí se llega al almacén de ese día. */}
                  {(() => {
                    const ce = celda(edit.personaId, edit.fecha);
                    if ((ce.tipo !== "turno" && ce.tipo !== "default") || edit.fecha < hoyLima()) return null;
                    return (
                      <p className="mt-3 text-sm">
                        <Boton variante="enlace" disabled={guardando} onClick={() => { const e = edit; setEdit(null); abrirAlmacen(e.personaId, e.fecha); }}>
                          ¿Piso o almacén ese día? Ahora: {textoPuesto(puestoDe(edit.personaId, edit.fecha))}
                        </Boton>
                      </p>
                    );
                  })()}
                  <div className="mt-3 flex flex-wrap justify-between gap-2">
                    <div className="flex gap-2">
                      <Boton variante="secundario" disabled={guardando} onClick={marcarDescanso}>Descanso</Boton>
                      <Boton variante="sutil" disabled={guardando} onClick={quitar}>Quitar</Boton>
                    </div>
                    <Boton variante="secundario" disabled={guardando} onClick={() => setEdit(null)}>Cancelar</Boton>
                  </div>
                </>
              )}
            </Modal>
          );
        })()}
      </main>
    </div>
  );
}

"use client";

// ─────────────────────────────────────────────────────────────────────────────
// Desempeño del equipo — una fila por persona, un cuadrito por día.
//
// QUÉ PROMETE: que cualquier número de la tabla se pueda abrir hasta el día que
//   lo produjo, sin salir de la pantalla y sin entrar a la ficha de nadie.
// QUÉ ASUME: que el rango cabe en memoria (~30 personas × ~60 días). Por encima
//   de 62 días la cuadrícula se apaga sola y lo dice; los totales siguen.
// CÓMO SE VUELVE ATRÁS: lo único que escribe son las dos justificaciones, y las
//   dos van por las mismas RPC que Incidencias (fn_levantar_tardanza y
//   fn_set_justificacion), con su rastro. Todo lo demás es lectura.
//
// POR QUÉ ESTÁ HECHA ASÍ — la versión anterior de esta pantalla resumía bien y
// no servía. Decía «Sandra · 135 min tarde» y ahí se acababa: no se podía saber
// qué día fue, ni si eran nueve tardanzas chicas o una de dos horas y cuarto, ni
// justificarla. Para eso había que ir a su ficha, que es el camino de cuatro
// clics que esta pantalla vino a matar. Tres cosas se decidieron a partir de ahí:
//
// · EL DÍA ES LA UNIDAD, no la persona. Cada fila termina en una franja de
//   cuadritos, uno por día del rango, con su color. La tardanza grave lleva
//   un anillo que salta sin buscarlo —no un oscurecido: eso invertía la
//   lectura en modo oscuro, donde --color-ambar se vuelve más CLARO, no más
//   oscuro— y los patrones —siempre los lunes, siempre después de un
//   descanso— aparecen solos porque están alineados en columnas. Tocar un
//   cuadrito abre ese día con lo que le tocaba, lo que marcó y qué se puede
//   hacer al respecto.
//
// · TODO NÚMERO LLEVA SU DENOMINADOR. «50 h» no es bueno ni malo; «50 de 72 h»
//   sí dice algo. Lo que le tocaba sale de su horario y sus turnos
//   (lib/admin/jornada-esperada.ts), que espeja la cascada de la base.
//
// · EL ORDEN MIDE GRAVEDAD, NO CANTIDAD. Antes ordenaba por número de tardanzas
//   y ponía a quien llegó siete minutos tarde dos veces por encima de quien
//   llegó dos horas y cuarto tarde una. Manda la PEOR tardanza del periodo, y
//   después los minutos acumulados. Las faltas siguen yendo primero.
//
// La ruta sigue siendo /admin/horas aunque el título no diga «horas»: hay
// enlaces vivos y romper una URL para cambiar un nombre no lo vale.
//
// Y lo que NO cuenta, que es donde se evitan los falsos positivos: las tardanzas
// con motivo registrado, y las faltas que fn_faltas ya descarta (vacaciones,
// descanso sustitutorio por feriado, suspensión, justificación). Acusar a quien
// no debía cuesta más que dejar pasar una falta real.
// ─────────────────────────────────────────────────────────────────────────────

import { Fragment, Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { EsqueletoTabla } from "@/components/cargando";
import { useToast } from "@/components/toast";
import { traerTodo } from "@/lib/admin/traer-todo";
import { descargarCsv, generarCsv } from "@/lib/admin/csv";
import { useFiltroGuardado } from "@/lib/admin/use-filtro-guardado";
import { hoyLima, TZ_LIMA, formatoMinutos } from "@cayla-dynamic/shared";
import { type Area, AREAS_FALLBACK, parseAreas, areaCorto, areaNombre } from "@/lib/areas";
import { MESES, lecturaObjetivos, type ObjetivoItem } from "@/lib/objetivos";
import { GraficoHoras, type DiaGrafico } from "@/components/grafico-horas";
import {
  esperadoDelDia, horarioVigente, fechasDelRango, dowDe, estadoDelDia,
  type Esperado, type EstadoDia, type HorarioTramo, type TurnoDia,
} from "@/lib/admin/jornada-esperada";
import { Insignia } from "@/components/ui/insignia";
import { Campo, CampoSelect, CampoCasilla } from "@/components/ui/campo";
import { Boton } from "@/components/ui/boton";
import { Tabla, TablaEncabezado, Th } from "@/components/ui/tabla";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { X, Search } from "lucide-react";

// Por encima de esto la cuadrícula deja de ayudar y empieza a colgar el
// navegador: 30 personas × 365 días son once mil cuadritos. Se apaga y se dice.
const MAX_DIAS_CUADRICULA = 62;

// Una tardanza de este tamaño ya no es «llegó justo»: cambia el color del
// cuadro. No es un umbral legal ni sanciona nada — es cuándo se ve distinto.
const TARDANZA_SERIA_MIN = 15;
const TARDANZA_GRAVE_MIN = 60;

const MOTIVOS_FALTA = [
  { valor: "permiso_concedido", label: "Permiso concedido" },
  { valor: "cumpleanos", label: "Cumpleaños" },
  { valor: "estudios", label: "Estudios" },
  { valor: "descanso_medico", label: "Descanso médico" },
  { valor: "otro", label: "Otro" },
];
const MOTIVOS_TARDANZA = [
  { valor: "fuerza_mayor", label: "Fuerza mayor" },
  { valor: "salud", label: "Salud" },
  { valor: "transporte", label: "Transporte" },
  { valor: "otro", label: "Otro" },
];
const etiqueta = (lista: { valor: string; label: string }[], m: string | null | undefined) =>
  lista.find((x) => x.valor === m)?.label ?? m ?? "";

// Motivos que devuelve fn_faltas cuando el día NO cuenta como falta.
const MOTIVO_NO_FALTA: Record<string, string> = {
  suspension: "suspensión",
  vacaciones: "vacaciones",
  descanso_sustitutorio: "descanso sustitutorio",
};

function primerDiaDelMes(iso = hoyLima()): string { return iso.slice(0, 8) + "01"; }
// Lunes de la semana que contiene `iso`, mismo criterio que Incidencias
// (admin/incidencias/page.tsx: lunesDeLaSemana). Aritmética de Date en UTC,
// no de string como `antiguedad` más abajo, porque acá sí hace falta cruzar
// límites de mes.
function addDiasISO(iso: string, n: number): string {
  const [y, m, d] = iso.split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  dt.setUTCDate(dt.getUTCDate() + n);
  return dt.toISOString().slice(0, 10);
}
function lunesDeLaSemana(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  const dow = new Date(Date.UTC(y, m - 1, d)).getUTCDay(); // 0=domingo…6=sábado
  return addDiasISO(iso, dow === 0 ? -6 : 1 - dow);
}
function rango(preset: "semana" | "mes" | "mesPasado" | "anio"): { desde: string; hasta: string } {
  const hoy = hoyLima();
  const [y, m] = hoy.split("-").map(Number);
  if (preset === "semana") {
    // Lunes a DOMINGO, no a sábado: en Trujillo se trabaja domingo, y cortar
    // el sábado dejaría fuera justo el día más reciente para esa sede.
    const lunes = lunesDeLaSemana(hoy);
    return { desde: lunes, hasta: addDiasISO(lunes, 6) };
  }
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
// "2023-06-15" medido al "2026-08-31" → "3 a. 2 m.". Aritmética de string, no
// de Date: mismo motivo que el resto del archivo — un año-mes-día no tiene
// huso horario del que protegerse, y restarlo como Date sí puede desfasarse.
function antiguedad(fechaIngreso: string, hasta: string): string {
  const [ay, am, ad] = fechaIngreso.split("-").map(Number);
  const [by, bm, bd] = hasta.split("-").map(Number);
  let anios = by - ay;
  let meses = bm - am;
  if (bd < ad) meses--;
  if (meses < 0) { anios--; meses += 12; }
  if (anios <= 0 && meses <= 0) return "recién ingresa";
  if (anios === 0) return `${meses} mes${meses === 1 ? "" : "es"}`;
  if (meses === 0) return `${anios} año${anios === 1 ? "" : "s"}`;
  return `${anios} a. ${meses} m.`;
}

function fechaLarga(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { weekday: "long", day: "numeric", month: "long", timeZone: "UTC" })
    .format(new Date(Date.UTC(y, m - 1, d)));
}
function horaLima(ts: string | null): string {
  if (!ts) return "—";
  return new Intl.DateTimeFormat("es-PE", { timeZone: TZ_LIMA, hour: "2-digit", minute: "2-digit", hour12: true })
    .format(new Date(ts));
}
const LETRA_DIA = ["D", "L", "M", "M", "J", "V", "S"];
// Sin acentos ni mayúsculas, para que "chavez" encuentre a "Chávez".
function plano(s: string): string {
  return s.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
}

// ── El día ───────────────────────────────────────────────────────────────────
// `EstadoDia` y la regla que lo decide viven en lib/admin/jornada-esperada.ts,
// con sus pruebas: una regla que dice si alguien faltó no se prueba a ojo.
interface Dia {
  fecha: string;
  estado: EstadoDia;
  esperado: Esperado;
  entradaTs: string | null;
  salidaTs: string | null;
  horas: number | null;
  minutosTarde: number | null;
  minutosSalidaTemprana: number | null;
  horasExtra: number;
  jornadaEstado: string | null;
  levantada: string | null;      // motivo del levantamiento de la tardanza
  faltaMotivo: string | null;    // motivo por el que ese día no cuenta como falta
  agregado: boolean;             // registro histórico 2025 (un mes en una fecha)
}

interface Fila {
  personaId: string;
  nombre: string;
  sede: string;
  area: string;
  activa: boolean;
  fechaIngreso: string | null;
  ausenciasDias: number;
  // Mismo total de arriba, partido en dos (fn_ausencias_resumen, 0443): lo
  // que CAYLA paga —por ley o por decisión propia— y lo que no. No es
  // "grave" contra "leve": descanso médico y maternidad están adentro de
  // ausenciasDiasPagados, protegidos por ley — ver el Tile de abajo.
  ausenciasDiasPagados: number;
  ausenciasDiasNoPagados: number;
  ausenciasRegistros: number;
  ausenciasPorTipo: Record<string, number>;
  dias: Dia[];
  diasEsperados: number;      // los que le tocaban Y no tenían motivo para faltar
  diasTrabajados: number;
  diasConMotivo: number;      // vacaciones, permiso, descanso médico, suspensión…
  horasEsperadas: number;
  horasConMotivo: number;
  // Días medidos contra el HORARIO BASE por no haber turno cargado. No es un
  // dato sobre la persona: es un dato sobre lo que el sistema sabe de ese día.
  diasSinTurno: number;
  // De esos días sin turno, cuántos además tuvieron una tardanza o salida
  // anticipada real — el número que importa para el KPI: no todo día sin
  // turno cargado produce una anomalía, solo estos la vuelven sospechosa.
  tardanzasSospechosas: number;
  horasTotales: number;
  horasReales: number;
  horasAgregadas: number;
  agregados: number;
  tardanzas: number;
  tardanzasLevantadas: number;
  minutosTarde: number;
  peorTardanza: number;
  salidasTempranas: number;
  horasExtra: number;
  faltas: number;
  faltasJustificadas: number;
  incompletas: number;
  pendientes: number;
  objCumplidos: number;
  objTotal: number;
  objetivos: ObjetivoItem[];
  // ¿Hay contra qué medirla? Sin horario ni turnos, sus horas no se comparan
  // con nada — y mezclarlas en un total «de X h que tocaban» lo vuelve falso.
  tieneHorario: boolean;
}

const porRevisar = (f: Fila) => f.incompletas + f.pendientes;
const cumplimiento = (f: Fila) => (f.horasEsperadas > 0 ? f.horasReales / f.horasEsperadas : -1);
const objPct = (f: Fila) => (f.objTotal > 0 ? f.objCumplidos / f.objTotal : -1);

// Colores del cuadrito. Se leen en este orden en la leyenda, y el ámbar tiene
// tres intensidades porque siete minutos y dos horas no son la misma noticia.
function colorDia(d: Dia): string {
  switch (d.estado) {
    case "falta": return "bg-rojo";
    case "revisar": return "border border-dashed border-taupe bg-papel";
    case "tarde": {
      const m = d.minutosTarde ?? 0;
      // Antes: "bg-ambar brightness-75" para la grave. Un filtro que siempre
      // oscurece funciona sobre --color-ambar en claro (#74501a, ya oscuro) y
      // se INVIERTE en oscuro (#c99a4a, un dorado claro): ahí "más oscuro" se
      // acerca al fondo en vez de saltar, y la de veinte minutos brilla más
      // que la de dos horas. El anillo no depende de qué tan claro sea el
      // token en cada tema, así que apunta igual en los dos.
      if (m >= TARDANZA_GRAVE_MIN) return "bg-ambar ring-2 ring-inset ring-rojo-profundo";
      if (m >= TARDANZA_SERIA_MIN) return "bg-ambar";
      // Era /45: medía 2.09:1 en claro y 2.34:1 en oscuro contra bg-papel,
      // por debajo del piso de 3:1 para contraste no-textual (WCAG 1.4.11).
      // /65 llega a ~3.0:1 en los dos temas sin acercarse a "tardanza seria".
      return "bg-ambar/65";
    }
    // Era /20: 1.34:1 en claro, 1.29:1 en oscuro. /75 llega a ~3:1 en oscuro
    // (el más exigente de los dos) sin cambiar el resto de la escala.
    case "justificada": return "bg-rojo/75";
    case "ok": return "bg-verde";
    case "extra": return "bg-verde/45 ring-1 ring-inset ring-verde";
    // Era /25: 1.42:1 en claro, 1.51:1 en oscuro. /70 llega a ~3:1 en claro
    // (el más exigente) — auditoría UX/UI del 2026-09-14, medida contra los
    // hex reales de globals.css con la fórmula de luminancia WCAG 2.x.
    case "sin_marca": return "bg-taupe/70";
    case "descanso": return "bg-sand";
    case "sin_horario": return "bg-sand/40";
    case "futuro": return "border border-sand";
  }
}

function explicarDia(d: Dia, nombre: string): string {
  const partes: string[] = [`${nombre} · ${fechaLarga(d.fecha)}`];
  if (d.esperado.trabaja) {
    partes.push(`le tocaba ${d.esperado.entrada}${d.esperado.salida ? `–${d.esperado.salida}` : ""}` +
      (d.esperado.horas > 0 ? ` (${fmtHoras(d.esperado.horas)})` : ""));
  } else if (d.estado === "sin_horario") {
    partes.push("sin horario cargado");
  } else {
    partes.push("descanso");
  }
  if (d.entradaTs) partes.push(`entró ${horaLima(d.entradaTs)}`);
  if (d.salidaTs) partes.push(`salió ${horaLima(d.salidaTs)}`);
  if (d.horas !== null) partes.push(`${fmtHoras(d.horas)} trabajadas`);
  if ((d.minutosTarde ?? 0) > 0) {
    partes.push(d.levantada ? `${formatoMinutos(d.minutosTarde!)} tarde (justificada)` : `${formatoMinutos(d.minutosTarde!)} TARDE`);
  }
  if ((d.minutosSalidaTemprana ?? 0) > 0) partes.push(`salió ${formatoMinutos(d.minutosSalidaTemprana!)} antes`);
  if (d.estado === "falta") partes.push("FALTA");
  if (d.estado === "justificada") partes.push(`no marcó — ${MOTIVO_NO_FALTA[d.faltaMotivo ?? ""] ?? etiqueta(MOTIVOS_FALTA, d.faltaMotivo) ?? "justificada"}`);
  if (d.estado === "revisar") partes.push(d.jornadaEstado === "auto_cerrada_pendiente" ? "cerrada automáticamente" : "sin salida marcada");
  if (d.estado === "extra") partes.push("trabajó en su día de descanso");
  if (d.agregado) partes.push("registro histórico 2025 (un mes en una fecha)");
  return partes.join(" · ");
}

// "3 d Vacaciones · 2 d Descanso médico (con documento)" — el título del
// cuadrito, para no gastar una columna aparte por cada tipo posible.
function desgloseAusencias(porTipo: Record<string, number>): string {
  const entradas = Object.entries(porTipo);
  if (entradas.length === 0) return "Sin ausencias en el periodo.";
  return entradas.map(([tipo, dias]) => `${dias} d ${tipo}`).join(" · ");
}

type Columna = "atencion" | "nombre" | "sede" | "asistencia" | "horas" | "tardanzas" | "faltas" | "revisar" | "objetivos" | "ausencias";
type Orden = { col: Columna; asc: boolean };

function comparar(a: Fila, b: Fila, col: Columna, asc: boolean): number {
  const s = asc ? 1 : -1;
  const nom = () => a.nombre.localeCompare(b.nombre, "es");
  switch (col) {
    // Cascada, no una puntuación que pese las tres cosas en un número: eso
    // diría cosas que nadie pidió. Faltas primero porque no vino; después la
    // PEOR tardanza, que es la que se conversa; después el acumulado.
    case "atencion":
      return (
        b.faltas - a.faltas ||
        b.peorTardanza - a.peorTardanza ||
        b.minutosTarde - a.minutosTarde ||
        porRevisar(b) - porRevisar(a) ||
        nom()
      );
    case "nombre": return s * nom();
    case "sede": return s * a.sede.localeCompare(b.sede) || nom();
    case "asistencia": return s * ((a.diasTrabajados - a.diasEsperados) - (b.diasTrabajados - b.diasEsperados)) || nom();
    case "horas": return s * (cumplimiento(a) - cumplimiento(b)) || nom();
    case "tardanzas": return s * (a.peorTardanza - b.peorTardanza) || s * (a.minutosTarde - b.minutosTarde) || nom();
    case "faltas": return s * (a.faltas - b.faltas) || nom();
    case "revisar": return s * (porRevisar(a) - porRevisar(b)) || nom();
    case "objetivos": return s * (objPct(a) - objPct(b)) || nom();
    case "ausencias": return s * (a.ausenciasDias - b.ausenciasDias) || nom();
  }
}

// Th propio de esta pantalla, no el de components/ui/tabla.tsx: además de
// pintar la celda gestiona el orden de la columna, cosa que el compartido no
// hace. Nombre distinto a propósito, para que un grep de "Th" no confunda
// los dos componentes.
function ThOrdenable({ col, orden, setOrden, num = false, sticky = false, children, title }: {
  col: Columna; orden: Orden; setOrden: (o: Orden) => void; num?: boolean;
  /**
   * Ancla la celda al borde izquierdo cuando la tabla se desplaza en
   * horizontal — la usa solo "Nombre": sin esto, quien arrastra hacia la
   * derecha en un teléfono para leer "Faltas" o "Revisar" pierde de vista de
   * quién es la fila. Fondo opaco (bg-sand, no el bg-sand/70 del thead):
   * sticky pinta su propia capa, y una capa semitransparente no tapa lo que
   * pasa por debajo al desplazarse.
   */
  sticky?: boolean;
  children: React.ReactNode; title?: string;
}) {
  const activa = orden.col === col;
  const texto = col === "nombre" || col === "sede";
  return (
    <th
      className={`px-3 py-2 font-normal ${num ? "text-right" : "text-left"} ${sticky ? "sticky left-0 z-20 bg-sand" : ""}`}
      title={title}
    >
      <button
        onClick={() => setOrden(activa ? { col, asc: !orden.asc } : { col, asc: texto })}
        className={`inline-flex items-center gap-1 rounded px-1 py-0.5 hover:text-tinta ${activa ? "font-medium text-tinta" : ""}`}
      >
        {children}
        <span aria-hidden className={activa ? "" : "opacity-0"}>{orden.asc ? "▲" : "▼"}</span>
      </button>
    </th>
  );
}

// Contra qué se midió ese día. No es adorno: una tardanza medida contra el
// horario base cuando la persona en realidad rotó de turno no es un dato sobre
// ella, es un dato sobre lo que falta en /admin/turnos. La columna existe para
// que no se confundan las dos cosas.
function medidoContra(d: Dia): { texto: string; sospechoso: boolean } {
  const hayNovedad = (d.minutosTarde ?? 0) > 0 || (d.minutosSalidaTemprana ?? 0) > 0;
  switch (d.esperado.origen) {
    case "turno": return { texto: "turno del día", sospechoso: false };
    case "horario":
    case "legacy": return { texto: "horario base", sospechoso: hayNovedad };
    case "sin_horario": return { texto: "sin horario", sospechoso: false };
  }
}

// El desempeño de una persona, abierto DEBAJO de su fila. Va debajo y no en
// otra pantalla ni tapando la tabla: así siguen a la vista las demás filas para
// comparar, y no se pierden ni los filtros ni el periodo.
function DetallePersona({ f, meta, anio, mes, sel, onDia }: {
  f: Fila; meta: number;
  anio: number; mes: number;   // el mes de «hasta»: los objetivos son mensuales
  sel: { personaId: string; fecha: string } | null;
  onDia: (personaId: string, fecha: string) => void;
}) {
  const mesLabel = `${MESES[mes - 1].toLowerCase()} ${anio}`;
  const sig = mes === 12 ? { anio: anio + 1, mes: 1 } : { anio, mes: mes + 1 };
  const sigLabel = `${MESES[sig.mes - 1].toLowerCase()} ${sig.anio}`;
  const objUrl = (a: number, m: number) => `/admin/objetivos?persona=${f.personaId}&anio=${a}&mes=${m}`;
  const objPorcentaje = f.objTotal > 0 ? Math.round((f.objCumplidos / f.objTotal) * 100) : 0;
  const nivel = lecturaObjetivos(f.objCumplidos, f.objTotal);
  const conMarcaje = f.dias.filter((d) => d.entradaTs !== null || d.horas !== null);
  const grafico: DiaGrafico[] = conMarcaje
    .filter((d) => !d.agregado)
    .map((d) => ({
      fecha: d.fecha,
      horas: d.horas ?? 0,
      problema: d.estado === "tarde" || d.estado === "revisar",
    }));
  const promedio = f.diasTrabajados > 0 ? f.horasReales / f.diasTrabajados : 0;
  const diasSospechosos = conMarcaje.filter((d) => medidoContra(d).sospechoso);
  const sinTurnoConNovedad = diasSospechosos.length;

  return (
    <div className="space-y-4 border-t-2 border-tinta/15 bg-crema/60 px-4 py-5">
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 xl:grid-cols-6">
        {[
          { label: "Total del periodo", valor: fmtHoras(f.horasReales) },
          { label: "Días trabajados", valor: `${f.diasTrabajados}${f.diasEsperados ? ` de ${f.diasEsperados}` : ""}` },
          { label: "Promedio por día", valor: promedio > 0 ? fmtHoras(promedio) : "—" },
          { label: "Días con tardanza", valor: String(f.tardanzas) },
          { label: "Salidas anticipadas", valor: String(f.salidasTempranas) },
          { label: "Tiempo adicional", valor: f.horasExtra > 0 ? fmtHoras(f.horasExtra) : "—" },
        ].map((c) => (
          <div key={c.label} className="rounded-2xl border border-sand bg-papel px-4 py-3">
            <div className="text-xs uppercase tracking-wide text-taupe">{c.label}</div>
            <div className="mt-1 font-serif text-xl">{c.valor}</div>
          </div>
        ))}
      </div>

      {/* Los dos avisos que separan «problema de la persona» de «problema de
          datos». El segundo es el que evita conversaciones injustas. */}
      {f.diasConMotivo > 0 && (
        <p className="rounded-lg bg-sand/50 px-3 py-2 text-xs">
          Además tuvo <strong>{f.diasConMotivo} día{f.diasConMotivo === 1 ? "" : "s"} con motivo registrado</strong>{" "}
          ({fmtHoras(f.horasConMotivo)}): vacaciones, permiso, descanso médico, suspensión o descanso sustitutorio.
          No cuentan como falta y <strong>tampoco entran en las horas que le tocaban</strong>.
        </p>
      )}
      {sinTurnoConNovedad > 0 && (
        <p className="rounded-lg bg-ambar/10 px-3 py-2 text-xs">
          <strong>{sinTurnoConNovedad} de sus días con tardanza o salida anticipada se midieron contra su horario
          base</strong>, porque ese día no había turno cargado en Turnos. Si en la práctica rotó de turno, esos
          minutos dicen más de lo que falta registrar que de la persona — mira la columna «medido contra» antes
          de conversarlo.{" "}
          <Link href={`/admin/turnos?fecha=${diasSospechosos[0].fecha}`} className="text-rojo underline">
            Ir a Turnos, en la semana del {fechaLarga(diasSospechosos[0].fecha)} →
          </Link>
        </p>
      )}

      {/* Del total de `ausencias` en el rango, sin pasar por la cascada de
          horario/turnos — por eso puede no coincidir con "días con motivo" de
          arriba: ese cuenta solo días que le tocaba trabajar, este cuenta
          cualquier día de la ausencia, caiga o no en su horario. */}
      {f.ausenciasDias > 0 && (
        <div className="rounded-2xl border border-sand bg-papel p-4">
          <h3 className="mb-2 font-serif text-lg">
            Ausencias del periodo
            <span className="ml-2 text-sm font-normal text-taupe">
              · {f.ausenciasDias} día{f.ausenciasDias === 1 ? "" : "s"} en {f.ausenciasRegistros} registro{f.ausenciasRegistros === 1 ? "" : "s"}
            </span>
          </h3>
          <ul className="space-y-1 text-sm">
            {Object.entries(f.ausenciasPorTipo).map(([tipo, dias]) => (
              <li key={tipo} className="flex justify-between gap-4">
                <span>{tipo}</span>
                <span className="text-taupe">{dias} día{dias === 1 ? "" : "s"}</span>
              </li>
            ))}
          </ul>
          <Link href="/admin/ausencias" className="mt-2 inline-block text-xs text-rojo hover:underline">
            Ver el detalle en Ausencias →
          </Link>
        </div>
      )}

      <div className="rounded-2xl border border-sand bg-papel p-4">
        <h3 className="mb-3 font-serif text-lg">
          Horas por día
          {meta > 0 && <span className="ml-2 text-sm font-normal text-taupe">· su jornada son {fmtHoras(meta)}</span>}
        </h3>
        <GraficoHoras dias={grafico} meta={meta} />
      </div>

      {/* Los objetivos son MENSUALES: no siguen al rango de fechas, y por eso
          el título lleva el mes escrito. Acá van de solo lectura —marcarlos
          cumplidos es de /admin/objetivos, que además re-valida quién puede—
          pero los dos enlaces llegan con la persona y el mes ya elegidos. */}
      <div className="rounded-2xl border border-sand bg-papel p-4">
        <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
          <h3 className="font-serif text-lg">Objetivos de {mesLabel}</h3>
          {f.objTotal > 0 && (
            <span className="flex items-center gap-2 text-sm">
              <span className="text-taupe">{f.objCumplidos}/{f.objTotal} cumplidos</span>
              {/* Sin color que premie: desde la 0171 los objetivos no pagan. */}
              <Insignia atenuada punto={false}>{nivel.etiqueta}</Insignia>
            </span>
          )}
        </div>

        {f.objTotal === 0 ? (
          <p className="text-sm text-taupe">
            Todavía no tiene objetivos cargados para {mesLabel}.{" "}
            <Link href={objUrl(anio, mes)} className="text-rojo hover:underline">Cargárselos ahora →</Link>
          </p>
        ) : (
          <>
            <div className="mb-3 h-2 overflow-hidden rounded-full bg-sand">
              <div className={`h-full rounded-full ${objPorcentaje >= 60 ? "bg-verde" : objPorcentaje >= 30 ? "bg-ambar" : "bg-rojo"}`}
                style={{ width: `${objPorcentaje}%` }} />
            </div>
            <ul className="space-y-1 text-sm">
              {f.objetivos.map((o) => (
                <li key={o.id} className="flex items-start gap-2">
                  <span className={o.cumplido ? "text-verde" : "text-taupe/50"}>{o.cumplido ? "✓" : "○"}</span>
                  <span className={o.cumplido ? "text-taupe line-through" : ""}>{o.descripcion}</span>
                </li>
              ))}
            </ul>
          </>
        )}

        <div className="mt-3 flex flex-wrap gap-4 text-xs">
          <Link href={objUrl(anio, mes)} className="text-rojo hover:underline">Editar los de {mesLabel} →</Link>
          <Link href={objUrl(sig.anio, sig.mes)} className="text-rojo hover:underline">Preparar los de {sigLabel} →</Link>
        </div>
      </div>

      <Tabla className="[font-variant-numeric:tabular-nums]">
        <TablaEncabezado>
          <Th>Fecha</Th>
          <Th>Entrada</Th>
          <Th>Salida</Th>
          <Th>Horas</Th>
          <Th>Tardanza</Th>
          <Th>Sal. antic.</Th>
          <Th>T. adicional</Th>
          <Th>Medido contra</Th>
          <Th>Incidencia</Th>
        </TablaEncabezado>
        <tbody>
          {conMarcaje.length === 0 ? (
            <tr><td colSpan={9} className="px-4 py-6 text-center text-taupe">Sin jornadas en el periodo.</td></tr>
          ) : conMarcaje.map((d) => {
            const mc = medidoContra(d);
            const activa = sel?.personaId === f.personaId && sel?.fecha === d.fecha;
            return (
              // <tr> nativo y no <Fila>: <Fila> trae su propia zebra
              // (even:bg-hueso/50), y esa pseudoclase pesa más que un
              // "bg-crema" suelto — en una fila par, la marca de "día
              // abierto" quedaría tapada por la zebra. Mismo criterio que
              // reporte-sede/page.tsx, que por eso tampoco usa <Fila> acá.
              <tr key={d.fecha}
                onClick={() => onDia(f.personaId, d.fecha)}
                className={`cursor-pointer border-t border-sand transition-colors hover:bg-crema ${activa ? "bg-crema" : ""}`}
                title="Abrir este día">
                <td className="px-4 py-2 capitalize">{fechaLarga(d.fecha)}</td>
                <td className="px-4 py-2">{horaLima(d.entradaTs)}</td>
                <td className="px-4 py-2">{d.salidaTs ? horaLima(d.salidaTs) : <span className="text-ambar">—</span>}</td>
                <td className="px-4 py-2">{d.horas !== null ? fmtHoras(d.horas) : "—"}</td>
                <td className="px-4 py-2">
                  {(d.minutosTarde ?? 0) > 0
                    ? d.levantada
                      ? <span className="text-taupe"><s>{formatoMinutos(d.minutosTarde!)}</s> · levantada</span>
                      : <span className="text-rojo">{formatoMinutos(d.minutosTarde!)}</span>
                    : <span className="text-taupe/50">—</span>}
                </td>
                <td className="px-4 py-2">
                  {(d.minutosSalidaTemprana ?? 0) > 0
                    ? <span className="text-ambar">{formatoMinutos(d.minutosSalidaTemprana!)}</span>
                    : <span className="text-taupe/50">—</span>}
                </td>
                <td className="px-4 py-2">{d.horasExtra > 0 ? <span className="text-verde">{fmtHoras(d.horasExtra)}</span> : <span className="text-taupe/50">—</span>}</td>
                <td className={`px-4 py-2 text-xs ${mc.sospechoso ? "text-ambar" : "text-taupe"}`}>
                  {mc.texto}
                  {d.esperado.trabaja && <span className="text-taupe/60"> · {d.esperado.entrada}{d.esperado.salida ? `–${d.esperado.salida}` : ""}</span>}
                  {mc.sospechoso && <span title="Este día no tenía turno cargado: la tardanza o la salida anticipada se midió contra el horario base."> ⚠</span>}
                </td>
                <td className="px-4 py-2 text-xs">
                  {d.estado === "revisar" && <Insignia variante="advertencia" punto={false}>
                    {d.jornadaEstado === "auto_cerrada_pendiente" ? "auto-cerrada" : "sin salida"}</Insignia>}
                  {d.estado === "extra" && <Insignia variante="positivo" punto={false}>en su descanso</Insignia>}
                  {d.agregado && <Insignia atenuada punto={false}>histórico 2025</Insignia>}
                </td>
              </tr>
            );
          })}
        </tbody>
      </Tabla>
      <div className="flex flex-wrap items-center justify-between gap-3 text-xs">
        <p className="text-taupe">Toca cualquier día para abrirlo, justificarlo o mandarlo a Correcciones.</p>
        <div className="flex gap-4">
          <Link href={`/admin/personas/${f.personaId}`} className="text-rojo hover:underline">Abrir su ficha →</Link>
        </div>
      </div>
    </div>
  );
}

function Tile({ label, valor, pie, tono = "neutral" }: { label: string; valor: string; pie?: string; tono?: "neutral" | "alerta" }) {
  return (
    <div className="rounded-xl border border-sand bg-papel px-4 py-3">
      <div className="text-xs uppercase tracking-wide text-taupe">{label}</div>
      <div className={`mt-1 text-2xl font-semibold [font-variant-numeric:tabular-nums] ${tono === "alerta" && valor !== "0" ? "text-rojo" : ""}`}>{valor}</div>
      {pie && <div className="text-xs text-taupe">{pie}</div>}
    </div>
  );
}

function DesempenoContenido() {
  const router = useRouter();
  const { avisar } = useToast();
  const searchParams = useSearchParams();
  const personaEnlace = searchParams.get("persona");

  const [desde, setDesde] = useState(primerDiaDelMes());
  const [hasta, setHasta] = useState(hoyLima());
  const [filas, setFilas] = useState<Fila[]>([]);
  const [areas, setAreas] = useState<Area[]>(AREAS_FALLBACK);
  const [periodo, setPeriodo] = useState<{ fecha_ini: string; fecha_fin: string } | null>(null);
  const [sinActividad, setSinActividad] = useState(0);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Sede, área e "incluir inactivas" se acuerdan de la última vez; la fecha y
  // la búsqueda por nombre no — son de esta visita, no de cómo se mira siempre
  // esta pantalla.
  const [fSede, setFSede] = useFiltroGuardado("horas.sede", "");
  const [fArea, setFArea] = useFiltroGuardado("horas.area", "");
  const [fBusca, setFBusca] = useState("");
  const [verInactivas, setVerInactivas] = useFiltroGuardado("horas.verInactivas", false);
  const [orden, setOrden] = useState<Orden>({ col: "atencion", asc: true });

  // El día abierto. Es lo único que esta pantalla «selecciona».
  const [sel, setSel] = useState<{ personaId: string; fecha: string } | null>(null);
  // Qué persona tiene su desempeño abierto debajo de su fila.
  const [abierta, setAbierta] = useState<string | null>(null);
  const enlaceUsado = useRef(false);
  const [motivo, setMotivo] = useState("");
  const [obs, setObs] = useState("");
  const [guardando, setGuardando] = useState(false);

  const fechas = useMemo(() => (desde <= hasta ? fechasDelRango(desde, hasta) : []), [desde, hasta]);
  const hayCuadricula = fechas.length > 0 && fechas.length <= MAX_DIAS_CUADRICULA;
  const mesObjetivos = `${MESES[Number(hasta.slice(5, 7)) - 1]} ${hasta.slice(0, 4)}`;

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    setCargando(true);

    const [
      { data: personas, error: errPersonas },
      { data: jornadas, error: errJornadas },
      { data: extraData, error: errExtra },
      { data: faltasData, error: errFaltas },
      { data: objetivosData, error: errObjetivos },
      { data: levData, error: errLev },
      { data: horariosData, error: errHorarios },
      { data: turnosData, error: errTurnos },
      { data: areasData, error: areasError },
      { data: ausenciasResumenData, error: errAusencias },
    ] = await Promise.all([
      supabase.from("personas")
        .select("id, nombres, apellidos, estado, funcion, fecha_ingreso, sedes:sede_base_id(codigo)")
        .order("nombres"),
      // Por lotes: PostgREST corta en 1000 filas y devuelve 200 OK sin avisar.
      // El order por fecha+persona no es cosmético: sin un orden estable, dos
      // lotes pueden repetir una fila y perder otra.
      traerTodo<{ persona_id: string; fecha: string; entrada_ts: string | null; salida_final_ts: string | null; horas_trabajadas: number | null; minutos_tarde: number | null; horas_extra_detectadas: number | null; estado: string }>(
        (ini, fin) => supabase.from("jornadas")
          .select("persona_id, fecha, entrada_ts, salida_final_ts, horas_trabajadas, minutos_tarde, horas_extra_detectadas, estado")
          .gte("fecha", desde).lte("fecha", hasta)
          .order("fecha").order("persona_id").range(ini, fin),
      ),
      supabase.rpc("fn_jornadas_extra", { p_desde: desde, p_hasta: hasta }),
      supabase.rpc("fn_faltas", { p_desde: desde, p_hasta: hasta }),
      supabase.rpc("fn_objetivos_checklist", { p_anio: Number(hasta.slice(0, 4)), p_mes: Number(hasta.slice(5, 7)) }),
      supabase.from("tardanzas_justificadas").select("persona_id, fecha, motivo").gte("fecha", desde).lte("fecha", hasta),
      // Lo que le tocaba. Los dos tramos que hacen falta: cualquier horario que
      // SOLAPE el rango, no solo el vigente hoy — un rango pasado se mide contra
      // el horario que regía entonces, no contra el de ahora.
      supabase.from("horarios_asignados")
        .select("persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida, dias_laborables, horario_por_dia, almuerzo_min_minutos")
        .lte("vigente_desde", hasta).or(`vigente_hasta.is.null,vigente_hasta.gte.${desde}`),
      supabase.from("turnos").select("persona_id, fecha, hora_entrada, hora_salida, es_descanso")
        .gte("fecha", desde).lte("fecha", hasta),
      supabase.rpc("fn_areas"),
      supabase.rpc("fn_ausencias_resumen", { p_desde: desde, p_hasta: hasta }),
    ]);

    // Cualquiera de estas siete puede fallar sin que Supabase lance una
    // excepción: `data` llega null y, sin este chequeo, cada `?? []` de abajo
    // lo leía como "cero" — cero faltas, cero tardanzas levantadas, cero
    // ausencias. Eso no es "no hay nada": es que la consulta no respondió, y
    // se leía como un periodo perfecto en vez de un error. `areasError` queda
    // afuera a propósito: ya tiene su propio degradado (parseAreas cae a
    // AREAS_FALLBACK) y es solo un catálogo de etiquetas, no un conteo.
    const errAux = errExtra ?? errFaltas ?? errObjetivos ?? errLev ?? errHorarios ?? errTurnos ?? errAusencias;
    if (errPersonas || errJornadas || errAux) {
      setError((errPersonas ?? errJornadas ?? errAux)!.message);
      setCargando(false);
      return; // no pisa `filas` con datos parciales
    }
    setError(null);
    setAreas(parseAreas(areasData, areasError));

    // ── Índices ────────────────────────────────────────────────────────────
    const horariosPor = new Map<string, HorarioTramo[]>();
    for (const h of ((horariosData as unknown as HorarioTramo[] | null) ?? [])) {
      const l = horariosPor.get(h.persona_id) ?? [];
      l.push(h);
      horariosPor.set(h.persona_id, l);
    }
    const turnoPor = new Map<string, TurnoDia>();
    for (const t of ((turnosData as unknown as { persona_id: string; fecha: string; hora_entrada: string | null; hora_salida: string | null; es_descanso: boolean }[] | null) ?? [])) {
      turnoPor.set(`${t.persona_id}|${t.fecha}`, t);
    }
    const jornadaPor = new Map<string, { entrada_ts: string | null; salida_final_ts: string | null; horas_trabajadas: number | null; minutos_tarde: number | null; horas_extra_detectadas: number | null; estado: string }>();
    for (const j of jornadas ?? []) jornadaPor.set(`${j.persona_id}|${j.fecha}`, j);
    const extraPor = new Map<string, number>();
    for (const e of ((extraData as { persona_id: string; fecha: string; minutos_salida_temprana: number }[] | null) ?? [])) {
      extraPor.set(`${e.persona_id}|${e.fecha}`, e.minutos_salida_temprana);
    }
    const levPor = new Map<string, string>();
    for (const t of ((levData as { persona_id: string; fecha: string; motivo: string }[] | null) ?? [])) {
      levPor.set(`${t.persona_id}|${t.fecha}`, t.motivo);
    }
    const faltaPor = new Map<string, { justificada: boolean; motivo: string | null }>();
    for (const f of ((faltasData as { persona_id: string; fecha: string; justificada: boolean; motivo: string | null }[] | null) ?? [])) {
      faltaPor.set(`${f.persona_id}|${f.fecha}`, { justificada: f.justificada, motivo: f.motivo });
    }
    const objPor = new Map<string, { cumplidos: number; total: number; items: ObjetivoItem[] }>();
    for (const o of ((objetivosData as unknown as ObjetivoItem[] | null) ?? [])) {
      const a = objPor.get(o.persona_id) ?? { cumplidos: 0, total: 0, items: [] };
      a.total++;
      a.items.push(o);
      if (o.cumplido) a.cumplidos++;
      objPor.set(o.persona_id, a);
    }
    const ausenciasPor = new Map<string, { dias: number; diasPagados: number; diasNoPagados: number; registros: number; porTipo: Record<string, number> }>();
    for (const a of ((ausenciasResumenData as unknown as {
      persona_id: string; dias_total: number; dias_pagados: number; dias_no_pagados: number;
      registros: number; por_tipo: Record<string, number>;
    }[] | null) ?? [])) {
      ausenciasPor.set(a.persona_id, {
        dias: a.dias_total, diasPagados: a.dias_pagados, diasNoPagados: a.dias_no_pagados,
        registros: a.registros, porTipo: a.por_tipo ?? {},
      });
    }

    const hoy = hoyLima();
    const listaFechas = desde <= hasta ? fechasDelRango(desde, hasta) : [];
    const out: Fila[] = [];

    for (const p of personas ?? []) {
      const pid = p.id;
      const tramos = horariosPor.get(pid) ?? [];
      const ausRes = ausenciasPor.get(pid);
      const f: Fila = {
        personaId: pid,
        nombre: `${p.nombres} ${p.apellidos}`,
        sede: (p as unknown as { sedes?: { codigo: string } }).sedes?.codigo ?? "?",
        area: (p as unknown as { funcion: string }).funcion ?? "",
        activa: (p as unknown as { estado: string }).estado === "activo",
        fechaIngreso: (p as unknown as { fecha_ingreso: string | null }).fecha_ingreso ?? null,
        ausenciasDias: ausRes?.dias ?? 0,
        ausenciasDiasPagados: ausRes?.diasPagados ?? 0,
        ausenciasDiasNoPagados: ausRes?.diasNoPagados ?? 0,
        ausenciasRegistros: ausRes?.registros ?? 0,
        ausenciasPorTipo: ausRes?.porTipo ?? {},
        dias: [], diasEsperados: 0, diasTrabajados: 0, diasConMotivo: 0,
        horasEsperadas: 0, horasConMotivo: 0, diasSinTurno: 0, tardanzasSospechosas: 0,
        horasTotales: 0, horasReales: 0, horasAgregadas: 0, agregados: 0,
        tardanzas: 0, tardanzasLevantadas: 0, minutosTarde: 0, peorTardanza: 0,
        salidasTempranas: 0, horasExtra: 0,
        faltas: 0, faltasJustificadas: 0, incompletas: 0, pendientes: 0,
        objCumplidos: objPor.get(pid)?.cumplidos ?? 0, objTotal: objPor.get(pid)?.total ?? 0,
        objetivos: objPor.get(pid)?.items ?? [], tieneHorario: false,
      };

      for (const fecha of listaFechas) {
        const clave = `${pid}|${fecha}`;
        const esperado = esperadoDelDia(fecha, turnoPor.get(clave) ?? null, horarioVigente(tramos, fecha));
        const j = jornadaPor.get(clave) ?? null;
        const falta = faltaPor.get(clave) ?? null;
        const levantada = levPor.get(clave) ?? null;
        const horas = j && j.horas_trabajadas !== null ? Number(j.horas_trabajadas) : null;
        // Más de 24 h en un día es un AGREGADO del histórico 2025 (un mes entero
        // guardado en una fecha). Suma al total —la planilla lo usó para CTS y
        // gratificación— pero no es un día: fuera del promedio y del cuadrito.
        const agregado = (horas ?? 0) > 24;

        const estado: EstadoDia = estadoDelDia({
          fecha, hoy, esperado, agregado,
          jornada: j ? { horas, minutosTarde: j.minutos_tarde, estado: j.estado } : null,
          falta,
          tardanzaJustificada: levantada !== null,
        });

        f.dias.push({
          fecha, estado, esperado,
          entradaTs: j?.entrada_ts ?? null,
          salidaTs: j?.salida_final_ts ?? null,
          horas,
          minutosTarde: j?.minutos_tarde ?? null,
          minutosSalidaTemprana: extraPor.get(clave) ?? null,
          horasExtra: Number(j?.horas_extra_detectadas ?? 0),
          jornadaEstado: j?.estado ?? null,
          levantada,
          faltaMotivo: falta?.motivo ?? null,
          agregado,
        });

        // ── Acumulados ─────────────────────────────────────────────────────
        // Lo esperado solo cuenta hasta hoy: sumar los días que todavía no
        // llegaron pintaría a todo el mundo en deuda a principio de mes.
        // Lo esperado solo cuenta hasta hoy —sumar los días que no llegaron
        // pintaría a todo el mundo en deuda a principio de mes— y NO cuenta los
        // días con motivo registrado. Sin esa segunda resta, quien estuvo de
        // vacaciones aparece debiendo las horas de sus vacaciones: un número que
        // hace quedar mal a quien tenía permiso.
        if (esperado.trabaja && fecha <= hoy) {
          if (falta?.justificada) { f.diasConMotivo++; f.horasConMotivo += esperado.horas; }
          else { f.diasEsperados++; f.horasEsperadas += esperado.horas; }
          if (esperado.origen !== "turno") f.diasSinTurno++;
        }
        // Mismo criterio que medidoContra() en DetallePersona: solo "horario"
        // o "legacy" pueden ser sospechosos — "turno" es la referencia correcta
        // y "sin_horario" no tiene con qué medir una tardanza.
        if ((esperado.origen === "horario" || esperado.origen === "legacy") &&
            ((j?.minutos_tarde ?? 0) > 0 || (extraPor.get(clave) ?? 0) > 0)) {
          f.tardanzasSospechosas++;
        }
        if (esperado.origen !== "sin_horario") f.tieneHorario = true;
        if (horas !== null) {
          f.horasTotales += horas;
          if (agregado) { f.horasAgregadas += horas; f.agregados++; }
          else { f.horasReales += horas; if (horas > 0) f.diasTrabajados++; }
        } else if (j) f.incompletas++;
        if (j?.estado === "auto_cerrada_pendiente") f.pendientes++;
        if ((j?.minutos_tarde ?? 0) > 0) {
          if (levantada) f.tardanzasLevantadas++;
          else {
            f.tardanzas++;
            f.minutosTarde += j!.minutos_tarde!;
            f.peorTardanza = Math.max(f.peorTardanza, j!.minutos_tarde!);
          }
        }
        if ((extraPor.get(clave) ?? 0) > 0) f.salidasTempranas++;
        if ((j?.horas_extra_detectadas ?? 0) > 0) f.horasExtra += Number(j!.horas_extra_detectadas);
        if (falta) { if (falta.justificada) f.faltasJustificadas++; else f.faltas++; }
      }
      out.push(f);
    }

    // Quien no tiene nada que mostrar en el rango no ocupa una fila; se dice
    // cuánta gente quedó fuera para que no desaparezca en silencio.
    // `ausenciasDias` entra acá a propósito: sin esto, alguien de licencia todo
    // el periodo —cero días trabajados, cero esperados, nada que revisar—
    // desaparecía de la tabla en silencio, que es justo a quien más le importa
    // que la nueva columna de Ausencias le muestre algo.
    const conAlgo = out.filter((r) =>
      r.diasTrabajados > 0 || r.agregados > 0 || r.incompletas > 0 ||
      r.faltas > 0 || r.faltasJustificadas > 0 || r.diasEsperados > 0 ||
      r.ausenciasDias > 0);
    setSinActividad(out.filter((r) => r.activa).length - conAlgo.filter((r) => r.activa).length);
    setFilas(conAlgo);

    // Al llegar desde la ficha con ?persona=, se abre el día MÁS GRAVE de esa
    // persona: es lo que se venía a ver. Sin esto el enlace dejaría la fila
    // destacada y el día habría que buscarlo a ojo entre treinta cuadritos.
    // El guard es un ref y no un estado a propósito: así esto no vuelve a
    // dispararse cada vez que la pantalla se recarga tras justificar algo.
    if (personaEnlace && !enlaceUsado.current) {
      enlaceUsado.current = true;
      const f = conAlgo.find((x) => x.personaId === personaEnlace);
      const porGravedad: EstadoDia[] = ["falta", "tarde", "revisar"];
      for (const e of f ? porGravedad : []) {
        const cand = f!.dias.filter((d) => d.estado === e);
        if (cand.length === 0) continue;
        const peor = e === "tarde"
          ? cand.reduce((a, b) => ((a.minutosTarde ?? 0) >= (b.minutosTarde ?? 0) ? a : b))
          : cand[0];
        setSel({ personaId: f!.personaId, fecha: peor.fecha });
        setAbierta(f!.personaId);
        break;
      }
    }
    setCargando(false);
  }, [router, desde, hasta, personaEnlace]);

  useEffect(() => { void cargar(); }, [cargar]);

  // El periodo de planilla NO se calcula acá. Va del 29 al 28, pero eso es un
  // hecho de `periodos_planilla`, no una regla que se pueda escribir en código.
  useEffect(() => {
    void createAdminSupabaseClient()
      .from("periodos_planilla").select("fecha_ini, fecha_fin")
      .lte("fecha_ini", hoyLima()).order("fecha_ini", { ascending: false }).limit(1)
      .then(({ data, error: e }) => { if (!e && data && data.length > 0) setPeriodo(data[0]); });
  }, []);

  const sedes = useMemo(() => [...new Set(filas.map((f) => f.sede))].sort(), [filas]);
  const areasPresentes = useMemo(() => [...new Set(filas.map((f) => f.area))].filter(Boolean).sort(), [filas]);
  const hayObjetivos = useMemo(() => filas.some((f) => f.objTotal > 0), [filas]);
  const hayAusencias = useMemo(() => filas.some((f) => f.ausenciasDias > 0), [filas]);

  const vista = useMemo(() => {
    const q = plano(fBusca.trim());
    return filas
      .filter((f) => verInactivas || f.activa)
      .filter((f) => !fSede || f.sede === fSede)
      .filter((f) => !fArea || f.area === fArea)
      .filter((f) => !q || plano(f.nombre).includes(q))
      .sort((a, b) => comparar(a, b, orden.col, orden.asc));
  }, [filas, verInactivas, fSede, fArea, fBusca, orden]);

  const totales = useMemo(() => ({
    horas: vista.reduce((s, f) => s + f.horasReales, 0),
    agregadas: vista.reduce((s, f) => s + f.horasAgregadas, 0),
    esperadas: vista.reduce((s, f) => s + f.horasEsperadas, 0),
    // Cuánta gente de la vista NO tiene horario ni turnos cargados. Sin esto el
    // recuadro decía «163 h de 90 h que tocaban» —trabajaron casi el doble de
    // lo que les tocaba— cuando lo que pasaba es que el 90 era el horario de
    // UNA de las tres. Un total que suma manzanas comparadas con nada.
    sinHorario: vista.filter((f) => !f.tieneHorario).length,
    tardanzas: vista.reduce((s, f) => s + f.tardanzas, 0),
    peor: vista.reduce((m, f) => Math.max(m, f.peorTardanza), 0),
    sospechosas: vista.reduce((s, f) => s + f.tardanzasSospechosas, 0),
    faltas: vista.reduce((s, f) => s + f.faltas, 0),
    porRevisar: vista.reduce((s, f) => s + porRevisar(f), 0),
    ausenciasDias: vista.reduce((s, f) => s + f.ausenciasDias, 0),
    ausenciasDiasPagados: vista.reduce((s, f) => s + f.ausenciasDiasPagados, 0),
    ausenciasDiasNoPagados: vista.reduce((s, f) => s + f.ausenciasDiasNoPagados, 0),
  }), [vista]);

  const filaSel = useMemo(() => (sel ? filas.find((f) => f.personaId === sel.personaId) ?? null : null), [filas, sel]);
  const diaSel = useMemo(() => (sel && filaSel ? filaSel.dias.find((d) => d.fecha === sel.fecha) ?? null : null), [filaSel, sel]);

  // Abrir y cerrar el día. El formulario del panel se limpia acá y no en un
  // efecto que mire `sel`: un efecto que solo existe para resetear estado es
  // una cascada de renders y una regla que el linter marca con razón.
  const abrirDia = useCallback((personaId: string, fecha: string) => {
    setSel({ personaId, fecha });
    // Abrir un día desde la cuadrícula despliega también su desempeño: el día
    // se entiende mirando los de alrededor, no solo.
    setAbierta(personaId);
    setMotivo(""); setObs("");
  }, []);
  const cerrarDia = useCallback(() => {
    setSel(null);
    setMotivo(""); setObs("");
  }, []);

  useEffect(() => {
    if (!sel || !filaSel) return;
    const alPulsar = (e: KeyboardEvent) => {
      if (e.key === "Escape") { cerrarDia(); return; }
      // ←/→ mueven al día anterior/siguiente de la MISMA persona sin cerrar
      // el panel — útil al revisar varias tardanzas seguidas de una fila.
      // Izquierda es un día antes porque los cuadritos del grid van en ese
      // mismo sentido: fecha más antigua a la izquierda.
      if (e.key !== "ArrowLeft" && e.key !== "ArrowRight") return;
      const idx = filaSel.dias.findIndex((d) => d.fecha === sel.fecha);
      if (idx === -1) return;
      const dia = filaSel.dias[e.key === "ArrowLeft" ? idx - 1 : idx + 1];
      if (dia) abrirDia(filaSel.personaId, dia.fecha);
    };
    window.addEventListener("keydown", alPulsar);
    return () => window.removeEventListener("keydown", alPulsar);
  }, [sel, filaSel, cerrarDia, abrirDia]);

  const aplicarPreset = (p: "semana" | "mes" | "mesPasado" | "anio") => { const r = rango(p); setDesde(r.desde); setHasta(r.hasta); };
  const hayFiltro = Boolean(fSede || fArea || fBusca.trim() || verInactivas);

  // La tabla ya calculada (denominador incluido), no los marcajes crudos que
  // exporta /admin/exportar — para llevar esta vista, tal como quedó filtrada
  // y ordenada, a una reunión de sede o a contabilidad sin copiarla a mano.
  function exportarVista() {
    const filas = vista.map((f) => ({
      nombre: f.nombre,
      sede: f.sede,
      area: f.area,
      activa: f.activa ? "sí" : "no",
      dias_trabajados: f.diasTrabajados,
      dias_esperados: f.tieneHorario ? f.diasEsperados : "",
      horas_reales: f.horasReales.toFixed(1),
      horas_esperadas: f.tieneHorario ? f.horasEsperadas.toFixed(1) : "",
      tardanzas: f.tardanzas,
      peor_tardanza_min: f.tardanzas > 0 ? f.peorTardanza : "",
      faltas: f.faltas,
      por_revisar: porRevisar(f),
      ausencias_dias: f.ausenciasDias,
      // Mismo split que el Tile de arriba (0443): quien lleva esto a
      // contabilidad necesita distinguir lo que paga de lo que no, no solo el
      // total — es justo lo que el total mezclaba antes.
      ausencias_dias_pagados: f.ausenciasDiasPagados,
      ausencias_dias_no_pagados: f.ausenciasDiasNoPagados,
      objetivos_cumplidos: f.objTotal > 0 ? f.objCumplidos : "",
      objetivos_total: f.objTotal > 0 ? f.objTotal : "",
    }));
    const csv = generarCsv(filas, [
      "nombre", "sede", "area", "activa",
      "dias_trabajados", "dias_esperados", "horas_reales", "horas_esperadas",
      "tardanzas", "peor_tardanza_min", "faltas", "por_revisar",
      "ausencias_dias", "ausencias_dias_pagados", "ausencias_dias_no_pagados",
      "objetivos_cumplidos", "objetivos_total",
    ]);
    descargarCsv(`dynamic-desempeno-${desde}_a_${hasta}.csv`, csv);
  }

  // ── Las dos únicas escrituras, por las mismas RPC que Incidencias ─────────
  async function justificar(tipo: "tardanza" | "falta") {
    if (!sel) return;
    const lista = tipo === "tardanza" ? MOTIVOS_TARDANZA : MOTIVOS_FALTA;
    const m = motivo || lista[0].valor;
    if (m === "otro" && obs.trim().length < 3) {
      avisar("error", "Para «Otro» la observación es obligatoria.");
      return;
    }
    setGuardando(true);
    const supabase = createAdminSupabaseClient();
    const { error: e } = tipo === "tardanza"
      ? await supabase.rpc("fn_levantar_tardanza", { p_persona_id: sel.personaId, p_fecha: sel.fecha, p_motivo: m, p_observacion: obs.trim() || null })
      : await supabase.rpc("fn_set_justificacion", { p_persona_id: sel.personaId, p_fecha: sel.fecha, p_motivo: m, p_observacion: obs.trim() || null });
    setGuardando(false);
    if (e) { avisar("error", e.message); return; }
    avisar("ok", tipo === "tardanza" ? "Tardanza justificada. La hora real no se tocó." : "Falta justificada.");
    setObs(""); setMotivo("");
    await cargar();
  }

  async function quitarJustificacionFalta() {
    if (!sel) return;
    setGuardando(true);
    const { error: e } = await createAdminSupabaseClient()
      .rpc("fn_quitar_justificacion", { p_persona_id: sel.personaId, p_fecha: sel.fecha });
    setGuardando(false);
    if (e) { avisar("error", e.message); return; }
    avisar("ok", "Justificación retirada. El día vuelve a contar como falta.");
    await cargar();
  }

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        <CabeceraPagina
          titulo="Desempeño del equipo"
          descripcion="Toca una fila y su desempeño se abre debajo. Cada cuadrito es un día: tócalo para ver qué pasó y resolverlo ahí mismo."
          accion={
            <div className="flex flex-wrap items-end gap-3">
              <div className="flex gap-1 rounded-lg border p-1 text-sm">
                {/* La más usada primero: es lo que una encargada mira el lunes
                    por la mañana, y antes había que armarla a mano con los dos
                    calendarios.
                    Nativos a propósito: esto es un control segmentado (varias
                    opciones dentro de un mismo marco), no un botón suelto —
                    <Boton> siempre trae su propio padding/tamaño y forzarlo acá
                    rompería el marco compartido "rounded-lg border p-1". */}
                <button onClick={() => aplicarPreset("semana")} className="rounded-md px-2.5 py-1 hover:bg-sand/60">Esta semana</button>
                <button onClick={() => aplicarPreset("mes")} className="rounded-md px-2.5 py-1 hover:bg-sand/60">Este mes</button>
                <button onClick={() => aplicarPreset("mesPasado")} className="rounded-md px-2.5 py-1 hover:bg-sand/60">Mes pasado</button>
                {periodo && (
                  <button onClick={() => { setDesde(periodo.fecha_ini); setHasta(periodo.fecha_fin); }}
                    className="rounded-md px-2.5 py-1 hover:bg-sand/60"
                    title={`Periodo en curso: ${periodo.fecha_ini} a ${periodo.fecha_fin}`}>
                    Periodo de planilla
                  </button>
                )}
                <button onClick={() => aplicarPreset("anio")} className="rounded-md px-2.5 py-1 hover:bg-sand/60">Todo el año</button>
              </div>
              <Campo etiqueta="Desde" type="date" value={desde} onChange={(e) => setDesde(e.target.value)} />
              <Campo etiqueta="Hasta" type="date" value={hasta} onChange={(e) => setHasta(e.target.value)} />
            </div>
          }
        />

        <div className="mb-4 flex flex-wrap items-center gap-3 rounded-xl border border-sand bg-papel px-4 py-3 text-sm">
          <div className="relative">
            <Search size={15} strokeWidth={1.8} aria-hidden className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-taupe" />
            <Campo value={fBusca} onChange={(e) => setFBusca(e.target.value)} placeholder="Buscar por nombre…"
              aria-label="Buscar por nombre" className="w-52 pl-8" />
          </div>
          <CampoSelect etiqueta="Sede" value={fSede} onChange={(e) => setFSede(e.target.value)}>
            <option value="">Todas</option>
            {sedes.map((s) => <option key={s} value={s}>{s}</option>)}
          </CampoSelect>
          <CampoSelect etiqueta="Área" value={fArea} onChange={(e) => setFArea(e.target.value)}>
            <option value="">Todas</option>
            {areasPresentes.map((a) => <option key={a} value={a}>{areaNombre(areas, a)}</option>)}
          </CampoSelect>
          <CampoCasilla
            etiqueta="Incluir inactivas"
            checked={verInactivas}
            onChange={(e) => setVerInactivas(e.target.checked)}
            title="Su historial sostiene los reportes de periodos pasados."
          />
          <div className="ml-auto flex items-center gap-4">
            {vista.length > 0 && (
              <Boton variante="enlace" className="text-taupe hover:text-tinta" onClick={exportarVista}>
                Exportar CSV
              </Boton>
            )}
            {orden.col !== "atencion" && (
              <Boton variante="enlace" className="text-taupe hover:text-tinta" onClick={() => setOrden({ col: "atencion", asc: true })}>
                Volver al orden por atención
              </Boton>
            )}
            {hayFiltro && (
              <Boton variante="enlace" className="text-taupe hover:text-tinta"
                onClick={() => { setFSede(""); setFArea(""); setFBusca(""); setVerInactivas(false); }}>
                Quitar filtros
              </Boton>
            )}
          </div>
        </div>

        <div className="mb-5 grid grid-cols-2 gap-3 sm:grid-cols-3 xl:grid-cols-7">
          <Tile label="Horas del periodo" valor={`${totales.horas.toFixed(0)} h`}
            pie={
              totales.esperadas === 0
                ? "nadie tiene horario cargado: no hay con qué comparar"
                : totales.sinHorario > 0
                  ? `de ${totales.esperadas.toFixed(0)} h que tocaban a ${vista.length - totales.sinHorario} de ${vista.length}`
                  : `de ${totales.esperadas.toFixed(0)} h que tocaban`
            } />
          <Tile label="Faltas" valor={String(totales.faltas)} tono="alerta" pie="le tocaba y no marcó" />
          <Tile label="Tardanzas" valor={String(totales.tardanzas)} tono="alerta"
            pie={totales.peor > 0 ? `la peor, ${formatoMinutos(totales.peor)}` : undefined} />
          <Tile label="Turnos sin cargar" valor={String(totales.sospechosas)} tono="alerta"
            pie="tardanzas medidas contra el horario base, no el turno" />
          <Tile label="Por revisar" valor={String(totales.porRevisar)} tono="alerta" pie="marcajes sin cerrar" />
          {/* El total se abre en dos cifras con el mismo peso visual
              (0443/auditoría de Ausencias): "pagados" mezcla descanso médico
              y maternidad —protegidos por ley— con licencias que CAYLA
              concedió a propósito; no es un número de alarma, es
              información. "No pagados" es el que puede alimentar el aviso de
              patrón en Ausencias ("para mirar, no para sancionar"). */}
          <Tile label="Ausencias" valor={`${totales.ausenciasDias} d`}
            pie={
              totales.ausenciasDias === 0
                ? "nadie en el periodo"
                : `${totales.ausenciasDiasNoPagados} no pagados · ${totales.ausenciasDiasPagados} pagados`
            } />
          <Tile label="Personas" valor={String(vista.length)} pie={`de ${filas.length} con actividad`} />
        </div>

        {error && (
          <div className="mb-4 rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
            No se pudo cargar el desempeño: {error}{" "}
            <Boton variante="enlace" onClick={() => void cargar()}>Reintentar</Boton>
          </div>
        )}
        {desde > hasta && <p className="mb-4 text-sm text-rojo">El «desde» es posterior al «hasta».</p>}
        {cargando && (
          <EsqueletoTabla
            anchos={["w-36", "w-16", "w-14", "w-14", "w-14", "w-12", "w-16", ...(hayAusencias ? ["w-14"] : []), ...(hayObjetivos ? ["w-14"] : [])]}
            franjaFinal={hayCuadricula ? Math.min(fechas.length, 16) : undefined}
          />
        )}
        {!cargando && !error && filas.length === 0 && <p className="text-sm text-taupe">Sin actividad en este periodo.</p>}
        {!cargando && !error && filas.length > 0 && vista.length === 0 && (
          <p className="text-sm text-taupe">Ninguna persona coincide con estos filtros.</p>
        )}

        {vista.length > 0 && (
          <>
            {/* alturaMaxima: sin esto <TablaEncabezado> no ancla a nada — ver
                su propio comentario en components/ui/tabla.tsx — y con listas
                largas se pierde de vista qué columna es cuál al bajar. Las
                filas siguen escritas a mano y no con <Fila>: llevan su propia
                columna "Nombre" pegada al borde para el arrastre horizontal,
                que <Fila> no resuelve. */}
            <Tabla className="[font-variant-numeric:tabular-nums]" alturaMaxima="70vh">
              <TablaEncabezado>
                  <ThOrdenable col="nombre" orden={orden} setOrden={setOrden} sticky>Nombre</ThOrdenable>
                  <ThOrdenable col="sede" orden={orden} setOrden={setOrden}>Sede</ThOrdenable>
                  <ThOrdenable col="asistencia" orden={orden} setOrden={setOrden} num title="Días trabajados de los que le tocaban">Días</ThOrdenable>
                  <ThOrdenable col="horas" orden={orden} setOrden={setOrden} num title="Horas trabajadas de las que le tocaban">Horas</ThOrdenable>
                  <ThOrdenable col="tardanzas" orden={orden} setOrden={setOrden} num title="Cuántas, y la peor del periodo">Tardanzas</ThOrdenable>
                  <ThOrdenable col="faltas" orden={orden} setOrden={setOrden} num>Faltas</ThOrdenable>
                  <ThOrdenable col="revisar" orden={orden} setOrden={setOrden} num>Revisar</ThOrdenable>
                  {hayAusencias && <ThOrdenable col="ausencias" orden={orden} setOrden={setOrden} num title="Días de ausencia en el periodo (vacaciones, descanso médico, permisos…)">Ausencias</ThOrdenable>}
                  {hayObjetivos && <ThOrdenable col="objetivos" orden={orden} setOrden={setOrden} num>Objetivos</ThOrdenable>}
                  {hayCuadricula && (
                    <th className="px-3 py-1 text-left font-normal">
                      <div className="flex">
                        {fechas.map((f) => {
                          const dw = dowDe(f);
                          return (
                            <div key={f} className={`w-[18px] shrink-0 text-center text-[9px] leading-tight ${dw === 0 ? "text-rojo/60" : ""}`}>
                              <div>{LETRA_DIA[dw]}</div>
                              <div className="text-taupe">{Number(f.slice(8, 10))}</div>
                            </div>
                          );
                        })}
                      </div>
                    </th>
                  )}
              </TablaEncabezado>
              <tbody>
                {vista.map((f) => (
                    <Fragment key={f.personaId}>
                    <tr
                      onClick={() => setAbierta((a) => (a === f.personaId ? null : f.personaId))}
                      className={`group cursor-pointer border-t align-middle hover:bg-crema/60 ${abierta === f.personaId ? "bg-crema" : ""}`}
                      title={abierta === f.personaId ? "Cerrar su desempeño" : "Ver su desempeño"}>
                      {/* Ancla de la fila: sticky para que arrastrar en horizontal —el
                          caso normal en un teléfono, con hasta ~62 columnas de
                          cuadrícula— no pierda de vista de quién es. Fondo propio
                          (papel o crema, el mismo que ya traía la fila): una celda
                          sticky pinta su propia capa, y sin esto se transparenta al
                          pasar por debajo de las columnas que siguen desplazándose. */}
                      <td className={`sticky left-0 z-[1] px-3 py-1.5 ${abierta === f.personaId ? "bg-crema" : "bg-papel group-hover:bg-crema/60"}`}>
                        <span aria-hidden className="mr-1.5 inline-block w-2 text-taupe">{abierta === f.personaId ? "▾" : "▸"}</span>
                        {f.nombre}
                        {!f.activa && <Insignia atenuada tamano="sm" punto={false} className="ml-2">inactiva</Insignia>}
                        <div className="text-[11px] text-taupe">
                          {f.area ? areaCorto(areas, f.area) : "sin área"}
                          {f.fechaIngreso && <> · {antiguedad(f.fechaIngreso, hasta)}</>}
                        </div>
                      </td>
                      <td className="px-3 py-1.5 text-taupe">{f.sede}</td>
                      <td className="px-3 py-1.5 text-right">
                        {f.diasTrabajados}
                        {f.tieneHorario
                          ? <span className="text-taupe/60"> / {f.diasEsperados}</span>
                          : <Link href="/admin/horarios" onClick={(e) => e.stopPropagation()}
                              className="text-ambar hover:underline"
                              title="No tiene horario ni turnos cargados: no hay contra qué medirla. Ir a Horarios →">
                              {" "}· sin horario
                            </Link>}
                      </td>
                      <td className="px-3 py-1.5 text-right">
                        <span className="font-medium">{f.horasReales.toFixed(1)}</span>
                        {f.tieneHorario && <span className="text-taupe/60"> / {f.horasEsperadas.toFixed(1)}</span>}
                      </td>
                      <td className="px-3 py-1.5 text-right">
                        {f.tardanzas === 0
                          ? <span className="text-taupe/50">—</span>
                          : <span className={f.peorTardanza >= TARDANZA_SERIA_MIN ? "text-rojo" : "text-ambar"}>
                              {f.tardanzas}<span className="text-taupe/60"> · peor {formatoMinutos(f.peorTardanza)}</span>
                            </span>}
                      </td>
                      <td className="px-3 py-1.5 text-right">
                        {f.faltas > 0 ? <span className="font-medium text-rojo">{f.faltas}</span> : <span className="text-taupe/50">—</span>}
                      </td>
                      <td className="px-3 py-1.5 text-right">
                        {porRevisar(f) > 0 ? <span className="text-ambar">{porRevisar(f)}</span> : <span className="text-taupe/50">—</span>}
                      </td>
                      {hayAusencias && (
                        <td className="px-3 py-1.5 text-right" title={desgloseAusencias(f.ausenciasPorTipo)}>
                          {f.ausenciasDias > 0 ? <span>{f.ausenciasDias} d</span> : <span className="text-taupe/50">—</span>}
                        </td>
                      )}
                      {hayObjetivos && (
                        <td className="px-3 py-1.5 text-right">
                          {f.objTotal === 0 ? <span className="text-taupe/40">—</span>
                            : <span className={objPct(f) < 0.3 ? "text-rojo" : ""}>{f.objCumplidos}/{f.objTotal}</span>}
                        </td>
                      )}
                      {hayCuadricula && (
                        <td className="px-3 py-1.5">
                          <div className="flex">
                            {f.dias.map((d) => (
                              <div key={d.fecha} className="w-[18px] shrink-0 px-[1px]">
                                <button
                                  onClick={() => abrirDia(f.personaId, d.fecha)}
                                  title={explicarDia(d, f.nombre)}
                                  aria-label={explicarDia(d, f.nombre)}
                                  className={`block h-5 w-full rounded-[3px] transition-transform hover:scale-125 ${colorDia(d)} ${
                                    sel?.personaId === f.personaId && sel?.fecha === d.fecha ? "ring-2 ring-tinta ring-offset-1" : ""}`}
                                />
                              </div>
                            ))}
                          </div>
                        </td>
                      )}
                    </tr>
                    {abierta === f.personaId && (
                      <tr>
                        <td colSpan={7 + (hayAusencias ? 1 : 0) + (hayObjetivos ? 1 : 0) + (hayCuadricula ? 1 : 0)} className="p-0">
                          <DetallePersona
                            f={f}
                            meta={f.diasEsperados > 0 ? f.horasEsperadas / f.diasEsperados : 0}
                            anio={Number(hasta.slice(0, 4))}
                            mes={Number(hasta.slice(5, 7))}
                            sel={sel}
                            onDia={abrirDia}
                          />
                        </td>
                      </tr>
                    )}
                    </Fragment>
                  ))}
              </tbody>
            </Tabla>

            <div className="mt-3 flex flex-wrap items-center gap-x-5 gap-y-2 text-xs text-taupe">
              <span className="font-medium text-tinta">Cada cuadrito, un día:</span>
              <span className="flex items-center gap-1.5"><i className="inline-block size-3 rounded-[3px] bg-verde" /> trabajó</span>
              <span className="flex items-center gap-1.5"><i className="inline-block size-3 rounded-[3px] bg-ambar/65" /><i className="inline-block size-3 rounded-[3px] bg-ambar" /><i className="inline-block size-3 rounded-[3px] bg-ambar ring-2 ring-inset ring-rojo-profundo" /> tardanza (más marcado, más tarde)</span>
              <span className="flex items-center gap-1.5"><i className="inline-block size-3 rounded-[3px] bg-rojo" /> falta</span>
              <span className="flex items-center gap-1.5"><i className="inline-block size-3 rounded-[3px] bg-rojo/75" /> no marcó, con motivo</span>
              <span className="flex items-center gap-1.5"><i className="inline-block size-3 rounded-[3px] border border-dashed border-taupe bg-papel" /> marcaje por revisar</span>
              <span className="flex items-center gap-1.5"><i className="inline-block size-3 rounded-[3px] bg-verde/45 ring-1 ring-inset ring-verde" /> trabajó en su descanso</span>
              <span className="flex items-center gap-1.5"><i className="inline-block size-3 rounded-[3px] bg-sand" /> descanso</span>
              <span className="flex items-center gap-1.5"><i className="inline-block size-3 rounded-[3px] bg-taupe/70" /> le tocaba, sin marcaje y sin motivo</span>
            </div>
          </>
        )}

        {vista.length > 0 && !hayCuadricula && (
          <p className="mt-3 text-xs text-taupe">
            La cuadrícula solo se dibuja hasta {MAX_DIAS_CUADRICULA} días — {fechas.length} días serían miles de
            cuadritos y el navegador se arrastra. Los totales de arriba sí cubren todo el rango; acorta las
            fechas para ver los días.
          </p>
        )}

        <p className="mt-4 max-w-3xl text-xs text-taupe">
          Ordenado por lo que necesita atención: faltas, después la <strong>peor</strong> tardanza del periodo
          (no cuántas), después los marcajes por revisar. «Días» y «horas» van contra lo que le tocaba según su
          horario y sus turnos, contando solo hasta hoy y <strong>sin los días con motivo registrado</strong>:
          quien estuvo de vacaciones no debe las horas de sus vacaciones. Las tardanzas con motivo registrado no cuentan, y las
          faltas las calcula la base: no es falta el día de vacaciones, el de descanso sustitutorio por feriado,
          el de suspensión ni el que tiene justificación.
          {hayObjetivos && <> Los objetivos son los de <strong>{mesObjetivos.toLowerCase()}</strong>: son mensuales, no siguen al rango.</>}
          {totales.agregadas > 0 && (
            <> Este rango incluye <strong>{totales.agregadas.toFixed(0)} h de registros históricos de 2025</strong> —
            el total de un mes guardado en una sola fecha, porque entonces no había marcaje diario. La planilla
            los usó para CTS y gratificación, pero no son días: quedan fuera de las horas de arriba y de la
            cuadrícula, que compara contra lo que tocaba día a día.</>
          )}
          {sinActividad > 0 && (
            <> Hay <strong>{sinActividad} persona{sinActividad === 1 ? "" : "s"} activa{sinActividad === 1 ? "" : "s"}</strong> sin
            nada que mostrar en este rango (ingreso posterior o sin horario cargado); no salen en la tabla.</>
          )}
        </p>
      </main>

      {/* ── El día ─────────────────────────────────────────────────────────── */}
      {sel && filaSel && diaSel && (
        <>
          <div onClick={cerrarDia} className="fixed inset-0 z-40 bg-black/40" aria-hidden />
          <aside role="dialog" aria-label={`${filaSel.nombre}, ${fechaLarga(diaSel.fecha)}`}
            className="fixed inset-y-0 right-0 z-50 w-full max-w-[460px] overflow-y-auto border-l border-sand bg-crema shadow-xl">
            <div className="sticky top-0 flex items-start justify-between gap-4 border-b border-sand bg-crema px-5 py-4">
              <div>
                <h2 className="font-serif text-xl capitalize">{fechaLarga(diaSel.fecha)}</h2>
                <p className="text-sm text-taupe">{filaSel.nombre} · Sede {filaSel.sede}</p>
              </div>
              <button onClick={cerrarDia} aria-label="Cerrar" className="rounded-lg border border-sand p-1.5 text-taupe hover:text-tinta">
                <X size={18} strokeWidth={1.8} />
              </button>
            </div>

            <div className="space-y-4 p-5 text-sm">
              <div className="rounded-2xl border border-sand bg-papel p-4">
                <h3 className="mb-2 font-serif text-lg">Qué pasó</h3>
                <dl className="space-y-1.5">
                  <div className="flex justify-between gap-4">
                    <dt className="text-taupe">Le tocaba</dt>
                    <dd className="text-right">
                      {diaSel.esperado.trabaja
                        ? <>{diaSel.esperado.entrada}{diaSel.esperado.salida ? `–${diaSel.esperado.salida}` : ""}
                            {diaSel.esperado.horas > 0 && <span className="text-taupe"> · {fmtHoras(diaSel.esperado.horas)}</span>}</>
                        : diaSel.esperado.origen === "sin_horario" ? <span className="text-ambar">sin horario cargado</span> : "descanso"}
                      {diaSel.esperado.origen === "turno" && <div className="text-[11px] text-taupe">turno puntual del día</div>}
                    </dd>
                  </div>
                  <div className="flex justify-between gap-4">
                    <dt className="text-taupe">Entró</dt>
                    <dd className={(diaSel.minutosTarde ?? 0) > 0 && !diaSel.levantada ? "text-rojo" : ""}>{horaLima(diaSel.entradaTs)}</dd>
                  </div>
                  <div className="flex justify-between gap-4">
                    <dt className="text-taupe">Salió</dt>
                    <dd>{diaSel.salidaTs ? horaLima(diaSel.salidaTs) : <span className="text-ambar">sin marcar</span>}</dd>
                  </div>
                  <div className="flex justify-between gap-4">
                    <dt className="text-taupe">Trabajó</dt>
                    <dd>{diaSel.horas !== null ? fmtHoras(diaSel.horas) : "—"}</dd>
                  </div>
                  {(diaSel.minutosTarde ?? 0) > 0 && (
                    <div className="flex justify-between gap-4">
                      <dt className="text-taupe">Tardanza</dt>
                      <dd className={diaSel.levantada ? "text-taupe line-through" : "font-medium text-rojo"}>
                        {formatoMinutos(diaSel.minutosTarde!)}
                      </dd>
                    </div>
                  )}
                  {(diaSel.minutosSalidaTemprana ?? 0) > 0 && (
                    <div className="flex justify-between gap-4">
                      <dt className="text-taupe">Salida anticipada</dt>
                      <dd className="text-ambar">{formatoMinutos(diaSel.minutosSalidaTemprana!)}</dd>
                    </div>
                  )}
                </dl>
                {diaSel.estado === "falta" && (
                  <p className="mt-3 rounded-lg bg-rojo/10 px-3 py-2 text-rojo">Le tocaba trabajar y no hay ningún marcaje.</p>
                )}
                {diaSel.estado === "justificada" && (
                  <p className="mt-3 rounded-lg bg-sand/60 px-3 py-2">
                    No marcó, y no cuenta como falta: {MOTIVO_NO_FALTA[diaSel.faltaMotivo ?? ""] ?? etiqueta(MOTIVOS_FALTA, diaSel.faltaMotivo) ?? "justificada"}.
                  </p>
                )}
                {diaSel.estado === "revisar" && (
                  <p className="mt-3 rounded-lg bg-ambar/10 px-3 py-2">
                    {diaSel.jornadaEstado === "auto_cerrada_pendiente"
                      ? "El sistema cerró este día automáticamente porque nadie marcó la salida."
                      : "Falta la marca de salida, así que las horas de este día no se pueden calcular."}
                  </p>
                )}
                {diaSel.levantada && (
                  <p className="mt-3 rounded-lg bg-sand/60 px-3 py-2">
                    Tardanza justificada: {etiqueta(MOTIVOS_TARDANZA, diaSel.levantada)}. La hora real no se tocó.
                  </p>
                )}
                {diaSel.estado === "extra" && (
                  <p className="mt-3 rounded-lg bg-verde/10 px-3 py-2">Trabajó en un día que su horario marca como descanso.</p>
                )}
              </div>

              {/* Justificar. Va por las mismas RPC que Incidencias — no hay una
                  segunda forma de perdonar un día en este sistema. */}
              {((diaSel.minutosTarde ?? 0) > 0 && !diaSel.levantada) || diaSel.estado === "falta" ? (
                <div className="rounded-2xl border border-sand bg-papel p-4">
                  <h3 className="mb-1 font-serif text-lg">
                    {diaSel.estado === "falta" ? "Justificar la falta" : "Justificar la tardanza"}
                  </h3>
                  <p className="mb-3 text-xs text-taupe">
                    Queda registrado con su motivo y sale del conteo. Dynamic avisa; la decisión es tuya.
                  </p>
                  {(() => {
                    const esFalta = diaSel.estado === "falta";
                    const lista = esFalta ? MOTIVOS_FALTA : MOTIVOS_TARDANZA;
                    const sel2 = motivo || lista[0].valor;
                    return (
                      <>
                        <div className="mb-2">
                          <CampoSelect etiqueta="Motivo" value={sel2} onChange={(e) => setMotivo(e.target.value)}>
                            {lista.map((m) => <option key={m.valor} value={m.valor}>{m.label}</option>)}
                          </CampoSelect>
                        </div>
                        <div className="mb-3">
                          <Campo
                            etiqueta="Observación"
                            value={obs}
                            onChange={(e) => setObs(e.target.value)}
                            error={sel2 === "otro" ? "Obligatoria para «Otro»." : undefined}
                          />
                        </div>
                        <Boton variante="primario" cargando={guardando} onClick={() => void justificar(esFalta ? "falta" : "tardanza")}>
                          Justificar
                        </Boton>
                      </>
                    );
                  })()}
                </div>
              ) : null}

              {diaSel.estado === "justificada" && !MOTIVO_NO_FALTA[diaSel.faltaMotivo ?? ""] && (
                <Boton variante="enlace" cargando={guardando}
                  className="text-rojo hover:text-rojo hover:no-underline"
                  onClick={() => void quitarJustificacionFalta()}>
                  Quitar la justificación — vuelve a contar como falta
                </Boton>
              )}

              <div className="flex flex-col gap-3 border-t border-sand pt-4">
                {/* Botón, no enlace, solo cuando "revisar" es la única acción
                    pendiente real del día — los otros dos enlaces de abajo son
                    exploración, no algo que haga falta resolver. */}
                {diaSel.estado === "revisar" && (
                  <Boton variante="primario"
                    onClick={() => router.push(`/admin/correcciones?persona=${filaSel.personaId}&fecha=${diaSel.fecha}`)}>
                    Abrir este día en Correcciones →
                  </Boton>
                )}
                <div className="flex flex-col gap-2">
                  {diaSel.estado !== "revisar" && (
                    <Link href={`/admin/correcciones?persona=${filaSel.personaId}&fecha=${diaSel.fecha}`}
                      className="text-rojo hover:underline">Abrir este día en Correcciones →</Link>
                  )}
                  <Link href={`/admin/incidencias?persona=${filaSel.personaId}`}
                    className="text-rojo hover:underline">Ver sus incidencias →</Link>
                  <Link href={`/admin/personas/${filaSel.personaId}`}
                    className="text-rojo hover:underline">Abrir su ficha →</Link>
                </div>
              </div>
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

"use client";

import { Fragment, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { AdminNav } from "../nav";
import { Cargando, SinDatos } from "@/components/cargando";
import { useToast } from "@/components/toast";
import { useRolActual } from "@/lib/admin/use-rol";
import { RANGO_LABEL, formatSoles } from "@/lib/rangos";
import { descargarCsv, generarCsv } from "@/lib/admin/csv";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { TZ_LIMA, parsearMontoSoles, puedeVerPlanilla } from "@cayla-dynamic/shared";

// ── Fechas ───────────────────────────────────────────────────────────────────
// Exportadas: las reutiliza /admin/planilla/boleta (misma fuente de verdad de formato).
export const MESES_LARGO = [
  "enero", "febrero", "marzo", "abril", "mayo", "junio",
  "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
];
const MESES_ABR = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];

// Año actual en horario de Lima (para la gestión de feriados sin periodo cargado)
function anioActualLima(): number {
  return Number(
    new Intl.DateTimeFormat("en-CA", { timeZone: TZ_LIMA, year: "numeric" }).format(new Date()),
  );
}

// "2026-07-28" → "28 jul"
export function fechaCorta(iso: string): string {
  const [, m, d] = iso.split("-");
  return `${Number(d)} ${MESES_ABR[Number(m) - 1]}`;
}

// Hoy en Lima como DD/MM/AAAA. Se arma con Intl y no con new Date().toISOString(),
// que resuelve en UTC: a partir de las 19:00 de Lima daría el día siguiente.
function hoyLimaDMA(): string {
  const p = new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA, year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(new Date());
  const v = (t: string) => p.find((x) => x.type === t)!.value;
  return `${v("day")}/${v("month")}/${v("year")}`;
}

// "2026-06-15" → "15/06"
function fechaDiaMes(iso: string): string {
  const [, m, d] = iso.split("-");
  return `${d}/${m}`;
}

// "2026-07-28" + 1 → "2026-07-29" (aritmética en UTC: sin sorpresas de zona)
function sumarDias(iso: string, n: number): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

// timestamptz → "13 jul 2026" en Lima
export function fechaLima(iso: string): string {
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA, day: "numeric", month: "short", year: "numeric",
  }).format(new Date(iso));
}

export function fmtHoras(n: number): string {
  return `${n.toLocaleString("es-PE", { maximumFractionDigits: 2 })} h`;
}

// ── Tipos (forma del jsonb de fn_periodos / fn_proyeccion_periodo / fn_simular_planilla) ──
interface PeriodoInfo {
  id: string;
  fecha_ini: string;
  fecha_fin: string;
  estado: "abierto" | "pagado";
  pagado_at: string | null;
  anio_etiqueta: number;
  mes_etiqueta: number;
}
// Una fila por persona cuya cifra pagada ya no coincide con el cálculo de hoy.
// Sale de fn_planilla_foto_diferencias (0096): el sistema lo DICE, no lo corrige solo.
interface Desvio {
  persona_id: string;
  nombre: string;
  total_foto: number | null;
  total_ahora: number | null;
  diferencia: number;
}
// ── Qué cambió respecto al mes pasado (0319) ────────────────────────────────
// Sale de `fn_planilla_variacion`. Los dos lados se los pide esa función a
// `fn_proyeccion_periodo`, así que un periodo ya pagado se compara por lo que se
// PAGÓ —su foto congelada— y no por lo que se recalcularía hoy.
//
// Las etiquetas viven aquí y no en `packages/shared/labels.ts` a propósito: no
// son un catálogo de la base que otra pantalla pueda necesitar, son los códigos
// que devuelve esa función y solo los pinta este panel. Su fuente de verdad es
// la migración 0319; si aparece un aviso nuevo, se agrega ahí y aquí.
type AvisoVariacion =
  | "salio"
  | "entro"
  | "cobra_cero"
  | "empieza_a_cobrar"
  | "trabajo_y_no_cobra"
  | "salto"
  | "cobra_igual_trabajo_menos";

type ExplicaVariacion = "ceso" | "ingreso" | "sueldo_cambio" | "mas_ausencias" | "menos_ausencias";

const AVISO_LABEL: Record<AvisoVariacion, string> = {
  salio: "Ya no aparece",
  entro: "No estaba el mes pasado",
  cobra_cero: "Cobra S/ 0",
  empieza_a_cobrar: "Empieza a cobrar",
  trabajo_y_no_cobra: "Trabajó y no cobra",
  salto: "Salto",
  cobra_igual_trabajo_menos: "Cobra igual, trabajó menos",
};

const EXPLICA_LABEL: Record<ExplicaVariacion, string> = {
  ceso: "cesó",
  ingreso: "ingresó",
  sueldo_cambio: "le cambió el sueldo",
  mas_ausencias: "más ausencias",
  menos_ausencias: "menos ausencias",
};

interface FilaVariacion {
  persona_id: string;
  nombre: string;
  sede: string | null;
  total_actual: number;
  total_previo: number;
  delta: number;
  delta_pct: number | null;
  horas_actual: number;
  horas_previo: number;
  ausencias_actual: number;
  ausencias_previo: number;
  avisos: AvisoVariacion[];
  explica: ExplicaVariacion[];
}

interface Variacion {
  sin_previo: boolean;
  periodo_desde: string;
  periodo_hasta: string;
  periodo_dias?: number;
  previo_desde?: string;
  previo_hasta?: string;
  previo_dias?: number;
  previo_estado?: "abierto" | "pagado";
  previo_fuente?: string;
  periodos_de_distinto_largo?: boolean;
  resumen: {
    personas_actual: number;
    personas_previo: number;
    entraron?: number;
    salieron?: number;
    total_actual?: number;
    total_previo?: number;
    total_delta?: number;
    horas_actual?: number;
    horas_previo?: number;
  };
  filas: FilaVariacion[];
}

interface Feriado {
  fecha: string;
  nombre: string;
}
export interface FeriadoDetalle {
  fecha: string;
  horas_trabajadas: number;
  proporcional_horas: number;
  antes_ingreso: boolean;
  /** Desde la 0276 · lo que ese feriado devengó, SIN redondear. Quien lo
   *  muestre redondea: la boleta lo mete crudo en la base de provisión. */
  monto?: number;
}
export interface Movimiento {
  id: string;
  tipo: "bono" | "descuento";
  concepto: string;
  monto: number;
}
export interface Fila {
  persona_id: string;
  nombre: string;
  sede: string;
  estado: string;
  rango: string | null;
  salario_ref: number | null;
  // Si NO está en planilla —locador por honorarios— la fila no muestra la
  // categoría de la escala: la escala es de trabajadores, y decir que ocupa una
  // es parte de lo que desnaturaliza una locación de servicios (0182). El dato
  // de `rango` se conserva porque es de donde sale cuánto se le transfiere.
  en_planilla: boolean | null;
  // Ya viaja en el JSON de fn_planilla_calcular desde la 0117; se expone acá
  // (0322) para que la boleta pueda distinguir a un practicante de un RxH —
  // los dos tienen en_planilla=false, pero no son el mismo documento.
  tipo_vinculo: string | null;
  horas_mes: number;
  dias_trabajados: number;
  dias_pendientes: number;
  horas_sin_salario: number;
  dias_vacaciones: number;   // 0100 — por qué está en cero
  dias_laborables: number;   // 0100 — 0 = no tiene horario asignado
  pago_base: number;
  // Desglose legal del pago base (0104, recalculado por la 0105). NULL cuando
  // falta la básica legal o la puntuación del mes: entonces la boleta no parte
  // la fila. basica_legal_prop + complemento_variable === pago_base, siempre.
  basica_legal_prop: number | null;
  complemento_variable: number | null;
  // 0105 — puntuación de rendimiento del mes (0–100) y la etiqueta que se eligió
  // para el concepto ESE mes. La etiqueta es un dato, no código: puede cambiar de
  // un periodo a otro y cada pago guarda con qué nombre se emitió.
  // El defecto es 100, y al 100% la fórmula devuelve el salario del rango: por eso
  // activar esto no le mueve el sueldo a nadie. rendimiento_por_defecto distingue
  // «nadie lo ha puntuado» de «alguien escribió 100».
  sueldo_base_legal: number | null;
  rendimiento_pct: number | null;
  rendimiento_por_defecto: boolean | null;
  complemento_etiqueta: string | null;
  fecha_ingreso: string;
  feriados_detalle: FeriadoDetalle[];
  monto_feriados: number;
  feriados_no_corresponde: number;
  objetivos_cumplidos: number | null;
  objetivos_total: number | null;
  monto_plus: number;
  bajo_desempeno: boolean;
  feriados_sin_salario: number;
  con_hijos: boolean;
  asignacion_familiar: number;
  // Los dos términos que la 0110 metió en el 'total' y que hasta el 2026-07-31
  // NO estaban declarados aquí ni impresos en la boleta. Eso hacía que el total
  // no cuadrara con sus propias líneas: la boleta de Danixa sumaba S/76.67 en lo
  // visible y remataba en S/71.84, con S/4.83 de descuento de pensión aplicados
  // y sin una línea que los nombrara. Son opcionales porque una base sin la 0110
  // pegada no los devuelve, y `undefined > 0` es false, así que la boleta
  // simplemente no dibuja la fila en vez de escribir «S/ NaN».
  monto_movilidad?: number;
  movilidad_diaria?: number;
  // La 0120 metió la educación en el 'total' del SQL y la boleta no la imprimía:
  // el mismo agujero que la 0110 abrió con la movilidad, y con la misma
  // consecuencia — un dinero que se paga y que la persona no puede explicar.
  // `instituciones_educacion` viene de la 0150 y trae los nombres separados por
  // ' · ' cuando hay más de un comprobante vigente.
  monto_educacion?: number;
  instituciones_educacion?: string | null;
  // Los dos de la 0236, con los que la boleta explica un cero en vez de borrar la
  // línea. Opcionales y leídos con `?? false`: una base sin la 0236 pegada no los
  // devuelve, y entonces la boleta se comporta como antes — no dibuja la fila —
  // en vez de escribir una explicación falsa.
  educacion_registrada?: boolean;
  educacion_sin_comprobante?: boolean;
  descuento_afp?: number;
  tasa_afp?: number;
  regimen_pension?: string | null;
  tasa_es_del_regimen?: boolean;
  // El aporte de EsSalud que paga CAYLA (0116). NO se descuenta al trabajador y no
  // entra en 'total': el 9% es íntegramente de cargo del empleador (Ley 26790 art. 6).
  // 'essalud_es_piso' es true cuando la persona devengó MENOS que la RMV y el aporte
  // salió del piso legal, no de su sueldo — sin ese dato la cifra no se puede explicar
  // (alguien que ganó S/36.96 genera S/101.70 de EsSalud).
  base_essalud?: number;
  aporte_essalud?: number;
  essalud_tasa?: number;
  essalud_es_piso?: boolean;
  bonos: number;
  descuentos: number;
  movimientos: Movimiento[];
  provision_gratificacion: number;
  // Ley 30334: el 9 % que ya no va a EsSalud y se le entrega a la persona. Llega
  // opcional porque una base sin la 0134 aplicada no manda la clave, y la boleta
  // tiene que seguir saliendo igual que antes en vez de imprimir «NaN».
  provision_bonif_extraordinaria?: number;
  provision_cts: number;
  provision_vacaciones: number;
  provision_total: number;
  // Sobretiempo (0185): SOLO el recargo del 25 % / 35 %, no la hora completa —
  // las horas ya están dentro de pago_base. `horas_sobretiempo` son las horas
  // que excedieron las 48 semanales; `monto_sobretiempo` es lo que cuesta el
  // recargo sobre ellas. Opcionales porque una base sin la 0185 pegada no manda
  // las claves, y la boleta tiene que seguir saliendo igual que antes.
  monto_sobretiempo?: number;
  horas_sobretiempo?: number;
  sobretiempo_desde?: string | null;
  sobretiempo_hasta?: string | null;
  // Descanso semanal trabajado (0280): también SOLO el recargo —el 100 % del
  // art. 3 del D. Leg. 713—, porque las horas de ese día ya están en pago_base.
  // `descanso_semanal_dias` es cuántas veces se cerró un ciclo de siete días
  // sin descansar, no cuántos días se trabajó. Opcionales por lo mismo que las
  // de la 0185: una base sin la 0280 pegada no manda las claves y la boleta
  // tiene que seguir saliendo igual que antes.
  monto_descanso_semanal?: number;
  descanso_semanal_dias?: number;
  descanso_semanal_desde?: string | null;
  descanso_semanal_hasta?: string | null;
  // Retención de renta de cuarta categoría (0245), solo para quien cobra por
  // recibo por honorarios. `retencion_4ta_base` es el importe por el que tiene
  // que emitir su recibo —NO el total, que ya es el neto— y por eso viaja: sin
  // él la boleta no puede decirle a un locador por cuánto facturar.
  // `retencion_4ta_sin_configurar` es el aviso: pasa el tope y nadie eligió modo.
  // Todas opcionales, como las de la 0185 y la 0236: una base sin la 0245 pegada
  // no manda las claves y la pantalla se comporta exactamente como antes.
  // ¿Su pago depende de las horas que registre? (0250). Es de PRESENTACIÓN: no
  // mueve un céntimo — `pago_base` ya se calcula distinto desde la 0047. Viaja
  // para que la boleta pueda distinguir dos locadores que cobran al revés y
  // dejar de ponerles la misma etiqueta.
  sueldo_fijo?: boolean;
  // Los días de descanso médico que asume CAYLA (0254). Son de PRESENTACIÓN:
  // el importe YA está dentro de `pago_base` —igual que los de vacaciones desde
  // la 0177— y no se suma otra vez en ningún sitio. Viajan para que la boleta
  // pueda sacarlos a su propia línea, porque si no, la de básica promete «por
  // tus horas del periodo» sobre un importe que incluye días que no se
  // trabajaron. Opcionales: sin la 0254 pegada, la boleta se comporta como antes.
  monto_descanso_medico?: number;
  dias_descanso_medico_pagados?: number;
  retencion_4ta?: number;
  retencion_4ta_base?: number;
  retencion_4ta_modo?: string | null;
  retencion_4ta_constancia_hasta?: string | null;
  retencion_4ta_sin_configurar?: boolean;
  total: number; // ya incluye + asignación + movilidad + sobretiempo − pensión + bonos − descuentos − retención de 4ta
}
export interface FactoresProvision {
  gratificacion: number;
  cts: number;
  vacaciones: number;
}
export interface Proyeccion {
  periodo_id?: string;
  estado?: "abierto" | "pagado";
  pagado_at?: string | null;
  simulacion: boolean;
  fecha_ini: string;
  fecha_fin: string;
  anio_etiqueta: number;
  mes_etiqueta: number;
  dias: number;
  base_horas: number;
  feriados: Feriado[];
  factores_provision: FactoresProvision;
  asignacion_monto: number;
  filas: Fila[];
}
// Lo que se elige en el desplegable. "vacaciones" y "otros" NO son tipos nuevos
// en la base: son etiquetas (categoría) sobre un movimiento que suma, igual que
// un bono. La aritmética de la planilla no cambia — para restar, siempre Descuento.
// gratificacion/cts tampoco son tipos nuevos en la base: son categorías sobre un
// bono. Su MONTO lo calcula el sistema (fn_grati_cts_periodo) para el periodo que
// contiene la fecha de pago legal, y se autocompleta al elegirlas.
type ClaseMov = "bono" | "descuento" | "vacaciones" | "gratificacion" | "cts" | "otros";
const CLASE_A_TIPO: Record<ClaseMov, "bono" | "descuento"> = {
  bono: "bono", descuento: "descuento", vacaciones: "bono", gratificacion: "bono", cts: "bono", otros: "bono",
};
const CLASE_A_CATEGORIA: Record<ClaseMov, string | null> = {
  bono: null, descuento: null, vacaciones: "vacaciones", gratificacion: "gratificacion", cts: "cts", otros: "otros",
};
// Nombres LEGALES, revertido el 2026-07-28 por decisión de Felipe. Antes decían
// «Bono Gratitud» y «Bono Comprometidos» para ser discretos, y eso era un riesgo:
// la gratificación y la CTS son derechos de ley, no liberalidades. Llamarlas bono
// disfraza una obligación como un regalo, y ante SUNAFIL se lee como intento de
// ocultar un pago obligatorio — exactamente lo contrario del blindaje que se
// buscaba con el resto del trabajo de hoy.
// Por dentro nada cambia: la categoría, el cálculo (fn_grati_cts_periodo) y el
// candado siguen igual. Solo cambia el nombre que se escribe y se lee.
const CLASE_LABEL: Record<ClaseMov, string> = {
  bono: "Bono", descuento: "Descuento", vacaciones: "Vacaciones", gratificacion: "Gratificación", cts: "CTS", otros: "Otros",
};
const CLASE_PLACEHOLDER: Record<ClaseMov, string> = {
  bono: "ej. reconocimiento del mes",
  descuento: "ej. adelanto quincenal",
  vacaciones: "ej. Vacaciones 22–28 jul 2026",
  gratificacion: "el sistema lo calcula",
  cts: "el sistema lo calcula",
  otros: "ej. reintegro",
};

interface MovForm {
  tipo: ClaseMov;
  concepto: string;
  monto: string;
  /** CAMBIO 0305 — De qué periodo YA PAGADO viene esta corrección. Vacío es lo
   *  normal: el movimiento es de este mes y no corrige nada. */
  origen: string;
}
// Grati/CTS que toca en el periodo, calculado por fn_grati_cts_periodo.
interface GratiCts {
  gratiAplica: boolean;
  gratiConcepto: string;
  ctsAplica: boolean;
  ctsConcepto: string;
  porPersona: Record<string, { grati: number; cts: number }>;
}

// Una liquidación YA PAGADA de alguien que cesó dentro de este periodo, tal
// como la devuelve fn_liquidaciones_del_periodo (0210).
//
// `cobro_del_periodo` es la parte que SE SOLAPA con la planilla: el sueldo del
// mes que esa liquidación ya cubrió. El resto del total son las truncas, que la
// planilla no calcula y por tanto no duplica.
interface Liquidada {
  cobro_del_periodo: number;
  total_liquidacion: number;
  pagada_el: string;
  fecha_cese: string;
}

function etiquetaPeriodo(p: PeriodoInfo): string {
  return `${MESES_LARGO[p.mes_etiqueta - 1]} ${p.anio_etiqueta} · ${fechaCorta(p.fecha_ini)} → ${fechaCorta(p.fecha_fin)}`;
}

// Columnas de la tabla principal. Se usa como colSpan en las filas de estado
// vacío: si no coincide con los <th> reales, esas filas se dibujan torcidas.
// Contadas a mano el 2026-08-06 tras sacar Objetivos, Rendim. y Plus (mig 0171):
// Nombre · Sede · Rango y salario · Horas · Pago base · Feriados ·
// Asig. familiar · Básica legal · Bonos · Descuentos · Total.
const COLS = 11;

// ── Tabla de planilla (compartida entre periodo oficial y simulador) ─────────
// Componente a nivel de módulo: si viviera dentro de PlanillaPage se
// remontaría en cada render y los inputs perderían el foco al tipear.
// Por qué alguien aparece en S/0.00. Tres situaciones que hasta la 0100 se veían
// idénticas, y solo una de ellas es inofensiva. La razón se decide AQUÍ y en
// ningún otro sitio: si mañana hay una cuarta, se agrega en un solo lugar.
type EstadoFiltro = "activos" | "inactivos" | "todos";
function pasaEstado(f: Fila, e: EstadoFiltro): boolean {
  if (e === "todos") return true;
  return e === "activos" ? f.estado === "activo" : f.estado !== "activo";
}

function razonDelCero(f: Fila): { texto: string; grave: boolean } | null {
  if (f.total > 0 || f.horas_mes > 0) return null;
  if (f.dias_vacaciones > 0) {
    return { texto: `De vacaciones (${f.dias_vacaciones} días del periodo)`, grave: false };
  }
  if (f.dias_laborables === 0) {
    return { texto: "Sin horario asignado — el sistema no sabe qué días le tocaba venir", grave: true };
  }
  return { texto: `No marcó ningún día, y le tocaban ${f.dias_laborables}`, grave: true };
}

function TablaPlanilla(props: {
  filas: Fila[];
  simulacion: boolean;
  pagado: boolean;
  sedeFiltro: string;
  periodoId?: string;
  ocupado?: boolean;
  objEdit?: Record<string, string>;
  onObjChange?: (personaId: string, valor: string) => void;
  onObjBlur?: (f: Fila) => void;
  guardandoObj?: string | null;
  baseEdit?: Record<string, string>;
  onBaseChange?: (personaId: string, valor: string) => void;
  onBaseBlur?: (f: Fila) => void;
  guardandoBase?: string | null;
  rendEdit?: Record<string, string>;
  onRendChange?: (personaId: string, valor: string) => void;
  onRendBlur?: (f: Fila) => void;
  guardandoRend?: string | null;
  movAbierto?: string | null;
  onToggleMov?: (personaId: string) => void;
  movForm?: MovForm;
  onMovForm?: (mf: MovForm) => void;
  onAgregarMov?: (f: Fila) => void;
  onQuitarMov?: (m: Movimiento) => void;
  onYaPagado?: (f: Fila) => void;
  /** Quién de este periodo ya cobró su liquidación (0210), por persona_id. */
  liquidadas?: Record<string, Liquidada>;
  guardandoMov?: boolean;
  gc?: GratiCts | null;
  /** CAMBIO 0305 — Periodos ya pagados y anteriores a este, para poder decir de
   *  cuál viene un retroactivo sin escribirlo en el texto del concepto. */
  origenes?: { id: string; etiqueta: string }[];
}) {
  const {
    filas, simulacion, pagado, sedeFiltro, periodoId, ocupado = false,
    objEdit = {}, onObjChange, onObjBlur, guardandoObj = null,
    baseEdit = {}, onBaseChange, onBaseBlur, guardandoBase = null,
    rendEdit = {}, onRendChange, onRendBlur, guardandoRend = null,
    movAbierto = null, onToggleMov, movForm, onMovForm, onAgregarMov, onQuitarMov, onYaPagado,
    liquidadas = {},
    guardandoMov = false, gc = null, origenes = [],
  } = props;
  // Al elegir grati/CTS en el desplegable, autocompleta concepto y el monto que el
  // sistema calculó para esa persona en este periodo. El resto queda manual.
  const alCambiarTipo = (f: Fila, t: ClaseMov) => {
    if ((t === "gratificacion" || t === "cts") && gc) {
      const gp = gc.porPersona[f.persona_id];
      const monto = t === "gratificacion" ? gp?.grati : gp?.cts;
      const concepto = t === "gratificacion" ? gc.gratiConcepto : gc.ctsConcepto;
      // CAMBIO 0305 — `origen` vacío a propósito: una gratificación o una CTS
      // corresponden a la ventana de ESTE periodo, no corrigen un mes anterior.
      // Si alguien venía de marcar un origen y cambia a grati, se limpia.
      onMovForm?.({ tipo: t, concepto: concepto || CLASE_LABEL[t], monto: monto ? String(monto) : "", origen: "" });
    } else {
      onMovForm?.({ ...movForm!, tipo: t });
    }
  };
  const editable = !simulacion;
  const hintPagado = "periodo pagado — reábrelo para modificar";

  const totales = useMemo(
    () =>
      filas.reduce(
        (acc, f) => ({
          pago_base: acc.pago_base + f.pago_base,
          feriados: acc.feriados + f.monto_feriados,
          asignacion: acc.asignacion + f.asignacion_familiar,
          plus: acc.plus + f.monto_plus,
          bonos: acc.bonos + f.bonos,
          descuentos: acc.descuentos + f.descuentos,
          total: acc.total + f.total,
          // ── LO QUE SALE DEL BANCO, que no es el total ────────────────────
          // El total es lo que se le TRANSFIERE a la gente. Además de eso salen
          // de la cuenta de CAYLA tres pagos que se hacen a nombre de la persona
          // o por ella, y que no aparecían sumados en ninguna pantalla:
          //
          //   · el descuento de pensión, que va a la AFP o a la ONP (0110)
          //   · el 9 % de EsSalud, que es de cargo del empleador (0116)
          //   · la retención de renta de 4ta, que va a SUNAT (0245)
          //
          // Y NO se suman las provisiones: ésas se devengan este mes pero se
          // pagan después. Mezclarlas convertiría esta cifra en un híbrido de
          // caja y devengado, que es justo lo que hace difícil de leer el
          // «costo real» de la pantalla de Costos.
          //
          // Los tres llegan opcionales (`?? 0`): una base sin la 0110, la 0116 o
          // la 0245 pegadas no manda la clave, y entonces esta cifra vale lo
          // mismo que el total en vez de decir «NaN».
          pension: acc.pension + (f.descuento_afp ?? 0),
          essalud: acc.essalud + (f.aporte_essalud ?? 0),
          retencion_4ta: acc.retencion_4ta + (f.retencion_4ta ?? 0),
        }),
        { pago_base: 0, feriados: 0, asignacion: 0, plus: 0, bonos: 0, descuentos: 0, total: 0,
          pension: 0, essalud: 0, retencion_4ta: 0 },
      ),
    [filas],
  );
  const saleDelBanco = totales.total + totales.pension + totales.essalud + totales.retencion_4ta;

  return (
    <div className="overflow-x-auto rounded-2xl border border-sand bg-papel">
      <table className="w-full text-sm">
        <thead className="bg-sand/70 text-left text-taupe">
          <tr>
            <th className="px-4 py-2 font-normal">Nombre</th>
            <th className="px-4 py-2 font-normal">Sede</th>
            <th className="px-4 py-2 font-normal">Rango y salario</th>
            <th className="px-4 py-2 font-normal">Horas</th>
            <th className="px-4 py-2 text-right font-normal">Pago base</th>
            <th className="px-4 py-2 text-right font-normal">Feriados</th>
            <th className="px-4 py-2 text-right font-normal">Asig. familiar</th>
            {/* Objetivos, Rendim. y Plus salieron de acá el 2026-08-06 (mig 0171).
                Los objetivos siguen existiendo en /admin/objetivos, pero como
                historial para promover: dejaron de pagar. Y el rendimiento dejó
                de escalar el sueldo — escribir un 80 ahí recortaba una
                remuneración con dos clics, que el art. 30.b de la LPCL prohíbe. */}
            <th className="px-4 py-2 text-right font-normal" title="Remuneración básica legal mensual: la que se declara en PLAME. Vacía = la boleta no imprime esa línea.">
              Básica legal
            </th>
            <th className="px-4 py-2 text-right font-normal">Bonos</th>
            <th className="px-4 py-2 text-right font-normal">Descuentos</th>
            <th className="px-4 py-2 text-right font-normal">Total</th>
          </tr>
        </thead>
        <tbody>
          {filas.length === 0 && (
            <tr>
              <td colSpan={COLS} className="px-4 py-6 text-center text-taupe">
                No hay personas para mostrar en este {simulacion ? "rango" : "periodo"}.
              </td>
            </tr>
          )}
          {filas.map((f) => {
            const totalObj = f.objetivos_total ?? 10;
            const movs = f.movimientos ?? [];
            return (
              <Fragment key={f.persona_id}>
                <tr className={`border-t ${f.horas_sin_salario > 0 ? "bg-rojo/10" : ""}`}>
                  <td className="px-4 py-2">
                    {f.nombre}
                    {f.estado !== "activo" && (
                      <span className="ml-1.5 whitespace-nowrap rounded-full bg-sand px-2 py-0.5 text-xs text-taupe">
                        ya no está
                      </span>
                    )}
                    {editable && f.total > 0 && onYaPagado && (
                      <>
                        <br />
                        <button
                          onClick={() => onYaPagado(f)}
                          disabled={ocupado}
                          title="Registrar que ya se le pagó fuera de la planilla"
                          className="text-xs text-taupe underline decoration-taupe/30 underline-offset-2 hover:text-tinta hover:decoration-tinta disabled:opacity-50"
                        >
                          💸 Ya le pagué aparte
                        </button>
                      </>
                    )}
                    {/* CAMBIO 0210 · El aviso que faltaba. Hasta hoy esta fila
                        solo decía «ya no está», y con eso se cerró el periodo de
                        julio con seis personas dentro que YA habían cobrado su
                        liquidación: S/1,145.87 registrados dos veces.
                        Se muestra aunque el total sea 0 —es decir, aunque ya se
                        haya apretado el botón— porque entonces confirma que está
                        resuelto en vez de dejar la duda. */}
                    {(() => {
                      const liq = liquidadas[f.persona_id];
                      if (!liq) return null;
                      // CAMBIO 0244 · La condición de «resuelto» es la MISMA que usa el
                      // freno del cierre, y hasta hoy no lo era. Este cartel nació con la
                      // 0243, cuando bastaba con que la fila quedara en cero; la 0244
                      // cambió la regla en la base a «los descuentos cubren lo que la
                      // liquidación pagó de este mes», y esta línea se quedó atrás.
                      //
                      // La diferencia no es teórica: si después de congelar entra algo al
                      // periodo —un feriado posterior al cese, una jornada corregida— la
                      // fila vuelve a tener total, la base ya deja cerrar, y esta pantalla
                      // seguía pidiendo en ámbar que se descontara un saldo que SÍ es suyo.
                      const resuelto = f.total <= 0 || f.descuentos >= liq.cobro_del_periodo;
                      return (
                        <p className={`mt-0.5 text-xs ${resuelto ? "text-taupe" : "text-ambar"}`}>
                          {resuelto ? "✓ " : "⚠ "}
                          Ya cobró su liquidación el {fechaCorta(liq.pagada_el)} ·{" "}
                          {formatSoles(liq.cobro_del_periodo)} de este mes
                          {resuelto
                            ? " — ya está descontado aquí."
                            : " — si no vas a transferirle otra vez, usa «Ya le pagué aparte»."}
                        </p>
                      );
                    })()}
                    {(() => {
                      const r = razonDelCero(f);
                      if (!r) return null;
                      return (
                        <p className={`mt-0.5 text-xs ${r.grave ? "text-ambar" : "text-taupe"}`}>
                          {r.grave ? "⚠ " : ""}{r.texto}
                        </p>
                      );
                    })()}
                    {/* EL AVISO DE LA 0245. Un locador cuyo recibo del mes pasa
                        el tope de S/1,500 y a quien nadie le eligió modo de
                        retención. NO retiene por su cuenta —eso le cambiaría el
                        neto a alguien sin que nadie lo decidiera— pero deja de
                        ser invisible: CAYLA es agente de retención y no retener
                        cuando toca es infracción del art. 177 del Código
                        Tributario, con multa del 50 % del tributo no retenido.
                        Se configura en Equipo, no acá: es un dato de la persona,
                        no de este mes. */}
                    {f.retencion_4ta_sin_configurar && (
                      <p className="mt-0.5 text-xs text-ambar">
                        ⚠ Su recibo pasa de S/1,500 y no tiene configurada la retención de 4ta —
                        decídelo en Equipo (o confirma que tiene constancia de suspensión).
                      </p>
                    )}
                    {!simulacion && periodoId && (
                      <>
                        <br />
                        <Link
                          href={`/admin/planilla/boleta?periodo=${periodoId}&persona=${f.persona_id}`}
                          target="_blank"
                          className="text-xs text-taupe underline decoration-taupe/30 underline-offset-2 hover:text-tinta hover:decoration-tinta"
                        >
                          🧾 Ver boleta
                        </Link>
                      </>
                    )}
                  </td>
                  <td className="px-4 py-2">{f.sede}</td>
                  <td className="px-4 py-2">
                    {f.salario_ref !== null ? (
                      <span className="whitespace-nowrap">
                        {f.en_planilla === false
                          ? "Honorarios"
                          : ((f.rango && (RANGO_LABEL[f.rango] ?? f.rango)) ?? "—")}
                        {" · "}{formatSoles(f.salario_ref)}
                      </span>
                    ) : (
                      <span className="text-rojo">Sin salario</span>
                    )}
                    {f.horas_sin_salario > 0 && (
                      <p className="mt-1 text-xs text-rojo">
                        {fmtHoras(f.horas_sin_salario)} sin salario asignado — asígnale rango en Equipo
                      </p>
                    )}
                    {f.feriados_sin_salario > 0 && (
                      <p className="mt-1 text-xs text-rojo">
                        {f.feriados_sin_salario} feriado(s) sin salario asignado ese día — el premio no se pudo calcular
                      </p>
                    )}
                  </td>
                  <td className="px-4 py-2">
                    <span className="whitespace-nowrap">{fmtHoras(f.horas_mes)}</span>
                    {f.dias_pendientes > 0 && (
                      <span
                        className="ml-2 whitespace-nowrap rounded-full bg-ambar/15 px-2 py-0.5 text-xs text-ambar"
                        title="Días auto-cerrados sin revisar — corrígelos en Correcciones"
                      >
                        {f.dias_pendientes} pend.
                      </span>
                    )}
                  </td>
                  <td className="px-4 py-2 text-right">{formatSoles(f.pago_base)}</td>
                  <td
                    className="px-4 py-2 text-right"
                    title={
                      f.feriados_detalle.length > 0
                        ? f.feriados_detalle
                            .map((d) =>
                              d.antes_ingreso
                                ? `${fechaCorta(d.fecha)}: no corresponde (anterior al ingreso)`
                                : `${fechaCorta(d.fecha)}: ${d.horas_trabajadas} h trabajadas + ${d.proporcional_horas} h proporcionales`,
                            )
                            .join("\n")
                        : undefined
                    }
                  >
                    {f.monto_feriados > 0 ? formatSoles(f.monto_feriados) : <span className="text-taupe/50">—</span>}
                    {f.feriados_no_corresponde > 0 && (
                      <p className="mt-1 text-xs text-ambar">
                        {f.feriados_no_corresponde} feriado{f.feriados_no_corresponde === 1 ? "" : "s"} no le
                        {f.feriados_no_corresponde === 1 ? " corresponde" : " corresponden"} — ingresó {fechaDiaMes(f.fecha_ingreso)}
                      </p>
                    )}
                  </td>
                  <td className="px-4 py-2 text-right whitespace-nowrap" title={f.con_hijos ? "Asignación familiar (con hijos)" : undefined}>
                    {f.asignacion_familiar > 0 ? <>👶 {formatSoles(f.asignacion_familiar)}</> : <span className="text-taupe/50">—</span>}
                  </td>
                  {/* La celda de Objetivos salió el 2026-08-06 (mig 0171). Los
                      objetivos se cargan en /admin/objetivos, que es donde
                      pertenecen ahora que son historial de promoción y no un
                      concepto de pago. Cargarlos desde la planilla mezclaba las
                      dos cosas y era justo lo que había que separar. */}
                  {/* Básica legal — es de la PERSONA, no del periodo, así que se
                      puede editar incluso con el periodo pagado. Ojo: cambiarla
                      cambia el desglose de sus boletas pasadas (ver 0106). */}
                  <td className="px-4 py-2 text-right">
                    {editable ? (
                      <div className="flex items-center justify-end gap-1 whitespace-nowrap">
                        <input
                          type="number"
                          min={0}
                          step={10}
                          placeholder="—"
                          value={baseEdit[f.persona_id] ?? (f.sueldo_base_legal ?? "")}
                          onChange={(e) => onBaseChange?.(f.persona_id, e.target.value)}
                          onBlur={() => onBaseBlur?.(f)}
                          disabled={ocupado}
                          className="w-20 rounded-lg border px-2 py-1 text-right disabled:opacity-50"
                        />
                        {guardandoBase === f.persona_id && <span className="text-xs text-taupe">…</span>}
                      </div>
                    ) : f.sueldo_base_legal !== null && f.sueldo_base_legal !== undefined ? (
                      formatSoles(f.sueldo_base_legal)
                    ) : (
                      <span className="text-taupe/50">—</span>
                    )}
                  </td>
                  {/* Las celdas de Rendimiento y Plus salieron el 2026-08-06
                      junto con sus columnas (mig 0171). */}
                  <td className="px-4 py-2 text-right">
                    {f.bonos > 0 ? (
                      <span className="whitespace-nowrap text-verde">+{formatSoles(f.bonos)}</span>
                    ) : (
                      <span className="text-taupe/50">—</span>
                    )}
                  </td>
                  <td className="px-4 py-2 text-right">
                    <div className="flex items-center justify-end gap-2 whitespace-nowrap">
                      {f.descuentos > 0 ? (
                        <span className="text-rojo">−{formatSoles(f.descuentos)}</span>
                      ) : (
                        <span className="text-taupe/50">—</span>
                      )}
                      {/* La retención de 4ta va SEPARADA del monto de arriba y
                          no sumada a él: aquel son los movimientos que alguien
                          escribió a mano y este lo calcula el sistema. Fundirlos
                          haría que el botón ± no cuadrara con su propia columna.
                          Sin ella el total no se explicaría desde esta tabla,
                          que es lo que se mira antes de transferir. */}
                      {(f.retencion_4ta ?? 0) > 0 && (
                        <span
                          className="rounded-full bg-rojo/10 px-2 py-0.5 text-xs text-rojo"
                          title="Retención de Impuesto a la Renta de 4ta categoría (8 %). Se paga a SUNAT a nombre de la persona."
                        >
                          4ta −{formatSoles(f.retencion_4ta ?? 0)}
                        </span>
                      )}
                      {editable && (
                        <button
                          onClick={() => onToggleMov?.(f.persona_id)}
                          disabled={ocupado}
                          title="Ver y editar bonos y descuentos"
                          aria-label={`Bonos y descuentos de ${f.nombre}`}
                          className={`rounded-lg border px-2 py-0.5 text-xs hover:bg-sand/50 disabled:opacity-50 ${movAbierto === f.persona_id ? "bg-sand/60" : ""}`}
                        >
                          ±
                        </button>
                      )}
                    </div>
                  </td>
                  <td className="px-4 py-2 text-right font-bold">{formatSoles(f.total)}</td>
                </tr>
                {editable && movAbierto === f.persona_id && movForm && (
                  <tr className="border-t bg-sand/20">
                    <td colSpan={COLS} className="px-4 py-3">
                      <div className="max-w-2xl">
                        <p className="mb-2 text-sm font-medium">Bonos y descuentos — {f.nombre}</p>
                        {pagado && (
                          <p className="mb-2 text-xs text-taupe">🔒 {hintPagado}</p>
                        )}
                        {movs.length === 0 ? (
                          <p className="mb-2 text-sm text-taupe">Sin bonos ni descuentos en este periodo.</p>
                        ) : (
                          <ul className="mb-2 grid gap-1">
                            {movs.map((m) => (
                              <li key={m.id} className="flex items-center justify-between gap-3 text-sm">
                                <span>
                                  <span className={m.tipo === "bono" ? "text-verde" : "text-rojo"}>
                                    {m.tipo === "bono" ? "+" : "−"}{formatSoles(m.monto)}
                                  </span>{" "}
                                  <span className="text-taupe">({m.tipo})</span> — {m.concepto}
                                </span>
                                <button
                                  onClick={() => onQuitarMov?.(m)}
                                  disabled={pagado || guardandoMov || ocupado}
                                  title={pagado ? hintPagado : "Quitar"}
                                  className="text-xs text-rojo hover:underline disabled:opacity-50"
                                >
                                  ×
                                </button>
                              </li>
                            ))}
                          </ul>
                        )}
                        <div className="flex flex-wrap items-end gap-2 border-t pt-2">
                          <label className="flex flex-col gap-1 text-xs text-taupe">
                            Tipo
                            <select
                              value={movForm.tipo}
                              onChange={(e) => alCambiarTipo(f, e.target.value as ClaseMov)}
                              disabled={pagado || guardandoMov}
                              title={pagado ? hintPagado : undefined}
                              className="rounded-lg border bg-crema px-2 py-1.5 text-sm text-tinta disabled:opacity-50"
                            >
                              <option value="bono">Bono</option>
                              <option value="descuento">Descuento</option>
                              <option value="vacaciones">Vacaciones</option>
                              {/* Solo en el periodo que corresponde (fecha de pago legal dentro del rango) */}
                              {gc?.gratiAplica && <option value="gratificacion">{CLASE_LABEL.gratificacion}</option>}
                              {gc?.ctsAplica && <option value="cts">{CLASE_LABEL.cts}</option>}
                              <option value="otros">Otros</option>
                            </select>
                          </label>
                          <label className="flex flex-col gap-1 text-xs text-taupe">
                            Concepto
                            <input
                              value={movForm.concepto}
                              onChange={(e) => onMovForm?.({ ...movForm, concepto: e.target.value })}
                              placeholder={CLASE_PLACEHOLDER[movForm.tipo]}
                              disabled={pagado || guardandoMov}
                              title={pagado ? hintPagado : undefined}
                              className="w-52 rounded-lg border px-2 py-1.5 text-sm text-tinta disabled:opacity-50"
                            />
                          </label>
                          <label className="flex flex-col gap-1 text-xs text-taupe">
                            Monto (S/)
                            <input
                              type="number"
                              min={0.01}
                              step={0.01}
                              value={movForm.monto}
                              onChange={(e) => onMovForm?.({ ...movForm, monto: e.target.value })}
                              placeholder="0.00"
                              disabled={pagado || guardandoMov}
                              title={pagado ? hintPagado : undefined}
                              className="w-24 rounded-lg border px-2 py-1.5 text-right text-sm text-tinta disabled:opacity-50"
                            />
                          </label>
                          {/* CAMBIO 0305 — Solo aparece si HAY meses ya pagados
                              antes de este. En el primer periodo de la historia
                              no hay nada que corregir, y un desplegable vacío
                              solo invita a preguntarse qué falta. */}
                          {origenes.length > 0 && (
                            <label className="flex flex-col gap-1 text-xs text-taupe">
                              ¿Corrige un mes anterior?
                              <select
                                value={movForm.origen}
                                onChange={(e) => onMovForm?.({ ...movForm, origen: e.target.value })}
                                disabled={pagado || guardandoMov}
                                title={pagado ? hintPagado : "Si esto paga una diferencia de un mes ya cerrado, dilo acá: queda registrado de dónde viene."}
                                className="rounded-lg border px-2 py-1.5 text-sm text-tinta disabled:opacity-50"
                              >
                                <option value="">No — es de este mes</option>
                                {origenes.map((o) => (
                                  <option key={o.id} value={o.id}>{o.etiqueta}</option>
                                ))}
                              </select>
                            </label>
                          )}
                          <button
                            onClick={() => onAgregarMov?.(f)}
                            disabled={pagado || guardandoMov || ocupado}
                            title={pagado ? hintPagado : undefined}
                            className="rounded-lg bg-tinta px-3 py-1.5 text-sm font-medium text-crema disabled:opacity-50"
                          >
                            {guardandoMov ? "Guardando…" : "Agregar"}
                          </button>
                        </div>
                      </div>
                    </td>
                  </tr>
                )}
              </Fragment>
            );
          })}
        </tbody>
        {filas.length > 0 && (
          <tfoot>
            <tr className="border-t bg-sand/50">
              <td className="px-4 py-2 font-medium" colSpan={4}>
                Total ({filas.length} {filas.length === 1 ? "persona" : "personas"}
                {sedeFiltro !== "todas" ? ` — ${sedeFiltro}` : ""})
              </td>
              <td className="px-4 py-2 text-right font-medium">{formatSoles(totales.pago_base)}</td>
              <td className="px-4 py-2 text-right font-medium">{formatSoles(totales.feriados)}</td>
              <td className="px-4 py-2 text-right font-medium">{formatSoles(totales.asignacion)}</td>
              {/* Básica legal: no se suma. Es la remuneración que se declara en
                  PLAME de cada persona, no un concepto que se pague acá. */}
              <td className="px-4 py-2" />
              <td className="px-4 py-2 text-right font-medium">
                {totales.bonos > 0 ? <span className="text-verde">+{formatSoles(totales.bonos)}</span> : <span className="text-taupe/50">—</span>}
              </td>
              <td className="px-4 py-2 text-right font-medium">
                {totales.descuentos > 0 ? <span className="text-rojo">−{formatSoles(totales.descuentos)}</span> : <span className="text-taupe/50">—</span>}
              </td>
              <td className="px-4 py-2 text-right font-bold">{formatSoles(totales.total)}</td>
            </tr>
            {/* ── LA SEGUNDA FILA: LO QUE HAY QUE TENER EN LA CUENTA ──────────
                Va como fila aparte y no como columna nueva porque no es del
                mismo tipo que las de arriba: aquéllas son conceptos POR PERSONA
                y ésta es una suma de la empresa.

                Se muestra solo cuando hay algo que agregar. Si no hay pensión,
                EsSalud ni retención —una simulación, o un periodo de puros
                locadores sin configurar— esta cifra sería idéntica al total y
                una fila que repite el número de arriba es ruido.

                Y no reemplaza al total: son dos preguntas distintas. Arriba,
                cuánto le llega a la gente. Abajo, cuánto sale de la cuenta. */}
            {saleDelBanco > totales.total && (
              <tr className="border-t bg-sand/50">
                <td className="px-4 py-2 text-taupe" colSpan={COLS - 1}>
                  Sale de la cuenta de CAYLA
                  <span className="block text-xs">
                    el total de arriba + {formatSoles(totales.pension)} de pensión +{" "}
                    {formatSoles(totales.essalud)} de EsSalud
                    {totales.retencion_4ta > 0 && <> + {formatSoles(totales.retencion_4ta)} de retención de 4ta</>}
                    {" "}· no incluye provisiones, que se pagan después
                  </span>
                </td>
                <td className="px-4 py-2 text-right font-bold">{formatSoles(saleDelBanco)}</td>
              </tr>
            )}
          </tfoot>
        )}
      </table>
    </div>
  );
}

export default function PlanillaPage() {
  const router = useRouter();
  const rol = useRolActual();
  const puedeVer = puedeVerPlanilla(rol);
  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  // Periodos
  const [periodos, setPeriodos] = useState<PeriodoInfo[] | null>(null);
  const [errorPeriodos, setErrorPeriodos] = useState<string | null>(null);
  const [periodoSel, setPeriodoSel] = useState<string | null>(null);
  const [guardandoPeriodo, setGuardandoPeriodo] = useState(false);
  // Desvíos de un periodo YA pagado: qué personas cambiaron de cifra desde el pago.
  const [desvios, setDesvios] = useState<Desvio[] | null>(null);
  const [variacion, setVariacion] = useState<Variacion | null>(null);
  const [mostrandoVariacion, setMostrandoVariacion] = useState(false);
  const [variacionTodas, setVariacionTodas] = useState(false);
  const [guardandoBono, setGuardandoBono] = useState(false);

  // Crear periodo (primero / encadenado)
  const [primerIni, setPrimerIni] = useState("");
  const [primerFin, setPrimerFin] = useState("");
  const [mostrandoNuevo, setMostrandoNuevo] = useState(false);
  const [nuevoFin, setNuevoFin] = useState("");
  const [creandoPeriodo, setCreandoPeriodo] = useState(false);

  // Proyección del periodo seleccionado
  const [proy, setProy] = useState<Proyeccion | null>(null);
  const [gc, setGc] = useState<GratiCts | null>(null);
  // Quién de este periodo ya cobró su liquidación (0210), indexado por
  // persona_id. `{}` significa «no hay ninguna», que es lo normal casi todos los
  // meses; nunca null, para que la búsqueda por clave no tenga que defenderse.
  const [liquidadas, setLiquidadas] = useState<Record<string, Liquidada>>({});
  const [cargando, setCargando] = useState(false);
  const [errorCarga, setErrorCarga] = useState<string | null>(null);
  const { avisar } = useToast();
  const reqId = useRef(0); // "última carga gana": descarta respuestas fuera de orden

  const [sedeFiltro, setSedeFiltro] = useState("todas");
  // Activos / ya no están / todos. Arranca en "activos" porque es lo que se mira
  // el 99 % de las veces; el aviso de abajo cubre el 1 % peligroso.
  const [estadoFiltro, setEstadoFiltro] = useState<"activos" | "inactivos" | "todos">("activos");
  // RxH (en_planilla === false) vive en su propia pestaña: no son trabajadores
  // en planilla, son locadores por honorarios, y hasta ahora salían mezclados
  // como filas de la misma tabla con "Honorarios" en vez de rango.
  const [tablaTab, setTablaTab] = useState<"planilla" | "honorarios">("planilla");

  // Objetivos: valor en edición por persona (solo las filas tocadas)
  const [objEdit, setObjEdit] = useState<Record<string, string>>({});
  const [baseEdit, setBaseEdit] = useState<Record<string, string>>({});
  const [guardandoBase, setGuardandoBase] = useState<string | null>(null);
  const [rendEdit, setRendEdit] = useState<Record<string, string>>({});
  const [guardandoRend, setGuardandoRend] = useState<string | null>(null);
  const [guardandoObj, setGuardandoObj] = useState<string | null>(null);

  // Bonos / descuentos: panel abierto + mini-form
  const [movAbierto, setMovAbierto] = useState<string | null>(null);
  const [movForm, setMovForm] = useState<MovForm>({ tipo: "bono", concepto: "", monto: "", origen: "" });
  const [guardandoMov, setGuardandoMov] = useState(false);

  // Provisiones (plegable)
  const [mostrandoProvisiones, setMostrandoProvisiones] = useState(false);

  // Simulador (plegable, solo lectura)
  const [mostrandoSim, setMostrandoSim] = useState(false);
  const [simIni, setSimIni] = useState("");
  const [simFin, setSimFin] = useState("");
  const [simProy, setSimProy] = useState<Proyeccion | null>(null);
  const [simCargando, setSimCargando] = useState(false);
  const [simError, setSimError] = useState<string | null>(null);
  const reqIdSim = useRef(0);

  // Gestión de feriados (lista del AÑO del periodo, no solo del rango)
  const [mostrandoFeriados, setMostrandoFeriados] = useState(false);
  const [feriadosAnio, setFeriadosAnio] = useState<Feriado[] | null>(null);
  const [errorFeriados, setErrorFeriados] = useState<string | null>(null);
  const [nuevoFeriado, setNuevoFeriado] = useState({ fecha: "", nombre: "" });
  const [guardandoFeriado, setGuardandoFeriado] = useState(false);

  // Si el rol no llega en ~6 s, avisar en vez de un "Cargando…" eterno
  const [rolDemorado, setRolDemorado] = useState(false);
  useEffect(() => {
    if (rol !== null) {
      setRolDemorado(false);
      return;
    }
    const t = window.setTimeout(() => setRolDemorado(true), 6000);
    return () => window.clearTimeout(t);
  }, [rol]);

  // Sin sesión no hay panel
  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      if (!data.session) router.replace("/admin/login");
    });
  }, [supabase, router]);

  // ── Periodos ───────────────────────────────────────────────────────────────
  const cargarPeriodos = useCallback(async (): Promise<PeriodoInfo[] | null> => {
    if (!puedeVer) return null;
    setErrorPeriodos(null);
    const { data, error } = await supabase.rpc("fn_periodos");
    if (error) {
      setErrorPeriodos(error.message);
      return null;
    }
    const lista = ((data as unknown as PeriodoInfo[]) ?? []);
    setPeriodos(lista);
    return lista;
  }, [supabase, puedeVer]);

  // Carga inicial: lista + selección del más reciente
  useEffect(() => {
    void (async () => {
      const lista = await cargarPeriodos();
      if (lista && lista.length > 0) {
        setPeriodoSel((prev) => prev ?? lista[0].id);
      }
    })();
  }, [cargarPeriodos]);

  // CAMBIO 0305 — Los meses que un retroactivo puede corregir: PAGADOS y
  // anteriores al que se está viendo. La base valida lo mismo (fn_agregar_
  // movimiento), así que esto no es la única defensa — es para no ofrecer una
  // opción que va a ser rechazada.
  const origenes = useMemo(() => {
    if (!proy || !periodos) return [];
    const actual = periodos.find((p) => p.id === proy.periodo_id);
    if (!actual) return [];
    return periodos
      .filter((p) => p.estado === "pagado" && p.fecha_fin < actual.fecha_ini)
      .sort((a, b) => b.fecha_fin.localeCompare(a.fecha_fin))
      .map((p) => ({
        id: p.id,
        etiqueta: `${MESES_LARGO[p.mes_etiqueta - 1]} ${p.anio_etiqueta}`,
      }));
  }, [proy, periodos]);

  const periodoActual = useMemo(
    () => periodos?.find((p) => p.id === periodoSel) ?? null,
    [periodos, periodoSel],
  );
  const esUltimo = periodos !== null && periodos.length > 0 && periodoSel === periodos[0].id;
  const pagado = periodoActual?.estado === "pagado";

  // Solo tiene sentido preguntarlo cuando el periodo está pagado: es la única
  // situación en la que existe una foto contra la que comparar.
  const cargarDesvios = useCallback(async () => {
    if (!puedeVer || !periodoActual || periodoActual.estado !== "pagado") { setDesvios(null); return; }
    const { data, error } = await supabase.rpc("fn_planilla_foto_diferencias", {
      p_periodo_id: periodoActual.id,
    });
    // Si la consulta falla no se dice «todo cuadra»: se deja en desconocido.
    setDesvios(error ? null : ((data as unknown as Desvio[]) ?? []));
  }, [supabase, puedeVer, periodoActual]);

  useEffect(() => { void cargarDesvios(); }, [cargarDesvios]);

  // ── Qué cambió respecto al mes pasado (0319) ───────────────────────────────
  // A diferencia de los desvíos, esto se pregunta SIEMPRE: la comparación con
  // el periodo anterior sirve sobre todo ANTES de pagar, que es cuando todavía
  // se puede corregir. `fn_planilla_variacion` resuelve sola cuál es el periodo
  // anterior y devuelve `sin_previo` si no hay ninguno.
  //
  // Devuelve el dato en vez de escribirlo, y quien lo escribe es el efecto de
  // abajo. Es distinto del resto de cargas de esta pantalla a propósito: así el
  // `setState` nunca ocurre de forma síncrona dentro del efecto —lo que el
  // linter marca con razón— y, sobre todo, una respuesta que llega tarde ya no
  // puede pisar a la del periodo que el usuario acaba de elegir.
  const pedirVariacion = useCallback(async (): Promise<Variacion | null> => {
    if (!puedeVer || !periodoActual) return null;
    const { data, error } = await supabase.rpc("fn_planilla_variacion", {
      p_periodo_id: periodoActual.id,
    });
    // Si falla, queda en desconocido y el panel no se dibuja. Un panel vacío
    // que parece «no hay nada que mirar» es peor que un panel ausente.
    return error ? null : ((data as unknown as Variacion) ?? null);
  }, [supabase, puedeVer, periodoActual]);

  useEffect(() => {
    let vigente = true;
    void pedirVariacion().then((v) => { if (vigente) setVariacion(v); });
    return () => { vigente = false; };
  }, [pedirVariacion]);

  // Inicio encadenado del siguiente periodo: día siguiente al último cierre
  const inicioEncadenado = periodos && periodos.length > 0 ? sumarDias(periodos[0].fecha_fin, 1) : null;

  // Periodo VIGENTE: cargarProyeccion lo lee de aquí (no del closure) para que
  // una recarga disparada desde un closure viejo (p. ej. post-guardado de
  // objetivos) nunca pida ni pinte un periodo que ya no está seleccionado.
  const periodoSelRef = useRef<string | null>(null);

  const cargarProyeccion = useCallback(async () => {
    if (!puedeVer) return;
    const id = periodoSelRef.current;
    if (!id) return;
    const mi = ++reqId.current;
    setCargando(true);
    setErrorCarga(null);
    // Toda recarga cierra el panel ± y limpia su formulario: si quedara abierto,
    // un guardado posterior actuaría sobre filas/periodo que están por cambiar.
    setMovAbierto(null);
    setMovForm({ tipo: "bono", concepto: "", monto: "", origen: "" });
    const { data, error } = await supabase.rpc("fn_proyeccion_periodo", { p_periodo_id: id });
    if (mi !== reqId.current) return; // llegó una carga más nueva; descarto ésta
    setCargando(false);
    if (error) {
      setErrorCarga(error.message);
      return;
    }
    setProy(data as unknown as Proyeccion);
    setObjEdit({}); // los valores en edición eran del periodo anterior
    // Grati/CTS que toca en este periodo (falla suave: si no llega, el desplegable
    // simplemente no muestra esas opciones y la planilla sigue igual).
    const { data: gcData } = await supabase.rpc("fn_grati_cts_periodo", { p_periodo_id: id });
    if (mi !== reqId.current) return;
    const g = gcData as any;
    setGc(g ? {
      gratiAplica: Boolean(g.grati_aplica),
      gratiConcepto: g.grati_concepto ?? "",
      ctsAplica: Boolean(g.cts_aplica),
      ctsConcepto: g.cts_concepto ?? "",
      porPersona: Object.fromEntries(((g.personas as any[]) ?? []).map((x) => [x.persona_id, { grati: Number(x.grati) || 0, cts: Number(x.cts) || 0 }])),
    } : null);
    // Quién de este periodo YA cobró su liquidación (0210). Falla suave a
    // propósito: si no llega, la pantalla se queda como estaba y sigue
    // pagándose igual. Es un aviso, no un requisito — un cartel que tumbe la
    // planilla sería peor que el problema que avisa.
    const { data: liqData } = await supabase.rpc("fn_liquidaciones_del_periodo", { p_periodo_id: id });
    if (mi !== reqId.current) return;
    setLiquidadas((liqData as Record<string, Liquidada> | null) ?? {});
  }, [supabase, puedeVer]);

  useEffect(() => {
    periodoSelRef.current = periodoSel;
    if (periodoSel) {
      void cargarProyeccion(); // cierra el panel ± y limpia su form al arrancar
    } else {
      reqId.current++; // invalida cualquier carga en vuelo del periodo anterior
      setCargando(false);
      setMovAbierto(null);
      setMovForm({ tipo: "bono", concepto: "", monto: "", origen: "" });
      setProy(null);
    }
  }, [periodoSel, cargarProyeccion]);

  // Si el periodo seleccionado dejó de existir tras recargar fn_periodos (p. ej.
  // fue eliminado desde otra pestaña), la selección cae al más reciente y la
  // proyección vieja se despinta de inmediato (no debe quedar visible ni editable).
  useEffect(() => {
    if (periodos === null || !periodoSel) return;
    if (periodos.some((p) => p.id === periodoSel)) return;
    setProy(null);
    setPeriodoSel(periodos.length > 0 ? periodos[0].id : null);
  }, [periodos, periodoSel]);

  async function crearPeriodo(fin: string, ini?: string) {
    if (!fin) {
      avisar("error", "Pon la fecha de cierre del periodo.");
      return;
    }
    setCreandoPeriodo(true);
    const { data, error } = await supabase.rpc(
      "fn_crear_periodo",
      ini ? { p_fecha_fin: fin, p_fecha_ini: ini } : { p_fecha_fin: fin },
    );
    setCreandoPeriodo(false);
    if (error) {
      avisar("error", mensajeDeError(error, "crear el periodo"));
      return;
    }
    const nuevo = data as unknown as { id: string; fecha_ini: string; fecha_fin: string };
    avisar("ok", `Periodo creado: ${fechaCorta(nuevo.fecha_ini)} → ${fechaCorta(nuevo.fecha_fin)}.`);
    setMostrandoNuevo(false);
    setNuevoFin("");
    setPrimerIni("");
    setPrimerFin("");
    await cargarPeriodos();
    setPeriodoSel(nuevo.id);
  }

  async function eliminarPeriodo() {
    if (!periodoActual) return;
    if (
      !window.confirm(
        `¿Eliminar el periodo ${fechaCorta(periodoActual.fecha_ini)} → ${fechaCorta(periodoActual.fecha_fin)}? ` +
          "Se pierden los bonos y descuentos registrados en él. Solo se puede eliminar el último periodo abierto.",
      )
    )
      return;
    setGuardandoPeriodo(true);
    const { error } = await supabase.rpc("fn_eliminar_periodo", { p_periodo_id: periodoActual.id });
    setGuardandoPeriodo(false);
    if (error) {
      avisar("error", mensajeDeError(error, "eliminar el periodo"));
      return;
    }
    avisar("ok", "Periodo eliminado.");
    const lista = await cargarPeriodos();
    setPeriodoSel(lista && lista.length > 0 ? lista[0].id : null);
  }

  async function marcarPagado(pagar: boolean) {
    if (!periodoActual) return;
    if (pagar) {
      // CAMBIO 0284 — Se avisa ANTES de intentarlo. La base lo frena igual
      // (fn_planilla_congelar), pero llegar hasta el error con el diálogo ya
      // aceptado se lee como que el sistema falló, y no es eso: es que faltan
      // horas por confirmar. Decirlo acá convierte un error en una instrucción.
      if (diasPendientes) {
        window.alert(
          `Todavía no se puede cerrar este periodo.\n\n` +
            `Hay ${diasPendientes.dias} día(s) cuya hora de salida la puso el sistema porque nadie marcó, ` +
            `y aún están sin confirmar: ${diasPendientes.nombres.join(", ")}.\n\n` +
            `Esa hora no la marcó ninguna persona, y si cruza las 48 h de la semana se paga recargo sobre ella. ` +
            `Entra a Correcciones, confirma o corrige esas salidas, y vuelve aquí.`,
        );
        return;
      }
      if (
        !window.confirm(
          "Marcar este periodo como PAGADO guarda una copia intacta del desglose de cada persona: " +
            "es el número que queda para contabilidad y ya no cambia solo.\n\n" +
            "Si después hay que corregir algo, se reabre con Revertir pago (queda el motivo) y se vuelve " +
            "a marcar como pagado: se guarda una copia nueva y la anterior se conserva.\n\n¿Continuar?",
        )
      )
        return;
      setGuardandoPeriodo(true);
      const { error } = await supabase.rpc("fn_periodo_pagado", { p_periodo_id: periodoActual.id, p_pagado: true });
      setGuardandoPeriodo(false);
      if (error) { avisar("error", mensajeDeError(error, "actualizar el periodo")); return; }
      avisar("ok", "Periodo marcado como PAGADO 🔒.");
      await Promise.all([cargarPeriodos(), cargarProyeccion()]);
      return;
    }
    // Reabrir un pago DEJA RASTRO: se pide el motivo y queda auditado (quién/cuándo/por qué).
    const motivo = window.prompt(
      "Vas a REABRIR un periodo ya pagado. ¿Por qué? (queda registrado)\nEj.: corregir una tardanza mal contada."
    );
    if (motivo === null) return;
    if (motivo.trim().length < 4) { avisar("error", "El motivo de la reapertura es obligatorio (mínimo 4 caracteres)."); return; }
    setGuardandoPeriodo(true);
    const { error } = await supabase.rpc("fn_revertir_pago", { p_periodo_id: periodoActual.id, p_motivo: motivo.trim() });
    setGuardandoPeriodo(false);
    if (error) { avisar("error", mensajeDeError(error, "reabrir")); return; }
    avisar("ok", "Periodo reabierto con registro. Corrige lo necesario y vuelve a marcarlo como PAGADO.");
    await Promise.all([cargarPeriodos(), cargarProyeccion()]);
  }

  // Volver a pagar NO reabre el periodo: los candados de sus marcajes no se
  // levantan en ningún momento (fn_repagar_periodo, migración 0098).
  async function repagarPeriodo() {
    if (!periodoActual) return;
    const motivo = window.prompt(
      "Vas a recalcular este periodo y guardar una copia nueva del desglose.\n" +
        "La copia anterior se conserva y queda registrado quién lo hizo y por qué.\n\n" +
        "¿Por qué se vuelve a pagar? (mínimo 4 caracteres)\nEj.: se corrigió una marca del 12."
    );
    if (motivo === null) return;
    if (motivo.trim().length < 4) {
      avisar("error", "El motivo es obligatorio: volver a pagar cambia una cifra que ya se entregó.");
      return;
    }
    setGuardandoPeriodo(true);
    const { data, error } = await supabase.rpc("fn_repagar_periodo", {
      p_periodo_id: periodoActual.id,
      p_motivo: motivo.trim(),
    });
    setGuardandoPeriodo(false);
    if (error) { avisar("error", mensajeDeError(error, "volver a pagar")); return; }
    const r = data as unknown as { diferencia: number; personas: number; version: number };
    const d = Number(r?.diferencia ?? 0);
    avisar(
      "ok",
      d === 0
        ? "Copia nueva guardada. El total no cambió."
        : `Copia nueva guardada. El total ${d > 0 ? "subió" : "bajó"} ${formatSoles(Math.abs(d))}.`,
    );
    await Promise.all([cargarPeriodos(), cargarProyeccion(), cargarDesvios()]);
  }

  async function calcularBonoPuntualidad() {
    if (!periodoActual) return;
    if (
      !window.confirm(
        "Esto calcula el bono de puntualidad de todo el periodo y lo agrega como bono automático " +
          "a cada persona que no tuvo tardanzas. Si ya lo habías calculado antes en este periodo, se " +
          "reemplaza (no se duplica). ¿Continuar?",
      )
    )
      return;
    setGuardandoBono(true);
    const { data, error } = await supabase.rpc("fn_calcular_bono_puntualidad", {
      p_periodo_id: periodoActual.id,
    });
    setGuardandoBono(false);
    if (error) {
      avisar("error", mensajeDeError(error, "calcular el bono de puntualidad"));
      return;
    }
    const r = data as unknown as { poblacion: number; puntuales: number; monto_por_persona: number };
    avisar(
      "ok",
      r.poblacion === 0
        ? "No hay días trabajados en este periodo todavía: nadie califica."
        : r.puntuales === 0
          ? `Nadie logró cero tardanzas de las ${r.poblacion} personas con días trabajados: no se agregó ningún bono.`
          : `${r.puntuales} de ${r.poblacion} personas lograron cero tardanzas → ${formatSoles(r.monto_por_persona)} cada una.`,
    );
    await cargarProyeccion();
  }

  // ── Feriados (gestión anual, se conserva de la v1) ─────────────────────────
  const anioFeriados = proy?.anio_etiqueta ?? periodoActual?.anio_etiqueta ?? anioActualLima();

  const cargarFeriadosAnio = useCallback(async () => {
    if (!puedeVer) return;
    setErrorFeriados(null);
    const { data, error } = await supabase.rpc("fn_feriados", { p_anio: anioFeriados });
    if (error) {
      setErrorFeriados(error.message);
      setFeriadosAnio(null);
      return;
    }
    setFeriadosAnio((data as unknown as Feriado[]) ?? []);
  }, [supabase, anioFeriados, puedeVer]);

  useEffect(() => {
    if (mostrandoFeriados) void cargarFeriadosAnio();
  }, [mostrandoFeriados, cargarFeriadosAnio]);

  async function agregarFeriado() {
    if (!nuevoFeriado.fecha || nuevoFeriado.nombre.trim().length < 2) {
      avisar("error", "Pon la fecha y el nombre del feriado.");
      return;
    }
    setGuardandoFeriado(true);
    const { error } = await supabase.rpc("fn_set_feriado", {
      p_fecha: nuevoFeriado.fecha,
      p_nombre: nuevoFeriado.nombre.trim(),
    });
    setGuardandoFeriado(false);
    if (error) {
      avisar("error", mensajeDeError(error, "guardar el feriado"));
      return;
    }
    setNuevoFeriado({ fecha: "", nombre: "" });
    avisar("ok", "Feriado guardado.");
    await Promise.all([cargarFeriadosAnio(), cargarProyeccion()]);
  }

  async function quitarFeriado(f: Feriado) {
    if (!window.confirm(`¿Quitar el feriado "${f.nombre}" (${fechaCorta(f.fecha)})? La planilla dejará de pagarlo doble.`)) return;
    setGuardandoFeriado(true);
    const { error } = await supabase.rpc("fn_quitar_feriado", { p_fecha: f.fecha });
    setGuardandoFeriado(false);
    if (error) {
      avisar("error", mensajeDeError(error, "quitar el feriado"));
      return;
    }
    avisar("ok", "Feriado quitado.");
    await Promise.all([cargarFeriadosAnio(), cargarProyeccion()]);
  }

  // ── Básica legal (0103/0106) ────────────────────────────────────────────────
  // Es un dato de la PERSONA, no del periodo. Vaciar el input NO borra el valor
  // guardado —eso sería un borrado silencioso de un dato contractual—; vuelve a
  // mostrar lo que había. Para quitarlo hace falta hacerlo a conciencia por SQL.
  async function guardarBaseLegal(f: Fila) {
    const bruto = baseEdit[f.persona_id];
    if (bruto === undefined) return;
    const limpiar = () =>
      setBaseEdit((prev) => {
        const { [f.persona_id]: _, ...resto } = prev;
        return resto;
      });
    const texto = bruto.trim();
    if (texto === "") {
      limpiar();
      return;
    }
    const n = Number(texto);
    if (!Number.isFinite(n) || n <= 0) {
      avisar("error", `La básica legal de ${f.nombre} debe ser un monto mayor que cero.`);
      return;
    }
    if (n === f.sueldo_base_legal) {
      limpiar();
      return;
    }
    setGuardandoBase(f.persona_id);
    const { error } = await supabase.rpc("fn_set_sueldo_base_legal", {
      p_persona_id: f.persona_id,
      p_monto: n,
    });
    setGuardandoBase(null);
    if (error) {
      avisar("error", `No se pudo guardar la básica legal: ` + mensajeDeError(error));
      return;
    }
    limpiar();
    avisar("ok", `Básica legal de ${f.nombre}: ${formatSoles(n)}.`);
    await cargarProyeccion();
  }

  // ── Rendimiento del mes (0105/0106) ─────────────────────────────────────────
  // Vaciar el input SÍ tiene significado aquí: vuelve al defecto (100%), que paga
  // el rango completo. Por eso borra la fila en vez de escribir un 100 a mano —
  // así el registro distingue «nadie lo puntuó» de «lo puntuaron 100».
  async function guardarRendimiento(f: Fila) {
    if (!proy || proy.simulacion) return;
    const bruto = rendEdit[f.persona_id];
    if (bruto === undefined) return;
    const limpiar = () =>
      setRendEdit((prev) => {
        const { [f.persona_id]: _, ...resto } = prev;
        return resto;
      });
    const texto = bruto.trim();
    setGuardandoRend(f.persona_id);
    let error;
    if (texto === "") {
      ({ error } = await supabase.rpc("fn_quitar_rendimiento", {
        p_persona_id: f.persona_id,
        p_anio: proy.anio_etiqueta,
        p_mes: proy.mes_etiqueta,
      }));
    } else {
      const n = Number(texto);
      if (!Number.isFinite(n) || n < 0 || n > 100) {
        setGuardandoRend(null);
        avisar("error", `El rendimiento de ${f.nombre} debe estar entre 0 y 100.`);
        return;
      }
      if (!f.rendimiento_por_defecto && n === f.rendimiento_pct) {
        setGuardandoRend(null);
        limpiar();
        return;
      }
      ({ error } = await supabase.rpc("fn_set_rendimiento", {
        p_persona_id: f.persona_id,
        p_anio: proy.anio_etiqueta,
        p_mes: proy.mes_etiqueta,
        p_porcentaje: n,
        p_etiqueta_codigo: null,
      }));
    }
    setGuardandoRend(null);
    if (error) {
      avisar("error", `No se pudo guardar el rendimiento: ` + mensajeDeError(error));
      return;
    }
    limpiar();
    avisar("ok", texto === ""
      ? `${f.nombre} vuelve al 100% por defecto.`
      : `Rendimiento de ${f.nombre}: ${texto}%.`);
    await cargarProyeccion();
  }

  // ── Objetivos (etiqueta del periodo = mes de la fecha de cierre) ───────────
  async function guardarObjetivos(f: Fila) {
    if (!proy || proy.simulacion) return;
    const bruto = objEdit[f.persona_id];
    if (bruto === undefined) return; // no se tocó
    const texto = bruto.trim();
    const limpiar = () =>
      setObjEdit((prev) => {
        const { [f.persona_id]: _, ...resto } = prev;
        return resto;
      });
    if (texto === "") {
      limpiar(); // vaciar el input no borra el registro; vuelve a mostrar lo guardado
      return;
    }
    const total = f.objetivos_total ?? 10;
    const n = Number(texto);
    if (!Number.isInteger(n) || n < 0 || n > total) {
      avisar("error", `Los objetivos de ${f.nombre} deben ser un entero entre 0 y ${total}.`);
      return;
    }
    if (n === f.objetivos_cumplidos) {
      limpiar();
      return;
    }
    setGuardandoObj(f.persona_id);
    const { error } = await supabase.rpc("fn_set_objetivos", {
      p_persona_id: f.persona_id,
      p_anio: proy.anio_etiqueta,
      p_mes: proy.mes_etiqueta,
      p_cumplidos: n,
      p_total: total,
    });
    setGuardandoObj(null);
    if (error) {
      avisar("error", `No se pudieron guardar los objetivos: ` + mensajeDeError(error));
      return;
    }
    avisar("ok", `Objetivos de ${f.nombre}: ${n} de ${total}.`);
    await cargarProyeccion();
  }

  // ── Bonos / descuentos ─────────────────────────────────────────────────────
  function toggleMov(personaId: string) {
    setMovAbierto((prev) => (prev === personaId ? null : personaId));
    setMovForm({ tipo: "bono", concepto: "", monto: "", origen: "" });
  }

  async function agregarMovimiento(f: Fila) {
    if (!proy?.periodo_id) return;
    const concepto = movForm.concepto.trim();
    const monto = Number(movForm.monto);
    if (concepto.length < 2) {
      avisar("error", "Pon el concepto del movimiento (mínimo 2 letras).");
      return;
    }
    if (!Number.isFinite(monto) || monto <= 0) {
      avisar("error", "El monto debe ser mayor a 0.");
      return;
    }
    setGuardandoMov(true);
    const { error } = await supabase.rpc("fn_agregar_movimiento", {
      p_periodo_id: proy.periodo_id,
      p_persona_id: f.persona_id,
      p_tipo: CLASE_A_TIPO[movForm.tipo],
      p_concepto: concepto,
      p_monto: monto,
      p_categoria: CLASE_A_CATEGORIA[movForm.tipo],
      // CAMBIO 0305 — vacío significa «no corrige nada», y la base lo espera en
      // null, no en cadena vacía.
      p_periodo_origen_id: movForm.origen || null,
    });
    setGuardandoMov(false);
    if (error) {
      avisar("error", mensajeDeError(error, "registrar el movimiento"));
      return;
    }
    avisar("ok", `${CLASE_LABEL[movForm.tipo]} de ${formatSoles(monto)} para ${f.nombre}.`);
    await cargarProyeccion(); // cierra el panel ± y limpia el formulario

  }

  // «Ya le pagué aparte». No borra a la persona de la planilla: le pone un
  // descuento por lo que ya recibió, con la fecha escrita en el concepto. Su
  // total baja a cero (o a la diferencia) y en la boleta queda dicho por qué.
  //
  // Se prefiere esto a excluirla del periodo porque dentro de un año «esta
  // persona no aparece en julio» no explica nada y parece un fallo; «se le
  // descontó S/850 porque ya se le había pagado el 14/07» sí.
  async function marcarYaPagado(f: Fila) {
    if (!proy?.periodo_id) return;
    // CAMBIO 0244 · Qué importe se propone. Si esta persona ya cobró su
    // liquidación, lo que hay que descontar es lo que ESA liquidación pagó de
    // este mes menos lo ya descontado — no el total de su fila. Proponer el
    // total le quitaba de paso cualquier saldo que sí hubiera ganado después de
    // congelar, y encima el freno del cierre no pide tanto: se levanta en cuanto
    // los descuentos cubren el monto de la liquidación.
    //
    // Sigue siendo una PROPUESTA: el campo se puede editar, porque el único que
    // sabe cuánto salió del banco es quien lo transfirió.
    const liq = liquidadas[f.persona_id];
    const porCubrir = liq ? liq.cobro_del_periodo - f.descuentos : f.total;
    const sugerido = Math.max(0, Math.round(porCubrir * 100) / 100);
    const montoTxt = window.prompt(
      `${f.nombre} — ¿cuánto le pagaste ya, fuera de la planilla?\n\n` +
        `Este periodo le calcula ${formatSoles(f.total)}. Se registrará como un descuento por lo ` +
        `que ya recibió, así su total queda en cero (o en la diferencia) y en su boleta queda ` +
        `escrito por qué.` +
        // De dónde sale el número que viene puesto. Sin esta línea, quien lo lee
        // no sabe si el importe propuesto es lo que la planilla le calcula o lo
        // que su liquidación ya le pagó — y son cosas distintas.
        (liq
          ? `\n\nSu liquidación del ${fechaCorta(liq.pagada_el)} ya le pagó ` +
            `${formatSoles(liq.cobro_del_periodo)} de este mes` +
            (f.descuentos > 0 ? `, y aquí ya hay ${formatSoles(f.descuentos)} descontados` : "") +
            `. Por eso viene propuesto ${formatSoles(sugerido)}.`
          : ""),
      String(sugerido),
    );
    if (montoTxt === null) return;
    // El monto lo lee `parsearMontoSoles`, no un `replace` a mano: la app
    // imprime «8,500.00» con Intl y quien copia esa cifra tiene que poder
    // pegarla. Ver packages/shared/src/montos.ts para por qué esto no vive acá.
    const leido = parsearMontoSoles(montoTxt);
    if (!leido.ok) {
      avisar("error", leido.motivo);
      return;
    }
    const monto = leido.monto;
    if (monto <= 0) {
      avisar("error", "El monto tiene que ser mayor a 0.");
      return;
    }
    const fecha = window.prompt(
      "¿Qué día se lo pagaste? (formato DD/MM/AAAA)\n\nQueda escrito en su boleta y en la foto del pago.",
      hoyLimaDMA(),
    );
    if (fecha === null) return;
    if (!/^\d{2}\/\d{2}\/\d{4}$/.test(fecha.trim())) {
      avisar("error", "La fecha tiene que ir como DD/MM/AAAA — por ejemplo 14/07/2026.");
      return;
    }
    setGuardandoMov(true);
    const { error } = await supabase.rpc("fn_agregar_movimiento", {
      p_periodo_id: proy.periodo_id,
      p_persona_id: f.persona_id,
      p_tipo: "descuento",
      p_concepto: `Ya pagado el ${fecha.trim()} — fuera de planilla`,
      p_monto: monto,
      p_categoria: null,
    });
    setGuardandoMov(false);
    if (error) {
      avisar("error", mensajeDeError(error, "registrar"));
      return;
    }
    avisar("ok", `Registrado: a ${f.nombre} ya se le habían pagado ${formatSoles(monto)} el ${fecha.trim()}.`);
    await cargarProyeccion();
  }

  async function quitarMovimiento(m: Movimiento) {
    if (!window.confirm(`¿Quitar el ${m.tipo} "${m.concepto}" de ${formatSoles(m.monto)}?`)) return;
    setGuardandoMov(true);
    const { error } = await supabase.rpc("fn_quitar_movimiento", { p_movimiento_id: m.id });
    setGuardandoMov(false);
    if (error) {
      avisar("error", mensajeDeError(error, "quitar el movimiento"));
      return;
    }
    avisar("ok", "Movimiento quitado.");
    await cargarProyeccion();
  }

  // ── Simulador (solo lectura, nada se guarda) ───────────────────────────────
  async function simular() {
    if (!simIni || !simFin) {
      avisar("error", "Pon las dos fechas del rango a simular.");
      return;
    }
    const mi = ++reqIdSim.current;
    setSimCargando(true);
    setSimError(null);
    const { data, error } = await supabase.rpc("fn_simular_planilla", { p_ini: simIni, p_fin: simFin });
    if (mi !== reqIdSim.current) return;
    setSimCargando(false);
    if (error) {
      setSimError(error.message);
      setSimProy(null);
      return;
    }
    setSimProy(data as unknown as Proyeccion);
  }

  // ── Filtro de sede ─────────────────────────────────────────────────────────
  const sedes = useMemo(
    () => Array.from(new Set((proy?.filas ?? []).map((f) => f.sede))).sort(),
    [proy],
  );
  const filasVisibles = useMemo(
    () => (proy?.filas ?? []).filter(
      (f) => (sedeFiltro === "todas" || f.sede === sedeFiltro) && pasaEstado(f, estadoFiltro),
    ),
    [proy, sedeFiltro, estadoFiltro],
  );
  const simFilasVisibles = useMemo(
    () => (simProy?.filas ?? []).filter(
      (f) => (sedeFiltro === "todas" || f.sede === sedeFiltro) && pasaEstado(f, estadoFiltro),
    ),
    [simProy, sedeFiltro, estadoFiltro],
  );
  // Partidas de la misma lista, por la pestaña Planilla / Honorarios (RxH).
  const filasPlanillaTab = useMemo(
    () => filasVisibles.filter((f) => f.en_planilla !== false),
    [filasVisibles],
  );
  const filasHonorariosTab = useMemo(
    () => filasVisibles.filter((f) => f.en_planilla === false),
    [filasVisibles],
  );
  const simFilasPlanillaTab = useMemo(
    () => simFilasVisibles.filter((f) => f.en_planilla !== false),
    [simFilasVisibles],
  );
  const simFilasHonorariosTab = useMemo(
    () => simFilasVisibles.filter((f) => f.en_planilla === false),
    [simFilasVisibles],
  );
  const filasTabActiva = tablaTab === "planilla" ? filasPlanillaTab : filasHonorariosTab;
  const simFilasTabActiva = tablaTab === "planilla" ? simFilasPlanillaTab : simFilasHonorariosTab;
  const provTotales = useMemo(
    () =>
      filasVisibles.reduce(
        (acc, f) => ({
          gratificacion: acc.gratificacion + f.provision_gratificacion,
          cts: acc.cts + f.provision_cts,
          vacaciones: acc.vacaciones + f.provision_vacaciones,
          total: acc.total + f.provision_total,
        }),
        { gratificacion: 0, cts: 0, vacaciones: 0, total: 0 },
      ),
    [filasVisibles],
  );

  // Quienes el filtro está escondiendo Y tienen plata por cobrar. Se calcula
  // sobre TODAS las filas del periodo, no sobre las visibles: el sentido del
  // aviso es justamente contar lo que no se está viendo.
  const ocultosPorCobrar = useMemo(() => {
    if (estadoFiltro !== "activos") return null;
    const ocultos = (proy?.filas ?? []).filter(
      (f) => f.estado !== "activo" && f.total > 0 && (sedeFiltro === "todas" || f.sede === sedeFiltro),
    );
    if (ocultos.length === 0) return null;
    return { n: ocultos.length, monto: ocultos.reduce((a, f) => a + f.total, 0) };
  }, [proy, estadoFiltro, sedeFiltro]);

  // CAMBIO 0284 — Días con la salida puesta por el sistema y sin confirmar.
  // Sobre TODAS las filas del periodo y NUNCA sobre `filasVisibles`, por la
  // misma razón que el aviso de arriba: si el filtro esconde justo a esa
  // persona, el aviso desaparecería y el freno de la base saltaría igual —
  // avisando de alguien que la pantalla no está mostrando.
  // El freno de verdad vive en `fn_planilla_congelar` (0284); esto solo evita
  // llegar hasta ahí a ciegas.
  const diasPendientes = useMemo(() => {
    const conPendientes = (proy?.filas ?? []).filter((f) => f.dias_pendientes > 0);
    if (conPendientes.length === 0) return null;
    return {
      personas: conPendientes.length,
      dias: conPendientes.reduce((a, f) => a + f.dias_pendientes, 0),
      nombres: conPendientes.map((f) => f.nombre).sort(),
    };
  }, [proy]);

  // ── CSV (columnas de la tabla + las 4 de provisiones; respeta el filtro) ───
  // Nombre y contenido salen de proy (lo realmente cargado), NUNCA del selector
  // de periodo: si el selector cambió y la carga aún no llega, el CSV sería del
  // periodo equivocado. No hay CSV de la simulación.
  function descargarCsvPlanilla() {
    if (!proy || proy.simulacion) return;
    const filas = filasVisibles.map((f) => ({
      nombre: f.nombre,
      sede: f.sede,
      rango: f.rango ? (RANGO_LABEL[f.rango] ?? f.rango) : "sin salario",
      salario_referencia: f.salario_ref ?? "",
      horas: f.horas_mes,
      dias_trabajados: f.dias_trabajados,
      dias_pendientes: f.dias_pendientes,
      horas_sin_salario: f.horas_sin_salario,
      pago_base: f.pago_base,
      monto_feriados: f.monto_feriados,
      asignacion_familiar: f.asignacion_familiar,
      objetivos_cumplidos: f.objetivos_cumplidos ?? "",
      objetivos_total: f.objetivos_total ?? "",
      monto_plus: f.monto_plus,
      bonos: f.bonos,
      descuentos: f.descuentos,
      // La retención de 4ta va en el CSV porque es lo que el contador necesita
      // para declararla: el tributo 3042 de la PLAME sale de esta columna, y
      // hasta la 0245 había que sacarlo de los recibos uno por uno. Se exporta
      // también la base: sin ella la retención no se puede verificar.
      retencion_4ta_base: f.retencion_4ta_base ?? "",
      retencion_4ta: f.retencion_4ta ?? "",
      total: f.total,
      provision_gratificacion: f.provision_gratificacion,
      provision_cts: f.provision_cts,
      provision_vacaciones: f.provision_vacaciones,
      provision_total: f.provision_total,
    }));
    const csv = generarCsv(filas, [
      "nombre",
      "sede",
      "rango",
      "salario_referencia",
      "horas",
      "dias_trabajados",
      "dias_pendientes",
      "horas_sin_salario",
      "pago_base",
      "monto_feriados",
      "asignacion_familiar",
      "objetivos_cumplidos",
      "objetivos_total",
      "monto_plus",
      "bonos",
      "descuentos",
      "retencion_4ta_base",
      "retencion_4ta",
      "total",
      "provision_gratificacion",
      "provision_cts",
      "provision_vacaciones",
      "provision_total",
    ]);
    descargarCsv(`planilla-${proy.fecha_ini}_${proy.fecha_fin}.csv`, csv);
  }

  // ── Gating ─────────────────────────────────────────────────────────────────
  if (rol === null) {
    return (
      <div className="flex min-h-screen flex-col">
        <AdminNav />
        <main className="flex-1 p-6">
          {rolDemorado ? (
            <p className="max-w-md rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
              No se pudo identificar tu usuario — cierra sesión y vuelve a entrar.
            </p>
          ) : (
            <Cargando />
          )}
        </main>
      </div>
    );
  }
  if (!puedeVer) {
    return (
      <div className="flex min-h-screen flex-col">
        <AdminNav />
        <main className="flex-1 p-6">
          <p className="max-w-md rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
            Solo administradores y líderes pueden ver la planilla.
          </p>
        </main>
      </div>
    );
  }

  const ocupado = cargando || guardandoObj !== null || guardandoMov || guardandoPeriodo || guardandoBono;

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        {/* Cabecera: selector de periodo */}
        <div className="mb-4 flex flex-wrap items-center gap-3">
          <h1 className="font-serif text-2xl">Planilla</h1>
          {periodos && periodos.length > 0 && (
            <>
              <select
                value={periodoSel ?? ""}
                onChange={(e) => {
                  setPeriodoSel(e.target.value);
                }}
                className="rounded-lg border bg-crema px-3 py-1.5 text-sm"
                aria-label="Periodo de pago"
              >
                {periodos.map((p) => (
                  <option key={p.id} value={p.id}>
                    {etiquetaPeriodo(p)}
                    {p.estado === "pagado" ? " · PAGADO" : ""}
                  </option>
                ))}
              </select>
              {periodoActual &&
                (periodoActual.estado === "pagado" ? (
                  <span className="whitespace-nowrap rounded-full bg-verde/15 px-2.5 py-0.5 text-xs font-medium text-verde">
                    PAGADO 🔒
                  </span>
                ) : (
                  <span className="whitespace-nowrap rounded-full bg-ambar/15 px-2.5 py-0.5 text-xs text-ambar">
                    abierto
                  </span>
                ))}
              <button
                onClick={() => {
                  setMostrandoNuevo((v) => !v);
                }}
                className="rounded-lg border px-3 py-1.5 text-sm hover:bg-sand/50"
              >
                + Nuevo periodo
              </button>
              {esUltimo && periodoActual?.estado === "abierto" && (
                <button
                  onClick={() => void eliminarPeriodo()}
                  disabled={guardandoPeriodo}
                  className="rounded-lg border px-3 py-1.5 text-sm text-rojo hover:bg-rojo/10 disabled:opacity-50"
                >
                  Eliminar
                </button>
              )}
            </>
          )}
        </div>

        {errorPeriodos && (
          <div className="mb-4 max-w-3xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
            No se pudieron cargar los periodos: {errorPeriodos}{" "}
            <button
              onClick={() =>
                void (async () => {
                  const lista = await cargarPeriodos();
                  if (lista && lista.length > 0) setPeriodoSel((prev) => prev ?? lista[0].id);
                })()
              }
              className="font-medium underline"
            >
              Reintentar
            </button>
          </div>
        )}

        {/* Aún cargando la lista */}
        {periodos === null && !errorPeriodos && <Cargando />}

        {/* Sin periodos: pantalla de arranque */}
        {periodos !== null && periodos.length === 0 && (
          <div className="max-w-xl rounded-lg border bg-sand/30 p-6">
            <h2 className="mb-2 font-serif text-lg">Crear el primer periodo</h2>
            <p className="mb-4 text-sm text-taupe">
              La planilla se paga por periodos encadenados: tú eliges el día de cierre y el siguiente
              periodo empieza automáticamente al día siguiente (sin huecos ni días contados dos veces).
              Solo este primer periodo necesita fecha de inicio. Cada periodo debe durar entre 20 y 46 días.
            </p>
            <div className="flex flex-wrap items-end gap-3">
              <label className="flex flex-col gap-1 text-sm">
                Fecha de inicio
                <input
                  type="date"
                  value={primerIni}
                  onChange={(e) => setPrimerIni(e.target.value)}
                  className="rounded-lg border px-3 py-2"
                />
              </label>
              <label className="flex flex-col gap-1 text-sm">
                Fecha de cierre
                <input
                  type="date"
                  value={primerFin}
                  onChange={(e) => setPrimerFin(e.target.value)}
                  className="rounded-lg border px-3 py-2"
                />
              </label>
              <button
                onClick={() => void crearPeriodo(primerFin, primerIni)}
                disabled={creandoPeriodo || !primerIni || !primerFin}
                className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50"
              >
                {creandoPeriodo ? "Creando…" : "Crear periodo"}
              </button>
            </div>
          </div>
        )}

        {/* Con periodos: panel principal */}
        {periodos !== null && periodos.length > 0 && (
          <>
            {/* Nuevo periodo (encadenado) */}
            {mostrandoNuevo && inicioEncadenado && (
              <div className="mb-4 max-w-2xl rounded-lg border bg-sand/30 p-4">
                <p className="mb-2 text-sm font-medium">Nuevo periodo</p>
                <div className="flex flex-wrap items-end gap-3">
                  <label className="flex flex-col gap-1 text-sm">
                    Inicio (encadenado)
                    <input
                      type="date"
                      value={inicioEncadenado}
                      readOnly
                      disabled
                      className="rounded-lg border px-3 py-2 opacity-60"
                    />
                  </label>
                  <label className="flex flex-col gap-1 text-sm">
                    Fecha de cierre
                    <input
                      type="date"
                      value={nuevoFin}
                      min={sumarDias(inicioEncadenado, 19)}
                      max={sumarDias(inicioEncadenado, 45)}
                      onChange={(e) => setNuevoFin(e.target.value)}
                      className="rounded-lg border px-3 py-2"
                    />
                  </label>
                  <button
                    onClick={() => void crearPeriodo(nuevoFin)}
                    disabled={creandoPeriodo || !nuevoFin}
                    className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50"
                  >
                    {creandoPeriodo ? "Creando…" : "Crear periodo"}
                  </button>
                  <button
                    onClick={() => setMostrandoNuevo(false)}
                    className="rounded-lg border px-3 py-2 text-sm hover:bg-sand/50"
                  >
                    Cancelar
                  </button>
                </div>
                <p className="mt-2 text-xs text-taupe">
                  El inicio no se puede cambiar: siempre es el día siguiente al último cierre
                  ({fechaCorta(periodos[0].fecha_fin)} → empieza el {fechaCorta(inicioEncadenado)}),
                  para que ningún día quede fuera ni se pague dos veces. Duración permitida: 20 a 46 días.
                </p>
              </div>
            )}

            {errorCarga && (
              <div className="mb-4 max-w-3xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
                No se pudo cargar la proyección: {errorCarga}{" "}
                <button onClick={() => void cargarProyeccion()} className="font-medium underline">
                  Reintentar
                </button>
              </div>
            )}

            {/* El periodo pagado dejó de cuadrar. El sistema lo DICE; corregir es
                decisión de una persona, nunca automática. */}
            {pagado && desvios && desvios.length > 0 && (
              <div className="mb-4 max-w-3xl rounded-lg bg-ambar/15 px-4 py-3 text-sm text-ambar">
                <p className="font-medium">
                  Este periodo ya está pagado, pero su desglose dejó de coincidir con los datos de hoy.
                </p>
                <p className="mt-1 text-xs">
                  Alguien corrigió algo de estas fechas después del pago. Lo que se transfirió no cambió — lo que
                  cambió es lo que el sistema calcularía ahora.
                </p>
                <ul className="mt-2 space-y-0.5 text-xs">
                  {desvios.slice(0, 8).map((d) => (
                    <li key={d.persona_id}>
                      <span className="font-medium">{d.nombre}</span>:{" "}
                      {d.total_foto === null
                        ? "no estaba en la planilla pagada y ahora sí"
                        : d.total_ahora === null
                          ? "estaba en la planilla pagada y ahora no aparece"
                          : `${formatSoles(d.total_foto)} → ${formatSoles(d.total_ahora)} (${
                              d.diferencia > 0 ? "+" : ""
                            }${formatSoles(d.diferencia)})`}
                    </li>
                  ))}
                  {desvios.length > 8 && <li>…y {desvios.length - 8} más.</li>}
                </ul>
                <button
                  onClick={() => void repagarPeriodo()}
                  disabled={guardandoPeriodo}
                  className="mt-3 rounded-lg bg-ambar px-4 py-1.5 text-sm font-medium text-crema disabled:opacity-50"
                >
                  {guardandoPeriodo ? "Guardando…" : "Recalcular y volver a pagar"}
                </button>
                <p className="mt-2 text-xs opacity-80">
                  Guarda una copia nueva del desglose. La anterior se conserva, y queda registrado quién lo hizo y
                  por qué. El periodo no se reabre en ningún momento.
                </p>
              </div>
            )}

            {/* Candado del periodo */}
            {periodoActual && (
              <div className="mb-4 flex flex-wrap items-center gap-3">
                {pagado ? (
                  <>
                    <span className="text-sm text-taupe">
                      Pagado{periodoActual.pagado_at ? ` el ${fechaLima(periodoActual.pagado_at)}` : ""} — el desglose
                      quedó congelado; es la cifra que va a Costos.
                    </span>
                    <button
                      onClick={() => void marcarPagado(false)}
                      disabled={guardandoPeriodo}
                      className="rounded-lg border px-3 py-1.5 text-sm hover:bg-sand/50 disabled:opacity-50"
                    >
                      Reabrir periodo
                    </button>
                  </>
                ) : (
                  <>
                    {/* El botón «Calcular bono de puntualidad» salió el
                        2026-08-06. El bono está en cero desde la migración 0121,
                        así que el botón corría, no pagaba nada y no lo decía: un
                        botón que existe y no hace nada enseña a desconfiar de la
                        pantalla entera. `fn_calcular_bono_puntualidad` sigue en
                        la base con su guard, por si algún día se reactiva. */}
                    <button
                      onClick={() => void marcarPagado(true)}
                      disabled={guardandoPeriodo || cargando}
                      className="rounded-lg bg-tinta px-4 py-1.5 text-sm font-medium text-crema disabled:opacity-50"
                    >
                      {guardandoPeriodo ? "Guardando…" : "Marcar como PAGADO"}
                    </button>
                  </>
                )}
              </div>
            )}

            {/* Cabecera resumen del periodo */}
            {proy && (
              <div className="mb-4 flex flex-wrap items-center gap-x-5 gap-y-2 text-sm text-taupe">
                <span className="whitespace-nowrap">
                  {fechaCorta(proy.fecha_ini)} → {fechaCorta(proy.fecha_fin)}
                </span>
                <span>·</span>
                <span>{proy.dias} días</span>
                <span>·</span>
                <span>Base full-time: {fmtHoras(proy.base_horas)}</span>
                {proy.feriados.length > 0 && <span>·</span>}
                {proy.feriados.map((f) => (
                  <span key={f.fecha} className="whitespace-nowrap rounded-full bg-ambar/15 px-2 py-0.5 text-xs text-ambar">
                    {fechaCorta(f.fecha)} — {f.nombre}
                  </span>
                ))}
                {proy.feriados.length === 0 && <span>· sin feriados en este periodo</span>}
              </div>
            )}

            {/* Gestión de feriados (plegable) */}
            <div className="mb-4">
              <button
                onClick={() => setMostrandoFeriados((v) => !v)}
                className="text-sm text-taupe hover:text-tinta hover:underline"
              >
                {mostrandoFeriados ? "▾" : "▸"} Gestionar feriados
              </button>
              {mostrandoFeriados && (
                <div className="mt-2 max-w-2xl rounded-lg border bg-sand/30 p-4">
                  <p className="mb-2 text-sm font-medium">Feriados nacionales de {anioFeriados}</p>
                  {errorFeriados ? (
                    <p className="text-sm text-rojo">
                      No se pudieron cargar los feriados: {errorFeriados}{" "}
                      <button onClick={() => void cargarFeriadosAnio()} className="font-medium underline">Reintentar</button>
                    </p>
                  ) : feriadosAnio === null ? (
                    <Cargando />
                  ) : feriadosAnio.length === 0 ? (
                    <SinDatos texto="No hay feriados registrados este año." pista="Los feriados se cargan en la pantalla Feriados. Sin ellos, el pago por feriado laborado no se calcula." />
                  ) : (
                    <ul className="mb-3 grid gap-x-10 sm:grid-cols-2">
                      {feriadosAnio.map((f) => (
                        <li key={f.fecha} className="flex items-center justify-between gap-3 border-b border-sand/60 py-1.5 text-sm">
                          <span className="min-w-0">
                            <span className="text-taupe">{fechaCorta(f.fecha)}</span> — {f.nombre}
                          </span>
                          <button
                            onClick={() => void quitarFeriado(f)}
                            disabled={guardandoFeriado}
                            className="shrink-0 text-xs text-rojo hover:underline disabled:opacity-50"
                          >
                            Quitar
                          </button>
                        </li>
                      ))}
                    </ul>
                  )}
                  <div className="mt-2 flex flex-wrap items-end gap-3 border-t pt-3">
                    <label className="flex flex-col gap-1 text-sm">
                      Fecha
                      <input
                        type="date"
                        value={nuevoFeriado.fecha}
                        onChange={(e) => setNuevoFeriado({ ...nuevoFeriado, fecha: e.target.value })}
                        className="rounded-lg border px-3 py-2"
                      />
                    </label>
                    <label className="flex flex-col gap-1 text-sm">
                      Nombre
                      <input
                        value={nuevoFeriado.nombre}
                        onChange={(e) => setNuevoFeriado({ ...nuevoFeriado, nombre: e.target.value })}
                        placeholder="ej. Fiestas Patrias"
                        className="rounded-lg border px-3 py-2"
                      />
                    </label>
                    <button
                      onClick={() => void agregarFeriado()}
                      disabled={guardandoFeriado}
                      className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50"
                    >
                      {guardandoFeriado ? "Guardando…" : "Agregar feriado"}
                    </button>
                  </div>
                  <p className="mt-2 text-xs text-taupe">
                    Solo feriados nacionales por ley: cada uno paga el proporcional a todos, y doble a quien lo trabaja.
                  </p>
                </div>
              )}
            </div>

            {/* La red de seguridad del filtro: si esconder a quienes ya no están
                deja plata sin pagar a la vista, el sistema lo dice. Es la razón por
                la que el filtro puede arrancar en «solo el equipo actual» sin riesgo. */}
            {ocultosPorCobrar && (
              <div className="mb-3 max-w-3xl rounded-lg bg-ambar/15 px-4 py-3 text-sm text-ambar">
                <strong className="font-medium">
                  {ocultosPorCobrar.n === 1
                    ? "Hay 1 persona que ya no está en el equipo"
                    : `Hay ${ocultosPorCobrar.n} personas que ya no están en el equipo`}{" "}
                  con {formatSoles(ocultosPorCobrar.monto)} por cobrar en este periodo,
                </strong>{" "}
                y el filtro las está ocultando. Trabajaron parte del periodo antes de irse.{" "}
                <button
                  onClick={() => setEstadoFiltro("todos")}
                  className="font-medium underline"
                >
                  Verlas
                </button>
              </div>
            )}

            {/* Filtros + CSV */}
            <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
              <div className="flex flex-wrap items-center gap-3">
                <label className="flex items-center gap-2 text-sm">
                  Sede
                  <select
                    value={sedeFiltro}
                    onChange={(e) => setSedeFiltro(e.target.value)}
                    className="rounded-lg border bg-crema px-3 py-1.5"
                  >
                    <option value="todas">Todas</option>
                    {sedes.map((s) => (
                      <option key={s} value={s}>{s}</option>
                    ))}
                  </select>
                </label>
                <label className="flex items-center gap-2 text-sm">
                  Mostrar
                  <select
                    value={estadoFiltro}
                    onChange={(e) => setEstadoFiltro(e.target.value as EstadoFiltro)}
                    className="rounded-lg border bg-crema px-3 py-1.5"
                  >
                    <option value="activos">Solo el equipo actual</option>
                    <option value="inactivos">Solo quienes ya no están</option>
                    <option value="todos">Todos</option>
                  </select>
                </label>
              </div>
              <button
                onClick={descargarCsvPlanilla}
                disabled={cargando || errorCarga !== null || !proy || filasVisibles.length === 0}
                className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50"
              >
                Descargar CSV
              </button>
            </div>

            {/* ── Qué cambió respecto al mes pasado (0319) ──────────────────
                Se pone ANTES de la tabla a propósito: la tabla dice cuánto
                cobra cada quien y esto dice a quién hay que mirar. Leer treinta
                filas buscando la que se movió es justo lo que este panel evita. */}
            {variacion && !variacion.sin_previo && (() => {
              const conAviso = variacion.filas.filter((f) => f.avisos.length > 0);
              const visibles = variacionTodas ? variacion.filas : conAviso;
              return (
                <div className="mb-4 max-w-4xl rounded-lg border bg-papel p-4">
                  <div className="flex flex-wrap items-baseline justify-between gap-3">
                    <div>
                      <p className="font-medium">Qué cambió respecto al mes pasado</p>
                      <p className="mt-0.5 text-xs text-taupe">
                        Contra el periodo {fechaCorta(variacion.previo_desde!)} –{" "}
                        {fechaCorta(variacion.previo_hasta!)}
                        {variacion.previo_fuente === "foto"
                          ? " · ya pagado, se compara por lo que se pagó"
                          : " · todavía abierto, su cifra aún se mueve"}
                      </p>
                    </div>
                    <button
                      onClick={() => setMostrandoVariacion((v) => !v)}
                      className="text-sm text-taupe hover:text-tinta hover:underline"
                    >
                      {mostrandoVariacion ? "▾ Ocultar" : "▸ Ver detalle"}
                    </button>
                  </div>

                  <p className="mt-2 text-sm">
                    {conAviso.length === 0 ? (
                      <span className="text-verde">Nada llama la atención este periodo.</span>
                    ) : (
                      <span className="text-rojo">
                        {conAviso.length === 1
                          ? "1 persona con algo que mirar"
                          : `${conAviso.length} personas con algo que mirar`}
                        .
                      </span>
                    )}{" "}
                    <span className="text-taupe">
                      El total del equipo va de {formatSoles(variacion.resumen.total_previo ?? 0)} a{" "}
                      {formatSoles(variacion.resumen.total_actual ?? 0)} (
                      {(variacion.resumen.total_delta ?? 0) > 0 ? "+" : ""}
                      {formatSoles(variacion.resumen.total_delta ?? 0)}).
                    </span>
                  </p>

                  {/* Los periodos de CAYLA duran entre 20 y 46 días. Si los dos
                      lados no miden lo mismo, se dice ANTES que ninguna cifra:
                      medio informe se explica solo con eso. */}
                  {variacion.periodos_de_distinto_largo && (
                    <p className="mt-2 rounded-lg bg-ambar/15 px-3 py-2 text-xs text-ambar">
                      Ojo: los dos periodos no duran lo mismo ({variacion.periodo_dias} días contra{" "}
                      {variacion.previo_dias}). Parte de lo que se ve aquí es el calendario, no un cambio real.
                    </p>
                  )}

                  {mostrandoVariacion && (
                    <>
                      {visibles.length === 0 ? (
                        <p className="mt-3 text-sm text-taupe">
                          Nadie levantó un aviso.{" "}
                          <button
                            onClick={() => setVariacionTodas(true)}
                            className="font-medium underline"
                          >
                            Ver a todo el equipo igualmente
                          </button>
                        </p>
                      ) : (
                        <div className="mt-3 overflow-x-auto">
                          <table className="w-full min-w-[46rem] text-sm">
                            <thead>
                              <tr className="bg-sand/60 text-left text-xs">
                                <th className="px-3 py-2 font-normal">Persona</th>
                                <th className="px-3 py-2 text-right font-normal">Mes pasado</th>
                                <th className="px-3 py-2 text-right font-normal">Este mes</th>
                                <th className="px-3 py-2 text-right font-normal">Diferencia</th>
                                <th className="px-3 py-2 text-right font-normal" title="Horas marcadas. Las ausencias pagadas no marcan: por eso una caída a cero puede ser normal.">
                                  Horas
                                </th>
                                <th className="px-3 py-2 font-normal">Qué pasa</th>
                              </tr>
                            </thead>
                            <tbody>
                              {visibles.map((f) => (
                                <tr key={f.persona_id} className="border-b border-sand/60 align-top">
                                  <td className="px-3 py-2">
                                    <span className="font-medium">{f.nombre}</span>
                                    {f.sede && <span className="ml-1.5 text-xs text-taupe">{f.sede}</span>}
                                  </td>
                                  <td className="px-3 py-2 text-right tabular-nums text-taupe">
                                    {formatSoles(f.total_previo)}
                                  </td>
                                  <td className="px-3 py-2 text-right tabular-nums">{formatSoles(f.total_actual)}</td>
                                  <td
                                    className={`px-3 py-2 text-right tabular-nums font-medium ${
                                      f.avisos.length > 0 ? "text-rojo" : "text-taupe"
                                    }`}
                                  >
                                    {f.delta > 0 ? "+" : ""}
                                    {formatSoles(f.delta)}
                                    {f.delta_pct !== null && (
                                      <span className="ml-1 text-xs font-normal opacity-70">
                                        ({f.delta_pct > 0 ? "+" : ""}
                                        {f.delta_pct}%)
                                      </span>
                                    )}
                                  </td>
                                  <td className="px-3 py-2 text-right tabular-nums text-xs text-taupe">
                                    {f.horas_previo.toFixed(0)} → {f.horas_actual.toFixed(0)}
                                  </td>
                                  <td className="px-3 py-2">
                                    <div className="flex flex-wrap items-center gap-1.5">
                                      {f.avisos.map((a) => (
                                        <span
                                          key={a}
                                          className="rounded-lg bg-rojo/12 px-2 py-0.5 text-xs text-rojo-profundo"
                                        >
                                          {AVISO_LABEL[a] ?? a}
                                        </span>
                                      ))}
                                      {/* La explicación NO es un aviso y no se pinta como tal:
                                          va en gris, al lado, para que quien lea la fila no
                                          tenga que ir a otra pantalla a descartar el susto. */}
                                      {f.explica.length > 0 && (
                                        <span className="text-xs text-taupe">
                                          {f.explica.map((e) => EXPLICA_LABEL[e] ?? e).join(" · ")}
                                        </span>
                                      )}
                                    </div>
                                  </td>
                                </tr>
                              ))}
                            </tbody>
                          </table>
                        </div>
                      )}

                      <label className="mt-3 flex items-center gap-2 text-xs text-taupe">
                        <input
                          type="checkbox"
                          checked={variacionTodas}
                          onChange={(e) => setVariacionTodas(e.target.checked)}
                        />
                        Mostrar también a quien no levantó ningún aviso
                      </label>
                      <p className="mt-2 text-xs text-taupe">
                        Esto no bloquea nada ni corrige nada: es una lista. Un aviso con una explicación al lado
                        casi siempre está bien; el que hay que mirar es el que aparece solo.
                      </p>
                    </>
                  )}
                </div>
              );
            })()}

            {/* Derivado, no un estado más: si hay periodo y todavía no hay
                respuesta, es que se está pidiendo. */}
            {periodoActual && !variacion && (
              <p className="mb-4 text-sm text-taupe">Comparando con el mes pasado…</p>
            )}

            {/* Pestaña Planilla / Honorarios (RxH). Un RxH no está en planilla
                —es un locador por honorarios, no tiene jornada (ver
                CLAUDE.md, exclusiones de sobretiempo)— y hasta ahora salía
                como una fila más de esta misma tabla, con "Honorarios" en
                vez de rango. Se separan aquí para que la tabla de arriba sea
                de verdad la planilla, y siguen editables en su pestaña:
                boleta, movimientos y el aviso de retención de 4ta no
                cambian. */}
            {proy && (
              <div className="mb-3 flex gap-1 border-b border-sand">
                {(["planilla", "honorarios"] as const).map((t) => (
                  <button
                    key={t}
                    onClick={() => setTablaTab(t)}
                    className={`rounded-t-lg px-4 py-2 text-sm font-medium ${
                      tablaTab === t
                        ? "border border-b-0 border-sand bg-papel text-tinta"
                        : "text-taupe hover:text-tinta"
                    }`}
                  >
                    {t === "planilla"
                      ? `Planilla (${filasPlanillaTab.length})`
                      : `Honorarios · RxH (${filasHonorariosTab.length})`}
                  </button>
                ))}
              </div>
            )}

            {/* Tabla del periodo */}
            {cargando && !proy ? (
              <Cargando />
            ) : proy ? (
              <TablaPlanilla
                filas={filasTabActiva}
                simulacion={false}
                pagado={pagado}
                sedeFiltro={sedeFiltro}
                periodoId={proy.periodo_id}
                ocupado={ocupado}
                objEdit={objEdit}
                onObjChange={(personaId, valor) => setObjEdit((prev) => ({ ...prev, [personaId]: valor }))}
                onObjBlur={(f) => void guardarObjetivos(f)}
                guardandoObj={guardandoObj}
                baseEdit={baseEdit}
                onBaseChange={(personaId, valor) => setBaseEdit((prev) => ({ ...prev, [personaId]: valor }))}
                onBaseBlur={(f) => void guardarBaseLegal(f)}
                guardandoBase={guardandoBase}
                rendEdit={rendEdit}
                onRendChange={(personaId, valor) => setRendEdit((prev) => ({ ...prev, [personaId]: valor }))}
                onRendBlur={(f) => void guardarRendimiento(f)}
                guardandoRend={guardandoRend}
                movAbierto={movAbierto}
                onToggleMov={toggleMov}
                movForm={movForm}
                origenes={origenes}
                onMovForm={setMovForm}
                onAgregarMov={(f) => void agregarMovimiento(f)}
                onQuitarMov={(m) => void quitarMovimiento(m)}
                // Sin esta línea el botón «💸 Ya le pagué aparte» NO EXISTE en la
                // pantalla: la tabla solo lo pinta si recibe este manejador, y
                // nadie se lo pasaba. `marcarYaPagado` llevaba desde su primer
                // día escrita, completa y sin llamar — código muerto que se leía
                // como una función disponible.
                //
                // Lo destapó un caso real (2026-08-10): a seis personas cesadas
                // se les registró el mismo mes dos veces —una en la foto del
                // periodo y otra en su liquidación, S/1,145.87 en total— y este
                // botón es justo el remedio que había que apretar y no estaba.
                // Ver docs/estado.md, sección A.2.b.bis.
                onYaPagado={(f) => void marcarYaPagado(f)}
                liquidadas={liquidadas}
                guardandoMov={guardandoMov}
                gc={gc}
              />
            ) : null}

            {/* Provisiones (plegable) */}
            {proy && (
              <div className="mt-4">
                <button
                  onClick={() => setMostrandoProvisiones((v) => !v)}
                  className="text-sm text-taupe hover:text-tinta hover:underline"
                >
                  {mostrandoProvisiones ? "▾" : "▸"} Provisiones del periodo (gratificación · CTS · vacaciones)
                </button>
                {mostrandoProvisiones && (
                  <div className="mt-2">
                    <div className="max-w-3xl overflow-x-auto rounded-2xl border border-sand bg-papel">
                      <table className="w-full text-sm">
                        <thead className="bg-sand/70 text-left text-taupe">
                          <tr>
                            <th className="px-4 py-2 font-normal">Nombre</th>
                            <th className="px-4 py-2 text-right font-normal">Gratificación</th>
                            <th className="px-4 py-2 text-right font-normal">CTS</th>
                            <th className="px-4 py-2 text-right font-normal">Vacaciones</th>
                            <th className="px-4 py-2 text-right font-normal">Total provisión</th>
                          </tr>
                        </thead>
                        <tbody>
                          {filasVisibles.length === 0 && (
                            <tr>
                              <td colSpan={5} className="px-4 py-6 text-center text-taupe">
                                No hay personas para mostrar en este periodo.
                              </td>
                            </tr>
                          )}
                          {filasVisibles.map((f) => (
                            <tr key={f.persona_id} className="border-t">
                              <td className="px-4 py-2">{f.nombre}</td>
                              <td className="px-4 py-2 text-right">{formatSoles(f.provision_gratificacion)}</td>
                              <td className="px-4 py-2 text-right">{formatSoles(f.provision_cts)}</td>
                              <td className="px-4 py-2 text-right">{formatSoles(f.provision_vacaciones)}</td>
                              <td className="px-4 py-2 text-right font-medium">{formatSoles(f.provision_total)}</td>
                            </tr>
                          ))}
                        </tbody>
                        {filasVisibles.length > 0 && (
                          <tfoot>
                            <tr className="border-t bg-sand/50">
                              <td className="px-4 py-2 font-medium">Total</td>
                              <td className="px-4 py-2 text-right font-medium">{formatSoles(provTotales.gratificacion)}</td>
                              <td className="px-4 py-2 text-right font-medium">{formatSoles(provTotales.cts)}</td>
                              <td className="px-4 py-2 text-right font-medium">{formatSoles(provTotales.vacaciones)}</td>
                              <td className="px-4 py-2 text-right font-bold">{formatSoles(provTotales.total)}</td>
                            </tr>
                          </tfoot>
                        )}
                      </table>
                    </div>
                    <p className="mt-2 max-w-3xl text-xs text-taupe">
                      Las provisiones NO forman parte del pago del periodo: son acumulación futura
                      (ahorro/deuda que se va juntando). Factores MYPE editables en configuración — validar con el contador.
                    </p>
                  </div>
                )}
              </div>
            )}

            {/* Simulador (plegable, solo lectura) */}
            <div className="mt-4">
              <button
                onClick={() => setMostrandoSim((v) => !v)}
                className="text-sm text-taupe hover:text-tinta hover:underline"
              >
                {mostrandoSim ? "▾" : "▸"} Simular otro rango de fechas
              </button>
              {mostrandoSim && (
                <div className="mt-2 rounded-lg border bg-sand/30 p-4">
                  <div className="flex flex-wrap items-end gap-3">
                    <label className="flex flex-col gap-1 text-sm">
                      Desde
                      <input
                        type="date"
                        value={simIni}
                        onChange={(e) => setSimIni(e.target.value)}
                        className="rounded-lg border px-3 py-2"
                      />
                    </label>
                    <label className="flex flex-col gap-1 text-sm">
                      Hasta
                      <input
                        type="date"
                        value={simFin}
                        onChange={(e) => setSimFin(e.target.value)}
                        className="rounded-lg border px-3 py-2"
                      />
                    </label>
                    <button
                      onClick={() => void simular()}
                      disabled={simCargando || !simIni || !simFin}
                      className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50"
                    >
                      {simCargando ? "Calculando…" : "Calcular"}
                    </button>
                  </div>
                  <p className="mt-2 text-xs text-taupe">
                    Rango libre de hasta 62 días, solo para mirar: no crea periodos ni guarda nada.
                  </p>
                  {simError && (
                    <div className="mt-3 max-w-3xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
                      No se pudo simular: {simError}
                    </div>
                  )}
                  {simProy && !simError && (
                    <div className="mt-3">
                      <div className="mb-3 rounded-lg bg-ambar/15 px-4 py-3 text-sm text-ambar">
                        SIMULACIÓN — nada de esto se guarda. {fechaCorta(simProy.fecha_ini)} →{" "}
                        {fechaCorta(simProy.fecha_fin)} · {simProy.dias} días · base {fmtHoras(simProy.base_horas)}.
                        Sin bonos ni descuentos (esos viven en cada periodo oficial).
                      </div>
                      <TablaPlanilla
                        filas={simFilasTabActiva}
                        simulacion={true}
                        pagado={false}
                        sedeFiltro={sedeFiltro}
                      />
                    </div>
                  )}
                </div>
              )}
            </div>

            <p className="mt-4 max-w-2xl text-xs text-taupe">
              Proyección referencial basada en horas registradas. El total por persona ya incluye
              asignación familiar y bonos, y resta descuentos.
            </p>
          </>
        )}
      </main>
    </div>
  );
}

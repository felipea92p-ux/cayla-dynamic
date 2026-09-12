"use client";

import { Fragment, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { Search } from "lucide-react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Cargando, SinDatos } from "@/components/cargando";
import { useToast } from "@/components/toast";
import { useRolActual } from "@/lib/admin/use-rol";
import { useFiltroGuardado } from "@/lib/admin/use-filtro-guardado";
import { RANGO_LABEL, formatSoles } from "@/lib/rangos";
import { descargarCsv, generarCsv } from "@/lib/admin/csv";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { Modal } from "@/components/ui/modal";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
// "Fila" ya es el nombre de la interfaz de negocio de este archivo (una fila
// de planilla) — el <tr> compartido del primitivo entra con alias para no
// chocar.
import { Tabla, TablaEncabezado, Th, Fila as FilaTabla } from "@/components/ui/tabla";
import {
  TZ_LIMA, parsearMontoSoles, puedeVerPlanilla,
  TIPOS_VINCULO, TIPO_VINCULO_LABEL, type TipoVinculo,
} from "@cayla-dynamic/shared";

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

// Hoy en Lima como AAAA-MM-DD — para comparar contra `fecha_fin` (mismo
// formato) y para el valor inicial de un <input type="date">.
function hoyLimaISO(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: TZ_LIMA }).format(new Date());
}

// "2026-07-14" → "14/07/2026" — el formato que ya llevan escrito el concepto
// de "Ya le pagué aparte" y el de un desembolso adelantado.
function isoADiaMesAnio(iso: string): string {
  const [y, m, d] = iso.split("-");
  return `${d}/${m}/${y}`;
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
  // El mismo recargo de arriba, partido en 25 % y 35 % (0349) — lo pidió el
  // contador para conciliar contra los códigos 0105/0106 de la PLAME.
  // `monto_sobretiempo_25 + monto_sobretiempo_35` siempre suma exacto
  // `monto_sobretiempo`; ver el comentario de la migración para el porqué.
  // Opcionales por lo mismo que el resto: una base sin la 0349 pegada no
  // manda las claves, y la boleta tiene que seguir saliendo igual que antes.
  monto_sobretiempo_25?: number;
  monto_sobretiempo_35?: number;
  horas_sobretiempo_25?: number;
  horas_sobretiempo_35?: number;
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
// El estado de pago de UN grupo (tipo_vinculo) dentro del periodo — 0323.
// Sale de fn_proyeccion_periodo (clave 'grupos'), siempre las 5 aunque un
// grupo no tenga a nadie ese periodo: `personas` en 0 es la señal de que la
// pestaña está vacía, no que falte el dato.
export interface GrupoPago {
  grupo: TipoVinculo;
  estado: "abierto" | "pagado";
  pagado_at: string | null;
  pagado_por_nombre: string | null;
  personas: number;
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
// CAMBIO 0346 — bonificacion_extraordinaria es una categoría más sobre un bono,
// igual que gratificacion/cts: su monto lo calcula fn_grati_cts_periodo (el 9%
// de Ley 30334 sobre la MISMA gratificación de este semestre) y se autocompleta
// al elegirla, como movimiento separado del de «Gratificación».
type ClaseMov = "bono" | "descuento" | "vacaciones" | "gratificacion" | "cts" | "bonificacion_extraordinaria" | "otros";
const CLASE_A_TIPO: Record<ClaseMov, "bono" | "descuento"> = {
  bono: "bono", descuento: "descuento", vacaciones: "bono", gratificacion: "bono", cts: "bono",
  bonificacion_extraordinaria: "bono", otros: "bono",
};
const CLASE_A_CATEGORIA: Record<ClaseMov, string | null> = {
  bono: null, descuento: null, vacaciones: "vacaciones", gratificacion: "gratificacion", cts: "cts",
  bonificacion_extraordinaria: "bonificacion_extraordinaria", otros: "otros",
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
  bono: "Bono", descuento: "Descuento", vacaciones: "Vacaciones", gratificacion: "Gratificación", cts: "CTS",
  bonificacion_extraordinaria: "Bonificación 9% (Ley 30334)", otros: "Otros",
};
const CLASE_PLACEHOLDER: Record<ClaseMov, string> = {
  bono: "ej. reconocimiento del mes",
  descuento: "ej. adelanto quincenal",
  vacaciones: "ej. Vacaciones 22–28 jul 2026",
  gratificacion: "el sistema lo calcula",
  cts: "el sistema lo calcula",
  bonificacion_extraordinaria: "el sistema lo calcula",
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
// CAMBIO 0346 — beConcepto y el campo be de porPersona: el 9% de Ley 30334,
// del mismo monto de grati, para registrarse como movimiento aparte.
interface GratiCts {
  gratiAplica: boolean;
  gratiConcepto: string;
  ctsAplica: boolean;
  ctsConcepto: string;
  beConcepto: string;
  porPersona: Record<string, { grati: number; cts: number; be: number }>;
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

// Un periodo ya terminó y nadie lo dice: `estado` es el agregado de los 5
// grupos (fn_periodos), así que "abierto" con `fecha_fin` ya pasada significa
// que a alguien le falta pagar. Entre varios así —no debería pasar, pero el
// desplegable no lo impide—, el más antiguo sigue siendo el más urgente de
// cerrar: se conserva sin cambios para la insignia y el aviso "terminó y
// sigue sin pagar →". Lo que cambia es CUÁL periodo abre la pantalla por
// defecto — ver `periodoInicialSugerido`, más abajo — porque esa es una
// pregunta distinta: "qué es más urgente cerrar" no es lo mismo que "qué
// periodo hace falta mirar hoy".
function periodoVencidoSinPagar(lista: PeriodoInfo[], hoyIso: string): PeriodoInfo | null {
  const vencidos = lista.filter((p) => p.estado === "abierto" && p.fecha_fin < hoyIso);
  if (vencidos.length === 0) return null;
  return vencidos.reduce((a, b) => (a.fecha_fin < b.fecha_fin ? a : b));
}

// CAMBIO 2026-09-12 (decisión de Felipe). Hasta hoy la carga inicial abría
// directo en `periodoVencidoSinPagar` (el MÁS ANTIGUO sin pagar) apenas
// existía uno — y con dos periodos vencidos a la vez (pasa seguido: nadie
// cierra el mismo día que vence) la pantalla podía arrancar dos meses atrás
// del periodo real. El 2026-09-12 eso hizo que tres practicantes recién
// ingresados (04, 05 y 11 de septiembre) salieran con "Sin horario asignado"
// al abrir Planilla: el horario SÍ estaba cargado — el periodo que se veía
// por defecto (28 jun → 28 jul) era anterior a que existieran.
//
// LA REGLA QUEDA: si HOY cae dentro del rango de algún periodo sin pagar
// (`fecha_ini <= hoy <= fecha_fin`, sea el mes en curso o uno que ya venció),
// ese es el que se ve — es el que de verdad hace falta mirar hoy. Solo si
// ninguno contiene a hoy (nadie ha creado el periodo del mes en curso
// todavía) se cae al más antiguo sin pagar, que sigue siendo lo más urgente
// de cerrar en ese caso. El periodo vencido más viejo NUNCA se pierde de
// vista: sigue con su propia insignia y su enlace "terminó y sigue sin
// pagar →" para llegar ahí con un clic.
function periodoInicialSugerido(lista: PeriodoInfo[], hoyIso: string): PeriodoInfo | null {
  const deHoy = lista.find(
    (p) => p.estado !== "pagado" && p.fecha_ini <= hoyIso && hoyIso <= p.fecha_fin,
  );
  return deHoy ?? periodoVencidoSinPagar(lista, hoyIso);
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
  /** CAMBIO 0343 — Registrar un adelanto de gratificación/CTS/vacaciones fuera
   *  del ciclo normal (típicamente a alguien que cesa a mitad de semestre),
   *  en el libro de desembolsos — no en movimientos_planilla. */
  onRegistrarDesembolso?: (f: Fila) => void;
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
    onRegistrarDesembolso,
    liquidadas = {},
    guardandoMov = false, gc = null, origenes = [],
  } = props;
  // Al elegir grati/CTS en el desplegable, autocompleta concepto y el monto que el
  // sistema calculó para esa persona en este periodo. El resto queda manual.
  const alCambiarTipo = (f: Fila, t: ClaseMov) => {
    if ((t === "gratificacion" || t === "cts" || t === "bonificacion_extraordinaria") && gc) {
      const gp = gc.porPersona[f.persona_id];
      const monto = t === "gratificacion" ? gp?.grati : t === "cts" ? gp?.cts : gp?.be;
      const concepto = t === "gratificacion" ? gc.gratiConcepto : t === "cts" ? gc.ctsConcepto : gc.beConcepto;
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
    <Tabla>
      <TablaEncabezado>
        <Th>Nombre</Th>
        <Th>Sede</Th>
        <Th>Rango y salario</Th>
        <Th>Horas</Th>
        <Th className="text-right">Pago base</Th>
        <Th className="text-right">Feriados</Th>
        <Th className="text-right">Asig. familiar</Th>
        {/* Objetivos, Rendim. y Plus salieron de acá el 2026-08-06 (mig 0171).
            Los objetivos siguen existiendo en /admin/objetivos, pero como
            historial para promover: dejaron de pagar. Y el rendimiento dejó
            de escalar el sueldo — escribir un 80 ahí recortaba una
            remuneración con dos clics, que el art. 30.b de la LPCL prohíbe. */}
        <Th className="text-right">
          {/* Th no reenvía `title` (solo toma children/className) — el tooltip
              va en un span propio adentro. */}
          <span title="Remuneración básica legal mensual: la que se declara en PLAME. Vacía = la boleta no imprime esa línea.">
            Básica legal
          </span>
        </Th>
        <Th className="text-right">Bonos</Th>
        <Th className="text-right">Descuentos</Th>
        <Th className="text-right">Total</Th>
      </TablaEncabezado>
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
                      <Insignia variante="neutral" atenuada className="ml-1.5">
                        ya no está
                      </Insignia>
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
                    {/* CAMBIO 0343 · Sin `onRegistrarDesembolso` este botón no
                        existe, igual que "Ya le pagué aparte" antes de la 0210
                        — nace desconectado hasta que alguien lo cablea abajo.
                        No se condiciona a `f.total > 0`: un adelanto de
                        beneficio se puede dar aunque el sueldo del periodo ya
                        esté en cero. */}
                    {editable && onRegistrarDesembolso && (
                      <>
                        <br />
                        <button
                          onClick={() => onRegistrarDesembolso(f)}
                          disabled={ocupado}
                          title="Registrar un adelanto de gratificación, CTS o vacaciones fuera del ciclo normal"
                          className="text-xs text-taupe underline decoration-taupe/30 underline-offset-2 hover:text-tinta hover:decoration-tinta disabled:opacity-50"
                        >
                          🎁 Adelanto de beneficio
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
                        {f.tipo_vinculo === "practicante"
                          ? "Subvención"
                          : f.en_planilla === false
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
                      <span title="Días auto-cerrados sin revisar — corrígelos en Correcciones">
                        <Insignia variante="advertencia" className="ml-2">
                          {f.dias_pendientes} pend.
                        </Insignia>
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
                        <span title="Retención de Impuesto a la Renta de 4ta categoría (8 %). Se paga a SUNAT a nombre de la persona.">
                          <Insignia variante="alerta">
                            4ta −{formatSoles(f.retencion_4ta ?? 0)}
                          </Insignia>
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
                          <CampoSelect
                            etiqueta="Tipo"
                            value={movForm.tipo}
                            onChange={(e) => alCambiarTipo(f, e.target.value as ClaseMov)}
                            disabled={pagado || guardandoMov}
                            title={pagado ? hintPagado : undefined}
                          >
                            <option value="bono">Bono</option>
                            <option value="descuento">Descuento</option>
                            <option value="vacaciones">Vacaciones</option>
                            {/* Solo en el periodo que corresponde (fecha de pago legal dentro del rango) */}
                            {gc?.gratiAplica && <option value="gratificacion">{CLASE_LABEL.gratificacion}</option>}
                            {/* CAMBIO 0346 — sigue la misma aplicabilidad que la gratificación: es un 9% de ese mismo monto. */}
                            {gc?.gratiAplica && <option value="bonificacion_extraordinaria">{CLASE_LABEL.bonificacion_extraordinaria}</option>}
                            {gc?.ctsAplica && <option value="cts">{CLASE_LABEL.cts}</option>}
                            <option value="otros">Otros</option>
                          </CampoSelect>
                          <Campo
                            etiqueta="Concepto"
                            value={movForm.concepto}
                            onChange={(e) => onMovForm?.({ ...movForm, concepto: e.target.value })}
                            placeholder={CLASE_PLACEHOLDER[movForm.tipo]}
                            disabled={pagado || guardandoMov}
                            title={pagado ? hintPagado : undefined}
                            className="w-52"
                          />
                          <Campo
                            etiqueta="Monto (S/)"
                            type="number"
                            min={0.01}
                            step={0.01}
                            value={movForm.monto}
                            onChange={(e) => onMovForm?.({ ...movForm, monto: e.target.value })}
                            placeholder="0.00"
                            disabled={pagado || guardandoMov}
                            title={pagado ? hintPagado : undefined}
                            className="w-24 text-right"
                          />
                          {/* CAMBIO 0305 — Solo aparece si HAY meses ya pagados
                              antes de este. En el primer periodo de la historia
                              no hay nada que corregir, y un desplegable vacío
                              solo invita a preguntarse qué falta. */}
                          {origenes.length > 0 && (
                            <CampoSelect
                              etiqueta="¿Corrige un mes anterior?"
                              value={movForm.origen}
                              onChange={(e) => onMovForm?.({ ...movForm, origen: e.target.value })}
                              disabled={pagado || guardandoMov}
                              title={pagado ? hintPagado : "Si esto paga una diferencia de un mes ya cerrado, dilo acá: queda registrado de dónde viene."}
                            >
                              <option value="">No — es de este mes</option>
                              {origenes.map((o) => (
                                <option key={o.id} value={o.id}>{o.etiqueta}</option>
                              ))}
                            </CampoSelect>
                          )}
                          <Boton
                            variante="primario"
                            onClick={() => onAgregarMov?.(f)}
                            disabled={pagado || ocupado}
                            cargando={guardandoMov}
                            title={pagado ? hintPagado : undefined}
                          >
                            Agregar
                          </Boton>
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
    </Tabla>
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
  const [errorDesvios, setErrorDesvios] = useState<string | null>(null);
  const [variacion, setVariacion] = useState<Variacion | null>(null);
  const [mostrandoVariacion, setMostrandoVariacion] = useState(false);
  const [variacionTodas, setVariacionTodas] = useState(false);

  // Crear periodo (primero / encadenado)
  const [primerIni, setPrimerIni] = useState("");
  const [primerFin, setPrimerFin] = useState("");
  const [mostrandoNuevo, setMostrandoNuevo] = useState(false);
  const [nuevoFin, setNuevoFin] = useState("");
  const [creandoPeriodo, setCreandoPeriodo] = useState(false);

  // Proyección del periodo seleccionado
  const [proy, setProy] = useState<Proyeccion | null>(null);
  // El estado de pago de los 5 grupos (tipo_vinculo) — 0323, fn_periodo_grupos_estado.
  // Función aparte de fn_proyeccion_periodo: llena las pestañas y sus candados.
  const [grupos, setGrupos] = useState<GrupoPago[] | null>(null);
  const [gc, setGc] = useState<GratiCts | null>(null);
  // Quién de este periodo ya cobró su liquidación (0210), indexado por
  // persona_id. `{}` significa «no hay ninguna», que es lo normal casi todos los
  // meses; nunca null, para que la búsqueda por clave no tenga que defenderse.
  const [liquidadas, setLiquidadas] = useState<Record<string, Liquidada>>({});
  const [cargando, setCargando] = useState(false);
  const [errorCarga, setErrorCarga] = useState<string | null>(null);
  const { avisar } = useToast();
  const reqId = useRef(0); // "última carga gana": descarta respuestas fuera de orden

  // Preferencia de VISTA — se acuerda entre visitas (ver use-filtro-guardado.ts):
  // quien solo mira su sede no debería reelegirla cada vez que abre Planilla.
  const [sedeFiltro, setSedeFiltro] = useFiltroGuardado("planilla.sede", "todas");
  // Activos / ya no están / todos. Arranca en "activos" porque es lo que se mira
  // el 99 % de las veces; el aviso de abajo cubre el 1 % peligroso.
  const [estadoFiltro, setEstadoFiltro] = useFiltroGuardado<"activos" | "inactivos" | "todos">("planilla.estado", "activos");
  // Texto de búsqueda: NUNCA con useFiltroGuardado — es de esta visita, no de
  // "cómo miro siempre esta pantalla" (ver use-filtro-guardado.ts).
  const [nombreFiltro, setNombreFiltro] = useState("");
  // Una pestaña por tipo_vinculo (0323): cada una es su propio candado de
  // pago —RxH se paga más tarde que planilla, y ya no hace falta fingir que
  // se pagó todo el mismo día—. Antes era un binario planilla/honorarios; con
  // el pago por grupo, "prueba" y "practicante" también necesitan la suya.
  const [tablaTab, setTablaTab] = useState<TipoVinculo>("planilla");

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
  // CAMBIO 0355 — «Agregar todo» de gratificación/CTS/bonificación pendientes.
  const [guardandoBulk, setGuardandoBulk] = useState(false);

  // ── Diálogos del sistema operativo migrados a <Modal> ──────────────────────
  // Felipe aprobó migrar TODOS los window.confirm/alert/prompt de este panel
  // (ver CLAUDE.md): no se pintan con ningún --color-* y no siguen el modo
  // oscuro, y un window.prompt() se cierra solo al primer error y se lleva el
  // texto escrito. No cambia qué función se llama al confirmar — solo cómo se
  // pregunta.
  //
  // Los seis confirm() + el único alert() de esta pantalla comparten un solo
  // Modal genérico: los seis solo necesitan mensaje + Sí/Cancelar (o, en el
  // caso del alert, un único "Entendido"), y nada de lo que preguntan se
  // escribe — es la misma razón por la que no hace falta un Modal por acción,
  // a diferencia de los prompt() de abajo, que sí piden datos.
  const [confirmPendiente, setConfirmPendiente] = useState<{
    mensaje: string;
    /** null = solo informativo (antes window.alert) — un único botón "Entendido". */
    accion: (() => void | Promise<void>) | null;
    variante?: "primario" | "peligro";
    textoBoton?: string;
  } | null>(null);

  // Reabrir un pago pagado, y Volver a pagar (repagarPeriodo): los dos
  // pedían un motivo obligatorio por window.prompt(). Se quedan cada uno con
  // su propio Modal (no el genérico de arriba) porque piden un dato, con la
  // misma forma que ya usa Correcciones: <textarea autoFocus> dentro de un
  // Modal, Cancelar/Confirmar.
  const [reabrirModal, setReabrirModal] = useState<TipoVinculo | null>(null);
  const [reabrirMotivo, setReabrirMotivo] = useState("");
  const [repagoModal, setRepagoModal] = useState(false);
  const [repagoMotivo, setRepagoMotivo] = useState("");

  // «Ya le pagué aparte»: antes dos window.prompt() en cadena (monto, fecha).
  const [yaPagadoModal, setYaPagadoModal] = useState<{ fila: Fila; sugerido: number; liq: Liquidada | null } | null>(null);
  const [yaPagadoMonto, setYaPagadoMonto] = useState("");
  const [yaPagadoFecha, setYaPagadoFecha] = useState("");

  // «Adelanto de beneficio»: antes cuatro window.prompt() en cadena (tipo,
  // monto, fecha, nota).
  const [desembolsoModal, setDesembolsoModal] = useState<Fila | null>(null);
  const [desembolsoForm, setDesembolsoForm] = useState<{
    beneficio: "gratificacion" | "cts" | "vacaciones";
    monto: string;
    fecha: string;
    nota: string;
  }>({ beneficio: "gratificacion", monto: "", fecha: "", nota: "" });

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

  // Carga inicial: lista + selección. `periodoInicialSugerido` (arriba)
  // prefiere el periodo que CONTIENE a hoy, sin importar si ya venció; si
  // ninguno contiene a hoy, cae al más antiguo sin pagar. Antes de la 2026-
  // 09-12 se saltaba directo a "el más antiguo sin pagar" en cuanto existía
  // uno, así que con dos periodos vencidos a la vez la pantalla podía abrir
  // dos meses atrás del que de verdad hacía falta mirar.
  useEffect(() => {
    void (async () => {
      const lista = await cargarPeriodos();
      if (lista && lista.length > 0) {
        const sugerido = periodoInicialSugerido(lista, hoyLimaISO());
        setPeriodoSel((prev) => prev ?? sugerido?.id ?? lista[0].id);
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

  // CAMBIO 0355 — cuánto hay pendiente de gratificación/CTS/bonificación en
  // este periodo, para el banner de «Agregar todo». Se lee de gc.porPersona
  // —el mismo dato que ya autocompleta cada fila a mano—, así que si alguien
  // ya está pagado (grati=0) no cuenta ni como persona ni como movimiento.
  const pendientesGratiCts = useMemo(() => {
    if (!gc) return null;
    let personas = 0, movimientos = 0, total = 0;
    for (const v of Object.values(gc.porPersona)) {
      const suma = v.grati + v.be + v.cts;
      if (suma <= 0) continue;
      personas++;
      movimientos += (v.grati > 0 ? 1 : 0) + (v.be > 0 ? 1 : 0) + (v.cts > 0 ? 1 : 0);
      total += suma;
    }
    return personas > 0 ? { personas, movimientos, total } : null;
  }, [gc]);

  const periodoActual = useMemo(
    () => periodos?.find((p) => p.id === periodoSel) ?? null,
    [periodos, periodoSel],
  );
  const esUltimo = periodos !== null && periodos.length > 0 && periodoSel === periodos[0].id;
  const pagado = periodoActual?.estado === "pagado";
  // El periodo que se está mirando terminó y no está pagado — se recalcula con
  // `periodos` completo (no solo el seleccionado) para poder avisar aunque la
  // encargada haya cambiado a otro periodo desde el que arrancó por defecto.
  const periodoVencido = useMemo(
    () => (periodos ? periodoVencidoSinPagar(periodos, hoyLimaISO()) : null),
    [periodos],
  );
  const viendoElVencido = periodoVencido !== null && periodoVencido.id === periodoSel;

  // Solo tiene sentido preguntarlo cuando el periodo está pagado: es la única
  // situación en la que existe una foto contra la que comparar.
  const cargarDesvios = useCallback(async () => {
    if (!puedeVer || !periodoActual || periodoActual.estado !== "pagado") {
      setDesvios(null);
      setErrorDesvios(null);
      return;
    }
    setErrorDesvios(null);
    const { data, error } = await supabase.rpc("fn_planilla_foto_diferencias", {
      p_periodo_id: periodoActual.id,
    });
    // Si la consulta falla no se dice «todo cuadra»: se deja en desconocido —
    // y desde acá SE MUESTRA como error (antes el dato distinguía null de [],
    // pero la pantalla nunca leía esa diferencia: un fallo se veía exactamente
    // igual que «no hay desvíos», el falso negativo que ninguna consulta que
    // puede fallar debería producir en silencio).
    if (error) {
      setDesvios(null);
      setErrorDesvios(error.message);
      return;
    }
    setDesvios((data as unknown as Desvio[]) ?? []);
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
    // Estado de pago por grupo (0323) — falla suave: si no llega, las pestañas
    // se quedan sin candado y `grupoActivoPagado` cae en "abierto" (defecto
    // seguro: sigue pidiendo confirmación en vez de dar algo por pagado).
    const { data: gruposData, error: gruposError } = await supabase.rpc("fn_periodo_grupos_estado", { p_periodo_id: id });
    if (mi !== reqId.current) return;
    setGrupos(gruposError ? null : ((gruposData as unknown as GrupoPago[]) ?? null));
    // Grati/CTS que toca en este periodo (falla suave: si no llega, el desplegable
    // simplemente no muestra esas opciones y la planilla sigue igual).
    const { data: gcData } = await supabase.rpc("fn_grati_cts_periodo", { p_periodo_id: id });
    if (mi !== reqId.current) return;
    const g = gcData as unknown as {
      grati_aplica: boolean; grati_concepto: string;
      cts_aplica: boolean; cts_concepto: string;
      be_concepto: string;
      personas: { persona_id: string; grati: number; cts: number; be: number }[];
    } | null;
    setGc(g ? {
      gratiAplica: Boolean(g.grati_aplica),
      gratiConcepto: g.grati_concepto ?? "",
      ctsAplica: Boolean(g.cts_aplica),
      ctsConcepto: g.cts_concepto ?? "",
      beConcepto: g.be_concepto ?? "",
      porPersona: Object.fromEntries((g.personas ?? []).map((x) => [x.persona_id, { grati: Number(x.grati) || 0, cts: Number(x.cts) || 0, be: Number(x.be) || 0 }])),
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

  function eliminarPeriodo() {
    if (!periodoActual) return;
    const periodoId = periodoActual.id;
    setConfirmPendiente({
      mensaje:
        `¿Eliminar el periodo ${fechaCorta(periodoActual.fecha_ini)} → ${fechaCorta(periodoActual.fecha_fin)}? ` +
        "Se pierden los bonos y descuentos registrados en él. Solo se puede eliminar el último periodo abierto.",
      variante: "peligro",
      textoBoton: "Eliminar",
      accion: async () => {
        setGuardandoPeriodo(true);
        const { error } = await supabase.rpc("fn_eliminar_periodo", { p_periodo_id: periodoId });
        setGuardandoPeriodo(false);
        if (error) {
          avisar("error", mensajeDeError(error, "eliminar el periodo"));
          return;
        }
        avisar("ok", "Periodo eliminado.");
        const lista = await cargarPeriodos();
        setPeriodoSel(lista && lista.length > 0 ? lista[0].id : null);
      },
    });
  }

  // CAMBIO 0284, ahora por grupo (0323) — Días con la salida puesta por el
  // sistema y sin confirmar. Sobre TODAS las filas del periodo y NUNCA sobre
  // `filasVisibles`, por la misma razón que el aviso de arriba: si el filtro
  // esconde justo a esa persona, el aviso desaparecería y el freno de la base
  // saltaría igual — avisando de alguien que la pantalla no está mostrando.
  // El freno de verdad vive en `fn_planilla_congelar`, y desde la 0323 mira
  // solo el grupo que se está congelando: este aviso hace lo mismo por grupo,
  // para no bloquear pagar RxH por un pendiente que es de planilla.
  const diasPendientesPorGrupo = useMemo(() => {
    const m = new Map<TipoVinculo, { personas: number; dias: number; nombres: string[] }>();
    for (const f of proy?.filas ?? []) {
      if (f.dias_pendientes <= 0) continue;
      const g = TIPOS_VINCULO.includes(f.tipo_vinculo as TipoVinculo) ? (f.tipo_vinculo as TipoVinculo) : "planilla";
      const acc = m.get(g) ?? { personas: 0, dias: 0, nombres: [] };
      acc.personas += 1;
      acc.dias += f.dias_pendientes;
      acc.nombres.push(f.nombre);
      m.set(g, acc);
    }
    return m;
  }, [proy]);

  // CAMBIO 0323 — gana `grupo`: cada tipo_vinculo se paga y se reabre por su
  // cuenta (fn_periodo_pagado/fn_revertir_pago ahora piden el grupo). El
  // periodo entero sigue existiendo como AGREGADO en la base —pasa a pagado
  // solo cuando los 5 grupos con gente ya lo están— pero el botón vive por
  // pestaña.
  function marcarPagado(grupo: TipoVinculo, pagar: boolean) {
    if (!periodoActual) return;
    const periodoId = periodoActual.id;
    const etiqueta = TIPO_VINCULO_LABEL[grupo];
    if (pagar) {
      // CAMBIO 0284 — Se avisa ANTES de intentarlo. La base lo frena igual
      // (fn_planilla_congelar), pero llegar hasta el error con el diálogo ya
      // aceptado se lee como que el sistema falló, y no es eso: es que faltan
      // horas por confirmar. Decirlo acá convierte un error en una instrucción.
      const pendientes = diasPendientesPorGrupo.get(grupo);
      if (pendientes) {
        setConfirmPendiente({
          mensaje:
            `Todavía no se puede pagar «${etiqueta}».\n\n` +
            `Hay ${pendientes.dias} día(s) cuya hora de salida la puso el sistema porque nadie marcó, ` +
            `y aún están sin confirmar: ${pendientes.nombres.join(", ")}.\n\n` +
            `Esa hora no la marcó ninguna persona, y si cruza las 48 h de la semana se paga recargo sobre ella. ` +
            `Entra a Correcciones, confirma o corrige esas salidas, y vuelve aquí.`,
          accion: null,
        });
        return;
      }
      setConfirmPendiente({
        mensaje:
          `Marcar «${etiqueta}» como PAGADO guarda una copia intacta del desglose de cada persona de ese grupo: ` +
          "es el número que queda para contabilidad y ya no cambia solo.\n\n" +
          "Si después hay que corregir algo, se reabre con Revertir pago (queda el motivo) y se vuelve " +
          "a marcar como pagado: se guarda una copia nueva y la anterior se conserva.\n\n¿Continuar?",
        textoBoton: "Marcar como pagado",
        accion: async () => {
          setGuardandoPeriodo(true);
          const { error } = await supabase.rpc("fn_periodo_pagado", {
            p_periodo_id: periodoId, p_pagado: true, p_grupo: grupo,
          });
          setGuardandoPeriodo(false);
          if (error) { avisar("error", mensajeDeError(error, "actualizar el periodo")); return; }
          avisar("ok", `«${etiqueta}» marcado como PAGADO 🔒.`);
          await Promise.all([cargarPeriodos(), cargarProyeccion()]);
        },
      });
      return;
    }
    // Reabrir un pago DEJA RASTRO: se pide el motivo y queda auditado
    // (quién/cuándo/por qué) — por eso tiene su propio Modal con <textarea>
    // en vez del confirm genérico de arriba.
    setReabrirMotivo("");
    setReabrirModal(grupo);
  }

  async function confirmarReabrir() {
    if (!periodoActual || !reabrirModal) return;
    const motivo = reabrirMotivo.trim();
    if (motivo.length < 4) {
      avisar("error", "El motivo de la reapertura es obligatorio (mínimo 4 caracteres).");
      return;
    }
    const grupo = reabrirModal;
    const etiqueta = TIPO_VINCULO_LABEL[grupo];
    setGuardandoPeriodo(true);
    const { error } = await supabase.rpc("fn_revertir_pago", {
      p_periodo_id: periodoActual.id, p_motivo: motivo, p_grupo: grupo,
    });
    setGuardandoPeriodo(false);
    if (error) { avisar("error", mensajeDeError(error, "reabrir")); return; }
    setReabrirModal(null);
    avisar("ok", `«${etiqueta}» reabierto con registro. Corrige lo necesario y vuelve a marcarlo como PAGADO.`);
    await Promise.all([cargarPeriodos(), cargarProyeccion()]);
  }

  // Volver a pagar NO reabre el periodo: los candados de sus marcajes no se
  // levantan en ningún momento (fn_repagar_periodo). Desde la 0323 recalcula
  // UN grupo a la vez —el de la pestaña activa—, porque cada grupo tiene su
  // propia foto. Si el desvío de abajo es de otro grupo, cambia de pestaña y
  // vuelve a apretar el botón ahí.
  function repagarPeriodo() {
    if (!periodoActual) return;
    setRepagoMotivo("");
    setRepagoModal(true);
  }

  async function confirmarRepago() {
    if (!periodoActual) return;
    const motivo = repagoMotivo.trim();
    if (motivo.length < 4) {
      avisar("error", "El motivo es obligatorio: volver a pagar cambia una cifra que ya se entregó.");
      return;
    }
    setGuardandoPeriodo(true);
    const { data, error } = await supabase.rpc("fn_repagar_periodo", {
      p_periodo_id: periodoActual.id,
      p_motivo: motivo,
      p_grupo: tablaTabEfectiva,
    });
    setGuardandoPeriodo(false);
    if (error) { avisar("error", mensajeDeError(error, "volver a pagar")); return; }
    setRepagoModal(false);
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

  function quitarFeriado(f: Feriado) {
    setConfirmPendiente({
      mensaje: `¿Quitar el feriado "${f.nombre}" (${fechaCorta(f.fecha)})? La planilla dejará de pagarlo doble.`,
      variante: "peligro",
      textoBoton: "Quitar",
      accion: async () => {
        setGuardandoFeriado(true);
        const { error } = await supabase.rpc("fn_quitar_feriado", { p_fecha: f.fecha });
        setGuardandoFeriado(false);
        if (error) {
          avisar("error", mensajeDeError(error, "quitar el feriado"));
          return;
        }
        avisar("ok", "Feriado quitado.");
        await Promise.all([cargarFeriadosAnio(), cargarProyeccion()]);
      },
    });
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

  function agregarMovimiento(f: Fila) {
    if (!proy?.periodo_id) return;
    const periodoId = proy.periodo_id;
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
    const tipo = movForm.tipo;
    const origen = movForm.origen;
    // Mismo candado que las otras seis acciones de dinero de esta pantalla
    // (quitar movimiento, marcar pagado, repagar periodo, eliminar periodo,
    // quitar feriado, agregar pendientes de grati/CTS): confirmar el monto
    // exacto antes de escribir, para que un typo de un dígito (S/350 →
    // S/3500) no se guarde sin que nadie lo revise primero.
    setConfirmPendiente({
      mensaje: `¿Registrar ${CLASE_LABEL[tipo]} de ${formatSoles(monto)} para ${f.nombre} — "${concepto}"?`,
      accion: async () => {
        setGuardandoMov(true);
        const { error } = await supabase.rpc("fn_agregar_movimiento", {
          p_periodo_id: periodoId,
          p_persona_id: f.persona_id,
          p_tipo: CLASE_A_TIPO[tipo],
          p_concepto: concepto,
          p_monto: monto,
          p_categoria: CLASE_A_CATEGORIA[tipo],
          // CAMBIO 0305 — vacío significa «no corrige nada», y la base lo espera en
          // null, no en cadena vacía.
          p_periodo_origen_id: origen || null,
        });
        setGuardandoMov(false);
        if (error) {
          avisar("error", mensajeDeError(error, "registrar el movimiento"));
          return;
        }
        avisar("ok", `${CLASE_LABEL[tipo]} de ${formatSoles(monto)} para ${f.nombre}.`);
        await cargarProyeccion(); // cierra el panel ± y limpia el formulario
      },
    });
  }

  // CAMBIO 0355 — «Agregar todo». fn_grati_cts_agregar_pendientes ya decide
  // quién tiene algo pendiente (deja el monto en 0 a quien no); acá solo se
  // suma para mostrar el aviso ANTES de escribir nada.
  function agregarPendientesGratiCts() {
    if (!proy?.periodo_id || !pendientesGratiCts) return;
    const periodoId = proy.periodo_id;
    setConfirmPendiente({
      mensaje:
        `Vas a registrar ${pendientesGratiCts.movimientos} movimiento(s) para ` +
        `${pendientesGratiCts.personas} persona(s), por un total de ${formatSoles(pendientesGratiCts.total)}. ` +
        `¿Confirmas?`,
      accion: async () => {
        setGuardandoBulk(true);
        const { data, error } = await supabase.rpc("fn_grati_cts_agregar_pendientes", {
          p_periodo_id: periodoId,
        });
        setGuardandoBulk(false);
        if (error) {
          avisar("error", mensajeDeError(error, "agregar los pendientes"));
          return;
        }
        const r = data as unknown as {
          agregados: { nombre: string; categoria: string; monto: number }[];
          fallidos: { nombre: string; categoria: string; motivo: string }[];
          total_agregado: number;
        };
        if (r.agregados.length > 0) {
          avisar("ok", `Se agregaron ${r.agregados.length} movimiento(s) por ${formatSoles(r.total_agregado)}.`);
        }
        if (r.fallidos.length > 0) {
          avisar(
            "error",
            `${r.fallidos.length} no se pudieron agregar — ` +
            r.fallidos.map((f) => `${f.nombre} (${CLASE_LABEL[f.categoria as ClaseMov] ?? f.categoria}): ${f.motivo}`).join(" · ")
          );
        }
        if (r.agregados.length === 0 && r.fallidos.length === 0) {
          avisar("ok", "No había nada pendiente por agregar.");
        }
        await cargarProyeccion();
      },
    });
  }

  // «Ya le pagué aparte». No borra a la persona de la planilla: le pone un
  // descuento por lo que ya recibió, con la fecha escrita en el concepto. Su
  // total baja a cero (o a la diferencia) y en la boleta queda dicho por qué.
  //
  // Se prefiere esto a excluirla del periodo porque dentro de un año «esta
  // persona no aparece en julio» no explica nada y parece un fallo; «se le
  // descontó S/850 porque ya se le había pagado el 14/07» sí.
  function marcarYaPagado(f: Fila) {
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
    const liq = liquidadas[f.persona_id] ?? null;
    const porCubrir = liq ? liq.cobro_del_periodo - f.descuentos : f.total;
    const sugerido = Math.max(0, Math.round(porCubrir * 100) / 100);
    setYaPagadoModal({ fila: f, sugerido, liq });
    setYaPagadoMonto(String(sugerido));
    // Un campo de fecha que bloquea el envío no puede arrancar vacío (ver
    // CLAUDE.md) — arranca en hoy, visible y editable en un clic.
    setYaPagadoFecha(hoyLimaISO());
  }

  async function confirmarYaPagado() {
    if (!proy?.periodo_id || !yaPagadoModal) return;
    const f = yaPagadoModal.fila;
    // El monto lo lee `parsearMontoSoles`, no un `replace` a mano: la app
    // imprime «8,500.00» con Intl y quien copia esa cifra tiene que poder
    // pegarla. Ver packages/shared/src/montos.ts para por qué esto no vive acá.
    const leido = parsearMontoSoles(yaPagadoMonto);
    if (!leido.ok) {
      avisar("error", leido.motivo);
      return;
    }
    const monto = leido.monto;
    if (monto <= 0) {
      avisar("error", "El monto tiene que ser mayor a 0.");
      return;
    }
    if (!yaPagadoFecha) {
      avisar("error", "Pon el día en que se le pagó.");
      return;
    }
    const fechaTexto = isoADiaMesAnio(yaPagadoFecha);
    setGuardandoMov(true);
    const { error } = await supabase.rpc("fn_agregar_movimiento", {
      p_periodo_id: proy.periodo_id,
      p_persona_id: f.persona_id,
      p_tipo: "descuento",
      p_concepto: `Ya pagado el ${fechaTexto} — fuera de planilla`,
      p_monto: monto,
      p_categoria: null,
    });
    setGuardandoMov(false);
    if (error) {
      avisar("error", mensajeDeError(error, "registrar"));
      return;
    }
    setYaPagadoModal(null);
    avisar("ok", `Registrado: a ${f.nombre} ya se le habían pagado ${formatSoles(monto)} el ${fechaTexto}.`);
    await cargarProyeccion();
  }

  // «Adelanto de beneficio» (0343). Escribe en desembolsos_beneficios, NO en
  // movimientos_planilla — es la puerta que le faltaba a esa tabla desde la
  // 0155. Existe para el caso de alguien que cesa a mitad de semestre y
  // necesita su gratificación o CTS truncas por adelantado: registrado acá,
  // fn_grati_trunca / fn_cts_trunca / fn_vacaciones_truncas lo restan solas al
  // armar la liquidación, y no hace falta tocar el sueldo del periodo con un
  // bono suelto que la liquidación no sabría reconocer.
  //
  // Antes eran cuatro window.prompt() en cadena (tipo, monto, fecha, nota) —
  // ahora un único Modal con los cuatro campos a la vista a la vez.
  function registrarDesembolso(f: Fila) {
    setDesembolsoForm({ beneficio: "gratificacion", monto: "", fecha: hoyLimaISO(), nota: "" });
    setDesembolsoModal(f);
  }

  async function confirmarDesembolso() {
    const f = desembolsoModal;
    if (!f) return;
    const { beneficio, fecha } = desembolsoForm;
    const leido = parsearMontoSoles(desembolsoForm.monto);
    if (!leido.ok) {
      avisar("error", leido.motivo);
      return;
    }
    if (leido.monto <= 0) {
      avisar("error", "El monto tiene que ser mayor a 0.");
      return;
    }
    if (!fecha) {
      avisar("error", "Pon el día en que se le paga.");
      return;
    }
    const [aaaa, mm] = fecha.split("-");
    const mesNum = Number(mm);
    const anio = Number(aaaa);

    // Gratificación y CTS se parten en dos ventanas por semestre calendario;
    // vacaciones no las tiene (check de desembolsos_beneficios, 0155).
    const ventana =
      beneficio === "vacaciones" ? "vacaciones"
      : beneficio === "gratificacion" ? (mesNum <= 6 ? "grati_s1" : "grati_s2")
      : (mesNum <= 6 ? "cts_may" : "cts_nov");

    setGuardandoMov(true);
    const { error } = await supabase.rpc("fn_registrar_desembolso", {
      p_persona_id: f.persona_id,
      p_ventana: ventana,
      p_anio: anio,
      p_monto: leido.monto,
      p_fecha_pago: fecha,
      p_origen: "transferencia",
      p_nota: desembolsoForm.nota.trim() || null,
    });
    setGuardandoMov(false);
    if (error) {
      avisar("error", mensajeDeError(error, "registrar el adelanto"));
      return;
    }
    setDesembolsoModal(null);
    avisar(
      "ok",
      `Registrado: adelanto de ${formatSoles(leido.monto)} de ${CLASE_LABEL[beneficio]} para ${f.nombre}. ` +
        `La liquidación lo va a restar sola cuando corresponda.`,
    );
  }

  function quitarMovimiento(m: Movimiento) {
    setConfirmPendiente({
      mensaje: `¿Quitar el ${m.tipo} "${m.concepto}" de ${formatSoles(m.monto)}?`,
      variante: "peligro",
      textoBoton: "Quitar",
      accion: () => quitarMovimientoConfirmado(m),
    });
  }

  async function quitarMovimientoConfirmado(m: Movimiento) {
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

  // ── Filtro de sede + nombre ────────────────────────────────────────────────
  const sedes = useMemo(
    () => Array.from(new Set((proy?.filas ?? []).map((f) => f.sede))).sort(),
    [proy],
  );
  // Sin tildes ni mayúsculas, igual que Equipo y el buscador global (⌘K):
  // buscar "nunez" tiene que encontrar a "Núñez".
  const nombreBuscado = useMemo(
    () => nombreFiltro.trim().normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase(),
    [nombreFiltro],
  );
  const filasVisibles = useMemo(
    () => (proy?.filas ?? []).filter(
      (f) =>
        (sedeFiltro === "todas" || f.sede === sedeFiltro) &&
        pasaEstado(f, estadoFiltro) &&
        (!nombreBuscado || f.nombre.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase().includes(nombreBuscado)),
    ),
    [proy, sedeFiltro, estadoFiltro, nombreBuscado],
  );
  const simFilasVisibles = useMemo(
    () => (simProy?.filas ?? []).filter(
      (f) =>
        (sedeFiltro === "todas" || f.sede === sedeFiltro) &&
        pasaEstado(f, estadoFiltro) &&
        (!nombreBuscado || f.nombre.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase().includes(nombreBuscado)),
    ),
    [simProy, sedeFiltro, estadoFiltro, nombreBuscado],
  );
  // Partidas de la misma lista, una por pestaña (tipo_vinculo, 0323). Un dato
  // ausente o desconocido cae en "planilla" — mismo defecto seguro que usa
  // `fn_planilla_congelar` en la base (`coalesce(f->>'tipo_vinculo', 'planilla')`).
  const filasPorGrupo = useMemo(() => {
    const m = new Map<TipoVinculo, Fila[]>(TIPOS_VINCULO.map((g) => [g, [] as Fila[]]));
    for (const f of filasVisibles) {
      const g = TIPOS_VINCULO.includes(f.tipo_vinculo as TipoVinculo) ? (f.tipo_vinculo as TipoVinculo) : "planilla";
      m.get(g)!.push(f);
    }
    return m;
  }, [filasVisibles]);
  const simFilasPorGrupo = useMemo(() => {
    const m = new Map<TipoVinculo, Fila[]>(TIPOS_VINCULO.map((g) => [g, [] as Fila[]]));
    for (const f of simFilasVisibles) {
      const g = TIPOS_VINCULO.includes(f.tipo_vinculo as TipoVinculo) ? (f.tipo_vinculo as TipoVinculo) : "planilla";
      m.get(g)!.push(f);
    }
    return m;
  }, [simFilasVisibles]);
  // Pestañas a mostrar: "planilla" siempre (es la de por defecto, y así nunca
  // se queda la pantalla sin ninguna pestaña visible), las otras 4 solo si
  // tienen a alguien en ESTE periodo — Felipe lo pidió así: "prueba",
  // "practicante" y "no_trabajador" casi nunca tienen a nadie.
  const tabsVisibles = useMemo(
    () => TIPOS_VINCULO.filter((g) => g === "planilla" || (filasPorGrupo.get(g)?.length ?? 0) > 0),
    [filasPorGrupo],
  );
  // Derivado, no sincronizado por efecto: si la pestaña elegida se quedó sin
  // nadie (cambió de periodo, o se movió a alguien de grupo) y por eso ya no
  // está en `tabsVisibles`, esta pantalla se COMPORTA como si estuviera en
  // "planilla" sin necesidad de un setState en un effect — `setTablaTab` solo
  // lo escriben los clics de las pestañas.
  const tablaTabEfectiva = tabsVisibles.includes(tablaTab) ? tablaTab : "planilla";
  const filasTabActiva = filasPorGrupo.get(tablaTabEfectiva) ?? [];
  const simFilasTabActiva = simFilasPorGrupo.get(tablaTabEfectiva) ?? [];
  // El estado de pago de la pestaña activa — sale de fn_periodo_grupos_estado
  // (0323). Ausente (base sin la 0323, o simulación) se lee como "abierto":
  // el defecto seguro es seguir pidiendo confirmación, no dar por pagado algo
  // que la base nunca dijo.
  const grupoActivo = useMemo(
    () => grupos?.find((g) => g.grupo === tablaTabEfectiva) ?? null,
    [grupos, tablaTabEfectiva],
  );
  const grupoActivoPagado = grupoActivo?.estado === "pagado";
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
      <div className="flex flex-1 flex-col">
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
      <div className="flex flex-1 flex-col">
        <main className="flex-1 p-6">
          <p className="max-w-md rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
            Solo administradores y líderes pueden ver la planilla.
          </p>
        </main>
      </div>
    );
  }

  const ocupado = cargando || guardandoObj !== null || guardandoMov || guardandoPeriodo;

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        {/* Cabecera: selector de periodo */}
        <div className="mb-4 flex flex-wrap items-center gap-3">
          <h1 className="font-serif text-2xl">Planilla</h1>
          {periodos && periodos.length > 0 && (
            <>
              <CampoSelect
                value={periodoSel ?? ""}
                onChange={(e) => {
                  setPeriodoSel(e.target.value);
                }}
                aria-label="Periodo de pago"
              >
                {periodos.map((p) => (
                  <option key={p.id} value={p.id}>
                    {etiquetaPeriodo(p)}
                    {p.estado === "pagado" ? " · PAGADO" : periodoVencido?.id === p.id ? " · VENCIDO SIN PAGAR" : ""}
                  </option>
                ))}
              </CampoSelect>
              {periodoActual &&
                (periodoActual.estado === "pagado" ? (
                  <Insignia variante="positivo">PAGADO 🔒</Insignia>
                ) : viendoElVencido ? (
                  <Insignia variante="alerta">VENCIDO SIN PAGAR</Insignia>
                ) : (
                  <Insignia variante="advertencia">abierto</Insignia>
                ))}
              {/* Ningún otro sitio del panel recuerda que este periodo sigue
                  esperando — ver CLAUDE.md. Se pinta solo cuando NO se está
                  mirando ya el vencido, para no duplicar la insignia de arriba. */}
              {periodoVencido && !viendoElVencido && (
                <Boton
                  variante="enlace"
                  className="text-xs text-rojo hover:text-rojo-profundo"
                  onClick={() => setPeriodoSel(periodoVencido.id)}
                >
                  {etiquetaPeriodo(periodoVencido)} terminó y sigue sin pagar →
                </Boton>
              )}
              <Boton
                onClick={() => {
                  setMostrandoNuevo((v) => !v);
                }}
              >
                + Nuevo periodo
              </Boton>
              {esUltimo && periodoActual?.estado === "abierto" && (
                <Boton
                  variante="peligro"
                  onClick={() => void eliminarPeriodo()}
                  disabled={guardandoPeriodo}
                >
                  Eliminar
                </Boton>
              )}
            </>
          )}
        </div>

        {errorPeriodos && (
          <div className="mb-4 max-w-3xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
            No se pudieron cargar los periodos: {errorPeriodos}{" "}
            <Boton
              variante="enlace"
              className="font-medium"
              onClick={() =>
                void (async () => {
                  const lista = await cargarPeriodos();
                  if (lista && lista.length > 0) {
                    const sugerido = periodoInicialSugerido(lista, hoyLimaISO());
                    setPeriodoSel((prev) => prev ?? sugerido?.id ?? lista[0].id);
                  }
                })()
              }
            >
              Reintentar
            </Boton>
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
              <Campo etiqueta="Fecha de inicio" type="date" value={primerIni} onChange={(e) => setPrimerIni(e.target.value)} />
              <Campo etiqueta="Fecha de cierre" type="date" value={primerFin} onChange={(e) => setPrimerFin(e.target.value)} />
              <Boton
                variante="primario"
                onClick={() => void crearPeriodo(primerFin, primerIni)}
                disabled={!primerIni || !primerFin}
                cargando={creandoPeriodo}
              >
                Crear periodo
              </Boton>
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
                  <Campo etiqueta="Inicio (encadenado)" type="date" value={inicioEncadenado} readOnly disabled className="opacity-60" />
                  <Campo
                    etiqueta="Fecha de cierre"
                    type="date"
                    value={nuevoFin}
                    min={sumarDias(inicioEncadenado, 19)}
                    max={sumarDias(inicioEncadenado, 45)}
                    onChange={(e) => setNuevoFin(e.target.value)}
                  />
                  <Boton variante="primario" onClick={() => void crearPeriodo(nuevoFin)} disabled={!nuevoFin} cargando={creandoPeriodo}>
                    Crear periodo
                  </Boton>
                  <Boton onClick={() => setMostrandoNuevo(false)}>Cancelar</Boton>
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
                <Boton variante="enlace" className="font-medium" onClick={() => void cargarProyeccion()}>
                  Reintentar
                </Boton>
              </div>
            )}

            {/* Sin esto, un fallo al comprobar los desvíos se veía IGUAL que
                «no hay desvíos» — el mismo falso negativo silencioso que la
                regla de diseño de hoy prohíbe. */}
            {pagado && errorDesvios && (
              <div className="mb-4 max-w-3xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
                No se pudo comprobar si este periodo pagado sigue cuadrando con los datos de hoy: {errorDesvios}{" "}
                <Boton variante="enlace" className="font-medium" onClick={() => void cargarDesvios()}>
                  Reintentar
                </Boton>
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
                  {guardandoPeriodo ? "Guardando…" : `Recalcular y volver a pagar «${TIPO_VINCULO_LABEL[tablaTabEfectiva]}»`}
                </button>
                <p className="mt-2 text-xs opacity-80">
                  Recalcula solo el grupo de la pestaña donde estás parado — si el desvío es de otro grupo, cambia de
                  pestaña primero. Guarda una copia nueva de su desglose. La anterior se conserva, y queda registrado quién lo hizo y
                  por qué. El periodo no se reabre en ningún momento.
                </p>
              </div>
            )}

            {/* El candado de pago vive por pestaña desde la 0323 — ver más abajo,
                junto a la tabla de cada grupo. periodos_planilla sigue teniendo
                un estado agregado (pagado cuando los 5 grupos con gente lo
                están), pero ya no hay un botón único para todo el periodo. */}

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
                  <Insignia key={f.fecha} variante="advertencia">
                    {fechaCorta(f.fecha)} — {f.nombre}
                  </Insignia>
                ))}
                {proy.feriados.length === 0 && <span>· sin feriados en este periodo</span>}
              </div>
            )}

            {/* CAMBIO 0355 — Gratificación/CTS/Bonificación 9% pendientes de
                este periodo, con un botón que las agrega todas de una vez.
                No escribe nada solo: sigue pidiendo confirmación antes de
                que el monto se vuelva un movimiento real, y después dice a
                quién se le agregó y a quién no (y por qué). */}
            {pendientesGratiCts && (
              <div className="mb-4 flex max-w-3xl flex-wrap items-center justify-between gap-3 rounded-lg bg-ambar/15 px-4 py-3 text-sm text-ambar">
                <span>
                  {[gc?.gratiAplica && "Gratificación", gc?.gratiAplica && "Bonificación 9%", gc?.ctsAplica && "CTS"]
                    .filter(Boolean)
                    .join(" · ")}{" "}
                  pendiente para {pendientesGratiCts.personas}{" "}
                  {pendientesGratiCts.personas === 1 ? "persona" : "personas"} — {formatSoles(pendientesGratiCts.total)} en total.
                </span>
                <button
                  onClick={() => void agregarPendientesGratiCts()}
                  disabled={guardandoBulk}
                  className="whitespace-nowrap rounded-lg bg-ambar px-4 py-1.5 text-sm font-medium text-crema disabled:opacity-50"
                >
                  {guardandoBulk ? "Agregando…" : `Agregar todo (${pendientesGratiCts.movimientos})`}
                </button>
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
                      <Boton variante="enlace" className="font-medium" onClick={() => void cargarFeriadosAnio()}>Reintentar</Boton>
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
                    <Campo
                      etiqueta="Fecha"
                      type="date"
                      value={nuevoFeriado.fecha}
                      onChange={(e) => setNuevoFeriado({ ...nuevoFeriado, fecha: e.target.value })}
                    />
                    <Campo
                      etiqueta="Nombre"
                      value={nuevoFeriado.nombre}
                      onChange={(e) => setNuevoFeriado({ ...nuevoFeriado, nombre: e.target.value })}
                      placeholder="ej. Fiestas Patrias"
                    />
                    <Boton variante="primario" onClick={() => void agregarFeriado()} cargando={guardandoFeriado}>
                      Agregar feriado
                    </Boton>
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
                <Boton variante="enlace" className="font-medium" onClick={() => setEstadoFiltro("todos")}>
                  Verlas
                </Boton>
              </div>
            )}

            {/* Filtros + CSV */}
            <div className="mb-3 flex flex-wrap items-end justify-between gap-3">
              <div className="flex flex-wrap items-end gap-3">
                <div className="relative">
                  <Search size={15} strokeWidth={1.8} aria-hidden className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-taupe" />
                  <Campo
                    value={nombreFiltro}
                    onChange={(e) => setNombreFiltro(e.target.value)}
                    placeholder="Buscar por nombre…"
                    aria-label="Buscar por nombre"
                    className="w-52 pl-8"
                  />
                </div>
                <CampoSelect etiqueta="Sede" value={sedeFiltro} onChange={(e) => setSedeFiltro(e.target.value)}>
                  <option value="todas">Todas</option>
                  {sedes.map((s) => (
                    <option key={s} value={s}>{s}</option>
                  ))}
                </CampoSelect>
                <CampoSelect
                  etiqueta="Mostrar"
                  value={estadoFiltro}
                  onChange={(e) => setEstadoFiltro(e.target.value as EstadoFiltro)}
                >
                  <option value="activos">Solo el equipo actual</option>
                  <option value="inactivos">Solo quienes ya no están</option>
                  <option value="todos">Todos</option>
                </CampoSelect>
              </div>
              <Boton
                variante="primario"
                onClick={descargarCsvPlanilla}
                disabled={cargando || errorCarga !== null || !proy || filasVisibles.length === 0}
              >
                Descargar CSV
              </Boton>
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
                          <Boton variante="enlace" className="font-medium" onClick={() => setVariacionTodas(true)}>
                            Ver a todo el equipo igualmente
                          </Boton>
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
                        {/* Casilla suelta: no hay CampoCasilla todavía en components/ui/campo.tsx
                            (Fase A no la agregó pese a lo anunciado) — mismas clases que ese
                            primitivo va a necesitar (accent-tinta, size-4), para que migrar sea
                            trivial en cuanto exista. */}
                        <input
                          type="checkbox"
                          checked={variacionTodas}
                          onChange={(e) => setVariacionTodas(e.target.checked)}
                          className="size-4 rounded border-sand accent-tinta"
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

            {/* Pestaña por tipo_vinculo (0323). Antes era un binario
                planilla/honorarios; con el pago por grupo cada tipo_vinculo
                —incluidos prueba y practicante, que antes venían mezclados
                dentro de "planilla" y "honorarios" respectivamente— tiene su
                propia pestaña, su propio candado de pago y su propia foto
                congelada. Siguen editables ahí: boleta, movimientos y el
                aviso de retención de 4ta no cambian.
                Solo se muestran las que tienen a alguien este periodo —
                "planilla" siempre, las otras 4 casi nunca tienen gente. */}
            {proy && (
              <div className="mb-3 flex flex-wrap gap-1 border-b border-sand">
                {tabsVisibles.map((g) => (
                  <button
                    key={g}
                    onClick={() => setTablaTab(g)}
                    className={`rounded-t-lg px-4 py-2 text-sm font-medium ${
                      tablaTabEfectiva === g
                        ? "border border-b-0 border-sand bg-papel text-tinta"
                        : "text-taupe hover:text-tinta"
                    }`}
                  >
                    {TIPO_VINCULO_LABEL[g]} ({filasPorGrupo.get(g)?.length ?? 0})
                    {grupos?.find((x) => x.grupo === g)?.estado === "pagado" && " 🔒"}
                  </button>
                ))}
              </div>
            )}

            {/* Candado de pago DE ESTE GRUPO (0323) — cada pestaña paga y se
                reabre por su cuenta. periodoActual.estado sigue siendo el
                agregado de los 5 (ver comentario más arriba), pero el botón
                ya no es periodo-entero. */}
            {proy && periodoActual && (
              <div className="mb-4 flex flex-wrap items-center gap-3">
                {grupoActivoPagado ? (
                  <>
                    <span className="text-sm text-taupe">
                      Pagado{grupoActivo?.pagado_at ? ` el ${fechaLima(grupoActivo.pagado_at)}` : ""}
                      {grupoActivo?.pagado_por_nombre ? ` por ${grupoActivo.pagado_por_nombre}` : ""} — el desglose de
                      «{TIPO_VINCULO_LABEL[tablaTabEfectiva]}» quedó congelado; es la cifra que va a Costos.
                    </span>
                    <Boton onClick={() => void marcarPagado(tablaTabEfectiva, false)} disabled={guardandoPeriodo}>
                      Reabrir «{TIPO_VINCULO_LABEL[tablaTabEfectiva]}»
                    </Boton>
                  </>
                ) : (
                  <Boton
                    variante="primario"
                    onClick={() => void marcarPagado(tablaTabEfectiva, true)}
                    disabled={cargando || filasTabActiva.length === 0}
                    cargando={guardandoPeriodo}
                    title={filasTabActiva.length === 0 ? "No hay nadie de este grupo en el periodo." : undefined}
                  >
                    Marcar «{TIPO_VINCULO_LABEL[tablaTabEfectiva]}» como PAGADO
                  </Boton>
                )}
              </div>
            )}

            {/* Tabla del periodo */}
            {cargando && !proy ? (
              <Cargando />
            ) : proy ? (
              <TablaPlanilla
                filas={filasTabActiva}
                simulacion={false}
                pagado={grupoActivoPagado}
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
                onRegistrarDesembolso={(f) => void registrarDesembolso(f)}
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
                    <Tabla className="max-w-3xl">
                      <TablaEncabezado>
                        <Th>Nombre</Th>
                        <Th className="text-right">Gratificación</Th>
                        <Th className="text-right">CTS</Th>
                        <Th className="text-right">Vacaciones</Th>
                        <Th className="text-right">Total provisión</Th>
                      </TablaEncabezado>
                      <tbody>
                        {filasVisibles.length === 0 && (
                          <tr>
                            <td colSpan={5} className="px-4 py-6 text-center text-taupe">
                              No hay personas para mostrar en este periodo.
                            </td>
                          </tr>
                        )}
                        {filasVisibles.map((f) => (
                          <FilaTabla key={f.persona_id}>
                            <td className="px-4 py-2">{f.nombre}</td>
                            <td className="px-4 py-2 text-right">{formatSoles(f.provision_gratificacion)}</td>
                            <td className="px-4 py-2 text-right">{formatSoles(f.provision_cts)}</td>
                            <td className="px-4 py-2 text-right">{formatSoles(f.provision_vacaciones)}</td>
                            <td className="px-4 py-2 text-right font-medium">{formatSoles(f.provision_total)}</td>
                          </FilaTabla>
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
                    </Tabla>
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
                    <Campo etiqueta="Desde" type="date" value={simIni} onChange={(e) => setSimIni(e.target.value)} />
                    <Campo etiqueta="Hasta" type="date" value={simFin} onChange={(e) => setSimFin(e.target.value)} />
                    <Boton variante="primario" onClick={() => void simular()} disabled={!simIni || !simFin} cargando={simCargando}>
                      Calcular
                    </Boton>
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

        {/* ── Diálogos migrados de window.confirm/alert/prompt a <Modal> ──────
            Ver CLAUDE.md: Felipe aprobó migrar TODOS los diálogos nativos del
            panel. No cambia qué función se llama al confirmar — solo cómo se
            pregunta. */}

        {/* Genérico: los seis confirm() + el único alert() de esta pantalla. */}
        <Modal
          abierto={confirmPendiente !== null}
          onCerrar={() => setConfirmPendiente(null)}
          titulo={confirmPendiente?.accion === null ? "Aviso" : "Confirmar"}
          ancho="sm"
        >
          {confirmPendiente && (
            <>
              <p className="mb-4 whitespace-pre-line text-sm text-taupe">{confirmPendiente.mensaje}</p>
              <div className="flex justify-end gap-2">
                {confirmPendiente.accion === null ? (
                  <Boton variante="primario" onClick={() => setConfirmPendiente(null)}>Entendido</Boton>
                ) : (
                  <>
                    <Boton onClick={() => setConfirmPendiente(null)}>Cancelar</Boton>
                    <Boton
                      variante={confirmPendiente.variante ?? "primario"}
                      onClick={() => {
                        const accion = confirmPendiente.accion;
                        setConfirmPendiente(null);
                        if (accion) void accion();
                      }}
                    >
                      {confirmPendiente.textoBoton ?? "Confirmar"}
                    </Boton>
                  </>
                )}
              </div>
            </>
          )}
        </Modal>

        {/* Reabrir un pago: pedía el motivo por window.prompt(). */}
        <Modal
          abierto={reabrirModal !== null}
          onCerrar={() => setReabrirModal(null)}
          bloqueado={guardandoPeriodo}
          titulo={reabrirModal ? `Reabrir «${TIPO_VINCULO_LABEL[reabrirModal]}»` : undefined}
          ancho="sm"
        >
          {reabrirModal && (
            <>
              <p className="mb-4 text-sm text-taupe">
                Ya está pagado. Reabrir deja rastro: se pide el motivo y queda auditado (quién, cuándo y por qué).
              </p>
              <label className="mb-4 flex flex-col gap-1 text-sm">
                Motivo (obligatorio)
                <AreaTexto
                  value={reabrirMotivo}
                  onChange={(e) => setReabrirMotivo(e.target.value)}
                  rows={2}
                  autoFocus
                  placeholder="ej. corregir una tardanza mal contada"
                />
              </label>
              <div className="flex justify-end gap-2">
                <Boton onClick={() => setReabrirModal(null)} disabled={guardandoPeriodo}>Cancelar</Boton>
                <Boton variante="primario" onClick={() => void confirmarReabrir()} cargando={guardandoPeriodo}>
                  Reabrir
                </Boton>
              </div>
            </>
          )}
        </Modal>

        {/* Volver a pagar: pedía el motivo por window.prompt(). */}
        <Modal
          abierto={repagoModal}
          onCerrar={() => setRepagoModal(false)}
          bloqueado={guardandoPeriodo}
          titulo={`Volver a pagar «${TIPO_VINCULO_LABEL[tablaTabEfectiva]}»`}
          ancho="sm"
        >
          <p className="mb-4 text-sm text-taupe">
            Se guarda una copia nueva del desglose. La copia anterior se conserva y queda registrado quién lo
            hizo y por qué.
          </p>
          <label className="mb-4 flex flex-col gap-1 text-sm">
            ¿Por qué se vuelve a pagar? (obligatorio)
            <AreaTexto
              value={repagoMotivo}
              onChange={(e) => setRepagoMotivo(e.target.value)}
              rows={2}
              autoFocus
              placeholder="ej. se corrigió una marca del 12"
            />
          </label>
          <div className="flex justify-end gap-2">
            <Boton onClick={() => setRepagoModal(false)} disabled={guardandoPeriodo}>Cancelar</Boton>
            <Boton variante="primario" onClick={() => void confirmarRepago()} cargando={guardandoPeriodo}>
              Volver a pagar
            </Boton>
          </div>
        </Modal>

        {/* «Ya le pagué aparte»: antes dos window.prompt() en cadena (monto, fecha). */}
        <Modal
          abierto={yaPagadoModal !== null}
          onCerrar={() => setYaPagadoModal(null)}
          bloqueado={guardandoMov}
          titulo="Ya le pagué aparte"
          ancho="sm"
        >
          {yaPagadoModal && (
            <>
              <p className="mb-4 text-sm text-taupe">
                {yaPagadoModal.fila.nombre} — este periodo le calcula {formatSoles(yaPagadoModal.fila.total)}.
                Se registra como un descuento por lo que ya recibió, así su total queda en cero (o en la
                diferencia) y en su boleta queda escrito por qué.
                {yaPagadoModal.liq && (
                  <>
                    {" "}Su liquidación del {fechaCorta(yaPagadoModal.liq.pagada_el)} ya le pagó{" "}
                    {formatSoles(yaPagadoModal.liq.cobro_del_periodo)} de este mes
                    {yaPagadoModal.fila.descuentos > 0
                      ? `, y aquí ya hay ${formatSoles(yaPagadoModal.fila.descuentos)} descontados`
                      : ""}
                    . Por eso viene propuesto {formatSoles(yaPagadoModal.sugerido)}.
                  </>
                )}
              </p>
              <div className="mb-4 flex flex-wrap gap-3">
                <Campo
                  etiqueta="Monto (S/)"
                  value={yaPagadoMonto}
                  onChange={(e) => setYaPagadoMonto(e.target.value)}
                  autoFocus
                  className="w-32"
                />
                <Campo
                  etiqueta="Fecha de pago"
                  type="date"
                  value={yaPagadoFecha}
                  onChange={(e) => setYaPagadoFecha(e.target.value)}
                />
              </div>
              <p className="mb-4 text-xs text-taupe">Queda escrito en su boleta y en la foto del pago.</p>
              <div className="flex justify-end gap-2">
                <Boton onClick={() => setYaPagadoModal(null)} disabled={guardandoMov}>Cancelar</Boton>
                <Boton variante="primario" onClick={() => void confirmarYaPagado()} cargando={guardandoMov}>
                  Registrar
                </Boton>
              </div>
            </>
          )}
        </Modal>

        {/* Adelanto de beneficio: antes cuatro window.prompt() en cadena. */}
        <Modal
          abierto={desembolsoModal !== null}
          onCerrar={() => setDesembolsoModal(null)}
          bloqueado={guardandoMov}
          titulo="Adelanto de beneficio"
          ancho="sm"
        >
          {desembolsoModal && (
            <>
              <p className="mb-3 text-sm text-taupe">
                Para {desembolsoModal.nombre}, fuera del ciclo normal. La liquidación lo va a restar sola
                cuando corresponda.
              </p>
              <div className="mb-3 flex flex-wrap gap-3">
                <CampoSelect
                  etiqueta="Beneficio"
                  value={desembolsoForm.beneficio}
                  onChange={(e) =>
                    setDesembolsoForm({ ...desembolsoForm, beneficio: e.target.value as typeof desembolsoForm.beneficio })
                  }
                  autoFocus
                >
                  <option value="gratificacion">Gratificación</option>
                  <option value="cts">CTS</option>
                  <option value="vacaciones">Vacaciones</option>
                </CampoSelect>
                <Campo
                  etiqueta="Monto (S/)"
                  value={desembolsoForm.monto}
                  onChange={(e) => setDesembolsoForm({ ...desembolsoForm, monto: e.target.value })}
                  className="w-32"
                />
                <Campo
                  etiqueta="Fecha de pago"
                  type="date"
                  value={desembolsoForm.fecha}
                  onChange={(e) => setDesembolsoForm({ ...desembolsoForm, fecha: e.target.value })}
                />
              </div>
              <label className="mb-2 flex flex-col gap-1 text-sm">
                Nota (opcional)
                <AreaTexto
                  value={desembolsoForm.nota}
                  onChange={(e) => setDesembolsoForm({ ...desembolsoForm, nota: e.target.value })}
                  rows={2}
                  placeholder="ej. el motivo del adelanto"
                />
              </label>
              <p className="mb-4 text-xs text-taupe">De la fecha se deduce a qué semestre o ventana corresponde.</p>
              <div className="flex justify-end gap-2">
                <Boton onClick={() => setDesembolsoModal(null)} disabled={guardandoMov}>Cancelar</Boton>
                <Boton variante="primario" onClick={() => void confirmarDesembolso()} cargando={guardandoMov}>
                  Registrar adelanto
                </Boton>
              </div>
            </>
          )}
        </Modal>
      </main>
    </div>
  );
}

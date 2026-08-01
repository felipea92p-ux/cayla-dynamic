"use client";

import { Fragment, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { AdminNav } from "../nav";
import { Cargando, SinDatos } from "@/components/cargando";
import { useRolActual } from "@/lib/admin/use-rol";
import { RANGO_LABEL, formatSoles } from "@/lib/rangos";
import { descargarCsv, generarCsv } from "@/lib/admin/csv";
import { mensajeDeError } from "@/lib/admin/mensaje-error";

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
    new Intl.DateTimeFormat("en-CA", { timeZone: "America/Lima", year: "numeric" }).format(new Date()),
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
    timeZone: "America/Lima", year: "numeric", month: "2-digit", day: "2-digit",
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
    timeZone: "America/Lima", day: "numeric", month: "short", year: "numeric",
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
interface Feriado {
  fecha: string;
  nombre: string;
}
export interface FeriadoDetalle {
  fecha: string;
  horas_trabajadas: number;
  proporcional_horas: number;
  antes_ingreso: boolean;
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
  provision_cts: number;
  provision_vacaciones: number;
  provision_total: number;
  total: number; // ya incluye + asignación + movilidad − pensión + bonos − descuentos
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
}
// Grati/CTS que toca en el periodo, calculado por fn_grati_cts_periodo.
interface GratiCts {
  gratiAplica: boolean;
  gratiConcepto: string;
  ctsAplica: boolean;
  ctsConcepto: string;
  porPersona: Record<string, { grati: number; cts: number }>;
}

function etiquetaPeriodo(p: PeriodoInfo): string {
  return `${MESES_LARGO[p.mes_etiqueta - 1]} ${p.anio_etiqueta} · ${fechaCorta(p.fecha_ini)} → ${fechaCorta(p.fecha_fin)}`;
}

const COLS = 14; // columnas de la tabla principal (+2 en la 0106: básica legal y rendimiento)

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
  guardandoMov?: boolean;
  gc?: GratiCts | null;
}) {
  const {
    filas, simulacion, pagado, sedeFiltro, periodoId, ocupado = false,
    objEdit = {}, onObjChange, onObjBlur, guardandoObj = null,
    baseEdit = {}, onBaseChange, onBaseBlur, guardandoBase = null,
    rendEdit = {}, onRendChange, onRendBlur, guardandoRend = null,
    movAbierto = null, onToggleMov, movForm, onMovForm, onAgregarMov, onQuitarMov, onYaPagado,
    guardandoMov = false, gc = null,
  } = props;
  // Al elegir grati/CTS en el desplegable, autocompleta concepto y el monto que el
  // sistema calculó para esa persona en este periodo. El resto queda manual.
  const alCambiarTipo = (f: Fila, t: ClaseMov) => {
    if ((t === "gratificacion" || t === "cts") && gc) {
      const gp = gc.porPersona[f.persona_id];
      const monto = t === "gratificacion" ? gp?.grati : gp?.cts;
      const concepto = t === "gratificacion" ? gc.gratiConcepto : gc.ctsConcepto;
      onMovForm?.({ tipo: t, concepto: concepto || CLASE_LABEL[t], monto: monto ? String(monto) : "" });
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
        }),
        { pago_base: 0, feriados: 0, asignacion: 0, plus: 0, bonos: 0, descuentos: 0, total: 0 },
      ),
    [filas],
  );

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
            <th className="px-4 py-2 font-normal">Objetivos</th>
            <th className="px-4 py-2 text-right font-normal" title="Remuneración básica legal mensual: la que se declara en PLAME. Vacía = la boleta no imprime esa línea.">
              Básica legal
            </th>
            <th className="px-4 py-2 text-right font-normal" title="Rendimiento del mes, 0 a 100. Vacío = 100% (paga el rango completo, igual que siempre).">
              Rendim.
            </th>
            <th className="px-4 py-2 text-right font-normal">Plus</th>
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
                    {(() => {
                      const r = razonDelCero(f);
                      if (!r) return null;
                      return (
                        <p className={`mt-0.5 text-xs ${r.grave ? "text-ambar" : "text-taupe"}`}>
                          {r.grave ? "⚠ " : ""}{r.texto}
                        </p>
                      );
                    })()}
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
                        {(f.rango && (RANGO_LABEL[f.rango] ?? f.rango)) ?? "—"} · {formatSoles(f.salario_ref)}
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
                  <td className="px-4 py-2">
                    {editable ? (
                      <div className="flex items-center gap-1 whitespace-nowrap">
                        <input
                          type="number"
                          min={0}
                          max={totalObj}
                          step={1}
                          placeholder="—"
                          value={objEdit[f.persona_id] ?? (f.objetivos_cumplidos ?? "")}
                          onChange={(e) => onObjChange?.(f.persona_id, e.target.value)}
                          onBlur={() => onObjBlur?.(f)}
                          disabled={ocupado || pagado}
                          title={pagado ? hintPagado : undefined}
                          className="w-14 rounded-lg border px-2 py-1 text-right disabled:opacity-50"
                        />
                        <span className="text-taupe">/ {totalObj}</span>
                        {guardandoObj === f.persona_id && <span className="text-xs text-taupe">…</span>}
                      </div>
                    ) : (
                      <span className="whitespace-nowrap">
                        {f.objetivos_cumplidos ?? "—"} / {totalObj}
                      </span>
                    )}
                    {f.bajo_desempeno && (
                      <span
                        className="mt-1 inline-block whitespace-nowrap rounded-full bg-rojo/10 px-2 py-0.5 text-xs text-rojo"
                        title="Menos del 30% de objetivos — amerita conversación (principios CAYLA)"
                      >
                        ⚠ bajo desempeño
                      </span>
                    )}
                  </td>
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
                  {/* Rendimiento — vacío significa 100%, y 100% paga el rango
                      completo. El sistema nunca recorta por omisión. */}
                  <td className="px-4 py-2 text-right">
                    {editable ? (
                      <div className="flex items-center justify-end gap-1 whitespace-nowrap">
                        <input
                          type="number"
                          min={0}
                          max={100}
                          step={5}
                          placeholder="100"
                          value={rendEdit[f.persona_id] ?? (f.rendimiento_por_defecto ? "" : (f.rendimiento_pct ?? ""))}
                          onChange={(e) => onRendChange?.(f.persona_id, e.target.value)}
                          onBlur={() => onRendBlur?.(f)}
                          disabled={ocupado || pagado}
                          title={pagado ? hintPagado : undefined}
                          className="w-16 rounded-lg border px-2 py-1 text-right disabled:opacity-50"
                        />
                        <span className="text-taupe">%</span>
                        {guardandoRend === f.persona_id && <span className="text-xs text-taupe">…</span>}
                      </div>
                    ) : (
                      <span className="whitespace-nowrap">
                        {f.rendimiento_pct ?? 100}%
                        {f.rendimiento_por_defecto && <span className="text-taupe/50"> def.</span>}
                      </span>
                    )}
                  </td>
                  <td className="px-4 py-2 text-right">
                    {f.monto_plus > 0 ? formatSoles(f.monto_plus) : <span className="text-taupe/50">—</span>}
                  </td>
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
              <td className="px-4 py-2" />
              <td className="px-4 py-2" />
              <td className="px-4 py-2" />
              <td className="px-4 py-2 text-right font-medium">{formatSoles(totales.plus)}</td>
              <td className="px-4 py-2 text-right font-medium">
                {totales.bonos > 0 ? <span className="text-verde">+{formatSoles(totales.bonos)}</span> : <span className="text-taupe/50">—</span>}
              </td>
              <td className="px-4 py-2 text-right font-medium">
                {totales.descuentos > 0 ? <span className="text-rojo">−{formatSoles(totales.descuentos)}</span> : <span className="text-taupe/50">—</span>}
              </td>
              <td className="px-4 py-2 text-right font-bold">{formatSoles(totales.total)}</td>
            </tr>
          </tfoot>
        )}
      </table>
    </div>
  );
}

export default function PlanillaPage() {
  const router = useRouter();
  const rol = useRolActual();
  const puedeVer = rol === "admin" || rol === "lider_do";
  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  // Periodos
  const [periodos, setPeriodos] = useState<PeriodoInfo[] | null>(null);
  const [errorPeriodos, setErrorPeriodos] = useState<string | null>(null);
  const [periodoSel, setPeriodoSel] = useState<string | null>(null);
  const [guardandoPeriodo, setGuardandoPeriodo] = useState(false);
  // Desvíos de un periodo YA pagado: qué personas cambiaron de cifra desde el pago.
  const [desvios, setDesvios] = useState<Desvio[] | null>(null);
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
  const [cargando, setCargando] = useState(false);
  const [errorCarga, setErrorCarga] = useState<string | null>(null);
  const [mensaje, setMensaje] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  const reqId = useRef(0); // "última carga gana": descarta respuestas fuera de orden

  const [sedeFiltro, setSedeFiltro] = useState("todas");
  // Activos / ya no están / todos. Arranca en "activos" porque es lo que se mira
  // el 99 % de las veces; el aviso de abajo cubre el 1 % peligroso.
  const [estadoFiltro, setEstadoFiltro] = useState<"activos" | "inactivos" | "todos">("activos");

  // Objetivos: valor en edición por persona (solo las filas tocadas)
  const [objEdit, setObjEdit] = useState<Record<string, string>>({});
  const [baseEdit, setBaseEdit] = useState<Record<string, string>>({});
  const [guardandoBase, setGuardandoBase] = useState<string | null>(null);
  const [rendEdit, setRendEdit] = useState<Record<string, string>>({});
  const [guardandoRend, setGuardandoRend] = useState<string | null>(null);
  const [guardandoObj, setGuardandoObj] = useState<string | null>(null);

  // Bonos / descuentos: panel abierto + mini-form
  const [movAbierto, setMovAbierto] = useState<string | null>(null);
  const [movForm, setMovForm] = useState<MovForm>({ tipo: "bono", concepto: "", monto: "" });
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

  function avisar(tipo: "ok" | "error", texto: string) {
    setMensaje({ tipo, texto });
  }

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
    setMovForm({ tipo: "bono", concepto: "", monto: "" });
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
  }, [supabase, puedeVer]);

  useEffect(() => {
    periodoSelRef.current = periodoSel;
    if (periodoSel) {
      void cargarProyeccion(); // cierra el panel ± y limpia su form al arrancar
    } else {
      reqId.current++; // invalida cualquier carga en vuelo del periodo anterior
      setCargando(false);
      setMovAbierto(null);
      setMovForm({ tipo: "bono", concepto: "", monto: "" });
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
    setMovForm({ tipo: "bono", concepto: "", monto: "" });
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
    const sugerido = Math.max(0, Math.round(f.total * 100) / 100);
    const montoTxt = window.prompt(
      `${f.nombre} — ¿cuánto le pagaste ya, fuera de la planilla?\n\n` +
        `Este periodo le calcula ${formatSoles(f.total)}. Se registrará como un descuento por lo ` +
        `que ya recibió, así su total queda en cero (o en la diferencia) y en su boleta queda ` +
        `escrito por qué.`,
      String(sugerido),
    );
    if (montoTxt === null) return;
    const monto = Number(montoTxt.replace(",", "."));
    if (!Number.isFinite(monto) || monto <= 0) {
      avisar("error", "El monto tiene que ser un número mayor a 0.");
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
                  setMensaje(null);
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
                  setMensaje(null);
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

        {mensaje && (
          <div className={`mb-4 max-w-3xl rounded-lg px-4 py-3 text-sm ${mensaje.tipo === "ok" ? "bg-sand/40 text-tinta" : "bg-rojo/10 text-rojo"}`}>
            {mensaje.texto}
          </div>
        )}

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
                    <button
                      onClick={() => void calcularBonoPuntualidad()}
                      disabled={guardandoBono || cargando}
                      className="rounded-lg border px-3 py-1.5 text-sm hover:bg-sand/50 disabled:opacity-50"
                    >
                      {guardandoBono ? "Calculando…" : "🎯 Calcular bono de puntualidad"}
                    </button>
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

            {/* Tabla del periodo */}
            {cargando && !proy ? (
              <Cargando />
            ) : proy ? (
              <TablaPlanilla
                filas={filasVisibles}
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
                onMovForm={setMovForm}
                onAgregarMov={(f) => void agregarMovimiento(f)}
                onQuitarMov={(m) => void quitarMovimiento(m)}
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
                        filas={simFilasVisibles}
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

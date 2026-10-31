/**
 * «PARÁMETROS» EN LO QUE UNA PANTALLA NECESITA SABER (0552).
 *
 * QUÉ PROMETE. Los tipos de lo que devuelven `fn_parametros_listar` y
 * `fn_parametros_historial`, la lectura segura de sus números, el reparto de la
 * lista en lo que se puede cambiar y lo que fija una norma, y —lo que Felipe
 * pidió— la VISTA PREVIA: a quién le cambia algo antes de confirmar. Todo en
 * funciones puras que se prueban sin levantar nada.
 *
 * QUÉ NO HACE. No valida lo que decide la base (mínimos, máximos, quién puede):
 * eso lo repiten `validarValorParametro` y `puedeCambiarParametro` para no hacer
 * un viaje en balde, pero la que manda es `fn_parametro_cambiar`.
 *
 * POR QUÉ LA VISTA PREVIA NO ES UNA CONSULTA NUEVA. Para los dos parámetros que
 * tienen personas detrás —días de prueba y el aviso de descanso médico— la base
 * ya entrega cada situación contada (`fn_pruebas_abiertas`,
 * `fn_ausencias_subsidio`). Recalcular «qué pasaría con el valor nuevo» es una
 * comparación sobre esas filas, y la regla de qué es «cumplida» o «vencida» sigue
 * viviendo en un solo sitio (`situacionDePrueba`, packages/shared): una segunda
 * copia de esa regla en este archivo sería exactamente lo que el CLAUDE.md
 * prohíbe. Los parámetros sin personas detrás (el auto-cierre) dicen en palabras
 * qué cambia y qué no.
 */

import { etiquetaDePrueba, situacionDePrueba, type ClaseParametro } from "@cayla-dynamic/shared";
import type { FilaPrueba } from "@/lib/admin/pruebas";

/** Una fila de `fn_parametros_listar` (0552), con los numéricos ya como número. */
export interface ParametroFila {
  parametro: string;
  nombre: string;
  descripcion: string;
  unidad: string;
  clase: ClaseParametro;
  tipo_valor: "entero" | "decimal";
  valor_min: number | null;
  valor_max: number | null;
  valor_defecto: number;
  editable: boolean;
  base: string | null;
  valor_actual: number;
  /** true = no hay fila en la base y rige el valor de partida. */
  es_defecto: boolean;
  ultimo_cambio_at: string | null;
  ultimo_cambio_por: string | null;
  ultimo_motivo: string | null;
  ultimo_origen: "pantalla" | "base" | null;
  /** Los roles que pueden cambiarlo (0571). Vacío si la base todavía no tiene la 0571. */
  roles_cambia: string[];
  /** Rige por fechas (clase plata, 0574): se cambia con una fecha de vigencia. */
  rige_por_fechas: boolean;
  /** Desde cuándo rige el valor de hoy; null = rige el valor de partida. */
  vigente_desde: string | null;
  /** El próximo cambio ya programado, si hay uno. */
  proximo_valor: number | null;
  proximo_desde: string | null;
}

/** Una fila de `fn_parametros_historial` (0552). */
export interface CambioParametro {
  id: string;
  parametro: string;
  nombre: string;
  unidad: string;
  editable: boolean;
  valor_anterior: number;
  valor_nuevo: number;
  motivo: string;
  /** `base` = alguien lo cambió a mano en la base, sin pasar por la pantalla. */
  origen: "pantalla" | "base";
  cambiado_por: string | null;
  cambiado_at: string;
}

/** `numeric` llega como número o como texto según el camino; aquí siempre número. */
function num(x: unknown): number {
  return typeof x === "number" ? x : Number(x);
}
function numONulo(x: unknown): number | null {
  return x === null || x === undefined ? null : num(x);
}

export function normalizarParametros(filas: ReadonlyArray<Record<string, unknown>>): ParametroFila[] {
  return filas.map((f) => ({
    parametro: String(f.parametro),
    nombre: String(f.nombre),
    descripcion: String(f.descripcion),
    unidad: String(f.unidad),
    clase: f.clase as ClaseParametro,
    tipo_valor: f.tipo_valor === "decimal" ? "decimal" : "entero",
    valor_min: numONulo(f.valor_min),
    valor_max: numONulo(f.valor_max),
    valor_defecto: num(f.valor_defecto),
    editable: f.editable === true,
    base: (f.base as string | null) ?? null,
    valor_actual: num(f.valor_actual),
    es_defecto: f.es_defecto === true,
    ultimo_cambio_at: (f.ultimo_cambio_at as string | null) ?? null,
    ultimo_cambio_por: (f.ultimo_cambio_por as string | null) ?? null,
    ultimo_motivo: (f.ultimo_motivo as string | null) ?? null,
    ultimo_origen: f.ultimo_origen === "pantalla" || f.ultimo_origen === "base" ? f.ultimo_origen : null,
    roles_cambia: Array.isArray(f.roles_cambia) ? f.roles_cambia.map(String) : [],
    rige_por_fechas: f.rige_por_fechas === true,
    vigente_desde: (f.vigente_desde as string | null) ?? null,
    proximo_valor: numONulo(f.proximo_valor),
    proximo_desde: (f.proximo_desde as string | null) ?? null,
  }));
}

export function normalizarCambios(filas: ReadonlyArray<Record<string, unknown>>): CambioParametro[] {
  return filas.map((f) => ({
    id: String(f.id),
    parametro: String(f.parametro),
    nombre: String(f.nombre),
    unidad: String(f.unidad),
    editable: f.editable === true,
    valor_anterior: num(f.valor_anterior),
    valor_nuevo: num(f.valor_nuevo),
    motivo: String(f.motivo),
    origen: f.origen === "base" ? "base" : "pantalla",
    cambiado_por: (f.cambiado_por as string | null) ?? null,
    cambiado_at: String(f.cambiado_at),
  }));
}

/** Lo que se puede cambiar, primero; lo que fija una norma, aparte y solo para leer. */
export function repartirParametros(filas: readonly ParametroFila[]): { editables: ParametroFila[]; fijos: ParametroFila[] } {
  return {
    editables: filas.filter((f) => f.editable),
    fijos: filas.filter((f) => !f.editable),
  };
}

// ── La vista previa ─────────────────────────────────────────────────────────

export interface FilaImpacto {
  persona: string;
  antes: string;
  despues: string;
}

export interface Impacto {
  /** Las personas a las que este valor les cambia algo. Vacío = a nadie. */
  filas: FilaImpacto[];
  /** Cuántas personas miró la comparación y no cambian. */
  sinCambio: number;
  /** Lo que la lista no alcanza a decir (qué rige, desde cuándo, qué no toca). */
  nota: string | null;
}

/** Qué parámetros tienen personas detrás y de dónde se leen. El resto dice su efecto en palabras. */
export type FuenteDeImpacto = "pruebas" | "descanso_medico" | "ninguna";

export function fuenteDeImpacto(parametro: string): FuenteDeImpacto {
  if (parametro === "prueba_dias") return "pruebas";
  if (parametro === "descanso_medico_avisar_desde") return "descanso_medico";
  return "ninguna";
}

/**
 * Con `nuevoPlazo` días de prueba, ¿a quién le cambia la situación? Una persona
 * «cumplida» (ya puede pasar a contrato) que pasa a «en curso», o una «vencida»
 * que deja de estarlo. Quien sigue en la misma situación solo ve cambiar el «de X».
 */
export function impactoDiasDePrueba(filas: readonly FilaPrueba[], nuevoPlazo: number): Impacto {
  const cambian: FilaImpacto[] = [];
  let sinCambio = 0;
  for (const f of filas) {
    const antes = situacionDePrueba(f);
    // Sin `situacion`: la regla la deriva de los días y del plazo nuevo.
    const despuesFila = { dias_trabajados: f.dias_trabajados, dias_plazo: nuevoPlazo };
    const despues = situacionDePrueba(despuesFila);
    if (antes === despues) {
      sinCambio += 1;
      continue;
    }
    cambian.push({
      persona: `${f.nombres} ${f.apellidos}`.trim(),
      antes: etiquetaDePrueba(f).texto,
      despues: etiquetaDePrueba(despuesFila).texto,
    });
  }
  return {
    filas: cambian,
    sinCambio,
    nota: filas.length === 0 ? "Hoy no hay nadie en preselección: el cambio no mueve a nadie." : null,
  };
}

/** Una fila de `fn_ausencias_subsidio` (0197), lo que esta vista previa lee. */
export interface FilaSubsidio {
  persona_id: string;
  nombre: string;
  dias_calendario: number;
}

/**
 * Con el aviso desde `nuevoDesde` días de descanso médico, ¿a quién se empieza o
 * se deja de avisar? Solo aviso a DO: ningún pago cambia con este número.
 */
export function impactoAvisoDescansoMedico(
  filas: readonly FilaSubsidio[],
  desdeActual: number,
  nuevoDesde: number,
): Impacto {
  const cambian: FilaImpacto[] = [];
  let sinCambio = 0;
  for (const f of filas) {
    const antes = f.dias_calendario >= desdeActual;
    const despues = f.dias_calendario >= nuevoDesde;
    if (antes === despues) {
      sinCambio += 1;
      continue;
    }
    cambian.push({
      persona: f.nombre,
      antes: antes ? `Se avisa (lleva ${f.dias_calendario})` : `No se avisa (lleva ${f.dias_calendario})`,
      despues: despues ? "Se avisaría" : "Dejaría de avisarse",
    });
  }
  return {
    filas: cambian,
    sinCambio,
    nota: "Solo cambia el aviso a DO. El tope de días que paga CAYLA lo fija el RIT y no se mueve desde acá.",
  };
}

/** Lo que se dice de un parámetro sin personas detrás: qué cambia y, sobre todo, qué NO. */
export function notaDeEfecto(parametro: string): string | null {
  if (parametro === "auto_cierre_horas") {
    return "Rige desde el próximo auto-cierre. No reabre ni cambia ninguna jornada ya cerrada.";
  }
  return null;
}

// ============================================================================
// Los parámetros que rigen POR FECHAS (clase plata, 0574)
// ============================================================================

/** Un día más a una fecha ISO (aaaa-mm-dd), sin pasar por la hora local. */
function diaSiguiente(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  const t = new Date(Date.UTC(y, m - 1, d + 1));
  return t.toISOString().slice(0, 10);
}

/**
 * La fecha con la que NACE el campo «Rige desde»: hoy, salvo que la última
 * versión ya empiece hoy o después; entonces, el día siguiente a esa. La base
 * exige una fecha posterior a la última versión, y un campo de fecha que bloquea
 * el envío no arranca vacío (CLAUDE.md): nace con la fecha más probable.
 */
export function fechaInicialDeVigencia(hoy: string, ultimaDesde: string | null): string {
  if (!ultimaDesde || ultimaDesde < hoy) return hoy;
  return diaSiguiente(ultimaDesde);
}

/**
 * La fecha más temprana que acepta la base: el día siguiente a la última
 * versión. null = no hay ninguna versión todavía (la base solo exige que la
 * fecha no caiga en un periodo ya pagado, y eso lo dice la vista previa).
 */
export function fechaMinimaDeVigencia(ultimaDesde: string | null): string | null {
  return ultimaDesde ? diaSiguiente(ultimaDesde) : null;
}

/**
 * El valor que regiría el día del cambio, sin el nuevo: si ya hay un cambio
 * programado, ese (la fecha nueva siempre va después de él); si no, el de hoy.
 * Contra esto se compara «ese ya es el valor».
 */
export function valorAntesDelCambio(fila: Pick<ParametroFila, "valor_actual" | "proximo_valor">): number {
  return fila.proximo_valor ?? fila.valor_actual;
}

/** Una fila de `fn_parametro_vista_previa` (0574). */
export interface FilaVistaPrevia {
  persona: string;
  vinculo: string;
  detalle: string;
}

/**
 * La vista previa de un parámetro con fechas, en la forma de la lista de
 * impacto que ya usa el panel. Dice A QUIÉN le toca; el monto de cada pago lo
 * calcula la planilla del periodo, no esta pantalla.
 */
export function impactoDeVistaPrevia(
  filas: ReadonlyArray<FilaVistaPrevia>,
  antes: string,
  despues: string,
): Impacto {
  return {
    filas: filas.map((f) => ({ persona: `${f.persona} (${f.vinculo})`, antes, despues })),
    sinCambio: 0,
    nota: "Muestra a quién le toca este valor. Cuánto cambia el pago de cada persona lo calcula la planilla de cada periodo, desde la fecha elegida; lo ya pagado no se toca.",
  };
}

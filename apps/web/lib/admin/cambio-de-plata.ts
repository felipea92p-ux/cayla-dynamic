/**
 * LO QUE TODA PANTALLA QUE CAMBIA PLATA TIENE QUE DECIR ANTES DE CONFIRMAR (0578).
 *
 * Felipe (2026-10-31): todo cambio de sueldo, base, tope u horas avisa qué módulos
 * mueve, que maneja plata, que queda en el historial, que el sistema tarda un poco
 * en recalcular, y desde qué ciclo rige: inicio del ciclo actual, del siguiente, o
 * desde hoy. Y siempre con doble confirmación.
 *
 * Funciones puras: se prueban con vitest sin levantar nada.
 */

export interface PeriodoCiclo {
  fecha_ini: string;
  fecha_fin: string;
}

export type ClaveVigencia = "inicio_actual" | "inicio_siguiente" | "hoy";

export interface OpcionVigencia {
  clave: ClaveVigencia;
  /** aaaa-mm-dd */
  fecha: string;
  etiqueta: string;
  detalle: string;
}

function diaSiguiente(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + 1)).toISOString().slice(0, 10);
}

/** 31/10/2026 */
export function fechaCorta(iso: string): string {
  const [y, m, d] = iso.split("-");
  return `${d}/${m}/${y}`;
}

/**
 * Las tres fechas desde las que puede regir un cambio. El ciclo actual es el periodo
 * que contiene a `hoy`; el siguiente empieza el día después de que termina. Si hoy no
 * cae en ningún periodo cargado, solo queda «desde hoy».
 */
export function opcionesDeVigencia(hoy: string, periodos: ReadonlyArray<PeriodoCiclo>): OpcionVigencia[] {
  const actual = periodos.find((p) => p.fecha_ini <= hoy && hoy <= p.fecha_fin) ?? null;
  const opciones: OpcionVigencia[] = [];
  if (actual) {
    const siguiente = diaSiguiente(actual.fecha_fin);
    opciones.push({
      clave: "inicio_actual",
      fecha: actual.fecha_ini,
      etiqueta: `Desde el inicio del ciclo actual (${fechaCorta(actual.fecha_ini)})`,
      detalle: `Cuenta todo el ciclo ${fechaCorta(actual.fecha_ini)} → ${fechaCorta(actual.fecha_fin)}, también los días que ya pasaron.`,
    });
    opciones.push({
      clave: "inicio_siguiente",
      fecha: siguiente,
      etiqueta: `Desde el inicio del ciclo siguiente (${fechaCorta(siguiente)})`,
      detalle: "El ciclo en curso no se toca; el cambio empieza con el próximo.",
    });
  }
  opciones.push({
    clave: "hoy",
    fecha: hoy,
    etiqueta: `Desde hoy (${fechaCorta(hoy)})`,
    detalle: actual
      ? `Los días del ciclo actual antes de hoy se pagan como estaban; desde hoy, con el valor nuevo.`
      : "Desde hoy.",
  });
  return opciones;
}

/** Los renglones del aviso que se lee ANTES de confirmar un cambio de plata. */
export function avisoDeCambioDePlata(opcion: OpcionVigencia | null): string[] {
  return [
    "Este cambio maneja plata: cambia cuánto se le paga a personas reales. Revísalo con cuidado.",
    "Mueve la Planilla del ciclo, las boletas, las provisiones y lo que cada persona ve en «Lo mío».",
    opcion
      ? `Rige ${opcion.etiqueta.charAt(0).toLowerCase()}${opcion.etiqueta.slice(1)}. ${opcion.detalle}`
      : "Elige desde cuándo rige.",
    "Queda escrito en el historial con tu nombre, la hora y el motivo. Si te equivocas, lo ves ahí y se corrige con otro cambio.",
    "Después de confirmar, los módulos tardan un momento en recalcular con el valor nuevo.",
    "Se deja un comunicado en BORRADOR solo para las personas afectadas; lo revisas y lo publicas desde Anuncios.",
  ];
}

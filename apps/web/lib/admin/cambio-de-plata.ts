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

import { sumarDias } from "@cayla-dynamic/shared";

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
    const siguiente = sumarDias(actual.fecha_fin, 1);
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

/**
 * Las fechas desde las que puede regir un PARÁMETRO con fechas de /admin/parametros
 * (la base y el tope del practicante): solo el inicio de un ciclo, nunca «desde hoy».
 *
 * La planilla lee esos valores con el que regía EL PRIMER DÍA del periodo
 * (`fn_parametro_valor_en(parámetro, p_ini)`, 0577). Hasta el 2026-11-16 esta pantalla
 * ofrecía «desde hoy» y una fecha libre, y prometía «desde hoy, con el valor nuevo»:
 * un cambio a mitad de ciclo no tocaba ese ciclo y empezaba recién en el siguiente.
 * Medido ese día: tope cambiado a 60 h «desde» el día 12 de un ciclo, y el ciclo se
 * pagó entero con el tope viejo.
 *
 * `ultimaDesde` es la fecha de la última versión del parámetro: la base solo acepta
 * una fecha posterior (0574), así que un inicio de ciclo igual o anterior se descarta.
 *
 * El sueldo por grupo NO usa esto: el sueldo se paga día por día con el de su tramo,
 * y ahí «desde hoy» sí es verdad (PanelSueldoGrupo sigue con `opcionesDeVigencia`).
 */
export function opcionesPorCiclo(
  hoy: string,
  periodos: ReadonlyArray<PeriodoCiclo>,
  ultimaDesde: string | null,
): OpcionVigencia[] {
  return opcionesDeVigencia(hoy, periodos).filter(
    (o) => o.clave !== "hoy" && (ultimaDesde === null || o.fecha > ultimaDesde),
  );
}

/**
 * Por qué falta alguna de las dos fechas de `opcionesPorCiclo`, o null si están las dos.
 * Es lo que se lee debajo de las opciones: sin esto, una opción que desaparece parece un error.
 */
export function avisoDeCiclos(
  hoy: string,
  periodos: ReadonlyArray<PeriodoCiclo>,
  ultimaDesde: string | null,
): string | null {
  const actual = periodos.find((p) => p.fecha_ini <= hoy && hoy <= p.fecha_fin) ?? null;
  if (!actual) {
    return "Hoy no cae en ningún ciclo de pago cargado. Crea el periodo en Planilla antes de cambiar este valor: el cambio tiene que empezar al inicio de un ciclo.";
  }
  if (ultimaDesde === null || ultimaDesde < actual.fecha_ini) return null;
  if (ultimaDesde < sumarDias(actual.fecha_fin, 1)) {
    return `Este ciclo ya tiene un cambio desde el ${fechaCorta(ultimaDesde)}: uno nuevo puede empezar en el ciclo siguiente.`;
  }
  return `Ya hay un cambio programado desde el ${fechaCorta(ultimaDesde)}: uno nuevo puede empezar recién en el ciclo que sigue a ese.`;
}

/**
 * Los renglones del aviso que se lee ANTES de confirmar un cambio de plata.
 * `porCiclo`: el valor lo lee la planilla al inicio del ciclo (los parámetros), así que
 * se dice también que ese ciclo ya no se corrige desde la pantalla.
 */
export function avisoDeCambioDePlata(opcion: OpcionVigencia | null, { porCiclo = false }: { porCiclo?: boolean } = {}): string[] {
  return [
    "Este cambio maneja plata: cambia cuánto se le paga a personas reales. Revísalo con cuidado.",
    "Mueve la Planilla del ciclo, las boletas, las provisiones y lo que cada persona ve en «Lo mío».",
    opcion
      ? `Rige ${opcion.etiqueta.charAt(0).toLowerCase()}${opcion.etiqueta.slice(1)}. ${opcion.detalle}`
      : "Elige desde cuándo rige.",
    ...(porCiclo && opcion
      ? [
          `La planilla toma el valor que rige el primer día de cada ciclo. Una vez confirmado, el ciclo que empieza el ${fechaCorta(opcion.fecha)} queda con este valor: si te equivocas, la corrección empieza recién en el ciclo que sigue.`,
        ]
      : []),
    "Queda escrito en el historial con tu nombre, la hora y el motivo. Si te equivocas, lo ves ahí y se corrige con otro cambio.",
    "Después de confirmar, los módulos tardan un momento en recalcular con el valor nuevo.",
    "Se deja un comunicado en BORRADOR solo para las personas afectadas; lo revisas y lo publicas desde Anuncios.",
  ];
}

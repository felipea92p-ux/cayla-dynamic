// El refrigerio de un horario: qué valores se ofrecen y cuándo conviene
// sugerir que no haya ninguno. Vive aparte de la pantalla de Horarios para
// poder probarlo sin dibujarla (tests/refrigerio.test.ts).
//
// Por qué existe el 0 («sin refrigerio»): hay integrantes que entran solo en
// la tarde (p. ej. 14:15–21:45) y ya llegan almorzadas. Con el refrigerio en
// 60, el sistema les descontaba una hora que nunca tomaron: su horario salía
// de 6.5 h en vez de 7.5 h, y como nadie marca una salida a refrigerio que no
// existe, cada día completo se veía como una hora de más —
// fn_calcular_metricas_jornada compara las horas reales contra las
// programadas— y se les detectaba «tiempo adicional» que no era tal.
//
// La base ya aceptaba el 0 desde la 0016 («0 = sin refrigerio») y
// fn_recalcular_jornada lo lee con coalesce(…, 0): lo único que lo impedía
// era la lista de la pantalla.

// Los refrigerios reales de CAYLA (60 o 75 minutos), y ninguno. La lista es
// cerrada A PROPÓSITO: la auditoría del 2026-09-14 encontró que un campo libre
// dejaba pasar un «6» en vez de «60», y eso se cuela directo al cálculo de
// jornada. Un valor nuevo se agrega acá, no se teclea en la pantalla.
export const REFRIGERIOS_MIN = [0, 60, 75];

// Entrando desde esta hora, el almuerzo ya pasó (o está pasando). Es solo el
// umbral de una SUGERENCIA: nada se cambia solo ni se bloquea nada por esto,
// porque quitar el refrigerio cambia cómo se miden las horas de alguien y esa
// decisión es de quien edita el horario.
export const HORA_DESDE_LA_QUE_YA_ALMORZO = "13:00";

// Datos viejos pueden traer un refrigerio fuera de la lista (el legacy por
// defecto era 45). En vez de esconderlo —un select no puede mostrar
// «seleccionado» un valor que no está en sus opciones sin que el estado real
// quede desincronizado de lo que se ve— se agrega como opción visible, para no
// pisarlo sin que quien edita lo note.
export function opcionesRefrigerio(actual: number): number[] {
  return REFRIGERIOS_MIN.includes(actual) ? REFRIGERIOS_MIN : [...REFRIGERIOS_MIN, actual].sort((a, b) => a - b);
}

/**
 * «Ninguno» / «60 min», o solo el número en las columnas angostas. Es
 * «Ninguno» y no «Sin refrigerio» porque el select vive justo debajo de la
 * etiqueta «Refrigerio» y en una columna de ~140 px el texto largo se corta.
 */
export function etiquetaRefrigerio(min: number, corta = false): string {
  if (corta) return String(min);
  return min === 0 ? "Ninguno" : `${min} min`;
}

type DiaHorario = { e: string; s: string; r: number };

/**
 * ¿Este día entra pasada la hora de almuerzo y aún tiene refrigerio puesto?
 * Solo turnos del mismo día: una salida igual o anterior a la entrada cruza la
 * medianoche (un turno nocturno), y ahí «ya almorzó» no se puede suponer.
 * Las horas son «HH:MM» (lo que da el input de hora), que comparan bien como
 * texto.
 */
export function yaLlegaAlmorzada(dia: DiaHorario): boolean {
  if (!dia.e || !dia.s) return false;
  return dia.r > 0 && dia.e >= HORA_DESDE_LA_QUE_YA_ALMORZO && dia.s > dia.e;
}

/** Los días de la semana (0=domingo … 6=sábado) donde conviene sugerir quitar el refrigerio. */
export function diasQueYaLlegaAlmorzada(porDia: Record<number, DiaHorario>): number[] {
  return Object.entries(porDia)
    .filter(([, dia]) => yaLlegaAlmorzada(dia))
    .map(([d]) => Number(d))
    .sort((a, b) => a - b);
}

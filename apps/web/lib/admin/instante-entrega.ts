import { hoyLima } from "@cayla-dynamic/shared";

/**
 * El instante exacto que se registra como entrega de un memo, a partir del DÍA
 * que eligió quien lo archiva.
 *
 * La pantalla pide un día, pero la base guarda un instante y lo valida contra
 * dos bordes (`fn_expediente_adjuntar`, mig. 0074): no puede ser futuro ni
 * anterior a la firma del documento.
 *
 * Con el mediodía fijo que se usaba antes, el caso más común de todos —firmar
 * el memo por la tarde y entregarlo ese mismo día— chocaba con el segundo
 * borde: la base respondía «la entrega no puede ser anterior a la firma» y
 * desde la pantalla no había forma de salir, porque la fecha que la persona
 * había puesto era la correcta. El error estaba en traducir "hoy" a las 12:00.
 *
 * La regla: si la entrega fue hoy vale el instante real; si fue un día
 * anterior, el mediodía de ese día, subido a la hora de la firma cuando la
 * firma cae más tarde. Nunca en el futuro.
 *
 * Por qué importa la precisión: de esta fecha cuelgan los plazos de descargo
 * (6 días hábiles en una imputación de cargos, art. 31). No es cosmética.
 */
export function instanteEntrega(
  dia: string,
  firmadoAt: string | null,
  ahora: Date = new Date(),
): string {
  // Perú no tiene horario de verano: el desfase es -05:00 fijo (ver fecha-lima.ts).
  let t = dia === hoyLima() ? ahora : new Date(`${dia}T12:00:00-05:00`);
  if (firmadoAt) {
    const firma = new Date(firmadoAt);
    if (!isNaN(firma.getTime()) && t < firma) t = firma;
  }
  if (t > ahora) t = ahora;
  return t.toISOString();
}

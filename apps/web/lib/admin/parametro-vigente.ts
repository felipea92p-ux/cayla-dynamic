// Qué fila de `parametros_laborales` rige un día — con la MISMA regla que la planilla.
//
// QUÉ PROMETE: dadas las filas de un parámetro versionado, devuelve la que rige
// el día pedido: `vigente_desde <= día` y (`vigente_hasta` nula o `>= día`), y si
// hay más de una, la de `vigente_desde` más reciente. Una por cada (clave, sede).
// Es la condición de `fn_planilla_calcular` y de `montoAsignacionFamiliar`; acá
// se escribe UNA vez para las pantallas que la necesitan.
//
// POR QUÉ EXISTE (2026-09-30, cuando la RMV pasó de 1,130 a 1,230): Contratos
// leía la RMV con `vigente_desde <= hoy` y `vigente_hasta IS NULL`. Esa lectura
// solo ve la fila ABIERTA. Al versionar la RMV se CIERRA la vieja (`vigente_hasta`
// = víspera) y se abre la nueva con fecha futura, y entre esas dos cosas no hay
// ninguna fila que cumpla: la pantalla se quedaba SIN RMV, el bloqueo del piso de
// la subvención no se disparaba y el convenio de jornada reducida imprimía
// «[FALTA PUBLICAR LA RMV VIGENTE EN EL SISTEMA]». Y, al revés, si la fila vieja
// sigue abierta y la nueva también, `.is(null)` devuelve las dos y `find` se queda
// con la primera que llegue, que puede ser la vieja.
//
// QUÉ NO HACE: no consulta nada ni sabe de sedes más allá de agrupar por ellas.
// La consulta la sigue haciendo la pantalla; esto solo decide qué fila manda.
// Tampoco inventa un valor si ninguna rige: devuelve una lista sin esa clave, y
// «no hay dato» sigue siendo «no hay dato» — nunca «pon el de siempre».

export interface FilaParametro {
  clave: string;
  sede_codigo: string | null;
  vigente_desde: string;
  vigente_hasta: string | null;
}

/** ¿Rige esta fila el día `dia` (aaaa-mm-dd)? Los extremos cuentan: es inclusivo. */
export function estaVigente(f: FilaParametro, dia: string): boolean {
  return f.vigente_desde <= dia && (f.vigente_hasta === null || f.vigente_hasta >= dia);
}

/**
 * Las filas que rigen `dia`, una por (clave, sede): la de `vigente_desde` más
 * reciente. Conserva el orden en que cada (clave, sede) apareció vigente por primera vez.
 * Las fechas son `aaaa-mm-dd`, que se comparan bien como texto.
 */
export function vigentesAl<T extends FilaParametro>(filas: readonly T[], dia: string): T[] {
  const porLlave = new Map<string, T>();
  for (const f of filas) {
    if (!estaVigente(f, dia)) continue;
    const llave = `${f.clave}|${f.sede_codigo ?? ""}`;
    const actual = porLlave.get(llave);
    if (!actual || f.vigente_desde > actual.vigente_desde) porLlave.set(llave, f);
  }
  return [...porLlave.values()];
}

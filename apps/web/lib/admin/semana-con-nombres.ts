// ============================================================================
// semana-con-nombres.ts — «Con nombres»: la semana de Turnos hora por hora,
// con quién está en cada hora (2026-11-02)
// ============================================================================
// PROMETE: dada la lista de turnos de UN día (ya resueltos por la cascada de
//          jornada-esperada.ts, en horas decimales), responde para una hora
//          concreta: cuántas operativas hay en su peor momento, cuántas líderes,
//          qué meta rige y quiénes son, con la hora exacta de quien entra o sale
//          dentro de esa hora.
// ASUME:   que quién «cuenta» (operativa) y quién es líder ya lo decidió
//          `cuentaEnCobertura` (packages/shared/src/cobertura-equipo.ts). Esto
//          no vuelve a decidirlo: recibe las dos marcas hechas.
// NO HACE: colores (eso es `estiloDeHora`, de cobertura-turnos.ts) ni leer la
//          base. Solo responde con números y nombres.
//
// POR QUÉ «el peor momento» y no «quién pasa por esa hora». La vista Integrada
// cuenta a cualquiera que toque la media hora; con eso, una hora en la que
// alguien se va a las 13:15 sale «completa» aunque de 13:15 a 14:00 falte gente.
// Esta vista mide la hora en cuatro cuartos y se queda con el MENOR: lo que la
// clienta encuentra en el peor momento de esa hora. Los nombres, en cambio, son
// todos los que pasan por ella, cada uno con su «entra 10:45» o «sale 13:15»
// para que se entienda por qué el número es menor que la lista.
//
// Y lo que queda antes de la primera entrada o después de la última salida del
// día no se mide (`fuera`): es la misma regla de `ventanaDelDia` en la
// Integrada, para que el domingo de TRU, que cierra a las 18:15, no salga en
// rojo de 18:15 en adelante.
// ============================================================================

export interface TurnoConNombre {
  id: string;
  nombre: string;
  /** Hora decimal de entrada (08:30 → 8.5). */
  entrada: number;
  /** Hora decimal de salida. */
  salida: number;
  /** Cuenta contra la meta de operativas (decidido por `cuentaEnCobertura`). */
  cuenta: boolean;
  /** Cuenta contra la meta de líderes. */
  lider: boolean;
  /** Por qué no suma, en una o dos palabras («preselección», el área). Solo si `cuenta` es false. */
  aparte?: string;
}

export interface PersonaEnLaHora {
  id: string;
  nombre: string;
  cuenta: boolean;
  lider: boolean;
  aparte?: string;
  /** Si entra dentro de esta hora, a qué hora; si no, null. */
  entra: number | null;
  /** Si sale dentro de esta hora, a qué hora; si no, null. */
  sale: number | null;
}

export interface CeldaConNombres {
  desde: number;
  hasta: number;
  /** La hora cae entera antes de la primera entrada o después de la última salida del día: no se mide. */
  fuera: boolean;
  /** Operativas en el peor cuarto de la hora. */
  enPiso: number;
  /** Líderes en el peor cuarto de la hora. */
  lideres: number;
  /** La meta más alta que rige en la hora (una hora puede cruzar el corte mañana/tarde). */
  meta: number;
  /** Hay gente en piso, hay meta de líderes y no hay ninguna líder en algún momento de la hora. */
  sinLider: boolean;
  /** Todos los que pasan por la hora: líderes primero, después por hora de entrada. */
  gente: PersonaEnLaHora[];
}

const CUARTOS = [0.125, 0.375, 0.625, 0.875]; // el centro de cada cuarto: un borde exacto no cuenta doble

/** La primera entrada y la última salida del día, entre quienes cuentan o lideran. */
export function ventanaDeTurnos(turnos: TurnoConNombre[]): { desde: number; hasta: number } | null {
  const medidos = turnos.filter((t) => t.cuenta || t.lider);
  if (medidos.length === 0) return null;
  return { desde: Math.min(...medidos.map((t) => t.entrada)), hasta: Math.max(...medidos.map((t) => t.salida)) };
}

/** Las horas en punto que hay que dibujar para toda la semana: de la primera entrada a la última salida, de cualquier día. */
export function horasDeLaSemana(dias: TurnoConNombre[][]): number[] {
  const todos = dias.flat();
  if (todos.length === 0) return [];
  const desde = Math.floor(Math.min(...todos.map((t) => t.entrada)));
  const hasta = Math.ceil(Math.max(...todos.map((t) => t.salida)));
  return Array.from({ length: Math.max(0, hasta - desde) }, (_, i) => desde + i);
}

export function celdaConNombres(args: {
  turnos: TurnoConNombre[];
  /** Hora en punto de inicio (8 = de 08:00 a 09:00). */
  hora: number;
  /** La meta de operativas que rige en un instante del día (la de la mañana o la de la tarde). */
  metaEn: (horaDecimal: number) => number;
  metaLideres: number;
}): CeldaConNombres {
  const { turnos, hora, metaEn, metaLideres } = args;
  const desde = hora, hasta = hora + 1;
  const ventana = ventanaDeTurnos(turnos);
  const muestras = CUARTOS.map((c) => hora + c).filter((x) => ventana !== null && x >= ventana.desde && x < ventana.hasta);
  const presentes = (x: number, filtro: (t: TurnoConNombre) => boolean) =>
    turnos.filter((t) => filtro(t) && t.entrada <= x && x < t.salida).length;

  const fuera = muestras.length === 0;
  const enPiso = fuera ? 0 : Math.min(...muestras.map((x) => presentes(x, (t) => t.cuenta)));
  const lideres = fuera ? 0 : Math.min(...muestras.map((x) => presentes(x, (t) => t.lider)));
  const meta = fuera ? 0 : Math.max(...muestras.map(metaEn));
  const sinLider = !fuera && metaLideres > 0 && lideres === 0 && enPiso > 0;

  const gente = turnos
    .filter((t) => t.entrada < hasta && t.salida > desde)
    .map((t) => ({
      id: t.id, nombre: t.nombre, cuenta: t.cuenta, lider: t.lider, aparte: t.aparte,
      entra: t.entrada > desde ? t.entrada : null,
      sale: t.salida < hasta ? t.salida : null,
    }))
    .sort((a, b) => Number(b.lider) - Number(a.lider) || (a.entra ?? desde) - (b.entra ?? desde) || a.nombre.localeCompare(b.nombre, "es"));

  return { desde, hasta, fuera, enPiso, lideres, meta, sinLider, gente };
}

// ----------------------------------------------------------------------------
// El resumen del pie (2026-11-02): cuatro números por día, para leer la semana
// sin recorrer todas las casillas.
// ----------------------------------------------------------------------------
// «Horas en tienda» suma de la entrada a la salida de cada persona, CON el
// refrigerio adentro. No es lo que se paga: para eso está la planilla, que
// descuenta el refrigerio. Es lo mismo que mide la cobertura —quien está en
// refrigerio sigue contada en la casilla—, y la leyenda lo dice con esas palabras.
// El promedio en piso se toma sobre las horas que se miden (no las de fuera del
// día), con el número del peor momento de cada una: el mismo de la casilla.

export interface ResumenDelDia {
  /** Suma de (salida − entrada) de todas las que trabajan ese día, en horas. */
  horasEnTienda: number;
  /** Cuántas personas tienen turno ese día. */
  personas: number;
  /** Promedio, sobre las horas medidas, de las operativas en piso. null si no hay horas medidas. */
  promedioEnPiso: number | null;
  /** Cuántas horas medidas quedan por debajo de su meta. */
  horasConFalta: number;
}

export function resumenDelDia(celdas: CeldaConNombres[], turnos: TurnoConNombre[]): ResumenDelDia {
  const medidas = celdas.filter((c) => !c.fuera);
  const horasEnTienda = turnos.reduce((a, t) => a + Math.max(0, t.salida - t.entrada), 0);
  return {
    horasEnTienda: Math.round(horasEnTienda * 100) / 100,
    personas: new Set(turnos.map((t) => t.id)).size,
    promedioEnPiso: medidas.length ? Math.round((medidas.reduce((a, c) => a + c.enPiso, 0) / medidas.length) * 10) / 10 : null,
    horasConFalta: medidas.filter((c) => c.meta > 0 && c.enPiso < c.meta).length,
  };
}

import type { MarcajeDelDia } from "@cayla-dynamic/shared";

/**
 * Qué marcas componen la jornada que esta persona tiene EN CURSO ahora mismo.
 *
 * POR QUÉ EXISTE. El terminal decidía qué ofrecer mirando solo las marcas de
 * HOY. A las 00:30, «hoy» es el día nuevo y está vacío, así que a quien acababa
 * de cerrar tienda le ofrecía «Entrada» — y con eso abría un día fantasma que el
 * auto-cierre remataba en 22 horas. La salida real nunca llegaba a existir (C4).
 *
 * POR QUÉ NO BASTA CON MIRAR AYER Y HOY JUNTOS, que fue lo primero que probé:
 * `determinarSiguienteAccion` responde «cerrado» en cuanto ve un `salida_final`
 * en la lista. Pasarle el día de ayer completo haría que a quien ayer cerró
 * normal y hoy llega a las 08:00 el terminal le dijera «ya registraste tu salida
 * final de hoy». Un error por otro.
 *
 * LA REGLA, y es la del turno, no la del calendario:
 *
 *   · Si ya marcó algo HOY, la jornada en curso es la de hoy. Da igual lo de
 *     ayer: la noche terminó.
 *   · Si no marcó nada hoy y la de AYER se quedó sin salida final, entonces
 *     sigue dentro de esa jornada — cruzó la medianoche.
 *   · En cualquier otro caso no hay jornada en curso, y le toca entrar.
 *
 * Vive aparte y sin tocar red ni React para poder probarla: es una decisión de
 * negocio, y la pantalla solo la consulta.
 */
export function marcasDeLaJornadaEnCurso(
  deAyer: MarcajeDelDia[],
  deHoy: MarcajeDelDia[],
): MarcajeDelDia[] {
  if (deHoy.length > 0) return deHoy;
  if (deAyer.length === 0) return [];

  const ayerSigueAbierta = !deAyer.some((m) => m.tipo === "salida_final");
  return ayerSigueAbierta ? deAyer : [];
}

/**
 * A QUÉ JORNADA PERTENECE CADA MARCA, y de ahí cuál es la que está en curso.
 *
 * Es la mitad de terminal del defecto que la 0317 arregla en la base. Quien
 * cierra tienda a las 00:30 tiene su salida guardada con `fecha_jornada` del día
 * ANTERIOR —eso lo hace bien la 0240— pero este archivo repartía las marcas por
 * la fecha de CALENDARIO del `timestamp_marca`, así que esa salida caía en el
 * cubo de HOY.
 *
 * Consecuencia medida: al marcar su entrada de la mañana, la máquina de estados
 * veía un `salida_final` en la lista de hoy y respondía «cerrado». El terminal
 * mostraba «Ya cerraste tu día. ¿Volviste a entrar?» y el único botón hacia
 * adelante anulaba la salida REAL de anoche — 9,50 h y S/109,62 medidos, y el
 * día del martes reabierto sin entrada.
 *
 * La regla es de una línea: **manda `fecha_jornada` si la hay, y solo si no la
 * hay se mira el calendario.** Las entradas no la llevan, y por eso el
 * `coalesce` no es un adorno defensivo: es el caso normal.
 *
 * Se saca aquí, a una función pura, porque antes vivía dentro de
 * `cargarMarcajesHoyPorPersona`, que hace red — y por eso no la probaba nadie.
 */
export function jornadaEnCursoPorPersona(
  filas: {
    persona_id: string;
    tipo: MarcajeDelDia["tipo"];
    timestamp_marca: string;
    fecha_jornada?: string | null;
  }[],
  hoy: string,
  diaDelTimestamp: (ts: string) => string,
): Map<string, MarcajeDelDia[]> {
  const ayer = new Map<string, MarcajeDelDia[]>();
  const hoyMap = new Map<string, MarcajeDelDia[]>();

  for (const m of filas) {
    const dia = m.fecha_jornada ?? diaDelTimestamp(m.timestamp_marca);
    const destino = dia === hoy ? hoyMap : ayer;
    const lista = destino.get(m.persona_id) ?? [];
    lista.push({ tipo: m.tipo, timestamp: m.timestamp_marca });
    destino.set(m.persona_id, lista);
  }

  const mapa = new Map<string, MarcajeDelDia[]>();
  for (const personaId of new Set([...ayer.keys(), ...hoyMap.keys()])) {
    const enCurso = marcasDeLaJornadaEnCurso(ayer.get(personaId) ?? [], hoyMap.get(personaId) ?? []);
    if (enCurso.length > 0) mapa.set(personaId, enCurso);
  }
  return mapa;
}

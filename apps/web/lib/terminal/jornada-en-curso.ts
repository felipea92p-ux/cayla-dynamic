import { TOPE_JORNADA_CRUZA_MEDIANOCHE_HORAS, type MarcajeDelDia } from "@cayla-dynamic/shared";

const TOPE_MS = TOPE_JORNADA_CRUZA_MEDIANOCHE_HORAS * 60 * 60 * 1000;

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
 *     sigue dentro de esa jornada — cruzó la medianoche…
 *   · …PERO SOLO HASTA LAS 16 HORAS DESDE SU ENTRADA. Ver abajo.
 *   · En cualquier otro caso no hay jornada en curso, y le toca entrar.
 *
 * ── EL TOPE DE 16 HORAS, Y POR QUÉ ESTABA MAL QUE NO ESTUVIERA ──────────────
 *
 * `fn_registrar_marcaje` adopta la jornada de ayer con esta condición:
 *
 *     and p_timestamp_cliente <= j.entrada_ts + interval '16 hours'
 *
 * Este archivo no la tenía. Pasado ese tope las dos mitades del sistema decían
 * cosas distintas sobre la misma persona: el navegador seguía creyéndola dentro
 * de la jornada de ayer y le ofrecía un menú de SALIDAS, y el servidor ya
 * esperaba una `entrada` de hoy. Cualquier botón que pulsara lo rechazaba el
 * servidor —«tipo salida_final no válido en el estado actual (se esperaba
 * entrada)»— y la pantalla no ofrecía ninguna otra cosa que pulsar.
 *
 * El agujero era real y no teórico: `fn_auto_cierre` corre cada 15 minutos y
 * tiene su PROPIA condición para cerrar una jornada, así que hay una franja en
 * la que la jornada de ayer ya pasó las 16 h y todavía no la ha cerrado nadie.
 * Ahí dentro, quien fuera a marcar se quedaba sin poder hacerlo.
 *
 * Se mide contra la ENTRADA de esa jornada, igual que el servidor mide contra
 * `j.entrada_ts` — no contra la última marca ni contra la medianoche. Y si no
 * hay entrada, no hay jornada que adoptar: el servidor pide `j.entrada_ts is
 * not null` por la misma razón.
 *
 * Vive aparte y sin tocar red ni React para poder probarla: es una decisión de
 * negocio, y la pantalla solo la consulta. `ahoraMs` entra como argumento y no
 * se lee de `Date.now()` acá dentro por lo mismo — una decisión que depende del
 * reloj y no lo recibe es una decisión que no se puede probar.
 */
export function marcasDeLaJornadaEnCurso(
  deAyer: MarcajeDelDia[],
  deHoy: MarcajeDelDia[],
  ahoraMs: number,
): MarcajeDelDia[] {
  if (deHoy.length > 0) return deHoy;
  if (deAyer.length === 0) return [];

  const ayerSigueAbierta = !deAyer.some((m) => m.tipo === "salida_final");
  if (!ayerSigueAbierta) return [];

  // La entrada de esa jornada. Sin ella el servidor no adopta nada, así que
  // tampoco lo hace la pantalla: ofrecerle salidas sería ofrecerle un botón
  // condenado.
  const entrada = deAyer
    .filter((m) => m.tipo === "entrada")
    .map((m) => Date.parse(m.timestamp))
    .filter((t) => Number.isFinite(t))
    .sort((a, b) => a - b)[0];
  if (entrada === undefined) return [];

  return ahoraMs <= entrada + TOPE_MS ? deAyer : [];
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
  ahoraMs: number,
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
    const enCurso = marcasDeLaJornadaEnCurso(
      ayer.get(personaId) ?? [],
      hoyMap.get(personaId) ?? [],
      ahoraMs,
    );
    if (enCurso.length > 0) mapa.set(personaId, enCurso);
  }
  return mapa;
}

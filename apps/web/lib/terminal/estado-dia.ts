import { createTerminalSupabaseClient } from "@cayla-dynamic/database";
import {
  determinarSiguienteAccion,
  fechaLima,
  hoyLima,
  rangoDelDiaLima,
  type MarcajeDelDia,
  type SiguienteAccion,
} from "@cayla-dynamic/shared";
import { obtenerPendientes } from "./offline-db";
import { jornadaEnCursoPorPersona } from "./jornada-en-curso";
import { topeDeRed } from "./tope-de-red";

/**
 * Qué día es hoy en Lima.
 *
 * Delega en `hoyLima()` en vez de repetir el `Intl.DateTimeFormat`: el corte del
 * día decide a qué fecha se le paga un marcaje, y el CLAUDE.md pide que esa
 * respuesta tenga UNA sola versión. Este archivo llegó a tener tres copias del
 * huso de Lima —esta, el `-05:00` escrito a mano del filtro, y la de abajo—.
 */
export function fechaLimaHoy(): string {
  return hoyLima();
}

/**
 * El resultado de cargar el estado del día: el mapa, y si de verdad se pudo
 * CONFIRMAR contra el servidor o es solo lo que hay en la cola local.
 *
 * `confiable` existe porque un mapa vacío significaba DOS cosas y el terminal
 * las trataba como una sola: «confirmé que esta persona no tiene marcas hoy» y
 * «no pude preguntarle al servidor, no sé nada de ella». La primera es el 99 %
 * de los casos (alguien que recién llega) y `siguienteAccionPara` acierta
 * ofreciéndole «Entrada». La segunda pasaba, sobre todo, justo después de que
 * esta pestaña se recargara —un teléfono que estuvo en segundo plano, una Mac
 * mini que se reinició— en el instante exacto en que el refresco periódico
 * coincidía con un corte de red: el mapa quedaba vacío para TODOS, y a quien
 * ya llevaba horas adentro el terminal volvía a ofrecerle «Entrada». El
 * servidor la rechazaba bien (ver fn_registrar_marcaje), pero la marca se
 * apartaba sin que nadie se enterara hasta que alguien la reconstruía a mano
 * horas después (casos reales: Raquel Ticona y Joselyn Gavilan, 2026-09-09).
 *
 * Quien llama decide con esto qué hacer: si `confiable` es `false`, no hay
 * que confiar en que el mapa está completo — hay que preguntar de nuevo antes
 * de ofrecer ninguna acción.
 */
export interface EstadoDelDia {
  mapa: Map<string, MarcajeDelDia[]>;
  confiable: boolean;
}

export async function cargarMarcajesHoyPorPersona(): Promise<EstadoDelDia> {
  const mapa = new Map<string, MarcajeDelDia[]>();
  let confiable = false;

  if (typeof navigator !== "undefined" && navigator.onLine) {
    const supabase = createTerminalSupabaseClient();
    // Los DOS extremos del día, no solo el de abajo. Con `.gte` a secas, una
    // marca con fecha futura —hoy se pueden guardar— quedaba viva para siempre
    // en el estado del día: el terminal creía a esa persona dentro, no le
    // dejaba marcar su salida, y fn_reabrir_dia respondía «No hay una salida
    // final de hoy para reabrir». El servidor sí filtra por fecha exacta; era
    // esta copia la que difería.
    const { inicio: inicioDia, fin: finDia } = rangoDelDiaLima();
    // DESDE AYER, no desde hoy (0240). Quien cierra tienda a las 00:30 sigue
    // dentro de la jornada del día anterior, y el terminal tiene que saberlo
    // para ofrecerle SALIR en vez de entrar. Se trae el rango ampliado y luego
    // `marcasDeLaJornadaEnCurso` decide cuál de los dos días manda — pasarle los
    // dos juntos a la máquina de estados le haría decir «ya registraste tu
    // salida» a quien ayer cerró normal y hoy llega por la mañana.
    const inicioAyer = new Date(new Date(inicioDia).getTime() - 24 * 60 * 60 * 1000).toISOString();
    // Con tope y dentro de un try: esta consulta corre en el arranque y en cada
    // refresco, y sin tope una red colgada dejaba a `cargarTodo()` esperando para
    // siempre. Aquí el respaldo es no traer nada del servidor y quedarse con lo
    // local, que es exactamente lo que hace el bloque de abajo.
    type FilaMarcaje = {
      persona_id: string;
      tipo: MarcajeDelDia["tipo"];
      timestamp_marca: string;
      // ⇩ SIN ESTA COLUMNA EL TERMINAL BORRA HORAS. Quien cierra tienda a las
      // 00:30 tiene su salida guardada con la `fecha_jornada` del día anterior;
      // repartiendo por el calendario del `timestamp_marca`, esa salida caía en
      // el cubo de HOY y el terminal le decía «ya cerraste tu día» a quien
      // acababa de llegar. Ver `jornadaEnCursoPorPersona`.
      fecha_jornada: string | null;
    };
    let data: FilaMarcaje[] | null = null;
    try {
      const res = await supabase
        .from("marcajes")
        .select("persona_id, tipo, timestamp_marca, fecha_jornada")
        .abortSignal(topeDeRed())
        // Las anuladas (mig. 0081) no existen para el estado del día. Sin este
        // filtro, anular la entrada de alguien dejaba al terminal creyéndolo
        // dentro: le ofrecería "salida" y no le dejaría volver a marcar entrada.
        // La 0082 arregló esto en fn_siguiente_tipo_esperado, pero el terminal
        // decide en el navegador con determinarSiguienteAccion, y esa es otra copia.
        .is("anulada_at", null)
        .gte("timestamp_marca", inicioAyer)
        .lte("timestamp_marca", finDia);
      // `confiable` solo si el servidor de verdad contestó — postgrest puede
      // devolver `{data: null, error}` SIN lanzar, y eso es tan "no sé" como
      // un corte de red. Un array vacío SIN error sí es una respuesta real
      // (nadie marcó nada en el rango) y cuenta como confiable.
      if (!res.error) {
        data = res.data as unknown as FilaMarcaje[];
        confiable = true;
      }
    } catch {
      data = null;
    }

    // Se separan por día ANTES de decidir. `fechaLima` y no el huso del
    // navegador: el corte del día es el de Lima, y esa respuesta tiene un solo
    // sitio (fecha-lima.ts).
    const hoyStr = fechaLimaHoy();
    // `Date.now()` se lee ACÁ y se pasa hacia adentro: `jornadaEnCursoPorPersona`
    // aplica con él el mismo tope de 16 h que `fn_registrar_marcaje`, y una
    // función que consulta el reloj por su cuenta no se puede probar.
    for (const [personaId, enCurso] of jornadaEnCursoPorPersona(data ?? [], hoyStr, fechaLima, Date.now())) {
      mapa.set(personaId, enCurso);
    }
  }

  // Superpone marcajes locales aún no sincronizados (offline u optimistas recién hechos),
  // pero SOLO los de HOY: una marca vieja atascada de ayer no debe mostrarse como si
  // fuera de hoy (eso confundía el estado del día tras cruzar la medianoche).
  const hoy = fechaLimaHoy();
  const pendientes = await obtenerPendientes();
  for (const p of pendientes) {
    if (fechaLima(p.timestampCliente) !== hoy) continue;
    // El servidor YA contestó que no a esta marca (rechazo real, no un corte
    // de red) — sigue en la cola por si un reintento la resuelve, pero no
    // debe seguir contando como "de hoy" mientras tanto: antes de esto, el
    // terminal podía ofrecer una acción (p. ej. "¿volviste a entrar?") sobre
    // una salida que el servidor nunca aceptó, hasta que sync.ts acumulara
    // seis fallos confirmados (minuto y medio) y recién ahí la apartara.
    if (p.rechazadaPorServidor) continue;
    const lista = mapa.get(p.personaId) ?? [];
    lista.push({ tipo: p.tipo, timestamp: p.timestampCliente });
    mapa.set(p.personaId, lista);
  }

  return { mapa, confiable };
}

/**
 * Pregunta al servidor por UNA sola persona, con un tope corto — para el
 * único momento en que de verdad hace falta esperar una respuesta antes de
 * seguir: cuando se tocó un nombre y esta pestaña todavía no ha podido
 * confirmar el estado de NADIE desde que arrancó (ver `confiable` arriba).
 *
 * No es una versión reducida de `cargarMarcajesHoyPorPersona`: es más
 * angosta a propósito (un solo `eq`, 3 s en vez de 8) porque acá alguien está
 * de pie esperando, mientras que el refresco periódico corre solo, de fondo,
 * sin que nadie lo mire.
 *
 * Devuelve `null` si no se pudo confirmar (offline, error, o venció el tope)
 * — nunca un array vacío por defecto. Quien llama decide qué hacer con ese
 * `null`: nunca asumir "Entrada".
 */
export async function confirmarEstadoPuntual(personaId: string): Promise<MarcajeDelDia[] | null> {
  if (typeof navigator !== "undefined" && !navigator.onLine) return null;

  const { inicio: inicioDia, fin: finDia } = rangoDelDiaLima();
  const inicioAyer = new Date(new Date(inicioDia).getTime() - 24 * 60 * 60 * 1000).toISOString();
  const hoyStr = fechaLimaHoy();

  let filas: { persona_id: string; tipo: MarcajeDelDia["tipo"]; timestamp_marca: string; fecha_jornada: string | null }[] = [];
  try {
    const supabase = createTerminalSupabaseClient();
    const res = await supabase
      .from("marcajes")
      .select("persona_id, tipo, timestamp_marca, fecha_jornada")
      .eq("persona_id", personaId)
      .is("anulada_at", null)
      .gte("timestamp_marca", inicioAyer)
      .lte("timestamp_marca", finDia)
      .abortSignal(topeDeRed(3));
    if (res.error) return null;
    filas = (res.data ?? []) as unknown as typeof filas;
  } catch {
    return null;
  }

  const porPersona = jornadaEnCursoPorPersona(filas, hoyStr, fechaLima, Date.now());
  const marcasDeHoy = porPersona.get(personaId) ?? [];

  // Superpone lo local pendiente de esta persona, igual que el refresco
  // periódico — un marcaje optimista recién hecho no debe desaparecer solo
  // porque esta confirmación puntual llegó primero que la sincronización.
  const hoy = hoyStr;
  const pendientes = await obtenerPendientes();
  for (const p of pendientes) {
    if (p.personaId !== personaId) continue;
    if (fechaLima(p.timestampCliente) !== hoy) continue;
    if (p.rechazadaPorServidor) continue;
    marcasDeHoy.push({ tipo: p.tipo, timestamp: p.timestampCliente });
  }

  return marcasDeHoy;
}

export function siguienteAccionPara(marcajesHoy: MarcajeDelDia[]): SiguienteAccion {
  return determinarSiguienteAccion(marcajesHoy);
}

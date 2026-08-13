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
import { marcasDeLaJornadaEnCurso } from "./jornada-en-curso";
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

export async function cargarMarcajesHoyPorPersona(): Promise<Map<string, MarcajeDelDia[]>> {
  const mapa = new Map<string, MarcajeDelDia[]>();

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
    };
    let data: FilaMarcaje[] | null = null;
    try {
      const res = await supabase
        .from("marcajes")
        .select("persona_id, tipo, timestamp_marca")
        .abortSignal(topeDeRed())
        // Las anuladas (mig. 0081) no existen para el estado del día. Sin este
        // filtro, anular la entrada de alguien dejaba al terminal creyéndolo
        // dentro: le ofrecería "salida" y no le dejaría volver a marcar entrada.
        // La 0082 arregló esto en fn_siguiente_tipo_esperado, pero el terminal
        // decide en el navegador con determinarSiguienteAccion, y esa es otra copia.
        .is("anulada_at", null)
        .gte("timestamp_marca", inicioAyer)
        .lte("timestamp_marca", finDia);
      data = res.data as unknown as FilaMarcaje[];
    } catch {
      data = null;
    }

    // Se separan por día ANTES de decidir. `fechaLima` y no el huso del
    // navegador: el corte del día es el de Lima, y esa respuesta tiene un solo
    // sitio (fecha-lima.ts).
    const hoyStr = fechaLimaHoy();
    const porPersonaAyer = new Map<string, MarcajeDelDia[]>();
    const porPersonaHoy = new Map<string, MarcajeDelDia[]>();
    for (const m of data ?? []) {
      const destino = fechaLima(m.timestamp_marca) === hoyStr ? porPersonaHoy : porPersonaAyer;
      const lista = destino.get(m.persona_id) ?? [];
      lista.push({ tipo: m.tipo, timestamp: m.timestamp_marca });
      destino.set(m.persona_id, lista);
    }
    for (const personaId of new Set([...porPersonaAyer.keys(), ...porPersonaHoy.keys()])) {
      const enCurso = marcasDeLaJornadaEnCurso(
        porPersonaAyer.get(personaId) ?? [],
        porPersonaHoy.get(personaId) ?? [],
      );
      if (enCurso.length > 0) mapa.set(personaId, enCurso);
    }
  }

  // Superpone marcajes locales aún no sincronizados (offline u optimistas recién hechos),
  // pero SOLO los de HOY: una marca vieja atascada de ayer no debe mostrarse como si
  // fuera de hoy (eso confundía el estado del día tras cruzar la medianoche).
  const hoy = fechaLimaHoy();
  const pendientes = await obtenerPendientes();
  for (const p of pendientes) {
    if (fechaLima(p.timestampCliente) !== hoy) continue;
    const lista = mapa.get(p.personaId) ?? [];
    lista.push({ tipo: p.tipo, timestamp: p.timestampCliente });
    mapa.set(p.personaId, lista);
  }

  return mapa;
}

export function siguienteAccionPara(marcajesHoy: MarcajeDelDia[]): SiguienteAccion {
  return determinarSiguienteAccion(marcajesHoy);
}

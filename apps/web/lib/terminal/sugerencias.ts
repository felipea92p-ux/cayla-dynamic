import { createTerminalSupabaseClient } from "@cayla-dynamic/database";
import { calcularHoraMediaRefrigerio, hoyLima, type EstadisticasSugerencia } from "@cayla-dynamic/shared";
import { esperadoDelDia, horarioVigente, type HorarioTramo, type TurnoDia } from "@/lib/admin/jornada-esperada";
import { horaDecimalDeHHMM, type HorarioDeHoy } from "./presencia";
import { topeDeRed } from "./tope-de-red";

const DIAS_HISTORIAL_REFRIGERIO = 30;

/**
 * Lo que el terminal sabe de cada persona antes de que toque su nombre: el
 * ritmo para sugerir la salida (`EstadisticasSugerencia`) y, de los MISMOS
 * horarios ya cargados, qué le toca hoy (`HorarioDeHoy`) — para que la casilla
 * distinga «aún no llega» de «hoy no trabaja» sin pedirle nada nuevo a la red.
 */
export interface EstadisticasTerminal extends EstadisticasSugerencia, HorarioDeHoy {}

/**
 * El ritmo de cada persona de la sede, para afinar qué salida sugerir en el
 * terminal — ver `sugerirSalidaPrincipal` en packages/shared. Se trae en
 * bloque al cargar el roster, nunca al tocar un nombre: marcar tiene que
 * seguir siendo instantáneo (decisión de Felipe, jul-2026), y eso no admite
 * una consulta de red en el camino.
 *
 * MISMA RECETA DEFENSIVA que `cargarMarcajesHoyPorPersona` (estado-dia.ts):
 * sin red no se intenta nada, cada consulta va en su propio try/catch para
 * que la falla de una no tumbe a las otras, y nunca se lanza — en el peor
 * caso, esta función devuelve un mapa vacío y `sugerirSalidaPrincipal` cae
 * sola a la regla fija de siempre. Nadie se queda sin poder marcar por esto.
 *
 * LÍMITE CONOCIDO: usa `hoyLima()` para resolver el horario esperado, no la
 * fecha de la jornada en curso de cada persona. Para quien sigue dentro de
 * la jornada de AYER (turno que cruza medianoche, ver `jornada-en-curso.ts`)
 * esto puede pedir el horario del día equivocado. Se acepta para este primer
 * corte porque el efecto es acotado —la sugerencia de salida final puede
 * llegar tarde o temprano para ese caso puntual, nunca bloquea el marcaje—,
 * pero si se nota que pesa, la resolución correcta es reusar
 * `jornadaEnCursoPorPersona`, no reinventarla acá.
 */
export async function cargarEstadisticasSugerenciaPorPersona(): Promise<Map<string, EstadisticasTerminal>> {
  const mapa = new Map<string, EstadisticasTerminal>();
  if (typeof navigator === "undefined" || !navigator.onLine) return mapa;

  const supabase = createTerminalSupabaseClient();
  const hoy = hoyLima();

  const mediasPorPersona = new Map<string, number | null>();
  try {
    const desde = new Date(Date.now() - DIAS_HISTORIAL_REFRIGERIO * 24 * 60 * 60 * 1000).toISOString();
    const res = await supabase
      .from("marcajes")
      .select("persona_id, timestamp_marca")
      .eq("tipo", "salida_almuerzo")
      .is("anulada_at", null)
      .gte("timestamp_marca", desde)
      .abortSignal(topeDeRed());
    const filas = (res.data ?? []) as { persona_id: string; timestamp_marca: string }[];
    const porPersona = new Map<string, string[]>();
    for (const f of filas) {
      const lista = porPersona.get(f.persona_id) ?? [];
      lista.push(f.timestamp_marca);
      porPersona.set(f.persona_id, lista);
    }
    for (const [personaId, timestamps] of porPersona) {
      mediasPorPersona.set(personaId, calcularHoraMediaRefrigerio(timestamps)?.media ?? null);
    }
  } catch {
    // Sin historial de refrigerio: cada persona cae sola a la regla fija.
  }

  const horariosPorPersona = new Map<string, HorarioTramo[]>();
  try {
    const res = await supabase
      .from("horarios_asignados")
      .select(
        "persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida, dias_laborables, horario_por_dia, almuerzo_min_minutos",
      )
      .abortSignal(topeDeRed());
    const filas = (res.data ?? []) as HorarioTramo[];
    for (const t of filas) {
      const lista = horariosPorPersona.get(t.persona_id) ?? [];
      lista.push(t);
      horariosPorPersona.set(t.persona_id, lista);
    }
  } catch {
    // Sin horario asignado: cada persona cae sola al respaldo de salida final.
  }

  const turnosPorPersona = new Map<string, TurnoDia>();
  try {
    const res = await supabase
      .from("turnos")
      .select("persona_id, hora_entrada, hora_salida, es_descanso")
      .eq("fecha", hoy)
      .abortSignal(topeDeRed());
    const filas = (res.data ?? []) as (TurnoDia & { persona_id: string })[];
    for (const t of filas) turnosPorPersona.set(t.persona_id, t);
  } catch {
    // Sin turno puntual de hoy: esperadoDelDia sigue con el horario base.
  }

  const personaIds = new Set([...mediasPorPersona.keys(), ...horariosPorPersona.keys()]);
  for (const personaId of personaIds) {
    const tramos = horariosPorPersona.get(personaId) ?? [];
    const horario = horarioVigente(tramos, hoy);
    const turno = turnosPorPersona.get(personaId) ?? null;
    const esperado = esperadoDelDia(hoy, turno, horario);
    const horaSalidaEsperada = esperado.trabaja && esperado.salida ? horaDecimalDeHHMM(esperado.salida) : null;

    mapa.set(personaId, {
      horaMediaRefrigerio: mediasPorPersona.get(personaId) ?? null,
      horaSalidaEsperada,
      entradaEsperada: esperado.trabaja ? esperado.entrada : null,
      // «Sin horario» NO es «de descanso»: solo se afirma lo segundo cuando el
      // horario o el turno de hoy lo dicen (`origen` distinto de sin_horario).
      libreHoy: !esperado.trabaja && esperado.origen !== "sin_horario",
    });
  }

  return mapa;
}

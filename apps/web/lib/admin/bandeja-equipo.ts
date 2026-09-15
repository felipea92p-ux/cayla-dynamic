import type { ClienteCayla } from "@cayla-dynamic/database";
import {
  puedeGestionarCatalogos, puedeGestionarContratos, puedeOperarEquipo, puedeVerPlanilla, puedeVerSaludDeAlertas,
} from "@cayla-dynamic/shared";

/**
 * Cuánto hay pendiente en la Bandeja del panel (la de encargada/DO en
 * `/admin/bandeja`, no la de `/mio`) — un solo número para el bolito rojo del
 * ítem «Bandeja» del menú.
 *
 * POR QUÉ EXISTE, SI `/admin/bandeja` YA TRAE LAS MISMAS LISTAS
 *
 * Esa pantalla junta NUEVE secciones (0257, 0290, 0330, 0362, 0385, 0399,
 * 0425, 0427), pero solo TRES tenían, hasta ahora, un contador en algún lado
 * del menú: educación, ausencias y revisiones (incidencias). Las otras seis
 * —sin horario vigente, revisión de ruta, revisión de contrato, solicitudes
 * de vacaciones, solicitudes de cambio de perfil, salud del despacho de
 * avisos— no encendían nada: alguien podía tener trabajo esperando ahí y no
 * enterarse sin entrar a mirar. Este número es la unión de las nueve, para
 * que el propio ítem «Bandeja» avise de lo que las otras tres no cubren.
 *
 * Repite las mismas RPC y el mismo criterio de "pendiente" que ya usa
 * `bandeja/page.tsx` —nunca inventa uno nuevo—, solo que acá se pide el
 * LARGO de cada lista en vez de la lista entera. Es el mismo patrón que ya
 * usaba `nav.tsx` para «revisiones» antes de esto (llamar la misma RPC que
 * la pantalla, quedarse con `.length`): una función de conteo aparte sería
 * un segundo criterio que podría separarse del primero.
 *
 * Falla silencioso por sección, como el resto de los contadores del menú: un
 * error o una RPC que todavía no existe en esta base (`fn_personas_sin_horario_vigente`,
 * 0385) restan esa sección del total en vez de tumbar el badge entero.
 */
/** Un estudio tal como lo trae `fn_educacion_situacion` (0450), con lo que la Bandeja necesita. */
export interface FilaEducacionBandeja {
  familia_id: string;
  persona_id: string;
  persona: string;
  sede: string;
  institucion: string;
  vigencia: string;
  estado_constancia: string;
  fecha_pago_constancia: string | null;
  plazo: string | null;
  pago_proximo: boolean;
  proxima_fecha_pago: string | null;
  dias_para_pago: number | null;
}

/**
 * ¿Este estudio va en «Para saber»? Lo que le pide acción a DO sin ser una
 * entrega —constancia vencida, estudio vigente sin calendario, el mismo criterio
 * que `fn_educacion_por_atender`— más los pagos a la institución que llegan en
 * los próximos días: el aviso que DO pidió para tener el apoyo listo.
 *
 * Una sola definición para la pantalla y para este contador: dos copias de
 * «qué cuenta» es cómo el número deja de corresponder a la lista.
 */
export function esEducacionParaSaber(f: FilaEducacionBandeja): boolean {
  return f.estado_constancia === "vencida"
    || (f.estado_constancia === "sin_calendario" && (f.vigencia === "vigente" || f.vigencia === "por_terminar"))
    || f.pago_proximo;
}

export async function contarBandejaEquipoPendiente(
  supabase: ClienteCayla,
  rol: string | null | undefined,
): Promise<number> {
  // `PromiseLike`, no `Promise`: `.rpc(...)` devuelve un `PostgrestFilterBuilder`
  // (thenable, no una `Promise` de verdad), y `.then()` sobre eso conserva el
  // mismo tipo — lo mismo que ya le pasa a `tareas` en bandeja/page.tsx.
  const tareas: PromiseLike<number>[] = [];

  if (puedeVerPlanilla(rol)) {
    // ⇩ CAMBIO 0450 ⇩ Las tres secciones de educación que pinta la Bandeja:
    // constancias por revisar y avisos de «ya no voy a pagar» (Por aprobar), y
    // los estudios para tener presentes (Para saber). Una entrega cuenta UNO,
    // tenga los archivos que tenga.
    tareas.push(
      Promise.all([
        supabase.rpc("fn_educacion_entregas_pendientes"),
        supabase.rpc("fn_educacion_avisos_fin_pendientes"),
        supabase.rpc("fn_educacion_situacion"),
      ]).then(([entregas, avisos, situacion]) =>
        (Array.isArray(entregas.data) ? entregas.data.length : 0)
        + (Array.isArray(avisos.data) ? avisos.data.length : 0)
        + ((situacion.data as unknown as FilaEducacionBandeja[] | null) ?? []).filter(esEducacionParaSaber).length),
    );
    tareas.push(
      supabase.rpc("fn_solicitudes_vacaciones", { p_solo_pendientes: true })
        .then(({ data }) => (Array.isArray(data) ? data.length : 0)),
    );
  }

  if (puedeOperarEquipo(rol)) {
    tareas.push(
      supabase.rpc("fn_vacaciones_por_vencer", { p_dias: 60, p_as_of: null })
        .then(({ data }) => (Array.isArray(data) ? data.length : 0)),
    );
    tareas.push(
      supabase.rpc("fn_personas_sin_horario_vigente", { p_dias: 60 })
        .then(({ data }) => (Array.isArray(data) ? data.length : 0)),
    );
    tareas.push(
      supabase.rpc("fn_revisiones_pedidas", { p_solo_pendientes: true })
        .then(({ data }) => (Array.isArray(data) ? data.length : 0)),
    );
    tareas.push(
      supabase.rpc("fn_solicitudes_perfil_pendientes")
        .then(({ data }) => (Array.isArray(data) ? data.length : 0)),
    );
  }

  if (puedeGestionarCatalogos(rol)) {
    tareas.push(
      supabase.rpc("fn_movilidad_revisiones_pedidas", { p_solo_pendientes: true })
        .then(({ data }) => (Array.isArray(data) ? data.length : 0)),
    );
  }

  if (puedeGestionarContratos(rol)) {
    tareas.push(
      supabase.rpc("fn_contrato_revisiones_pedidas", { p_solo_pendientes: true })
        .then(({ data }) => (Array.isArray(data) ? data.length : 0)),
    );
  }

  if (puedeVerSaludDeAlertas(rol)) {
    tareas.push(
      supabase.rpc("fn_alertas_despacho_resumen").then(({ data }) => {
        if (!data) return 0;
        const r = data as unknown as { atascadas: number; fallidas_definitivas: number; caducadas: number };
        return r.atascadas + r.fallidas_definitivas + r.caducadas;
      }),
    );
  }

  const conteos = await Promise.all(tareas);
  return conteos.reduce((a, b) => a + b, 0);
}

/**
 * Lo mismo que `contarBandejaEquipoPendiente`, pero agrupado POR PERSONA en
 * vez de un solo número — para el badge de "N pendientes" de `/admin/equipo`
 * (0428). Mismas RPC, mismos permisos, mismo criterio de "pendiente": no se
 * inventa un tercer criterio para una tercera pantalla.
 *
 * Queda afuera `fn_alertas_despacho_resumen`: es salud del cron de avisos por
 * correo, no la tarea de una persona — no tiene `persona_id` que agrupar.
 *
 * Tolerante por sección, igual que el contador: si una RPC falla o no existe
 * todavía en esta base, esa sección no aporta nada al mapa en vez de tumbar
 * las demás.
 */
export async function listarPendientesPorPersona(
  supabase: ClienteCayla,
  rol: string | null | undefined,
): Promise<Map<string, string[]>> {
  const mapa = new Map<string, string[]>();
  const agregar = (id: string | null | undefined, etiqueta: string) => {
    if (!id) return;
    const lista = mapa.get(id) ?? [];
    lista.push(etiqueta);
    mapa.set(id, lista);
  };

  const tareas: PromiseLike<void>[] = [];

  if (puedeVerPlanilla(rol)) {
    tareas.push(
      supabase.rpc("fn_educacion_listar").then(({ data }) => {
        ((data as unknown as { persona_id: string; semaforo: string; meses_sin_papel: number }[] | null) ?? [])
          .filter((f) => f.semaforo === "sin_comprobante" || f.semaforo === "por_vencer" || f.meses_sin_papel > 0)
          .forEach((f) => agregar(f.persona_id, "Educación: comprobante pendiente"));
      }),
    );
    tareas.push(
      supabase.rpc("fn_solicitudes_vacaciones", { p_solo_pendientes: true }).then(({ data }) => {
        (Array.isArray(data) ? (data as { persona_id: string }[]) : [])
          .forEach((r) => agregar(r.persona_id, "Solicitud de vacaciones"));
      }),
    );
  }

  if (puedeOperarEquipo(rol)) {
    tareas.push(
      supabase.rpc("fn_vacaciones_por_vencer", { p_dias: 60, p_as_of: null }).then(({ data }) => {
        (Array.isArray(data) ? (data as { persona_id: string }[]) : [])
          .forEach((r) => agregar(r.persona_id, "Vacaciones por vencer"));
      }),
    );
    tareas.push(
      supabase.rpc("fn_personas_sin_horario_vigente", { p_dias: 60 }).then(({ data }) => {
        (Array.isArray(data) ? (data as { persona_id: string }[]) : [])
          .forEach((r) => agregar(r.persona_id, "Sin horario vigente"));
      }),
    );
    tareas.push(
      supabase.rpc("fn_revisiones_pedidas", { p_solo_pendientes: true }).then(({ data }) => {
        (Array.isArray(data) ? (data as { persona_id: string }[]) : [])
          .forEach((r) => agregar(r.persona_id, "Revisión de marcaje pedida"));
      }),
    );
    tareas.push(
      supabase.rpc("fn_solicitudes_perfil_pendientes").then(({ data }) => {
        (Array.isArray(data) ? (data as { persona_id: string }[]) : [])
          .forEach((r) => agregar(r.persona_id, "Cambio de perfil pendiente"));
      }),
    );
  }

  if (puedeGestionarCatalogos(rol)) {
    tareas.push(
      supabase.rpc("fn_movilidad_revisiones_pedidas", { p_solo_pendientes: true }).then(({ data }) => {
        (Array.isArray(data) ? (data as { persona_id: string }[]) : [])
          .forEach((r) => agregar(r.persona_id, "Revisión de ruta pedida"));
      }),
    );
  }

  if (puedeGestionarContratos(rol)) {
    tareas.push(
      supabase.rpc("fn_contrato_revisiones_pedidas", { p_solo_pendientes: true }).then(({ data }) => {
        (Array.isArray(data) ? (data as { persona_id: string }[]) : [])
          .forEach((r) => agregar(r.persona_id, "Revisión de contrato pedida"));
      }),
    );
  }

  await Promise.all(tareas);
  return mapa;
}

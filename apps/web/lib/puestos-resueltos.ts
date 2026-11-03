// ============================================================================
// puestos-resueltos.ts — dónde trabaja cada quien cada día, ya resuelto (0588)
// ============================================================================
// PROMETE: leer el plan de piso/almacén de un rango de días con la regla única
//          de la base, `fn_puestos_resueltos` (0588): el plan del día manda; si
//          no hay, su puesto base; si no, piso (sin filas). Devuelve la misma
//          forma que las filas de `puestos_planificados`, más `origen`.
// ASUME:   un cliente de Supabase con la sesión de quien mira (panel, «Lo mío» o
//          terminal). La función lee con las políticas de cada quien, así que
//          cada uno ve lo mismo que ya veía en la tabla.
// RESPALDO: si la 0588 todavía no está pegada (la función no existe), lee la
//          tabla del día como antes, sin la base. El código puede llegar antes
//          que la migración sin romper nada.
// NUNCA:   leer `puestos_planificados` directo en otro sitio. Desde la 0588 una
//          fila «piso» (este día en piso aunque su base sea el almacén) no tiene
//          horas, y una lectura directa la tomaría por «todo el turno en almacén».
//          Por eso Turnos, «Mis turnos» y el terminal pasan todos por aquí.
// ============================================================================

export interface FilaPuesto {
  persona_id: string;
  fecha: string;
  /** null = todo el turno en almacén. */
  desde: string | null;
  hasta: string | null;
  /** 'dia' = lo planificado para ese día; 'base' = su puesto base. */
  origen: "dia" | "base";
}

interface Respuesta { data: unknown; error: { code?: string; message?: string } | null }
interface Consulta extends PromiseLike<Respuesta> {
  abortSignal(s: AbortSignal): Consulta;
  eq(k: string, v: string): Consulta;
  gte(k: string, v: string): Consulta;
  lte(k: string, v: string): Consulta;
}
interface ClientePuestos {
  rpc(fn: string, args: Record<string, unknown>): Consulta;
  from(tabla: string): { select(columnas: string): Consulta };
}

/** La función no existe todavía (PostgREST o Postgres): es el caso «la 0588 no está pegada». */
export const esFuncionInexistente = (e: { code?: string } | null): boolean =>
  e !== null && (e.code === "PGRST202" || e.code === "42883");

/**
 * Lee el plan resuelto entre `desde` y `hasta` (fechas de Lima, ISO). Devuelve
 * `{ data, error }` como cualquier lectura de Supabase, para poder ir dentro de
 * un `Promise.all`. Con `personaId`, solo las filas de esa persona.
 */
export async function leerPuestosResueltos(
  cliente: unknown,
  desde: string,
  hasta: string,
  opciones: { personaId?: string; senal?: AbortSignal } = {},
): Promise<{ data: FilaPuesto[] | null; error: Respuesta["error"] }> {
  const sb = cliente as ClientePuestos;
  const conSenal = (c: Consulta) => (opciones.senal ? c.abortSignal(opciones.senal) : c);
  const deEsa = (filas: FilaPuesto[]) =>
    opciones.personaId ? filas.filter((f) => f.persona_id === opciones.personaId) : filas;

  const r = await conSenal(sb.rpc("fn_puestos_resueltos", { p_desde: desde, p_hasta: hasta }));
  if (!r.error) return { data: deEsa(((r.data as FilaPuesto[] | null) ?? []).map(normalizar)), error: null };
  if (!esFuncionInexistente(r.error)) return { data: null, error: r.error };

  // Respaldo: la tabla del día, como antes de la 0588 (todavía no hay filas «piso» ni base).
  let q = sb.from("puestos_planificados").select("persona_id, fecha, desde, hasta").gte("fecha", desde).lte("fecha", hasta);
  if (opciones.personaId) q = q.eq("persona_id", opciones.personaId);
  const t = await conSenal(q);
  if (t.error) return { data: null, error: t.error };
  return {
    data: deEsa(((t.data as Omit<FilaPuesto, "origen">[] | null) ?? []).map((f) => normalizar({ ...f, origen: "dia" }))),
    error: null,
  };
}

const normalizar = (f: FilaPuesto): FilaPuesto => ({
  persona_id: f.persona_id,
  fecha: f.fecha,
  desde: f.desde ?? null,
  hasta: f.hasta ?? null,
  origen: f.origen === "base" ? "base" : "dia",
});

export interface PeriodoBase { vigente_desde: string; vigente_hasta: string | null }

/** ¿Su puesto base es el almacén ese día? La misma pregunta que fn_puesto_base_es_almacen (0588). */
export function baseEsAlmacen(periodos: readonly PeriodoBase[], fecha: string): boolean {
  return periodos.some((p) => p.vigente_desde <= fecha && (p.vigente_hasta === null || p.vigente_hasta >= fecha));
}

/** Desde cuándo rige la base que cubre ese día (para decirlo en pantalla), o null si ese día su base es piso. */
export function baseVigenteDesde(periodos: readonly PeriodoBase[], fecha: string): string | null {
  const p = periodos.find((x) => x.vigente_desde <= fecha && (x.vigente_hasta === null || x.vigente_hasta >= fecha));
  return p ? p.vigente_desde : null;
}

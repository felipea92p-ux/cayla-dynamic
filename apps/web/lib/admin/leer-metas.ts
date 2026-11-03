// ============================================================================
// leer-metas.ts — leer la meta de cobertura de una sede en un rango de fechas
// ============================================================================
// PROMETE: devolver las filas de `fn_metas_cobertura` (0590): para cada fecha,
//          los rangos de hora que rigen, ya resueltos en la base (la excepción
//          más corta o la predeterminada).
// RESPALDO: si la 0590 todavía no está pegada (la función no existe), arma las
//          mismas filas desde `metas_cobertura` (0039) igual que la siembra de la
//          0590: mañana [00:00, 14:15), tarde [14:15, 24:00), líderes en los dos,
//          y el 0 viejo como «sin meta». Así el código puede llegar antes que la
//          migración sin que cambie nada en pantalla.
// NUNCA:   leer `metas_cobertura` en otro sitio para decidir una meta: desde la
//          0590 está vieja en cuanto alguien cambia una meta.
// ============================================================================
import { esFuncionInexistente } from "@/lib/puestos-resueltos";
import type { FilaMeta } from "./metas-cobertura";

interface Respuesta { data: unknown; error: { code?: string; message: string } | null }
interface Consulta extends PromiseLike<Respuesta> { eq(k: string, v: string): Consulta; in(k: string, v: string[]): Consulta }
interface ClienteMetas {
  rpc(fn: string, args: Record<string, unknown>): PromiseLike<Respuesta>;
  from(tabla: string): { select(columnas: string): Consulta };
}

interface FilaVieja { sede_id: string; dia_semana: number; meta: number | null; meta_tarde: number | null; meta_encargadas: number | null }

const CORTE_MIN = 855; // 14:15

const sumarDias = (iso: string, n: number) => {
  const d = new Date(`${iso}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
};
/** 0 = domingo … 6 = sábado, como metas_cobertura y la pantalla. */
const dowDe = (iso: string) => new Date(`${iso}T12:00:00Z`).getUTCDay();

/** Las filas viejas (0039) de una sede → las filas de fn_metas_cobertura, fecha por fecha. Lo mismo que siembra la 0590. */
export function filasDesdeMetaVieja(viejas: readonly FilaVieja[], desde: string, hasta: string): FilaMeta[] {
  const porDia = new Map(viejas.map((v) => [v.dia_semana, v]));
  const filas: FilaMeta[] = [];
  for (let f = desde; f <= hasta; f = sumarDias(f, 1)) {
    const v = porDia.get(dowDe(f));
    if (!v) continue;
    const lideres = v.meta_encargadas && v.meta_encargadas > 0 ? v.meta_encargadas : null;
    const tramos: [number, number, number | null][] = [[0, CORTE_MIN, v.meta], [CORTE_MIN, 1440, v.meta_tarde]];
    for (const [d, h, n] of tramos) {
      const personal = n && n > 0 ? n : null;
      if (personal === null && lideres === null) continue;
      filas.push({
        fecha: f, desde_min: d, hasta_min: h, personal, lideres,
        periodo_id: `vieja-${v.sede_id}`, periodo_nombre: "Predeterminada", es_predeterminada: true,
      });
    }
  }
  return filas;
}

/**
 * La meta de una sede entre `desde` y `hasta` (fechas de Lima, ISO), con la
 * forma `{ data, error }` de cualquier lectura de Supabase.
 */
export async function leerMetasDeCobertura(
  cliente: unknown,
  sedeId: string,
  desde: string,
  hasta: string,
): Promise<{ data: FilaMeta[] | null; error: Respuesta["error"] }> {
  const sb = cliente as ClienteMetas;
  const r = await sb.rpc("fn_metas_cobertura", { p_sede_id: sedeId, p_desde: desde, p_hasta: hasta });
  if (!r.error) return { data: (r.data as FilaMeta[] | null) ?? [], error: null };
  if (!esFuncionInexistente(r.error)) return { data: null, error: r.error };
  const t = await sb.from("metas_cobertura").select("sede_id, dia_semana, meta, meta_tarde, meta_encargadas").eq("sede_id", sedeId);
  if (t.error) return { data: null, error: t.error };
  return { data: filasDesdeMetaVieja((t.data as FilaVieja[] | null) ?? [], desde, hasta), error: null };
}

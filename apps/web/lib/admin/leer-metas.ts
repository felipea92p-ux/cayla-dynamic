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
import { lideresDelDia, mananaTarde, metasPorSedeYFecha, type FilaMeta } from "./metas-cobertura";

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

/** Las filas viejas (0039) → las filas de fn_metas_cobertura, sede por sede y fecha por fecha. Lo mismo que siembra la 0590. */
export function filasDesdeMetaVieja(viejas: readonly FilaVieja[], desde: string, hasta: string): FilaMeta[] {
  const porSedeYDia = new Map(viejas.map((v) => [`${v.sede_id}|${v.dia_semana}`, v]));
  const sedes = [...new Set(viejas.map((v) => v.sede_id))];
  const filas: FilaMeta[] = [];
  for (const sede of sedes) for (let f = desde; f <= hasta; f = sumarDias(f, 1)) {
    const v = porSedeYDia.get(`${sede}|${dowDe(f)}`);
    if (!v) continue;
    const lideres = v.meta_encargadas && v.meta_encargadas > 0 ? v.meta_encargadas : null;
    const tramos: [number, number, number | null][] = [[0, CORTE_MIN, v.meta], [CORTE_MIN, 1440, v.meta_tarde]];
    for (const [d, h, n] of tramos) {
      const personal = n && n > 0 ? n : null;
      if (personal === null && lideres === null) continue;
      filas.push({
        sede_id: v.sede_id, fecha: f, desde_min: d, hasta_min: h, personal, lideres,
        periodo_id: `vieja-${v.sede_id}`, periodo_nombre: "Predeterminada", es_predeterminada: true,
      });
    }
  }
  return filas;
}

/**
 * La meta de una sede (o de todas las que se pueden ver, con `sedeId` null)
 * entre `desde` y `hasta` (fechas de Lima, ISO), con la forma `{ data, error }`
 * de cualquier lectura de Supabase.
 */
export async function leerMetasDeCobertura(
  cliente: unknown,
  sedeId: string | null,
  desde: string,
  hasta: string,
): Promise<{ data: FilaMeta[] | null; error: Respuesta["error"] }> {
  const sb = cliente as ClienteMetas;
  const r = await sb.rpc("fn_metas_cobertura", { p_sede_id: sedeId, p_desde: desde, p_hasta: hasta });
  if (!r.error) return { data: (r.data as FilaMeta[] | null) ?? [], error: null };
  if (!esFuncionInexistente(r.error)) return { data: null, error: r.error };
  const q = sb.from("metas_cobertura").select("sede_id, dia_semana, meta, meta_tarde, meta_encargadas");
  const t = await (sedeId ? q.eq("sede_id", sedeId) : q);
  if (t.error) return { data: null, error: t.error };
  return { data: filasDesdeMetaVieja((t.data as FilaVieja[] | null) ?? [], desde, hasta), error: null };
}

/**
 * La meta de cada sede en UNA fecha, dicha como la decía la 0039 —mañana, tarde y
 * líderes—, para las pantallas que todavía cuentan así (Dashboard, Reporte de
 * sede). El mayor personal de los rangos de cada lado de las 14:15.
 */
export function metasComoAntes(filas: readonly FilaMeta[]): { sede_id: string; meta: number; meta_tarde: number; meta_encargadas: number }[] {
  return [...metasPorSedeYFecha(filas)].flatMap(([sede, porFecha]) =>
    [...porFecha.values()].slice(0, 1).map((d) => {
      const mt = mananaTarde(d.rangos);
      return { sede_id: sede, meta: mt.manana, meta_tarde: mt.tarde, meta_encargadas: mt.lideres };
    }));
}

/** Los líderes que pide cada sede cada fecha (solo donde pide alguno), para Incidencias. */
export function lideresPorSedeYFecha(filas: readonly FilaMeta[]): { sede_id: string; fecha: string; dia_semana: number; meta_encargadas: number }[] {
  return [...metasPorSedeYFecha(filas)].flatMap(([sede, porFecha]) =>
    [...porFecha.values()].flatMap((d) => {
      const n = lideresDelDia(d.rangos);
      return n > 0 ? [{ sede_id: sede, fecha: d.fecha, dia_semana: dowDe(d.fecha), meta_encargadas: n }] : [];
    }));
}

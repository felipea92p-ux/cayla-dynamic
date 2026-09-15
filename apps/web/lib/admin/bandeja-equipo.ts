import type { ClienteCayla } from "@cayla-dynamic/database";
import { contarPendientesBandeja, pendientesPorPersona, traerFuentesBandeja } from "./bandeja-fuentes";

/**
 * Los dos números de la Bandeja del panel que viven FUERA de su pantalla: el
 * bolito rojo del ítem «Bandeja» del menú (nav.tsx) y el aviso «N pendientes»
 * de cada persona en Equipo (0428).
 *
 * Hasta el 2026-09-15 cada uno repetía su propia lista de RPC, y las dos se
 * habían separado de la pantalla: el menú no sumaba las liquidaciones vencidas
 * y Equipo contaba Educación con la consulta anterior a la 0450. Ahora los dos
 * piden las fuentes a `traerFuentesBandeja` y cuentan sobre `armarPendientes`
 * — la misma lista que pinta `/admin/bandeja` —, así que una fuente nueva entra
 * a los tres lugares o a ninguno.
 *
 * Falla en silencio por sección, como el resto de los contadores del menú: una
 * RPC que falla resta esa sección en vez de tumbar el número entero.
 */
export async function contarBandejaEquipoPendiente(
  supabase: ClienteCayla,
  rol: string | null | undefined,
): Promise<number> {
  return contarPendientesBandeja(await traerFuentesBandeja(supabase, rol));
}

export async function listarPendientesPorPersona(
  supabase: ClienteCayla,
  rol: string | null | undefined,
): Promise<Map<string, string[]>> {
  return pendientesPorPersona(await traerFuentesBandeja(supabase, rol));
}

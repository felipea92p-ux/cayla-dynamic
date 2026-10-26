import type { ClienteCayla } from "@cayla-dynamic/database";
import { ROLES_DO } from "@cayla-dynamic/shared";
import {
  cuentaDeLaBandeja, pendientesPorPersona, traerFuentesBandeja,
  type CuentaBandeja, type FuentesBandeja,
} from "./bandeja-fuentes";

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
 *
 * Normas (0460) es la excepción a propósito: no vive en `traerFuentesBandeja`
 * porque no es un pendiente que se resuelva «aquí» ni «afuera» persona por
 * persona — es un resumen agregado («N constancias pendientes»)
 * que no encaja en la forma `Pendiente`. Se pide aparte, en paralelo, y entra
 * a la cuenta como UNA señal (`cuentaDeLaBandeja`), no una por constancia.
 *
 * El menú y el indicador del Dashboard piden por `traerFuentesYNormas` y cuentan
 * con `cuentaDeLaBandeja`: el camino y la cuenta son uno solo, así que no
 * pueden dar números distintos (2026-10-25: daban 96 y 92 para lo mismo).
 */

/** Solo DO gestiona Normas (publica, ve «Versiones» y «Constancias») — la
 *  encargada de sede no. No hay un `puedeGestionarNormas` en `permisos.ts`
 *  porque la pantalla misma nunca lo necesitó como función: comparaba
 *  `ROLES_DO.includes(rol)` directo. Se repite acá esa misma comparación en
 *  vez de inventar un permiso nuevo para un solo llamador. */
function rolEsDo(rol: string | null | undefined): boolean {
  return rol != null && ROLES_DO.includes(rol);
}

/** Lo que trae `fn_documentos_vigentes`, en lo que a las constancias pendientes importa. */
interface FilaDocumentoVigenteBandeja {
  requiere_acuse: boolean | null;
  poblacion: number | null;
  total_acuses: number | null;
}

/** Cuántas constancias faltan, sumadas sobre todos los tipos que la piden.
 *  Una sola definición para el contador y para el resumen compacto de abajo —
 *  dos copias de «qué cuenta» es cómo el número deja de corresponder a lo que
 *  se enlaza. */
function pendientesDeNormas(data: unknown): number {
  const filas = (data as unknown as FilaDocumentoVigenteBandeja[] | null) ?? [];
  return filas
    .filter((f) => f.requiere_acuse)
    .reduce((s, f) => s + ((f.poblacion ?? 0) - (f.total_acuses ?? 0)), 0);
}

/** Las fuentes de la Bandeja más las constancias de Normas sin recoger (solo DO las ve; para el resto, 0). */
export async function traerFuentesYNormas(
  supabase: ClienteCayla,
  rol: string | null | undefined,
): Promise<{ fuentes: FuentesBandeja; constanciasNormas: number }> {
  const [fuentes, constanciasNormas] = await Promise.all([
    traerFuentesBandeja(supabase, rol),
    rolEsDo(rol)
      ? supabase.rpc("fn_documentos_vigentes").then(({ data }) => pendientesDeNormas(data))
      : Promise.resolve(0),
  ]);
  return { fuentes, constanciasNormas };
}

/** Sin nada pendiente: el valor inicial del bolito antes de que llegue la primera cuenta. */
export const CUENTA_VACIA: CuentaBandeja = { tareas: 0, sistema: 0, normas: 0, total: 0 };

/**
 * La cuenta COMPLETA de la Bandeja (filas, señal de correo, señal de Normas),
 * no solo el total: el menú la usa para explicar en su `title` de dónde sale el
 * número. Ver `cuentaDeLaBandeja` para qué cuenta y cuánto pesa cada cosa.
 */
export async function cuentaBandejaEquipo(
  supabase: ClienteCayla,
  rol: string | null | undefined,
): Promise<CuentaBandeja> {
  const { fuentes, constanciasNormas } = await traerFuentesYNormas(supabase, rol);
  return cuentaDeLaBandeja(fuentes, constanciasNormas);
}

/** El bolito del ítem «Bandeja» del menú: solo el total de `cuentaBandejaEquipo`. */
export async function contarBandejaEquipoPendiente(
  supabase: ClienteCayla,
  rol: string | null | undefined,
): Promise<number> {
  return (await cuentaBandejaEquipo(supabase, rol)).total;
}

export async function listarPendientesPorPersona(
  supabase: ClienteCayla,
  rol: string | null | undefined,
): Promise<Map<string, string[]>> {
  return pendientesPorPersona(await traerFuentesBandeja(supabase, rol));
}

/** El enlace compacto de Normas para la Bandeja de equipo — «Normas: N
 *  constancias pendientes → Ver en Normas», o `null` cuando no
 *  hay nada pendiente (nunca un enlace a una lista vacía) o cuando quien
 *  pregunta no es DO. Vive separado de `contarBandejaEquipoPendiente` —que
 *  ya suma lo mismo para el bolito del menú— porque acá hace falta el TEXTO
 *  y el DESTINO, no solo el número; una sola RPC (`fn_documentos_vigentes`)
 *  sostiene a los dos, así que no hay una segunda fuente de datos. */
export interface ResumenNormas {
  texto: string;
  href: string;
}

export async function resumenNormasPendientes(
  supabase: ClienteCayla,
  rol: string | null | undefined,
): Promise<ResumenNormas | null> {
  if (!rolEsDo(rol)) return null;
  const { data } = await supabase.rpc("fn_documentos_vigentes");
  const n = pendientesDeNormas(data);
  if (n === 0) return null;
  return {
    // Constancias, no personas: `pendientesDeNormas` suma (población − acuses) por
    // documento, o sea pares persona-documento. Una persona con cuatro documentos
    // sin recoger es «4 constancias», no «4 personas».
    texto: `Normas: ${n} ${n === 1 ? "constancia pendiente" : "constancias pendientes"}`,
    href: "/admin/normas?tab=constancias",
  };
}

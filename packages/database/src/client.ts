import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "./types";

/**
 * Sesiones SEPARADAS por superficie: el terminal de marcaje y el panel admin
 * guardan su sesión bajo claves distintas de localStorage. Así, si una
 * supervisora entra al panel desde la Mac mini de su sede, NO desconecta la
 * sesión del terminal de marcaje (y viceversa).
 *
 * Todas las pantallas de este MVP son "use client" con sesión en localStorage,
 * así que no se necesita el manejo de cookies SSR de @supabase/ssr.
 */

const clientes: Partial<Record<string, SupabaseClient<Database>>> = {};

function crearClienteConAlmacen(storageKey: string): SupabaseClient<Database> {
  if (!clientes[storageKey]) {
    clientes[storageKey] = createClient<Database>(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      { auth: { storageKey } },
    );
  }
  return clientes[storageKey]!;
}

/** Cliente del TERMINAL de marcaje (sesión persistente del dispositivo fijo de la sede). */
export function createTerminalSupabaseClient(): SupabaseClient<Database> {
  return crearClienteConAlmacen("cayla-auth-terminal");
}

/** Cliente del PANEL DE ADMINISTRACIÓN (sesión personal de admin/supervisor). */
export function createAdminSupabaseClient(): SupabaseClient<Database> {
  return crearClienteConAlmacen("cayla-auth-admin");
}

/**
 * Cliente con llave ANÓNIMA para las rutas de servidor. Sirve para los caminos
 * públicos de Auth —`/recover` es el caso— que la llave de servicio distorsiona:
 * pedirlos firmando como quien se salta las RLS no es lo mismo que pedirlos como
 * los pide el navegador en «Olvidé mi clave», y lo que se quiere es exactamente
 * eso, el mismo correo por el mismo camino.
 *
 * No usa `crearClienteConAlmacen`: aquel guarda sesión bajo una clave de
 * `localStorage`, que en el servidor no existe y además convertiría el cliente
 * en un singleton compartido entre peticiones de personas distintas.
 */
export function createAnonClient(): SupabaseClient<Database> | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const llave = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !llave) return null;
  return createClient<Database>(url, llave, { auth: { persistSession: false } });
}

/**
 * Cliente con llave de servicio — SOLO para las rutas de servidor
 * (`app/api/*`). Nunca importar desde código que corre en el navegador: la
 * llave de servicio se salta RLS por completo.
 *
 * Lee `NEXT_PUBLIC_SUPABASE_URL` y no `SUPABASE_URL`: en Vercel solo existe la
 * primera. Hasta agosto de 2026 esta función leía la segunda y era, por eso,
 * una trampa — nadie la llamaba (las tres rutas armaban su propio cliente a
 * mano), y la primera que lo hubiera hecho habría reventado en producción con
 * un error de URL indefinida.
 *
 * Devuelve `null` en vez de lanzar cuando falta configuración, para que la ruta
 * responda "servidor sin configurar" con su propio código de estado en lugar de
 * caerse con un 500 sin explicación.
 */
export function createServiceRoleClient(): SupabaseClient<Database> | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const llave = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !llave) return null;
  return createClient<Database>(url, llave, { auth: { persistSession: false } });
}

/**
 * Cliente con llave anónima que actúa COMO LA PERSONA que hizo la petición, a
 * partir del token que ella misma mandó en la cabecera `Authorization`.
 *
 * Existe porque una ruta de servidor tiene dos maneras muy distintas de
 * escribir, y hasta ahora solo tenía la primera:
 *
 *   - con `createServiceRoleClient()` escribe como `service_role`, que se
 *     salta las RLS y, sobre todo, NO ES NADIE: dentro de la base `auth.uid()`
 *     es null, así que ninguna función puede saber quién pidió el cambio ni
 *     dejarlo anotado.
 *   - con este cliente escribe como quien pulsó el botón, y entonces los
 *     guards `SECURITY DEFINER` del repositorio funcionan igual que cuando la
 *     llamada viene del navegador — incluida la fila de `correcciones_auditoria`
 *     que varias de ellas insertan con `fn_persona_actual_id()`.
 *
 * Se usa cuando la ruta necesita lo segundo: que la base identifique a la
 * persona. Para lo que de verdad tiene que saltarse las RLS (leer el padrón
 * entero, hablar con Auth) sigue estando la llave de servicio.
 *
 * El token va en `global.headers` y no por `setSession`: el cliente se crea
 * nuevo en cada petición y no persiste sesión, así que no hay forma de que la
 * sesión de una persona se filtre a la petición de otra.
 */
export function createUserClient(token: string): SupabaseClient<Database> | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const llave = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !llave || !token) return null;
  return createClient<Database>(url, llave, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
}

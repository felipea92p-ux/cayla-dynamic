import { createAdminSupabaseClient } from "@cayla-dynamic/database";

// ============================================================================
// La única puerta por la que alguien se cambia su propia clave
// ============================================================================
// Vive acá y no repetida en cada pantalla por lo de siempre: hay tres sitios
// donde una persona pone su clave —la invitación, «olvidé mi clave» y Mi cuenta
// dentro del panel— y los tres tienen que hacer exactamente lo mismo. Antes los
// tres llamaban por su cuenta a `supabase.auth.updateUser({ password })`, con
// su propia comprobación de largo escrita a mano, y ninguno apagaba la marca de
// «hay que cambiarla».
// ============================================================================

/** ¿Esta sesión trae la marca de «tienes que cambiar tu clave»? */
export function clavePorCambiar(usuario: { app_metadata?: Record<string, unknown> } | null | undefined): boolean {
  return usuario?.app_metadata?.clave_por_cambiar === true;
}

/**
 * Guarda la clave nueva. Devuelve `null` si salió bien, o el texto del problema.
 *
 * Refresca la sesión al terminar, y eso no es un detalle: la marca vive en el
 * token, así que sin refrescar el navegador seguiría creyendo que hay que
 * cambiar la clave que se acaba de cambiar — y el guardia del panel devolvería
 * a la persona a esta misma pantalla, en bucle.
 */
export async function guardarMiClave(clave: string): Promise<string | null> {
  const supabase = createAdminSupabaseClient();
  const { data: sesion } = await supabase.auth.getSession();
  const token = sesion.session?.access_token;
  if (!token) return "Tu sesión venció. Vuelve a entrar y prueba otra vez.";

  let res: Response;
  try {
    res = await fetch("/api/mi-clave", {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
      body: JSON.stringify({ password: clave }),
    });
  } catch {
    // Todo falla, todo el tiempo. Sin red no se cambió nada, y decirlo así evita
    // que alguien se quede pensando si su clave vieja sigue sirviendo: sí sirve.
    return "No se pudo hablar con el servidor. Tu clave anterior sigue funcionando; inténtalo de nuevo.";
  }

  const datos = await res.json().catch(() => ({}));
  if (!res.ok) return datos.error ?? "No se pudo guardar la clave.";

  await supabase.auth.refreshSession();
  return null;
}

/**
 * Anota que la clave con la que esta persona ACABA de entrar no cumple la
 * política, para que el panel la lleve a cambiarla.
 *
 * El login es el único momento en que el sistema ve una clave en claro —lo que
 * guarda Supabase es un hash, y de un hash no se puede juzgar nada—, así que es
 * el único momento en que esto se puede saber de las claves que ya existían.
 *
 * Falla en silencio a propósito: si esto no sale, lo peor que pasa es que a
 * alguien no se le pida cambiar su clave floja hoy. Bloquear el login por ello
 * sería dejar sin panel a la sede por un problema de anotación.
 */
export async function marcarMiClavePorCambiar(token: string): Promise<void> {
  try {
    await fetch("/api/mi-clave", {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
      body: JSON.stringify({ accion: "marcar" }),
    });
  } catch {
    /* ver arriba */
  }
}

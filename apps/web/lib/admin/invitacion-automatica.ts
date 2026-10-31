import { createAdminSupabaseClient } from "@cayla-dynamic/database";

/**
 * Le avisa al servidor «acabo de guardar un correo»: si con eso alguien quedó
 * lista para su invitación, se le manda ahí mismo —una sola vez en su vida, lo
 * garantiza la 0572—. Devuelve a quién le salió, para que la pantalla lo diga.
 *
 * Nunca falla hacia afuera: si el servidor no responde, el correo ya quedó
 * guardado en la ficha y la invitación sale la próxima vez que alguien abra
 * Cuentas, que vuelve a mirar lo mismo. Un error acá no puede deshacer ni
 * ensuciar el «Ficha guardada» que ya se mostró.
 */
export async function pedirInvitacionesAutomaticas(): Promise<{ nombre: string; correo: string }[]> {
  try {
    const { data } = await createAdminSupabaseClient().auth.getSession();
    const token = data.session?.access_token;
    if (!token) return [];
    const res = await fetch("/api/admin/cuentas", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
      body: JSON.stringify({ accion: "invitar-automatico" }),
    });
    if (!res.ok) return [];
    const cuerpo = await res.json().catch(() => ({}));
    return Array.isArray(cuerpo?.enviadas) ? cuerpo.enviadas : [];
  } catch {
    return [];
  }
}

export function textoInvitacionesEnviadas(enviadas: { nombre: string; correo: string }[]): string {
  return `Le llegó a ${enviadas.map((e) => `${e.nombre} (${e.correo})`).join(", ")} la invitación para crear su cuenta. Sale una sola vez.`;
}

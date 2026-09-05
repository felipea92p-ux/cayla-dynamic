import { createServiceRoleClient } from "@cayla-dynamic/database";
import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { problemasDeClave } from "@cayla-dynamic/shared";

// ============================================================================
// Cambiar MI PROPIA clave — y apagar la marca de «hay que cambiarla»
// ============================================================================
//
// QUÉ PROMETE
//   Que quien tiene sesión pueda ponerse una clave nueva, que esa clave cumpla
//   la política de la casa, y que en el mismo movimiento deje de estar marcada
//   como «hay que cambiarla». Las tres cosas o ninguna.
//
// QUÉ ASUME
//   Que `app_metadata.clave_por_cambiar` solo lo escribe el servidor. Es la
//   razón de que la marca viva en `app_metadata` y no en `user_metadata`:
//   `supabase.auth.updateUser({ data })` deja a cualquiera escribir su propio
//   `user_metadata` desde el navegador, así que una marca ahí la apagaría la
//   persona sin cambiar nada. `app_metadata` solo se toca con la llave de
//   servicio, que vive acá.
//
// POR QUÉ ESTO NO SE HACE EN EL NAVEGADOR, que era como estaba
//   Las pantallas llamaban a `supabase.auth.updateUser({ password })` directo.
//   Eso funciona, pero deja dos cosas fuera:
//     · La política. El navegador puede comprobarla y la comprueba, pero una
//       comprobación que solo vive en el navegador es una sugerencia.
//     · La marca. Cambiar la clave y apagar la marca son dos escrituras, y solo
//       la llave de servicio puede hacer la segunda. Separadas, la persona
//       cambiaba su clave y el sistema seguía empujándola a cambiarla.
//
// CÓMO SE DEGRADA SI SUPABASE NO RESPONDE
//   No hace nada y lo dice. No hay estado a medias que dejar: es una sola
//   llamada a `updateUserById`, que escribe la clave y el `app_metadata` juntos.
//   La persona sigue entrando con la clave vieja, que es el respaldo correcto.
// ============================================================================

/** Qué marca lleva quien todavía no eligió su clave. Un solo nombre, dos motivos:
 *  una clave temporal que le dictaron, o una que no cumple la política. */
export const MARCA_CLAVE_POR_CAMBIAR = "clave_por_cambiar";

export async function POST(req: Request) {
  const admin = createServiceRoleClient();
  if (!admin) return NextResponse.json({ error: "servidor sin configurar" }, { status: 500 });

  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) return NextResponse.json({ error: "sin sesión" }, { status: 401 });
  const { data: userData, error: ue } = await admin.auth.getUser(token);
  if (ue || !userData.user) return NextResponse.json({ error: "sesión inválida" }, { status: 401 });
  const usuario = userData.user;

  const body = await req.json().catch(() => ({}));
  const accion = body?.accion ?? "cambiar";

  // ── Marcar la propia cuenta como «hay que cambiar la clave» ──────────────
  //
  // La llama el login cuando la clave con la que alguien ACABA de entrar no
  // cumple la política. Es el único momento en que el sistema ve una clave en
  // claro, así que es el único momento en que puede saberlo — Supabase guarda
  // el hash, y desde el hash no se puede juzgar nada.
  //
  // No recibe la clave: recibirla sería mandar una contraseña por la red sin
  // ninguna necesidad. El navegador ya sabe juzgar (misma función, mismo
  // archivo) y acá solo se anota la conclusión. Y anotar de más no abre nada:
  // lo peor que consigue quien mienta es que le pidan cambiar su propia clave.
  if (accion === "marcar") {
    const { error } = await admin.auth.admin.updateUserById(usuario.id, {
      app_metadata: { [MARCA_CLAVE_POR_CAMBIAR]: true },
    });
    if (error) {
      Sentry.captureException(error);
      return NextResponse.json({ error: "no se pudo anotar" }, { status: 500 });
    }
    return NextResponse.json({ ok: true });
  }

  const clave = String(body?.password ?? "");
  // El correo entra en el juicio: `felipe@…` con clave `Felipe2026x` no es una
  // clave, es el nombre de la puerta escrito en la llave.
  const problemas = problemasDeClave(clave, usuario.email);
  if (problemas.length > 0) {
    return NextResponse.json({ error: problemas.join(" "), problemas }, { status: 400 });
  }

  // Las dos escrituras van juntas en una sola llamada a propósito: si la clave
  // se cambiara y la marca se quedara puesta, la persona quedaría en un bucle
  // —cambia su clave, el sistema la manda a cambiarla otra vez— sin nada que
  // pudiera hacer al respecto.
  const { error } = await admin.auth.admin.updateUserById(usuario.id, {
    password: clave,
    app_metadata: { [MARCA_CLAVE_POR_CAMBIAR]: false },
  });
  if (error) {
    Sentry.captureException(error);
    // El más probable: la política de Supabase Auth es MÁS estricta que la
    // nuestra (alguien la subió en el panel y no acá). Decirlo así evita la
    // media hora de buscar el fallo en el sitio equivocado.
    const t = (error.message ?? "").toLowerCase();
    if (t.includes("password")) {
      return NextResponse.json(
        { error: "El sistema de acceso rechazó esa clave. Prueba con una más larga o menos previsible." },
        { status: 400 },
      );
    }
    return NextResponse.json({ error: "No se pudo guardar la clave. Vuelve a intentarlo." }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}

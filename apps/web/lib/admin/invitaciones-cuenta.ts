import type { createServiceRoleClient } from "@cayla-dynamic/database";
import * as Sentry from "@sentry/nextjs";
import { mensajeDeError } from "@/lib/admin/mensaje-error";

// Los correos de acceso a la cuenta: la invitación para elegir clave y el de
// «recuperar acceso». SOLO servidor —usa la llave de servicio—; lo llama
// `/api/admin/cuentas`.
//
// QUÉ PROMETE: a cada persona le llega como mucho UNA invitación automática en
// su vida (en cuanto su ficha tiene correo) y UNA manual por cada correo. Lo
// garantiza la base —los índices únicos de la 0572—, no este archivo: aquí solo
// se respeta el orden reservar → enviar → cerrar.
//
// QUÉ ASUME: que `invitaciones_cuenta` existe. Si no, no sale ningún correo: sin
// dónde reservar no hay forma de prometer «una sola vez», y mandar sin esa
// promesa es justo lo que se vino a evitar.

type Admin = NonNullable<ReturnType<typeof createServiceRoleClient>>;

export type Origen = "automatica" | "manual";
export type Tipo = "invitacion" | "recuperacion";

// Los errores de Supabase Auth no son de Postgres: no traen código SQL y llegan
// en inglés. Quien los lee acá es una admin de CAYLA, no una ingeniera, así que
// el más frecuente —el correo repetido, que sale cada vez que alguien intenta
// crear dos veces la misma cuenta— se dice en español. El resto se registra y
// se responde con algo honesto en vez de pegar el texto en inglés.
export function mensajeDeAuth(error: { message?: string; status?: number } | null | undefined): string {
  const t = (error?.message ?? "").toLowerCase();
  // El más probable cuando se reenvían muchas invitaciones de una pasada: el
  // proyecto tiene un tope de correos por hora. No es un fallo del envío ni un
  // problema de esa persona — es que hay que esperar y seguir con el resto.
  if (esTopeDeCorreos(error)) {
    return "Se llegó al tope de correos por hora del proyecto. Espera un rato y sigue con las que faltan; las ya enviadas no se pierden.";
  }
  if (t.includes("already been registered") || t.includes("already registered")) {
    return "Ese correo ya está registrado en otra cuenta. Usa otro, o revisa si esa persona ya tiene acceso.";
  }
  if (t.includes("password")) {
    return "La contraseña generada no cumple los requisitos del sistema de acceso. Vuelve a intentarlo.";
  }
  if (t.includes("invalid") && t.includes("email")) {
    return "Ese correo no tiene un formato válido.";
  }
  return "El sistema de acceso no pudo completar la operación. Vuelve a intentarlo; si sigue igual, avisa a Felipe.";
}

function esTopeDeCorreos(error: { message?: string; status?: number } | null | undefined): boolean {
  const t = (error?.message ?? "").toLowerCase();
  return error?.status === 429 || t.includes("rate limit") || t.includes("only request this after");
}

// Mismo criterio que `fn_set_email` y que el `check` de la 0572: el login no
// distingue mayúsculas, y dos formas de escribir el mismo buzón burlarían el
// «uno por correo».
export function normalizarCorreo(correo: string | null | undefined): string {
  return (correo ?? "").trim().toLowerCase();
}

/**
 * A quién se invita para que deje su constancia: integrantes activas, en
 * planilla o practicantes, sin cuenta. Es la ÚNICA definición —la usan la lista
 * de la pantalla y el envío automático—, así que no pueden contestar distinto.
 *
 * La Ley 30709 obliga a INFORMAR la política salarial a cada persona y a poder
 * probarlo, y `fn_acusar_politica_salarial` solo acepta el acuse de quien tiene
 * sesión propia: sin cuenta, no hay forma de que dejen constancia.
 *
 * NO se les promueve a encargada para lograrlo — eso les daría acceso al panel
 * de su sede. Con su rol de integrante el menú ya les muestra solo lo que les
 * corresponde (la política salarial va sin `roles` a propósito) y las RLS de
 * `asignaciones_salario` y `movimientos_planilla` siguen cerradas a
 * admin/líder: no ven sueldos de nadie, ni el suyo en planilla.
 *
 * También entra la practicante (`en_planilla` es falso para ella: no es
 * 'planilla' ni 'prueba'), aunque su motivo no sea la Ley 30709 — tiene horario
 * y marca en el terminal igual que cualquiera, así que necesita la misma cuenta
 * mínima para entrar a lo suyo. RxH y no_trabajador se quedan afuera a
 * propósito: a un locador no se le mide jornada (0191), y darle una cuenta de
 * este tipo sería la misma señal de subordinación que esa migración existe
 * para evitar.
 */
export async function invitablesSinCuenta(admin: Admin) {
  const { data, error } = await admin
    .from("personas")
    .select("id, nombres, apellidos, email, sedes:sede_base_id(codigo)")
    .eq("rol", "integrante")
    .eq("estado", "activo").eq("cuenta_de_servicio", false)
    .or("en_planilla.eq.true,tipo_vinculo.eq.practicante")
    .is("auth_user_id", null)
    .order("apellidos");
  if (error) throw error;
  return (data ?? []).map((p) => ({
    id: p.id,
    nombre: `${p.nombres} ${p.apellidos}`,
    sede: (p.sedes as { codigo?: string } | null)?.codigo ?? "?",
    email: p.email ?? null,
  }));
}

export interface Historial {
  // La automática que salió (o está saliendo). Nunca hay más de una.
  automatica: { correo: string; at: string } | null;
  // Por qué no salió la última automática, si su último intento falló.
  automaticaFallo: string | null;
  // Correos a los que ya se mandó la manual, con su fecha.
  manuales: Record<string, string>;
}

export async function historialDeInvitaciones(admin: Admin, personaIds: string[]): Promise<Record<string, Historial>> {
  const out: Record<string, Historial> = {};
  if (personaIds.length === 0) return out;
  const { data, error } = await admin
    .from("invitaciones_cuenta")
    .select("persona_id, correo, origen, estado, detalle, creada_at")
    .in("persona_id", personaIds)
    .order("creada_at");
  if (error) throw error;
  for (const f of data ?? []) {
    const h = (out[f.persona_id] ??= { automatica: null, automaticaFallo: null, manuales: {} });
    if (f.origen === "automatica") {
      // En orden de creación: un intento que funciona después de uno fallido
      // borra el fallo, y uno fallido después de nada lo deja dicho.
      if (f.estado === "fallida") h.automaticaFallo = f.detalle;
      else { h.automatica = { correo: f.correo, at: f.creada_at }; h.automaticaFallo = null; }
    } else if (f.estado !== "fallida") {
      h.manuales[f.correo] = f.creada_at;
    }
  }
  return out;
}

type Reserva = { ok: true; id: string } | { ok: false; yaEnviada: true } | { ok: false; yaEnviada: false; error: string };

// El compare-and-set. Si otro pedido ya reservó este envío —doble clic, dos
// pantallas guardando a la vez— el índice único de la 0572 lo rechaza con 23505
// y aquí se devuelve «ya enviada» sin haber mandado nada.
export async function reservarEnvio(
  admin: Admin,
  r: { personaId: string; correo: string; origen: Origen; tipo: Tipo; enviadaPor: string | null },
): Promise<Reserva> {
  const { data, error } = await admin
    .from("invitaciones_cuenta")
    .insert({ persona_id: r.personaId, correo: r.correo, origen: r.origen, tipo: r.tipo, enviada_por: r.enviadaPor })
    .select("id")
    .single();
  if (!error) return { ok: true, id: data.id };
  if (error.code === "23505") return { ok: false, yaEnviada: true };
  Sentry.captureException(error);
  // PGRST205 es «esa tabla no está en el esquema» dicho por PostgREST: la 0572
  // todavía no se pegó.
  if (error.code === "PGRST205" || error.code === "42P01") {
    return { ok: false, yaEnviada: false, error: "Falta pegar la migración 0572 en la base. Avisa a Felipe; hasta entonces no sale ningún correo de acceso." };
  }
  return { ok: false, yaEnviada: false, error: mensajeDeError(error, "anotar el envío") };
}

export async function cerrarEnvio(admin: Admin, id: string, resultado: { ok: true; nota?: string } | { ok: false; motivo: string }) {
  const { error } = await admin
    .from("invitaciones_cuenta")
    .update({
      estado: resultado.ok ? "enviada" : "fallida",
      detalle: resultado.ok ? resultado.nota ?? null : resultado.motivo,
      resuelta_at: new Date().toISOString(),
    })
    .eq("id", id);
  // Si esto falla el correo ya salió (o ya falló); la fila se queda en
  // 'reservada' y cuenta como enviada, que es lo prudente: no repetir.
  if (error) Sentry.captureException(error);
}

// Una reserva que lleva más de una hora abierta es de un envío que se murió a
// medias (la función de Vercel no dura tanto). Se da por fallida para que se
// pueda reintentar — mismo plazo que las alertas por correo (0362).
async function liberarReservasMuertas(admin: Admin) {
  const haceUnaHora = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const { error } = await admin
    .from("invitaciones_cuenta")
    .update({ estado: "fallida", detalle: "quedó a medias: el envío se cortó antes de confirmarse", resuelta_at: new Date().toISOString() })
    .eq("estado", "reservada")
    .lt("creada_at", haceUnaHora);
  if (error) Sentry.captureException(error);
}

export type ResultadoInvitacion =
  | { estado: "enviada"; correo: string }
  | { estado: "ya-enviada" }
  | { estado: "fallida"; error: string; tope: boolean };

/**
 * Manda la invitación para elegir clave a quien todavía no tiene cuenta, y le
 * enlaza la cuenta a su ficha. La usan el botón «Invitar» y el envío automático.
 *
 * Ella elige su propia clave: nadie más la conoce, ni siquiera quien invita —a
 * diferencia de `crear`, que devuelve la contraseña en pantalla—. Y el correo
 * llega a la dirección que la persona designó en su contrato como medio de
 * comunicación válido, que es el mismo criterio con el que se entrega el RIT.
 */
export async function invitarAPersona(
  admin: Admin,
  a: { personaId: string; correo: string; origen: Origen; enviadaPor: string | null; redirectTo: string },
): Promise<ResultadoInvitacion> {
  const reserva = await reservarEnvio(admin, { ...a, tipo: "invitacion" });
  if (!reserva.ok) return reserva.yaEnviada ? { estado: "ya-enviada" } : { estado: "fallida", error: reserva.error, tope: false };

  const { data: inv, error } = await admin.auth.admin.inviteUserByEmail(a.correo, { redirectTo: a.redirectTo });
  if (error) {
    Sentry.captureException(error);
    const motivo = mensajeDeAuth(error);
    await cerrarEnvio(admin, reserva.id, { ok: false, motivo });
    return { estado: "fallida", error: motivo, tope: esTopeDeCorreos(error) };
  }
  // El correo YA salió: pase lo que pase con el enlace, la fila se cierra como
  // enviada, porque la promesa es sobre correos y este llegó. Si el enlace
  // falla, el botón manual lo repara: Supabase reinvita al mismo usuario y lo
  // devuelve, y entonces se enlaza.
  const { error: e2 } = await admin
    .from("personas")
    .update({ auth_user_id: inv.user.id })
    .eq("id", a.personaId)
    .is("auth_user_id", null);
  if (e2) {
    Sentry.captureException(e2);
    await cerrarEnvio(admin, reserva.id, { ok: true, nota: "salió el correo, pero la cuenta no se enlazó con la ficha" });
    return { estado: "fallida", error: mensajeDeError(e2, "enlazar la cuenta con su ficha"), tope: false };
  }
  await cerrarEnvio(admin, reserva.id, { ok: true });
  return { estado: "enviada", correo: a.correo };
}

/**
 * El envío automático: a quien está para invitar, tiene correo y nunca recibió
 * su invitación automática, se la manda. Se llama cada vez que alguien guarda
 * un correo en una ficha (Datos personales, Equipo) y cada vez que se abre
 * Cuentas, así que el correo que entre por cualquier camino —también por el
 * SQL Editor— sale a más tardar la próxima vez que alguien mire esa pantalla.
 *
 * Va de a una, con una pausa, y corta al primer tope de correos por hora:
 * seguir solo sumaría fallos. Lo que no salió queda para el próximo llamado.
 */
export async function invitarAutomaticamente(admin: Admin, redirectTo: string) {
  await liberarReservasMuertas(admin);
  const invitables = await invitablesSinCuenta(admin);
  const conCorreo = invitables.filter((p) => normalizarCorreo(p.email).includes("@"));
  const historial = await historialDeInvitaciones(admin, conCorreo.map((p) => p.id));
  const enviadas: { nombre: string; correo: string }[] = [];
  const fallidas: { nombre: string; error: string }[] = [];
  for (const p of conCorreo) {
    if (historial[p.id]?.automatica) continue;
    if (enviadas.length + fallidas.length > 0) await new Promise((r) => setTimeout(r, 700));
    const correo = normalizarCorreo(p.email);
    const r = await invitarAPersona(admin, { personaId: p.id, correo, origen: "automatica", enviadaPor: null, redirectTo });
    if (r.estado === "enviada") enviadas.push({ nombre: p.nombre, correo });
    if (r.estado === "fallida") {
      fallidas.push({ nombre: p.nombre, error: r.error });
      if (r.tope) break;
    }
  }
  return { enviadas, fallidas };
}

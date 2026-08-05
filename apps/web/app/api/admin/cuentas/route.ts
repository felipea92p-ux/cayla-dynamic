import { createServiceRoleClient } from "@cayla-dynamic/database";
import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { puedeActuarSobre, puedeGestionarCatalogos, ROLES_CON_PANEL } from "@cayla-dynamic/shared";

// Gestión de cuentas del panel — SOLO admin/lider_do. Corre en el servidor con la
// llave de servicio; verifica que quien llama sea admin (por su sesión).
// Acciones: listar | resetear (contraseña de otro) | crear (cuenta de una persona).

// Estas claves son la única credencial de una cuenta del panel hasta que su dueña
// la cambia. `Math.random()` NO sirve para eso: no es criptográfico y su estado
// interno se puede reconstruir observando unas pocas salidas, así que quien viera
// una clave generada podría predecir las siguientes. `crypto.getRandomValues` sí
// es del sistema operativo.
//
// El bucle de descarte existe porque 256 no es múltiplo de 24 ni de 8: tomar el
// resto a secas haría que las primeras letras del alfabeto salieran más seguido.
// Se descartan los bytes de la cola incompleta y se pide otro.
function pick(set: string, n: number) {
  const limite = Math.floor(256 / set.length) * set.length;
  let out = "";
  while (out.length < n) {
    const bytes = new Uint8Array(n - out.length);
    globalThis.crypto.getRandomValues(bytes);
    for (const b of bytes) if (b < limite) out += set[b % set.length];
  }
  return out;
}

function generarClave() {
  const abc = "abcdefghijkmnpqrstuvwxyz", ABC = "ABCDEFGHJKLMNPQRSTUVWXYZ", num = "23456789";
  return `${pick(ABC, 1)}${pick(abc, 5)}-${pick(num, 4)}`;
}


async function emailsPorUsuario(admin: any): Promise<Record<string, string>> {
  const out: Record<string, string> = {};
  let page = 1;
  while (true) {
    const { data } = await admin.auth.admin.listUsers({ page, perPage: 200 });
    for (const u of data.users) out[u.id] = u.email ?? "";
    if (data.users.length < 200) break;
    page++;
  }
  return out;
}

// Los errores de Supabase Auth no son de Postgres: no traen código SQL y llegan
// en inglés. Quien los lee acá es una admin de CAYLA, no una ingeniera, así que
// el más frecuente —el correo repetido, que sale cada vez que alguien intenta
// crear dos veces la misma cuenta— se dice en español. El resto se registra y
// se responde con algo honesto en vez de pegar el texto en inglés.
function mensajeDeAuth(error: { message?: string } | null | undefined): string {
  const t = (error?.message ?? "").toLowerCase();
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

export async function POST(req: Request) {
  const admin = createServiceRoleClient();
  if (!admin) return NextResponse.json({ error: "servidor sin configurar" }, { status: 500 });

  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) return NextResponse.json({ error: "sin sesión" }, { status: 401 });
  const { data: userData, error: ue } = await admin.auth.getUser(token);
  if (ue || !userData.user) return NextResponse.json({ error: "sesión inválida" }, { status: 401 });
  const { data: yo } = await admin.from("personas").select("rol").eq("auth_user_id", userData.user.id).maybeSingle();
  if (!yo || !puedeGestionarCatalogos(yo.rol)) {
    return NextResponse.json({ error: "solo un administrador puede gestionar cuentas" }, { status: 403 });
  }

  const body = await req.json().catch(() => ({}));
  const { accion, personaId, email } = body;

  try {
    if (accion === "listar") {
      const { data: personas } = await admin
        .from("personas")
        .select("id, nombres, apellidos, rol, auth_user_id, sedes:sede_base_id(codigo)")
        .in("rol", [...ROLES_CON_PANEL])
        .eq("estado", "activo")
        .order("nombres");
      const emails = await emailsPorUsuario(admin);
      const cuentas = (personas ?? []).map((p: any) => ({
        id: p.id,
        nombre: `${p.nombres} ${p.apellidos}`,
        rol: p.rol,
        sede: p.sedes?.codigo ?? "?",
        email: p.auth_user_id ? emails[p.auth_user_id] ?? null : null,
        tieneCuenta: !!p.auth_user_id,
      }));
      // Integrantes que se pueden promover a encargada (para darles acceso al panel de su sede)
      const { data: integrantes } = await admin
        .from("personas")
        .select("id, nombres, apellidos, sedes:sede_base_id(codigo)")
        .eq("rol", "integrante")
        .eq("estado", "activo")
        .order("nombres");
      const promovibles = (integrantes ?? []).map((p: any) => ({
        id: p.id,
        nombre: `${p.nombres} ${p.apellidos}`,
        sede: p.sedes?.codigo ?? "?",
      }));
      return NextResponse.json({ cuentas, promovibles });
    }

    if (accion === "promover") {
      // Convierte a un integrante en encargada (supervisor_sede) de su sede.
      const { data: p } = await admin.from("personas").select("id, rol").eq("id", personaId).maybeSingle();
      if (!p) return NextResponse.json({ error: "persona no encontrada" }, { status: 404 });
      if (!puedeActuarSobre(yo.rol, p.rol)) {
        return NextResponse.json({ error: "no puedes cambiar el rol de esa persona" }, { status: 403 });
      }
      // El rol del objetivo se leía y no se usaba, así que "promover" servía
      // igual para DEGRADAR: con el id de un admin lo dejaba como encargada.
      // Esta acción solo sube a un integrante; cualquier otro cambio de rol es
      // otra operación y necesita su propia puerta.
      if (p.rol !== "integrante") {
        return NextResponse.json({ error: "solo se promueve a un integrante" }, { status: 409 });
      }
      const { error } = await admin.from("personas").update({ rol: "supervisor_sede" }).eq("id", personaId);
      if (error) {
        Sentry.captureException(error);
        return NextResponse.json({ error: mensajeDeError(error, "promover a esa persona") }, { status: 500 });
      }
      return NextResponse.json({ ok: true });
    }

    if (accion === "resetear") {
      const { data: p } = await admin.from("personas").select("auth_user_id, rol").eq("id", personaId).maybeSingle();
      if (!p) return NextResponse.json({ error: "persona no encontrada" }, { status: 404 });
      if (!puedeActuarSobre(yo.rol, p.rol)) {
        return NextResponse.json({ error: "no puedes resetear la contraseña de esa persona" }, { status: 403 });
      }
      if (!p.auth_user_id) return NextResponse.json({ error: "esa persona no tiene cuenta" }, { status: 409 });
      const nueva = generarClave();
      const { error } = await admin.auth.admin.updateUserById(p.auth_user_id, { password: nueva });
      if (error) {
        Sentry.captureException(error);
        return NextResponse.json({ error: mensajeDeAuth(error) }, { status: 500 });
      }
      return NextResponse.json({ password: nueva });
    }

    if (accion === "crear") {
      if (!email || !String(email).includes("@")) return NextResponse.json({ error: "correo inválido" }, { status: 400 });
      const { data: p } = await admin.from("personas").select("id, auth_user_id, rol").eq("id", personaId).maybeSingle();
      if (!p) return NextResponse.json({ error: "persona no encontrada" }, { status: 404 });
      // Crear la cuenta de alguien es elegir con qué correo entra: sin esta
      // comprobación, un líder DO podía darle al admin que aún no tiene cuenta
      // un correo suyo y entrar como admin.
      if (!puedeActuarSobre(yo.rol, p.rol)) {
        return NextResponse.json({ error: "no puedes crear la cuenta de esa persona" }, { status: 403 });
      }
      if (p.auth_user_id) return NextResponse.json({ error: "esa persona ya tiene cuenta" }, { status: 409 });
      const nueva = generarClave();
      const { data: authData, error } = await admin.auth.admin.createUser({ email, password: nueva, email_confirm: true });
      if (error) {
        Sentry.captureException(error);
        return NextResponse.json({ error: mensajeDeAuth(error) }, { status: 500 });
      }
      const { error: e2 } = await admin.from("personas").update({ auth_user_id: authData.user.id }).eq("id", personaId);
      if (e2) {
        Sentry.captureException(e2);
        return NextResponse.json({ error: mensajeDeError(e2, "enlazar la cuenta con su ficha") }, { status: 500 });
      }
      return NextResponse.json({ password: nueva, email });
    }

    return NextResponse.json({ error: "acción no válida" }, { status: 400 });
  } catch (e) {
    // Lo que llegue acá es inesperado por definición: no pasó por ninguna de las
    // ramas de arriba. El detalle va al registro; a la pantalla, algo legible.
    Sentry.captureException(e);
    return NextResponse.json(
      { error: "El sistema no pudo completar la operación. Vuelve a intentarlo; si sigue igual, avisa a Felipe." },
      { status: 500 },
    );
  }
}

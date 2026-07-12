import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

// Gestión de cuentas del panel — SOLO admin/lider_do. Corre en el servidor con la
// llave de servicio; verifica que quien llama sea admin (por su sesión).
// Acciones: listar | resetear (contraseña de otro) | crear (cuenta de una persona).

const URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;

function generarClave() {
  const abc = "abcdefghijkmnpqrstuvwxyz", ABC = "ABCDEFGHJKLMNPQRSTUVWXYZ", num = "23456789";
  const pick = (set: string, n: number) => Array.from({ length: n }, () => set[Math.floor(Math.random() * set.length)]).join("");
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

export async function POST(req: Request) {
  if (!URL || !SERVICE) return NextResponse.json({ error: "servidor sin configurar" }, { status: 500 });
  const admin = createClient(URL, SERVICE, { auth: { persistSession: false } });

  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) return NextResponse.json({ error: "sin sesión" }, { status: 401 });
  const { data: userData, error: ue } = await admin.auth.getUser(token);
  if (ue || !userData.user) return NextResponse.json({ error: "sesión inválida" }, { status: 401 });
  const { data: yo } = await admin.from("personas").select("rol").eq("auth_user_id", userData.user.id).maybeSingle();
  if (!yo || !["admin", "lider_do"].includes(yo.rol)) {
    return NextResponse.json({ error: "solo un administrador puede gestionar cuentas" }, { status: 403 });
  }

  const body = await req.json().catch(() => ({}));
  const { accion, personaId, email } = body;

  try {
    if (accion === "listar") {
      const { data: personas } = await admin
        .from("personas")
        .select("id, nombres, apellidos, rol, auth_user_id, sedes:sede_base_id(codigo)")
        .in("rol", ["admin", "lider_do", "supervisor_sede"])
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
      return NextResponse.json({ cuentas });
    }

    if (accion === "resetear") {
      const { data: p } = await admin.from("personas").select("auth_user_id").eq("id", personaId).maybeSingle();
      if (!p?.auth_user_id) return NextResponse.json({ error: "esa persona no tiene cuenta" }, { status: 409 });
      const nueva = generarClave();
      const { error } = await admin.auth.admin.updateUserById(p.auth_user_id, { password: nueva });
      if (error) return NextResponse.json({ error: error.message }, { status: 500 });
      return NextResponse.json({ password: nueva });
    }

    if (accion === "crear") {
      if (!email || !String(email).includes("@")) return NextResponse.json({ error: "correo inválido" }, { status: 400 });
      const { data: p } = await admin.from("personas").select("id, auth_user_id").eq("id", personaId).maybeSingle();
      if (!p) return NextResponse.json({ error: "persona no encontrada" }, { status: 404 });
      if (p.auth_user_id) return NextResponse.json({ error: "esa persona ya tiene cuenta" }, { status: 409 });
      const nueva = generarClave();
      const { data: authData, error } = await admin.auth.admin.createUser({ email, password: nueva, email_confirm: true });
      if (error) return NextResponse.json({ error: error.message }, { status: 500 });
      const { error: e2 } = await admin.from("personas").update({ auth_user_id: authData.user.id }).eq("id", personaId);
      if (e2) return NextResponse.json({ error: e2.message }, { status: 500 });
      return NextResponse.json({ password: nueva, email });
    }

    return NextResponse.json({ error: "acción no válida" }, { status: 400 });
  } catch (e: any) {
    return NextResponse.json({ error: e.message ?? "error" }, { status: 500 });
  }
}

import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

// Reabre el día de una persona que ya marcó salida final: convierte esa salida
// final en una salida temporal (con el motivo del regreso) y registra el retorno,
// de modo que las horas cuenten correcto (el rato afuera NO suma). Corre en el
// servidor con la llave de servicio (nunca expuesta al cliente).

const URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;

export async function POST(req: Request) {
  if (!URL || !SERVICE) {
    return NextResponse.json({ error: "servidor sin configurar" }, { status: 500 });
  }
  const admin = createClient(URL, SERVICE, { auth: { persistSession: false } });

  // 1) La petición debe venir de una sesión de TERMINAL válida.
  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) return NextResponse.json({ error: "sin sesión" }, { status: 401 });
  const { data: userData, error: ue } = await admin.auth.getUser(token);
  if (ue || !userData.user) return NextResponse.json({ error: "sesión inválida" }, { status: 401 });
  const { data: term } = await admin
    .from("terminales")
    .select("id, activo")
    .eq("auth_user_id", userData.user.id)
    .maybeSingle();
  if (!term || !term.activo) {
    return NextResponse.json({ error: "no es un terminal válido" }, { status: 403 });
  }

  // 2) Datos.
  const { personaId, motivo } = await req.json().catch(() => ({}));
  if (!personaId || !motivo || String(motivo).trim().length < 3) {
    return NextResponse.json({ error: "faltan datos (personaId, motivo)" }, { status: 400 });
  }

  // 3) Buscar la última salida final de HOY (hora Lima).
  const hoy = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Lima" }).format(new Date());
  const ini = `${hoy}T00:00:00-05:00`, fin = `${hoy}T23:59:59-05:00`;
  const { data: finals } = await admin
    .from("marcajes")
    .select("id, sede_id")
    .eq("persona_id", personaId)
    .eq("tipo", "salida_final")
    .gte("timestamp_marca", ini)
    .lte("timestamp_marca", fin)
    .order("timestamp_marca", { ascending: false })
    .limit(1);
  const cierre = finals?.[0];
  if (!cierre) {
    return NextResponse.json({ error: "no hay salida final de hoy para reabrir" }, { status: 409 });
  }

  // 4) Reclasificar esa salida final como salida temporal (con motivo)…
  const { error: e1 } = await admin
    .from("marcajes")
    .update({ tipo: "salida_otro", motivo_otro: String(motivo).trim() })
    .eq("id", cierre.id);
  if (e1) return NextResponse.json({ error: e1.message }, { status: 500 });

  // 5) …y registrar el retorno ahora (queda "adentro", día abierto de nuevo).
  const { error: e2 } = await admin.from("marcajes").insert({
    client_uuid: globalThis.crypto.randomUUID(),
    persona_id: personaId,
    sede_id: cierre.sede_id,
    tipo: "retorno_otro",
    timestamp_marca: new Date().toISOString(),
    origen: "terminal",
  });
  if (e2) return NextResponse.json({ error: e2.message }, { status: 500 });

  // 6) Recalcular la jornada del día.
  const { error: e3 } = await admin.rpc("fn_recalcular_jornada", { p_persona_id: personaId, p_fecha: hoy });
  if (e3) return NextResponse.json({ error: e3.message }, { status: 500 });

  return NextResponse.json({ ok: true });
}

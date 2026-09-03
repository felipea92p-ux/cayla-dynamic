import { createServiceRoleClient } from "@cayla-dynamic/database";
import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { Resend } from "resend";
import { TZ_LIMA } from "@cayla-dynamic/shared";

// Drena la cola de `alertas` (canal = 'email', estado = 'pendiente') y manda el
// correo. Lo llama el cron de Postgres cada 15 min (migración 0352) — nunca una
// persona. Mismo patrón que /api/espejo: token compartido en el header, nunca
// en el repo.
//
// QUÉ PROMETE: cada alerta pendiente termina en 'enviado' o 'fallido', nunca se
// queda pendiente en silencio para siempre — y un correo que falla no frena a
// los demás de la cola.
//
// POR QUÉ RESEND: el dominio cayla.pe ya está verificado ahí —Supabase Auth lo
// usa para el correo de "recuperar clave" (dynamic@cayla.pe)—, así que no hace
// falta configurar DNS de nuevo. Es una API key propia, aparte de la que usa
// Supabase: si un día hay que revocar una, la otra sigue viva.

const ALERTAS_CRON_TOKEN = process.env.ALERTAS_CRON_TOKEN;
const RESEND_API_KEY = process.env.RESEND_API_KEY;
const REMITENTE = "CAYLA Dynamic <dynamic@cayla.pe>";

export const dynamic = "force-dynamic";

function horaLima(iso: string): string {
  return new Intl.DateTimeFormat("es-PE", { timeZone: TZ_LIMA, hour: "2-digit", minute: "2-digit", hour12: true }).format(new Date(iso));
}

interface Alerta { id: string; persona_id: string; tipo: string; payload: Record<string, unknown> }

// Un tipo por mensaje. Los que `alertas` declara pero ningún código genera
// todavía (olvido_salida, tardanza, salida_no_retornada, digest_diario) caen
// en el `default` de abajo: un mensaje genérico en vez de una excepción, para
// que el día que alguien empiece a insertarlos esto no reviente por no
// conocerlos.
function redactar(alerta: Alerta, nombre: string): { asunto: string; texto: string } {
  if (alerta.tipo === "auto_cierre") {
    const fecha = String(alerta.payload.fecha ?? "");
    const tsCierre = String(alerta.payload.ts_cierre ?? "");
    return {
      asunto: `Dynamic: el día ${fecha} de ${nombre} se cerró solo`,
      texto:
        `Hola,\n\n` +
        `El ${fecha}, ${nombre} no marcó su salida y el sistema cerró el día ` +
        `solo, poniendo como hora de salida las ${tsCierre ? horaLima(tsCierre) : "—"}. ` +
        `Esa hora es una suposición (la programada, o la última marca del día) — ` +
        `no lo que de verdad se marcó.\n\n` +
        `Si esa hora no es la real, corrígela en el panel → Correcciones.\n\n` +
        `— Dynamic, CAYLA`,
    };
  }
  return {
    asunto: `Dynamic: nueva incidencia de ${nombre}`,
    texto: `Hay una incidencia nueva de tipo "${alerta.tipo}" para ${nombre}. Revísala en el panel → Incidencias.\n\n— Dynamic, CAYLA`,
  };
}

export async function POST(req: Request) {
  const sb = createServiceRoleClient();
  if (!sb || !ALERTAS_CRON_TOKEN || !RESEND_API_KEY) {
    return NextResponse.json({ error: "servidor sin configurar" }, { status: 500 });
  }
  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!token || token !== ALERTAS_CRON_TOKEN) return NextResponse.json({ error: "no autorizado" }, { status: 401 });

  const { data: pendientes, error } = await sb
    .from("alertas")
    .select("id, persona_id, tipo, payload")
    .eq("estado", "pendiente")
    .eq("canal", "email")
    .order("created_at")
    .limit(100);

  if (error) {
    Sentry.captureException(error);
    return NextResponse.json({ error: "no se pudo leer la cola" }, { status: 500 });
  }
  if (!pendientes || pendientes.length === 0) {
    return NextResponse.json({ enviadas: 0, fallidas: 0 });
  }

  const resend = new Resend(RESEND_API_KEY);

  let enviadas = 0;
  let fallidas = 0;

  for (const alerta of pendientes as Alerta[]) {
    try {
      const { data: persona } = await sb
        .from("personas")
        .select("nombres, apellidos, email, sede_base_id")
        .eq("id", alerta.persona_id)
        .maybeSingle();

      // Sin persona no hay a quién avisar ni de qué sede — no se reintenta.
      if (!persona) {
        await sb.from("alertas").update({ estado: "fallido" }).eq("id", alerta.id);
        fallidas++;
        continue;
      }

      const sedeId = (alerta.payload.sede_id as string | undefined) ?? persona.sede_base_id;
      const { data: encargadas } = await sb
        .from("personas")
        .select("email")
        .eq("sede_base_id", sedeId)
        .eq("rol", "supervisor_sede")
        .eq("estado", "activo");

      // La propia persona Y su(s) encargada(s) — decisión de Felipe (2026-09-03):
      // quien se auto-cerró también tiene que enterarse, no solo quien supervisa.
      const destinatarios = [persona.email, ...((encargadas ?? []).map((e) => e.email))].filter(
        (correo): correo is string => !!correo,
      );

      if (destinatarios.length === 0) {
        // Ni la persona ni su sede tienen correo cargado. No es un error de
        // envío — es un dato que falta — pero igual no se reintenta solo: sin
        // cargar el correo, la próxima pasada fallaría exactamente igual.
        await sb.from("alertas").update({ estado: "fallido" }).eq("id", alerta.id);
        fallidas++;
        continue;
      }

      const nombre = `${persona.nombres} ${persona.apellidos}`.trim();
      const { asunto, texto } = redactar(alerta, nombre);

      // resend.emails.send NO lanza en un rechazo: devuelve { error }. Si se
      // tratara como éxito por no haber excepción, la fila se marcaría
      // 'enviado' sin haber salido nada — silencioso, que es lo peor.
      const { error: errEnvio } = await resend.emails.send({
        from: REMITENTE,
        to: destinatarios,
        subject: asunto,
        text: texto,
      });
      if (errEnvio) throw new Error(errEnvio.message);

      await sb.from("alertas").update({ estado: "enviado", enviado_at: new Date().toISOString() }).eq("id", alerta.id);
      enviadas++;
    } catch (e) {
      // Un correo que falla no frena la cola: se marca y se sigue con el resto.
      Sentry.captureException(e);
      await sb.from("alertas").update({ estado: "fallido" }).eq("id", alerta.id);
      fallidas++;
    }
  }

  return NextResponse.json({ enviadas, fallidas });
}

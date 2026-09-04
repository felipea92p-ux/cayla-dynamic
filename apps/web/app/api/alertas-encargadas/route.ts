import { createServiceRoleClient } from "@cayla-dynamic/database";
import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";

// Despacha por correo lo que hay pendiente en `alertas`, a la encargada de la
// sede de la persona involucrada. Lo llama el cron de Vercel (vercel.json),
// una vez al día a las 12:00 UTC (07:00 Lima).
//
// UNA VEZ AL DÍA, NO CADA POCOS MINUTOS — y no es la frecuencia ideal, es la
// que permite el plan Hobby de Vercel: como mucho un cron por proyecto, y
// como mucho una vez al día. El primer intento fue cada 10 minutos y el
// despliegue del PR #162 falló en seco, señalando derecho a
// https://vercel.com/docs/cron-jobs/usage-and-pricing. Con esto, el aviso es
// más un digest de lo que pasó ayer que un aviso instantáneo — que el plan
// pase a Pro es lo único que lo vuelve inmediato de verdad.
//
// La variable se llama `CRON_SECRET` y no algo propio de esta ruta (a
// diferencia de `ESPEJO_TOKEN` en /api/espejo) porque Vercel reconoce ese
// nombre exacto: si existe, manda solo él `Authorization: Bearer
// $CRON_SECRET` en cada invocación de cron — no hay que configurar nada más
// para que la protección funcione.
//
// `alertas` se escribe desde la 0007 (auto-cierre) con canal='push', pensado
// para una app móvil que nunca existió: nadie la despachaba. Esta ruta no
// respeta esa columna a propósito — ver el comentario de la migración 0354.
// Hasta que haya una app real con `push_tokens`, todo pendiente sale por
// correo, que es el único camino de entrega que hoy existe de verdad.

const CRON_SECRET = process.env.CRON_SECRET;
const RESEND_API_KEY = process.env.RESEND_API_KEY;
const RESEND_FROM = process.env.RESEND_FROM ?? "Dynamic <onboarding@resend.dev>";

export const dynamic = "force-dynamic";

interface AlertaPendiente {
  alerta_id: string;
  tipo: string;
  payload: Record<string, unknown>;
  persona_nombre: string;
  sede_codigo: string;
  destinatarios: string[];
  destinatarios_nombres: string[];
}

function textoDeFecha(payload: Record<string, unknown>): string {
  const f = payload.fecha;
  return typeof f === "string" ? f : "una fecha reciente";
}

/** Igual que `textoDeFecha`, para el resto de campos del payload de vencimiento (0356/0357). */
function texto(payload: Record<string, unknown>, campo: string, porDefecto = "—"): string {
  const v = payload[campo];
  return typeof v === "string" || typeof v === "number" ? String(v) : porDefecto;
}

/** Asunto y cuerpo por tipo de alerta. Un `tipo` sin plantilla propia cae a un texto genérico, nunca se cae la ruta entera por un tipo nuevo que aparezca en `alertas`. */
function componerCorreo(a: AlertaPendiente): { asunto: string; texto: string } {
  const fecha = textoDeFecha(a.payload);
  const link = `https://cayla-dynamic.vercel.app/admin/correcciones?fecha=${fecha}`;

  if (a.tipo === "auto_cierre") {
    return {
      asunto: `Dynamic: la jornada de ${a.persona_nombre} quedó sin cerrar (${fecha})`,
      texto:
        `Dynamic cerró sola la jornada de ${a.persona_nombre} el ${fecha} porque no se registró una salida.\n\n` +
        `Revísala en Correcciones antes de que se pague así: ${link}\n\n` +
        `Este correo es un aviso automático — no es necesario responderlo.`,
    };
  }

  // Los dos de abajo (0356/0357) llegan con `persona_id` YA resuelto al
  // destinatario (DO), no a la encargada — ver el porqué en el encabezado
  // de la 0358. El link va a la pantalla donde DO ya mira esto hoy, no a
  // Correcciones: un contrato o un récord de vacaciones no se corrige ahí.
  if (a.tipo === "contrato_por_vencer") {
    const dias = texto(a.payload, "dias_restantes");
    return {
      asunto: `Dynamic: el contrato de ${texto(a.payload, "persona")} vence en ${dias} día(s)`,
      texto:
        `El contrato de ${texto(a.payload, "persona")} (${texto(a.payload, "sede")}) vence el ${texto(a.payload, "fecha_fin_contrato")} — en ${dias} día(s).\n\n` +
        `Revísalo en Contratos: https://cayla-dynamic.vercel.app/admin/contratos\n\n` +
        `Este correo es un aviso automático — no es necesario responderlo.`,
    };
  }

  if (a.tipo === "vacaciones_por_vencer") {
    const vencidos = texto(a.payload, "records_vencidos", "0");
    const yaVencido = vencidos !== "0" && vencidos !== "—";
    return {
      asunto: yaVencido
        ? `Dynamic: ${texto(a.payload, "persona")} ya tiene vacaciones vencidas`
        : `Dynamic: las vacaciones de ${texto(a.payload, "persona")} vencen en ${texto(a.payload, "dias_para_vencer")} día(s)`,
      texto:
        (yaVencido
          ? `${texto(a.payload, "persona")} (${texto(a.payload, "sede")}) ya tiene ${vencidos} récord(s) de vacaciones vencido(s) — el art. 23 del D. Leg. 713 lo castiga con una remuneración entera de indemnización.\n\n`
          : `Las vacaciones de ${texto(a.payload, "persona")} (${texto(a.payload, "sede")}) vencen el ${texto(a.payload, "vence_el")} — en ${texto(a.payload, "dias_para_vencer")} día(s).\n\n`) +
        `Tiene ${texto(a.payload, "dias_pendientes")} día(s) pendientes en total. Revísalo en Ausencias: https://cayla-dynamic.vercel.app/admin/ausencias\n\n` +
        `Este correo es un aviso automático — no es necesario responderlo.`,
    };
  }

  return {
    asunto: `Dynamic: aviso de ${a.persona_nombre}`,
    texto: `Hay un aviso pendiente de tipo "${a.tipo}" para ${a.persona_nombre} (${fecha}). Revísalo en el panel: ${link}`,
  };
}

async function enviarCorreo(destinatarios: string[], asunto: string, texto: string): Promise<{ ok: boolean; error?: string }> {
  if (!RESEND_API_KEY) return { ok: false, error: "RESEND_API_KEY no configurada" };

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${RESEND_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: RESEND_FROM, to: destinatarios, subject: asunto, text: texto }),
  });
  if (res.ok) return { ok: true };

  const cuerpo = await res.text().catch(() => "");
  return { ok: false, error: `Resend respondió ${res.status}: ${cuerpo.slice(0, 300)}` };
}

export async function GET(req: Request) {
  const sb = createServiceRoleClient();
  if (!sb || !CRON_SECRET) return NextResponse.json({ error: "servidor sin configurar" }, { status: 500 });

  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!token || token !== CRON_SECRET) return NextResponse.json({ error: "no autorizado" }, { status: 401 });

  try {
    const { data, error } = await sb.rpc("fn_alertas_email_pendientes");
    if (error) throw new Error(error.message);

    const pendientes = (data ?? []) as AlertaPendiente[];
    let enviadas = 0, fallidas = 0, sinDestinatario = 0;

    for (const a of pendientes) {
      if (a.destinatarios.length === 0) {
        sinDestinatario++;
        await sb.rpc("fn_marcar_alerta_resultado", {
          p_id: a.alerta_id, p_exito: false, p_nota: "sin encargada con correo activo en esa sede",
        });
        continue;
      }

      const { asunto, texto } = componerCorreo(a);
      const r = await enviarCorreo(a.destinatarios, asunto, texto);
      if (r.ok) enviadas++; else fallidas++;
      await sb.rpc("fn_marcar_alerta_resultado", { p_id: a.alerta_id, p_exito: r.ok, p_nota: r.error ?? null });
    }

    return NextResponse.json({ procesadas: pendientes.length, enviadas, fallidas, sinDestinatario });
  } catch (e) {
    Sentry.captureException(e);
    return NextResponse.json({ error: "no se pudo despachar alertas" }, { status: 500 });
  }
}

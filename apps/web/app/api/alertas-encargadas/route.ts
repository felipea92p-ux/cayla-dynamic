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

//
// CÓMO SE EVITA MANDAR DOS VECES EL MISMO CORREO (0362, hallazgos 16-18 de la
// auditoría del 2026-09-03/04). Cada fila se RESERVA antes de enviarla con
// `fn_alertas_reservar`, que es un compare-and-set en la base: solo una
// ejecución consigue el `true`. Si dos invocaciones se solapan —un reintento
// del cron, un redeploy que dispara la ruta dos veces— las dos listan las
// mismas filas, pero la segunda recibe `false` en cada una y las salta. Y
// como la marca queda ANTES del envío, si esta función muere a mitad del
// lote solo la fila en vuelo queda 'procesando' (la base la reintenta sola
// pasada una hora); las ya enviadas dicen 'enviado' y no se repiten mañana.

const CRON_SECRET = process.env.CRON_SECRET;
const RESEND_API_KEY = process.env.RESEND_API_KEY;
const RESEND_FROM = process.env.RESEND_FROM ?? "Dynamic <onboarding@resend.dev>";

export const dynamic = "force-dynamic";

// 60 s es el MÁXIMO que permite el plan Hobby de Vercel para una función. Sin
// declararlo, el tope es 10 s, y con ~15-20 pendientes acumulados (un fin de
// semana sin cron) el lote en serie se pasaba y la función moría a medias.
// No hace falta más que 60: con el compare-and-set de arriba, lo que no
// alcance a salir hoy sigue 'pendiente' y sale mañana — sin duplicar nada.
export const maxDuration = 60;

interface AlertaPendiente {
  alerta_id: string;
  tipo: string;
  payload: Record<string, unknown>;
  persona_nombre: string;
  sede_codigo: string;
  destinatarios: string[];
  destinatarios_nombres: string[];
  /** Cuántas veces ya se intentó (0362). El intento de esta vuelta es `intentos + 1`. */
  intentos: number;
  /** Estado en que estaba al listarla: 'pendiente', 'fallido' (reintento) o 'procesando' (quedó de un corte). */
  estado_previo: string;
}

interface FalloDeEnvio {
  alerta_id: string;
  tipo: string;
  intento: number;
  error: string;
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
    let enviadas = 0, fallidas = 0, sinDestinatario = 0, tomadasPorOtra = 0, reintentos = 0;
    const detalleFallos: FalloDeEnvio[] = [];
    // Sedes sin encargada con correo activo: ese fallo no pasa por Resend ni
    // por Sentry como excepción, así que si no se avisa aparte, al tercer
    // día la fila es definitiva y nadie sabe que la causa está en Equipo.
    const sedesSinDestinatario = new Set<string>();

    for (const a of pendientes) {
      // La reserva va PRIMERO, antes de mirar destinatarios o de mandar nada:
      // si otra ejecución ya la tomó, acá no se toca ni se cuenta como fallo.
      const { data: reservada, error: errorReserva } = await sb.rpc("fn_alertas_reservar", { p_id: a.alerta_id });
      if (errorReserva) throw new Error(errorReserva.message);
      if (reservada !== true) { tomadasPorOtra++; continue; }

      // Las que venían 'procesando' son las que una ejecución anterior dejó a
      // medias: la base las volvió a soltar pasada una hora. No es un error de
      // hoy, pero conviene saber que ayer hubo un corte. Se cuentan DESPUÉS de
      // reservar, para no contar la que otra ejecución ya retomó.
      if (a.estado_previo === "procesando") reintentos++;

      const intento = a.intentos + 1;

      if (a.destinatarios.length === 0) {
        sinDestinatario++;
        sedesSinDestinatario.add(a.sede_codigo);
        await sb.rpc("fn_marcar_alerta_resultado", {
          p_id: a.alerta_id, p_exito: false, p_nota: `intento ${intento}: sin encargada con correo activo en esa sede`,
        });
        continue;
      }

      const { asunto, texto } = componerCorreo(a);
      const r = await enviarCorreo(a.destinatarios, asunto, texto);
      if (r.ok) {
        enviadas++;
      } else {
        fallidas++;
        detalleFallos.push({ alerta_id: a.alerta_id, tipo: a.tipo, intento, error: r.error ?? "sin detalle" });
      }
      await sb.rpc("fn_marcar_alerta_resultado", {
        p_id: a.alerta_id, p_exito: r.ok, p_nota: r.ok ? null : `intento ${intento}: ${r.error ?? "sin detalle"}`,
      });
    }

    // Un fallo de Resend antes quedaba 'fallido' en la tabla y nadie se
    // enteraba. Ahora la base lo reintenta hasta tres veces, y Sentry avisa
    // en cada una para que, si el tercero también falla, alguien ya esté
    // mirando la clave o el dominio de Resend.
    if (fallidas > 0) {
      Sentry.captureMessage(`Alertas por correo: ${fallidas} envío(s) fallido(s)`, {
        level: "warning",
        extra: { detalle: detalleFallos },
      });
    }
    if (sinDestinatario > 0) {
      Sentry.captureMessage(
        `Alertas por correo: ${sinDestinatario} aviso(s) sin encargada con correo en ${[...sedesSinDestinatario].sort().join(", ")}`,
        { level: "warning", extra: { sedes: [...sedesSinDestinatario].sort() } },
      );
    }
    if (reintentos > 0) {
      Sentry.captureMessage(`Alertas: ${reintentos} reintento(s) tras un corte`, { level: "info" });
    }

    return NextResponse.json({ procesadas: pendientes.length, enviadas, fallidas, sinDestinatario, tomadasPorOtra, reintentos });
  } catch (e) {
    Sentry.captureException(e);
    return NextResponse.json({ error: "no se pudo despachar alertas" }, { status: 500 });
  }
}

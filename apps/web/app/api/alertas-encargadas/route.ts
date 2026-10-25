import { createServiceRoleClient } from "@cayla-dynamic/database";
import { hoyLima } from "@cayla-dynamic/shared";
import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import {
  causaDeNota,
  causaDeRespuesta,
  NOTA_CUERPO_NO_RECIBIDO,
  NOTA_SIN_DESTINATARIO,
  PREFIJO_SIN_RESPUESTA,
  type CausaInfo,
} from "@/lib/alertas/causa-del-fallo";
import { decidirCorte, FALLOS_SEGUIDOS_PARA_CORTAR, rachaNueva } from "@/lib/alertas/corte-del-lote";
import { diasAlEnviar, fraseDePlazo } from "@/lib/alertas/plazo-al-enviar";
import { ahoraMs, esperarMs, esperaPorSegundo, LIMITE_BLANDO_MS } from "@/lib/alertas/ritmo-del-despacho";

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
//
// CUANDO RESEND NO RESPONDE, O RESPONDE QUE EL PROBLEMA ES NUESTRO (Vogels:
// la dependencia ya está caída). Se degrada así: ningún aviso por correo sale,
// y se nota en ese mismo despacho con UN solo mensaje de Sentry en nivel error
// que dice la causa y cuántos avisos quedaron sin intentar. No se pierde el
// HECHO: la fuente de verdad (Contratos, Ausencias, Correcciones) sigue
// mostrándolo en la Bandeja. Lo que sí puede perderse es el CORREO: la base solo
// despacha avisos de los últimos 7 días (`fn_alerta_despachable`, 0362), así que
// si la avería dura más que eso, los avisos más viejos ya no salen por correo y
// quedan solo en su pantalla.
//
// POR QUÉ EL LOTE SE CORTA. El 2026-10-25, 61 avisos gastaron sus tres
// intentos contra una sola avería (Resend: «The cayla.pe domain is not
// verified»). La reserva gasta un intento ANTES de enviar y el cron es diario,
// así que tres intentos son tres DÍAS; tratar la avería de un canal como fallo
// de cada fila convertía UNA causa en N muertes. Ahora cada fallo se clasifica
// con `causaDeRespuesta` (apps/web/lib/alertas/causa-del-fallo.ts, la única
// definición de «por qué falló») y `decidirCorte` (apps/web/lib/alertas/
// corte-del-lote.ts) decide si se CORTA el lote sin reservar las demás filas,
// que siguen 'pendiente' sin intento gastado. Las reglas, con su porqué, están
// en ese archivo; en resumen:
//   · dominio sin verificar, clave inválida/suspendida, variable sin configurar:
//     corta a la primera y le DEVUELVE el intento a esa fila (no tuvo culpa);
//   · límite de envíos: si es «por segundo» espera y reintenta UNA vez; si sigue,
//     o es una cuota diaria o mensual, corta;
//   · Resend caído (5xx, red, tiempo): corta a la segunda fila seguida;
//   · lo que Dynamic no reconoce: corta a los 3 fallos seguidos de la misma causa.
// Una dirección que Resend rechaza, o nadie a quien escribir, no corta: se sigue
// con la siguiente, como siempre.
//
// `fn_alertas_devolver_intento` es de la 0548. Si todavía no está pegada en
// producción, la ruta sigue como antes (la fila gasta su intento) y no se queja.

const CRON_SECRET = process.env.CRON_SECRET;
const RESEND_API_KEY = process.env.RESEND_API_KEY;
// Sin fallback a propósito (hallazgo 10, auditoría 2026-09-03/04). Con
// `?? "Dynamic <onboarding@resend.dev>"` — el remitente de PRUEBA de Resend,
// que solo entrega a la cuenta dueña de la API key — una `RESEND_FROM` que
// nunca se configuró en Vercel quedaba enmascarada: la ruta igual intentaba
// el envío y dejaba que el 403 de Resend fuera la única señal, con un texto
// que no dice que el remitente es el problema. Ahora, si falta, `enviarCorreo`
// lo rechaza ANTES de llamar a Resend, con un motivo que sí lo dice — y ese
// texto es justo el que `/admin/bandeja` muestra tras el tercer reintento.
const RESEND_FROM = process.env.RESEND_FROM;

export const dynamic = "force-dynamic";

// Sin fluid compute, 60 s es el MÁXIMO del plan Hobby de Vercel (y 10 s el
// valor por defecto); con fluid compute Vercel permite hasta 300 s. Se dejó en
// 60 porque NO está comprobado que este proyecto lo tenga activado, y declarar
// 300 sin eso puede hacer fallar el despliegue. Para no depender del tope duro,
// el lote se corta solo a los 45 s (`LIMITE_BLANDO_MS`): con el compare-and-set
// de arriba, lo que no alcance a salir hoy sigue 'pendiente' y sale mañana, sin
// duplicar nada. Con Resend lento y Supabase lejano, 61 filas pueden pasar de
// 60 s (medido en simulación por la revisión del 2026-10-25: ~1 s por fila).
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
  causa: string;
  del_canal: boolean;
}

/** Cuánto se espera a Resend antes de darlo por caído. Con 60 s de `maxDuration`, un envío colgado no puede comerse el lote entero. */
const TIEMPO_MAXIMO_RESEND_MS = 10_000;

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
function componerCorreo(a: AlertaPendiente, hoy: string): { asunto: string; texto: string } {
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
  // Los días se cuentan AL ENVIAR contra la fecha del payload, no con el número
  // que quedó escrito al generar la fila: la fila puede salir (o reintentarse)
  // días después y el número viejo sería falso. Si la fecha falta, cae al
  // número del payload; ver `diasAlEnviar`.
  if (a.tipo === "contrato_por_vencer") {
    const persona = texto(a.payload, "persona");
    const fin = a.payload.fecha_fin_contrato;
    const { verbo, plazo, frase } = fraseDePlazo(diasAlEnviar(fin, a.payload.dias_restantes, hoy));
    return {
      asunto: `Dynamic: el contrato de ${persona} ${frase}`,
      texto:
        `El contrato de ${persona} (${texto(a.payload, "sede")}) ${verbo}${typeof fin === "string" ? ` el ${fin}` : ""}${plazo ? ` — ${plazo}` : ""}.` +
        // Un aviso que sale con «venció» salió tarde: la fila esperó (o se
        // reintentó) hasta pasar la fecha, y mientras tanto el contrato pudo
        // renovarse. No se afirma más de lo que se sabe: se pide mirarlo.
        `${verbo === "venció" ? " Este aviso salió con retraso: antes de actuar, confirma en Contratos si ya se renovó." : ""}\n\n` +
        `Revísalo en Contratos: https://cayla-dynamic.vercel.app/admin/contratos\n\n` +
        `Este correo es un aviso automático — no es necesario responderlo.`,
    };
  }

  if (a.tipo === "vacaciones_por_vencer") {
    const persona = texto(a.payload, "persona");
    const sede = texto(a.payload, "sede");
    const venceEl = a.payload.vence_el;
    const dias = diasAlEnviar(venceEl, a.payload.dias_para_vencer, hoy);
    const { plazo } = fraseDePlazo(dias);
    const vencidos = texto(a.payload, "records_vencidos", "0");
    // Dos formas de «ya vencido», y no se funden: con récords vencidos desde
    // que se generó la fila se afirma el hecho (y el art. 23); si lo único que
    // pasó es que la fecha se cumplió mientras la fila esperaba salir, no se
    // sabe si la persona ya gozó esos días entre tanto, y el correo pide mirarlo
    // en vez de afirmarlo (un falso positivo cuesta más que una falta real).
    const conRecordsVencidos = vencidos !== "0" && vencidos !== "—";
    const soloPorFecha = !conRecordsVencidos && dias !== null && dias < 0;
    const cola =
      `Tiene ${texto(a.payload, "dias_pendientes", "varios")} día(s) pendientes en total. Revísalo en Ausencias: https://cayla-dynamic.vercel.app/admin/ausencias\n\n` +
      `Este correo es un aviso automático — no es necesario responderlo.`;

    if (conRecordsVencidos) {
      return {
        asunto: `Dynamic: ${persona} ya tiene vacaciones vencidas`,
        texto:
          // «Al generarse este aviso»: el dato quedó congelado cuando se creó la
          // fila, y el correo puede salir días después. Dynamic avisa, no
          // sanciona: se cita la norma como lo que prevé y se pide confirmar.
          `Al generarse este aviso, ${persona} (${sede}) ya tenía ${vencidos} récord(s) de vacaciones vencido(s) — el art. 23 del D. Leg. 713 prevé una indemnización de una remuneración entera. ` +
          `Confirma en Ausencias que sigue así antes de actuar.\n\n` + cola,
      };
    }
    if (soloPorFecha) {
      return {
        asunto: `Dynamic: el plazo de vacaciones de ${persona} ya venció`,
        texto:
          `El plazo para gozar las vacaciones de ${persona} (${sede}) venció el ${texto(a.payload, "vence_el")} — ${plazo}. ` +
          `Revisa en Ausencias si ya las gozó: si no, el art. 23 del D. Leg. 713 prevé una indemnización de una remuneración entera.\n\n` + cola,
      };
    }
    return {
      asunto: `Dynamic: las vacaciones de ${persona} vencen ${plazo ?? "pronto"}`,
      texto:
        // Sin `vence_el` no se inventa un plazo (ni se usa el número congelado del
        // payload): se dice que no se pudo calcular.
        `Las vacaciones de ${persona} (${sede}) vencen${typeof venceEl === "string" ? ` el ${venceEl}${plazo ? ` — ${plazo}` : ""}` : " pronto (no se pudo calcular la fecha exacta)"}.\n\n` + cola,
    };
  }

  return {
    asunto: `Dynamic: aviso de ${a.persona_nombre}`,
    texto: `Hay un aviso pendiente de tipo "${a.tipo}" para ${a.persona_nombre} (${fecha}). Revísalo en el panel: ${link}`,
  };
}

type ResultadoEnvio = { ok: true } | { ok: false; error: string; causa: CausaInfo; retryAfter?: string | null };

async function enviarCorreo(destinatarios: string[], asunto: string, texto: string): Promise<ResultadoEnvio> {
  // Faltas de configuración: la causa sale del mismo texto que se guarda, así
  // quien escribe la nota y quien la reconoce no pueden separarse.
  if (!RESEND_API_KEY) {
    const error = "RESEND_API_KEY no configurada";
    return { ok: false, error, causa: causaDeNota(error) };
  }
  if (!RESEND_FROM) {
    const error = "RESEND_FROM no configurada — sin un dominio propio verificado en Resend, el remitente de prueba no entrega a destinatarios reales";
    return { ok: false, error, causa: causaDeNota(error) };
  }

  const r = await enviarUnaVez(destinatarios, asunto, texto);
  // Un 429 «por segundo» es transitorio: otra aplicación que comparte el equipo
  // de Resend, o una ráfaga nuestra, y se resuelve en un segundo. Gastar el
  // intento de la fila y cortar el lote hasta mañana por eso sería desproporcionado:
  // se espera lo que Resend pide (con techo) y se reintenta UNA vez. Una cuota
  // diaria o mensual NO se reintenta: no se resuelve esperando un segundo.
  if (!r.ok && r.causa.limite === "por_segundo") {
    await esperarMs(esperaPorSegundo(r.retryAfter));
    return enviarUnaVez(destinatarios, asunto, texto);
  }
  return r;
}

async function enviarUnaVez(destinatarios: string[], asunto: string, texto: string): Promise<ResultadoEnvio> {
  // Un fetch sin try/catch convertía una caída de red en una excepción que
  // abortaba el lote entero con 500 y dejaba la fila 'procesando' una hora con
  // el intento ya gastado. Y sin tiempo máximo, un Resend colgado se comía los
  // 60 s de la función. Ambas cosas son «Resend caído», no un fallo de la fila.
  let res: Response;
  try {
    res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${RESEND_API_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from: RESEND_FROM, to: destinatarios, subject: asunto, text: texto }),
      signal: AbortSignal.timeout(TIEMPO_MAXIMO_RESEND_MS),
    });
  } catch (e) {
    // Se mira el `name` y no `instanceof Error`: el tiempo agotado de
    // `AbortSignal.timeout` es una DOMException, y en algunos entornos no hereda de Error.
    const nombre = typeof e === "object" && e !== null ? (e as { name?: unknown }).name : undefined;
    const agotado = nombre === "TimeoutError" || nombre === "AbortError";
    const mensaje = typeof e === "object" && e !== null && typeof (e as { message?: unknown }).message === "string" ? (e as { message: string }).message : String(e);
    const detalle = agotado
      ? `sin respuesta tras ${TIEMPO_MAXIMO_RESEND_MS / 1000} s`
      : `error de red: ${mensaje.slice(0, 150)}`;
    return {
      ok: false,
      error: `${PREFIJO_SIN_RESPUESTA} (${detalle})`,
      causa: causaDeRespuesta({ status: null, cuerpo: "", red: true }),
    };
  }
  if (res.ok) return { ok: true };

  // Leer el cuerpo también puede agotar el tiempo; entonces queda vacío y la
  // causa sale del status solo. La nota lo dice, para que la Bandeja no muestre
  // un «Resend respondió 403: » mudo bajo «motivo que Dynamic no reconoce».
  const cuerpo = await res.text().catch(() => "");
  return {
    ok: false,
    error: `Resend respondió ${res.status}: ${cuerpo === "" ? NOTA_CUERPO_NO_RECIBIDO : cuerpo.slice(0, 300)}`,
    causa: causaDeRespuesta({ status: res.status, cuerpo }),
    retryAfter: res.headers.get("retry-after"),
  };
}

type ClienteServicio = NonNullable<ReturnType<typeof createServiceRoleClient>>;

/**
 * Le devuelve a una fila 'fallido' el intento que la reserva le gastó, cuando el
 * fallo fue del canal y no de ella (0548). Nunca aborta el lote:
 *  · la función todavía no existe (migración sin pegar: PGRST202 / 42883) → se
 *    ignora sin ruido y todo sigue como antes de la 0548;
 *  · cualquier otro error es real → a Sentry como excepción.
 */
async function devolverIntento(sb: ClienteServicio, alertaId: string): Promise<void> {
  try {
    // `fn_alertas_devolver_intento` es nueva y los tipos generados todavía no la
    // conocen mientras la 0548 no se pegue: se llama sin tipar.
    const sinTipos = sb as unknown as { rpc: (nombre: string, args: object) => PromiseLike<{ error: { code?: string; message: string } | null }> };
    const { error } = await sinTipos.rpc("fn_alertas_devolver_intento", { p_id: alertaId });
    if (!error) return;
    if (error.code === "PGRST202" || error.code === "42883") return;
    Sentry.captureException(new Error(`fn_alertas_devolver_intento falló para ${alertaId}: ${error.message}`));
  } catch (e) {
    Sentry.captureException(e);
  }
}

export async function GET(req: Request) {
  const sb = createServiceRoleClient();
  if (!sb || !CRON_SECRET) return NextResponse.json({ error: "servidor sin configurar" }, { status: 500 });

  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!token || token !== CRON_SECRET) return NextResponse.json({ error: "no autorizado" }, { status: 401 });

  try {
    // El reloj arranca ANTES de listar: el tope blando de 45 s cuenta todo el lote.
    const inicio = ahoraMs();
    const { data, error } = await sb.rpc("fn_alertas_email_pendientes");
    if (error) throw new Error(error.message);

    const pendientes = (data ?? []) as AlertaPendiente[];
    // Una sola vez por despacho: todas las filas de este lote se cuentan contra
    // el mismo «hoy» de Lima.
    const hoy = hoyLima();
    let enviadas = 0, fallidas = 0, sinDestinatario = 0, tomadasPorOtra = 0, reintentos = 0;
    const detalleFallos: FalloDeEnvio[] = [];
    // Sedes sin ningún destinatario con correo: ese fallo no pasa por Resend ni
    // por Sentry como excepción, así que si no se avisa aparte, al tercer
    // día la fila es definitiva y nadie sabe que la causa está en Equipo.
    const sedesSinDestinatario = new Set<string>();
    // Si el canal de envío está averiado se corta el lote: la causa y cuántas
    // filas quedaron sin tocar (siguen 'pendiente', con su intento intacto).
    // `porDisyuntor` = no se supo qué se averió, pero fue lo mismo tres veces.
    let cortadoPorCanal: { causa: CausaInfo; sinIntentar: number; porDisyuntor: boolean } | null = null;
    // Si el lote se acerca al tope de tiempo de la función: lo que quedó sin tocar.
    let cortadoPorTiempo: { sinIntentar: number } | null = null;
    const racha = rachaNueva();

    for (let i = 0; i < pendientes.length; i++) {
      // Tope blando, al inicio de cada vuelta y ANTES de reservar: una fila
      // reservada y a medio enviar cuando Vercel mata la función queda
      // 'procesando' con el intento gastado y, si Resend sí aceptó ese correo,
      // sale doble mañana. Lo que no alcance a salir hoy sigue como estaba.
      if (ahoraMs() - inicio > LIMITE_BLANDO_MS) {
        cortadoPorTiempo = { sinIntentar: pendientes.length - i };
        break;
      }
      const a = pendientes[i];
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
        const { error: errorMarcar1 } = await sb.rpc("fn_marcar_alerta_resultado", {
          p_id: a.alerta_id, p_exito: false, p_nota: `intento ${intento}: ${NOTA_SIN_DESTINATARIO}`,
        });
        // Si esto falla, la fila queda 'procesando' aunque el correo ya se
        // decidió (aquí, que no se envió) — Supabase nunca lanza excepción
        // por un rechazo de PostgREST, solo lo devuelve en `error`. Sin
        // comprobarlo, la fila se reintenta pasada una hora aunque no haya
        // nada nuevo que hacer con ella. Se reporta como excepción real, sin
        // `throw`: un fallo de una alerta no debe abortar el resto del lote.
        if (errorMarcar1) Sentry.captureException(new Error(`fn_marcar_alerta_resultado falló para ${a.alerta_id}: ${errorMarcar1.message}`));
        continue;
      }

      const { asunto, texto } = componerCorreo(a, hoy);
      const r = await enviarCorreo(a.destinatarios, asunto, texto);
      if (r.ok) {
        enviadas++;
      } else {
        fallidas++;
        detalleFallos.push({ alerta_id: a.alerta_id, tipo: a.tipo, intento, error: r.error, causa: r.causa.causa, del_canal: r.causa.del_canal });
      }
      const { error: errorMarcar2 } = await sb.rpc("fn_marcar_alerta_resultado", {
        p_id: a.alerta_id, p_exito: r.ok, p_nota: r.ok ? null : `intento ${intento}: ${r.error}`,
      });
      // Mismo riesgo que arriba, más caro aquí: si el correo SÍ salió (r.ok)
      // pero esta llamada falla por un motivo transitorio, la fila sigue
      // 'procesando' — el despacho de la hora siguiente la considera de
      // nuevo y reenvía el correo ya entregado, duplicándolo sin que nada lo
      // note (el flujo entero seguía devolviendo 200).
      if (errorMarcar2) Sentry.captureException(new Error(`fn_marcar_alerta_resultado falló para ${a.alerta_id} (envío ${r.ok ? "exitoso" : "fallido"}): ${errorMarcar2.message}`));

      // Avería del CANAL: esta fila ya quedó marcada como fallida (como antes),
      // pero las que siguen fallarían exactamente igual y cada una gastaría un
      // intento —un DÍA— sin posibilidad de salir. Se cortan sin reservarlas.
      // `decidirCorte` explica cuándo corta, cuándo devuelve el intento y por qué.
      const decision = decidirCorte(racha, r.ok ? { ok: true } : { ok: false, causa: r.causa });
      if (!r.ok && decision.corta) {
        // Después de marcar: la devolución solo actúa sobre una fila 'fallido'.
        if (decision.devolverIntento) await devolverIntento(sb, a.alerta_id);
        cortadoPorCanal = { causa: r.causa, sinIntentar: pendientes.length - i - 1, porDisyuntor: decision.razon === "disyuntor" };
        break;
      }
    }

    // Un fallo de Resend antes quedaba 'fallido' en la tabla y nadie se
    // enteraba. Ahora la base lo reintenta hasta tres veces, y Sentry avisa
    // en cada una para que, si el tercero también falla, alguien ya esté
    // mirando la clave o el dominio de Resend.
    // Una avería de canal avisa UNA vez, en nivel error, con la causa y lo que
    // quedó sin intentar (y todos los fallos del lote en `detalle`); si el lote
    // no se cortó, los fallos sueltos (una dirección rechazada, una primera
    // caída de Resend que luego se recuperó) avisan como warning. Así la misma
    // avería no suena N veces.
    if (cortadoPorCanal) {
      Sentry.captureMessage(
        cortadoPorCanal.porDisyuntor
          ? `Alertas por correo: ${FALLOS_SEGUIDOS_PARA_CORTAR} envíos seguidos fallaron por lo mismo (${cortadoPorCanal.causa.etiqueta}); se cortó el lote por precaución y ${cortadoPorCanal.sinIntentar} aviso(s) quedaron sin intentar`
          : `Alertas por correo: el canal de envío falló (${cortadoPorCanal.causa.etiqueta}); ${cortadoPorCanal.sinIntentar} aviso(s) quedaron sin intentar`,
        {
          level: "error",
          extra: {
            causa: cortadoPorCanal.causa.causa,
            que_hacer: cortadoPorCanal.causa.que_hacer,
            sinIntentar: cortadoPorCanal.sinIntentar,
            porDisyuntor: cortadoPorCanal.porDisyuntor,
            detalle: detalleFallos,
          },
        },
      );
    } else if (detalleFallos.length > 0) {
      Sentry.captureMessage(`Alertas por correo: ${detalleFallos.length} envío(s) fallido(s)`, {
        level: "warning",
        extra: { detalle: detalleFallos },
      });
    }
    // El tiempo es otra historia que la avería del canal, y avisa aparte: aquí
    // no hay nada que arreglar en Resend, solo que el lote no cupo en un día.
    if (cortadoPorTiempo) {
      Sentry.captureMessage(
        `Alertas por correo: el despacho se cortó por tiempo; ${cortadoPorTiempo.sinIntentar} aviso(s) salen mañana`,
        { level: "warning", extra: { sinIntentar: cortadoPorTiempo.sinIntentar, limiteMs: LIMITE_BLANDO_MS } },
      );
    }
    if (sinDestinatario > 0) {
      Sentry.captureMessage(
        `Alertas por correo: ${sinDestinatario} aviso(s) sin ningún destinatario con correo en ${[...sedesSinDestinatario].sort().join(", ")}`,
        { level: "warning", extra: { sedes: [...sedesSinDestinatario].sort() } },
      );
    }
    if (reintentos > 0) {
      Sentry.captureMessage(`Alertas: ${reintentos} reintento(s) tras un corte`, { level: "info" });
    }

    return NextResponse.json({
      procesadas: pendientes.length, enviadas, fallidas, sinDestinatario, tomadasPorOtra, reintentos,
      cortadoPorCanal: cortadoPorCanal ? { causa: cortadoPorCanal.causa.causa, sinIntentar: cortadoPorCanal.sinIntentar } : null,
      cortadoPorTiempo,
    });
  } catch (e) {
    Sentry.captureException(e);
    return NextResponse.json({ error: "no se pudo despachar alertas" }, { status: 500 });
  }
}

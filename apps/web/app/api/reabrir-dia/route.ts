import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { mensajeDeError } from "@/lib/admin/mensaje-error";

// Reabre el día de una persona que ya marcó salida final: esa salida se anula y
// se reemite como salida TEMPORAL con el mismo instante (así el rato afuera no
// suma), y entra el retorno. La persona queda adentro otra vez.
//
// ── POR QUÉ ESTA RUTA CASI NO HACE NADA ─────────────────────────────────────
//
// Antes hacía las tres escrituras acá, con la llave de servicio, en tres viajes
// sueltos. Si el segundo fallaba, la salida final ya se había convertido en
// temporal y el retorno nunca entraba: el día quedaba ABIERTO para siempre y las
// horas de esa persona salían mal, sin que nadie se enterara hasta cuadrar la
// planilla. Ahora todo eso vive en fn_reabrir_dia (mig. 0137), que es una
// transacción: o queda todo, o no queda nada.
//
// Y ya no se usa la llave de servicio. La petición viaja con el token de la
// TERMINAL, así que la función identifica el kiosco por `auth.uid()` y de ahí
// saca la sede. Antes el terminal se resolvía acá y se le pasaba a la base como
// dato; ahora no hay ningún dato que falsificar.

const URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const ANON = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

export async function POST(req: Request) {
  if (!URL || !ANON) {
    return NextResponse.json({ error: "servidor sin configurar" }, { status: 500 });
  }

  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) return NextResponse.json({ error: "sin sesión" }, { status: 401 });

  const { personaId, motivo } = await req.json().catch(() => ({}));
  if (!personaId || !motivo) {
    return NextResponse.json({ error: "faltan datos (personaId, motivo)" }, { status: 400 });
  }

  // El cliente lleva la sesión de la terminal, no la llave de servicio: es lo que
  // hace que auth.uid() dentro de la función devuelva el kiosco que llamó.
  const sb = createClient(URL, ANON, {
    auth: { persistSession: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });

  const { data, error } = await sb.rpc("fn_reabrir_dia", {
    p_persona_id: personaId,
    p_motivo: String(motivo),
  });

  if (error) {
    // Los mensajes de la función están escritos para que los lea quien está
    // parada frente al kiosco ("esa marca es de otra sede", "no hay salida final
    // de hoy"), así que se devuelven tal cual en vez de un "no se pudo" que
    // obliga a llamar a la encargada para averiguar qué pasó.
    //
    // `mensajeDeError` conserva eso exactamente: los cinco mensajes de
    // fn_reabrir_dia salen con código P0001 —los escribimos nosotros— y pasan
    // intactos. Lo que ya NO sale es lo otro: si un día falla un constraint o
    // un permiso, el kiosco mostraba «violates foreign key constraint …», que
    // no le dice nada a nadie y de paso publica cómo se llaman las tablas.
    if (error.code !== "P0001") Sentry.captureException(error);
    return NextResponse.json({ error: mensajeDeError(error) }, { status: 400 });
  }

  return NextResponse.json(data ?? { ok: true });
}

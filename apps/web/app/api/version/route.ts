import { NextResponse } from "next/server";

// Qué despliegue está sirviendo esto, para que una pestaña abierta compare con
// el suyo y avise «hay una versión nueva» (lib/version-despliegue.ts).
//
// Es público a propósito: solo dice un identificador de despliegue, sin
// sesión, sin datos de nadie. Y nunca se guarda en caché —ni en el navegador
// ni en Vercel—: una respuesta cacheada contestaría la versión vieja justo
// cuando se necesita saber que hay otra.

export const dynamic = "force-dynamic";

export function GET() {
  return NextResponse.json(
    { version: process.env.VERCEL_DEPLOYMENT_ID ?? "" },
    { headers: { "Cache-Control": "no-store, max-age=0" } },
  );
}

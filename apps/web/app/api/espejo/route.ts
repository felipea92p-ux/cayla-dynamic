import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

// "Puente" para el espejo a Google Sheets. El Apps Script llama aquí (con la llave
// como token); el servidor lee de Supabase (donde la llave sí funciona) y devuelve
// las filas ya listas (Resumen + Marcajes del mes) para volcarlas en la hoja.

const URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ESPEJO_TOKEN = process.env.ESPEJO_TOKEN;
const TZ = "America/Lima";

export const dynamic = "force-dynamic";

export async function GET(req: Request) {
  if (!URL || !SERVICE || !ESPEJO_TOKEN) return NextResponse.json({ error: "servidor sin configurar" }, { status: 500 });
  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!token || token !== ESPEJO_TOKEN) return NextResponse.json({ error: "no autorizado" }, { status: 401 });

  const sb = createClient(URL, SERVICE, { auth: { persistSession: false } });

  const hoy = new Intl.DateTimeFormat("en-CA", { timeZone: TZ }).format(new Date());
  const Y = Number(hoy.slice(0, 4)), M = Number(hoy.slice(5, 7));
  const diasMes = new Date(Y, M, 0).getDate();
  const p2 = (n: number) => String(n).padStart(2, "0");
  const ini = `${Y}-${p2(M)}-01`, fin = `${Y}-${p2(M)}-${p2(diasMes)}`;

  async function pageAll(build: () => any): Promise<any[]> {
    let out: any[] = [], from = 0; const L = 1000;
    while (true) {
      const { data, error } = await build().range(from, from + L - 1);
      if (error) throw new Error(error.message);
      out = out.concat(data ?? []);
      if (!data || data.length < L) break;
      from += L;
    }
    return out;
  }

  try {
    const personas = await pageAll(() => sb.from("personas").select("id,nombres,apellidos,estado,sedes:sede_base_id(codigo)"));
    const sedes = await pageAll(() => sb.from("sedes").select("id,codigo"));
    const jornadas = await pageAll(() => sb.from("jornadas").select("persona_id,fecha,horas_trabajadas,minutos_tarde").gte("fecha", ini).lte("fecha", fin));
    // Las marcas anuladas (mig. 0081) quedan fuera: la hoja debe reflejar el día
    // que cuenta para el pago, no el rastro de lo que se retiró. Si se colaran,
    // la hoja y la planilla contarían días distintos.
    const marcajes = await pageAll(() => sb.from("marcajes").select("persona_id,tipo,timestamp_marca,sede_id").is("anulada_at", null).gte("timestamp_marca", `${ini}T00:00:00-05:00`).lte("timestamp_marca", `${fin}T23:59:59-05:00`).order("timestamp_marca"));

    const sedeCod: Record<string, string> = {};
    sedes.forEach((s: any) => { sedeCod[s.id] = s.codigo; });
    const info: Record<string, { nombre: string; sede: string; activo: boolean }> = {};
    personas.forEach((p: any) => { info[p.id] = { nombre: `${p.nombres} ${p.apellidos}`, sede: p.sedes?.codigo ?? "?", activo: p.estado === "activo" }; });

    // Resumen: matriz persona × día del mes
    const horas: Record<string, { dias: Record<number, number>; total: number; tarde: number }> = {};
    jornadas.forEach((j: any) => {
      const d = Number(j.fecha.slice(8, 10));
      const r = horas[j.persona_id] || (horas[j.persona_id] = { dias: {}, total: 0, tarde: 0 });
      r.dias[d] = j.horas_trabajadas || 0; r.total += j.horas_trabajadas || 0; if (j.minutos_tarde) r.tarde++;
    });
    const head: any[] = ["Persona", "Sede"];
    for (let d = 1; d <= diasMes; d++) head.push(d);
    head.push("Total", "Tardanzas");
    const resumen: any[][] = [head];
    Object.keys(info).filter((id) => info[id].activo)
      .sort((a, b) => info[a].nombre.localeCompare(info[b].nombre))
      .forEach((id) => {
        const r = horas[id] || { dias: {}, total: 0, tarde: 0 };
        const fila: any[] = [info[id].nombre, info[id].sede];
        for (let d = 1; d <= diasMes; d++) fila.push(r.dias[d] ? Math.round(r.dias[d] * 100) / 100 : "");
        fila.push(Math.round(r.total * 100) / 100, r.tarde || "");
        resumen.push(fila);
      });

    // Marcajes crudos
    const fecha = (iso: string) => new Intl.DateTimeFormat("en-CA", { timeZone: TZ }).format(new Date(iso));
    const hora = (iso: string) => new Intl.DateTimeFormat("es-PE", { timeZone: TZ, hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(iso));
    const marc: any[][] = [["Fecha", "Hora", "Persona", "Sede", "Tipo"]];
    marcajes.forEach((mk: any) => {
      marc.push([fecha(mk.timestamp_marca), hora(mk.timestamp_marca), info[mk.persona_id]?.nombre ?? mk.persona_id, sedeCod[mk.sede_id] ?? "?", String(mk.tipo).replace(/_/g, " ")]);
    });

    return NextResponse.json(
      { resumen, marcajes: marc, actualizado: hoy },
      { headers: { "Cache-Control": "no-store" } },
    );
  } catch (e: any) {
    return NextResponse.json({ error: e.message ?? "error" }, { status: 500 });
  }
}

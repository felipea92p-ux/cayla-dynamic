// GENTE EN PISO FRENTE A LA VENTA — la tendencia de Inicio para una tienda: hora por hora, cuántas compras hubo,
// cuánta gente había en piso y cuánta pedía la venta, en las últimas cuatro semanas.
//
// PROMETE: para cada hora del día, el promedio de compras, de personas en piso y de lo que pedía la venta, y en
//   cuántos días hubo menos gente de la que pedía. Una hora con pocos días medidos no se juzga.
// ASUME: que cada día se arma con la misma regla que la repetición de Turnos (`personasDelDiaCerrado` y
//   `diaCompletoReal`, lib/admin/repeticion.ts): en piso es el peor cuarto de cada hora; lo que pedía la venta son
//   las compras de esa hora ÷ el ritmo de la tienda, nunca menos que su mínimo (0585). Esto no decide nada de eso:
//   solo junta días.
// NO HACE: decir quién faltaba. Ni nombres ni personas: horas.
//
// Una compra es un ticket completado de Retail (no soles ni prendas): es lo que mide el ritmo de la tienda.

import { cuentaEnCobertura, rangoDelDiaLima, fechaLima, type MarcajeDelDia } from "@cayla-dynamic/shared";
import type { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { AREA_DEFAULT, esOperativaEn, parseAreas } from "@/lib/areas";
import { esperadoDelDia, horarioVigente, type HorarioTramo, type TurnoDia } from "@/lib/admin/jornada-esperada";
import { leerPuestosResueltos } from "@/lib/puestos-resueltos";
import { aDecimal, PISO, puestoDesdeFilas, type PuestoDelDia } from "@/lib/admin/almacen";
import { diaCompletoReal, personasDelDiaCerrado, planDelDia, type HoraDelDiaReal } from "@/lib/admin/repeticion";
import { traerTodo } from "@/lib/admin/traer-todo";
import type { CambioUbicacion, Ubicacion } from "@/lib/terminal/ubicacion";

/** Cuántos días cerrados se miran: los mismos que usa Turnos para lo que pide la venta donde no hay meta. */
export const DIAS_DE_PISO = 28;
/** Una hora con menos días medidos que esto no se juzga: con tres días, un solo día malo es un tercio. */
export const MINIMO_DIAS_HORA = 4;

export interface DiaDePiso {
  fecha: string;
  horas: HoraDelDiaReal[];
}

export type TipoDeDia = "todos" | "semana" | "finde";

/** Lunes a viernes, o sábado y domingo. La fecha es de Lima; al mediodía UTC no cambia de día. */
export function esDelTipo(fecha: string, tipo: TipoDeDia): boolean {
  if (tipo === "todos") return true;
  const dow = new Date(`${fecha}T12:00:00Z`).getUTCDay();
  const finde = dow === 0 || dow === 6;
  return tipo === "finde" ? finde : !finde;
}

export interface HoraDePiso {
  hora: number;
  /** Días en que la tienda estuvo abierta a esa hora. */
  dias: number;
  /** Promedio, con un decimal. null si las compras no se pudieron leer. */
  compras: number | null;
  enPiso: number;
  pedia: number | null;
  /** Días en que hubo menos gente en piso de la que pedía la venta. */
  conFalta: number;
}

const unDecimal = (n: number) => Math.round(n * 10) / 10;

export function pisoPorHora(dias: readonly DiaDePiso[], tipo: TipoDeDia): HoraDePiso[] {
  const porHora = new Map<number, HoraDelDiaReal[]>();
  for (const d of dias) {
    if (!esDelTipo(d.fecha, tipo)) continue;
    for (const h of d.horas) porHora.set(h.hora, [...(porHora.get(h.hora) ?? []), h]);
  }
  return [...porHora.entries()]
    .sort((a, b) => a[0] - b[0])
    .map(([hora, hs]) => {
      const conVenta = hs.filter((h) => h.compras !== null);
      const conPedido = hs.filter((h) => h.pedia !== null);
      return {
        hora,
        dias: hs.length,
        compras: conVenta.length ? unDecimal(conVenta.reduce((s, h) => s + (h.compras ?? 0), 0) / conVenta.length) : null,
        enPiso: unDecimal(hs.reduce((s, h) => s + h.enPiso, 0) / hs.length),
        pedia: conPedido.length ? unDecimal(conPedido.reduce((s, h) => s + (h.pedia ?? 0), 0) / conPedido.length) : null,
        conFalta: hs.filter((h) => h.pedia !== null && h.enPiso < h.pedia).length,
      };
    });
}

/** La hora en que más seguido faltó gente (en proporción de sus días). Entre empatadas, la de más días con falta. */
export function horaMasCorta(horas: readonly HoraDePiso[]): HoraDePiso | null {
  let mejor: HoraDePiso | null = null;
  for (const h of horas) {
    if (h.dias < MINIMO_DIAS_HORA || h.conFalta === 0) continue;
    const r = h.conFalta / h.dias, rm = mejor ? mejor.conFalta / mejor.dias : -1;
    if (r > rm + 1e-9 || (Math.abs(r - rm) <= 1e-9 && mejor && h.conFalta > mejor.conFalta)) mejor = h;
  }
  return mejor;
}

/** ¿Faltó gente en esa hora la mitad de los días o más? Es la hora que se marca en el dibujo. */
export function faltaSeguido(h: HoraDePiso): boolean {
  return h.dias >= MINIMO_DIAS_HORA && h.conFalta * 2 >= h.dias;
}

// ── La lectura ───────────────────────────────────────────────────────────────

type Cliente = ReturnType<typeof createAdminSupabaseClient>;

function sumarDias(iso: string, n: number): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

export interface PisoYVenta {
  dias: DiaDePiso[];
  /** Las compras de retail no se pudieron leer: se dibuja la gente en piso, sin lo que pedía la venta. */
  comprasFallo: boolean;
  desde: string;
  hasta: string;
}

/**
 * Lee lo mismo que Turnos lee para repetir un día —el equipo de la sede, sus turnos y horarios, su almacén, sus
 * marcas y las compras de la tienda— para los últimos `DIAS_DE_PISO` días cerrados, y arma cada día con la regla
 * de Turnos. Lanza si falta algo sin lo cual el número de gente en piso mentiría; las compras, no: sin ellas se
 * dibuja la gente y se dice que la venta no se pudo leer.
 */
export async function traerPisoYVenta(supabase: Cliente, sede: { id: string; tipo: string | null }, hoy: string): Promise<PisoYVenta> {
  const desde = sumarDias(hoy, -DIAS_DE_PISO), hasta = sumarDias(hoy, -1);
  const inicio = rangoDelDiaLima(desde).inicio, fin = rangoDelDiaLima(hasta).fin;

  // El mismo equipo que la grilla de Turnos (un practicante cubre piso igual que cualquiera).
  const { data: pe, error: peErr } = await supabase.from("personas").select("id, nombres, apellidos, rol")
    .eq("sede_base_id", sede.id).eq("estado", "activo").eq("cuenta_de_servicio", false)
    .or("en_planilla.eq.true,tipo_vinculo.eq.practicante").eq("sueldo_fijo", false);
  if (peErr) throw new Error("No se pudo leer el equipo de la tienda.");
  const equipo = (pe ?? []) as { id: string; nombres: string; apellidos: string | null; rol: string }[];
  const ids = equipo.map((p) => p.id);
  if (ids.length === 0) return { dias: [], comprasFallo: false, desde, hasta };

  const [
    { data: f, error: fErr }, { data: ar, error: arErr }, { data: h, error: hErr }, { data: t, error: tErr },
    { data: pue, error: pueErr }, { data: cam, error: camErr }, { data: mar, error: marErr },
    { data: com, error: comErr }, { data: par }, { data: ven },
  ] = await Promise.all([
    supabase.rpc("fn_personas_funciones"),
    supabase.rpc("fn_areas"),
    supabase.from("horarios_asignados")
      .select("persona_id, hora_entrada, hora_salida, dias_laborables, horario_por_dia, almuerzo_min_minutos, vigente_desde, vigente_hasta")
      .in("persona_id", ids).lte("vigente_desde", hasta).or(`vigente_hasta.is.null,vigente_hasta.gte.${desde}`),
    traerTodo((a, b) => supabase.from("turnos").select("persona_id, fecha, hora_entrada, hora_salida, es_descanso")
      .in("persona_id", ids).gte("fecha", desde).lte("fecha", hasta).order("fecha").order("persona_id").range(a, b)),
    leerPuestosResueltos(supabase, desde, hasta),
    supabase.from("cambios_ubicacion" as never).select("persona_id, ubicacion, timestamp_cambio, vuelve_previsto")
      .eq("sede_id" as never, sede.id as never).is("anulado_at" as never, null)
      .gte("timestamp_cambio" as never, inicio as never).lte("timestamp_cambio" as never, fin as never),
    // Cuatro semanas de marcas pasan de las 1000 filas que corta PostgREST: se pide todo, en lotes.
    traerTodo((a, b) => supabase.from("marcajes").select("id, persona_id, tipo, timestamp_marca, fecha_jornada")
      .in("persona_id", ids).is("anulada_at", null).gte("timestamp_marca", inicio).lte("timestamp_marca", fin)
      .order("timestamp_marca").order("id").range(a, b)),
    supabase.rpc("fn_compras_por_hora", { p_sede_id: sede.id, p_desde: desde, p_hasta: hasta }),
    supabase.rpc("fn_cobertura_por_venta", { p_sede_id: sede.id }),
    // El horario de la tienda por día de la semana (0584). Si falla, no se descarta ninguna hora.
    supabase.rpc("fn_sede_ventana_semanal", { p_sede_id: sede.id }),
  ]);
  // Sin funciones, áreas, horarios, turnos, almacén o marcas, «cuántas había en piso» saldría inventado.
  if (fErr || arErr || hErr || tErr || pueErr || camErr || marErr) throw new Error("No se pudo leer lo marcado en la tienda.");

  const areas = parseAreas(ar, arErr);
  const funcion = new Map(((f as { persona_id: string; funcion: string; es_encargada_piso?: boolean; tipo_vinculo?: string | null }[] | null) ?? [])
    .map((x) => [x.persona_id, x] as const));
  const personas = equipo.map((p) => {
    const x = funcion.get(p.id);
    const c = cuentaEnCobertura(
      { rol: p.rol as Parameters<typeof cuentaEnCobertura>[0]["rol"], tipoVinculo: x?.tipo_vinculo ?? null, esEncargadaPiso: Boolean(x?.es_encargada_piso), areaOperativa: esOperativaEn(areas, x?.funcion ?? AREA_DEFAULT) },
      sede.tipo,
    );
    return { id: p.id, nombre: p.nombres, cuenta: c.cuentaEnMetaOp, lider: c.lider };
  });

  const horarios = new Map<string, HorarioTramo[]>();
  for (const x of (h ?? []) as HorarioTramo[]) horarios.set(x.persona_id, [...(horarios.get(x.persona_id) ?? []), x]);
  const turnos = new Map(((t ?? []) as (TurnoDia & { persona_id: string; fecha: string })[]).map((x) => [`${x.persona_id}|${x.fecha}`, x as TurnoDia]));
  const filasPuesto = new Map<string, { desde: string | null; hasta: string | null }[]>();
  for (const x of pue ?? []) {
    const k = `${x.persona_id}|${x.fecha}`;
    filasPuesto.set(k, [...(filasPuesto.get(k) ?? []), { desde: x.desde, hasta: x.hasta }]);
  }
  const puestos = new Map<string, PuestoDelDia>([...filasPuesto].map(([k, filas]) => [k, puestoDesdeFilas(filas)]));
  const cambios = new Map<string, CambioUbicacion[]>();
  for (const x of (cam ?? []) as unknown as { persona_id: string; ubicacion: Ubicacion; timestamp_cambio: string; vuelve_previsto: string | null }[]) {
    const k = `${x.persona_id}|${fechaLima(x.timestamp_cambio)}`;
    cambios.set(k, [...(cambios.get(k) ?? []), { ubicacion: x.ubicacion, timestamp: x.timestamp_cambio, vuelvePrevisto: x.vuelve_previsto }]);
  }
  const marcajes = new Map<string, MarcajeDelDia[]>();
  for (const x of (mar ?? []) as { persona_id: string; tipo: MarcajeDelDia["tipo"]; timestamp_marca: string; fecha_jornada: string | null }[]) {
    const k = `${x.persona_id}|${x.fecha_jornada ?? fechaLima(x.timestamp_marca)}`;
    marcajes.set(k, [...(marcajes.get(k) ?? []), { tipo: x.tipo, timestamp: x.timestamp_marca }]);
  }
  const compras = new Map<string, Map<number, number>>();
  for (const x of (com ?? []) as { fecha: string; hora: number; compras: number }[]) {
    const m = compras.get(x.fecha) ?? new Map<number, number>();
    m.set(x.hora, x.compras);
    compras.set(x.fecha, m);
  }
  const parametros = ((par as { ritmo: number; minimo: number }[] | null) ?? [])[0] ?? null;
  const ventana = new Map(((ven as { dia: number; abre: string; cierra: string }[] | null) ?? [])
    .map((v) => [Number(v.dia), { abre: aDecimal(v.abre), cierra: aDecimal(v.cierra) }] as const));
  const comprasFallo = Boolean(comErr);

  const dias: DiaDePiso[] = [];
  const ahora = new Date();
  for (let fecha = desde; fecha <= hasta; fecha = sumarDias(fecha, 1)) {
    // Un día sin ninguna marca de la tienda no se promedia: estuvo cerrada, o no hay qué medir.
    if (!ids.some((id) => marcajes.has(`${id}|${fecha}`))) continue;
    const medianocheIso = rangoDelDiaLima(fecha).inicio;
    const personasDia = personasDelDiaCerrado({
      personas, medianocheIso, ahora,
      planDe: (id) => planDelDia(esperadoDelDia(fecha, turnos.get(`${id}|${fecha}`) ?? null, horarioVigente(horarios.get(id) ?? [], fecha))),
      puestoDe: (id) => puestos.get(`${id}|${fecha}`) ?? PISO,
      cambiosDe: (id) => cambios.get(`${id}|${fecha}`) ?? [],
      marcajesDe: (id) => marcajes.get(`${id}|${fecha}`) ?? [],
    });
    const delDia = compras.get(fecha);
    const deHoy = ventana.get(new Date(`${fecha}T12:00:00Z`).getUTCDay());
    dias.push({
      fecha,
      horas: diaCompletoReal({
        personas: personasDia, medianocheIso,
        comprasDe: comprasFallo ? null : (hora) => delDia?.get(hora) ?? 0,
        parametros: comprasFallo ? null : (parametros ? { ritmo: Number(parametros.ritmo), minimo: Number(parametros.minimo) } : null),
        ventana: deHoy,
      // Aquí, a diferencia de la repetición de Turnos, la hora que no se juzga ni se dibuja: promediar la media hora
      // en que el equipo va llegando no dice nada de cómo se atiende.
      }).filter((h) => h.juzgada),
    });
  }
  return { dias, comprasFallo, desde, hasta };
}

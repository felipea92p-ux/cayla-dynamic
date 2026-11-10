"use client";

import { useEffect, useMemo, useState } from "react";
import type { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { hoyLima, sumarDias } from "@cayla-dynamic/shared";
import { Filtro } from "@/components/ui/filtro";
import { Insignia } from "@/components/ui/insignia";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Cargando } from "@/components/cargando";
import { dowDe, type HorarioTramo, type TurnoDia } from "@/lib/admin/jornada-esperada";
import {
  armarSemana, cuadreDeSemana, deQue, inclinacionDeSemana, lunesDe, textoHoras,
  textoRotacion, totalDeSemana, type DiaDeMiSemana, type PuestoFila,
} from "@/lib/mi-semana";
import { esPiso, textoPuesto } from "@/lib/admin/almacen";
import { leerPuestosResueltos } from "@/lib/puestos-resueltos";

/**
 * «Tu semana», en «Lo mío · Mis turnos».
 *
 * QUÉ PROMETE · los siete días de la semana anterior, esta o la próxima, cada
 *               uno con su horario, sus horas, si lleva refrigerio, si descansa
 *               y en qué puesto (piso o almacén); el total contra su horario de
 *               siempre y, si no cuadra, por qué preguntar. Las reglas viven en
 *               lib/mi-semana.ts, con sus pruebas.
 * QUÉ ASUME   · la RLS le deja leer sus filas de `turnos`, `horarios_asignados`
 *               y `feriados` (las mismas que ya leía la sección vieja), y su plan
 *               de piso/almacén por `fn_puestos_resueltos` (0588).
 *
 * Pide sus propios datos —tres semanas fijas alrededor de hoy— en vez de
 * colgarse de los de «Mis días», que cambian con el rango que ella elige allá:
 * si eligiera el mes pasado, el Resumen no sabría qué le toca hoy.
 */

type Cliente = ReturnType<typeof createAdminSupabaseClient>;
export type Desfase = -1 | 0 | 1;

export interface MiSemana {
  cargando: boolean;
  error: string | null;
  hoy: string;
  semanas: Record<Desfase, DiaDeMiSemana[]>;
  /** La jornada que fijó DO (0584), o null. */
  jornada: number | null;
}

const VACIA: Record<Desfase, DiaDeMiSemana[]> = { [-1]: [], 0: [], 1: [] };

export function useMiSemana(supabase: Cliente, personaId: string | null): MiSemana {
  const hoy = hoyLima();
  const lunes = lunesDe(hoy);
  const [estado, setEstado] = useState<MiSemana>({ cargando: true, error: null, hoy, semanas: VACIA, jornada: null });

  useEffect(() => {
    if (!personaId) return;
    let vivo = true;
    void (async () => {
    const desde = sumarDias(lunes, -7);
    const hasta = sumarDias(lunes, 13);
    const [{ data: hs, error: errHs }, { data: ts, error: errTs }, { data: fer }, puestos, { data: yo }] = await Promise.all([
      supabase.from("horarios_asignados")
        .select("persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida, dias_laborables, horario_por_dia, almuerzo_min_minutos")
        .eq("persona_id", personaId)
        .lte("vigente_desde", hasta).or(`vigente_hasta.is.null,vigente_hasta.gte.${desde}`),
      supabase.from("turnos")
        .select("fecha, hora_entrada, hora_salida, es_descanso")
        .eq("persona_id", personaId)
        .gte("fecha", desde).lte("fecha", hasta),
      supabase.from("feriados").select("fecha, nombre").gte("fecha", desde).lte("fecha", hasta),
      leerPuestos(supabase, personaId, desde, hasta),
      // Si la 0584 todavía no estuviera, la columna no existe: falla sola y queda
      // en null, que es «comparar con el horario».
      supabase.from("personas").select("jornada_semanal_horas").eq("id", personaId).maybeSingle(),
    ]);
    if (!vivo) return;
    if (errHs || errTs) {
      setEstado({ cargando: false, error: "No se pudo leer tu horario. Vuelve a intentarlo en un momento.", hoy, semanas: VACIA, jornada: null });
      return;
    }
    const tramos = (hs as unknown as HorarioTramo[]) ?? [];
    const turnos = new Map(((ts satisfies (TurnoDia & { fecha: string })[]) ?? []).map((t) => [t.fecha, t]));
    const feriados = new Map(((fer as { fecha: string; nombre: string }[] | null) ?? []).map((f) => [f.fecha, f.nombre]));
    const semana = (d: Desfase) => armarSemana({ lunes: sumarDias(lunes, 7 * d), turnos, tramos, feriados, puestos });
    setEstado({
      cargando: false, error: null, hoy, semanas: { [-1]: semana(-1), 0: semana(0), 1: semana(1) },
      jornada: (yo?.jornada_semanal_horas as number | null | undefined) ?? null,
    });
    })();
    return () => { vivo = false; };
  }, [supabase, personaId, lunes, hoy]);
  return estado;
}

/**
 * Lo planificado de piso/almacén, ya resuelto con su puesto base (0588): la
 * lectura única de `lib/puestos-resueltos.ts`, que nunca lee la tabla directo.
 * Cualquier error devuelve null, que la pantalla entiende como «no se sabe» y
 * calla el puesto: no afirmar un puesto que no se leyó.
 */
async function leerPuestos(supabase: Cliente, personaId: string, desde: string, hasta: string): Promise<PuestoFila[] | null> {
  try {
    const { data, error } = await leerPuestosResueltos(supabase, desde, hasta, { personaId });
    if (error || !data) return null;
    return data.map((f) => ({ fecha: f.fecha, desde: f.desde, hasta: f.hasta }));
  } catch {
    return null;
  }
}

const DIAS_CORTOS = ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"];
const MESES = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "set", "oct", "nov", "dic"];

function diaMes(iso: string): string {
  const [, m, d] = iso.split("-").map(Number);
  return `${d} ${MESES[m - 1]}`;
}

const ETIQUETA: Record<Desfase, string> = { [-1]: "Anterior", 0: "Esta semana", 1: "Próxima" };

export function TuSemana({ datos }: { datos: MiSemana }) {
  const [desfase, setDesfase] = useState<Desfase>(0);
  const dias = datos.semanas[desfase];
  const total = useMemo(() => totalDeSemana(dias, datos.jornada), [dias, datos.jornada]);
  const cuadre = cuadreDeSemana(total);
  const rotacion = desfase === 0
    ? textoRotacion(inclinacionDeSemana(datos.semanas[0]), inclinacionDeSemana(datos.semanas[1]))
    : null;

  if (datos.cargando) return <Cargando />;
  if (datos.error) return <BannerAviso variante="alerta">{datos.error}</BannerAviso>;

  const sinNada = dias.every((d) => d.esperado.origen === "sin_horario");
  const pct = total.referencia ? Math.min(100, (total.horas / total.referencia) * 100) : 0;

  return (
    <div className="flex flex-col gap-4">
      <div role="group" aria-label="Qué semana ver" className="flex flex-wrap gap-2">
        {([-1, 0, 1] as Desfase[]).map((d) => (
          <Filtro key={d} activo={d === desfase} tamano="sm" onClick={() => setDesfase(d)}>{ETIQUETA[d]}</Filtro>
        ))}
      </div>

      {dias.length > 0 && (
        <p className="text-sm text-taupe">Del {diaMes(dias[0].fecha)} al {diaMes(dias[6].fecha)}.</p>
      )}

      {sinNada ? (
        <p className="text-sm text-taupe">
          No hay turnos ni horario cargados para esta semana. Si eso no es lo que esperabas, avísale a tu líder de equipo.
        </p>
      ) : (
        <>
          <div data-tour="mio-turnos-total" className="flex flex-col gap-2 rounded-control bg-hueso p-3">
            <span className="text-xs font-medium uppercase tracking-wide text-taupe">Horas de la semana</span>
            <div className="font-serif text-3xl leading-none">
              {textoHoras(total.horas)}
              {total.referencia !== null && (
                <span className="ml-2 font-sans text-sm text-taupe">de {textoHoras(total.referencia)} {deQue(total)}</span>
              )}
            </div>
            {total.referencia !== null && total.referencia > 0 && (
              <div className="h-1.5 overflow-hidden rounded-full bg-sand" aria-hidden>
                <div className={`h-full ${cuadre?.tono === "positivo" ? "bg-verde" : "bg-ambar"}`} style={{ width: `${pct}%` }} />
              </div>
            )}
            <span className="text-xs text-taupe">
              {total.diasDeTrabajo} {total.diasDeTrabajo === 1 ? "día" : "días"} de trabajo y {7 - total.diasDeTrabajo} de descanso.
              {rotacion ? ` ${rotacion}` : ""}
            </span>
          </div>

          {cuadre && cuadre.tono === "advertencia" && (
            <BannerAviso variante="advertencia" role="status">{cuadre.texto}</BannerAviso>
          )}

          <ul data-tour="mio-turnos-semana" className="flex flex-col gap-1.5">
            {dias.map((d) => <FilaDia key={d.fecha} dia={d} esHoy={d.fecha === datos.hoy} />)}
          </ul>

          {desfase === 1 && (
            <p className="text-xs text-taupe">
              La próxima semana todavía puede cambiar. Si tu líder de equipo la ajusta, lo verás aquí.
            </p>
          )}
        </>
      )}
    </div>
  );
}

function FilaDia({ dia, esHoy }: { dia: DiaDeMiSemana; esHoy: boolean }) {
  const { esperado: e, base } = dia;
  const dow = DIAS_CORTOS[dowDe(dia.fecha)];
  const cambiaDelHorario = e.origen === "turno" && base.origen !== "sin_horario"
    && (e.trabaja !== base.trabaja || e.entrada !== base.entrada || e.salida !== base.salida);

  const marco = !e.trabaja
    ? "border border-dashed border-sand text-taupe"
    : esHoy ? "border border-tinta bg-papel" : "bg-hueso";

  return (
    <li className={`grid grid-cols-[3.5rem_1fr_auto] items-center gap-3 rounded-control px-3 py-2 ${marco}`}>
      <span className="font-medium">
        {dow}
        <span className="block text-[11px] font-normal text-taupe">{diaMes(dia.fecha)}{esHoy ? " · hoy" : ""}</span>
      </span>
      {e.trabaja ? (
        <span className="tabular-nums">
          {e.entrada}{e.salida ? `–${e.salida}` : ""}
          <span className="block text-xs text-taupe">
            {textoHoras(e.horas)}
            {(e.refrigerioMin ?? 0) > 0 ? ` · ${e.refrigerioMin} min de refrigerio` : ""}
            {cambiaDelHorario ? " · cambia de tu horario" : ""}
            {dia.feriado ? ` · feriado: ${dia.feriado}` : ""}
          </span>
        </span>
      ) : (
        <span>
          Descanso
          {(cambiaDelHorario || dia.feriado) && (
            <span className="block text-xs">
              {cambiaDelHorario ? "Cambia de tu horario." : ""}{dia.feriado ? ` Feriado: ${dia.feriado}.` : ""}
            </span>
          )}
        </span>
      )}
      <span>
        {e.trabaja && dia.puesto && (
          <Insignia variante={esPiso(dia.puesto) ? "positivo" : "informativo"}>{textoPuesto(dia.puesto)}</Insignia>
        )}
      </span>
    </li>
  );
}

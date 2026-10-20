"use client";

// ============================================================================
// «Jornada» del Dashboard: cómo fue el día de cada quien y cuánto almorzó
// ============================================================================
// QUÉ PROMETE   · por sede, el día de cada persona que marcó: a qué hora entró, cuándo salió a almorzar, cuánto fue, si sigue
//                 almorzando y cuándo salió. Sirve para ver cuánto se toma de almuerzo cada quien, que hasta hoy solo se veía
//                 abriendo Correcciones persona por persona.
// QUÉ ASUME     · que las marcas de almuerzo ya vienen sin las anuladas; el día es el de Lima. El tiempo permitido sale del
//                 horario de ese día (`refrigerio_min`): si es 0 o no se conoce, NO se compara (sin vara no hay «se pasó»).
//
// CÓMO SE ORDENA (decidido con Felipe el 2026-10-20, maqueta «Diseño 1»)
//   · «Para atender» arriba: almorzando ahora, se pasó del tiempo, volvió tarde. Tocar una pastilla deja solo esas personas.
//   · Un grupo plegable por sede, con su resumen a la vista aunque esté cerrado (cuántos almuerzan, cuántos se pasaron, el promedio).
//   · Dentro: la línea del día (barra de entrada a salida con el almuerzo rayado) o una tabla; se cambia con dos íconos.
//   · CCO y Desarrollo Organizacional son independientes: no cuentan en las tiendas y van AL FINAL, aparte, separados por área.
//
// No guarda nada. Lo de hoy se refresca cada minuto; la historia de otro día se pide una vez.
// ============================================================================

import { useCallback, useEffect, useMemo, useState } from "react";
import { ChevronDown, ChevronRight, Table2, AlignLeft } from "lucide-react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { fechaLima, horaDecimalLima, horaLima, hoyLima, rangoDelDiaLima } from "@cayla-dynamic/shared";
import { Cargando } from "@/components/cargando";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { BotonIcono } from "@/components/ui/boton-icono";
import { CampoSelect } from "@/components/ui/campo";
import { EstadoVacio } from "@/components/ui/estado-vacio";
import { Filtro } from "@/components/ui/filtro";
import { Insignia } from "@/components/ui/insignia";
import { ParaAtender } from "@/components/ui/para-atender";
import { Fila, Tabla, TablaEncabezado, Th } from "@/components/ui/tabla";
import { cx } from "@/components/ui/cx";
import { addDias } from "@/lib/admin/incidencias";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { useFiltroGuardado } from "@/lib/admin/use-filtro-guardado";
import {
  almuerzosPorDia, estadoDelDia, llaveDia, minutosDeAlmuerzo, minutosEntre, sePaso, TIPOS_DE_ALMUERZO,
  type AlmuerzoDelDia, type EstadoDelDia,
} from "@/lib/admin/almuerzo";
import { parseAreas, areaNombre, AREA_DEFAULT } from "@/lib/areas";

interface FilaJornada {
  id: string;
  nombre: string;
  sedeCodigo: string;
  /** `sedes.tipo`: «central» es una oficina (CCO), el resto son tiendas o talleres. */
  sedeTipo: string | null;
  area: string;
  entradaTs: string;
  salidaTs: string | null;
  almuerzo: AlmuerzoDelDia | null;
  /** Minutos de refrigerio que le daba su horario ese día; null si no se conoce o es 0. */
  permitido: number | null;
}

const OFICINAS = "oficinas";
const ETIQUETA_ESTADO: Record<EstadoDelDia, { texto: string; variante: "positivo" | "advertencia" | "neutral" }> = {
  trabajando: { texto: "Trabajando", variante: "positivo" },
  almorzando: { texto: "Almorzando", variante: "advertencia" },
  termino: { texto: "Terminó", variante: "neutral" },
};

const dur = (m: number) => (m >= 60 ? `${Math.floor(m / 60)} h${m % 60 ? ` ${String(m % 60).padStart(2, "0")}` : ""}` : `${m} min`);
const enMinutosDelDia = (ts: string) => Math.round(horaDecimalLima(ts) * 60);

export function PanelJornada({ sedes: sedesDeAlcance }: { sedes?: { codigo: string; nombre: string }[] }) {
  const hoy = hoyLima();
  const [dia, setDia] = useState(hoy);
  const [vista, setVista] = useFiltroGuardado<"linea" | "tabla">("dashboard.jornada.vista", "tabla");
  const [sedeSel, setSedeSel] = useState<string>("todas");
  const [solo, setSolo] = useState<"" | "almorzando" | "paso" | "tarde">("");
  const [abiertas, setAbiertas] = useState<Record<string, boolean>>({});
  const [filas, setFilas] = useState<FilaJornada[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [ahoraTs, setAhoraTs] = useState(() => new Date().toISOString());

  const esHoy = dia === hoy;

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { inicio, fin } = rangoDelDiaLima(dia);
    const [pers, sedesQ, funciones, areasQ, jornadas, marcas] = await Promise.all([
      supabase.from("personas").select("id, nombres, apellidos, sede_base_id")
        .eq("estado", "activo").eq("cuenta_de_servicio", false)
        // Mismo criterio que «Hoy»: quien cobra fijo no marca, y a los RxH no se les mide jornada.
        .or("en_planilla.eq.true,tipo_vinculo.eq.practicante").eq("sueldo_fijo", false).order("nombres"),
      supabase.from("sedes").select("id, codigo, tipo"),
      supabase.rpc("fn_personas_funciones"),
      supabase.rpc("fn_areas"),
      supabase.from("jornadas").select("persona_id, entrada_ts, salida_final_ts, horario_aplicado").eq("fecha", dia),
      supabase.from("marcajes").select("persona_id, tipo, timestamp_marca")
        .in("tipo", [...TIPOS_DE_ALMUERZO]).is("anulada_at", null).gte("timestamp_marca", inicio).lt("timestamp_marca", fin).limit(5000),
    ]);
    // Lo imprescindible: sin personas, sedes o jornadas no hay pantalla. Lo blando (áreas, almuerzos) degrada: sin almuerzos
    // la línea se dibuja sin la franja, y eso se avisa; nunca como «nadie almorzó».
    const falla = pers.error ?? sedesQ.error ?? jornadas.error;
    if (falla) { setError(mensajeDeError(falla, "cargar la jornada")); return; }
    const areas = parseAreas(areasQ.data, areasQ.error);
    const funcionDe = new Map(((funciones.data as { persona_id: string; funcion: string }[] | null) ?? []).map((f) => [f.persona_id, f.funcion]));
    const sedeDe = new Map(((sedesQ.data as { id: string; codigo: string; tipo: string | null }[] | null) ?? []).map((s) => [s.id, s]));
    const jornadaDe = new Map(((jornadas.data as { persona_id: string; entrada_ts: string | null; salida_final_ts: string | null; horario_aplicado: { refrigerio_min?: number } | null }[] | null) ?? []).map((j) => [j.persona_id, j]));
    const almuerzos = marcas.error ? new Map<string, AlmuerzoDelDia>() : almuerzosPorDia((marcas.data as { persona_id: string; tipo: string; timestamp_marca: string }[] | null) ?? []);

    const out: FilaJornada[] = [];
    for (const p of (pers.data as { id: string; nombres: string; apellidos: string; sede_base_id: string | null }[] | null) ?? []) {
      const j = jornadaDe.get(p.id);
      if (!j?.entrada_ts) continue; // quien no marcó entrada ese día no tiene jornada que dibujar
      const s = p.sede_base_id ? sedeDe.get(p.sede_base_id) : undefined;
      const r = Number(j.horario_aplicado?.refrigerio_min ?? 0);
      out.push({
        id: p.id, nombre: `${p.nombres} ${p.apellidos}`, sedeCodigo: s?.codigo ?? "—", sedeTipo: s?.tipo ?? null,
        area: areaNombre(areas, funcionDe.get(p.id) ?? AREA_DEFAULT),
        entradaTs: j.entrada_ts, salidaTs: j.salida_final_ts,
        almuerzo: almuerzos.get(llaveDia(p.id, dia)) ?? null,
        permitido: r > 0 ? r : null,
      });
    }
    setFilas(out);
    setError(marcas.error ? "No se pudieron traer las marcas de almuerzo: las barras se ven sin ellas." : null);
    setAhoraTs(new Date().toISOString());
  }, [dia]);

  // eslint-disable-next-line react-hooks/set-state-in-effect -- pedir el día al cambiarlo; el estado se pone después del await.
  useEffect(() => { void cargar(); }, [cargar]);
  // Lo de hoy corre: el cronómetro del almuerzo en curso y quién acaba de volver.
  useEffect(() => {
    if (!esHoy) return;
    const t = setInterval(() => void cargar(), 60_000);
    return () => clearInterval(t);
  }, [esHoy, cargar]);

  const datos = useMemo(() => (filas ?? []).map((f) => {
    const estado = esHoy ? estadoDelDia({ salidaTs: f.salidaTs, almuerzo: f.almuerzo }) : f.salidaTs ? "termino" as const : "trabajando" as const;
    const minutos = minutosDeAlmuerzo(f.almuerzo, ahoraTs);
    return { f, estado, minutos, paso: sePaso(minutos, f.permitido) };
  }), [filas, esHoy, ahoraTs]);

  const conteo = {
    almorzando: datos.filter((d) => d.estado === "almorzando").length,
    paso: datos.filter((d) => d.paso).length,
    tarde: datos.filter((d) => d.paso && d.f.almuerzo?.volvioTs).length,
  };

  const visibles = datos.filter((d) =>
    (solo === "" || (solo === "almorzando" && d.estado === "almorzando") || (solo === "paso" && d.paso) || (solo === "tarde" && d.paso && d.f.almuerzo?.volvioTs))
    && (sedeSel === "todas" || (sedeSel === OFICINAS ? d.f.sedeTipo === "central" : d.f.sedeTipo !== "central" && d.f.sedeCodigo === sedeSel)));

  // Tiendas y talleres, un grupo por sede; las oficinas, al final y por área.
  const tiendas = visibles.filter((d) => d.f.sedeTipo !== "central");
  const oficinas = visibles.filter((d) => d.f.sedeTipo === "central");
  const codigosTienda = useMemo(() => {
    const delAlcance = (sedesDeAlcance ?? []).map((s) => s.codigo);
    const presentes = [...new Set(datos.filter((d) => d.f.sedeTipo !== "central").map((d) => d.f.sedeCodigo))];
    return [...new Set([...delAlcance, ...presentes])].filter((c) => presentes.includes(c)).sort((a, b) => a.localeCompare(b, "es"));
  }, [datos, sedesDeAlcance]);
  const hayOficinas = datos.some((d) => d.f.sedeTipo === "central");

  const dias = useMemo(() => Array.from({ length: 7 }, (_, i) => addDias(hoy, -i)), [hoy]);
  const etiquetaDia = (iso: string) => {
    if (iso === hoy) return "Hoy";
    const [y, m, d] = iso.split("-").map(Number);
    return new Intl.DateTimeFormat("es-PE", { weekday: "long", day: "numeric", month: "long", timeZone: "UTC" }).format(new Date(Date.UTC(y, m - 1, d)));
  };

  // El eje de la línea: de la hora entera anterior a la primera entrada a la siguiente a la última salida (o a «ahora»).
  const eje = useMemo(() => {
    const minimos = datos.map((d) => enMinutosDelDia(d.f.entradaTs));
    const maximos = datos.map((d) => (d.f.salidaTs ? enMinutosDelDia(d.f.salidaTs) : esHoy ? enMinutosDelDia(ahoraTs) : enMinutosDelDia(d.f.entradaTs) + 480));
    const ini = Math.min(8 * 60, Math.floor(Math.min(...minimos, 8 * 60) / 60) * 60);
    const fin = Math.max(19 * 60, Math.ceil(Math.max(...maximos, 19 * 60) / 60) * 60);
    return { ini, fin };
  }, [datos, esHoy, ahoraTs]);
  const pct = (min: number) => ((min - eje.ini) / (eje.fin - eje.ini)) * 100;
  const horasEje = useMemo(() => {
    const out: number[] = [];
    for (let h = eje.ini / 60; h <= eje.fin / 60; h++) out.push(h);
    return out;
  }, [eje]);

  const resumenDe = (ds: typeof datos) => {
    const ms = ds.map((d) => d.minutos).filter((m): m is number => m !== null && ds.find((x) => x.minutos === m)?.estado !== "almorzando");
    return {
      almorzando: ds.filter((d) => d.estado === "almorzando").length,
      paso: ds.filter((d) => d.paso).length,
      promedio: ms.length ? Math.round(ms.reduce((a, b) => a + b, 0) / ms.length) : null,
    };
  };

  const linea = (ds: typeof datos) => {
    return (
      <div className="px-4 pb-3">
        <div className="grid grid-cols-[10rem_1fr] items-end pt-2 text-[11px] text-taupe">
          <span />
          <div className="relative h-4">
            {horasEje.map((h) => <span key={h} className="absolute -translate-x-1/2" style={{ left: `${pct(h * 60)}%` }}>{h}</span>)}
          </div>
        </div>
        {ds.map(({ f, estado, minutos, paso }) => {
          const e = enMinutosDelDia(f.entradaTs);
          const fin = f.salidaTs ? enMinutosDelDia(f.salidaTs) : esHoy ? enMinutosDelDia(ahoraTs) : e;
          const sa = f.almuerzo ? enMinutosDelDia(f.almuerzo.salioTs) : null;
          const ra = f.almuerzo?.volvioTs ? enMinutosDelDia(f.almuerzo.volvioTs) : null;
          const finAlm = ra ?? (esHoy && sa !== null ? enMinutosDelDia(ahoraTs) : sa);
          const trozo = (a: number, b: number) => ({ left: `${pct(a)}%`, width: `${Math.max(0, pct(b) - pct(a))}%` });
          return (
            <div key={f.id} className="grid grid-cols-[10rem_1fr] items-center border-t border-sand py-1.5">
              <div className="min-w-0 pr-2 text-sm leading-tight">
                <span className="block truncate font-medium text-tinta">{f.nombre}</span>
                <span className="block truncate text-xs text-taupe">{horaLima(f.entradaTs)}{f.salidaTs ? ` – ${horaLima(f.salidaTs)}` : ""}</span>
              </div>
              <div
                className="relative h-6"
                style={{ backgroundImage: "repeating-linear-gradient(90deg, transparent 0, transparent calc(100% / var(--n) - 1px), var(--color-sand) calc(100% / var(--n) - 1px), var(--color-sand) calc(100% / var(--n)))", ["--n" as string]: horasEje.length - 1 }}
                role="img"
                aria-label={`${f.nombre}: entró ${horaLima(f.entradaTs)}${f.almuerzo ? `, almorzó ${minutos} minutos` : ", sin almuerzo marcado"}${estado === "almorzando" ? ", almorzando ahora" : ""}`}
              >
                {sa !== null && finAlm !== null ? (
                  <>
                    <div className="absolute top-0.5 h-5 rounded bg-[color-mix(in_oklab,var(--color-tinta)_80%,var(--color-papel))]" style={trozo(e, sa)} />
                    <div
                      className={cx("absolute top-0.5 grid h-5 place-items-center overflow-hidden whitespace-nowrap rounded border text-[10px] font-bold", paso ? "border-rojo-profundo text-rojo-profundo" : "border-ambar text-ambar")}
                      style={{ ...trozo(sa, finAlm), backgroundImage: "repeating-linear-gradient(135deg, color-mix(in oklab, var(--color-ambar) 50%, var(--color-papel)) 0 5px, color-mix(in oklab, var(--color-ambar) 24%, var(--color-papel)) 5px 10px)" }}
                      title={`Almuerzo ${horaLima(f.almuerzo!.salioTs)}${f.almuerzo!.volvioTs ? ` – ${horaLima(f.almuerzo!.volvioTs)}` : " (sin regreso todavía)"}`}
                    >
                      {minutos !== null ? dur(minutos) : ""}{ra === null ? " …" : ""}
                    </div>
                    {ra !== null && fin > ra && <div className="absolute top-0.5 h-5 rounded bg-[color-mix(in_oklab,var(--color-tinta)_80%,var(--color-papel))]" style={trozo(ra, fin)} />}
                  </>
                ) : (
                  <div className="absolute top-0.5 h-5 rounded bg-[color-mix(in_oklab,var(--color-tinta)_80%,var(--color-papel))]" style={trozo(e, fin)} />
                )}
                {esHoy && !f.salidaTs && <div className="absolute inset-y-0 w-0.5 bg-rojo" style={{ left: `${pct(enMinutosDelDia(ahoraTs))}%` }} />}
              </div>
            </div>
          );
        })}
      </div>
    );
  }

  const tablaDia = (ds: typeof datos) => {
    return (
      <Tabla className="rounded-none border-0 [font-variant-numeric:tabular-nums]">
        <TablaEncabezado>
          <Th>Persona</Th><Th>Entró</Th><Th>Salió a almorzar</Th><Th>Volvió</Th><Th>Almuerzo</Th><Th>Salida</Th><Th>Estado</Th>
        </TablaEncabezado>
        <tbody>
          {ds.map(({ f, estado, minutos, paso }) => (
            <Fila key={f.id}>
              <td className="px-4 py-2"><span className="font-medium">{f.nombre}</span></td>
              <td className="px-4 py-2">{horaLima(f.entradaTs)}</td>
              <td className="px-4 py-2">{f.almuerzo ? horaLima(f.almuerzo.salioTs) : <span className="text-taupe/50">—</span>}</td>
              <td className="px-4 py-2">
                {f.almuerzo?.volvioTs ? horaLima(f.almuerzo.volvioTs) : f.almuerzo ? <Insignia variante="advertencia" tamano="sm" punto={false}>{esHoy ? "aún no" : "sin regreso"}</Insignia> : <span className="text-taupe/50">—</span>}
              </td>
              <td className="px-4 py-2">
                {minutos === null ? <span className="text-taupe/50">—</span> : (
                  <span className={paso ? "text-rojo" : undefined}>
                    <b className="font-medium">{dur(minutos)}</b>
                    {paso && f.permitido && <span className="ml-1 text-xs">+{minutos - f.permitido}</span>}
                  </span>
                )}
              </td>
              <td className="px-4 py-2">{f.salidaTs ? horaLima(f.salidaTs) : <span className="text-taupe/50">—</span>}</td>
              <td className="px-4 py-2"><Insignia variante={ETIQUETA_ESTADO[estado].variante} tamano="sm">{ETIQUETA_ESTADO[estado].texto}</Insignia></td>
            </Fila>
          ))}
        </tbody>
      </Tabla>
    );
  }

  const cuerpo = (ds: typeof datos) => (vista === "linea" ? linea(ds) : tablaDia(ds));

  const grupo = (clave: string, titulo: string, ds: typeof datos, opciones: { nota?: string; hijos?: React.ReactNode } = {}) => {
    const { nota, hijos } = opciones;
    // Todo arranca cerrado (a pedido de Felipe, 2026-10-20), también al elegir una sede o un aviso: se abre con un toque.
    const abierto = abiertas[clave] ?? false;
    const r = resumenDe(ds);
    const Chevron = abierto ? ChevronDown : ChevronRight;
    return (
      <section key={clave} className="rounded-superficie border border-sand bg-crema/40">
        <button type="button" aria-expanded={abierto} onClick={() => setAbiertas((a) => ({ ...a, [clave]: !abierto }))} className="flex w-full items-center justify-between gap-3 px-4 py-3 text-left">
          <span className="flex min-w-0 items-center gap-2">
            <Chevron size={16} strokeWidth={1.8} className="shrink-0 text-taupe" aria-hidden />
            <span className="font-serif text-lg text-tinta">{titulo}</span>
            <span className="text-sm text-taupe">· {ds.length} {ds.length === 1 ? "persona" : "personas"}{nota ? ` · ${nota}` : ""}</span>
          </span>
          <span className="flex shrink-0 flex-wrap items-center justify-end gap-1.5">
            {r.almorzando > 0 && <Insignia variante="advertencia" tamano="sm">{r.almorzando} almorzando</Insignia>}
            {r.paso > 0 && <Insignia variante="alerta" tamano="sm">{r.paso} se pasó</Insignia>}
            {r.promedio !== null && <span className="text-xs text-taupe">promedio {r.promedio} min</span>}
          </span>
        </button>
        {abierto && <div className="border-t border-sand bg-papel">{hijos ?? cuerpo(ds)}</div>}
      </section>
    );
  }

  const personasEnVista = visibles.length;
  const areasDeOficina = [...new Set(oficinas.map((d) => d.f.area))].sort((a, b) => a.localeCompare(b, "es"));

  return (
    <div className="space-y-4">
      {error && <BannerAviso enLinea variante="advertencia" className="text-xs">{error}</BannerAviso>}

      <ParaAtender
        items={[
          ...(esHoy ? [{ clave: "almorzando", texto: `${conteo.almorzando} almorzando ahora`, n: conteo.almorzando, tono: "ambar" as const }] : []),
          { clave: "paso", texto: `${conteo.paso} se ${conteo.paso === 1 ? "pasó" : "pasaron"} del tiempo`, n: conteo.paso, tono: "rojo" as const },
          { clave: "tarde", texto: `${conteo.tarde} volvió tarde`, n: conteo.tarde, tono: "rojo" as const },
        ]}
        activa={solo || null}
        alTocar={(c) => setSolo(solo === c ? "" : (c as typeof solo))}
      />

      <div className="flex flex-wrap items-center gap-2">
        <div className="w-52">
          <CampoSelect tamano="sm" aria-label="Día" value={dia} onChange={(e) => setDia(e.target.value)}>
            {dias.map((iso) => <option key={iso} value={iso}>{etiquetaDia(iso)}</option>)}
          </CampoSelect>
        </div>
        <div className="flex flex-wrap items-center gap-1.5" role="group" aria-label="Sede">
          <Filtro tamano="sm" activo={sedeSel === "todas"} onClick={() => setSedeSel("todas")}>Todas</Filtro>
          {codigosTienda.map((c) => <Filtro key={c} tamano="sm" activo={sedeSel === c} onClick={() => setSedeSel(c)}>{c}</Filtro>)}
          {hayOficinas && <Filtro tamano="sm" activo={sedeSel === OFICINAS} onClick={() => setSedeSel(OFICINAS)}>Oficinas</Filtro>}
        </div>
        <div className="ml-auto flex gap-1.5" role="group" aria-label="Cómo ver la jornada">
          <BotonIcono tamano="md" etiqueta="Ver como línea del día" icono={<AlignLeft aria-hidden />} activo={vista === "linea"} onClick={() => setVista("linea")} />
          <BotonIcono tamano="md" etiqueta="Ver como tabla" icono={<Table2 aria-hidden />} activo={vista === "tabla"} onClick={() => setVista("tabla")} />
        </div>
      </div>

      {filas === null && !error ? <Cargando texto="Cargando la jornada…" /> : personasEnVista === 0 ? (
        <EstadoVacio>{solo ? "Nadie coincide con ese aviso." : "Nadie marcó entrada ese día."}</EstadoVacio>
      ) : (
        <div className="space-y-2.5">
          {codigosTienda.filter((c) => tiendas.some((d) => d.f.sedeCodigo === c)).map((c) => (
            grupo(c, c, tiendas.filter((d) => d.f.sedeCodigo === c))
          ))}
          {oficinas.length > 0 && grupo(OFICINAS, "Oficinas", oficinas, {
            nota: "aparte: no cuentan en las tiendas",
            hijos: areasDeOficina.map((a) => (
              <div key={a}>
                <p className="px-4 pt-3 text-xs font-medium text-taupe">{a}</p>
                {cuerpo(oficinas.filter((d) => d.f.area === a))}
              </div>
            )),
          })}
        </div>
      )}

      {vista === "linea" && personasEnVista > 0 && (
        <p className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-taupe">
          <span><i className="mr-1 inline-block h-2.5 w-3.5 rounded-sm bg-[color-mix(in_oklab,var(--color-tinta)_80%,var(--color-papel))] align-middle" aria-hidden />Trabajando</span>
          <span><i className="mr-1 inline-block h-2.5 w-3.5 rounded-sm border border-ambar align-middle" style={{ backgroundImage: "repeating-linear-gradient(135deg, color-mix(in oklab, var(--color-ambar) 50%, var(--color-papel)) 0 4px, color-mix(in oklab, var(--color-ambar) 24%, var(--color-papel)) 4px 8px)" }} aria-hidden />Almuerzo (rojo si pasa del tiempo de su horario)</span>
          {esHoy && <span><i className="mr-1 inline-block h-2.5 w-0.5 bg-rojo align-middle" aria-hidden />Ahora</span>}
        </p>
      )}
      <p className="text-xs text-taupe">{fechaLima(ahoraTs) === dia && esHoy ? "Se actualiza cada minuto." : "Día pasado: lo que quedó marcado."}</p>
    </div>
  );
}

// `minutosEntre` se reexporta por si otra pantalla necesita la misma cuenta sin importar dos archivos.
export { minutosEntre };

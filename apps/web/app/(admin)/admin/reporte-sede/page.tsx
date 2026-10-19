"use client";

import { Suspense, useCallback, useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { parseAreas, esOperativaEn, AREA_DEFAULT, type Area } from "@/lib/areas";
import { Marca } from "@/components/marca";
import { Cargando } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { Tabla, TablaEncabezado, Th } from "@/components/ui/tabla";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { traerTodo } from "@/lib/admin/traer-todo";
import { loQueNoSePudo, sePuedeEntregar } from "@/lib/admin/lo-que-no-se-pudo";
import { NIVEL_DISCIPLINARIO_CORTO, TZ_LIMA, cuentaEnCobertura, hoyLima, primeroDeMesLima } from "@cayla-dynamic/shared";
import { causaMetaImposible, enPausaAhora, porPausaMasLarga, textoPausaDesde, trabajandoAhora, type PausaAbierta } from "@/lib/admin/asistencia-hoy";
import { traerPausasAbiertas } from "@/lib/admin/pausas-abiertas";
import { diaDeLaSedeDe, type DiaDeLaSede, type HorarioTramo, type TurnoDia } from "@/lib/admin/jornada-esperada";
import { coberturaDeHoyApagada, hojaIncluyeHoy, textoCoberturaApagada, textoMetaDeHoy } from "@/lib/admin/cobertura-hoja-sede";
import { traerSiEsFeriado } from "@/lib/admin/feriado-de-hoy";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { sobretituloDeHoy } from "@/lib/admin/sobretitulo";

const CORTE_TARDE = 14.25; // mismo corte mañana/tarde que Turnos/Dashboard

function fmtDia(iso: string, opts: Intl.DateTimeFormatOptions): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { ...opts, timeZone: "UTC" }).format(new Date(Date.UTC(y, m - 1, d)));
}
// Etiqueta del periodo elegido. Antes esta pantalla solo aceptaba mes
// calendario completo, así que un solo nombre de mes alcanzaba. Ahora el
// rango es libre —puede ser el periodo de planilla, una semana, un solo
// día— y la etiqueta tiene que decirlo sin mentir por omisión.
function rangoLabel(desde: string, hasta: string): string {
  if (desde === hasta) return fmtDia(desde, { day: "numeric", month: "long", year: "numeric" });
  const mismoAnio = desde.slice(0, 4) === hasta.slice(0, 4);
  const mismoMes = mismoAnio && desde.slice(5, 7) === hasta.slice(5, 7);
  if (mismoMes) return `${Number(desde.slice(8, 10))}–${fmtDia(hasta, { day: "numeric", month: "long", year: "numeric" })}`;
  const izq = fmtDia(desde, mismoAnio ? { day: "numeric", month: "short" } : { day: "numeric", month: "short", year: "numeric" });
  return `${izq} – ${fmtDia(hasta, { day: "numeric", month: "short", year: "numeric" })}`;
}
function diaSemanaDe(iso: string): number {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay();
}
function horaDecimalLimaAhora(): number {
  const p = new Intl.DateTimeFormat("en-GB", { timeZone: TZ_LIMA, hour: "2-digit", minute: "2-digit", hour12: false }).formatToParts(new Date());
  const h = Number(p.find((x) => x.type === "hour")?.value ?? 0) % 24;
  const m = Number(p.find((x) => x.type === "minute")?.value ?? 0);
  return h + m / 60;
}
function fmtHoras(h: number): string { const hh = Math.floor(h); const mm = Math.round((h - hh) * 60); return `${hh}h ${String(mm).padStart(2, "0")}m`; }

interface Sede { id: string; codigo: string; nombre: string; tipo: string }
interface Fila {
  personaId: string; nombre: string;
  estadoHoy: string; // abierta / en_pausa / cerrada / sin_marcar
  // Desde cuándo está en pausa, si `estadoHoy` es `en_pausa` y se pudo saber.
  pausa?: PausaAbierta | null;
  esOperativa: boolean; esEncargada: boolean;
  dias: number; horas: number; tardanzas: number; minTarde: number; salidasTemp: number;
}
interface Meta { man: number; tar: number; enc: number }
// `umbral` nombra el escalón alcanzado desde la 0200 — amonestacion ·
// suspension · imputacion · bloqueado · aviso —, no solo «amonestacion o aviso».
interface TardRow { persona_id: string; nombre: string; sede: string; tardanzas_mes: number; umbral: string }
interface FaltaRow { persona_id: string; nombre: string; sede: string; nivel: string }

// Una línea de cobertura: «Operativas en piso 2 / meta 4 · faltan 2». Vive acá,
// al nivel del módulo, y no dentro de la pantalla: un componente definido en el
// render se vuelve a crear en cada render y reinicia su estado (la regla
// `react-hooks/static-components`). No usa nada de la pantalla, solo sus propias
// propiedades, así que moverlo no cambia lo que dibuja.
const Cobertura = ({ label, n, m }: { label: string; n: number; m: number }) => {
  const sinMeta = m <= 0; const ok = !sinMeta && n >= m;
  const color = sinMeta ? "var(--color-taupe)" : ok ? "var(--color-verde)" : "var(--color-rojo)";
  return (
    <span className="flex items-center gap-1.5 text-sm">
      <span className="text-taupe">{label}</span>
      <span className="font-semibold tabular-nums" style={{ color }}>{n}{!sinMeta && <span className="font-normal text-taupe"> / meta {m}</span>}</span>
      {sinMeta ? <span className="text-xs text-taupe/60">sin meta</span> : <span className="text-xs font-medium" style={{ color }}>{ok ? "· completo" : `· faltan ${m - n}`}</span>}
    </span>
  );
};

function ReporteSedeContenido() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  const [sedes, setSedes] = useState<Sede[]>([]);
  const [sedeId, setSedeId] = useState<string>("");
  const [desde, setDesde] = useState(primeroDeMesLima());
  const [hasta, setHasta] = useState(hoyLima());
  const [filas, setFilas] = useState<Fila[]>([]);
  const [meta, setMeta] = useState<Meta>({ man: 0, tar: 0, enc: 0 });
  const [tardAlerta, setTardAlerta] = useState<TardRow[]>([]);
  const [faltaAlerta, setFaltaAlerta] = useState<FaltaRow[]>([]);
  const [cargando, setCargando] = useState(false);
  const [cargado, setCargado] = useState(false);
  /**
   * Qué NO se pudo traer. Vacío es el caso normal.
   *
   * POR QUÉ ESTA PANTALLA LO NECESITA MÁS QUE NINGUNA: esta hoja se imprime, se
   * firma y se lleva a la sede. Hasta hoy sus nueve consultas tiraban el `error`
   * —solo `errAreas` se miraba— así que un fallo de red salía como un papel con
   * el equipo entero en «Días 0 · 0h 00m · Tardanzas —» y el botón de PDF
   * habilitado. Un cero es una afirmación: dice que esa persona no trabajó.
   *
   * No se distingue por gravedad a propósito. Cualquiera de estas consultas
   * alimenta una columna del papel, y la regla de la casa es que un dato que
   * falta se NOTE en vez de rellenarse.
   */
  const [noSePudo, setNoSePudo] = useState<string[]>([]);
  // Desde cuándo está en pausa cada quien no se pudo consultar. Va APARTE de
  // `noSePudo` a propósito: todo lo que entra ahí desactiva el PDF, y esto es un
  // detalle del recuadro «Hoy» —los nombres salen igual, sin hora— que no vuelve
  // falso el papel. Bloquear la impresión por eso sería desproporcionado.
  const [pausasNoRespondieron, setPausasNoRespondieron] = useState(false);
  // Qué día es HOY para esta sede: si a alguien del equipo le tocaba trabajar, si a
  // nadie, o si no hay con qué saberlo (null: no se preguntó o la consulta falló).
  // Ver cobertura-hoja-sede.ts.
  const [diaDeHoy, setDiaDeHoy] = useState<DiaDeLaSede | null>(null);
  /**
   * Por qué no se pudo elegir ninguna sede, cuando la consulta SÍ contestó.
   *
   * Dos caminos distintos y los dos terminaban igual de mudos (hallazgo 31 de
   * la auditoría del 2026-09-03/04): llegar con un `?sede=CODIGO` que no está
   * entre las activas —Sedes ofrecía «Hoja» también en las filas inactivas— o
   * que no haya ninguna sede activa. En los dos casos nunca se fijaba `sedeId`,
   * `cargar()` salía por su primera línea y la pantalla se quedaba en blanco:
   * ni datos ni error. `codigo` es el que venía en la dirección, o null cuando
   * el problema es que la lista está vacía.
   */
  const [sedeNoElegible, setSedeNoElegible] = useState<{ codigo: string | null } | null>(null);

  // Cargar sedes (para el selector). Pre-selecciona la del ?sede=CODIGO si viene.
  useEffect(() => {
    void (async () => {
      const { data: sesion } = await supabase.auth.getSession();
      if (!sesion.session) { router.replace("/admin/login"); return; }
      const { data, error } = await supabase.from("sedes").select("id, codigo, nombre, tipo").eq("activa", true).order("codigo");
      // Si esta falla, el desplegable queda vacío, nunca hay `sedeId`, `cargar()`
      // sale por su primera línea y la pantalla se queda en blanco SIN UNA SOLA
      // PALABRA — se lee como «no hay sedes», que es una frase falsa.
      if (error) {
        setNoSePudo(["la lista de sedes"]);
        return;
      }
      const lista = (data as Sede[]) ?? [];
      setSedes(lista);
      const cod = searchParams.get("sede")?.toUpperCase() ?? null;
      const pre = cod ? lista.find((s) => s.codigo === cod) : lista[0];
      if (pre) { setSedeId(pre.id); setSedeNoElegible(null); return; }
      // Y si no hay a quién preseleccionar, se dice — nunca se cae al primero
      // de la lista: la dirección pedía una sede concreta, y contestar con otra
      // sería peor que no contestar. El papel lleva el nombre de la sede.
      //
      // Se apaga además lo que hubiera cargado antes. Este efecto depende de
      // `searchParams`, así que vuelve a correr sin recargar la página (una
      // dirección escrita a mano, un marcador viejo, atrás/adelante): si la hoja
      // de OTRA sede seguía montada, quedaba entera debajo del aviso, con
      // «Descargar PDF» habilitado — un papel con el nombre de una sede y un
      // aviso que nombra otra. Con `sedeId` vacío no se recarga nada, la hoja no
      // se pinta, el botón queda deshabilitado y el desplegable cae en «Elegir
      // sede…».
      setSedeId("");
      setCargado(false);
      setSedeNoElegible({ codigo: cod });
    })();
  }, [supabase, router, searchParams]);

  const cargar = useCallback(async () => {
    if (!sedeId || !desde || !hasta || hasta < desde) return;
    setCargando(true);
    const hoy = hoyLima();
    const diaHoy = diaSemanaDe(hoy);
    const codigoSede = sedes.find((s) => s.id === sedeId)?.codigo ?? "";

    const [
      { data: personas, error: errPersonas },
      { data: jornadas, error: errJornadas },
      { data: extras, error: errExtras },
      { data: funciones, error: errFunciones },
      { data: areasRaw, error: errAreas },
      { data: metasRaw, error: errMetas },
      { data: tardResumen, error: errTard },
      { data: faltasResumen, error: errFaltas },
      { data: turnosHoy, error: errTurnos },
      { data: horariosVigentes, error: errHorarios },
      // ¿Hoy es feriado? Solo cambia QUÉ se apaga y con qué palabra (ver `diaDeLaSedeDe`).
      // Si falla cae a «no es feriado» y la línea se imprime como antes: una duda no calla.
      feriadoHoy,
    ] = await Promise.all([
      // Mismo criterio del dashboard (7afe8e5): un practicante trabaja en la
      // sede y tiene que salir en su hoja, aunque el escalafón disciplinario
      // (fn_tardanzas_resumen/fn_faltas_resumen, más abajo) lo siga
      // excluyendo — esta hoja solo lo muestra, no lo sanciona.
      supabase.from("personas").select("id, nombres, apellidos, rol, sede_base_id")
        .eq("estado", "activo").eq("cuenta_de_servicio", false)
        .or("en_planilla.eq.true,tipo_vinculo.eq.practicante")
        .eq("sueldo_fijo", false).eq("sede_base_id", sedeId).order("nombres"),
      // Por lotes: sin esto PostgREST cortaba en 1000 filas en silencio y la
      // hoja de sede salía con horas y tardanzas de menos.
      traerTodo<{ persona_id: string; fecha: string; estado: string; minutos_tarde: number | null; horas_trabajadas: number | null }>(
        (ini, fin) =>
          supabase
            .from("jornadas")
            .select("persona_id, fecha, estado, minutos_tarde, horas_trabajadas")
            .gte("fecha", desde)
            .lte("fecha", hasta)
            .order("fecha")
            .order("persona_id")
            .range(ini, fin),
      ),
      supabase.rpc("fn_jornadas_extra", { p_desde: desde, p_hasta: hasta }),
      supabase.rpc("fn_personas_funciones"),
      supabase.rpc("fn_areas"),
      supabase.from("metas_cobertura").select("sede_id, meta, meta_tarde, meta_encargadas").eq("dia_semana", diaHoy).eq("sede_id", sedeId),
      // `p_as_of` es el fin del rango elegido, no la fecha de hoy: sin esto,
      // mirar un periodo cerrado mostraba en «Necesita atención» el estado de
      // HOY con el umbral de hoy, no el del periodo que se está archivando.
      supabase.rpc("fn_tardanzas_resumen", { p_as_of: hasta }),
      supabase.rpc("fn_faltas_resumen", { p_as_of: hasta }),
      // Turnos y horarios de HOY: de los dos sale «¿a alguien del equipo le tocaba
      // trabajar hoy?» (jornada-esperada.ts). Se traen los de todo el mundo y se
      // mira solo a quienes son de esta sede — son decenas de filas, no más — igual
      // que el Dashboard, para que las dos pantallas lean lo mismo.
      supabase.from("turnos").select("persona_id, fecha, hora_entrada, hora_salida, es_descanso").eq("fecha", hoy),
      supabase
        .from("horarios_asignados")
        .select("persona_id, hora_entrada, hora_salida, dias_laborables, horario_por_dia, almuerzo_min_minutos, vigente_desde, vigente_hasta")
        .lte("vigente_desde", hoy)
        .or(`vigente_hasta.is.null,vigente_hasta.gte.${hoy}`),
      traerSiEsFeriado(supabase, hoy),
    ]);
    // Los turnos de hoy solo importan si la hoja llega hasta hoy.
    //
    // Si estas dos consultas fallan NO se nombran en `noSePudo` (que apaga el PDF): la
    // línea de cobertura se imprime exactamente como antes de existir esto —con su «faltan 1»
    // si tocaba—, que es un papel tan válido como el de ayer. Bloquear la impresión porque
    // falló un dato que solo APAGA una alarma sería desproporcionado; es el mismo criterio de
    // `pausasNoRespondieron`, arriba.
    const llegaAHoy = hojaIncluyeHoy(desde, hasta, hoy);

    // Qué se cayó, con el nombre de la columna que alimenta — no el de la RPC.
    // Quien lee esto está a punto de firmar el papel, no de depurar.
    setNoSePudo(
      loQueNoSePudo([
        { error: errPersonas, que: "el equipo de la sede" },
        { error: errJornadas, que: "los días y las horas" },
        { error: errExtras, que: "las salidas anticipadas" },
        { error: errFunciones, que: "las funciones" },
        { error: errAreas, que: "las áreas" },
        { error: errMetas, que: "las metas de cobertura" },
        { error: errTard, que: "las tardanzas" },
        { error: errFaltas, que: "las faltas" },
      ]),
    );

    const areasList: Area[] = parseAreas(areasRaw, errAreas);
    const funcionPorPersona = new Map(
      ((funciones as { persona_id: string; funcion: string; es_encargada_piso?: boolean; tipo_vinculo?: string | null }[] | null) ?? [])
        .map((x) => [x.persona_id, { funcion: x.funcion, enc: Boolean(x.es_encargada_piso), vinculo: x.tipo_vinculo ?? null }]));
    // Misma definición que el Dashboard y Turnos (cobertura-equipo.ts): depende
    // del tipo de la sede que se está mirando.
    const tipoDeSede = sedes.find((x) => x.id === sedeId)?.tipo ?? null;
    const m = ((metasRaw as { meta: number; meta_tarde: number | null; meta_encargadas: number | null }[] | null) ?? [])[0];
    const metaNueva = { man: m?.meta ?? 0, tar: m?.meta_tarde ?? m?.meta ?? 0, enc: m?.meta_encargadas ?? 0 };

    // Salidas anticipadas del mes (RPC; solo filas > 0).
    const salTemp = new Map<string, number>();
    for (const e of ((extras as { persona_id: string; fecha: string; minutos_salida_temprana: number }[] | null) ?? [])) {
      salTemp.set(e.persona_id, (salTemp.get(e.persona_id) ?? 0) + 1);
    }
    // Jornadas agrupadas por persona.
    const jorPorPersona = new Map<string, { fecha: string; estado: string; minutos_tarde: number | null; horas_trabajadas: number | null }[]>();
    for (const j of (jornadas as any[]) ?? []) {
      const arr = jorPorPersona.get(j.persona_id) ?? [];
      arr.push(j); jorPorPersona.set(j.persona_id, arr);
    }

    const filasCalc: Fila[] = ((personas as any[]) ?? []).map((p) => {
      const js = jorPorPersona.get(p.id) ?? [];
      const reales = js.filter((j) => (j.horas_trabajadas ?? 0) <= 24); // excluye agregados históricos 2025
      const hoyJ = js.find((j) => j.fecha === hoy);
      const f = funcionPorPersona.get(p.id);
      const cuenta = cuentaEnCobertura(
        {
          rol: p.rol,
          tipoVinculo: f?.vinculo ?? null,
          esEncargadaPiso: Boolean(f?.enc),
          areaOperativa: esOperativaEn(areasList, f?.funcion ?? AREA_DEFAULT),
        },
        tipoDeSede,
      );
      return {
        personaId: p.id,
        nombre: `${p.nombres} ${p.apellidos}`,
        estadoHoy: hoyJ?.estado ?? "sin_marcar",
        esOperativa: cuenta.operativa,
        esEncargada: cuenta.lider,
        dias: reales.filter((j) => (j.horas_trabajadas ?? 0) > 0).length,
        horas: js.reduce((s, j) => s + (j.horas_trabajadas ?? 0), 0),
        tardanzas: js.filter((j) => (j.minutos_tarde ?? 0) > 0).length,
        minTarde: js.reduce((s, j) => s + (j.minutos_tarde ?? 0), 0),
        salidasTemp: salTemp.get(p.id) ?? 0,
      };
    });
    // Qué día es hoy para la sede. Misma cascada que el Dashboard: el turno puntual
    // de hoy manda y, si no hay, el horario base vigente. Si alguna de las dos
    // consultas falló, o el rango no llega a hoy, es «no se sabe» (null) y la línea
    // de cobertura queda como estaba.
    let diaDeHoyNuevo: DiaDeLaSede | null = null;
    if (llegaAHoy && !errTurnos && !errHorarios) {
      const turnoPorPersona = new Map(
        ((turnosHoy as { persona_id: string; hora_entrada: string | null; hora_salida: string | null; es_descanso: boolean }[] | null) ?? [])
          .map((t) => [t.persona_id, t as TurnoDia]),
      );
      const tramosPorPersona = new Map<string, HorarioTramo[]>();
      for (const h of (horariosVigentes as HorarioTramo[] | null) ?? []) {
        const arr = tramosPorPersona.get(h.persona_id) ?? [];
        arr.push(h);
        tramosPorPersona.set(h.persona_id, arr);
      }
      diaDeHoyNuevo = diaDeLaSedeDe(
        filasCalc.map((f) => f.personaId),
        hoy,
        (id) => turnoPorPersona.get(id) ?? null,
        (id) => tramosPorPersona.get(id) ?? [],
        feriadoHoy.esFeriado,
      );
    }
    // Desde cuándo está en pausa cada quien (solo de los que la base ya marcó
    // «en pausa»). Si falla, salen sus nombres sin hora.
    const { porPersona: pausas, fallo: fallaronPausas } = await traerPausasAbiertas(
      supabase,
      filasCalc.filter((f) => enPausaAhora(f.estadoHoy)).map((f) => f.personaId),
      hoy,
    );
    setPausasNoRespondieron(fallaronPausas);
    setFilas(filasCalc.map((f) => ({ ...f, pausa: pausas.get(f.personaId) ?? null })));
    // Junto a `filas`, no antes: la línea de cobertura cruza las dos, y con un
    // `await` en medio se pintaría un instante el día de esta sede con el equipo
    // de la anterior.
    setDiaDeHoy(diaDeHoyNuevo);
    // La meta también, junto a `filas`: al cambiar de sede, con el `await` de pausas en medio,
    // se veía un instante la meta de la sede nueva con el equipo de la anterior.
    setMeta(metaNueva);
    // Cualquier escalón alcanzado entra a «Necesita atención», no solo la
    // amonestación: esta hoja se imprime y se lleva a la sede.
    setTardAlerta(((tardResumen as TardRow[]) ?? []).filter((t) => t.sede === codigoSede && t.umbral !== "aviso"));
    setFaltaAlerta(((faltasResumen as FaltaRow[]) ?? []).filter((f) => f.sede === codigoSede && f.nivel === "rojo"));
    setCargado(true);
    setCargando(false);
  }, [supabase, sedeId, desde, hasta, sedes]);

  useEffect(() => { if (sedeId) void cargar(); }, [sedeId, cargar]);

  const sede = sedes.find((s) => s.id === sedeId);
  const tramoTarde = horaDecimalLimaAhora() >= CORTE_TARDE;
  // «Trabajando» y «en pausa» son dos cosas (ver asistencia-hoy.ts): la misma
  // cuenta que el Dashboard, con la misma definición, para que la hoja que se
  // imprime y la pantalla no digan números distintos a la misma hora.
  const trabajando = filas.filter((f) => trabajandoAhora(f.estadoHoy));
  const enPausa = filas.filter((f) => enPausaAhora(f.estadoHoy));
  const opPiso = trabajando.filter((f) => f.esOperativa).length;
  const encPiso = trabajando.filter((f) => f.esEncargada).length;
  const metaOp = tramoTarde ? meta.tar : meta.man;
  // El equipo que PODRÍA cubrir cada meta (esté hoy o no): ver causaMetaImposible.
  const equipoOperativas = filas.filter((f) => f.esOperativa).length;
  const equipoLideres = filas.filter((f) => f.esEncargada).length;
  const mostrarOperativas = !(equipoOperativas === 0 && metaOp <= 0);
  const mostrarLideres = !(equipoLideres === 0 && meta.enc <= 0);
  const causasMeta = [
    { quien: "Operativas", causa: causaMetaImposible("operativas", metaOp, equipoOperativas) },
    { quien: "Líderes", causa: causaMetaImposible("lideres", meta.enc, equipoLideres) },
  ].flatMap((c) => (c.causa ? [{ quien: c.quien, detalle: c.causa.detalle }] : []));
  const rango = rangoLabel(desde, hasta);
  const hoy = hoyLima();
  // Una sola pregunta para las dos decisiones de abajo: si el recuadro «Hoy» se dibuja
  // y si su línea de cobertura se apaga. Ver cobertura-hoja-sede.ts.
  const hojaLlegaAHoy = hojaIncluyeHoy(desde, hasta, hoy);
  // Central un domingo: meta de 1 líder y a nadie le toca. Sin esto salía «faltan 1»
  // en rojo en un papel que se firma. Ver cobertura-hoja-sede.ts.
  const coberturaApagada = coberturaDeHoyApagada({
    dia: diaDeHoy,
    estadosHoy: filas.map((f) => f.estadoHoy),
    rangoIncluyeHoy: hojaLlegaAHoy,
  });
  const textoMeta = textoMetaDeHoy(meta.man, meta.tar, meta.enc);
  const textoApagada = textoCoberturaApagada(diaDeHoy);

  // El nombre con el que se guarda el PDF. Ver use-titulo-documento.ts.
  // Aquí el periodo va DELANTE, al contrario que en la boleta: estos reportes
  // se archivan por periodo y se comparan entre sedes, así que ordenados por
  // fecha quedan agrupados solos en la carpeta.
  useTituloDocumento(sede ? `Reporte ${rango} — ${sede.nombre}` : null);

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6 print:p-0">
        {/* Controles — no salen en el PDF */}
        <div className="print:hidden">
          <CabeceraPagina
            sobretitulo={sobretituloDeHoy("Reportes")}
            titulo="Hoja de sede"
            descripcion="El estado de una sede en una página: hoy, el periodo elegido y lo que necesita atención."
            accion={
            <div className="flex flex-wrap items-end gap-3">
            <CampoSelect
              etiqueta="Sede"
              value={sedeId}
              onChange={(e) => { setSedeId(e.target.value); setSedeNoElegible(null); setCargado(false); }}
              className="min-w-40"
            >
              {/* Sin sede elegida el desplegable mostraría la primera de la lista
                  mientras `sedeId` sigue vacío: se vería una sede que no es la que
                  se está mirando. Esta opción hace visible que no hay ninguna. */}
              {!sedeId && <option value="" disabled>Elegir sede…</option>}
              {sedes.map((s) => <option key={s.id} value={s.id}>{s.nombre}</option>)}
            </CampoSelect>
            <Campo
              etiqueta="Desde"
              type="date"
              value={desde}
              max={hasta}
              onChange={(e) => { const v = e.target.value; setDesde(v); if (v > hasta) setHasta(v); setCargado(false); }}
            />
            <Campo
              etiqueta="Hasta"
              type="date"
              value={hasta}
              min={desde}
              max={hoy}
              onChange={(e) => { const v = e.target.value; setHasta(v); if (v < desde) setDesde(v); setCargado(false); }}
            />
            {/* Sin todos los datos NO se imprime. El papel se firma y se lleva a
                la sede: un cero que en realidad es «no se pudo consultar» dice por
                escrito que esa persona no trabajó. */}
            <Boton variante="primario" onClick={() => window.print()} disabled={!sePuedeEntregar(cargado, noSePudo)}>
              Descargar PDF
            </Boton>
          </div>
            }
          />
        </div>

        {/* El aviso SÍ se imprime — no lleva `no-print` a propósito. Si alguien
            fuerza la impresión con ⌘P saltándose el botón, el papel tiene que
            salir diciendo que está incompleto. Un aviso que desaparece justo en
            el papel es el defecto que la A11 tuvo con el memo en borrador. */}
        {noSePudo.length > 0 && (
          <div className="mb-6 rounded-2xl border border-rojo/30 bg-rojo/[0.06] p-4 text-sm">
            <div className="font-medium text-rojo">Esta hoja está incompleta — no la imprimas todavía</div>
            <p className="mt-1 text-tinta">
              No se pudo traer {noSePudo.join(", ")}. Lo que falta aparece abajo como cero o como raya, y
              eso <strong>no significa que no ocurriera</strong>. Vuelve a cargar; si sigue igual, avisa.
            </p>
          </div>
        )}

        {/* La sede que pedía la dirección no está entre las activas — o no hay
            ninguna. Se dice con todas las letras: antes esto era una pantalla en
            blanco, que se lee como «esta sede no tiene nada» y no como «esta sede
            no está». Se imprime igual que el aviso de arriba, por si alguien fuerza
            ⌘P: el papel tiene que decir por qué salió vacío. */}
        {sedeNoElegible && (
          <div className="mb-6 max-w-3xl rounded-2xl border border-ambar/40 bg-ambar/[0.06] p-4 text-sm">
            {/* El título no dice «no está activa»: la consulta trae SOLO las
                activas, así que la pantalla no puede distinguir «desactivada» de
                «ese código no existe». Afirmar la primera manda a buscar en
                Sedes una sede que quizá nunca existió. El cuerpo nombra las dos
                causas, que es todo lo que se sabe de verdad. */}
            <div className="font-medium text-tinta">
              {sedeNoElegible.codigo
                ? `No se puede armar la hoja de ${sedeNoElegible.codigo}`
                : "No hay ninguna sede activa"}
            </div>
            <p className="mt-1 text-taupe">
              {sedeNoElegible.codigo
                ? "Esta hoja solo se arma para sedes activas, y ese código no existe o está desactivado. Elígela en el selector de esta pantalla si aparece, o revísala en Sedes."
                : "Esta hoja se arma sobre una sede activa y ahora mismo no hay ninguna. Se activa una en Sedes."}
            </p>
          </div>
        )}

        {cargando && !cargado ? (
          <Cargando texto="Armando la hoja…" />
        ) : cargado && sede && (
          <div className="hoja">
            {/* Cabecera — solo en el PDF: en pantalla ya está la del menú, y
                repetir las dos ahí se ve como que la pantalla no sabe cuál usar. */}
            <div className="mb-6 hidden items-start justify-between border-b border-sand pb-4 print:flex print:mb-4 print:pb-3">
              <Marca tono="tinta" isotipo="rojo" />
              <div className="text-right">
                <p className="etiqueta text-taupe">Hoja de sede</p>
                <p className="font-serif text-lg">{sede.nombre}</p>
                <p className="text-xs text-taupe">{rango} · generado {new Date().toLocaleDateString("es-PE", { day: "2-digit", month: "long", year: "numeric" })}</p>
              </div>
            </div>

            <h2 className="mb-4 font-serif text-2xl">
              {sede.nombre} <span className="text-lg font-normal text-taupe">· {rango}</span>
            </h2>

            {/* HOY — solo si la hoja llega hasta hoy. «Hoy» sale de las jornadas del rango
                elegido: en un periodo que termina antes de hoy esa consulta nunca lo trae, y
                cada integrante caía en «sin marcar» — un «Nadie está trabajando» y un
                «faltan N» en rojo que eran un cero inventado, escrito en un papel que se
                firma y se archiva. La hoja de un periodo cerrado describe ese periodo, igual
                que «Necesita atención» (que mide con el fin del rango, no con hoy): no lleva
                un «Hoy» que no le corresponde. */}
            {hojaLlegaAHoy ? (
              <section className="mb-6 rounded-2xl border border-verde/20 bg-verde/[0.06] p-5 print:break-inside-avoid print:bg-white">
                <div className="etiqueta text-verde">
                  Hoy · {trabajando.length} trabajando ahora{enPausa.length > 0 ? ` · ${enPausa.length} en pausa` : ""} · equipo de {filas.length}
                </div>
                <div className="mt-3 flex flex-wrap gap-2">
                  {/* «Nadie está trabajando», no «nadie marcado todavía»: quien ya
                      marcó y salió también deja este recuadro vacío, y decir que
                      nadie marcó sería falso a las 6 de la tarde. */}
                  {trabajando.length === 0 ? <span className="text-sm text-taupe">Nadie está trabajando en este momento.</span> :
                    trabajando.map((f) => (
                      <span key={f.personaId} className="rounded-full border border-sand bg-papel px-3 py-1 text-sm">{f.nombre}</span>
                    ))}
                </div>
                {enPausa.length > 0 && (
                  <div className="mt-3 flex flex-wrap items-center gap-2">
                    <span className="etiqueta text-ambar">En pausa</span>
                    {/* Con la hora de salida y SIN «cuánto lleva»: en un papel los
                        minutos envejecen (leídos mañana afirman lo que no es), la
                        hora de salida no. */}
                    {[...enPausa].sort(porPausaMasLarga).map((f) => (
                      <span key={f.personaId} className="rounded-full border border-ambar/45 bg-papel px-3 py-1 text-sm">
                        {f.nombre}
                        {f.pausa && <span className="ml-1.5 text-xs text-taupe">{textoPausaDesde(f.pausa)}</span>}
                      </span>
                    ))}
                    {pausasNoRespondieron && <span className="text-xs text-ambar">No se pudo comprobar desde cuándo.</span>}
                  </div>
                )}
                {/* Igual que en el Dashboard: una línea «0 · sin meta» de un grupo que en
                    esta sede no existe no informa nada, y la causa de una meta que no se
                    puede cumplir se dice en vez de dejar un «faltan 1» que parece falta. */}
                {/* Sin turnos hoy —y con la certeza de que es porque descansan, no porque
                    falte el horario— no hay cobertura que medir: la línea se apaga en gris
                    y dice por qué. Con meta, la nombra sin pintarla como faltante: es una
                    hoja que se imprime, así que es corta y no da instrucciones. */}
                {coberturaApagada ? (
                  <div className="mt-4 border-t border-verde/15 pt-3 text-sm text-taupe">
                    <p><span className="font-medium">{textoApagada.titulo}</span> · {textoApagada.detalle}</p>
                    {textoMeta && <p className="mt-1 text-xs">{textoMeta} No se mide porque nadie tiene turno; se define en Turnos.</p>}
                  </div>
                ) : (mostrarOperativas || mostrarLideres) && (
                  <div className="mt-4 flex flex-wrap items-center gap-x-6 gap-y-1 border-t border-verde/15 pt-3">
                    {mostrarOperativas && <Cobertura label="Operativas en piso" n={opPiso} m={metaOp} />}
                    {mostrarLideres && <Cobertura label="Líderes en piso" n={encPiso} m={meta.enc} />}
                  </div>
                )}
                {causasMeta.map((c) => (
                  <p key={c.quien} className="mt-2 text-xs text-taupe">
                    <strong className="font-semibold text-tinta">{c.quien}:</strong> {c.detalle}
                  </p>
                ))}
              </section>
            ) : (
              // Solo en pantalla: en el papel no hay nada que explicar, y en la pantalla
              // quien cambia «Hasta» y ve desaparecer el recuadro no debe pensar que se rompió.
              <p className="mb-6 text-sm text-taupe print:hidden">
                «Hoy» no aparece porque este periodo termina antes de hoy: la hoja describe solo el periodo elegido.
                Para ver quién está en piso ahora, pon «Hasta» en hoy o abre el Dashboard.
              </p>
            )}

            {/* EL PERIODO */}
            <section className="mb-6 print:break-inside-avoid">
              <h3 className="mb-2 font-serif text-lg">El periodo · {rango}</h3>
              <Tabla className="[font-variant-numeric:tabular-nums]">
                <TablaEncabezado>
                  <Th>Nombre</Th>
                  <Th>Días</Th>
                  <Th>Horas</Th>
                  <Th>Tardanzas</Th>
                  <Th>Min. tarde</Th>
                  <Th>Sal. antic.</Th>
                </TablaEncabezado>
                <tbody>
                  {filas.length === 0 ? (
                    <tr><td colSpan={6} className="px-4 py-6 text-center text-taupe">Sin gente asignada a esta sede.</td></tr>
                  ) : filas.slice().sort((a, b) => b.horas - a.horas).map((f) => (
                    <tr key={f.personaId} className="border-t border-sand">
                      <td className="px-4 py-2.5">{f.nombre}</td>
                      <td className="px-4 py-2.5">{f.dias}</td>
                      <td className="px-4 py-2.5 font-medium">{fmtHoras(f.horas)}</td>
                      <td className="px-4 py-2.5">{f.tardanzas > 0 ? <span className="text-rojo">{f.tardanzas}</span> : <span className="text-taupe/40">—</span>}</td>
                      <td className="px-4 py-2.5">{f.minTarde > 0 ? `${f.minTarde} min` : <span className="text-taupe/40">—</span>}</td>
                      <td className="px-4 py-2.5">{f.salidasTemp > 0 ? f.salidasTemp : <span className="text-taupe/40">—</span>}</td>
                    </tr>
                  ))}
                </tbody>
              </Tabla>
            </section>

            {/* ATENCIÓN */}
            <section className="rounded-2xl border border-sand bg-rojo/[0.04] p-5 print:break-inside-avoid print:bg-white">
              <div className="etiqueta mb-2 text-rojo">Necesita atención</div>
              {tardAlerta.length === 0 && faltaAlerta.length === 0 ? (
                <p className="text-sm text-taupe">Nada pendiente en disciplina. Buena señal.</p>
              ) : (
                <ul className="space-y-1.5 text-sm">
                  {tardAlerta.map((t) => (
                    <li key={t.persona_id}>
                      <strong>{t.nombre}</strong> — {t.umbral === "bloqueado"
                        ? "tiene una imputación de cargos vigente; decide Gerencia"
                        : `corresponde ${NIVEL_DISCIPLINARIO_CORTO[t.umbral as keyof typeof NIVEL_DISCIPLINARIO_CORTO] ?? t.umbral} por tardanzas`}
                      {" "}({t.tardanzas_mes} este mes).
                    </li>
                  ))}
                  {faltaAlerta.map((f) => (
                    <li key={f.persona_id}><strong>{f.nombre}</strong> — causal por faltas (art. 25-h). Acción inmediata.</li>
                  ))}
                </ul>
              )}
            </section>
          </div>
        )}
      </main>
    </div>
  );
}

export default function ReporteSedePage() {
  return (
    <Suspense fallback={<main className="p-6"><p className="text-sm text-taupe">Cargando…</p></main>}>
      <ReporteSedeContenido />
    </Suspense>
  );
}

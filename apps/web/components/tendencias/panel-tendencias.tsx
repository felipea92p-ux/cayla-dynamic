"use client";

// La pestaña «Tendencias» del Dashboard: la historia, no la foto de hoy.
//
// PROMETE: cinco a siete gráficos —asistencia sobre lo esperado, días perdidos por motivo, hora de llegada por
//   sede, cuándo se llega tarde, gente en piso frente a la venta (tiendas), reportes por motivo y costo de
//   planilla— cada uno con su propia carga, su propio error y su propio vacío. Un gráfico que no respondió dice «no se pudo consultar»; nunca se dibuja como si todo estuviera bien.
// ASUME: se monta SOLO cuando alguien abre la pestaña, y pide su historia UNA vez (más otra si cambia el
//   periodo). No entra en el refresco de 30 s del Dashboard: la historia no cambia cada medio minuto.
// QUIÉN VE QUÉ: asistencia, días perdidos y puntualidad, quien llegó al Dashboard (la base ya recorta al líder a
//   su sede); gente en piso, las tiendas de su alcance (fn_compras_por_hora también recorta);
//   Casos, solo quien `fn_ve_casos` deja; costo de planilla, solo quien `puedeVerPlanilla` — y para quien no,
//   NI SIQUIERA se llama a la RPC (un líder de sede no debe ver sueldos).

import { useEffect, useMemo, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { hoyLima, mesesRecientesLima, puedeVerPlanilla } from "@cayla-dynamic/shared";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Boton } from "@/components/ui/boton";
import { Cargando } from "@/components/cargando";
import { EstadoVacio } from "@/components/ui/estado-vacio";
import { Filtro } from "@/components/ui/filtro";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { AyudaCabecera } from "@/components/vidrio/ayuda-cabecera";
import { interruptoresVidrio } from "@/lib/vidrio";
import { traerResumenCasos } from "@/lib/admin/casos-resumen";
import {
  asistenciaSemanal, barrasDeCasos, calorTardanza, columnasDeCosto, diasPerdidosPorMes, llegadaPorSede, MINIMO_CASOS,
  OTROS_MOTIVOS, SIN_JUSTIFICAR, type FilaAsistencia, type FilaFalta, type PeriodoCosto,
} from "@/lib/admin/tendencias";
import { DIAS_DE_PISO, pisoPorHora, traerPisoYVenta, type TipoDeDia } from "@/lib/admin/piso-venta";
import { nombreDeMotivo } from "@/lib/admin/motivo-falta";
import { traerTodo } from "@/lib/admin/traer-todo";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import {
  BarrasCasos, CalorTardanza, ColumnasCosto, DiasPerdidosGrafico, LineaAsistencia, LlegadaPorSede, PisoYVentaGrafico, pisoDeLinea,
} from "./graficos";

type Estado<T> = { cargando: true } | { cargando: false; error: string } | { cargando: false; error: null; datos: T };

/** Una consulta con sus tres estados. `clave` cambia → se vuelve a pedir. */
function useConsulta<T>(activa: boolean, clave: string, pedir: () => Promise<T>): [Estado<T>, () => void] {
  const [estado, setEstado] = useState<Estado<T>>({ cargando: true });
  const [intento, setIntento] = useState(0);
  useEffect(() => {
    if (!activa) return;
    let vivo = true;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setEstado({ cargando: true });
    pedir().then(
      (datos) => { if (vivo) setEstado({ cargando: false, error: null, datos }); },
      (e: unknown) => { if (vivo) setEstado({ cargando: false, error: e instanceof Error ? e.message : "No se pudo consultar." }); },
    );
    return () => { vivo = false; };
    // `pedir` cambia de identidad en cada render; lo que decide pedir de nuevo es `clave` (periodo, sede…).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activa, clave, intento]);
  return [estado, () => setIntento((n) => n + 1)];
}

function restarDias(iso: string, n: number): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d - n)).toISOString().slice(0, 10);
}

const PERIODOS = [
  { clave: "3m", texto: "3 meses", dias: 91 },
  { clave: "6m", texto: "6 meses", dias: 182 },
  { clave: "anio", texto: "Desde enero", dias: 0 },
] as const;
type ClavePeriodo = (typeof PERIODOS)[number]["clave"];

function Seccion({ titulo, que, queCorto, children, nota }: { titulo: string; que: string; queCorto?: string; children: React.ReactNode; nota?: React.ReactNode }) {
  // Con el vidrio cada gráfico lleva una línea a la vista, y la explicación completa va en su «?»: no se pierde ni una palabra de lo que aclara qué se cuenta y qué no.
  if (interruptoresVidrio().panel) {
    return (
      <TarjetaInfo
        como="section"
        titulo={
          <>
            {titulo}
            {nota || queCorto ? (
              <AyudaCabecera nombre={titulo}>
                {queCorto ? <span className="mb-2 block">{que}</span> : null}
                {nota}
              </AyudaCabecera>
            ) : null}
          </>
        }
      >
        <p className="-mt-1 mb-3 text-sm text-taupe">{queCorto ?? que}</p>
        {children}
      </TarjetaInfo>
    );
  }
  return (
    <TarjetaInfo como="section" titulo={titulo}>
      <p className="-mt-1 mb-3 text-sm text-taupe">{que}</p>
      {children}
      {nota && <p className="mt-3 border-t border-sand pt-2 text-xs text-taupe">{nota}</p>}
    </TarjetaInfo>
  );
}

/** Lo que dice cada gráfico cuando no hay qué mostrar: carga, error o vacío, nunca un cero inventado. */
function Cuerpo<T>({ estado, reintentar, vacio, hijos }: {
  estado: Estado<T>; reintentar: () => void; vacio: (d: T) => string | null; hijos: (d: T) => React.ReactNode;
}) {
  if (estado.cargando) return <Cargando compacto />;
  if (estado.error !== null) {
    return (
      <BannerAviso enLinea role="alert">
        No se pudo consultar. Eso no significa que todo esté en orden: significa que no se pudo mirar.{" "}
        <Boton variante="enlace" onClick={reintentar}>Reintentar</Boton>
      </BannerAviso>
    );
  }
  const sinDatos = vacio(estado.datos);
  return sinDatos ? <EstadoVacio>{sinDatos}</EstadoVacio> : <>{hijos(estado.datos)}</>;
}

const TIPOS_DE_DIA: { clave: TipoDeDia; texto: string }[] = [
  { clave: "todos", texto: "Todos los días" },
  { clave: "semana", texto: "Lunes a viernes" },
  { clave: "finde", texto: "Sábado y domingo" },
];

/** Dos consultas como una: carga si alguna carga, falla si alguna falla. */
function combinar<A, B>(a: Estado<A>, b: Estado<B>): Estado<[A, B]> {
  if (a.cargando || b.cargando) return { cargando: true };
  if (a.error !== null) return a;
  if (b.error !== null) return b;
  return { cargando: false, error: null, datos: [a.datos, b.datos] };
}

export function PanelTendencias({ rol, sedes }: {
  rol: string | null;
  /** `id` y `tipo` los usa «Gente en piso»: solo las tiendas tienen venta por hora. */
  sedes: { id: string; codigo: string; nombre: string; tipo: string | null }[];
}) {
  // Las sedes salen de la TABLA `sedes` (la que ve quien mira), no de lo que devolvió la función: una sede sin
  // días medidos —por ejemplo Central, si su equipo es de sueldo fijo o de dirección— tiene que seguir
  // en la lista y DECIR por qué está vacía, no desaparecer como si no existiera.
  const nombreDeSede = (codigo: string) => sedes.find((s) => s.codigo === codigo)?.nombre ?? codigo;
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const hoy = hoyLima();
  const verPlanilla = puedeVerPlanilla(rol as Parameters<typeof puedeVerPlanilla>[0]);
  const [periodo, setPeriodo] = useState<ClavePeriodo>("3m");
  const [sede, setSede] = useState<string | null>(null);

  // ── Asistencia y puntualidad (función 0534) ────────────────────────────────
  const desde = periodo === "anio" ? `${hoy.slice(0, 4)}-01-01` : restarDias(hoy, PERIODOS.find((p) => p.clave === periodo)!.dias);
  const [asist, reintentarAsist] = useConsulta<FilaAsistencia[]>(true, `asist:${desde}`, async () => {
    const { data, error } = await supabase.rpc("fn_asistencia_serie", { p_desde: desde, p_hasta: hoy });
    if (error) throw new Error(mensajeDeError(error, "traer la asistencia"));
    return (data ?? []) as FilaAsistencia[];
  });

  // ── Días perdidos (fn_faltas, 0414): cada día que tocaba y no se vino, con su motivo ──
  // Un periodo largo pasa de las 1000 filas que corta PostgREST: se pide todo, en lotes, con un orden único.
  const [faltas, reintentarFaltas] = useConsulta(true, `faltas:${desde}`, async () => {
    const [{ data, error }, { data: tipos }] = await Promise.all([
      traerTodo((a, b) => supabase.rpc("fn_faltas", { p_desde: desde, p_hasta: hoy }).order("fecha").order("persona_id").range(a, b)),
      // Sin el catálogo, el motivo se lee por su código («descanso medico»): no se frena el gráfico por un nombre.
      supabase.from("tipos_ausencia").select("codigo, nombre"),
    ]);
    if (error) throw new Error(mensajeDeError(error, "traer los días perdidos"));
    return {
      filas: (data ?? []) as FilaFalta[],
      nombres: new Map(((tipos as { codigo: string; nombre: string }[] | null) ?? []).map((t) => [t.codigo, t.nombre] as const)),
    };
  });

  // ── Gente en piso frente a la venta: una tienda a la vez ───────────────────
  // La tienda la decide el filtro de sede de arriba si es una tienda; con «Todas las sedes», unos botones propios.
  const tiendas = sedes.filter((s) => s.tipo === "tienda");
  const [tiendaPropia, setTiendaPropia] = useState<string | null>(null);
  const [tipoDeDia, setTipoDeDia] = useState<TipoDeDia>("todos");
  const sedeArriba = sede ? sedes.find((s) => s.codigo === sede) ?? null : null;
  const tienda = sedeArriba ? (sedeArriba.tipo === "tienda" ? sedeArriba : null) : (tiendas.find((t) => t.codigo === tiendaPropia) ?? tiendas[0] ?? null);
  const [piso, reintentarPiso] = useConsulta(tienda !== null, `piso:${tienda?.id ?? ""}`, () => traerPisoYVenta(supabase, tienda!, hoy));

  // ── Casos: solo quien ya los ve ────────────────────────────────────────────
  const [veCasos, setVeCasos] = useState<boolean | null>(null);
  useEffect(() => {
    let vivo = true;
    void supabase.rpc("fn_ve_casos").then(({ data, error }) => { if (vivo) setVeCasos(!error && data === true); });
    return () => { vivo = false; };
  }, [supabase]);
  const [casos, reintentarCasos] = useConsulta(veCasos === true, "casos", async () => {
    const { filas, error } = await traerResumenCasos(supabase, mesesRecientesLima(12, hoy)[11]);
    if (error) throw new Error(error);
    return barrasDeCasos(filas);
  });

  // ── Costo de planilla: solo DO y admin. Si no, ni se llama a la base. ─────
  const [costo, reintentarCosto] = useConsulta(verPlanilla, "costo", async () => {
    const [{ data, error }, { data: enCurso }] = await Promise.all([
      supabase.rpc("fn_costos_planilla", { p_desde: mesesRecientesLima(12, hoy)[11], p_hasta: hoy }),
      supabase.from("periodos_planilla").select("fecha_ini, fecha_fin").lte("fecha_ini", hoy).gte("fecha_fin", hoy).limit(1),
    ]);
    if (error) throw new Error(mensajeDeError(error, "traer el costo de planilla"));
    const por = ((data as unknown as { por_periodo?: PeriodoCosto[] } | null)?.por_periodo) ?? [];
    return columnasDeCosto(por, (enCurso?.[0] as { fecha_ini: string; fecha_fin: string } | undefined) ?? null);
  });

  // Un botón por sede QUE TIENE días medidos; las que no, no son un botón muerto sino una línea que lo dice
  // («Sin días medidos en este periodo: …»), para que nadie crea que la sede no existe. En producción (medido
  // el 2026-10-19) Central y Oficina Trujillo sí tienen gente medible; una sede con 0 —«003»— queda en la línea.
  const conDatos = new Set(asist.cargando || asist.error !== null ? [] : asist.datos.map((f) => f.sede_codigo));
  const sedesVisibles = asist.cargando || asist.error !== null ? [] : sedes.filter((s) => conDatos.has(s.codigo) || s.codigo === sede).map((s) => s.codigo);
  const sedesSinDatos = asist.cargando || asist.error !== null ? [] : sedes.filter((s) => !conDatos.has(s.codigo) && s.codigo !== sede);
  const filtradas = useMemo(() => (asist.cargando || asist.error !== null ? [] : asist.datos.filter((f) => !sede || f.sede_codigo === sede)), [asist, sede]);

  const SIN_DIAS_DE_SEDE = "Esta sede no tiene días medidos en el periodo. No se mide a quien cobra sueldo fijo, por recibo o es personal de dirección, ni a quien no tiene horario cargado.";
  return (
    <div className="grid gap-4">
      {/* ── Qué periodo y qué sede: lo que se toca, a la vista ── */}
      <div className={`flex flex-wrap items-center gap-2${interruptoresVidrio().panel ? " vidrio-riel" : ""}`} role="group" aria-label="Periodo y sede de las tendencias">
        {PERIODOS.map((p) => <Filtro key={p.clave} tamano="sm" activo={periodo === p.clave} onClick={() => setPeriodo(p.clave)}>{p.texto}</Filtro>)}
        {sedesVisibles.length > 1 && (
          <>
            <span aria-hidden className="mx-1 h-4 w-px bg-sand" />
            <Filtro tamano="sm" activo={sede === null} onClick={() => setSede(null)}>Todas las sedes</Filtro>
            {sedesVisibles.map((s) => <Filtro key={s} tamano="sm" activo={sede === s} onClick={() => setSede(s)}>{nombreDeSede(s)}</Filtro>)}
          </>
        )}
      </div>
      {sedesSinDatos.length > 0 && (
        <p className="-mt-2 text-xs text-taupe">Sin días medidos en este periodo: {sedesSinDatos.map((s) => s.nombre).join(", ")}.</p>
      )}

      <Seccion
        titulo="Asistencia sobre lo esperado"
        que="De los días que tocaba trabajar, en cuántos hubo marca. Por semana."
        queCorto="En cuántos de los días que tocaba trabajar hubo marca."
        nota={<>Cuenta los días que tocaba trabajar, sin vacaciones, descansos, feriados ni días con motivo; no incluye a quien cobra por recibo, tiene sueldo fijo o es personal de dirección. Cada sede cuenta a su gente de hoy. La semana en curso va hueca porque no terminó.</>}
      >
        <Cuerpo estado={asist} reintentar={reintentarAsist}
          vacio={() => (asistenciaSemanal(filtradas, hoy, sede).every((p) => p.pct === null) ? (sede ? SIN_DIAS_DE_SEDE : "Todavía no hay semanas completas que mostrar en este periodo.") : null)}
          hijos={() => {
            const puntos = asistenciaSemanal(filtradas, hoy, sede);
            const piso = pisoDeLinea(puntos);
            return (<>
              <LineaAsistencia puntos={puntos} />
              {piso !== null && piso > 0 && <p className="mt-1 text-xs text-taupe">{interruptoresVidrio().panel ? `El eje empieza en ${piso} %, no en 0.` : `El eje empieza en ${piso} %, no en 0: así se ven las diferencias chicas. No es una caída tan grande como parece.`}</p>}
            </>);
          }} />
      </Seccion>

      <Seccion
        titulo="Días perdidos, por motivo"
        que="Todo lo que se perdió de los días que tocaba trabajar, separado por qué. Por mes."
        queCorto="Lo que se perdió de los días que tocaba trabajar, y por qué."
        nota={<>La asistencia de arriba solo mira los días sin motivo, así que un descanso médico no la baja: aquí sí cuenta. Son días laborables, no de calendario. No cuenta vacaciones, descansos sustitutorios ni suspensiones. Mide a la misma gente que la asistencia, con su equipo de hoy; nunca por persona. Más de cuatro motivos: los tres más grandes van solos y el resto junto. El mes que el periodo o el día de hoy cortan va rayado.</>}
      >
        <Cuerpo estado={combinar(asist, faltas)} reintentar={() => { reintentarAsist(); reintentarFaltas(); }}
          vacio={([a, f]) => (diasPerdidosPorMes(f.filas, a, desde, hoy, sede).meses.length === 0 ? (sede ? SIN_DIAS_DE_SEDE : "Todavía no hay días medidos en este periodo.") : null)}
          hijos={([a, f]) => {
            const d = diasPerdidosPorMes(f.filas, a, desde, hoy, sede);
            if (d.motivos.length === 0) return <EstadoVacio>No se perdió ningún día que tocaba trabajar en este periodo.</EstadoVacio>;
            return (
              <DiasPerdidosGrafico
                datos={d}
                nombreDe={(clave) => (clave === SIN_JUSTIFICAR ? "Faltas sin justificar" : clave === OTROS_MOTIVOS ? "Otros motivos" : nombreDeMotivo(clave, f.nombres))}
              />
            );
          }} />
      </Seccion>

      <Seccion
        titulo="A qué hora llega cada sede"
        que="Frente a la hora de entrada de cada quien: el punto es lo típico y la franja, lo que pasa casi siempre."
        queCorto="El punto es lo típico; la franja, lo que pasa casi siempre."
        nota="Mide solo los días en que el sistema guardó con qué horario se midió la jornada, así que la historia empieza más tarde que la de asistencia. Nunca por persona."
      >
        <Cuerpo estado={asist} reintentar={reintentarAsist}
          vacio={() => (llegadaPorSede(filtradas).length === 0 ? (sede ? SIN_DIAS_DE_SEDE : "Todavía no hay llegadas medidas en este periodo.") : null)}
          hijos={() => <LlegadaPorSede sedes={llegadaPorSede(filtradas)} nombreDe={nombreDeSede} />} />
      </Seccion>

      <Seccion
        titulo="Cuándo se llega tarde"
        que="En qué día de la semana pasa más seguido, por sede."
        queCorto="En qué día pasa más seguido."
        nota="Tarde = 5 minutos o más después de la hora. «·» = pocas llegadas para decir algo; «–» = nadie de la sede trabajó ese día. Es para organizar el día, no para señalar a alguien."
      >
        <Cuerpo estado={asist} reintentar={reintentarAsist}
          vacio={() => (calorTardanza(filtradas).length === 0 ? (sede ? SIN_DIAS_DE_SEDE : "Todavía no hay llegadas medidas en este periodo.") : null)}
          hijos={() => <CalorTardanza filas={calorTardanza(filtradas)} nombreDe={nombreDeSede} />} />
      </Seccion>

      {tiendas.length > 0 && (
        <Seccion
          titulo="Gente en piso frente a la venta"
          que={`Hora por hora: cuántas compras hubo, cuánta gente había en piso y cuánta pedía la venta. Últimos ${DIAS_DE_PISO} días.`}
          queCorto={`Hora por hora, en los últimos ${DIAS_DE_PISO} días.`}
          nota={<>Una compra es un ticket completado de Retail. En piso es el peor cuarto de cada hora, sin quien está en almacén, en refrigerio o en pausa: la misma cuenta que la repetición del día en Turnos. Lo que pedía la venta son las compras de la hora divididas por el ritmo de la tienda, nunca menos que su mínimo (Parámetros). Solo se miran las horas enteras dentro del horario de la tienda (de la primera entrada a la última salida de su equipo): en la que abre o cierra a medias, el peor cuarto cae con la tienda cerrada. Una hora con menos de cuatro días medidos no se marca. Nunca por persona.</>}
        >
          {tienda === null ? (
            <EstadoVacio>{sedeArriba?.nombre ?? "Esta sede"} no es tienda: este gráfico mira la venta de cada hora.</EstadoVacio>
          ) : (
            <>
              <div className="mb-3 flex flex-wrap items-center gap-2" role="group" aria-label="Tienda y días">
                {!sedeArriba && tiendas.length > 1 && (
                  <>
                    {tiendas.map((t) => <Filtro key={t.codigo} tamano="sm" activo={tienda.codigo === t.codigo} onClick={() => setTiendaPropia(t.codigo)}>{t.nombre}</Filtro>)}
                    <span aria-hidden className="mx-1 h-4 w-px bg-sand" />
                  </>
                )}
                {TIPOS_DE_DIA.map((t) => <Filtro key={t.clave} tamano="sm" activo={tipoDeDia === t.clave} onClick={() => setTipoDeDia(t.clave)}>{t.texto}</Filtro>)}
              </div>
              <Cuerpo estado={piso} reintentar={reintentarPiso}
                vacio={(d) => (pisoPorHora(d.dias, tipoDeDia).length === 0 ? `Todavía no hay días con marcas en ${tienda.nombre} para mirar.` : null)}
                hijos={(d) => <PisoYVentaGrafico horas={pisoPorHora(d.dias, tipoDeDia)} comprasFallo={d.comprasFallo} />} />
            </>
          )}
        </Seccion>
      )}

      {veCasos === true && (
        <Seccion
          titulo="Reportes por motivo"
          que="Sobre qué trata lo que el equipo reporta. Últimos 12 meses."
          nota={`Una categoría solo aparece si tiene al menos ${MINIMO_CASOS} reportes; las más chicas se juntan en «Otras categorías». No incluye los de Título X, que nunca se separan, ni se muestra el total.`}
        >
          <Cuerpo estado={casos} reintentar={reintentarCasos}
            vacio={(d) => (d.hayQueMostrar ? null : "Todavía no hay suficientes reportes para mostrar sin identificar a nadie.")}
            hijos={(d) => <BarrasCasos datos={d} />} />
        </Seccion>
      )}

      {verPlanilla && (
        <Seccion
          titulo="Costo de planilla por periodo"
          que="Lo que costó cada periodo ya pagado (del 29 al 28). Últimos 12 meses."
          queCorto="Cada periodo ya pagado, del 29 al 28."
          nota="Solo cuenta periodos marcados como pagados, tal como se pagaron. El que está en curso va rayado y sin monto: todavía no es un hecho. «Retroactivo» = reconstruido después del pago."
        >
          <Cuerpo estado={costo} reintentar={reintentarCosto}
            vacio={(d) => (d.length === 0 ? "Todavía no hay periodos pagados que mostrar." : null)}
            hijos={(d) => <ColumnasCosto columnas={d} />} />
        </Seccion>
      )}
    </div>
  );
}

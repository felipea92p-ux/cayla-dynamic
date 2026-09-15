"use client";

// /admin/provisiones — rediseño del 2026-09-15.
//
// Qué tiene que responder en diez segundos: cuánto hay por beneficio, qué sale
// del banco y cuándo, y quién requiere revisión. Y al abrir a una persona: qué
// ya se pagó, qué se acumula, qué falta y cuándo toca.
//
// Las decisiones, tomadas con Felipe ese día sobre demos navegables:
//   · Resumen arriba + tabla de siete columnas + detalle en panel lateral.
//   · Indicadores por beneficio con su nombre exacto («saldo no pagado al
//     corte»), no un «total provisionado» que prometa más de lo que es.
//   · Calendario con lo vencido primero y lo que viene como acumulado a hoy;
//     la proyección al cierre va después, en su propia función SQL auditada.
//   · El negativo se muestra como «pagado de más» con su origen.
//   · Practicantes en una sección plegada; honorarios y días de prueba siguen
//     sin fila (0274).
//   · Corte siempre al día de hoy: recalcular una fecha pasada descuenta pagos
//     posteriores. Las fotos al cerrar planilla son una fase aparte.
//
// NADA DE ESTO TOCA EL CÁLCULO. `fn_provisiones` es la misma (0428) y también
// alimenta el pago real vía `fn_grati_cts_periodo`. Toda la lectura vive en
// `lib/admin/provisiones.ts`, con sus pruebas.

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { puedeVerPlanilla } from "@cayla-dynamic/shared";
import { Cargando } from "@/components/cargando";
import { useRolActual } from "@/lib/admin/use-rol";
import { descargarCsv, generarCsv } from "@/lib/admin/csv";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Drawer } from "@/components/ui/drawer";
import { cx } from "@/components/ui/cx";
import {
  COLUMNAS_CSV,
  ETIQUETA_ESTADO_FILA,
  FILTROS_VACIOS,
  esPracticante,
  fechaCorta,
  filasCsv,
  filtrar,
  hayFiltros,
  type DesembolsoLibro,
  type EstadoFila,
  type FiltrosProvisiones,
  type ProvData,
  type ProvPersona,
} from "@/lib/admin/provisiones";
import { CalendarioPagos, ResumenProvisiones } from "./ResumenYCalendario";
import { Practicantes, TablaProvisiones } from "./TablaProvisiones";
import { DetallePersona } from "./DetallePersona";

type Vista = "personas" | "calendario";
const ESTADOS_FILTRO: EstadoFila[] = ["vencido", "pagado_de_mas", "sin_tramo", "al_dia"];

export default function ProvisionesPage() {
  const router = useRouter();
  const rol = useRolActual();
  const puedeVer = puedeVerPlanilla(rol);
  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  const [data, setData] = useState<ProvData | null>(null);
  const [error, setError] = useState<string | null>(null);
  // Cargando es «todavía no hay ni datos ni error»: se deduce, no se guarda.
  // Guardarlo obligaba a encenderlo dentro del efecto de carga, que es el
  // setState síncrono que prohíbe react-hooks/set-state-in-effect.
  const cargando = !data && !error;
  // undefined = leyendo · null = no se pudo leer · arreglo = leído
  const [libro, setLibro] = useState<DesembolsoLibro[] | null | undefined>(undefined);
  const [filtros, setFiltros] = useState<FiltrosProvisiones>(FILTROS_VACIOS);
  const [vista, setVista] = useState<Vista>("personas");
  const [comoAbierto, setComoAbierto] = useState(false);
  const [persona, setPersona] = useState<ProvPersona | null>(null);
  const [panelAbierto, setPanelAbierto] = useState(false);
  const focoAlAbrir = useRef<HTMLElement | null>(null);

  // Si el rol no llega en ~6 s, avisar en vez de un "Cargando…" eterno.
  // Solo se lee mientras rol === null, así que no hace falta apagarlo cuando
  // llega: apagarlo dentro del efecto era un setState síncrono.
  const [rolDemorado, setRolDemorado] = useState(false);
  useEffect(() => {
    if (rol !== null) return;
    const t = window.setTimeout(() => setRolDemorado(true), 6000);
    return () => window.clearTimeout(t);
  }, [rol]);

  // Sin sesión no hay panel
  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      if (!data.session) router.replace("/admin/login");
    });
  }, [supabase, router]);

  const cargar = useCallback(async () => {
    if (!puedeVer) return;
    const { data, error } = await supabase.rpc("fn_provisiones"); // sin args = a hoy
    if (error) {
      setError(error.message);
      return;
    }
    const d = data as unknown as ProvData;
    setError(null);
    setData(d);

    // EL LIBRO SE LEE APARTE, Y SU FALLA NO TUMBA LA PANTALLA. De él salen solo
    // la fecha y la vía de cada pago; los montos ya vienen en fn_provisiones.
    // Si esta lectura falla, todo se sigue viendo, el panel lo dice y el CSV
    // escribe «no disponible» en esas columnas en vez de dejarlas vacías.
    // Mismo año que usa la base para descontar (`v_y`): el de la fecha de corte.
    setLibro(undefined);
    const { data: filas, error: errorLibro } = await supabase
      .from("desembolsos_beneficios")
      .select("persona_id, ventana, anio, monto, fecha_pago, origen, nota, created_at")
      .eq("anio", Number(d.as_of.slice(0, 4)));
    setLibro(errorLibro ? null : (filas ?? []).map((f) => ({ ...f, monto: Number(f.monto) })));
  }, [supabase, puedeVer]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- cargar al montar, mismo patrón que el resto del panel (disciplina, educación, bandeja).
    void cargar();
  }, [cargar]);

  // ── Derivados ──────────────────────────────────────────────────────────────
  // Las sedes salen de las filas, no de una lista escrita a mano.
  const sedes = useMemo(
    () => Array.from(new Set((data?.personas ?? []).map((p) => p.sede))).sort(),
    [data],
  );
  const filtradas = useMemo(() => (data ? filtrar(data.personas, data, filtros) : []), [data, filtros]);
  const conDerecho = useMemo(() => filtradas.filter((p) => !esPracticante(p)), [filtradas]);
  const practicantes = useMemo(() => filtradas.filter(esPracticante), [filtradas]);
  const filtrado = hayFiltros(filtros);

  // CAMBIO 0365 — quienes hoy SÍ tienen tramo pero tuvieron un hueco dentro del
  // año que reserva. `personas_sin_salario` (de la base) no los cuenta.
  const conHueco = useMemo(
    () => (data?.personas ?? []).filter((p) => !p.sin_salario_vigente && (p.dias_sin_salario ?? 0) > 0).length,
    [data],
  );

  const limpiar = () => setFiltros(FILTROS_VACIOS);

  function abrir(p: ProvPersona, origen: HTMLElement) {
    focoAlAbrir.current = origen;
    setPersona(p);
    setPanelAbierto(true);
  }

  function descargar() {
    if (!data) return;
    const csv = generarCsv(filasCsv(data, filtradas, libro ?? null), [...COLUMNAS_CSV]);
    descargarCsv(`provisiones-${data.as_of}.csv`, csv);
  }

  // ── Gating ──────────────────────────────────────────────────────────────────
  if (rol === null) {
    return (
      <div className="flex flex-1 flex-col">
        <main className="flex-1 p-6">
          {rolDemorado ? (
            <p className="max-w-md rounded-control bg-rojo/10 px-4 py-3 text-sm text-rojo">
              No se pudo identificar tu usuario — cierra sesión y vuelve a entrar.
            </p>
          ) : (
            <Cargando />
          )}
        </main>
      </div>
    );
  }
  if (!puedeVer) {
    return (
      <div className="flex flex-1 flex-col">
        <main className="flex-1 p-6">
          <p className="max-w-md rounded-control bg-rojo/10 px-4 py-3 text-sm text-rojo">
            Solo administración y el equipo de Desarrollo Organizacional pueden ver las provisiones.
          </p>
        </main>
      </div>
    );
  }

  const soloSede = filtros.sede && !filtros.texto.trim() && !filtros.estado;
  const vacio = !filtrado ? (
    "No hay personas con provisiones."
  ) : soloSede ? (
    "No hay personas con provisiones para esta sede."
  ) : (
    <>
      No encontramos resultados con estos filtros.{" "}
      <Boton variante="enlace" onClick={limpiar}>
        Limpiar filtros
      </Boton>
    </>
  );

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        <CabeceraPagina
          titulo="Provisiones"
          descripcion={
            <>
              Obligaciones laborales acumuladas y próximos desembolsos.
              {data && (
                <span className="mt-2 flex flex-wrap items-center gap-3">
                  <span className="rounded-pildora bg-sand px-2.5 py-0.5 text-xs font-medium text-tinta">
                    Al {fechaCorta(data.as_of)}
                  </span>
                  <Boton
                    variante="enlace"
                    className="text-xs"
                    aria-expanded={comoAbierto}
                    aria-controls="como-se-calculan"
                    onClick={() => setComoAbierto((v) => !v)}
                  >
                    ⓘ Cómo se calculan las provisiones
                  </Boton>
                </span>
              )}
            </>
          }
          accion={
            data && (
              <Boton
                variante="secundario"
                onClick={descargar}
                cargando={libro === undefined}
                disabled={filtradas.length === 0}
              >
                Descargar CSV
              </Boton>
            )
          }
        />

        {data && comoAbierto && (
          <div id="como-se-calculan">
            <TarjetaInfo
              titulo="Cómo se calculan las provisiones"
              className="mb-6 max-w-3xl"
              accion={
                <Boton variante="enlace" className="text-sm" onClick={() => setComoAbierto(false)}>
                  Cerrar
                </Boton>
              }
            >
              <ComoSeCalculan data={data} />
            </TarjetaInfo>
          </div>
        )}

        {error && (
          <div className="mb-4 max-w-3xl rounded-control bg-rojo/10 px-4 py-3 text-sm text-rojo">
            No se pudieron cargar las provisiones: {error}{" "}
            <Boton variante="enlace" className="font-medium" onClick={() => void cargar()}>
              Reintentar
            </Boton>
          </div>
        )}

        {cargando && !data && <Cargando />}

        {data && (
          <>
            <ResumenProvisiones
              data={data}
              personas={conDerecho}
              filtrado={filtrado}
              onVerCalendario={() => setVista("calendario")}
            />

            {/* SIN TRAMO DE SALARIO (CAMBIO 0365). Un cero puede ser «aún no
                devengó» o «nadie le cargó el tramo»; la base lo cuenta una vez
                arriba para no tener que recorrer la tabla buscando el cero que miente. */}
            {((data.personas_sin_salario ?? 0) > 0 || conHueco > 0) && (
              <BannerAviso variante="alerta" className="mb-6 max-w-3xl">
                {(data.personas_sin_salario ?? 0) > 0 && (
                  <>
                    <strong className="font-medium">
                      {data.personas_sin_salario} {data.personas_sin_salario === 1 ? "persona" : "personas"} sin
                      tramo de salario vigente:
                    </strong>{" "}
                    sus reservas salen cortas o en cero, no porque no les toque. Asígnale el salario en Equipo
                    para que la reserva se calcule.{" "}
                  </>
                )}
                {conHueco > 0 && (
                  <span>
                    {(data.personas_sin_salario ?? 0) > 0 ? "Y " : ""}
                    {conHueco === 1 ? "una persona" : `${conHueco} personas`}
                    {(data.personas_sin_salario ?? 0) > 0 ? " más " : " "}
                    {conHueco === 1 ? "tiene" : "tienen"} días sin tramo dentro del año que reserva: esos días
                    no cuentan.
                  </span>
                )}
              </BannerAviso>
            )}

            <div className="mb-4 flex flex-wrap items-end gap-3">
              <div role="tablist" aria-label="Vista" className="inline-flex rounded-control border border-sand bg-hueso p-1">
                {(
                  [
                    ["personas", "Por persona"],
                    ["calendario", "Calendario de pagos"],
                  ] as const
                ).map(([clave, etiqueta]) => (
                  <button
                    key={clave}
                    type="button"
                    role="tab"
                    aria-selected={vista === clave}
                    onClick={() => setVista(clave)}
                    className={cx(
                      "rounded-[6px] px-3 py-1.5 text-sm font-medium transition-colors duration-150",
                      vista === clave ? "bg-papel text-tinta ring-1 ring-sand" : "text-taupe hover:text-tinta",
                    )}
                  >
                    {etiqueta}
                  </button>
                ))}
              </div>
            </div>

            <div role="search" className="mb-4 flex flex-wrap items-center gap-3">
              <div className="w-full sm:w-64">
                <Campo
                  id="provisiones-buscar"
                  type="search"
                  aria-label="Buscar persona"
                  placeholder="Buscar persona…"
                  value={filtros.texto}
                  onChange={(e) => setFiltros((f) => ({ ...f, texto: e.target.value }))}
                />
              </div>
              <CampoSelect
                id="provisiones-sede"
                aria-label="Sede"
                value={filtros.sede}
                onChange={(e) => setFiltros((f) => ({ ...f, sede: e.target.value }))}
              >
                <option value="">Todas las sedes</option>
                {sedes.map((s) => (
                  <option key={s} value={s}>
                    {s}
                  </option>
                ))}
              </CampoSelect>
              <CampoSelect
                id="provisiones-estado"
                aria-label="Estado"
                value={filtros.estado}
                onChange={(e) => setFiltros((f) => ({ ...f, estado: e.target.value as EstadoFila | "" }))}
              >
                <option value="">Todos los estados</option>
                {ESTADOS_FILTRO.map((e) => (
                  <option key={e} value={e}>
                    {ETIQUETA_ESTADO_FILA[e]}
                  </option>
                ))}
              </CampoSelect>
              {filtrado && (
                <Boton variante="enlace" className="text-sm" onClick={limpiar}>
                  Limpiar filtros
                </Boton>
              )}
              <span className="text-xs text-taupe sm:ml-auto">
                {filtradas.length} de {data.personas.length} personas
              </span>
            </div>

            {vista === "personas" ? (
              <>
                <TablaProvisiones data={data} personas={conDerecho} onAbrir={abrir} vacio={vacio} />
                <Practicantes personas={practicantes} onAbrir={abrir} />
              </>
            ) : (
              <CalendarioPagos data={data} personas={conDerecho} />
            )}

            <Drawer
              abierto={panelAbierto}
              onCerrar={() => setPanelAbierto(false)}
              titulo={persona?.nombre}
              ancho="amplio"
              volverElFocoA={focoAlAbrir}
            >
              {persona && <DetallePersona data={data} persona={persona} libro={libro} />}
            </Drawer>
          </>
        )}
      </main>
    </div>
  );
}

// Lo que antes eran tres párrafos legales encima de la tabla. No se eliminó:
// se movió aquí, y ganó lo que faltaba decir — los límites que la auditoría
// del 2026-09-15 midió y que todavía no tienen arreglo.
function ComoSeCalculan({ data }: { data: ProvData }) {
  const f = data.factores ?? {};
  const pct = (x: number | undefined) =>
    x == null ? "—" : `${(x * 100).toLocaleString("es-PE", { maximumFractionDigits: 2 })} %`;
  const tasaBe = data.personas[0]?.tasa_be ?? 0.09;
  return (
    <ul className="grid list-disc gap-2 pl-5 text-sm">
      <li>
        <strong className="font-medium">Régimen MYPE pequeña empresa.</strong> Sobre lo ganado cada día —horas,
        sueldo fijo, asignación familiar, ausencias pagadas aprobadas y feriados— se reserva {pct(f.gratificacion)}{" "}
        de gratificación, {pct(f.cts)} de CTS{f.sexto_cts ? " (con el sexto de la gratificación)" : ""} y{" "}
        {pct(f.vacaciones)} de vacaciones. La bonificación extraordinaria es el {pct(tasaBe)} de la gratificación
        (Ley 30334).
      </li>
      <li>
        <strong className="font-medium">Cada cifra es lo que falta:</strong> lo devengado menos lo ya pagado, por
        planilla o anotado en el libro de desembolsos (se toma la mayor de las dos, nunca la suma). Si se pagó
        más de lo devengado, sale en negativo como «pagado de más».
      </li>
      <li>
        <strong className="font-medium">Cuándo se paga:</strong> la gratificación y su 9 % el 15 de julio (ene–jun)
        y el 15 de diciembre (jul–dic). La CTS se deposita en la cuenta CTS del banco —no en efectivo— el 15 de
        mayo (nov–abr) y el 15 de noviembre (may–oct). Las vacaciones acumulan desde cada aniversario y se pagan al
        gozarlas.
      </li>
      <li>
        <strong className="font-medium">Quién aparece:</strong> quien devenga algún beneficio, aunque hoy sume cero
        (por ejemplo, quien entró esta semana). Las practicantes van en su propia sección: por la Ley 28518 no
        generan estos beneficios. Quien cobra por recibo por honorarios o está en días de prueba no ocupa fila: no
        hay nada que reservarle.
      </li>
      <li>
        <strong className="font-medium">Límites que conviene saber:</strong> solo se muestran las ventanas del año
        de corte, así que una ventana del año anterior que no quedó registrada como pagada deja de verse el 1 de
        enero. La CTS que acumulan noviembre y diciembre aparece recién el 1 de enero, y del 16 al 31 de
        diciembre el monto del próximo pago no está disponible.
      </li>
      <li>Cifras referenciales: el contador cierra los montos.</li>
    </ul>
  );
}

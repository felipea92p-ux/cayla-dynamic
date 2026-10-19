"use client";

// ============================================================================
// Costos — lo que cuesta el equipo
// ----------------------------------------------------------------------------
// Lee SOLO la foto de los pagos congelados (migraciones 0096 y 0097). Un
// periodo que todavía no se marcó como pagado no aparece aquí, y eso es a
// propósito: su número aún se mueve, y un costo que se mueve no es un costo.
// La proyección del periodo en curso vive donde siempre, en Planilla.
//
// TRES cifras distintas, y la pantalla no las mezcla nunca:
//   · «Se transfirió»   — lo que recibió la gente.
//   · «Costo real»      — eso más las provisiones (gratificación, CTS y
//                         vacaciones que se devengan aunque se paguen después).
//   · «Salió del banco» — lo que recibió la gente MÁS lo que CAYLA remite por
//                         ella: pensión a la AFP o la ONP, el 9 % de EsSalud y
//                         la retención de renta de 4ta (mig. 0260).
// Mirar solo la primera subestima el costo del equipo en torno a un 16,7 %.
//
// LAS DOS ÚLTIMAS RESPONDEN PREGUNTAS DISTINTAS y ninguna reemplaza a la otra.
// «Costo real» es la vista DEVENGADA, la que usa el contador: incluye lo que se
// pagará después y excluye lo que se remite por la persona. «Salió del banco»
// es la de CAJA: lo contrario en las dos mitades. Medido sobre un periodo
// cerrado de prueba, en alguien de planilla la diferencia entre las dos es de
// S/205.44 sobre S/839.04 — un 24 %.
// ============================================================================

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Cargando } from "@/components/cargando";
import { AyudaPantalla } from "@/components/ui/ayuda-pantalla";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Boton } from "@/components/ui/boton";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { CampoSelect } from "@/components/ui/campo";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { sobretituloDeHoy } from "@/lib/admin/sobretitulo";
import { Insignia } from "@/components/ui/insignia";
import { Fila, Tabla, TablaEncabezado, Th } from "@/components/ui/tabla";
import { useRolActual } from "@/lib/admin/use-rol";
import { formatSoles } from "@/lib/rangos";
import { descargarCsv, generarCsv } from "@/lib/admin/csv";
import { puedeVerPlanilla } from "@cayla-dynamic/shared";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { AyudaPantalla } from "@/components/ui/ayuda-pantalla";
import { sobretituloDeHoy } from "@/lib/admin/sobretitulo";

const MESES = [
  "enero", "febrero", "marzo", "abril", "mayo", "junio",
  "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
];

// "2026-07-15" → "15/07/2026". Por string a propósito: `new Date("2026-07-15")`
// se interpreta en UTC y en Lima retrocede un día.
function fechaCorta(iso: string | null | undefined): string {
  if (!iso) return "—";
  const [y, m, d] = iso.split("-");
  if (!y || !m || !d) return iso;
  return `${d}/${m}/${y}`;
}

interface Totales {
  personas: number;
  periodos: number;
  neto: number;
  provisiones: number;
  costo: number;
  // Lo que salió de la cuenta (0260): el neto más lo que CAYLA remite por la
  // persona — pensión, EsSalud y retención de 4ta. Opcional: sin la 0260
  // pegada no viene, y la pantalla no dibuja la cifra en vez de decir NaN.
  salio_del_banco?: number;
}
interface PorPeriodo {
  periodo_id: string;
  fecha_ini: string;
  fecha_fin: string;
  anio: number;
  mes: number;
  pagado_at: string | null;
  congelada_at: string;
  version: number;
  reconstruida: boolean;
  personas: number;
  neto: number;
  provisiones: number;
  costo: number;
  salio_del_banco?: number;
}
interface PorGrupo {
  nombre: string;
  personas: number;
  neto: number;
  provisiones: number;
  costo: number;
  salio_del_banco?: number;
}
interface PorSede extends PorGrupo {
  sede: string;
  tipo: "central" | "taller" | "tienda";
  horas: number;
  costo_por_persona: number | null;
  costo_por_hora: number | null;
}
interface PorTipo {
  tipo: "central" | "taller" | "tienda";
  sedes: number;
  personas: number;
  horas: number;
  neto: number;
  provisiones: number;
  costo: number;
  costo_por_persona: number | null;
  costo_por_hora: number | null;
  salio_del_banco?: number;
}
interface PorArea extends PorGrupo { area: string | null; operativa: boolean }
interface PorPersona {
  persona_id: string;
  nombre: string;
  sede: string;
  area: string | null;
  periodos: number;
  horas: number;
  neto: number;
  provisiones: number;
  costo: number;
  salio_del_banco?: number;
}
interface Costos {
  desde: string;
  hasta: string;
  periodos_retroactivos: number;
  totales: Totales;
  por_periodo: PorPeriodo[];
  por_sede: PorSede[];
  por_tipo: PorTipo[];
  por_area: PorArea[];
  por_persona: PorPersona[];
}

const ETIQUETA_TIPO: Record<string, string> = {
  tienda: "Tiendas",
  taller: "Taller",
  central: "Central (administración y DO)",
};

// Encabezados de tabla: TablaEncabezado + Th (@/components/ui/tabla), como el
// resto del panel. Solo queda este ayudante para las celdas numéricas, que el
// primitivo compartido deja a propósito fuera de su superficie (ver el
// comentario de tabla.tsx).
const NUM = "px-4 py-2 text-right tabular-nums";

export default function CostosPage() {
  const router = useRouter();
  const rol = useRolActual();
  const puedeVer = puedeVerPlanilla(rol);
  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  const [anios, setAnios] = useState<number[]>([]);
  const [anio, setAnio] = useState<number | null>(null);
  const [data, setData] = useState<Costos | null>(null);
  const [cargando, setCargando] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [rolDemorado, setRolDemorado] = useState(false);
  useEffect(() => {
    if (rol !== null) { setRolDemorado(false); return; }
    const t = window.setTimeout(() => setRolDemorado(true), 6000);
    return () => window.clearTimeout(t);
  }, [rol]);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      if (!data.session) router.replace("/admin/login");
    });
  }, [supabase, router]);

  // Los años que ofrecemos salen de los periodos que existen, no de un rango
  // inventado: así la lista nunca ofrece un año vacío ni esconde uno con datos.
  // Se usa `fn_periodos` —la misma fuente que la pantalla de Planilla— para que
  // las dos no puedan discrepar sobre qué periodos hay.
  const vivoRef = useRef(true);
  useEffect(() => () => { vivoRef.current = false; }, []);

  // Si esta consulta falla, NO es lo mismo que "todavía no hay periodos
  // pagados": es un error real, y se guarda en el mismo `error` que usa
  // `cargar()` para que la pantalla pinte la banda roja con "Reintentar" en
  // vez de la frase tranquilizadora de la lista vacía.
  const cargarAnios = useCallback(async () => {
    if (!puedeVer) return;
    const { data, error } = await supabase.rpc("fn_periodos");
    if (!vivoRef.current) return;
    if (error || !data) {
      setError(error?.message ?? "No se pudo cargar la lista de periodos.");
      return;
    }
    const lista = data as unknown as Array<{ fecha_fin: string; estado: string }>;
    const ys = Array.from(
      new Set(lista.filter((p) => p.estado === "pagado").map((p) => Number(p.fecha_fin.slice(0, 4)))),
    ).sort((a, b) => b - a);
    setAnios(ys);
    setAnio((prev) => prev ?? ys[0] ?? null);
  }, [supabase, puedeVer]);

  // Cargar al montar es el mismo patrón que usa cada pantalla del panel que
  // trae datos de la base; el aviso de acá es el mismo que ya tienen todas
  // ellas sin corregir.
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargarAnios(); }, [cargarAnios]);

  const cargar = useCallback(async () => {
    if (!puedeVer || anio === null) return;
    setCargando(true);
    setError(null);
    const { data, error } = await supabase.rpc("fn_costos_planilla", {
      p_desde: `${anio}-01-01`,
      p_hasta: `${anio}-12-31`,
    });
    setCargando(false);
    if (error) { setError(error.message); return; }
    setData(data as unknown as Costos);
  }, [supabase, puedeVer, anio]);

  // Mismo patrón y mismo motivo que el efecto de cargarAnios, arriba.
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargar(); }, [cargar]);

  // Un solo botón "Reintentar" sirve a dos consultas distintas. Si todavía no
  // hay años (la lista de periodos nunca llegó a cargar), reintenta esa; si
  // ya hay años pero el año elegido falló, reintenta el costo de ese año.
  function reintentar() {
    setError(null);
    if (anios.length === 0) { void cargarAnios(); } else { void cargar(); }
  }

  // El código de una sede puede ser "003": en una tabla que va a leer una
  // persona, eso no dice nada. Se traduce al nombre usando por_sede, que ya
  // viene cargado — sin pedirle otra cosa a la base.
  const nombreDeSede = useMemo(
    () => new Map((data?.por_sede ?? []).map((s) => [s.sede, s.nombre])),
    [data],
  );

  function descargarCsvCostos() {
    if (!data) return;
    const tipoDeSede = new Map(data.por_sede.map((s) => [s.sede, s.tipo]));
    const filas = data.por_persona.map((p) => ({
      nombre: p.nombre,
      sede: nombreDeSede.get(p.sede) ?? p.sede,
      tipo_de_sede: tipoDeSede.get(p.sede) ?? "",
      area: p.area ?? "",
      periodos_pagados: p.periodos,
      horas: p.horas,
      se_transfirio: p.neto,
      provisiones: p.provisiones,
      costo_real: p.costo,
      salio_del_banco: p.salio_del_banco ?? "",
    }));
    const csv = generarCsv(filas, [
      "nombre", "sede", "tipo_de_sede", "area", "periodos_pagados", "horas",
      "se_transfirio", "provisiones", "costo_real", "salio_del_banco",
    ]);
    descargarCsv(`costos-${anio}.csv`, csv);
  }

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
            Solo administradores y líderes pueden ver los costos de planilla.
          </p>
        </main>
      </div>
    );
  }

  const t = data?.totales;

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        <CabeceraPagina
          sobretitulo={sobretituloDeHoy("Pago")}
          titulo="Costos del equipo"
          descripcion="Lo que costó el equipo en los periodos ya pagados. Lo que sigue abierto se ve en Planilla."
          ayuda={
            <AyudaPantalla
              titulo="Cómo se leen los costos"
              intro="Solo aparecen los periodos ya marcados como pagados: su desglose quedó congelado y ya no cambia."
              secciones={[
                { titulo: "Costo y proyección", texto: "Lo que todavía está abierto se ve en Planilla, y es una proyección, no un costo. Aquí solo entra lo que ya se pagó." },
                { titulo: "Un periodo, no un mes", texto: "Los periodos de CAYLA no son meses calendario (van del 29 al 28), así que cada fila es un periodo." },
                { titulo: "Costo real, transferencia y banco", texto: "«Se transfirió» es lo que se pagó a las personas; el «costo real» suma además las provisiones; «salió del banco» incluye pensión, EsSalud y 4.ª." },
                { titulo: "Reconstruido", texto: "Los periodos anteriores a que el sistema guardara la foto del pago llevan el desglose reconstruido: su cifra es la de hoy, no necesariamente la que se transfirió." },
              ]}
            />
          }
          accion={
            <div className="flex items-center gap-2">
              <div className="w-28">
                <CampoSelect tamano="sm" aria-label="Año" value={anio ?? ""} onChange={(e) => setAnio(Number(e.target.value))} disabled={anios.length === 0}>
                  {anios.map((y) => (<option key={y} value={y}>{y}</option>))}
                </CampoSelect>
              </div>
              <Boton variante="secundario" onClick={descargarCsvCostos} disabled={!data || data.por_persona.length === 0}>
                Descargar CSV
              </Boton>
            </div>
          }
        />

        {error && (
          <BannerAviso role="alert" variante="alerta" enLinea className="mb-4 max-w-3xl">
            No se pudieron cargar los costos: {error}{" "}
            <Boton variante="enlace" onClick={reintentar}>Reintentar</Boton>
          </BannerAviso>
        )}

        {cargando && !data && (
          <Cargando />
        )}

        {anios.length === 0 && !cargando && !error && (
          <BannerAviso variante="neutral" enLinea className="max-w-3xl">
            Todavía no hay ningún periodo marcado como pagado, así que no hay costos que sumar. En cuanto
            cierres el primero, aparecerá aquí.
          </BannerAviso>
        )}

        {data && data.periodos_retroactivos > 0 && (
          <BannerAviso variante="advertencia" enLinea className="mb-4 max-w-3xl">
            {data.periodos_retroactivos === 1
              ? "Un periodo de este año tiene el desglose reconstruido"
              : `${data.periodos_retroactivos} periodos de este año tienen el desglose reconstruido`}{" "}
            en vez de congelado el día del pago: son anteriores a que el sistema guardara la foto. Su cifra
            es la de hoy, no necesariamente la que se transfirió. Los periodos que cierres de ahora en
            adelante quedan congelados en el momento exacto del pago.
          </BannerAviso>
        )}

        {t && (
          /* La franja del año: el costo real manda; el resto es el desglose de dónde sale. */
          <TarjetaInfo className="mb-6 flex max-w-5xl flex-wrap items-center gap-x-8 gap-y-3">
            <div>
              <p className="text-xs text-taupe">Costo real del año</p>
              <p className="font-serif text-3xl leading-none tabular-nums text-tinta">{formatSoles(t.costo)}</p>
            </div>
            <dl className="flex flex-wrap gap-x-8 gap-y-2 text-sm">
              <div><dt className="text-xs text-taupe">Se transfirió</dt><dd className="font-medium tabular-nums">{formatSoles(t.neto)}</dd></div>
              <div><dt className="text-xs text-taupe">Provisiones devengadas</dt><dd className="font-medium tabular-nums">{formatSoles(t.provisiones)}</dd></div>
              {t.salio_del_banco !== undefined && (
                <div><dt className="text-xs text-taupe">Salió del banco <span className="text-taupe/80">(+ pensión, EsSalud y 4.ª)</span></dt><dd className="font-medium tabular-nums">{formatSoles(t.salio_del_banco)}</dd></div>
              )}
              <div><dt className="text-xs text-taupe">Periodos cerrados</dt><dd className="font-medium tabular-nums">{t.periodos} <span className="text-xs font-normal text-taupe">· {t.personas} personas</span></dd></div>
            </dl>
          </TarjetaInfo>
        )}

        {data && data.por_periodo.length > 0 && (
          <>
            <SeccionTabla titulo="Por periodo">
              <TablaEncabezado>
                <Th>Periodo</Th>
                <Th>Cerró en</Th>
                <Th className="text-right">Personas</Th>
                <Th className="text-right">Se transfirió</Th>
                <Th className="text-right">Provisiones</Th>
                <Th className="text-right">Costo real</Th>
                <Th className="text-right">Salió del banco</Th>
              </TablaEncabezado>
              <tbody>
                {data.por_periodo.map((p) => (
                  <Fila key={p.periodo_id}>
                    <td className="px-4 py-2">
                      {fechaCorta(p.fecha_ini)} → {fechaCorta(p.fecha_fin)}
                      {p.reconstruida && (
                        <Insignia variante="advertencia" className="ml-2">reconstruido</Insignia>
                      )}
                      {p.version > 1 && (
                        <Insignia atenuada punto={false} className="ml-2">
                          repagado ({p.version}.ª copia)
                        </Insignia>
                      )}
                    </td>
                    <td className="px-4 py-2 capitalize">{MESES[p.mes - 1]}</td>
                    <td className={NUM}>{p.personas}</td>
                    <td className={NUM}>{formatSoles(p.neto)}</td>
                    <td className={NUM}>{formatSoles(p.provisiones)}</td>
                    <td className={`${NUM} font-medium`}>{formatSoles(p.costo)}</td>
                    <td className={NUM}>{p.salio_del_banco === undefined ? "—" : formatSoles(p.salio_del_banco)}</td>
                  </Fila>
                ))}
              </tbody>
            </SeccionTabla>

            <SeccionTabla titulo="Operar tiendas · producir · administrar">
              <TablaEncabezado>
                <Th>Qué es</Th>
                <Th className="text-right">Sedes</Th>
                <Th className="text-right">Personas</Th>
                <Th className="text-right">Costo real</Th>
                <Th className="text-right">Salió del banco</Th>
                <Th className="text-right">Por persona</Th>
                <Th className="text-right">Por hora</Th>
              </TablaEncabezado>
              <tbody>
                {data.por_tipo.map((t) => (
                  <Fila key={t.tipo}>
                    <td className="px-4 py-2">{ETIQUETA_TIPO[t.tipo] ?? t.tipo}</td>
                    <td className={NUM}>{t.sedes}</td>
                    <td className={NUM}>{t.personas}</td>
                    <td className={`${NUM} font-medium`}>{formatSoles(t.costo)}</td>
                    <td className={NUM}>{t.salio_del_banco === undefined ? "—" : formatSoles(t.salio_del_banco)}</td>
                    <td className={NUM}>{t.costo_por_persona === null ? "—" : formatSoles(t.costo_por_persona)}</td>
                    <td className={NUM}>{t.costo_por_hora === null ? "—" : formatSoles(t.costo_por_hora)}</td>
                  </Fila>
                ))}
              </tbody>
            </SeccionTabla>

            <SeccionTabla titulo="Por sede">
              <TablaEncabezado>
                <Th>Sede</Th>
                <Th>Qué es</Th>
                <Th className="text-right">Personas</Th>
                <Th className="text-right">Costo real</Th>
                <Th className="text-right">Salió del banco</Th>
                <Th className="text-right">Por persona</Th>
                <Th className="text-right">Por hora</Th>
              </TablaEncabezado>
              <tbody>
                {data.por_sede.map((s) => (
                  <Fila key={s.sede}>
                    <td className="px-4 py-2">{s.nombre}</td>
                    <td className="px-4 py-2 text-taupe">{ETIQUETA_TIPO[s.tipo] ?? s.tipo}</td>
                    <td className={NUM}>{s.personas}</td>
                    <td className={`${NUM} font-medium`}>{formatSoles(s.costo)}</td>
                    <td className={NUM}>{s.salio_del_banco === undefined ? "—" : formatSoles(s.salio_del_banco)}</td>
                    <td className={NUM}>{s.costo_por_persona === null ? "—" : formatSoles(s.costo_por_persona)}</td>
                    <td className={NUM}>{s.costo_por_hora === null ? "—" : formatSoles(s.costo_por_hora)}</td>
                  </Fila>
                ))}
              </tbody>
            </SeccionTabla>

            <p className="-mt-4 mb-6 max-w-3xl text-xs text-taupe">
              Compara por <strong className="font-medium">persona</strong> y por{" "}
              <strong className="font-medium">hora</strong>, no por el total: una sede con nueve personas
              siempre va a costar más que una con cuatro, y eso no dice nada. El desglose completo (lo que se
              transfirió y las provisiones por separado) está en el CSV.
            </p>

            <SeccionTabla titulo="Por área">
              <TablaEncabezado>
                <Th>Área</Th>
                <Th className="text-right">Personas</Th>
                <Th className="text-right">Se transfirió</Th>
                <Th className="text-right">Provisiones</Th>
                <Th className="text-right">Costo real</Th>
                <Th className="text-right">Salió del banco</Th>
              </TablaEncabezado>
              <tbody>
                {data.por_area.map((a) => (
                  <Fila key={a.area ?? "sin-area"}>
                    <td className="px-4 py-2">
                      {a.nombre}
                      {a.operativa && (
                        <Insignia atenuada punto={false} className="ml-2">operativa</Insignia>
                      )}
                    </td>
                    <td className={NUM}>{a.personas}</td>
                    <td className={NUM}>{formatSoles(a.neto)}</td>
                    <td className={NUM}>{formatSoles(a.provisiones)}</td>
                    <td className={`${NUM} font-medium`}>{formatSoles(a.costo)}</td>
                    <td className={NUM}>{a.salio_del_banco === undefined ? "—" : formatSoles(a.salio_del_banco)}</td>
                  </Fila>
                ))}
              </tbody>
            </SeccionTabla>

            <SeccionTabla titulo="Por persona">
              <TablaEncabezado>
                <Th>Nombre</Th>
                <Th>Sede</Th>
                <Th className="text-right">Periodos</Th>
                <Th className="text-right">Horas</Th>
                <Th className="text-right">Se transfirió</Th>
                <Th className="text-right">Provisiones</Th>
                <Th className="text-right">Costo real</Th>
                <Th className="text-right">Salió del banco</Th>
              </TablaEncabezado>
              <tbody>
                {data.por_persona.map((p) => (
                  <Fila key={p.persona_id}>
                    <td className="px-4 py-2">{p.nombre}</td>
                    <td className="px-4 py-2 text-taupe">{nombreDeSede.get(p.sede) ?? p.sede}</td>
                    <td className={NUM}>{p.periodos}</td>
                    <td className={NUM}>{p.horas.toLocaleString("es-PE", { maximumFractionDigits: 1 })}</td>
                    <td className={NUM}>{formatSoles(p.neto)}</td>
                    <td className={NUM}>{formatSoles(p.provisiones)}</td>
                    <td className={`${NUM} font-medium`}>{formatSoles(p.costo)}</td>
                    <td className={NUM}>{p.salio_del_banco === undefined ? "—" : formatSoles(p.salio_del_banco)}</td>
                  </Fila>
                ))}
              </tbody>
            </SeccionTabla>
          </>
        )}

        {data && data.por_periodo.length === 0 && anios.length > 0 && !cargando && (
          <div className="max-w-3xl rounded-control bg-sand/40 px-4 py-3 text-sm text-taupe">
            En {anio} no hay ningún periodo marcado como pagado.
          </div>
        )}
      </main>
    </div>
  );
}

// No se llama "Tabla" para no chocar con el primitivo compartido
// (@/components/ui/tabla): esto solo le agrega el título de sección, y por
// dentro usa ese mismo <Tabla> — así el envoltorio de esta pantalla queda con
// la misma superficie elevada (bg-papel, rounded-superficie) que el resto del
// panel, en vez del bg-crema aislado que tenía antes.
function SeccionTabla({ titulo, children }: { titulo: string; children: React.ReactNode }) {
  return (
    <section className="mb-6">
      <h2 className="mb-2 font-serif text-lg">{titulo}</h2>
      <Tabla className="max-w-5xl">{children}</Tabla>
    </section>
  );
}

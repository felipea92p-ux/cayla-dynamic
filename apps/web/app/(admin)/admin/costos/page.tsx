"use client";

// ============================================================================
// Costos — lo que cuesta el equipo
// ----------------------------------------------------------------------------
// Lee SOLO la foto de los pagos congelados (migraciones 0096 y 0097). Un
// periodo que todavía no se marcó como pagado no aparece aquí, y eso es a
// propósito: su número aún se mueve, y un costo que se mueve no es un costo.
// La proyección del periodo en curso vive donde siempre, en Planilla.
//
// Dos cifras distintas, y la pantalla no las mezcla nunca:
//   · «Se transfirió» — lo que recibió la gente.
//   · «Costo real»    — eso más las provisiones (gratificación, CTS y
//                       vacaciones que se devengan aunque se paguen después).
// Mirar solo la primera subestima el costo del equipo en torno a un 16,7 %.
// ============================================================================

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { AdminNav } from "../nav";
import { useRolActual } from "@/lib/admin/use-rol";
import { formatSoles } from "@/lib/rangos";
import { descargarCsv, generarCsv } from "@/lib/admin/csv";

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
}
interface PorGrupo {
  nombre: string;
  personas: number;
  neto: number;
  provisiones: number;
  costo: number;
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

const NUM = "px-3 py-2 text-right tabular-nums";
const TH = "px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-taupe";
const THN = "px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-taupe";

export default function CostosPage() {
  const router = useRouter();
  const rol = useRolActual();
  const puedeVer = rol === "admin" || rol === "lider_do";
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
  useEffect(() => {
    if (!puedeVer) return;
    let vivo = true;
    void supabase.rpc("fn_periodos").then(({ data, error }) => {
      if (!vivo || error || !data) return;
      const lista = data as unknown as Array<{ fecha_fin: string; estado: string }>;
      const ys = Array.from(
        new Set(lista.filter((p) => p.estado === "pagado").map((p) => Number(p.fecha_fin.slice(0, 4)))),
      ).sort((a, b) => b - a);
      setAnios(ys);
      setAnio((prev) => prev ?? ys[0] ?? null);
    });
    return () => { vivo = false; };
  }, [supabase, puedeVer]);

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

  useEffect(() => { void cargar(); }, [cargar]);

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
    }));
    const csv = generarCsv(filas, [
      "nombre", "sede", "tipo_de_sede", "area", "periodos_pagados", "horas",
      "se_transfirio", "provisiones", "costo_real",
    ]);
    descargarCsv(`costos-${anio}.csv`, csv);
  }

  if (rol === null) {
    return (
      <div className="flex min-h-screen flex-col">
        <AdminNav />
        <main className="flex-1 p-6">
          {rolDemorado ? (
            <p className="max-w-md rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
              No se pudo identificar tu usuario — cierra sesión y vuelve a entrar.
            </p>
          ) : (
            <div className="flex flex-col items-center gap-4 py-20 text-taupe"><span className="colibri aletea w-12 text-rojo/70" aria-hidden /><span className="text-sm">Cargando…</span></div>
          )}
        </main>
      </div>
    );
  }
  if (!puedeVer) {
    return (
      <div className="flex min-h-screen flex-col">
        <AdminNav />
        <main className="flex-1 p-6">
          <p className="max-w-md rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
            Solo administradores y líderes pueden ver los costos de planilla.
          </p>
        </main>
      </div>
    );
  }

  const t = data?.totales;

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
          <h1 className="font-serif text-2xl">Costos del equipo</h1>
          <div className="flex items-center gap-3">
            <label className="flex items-center gap-2 text-sm">
              Año
              <select
                value={anio ?? ""}
                onChange={(e) => setAnio(Number(e.target.value))}
                disabled={anios.length === 0}
                className="rounded-lg border bg-crema px-3 py-1.5"
              >
                {anios.map((y) => (<option key={y} value={y}>{y}</option>))}
              </select>
            </label>
            <button
              onClick={descargarCsvCostos}
              disabled={!data || data.por_persona.length === 0}
              className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50"
            >
              Descargar CSV
            </button>
          </div>
        </div>

        <p className="mb-4 max-w-3xl text-xs text-taupe">
          Solo aparecen los periodos ya <strong className="font-medium">marcados como pagados</strong>: su
          desglose quedó congelado y ya no cambia. Lo que todavía está abierto se ve en Planilla, y es una
          proyección, no un costo. Los periodos de CAYLA no son meses calendario, así que cada fila es{" "}
          <strong className="font-medium">un periodo</strong>, no un mes.
        </p>

        {error && (
          <div className="mb-4 max-w-3xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
            No se pudieron cargar los costos: {error}{" "}
            <button onClick={() => void cargar()} className="font-medium underline">Reintentar</button>
          </div>
        )}

        {cargando && !data && (
          <div className="flex flex-col items-center gap-4 py-20 text-taupe"><span className="colibri aletea w-12 text-rojo/70" aria-hidden /><span className="text-sm">Cargando…</span></div>
        )}

        {anios.length === 0 && !cargando && !error && (
          <div className="max-w-3xl rounded-lg bg-sand/40 px-4 py-3 text-sm text-taupe">
            Todavía no hay ningún periodo marcado como pagado, así que no hay costos que sumar. En cuanto
            cierres el primero, aparecerá aquí.
          </div>
        )}

        {data && data.periodos_retroactivos > 0 && (
          <div className="mb-4 max-w-3xl rounded-lg bg-ambar/15 px-4 py-3 text-sm text-ambar">
            {data.periodos_retroactivos === 1
              ? "Un periodo de este año tiene el desglose reconstruido"
              : `${data.periodos_retroactivos} periodos de este año tienen el desglose reconstruido`}{" "}
            en vez de congelado el día del pago: son anteriores a que el sistema guardara la foto. Su cifra
            es la de hoy, no necesariamente la que se transfirió. Los periodos que cierres de ahora en
            adelante quedan congelados en el momento exacto del pago.
          </div>
        )}

        {t && (
          <div className="mb-6 grid max-w-4xl grid-cols-2 gap-3 sm:grid-cols-4">
            <div className="rounded-lg bg-tinta px-4 py-3 text-crema">
              <div className="text-xs opacity-70">Costo real del año</div>
              <div className="text-xl font-medium tabular-nums">{formatSoles(t.costo)}</div>
            </div>
            <div className="rounded-lg bg-sand/40 px-4 py-3">
              <div className="text-xs text-taupe">Se transfirió</div>
              <div className="text-xl font-medium tabular-nums">{formatSoles(t.neto)}</div>
            </div>
            <div className="rounded-lg bg-sand/40 px-4 py-3">
              <div className="text-xs text-taupe">Provisiones devengadas</div>
              <div className="text-xl font-medium tabular-nums">{formatSoles(t.provisiones)}</div>
            </div>
            <div className="rounded-lg bg-sand/40 px-4 py-3">
              <div className="text-xs text-taupe">Periodos cerrados</div>
              <div className="text-xl font-medium tabular-nums">{t.periodos}</div>
              <div className="text-xs text-taupe">{t.personas} personas</div>
            </div>
          </div>
        )}

        {data && data.por_periodo.length > 0 && (
          <>
            <Tabla titulo="Por periodo">
              <thead>
                <tr className="border-b">
                  <th className={TH}>Periodo</th>
                  <th className={TH}>Cerró en</th>
                  <th className={THN}>Personas</th>
                  <th className={THN}>Se transfirió</th>
                  <th className={THN}>Provisiones</th>
                  <th className={THN}>Costo real</th>
                </tr>
              </thead>
              <tbody>
                {data.por_periodo.map((p) => (
                  <tr key={p.periodo_id} className="border-b last:border-0">
                    <td className="px-3 py-2">
                      {fechaCorta(p.fecha_ini)} → {fechaCorta(p.fecha_fin)}
                      {p.reconstruida && (
                        <span className="ml-2 rounded bg-ambar/20 px-1.5 py-0.5 text-xs text-ambar">
                          reconstruido
                        </span>
                      )}
                      {p.version > 1 && (
                        <span className="ml-2 rounded bg-sand/60 px-1.5 py-0.5 text-xs text-taupe">
                          repagado ({p.version}.ª copia)
                        </span>
                      )}
                    </td>
                    <td className="px-3 py-2 capitalize">{MESES[p.mes - 1]}</td>
                    <td className={NUM}>{p.personas}</td>
                    <td className={NUM}>{formatSoles(p.neto)}</td>
                    <td className={NUM}>{formatSoles(p.provisiones)}</td>
                    <td className={`${NUM} font-medium`}>{formatSoles(p.costo)}</td>
                  </tr>
                ))}
              </tbody>
            </Tabla>

            <Tabla titulo="Operar tiendas · producir · administrar">
              <thead>
                <tr className="border-b">
                  <th className={TH}>Qué es</th>
                  <th className={THN}>Sedes</th>
                  <th className={THN}>Personas</th>
                  <th className={THN}>Costo real</th>
                  <th className={THN}>Por persona</th>
                  <th className={THN}>Por hora</th>
                </tr>
              </thead>
              <tbody>
                {data.por_tipo.map((t) => (
                  <tr key={t.tipo} className="border-b last:border-0">
                    <td className="px-3 py-2">{ETIQUETA_TIPO[t.tipo] ?? t.tipo}</td>
                    <td className={NUM}>{t.sedes}</td>
                    <td className={NUM}>{t.personas}</td>
                    <td className={`${NUM} font-medium`}>{formatSoles(t.costo)}</td>
                    <td className={NUM}>{t.costo_por_persona === null ? "—" : formatSoles(t.costo_por_persona)}</td>
                    <td className={NUM}>{t.costo_por_hora === null ? "—" : formatSoles(t.costo_por_hora)}</td>
                  </tr>
                ))}
              </tbody>
            </Tabla>

            <Tabla titulo="Por sede">
              <thead>
                <tr className="border-b">
                  <th className={TH}>Sede</th>
                  <th className={TH}>Qué es</th>
                  <th className={THN}>Personas</th>
                  <th className={THN}>Costo real</th>
                  <th className={THN}>Por persona</th>
                  <th className={THN}>Por hora</th>
                </tr>
              </thead>
              <tbody>
                {data.por_sede.map((s) => (
                  <tr key={s.sede} className="border-b last:border-0">
                    <td className="px-3 py-2">{s.nombre}</td>
                    <td className="px-3 py-2 text-taupe">{ETIQUETA_TIPO[s.tipo] ?? s.tipo}</td>
                    <td className={NUM}>{s.personas}</td>
                    <td className={`${NUM} font-medium`}>{formatSoles(s.costo)}</td>
                    <td className={NUM}>{s.costo_por_persona === null ? "—" : formatSoles(s.costo_por_persona)}</td>
                    <td className={NUM}>{s.costo_por_hora === null ? "—" : formatSoles(s.costo_por_hora)}</td>
                  </tr>
                ))}
              </tbody>
            </Tabla>

            <p className="-mt-4 mb-6 max-w-3xl text-xs text-taupe">
              Compara por <strong className="font-medium">persona</strong> y por{" "}
              <strong className="font-medium">hora</strong>, no por el total: una sede con nueve personas
              siempre va a costar más que una con cuatro, y eso no dice nada. El desglose completo (lo que se
              transfirió y las provisiones por separado) está en el CSV.
            </p>

            <Tabla titulo="Por área">
              <thead>
                <tr className="border-b">
                  <th className={TH}>Área</th>
                  <th className={THN}>Personas</th>
                  <th className={THN}>Se transfirió</th>
                  <th className={THN}>Provisiones</th>
                  <th className={THN}>Costo real</th>
                </tr>
              </thead>
              <tbody>
                {data.por_area.map((a) => (
                  <tr key={a.area ?? "sin-area"} className="border-b last:border-0">
                    <td className="px-3 py-2">
                      {a.nombre}
                      {a.operativa && (
                        <span className="ml-2 rounded bg-sand/60 px-1.5 py-0.5 text-xs text-taupe">
                          operativa
                        </span>
                      )}
                    </td>
                    <td className={NUM}>{a.personas}</td>
                    <td className={NUM}>{formatSoles(a.neto)}</td>
                    <td className={NUM}>{formatSoles(a.provisiones)}</td>
                    <td className={`${NUM} font-medium`}>{formatSoles(a.costo)}</td>
                  </tr>
                ))}
              </tbody>
            </Tabla>

            <Tabla titulo="Por persona">
              <thead>
                <tr className="border-b">
                  <th className={TH}>Nombre</th>
                  <th className={TH}>Sede</th>
                  <th className={THN}>Periodos</th>
                  <th className={THN}>Horas</th>
                  <th className={THN}>Se transfirió</th>
                  <th className={THN}>Provisiones</th>
                  <th className={THN}>Costo real</th>
                </tr>
              </thead>
              <tbody>
                {data.por_persona.map((p) => (
                  <tr key={p.persona_id} className="border-b last:border-0">
                    <td className="px-3 py-2">{p.nombre}</td>
                    <td className="px-3 py-2 text-taupe">{nombreDeSede.get(p.sede) ?? p.sede}</td>
                    <td className={NUM}>{p.periodos}</td>
                    <td className={NUM}>{p.horas.toLocaleString("es-PE", { maximumFractionDigits: 1 })}</td>
                    <td className={NUM}>{formatSoles(p.neto)}</td>
                    <td className={NUM}>{formatSoles(p.provisiones)}</td>
                    <td className={`${NUM} font-medium`}>{formatSoles(p.costo)}</td>
                  </tr>
                ))}
              </tbody>
            </Tabla>
          </>
        )}

        {data && data.por_periodo.length === 0 && anios.length > 0 && !cargando && (
          <div className="max-w-3xl rounded-lg bg-sand/40 px-4 py-3 text-sm text-taupe">
            En {anio} no hay ningún periodo marcado como pagado.
          </div>
        )}
      </main>
    </div>
  );
}

function Tabla({ titulo, children }: { titulo: string; children: React.ReactNode }) {
  return (
    <section className="mb-6">
      <h2 className="mb-2 font-serif text-lg">{titulo}</h2>
      <div className="max-w-5xl overflow-x-auto rounded-lg border bg-crema">
        <table className="w-full text-sm">{children}</table>
      </div>
    </section>
  );
}

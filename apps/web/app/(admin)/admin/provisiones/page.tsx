"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { AdminNav } from "../nav";
import { Cargando } from "@/components/cargando";
import { useRolActual } from "@/lib/admin/use-rol";
import { formatSoles } from "@/lib/rangos";
import { descargarCsv, generarCsv } from "@/lib/admin/csv";
import { puedeVerPlanilla } from "@cayla-dynamic/shared";

// ── Fechas (por string: NUNCA new Date(), para no correr un día por zona) ────
// "2027-03-12" → "12/03/2027"
function fechaLarga(iso: string | null | undefined): string {
  if (!iso) return "—";
  const [y, m, d] = iso.split("-");
  if (!y || !m || !d) return iso;
  return `${d}/${m}/${y}`;
}
// "2026-07-15" → "15/07"
function fechaDiaMes(iso: string | null | undefined): string {
  if (!iso) return "—";
  const [, m, d] = iso.split("-");
  if (!m || !d) return iso;
  return `${d}/${m}`;
}
// 2.5 → "2.5 días"
function fmtDias(n: number): string {
  return `${(n ?? 0).toLocaleString("es-PE", { minimumFractionDigits: 1, maximumFractionDigits: 1 })} días`;
}

/**
 * Una ventana ya desembolsada se muestra como «pagado el 15/07», no como S/ 0.00.
 *
 * POR QUÉ NO UN CERO. Hasta la 0123 esta pantalla mostraba la gratificación de
 * enero–junio acumulando en agosto, cuando ya se había pagado el 15 de julio: la
 * misma plata contada dos veces. La 0123 la manda en cero para que deje de
 * inflar el total, pero un cero solo se lee como «a esta persona no le tocaba
 * nada», que es una mentira distinta. Por eso viaja también el monto real.
 *
 * `pagada` es opcional a propósito: sin la 0123 aplicada llega `undefined`, la
 * función cae al monto de siempre y la pantalla se ve exactamente como antes.
 *
 * Y SI QUEDA SALDO, EL SALDO MANDA. Desde la 0158 «pagada» dejó de significar
 * «liquidada del todo»: un depósito directo PARCIAL de CTS la marca pagada y aun
 * así deja un pendiente, que es el número que entra al total. Mostrando solo lo
 * pagado, la fila no cuadraba a la vista —se leía «pagado S/94.17» junto a un
 * total que contaba otros S/146.77 que no aparecían por ningún lado—. La
 * gratificación sigue siendo todo-o-nada, así que ahí el pendiente es 0 y la
 * celda se ve igual que siempre.
 */
function celdaVentana(
  monto: number,
  pagada: boolean | undefined,
  montoPagado: number | null | undefined,
  fechaPago: string,
) {
  if (!pagada) return <>{formatSoles(monto)}</>;
  return (
    <span className={monto === 0 ? "text-taupe" : undefined}>
      {monto !== 0 && <span className="block">{formatSoles(monto)}</span>}
      <span className={monto !== 0 ? "block text-xs text-taupe" : undefined}>
        pagado {fechaDiaMes(fechaPago)}
        {typeof montoPagado === "number" && ` · ${formatSoles(montoPagado)}`}
      </span>
    </span>
  );
}
// "2026-07-15" → "Julio" (mes de pago, capitalizado; por string, sin new Date())
const MESES = [
  "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
  "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre",
];
function mesDePago(iso: string | null | undefined): string {
  if (!iso) return "—";
  const m = Number(iso.split("-")[1]);
  return MESES[m - 1] ?? "—";
}
// El payload trae el tipo sin tilde ('Gratificacion'); lo mostramos en español de la casa.
function tipoLabel(t: string | null | undefined): string {
  if (t === "Gratificacion") return "Gratificación";
  return t ?? "—";
}

// ── Tipos (forma del jsonb de fn_provisiones v2 — vista anual) ────────────────
type ProximoRef = "grati_s1" | "grati_s2" | "cts_may" | "cts_nov";

interface ProvPersona {
  persona_id: string;
  nombre: string;
  sede: string;
  fecha_ingreso: string;
  grati_s1: number;
  grati_s2: number;
  grati_total: number;
  // ⇩ 0134 ⇩ La bonificación extraordinaria de la Ley 30334: el 9% que, en vez
  // de ir a EsSalud, se le paga a la persona junto con la gratificación. Sale
  // del mismo número que la grati y se apaga con la misma bandera.
  //
  // Viaja desde la 0134 y la pantalla la ignoró hasta el 2026-08-19: el «Gran
  // total» se sumaba acá sin ella y la reserva salía corta. Ahora tiene columna
  // propia, para que el total que muestra `gran_total` cuadre con lo que se ve.
  be_total: number;
  tasa_be: number;
  cts_may: number;
  cts_nov: number;
  cts_total: number;
  // ⇩ 0123 ⇩ Una ventana ya desembolsada llega en 0 —para que no infle el
  // total— y su monto real viaja aparte, para poder decir «pagado» en vez de
  // mostrar un cero que se lee como «no le tocaba nada».
  // Opcionales a propósito: si la 0123 aún no está pegada, llegan `undefined`
  // y la pantalla se comporta exactamente como antes.
  grati_s1_pagada?: boolean;
  grati_s2_pagada?: boolean;
  cts_may_pagada?: boolean;
  cts_nov_pagada?: boolean;
  grati_s1_monto_pagado?: number | null;
  grati_s2_monto_pagado?: number | null;
  cts_may_monto_pagado?: number | null;
  cts_nov_monto_pagado?: number | null;
  vac: number;
  // ⇩ 0273 ⇩ Las vacaciones son la quinta ventana del libro de desembolsos y
  // eran la única que nunca se descontaba. Opcionales por la misma razón que
  // las de arriba: sin la 0273 pegada llegan `undefined` y la celda se ve igual
  // que siempre.
  vac_pagada?: boolean;
  vac_monto_pagado?: number | null;
  vac_dias: number;
  proximo_aniversario: string;
  gran_total: number;
}
interface ProvData {
  as_of: string;
  factores: { gratificacion: number; cts: number; vacaciones: number };
  proximo: { fecha: string | null; tipo: string | null; ref: ProximoRef | null };
  grati_s1_pago: string;
  grati_s2_pago: string;
  cts_may_pago: string;
  cts_nov_pago: string;
  grati_s1_periodo: string;
  grati_s2_periodo: string;
  cts_may_periodo: string;
  cts_nov_periodo: string;
  personas: ProvPersona[];
}

const COLS = 14; // 2 + 3 grati + bonif + 3 cts + 3 vac + gran total + próximo pago

export default function ProvisionesPage() {
  const router = useRouter();
  const rol = useRolActual();
  const puedeVer = puedeVerPlanilla(rol);
  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  const [data, setData] = useState<ProvData | null>(null);
  const [cargando, setCargando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sedeFiltro, setSedeFiltro] = useState("todas");

  // Si el rol no llega en ~6 s, avisar en vez de un "Cargando…" eterno
  const [rolDemorado, setRolDemorado] = useState(false);
  useEffect(() => {
    if (rol !== null) {
      setRolDemorado(false);
      return;
    }
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
    setCargando(true);
    setError(null);
    const { data, error } = await supabase.rpc("fn_provisiones"); // sin args = a hoy
    setCargando(false);
    if (error) {
      setError(error.message);
      return;
    }
    setData(data as unknown as ProvData);
  }, [supabase, puedeVer]);

  useEffect(() => {
    void cargar();
  }, [cargar]);

  // ── Derivados (siempre desde data, para lint limpio como en planilla) ──────
  const sedes = useMemo(
    () => Array.from(new Set((data?.personas ?? []).map((p) => p.sede))).sort(),
    [data],
  );
  const visibles = useMemo(
    () => (data?.personas ?? []).filter((p) => sedeFiltro === "todas" || p.sede === sedeFiltro),
    [data, sedeFiltro],
  );
  // El pie suma lo que manda la base, campo por campo — incluido `gran_total`.
  //
  // POR QUÉ NO SE RECALCULA ACÁ. Hasta hoy el «Gran total» de la fila y el del
  // pie se armaban como `grati_total + cts_total + vac`, y esa suma OMITE la
  // bonificación extraordinaria de la Ley 30334 (`be_total`, ~9% de la
  // gratificación) que `fn_provisiones` sí incluye en su `gran_total`. La
  // reserva salía corta en esa cifra, y el CSV que va al contador también.
  // Medido el 2026-08-19 con una persona de S/1.500: la pantalla decía
  // S/2.010,12 y la base S/2.095,77 — los S/85,65 que faltaban eran la bonif.
  //
  // La regla que queda: un total que la base ya calcula NO se vuelve a calcular
  // acá. Si hace falta que cuadre a la vista, se agrega la columna que falta
  // —que es lo que se hizo con «Bonif. extr.»— no se cambia el total.
  const totales = useMemo(
    () =>
      visibles.reduce(
        (acc, p) => ({
          grati_s1: acc.grati_s1 + p.grati_s1,
          grati_s2: acc.grati_s2 + p.grati_s2,
          grati_total: acc.grati_total + p.grati_total,
          be_total: acc.be_total + p.be_total,
          cts_may: acc.cts_may + p.cts_may,
          cts_nov: acc.cts_nov + p.cts_nov,
          cts_total: acc.cts_total + p.cts_total,
          vac: acc.vac + p.vac,
          gran_total: acc.gran_total + p.gran_total,
        }),
        {
          grati_s1: 0, grati_s2: 0, grati_total: 0, be_total: 0,
          cts_may: 0, cts_nov: 0, cts_total: 0,
          vac: 0, gran_total: 0,
        },
      ),
    [visibles],
  );

  // Monto del próximo pago de una persona = la fila cuya clave es data.proximo.ref
  const proximoRef = data?.proximo?.ref ?? null;
  function montoProximo(p: ProvPersona): number | null {
    if (!proximoRef) return null;
    return p[proximoRef];
  }

  // ── CSV (todas las columnas; respeta el filtro de sede) ────────────────────
  function descargarCsvProvisiones() {
    if (!data) return;
    const filas = visibles.map((p) => ({
      nombre: p.nombre,
      sede: p.sede,
      fecha_ingreso: p.fecha_ingreso,
      grati_julio_ene_jun: p.grati_s1,
      grati_diciembre_jul_dic: p.grati_s2,
      grati_total: p.grati_total,
      bonificacion_extraordinaria: p.be_total,
      cts_mayo_nov_abr: p.cts_may,
      cts_noviembre_may_oct: p.cts_nov,
      cts_total: p.cts_total,
      vacaciones: p.vac,
      vacaciones_dias: p.vac_dias,
      proximo_aniversario: p.proximo_aniversario,
      gran_total: p.gran_total,
      proximo_pago_monto: montoProximo(p) ?? "",
      proximo_pago_fecha: data.proximo?.fecha ?? "",
    }));
    const csv = generarCsv(filas, [
      "nombre",
      "sede",
      "fecha_ingreso",
      "grati_julio_ene_jun",
      "grati_diciembre_jul_dic",
      "grati_total",
      "bonificacion_extraordinaria",
      "cts_mayo_nov_abr",
      "cts_noviembre_may_oct",
      "cts_total",
      "vacaciones",
      "vacaciones_dias",
      "proximo_aniversario",
      "gran_total",
      "proximo_pago_monto",
      "proximo_pago_fecha",
    ]);
    descargarCsv(`provisiones-${data.as_of}.csv`, csv);
  }

  // ── Gating ──────────────────────────────────────────────────────────────────
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
            <Cargando />
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
            Solo administradores y líderes pueden ver las provisiones.
          </p>
        </main>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        {/* Cabecera */}
        <h1 className="mb-3 font-serif text-2xl">
          {data ? `Provisiones al ${fechaLarga(data.as_of)}` : "Provisiones"}
        </h1>

        {/* Banda destacada: próximo desembolso */}
        {data &&
          (data.proximo?.fecha && data.proximo?.tipo ? (
            <div className="mb-3 max-w-3xl rounded-lg bg-ambar/15 px-4 py-3 text-sm font-medium text-ambar">
              Próximo desembolso: {tipoLabel(data.proximo.tipo)} el {fechaLarga(data.proximo.fecha)}
            </div>
          ) : (
            <div className="mb-3 max-w-3xl rounded-lg bg-sand/40 px-4 py-3 text-sm text-taupe">
              No quedan desembolsos programados en lo que resta del año.
            </div>
          ))}

        {data && (
          <p className="mb-4 max-w-3xl text-xs text-taupe">
            Régimen MYPE pequeña empresa · la CTS se{" "}
            <strong className="font-medium">deposita en la cuenta de banco</strong> del trabajador (no
            en efectivo) · cifras referenciales (el contador cierra los montos).
          </p>
        )}

        {/* Error de carga */}
        {error && (
          <div className="mb-4 max-w-3xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
            No se pudieron cargar las provisiones: {error}{" "}
            <button onClick={() => void cargar()} className="font-medium underline">
              Reintentar
            </button>
          </div>
        )}

        {/* Cargando inicial */}
        {cargando && !data && <Cargando />}

        {data && (
          <>
            {/* Filtro de sede + CSV */}
            <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
              <label className="flex items-center gap-2 text-sm">
                Sede
                <select
                  value={sedeFiltro}
                  onChange={(e) => setSedeFiltro(e.target.value)}
                  className="rounded-lg border bg-crema px-3 py-1.5"
                >
                  <option value="todas">Todas</option>
                  {sedes.map((s) => (
                    <option key={s} value={s}>
                      {s}
                    </option>
                  ))}
                </select>
              </label>
              <button
                onClick={descargarCsvProvisiones}
                disabled={cargando || error !== null || visibles.length === 0}
                className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50"
              >
                Descargar CSV
              </button>
            </div>

            {/* Tabla anual */}
            <div className="overflow-x-auto rounded-2xl border border-sand bg-papel">
              <table className="w-full text-sm">
                <thead className="bg-sand/70 text-left text-taupe">
                  {/* Encabezados de grupo (fechas de pago del payload) */}
                  <tr>
                    <th className="px-4 py-2" colSpan={2} />
                    <th className="border-l px-4 py-2 text-center font-normal" colSpan={3}>
                      Gratificación · paga {fechaDiaMes(data.grati_s1_pago)} y{" "}
                      {fechaDiaMes(data.grati_s2_pago)}
                    </th>
                    <th className="border-l px-4 py-2 text-center font-normal">
                      Bonif. extr.
                    </th>
                    <th className="border-l px-4 py-2 text-center font-normal" colSpan={3}>
                      CTS · deposita {fechaDiaMes(data.cts_may_pago)} y {fechaDiaMes(data.cts_nov_pago)}
                    </th>
                    <th className="border-l px-4 py-2 text-center font-normal" colSpan={3}>
                      Vacaciones · aniversario
                    </th>
                    <th className="border-l px-4 py-2 text-center font-normal">Gran total</th>
                    <th className="border-l px-4 py-2 text-center font-normal">Próximo pago</th>
                  </tr>
                  {/* Sub-encabezados */}
                  <tr className="border-t">
                    <th className="px-4 py-2 font-normal">Nombre</th>
                    <th className="px-4 py-2 font-normal">Sede</th>
                    <th className="border-l px-4 py-2 text-right font-normal">
                      {mesDePago(data.grati_s1_pago)}{" "}
                      <span className="text-taupe">({data.grati_s1_periodo})</span>
                    </th>
                    <th className="px-4 py-2 text-right font-normal">
                      {mesDePago(data.grati_s2_pago)}{" "}
                      <span className="text-taupe">({data.grati_s2_periodo})</span>
                    </th>
                    <th className="px-4 py-2 text-right font-normal">Total</th>
                    <th className="border-l px-4 py-2 text-right font-normal">
                      Ley 30334{" "}
                      <span className="text-taupe">
                        ({(data.personas[0]?.tasa_be ?? 0.09) * 100}%)
                      </span>
                    </th>
                    <th className="border-l px-4 py-2 text-right font-normal">
                      {mesDePago(data.cts_may_pago)}{" "}
                      <span className="text-taupe">({data.cts_may_periodo})</span>
                    </th>
                    <th className="px-4 py-2 text-right font-normal">
                      {mesDePago(data.cts_nov_pago)}{" "}
                      <span className="text-taupe">({data.cts_nov_periodo})</span>
                    </th>
                    <th className="px-4 py-2 text-right font-normal">Total</th>
                    <th className="border-l px-4 py-2 text-right font-normal">Monto</th>
                    <th className="px-4 py-2 text-right font-normal">Días</th>
                    <th className="px-4 py-2 font-normal">Aniversario</th>
                    <th className="border-l px-4 py-2 text-right font-normal">Gran total</th>
                    <th className="border-l px-4 py-2 text-right font-normal">Próximo pago</th>
                  </tr>
                </thead>
                <tbody>
                  {visibles.length === 0 && (
                    <tr>
                      <td colSpan={COLS} className="px-4 py-6 text-center text-taupe">
                        No hay personas activas para mostrar.
                      </td>
                    </tr>
                  )}
                  {visibles.map((p) => {
                    const mp = montoProximo(p);
                    return (
                      <tr key={p.persona_id} className="border-t">
                        <td className="px-4 py-2">{p.nombre}</td>
                        <td className="px-4 py-2">{p.sede}</td>
                        {/* Gratificación */}
                        <td className="border-l px-4 py-2 text-right">
                          {celdaVentana(p.grati_s1, p.grati_s1_pagada, p.grati_s1_monto_pagado, data.grati_s1_pago)}
                        </td>
                        <td className="px-4 py-2 text-right">
                          {celdaVentana(p.grati_s2, p.grati_s2_pagada, p.grati_s2_monto_pagado, data.grati_s2_pago)}
                        </td>
                        <td className="px-4 py-2 text-right font-bold">{formatSoles(p.grati_total)}</td>
                        {/* Bonificación extraordinaria (Ley 30334) — sale de la grati */}
                        <td className="border-l px-4 py-2 text-right">{formatSoles(p.be_total)}</td>
                        {/* CTS */}
                        <td className="border-l px-4 py-2 text-right">
                          {celdaVentana(p.cts_may, p.cts_may_pagada, p.cts_may_monto_pagado, data.cts_may_pago)}
                        </td>
                        <td className="px-4 py-2 text-right">
                          {celdaVentana(p.cts_nov, p.cts_nov_pagada, p.cts_nov_monto_pagado, data.cts_nov_pago)}
                        </td>
                        <td className="px-4 py-2 text-right font-bold">{formatSoles(p.cts_total)}</td>
                        {/* Vacaciones — desde la 0273 también pueden estar pagadas
                            por fuera de planilla, así que se dice igual que en las
                            otras ventanas: el saldo arriba y lo pagado debajo. */}
                        <td className="border-l px-4 py-2 text-right">
                          {formatSoles(p.vac)}
                          {p.vac_pagada && typeof p.vac_monto_pagado === "number" && (
                            <span className="block text-xs text-taupe">
                              pagado · {formatSoles(p.vac_monto_pagado)}
                            </span>
                          )}
                        </td>
                        <td className="whitespace-nowrap px-4 py-2 text-right text-xs text-taupe">
                          {fmtDias(p.vac_dias)}
                        </td>
                        <td className="whitespace-nowrap px-4 py-2 text-xs text-taupe">
                          aniversario {fechaLarga(p.proximo_aniversario)}
                        </td>
                        {/* Gran total — el que calcula fn_provisiones, no una suma de acá.
                            Ver el comentario de `totales`: sumarlo en el cliente omitía la
                            bonificación extraordinaria y dejaba la reserva corta. */}
                        <td className="border-l bg-ambar/10 px-4 py-2 text-right font-bold">
                          {formatSoles(p.gran_total)}
                        </td>
                        {/* Próximo pago */}
                        <td className="whitespace-nowrap border-l px-4 py-2 text-right">
                          {mp !== null ? (
                            <>
                              {formatSoles(mp)}
                              <span className="block text-xs text-taupe">
                                {fechaDiaMes(data.proximo.fecha)}
                              </span>
                            </>
                          ) : (
                            <span className="text-taupe/50">—</span>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
                {visibles.length > 0 && (
                  <tfoot>
                    <tr className="border-t bg-sand/50">
                      <td className="px-4 py-2 font-medium" colSpan={2}>
                        Total ({visibles.length} {visibles.length === 1 ? "persona" : "personas"}
                        {sedeFiltro !== "todas" ? ` — ${sedeFiltro}` : ""})
                      </td>
                      <td className="border-l px-4 py-2 text-right font-medium">
                        {formatSoles(totales.grati_s1)}
                      </td>
                      <td className="px-4 py-2 text-right font-medium">{formatSoles(totales.grati_s2)}</td>
                      <td className="px-4 py-2 text-right font-bold">{formatSoles(totales.grati_total)}</td>
                      <td className="border-l px-4 py-2 text-right font-medium">
                        {formatSoles(totales.be_total)}
                      </td>
                      <td className="border-l px-4 py-2 text-right font-medium">
                        {formatSoles(totales.cts_may)}
                      </td>
                      <td className="px-4 py-2 text-right font-medium">{formatSoles(totales.cts_nov)}</td>
                      <td className="px-4 py-2 text-right font-bold">{formatSoles(totales.cts_total)}</td>
                      <td className="border-l px-4 py-2 text-right font-medium">{formatSoles(totales.vac)}</td>
                      <td className="px-4 py-2" />
                      <td className="px-4 py-2" />
                      <td className="border-l bg-ambar/10 px-4 py-2 text-right font-bold">
                        {formatSoles(totales.gran_total)}
                      </td>
                      <td className="border-l px-4 py-2" />
                    </tr>
                  </tfoot>
                )}
              </table>
            </div>

            {/* Nota al pie */}
            <p className="mt-4 max-w-3xl text-xs text-taupe">
              Provisión = lo que se reserva para cada pago. Grati y CTS se pagan 2 veces al año;
              vacaciones 1 vez (aniversario). Régimen MYPE pequeña empresa. Cifras referenciales; el
              monto legal final lo calcula el contador. La CTS de mayo del histórico anterior se
              completará cuando se cargue ese periodo.
            </p>
          </>
        )}
      </main>
    </div>
  );
}

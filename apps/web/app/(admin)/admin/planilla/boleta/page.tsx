"use client";

import { Suspense, useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { useRolActual } from "@/lib/admin/use-rol";
import { RANGO_LABEL, formatSoles } from "@/lib/rangos";
import { Marca } from "@/components/marca";
import {
  MESES_LARGO,
  fechaCorta,
  fechaLima,
  fmtHoras,
  type Fila,
  type Proyeccion,
} from "../page";

// Boleta INTERNA de CAYLA: resumen para que la persona vea cómo se calculó su
// sueldo del mes, e imprimirlo/entregarlo (Ctrl+P → Guardar como PDF). NO es
// la boleta oficial PLAME — ver el texto de valor al pie, decidido con Felipe
// el 2026-07-14 (formato lista, sin montos porque AFP varía por fondo).

function fechaHoyLima(): string {
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: "America/Lima", day: "numeric", month: "long", year: "numeric",
  }).format(new Date());
}

function BoletaContenido() {
  const router = useRouter();
  const params = useSearchParams();
  const rol = useRolActual();
  const puedeVer = rol === "admin" || rol === "lider_do";

  const periodoId = params.get("periodo");
  const personaId = params.get("persona");

  const [proy, setProy] = useState<Proyeccion | null>(null);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const cargar = useCallback(async () => {
    if (!periodoId || !personaId) return;
    setCargando(true);
    setError(null);
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) {
      router.replace("/admin/login");
      return;
    }
    const { data, error: e } = await supabase.rpc("fn_proyeccion_periodo", { p_periodo_id: periodoId });
    setCargando(false);
    if (e) {
      setError(e.message);
      return;
    }
    setProy(data as unknown as Proyeccion);
  }, [periodoId, personaId, router]);

  useEffect(() => {
    void cargar();
  }, [cargar]);

  if (!periodoId || !personaId) {
    return (
      <main className="p-6">
        <p className="max-w-md rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
          Falta el periodo o la persona. Abre la boleta desde el botón{" "}
          <Link href="/admin/planilla" className="underline">
            🧾 Ver boleta
          </Link>{" "}
          de la tabla de Planilla.
        </p>
      </main>
    );
  }

  if (rol === null || cargando) {
    return (
      <main className="p-6">
        <p className="text-sm text-taupe">Cargando…</p>
      </main>
    );
  }

  if (!puedeVer) {
    return (
      <main className="p-6">
        <p className="max-w-md rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
          Solo administradores y líderes pueden generar boletas.
        </p>
      </main>
    );
  }

  if (error) {
    return (
      <main className="p-6">
        <p className="max-w-md rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
          No se pudo cargar el periodo: {error}{" "}
          <button onClick={() => void cargar()} className="font-medium underline">
            Reintentar
          </button>
        </p>
      </main>
    );
  }

  const f: Fila | undefined = proy?.filas.find((x) => x.persona_id === personaId);

  if (!proy || !f) {
    return (
      <main className="p-6">
        <p className="max-w-md rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
          No se encontró a esa persona en este periodo.{" "}
          <Link href="/admin/planilla" className="underline">
            Volver a Planilla
          </Link>
        </p>
      </main>
    );
  }

  const totalObj = f.objetivos_total ?? 10;
  const pctObj = totalObj > 0 && f.objetivos_cumplidos !== null ? f.objetivos_cumplidos / totalObj : null;
  const nivelPlus =
    pctObj === null ? "—" : pctObj >= 1 ? "100% (21%)" : pctObj >= 0.6 ? "60% o más (12.6%)" : "menos de 60% (sin plus)";
  const bonos = f.movimientos?.filter((m) => m.tipo === "bono") ?? [];
  const descuentos = f.movimientos?.filter((m) => m.tipo === "descuento") ?? [];

  return (
    <main className="mx-auto max-w-2xl p-6 print:p-0">
      {/* Barra de acciones — no se imprime */}
      <div className="mb-6 flex items-center justify-between print:hidden">
        <Link href="/admin/planilla" className="text-sm text-taupe hover:text-tinta hover:underline">
          ← Volver a Planilla
        </Link>
        <button
          onClick={() => window.print()}
          className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema hover:bg-rojo-profundo"
        >
          Imprimir / Guardar como PDF
        </button>
      </div>

      {/* ── Boleta ── */}
      <div className="rounded-lg border border-sand p-8 print:rounded-none print:border-0 print:p-0">
        <div className="mb-6 flex items-start justify-between border-b border-sand pb-4">
          <Marca tono="tinta" isotipo="rojo" />
          <div className="text-right">
            <p className="etiqueta text-taupe">Boleta interna de pago</p>
            <p className="font-serif text-lg">
              {MESES_LARGO[proy.mes_etiqueta - 1]} {proy.anio_etiqueta}
            </p>
            <p className="text-xs text-taupe">
              {fechaCorta(proy.fecha_ini)} → {fechaCorta(proy.fecha_fin)}
            </p>
          </div>
        </div>

        <div className="mb-6">
          <p className="font-serif text-2xl">{f.nombre}</p>
          <p className="text-sm text-taupe">
            {f.sede} · {f.rango ? (RANGO_LABEL[f.rango] ?? f.rango) : "sin rango"}
            {f.salario_ref !== null ? ` · ${formatSoles(f.salario_ref)}/mes` : ""}
          </p>
        </div>

        {/* Detalle del pago */}
        <table className="mb-6 w-full text-sm">
          <tbody>
            <tr className="border-t border-sand">
              <td className="py-2">Pago base ({fmtHoras(f.horas_mes)})</td>
              <td className="py-2 text-right">{formatSoles(f.pago_base)}</td>
            </tr>
            {f.monto_feriados > 0 && (
              <tr className="border-t border-sand">
                <td className="py-2">Feriados</td>
                <td className="py-2 text-right">{formatSoles(f.monto_feriados)}</td>
              </tr>
            )}
            {f.asignacion_familiar > 0 && (
              <tr className="border-t border-sand">
                <td className="py-2">Asignación familiar 👶</td>
                <td className="py-2 text-right">{formatSoles(f.asignacion_familiar)}</td>
              </tr>
            )}
            <tr className="border-t border-sand">
              <td className="py-2">
                Plus de objetivos
                {f.objetivos_cumplidos !== null && (
                  <span className="text-taupe"> ({f.objetivos_cumplidos}/{totalObj} — {nivelPlus})</span>
                )}
              </td>
              <td className="py-2 text-right">
                {f.monto_plus > 0 ? formatSoles(f.monto_plus) : <span className="text-taupe/50">—</span>}
              </td>
            </tr>
            {bonos.map((m) => (
              <tr key={m.id} className="border-t border-sand">
                <td className="py-2 text-verde">Bono — {m.concepto}</td>
                <td className="py-2 text-right text-verde">+{formatSoles(m.monto)}</td>
              </tr>
            ))}
            {descuentos.map((m) => (
              <tr key={m.id} className="border-t border-sand">
                <td className="py-2 text-rojo">Descuento — {m.concepto}</td>
                <td className="py-2 text-right text-rojo">−{formatSoles(m.monto)}</td>
              </tr>
            ))}
            <tr className="border-t-2 border-tinta">
              <td className="py-3 font-serif text-lg">Total</td>
              <td className="py-3 text-right font-serif text-lg font-bold">{formatSoles(f.total)}</td>
            </tr>
          </tbody>
        </table>

        {/* Bloque de valor — decidido con Felipe 2026-07-14, opción C (lista, sin montos) */}
        <div className="mb-6 rounded-lg bg-sand/40 p-4 text-sm">
          <p className="mb-2 font-medium">Boleta interna de CAYLA — no es tu boleta oficial (PLAME).</p>
          <p className="mb-1">
            <span className="text-verde">✓</span>{" "}
            <span className="font-medium">EsSalud, AFP y asignación familiar:</span> los cubre CAYLA,
            no se descuentan de tu sueldo.
          </p>
          <p>
            <span className="text-verde">✓</span>{" "}
            <span className="font-medium">Gratificación, CTS y vacaciones:</span> se siguen acumulando,
            se pagan en sus fechas.
          </p>
        </div>

        <p className="text-xs text-taupe">
          ¿Algo no cuadra o tienes dudas? Consulta con tu líder de equipo. Generada el {fechaHoyLima()}.
        </p>
      </div>
    </main>
  );
}

export default function BoletaPage() {
  return (
    <Suspense fallback={<main className="p-6"><p className="text-sm text-taupe">Cargando…</p></main>}>
      <BoletaContenido />
    </Suspense>
  );
}

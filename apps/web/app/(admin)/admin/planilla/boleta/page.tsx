"use client";

import { Suspense, useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { useRolActual } from "@/lib/admin/use-rol";
import { RANGO_LABEL, formatSoles } from "@/lib/rangos";
import { Cargando } from "@/components/cargando";
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

// «168.94 h» no se lee: son 168 h y 56 min. Vive solo aquí a propósito —
// fmtHoras (compartido con Planilla) sigue dando centésimas porque ahí son una
// tabla de trabajo y sirven para cuadrar. Esto es un documento para la persona.
function fmtHorasHumano(n: number): string {
  const h = Math.floor(n);
  const min = Math.round((n - h) * 60);
  if (min === 0) return `${h} h`;
  if (min === 60) return `${h + 1} h`;
  return `${h} h ${min} min`;
}

// Por qué el pago base no es el sueldo completo. Los datos ya existían —la 0100
// los expone justamente para que un cero no quede sin explicar—, lo que faltaba
// era decírselo a la persona en su propia boleta. Decidido con Felipe 2026-07-28.
//
// La redacción es deliberadamente distinta a la de Planilla: ahí dice «sin
// salario asignado — asígnale rango en Equipo» porque es una pantalla para
// administrar. Aquí lo mismo se cuenta sin pedirle a la persona que arregle
// nada, que no es su trabajo.
function contextoPagoBase(f: Fila): string[] {
  const partes: string[] = [];
  if (f.dias_laborables === 0) {
    partes.push("no hay horario asignado, así que el sistema no sabe qué días te tocaba venir");
  } else {
    partes.push(`${f.dias_trabajados} de ${f.dias_laborables} días que te tocaba trabajar`);
  }
  if (f.dias_vacaciones > 0) {
    partes.push(`${f.dias_vacaciones} de vacaciones`);
  }
  if (f.horas_sin_salario > 0) {
    partes.push(`${fmtHoras(f.horas_sin_salario)} sin tarifa asignada, que no se pudieron pagar`);
  }
  return partes;
}

function BoletaContenido() {
  const router = useRouter();
  const params = useSearchParams();
  const rol = useRolActual();
  const puedeVer = rol === "admin" || rol === "lider_do";

  const periodoId = params.get("periodo");
  const personaId = params.get("persona");

  const [proy, setProy] = useState<Proyeccion | null>(null);
  const [baseLegal, setBaseLegal] = useState<number | null>(null);
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

    // La base legal contractual (0103) es un atributo de la PERSONA, no un
    // resultado del cálculo, así que se lee de personas y no de
    // fn_proyeccion_periodo — que son 320 líneas muy testeadas y no hacía falta
    // tocar. La política personas_select_admin_lider (0003) ya permite leerla.
    // Si falla, la boleta sigue funcionando sin esa línea: es información
    // añadida, no un requisito para mostrar el pago.
    const { data: persona } = await supabase
      .from("personas")
      .select("sueldo_base_legal")
      .eq("id", personaId)
      .maybeSingle();
    setBaseLegal(persona?.sueldo_base_legal ?? null);
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
        <Cargando />
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

  // Subtotal ganado: todo lo que suma, antes de restar. Solo se muestra si hay
  // descuentos — sin ellos sería idéntico al total y solo agregaría ruido.
  // Decidido con Felipe el 2026-07-28: cuando el descuento es grande (un adelanto,
  // por ejemplo), sin esta línea la persona ve solo el neto y no reconoce que sí
  // ganó su sueldo completo. Suma los mismos campos ya redondeados que usa el
  // 'total' de fn_proyeccion_periodo, así el desglose cuadra al céntimo.
  const subtotalGanado =
    f.pago_base +
    f.monto_feriados +
    f.asignacion_familiar +
    f.monto_plus +
    bonos.reduce((suma, m) => suma + m.monto, 0);

  // ¿Esta boleta es definitiva o todavía se mueve? Antes no se decía en ningún
  // lado, así que alguien podía imprimirla, guardarla, y después recibir otro
  // monto. Para un periodo ya pagado NO decimos «definitiva»: decimos la fecha
  // en que se pagó, que es un hecho. (fn_proyeccion_periodo recalcula en vivo y
  // no lee la foto congelada de la 0096, así que afirmar «definitiva» sería
  // prometer algo que esta pantalla no puede garantizar.)
  // 'estado' es opcional en Proyeccion: si no viene, no inventamos sello.
  const sello =
    proy.simulacion
      ? { texto: "Simulación — no es un pago real", alerta: true }
      : proy.estado === "pagado"
        ? { texto: `Pagada${proy.pagado_at ? ` el ${fechaCorta(proy.pagado_at)}` : ""}`, alerta: false }
        : proy.estado === "abierto"
          ? { texto: "Provisional — el mes aún no cierra", alerta: true }
          : null;

  const contexto = contextoPagoBase(f);

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
            {sello && (
              <p
                className={`mt-1 inline-block rounded px-2 py-0.5 text-xs font-medium ${
                  sello.alerta ? "bg-rojo/10 text-rojo" : "bg-verde/10 text-verde"
                }`}
              >
                {sello.texto}
              </p>
            )}
            <p className="text-xs text-taupe">
              {fechaCorta(proy.fecha_ini)} → {fechaCorta(proy.fecha_fin)}
            </p>
          </div>
        </div>

        <div className="mb-6">
          <p className="font-serif text-2xl">{f.nombre}</p>
          <p className="text-sm text-taupe">
            {f.sede} · {f.rango ? (RANGO_LABEL[f.rango] ?? f.rango) : "sin rango"}
          </p>

          {/* Dos cifras, diferenciadas a propósito: antes iban fundidas en un
              solo «S/ X/mes» que mezclaba lo garantizado con lo potencial.
              · Base legal: en tinta y en negrita — es lo fijo y lo que se
                declara en PLAME. Se omite si está en NULL (ver 0103): no
                afirmamos una base que nadie confirmó.
              · Potencial del rango: en taupe — es referencial.
              Decidido con Felipe el 2026-07-28. */}
          {(baseLegal !== null || f.salario_ref !== null) && (
            <dl className="mt-3 space-y-1 text-sm">
              {baseLegal !== null && (
                <div className="flex justify-between gap-4">
                  <dt className="font-medium">Base Legal Contractual</dt>
                  <dd className="font-medium">{formatSoles(baseLegal)}</dd>
                </div>
              )}
              {f.salario_ref !== null && (
                <div className="flex justify-between gap-4 text-taupe">
                  <dt>Potencial Máximo de Rendimiento Operativo</dt>
                  <dd>{formatSoles(f.salario_ref)}</dd>
                </div>
              )}
            </dl>
          )}
        </div>

        {/* Detalle del pago */}
        <table className="mb-6 w-full text-sm">
          <tbody>
            <tr className="border-t border-sand">
              <td className="py-2">
                Pago base ({fmtHorasHumano(f.horas_mes)})
                {contexto.length > 0 && (
                  <span className="block text-xs text-taupe">{contexto.join(" · ")}</span>
                )}
                {f.dias_pendientes > 0 && (
                  <span className="block text-xs text-rojo">
                    {f.dias_pendientes === 1
                      ? "Queda 1 día por confirmar: este monto todavía puede cambiar."
                      : `Quedan ${f.dias_pendientes} días por confirmar: este monto todavía puede cambiar.`}
                  </span>
                )}
              </td>
              <td className="py-2 text-right align-top">{formatSoles(f.pago_base)}</td>
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
                {/* Un guion pelado no distingue «no llegué» de «no me evaluaron», y
                    es plata. Misma idea que la 0100 con los ceros de Planilla. */}
                <span className="block text-xs text-taupe">
                  {f.objetivos_cumplidos !== null
                    ? `${f.objetivos_cumplidos}/${totalObj} cumplidos — ${nivelPlus}`
                    : "este mes no se registraron objetivos, así que no hubo plus que calcular"}
                </span>
              </td>
              <td className="py-2 text-right align-top">
                {f.monto_plus > 0 ? formatSoles(f.monto_plus) : <span className="text-taupe/50">—</span>}
              </td>
            </tr>
            {bonos.map((m) => (
              <tr key={m.id} className="border-t border-sand">
                <td className="py-2 text-verde">Bono — {m.concepto}</td>
                <td className="py-2 text-right text-verde">+{formatSoles(m.monto)}</td>
              </tr>
            ))}
            {descuentos.length > 0 && (
              <tr className="border-t border-tinta/30">
                <td className="py-2 font-medium">Subtotal ganado</td>
                <td className="py-2 text-right font-medium">{formatSoles(subtotalGanado)}</td>
              </tr>
            )}
            {descuentos.map((m) => (
              <tr key={m.id} className="border-t border-sand">
                <td className="py-2 text-rojo">Descuento — {m.concepto}</td>
                <td className="py-2 text-right text-rojo">−{formatSoles(m.monto)}</td>
              </tr>
            ))}
            <tr className="border-t-2 border-tinta">
              <td className="py-3 font-serif text-lg">Total a recibir este mes</td>
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
            <span className="font-medium">Gratificación, CTS y vacaciones:</span> se siguen acumulando
            y se pagan en sus fechas. Si este mes ya te tocó alguna, la verás arriba como bono.
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
    <Suspense fallback={<main className="p-6"><Cargando /></main>}>
      <BoletaContenido />
    </Suspense>
  );
}

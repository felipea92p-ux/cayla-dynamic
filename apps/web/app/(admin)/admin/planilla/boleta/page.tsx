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
// Nada se imprime si el dato no vino. Suena obvio, pero aquí hay una trampa que
// costó un susto: las migraciones de este proyecto se pegan a mano en producción,
// así que el frontend puede desplegarse ANTES de que existan los campos. Un campo
// ausente llega como undefined, y en JavaScript `undefined > 0` es false (bien)
// pero `undefined === 0` también es false (mal): sin la guarda de typeof, la rama
// else escribía «undefined de undefined días» en un documento de pago.
// Por eso aquí se comprueba typeof number, no !== null.
function num(v: number | null | undefined): number | null {
  return typeof v === "number" && Number.isFinite(v) ? v : null;
}

function contextoPagoBase(f: Fila): string[] {
  const partes: string[] = [];
  const laborables = num(f.dias_laborables);
  const trabajados = num(f.dias_trabajados);
  const vacaciones = num(f.dias_vacaciones);
  const sinSalario = num(f.horas_sin_salario);

  if (laborables === 0) {
    partes.push("no hay horario asignado, así que el sistema no sabe qué días te tocaba venir");
  } else if (laborables !== null && trabajados !== null && trabajados <= laborables) {
    partes.push(`${trabajados} de ${laborables} días que te tocaba trabajar`);
  } else if (trabajados !== null) {
    // «21 de 10 días» es lo que salía antes, y no significa nada. Pasa cuando el
    // horario asignado cubre menos días de los que la persona vino de verdad —
    // normalmente porque su horario está mal configurado. La boleta no es el
    // sitio para destapar eso: dice los días que trabajó, que es un hecho, y el
    // desajuste se revisa en Horarios. Visto en producción el 2026-07-28 con una
    // persona a la que el sistema le contaba 10 laborables y trabajó 21.
    partes.push(`${trabajados} días trabajados`);
  }
  if (vacaciones !== null && vacaciones > 0) {
    partes.push(`${vacaciones} de vacaciones`);
  }
  if (sinSalario !== null && sinSalario > 0) {
    partes.push(`${fmtHoras(sinSalario)} sin tarifa asignada, que no se pudieron pagar`);
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

  // El desglose solo se muestra si las TRES cifras son números de verdad.
  // Se comprueba con typeof y no con !== null a propósito: si la 0104/0105 no
  // están pegadas en la base, estos campos llegan undefined, y `undefined !== null`
  // es true. Con la comprobación floja, la boleta habría partido el pago y escrito
  // «S/ NaN» donde va el sueldo de alguien. Aquí no se asume nada.
  const basicaProp = num(f.basica_legal_prop);
  const complemento = num(f.complemento_variable);
  const rendimientoPct = num(f.rendimiento_pct);
  const hayDesglose = baseLegal !== null && basicaProp !== null && complemento !== null;

  const pendientes = num(f.dias_pendientes) ?? 0;
  const avisoPendientes =
    pendientes > 0
      ? pendientes === 1
        ? "Queda 1 día por confirmar: este monto todavía puede cambiar."
        : `Quedan ${pendientes} días por confirmar: este monto todavía puede cambiar.`
      : null;

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
      {/* La clase `hoja` no pinta nada en pantalla: existe solo para que las
          reglas de @media print de globals.css puedan apretar el interlineado y
          los rellenos de las celdas sin repetir quince variantes print: aquí. */}
      <div className="hoja rounded-lg border border-sand p-8 print:rounded-none print:border-0 print:p-0">
        <div className="mb-6 flex items-start justify-between border-b border-sand pb-4 print:mb-4 print:pb-3">
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

        <div className="mb-6 print:mb-4">
          <p className="font-serif text-2xl">{f.nombre}</p>
          <p className="text-sm text-taupe">
            {f.sede} · {f.rango ? (RANGO_LABEL[f.rango] ?? f.rango) : "sin rango"}
          </p>

          {/* EL POTENCIAL MÁXIMO DEL RANGO YA NO SE IMPRIME AQUÍ.
              Decidido con Felipe el 2026-07-28, y la razón no es el número: es
              el consentimiento. La boleta es unilateral —nadie la firma—, así
              que un «potencial máximo» impreso cada mes crea una expectativa que
              el integrante nunca aceptó, y eso es lo que se presentaría como
              promesa incumplida. El mismo número, en el convenio firmado, es un
              entendimiento mutuo documentado, que es lo que el Art. 19 necesita.
              De paso desaparecen dos problemas: que la cifra se podía superar
              (el plus por metas es 21% ENCIMA del rango) y el desmentido que
              había que poner en el pie para explicarla.
              El potencial sigue existiendo en Planilla, para gestión interna. */}
          {baseLegal !== null && (
            <dl className="mt-3 space-y-1 text-sm">
              <div className="flex justify-between gap-4">
                <dt className="font-medium">Remuneración Básica Legal</dt>
                <dd className="font-medium">{formatSoles(baseLegal)}</dd>
              </div>
            </dl>
          )}
        </div>

        {/* Detalle del pago */}
        <table className="mb-6 w-full text-sm print:mb-4">
          <tbody>
            {/* El pago base se parte en dos cuando la persona tiene básica legal
                fijada (0103/0104). Las dos filas suman exactamente el pago base:
                la básica se redondea y el complemento es la diferencia. Si no hay
                básica fijada, cae a una sola fila y no se inventa la separación. */}
            {hayDesglose ? (
              <>
                <tr className="border-t border-sand">
                  <td className="py-2">
                    Remuneración Básica Legal ({fmtHorasHumano(f.horas_mes)})
                    <span className="block text-xs text-taupe">
                      proporcional a {formatSoles(baseLegal!)} por mes completo
                    </span>
                    {contexto.length > 0 && (
                      <span className="block text-xs text-taupe">{contexto.join(" · ")}</span>
                    )}
                    {avisoPendientes && (
                      <span className="block text-xs text-rojo">{avisoPendientes}</span>
                    )}
                  </td>
                  <td className="py-2 text-right align-top">{formatSoles(basicaProp!)}</td>
                </tr>
                <tr className="border-t border-sand">
                  <td className="py-2">
                    {/* Con la 0104 sola —el estado que Felipe eligió el 2026-07-28
                        para salir del paso— este literal es la etiqueta: el pago no
                        cambia, solo se presenta partido. Cuando entre la 0105 la
                        etiqueta pasará a venir de la fila del mes, elegida de un
                        catálogo, y podrá cambiar de un periodo a otro sin tocar
                        código. Hasta entonces, cambiarla es cambiar esta línea. */}
                    {f.complemento_etiqueta ?? "Rendimiento Extraordinario"}
                    {/* El porcentaje solo se imprime si ALGUIEN lo puntuó de
                        verdad. El 100% por defecto no es una evaluación, y
                        escribirlo creaba una contradicción vista en producción:
                        la misma hoja decía «rendimiento 100%» y, tres líneas más
                        abajo, «3/10 objetivos cumplidos». Para quien la lee son
                        incompatibles; y para un inspector es peor — muestra a
                        alguien cobrando el 100% de lo «variable» mientras falla
                        el 70% de sus metas, que es la prueba de que ese
                        complemento no depende del rendimiento.
                        Decidido con Felipe el 2026-07-28. */}
                    <span className="block text-xs text-taupe">
                      variable, no permanente
                      {rendimientoPct !== null && f.rendimiento_por_defecto !== true
                        ? ` · rendimiento ${rendimientoPct}%`
                        : ""}
                    </span>
                  </td>
                  <td className="py-2 text-right align-top">{formatSoles(complemento!)}</td>
                </tr>
              </>
            ) : (
              <tr className="border-t border-sand">
                <td className="py-2">
                  Remuneración Básica Ordinaria ({fmtHorasHumano(f.horas_mes)})
                  {contexto.length > 0 && (
                    <span className="block text-xs text-taupe">{contexto.join(" · ")}</span>
                  )}
                  {avisoPendientes && (
                    <span className="block text-xs text-rojo">{avisoPendientes}</span>
                  )}
                </td>
                <td className="py-2 text-right align-top">{formatSoles(f.pago_base)}</td>
              </tr>
            )}
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
                Incentivo Variable por Metas (No Permanente)
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
                {/* Sin el prefijo «Bono — », a propósito (2026-07-28). La
                    gratificación y la CTS se guardan como tipo='bono' —la tabla
                    movimientos_planilla solo tiene 'bono' y 'descuento', sin
                    categoría—, así que el prefijo escribía «Bono — Gratificación»
                    y seguía llamando bono a un derecho de ley. El concepto ya
                    lleva su nombre, y que suma se ve en el signo + y en el verde.
                    Para los descuentos el prefijo se queda: ahí no hay riesgo
                    legal y ayuda a leer por qué se resta. */}
                <td className="py-2 text-verde">{m.concepto}</td>
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

        {/* ── Aclaración y Deslinde Legal ──────────────────────────────────────
            Reemplaza la nota simple anterior. Decidido con Felipe 2026-07-28.
            Los dos puntos de VALOR (lo que cubre CAYLA, y que grati/CTS/vacaciones
            siguen acumulándose) se conservan: eran una decisión del 2026-07-14 y
            son lo único de este bloque que juega a favor de quien lo lee.
            Las cifras se toman de los datos de la persona, NUNCA se escriben a
            mano: un deslinde que cita un monto que no coincide con el desglose de
            arriba se vuelve prueba en contra. Si un dato falta, el punto se omite. */}
        <div className="mb-6 rounded-lg bg-sand/40 p-4 text-sm print:mb-3 print:break-inside-avoid print:p-3">
          <p className="mb-3 font-medium">Aclaración y Deslinde Legal de Remuneración</p>
          <ul className="mb-3 list-disc space-y-2 pl-5">
            {/* SIN CIFRA, y remitiendo al PLAME. Decidido con Felipe el 2026-07-28.
                Antes afirmaba «el único sueldo ordinario fijo asciende a S/ X».
                Se quitó el monto porque esta hoja no puede garantizar que coincida
                con el documento oficial de cada persona, y una cifra que se
                contradiga con el PLAME convierte esta boleta en prueba en contra.
                El PLAME es la autoridad y aquí se dice así. */}
            <li>
              <span className="font-medium">Remuneración básica:</span> el sueldo ordinario fijo y
              garantizado es el que figura como remuneración básica en tu boleta oficial PLAME. Los
              importes de esta hoja son un desglose interno de cómo se compone tu pago del mes.
            </li>
            {/* ANTES ESTE PUNTO ERA FALSO, y por eso se reescribió: decía que
                «los montos adicionales» eran incentivos variables no computables,
                y entre esos adicionales están la asignación familiar, los feriados
                y la gratificación — que son DERECHOS DE LEY, no incentivos, y sí
                son computables. Un documento firmado por la empresa que
                mischaracteriza lo obligatorio es exactamente lo que se usa en
                contra. Ahora se nombra qué es variable y se dice que el resto no.
                Que la empresa demuestre saber distinguir es lo que hace creíble
                el amparo del Art. 19; meterlo todo en el mismo saco lo destruye. */}
            <li>
              <span className="font-medium">Carácter variable de algunos conceptos:</span> el{" "}
              <span className="font-medium">Rendimiento Extraordinario</span> y el{" "}
              <span className="font-medium">Incentivo Variable por Metas</span> son variables, se
              evalúan mes a mes, no tienen carácter permanente y no forman parte de la remuneración
              computable (Art. 19 del D.S. 001-97-TR).
            </li>
            <li>
              <span className="font-medium">Lo demás son derechos de ley:</span> los feriados, la
              asignación familiar, la gratificación, la CTS y las vacaciones te corresponden por
              ley y se pagan como tales. No son incentivos ni dependen de tu rendimiento.
            </li>
            <li>
              <span className="font-medium">Efecto fiscal y laboral:</span> la boleta oficial para
              efectos de SUNAT, SUNAFIL, aportes de ley y beneficios sociales es exclusivamente la
              emitida en el sistema PLAME. Esta es una boleta interna de CAYLA.
            </li>
          </ul>
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

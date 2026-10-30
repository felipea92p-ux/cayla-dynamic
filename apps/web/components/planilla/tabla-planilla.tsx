"use client";

// La tabla de un grupo del periodo. Solo LEE: toda escritura sobre una persona
// —bonos, descuentos, «Ya le pagué aparte», básica legal— vive en su panel
// (panel-persona.tsx), que se abre al tocar la fila.
//
// Por qué salió de la fila lo que se editaba ahí (2026-09-15): la básica legal
// se guardaba sola al salir del campo, así que pasar con Tab por la tabla de
// revisión podía reescribir un dato de contrato; y tres botones y cinco avisos
// dentro de la celda del nombre hacían ilegible justo la columna que se lee
// primero. Ninguna columna se quitó: se quitó lo que no era lectura.
//
// La columna «Pagado» (0562) es la ÚNICA excepción a «solo lee», y a propósito:
// es un solo gesto (una casilla), nunca queda a medias como la básica legal lo
// quedaba, y no se guarda sola — el click abre la confirmación en el padre, así
// que nada se escribe por pasar Tab por la fila. Es el checklist personal de
// Felipe para ir pagando persona por persona; no es el pago oficial del grupo.
//
// Dos presentaciones del MISMO dato: tabla desde md, tarjetas por persona en
// celular. Una tabla de once columnas a 375 px no se lee, se adivina.

import { useMemo, type MouseEvent } from "react";
import { ChevronRight } from "lucide-react";
import { formatSoles, RANGO_LABEL } from "@/lib/rangos";
import { CampoCasilla } from "@/components/ui/campo";
import { Insignia } from "@/components/ui/insignia";
import { Tabla, TablaEncabezado, Th, Fila as FilaTabla } from "@/components/ui/tabla";
import { fechaCorta, fechaLargaLima, feriadoNoCorresponde, fmtHoras } from "@/lib/admin/planilla/formato";
import { claveFila, sumarFilas, textoCese, type Cese, type Hallazgo } from "@/lib/admin/planilla/revision";
import type { EstadoPagoPersona, Fila } from "@/lib/admin/planilla/tipos";
import { EtiquetaPrueba } from "@/components/pruebas/etiqueta-prueba";
import type { FilaPrueba } from "@/lib/admin/pruebas";

// Contadas: Persona · Sede · Rango y salario · Horas · Pago base · Feriados ·
// Asig. familiar · Movilidad · Educación · Básica legal · Bonos · Descuentos ·
// Total · Pagado · (abrir).
const COLS = 15;

/** La celda de «Pagado»: casilla + su estado, o solo lectura si el grupo ya se congeló. */
function CeldaPago({ f, estado, puedeMarcar, onMarcar, onDesmarcar, onVerHistorial }: {
  f: Fila;
  estado: EstadoPagoPersona | undefined;
  puedeMarcar: boolean;
  onMarcar?: (f: Fila) => void;
  onDesmarcar?: (f: Fila) => void;
  onVerHistorial?: (f: Fila) => void;
}) {
  const marcado = estado?.marcado ?? false;
  // El monto se congela al marcar; si después una corrección movió el Total, se avisa — nunca se calla ni se corrige solo.
  const cambio = marcado && estado && Math.abs(estado.monto - f.total) > 0.004;
  if (!puedeMarcar) {
    return marcado
      ? <span className="inline-flex items-center gap-1 text-xs text-verde"><span aria-hidden>✓</span>Pagado</span>
      : <span className="text-taupe/50">—</span>;
  }
  return (
    <span className="inline-flex flex-col items-start gap-0.5">
      <CampoCasilla
        checked={marcado}
        onChange={() => (marcado ? onDesmarcar?.(f) : onMarcar?.(f))}
        aria-label={marcado ? `Desmarcar a ${f.nombre} como pagada` : `Marcar a ${f.nombre} como pagada`}
      />
      {marcado && estado?.marcado_at && (
        <span className="whitespace-nowrap text-xs text-taupe">
          {fechaLargaLima(estado.marcado_at)}{estado.marcado_por_nombre ? ` · ${estado.marcado_por_nombre}` : ""}
        </span>
      )}
      {cambio && (
        <span className="whitespace-nowrap text-xs text-ambar" title="El Total cambió desde que se marcó — vuelve a revisar antes de pagar.">
          cambió: {formatSoles(estado.monto)} → {formatSoles(f.total)}
        </span>
      )}
      {estado && (
        <button type="button" onClick={() => onVerHistorial?.(f)} className="text-xs text-taupe underline decoration-taupe/0 underline-offset-2 hover:decoration-taupe/60">
          Historial
        </button>
      )}
    </span>
  );
}

function rangoYSalario(f: Fila) {
  if (f.salario_ref === null) return <span className="text-rojo-profundo">Sin salario</span>;
  const etiqueta = f.tipo_vinculo === "practicante"
    ? "Subvención"
    : f.en_planilla === false
      ? "Honorarios"
      : ((f.rango && (RANGO_LABEL[f.rango] ?? f.rango)) ?? "—");
  return <span className="whitespace-nowrap">{etiqueta} · {formatSoles(f.salario_ref)}</span>;
}

/** La insignia que resume a la persona: lo que frena primero, lo que pide revisión después. */
function InsigniasPersona({ hallazgos, cese }: { hallazgos: Hallazgo[]; cese: Cese }) {
  const frena = hallazgos.filter((h) => h.severidad === "bloquea").length;
  const revisar = hallazgos.filter((h) => h.severidad === "revisar").length;
  const textoDelCese = textoCese(cese);
  if (!frena && !revisar && !textoDelCese) return null;
  return (
    <span className="mt-1 flex flex-wrap gap-1">
      {textoDelCese && <Insignia variante="neutral" tamano="sm">{textoDelCese}</Insignia>}
      {frena > 0 && <Insignia variante="alerta" tamano="sm">Frena el pago</Insignia>}
      {revisar > 0 && (
        <Insignia variante="advertencia" tamano="sm">
          {revisar} por revisar
        </Insignia>
      )}
    </span>
  );
}

function Guion() {
  return <span className="text-taupe/50">—</span>;
}

export function TablaPlanilla({
  filas,
  totalDelGrupo,
  etiquetaGrupo,
  filtrado,
  simulacion = false,
  hallazgos,
  ceses,
  pruebas,
  pagos,
  puedeMarcarPago = false,
  onMarcarPago,
  onDesmarcarPago,
  onVerHistorialPago,
  onAbrir,
}: {
  /** Las filas que se ven (ya filtradas). */
  filas: Fila[];
  /** Cuántas personas tiene el grupo SIN filtro: para decir «X de Y». */
  totalDelGrupo: number;
  etiquetaGrupo: string;
  /** Si hay algún filtro puesto: el pie deja de llamarse «Total» y pasa a «Subtotal visible». */
  filtrado: boolean;
  simulacion?: boolean;
  hallazgos?: Map<string, Hallazgo[]>;
  ceses?: Map<string, Cese>;
  /** Quién está de prueba y en qué día va (0536): la etiqueta «Prueba · 2 de 3» junto al nombre. */
  pruebas?: Map<string, FilaPrueba>;
  /** El checklist personal de pago (0562), por persona_id. Sin esto, la columna «Pagado» no se dibuja. */
  pagos?: Map<string, EstadoPagoPersona>;
  /** Solo admin, y solo mientras el grupo sigue abierto: una vez congelado, la columna pasa a ser de solo lectura. */
  puedeMarcarPago?: boolean;
  onMarcarPago?: (f: Fila) => void;
  onDesmarcarPago?: (f: Fila) => void;
  onVerHistorialPago?: (f: Fila) => void;
  onAbrir?: (f: Fila, disparador: HTMLElement) => void;
}) {
  const t = useMemo(() => sumarFilas(filas), [filas]);
  const etiquetaPie = filtrado
    ? `Subtotal visible · ${filas.length} de ${totalDelGrupo} ${totalDelGrupo === 1 ? "persona" : "personas"}`
    : `Total «${etiquetaGrupo}» · ${filas.length} ${filas.length === 1 ? "persona" : "personas"}`;
  const abrir = (f: Fila) => (e: MouseEvent<HTMLElement>) => onAbrir?.(f, e.currentTarget);
  const vacio = simulacion
    ? "No hay personas de este grupo en el rango simulado."
    : filtrado
      ? "Nadie de este grupo coincide con el filtro."
      : "No hay personas de este grupo en el periodo.";

  return (
    <>
      {/* ── Desde md: la tabla completa ─────────────────────────────────── */}
      <div className="hidden md:block">
        <Tabla>
          <TablaEncabezado>
            <Th>Persona</Th>
            <Th>Sede</Th>
            <Th>Rango y salario</Th>
            <Th className="text-right">Horas</Th>
            <Th className="text-right">Pago base</Th>
            <Th className="text-right">Feriados</Th>
            <Th className="text-right">Asig. familiar</Th>
            <Th className="text-right">
              <span title="Movilidad (pasajes) por los días que marcó: la tarifa de su sede × los días trabajados. Es no remunerativa solo si está supeditada a la asistencia.">
                Movilidad
              </span>
            </Th>
            <Th className="text-right">
              <span title="Asignación por educación: se paga contra el comprobante archivado.">
                Educación
              </span>
            </Th>
            <Th className="text-right">
              <span title="Remuneración básica legal mensual: la que se declara en PLAME. Es un dato de la persona, no un monto de este periodo.">
                Básica legal
              </span>
            </Th>
            <Th className="text-right">Bonos</Th>
            <Th className="text-right">Descuentos</Th>
            <Th className="text-right">Total</Th>
            <Th>Pagado</Th>
            <Th><span className="sr-only">Abrir</span></Th>
          </TablaEncabezado>
          <tbody>
            {filas.length === 0 && (
              <tr>
                <td colSpan={COLS} className="px-4 py-6 text-center text-taupe">{vacio}</td>
              </tr>
            )}
            {filas.map((f) => {
              const hs = hallazgos?.get(claveFila(f)) ?? [];
              const cese = ceses?.get(f.persona_id) ?? null;
              const frena = hs.some((h) => h.severidad === "bloquea");
              return (
                <FilaTabla
                  key={f.persona_id}
                  className={`align-top ${onAbrir ? "cursor-pointer" : ""} ${frena ? "bg-rojo/[0.04]" : ""}`}
                >
                  <td className="px-4 py-2" onClick={onAbrir ? abrir(f) : undefined}>
                    {onAbrir ? (
                      <button
                        type="button"
                        onClick={(e) => { e.stopPropagation(); onAbrir(f, e.currentTarget); }}
                        className="text-left font-medium text-tinta underline decoration-taupe/0 underline-offset-2 hover:decoration-taupe/60"
                      >
                        {f.nombre}
                      </button>
                    ) : (
                      <span className="font-medium">{f.nombre}</span>
                    )}
                    <EtiquetaPrueba fila={pruebas?.get(f.persona_id)} className="ml-2" />
                    <InsigniasPersona hallazgos={hs} cese={cese} />
                  </td>
                  <td className="px-4 py-2" onClick={onAbrir ? abrir(f) : undefined}>{f.sede}</td>
                  <td className="px-4 py-2" onClick={onAbrir ? abrir(f) : undefined}>{rangoYSalario(f)}</td>
                  <td className="px-4 py-2 text-right tabular-nums" onClick={onAbrir ? abrir(f) : undefined}>
                    <span className="whitespace-nowrap">{fmtHoras(f.horas_mes)}</span>
                    {f.dias_pendientes > 0 && (
                      <span className="mt-1 block">
                        <Insignia variante="advertencia" tamano="sm">{f.dias_pendientes} pend.</Insignia>
                      </span>
                    )}
                  </td>
                  <td className="px-4 py-2 text-right tabular-nums" onClick={onAbrir ? abrir(f) : undefined}>
                    {formatSoles(f.pago_base)}
                  </td>
                  <td
                    className="px-4 py-2 text-right tabular-nums"
                    onClick={onAbrir ? abrir(f) : undefined}
                    title={f.feriados_detalle.length > 0
                      ? f.feriados_detalle.map((d) =>
                          `${fechaCorta(d.fecha)}: ${feriadoNoCorresponde(d) ?? `${d.horas_trabajadas} h trabajadas + ${d.proporcional_horas} h proporcionales`}`).join("\n")
                      : undefined}
                  >
                    {f.monto_feriados > 0 ? formatSoles(f.monto_feriados) : <Guion />}
                    {/* Una línea corta; el porqué completo va en el título de la celda y en el panel de la persona. */}
                    {f.feriados_no_corresponde > 0 && (
                      <span
                        className="mt-1 block whitespace-nowrap text-xs text-taupe"
                        title={f.feriados_detalle
                          .filter((d) => feriadoNoCorresponde(d))
                          .map((d) => `${fechaCorta(d.fecha)}: ${feriadoNoCorresponde(d)}`)
                          .join("\n")}
                      >
                        {f.feriados_no_corresponde} no aplica{f.feriados_no_corresponde === 1 ? "" : "n"}
                      </span>
                    )}
                  </td>
                  <td className="px-4 py-2 text-right tabular-nums" onClick={onAbrir ? abrir(f) : undefined}>
                    {f.asignacion_familiar > 0 ? formatSoles(f.asignacion_familiar) : <Guion />}
                  </td>
                  <td
                    className="px-4 py-2 text-right tabular-nums"
                    onClick={onAbrir ? abrir(f) : undefined}
                    title={(f.monto_movilidad ?? 0) > 0 && f.movilidad_diaria
                      ? `${formatSoles(f.movilidad_diaria)} por día trabajado`
                      : undefined}
                  >
                    {(f.monto_movilidad ?? 0) > 0 ? formatSoles(f.monto_movilidad ?? 0) : <Guion />}
                  </td>
                  <td
                    className="px-4 py-2 text-right tabular-nums"
                    onClick={onAbrir ? abrir(f) : undefined}
                    title={(f.monto_educacion ?? 0) > 0 && f.instituciones_educacion
                      ? f.instituciones_educacion
                      : undefined}
                  >
                    {(f.monto_educacion ?? 0) > 0 ? formatSoles(f.monto_educacion ?? 0) : <Guion />}
                    {/* Un cero con explicación, como en la boleta (0236): tiene la
                        asignación registrada y no se le paga porque falta el papel. */}
                    {(f.monto_educacion ?? 0) === 0 && f.educacion_sin_comprobante && (
                      <span
                        className="mt-1 block whitespace-nowrap text-xs text-taupe"
                        title="Tiene la asignación registrada, pero falta cargar el comprobante: no se paga hasta tenerlo."
                      >
                        sin comprobante
                      </span>
                    )}
                  </td>
                  <td className="px-4 py-2 text-right tabular-nums text-taupe" onClick={onAbrir ? abrir(f) : undefined}>
                    {f.sueldo_base_legal != null ? formatSoles(f.sueldo_base_legal) : <Guion />}
                  </td>
                  <td className="px-4 py-2 text-right tabular-nums" onClick={onAbrir ? abrir(f) : undefined}>
                    {f.bonos > 0 ? <span className="whitespace-nowrap">+{formatSoles(f.bonos)}</span> : <Guion />}
                  </td>
                  <td className="px-4 py-2 text-right tabular-nums" onClick={onAbrir ? abrir(f) : undefined}>
                    {f.descuentos > 0 ? <span className="whitespace-nowrap">−{formatSoles(f.descuentos)}</span> : <Guion />}
                    {(f.retencion_4ta ?? 0) > 0 && (
                      <span className="mt-1 block">
                        <Insignia variante="neutral" tamano="sm" punto={false}>4ta −{formatSoles(f.retencion_4ta ?? 0)}</Insignia>
                      </span>
                    )}
                  </td>
                  <td className="px-4 py-2 text-right font-semibold tabular-nums" onClick={onAbrir ? abrir(f) : undefined}>
                    {formatSoles(f.total)}
                  </td>
                  <td className="px-4 py-2 align-top">
                    <CeldaPago
                      f={f}
                      estado={pagos?.get(f.persona_id)}
                      puedeMarcar={puedeMarcarPago}
                      onMarcar={onMarcarPago}
                      onDesmarcar={onDesmarcarPago}
                      onVerHistorial={onVerHistorialPago}
                    />
                  </td>
                  <td className="py-2 pr-3 text-taupe" onClick={onAbrir ? abrir(f) : undefined}>
                    {onAbrir && <ChevronRight size={16} aria-hidden />}
                  </td>
                </FilaTabla>
              );
            })}
          </tbody>
          {filas.length > 0 && (
            <tfoot>
              <tr className="border-t border-sand bg-sand/50">
                <td className="px-4 py-2 font-medium" colSpan={4}>{etiquetaPie}</td>
                <td className="px-4 py-2 text-right font-medium tabular-nums">{formatSoles(t.pago_base)}</td>
                <td className="px-4 py-2 text-right font-medium tabular-nums">{formatSoles(t.feriados)}</td>
                <td className="px-4 py-2 text-right font-medium tabular-nums">{formatSoles(t.asignacion)}</td>
                <td className="px-4 py-2 text-right font-medium tabular-nums">{t.movilidad > 0 ? formatSoles(t.movilidad) : <Guion />}</td>
                <td className="px-4 py-2 text-right font-medium tabular-nums">{t.educacion > 0 ? formatSoles(t.educacion) : <Guion />}</td>
                {/* Básica legal no se suma: es un dato por persona, no un concepto que se pague acá. */}
                <td className="px-4 py-2" />
                <td className="px-4 py-2 text-right font-medium tabular-nums">{t.bonos > 0 ? `+${formatSoles(t.bonos)}` : <Guion />}</td>
                <td className="px-4 py-2 text-right font-medium tabular-nums">{t.descuentos > 0 ? `−${formatSoles(t.descuentos)}` : <Guion />}</td>
                <td className="px-4 py-2 text-right font-bold tabular-nums">{formatSoles(t.total)}</td>
                <td />
                <td />
              </tr>
              {/* Dos preguntas distintas: arriba, cuánto le llega a la gente; acá,
                  cuánto sale de la cuenta. Solo aparece si hay algo que agregar. */}
              {t.sale_del_banco > t.total + 0.004 && (
                <tr className="border-t border-sand bg-sand/30">
                  <td className="px-4 py-2 text-taupe" colSpan={COLS - 2}>
                    Sale de la cuenta de CAYLA
                    <span className="block text-xs">
                      el total + {formatSoles(t.pension)} de pensión + {formatSoles(t.essalud)} de EsSalud
                      {t.retencion_4ta > 0 && <> + {formatSoles(t.retencion_4ta)} de retención de 4ta</>}
                      {" "}· no incluye provisiones, que se pagan después
                    </span>
                  </td>
                  <td className="px-4 py-2 text-right font-bold tabular-nums">{formatSoles(t.sale_del_banco)}</td>
                  <td />
                </tr>
              )}
            </tfoot>
          )}
        </Tabla>
      </div>

      {/* ── Celular: una tarjeta por persona ────────────────────────────── */}
      <div className="md:hidden">
        {filas.length === 0 ? (
          <p className="rounded-superficie border border-sand bg-papel px-4 py-6 text-center text-sm text-taupe">{vacio}</p>
        ) : (
          <ul className="space-y-2">
            {filas.map((f) => {
              const hs = hallazgos?.get(claveFila(f)) ?? [];
              const cese = ceses?.get(f.persona_id) ?? null;
              const contenido = (
                <>
                  <span className="flex items-start justify-between gap-3">
                    <span className="min-w-0">
                      <span className="block font-medium text-tinta">{f.nombre}<EtiquetaPrueba fila={pruebas?.get(f.persona_id)} className="ml-2" /></span>
                      <span className="block text-xs text-taupe">
                        {f.sede} · {fmtHoras(f.horas_mes)}
                        {f.dias_pendientes > 0 && ` · ${f.dias_pendientes} pend.`}
                      </span>
                      {((f.monto_movilidad ?? 0) > 0 || (f.monto_educacion ?? 0) > 0) && (
                        <span className="block text-xs text-taupe">
                          {(f.monto_movilidad ?? 0) > 0 && `Movilidad ${formatSoles(f.monto_movilidad ?? 0)}`}
                          {(f.monto_movilidad ?? 0) > 0 && (f.monto_educacion ?? 0) > 0 && " · "}
                          {(f.monto_educacion ?? 0) > 0 && `Educación ${formatSoles(f.monto_educacion ?? 0)}`}
                        </span>
                      )}
                    </span>
                    <span className="shrink-0 text-right font-semibold tabular-nums">{formatSoles(f.total)}</span>
                  </span>
                  <InsigniasPersona hallazgos={hs} cese={cese} />
                </>
              );
              return (
                <li key={f.persona_id}>
                  {/* La casilla de pago queda FUERA del botón que abre el panel: un botón
                      dentro de otro botón no es válido, y acá los dos conviven. */}
                  <div className="rounded-superficie border border-sand bg-papel p-4 text-sm">
                    {onAbrir ? (
                      <button type="button" onClick={(e) => onAbrir(f, e.currentTarget)} className="block w-full text-left">
                        {contenido}
                      </button>
                    ) : contenido}
                    {pagos && (
                      <div className="mt-2 flex items-center justify-between gap-3 border-t border-sand pt-2">
                        <span className="text-xs text-taupe">Pagado</span>
                        <CeldaPago
                          f={f}
                          estado={pagos.get(f.persona_id)}
                          puedeMarcar={puedeMarcarPago}
                          onMarcar={onMarcarPago}
                          onDesmarcar={onDesmarcarPago}
                          onVerHistorial={onVerHistorialPago}
                        />
                      </div>
                    )}
                  </div>
                </li>
              );
            })}
          </ul>
        )}
        {filas.length > 0 && (
          <div className="mt-2 rounded-superficie bg-sand/50 px-4 py-3 text-sm">
            <p className="flex justify-between gap-3 font-medium">
              <span>{etiquetaPie}</span>
              <span className="tabular-nums">{formatSoles(t.total)}</span>
            </p>
            {t.sale_del_banco > t.total + 0.004 && (
              <p className="mt-1 flex justify-between gap-3 text-xs text-taupe">
                <span>Sale de la cuenta (con pensión, EsSalud y 4ta)</span>
                <span className="tabular-nums">{formatSoles(t.sale_del_banco)}</span>
              </p>
            )}
          </div>
        )}
      </div>
    </>
  );
}

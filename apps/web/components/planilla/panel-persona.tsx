"use client";

// Todo lo de UNA persona en ESTE periodo: cómo se arma su total, qué avisa, sus
// horas, y las escrituras que antes vivían dentro de la fila de la tabla.
//
// Las confirmaciones van EN LÍNEA y no en un <Modal>: el panel entra animado con
// `transform`, y un `position: fixed` dentro de un ancestro transformado queda
// encerrado en él. Además, confirmar junto al formulario deja a la vista lo que
// se está confirmando.
//
// No cambia ninguna llamada a la base: mismas funciones y mismos parámetros
// que la pantalla usaba el 2026-09-14 (fn_agregar_movimiento,
// fn_quitar_movimiento, fn_registrar_desembolso, fn_set_sueldo_base_legal).

import { useState, type ReactNode, type RefObject } from "react";
import Link from "next/link";
import type { createAdminSupabaseClient } from "@cayla-dynamic/database";
import {
  ES_DE_MODALIDAD_FORMATIVA, TIPO_VINCULO_LABEL, hoyLima, nombreDelPeriodo, parsearMontoSoles,
  periodoAnterior, periodoQueContiene,
  type BeneficioDesembolso, type PeriodoDeBeneficio,
} from "@cayla-dynamic/shared";
import { formatSoles, RANGO_LABEL } from "@/lib/rangos";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { useToast } from "@/components/toast";
import { Drawer } from "@/components/ui/drawer";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { Insignia } from "@/components/ui/insignia";
import { fechaCorta, fmtHoras, isoADiaMesAnio } from "@/lib/admin/planilla/formato";
import {
  desgloseDe, grupoDe, liquidacionResuelta, textoCese, type Cese, type Hallazgo,
} from "@/lib/admin/planilla/revision";
import {
  CLASE_A_CATEGORIA, CLASE_A_TIPO, CLASE_LABEL, CLASE_PLACEHOLDER, MOV_FORM_VACIO, type ClaseMov, type MovForm,
} from "@/lib/admin/planilla/movimientos";
import type { Fila, GratiCts, Liquidada, Movimiento } from "@/lib/admin/planilla/tipos";

type Supabase = ReturnType<typeof createAdminSupabaseClient>;

interface Confirmacion {
  texto: string;
  textoBoton: string;
  peligro?: boolean;
  accion: () => Promise<void>;
}

function Seccion({ titulo, children }: { titulo: string; children: ReactNode }) {
  return (
    <section className="border-t border-sand pt-4 first:border-t-0 first:pt-0">
      <h3 className="etiqueta mb-2 text-taupe">{titulo}</h3>
      {children}
    </section>
  );
}

function Dato({ etiqueta, children }: { etiqueta: string; children: ReactNode }) {
  return (
    <div className="flex justify-between gap-4 py-1 text-sm">
      <dt className="text-taupe">{etiqueta}</dt>
      <dd className="text-right tabular-nums">{children}</dd>
    </div>
  );
}

function CajaConfirmar({ c, ocupado, onCancelar, onConfirmar }: {
  c: Confirmacion; ocupado: boolean; onCancelar: () => void; onConfirmar: () => void;
}) {
  return (
    <div className={`mt-3 rounded-control border p-3 text-sm ${c.peligro ? "border-rojo/30 bg-rojo/[0.05]" : "border-sand bg-hueso"}`}>
      <p className="mb-3 whitespace-pre-line">{c.texto}</p>
      <div className="flex justify-end gap-2">
        <Boton tamano="sm" onClick={onCancelar} disabled={ocupado}>Cancelar</Boton>
        <Boton tamano="sm" variante={c.peligro ? "peligro" : "primario"} onClick={onConfirmar} cargando={ocupado}>
          {c.textoBoton}
        </Boton>
      </div>
    </div>
  );
}

// ── Adelanto de beneficio: a qué ventana del libro va ─────────────────────
// La ventana y el año salen de `periodoQueContiene` (packages/shared), que hace
// la misma cuenta que fn_cts_trunca y fn_grati_trunca. Hasta el 2026-09-15 este
// formulario decidía la CTS con la regla de la gratificación (mes <= 6), y una
// CTS adelantada en junio quedaba restando de la ventana ya depositada en mayo.
//
// `periodo` existe para lo que la fecha sola no resuelve: una CTS pagada el
// 10/05 puede ser del periodo que empieza o el depósito atrasado del que
// terminó. Por defecto, el periodo que contiene la fecha —lo mismo que haría la
// liquidación con esa fecha de cese—, y el anterior a un clic.
type AdelantoForm = {
  beneficio: BeneficioDesembolso;
  monto: string;
  fecha: string;
  nota: string;
  periodo: "actual" | "anterior";
};

// CAMBIO 0467 — arranca en el beneficio que esa persona sí puede recibir. Con
// un valor fijo, el formulario de una practicante abría en «gratificación»,
// que ya no es una opción de su desplegable: el select salía en blanco y el
// primer clic registraba lo que el navegador eligiera por su cuenta.
const adelantoVacio = (tipoVinculo?: string | null): AdelantoForm => ({
  beneficio: tipoVinculo === "practicante" ? "subvencion_semestral" : "gratificacion",
  monto: "", fecha: hoyLima(), nota: "", periodo: "actual",
});

function periodosDelAdelanto(a: AdelantoForm): { actual: PeriodoDeBeneficio; anterior: PeriodoDeBeneficio } | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(a.fecha)) return null;
  const actual = periodoQueContiene(a.beneficio, a.fecha);
  return { actual, anterior: periodoAnterior(actual) };
}

function periodoDelAdelanto(a: AdelantoForm): PeriodoDeBeneficio | null {
  const p = periodosDelAdelanto(a);
  if (!p) return null;
  return a.periodo === "anterior" && a.beneficio !== "vacaciones" ? p.anterior : p.actual;
}

function Contenido({
  fila: f, periodoId, pagado, liquidada, cese, hallazgos, gc, origenes, supabase, onCambio,
}: {
  fila: Fila;
  periodoId: string;
  pagado: boolean;
  liquidada: Liquidada | null;
  cese: Cese;
  hallazgos: Hallazgo[];
  gc: GratiCts | null;
  origenes: { id: string; etiqueta: string }[];
  supabase: Supabase;
  onCambio: () => Promise<void>;
}) {
  const { avisar } = useToast();
  const [ocupado, setOcupado] = useState(false);
  // Una sola confirmación abierta a la vez, y se dibuja junto al formulario que la pidió.
  const [confirmacion, setConfirmacion] = useState<{ donde: string; c: Confirmacion } | null>(null);
  const [movForm, setMovForm] = useState<MovForm>(MOV_FORM_VACIO);
  const [mostrandoYaPagado, setMostrandoYaPagado] = useState(false);
  const liqPorCubrir = liquidada ? liquidada.cobro_del_periodo - f.descuentos : f.total;
  const sugeridoYaPagado = Math.max(0, Math.round(liqPorCubrir * 100) / 100);
  const [yaPagado, setYaPagado] = useState({ monto: String(sugeridoYaPagado), fecha: hoyLima() });
  const [mostrandoAdelanto, setMostrandoAdelanto] = useState(false);
  const [adelanto, setAdelanto] = useState<AdelantoForm>(() => adelantoVacio(f.tipo_vinculo));
  const periodoAdelanto = periodoDelAdelanto(adelanto);
  const [basica, setBasica] = useState(f.sueldo_base_legal != null ? String(f.sueldo_base_legal) : "");

  const desglose = desgloseDe(f);
  const movs = f.movimientos ?? [];
  const bonos = movs.filter((m) => m.tipo === "bono");
  const descuentos = movs.filter((m) => m.tipo === "descuento");
  const lock = "Este grupo ya está pagado: se reabre para modificarlo.";

  async function ejecutar() {
    if (!confirmacion) return;
    setOcupado(true);
    try {
      await confirmacion.c.accion();
    } finally {
      setOcupado(false);
      setConfirmacion(null);
    }
  }

  // ── Bonos y descuentos ──────────────────────────────────────────────────
  function alCambiarTipo(t: ClaseMov) {
    if ((t === "gratificacion" || t === "cts" || t === "bonificacion_extraordinaria") && gc) {
      const gp = gc.porPersona[f.persona_id];
      const monto = t === "gratificacion" ? gp?.grati : t === "cts" ? gp?.cts : gp?.be;
      const concepto = t === "gratificacion" ? gc.gratiConcepto : t === "cts" ? gc.ctsConcepto : gc.beConcepto;
      // `origen` vacío a propósito (0305): grati y CTS son de la ventana de ESTE periodo.
      setMovForm({ tipo: t, concepto: concepto || CLASE_LABEL[t], monto: monto ? String(monto) : "", origen: "" });
    } else {
      setMovForm({ ...movForm, tipo: t });
    }
  }

  function pedirAgregarMovimiento() {
    const concepto = movForm.concepto.trim();
    const monto = Number(movForm.monto);
    if (concepto.length < 2) { avisar("error", "Pon el concepto del movimiento (mínimo 2 letras)."); return; }
    if (!Number.isFinite(monto) || monto <= 0) { avisar("error", "El monto debe ser mayor a 0."); return; }
    const { tipo, origen } = movForm;
    setConfirmacion({
      donde: "mov",
      c: {
        texto: `¿Registrar ${CLASE_LABEL[tipo]} de ${formatSoles(monto)} para ${f.nombre} — «${concepto}»?`,
        textoBoton: "Registrar",
        accion: async () => {
          const { error } = await supabase.rpc("fn_agregar_movimiento", {
            p_periodo_id: periodoId,
            p_persona_id: f.persona_id,
            p_tipo: CLASE_A_TIPO[tipo],
            p_concepto: concepto,
            p_monto: monto,
            p_categoria: CLASE_A_CATEGORIA[tipo],
            p_periodo_origen_id: origen || null,
          });
          if (error) { avisar("error", mensajeDeError(error, "registrar el movimiento")); return; }
          avisar("ok", `${CLASE_LABEL[tipo]} de ${formatSoles(monto)} para ${f.nombre}.`);
          setMovForm(MOV_FORM_VACIO);
          await onCambio();
        },
      },
    });
  }

  function pedirQuitarMovimiento(m: Movimiento) {
    setConfirmacion({
      donde: `quitar-${m.id}`,
      c: {
        texto: `¿Quitar el ${m.tipo} «${m.concepto}» de ${formatSoles(m.monto)}?`,
        textoBoton: "Quitar",
        peligro: true,
        accion: async () => {
          const { error } = await supabase.rpc("fn_quitar_movimiento", { p_movimiento_id: m.id });
          if (error) { avisar("error", mensajeDeError(error, "quitar el movimiento")); return; }
          avisar("ok", "Movimiento quitado.");
          await onCambio();
        },
      },
    });
  }

  // ── Ya le pagué aparte ──────────────────────────────────────────────────
  // No saca a la persona de la planilla: le pone un descuento por lo que ya
  // recibió, con la fecha escrita en el concepto. Dentro de un año «se le
  // descontó S/850 porque ya se le había pagado el 14/07» explica algo; «no
  // aparece en julio» parece un fallo.
  function pedirYaPagado() {
    const leido = parsearMontoSoles(yaPagado.monto);
    if (!leido.ok) { avisar("error", leido.motivo); return; }
    if (leido.monto <= 0) { avisar("error", "El monto tiene que ser mayor a 0."); return; }
    if (!yaPagado.fecha) { avisar("error", "Pon el día en que se le pagó."); return; }
    const fechaTexto = isoADiaMesAnio(yaPagado.fecha);
    const monto = leido.monto;
    setConfirmacion({
      donde: "ya-pagado",
      c: {
        texto: `¿Registrar que a ${f.nombre} ya se le pagaron ${formatSoles(monto)} el ${fechaTexto}? Queda como descuento en este periodo y en su boleta.`,
        textoBoton: "Registrar",
        accion: async () => {
          const { error } = await supabase.rpc("fn_agregar_movimiento", {
            p_periodo_id: periodoId,
            p_persona_id: f.persona_id,
            p_tipo: "descuento",
            p_concepto: `Ya pagado el ${fechaTexto} — fuera de planilla`,
            p_monto: monto,
            p_categoria: null,
          });
          if (error) { avisar("error", mensajeDeError(error, "registrar")); return; }
          avisar("ok", `Registrado: a ${f.nombre} ya se le habían pagado ${formatSoles(monto)} el ${fechaTexto}.`);
          setMostrandoYaPagado(false);
          await onCambio();
        },
      },
    });
  }

  // ── Adelanto de beneficio (0343) ────────────────────────────────────────
  // Escribe en desembolsos_beneficios, NO en movimientos_planilla: las truncas
  // lo restan solas al armar la liquidación.
  function pedirAdelanto() {
    const leido = parsearMontoSoles(adelanto.monto);
    if (!leido.ok) { avisar("error", leido.motivo); return; }
    if (leido.monto <= 0) { avisar("error", "El monto tiene que ser mayor a 0."); return; }
    // Ventana y año salen del periodo elegido, no del mes suelto: ver `periodoDelAdelanto`.
    const periodo = periodoAdelanto;
    if (!periodo) { avisar("error", "Pon el día en que se le paga."); return; }
    const monto = leido.monto;
    setConfirmacion({
      donde: "adelanto",
      c: {
        texto:
          `¿Registrar un adelanto de ${
            adelanto.beneficio === "subvencion_semestral"
              ? "media subvención"
              : adelanto.beneficio === "descanso_practicante"
                ? "descanso de 15 días"
                : CLASE_LABEL[adelanto.beneficio]
          } de ${formatSoles(monto)} para ${f.nombre}, pagado el ${isoADiaMesAnio(adelanto.fecha)}?\n` +
          `Se anota como ${nombreDelPeriodo(periodo)}: la liquidación lo va a restar de esa misma ventana.`,
        textoBoton: "Registrar adelanto",
        accion: async () => {
          const { error } = await supabase.rpc("fn_registrar_desembolso", {
            p_persona_id: f.persona_id,
            p_ventana: periodo.ventana,
            p_anio: periodo.anio,
            p_monto: monto,
            p_fecha_pago: adelanto.fecha,
            p_origen: "transferencia",
            p_nota: adelanto.nota.trim() || null,
          });
          if (error) { avisar("error", mensajeDeError(error, "registrar el adelanto")); return; }
          avisar("ok", `Adelanto de ${formatSoles(monto)} registrado. La liquidación lo va a restar sola cuando corresponda.`);
          setMostrandoAdelanto(false);
          setAdelanto(adelantoVacio(f.tipo_vinculo));
        },
      },
    });
  }

  // ── Básica legal (0103/0106) ────────────────────────────────────────────
  // Dato de la PERSONA, no del periodo. Hasta el 2026-09-15 se guardaba solo
  // al salir del campo en la tabla; ahora se guarda con un botón y se confirma,
  // porque cambia el desglose de sus boletas pasadas.
  function pedirBasica() {
    const n = Number(basica.trim());
    if (!basica.trim() || !Number.isFinite(n) || n <= 0) {
      avisar("error", "La básica legal debe ser un monto mayor que cero.");
      return;
    }
    if (n === f.sueldo_base_legal) return;
    setConfirmacion({
      donde: "basica",
      c: {
        texto: `¿Cambiar la básica legal de ${f.nombre} a ${formatSoles(n)}?\n\nEs un dato de su contrato: cambia cómo se parte el pago base en sus boletas, también las de periodos pasados que se vuelvan a calcular.`,
        textoBoton: "Guardar básica legal",
        accion: async () => {
          const { error } = await supabase.rpc("fn_set_sueldo_base_legal", { p_persona_id: f.persona_id, p_monto: n });
          if (error) { avisar("error", "No se pudo guardar la básica legal: " + mensajeDeError(error)); return; }
          avisar("ok", `Básica legal de ${f.nombre}: ${formatSoles(n)}.`);
          await onCambio();
        },
      },
    });
  }

  const conf = (donde: string) =>
    confirmacion?.donde === donde ? (
      <CajaConfirmar c={confirmacion.c} ocupado={ocupado} onCancelar={() => setConfirmacion(null)} onConfirmar={() => void ejecutar()} />
    ) : null;

  const rango = f.tipo_vinculo === "practicante" ? "Subvención"
    : f.en_planilla === false ? "Honorarios"
    : (f.rango && (RANGO_LABEL[f.rango] ?? f.rango)) ?? "Sin rango";

  return (
    <div className="space-y-5">
      {/* Quién es, en este periodo */}
      <div className="text-sm">
        <p className="text-taupe">
          {f.sede} · {TIPO_VINCULO_LABEL[grupoDe(f)]} · {rango}
          {f.salario_ref !== null ? ` · ${formatSoles(f.salario_ref)}` : ""}
        </p>
        <p className="mt-1 text-taupe">
          Ingresó el {fechaCorta(f.fecha_ingreso)} {f.fecha_ingreso.slice(0, 4)}
          {textoCese(cese) ? ` · ${textoCese(cese)}` : ""}
        </p>
        <Link
          href={`/admin/planilla/boleta?periodo=${periodoId}&persona=${f.persona_id}`}
          target="_blank"
          className="mt-2 inline-block text-sm text-taupe underline underline-offset-2 hover:text-tinta"
        >
          Ver boleta →
        </Link>
      </div>

      {pagado && (
        <p className="rounded-control bg-verde/10 px-3 py-2 text-sm text-verde">
          Pagado: lo que ves es la copia congelada del pago. {lock}
        </p>
      )}

      {hallazgos.length > 0 && (
        <Seccion titulo="Qué revisar">
          <ul className="space-y-2">
            {hallazgos.map((h) => (
              <li key={h.codigo} className="flex flex-wrap items-baseline gap-2 text-sm">
                <Insignia
                  variante={h.severidad === "bloquea" ? "alerta" : h.severidad === "revisar" ? "advertencia" : "neutral"}
                  tamano="sm"
                >
                  {h.severidad === "bloquea" ? "Frena el pago" : h.severidad === "revisar" ? "Revisar" : "Para saber"}
                </Insignia>
                <span>{h.texto}</span>
                {h.resolverEn && (
                  <Link href={h.resolverEn.href} className="text-xs text-taupe underline underline-offset-2 hover:text-tinta">
                    {h.resolverEn.etiqueta} →
                  </Link>
                )}
              </li>
            ))}
          </ul>
          {liquidada && liquidacionResuelta(f, liquidada) && (
            <p className="mt-2 text-xs text-taupe">
              ✓ Ya cobró su liquidación el {fechaCorta(liquidada.pagada_el)} ({formatSoles(liquidada.cobro_del_periodo)} de este mes) y ya está descontado aquí.
            </p>
          )}
        </Seccion>
      )}

      <Seccion titulo="Cómo se arma su total">
        <dl>
          {desglose.lineas.map((l) => (
            <div key={l.clave} className="flex justify-between gap-4 border-b border-sand/60 py-1.5 text-sm">
              <dt>
                {l.etiqueta}
                {l.origen && <span className="block text-xs text-taupe">{l.origen}</span>}
              </dt>
              <dd className="shrink-0 text-right tabular-nums">
                {l.signo < 0 ? "−" : ""}{formatSoles(l.monto)}
              </dd>
            </div>
          ))}
          <div className="flex justify-between gap-4 pt-2 text-base font-semibold">
            <dt>Total a transferir</dt>
            <dd className="tabular-nums">{formatSoles(f.total)}</dd>
          </div>
          {!desglose.cuadra && (
            <p className="mt-1 text-xs text-rojo-profundo">
              Las partidas suman {formatSoles(f.total - desglose.diferencia)}: hay {formatSoles(desglose.diferencia)} que esta
              lista no sabe explicar. Avisar antes de pagar.
            </p>
          )}
        </dl>
      </Seccion>

      <Seccion titulo="Horas y días">
        <dl>
          <Dato etiqueta="Horas registradas">{fmtHoras(f.horas_mes)}</Dato>
          <Dato etiqueta="Días trabajados / le tocaban">{f.dias_trabajados} / {f.dias_laborables}</Dato>
          {f.dias_pendientes > 0 && (
            <Dato etiqueta="Días con salida sin confirmar">
              <Link href="/admin/correcciones" className="underline underline-offset-2">{f.dias_pendientes} → Correcciones</Link>
            </Dato>
          )}
          {f.dias_vacaciones > 0 && <Dato etiqueta="Días de vacaciones">{f.dias_vacaciones}</Dato>}
          {(f.dias_descanso_medico_pagados ?? 0) > 0 && (
            <Dato etiqueta="Descanso médico pagado">
              {f.dias_descanso_medico_pagados} días · {formatSoles(f.monto_descanso_medico ?? 0)} (dentro del pago base)
            </Dato>
          )}
          {f.horas_sin_salario > 0 && <Dato etiqueta="Horas sin salario">{fmtHoras(f.horas_sin_salario)}</Dato>}
          {(f.horas_sobretiempo ?? 0) > 0 && (
            <Dato etiqueta="Sobretiempo">
              {fmtHoras(f.horas_sobretiempo ?? 0)}
              {f.horas_sobretiempo_25 != null && ` (25 %: ${f.horas_sobretiempo_25} h · 35 %: ${f.horas_sobretiempo_35 ?? 0} h)`}
            </Dato>
          )}
          {(f.descanso_semanal_dias ?? 0) > 0 && <Dato etiqueta="Descansos semanales trabajados">{f.descanso_semanal_dias}</Dato>}
        </dl>
        {f.feriados_detalle.length > 0 && (
          <ul className="mt-2 space-y-0.5 text-xs text-taupe">
            {f.feriados_detalle.map((d) => (
              <li key={d.fecha}>
                Feriado {fechaCorta(d.fecha)}:{" "}
                {d.antes_ingreso ? "no corresponde (anterior al ingreso)" : `${d.horas_trabajadas} h trabajadas + ${d.proporcional_horas} h proporcionales`}
              </li>
            ))}
          </ul>
        )}
      </Seccion>

      <Seccion titulo="Bonos y descuentos">
        {movs.length === 0 ? (
          <p className="text-sm text-taupe">Sin bonos ni descuentos en este periodo.</p>
        ) : (
          <ul className="space-y-1">
            {[...bonos, ...descuentos].map((m) => (
              <li key={m.id}>
                <div className="flex items-center justify-between gap-3 text-sm">
                  <span>
                    <span className="tabular-nums">{m.tipo === "bono" ? "+" : "−"}{formatSoles(m.monto)}</span>{" "}
                    <span className="text-taupe">({m.tipo})</span> {m.concepto}
                  </span>
                  <Boton
                    variante="enlace"
                    className="shrink-0 text-xs text-rojo"
                    onClick={() => pedirQuitarMovimiento(m)}
                    disabled={pagado || ocupado}
                    title={pagado ? lock : "Quitar"}
                  >
                    Quitar
                  </Boton>
                </div>
                {conf(`quitar-${m.id}`)}
              </li>
            ))}
          </ul>
        )}

        {pagado ? (
          <p className="mt-3 text-xs text-taupe">{lock}</p>
        ) : (
          <div className="mt-3 grid gap-2 rounded-control border border-sand p-3 sm:grid-cols-2">
            <CampoSelect etiqueta="Tipo" value={movForm.tipo} onChange={(e) => alCambiarTipo(e.target.value as ClaseMov)} disabled={ocupado}>
              <option value="bono">Bono</option>
              <option value="descuento">Descuento</option>
              <option value="vacaciones">Vacaciones</option>
              {/* Solo en el periodo que contiene la fecha de pago legal. */}
              {gc?.gratiAplica && <option value="gratificacion">{CLASE_LABEL.gratificacion}</option>}
              {gc?.gratiAplica && <option value="bonificacion_extraordinaria">{CLASE_LABEL.bonificacion_extraordinaria}</option>}
              {gc?.ctsAplica && <option value="cts">{CLASE_LABEL.cts}</option>}
              <option value="otros">Otros</option>
            </CampoSelect>
            <Campo
              etiqueta="Monto (S/)" type="number" min={0.01} step={0.01} value={movForm.monto}
              onChange={(e) => setMovForm({ ...movForm, monto: e.target.value })} placeholder="0.00" disabled={ocupado}
            />
            <div className="sm:col-span-2">
              <Campo
                etiqueta="Concepto" value={movForm.concepto}
                onChange={(e) => setMovForm({ ...movForm, concepto: e.target.value })}
                placeholder={CLASE_PLACEHOLDER[movForm.tipo]} disabled={ocupado}
              />
            </div>
            {/* 0305 — solo si HAY meses ya pagados antes de este. */}
            {origenes.length > 0 && (
              <div className="sm:col-span-2">
                <CampoSelect
                  etiqueta="¿Corrige un periodo anterior?" value={movForm.origen}
                  onChange={(e) => setMovForm({ ...movForm, origen: e.target.value })} disabled={ocupado}
                >
                  <option value="">No — es de este periodo</option>
                  {origenes.map((o) => <option key={o.id} value={o.id}>{o.etiqueta}</option>)}
                </CampoSelect>
              </div>
            )}
            <div className="flex justify-end sm:col-span-2">
              <Boton variante="primario" tamano="sm" onClick={pedirAgregarMovimiento} disabled={ocupado || confirmacion?.donde === "mov"}>
                Agregar
              </Boton>
            </div>
            <div className="sm:col-span-2">{conf("mov")}</div>
          </div>
        )}
      </Seccion>

      <Seccion titulo="Pagos fuera de la planilla">
        {!pagado && (f.total > 0 || liquidada) && (
          <div className="mb-3">
            {!mostrandoYaPagado ? (
              <Boton tamano="sm" onClick={() => setMostrandoYaPagado(true)}>Ya le pagué aparte…</Boton>
            ) : (
              <div className="rounded-control border border-sand p-3">
                <p className="mb-2 text-sm text-taupe">
                  Se registra como un descuento por lo que ya recibió: su total baja a cero (o a la diferencia) y en la
                  boleta queda escrito por qué.
                  {liquidada && ` Su liquidación del ${fechaCorta(liquidada.pagada_el)} ya le pagó ${formatSoles(liquidada.cobro_del_periodo)} de este mes; por eso viene propuesto ${formatSoles(sugeridoYaPagado)}.`}
                </p>
                <div className="flex flex-wrap items-end gap-2">
                  <Campo etiqueta="Monto (S/)" value={yaPagado.monto} onChange={(e) => setYaPagado({ ...yaPagado, monto: e.target.value })} className="w-32" />
                  <Campo etiqueta="Fecha de pago" type="date" value={yaPagado.fecha} onChange={(e) => setYaPagado({ ...yaPagado, fecha: e.target.value })} />
                  <Boton tamano="sm" onClick={() => setMostrandoYaPagado(false)}>Cancelar</Boton>
                  <Boton tamano="sm" variante="primario" onClick={pedirYaPagado} disabled={ocupado}>Registrar</Boton>
                </div>
                {conf("ya-pagado")}
              </div>
            )}
          </div>
        )}
        {!mostrandoAdelanto ? (
          <Boton tamano="sm" onClick={() => setMostrandoAdelanto(true)}>
            {f.tipo_vinculo === "practicante"
              ? "Adelanto de media subvención o descanso…"
              : "Adelanto de gratificación, CTS o vacaciones…"}
          </Boton>
        ) : (
          <div className="rounded-control border border-sand p-3">
            <p className="mb-2 text-sm text-taupe">
              Fuera del ciclo normal (típicamente a quien cesa a mitad de semestre). No toca este periodo: la liquidación lo resta sola.
            </p>
            <div className="flex flex-wrap items-end gap-2">
              {/* CAMBIO 0467 — a una practicante no le tocan gratificación, CTS
                  ni vacaciones (Ley 28518 art. 47), y sí sus dos pagos propios
                  (art. 42). Cada vínculo ve solo lo suyo: ofrecer los cinco a
                  todo el mundo es invitar a archivar un pago donde no va, que
                  es el defecto que este mismo formulario tenía con la CTS. */}
              <CampoSelect
                etiqueta="Beneficio" value={adelanto.beneficio}
                onChange={(e) => setAdelanto({ ...adelanto, beneficio: e.target.value as typeof adelanto.beneficio })}
              >
                {f.tipo_vinculo === "practicante" ? (
                  <>
                    <option value="subvencion_semestral">Media subvención (cada 6 meses)</option>
                    <option value="descanso_practicante">Descanso de 15 días</option>
                  </>
                ) : (
                  <>
                    <option value="gratificacion">Gratificación</option>
                    <option value="cts">CTS</option>
                    <option value="vacaciones">Vacaciones</option>
                  </>
                )}
              </CampoSelect>
              <Campo etiqueta="Monto (S/)" value={adelanto.monto} onChange={(e) => setAdelanto({ ...adelanto, monto: e.target.value })} className="w-32" />
              <Campo etiqueta="Fecha de pago" type="date" value={adelanto.fecha} onChange={(e) => setAdelanto({ ...adelanto, fecha: e.target.value })} />
              {!ES_DE_MODALIDAD_FORMATIVA.includes(adelanto.beneficio) &&
                adelanto.beneficio !== "vacaciones" && periodosDelAdelanto(adelanto) && (
                <CampoSelect
                  etiqueta="Periodo que se paga" value={adelanto.periodo}
                  onChange={(e) => setAdelanto({ ...adelanto, periodo: e.target.value as AdelantoForm["periodo"] })}
                >
                  <option value="actual">{nombreDelPeriodo(periodosDelAdelanto(adelanto)!.actual)}</option>
                  <option value="anterior">{nombreDelPeriodo(periodosDelAdelanto(adelanto)!.anterior)}</option>
                </CampoSelect>
              )}
            </div>
            {/* Lo que va a pasar, dicho antes de confirmar: la ventana es lo que
                decide de dónde lo resta la liquidación, y hasta el 2026-09-15 se
                equivocaba en silencio. */}
            {periodoAdelanto && (
              <p className="mt-2 text-sm text-taupe">
                Se anota como <strong className="font-medium text-tinta">{nombreDelPeriodo(periodoAdelanto)}</strong>
                {adelanto.beneficio === "vacaciones" ? "." : ": la liquidación lo va a restar de esa misma ventana."}
              </p>
            )}
            <label className="mt-2 flex flex-col gap-1 text-sm">
              <span className="text-taupe">Nota (opcional)</span>
              <AreaTexto value={adelanto.nota} onChange={(e) => setAdelanto({ ...adelanto, nota: e.target.value })} rows={2} placeholder="ej. el motivo del adelanto" />
            </label>
            <div className="mt-2 flex justify-end gap-2">
              <Boton tamano="sm" onClick={() => setMostrandoAdelanto(false)}>Cancelar</Boton>
              <Boton tamano="sm" variante="primario" onClick={pedirAdelanto} disabled={ocupado}>Registrar adelanto</Boton>
            </div>
            {conf("adelanto")}
          </div>
        )}
      </Seccion>

      <Seccion titulo="No entra en el total">
        <dl>
          <Dato etiqueta="Básica legal (PLAME)">{f.sueldo_base_legal != null ? formatSoles(f.sueldo_base_legal) : "—"}</Dato>
          {(f.aporte_essalud ?? 0) > 0 && (
            <Dato etiqueta="EsSalud (lo paga CAYLA)">
              {formatSoles(f.aporte_essalud ?? 0)}{f.essalud_es_piso ? " · sobre el piso de la RMV" : ""}
            </Dato>
          )}
          <Dato etiqueta="Provisión gratificación">{formatSoles(f.provision_gratificacion)}</Dato>
          <Dato etiqueta="Provisión CTS">{formatSoles(f.provision_cts)}</Dato>
          <Dato etiqueta="Provisión vacaciones">{formatSoles(f.provision_vacaciones)}</Dato>
        </dl>
        <div className="mt-3 flex flex-wrap items-end gap-2">
          <Campo
            etiqueta="Cambiar básica legal (S/)" type="number" min={0} step={10} value={basica}
            onChange={(e) => setBasica(e.target.value)} className="w-36" disabled={ocupado}
          />
          <Boton tamano="sm" onClick={pedirBasica} disabled={ocupado || basica.trim() === "" || Number(basica) === f.sueldo_base_legal}>
            Guardar
          </Boton>
        </div>
        {conf("basica")}
      </Seccion>
    </div>
  );
}

export function PanelPersona(props: {
  fila: Fila | null;
  onCerrar: () => void;
  volverElFocoA: RefObject<HTMLElement | null>;
  periodoId: string;
  pagado: boolean;
  liquidada: Liquidada | null;
  cese: Cese;
  hallazgos: Hallazgo[];
  gc: GratiCts | null;
  origenes: { id: string; etiqueta: string }[];
  supabase: Supabase;
  onCambio: () => Promise<void>;
}) {
  const { fila, onCerrar, volverElFocoA, ...resto } = props;
  return (
    <Drawer abierto={fila !== null} onCerrar={onCerrar} titulo={fila?.nombre} volverElFocoA={volverElFocoA} ancho="amplio">
      {/* La clave reinicia los formularios al cambiar de persona: un monto a medio
          escribir de Ana no puede quedar esperando en el panel de Bea. */}
      {fila && <Contenido key={fila.persona_id} fila={fila} {...resto} />}
    </Drawer>
  );
}

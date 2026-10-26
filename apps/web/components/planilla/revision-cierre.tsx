"use client";

// «Revisar cierre de <grupo>» — lo último que se ve antes de congelar un pago.
//
// Decisiones del 2026-09-15:
// - Pagar sigue siendo UNA operación (congela la foto y pone el candado); el
//   nombre cambia a lo que hace: «Confirmar pago y congelar».
// - Bloquea solo lo que la base ya frena (dos frenos). El resto son avisos que
//   piden marcar «los revisé» — no un checklist ítem por ítem, que con treinta
//   personas y doce meses se termina marcando sin mirar.
// - Si hay un periodo ANTERIOR sin pagar, se nombra y se pide aceptarlo. No se
//   bloquea: está permitido desde la 0323.
// - Pagar un periodo que TODAVÍA NO TERMINÓ —incluido el mismo día del cierre—
//   pide, además, escribir una palabra (2026-10-22). El 2026-10-21 se marcó
//   «pagado» el grupo planilla siete días antes del cierre con el mismo clic
//   que uno ya terminado, y desde ese instante sus marcas nuevas entraron
//   selladas sin recalcular horas. No se
//   bloquea —Felipe: a veces es una excepción legítima, una liquidación o un
//   practicante que se va—; se hace imposible hacerlo sin querer.
//
// Todo lo que muestra es del grupo COMPLETO, nunca de lo filtrado: es
// exactamente lo que `fn_periodo_pagado` va a congelar.

import { useState } from "react";
import { TIPO_VINCULO_LABEL, type TipoVinculo } from "@cayla-dynamic/shared";
import { formatSoles } from "@/lib/rangos";
import { Modal } from "@/components/ui/modal";
import { Boton } from "@/components/ui/boton";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Campo, CampoCasilla } from "@/components/ui/campo";
import { MESES_LARGO, fechaCorta, fechaLargaLima } from "@/lib/admin/planilla/formato";
import {
  PALABRA_PAGO_ADELANTADO, confirmaPagoAdelantado, diasQueFaltanParaTerminar, tituloAvisoPagoAdelantado,
} from "@/lib/admin/planilla/pago-adelantado";
import type { HallazgoAgrupado, Totales } from "@/lib/admin/planilla/revision";
import type { PeriodoInfo } from "@/lib/admin/planilla/tipos";

/** «Septiembre 2026», igual que la cabecera de la pantalla. */
function mesTitulo(p: Pick<PeriodoInfo, "mes_etiqueta" | "anio_etiqueta">): string {
  const mes = MESES_LARGO[p.mes_etiqueta - 1];
  return `${mes.charAt(0).toUpperCase()}${mes.slice(1)} ${p.anio_etiqueta}`;
}

export interface AnteriorPendiente {
  periodo: PeriodoInfo;
  /** Grupos con gente que siguen sin pagar en ese periodo; vacío si no se pudo saber. */
  faltan: TipoVinculo[];
}

function Contenido({
  grupo, periodo, hoy, totales, cesaron, hallazgos, anteriores, guardando, onCerrar, onConfirmar,
}: {
  grupo: TipoVinculo;
  periodo: PeriodoInfo;
  /** Hoy en Lima (`hoyLima()`), que decide si el periodo ya terminó. Llega de afuera para no recalcularlo aquí. */
  hoy: string;
  totales: Totales;
  cesaron: number;
  hallazgos: HallazgoAgrupado[];
  anteriores: AnteriorPendiente[];
  guardando: boolean;
  onCerrar: () => void;
  onConfirmar: () => void;
}) {
  const etiqueta = TIPO_VINCULO_LABEL[grupo];
  const frenan = hallazgos.filter((h) => h.severidad === "bloquea");
  const revisar = hallazgos.filter((h) => h.severidad === "revisar");
  const [revisados, setRevisados] = useState(false);
  const [anterioresAceptados, setAnterioresAceptados] = useState(false);
  const [palabra, setPalabra] = useState("");
  // null = el periodo ya terminó; 0 = hoy es el cierre (todavía no terminó); N = faltan N días.
  const diasQueFaltan = diasQueFaltanParaTerminar(periodo.fecha_fin, hoy);
  const listo = frenan.length === 0
    && (revisar.length === 0 || revisados)
    && (anteriores.length === 0 || anterioresAceptados)
    && (diasQueFaltan === null || confirmaPagoAdelantado(palabra));

  return (
    <div className="space-y-4 text-sm">
      <dl className="grid grid-cols-2 gap-x-6 gap-y-3 rounded-control bg-hueso p-4">
        <div className="col-span-2">
          <dt className="text-xs text-taupe">Periodo</dt>
          <dd className="font-medium">
            {mesTitulo(periodo)} · {fechaCorta(periodo.fecha_ini)} → {fechaCorta(periodo.fecha_fin)}
          </dd>
        </div>
        <div>
          <dt className="text-xs text-taupe">Grupo</dt>
          <dd className="font-medium">{etiqueta}</dd>
        </div>
        <div>
          <dt className="text-xs text-taupe">Personas</dt>
          <dd className="font-medium">
            {totales.personas}
            {cesaron > 0 && <span className="font-normal text-taupe"> · {cesaron} cesaron o están inactivas</span>}
          </dd>
        </div>
        <div>
          <dt className="text-xs text-taupe">Total a transferir</dt>
          <dd className="font-serif text-xl tabular-nums">{formatSoles(totales.total)}</dd>
        </div>
        <div>
          <dt className="text-xs text-taupe">Sale de la cuenta</dt>
          <dd className="tabular-nums">{formatSoles(totales.sale_del_banco)}</dd>
          <dd className="text-xs text-taupe">con pensión, EsSalud y 4ta</dd>
        </div>
        <div className="col-span-2">
          <dt className="text-xs text-taupe">Se registra</dt>
          <dd>{fechaLargaLima(new Date().toISOString())}, a tu nombre</dd>
        </div>
      </dl>

      {frenan.length > 0 && (
        <div className="rounded-control border border-rojo/30 bg-rojo/[0.05] p-3">
          <p className="font-medium text-rojo-profundo">Todavía no se puede pagar «{etiqueta}»</p>
          <ul className="mt-2 max-h-40 space-y-1 overflow-y-auto">
            {frenan.flatMap((h) => h.personas.map((p) => (
              <li key={`${h.codigo}-${p.persona_id}`}><span className="font-medium">{p.nombre}</span>: {p.texto}</li>
            )))}
          </ul>
          <p className="mt-2 text-xs text-taupe">
            La base no deja congelar con esto pendiente. Resuélvelo y vuelve: no se guarda nada a medias.
          </p>
        </div>
      )}

      {frenan.length === 0 && revisar.length > 0 && (
        <div className="rounded-control border border-ambar/40 bg-ambar/[0.07] p-3">
          <p className="font-medium text-ambar">Avisos de «{etiqueta}» ({revisar.reduce((a, h) => a + h.personas.length, 0)})</p>
          <ul className="mt-2 max-h-40 space-y-1 overflow-y-auto">
            {revisar.flatMap((h) => h.personas.map((p) => (
              <li key={`${h.codigo}-${p.persona_id}`}><span className="font-medium">{p.nombre}</span>: {p.texto}</li>
            )))}
          </ul>
          <div className="mt-3">
            <CampoCasilla etiqueta="Revisé estos avisos y el pago va igual" checked={revisados} onChange={(e) => setRevisados(e.target.checked)} />
          </div>
        </div>
      )}

      {frenan.length === 0 && anteriores.length > 0 && (
        <div className="rounded-control border border-ambar/40 bg-ambar/[0.07] p-3">
          <p className="font-medium text-ambar">
            {anteriores.length === 1 ? "Hay un periodo anterior sin pagar" : `Hay ${anteriores.length} periodos anteriores sin pagar`}
          </p>
          <ul className="mt-2 space-y-1">
            {anteriores.map((a) => (
              <li key={a.periodo.id}>
                {mesTitulo(a.periodo)}
                {a.faltan.length > 0 && <span className="text-taupe"> · falta: {a.faltan.map((g) => TIPO_VINCULO_LABEL[g]).join(", ")}</span>}
              </li>
            ))}
          </ul>
          <div className="mt-3">
            <CampoCasilla
              etiqueta={anteriores.length === 1 ? "Sé que ese periodo sigue sin pagar" : "Sé que esos periodos siguen sin pagar"}
              checked={anterioresAceptados}
              onChange={(e) => setAnterioresAceptados(e.target.checked)}
            />
          </div>
        </div>
      )}

      {frenan.length === 0 && diasQueFaltan !== null && (
        <BannerAviso variante="alerta" titulo={tituloAvisoPagoAdelantado(diasQueFaltan)}>
          <p>
            El periodo cierra {diasQueFaltan === 0 ? "hoy," : "el"} {fechaCorta(periodo.fecha_fin)}. Si confirmas ahora, desde este instante{" "}
            <strong>las marcas nuevas de «{etiqueta}» entrarán selladas</strong> y{" "}
            <strong>sus horas no se recalcularán</strong>: quien marque de aquí al cierre puede quedar con la
            jornada sin salida y sin horas, y ya no se podrá corregir sin reabrir el pago.
          </p>
          <p className="mt-2 text-taupe">
            Si es una excepción a propósito —por ejemplo una liquidación o un practicante que se va—, puedes seguir.
            Si fue un clic de más, cancela.
          </p>
          <div className="mt-3">
            <Campo
              etiqueta={`Para confirmar, escribe «${PALABRA_PAGO_ADELANTADO}»`}
              value={palabra}
              onChange={(e) => setPalabra(e.target.value)}
              autoComplete="off"
            />
          </div>
        </BannerAviso>
      )}

      <p className="text-xs text-taupe">
        Confirmar registra que ya se transfirió a estas {totales.personas} personas y congela su desglose: es la cifra que
        queda para contabilidad y ya no cambia sola. Si después hay que corregir, se reabre con motivo o se vuelve a
        pagar; la copia anterior se conserva. Los filtros de la pantalla no cambian quién entra.
      </p>

      <div className="flex flex-wrap justify-end gap-2">
        <Boton onClick={onCerrar} disabled={guardando}>Cancelar</Boton>
        <Boton variante="primario" onClick={onConfirmar} disabled={!listo} cargando={guardando}>
          Confirmar pago y congelar «{etiqueta}»
        </Boton>
      </div>
    </div>
  );
}

export function RevisionCierre(props: {
  grupo: TipoVinculo | null;
  periodo: PeriodoInfo;
  hoy: string;
  totales: Totales;
  cesaron: number;
  hallazgos: HallazgoAgrupado[];
  anteriores: AnteriorPendiente[];
  guardando: boolean;
  onCerrar: () => void;
  onConfirmar: () => void;
}) {
  const { grupo, ...resto } = props;
  return (
    <Modal
      abierto={grupo !== null}
      onCerrar={props.onCerrar}
      bloqueado={props.guardando}
      titulo={grupo ? `Revisar cierre de «${TIPO_VINCULO_LABEL[grupo]}»` : undefined}
      ancho="lg"
    >
      {/* La clave reinicia las casillas: lo revisado para Planilla no vale para Practicantes. */}
      {grupo && <Contenido key={`${props.periodo.id}-${grupo}`} grupo={grupo} {...resto} />}
    </Modal>
  );
}

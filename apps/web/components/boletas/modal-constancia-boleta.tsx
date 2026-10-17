"use client";

import { useEffect, useState } from "react";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { Modal } from "@/components/ui/modal";
import { Boton } from "@/components/ui/boton";
import { Cargando } from "@/components/cargando";
import { ConstanciaDeFirma, useConstancia } from "@/components/boletas/constancia-de-firma";
import { InsigniaDeEstado } from "@/components/boletas/insignia-de-estado";
import { PieDeModal, TACTIL } from "@/components/boletas/pie-de-modal";
import { VisorDeHojas } from "@/components/boletas/visor-de-hojas";
import { estadoVisible, tiempoParaRestablecer, type TipoBoleta } from "@/lib/boletas";
import { hojasFirmadasDeVersion, type HojaFirmada } from "@/lib/boletas-archivos";
import { fechaHoraLima, type FilaTablero } from "@/lib/admin/boletas-pantalla";

type Anulacion = {
  id: string;
  anulada_at: string;
  anulada_por: string;
  motivo: string;
  restablecida_at: string | null;
  restablecida_por: string | null;
};

/**
 * LA BOLETA CON SU CONSTANCIA, PARA DO (0532). Dos usos de la misma pieza:
 *
 *  · «Ver boleta firmada»: la boleta y, debajo, la firma que la persona copió en
 *    ella, quién y cuándo. Es lo que DO le muestra al contador si pide la prueba.
 *  · «Ver anulación»: lo que se anuló —la misma boleta y su constancia, que se
 *    conservan— con el motivo y el historial de anulaciones y restablecimientos.
 *
 * Nada de esto escribe en la base. Mirar la boleta de otra persona no marca nada
 * como «abierto» (`fn_boleta_partes`, 0482): DO revisando no es la persona
 * recibiendo.
 */
export function ModalConstanciaBoleta({
  supabase, modo, fila, nombreDelPeriodo, onCerrar, onAnular, onRestablecer,
}: {
  supabase: ClienteCayla;
  modo: "constancia" | "anulacion";
  fila: FilaTablero;
  nombreDelPeriodo: string;
  onCerrar: () => void;
  /** Solo en «constancia»: abre el modal de anular sobre esta boleta. */
  onAnular?: () => void;
  /** Solo en «anulación», mientras corre el plazo. */
  onRestablecer?: () => void;
}) {
  const { constancia, error: errorConstancia } = useConstancia(supabase, fila.version_id);
  const [hojas, setHojas] = useState<HojaFirmada[] | null>(null);
  const [errorHojas, setErrorHojas] = useState<string | null>(null);
  const [anulaciones, setAnulaciones] = useState<Anulacion[] | null>(null);

  useEffect(() => {
    if (!fila.version_id) return;
    let vigente = true;
    void hojasFirmadasDeVersion(supabase, fila.version_id, 900).then((r) => {
      if (!vigente) return;
      setErrorHojas(r.error);
      setHojas(r.error ? null : r.hojas);
    });
    return () => { vigente = false; };
  }, [supabase, fila.version_id]);

  useEffect(() => {
    if (modo !== "anulacion" || !fila.boleta_id) return;
    let vigente = true;
    void supabase.rpc("fn_boleta_anulaciones", { p_boleta_id: fila.boleta_id }).then(({ data }) => {
      if (vigente) setAnulaciones((data ?? []) as Anulacion[]);
    });
    return () => { vigente = false; };
  }, [supabase, modo, fila.boleta_id]);

  const titulo = modo === "constancia" ? "Boleta firmada" : "Boleta anulada";
  const queda = tiempoParaRestablecer(fila.restablecible_hasta);

  return (
    <Modal abierto onCerrar={onCerrar} titulo={titulo} ancho="xl">
      <div className="mb-3 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm">
        <b className="font-medium text-tinta">{fila.nombre}</b>
        <span className="text-taupe">{fila.sede_codigo} · {nombreDelPeriodo}</span>
        <InsigniaDeEstado estado={estadoVisible(fila)} />
      </div>

      {modo === "anulacion" && (
        <div className="mb-4 space-y-3">
          <dl className="grid grid-cols-2 gap-x-4 gap-y-3 rounded-xl border border-sand bg-hueso p-4 text-sm">
            <div><dt className="text-xs uppercase tracking-wide text-taupe">Anulada</dt><dd className="font-medium text-tinta">{fechaHoraLima(fila.anulada_at)}</dd></div>
            <div>
              <dt className="text-xs uppercase tracking-wide text-taupe">Se puede restablecer</dt>
              <dd className="font-medium text-tinta">{queda ? `Sí: quedan ${queda}` : "No: venció el plazo de 48 horas"}</dd>
            </div>
            <div className="col-span-2"><dt className="text-xs uppercase tracking-wide text-taupe">Motivo</dt><dd className="font-medium text-tinta">{fila.anulada_motivo ?? "—"}</dd></div>
          </dl>
          {anulaciones === null ? (
            <Cargando texto="Trayendo el historial…" />
          ) : (anulaciones.length > 1 || anulaciones.some((x) => x.restablecida_at)) && (
            <ul className="space-y-2 text-sm">
              {anulaciones.map((a) => (
                <li key={a.id} className="rounded-xl border border-sand px-4 py-2">
                  <p className="text-tinta">Anulada por {a.anulada_por} · {fechaHoraLima(a.anulada_at)}</p>
                  <p className="text-xs text-taupe">{a.motivo}</p>
                  {a.restablecida_at && (
                    <p className="mt-1 text-xs text-verde">Restablecida por {a.restablecida_por} · {fechaHoraLima(a.restablecida_at)}</p>
                  )}
                </li>
              ))}
            </ul>
          )}
        </div>
      )}

      {fila.version_id ? (
        <>
          <p className="mb-1 text-xs font-medium uppercase tracking-wide text-taupe">
            {modo === "anulacion" ? "Lo que se anuló" : "La boleta"}
          </p>
          {errorHojas ? (
            <p role="alert" className="rounded-control bg-rojo/10 px-3 py-2 text-sm text-rojo-profundo">{errorHojas}</p>
          ) : hojas === null ? (
            <Cargando texto="Abriendo la boleta…" />
          ) : (
            <VisorDeHojas hojas={hojas} tipo={(fila.tipo ?? "imagen") as TipoBoleta} />
          )}
          <div className="mt-4">
            <ConstanciaDeFirma nombre={fila.nombre} constancia={constancia} error={errorConstancia} />
          </div>
        </>
      ) : (
        <p className="text-sm text-taupe">Esta boleta no tiene hojas guardadas.</p>
      )}

      <PieDeModal>
        <Boton className={TACTIL} onClick={onCerrar}>Cerrar</Boton>
        {modo === "constancia" && onAnular && (
          <Boton variante="peligro" className={TACTIL} onClick={onAnular}>Anular</Boton>
        )}
        {modo === "anulacion" && onRestablecer && (
          <Boton variante="primario" className={TACTIL} onClick={onRestablecer}>Restablecer</Boton>
        )}
      </PieDeModal>
    </Modal>
  );
}

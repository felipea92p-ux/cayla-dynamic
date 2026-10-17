"use client";

import { useState } from "react";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { Modal } from "@/components/ui/modal";
import { Boton } from "@/components/ui/boton";
import { useToast } from "@/components/toast";
import { PieDeModal, TACTIL } from "@/components/boletas/pie-de-modal";
import { tiempoParaRestablecer } from "@/lib/boletas";
import { fechaHoraLima, type FilaTablero } from "@/lib/admin/boletas-pantalla";
import { mensajeDeError } from "@/lib/admin/mensaje-error";

/**
 * RESTABLECER UNA ANULACIÓN (0532), mientras corren las 48 horas.
 *
 * La boleta vuelve EXACTAMENTE como estaba: el mismo estado, las mismas hojas y,
 * si ya estaba firmada, su misma firma —el acuse cuelga de la versión y anular
 * no lo tocó—. La persona no tiene que firmar otra vez. Queda anotado en el
 * historial que se anuló y que se restableció.
 *
 * El plazo lo mide la base con su reloj: si se venció mientras este modal estaba
 * abierto, `fn_boleta_restablecer` contesta con un mensaje que dice qué hacer
 * (subir una boleta nueva), y aquí se muestra tal cual.
 */
export function ModalRestablecerBoleta({
  supabase, fila, nombreDelPeriodo, onCerrar, onRestablecida,
}: {
  supabase: ClienteCayla;
  fila: FilaTablero;
  nombreDelPeriodo: string;
  onCerrar: () => void;
  onRestablecida: () => void;
}) {
  const { avisar } = useToast();
  const [error, setError] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);
  const nombre = fila.nombre.split(" ")[0];

  async function restablecer() {
    if (fila.boleta_id === null) return;
    setError(null);
    setEnviando(true);
    const { error: e } = await supabase.rpc("fn_boleta_restablecer", { p_boleta_id: fila.boleta_id });
    if (e) { setEnviando(false); setError(mensajeDeError(e)); return; }
    avisar("ok", `Boleta restablecida: ${nombre} la vuelve a ver.`);
    onRestablecida();
  }

  return (
    <Modal abierto onCerrar={onCerrar} titulo="Restablecer boleta" ancho="md" bloqueado={enviando}>
      <p className="text-sm text-tinta">
        ¿Restablecer la boleta de <b className="font-medium">{fila.nombre}</b> · {nombreDelPeriodo}?
      </p>

      <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-3 rounded-xl border border-sand bg-hueso p-4 text-sm">
        <div><dt className="text-xs uppercase tracking-wide text-taupe">Se anuló</dt><dd className="font-medium text-tinta">{fechaHoraLima(fila.anulada_at)}</dd></div>
        <div><dt className="text-xs uppercase tracking-wide text-taupe">Quedan para restablecer</dt><dd className="font-medium text-tinta">{tiempoParaRestablecer(fila.restablecible_hasta) || "—"}</dd></div>
        <div className="col-span-2"><dt className="text-xs uppercase tracking-wide text-taupe">Motivo de la anulación</dt><dd className="font-medium text-tinta">{fila.anulada_motivo ?? "—"}</dd></div>
      </dl>

      <p className="mt-3 rounded-xl border border-sand px-4 py-3 text-sm text-tinta">
        Vuelve exactamente como estaba{fila.firmada ? ", con su firma intacta" : ""}. {nombre} la vuelve a ver en «Lo mío».
        Queda anotado en el historial que se anuló y que se restableció.
      </p>

      {error && <p role="alert" className="mt-3 rounded-control bg-rojo/10 px-3 py-2 text-sm text-rojo-profundo">{error}</p>}
      <PieDeModal>
        <Boton className={TACTIL} disabled={enviando} onClick={onCerrar}>Volver</Boton>
        <Boton variante="primario" className={TACTIL} cargando={enviando} onClick={() => void restablecer()}>
          {enviando ? "Restableciendo…" : "Restablecer boleta"}
        </Boton>
      </PieDeModal>
    </Modal>
  );
}

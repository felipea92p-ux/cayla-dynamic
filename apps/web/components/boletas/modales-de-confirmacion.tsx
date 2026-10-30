"use client";

import { useState } from "react";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { Modal } from "@/components/ui/modal";
import { Boton } from "@/components/ui/boton";
import { useToast } from "@/components/toast";
import { PieDeModal, TACTIL } from "@/components/boletas/pie-de-modal";
import type { FilaTablero } from "@/lib/admin/boletas-pantalla";
import { mensajeDeError } from "@/lib/admin/mensaje-error";

/**
 * ANOTAR QUE SE ENTREGÓ EN PAPEL, para quien no tiene cuenta y no puede abrir su
 * boleta en el sistema. Deja la constancia de la entrega; no sube ningún archivo.
 * Se pide confirmar porque esta pantalla no ofrece deshacerlo.
 */
export function ModalMarcarPapel({
  supabase, fila, periodoId, nombreDelPeriodo, onCerrar, onMarcada,
}: {
  supabase: ClienteCayla;
  fila: FilaTablero;
  periodoId: string;
  nombreDelPeriodo: string;
  onCerrar: () => void;
  onMarcada: () => void;
}) {
  const { avisar } = useToast();
  const [error, setError] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);

  async function marcar() {
    setError(null);
    setEnviando(true);
    const { error: e } = await supabase.rpc("fn_boleta_marcar_papel", { p_periodo_id: periodoId, p_persona_id: fila.persona_id });
    if (e) { setEnviando(false); setError(mensajeDeError(e)); return; }
    avisar("ok", `Anotado: la boleta de ${fila.nombre} se entregó en papel.`);
    onMarcada();
  }

  return (
    <Modal abierto onCerrar={onCerrar} titulo="Entregada en papel" ancho="sm" bloqueado={enviando}>
      <p className="text-sm text-tinta">
        ¿Le entregaste a <b className="font-medium">{fila.nombre}</b> su boleta impresa de {nombreDelPeriodo}?
      </p>
      <p className="mt-2 text-sm text-taupe">
        Queda anotado con tu nombre y la fecha de hoy. Úsalo solo si ya se la diste.
      </p>
      {error && <p role="alert" className="mt-3 rounded-control bg-rojo/10 px-3 py-2 text-sm text-rojo-profundo">{error}</p>}
      <PieDeModal>
        <Boton className={TACTIL} disabled={enviando} onClick={onCerrar}>Todavía no</Boton>
        <Boton variante="primario" className={TACTIL} cargando={enviando} onClick={() => void marcar()}>
          {enviando ? "Anotando…" : "Sí, se la entregué"}
        </Boton>
      </PieDeModal>
    </Modal>
  );
}

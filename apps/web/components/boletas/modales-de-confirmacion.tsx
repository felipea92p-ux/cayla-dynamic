"use client";

import { useState } from "react";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { Modal } from "@/components/ui/modal";
import { Boton } from "@/components/ui/boton";
import { AreaTexto } from "@/components/ui/area-texto";
import { useToast } from "@/components/toast";
import { PieDeModal, TACTIL } from "@/components/boletas/pie-de-modal";
import type { FilaTablero } from "@/lib/admin/boletas-pantalla";
import { mensajeDeError } from "@/lib/admin/mensaje-error";

/**
 * ANULAR UNA BOLETA PUBLICADA.
 *
 * Exige el motivo (al menos 5 letras, igual que la base): queda anotado junto a
 * la boleta y en la auditoría. Los archivos se conservan — anular retira la
 * boleta de la vista de la persona, no borra lo que se subió.
 */
export function ModalAnularBoleta({
  supabase, fila, nombreDelPeriodo, onCerrar, onAnulada,
}: {
  supabase: ClienteCayla;
  fila: FilaTablero;
  nombreDelPeriodo: string;
  onCerrar: () => void;
  onAnulada: () => void;
}) {
  const { avisar } = useToast();
  const [motivo, setMotivo] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);

  async function anular() {
    if (fila.boleta_id === null) return;
    if (motivo.trim().length < 5) {
      setError("Escribe el motivo (al menos 5 letras): queda anotado junto a la boleta.");
      return;
    }
    setError(null);
    setEnviando(true);
    const { error: e } = await supabase.rpc("fn_boleta_anular", { p_boleta_id: fila.boleta_id, p_motivo: motivo.trim() });
    if (e) { setEnviando(false); setError(mensajeDeError(e)); return; }
    avisar("ok", `Boleta de ${fila.nombre} anulada. Ya no la ve.`);
    onAnulada();
  }

  return (
    <Modal abierto onCerrar={onCerrar} titulo="Anular boleta" ancho="md" bloqueado={enviando}>
      <p className="mb-3 text-sm text-tinta">
        Boleta de <b className="font-medium">{fila.nombre}</b> · {nombreDelPeriodo}.
        La persona dejará de verla. Los archivos se conservan en el historial, junto con tu motivo.
      </p>
      <AreaTexto
        etiqueta="Motivo"
        rows={3}
        value={motivo}
        disabled={enviando}
        placeholder="Por ejemplo: se subió la boleta de otra persona"
        onChange={(e) => { setMotivo(e.target.value); setError(null); }}
      />
      {error && <p role="alert" className="mt-3 rounded-control bg-rojo/10 px-3 py-2 text-sm text-rojo-profundo">{error}</p>}
      <PieDeModal>
        <Boton className={TACTIL} disabled={enviando} onClick={onCerrar}>Cancelar</Boton>
        <Boton variante="peligro" className={TACTIL} cargando={enviando} onClick={() => void anular()}>
          {enviando ? "Anulando…" : "Anular boleta"}
        </Boton>
      </PieDeModal>
    </Modal>
  );
}

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

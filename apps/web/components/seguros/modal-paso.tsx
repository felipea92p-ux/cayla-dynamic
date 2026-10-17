"use client";

// ============================================================================
// Marcar un paso como hecho, o quitarle la marca
// ============================================================================
// QUÉ PROMETE
//   Un solo diálogo para todo lo que en Seguros se marca con una fecha: los tres
//   pasos del papeleo de una póliza (prima, firma, factura) y los dos de un cambio
//   de seguro (la baja del anterior, el alta del nuevo). Marcar pide la fecha en que
//   se hizo; quitar la marca pide el motivo, porque desmarcar algo hecho es lo que
//   más conviene que quede escrito.
//
// LA FECHA NACE EN HOY (CLAUDE.md, regla del 2026-08-26): un campo de fecha que
//   bloquea el envío no puede arrancar vacío. Si el paso ya tenía fecha, arranca en
//   esa, para corregirla.
//
// QUÉ NO HACE
//   No sabe qué función de la base llamar: `onConfirmar` la llama y devuelve el
//   mensaje de error, o null si salió bien (y entonces quien lo abrió lo cierra).
// ============================================================================

import { useState } from "react";
import { AreaTexto } from "@/components/ui/area-texto";
import { Boton } from "@/components/ui/boton";
import { Campo } from "@/components/ui/campo";
import { Modal } from "@/components/ui/modal";

export interface PasoPorMarcar {
  /** Qué se está marcando, ya con a quién y en qué póliza o cambio: «Prima pagada — póliza 24043267 de Ana Prueba». */
  detalle: string;
  /** true: quitar la marca (pide motivo). false: marcar o cambiar la fecha (pide fecha). */
  quitar: boolean;
  /** La fecha que ya tenía el paso, si tenía. */
  fechaActual: string | null;
  /** Para el motivo, cuando se quita: un ejemplo de qué escribir. */
  ejemploDeMotivo: string;
}

export function ModalPaso({
  paso, hoy, onCerrar, onConfirmar,
}: {
  paso: PasoPorMarcar | null;
  hoy: string;
  onCerrar: () => void;
  /** Llama a la base. Devuelve el mensaje de error, o null si salió bien. */
  onConfirmar: (fecha: string | null, motivo: string) => Promise<string | null>;
}) {
  const [ocupado, setOcupado] = useState(false);
  return (
    <Modal
      abierto={paso !== null}
      onCerrar={() => { if (!ocupado) onCerrar(); }}
      bloqueado={ocupado}
      titulo={paso ? (paso.quitar ? "Quitar la marca" : "Marcar como hecho") : undefined}
      ancho="sm"
    >
      {/* Se monta de nuevo cada vez que se abre: así nace con la fecha de ESE paso, sin un efecto que la copie. */}
      {paso && <Cuerpo paso={paso} hoy={hoy} onCerrar={onCerrar} onConfirmar={onConfirmar} onOcupado={setOcupado} />}
    </Modal>
  );
}

function Cuerpo({
  paso, hoy, onCerrar, onConfirmar, onOcupado,
}: {
  paso: PasoPorMarcar;
  hoy: string;
  onCerrar: () => void;
  onConfirmar: (fecha: string | null, motivo: string) => Promise<string | null>;
  onOcupado: (ocupado: boolean) => void;
}) {
  const [fecha, setFecha] = useState(paso.fechaActual ?? hoy);
  const [motivo, setMotivo] = useState("");
  const [mensaje, setMensaje] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  async function confirmar() {
    if (paso.quitar && motivo.trim().length < 5) { setMensaje("Escribe el motivo (al menos 5 letras)."); return; }
    if (!paso.quitar && !fecha) { setMensaje("Falta la fecha."); return; }
    setOcupado(true); onOcupado(true);
    const error = await onConfirmar(paso.quitar ? null : fecha, motivo.trim());
    setOcupado(false); onOcupado(false);
    if (error) setMensaje(error);
  }

  return (
    <>
      <p className="mb-3 text-sm text-taupe">{paso.detalle}</p>
      {paso.quitar ? (
        <label className="flex flex-col gap-1">
          <span className="text-sm text-taupe">Por qué se quita la marca</span>
          <AreaTexto
            value={motivo}
            onChange={(e) => { setMotivo(e.target.value); setMensaje(null); }}
            placeholder={paso.ejemploDeMotivo}
            className={mensaje ? "border-rojo" : undefined}
          />
          {mensaje && <span className="text-xs text-rojo">{mensaje}</span>}
        </label>
      ) : (
        <Campo
          etiqueta="Fecha en que se hizo"
          type="date" value={fecha} max={hoy}
          onChange={(e) => { setFecha(e.target.value); setMensaje(null); }}
          error={mensaje ?? undefined}
        />
      )}
      <div className="mt-4 flex justify-end gap-2">
        <Boton onClick={onCerrar} disabled={ocupado}>Cancelar</Boton>
        <Boton variante={paso.quitar ? "peligro" : "primario"} onClick={() => void confirmar()} cargando={ocupado}>
          {paso.quitar ? "Sí, quitar la marca" : "Guardar"}
        </Boton>
      </div>
    </>
  );
}

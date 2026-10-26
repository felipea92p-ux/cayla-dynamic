"use client";

import { useEffect, useMemo, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import type { MotivoRechazo } from "@cayla-dynamic/shared";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { fechaCorta } from "@/lib/educacion";
import type { Entrega } from "@/lib/admin/educacion-tipos";
import { Boton } from "@/components/ui/boton";
import { Modal } from "@/components/ui/modal";
import { rechazoIncompleto } from "@/lib/admin/educacion-ciclo";
import { CamposDeRechazo } from "./campos-de-rechazo";

/**
 * APROBAR O RECHAZAR UNA CONSTANCIA — los dos botones y sus dos confirmaciones.
 *
 * PROMETE: llamar a `fn_educacion_resolver_entrega`, la misma función de siempre,
 *   y avisar a quien lo usa con `onResuelta` cuando la base contestó que sí.
 * ASUME: la base decide quién puede revisar; acá solo se esconde el botón a
 *   quien revisaría su propia constancia (la base también lo impide).
 * NO HACE: no cambia lo que se paga. Aprobar o rechazar es una alerta, no un
 *   descuento (decisión «solo alerta», 2026-09-15).
 *
 * Vivía dentro del panel de cada estudio. Se sacó cuando apareció el visor
 * grande, que también aprueba y rechaza: dos copias de «qué se le dice a la
 * integrante al rechazar» es exactamente lo que acaba contradiciéndose.
 */
export function AccionesRevision({
  entrega, persona, esPropia, onResuelta, onError, onOcupado,
}: {
  entrega: Entrega;
  /** Para los textos de confirmación («Pago del … de Ana»). */
  persona: string;
  esPropia: boolean;
  onResuelta: (texto: string) => void | Promise<void>;
  onError: (texto: string) => void;
  /** Avisa cuando hay una confirmación abierta o trabajando: el visor suspende Esc y las flechas. */
  onOcupado?: (ocupado: boolean) => void;
}) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const [aprobando, setAprobando] = useState(false);
  const [rechazando, setRechazando] = useState(false);
  const [trabajando, setTrabajando] = useState(false);
  const [categoria, setCategoria] = useState<MotivoRechazo | "">("");
  const [comentario, setComentario] = useState("");

  const ocupado = aprobando || rechazando || trabajando;
  useEffect(() => { onOcupado?.(ocupado); }, [ocupado, onOcupado]);
  // Si el visor se desmonta con una confirmación abierta, no le queda ocupado colgado.
  useEffect(() => () => onOcupado?.(false), [onOcupado]);

  async function aprobar() {
    setTrabajando(true);
    const { error } = await supabase.rpc("fn_educacion_resolver_entrega", { p_id: entrega.id, p_aprobar: true });
    setTrabajando(false);
    if (error) { onError(mensajeDeError(error, "aprobar la constancia")); return; }
    setAprobando(false);
    await onResuelta(`Constancia de ${persona} aprobada.`);
  }

  async function rechazar() {
    const falta = rechazoIncompleto(categoria, comentario);
    if (falta) { onError(falta); return; }
    setTrabajando(true);
    const { error } = await supabase.rpc("fn_educacion_resolver_entrega", {
      p_id: entrega.id, p_aprobar: false, p_categoria: categoria, p_comentario: comentario.trim(),
    });
    setTrabajando(false);
    if (error) { onError(mensajeDeError(error, "rechazar la constancia")); return; }
    setRechazando(false); setCategoria(""); setComentario("");
    await onResuelta(`Constancia de ${persona} rechazada. Le llega el motivo en su Bandeja.`);
  }

  return (
    <>
      {esPropia ? (
        <p className="text-xs text-taupe">Es tu propia constancia: la revisa otra persona de Desarrollo Organizacional.</p>
      ) : (
        <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <Boton variante="peligro" onClick={() => setRechazando(true)}>Rechazar</Boton>
          <Boton variante="primario" onClick={() => setAprobando(true)}>Aprobar</Boton>
        </div>
      )}

      <Modal abierto={aprobando} onCerrar={() => setAprobando(false)} bloqueado={trabajando} titulo="¿Aprobar esta constancia?" ancho="sm">
        <p className="mb-4 text-sm text-taupe">
          Pago del {fechaCorta(entrega.fecha_pago)} de {persona}. Queda registrado que la aprobaste hoy, y su próximo
          pago pasa a {entrega.proxima_fecha_pago ? `el ${fechaCorta(entrega.proxima_fecha_pago)}` : "sin fecha"}.
        </p>
        <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <Boton onClick={() => setAprobando(false)} disabled={trabajando}>Cancelar</Boton>
          <Boton variante="primario" cargando={trabajando} onClick={() => void aprobar()}>Aprobar</Boton>
        </div>
      </Modal>

      <Modal abierto={rechazando} onCerrar={() => setRechazando(false)} bloqueado={trabajando} titulo="Rechazar constancia" ancho="md">
        <p className="mb-3 text-sm text-taupe">{persona} va a leer el motivo y el comentario en su Bandeja, para corregirla.</p>
        <CamposDeRechazo categoria={categoria} onCategoria={setCategoria} comentario={comentario} onComentario={setComentario} />
        <div className="mt-4 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <Boton onClick={() => setRechazando(false)} disabled={trabajando}>Cancelar</Boton>
          <Boton variante="peligro" cargando={trabajando} onClick={() => void rechazar()}
            disabled={rechazoIncompleto(categoria, comentario) !== null}>Rechazar constancia</Boton>
        </div>
      </Modal>
    </>
  );
}

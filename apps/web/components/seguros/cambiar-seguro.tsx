"use client";

// ============================================================================
// Cambiar el seguro de una persona
// ============================================================================
// QUÉ PROMETE
//   Que DO pueda decir «esta persona, desde tal fecha, está en tal seguro» cuando
//   lo que le toca por su vínculo no es lo que tiene en la realidad (un convenio, un
//   plan que contrató por su cuenta, un seguro que todavía no existe para su vínculo).
//   «Automático por vínculo; DO lo cambia por persona» (Felipe, 2026-10-17).
//
//   Si elige el seguro que le tocaría por su vínculo, el diálogo no crea una asignación
//   —la dejaría fija en ese seguro y sin seguir más a su vínculo—: termina la que
//   tenía, que es lo que la base pide para ese caso («volver al automático»).
//
// QUÉ NO HACE
//   No decide cuál le toca por su vínculo (lo dice la base en `automatico`), ni si el
//   cambio es válido (la persona activa, el seguro principal y vigente, la fecha no
//   futura): el mensaje de la base se muestra tal cual. Tampoco avisa a la aseguradora
//   ni al contador: deja DOS pendientes —la baja del anterior, el alta del nuevo— que
//   se cierran en la tarjeta de la persona y se ven en la Bandeja.
//
// LA FECHA NACE EN HOY (CLAUDE.md, regla del 2026-08-26), y no puede ser futura.
// ============================================================================

import { useState } from "react";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { AreaTexto } from "@/components/ui/area-texto";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { Modal } from "@/components/ui/modal";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { isoADiaMesAnio } from "@/lib/admin/planilla/formato";
import type { SeguroDePersona, TipoSeguro } from "@/lib/admin/seguros";

export function CambiarSeguro({
  persona, tipos, supabase, hoy, onCerrar, onListo,
}: {
  /** A quién se le cambia el seguro, o null si el diálogo está cerrado. */
  persona: SeguroDePersona | null;
  tipos: TipoSeguro[];
  supabase: ClienteCayla;
  hoy: string;
  onCerrar: () => void;
  /** Recibe la frase para el aviso de «listo». Quien lo abrió recarga la lista. */
  onListo: (mensaje: string) => void;
}) {
  const [ocupado, setOcupado] = useState(false);
  return (
    <Modal
      abierto={persona !== null}
      onCerrar={() => { if (!ocupado) onCerrar(); }}
      bloqueado={ocupado}
      titulo={persona ? `Cambiar el seguro de ${persona.persona}` : undefined}
      ancho="md"
    >
      {/* Se monta de nuevo cada vez que se abre: así nace con los datos de ESA persona. */}
      {persona && <Cuerpo persona={persona} tipos={tipos} supabase={supabase} hoy={hoy} onCerrar={onCerrar} onListo={onListo} onOcupado={setOcupado} />}
    </Modal>
  );
}

function Cuerpo({
  persona, tipos, supabase, hoy, onCerrar, onListo, onOcupado,
}: {
  persona: SeguroDePersona;
  tipos: TipoSeguro[];
  supabase: ClienteCayla;
  hoy: string;
  onCerrar: () => void;
  onListo: (mensaje: string) => void;
  onOcupado: (ocupado: boolean) => void;
}) {
  // A qué otro seguro puede pasar: los principales y vivos, menos el que ya tiene.
  const opciones = tipos.filter((t) => t.principal && t.activo && t.clave !== persona.tipo?.clave);
  const [tipo, setTipo] = useState(opciones.length === 1 ? opciones[0].clave : "");
  const [desde, setDesde] = useState(hoy);
  const [motivo, setMotivo] = useState("");
  const [intento, setIntento] = useState(false);
  const [mensaje, setMensaje] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const vuelveAlAutomatico = persona.asignacion !== null && tipo !== "" && tipo === persona.automatico?.clave;
  const errores = {
    tipo: tipo === "" ? "Elige el seguro." : undefined,
    desde: !desde ? "Falta la fecha desde la que rige." : undefined,
    motivo: motivo.trim().length < 5 ? "Escribe el motivo (al menos 5 letras): queda en el historial de su seguro." : undefined,
  };
  const hayErrores = Object.values(errores).some(Boolean);
  const ver = <K extends keyof typeof errores>(k: K) => (intento ? errores[k] : undefined);

  async function guardar() {
    setIntento(true); setMensaje(null);
    if (hayErrores) return;
    setOcupado(true); onOcupado(true);
    const { error } = vuelveAlAutomatico
      ? await supabase.rpc("fn_seguro_volver_al_automatico", { p_asignacion_id: persona.asignacion!.id, p_hasta: desde, p_motivo: motivo.trim() })
      : await supabase.rpc("fn_seguro_asignar", { p_persona_id: persona.personaId, p_tipo: tipo, p_desde: desde, p_motivo: motivo.trim() });
    setOcupado(false); onOcupado(false);
    if (error) { setMensaje(mensajeDeError(error, "guardar")); return; }
    const nuevo = opciones.find((t) => t.clave === tipo)?.nombre ?? "el seguro nuevo";
    onListo(`${persona.persona} pasa a ${nuevo}. Quedaron pendientes la baja del anterior y el alta del nuevo.`);
  }

  return (
    <>
      <p className="mb-3 text-sm text-taupe">
        Hoy está en <span className="text-tinta">{persona.tipo?.nombre ?? "ningún seguro"}</span>
        {persona.origen === "asignacion" && persona.asignacion
          ? <> — lo asignó DO desde el {isoADiaMesAnio(persona.asignacion.desde)}: «{persona.asignacion.motivo}».</>
          : persona.tipo ? <> — el que le toca por su vínculo.</> : <> — su vínculo no lleva un seguro de la empresa.</>}
      </p>

      {opciones.length === 0 ? (
        <p className="rounded-lg bg-hueso px-3 py-2 text-sm text-taupe">
          No hay otro seguro principal al que pasarla. Si tiene uno que el sistema no conoce, agrégalo desde «Tipos de seguro».
        </p>
      ) : (
        <>
          {mensaje && <p role="alert" className="mb-3 rounded border border-rojo/30 bg-rojo/10 px-3 py-2 text-sm text-rojo">{mensaje}</p>}
          <div className="space-y-3">
            <CampoSelect etiqueta="Pasa a" value={tipo} onChange={(e) => { setTipo(e.target.value); setMensaje(null); }} error={ver("tipo")}>
              <option value="">Elige el seguro</option>
              {opciones.map((t) => (
                <option key={t.clave} value={t.clave}>
                  {t.nombre}{t.clave === persona.automatico?.clave ? " — el que le toca por su vínculo" : ""}
                </option>
              ))}
            </CampoSelect>
            {vuelveAlAutomatico && (
              <p className="rounded-lg bg-hueso px-3 py-2 text-xs text-taupe">
                Es el que le toca por su vínculo: no se le asigna, se termina la asignación de DO y vuelve a seguirlo.
              </p>
            )}
            <Campo etiqueta="Desde cuándo rige" type="date" value={desde} max={hoy} onChange={(e) => setDesde(e.target.value)} error={ver("desde")} />
            <label className="flex flex-col gap-1">
              <span className="text-sm text-taupe">Por qué se cambia</span>
              <AreaTexto
                value={motivo}
                onChange={(e) => setMotivo(e.target.value)}
                placeholder="ej. Contrató su propio plan y presentó la constancia"
                className={ver("motivo") ? "border-rojo" : undefined}
              />
              {ver("motivo") && <span className="text-xs text-rojo">{errores.motivo}</span>}
            </label>
          </div>
          <p className="mt-3 text-xs text-taupe">
            Esto deja dos pendientes: pedir la baja del seguro anterior y dar de alta el nuevo. Dynamic no avisa solo a la
            aseguradora ni al contador: los cierras tú, aquí, cuando lo hagas.
          </p>
        </>
      )}

      <div className="mt-5 flex justify-end gap-2">
        <Boton onClick={onCerrar} disabled={ocupado}>Cancelar</Boton>
        {opciones.length > 0 && (
          <Boton variante="primario" onClick={() => void guardar()} cargando={ocupado}>
            {vuelveAlAutomatico ? "Volver al automático" : "Cambiar el seguro"}
          </Boton>
        )}
      </div>
    </>
  );
}

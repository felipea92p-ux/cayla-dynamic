"use client";

// ============================================================================
// Una prueba de tres días: qué lleva, qué falta y las tres cosas que se pueden
// hacer — «no fue apto», «se retiró» y «hacer contrato».
// ----------------------------------------------------------------------------
// QUÉ PROMETE. Es UNA pieza y vive en dos sitios: el desplegable de la Bandeja (para
// DO y para la líder de equipo, que no abre Contratos) y el asistente de Contratos
// (para DO). Así la regla de «qué se hace con una prueba» no tiene dos copias.
//
// QUÉ NO HACE. No decide quién puede: dibuja los botones con `puedeDecidirPrueba`
// y la base (`fn_prueba_puede_actuar`) es quien deja pasar la llamada. Tampoco
// calcula días ni pagos: los recibe de `fn_pruebas_abiertas`.
//
// POR QUÉ LA CONFIRMACIÓN DICE LO QUE CUESTA. «No fue apto» y «se retiró» dan de
// baja con el mismo gesto; lo único que cambia es si se le paga lo trabajado (decisión
// de Felipe, 2026-10-19). Por eso el diálogo abre con esa diferencia, en letras, y con
// las horas que están en juego — no con un «¿seguro?».
// ============================================================================

import { useRouter } from "next/navigation";
import { useState } from "react";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { puedeDecidirPrueba, puedeGestionarContratos } from "@cayla-dynamic/shared";
import { Boton } from "@/components/ui/boton";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { AreaTexto } from "@/components/ui/area-texto";
import { Insignia } from "@/components/ui/insignia";
import { Modal } from "@/components/ui/modal";
import { useToast } from "@/components/toast";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import {
  consecuenciaDelCierre, etiquetaDePrueba, ETIQUETA_RESULTADO, mensajeDeCierre, motivoValido, nombreDe,
  puedeHacerContrato, textoDeHoras, textoDelDia, type FilaPrueba, type ResultadoCierre,
} from "@/lib/admin/pruebas";
import { diaYMes } from "@/lib/bandeja-mia";
import { FormularioDniPrueba } from "./formulario-dni-prueba";

export function PanelPrueba({
  fila, supabase, rol, alCambiar,
}: {
  fila: FilaPrueba;
  supabase: ClienteCayla;
  rol: string | null | undefined;
  /** Después de cerrar la prueba o de guardar el DNI: quien lo usa vuelve a pedir la lista. */
  alCambiar: () => void;
}) {
  const { avisar } = useToast();
  const router = useRouter();
  const [cerrando, setCerrando] = useState<ResultadoCierre | null>(null);
  const [motivo, setMotivo] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const nombre = nombreDe(fila);
  const etiqueta = etiquetaDePrueba(fila);
  const puedeDecidir = puedeDecidirPrueba(rol);
  const consecuencia = cerrando ? consecuenciaDelCierre(cerrando, fila) : null;

  function abrir(resultado: ResultadoCierre) {
    setMotivo("");
    setError(null);
    setCerrando(resultado);
  }

  async function confirmar() {
    if (!cerrando) return;
    if (!motivoValido(motivo)) { setError("Escribe el motivo: queda registrado junto con quién decidió."); return; }
    setError(null);
    setEnviando(true);
    const { error: e } = await supabase.rpc("fn_prueba_cerrar", {
      p_persona_id: fila.persona_id,
      p_resultado: cerrando,
      p_motivo: motivo.trim(),
    });
    setEnviando(false);
    if (e) { setError(mensajeDeError(e, "cerrar la preselección")); return; }
    avisar("ok", mensajeDeCierre(cerrando, nombre));
    setCerrando(null);
    alCambiar();
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-2">
        <Insignia variante={etiqueta.variante}>{etiqueta.texto}</Insignia>
        <span className="text-sm text-taupe">{textoDelDia(fila)}</span>
      </div>
      <p className="text-xs text-taupe">
        Empezó el {diaYMes(fila.inicio)} · lleva {textoDeHoras(fila.horas_marcadas)} marcadas
        {fila.ultima_jornada ? ` · último día trabajado: ${diaYMes(fila.ultima_jornada)}` : " · todavía no marcó"}
      </p>

      {!fila.registrada && (
        <BannerAviso enLinea variante="advertencia">
          Esta preselección no quedó registrada al crear a la persona. Se registrará sola al cerrarla.
        </BannerAviso>
      )}

      <section aria-label="DNI" className="flex flex-col gap-2">
        <h3 className="text-sm font-medium">DNI (ambos lados)</h3>
        <FormularioDniPrueba
          supabase={supabase} personaId={fila.persona_id} nombre={nombre}
          diasPlazo={fila.dias_plazo} yaCargado={fila.dni_cargado} alGuardar={alCambiar}
        />
      </section>

      {puedeDecidir ? (
        <section aria-label="Decidir" className="flex flex-col gap-2 border-t border-dashed border-sand pt-3">
          <h3 className="text-sm font-medium">Decidir</h3>
          <div className="flex flex-wrap gap-2">
            {puedeHacerContrato(fila) && puedeGestionarContratos(rol) && (
              <Boton variante="primario" onClick={() => router.push(`/admin/contratos?persona=${fila.persona_id}`)}>
                Hacer contrato →
              </Boton>
            )}
            <Boton onClick={() => abrir("no_apto")}>No fue apto</Boton>
            <Boton variante="peligro" onClick={() => abrir("retirado")}>Se retiró</Boton>
          </div>
          {puedeHacerContrato(fila) && !puedeGestionarContratos(rol) && (
            <p className="text-xs text-taupe">Para hacerle el contrato, avisa a Desarrollo Organizacional.</p>
          )}
          {!puedeHacerContrato(fila) && (
            <p className="text-xs text-taupe">
              El contrato se hace cuando complete sus {fila.dias_plazo} días. Antes de eso solo se puede decidir que no fue apto o que se retiró.
            </p>
          )}
        </section>
      ) : (
        <p className="text-xs text-taupe">Solo Desarrollo Organizacional y las líderes de equipo deciden sobre una preselección.</p>
      )}

      <Modal
        abierto={cerrando !== null}
        onCerrar={() => setCerrando(null)}
        titulo={cerrando ? `${ETIQUETA_RESULTADO[cerrando]}: ${nombre}` : undefined}
        ancho="md"
        bloqueado={enviando}
      >
        {consecuencia && (
          <div className="flex flex-col gap-3">
            <BannerAviso enLinea variante={consecuencia.peligro ? "alerta" : "informativo"} titulo={`${consecuencia.titulo}.`}>
              <ul className="mt-1 list-disc space-y-1 pl-5">
                {consecuencia.lineas.map((l) => <li key={l}>{l}</li>)}
              </ul>
            </BannerAviso>
            <AreaTexto
              id={`motivo-prueba-${fila.persona_id}`}
              etiqueta="Motivo (queda registrado junto con quién decidió)"
              value={motivo}
              rows={2}
              disabled={enviando}
              onChange={(e) => { setMotivo(e.target.value); if (error) setError(null); }}
              error={error ?? undefined}
            />
            <div className="flex flex-wrap justify-end gap-2">
              <Boton onClick={() => setCerrando(null)} disabled={enviando}>Cancelar</Boton>
              <Boton variante={consecuencia.peligro ? "peligro" : "primario"} onClick={() => void confirmar()} cargando={enviando}>
                {cerrando === "retirado" ? "Confirmar: se retiró" : "Confirmar: no fue apto"}
              </Boton>
            </div>
          </div>
        )}
      </Modal>
    </div>
  );
}

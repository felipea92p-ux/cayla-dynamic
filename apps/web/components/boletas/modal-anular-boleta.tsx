"use client";

import { useEffect, useState } from "react";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { Modal } from "@/components/ui/modal";
import { Boton } from "@/components/ui/boton";
import { AreaTexto } from "@/components/ui/area-texto";
import { CampoSelect } from "@/components/ui/campo";
import { useToast } from "@/components/toast";
import { Cargando } from "@/components/cargando";
import { ConstanciaDeFirma, useConstancia } from "@/components/boletas/constancia-de-firma";
import { InsigniaDeEstado } from "@/components/boletas/insignia-de-estado";
import { PieDeModal, TACTIL } from "@/components/boletas/pie-de-modal";
import { VisorDeHojas } from "@/components/boletas/visor-de-hojas";
import {
  HORAS_PARA_RESTABLECER, MOTIVOS_DE_ANULACION, LETRAS_MINIMAS_DEL_MOTIVO, estadoVisible, motivoDeAnulacion,
  type ClaveMotivo, type TipoBoleta,
} from "@/lib/boletas";
import { hojasFirmadasDeVersion, type HojaFirmada } from "@/lib/boletas-archivos";
import { fechaHoraLima, type FilaTablero } from "@/lib/admin/boletas-pantalla";
import { mensajeDeError } from "@/lib/admin/mensaje-error";

/**
 * ANULAR UNA BOLETA YA APROBADA (0532).
 *
 * Anular saca la boleta de la vista de la persona, y desde la 0532 se puede
 * restablecer durante 48 horas. Por eso este modal NO es un «¿seguro?»: es la
 * revisión que DO hace ANTES de apretar, con lo que hace falta para saber si la
 * anulación es la correcta —la persona, la sede, el periodo, las fechas, la
 * boleta misma y su constancia de firma— y con el plazo escrito con fecha y hora.
 *
 * EL MOTIVO sale de una lista, o «Otro» con al menos 5 letras (lo mismo que
 * `fn_boleta_anular` exige; la base repite la comprobación y gana). Queda anotado
 * junto a la boleta, en el historial de anulaciones y en la auditoría.
 *
 * LA CASILLA CON EL NOMBRE existe porque una boleta anulada por error es la
 * boleta de otra persona que desaparece de su «Lo mío»: obliga a leer el nombre
 * antes de apretar, y el botón no se enciende sin ella.
 *
 * Los archivos y la firma NO se tocan al anular: quedan en la base, y por eso
 * restablecer puede devolverla exacta.
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
  const [clave, setClave] = useState<ClaveMotivo | "">("");
  const [otro, setOtro] = useState("");
  const [confirmo, setConfirmo] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);

  // La boleta y su constancia, para que DO vea lo que está por anular.
  const { constancia, error: errorConstancia } = useConstancia(supabase, fila.version_id);
  const [hojas, setHojas] = useState<HojaFirmada[] | null>(null);
  const [errorHojas, setErrorHojas] = useState<string | null>(null);
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

  const motivo = motivoDeAnulacion(clave, otro);
  const puede = motivo !== null && confirmo && !enviando;
  // El plazo se cuenta desde que se anula: «hasta» es ahora + 48 horas.
  const [hasta] = useState(() => fechaHoraLima(new Date(Date.now() + HORAS_PARA_RESTABLECER * 3_600_000).toISOString()));
  const firmada = estadoVisible(fila) === "firmada";

  async function anular() {
    if (fila.boleta_id === null || motivo === null) return;
    setError(null);
    setEnviando(true);
    const { error: e } = await supabase.rpc("fn_boleta_anular", { p_boleta_id: fila.boleta_id, p_motivo: motivo });
    if (e) { setEnviando(false); setError(mensajeDeError(e)); return; }
    avisar("ok", `Boleta de ${fila.nombre} anulada. Puedes restablecerla durante ${HORAS_PARA_RESTABLECER} horas.`);
    onAnulada();
  }

  return (
    <Modal abierto onCerrar={onCerrar} titulo="Anular boleta" ancho="xl" bloqueado={enviando}>
      <p className="mb-3 text-sm text-taupe">Revisa que sea la persona y la boleta correctas antes de anular.</p>

      <dl className="mb-4 grid grid-cols-2 gap-x-4 gap-y-3 rounded-xl border border-sand bg-hueso p-4 text-sm">
        <Dato etiqueta="Persona">{fila.nombre}</Dato>
        <Dato etiqueta="Sede">{fila.sede_codigo}</Dato>
        <Dato etiqueta="Periodo">{nombreDelPeriodo}</Dato>
        <Dato etiqueta="Estado ahora"><InsigniaDeEstado estado={estadoVisible(fila)} /></Dato>
        <Dato etiqueta="Publicada">{fechaHoraLima(fila.publicada_at)}</Dato>
        <Dato etiqueta={`Abierta por ${fila.nombre.split(" ")[0]}`}>{fechaHoraLima(fila.vista_at)}</Dato>
        <Dato etiqueta="Firmada">{firmada || fila.recibida_at ? fechaHoraLima(fila.recibida_at) : "—"}</Dato>
      </dl>

      {fila.version_id && (
        <div className="mb-4">
          <p className="mb-1 text-xs font-medium uppercase tracking-wide text-taupe">La boleta</p>
          <div className="max-h-56 overflow-auto rounded-xl border border-sand p-2">
            {errorHojas ? (
              <p role="alert" className="text-sm text-rojo-profundo">{errorHojas}</p>
            ) : hojas === null ? (
              <Cargando texto="Abriendo la boleta…" />
            ) : (
              <VisorDeHojas hojas={hojas} tipo={(fila.tipo ?? "imagen") as TipoBoleta} />
            )}
          </div>
        </div>
      )}

      {fila.version_id && (
        <div className="mb-4">
          <ConstanciaDeFirma nombre={fila.nombre} constancia={constancia} error={errorConstancia} />
        </div>
      )}

      <CampoSelect
        etiqueta="Motivo (queda anotado junto a la boleta)"
        value={clave}
        disabled={enviando}
        onChange={(e) => { setClave(e.target.value as ClaveMotivo | ""); setError(null); }}
      >
        <option value="">Elige un motivo…</option>
        {MOTIVOS_DE_ANULACION.map((m) => <option key={m.clave} value={m.clave}>{m.texto}</option>)}
      </CampoSelect>
      {clave === "otro" && (
        <div className="mt-3">
          <AreaTexto
            etiqueta="Escribe el motivo"
            rows={2}
            value={otro}
            disabled={enviando}
            placeholder="Por ejemplo: el contador la reemplaza por la corregida"
            onChange={(e) => { setOtro(e.target.value); setError(null); }}
          />
          <p className="mt-1 text-xs text-taupe">
            {otro.trim().length >= LETRAS_MINIMAS_DEL_MOTIVO
              ? `${otro.trim().length} letras`
              : `${otro.trim().length} de ${LETRAS_MINIMAS_DEL_MOTIVO} letras como mínimo`}
          </p>
        </div>
      )}

      <div className="mt-4 rounded-xl border border-rojo/40 bg-rojo/10 px-4 py-3 text-sm text-tinta">
        Qué pasa al anular: <b className="font-medium">{fila.nombre.split(" ")[0]}</b> deja de ver la boleta en «Lo mío» y ve que está
        en revisión.{fila.recibida_at ? " Su firma queda guardada: no se pierde." : ""}{" "}
        <b className="font-medium">Tienes {HORAS_PARA_RESTABLECER} horas para restablecerla (hasta el {hasta}).</b>{" "}
        Pasado ese plazo, hay que subir una boleta nueva.
      </div>

      <label className="mt-4 flex items-start gap-2 text-sm text-tinta">
        <input
          type="checkbox"
          className="mt-0.5 size-4 shrink-0 accent-tinta disabled:opacity-50"
          checked={confirmo}
          disabled={enviando}
          onChange={(e) => setConfirmo(e.target.checked)}
        />
        <span>Confirmo que es la boleta de <b className="font-medium">{fila.nombre}</b> · {nombreDelPeriodo}</span>
      </label>

      {error && <p role="alert" className="mt-3 rounded-control bg-rojo/10 px-3 py-2 text-sm text-rojo-profundo">{error}</p>}
      <PieDeModal>
        <Boton className={TACTIL} disabled={enviando} onClick={onCerrar}>Cancelar</Boton>
        <Boton variante="peligro" className={TACTIL} disabled={!puede} cargando={enviando} onClick={() => void anular()}>
          {enviando ? "Anulando…" : "Anular boleta"}
        </Boton>
      </PieDeModal>
    </Modal>
  );
}

function Dato({ etiqueta, children }: { etiqueta: string; children: React.ReactNode }) {
  return (
    <div className="min-w-0">
      <dt className="text-xs uppercase tracking-wide text-taupe">{etiqueta}</dt>
      <dd className="break-words font-medium text-tinta">{children}</dd>
    </div>
  );
}

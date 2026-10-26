"use client";

import { useCallback, useEffect, useState } from "react";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { Modal } from "@/components/ui/modal";
import { Boton } from "@/components/ui/boton";
import { Cargando } from "@/components/cargando";
import { useToast } from "@/components/toast";
import { FirmaEditor } from "@/app/(admin)/admin/personas/[id]/FirmaEditor";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { nombreDelPeriodo, type FilaMiBoleta } from "@/lib/mis-boletas";

/**
 * LA PERSONA FIRMA SU BOLETA (0532).
 *
 * Desde la 0532 una boleta se da por recibida FIRMÁNDOLA, con la firma que la
 * persona ya tiene guardada en Mi perfil → Firma. Es el patrón del memo y del
 * contrato: se muestra la firma, se pide una segunda confirmación y la base copia
 * la imagen en esa boleta, con fecha y hora, para siempre.
 *
 * DOS PASOS A PROPÓSITO. Un clic de más aquí cuenta como la firma de la persona
 * sobre un documento de plata, y el error de un clic no es de ella: es de cómo se
 * diseñó la pantalla. Por eso «Firmar y recibir» no firma: pide la segunda
 * confirmación, con la firma delante.
 *
 * SIN FIRMA GUARDADA, la crea ahí mismo (`FirmaEditor`, el mismo de Mi perfil) y
 * sigue: nadie se queda atascada por no haber pasado antes por el perfil.
 *
 * QUÉ ASUME. Que la persona ya abrió la boleta —la pantalla no ofrece «Firmar»
 * antes de «Ver», y la base lo exige—; y que si DO reemplazó la boleta mientras
 * tanto, la base lo dice («Tu boleta se actualizó…») y aquí se muestra tal cual.
 */
export function ModalFirmarBoleta({
  supabase, fila, onCerrar, onFirmada,
}: {
  supabase: ClienteCayla;
  fila: FilaMiBoleta;
  onCerrar: () => void;
  /** Se llama después de firmar, para que la lista se vuelva a leer. */
  onFirmada: () => void;
}) {
  const { avisar } = useToast();
  const [miFirma, setMiFirma] = useState<string | null>(null);
  const [nombreOficial, setNombreOficial] = useState("");
  const [cargando, setCargando] = useState(true);
  const [paso, setPaso] = useState<0 | 1>(0);
  const [cambiando, setCambiando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);

  const periodo = nombreDelPeriodo(fila.fecha_fin, { minuscula: true });

  const cargar = useCallback(async () => {
    const [{ data: mf }, { data: u }] = await Promise.all([
      supabase.rpc("fn_mi_firma"),
      supabase.auth.getUser(),
    ]);
    setMiFirma((mf as string | null) ?? null);
    // `nombre_dni` y no nombres+apellidos: es el que se imprime en la firma
    // tipográfica (ver FirmaEditor) y sale del DNI, no de cómo se escribió la ficha.
    const uid = u.user?.id;
    if (uid) {
      const { data: p } = await supabase.from("personas").select("id, nombres, apellidos").eq("auth_user_id", uid).maybeSingle();
      if (p) {
        const { data: ficha } = await supabase.from("datos_personales").select("nombre_dni").eq("persona_id", p.id).maybeSingle();
        setNombreOficial((ficha?.nombre_dni as string | null) || `${p.nombres as string} ${p.apellidos as string}`);
      }
    }
    setCargando(false);
  }, [supabase]);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargar(); }, [cargar]);

  async function firmar() {
    if (!fila.version_id) return;
    setError(null);
    setEnviando(true);
    const { error: e } = await supabase.rpc("fn_boleta_firmar", { p_version_id: fila.version_id });
    setEnviando(false);
    if (e) {
      // La base escribe sus mensajes para leerse, incluido el de «tu boleta se actualizó».
      setError(mensajeDeError(e));
      setPaso(0);
      return;
    }
    avisar("ok", `Firmaste tu boleta de ${periodo}.`);
    onFirmada();
  }

  const editando = !cargando && (miFirma === null || cambiando);

  return (
    <Modal abierto onCerrar={onCerrar} titulo="Firmar tu boleta" ancho="md" bloqueado={enviando}>
      {cargando ? (
        <Cargando texto="Un momento…" />
      ) : editando ? (
        <div className="space-y-3">
          <p className="text-sm text-tinta">
            {miFirma === null
              ? "Todavía no tienes una firma guardada. Créala una sola vez: la usarás en tus boletas, tu contrato y lo demás que firmes aquí."
              : "Cambia tu firma. Las boletas que ya firmaste conservan la que usaste ese día."}
          </p>
          <FirmaEditor
            supabase={supabase}
            nombreOficial={nombreOficial}
            avisar={avisar}
            onGuardada={(imagen) => { setMiFirma(imagen); setCambiando(false); }}
          />
          {miFirma !== null && (
            <Boton variante="secundario" className="min-h-11" onClick={() => setCambiando(false)}>Volver</Boton>
          )}
        </div>
      ) : paso === 0 ? (
        <div className="space-y-3">
          <p className="text-sm text-tinta">
            Vas a firmar tu boleta de <b className="font-medium">{periodo}</b>. Esta es tu firma guardada: quedará copiada en
            esta boleta, con la fecha y la hora.
          </p>
          <FirmaGuardada imagen={miFirma} nombre={nombreOficial} />
          <p className="text-xs text-taupe">
            Para dar por recibida tu boleta necesitas firmarla. Si no puedes hacerlo desde aquí, avisa a Desarrollo Organizacional.
          </p>
          {error && <p role="alert" className="rounded-control bg-rojo/10 px-3 py-2 text-sm text-rojo-profundo">{error}</p>}
          <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-between">
            <Boton variante="enlace" className="min-h-11 self-start" onClick={() => setCambiando(true)}>Cambiar mi firma</Boton>
            <div className="flex flex-col-reverse gap-2 sm:flex-row">
              <Boton variante="secundario" className="min-h-11" onClick={onCerrar}>Cancelar</Boton>
              <Boton variante="primario" className="min-h-11" onClick={() => setPaso(1)}>Firmar y recibir</Boton>
            </div>
          </div>
        </div>
      ) : (
        <div className="space-y-3">
          <div className="rounded-xl border border-rojo/40 bg-rojo/10 p-4">
            <p className="text-sm font-medium text-tinta">¿Firmas tu boleta de {periodo}?</p>
            <p className="mt-1 text-sm text-tinta">Un clic de más aquí cuenta como tu firma. Revísalo una vez más: no se puede deshacer.</p>
          </div>
          <FirmaGuardada imagen={miFirma} nombre={nombreOficial} />
          {error && <p role="alert" className="rounded-control bg-rojo/10 px-3 py-2 text-sm text-rojo-profundo">{error}</p>}
          <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
            <Boton variante="secundario" className="min-h-11" disabled={enviando} onClick={() => setPaso(0)}>Volver</Boton>
            <Boton variante="primario" className="min-h-11" cargando={enviando} onClick={() => void firmar()}>
              {enviando ? "Firmando…" : "Sí, firmar mi boleta"}
            </Boton>
          </div>
        </div>
      )}
    </Modal>
  );
}

/** Tu firma sobre un papel claro fijo: tinta oscura sobre fondo transparente se perdería en el modo oscuro. */
function FirmaGuardada({ imagen, nombre }: { imagen: string | null; nombre: string }) {
  if (!imagen) return null;
  return (
    <div
      className="flex min-h-24 flex-col items-center justify-end gap-1 rounded-lg border border-sand px-4 pb-2 pt-3"
      style={{ background: "var(--color-crema-fija)", color: "var(--color-tinta-fija)" }}
    >
      {/* eslint-disable-next-line @next/next/no-img-element -- la firma viene como data URL de la base */}
      <img src={imagen} alt="Tu firma guardada" className="max-h-20 w-auto max-w-full" />
      <span className="block w-4/5 border-t" style={{ borderColor: "var(--color-tinta-fija)" }} />
      <span className="text-xs">{nombre}</span>
    </div>
  );
}

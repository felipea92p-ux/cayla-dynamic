"use client";

// ============================================================================
// organigrama.tsx — el organigrama completo: se lee, y DO lo ordena
// ============================================================================
// La misma pieza sirve al panel y a «Lo mío». Quién puede ver y quién puede
// cambiar lo dice la base (`fn_organigrama` → `publicado`, `puede_editar`).
// ============================================================================

import { useCallback, useEffect, useMemo, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Cargando } from "@/components/cargando";
import { DibujoDelOrganigrama } from "@/components/organigrama/dibujo";
import { EditorDePersona, type Editando } from "@/components/organigrama/editor-persona";
import { useToast } from "@/components/toast";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Boton } from "@/components/ui/boton";
import { EstadoVacio } from "@/components/ui/estado-vacio";
import { Modal } from "@/components/ui/modal";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { leerOrganigrama, type Organigrama } from "@/lib/organigrama";

export function VistaDelOrganigrama({ conEdicion = false }: {
  /** El panel ofrece ordenar a quien la base deja; «Lo mío» solo muestra. */
  conEdicion?: boolean;
}) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const { avisar } = useToast();
  const [datos, setDatos] = useState<Organigrama | null>(null);
  const [fallo, setFallo] = useState<string | null>(null);
  const [ordenando, setOrdenando] = useState(false);
  const [editando, setEditando] = useState<Editando | null>(null);
  const [confirmando, setConfirmando] = useState(false);
  const [publicando, setPublicando] = useState(false);

  const cargar = useCallback(async () => {
    const { data, error } = await supabase.rpc("fn_organigrama");
    if (error) {
      setFallo(mensajeDeError(error, "cargar el organigrama"));
    } else {
      setDatos(leerOrganigrama(data));
      setFallo(null);
    }
  }, [supabase]);

  // `cargar` solo pone estado después de su `await`: no hay renders en cascada.
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargar(); }, [cargar]);

  async function publicar(valor: boolean) {
    setPublicando(true);
    const { error } = await supabase.rpc("fn_organigrama_publicar", { p_publicar: valor });
    if (error) {
      avisar("error", mensajeDeError(error, "publicar el organigrama"));
    } else {
      await cargar();
      setConfirmando(false);
      avisar("ok", valor ? "Ya lo ve todo el equipo." : "Volvió a borrador: solo lo ve Desarrollo Organizacional.");
    }
    setPublicando(false);
  }

  if (fallo) {
    return (
      <BannerAviso variante="alerta" role="alert">
        {fallo} <Boton variante="enlace" onClick={() => { void cargar(); }}>Reintentar</Boton>
      </BannerAviso>
    );
  }
  if (!datos) return <Cargando />;

  const edita = conEdicion && datos.puede_editar;
  if (!datos.publicado && !datos.puede_editar) {
    return <EstadoVacio>El organigrama todavía no está publicado.</EstadoVacio>;
  }

  return (
    <div className="flex flex-col gap-4">
      {!datos.publicado && (
        <BannerAviso enLinea variante="advertencia" titulo="Borrador:">
          solo lo ve Desarrollo Organizacional.
        </BannerAviso>
      )}
      {edita && (
        <div className="flex flex-wrap justify-end gap-2">
          <Boton onClick={() => setOrdenando((v) => !v)} aria-expanded={ordenando}>
            {ordenando ? "Terminar de ordenar" : "Ordenar"}
          </Boton>
          {datos.publicado
            ? <Boton onClick={() => { void publicar(false); }} cargando={publicando}>Volver a borrador</Boton>
            : <Boton variante="primario" onClick={() => setConfirmando(true)} disabled={datos.personas.length === 0}>Publicar al equipo</Boton>}
        </div>
      )}
      {ordenando && <p className="text-sm text-taupe">Toca una tarjeta para cambiar su equipo, su función, su color o sus líneas.</p>}

      {edita && datos.sin_ubicar.length > 0 && (
        <TarjetaInfo como="section" titulo={`Sin ubicar (${datos.sin_ubicar.length})`}>
          <ul className="flex flex-wrap gap-2">
            {datos.sin_ubicar.map((p) => (
              <li key={p.persona_id}>
                <Boton onClick={() => setEditando({ persona_id: p.persona_id, nombre: `${p.nombres} ${p.apellidos}`, cargo: p.cargo })}>
                  {p.nombres} {p.apellidos}{p.sede ? ` · ${p.sede}` : ""}
                </Boton>
              </li>
            ))}
          </ul>
        </TarjetaInfo>
      )}

      {datos.personas.length === 0
        ? <EstadoVacio>Todavía no hay nadie ubicado en el organigrama.</EstadoVacio>
        : (
          <DibujoDelOrganigrama datos={datos}
            onElegir={ordenando ? (n) => setEditando({ persona_id: n.persona_id, nombre: `${n.nombres} ${n.apellidos}` }) : undefined} />
        )}

      {editando && (
        <EditorDePersona key={editando.persona_id} datos={datos} quien={editando} onCerrar={() => setEditando(null)} onGuardado={cargar} />
      )}

      <Modal abierto={confirmando} titulo="Publicar el organigrama" bloqueado={publicando} onCerrar={() => setConfirmando(false)}>
        <p className="mb-4 text-sm text-tinta">
          Todo el equipo verá las funciones tal como aparecen aquí. Si alguna cambia lo que una persona hace hoy,
          conversa con ella y revisa su contrato antes de publicar.
        </p>
        <div className="flex flex-wrap justify-end gap-2">
          <Boton variante="enlace" onClick={() => setConfirmando(false)}>Todavía no</Boton>
          <Boton variante="primario" tamano="lg" cargando={publicando} onClick={() => { void publicar(true); }}>Publicar</Boton>
        </div>
      </Modal>
    </div>
  );
}

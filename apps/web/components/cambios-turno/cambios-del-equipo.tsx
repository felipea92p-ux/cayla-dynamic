"use client";

import { useEffect, useState } from "react";
import type { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { Boton } from "@/components/ui/boton";
import { AreaTexto } from "@/components/ui/area-texto";
import { Insignia } from "@/components/ui/insignia";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { diaMes } from "@/lib/disponibilidad";
import { horasParaDo, pasoADo } from "@/lib/pedidos-turno";
import { COLUMNAS_CAMBIO, tramo, type CambioEquipo } from "@/lib/cambios-turno";

/**
 * «Cambios entre compañeras» — en «Disponibilidad del equipo» (0592).
 *
 * QUÉ PROMETE · que su líder de equipo vea los cambios de turno que la
 *               compañera ya aceptó y los apruebe o no; y que DO vea todos.
 *               Aprobar intercambia los dos turnos en el acto. El piso o
 *               almacén de ese día no se intercambia: se le avisa que lo mire.
 * QUÉ ASUME   · la RLS de la 0592 y `fn_turno_cambio_resolver`, que decide
 *               quién aprueba (la líder de las dos, o DO). Las 48 h para que
 *               pase a DO son las de «Este día no me calza» (lib/pedidos-turno.ts),
 *               contadas desde que la compañera aceptó.
 */

type Cliente = ReturnType<typeof createAdminSupabaseClient>;
type Avisar = (tipo: "ok" | "error", texto: string) => void;
interface PersonaMin { id: string; nombres: string; apellidos: string; rol: string | null }

export function CambiosDelEquipo({ supabase, personas, yoId, avisar }: {
  supabase: Cliente; personas: PersonaMin[]; yoId: string; avisar: Avisar;
}) {
  const [cambios, setCambios] = useState<CambioEquipo[] | null>(null);
  const [recarga, setRecarga] = useState(0);
  const clave = personas.map((p) => p.id).join(",");

  useEffect(() => {
    const ids = clave ? clave.split(",") : [];
    if (ids.length === 0) return;
    let vivo = true;
    void (async () => {
      const { data, error } = await supabase.from("turno_cambios").select(COLUMNAS_CAMBIO)
        .in("solicitante_id", ids).eq("estado", "aceptado")
        .order("fecha", { ascending: true }).order("id", { ascending: true });
      if (!vivo) return;
      setCambios(error ? null : ((data as unknown as CambioEquipo[]) ?? []));
    })();
    return () => { vivo = false; };
  }, [supabase, clave, recarga]);

  if (!cambios || cambios.length === 0) return null;
  const nombre = new Map(personas.map((p) => [p.id, `${p.nombres} ${p.apellidos}`]));

  return (
    <section className="flex flex-col gap-3" aria-label="Cambios entre compañeras">
      <h2 className="font-serif text-lg">Cambios entre compañeras</h2>
      <p className="text-sm text-taupe">Las dos ya están de acuerdo. Al aprobar, se intercambian sus turnos de ese día.</p>
      <ul className="flex flex-col gap-3">
        {cambios.map((c) => (
          <Cambio key={c.id} c={c} nombre={(id) => nombre.get(id) ?? "Una compañera"}
            esDeEllas={c.solicitante_id === yoId || c.companera_id === yoId}
            supabase={supabase} avisar={avisar} onListo={() => setRecarga((n) => n + 1)} />
        ))}
      </ul>
    </section>
  );
}

function Cambio({ c, nombre, esDeEllas, supabase, avisar, onListo }: {
  c: CambioEquipo; nombre: (id: string) => string; esDeEllas: boolean;
  supabase: Cliente; avisar: Avisar; onListo: () => void;
}) {
  const [respuesta, setRespuesta] = useState("");
  const [enviando, setEnviando] = useState(false);
  // Desde que la compañera aceptó: recién ahí espera a la líder.
  const desde = { estado: "abierto" as const, creado_at: c.contestado_at ?? c.creado_at };

  const resolver = async (aprueba: boolean) => {
    setEnviando(true);
    const { error } = await supabase.rpc("fn_turno_cambio_resolver", {
      p_id: c.id, p_aprueba: aprueba, p_respuesta: respuesta.trim() || null,
    });
    setEnviando(false);
    if (error) return avisar("error", mensajeDeError(error));
    avisar("ok", aprueba ? "Aprobado: ya se intercambiaron los dos turnos." : "Listo: les llega tu respuesta.");
    onListo();
  };

  return (
    <TarjetaInfo como="li" titulo={`${diaMes(c.fecha)} · ${nombre(c.solicitante_id)} ⇄ ${nombre(c.companera_id)}`}
      accion={pasoADo(desde) ? <Insignia variante="advertencia">Pasó a DO</Insignia>
        : <Insignia variante="informativo" atenuada>{`Pasa a DO en ${horasParaDo(desde)} h`}</Insignia>}>
      <div className="flex flex-col gap-2 text-sm">
        <p>
          {nombre(c.solicitante_id)} pasa de {tramo(c.sol_entrada, c.sol_salida)} a {tramo(c.comp_entrada, c.comp_salida)};{" "}
          {nombre(c.companera_id)}, al revés. Las dos trabajan las mismas horas ese día.
        </p>
        {c.comentario && <p className="italic">«{c.comentario}»</p>}
        <BannerAviso variante="informativo" enLinea>
          El piso o almacén de ese día no se intercambia: revísalo en Turnos después de aprobar.
        </BannerAviso>
        {esDeEllas ? (
          <p className="text-taupe">Es un cambio tuyo: lo aprueba Desarrollo Organizacional.</p>
        ) : (
          <>
            <AreaTexto etiqueta="Mensaje para las dos (obligatorio si no lo apruebas)" value={respuesta} rows={2}
              maxLength={500} onChange={(e) => setRespuesta(e.target.value)} />
            <div className="flex flex-wrap gap-2">
              <Boton variante="primario" cargando={enviando} onClick={() => void resolver(true)}>Aprobar</Boton>
              <Boton disabled={enviando || respuesta.trim().length < 5} onClick={() => void resolver(false)}>No aprobar</Boton>
            </div>
          </>
        )}
      </div>
    </TarjetaInfo>
  );
}

/**
 * Desde un pedido de «Este día no me calza»: la líder elige con quién cambiarlo.
 * Basta con que la compañera acepte (la líder ya lo aprobó al proponerlo).
 */
export function ProponerCambioDesdePedido({ supabase, pedidoId, personaId, fecha, avisar, onListo }: {
  supabase: Cliente; pedidoId: string; personaId: string; fecha: string; avisar: Avisar; onListo: () => void;
}) {
  const [abierto, setAbierto] = useState(false);
  const [candidatas, setCandidatas] = useState<{ persona_id: string; nombre: string; hora_entrada: string; hora_salida: string }[] | null>(null);
  const [enviando, setEnviando] = useState(false);

  useEffect(() => {
    if (!abierto) return;
    let vivo = true;
    void (async () => {
      const { data, error } = await supabase.rpc("fn_turno_cambio_candidatas", { p_fecha: fecha, p_persona_id: personaId });
      if (!vivo) return;
      setCandidatas(error ? [] : (data ?? []));
    })();
    return () => { vivo = false; };
  }, [supabase, abierto, fecha, personaId]);

  const proponer = async (companeraId: string) => {
    setEnviando(true);
    const { error } = await supabase.rpc("fn_turno_cambio_proponer_por_pedido", { p_pedido_id: pedidoId, p_companera_id: companeraId });
    setEnviando(false);
    if (error) return avisar("error", mensajeDeError(error));
    avisar("ok", "Listo: se lo pedimos a la compañera. Si acepta, se cambian en el acto.");
    onListo();
  };

  if (!abierto) {
    return <Boton variante="enlace" className="self-start" onClick={() => setAbierto(true)}>Cambiarlo con una compañera</Boton>;
  }
  return (
    <div className="flex flex-col gap-2">
      <span className="text-sm text-taupe">¿Con quién? (su tienda, ese día, un turno distinto del mismo largo)</span>
      {candidatas === null ? <span className="text-sm text-taupe">Buscando…</span>
        : candidatas.length === 0 ? <span className="text-sm text-taupe">Ese día no hay con quién: cámbialo en Turnos.</span>
        : (
          <div className="flex flex-wrap gap-2">
            {candidatas.map((k) => (
              <Boton key={k.persona_id} tamano="sm" disabled={enviando} onClick={() => void proponer(k.persona_id)}>
                {k.nombre} · {tramo(k.hora_entrada, k.hora_salida)}
              </Boton>
            ))}
          </div>
        )}
    </div>
  );
}

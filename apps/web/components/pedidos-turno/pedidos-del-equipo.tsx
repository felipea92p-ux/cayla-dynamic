"use client";

import { useEffect, useState } from "react";
import type { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { esRolIntegrante } from "@cayla-dynamic/shared";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { Boton } from "@/components/ui/boton";
import { Filtro } from "@/components/ui/filtro";
import { AreaTexto } from "@/components/ui/area-texto";
import { Insignia } from "@/components/ui/insignia";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { ProponerCambioDesdePedido } from "@/components/cambios-turno/cambios-del-equipo";
import {
  COLUMNAS_PEDIDO, MIN_RESPUESTA, RESOLUCIONES, horasParaDo, pasoADo, respuestaValida, resumenPedido,
  type PedidoTurno, type ResolucionPedido,
} from "@/lib/pedidos-turno";

/**
 * «Días que no les calzan» — arriba de «Disponibilidad del equipo» (0587).
 *
 * QUÉ PROMETE · que su líder de equipo vea los pedidos abiertos de su sede, con
 *               cuánto falta para que pasen a DO, y los responda; y que DO vea
 *               todos, con los que ya pasaron las 48 h arriba. Responder no
 *               cambia el turno: si le calza, el turno se cambia en Turnos.
 * QUÉ ASUME   · la RLS de la 0587 (la líder, su sede; DO, todo) y que
 *               `fn_turno_pedido_responder` decide quién responde. La pantalla
 *               esconde los botones que la base igual rechazaría.
 */

type Cliente = ReturnType<typeof createAdminSupabaseClient>;
type Avisar = (tipo: "ok" | "error", texto: string) => void;
interface PersonaMin { id: string; nombres: string; apellidos: string; rol: string | null }

export function PedidosDelEquipo({ supabase, personas, yoId, esDO, avisar }: {
  supabase: Cliente; personas: PersonaMin[]; yoId: string; esDO: boolean; avisar: Avisar;
}) {
  const [pedidos, setPedidos] = useState<PedidoTurno[] | null>(null);
  const [recarga, setRecarga] = useState(0);
  const clave = personas.map((p) => p.id).join(",");

  useEffect(() => {
    const ids = clave ? clave.split(",") : [];
    if (ids.length === 0) return;
    let vivo = true;
    void (async () => {
      const { data, error } = await supabase.from("turno_pedidos").select(COLUMNAS_PEDIDO)
        .in("persona_id", ids).eq("estado", "abierto")
        .order("creado_at", { ascending: true }).order("id", { ascending: true });
      if (!vivo) return;
      // Sin la 0587 la tabla no existe: la sección se calla.
      setPedidos(error ? null : ((data as unknown as PedidoTurno[]) ?? []));
    })();
    return () => { vivo = false; };
  }, [supabase, clave, recarga]);

  if (!pedidos || pedidos.length === 0) return null;

  const porId = new Map(personas.map((p) => [p.id, p]));
  // Para DO, primero lo que ya es suyo (pasó las 48 h); para la líder, lo más viejo primero.
  const orden = [...pedidos].sort((a, b) =>
    (esDO ? Number(pasoADo(b)) - Number(pasoADo(a)) : 0) || a.creado_at.localeCompare(b.creado_at));
  const deDo = pedidos.filter((p) => pasoADo(p)).length;

  return (
    <section className="flex flex-col gap-3" aria-label="Días que no les calzan">
      <h2 className="font-serif text-lg">Días que no les calzan</h2>
      <p className="text-sm text-taupe">
        Pidieron cambiar el turno de un día. Mientras nadie responda, el turno sigue igual.
        {esDO && deDo > 0 ? ` ${deDo} ya ${deDo === 1 ? "pasó" : "pasaron"} las 48 h sin respuesta de su líder.` : ""}
      </p>
      <ul className="flex flex-col gap-3">
        {orden.map((p) => {
          const persona = porId.get(p.persona_id);
          if (!persona) return null;
          return (
            <Pedido key={p.id} pedido={p} persona={persona}
              puedeResponder={p.persona_id !== yoId && (esDO || esRolIntegrante(persona.rol))}
              supabase={supabase} avisar={avisar} onListo={() => setRecarga((n) => n + 1)} />
          );
        })}
      </ul>
    </section>
  );
}

function Pedido({ pedido, persona, puedeResponder, supabase, avisar, onListo }: {
  pedido: PedidoTurno; persona: PersonaMin; puedeResponder: boolean;
  supabase: Cliente; avisar: Avisar; onListo: () => void;
}) {
  const [resolucion, setResolucion] = useState<Exclude<ResolucionPedido, "cambio_companera">>("acepta");
  const [respuesta, setRespuesta] = useState("");
  const [enviando, setEnviando] = useState(false);
  const conDo = pasoADo(pedido);
  const pide = RESOLUCIONES.find((r) => r.valor === resolucion)?.pideTexto ?? true;

  const responder = async () => {
    setEnviando(true);
    const { error } = await supabase.rpc("fn_turno_pedido_responder", {
      p_id: pedido.id, p_resolucion: resolucion, p_respuesta: respuesta.trim() || null,
    });
    setEnviando(false);
    if (error) return avisar("error", mensajeDeError(error));
    avisar("ok", resolucion === "acepta"
      ? "Listo: le llega tu respuesta. Ahora cambia su turno de ese día en Turnos."
      : "Listo: le llega tu respuesta a su Bandeja.");
    onListo();
  };

  return (
    <TarjetaInfo como="li" titulo={`${persona.nombres} ${persona.apellidos}`}
      accion={conDo ? <Insignia variante="advertencia">Pasó a DO</Insignia>
        : <Insignia variante="informativo" atenuada>{`Pasa a DO en ${horasParaDo(pedido)} h`}</Insignia>}>
      <div className="flex flex-col gap-3 text-sm">
        <p className="font-medium">{resumenPedido(pedido, "ella")}</p>
        {pedido.comentario && <p className="italic">«{pedido.comentario}»</p>}
        {puedeResponder ? (
          <div className="flex flex-col gap-2 rounded-control bg-hueso p-3">
            <div role="group" aria-label="Qué le respondes" className="flex flex-wrap gap-2">
              {RESOLUCIONES.map((r) => (
                <Filtro key={r.valor} tamano="sm" activo={r.valor === resolucion} onClick={() => setResolucion(r.valor)}>{r.label}</Filtro>
              ))}
            </div>
            <AreaTexto
              etiqueta={pide ? `Explícale por qué (al menos ${MIN_RESPUESTA} caracteres)` : "Mensaje para ella (opcional)"}
              value={respuesta} rows={2} maxLength={500} onChange={(e) => setRespuesta(e.target.value)} />
            {resolucion === "acepta" && (
              <BannerAviso variante="informativo" enLinea>Responder no cambia el turno: después, cámbialo en Turnos.</BannerAviso>
            )}
            <Boton variante="primario" className="self-start" cargando={enviando}
              disabled={!respuestaValida(resolucion, respuesta)} onClick={() => void responder()}>
              Responder
            </Boton>
            <ProponerCambioDesdePedido supabase={supabase} pedidoId={pedido.id} personaId={pedido.persona_id}
              fecha={pedido.fecha} avisar={avisar} onListo={onListo} />
          </div>
        ) : (
          <p className="text-taupe">Lo responde Desarrollo Organizacional.</p>
        )}
      </div>
    </TarjetaInfo>
  );
}

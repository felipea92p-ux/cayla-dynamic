"use client";

import { useEffect, useState } from "react";
import type { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { rangoDelDiaLima, sumarDias } from "@cayla-dynamic/shared";
import { Boton } from "@/components/ui/boton";
import { Filtro } from "@/components/ui/filtro";
import { AreaTexto } from "@/components/ui/area-texto";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { useToast } from "@/components/toast";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { diaMes } from "@/lib/disponibilidad";
import {
  COLUMNAS_PEDIDO, MAX_COMENTARIO, MOTIVOS, PROPUESTAS, resumenPedido, sePuedePedir, textoResolucion,
  type MotivoPedido, type PedidoTurno, type PropuestaPedido,
} from "@/lib/pedidos-turno";
import type { MiSemana } from "./tu-semana";

/**
 * «Este día no me calza», debajo de «Tu semana» en Mis turnos (0587).
 *
 * QUÉ PROMETE · elegir un día que le toca trabajar (de hoy a dos semanas, los
 *               que ya muestra «Tu semana»), decir por qué y qué le calza, y
 *               mandárselo a su líder de equipo. Ve en qué está cada pedido y
 *               puede retirarlo mientras nadie respondió. Las reglas viven en
 *               lib/pedidos-turno.ts y en la base.
 * NO HACE     · cambiar su turno. Mientras nadie responda, el turno sigue igual;
 *               si le dicen que sí, su líder lo cambia en Turnos y ella lo ve
 *               en «Tu semana» y en su Bandeja.
 * EN «LO MÍO» · nunca se nombra a otra persona: «tu líder de equipo», «DO».
 */

type Cliente = ReturnType<typeof createAdminSupabaseClient>;

const DIAS_CORTOS = ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"];
const dow = (iso: string) => new Date(`${iso}T12:00:00Z`).getUTCDay();

export function EsteDiaNoMeCalza({ supabase, personaId, semana }: {
  supabase: Cliente;
  personaId: string;
  semana: MiSemana;
}) {
  const toast = useToast();
  const [pedidos, setPedidos] = useState<PedidoTurno[] | null>(null);
  const [recarga, setRecarga] = useState(0);
  const [abierto, setAbierto] = useState(false);
  const [enviando, setEnviando] = useState(false);

  // Los días que le tocan trabajar de hoy en adelante, de las dos semanas que ya leyó «Tu semana».
  const abiertosPorDia = new Set((pedidos ?? []).filter((p) => p.estado === "abierto").map((p) => p.fecha));
  const dias = [...semana.semanas[0], ...semana.semanas[1]]
    .filter((d) => d.esperado.trabaja && sePuedePedir(d.fecha, semana.hoy) && !abiertosPorDia.has(d.fecha));

  // Nace con el primer día posible elegido: nunca vacío (CLAUDE.md, «un campo que bloquea no arranca en ""»).
  const [fecha, setFecha] = useState<string | null>(null);
  const fechaElegida = fecha && dias.some((d) => d.fecha === fecha) ? fecha : dias[0]?.fecha ?? null;
  const [motivo, setMotivo] = useState<MotivoPedido>("estudios");
  const [propuesta, setPropuesta] = useState<PropuestaPedido>("tarde");
  const [comentario, setComentario] = useState("");

  useEffect(() => {
    let vivo = true;
    void (async () => {
      const { data, error } = await supabase.from("turno_pedidos").select(COLUMNAS_PEDIDO)
        .eq("persona_id", personaId)
        .order("creado_at", { ascending: false })
        .limit(20);
      if (!vivo) return;
      // Sin la 0587 la tabla no existe: la sección se calla entera.
      setPedidos(error ? null : ((data as unknown as PedidoTurno[]) ?? []));
    })();
    return () => { vivo = false; };
  }, [supabase, personaId, recarga]);

  if (pedidos === null || semana.cargando || semana.error) return null;

  const enviar = async () => {
    if (!fechaElegida) return;
    setEnviando(true);
    const { error } = await supabase.rpc("fn_turno_pedido_crear", {
      p_fecha: fechaElegida, p_motivo: motivo, p_propuesta: propuesta, p_comentario: comentario.trim() || null,
    });
    setEnviando(false);
    if (error) {
      toast.avisar("error", mensajeDeError(error));
      return;
    }
    toast.avisar("ok", "Listo: se lo mandaste a tu líder de equipo. Mientras te responde, tu turno sigue igual.");
    setAbierto(false);
    setComentario("");
    setFecha(null);
    setRecarga((n) => n + 1);
  };

  const retirar = async (id: string) => {
    const { error } = await supabase.rpc("fn_turno_pedido_retirar", { p_id: id });
    if (error) toast.avisar("error", mensajeDeError(error));
    else setRecarga((n) => n + 1);
  };

  // Lo abierto, y lo respondido de los últimos 30 días: lo viejo ya está en su Bandeja.
  const hace30 = Date.parse(rangoDelDiaLima(sumarDias(semana.hoy, -30)).inicio);
  const visibles = pedidos.filter((p) => p.estado === "abierto"
    || (p.estado === "resuelto" && p.resuelto_at && Date.parse(p.resuelto_at) >= hace30));

  return (
    <div data-tour="mio-turnos-no-me-calza" className="mt-4 flex flex-col gap-3 border-t border-sand pt-3">
      {visibles.length > 0 && (
        <ul className="flex flex-col gap-2">
          {visibles.map((p) => (
            <li key={p.id} className="flex flex-col gap-1 rounded-control bg-hueso px-3 py-2 text-sm">
              <span className="font-medium">{resumenPedido(p)}</span>
              {p.estado === "abierto" ? (
                <>
                  <span className="text-taupe">Esperando a tu líder de equipo. Mientras tanto tu turno sigue igual.</span>
                  <Boton tamano="sm" className="self-start" onClick={() => void retirar(p.id)}>Retirarlo</Boton>
                </>
              ) : (
                <span>
                  <strong>{textoResolucion(p.resolucion)}</strong>
                  {p.respuesta ? ` — «${p.respuesta}»` : ""}
                </span>
              )}
            </li>
          ))}
        </ul>
      )}

      {!abierto ? (
        <Boton className="self-start" onClick={() => setAbierto(true)} disabled={dias.length === 0}>
          Este día no me calza
        </Boton>
      ) : (
        <div className="flex flex-col gap-3 rounded-control bg-hueso p-3">
          <div role="group" aria-label="Qué día" className="flex flex-col gap-1">
            <span className="text-sm text-taupe">¿Qué día?</span>
            <div className="flex flex-wrap gap-2">
              {dias.map((d) => (
                <Filtro key={d.fecha} tamano="sm" activo={d.fecha === fechaElegida} onClick={() => setFecha(d.fecha)}>
                  {DIAS_CORTOS[dow(d.fecha)]} {diaMes(d.fecha)}
                  {d.esperado.entrada && d.esperado.salida ? ` · ${d.esperado.entrada}–${d.esperado.salida}` : ""}
                </Filtro>
              ))}
            </div>
          </div>
          <div role="group" aria-label="Por qué" className="flex flex-col gap-1">
            <span className="text-sm text-taupe">¿Por qué?</span>
            <div className="flex flex-wrap gap-2">
              {MOTIVOS.map((m) => (
                <Filtro key={m.valor} tamano="sm" activo={m.valor === motivo} onClick={() => setMotivo(m.valor)}>{m.label}</Filtro>
              ))}
            </div>
          </div>
          <div role="group" aria-label="Qué te calza" className="flex flex-col gap-1">
            <span className="text-sm text-taupe">¿Qué te calza ese día?</span>
            <div className="flex flex-wrap gap-2">
              {PROPUESTAS.map((p) => (
                <Filtro key={p.valor} tamano="sm" activo={p.valor === propuesta} onClick={() => setPropuesta(p.valor)}>{p.label}</Filtro>
              ))}
            </div>
          </div>
          <AreaTexto
            etiqueta="Algo más que quieras contarle (opcional)"
            value={comentario}
            maxLength={MAX_COMENTARIO}
            onChange={(e) => setComentario(e.target.value)}
          />
          <BannerAviso variante="informativo">
            Va a tu líder de equipo. Si en 48 horas no te responde, lo ve Desarrollo Organizacional. Mientras tanto, tu turno sigue igual.
          </BannerAviso>
          <div className="flex flex-wrap gap-2">
            <Boton variante="primario" onClick={() => void enviar()} disabled={!fechaElegida || enviando}>
              {enviando ? "Enviando…" : "Enviar a mi líder de equipo"}
            </Boton>
            <Boton onClick={() => setAbierto(false)}>Cancelar</Boton>
          </div>
        </div>
      )}
      {!abierto && dias.length === 0 && (
        <p className="text-sm text-taupe">No tienes días por trabajar en estas dos semanas que puedas pedir.</p>
      )}
    </div>
  );
}

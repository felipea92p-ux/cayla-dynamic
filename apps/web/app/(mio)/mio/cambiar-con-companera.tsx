"use client";

import { useEffect, useState } from "react";
import type { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Boton } from "@/components/ui/boton";
import { Filtro } from "@/components/ui/filtro";
import { AreaTexto } from "@/components/ui/area-texto";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { useToast } from "@/components/toast";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { diaMes } from "@/lib/disponibilidad";
import { sePuedePedir } from "@/lib/pedidos-turno";
import { estadoParaElla, estaVivo, resumenCambio, tramo, type MiCambio } from "@/lib/cambios-turno";
import type { MiSemana } from "./tu-semana";

/**
 * «Cambiar con una compañera», en «Lo mío · Mis turnos» (0592).
 *
 * QUÉ PROMETE · que ella le proponga a una compañera de su tienda cambiarse el
 *               turno de un día (mismo día, mismo largo); que la compañera lo
 *               acepte o no desde aquí; y que las dos vean en qué está. Hasta
 *               que lo apruebe su líder, sus turnos siguen igual.
 * QUÉ ASUME   · `fn_turno_cambio_candidatas` dice con quién se puede (la base
 *               decide; acá no se repite la regla) y `fn_turno_cambios_mios`
 *               trae los suyos con el nombre de la otra. Sin la 0592, se calla.
 */

type Cliente = ReturnType<typeof createAdminSupabaseClient>;
interface Candidata { persona_id: string; nombre: string; hora_entrada: string; hora_salida: string }

const DIAS_CORTOS = ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"];
const dow = (iso: string) => new Date(`${iso}T12:00:00Z`).getUTCDay();

export function CambiarConCompanera({ supabase, semana }: { supabase: Cliente; semana: MiSemana }) {
  const toast = useToast();
  const [cambios, setCambios] = useState<MiCambio[] | null>(null);
  const [recarga, setRecarga] = useState(0);
  const [abierto, setAbierto] = useState(false);
  const [fecha, setFecha] = useState<string | null>(null);
  const [candidatas, setCandidatas] = useState<Candidata[] | null>(null);
  const [elegida, setElegida] = useState<string | null>(null);
  const [comentario, setComentario] = useState("");
  const [enviando, setEnviando] = useState(false);

  useEffect(() => {
    let vivo = true;
    void (async () => {
      const { data, error } = await supabase.rpc("fn_turno_cambios_mios");
      if (!vivo) return;
      setCambios(error ? null : ((data as unknown as MiCambio[]) ?? []));
    })();
    return () => { vivo = false; };
  }, [supabase, recarga]);

  const vivosPorDia = new Set((cambios ?? []).filter((c) => estaVivo(c.estado)).map((c) => c.fecha));
  const dias = [...semana.semanas[0], ...semana.semanas[1]]
    .filter((d) => d.esperado.trabaja && sePuedePedir(d.fecha, semana.hoy) && !vivosPorDia.has(d.fecha));
  // Nace con el primer día posible: nunca vacío.
  const fechaElegida = fecha && dias.some((d) => d.fecha === fecha) ? fecha : dias[0]?.fecha ?? null;

  useEffect(() => {
    if (!abierto || !fechaElegida) return;
    let vivo = true;
    void (async () => {
      const { data, error } = await supabase.rpc("fn_turno_cambio_candidatas", { p_fecha: fechaElegida });
      if (!vivo) return;
      setCandidatas(error ? [] : ((data as Candidata[]) ?? []));
    })();
    return () => { vivo = false; };
  }, [supabase, abierto, fechaElegida]);

  if (cambios === null || semana.cargando || semana.error) return null;

  const listo = (texto: string) => { toast.avisar("ok", texto); setRecarga((n) => n + 1); };

  const proponer = async () => {
    if (!fechaElegida || !elegida) return;
    setEnviando(true);
    const { error } = await supabase.rpc("fn_turno_cambio_proponer", {
      p_fecha: fechaElegida, p_companera_id: elegida, p_comentario: comentario.trim() || null,
    });
    setEnviando(false);
    if (error) return toast.avisar("error", mensajeDeError(error));
    setAbierto(false); setElegida(null); setComentario(""); setFecha(null); setCandidatas(null);
    listo("Listo: se lo pediste. Si acepta, lo aprueba tu líder de equipo. Mientras tanto tu turno sigue igual.");
  };

  const contestar = async (id: string, acepta: boolean) => {
    const { error } = await supabase.rpc("fn_turno_cambio_contestar", { p_id: id, p_acepta: acepta });
    if (error) return toast.avisar("error", mensajeDeError(error));
    listo(acepta ? "Aceptaste. Si hace falta, lo aprueba tu líder de equipo." : "Listo: le avisamos que no puedes.");
  };

  const retirar = async (id: string) => {
    const { error } = await supabase.rpc("fn_turno_cambio_retirar", { p_id: id });
    if (error) return toast.avisar("error", mensajeDeError(error));
    listo("Lo retiraste.");
  };

  // Lo vivo, y lo que terminó en los últimos días (lo viejo ya está en su Bandeja).
  const visibles = cambios.filter((c) => estaVivo(c.estado) ? c.fecha >= semana.hoy : c.fecha >= semana.hoy && c.estado !== "retirado");

  return (
    <div data-tour="mio-turnos-cambiar" className="mt-4 flex flex-col gap-3 border-t border-sand pt-3">
      {visibles.length > 0 && (
        <ul className="flex flex-col gap-2">
          {visibles.map((c) => (
            <li key={c.id} className="flex flex-col gap-1 rounded-control bg-hueso px-3 py-2 text-sm">
              <span className="font-medium">{resumenCambio(c)}</span>
              <span className="text-taupe">{estadoParaElla(c)}</span>
              {c.comentario && <span className="italic">«{c.comentario}»</span>}
              {c.respuesta && <span>Tu líder de equipo: «{c.respuesta}»</span>}
              {c.estado === "propuesto" && c.soy === "companera" && (
                <div className="flex flex-wrap gap-2">
                  <Boton tamano="sm" variante="primario" onClick={() => void contestar(c.id, true)}>Acepto</Boton>
                  <Boton tamano="sm" onClick={() => void contestar(c.id, false)}>No puedo</Boton>
                </div>
              )}
              {estaVivo(c.estado) && c.soy === "solicitante" && !c.lo_propuso_su_lider && (
                <Boton tamano="sm" className="self-start" onClick={() => void retirar(c.id)}>Retirarlo</Boton>
              )}
            </li>
          ))}
        </ul>
      )}

      {!abierto ? (
        <Boton className="self-start" onClick={() => setAbierto(true)} disabled={dias.length === 0}>
          Cambiar con una compañera
        </Boton>
      ) : (
        <div className="flex flex-col gap-3 rounded-control bg-hueso p-3">
          <div role="group" aria-label="Qué día" className="flex flex-col gap-1">
            <span className="text-sm text-taupe">¿Qué día?</span>
            <div className="flex flex-wrap gap-2">
              {dias.map((d) => (
                <Filtro key={d.fecha} tamano="sm" activo={d.fecha === fechaElegida}
                  onClick={() => { setFecha(d.fecha); setElegida(null); setCandidatas(null); }}>
                  {DIAS_CORTOS[dow(d.fecha)]} {diaMes(d.fecha)}
                  {d.esperado.entrada && d.esperado.salida ? ` · ${d.esperado.entrada}–${d.esperado.salida}` : ""}
                </Filtro>
              ))}
            </div>
          </div>
          <div role="group" aria-label="Con quién" className="flex flex-col gap-1">
            <span className="text-sm text-taupe">¿Con quién?</span>
            {candidatas === null ? <span className="text-sm text-taupe">Buscando…</span>
              : candidatas.length === 0 ? (
                <span className="text-sm text-taupe">
                  Ese día nadie de tu tienda tiene un turno distinto del mismo largo. Si lo necesitas, usa «Este día no me calza».
                </span>
              ) : (
                <div className="flex flex-wrap gap-2">
                  {candidatas.map((k) => (
                    <Filtro key={k.persona_id} tamano="sm" activo={k.persona_id === elegida} onClick={() => setElegida(k.persona_id)}>
                      {k.nombre} · {tramo(k.hora_entrada, k.hora_salida)}
                    </Filtro>
                  ))}
                </div>
              )}
          </div>
          <AreaTexto etiqueta="Un mensaje para ella (opcional)" value={comentario} maxLength={300}
            onChange={(e) => setComentario(e.target.value)} />
          <BannerAviso variante="informativo">
            Primero tu compañera dice si acepta; después lo aprueba tu líder de equipo. Hasta entonces, tu turno sigue igual.
          </BannerAviso>
          <div className="flex flex-wrap gap-2">
            <Boton variante="primario" onClick={() => void proponer()} disabled={!elegida || enviando}>
              {enviando ? "Enviando…" : "Pedírselo"}
            </Boton>
            <Boton onClick={() => setAbierto(false)}>Cancelar</Boton>
          </div>
        </div>
      )}
    </div>
  );
}

"use client";

import { useEffect, useState } from "react";
import type { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { hoyLima } from "@cayla-dynamic/shared";
import { Boton } from "@/components/ui/boton";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Cargando } from "@/components/cargando";
import { useToast } from "@/components/toast";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { EditorDisponibilidad, type EnvioDisponibilidad } from "@/components/disponibilidad/editor-disponibilidad";
import {
  desdeBloques, diaMes, resumenEnPalabras, type Bloque, type Motivo, type Ventana,
} from "@/lib/disponibilidad";

/**
 * «Mi disponibilidad», en «Lo mío», grupo Asistencia (0584).
 *
 * QUÉ PROMETE · que la colaboradora diga qué días u horas no puede trabajar,
 *               por qué y desde cuándo, y que lo mande a su líder de equipo.
 *               Muestra lo que está vigente (aprobado), lo que espera y lo que
 *               su líder quiere conversar. La jornada la ve, no la cambia.
 * QUÉ ASUME   · la RLS de la 0584 le deja leer sus `disponibilidades` y sus
 *               bloques; `fn_sede_ventana_semanal` le da la ventana de su sede.
 *
 * Si la 0584 todavía no está en la base (la tabla no existe), la sección lo dice
 * y no ofrece un formulario que no se podría guardar.
 */

type Cliente = ReturnType<typeof createAdminSupabaseClient>;

interface Fila {
  id: string;
  tipo: "total" | "parcial";
  motivo: Motivo | null;
  vigente_desde: string;
  vigente_hasta: string | null;
  estado: "enviada" | "aprobada" | "conversar" | "reemplazada" | "retirada";
  horario_fijo: boolean;
  creada_at: string;
  resuelta_at: string | null;
  respuesta: string | null;
  disponibilidad_bloques: Bloque[];
}

interface Datos {
  jornada: number | null;
  ventana: Ventana[];
  vigente: Fila | null;
  pendiente: Fila | null;
  conversar: Fila | null;
}

export function MiDisponibilidad({ supabase, personaId }: { supabase: Cliente; personaId: string }) {
  const toast = useToast();
  const [datos, setDatos] = useState<Datos | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [recarga, setRecarga] = useState(0);
  const [enviando, setEnviando] = useState(false);
  const [editando, setEditando] = useState(false);

  useEffect(() => {
    let vivo = true;
    void (async () => {
      const { data: yo } = await supabase.from("personas")
        .select("sede_base_id, jornada_semanal_horas").eq("id", personaId).maybeSingle();
      const [{ data: filas, error: err }, { data: ven }] = await Promise.all([
        supabase.from("disponibilidades")
          .select("id, tipo, motivo, vigente_desde, vigente_hasta, estado, horario_fijo, creada_at, resuelta_at, respuesta, disponibilidad_bloques(dia_semana, fecha, desde, hasta, estado)")
          .eq("persona_id", personaId)
          .in("estado", ["enviada", "aprobada", "conversar"])
          .order("creada_at", { ascending: false })
          .order("id", { ascending: false })
          .limit(10),
        yo?.sede_base_id
          ? supabase.rpc("fn_sede_ventana_semanal", { p_sede_id: yo.sede_base_id as string })
          : Promise.resolve({ data: [] }),
      ]);
      if (!vivo) return;
      if (err) {
        setError("Esta sección todavía no está lista. Vuelve a intentarlo más tarde.");
        return;
      }
      const lista = (filas as unknown as Fila[]) ?? [];
      const hoy = hoyLima();
      const aprobadas = lista.filter((f) => f.estado === "aprobada");
      setDatos({
        jornada: (yo?.jornada_semanal_horas as number | null) ?? null,
        ventana: ((ven as { dia: number; abre: string; cierra: string }[] | null) ?? []),
        // La que rige hoy; si todavía no empieza, la próxima.
        vigente: aprobadas.find((f) => f.vigente_desde <= hoy && (!f.vigente_hasta || f.vigente_hasta >= hoy))
          ?? aprobadas.sort((a, b) => a.vigente_desde.localeCompare(b.vigente_desde))[0] ?? null,
        pendiente: lista.find((f) => f.estado === "enviada") ?? null,
        conversar: lista.find((f) => f.estado === "conversar") ?? null,
      });
      setError(null);
    })();
    return () => { vivo = false; };
  }, [supabase, personaId, recarga]);

  if (error) return <BannerAviso variante="informativo">{error}</BannerAviso>;
  if (!datos) return <Cargando />;

  const enviar = async (e: EnvioDisponibilidad) => {
    setEnviando(true);
    const { error: err } = await supabase.rpc("fn_disponibilidad_enviar", {
      p_tipo: e.tipo, p_motivo: e.motivo, p_desde: e.desde, p_hasta: e.hasta,
      p_bloques: e.bloques as unknown as never, p_nota: e.nota,
    });
    setEnviando(false);
    if (err) {
      toast.avisar("error", mensajeDeError(err));
      return;
    }
    toast.avisar("ok", "Listo: se la mandaste a tu líder de equipo. Hasta que la apruebe, tus turnos siguen igual.");
    setEditando(false);
    setRecarga((n) => n + 1);
  };

  const retirar = async (id: string) => {
    const { error: err } = await supabase.rpc("fn_disponibilidad_retirar", { p_id: id });
    if (err) toast.avisar("error", mensajeDeError(err));
    else setRecarga((n) => n + 1);
  };

  const base = datos.pendiente ?? datos.vigente;
  const inicial = base
    ? { tipo: base.tipo, motivo: base.motivo, ...desdeBloques(base.disponibilidad_bloques) }
    : undefined;
  const mostrarEditor = editando || (!datos.vigente && !datos.pendiente);

  return (
    <div className="flex flex-col gap-4">
      <p className="text-sm text-taupe">
        {datos.jornada !== null
          ? <>Tu jornada: <strong className="text-tinta">{datos.jornada} h por semana</strong>. La fija Desarrollo Organizacional en tu contrato; aquí solo dices cuándo puedes.</>
          : "Tu jornada todavía no está registrada. La fija Desarrollo Organizacional; aquí solo dices cuándo puedes."}
      </p>

      {datos.conversar && !datos.pendiente && (
        <BannerAviso variante="advertencia" titulo="Tu líder de equipo quiere conversarlo">
          «{datos.conversar.respuesta}». Mientras tanto, tus turnos siguen como están.
        </BannerAviso>
      )}

      {datos.pendiente && (
        <BannerAviso variante="informativo" titulo="Esperando a tu líder de equipo">
          <div className="flex flex-col gap-2">
            <span>La mandaste el {diaMes(datos.pendiente.creada_at.slice(0, 10))}. Hasta que la apruebe, se usa la anterior.</span>
            {resumenEnPalabras(desdeBloques(datos.pendiente.disponibilidad_bloques).semana,
              desdeBloques(datos.pendiente.disponibilidad_bloques).excepciones).map((l) => <span key={l}>{l}</span>)}
            <Boton tamano="sm" className="self-start" onClick={() => void retirar(datos.pendiente!.id)}>Retirarla</Boton>
          </div>
        </BannerAviso>
      )}

      {datos.vigente && (
        <div className="flex flex-col gap-1 rounded-control bg-hueso p-3 text-sm">
          <span className="text-xs font-medium uppercase tracking-wide text-taupe">Lo que rige</span>
          {(datos.vigente.tipo === "total" ? ["Puedes cualquier día y hora."]
            : resumenEnPalabras(desdeBloques(datos.vigente.disponibilidad_bloques).semana,
                desdeBloques(datos.vigente.disponibilidad_bloques).excepciones)).map((l) => <span key={l}>{l}</span>)}
          <span className="text-taupe">
            Desde el {diaMes(datos.vigente.vigente_desde)}{datos.vigente.vigente_hasta ? ` hasta el ${diaMes(datos.vigente.vigente_hasta)}` : ", sin fecha de fin"}.
            {datos.vigente.horario_fijo ? " Tu horario es fijo: la sugerencia de turnos no lo mueve." : ""}
          </span>
        </div>
      )}

      {!mostrarEditor ? (
        <Boton className="self-start" onClick={() => setEditando(true)}>Cambiar mi disponibilidad</Boton>
      ) : (
        <div data-tour="mio-disponibilidad-editor">
          <EditorDisponibilidad
            inicial={inicial}
            ventana={datos.ventana}
            jornada={datos.jornada}
            textoBoton="Enviar a mi líder de equipo"
            enviando={enviando}
            onEnviar={(e) => void enviar(e)}
          />
        </div>
      )}
    </div>
  );
}

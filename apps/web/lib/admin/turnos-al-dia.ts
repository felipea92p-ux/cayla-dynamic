"use client";

// «TURNOS Y COBERTURA AL DÍA SIN RECARGAR» (2026-11-02, pedido de Felipe).
//
// El problema: cambiar el horario de una colaboradora no movía la grilla de
// cobertura hasta apretar F5. Pasaba por tres caminos distintos:
//
//   1. Dentro de la MISMA pantalla. «Para decidir» (Hacer permanente, Usar el
//      horario base, Quitar espejos) llama a fn_set_horario_semanal /
//      fn_quitar_turno y solo se recargaba a sí mismo: la sábana de la Vista
//      Integrada, la de Semana y la de Día seguían contando el horario viejo.
//      Eso lo arregla la propia página (turnos/page.tsx), avisándose entre sus
//      dos mitades.
//   2. Desde OTRA pestaña del mismo navegador (Horarios abierto al lado). Lo
//      cubre el canal de abajo: quien guarda avisa, y Turnos se pone al día en
//      el acto.
//   3. Desde OTRA persona (una líder de equipo en su sede). Ese aviso no llega
//      por el navegador: Turnos vuelve a leer cada minuto mientras está a la
//      vista, y apenas se vuelve a mirar la pestaña.
//
// Por qué no Supabase Realtime: exigiría sumar `turnos` y `horarios_asignados`
// a la publicación `supabase_realtime` (una migración que se pega a mano) y un
// canal abierto por cada pantalla de admin, para una lectura que ya es barata.
// Un minuto de demora para el cambio de otra persona es aceptable en una
// pantalla de planificación; si deja de serlo, Realtime es el paso siguiente.
//
// Solo dice CUÁNDO volver a leer. Qué se lee y cómo se cuenta la cobertura
// sigue siendo de la pantalla.

import { useEffect, useRef } from "react";

const CANAL = "cayla:turnos-y-horarios";

/** Cada cuánto vuelve a leer una pantalla a la vista, por si otra persona cambió algo. */
export const CADA_CUANTO_MS = 60_000;
/** Al volver a la pestaña, no se repite la lectura si la última fue hace menos que esto. */
export const MINIMO_ENTRE_LECTURAS_MS = 5_000;

// Identifica a ESTA pestaña: un aviso que sale de aquí no debe hacerla leer dos
// veces (la pantalla que guardó ya se pone al día por su cuenta).
const ESTA_PESTANA = Math.random().toString(36).slice(2);

interface Aviso { tipo: "cambio"; origen: string }

/** ¿Este mensaje del canal es un aviso de cambio que vino de otra pestaña? */
export function esAvisoDeOtraPestana(dato: unknown, estaPestana: string): boolean {
  if (typeof dato !== "object" || dato === null) return false;
  const a = dato as Partial<Aviso>;
  return a.tipo === "cambio" && typeof a.origen === "string" && a.origen !== estaPestana;
}

/**
 * ¿Toca volver a leer ahora? No con la pestaña escondida (nadie mira), no
 * mientras alguien escribe en un campo (pisaría lo que está tecleando —la meta
 * de cobertura se guarda al salir del campo—), y no dos veces seguidas.
 */
export function tocaPonerseAlDia(e: {
  visible: boolean;
  escribiendo: boolean;
  desdeUltimaMs: number;
  minimoMs?: number;
}): boolean {
  if (!e.visible || e.escribiendo) return false;
  return e.desdeUltimaMs >= (e.minimoMs ?? MINIMO_ENTRE_LECTURAS_MS);
}

let canal: BroadcastChannel | null | undefined;
function elCanal(): BroadcastChannel | null {
  if (canal !== undefined) return canal;
  canal = typeof BroadcastChannel === "undefined" ? null : new BroadcastChannel(CANAL);
  return canal;
}

/**
 * Avisa a las otras pestañas de este navegador que cambió un turno o un
 * horario. Se llama DESPUÉS de que la base respondió bien. Sin
 * BroadcastChannel (navegador viejo) no hace nada: queda la lectura por minuto.
 */
export function avisarCambioDeTurnos(): void {
  try {
    elCanal()?.postMessage({ tipo: "cambio", origen: ESTA_PESTANA } satisfies Aviso);
  } catch {
    // Un aviso que no sale no rompe nada: la otra pestaña se pone al día sola en un minuto.
  }
}

function hayCampoEnUso(): boolean {
  const el = document.activeElement;
  if (!el) return false;
  if (el instanceof HTMLTextAreaElement || el instanceof HTMLSelectElement) return true;
  if (el instanceof HTMLInputElement) return !["button", "checkbox", "radio", "submit", "reset"].includes(el.type);
  return el instanceof HTMLElement && el.isContentEditable;
}

/**
 * Mantiene una pantalla de turnos al día: lee cuando otra pestaña avisa un
 * cambio, cuando se vuelve a mirar la pestaña, y cada minuto mientras está a
 * la vista. `ponerseAlDia` tiene que ser una lectura EN SILENCIO: sin el
 * «Cargando…» que borra la grilla y sin avisos de error repetidos cada minuto.
 */
export function useTurnosAlDia(ponerseAlDia: () => void, activo = true): void {
  const ultima = useRef(ponerseAlDia);
  useEffect(() => { ultima.current = ponerseAlDia; });

  useEffect(() => {
    if (!activo) return;
    let leidoEn = Date.now(); // la pantalla acaba de cargar por su cuenta
    const intentar = (minimoMs?: number) => {
      const ahora = Date.now();
      if (!tocaPonerseAlDia({
        visible: document.visibilityState === "visible",
        escribiendo: hayCampoEnUso(),
        desdeUltimaMs: ahora - leidoEn,
        minimoMs,
      })) return;
      leidoEn = ahora;
      ultima.current();
    };

    // Un cambio avisado por otra pestaña se lee ya, sin esperar el mínimo.
    const c = typeof BroadcastChannel === "undefined" ? null : new BroadcastChannel(CANAL);
    const alAviso = (ev: MessageEvent) => { if (esAvisoDeOtraPestana(ev.data, ESTA_PESTANA)) intentar(0); };
    c?.addEventListener("message", alAviso);

    const alVolver = () => intentar();
    document.addEventListener("visibilitychange", alVolver);
    window.addEventListener("focus", alVolver);
    const t = window.setInterval(() => intentar(CADA_CUANTO_MS - 1_000), CADA_CUANTO_MS);

    return () => {
      c?.removeEventListener("message", alAviso);
      c?.close();
      document.removeEventListener("visibilitychange", alVolver);
      window.removeEventListener("focus", alVolver);
      window.clearInterval(t);
    };
  }, [activo]);
}

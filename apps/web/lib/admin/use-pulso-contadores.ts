"use client";

// El pulso con el que el marco del panel vuelve a preguntar sus contadores.
//
// QUÉ PROMETE
//   Un número entero que sube cuando los contadores del menú (Educación,
//   Ausencias, Incidencias, Bandeja, Info) deben volver a consultarse. Nunca
//   sube más de una vez por `VIGENCIA_CONTADORES_MS`, salvo que se pida a la
//   fuerza.
//
// QUÉ ASUME
//   Que el marco del panel vive entre pantallas (layout) y por eso su estado
//   sobrevive a navegar. Los efectos de los contadores dependen de este número
//   y no del `pathname`: así una navegación que cae dentro de la vigencia no
//   dispara nada, y —a diferencia de dejar el `pathname` y saltarse la
//   llamada— tampoco cancela una consulta en vuelo (el `vivo = false` de la
//   limpieza descartaba la respuesta, y la siguiente navegación, ya dentro de
//   la vigencia, no la repetía: el número se quedaba viejo).
//
// POR QUÉ SE CAMBIÓ (2026-10-24)
//   Antes cada contador se volvía a pedir en CADA navegación. Medido en el
//   panel local: entrar a cualquier módulo, incluso a Apariencia que casi no
//   tiene datos, lanzaba 57–107 consultas, la mayoría de la barra lateral —la
//   Bandeja junta nueve fuentes—, y en Equipo y Disciplina quedaban 5–6 rondas
//   en cadena. Con ~150 ms de ida y vuelta a Supabase eso es casi un segundo
//   de espera que ninguna pantalla se había ganado.
//
// LO QUE SE PIERDE Y COMO SE COMPENSA
//   El comentario de `nav.tsx` decía que refrescarse en cada navegación era el
//   único mecanismo de actualización, porque un contador de Incidencias en frío
//   es un reclamo sin leer con el periodo cerrándose. Ahora un número puede
//   tener hasta un minuto. Se compensa con dos cosas: volver a la pestaña
//   refresca (antes no), y resolver algo en la Bandeja sigue refrescando al
//   instante (ese camino no pasa por acá).

import { useEffect, useRef, useState } from "react";

/** Cuánto vale un contador sin volver a preguntarlo. */
export const VIGENCIA_CONTADORES_MS = 60_000;

/** ¿Ya venció lo último que se consultó? `ultimo` es la hora de esa consulta. */
export function vencioElContador(ultimo: number | null, ahora: number, vigenciaMs = VIGENCIA_CONTADORES_MS): boolean {
  return ultimo === null || ahora - ultimo >= vigenciaMs;
}

export function usePulsoContadores(pathname: string, vigenciaMs = VIGENCIA_CONTADORES_MS): number {
  const [pulso, setPulso] = useState(0);
  // La hora de la última consulta. `null` hasta que el marco se monta: los
  // efectos de los contadores ya corren solos en el montaje, así que esa
  // primera vez solo se anota la hora y NO se sube el pulso (subirlo
  // duplicaría las 50 consultas del arranque).
  const ultimo = useRef<number | null>(null);

  useEffect(() => {
    const ahora = Date.now();
    if (ultimo.current === null) {
      ultimo.current = ahora;
      return;
    }
    if (!vencioElContador(ultimo.current, ahora, vigenciaMs)) return;
    ultimo.current = ahora;
    setPulso((n) => n + 1);
  }, [pathname, vigenciaMs]);

  // Volver a la pestaña después de un rato también cuenta como «navegar».
  useEffect(() => {
    function alVolver() {
      if (document.visibilityState !== "visible") return;
      const ahora = Date.now();
      if (!vencioElContador(ultimo.current, ahora, vigenciaMs)) return;
      ultimo.current = ahora;
      setPulso((n) => n + 1);
    }
    document.addEventListener("visibilitychange", alVolver);
    return () => document.removeEventListener("visibilitychange", alVolver);
  }, [vigenciaMs]);

  return pulso;
}

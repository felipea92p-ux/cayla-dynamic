"use client";

import { useCallback, useEffect, useRef, useState, type SetStateAction } from "react";

/**
 * Un filtro que se acuerda de la última vez — sin esto, cada pantalla de
 * lista empezaba en blanco y quien la revisa todas las mañanas rearmaba a
 * mano el mismo filtro. Vive en localStorage: es por navegador, no por
 * persona en la base, así que dos personas que comparten un equipo no se
 * pisan el filtro de la otra, y nadie necesita una migración para esto.
 *
 * SOLO PARA PREFERENCIAS DE VISTA (sede, área, un casillero) — NUNCA para
 * texto de búsqueda ni rangos de fecha. Esos son de esta visita, no de "cómo
 * miro siempre esta pantalla": reabrir Incidencias el mes que viene y
 * encontrarse con el rango de fechas de la vez pasada confundiría más de lo
 * que ayuda. Esa distinción se decide en cada pantalla, no acá.
 *
 * Es la misma firma que `useState`, a propósito: cambiar un filtro de
 * "no se guarda" a "se guarda" es una sola línea.
 *
 * ARRANCA SIEMPRE EN `inicial` —en el servidor y en el primer render del
 * cliente, para que los dos coincidan— y recién montado, si hay algo
 * guardado, lo aplica. Ese salto de un render es el precio de no arriesgar
 * un error de hidratación (leer localStorage antes de montar exige `window`,
 * que no existe en el servidor).
 *
 * SOLO SE ESCRIBE LO QUE LA PERSONA ELIGE, nunca el valor con que arranca
 * (2026-11-07). Hasta entonces un efecto guardaba `valor` en cada render,
 * también el primero: al montar escribía `inicial` encima de lo guardado,
 * antes de que la lectura alcanzara a aplicarse. En producción el siguiente
 * render lo arreglaba, pero en desarrollo React monta dos veces (modo
 * estricto) y el segundo montaje leía ese `inicial`: ninguna preferencia de
 * ninguna pantalla sobrevivía a una recarga en local. Se midió en Turnos y en
 * Correcciones —«semana» volvía a la vista por rol, un resumen plegado volvía
 * abierto— y confundía cada revisión de un cambio de diseño.
 * Ahora el setter marca que hubo una elección y el efecto escribe solo eso.
 * Sin clave guardada, la pantalla arranca en `inicial`, igual que antes.
 */
export function useFiltroGuardado<T>(clave: string, inicial: T) {
  const llave = `dynamic.filtro.${clave}`;
  const [valor, setValorInterno] = useState<T>(inicial);
  // true entre que la pantalla llama a setValor y el efecto lo guarda. Un ref y no estado: no debe provocar un render.
  const elegido = useRef(false);

  useEffect(() => {
    try {
      const guardado = window.localStorage.getItem(llave);
      // eslint-disable-next-line react-hooks/set-state-in-effect
      if (guardado !== null) setValorInterno(JSON.parse(guardado));
    } catch {
      // localStorage puede fallar (modo privado, cuota llena) — el filtro
      // sigue funcionando, solo no se acuerda entre visitas.
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (!elegido.current) return;
    elegido.current = false;
    try {
      window.localStorage.setItem(llave, JSON.stringify(valor));
    } catch {
      // mismo caso que arriba: sin espacio o sin permiso, no es un error que
      // deba interrumpir a nadie.
    }
  }, [llave, valor]);

  const setValor = useCallback((v: SetStateAction<T>) => {
    elegido.current = true;
    setValorInterno(v);
  }, []);

  return [valor, setValor] as const;
}

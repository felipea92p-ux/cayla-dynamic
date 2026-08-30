"use client";

import { useEffect, useState } from "react";

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
 */
export function useFiltroGuardado<T>(clave: string, inicial: T) {
  const llave = `dynamic.filtro.${clave}`;
  const [valor, setValor] = useState<T>(inicial);

  useEffect(() => {
    try {
      const guardado = window.localStorage.getItem(llave);
      // eslint-disable-next-line react-hooks/set-state-in-effect
      if (guardado !== null) setValor(JSON.parse(guardado));
    } catch {
      // localStorage puede fallar (modo privado, cuota llena) — el filtro
      // sigue funcionando, solo no se acuerda entre visitas.
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    try {
      window.localStorage.setItem(llave, JSON.stringify(valor));
    } catch {
      // mismo caso que arriba: sin espacio o sin permiso, no es un error que
      // deba interrumpir a nadie.
    }
  }, [llave, valor]);

  return [valor, setValor] as const;
}

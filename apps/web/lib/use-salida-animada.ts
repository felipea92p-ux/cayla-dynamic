"use client";

// Un panel que se abre ENCIMA de la pantalla —el cajón del menú del panel, el
// del menú de «Lo mío»— se desmonta al cerrarse (`if (!abierto) return null`),
// y un elemento que ya no está no puede animar su salida: la CSS no tiene a
// qué aplicarle el `translateX(-100%)`. Hasta el 2026-09-11 los dos cajones
// entraban y salían de golpe por eso.
//
// Este hook resuelve la mitad que la CSS no puede: mantiene el cajón montado
// lo que dura su animación de salida, y recién entonces lo suelta. Devuelve
// dos cosas —si hay que dibujarlo y si está yéndose— para que el componente
// elija la clase (`cajon-entra` o `cajon-sale`, en globals.css) y deje el
// cajón inerte mientras se va: 200 ms en los que todavía está en el DOM pero
// ya nadie debería poder tocarlo ni tabular a él.
//
// La espera se salta si quien mira pidió menos movimiento. No es un detalle:
// la CSS pone `animation: none` en ese caso, así que sin esta comprobación el
// cajón se quedaría 200 ms quieto y entero después de tocar «cerrar», que se
// siente como un botón que responde tarde. Se pregunta en el momento de
// cerrar y no una vez al montar, por la misma razón que `useNavColapsado`
// consulta el media query al hacer clic: la preferencia puede cambiar con la
// pestaña abierta.
//
// Lo que NO hace: manejar el foco. Eso sigue en `useFocoAtrapado`, que mira
// `abierto` y no `montado`, así que el foco vuelve a la hamburguesa en cuanto
// se pide cerrar, sin esperar a que termine de irse.

import { useEffect, useState } from "react";

const CONSULTA_MENOS_MOVIMIENTO = "(prefers-reduced-motion: reduce)";

export function useSalidaAnimada(
  abierto: boolean,
  /** Lo que dura la animación de salida en la CSS. Tiene que coincidir con ella. */
  duracionMs: number,
): {
  /** Si hay que dibujar el panel: abierto, o cerrándose todavía. */
  montado: boolean;
  /** Si está en los milisegundos de irse: ya no abierto, pero todavía dibujado. */
  saliendo: boolean;
} {
  const [montado, setMontado] = useState(abierto);

  // Al abrir se monta EN ESTE MISMO render: ajustar el estado durante el render
  // —el patrón que React documenta y que `nav.tsx` ya usa con
  // `pathnameAnterior`—, y no en un efecto, que llegaría un fotograma tarde y
  // pintaría un cajón "abierto" que todavía no existe.
  if (abierto && !montado) setMontado(true);

  useEffect(() => {
    if (abierto || !montado) return;
    const espera = window.matchMedia(CONSULTA_MENOS_MOVIMIENTO).matches ? 0 : duracionMs;
    const temporizador = window.setTimeout(() => setMontado(false), espera);
    // Si lo vuelven a abrir antes de que termine de irse, la salida se cancela y
    // el cajón sigue montado: sin esta limpieza, el temporizador viejo lo
    // desmontaría por debajo del cajón recién abierto.
    return () => window.clearTimeout(temporizador);
  }, [abierto, montado, duracionMs]);

  return { montado, saliendo: montado && !abierto };
}

"use client";

// Un <textarea> que crece con lo que se escribe, en vez de esconder el texto
// detrás de una barra o —peor— detrás del borde derecho de un <input>.
//
// Nació el 2026-09-04 en Contratos: los campos del Anexo I del convenio de
// prácticas (área de destino, objetivo formativo, hitos de evaluación) eran
// <input> de una sola línea, y un objetivo de dos renglones «se iba de largo»:
// en pantalla solo se veía el final, y lo que se firma tiene que poderse leer
// entero antes de generarlo. Altura mínima = `rows`; sin máximo a propósito.
//
// Mide con scrollHeight, y vuelve a medir cuando cambia el valor Y cuando
// cambia el ancho (ventana más angosta, zoom del navegador, iPad girado): el
// texto se reparte en más renglones y una altura fija en px los escondería sin
// barra ni asa — el mismo síntoma que este componente existe para evitar.
//
// No usa la propiedad CSS `field-sizing: content` porque solo llega en Safari
// 26.2, y las Mac mini de las sedes y el equipo de quien administra no se
// actualizan a la vez ni bajo control de nadie. Medir por JS funciona en todos.
//
// El chrome (borde, radio, fondo, tipografía) es a propósito el mismo que
// Campo: antes cada uso escribía su propia cadena de clases a mano y ya
// divergía de un input normal — un formulario con Campo para "Nombre" y
// AreaTexto para "Objetivo formativo" mostraba dos cajas de campo distintas
// una al lado de la otra. `etiqueta` y `error` copian el mismo contrato que
// Campo por la misma razón. Si el día de mañana esa cadena base se vuelve a
// separar entre los dos archivos, hay que juntarla en una constante
// compartida — hoy vive repetida a propósito porque este componente solo
// puede tocar este archivo.
//
// Y ya se separó una vez. El 2026-09-07 este componente copió la etiqueta de
// Campo el mismo día en que Campo la pasaba de mayúsculas con tracking a caja
// normal: se llevó la versión vieja. Durante tres semanas cada formulario que
// mezclaba los dos —Anuncios, la medida de un caso, las categorías de la
// política salarial— mostró dos rótulos distintos uno encima del otro, y la
// pantalla del Archivo (en su rama, aún sin fusionar) terminó escribiendo su
// propio <label> para no usar `etiqueta`.
// Desde el 2026-10-01 rótulo y separación son los de Campo, clase por clase.

import { useLayoutEffect, useRef } from "react";
import type { TextareaHTMLAttributes } from "react";
import { cx } from "./cx";

type Props = Omit<TextareaHTMLAttributes<HTMLTextAreaElement>, "value"> & {
  value: string;
  /** Rótulo arriba del campo, igual que en Campo. Si no se pasa (los usos de
   * hoy en Contratos, que ya envuelven el campo en su propio <label>), el
   * textarea sale suelto — envolverlo siempre en un <label> propio anidaría
   * dos <label> uno dentro del otro donde quien llama ya puso el suyo. */
  etiqueta?: string;
  /** Mensaje de error, con borde rojo a juego. No valida por sí solo. */
  error?: string;
};

// Misma cadena base que Campo usa para <input>: mismo radio, mismo fondo,
// mismo tamaño de texto. `resize-none overflow-hidden` es lo propio de este
// componente (el alto lo pone el JS de abajo, no el usuario arrastrando).
//
// El tamaño también se había quedado atrás: aquí decía `text-sm` a secas
// cuando Campo ya usaba `text-base sm:text-sm`, que es lo que evita que Safari
// de iOS agrande la página al enfocar un control con letra menor a 16px (y no
// la vuelva a achicar). Un <textarea> dispara ese zoom igual que un <input>, y
// «Lo mío → Responder» se escribe sobre todo desde el teléfono.
const CHROME_BASE =
  "w-full resize-none overflow-hidden rounded-control border border-sand bg-hueso px-3 py-2 text-base text-tinta transition-colors duration-150 placeholder:text-taupe/60 sm:text-sm";

function ajustarAltura(el: HTMLTextAreaElement) {
  // "auto" primero, para que al BORRAR texto la altura también baje: si no,
  // scrollHeight nunca es menor que la altura ya fijada.
  el.style.height = "auto";
  // scrollHeight no incluye los bordes; con box-sizing: border-box (el
  // preflight de Tailwind) hay que sumarlos o la caja queda 2 px corta.
  const bordes = el.offsetHeight - el.clientHeight;
  el.style.height = `${el.scrollHeight + bordes}px`;
}

export function AreaTexto({ value, rows = 2, etiqueta, error, id, className, ...rest }: Props) {
  const ref = useRef<HTMLTextAreaElement>(null);

  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    ajustarAltura(el);
  }, [value]);

  useLayoutEffect(() => {
    const el = ref.current;
    if (!el || typeof ResizeObserver === "undefined") return;
    let anchoPrevio = el.clientWidth;
    const observador = new ResizeObserver(() => {
      // Solo el ANCHO: la altura la cambia este mismo código y reaccionar a
      // ella sería medirse a sí mismo en bucle.
      if (el.clientWidth === anchoPrevio) return;
      anchoPrevio = el.clientWidth;
      ajustarAltura(el);
    });
    observador.observe(el);
    return () => observador.disconnect();
  }, []);

  const campo = (
    <textarea
      ref={ref}
      id={id}
      rows={rows}
      value={value}
      className={cx(CHROME_BASE, error && "border-rojo", className)}
      {...rest}
    />
  );

  if (!etiqueta && !error) return campo;

  return (
    <label className="flex flex-col gap-1">
      {etiqueta && <span className="text-sm text-taupe">{etiqueta}</span>}
      {campo}
      {error && <span className="text-xs text-rojo">{error}</span>}
    </label>
  );
}

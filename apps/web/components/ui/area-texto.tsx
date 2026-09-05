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

import { useLayoutEffect, useRef } from "react";
import type { TextareaHTMLAttributes } from "react";
import { cx } from "./cx";

type Props = Omit<TextareaHTMLAttributes<HTMLTextAreaElement>, "value"> & {
  value: string;
};

function ajustarAltura(el: HTMLTextAreaElement) {
  // "auto" primero, para que al BORRAR texto la altura también baje: si no,
  // scrollHeight nunca es menor que la altura ya fijada.
  el.style.height = "auto";
  // scrollHeight no incluye los bordes; con box-sizing: border-box (el
  // preflight de Tailwind) hay que sumarlos o la caja queda 2 px corta.
  const bordes = el.offsetHeight - el.clientHeight;
  el.style.height = `${el.scrollHeight + bordes}px`;
}

export function AreaTexto({ value, rows = 2, className, ...rest }: Props) {
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

  return (
    <textarea
      ref={ref}
      rows={rows}
      value={value}
      className={cx("resize-none overflow-hidden", className)}
      {...rest}
    />
  );
}

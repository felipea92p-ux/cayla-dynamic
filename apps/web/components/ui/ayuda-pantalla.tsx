"use client";

// El «ⓘ» de una pantalla: junto a su descripción corta, abre una ventana con el detalle de cómo se
// usa. Nació de ver que cada pantalla de Asistencia guardaba su explicación de otra forma —un
// párrafo de cuatro líneas bajo el título (Ausencias), un globo nativo que no se ve en el celular
// (Horarios), un botón «Cómo se detectan» que desplegaba una tarjeta (Incidencias), una leyenda
// plegada (Desempeño)— y en ninguna se sabía dónde buscar la ayuda.
//
// La regla que deja: la descripción dice, en UNA línea, para qué sirve la pantalla y qué se toca
// primero; todo lo demás va aquí. El formato de la ventana es el de «Reglas y umbrales» de
// Disciplina (término a la izquierda, explicación a la derecha, y la referencia legal debajo).
//
// Va AL FINAL de la descripción, como en Retail (docs/ayuda-retail-prototipo-2026-10-19.html). El botón es un botón de verdad (lector de pantalla, teclado, y se ve en el celular donde un
// `title` no existe) y el nombre accesible dice a qué pantalla pertenece la ayuda.

import { useState, type ReactNode } from "react";
import { Info } from "lucide-react";
import { Boton } from "./boton";
import { cx } from "./cx";
import { Modal } from "./modal";

export type SeccionAyuda = {
  titulo: string;
  texto: ReactNode;
  /** La fuente, en una línea chica: «RIT 19.2», «Ley 28518, art. 30». */
  referencia?: string;
};

/**
 * El botón ⓘ solo, para las pantallas que ya tienen su propia ventana de ayuda (Disciplina,
 * Objetivos, Seguros): hasta el 2026-10-19 cada una dibujaba el suyo —un enlace «Ver reglas y
 * umbrales», un botón con icono y texto en rojo, un anillo de 24 px— y ninguna se parecía.
 *
 * Anillo fino de 18 px (trazo 1.6), el que eligió Felipe entre siete dibujos en
 * docs/ayuda-icono-prototipo-2026-10-19.html. El dibujo es chico a propósito —no compite con el
 * título—, pero el área de toque es de 32 px.
 */
export function BotonAyuda({ onClick, etiqueta, className }: { onClick: () => void; etiqueta: string; className?: string }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={etiqueta}
      title={etiqueta}
      aria-haspopup="dialog"
      className={cx(
        "-my-2 inline-flex size-8 shrink-0 items-center justify-center rounded-pildora text-taupe transition-colors duration-150 hover:bg-sand/60 hover:text-tinta",
        className,
      )}
    >
      <Info className="size-[18px]" strokeWidth={1.6} aria-hidden />
    </button>
  );
}

export function AyudaPantalla({
  titulo,
  intro,
  secciones,
  children,
}: {
  /** El nombre de la ventana: «Cómo funciona Correcciones». */
  titulo: string;
  /** Una o dos frases: lo que esta pantalla es y lo que NO hace. */
  intro?: ReactNode;
  secciones?: SeccionAyuda[];
  /** Contenido libre debajo de las secciones (una leyenda, por ejemplo). */
  children?: ReactNode;
}) {
  const [abierta, setAbierta] = useState(false);
  return (
    <>
      <BotonAyuda etiqueta={titulo} onClick={() => setAbierta(true)} />
      <Modal abierto={abierta} onCerrar={() => setAbierta(false)} titulo={titulo} ancho="lg">
        <div className="grid gap-4 text-sm">
          {intro && <p className="text-taupe">{intro}</p>}
          {secciones && secciones.length > 0 && (
            <dl className="grid gap-3">
              {secciones.map((s) => (
                <div key={s.titulo} className="grid gap-0.5 border-t border-sand pt-3 sm:grid-cols-[8rem_1fr] sm:gap-4">
                  <dt className="font-medium text-tinta">{s.titulo}</dt>
                  <dd className="text-taupe">
                    {s.texto}
                    {s.referencia && <span className="mt-0.5 block text-xs">{s.referencia}</span>}
                  </dd>
                </div>
              ))}
            </dl>
          )}
          {children}
          <div className="flex justify-end">
            <Boton variante="primario" onClick={() => setAbierta(false)}>Entendido</Boton>
          </div>
        </div>
      </Modal>
    </>
  );
}

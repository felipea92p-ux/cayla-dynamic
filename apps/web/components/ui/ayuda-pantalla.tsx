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
// El botón es un botón de verdad (lector de pantalla, teclado, y se ve en el celular donde un
// `title` no existe) y el nombre accesible dice a qué pantalla pertenece la ayuda.

import { useState, type ReactNode } from "react";
import { Info } from "lucide-react";
import { Boton } from "./boton";
import { Modal } from "./modal";

export type SeccionAyuda = {
  titulo: string;
  texto: ReactNode;
  /** La fuente, en una línea chica: «RIT 19.2», «Ley 28518, art. 30». */
  referencia?: string;
};

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
      <button
        type="button"
        onClick={() => setAbierta(true)}
        aria-label={titulo}
        aria-haspopup="dialog"
        className="-my-1 inline-flex size-8 shrink-0 items-center justify-center rounded-pildora text-taupe transition-colors duration-150 hover:bg-sand/40 hover:text-tinta"
      >
        <Info className="size-5" strokeWidth={1.6} aria-hidden />
      </button>
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

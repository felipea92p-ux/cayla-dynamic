// El título de una pantalla con vidrio, el de Retail (components/ui/EncabezadoPagina.tsx): arriba la línea de dónde y cuándo, después el título
// en 46 px (36 en el teléfono). Recibe lo mismo que `CabeceraPagina`, que es quien lo elige según el interruptor.
//
// QUÉ VA A LA VISTA Y QUÉ NO
//   Una frase (texto) va al «?». Lo que no es una frase —«en vivo», un rango de fechas, un dato que cambia— se queda a la vista: la frase explica la
//   pantalla, pero un dato sirve para decidir, y tenerlo que abrir para verlo sería peor que el párrafo que se quería evitar.

import type { ReactNode } from "react";
import { AyudaCabecera } from "@/components/vidrio/ayuda-cabecera";

export function CabeceraPaginaVidrio({
  sobretitulo,
  titulo,
  descripcion,
  ayuda,
  accion,
}: {
  sobretitulo?: ReactNode;
  titulo: string;
  descripcion?: ReactNode;
  ayuda?: ReactNode;
  accion?: ReactNode;
}) {
  const frase = typeof descripcion === "string" ? descripcion : null;
  const dato = typeof descripcion === "string" ? null : descripcion;
  return (
    <div className="vidrio-cabecera mb-5 flex flex-wrap items-center justify-between gap-x-10 gap-y-4 sm:mb-8">
      <div className="min-w-0">
        {sobretitulo ? (
          <p className="vidrio-sobretitulo flex min-w-0 items-center gap-3">
            <span aria-hidden className="h-px w-8 shrink-0 bg-taupe" />
            <span className="min-w-0">{sobretitulo}</span>
          </p>
        ) : null}
        {/* receta-propia: esta ES la cabecera de pantalla; CabeceraPagina la elige con el interruptor encendido */}
        <h1 className="vidrio-titulo text-tinta">
          {titulo}
          {frase ? <AyudaCabecera nombre={titulo}>{frase}</AyudaCabecera> : null}
          {ayuda ? <span className="vidrio-titulo-ayuda">{ayuda}</span> : null}
        </h1>
        {dato ? <div className="mt-2 max-w-2xl text-sm text-taupe">{dato}</div> : null}
      </div>
      {accion ? <div className="max-w-full shrink-0">{accion}</div> : null}
    </div>
  );
}

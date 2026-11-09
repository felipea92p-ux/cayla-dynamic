"use client";

// La flecha de volver arriba (2026-11-09). Nació en «Cómo funciona la disciplina»: en un teléfono esa guía
// mide más de una docena de pantallas, y el índice que lleva a cada sección vive arriba de todo. Sin ella,
// volver al índice era deslizar con el dedo una y otra vez.
//
// QUÉ PROMETE · aparece abajo a la derecha cuando ya bajaste más de una pantalla —arriba de todo no hay a
//               dónde subir, y un botón que no hace nada enseña a no tocarlo— y al tocarla vuelve al
//               principio. Con `destino` deja el foco en ese elemento, para que quien navega con teclado o
//               con lector de pantalla siga desde arriba y no desde un botón que acaba de desaparecer.
// QUÉ ASUME   · que la pantalla se desplaza en la ventana, como todas las de Lo mío. Dentro de una caja
//               con su propio scroll no aparecería nunca. Y que `destino`, si se da, existe y acepta foco
//               (`tabIndex={-1}` en un título).
// NO HACE     · animarse por su cuenta: el viaje es suave solo si la persona encendió las animaciones
//               (`prefiereQuieto()`, lib/vidrio-movimiento.ts); si no, llega de una vez.
//
// Abajo a la DERECHA y no a la izquierda: es donde la busca el pulgar y donde la pone casi todo sitio.
// Los avisos (`useToast`) salen en esa misma esquina y, por estar más arriba en capas (z-60 contra z-40),
// la tapan los segundos que duran. Esta guía no guarda nada, así que no le pasa; una pantalla que guarde
// mucho y quiera la flecha tiene que mirar eso antes.

import { useEffect, useState } from "react";
import { ArrowUp } from "lucide-react";
import { BotonIcono } from "@/components/ui/boton-icono";
import { prefiereQuieto } from "@/lib/vidrio-movimiento";

export function VolverArriba({ destino }: { destino?: string }) {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    // Una comparación por evento: React no vuelve a dibujar si el booleano no cambió, así que no hace falta
    // espaciar las lecturas.
    const medir = () => setVisible(window.scrollY > window.innerHeight);
    medir();
    window.addEventListener("scroll", medir, { passive: true });
    window.addEventListener("resize", medir);
    return () => {
      window.removeEventListener("scroll", medir);
      window.removeEventListener("resize", medir);
    };
  }, []);

  if (!visible) return null;

  function subir() {
    // «instant» y no «auto»: «auto» obedece al CSS de la página, y una regla `scroll-behavior: smooth` que
    // alguien agregue mañana volvería suave el viaje de quien pidió quietud.
    window.scrollTo({ top: 0, behavior: prefiereQuieto() ? "instant" : "smooth" });
    if (destino) document.getElementById(destino)?.focus({ preventScroll: true });
  }

  return (
    <div className="fixed bottom-[max(1rem,env(safe-area-inset-bottom))] right-[max(1rem,env(safe-area-inset-right))] z-40 print:hidden">
      <BotonIcono etiqueta="Volver arriba" icono={<ArrowUp aria-hidden />} tamano="lg" onClick={subir} className="shadow-md" />
    </div>
  );
}

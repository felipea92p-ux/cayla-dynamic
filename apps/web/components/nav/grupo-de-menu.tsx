"use client";

// Un grupo de un menú lateral: su título, que lo pliega, y la lista de
// renglones que pliega. Lo usan los DOS menús de la casa —el del panel
// (`panel-navegacion.tsx`) y el de «Lo mío» (`menu-detalle.tsx`)— y existe
// para que la regla de cómo se pliega un grupo viva en un solo sitio.
//
// QUÉ PROMETE
//   Dibuja el título y esconde los renglones cuando `cerrado`, según el modo.
//   No sabe qué hay dentro: el panel le pasa enlaces y «Lo mío» botones. Ni
//   decide qué grupos están cerrados ni lo recuerda: eso llega de fuera
//   (`useGruposCerrados`), porque cada menú tiene su propia memoria.
//
// POR QUÉ SE SEPARÓ (2026-10-06)
//   Hasta entonces solo el panel tenía grupos, y su título vivía dentro de
//   `panel-navegacion.tsx`. Cuando «Lo mío» pasó a tener grupos que se cierran,
//   copiarlo habría dejado dos versiones de la regla más delicada de todas —la
//   de abajo, «en rail los grupos no se contraen»— y en este repositorio dos
//   copias de algo ya terminaron una vez con una atrás sin que nada fallara
//   (los contadores del menú, escritos a mano seis veces).

import { useId, type ReactNode } from "react";
import { ChevronDown } from "lucide-react";
import { cx } from "@/components/ui/cx";

/** Cómo se dibuja el menú. Ver `lib/use-nav-colapsado.ts`. */
export type ModoMenu = "auto" | "rail" | "ancho" | "cajon";

// `ocultoAlCerrar` es la clase que se le pone a la lista de un grupo contraído,
// y es donde vive la única decisión no obvia de todo esto: EN RAIL LOS GRUPOS NO
// SE CONTRAEN. En rail no hay títulos —solo iconos y una raya entre grupos—, así
// que no habría dónde volver a pulsar para expandirlos: quien contrajera
// «Nómina» en ancho y después angostara la ventana se quedaría sin Planilla
// hasta ensancharla de nuevo. Por eso en `rail` la clase es vacía (nunca
// esconde) y en `auto` es `xl:hidden`: esconde donde el título se ve, y no
// donde no.
const CLASES: Record<ModoMenu, { titulo: string; separador: string; ocultoAlCerrar: string }> = {
  // Sin elegir: la CSS decide. Rail por debajo de 1280px, ancho a partir de ahí.
  auto: { titulo: "hidden xl:flex", separador: "block xl:hidden", ocultoAlCerrar: "xl:hidden" },
  rail: { titulo: "hidden", separador: "block", ocultoAlCerrar: "" },
  ancho: { titulo: "flex", separador: "hidden", ocultoAlCerrar: "hidden" },
  cajon: { titulo: "flex", separador: "hidden", ocultoAlCerrar: "hidden" },
};
// `titulo` dice `flex` y no `block`, y el botón NO lleva su propio `flex`: dos
// clases de `display` en el mismo elemento las decide el orden del CSS, no el
// de la línea. Hasta el 2026-10-06 el botón decía `flex` y el modo `xl:block`,
// ganaba `block`, y como Tailwind pone `display: block` a todo `svg`, la flecha
// caía en una segunda línea debajo del título: cada título medía 43 px en vez
// de 29, en el panel desde que sus grupos se pliegan. Medido en el navegador.

export function GrupoDeMenu({
  etiqueta,
  modo,
  cerrado,
  contieneActivo,
  onAlternar,
  separado,
  children,
}: {
  /** Sin etiqueta, el grupo es solo su lista: es el primero de cada menú. */
  etiqueta?: string;
  modo: ModoMenu;
  cerrado: boolean;
  /** Si la pantalla o sección en la que estás vive en este grupo. */
  contieneActivo: boolean;
  onAlternar: (etiqueta: string) => void;
  /** Todos menos el primero llevan un respiro arriba. */
  separado: boolean;
  children: ReactNode;
}) {
  const c = CLASES[modo];
  // El sidebar y el cajón montan el menú a la vez, así que un id fijo saldría
  // duplicado en el documento y `aria-controls` apuntaría a cualquiera de los
  // dos. `useId` da uno distinto por grupo y por instancia.
  const idLista = useId();

  return (
    <div className={separado ? "mt-1" : undefined}>
      {etiqueta ? (
        <>
          <button
            type="button"
            onClick={() => onAlternar(etiqueta)}
            aria-expanded={!cerrado}
            aria-controls={idLista}
            className={cx(
              "etiqueta w-full items-center gap-1 rounded-control px-3 pb-0.5 pt-2.5 text-left transition-colors duration-150 hover:text-tinta",
              // Si estás dentro de un grupo contraído, el título se pinta como
              // se pintan los renglones activos. Sin esto, contraer el grupo en
              // el que estás borra de la pantalla la única señal de dónde estás
              // — y la alternativa (volver a abrirlo solo) haría que el botón
              // no hiciera nada cuando más natural es pulsarlo.
              cerrado && contieneActivo ? "text-tinta" : "text-taupe",
              c.titulo,
            )}
          >
            <span className="truncate">{etiqueta}</span>
            <ChevronDown
              size={14}
              strokeWidth={2}
              aria-hidden
              className={cx(
                "ml-auto shrink-0 transition-transform duration-150 motion-reduce:transition-none",
                cerrado && "-rotate-90",
              )}
            />
          </button>
          {/* En rail no cabe el título del grupo, pero la separación sí tiene
              que verse: sin ella son treinta iconos en una columna sin ninguna
              jerarquía, que es justo el problema del que venimos. */}
          <span aria-hidden className={cx("mx-3 my-2 h-px bg-sand", c.separador)} />
        </>
      ) : null}

      <div id={idLista} className={cx("grid gap-0.5", cerrado && c.ocultoAlCerrar)}>
        {children}
      </div>
    </div>
  );
}

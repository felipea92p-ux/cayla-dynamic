"use client";

// La lista de grupos del menú, dibujada. Es UN componente para los tres
// sitios donde aparece —sidebar ancho, rail de iconos y cajón de teléfono—
// porque antes eran dos copias y los contadores se habían escrito a mano seis
// veces entre las dos: cambiar una ruta dejaba cinco copias atrás sin que
// nada fallara.
//
// El modo "auto" es el que hace que esto no parpadee al cargar: en vez de
// preguntar el ancho de la ventana con JavaScript (que en el servidor no
// existe), deja que la CSS decida con `xl:`. Ver `lib/use-nav-colapsado.ts`.

import { useId } from "react";
import Link from "next/link";
import { ChevronDown } from "lucide-react";
import { esActivo, type Contador, type Grupo } from "@/app/(admin)/admin/nav-items";
import { cx } from "@/components/ui/cx";

export type Modo = "auto" | "rail" | "ancho" | "cajon";

export type Contadores = Record<Contador, { n: number; titulo: string }>;

// Cada modo pinta las mismas cinco piezas con distintas clases. Tenerlas en un
// mapa y no en `modo === "rail" ? … : …` repartido por el JSX es lo que deja
// leer de un vistazo en qué se diferencian.
// `ocultoAlCerrar` es la clase que se le pone a la lista de un grupo contraído,
// y es donde vive la única decisión no obvia de todo esto: EN RAIL LOS GRUPOS NO
// SE CONTRAEN. En rail no hay títulos —solo iconos y una raya entre grupos—, así
// que no habría dónde volver a pulsar para expandirlos: quien contrajera
// «Nómina» en ancho y después angostara la ventana se quedaría sin Planilla
// hasta ensancharla de nuevo. Por eso en `rail` la clase es vacía (nunca
// esconde) y en `auto` es `xl:hidden`: esconde donde el título se ve, y no
// donde no.
const CLASES: Record<Modo, {
  enlace: string;
  etiqueta: string;
  titulo: string;
  separador: string;
  pildora: string;
  punto: string;
  ocultoAlCerrar: string;
}> = {
  // Sin elegir: la CSS decide. Rail por debajo de 1280px, ancho a partir de ahí.
  //
  // El `py-1.5` de los modos anchos no es capricho: con treinta renglones, cada
  // 4px de más por fila son 120px de scroll. Medido con `py-2` daba 1363px de
  // alto contra ~870 de visible en un portátil, o sea Configuración quedaba
  // lejos. En rail se queda en `py-2` porque ahí el renglón es un objetivo
  // cuadrado para el ratón, no una línea de texto.
  auto: {
    enlace: "justify-center px-2 py-2 xl:justify-start xl:gap-2.5 xl:px-3 xl:py-1.5",
    etiqueta: "sr-only xl:not-sr-only",
    titulo: "hidden xl:block",
    separador: "block xl:hidden",
    pildora: "hidden xl:inline-flex",
    punto: "xl:hidden",
    ocultoAlCerrar: "xl:hidden",
  },
  rail: {
    enlace: "justify-center px-2 py-2",
    etiqueta: "sr-only",
    titulo: "hidden",
    separador: "block",
    pildora: "hidden",
    punto: "",
    ocultoAlCerrar: "",
  },
  ancho: {
    enlace: "gap-2.5 px-3 py-1.5",
    etiqueta: "",
    titulo: "block",
    separador: "hidden",
    pildora: "inline-flex",
    punto: "hidden",
    ocultoAlCerrar: "hidden",
  },
  // El cajón de teléfono se toca con el dedo: py-3 deja el renglón en ~44px,
  // el mínimo de un objetivo táctil.
  cajon: {
    enlace: "gap-3 px-3 py-3",
    etiqueta: "",
    titulo: "block",
    separador: "hidden",
    pildora: "inline-flex",
    punto: "hidden",
    ocultoAlCerrar: "hidden",
  },
};

export function PanelNavegacion({
  grupos,
  pathname,
  contadores,
  modo,
  cerrados,
  onAlternarGrupo,
  onNavegar,
}: {
  /** Ya filtrados por rol: acá no se vuelve a decidir quién ve qué. */
  grupos: Grupo[];
  pathname: string;
  contadores: Contadores;
  modo: Modo;
  /** Etiquetas de los grupos contraídos. */
  cerrados: ReadonlySet<string>;
  onAlternarGrupo: (etiqueta: string) => void;
  /** El cajón lo usa para cerrarse al tocar un renglón. */
  onNavegar?: () => void;
}) {
  const c = CLASES[modo];
  const iconoTam = modo === "cajon" ? 18 : 16;
  // El sidebar y el cajón montan este componente a la vez, así que un id fijo
  // saldría duplicado en el documento y `aria-controls` apuntaría a cualquiera
  // de los dos. `useId` da un prefijo distinto por instancia.
  const prefijo = useId();

  return (
    <>
      {grupos.map((g, gi) => {
        const cerrado = g.label !== undefined && cerrados.has(g.label);
        const idLista = `${prefijo}-grupo-${gi}`;
        // Si la pantalla en la que estás vive en un grupo contraído, el título
        // se pinta como se pintan los renglones activos. Sin esto, contraer el
        // grupo en el que estás borra de la pantalla la única señal de dónde
        // estás — y la alternativa (volver a abrirlo solo) haría que el botón
        // no hiciera nada cuando más natural es pulsarlo.
        const contieneActivo = g.items.some((it) => esActivo(pathname, it.href));

        return (
        <div key={g.label ?? `grupo-${gi}`} className={gi > 0 ? "mt-1" : undefined}>
          {g.label ? (
            <>
              <button
                type="button"
                onClick={() => onAlternarGrupo(g.label as string)}
                aria-expanded={!cerrado}
                aria-controls={idLista}
                className={cx(
                  "etiqueta flex w-full items-center gap-1 rounded-control px-3 pb-0.5 pt-2.5 text-left transition-colors duration-150 hover:text-tinta",
                  cerrado && contieneActivo ? "text-tinta" : "text-taupe",
                  c.titulo,
                )}
              >
                <span className="truncate">{g.label}</span>
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
              {/* En rail no cabe el título del grupo, pero la separación sí
                  tiene que verse: sin ella son treinta iconos en una columna
                  sin ninguna jerarquía, que es justo el problema del que
                  venimos. */}
              <span aria-hidden className={cx("mx-3 my-2 h-px bg-sand", c.separador)} />
            </>
          ) : null}

          <div id={idLista} className={cx("grid gap-0.5", cerrado && c.ocultoAlCerrar)}>
            {g.items.map((it) => {
              const activo = esActivo(pathname, it.href);
              const cuenta = it.contador ? contadores[it.contador] : undefined;
              const conAviso = cuenta !== undefined && cuenta.n > 0;

              return (
                <Link
                  key={it.href}
                  href={it.href}
                  onClick={onNavegar}
                  // Sin esto, en rail el enlace no anuncia nada más que su
                  // icono; y `aria-current` es la ÚNICA señal de dónde estás
                  // para quien no ve el resaltado.
                  aria-current={activo ? "page" : undefined}
                  title={conAviso ? `${it.label} — ${cuenta.titulo}` : it.label}
                  className={cx(
                    "relative flex items-center rounded-control text-sm transition-colors duration-150 active:scale-[0.97]",
                    c.enlace,
                    activo
                      ? "bg-sand/60 font-medium text-tinta"
                      : "text-taupe hover:bg-sand/40 hover:text-rojo active:bg-sand/60 active:text-rojo-profundo",
                  )}
                >
                  <it.Icon size={iconoTam} strokeWidth={1.8} className="shrink-0" aria-hidden />

                  {/* La etiqueta nunca se desmonta: en rail se oculta con
                      `sr-only`, así el lector de pantalla la sigue leyendo y
                      quien mira la tiene en el `title`. */}
                  <span className={cx("truncate", c.etiqueta)}>{it.label}</span>

                  {conAviso ? (
                    <>
                      {/* Ancho: la píldora con el número. */}
                      <span
                        className={cx(
                          "ml-auto items-center rounded-pildora bg-rojo px-1.5 text-[10px] font-medium leading-4 text-crema",
                          c.pildora,
                        )}
                      >
                        {cuenta.n}
                      </span>
                      {/* Rail: un punto. El número no se lee a ese tamaño, así
                          que el dato entero viaja en el `title` y en el texto
                          para lector de pantalla de abajo. */}
                      <span
                        aria-hidden
                        className={cx(
                          "absolute right-1.5 top-1.5 size-2 rounded-pildora bg-rojo",
                          c.punto,
                        )}
                      />
                    </>
                  ) : null}

                  {conAviso ? <span className="sr-only">{cuenta.titulo}</span> : null}
                </Link>
              );
            })}
          </div>
        </div>
        );
      })}
    </>
  );
}

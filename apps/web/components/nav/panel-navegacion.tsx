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

import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import Link from "next/link";
import { esActivo, type Contador, type Grupo } from "@/app/(admin)/admin/nav-items";
import { cx } from "@/components/ui/cx";
import { GrupoDeMenu, type ModoMenu } from "./grupo-de-menu";

export type Modo = ModoMenu;

export type Contadores = Record<Contador, { n: number; titulo: string }>;

// Cada modo pinta las mismas cuatro piezas de un renglón con distintas clases.
// Tenerlas en un mapa y no en `modo === "rail" ? … : …` repartido por el JSX es
// lo que deja leer de un vistazo en qué se diferencian. Las del título de cada
// grupo —y la regla de que en rail no se contraen— viven en `grupo-de-menu.tsx`,
// que comparte este menú con el de «Lo mío».
const CLASES: Record<Modo, {
  enlace: string;
  etiqueta: string;
  pildora: string;
  punto: string;
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
    pildora: "hidden xl:inline-flex",
    punto: "xl:hidden",
  },
  rail: {
    enlace: "justify-center px-2 py-2",
    etiqueta: "sr-only",
    pildora: "hidden",
    punto: "",
  },
  ancho: {
    enlace: "gap-2.5 px-3 py-1.5",
    etiqueta: "",
    pildora: "inline-flex",
    punto: "hidden",
  },
  // El cajón de teléfono se toca con el dedo: py-3 deja el renglón en ~44px,
  // el mínimo de un objetivo táctil.
  cajon: {
    enlace: "gap-3 px-3 py-3",
    etiqueta: "",
    pildora: "inline-flex",
    punto: "hidden",
  },
};

// El nombre de cada pantalla en rail. Antes era el `title` del navegador, que
// espera cerca de un segundo, no se puede estilizar y no sale al llegar con Tab.
// Esta etiqueta sale en el mismo instante, también con el teclado.
//
// Es UNA sola etiqueta para todo el menú, con `position: fixed`, y no una por
// renglón: el `<nav>` del sidebar tiene `overflow-y-auto`, y eso recorta
// cualquier cosa absoluta que se salga por la derecha. Fixed la saca del recorte.
//
// Y va en un portal, a `document.body`. Con `fixed` sola no basta: el sidebar es
// `sticky`, y un `sticky` abre su propio contexto de apilamiento, así que el
// `z-50` de la etiqueta solo valía DENTRO del sidebar. La pantalla de al lado
// (la tarjeta «Equipo» de Datos personales) se pintaba encima y comía la
// etiqueta: «Horarios» se leía «Horario». Visto en producción el 2026-10-24.
//
// Solo donde no se ve el texto del renglón: en rail siempre, en auto hasta
// 1280px (`xl:hidden`), y nunca en ancho ni en el cajón.
const ETIQUETA_SEGUN_MODO: Record<Modo, string | null> = {
  auto: "xl:hidden",
  rail: "",
  ancho: null,
  cajon: null,
};

type Etiqueta = { texto: string; top: number; left: number };

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
  const claseEtiqueta = ETIQUETA_SEGUN_MODO[modo];
  const [etiqueta, setEtiqueta] = useState<Etiqueta | null>(null);

  // Si el menú se desplaza o se cambia de modo con la etiqueta puesta, queda
  // flotando donde ya no hay nada.
  useEffect(() => {
    if (!etiqueta) return;
    const quitar = () => setEtiqueta(null);
    window.addEventListener("scroll", quitar, true);
    window.addEventListener("resize", quitar);
    return () => {
      window.removeEventListener("scroll", quitar, true);
      window.removeEventListener("resize", quitar);
    };
  }, [etiqueta]);

  function mostrar(e: { currentTarget: HTMLElement }, texto: string) {
    if (claseEtiqueta === null) return;
    const r = e.currentTarget.getBoundingClientRect();
    setEtiqueta({ texto, top: r.top + r.height / 2, left: r.right + 8 });
  }

  return (
    <>
      {grupos.map((g, gi) => (
        <GrupoDeMenu
          key={g.label ?? `grupo-${gi}`}
          etiqueta={g.label}
          modo={modo}
          cerrado={g.label !== undefined && cerrados.has(g.label)}
          contieneActivo={g.items.some((it) => esActivo(pathname, it.href))}
          onAlternar={onAlternarGrupo}
          separado={gi > 0}
        >
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
                onMouseEnter={(e) => mostrar(e, conAviso ? `${it.label} — ${cuenta.titulo}` : it.label)}
                onFocus={(e) => mostrar(e, conAviso ? `${it.label} — ${cuenta.titulo}` : it.label)}
                onMouseLeave={() => setEtiqueta(null)}
                onBlur={() => setEtiqueta(null)}
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
        </GrupoDeMenu>
      ))}
      {etiqueta && claseEtiqueta !== null ? createPortal(
        <span
          role="presentation"
          style={{ top: etiqueta.top, left: etiqueta.left }}
          className={cx(
            "pointer-events-none fixed z-50 -translate-y-1/2 whitespace-nowrap rounded-control bg-tinta px-2.5 py-1.5 text-xs text-crema",
            claseEtiqueta,
          )}
        >
          {etiqueta.texto}
        </span>,
        document.body,
      ) : null}
    </>
  );
}

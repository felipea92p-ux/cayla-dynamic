"use client";

// El menú de secciones de una pantalla larga, con la forma del marco del panel:
// columna pegada al borde izquierdo, de altura completa, que se pliega a iconos
// y que por debajo de 768px es un cajón.
//
// POR QUÉ EXISTE
//
// «Lo mío» (/mio) tenía sus ocho secciones en una tira horizontal con
// `overflow-x-auto` y la barra de scroll escondida, así que en cualquier
// pantalla que no fuera ancha había secciones enteras fuera de la vista y sin
// nada que anunciara que estaban ahí. Es el mismo problema que el panel
// resolvió el 2026-09-07 cambiando su barra horizontal por un sidebar, y que ya
// se había intentado arreglar con scroll horizontal (688e8e5) y revertido el
// mismo día (21591a7) por esconder ítems.
//
// POR QUÉ EN EL BORDE Y NO AL LADO DEL DETALLE
//
// La primera versión lo puso como una tarjeta al lado del bloque de detalle,
// para no tocar el marco de la pantalla. Se vio en producción y se corrigió el
// mismo día: /mio es una columna centrada, así que el menú quedaba flotando en
// mitad de la página mientras el margen izquierdo —donde el panel tiene su
// menú— seguía vacío. Dos superficies del mismo sistema poniendo su navegación
// en sitios distintos obligan a buscarla dos veces.
//
// Ahora es el mismo objeto que el del panel: mismo ancho, misma altura, misma
// marca arriba, mismo botón de plegar abajo, misma línea a la derecha.
//
// POR QUÉ NO ES `PanelNavegacion`
//
// Ese componente dibuja ENLACES a rutas, agrupados y con contadores, y decide
// lo activo comparando el `pathname`. Acá no hay rutas: son BOTONES que cambian
// un estado dentro de una sola pantalla. Meter las dos ideas en un componente
// pediría que cada ítem fuera «o un href o un onClick» y que lo activo llegara
// de fuera — dos condicionales nuevas en la pieza más usada del panel, a cambio
// de compartir un mapa de clases. Lo que sí se comparte es lo que tiene
// COMPORTAMIENTO: el plegado (`useNavColapsado`), la trampa de foco del cajón
// (`useFocoAtrapado`), su salida animada (`useSalidaAnimada`) y, desde el
// 2026-10-06, el título de cada grupo con su regla de cuándo se contrae
// (`GrupoDeMenu`).
//
// GRUPOS Y BUSCADOR (2026-10-06)
//
// Eran ocho secciones en una sola lista y llegaron a catorce. Se eligió con un
// prototipo, mirando las opciones lado a lado: grupos con título que se pueden
// cerrar, como en el panel, y un buscador (⌘K) solo en la computadora — en el
// teléfono nadie tiene teclado a mano, y abrirlo taparía media pantalla para
// elegir entre catorce. Qué grupos hay y cómo se llaman lo decide la pantalla
// (`lib/mio-secciones.ts`); este componente solo los dibuja.

import { useCallback, useEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";
import { ChevronsDown, LogOut, Menu, PanelLeftClose, PanelLeftOpen, Search, X } from "lucide-react";
import { useGruposCerrados, useNavColapsado } from "@/lib/use-nav-colapsado";
import { useFocoAtrapado } from "@/lib/use-foco-atrapado";
import { useSalidaAnimada } from "@/lib/use-salida-animada";
import type { GrupoDetalle } from "@/lib/secciones-de-menu";
import { Colibri, Marca } from "@/components/marca";
import { cx } from "@/components/ui/cx";
import { Insignia } from "@/components/ui/insignia";
import { GrupoDeMenu, type ModoMenu } from "./grupo-de-menu";
import { BuscadorSecciones } from "./buscador-secciones";

// Lo que tarda el cajón en irse. Tiene que coincidir con `.cajon-sale` de
// globals.css: es lo que el hook espera antes de desmontarlo.
const SALIDA_DEL_CAJON_MS = 200;

// Los tipos de la lista —`SeccionDetalle`, `GrupoDetalle`— viven en
// `lib/secciones-de-menu.ts`, junto con la regla del buscador, para poder
// probarlos sin un navegador.


// Cada modo pinta el mismo renglón con distintas clases, en un mapa y no
// repartidas por el JSX — igual que `panel-navegacion.tsx`, y por la misma
// razón: así se lee de un vistazo en qué se diferencian.
//
// El renglón ancho mide lo mismo que el del panel, `py-1.5`, desde el
// 2026-10-06. Antes era `py-2` porque eran ocho secciones y no había scroll que
// ahorrar. Con catorce y los títulos de grupo, medido en el prototipo en una
// laptop de 13″ (780 px de alto útil): con `py-2` la lista medía 669 px para
// 625 de espacio y «Historial» quedaba fuera; con `py-1.5`, 613, y entra. En
// rail y en el cajón no cambia: ahí el renglón es un objetivo para el ratón o
// el dedo, no una línea de texto.
//
// `pildora` y `punto` son lo del contador y siguen la regla de
// `panel-navegacion.tsx`: en ancho y en cajón, la píldora con el número; en rail
// no cabe un número, así que un punto (y el dato viaja en el `title` y en el
// texto para lector de pantalla).
const CLASES: Record<ModoMenu, { fila: string; etiqueta: string; pildora: string; punto: string }> = {
  // Sin elegir: la CSS decide. Rail por debajo de 1280px, ancho a partir de ahí.
  auto: {
    fila: "justify-center px-2 py-2 xl:justify-start xl:gap-2.5 xl:px-3 xl:py-1.5",
    etiqueta: "sr-only xl:not-sr-only",
    pildora: "hidden xl:inline-flex",
    punto: "xl:hidden",
  },
  rail: { fila: "justify-center px-2 py-2", etiqueta: "sr-only", pildora: "hidden", punto: "" },
  ancho: { fila: "gap-2.5 px-3 py-1.5", etiqueta: "", pildora: "inline-flex", punto: "hidden" },
  // El cajón se toca con el dedo: py-3 deja el renglón en ~44px, el mínimo de
  // un objetivo táctil.
  cajon: { fila: "gap-3 px-3 py-3", etiqueta: "", pildora: "inline-flex", punto: "hidden" },
};

// Los mismos anchos que `sidebar-admin.tsx`, no unos parecidos: las dos
// columnas se ven una encima de la otra al cambiar de superficie.
const ANCHO: Record<Exclude<ModoMenu, "cajon">, string> = {
  auto: "w-16 xl:w-64",
  rail: "w-16",
  ancho: "w-64",
};

// Lo que solo se ve ancho, lo que solo se ve en rail, y cómo se acomoda la caja
// de cada uno. En "auto" son variantes `xl:` porque a esa altura nadie eligió
// nada y el ancho lo decide la ventana, no React.
const SEGUN_ANCHO: Record<
  Exclude<ModoMenu, "cajon">,
  { soloAncho: string; soloRail: string; caja: string }
> = {
  auto: {
    soloAncho: "hidden xl:flex",
    soloRail: "flex xl:hidden",
    caja: "justify-center xl:justify-start xl:gap-2.5",
  },
  rail: { soloAncho: "hidden", soloRail: "flex", caja: "justify-center" },
  ancho: { soloAncho: "flex", soloRail: "hidden", caja: "gap-2.5" },
};

/**
 * La lista de secciones, dibujada. Es UN componente para los tres sitios donde
 * aparece —columna ancha, rail de iconos y cajón de teléfono—, que es la
 * lección que `panel-navegacion.tsx` ya dejó escrita: cuando eran dos copias,
 * cambiar una cosa dejaba la otra atrás sin que nada fallara.
 */
function ListaSecciones<T extends string>({
  grupos,
  activo,
  onSel,
  modo,
  cerrados,
  onAlternarGrupo,
  onElegir,
}: {
  grupos: readonly GrupoDetalle<T>[];
  activo: T;
  onSel: (valor: T) => void;
  modo: ModoMenu;
  /** Etiquetas de los grupos cerrados. */
  cerrados: ReadonlySet<string>;
  onAlternarGrupo: (etiqueta: string) => void;
  /** El cajón lo usa para cerrarse al tocar un renglón. */
  onElegir?: () => void;
}) {
  const c = CLASES[modo];
  const iconoTam = modo === "cajon" ? 18 : 16;
  // El orden de cada renglón en el menú entero, no dentro de su grupo: es lo
  // que lee la cascada del cajón, y sin esto cada grupo arrancaría de cero.
  let orden = 0;

  return (
    <div>
      {grupos.map((g, gi) => (
        <GrupoDeMenu
          key={g.label ?? `grupo-${gi}`}
          etiqueta={g.label}
          modo={modo}
          cerrado={g.label !== undefined && cerrados.has(g.label)}
          contieneActivo={g.secciones.some((s) => s.valor === activo)}
          onAlternar={onAlternarGrupo}
          separado={gi > 0}
        >
          {g.secciones.map((s) => {
            const i = orden++;
            const activa = s.valor === activo;
            const conAviso = (s.contador ?? 0) > 0;
            return (
              <button
                key={s.valor}
                type="button"
                onClick={() => {
                  onSel(s.valor);
                  onElegir?.();
                }}
                // Solo en el cajón: los renglones llegan en cascada, cada uno 28 ms
                // después del anterior (`.fila-en-cascada` en globals.css lee `--i`).
                // La columna de escritorio no se anima: está siempre a la vista, y
                // algo que ya se ve no tiene de dónde llegar.
                style={modo === "cajon" ? ({ "--i": i } as CSSProperties) : undefined}
                // `aria-current="page"`, y no un `role="tab"` con `aria-selected`,
                // porque es lo que estas secciones ya anunciaban cuando eran una
                // tira de pestañas. Un `tablist` de verdad obliga además a mover el
                // foco con las flechas y a que cada panel sea un `tabpanel`; a
                // medias sería peor que esto, que hoy es correcto.
                aria-current={activa ? "page" : undefined}
                title={conAviso ? `${s.label} — ${s.contador} por ver` : s.label}
                className={cx(
                  "relative flex items-center rounded-control text-left text-sm transition-colors duration-150 active:scale-[0.97]",
                  modo === "cajon" && "fila-en-cascada",
                  c.fila,
                  activa
                    ? "bg-sand/60 font-medium text-tinta"
                    : "text-taupe hover:bg-sand/40 hover:text-rojo active:bg-sand/60 active:text-rojo-profundo",
                )}
              >
                <s.Icon size={iconoTam} strokeWidth={1.8} className="shrink-0" aria-hidden />
                {/* La etiqueta nunca se desmonta: en rail se oculta con `sr-only`,
                    así el lector de pantalla la sigue leyendo y quien mira la tiene
                    en el `title`. */}
                <span className={cx("truncate", c.etiqueta)}>{s.label}</span>

                {conAviso ? (
                  <>
                    {/* Ancho: la píldora con el número. `Insignia` va DENTRO de un
                        contenedor que decide cuándo se ve, y no con `hidden` en su
                        propia clase: la insignia ya trae su `inline-flex`, y dos
                        clases de `display` en el mismo elemento las decide el orden
                        del CSS, no el de la línea. */}
                    <span className={cx("ml-auto", c.pildora)} aria-hidden>
                      <Insignia variante="contador" tamano="sm">{s.contador}</Insignia>
                    </span>
                    {/* Rail: un punto, como el panel. */}
                    <span
                      aria-hidden
                      className={cx("absolute right-1.5 top-1.5 size-2 rounded-pildora bg-rojo", c.punto)}
                    />
                    <span className="sr-only">{s.contador} por ver</span>
                  </>
                ) : null}
              </button>
            );
          })}
        </GrupoDeMenu>
      ))}
    </div>
  );
}

/**
 * El menú completo: la barra de teléfono, la columna de 768px para arriba y el
 * cajón. Los tres salen de la misma lista.
 *
 * Va como PRIMER hijo de un contenedor `flex flex-col md:flex-row` que envuelva
 * la pantalla entera; así la columna se pega al borde izquierdo y el contenido
 * ocupa el resto, igual que en `(admin)/layout.tsx`.
 */
export function MenuDetalle<T extends string>({
  grupos,
  memoriaGrupos,
  activo,
  onSel,
  etiqueta,
  accion,
  accionCajon,
  onSalir,
  sesion,
}: {
  grupos: readonly GrupoDetalle<T>[];
  /**
   * El nombre con que este menú recuerda qué grupos cerró cada quien, en el
   * navegador. Propio de cada pantalla: no se comparte con el del panel (ver
   * `useGruposCerrados`).
   */
  memoriaGrupos: string;
  activo: T;
  onSel: (valor: T) => void;
  /** Cómo se llama este menú para quien no lo ve. Ej.: «Secciones de tu perfil». */
  etiqueta: string;
  /**
   * Lo que va a la derecha de la barra de teléfono: la salida de la pantalla
   * (en /mio, «Volver al panel»). Solo se ve por debajo de 768px, donde la
   * barra existe; de ahí para arriba la pantalla tiene que ofrecerla por su
   * cuenta. Opcional porque no toda pantalla larga tiene a dónde volver.
   */
  accion?: ReactNode;
  /**
   * Lo que va en la cabecera del cajón de teléfono, al lado de la ✕. En /mio,
   * el cambio de tema: se toca una vez y no necesita ocupar la barra de arriba,
   * donde le quitaba el espacio que necesita el nombre de la sección para
   * quedar al centro. Ahí, y no al pie junto a «Salir», porque al pie le
   * quitaba 54 px a la lista (medido en el prototipo).
   */
  accionCajon?: ReactNode;
  /**
   * Cerrar la sesión. Si viene, «Salir» se dibuja AL PIE DEL MENÚ en los dos
   * tamaños —abajo del cajón en teléfono, encima de «Colapsar» en la columna—
   * y no en la pantalla: es donde el cajón del panel tiene «Cerrar sesión», y
   * quien lo aprende en una superficie lo encuentra en la otra. Lo dibuja
   * este componente y no la pantalla porque en rail tiene que quedar el icono
   * solo, y eso lo sabe él.
   */
  onSalir?: () => void;
  /** El nombre de quien está en sesión, para el pie del cajón. */
  sesion?: string;
}) {
  // El MISMO plegado del panel, a propósito, con la misma clave de
  // localStorage: no son dos preferencias («quiero el menú del panel angosto» y
  // «quiero el de mi perfil angosto») sino una sola —«quiero el menú angosto»—
  // y quien tiene las dos superficies no debería tener que decirlo dos veces.
  const { modo, expandido, alternar } = useNavColapsado();
  const { cerrados, alternarGrupo } = useGruposCerrados(memoriaGrupos);
  const [cajonAbierto, setCajonAbierto] = useState(false);
  const disparador = useRef<HTMLButtonElement>(null);
  const caja = useRef<HTMLDivElement>(null);

  useFocoAtrapado({
    abierto: cajonAbierto,
    onCerrar: () => setCajonAbierto(false),
    caja,
    volverElFocoA: disparador,
  });

  // El cajón sigue dibujado los 200 ms que tarda en irse (ver el hook): sin
  // esto, cerrar lo desmonta en el acto y la animación de salida no tiene a
  // qué aplicarse.
  const { montado: cajonMontado, saliendo: cajonSaliendo } = useSalidaAnimada(
    cajonAbierto,
    SALIDA_DEL_CAJON_MS,
  );

  const actual = grupos.flatMap((g) => g.secciones).find((s) => s.valor === activo);

  // ── El buscador (⌘K) ───────────────────────────────────────────────────
  // ⌘K / Ctrl+K lo abre desde cualquier parte de la pantalla, escribiendo o
  // no: el mismo atajo, con la misma regla, que en el panel (`nav.tsx`). Al
  // cerrarse, el foco vuelve a donde estaba antes de abrirlo —el botón de la
  // lupa, o lo que fuera que tenía el foco al apretar las teclas—.
  const [buscadorAbierto, setBuscadorAbierto] = useState(false);
  const focoAntesDelBuscador = useRef<HTMLElement | null>(null);
  const abrirBuscador = useCallback(() => {
    focoAntesDelBuscador.current = document.activeElement as HTMLElement | null;
    setBuscadorAbierto(true);
  }, []);
  const cerrarBuscador = useCallback(() => {
    setBuscadorAbierto(false);
    focoAntesDelBuscador.current?.focus();
  }, []);
  useEffect(() => {
    function alPresionar(e: KeyboardEvent) {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        abrirBuscador();
      }
    }
    window.addEventListener("keydown", alPresionar);
    return () => window.removeEventListener("keydown", alPresionar);
  }, [abrirBuscador]);

  // ── «Más abajo», en el cajón ───────────────────────────────────────────
  // En un iPhone con Safari quedan unos 500 px para la lista, y la lista
  // entera mide cerca de 800 (medido en el prototipo el 2026-10-06): sin
  // aviso, las últimas secciones están ahí pero nadie sabe que existen. El
  // aviso aparece solo cuando de verdad queda algo abajo, y se va al llegar al
  // final o al cerrar grupos hasta que todo entra.
  const listaCajon = useRef<HTMLElement>(null);
  const [quedaMasAbajo, setQuedaMasAbajo] = useState(false);
  const medirMasAbajo = useCallback(() => {
    const el = listaCajon.current;
    if (el) setQuedaMasAbajo(el.scrollTop + el.clientHeight < el.scrollHeight - 4);
  }, []);
  useEffect(() => {
    const el = listaCajon.current;
    if (!cajonMontado || !el) return;
    // Un fotograma después: recién montado, el cajón todavía no tiene su alto.
    const cuadro = requestAnimationFrame(medirMasAbajo);
    // Lo que cambia el alto: girar el teléfono (la caja) y cerrar o abrir un
    // grupo (su contenido).
    const observador = new ResizeObserver(medirMasAbajo);
    observador.observe(el);
    if (el.firstElementChild) observador.observe(el.firstElementChild);
    return () => {
      cancelAnimationFrame(cuadro);
      observador.disconnect();
    };
  }, [cajonMontado, medirMasAbajo]);

  return (
    <>
      {/* ── Teléfono: la barra que abre el cajón ────────────────────────────
          Pegada arriba y no suelta encima del detalle, que es lo que hace el
          panel por debajo de 768px. Misma altura que la cabecera del panel
          (`nav.tsx`), porque son la misma pieza vista desde dos superficies;
          el padding cede 4px en teléfono porque acá caben tres cosas
          —menú, título y salida— donde allá caben dos.

          Tres cosas, en el orden en que un teléfono las pone desde siempre:
          a la izquierda lo que abre, en el centro dónde estás, a la derecha la
          salida.

          · La hamburguesa. Hasta el 2026-09-11 era un icono suelto pegado al
            nombre de la sección, con un «Cambiar» chico a la derecha, y se
            probó con gente de verdad: NO LA ENCONTRABAN. Ahora es un cuadrado
            RELLENO con la palabra «Menú» al lado, los dos dentro de un solo
            botón para que tocar la palabra también abra. Es la misma receta
            que la hamburguesa del panel (`nav.tsx`), que cambió el mismo día
            por la misma razón: un cuadrado con borde `sand` da 1.16:1 sobre
            crema, o sea que a la vista era un icono flotando.

            El relleno era tinta, como el del panel, y desde el 2026-10-06 es
            `taupe`, el café de la paleta: tinta era lo único negro en una
            pantalla de tonos cálidos. Se eligió entre cinco con el contraste
            medido, porque lo que no se puede perder es lo que se ganó en
            septiembre —que se vea—: crema sobre taupe da 5.21:1 en claro y
            5.82:1 en oscuro, por encima del 3:1 que pide un control. Rojo
            daba 4.83:1 pero dejaba dos botones rojos en la barra de quien
            tiene «Volver al panel». El del panel sigue en tinta.

          · La sección en la que estás, en serif y CENTRADA EN LA PANTALLA,
            como el título de cualquier pantalla de teléfono. Hasta el
            2026-10-06 se centraba en el hueco que dejaban los botones, y como
            «Menú» es más ancho que lo que había a la derecha, el nombre caía
            25 px a la derecha del centro (medido). Ahora la barra es una
            grilla `1fr auto 1fr`: los dos lados miden lo mismo y el nombre
            queda al medio. Si no hay sitio —un líder, con «Volver al panel» a
            la derecha, mirando «Vacaciones y permisos»— la grilla corre el
            nombre hacia el lado libre en vez de montarlo sobre un botón. Dos
            líneas como máximo.

          · La salida, en `accion`: la pantalla decide qué va ahí (en /mio es
            «Volver al panel», y solo para quien tiene panel). Va acá y no
            solo en la tarjeta del perfil porque en teléfono la tarjeta queda
            debajo del pliegue, y quien entró desde el panel necesita volver
            sin buscar. */}
      <div className="sticky top-0 z-30 grid h-16 shrink-0 grid-cols-[1fr_auto_1fr] items-center gap-2 border-b border-sand bg-crema px-3 sm:gap-3 sm:px-6 md:hidden print:hidden">
        <button
          ref={disparador}
          type="button"
          onClick={() => setCajonAbierto(true)}
          aria-expanded={cajonAbierto}
          aria-haspopup="dialog"
          // El mismo nombre que la hamburguesa del panel. La sección actual ya
          // no viaja acá: está al lado, visible y anunciada por su propia
          // región en vivo.
          aria-label="Abrir menú"
          className="group flex shrink-0 items-center gap-2 justify-self-start text-sm font-medium text-tinta"
        >
          {/* El cuadrado: clase por clase la hamburguesa de `nav.tsx`, con los
              estados de hover/active colgados del botón entero (`group-*`)
              para que se enciendan también al pasar por la palabra. Y
              `.menu-se-hace-notar`: un par de latidos al cargar, una sola
              vez, que es lo que enseña dónde está a quien no lo encontraba. */}
          <span
            aria-hidden
            className="menu-se-hace-notar rounded-control bg-taupe p-2 text-crema transition-colors duration-150 group-hover:bg-rojo group-active:scale-[0.97]"
          >
            <Menu size={20} strokeWidth={1.8} aria-hidden />
          </span>
          <span>Menú</span>
        </button>

        {/* En qué sección estás. `aria-live` porque el cajón se cierra ENCIMA
            del cambio y el foco vuelve a la hamburguesa: sin esto, quien no ve
            la pantalla elige «Mis turnos» y no oye nada que lo confirme.
            El `key` es lo que hace que el nombre nuevo entre animado —al
            cambiar de sección se remonta, y la CSS (`.titulo-entra` en
            globals.css) corre al montarse. */}
        <p aria-live="polite" className="min-w-0 text-center">
          <span
            key={actual?.valor ?? "sin-elegir"}
            // `text-base` por debajo de 400px: con «Volver al panel» a la
            // derecha, a «Vacaciones y permisos» le queda poco en un teléfono
            // de 360, y en `text-lg` la primera línea ya no cabe.
            className="titulo-entra line-clamp-2 font-serif text-base leading-tight text-tinta min-[400px]:text-lg"
          >
            {actual?.label ?? etiqueta}
          </span>
        </p>

        {/* Su propia caja aunque venga vacía: es la tercera columna de la
            grilla, y sin ella el nombre dejaría de estar al centro. */}
        <div className="flex items-center justify-self-end">{accion}</div>
      </div>

      {/* ── De 768px para arriba: la columna ────────────────────────────────
          Misma receta que `sidebar-admin.tsx`: pegada al viewport, de alto
          completo y con su propio scroll, para que arrastrar la página no se
          lleve el menú con ella. */}
      <div
        className={cx(
          "sticky top-0 hidden h-screen shrink-0 flex-col border-r border-sand bg-crema transition-[width] duration-150 motion-reduce:transition-none md:flex print:hidden",
          ANCHO[modo],
        )}
      >
        <div className="flex h-16 shrink-0 items-center border-b border-sand px-3">
          {/* En rail no cabe el lockup entero, pero el colibrí sí: la marca no
              desaparece a ningún ancho. */}
          <Marca tono="tinta" isotipo="rojo" className={cx("min-w-0", SEGUN_ANCHO[modo].soloAncho)} />
          <span className={cx("mx-auto", SEGUN_ANCHO[modo].soloRail)}>
            <Colibri tono="rojo" className="w-8" />
          </span>
          {/* El buscador, al lado de la marca y no como un renglón más: ahí no
              le quita alto a la lista, que en una laptop de 13″ entra con lo
              justo. Misma cara que el «Buscar ⌘K» del panel, sin la palabra
              porque no cabe junto al lockup. */}
          <button
            type="button"
            onClick={abrirBuscador}
            aria-label="Buscar una sección"
            title="Buscar una sección (⌘K o Ctrl+K)"
            className={cx(
              "ml-auto shrink-0 items-center gap-1.5 rounded-control border border-sand px-2 py-1.5 text-sm text-taupe transition-colors duration-150 hover:border-taupe/40 hover:bg-sand/30 hover:text-rojo active:scale-[0.97] active:text-rojo-profundo",
              SEGUN_ANCHO[modo].soloAncho,
            )}
          >
            <Search size={15} strokeWidth={1.8} aria-hidden />
            <kbd className="rounded border border-sand bg-sand/50 px-1 font-sans text-[10px] text-taupe">⌘K</kbd>
          </button>
        </div>

        <nav
          id="menu-detalle"
          aria-label={etiqueta}
          className="min-h-0 flex-1 overflow-y-auto px-2 py-2"
        >
          {/* En rail no hay sitio junto al colibrí: la lupa pasa a ser el
              primer renglón, separada de las secciones por una raya. */}
          <div className={cx("flex-col", SEGUN_ANCHO[modo].soloRail)}>
            <button
              type="button"
              onClick={abrirBuscador}
              aria-label="Buscar una sección"
              title="Buscar una sección (⌘K o Ctrl+K)"
              className="flex items-center justify-center rounded-control px-2 py-2 text-taupe transition-colors duration-150 hover:bg-sand/40 hover:text-rojo active:scale-[0.97]"
            >
              <Search size={16} strokeWidth={1.8} aria-hidden />
            </button>
            <span aria-hidden className="mx-3 my-2 h-px bg-sand" />
          </div>
          <ListaSecciones
            grupos={grupos}
            activo={activo}
            onSel={onSel}
            modo={modo}
            cerrados={cerrados}
            onAlternarGrupo={alternarGrupo}
          />
        </nav>

        <div className="shrink-0 border-t border-sand p-2">
          {/* «Salir», encima de «Colapsar» y con su misma forma: en rail queda
              el icono solo y el nombre viaja en `title`/`aria-label`, igual que
              el botón de abajo. */}
          {onSalir ? (
            <button
              type="button"
              onClick={onSalir}
              aria-label="Salir"
              title="Salir"
              className={cx(
                "flex w-full items-center rounded-control px-2 py-2 text-sm text-taupe transition-colors duration-150 hover:bg-sand/40 hover:text-rojo active:scale-[0.97]",
                SEGUN_ANCHO[modo].caja,
              )}
            >
              <LogOut size={16} strokeWidth={1.8} aria-hidden className="shrink-0" />
              <span className={cx("truncate", SEGUN_ANCHO[modo].soloAncho)}>Salir</span>
            </button>
          ) : null}

          {/* Igual que el sidebar del panel, en modo "auto" quién manda es la
              CSS y no el estado: `expandido` recién es fiable después de
              montar, y decidir el icono con él haría parpadear el botón en cada
              carga. */}
          <button
            type="button"
            onClick={alternar}
            aria-expanded={expandido}
            aria-controls="menu-detalle"
            aria-label={expandido ? "Colapsar el menú" : "Expandir el menú"}
            title={expandido ? "Colapsar el menú" : "Expandir el menú"}
            className={cx(
              "flex w-full items-center rounded-control px-2 py-2 text-sm text-taupe transition-colors duration-150 hover:bg-sand/40 hover:text-rojo active:scale-[0.97]",
              SEGUN_ANCHO[modo].caja,
            )}
          >
            <PanelLeftClose
              size={16}
              strokeWidth={1.8}
              aria-hidden
              className={cx("shrink-0", SEGUN_ANCHO[modo].soloAncho)}
            />
            <PanelLeftOpen
              size={16}
              strokeWidth={1.8}
              aria-hidden
              className={cx("shrink-0", SEGUN_ANCHO[modo].soloRail)}
            />
            <span className={cx("truncate", SEGUN_ANCHO[modo].soloAncho)}>Colapsar</span>
          </button>
        </div>
      </div>

      {/* ── Por debajo de 768px: el cajón ───────────────────────────────────
          Mismo criterio que el del panel: entra desde la izquierda sobre un
          velo, en vez de empujar la página hacia abajo. Y desde el 2026-09-11
          entra y sale DESLIZANDO (`.cajon-entra`/`.cajon-sale` en globals.css)
          en vez de aparecer de golpe; mientras se va queda `inert`, para que
          esos 200 ms no sean una ventana en la que todavía se puede tocar un
          renglón de un menú que ya se cerró. */}
      {cajonMontado && (
        <>
          {/* `bg-black/40` y no `bg-tinta/NN`: en modo oscuro tinta ACLARA, que
              es lo contrario de lo que un velo tiene que hacer. */}
          <div
            onClick={() => setCajonAbierto(false)}
            className={cx("fixed inset-0 z-40 bg-black/40 md:hidden", cajonSaliendo ? "velo-sale" : "velo-entra")}
            aria-hidden
          />
          <div
            ref={caja}
            role="dialog"
            aria-modal="true"
            aria-label={etiqueta}
            inert={cajonSaliendo || undefined}
            className={cx(
              "fixed inset-y-0 left-0 z-50 flex w-72 max-w-[85vw] flex-col border-r border-sand bg-crema md:hidden print:hidden",
              cajonSaliendo ? "cajon-sale" : "cajon-entra",
            )}
          >
            <div className="flex h-16 shrink-0 items-center justify-between border-b border-sand px-4">
              <Marca tono="tinta" isotipo="rojo" />
              <div className="flex items-center gap-1">
                {accionCajon}
                <button
                  type="button"
                  onClick={() => setCajonAbierto(false)}
                  aria-label="Cerrar menú"
                  className="rounded-control p-2 text-taupe transition-colors duration-150 hover:bg-sand/40 hover:text-rojo active:scale-[0.97]"
                >
                  <X size={20} strokeWidth={1.8} aria-hidden />
                </button>
              </div>
            </div>

            <div className="relative min-h-0 flex-1">
              <nav
                ref={listaCajon}
                onScroll={medirMasAbajo}
                aria-label={etiqueta}
                className="h-full overflow-y-auto px-2 py-2"
              >
                <ListaSecciones
                  grupos={grupos}
                  activo={activo}
                  onSel={onSel}
                  modo="cajon"
                  cerrados={cerrados}
                  onAlternarGrupo={alternarGrupo}
                  onElegir={() => setCajonAbierto(false)}
                />
              </nav>
              {/* Decorativo para quien no ve la pantalla: el lector de
                  pantalla ya recorre la lista entera, quepa o no. No intercepta
                  el dedo (`pointer-events-none`): debajo hay renglones. */}
              {quedaMasAbajo ? (
                <div
                  aria-hidden
                  className="pointer-events-none absolute inset-x-0 bottom-0 flex h-16 items-end justify-center bg-linear-to-b from-transparent to-crema pb-2"
                >
                  <span className="flex items-center gap-1 rounded-pildora border border-sand bg-papel px-2.5 py-0.5 text-xs text-tinta">
                    Más abajo
                    <ChevronsDown size={14} strokeWidth={1.8} aria-hidden />
                  </span>
                </div>
              ) : null}
            </div>

            {/* El pie: clase por clase el de `cajon-admin.tsx`. Cerrar sesión
                es la única acción del menú que no es una sección, y va abajo y
                separada por la línea para que no se confunda con una. */}
            {onSalir ? (
              <div className="shrink-0 border-t border-sand p-3">
                {sesion ? (
                  <p className="px-1 pb-2 text-xs text-taupe" title="Sesión activa">
                    Sesión: {sesion}
                  </p>
                ) : null}
                <button
                  type="button"
                  onClick={onSalir}
                  className="flex w-full items-center gap-3 rounded-control border border-sand px-3 py-3 text-left text-sm text-taupe transition-colors duration-150 hover:border-rojo/30 hover:text-rojo active:scale-[0.97]"
                >
                  <LogOut size={18} strokeWidth={1.8} aria-hidden /> Salir
                </button>
              </div>
            ) : null}
          </div>
        </>
      )}

      <BuscadorSecciones
        grupos={grupos}
        abierto={buscadorAbierto}
        onCerrar={cerrarBuscador}
        onElegir={onSel}
      />
    </>
  );
}

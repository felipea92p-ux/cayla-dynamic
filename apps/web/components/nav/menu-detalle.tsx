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
// (`useFocoAtrapado`) y su salida animada (`useSalidaAnimada`).

import { useRef, useState, type CSSProperties, type ReactNode } from "react";
import { Menu, PanelLeftClose, PanelLeftOpen, X, type LucideIcon } from "lucide-react";
import { useNavColapsado } from "@/lib/use-nav-colapsado";
import { useFocoAtrapado } from "@/lib/use-foco-atrapado";
import { useSalidaAnimada } from "@/lib/use-salida-animada";
import { Colibri, Marca } from "@/components/marca";
import { cx } from "@/components/ui/cx";

// Lo que tarda el cajón en irse. Tiene que coincidir con `.cajon-sale` de
// globals.css: es lo que el hook espera antes de desmontarlo.
const SALIDA_DEL_CAJON_MS = 200;

export type SeccionDetalle<T extends string> = {
  valor: T;
  label: string;
  Icon: LucideIcon;
};

type ModoMenu = "auto" | "rail" | "ancho" | "cajon";

// Cada modo pinta el mismo renglón con distintas clases, en un mapa y no
// repartidas por el JSX — igual que `panel-navegacion.tsx`, y por la misma
// razón: así se lee de un vistazo en qué se diferencian.
//
// La única diferencia con el panel es el alto del renglón ancho: allá es
// `py-1.5` porque son treinta renglones y cada 4px de más son 120px de scroll.
// Acá son ocho, no hay scroll que ahorrar, y `py-2` es el mismo alto que el
// panel ya usa en rail.
const CLASES: Record<ModoMenu, { fila: string; etiqueta: string }> = {
  // Sin elegir: la CSS decide. Rail por debajo de 1280px, ancho a partir de ahí.
  auto: {
    fila: "justify-center px-2 py-2 xl:justify-start xl:gap-2.5 xl:px-3",
    etiqueta: "sr-only xl:not-sr-only",
  },
  rail: { fila: "justify-center px-2 py-2", etiqueta: "sr-only" },
  ancho: { fila: "gap-2.5 px-3 py-2", etiqueta: "" },
  // El cajón se toca con el dedo: py-3 deja el renglón en ~44px, el mínimo de
  // un objetivo táctil.
  cajon: { fila: "gap-3 px-3 py-3", etiqueta: "" },
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
  secciones,
  activo,
  onSel,
  modo,
  onElegir,
}: {
  secciones: readonly SeccionDetalle<T>[];
  activo: T;
  onSel: (valor: T) => void;
  modo: ModoMenu;
  /** El cajón lo usa para cerrarse al tocar un renglón. */
  onElegir?: () => void;
}) {
  const c = CLASES[modo];
  const iconoTam = modo === "cajon" ? 18 : 16;

  return (
    <div className="grid gap-0.5">
      {secciones.map((s, i) => {
        const activa = s.valor === activo;
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
            title={s.label}
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
          </button>
        );
      })}
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
  secciones,
  activo,
  onSel,
  etiqueta,
  accion,
}: {
  secciones: readonly SeccionDetalle<T>[];
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
}) {
  // El MISMO plegado del panel, a propósito, con la misma clave de
  // localStorage: no son dos preferencias («quiero el menú del panel angosto» y
  // «quiero el de mi perfil angosto») sino una sola —«quiero el menú angosto»—
  // y quien tiene las dos superficies no debería tener que decirlo dos veces.
  const { modo, expandido, alternar } = useNavColapsado();
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

  const actual = secciones.find((s) => s.valor === activo);

  return (
    <>
      {/* ── Teléfono: la barra que abre el cajón ────────────────────────────
          Pegada arriba y no suelta encima del detalle, que es lo que hace el
          panel por debajo de 768px. Misma altura y mismo padding que la
          cabecera del panel (`nav.tsx`), porque son la misma pieza vista desde
          dos superficies.

          Tres cosas, en el orden en que un teléfono las pone desde siempre:
          a la izquierda lo que abre, en el centro dónde estás, a la derecha la
          salida.

          · La hamburguesa. Hasta el 2026-09-11 era un icono suelto pegado al
            nombre de la sección, con un «Cambiar» chico a la derecha, y se
            probó con gente de verdad: NO LA ENCONTRABAN. Ahora es un cuadrado
            RELLENO en tinta —el tono del botón primario de la casa— con la
            palabra «Menú» al lado, los dos dentro de un solo botón para que
            tocar la palabra también abra. Es la misma receta que la
            hamburguesa del panel (`nav.tsx`), que cambió el mismo día por la
            misma razón: un cuadrado con borde `sand` da 1.16:1 sobre crema,
            o sea que a la vista era un icono flotando.

          · La sección en la que estás, en serif y al centro, como el título
            de cualquier pantalla de teléfono. Dos líneas como máximo:
            «Vacaciones y permisos» no cabe en una entre los dos botones.

          · La salida, en `accion`: la pantalla decide qué va ahí (en /mio es
            «Volver al panel», y solo para quien tiene panel). Va acá y no
            solo en la tarjeta del perfil porque en teléfono la tarjeta queda
            debajo del pliegue, y quien entró desde el panel necesita volver
            sin buscar. */}
      <div className="sticky top-0 z-30 flex h-16 shrink-0 items-center gap-3 border-b border-sand bg-crema px-4 sm:px-6 md:hidden print:hidden">
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
          className="group flex shrink-0 items-center gap-2 text-sm font-medium text-tinta"
        >
          {/* El cuadrado: clase por clase la hamburguesa de `nav.tsx`, con los
              estados de hover/active colgados del botón entero (`group-*`)
              para que se enciendan también al pasar por la palabra. Y
              `.menu-se-hace-notar`: un par de latidos al cargar, una sola
              vez, que es lo que enseña dónde está a quien no lo encontraba. */}
          <span
            aria-hidden
            className="menu-se-hace-notar rounded-control bg-tinta p-2 text-crema transition-colors duration-150 group-hover:bg-rojo group-active:scale-[0.97]"
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
        <p aria-live="polite" className="min-w-0 flex-1 text-center">
          <span
            key={actual?.valor ?? "sin-elegir"}
            className="titulo-entra line-clamp-2 font-serif text-lg leading-tight text-tinta"
          >
            {actual?.label ?? etiqueta}
          </span>
        </p>

        {accion}
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
        </div>

        <nav
          id="menu-detalle"
          aria-label={etiqueta}
          className="min-h-0 flex-1 overflow-y-auto px-2 py-2"
        >
          <ListaSecciones secciones={secciones} activo={activo} onSel={onSel} modo={modo} />
        </nav>

        <div className="shrink-0 border-t border-sand p-2">
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
              <button
                type="button"
                onClick={() => setCajonAbierto(false)}
                aria-label="Cerrar menú"
                className="rounded-control p-2 text-taupe transition-colors duration-150 hover:bg-sand/40 hover:text-rojo active:scale-[0.97]"
              >
                <X size={20} strokeWidth={1.8} aria-hidden />
              </button>
            </div>

            <nav aria-label={etiqueta} className="min-h-0 flex-1 overflow-y-auto px-2 py-2">
              <ListaSecciones
                secciones={secciones}
                activo={activo}
                onSel={onSel}
                modo="cajon"
                onElegir={() => setCajonAbierto(false)}
              />
            </nav>
          </div>
        </>
      )}
    </>
  );
}

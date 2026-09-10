"use client";

// El menú de secciones de una pantalla larga: una columna a la izquierda del
// detalle, que se pliega a iconos y que por debajo de 768px es un cajón.
//
// POR QUÉ EXISTE, Y POR QUÉ NO ES `PanelNavegacion`
//
// «Lo mío» (/mio) tenía sus ocho secciones en una tira horizontal con
// `overflow-x-auto`. Ocho pestañas no entran en una pantalla angosta, así que
// la mitad vivía fuera de la vista, detrás de un scroll lateral que no se
// anuncia — el mismo problema que el panel resolvió el 2026-09-07 cambiando su
// barra horizontal por un sidebar, y que ya se había intentado arreglar con
// scroll horizontal (688e8e5) y revertido el mismo día (21591a7).
//
// La forma es deliberadamente la del panel —mismos tokens, mismo alto de
// renglón, mismo plegado, mismo cajón— porque quien aprendió a usar uno no
// tiene que aprender el otro. Lo que NO se reutiliza es `PanelNavegacion`: ese
// componente dibuja ENLACES a rutas, agrupados y con contadores, y decide lo
// activo comparando el `pathname`. Acá no hay rutas: son BOTONES que cambian
// un estado dentro de una sola pantalla. Meter las dos ideas en un componente
// pediría que cada ítem fuera «o un href o un onClick» y que lo activo llegara
// de fuera — dos condicionales nuevas en la pieza más usada del panel, a
// cambio de compartir un mapa de clases. Lo que sí se comparte es lo que tiene
// COMPORTAMIENTO: el plegado (`useNavColapsado`) y la trampa de foco del cajón
// (`useFocoAtrapado`).

import { useRef, useState } from "react";
import { Menu, PanelLeftClose, PanelLeftOpen, X, type LucideIcon } from "lucide-react";
import { useNavColapsado } from "@/lib/use-nav-colapsado";
import { useFocoAtrapado } from "@/lib/use-foco-atrapado";
import { cx } from "@/components/ui/cx";

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

const ANCHO: Record<Exclude<ModoMenu, "cajon">, string> = {
  auto: "w-16 xl:w-56",
  rail: "w-16",
  ancho: "w-56",
};

// Lo que solo se ve ancho y lo que solo se ve en rail. En "auto" son variantes
// `xl:` porque a esa altura nadie eligió nada y el ancho lo decide la ventana,
// no React.
const SEGUN_ANCHO: Record<
  Exclude<ModoMenu, "cajon">,
  { soloAncho: string; soloRail: string; caja: string }
> = {
  auto: {
    soloAncho: "hidden xl:inline",
    soloRail: "inline xl:hidden",
    caja: "justify-center xl:justify-start xl:gap-2.5",
  },
  rail: { soloAncho: "hidden", soloRail: "inline", caja: "justify-center" },
  ancho: { soloAncho: "inline", soloRail: "hidden", caja: "gap-2.5" },
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
      {secciones.map((s) => {
        const activa = s.valor === activo;
        return (
          <button
            key={s.valor}
            type="button"
            onClick={() => {
              onSel(s.valor);
              onElegir?.();
            }}
            // `aria-current="page"`, y no un `role="tab"` con `aria-selected`,
            // porque es lo que estas secciones ya anunciaban cuando eran una
            // tira de pestañas. Un `tablist` de verdad obliga además a mover el
            // foco con las flechas y a que cada panel sea un `tabpanel`; a
            // medias sería peor que esto, que hoy es correcto.
            aria-current={activa ? "page" : undefined}
            title={s.label}
            className={cx(
              "relative flex items-center rounded-control text-left text-sm transition-colors duration-150 active:scale-[0.97]",
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
 * El menú de secciones completo: el botón de teléfono, la columna de 768px
 * para arriba y el cajón. Los tres salen de la misma lista.
 */
export function MenuDetalle<T extends string>({
  secciones,
  activo,
  onSel,
  etiqueta,
}: {
  secciones: readonly SeccionDetalle<T>[];
  activo: T;
  onSel: (valor: T) => void;
  /** Cómo se llama este menú para quien no lo ve. Ej.: «Secciones de tu perfil». */
  etiqueta: string;
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

  const actual = secciones.find((s) => s.valor === activo);

  return (
    <>
      {/* ── Teléfono: el botón que abre el cajón ────────────────────────────
          Dice en qué sección estás, que es la mitad del trabajo de un menú.
          Sin eso sería un icono suelto que no informa de nada. */}
      <button
        ref={disparador}
        type="button"
        onClick={() => setCajonAbierto(true)}
        aria-expanded={cajonAbierto}
        aria-haspopup="dialog"
        // Explícito, y no el texto de adentro: leído del contenido, este botón
        // se anuncia «Mis días Cambiar», que no dice ni qué abre ni qué es lo
        // que está pasando ahora.
        aria-label={`${etiqueta} — ahora: ${actual?.label ?? "sin elegir"}`}
        className="flex items-center gap-2 rounded-2xl border border-sand px-4 py-3 text-sm text-tinta transition-colors duration-150 hover:bg-hueso active:scale-[0.99] md:hidden print:hidden"
      >
        <Menu size={18} strokeWidth={1.8} className="shrink-0" aria-hidden />
        <span className="font-medium">{actual?.label ?? etiqueta}</span>
        <span className="ml-auto text-xs text-taupe">Cambiar</span>
      </button>

      {/* ── De 768px para arriba: la columna ────────────────────────────────
          `self-start` no es decorativo: en una fila flex los hijos se estiran a
          lo alto por defecto, y un elemento tan alto como su fila nunca llega a
          pegarse — `sticky` no tendría de dónde despegarse. */}
      <div
        className={cx(
          "sticky top-6 hidden shrink-0 flex-col self-start rounded-2xl border border-sand transition-[width] duration-150 motion-reduce:transition-none md:flex print:hidden",
          ANCHO[modo],
        )}
      >
        <nav aria-label={etiqueta} id="menu-detalle" className="p-2">
          <ListaSecciones secciones={secciones} activo={activo} onSel={onSel} modo={modo} />
        </nav>

        <div className="border-t border-sand p-2">
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
          velo, en vez de empujar la página hacia abajo. */}
      {cajonAbierto && (
        <>
          {/* `bg-black/40` y no `bg-tinta/NN`: en modo oscuro tinta ACLARA, que
              es lo contrario de lo que un velo tiene que hacer. */}
          <div
            onClick={() => setCajonAbierto(false)}
            className="fixed inset-0 z-40 bg-black/40 md:hidden"
            aria-hidden
          />
          <div
            ref={caja}
            role="dialog"
            aria-modal="true"
            aria-label={etiqueta}
            className="fixed inset-y-0 left-0 z-50 flex w-72 max-w-[85vw] flex-col border-r border-sand bg-crema md:hidden print:hidden"
          >
            <div className="flex h-16 shrink-0 items-center justify-between border-b border-sand px-4">
              <span className="etiqueta text-taupe">{etiqueta}</span>
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

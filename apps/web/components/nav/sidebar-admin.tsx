"use client";

// La columna de navegación del panel, de 1280px para arriba.
//
// Reemplaza a la barra horizontal que envolvía en tres o cuatro filas y le
// comía ~145px de alto a cada una de las 24 pantallas. El alto del encabezado
// ya no depende de cuántos renglones ve cada rol.
//
// Se queda pegada al viewport (`sticky top-0 h-screen`) y hace su propio
// scroll: para admin/DO son treinta iconos, más de lo que cabe en un portátil,
// y arrastrar la página no puede llevarse el menú con ella.

import { PanelNavegacion, type Contadores, type Modo } from "@/components/nav/panel-navegacion";
import { Colibri, Marca } from "@/components/marca";
import { cx } from "@/components/ui/cx";
import type { Grupo } from "@/app/(admin)/admin/nav-items";
import { PanelLeftClose, PanelLeftOpen } from "lucide-react";

type ModoSidebar = Exclude<Modo, "cajon">;

const ANCHO: Record<ModoSidebar, string> = {
  auto: "w-16 xl:w-64",
  rail: "w-16",
  ancho: "w-64",
};

// Lo que solo se ve ancho, lo que solo se ve en rail, y cómo se acomoda la
// caja de cada uno. En "auto" son variantes `xl:` porque a esa altura nadie
// eligió nada y el ancho lo decide la ventana, no React.
const SEGUN_ANCHO: Record<ModoSidebar, { soloAncho: string; soloRail: string; caja: string }> = {
  auto: { soloAncho: "hidden xl:flex", soloRail: "flex xl:hidden", caja: "justify-center xl:justify-start xl:gap-2.5" },
  rail: { soloAncho: "hidden", soloRail: "flex", caja: "justify-center" },
  ancho: { soloAncho: "flex", soloRail: "hidden", caja: "gap-2.5" },
};

export function SidebarAdmin({
  grupos,
  pathname,
  contadores,
  modo,
  expandido,
  onAlternar,
  cerrados,
  onAlternarGrupo,
}: {
  grupos: Grupo[];
  pathname: string;
  contadores: Contadores;
  modo: Exclude<Modo, "cajon">;
  expandido: boolean;
  onAlternar: () => void;
  cerrados: ReadonlySet<string>;
  onAlternarGrupo: (etiqueta: string) => void;
}) {
  return (
    <div
      className={cx(
        // `hidden md:flex`: por debajo de 768px no hay sidebar, hay cajón.
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
        id="nav-principal"
        aria-label="Navegación principal"
        className="min-h-0 flex-1 overflow-y-auto px-2 py-2"
      >
        <PanelNavegacion
          grupos={grupos}
          pathname={pathname}
          contadores={contadores}
          modo={modo}
          cerrados={cerrados}
          onAlternarGrupo={onAlternarGrupo}
        />
      </nav>

      <div className="shrink-0 border-t border-sand p-2">
        {/* Igual que el resto del sidebar, en modo "auto" quién manda es la CSS
            y no el estado: `expandido` recién es fiable después de montar, y
            decidir el icono con él haría parpadear el botón en cada carga. */}
        <button
          onClick={onAlternar}
          aria-expanded={expandido}
          aria-controls="nav-principal"
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
            className={SEGUN_ANCHO[modo].soloAncho}
          />
          <PanelLeftOpen
            size={16}
            strokeWidth={1.8}
            aria-hidden
            className={SEGUN_ANCHO[modo].soloRail}
          />
          <span className={cx("truncate", SEGUN_ANCHO[modo].soloAncho)}>Colapsar</span>
        </button>
      </div>
    </div>
  );
}

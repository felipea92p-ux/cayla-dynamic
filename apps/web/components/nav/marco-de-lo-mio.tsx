"use client";

// El marco de «Lo mío». Apagado es exactamente el de hoy: la misma caja con `MenuDetalle` y la pantalla. Encendido, la misma cabecera y la misma
// placa del panel, con el menú propio de Lo mío: cada persona ve un solo sistema (decisión de Felipe, 2026-11-05).

import { useCallback, useEffect, useMemo, useRef, useState, type ComponentProps, type ReactNode } from "react";
import { MenuDetalle } from "@/components/nav/menu-detalle";
import { BuscadorSecciones } from "@/components/nav/buscador-secciones";
import { MarcoVidrio } from "@/components/vidrio/marco";
import type { PersonaDeLaPlaca } from "@/components/vidrio/placa-persona";
import { interruptoresVidrio } from "@/lib/vidrio";
import { armarFilas, type HojaMenu } from "@/lib/vidrio-menu";

type PropsDelMenu<T extends string> = ComponentProps<typeof MenuDetalle<T>>;

function LoMioConVidrio<T extends string>({
  grupos,
  activo,
  onSel,
  etiqueta,
  accion,
  onSalir,
  placa,
  sede,
  alTocarPlaca,
  children,
}: PropsDelMenu<T> & {
  placa: PersonaDeLaPlaca | null;
  sede?: string | null;
  alTocarPlaca: () => void;
  children: ReactNode;
}) {
  const filas = useMemo(
    () =>
      armarFilas(
        grupos.map((g) => ({
          label: g.label,
          corto: g.corto,
          Icon: g.Icon,
          hojas: g.secciones.map((s): HojaMenu => ({ id: s.valor, etiqueta: s.label, Icon: s.Icon, n: s.contador ?? 0 })),
        })),
      ),
    [grupos],
  );
  const actual = grupos.flatMap((g) => g.secciones).find((s) => s.valor === activo);

  // ⌘K / Ctrl K, con la misma regla que `MenuDetalle`: al cerrar, el foco vuelve a donde estaba.
  const [buscador, setBuscador] = useState(false);
  const focoAntes = useRef<HTMLElement | null>(null);
  const abrirBuscador = useCallback(() => {
    focoAntes.current = document.activeElement as HTMLElement | null;
    setBuscador(true);
  }, []);
  const cerrarBuscador = useCallback(() => {
    setBuscador(false);
    focoAntes.current?.focus();
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

  return (
    <MarcoVidrio
      filas={filas}
      activa={activo}
      etiquetaMenu={etiqueta}
      alElegir={(h) => onSel(h.id as T)}
      hrefInicio="/mio"
      persona={placa}
      alTocarPlaca={alTocarPlaca}
      onSalir={onSalir ?? (() => {})}
      etiquetaBuscador="Buscar una sección"
      onBuscar={abrirBuscador}
      buscarEnCelular={false}
      sede={sede}
      accion={accion}
      tituloCelular={actual?.label ?? etiqueta}
      palabraMenu
    >
      {children}
      <BuscadorSecciones grupos={grupos} abierto={buscador} onCerrar={cerrarBuscador} onElegir={(v) => onSel(v)} />
    </MarcoVidrio>
  );
}

export function MarcoDeLoMio<T extends string>({
  placa,
  sede,
  alTocarPlaca,
  children,
  ...menu
}: PropsDelMenu<T> & {
  placa: PersonaDeLaPlaca | null;
  sede?: string | null;
  alTocarPlaca: () => void;
  children: ReactNode;
}) {
  if (interruptoresVidrio().panel) {
    return (
      <LoMioConVidrio {...menu} placa={placa} sede={sede} alTocarPlaca={alTocarPlaca}>
        {children}
      </LoMioConVidrio>
    );
  }
  return (
    // El marco de esta pantalla, con la misma forma que el del panel (`(admin)/layout.tsx`): el menú pegado al borde izquierdo y el contenido
    // ocupando el resto. En teléfono se apila, y ahí el menú es la barra pegajosa de arriba que abre el cajón.
    <div className="flex min-h-screen flex-col bg-crema text-tinta md:flex-row">
      <MenuDetalle {...menu} />
      {children}
    </div>
  );
}

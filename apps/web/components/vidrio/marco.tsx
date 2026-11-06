"use client";

// El marco con vidrio: el menú a la izquierda, la cabecera arriba y la pantalla adentro. Lo usan el panel (`marco-panel.tsx`) y Lo mío
// (`components/nav/marco-de-lo-mio.tsx`): cada persona ve un solo sistema.
//
// QUÉ PROMETE
//   Dibuja el marco con lo que le llega. No consulta nada, no decide quién ve qué, y solo existe con el interruptor encendido: apagado, el
//   marco de hoy sigue siendo el de hoy (`nav.tsx`, `menu-detalle.tsx`).
//
// QUÉ ASUME
//   La cabecera mide 64 px en todos los anchos. Retail baja a 60 en el teléfono, pero aquí hay pantallas pegadas a esos 64 (`top-16` en Datos
//   personales y Contratos): con 60, el contenido asomaría por una rendija de 4 px al desplazar.
//
// EL CAJÓN CAMBIA A LOS 768 PX, NO A LOS 640 DE RETAIL
//   Las pantallas de Dynamic ya están pensadas para perder el menú en ese ancho (todo su `md:`). Entre 640 y 767 caben un teléfono de lado y
//   una tablet chica: ahí una columna de 84 px deja 556 px para una tabla.

import { useEffect, useRef, useState, useSyncExternalStore, type ReactNode } from "react";
import Link from "next/link";
import { Menu, Search, X } from "lucide-react";
import { alejarFondo, devolverFondo, moverFondo } from "@/lib/fondo-de-la-hoja";
import { useAtrasCierraLaHoja } from "@/lib/use-atras-cierra-la-hoja";
import { useFocoAtrapado } from "@/lib/use-foco-atrapado";
import { useCerrarConElDedo } from "@/lib/use-cerrar-con-el-dedo";
import { useEsCelular, useLateralPlegado } from "@/lib/use-vidrio-lateral";
import { alternarLateral } from "@/lib/vidrio-lateral";
import type { FilaMenu, HojaMenu } from "@/lib/vidrio-menu";
import { BotonTema } from "@/components/vidrio/boton-tema";
import { LogoCayla } from "@/components/vidrio/logo-cayla";
import { MenuFilas } from "@/components/vidrio/menu";
import { OndaBotones } from "@/components/vidrio/onda-botones";
import { PlacaPersona, type PersonaDeLaPlaca } from "@/components/vidrio/placa-persona";

// La tecla que se muestra es la de la máquina que se tiene delante. Retail y el Dynamic de hoy muestran una sola para todos.
const nada = () => () => {};
function useTeclaDelBuscador(): string {
  return useSyncExternalStore(
    nada,
    () => (/mac|iphone|ipad/i.test(navigator.platform) ? "⌘K" : "Ctrl K"),
    () => "",
  );
}

export function MarcoVidrio({
  filas,
  activa,
  etiquetaMenu,
  notaDeSuma,
  alElegir,
  hrefInicio,
  persona,
  placaHref,
  alTocarPlaca,
  onSalir,
  etiquetaBuscador,
  onBuscar,
  buscarEnCelular = true,
  sede,
  accion,
  tituloCelular,
  palabraMenu = false,
  children,
}: {
  filas: readonly FilaMenu[];
  activa: string | null;
  etiquetaMenu: string;
  notaDeSuma?: string;
  alElegir?: (hoja: HojaMenu) => void;
  hrefInicio: string;
  persona: PersonaDeLaPlaca | null;
  placaHref?: string;
  alTocarPlaca?: () => void;
  onSalir: () => void;
  etiquetaBuscador: string;
  onBuscar: () => void;
  /** Lo mío no ofrece su buscador en el teléfono: son pocas secciones y el menú está a un toque. */
  buscarEnCelular?: boolean;
  /** Líder de equipo e integrante ven su sede; DO y administración, nada: mira todas las sedes. */
  sede?: string | null;
  /** Lo que va a la derecha antes del tema. En Lo mío, «Volver al panel». */
  accion?: ReactNode;
  /** Dónde estás, en la barra del teléfono. Lo mío lo necesita porque sus secciones no tienen título propio arriba. */
  tituloCelular?: string;
  /** La palabra «Menú» junto al botón: en Lo mío se probó con gente, y sin ella no lo encontraban (2026-09-11). */
  palabraMenu?: boolean;
  children: ReactNode;
}) {
  const plegado = useLateralPlegado();
  const celular = useEsCelular();
  const compacto = plegado && !celular;

  const [cajon, setCajon] = useState(false);
  // Girar una tablet con el cajón abierto: en ese ancho el menú ya está siempre a la vista.
  if (cajon && !celular) setCajon(false);

  const aside = useRef<HTMLElement>(null);
  const velo = useRef<HTMLDivElement>(null);
  const hamburguesa = useRef<HTMLButtonElement>(null);
  const cerrarCajon = () => setCajon(false);

  // Lo de atrás se corre de costado mientras el menú está abierto, y vuelve con él (también al ritmo del dedo). Mismos tiempos que `.marco-riel` en marco.css.
  const fondo = useRef<symbol | null>(null);
  useEffect(() => {
    if (!cajon || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const llave = alejarFondo(420, "lado");
    fondo.current = llave;
    return () => {
      devolverFondo(llave, 260, "var(--vidrio-ease-salida)");
      fondo.current = null;
    };
  }, [cajon]);

  useFocoAtrapado({ abierto: cajon, onCerrar: cerrarCajon, caja: aside, volverElFocoA: hamburguesa });
  useCerrarConElDedo(aside, velo, cajon, cerrarCajon, (progreso, ms) => moverFondo(fondo.current, progreso, ms));
  useAtrasCierraLaHoja(cajon, cerrarCajon);

  // Con el cajón abierto, la pantalla de atrás no se desplaza.
  useEffect(() => {
    if (!cajon) return;
    const antes = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = antes;
    };
  }, [cajon]);

  // La tecla «[», como en Retail. No se dispara escribiendo, con un modificador ni con una ventana abierta.
  useEffect(() => {
    const alTeclado = (e: KeyboardEvent) => {
      if (e.key !== "[" || e.metaKey || e.ctrlKey || e.altKey) return;
      if (e.target instanceof Element && e.target.closest("input, textarea, select, [contenteditable=''], [contenteditable='true'], [role='dialog']")) return;
      e.preventDefault();
      alternarLateral();
    };
    document.addEventListener("keydown", alTeclado);
    return () => document.removeEventListener("keydown", alTeclado);
  }, []);

  const tecla = useTeclaDelBuscador();

  return (
    <div className="marco-raiz flex min-h-screen w-full min-w-0 flex-1">
      <OndaBotones />
      {/* Siempre montado, para que también se apague al cerrar; cerrado no recibe toques. */}
      <div
        ref={velo}
        aria-hidden
        data-abierto={cajon}
        onClick={cerrarCajon}
        className={`velo-cajon fixed inset-0 z-40 md:hidden print:hidden ${cajon ? "" : "pointer-events-none"}`}
      />

      <aside
        id="lateral"
        ref={aside}
        aria-label="Menú principal"
        role={cajon ? "dialog" : undefined}
        aria-modal={cajon ? true : undefined}
        data-cajon={cajon ? "abierto" : undefined}
        // Tocar un destino cierra el cajón del teléfono. En la computadora no hay nada que cerrar.
        onClick={(e) => {
          if (cajon && e.target instanceof Element && e.target.closest("a, [data-hoja]")) cerrarCajon();
        }}
        className="marco-riel print:hidden"
      >
        <div className="flex items-start" data-pieza-cajon style={{ "--k": 0 } as React.CSSProperties}>
          <Link href={hrefInicio} aria-label="CAYLA Dynamic, ir al inicio" className="marco-logo group">
            <LogoCayla className="marco-logo-dibujo" />
            <span aria-hidden className="marco-logo-sistema">Dynamic</span>
          </Link>
          <button
            type="button"
            onClick={cerrarCajon}
            aria-label="Cerrar menú"
            className="mr-3 mt-6 grid size-10 shrink-0 place-items-center rounded-lg text-tinta/65 transition-colors hover:bg-sand/60 hover:text-rojo md:hidden"
          >
            <X size={20} strokeWidth={1.8} aria-hidden />
          </button>
        </div>

        <MenuFilas
          filas={filas}
          activa={activa}
          etiqueta={etiquetaMenu}
          notaDeSuma={notaDeSuma}
          compacto={compacto}
          celular={celular}
          alElegir={alElegir}
        />

        <PlacaPersona persona={persona} href={placaHref} alTocar={alTocarPlaca} onSalir={onSalir} />
      </aside>

      {/* Fuera del <aside>, que recorta: la gota sobresale de su borde. Viaja con él al plegar. Bajo 768 px no se ve: ahí el menú tiene su ✕. */}
      <button
        type="button"
        onClick={alternarLateral}
        aria-label={compacto ? "Abrir el menú" : "Plegar el menú"}
        aria-expanded={!compacto}
        aria-controls="lateral"
        title={`${compacto ? "Abrir" : "Plegar"} el menú  ( [ )`}
        className="marco-plegar print:hidden"
      >
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
          <path d="M15 6l-6 6 6 6" />
        </svg>
      </button>

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="marco-cabecera print:hidden" data-fondo-hoja="borde" data-con-titulo={tituloCelular ? "" : undefined}>
          <div className="marco-cabecera-fila">
            <div className="marco-isla marco-isla-izq">
              <button
                ref={hamburguesa}
                type="button"
                onClick={() => setCajon(true)}
                aria-label="Abrir menú"
                aria-expanded={cajon}
                aria-controls="lateral"
                className="marco-boton-menu hidden"
              >
                <Menu size={20} strokeWidth={1.8} aria-hidden />
                {palabraMenu ? <span aria-hidden>Menú</span> : null}
              </button>
              <button
                type="button"
                onClick={onBuscar}
                aria-label={etiquetaBuscador}
                className={`marco-buscador ${buscarEnCelular ? "flex" : "hidden md:flex"} items-center gap-2.5 rounded-full border px-3.5 text-[13px] text-tinta/70`}
              >
                <Search size={16} strokeWidth={1.8} aria-hidden className="shrink-0" />
                <span className="marco-buscador-texto truncate">Buscar…</span>
                <kbd className="marco-buscador-tecla ml-auto font-sans text-[11px] text-tinta/70">{tecla}</kbd>
              </button>
              {/* En un teléfono ancho, el colibrí junto al menú, como en Retail. Lo mío tiene ahí su título. */}
              {tituloCelular ? null : (
                <Link href={hrefInicio} aria-label="CAYLA Dynamic, ir al inicio" className="marco-colibri hidden">
                  <LogoCayla soloColibri className="h-[26px]" />
                </Link>
              )}
            </div>

            {/* Dónde estás. `aria-live`: el cajón se cierra encima del cambio y quien no ve la pantalla no oiría nada. */}
            {tituloCelular ? (
              <p aria-live="polite" className="marco-titulo-celular hidden">{tituloCelular}</p>
            ) : null}

            <div className="marco-isla marco-isla-der">
              {sede ? <span className="marco-sede">{sede}</span> : null}
              {accion}
              <BotonTema />
              {/* En el teléfono el buscador es una lupa suelta al final, como en Retail. Los dos botones hacen lo mismo y solo uno se ve a la vez. */}
              {buscarEnCelular ? (
                <button type="button" onClick={onBuscar} aria-label={etiquetaBuscador} className="marco-lupa hidden">
                  <Search size={16} strokeWidth={1.8} aria-hidden />
                </button>
              ) : null}
            </div>
          </div>
        </header>

        {/* Lo de atrás de una hoja en el teléfono: se aleja como una tarjeta. No agrega nada a la página: la misma columna que tenía el contenido. */}
        <div data-fondo-hoja className="flex min-w-0 flex-1 flex-col">
          {children}
        </div>
      </div>
    </div>
  );
}

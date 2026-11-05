"use client";

// Las filas del menú con vidrio: las sueltas, los módulos que se abren de a uno, la ficha que se desliza a la fila donde estás y, con el
// menú plegado, la hoja que flota al lado con las pantallas de un módulo. La forma es la de Retail (components/AppShell.tsx); el dibujo
// vive en app/estilos/vidrio/marco.css.
//
// QUÉ PROMETE
//   Dibuja lo que le llega y avisa qué hoja se tocó. No decide quién ve qué ni sabe de rutas: `activa` y las filas llegan de afuera.
//
// LO QUE DEPENDE DEL ANCHO VIVE EN LA HOJA DE ESTILOS
//   Si el menú está plegado lo decide `data-lateral` en <html> antes de pintar. `compacto` solo cambia lo que un toque hace.

import { useCallback, useEffect, useLayoutEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";
import { createPortal } from "react-dom";
import Link from "next/link";
import { ChevronRight } from "lucide-react";
import {
  claveDeLaActiva,
  esModulo,
  moduloDeLaHoja,
  sumaDelModulo,
  tituloDelModulo,
  type FilaMenu,
  type HojaMenu,
  type ModuloMenu,
} from "@/lib/vidrio-menu";
import { Globito } from "@/components/vidrio/globito";

const claseFila = (activa: boolean) =>
  `marco-fila group flex w-full items-center gap-3 overflow-hidden whitespace-nowrap ${
    activa ? "font-semibold text-tinta" : "text-tinta/80 hover:bg-tinta/6 hover:text-tinta"
  }`;
const claseIcono = (activa: boolean, tamano: string) =>
  `marco-icono shrink-0 transition-colors duration-300 ease-cayla ${tamano} ${activa ? "text-tinta" : "text-tinta/60 group-hover:text-tinta"}`;
const claseEtiqueta = "marco-etiqueta min-w-0 flex-1 truncate text-left";

type Eventos = {
  onMouseEnter?: (e: React.MouseEvent<HTMLElement>) => void;
  onMouseLeave?: () => void;
  onFocus?: (e: React.FocusEvent<HTMLElement>) => void;
  onBlur?: () => void;
};

/** Una pantalla: un enlace si tiene dirección, un botón si cambia de sección sin salir (Lo mío). */
function FilaHoja({
  hoja,
  prof,
  activa,
  alElegir,
  eventos,
  children,
}: {
  hoja: HojaMenu;
  prof: 0 | 1;
  activa: boolean;
  alElegir?: (hoja: HojaMenu) => void;
  eventos?: Eventos;
  children?: ReactNode;
}) {
  const datos = { "data-prof": prof, "data-fila-activa": activa ? "" : undefined };
  const contenido = (
    <>
      <hoja.Icon strokeWidth={1.8} aria-hidden className={claseIcono(activa, prof === 0 ? "size-5" : "size-4")} />
      <span className={claseEtiqueta}>{hoja.etiqueta}</span>
      {children}
      <Globito n={hoja.n} etiqueta={hoja.titulo} />
    </>
  );
  return hoja.href ? (
    <Link href={hoja.href} title={hoja.titulo} aria-current={activa ? "page" : undefined} {...datos} {...eventos} className={claseFila(activa)}>
      {contenido}
    </Link>
  ) : (
    <button
      type="button"
      data-hoja
      title={hoja.titulo}
      aria-current={activa ? "page" : undefined}
      onClick={() => alElegir?.(hoja)}
      {...datos}
      {...eventos}
      className={claseFila(activa)}
    >
      {contenido}
    </button>
  );
}

export function MenuFilas({
  filas,
  activa,
  etiqueta,
  notaDeSuma,
  compacto,
  celular,
  alElegir,
}: {
  filas: readonly FilaMenu[];
  /** El id de la hoja de la pantalla en la que se está. */
  activa: string | null;
  /** Cómo se llama este menú para quien no lo ve. */
  etiqueta: string;
  notaDeSuma?: string;
  compacto: boolean;
  celular: boolean;
  alElegir?: (hoja: HojaMenu) => void;
}) {
  const moduloActivo = moduloDeLaHoja(filas, activa);

  // De a uno: el módulo de la pantalla se abre solo y, al cambiar de módulo, el anterior se cierra. Se ajusta durante el render (el patrón
  // que React documenta): las filas llegan después de la sesión, así que el módulo activo puede aparecer un momento después de montar.
  const [abierto, setAbierto] = useState<string | null>(moduloActivo);
  const [moduloAnterior, setModuloAnterior] = useState(moduloActivo);
  if (moduloActivo !== moduloAnterior) {
    setModuloAnterior(moduloActivo);
    if (moduloActivo) setAbierto(moduloActivo);
  }
  const [tocado, setTocado] = useState<string | null>(null);

  // ---- Con el menú plegado: el nombre de una fila suelta y la hoja de un módulo, de a uno ----
  const [nombre, setNombre] = useState<{ texto: string; top: number; left: number } | null>(null);
  const [flotante, setFlotante] = useState<{ modulo: string; top: number; left: number; enfocar: boolean } | null>(null);
  const relojAbrir = useRef(0);
  const relojCerrar = useRef(0);

  const mantener = () => window.clearTimeout(relojCerrar.current);
  const cerrarFlotante = (devolverFoco = false) => {
    window.clearTimeout(relojAbrir.current);
    window.clearTimeout(relojCerrar.current);
    if (flotante && devolverFoco) document.querySelector<HTMLElement>(`[data-modulo-id="${CSS.escape(flotante.modulo)}"]`)?.focus();
    setFlotante(null);
  };
  // Con gracia: cruzar del menú a la hoja no la cierra. Se limpia el reloj anterior antes de poner otro para que `mantener` lo alcance.
  const programarCierre = () => {
    window.clearTimeout(relojAbrir.current);
    window.clearTimeout(relojCerrar.current);
    relojCerrar.current = window.setTimeout(() => setFlotante(null), 260);
  };
  const abrirFlotante = (modulo: ModuloMenu, el: HTMLElement, enfocar: boolean) => {
    mantener();
    const r = el.getBoundingClientRect();
    const alto = 16 + 34 + modulo.hojas.length * 44;
    setNombre(null);
    setFlotante({
      modulo: modulo.id,
      top: Math.max(64, Math.min(r.top - 8, window.innerHeight - alto - 12)),
      left: r.right + 18,
      enfocar,
    });
  };
  const entrarFila = (el: HTMLElement, texto: string, modulo?: ModuloMenu) => {
    if (!compacto) return;
    mantener();
    if (modulo) {
      setNombre(null);
      window.clearTimeout(relojAbrir.current);
      relojAbrir.current = window.setTimeout(() => abrirFlotante(modulo, el, false), 120);
    } else {
      const r = el.getBoundingClientRect();
      setFlotante(null);
      setNombre({ texto, top: r.top + r.height / 2, left: r.right + 18 });
    }
  };
  const salirFila = () => {
    setNombre(null);
    programarCierre();
  };

  useEffect(() => {
    if (compacto) return;
    // Al abrir el menú ya no hay nada flotando. Se limpia aquí y no al tocar el botón: la tecla «[» y el ancho de la ventana también lo abren.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setFlotante(null);
    setNombre(null);
  }, [compacto]);

  const moduloAbierto = compacto ? null : abierto;
  const claveActiva = claveDeLaActiva(filas, activa, moduloAbierto);

  // ---- La ficha de la fila donde estás ----
  // Una sola para todo el menú, ubicada midiendo la fila. Al navegar viaja a la fila nueva; cuando un módulo se abre o el menú se pliega,
  // acompaña a su fila cuadro a cuadro y sin transición, para no quedarse atrás mientras las cajas cambian de alto.
  const navRef = useRef<HTMLElement | null>(null);
  const gotaRef = useRef<HTMLSpanElement | null>(null);
  const relojGota = useRef(0);
  const claveAnterior = useRef<string | null>(null);

  const ponerGota = useCallback((animar: boolean) => {
    const nav = navRef.current;
    const gota = gotaRef.current;
    if (!nav || !gota) return;
    const fila = nav.querySelector<HTMLElement>("[data-fila-activa]");
    if (!fila || fila.offsetHeight < 1) {
      gota.removeAttribute("data-lista");
      return;
    }
    let top = 0;
    let left = 0;
    for (let el: HTMLElement | null = fila; el && el !== nav; el = el.offsetParent as HTMLElement | null) {
      top += el.offsetTop;
      left += el.offsetLeft;
    }
    // Recién encendida aparece en su lugar: viajar desde la esquina sería un adorno.
    gota.toggleAttribute("data-quieta", !animar || !gota.hasAttribute("data-lista"));
    gota.style.top = `${top}px`;
    gota.style.left = `${left}px`;
    gota.style.width = `${fila.offsetWidth}px`;
    gota.style.height = `${fila.offsetHeight}px`;
    gota.style.setProperty("--k", fila.closest<HTMLElement>("[data-pieza-cajon]")?.style.getPropertyValue("--k") || "0");
    gota.setAttribute("data-lista", "");
  }, []);

  useLayoutEffect(() => {
    const navego = claveAnterior.current !== null && claveAnterior.current !== claveActiva;
    claveAnterior.current = claveActiva;
    cancelAnimationFrame(relojGota.current);
    // 520 ms: lo que tarda en abrirse una caja (460) con algo de aire, y de sobra para el plegado (300).
    const fin = performance.now() + 520;
    const paso = () => {
      ponerGota(navego);
      if (performance.now() < fin) relojGota.current = requestAnimationFrame(paso);
      else gotaRef.current?.removeAttribute("data-quieta");
    };
    paso();
    return () => cancelAnimationFrame(relojGota.current);
  }, [claveActiva, moduloAbierto, compacto, celular, filas.length, ponerGota]);

  useEffect(() => {
    const alCambiar = () => ponerGota(false);
    window.addEventListener("resize", alCambiar);
    return () => window.removeEventListener("resize", alCambiar);
  }, [ponerGota]);

  const moduloFlotante = compacto && flotante ? filas.find((f): f is ModuloMenu => esModulo(f) && f.id === flotante.modulo) : undefined;

  return (
    <nav
      ref={navRef}
      id="nav-principal"
      aria-label={etiqueta}
      className="relative min-h-0 flex-1 overflow-y-auto overflow-x-hidden"
      onMouseLeave={programarCierre}
      onMouseEnter={mantener}
    >
      <span ref={gotaRef} aria-hidden className="marco-gota" />
      <div className="relative flex flex-col">
        {filas.map((f, n) => {
          const margen = { "--k": 1 + n } as CSSProperties;
          if (!esModulo(f)) {
            const esActiva = claveActiva === `h:${f.id}`;
            return (
              <div key={f.id} data-pieza-cajon style={margen}>
                <FilaHoja
                  hoja={f}
                  prof={0}
                  activa={esActiva}
                  alElegir={alElegir}
                  eventos={{
                    onMouseEnter: (e) => entrarFila(e.currentTarget, f.etiqueta),
                    onMouseLeave: salirFila,
                    onFocus: (e) => entrarFila(e.currentTarget, f.etiqueta),
                    onBlur: salirFila,
                  }}
                >
                  <span aria-hidden className="marco-corto">{f.corto ?? f.etiqueta}</span>
                </FilaHoja>
              </div>
            );
          }

          const abre = moduloAbierto === f.id;
          const esActiva = claveActiva === `m:${f.id}`;
          const contieneActiva = moduloActivo === f.id;
          const suma = sumaDelModulo(f);
          const titulo = tituloDelModulo(f, notaDeSuma);
          return (
            <div key={f.id} data-pieza-cajon style={margen}>
              <button
                type="button"
                data-modulo-id={f.id}
                title={titulo}
                onClick={(e) => {
                  if (compacto) {
                    abrirFlotante(f, e.currentTarget, true);
                    return;
                  }
                  setTocado(f.id);
                  setAbierto((a) => (a === f.id ? null : f.id));
                }}
                onMouseEnter={(e) => entrarFila(e.currentTarget, f.etiqueta, f)}
                onMouseLeave={salirFila}
                aria-haspopup={compacto ? "menu" : undefined}
                aria-expanded={compacto ? flotante?.modulo === f.id : abre}
                data-prof={0}
                data-fila-activa={esActiva ? "" : undefined}
                data-asiente={abre && tocado === f.id ? "" : undefined}
                className={claseFila(esActiva)}
              >
                <f.Icon strokeWidth={1.8} aria-hidden className={claseIcono(esActiva || contieneActiva, "size-5")} />
                <span className={claseEtiqueta}>{f.etiqueta}</span>
                <span aria-hidden className="marco-corto">{f.corto ?? f.etiqueta}</span>
                {/* Cerrado o plegado no se ven sus hojas: el número sube a esta fila para que se vea igual. */}
                {abre ? null : <Globito n={suma} etiqueta={titulo} />}
                <ChevronRight
                  strokeWidth={1.8}
                  aria-hidden
                  className={`marco-chevron size-3.5 shrink-0 text-tinta/50 transition-transform duration-300 ease-cayla ${abre ? "rotate-90" : ""}`}
                />
              </button>
              {/* Siempre montadas para poder animar el despliegue; cerradas miden 0 y quedan fuera del tabulador (`inert`). */}
              <div className="lateral-hijos" data-abierto={abre} inert={!abre}>
                <div>
                  {f.hojas.map((h, i) => (
                    <div key={h.id} className="lateral-hijo" style={{ "--i": i } as CSSProperties}>
                      <FilaHoja hoja={h} prof={1} activa={claveActiva === `h:${h.id}`} alElegir={alElegir} />
                    </div>
                  ))}
                </div>
              </div>
            </div>
          );
        })}
      </div>

      {/* En un portal: el <nav> y el <aside> recortan lo que se sale, y un nombre cortado a la mitad es peor que ninguno. */}
      {compacto && nombre && !moduloFlotante
        ? createPortal(
            <div
              role="tooltip"
              style={{ top: nombre.top, left: nombre.left }}
              className="pointer-events-none fixed z-[35] -translate-y-1/2 whitespace-nowrap rounded-lg bg-tinta px-3 py-1.5 text-[13px] font-medium text-crema"
            >
              {nombre.texto}
            </div>,
            document.body,
          )
        : null}
      {moduloFlotante && flotante
        ? createPortal(
            <HojaDelModulo
              key={moduloFlotante.id}
              modulo={moduloFlotante}
              top={flotante.top}
              left={flotante.left}
              activa={activa}
              enfocar={flotante.enfocar}
              alElegir={alElegir}
              onCerrar={cerrarFlotante}
              onEntrar={mantener}
              onSalir={programarCierre}
            />,
            document.body,
          )
        : null}
    </nav>
  );
}

/**
 * Las pantallas de un módulo con el menú plegado. Es un MENÚ, no un diálogo: no atrapa el foco; Tab y Escape lo cierran y devuelven el foco a
 * la fila que lo abrió. Se abre de dos maneras: con un toque o Enter (el foco entra a la primera pantalla) o pasando el mouse 120 ms
 * (el foco no se mueve: es mirar, no elegir).
 */
function HojaDelModulo({
  modulo,
  top,
  left,
  activa,
  enfocar,
  alElegir,
  onCerrar,
  onEntrar,
  onSalir,
}: {
  modulo: ModuloMenu;
  top: number;
  left: number;
  activa: string | null;
  enfocar: boolean;
  alElegir?: (hoja: HojaMenu) => void;
  onCerrar: (devolverFoco?: boolean) => void;
  onEntrar: () => void;
  onSalir: () => void;
}) {
  const filas = useRef<(HTMLElement | null)[]>([]);
  useEffect(() => {
    if (!enfocar) return;
    filas.current[Math.max(0, modulo.hojas.findIndex((h) => h.id === activa))]?.focus();
  }, [enfocar, modulo, activa]);

  function alTeclado(e: React.KeyboardEvent<HTMLDivElement>) {
    const vivas = filas.current.filter((f): f is HTMLElement => f !== null);
    const i = vivas.indexOf(document.activeElement as HTMLElement);
    const mover = (a: number) => {
      e.preventDefault();
      vivas[(a + vivas.length) % vivas.length]?.focus();
    };
    if (e.key === "ArrowDown") mover(i + 1);
    else if (e.key === "ArrowUp") mover(i <= 0 ? vivas.length - 1 : i - 1);
    else if (e.key === "Home") mover(0);
    else if (e.key === "End") mover(vivas.length - 1);
    else if (e.key === "Escape") {
      e.preventDefault();
      onCerrar(true);
    } else if (e.key === "Tab") onCerrar(false);
    else if (e.key === " ") {
      e.preventDefault();
      vivas[i]?.click();
    }
  }

  return (
    <div
      role="menu"
      aria-label={modulo.etiqueta}
      onKeyDown={alTeclado}
      onMouseEnter={onEntrar}
      onMouseLeave={onSalir}
      style={{ top, left }}
      className="marco-cajon-grupo fixed z-[35] w-[15rem] p-2"
    >
      <p aria-hidden className="marco-cajon-titulo px-3 pb-1.5 pt-2">{modulo.etiqueta}</p>
      {modulo.hojas.map((h, i) => {
        const esActiva = h.id === activa;
        const clase = `marco-cajon-fila group relative flex h-11 w-full items-center gap-3 px-3 text-left text-sm outline-none transition-colors focus-visible:bg-tinta/6 ${
          esActiva ? "font-semibold text-tinta" : "text-tinta/80 hover:bg-tinta/6 hover:text-tinta"
        }`;
        const contenido = (
          <>
            <h.Icon strokeWidth={1.8} aria-hidden className={`size-5 shrink-0 transition-colors ${esActiva ? "text-tinta" : "text-tinta/60 group-hover:text-tinta"}`} />
            <span className="min-w-0 flex-1 truncate">{h.etiqueta}</span>
            <Globito n={h.n} etiqueta={h.titulo} />
          </>
        );
        return h.href ? (
          <Link
            key={h.id}
            href={h.href}
            role="menuitem"
            tabIndex={-1}
            title={h.titulo}
            aria-current={esActiva ? "page" : undefined}
            ref={(el) => {
              filas.current[i] = el;
            }}
            onClick={() => onCerrar(false)}
            className={clase}
          >
            {contenido}
          </Link>
        ) : (
          <button
            key={h.id}
            type="button"
            role="menuitem"
            tabIndex={-1}
            title={h.titulo}
            aria-current={esActiva ? "page" : undefined}
            ref={(el) => {
              filas.current[i] = el;
            }}
            onClick={() => {
              alElegir?.(h);
              onCerrar(false);
            }}
            className={clase}
          >
            {contenido}
          </button>
        );
      })}
    </div>
  );
}

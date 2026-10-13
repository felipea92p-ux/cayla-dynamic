"use client";

import { Suspense, useEffect, type ComponentProps, type MouseEvent } from "react";
import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { alCambiarLaDireccion, elDestinoEsLaPaginaAnterior } from "@/lib/volver-atras";

// El enlace «← Volver…» / «Cancelar» de las pantallas de «Lo mío», y el vigía
// que le permite saber de dónde se llegó. La regla —y por qué no basta un
// `router.back()` a secas— está en `lib/volver-atras.ts`.

/**
 * Un enlace que, si la página anterior ES su destino, retrocede en vez de abrir
 * una página nueva: así «atrás» después de volver no te devuelve a lo que
 * acabas de cerrar. Si no, es un enlace común. Conserva el clic con ⌘/Ctrl
 * (abrir en otra pestaña) y el clic central.
 */
export function EnlaceVolver({ href, onClick, ...resto }: Omit<ComponentProps<typeof Link>, "href"> & { href: string }) {
  const router = useRouter();

  function alTocar(e: MouseEvent<HTMLAnchorElement>) {
    onClick?.(e);
    if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    if (!elDestinoEsLaPaginaAnterior(href)) return;
    e.preventDefault();
    router.back();
  }

  return <Link href={href} onClick={alTocar} {...resto} />;
}

/**
 * Anota cada dirección de «Lo mío» y cada retroceso por el historial. Va en el
 * layout, una sola vez: tiene que ver la PRIMERA dirección del documento.
 */
export function SeguirRuta() {
  return (
    <Suspense fallback={null}>
      <Vigia />
    </Suspense>
  );
}

function Vigia() {
  const ruta = usePathname();
  const parametros = useSearchParams().toString();

  // `ruta` y `parametros` solo avisan CUÁNDO mirar: lo que se anota es la
  // dirección real del navegador, que ya cambió cuando Next se entera.
  useEffect(() => {
    alCambiarLaDireccion(window.location.pathname + window.location.search);
  }, [ruta, parametros]);

  // «Atrás» y «adelante»: `popstate` llega con la dirección ya cambiada, y se
  // anota ANTES de que Next vuelva a pintar, así el efecto de arriba la
  // encuentra igual y no la cuenta como una navegación nueva.
  useEffect(() => {
    const alMoverseEnElHistorial = () =>
      alCambiarLaDireccion(window.location.pathname + window.location.search, true);
    window.addEventListener("popstate", alMoverseEnElHistorial);
    return () => window.removeEventListener("popstate", alMoverseEnElHistorial);
  }, []);

  return null;
}

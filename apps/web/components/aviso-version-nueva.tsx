"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { RefreshCw, X } from "lucide-react";
import { Boton } from "@/components/ui/boton";
import { BotonIcono } from "@/components/ui/boton-icono";
import { CADA_CUANTO_MS, VERSION_DE_ESTA_PAGINA, hayVersionNueva } from "@/lib/version-despliegue";

// La barra que baja desde arriba cuando Vercel publicó una versión nueva
// mientras la pestaña seguía abierta. Se monta en el panel y en «Lo mío»; NO en
// el terminal, y a propósito: es la pantalla de marcar de la sede, la toca
// cualquiera, y una persona que pasa a marcar no debería poder recargarla a
// medio turno por un aviso que no es para ella. El terminal tiene su propio
// service worker y su cola sin conexión; sumarle esto es una decisión aparte.
//
// NUNCA recarga sola (ver lib/version-despliegue.ts): quien tiene la pantalla
// abierta puede estar escribiendo algo que no se guardó. «Más tarde» la
// descarta hasta que llegue OTRA versión distinta; recargar a mano la quita.
const CLAVE_DESCARTADA = "cayla-version-descartada";

function leerDescartada(): string | null {
  try {
    return sessionStorage.getItem(CLAVE_DESCARTADA);
  } catch {
    return null; // Sin sessionStorage el aviso vuelve a salir en cada carga: molesta, no rompe nada.
  }
}

export function AvisoVersionNueva() {
  const [nueva, setNueva] = useState<string | null>(null);
  // La que se descartó en esta carga. La memoria de sessionStorage no basta sola:
  // sin ella, un navegador que no deja guardar volvería a mostrar el aviso en la
  // siguiente consulta, a los tres minutos de haberlo cerrado.
  const descartada = useRef<string | null>(null);

  const preguntar = useCallback(async () => {
    const ctrl = new AbortController();
    const corte = setTimeout(() => ctrl.abort(), 8000);
    try {
      const r = await fetch(`/api/version?t=${Date.now()}`, { cache: "no-store", signal: ctrl.signal });
      if (!r.ok) return;
      const { version } = (await r.json()) as { version?: unknown };
      if (!hayVersionNueva(VERSION_DE_ESTA_PAGINA, version)) return;
      if (version === descartada.current || version === leerDescartada()) return;
      setNueva(version);
    } catch {
      // Sin internet, un corte o una respuesta rota: no es una versión nueva, y
      // un aviso de «no pude saber» no le sirve a nadie. Se vuelve a preguntar solo.
    } finally {
      clearTimeout(corte);
    }
  }, []);

  useEffect(() => {
    if (!VERSION_DE_ESTA_PAGINA) return; // fuera de Vercel no hay con qué comparar
    if (nueva) return; // ya se sabe; seguir preguntando no cambia nada

    const siEstaALaVista = () => {
      if (document.visibilityState === "visible") void preguntar();
    };
    const intervalo = setInterval(siEstaALaVista, CADA_CUANTO_MS);
    // Al volver a la pestaña, sin esperar al siguiente turno del reloj: es el
    // momento en que alguien con la pestaña dormida horas se la encuentra vieja.
    document.addEventListener("visibilitychange", siEstaALaVista);
    window.addEventListener("online", siEstaALaVista);
    window.addEventListener("pageshow", siEstaALaVista);
    return () => {
      clearInterval(intervalo);
      document.removeEventListener("visibilitychange", siEstaALaVista);
      window.removeEventListener("online", siEstaALaVista);
      window.removeEventListener("pageshow", siEstaALaVista);
    };
  }, [nueva, preguntar]);

  if (!nueva) return null;

  function masTarde() {
    descartada.current = nueva;
    try {
      sessionStorage.setItem(CLAVE_DESCARTADA, nueva!);
    } catch {
      // Se descartó en pantalla igual; solo no se acuerda si recargan.
    }
    setNueva(null); // el efecto vuelve a preguntar: si llega OTRA versión, esa sí sale
  }

  return (
    <div
      role="status"
      className="aviso-baja fixed inset-x-0 top-0 z-[65] border-b border-borde-control bg-papel shadow-xl print:hidden"
    >
      <div className="mx-auto flex max-w-5xl flex-wrap items-center gap-x-4 gap-y-2 px-4 py-2.5 text-sm sm:px-6">
        <RefreshCw size={16} strokeWidth={1.8} aria-hidden className="shrink-0 text-taupe" />
        <p className="min-w-0 flex-1 basis-60">
          <b className="font-medium">Hay una versión nueva de Dynamic.</b>{" "}
          <span className="text-taupe">Guarda lo que estás haciendo y actualiza.</span>
        </p>
        <div className="flex shrink-0 items-center gap-2">
          <Boton variante="primario" tamano="sm" onClick={() => window.location.reload()}>
            Actualizar ahora
          </Boton>
          <BotonIcono etiqueta="Más tarde" icono={<X size={14} strokeWidth={1.8} aria-hidden />} onClick={masTarde} />
        </div>
      </div>
    </div>
  );
}

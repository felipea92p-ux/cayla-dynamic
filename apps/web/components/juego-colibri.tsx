"use client";

// El juego del colibrí dentro del panel: el easter egg del buscador (escribe
// «colibrí» en ⌘K). Es el MISMO juego que ve quien abre Dynamic sin internet
// (`/sin-conexion.html`): el motor vive en `public/colibri/juego.js`, suelto de
// React, justamente para que los dos sitios no tengan cada uno su copia. Lo que
// hace cada juego y cómo se sortea está en ese archivo.
//
// El motor se carga como un archivo estático, no como parte del paquete de Next,
// y se carga SOLO cuando alguien abre el juego: quien nunca lo busca no descarga
// ni un byte de él.

import { useEffect, useRef, useState } from "react";
import { Modal } from "@/components/ui/modal";

type Motor = { montar: (canvas: HTMLCanvasElement, opciones?: { variante?: string | null }) => { detener: () => void } };

// En una variable y con `webpackIgnore`: así el empaquetador lo deja como una
// importación del navegador, tal cual, en vez de intentar resolver una ruta de `public/`.
const RUTA_DEL_MOTOR = "/colibri/juego.js";

export function JuegoColibri({ abierto, onCerrar }: { abierto: boolean; onCerrar: () => void }) {
  const lienzo = useRef<HTMLCanvasElement>(null);
  const [fallo, setFallo] = useState(false);

  useEffect(() => {
    if (!abierto) return;
    let vivo = true;
    let juego: { detener: () => void } | null = null;
    import(/* webpackIgnore: true */ RUTA_DEL_MOTOR)
      .then((motor: Motor) => {
        if (!vivo || !lienzo.current) return;
        // `?juego=` no se lee acá: forzar uno es cosa de la página sin conexión, para probar.
        juego = motor.montar(lienzo.current);
      })
      .catch(() => {
        // Sin el archivo (sin red justo ahora) no hay juego, y no pasa nada más.
        if (vivo) setFallo(true);
      });
    return () => {
      vivo = false;
      juego?.detener();
    };
  }, [abierto]);

  return (
    <Modal abierto={abierto} onCerrar={onCerrar} titulo="El colibrí" ancho="lg">
      {fallo ? (
        <p className="text-sm text-taupe">Hoy el colibrí no quiso salir. Prueba de nuevo en un momento.</p>
      ) : (
        <>
          <canvas
            ref={lienzo}
            tabIndex={0}
            className="aspect-[640/240] w-full touch-manipulation cursor-pointer rounded-lg border border-sand bg-crema"
          />
          <p className="mt-3 text-xs text-taupe">Espacio, flecha arriba o tocar la pantalla · Escape para salir</p>
        </>
      )}
    </Modal>
  );
}

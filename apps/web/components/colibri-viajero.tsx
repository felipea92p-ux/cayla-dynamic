"use client";

// El colibrí que cruza la pantalla cuando alguien escribe el código Konami
// (↑ ↑ ↓ ↓ ← → ← → B A) en el panel. Un easter egg: pasa una vez, dura tres
// segundos y medio, no se puede tocar y no deja nada. Las reglas que lo hacen
// «nada invasivo» están en `lib/easter-eggs.ts`.
//
// Solo se monta en el marco del panel. NO en el terminal de marcaje: ahí una
// tecla suelta no puede disparar nada (ver el encabezado de `lib/easter-eggs.ts`).

import { useEffect, useState } from "react";
import { Colibri } from "@/components/marca";
import { enCampoDeTexto } from "@/components/atajos-teclado";
import { CODIGO_KONAMI, avanzarKonami } from "@/lib/easter-eggs";

export function ColibriViajero() {
  // Un número y no un booleano: si alguien repite el código mientras el colibrí vuela, el `key` nuevo lo reinicia.
  const [vuelo, setVuelo] = useState<number | null>(null);

  useEffect(() => {
    let progreso = 0;
    function alPresionar(e: KeyboardEvent) {
      // Con una tecla modificadora o escribiendo en un campo no cuenta: buscar el huevo no puede costar un dato.
      if (e.metaKey || e.ctrlKey || e.altKey || enCampoDeTexto(e.target)) {
        progreso = 0;
        return;
      }
      progreso = avanzarKonami(progreso, e.key);
      if (progreso === CODIGO_KONAMI.length) {
        progreso = 0;
        setVuelo((n) => (n ?? 0) + 1);
      }
    }
    window.addEventListener("keydown", alPresionar);
    return () => window.removeEventListener("keydown", alPresionar);
  }, []);

  if (vuelo === null) return null;
  return (
    <div key={vuelo} className="colibri-viajero" aria-hidden onAnimationEnd={(e) => { if (e.target === e.currentTarget) setVuelo(null); }}>
      <Colibri tono="rojo" className="colibri-aleteo w-16" />
    </div>
  );
}

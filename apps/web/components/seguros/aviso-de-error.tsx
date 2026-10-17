"use client";

// ============================================================================
// El aviso de error de un diálogo largo
// ============================================================================
// El mensaje de error va ARRIBA del diálogo y el botón que lo provoca va ABAJO: en un
// teléfono, con el contenido desplazado, el error aparecía fuera de pantalla y parecía
// que «no pasó nada». Al montarse, el aviso se trae a la vista. Ya trae `role="alert"`
// para que el lector de pantalla lo lea.
// ============================================================================

import { useEffect, useRef } from "react";

export function AvisoDeError({ mensaje }: { mensaje: string }) {
  const ref = useRef<HTMLParagraphElement>(null);
  // `block: "nearest"`: si ya se ve, no mueve nada.
  useEffect(() => { ref.current?.scrollIntoView({ block: "nearest" }); }, [mensaje]);
  return (
    <p ref={ref} role="alert" className="mb-3 rounded border border-rojo/30 bg-rojo/10 px-3 py-2 text-sm text-rojo">{mensaje}</p>
  );
}

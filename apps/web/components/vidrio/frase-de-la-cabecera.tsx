"use client";

// Un solo «?» junto al título. Retail juntó en su globo la frase de la pantalla y su detalle (EncabezadoPagina); aquí el detalle es una ventana (`AyudaPantalla`), así que el «?» abre
// esa ventana y la frase se lee ahí, arriba de todo. Sin este proveedor, `useFraseDeLaCabecera` da `undefined` y `AyudaPantalla` se ve como siempre: apagado, nada cambia.

import { createContext, useContext, type ReactNode } from "react";

const FraseDeLaCabecera = createContext<string | null | undefined>(undefined);

export function AyudaConFrase({ frase, children }: { frase: string | null; children: ReactNode }) {
  return <FraseDeLaCabecera.Provider value={frase}>{children}</FraseDeLaCabecera.Provider>;
}

export function useFraseDeLaCabecera(): string | null | undefined {
  return useContext(FraseDeLaCabecera);
}

export function SignoDeAyuda({ onClick, etiqueta }: { onClick: () => void; etiqueta: string }) {
  return (
    <button type="button" onClick={onClick} aria-label={etiqueta} title={etiqueta} aria-haspopup="dialog" className="ayuda-cab-q">
      <span aria-hidden>?</span>
    </button>
  );
}

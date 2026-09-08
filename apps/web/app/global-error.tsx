"use client";

import * as Sentry from "@sentry/nextjs";
import { useEffect } from "react";

// Último recurso: si algo revienta tan arriba que ni el marco de la app carga,
// esta pantalla se muestra sola. Lleva estilos propios (inline) porque reemplaza
// TODO, incluido el <html> y la hoja de estilos. Casi nunca se ve — pero cuando
// pasa, salva la cara en vez de mostrar una pantalla en blanco.
//
// El modo oscuro acá SOLO sigue al sistema operativo (el `<style>` de abajo),
// nunca al selector de la app: leer `localStorage` a mano en la pantalla que
// existe justamente porque algo más ya reventó sería cambiar robustez por
// pulir un detalle que casi nadie va a ver.
//
// Los seis hex de abajo (tres claros, tres oscuros) son una copia deliberada
// de --color-crema/--color-tinta/--color-taupe de globals.css: no hay forma
// de que un linter ate estos literales a los tokens, porque esta pantalla no
// puede depender de la hoja de estilos que puede ser justo lo que reventó.
export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  // Next no reporta por su cuenta los errores que llegan hasta aquí: hay que avisarle
  // a Sentry a mano, o el fallo más grave posible sería el único que nunca vemos.
  useEffect(() => {
    Sentry.captureException(error);
  }, [error]);

  return (
    <html lang="es">
      <head>
        <style>{`
          @media (prefers-color-scheme: dark) {
            .global-error-body { background: #1c1a16 !important; color: #ede7db !important; }
            .global-error-detalle { color: #ab9080 !important; }
            .global-error-boton { background: #ede7db !important; color: #1c1a16 !important; }
          }
        `}</style>
      </head>
      <body
        className="global-error-body"
        style={{
          margin: 0,
          minHeight: "100vh",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          gap: "20px",
          background: "#f5f0e8",
          color: "#1a1a18",
          fontFamily: "ui-sans-serif, system-ui, sans-serif",
          textAlign: "center",
          padding: "24px",
        }}
      >
        <h1
          style={{
            fontFamily: "ui-serif, Georgia, serif",
            fontSize: "30px",
            fontWeight: 500,
            margin: 0,
          }}
        >
          Algo salió mal
        </h1>
        <p
          className="global-error-detalle"
          style={{
            maxWidth: "22rem",
            fontSize: "14px",
            color: "#805c4c",
            margin: 0,
            lineHeight: 1.6,
          }}
        >
          La aplicación tuvo un problema al arrancar. No se perdió nada — vuelve a
          intentarlo.
        </p>
        <button
          className="global-error-boton"
          onClick={reset}
          style={{
            border: "none",
            borderRadius: "8px",
            background: "#1a1a18",
            color: "#f5f0e8",
            padding: "10px 20px",
            fontSize: "14px",
            fontWeight: 500,
            cursor: "pointer",
          }}
        >
          Reintentar
        </button>
      </body>
    </html>
  );
}

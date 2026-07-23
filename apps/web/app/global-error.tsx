"use client";

// Último recurso: si algo revienta tan arriba que ni el marco de la app carga,
// esta pantalla se muestra sola. Lleva estilos propios (inline) porque reemplaza
// TODO, incluido el <html> y la hoja de estilos. Casi nunca se ve — pero cuando
// pasa, salva la cara en vez de mostrar una pantalla en blanco.
export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <html lang="es">
      <body
        style={{
          margin: 0,
          minHeight: "100vh",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          gap: "20px",
          background: "#f2ece1",
          color: "#1f1e1b",
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
          style={{
            maxWidth: "22rem",
            fontSize: "14px",
            color: "#9c7563",
            margin: 0,
            lineHeight: 1.6,
          }}
        >
          La aplicación tuvo un problema al arrancar. No se perdió nada — vuelve a
          intentarlo.
        </p>
        <button
          onClick={reset}
          style={{
            border: "none",
            borderRadius: "8px",
            background: "#1f1e1b",
            color: "#f2ece1",
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

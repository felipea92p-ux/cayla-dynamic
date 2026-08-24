import type { Metadata, Viewport } from "next";
import { EB_Garamond, DM_Sans } from "next/font/google";
import "./globals.css";

// Serif del alma del sistema (títulos, datos con carácter).
const ebGaramond = EB_Garamond({
  variable: "--font-eb-garamond",
  subsets: ["latin"],
  display: "swap",
});

// Sans del sistema (cuerpo, tablas, etiquetas).
const dmSans = DM_Sans({
  variable: "--font-dm-sans",
  subsets: ["latin"],
  display: "swap",
});

export const metadata: Metadata = {
  title: "Dynamic — CAYLA",
  // No enumera las sedes. Decía «(TRU, LIM, AQP)» y era falso desde que abrió
  // Central: la lista de sedes vive en una tabla y se gestiona desde una
  // pantalla, así que escribirla a mano aquí sólo garantiza que envejezca.
  description: "Asistencia y planilla de CAYLA",
  // ── EL ICONO, POR LOS DOS CAMINOS QUE HACEN FALTA ────────────────────────
  // `icon` es la pestaña del navegador. `apple` es el que iOS usa cuando
  // alguien hace «Añadir a pantalla de inicio» — y es un camino APARTE del
  // manifest: iOS no lee los iconos del manifest, así que declarar sólo uno de
  // los dos deja el icono bien en un teléfono y mal en el otro.
  //
  // Antes esto era `icon: "/colibri.png"`, que son 1755×1184 y transparente:
  // como favicon pasaba (el navegador lo encoge), pero como icono de inicio
  // habría salido deformado y con el fondo NEGRO, que es como iOS pinta la
  // transparencia. Los de abajo son cuadrados y opacos.
  icons: {
    icon: [
      { url: "/icono-32.png", sizes: "32x32", type: "image/png" },
      { url: "/icono-192.png", sizes: "192x192", type: "image/png" },
    ],
    apple: [{ url: "/apple-touch-icon.png", sizes: "180x180", type: "image/png" }],
  },
};

// La crema tiñe la barra del navegador en el móvil, para que la app no arranque
// con una franja blanca encima de su propio fondo.
export const viewport: Viewport = {
  themeColor: "#f5f0e8",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="es"
      className={`${dmSans.variable} ${ebGaramond.variable} h-full antialiased`}
    >
      <body className="flex min-h-full flex-col font-sans">{children}</body>
    </html>
  );
}

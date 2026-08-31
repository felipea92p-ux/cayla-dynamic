import type { Metadata, Viewport } from "next";
import { EB_Garamond, DM_Sans } from "next/font/google";
import { ToastProvider } from "@/components/toast";
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

// La crema (o su equivalente oscuro) tiñe la barra del navegador en el móvil,
// para que la app no arranque con una franja blanca encima de su propio fondo.
// Los dos colores cubren el caso SISTEMA; quien elige el tema a mano desde el
// selector no cambia esta franja hasta la próxima carga — es cosmético, no
// vale la pena una segunda vía solo para eso.
export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f5f0e8" },
    { media: "(prefers-color-scheme: dark)", color: "#1c1a16" },
  ],
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
      // El script de abajo pone `data-tema` en este mismo elemento antes de
      // que React hidrate — a propósito, es lo que evita el parpadeo. React no
      // tiene forma de saber eso de antemano y sin este aviso lo reporta como
      // un error de hidratación, aunque el HTML esté bien.
      suppressHydrationWarning
    >
      <body className="flex min-h-full flex-col font-sans">
        {/* Pone `data-tema` en <html> ANTES de que se pinte nada, para que quien
            eligió "oscuro" a mano no vea un parpadeo de la paleta clara al
            cargar la página. Sin esto, `useTema` (que sí es seguro para
            hidratación) solo aplicaría el tema guardado DESPUÉS del primer
            render de React — un parpadeo real, no cosmético, en cada carga. Si
            no hay nada guardado, no toca el atributo y manda `prefers-color-scheme`
            —la regla ya escrita en globals.css—, así que tampoco hace falta
            preguntarle nada al sistema operativo desde acá. */}
        <script
          dangerouslySetInnerHTML={{
            __html:
              "try{var t=localStorage.getItem('cayla-tema');if(t==='claro'||t==='oscuro')document.documentElement.setAttribute('data-tema',t);}catch(e){}",
          }}
        />
        {/* Safari de iPhone no dispara `:active` en toques salvo que el documento
            tenga un listener de touch propio — sin esto, los botones y enlaces que
            "prenden" al presionar con el dedo solo lo hacían con mouse. */}
        <script
          dangerouslySetInnerHTML={{
            __html: "document.addEventListener('touchstart', function(){}, {passive:true});",
          }}
        />
        {/* Envuelve TODO —admin, terminal, lo mío— para que `useToast()` esté
            disponible desde cualquier pantalla, sin volver a montarlo por ruta. */}
        <ToastProvider>{children}</ToastProvider>
      </body>
    </html>
  );
}

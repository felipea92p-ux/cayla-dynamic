import type { MetadataRoute } from "next";

// ============================================================================
// El manifest — lo que Android lee cuando alguien hace «Añadir a pantalla
// principal». iOS NO lo usa para el icono: iOS mira `apple-touch-icon`, que se
// declara aparte en `metadata.icons.apple` del layout. Son dos caminos, y hay
// que poner los dos o el icono sale bien en un teléfono y mal en el otro.
//
// POR QUÉ HAY UN ICONO «MASKABLE» ADEMÁS DEL NORMAL. Android recorta el icono a
// la forma del launcher —círculo, squircle, gota— y solo garantiza que se vea
// el 80 % central. Un icono normal metido en esa máscara pierde el pico y la
// cola del colibrí; y si no se declara ninguno maskable, Android encoge el
// icono entero dentro de un círculo blanco, que se ve peor todavía. Por eso el
// maskable lleva el colibrí más pequeño: es el mismo dibujo con más aire.
//
// LOS ICONOS SON OPACOS A PROPÓSITO. `colibri.png` es una silueta transparente
// —el CSS la usa como máscara y le pone el color con `currentColor`— y iOS
// pinta de NEGRO cualquier transparencia del icono de inicio. Así que estos se
// generaron componiendo el colibrí sobre crema, sin canal alfa.
// ============================================================================

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Dynamic — CAYLA",
    // El nombre que sale DEBAJO del icono. Corto porque el sistema lo corta:
    // iOS alrededor de 12 caracteres, Android algo más.
    short_name: "Dynamic",
    description: "Asistencia y planilla de CAYLA",
    lang: "es-PE",
    start_url: "/",
    display: "standalone",
    // La crema es el fondo dominante de la app (--color-crema). La pantalla de
    // arranque de Android usa `background_color`, así que ponerla igual evita
    // el destello blanco antes de que cargue.
    background_color: "#f5f0e8",
    // El tinte de la barra de estado. Va la crema y no el rojo: el rojo es el
    // acento sagrado, y una barra roja permanente lo gastaría.
    theme_color: "#f5f0e8",
    icons: [
      { src: "/icono-192.png", sizes: "192x192", type: "image/png", purpose: "any" },
      { src: "/icono-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
      { src: "/icono-maskable-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
    ],
  };
}

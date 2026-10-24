"use client";

import { usePathname, useRouter } from "next/navigation";
import { Pestanas } from "@/components/ui/pestanas";

// La Fase 9 de la auditoría pidió separar "Documento vigente" de "Versiones y
// publicación" — hoy eran la misma pantalla con un botón de publicar mezclado
// en medio del texto que se lee. `nav-items.ts` es una lista PLANA (sin
// sub-items, ver su propio comentario) y agregar cuatro renglones nuevos ahí
// llenaría el menú global de algo que solo le importa a quien administra este
// documento — así que la separación vive ACÁ, como una sub-navegación local,
// igual que ya hacía "hoja de constancias" con un link suelto antes de esta
// pantalla.
//
// Desde el 2026-10-24 dibuja con <Pestanas> (la pieza del ADR 0004) en vez de su propia raya roja: una pestaña
// subrayada se ve igual en todo el panel. Cada pestaña es una ruta, así que elegirla navega.
const RUTAS = [
  { href: "/admin/politica-salarial", texto: "Documento vigente" },
  { href: "/admin/politica-salarial/versiones", texto: "Versiones y publicación" },
  { href: "/admin/politica-salarial/categorias", texto: "Categorías" },
  { href: "/admin/politica-salarial/constancias", texto: "Constancias" },
] as const;

/** Solo para quien puede publicar (esDO) — cualquier otra persona ve solo el documento. */
export function SubnavPoliticaSalarial() {
  const pathname = usePathname();
  const router = useRouter();
  const activa =
    RUTAS.find((r) => r.href !== "/admin/politica-salarial" && pathname?.startsWith(r.href))?.href ??
    RUTAS[0].href;
  return (
    <Pestanas
      etiqueta="Secciones de Política salarial"
      className="print:hidden"
      pestanas={RUTAS.map((r) => ({ clave: r.href, texto: r.texto }))}
      activa={activa}
      alElegir={(href) => router.push(href)}
    />
  );
}

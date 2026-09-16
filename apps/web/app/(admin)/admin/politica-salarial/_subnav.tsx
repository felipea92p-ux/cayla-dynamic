"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cx } from "@/components/ui/cx";

// La Fase 9 de la auditoría pidió separar "Documento vigente" de "Versiones y
// publicación" — hoy eran la misma pantalla con un botón de publicar mezclado
// en medio del texto que se lee. `nav-items.ts` es una lista PLANA (sin
// sub-items, ver su propio comentario) y agregar cuatro renglones nuevos ahí
// llenaría el menú global de algo que solo le importa a quien administra este
// documento — así que la separación vive ACÁ, como una sub-navegación local,
// igual que ya hacía "hoja de constancias" con un link suelto antes de esta
// pantalla.
const RUTAS = [
  { href: "/admin/politica-salarial", label: "Documento vigente" },
  { href: "/admin/politica-salarial/versiones", label: "Versiones y publicación" },
  { href: "/admin/politica-salarial/categorias", label: "Categorías" },
  { href: "/admin/politica-salarial/constancias", label: "Constancias" },
] as const;

/** Solo para quien puede publicar (esDO) — cualquier otra persona ve solo el documento. */
export function SubnavPoliticaSalarial() {
  const pathname = usePathname();
  return (
    <nav className="mb-6 flex flex-wrap gap-1 border-b border-sand pb-px print:hidden">
      {RUTAS.map((r) => {
        const activo = r.href === "/admin/politica-salarial" ? pathname === r.href : pathname?.startsWith(r.href);
        return (
          <Link
            key={r.href}
            href={r.href}
            className={cx(
              "rounded-t-control border-b-2 px-3 py-2 text-sm font-medium transition-colors duration-150",
              activo ? "border-rojo text-tinta" : "border-transparent text-taupe hover:text-tinta",
            )}
          >
            {r.label}
          </Link>
        );
      })}
    </nav>
  );
}

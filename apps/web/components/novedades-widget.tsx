"use client";

// ============================================================================
// Las novedades del sistema que a esta persona todavía le faltan por entender.
// ============================================================================
//
// Hermano de `AnunciosWidget` y con la misma regla: si no hay nada pendiente
// no se dibuja nada, y una vez marcada como entendida desaparece de acá (sigue
// en /admin/anuncios). No es un modal ni bloquea nada: una novedad cuenta qué
// mejoró, no le pide nada a nadie.
//
// Muestra lo justo para una pantalla de inicio: las tres más recientes, y de
// cada una solo el primer párrafo (ver «EL PRIMER PÁRRAFO TIENE QUE VALER
// SOLO» en `lib/novedades.ts`). El resto está a un clic.
//
// Si no se pueden leer las marcas de la persona, calla: una tarjeta que no se
// puede descartar es peor que no mostrarla. Ver `use-novedades-vistas.ts`.
// ============================================================================

import Link from "next/link";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { useNovedadesVistas } from "@/lib/use-novedades-vistas";
import {
  novedadesPendientes, primerParrafo, tieneMasQueElPrimerParrafo, type Novedad,
} from "@/lib/novedades";
import { Boton } from "@/components/ui/boton";

/** Cuántas caben en una pantalla de inicio sin empujar lo que importa. */
const MAXIMO_VISIBLES = 3;

export function NovedadesWidget() {
  const persona = usePersonaActual();
  const { vistas, marcar } = useNovedadesVistas(persona !== null);

  if (!persona || vistas === null) return null;
  return <NovedadesPendientes pendientes={novedadesPendientes(persona.rol, vistas)} onEntendido={marcar} />;
}

/** La tarjeta, sin datos ni sesión: recibe lo que ya se decidió mostrar. */
export function NovedadesPendientes({
  pendientes,
  onEntendido,
}: {
  pendientes: readonly Novedad[];
  onEntendido: (id: string) => void;
}) {
  if (pendientes.length === 0) return null;

  const visibles = pendientes.slice(0, MAXIMO_VISIBLES);
  const restantes = pendientes.length - visibles.length;

  return (
    <section aria-label="Novedades del sistema" className="mb-6 rounded-2xl border border-sand bg-papel p-4">
      <h2 className="mb-2 text-sm font-medium text-tinta">
        {pendientes.length === 1 ? "Una novedad del sistema" : `${pendientes.length} novedades del sistema`}
      </h2>
      <ul className="space-y-2">
        {visibles.map((n) => (
          <li key={n.id} className="rounded-xl border border-sand/70 bg-crema p-3">
            <p className="text-sm font-medium text-tinta">{n.titulo}</p>
            <p className="mt-1 text-xs text-taupe">{primerParrafo(n)}</p>
            <div className="mt-2 flex flex-wrap items-center gap-3">
              <Boton variante="sutil" tamano="sm" onClick={() => onEntendido(n.id)}>
                Entendido
              </Boton>
              {tieneMasQueElPrimerParrafo(n) && (
                <Link href="/admin/anuncios" className="text-xs text-taupe underline">
                  Leerla completa
                </Link>
              )}
            </div>
          </li>
        ))}
      </ul>
      <Link href="/admin/anuncios" className="mt-3 inline-block text-xs text-taupe underline">
        {restantes > 0 ? `Y ${restantes} más — ver todas las novedades` : "Ver todas las novedades"}
      </Link>
    </section>
  );
}

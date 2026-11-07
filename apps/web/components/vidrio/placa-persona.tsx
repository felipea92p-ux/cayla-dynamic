"use client";

// Abajo del menú, la persona: su foto, su nombre, su rol y su sede, y la puerta para salir. Tocar la placa lleva a Lo mío. La puerta queda
// afuera de ese toque: salir nunca se dispara por querer ver el perfil.
//
// Con el menú plegado, Retail deja solo la foto y confía en que desde el perfil también se sale. Aquí no alcanza: Dynamic se pliega solo bajo
// 1280 px y Lo mío usa el mismo menú, así que en una laptop chica no habría cómo cerrar sesión. Plegada, la puerta va bajo la foto.

import Link from "next/link";
import { LogOut } from "lucide-react";

export type PersonaDeLaPlaca = {
  nombre: string;
  /** «Líder de equipo · Tienda TRU». */
  detalle?: string;
  fotoUrl?: string | null;
};

function iniciales(nombre: string): string {
  const partes = nombre.trim().split(/\s+/);
  return `${partes[0]?.[0] ?? ""}${partes[1]?.[0] ?? ""}`.toUpperCase();
}

export function PlacaPersona({
  persona,
  href,
  alTocar,
  onSalir,
}: {
  persona: PersonaDeLaPlaca | null;
  /** A dónde lleva tocar la placa. En Lo mío no hay a dónde ir: vuelve al resumen con `alTocar`. */
  href?: string;
  alTocar?: () => void;
  onSalir: () => void;
}) {
  const quien = (
    <>
      <span className="marco-yo-lente">
        {persona?.fotoUrl ? (
          // eslint-disable-next-line @next/next/no-img-element -- foto de un bucket externo, no un asset local
          <img src={persona.fotoUrl} alt="" className="size-9 rounded-full object-cover" />
        ) : (
          <span aria-hidden className="marco-yo-iniciales">{persona ? iniciales(persona.nombre) : ""}</span>
        )}
      </span>
      <span className="marco-yo-texto">
        <span className="marco-yo-nombre">{persona?.nombre ?? " "}</span>
        {persona?.detalle ? <span className="marco-yo-rol">{persona.detalle}</span> : null}
      </span>
    </>
  );
  return (
    <div data-pieza-cajon style={{ "--k": 14 } as React.CSSProperties} className="marco-yo">
      {href ? (
        <Link href={href} title={persona?.nombre} aria-label={persona ? `Lo mío de ${persona.nombre}` : "Lo mío"} className="marco-yo-quien group text-left">
          {quien}
        </Link>
      ) : (
        <button type="button" onClick={alTocar} title={persona?.nombre} aria-label={persona ? `Lo mío de ${persona.nombre}` : "Lo mío"} className="marco-yo-quien group text-left">
          {quien}
        </button>
      )}
      <button type="button" onClick={onSalir} aria-label="Cerrar sesión" title="Cerrar sesión" className="marco-yo-salir">
        <LogOut size={16} strokeWidth={1.8} aria-hidden />
      </button>
    </div>
  );
}

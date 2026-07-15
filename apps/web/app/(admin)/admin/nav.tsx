"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { useRolActual } from "@/lib/admin/use-rol";
import { Marca } from "@/components/marca";

const LINKS: Array<{ href: string; label: string; roles?: string[] }> = [
  { href: "/admin/dashboard", label: "Dashboard" },
  { href: "/admin/perfil", label: "Perfil" },
  { href: "/admin/horas", label: "Horas" },
  { href: "/admin/incidencias", label: "Incidencias", roles: ["admin", "lider_do", "supervisor_sede"] },
  { href: "/admin/correcciones", label: "Correcciones", roles: ["admin", "lider_do", "supervisor_sede"] },
  { href: "/admin/horarios", label: "Horarios", roles: ["admin", "lider_do", "supervisor_sede"] },
  { href: "/admin/turnos", label: "Turnos", roles: ["admin", "lider_do", "supervisor_sede"] },
  { href: "/admin/objetivos", label: "Objetivos", roles: ["admin", "lider_do", "supervisor_sede"] },
  { href: "/admin/planilla", label: "Planilla", roles: ["admin", "lider_do"] },
  { href: "/admin/provisiones", label: "Provisiones", roles: ["admin", "lider_do"] },
  { href: "/admin/equipo", label: "Equipo" },
  { href: "/admin/areas", label: "Áreas", roles: ["admin", "lider_do"] },
  { href: "/admin/cuentas", label: "Cuentas" },
  { href: "/admin/exportar", label: "Exportar CSV" },
];

export function AdminNav() {
  const pathname = usePathname();
  const router = useRouter();
  const rol = useRolActual();
  const [abierto, setAbierto] = useState(false);

  // Al navegar a otra página, el menú móvil se cierra solo.
  useEffect(() => {
    setAbierto(false);
  }, [pathname]);

  async function cerrarSesion() {
    const supabase = createAdminSupabaseClient();
    await supabase.auth.signOut();
    router.replace("/admin/login");
  }

  const visibles = LINKS.filter((l) => !l.roles || (rol !== null && l.roles.includes(rol)));

  return (
    <header className="border-b border-sand">
      <div className="flex items-center justify-between px-4 py-3 sm:px-6">
        <div className="flex min-w-0 items-center gap-6 xl:gap-8">
          <Marca tono="tinta" isotipo="rojo" />
          {/* Navegación horizontal — solo en pantallas grandes */}
          <nav className="hidden flex-wrap gap-x-5 gap-y-1 text-sm xl:flex">
            {visibles.map((l) => (
              <Link
                key={l.href}
                href={l.href}
                className={
                  pathname === l.href
                    ? "font-medium text-tinta"
                    : "text-taupe transition-colors hover:text-tinta"
                }
              >
                {l.label}
              </Link>
            ))}
          </nav>
        </div>

        <div className="flex items-center gap-3">
          <button
            onClick={cerrarSesion}
            className="hidden text-sm text-taupe transition-colors hover:text-tinta xl:block"
          >
            Cerrar sesión
          </button>
          {/* Botón hamburguesa — solo en pantallas chicas */}
          <button
            onClick={() => setAbierto((a) => !a)}
            aria-label={abierto ? "Cerrar menú" : "Abrir menú"}
            aria-expanded={abierto}
            className="rounded-lg border border-sand p-2 text-tinta xl:hidden"
          >
            {abierto ? (
              <svg width="20" height="20" viewBox="0 0 20 20" fill="none" aria-hidden="true">
                <path d="M5 5l10 10M15 5L5 15" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
              </svg>
            ) : (
              <svg width="20" height="20" viewBox="0 0 20 20" fill="none" aria-hidden="true">
                <path d="M3 5.5h14M3 10h14M3 14.5h14" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
              </svg>
            )}
          </button>
        </div>
      </div>

      {/* Menú desplegable móvil */}
      {abierto && (
        <nav className="border-t border-sand px-4 pb-4 pt-2 sm:px-6 xl:hidden">
          <div className="grid gap-1">
            {visibles.map((l) => (
              <Link
                key={l.href}
                href={l.href}
                className={`rounded-lg px-3 py-2.5 text-sm ${
                  pathname === l.href
                    ? "bg-sand/60 font-medium text-tinta"
                    : "text-taupe hover:bg-sand/40 hover:text-tinta"
                }`}
              >
                {l.label}
              </Link>
            ))}
            <button
              onClick={cerrarSesion}
              className="mt-2 rounded-lg border border-sand px-3 py-2.5 text-left text-sm text-taupe hover:text-tinta"
            >
              Cerrar sesión
            </button>
          </div>
        </nav>
      )}
    </header>
  );
}

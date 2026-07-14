"use client";

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

  async function cerrarSesion() {
    const supabase = createAdminSupabaseClient();
    await supabase.auth.signOut();
    router.replace("/admin/login");
  }

  return (
    <header className="flex items-center justify-between border-b border-sand px-6 py-3">
      <div className="flex items-center gap-8">
        <Marca tono="tinta" isotipo="rojo" />
        <nav className="flex gap-5 text-sm">
          {LINKS.filter((l) => !l.roles || (rol !== null && l.roles.includes(rol))).map((l) => (
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
      <button onClick={cerrarSesion} className="text-sm text-taupe transition-colors hover:text-tinta">
        Cerrar sesión
      </button>
    </header>
  );
}

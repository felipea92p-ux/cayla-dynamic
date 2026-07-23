"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { useRolActual } from "@/lib/admin/use-rol";
import { Marca } from "@/components/marca";
import {
  LayoutDashboard, TriangleAlert, PencilLine, CalendarClock, Clock, Hourglass,
  Users, IdCard, TreePalm, Gavel, ReceiptText, PiggyBank, Target, Store, KeyRound,
  Building2, FileDown, FileText, LogOut, Menu, X, type LucideIcon,
} from "lucide-react";

const DO = ["admin", "lider_do"];
const SEDE = ["admin", "lider_do", "supervisor_sede"];

type Item = { href: string; label: string; Icon: LucideIcon; roles?: string[] };
const GRUPOS: Array<{ label?: string; items: Item[] }> = [
  { items: [{ href: "/admin/dashboard", label: "Dashboard", Icon: LayoutDashboard }] },
  { label: "Asistencia", items: [
    { href: "/admin/incidencias", label: "Incidencias", Icon: TriangleAlert, roles: SEDE },
    { href: "/admin/correcciones", label: "Correcciones", Icon: PencilLine, roles: SEDE },
    { href: "/admin/turnos", label: "Turnos", Icon: CalendarClock, roles: SEDE },
    { href: "/admin/horarios", label: "Horarios", Icon: Clock, roles: SEDE },
    { href: "/admin/horas", label: "Horas", Icon: Hourglass },
  ] },
  { label: "Personas", items: [
    { href: "/admin/equipo", label: "Equipo", Icon: Users },
    { href: "/admin/datos-personales", label: "Datos personales", Icon: IdCard, roles: SEDE },
    { href: "/admin/objetivos", label: "Objetivos", Icon: Target, roles: SEDE },
    { href: "/admin/disciplina", label: "Disciplina", Icon: Gavel, roles: SEDE },
  ] },
  { label: "Nómina", items: [
    { href: "/admin/planilla", label: "Planilla", Icon: ReceiptText, roles: DO },
    { href: "/admin/provisiones", label: "Provisiones", Icon: PiggyBank, roles: DO },
    { href: "/admin/vacaciones", label: "Vacaciones", Icon: TreePalm, roles: DO },
  ] },
  { label: "Gestión", items: [
    { href: "/admin/areas", label: "Áreas", Icon: Store, roles: DO },
    { href: "/admin/sedes", label: "Sedes", Icon: Building2, roles: DO },
    { href: "/admin/reporte-sede", label: "Hoja de sede", Icon: FileText, roles: SEDE },
    { href: "/admin/cuentas", label: "Cuentas", Icon: KeyRound },
    { href: "/admin/exportar", label: "Exportar CSV", Icon: FileDown },
  ] },
];

// El perfil de una persona (/admin/personas/[id]) se entra desde Equipo, así que
// mientras estás en él, resaltamos "Equipo" para no dejar la ubicación huérfana.
function esActivo(pathname: string, href: string): boolean {
  if (pathname === href) return true;
  if (href === "/admin/equipo" && pathname.startsWith("/admin/personas")) return true;
  return false;
}

export function AdminNav() {
  const pathname = usePathname();
  const router = useRouter();
  const rol = useRolActual();
  const [abierto, setAbierto] = useState(false);

  useEffect(() => { setAbierto(false); }, [pathname]);

  async function cerrarSesion() {
    const supabase = createAdminSupabaseClient();
    await supabase.auth.signOut();
    router.replace("/admin/login");
  }

  const visible = (it: Item) => !it.roles || (rol !== null && it.roles.includes(rol));
  const grupos = GRUPOS
    .map((g) => ({ ...g, items: g.items.filter(visible) }))
    .filter((g) => g.items.length > 0);

  return (
    <header className="border-b border-sand">
      <div className="flex items-center justify-between px-4 py-3 sm:px-6">
        <div className="flex min-w-0 items-center gap-6 xl:gap-8">
          <Marca tono="tinta" isotipo="rojo" />
          {/* Barra horizontal — desktop. Grupos separados por un divisor sutil. */}
          <nav className="hidden flex-wrap items-center gap-x-2 gap-y-1 text-sm xl:flex">
            {grupos.map((g, gi) => (
              <div key={gi} className="flex items-center gap-x-0.5">
                {gi > 0 && <span aria-hidden className="mx-1.5 h-3.5 w-px bg-sand" />}
                {g.items.map((it) => (
                  <Link key={it.href} href={it.href}
                    className={`flex items-center gap-1.5 rounded-md px-2 py-1 transition-colors ${
                      esActivo(pathname, it.href) ? "bg-sand/60 font-medium text-tinta" : "text-taupe hover:bg-sand/30 hover:text-tinta"}`}>
                    <it.Icon size={15} strokeWidth={1.8} aria-hidden />
                    {it.label}
                  </Link>
                ))}
              </div>
            ))}
          </nav>
        </div>

        <div className="flex items-center gap-3">
          <button onClick={cerrarSesion}
            className="hidden items-center gap-1.5 text-sm text-taupe transition-colors hover:text-tinta xl:flex">
            <LogOut size={15} strokeWidth={1.8} aria-hidden /> Cerrar sesión
          </button>
          <button onClick={() => setAbierto((a) => !a)}
            aria-label={abierto ? "Cerrar menú" : "Abrir menú"} aria-expanded={abierto}
            className="rounded-lg border border-sand p-2 text-tinta xl:hidden">
            {abierto ? <X size={20} strokeWidth={1.8} /> : <Menu size={20} strokeWidth={1.8} />}
          </button>
        </div>
      </div>

      {/* Menú desplegable móvil — vertical, con títulos de grupo e íconos. */}
      {abierto && (
        <nav className="border-t border-sand px-4 pb-4 pt-1 sm:px-6 xl:hidden">
          {grupos.map((g, gi) => (
            <div key={gi}>
              {g.label && (
                <p className="px-3 pb-1 pt-3 text-[11px] uppercase tracking-wider text-taupe/70">{g.label}</p>
              )}
              <div className="grid gap-0.5">
                {g.items.map((it) => (
                  <Link key={it.href} href={it.href}
                    className={`flex items-center gap-2.5 rounded-lg px-3 py-2.5 text-sm ${
                      esActivo(pathname, it.href)
                        ? "bg-sand/60 font-medium text-tinta"
                        : "text-taupe hover:bg-sand/40 hover:text-tinta"}`}>
                    <it.Icon size={17} strokeWidth={1.8} aria-hidden />
                    {it.label}
                  </Link>
                ))}
              </div>
            </div>
          ))}
          <button onClick={cerrarSesion}
            className="mt-3 flex w-full items-center gap-2.5 rounded-lg border border-sand px-3 py-2.5 text-left text-sm text-taupe hover:text-tinta">
            <LogOut size={17} strokeWidth={1.8} aria-hidden /> Cerrar sesión
          </button>
        </nav>
      )}
    </header>
  );
}

"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";

const LINKS = [
  { href: "/admin/dashboard", label: "Dashboard" },
  { href: "/admin/exportar", label: "Exportar CSV" },
];

export function AdminNav() {
  const pathname = usePathname();
  const router = useRouter();

  async function cerrarSesion() {
    const supabase = createAdminSupabaseClient();
    await supabase.auth.signOut();
    router.replace("/admin/login");
  }

  return (
    <header className="flex items-center justify-between border-b px-6 py-3">
      <div className="flex items-center gap-6">
        <span className="font-semibold">Dynamic — CAYLA</span>
        <nav className="flex gap-4 text-sm">
          {LINKS.map((l) => (
            <Link
              key={l.href}
              href={l.href}
              className={pathname === l.href ? "font-medium text-black" : "text-neutral-500 hover:text-black"}
            >
              {l.label}
            </Link>
          ))}
        </nav>
      </div>
      <button onClick={cerrarSesion} className="text-sm text-neutral-500 hover:text-black">
        Cerrar sesión
      </button>
    </header>
  );
}

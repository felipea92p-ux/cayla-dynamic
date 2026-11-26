"use client";

// El organigrama de CAYLA (0623). Lo ve quien abre el panel; lo ordena DO. La
// misma pieza está en «Lo mío → Empresa» para todo el equipo.

import { useEffect, useMemo } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { VistaDelOrganigrama } from "@/components/organigrama/organigrama";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { sobretituloDeHoy } from "@/lib/admin/sobretitulo";

export default function OrganigramaPage() {
  const router = useRouter();
  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => { if (!data.session) router.replace("/admin/login"); });
  }, [supabase, router]);

  return (
    <main className="flex-1 p-4 pt-6 sm:p-6">
      <CabeceraPagina
        sobretitulo={sobretituloDeHoy("Empresa")}
        titulo="Organigrama"
        descripcion="Quién es quién en CAYLA y en qué equipo está."
      />
      <VistaDelOrganigrama conEdicion />
    </main>
  );
}

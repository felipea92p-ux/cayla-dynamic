"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { createBrowserSupabaseClient } from "@cayla-dynamic/database";

export default function AdminIndexPage() {
  const router = useRouter();

  useEffect(() => {
    const supabase = createBrowserSupabaseClient();
    supabase.auth.getSession().then(({ data }) => {
      router.replace(data.session ? "/admin/exportar" : "/admin/login");
    });
  }, [router]);

  return (
    <div className="flex flex-1 items-center justify-center">
      <p className="text-neutral-500">Cargando…</p>
    </div>
  );
}

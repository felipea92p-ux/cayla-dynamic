"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";

export default function AdminIndexPage() {
  const router = useRouter();

  useEffect(() => {
    const supabase = createAdminSupabaseClient();
    supabase.auth.getSession().then(({ data }) => {
      router.replace(data.session ? "/admin/dashboard" : "/admin/login");
    });
  }, [router]);

  return (
    <div className="flex flex-1 items-center justify-center">
      <p className="text-taupe">Cargando…</p>
    </div>
  );
}

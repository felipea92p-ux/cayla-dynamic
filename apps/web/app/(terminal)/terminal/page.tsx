"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { createTerminalSupabaseClient } from "@cayla-dynamic/database";

export default function TerminalIndexPage() {
  const router = useRouter();

  useEffect(() => {
    const supabase = createTerminalSupabaseClient();
    supabase.auth.getSession().then(({ data }) => {
      router.replace(data.session ? "/terminal/marcar" : "/terminal/vincular");
    });
  }, [router]);

  return (
    <div className="flex flex-1 items-center justify-center">
      <p className="text-taupe">Cargando…</p>
    </div>
  );
}

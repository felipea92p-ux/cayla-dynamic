"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Colibri } from "@/components/marca";
import { ROLES_CON_PANEL } from "@cayla-dynamic/shared";

export default function AdminLoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [cargando, setCargando] = useState(false);

  async function entrar(e: FormEvent) {
    e.preventDefault();
    setCargando(true);
    setError(null);
    const supabase = createAdminSupabaseClient();
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) {
      setCargando(false);
      setError("Correo o contraseña incorrectos.");
      return;
    }

    // A DÓNDE ATERRIZA CADA QUIEN.
    //
    // El Dashboard es un tablero de encargada. Una integrante con cuenta —las
    // hay: se les invita para que dejen constancia de la política salarial, Ley
    // 30709— caía ahí y veía una pantalla que su propia RLS le devuelve casi
    // vacía: no es una fuga, es un tablero de otra persona que se lee como que
    // el sistema no tiene datos. Su sitio es «Lo mío».
    //
    // Ante la duda se manda a /mio, no al panel: equivocarse hacia lo suyo no
    // rompe nada, y equivocarse hacia el panel deja a alguien mirando pantallas
    // que no le hablan.
    const { data: yo } = await supabase
      .from("personas")
      .select("rol")
      .eq("auth_user_id", data.user?.id ?? "")
      .maybeSingle();
    setCargando(false);
    const rol = (yo as { rol?: string } | null)?.rol;
    router.replace(rol && ROLES_CON_PANEL.includes(rol as never) ? "/admin/dashboard" : "/mio");
  }

  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-8 p-8">
      <div className="flex flex-col items-center gap-4">
        <Colibri tono="rojo" className="w-12" />
        <div className="text-center">
          <h1 className="font-serif text-3xl leading-none">Dynamic</h1>
          <p className="etiqueta mt-2 text-taupe">Panel de administración · CAYLA</p>
        </div>
      </div>
      <form onSubmit={entrar} className="flex w-full max-w-xs flex-col gap-3">
        <input
          type="email"
          placeholder="correo"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          className="rounded-lg border border-sand bg-crema px-4 py-3 outline-none placeholder:text-taupe/60 focus:border-taupe"
          required
        />
        <input
          type="password"
          placeholder="contraseña"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          className="rounded-lg border border-sand bg-crema px-4 py-3 outline-none placeholder:text-taupe/60 focus:border-taupe"
          required
        />
        {error && <p className="text-sm text-rojo">{error}</p>}
        <button
          type="submit"
          disabled={cargando}
          className="rounded-lg bg-tinta px-4 py-3 font-medium text-crema transition-colors hover:bg-rojo-profundo disabled:opacity-50"
        >
          {cargando ? "Entrando…" : "Entrar"}
        </button>
        <a href="/admin/olvide-clave" className="text-center text-sm text-taupe underline-offset-2 hover:underline">
          ¿Olvidaste tu clave?
        </a>
      </form>
    </div>
  );
}

"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { createBrowserSupabaseClient } from "@cayla-dynamic/database";
import { refrescarInfoTerminal } from "@/lib/terminal/terminal-info";

export default function VincularTerminalPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [cargando, setCargando] = useState(false);

  async function vincular(e: FormEvent) {
    e.preventDefault();
    setCargando(true);
    setError(null);

    const supabase = createBrowserSupabaseClient();
    const { error: authError } = await supabase.auth.signInWithPassword({ email, password });

    if (authError) {
      setCargando(false);
      setError("Credenciales de dispositivo incorrectas. Verifica con el administrador.");
      return;
    }

    const info = await refrescarInfoTerminal();
    setCargando(false);

    if (!info) {
      setError("Se inició sesión pero no se encontró el registro de este terminal. Avisa al administrador.");
      return;
    }

    router.replace("/terminal/marcar");
  }

  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-6 p-8">
      <h1 className="text-xl font-semibold">Vincular este dispositivo</h1>
      <p className="max-w-sm text-center text-sm text-neutral-400">
        Ingresa las credenciales de terminal que te dio el administrador. Esto solo se hace una
        vez por dispositivo.
      </p>
      <form onSubmit={vincular} className="flex w-full max-w-xs flex-col gap-3">
        <input
          type="email"
          placeholder="correo del terminal"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          className="rounded-lg bg-neutral-800 px-4 py-3 text-white outline-none"
          required
        />
        <input
          type="password"
          placeholder="contraseña"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          className="rounded-lg bg-neutral-800 px-4 py-3 text-white outline-none"
          required
        />
        {error && <p className="text-sm text-red-400">{error}</p>}
        <button
          type="submit"
          disabled={cargando}
          className="rounded-lg bg-white px-4 py-3 font-medium text-black disabled:opacity-50"
        >
          {cargando ? "Vinculando…" : "Vincular"}
        </button>
      </form>
    </div>
  );
}

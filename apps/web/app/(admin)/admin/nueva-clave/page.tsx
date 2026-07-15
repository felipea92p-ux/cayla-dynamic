"use client";

import { useEffect, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Colibri } from "@/components/marca";

type Estado = "cargando" | "listo" | "invalido" | "guardado";

export default function NuevaClavePage() {
  const router = useRouter();
  const [estado, setEstado] = useState<Estado>("cargando");
  const [nueva, setNueva] = useState("");
  const [confirma, setConfirma] = useState("");
  const [guardando, setGuardando] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // El enlace del correo trae el token en la URL; supabase-js lo detecta solo
  // y dispara PASSWORD_RECOVERY. Si en unos segundos no llega, el enlace ya
  // expiró o es inválido.
  useEffect(() => {
    const supabase = createAdminSupabaseClient();
    let activo = true;
    const { data: sub } = supabase.auth.onAuthStateChange((event) => {
      if (event === "PASSWORD_RECOVERY" && activo) setEstado("listo");
    });
    supabase.auth.getSession().then(({ data }) => {
      if (activo && data.session) setEstado((e) => (e === "cargando" ? "listo" : e));
    });
    const t = setTimeout(() => {
      setEstado((e) => (e === "cargando" ? "invalido" : e));
    }, 4000);
    return () => {
      activo = false;
      sub.subscription.unsubscribe();
      clearTimeout(t);
    };
  }, []);

  async function guardar(e: FormEvent) {
    e.preventDefault();
    setError(null);
    if (nueva.length < 6) { setError("La contraseña debe tener al menos 6 caracteres."); return; }
    if (nueva !== confirma) { setError("Las contraseñas no coinciden."); return; }
    setGuardando(true);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.auth.updateUser({ password: nueva });
    setGuardando(false);
    if (error) { setError(error.message); return; }
    setEstado("guardado");
  }

  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-8 p-8">
      <div className="flex flex-col items-center gap-4">
        <Colibri tono="rojo" className="w-12" />
        <div className="text-center">
          <h1 className="font-serif text-3xl leading-none">Dynamic</h1>
          <p className="etiqueta mt-2 text-taupe">Nueva clave</p>
        </div>
      </div>

      {estado === "cargando" && <p className="text-sm text-taupe">Verificando el enlace…</p>}

      {estado === "invalido" && (
        <div className="flex w-full max-w-xs flex-col gap-3 text-center">
          <p className="text-sm text-rojo">Este enlace ya no es válido o expiró.</p>
          <a href="/admin/olvide-clave" className="text-sm text-taupe underline-offset-2 hover:underline">
            Pedir un enlace nuevo
          </a>
        </div>
      )}

      {estado === "listo" && (
        <form onSubmit={guardar} className="flex w-full max-w-xs flex-col gap-3">
          <input
            type="password"
            placeholder="Nueva contraseña"
            value={nueva}
            onChange={(e) => setNueva(e.target.value)}
            className="rounded-lg border border-sand bg-crema px-4 py-3 outline-none placeholder:text-taupe/60 focus:border-taupe"
            required
          />
          <input
            type="password"
            placeholder="Repite la nueva contraseña"
            value={confirma}
            onChange={(e) => setConfirma(e.target.value)}
            className="rounded-lg border border-sand bg-crema px-4 py-3 outline-none placeholder:text-taupe/60 focus:border-taupe"
            required
          />
          {error && <p className="text-sm text-rojo">{error}</p>}
          <button
            type="submit"
            disabled={guardando}
            className="rounded-lg bg-tinta px-4 py-3 font-medium text-crema transition-colors hover:bg-rojo-profundo disabled:opacity-50"
          >
            {guardando ? "Guardando…" : "Guardar y entrar"}
          </button>
        </form>
      )}

      {estado === "guardado" && (
        <div className="flex w-full max-w-xs flex-col gap-4 text-center">
          <p className="text-sm text-verde">Tu contraseña se actualizó correctamente.</p>
          <button
            onClick={() => router.replace("/admin/dashboard")}
            className="rounded-lg bg-tinta px-4 py-3 font-medium text-crema transition-colors hover:bg-rojo-profundo"
          >
            Ir al panel
          </button>
        </div>
      )}
    </div>
  );
}

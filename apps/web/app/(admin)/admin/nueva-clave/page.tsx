"use client";

import { Suspense, useEffect, useState, type FormEvent } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { REQUISITOS_CLAVE, problemasDeClave } from "@cayla-dynamic/shared";
import { guardarMiClave } from "@/lib/admin/mi-clave";
import { Colibri } from "@/components/marca";

type Estado = "cargando" | "listo" | "invalido" | "guardado";

function NuevaClaveContenido() {
  const router = useRouter();
  // Por qué llegó acá. Sin esto, quien entra con su clave de siempre y es
  // desviado a esta pantalla no tiene forma de saber qué pasó: ve un formulario
  // de «nueva clave» sin haber pedido ninguna, y lo más razonable que puede
  // pensar es que le robaron la cuenta.
  const motivo = useSearchParams().get("motivo");
  const [correo, setCorreo] = useState<string | null>(null);
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
      if (!activo || !data.session) return;
      setCorreo(data.session.user.email ?? null);
      setEstado((e) => (e === "cargando" ? "listo" : e));
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
    // La política vive en `packages/shared/src/clave.ts` y la comprueba también
    // el servidor. Acá se comprueba igual para que la respuesta sea inmediata,
    // no para sustituir aquélla: una validación que solo vive en el navegador
    // es una sugerencia.
    const problemas = problemasDeClave(nueva, correo);
    if (problemas.length > 0) { setError(problemas.join(" ")); return; }
    if (nueva !== confirma) { setError("Las contraseñas no coinciden."); return; }
    setGuardando(true);
    const problema = await guardarMiClave(nueva);
    setGuardando(false);
    if (problema) { setError(problema); return; }
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

      {estado === "listo" && motivo === "debil" && (
        <p className="w-full max-w-xs rounded-lg bg-sand/60 px-4 py-3 text-sm text-tinta">
          Tu clave actual ya no cumple lo que pide el sistema. Con esta cuenta se ven los
          sueldos de todo el equipo, así que hay que cambiarla antes de seguir.
        </p>
      )}

      {estado === "listo" && motivo === "temporal" && (
        <p className="w-full max-w-xs rounded-lg bg-sand/60 px-4 py-3 text-sm text-tinta">
          Estás entrando con una clave que te dictaron. Elige la tuya: a partir de ahora
          nadie más la conoce.
        </p>
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
          {/* Los requisitos ANTES de escribir, no después de fallar. Una regla
              que solo aparece cuando ya te equivocaste es una regla que enseña
              tarde — y acá cada intento fallido es una vuelta más a un
              formulario que ya se abrió porque alguien perdió su acceso. */}
          <ul className="flex flex-col gap-0.5 text-xs text-taupe">
            {REQUISITOS_CLAVE.map((r) => <li key={r}>· {r}</li>)}
          </ul>
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

// `useSearchParams` obliga a un límite de Suspense en Next; sin él, el build
// falla al prerrenderizar esta ruta. Mismo patrón que usa Incidencias.
export default function NuevaClavePage() {
  return (
    <Suspense fallback={<div className="flex flex-1 items-center justify-center p-8"><p className="text-sm text-taupe">Cargando…</p></div>}>
      <NuevaClaveContenido />
    </Suspense>
  );
}

"use client";

import { useState, type FormEvent } from "react";
import * as Sentry from "@sentry/nextjs";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Colibri } from "@/components/marca";

export default function OlvideClavePage() {
  const [email, setEmail] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [enviado, setEnviado] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function enviar(e: FormEvent) {
    e.preventDefault();
    setEnviando(true);
    setError(null);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), {
      redirectTo: `${window.location.origin}/admin/nueva-clave`,
    });
    setEnviando(false);
    // No revelamos si el correo existe o no: mismo mensaje en ambos casos.
    // (Supabase tampoco lo revela: a un correo sin cuenta responde 200 y no
    // manda nada. Por eso un error acá nunca significa «ese correo no existe».)
    if (error && error.status !== 400) {
      // Se perdía entero. El 2026-08-12 alguien vio este mensaje desde su
      // teléfono y no quedó rastro de por qué: ni el status, ni el texto de
      // Supabase, ni a qué correo se le intentó enviar. Ahora va a Sentry.
      Sentry.captureException(error, { tags: { pantalla: "olvide-clave" } });
      // Dos causas distintas, y a la persona le importa la diferencia: con 429
      // basta esperar; con cualquier otra, esperar no arregla nada y lo que
      // corresponde es pedir la clave por el otro camino.
      setError(
        error.status === 429
          ? "Se pidieron demasiados enlaces en la última hora. Espera un rato y vuelve a intentarlo."
          : "No se pudo enviar el correo. Pídele a Felipe una clave nueva desde el panel; no hace falta que sigas intentando acá.",
      );
      return;
    }
    setEnviado(true);
  }

  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-8 p-8">
      <div className="flex flex-col items-center gap-4">
        <Colibri tono="rojo" className="w-12" />
        <div className="text-center">
          <h1 className="font-serif text-3xl leading-none">Dynamic</h1>
          <p className="etiqueta mt-2 text-taupe">Recuperar acceso</p>
        </div>
      </div>

      {enviado ? (
        <div className="flex w-full max-w-xs flex-col gap-4 text-center">
          <p className="text-sm text-tinta">
            Si <span className="font-medium">{email}</span> tiene una cuenta, te llegará un correo con un enlace
            para crear una nueva clave. Revisa también spam/promociones.
          </p>
          <a href="/admin/login" className="text-sm text-taupe underline-offset-2 hover:underline">
            Volver a entrar
          </a>
        </div>
      ) : (
        <form onSubmit={enviar} className="flex w-full max-w-xs flex-col gap-3">
          <p className="text-sm text-taupe">
            Escribe el correo con el que entras al panel. Te enviaremos un enlace para crear una nueva clave.
          </p>
          <input
            type="email"
            placeholder="correo"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="rounded-lg border border-sand bg-crema px-4 py-3 outline-none placeholder:text-taupe/60 focus:border-taupe"
            required
          />
          {error && <p className="text-sm text-rojo">{error}</p>}
          <button
            type="submit"
            disabled={enviando}
            className="rounded-lg bg-tinta px-4 py-3 font-medium text-crema transition-colors hover:bg-rojo-profundo disabled:opacity-50"
          >
            {enviando ? "Enviando…" : "Enviar enlace"}
          </button>
          <a href="/admin/login" className="text-center text-sm text-taupe underline-offset-2 hover:underline">
            Volver a entrar
          </a>
        </form>
      )}
    </div>
  );
}

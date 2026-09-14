"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Colibri } from "@/components/marca";
import { ROLES_CON_PANEL, claveSirve } from "@cayla-dynamic/shared";
import { clavePorCambiar, marcarMiClavePorCambiar } from "@/lib/admin/mi-clave";
import { esFallaDeRed } from "@/lib/admin/mensaje-error";
import { Campo } from "@/components/ui/campo";
import { CampoClave } from "@/components/ui/campo-clave";
import { Boton } from "@/components/ui/boton";

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
      // No todo error acá es "la clave está mal". Un fallo de red o de Supabase
      // caído (frecuente en sede, con wifi de tienda) devuelve el mismo `error`
      // genérico que una clave incorrecta, y decirle a la encargada que su clave
      // está mal cuando el problema es la conexión la manda a escribirla de
      // nuevo, a pedir un enlace de recuperación que tampoco va a llegar, y
      // recién ahí a llamar con un diagnóstico equivocado.
      if (error.status === 400) {
        setError("Correo o contraseña incorrectos.");
      } else if (error.status === 429) {
        setError("Demasiados intentos seguidos. Espera unos minutos antes de volver a intentar.");
      } else if (esFallaDeRed(error)) {
        setError("No es tu clave: no hay conexión con el sistema. Intenta de nuevo en un momento.");
      } else {
        setError("No se pudo entrar. Vuelve a intentarlo; si sigue igual, avisa a Felipe.");
      }
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

    // ── ¿HAY QUE CAMBIAR ESTA CLAVE ANTES DE SEGUIR? ────────────────────────
    //
    // Éste es el ÚNICO momento en que el sistema ve una clave en claro: lo que
    // Supabase guarda es un hash, y de un hash no se puede juzgar si la clave
    // era «111111». Así que es el único sitio donde se puede atrapar a las que
    // YA EXISTÍAN cuando se subió la política — subir el mínimo no caduca
    // ninguna clave vieja, solo impide poner una nueva floja.
    //
    // Dos motivos llevan a la misma pantalla, y por eso comparten marca:
    //   · `debil`    — la clave con la que acaba de entrar no cumple la política.
    //   · `temporal` — se la dictaron al crear o resetear su cuenta, y nunca la
    //                  cambió. Si se pasó por WhatsApp, como sugiere la propia
    //                  pantalla de Cuentas, la conoce quien la envió.
    //
    // Se ANOTA en la cuenta además de redirigir: una redirección se esquiva
    // escribiendo otra dirección en la barra, y esta cuenta ve los sueldos de
    // todo el equipo. Con la marca puesta, el panel entero la devuelve acá.
    const debil = !claveSirve(password, email);
    if (debil) await marcarMiClavePorCambiar(data.session?.access_token ?? "");
    if (debil || clavePorCambiar(data.user)) {
      setCargando(false);
      router.replace(`/admin/nueva-clave?motivo=${debil ? "debil" : "temporal"}`);
      return;
    }

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
        <Campo
          type="email"
          placeholder="correo"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
        />
        <CampoClave
          placeholder="contraseña"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
        />
        {error && <p className="text-sm text-rojo">{error}</p>}
        <Boton type="submit" variante="primario" disabled={cargando} cargando={cargando}>
          {cargando ? "Entrando…" : "Entrar"}
        </Boton>
        <a href="/admin/olvide-clave" className="text-center text-sm text-taupe underline-offset-2 hover:underline">
          ¿Olvidaste tu clave?
        </a>
      </form>
    </div>
  );
}

"use client";

import { useState, useSyncExternalStore, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Colibri } from "@/components/marca";
import { PanelVuelo } from "@/components/login/PanelVuelo";
import { saludoDelDia } from "@/lib/login-vuelo";
import { useRafagaDeClics } from "@/lib/use-rafaga-de-clics";
import { ROLES_CON_PANEL, claveSirve } from "@cayla-dynamic/shared";
import { clavePorCambiar, marcarMiClavePorCambiar } from "@/lib/admin/mi-clave";
import { esFallaDeRed } from "@/lib/admin/mensaje-error";
import { esCuentaDeServicio, MENSAJE_CUENTA_DE_SERVICIO } from "@/lib/cuenta-de-servicio";
import { Campo } from "@/components/ui/campo";
import { CampoClave } from "@/components/ui/campo-clave";
import { Boton } from "@/components/ui/boton";

const sinSuscripcion = () => () => {};

export default function AdminLoginPage() {
  const router = useRouter();
  // El saludo depende de la hora: lo pone el navegador (en el servidor no se sabe cuándo se abrirá la página).
  // Easter egg: cinco clics seguidos sobre el colibrí de arriba (el del celular; en pantalla ancha es el del panel). Ver docs/easter-eggs.md.
  const { activo: travieso, alClic } = useRafagaDeClics();
  const saludo = useSyncExternalStore(sinSuscripcion, () => saludoDelDia(new Date()), () => null);
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

    // Una estación de retail tiene usuario (así entra a las tiendas), pero no
    // es una persona: aquí no tiene nada que ver. Antes que la clave, porque
    // mandarla a cambiarla sería invitarla a quedarse (0490).
    if (await esCuentaDeServicio(supabase, data.user?.id)) {
      await supabase.auth.signOut();
      setCargando(false);
      setError(MENSAJE_CUENTA_DE_SERVICIO);
      return;
    }

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

  // «El vuelo» (el mismo login de CAYLA Retail): la marca a la izquierda y el formulario a la derecha desde 1024 px;
  // en el celular, solo el formulario con la marca arriba, como siempre.
  return (
    <div className="login-pagina">
      <PanelVuelo />

      <main className="login-lado">
        <form onSubmit={entrar} className="login-form flex flex-col gap-3">
          <div className="login-marca-chica">
            <div className="w-12" onClick={alClic} data-travieso={travieso ? "" : undefined}>
              <Colibri tono="rojo" className="w-12" />
            </div>
            <p className="mt-4 font-serif text-3xl leading-none">Dynamic</p>
            <p className="etiqueta mt-2 text-taupe">Panel de administración · CAYLA</p>
          </div>

          <div className="mb-3">
            <p className="login-saludo" data-listo={saludo ? "" : undefined}>
              {saludo ?? "\u00a0"}
            </p>
            <h1 className="login-titulo">Entrar</h1>
            <p className="mt-2 text-sm leading-relaxed text-taupe">
              Con el correo y la contraseña de tu cuenta de CAYLA.
            </p>
          </div>

          <Campo
            etiqueta="Correo"
            type="email"
            autoComplete="username"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
          />
          <CampoClave
            etiqueta="Contraseña"
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
          {error && <p className="text-sm text-rojo">{error}</p>}
          <Boton type="submit" variante="primario" disabled={cargando} cargando={cargando} className="login-entrar mt-2">
            {cargando ? "Entrando…" : "Entrar"}
          </Boton>
        </form>

        <p className="login-pie text-sm">
          <a href="/admin/olvide-clave" className="text-taupe underline-offset-2 hover:underline">
            ¿Olvidaste tu clave?
          </a>
        </p>
      </main>
    </div>
  );
}

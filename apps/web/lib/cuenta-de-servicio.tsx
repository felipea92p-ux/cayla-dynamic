"use client";

import { useEffect, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Colibri } from "@/components/marca";

// ============================================================================
// Una cuenta de servicio no entra a Dynamic
// ============================================================================
// Las estaciones de caja y almacén de cayla-retail son filas de `personas`
// (retail les cuelga ventas y movimientos) con usuario de acceso propio, porque
// así entran a las tiendas. Pero no son personas: no marcan, no cobran, no
// tienen «Lo mío» ni panel. La 0490 las marca con `cuenta_de_servicio`, y la
// decisión (Felipe, 2026-09-28) es que Dynamic les niegue la entrada con una
// frase que diga por qué, en vez de mostrarles un «Lo mío» vacío.
//
// Tres sitios preguntan, y los tres pasan por aquí para decir lo mismo: el
// login (antes de mandar a nadie a ningún lado), el marco del panel y el de
// «Lo mío» (para una sesión que ya estaba abierta).
//
// Si la columna todavía no existe —el código llegó antes que la 0490— la
// consulta falla y se responde `false`: la cuenta se trata como una persona,
// que es lo que era hasta hoy. Nunca deja fuera a alguien por un error.
// ============================================================================

export const MENSAJE_CUENTA_DE_SERVICIO =
  "Esta es una cuenta de Retail (una estación de caja o almacén), no la de una persona. " +
  "No tiene acceso a Dynamic: para marcar asistencia o ver lo tuyo, entra con tu propio usuario.";

type Cliente = ReturnType<typeof createAdminSupabaseClient>;

/** ¿El usuario de esta sesión es una cuenta de servicio? Ante cualquier duda, `false`. */
export async function esCuentaDeServicio(supabase: Cliente, authUserId: string | null | undefined): Promise<boolean> {
  if (!authUserId) return false;
  const { data, error } = await supabase
    .from("personas")
    .select("cuenta_de_servicio")
    .eq("auth_user_id", authUserId)
    .maybeSingle();
  if (error || !data) return false;
  return (data as { cuenta_de_servicio?: boolean }).cuenta_de_servicio === true;
}

/**
 * Envuelve una superficie (panel o «Lo mío»). Mientras pregunta, deja pasar:
 * no se retiene la pantalla de nadie por una consulta lenta. Si la sesión es
 * de una cuenta de servicio, la cierra y muestra por qué.
 */
export function GuardaCuentaDeServicio({ children }: { children: React.ReactNode }) {
  const [bloqueada, setBloqueada] = useState(false);

  useEffect(() => {
    let vivo = true;
    const supabase = createAdminSupabaseClient();
    // Del almacén de la sesión: `getUser()` era una ronda entera al servidor de autenticación en
    // cada apertura, para un dato que la sesión ya trae. La base sigue validando el token.
    void supabase.auth.getSession().then(async ({ data }) => {
      if (!(await esCuentaDeServicio(supabase, data.session?.user.id)) || !vivo) return;
      setBloqueada(true);
      await supabase.auth.signOut();
    });
    return () => { vivo = false; };
  }, []);

  if (!bloqueada) return <>{children}</>;
  return <CuentaDeServicioSinAcceso />;
}

export function CuentaDeServicioSinAcceso() {
  return (
    <div className="flex min-h-screen flex-1 flex-col items-center justify-center gap-6 bg-crema p-8 text-tinta">
      <Colibri tono="rojo" className="w-12" />
      <div className="max-w-sm text-center">
        <h1 className="font-serif text-2xl leading-tight">Esta cuenta no es de Dynamic</h1>
        <p className="mt-3 text-sm text-taupe">{MENSAJE_CUENTA_DE_SERVICIO}</p>
      </div>
      <a href="/admin/login" className="text-sm underline underline-offset-4 hover:text-rojo">
        Entrar con otro usuario
      </a>
    </div>
  );
}

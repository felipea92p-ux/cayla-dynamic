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
//
// Y una segunda razón para no pasar, desde la 0597: quien ya se dio de baja. El
// candado de verdad está en la base (su cuenta queda sin poder iniciar sesión),
// pero el token que ya tenía sigue valiendo hasta una hora, y esta guarda es la
// que le cierra esa sesión en cuanto abre la app o vuelve a la pestaña.
//
// Y dos más, del 2026-11-08: la cuenta del TERMINAL de una sede y cualquier
// usuario sin ficha en `personas`. Ese día, en la Mac mini de TRU, el panel
// estaba abierto con una cuenta así: el menú mostraba solo «Info» y
// «Publicaciones», Correcciones decía «0 colaboradores · Nadie coincide con este
// filtro» y «Para atender: Nada pendiente» mientras el terminal, en la pestaña
// de al lado, avisaba de 4 marcas sin registrar. Ninguna consulta fallaba: la
// RLS le devuelve CERO filas a quien no es nadie (la 0291 le quitó al terminal
// la lectura de `personas`, y `fn_marcas_apartadas` responde vacío a quien no es
// admin ni líder), y una lista vacía sin error se lee igual que «no hay nada».
// Es la misma pantalla engañosa que la 0490 cerró para las estaciones de Retail.
//
// La duda se sigue resolviendo hacia dentro: solo se cierra cuando la consulta
// CONTESTÓ y dijo que no hay ficha. Un error de red no deja fuera a nadie.
//
// ⚠️ Y SE CIERRA SOLO EN ESTE NAVEGADOR (`scope: "local"`). `signOut()` a secas
// es global en supabase-js: revoca TODAS las sesiones de ese usuario. Con la
// cuenta del terminal eso desvincula la Mac mini de la sede —deja de enviar
// marcas— y con una estación de Retail saca a la caja de la tienda. Solo la
// baja (0597) cierra en todos lados, que es lo que se busca ahí.
// ============================================================================

export const MENSAJE_CUENTA_DE_SERVICIO =
  "Esta es una cuenta de Retail (una estación de caja o almacén), no la de una persona. " +
  "No tiene acceso a Dynamic: para marcar asistencia o ver lo tuyo, entra con tu propio usuario.";

// No dice «te dieron de baja»: GoTrue responde lo mismo con cualquier clave, así
// que esta frase la puede leer quien solo sepa el correo de esa persona.
export const MENSAJE_CUENTA_DADA_DE_BAJA =
  "Esta cuenta ya no tiene acceso a Dynamic. Si crees que es un error, habla con Desarrollo Organizacional.";

// Quien entra al panel con la cuenta del terminal casi siempre es la líder de la
// sede, que tiene esas credenciales porque vincula la Mac. Por eso se le dice
// qué es esa cuenta y qué hacer, sin culpa.
export const MENSAJE_CUENTA_DE_TERMINAL =
  "Esta es la cuenta del terminal de marcaje de la sede: sirve para vincular la Mac mini, no para entrar al panel. " +
  "Entra con tu propio usuario. El terminal sigue funcionando: no se desvinculó.";

export const MENSAJE_CUENTA_SIN_FICHA =
  "Este usuario no está unido a ninguna ficha del equipo, así que el sistema no sabe quién eres ni qué puedes ver. " +
  "Pide a Desarrollo Organizacional que revise tu cuenta en Equipo → Cuentas.";

/** ¿El error de iniciar sesión es que la cuenta está cortada (0597), y no la clave? */
export function esCuentaDadaDeBaja(error: { code?: string } | null | undefined): boolean {
  return error?.code === "user_banned";
}

type Cliente = ReturnType<typeof createAdminSupabaseClient>;

export type MotivoSinAcceso = "servicio" | "baja" | "terminal" | "sin_ficha";

/**
 * Por qué esta sesión no debería seguir adentro. Ante cualquier duda, `null`.
 *
 * «Sin ficha» exige que la consulta haya CONTESTADO sin fila: la política
 * `personas_select_propia` deja a cada quien leer la suya, así que una persona
 * de verdad siempre se encuentra. Un error, en cambio, no dice nada.
 */
export async function motivoSinAcceso(supabase: Cliente, authUserId: string | null | undefined): Promise<MotivoSinAcceso | null> {
  if (!authUserId) return null;
  const { data, error } = await supabase
    .from("personas")
    .select("cuenta_de_servicio, estado")
    .eq("auth_user_id", authUserId)
    .maybeSingle();
  if (error) return null;
  if (!data) {
    // `terminales_select_propio` (0003) deja a la cuenta del terminal leer su fila.
    const t = await supabase.from("terminales").select("id").eq("auth_user_id", authUserId).maybeSingle();
    if (t.error) return null;
    return t.data ? "terminal" : "sin_ficha";
  }
  const fila = data as { cuenta_de_servicio?: boolean; estado?: string };
  if (fila.cuenta_de_servicio === true) return "servicio";
  return fila.estado === "inactivo" ? "baja" : null;
}

/** El texto que se le muestra a cada motivo, para que el login y la guarda digan lo mismo. */
export function mensajeSinAcceso(motivo: MotivoSinAcceso): string {
  switch (motivo) {
    case "servicio": return MENSAJE_CUENTA_DE_SERVICIO;
    case "baja": return MENSAJE_CUENTA_DADA_DE_BAJA;
    case "terminal": return MENSAJE_CUENTA_DE_TERMINAL;
    case "sin_ficha": return MENSAJE_CUENTA_SIN_FICHA;
  }
}

/**
 * Cierra la sesión del panel de quien no debe estar. Solo la baja cierra en todos
 * los dispositivos; el resto, solo aquí (ver el encabezado: global desvincula el
 * terminal de la sede o saca a la caja de Retail).
 */
export async function cerrarSesionSinAcceso(supabase: Cliente, motivo: MotivoSinAcceso): Promise<void> {
  await supabase.auth.signOut({ scope: motivo === "baja" ? "global" : "local" });
}

/**
 * Envuelve una superficie (panel o «Lo mío»). Mientras pregunta, deja pasar:
 * no se retiene la pantalla de nadie por una consulta lenta. Si la sesión es
 * de una cuenta de servicio o de alguien dado de baja, la cierra y muestra por
 * qué. Vuelve a preguntar al regresar a la pestaña: una baja puede llegar con la
 * app abierta, y el celular se deja así días.
 */
export function GuardaDeAcceso({ children }: { children: React.ReactNode }) {
  const [motivo, setMotivo] = useState<MotivoSinAcceso | null>(null);

  useEffect(() => {
    let vivo = true;
    const supabase = createAdminSupabaseClient();
    // Del almacén de la sesión: `getUser()` era una ronda entera al servidor de autenticación en
    // cada apertura, para un dato que la sesión ya trae. La base sigue validando el token.
    const preguntar = () => supabase.auth.getSession().then(async ({ data }) => {
      const m = await motivoSinAcceso(supabase, data.session?.user.id);
      if (!m || !vivo) return;
      setMotivo(m);
      await cerrarSesionSinAcceso(supabase, m);
    });
    const alVolver = () => { if (document.visibilityState === "visible") void preguntar(); };
    void preguntar();
    document.addEventListener("visibilitychange", alVolver);
    return () => {
      vivo = false;
      document.removeEventListener("visibilitychange", alVolver);
    };
  }, []);

  if (motivo === "servicio") return <CuentaDeServicioSinAcceso />;
  if (motivo === "baja") return <CuentaDadaDeBajaSinAcceso />;
  if (motivo === "terminal") return <SinAccesoConOtroUsuario titulo="Esta es la cuenta del terminal" texto={MENSAJE_CUENTA_DE_TERMINAL} />;
  if (motivo === "sin_ficha") return <SinAccesoConOtroUsuario titulo="Este usuario no tiene ficha" texto={MENSAJE_CUENTA_SIN_FICHA} />;
  return <>{children}</>;
}

function SinAccesoConOtroUsuario({ titulo, texto }: { titulo: string; texto: string }) {
  return (
    <div className="flex min-h-screen flex-1 flex-col items-center justify-center gap-6 bg-crema p-8 text-tinta">
      <Colibri tono="rojo" className="w-12" />
      <div className="max-w-sm text-center">
        <h1 className="font-serif text-2xl leading-tight">{titulo}</h1>
        <p className="mt-3 text-sm text-taupe">{texto}</p>
      </div>
      <a href="/admin/login" className="text-sm underline underline-offset-4 hover:text-rojo">
        Entrar con mi usuario
      </a>
    </div>
  );
}

function CuentaDadaDeBajaSinAcceso() {
  return (
    <div className="flex min-h-screen flex-1 flex-col items-center justify-center gap-6 bg-crema p-8 text-tinta">
      <Colibri tono="rojo" className="w-12" />
      <div className="max-w-sm text-center">
        <h1 className="font-serif text-2xl leading-tight">Esta cuenta ya no tiene acceso</h1>
        <p className="mt-3 text-sm text-taupe">{MENSAJE_CUENTA_DADA_DE_BAJA}</p>
      </div>
    </div>
  );
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

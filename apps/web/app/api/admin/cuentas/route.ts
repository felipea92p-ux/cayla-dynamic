import { createAnonClient, createServiceRoleClient, createUserClient } from "@cayla-dynamic/database";
import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { problemasDeClave, puedeActuarSobre, puedeGestionarCatalogos, ROLES_CON_PANEL } from "@cayla-dynamic/shared";

// Gestión de cuentas del panel — SOLO admin/lider_do. Corre en el servidor con la
// llave de servicio; verifica que quien llama sea admin (por su sesión).
// Acciones: listar | resetear (contraseña de otro) | crear (cuenta de una persona)
//         | invitar (correo para que elija su clave) | reinvitar | promover
//         | cambiar-correo (el usuario con el que entra, en la cuenta y en la ficha).

// Estas claves son la única credencial de una cuenta del panel hasta que su dueña
// la cambia. `Math.random()` NO sirve para eso: no es criptográfico y su estado
// interno se puede reconstruir observando unas pocas salidas, así que quien viera
// una clave generada podría predecir las siguientes. `crypto.getRandomValues` sí
// es del sistema operativo.
//
// El bucle de descarte existe porque 256 no es múltiplo de 24 ni de 8: tomar el
// resto a secas haría que las primeras letras del alfabeto salieran más seguido.
// Se descartan los bytes de la cola incompleta y se pide otro.
function pick(set: string, n: number) {
  const limite = Math.floor(256 / set.length) * set.length;
  let out = "";
  while (out.length < n) {
    const bytes = new Uint8Array(n - out.length);
    globalThis.crypto.getRandomValues(bytes);
    for (const b of bytes) if (b < limite) out += set[b % set.length];
  }
  return out;
}

// La clave temporal tiene que cumplir la MISMA política que se le va a exigir a
// la persona cuando elija la suya (`packages/shared/src/clave.ts`): 12
// caracteres, minúscula, mayúscula y número. La de antes tenía 10 y no habría
// pasado el filtro nuevo — el sistema habría repartido claves que él mismo
// rechaza, y el error saldría en el momento más confuso posible: al crear la
// cuenta, hablando de la contraseña de alguien que aún no existe.
//
// Los grupos separados por guiones son para dictarla por teléfono sin que nadie
// deletree dieciséis caracteres seguidos. Los alfabetos ya excluían las letras y
// números que se confunden al leer en voz alta (l/I/1, O/0).
//
// Se valida lo que se genera y se vuelve a tirar si no pasa. No es paranoia: el
// azar puede sacar una seguidilla larga, y esta casa aprendió que un guardián
// que solo se prueba con lo que debe pasar es un guardián que no se ha probado.
function generarClave() {
  const abc = "abcdefghijkmnpqrstuvwxyz", ABC = "ABCDEFGHJKLMNPQRSTUVWXYZ", num = "23456789";
  for (let intento = 0; intento < 20; intento++) {
    const candidata = `${pick(ABC, 1)}${pick(abc, 5)}-${pick(num, 4)}-${pick(abc, 4)}`;
    if (problemasDeClave(candidata).length === 0) return candidata;
  }
  // Inalcanzable en la práctica (20 intentos independientes), pero si pasara,
  // fallar es mejor que repartir una clave que el sistema va a rechazar después.
  throw new Error("no se pudo generar una clave que cumpla la política");
}

// Lo que se le anota a una cuenta a la que se le acaba de dictar una clave: hay
// que cambiarla antes de usar el panel. Sin esto, una clave repartida por
// WhatsApp —que es el camino que la propia pantalla sugiere: «cópiala y
// pásasela»— se queda como credencial permanente, conocida por quien la envió y
// por cualquiera que haya visto ese chat.
//
// Va en `app_metadata` y no en `user_metadata` porque el segundo lo puede
// escribir la propia persona desde el navegador con `updateUser({ data })`: una
// marca ahí la apagaría sin cambiar la clave. Se apaga en `/api/mi-clave`.
const CLAVE_TEMPORAL = { clave_por_cambiar: true };


// De cada cuenta de acceso interesan tres cosas, y ninguna vive en `personas`:
// con qué correo entra, si alguna vez entró, y si su correo está confirmado.
// Las dos últimas son las que distinguen «le mandé la invitación y la aceptó»
// de «le mandé la invitación y sigue sin abrirla».
interface CuentaAuth {
  email: string;
  ultimoAcceso: string | null;
  confirmado: boolean;
}

async function usuariosPorId(admin: any): Promise<Record<string, CuentaAuth>> {
  const out: Record<string, CuentaAuth> = {};
  let page = 1;
  while (true) {
    const { data } = await admin.auth.admin.listUsers({ page, perPage: 200 });
    for (const u of data.users) {
      out[u.id] = {
        email: u.email ?? "",
        ultimoAcceso: u.last_sign_in_at ?? null,
        confirmado: !!u.email_confirmed_at,
      };
    }
    if (data.users.length < 200) break;
    page++;
  }
  return out;
}

// Los errores de Supabase Auth no son de Postgres: no traen código SQL y llegan
// en inglés. Quien los lee acá es una admin de CAYLA, no una ingeniera, así que
// el más frecuente —el correo repetido, que sale cada vez que alguien intenta
// crear dos veces la misma cuenta— se dice en español. El resto se registra y
// se responde con algo honesto en vez de pegar el texto en inglés.
function mensajeDeAuth(error: { message?: string; status?: number } | null | undefined): string {
  const t = (error?.message ?? "").toLowerCase();
  // El más probable cuando se reenvían muchas invitaciones de una pasada: el
  // proyecto tiene un tope de correos por hora. No es un fallo del envío ni un
  // problema de esa persona — es que hay que esperar y seguir con el resto.
  if (error?.status === 429 || t.includes("rate limit") || t.includes("only request this after")) {
    return "Se llegó al tope de correos por hora del proyecto. Espera un rato y sigue con las que faltan; las ya enviadas no se pierden.";
  }
  if (t.includes("already been registered") || t.includes("already registered")) {
    return "Ese correo ya está registrado en otra cuenta. Usa otro, o revisa si esa persona ya tiene acceso.";
  }
  if (t.includes("password")) {
    return "La contraseña generada no cumple los requisitos del sistema de acceso. Vuelve a intentarlo.";
  }
  if (t.includes("invalid") && t.includes("email")) {
    return "Ese correo no tiene un formato válido.";
  }
  return "El sistema de acceso no pudo completar la operación. Vuelve a intentarlo; si sigue igual, avisa a Felipe.";
}

export async function POST(req: Request) {
  const admin = createServiceRoleClient();
  if (!admin) return NextResponse.json({ error: "servidor sin configurar" }, { status: 500 });

  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) return NextResponse.json({ error: "sin sesión" }, { status: 401 });
  const { data: userData, error: ue } = await admin.auth.getUser(token);
  if (ue || !userData.user) return NextResponse.json({ error: "sesión inválida" }, { status: 401 });
  // `admin` es la llave de servicio: se salta RLS por completo, así que esta
  // ruta NUNCA pasa por fn_rol_actual() (que la 0374 hizo devolver null para
  // quien está cesado). Sin pedir `estado` acá, una persona a la que se le
  // registró la salida sigue pudiendo listar el padrón de cuentas, resetear
  // la clave de cualquiera (la ruta se la devuelve) y cambiarse su propio
  // correo de login — recuperando todo lo que la 0374 le quitó. Es la misma
  // condición que la 0374 ya puso del lado de la base; acá hace falta
  // repetirla porque la llave de servicio no la ve.
  const { data: yo } = await admin.from("personas").select("rol, estado").eq("auth_user_id", userData.user.id).maybeSingle();
  if (!yo || yo.estado !== "activo" || !puedeGestionarCatalogos(yo.rol)) {
    return NextResponse.json({ error: "solo un administrador puede gestionar cuentas" }, { status: 403 });
  }

  const body = await req.json().catch(() => ({}));
  const { accion, personaId, email } = body;

  try {
    if (accion === "listar") {
      const { data: personas } = await admin
        .from("personas")
        .select("id, nombres, apellidos, rol, auth_user_id, sedes:sede_base_id(codigo)")
        .in("rol", [...ROLES_CON_PANEL])
        .eq("estado", "activo").eq("cuenta_de_servicio", false)
        .order("nombres");
      // Las integrantes que YA tienen cuenta también se listan. Hasta el
      // 2026-10-24 esta tabla solo traía los roles con panel, así que una
      // integrante que había aceptado su invitación no salía en ninguna lista de
      // la pantalla —ni en «Invitar», que es para quien no tiene cuenta, ni en
      // «Volver a invitar», que es para quien nunca entró— y no había dónde
      // resetearle la clave ni corregirle el correo. Sin cuenta siguen fuera:
      // a ellas se les crea el acceso por invitación, para que elijan su clave.
      const { data: integrantesConCuenta, error: errIntegrantes } = await admin
        .from("personas")
        .select("id, nombres, apellidos, rol, auth_user_id, sedes:sede_base_id(codigo)")
        .eq("rol", "integrante")
        .not("auth_user_id", "is", null)
        .eq("estado", "activo").eq("cuenta_de_servicio", false);
      if (errIntegrantes) {
        Sentry.captureException(errIntegrantes);
        return NextResponse.json({ error: mensajeDeError(errIntegrantes, "leer las cuentas de las integrantes") }, { status: 500 });
      }
      const usuarios = await usuariosPorId(admin);
      const cuentas = [...(personas ?? []), ...(integrantesConCuenta ?? [])]
        .map((p) => ({
          id: p.id,
          nombre: `${p.nombres} ${p.apellidos}`,
          rol: p.rol,
          sede: (p.sedes as { codigo?: string } | null)?.codigo ?? "?",
          email: p.auth_user_id ? usuarios[p.auth_user_id]?.email ?? null : null,
          tieneCuenta: !!p.auth_user_id,
        }))
        .sort((a, b) => a.nombre.localeCompare(b.nombre, "es"));
      // Integrantes que se pueden promover a encargada (para darles acceso al panel de su sede)
      const { data: integrantes } = await admin
        .from("personas")
        .select("id, nombres, apellidos, sedes:sede_base_id(codigo)")
        .eq("rol", "integrante")
        .eq("estado", "activo").eq("cuenta_de_servicio", false)
        .order("nombres");
      const promovibles = (integrantes ?? []).map((p: any) => ({
        id: p.id,
        nombre: `${p.nombres} ${p.apellidos}`,
        sede: p.sedes?.codigo ?? "?",
      }));
      // Integrantes a invitar para que dejen constancia de la política salarial.
      // La Ley 30709 obliga a INFORMARLA a cada persona y a poder probarlo, y
      // `fn_acusar_politica_salarial` solo acepta el acuse de quien tiene sesión
      // propia: sin cuenta, no hay forma de que dejen constancia.
      //
      // NO se les promueve a encargada para lograrlo — eso les daría acceso al
      // panel de su sede. Con su rol de integrante el menú ya les muestra solo
      // lo que les corresponde (la política salarial va sin `roles` a propósito)
      // y las RLS de `asignaciones_salario` y `movimientos_planilla` siguen
      // cerradas a admin/líder: no ven sueldos de nadie, ni el suyo en planilla.
      //
      // También entra la practicante (`en_planilla` es falso para ella: no es
      // 'planilla' ni 'prueba'), aunque su motivo no sea la Ley 30709 — tiene
      // horario y marca en el terminal igual que cualquiera, así que necesita la
      // misma cuenta mínima para entrar a lo suyo. RxH y no_trabajador se quedan
      // afuera a propósito: a un locador no se le mide jornada (0191), y darle
      // una cuenta de este tipo sería la misma señal de subordinación que esa
      // migración existe para evitar.
      const { data: sinCuenta } = await admin
        .from("personas")
        .select("id, nombres, apellidos, email, en_planilla, tipo_vinculo, sedes:sede_base_id(codigo)")
        .eq("rol", "integrante")
        .eq("estado", "activo").eq("cuenta_de_servicio", false)
        .or("en_planilla.eq.true,tipo_vinculo.eq.practicante")
        .is("auth_user_id", null)
        .order("apellidos");
      const invitables = (sinCuenta ?? [])
        .map((p: any) => ({
          id: p.id,
          nombre: `${p.nombres} ${p.apellidos}`,
          sede: p.sedes?.codigo ?? "?",
          email: p.email ?? null,
        }));
      // Quien tiene cuenta y NUNCA entró. Es el hueco que dejaba el diseño
      // anterior: `invitar` enlaza `auth_user_id` en cuanto GoTrue acepta el
      // envío, así que la persona desaparecía de «invitables» aunque el correo
      // se hubiera perdido en spam y ella no hubiera hecho nada. Quedaba
      // contada como resuelta sin haber entrado nunca.
      //
      // «Nunca entró» se lee de `last_sign_in_at`, no de `confirmado`: aceptar
      // la invitación ES iniciar sesión (el enlace la deja adentro para que
      // ponga su clave), así que ese campo en null significa exactamente
      // «no abrió el correo».
      //
      // Va sin filtrar por rol ni por planilla a propósito: acá no se decide a
      // quién invitar —eso ya se decidió cuando se le creó la cuenta— sino a
      // quién le quedó el acceso a medias.
      const { data: conCuenta } = await admin
        .from("personas")
        .select("id, nombres, apellidos, rol, auth_user_id, sedes:sede_base_id(codigo)")
        .not("auth_user_id", "is", null)
        .eq("estado", "activo").eq("cuenta_de_servicio", false)
        .order("apellidos");
      const pendientes = (conCuenta ?? [])
        .map((p: any) => ({ p, u: usuarios[p.auth_user_id] }))
        .filter(({ u }: any) => u && !u.ultimoAcceso)
        .map(({ p, u }: any) => ({
          id: p.id,
          nombre: `${p.nombres} ${p.apellidos}`,
          rol: p.rol,
          sede: p.sedes?.codigo ?? "?",
          email: u.email || null,
          // Decide qué correo se le puede mandar: a quien ya tiene clave
          // (cuenta creada a mano) GoTrue le rechaza una segunda invitación.
          confirmado: u.confirmado,
        }));

      return NextResponse.json({ cuentas, promovibles, invitables, pendientes });
    }

    if (accion === "invitar") {
      // Manda un correo de invitación al correo que la persona declaró. Ella
      // elige su propia clave: nadie más la conoce, ni siquiera quien invita —
      // a diferencia de `crear`, que devuelve la contraseña en pantalla.
      //
      // Y la cadena de prueba queda mejor: el correo llega a la dirección que
      // la persona designó en su contrato como medio de comunicación válido,
      // que es el mismo criterio con el que se entrega el RIT.
      const { data: p } = await admin
        .from("personas")
        .select("id, auth_user_id, rol, email, nombres, apellidos")
        .eq("id", personaId)
        .maybeSingle();
      if (!p) return NextResponse.json({ error: "persona no encontrada" }, { status: 404 });
      if (!puedeActuarSobre(yo.rol, p.rol)) {
        return NextResponse.json({ error: "no puedes invitar a esa persona" }, { status: 403 });
      }
      if (p.auth_user_id) return NextResponse.json({ error: "esa persona ya tiene cuenta" }, { status: 409 });
      const destino = (email ?? p.email ?? "").trim();
      if (!destino.includes("@")) {
        return NextResponse.json(
          { error: `${p.nombres} no tiene correo registrado. Agrégalo en Datos personales antes de invitarla.` },
          { status: 400 },
        );
      }
      // A dónde llega al hacer clic. Sin esto, Supabase la manda al Site URL
      // configurado en el proyecto: la persona cae en la raíz, sin clave y sin
      // saber qué hacer. Es la misma pantalla a la que lleva «Olvidé mi clave».
      // El origen sale del request para que funcione igual en producción y en
      // una vista previa de Vercel, sin una variable de entorno más que mantener.
      const origen = req.headers.get("origin") ?? new URL(req.url).origin;
      const { data: inv, error } = await admin.auth.admin.inviteUserByEmail(destino, {
        redirectTo: `${origen}/admin/nueva-clave`,
      });
      if (error) {
        Sentry.captureException(error);
        return NextResponse.json({ error: mensajeDeAuth(error) }, { status: 500 });
      }
      const { error: e2 } = await admin
        .from("personas")
        .update({ auth_user_id: inv.user.id })
        .eq("id", personaId);
      if (e2) {
        Sentry.captureException(e2);
        return NextResponse.json({ error: mensajeDeError(e2, "enlazar la cuenta con su ficha") }, { status: 500 });
      }
      return NextResponse.json({ invitado: destino });
    }

    if (accion === "reinvitar") {
      // Vuelve a mandarle el correo a quien tiene cuenta y nunca entró.
      //
      // Son DOS correos distintos, y cuál toca lo decide GoTrue, no nosotros
      // (medido contra el GoTrue local el 2026-08-13):
      //
      //   · sin confirmar → se puede reinvitar cuantas veces haga falta: el
      //     usuario es el mismo, `invited_at` se renueva y sale el correo de
      //     invitación. Es el caso de quien fue invitada y no abrió el enlace.
      //   · confirmada → la invitación responde 422 `email_exists`. Es quien
      //     tiene cuenta creada a mano, con `email_confirm: true` y una clave
      //     que alguien le dictó. A ella le sirve el correo de recuperación:
      //     el mismo de «Olvidé mi clave», que la deja poner la suya.
      //
      // Mandar el que no toca no es un detalle de forma: el primero fallaría
      // con un error en inglés y el segundo llegaría hablando de recuperar una
      // clave que la persona nunca tuvo.
      const { data: p } = await admin
        .from("personas")
        .select("id, auth_user_id, rol, email, nombres, apellidos")
        .eq("id", personaId)
        .maybeSingle();
      if (!p) return NextResponse.json({ error: "persona no encontrada" }, { status: 404 });
      if (!puedeActuarSobre(yo.rol, p.rol)) {
        return NextResponse.json({ error: "no puedes invitar a esa persona" }, { status: 403 });
      }
      if (!p.auth_user_id) {
        return NextResponse.json({ error: "esa persona todavía no tiene cuenta: usa Invitar" }, { status: 409 });
      }
      const { data: u, error: eu } = await admin.auth.admin.getUserById(p.auth_user_id);
      if (eu || !u?.user) {
        Sentry.captureException(eu ?? new Error("cuenta de acceso no encontrada"));
        return NextResponse.json({ error: mensajeDeAuth(eu) }, { status: 500 });
      }
      // Se relee del usuario y no de la lista: entre que la pantalla cargó y
      // llegó este clic la persona pudo entrar, y reenviarle el correo a quien
      // ya está adentro solo siembra dudas sobre si su clave sigue sirviendo.
      if (u.user.last_sign_in_at) {
        return NextResponse.json({ error: "ya entró al panel; si perdió su clave, resetéala" }, { status: 409 });
      }
      // El correo destino es el de la CUENTA, no el de la ficha: ese es el
      // usuario con el que entra. Si la ficha tiene otro, cambiarlo es otra
      // operación (y hoy se hace desde acá, no desde Datos personales).
      const correo = (u.user.email ?? p.email ?? "").trim();
      if (!correo.includes("@")) {
        return NextResponse.json(
          { error: `La cuenta de ${p.nombres} no tiene un correo válido.` },
          { status: 400 },
        );
      }
      const raiz = req.headers.get("origin") ?? new URL(req.url).origin;
      const destinoTrasClic = `${raiz}/admin/nueva-clave`;

      if (!u.user.email_confirmed_at) {
        const { error } = await admin.auth.admin.inviteUserByEmail(correo, { redirectTo: destinoTrasClic });
        if (error) {
          Sentry.captureException(error);
          return NextResponse.json({ error: mensajeDeAuth(error) }, { status: 500 });
        }
        return NextResponse.json({ enviado: correo, tipo: "invitacion" });
      }

      // La recuperación NO se pide con la llave de servicio: `/recover` es un
      // camino público y con la llave de servicio va firmado como quien puede
      // todo. Con la llave anónima se comporta igual que «Olvidé mi clave».
      const publico = createAnonClient();
      if (!publico) return NextResponse.json({ error: "servidor sin configurar" }, { status: 500 });
      const { error } = await publico.auth.resetPasswordForEmail(correo, { redirectTo: destinoTrasClic });
      if (error) {
        Sentry.captureException(error);
        return NextResponse.json({ error: mensajeDeAuth(error) }, { status: 500 });
      }
      return NextResponse.json({ enviado: correo, tipo: "recuperacion" });
    }

    if (accion === "promover") {
      // Convierte a un integrante en encargada (supervisor_sede) de su sede.
      const { data: p } = await admin.from("personas").select("id, rol").eq("id", personaId).maybeSingle();
      if (!p) return NextResponse.json({ error: "persona no encontrada" }, { status: 404 });
      if (!puedeActuarSobre(yo.rol, p.rol)) {
        return NextResponse.json({ error: "no puedes cambiar el rol de esa persona" }, { status: 403 });
      }
      // El rol del objetivo se leía y no se usaba, así que "promover" servía
      // igual para DEGRADAR: con el id de un admin lo dejaba como encargada.
      // Esta acción solo sube a un integrante; cualquier otro cambio de rol es
      // otra operación y necesita su propia puerta.
      if (p.rol !== "integrante") {
        return NextResponse.json({ error: "solo se promueve a un integrante" }, { status: 409 });
      }
      // El rol NO se escribe desde acá con la llave de servicio. Dos razones, y
      // la segunda es la que importa:
      //
      //   1. Desde la 0296 un `update` directo de `personas.rol` lo aborta un
      //      trigger salvo que quien escriba sea `postgres`. La llave de
      //      servicio es `service_role`, no `postgres`: medido contra la base,
      //      este update devolvía «El rol se cambia con fn_set_rol, no con un
      //      update directo».
      //   2. Escribiendo por acá el cambio de rol no dejaba NINGUNA fila en
      //      `correcciones_auditoria`. `fn_set_rol` (0295) la inserta siempre —
      //      un cambio que puede dar acceso a todos los sueldos y al padrón
      //      completo no puede ser invisible. La llave de servicio no es nadie
      //      dentro de la base (`auth.uid()` es null), así que por ese camino
      //      no había a quién anotar.
      //
      // Por eso la llamada va con la sesión de quien pulsó el botón, que ya
      // vino validada arriba. `fn_set_rol` vuelve a comprobar los permisos por
      // su cuenta —y hace cumplir el escalafón entero, no solo lo que mira
      // `puedeActuarSobre`—, así que las dos puertas dicen lo mismo.
      const comoYo = createUserClient(token);
      if (!comoYo) return NextResponse.json({ error: "servidor sin configurar" }, { status: 500 });
      const { error } = await comoYo.rpc("fn_set_rol", {
        p_persona_id: personaId,
        p_nuevo_rol: "supervisor_sede",
      });
      if (error) {
        Sentry.captureException(error);
        return NextResponse.json({ error: mensajeDeError(error, "promover a esa persona") }, { status: 500 });
      }
      return NextResponse.json({ ok: true });
    }

    if (accion === "resetear") {
      const { data: p } = await admin.from("personas").select("auth_user_id, rol").eq("id", personaId).maybeSingle();
      if (!p) return NextResponse.json({ error: "persona no encontrada" }, { status: 404 });
      if (!puedeActuarSobre(yo.rol, p.rol)) {
        return NextResponse.json({ error: "no puedes resetear la contraseña de esa persona" }, { status: 403 });
      }
      if (!p.auth_user_id) return NextResponse.json({ error: "esa persona no tiene cuenta" }, { status: 409 });
      const nueva = generarClave();
      const { error } = await admin.auth.admin.updateUserById(p.auth_user_id, {
        password: nueva,
        app_metadata: CLAVE_TEMPORAL,
      });
      if (error) {
        Sentry.captureException(error);
        return NextResponse.json({ error: mensajeDeAuth(error) }, { status: 500 });
      }
      return NextResponse.json({ password: nueva });
    }

    if (accion === "crear") {
      if (!email || !String(email).includes("@")) return NextResponse.json({ error: "correo inválido" }, { status: 400 });
      const { data: p } = await admin.from("personas").select("id, auth_user_id, rol").eq("id", personaId).maybeSingle();
      if (!p) return NextResponse.json({ error: "persona no encontrada" }, { status: 404 });
      // Crear la cuenta de alguien es elegir con qué correo entra: sin esta
      // comprobación, un líder DO podía darle al admin que aún no tiene cuenta
      // un correo suyo y entrar como admin.
      if (!puedeActuarSobre(yo.rol, p.rol)) {
        return NextResponse.json({ error: "no puedes crear la cuenta de esa persona" }, { status: 403 });
      }
      if (p.auth_user_id) return NextResponse.json({ error: "esa persona ya tiene cuenta" }, { status: 409 });
      const nueva = generarClave();
      // Se normaliza igual que en `fn_set_email`: el login no distingue
      // mayúsculas, y así la ficha y el acceso guardan exactamente el mismo texto.
      const correo = String(email).trim().toLowerCase();
      const { data: authData, error } = await admin.auth.admin.createUser({
        email: correo, password: nueva, email_confirm: true, app_metadata: CLAVE_TEMPORAL,
      });
      if (error) {
        Sentry.captureException(error);
        return NextResponse.json({ error: mensajeDeAuth(error) }, { status: 500 });
      }
      // El correo se copia A LA FICHA, no solo a la cuenta. Sin esto —así estuvo
      // hasta el 2026-08-13— la persona quedaba con acceso pero con
      // `personas.email` vacío, y el candado de la 0198 hacía el resto: la ficha
      // rechaza cambiar el correo de quien ya tiene cuenta, así que ese hueco no
      // se podía llenar nunca más desde el panel.
      const { error: e2 } = await admin
        .from("personas")
        .update({ auth_user_id: authData.user.id, email: correo })
        .eq("id", personaId);
      if (e2) {
        Sentry.captureException(e2);
        return NextResponse.json({ error: mensajeDeError(e2, "enlazar la cuenta con su ficha") }, { status: 500 });
      }
      return NextResponse.json({ password: nueva, email: correo });
    }

    // El destino al que apunta el error de la 0198. Existe desde el 2026-08-13:
    // hasta entonces la ficha decía «hazlo desde Cuentas» y acá solo se podía
    // resetear la contraseña, así que el correo de quien ya entraba al sistema
    // no se podía corregir desde ninguna pantalla del panel. Un error que manda
    // a un sitio donde la cosa no está enseña a no creerle a los errores.
    //
    // Va por acá y no por `fn_set_email` a propósito: cambiar el correo son DOS
    // escrituras —la cuenta de acceso y la ficha— y la base no puede tocar Auth.
    // Ese es justamente el motivo por el que la 0198 se lo prohíbe a la ficha.
    if (accion === "cambiar-correo") {
      const correo = String(email ?? "").trim().toLowerCase();
      if (!correo.includes("@")) return NextResponse.json({ error: "correo inválido" }, { status: 400 });
      const { data: p } = await admin
        .from("personas")
        .select("id, auth_user_id, rol, email, nombres")
        .eq("id", personaId)
        .maybeSingle();
      if (!p) return NextResponse.json({ error: "persona no encontrada" }, { status: 404 });
      // Mismo criterio que en `crear`: elegir con qué correo entra alguien es
      // elegir quién puede entrar como esa persona.
      if (!puedeActuarSobre(yo.rol, p.rol)) {
        return NextResponse.json({ error: "no puedes cambiar el correo de esa persona" }, { status: 403 });
      }
      if (!p.auth_user_id) {
        return NextResponse.json(
          { error: `${p.nombres} todavía no tiene cuenta: su correo se pone desde Datos personales.` },
          { status: 409 },
        );
      }

      // `email_confirm: true` deja el correo nuevo válido de inmediato. Sin eso
      // Supabase manda un correo de confirmación y mantiene el ANTERIOR como
      // usuario hasta que alguien haga clic: si el correo viejo estaba mal
      // escrito —que es el caso por el que se llega acá— ese clic no llega nunca
      // y la persona se queda sin poder entrar con ninguno de los dos.
      const { error } = await admin.auth.admin.updateUserById(p.auth_user_id, {
        email: correo,
        email_confirm: true,
      });
      if (error) {
        Sentry.captureException(error);
        return NextResponse.json({ error: mensajeDeAuth(error) }, { status: 500 });
      }

      // El acceso ya cambió. Si esta segunda escritura falla queda el estado que
      // la 0198 quiere hacer imposible —un correo en la ficha y otro en el
      // login—, así que el mensaje dice exactamente qué pasó en vez de un «no se
      // pudo» que dejaría a quien lo lee sin saber con cuál entra la persona.
      // Repetir la acción lo arregla: los dos pasos son idempotentes.
      const { error: e2 } = await admin.from("personas").update({ email: correo }).eq("id", personaId);
      if (e2) {
        Sentry.captureException(e2);
        return NextResponse.json(
          { error: `${p.nombres} YA entra con ${correo}, pero su ficha quedó con el correo anterior. Vuelve a darle a Cambiar correo con el mismo para emparejarlos.` },
          { status: 500 },
        );
      }
      return NextResponse.json({ ok: true, email: correo, anterior: p.email ?? null });
    }

    return NextResponse.json({ error: "acción no válida" }, { status: 400 });
  } catch (e) {
    // Lo que llegue acá es inesperado por definición: no pasó por ninguna de las
    // ramas de arriba. El detalle va al registro; a la pantalla, algo legible.
    Sentry.captureException(e);
    return NextResponse.json(
      { error: "El sistema no pudo completar la operación. Vuelve a intentarlo; si sigue igual, avisa a Felipe." },
      { status: 500 },
    );
  }
}

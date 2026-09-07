"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { CargandoFila, SinDatos } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { Tabla } from "@/components/ui/tabla";
import { useToast } from "@/components/toast";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { guardarMiClave } from "@/lib/admin/mi-clave";
import { REQUISITOS_CLAVE, problemasDeClave, puedeGestionarCatalogos } from "@cayla-dynamic/shared";

interface Cuenta {
  id: string;
  nombre: string;
  rol: string;
  sede: string;
  email: string | null;
  tieneCuenta: boolean;
}

interface Promovible {
  id: string;
  nombre: string;
  sede: string;
}

interface Invitable {
  id: string;
  nombre: string;
  sede: string;
  email: string | null;
}

interface Pendiente {
  id: string;
  nombre: string;
  rol: string;
  sede: string;
  email: string | null;
  confirmado: boolean;
}

// UNA LISTA QUE NO SE PUDO CARGAR NO SE PINTA COMO UNA LISTA VACÍA.
//
// En esta pantalla el vacío es una buena noticia («todas las cuentas creadas
// están en uso», «cualquiera puede dejar su constancia»), así que un 403 o una
// sesión vencida se leían como tranquilidad — y sobre esa lectura se crean
// cuentas duplicadas. Cada bloque tiene sus tres estados con tres textos:
// cargando, no se pudo cargar, y vacío de verdad.
//
// Y el motivo se dice acá mismo. Estos bloques viven al final de una pantalla
// larga, lejos del aviso persistente de arriba que sí lo lleva: obligar a subir
// a buscar el porqué es la misma distancia que hace que un aviso no se lea.
function ListaNoCargada({ que, motivo, noSignifica, reintentar }: { que: string; motivo: string; noSignifica: string; reintentar: () => void }) {
  return (
    <div className="rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
      <p>No se pudo cargar {que}: {motivo}</p>
      <p className="mt-1">
        Esto <strong>no</strong> quiere decir que {noSignifica}.{" "}
        <button onClick={reintentar} className="font-medium underline">Reintentar</button>
      </p>
    </div>
  );
}

const ROL_LABEL: Record<string, string> = {
  admin: "Admin",
  lider_do: "Líder DO",
  supervisor_sede: "Encargada",
};

export default function CuentasPage() {
  const router = useRouter();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const esAdmin = puedeGestionarCatalogos(rol);

  const { avisar } = useToast();

  // cambiar mi contraseña
  const [nueva, setNueva] = useState("");
  const [confirma, setConfirma] = useState("");
  const [guardandoMia, setGuardandoMia] = useState(false);
  // El correo con el que entra quien está mirando. Entra en el juicio de la
  // clave: `felipe@…` con clave `Felipe2026x` no es una clave, es el nombre de
  // la puerta escrito en la llave.
  const [correoPropio, setCorreoPropio] = useState<string | null>(null);

  // gestión de cuentas
  const [cuentas, setCuentas] = useState<Cuenta[]>([]);
  const [promovibles, setPromovibles] = useState<Promovible[]>([]);
  const [invitables, setInvitables] = useState<Invitable[]>([]);
  const [pendientes, setPendientes] = useState<Pendiente[]>([]);
  // Arranca en «cargando» y no en «vacío»: hasta que la primera consulta
  // conteste, la pantalla no sabe nada — y pintar las listas vacías mientras
  // tanto es la misma buena noticia falsa que este arreglo persigue.
  const [cargando, setCargando] = useState(true);
  const [emailNuevo, setEmailNuevo] = useState<Record<string, string>>({});
  // Qué fila tiene abierto el formulario de «cambiar correo». Va cerrado por
  // defecto: es la acción que más daño hace por accidente de esta tabla —el
  // correo ES el usuario con el que se entra— y no debe estar a un clic de
  // distancia junto a las demás.
  const [cambiando, setCambiando] = useState<string | null>(null);
  const [claveGenerada, setClaveGenerada] = useState<Record<string, string>>({});
  const [procesando, setProcesando] = useState<string | null>(null);
  const [tanda, setTanda] = useState(false);
  // Se queda local a propósito, sin pasar al toast global: `enTanda` la reusa
  // como progreso en vivo ("Enviando 3 de 10…"), actualizándola en cada vuelta
  // del lote. Un toast por vuelta sería una fila de avisos apilándose y
  // apagándose solos — acá hace falta un estado que se pise a sí mismo.
  const [msgGestion, setMsgGestion] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  // El fallo del LISTADO va aparte de `msgGestion` y no se borra con la
  // siguiente acción: mientras la lista no se pueda cargar, la pantalla tiene
  // que seguir diciéndolo. Un listado que falla se veía igual que uno vacío
  // —«nadie tiene cuenta todavía»— y sobre esa lectura se crean cuentas
  // duplicadas.
  const [errListado, setErrListado] = useState<string | null>(null);

  const token = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data } = await supabase.auth.getSession();
    return data.session?.access_token ?? "";
  }, []);

  // De acá nunca puede salir una respuesta que PAREZCA correcta sin serlo: quien
  // llama solo mira `data.error`, así que un 401/403/500 sin cuerpo, o una
  // respuesta que ni siquiera es JSON, tienen que salir con ese campo puesto.
  // Antes se devolvía `res.json()` a secas y un fallo llegaba como `{}`.
  const pedir = useCallback(
    async (body: Record<string, unknown>) => {
      try {
        const res = await fetch("/api/admin/cuentas", {
          method: "POST",
          headers: { "Content-Type": "application/json", Authorization: `Bearer ${await token()}` },
          body: JSON.stringify(body),
        });
        // Una respuesta que ni siquiera es JSON —el HTML de un proxy de acceso,
        // una página de error servida con 200— se tragaba en el `catch` y salía
        // como `{}`: sin `error`, o sea indistinguible de «no hay nadie». Se
        // recuerda el fallo de lectura y se trata como error pase lo que pase
        // con el estado, porque un 200 ilegible es justo el caso que engaña.
        let seLeyo = true;
        const data = await res.json().catch(() => { seLeyo = false; return {}; });
        if (!seLeyo) {
          return { error: "El servidor respondió algo que el panel no pudo leer. Vuelve a entrar y reinténtalo." };
        }
        // El 401 se mira ANTES de deferir al cuerpo: la ruta SIEMPRE manda
        // `{error:"sin sesión"}` o `{error:"sesión inválida"}`, así que el caso
        // más probable de fallo acá llegaba en jerga y sin decir qué hacer. El
        // texto es el mismo que `mensaje-error.ts` ya eligió para PGRST301.
        if (res.status === 401) return { error: "Tu sesión venció. Vuelve a entrar." };
        if (!res.ok && !data?.error) {
          return { error: `El servidor respondió ${res.status}. Vuelve a intentarlo; si sigue igual, avisa a Felipe.` };
        }
        return data;
      } catch {
        return { error: "No se pudo contactar al servidor. Revisa tu conexión y vuelve a intentarlo." };
      }
    },
    [token],
  );

  const listar = useCallback(async () => {
    setCargando(true);
    const data = await pedir({ accion: "listar" });
    // Se revisa igual que el resto de acciones de esta pantalla. Sin esto, una
    // sesión vencida, un 403 o un 500 dejaban las cuatro listas en cero y la
    // pantalla se leía como «no hay nadie», que acá es una buena noticia falsa.
    if (data.error) {
      setErrListado(String(data.error));
      setCargando(false);
      return;
    }
    setErrListado(null);
    setCuentas(data.cuentas ?? []);
    setPromovibles(data.promovibles ?? []);
    setInvitables(data.invitables ?? []);
    setPendientes(data.pendientes ?? []);
    setCargando(false);
  }, [pedir]);

  useEffect(() => {
    const supabase = createAdminSupabaseClient();
    supabase.auth.getSession().then(({ data }) => {
      if (!data.session) { router.replace("/admin/login"); return; }
      setCorreoPropio(data.session.user.email ?? null);
      if (esAdmin) void listar();
    });
  }, [router, esAdmin, listar]);

  async function cambiarMiClave() {
    // Una sola política, un solo sitio (`packages/shared/src/clave.ts`). Acá
    // había escrito a mano «al menos 6 caracteres», igual que en la pantalla de
    // nueva clave y que en la configuración de Supabase: tres copias del mismo
    // número, y ninguna sabía de las otras.
    const problemas = problemasDeClave(nueva, correoPropio);
    if (problemas.length > 0) { avisar("error", problemas.join(" ")); return; }
    if (nueva !== confirma) { avisar("error", "Las contraseñas no coinciden."); return; }
    setGuardandoMia(true);
    const problema = await guardarMiClave(nueva);
    setGuardandoMia(false);
    if (problema) { avisar("error", problema); return; }
    setNueva(""); setConfirma("");
    avisar("ok", "Tu contraseña se cambió correctamente.");
  }

  async function promover(p: Promovible) {
    setProcesando(p.id); setMsgGestion(null);
    const data = await pedir({ accion: "promover", personaId: p.id });
    setProcesando(null);
    if (data.error) { setMsgGestion({ tipo: "error", texto: `${p.nombre}: ${data.error}` }); return; }
    setMsgGestion({ tipo: "ok", texto: `${p.nombre} ahora es encargada de ${p.sede}. Ya puedes crearle su cuenta abajo.` });
    void listar();
  }

  async function invitar(p: Invitable) {
    setProcesando(p.id); setMsgGestion(null);
    const data = await pedir({ accion: "invitar", personaId: p.id });
    setProcesando(null);
    if (data.error) { setMsgGestion({ tipo: "error", texto: `${p.nombre}: ${data.error}` }); return; }
    setMsgGestion({ tipo: "ok", texto: `Invitación enviada a ${data.invitado}. ${p.nombre} recibirá un correo para poner su propia clave.` });
    void listar();
  }

  async function reinvitar(p: Pendiente) {
    setProcesando(p.id); setMsgGestion(null);
    const data = await pedir({ accion: "reinvitar", personaId: p.id });
    setProcesando(null);
    if (data.error) { setMsgGestion({ tipo: "error", texto: `${p.nombre}: ${data.error}` }); return; }
    setMsgGestion({
      tipo: "ok",
      texto: data.tipo === "recuperacion"
        ? `Enlace enviado a ${data.enviado}. ${p.nombre} ya tenía clave, así que le llega el correo de «recuperar acceso» para poner la suya.`
        : `Invitación reenviada a ${data.enviado}.`,
    });
    void listar();
  }

  // Envío en tanda. Va de a una y con una pausa entre correos porque el
  // proyecto tiene un tope por hora: mandarlos todos a la vez no llega antes y
  // convierte un tope en veinte errores. Si el tope salta, se corta ahí mismo —
  // seguir intentando solo suma fallos y borra de la vista quién sí recibió.
  async function enTanda(gente: { id: string; nombre: string }[], accion: "invitar" | "reinvitar") {
    setTanda(true); setMsgGestion(null);
    const hechas: string[] = [];
    const fallos: string[] = [];
    let tope = false;
    for (const p of gente) {
      setProcesando(p.id);
      setMsgGestion({ tipo: "ok", texto: `Enviando ${hechas.length + fallos.length + 1} de ${gente.length}: ${p.nombre}…` });
      const data = await pedir({ accion, personaId: p.id });
      if (data.error) {
        fallos.push(`${p.nombre} — ${data.error}`);
        if (String(data.error).includes("tope de correos")) { tope = true; break; }
      } else {
        hechas.push(p.nombre);
      }
      await new Promise((r) => setTimeout(r, 700));
    }
    setProcesando(null); setTanda(false);
    const resumen = [
      `Enviados: ${hechas.length} de ${gente.length}.`,
      fallos.length ? `Sin enviar (${fallos.length}): ${fallos.join(" · ")}` : "",
      tope ? "Se cortó al llegar al tope por hora — vuelve a darle en un rato y sigue por donde quedó." : "",
    ].filter(Boolean).join(" ");
    setMsgGestion({ tipo: fallos.length ? "error" : "ok", texto: resumen });
    void listar();
  }

  async function accion(c: Cuenta, tipo: "resetear" | "crear" | "cambiar-correo") {
    setProcesando(c.id); setMsgGestion(null);
    const body: Record<string, unknown> = { accion: tipo, personaId: c.id };
    if (tipo !== "resetear") body.email = emailNuevo[c.id]?.trim();
    const data = await pedir(body);
    setProcesando(null);
    if (data.error) { setMsgGestion({ tipo: "error", texto: `${c.nombre}: ${data.error}` }); return; }
    // Cambiar el correo no devuelve contraseña: no la toca. Decirlo es la mitad
    // del mensaje — quien acaba de cambiarle el correo a alguien necesita saber
    // si además tiene que pasarle una clave nueva.
    if (tipo === "cambiar-correo") {
      setCambiando(null);
      setEmailNuevo((m) => ({ ...m, [c.id]: "" }));
      setMsgGestion({ tipo: "ok", texto: `${c.nombre} ahora entra con ${data.email}. Su contraseña no cambió: avísale del correo nuevo, nada más.` });
      void listar();
      return;
    }
    setClaveGenerada((m) => ({ ...m, [c.id]: data.password }));
    if (tipo === "crear") void listar();
  }

  if (rol !== null && !esAdmin) {
    return (
      <div className="flex flex-1 flex-col">
        <main className="flex-1 p-6">
          <h1 className="mb-1 font-serif text-2xl">Mi cuenta</h1>
          <SeccionMiClave {...{ nueva, setNueva, confirma, setConfirma, guardandoMia, cambiarMiClave }} />
        </main>
      </div>
    );
  }

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        <h1 className="mb-1 font-serif text-2xl">Cuentas</h1>
        <p className="mb-6 text-sm text-taupe">Cambia tu contraseña y gestiona los accesos del equipo al panel.</p>

        <SeccionMiClave {...{ nueva, setNueva, confirma, setConfirma, guardandoMia, cambiarMiClave }} />

        <h2 className="mb-3 mt-8 font-serif text-lg">Gestionar cuentas del equipo</h2>
        {/* Persistente a propósito: no es un aviso que se va solo. Mientras la
            lista no cargue, todo lo que se ve debajo puede estar incompleto. */}
        {errListado && (
          <div className="mb-3 rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
            <p>No se pudo cargar la lista de cuentas: {errListado}</p>
            <p className="mt-1">
              Lo que se ve debajo puede estar incompleto o desactualizado — no lo leas como «así están las cuentas hoy».{" "}
              <button onClick={() => void listar()} className="font-medium underline">Reintentar</button>
            </p>
          </div>
        )}
        {msgGestion && (
          <p className={`mb-3 text-sm ${msgGestion.tipo === "ok" ? "text-verde" : "text-rojo"}`}>{msgGestion.texto}</p>
        )}
        <Tabla>
          <thead className="bg-sand/70 text-left">
            <tr className="etiqueta text-taupe">
              <th className="px-4 py-2.5 font-medium">Persona</th>
              <th className="px-4 py-2.5 font-medium">Rol</th>
              <th className="px-4 py-2.5 font-medium">Sede</th>
              <th className="px-4 py-2.5 font-medium">Correo / acceso</th>
              <th className="px-4 py-2.5 font-medium">Acción</th>
            </tr>
          </thead>
          <tbody>
              {cargando ? (
                <CargandoFila columnas={5} />
              ) : errListado && cuentas.length === 0 ? (
                <tr className="border-t border-sand">
                  <td colSpan={5} className="px-4 py-6 text-center text-sm text-rojo">
                    No se pudo cargar la lista. Esto <strong>no</strong> quiere decir que nadie tenga cuenta.
                  </td>
                </tr>
              ) : (
                cuentas.map((c) => (
                  <tr key={c.id} className="border-t border-sand align-top">
                    <td className="px-4 py-3">{c.nombre}</td>
                    <td className="px-4 py-3 text-taupe">{ROL_LABEL[c.rol] ?? c.rol}</td>
                    <td className="px-4 py-3 text-taupe">{c.sede}</td>
                    <td className="px-4 py-3">
                      {c.tieneCuenta ? (
                        <span className="text-tinta">{c.email}</span>
                      ) : (
                        <span className="text-rojo">sin cuenta</span>
                      )}
                      {claveGenerada[c.id] && (
                        <div className="mt-1 rounded bg-sand/60 px-2 py-1 text-xs">
                          Nueva contraseña <strong>temporal</strong>:{" "}
                          <span className="font-medium text-tinta">{claveGenerada[c.id]}</span> — cópiala y pásasela.
                          El sistema le va a pedir que elija la suya al entrar, así que ésta deja de servir
                          en cuanto lo haga.
                        </div>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      {c.tieneCuenta ? (
                        <div className="flex flex-col gap-2">
                          <div className="flex flex-wrap gap-2">
                            <Boton
                              variante="secundario"
                              onClick={() => accion(c, "resetear")}
                              disabled={procesando === c.id}
                            >
                              {procesando === c.id ? "…" : "Resetear contraseña"}
                            </Boton>
                            <Boton
                              variante="secundario"
                              className="text-taupe"
                              onClick={() => {
                                setCambiando((x) => (x === c.id ? null : c.id));
                                setEmailNuevo((m) => ({ ...m, [c.id]: m[c.id] ?? c.email ?? "" }));
                              }}
                            >
                              {cambiando === c.id ? "Cancelar" : "Cambiar correo"}
                            </Boton>
                          </div>
                          {cambiando === c.id && (
                            <div className="flex flex-wrap items-center gap-2 rounded-lg bg-sand/40 p-2">
                              <input
                                type="email"
                                placeholder="correo@gmail.com"
                                value={emailNuevo[c.id] ?? ""}
                                onChange={(e) => setEmailNuevo((m) => ({ ...m, [c.id]: e.target.value }))}
                                className="rounded-lg border border-sand bg-crema px-2 py-1.5 text-sm"
                              />
                              <Boton
                                variante="primario"
                                onClick={() => accion(c, "cambiar-correo")}
                                disabled={
                                  procesando === c.id ||
                                  !emailNuevo[c.id]?.includes("@") ||
                                  emailNuevo[c.id]?.trim().toLowerCase() === (c.email ?? "").toLowerCase()
                                }
                              >
                                {procesando === c.id ? "…" : "Guardar correo"}
                              </Boton>
                              {/* Lo que de verdad hay que entender antes de darle:
                                  desde ese momento el correo viejo ya no sirve
                                  para entrar, y la contraseña sigue siendo la
                                  misma. Se cambia en la cuenta y en la ficha a la
                                  vez — la ficha sola no cambiaría el acceso, que
                                  es lo que la 0198 impide. */}
                              <span className="w-full text-xs text-taupe">
                                Pasa a ser su usuario para entrar; con el anterior ya no podrá.
                                Su contraseña no cambia. Se actualiza también en su ficha.
                              </span>
                            </div>
                          )}
                        </div>
                      ) : (
                        <div className="flex flex-wrap items-center gap-2">
                          <input
                            type="email"
                            placeholder="correo@gmail.com"
                            value={emailNuevo[c.id] ?? ""}
                            onChange={(e) => setEmailNuevo((m) => ({ ...m, [c.id]: e.target.value }))}
                            className="rounded-lg border border-sand bg-crema px-2 py-1.5 text-sm"
                          />
                          <Boton
                            variante="primario"
                            onClick={() => accion(c, "crear")}
                            disabled={procesando === c.id || !emailNuevo[c.id]}
                          >
                            {procesando === c.id ? "…" : "Crear cuenta"}
                          </Boton>
                        </div>
                      )}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
        </Tabla>

        <h2 className="mb-1 mt-8 font-serif text-lg">Invitar para que dejen constancia</h2>
        <p className="mb-3 text-sm text-taupe">
          La Ley 30709 obliga a informar la política salarial a cada persona y a poder probarlo. Para dejar
          su constancia necesitan entrar con su propia cuenta. Al invitarles reciben un correo y{" "}
          <strong>eligen su clave por su cuenta</strong> — nadie más la conoce. No ven planilla, ni sueldos, ni
          datos de nadie: su menú solo muestra lo que les corresponde.
        </p>
        {cargando ? (
          <p className="text-sm text-taupe">Cargando…</p>
        ) : errListado && invitables.length === 0 ? (
          <ListaNoCargada que="a quién falta invitar" motivo={errListado} noSignifica="no quede nadie por invitar" reintentar={() => void listar()} />
        ) : invitables.length === 0 ? (
          <SinDatos texto="No hay integrantes por invitar." pista="Acá aparece quien está en planilla y todavía no tiene cuenta. Si está vacío, cualquiera puede dejar su constancia." />
        ) : (
          <div className="flex flex-wrap gap-2">
            {invitables.some((p) => p.email) && (
              <Boton
                variante="primario"
                onClick={() => enTanda(invitables.filter((p) => p.email), "invitar")}
                disabled={tanda || procesando !== null}
              >
                {tanda ? "Enviando…" : `Invitar a todas (${invitables.filter((p) => p.email).length})`}
              </Boton>
            )}
            {invitables.map((p) => (
              <div key={p.id} className="flex items-center gap-3 rounded-lg border border-sand bg-sand/25 px-3 py-2">
                <span className="text-sm text-tinta">
                  {p.nombre} <span className="text-taupe">· {p.sede}</span>
                  {p.email ? (
                    <span className="block text-xs text-taupe">{p.email}</span>
                  ) : (
                    <span className="block text-xs text-ambar">sin correo — agrégalo en Datos personales</span>
                  )}
                </span>
                <Boton
                  variante="secundario"
                  onClick={() => invitar(p)}
                  disabled={procesando === p.id || !p.email || tanda}
                >
                  {procesando === p.id ? "…" : "Invitar"}
                </Boton>
              </div>
            ))}
          </div>
        )}

        <h2 className="mb-1 mt-8 font-serif text-lg">Volver a invitar — todavía no han entrado</h2>
        <p className="mb-3 text-sm text-taupe">
          Tienen cuenta creada pero <strong>nunca han iniciado sesión</strong>: el correo se perdió, llegó a spam
          o quedó pendiente. A quien fue invitada le llega otra vez la invitación; a quien ya tenía clave le llega
          el enlace de «recuperar acceso» para poner la suya. Van de a una, con una pausa entre correos, porque el
          proyecto tiene un tope por hora.
        </p>
        {cargando ? (
          <p className="text-sm text-taupe">Cargando…</p>
        ) : errListado && pendientes.length === 0 ? (
          <ListaNoCargada que="quién tiene el acceso a medias" motivo={errListado} noSignifica="nadie haya quedado a medias" reintentar={() => void listar()} />
        ) : pendientes.length === 0 ? (
          <SinDatos texto="Nadie quedó a medias." pista="Acá aparece quien tiene cuenta y nunca entró. Si está vacío, todas las cuentas creadas están en uso." />
        ) : (
          <div className="flex flex-wrap gap-2">
            {pendientes.some((p) => p.email) && (
              <Boton
                variante="primario"
                onClick={() => enTanda(pendientes.filter((p) => p.email), "reinvitar")}
                disabled={tanda || procesando !== null}
              >
                {tanda ? "Enviando…" : `Reenviar a todas (${pendientes.filter((p) => p.email).length})`}
              </Boton>
            )}
            {pendientes.map((p) => (
              <div key={p.id} className="flex items-center gap-3 rounded-lg border border-sand bg-sand/25 px-3 py-2">
                <span className="text-sm text-tinta">
                  {p.nombre} <span className="text-taupe">· {p.sede} · {ROL_LABEL[p.rol] ?? p.rol}</span>
                  {p.email ? (
                    <span className="block text-xs text-taupe">
                      {p.email} · {p.confirmado ? "le llega «recuperar acceso»" : "le llega la invitación"}
                    </span>
                  ) : (
                    <span className="block text-xs text-ambar">su cuenta no tiene correo</span>
                  )}
                </span>
                <Boton
                  variante="secundario"
                  onClick={() => reinvitar(p)}
                  disabled={procesando === p.id || !p.email || tanda}
                >
                  {procesando === p.id ? "…" : "Reenviar"}
                </Boton>
              </div>
            ))}
          </div>
        )}

        <h2 className="mb-1 mt-8 font-serif text-lg">Convertir en encargada</h2>
        <p className="mb-3 text-sm text-taupe">
          Da acceso al panel de su sede a una integrante. Al convertirla, aparece arriba para crearle su cuenta.
        </p>
        {cargando ? (
          <p className="text-sm text-taupe">Cargando…</p>
        ) : errListado && promovibles.length === 0 ? (
          <ListaNoCargada que="a quién se puede convertir en encargada" motivo={errListado} noSignifica="no haya a quién convertir" reintentar={() => void listar()} />
        ) : promovibles.length === 0 ? (
          <SinDatos texto="No hay integrantes por promover." pista="Acá aparece quien todavía no tiene cuenta de acceso al panel. Si está vacío, es que todas las personas con rol de encargada o líder ya tienen la suya." />
        ) : (
          <div className="flex flex-wrap gap-2">
            {promovibles.map((p) => (
              <div key={p.id} className="flex items-center gap-3 rounded-lg border border-sand bg-sand/25 px-3 py-2">
                <span className="text-sm text-tinta">
                  {p.nombre} <span className="text-taupe">· {p.sede}</span>
                </span>
                <Boton
                  variante="secundario"
                  onClick={() => promover(p)}
                  disabled={procesando === p.id}
                >
                  {procesando === p.id ? "…" : "Hacer encargada"}
                </Boton>
              </div>
            ))}
          </div>
        )}
      </main>
    </div>
  );
}

function SeccionMiClave({
  nueva, setNueva, confirma, setConfirma, guardandoMia, cambiarMiClave,
}: {
  nueva: string; setNueva: (s: string) => void;
  confirma: string; setConfirma: (s: string) => void;
  guardandoMia: boolean; cambiarMiClave: () => void;
}) {
  return (
    <div className="max-w-md rounded-lg border border-sand bg-sand/25 p-5">
      <h2 className="mb-3 font-serif text-lg">Cambiar mi contraseña</h2>
      <div className="flex flex-col gap-3">
        <input type="password" placeholder="Nueva contraseña" value={nueva} onChange={(e) => setNueva(e.target.value)}
          className="rounded-lg border border-sand bg-crema px-3 py-2 outline-none focus:border-taupe" />
        <input type="password" placeholder="Repite la nueva contraseña" value={confirma} onChange={(e) => setConfirma(e.target.value)}
          className="rounded-lg border border-sand bg-crema px-3 py-2 outline-none focus:border-taupe" />
        {/* Los requisitos antes de escribir, no después de fallar. */}
        <ul className="flex flex-col gap-0.5 text-xs text-taupe">
          {REQUISITOS_CLAVE.map((r) => <li key={r}>· {r}</li>)}
        </ul>
        <Boton variante="primario" className="self-start" onClick={cambiarMiClave} disabled={guardandoMia}>
          {guardandoMia ? "Guardando…" : "Cambiar contraseña"}
        </Boton>
      </div>
    </div>
  );
}

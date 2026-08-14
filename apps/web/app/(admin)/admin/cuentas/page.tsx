"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { AdminNav } from "../nav";
import { CargandoFila, SinDatos } from "@/components/cargando";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { puedeGestionarCatalogos } from "@cayla-dynamic/shared";

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

  // cambiar mi contraseña
  const [nueva, setNueva] = useState("");
  const [confirma, setConfirma] = useState("");
  const [msgMia, setMsgMia] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  const [guardandoMia, setGuardandoMia] = useState(false);

  // gestión de cuentas
  const [cuentas, setCuentas] = useState<Cuenta[]>([]);
  const [promovibles, setPromovibles] = useState<Promovible[]>([]);
  const [invitables, setInvitables] = useState<Invitable[]>([]);
  const [pendientes, setPendientes] = useState<Pendiente[]>([]);
  const [cargando, setCargando] = useState(false);
  const [emailNuevo, setEmailNuevo] = useState<Record<string, string>>({});
  const [claveGenerada, setClaveGenerada] = useState<Record<string, string>>({});
  const [procesando, setProcesando] = useState<string | null>(null);
  const [tanda, setTanda] = useState(false);
  const [msgGestion, setMsgGestion] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);

  const token = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data } = await supabase.auth.getSession();
    return data.session?.access_token ?? "";
  }, []);

  const pedir = useCallback(
    async (body: Record<string, unknown>) => {
      const res = await fetch("/api/admin/cuentas", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${await token()}` },
        body: JSON.stringify(body),
      });
      return res.json();
    },
    [token],
  );

  const listar = useCallback(async () => {
    setCargando(true);
    const data = await pedir({ accion: "listar" });
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
      if (esAdmin) void listar();
    });
  }, [router, esAdmin, listar]);

  async function cambiarMiClave() {
    setMsgMia(null);
    if (nueva.length < 6) { setMsgMia({ tipo: "error", texto: "La contraseña debe tener al menos 6 caracteres." }); return; }
    if (nueva !== confirma) { setMsgMia({ tipo: "error", texto: "Las contraseñas no coinciden." }); return; }
    setGuardandoMia(true);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.auth.updateUser({ password: nueva });
    setGuardandoMia(false);
    if (error) { setMsgMia({ tipo: "error", texto: mensajeDeError(error) }); return; }
    setNueva(""); setConfirma("");
    setMsgMia({ tipo: "ok", texto: "Tu contraseña se cambió correctamente." });
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

  async function accion(c: Cuenta, tipo: "resetear" | "crear") {
    setProcesando(c.id); setMsgGestion(null);
    const body: Record<string, unknown> = { accion: tipo, personaId: c.id };
    if (tipo === "crear") body.email = emailNuevo[c.id]?.trim();
    const data = await pedir(body);
    setProcesando(null);
    if (data.error) { setMsgGestion({ tipo: "error", texto: `${c.nombre}: ${data.error}` }); return; }
    setClaveGenerada((m) => ({ ...m, [c.id]: data.password }));
    if (tipo === "crear") void listar();
  }

  if (rol !== null && !esAdmin) {
    return (
      <div className="flex min-h-screen flex-col">
        <AdminNav />
        <main className="flex-1 p-6">
          <h1 className="mb-1 font-serif text-2xl">Mi cuenta</h1>
          <SeccionMiClave {...{ nueva, setNueva, confirma, setConfirma, msgMia, guardandoMia, cambiarMiClave }} />
        </main>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <h1 className="mb-1 font-serif text-2xl">Cuentas</h1>
        <p className="mb-6 text-sm text-taupe">Cambia tu contraseña y gestiona los accesos del equipo al panel.</p>

        <SeccionMiClave {...{ nueva, setNueva, confirma, setConfirma, msgMia, guardandoMia, cambiarMiClave }} />

        <h2 className="mb-3 mt-8 font-serif text-lg">Gestionar cuentas del equipo</h2>
        {msgGestion && (
          <p className={`mb-3 text-sm ${msgGestion.tipo === "ok" ? "text-verde" : "text-rojo"}`}>{msgGestion.texto}</p>
        )}
        <div className="overflow-x-auto rounded-2xl border border-sand bg-papel">
          <table className="w-full text-sm">
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
                          Nueva contraseña: <span className="font-medium text-tinta">{claveGenerada[c.id]}</span> — cópiala y pásasela.
                        </div>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      {c.tieneCuenta ? (
                        <button
                          onClick={() => accion(c, "resetear")}
                          disabled={procesando === c.id}
                          className="rounded-lg border border-sand px-3 py-1.5 text-sm text-tinta transition-colors hover:bg-sand/40 disabled:opacity-50"
                        >
                          {procesando === c.id ? "…" : "Resetear contraseña"}
                        </button>
                      ) : (
                        <div className="flex flex-wrap items-center gap-2">
                          <input
                            type="email"
                            placeholder="correo@gmail.com"
                            value={emailNuevo[c.id] ?? ""}
                            onChange={(e) => setEmailNuevo((m) => ({ ...m, [c.id]: e.target.value }))}
                            className="rounded-lg border border-sand bg-crema px-2 py-1.5 text-sm"
                          />
                          <button
                            onClick={() => accion(c, "crear")}
                            disabled={procesando === c.id || !emailNuevo[c.id]}
                            className="rounded-lg bg-tinta px-3 py-1.5 text-sm font-medium text-crema disabled:opacity-50"
                          >
                            {procesando === c.id ? "…" : "Crear cuenta"}
                          </button>
                        </div>
                      )}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>

        <h2 className="mb-1 mt-8 font-serif text-lg">Invitar para que dejen constancia</h2>
        <p className="mb-3 text-sm text-taupe">
          La Ley 30709 obliga a informar la política salarial a cada persona y a poder probarlo. Para dejar
          su constancia necesitan entrar con su propia cuenta. Al invitarlas reciben un correo y{" "}
          <strong>eligen su clave ellas mismas</strong> — nadie más la conoce. No ven planilla, ni sueldos, ni
          datos de nadie: su menú solo muestra lo que les corresponde.
        </p>
        {invitables.length === 0 ? (
          <SinDatos texto="No hay integrantes por invitar." pista="Acá aparece quien está en planilla y todavía no tiene cuenta. Si está vacío, todas pueden dejar su constancia." />
        ) : (
          <div className="flex flex-wrap gap-2">
            {invitables.some((p) => p.email) && (
              <button
                onClick={() => enTanda(invitables.filter((p) => p.email), "invitar")}
                disabled={tanda || procesando !== null}
                className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50"
              >
                {tanda ? "Enviando…" : `Invitar a todas (${invitables.filter((p) => p.email).length})`}
              </button>
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
                <button
                  onClick={() => invitar(p)}
                  disabled={procesando === p.id || !p.email || tanda}
                  className="rounded-lg border border-sand px-3 py-1 text-sm text-tinta transition-colors hover:bg-sand/40 disabled:opacity-50"
                >
                  {procesando === p.id ? "…" : "Invitar"}
                </button>
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
        {pendientes.length === 0 ? (
          <SinDatos texto="Nadie quedó a medias." pista="Acá aparece quien tiene cuenta y nunca entró. Si está vacío, todas las cuentas creadas están en uso." />
        ) : (
          <div className="flex flex-wrap gap-2">
            {pendientes.some((p) => p.email) && (
              <button
                onClick={() => enTanda(pendientes.filter((p) => p.email), "reinvitar")}
                disabled={tanda || procesando !== null}
                className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50"
              >
                {tanda ? "Enviando…" : `Reenviar a todas (${pendientes.filter((p) => p.email).length})`}
              </button>
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
                <button
                  onClick={() => reinvitar(p)}
                  disabled={procesando === p.id || !p.email || tanda}
                  className="rounded-lg border border-sand px-3 py-1 text-sm text-tinta transition-colors hover:bg-sand/40 disabled:opacity-50"
                >
                  {procesando === p.id ? "…" : "Reenviar"}
                </button>
              </div>
            ))}
          </div>
        )}

        <h2 className="mb-1 mt-8 font-serif text-lg">Convertir en encargada</h2>
        <p className="mb-3 text-sm text-taupe">
          Da acceso al panel de su sede a una integrante. Al convertirla, aparece arriba para crearle su cuenta.
        </p>
        {promovibles.length === 0 ? (
          <SinDatos texto="No hay integrantes por promover." pista="Acá aparece quien todavía no tiene cuenta de acceso al panel. Si está vacío, es que todas las personas con rol de encargada o líder ya tienen la suya." />
        ) : (
          <div className="flex flex-wrap gap-2">
            {promovibles.map((p) => (
              <div key={p.id} className="flex items-center gap-3 rounded-lg border border-sand bg-sand/25 px-3 py-2">
                <span className="text-sm text-tinta">
                  {p.nombre} <span className="text-taupe">· {p.sede}</span>
                </span>
                <button
                  onClick={() => promover(p)}
                  disabled={procesando === p.id}
                  className="rounded-lg border border-sand px-3 py-1 text-sm text-tinta transition-colors hover:bg-sand/40 disabled:opacity-50"
                >
                  {procesando === p.id ? "…" : "Hacer encargada"}
                </button>
              </div>
            ))}
          </div>
        )}
      </main>
    </div>
  );
}

function SeccionMiClave({
  nueva, setNueva, confirma, setConfirma, msgMia, guardandoMia, cambiarMiClave,
}: {
  nueva: string; setNueva: (s: string) => void;
  confirma: string; setConfirma: (s: string) => void;
  msgMia: { tipo: "ok" | "error"; texto: string } | null;
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
        {msgMia && <p className={`text-sm ${msgMia.tipo === "ok" ? "text-verde" : "text-rojo"}`}>{msgMia.texto}</p>}
        <button onClick={cambiarMiClave} disabled={guardandoMia}
          className="self-start rounded-lg bg-tinta px-5 py-2 text-sm font-medium text-crema disabled:opacity-50">
          {guardandoMia ? "Guardando…" : "Cambiar contraseña"}
        </button>
      </div>
    </div>
  );
}

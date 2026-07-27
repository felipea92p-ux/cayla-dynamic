"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { AdminNav } from "../nav";
import { CargandoFila } from "@/components/cargando";

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

const ROL_LABEL: Record<string, string> = {
  admin: "Admin",
  lider_do: "Líder DO",
  supervisor_sede: "Encargada",
};

export default function CuentasPage() {
  const router = useRouter();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const esAdmin = rol === "admin" || rol === "lider_do";

  // cambiar mi contraseña
  const [nueva, setNueva] = useState("");
  const [confirma, setConfirma] = useState("");
  const [msgMia, setMsgMia] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  const [guardandoMia, setGuardandoMia] = useState(false);

  // gestión de cuentas
  const [cuentas, setCuentas] = useState<Cuenta[]>([]);
  const [promovibles, setPromovibles] = useState<Promovible[]>([]);
  const [cargando, setCargando] = useState(false);
  const [emailNuevo, setEmailNuevo] = useState<Record<string, string>>({});
  const [claveGenerada, setClaveGenerada] = useState<Record<string, string>>({});
  const [procesando, setProcesando] = useState<string | null>(null);
  const [msgGestion, setMsgGestion] = useState<string | null>(null);

  const token = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data } = await supabase.auth.getSession();
    return data.session?.access_token ?? "";
  }, []);

  const listar = useCallback(async () => {
    setCargando(true);
    const res = await fetch("/api/admin/cuentas", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${await token()}` },
      body: JSON.stringify({ accion: "listar" }),
    });
    const data = await res.json();
    setCuentas(data.cuentas ?? []);
    setPromovibles(data.promovibles ?? []);
    setCargando(false);
  }, [token]);

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
    if (error) { setMsgMia({ tipo: "error", texto: error.message }); return; }
    setNueva(""); setConfirma("");
    setMsgMia({ tipo: "ok", texto: "Tu contraseña se cambió correctamente." });
  }

  async function promover(p: Promovible) {
    setProcesando(p.id); setMsgGestion(null);
    const res = await fetch("/api/admin/cuentas", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${await token()}` },
      body: JSON.stringify({ accion: "promover", personaId: p.id }),
    });
    const data = await res.json();
    setProcesando(null);
    if (data.error) { setMsgGestion(`${p.nombre}: ${data.error}`); return; }
    setMsgGestion(`${p.nombre} ahora es encargada de ${p.sede}. Ya puedes crearle su cuenta abajo.`);
    void listar();
  }

  async function accion(c: Cuenta, tipo: "resetear" | "crear") {
    setProcesando(c.id); setMsgGestion(null);
    const body: any = { accion: tipo, personaId: c.id };
    if (tipo === "crear") body.email = emailNuevo[c.id]?.trim();
    const res = await fetch("/api/admin/cuentas", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${await token()}` },
      body: JSON.stringify(body),
    });
    const data = await res.json();
    setProcesando(null);
    if (data.error) { setMsgGestion(`${c.nombre}: ${data.error}`); return; }
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
        {msgGestion && <p className="mb-3 text-sm text-rojo">{msgGestion}</p>}
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

        <h2 className="mb-1 mt-8 font-serif text-lg">Convertir en encargada</h2>
        <p className="mb-3 text-sm text-taupe">
          Da acceso al panel de su sede a una integrante. Al convertirla, aparece arriba para crearle su cuenta.
        </p>
        {promovibles.length === 0 ? (
          <p className="text-sm text-taupe">No hay integrantes por promover.</p>
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

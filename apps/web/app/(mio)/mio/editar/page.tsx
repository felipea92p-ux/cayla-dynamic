"use client";

import { useCallback, useEffect, useState, type FormEvent } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Cargando } from "@/components/cargando";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { Insignia } from "@/components/ui/insignia";
import {
  ESTADO_CIVIL_LABELS, ESTADOS_CIVILES, GENERO_LABELS, GENEROS,
  GRADO_INSTRUCCION_LABELS, GRADOS_INSTRUCCION,
  VINCULO_DERECHOHABIENTE_LABELS, VINCULOS_DERECHOHABIENTE,
} from "@cayla-dynamic/shared";

/**
 * «Editar mis datos» — antes vivía como una sección más dentro de la pestaña
 * «Vacaciones y permisos» de /mio, donde nadie iba a buscar «cambiar mi
 * celular». Se le dio su propia vista, mismo criterio que /mio/contrato y
 * /mio/boleta: la sesión se resuelve acá mismo (por `auth_user_id`, nunca por
 * un id que viaje en la URL), sin depender de que /mio ya la haya cargado.
 *
 * EL VALOR REAL NO CAMBIA ACÁ: se propone con `fn_crear_solicitud_perfil`, y
 * Desarrollo Organizacional lo aprueba o lo rechaza (migración 0399). Esta
 * pantalla es el formulario del pedido, no el cambio en sí.
 */

/** Una fila del catálogo de campos de perfil (migración 0399) — qué se puede
 *  pedir cambiar y si exige documento. Se lee de la tabla, nunca a mano
 *  (regla del repo: nada de listas escritas fuera de donde vive la verdad). */
interface CatalogoCampoPerfil {
  campo: string;
  etiqueta: string;
  requiere_documento: boolean;
  documento_sugerido: string | null;
  columnas: string[];
}

/** Una propuesta suya de cambio de perfil. La escribe `fn_crear_solicitud_perfil`. */
interface SolicitudPerfil {
  id: string;
  campo: string;
  valor_anterior: Record<string, unknown>;
  valor_propuesto: Record<string, unknown>;
  estado: "pendiente" | "aprobado" | "rechazado" | "reemplazada";
  creada_at: string;
  motivo: string | null;
}

function MiEditarContenido() {
  const router = useRouter();
  const supabase = createAdminSupabaseClient();

  const [yo, setYo] = useState<{ id: string } | null>(null);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [catalogoPerfil, setCatalogoPerfil] = useState<CatalogoCampoPerfil[]>([]);
  const [misSolicitudesPerfil, setMisSolicitudesPerfil] = useState<SolicitudPerfil[]>([]);
  const [campoPerfil, setCampoPerfil] = useState("celular");
  const [formPerfil, setFormPerfil] = useState<Record<string, string>>({});
  const [archivosPerfil, setArchivosPerfil] = useState<File[]>([]);
  const [enviandoPerfil, setEnviandoPerfil] = useState(false);
  const [avisoPerfil, setAvisoPerfil] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);

  const cargarSolicitudesPerfil = useCallback(async (personaId: string) => {
    const { data } = await supabase
      .from("solicitudes_cambio_perfil")
      .select("id, campo, valor_anterior, valor_propuesto, estado, creada_at, motivo")
      .eq("persona_id", personaId)      // ← explícito. La RLS es la red, no el filtro.
      .order("creada_at", { ascending: false });
    setMisSolicitudesPerfil((data as SolicitudPerfil[]) ?? []);
  }, [supabase]);

  useEffect(() => {
    let vivo = true;
    void (async () => {
      setCargando(true);
      setError(null);

      const { data: sesion } = await supabase.auth.getSession();
      if (!sesion.session) { router.replace("/mio"); return; }

      const { data: sesionAuth } = await supabase.auth.getUser();
      const uid = sesionAuth.user?.id;
      if (!uid) {
        if (vivo) { setCargando(false); setError("No se pudo leer tu sesión. Vuelve a entrar."); }
        return;
      }

      const { data: p } = await supabase
        .from("personas").select("id").eq("auth_user_id", uid).maybeSingle();
      if (!p) {
        if (vivo) {
          setCargando(false);
          setError("Tu cuenta todavía no está enlazada con tu ficha. Avisa a Desarrollo Organizacional.");
        }
        return;
      }
      if (!vivo) return;
      setYo({ id: p.id as string });

      const [{ data: cat }] = await Promise.all([
        supabase.from("catalogo_campos_perfil")
          .select("campo, etiqueta, requiere_documento, documento_sugerido, columnas")
          .order("etiqueta"),
        cargarSolicitudesPerfil(p.id as string),
      ]);
      if (!vivo) return;
      setCatalogoPerfil((cat as CatalogoCampoPerfil[]) ?? []);
      setCargando(false);
    })();
    return () => { vivo = false; };
  }, [supabase, router, cargarSolicitudesPerfil]);

  const campoActualPerfil = catalogoPerfil.find((c) => c.campo === campoPerfil) ?? null;

  /** Hay una pendiente sobre este mismo campo — salvo familiar_nuevo, que
   *  admite varias en paralelo (la base lo permite; acá solo se informa). */
  const yaHayPendientePerfil = campoPerfil !== "familiar_nuevo"
    && misSolicitudesPerfil.some((s) => s.campo === campoPerfil && s.estado === "pendiente");

  /** Construye el jsonb que espera fn_crear_solicitud_perfil a partir de las
   *  columnas que declara el catálogo para el campo elegido. */
  function valorPropuestoPerfil(): Record<string, string | boolean> {
    if (!campoActualPerfil) return {};
    const v: Record<string, string | boolean> = {};
    for (const col of campoActualPerfil.columnas) {
      if (col === "hijos_menores" || col === "discapacidad") {
        v[col] = formPerfil[col] === "true";
      } else if (formPerfil[col]) {
        v[col] = formPerfil[col];
      }
    }
    // correccion_identidad admite un subconjunto — nunca se manda una clave sin
    // valor. Los demás campos ya vienen completos por el `required` del form.
    return v;
  }

  async function proponerCambioPerfil(e: FormEvent) {
    e.preventDefault();
    if (!yo?.id || !campoActualPerfil) return;
    setAvisoPerfil(null);
    setEnviandoPerfil(true);
    try {
      const rutas: string[] = [];
      for (const archivo of archivosPerfil) {
        const ext = archivo.name.split(".").pop()?.toLowerCase() || "jpg";
        const ruta = `solicitud/${yo.id}/${Date.now()}-${Math.round(Math.random() * 1e6)}.${ext}`;
        const fallo = await subirArchivoConProgreso(supabase, "solicitudes-perfil", ruta, archivo, () => {});
        if (fallo) { setAvisoPerfil({ tipo: "error", texto: `No se pudo subir «${archivo.name}»: ${fallo}` }); return; }
        rutas.push(ruta);
      }

      const { error: errRpc } = await supabase.rpc("fn_crear_solicitud_perfil", {
        p_campo: campoPerfil,
        p_valor_propuesto: valorPropuestoPerfil(),
        p_rutas_adjuntas: rutas,
      });
      if (errRpc) { setAvisoPerfil({ tipo: "error", texto: errRpc.message }); return; }

      setAvisoPerfil({ tipo: "ok", texto: "Pedido. Te avisamos cuando Desarrollo Organizacional responda." });
      setFormPerfil({});
      setArchivosPerfil([]);
      await cargarSolicitudesPerfil(yo.id);
    } finally {
      setEnviandoPerfil(false);
    }
  }

  if (cargando) {
    return (
      <main className="p-6">
        <Cargando />
      </main>
    );
  }

  if (error) {
    return (
      <main className="p-6">
        <p className="max-w-md rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">{error}</p>
        <Link href="/mio" className="mt-3 inline-block text-sm text-taupe hover:text-tinta hover:underline">
          ← Volver a Mi perfil
        </Link>
      </main>
    );
  }

  return (
    <main className="mx-auto min-h-screen w-full max-w-2xl bg-crema px-5 py-8 text-tinta">
      <Link href="/mio" className="text-sm text-taupe hover:text-tinta hover:underline">
        ← Volver a Mi perfil
      </Link>

      <h1 className="mt-3 font-serif text-2xl">Editar mis datos</h1>
      <p className="mt-1 mb-6 text-sm text-taupe">
        Elige qué quieres cambiar. Desarrollo Organizacional lo revisa antes de que se aplique.
      </p>

      {catalogoPerfil.length > 0 && (
        <section className="rounded-2xl border border-sand bg-papel p-5 text-sm">
          <form onSubmit={(e) => void proponerCambioPerfil(e)} className="flex flex-col gap-3">
            <CampoSelect
              etiqueta="Qué quieres cambiar"
              value={campoPerfil}
              onChange={(e) => { setCampoPerfil(e.target.value); setFormPerfil({}); setArchivosPerfil([]); }}
              className="max-w-xs"
            >
              {catalogoPerfil.map((c) => <option key={c.campo} value={c.campo}>{c.etiqueta}</option>)}
            </CampoSelect>

            <div className="flex flex-wrap items-end gap-3">
              {campoPerfil === "celular" && (
                <Campo etiqueta="Nuevo celular" type="tel" required value={formPerfil.celular ?? ""}
                  onChange={(e) => setFormPerfil((f) => ({ ...f, celular: e.target.value }))} />
              )}
              {campoPerfil === "direccion" && (
                <div className="min-w-56 flex-1">
                  <Campo etiqueta="Nueva dirección" type="text" required value={formPerfil.direccion ?? ""}
                    onChange={(e) => setFormPerfil((f) => ({ ...f, direccion: e.target.value }))} />
                </div>
              )}
              {campoPerfil === "contacto_emergencia" && (<>
                <Campo etiqueta="Nombre" type="text" required value={formPerfil.emergencia_nombre ?? ""}
                  onChange={(e) => setFormPerfil((f) => ({ ...f, emergencia_nombre: e.target.value }))} />
                <Campo etiqueta="Vínculo" type="text" required value={formPerfil.emergencia_vinculo ?? ""}
                  onChange={(e) => setFormPerfil((f) => ({ ...f, emergencia_vinculo: e.target.value }))}
                  placeholder="madre, esposo…" />
                <Campo etiqueta="Teléfono" type="tel" required value={formPerfil.emergencia_telefono ?? ""}
                  onChange={(e) => setFormPerfil((f) => ({ ...f, emergencia_telefono: e.target.value }))} />
              </>)}
              {campoPerfil === "estado_civil" && (
                <CampoSelect etiqueta="Nuevo estado civil" required value={formPerfil.estado_civil ?? ""}
                  onChange={(e) => setFormPerfil((f) => ({ ...f, estado_civil: e.target.value }))}>
                  <option value="" disabled>Elige…</option>
                  {ESTADOS_CIVILES.map((ec) => <option key={ec} value={ec}>{ESTADO_CIVIL_LABELS[ec]}</option>)}
                </CampoSelect>
              )}
              {campoPerfil === "hijos_menores" && (
                <CampoSelect etiqueta="¿Tienes hijos menores a cargo?" required value={formPerfil.hijos_menores ?? ""}
                  onChange={(e) => setFormPerfil((f) => ({ ...f, hijos_menores: e.target.value }))}>
                  <option value="" disabled>Elige…</option>
                  <option value="true">Sí</option>
                  <option value="false">No</option>
                </CampoSelect>
              )}
              {campoPerfil === "grado_instruccion" && (
                <CampoSelect etiqueta="Nuevo grado de instrucción" required value={formPerfil.grado_instruccion ?? ""}
                  onChange={(e) => setFormPerfil((f) => ({ ...f, grado_instruccion: e.target.value }))}>
                  <option value="" disabled>Elige…</option>
                  {GRADOS_INSTRUCCION.map((g) => <option key={g} value={g}>{GRADO_INSTRUCCION_LABELS[g]}</option>)}
                </CampoSelect>
              )}
              {campoPerfil === "discapacidad" && (<>
                <CampoSelect etiqueta="¿Tienes una discapacidad?" required value={formPerfil.discapacidad ?? ""}
                  onChange={(e) => setFormPerfil((f) => ({ ...f, discapacidad: e.target.value }))}>
                  <option value="" disabled>Elige…</option>
                  <option value="true">Sí</option>
                  <option value="false">No</option>
                </CampoSelect>
                {formPerfil.discapacidad === "true" && (
                  <Campo etiqueta="Código CONADIS" type="text" required value={formPerfil.discapacidad_conadis ?? ""}
                    onChange={(e) => setFormPerfil((f) => ({ ...f, discapacidad_conadis: e.target.value }))} />
                )}
              </>)}
              {campoPerfil === "cuenta_bancaria" && (<>
                <Campo etiqueta="Banco" type="text" required value={formPerfil.entidad_bancaria ?? ""}
                  onChange={(e) => setFormPerfil((f) => ({ ...f, entidad_bancaria: e.target.value }))} />
                <Campo etiqueta="Número de cuenta" type="text" required value={formPerfil.numero_cuenta ?? ""}
                  onChange={(e) => setFormPerfil((f) => ({ ...f, numero_cuenta: e.target.value }))} />
              </>)}
              {campoPerfil === "cuspp" && (
                <Campo etiqueta="Nuevo CUSPP" type="text" required value={formPerfil.cuspp ?? ""}
                  onChange={(e) => setFormPerfil((f) => ({ ...f, cuspp: e.target.value }))} />
              )}
              {campoPerfil === "correccion_identidad" && (<>
                <p className="w-full text-xs text-taupe">
                  Es una corrección de un dato mal capturado, no una actualización — completa solo lo que está mal.
                </p>
                <Campo etiqueta="DNI correcto" type="text" value={formPerfil.documento ?? ""}
                  onChange={(e) => setFormPerfil((f) => ({ ...f, documento: e.target.value }))} />
                <Campo etiqueta="Nombre completo correcto" type="text" value={formPerfil.nombre_dni ?? ""}
                  onChange={(e) => setFormPerfil((f) => ({ ...f, nombre_dni: e.target.value }))} />
                <Campo etiqueta="Fecha de nacimiento correcta" type="date" value={formPerfil.fecha_nacimiento ?? ""}
                  onChange={(e) => setFormPerfil((f) => ({ ...f, fecha_nacimiento: e.target.value }))} />
                <CampoSelect etiqueta="Género correcto" value={formPerfil.genero ?? ""}
                  onChange={(e) => setFormPerfil((f) => ({ ...f, genero: e.target.value }))}>
                  <option value="">— sin corregir —</option>
                  {GENEROS.map((g) => <option key={g} value={g}>{GENERO_LABELS[g]}</option>)}
                </CampoSelect>
              </>)}
              {campoPerfil === "familiar_nuevo" && (<>
                <Campo etiqueta="Nombres" type="text" required value={formPerfil.nombres ?? ""}
                  onChange={(e) => setFormPerfil((f) => ({ ...f, nombres: e.target.value }))} />
                <Campo etiqueta="Apellidos" type="text" required value={formPerfil.apellidos ?? ""}
                  onChange={(e) => setFormPerfil((f) => ({ ...f, apellidos: e.target.value }))} />
                <CampoSelect etiqueta="Vínculo" required value={formPerfil.vinculo ?? ""}
                  onChange={(e) => setFormPerfil((f) => ({ ...f, vinculo: e.target.value }))}>
                  <option value="" disabled>Elige…</option>
                  {VINCULOS_DERECHOHABIENTE.map((v) => <option key={v} value={v}>{VINCULO_DERECHOHABIENTE_LABELS[v]}</option>)}
                </CampoSelect>
                <Campo
                  etiqueta={`Fecha de nacimiento${formPerfil.vinculo === "hijo" ? "" : " (si aplica)"}`}
                  type="date" required={formPerfil.vinculo === "hijo"} value={formPerfil.fecha_nacimiento ?? ""}
                  onChange={(e) => setFormPerfil((f) => ({ ...f, fecha_nacimiento: e.target.value }))} />
              </>)}
            </div>

            {campoActualPerfil?.requiere_documento && (
              // Sin componente propio: el catálogo de UI compartido todavía no
              // tiene un input de archivo (solo Campo/CampoSelect/CampoCasilla/
              // AreaTexto), así que se queda con el mismo tratamiento nativo
              // que ya traía, para no inventar un componente a mitad de una
              // migración de presentación.
              <label className="flex flex-col gap-1 text-xs text-taupe">
                Documento de sustento{campoActualPerfil.documento_sugerido ? ` (${campoActualPerfil.documento_sugerido})` : ""}
                <input type="file" multiple accept="image/jpeg,image/png,application/pdf"
                  onChange={(e) => setArchivosPerfil(Array.from(e.target.files ?? []))}
                  className="rounded-control border border-sand bg-hueso px-3 py-1.5 text-sm text-tinta" />
              </label>
            )}

            {yaHayPendientePerfil && (
              <p className="text-xs text-ambar">
                Ya tienes una solicitud pendiente sobre este campo — enviar otra reemplaza a esa.
              </p>
            )}

            <Boton type="submit" variante="primario" className="w-fit" disabled={
              enviandoPerfil || (campoActualPerfil?.requiere_documento && archivosPerfil.length === 0)
            } cargando={enviandoPerfil}>
              {enviandoPerfil ? "Enviando…" : "Pedir el cambio"}
            </Boton>
          </form>
          {avisoPerfil && (
            <p className={`mt-2 text-xs ${avisoPerfil.tipo === "ok" ? "text-verde" : "text-rojo"}`}>
              {avisoPerfil.texto}
            </p>
          )}

          {misSolicitudesPerfil.length > 0 && (
            <ul className="mt-4 space-y-2 border-t border-sand pt-3 text-xs">
              {misSolicitudesPerfil.map((s) => (
                <li key={s.id} className="flex flex-wrap items-baseline justify-between gap-2">
                  <span>
                    <strong>{catalogoPerfil.find((c) => c.campo === s.campo)?.etiqueta ?? s.campo}</strong>
                    {" "}
                    <Insignia tamano="sm" atenuada={s.estado === "reemplazada"} variante={
                      s.estado === "aprobado" ? "positivo"
                      : s.estado === "rechazado" ? "alerta"
                      : s.estado === "reemplazada" ? "neutral"
                      : "informativo"
                    }>
                      {s.estado === "pendiente" ? "por resolver" : s.estado === "reemplazada" ? "reemplazada por otra" : s.estado}
                    </Insignia>
                    {s.motivo && <span className="text-taupe"> — «{s.motivo}»</span>}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </section>
      )}
    </main>
  );
}

export default function MiEditarPage() {
  return <MiEditarContenido />;
}

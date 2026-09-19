"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Cargando } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { Insignia } from "@/components/ui/insignia";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import {
  ESTADO_CIVIL_LABELS, ESTADOS_CIVILES, GENERO_LABELS,
  GRADO_INSTRUCCION_LABELS, GRADOS_INSTRUCCION,
  REGIMEN_PENSION_LABELS, siNoSinDato,
  VINCULO_DERECHOHABIENTE_LABELS,
} from "@cayla-dynamic/shared";

/**
 * «Editar mis datos» — la ficha completa, en la misma forma que
 * /admin/datos-personales (misma persona que la lee, dos superficies
 * distintas), pero de solo lectura hasta pulsar «Editar». Antes vivía como un
 * selector de un campo a la vez, escondido dentro de la pestaña «Vacaciones y
 * permisos» de /mio.
 *
 * SOLO SIETE CAMPOS SON SUYOS PARA CAMBIAR: celular, dirección, contacto de
 * emergencia, estado civil, grado de instrucción, hijos menores a cargo y
 * cuenta bancaria — decisión de producto, no del catálogo (que tiene 11). El
 * resto (DNI, nombre, nacimiento, género, sistema de pensiones, correo,
 * discapacidad, familiares) se ve pero no se toca desde acá: para eso sigue
 * existiendo Desarrollo Organizacional en /admin/datos-personales.
 *
 * EL VALOR REAL NO CAMBIA ACÁ: cada campo que cambió se manda como una
 * propuesta separada con `fn_crear_solicitud_perfil` (0399) — el catálogo
 * sigue siendo la única fuente de qué exige documento, nunca una lista
 * escrita a mano acá. Quien aprueba es el admin/DO o, desde la 0403, la
 * encargada de la propia sede.
 */

interface Yo {
  id: string; nombres: string; apellidos: string; documento: string | null;
  email: string | null; regimenPension: string | null; sede: string | null;
}
interface Ficha {
  nombre_dni: string | null; fecha_nacimiento: string | null; estado_civil: string | null;
  genero: string | null;
  direccion: string | null; celular: string | null; entidad_bancaria: string | null; numero_cuenta: string | null;
  grado_instruccion: string | null; hijos_menores: boolean | null;
  emergencia_nombre: string | null; emergencia_vinculo: string | null; emergencia_telefono: string | null;
  discapacidad: boolean | null; discapacidad_conadis: string | null;
}
interface Derechohabiente {
  id: string; nombres: string; apellidos: string; documento: string | null;
  fecha_nacimiento: string | null; vinculo: string; essalud: boolean; vida_ley: boolean; vigente_hasta: string | null;
}

/** Una fila del catálogo de campos de perfil (0399) — qué se puede pedir y si
 *  exige documento. Se lee de la tabla, nunca a mano. */
interface CatalogoCampoPerfil {
  campo: string; etiqueta: string; requiere_documento: boolean; documento_sugerido: string | null; columnas: string[];
}
interface SolicitudPerfil {
  id: string; campo: string; estado: "pendiente" | "aprobado" | "rechazado" | "reemplazada";
  creada_at: string; motivo: string | null;
}

/** Los siete campos que esta pantalla deja tocar. Cuáles de ellos exigen
 *  documento se pregunta al catálogo (abajo), nunca se repite acá. */
const CAMPOS_EDITABLES = [
  "celular", "direccion", "contacto_emergencia",
  "estado_civil", "grado_instruccion", "hijos_menores", "cuenta_bancaria",
] as const;
type CampoEditable = (typeof CAMPOS_EDITABLES)[number];

interface FormEdit {
  celular: string; direccion: string;
  emergencia_nombre: string; emergencia_vinculo: string; emergencia_telefono: string;
  estado_civil: string; grado_instruccion: string; hijos_menores: "" | "si" | "no";
  entidad_bancaria: string; numero_cuenta: string;
}

function formDeFicha(f: Ficha | null): FormEdit {
  return {
    celular: f?.celular ?? "", direccion: f?.direccion ?? "",
    emergencia_nombre: f?.emergencia_nombre ?? "", emergencia_vinculo: f?.emergencia_vinculo ?? "",
    emergencia_telefono: f?.emergencia_telefono ?? "",
    estado_civil: f?.estado_civil ?? "", grado_instruccion: f?.grado_instruccion ?? "",
    hijos_menores: f?.hijos_menores === true ? "si" : f?.hijos_menores === false ? "no" : "",
    entidad_bancaria: f?.entidad_bancaria ?? "", numero_cuenta: f?.numero_cuenta ?? "",
  };
}

function MiEditarContenido() {
  const router = useRouter();
  const supabase = createAdminSupabaseClient();

  const [yo, setYo] = useState<Yo | null>(null);
  const [ficha, setFicha] = useState<Ficha | null>(null);
  const [derechos, setDerechos] = useState<Derechohabiente[]>([]);
  const [catalogoPerfil, setCatalogoPerfil] = useState<CatalogoCampoPerfil[]>([]);
  const [misSolicitudesPerfil, setMisSolicitudesPerfil] = useState<SolicitudPerfil[]>([]);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [editando, setEditando] = useState(false);
  const [form, setForm] = useState<FormEdit>(formDeFicha(null));
  const [archivos, setArchivos] = useState<Partial<Record<CampoEditable, File[]>>>({});
  const [guardando, setGuardando] = useState(false);
  const [aviso, setAviso] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);

  const cargarSolicitudesPerfil = useCallback(async (personaId: string) => {
    const { data } = await supabase
      .from("solicitudes_cambio_perfil")
      .select("id, campo, estado, creada_at, motivo")
      .eq("persona_id", personaId)      // ← explícito. La RLS es la red, no el filtro.
      .order("creada_at", { ascending: false });
    setMisSolicitudesPerfil((data as SolicitudPerfil[]) ?? []);
  }, [supabase]);

  const cargar = useCallback(async () => {
    setCargando(true);
    setError(null);

    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/mio"); return; }

    const { data: sesionAuth } = await supabase.auth.getUser();
    const uid = sesionAuth.user?.id;
    if (!uid) { setCargando(false); setError("No se pudo leer tu sesión. Vuelve a entrar."); return; }

    const { data: p } = await supabase
      .from("personas")
      .select("id, nombres, apellidos, documento, email, regimen_pension, sedes!personas_sede_base_id_fkey(nombre)")
      .eq("auth_user_id", uid).maybeSingle();
    if (!p) {
      setCargando(false);
      setError("Tu cuenta todavía no está enlazada con tu ficha. Avisa a Desarrollo Organizacional.");
      return;
    }
    const yoActual: Yo = {
      id: p.id as string, nombres: p.nombres as string, apellidos: p.apellidos as string,
      documento: (p.documento as string | null) ?? null, email: (p.email as string | null) ?? null,
      regimenPension: (p.regimen_pension as string | null) ?? null,
      sede: ((p.sedes as { nombre: string } | null) ?? null)?.nombre ?? null,
    };
    setYo(yoActual);

    const [{ data: f }, { data: dh }, { data: cat }] = await Promise.all([
      supabase.from("datos_personales")
        .select("nombre_dni, fecha_nacimiento, estado_civil, genero, direccion, celular, entidad_bancaria, numero_cuenta, grado_instruccion, hijos_menores, emergencia_nombre, emergencia_vinculo, emergencia_telefono, discapacidad, discapacidad_conadis")
        .eq("persona_id", yoActual.id).maybeSingle(),
      supabase.from("derechohabientes")
        .select("id, nombres, apellidos, documento, fecha_nacimiento, vinculo, essalud, vida_ley, vigente_hasta")
        .eq("persona_id", yoActual.id).order("apellidos"),
      supabase.from("catalogo_campos_perfil")
        .select("campo, etiqueta, requiere_documento, documento_sugerido, columnas")
        .order("etiqueta"),
    ]);
    const fichaActual = (f as Ficha | null) ?? null;
    setFicha(fichaActual);
    setForm(formDeFicha(fichaActual));
    setDerechos((dh as Derechohabiente[]) ?? []);
    setCatalogoPerfil((cat as CatalogoCampoPerfil[]) ?? []);
    await cargarSolicitudesPerfil(yoActual.id);
    setCargando(false);
  }, [supabase, router, cargarSolicitudesPerfil]);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargar(); }, [cargar]);

  function etiquetaDe(campo: string): string {
    return catalogoPerfil.find((c) => c.campo === campo)?.etiqueta ?? campo;
  }
  function requiereDocumento(campo: string): boolean {
    return catalogoPerfil.find((c) => c.campo === campo)?.requiere_documento === true;
  }
  function documentoSugerido(campo: string): string | null {
    return catalogoPerfil.find((c) => c.campo === campo)?.documento_sugerido ?? null;
  }
  function hayPendiente(campo: string): boolean {
    return misSolicitudesPerfil.some((s) => s.campo === campo && s.estado === "pendiente");
  }

  // Qué campo cambió de verdad respecto a la ficha — decide qué se manda al
  // guardar, y cuándo aparece el botón de adjuntar documento junto al campo.
  const cambios: Record<CampoEditable, boolean> = {
    celular: form.celular.trim() !== (ficha?.celular ?? ""),
    direccion: form.direccion.trim() !== (ficha?.direccion ?? ""),
    contacto_emergencia:
      form.emergencia_nombre.trim() !== (ficha?.emergencia_nombre ?? "")
      || form.emergencia_vinculo.trim() !== (ficha?.emergencia_vinculo ?? "")
      || form.emergencia_telefono.trim() !== (ficha?.emergencia_telefono ?? ""),
    estado_civil: form.estado_civil !== (ficha?.estado_civil ?? ""),
    grado_instruccion: form.grado_instruccion !== (ficha?.grado_instruccion ?? ""),
    hijos_menores: form.hijos_menores !== (ficha?.hijos_menores === true ? "si" : ficha?.hijos_menores === false ? "no" : ""),
    cuenta_bancaria:
      form.entidad_bancaria.trim() !== (ficha?.entidad_bancaria ?? "")
      || form.numero_cuenta.trim() !== (ficha?.numero_cuenta ?? ""),
  };
  const hayAlgunCambio = CAMPOS_EDITABLES.some((c) => cambios[c]);

  function valorPropuesto(campo: CampoEditable): Record<string, string | boolean> {
    switch (campo) {
      case "celular": return { celular: form.celular.trim() };
      case "direccion": return { direccion: form.direccion.trim() };
      case "contacto_emergencia": return {
        emergencia_nombre: form.emergencia_nombre.trim(),
        emergencia_vinculo: form.emergencia_vinculo.trim(),
        emergencia_telefono: form.emergencia_telefono.trim(),
      };
      case "estado_civil": return { estado_civil: form.estado_civil };
      case "grado_instruccion": return { grado_instruccion: form.grado_instruccion };
      case "hijos_menores": return { hijos_menores: form.hijos_menores === "si" };
      case "cuenta_bancaria": return {
        entidad_bancaria: form.entidad_bancaria.trim(), numero_cuenta: form.numero_cuenta.trim(),
      };
    }
  }

  function entrarAEditar() {
    setForm(formDeFicha(ficha));
    setArchivos({});
    setAviso(null);
    setEditando(true);
  }
  function cancelarEdicion() {
    setForm(formDeFicha(ficha));
    setArchivos({});
    setAviso(null);
    setEditando(false);
  }

  async function guardarCambios() {
    if (!yo?.id) return;
    const porEnviar = CAMPOS_EDITABLES.filter((c) => cambios[c]);
    if (porEnviar.length === 0) {
      setAviso({ tipo: "error", texto: "No cambiaste ningún dato." });
      return;
    }
    // Se valida el documento de TODOS antes de mandar el primero: mejor
    // avisar antes que dejar la mitad de los pedidos enviados por culpa del
    // segundo campo.
    for (const c of porEnviar) {
      if (requiereDocumento(c) && (archivos[c]?.length ?? 0) === 0) {
        setAviso({ tipo: "error", texto: `Adjunta un documento para «${etiquetaDe(c)}» antes de guardar.` });
        return;
      }
    }

    setGuardando(true);
    setAviso(null);
    const enviados: string[] = [];
    for (const c of porEnviar) {
      const rutas: string[] = [];
      for (const archivo of archivos[c] ?? []) {
        const ext = archivo.name.split(".").pop()?.toLowerCase() || "jpg";
        const ruta = `solicitud/${yo.id}/${Date.now()}-${Math.round(Math.random() * 1e6)}.${ext}`;
        const fallo = await subirArchivoConProgreso(supabase, "solicitudes-perfil", ruta, archivo, () => {});
        if (fallo) {
          setGuardando(false);
          setAviso({ tipo: "error", texto: `No se pudo subir el documento de «${etiquetaDe(c)}»: ${fallo}` });
          await cargarSolicitudesPerfil(yo.id);
          return;
        }
        rutas.push(ruta);
      }
      const { error: errRpc } = await supabase.rpc("fn_crear_solicitud_perfil", {
        p_campo: c, p_valor_propuesto: valorPropuesto(c), p_rutas_adjuntas: rutas,
      });
      if (errRpc) {
        setGuardando(false);
        setAviso({ tipo: "error", texto: mensajeDeError(errRpc, `pedir el cambio de «${etiquetaDe(c)}»`) });
        await cargarSolicitudesPerfil(yo.id);
        return;
      }
      enviados.push(etiquetaDe(c));
    }

    setGuardando(false);
    setArchivos({});
    setEditando(false);
    await cargarSolicitudesPerfil(yo.id);
    setAviso({
      tipo: "ok",
      texto: `Pedido${enviados.length > 1 ? "s" : ""} enviado${enviados.length > 1 ? "s" : ""}: ${enviados.join(", ")}. `
        + "Te avisamos cuando se resuelvan.",
    });
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
          ← Volver a Info
        </Link>
      </main>
    );
  }
  if (!yo) return null;

  /** Un id de aria-labelledby estable a partir del label — hace falta porque
   *  Campo no acepta una etiqueta con JSX adentro (acá el label a veces trae
   *  una nota en un <span> propio), así que la asociación se hace por
   *  aria-labelledby en vez de anidar un <label> dentro del que ya trae Campo
   *  — el mismo patrón que ya usa /admin/datos-personales para el correo. */
  function slugCampo(label: string): string {
    return `campo-fijo-${label
      .toLowerCase()
      .normalize("NFD").replace(/[̀-ͯ]/g, "")
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/(^-|-$)/g, "")}`;
  }

  /** Un campo de solo lectura: DNI, nacimiento, género, pensión, correo,
   *  discapacidad — nunca se activa, pase lo que pase con `editando`. */
  function campoFijo(label: string, valor: string, nota?: string) {
    if (!nota) {
      return <Campo etiqueta={label} value={valor} disabled className="disabled:bg-sand/30 disabled:text-taupe" />;
    }
    const idLabel = slugCampo(label);
    return (
      <div className="flex flex-col gap-1">
        <span id={idLabel} className="text-sm text-taupe">
          {label}<span className="ml-1 text-[11px]">· {nota}</span>
        </span>
        <Campo aria-labelledby={idLabel} value={valor} disabled className="disabled:bg-sand/30 disabled:text-taupe" />
      </div>
    );
  }

  /** Uno de los siete campos que sí se pueden pedir cambiar. Deshabilitado
   *  fuera de modo edición; dentro, muestra el botón de documento si el
   *  catálogo lo exige Y el valor de verdad cambió. */
  function campoEditable(
    label: string, campo: CampoEditable, valor: string,
    onChange: (v: string) => void, tipo: "text" | "tel" = "text",
  ) {
    const pendiente = hayPendiente(campo);
    const idLabel = `campo-editable-${campo}`;
    return (
      <div className="flex flex-col gap-1">
        <span id={idLabel} className="text-sm text-taupe">
          {label}
          {pendiente && <span className="ml-1 text-[11px] text-pizarra">· cambio pendiente de aprobación</span>}
        </span>
        <Campo aria-labelledby={idLabel} type={tipo} value={valor} disabled={!editando}
          onChange={(e) => onChange(e.target.value)}
          className="disabled:bg-sand/30 disabled:text-taupe" />
        {editando && cambios[campo] && requiereDocumento(campo) && (
          // <input type="file"> nativo a propósito: acá el disparador vive
          // dentro de un aviso ambar, no es un campo con su propia etiqueta —
          // igual que ya documenta /admin/educacion para el mismo caso.
          <span className="flex flex-col gap-1 rounded-lg border border-ambar/40 bg-ambar/5 p-2 text-xs text-taupe">
            Este cambio exige un documento de sustento
            {documentoSugerido(campo) && ` (${documentoSugerido(campo)})`}.
            <input type="file" multiple accept="image/jpeg,image/png,application/pdf"
              onChange={(e) => setArchivos((a) => ({ ...a, [campo]: Array.from(e.target.files ?? []) }))}
              className="rounded-lg border border-sand bg-hueso px-2 py-1 text-xs" />
          </span>
        )}
      </div>
    );
  }

  return (
    <main className="mx-auto min-h-screen w-full max-w-3xl bg-crema px-5 py-8 text-tinta">
      <div className="mb-1 flex flex-wrap items-baseline justify-between gap-3">
        <div>
          <Link href="/mio" className="text-sm text-taupe hover:text-tinta hover:underline">
            ← Volver a Info
          </Link>
          <h1 className="mt-1 font-serif text-2xl">{yo.nombres} {yo.apellidos}</h1>
          {yo.sede && <p className="text-xs text-taupe">{yo.sede}</p>}
        </div>
        {editando ? (
          <div className="flex items-center gap-3">
            <Boton variante="secundario" onClick={cancelarEdicion} disabled={guardando}>
              Cancelar
            </Boton>
            <Boton variante="primario" onClick={() => void guardarCambios()} disabled={guardando || !hayAlgunCambio}>
              {guardando ? "Guardando…" : "Guardar cambios"}
            </Boton>
          </div>
        ) : (
          <Boton variante="secundario" tamano="sm" onClick={entrarAEditar}>
            Editar
          </Boton>
        )}
      </div>
      <p className="mb-5 text-sm text-taupe">
        Los cambios se piden, no se aplican solos: los revisa {yo.sede ? "tu líder de equipo o " : ""}Desarrollo Organizacional
        antes de que se apliquen.
      </p>

      {aviso && (
        <p className={`mb-4 rounded-lg px-4 py-3 text-sm ${aviso.tipo === "ok" ? "bg-verde/10 text-verde" : "bg-rojo/10 text-rojo"}`}>
          {aviso.texto}
        </p>
      )}

      <div className="space-y-4 rounded-2xl border border-sand bg-papel p-5">
        <section>
          <p className="mb-2 text-[11px] uppercase tracking-wider text-taupe">Identidad</p>
          <div className="grid gap-3 sm:grid-cols-2">
            {campoFijo("Número de DNI", yo.documento ?? "—", "solo Desarrollo Organizacional")}
            {campoFijo("Nombre completo (como en el DNI)", ficha?.nombre_dni ?? "—")}
            {campoFijo("Fecha de nacimiento", ficha?.fecha_nacimiento ?? "—")}
            {campoFijo("Género", ficha?.genero ? (GENERO_LABELS[ficha.genero as keyof typeof GENERO_LABELS] ?? ficha.genero) : "—")}
            {editando
              ? (
                <div className="flex flex-col gap-1">
                  <span id="campo-estado-civil-editable" className="text-sm text-taupe">
                    Estado civil
                    {hayPendiente("estado_civil") && <span className="ml-1 text-[11px] text-pizarra">· cambio pendiente de aprobación</span>}
                  </span>
                  <CampoSelect aria-labelledby="campo-estado-civil-editable" value={form.estado_civil}
                    onChange={(e) => setForm((f) => ({ ...f, estado_civil: e.target.value }))}>
                    <option value="">—</option>
                    {ESTADOS_CIVILES.map((ec) => <option key={ec} value={ec}>{ESTADO_CIVIL_LABELS[ec]}</option>)}
                  </CampoSelect>
                  {cambios.estado_civil && requiereDocumento("estado_civil") && (
                    // <input type="file"> nativo — ver el comentario de campoEditable.
                    <span className="flex flex-col gap-1 rounded-lg border border-ambar/40 bg-ambar/5 p-2 text-xs text-taupe">
                      Este cambio exige un documento de sustento ({documentoSugerido("estado_civil")}).
                      <input type="file" multiple accept="image/jpeg,image/png,application/pdf"
                        onChange={(e) => setArchivos((a) => ({ ...a, estado_civil: Array.from(e.target.files ?? []) }))}
                        className="rounded-lg border border-sand bg-hueso px-2 py-1 text-xs" />
                    </span>
                  )}
                </div>
              )
              : campoFijo("Estado civil", ficha?.estado_civil ? (ESTADO_CIVIL_LABELS[ficha.estado_civil as keyof typeof ESTADO_CIVIL_LABELS] ?? ficha.estado_civil) : "—",
                  hayPendiente("estado_civil") ? "cambio pendiente de aprobación" : undefined)}
            {editando
              ? (
                <div className="flex flex-col gap-1">
                  <span id="campo-grado-instruccion-editable" className="text-sm text-taupe">
                    Grado de instrucción
                    {hayPendiente("grado_instruccion") && <span className="ml-1 text-[11px] text-pizarra">· cambio pendiente de aprobación</span>}
                  </span>
                  <CampoSelect aria-labelledby="campo-grado-instruccion-editable" value={form.grado_instruccion}
                    onChange={(e) => setForm((f) => ({ ...f, grado_instruccion: e.target.value }))}>
                    <option value="">—</option>
                    {GRADOS_INSTRUCCION.map((g) => <option key={g} value={g}>{GRADO_INSTRUCCION_LABELS[g]}</option>)}
                  </CampoSelect>
                  {cambios.grado_instruccion && requiereDocumento("grado_instruccion") && (
                    // <input type="file"> nativo — ver el comentario de campoEditable.
                    <span className="flex flex-col gap-1 rounded-lg border border-ambar/40 bg-ambar/5 p-2 text-xs text-taupe">
                      Este cambio exige un documento de sustento ({documentoSugerido("grado_instruccion")}).
                      <input type="file" multiple accept="image/jpeg,image/png,application/pdf"
                        onChange={(e) => setArchivos((a) => ({ ...a, grado_instruccion: Array.from(e.target.files ?? []) }))}
                        className="rounded-lg border border-sand bg-hueso px-2 py-1 text-xs" />
                    </span>
                  )}
                </div>
              )
              : campoFijo("Grado de instrucción", ficha?.grado_instruccion ? (GRADO_INSTRUCCION_LABELS[ficha.grado_instruccion as keyof typeof GRADO_INSTRUCCION_LABELS] ?? ficha.grado_instruccion) : "—",
                  hayPendiente("grado_instruccion") ? "cambio pendiente de aprobación" : undefined)}
            {editando
              ? (
                <div className="flex flex-col gap-1">
                  <span id="campo-hijos-menores-editable" className="text-sm text-taupe">
                    ¿Hijos menores a cargo?
                    {hayPendiente("hijos_menores") && <span className="ml-1 text-[11px] text-pizarra">· cambio pendiente de aprobación</span>}
                  </span>
                  <CampoSelect aria-labelledby="campo-hijos-menores-editable" value={form.hijos_menores}
                    onChange={(e) => setForm((f) => ({ ...f, hijos_menores: e.target.value as "" | "si" | "no" }))}>
                    <option value="">—</option>
                    <option value="si">Sí</option>
                    <option value="no">No</option>
                  </CampoSelect>
                  {cambios.hijos_menores && requiereDocumento("hijos_menores") && (
                    // <input type="file"> nativo — ver el comentario de campoEditable.
                    <span className="flex flex-col gap-1 rounded-lg border border-ambar/40 bg-ambar/5 p-2 text-xs text-taupe">
                      Este cambio exige un documento de sustento ({documentoSugerido("hijos_menores")}).
                      <input type="file" multiple accept="image/jpeg,image/png,application/pdf"
                        onChange={(e) => setArchivos((a) => ({ ...a, hijos_menores: Array.from(e.target.files ?? []) }))}
                        className="rounded-lg border border-sand bg-hueso px-2 py-1 text-xs" />
                    </span>
                  )}
                </div>
              )
              : campoFijo("¿Hijos menores a cargo?", siNoSinDato(ficha?.hijos_menores),
                  hayPendiente("hijos_menores") ? "cambio pendiente de aprobación" : undefined)}
          </div>
        </section>

        <section>
          <p className="mb-2 text-[11px] uppercase tracking-wider text-taupe">Pensión</p>
          <div className="grid gap-3 sm:grid-cols-2">
            {campoFijo(
              "Sistema de pensiones",
              yo.regimenPension ? (REGIMEN_PENSION_LABELS[yo.regimenPension as keyof typeof REGIMEN_PENSION_LABELS] ?? yo.regimenPension) : "— todavía no se sabe",
            )}
            <p className="self-end text-[11px] text-taupe">
              Se descuenta de tu remuneración asegurable y va a tu fondo de pensión — no se queda en CAYLA.
            </p>
          </div>
        </section>

        <section>
          <p className="mb-2 text-[11px] uppercase tracking-wider text-taupe">Contacto</p>
          <div className="grid gap-3 sm:grid-cols-2">
            {campoEditable("Celular", "celular", editando ? form.celular : (ficha?.celular ?? ""),
              (v) => setForm((f) => ({ ...f, celular: v })), "tel")}
            {campoFijo("Correo", yo.email ?? "—", "es tu usuario para entrar")}
            <div className="sm:col-span-2">
              {campoEditable("Dirección", "direccion", editando ? form.direccion : (ficha?.direccion ?? ""),
                (v) => setForm((f) => ({ ...f, direccion: v })))}
            </div>
          </div>
        </section>

        <section>
          <p className="mb-2 text-[11px] uppercase tracking-wider text-taupe">
            Contacto de emergencia
            {hayPendiente("contacto_emergencia") && <span className="ml-1 normal-case text-pizarra">· cambio pendiente de aprobación</span>}
          </p>
          <div className="grid gap-3 sm:grid-cols-3">
            <Campo etiqueta="Nombre" value={editando ? form.emergencia_nombre : (ficha?.emergencia_nombre ?? "")} disabled={!editando}
              onChange={(e) => setForm((f) => ({ ...f, emergencia_nombre: e.target.value }))}
              className="disabled:bg-sand/30 disabled:text-taupe" />
            <Campo etiqueta="Vínculo" value={editando ? form.emergencia_vinculo : (ficha?.emergencia_vinculo ?? "")} disabled={!editando}
              onChange={(e) => setForm((f) => ({ ...f, emergencia_vinculo: e.target.value }))}
              className="disabled:bg-sand/30 disabled:text-taupe" />
            <Campo etiqueta="Teléfono" value={editando ? form.emergencia_telefono : (ficha?.emergencia_telefono ?? "")} disabled={!editando}
              onChange={(e) => setForm((f) => ({ ...f, emergencia_telefono: e.target.value }))}
              className="disabled:bg-sand/30 disabled:text-taupe" />
          </div>
        </section>

        <section>
          <p className="mb-2 text-[11px] uppercase tracking-wider text-taupe">
            Familiares {derechos.length > 0 && <span className="normal-case">· {derechos.filter((d) => !d.vigente_hasta).length} vigentes</span>}
          </p>
          <p className="mb-2 text-[11px] text-taupe">
            Esto se ve, pero se agrega o corrige avisando a Desarrollo Organizacional.
          </p>
          {derechos.length === 0 ? (
            <p className="text-sm text-taupe">Sin familiares registrados.</p>
          ) : (
            <ul className="divide-y rounded-lg border border-sand">
              {derechos.map((d) => (
                <li key={d.id} className={`flex flex-wrap items-center justify-between gap-2 px-3 py-2 text-sm ${d.vigente_hasta ? "text-taupe" : ""}`}>
                  <span>
                    {d.nombres} {d.apellidos}
                    <span className="ml-2 text-xs text-taupe">
                      {VINCULO_DERECHOHABIENTE_LABELS[d.vinculo as keyof typeof VINCULO_DERECHOHABIENTE_LABELS] ?? d.vinculo}
                      {d.documento && ` · DNI ${d.documento}`}
                      {d.fecha_nacimiento && ` · ${d.fecha_nacimiento}`}
                    </span>
                  </span>
                  <span className="flex items-center gap-2 text-xs">
                    {/* punto={false}: son atributos, no un estado — igual que
                        "sueldo fijo" o "dirección" en /admin/personas/[id]. */}
                    {d.essalud && <Insignia variante="neutral" punto={false}>EsSalud</Insignia>}
                    {d.vida_ley && <Insignia variante="neutral" punto={false}>Vida Ley</Insignia>}
                    {d.vigente_hasta && <span className="text-taupe">cerrado el {d.vigente_hasta}</span>}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </section>

        <section>
          <p className="mb-2 text-[11px] uppercase tracking-wider text-taupe">Banco</p>
          <div className="grid gap-3 sm:grid-cols-2">
            {campoEditable("Entidad bancaria", "cuenta_bancaria", editando ? form.entidad_bancaria : (ficha?.entidad_bancaria ?? ""),
              (v) => setForm((f) => ({ ...f, entidad_bancaria: v })))}
            <Campo etiqueta="N.° de cuenta" value={editando ? form.numero_cuenta : (ficha?.numero_cuenta ?? "")} disabled={!editando}
              onChange={(e) => setForm((f) => ({ ...f, numero_cuenta: e.target.value }))}
              className="disabled:bg-sand/30 disabled:text-taupe" />
          </div>
        </section>

        <section>
          <p className="mb-2 text-[11px] uppercase tracking-wider text-taupe">Discapacidad</p>
          <div className="grid gap-3 sm:grid-cols-2">
            {campoFijo("¿Persona con discapacidad?", siNoSinDato(ficha?.discapacidad))}
            {ficha?.discapacidad && campoFijo("N.° de certificado CONADIS", ficha.discapacidad_conadis ?? "—")}
          </div>
        </section>
      </div>

      {misSolicitudesPerfil.length > 0 && (
        <section className="mt-5 rounded-2xl border border-sand bg-papel p-5 text-sm">
          <h2 className="mb-3 font-serif text-lg">Tus pedidos de cambio</h2>
          <ul className="space-y-2 text-xs">
            {misSolicitudesPerfil.map((s) => (
              <li key={s.id} className="flex flex-wrap items-baseline justify-between gap-2 border-t border-sand pt-2 first:border-t-0 first:pt-0">
                <span>
                  <strong>{etiquetaDe(s.campo)}</strong>
                  {" · "}
                  <span className={
                    s.estado === "aprobado" ? "text-verde"
                    : s.estado === "rechazado" ? "text-rojo"
                    : s.estado === "reemplazada" ? "text-taupe"
                    : "text-pizarra"
                  }>
                    {s.estado === "pendiente" ? "por resolver" : s.estado === "reemplazada" ? "reemplazada por otra" : s.estado}
                  </span>
                  {s.motivo && <span className="text-taupe"> — «{s.motivo}»</span>}
                </span>
              </li>
            ))}
          </ul>
        </section>
      )}
    </main>
  );
}

export default function MiEditarPage() {
  return <MiEditarContenido />;
}

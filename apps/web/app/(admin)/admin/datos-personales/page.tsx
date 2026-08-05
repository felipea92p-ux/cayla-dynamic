"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { ESTADO_CIVIL_LABELS, ESTADOS_CIVILES, GRADO_INSTRUCCION_LABELS, GRADOS_INSTRUCCION, puedeOperarEquipo, puedeVerIdentidad, REGIMEN_PENSION_LABELS, REGIMENES_PENSION, VINCULO_DERECHOHABIENTE_LABELS, VINCULOS_DERECHOHABIENTE } from "@cayla-dynamic/shared";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { AdminNav } from "../nav";
import { Cargando } from "@/components/cargando";
import { mensajeDeError } from "@/lib/admin/mensaje-error";

interface Persona {
  id: string; nombres: string; apellidos: string; documento: string | null;
  sede_base_id: string; email: string | null;
  regimen_pension: string | null;   // CAMBIO 0125
}
interface Ficha {
  persona_id: string; nombre_dni: string | null; fecha_nacimiento: string | null; estado_civil: string | null;
  direccion: string | null; celular: string | null; entidad_bancaria: string | null; numero_cuenta: string | null;
  grado_instruccion: string | null; hijos_menores: boolean | null;
  foto_dni_url: string | null; foto_personal_url: string | null; foto_profesional_url: string | null;
  // CAMBIO 0125
  emergencia_nombre: string | null; emergencia_vinculo: string | null; emergencia_telefono: string | null;
  discapacidad: boolean | null; discapacidad_conadis: string | null;
}
interface Derechohabiente {
  id: string; persona_id: string; nombres: string; apellidos: string;
  documento: string | null; fecha_nacimiento: string | null; vinculo: string;
  essalud: boolean; vida_ley: boolean; vigente_hasta: string | null; nota: string | null;
}
interface Form {
  nombre_dni: string; fecha_nacimiento: string; estado_civil: string; direccion: string; celular: string;
  entidad_bancaria: string; numero_cuenta: string; grado_instruccion: string;
  hijos_menores: "" | "si" | "no";
  foto_dni_url: string; foto_personal_url: string; foto_profesional_url: string;
  emergencia_nombre: string; emergencia_vinculo: string; emergencia_telefono: string;
  discapacidad: "" | "si" | "no"; discapacidad_conadis: string;
}

const VACIO: Form = {
  nombre_dni: "", fecha_nacimiento: "", estado_civil: "", direccion: "", celular: "",
  entidad_bancaria: "", numero_cuenta: "", grado_instruccion: "", hijos_menores: "",
  foto_dni_url: "", foto_personal_url: "", foto_profesional_url: "",
  emergencia_nombre: "", emergencia_vinculo: "", emergencia_telefono: "",
  discapacidad: "", discapacidad_conadis: "",
};

/** Familiar nuevo, en blanco. */
const DH_VACIO = {
  nombres: "", apellidos: "", vinculo: "hijo", documento: "",
  fecha_nacimiento: "", essalud: false, vida_ley: false,
};

export default function DatosPersonalesPage() {
  const router = useRouter();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const puede = puedeOperarEquipo(rol);
  // El DNI y el régimen de pensión los edita SOLO Desarrollo Organizacional: el
  // primero se imprime en memos y contratos, el segundo decide cuánto se le
  // descuenta a la persona. Las funciones de la base los rechazan para la
  // encargada, así que aquí se muestran de solo lectura en vez de dejar que el
  // guardado falle con un error que nadie entiende.
  const puedeIdentidad = puedeVerIdentidad(rol);

  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [sedes, setSedes] = useState<Map<string, string>>(new Map());
  const [fichas, setFichas] = useState<Map<string, Ficha>>(new Map());
  const [derechos, setDerechos] = useState<Derechohabiente[]>([]);
  const [sel, setSel] = useState<string>("");
  const [form, setForm] = useState<Form>(VACIO);
  // Identidad: viven en `personas`, no en la ficha, y se guardan con su propia
  // función porque cada una deja su rastro de auditoría por separado.
  const [dni, setDni] = useState("");
  const [motivoDni, setMotivoDni] = useState("");
  const [regimen, setRegimen] = useState("");
  const [dhNuevo, setDhNuevo] = useState({ ...DH_VACIO });
  const [dhAbierto, setDhAbierto] = useState(false);
  // Si la carga falló, la pantalla no sabe qué hay de verdad: guardar desde aquí
  // borraría datos. Se bloquea hasta que una recarga vaya bien.
  const [cargaFallida, setCargaFallida] = useState(false);
  const [cargando, setCargando] = useState(true);
  const [guardando, setGuardando] = useState(false);
  const [msg, setMsg] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  const [q, setQ] = useState("");
  const [soloSinFicha, setSoloSinFicha] = useState(false);
  const fichaRef = useRef<HTMLDivElement>(null);

  const cargar = useCallback(async () => {
    setCargando(true);
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    const [
      { data: p, error: eP }, { data: s, error: eS },
      { data: dp, error: eD }, { data: dh, error: eDH },
    ] = await Promise.all([
      supabase.from("personas").select("id, nombres, apellidos, documento, sede_base_id, email, regimen_pension").eq("estado", "activo").order("nombres"),
      supabase.from("sedes").select("id, codigo"),
      supabase.from("datos_personales").select("persona_id, nombre_dni, fecha_nacimiento, estado_civil, direccion, celular, entidad_bancaria, numero_cuenta, grado_instruccion, hijos_menores, foto_dni_url, foto_personal_url, foto_profesional_url, emergencia_nombre, emergencia_vinculo, emergencia_telefono, discapacidad, discapacidad_conadis"),
      supabase.from("derechohabientes").select("id, persona_id, nombres, apellidos, documento, fecha_nacimiento, vinculo, essalud, vida_ley, vigente_hasta, nota").order("apellidos"),
    ]);

    // Si una consulta falla NO se pisa el estado. Antes se hacía
    // `(dp as Ficha[]) ?? []`, y un fallo de red dejaba el mapa de fichas vacío:
    // la pantalla mostraba a todo el mundo "sin ficha", el formulario salía en
    // blanco, y pulsar Guardar escribía null en TODO — borrando DNI, dirección y
    // número de cuenta de una persona real, sin que nada avisara.
    const fallo = eP ?? eS ?? eD ?? eDH;
    if (fallo) {
      setCargaFallida(true);
      setMsg({ tipo: "error", texto: `No se pudieron cargar las fichas: ${fallo.message}. No guardes nada hasta recargar: lo que ves puede no ser lo que hay.` });
      setCargando(false);
      return;
    }
    setCargaFallida(false);
    setPersonas((p as Persona[]) ?? []);
    setSedes(new Map(((s as Array<{ id: string; codigo: string }>) ?? []).map((x) => [x.id, x.codigo])));
    setFichas(new Map(((dp as Ficha[]) ?? []).map((x) => [x.persona_id, x])));
    setDerechos((dh as Derechohabiente[]) ?? []);
    setCargando(false);
  }, [supabase, router]);

  useEffect(() => { void cargar(); }, [cargar]);

  function seleccionar(id: string) {
    setSel(id); setMsg(null); setMotivoDni(""); setDhAbierto(false); setDhNuevo({ ...DH_VACIO });
    // En móvil la ficha queda debajo de la lista: la traemos a la vista
    // (respetando la preferencia de "reducir movimiento" del sistema).
    if (typeof window !== "undefined" && window.innerWidth < 768) {
      const suave = !window.matchMedia("(prefers-reduced-motion: reduce)").matches;
      setTimeout(() => fichaRef.current?.scrollIntoView({ behavior: suave ? "smooth" : "auto", block: "start" }), 60);
    }
    const persona = personas.find((x) => x.id === id) ?? null;
    setDni(persona?.documento ?? "");
    setRegimen(persona?.regimen_pension ?? "");
    const f = fichas.get(id);
    setForm(f ? {
      nombre_dni: f.nombre_dni ?? "", fecha_nacimiento: f.fecha_nacimiento ?? "", estado_civil: f.estado_civil ?? "",
      direccion: f.direccion ?? "", celular: f.celular ?? "", entidad_bancaria: f.entidad_bancaria ?? "",
      numero_cuenta: f.numero_cuenta ?? "", grado_instruccion: f.grado_instruccion ?? "",
      hijos_menores: f.hijos_menores === true ? "si" : f.hijos_menores === false ? "no" : "",
      foto_dni_url: f.foto_dni_url ?? "", foto_personal_url: f.foto_personal_url ?? "", foto_profesional_url: f.foto_profesional_url ?? "",
      emergencia_nombre: f.emergencia_nombre ?? "", emergencia_vinculo: f.emergencia_vinculo ?? "",
      emergencia_telefono: f.emergencia_telefono ?? "",
      discapacidad: f.discapacidad === true ? "si" : f.discapacidad === false ? "no" : "",
      discapacidad_conadis: f.discapacidad_conadis ?? "",
    } : { ...VACIO });
  }

  const personaSel = personas.find((p) => p.id === sel) ?? null;
  const dniCambio = !!personaSel && dni.trim() !== (personaSel.documento ?? "");
  const regimenCambio = !!personaSel && regimen !== (personaSel.regimen_pension ?? "");

  async function guardar() {
    if (!sel) return;
    if (cargaFallida) {
      setMsg({ tipo: "error", texto: "No se guarda: las fichas no llegaron a cargar y guardar ahora borraría los datos que ya existen. Recarga la página." });
      return;
    }
    // El motivo del DNI se exige aquí y no solo en la base, para que el aviso
    // llegue antes de intentar guardar y no como un error del servidor.
    if (dniCambio && !motivoDni.trim()) {
      setMsg({ tipo: "error", texto: "Escribe el motivo del cambio de DNI: ese número se imprime en memos y contratos." });
      return;
    }
    setGuardando(true); setMsg(null);

    // Los quince campos de la ficha SIEMPRE se mandan completos: la función de
    // la base es un upsert que reemplaza, no un update parcial. Si se omite uno,
    // se guarda en null.
    const { error } = await supabase.rpc("fn_set_datos_personales", {
      p_persona_id: sel,
      p_nombre_dni: form.nombre_dni.trim() || null,
      p_fecha_nacimiento: form.fecha_nacimiento || null,
      p_estado_civil: form.estado_civil.trim() || null,
      p_direccion: form.direccion.trim() || null,
      p_celular: form.celular.trim() || null,
      p_entidad_bancaria: form.entidad_bancaria.trim() || null,
      p_numero_cuenta: form.numero_cuenta.trim() || null,
      p_grado_instruccion: form.grado_instruccion.trim() || null,
      p_hijos_menores: form.hijos_menores === "" ? null : form.hijos_menores === "si",
      p_foto_dni_url: form.foto_dni_url.trim() || null,
      p_foto_personal_url: form.foto_personal_url.trim() || null,
      p_foto_profesional_url: form.foto_profesional_url.trim() || null,
      p_emergencia_nombre: form.emergencia_nombre.trim() || null,
      p_emergencia_vinculo: form.emergencia_vinculo.trim() || null,
      p_emergencia_telefono: form.emergencia_telefono.trim() || null,
      p_discapacidad: form.discapacidad === "" ? null : form.discapacidad === "si",
      p_discapacidad_conadis: form.discapacidad_conadis.trim() || null,
    });
    if (error) { setGuardando(false); setMsg({ tipo: "error", texto: mensajeDeError(error) }); return; }

    // Identidad: solo si de verdad cambió, para no ensuciar la auditoría con
    // guardados que no cambian nada.
    if (dniCambio) {
      const { error: eDni } = await supabase.rpc("fn_set_documento", {
        p_persona_id: sel, p_documento: dni.trim(), p_motivo: motivoDni.trim(),
      });
      if (eDni) { setGuardando(false); setMsg({ tipo: "error", texto: `La ficha se guardó, pero el DNI no: ${mensajeDeError(eDni)}` }); return; }
    }
    if (regimenCambio) {
      const { error: eReg } = await supabase.rpc("fn_set_regimen_pension", {
        p_persona_id: sel, p_regimen: regimen || null,
      });
      if (eReg) { setGuardando(false); setMsg({ tipo: "error", texto: `La ficha se guardó, pero el régimen de pensión no: ${mensajeDeError(eReg)}` }); return; }
    }

    setGuardando(false);
    await cargar();
    setMotivoDni("");
    setMsg({ tipo: "ok", texto: regimenCambio ? "Ficha guardada. El nuevo régimen se aplica desde el próximo cálculo de planilla." : "Ficha guardada." });
  }

  async function agregarDerechohabiente() {
    if (!sel) return;
    if (!dhNuevo.nombres.trim() || !dhNuevo.apellidos.trim()) {
      setMsg({ tipo: "error", texto: "El nombre y el apellido del familiar son obligatorios." });
      return;
    }
    if (dhNuevo.vinculo === "hijo" && !dhNuevo.fecha_nacimiento) {
      setMsg({ tipo: "error", texto: "La fecha de nacimiento de una hija o hijo es obligatoria: es lo que define hasta cuándo lo cubre EsSalud." });
      return;
    }
    setGuardando(true); setMsg(null);
    const { error } = await supabase.rpc("fn_set_derechohabiente", {
      p_id: null, p_persona_id: sel,
      p_nombres: dhNuevo.nombres.trim(), p_apellidos: dhNuevo.apellidos.trim(),
      p_vinculo: dhNuevo.vinculo,
      p_documento: dhNuevo.documento.trim() || null,
      p_fecha_nacimiento: dhNuevo.fecha_nacimiento || null,
      p_essalud: dhNuevo.essalud, p_vida_ley: dhNuevo.vida_ley, p_nota: null,
    });
    setGuardando(false);
    if (error) { setMsg({ tipo: "error", texto: mensajeDeError(error) }); return; }
    setDhNuevo({ ...DH_VACIO }); setDhAbierto(false);
    await cargar();
    setMsg({ tipo: "ok", texto: "Familiar agregado." });
  }

  async function cerrarDerechohabiente(id: string, nombre: string) {
    if (!window.confirm(`¿Cerrar a ${nombre}? No se borra: queda registrado hasta hoy, así que el periodo en que estuvo cubierto sigue explicándose.`)) return;
    setGuardando(true); setMsg(null);
    const { error } = await supabase.rpc("fn_cerrar_derechohabiente", { p_id: id, p_hasta: null });
    setGuardando(false);
    if (error) { setMsg({ tipo: "error", texto: mensajeDeError(error) }); return; }
    await cargar();
    setMsg({ tipo: "ok", texto: `${nombre} quedó cerrado con la fecha de hoy.` });
  }

  const lista = personas.filter((p) =>
    `${p.nombres} ${p.apellidos}`.toLowerCase().includes(q.trim().toLowerCase())
    && (!soloSinFicha || !fichas.has(p.id)));
  const sinFicha = personas.filter((p) => !fichas.has(p.id)).length;
  const misDerechos = derechos.filter((d) => d.persona_id === sel);

  if (rol !== null && !puede) {
    return (
      <div className="flex min-h-screen flex-col">
        <AdminNav />
        <main className="flex flex-1 items-center justify-center p-6">
          <p className="max-w-md text-center text-taupe">No tienes permiso para ver datos personales.</p>
        </main>
      </div>
    );
  }

  function campo(label: string, key: keyof Form, tipo: "text" | "date" = "text") {
    return (
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-taupe">{label}</span>
        <input type={tipo} value={form[key]} onChange={(e) => setForm((f) => ({ ...f, [key]: e.target.value }))}
          className="rounded-lg border px-3 py-2" />
      </label>
    );
  }
  /**
   * Campo de lista cerrada que NO descarta lo que ya estaba escrito.
   *
   * Las fichas anteriores tienen estado civil y grado de instrucción a mano. Si
   * el valor guardado no está en el catálogo, se añade al desplegable como
   * opción propia y marcada, en vez de aparecer vacío: un campo que se ve vacío
   * invita a guardarlo vacío, y ahí se pierde el dato de una persona real.
   */
  function campoLista(label: string, key: keyof Form, opciones: readonly string[], etiquetas: Record<string, string>) {
    const actual = form[key] as string;
    const esAntiguo = actual !== "" && !opciones.includes(actual);
    return (
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-taupe">
          {label}
          {esAntiguo && <span className="ml-1 text-[11px] text-amber-700">· valor antiguo, elige uno de la lista</span>}
        </span>
        <select value={actual} onChange={(e) => setForm((f) => ({ ...f, [key]: e.target.value }))}
          className={`rounded-lg border bg-crema px-3 py-2 ${esAntiguo ? "border-amber-400" : ""}`}>
          <option value="">—</option>
          {esAntiguo && <option value={actual}>{actual} (como estaba)</option>}
          {opciones.map((o) => (
            <option key={o} value={o}>{etiquetas[o] ?? o}</option>
          ))}
        </select>
      </label>
    );
  }
  function campoSiNo(label: string, key: "hijos_menores" | "discapacidad") {
    return (
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-taupe">{label}</span>
        <select value={form[key]} onChange={(e) => setForm((f) => ({ ...f, [key]: e.target.value as "" | "si" | "no" }))}
          className="rounded-lg border bg-crema px-3 py-2">
          <option value="">—</option>
          <option value="si">Sí</option>
          <option value="no">No</option>
        </select>
      </label>
    );
  }
  function campoFoto(label: string, key: keyof Form) {
    return (
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-taupe">{label} {form[key] && <a href={form[key] as string} target="_blank" rel="noreferrer" className="text-tinta underline">ver</a>}</span>
        <input value={form[key]} onChange={(e) => setForm((f) => ({ ...f, [key]: e.target.value }))}
          className="rounded-lg border px-3 py-2" placeholder="Enlace de Drive" />
      </label>
    );
  }

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <h1 className="mb-1 font-serif text-2xl">Datos personales</h1>
        <p className="mb-5 max-w-2xl text-sm text-taupe">
          Ficha personal de cada integrante: DNI, pensión, contacto, familia y documentos.
          Datos sensibles — visibles solo para Desarrollo Organizacional, la encargada de tu sede y cada persona sobre sí misma.
        </p>

        {msg && (
          <div className={`mb-4 max-w-2xl rounded-lg px-4 py-3 text-sm ${msg.tipo === "ok" ? "bg-sand/40 text-tinta" : "bg-rojo/10 text-rojo"}`}>
            {msg.texto}
          </div>
        )}

        <div className="grid gap-6 md:grid-cols-[260px_1fr]">
          {/* Lista de personas */}
          <div className="overflow-hidden rounded-2xl border border-sand bg-papel">
            <div className="border-b bg-sand/50 px-3 py-2">
              <div className="flex items-baseline justify-between">
                <h2 className="text-sm font-medium">Equipo {personas.length > 0 && <span className="font-normal text-taupe">· {personas.length}</span>}</h2>
                {sinFicha > 0 && (
                  <button onClick={() => setSoloSinFicha((v) => !v)} aria-pressed={soloSinFicha}
                    className={`rounded-full px-2 py-0.5 text-xs transition-colors ${soloSinFicha ? "bg-amber-200 text-amber-900" : "text-amber-800 hover:bg-amber-100"}`}>
                    {sinFicha} sin ficha
                  </button>
                )}
              </div>
              <div className="relative mt-2">
                <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar por nombre…"
                  className="w-full rounded-lg border bg-crema px-3 py-1.5 pr-8 text-sm" />
                {q && (
                  <button onClick={() => setQ("")} aria-label="Limpiar búsqueda"
                    className="absolute right-2 top-1/2 -translate-y-1/2 leading-none text-taupe hover:text-tinta">×</button>
                )}
              </div>
            </div>
            {cargando ? (
              <Cargando />
            ) : lista.length === 0 ? (
              <p className="px-3 py-4 text-sm text-taupe">Nadie coincide con “{q}”.</p>
            ) : (
              <ul className="max-h-[70vh] divide-y overflow-y-auto">
                {lista.map((p) => (
                  <li key={p.id}>
                    <button onClick={() => seleccionar(p.id)}
                      className={`flex w-full items-center justify-between px-3 py-2 text-left text-sm ${sel === p.id ? "bg-sand/60 font-medium text-tinta" : "hover:bg-sand/30"}`}>
                      <span>{p.nombres} {p.apellidos}</span>
                      <span className="flex items-center gap-1 text-xs text-taupe">
                        {sedes.get(p.sede_base_id)}
                        {!fichas.has(p.id) && <span className="rounded-full bg-amber-100 px-1.5 text-amber-800">sin ficha</span>}
                      </span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>

          {/* Ficha */}
          <div ref={fichaRef} className="scroll-mt-4 rounded-2xl border border-sand bg-papel p-5">
            {!personaSel ? (
              <p className="text-sm text-taupe">Elige a alguien de la lista para ver o editar su ficha.</p>
            ) : (
              <>
                <div className="mb-3 flex flex-wrap items-baseline justify-between gap-x-3">
                  <h2 className="font-serif text-lg">{personaSel.nombres} {personaSel.apellidos}</h2>
                  <div className="flex items-center gap-3 text-xs">
                    <span className="text-taupe">{sedes.get(personaSel.sede_base_id)}</span>
                    <button onClick={() => router.push(`/admin/personas/${personaSel.id}`)} className="text-tinta hover:underline">Ver perfil →</button>
                  </div>
                </div>
                <div className="space-y-4">
                  <section>
                    <p className="mb-2 text-[11px] uppercase tracking-wider text-taupe">Identidad</p>
                    <div className="grid gap-3 sm:grid-cols-2">
                      {/* El DNI vive en `personas` y se guarda con su propia función,
                          porque se imprime en papeles legales y su cambio va a auditoría. */}
                      <label className="flex flex-col gap-1 text-sm">
                        <span className="text-taupe">
                          Número de DNI
                          {!puedeIdentidad && <span className="ml-1 text-[11px]">· solo Desarrollo Organizacional</span>}
                        </span>
                        <input value={dni} disabled={!puedeIdentidad}
                          onChange={(e) => setDni(e.target.value)}
                          className={`rounded-lg border px-3 py-2 disabled:bg-sand/30 disabled:text-taupe ${dniCambio ? "border-amber-400" : ""}`} />
                      </label>
                      {campo("Nombre completo (como en el DNI)", "nombre_dni")}
                      {dniCambio && (
                        <label className="flex flex-col gap-1 text-sm sm:col-span-2">
                          <span className="text-amber-800">
                            Motivo del cambio de DNI (obligatorio) — de {personaSel.documento ?? "vacío"} a {dni.trim()}
                          </span>
                          <input value={motivoDni} onChange={(e) => setMotivoDni(e.target.value)}
                            placeholder="Por ejemplo: corregido contra la constancia de alta del T-Registro"
                            className="rounded-lg border border-amber-400 px-3 py-2" />
                          <span className="text-[11px] text-taupe">
                            Este número se imprime en los memos disciplinarios y en los documentos de respaldo, así que el cambio queda registrado con su motivo.
                          </span>
                        </label>
                      )}
                      {campo("Fecha de nacimiento", "fecha_nacimiento", "date")}
                      {campoLista("Estado civil", "estado_civil", ESTADOS_CIVILES, ESTADO_CIVIL_LABELS)}
                      {campoLista("Grado de instrucción", "grado_instruccion", GRADOS_INSTRUCCION, GRADO_INSTRUCCION_LABELS)}
                      {campoSiNo("¿Hijos menores a cargo?", "hijos_menores")}
                    </div>
                  </section>

                  {/* CAMBIO 0125 — El régimen decide la tasa que se le descuenta. */}
                  <section>
                    <p className="mb-2 text-[11px] uppercase tracking-wider text-taupe">Pensión</p>
                    <div className="grid gap-3 sm:grid-cols-2">
                      <label className="flex flex-col gap-1 text-sm">
                        <span className="text-taupe">
                          Sistema de pensiones
                          {!puedeIdentidad && <span className="ml-1 text-[11px]">· solo Desarrollo Organizacional</span>}
                        </span>
                        <select value={regimen} disabled={!puedeIdentidad}
                          onChange={(e) => setRegimen(e.target.value)}
                          className={`rounded-lg border bg-crema px-3 py-2 disabled:bg-sand/30 disabled:text-taupe ${regimenCambio ? "border-amber-400" : ""}`}>
                          <option value="">— todavía no se sabe</option>
                          {REGIMENES_PENSION.map((r) => (
                            <option key={r} value={r}>{REGIMEN_PENSION_LABELS[r]}</option>
                          ))}
                        </select>
                      </label>
                      <p className="self-end text-[11px] text-taupe">
                        {regimen === ""
                          ? "Sin régimen se le descuenta la tasa genérica del 13 %. Conviene poner el verdadero: sale en su boleta."
                          : "Se descuenta de su remuneración asegurable y va a su fondo de pensión — no se queda en CAYLA."}
                        {regimenCambio && <strong className="block text-amber-800">Se aplicará desde el próximo cálculo de planilla.</strong>}
                      </p>
                    </div>
                  </section>

                  <section>
                    <p className="mb-2 text-[11px] uppercase tracking-wider text-taupe">Contacto</p>
                    <div className="grid gap-3 sm:grid-cols-2">
                      {campo("Celular", "celular")}
                      <label className="flex flex-col gap-1 text-sm sm:col-span-2">
                        <span className="text-taupe">Dirección</span>
                        <input value={form.direccion} onChange={(e) => setForm((f) => ({ ...f, direccion: e.target.value }))} className="rounded-lg border px-3 py-2" />
                      </label>
                    </div>
                  </section>

                  {/* CAMBIO 0125 — A quién llamar si pasa algo. */}
                  <section>
                    <p className="mb-2 text-[11px] uppercase tracking-wider text-taupe">Contacto de emergencia</p>
                    <div className="grid gap-3 sm:grid-cols-3">
                      {campo("Nombre", "emergencia_nombre")}
                      {campo("Vínculo", "emergencia_vinculo")}
                      {campo("Teléfono", "emergencia_telefono")}
                    </div>
                  </section>

                  {/* CAMBIO 0125 — Familiares: EsSalud y Seguro de Vida Ley. */}
                  <section>
                    <div className="mb-2 flex items-baseline justify-between">
                      <p className="text-[11px] uppercase tracking-wider text-taupe">
                        Familiares {misDerechos.length > 0 && <span className="normal-case">· {misDerechos.filter((d) => !d.vigente_hasta).length} vigentes</span>}
                      </p>
                      <button onClick={() => setDhAbierto((v) => !v)} className="text-xs text-tinta hover:underline">
                        {dhAbierto ? "Cancelar" : "+ Agregar familiar"}
                      </button>
                    </div>
                    <p className="mb-2 text-[11px] text-taupe">
                      Dos cosas distintas: <strong>EsSalud</strong> es quien está inscrito ante SUNAT y puede atenderse;
                      <strong> Vida Ley</strong> es a quién le paga la aseguradora si la persona fallece. Sin esa declaración el pago va a un juzgado.
                    </p>

                    {misDerechos.length === 0 ? (
                      <p className="text-sm text-taupe">Sin familiares registrados.</p>
                    ) : (
                      <ul className="divide-y rounded-lg border border-sand">
                        {misDerechos.map((d) => (
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
                              {d.essalud && <span className="rounded-full bg-sand/60 px-2 py-0.5">EsSalud</span>}
                              {d.vida_ley && <span className="rounded-full bg-sand/60 px-2 py-0.5">Vida Ley</span>}
                              {d.vigente_hasta
                                ? <span className="text-taupe">cerrado el {d.vigente_hasta}</span>
                                : <button onClick={() => void cerrarDerechohabiente(d.id, `${d.nombres} ${d.apellidos}`)}
                                    disabled={guardando} className="text-rojo hover:underline disabled:opacity-50">cerrar</button>}
                            </span>
                          </li>
                        ))}
                      </ul>
                    )}

                    {dhAbierto && (
                      <div className="mt-3 rounded-lg border border-sand bg-crema/50 p-3">
                        <div className="grid gap-3 sm:grid-cols-2">
                          <label className="flex flex-col gap-1 text-sm">
                            <span className="text-taupe">Nombres</span>
                            <input value={dhNuevo.nombres} onChange={(e) => setDhNuevo((d) => ({ ...d, nombres: e.target.value }))} className="rounded-lg border px-3 py-2" />
                          </label>
                          <label className="flex flex-col gap-1 text-sm">
                            <span className="text-taupe">Apellidos</span>
                            <input value={dhNuevo.apellidos} onChange={(e) => setDhNuevo((d) => ({ ...d, apellidos: e.target.value }))} className="rounded-lg border px-3 py-2" />
                          </label>
                          <label className="flex flex-col gap-1 text-sm">
                            <span className="text-taupe">Vínculo</span>
                            <select value={dhNuevo.vinculo} onChange={(e) => setDhNuevo((d) => ({ ...d, vinculo: e.target.value }))}
                              className="rounded-lg border bg-crema px-3 py-2">
                              {VINCULOS_DERECHOHABIENTE.map((v) => (
                                <option key={v} value={v}>{VINCULO_DERECHOHABIENTE_LABELS[v]}</option>
                              ))}
                            </select>
                          </label>
                          <label className="flex flex-col gap-1 text-sm">
                            <span className="text-taupe">DNI <span className="text-[11px]">(puede faltar en un recién nacido)</span></span>
                            <input value={dhNuevo.documento} onChange={(e) => setDhNuevo((d) => ({ ...d, documento: e.target.value }))} className="rounded-lg border px-3 py-2" />
                          </label>
                          <label className="flex flex-col gap-1 text-sm">
                            <span className="text-taupe">
                              Fecha de nacimiento
                              {dhNuevo.vinculo === "hijo" && <span className="ml-1 text-[11px] text-amber-700">· obligatoria</span>}
                            </span>
                            <input type="date" value={dhNuevo.fecha_nacimiento} onChange={(e) => setDhNuevo((d) => ({ ...d, fecha_nacimiento: e.target.value }))} className="rounded-lg border px-3 py-2" />
                          </label>
                          <div className="flex flex-col gap-2 text-sm sm:self-end">
                            <label className="flex items-center gap-2">
                              <input type="checkbox" checked={dhNuevo.essalud} onChange={(e) => setDhNuevo((d) => ({ ...d, essalud: e.target.checked }))} />
                              <span>Inscrito en EsSalud</span>
                            </label>
                            <label className="flex items-center gap-2">
                              <input type="checkbox" checked={dhNuevo.vida_ley} onChange={(e) => setDhNuevo((d) => ({ ...d, vida_ley: e.target.checked }))} />
                              <span>Beneficiario de Vida Ley</span>
                            </label>
                          </div>
                        </div>
                        <button onClick={() => void agregarDerechohabiente()} disabled={guardando}
                          className="mt-3 rounded-lg bg-tinta px-4 py-1.5 text-sm text-crema disabled:opacity-50">
                          Agregar
                        </button>
                      </div>
                    )}
                  </section>

                  <section>
                    <p className="mb-2 text-[11px] uppercase tracking-wider text-taupe">Banco</p>
                    <div className="grid gap-3 sm:grid-cols-2">
                      {campo("Entidad bancaria", "entidad_bancaria")}
                      {campo("N.° de cuenta", "numero_cuenta")}
                    </div>
                  </section>

                  {/* CAMBIO 0125 — El T-Registro lo pregunta, y la deducción de la
                      Ley 29973 exige el certificado del CONADIS, no la declaración. */}
                  <section>
                    <p className="mb-2 text-[11px] uppercase tracking-wider text-taupe">Discapacidad</p>
                    <div className="grid gap-3 sm:grid-cols-2">
                      {campoSiNo("¿Persona con discapacidad?", "discapacidad")}
                      {form.discapacidad === "si" && campo("N.° de certificado CONADIS", "discapacidad_conadis")}
                    </div>
                  </section>

                  <section>
                    <p className="mb-2 text-[11px] uppercase tracking-wider text-taupe">Documentos</p>
                    <div className="grid gap-3 sm:grid-cols-2">
                      {campoFoto("Foto DNI", "foto_dni_url")}
                      {campoFoto("Foto personal", "foto_personal_url")}
                      {campoFoto("Foto profesional", "foto_profesional_url")}
                    </div>
                  </section>
                </div>
                <button onClick={guardar} disabled={guardando || cargaFallida}
                  className="mt-4 rounded-lg bg-tinta px-5 py-2 text-sm font-medium text-crema disabled:opacity-50">
                  {guardando ? "Guardando…" : "Guardar ficha"}
                </button>
              </>
            )}
          </div>
        </div>
      </main>
    </div>
  );
}

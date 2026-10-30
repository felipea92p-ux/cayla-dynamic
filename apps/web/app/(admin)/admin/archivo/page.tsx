"use client";

// ============================================================================
// Archivo de la empresa — los papeles que CAYLA presenta o recibe de una autoridad
// ============================================================================
// QUÉ PROMETE
//   Que Desarrollo Organizacional suba, encuentre y abra en un minuto los papeles
//   que pide una inspección —la inscripción de un banco de datos personales, la
//   constancia de REMYPE, una licencia de funcionamiento—, con quién los subió,
//   cuándo y hasta cuándo valen. Migración 0503.
//
// QUÉ ASUME
//   Que la base decide todo lo que importa: quién puede (solo DO), qué ficha es
//   la vigente (`estado`), que nada se edita ni se borra. Esta pantalla solo
//   dibuja y pide; `puedeGestionarArchivo` decide si se dibuja.
//
// EL ARCHIVO VA PRIMERO
//   Se sube el archivo y recién después se registra la ficha. Si Storage cae, no
//   queda ninguna fila; si la ficha falla después de subir, se intenta borrar el
//   archivo huérfano (la política lo permite porque nadie lo usa) y, si tampoco
//   se puede, queda suelto sin hacer daño.
// ============================================================================

import { Fragment, useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { fechaLima, hoyLima, puedeGestionarArchivo } from "@cayla-dynamic/shared";
import { Cargando } from "@/components/cargando";
import { useToast } from "@/components/toast";
import { AreaTexto } from "@/components/ui/area-texto";
import { Boton } from "@/components/ui/boton";
import { AyudaPantalla } from "@/components/ui/ayuda-pantalla";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { Insignia } from "@/components/ui/insignia";
import { Modal } from "@/components/ui/modal";
import { abrirArchivoFirmado } from "@/lib/abrir-archivo-firmado";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { isoADiaMesAnio } from "@/lib/admin/planilla/formato";
import { useRolActual } from "@/lib/admin/use-rol";
import { pesoLegible } from "@/lib/reducir-imagen";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import {
  agruparPorEntidad, coincide, entidadesUsadas, estadoVencimiento, problemaDeArchivo,
  rutaNuevaArchivo, textoVencimiento, versionesAnteriores,
  BUCKET_ARCHIVO, TIPOS_ARCHIVO, type FichaArchivo,
} from "@/lib/admin/archivo";

interface Sede { id: string; nombre: string; activa: boolean }

interface Form {
  titulo: string;
  entidad: string;
  numero: string;
  // Nace en HOY y no en "": es obligatoria, y un campo de fecha que bloquea el
  // envío no puede arrancar vacío (CLAUDE.md, regla del 2026-08-26).
  fecha_documento: string;
  // Opcional: vacía no bloquea nada, solo significa «no vence».
  vence_el: string;
  sede_id: string;
  nota: string;
}

function formVacio(): Form {
  return { titulo: "", entidad: "", numero: "", fecha_documento: hoyLima(), vence_el: "", sede_id: "", nota: "" };
}

function formDesde(f: FichaArchivo): Form {
  return {
    titulo: f.titulo, entidad: f.entidad, numero: f.numero ?? "", fecha_documento: f.fecha_documento,
    vence_el: f.vence_el ?? "", sede_id: f.sede_id ?? "", nota: f.nota ?? "",
  };
}

/** Lo que falta o está mal en el formulario, campo por campo. Vacío = se puede guardar. */
function erroresDe(form: Form, hoy: string): Partial<Record<keyof Form, string>> {
  const e: Partial<Record<keyof Form, string>> = {};
  if (form.titulo.trim().length < 3) e.titulo = "Escribe qué papel es.";
  if (form.entidad.trim().length < 2) e.entidad = "Escribe quién lo emite.";
  if (!form.fecha_documento) e.fecha_documento = "Falta la fecha del papel.";
  else if (form.fecha_documento > hoy) e.fecha_documento = "No puede ser posterior a hoy.";
  if (form.vence_el && form.fecha_documento && form.vence_el < form.fecha_documento) {
    e.vence_el = "No puede vencer antes de emitirse.";
  }
  return e;
}

const fechaPapel = (iso: string) => isoADiaMesAnio(iso);
const fechaSubida = (iso: string) => isoADiaMesAnio(fechaLima(iso));

export default function ArchivoPage() {
  const router = useRouter();
  const rol = useRolActual();
  const puede = puedeGestionarArchivo(rol);
  const { avisar } = useToast();
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const hoy = hoyLima();

  const [fichas, setFichas] = useState<FichaArchivo[]>([]);
  const [sedes, setSedes] = useState<Sede[]>([]);
  const [cargando, setCargando] = useState(true);
  const [cargaError, setCargaError] = useState<string | null>(null);
  const [busqueda, setBusqueda] = useState("");
  const [historialAbierto, setHistorialAbierto] = useState<string | null>(null);
  const [verRetirados, setVerRetirados] = useState(false);

  const cargar = useCallback(async () => {
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    const [archivo, sedesR] = await Promise.all([
      supabase.rpc("fn_archivo_empresa"),
      supabase.from("sedes").select("id, nombre, activa").order("nombre"),
    ]);
    setFichas((archivo.data as FichaArchivo[] | null) ?? []);
    setSedes((sedesR.data as Sede[] | null) ?? []);
    setCargaError(archivo.error ? mensajeDeError(archivo.error, "cargar el archivo") : null);
    setCargando(false);
  }, [supabase, router]);

  // `cargar` solo pone estado después de sus `await` (la sesión, la base): no
  // hay renders en cascada. Mismo patrón que /mio/boleta.
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { if (puede) void cargar(); }, [puede, cargar]);

  const vigentes = useMemo(() => fichas.filter((f) => f.estado === "vigente"), [fichas]);
  const retirados = useMemo(() => fichas.filter((f) => f.estado === "retirada"), [fichas]);
  const grupos = useMemo(
    () => agruparPorEntidad(vigentes.filter((f) => coincide(f, busqueda))),
    [vigentes, busqueda],
  );
  const alertas = useMemo(
    () => vigentes
      .map((f) => ({ f, v: estadoVencimiento(f.vence_el, hoy) }))
      .filter(({ v }) => v.estado === "vencido" || v.estado === "por_vencer")
      .sort((a, b) => (a.v.dias ?? 0) - (b.v.dias ?? 0)),
    [vigentes, hoy],
  );

  // ── Subir o reemplazar ────────────────────────────────────────────────
  // `reemplazando` null = papel nuevo; con ficha = corrige o actualiza esa.
  const [formAbierto, setFormAbierto] = useState(false);
  const [reemplazando, setReemplazando] = useState<FichaArchivo | null>(null);
  const [form, setForm] = useState<Form>(formVacio);
  const [archivo, setArchivo] = useState<File | null>(null);
  const [intentoGuardar, setIntentoGuardar] = useState(false);
  const [msgForm, setMsgForm] = useState<string | null>(null);
  const [progreso, setProgreso] = useState<number | null>(null);
  const [guardando, setGuardando] = useState(false);

  function abrirNuevo() {
    setReemplazando(null); setForm(formVacio()); setArchivo(null);
    setIntentoGuardar(false); setMsgForm(null); setFormAbierto(true);
  }
  function abrirReemplazo(f: FichaArchivo) {
    setReemplazando(f); setForm(formDesde(f)); setArchivo(null);
    setIntentoGuardar(false); setMsgForm(null); setFormAbierto(true);
  }
  function cerrarForm() { if (!guardando) setFormAbierto(false); }

  const errores = erroresDe(form, hoy);
  const problemaArchivo = archivo ? problemaDeArchivo(archivo) : null;
  const faltaArchivo = !archivo && !reemplazando;

  async function guardar() {
    setIntentoGuardar(true); setMsgForm(null);
    if (Object.keys(errores).length > 0) return;
    if (faltaArchivo) { setMsgForm("Elige el archivo del papel: un PDF o una foto."); return; }
    if (problemaArchivo) { setMsgForm(problemaArchivo); return; }

    setGuardando(true);
    // Sin archivo nuevo, la ficha nueva usa el de la que reemplaza: corregir un
    // dato no obliga a volver a subirlo.
    let ruta = reemplazando?.storage_path ?? "";
    let nombre = reemplazando?.nombre_archivo ?? "";
    let subidoAhora = false;
    if (archivo) {
      ruta = rutaNuevaArchivo(archivo.name, archivo.type, crypto.randomUUID());
      nombre = archivo.name;
      setProgreso(0);
      const fallo = await subirArchivoConProgreso(supabase, BUCKET_ARCHIVO, ruta, archivo, setProgreso);
      setProgreso(null);
      if (fallo) { setGuardando(false); setMsgForm(`El archivo no subió (${fallo}). Vuelve a intentarlo.`); return; }
      subidoAhora = true;
    }

    const { error } = await supabase.rpc("fn_archivo_subir", {
      p_storage_path: ruta,
      p_nombre_archivo: nombre,
      p_titulo: form.titulo.trim(),
      p_entidad: form.entidad.trim(),
      p_numero: form.numero.trim() || null,
      p_fecha_documento: form.fecha_documento,
      p_vence_el: form.vence_el || null,
      p_sede_id: form.sede_id || null,
      p_nota: form.nota.trim() || null,
      p_reemplaza_a: reemplazando?.id ?? null,
    });
    if (error) {
      // El archivo subió y la ficha no: se limpia el huérfano. Si no se puede,
      // queda suelto sin hacer daño (nadie lo ve ni lo usa).
      if (subidoAhora) await supabase.storage.from(BUCKET_ARCHIVO).remove([ruta]);
      setGuardando(false);
      setMsgForm(mensajeDeError(error, "guardar"));
      return;
    }
    setGuardando(false);
    setFormAbierto(false);
    await cargar();
    avisar("ok", reemplazando ? "Listo. La versión anterior quedó en el historial." : "Guardado en el archivo.");
  }

  // ── Retirar ───────────────────────────────────────────────────────────
  const [retirando, setRetirando] = useState<FichaArchivo | null>(null);
  const [motivo, setMotivo] = useState("");
  const [msgRetiro, setMsgRetiro] = useState<string | null>(null);
  const [ocupadoRetiro, setOcupadoRetiro] = useState(false);

  async function confirmarRetiro() {
    if (!retirando) return;
    if (motivo.trim().length < 5) { setMsgRetiro("Escribe el motivo (al menos 5 letras)."); return; }
    setOcupadoRetiro(true);
    const { error } = await supabase.rpc("fn_archivo_retirar", { p_id: retirando.id, p_motivo: motivo.trim() });
    setOcupadoRetiro(false);
    if (error) { setMsgRetiro(mensajeDeError(error)); return; }
    setRetirando(null);
    await cargar();
    avisar("ok", "Papel retirado. Sigue guardado en «Retirados».");
  }

  async function abrir(f: FichaArchivo) {
    const fallo = await abrirArchivoFirmado(supabase, BUCKET_ARCHIVO, f.storage_path, 120);
    if (fallo) avisar("error", fallo);
  }

  const sedesDelSelect = sedes.filter((s) => s.activa || s.id === form.sede_id);
  const sugerencias = entidadesUsadas(fichas);

  // ── Dibujo ────────────────────────────────────────────────────────────
  if (rol === null) return <main className="flex-1 p-6"><Cargando /></main>;
  if (!puede) {
    return (
      <main className="flex-1 p-6">
        <div className="max-w-2xl rounded-lg bg-ambar/15 px-4 py-3 text-sm text-ambar">
          El archivo de la empresa solo lo ve Desarrollo Organizacional.
        </div>
      </main>
    );
  }

  return (
    <main className="flex-1 p-6">
      <CabeceraPagina
        titulo="Archivo de la empresa"
        descripcion="Los papeles que CAYLA presenta o recibe de una autoridad, a la mano para una inspección."
        ayuda={
          <AyudaPantalla
            titulo="Cómo funciona el Archivo de la empresa"
            intro="Inscripciones, licencias y constancias: lo que una autoridad pide ver el día de una inspección."
            secciones={[
              { titulo: "Quién lo ve", texto: "Solo Desarrollo Organizacional. No es una pantalla para el equipo." },
              { titulo: "Nada se borra", texto: "Corregir un papel deja el anterior en su historial: lo que se mostró a una autoridad siempre se puede volver a ver." },
            ]}
          />
        }
        accion={!cargaError && <Boton variante="primario" onClick={abrirNuevo}>+ Subir un papel</Boton>}
      />

      {cargaError && (
        <div className="mb-4 max-w-3xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
          {cargaError}{" "}
          <Boton variante="enlace" onClick={() => void cargar()}>Reintentar</Boton>
        </div>
      )}

      {cargando ? <Cargando /> : !cargaError && (
        <>
          {alertas.length > 0 && (
            <div className="mb-6 max-w-3xl rounded-2xl border border-ambar/40 bg-ambar/10 px-5 py-4">
              <p className="mb-2 text-sm font-medium text-tinta">
                {alertas.length === 1 ? "Un papel necesita renovarse" : `${alertas.length} papeles necesitan renovarse`}
              </p>
              <ul className="space-y-1 text-sm text-tinta">
                {alertas.map(({ f }) => (
                  <li key={f.id}>
                    {f.titulo}{f.sede_nombre ? ` · ${f.sede_nombre}` : ""} —{" "}
                    <span className="font-medium">{textoVencimiento(f.vence_el, hoy)}</span>
                  </li>
                ))}
              </ul>
            </div>
          )}

          {vigentes.length === 0 ? (
            <div className="max-w-2xl rounded-2xl border border-sand bg-papel px-6 py-8 text-sm text-taupe">
              <p className="mb-2 text-tinta">Todavía no hay ningún papel en el archivo.</p>
              <p>
                Sube el primero con <span className="font-medium text-tinta">+ Subir un papel</span>. Los que más
                pide una inspección: la constancia de REMYPE, la licencia de funcionamiento de cada sede y la
                inscripción de los bancos de datos personales.
              </p>
            </div>
          ) : (
            <>
              <div className="mb-4 max-w-md">
                <Campo
                  etiqueta="Buscar"
                  value={busqueda}
                  onChange={(e) => setBusqueda(e.target.value)}
                  placeholder="Nombre del papel, quién lo emite, número o sede"
                />
              </div>

              {grupos.length === 0 && (
                <p className="text-sm text-taupe">Ningún papel coincide con «{busqueda}».</p>
              )}

              <div className="space-y-6">
                {grupos.map((g) => (
                  <section key={g.entidad} className="rounded-2xl border border-sand bg-papel">
                    <h2 className="border-b border-sand px-5 py-3 font-serif text-lg text-tinta">{g.entidad}</h2>
                    <ul>
                      {g.fichas.map((f) => {
                        const anteriores = versionesAnteriores(f, fichas);
                        const venc = estadoVencimiento(f.vence_el, hoy);
                        return (
                          <li key={f.id} className="border-b border-sand px-5 py-4 last:border-b-0">
                            <div className="flex flex-wrap items-start justify-between gap-3">
                              <div className="min-w-0 flex-1">
                                <p className="font-medium text-tinta">{f.titulo}</p>
                                <p className="mt-0.5 text-sm text-taupe">
                                  {f.numero && <><span className="font-mono text-tinta">{f.numero}</span> · </>}
                                  del {fechaPapel(f.fecha_documento)}
                                  {f.vence_el && <> · vence el {fechaPapel(f.vence_el)}</>}
                                  {" · "}{f.sede_nombre ?? "Toda la empresa"}
                                </p>
                                {f.nota && <p className="mt-1 text-sm text-taupe">{f.nota}</p>}
                                <p className="mt-1 text-xs text-taupe">
                                  {f.nombre_archivo} · {pesoLegible(f.bytes)} · subido el {fechaSubida(f.subido_at)}
                                  {f.subido_por_nombre && ` por ${f.subido_por_nombre}`}
                                </p>
                              </div>
                              <div className="flex flex-wrap items-center gap-2">
                                {venc.estado === "vencido" && <Insignia variante="alerta">{textoVencimiento(f.vence_el, hoy)}</Insignia>}
                                {venc.estado === "por_vencer" && <Insignia variante="advertencia">{textoVencimiento(f.vence_el, hoy)}</Insignia>}
                                <Boton variante="primario" tamano="sm" onClick={() => void abrir(f)}>Abrir</Boton>
                                <Boton tamano="sm" onClick={() => abrirReemplazo(f)}>Corregir o reemplazar</Boton>
                                <Boton variante="sutil" tamano="sm" onClick={() => { setRetirando(f); setMotivo(""); setMsgRetiro(null); }}>
                                  Retirar
                                </Boton>
                              </div>
                            </div>
                            {anteriores.length > 0 && (
                              <div className="mt-2">
                                <Boton variante="enlace" onClick={() => setHistorialAbierto(historialAbierto === f.id ? null : f.id)}>
                                  {historialAbierto === f.id ? "Ocultar" : "Ver"} {anteriores.length === 1 ? "la versión anterior" : `las ${anteriores.length} versiones anteriores`}
                                </Boton>
                                {historialAbierto === f.id && (
                                  <ul className="mt-2 space-y-2 border-l-2 border-sand pl-4">
                                    {anteriores.map((a) => (
                                      <li key={a.id} className="text-sm text-taupe">
                                        <span className="text-tinta">{a.titulo}</span>
                                        {a.numero && <> · <span className="font-mono">{a.numero}</span></>}
                                        {" · "}del {fechaPapel(a.fecha_documento)}
                                        {a.vence_el && <> · vence el {fechaPapel(a.vence_el)}</>}
                                        {" · "}{a.sede_nombre ?? "Toda la empresa"}
                                        <span className="block text-xs">
                                          subido el {fechaSubida(a.subido_at)}{a.subido_por_nombre && ` por ${a.subido_por_nombre}`} ·{" "}
                                          <Boton variante="enlace" onClick={() => void abrir(a)}>abrir su archivo</Boton>
                                        </span>
                                      </li>
                                    ))}
                                  </ul>
                                )}
                              </div>
                            )}
                          </li>
                        );
                      })}
                    </ul>
                  </section>
                ))}
              </div>
            </>
          )}

          {retirados.length > 0 && (
            <div className="mt-8">
              <Boton variante="enlace" onClick={() => setVerRetirados(!verRetirados)}>
                {verRetirados ? "Ocultar" : "Ver"} los retirados ({retirados.length})
              </Boton>
              {verRetirados && (
                <ul className="mt-3 max-w-3xl space-y-3">
                  {retirados.map((f) => (
                    <li key={f.id} className="rounded-xl border border-sand bg-hueso px-4 py-3 text-sm">
                      <p className="text-tinta">{f.titulo} <span className="text-taupe">· {f.entidad}</span></p>
                      <p className="mt-0.5 text-taupe">
                        Retirado el {f.retirado_at ? fechaSubida(f.retirado_at) : "—"}
                        {f.retirado_por_nombre && ` por ${f.retirado_por_nombre}`}: «{f.retirado_motivo}»
                      </p>
                      <Boton variante="enlace" onClick={() => void abrir(f)}>Abrir el archivo</Boton>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          )}
        </>
      )}

      {/* ── Subir o reemplazar ─────────────────────────────────────────── */}
      <Modal
        abierto={formAbierto}
        onCerrar={cerrarForm}
        bloqueado={guardando}
        titulo={reemplazando ? "Corregir o reemplazar un papel" : "Subir un papel"}
        ancho="lg"
      >
        {reemplazando && (
          <p className="mb-4 rounded-lg bg-hueso px-3 py-2 text-sm text-taupe">
            La ficha actual no se borra: queda en el historial de este papel. Si solo corriges un dato, no hace falta
            volver a subir el archivo.
          </p>
        )}
        {msgForm && (
          <p role="alert" className="mb-3 rounded border border-rojo/30 bg-rojo/10 px-3 py-2 text-sm text-rojo">{msgForm}</p>
        )}
        {/* `grid-cols-1` y no la grilla implícita: sin él, en un teléfono la única
            columna crece hasta el ancho natural del selector de archivo y los
            campos se salen del diálogo por la derecha. */}
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <label className="flex min-w-0 flex-col gap-1 sm:col-span-2">
            <span className="text-sm text-taupe">{reemplazando ? "Archivo nuevo (opcional)" : "Archivo"}</span>
            <input
              type="file"
              accept={TIPOS_ARCHIVO}
              onChange={(e) => { setArchivo(e.target.files?.[0] ?? null); setMsgForm(null); }}
              className={`w-full min-w-0 rounded-control border bg-hueso px-3 py-2 text-sm text-tinta file:mr-2 file:rounded file:border-0 file:bg-sand file:px-2 file:py-0.5 file:text-xs file:text-tinta ${
                intentoGuardar && (faltaArchivo || problemaArchivo) ? "border-rojo" : "border-sand"
              }`}
            />
            <span className={`text-xs ${intentoGuardar && (faltaArchivo || problemaArchivo) ? "text-rojo" : "text-taupe"}`}>
              {archivo
                ? problemaArchivo ?? `${archivo.name} · ${pesoLegible(archivo.size)}`
                : reemplazando
                  ? `Si no eliges uno, se conserva el actual: ${reemplazando.nombre_archivo}`
                  : intentoGuardar
                    ? "Falta el archivo: elige el PDF o la foto del papel."
                    : "Un PDF o una foto, hasta 50 MB."}
            </span>
          </label>
          <div className="sm:col-span-2">
            <Campo
              etiqueta="Qué papel es"
              value={form.titulo}
              onChange={(e) => setForm({ ...form, titulo: e.target.value })}
              placeholder="ej. Constancia de inscripción del banco de datos Videovigilancia"
              error={intentoGuardar ? errores.titulo : undefined}
            />
          </div>
          <div className="sm:col-span-2">
            <Campo
              etiqueta="Quién lo emite"
              value={form.entidad}
              onChange={(e) => setForm({ ...form, entidad: e.target.value })}
              placeholder="ej. Autoridad Nacional de Protección de Datos Personales"
              list="entidades-archivo"
              error={intentoGuardar ? errores.entidad : undefined}
            />
            <datalist id="entidades-archivo">
              {sugerencias.map((s) => <option key={s} value={s} />)}
            </datalist>
            {sugerencias.length > 0 && (
              <span className="mt-1 block text-xs text-taupe">
                Si ya hay papeles de esa entidad, elígela de la lista para que queden juntos.
              </span>
            )}
          </div>
          <Campo
            etiqueta="Número o código (opcional)"
            value={form.numero}
            onChange={(e) => setForm({ ...form, numero: e.target.value })}
            placeholder="ej. INS-2026-5135"
          />
          <CampoSelect
            etiqueta="De qué sede es"
            value={form.sede_id}
            onChange={(e) => setForm({ ...form, sede_id: e.target.value })}
          >
            <option value="">Toda la empresa</option>
            {sedesDelSelect.map((s) => <option key={s.id} value={s.id}>{s.nombre}</option>)}
          </CampoSelect>
          <Campo
            etiqueta="Fecha del papel"
            type="date"
            value={form.fecha_documento}
            max={hoy}
            onChange={(e) => setForm({ ...form, fecha_documento: e.target.value })}
            error={intentoGuardar ? errores.fecha_documento : undefined}
          />
          <div>
            <Campo
              etiqueta="Vence el (opcional)"
              type="date"
              value={form.vence_el}
              min={form.fecha_documento || undefined}
              onChange={(e) => setForm({ ...form, vence_el: e.target.value })}
              error={intentoGuardar ? errores.vence_el : undefined}
            />
            <span className="mt-1 block text-xs text-taupe">Déjalo vacío si el papel no vence. Si vence, avisa dos meses antes.</span>
          </div>
          {/* Rótulo propio y no `etiqueta`: AreaTexto lo pinta en mayúsculas y
              el resto de este formulario (Campo) va en caja normal. */}
          <label className="flex flex-col gap-1 sm:col-span-2">
            <span className="text-sm text-taupe">Nota (opcional)</span>
            <AreaTexto
              value={form.nota}
              onChange={(e) => setForm({ ...form, nota: e.target.value })}
              placeholder="ej. El original está colgado junto a la caja de la tienda"
            />
          </label>
        </div>
        {progreso !== null && (
          <div className="mt-3">
            <div className="h-1.5 w-full overflow-hidden rounded-pildora bg-sand">
              <div className="h-full bg-tinta transition-[width] duration-200" style={{ width: `${progreso}%` }} />
            </div>
            <span className="text-xs text-taupe">Subiendo — {progreso}%</span>
          </div>
        )}
        <div className="mt-5 flex justify-end gap-2">
          <Boton onClick={cerrarForm} disabled={guardando}>Cancelar</Boton>
          <Boton variante="primario" onClick={() => void guardar()} cargando={guardando}>
            {progreso !== null ? `Subiendo… ${progreso}%` : "Guardar en el archivo"}
          </Boton>
        </div>
      </Modal>

      {/* ── Retirar ────────────────────────────────────────────────────── */}
      <Modal
        abierto={retirando !== null}
        onCerrar={() => { if (!ocupadoRetiro) setRetirando(null); }}
        bloqueado={ocupadoRetiro}
        titulo="Retirar un papel"
        ancho="sm"
      >
        {retirando && (
          <Fragment>
            <p className="mb-3 text-sm text-taupe">
              «{retirando.titulo}» deja de verse en la lista, pero no se borra: queda en «Retirados» con tu nombre y
              este motivo. Úsalo para un papel que ya no aplica o que se subió por error. Si solo cambió un dato,
              usa «Corregir o reemplazar».
            </p>
            <label className="flex flex-col gap-1">
              <span className="text-sm text-taupe">Por qué se retira</span>
              <AreaTexto
                value={motivo}
                onChange={(e) => { setMotivo(e.target.value); setMsgRetiro(null); }}
                placeholder="ej. La tienda cerró y su licencia ya no aplica"
                className={msgRetiro ? "border-rojo" : undefined}
              />
              {msgRetiro && <span className="text-xs text-rojo">{msgRetiro}</span>}
            </label>
            <div className="mt-4 flex justify-end gap-2">
              <Boton onClick={() => setRetirando(null)} disabled={ocupadoRetiro}>Cancelar</Boton>
              <Boton variante="peligro" onClick={() => void confirmarRetiro()} cargando={ocupadoRetiro}>Sí, retirar</Boton>
            </div>
          </Fragment>
        )}
      </Modal>
    </main>
  );
}

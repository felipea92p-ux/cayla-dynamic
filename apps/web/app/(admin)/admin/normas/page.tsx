"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { AdminNav } from "../nav";
import { Cargando } from "@/components/cargando";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import { TZ_LIMA, hoyLima } from "@cayla-dynamic/shared";

// Normas: los documentos que rigen para todo el equipo, y la prueba de que se
// entregaron.
//
// POR QUÉ EXISTE ESTA PANTALLA. El Reglamento Interno promete que se entrega
// «dejando constancia escrita de su recepción», y el D.S. 039-91-TR da cinco
// días naturales para esa entrega. Hasta hoy el reglamento vivía en un enlace
// de Drive —que además se cayó— y no había forma de probar quién recibió qué.
//
// Y hay algo que esto hace y el papel no puede: un cargo firmado a mano dice
// que recibiste UN reglamento; no dice cuál versión. El día que una versión
// sustituya a otra, esa es exactamente la diferencia que importa.
//
// POR QUÉ DOS VÍAS DE CONSTANCIA. Medido en producción el 2026-08-10: de 24
// personas activas, 17 tienen cuenta y 7 no. Casi un tercio del equipo no puede
// entrar al panel. Una pantalla que solo admitiera el acuse propio dejaría la
// prueba incompleta justo donde más se mira, así que DO puede registrar la
// constancia en papel de quien no tiene cuenta, con el cargo escaneado.
//
// POR QUÉ NO TODO DOCUMENTO PIDE CONSTANCIA. El reglamento y la política
// salarial crean obligaciones y la ley exige poder probar que se informaron.
// La presentación de la empresa no crea ninguna. Pedir acuse por ella enseñaría
// que el acuse es trámite, y el día que llegue el reglamento nadie lo leería.
// Lo decide `documentos_tipos.requiere_acuse`, que se administra en la base.

const DO = ["admin", "lider_do"];
const MAX_BYTES_CARGO = 50 * 1024 * 1024;
const TIPOS_CARGO = "image/jpeg,image/png,image/heic,image/webp,application/pdf";

interface Doc {
  documento_id: string;
  tipo: string;
  tipo_nombre: string;
  version: number;
  titulo: string;
  documento: string;
  vigente_desde: string;
  publicado_at: string;
  requiere_acuse: boolean;
  mi_acuse_at: string | null;
  total_acuses: number;
  poblacion: number;
}

interface FilaAcuse {
  persona_id: string;
  nombre: string;
  sede: string;
  tiene_cuenta: boolean;
  acusado_at: string | null;
  via: string | null;
}

interface Tipo {
  codigo: string;
  nombre: string;
  requiere_acuse: boolean;
}

/** Un reglamento de 61 artículos pesa cerca de 300 KB. El tope es generoso a
 *  propósito, pero existe: sin él, un archivo equivocado se sube entero antes
 *  de que nadie note que no era un documento. */
const MAX_BYTES_DOC = 2 * 1024 * 1024;

function selloLima(iso: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (isNaN(d.getTime())) return iso;
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA, day: "2-digit", month: "long", year: "numeric",
    hour: "2-digit", minute: "2-digit", hour12: true,
  }).format(d);
}

// Fecha plana: se formatea en UTC para que no se corra un día por zona horaria.
function fechaCorta(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "long", year: "numeric", timeZone: "UTC" })
    .format(new Date(Date.UTC(y, m - 1, d)));
}

/**
 * El documento se guarda como markdown y se pinta sin librería: sólo se
 * reconocen los encabezados, las citas y los párrafos. Es a propósito — el
 * texto que vale como prueba es el guardado, y cuanto menos lo transforme esta
 * pantalla, menos puede desviarse de él.
 */
function Documento({ texto }: { texto: string }) {
  const lineas = texto.split("\n");
  return (
    <div className="prose-cayla max-w-none text-[13px] leading-relaxed text-tinta">
      {lineas.map((l, i) => {
        const t = l.trim();
        if (!t) return <div key={i} className="h-2" />;
        if (t === "---") return <hr key={i} className="my-4 border-sand" />;
        if (t.startsWith("#### ")) return <h4 key={i} className="mt-4 font-serif text-sm font-medium">{t.slice(5)}</h4>;
        if (t.startsWith("### ")) return <h3 key={i} className="mt-5 font-serif text-base font-medium">{t.slice(4)}</h3>;
        if (t.startsWith("## ")) return <h2 key={i} className="mt-6 border-b border-sand pb-1 font-serif text-lg">{t.slice(3)}</h2>;
        if (t.startsWith("# ")) return <h1 key={i} className="mt-2 font-serif text-2xl">{t.slice(2)}</h1>;
        if (t.startsWith("> ")) return <p key={i} className="my-2 border-l-2 border-sand pl-3 text-xs text-taupe">{t.slice(2)}</p>;
        return <p key={i} className="my-2">{t}</p>;
      })}
    </div>
  );
}

export default function NormasPage() {
  useTituloDocumento("Normas");
  const yo = usePersonaActual();
  const puedeGestionar = yo !== null && DO.includes(yo.rol);

  const [docs, setDocs] = useState<Doc[]>([]);
  const [abierto, setAbierto] = useState<string | null>(null);
  const [cargando, setCargando] = useState(true);
  const [msg, setMsg] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [nombreDeclarado, setNombreDeclarado] = useState("");

  // El seguimiento de quién falta, sólo para quien puede verlo.
  const [acuses, setAcuses] = useState<Map<string, FilaAcuse[]>>(new Map());
  const [verSeguimiento, setVerSeguimiento] = useState<string | null>(null);

  // ── Publicar una versión ──────────────────────────────────────────────────
  // El texto NO se escribe aquí: se sube el archivo que vive en `docs/`, bajo
  // control de versiones. Pegar 277.000 caracteres a mano es justo donde se
  // pierde un trozo sin que nadie lo note, y el documento que vale como prueba
  // es el que se guarda.
  const [tipos, setTipos] = useState<Tipo[]>([]);
  const [publicando, setPublicando] = useState(false);
  const [tipoElegido, setTipoElegido] = useState("rit");
  const [archivoDoc, setArchivoDoc] = useState<{ nombre: string; texto: string } | null>(null);
  const [tituloDoc, setTituloDoc] = useState("");
  const [vigenteDesde, setVigenteDesde] = useState("");
  const [notasDoc, setNotasDoc] = useState("");

  // La constancia en papel de quien no tiene cuenta.
  const [papelPara, setPapelPara] = useState<{ doc: string; persona: string; nombre: string } | null>(null);
  const [archivo, setArchivo] = useState<File | null>(null);
  const [fechaPapel, setFechaPapel] = useState("");
  const [notaPapel, setNotaPapel] = useState("");
  const [progreso, setProgreso] = useState<number | null>(null);

  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  const cargar = useCallback(async () => {
    setCargando(true);
    // ⚠️ El error SÍ se mira. La pantalla de Disciplina no lo miraba y durante
    // días imprimió «no hay nadie» cuando lo que había era un permiso que
    // faltaba (migración 0204). Un falso «no hay documentos» sería lo mismo.
    const { data, error } = await supabase.rpc("fn_documentos_vigentes");
    if (error) {
      setMsg({ tipo: "error", texto: mensajeDeError(error, "cargar los documentos") });
      setCargando(false);
      return;
    }
    const lista = (data as unknown as Doc[]) ?? [];
    setDocs(lista);
    if (lista.length && abierto === null) setAbierto(lista[0].documento_id);
    setCargando(false);
  }, [supabase, abierto]);

  useEffect(() => { void cargar(); }, [cargar]);

  // El nombre viene puesto, pero es EDITABLE: lo que prueba no es el dato de la
  // base, es que la persona lo escriba. Eso convierte un clic en un acto
  // deliberado — la misma decisión que tomó la política salarial.
  useEffect(() => {
    if (yo?.nombreCompleto) setNombreDeclarado(yo.nombreCompleto);
  }, [yo]);

  // El catálogo de tipos: se lee de la tabla, nunca se escribe en el código.
  // Añadir «Presentación de CAYLA» tiene que ser un dato, no un despliegue.
  useEffect(() => {
    if (!puedeGestionar) return;
    void (async () => {
      const { data } = await supabase
        .from("documentos_tipos")
        .select("codigo, nombre, requiere_acuse")
        .eq("activo", true)
        .order("orden");
      setTipos((data as Tipo[]) ?? []);
    })();
  }, [supabase, puedeGestionar]);

  async function elegirArchivo(f: File | null) {
    setArchivoDoc(null);
    if (!f) return;
    if (f.size > MAX_BYTES_DOC) {
      setMsg({ tipo: "error", texto: `“${f.name}” pesa ${(f.size / 1048576).toFixed(1)} MB y el máximo es 2 MB. ¿Seguro que es el documento?` });
      return;
    }
    const texto = await f.text();
    if (!texto.trim()) {
      setMsg({ tipo: "error", texto: "El archivo está vacío." });
      return;
    }
    setArchivoDoc({ nombre: f.name, texto });
    // El título sale de la primera línea de encabezado del documento, para que
    // no haya dos verdades sobre cómo se llama.
    const h1 = texto.split("\n").find((l) => l.trim().startsWith("# "));
    if (h1 && !tituloDoc) setTituloDoc(h1.replace(/^#\s*/, "").trim());
    setMsg(null);
  }

  async function publicar() {
    if (!archivoDoc) { setMsg({ tipo: "error", texto: "Elige el archivo del documento." }); return; }
    if (!tituloDoc.trim()) { setMsg({ tipo: "error", texto: "Falta el título con el que se va a mostrar." }); return; }
    setOcupado(true); setMsg(null);
    const { data, error } = await supabase.rpc("fn_publicar_documento", {
      p_tipo: tipoElegido,
      p_titulo: tituloDoc.trim(),
      p_documento: archivoDoc.texto,
      p_vigente_desde: vigenteDesde || null,
      p_notas: notasDoc.trim() || null,
    });
    setOcupado(false);
    if (error) { setMsg({ tipo: "error", texto: mensajeDeError(error, "publicar el documento") }); return; }
    setPublicando(false); setArchivoDoc(null); setNotasDoc("");
    await cargar();
    setMsg({
      tipo: "ok",
      texto: `Publicada la versión ${String(data)}. Desde ahora cada integrante deja su constancia, y quien no tenga cuenta la deja en papel.`,
    });
  }

  async function cargarAcuses(documentoId: string) {
    const { data } = await supabase.rpc("fn_acuses_documento", { p_documento_id: documentoId });
    setAcuses((m) => new Map(m).set(documentoId, (data as unknown as FilaAcuse[]) ?? []));
  }

  async function acusar(d: Doc) {
    if (!nombreDeclarado.trim()) {
      setMsg({ tipo: "error", texto: "Escribe tu nombre para dejar constancia." });
      return;
    }
    setOcupado(true); setMsg(null);
    const { error } = await supabase.rpc("fn_acusar_documento", {
      p_documento_id: d.documento_id,
      p_nombre_declarado: nombreDeclarado.trim(),
    });
    setOcupado(false);
    if (error) { setMsg({ tipo: "error", texto: mensajeDeError(error) }); return; }
    await cargar();
    setMsg({ tipo: "ok", texto: "Constancia registrada. No hace falta hacer nada más hasta que se publique una versión nueva." });
  }

  async function guardarPapel() {
    if (!papelPara) return;
    if (!archivo) {
      setMsg({ tipo: "error", texto: "Falta el cargo firmado escaneado. Sin el papel no hay constancia que registrar." });
      return;
    }
    if (archivo.size > MAX_BYTES_CARGO) {
      setMsg({ tipo: "error", texto: `“${archivo.name}” pesa ${(archivo.size / 1048576).toFixed(1)} MB y el máximo es 50 MB.` });
      return;
    }
    setOcupado(true); setMsg(null);
    // La ruta cuelga del documento y de la persona: así no hay forma de
    // archivar el cargo contra la versión equivocada.
    const ext = archivo.name.split(".").pop()?.toLowerCase() ?? "bin";
    const ruta = `${papelPara.doc}/${papelPara.persona}-${Date.now()}.${ext}`;

    setProgreso(0);
    const fallo = await subirArchivoConProgreso(supabase, "acuses", ruta, archivo, setProgreso);
    setProgreso(null);
    if (fallo) {
      setOcupado(false);
      setMsg({ tipo: "error", texto: `El archivo no subió (${fallo}). Vuelve a intentarlo.` });
      return;
    }

    const { error } = await supabase.rpc("fn_registrar_acuse_papel", {
      p_documento_id: papelPara.doc,
      p_persona_id: papelPara.persona,
      p_path: ruta,
      // La fecha buena es la del papel, no la de hoy: de la recepción cuelgan
      // los plazos, y entre firmar y escanear pueden pasar días.
      p_acusado_at: fechaPapel ? new Date(`${fechaPapel}T12:00:00-05:00`).toISOString() : null,
      p_nota: notaPapel.trim() || null,
    });
    setOcupado(false);
    if (error) { setMsg({ tipo: "error", texto: mensajeDeError(error) }); return; }
    const doc = papelPara.doc;
    setPapelPara(null); setArchivo(null); setNotaPapel("");
    await cargar();
    await cargarAcuses(doc);
    setMsg({ tipo: "ok", texto: "Constancia en papel registrada, con su cargo archivado." });
  }

  async function verCargo(path: string) {
    // URL firmada de vida corta: el almacén es privado y son papeles firmados.
    const { data, error } = await supabase.storage.from("acuses").createSignedUrl(path, 60);
    if (error || !data) { setMsg({ tipo: "error", texto: `No se pudo abrir: ${error?.message ?? "sin URL"}` }); return; }
    window.open(data.signedUrl, "_blank", "noopener,noreferrer");
  }

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <h1 className="mb-1 font-serif text-2xl">Normas</h1>
        <p className="mb-5 max-w-2xl text-sm text-taupe">
          Los documentos que rigen para todo el equipo. Aquí se leen, y aquí queda la constancia
          de que se recibieron — con la <strong>versión</strong>, que es lo que un papel firmado no dice.
        </p>

        {msg && (
          <div className={`mb-4 max-w-2xl rounded-lg px-4 py-3 text-sm ${msg.tipo === "ok" ? "bg-sand/40 text-tinta" : "bg-rojo/10 text-rojo"}`}>
            {msg.texto}
          </div>
        )}

        {/* ── Publicar, sólo para quien puede ── */}
        {puedeGestionar && (
          <div className="mb-5 max-w-3xl overflow-hidden rounded-2xl border border-sand bg-papel">
            <button onClick={() => setPublicando((v) => !v)}
              className="flex w-full items-center justify-between border-b bg-sand/50 px-4 py-2 text-left text-sm font-medium">
              <span>Publicar una versión</span>
              <span className="text-xs font-normal text-taupe">{publicando ? "ocultar" : "abrir"}</span>
            </button>
            {publicando && (
              <div className="px-4 py-3">
                <p className="mb-3 text-xs text-taupe">
                  El documento se sube desde su archivo, no se escribe aquí: el texto vive versionado
                  en el repositorio y así no hay dos verdades. Publicar el <strong>mismo</strong> texto no
                  crea versión nueva — pedir constancia sin que nada cambie enseña que la constancia es trámite.
                </p>
                <div className="grid gap-2 sm:grid-cols-2">
                  <label className="flex flex-col gap-1 text-xs">
                    Tipo de documento
                    <select value={tipoElegido} onChange={(e) => setTipoElegido(e.target.value)}
                      className="rounded border bg-crema px-2 py-1 text-xs">
                      {tipos.map((t) => (
                        <option key={t.codigo} value={t.codigo}>
                          {t.nombre}{t.requiere_acuse ? "" : " (sin constancia)"}
                        </option>
                      ))}
                    </select>
                  </label>
                  <label className="flex flex-col gap-1 text-xs">
                    Archivo (.md o .txt)
                    <input type="file" accept=".md,.txt,text/markdown,text/plain"
                      onChange={(e) => void elegirArchivo(e.target.files?.[0] ?? null)}
                      className="rounded border bg-crema px-2 py-1 text-xs file:mr-2 file:rounded file:border-0 file:bg-sand file:px-2 file:py-0.5 file:text-xs" />
                  </label>
                  <label className="flex flex-col gap-1 text-xs">
                    Título con el que se muestra
                    <input value={tituloDoc} onChange={(e) => setTituloDoc(e.target.value)}
                      placeholder="Reglamento Interno de Trabajo"
                      className="rounded border px-2 py-1 text-xs" />
                  </label>
                  <label className="flex flex-col gap-1 text-xs">
                    Rige desde
                    <input type="date" value={vigenteDesde} onChange={(e) => setVigenteDesde(e.target.value)}
                      className="rounded border px-2 py-1 text-xs" />
                    <span className="text-taupe">Si lo dejas vacío, rige desde hoy.</span>
                  </label>
                  <label className="flex flex-col gap-1 text-xs sm:col-span-2">
                    Nota de la versión (opcional)
                    <input value={notasDoc} onChange={(e) => setNotasDoc(e.target.value)}
                      placeholder="ej. sustituye a la v3.0 de junio de 2026"
                      className="rounded border px-2 py-1 text-xs" />
                  </label>
                </div>

                {archivoDoc && (
                  <div className="mt-3 rounded-lg border border-sand bg-crema/40 p-3">
                    <p className="text-xs text-taupe">
                      <strong>{archivoDoc.nombre}</strong> · {archivoDoc.texto.length.toLocaleString("es-PE")} caracteres ·{" "}
                      {archivoDoc.texto.split("\n").filter((l) => /^#{1,4}\s*ART[IÍ]CULO/i.test(l.trim())).length} artículos detectados
                    </p>
                    <div className="mt-2 max-h-40 overflow-y-auto text-[11px] leading-relaxed text-tinta">
                      <Documento texto={archivoDoc.texto.slice(0, 1200)} />
                    </div>
                    <p className="mt-1 text-xs text-taupe">Vista previa del principio, para comprobar que es el archivo correcto.</p>
                  </div>
                )}

                <div className="mt-3 flex items-center gap-2">
                  <button onClick={() => void publicar()} disabled={ocupado || !archivoDoc}
                    className="rounded-lg bg-tinta px-3 py-1.5 text-xs font-medium text-crema disabled:opacity-40">
                    Publicar
                  </button>
                  <button onClick={() => { setPublicando(false); setArchivoDoc(null); }}
                    className="rounded-lg border px-3 py-1.5 text-xs">Cancelar</button>
                </div>
              </div>
            )}
          </div>
        )}

        {cargando ? (
          <Cargando texto="Cargando los documentos…" />
        ) : docs.length === 0 ? (
          <p className="max-w-xl rounded-2xl border border-sand bg-papel px-4 py-6 text-sm text-taupe">
            Todavía no hay ningún documento publicado.
            {puedeGestionar && " Publica el primero con el botón de arriba."}
          </p>
        ) : (
          <div className="space-y-4">
            {docs.map((d) => {
              const filas = acuses.get(d.documento_id) ?? [];
              const pendientes = filas.filter((f) => f.acusado_at === null);
              return (
                <div key={d.documento_id} className="max-w-4xl overflow-hidden rounded-2xl border border-sand bg-papel">
                  <button
                    onClick={() => setAbierto(abierto === d.documento_id ? null : d.documento_id)}
                    className="flex w-full items-center justify-between gap-3 border-b bg-sand/50 px-4 py-3 text-left">
                    <span>
                      <span className="font-medium">{d.titulo}</span>
                      <span className="ml-2 text-xs text-taupe">
                        versión {d.version} · rige desde {fechaCorta(d.vigente_desde)}
                      </span>
                    </span>
                    <span className="flex items-center gap-2 text-xs">
                      {!d.requiere_acuse ? (
                        <span className="text-taupe">solo lectura</span>
                      ) : d.mi_acuse_at ? (
                        <span className="rounded-full bg-sand px-2 py-0.5 text-tinta">tu constancia está</span>
                      ) : (
                        <span className="rounded-full bg-rojo/10 px-2 py-0.5 text-rojo">falta tu constancia</span>
                      )}
                      <span className="text-taupe">{abierto === d.documento_id ? "ocultar" : "leer"}</span>
                    </span>
                  </button>

                  {abierto === d.documento_id && (
                    <div className="px-4 py-4">
                      <div className="max-h-[28rem] overflow-y-auto rounded-lg border border-sand bg-crema/40 px-4 py-3">
                        <Documento texto={d.documento} />
                      </div>

                      {/* ── La constancia propia ── */}
                      {d.requiere_acuse && (
                        <div className="mt-4 rounded-lg border border-sand bg-sand/20 p-3">
                          {d.mi_acuse_at ? (
                            <p className="text-xs text-taupe">
                              Dejaste constancia el <strong>{selloLima(d.mi_acuse_at)}</strong>. No hace falta
                              hacer nada más hasta que se publique una versión nueva. Si algo de este documento
                              no te cuadra, puedes plantearlo a la Gerencia y recibirás respuesta por escrito.
                            </p>
                          ) : (
                            <>
                              <p className="mb-2 text-xs text-taupe">
                                Dejar constancia significa que recibiste este documento y fuiste informada de su
                                contenido. No es una firma de conformidad ni renuncia a nada.
                              </p>
                              <div className="flex flex-wrap items-end gap-2">
                                <label className="flex flex-col gap-1 text-xs">
                                  Tu nombre
                                  <input value={nombreDeclarado} onChange={(e) => setNombreDeclarado(e.target.value)}
                                    className="rounded border px-2 py-1 text-xs" />
                                </label>
                                <button onClick={() => void acusar(d)} disabled={ocupado}
                                  className="rounded-lg bg-tinta px-3 py-1.5 text-xs font-medium text-crema disabled:opacity-40">
                                  Dejar constancia
                                </button>
                              </div>
                            </>
                          )}
                        </div>
                      )}

                      {/* ── El seguimiento, sólo para quien manda ── */}
                      {puedeGestionar && d.requiere_acuse && (
                        <div className="mt-4">
                          <button
                            onClick={() => {
                              const nuevo = verSeguimiento === d.documento_id ? null : d.documento_id;
                              setVerSeguimiento(nuevo);
                              if (nuevo) void cargarAcuses(nuevo);
                            }}
                            className="text-xs font-medium underline">
                            {d.total_acuses} de {d.poblacion} han dejado constancia
                            {d.total_acuses < d.poblacion && ` · faltan ${d.poblacion - d.total_acuses}`}
                            {verSeguimiento === d.documento_id ? " · ocultar" : " · ver quién"}
                          </button>

                          {verSeguimiento === d.documento_id && (
                            <ul className="mt-2 divide-y rounded-lg border border-sand">
                              {filas.map((f) => (
                                <li key={f.persona_id} className="flex flex-wrap items-center justify-between gap-2 px-3 py-2 text-xs">
                                  <span>
                                    {f.nombre} <span className="text-taupe">· {f.sede}</span>
                                    {!f.tiene_cuenta && <span className="ml-2 rounded-full bg-sand px-2 py-0.5 text-taupe">sin cuenta</span>}
                                  </span>
                                  {f.acusado_at ? (
                                    <span className="text-taupe">
                                      {selloLima(f.acusado_at)} · {f.via === "papel" ? "en papel" : "desde el sistema"}
                                    </span>
                                  ) : (
                                    <button
                                      onClick={() => {
                                        setPapelPara({ doc: d.documento_id, persona: f.persona_id, nombre: f.nombre });
                                        setArchivo(null); setFechaPapel(hoyLima()); setNotaPapel(""); setMsg(null);
                                      }}
                                      className="rounded border border-tinta/30 px-2 py-0.5 text-tinta hover:bg-sand/40">
                                      registrar su cargo en papel
                                    </button>
                                  )}
                                </li>
                              ))}
                              {filas.length === 0 && <li className="px-3 py-2 text-xs text-taupe">Sin datos.</li>}
                            </ul>
                          )}

                          {pendientes.length > 0 && verSeguimiento === d.documento_id && (
                            <p className="mt-2 text-xs text-taupe">
                              Quien no tiene cuenta deja constancia en papel: se le entrega el documento impreso,
                              firma el cargo y aquí se archiva el escaneo.
                            </p>
                          )}
                        </div>
                      )}

                      {/* ── El formulario del cargo en papel ── */}
                      {papelPara && papelPara.doc === d.documento_id && (
                        <div className="mt-3 rounded-lg border border-sand bg-sand/20 p-3">
                          <p className="mb-2 text-xs text-taupe">
                            Constancia en papel de <strong>{papelPara.nombre}</strong>. Sin el escaneo del cargo
                            firmado no se registra: aquí la constancia es la prueba.
                          </p>
                          <div className="grid gap-2 sm:grid-cols-2">
                            <label className="flex flex-col gap-1 text-xs">
                              Cargo firmado
                              <input type="file" accept={TIPOS_CARGO}
                                onChange={(e) => setArchivo(e.target.files?.[0] ?? null)}
                                className="rounded border bg-crema px-2 py-1 text-xs file:mr-2 file:rounded file:border-0 file:bg-sand file:px-2 file:py-0.5 file:text-xs" />
                            </label>
                            <label className="flex flex-col gap-1 text-xs">
                              Fecha de recepción
                              <input type="date" value={fechaPapel} max={hoyLima()}
                                onChange={(e) => setFechaPapel(e.target.value)}
                                className="rounded border px-2 py-1 text-xs" />
                            </label>
                            <label className="flex flex-col gap-1 text-xs sm:col-span-2">
                              Nota (opcional)
                              <input value={notaPapel} onChange={(e) => setNotaPapel(e.target.value)}
                                placeholder="ej. entregado en la tienda, con la encargada presente"
                                className="rounded border px-2 py-1 text-xs" />
                            </label>
                          </div>
                          {progreso !== null && (
                            <div className="mt-2">
                              <div className="h-1.5 w-full overflow-hidden rounded-full bg-sand">
                                <div className="h-full bg-tinta transition-[width] duration-200" style={{ width: `${progreso}%` }}
                                  role="progressbar" aria-valuenow={progreso} aria-valuemin={0} aria-valuemax={100}
                                  aria-label="Subiendo el cargo" />
                              </div>
                              <span className="text-xs text-taupe">Subiendo — {progreso}%</span>
                            </div>
                          )}
                          <div className="mt-2 flex items-center gap-2">
                            <button onClick={() => void guardarPapel()} disabled={ocupado}
                              className="rounded-lg bg-tinta px-3 py-1 text-xs font-medium text-crema disabled:opacity-40">
                              {progreso !== null ? `Subiendo… ${progreso}%` : "Registrar constancia"}
                            </button>
                            <button onClick={() => setPapelPara(null)} className="rounded-lg border px-3 py-1 text-xs">
                              Cancelar
                            </button>
                          </div>
                        </div>
                      )}

                      {/* ── Los cargos ya archivados ── */}
                      {puedeGestionar && verSeguimiento === d.documento_id && filas.some((f) => f.via === "papel") && (
                        <p className="mt-3 text-xs text-taupe">
                          Cargos archivados:{" "}
                          {filas.filter((f) => f.via === "papel").map((f) => (
                            <button key={f.persona_id}
                              onClick={() => void verCargo(`${d.documento_id}/${f.persona_id}`)}
                              className="mr-2 font-medium underline">{f.nombre}</button>
                          ))}
                        </p>
                      )}

                      <p className="mt-4 text-xs text-taupe">
                        Publicado el {selloLima(d.publicado_at)} · {d.tipo_nombre}
                      </p>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </main>
    </div>
  );
}

"use client";

// ============================================================================
// Los archivos de una póliza — la póliza, el convenio de pago y la factura
// ============================================================================
// QUÉ PROMETE
//   Subir, abrir y retirar los PDF (o fotos) de UNA póliza, con quién los subió y
//   cuándo. Migración 0528: `fn_seguro_adjuntar` y `fn_seguro_retirar_archivo`.
//
// EL ARCHIVO VA PRIMERO (el molde de Archivo, 0503)
//   Se sube al bucket y recién después se registra. Si Storage cae, no queda
//   ninguna fila; si el registro falla después de subir, se intenta borrar el
//   huérfano (la política lo permite porque nadie lo usa).
//
// POR QUÉ LA RUTA NO LLEVA EL NOMBRE
//   El PDF de una póliza se llama «Apellidos, Nombres, FOLA 24043267.pdf»: lleva
//   un nombre de persona. La ruta en el almacén es `<uuid>.<ext>` y nada más
//   (la base lo exige); el nombre original solo se guarda como dato.
// ============================================================================

import { useCallback, useEffect, useState } from "react";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { fechaLima } from "@cayla-dynamic/shared";
import { Cargando } from "@/components/cargando";
import { useToast } from "@/components/toast";
import { AreaTexto } from "@/components/ui/area-texto";
import { Boton } from "@/components/ui/boton";
import { CampoSelect } from "@/components/ui/campo";
import { Insignia } from "@/components/ui/insignia";
import { Modal } from "@/components/ui/modal";
import { abrirArchivoFirmado } from "@/lib/abrir-archivo-firmado";
import { problemaDeArchivo, rutaNuevaArchivo, TIPOS_ARCHIVO } from "@/lib/admin/archivo";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { isoADiaMesAnio } from "@/lib/admin/planilla/formato";
import { BUCKET_SEGUROS, etiquetaTipoArchivo, loVeLaPracticante, TIPOS_ARCHIVO_SEGURO, type TipoArchivoSeguro } from "@/lib/admin/seguros";
import { pesoLegible } from "@/lib/reducir-imagen";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";

interface ArchivoDePoliza {
  id: string; tipo: string; storage_path: string; nombre_archivo: string; mime: string; bytes: number;
  subido_por_nombre: string | null; subido_at: string;
  retirado_at: string | null; retirado_por_nombre: string | null; retirado_motivo: string | null;
}

const dia = (ts: string) => isoADiaMesAnio(fechaLima(ts));

export function ArchivosPoliza({
  abierto, onCerrar, supabase, polizaId, titulo, onCambio,
}: {
  abierto: boolean;
  onCerrar: () => void;
  supabase: ClienteCayla;
  polizaId: string | null;
  /** «Ana Prueba · póliza 24043267». */
  titulo: string;
  /** Avisa a la pantalla que cambió algo, para que recargue sus contadores. */
  onCambio: () => void;
}) {
  return (
    <Modal abierto={abierto && polizaId !== null} onCerrar={onCerrar} titulo="Archivos de la póliza" ancho="lg">
      {abierto && polizaId && <Cuerpo supabase={supabase} polizaId={polizaId} titulo={titulo} onCambio={onCambio} onCerrar={onCerrar} />}
    </Modal>
  );
}

function Cuerpo({
  supabase, polizaId, titulo, onCambio, onCerrar,
}: { supabase: ClienteCayla; polizaId: string; titulo: string; onCambio: () => void; onCerrar: () => void }) {
  const { avisar } = useToast();
  const [archivos, setArchivos] = useState<ArchivoDePoliza[]>([]);
  const [cargando, setCargando] = useState(true);
  const [cargaError, setCargaError] = useState<string | null>(null);

  const cargar = useCallback(async () => {
    const { data, error } = await supabase.rpc("fn_seguro_archivos", { p_poliza_id: polizaId });
    setArchivos((data as ArchivoDePoliza[] | null) ?? []);
    setCargaError(error ? mensajeDeError(error, "cargar los archivos") : null);
    setCargando(false);
  }, [supabase, polizaId]);

  // `cargar` solo pone estado después de su `await`: no hay renders en cascada.
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargar(); }, [cargar]);

  // ── Subir ─────────────────────────────────────────────────────────────
  const [tipo, setTipo] = useState<TipoArchivoSeguro>("poliza");
  const [archivo, setArchivo] = useState<File | null>(null);
  const [claveInput, setClaveInput] = useState(0);
  const [msg, setMsg] = useState<string | null>(null);
  const [progreso, setProgreso] = useState<number | null>(null);
  const [subiendo, setSubiendo] = useState(false);

  async function subir() {
    setMsg(null);
    if (!archivo) { setMsg("Elige el archivo: un PDF o una foto."); return; }
    const problema = problemaDeArchivo(archivo);
    if (problema) { setMsg(problema); return; }

    setSubiendo(true);
    const ruta = rutaNuevaArchivo(archivo.name, archivo.type, crypto.randomUUID());
    setProgreso(0);
    const fallo = await subirArchivoConProgreso(supabase, BUCKET_SEGUROS, ruta, archivo, setProgreso);
    setProgreso(null);
    if (fallo) { setSubiendo(false); setMsg(`El archivo no subió (${fallo}). Vuelve a intentarlo.`); return; }

    const { error } = await supabase.rpc("fn_seguro_adjuntar", {
      p_poliza_id: polizaId, p_tipo: tipo, p_storage_path: ruta, p_nombre_archivo: archivo.name,
    });
    if (error) {
      // Subió y no se registró: se limpia el huérfano; si no se puede, queda
      // suelto sin hacer daño (nadie lo ve ni lo usa).
      await supabase.storage.from(BUCKET_SEGUROS).remove([ruta]);
      setSubiendo(false);
      setMsg(mensajeDeError(error, "guardar"));
      return;
    }
    setSubiendo(false);
    setArchivo(null); setClaveInput((n) => n + 1);
    await cargar();
    onCambio();
    avisar("ok", "Archivo guardado.");
  }

  // ── Retirar ───────────────────────────────────────────────────────────
  const [retirando, setRetirando] = useState<string | null>(null);
  const [motivo, setMotivo] = useState("");
  const [msgRetiro, setMsgRetiro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  async function retirar(id: string) {
    if (motivo.trim().length < 5) { setMsgRetiro("Escribe el motivo (al menos 5 letras)."); return; }
    setOcupado(true);
    const { error } = await supabase.rpc("fn_seguro_retirar_archivo", { p_id: id, p_motivo: motivo.trim() });
    setOcupado(false);
    if (error) { setMsgRetiro(mensajeDeError(error)); return; }
    setRetirando(null); setMotivo("");
    await cargar();
    onCambio();
    avisar("ok", "Archivo retirado. Sigue guardado, a la vista del historial.");
  }

  async function abrir(a: ArchivoDePoliza) {
    const fallo = await abrirArchivoFirmado(supabase, BUCKET_SEGUROS, a.storage_path, 120);
    if (fallo) avisar("error", fallo);
  }

  const vigentes = archivos.filter((a) => !a.retirado_at);
  const retirados = archivos.filter((a) => a.retirado_at);

  return (
    <>
      <p className="mb-1 text-sm text-taupe">
        {titulo}. Los PDF llevan DNI y fecha de nacimiento. La póliza y el convenio de pago los ve también la
        practicante, solo los suyos, en «Lo mío → Mi seguro»; la factura y «Otro papel» los ve solo Desarrollo
        Organizacional.
      </p>
      <p className="mb-4 text-sm text-taupe">
        Sube a esta póliza solo el PDF de esta persona: si el archivo trae las pólizas de varias, ella las verá todas.
      </p>
      {cargando ? <Cargando /> : cargaError ? (
        <div className="mb-3 rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
          {cargaError} <Boton variante="enlace" onClick={() => void cargar()}>Reintentar</Boton>
        </div>
      ) : (
        <>
          {vigentes.length === 0 ? (
            <p className="mb-4 rounded-lg bg-hueso px-3 py-3 text-sm text-taupe">
              Esta póliza no tiene archivos todavía. Sube la póliza y el convenio de pago que mandó el corredor.
            </p>
          ) : (
            <ul className="mb-4 space-y-2">
              {vigentes.map((a) => (
                <li key={a.id} className="rounded-xl border border-sand bg-papel px-4 py-3">
                  <div className="flex flex-wrap items-start justify-between gap-2">
                    <div className="min-w-0 flex-1">
                      <p className="break-words text-sm text-tinta">
                        <Insignia variante="neutral" tamano="sm" className="mr-1.5">{etiquetaTipoArchivo(a.tipo)}</Insignia>
                        {a.nombre_archivo}
                      </p>
                      <p className="mt-0.5 text-xs text-taupe">
                        {pesoLegible(a.bytes)} · subido el {dia(a.subido_at)}{a.subido_por_nombre && ` por ${a.subido_por_nombre}`}
                      </p>
                    </div>
                    <div className="flex items-center gap-2">
                      <Boton variante="primario" tamano="sm" onClick={() => void abrir(a)}>Abrir</Boton>
                      <Boton variante="sutil" tamano="sm" onClick={() => { setRetirando(retirando === a.id ? null : a.id); setMotivo(""); setMsgRetiro(null); }}>
                        Retirar
                      </Boton>
                    </div>
                  </div>
                  {retirando === a.id && (
                    <div className="mt-3 border-t border-sand pt-3">
                      <label className="flex flex-col gap-1">
                        <span className="text-sm text-taupe">Por qué se retira</span>
                        <AreaTexto
                          value={motivo}
                          onChange={(e) => { setMotivo(e.target.value); setMsgRetiro(null); }}
                          placeholder="ej. Era el convenio de otra persona"
                          className={msgRetiro ? "border-rojo" : undefined}
                        />
                        {msgRetiro && <span className="text-xs text-rojo">{msgRetiro}</span>}
                      </label>
                      <div className="mt-2 flex justify-end gap-2">
                        <Boton tamano="sm" onClick={() => setRetirando(null)} disabled={ocupado}>Cancelar</Boton>
                        <Boton variante="peligro" tamano="sm" onClick={() => void retirar(a.id)} cargando={ocupado}>Sí, retirar</Boton>
                      </div>
                    </div>
                  )}
                </li>
              ))}
            </ul>
          )}

          <div className="rounded-xl border border-sand bg-hueso px-4 py-4">
            <p className="mb-3 text-sm text-tinta">Subir un archivo</p>
            {msg && <p role="alert" className="mb-3 rounded border border-rojo/30 bg-rojo/10 px-3 py-2 text-sm text-rojo">{msg}</p>}
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
              <CampoSelect etiqueta="Qué es" value={tipo} onChange={(e) => setTipo(e.target.value as TipoArchivoSeguro)}>
                {TIPOS_ARCHIVO_SEGURO.map((t) => <option key={t.valor} value={t.valor}>{t.etiqueta}</option>)}
              </CampoSelect>
              <label className="flex min-w-0 flex-col gap-1 sm:col-span-2">
                <span className="text-sm text-taupe">Archivo</span>
                <input
                  key={claveInput}
                  type="file"
                  accept={TIPOS_ARCHIVO}
                  onChange={(e) => { setArchivo(e.target.files?.[0] ?? null); setMsg(null); }}
                  className="w-full min-w-0 rounded-control border border-sand bg-papel px-3 py-2 text-sm text-tinta file:mr-2 file:rounded file:border-0 file:bg-sand file:px-2 file:py-0.5 file:text-xs file:text-tinta"
                />
                <span className="text-xs text-taupe">
                  {archivo ? `${archivo.name} · ${pesoLegible(archivo.size)}` : "Un PDF o una foto, hasta 50 MB."}
                </span>
              </label>
              <p className="text-xs text-taupe sm:col-span-3">
                {loVeLaPracticante(tipo)
                  ? "La practicante podrá abrirlo desde «Lo mío», en «Mi seguro»."
                  : "Solo lo ve Desarrollo Organizacional."}
              </p>
            </div>
            {progreso !== null && (
              <div className="mt-3">
                <div className="h-1.5 w-full overflow-hidden rounded-pildora bg-sand">
                  <div className="h-full bg-tinta transition-[width] duration-200" style={{ width: `${progreso}%` }} />
                </div>
                <span className="text-xs text-taupe">Subiendo — {progreso}%</span>
              </div>
            )}
            <div className="mt-3 flex justify-end">
              <Boton variante="primario" onClick={() => void subir()} cargando={subiendo}>
                {progreso !== null ? `Subiendo… ${progreso}%` : "Guardar el archivo"}
              </Boton>
            </div>
          </div>

          {retirados.length > 0 && (
            <div className="mt-4">
              <p className="mb-2 text-xs uppercase tracking-wide text-taupe">Retirados</p>
              <ul className="space-y-2">
                {retirados.map((a) => (
                  <li key={a.id} className="rounded-lg border border-sand bg-hueso px-3 py-2 text-sm text-taupe">
                    <span className="text-tinta">{etiquetaTipoArchivo(a.tipo)}: {a.nombre_archivo}</span>
                    <span className="block text-xs">
                      Retirado el {a.retirado_at ? dia(a.retirado_at) : "—"}
                      {a.retirado_por_nombre && ` por ${a.retirado_por_nombre}`}: «{a.retirado_motivo}» ·{" "}
                      <Boton variante="enlace" onClick={() => void abrir(a)}>abrir</Boton>
                    </span>
                  </li>
                ))}
              </ul>
            </div>
          )}
        </>
      )}
      <div className="mt-5 flex justify-end"><Boton onClick={onCerrar}>Cerrar</Boton></div>
    </>
  );
}

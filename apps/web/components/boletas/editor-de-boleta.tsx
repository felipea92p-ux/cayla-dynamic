"use client";

import { useEffect, useRef, useState } from "react";
import { FileText } from "lucide-react";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { Modal } from "@/components/ui/modal";
import { Boton } from "@/components/ui/boton";
import { Cargando } from "@/components/cargando";
import { useToast } from "@/components/toast";
import { PieDeModal, TACTIL } from "@/components/boletas/pie-de-modal";
import {
  BUCKET_BOLETAS, CALIDAD_JPEG_FOTO, LADO_MAYOR_FOTO_PX, TOPE_ARCHIVO_BYTES, TOPE_BOLETA_BYTES,
  cambiosEntreVersiones, editaAvisa, etiquetaDeHojas, extensionPorMime, problemaConLasHojas,
  rutaDeHoja, sumaDeBytes, type TipoBoleta,
} from "@/lib/boletas";
import { hojasFirmadasDeVersion } from "@/lib/boletas-archivos";
import { casillaAvisar, type FilaTablero } from "@/lib/admin/boletas-pantalla";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { comprimirImagen } from "@/lib/comprimir-imagen";
import { pesoLegible } from "@/lib/reducir-imagen";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import { tipoDeArchivo } from "@/lib/tipos-archivo";

// ============================================================================
// EDITOR DE UNA BOLETA — subir la primera vez, o editar una que ya existe
// ============================================================================
//
// PROMETE: deja a DO armar la lista ORDENADA de hojas (fotos o PDF) de una
//   boleta, verla antes de guardar, y guardarla como versión nueva. Nunca deja
//   una boleta a medias: primero suben TODAS las hojas nuevas y solo cuando la
//   última llegó se llama a la base. Si una falla, se dice cuál y NO se toca la
//   base (las ya subidas quedan sin usar, que es inofensivo).
// ASUME: `fn_boleta_guardar_version` (0482) vuelve a comprobar todo lo que aquí
//   se comprueba, y gana. Aquí solo se adelanta el mensaje.
//
// POR QUÉ LAS HOJAS QUE YA EXISTÍAN NO SE VUELVEN A SUBIR
//   Editar una boleta crea la versión N+1, que reutiliza las hojas que se
//   conservan MANDANDO SU MISMA RUTA. Una hoja con ruta ya está en el almacén y
//   es inmutable: subirla otra vez sería gastar los datos móviles de quien
//   trabaja desde el celular para dejar exactamente lo mismo.
//
// POR QUÉ UNA FOTO GIRA DESDE EL ORIGINAL
//   Cada giro vuelve a comprimir desde el archivo que eligió la persona, con el
//   giro acumulado (0/90/180/270). Girar sobre la foto ya comprimida sería
//   comprimir un JPG de un JPG cuatro veces para volver al punto de partida.
// ============================================================================

type Giro = 0 | 90 | 180 | 270;

type HojaExistente = {
  clave: string;
  origen: "existente";
  ruta: string;
  mime: string;
  bytes: number;
  url: string;
};

type HojaNueva = {
  clave: string;
  origen: "nueva";
  nombre: string;
  /** Lo que eligió la persona, sin tocar: de aquí se vuelve a comprimir al girar. */
  original: File;
  /** Lo que se sube: la foto ya reducida a JPG, o el PDF tal cual. */
  blob: Blob;
  mime: string;
  bytes: number;
  vista: string | null;
  giro: Giro;
  procesando: boolean;
  /** Si ya subió (y el guardado falló después), no se repite al reintentar. */
  rutaSubida: string | null;
};

type Hoja = HojaExistente | HojaNueva;

let contadorDeClaves = 0;
const nuevaClave = () => `h${++contadorDeClaves}`;

export function EditorDeBoleta({
  supabase,
  fila,
  periodoId,
  nombreDelPeriodo,
  onCerrar,
  onGuardado,
}: {
  supabase: ClienteCayla;
  fila: FilaTablero;
  periodoId: string;
  nombreDelPeriodo: string;
  onCerrar: () => void;
  onGuardado: () => void;
}) {
  const { avisar } = useToast();

  // Se edita la versión vigente de una boleta que NO está anulada. Una anulada
  // que se vuelve a subir arranca vacía: es otro documento.
  const editando = fila.version_id !== null && (fila.estado === "borrador" || fila.estado === "publicada");
  const publicada = editando && fila.estado === "publicada";

  const [tipo, setTipo] = useState<TipoBoleta>(editando && fila.tipo === "pdf" ? "pdf" : "imagen");
  const [hojas, setHojas] = useState<Hoja[]>([]);
  const [vigentes, setVigentes] = useState<string[]>([]);
  const [mas, setMas] = useState(false);
  const [cargandoActuales, setCargandoActuales] = useState(editando);
  const [errorActuales, setErrorActuales] = useState<string | null>(null);
  const [reintento, setReintento] = useState(0);
  const [preparando, setPreparando] = useState(false);
  const [vi, setVi] = useState(false);
  const [quiereAvisar, setQuiereAvisar] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [guardando, setGuardando] = useState(false);
  const [progreso, setProgreso] = useState<{ actual: number; total: number; pct: number } | null>(null);

  const entradaDeArchivo = useRef<HTMLInputElement>(null);
  // Todas las direcciones de vista previa creadas, para soltarlas al cerrar.
  const urlsCreadas = useRef<string[]>([]);
  useEffect(() => {
    const urls = urlsCreadas.current;
    return () => { urls.forEach((u) => URL.revokeObjectURL(u)); };
  }, []);

  // Al EDITAR se precargan las hojas de la versión vigente. Para DO esto no marca nada (0482).
  useEffect(() => {
    if (!editando || fila.version_id === null) return;
    let vigente = true;
    void hojasFirmadasDeVersion(supabase, fila.version_id, 3600).then(({ hojas: h, error: e }) => {
      if (!vigente) return;
      if (e) { setErrorActuales(e); setCargandoActuales(false); return; }
      setErrorActuales(null);
      setHojas(h.map((x) => ({ clave: nuevaClave(), origen: "existente" as const, ruta: x.ruta, mime: x.mime, bytes: x.bytes, url: x.url })));
      setVigentes(h.map((x) => x.ruta));
      setMas(h.length > 1);
      setCargandoActuales(false);
    });
    return () => { vigente = false; };
  }, [editando, fila.version_id, supabase, reintento]);

  // Un guardado en curso no se pierde por cerrar la pestaña sin querer.
  useEffect(() => {
    if (!guardando) return;
    const avisarAlSalir = (e: BeforeUnloadEvent) => { e.preventDefault(); };
    window.addEventListener("beforeunload", avisarAlSalir);
    return () => window.removeEventListener("beforeunload", avisarAlSalir);
  }, [guardando]);

  const esFoto = tipo === "imagen";
  const rutasActuales = hojas.map((h) => (h.origen === "existente" ? h.ruta : `nueva:${h.clave}`));
  const cambios = editando
    ? cambiosEntreVersiones(vigentes, rutasActuales)
    : { contenido: true, orden: false, igual: false };
  const casilla = casillaAvisar({ publicada, cambios, quiereAvisar });
  const total = sumaDeBytes(hojas);
  const pasaElTope = total > TOPE_BOLETA_BYTES;
  const hayNuevas = hojas.some((h) => h.origen === "nueva");
  const ocupado = guardando || preparando || hojas.some((h) => h.origen === "nueva" && h.procesando);
  const numeroDeVersion = (fila.version_n ?? 0) + 1;

  function soltarVista(h: Hoja | undefined) {
    if (h && h.origen === "nueva" && h.vista) URL.revokeObjectURL(h.vista);
  }

  async function agregar(archivos: File[]) {
    if (archivos.length === 0) return;
    setError(null);
    // Sin la casilla «más de una», elegir otro archivo REEMPLAZA: nunca se acumulan por descuido.
    const lista = mas ? archivos : archivos.slice(0, 1);
    setPreparando(true);

    const nuevas: HojaNueva[] = [];
    let problema: string | null = null;
    for (const f of lista) {
      const mime = tipoDeArchivo(f.name, f.type);
      if (esFoto) {
        if (!mime.startsWith("image/")) { problema = `«${f.name}» no es una foto. Sube una imagen (JPG, PNG o HEIC).`; continue; }
        if (f.size > TOPE_ARCHIVO_BYTES) { problema = `«${f.name}» pesa más de 50 MB. Tómala de nuevo con menos resolución.`; continue; }
        try {
          const blob = await comprimirImagen(f, LADO_MAYOR_FOTO_PX, CALIDAD_JPEG_FOTO, 0);
          const vista = URL.createObjectURL(blob);
          urlsCreadas.current.push(vista);
          nuevas.push({
            clave: nuevaClave(), origen: "nueva", nombre: f.name, original: f, blob, mime: "image/jpeg",
            bytes: blob.size, vista, giro: 0, procesando: false, rutaSubida: null,
          });
        } catch {
          // El navegador no supo abrir la foto (un HEIC en Chrome, por ejemplo).
          problema = "No pudimos leer esa foto. Tómala de nuevo o guárdala como JPG.";
        }
      } else {
        if (mime !== "application/pdf") { problema = `«${f.name}» no es un PDF.`; continue; }
        if (f.size > TOPE_ARCHIVO_BYTES) { problema = `«${f.name}» pesa más de 50 MB.`; continue; }
        nuevas.push({
          clave: nuevaClave(), origen: "nueva", nombre: f.name, original: f, blob: f, mime,
          bytes: f.size, vista: null, giro: 0, procesando: false, rutaSubida: null,
        });
      }
    }
    setPreparando(false);
    if (nuevas.length > 0) {
      if (!mas) hojas.forEach(soltarVista);
      setHojas((prev) => (mas ? [...prev, ...nuevas] : nuevas));
      // Hojas nuevas = documento nuevo: hay que volver a mirar el nombre.
      setVi(false);
    }
    if (problema) setError(problema);
  }

  async function girar(clave: string) {
    const h = hojas.find((x) => x.clave === clave);
    if (!h || h.origen !== "nueva") return;
    const giro = ((h.giro + 90) % 360) as Giro;
    setError(null);
    setHojas((prev) => prev.map((x) => (x.clave === clave && x.origen === "nueva" ? { ...x, procesando: true } : x)));
    try {
      const blob = await comprimirImagen(h.original, LADO_MAYOR_FOTO_PX, CALIDAD_JPEG_FOTO, giro);
      const vista = URL.createObjectURL(blob);
      urlsCreadas.current.push(vista);
      soltarVista(h);
      // Con otro giro es otro archivo: si ya había subido uno, ese no vale.
      setHojas((prev) => prev.map((x) => (x.clave === clave && x.origen === "nueva"
        ? { ...x, blob, bytes: blob.size, vista, giro, procesando: false, rutaSubida: null }
        : x)));
      setVi(false);
    } catch {
      setHojas((prev) => prev.map((x) => (x.clave === clave && x.origen === "nueva" ? { ...x, procesando: false } : x)));
      setError("No pudimos girar esa foto. Quítala y vuelve a elegirla.");
    }
  }

  function mover(i: number, d: -1 | 1) {
    setHojas((prev) => {
      const j = i + d;
      if (j < 0 || j >= prev.length) return prev;
      const copia = [...prev];
      [copia[i], copia[j]] = [copia[j], copia[i]];
      return copia;
    });
  }

  function quitar(clave: string) {
    soltarVista(hojas.find((x) => x.clave === clave));
    const quedan = hojas.filter((x) => x.clave !== clave);
    setHojas(quedan);
    setError(null);
    if (quedan.length === 0) setVi(false);
  }

  async function guardar() {
    setError(null);
    const problema = problemaConLasHojas(tipo, hojas.map((h) => ({ bytes: h.bytes, mime: h.mime })));
    if (problema) { setError(problema); return; }
    if (editando && cambios.igual) { setError("No hiciste ningún cambio: agrega, quita o reordena alguna hoja."); return; }
    if (!vi) {
      setError(`Marca la casilla de abajo: confirma que viste el nombre y que es la boleta de ${fila.nombre}. Una boleta en manos equivocadas expone un sueldo.`);
      return;
    }

    setGuardando(true);

    // 1 · Subir cada hoja NUEVA que aún no esté en el almacén. Si una falla, se corta aquí.
    const rutas = new Map<string, string>();
    for (const h of hojas) {
      if (h.origen === "existente") rutas.set(h.clave, h.ruta);
      else if (h.rutaSubida) rutas.set(h.clave, h.rutaSubida);
    }
    const pendientes = hojas.filter((h): h is HojaNueva => h.origen === "nueva" && !rutas.has(h.clave));
    for (let i = 0; i < pendientes.length; i++) {
      const h = pendientes[i];
      const posicion = hojas.findIndex((x) => x.clave === h.clave) + 1;
      const extension = extensionPorMime(h.mime);
      if (!extension) {
        setError(`La hoja ${posicion} («${h.nombre}») no es de un tipo que se pueda guardar.`);
        setGuardando(false); setProgreso(null);
        return;
      }
      const ruta = rutaDeHoja(periodoId, fila.persona_id, extension);
      const archivo = esFoto ? new File([h.blob], "boleta.jpg", { type: "image/jpeg" }) : h.original;
      setProgreso({ actual: i + 1, total: pendientes.length, pct: 0 });
      const falla = await subirArchivoConProgreso(supabase, BUCKET_BOLETAS, ruta, archivo, (pct) =>
        setProgreso({ actual: i + 1, total: pendientes.length, pct }));
      if (falla) {
        setError(`No pudimos subir la hoja ${posicion} («${h.nombre}»): ${falla}. No se guardó la boleta. Vuelve a intentarlo: las hojas que ya subieron no se repiten.`);
        setGuardando(false); setProgreso(null);
        return;
      }
      rutas.set(h.clave, ruta);
      setHojas((prev) => prev.map((x) => (x.clave === h.clave && x.origen === "nueva" ? { ...x, rutaSubida: ruta } : x)));
    }
    setProgreso(null);

    // 2 · Recién con todas las hojas en el almacén se le pide a la base crear la versión.
    const avisa = publicada ? editaAvisa({ publicada, cambios, quiereAvisar }) : true;
    const { error: eBase } = await supabase.rpc("fn_boleta_guardar_version", {
      p_periodo_id: periodoId,
      p_persona_id: fila.persona_id,
      p_tipo: tipo,
      p_partes: hojas.map((h) => ({ path: rutas.get(h.clave) ?? "" })),
      p_avisar: avisa,
    });
    if (eBase) {
      setError(mensajeDeError(eBase));
      setGuardando(false);
      return;
    }

    if (!editando) avisar("ok", `Boleta de ${fila.nombre} subida. Queda sin publicar hasta que publiques el periodo.`);
    else if (!publicada) avisar("ok", `Boleta de ${fila.nombre} actualizada. Sigue sin publicar.`);
    else if (avisa) avisar("ok", `Boleta de ${fila.nombre} actualizada. Se le avisó y su confirmación vuelve a empezar.`);
    else avisar("ok", `Boleta de ${fila.nombre} actualizada sin avisar.`);
    onGuardado();
  }

  const cuantas = hojas.length;
  const nombreDelArchivoEnFrase = esFoto ? (cuantas > 1 ? "las fotos" : "la foto") : (cuantas > 1 ? "los PDF" : "el PDF");
  const textoDelAgregar = cuantas === 0
    ? (esFoto ? "Elegir foto" : "Elegir PDF")
    : mas ? (esFoto ? "Agregar otra foto" : "Agregar otro PDF") : (esFoto ? "Reemplazar la foto" : "Reemplazar el PDF");

  return (
    <Modal
      abierto
      onCerrar={onCerrar}
      titulo={editando ? "Editar la boleta" : "Subir boleta"}
      ancho="lg"
      // Con hojas nuevas armadas, un toque de más en el velo o un Escape no debe tirarlas.
      bloqueado={guardando || hayNuevas}
    >
      <dl className="mb-4 grid grid-cols-[5.5rem_minmax(0,1fr)] gap-x-3 gap-y-1 text-sm">
        <dt className="text-taupe">Persona</dt>
        <dd className="min-w-0 break-words text-tinta">{fila.nombre}</dd>
        <dt className="text-taupe">Periodo</dt>
        <dd className="min-w-0 break-words text-tinta">{nombreDelPeriodo}</dd>
      </dl>

      {cargandoActuales ? (
        <Cargando texto="Abriendo las hojas actuales…" />
      ) : errorActuales ? (
        <div className="space-y-3">
          <p role="alert" className="rounded-control bg-rojo/10 px-3 py-2 text-sm text-rojo-profundo">{errorActuales}</p>
          <Boton className={TACTIL} onClick={() => { setCargandoActuales(true); setReintento((n) => n + 1); }}>Intentar de nuevo</Boton>
        </div>
      ) : (
        <>
          {/* Foto o PDF: una boleta es de un solo tipo. Con hojas puestas, el otro queda bloqueado. */}
          <div role="group" aria-label="Tipo de documento" className="mb-3 inline-flex overflow-hidden rounded-control border border-borde-control">
            {(["imagen", "pdf"] as const).map((t) => (
              <button
                key={t}
                type="button"
                aria-pressed={tipo === t}
                disabled={ocupado || (cuantas > 0 && tipo !== t)}
                onClick={() => { setTipo(t); setError(null); }}
                className={`px-5 py-2 text-sm disabled:cursor-not-allowed disabled:opacity-50 ${TACTIL} ${tipo === t ? "bg-tinta text-crema" : "bg-papel text-tinta"}`}
              >
                {t === "imagen" ? "Foto" : "PDF"}
              </button>
            ))}
          </div>

          <label className="mb-3 flex items-start gap-2 text-sm text-tinta">
            <input
              type="checkbox"
              className="mt-0.5 size-4 shrink-0 accent-tinta disabled:opacity-50"
              checked={mas}
              disabled={cuantas > 1 || ocupado}
              onChange={(e) => setMas(e.target.checked)}
            />
            <span>
              La boleta tiene más de {esFoto ? "una foto" : "un PDF"}
              {cuantas > 1 && <span className="text-taupe"> (quita las extras para volver a una sola)</span>}
            </span>
          </label>

          {cuantas > 0 && (
            <ul className="mb-3 grid grid-cols-2 gap-3 sm:grid-cols-3">
              {hojas.map((h, i) => (
                <li key={h.clave} className="flex min-w-0 flex-col gap-2 rounded-superficie border border-sand bg-hueso p-2">
                  <div className="flex h-28 items-center justify-center overflow-hidden rounded-control bg-sand text-taupe">
                    {h.origen === "nueva" && h.procesando ? (
                      <span className="text-xs">Procesando…</span>
                    ) : tipo === "pdf" ? (
                      <span className="flex flex-col items-center gap-1 text-xs"><FileText size={28} aria-hidden />PDF</span>
                    ) : (
                      // eslint-disable-next-line @next/next/no-img-element -- vista previa local o de un bucket privado, no un asset del proyecto
                      <img
                        src={h.origen === "nueva" ? (h.vista ?? "") : h.url}
                        alt={cuantas > 1 ? `Hoja ${i + 1} de ${cuantas}` : "Foto de la boleta"}
                        className="max-h-full max-w-full object-contain"
                      />
                    )}
                  </div>
                  <p className="min-w-0 break-words text-xs text-taupe">
                    {cuantas > 1 && <>{tipo === "pdf" ? "PDF" : "Hoja"} {i + 1} · </>}{pesoLegible(h.bytes)}
                    {tipo === "pdf" && h.origen === "nueva" && <><br />{h.nombre}</>}
                  </p>
                  <div className="flex flex-wrap gap-1.5">
                    {cuantas > 1 && i > 0 && (
                      <Boton tamano="sm" className={TACTIL} disabled={ocupado} aria-label="Mover antes" onClick={() => mover(i, -1)}>←</Boton>
                    )}
                    {cuantas > 1 && i < cuantas - 1 && (
                      <Boton tamano="sm" className={TACTIL} disabled={ocupado} aria-label="Mover después" onClick={() => mover(i, 1)}>→</Boton>
                    )}
                    {h.origen === "nueva" && esFoto && (
                      <Boton tamano="sm" className={TACTIL} disabled={ocupado} aria-label="Girar la foto" onClick={() => void girar(h.clave)}>Girar ↻</Boton>
                    )}
                    <Boton tamano="sm" className={TACTIL} disabled={ocupado} aria-label={`Quitar la hoja ${i + 1}`} onClick={() => quitar(h.clave)}>Quitar</Boton>
                  </div>
                </li>
              ))}
            </ul>
          )}

          <div className="mb-3 rounded-superficie border border-dashed border-borde-control bg-hueso p-4 text-center">
            <p className="mb-3 text-sm text-taupe">
              {esFoto ? "Que se vea completa, derecha y con buena luz." : "Sube el PDF tal como lo entregó el contador."}
            </p>
            <input
              ref={entradaDeArchivo}
              type="file"
              className="sr-only"
              tabIndex={-1}
              accept={esFoto ? "image/*" : "application/pdf"}
              multiple={mas}
              onChange={(e) => {
                // Se copia ANTES de vaciar el campo: en Chrome vaciarlo vacía también la lista.
                const elegidos = Array.from(e.target.files ?? []);
                e.target.value = "";
                void agregar(elegidos);
              }}
            />
            <Boton className={TACTIL} disabled={ocupado} cargando={preparando} onClick={() => entradaDeArchivo.current?.click()}>
              {preparando ? "Preparando…" : textoDelAgregar}
            </Boton>
          </div>

          {cuantas > 0 && (
            <p className={`mb-3 text-sm ${pasaElTope ? "text-rojo-profundo" : "text-taupe"}`}>
              {etiquetaDeHojas(tipo, cuantas)} · unos {pesoLegible(total)} en total · tope 500 MB por boleta
              {esFoto && hayNuevas && " · las fotos nuevas se reducen a JPG liviano"}
            </p>
          )}

          {cuantas > 0 && casilla.visible && (
            <label className="mb-3 flex items-start gap-2 text-sm text-tinta">
              <input
                type="checkbox"
                className="mt-0.5 size-4 shrink-0 accent-tinta disabled:opacity-50"
                checked={casilla.marcada}
                disabled={casilla.bloqueada || ocupado}
                onChange={(e) => setQuiereAvisar(e.target.checked)}
              />
              <span>
                Avisar y pedir confirmar de nuevo
                <span className="block text-taupe">{casilla.explicacion}</span>
              </span>
            </label>
          )}

          {cuantas > 0 && (
            <label className="mb-3 flex items-start gap-2 text-sm text-tinta">
              <input
                type="checkbox"
                className="mt-0.5 size-4 shrink-0 accent-tinta disabled:opacity-50"
                checked={vi}
                disabled={ocupado}
                onChange={(e) => { setVi(e.target.checked); setError(null); }}
              />
              <span>Vi el nombre en {nombreDelArchivoEnFrase} y es la boleta de <b className="font-medium">{fila.nombre}</b></span>
            </label>
          )}

          {progreso && (
            <div role="status" className="mb-3">
              <p className="mb-1 text-sm text-tinta">
                Subiendo {progreso.total > 1 ? `hoja ${progreso.actual} de ${progreso.total}` : "la boleta"}… {progreso.pct} %
              </p>
              <div className="h-1.5 overflow-hidden rounded-pildora bg-sand" aria-hidden>
                <div className="h-full bg-verde transition-[width]" style={{ width: `${progreso.pct}%` }} />
              </div>
            </div>
          )}

          {error && <p role="alert" className="mb-3 rounded-control bg-rojo/10 px-3 py-2 text-sm text-rojo-profundo">{error}</p>}

          <p className="text-xs text-taupe">
            {publicada
              ? `Se guarda como versión ${numeroDeVersion}; la anterior queda en el historial. Como ya está publicada, la persona verá la nueva de inmediato.`
              : editando
                ? `Se guarda como versión ${numeroDeVersion}; la anterior queda en el historial.`
                : "Queda como borrador: la persona no la ve hasta que publiques el periodo."}
          </p>
        </>
      )}

      <PieDeModal>
        <Boton className={TACTIL} disabled={guardando} onClick={onCerrar}>Cancelar</Boton>
        <Boton
          variante="primario"
          className={TACTIL}
          cargando={guardando}
          disabled={cargandoActuales || errorActuales !== null || ocupado || cuantas === 0}
          onClick={() => void guardar()}
        >
          {guardando ? "Guardando…" : editando ? `Guardar versión ${numeroDeVersion}` : "Subir"}
        </Boton>
      </PieDeModal>
    </Modal>
  );
}

"use client";

import { useEffect, useRef, useState } from "react";
import { Dancing_Script, Caveat, Sacramento } from "next/font/google";
import type { createAdminSupabaseClient } from "@cayla-dynamic/database";

type Metodo = "imagen" | "dibujo" | "tipografica";
type Estilo = "elegante" | "a_mano" | "clasica";

// Cargadas solo aquí (no en layout.tsx): ningún otro tramo de la app necesita
// una cursiva, y next/font las deja fuera del bundle de cualquier pantalla
// que no importe este archivo.
const fuenteElegante = Dancing_Script({ subsets: ["latin"], weight: "700" });
const fuenteAMano = Caveat({ subsets: ["latin"], weight: "600" });
const fuenteClasica = Sacramento({ subsets: ["latin"], weight: "400" });

const FUENTES: Record<Estilo, { label: string; className: string; family: string }> = {
  elegante: { label: "Elegante", className: fuenteElegante.className, family: fuenteElegante.style.fontFamily },
  a_mano: { label: "A mano", className: fuenteAMano.className, family: fuenteAMano.style.fontFamily },
  clasica: { label: "Clásica", className: fuenteClasica.className, family: fuenteClasica.style.fontFamily },
};

// Recorta al rectángulo con tinta y vuelve transparente el fondo del papel —
// el mismo tratamiento para los tres métodos, porque los tres terminan en lo
// mismo: tinta oscura sobre un fondo claro que hay que ajustar y despegar de
// su rectángulo. Antes esto solo existía para "subir imagen"; separarlo evita
// tener la misma lógica de recorte escrita tres veces (una por método).
function recortarYTransparentar(src: HTMLCanvasElement, anchoSalida = 520): string {
  const cw = src.width, ch = src.height;
  const sctx = src.getContext("2d");
  if (!sctx) throw new Error("Sin canvas.");
  const d = sctx.getImageData(0, 0, cw, ch).data;
  const rowInk = new Array(ch).fill(0), colInk = new Array(cw).fill(0);
  for (let y = 0; y < ch; y++) {
    for (let x = 0; x < cw; x++) {
      const i = (y * cw + x) * 4;
      const lum = 0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2];
      if (d[i + 3] > 40 && lum < 210) { rowInk[y]++; colInk[x]++; }
    }
  }
  let rowMax = 1, colMax = 1;
  for (let y = 0; y < ch; y++) if (rowInk[y] > rowMax) rowMax = rowInk[y];
  for (let x = 0; x < cw; x++) if (colInk[x] > colMax) colMax = colInk[x];
  const rThr = rowMax * 0.05, cThr = colMax * 0.05;
  let minX = 0, minY = 0, maxX = cw - 1, maxY = ch - 1;
  while (minY < maxY && rowInk[minY] < rThr) minY++;
  while (maxY > minY && rowInk[maxY] < rThr) maxY--;
  while (minX < maxX && colInk[minX] < cThr) minX++;
  while (maxX > minX && colInk[maxX] < cThr) maxX--;
  if (rowInk.slice(minY, maxY + 1).every((n) => n === 0)) {
    throw new Error("No se detectó ningún trazo. Dibuja tu firma antes de guardar.");
  }
  const pad = Math.round(Math.min(cw, ch) * 0.02);
  minX = Math.max(0, minX - pad); minY = Math.max(0, minY - pad);
  maxX = Math.min(cw - 1, maxX + pad); maxY = Math.min(ch - 1, maxY + pad);
  const bw = maxX - minX + 1, bh = maxY - minY + 1;
  const s1 = Math.min(1, anchoSalida / bw);
  const ow = Math.max(1, Math.round(bw * s1)), oh = Math.max(1, Math.round(bh * s1));
  const out = document.createElement("canvas");
  out.width = ow; out.height = oh;
  const octx = out.getContext("2d");
  if (!octx) throw new Error("Sin canvas.");
  octx.drawImage(src, minX, minY, bw, bh, 0, 0, ow, oh);
  // El fondo del papel se vuelve transparente, no blanco: sobre la raya de un
  // contrato, un rectángulo blanco encima se ve como una pegatina.
  const salida = octx.getImageData(0, 0, ow, oh);
  const px = salida.data;
  for (let i = 0; i < px.length; i += 4) {
    const lum = 0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2];
    if (lum >= 240) px[i + 3] = 0;
    else if (lum > 160) px[i + 3] = Math.round(px[i + 3] * ((240 - lum) / 80));
  }
  octx.putImageData(salida, 0, 0);
  return out.toDataURL("image/png");
}

// PostgrestError es un objeto plano (no siempre `instanceof Error`), así que
// `e instanceof Error ? e.message : generico` lo descartaba y siempre se veía
// el mismo texto genérico — aunque Postgres SÍ había explicado el motivo real
// (función inexistente, permiso denegado, validación...). Diagnosticar un
// fallo real se volvía imposible desde la pantalla.
function mensajeError(e: unknown, generico: string): string {
  if (e && typeof e === "object" && "message" in e && typeof (e as { message?: unknown }).message === "string") {
    return (e as { message: string }).message || generico;
  }
  return generico;
}

// La 0395 se pega a mano en producción y puede tardar en llegar (o quedar a
// medias). Mientras tanto, llamar a las funciones que agrega devuelve un
// error de "función no encontrada" — PGRST202 si PostgREST ya recargó su
// caché de esquema y de verdad no existe, 42883 (undefined_function) si el
// Postgres de abajo es el que se queja. Distinguir ESTE caso del resto
// importa: no es un permiso ni un dato inválido, es que el servidor todavía
// no tiene la actualización.
function esFuncionInexistente(error: { code?: string; message?: string } | null | undefined): boolean {
  if (!error) return false;
  if (error.code === "PGRST202" || error.code === "42883") return true;
  return typeof error.message === "string" && /could not find the function|does not exist/i.test(error.message);
}

function procesarImagenSubida(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(new Error("No se pudo leer el archivo."));
    reader.onload = () => {
      const img = new Image();
      img.onerror = () => reject(new Error("La imagen no es válida."));
      img.onload = () => {
        const s0 = Math.min(1, 1000 / img.width);
        const cw = Math.round(img.width * s0), ch = Math.round(img.height * s0);
        const src = document.createElement("canvas");
        src.width = cw; src.height = ch;
        const sctx = src.getContext("2d");
        if (!sctx) return reject(new Error("Sin canvas."));
        sctx.drawImage(img, 0, 0, cw, ch);
        try { resolve(recortarYTransparentar(src)); } catch (e) { reject(e); }
      };
      img.src = reader.result as string;
    };
    reader.readAsDataURL(file);
  });
}

async function renderizarTipografica(texto: string, estilo: Estilo): Promise<string> {
  // `family` ya es una lista CSS lista para usar —p. ej. `"Dancing Script",
  // "Dancing Script Fallback"`—, con sus propias comillas donde hacen falta.
  // Envolverla en comillas extra (como hacía la primera versión) rompe el
  // parseo de `font` y el canvas cae en silencio a un serif por defecto: la
  // firma se guardaba, pero nunca en la tipografía elegida.
  const family = FUENTES[estilo].family;
  const tam = 90;
  await document.fonts.load(`${tam}px ${family}`);
  await document.fonts.ready;
  const medir = document.createElement("canvas").getContext("2d");
  if (!medir) throw new Error("Sin canvas.");
  medir.font = `${tam}px ${family}`;
  const ancho = Math.max(1, Math.ceil(medir.measureText(texto).width));
  const padX = Math.round(tam * 0.4), padY = Math.round(tam * 0.5);
  const canvas = document.createElement("canvas");
  canvas.width = ancho + padX * 2;
  canvas.height = Math.round(tam * 1.5) + padY;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("Sin canvas.");
  ctx.fillStyle = "#ffffff";
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.fillStyle = "#000000";
  ctx.font = `${tam}px ${family}`;
  ctx.textBaseline = "alphabetic";
  ctx.fillText(texto, padX, Math.round(tam * 1.05));
  return recortarYTransparentar(canvas);
}

interface Props {
  supabase: ReturnType<typeof createAdminSupabaseClient>;
  nombreOficial: string;
  avisar: (tipo: "ok" | "error", texto: string) => void;
  // Para que quien la usa pueda refrescar una vista propia de la firma (el
  // contrato de /mio, por ejemplo) sin esperar a recargar la página. Opcional
  // y sin efecto en admin/personas/[id], que no lo pasa.
  onGuardada?: (imagen: string | null) => void;
}

export function FirmaEditor({ supabase, nombreOficial, avisar, onGuardada }: Props) {
  const [cargando, setCargando] = useState(true);
  const [firma, setFirma] = useState<{ imagen: string; tipo: Metodo; estilo: Estilo | null } | null>(null);
  const [editando, setEditando] = useState(false);
  // El servidor todavía no tiene la 0395 (o PostgREST no recargó su caché de
  // esquema tras pegarla): "Dibujar" y "Escribir" dependen de funciones que
  // no existen todavía, así que se desactivan con una explicación en vez de
  // dejar que alguien dibuje o escriba su firma y recién ahí se entere.
  const [sqlDesactualizado, setSqlDesactualizado] = useState(false);
  const [metodo, setMetodo] = useState<Metodo>("imagen");
  const [estilo, setEstilo] = useState<Estilo>("elegante");
  const [guardando, setGuardando] = useState(false);
  const [trazoVacio, setTrazoVacio] = useState(true);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const dibujando = useRef(false);
  const ultimoPunto = useRef<{ x: number; y: number } | null>(null);

  useEffect(() => {
    let vivo = true;
    void (async () => {
      const { data, error } = await supabase.rpc("fn_mi_firma_config").maybeSingle();
      if (!vivo) return;
      if (error) {
        // `fn_mi_firma_config` es de la migración 0395. Si producción todavía
        // no la tiene pegada (el frontend se despliega solo al fusionar a
        // `main`; el SQL lo pega Felipe a mano y puede tardar), esta llamada
        // falla — y leer ese error como "no hay firma" borraría de la
        // pantalla una firma que sigue intacta en la base. `fn_mi_firma()` es
        // la función vieja, previa a los tres métodos: solo devuelve la
        // imagen, pero sigue viva y sirve de red mientras tanto.
        if (esFuncionInexistente(error)) setSqlDesactualizado(true);
        const { data: imagenVieja, error: errorViejo } = await supabase.rpc("fn_mi_firma");
        if (!vivo) return;
        if (typeof imagenVieja === "string" && imagenVieja.startsWith("data:image")) {
          setFirma({ imagen: imagenVieja, tipo: "imagen", estilo: null });
        } else {
          if (errorViejo) avisar("error", mensajeError(errorViejo, "No se pudo leer tu firma."));
          setEditando(true);
        }
        setCargando(false);
        return;
      }
      const fila = data as { imagen: string; tipo: string; estilo: string | null } | null;
      if (fila?.imagen) {
        const cargada = { imagen: fila.imagen, tipo: fila.tipo as Metodo, estilo: fila.estilo as Estilo | null };
        setFirma(cargada);
        setMetodo(cargada.tipo);
        if (cargada.estilo) setEstilo(cargada.estilo);
      } else {
        setEditando(true); // sin firma todavía: el editor arranca abierto
      }
      setCargando(false);
    })();
    return () => { vivo = false; };
  }, [supabase, avisar]);

  function limpiarCanvas() {
    const canvas = canvasRef.current;
    const ctx = canvas?.getContext("2d");
    if (!canvas || !ctx) return;
    ctx.fillStyle = "#ffffff";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    setTrazoVacio(true);
  }

  // El canvas de dibujo arranca en blanco (no transparente) porque el recorte
  // compartido asume tinta oscura sobre papel claro, igual que un escaneo.
  useEffect(() => {
    if (metodo === "dibujo" && editando) limpiarCanvas();
  }, [metodo, editando]);

  function coordenadas(e: React.PointerEvent<HTMLCanvasElement>) {
    const canvas = canvasRef.current!;
    const rect = canvas.getBoundingClientRect();
    return { x: (e.clientX - rect.left) * (canvas.width / rect.width), y: (e.clientY - rect.top) * (canvas.height / rect.height) };
  }
  function iniciarTrazo(e: React.PointerEvent<HTMLCanvasElement>) {
    e.preventDefault();
    canvasRef.current?.setPointerCapture(e.pointerId);
    dibujando.current = true;
    ultimoPunto.current = coordenadas(e);
  }
  function continuarTrazo(e: React.PointerEvent<HTMLCanvasElement>) {
    if (!dibujando.current) return;
    const ctx = canvasRef.current?.getContext("2d");
    if (!ctx || !ultimoPunto.current) return;
    const p = coordenadas(e);
    ctx.strokeStyle = "#1a1a18";
    ctx.lineWidth = 3;
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.beginPath();
    ctx.moveTo(ultimoPunto.current.x, ultimoPunto.current.y);
    ctx.lineTo(p.x, p.y);
    ctx.stroke();
    ultimoPunto.current = p;
    setTrazoVacio(false);
  }
  function terminarTrazo() {
    dibujando.current = false;
    ultimoPunto.current = null;
  }

  async function guardar(dataUrl: string, tipo: Metodo, estiloUsado?: Estilo) {
    setGuardando(true);
    try {
      let { error } = await supabase.rpc("fn_set_mi_firma", {
        p_dataurl: dataUrl,
        p_tipo: tipo,
        p_estilo: tipo === "tipografica" ? estiloUsado : null,
      });
      if (error && esFuncionInexistente(error) && tipo === "imagen") {
        // Mismo caso que al cargar: si producción todavía no tiene la 0395,
        // la función de 3 argumentos no existe. "Escanear" no necesita
        // las columnas nuevas para nada, así que cae a la firma de siempre
        // en vez de quedar bloqueada hasta que alguien pegue el SQL.
        ({ error } = await supabase.rpc("fn_set_mi_firma", { p_dataurl: dataUrl }));
      }
      if (error) {
        if (esFuncionInexistente(error)) {
          setSqlDesactualizado(true);
          if (tipo !== "imagen") setMetodo("imagen");
          throw new Error(
            tipo === "imagen"
              ? "No se pudo guardar: el servidor no respondió ni con el método nuevo ni con el de siempre. Avisa a Felipe."
              : "Este método todavía no está disponible en el servidor. Usa \"Escanear\" mientras tanto, o vuelve a intentarlo en unos minutos.",
          );
        }
        throw error;
      }
      setFirma({ imagen: dataUrl, tipo, estilo: tipo === "tipografica" ? (estiloUsado ?? null) : null });
      setEditando(false);
      avisar("ok", "Firma guardada.");
      onGuardada?.(dataUrl);
    } catch (e) {
      avisar("error", mensajeError(e, "No se pudo guardar la firma."));
    } finally {
      setGuardando(false);
    }
  }

  async function subirImagen(file: File) {
    setGuardando(true);
    try {
      const dataUrl = await procesarImagenSubida(file);
      await guardar(dataUrl, "imagen");
    } catch (e) {
      avisar("error", mensajeError(e, "No se pudo procesar la imagen."));
      setGuardando(false);
    }
  }

  async function guardarDibujo() {
    const canvas = canvasRef.current;
    if (!canvas) return;
    try {
      const dataUrl = recortarYTransparentar(canvas);
      await guardar(dataUrl, "dibujo");
    } catch (e) {
      avisar("error", mensajeError(e, "No se pudo guardar el trazo."));
    }
  }

  async function guardarTipografica() {
    setGuardando(true);
    try {
      const dataUrl = await renderizarTipografica(nombreOficial, estilo);
      await guardar(dataUrl, "tipografica", estilo);
    } catch (e) {
      avisar("error", mensajeError(e, "No se pudo generar la firma."));
      setGuardando(false);
    }
  }

  async function quitarFirma() {
    setGuardando(true);
    const { error } = await supabase.rpc("fn_set_mi_firma", { p_dataurl: null });
    if (error) avisar("error", mensajeError(error, "No se pudo quitar la firma."));
    else { setFirma(null); setEditando(true); avisar("ok", "Firma quitada."); onGuardada?.(null); }
    setGuardando(false);
  }

  if (cargando) return <p className="text-sm text-taupe">Cargando tu firma…</p>;

  const TABS: { id: Metodo; label: string }[] = [
    { id: "imagen", label: "Escanear" },
    { id: "dibujo", label: "Dibujar" },
    { id: "tipografica", label: "Escribir" },
  ];

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center gap-4">
        {firma ? (
          <div className="w-60 rounded-lg border border-sand bg-white px-4 pb-2 pt-3">
            <div className="flex h-20 items-end justify-center">
              <img src={firma.imagen} alt="Tu firma" className="block h-20 w-auto max-w-full" />
            </div>
            <div className="border-t border-tinta/40 pt-1 text-[11px] text-taupe">Así se verá sobre la línea del memo</div>
          </div>
        ) : (
          <span className="text-sm text-taupe">Aún no has configurado tu firma.</span>
        )}
        <div className="flex flex-col gap-1">
          {!editando && (
            <button onClick={() => setEditando(true)} className="rounded-xl bg-tinta px-3 py-1.5 text-xs font-medium text-crema">
              Cambiar firma
            </button>
          )}
          {firma && <button onClick={() => void quitarFirma()} disabled={guardando} className="text-xs text-rojo hover:underline">Quitar</button>}
        </div>
      </div>

      {editando && (
        <div className="rounded-xl border border-sand bg-crema/40 p-4">
          {sqlDesactualizado && (
            <p className="mb-3 rounded-lg bg-ambar/15 px-3 py-2 text-xs text-ambar">
              «Dibujar» y «Escribir» todavía no están disponibles: el servidor no tiene la actualización más reciente. Puedes seguir usando «Escanear» mientras tanto — vuelve a intentar los otros dos en unos minutos.
            </p>
          )}
          <div className="mb-4 flex gap-1 rounded-lg bg-sand/50 p-1 text-sm">
            {TABS.map((t) => {
              const deshabilitada = sqlDesactualizado && t.id !== "imagen";
              return (
              <button
                key={t.id}
                onClick={() => setMetodo(t.id)}
                disabled={deshabilitada}
                title={deshabilitada ? "Todavía no disponible en el servidor" : undefined}
                className={`flex-1 rounded-md px-3 py-1.5 font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-40 ${metodo === t.id ? "bg-tinta text-crema" : "text-taupe hover:text-tinta"}`}
              >
                {t.label}
              </button>
              );
            })}
          </div>

          {metodo === "imagen" && (
            <div className="flex flex-col gap-2">
              <p className="text-sm text-taupe">Sube una foto o escaneo de tu firma, mejor sobre fondo blanco.</p>
              <label className="w-fit cursor-pointer rounded-xl bg-tinta px-3 py-1.5 text-xs font-medium text-crema">
                {guardando ? "Guardando…" : "Elegir archivo"}
                <input type="file" accept="image/png,image/jpeg" className="hidden" disabled={guardando}
                  onChange={(e) => { const f = e.target.files?.[0]; if (f) void subirImagen(f); e.target.value = ""; }} />
              </label>
            </div>
          )}

          {metodo === "dibujo" && (
            <div className="flex flex-col gap-2">
              <p className="text-sm text-taupe">Traza tu firma con el mouse, el trackpad o el dedo.</p>
              <canvas
                ref={canvasRef}
                width={600}
                height={200}
                className="w-full max-w-md touch-none rounded-lg border border-sand bg-white"
                style={{ aspectRatio: "3 / 1" }}
                onPointerDown={iniciarTrazo}
                onPointerMove={continuarTrazo}
                onPointerUp={terminarTrazo}
                onPointerLeave={terminarTrazo}
              />
              <div className="flex gap-2">
                <button onClick={limpiarCanvas} disabled={guardando} className="rounded-xl border border-sand px-3 py-1.5 text-xs font-medium text-taupe">Borrar trazo</button>
                <button onClick={() => void guardarDibujo()} disabled={guardando || trazoVacio} className="rounded-xl bg-tinta px-3 py-1.5 text-xs font-medium text-crema disabled:opacity-40">
                  {guardando ? "Guardando…" : "Guardar firma"}
                </button>
              </div>
            </div>
          )}

          {metodo === "tipografica" && (
            <div className="flex flex-col gap-3">
              <div>
                <label className="mb-1 block text-[11px] font-medium uppercase tracking-wide text-taupe">Tu nombre, tal como firmas</label>
                <input
                  value={nombreOficial}
                  readOnly
                  tabIndex={-1}
                  className="w-full cursor-default rounded-lg border border-sand bg-sand/40 px-3 py-2 text-sm text-tinta"
                />
                <p className="mt-1 text-xs text-taupe">Viene de tu Ficha personal — no se puede escribir un nombre distinto.</p>
              </div>
              <div className="flex gap-1 rounded-lg bg-sand/50 p-1 text-sm">
                {(Object.keys(FUENTES) as Estilo[]).map((e) => (
                  <button
                    key={e}
                    onClick={() => setEstilo(e)}
                    className={`flex-1 rounded-md px-3 py-1.5 font-medium transition-colors ${estilo === e ? "bg-tinta text-crema" : "text-taupe hover:text-tinta"}`}
                  >
                    {FUENTES[e].label}
                  </button>
                ))}
              </div>
              <div className="rounded-lg border border-sand bg-white px-4 py-6 text-center">
                {nombreOficial ? (
                  <span className={`${FUENTES[estilo].className} text-4xl text-tinta`}>{nombreOficial}</span>
                ) : (
                  <span className="text-sm text-taupe">Falta tu nombre en la Ficha personal.</span>
                )}
              </div>
              <button
                onClick={() => void guardarTipografica()}
                disabled={guardando || !nombreOficial.trim()}
                className="w-fit rounded-xl bg-tinta px-3 py-1.5 text-xs font-medium text-crema disabled:opacity-40"
              >
                {guardando ? "Guardando…" : "Guardar firma"}
              </button>
            </div>
          )}

          {firma && (
            <button onClick={() => setEditando(false)} className="mt-3 text-xs text-taupe hover:underline">Cancelar</button>
          )}
        </div>
      )}
    </div>
  );
}

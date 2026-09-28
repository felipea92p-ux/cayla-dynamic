"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Eye, Paperclip, X } from "lucide-react";
import { hoyLima } from "@cayla-dynamic/shared";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoCasilla, CampoSelect } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { Cargando } from "@/components/cargando";
import { cx } from "@/components/ui/cx";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { reducirImagen, pesoLegible } from "@/lib/reducir-imagen";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import {
  ESPERAS, TIPOS_DE_ADJUNTO, TIPOS_REPORTE, faltaEnReporte, fechaEnPalabras, rutaDeAdjunto, viaDeReporte,
  type EsperaReporte, type TipoReporte,
} from "@/lib/reportes";
import { useMiFicha } from "../usar-mi-ficha";

/**
 * «Contar algo»: el formulario de un reporte nuevo, en cuatro pasos
 * (docs/plan-reportes.md, sección 6; spike aprobado en docs/spike-reportes.html).
 *
 * LO QUE DECIDE LA BASE, NO ESTA PANTALLA. Quién lo va a leer
 * (`fn_reporte_quien_lo_leera`), qué plazo corre (`fn_sumar_dias_habiles`, la
 * misma cuenta de la 0212) y si se puede enviar (`fn_reporte_crear`). Aquí solo
 * se arma el pedido y se muestra lo que la base contesta, con sus palabras.
 *
 * ARRIBA, SIEMPRE, LAS DOS CASILLAS. Hostigamiento sexual y riesgo ahora no
 * son un tipo más que elegir en el paso 1: son lo primero que alguien en esa
 * situación tiene que ver, sin avanzar por ningún paso. Marcar la primera
 * cambia el camino entero (Título X): la líder deja de estar entre quienes
 * leen, y solo el relato es obligatorio (48.8).
 *
 * LA FECHA DEL HECHO NACE EN HOY (regla quinta de CLAUDE.md): visible,
 * editable, y nunca vacía.
 *
 * LOS ARCHIVOS VAN DESPUÉS DEL REPORTE. Las políticas del bucket exigen que el
 * reporte exista (la ruta empieza con su id). Si un archivo falla, el reporte
 * ya está enviado: se dice cuál no subió y se puede adjuntar desde el reporte.
 */

type Persona = { id: string; nombre: string; cargo: string | null; sede_codigo: string | null };
type Sede = { id: string; codigo: string; nombre: string };

export default function NuevoReporte() {
  const router = useRouter();
  const { supabase, ficha } = useMiFicha();
  const hoy = hoyLima();

  const [paso, setPaso] = useState(1);
  const [tituloX, setTituloX] = useState(false);
  const [urgente, setUrgente] = useState(false);
  const [tipo, setTipo] = useState<TipoReporte | null>(null);
  const [maltrato, setMaltrato] = useState(false);
  const [relato, setRelato] = useState("");
  const [fechaHecho, setFechaHecho] = useState(hoy);
  // "" = todavía no la cambió: vale la sede base (ver `sedeId` abajo).
  const [sedeElegida, setSedeId] = useState("");
  const [involucradas, setInvolucradas] = useState<string[]>([]);
  const [testigos, setTestigos] = useState<string[]>([]);
  const [primeraVez, setPrimeraVez] = useState<"" | "si" | "no">("");
  const [yaConversado, setYaConversado] = useState("");
  const [ticket, setTicket] = useState("");
  const [espera, setEspera] = useState<EsperaReporte | null>(null);
  const [archivos, setArchivos] = useState<File[]>([]);

  const [padron, setPadron] = useState<Persona[]>([]);
  const [sedes, setSedes] = useState<Sede[]>([]);
  const [errorCarga, setErrorCarga] = useState<string | null>(null);
  const [quienLee, setQuienLee] = useState<string[] | null>(null);
  const [vence, setVence] = useState<string | null>(null);
  const [enviando, setEnviando] = useState<string | null>(null);
  const [errorEnvio, setErrorEnvio] = useState<string | null>(null);

  // La sede del hecho arranca en la suya, como la fecha arranca en hoy.
  const sedeId = sedeElegida || (ficha.estado === "ok" ? ficha.sedeBaseId ?? "" : "");

  useEffect(() => {
    if (ficha.estado !== "ok") return;
    void (async () => {
      const [p, s] = await Promise.all([
        supabase.rpc("fn_reporte_padron"),
        supabase.from("sedes").select("id, codigo, nombre").eq("activa", true).order("nombre"),
      ]);
      if (p.error || s.error) {
        setErrorCarga(mensajeDeError(p.error ?? s.error, "preparar el formulario"));
        return;
      }
      setPadron((p.data ?? []) as Persona[]);
      setSedes((s.data ?? []) as Sede[]);
    })();
  }, [ficha.estado, supabase]);

  const via = tipo ? viaDeReporte({ tituloX, tipo, maltrato }) : null;
  const pidePersonas = tipo === "persona";
  const pideTestigos = tipo === "persona" || tipo === "empresa" || tipo === "clienta";

  // «Lo van a leer» y la fecha de respuesta, preguntados a la base cada vez que
  // cambia algo que los mueve. Solo se piden al llegar al paso 4.
  useEffect(() => {
    if (paso !== 4 || !via || !sedeId) return;
    let vivo = true;
    void (async () => {
      const q = await supabase.rpc("fn_reporte_quien_lo_leera", {
        p_via: via, p_sede: sedeId, p_involucradas: involucradas, p_testigos: testigos,
      });
      const dias = via === "convivencia" ? 15 : via === "reclamo" ? 10 : null;
      const v = dias ? await supabase.rpc("fn_sumar_dias_habiles", { p_desde: new Date().toISOString(), p_dias: dias }) : null;
      if (!vivo) return;
      setQuienLee(q.error ? null : (q.data ?? []).map((c) => c.cargo));
      setVence(v && !v.error ? (v.data as string) : null);
    })();
    return () => { vivo = false; };
  }, [paso, via, sedeId, involucradas, testigos, supabase]);

  const borrador = { tituloX, tipo, maltrato, relato, fechaHecho, sedeId, involucradas, testigos };
  const falta = faltaEnReporte(borrador, hoy, paso);
  const nadieLoLee = paso === 4 && quienLee !== null && quienLee.length === 0;

  const nombreDe = useMemo(() => new Map(padron.map((p) => [p.id, p.nombre] as const)), [padron]);

  async function enviar() {
    if (!tipo || !via) return;
    setErrorEnvio(null);
    setEnviando("Enviando tu reporte…");
    const { data, error } = await supabase.rpc("fn_reporte_crear", {
      p_tipo: tipo, p_via: via, p_sede: sedeId, p_fecha_hecho: fechaHecho, p_relato: relato,
      p_involucradas: pidePersonas ? involucradas : [],
      p_testigos: pideTestigos ? testigos : [],
      p_espera: espera, p_urgente: urgente,
      p_primera_vez: primeraVez === "" ? null : primeraVez === "si",
      p_ya_conversado: yaConversado || null,
      p_ticket: tipo === "clienta" ? ticket || null : null,
    });
    if (error || !data?.[0]) {
      setEnviando(null);
      setErrorEnvio(mensajeDeError(error, "enviar tu reporte"));
      return;
    }
    const { id } = data[0];

    const noSubieron: string[] = [];
    for (const [i, a] of archivos.entries()) {
      setEnviando(`Subiendo ${i + 1} de ${archivos.length}…`);
      const listo = await reducirImagen(a);
      const ruta = rutaDeAdjunto(id, listo.type || a.type);
      const fallo = ruta ? await subirArchivoConProgreso(supabase, "reportes", ruta, listo, () => {}) : "formato";
      if (fallo || !ruta) { noSubieron.push(a.name); continue; }
      const r = await supabase.rpc("fn_reporte_adjuntar", { p_reporte: id, p_path: ruta });
      if (r.error) noSubieron.push(a.name);
    }
    const aviso = noSubieron.length ? `&no_subieron=${encodeURIComponent(noSubieron.join(", "))}` : "";
    router.replace(`/mio/reportes/${id}?nuevo=1${aviso}`);
  }

  if (ficha.estado === "cargando") return <main className="p-8"><Cargando /></main>;
  if (ficha.estado === "error") return <main className="p-8 text-sm text-rojo">{ficha.mensaje}</main>;

  const disponibles = (excluir: string[]) => padron.filter((p) => !excluir.includes(p.id));

  return (
    <main className="mx-auto w-full max-w-3xl flex-1 px-5 py-8 text-sm text-tinta">
      <div className="mb-4 flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="etiqueta text-taupe">Reportes · Nuevo</p>
          <h1 className="mt-0.5 font-serif text-3xl leading-tight">Contar algo</h1>
        </div>
        <Link href="/mio?tab=reportes" className="rounded-control border border-sand px-4 py-2 text-taupe hover:text-tinta">
          Cancelar
        </Link>
      </div>

      {errorCarga && <p className="mb-4 rounded-control bg-rojo/10 px-3 py-2 text-rojo-profundo">{errorCarga}</p>}

      <div className="rounded-superficie border border-rojo/35 bg-rojo/5 p-4">
        <label className="flex items-start gap-2.5">
          <input type="checkbox" className="mt-0.5 size-4 accent-tinta" checked={tituloX}
            onChange={(e) => setTituloX(e.target.checked)} />
          <span>
            <span className="font-medium">¿Es acoso sexual, un comentario o un contacto de tipo sexual?</span>
            <span className="block text-taupe">
              Va por el procedimiento del Título X: lo leen solo Desarrollo Organizacional y quien investiga en tu
              sede. <strong className="font-medium text-tinta">Tu líder no lo ve.</strong>
            </span>
          </span>
        </label>
        <label className="mt-2.5 flex items-start gap-2.5">
          <input type="checkbox" className="mt-0.5 size-4 accent-tinta" checked={urgente}
            onChange={(e) => setUrgente(e.target.checked)} />
          <span>
            <span className="font-medium">Hay un riesgo para alguien ahora</span>
            <span className="block text-taupe">
              Se marca como urgente y va primero en la lista de quien lo gestiona. Si hay peligro inmediato, llama al{" "}
              <strong className="font-medium text-tinta">105</strong>.
            </span>
          </span>
        </label>
      </div>

      <div className="my-5 flex gap-1.5" aria-label={`Paso ${paso} de 4`}>
        {[1, 2, 3, 4].map((n) => (
          <div key={n} className={cx("h-1 flex-1 rounded-pildora", n <= paso ? "bg-tinta" : "bg-sand")} />
        ))}
      </div>

      {paso === 1 && (
        <section>
          <h2 className="font-serif text-xl">¿Sobre qué es?</h2>
          <p className="mb-3.5 text-taupe">Elige una. Si no estás segura, elige la más cercana: quien lo lea puede moverlo.</p>
          <div className="grid gap-2.5 sm:grid-cols-2">
            {TIPOS_REPORTE.map((t) => (
              <button key={t.valor} type="button" onClick={() => setTipo(t.valor)}
                className={cx(
                  "grid gap-1 rounded-superficie border bg-papel p-3.5 text-left transition-colors duration-150",
                  tipo === t.valor ? "border-tinta ring-1 ring-tinta" : "border-sand hover:border-taupe/40",
                )}>
                <span className="font-medium">{t.titulo}</span>
                <span className="text-xs text-taupe">{t.ayuda}</span>
              </button>
            ))}
          </div>
          {tipo === "persona" && !tituloX && (
            <div className="mt-3.5 rounded-superficie border border-sand p-3.5">
              <CampoCasilla etiqueta="Es maltrato o acoso (gritos, humillaciones, exclusión, amenazas)"
                checked={maltrato} onChange={(e) => setMaltrato(e.target.checked)} />
              <p className="mt-1 pl-6 text-xs text-taupe">
                Va por el artículo 43-A: Desarrollo Organizacional te responde por escrito en 15 días hábiles.
              </p>
            </div>
          )}
        </section>
      )}

      {paso === 2 && (
        <section>
          <h2 className="font-serif text-xl">¿Qué pasó?</h2>
          <p className="mb-3.5 text-taupe">
            Cuenta los hechos como si se los contaras a alguien que no estuvo: qué pasó, cuándo y dónde. No hace falta
            que sea perfecto.
          </p>
          <AreaTexto value={relato} rows={6} onChange={(e) => setRelato(e.target.value)}
            placeholder="Ej.: El martes, cerca de las 4 p. m., en caja…" />
        </section>
      )}

      {paso === 3 && (
        <section className="grid gap-4">
          <h2 className="font-serif text-xl">Detalles</h2>
          <div className="grid gap-4 sm:grid-cols-2">
            <Campo etiqueta="Fecha del hecho" type="date" value={fechaHecho} max={hoy}
              onChange={(e) => setFechaHecho(e.target.value || hoy)} />
            <CampoSelect etiqueta="Sede donde pasó" value={sedeId} onChange={(e) => setSedeId(e.target.value)}>
              {!sedeId && <option value="">Elige la sede</option>}
              {sedes.map((s) => <option key={s.id} value={s.id}>{s.nombre}</option>)}
            </CampoSelect>
          </div>

          {pidePersonas && (
            <SelectorPersonas etiqueta={tituloX ? "¿Sobre quién es? (opcional)" : "¿Sobre quién es?"}
              elegidas={involucradas} opciones={disponibles([...involucradas, ...testigos])} nombreDe={nombreDe}
              onCambiar={setInvolucradas} />
          )}
          {pideTestigos && (
            <SelectorPersonas etiqueta="¿Alguien más lo vio? (opcional)"
              elegidas={testigos} opciones={disponibles([...involucradas, ...testigos])} nombreDe={nombreDe}
              onCambiar={setTestigos} />
          )}
          {tipo === "clienta" && (
            <Campo etiqueta="N.º de ticket o boleta (opcional; no pongas el nombre de la clienta)" value={ticket}
              onChange={(e) => setTicket(e.target.value)} placeholder="B001-000123" />
          )}
          {(tipo === "persona" || tipo === "clienta") && (
            <div className="grid gap-4 sm:grid-cols-2">
              <CampoSelect etiqueta="¿Es la primera vez?" value={primeraVez}
                onChange={(e) => setPrimeraVez(e.target.value as "" | "si" | "no")}>
                <option value="">Prefiero no decirlo</option>
                <option value="no">No, ya pasó antes</option>
                <option value="si">Sí, es la primera vez</option>
              </CampoSelect>
              <Campo etiqueta="¿Ya lo conversaste con alguien? (opcional)" value={yaConversado}
                onChange={(e) => setYaConversado(e.target.value)} placeholder="Con quién y cuándo" />
            </div>
          )}

          <div>
            <span className="text-sm text-taupe">Fotos o archivos (opcional)</span>
            <label className="mt-1.5 flex cursor-pointer items-center justify-center gap-2 rounded-superficie border border-dashed border-taupe/50 bg-hueso p-4 text-taupe hover:text-tinta">
              <Paperclip className="size-4" strokeWidth={1.8} aria-hidden />
              Elegir foto (también de iPhone) o PDF
              <input type="file" multiple accept={TIPOS_DE_ADJUNTO.join(",")} className="sr-only"
                onChange={(e) => { setArchivos((a) => [...a, ...Array.from(e.target.files ?? [])]); e.target.value = ""; }} />
            </label>
            {archivos.length > 0 && (
              <ul className="mt-2 grid gap-1">
                {archivos.map((a, i) => (
                  <li key={`${a.name}-${i}`} className="flex items-center justify-between gap-2 rounded-control bg-sand/50 px-3 py-1.5 text-xs">
                    <span className="truncate">{a.name} · {pesoLegible(a.size)}</span>
                    <button type="button" aria-label={`Quitar ${a.name}`} className="text-taupe hover:text-rojo"
                      onClick={() => setArchivos((xs) => xs.filter((_, j) => j !== i))}>
                      <X className="size-3.5" aria-hidden />
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </section>
      )}

      {paso === 4 && (
        <section>
          <h2 className="font-serif text-xl">¿Qué esperas que pase?</h2>
          <p className="mb-3.5 text-taupe">Ayuda a quien lo lea a saber qué hacer. Puedes cambiar de idea después, en la conversación.</p>
          <div className="grid gap-2.5 sm:grid-cols-4">
            {ESPERAS.map((e) => (
              <button key={e.valor} type="button" onClick={() => setEspera(e.valor)}
                className={cx(
                  "grid gap-1 rounded-superficie border bg-papel p-3.5 text-left transition-colors duration-150",
                  espera === e.valor ? "border-tinta ring-1 ring-tinta" : "border-sand hover:border-taupe/40",
                )}>
                <span className="font-medium">{e.titulo}</span>
                <span className="text-xs text-taupe">{e.ayuda}</span>
              </button>
            ))}
          </div>

          <div className={cx(
            "mt-5 flex items-start gap-3 rounded-superficie border p-4",
            nadieLoLee ? "border-rojo/35 bg-rojo/5" : "border-pizarra/25 bg-pizarra/10",
          )}>
            <Eye className="mt-0.5 size-5 shrink-0 text-pizarra" strokeWidth={1.8} aria-hidden />
            <div className="grid gap-1">
              {quienLee === null ? (
                <span className="text-taupe">Comprobando quién lo va a leer…</span>
              ) : nadieLoLee ? (
                <span className="font-medium text-rojo-profundo">
                  Hoy no hay en Dynamic nadie que pueda recibir este reporte sin estar mencionado en él. Entrégalo en
                  sobre cerrado a Desarrollo Organizacional o a la Gerencia General (48.7), o acude a SUNAFIL, al MTPE,
                  al Ministerio Público o a la Policía (48.9).
                </span>
              ) : (
                <span className="font-medium">Lo van a leer: {quienLee.join(", ")}.</span>
              )}
              {!nadieLoLee && (
                <span className="text-taupe">
                  {tituloX
                    ? "Tu líder no lo ve. Nadie te pondrá frente a la otra persona (48.14). Las represalias están prohibidas (art. 51)."
                    : "La persona reportada no sabrá que fuiste tú. Las represalias están prohibidas (arts. 43-A.7 y 43-B.5)."}
                </span>
              )}
              {!nadieLoLee && (
                <span className="text-taupe">
                  {tituloX
                    ? "Te ofrecen atención en salud en 1 día hábil y medidas de protección en 3. El informe de quien investiga llega en 15 días calendario."
                    : vence
                      ? <>Te responden por escrito a más tardar el <strong className="font-medium text-tinta">{fechaEnPalabras(vence)}</strong>.</>
                      : null}
                </span>
              )}
            </div>
          </div>
        </section>
      )}

      {tituloX && (
        <div className="mt-4 rounded-superficie border border-sand p-4">
          <h2 className="mb-1.5 font-serif text-lg">Tu queja va por el Título X</h2>
          <ul className="ml-4 list-disc space-y-1 text-taupe">
            <li>La leen <strong className="font-medium text-tinta">Desarrollo Organizacional</strong> y <strong className="font-medium text-tinta">quien investiga en tu sede</strong>. Tu líder no la ve.</li>
            <li>Nadie te pondrá frente a la otra persona ni te hará repetirlo una y otra vez (48.14).</li>
            <li>También puedes entregarla en sobre cerrado, o acudir directo a SUNAFIL, al MTPE, a la Policía o al Ministerio Público (48.9).</li>
          </ul>
          <p className="mt-2 text-xs text-taupe">Solo es obligatorio contar qué pasó (48.8). Todo lo demás es opcional.</p>
        </div>
      )}

      {(falta || errorEnvio) && (
        <p className={cx("mt-4 text-xs", errorEnvio ? "text-rojo" : "text-taupe")}>{errorEnvio ?? falta}</p>
      )}

      <div className="mt-5 flex justify-between gap-3">
        <Boton onClick={() => setPaso((p) => Math.max(1, p - 1))} disabled={paso === 1 || !!enviando}>Atrás</Boton>
        {paso < 4 ? (
          <Boton variante="primario" disabled={!!falta} onClick={() => setPaso((p) => p + 1)}>Siguiente</Boton>
        ) : (
          <Boton variante="primario" disabled={!!falta || nadieLoLee || !!enviando} cargando={!!enviando}
            onClick={() => void enviar()}>
            {enviando ?? "Enviar reporte"}
          </Boton>
        )}
      </div>
    </main>
  );
}

function SelectorPersonas({
  etiqueta, elegidas, opciones, nombreDe, onCambiar,
}: {
  etiqueta: string;
  elegidas: string[];
  opciones: Persona[];
  nombreDe: Map<string, string>;
  onCambiar: (ids: string[]) => void;
}) {
  return (
    <div>
      <CampoSelect etiqueta={etiqueta} value="" onChange={(e) => { if (e.target.value) onCambiar([...elegidas, e.target.value]); }}>
        <option value="">Busca en el equipo…</option>
        {opciones.map((p) => (
          <option key={p.id} value={p.id}>
            {p.nombre}{p.cargo ? ` · ${p.cargo}` : ""}{p.sede_codigo ? ` · ${p.sede_codigo}` : ""}
          </option>
        ))}
      </CampoSelect>
      {elegidas.length > 0 && (
        <div className="mt-2 flex flex-wrap gap-1.5">
          {elegidas.map((id) => (
            <span key={id} className="inline-flex items-center gap-1 rounded-pildora bg-sand py-0.5 pl-2.5 pr-1 text-xs">
              {nombreDe.get(id) ?? "Persona"}
              <button type="button" aria-label="Quitar" className="px-1 text-taupe hover:text-rojo"
                onClick={() => onCambiar(elegidas.filter((x) => x !== id))}>
                <X className="size-3" aria-hidden />
              </button>
            </span>
          ))}
        </div>
      )}
    </div>
  );
}

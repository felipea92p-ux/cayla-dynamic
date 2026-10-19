"use client";

// ============================================================================
// Anuncios — el tablón de Desarrollo Organizacional.
// ----------------------------------------------------------------------------
// Reemplaza el WhatsApp informal para lo que sí importa que quede registrado
// (cierre de planilla, feriado, política nueva): un comunicado que las cuatro
// sedes pueden volver a encontrar dos meses después.
//
// No es `documentos_institucionales` (Normas): ese existe para lo que la ley
// obliga a probar que se entregó, versiona el texto y exige un acuse legal.
// Acá "leído" es un marcador liviano — sirve para que DO vea si un anuncio
// caló, no para sostener una sanción. Ver el encabezado de la 0351.
// ============================================================================

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { Cargando, SinDatos } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { useToast } from "@/components/toast";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { NovedadesDelSistema } from "@/components/novedades-del-sistema";
import { puedeGestionarAnuncios } from "@cayla-dynamic/shared";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { AyudaPantalla } from "@/components/ui/ayuda-pantalla";
import { sobretituloDeHoy } from "@/lib/admin/sobretitulo";

interface Sede { id: string; codigo: string; nombre: string; }

interface Anuncio {
  id: string;
  titulo: string;
  cuerpo: string;
  sede_id: string | null;
  sede_codigo: string | null;
  publicado_por_nombre: string;
  publicado_at: string;
  anulado_at: string | null;
  mi_leido_at: string | null;
  total_lectores: number;
}

function fechaHora(iso: string): string {
  return new Intl.DateTimeFormat("es-PE", {
    day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit",
  }).format(new Date(iso));
}

export default function AnunciosPage() {
  const router = useRouter();
  const { avisar } = useToast();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const puedePublicar = puedeGestionarAnuncios(rol);

  const [sedes, setSedes] = useState<Sede[]>([]);
  const [anuncios, setAnuncios] = useState<Anuncio[]>([]);
  const [cargando, setCargando] = useState(true);

  const [titulo, setTitulo] = useState("");
  const [cuerpo, setCuerpo] = useState("");
  const [sedeId, setSedeId] = useState("");
  const [publicando, setPublicando] = useState(false);

  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  // Sin `setCargando(true)` al entrar: el estado ya arranca en `true` (más
  // abajo), y ponerlo aquí ejecutaría un setState de forma síncrona dentro
  // del efecto que llama a `cargar` — lo que el linter marca como riesgo de
  // renders en cascada. Las recargas posteriores (tras publicar/anular/
  // marcar leído) simplemente no vuelven a mostrar el spinner, que además es
  // mejor: la lista no parpadea por una acción que el usuario ya vio confirmar.
  const cargar = useCallback(async () => {
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    const [{ data: sd }, { data: an, error: eAn }] = await Promise.all([
      supabase.from("sedes").select("id, codigo, nombre").order("codigo"),
      // `true`: si quien pregunta es DO, trae también los anulados (historial).
      // Para cualquier otra persona el propio RPC lo reduce a solo vigentes.
      supabase.rpc("fn_anuncios_vigentes", { p_incluir_anulados: true }),
    ]);
    if (eAn) {
      avisar("error", mensajeDeError(eAn, "cargar"));
      setCargando(false);
      return;
    }
    setSedes((sd as Sede[]) ?? []);
    setAnuncios((an as Anuncio[]) ?? []);
    setCargando(false);
  }, [supabase, router, avisar]);

  useEffect(() => { void (async () => { await cargar(); })(); }, [cargar]);

  async function publicar() {
    if (!titulo.trim() || !cuerpo.trim()) {
      avisar("error", "El anuncio necesita título y cuerpo.");
      return;
    }
    setPublicando(true);
    const { error } = await supabase.rpc("fn_publicar_anuncio", {
      p_titulo: titulo.trim(),
      p_cuerpo: cuerpo.trim(),
      p_sede_id: sedeId || null,
    });
    setPublicando(false);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    setTitulo(""); setCuerpo(""); setSedeId("");
    await cargar();
    avisar("ok", "Anuncio publicado.");
  }

  async function anular(id: string) {
    const { error } = await supabase.rpc("fn_anular_anuncio", { p_id: id });
    if (error) { avisar("error", mensajeDeError(error)); return; }
    await cargar();
    avisar("ok", "Anuncio anulado.");
  }

  async function marcarLeido(id: string) {
    // Optimista: no hace falta esperar la vuelta del servidor para que el
    // botón cambie — es un marcador liviano, no una acción que pueda fallar
    // de forma que a alguien le importe verlo revertirse.
    setAnuncios((prev) => prev.map((a) => (a.id === id ? { ...a, mi_leido_at: new Date().toISOString() } : a)));
    const { error } = await supabase.rpc("fn_marcar_anuncio_leido", { p_id: id });
    if (error) { await cargar(); avisar("error", mensajeDeError(error)); }
  }

  const vigentes = anuncios.filter((a) => !a.anulado_at);
  const anulados = anuncios.filter((a) => a.anulado_at);

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        <CabeceraPagina
          sobretitulo={sobretituloDeHoy("Publicaciones")}
          titulo="Anuncios"
          descripcion="Los comunicados de Desarrollo Organizacional al equipo, y las novedades del sistema."
          ayuda={
            <AyudaPantalla
              titulo="Qué hay en Anuncios"
              intro="Comunicados de Desarrollo Organizacional al equipo: cierre de planilla, feriados, política nueva."
              secciones={[
                { titulo: "Por qué están aquí", texto: "Quedan para que se puedan volver a encontrar, a diferencia de un chat." },
                { titulo: "Novedades del sistema", texto: "Más abajo: qué mejoró en Dynamic y por qué te sirve." },
              ]}
            />
          }
        />

        {/* Con permiso para publicar, el formulario va fijo a un lado y la
            lista ocupa el resto del ancho — como un compositor de correo, no
            como un formulario apilado encima de la lista que lee todo el
            mundo. Sin ese permiso no hay nada que poner ahí, así que la
            lista sola queda centrada en una columna de lectura. */}
        <div className={puedePublicar ? "grid items-start gap-6 lg:grid-cols-[360px_1fr]" : "mx-auto w-full max-w-2xl"}>
          {puedePublicar && (
            <div className="rounded-2xl border border-sand bg-papel p-5 lg:sticky lg:top-6">
              <h2 className="mb-3 text-sm font-medium">Publicar un anuncio</h2>
              <div className="flex flex-col gap-3">
                <Campo etiqueta="Título" value={titulo} onChange={(e) => setTitulo(e.target.value)}
                  maxLength={200} placeholder="ej. La planilla cierra el 28" />
                <AreaTexto etiqueta="Cuerpo" value={cuerpo} onChange={(e) => setCuerpo(e.target.value)}
                  rows={4} placeholder="El detalle del comunicado…" />
                <CampoSelect etiqueta="A quién" value={sedeId} onChange={(e) => setSedeId(e.target.value)}>
                  <option value="">Todas las sedes</option>
                  {sedes.map((s) => <option key={s.id} value={s.id}>Solo {s.nombre}</option>)}
                </CampoSelect>
                <div>
                  <Boton variante="primario" onClick={publicar} disabled={publicando}>
                    {publicando ? "Publicando…" : "Publicar"}
                  </Boton>
                </div>
              </div>
            </div>
          )}

          <div>
            <h2 className="mb-3 font-serif text-xl text-tinta">Comunicados</h2>
            {cargando ? (
              <Cargando />
            ) : vigentes.length === 0 ? (
              <SinDatos texto="No hay anuncios vigentes." pista={puedePublicar ? "Publica el primero al lado." : undefined} />
            ) : (
              <ul className="space-y-3">
                {vigentes.map((a) => (
                  <li key={a.id} className="rounded-2xl border border-sand bg-papel p-4">
                    <div className="flex flex-wrap items-baseline justify-between gap-2">
                      <h3 className="font-serif text-lg text-tinta">{a.titulo}</h3>
                      <span className="text-xs text-taupe">
                        {a.sede_codigo ? `Solo ${a.sede_codigo}` : "Todas las sedes"}
                      </span>
                    </div>
                    <p className="mt-2 whitespace-pre-wrap text-sm text-tinta">{a.cuerpo}</p>
                    <div className="mt-3 flex flex-wrap items-center justify-between gap-2 border-t border-sand/70 pt-3 text-xs text-taupe">
                      <span>
                        {a.publicado_por_nombre} · {fechaHora(a.publicado_at)} · {a.total_lectores} lectura{a.total_lectores === 1 ? "" : "s"}
                      </span>
                      <div className="flex items-center gap-2">
                        {a.mi_leido_at ? (
                          <span>Leíste esto</span>
                        ) : (
                          <Boton variante="sutil" tamano="sm" onClick={() => marcarLeido(a.id)}>
                            Marcar como leído
                          </Boton>
                        )}
                        {puedePublicar && (
                          <Boton variante="peligro" tamano="sm" onClick={() => anular(a.id)}>
                            Anular
                          </Boton>
                        )}
                      </div>
                    </div>
                  </li>
                ))}
              </ul>
            )}

            {puedePublicar && anulados.length > 0 && (
              <details className="mt-6">
                <summary className="cursor-pointer text-sm text-taupe">
                  Anulados ({anulados.length})
                </summary>
                <ul className="mt-3 space-y-2">
                  {anulados.map((a) => (
                    <li key={a.id} className="rounded-xl border border-sand/60 bg-papel/50 p-3 text-sm text-taupe">
                      <span className="line-through">{a.titulo}</span>
                      {" — "}
                      {a.publicado_por_nombre} · {fechaHora(a.publicado_at)}
                    </li>
                  ))}
                </ul>
              </details>
            )}

            {/* Espera a que termine la carga para que `rol` casi siempre ya
                haya llegado: sin esperar, las novedades de panel y de DO
                aparecerían de golpe debajo de una lista que ya se dibujó. Si
                el rol no llega (cuenta sin ficha), se ven las de todos y nada
                más — no depende de nada externo para mostrarse. */}
            {!cargando && <NovedadesDelSistema rol={rol} />}
          </div>
        </div>
      </main>
    </div>
  );
}

"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { Info } from "lucide-react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { hoyLima, puedeNombrarInvestigadora, puedeVerCasos } from "@cayla-dynamic/shared";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { fechaLargaLima } from "@/lib/admin/planilla/formato";
import { useToast } from "@/components/toast";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { Cargando } from "@/components/cargando";
import { cx } from "@/components/ui/cx";
import { etiquetaDeEstado, etiquetaDeVia, fechaEnPalabras } from "@/lib/reportes";

/**
 * «Casos» — los reportes que le toca gestionar a quien mira (plan, secciones
 * 7 y 9; spike aprobado en docs/spike-reportes.html).
 *
 * QUÉ SE VE LO DECIDE LA BASE. `fn_reportes_bandeja` ya devuelve solo lo que
 * la regla de la 0483 deja ver: la líder, lo de su sede sobre colaboradoras,
 * la empresa, ideas y consultas; DO, todo menos lo que la menciona; la
 * Gerencia General, lo de todas las sedes y lo que es sobre DO. Un admin sin
 * la marca de Gerencia General no recibe ningún caso, y la pantalla le dice
 * por qué en vez de mostrar una lista vacía que parece «no hay nada».
 *
 * LA LISTA NO DICE QUIÉN FUE REPORTADA. Se ve el código, el camino, la sede y
 * el plazo; a quién menciona se lee en la ficha, que deja rastro al abrirse.
 *
 * TAMBIÉN VIVEN AQUÍ las instrucciones que DO le encarga a la líder en un caso
 * del Título X (sin el caso: plan, decisión 16) y el registro de quién
 * investiga en cada sede, que consta en acta (48.3).
 */

type FilaCaso = {
  id: string; codigo: string; tipo: string; via: string; urgente: boolean; estado: string;
  gestiona: string | null; mi_motivo: string; sede_codigo: string; autora: string; creado_at: string;
  proximo_plazo: string | null; proximo_norma: string | null; proximo_vence_at: string | null;
  semaforo: string | null; plazos_vencidos: number;
};
type Medida = { id: string; instruccion: string; vigente_hasta: string | null; cumplida_at: string | null; creado_at: string };
type Organo = {
  id: string; sede_codigo: string; sede_nombre: string; persona_id: string; nombre: string;
  papel: string; desde: string; hasta: string | null; acta: string | null;
};

const LLEVA: Record<string, string> = { lider: "Líder", do: "DO", gerencia: "Gerencia" };
const PAPEL: Record<string, string> = { delegada: "Delegada", suplente: "Suplente", designada: "Designada" };
const SEMAFORO: Record<string, { texto: string; variante: "alerta" | "advertencia" | "positivo" }> = {
  vencido: { texto: "Vencido", variante: "alerta" },
  por_vencer: { texto: "Por vencer", variante: "advertencia" },
  en_plazo: { texto: "En plazo", variante: "positivo" },
};

export default function CasosPage() {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const { avisar } = useToast();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;

  const [casos, setCasos] = useState<FilaCaso[] | null>(null);
  const [medidas, setMedidas] = useState<Medida[]>([]);
  const [organos, setOrganos] = useState<Organo[]>([]);
  const [veCasos, setVeCasos] = useState<boolean | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [filtro, setFiltro] = useState<"todos" | "mios" | "vencidos">("todos");

  const cargar = useCallback(async () => {
    const [c, m, o, v] = await Promise.all([
      supabase.rpc("fn_reportes_bandeja"),
      supabase.rpc("fn_mis_medidas"),
      supabase.rpc("fn_organos_titulo_x"),
      supabase.rpc("fn_ve_casos"),
    ]);
    if (c.error) { setError(mensajeDeError(c.error, "leer los casos")); return; }
    setError(null);
    setCasos((c.data ?? []) as FilaCaso[]);
    setMedidas((m.data ?? []) as Medida[]);
    setOrganos((o.data ?? []) as Organo[]);
    setVeCasos(v.data === true);
  }, [supabase]);

  // No espera a la ficha: la base ya decide qué devuelve a cada sesión, y una
  // cuenta sin ficha enlazada se quedaría esperando para siempre.
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void cargar();
  }, [cargar]);

  async function medidaCumplida(id: string) {
    const { error: e } = await supabase.rpc("fn_reporte_medida_cumplida", { p_medida: id });
    if (e) { avisar("error", mensajeDeError(e, "marcar la instrucción")); return; }
    avisar("ok", "Instrucción marcada como cumplida.");
    await cargar();
  }

  if (yo && !puedeVerCasos(rol)) {
    return (
      <main className="flex flex-1 items-center justify-center p-6">
        <p className="max-w-md text-center text-taupe">Los casos los gestionan las líderes de equipo, Desarrollo Organizacional y la Gerencia General.</p>
      </main>
    );
  }

  const visibles = (casos ?? []).filter((c) =>
    filtro === "todos" ? true : filtro === "vencidos" ? c.semaforo === "vencido" : c.gestiona === c.mi_motivo);
  const pendientes = medidas.filter((m) => !m.cumplida_at);

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        <div className="mx-auto w-full max-w-5xl text-sm">
          <CabeceraPagina
            titulo="Casos"
            descripcion="Los reportes del equipo que te toca gestionar. Lo urgente primero; después, lo que vence antes."
          />
          <p className="mb-5 flex items-center gap-2 text-xs text-taupe">
            <Info className="size-4" strokeWidth={1.8} aria-hidden />
            Un reporte no es una falta. Nada se sanciona desde aquí: si corresponde, se abre un expediente en Disciplina.
          </p>

          {error && <p className="mb-4 rounded-control bg-rojo/10 px-3 py-2 text-rojo-profundo">{error}</p>}

          {veCasos === false && puedeNombrarInvestigadora(rol) && (
            <p className="mb-4 rounded-superficie border border-sand p-4 text-taupe">
              Tu cuenta tiene rol de administración pero no es la Gerencia General, así que no gestiona reportes: la
              regla del Reglamento no te muestra ninguno. Si crees que deberías verlos, habla con Desarrollo Organizacional.
            </p>
          )}

          {pendientes.length > 0 && (
            <section className="mb-6 rounded-superficie border border-pizarra/30 bg-pizarra/10 p-4">
              <h2 className="mb-1 font-serif text-lg">Instrucciones que te encargaron</h2>
              <p className="mb-3 text-xs text-taupe">
                Son medidas que Desarrollo Organizacional dictó en un caso. No se te muestra el caso a propósito: solo lo
                que hay que hacer.
              </p>
              <ul className="grid gap-2">
                {pendientes.map((m) => (
                  <li key={m.id} className="flex flex-wrap items-center justify-between gap-3 rounded-control bg-papel px-3.5 py-2.5">
                    <span>
                      <span className="block">{m.instruccion}</span>
                      <span className="text-xs text-taupe">
                        Desde el {fechaLargaLima(m.creado_at)}
                        {m.vigente_hasta ? ` · hasta el ${fechaLargaLima(m.vigente_hasta + "T12:00:00-05:00")}` : " · hasta nuevo aviso"}
                      </span>
                    </span>
                    <Boton tamano="sm" onClick={() => void medidaCumplida(m.id)}>Ya lo hice</Boton>
                  </li>
                ))}
              </ul>
            </section>
          )}

          <div className="mb-3 flex flex-wrap gap-1.5">
            {([["todos", "Abiertos"], ["mios", "Lo que llevo yo"], ["vencidos", "Vencidos"]] as const).map(([v, t]) => (
              <button key={v} type="button" onClick={() => setFiltro(v)}
                className={cx("rounded-pildora border px-3 py-1 text-xs",
                  filtro === v ? "border-tinta bg-tinta text-crema" : "border-sand text-taupe hover:text-tinta")}>
                {t}
                {v === "vencidos" && casos ? ` · ${casos.filter((c) => c.semaforo === "vencido").length}` : ""}
              </button>
            ))}
          </div>

          {casos === null && !error && <Cargando />}
          {casos && visibles.length === 0 && (
            <p className="rounded-superficie border border-dashed border-sand p-5 text-taupe">
              {filtro === "todos" ? "No hay casos abiertos que te toque gestionar." : "Nada en este filtro."}
            </p>
          )}

          {visibles.length > 0 && (
            <div className="overflow-hidden rounded-superficie border border-sand">
              <table className="w-full border-collapse bg-papel">
                <thead>
                  <tr className="bg-sand text-left text-xs text-taupe">
                    <th className="px-3 py-2 font-medium">Caso</th>
                    <th className="px-3 py-2 font-medium">Camino</th>
                    <th className="hidden px-3 py-2 font-medium sm:table-cell">Sede</th>
                    <th className="px-3 py-2 font-medium">Lo lleva</th>
                    <th className="px-3 py-2 font-medium">Próximo plazo</th>
                  </tr>
                </thead>
                <tbody>
                  {visibles.map((c) => {
                    const estado = etiquetaDeEstado(c.estado);
                    const sem = c.semaforo ? SEMAFORO[c.semaforo] : null;
                    return (
                      <tr key={c.id} className="border-t border-sand align-top even:bg-hueso/50 hover:bg-sand/40">
                        <td className="px-3 py-2.5">
                          <Link href={`/admin/casos/${c.id}`} className="font-medium tabular-nums underline-offset-2 hover:underline">
                            {c.codigo}
                          </Link>
                          <div className="mt-1 flex flex-wrap gap-1">
                            {c.urgente && <Insignia variante="alerta" tamano="sm">Urgente</Insignia>}
                            <Insignia variante={estado.variante} tamano="sm">{estado.texto}</Insignia>
                          </div>
                        </td>
                        <td className="px-3 py-2.5">{etiquetaDeVia(c.via, c.tipo)}</td>
                        <td className="hidden px-3 py-2.5 sm:table-cell">{c.sede_codigo}</td>
                        <td className="px-3 py-2.5">{c.gestiona ? LLEVA[c.gestiona] ?? c.gestiona : "—"}</td>
                        <td className="px-3 py-2.5">
                          {sem && <Insignia variante={sem.variante} tamano="sm">{sem.texto}</Insignia>}
                          {c.proximo_plazo && (
                            <div className="mt-1 text-xs text-taupe">
                              {c.proximo_plazo}
                              {c.proximo_vence_at ? ` · ${fechaEnPalabras(c.proximo_vence_at)}` : ""}
                            </div>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}

          <SeccionOrganos organos={organos} puedeNombrar={puedeNombrarInvestigadora(rol)} alGuardar={cargar} />
        </div>
      </main>
    </div>
  );
}

function SeccionOrganos({ organos, puedeNombrar, alGuardar }: {
  organos: Organo[]; puedeNombrar: boolean; alGuardar: () => Promise<void>;
}) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const { avisar } = useToast();
  const [abierto, setAbierto] = useState(false);
  const [sedes, setSedes] = useState<{ id: string; nombre: string }[]>([]);
  const [padron, setPadron] = useState<{ id: string; nombre: string; sede_codigo: string | null }[]>([]);
  const [sede, setSede] = useState("");
  const [persona, setPersona] = useState("");
  const [papel, setPapel] = useState("designada");
  const [desde, setDesde] = useState(hoyLima());
  const [acta, setActa] = useState("");
  const [guardando, setGuardando] = useState(false);

  useEffect(() => {
    if (!abierto) return;
    void (async () => {
      const [s, p] = await Promise.all([
        supabase.from("sedes").select("id, nombre").eq("activa", true).order("nombre"),
        supabase.rpc("fn_reporte_padron"),
      ]);
      setSedes((s.data ?? []) as { id: string; nombre: string }[]);
      setPadron((p.data ?? []) as { id: string; nombre: string; sede_codigo: string | null }[]);
    })();
  }, [abierto, supabase]);

  async function guardar() {
    setGuardando(true);
    const { error } = await supabase.rpc("fn_organo_titulo_x_guardar", {
      p_sede: sede, p_persona: persona, p_papel: papel, p_desde: desde, p_acta: acta,
    });
    setGuardando(false);
    if (error) { avisar("error", mensajeDeError(error, "registrar a quien investiga")); return; }
    avisar("ok", "Registrado.");
    setAbierto(false); setSede(""); setPersona(""); setActa("");
    await alGuardar();
  }

  const vigentes = organos.filter((o) => !o.hasta || o.hasta >= hoyLima());

  return (
    <section className="mt-8 rounded-superficie border border-sand p-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="font-serif text-lg">Quién investiga el Título X en cada sede</h2>
          <p className="text-xs text-taupe">
            La Delegada que eligen las trabajadoras, su suplente, o mientras no haya, quien designe la Gerencia General
            (48.3). Una queja de una sede sin nadie aquí llega sin quién la investigue.
          </p>
        </div>
        {puedeNombrar && !abierto && <Boton tamano="sm" onClick={() => setAbierto(true)}>Registrar con acta</Boton>}
      </div>

      {vigentes.length === 0 ? (
        <p className="mt-3 text-rojo-profundo">Ninguna sede tiene a alguien registrado.</p>
      ) : (
        <ul className="mt-3 grid gap-1">
          {vigentes.map((o) => (
            <li key={o.id} className="flex flex-wrap gap-x-2">
              <span className="font-medium">{o.sede_nombre}</span>
              <span>· {o.nombre}</span>
              <span className="text-taupe">· {PAPEL[o.papel] ?? o.papel} desde el {fechaLargaLima(o.desde + "T12:00:00-05:00")}</span>
            </li>
          ))}
        </ul>
      )}

      {abierto && (
        <div className="mt-4 grid gap-3 border-t border-sand pt-4 sm:grid-cols-2">
          <CampoSelect etiqueta="Sede" value={sede} onChange={(e) => setSede(e.target.value)}>
            <option value="">Elige la sede</option>
            {sedes.map((s) => <option key={s.id} value={s.id}>{s.nombre}</option>)}
          </CampoSelect>
          <CampoSelect etiqueta="Persona" value={persona} onChange={(e) => setPersona(e.target.value)}>
            <option value="">Elige a la persona</option>
            {padron.map((p) => <option key={p.id} value={p.id}>{p.nombre}{p.sede_codigo ? ` · ${p.sede_codigo}` : ""}</option>)}
          </CampoSelect>
          <CampoSelect etiqueta="Papel" value={papel} onChange={(e) => setPapel(e.target.value)}>
            <option value="designada">Designada (transitoria)</option>
            <option value="delegada">Delegada elegida</option>
            <option value="suplente">Suplente elegida</option>
          </CampoSelect>
          <Campo etiqueta="Desde" type="date" value={desde} onChange={(e) => setDesde(e.target.value || hoyLima())} />
          <div className="sm:col-span-2">
            <Campo etiqueta="Acta (número o descripción)" value={acta} onChange={(e) => setActa(e.target.value)}
              placeholder="Resolución de designación transitoria, 2026-09-28" />
          </div>
          <div className="flex gap-2 sm:col-span-2">
            <Boton variante="primario" cargando={guardando} disabled={!sede || !persona || acta.trim().length < 3}
              onClick={() => void guardar()}>Registrar</Boton>
            <Boton variante="sutil" onClick={() => setAbierto(false)}>Cancelar</Boton>
          </div>
        </div>
      )}
    </section>
  );
}

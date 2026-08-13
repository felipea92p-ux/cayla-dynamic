"use client";

import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Colibri } from "@/components/marca";
import { TZ_LIMA, hoyLima } from "@cayla-dynamic/shared";

/**
 * «Lo mío» — lo que cada persona ve de sí misma.
 *
 * POR QUÉ ESTÁ FUERA DE /admin
 *
 * El layout de `(admin)` no comprueba ningún rol: es un `<div>`. Cada pantalla se
 * defiende sola pidiendo sesión, pero ninguna pregunta QUIÉN eres. Meter aquí a
 * alguien con rol `integrante` dejaría alcanzables las 35 pantallas del panel, y
 * confiar en que las capas de abajo aguanten es la suposición que este
 * repositorio ha aprendido a medir en vez de dar por buena.
 *
 * ⚠ EL ERROR QUE ESTA PANTALLA YA COMETIÓ, Y QUE NO SE PUEDE REPETIR
 *
 * La primera versión (2026-08-12) no filtraba por persona: pedía `personas` con
 * `.limit(1)` y las jornadas sin `persona_id`, dando por hecho que la RLS
 * devolvería «lo suyo». Eso es cierto para una integrante y FALSO para todas las
 * demás: a una encargada, `personas_select_supervisor` le devuelve su sede
 * entera, y a DO, `personas_select_admin_lider` le devuelve a todo el mundo.
 *
 * Resultado medido en producción: Danitza —encargada— entró y la pantalla le
 * mostró el nombre de Dayana y 148 días, 1098 horas y 9 de 150 tardanzas, que
 * son la suma de medio equipo. No fue una fuga —esos datos ya los ve en el
 * panel, es su trabajo— pero la pantalla mintió sobre DE QUIÉN eran, en la
 * pantalla que se llama «lo mío».
 *
 * La regla que sale de ahí: SE FILTRA SIEMPRE POR `persona_id`, explícitamente,
 * en cada consulta. La RLS es la red de abajo, nunca el mecanismo. Una consulta
 * que depende de la RLS para acertar devuelve cosas distintas según quién
 * pregunte, y eso no se ve hasta que alguien con más permisos la abre.
 *
 * QUÉ VE, Y QUÉ NO
 *
 * Sus días, sus horas, sus tardanzas y el detalle de cada día. Nada de dinero:
 * ni sueldo, ni boleta, ni sobretiempo — decisión de Felipe (2026-08-11). En
 * particular NO el «tiempo adicional» del panel: son horas por encima del
 * horario programado y NO es sobretiempo pagable (desde la 0185 se mide contra
 * 48 h SEMANALES por ciclo), así que enseñarlo invita a leerlo como «me deben
 * estas horas».
 */

interface Yo {
  id: string;
  nombre: string;
  fechaIngreso: string | null;
}

interface Dia {
  fecha: string;
  entrada_ts: string | null;
  salida_final_ts: string | null;
  horas_trabajadas: number | null;
  minutos_tarde: number | null;
  estado: string;
}

const MESES = [
  "enero", "febrero", "marzo", "abril", "mayo", "junio",
  "julio", "agosto", "setiembre", "octubre", "noviembre", "diciembre",
];

/** «2026-07-29» → «29 de julio». */
function diaYMes(iso: string): string {
  const [, m, d] = iso.split("-");
  return `${Number(d)} de ${MESES[Number(m) - 1]}`;
}

/** 7.53 → «7h 32m». La gente cuenta en horas y minutos, no en decimales. */
function comoReloj(horas: number): string {
  const total = Math.round(horas * 60);
  return `${Math.floor(total / 60)}h ${String(total % 60).padStart(2, "0")}m`;
}

/** La hora de un marcaje, en Lima. Nunca `toLocaleTimeString` a secas: el huso
 *  del navegador no es el que decide a qué día pertenece una marca. */
function hora(iso: string | null): string {
  if (!iso) return "—";
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA, hour: "2-digit", minute: "2-digit", hour12: true,
  }).format(new Date(iso));
}

/** Hoy menos N días, en fecha de Lima. */
function haceDias(n: number): string {
  const [a, m, d] = hoyLima().split("-").map(Number);
  const x = new Date(Date.UTC(a, m - 1, d));
  x.setUTCDate(x.getUTCDate() - n);
  return x.toISOString().slice(0, 10);
}

export default function MioPage() {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const [sesion, setSesion] = useState<boolean | null>(null);
  const [yo, setYo] = useState<Yo | null>(null);
  const [dias, setDias] = useState<Dia[]>([]);
  const [perdonadas, setPerdonadas] = useState<Set<string>>(new Set());
  const [cargando, setCargando] = useState(false);
  const [aviso, setAviso] = useState<string | null>(null);

  // El rango. Por defecto los últimos 30 días: es lo que se entiende por «el
  // último mes» dicho en voz alta, y siempre incluye lo de esta semana — que es
  // lo primero que alguien mira. El periodo de pago está a un botón.
  const [desde, setDesde] = useState(haceDias(30));
  const [hasta, setHasta] = useState(hoyLima());

  const [email, setEmail] = useState("");
  const [clave, setClave] = useState("");
  const [entrando, setEntrando] = useState(false);
  const [errorLogin, setErrorLogin] = useState<string | null>(null);

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => setSesion(Boolean(data.session)));
  }, [supabase]);

  async function entrar(e: FormEvent) {
    e.preventDefault();
    setEntrando(true);
    setErrorLogin(null);
    const { error } = await supabase.auth.signInWithPassword({ email, password: clave });
    setEntrando(false);
    if (error) { setErrorLogin("Correo o contraseña incorrectos."); return; }
    setSesion(true);
  }

  // ── Quién soy ─────────────────────────────────────────────────────────────
  // POR auth_user_id, no por «la primera fila que la RLS me deje ver». Ver el
  // comentario de arriba: esa suposición fue el error de la primera versión.
  useEffect(() => {
    if (!sesion) return;
    void (async () => {
      const { data: sesionAuth } = await supabase.auth.getUser();
      const uid = sesionAuth.user?.id;
      if (!uid) { setAviso("No se pudo leer tu sesión. Vuelve a entrar."); return; }

      const { data: p } = await supabase
        .from("personas")
        .select("id, nombres, apellidos, fecha_ingreso")
        .eq("auth_user_id", uid)
        .maybeSingle();

      if (!p) {
        setAviso("Tu cuenta todavía no está enlazada con tu ficha. Avisa a Desarrollo Organizacional.");
        return;
      }
      setYo({
        id: p.id as string,
        nombre: `${p.nombres as string} ${p.apellidos as string}`,
        fechaIngreso: (p.fecha_ingreso as string | null) ?? null,
      });
    })();
  }, [supabase, sesion]);

  // ── Sus días ──────────────────────────────────────────────────────────────
  const cargar = useCallback(async () => {
    if (!yo) return;
    setCargando(true);
    const [{ data: js }, { data: perd }] = await Promise.all([
      supabase.from("jornadas")
        .select("fecha, entrada_ts, salida_final_ts, horas_trabajadas, minutos_tarde, estado")
        .eq("persona_id", yo.id)          // ← explícito. La RLS es la red, no el filtro.
        .gte("fecha", desde).lte("fecha", hasta)
        .order("fecha"),
      supabase.from("tardanzas_justificadas")
        .select("fecha")
        .eq("persona_id", yo.id)
        .gte("fecha", desde).lte("fecha", hasta),
    ]);
    setDias((js as Dia[]) ?? []);
    setPerdonadas(new Set(((perd as { fecha: string }[]) ?? []).map((t) => t.fecha)));
    setCargando(false);
  }, [supabase, yo, desde, hasta]);

  useEffect(() => { void cargar(); }, [cargar]);

  /** El periodo de pago en curso, para el botón. Del 29 al 28 — leído, no calculado. */
  async function irAlPeriodoDePago() {
    const hoy = hoyLima();
    const { data } = await supabase
      .from("periodos_planilla")
      .select("fecha_ini, fecha_fin")
      .lte("fecha_ini", hoy).gte("fecha_fin", hoy)
      .maybeSingle();
    if (!data) { setAviso("No hay un periodo de pago abierto para hoy."); return; }
    setAviso(null);
    setDesde(data.fecha_ini as string);
    setHasta(data.fecha_fin as string);
  }

  const resumen = useMemo(() => {
    // Un día de más de 24 h es un AGREGADO del histórico de 2025 —un mes entero
    // cargado en una fecha—, no una jornada. Suma al total pero no al promedio ni
    // al gráfico, que si no daría una barra imposible y un promedio absurdo.
    const reales = dias.filter((d) => (d.horas_trabajadas ?? 0) <= 24);
    const trabajados = reales.filter((d) => (d.horas_trabajadas ?? 0) > 0);
    const horasReales = reales.reduce((s, d) => s + (d.horas_trabajadas ?? 0), 0);
    return {
      reales,
      total: dias.reduce((s, d) => s + (d.horas_trabajadas ?? 0), 0),
      trabajados: trabajados.length,
      promedio: trabajados.length ? horasReales / trabajados.length : 0,
      // Una tardanza perdonada NO cuenta: si la encargada se la levantó, no tiene
      // por qué seguir viéndola en su marcador.
      tardanzas: dias.filter((d) => (d.minutos_tarde ?? 0) > 0 && !perdonadas.has(d.fecha)).length,
      medidos: dias.filter((d) => d.minutos_tarde !== null).length,
    };
  }, [dias, perdonadas]);

  const maxHoras = Math.max(8, ...resumen.reales.map((d) => d.horas_trabajadas ?? 0));

  if (sesion === null) {
    return <main className="flex min-h-screen items-center justify-center bg-crema text-taupe">Un momento…</main>;
  }

  if (!sesion) {
    return (
      <main className="flex min-h-screen flex-col items-center justify-center gap-8 bg-crema p-8 text-tinta">
        <div className="flex flex-col items-center gap-4">
          <Colibri tono="rojo" className="w-12" />
          <div className="text-center">
            <h1 className="font-serif text-3xl leading-none">Lo mío</h1>
            <p className="etiqueta mt-2 text-taupe">Tus días y tus horas · CAYLA</p>
          </div>
        </div>
        <form onSubmit={entrar} className="flex w-full max-w-xs flex-col gap-3">
          <input type="email" placeholder="correo" value={email} onChange={(e) => setEmail(e.target.value)}
            className="rounded-lg border border-sand bg-crema px-4 py-3 outline-none placeholder:text-taupe/60 focus:border-taupe" required />
          <input type="password" placeholder="contraseña" value={clave} onChange={(e) => setClave(e.target.value)}
            className="rounded-lg border border-sand bg-crema px-4 py-3 outline-none placeholder:text-taupe/60 focus:border-taupe" required />
          {errorLogin && <p className="text-sm text-rojo">{errorLogin}</p>}
          <button type="submit" disabled={entrando}
            className="rounded-lg bg-tinta px-4 py-3 font-medium text-crema transition-colors hover:bg-rojo-profundo disabled:opacity-50">
            {entrando ? "Entrando…" : "Entrar"}
          </button>
          <a href="/admin/olvide-clave" className="text-center text-sm text-taupe underline-offset-2 hover:underline">
            ¿Olvidaste tu clave?
          </a>
        </form>
      </main>
    );
  }

  return (
    <main className="mx-auto min-h-screen w-full max-w-3xl bg-crema px-5 py-8 text-tinta">
      <header className="mb-6 flex items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          <Colibri tono="rojo" className="w-8" />
          <div>
            <h1 className="font-serif text-2xl leading-tight">{yo?.nombre ?? "Lo mío"}</h1>
            <p className="etiqueta text-taupe">Tus días y tus horas</p>
          </div>
        </div>
        <button onClick={() => void supabase.auth.signOut().then(() => setSesion(false))}
          className="text-xs text-taupe underline">Salir</button>
      </header>

      {aviso && <div className="mb-6 rounded-2xl border border-ambar/30 bg-ambar/[0.06] p-4 text-sm">{aviso}</div>}

      {/* ── El filtro ────────────────────────────────────────────────────────
          Abre en los últimos 30 días. El botón del periodo de pago está porque es
          el tramo con el que se le paga —del 29 al 28, leído de la base y nunca
          calculado— y es contra el que va a querer cuadrar su boleta. */}
      <section className="mb-6 flex flex-wrap items-end gap-3 rounded-2xl border border-sand px-4 py-3">
        <label className="flex flex-col gap-1 text-xs text-taupe">Desde
          <input type="date" value={desde} max={hasta} onChange={(e) => setDesde(e.target.value)}
            className="rounded-lg border border-sand bg-crema px-3 py-1.5 text-sm text-tinta" />
        </label>
        <label className="flex flex-col gap-1 text-xs text-taupe">Hasta
          <input type="date" value={hasta} min={desde} max={hoyLima()} onChange={(e) => setHasta(e.target.value)}
            className="rounded-lg border border-sand bg-crema px-3 py-1.5 text-sm text-tinta" />
        </label>
        <div className="flex flex-wrap gap-2">
          <button onClick={() => { setDesde(haceDias(30)); setHasta(hoyLima()); }}
            className="rounded-lg border border-sand px-3 py-1.5 text-xs">Últimos 30 días</button>
          <button onClick={() => void irAlPeriodoDePago()}
            className="rounded-lg border border-sand px-3 py-1.5 text-xs">Periodo de pago</button>
        </div>
      </section>

      <div className="mb-6 grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Tarjeta titulo="Días trabajados" valor={String(resumen.trabajados)} />
        <Tarjeta titulo="Total de horas" valor={comoReloj(resumen.total)} />
        <Tarjeta titulo="Promedio por día" valor={comoReloj(resumen.promedio)} />
        {/* «de N medidos» y no un número suelto: un cero puede significar
            «llegaste puntual» o «no había horario que comparar». */}
        <Tarjeta titulo="Tardanzas" valor={`${resumen.tardanzas} de ${resumen.medidos}`} />
      </div>

      <section className="mb-6 rounded-2xl border border-sand p-5">
        <h2 className="mb-4 font-serif text-lg">Horas por día</h2>
        {cargando ? <p className="text-sm text-taupe">Cargando…</p>
          : resumen.reales.length === 0 ? <p className="text-sm text-taupe">No hay días marcados en este rango.</p>
          : (
            <ul className="flex items-end gap-1 overflow-x-auto pb-2" style={{ height: 180 }}>
              {resumen.reales.map((d) => {
                const h = d.horas_trabajadas ?? 0;
                const tarde = (d.minutos_tarde ?? 0) > 0 && !perdonadas.has(d.fecha);
                return (
                  <li key={d.fecha} className="flex min-w-6 flex-1 flex-col items-center justify-end gap-1"
                    title={`${diaYMes(d.fecha)} · ${comoReloj(h)}${tarde ? " · llegaste tarde" : ""}`}>
                    <div className={`w-full rounded-t ${tarde ? "bg-ambar" : "bg-verde"}`}
                      style={{ height: `${Math.max(2, (h / maxHoras) * 140)}px` }} />
                    <span className="text-[10px] text-taupe">{d.fecha.slice(8)}</span>
                  </li>
                );
              })}
            </ul>
          )}
        <p className="mt-3 text-xs text-taupe">
          En ámbar, los días en que llegaste tarde. Si tu encargada te levantó una tardanza, deja de contar acá.
        </p>
      </section>

      {/* ── El desglose ──────────────────────────────────────────────────────
          Solo los días con marcaje. Un día de descanso o un feriado no tienen por
          qué ocupar una fila vacía en una pantalla que se mira en el teléfono. */}
      <section className="rounded-2xl border border-sand p-5">
        <h2 className="mb-4 font-serif text-lg">Día por día</h2>
        {dias.length === 0 ? (
          <p className="text-sm text-taupe">No hay días marcados en este rango.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-sand text-left">
                  <th className="etiqueta pb-2 font-normal text-taupe">Día</th>
                  <th className="etiqueta pb-2 font-normal text-taupe">Entrada</th>
                  <th className="etiqueta pb-2 font-normal text-taupe">Salida</th>
                  <th className="etiqueta pb-2 font-normal text-taupe">Tardanza</th>
                  <th className="etiqueta pb-2 text-right font-normal text-taupe">Horas</th>
                </tr>
              </thead>
              <tbody>
                {[...dias].reverse().map((d) => {
                  const tarde = (d.minutos_tarde ?? 0) > 0;
                  const perdonada = perdonadas.has(d.fecha);
                  const laPusoElSistema = d.estado === "auto_cerrada_pendiente";
                  return (
                    <tr key={d.fecha} className="border-b border-sand/60">
                      <td className="py-2">{diaYMes(d.fecha)}</td>
                      <td className="py-2">{hora(d.entrada_ts)}</td>
                      <td className="py-2">
                        {hora(d.salida_final_ts)}
                        {/* Esa hora NO la marcó ella: la inventó el auto-cierre porque
                            olvidó marcar. Es justo la que conviene que revise, así que
                            se dice en vez de dejarla pasar por buena. */}
                        {laPusoElSistema && (
                          <span className="ml-2 rounded-full bg-ambar/15 px-2 py-0.5 text-[10px] text-ambar">
                            la puso el sistema
                          </span>
                        )}
                      </td>
                      <td className="py-2">
                        {!tarde ? <span className="text-taupe">—</span>
                          : perdonada ? <span className="text-taupe line-through">{d.minutos_tarde} min</span>
                          : <span className="text-ambar">{d.minutos_tarde} min</span>}
                      </td>
                      <td className="py-2 text-right">{comoReloj(d.horas_trabajadas ?? 0)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <p className="mt-6 text-xs text-taupe">
        Si algo no cuadra, no lo dejes pasar: avisa a tu encargada y se corrige con el motivo anotado. Lo que
        ves sale de tus marcajes, y un marcaje mal registrado se arregla, no se discute al final del mes.
      </p>
    </main>
  );
}

function Tarjeta({ titulo, valor }: { titulo: string; valor: string }) {
  return (
    <div className="rounded-2xl border border-sand px-4 py-3">
      <div className="etiqueta text-taupe">{titulo}</div>
      <div className="mt-1 font-serif text-2xl leading-none">{valor}</div>
    </div>
  );
}

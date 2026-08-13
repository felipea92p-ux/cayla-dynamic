"use client";

import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Colibri } from "@/components/marca";

/**
 * «Lo mío» — lo que cada integrante ve de sí misma.
 *
 * POR QUÉ ESTÁ FUERA DE /admin, Y NO ES UN CAPRICHO DE RUTAS
 *
 * El layout de `(admin)` no comprueba ningún rol: es un `<div>`. Cada pantalla
 * se defiende sola pidiendo sesión, pero ninguna pregunta QUIÉN eres. Meter aquí
 * a alguien con rol `integrante` dejaría alcanzables las 35 pantallas del panel,
 * y confiar en que las de abajo aguanten —RLS, guardas de las funciones— es
 * exactamente la suposición que este repositorio ha aprendido a medir en vez de
 * dar por buena. Auditar 35 pantallas cuesta; tener una sola no.
 *
 * QUÉ VE, Y QUÉ NO
 *
 * Sus días trabajados, sus horas, su promedio y sus tardanzas. Nada de dinero:
 * ni sueldo, ni boleta, ni el sobretiempo — decisión de Felipe (2026-08-11).
 *
 * En particular NO se muestra el «tiempo adicional» que sí sale en la pestaña
 * Desempeño del panel. Ese número son horas por encima del horario programado, y
 * NO es sobretiempo pagable: desde la 0185 el sobretiempo se mide contra 48 h
 * SEMANALES por ciclo, no contra la jornada del día. Enseñarle «6h 26m
 * adicionales» invita a leerlo como «me deben 6h 26m» y a reclamar sobre una
 * cifra que no significa eso.
 *
 * DE DÓNDE SALEN LOS DATOS
 *
 * De consultas normales, sin ninguna función nueva: las políticas
 * `jornadas_select_propia`, `tardj_select_propia` y `personas_select_propia`
 * existen desde la 0003 y la 0053, así que la base devuelve LO SUYO y nada más.
 * Si esta pantalla tuviera un fallo y pidiera el mes de otra persona, la
 * respuesta seguiría siendo vacía. La única pieza que hizo falta añadir fue la
 * lectura del calendario de periodos (0234).
 */

interface Periodo {
  id: string;
  fecha_ini: string;
  fecha_fin: string;
  estado: string;
}

interface Dia {
  fecha: string;
  horas_trabajadas: number | null;
  minutos_tarde: number | null;
}

const MESES = [
  "enero", "febrero", "marzo", "abril", "mayo", "junio",
  "julio", "agosto", "setiembre", "octubre", "noviembre", "diciembre",
];

/** «2026-07-29» → «29 de julio». Sin año: el año va en el encabezado del periodo. */
function diaYMes(iso: string): string {
  const [, m, d] = iso.split("-");
  return `${Number(d)} de ${MESES[Number(m) - 1]}`;
}

/** 7.53 → «7h 32m». La gente cuenta en horas y minutos, no en decimales. */
function comoReloj(horas: number): string {
  const total = Math.round(horas * 60);
  return `${Math.floor(total / 60)}h ${String(total % 60).padStart(2, "0")}m`;
}

export default function MioPage() {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const [sesion, setSesion] = useState<boolean | null>(null);
  const [nombre, setNombre] = useState<string>("");
  const [periodos, setPeriodos] = useState<Periodo[]>([]);
  const [cual, setCual] = useState(0); // 0 = el más reciente
  const [dias, setDias] = useState<Dia[]>([]);
  const [perdonadas, setPerdonadas] = useState<Set<string>>(new Set());
  const [cargando, setCargando] = useState(false);
  const [aviso, setAviso] = useState<string | null>(null);

  // ── Entrar ────────────────────────────────────────────────────────────────
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
    if (error) {
      setErrorLogin("Correo o contraseña incorrectos.");
      return;
    }
    setSesion(true);
  }

  // ── Cargar ────────────────────────────────────────────────────────────────
  const cargar = useCallback(async () => {
    setCargando(true);
    setAviso(null);

    // Su ficha. Por RLS esta consulta devuelve UNA fila: la suya.
    const { data: yo, error: errYo } = await supabase
      .from("personas")
      .select("nombres, apellidos, fecha_ingreso")
      .limit(1)
      .maybeSingle();

    if (errYo || !yo) {
      // Pasa si la cuenta existe en Auth pero no está enlazada a una persona.
      // Se dice, en vez de dejar la pantalla vacía pareciendo que no trabajó.
      setAviso("Tu cuenta todavía no está enlazada con tu ficha. Avisa a Desarrollo Organizacional.");
      setCargando(false);
      return;
    }
    setNombre(`${yo.nombres} ${yo.apellidos}`);

    // El calendario de pago, desde que entró. Nunca se calcula el 29 aquí: el
    // CHECK de la 0025 admite periodos de 20 a 46 días, así que la regla del 29
    // es costumbre, no garantía.
    const { data: peris, error: errPer } = await supabase
      .from("periodos_planilla")
      .select("id, fecha_ini, fecha_fin, estado")
      .gte("fecha_fin", yo.fecha_ingreso ?? "2000-01-01")
      .order("fecha_ini", { ascending: false });

    if (errPer || !peris?.length) {
      setAviso("Todavía no hay periodos de pago cargados.");
      setCargando(false);
      return;
    }
    setPeriodos(peris as Periodo[]);
    setCargando(false);
  }, [supabase]);

  useEffect(() => { if (sesion) void cargar(); }, [sesion, cargar]);

  const periodo = periodos[cual];

  useEffect(() => {
    if (!periodo) return;
    void (async () => {
      setCargando(true);
      const [{ data: js }, { data: perd }] = await Promise.all([
        supabase.from("jornadas")
          .select("fecha, horas_trabajadas, minutos_tarde")
          .gte("fecha", periodo.fecha_ini).lte("fecha", periodo.fecha_fin)
          .order("fecha"),
        supabase.from("tardanzas_justificadas")
          .select("fecha")
          .gte("fecha", periodo.fecha_ini).lte("fecha", periodo.fecha_fin),
      ]);
      setDias((js as Dia[]) ?? []);
      setPerdonadas(new Set(((perd as { fecha: string }[]) ?? []).map((t) => t.fecha)));
      setCargando(false);
    })();
  }, [supabase, periodo]);

  const resumen = useMemo(() => {
    // Un día de más de 24 h es un AGREGADO del histórico de 2025 —un mes entero
    // cargado en una fecha—, no una jornada. Suma al total pero no al promedio ni
    // al gráfico, que si no daría una barra imposible y un promedio absurdo.
    const reales = dias.filter((d) => (d.horas_trabajadas ?? 0) <= 24);
    const trabajados = reales.filter((d) => (d.horas_trabajadas ?? 0) > 0);
    const total = dias.reduce((s, d) => s + (d.horas_trabajadas ?? 0), 0);
    const horasReales = reales.reduce((s, d) => s + (d.horas_trabajadas ?? 0), 0);
    return {
      reales,
      total,
      trabajados: trabajados.length,
      promedio: trabajados.length ? horasReales / trabajados.length : 0,
      // Una tardanza perdonada NO cuenta: si el sistema se la levantó, la persona
      // no tiene por qué seguir viéndola en su marcador.
      tardanzas: dias.filter((d) => (d.minutos_tarde ?? 0) > 0 && !perdonadas.has(d.fecha)).length,
      medidos: dias.filter((d) => d.minutos_tarde !== null).length,
    };
  }, [dias, perdonadas]);

  const maxHoras = Math.max(8, ...resumen.reales.map((d) => d.horas_trabajadas ?? 0));

  // ── Pantallas ─────────────────────────────────────────────────────────────
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
    <main className="mx-auto min-h-screen w-full max-w-2xl bg-crema px-5 py-8 text-tinta">
      <header className="mb-6 flex items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          <Colibri tono="rojo" className="w-8" />
          <div>
            <h1 className="font-serif text-2xl leading-tight">{nombre || "Lo mío"}</h1>
            <p className="etiqueta text-taupe">Tus días y tus horas</p>
          </div>
        </div>
        <button onClick={() => void supabase.auth.signOut().then(() => setSesion(false))}
          className="text-xs text-taupe underline">Salir</button>
      </header>

      {aviso && (
        <div className="mb-6 rounded-2xl border border-ambar/30 bg-ambar/[0.06] p-4 text-sm">{aviso}</div>
      )}

      {periodo && (
        <>
          {/* El periodo, escrito en palabras. «29 de julio al 28 de agosto» dice
              lo que «01/08 – 31/08» no diría: que el mes de pago no es el mes del
              calendario, que es la primera pregunta de todo el mundo. */}
          <div className="mb-6 flex items-center justify-between gap-3 rounded-2xl border border-sand px-4 py-3">
            <button onClick={() => setCual((c) => Math.min(c + 1, periodos.length - 1))}
              disabled={cual >= periodos.length - 1}
              className="text-sm text-taupe disabled:opacity-30" aria-label="Periodo anterior">←</button>
            <div className="text-center">
              <div className="text-sm font-medium">
                Del {diaYMes(periodo.fecha_ini)} al {diaYMes(periodo.fecha_fin)}
              </div>
              <div className="etiqueta text-taupe">
                {periodo.estado === "pagado" ? "ya pagado" : "en curso"}
              </div>
            </div>
            <button onClick={() => setCual((c) => Math.max(c - 1, 0))} disabled={cual === 0}
              className="text-sm text-taupe disabled:opacity-30" aria-label="Periodo siguiente">→</button>
          </div>

          <div className="mb-6 grid grid-cols-2 gap-3 sm:grid-cols-4">
            <Tarjeta titulo="Días trabajados" valor={String(resumen.trabajados)} />
            <Tarjeta titulo="Total de horas" valor={comoReloj(resumen.total)} />
            <Tarjeta titulo="Promedio por día" valor={comoReloj(resumen.promedio)} />
            {/* «de N medidos» y no un número suelto: un cero puede significar
                «llegaste puntual» o «no había horario que comparar», y no es lo
                mismo. El panel lo dice así desde siempre. */}
            <Tarjeta titulo="Tardanzas" valor={`${resumen.tardanzas} de ${resumen.medidos}`} />
          </div>

          <section className="rounded-2xl border border-sand p-5">
            <h2 className="mb-4 font-serif text-lg">Horas por día</h2>
            {cargando ? (
              <p className="text-sm text-taupe">Cargando…</p>
            ) : resumen.reales.length === 0 ? (
              <p className="text-sm text-taupe">No hay días marcados en este periodo.</p>
            ) : (
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

          <p className="mt-6 text-xs text-taupe">
            Si algo no cuadra, no lo dejes pasar: avisa a tu encargada y se corrige con el motivo anotado. Lo
            que ves sale de tus marcajes, y un marcaje mal registrado se arregla, no se discute al final del mes.
          </p>
        </>
      )}
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

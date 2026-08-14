"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { AdminNav } from "../nav";
import { Cargando, SinDatos } from "@/components/cargando";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import { TZ_LIMA, puedeGestionarCatalogos } from "@cayla-dynamic/shared";


function hoyLima(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: TZ_LIMA }).format(new Date());
}
// Fechas planas (sin hora): se formatean en UTC para que no se corran un día.
function fechaCorta(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "short", timeZone: "UTC" })
    .format(new Date(Date.UTC(y, m - 1, d)));
}
function diaSemana(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { weekday: "long", timeZone: "UTC" })
    .format(new Date(Date.UTC(y, m - 1, d)));
}
const soles = (n: number) => `S/ ${n.toFixed(2)}`;

interface Persona { id: string; nombres: string; apellidos: string; sede_base_id: string; }
interface Sede { id: string; codigo: string; nombre: string; }
interface Feriado { fecha: string; nombre: string; }
// Una fila por persona que TRABAJÓ un feriado del rango, con su estado de
// compensación. `estado` en null = todavía se le está pagando la sobretasa.
interface Laborado {
  persona_id: string;
  nombre: string;
  sede: string;
  fecha_feriado: string;
  feriado_nombre: string;
  horas: number;
  sobretasa: number | null;
  dcs_id: string | null;
  fecha_descanso: string | null;
  estado: string | null;
  acta_ref: string | null;
  /** Por qué ese día NO compensa el feriado, o null si compensa bien (0238). */
  no_compensa_porque: string | null;
  /** Escrito solo cuando el día libre cae a más de 30 días del feriado. */
  motivo_fuera_de_plazo: string | null;
}
interface Registro {
  id: string;
  persona_id: string;
  fecha_feriado: string;
  fecha_descanso_sustitutorio: string;
  estado: string;
  acta_ref: string | null;
}
// Una pareja feriado → día libre. Se declaran EXPLÍCITAS, nunca se emparejan
// solas: la regla 1:1 tiene que verse, no adivinarse.
interface Pareja { feriado: string; descanso: string; }
// Resultado de cada intento del lote. Un lote puede quedar a medias (un día que
// cae en el descanso de una sola persona), y eso hay que mostrarlo fila por fila.
interface Resultado { persona: string; feriado: string; descanso: string; error: string | null; }
// El acta SIN el archivo: la lista no baja los megabytes, solo dice si están.
interface Acta {
  referencia: string;
  archivo_nombre: string | null;
  tiene_archivo: boolean;
  peso_kb: number;
  actualizado: string;
  registros: number;
}

const ESTADOS = ["PENDIENTE", "OTORGADO", "NO_OTORGADO"] as const;
// Mismo tope que el resto de papeles firmados desde que el acta vive en el
// almacén y no en una columna de la base (mig. 0175). Antes eran 3 MB, que no
// era una decisión sobre las actas: era el precio de guardarlas como texto.
const MAX_ACTA_BYTES = 50 * 1024 * 1024;


function inicioDeMes(): string {
  return `${hoyLima().slice(0, 7)}-01`;
}
function finDeMes(): string {
  const [y, m] = hoyLima().split("-").map(Number);
  return new Intl.DateTimeFormat("en-CA", { timeZone: "UTC" }).format(new Date(Date.UTC(y, m, 0)));
}

export default function FeriadosPage() {
  const router = useRouter();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const puedeGestionar = puedeGestionarCatalogos(rol);

  const [personas, setPersonas] = useState<Persona[]>([]);
  const [sedes, setSedes] = useState<Sede[]>([]);
  const [feriados, setFeriados] = useState<Feriado[]>([]);
  const [laborados, setLaborados] = useState<Laborado[]>([]);
  /**
   * persona + feriado → por qué ese día compensatorio no compensa.
   *
   * El motivo NO se calcula aquí: lo devuelve `fn_dcs_por_que_no_compensa` a
   * través de fn_feriados_laborados, y es LA MISMA frase con la que el candado
   * bloquea al registrar (0238). Si la pantalla tuviera su propia copia de la
   * regla, el día que una cambie dirían cosas distintas de la misma fila.
   *
   * Se cruza por (persona, feriado) porque esa es la clave 1:1 de la tabla.
   */
  const motivoPorFila = useMemo(
    () => new Map(laborados
      .filter((l) => l.no_compensa_porque)
      .map((l) => [`${l.persona_id}|${l.fecha_feriado}`, l.no_compensa_porque as string])),
    [laborados],
  );
  const [registros, setRegistros] = useState<Registro[]>([]);
  const [cargando, setCargando] = useState(true);
  const [msg, setMsg] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  const [resultados, setResultados] = useState<Resultado[]>([]);
  const [actas, setActas] = useState<Acta[]>([]);
  const [refActa, setRefActa] = useState("");
  const [subiendo, setSubiendo] = useState(false);
  const [progresoActa, setProgresoActa] = useState<number | null>(null);

  // rango de consulta
  const [desde, setDesde] = useState(inicioDeMes());
  const [hasta, setHasta] = useState(finDeMes());

  // formulario por lotes
  const [sedeFiltro, setSedeFiltro] = useState("");
  const [elegidas, setElegidas] = useState<Set<string>>(new Set());
  const [parejas, setParejas] = useState<Pareja[]>([{ feriado: "", descanso: "" }]);
  const [estado, setEstado] = useState<string>("PENDIENTE");
  const [actaRef, setActaRef] = useState("");
  const [guardando, setGuardando] = useState(false);

  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  const cargar = useCallback(async () => {
    setCargando(true);
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    const [{ data: p, error: eP }, { data: sd }, { data: f }, { data: l, error: eL }, { data: r }, { data: ac }] = await Promise.all([
      supabase.from("personas").select("id, nombres, apellidos, sede_base_id")
        .eq("estado", "activo").eq("en_planilla", true).order("nombres"),
      supabase.from("sedes").select("id, codigo, nombre").order("codigo"),
      supabase.from("feriados").select("fecha, nombre").order("fecha", { ascending: false }).limit(40),
      supabase.rpc("fn_feriados_laborados", { p_desde: desde, p_hasta: hasta }),
      supabase.from("feriados_descanso_sustitutorio")
        .select("id, persona_id, fecha_feriado, fecha_descanso_sustitutorio, estado, acta_ref")
        .order("fecha_feriado", { ascending: false }),
      supabase.rpc("fn_actas_descanso", {}),
    ]);
    if (eP) {
      setMsg({ tipo: "error", texto: mensajeDeError(eP, "cargar") });
      setCargando(false);
      return;
    }
    setPersonas((p as Persona[]) ?? []);
    setSedes((sd as Sede[]) ?? []);
    setFeriados((f as Feriado[]) ?? []);
    setLaborados(eL ? [] : ((l as unknown as Laborado[]) ?? []));
    setRegistros((r as Registro[]) ?? []);
    setActas(Array.isArray(ac) ? (ac as unknown as Acta[]) : []);
    setCargando(false);
  }, [supabase, router, desde, hasta]);

  useEffect(() => { void cargar(); }, [cargar]);

  const nombrePorId = useMemo(
    () => new Map(personas.map((x) => [x.id, `${x.nombres} ${x.apellidos}`])),
    [personas],
  );
  const visibles = useMemo(
    () => (sedeFiltro ? personas.filter((p) => p.sede_base_id === sedeFiltro) : personas),
    [personas, sedeFiltro],
  );
  // Solo cuentan las parejas completas: una a medio llenar no debe inflar el total.
  const parejasCompletas = useMemo(
    () => parejas.filter((x) => x.feriado && x.descanso),
    [parejas],
  );
  const totalRegistros = elegidas.size * parejasCompletas.length;

  const sobretasaSinResolver = useMemo(
    () => laborados
      .filter((l) => l.estado !== "OTORGADO")
      .reduce((acc, l) => acc + (l.sobretasa ?? 0), 0),
    [laborados],
  );

  // Las referencias que ya existen en los acuerdos. Se ofrecen en una lista en
  // vez de texto libre: si la referencia se tipea distinta, el acta queda
  // huérfana y el papel no aparece junto a su acuerdo.
  const referencias = useMemo(() => {
    const s = new Set<string>();
    registros.forEach((r) => { if (r.acta_ref) s.add(r.acta_ref); });
    actas.forEach((a) => s.add(a.referencia));
    return [...s].sort();
  }, [registros, actas]);

  const actaPorRef = useMemo(() => new Map(actas.map((a) => [a.referencia, a])), [actas]);

  /**
   * El acta va al almacén de archivos, como el cargo de un memo o un contrato
   * (mig. 0175). Antes se guardaba como texto dentro de la base y por eso tenía
   * que caber en 3 MB — un escaneo de varias hojas no cabía, y no había forma
   * razonable de cumplirlo salvo degradar el papel que hay que poder leer.
   *
   * El archivo sube PRIMERO y se anota DESPUÉS: si la subida falla, no queda
   * una fila diciendo que hay un acta que no existe. Al revés —anotar y luego
   * subir— dejaría la lista mintiendo.
   */
  async function subirActa(file: File) {
    if (!refActa) { setMsg({ tipo: "error", texto: "Elige a qué acuerdo pertenece el acta." }); return; }
    if (file.size > MAX_ACTA_BYTES) {
      setMsg({ tipo: "error", texto: `El archivo pesa ${(file.size / 1024 / 1024).toFixed(1)} MB y el máximo es ${MAX_ACTA_BYTES / 1024 / 1024} MB.` });
      return;
    }
    setSubiendo(true);
    setMsg(null);

    // La referencia va en la ruta pasada por un filtro: es texto que escribe una
    // persona ("Acta 2026-07-28 Taller LIM") y no puede decidir en qué carpeta
    // cae el archivo. La marca de tiempo evita pisar el acta anterior mientras
    // se comprueba que la nueva subió bien.
    const ext = file.name.split(".").pop()?.toLowerCase() ?? "bin";
    const clave = refActa.replace(/[^a-zA-Z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 60) || "acta";
    const ruta = `${clave}/${Date.now()}.${ext}`;

    setProgresoActa(0);
    const fallo = await subirArchivoConProgreso(supabase, "actas", ruta, file, setProgresoActa);
    setProgresoActa(null);
    if (fallo) {
      setSubiendo(false);
      setMsg({ tipo: "error", texto: `El acta no subió (${fallo}). Vuelve a intentarlo.` });
      return;
    }

    const { error } = await supabase.rpc("fn_registrar_acta_descanso", {
      p_referencia: refActa,
      p_path: ruta,
      p_nombre: file.name,
    });
    setSubiendo(false);
    if (error) { setMsg({ tipo: "error", texto: mensajeDeError(error) }); return; }
    await cargar();
    setMsg({ tipo: "ok", texto: `Acta guardada para “${refActa}”.` });
  }

  /**
   * Abre el acta en una pestaña nueva. El archivo se pide solo al abrirlo, no
   * al cargar la pantalla.
   *
   * Antes esto abría una pestaña vacía y le escribía un `<iframe src="data:…">`
   * con el PDF entero metido en el atributo. Chrome bloquea la navegación a
   * `data:` en el nivel superior (es una defensa contra el phishing), así que
   * la pestaña se quedaba EN BLANCO: ni el papel ni un error, solo about:blank.
   *
   * Se convierte a una URL de objeto —`blob:`— que el navegador sí abre con su
   * visor de PDF de siempre. Se libera al minuto: soltarla enseguida deja la
   * pestaña recién abierta sin nada que mostrar.
   */
  async function abrirActa(referencia: string) {
    // Dos orígenes posibles: el almacén (lo nuevo) y el texto en base (lo que ya
    // estaba subido antes de la 0175). Las actas viejas no se migraron a
    // propósito — se siguen leyendo donde están, sin un script que pueda
    // quedarse a medias.
    const { data, error } = await supabase.rpc("fn_acta_descanso_ubicacion", { p_referencia: referencia });
    const fila = Array.isArray(data) ? data[0] : null;
    if (error || !fila) { setMsg({ tipo: "error", texto: error?.message ?? "Esa acta no tiene archivo." }); return; }

    if (fila.storage_path) {
      // URL firmada de vida corta: el bucket es privado.
      const { data: firma, error: eF } = await supabase.storage.from("actas").createSignedUrl(fila.storage_path, 120);
      if (eF || !firma) { setMsg({ tipo: "error", texto: `No se pudo abrir: ${eF?.message ?? "sin URL"}` }); return; }
      if (!window.open(firma.signedUrl, "_blank", "noopener,noreferrer")) {
        setMsg({ tipo: "error", texto: "El navegador bloqueó la ventana. Permite las ventanas emergentes para este sitio." });
      }
      return;
    }

    if (!fila.dataurl) { setMsg({ tipo: "error", texto: "Esa acta no tiene archivo." }); return; }
    let url: string;
    try {
      url = URL.createObjectURL(await (await fetch(fila.dataurl)).blob());
    } catch {
      setMsg({ tipo: "error", texto: "No se pudo preparar el archivo para abrirlo. Vuelve a intentarlo." });
      return;
    }
    const w = window.open(url, "_blank", "noopener,noreferrer");
    if (!w) {
      URL.revokeObjectURL(url);
      setMsg({ tipo: "error", texto: "El navegador bloqueó la ventana. Permite las ventanas emergentes para este sitio." });
      return;
    }
    setTimeout(() => URL.revokeObjectURL(url), 60_000);
  }

  function alternar(id: string) {
    setElegidas((prev) => {
      const s = new Set(prev);
      if (s.has(id)) s.delete(id); else s.add(id);
      return s;
    });
  }
  function todasVisibles() {
    const ids = visibles.map((p) => p.id);
    const faltan = ids.some((id) => !elegidas.has(id));
    setElegidas((prev) => {
      const s = new Set(prev);
      // Si falta alguna por marcar, marca todas; si ya estaban todas, las desmarca.
      ids.forEach((id) => (faltan ? s.add(id) : s.delete(id)));
      return s;
    });
  }
  function cambiarPareja(i: number, campo: keyof Pareja, valor: string) {
    setParejas((prev) => prev.map((p, k) => (k === i ? { ...p, [campo]: valor } : p)));
  }

  // Guarda de a uno y va acumulando el resultado. Secuencial a propósito: si algo
  // falla quiero saber EXACTAMENTE en qué persona y en qué pareja, no un error suelto.
  async function registrarLote() {
    if (elegidas.size === 0) { setMsg({ tipo: "error", texto: "Elige al menos una persona." }); return; }
    if (parejasCompletas.length === 0) { setMsg({ tipo: "error", texto: "Agrega al menos una pareja de feriado y día libre." }); return; }
    setGuardando(true);
    setMsg(null);
    setResultados([]);

    const salida: Resultado[] = [];
    for (const personaId of elegidas) {
      for (const par of parejasCompletas) {
        const { error } = await supabase.rpc("fn_otorgar_descanso_sustitutorio", {
          p_persona_id: personaId,
          p_fecha_feriado: par.feriado,
          p_fecha_descanso: par.descanso,
          p_estado: estado,
          p_acta_ref: actaRef.trim() || null,
        });
        salida.push({
          persona: nombrePorId.get(personaId) ?? "—",
          feriado: par.feriado,
          descanso: par.descanso,
          error: error?.message ?? null,
        });
      }
    }

    setGuardando(false);
    setResultados(salida);
    const ok = salida.filter((x) => !x.error).length;
    const mal = salida.length - ok;
    await cargar();
    setMsg(
      mal === 0
        ? { tipo: "ok", texto: `${ok} registro${ok === 1 ? "" : "s"} guardado${ok === 1 ? "" : "s"} como ${estado}.` }
        : { tipo: "error", texto: `${ok} guardado${ok === 1 ? "" : "s"}, ${mal} rechazado${mal === 1 ? "" : "s"}. El detalle está abajo.` },
    );
  }

  async function quitar(id: string) {
    setGuardando(true);
    setMsg(null);
    const { error } = await supabase.rpc("fn_quitar_descanso_sustitutorio", { p_id: id });
    setGuardando(false);
    if (error) { setMsg({ tipo: "error", texto: mensajeDeError(error) }); return; }
    await cargar();
    setMsg({ tipo: "ok", texto: "Registro quitado. Ese feriado vuelve a pagar sobretasa." });
  }

  if (rol !== null && !puedeGestionar) {
    return (
      <div className="flex min-h-screen flex-col">
        <AdminNav />
        <main className="flex flex-1 items-center justify-center p-6">
          <p className="max-w-md text-center text-taupe">No tienes permiso para gestionar feriados.</p>
        </main>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <h1 className="mb-1 font-serif text-2xl">Feriados laborados</h1>
        <p className="mb-5 max-w-3xl text-sm text-taupe">
          Quien trabaja un feriado cobra <strong>triple</strong>, salvo que se le dé un{" "}
          <strong>día libre a cambio</strong>. Registrar aquí ese día libre hace dos cosas: quita la
          sobretasa de la planilla del periodo, y evita que ese día le salga como{" "}
          <strong>falta injustificada</strong> por no marcar.
        </p>

        {msg && (
          <div className={`mb-4 max-w-3xl rounded-lg px-4 py-3 text-sm ${msg.tipo === "ok" ? "bg-sand/40 text-tinta" : "bg-rojo/10 text-rojo"}`}>
            {msg.texto}
          </div>
        )}

        {/* Registrar por lotes */}
        <div className="mb-6 max-w-4xl rounded-2xl border border-sand bg-papel p-5">
          <h2 className="mb-3 text-sm font-medium">Registrar días libres a cambio</h2>

          {/* 1 · A quiénes */}
          <div className="mb-4">
            <div className="mb-2 flex flex-wrap items-center gap-3">
              <span className="text-sm">A quiénes</span>
              <select value={sedeFiltro} onChange={(e) => setSedeFiltro(e.target.value)}
                className="rounded-lg border bg-crema px-2 py-1 text-sm">
                <option value="">Todas las sedes</option>
                {sedes.map((s) => <option key={s.id} value={s.id}>{s.nombre}</option>)}
              </select>
              <button type="button" onClick={todasVisibles}
                className="rounded border border-sand px-2 py-1 text-xs text-taupe hover:text-tinta">
                Marcar / desmarcar visibles
              </button>
              {elegidas.size > 0 && (
                <span className="text-xs text-taupe">{elegidas.size} elegida{elegidas.size === 1 ? "" : "s"}</span>
              )}
            </div>
            <div className="grid max-h-52 gap-1 overflow-y-auto rounded-lg border border-sand bg-crema p-2 sm:grid-cols-2 lg:grid-cols-3">
              {visibles.map((p) => (
                <label key={p.id} className="flex items-center gap-2 rounded px-2 py-1 text-sm hover:bg-sand/40">
                  <input type="checkbox" checked={elegidas.has(p.id)} onChange={() => alternar(p.id)} />
                  {p.nombres} {p.apellidos}
                </label>
              ))}
              {visibles.length === 0 && <p className="px-2 py-1 text-sm text-taupe">Sin personas en esa sede.</p>}
            </div>
          </div>

          {/* 2 · Qué días — parejas explícitas */}
          <div className="mb-4">
            <p className="mb-2 text-sm">Qué días</p>
            <div className="grid gap-2">
              {parejas.map((par, i) => (
                <div key={i} className="flex flex-wrap items-center gap-2">
                  <select value={par.feriado} onChange={(e) => cambiarPareja(i, "feriado", e.target.value)}
                    className="min-w-56 rounded-lg border bg-crema px-3 py-2 text-sm">
                    <option value="">Feriado trabajado…</option>
                    {feriados.map((f) => (
                      <option key={f.fecha} value={f.fecha}>{fechaCorta(f.fecha)} — {f.nombre}</option>
                    ))}
                  </select>
                  <span className="text-taupe">→</span>
                  <input type="date" value={par.descanso} onChange={(e) => cambiarPareja(i, "descanso", e.target.value)}
                    className="rounded-lg border px-3 py-2 text-sm" />
                  <span className="min-w-20 text-xs capitalize text-taupe">
                    {par.descanso ? diaSemana(par.descanso) : ""}
                  </span>
                  {parejas.length > 1 && (
                    <button type="button" onClick={() => setParejas((prev) => prev.filter((_, k) => k !== i))}
                      className="rounded border border-rojo/30 px-2 py-1 text-xs text-rojo hover:bg-rojo/10">
                      Quitar
                    </button>
                  )}
                </div>
              ))}
            </div>
            <button type="button" onClick={() => setParejas((prev) => [...prev, { feriado: "", descanso: "" }])}
              className="mt-2 rounded border border-sand px-2 py-1 text-xs text-taupe hover:text-tinta">
              + Agregar otro día
            </button>
            <p className="mt-1 text-xs text-taupe">
              Cada feriado se compensa con <strong>un</strong> día libre. Por eso se declaran de a pares:
              así ves qué compensa qué, en vez de que el sistema lo adivine.
            </p>
          </div>

          {/* 3 · Estado y acta */}
          <div className="flex flex-wrap items-end gap-3">
            <label className="flex flex-col gap-1 text-sm">
              Estado
              <select value={estado} onChange={(e) => setEstado(e.target.value)}
                className="rounded-lg border bg-crema px-3 py-2">
                {ESTADOS.map((e) => <option key={e} value={e}>{e}</option>)}
              </select>
            </label>
            <label className="flex min-w-72 flex-1 flex-col gap-1 text-sm">
              Acta firmada {estado === "OTORGADO" && <span className="text-rojo">· obligatoria para OTORGADO</span>}
              <input value={actaRef} onChange={(e) => setActaRef(e.target.value)}
                className="rounded-lg border px-3 py-2" placeholder="ej. Acta 2026-07-28 Taller LIM" />
            </label>
          </div>

          <p className="mt-3 max-w-2xl text-xs text-taupe">
            {estado === "PENDIENTE" && "Acuerdo tomado, todavía sin confirmar. La planilla sigue pagando la sobretasa, pero el día libre ya NO cuenta como falta."}
            {estado === "OTORGADO" && "El descanso se dio y está respaldado. Quita la sobretasa de la planilla. Requiere acta firmada y que el feriado ya tenga horas marcadas."}
            {estado === "NO_OTORGADO" && "El descanso no se dio. La planilla vuelve a pagar la sobretasa y el día deja de estar justificado."}
          </p>

          {/* Cuántos registros van a salir — antes de crearlos. */}
          <div className="mt-4 flex flex-wrap items-center gap-3">
            <button onClick={registrarLote} disabled={guardando || totalRegistros === 0}
              className="rounded-lg bg-tinta px-5 py-2 text-sm font-medium text-crema disabled:opacity-50">
              {guardando ? "Guardando…" : "Registrar"}
            </button>
            <span className="text-sm text-taupe">
              {totalRegistros === 0
                ? "Elige personas y al menos una pareja de días."
                : `Se van a crear ${totalRegistros} registro${totalRegistros === 1 ? "" : "s"} · ${elegidas.size} persona${elegidas.size === 1 ? "" : "s"} × ${parejasCompletas.length} día${parejasCompletas.length === 1 ? "" : "s"}`}
            </span>
          </div>

          {/* Detalle del lote: qué entró y qué no, y por qué. */}
          {resultados.length > 0 && (
            <div className="mt-4 overflow-hidden rounded-lg border border-sand">
              <p className="border-b bg-sand/50 px-3 py-1.5 text-xs font-medium">Detalle del último envío</p>
              <ul className="divide-y text-xs">
                {resultados.map((r, i) => (
                  <li key={i} className="px-3 py-1.5">
                    <span className={r.error ? "text-rojo" : "text-taupe"}>
                      {r.error ? "✕" : "✓"} {r.persona} · {fechaCorta(r.feriado)} → {fechaCorta(r.descanso)}
                    </span>
                    {r.error && <div className="mt-0.5 text-rojo">{r.error}</div>}
                  </li>
                ))}
              </ul>
            </div>
          )}
        </div>

        {/* Actas firmadas */}
        <div className="mb-6 max-w-4xl rounded-2xl border border-sand bg-papel p-5">
          <h2 className="mb-1 text-sm font-medium">Actas firmadas</h2>
          <p className="mb-3 max-w-2xl text-xs text-taupe">
            El acuerdo se registra arriba; aquí se guarda el <strong>papel firmado</strong> que lo
            respalda. Un acta cubre a todas las personas de ese acuerdo — se sube una sola vez.
            PDF o foto, hasta 50 MB.
          </p>

          <div className="flex flex-wrap items-end gap-3">
            <label className="flex flex-col gap-1 text-sm">
              ¿De qué acuerdo?
              <select value={refActa} onChange={(e) => setRefActa(e.target.value)}
                className="min-w-64 rounded-lg border bg-crema px-3 py-2">
                <option value="">Elegir…</option>
                {referencias.map((ref) => (
                  <option key={ref} value={ref}>
                    {ref}{actaPorRef.get(ref)?.tiene_archivo ? " — ya tiene acta" : ""}
                  </option>
                ))}
              </select>
            </label>
            <label className="flex flex-col gap-1 text-sm">
              Archivo
              {/* HEIC/HEIF entran porque es lo que sale de la cámara de un
                  iPhone: sin ellos las fotos salían en gris en el diálogo y no
                  se podía ni elegirlas (mig. 0170). */}
              <input type="file" accept="application/pdf,image/png,image/jpeg,image/webp,image/heic,image/heif"
                disabled={!refActa || subiendo}
                onChange={(e) => { const f = e.target.files?.[0]; if (f) void subirActa(f); e.target.value = ""; }}
                className="text-sm file:mr-3 file:rounded-lg file:border file:border-sand file:bg-crema file:px-3 file:py-1.5 file:text-sm disabled:opacity-50" />
            </label>
            {/* Con 3 MB una espera muda pasaba desapercibida. Con 50 MB por la
                conexión de una tienda son minutos, y sin avance visible se lee
                como que la pantalla se colgó. */}
            {subiendo && (
              <span className="flex items-center gap-2 pb-2 text-sm text-taupe">
                {progresoActa !== null && (
                  <span className="h-1.5 w-24 overflow-hidden rounded-full bg-sand">
                    <span className="block h-full bg-tinta transition-[width] duration-200"
                      style={{ width: `${progresoActa}%` }}
                      role="progressbar" aria-valuenow={progresoActa} aria-valuemin={0} aria-valuemax={100}
                      aria-label="Subiendo el acta" />
                  </span>
                )}
                {progresoActa !== null ? `Subiendo — ${progresoActa}%` : "Guardando…"}
              </span>
            )}
          </div>

          {referencias.length === 0 && (
            <p className="mt-3 text-xs text-taupe">
              Todavía no hay acuerdos registrados. Registra uno arriba y su referencia aparecerá acá.
            </p>
          )}

          {actas.length > 0 && (
            <ul className="mt-4 divide-y overflow-hidden rounded-lg border border-sand text-sm">
              {actas.map((a) => (
                <li key={a.referencia} className="flex flex-wrap items-baseline justify-between gap-2 px-3 py-2">
                  <span>
                    <strong>{a.referencia}</strong>{" "}
                    <span className="text-xs text-taupe">
                      · {a.registros} registro{a.registros === 1 ? "" : "s"}
                      {a.archivo_nombre && <> · {a.archivo_nombre}</>}
                      {a.peso_kb > 0 && <> · {a.peso_kb} KB</>}
                    </span>
                  </span>
                  {a.tiene_archivo ? (
                    <button onClick={() => abrirActa(a.referencia)}
                      className="rounded border border-sand px-2 py-0.5 text-xs text-taupe hover:text-tinta">
                      Ver acta
                    </button>
                  ) : (
                    <span className="text-xs text-rojo">sin archivo</span>
                  )}
                </li>
              ))}
            </ul>
          )}

          {/* Los acuerdos que todavía no tienen su papel. Es la lista de lo que falta. */}
          {referencias.filter((r) => !actaPorRef.get(r)?.tiene_archivo).length > 0 && (
            <p className="mt-3 text-xs text-taupe">
              Sin acta subida:{" "}
              <strong className="text-tinta">
                {referencias.filter((r) => !actaPorRef.get(r)?.tiene_archivo).join(" · ")}
              </strong>
            </p>
          )}
        </div>

        {/* Quién trabajó feriados en el rango */}
        <div className="max-w-5xl overflow-hidden rounded-2xl border border-sand bg-papel">
          <div className="border-b bg-sand/50 px-4 py-2">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <h2 className="text-sm font-medium">Quién trabajó feriados</h2>
              <div className="flex items-center gap-2 text-xs">
                <input type="date" value={desde} onChange={(e) => setDesde(e.target.value)}
                  className="rounded border px-2 py-1" />
                <span className="text-taupe">→</span>
                <input type="date" value={hasta} onChange={(e) => setHasta(e.target.value)}
                  className="rounded border px-2 py-1" />
              </div>
            </div>
            {sobretasaSinResolver > 0 && (
              <p className="mt-1 text-xs text-taupe">
                Sobretasa que se pagaría hoy por los feriados sin compensación otorgada:{" "}
                <strong className="text-tinta">{soles(sobretasaSinResolver)}</strong>
              </p>
            )}
          </div>
          {cargando ? (
            <Cargando />
          ) : laborados.length === 0 ? (
            <p className="px-4 py-6 text-sm text-taupe">Nadie marcó horas en un feriado de este rango.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full min-w-[720px] text-sm">
                <thead className="bg-sand/70 text-left text-taupe">
                  <tr>
                    <th className="px-4 py-2 font-normal">Persona</th>
                    <th className="px-4 py-2 font-normal">Feriado</th>
                    <th className="px-4 py-2 text-right font-normal">Horas</th>
                    <th className="px-4 py-2 text-right font-normal">Sobretasa</th>
                    <th className="px-4 py-2 font-normal">Compensación</th>
                  </tr>
                </thead>
                <tbody>
                  {laborados.map((l) => (
                    <tr key={`${l.persona_id}-${l.fecha_feriado}`} className="border-t align-top">
                      <td className="px-4 py-2">
                        {l.nombre}
                        <div className="text-xs text-taupe">{l.sede}</div>
                      </td>
                      <td className="px-4 py-2">
                        {fechaCorta(l.fecha_feriado)}
                        <div className="text-xs text-taupe">{l.feriado_nombre}</div>
                      </td>
                      <td className="px-4 py-2 text-right tabular-nums">{l.horas}</td>
                      <td className={`px-4 py-2 text-right tabular-nums ${l.estado === "OTORGADO" ? "text-taupe line-through" : ""}`}>
                        {l.sobretasa === null ? <span className="text-taupe/60">sin salario</span> : soles(l.sobretasa)}
                      </td>
                      <td className="px-4 py-2">
                        {l.estado === null ? (
                          <span className="text-taupe">— paga sobretasa</span>
                        ) : (
                          <>
                            <span className={l.estado === "OTORGADO" ? "font-medium text-tinta" : "text-taupe"}>
                              {l.estado}
                            </span>
                            {l.fecha_descanso && (
                              <div className="text-xs text-taupe">libre el {fechaCorta(l.fecha_descanso)}</div>
                            )}
                          </>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>

        {/* Registros existentes — incluye los de feriados futuros, que no salen arriba */}
        <div className="mt-6 max-w-4xl overflow-hidden rounded-2xl border border-sand bg-papel">
          <h2 className="border-b bg-sand/50 px-4 py-2 text-sm font-medium">
            Descansos registrados {registros.length > 0 && <span className="font-normal text-taupe">· {registros.length}</span>}
          </h2>
          {registros.length === 0 ? (
            <SinDatos texto="Todavía no hay descansos sustitutorios registrados." pista="Cuando alguien trabaja un feriado y se le da otro día libre a cambio, se anota acá para que quede constancia con su acta firmada." />
          ) : (
            <ul className="divide-y">
              {registros.map((r) => (
                <li key={r.id} className="px-4 py-3 text-sm">
                  <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                    <span>
                      <strong>{nombrePorId.get(r.persona_id) ?? "—"}</strong>{" "}
                      <span className="text-taupe">
                        · trabajó el {fechaCorta(r.fecha_feriado)} · libre el {fechaCorta(r.fecha_descanso_sustitutorio)}
                      </span>{" "}
                      <span className={r.estado === "OTORGADO" ? "font-medium" : "text-taupe"}>· {r.estado}</span>
                    </span>
                    <button onClick={() => quitar(r.id)} disabled={guardando}
                      className="rounded border border-rojo/30 px-2 py-0.5 text-xs text-rojo hover:bg-rojo/10 disabled:opacity-40">
                      Quitar
                    </button>
                  </div>
                  {r.acta_ref && <p className="mt-1 text-xs text-taupe">Acta: {r.acta_ref}</p>}
                  {/* EN ROJO, con la razón concreta. Este registro le quitó a esa
                      persona la sobretasa del feriado —unos cien soles— a cambio
                      de un día libre que, según lo que la base sabe hoy, no
                      ocurrió. No se corrige solo: quitarlo le DEVUELVE la
                      sobretasa, o sea que mueve plata, y eso lo decide una
                      persona con el caso delante. */}
                  {motivoPorFila.get(`${r.persona_id}|${r.fecha_feriado}`) && (
                    <p className="mt-1 rounded-lg border border-rojo/30 bg-rojo/[0.06] px-2 py-1 text-xs text-rojo">
                      Este día no compensa: {motivoPorFila.get(`${r.persona_id}|${r.fecha_feriado}`)}.
                      {r.estado === "OTORGADO" && " Mientras siga en OTORGADO, se le está descontando la sobretasa del feriado."}
                    </p>
                  )}
                </li>
              ))}
            </ul>
          )}
        </div>
      </main>
    </div>
  );
}

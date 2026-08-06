"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { AdminNav } from "../nav";
import { Cargando } from "@/components/cargando";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { instanteEntrega } from "@/lib/admin/instante-entrega";
import { TZ_LIMA, hoyLima, puedeOperarEquipo } from "@cayla-dynamic/shared";


// Fechas planas: se formatean en UTC para que no se corran un día por zona horaria.
function fechaCorta(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "short", timeZone: "UTC" })
    .format(new Date(Date.UTC(y, m - 1, d)));
}
function addDias(iso: string, n: number): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}
function selloLima(iso: string): string {
  const d = new Date(iso);
  if (isNaN(d.getTime())) return iso;
  return new Intl.DateTimeFormat("es-PE", { timeZone: TZ_LIMA, day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", hour12: true }).format(d);
}

const NIVEL_LABEL: Record<string, string> = {
  verbal: "Llamada verbal",
  amonestacion: "Amonestación escrita",
  suspension: "Suspensión sin goce",
  imputacion: "Imputación de cargos",
  despido: "Carta de despido",
};
const CAUSAL_LABEL: Record<string, string> = { tardanza: "Tardanzas", falta: "Faltas", conducta: "Conducta" };

interface TardanzaRow { persona_id: string; nombre: string; sede: string; tardanzas_mes: number; umbral: string; }
interface FaltaRow { persona_id: string; nombre: string; sede: string; consecutivas: number; en_30: number; en_180: number; nivel: string; }
interface Hecho { fecha: string; minutos?: number; }
/** Quién puede suscribir un documento concreto (fn_expediente_firmantes, mig. 0074). */
interface Firmante { persona_id: string; nombre: string; cargo: string; tiene_firma: boolean; }
interface Adjunto {
  id: string;
  documento_id: string;
  storage_path: string;
  tipo: "cargo_firmado" | "acta_negativa";
  nota: string | null;
  subido_at: string;
}

const MAX_BYTES_CARGO = 50 * 1024 * 1024;
const TIPOS_CARGO = "image/jpeg,image/png,image/heic,image/webp,application/pdf";

// Sube por PUT a una URL ya firmada, con progreso real: `upload()` del cliente
// no informa avance, y una espera muda se lee como que la pantalla se colgó.
function subirConProgreso(
  urlFirmada: string, archivo: File, alAvanzar: (pct: number) => void,
): Promise<string | null> {
  return new Promise((resolver) => {
    const xhr = new XMLHttpRequest();
    xhr.open("PUT", urlFirmada);
    xhr.setRequestHeader("x-upsert", "true");
    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable) alAvanzar(Math.round((e.loaded / e.total) * 100));
    };
    xhr.onload = () =>
      resolver(xhr.status >= 200 && xhr.status < 300 ? null : `el servidor respondió ${xhr.status}`);
    xhr.onerror = () => resolver("se cortó la conexión durante la subida");
    const cuerpo = new FormData();
    cuerpo.append("cacheControl", "3600");
    cuerpo.append("", archivo);
    xhr.send(cuerpo);
  });
}

interface Doc {
  id: string; persona_id: string; tipo_causal: string; nivel: string; estado: string;
  periodo_desde: string | null; periodo_hasta: string | null; hechos: Hecho[];
  suspension_dias: number | null; suspension_desde: string | null; suspension_hasta: string | null;
  correlativo: string | null; creado_at: string; firmado_at: string | null;
  entregado_at: string | null; medio_entrega: string | null;
}

/**
 * El formulario para archivar el papel de una entrega.
 *
 * Vive acá y no dentro de cada sección porque el mismo trámite aparece en dos
 * momentos: cuando el memo está firmado y aún no se entrega, y cuando ya se
 * entregó por otra vía y falta archivar el cargo. Estaba escrito solo en el
 * primero, así que en "Entregados" el botón abría un aviso sin selector de
 * archivo — parecía que el sistema no dejaba subirlo.
 *
 * `pideFecha` es la única diferencia real entre los dos casos: en un documento
 * ya entregado la fecha buena es la registrada y la base no la pisa.
 */
function FormularioCargo({
  negativa, pideFecha, entregadoEl, fecha, progreso, ocupado,
  alElegirArchivo, alCambiarFecha, alCambiarNota, nota, alGuardar, alCancelar,
}: {
  negativa: boolean; pideFecha: boolean; entregadoEl: string | null;
  fecha: string; nota: string; progreso: number | null; ocupado: boolean;
  alElegirArchivo: (f: File | null) => void;
  alCambiarFecha: (v: string) => void;
  alCambiarNota: (v: string) => void;
  alGuardar: () => void; alCancelar: () => void;
}) {
  return (
    <div className="mt-3 rounded-lg border border-sand bg-sand/20 p-3">
      <p className="mb-2 text-xs text-taupe">
        {negativa
          ? "Sube el acta con testigo. Queda constancia de que se ofreció entregar; el documento NO se marca entregado."
          : pideFecha
            ? "Al subir el cargo, el documento queda entregado con esta fecha. Desde ahí corren los plazos de descargo (art. 31)."
            : `Sube el cargo para archivarlo en el legajo. No cambia la entrega ya registrada${entregadoEl ? ` (${entregadoEl})` : ""}.`}
      </p>
      <div className="grid gap-2 sm:grid-cols-2">
        <label className="flex flex-col gap-1 text-xs">
          {negativa ? "Acta de la negativa" : "Cargo firmado"}
          <input type="file" accept={TIPOS_CARGO}
            onChange={(e) => alElegirArchivo(e.target.files?.[0] ?? null)}
            className="rounded border bg-crema px-2 py-1 text-xs file:mr-2 file:rounded file:border-0 file:bg-sand file:px-2 file:py-0.5 file:text-xs" />
        </label>
        {pideFecha && (
          <label className="flex flex-col gap-1 text-xs">
            Fecha de entrega
            <input type="date" value={fecha} max={hoyLima()}
              onChange={(e) => alCambiarFecha(e.target.value)}
              className="rounded border px-2 py-1 text-xs" />
          </label>
        )}
        <label className="flex flex-col gap-1 text-xs sm:col-span-2">
          Nota (opcional)
          <input value={nota} onChange={(e) => alCambiarNota(e.target.value)}
            placeholder={negativa ? "ej. presente la encargada de TRU como testigo" : "ej. recibido en la tienda"}
            className="rounded border px-2 py-1 text-xs" />
        </label>
      </div>
      {progreso !== null && (
        <div className="mt-2">
          <div className="h-1.5 w-full overflow-hidden rounded-full bg-sand">
            <div className="h-full bg-tinta transition-[width] duration-200"
              style={{ width: `${progreso}%` }}
              role="progressbar" aria-valuenow={progreso} aria-valuemin={0} aria-valuemax={100}
              aria-label="Subiendo el cargo" />
          </div>
          <span className="text-xs text-taupe">Subiendo — {progreso}%</span>
        </div>
      )}
      <div className="mt-2 flex items-center gap-2">
        <button onClick={alGuardar} disabled={ocupado}
          className="rounded-lg bg-tinta px-3 py-1 text-xs font-medium text-crema disabled:opacity-40">
          {progreso !== null ? `Subiendo… ${progreso}%` : "Guardar"}
        </button>
        <button onClick={alCancelar}
          className="rounded-lg border px-3 py-1 text-xs">Cancelar</button>
      </div>
    </div>
  );
}

export default function DisciplinaPage() {
  const router = useRouter();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const puede = puedeOperarEquipo(rol);

  const [tardanzas, setTardanzas] = useState<TardanzaRow[]>([]);
  const [faltas, setFaltas] = useState<FaltaRow[]>([]);
  const [docs, setDocs] = useState<Doc[]>([]);
  const [nombres, setNombres] = useState<Map<string, string>>(new Map());
  const [cargando, setCargando] = useState(true);
  const [resaltado, setResaltado] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState<string | null>(null);
  const [msg, setMsg] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  const [medio, setMedio] = useState<Record<string, string>>({});

  // ── El cargo firmado ────────────────────────────────────────────────────
  const [adjuntos, setAdjuntos] = useState<Map<string, Adjunto[]>>(new Map());
  const [subiendoCargo, setSubiendoCargo] = useState<{ id: string; negativa: boolean } | null>(null);
  const [archivoCargo, setArchivoCargo] = useState<File | null>(null);
  const [fechaEntrega, setFechaEntrega] = useState("");
  const [notaCargo, setNotaCargo] = useState("");
  const [progresoCargo, setProgresoCargo] = useState<number | null>(null);
  const [verCerrados, setVerCerrados] = useState(false);
  // Quién puede suscribir CADA documento. Se pregunta por documento y no una
  // vez para todos porque la respuesta depende del nivel y de la sede: una
  // encargada puede firmar una amonestación verbal o escrita de SU tienda,
  // pero no una suspensión ni la de otra sede (fn_expediente_firmantes, 0074).
  // Antes se usaba fn_firmantes_disponibles, que solo listaba admin y líder DO:
  // la delegación existía en la base pero la pantalla no la ofrecía.
  const [firmantes, setFirmantes] = useState<Record<string, Firmante[]>>({});
  const [firmanteElegido, setFirmanteElegido] = useState<Record<string, string>>({});
  const borradoresRef = useRef<HTMLDivElement>(null);

  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  const cargar = useCallback(async () => {
    setCargando(true);
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    const [{ data: t }, { data: f }, { data: d, error: eD }, { data: p }] = await Promise.all([
      supabase.rpc("fn_tardanzas_resumen", {}),
      supabase.rpc("fn_faltas_resumen", {}),
      supabase.from("expediente_disciplinario")
        .select("id, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos, suspension_dias, suspension_desde, suspension_hasta, correlativo, creado_at, firmado_at, entregado_at, medio_entrega")
        // ⇩ Entra "entregado": antes desaparecía al entregarse, así que subías el
        //   cargo y no veías que hubiera quedado. Y no había dónde consultar el
        //   papel de una entrega de hace dos meses.
        .in("estado", ["borrador", "firmado", "entregado"])
        .order("creado_at", { ascending: false }),
      supabase.from("personas").select("id, nombres, apellidos"),
    ]);
    if (eD) setMsg({ tipo: "error", texto: mensajeDeError(eD, "cargar el legajo") });
    setTardanzas(Array.isArray(t) ? (t as TardanzaRow[]) : []);
    setFaltas(Array.isArray(f) ? (f as FaltaRow[]) : []);
    const lista = Array.isArray(d) ? (d as unknown as Doc[]) : [];
    setDocs(lista);
    setNombres(new Map(((p as Array<{ id: string; nombres: string; apellidos: string }>) ?? []).map((x) => [x.id, `${x.nombres} ${x.apellidos}`])));

    // Los firmantes posibles de cada borrador. Solo para borradores: un
    // documento ya firmado no cambia de firmante. Si alguna consulta falla, esa
    // fila se queda sin desplegable y se firma con la sesión actual — el mismo
    // comportamiento de antes, nunca un error en pantalla.
    // Los cargos ya archivados, para poder consultarlos sin salir del sistema.
    // Consulta aparte y tolerante: si la tabla no fuera legible, la pantalla
    // sigue funcionando sin los adjuntos en vez de quedarse en blanco.
    const { data: adj } = await supabase
      .from("expediente_adjuntos")
      .select("id, documento_id, storage_path, tipo, nota, subido_at")
      .order("subido_at", { ascending: false });
    const porDoc = new Map<string, Adjunto[]>();
    for (const a of (adj as Adjunto[]) ?? []) {
      porDoc.set(a.documento_id, [...(porDoc.get(a.documento_id) ?? []), a]);
    }
    setAdjuntos(porDoc);

    const borradores = lista.filter((x) => x.estado === "borrador");
    const pares = await Promise.all(
      borradores.map(async (x) => {
        const { data: fs } = await supabase.rpc("fn_expediente_firmantes", { p_id: x.id });
        return [x.id, Array.isArray(fs) ? (fs as Firmante[]) : []] as const;
      }),
    );
    setFirmantes(Object.fromEntries(pares));
    setCargando(false);
  }, [supabase, router]);

  useEffect(() => { void cargar(); }, [cargar]);

  // Atajo desde la alerta del Dashboard: si el hash apunta a una persona
  // (#tard-ID o #falta-ID), baja hasta su fila en el semáforo y la resalta.
  useEffect(() => {
    if (cargando) return;
    const hash = typeof window !== "undefined" ? window.location.hash.slice(1) : "";
    if (!hash) return;
    // El aviso del Dashboard («N memos sin el cargo archivado») apunta acá. Los
    // entregados están plegados por defecto: aterrizar y no ver nada es igual a
    // no haber avisado.
    if (hash === "entregados") setVerCerrados(true);
    const el = document.getElementById(hash);
    if (!el) return;
    const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
    el.scrollIntoView({ behavior: reduce ? "auto" : "smooth", block: "center" });
    setResaltado(hash);
    const t = setTimeout(() => setResaltado(null), 2800);
    return () => clearTimeout(t);
  }, [cargando]);

  async function generar(tipo: "tardanza" | "falta", personaId: string) {
    setOcupado(personaId); setMsg(null);
    const fn = tipo === "tardanza" ? "fn_expediente_generar_tardanza" : "fn_expediente_generar_falta";
    const { error } = await supabase.rpc(fn, { p_persona_id: personaId });
    setOcupado(null);
    if (error) { setMsg({ tipo: "error", texto: mensajeDeError(error) }); return; }
    await cargar();
    setMsg({ tipo: "ok", texto: "Borrador generado. Revísalo abajo y fírmalo cuando esté listo." });
    const suave = typeof window !== "undefined" && !window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    setTimeout(() => borradoresRef.current?.scrollIntoView({ behavior: suave ? "smooth" : "auto", block: "start" }), 80);
  }

  async function firmar(id: string) {
    const elegido = firmanteElegido[id];
    const f = elegido ? (firmantes[id] ?? []).find((x) => x.persona_id === elegido) : null;
    // El cargo va en el aviso a propósito: es lo que se va a imprimir en el
    // documento, y quien firma tiene que verlo antes de que sea definitivo.
    const aviso = f
      ? `¿Firmar este documento como ${f.nombre} (${f.cargo})? Le asigna su número oficial y deja de ser un borrador. Después podrás entregarlo o, si hizo falta, anularlo.`
      : "¿Firmar este documento? Le asigna su número oficial y deja de ser un borrador. Después podrás entregarlo o, si hizo falta, anularlo.";
    if (!window.confirm(aviso)) return;
    setOcupado(id); setMsg(null);
    const { data, error } = await supabase.rpc("fn_expediente_firmar", { p_id: id, p_firmante_id: elegido ?? null });
    setOcupado(null);
    if (error) { setMsg({ tipo: "error", texto: mensajeDeError(error) }); return; }
    await cargar();
    setMsg({ tipo: "ok", texto: `Firmado — documento ${data ?? ""}. Ya puedes entregarlo.` });
  }

  async function abrirCargo(id: string, negativa: boolean) {
    setSubiendoCargo({ id, negativa });
    setArchivoCargo(null);
    setFechaEntrega(hoyLima());
    setNotaCargo("");
    setMsg(null);
  }

  async function guardarCargo() {
    if (!subiendoCargo) return;
    // La fecha solo se pide cuando esta subida es la que marca la entrega: en un
    // documento ya entregado la fecha buena es la registrada, y en un acta de
    // negativa no hay entrega que fechar.
    const doc = docs.find((x) => x.id === subiendoCargo.id) ?? null;
    const pideFecha = !subiendoCargo.negativa && doc?.estado === "firmado";
    if (!archivoCargo) {
      setMsg({ tipo: "error", texto: subiendoCargo.negativa
        ? "Falta el acta de la negativa. Sin el papel con el testigo no queda constancia de que se ofreció."
        : "Falta el cargo firmado." });
      return;
    }
    if (archivoCargo.size > MAX_BYTES_CARGO) {
      setMsg({ tipo: "error", texto: `“${archivoCargo.name}” pesa ${(archivoCargo.size / 1048576).toFixed(1)} MB y el máximo es 50 MB.` });
      return;
    }
    if (pideFecha && !fechaEntrega) {
      setMsg({ tipo: "error", texto: "Indica la fecha de entrega: desde ahí corren los plazos de descargo." });
      return;
    }

    setOcupado(subiendoCargo.id); setMsg(null);
    // El archivo va a "<id del documento>/…": es lo que valida
    // fn_expediente_puede_adjuntar, así que no hay forma de colgarlo del memo
    // equivocado.
    const ext = archivoCargo.name.split(".").pop()?.toLowerCase() ?? "bin";
    const ruta = `${subiendoCargo.id}/${subiendoCargo.negativa ? "acta" : "cargo"}-${Date.now()}.${ext}`;

    setProgresoCargo(0);
    const firma = await supabase.storage.from("expedientes").createSignedUploadUrl(ruta, { upsert: true });
    const fallo = firma.error ? firma.error.message : await subirConProgreso(firma.data.signedUrl, archivoCargo, setProgresoCargo);
    setProgresoCargo(null);
    if (fallo) {
      setOcupado(null);
      setMsg({ tipo: "error", texto: `El archivo no subió (${fallo}). Vuelve a intentarlo.` });
      return;
    }

    // La fecha de entrega solo viaja si esta subida es la que marca la entrega.
    // La función la ignoraría igual en un documento ya entregado, pero mandarla
    // la somete a validaciones que no vienen al caso y podrían rechazar el
    // archivado de un papel perfectamente válido.
    const { error } = await supabase.rpc("fn_expediente_adjuntar", {
      p_documento_id: subiendoCargo.id,
      p_path: ruta,
      p_tipo: subiendoCargo.negativa ? "acta_negativa" : "cargo_firmado",
      p_fecha_entrega: pideFecha ? instanteEntrega(fechaEntrega, doc?.firmado_at ?? null) : null,
      p_nota: notaCargo.trim() || null,
    });
    setOcupado(null);
    if (error) { setMsg({ tipo: "error", texto: mensajeDeError(error) }); return; }

    setSubiendoCargo(null);
    await cargar();
    setMsg({ tipo: "ok", texto: subiendoCargo.negativa
      ? "Acta de negativa archivada contra el documento."
      : pideFecha
        ? "Cargo archivado y documento marcado como entregado. Ya no hace falta guardarlo en ninguna carpeta."
        : "Cargo archivado contra el documento. La fecha de entrega registrada no cambió." });
  }

  async function verAdjunto(path: string) {
    // URL firmada de vida corta: el bucket es privado y estos papeles son los
    // más delicados del sistema.
    const { data, error } = await supabase.storage.from("expedientes").createSignedUrl(path, 60);
    if (error || !data) { setMsg({ tipo: "error", texto: `No se pudo abrir: ${error?.message ?? "sin URL"}` }); return; }
    window.open(data.signedUrl, "_blank", "noopener,noreferrer");
  }

  async function entregar(id: string) {
    const m = medio[id] ?? "fisico";
    setOcupado(id); setMsg(null);
    const { error } = await supabase.rpc("fn_expediente_entregar", { p_id: id, p_medio: m });
    setOcupado(null);
    if (error) { setMsg({ tipo: "error", texto: mensajeDeError(error) }); return; }
    await cargar();
    setMsg({ tipo: "ok", texto: "Marcado como entregado. Guarda el cargo firmado en el legajo." });
  }

  async function guardarDias(d: Doc, dias: number) {
    if (dias < 1) return;
    const desde = d.suspension_desde ?? addDias(hoyLima(), 1);
    setOcupado(d.id); setMsg(null);
    const { error } = await supabase.rpc("fn_expediente_editar_borrador", {
      p_id: d.id, p_suspension_dias: dias, p_suspension_desde: desde, p_suspension_hasta: addDias(desde, dias - 1),
    });
    setOcupado(null);
    if (error) { setMsg({ tipo: "error", texto: mensajeDeError(error) }); return; }
    await cargar();
  }

  // Volver un memo firmado a borrador para cambiar quién lo suscribe (mig. 0131).
  // Solo mientras no se haya entregado: una vez entregado se anula, no se reabre.
  async function reabrirParaCambiarFirmante(id: string) {
    if (!window.confirm(
      "¿Volver este memo a borrador para cambiar quién lo firma?\n\n" +
      "Pierde su número oficial actual; al volver a firmarlo se le asigna uno nuevo. " +
      "Solo se puede mientras no se haya entregado.",
    )) return;
    setOcupado(id); setMsg(null);
    const { error } = await supabase.rpc("fn_expediente_reabrir", { p_id: id });
    setOcupado(null);
    if (error) { setMsg({ tipo: "error", texto: mensajeDeError(error) }); return; }
    await cargar();
    setMsg({ tipo: "ok", texto: "Vuelto a borrador. Arriba, en Borradores, elige el firmante correcto y fírmalo de nuevo." });
  }

  async function anular(id: string) {
    const motivo = window.prompt("Motivo de la anulación (queda registrado en el documento):");
    if (!motivo || motivo.trim().length < 3) return;
    setOcupado(id); setMsg(null);
    const { error } = await supabase.rpc("fn_expediente_anular", { p_id: id, p_motivo: motivo.trim() });
    setOcupado(null);
    if (error) { setMsg({ tipo: "error", texto: mensajeDeError(error) }); return; }
    await cargar();
    setMsg({ tipo: "ok", texto: "Documento anulado." });
  }

  const borradores = docs.filter((d) => d.estado === "borrador");
  const entregados = docs.filter((d) => d.estado === "entregado");
  const firmados = docs.filter((d) => d.estado === "firmado");

  if (rol !== null && !puede) {
    return (
      <div className="flex min-h-screen flex-col">
        <AdminNav />
        <main className="flex flex-1 items-center justify-center p-6">
          <p className="max-w-md text-center text-taupe">No tienes permiso para el módulo disciplinario.</p>
        </main>
      </div>
    );
  }

  function fechasDe(h: Hecho[]): string {
    if (!Array.isArray(h) || h.length === 0) return "—";
    return h.map((x) => fechaCorta(x.fecha) + (x.minutos != null ? ` (${x.minutos}′)` : "")).join(" · ");
  }

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <h1 className="mb-1 font-serif text-2xl">Disciplina</h1>
        <p className="mb-5 max-w-2xl text-sm text-taupe">
          El sistema detecta quién cruzó un umbral y <strong>arma el borrador del memo</strong> con las pruebas puestas;
          tú lo revisas y firmas. Tardanza y falta van <strong>separadas</strong>: pesan distinto en la escala.
        </p>

        {msg && (
          <div className={`mb-4 max-w-2xl rounded-lg px-4 py-3 text-sm ${msg.tipo === "ok" ? "bg-sand/40 text-tinta" : "bg-rojo/10 text-rojo"}`}>
            {msg.texto}
          </div>
        )}

        {/* Semáforo de tardanzas */}
        <div className="mb-6 max-w-3xl overflow-hidden rounded-2xl border border-sand bg-papel">
          <div className="border-b bg-sand/50 px-4 py-2">
            <h2 className="text-sm font-medium">Tardanzas — {new Intl.DateTimeFormat("es-PE", { month: "long", timeZone: TZ_LIMA }).format(new Date())}{!cargando && tardanzas.length > 0 && <span className="font-normal text-taupe"> · {tardanzas.length}</span>}</h2>
            <p className="mt-0.5 text-xs text-taupe">Umbral RIT art. 7: 3 en el mes corresponde amonestación.</p>
          </div>
          {cargando ? (
            <Cargando />
          ) : tardanzas.length === 0 ? (
            <p className="px-4 py-6 text-sm text-taupe">Nadie con tardanzas relevantes este mes.</p>
          ) : (
            <ul className="divide-y">
              {tardanzas.map((t) => (
                <li key={t.persona_id} id={`tard-${t.persona_id}`} className={`flex flex-wrap items-center justify-between gap-3 scroll-mt-24 px-4 py-3 text-sm transition-colors ${resaltado === `tard-${t.persona_id}` ? "bg-rojo/10" : ""}`}>
                  <span>
                    <strong>{t.nombre}</strong> <span className="text-taupe">· {t.sede}</span>
                    <span className={`ml-2 rounded-full px-2 py-0.5 text-xs ${t.umbral === "amonestacion" ? "bg-rojo/10 text-rojo" : "bg-amber-100 text-amber-800"}`}>
                      {t.tardanzas_mes} {t.umbral === "amonestacion" ? "· amonestación" : "· aviso"}
                    </span>
                  </span>
                  <button onClick={() => generar("tardanza", t.persona_id)} disabled={ocupado === t.persona_id}
                    className="rounded-lg border border-tinta/30 px-3 py-1 text-xs text-tinta hover:bg-sand/40 disabled:opacity-40">
                    {ocupado === t.persona_id ? "Generando…" : "Generar borrador"}
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>

        {/* Semáforo de faltas */}
        <div className="mb-6 max-w-3xl overflow-hidden rounded-2xl border border-sand bg-papel">
          <div className="border-b bg-sand/50 px-4 py-2">
            <h2 className="text-sm font-medium">Faltas — últimos 180 días{!cargando && faltas.length > 0 && <span className="font-normal text-taupe"> · {faltas.length}</span>}</h2>
            <p className="mt-0.5 text-xs text-taupe">Umbrales art. 25-h: 4 consecutivas · 6 en 30 días · 16 en 180 días.</p>
          </div>
          {cargando ? (
            <Cargando />
          ) : faltas.length === 0 ? (
            <p className="px-4 py-6 text-sm text-taupe">Nadie en umbral de faltas. Buena señal.</p>
          ) : (
            <ul className="divide-y">
              {faltas.map((f) => (
                <li key={f.persona_id} id={`falta-${f.persona_id}`} className={`flex flex-wrap items-center justify-between gap-3 scroll-mt-24 px-4 py-3 text-sm transition-colors ${resaltado === `falta-${f.persona_id}` ? "bg-rojo/10" : ""}`}>
                  <span>
                    <strong>{f.nombre}</strong> <span className="text-taupe">· {f.sede}</span>
                    <span className={`ml-2 rounded-full px-2 py-0.5 text-xs ${f.nivel === "rojo" ? "bg-rojo/10 text-rojo" : "bg-amber-100 text-amber-800"}`}>
                      {f.consecutivas} consec · {f.en_30} en 30d · {f.en_180} en 180d
                    </span>
                  </span>
                  <button onClick={() => generar("falta", f.persona_id)} disabled={ocupado === f.persona_id}
                    className="rounded-lg border border-tinta/30 px-3 py-1 text-xs text-tinta hover:bg-sand/40 disabled:opacity-40">
                    {ocupado === f.persona_id ? "Generando…" : "Generar borrador"}
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>

        {/* Borradores pendientes de firma */}
        <div ref={borradoresRef} className="mb-6 max-w-3xl scroll-mt-4 overflow-hidden rounded-2xl border border-sand bg-papel">
          <h2 className="border-b bg-sand/50 px-4 py-2 text-sm font-medium">
            Borradores pendientes {borradores.length > 0 && <span className="font-normal text-taupe">· {borradores.length}</span>}
          </h2>
          {borradores.length === 0 ? (
            <p className="px-4 py-6 text-sm text-taupe">No hay borradores por firmar.</p>
          ) : (
            <ul className="divide-y">
              {borradores.map((d) => (
                <li key={d.id} className="px-4 py-3 text-sm">
                  <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                    <span><strong>{nombres.get(d.persona_id) ?? "—"}</strong> <span className="text-taupe">· {CAUSAL_LABEL[d.tipo_causal]} · {NIVEL_LABEL[d.nivel]}</span></span>
                    <div className="flex items-center gap-2">
                      {(firmantes[d.id] ?? []).length > 0 && (
                        <select
                          value={firmanteElegido[d.id]
                            ?? (firmantes[d.id] ?? []).find((f) => f.persona_id === yo?.id)?.persona_id
                            ?? (firmantes[d.id] ?? [])[0]?.persona_id
                            ?? ""}
                          onChange={(e) => setFirmanteElegido((m) => ({ ...m, [d.id]: e.target.value }))}
                          className="rounded-lg border border-sand bg-papel px-2 py-1 text-xs text-tinta"
                          title="Quién firma este documento">
                          {(firmantes[d.id] ?? []).map((f) => (
                            <option key={f.persona_id} value={f.persona_id}>
                              {f.nombre} · {f.cargo}{f.tiene_firma ? "" : " (sin firma escaneada)"}
                            </option>
                          ))}
                        </select>
                      )}
                      <button onClick={() => router.push(`/admin/disciplina/memo/${d.id}`)}
                        className="rounded-lg border border-tinta/30 px-3 py-1 text-xs text-tinta hover:bg-sand/40">Ver memo</button>
                      <button onClick={() => firmar(d.id)} disabled={ocupado === d.id}
                        className="rounded-lg bg-tinta px-3 py-1 text-xs font-medium text-crema disabled:opacity-40">Firmar</button>
                      <button onClick={() => anular(d.id)} disabled={ocupado === d.id}
                        className="rounded border border-rojo/30 px-2 py-0.5 text-xs text-rojo hover:bg-rojo/10 disabled:opacity-40">Anular</button>
                    </div>
                  </div>
                  <p className="mt-1 text-xs text-taupe">Hechos: {fechasDe(d.hechos)}</p>
                  {d.nivel === "suspension" && (
                    <label className="mt-1 flex items-center gap-2 text-xs text-taupe">
                      Días de suspensión:
                      <input type="number" min={1} max={15} defaultValue={d.suspension_dias ?? 1}
                        onBlur={(e) => guardarDias(d, Number(e.target.value))}
                        className="w-16 rounded border px-2 py-1" />
                      {d.suspension_desde && <span>del {fechaCorta(d.suspension_desde)}{d.suspension_hasta ? ` al ${fechaCorta(d.suspension_hasta)}` : ""}</span>}
                    </label>
                  )}
                </li>
              ))}
            </ul>
          )}
        </div>

        {/* Firmados — pendientes de entrega */}
        {firmados.length > 0 && (
          <div className="max-w-3xl overflow-hidden rounded-2xl border border-sand bg-papel">
            <h2 className="border-b bg-sand/50 px-4 py-2 text-sm font-medium">Firmados — por entregar · {firmados.length}</h2>
            <ul className="divide-y">
              {firmados.map((d) => (
                <li key={d.id} className="px-4 py-3 text-sm">
                  <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                    <span>
                      <strong>{nombres.get(d.persona_id) ?? "—"}</strong>{" "}
                      <span className="text-taupe">· {CAUSAL_LABEL[d.tipo_causal]} · {NIVEL_LABEL[d.nivel]} · {d.correlativo}</span>
                    </span>
                    <div className="flex items-center gap-2">
                      <button onClick={() => router.push(`/admin/disciplina/memo/${d.id}`)}
                        className="rounded-lg border border-tinta/30 px-3 py-1 text-xs text-tinta hover:bg-sand/40">Ver memo</button>
                      {/* El camino que deja evidencia es el fácil. Marcar
                          entregado sin papel sigue siendo posible —una entrega
                          por correo certificado es válida y su cargo llega
                          días después— pero deja de ser el atajo. */}
                      <button onClick={() => void abrirCargo(d.id, false)} disabled={ocupado === d.id}
                        className="rounded-lg bg-tinta px-3 py-1 text-xs font-medium text-crema disabled:opacity-40">
                        Subir cargo firmado
                      </button>
                      <button onClick={() => void abrirCargo(d.id, true)} disabled={ocupado === d.id}
                        className="text-xs text-taupe underline disabled:opacity-40">se negó a firmar</button>
                      <details className="text-xs text-taupe">
                        <summary className="cursor-pointer">entregar sin papel</summary>
                        <div className="mt-2 flex items-center gap-2">
                          <select value={medio[d.id] ?? "fisico"} onChange={(e) => setMedio((m) => ({ ...m, [d.id]: e.target.value }))}
                            className="rounded border bg-crema px-2 py-1 text-xs">
                            <option value="fisico">Físico</option>
                            <option value="correo">Correo</option>
                            <option value="notarial">Notarial</option>
                          </select>
                          <button onClick={() => entregar(d.id)} disabled={ocupado === d.id}
                            className="rounded-lg border border-tinta/30 px-3 py-1 text-xs text-tinta hover:bg-sand/40 disabled:opacity-40">Marcar entregado</button>
                        </div>
                        <p className="mt-1 max-w-xs">
                          El cargo se puede subir después: no pisa la fecha de entrega que quede acá.
                        </p>
                      </details>
                      <button onClick={() => reabrirParaCambiarFirmante(d.id)} disabled={ocupado === d.id}
                        className="rounded-lg border border-taupe/30 px-3 py-1 text-xs text-taupe hover:bg-sand/40 disabled:opacity-40">Cambiar firmante</button>
                    </div>
                  </div>
                  {/* La firma, no la creación del borrador: de la firma cuelgan
                      los plazos, y entre una y otra pueden pasar días. */}
                  <p className="mt-1 text-xs text-taupe">Firmado {selloLima(d.firmado_at ?? d.creado_at)}</p>

                  {subiendoCargo?.id === d.id && (
                    <FormularioCargo
                      negativa={subiendoCargo.negativa}
                      pideFecha={!subiendoCargo.negativa}
                      entregadoEl={null}
                      fecha={fechaEntrega} nota={notaCargo}
                      progreso={progresoCargo} ocupado={ocupado === d.id}
                      alElegirArchivo={setArchivoCargo}
                      alCambiarFecha={setFechaEntrega}
                      alCambiarNota={setNotaCargo}
                      alGuardar={() => void guardarCargo()}
                      alCancelar={() => setSubiendoCargo(null)}
                    />
                  )}
                </li>
              ))}
            </ul>
          </div>
        )}

        {/* ── Entregados ──────────────────────────────────────────────────
            Antes desaparecían al entregarse: subías el cargo y no veías que
            hubiera quedado, y para consultar el papel de una entrega de hace
            dos meses no había ningún sitio. Plegado por defecto para que la
            pantalla siga enfocada en lo que falta hacer. */}
        {entregados.length > 0 && (
          <div id="entregados" className="mt-4 max-w-3xl scroll-mt-4 overflow-hidden rounded-2xl border border-sand bg-papel">
            <button onClick={() => setVerCerrados((v) => !v)}
              className="flex w-full items-center justify-between border-b bg-sand/50 px-4 py-2 text-left text-sm font-medium">
              <span>Entregados · {entregados.length}</span>
              <span className="text-xs font-normal text-taupe">
                {entregados.filter((d) => (adjuntos.get(d.id) ?? []).length === 0).length > 0 && (
                  <span className="text-rojo">
                    {entregados.filter((d) => (adjuntos.get(d.id) ?? []).length === 0).length} sin cargo archivado ·{" "}
                  </span>
                )}
                {verCerrados ? "ocultar" : "ver"}
              </span>
            </button>
            {verCerrados && (
              <ul className="divide-y">
                {entregados.map((d) => {
                  const papeles = adjuntos.get(d.id) ?? [];
                  return (
                    <li key={d.id} className="px-4 py-3 text-sm">
                      <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                        <span>
                          <strong>{nombres.get(d.persona_id) ?? "—"}</strong>{" "}
                          <span className="text-taupe">· {CAUSAL_LABEL[d.tipo_causal]} · {NIVEL_LABEL[d.nivel]} · {d.correlativo}</span>
                        </span>
                        <div className="flex flex-wrap items-center gap-2">
                          <button onClick={() => router.push(`/admin/disciplina/memo/${d.id}`)}
                            className="rounded-lg border border-tinta/30 px-3 py-1 text-xs text-tinta hover:bg-sand/40">Ver memo</button>
                          {papeles.map((a) => (
                            <button key={a.id} onClick={() => void verAdjunto(a.storage_path)}
                              className="text-xs font-medium underline">
                              {a.tipo === "acta_negativa" ? "Ver acta de negativa" : "Ver cargo"}
                            </button>
                          ))}
                          {papeles.length === 0 && (
                            <button onClick={() => void abrirCargo(d.id, false)}
                              className="rounded-lg border border-rojo/40 px-3 py-1 text-xs text-rojo">Subir cargo</button>
                          )}
                        </div>
                      </div>
                      <p className="mt-1 text-xs text-taupe">
                        Entregado {d.entregado_at ? selloLima(d.entregado_at) : "—"}
                        {d.medio_entrega && ` · ${d.medio_entrega}`}
                        {papeles.length === 0 && (
                          <span className="text-rojo"> · sin el papel archivado</span>
                        )}
                      </p>
                      {subiendoCargo?.id === d.id && (
                        <FormularioCargo
                          negativa={subiendoCargo.negativa}
                          pideFecha={false}
                          entregadoEl={d.entregado_at ? selloLima(d.entregado_at) : null}
                          fecha={fechaEntrega} nota={notaCargo}
                          progreso={progresoCargo} ocupado={ocupado === d.id}
                          alElegirArchivo={setArchivoCargo}
                          alCambiarFecha={setFechaEntrega}
                          alCambiarNota={setNotaCargo}
                          alGuardar={() => void guardarCargo()}
                          alCancelar={() => setSubiendoCargo(null)}
                        />
                      )}
                    </li>
                  );
                })}
              </ul>
            )}
          </div>
        )}
      </main>
    </div>
  );
}

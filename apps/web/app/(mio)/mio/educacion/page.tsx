"use client";

import { Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import {
  ARCHIVOS_POR_ENTREGA, ESTADO_CONSTANCIA, ESTADO_ENTREGA, FRECUENCIA_PAGO_LABELS, MOTIVO_RECHAZO_LABELS,
  TIPOS_CONSTANCIA, TIPO_CONSTANCIA_LABELS, TZ_LIMA, hoyLima, problemaDeArchivo, sugerirProximaFecha,
  type EstadoConstancia, type EstadoEntrega, type FrecuenciaPago, type MotivoRechazo, type TipoConstancia,
} from "@cayla-dynamic/shared";
import { Cargando } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { Modal } from "@/components/ui/modal";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { abrirArchivoFirmado } from "@/lib/abrir-archivo-firmado";
import {
  BUCKET_COMPROBANTES, elegido, fechaCorta, subirArchivosDeEntrega, type ArchivoElegido,
} from "@/lib/educacion";

/**
 * Tu apoyo educativo y sus constancias (0450).
 *
 * QUÉ PROMETE. Quien tiene una asignación por educación ve su beneficio, sube
 * desde el celular la constancia de cada pago a su institución —fotos o PDF,
 * varias páginas en el mismo envío— y sigue su revisión: pendiente, aprobada o
 * rechazada con el motivo. Mientras está pendiente la puede retirar o
 * reemplazar; lo revisado queda en su historial.
 *
 * LO QUE NO HACE, Y HAY QUE DECIRLO EN PANTALLA. Aprobar o rechazar una
 * constancia no cambia lo que cobra (decisión «solo alerta», 2026-09-15). Si la
 * pantalla no lo dijera, un rechazo se leería como «me quitaron la plata».
 *
 * EL ESTADO NO SE CALCULA ACÁ. Lo contesta `fn_educacion_situacion`, la misma
 * que lee el panel de DO y la Bandeja. Y se filtra por `persona_id` de forma
 * EXPLÍCITA: si quien abre /mio es de DO, esa función le devuelve a todo el
 * equipo (ver el mismo freno en lib/bandeja-mia.ts).
 */

interface Situacion {
  familia_id: string;
  asignacion_id: string;
  persona_id: string;
  institucion: string;
  beneficiario: string;
  beneficiario_nombre: string | null;
  monto: number;
  vigente_desde: string;
  vigente_hasta: string;
  vigencia: "futura" | "vigente" | "por_terminar" | "terminada";
  frecuencia_pago: FrecuenciaPago | null;
  proxima_fecha_pago: string | null;
  estado_constancia: EstadoConstancia;
  fecha_pago_constancia: string | null;
  plazo: string | null;
  dias_para_plazo: number | null;
  entrega_id: string | null;
  entrega_estado: EstadoEntrega | null;
  entrega_enviada_at: string | null;
  entrega_archivos: number | null;
  motivo_categoria: MotivoRechazo | null;
  motivo_comentario: string | null;
  aviso_fin_id: string | null;
}

interface Entrega {
  id: string;
  fecha_pago: string;
  tipo: TipoConstancia;
  proxima_fecha_pago: string | null;
  estado: EstadoEntrega;
  origen: "colaboradora" | "do" | "migrada";
  enviada_at: string;
  revisada_at: string | null;
  retirada_at: string | null;
  motivo_categoria: MotivoRechazo | null;
  motivo_comentario: string | null;
  reemplaza_a: string | null;
  archivos: { id: string; ruta: string; nombre: string; tipo_mime: string | null; bytes: number | null }[];
}

const soles = (n: number) =>
  `S/ ${Number(n).toLocaleString("es-PE", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

/** Un timestamptz → «15/09/2026 · 08:43», en hora de Lima. */
function fechaHora(ts: string | null): string {
  if (!ts) return "—";
  const f = new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA, day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit", hour12: false,
  }).formatToParts(new Date(ts));
  const p = (t: string) => f.find((x) => x.type === t)?.value ?? "";
  return `${p("day")}/${p("month")}/${p("year")} · ${p("hour")}:${p("minute")}`;
}

const kb = (b: number) => (b >= 1048576 ? `${(b / 1048576).toFixed(1)} MB` : `${Math.max(1, Math.round(b / 1024))} KB`);

function tipoPorDefecto(frecuencia: FrecuenciaPago | null): TipoConstancia {
  return frecuencia === "ciclo" ? "pago_ciclo" : frecuencia === "unico" ? "matricula" : "cuota_mensual";
}

/** Lo que se le dice a ella sobre su constancia. Una sola frase, con la fecha que importa. */
function fraseDeConstancia(s: Situacion, hoy: string): string {
  const plazo = s.plazo ? ` Tienes hasta el ${fechaCorta(s.plazo)}.` : "";
  switch (s.estado_constancia) {
    case "pendiente_revision":
      return "Desarrollo Organizacional la está revisando. Te avisamos en tu Bandeja cuando termine.";
    case "rechazada":
      return `No se pudo aprobar la constancia del pago del ${fechaCorta(s.fecha_pago_constancia)}. Corrígela y vuelve a enviarla.${plazo}`;
    case "vencida":
      return `Tu pago del ${fechaCorta(s.fecha_pago_constancia)} todavía no tiene su constancia y el plazo pasó. Súbela cuanto antes.`;
    case "por_vencer":
    case "falta_enviar":
      return `Tu pago del ${fechaCorta(s.fecha_pago_constancia)} necesita su constancia.${plazo}`;
    case "al_dia":
      return s.proxima_fecha_pago && s.proxima_fecha_pago > hoy
        ? `Tu próximo pago es el ${fechaCorta(s.proxima_fecha_pago)}. Cuando pagues, sube aquí la constancia.`
        : "No tienes constancias pendientes.";
    case "sin_calendario":
      return "Todavía no está registrado cuándo pagas a tu institución. Cuando pagues, sube aquí la constancia e indica tu próxima fecha de pago.";
  }
}

function EducacionContenido() {
  const router = useRouter();
  const params = useSearchParams();
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const hoy = hoyLima();

  const [personaId, setPersonaId] = useState<string | null>(null);
  const [situaciones, setSituaciones] = useState<Situacion[]>([]);
  const [historial, setHistorial] = useState<Record<string, Entrega[]>>({});
  const [textoValido, setTextoValido] = useState<string>("");
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [aviso, setAviso] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);

  const cargar = useCallback(async () => {
    setError(null);
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/mio"); return; }
    const uid = sesion.session.user.id;

    const { data: p } = await supabase.from("personas").select("id").eq("auth_user_id", uid).maybeSingle();
    if (!p) {
      setCargando(false);
      setError("Tu cuenta todavía no está enlazada con tu ficha. Avisa a Desarrollo Organizacional.");
      return;
    }
    const yo = p.id as string;
    setPersonaId(yo);

    const [sit, cfg] = await Promise.all([
      supabase.rpc("fn_educacion_situacion"),
      supabase.from("configuracion").select("valor").eq("clave", "educacion_constancias_validas").maybeSingle(),
    ]);
    if (sit.error) {
      setCargando(false);
      setError(mensajeDeError(sit.error, "traer tu apoyo educativo"));
      return;
    }
    // El filtro explícito: DO que abre /mio recibe a todo el equipo.
    const mias = ((sit.data ?? []) as unknown as Situacion[]).filter((s) => s.persona_id === yo);
    setSituaciones(mias);
    setTextoValido(typeof cfg.data?.valor === "string" ? cfg.data.valor : "");

    const historias = await Promise.all(
      mias.map((s) => supabase.rpc("fn_educacion_entregas", { p_familia_id: s.familia_id })),
    );
    setHistorial(Object.fromEntries(mias.map((s, i) => [s.familia_id, (historias[i].data ?? []) as unknown as Entrega[]])));
    setCargando(false);
  }, [supabase, router]);

  // eslint-disable-next-line react-hooks/set-state-in-effect -- cargar al montar, mismo patrón que /mio/movilidad.
  useEffect(() => { void cargar(); }, [cargar]);

  // Desde la Bandeja se llega a un estudio concreto.
  const familiaPedida = params.get("familia");
  useEffect(() => {
    if (!familiaPedida || cargando) return;
    document.getElementById(`estudio-${familiaPedida}`)?.scrollIntoView({ behavior: "smooth", block: "start" });
  }, [familiaPedida, cargando]);

  if (cargando) return <main className="p-6"><Cargando /></main>;

  if (error) {
    return (
      <main className="p-6">
        <p className="max-w-md rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo-profundo">
          {error} <Boton variante="enlace" onClick={() => void cargar()}>Reintentar</Boton>
        </p>
        <Link href="/mio" className="mt-3 inline-block text-sm text-taupe hover:text-tinta hover:underline">← Volver a Info</Link>
      </main>
    );
  }

  const activas = situaciones.filter((s) => s.vigencia !== "terminada");
  const anteriores = situaciones.filter((s) => s.vigencia === "terminada");

  return (
    <main className="mx-auto w-full max-w-2xl px-4 py-6 sm:px-6">
      <Link href="/mio" className="mb-4 inline-block text-sm text-taupe hover:text-tinta hover:underline">← Volver a Info</Link>
      <h1 className="mb-1 font-serif text-2xl">Educación</h1>
      <p className="mb-6 text-sm text-taupe">
        El apoyo de CAYLA para tus estudios o los de tus hijos, y las constancias que lo respaldan.
      </p>

      {aviso && (
        <p role="status" className={`mb-4 rounded-xl px-4 py-3 text-sm ${aviso.tipo === "ok" ? "bg-verde/10 text-verde" : "bg-rojo/10 text-rojo-profundo"}`}>
          {aviso.texto}
        </p>
      )}

      {situaciones.length === 0 ? (
        <section className="rounded-2xl border border-sand bg-papel p-5 text-sm">
          <h2 className="mb-1 font-serif text-lg">No tienes una asignación educativa activa</h2>
          <p className="text-taupe">
            Si CAYLA aprueba un apoyo para tus estudios o los de tu hijo o hija, aparecerá aquí y desde aquí
            subirás sus constancias.
          </p>
        </section>
      ) : (
        <div className="flex flex-col gap-6">
          {activas.map((s) => (
            <Estudio
              key={s.familia_id}
              situacion={s}
              historial={historial[s.familia_id] ?? []}
              personaId={personaId!}
              textoValido={textoValido}
              hoy={hoy}
              onCambio={async (texto) => { setAviso({ tipo: "ok", texto }); await cargar(); }}
              onError={(texto) => setAviso({ tipo: "error", texto })}
            />
          ))}
          {activas.length === 0 && (
            <section className="rounded-2xl border border-sand bg-papel p-5 text-sm text-taupe">
              No tienes una asignación educativa activa. Tus estudios anteriores están abajo.
            </section>
          )}
          {anteriores.length > 0 && (
            <details className="rounded-2xl border border-sand p-5 text-sm">
              <summary className="cursor-pointer font-medium">Estudios anteriores ({anteriores.length})</summary>
              <div className="mt-4 flex flex-col gap-4">
                {anteriores.map((s) => (
                  <Historial key={s.familia_id} titulo={`${s.institucion} · hasta el ${fechaCorta(s.vigente_hasta)}`}
                    entregas={historial[s.familia_id] ?? []} />
                ))}
              </div>
            </details>
          )}
        </div>
      )}
    </main>
  );
}

function Estudio({
  situacion: s, historial, personaId, textoValido, hoy, onCambio, onError,
}: {
  situacion: Situacion;
  historial: Entrega[];
  personaId: string;
  textoValido: string;
  hoy: string;
  onCambio: (texto: string) => Promise<void>;
  onError: (texto: string) => void;
}) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const [formulario, setFormulario] = useState<{ reemplazaA: string | null } | null>(null);
  const [retirando, setRetirando] = useState(false);
  const [confirmarRetiro, setConfirmarRetiro] = useState(false);
  const [avisoFin, setAvisoFin] = useState(false);

  const estado = ESTADO_CONSTANCIA[s.estado_constancia];
  const pendiente = historial.find((e) => e.estado === "pendiente") ?? null;
  const rechazada = s.estado_constancia === "rechazada" ? historial.find((e) => e.id === s.entrega_id) ?? null : null;

  async function retirar() {
    if (!pendiente) return;
    setRetirando(true);
    const { error } = await supabase.rpc("fn_educacion_retirar_entrega", { p_id: pendiente.id });
    setRetirando(false);
    setConfirmarRetiro(false);
    if (error) { onError(mensajeDeError(error, "retirar el envío")); return; }
    await onCambio("Retiraste el envío. Queda en tu historial como retirado; puedes enviar la constancia de nuevo cuando quieras.");
  }

  return (
    <section id={`estudio-${s.familia_id}`} className="scroll-mt-6 overflow-hidden rounded-2xl border border-sand bg-papel">
      {/* ── EL BENEFICIO ─────────────────────────────────────────────────── */}
      <div className="p-5">
        <p className="text-xs font-medium uppercase tracking-wide text-taupe">
          Apoyo educativo {s.vigencia === "futura" ? "programado" : "activo"}
        </p>
        <h2 className="mt-1 font-serif text-xl">{s.institucion}</h2>
        <dl className="mt-4 grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
          <div>
            <dt className="text-xs text-taupe">Estudia</dt>
            <dd>{s.beneficiario === "hijo" ? (s.beneficiario_nombre ?? "Tu hijo o hija") : "Tú"}</dd>
          </div>
          <div>
            <dt className="text-xs text-taupe">Apoyo mensual</dt>
            <dd className="tabular-nums">{soles(s.monto)}</dd>
          </div>
          <div>
            <dt className="text-xs text-taupe">Vigencia</dt>
            <dd>Desde el {fechaCorta(s.vigente_desde)}<span className="block text-xs text-taupe">hasta el {fechaCorta(s.vigente_hasta)}</span></dd>
          </div>
          <div>
            <dt className="text-xs text-taupe">Próximo pago a tu institución</dt>
            <dd>
              {s.proxima_fecha_pago ? fechaCorta(s.proxima_fecha_pago) : "Sin registrar"}
              {s.frecuencia_pago && <span className="block text-xs text-taupe">{FRECUENCIA_PAGO_LABELS[s.frecuencia_pago]}</span>}
            </dd>
          </div>
        </dl>
      </div>

      {/* ── LA CONSTANCIA ────────────────────────────────────────────────── */}
      <div className="border-t border-sand bg-hueso p-5">
        <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
          <h3 className="text-xs font-medium uppercase tracking-wide text-taupe">Constancia</h3>
          <Insignia variante={estado.tono}>{estado.etiqueta}</Insignia>
        </div>
        <p className="text-sm">{fraseDeConstancia(s, hoy)}</p>

        {rechazada && (
          <div className="mt-3 rounded-xl border border-rojo/30 bg-rojo/5 p-3 text-sm">
            <p className="font-medium text-rojo-profundo">
              Motivo: {rechazada.motivo_categoria ? MOTIVO_RECHAZO_LABELS[rechazada.motivo_categoria] : "—"}
            </p>
            {rechazada.motivo_comentario && <p className="mt-1">«{rechazada.motivo_comentario}»</p>}
          </div>
        )}

        {pendiente && (
          <div className="mt-3 rounded-xl border border-sand bg-papel p-3 text-sm">
            <p>Pago del {fechaCorta(pendiente.fecha_pago)} · {TIPO_CONSTANCIA_LABELS[pendiente.tipo]}</p>
            <p className="text-xs text-taupe">
              Enviada el {fechaHora(pendiente.enviada_at)} · {pendiente.archivos.length} archivo{pendiente.archivos.length === 1 ? "" : "s"}
            </p>
            <ListaArchivos archivos={pendiente.archivos} />
          </div>
        )}

        <p className="mt-3 text-xs text-taupe">
          La revisión no cambia lo que cobras este mes: la constancia es el respaldo que CAYLA necesita para sostener este apoyo.
        </p>

        {!formulario && (
          <div className="mt-4 flex flex-col gap-2 sm:flex-row sm:flex-wrap">
            {pendiente ? (
              <>
                <Boton className="w-full sm:w-auto" onClick={() => setFormulario({ reemplazaA: pendiente.id })}>Reemplazar envío</Boton>
                <Boton variante="sutil" className="w-full sm:w-auto" onClick={() => setConfirmarRetiro(true)}>Retirar envío</Boton>
              </>
            ) : rechazada ? (
              <Boton variante="primario" className="w-full sm:w-auto" onClick={() => setFormulario({ reemplazaA: rechazada.id })}>
                Corregir y volver a enviar
              </Boton>
            ) : (
              <Boton
                variante={s.estado_constancia === "al_dia" ? "secundario" : "primario"}
                className="w-full sm:w-auto"
                onClick={() => setFormulario({ reemplazaA: null })}
              >
                Subir constancia
              </Boton>
            )}
          </div>
        )}

        {formulario && (
          <FormularioConstancia
            situacion={s}
            personaId={personaId}
            textoValido={textoValido}
            reemplazaA={formulario.reemplazaA}
            hoy={hoy}
            onCancelar={() => setFormulario(null)}
            onEnviada={async () => {
              setFormulario(null);
              await onCambio("Constancia enviada. Desarrollo Organizacional la va a revisar y te avisamos en tu Bandeja.");
            }}
          />
        )}
      </div>

      {/* ── HISTORIAL ────────────────────────────────────────────────────── */}
      <div className="border-t border-sand p-5">
        <Historial titulo="Historial de constancias" entregas={historial} />
        {s.aviso_fin_id ? (
          <p className="mt-4 text-xs text-taupe">Avisaste que ya no vas a pagar este estudio. Desarrollo Organizacional lo está viendo.</p>
        ) : (
          <Boton variante="enlace" className="mt-4 text-xs text-taupe" onClick={() => setAvisoFin(true)}>
            Ya no voy a pagar este estudio
          </Boton>
        )}
      </div>

      <Modal abierto={confirmarRetiro} onCerrar={() => setConfirmarRetiro(false)} bloqueado={retirando}
        titulo="¿Retirar este envío?" ancho="sm">
        <p className="mb-4 text-sm text-taupe">
          Desarrollo Organizacional ya no lo va a revisar. No se borra: queda en tu historial como retirado, y puedes
          enviar la constancia de nuevo cuando quieras.
        </p>
        <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <Boton onClick={() => setConfirmarRetiro(false)} disabled={retirando}>Cancelar</Boton>
          <Boton variante="peligro" cargando={retirando} onClick={() => void retirar()}>Retirar envío</Boton>
        </div>
      </Modal>

      <AvisoFin abierto={avisoFin} situacion={s} onCerrar={() => setAvisoFin(false)}
        onAvisado={async () => { setAvisoFin(false); await onCambio("Listo. Desarrollo Organizacional va a revisar tu aviso."); }}
        onError={onError} />
    </section>
  );
}

function FormularioConstancia({
  situacion: s, personaId, textoValido, reemplazaA, hoy, onCancelar, onEnviada,
}: {
  situacion: Situacion;
  personaId: string;
  textoValido: string;
  reemplazaA: string | null;
  hoy: string;
  onCancelar: () => void;
  onEnviada: () => Promise<void>;
}) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  // El id del envío nace con el formulario y sobrevive a un reintento: los
  // archivos que ya subieron quedan en su carpeta y no se vuelven a subir.
  const [entregaId] = useState(() => crypto.randomUUID());

  // La fecha que bloquea el envío nace con valor (CLAUDE.md, 2026-08-26): la
  // del pago que se está pidiendo, o hoy si ese pago todavía no llega.
  const fechaInicial = s.fecha_pago_constancia && s.fecha_pago_constancia <= hoy ? s.fecha_pago_constancia : hoy;
  const [fechaPago, setFechaPago] = useState(fechaInicial);
  const [tipo, setTipo] = useState<TipoConstancia>(tipoPorDefecto(s.frecuencia_pago));
  const [proxima, setProxima] = useState<string>(sugerirProximaFecha(fechaInicial, s.frecuencia_pago) ?? "");
  const [proximaTocada, setProximaTocada] = useState(false);
  const [ultimoPago, setUltimoPago] = useState(false);
  const [nota, setNota] = useState("");
  const [archivos, setArchivos] = useState<ArchivoElegido[]>([]);
  const [progreso, setProgreso] = useState<Record<string, number>>({});
  const [fallo, setFallo] = useState<{ clave: string | null; texto: string } | null>(null);
  const [enviando, setEnviando] = useState(false);
  const camara = useRef<HTMLInputElement>(null);
  const galeria = useRef<HTMLInputElement>(null);

  // Las vistas previas son URLs locales: se sueltan al irse.
  const vistas = useRef<string[]>([]);
  useEffect(() => () => { vistas.current.forEach((u) => URL.revokeObjectURL(u)); }, []);

  function cambiarFecha(v: string) {
    setFechaPago(v);
    if (!proximaTocada) setProxima(sugerirProximaFecha(v, s.frecuencia_pago) ?? "");
  }

  function agregar(lista: FileList | null) {
    if (!lista) return;
    setFallo(null);
    const nuevos: ArchivoElegido[] = [];
    for (const f of Array.from(lista)) {
      const problema = problemaDeArchivo({ nombre: f.name, tipo: f.type, bytes: f.size });
      if (problema) { setFallo({ clave: null, texto: problema }); continue; }
      const a = elegido(f);
      if (a.vista) vistas.current.push(a.vista);
      nuevos.push(a);
    }
    setArchivos((prev) => {
      const juntos = [...prev, ...nuevos];
      if (juntos.length > ARCHIVOS_POR_ENTREGA) {
        setFallo({ clave: null, texto: `Un envío admite hasta ${ARCHIVOS_POR_ENTREGA} archivos. Quita alguno para agregar otro.` });
        return juntos.slice(0, ARCHIVOS_POR_ENTREGA);
      }
      return juntos;
    });
  }

  function quitar(clave: string) {
    setArchivos((prev) => prev.filter((a) => a.clave !== clave));
    if (fallo?.clave === clave) setFallo(null);
  }

  async function enviar() {
    setFallo(null);
    if (archivos.length === 0) { setFallo({ clave: null, texto: "Agrega al menos una foto o un PDF de la constancia." }); return; }
    if (!fechaPago) { setFallo({ clave: null, texto: "Indica en qué fecha pagaste." }); return; }
    if (fechaPago > hoy) { setFallo({ clave: null, texto: "La fecha de pago no puede ser posterior a hoy: la constancia se sube después de pagar." }); return; }
    if (!ultimoPago && proxima && proxima <= fechaPago) {
      setFallo({ clave: null, texto: "Tu próximo pago tiene que ser después del que estás respaldando." });
      return;
    }

    setEnviando(true);
    const subida = await subirArchivosDeEntrega(
      supabase, personaId, entregaId, archivos,
      (clave, pct) => setProgreso((p) => ({ ...p, [clave]: pct })),
      (clave, subido) => setArchivos((prev) => prev.map((a) => (a.clave === clave ? { ...a, subido } : a))),
    );
    if (!subida.ok) {
      setEnviando(false);
      setFallo({ clave: subida.clave, texto: `${subida.error} Tus archivos siguen elegidos: vuelve a intentarlo.` });
      return;
    }

    const { error } = await supabase.rpc("fn_educacion_enviar_entrega", {
      p_id: entregaId,
      p_asignacion_id: s.asignacion_id,
      p_fecha_pago: fechaPago,
      p_tipo: tipo,
      p_proxima_fecha_pago: ultimoPago || !proxima ? null : proxima,
      p_archivos: subida.archivos,
      p_nota: nota.trim() || null,
      p_reemplaza_a: reemplazaA,
    });
    setEnviando(false);
    if (error) {
      setFallo({ clave: null, texto: `${mensajeDeError(error, "enviar la constancia")} Tus archivos siguen elegidos.` });
      return;
    }
    await onEnviada();
  }

  const enCurso = enviando;

  return (
    <div className="mt-4 rounded-2xl border border-sand bg-papel p-4 sm:p-5">
      <h4 className="font-serif text-lg">{reemplazaA ? "Enviar la constancia corregida" : "Subir constancia"}</h4>

      {textoValido && <p className="mt-2 rounded-xl bg-hueso p-3 text-xs leading-relaxed text-tinta">{textoValido}</p>}

      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <Campo etiqueta="¿Qué fecha pagaste?" type="date" value={fechaPago} max={hoy}
          onChange={(e) => cambiarFecha(e.target.value)} disabled={enCurso} />
        <CampoSelect etiqueta="¿Qué es?" value={tipo} onChange={(e) => setTipo(e.target.value as TipoConstancia)} disabled={enCurso}>
          {TIPOS_CONSTANCIA.map((t) => <option key={t} value={t}>{TIPO_CONSTANCIA_LABELS[t]}</option>)}
        </CampoSelect>
        <div className="flex flex-col gap-1 sm:col-span-2">
          <Campo etiqueta="¿Cuándo es tu próximo pago?" type="date" value={ultimoPago ? "" : proxima}
            onChange={(e) => { setProxima(e.target.value); setProximaTocada(true); }} disabled={enCurso || ultimoPago} />
          <label className="flex items-center gap-2 text-xs text-taupe">
            <input type="checkbox" className="size-4 accent-tinta" checked={ultimoPago}
              onChange={(e) => setUltimoPago(e.target.checked)} disabled={enCurso} />
            Este fue mi último pago
          </label>
          <span className="text-xs text-taupe">Si todavía no sabes la fecha, déjala vacía: Desarrollo Organizacional te la preguntará.</span>
        </div>
      </div>

      {/* Dos botones grandes y no un solo campo de archivo: en el celular,
          «Tomar foto» abre la cámara directo (capture) y «Elegir archivos»
          deja escoger un PDF o fotos de la galería. */}
      <div className="mt-4 grid grid-cols-2 gap-2">
        <Boton type="button" className="w-full py-3" onClick={() => camara.current?.click()} disabled={enCurso}>Tomar foto</Boton>
        <Boton type="button" className="w-full py-3" onClick={() => galeria.current?.click()} disabled={enCurso}>Elegir archivos</Boton>
        <input ref={camara} type="file" accept="image/*" capture="environment" className="hidden"
          onChange={(e) => { agregar(e.target.files); e.target.value = ""; }} />
        <input ref={galeria} type="file" multiple accept="application/pdf,image/jpeg,image/png,image/heic,image/heif,.heic,.heif"
          className="hidden" onChange={(e) => { agregar(e.target.files); e.target.value = ""; }} />
      </div>
      <p className="mt-2 text-xs text-taupe">
        PDF o fotos. Si la constancia tiene varias páginas, agrégalas todas en este mismo envío (hasta {ARCHIVOS_POR_ENTREGA}).
      </p>

      {archivos.length > 0 && (
        <ul className="mt-3 flex flex-col gap-2">
          {archivos.map((a, i) => {
            const pct = progreso[a.clave];
            const conError = fallo?.clave === a.clave;
            return (
              <li key={a.clave} className={`flex items-center gap-3 rounded-xl border p-2 ${conError ? "border-rojo/40 bg-rojo/5" : "border-sand"}`}>
                {a.vista ? (
                  // eslint-disable-next-line @next/next/no-img-element -- vista previa local del archivo elegido
                  <img src={a.vista} alt={`Página ${i + 1}`} className="size-14 shrink-0 rounded-lg border border-sand object-cover" />
                ) : (
                  <span className="flex size-14 shrink-0 items-center justify-center rounded-lg border border-sand bg-hueso text-xs font-medium text-taupe">
                    {a.archivo.name.toLowerCase().endsWith(".pdf") ? "PDF" : "Foto"}
                  </span>
                )}
                <div className="min-w-0 flex-1 text-sm">
                  <p className="truncate">{a.archivo.name}</p>
                  <p className="text-xs text-taupe">
                    {a.subido ? "✓ Subido" : pct !== undefined && enCurso ? `Subiendo… ${pct}%` : kb(a.archivo.size)}
                  </p>
                </div>
                <Boton variante="sutil" tamano="sm" onClick={() => quitar(a.clave)} disabled={enCurso}
                  aria-label={`Quitar ${a.archivo.name}`}>Quitar</Boton>
              </li>
            );
          })}
        </ul>
      )}

      <div className="mt-3">
        <AreaTexto rows={2} value={nota} onChange={(e) => setNota(e.target.value)} disabled={enCurso}
          placeholder="Nota para Desarrollo Organizacional (opcional)" aria-label="Nota opcional" />
      </div>

      {fallo && <p role="alert" className="mt-3 rounded-xl bg-rojo/10 px-3 py-2 text-sm text-rojo-profundo">{fallo.texto}</p>}

      <div className="mt-4 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
        <Boton onClick={onCancelar} disabled={enCurso}>Cancelar</Boton>
        <Boton variante="primario" cargando={enCurso} onClick={() => void enviar()} disabled={archivos.length === 0}>
          {fallo && archivos.some((a) => a.subido) ? "Reintentar" : "Enviar para revisión"}
        </Boton>
      </div>
    </div>
  );
}

function ListaArchivos({ archivos }: { archivos: Entrega["archivos"] }) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const [fallo, setFallo] = useState<string | null>(null);
  if (archivos.length === 0) return null;
  return (
    <div className="mt-2">
      <ul className="flex flex-wrap gap-2">
        {archivos.map((a, i) => (
          <li key={a.id}>
            <Boton variante="enlace" className="text-xs" onClick={async () => {
              const error = await abrirArchivoFirmado(supabase, BUCKET_COMPROBANTES, a.ruta);
              setFallo(error);
            }}>
              {archivos.length === 1 ? "Ver archivo" : `Archivo ${i + 1}`}
            </Boton>
          </li>
        ))}
      </ul>
      {fallo && <p className="mt-1 text-xs text-rojo-profundo">{fallo}</p>}
    </div>
  );
}

function Historial({ titulo, entregas }: { titulo: string; entregas: Entrega[] }) {
  return (
    <div>
      <h3 className="mb-2 text-xs font-medium uppercase tracking-wide text-taupe">{titulo}</h3>
      {entregas.length === 0 ? (
        <p className="text-sm text-taupe">Todavía no hay constancias.</p>
      ) : (
        <ul className="divide-y divide-sand">
          {entregas.map((e) => {
            const est = ESTADO_ENTREGA[e.estado];
            return (
              <li key={e.id} className="py-2">
                <details>
                  <summary className="flex cursor-pointer list-none flex-wrap items-center justify-between gap-2 text-sm">
                    <span>
                      Pago del {fechaCorta(e.fecha_pago)}
                      <span className="text-taupe"> · {TIPO_CONSTANCIA_LABELS[e.tipo]}</span>
                      {e.reemplaza_a && <span className="text-xs text-taupe"> · corrección</span>}
                    </span>
                    <Insignia variante={est.tono}>{est.etiqueta}</Insignia>
                  </summary>
                  <div className="mt-2 rounded-xl bg-hueso p-3 text-xs text-taupe">
                    <p>{e.origen === "colaboradora" ? `Enviada el ${fechaHora(e.enviada_at)}` : "Cargada por Desarrollo Organizacional"}</p>
                    {e.revisada_at && e.estado !== "retirada" && (
                      <p>Revisada por Desarrollo Organizacional el {fechaHora(e.revisada_at)}</p>
                    )}
                    {e.retirada_at && <p>La retiraste el {fechaHora(e.retirada_at)}</p>}
                    {e.estado === "rechazada" && (
                      <p className="mt-1 text-rojo-profundo">
                        {e.motivo_categoria ? MOTIVO_RECHAZO_LABELS[e.motivo_categoria] : "Rechazada"}
                        {e.motivo_comentario ? `: «${e.motivo_comentario}»` : ""}
                      </p>
                    )}
                    <ListaArchivos archivos={e.archivos} />
                  </div>
                </details>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

function AvisoFin({
  abierto, situacion: s, onCerrar, onAvisado, onError,
}: {
  abierto: boolean;
  situacion: Situacion;
  onCerrar: () => void;
  onAvisado: () => Promise<void>;
  onError: (texto: string) => void;
}) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const [motivo, setMotivo] = useState("");
  const [guardando, setGuardando] = useState(false);

  async function avisar() {
    if (motivo.trim().length < 3) { onError("Cuenta brevemente por qué ya no vas a pagar."); return; }
    setGuardando(true);
    const { error } = await supabase.rpc("fn_educacion_avisar_fin", {
      p_asignacion_id: s.asignacion_id, p_motivo: motivo.trim(), p_ultimo_pago: null,
    });
    setGuardando(false);
    if (error) { onError(mensajeDeError(error, "enviar el aviso")); return; }
    setMotivo("");
    await onAvisado();
  }

  return (
    <Modal abierto={abierto} onCerrar={onCerrar} bloqueado={guardando} titulo="Ya no voy a pagar este estudio" ancho="sm">
      <p className="mb-3 text-sm text-taupe">
        Le avisamos a Desarrollo Organizacional para que cierre el apoyo de {s.institucion}. Hasta que lo haga, nada
        cambia.
      </p>
      <AreaTexto rows={3} value={motivo} onChange={(e) => setMotivo(e.target.value)} autoFocus
        placeholder="Por ejemplo: terminé el ciclo, dejé el curso, conseguí una beca" aria-label="Motivo" />
      <div className="mt-4 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
        <Boton onClick={onCerrar} disabled={guardando}>Cancelar</Boton>
        <Boton variante="primario" cargando={guardando} onClick={() => void avisar()}>Enviar aviso</Boton>
      </div>
    </Modal>
  );
}

export default function MiEducacionPage() {
  return (
    <Suspense fallback={<main className="p-6"><Cargando /></main>}>
      <EducacionContenido />
    </Suspense>
  );
}

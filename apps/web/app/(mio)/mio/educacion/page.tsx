"use client";

import { Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import {
  ARCHIVOS_POR_ENTREGA, ESTADO_CONSTANCIA, ESTADO_ENTREGA, ESTADO_SOLICITUD, FRECUENCIA_PAGO_LABELS,
  MOTIVO_RECHAZO_LABELS, TIPOS_CONSTANCIA, TIPO_CONSTANCIA_LABELS, TZ_LIMA, VIGENCIA_CORTA_DIAS, diasDeVigencia,
  finDeCicloSugerido, hoyLima, problemaDeArchivo, sugerirProximaFecha,
  type EstadoConstancia, type EstadoEntrega, type EstadoSolicitud, type FrecuenciaPago, type MotivoRechazo,
  type TipoConstancia, nombreDelMesLima,
} from "@cayla-dynamic/shared";
import { EnlaceVolver } from "@/components/enlace-volver";
import { Cargando } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { Modal } from "@/components/ui/modal";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { enDias } from "@/lib/admin/bandeja-urgencia";
import { abrirArchivoFirmado } from "@/lib/abrir-archivo-firmado";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import { mesDe, sumarMeses } from "@/lib/admin/educacion-meses";
import { mesesParaLaBase, problemaDelPago, repartirPago, sumaDelPago, type Correccion } from "@/lib/educacion-adelantado";
import { HistorialEducacion } from "@/components/educacion/historial-educacion";
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

interface Solicitud {
  id: string;
  institucion: string;
  costo_declarado: number;
  beneficiario: "trabajador" | "hijo";
  beneficiario_nombre: string | null;
  vigente_desde: string;
  vigente_hasta: string;
  comprobante_url: string | null;
  nota: string | null;
  estado: EstadoSolicitud;
  enviada_at: string;
  motivo_rechazo: string | null;
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
  const plazo = s.plazo && s.dias_para_plazo !== null
    ? ` ${enDias(s.dias_para_plazo, { futuro: "Vence", pasado: "Venció" })}.`
    : "";
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
  const [solicitud, setSolicitud] = useState<Solicitud | null>(null);
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

    // Su propia solicitud más reciente (0461) — solo importa cuando no tiene
    // ningún apoyo activo/futuro todavía. RLS ya la limita a la suya.
    const { data: sol } = await supabase.from("educacion_solicitudes").select("*")
      .eq("persona_id", yo).order("enviada_at", { ascending: false }).limit(1).maybeSingle();
    setSolicitud((sol ?? null) as unknown as Solicitud | null);

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
        <EnlaceVolver href="/mio" className="mt-3 inline-block text-sm text-taupe hover:text-tinta hover:underline">← Volver a Info</EnlaceVolver>
      </main>
    );
  }

  const activas = situaciones.filter((s) => s.vigencia !== "terminada");
  const anteriores = situaciones.filter((s) => s.vigencia === "terminada");
  // De la que terminó más tarde sale la renovación: es la que la persona
  // reconoce como «mi apoyo».
  const ultimoTerminado = anteriores.reduce<Situacion | null>(
    (m, s) => (!m || s.vigente_hasta > m.vigente_hasta ? s : m), null);
  // Con algo por corregir adentro, «Estudios anteriores» nace abierto: cerrado,
  // lo único que ella tiene que hacer quedaría escondido.
  const anteriorPorCorregir = anteriores.some(corregibleTerminado);

  return (
    <main className="mx-auto w-full max-w-2xl px-4 py-6 sm:px-6">
      <EnlaceVolver href="/mio" className="mb-4 inline-block text-sm text-taupe hover:text-tinta hover:underline">← Volver a Info</EnlaceVolver>
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
        <SolicitudApoyo
          solicitud={solicitud}
          ultimoTerminado={null}
          personaId={personaId!}
          hoy={hoy}
          onCambio={async (texto) => { setAviso({ tipo: "ok", texto }); await cargar(); }}
          onError={(texto) => setAviso({ tipo: "error", texto })}
        />
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
            <SolicitudApoyo
              solicitud={solicitud}
              ultimoTerminado={ultimoTerminado}
              personaId={personaId!}
              hoy={hoy}
              onCambio={async (texto) => { setAviso({ tipo: "ok", texto }); await cargar(); }}
              onError={(texto) => setAviso({ tipo: "error", texto })}
            />
          )}
          {anteriores.length > 0 && (
            <details open={anteriorPorCorregir} className="rounded-2xl border border-sand p-5 text-sm">
              <summary className="cursor-pointer font-medium">Estudios anteriores ({anteriores.length})</summary>
              <div className="mt-4 flex flex-col gap-4">
                {anteriores.map((s) => (
                  <EstudioTerminado
                    key={s.familia_id}
                    situacion={s}
                    historial={historial[s.familia_id] ?? []}
                    personaId={personaId!}
                    textoValido={textoValido}
                    hoy={hoy}
                    onCambio={async (texto) => { setAviso({ tipo: "ok", texto }); await cargar(); }}
                  />
                ))}
              </div>
            </details>
          )}
        </div>
      )}

      {/* Su recorrido en Educación (0529): lo que envió, qué se aprobó o rechazó y por qué. Sin nombres
          de quién de DO lo hizo: eso lo decide la base, no esta pantalla. */}
      <details className="mt-6 rounded-2xl border border-sand p-4">
        <summary className="cursor-pointer font-serif text-base">Tu historial</summary>
        <div className="mt-3"><HistorialEducacion modo="ella" /></div>
      </details>
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
  // Pago adelantado (0529): un solo pago que cubre varios meses. Los meses nacen llenos —del mes en
  // que pagó a cuatro meses después— para que nada que bloquee el envío arranque vacío.
  const [cuantos, setCuantos] = useState<"uno" | "varios">("uno");
  const [desdeMes, setDesdeMes] = useState(mesDe(fechaInicial));
  const [hastaMes, setHastaMes] = useState(sumarMeses(mesDe(fechaInicial), 4));
  const [sabe, setSabe] = useState<"total" | "cada">("total");
  const [total, setTotal] = useState("");
  const [cada, setCada] = useState("");
  const [correcciones, setCorrecciones] = useState<Record<string, Correccion>>({});
  const [corrigiendo, setCorrigiendo] = useState<{ mes: string; monto: string; motivo: string } | null>(null);
  const reparto = useMemo(
    () => repartirPago({ desde: desdeMes, hasta: hastaMes, sabe, total: Number(total) || 0, cada: Number(cada) || 0, correcciones }),
    [desdeMes, hastaMes, sabe, total, cada, correcciones],
  );
  const problemaAdelantado = cuantos === "varios" ? problemaDelPago(reparto, sabe, Number(total) || 0) : null;
  const opcionesDeMes = useMemo(() => {
    const r: string[] = [];
    for (let m = sumarMeses(mesDe(hoy), -12); m <= sumarMeses(mesDe(hoy), 18); m = sumarMeses(m, 1)) r.push(m);
    return r;
  }, [hoy]);
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
    if (cuantos === "varios" && problemaAdelantado) { setFallo({ clave: null, texto: problemaAdelantado }); return; }
    if (cuantos === "uno" && !ultimoPago && proxima && proxima <= fechaPago) {
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

    const { error } = cuantos === "varios" ? await supabase.rpc("fn_educacion_enviar_adelantado", {
      p_id: entregaId,
      p_asignacion_id: s.asignacion_id,
      p_fecha_pago: fechaPago,
      p_tipo: tipo,
      p_meses: mesesParaLaBase(reparto),
      p_archivos: subida.archivos,
      p_nota: nota.trim() || null,
      p_reemplaza_a: reemplazaA,
    }) : await supabase.rpc("fn_educacion_enviar_entrega", {
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
          <span className="text-sm text-taupe">¿Cuántos meses cubre este pago?</span>
          <div className="grid grid-cols-2 gap-2" role="group" aria-label="Cuántos meses cubre este pago">
            {([["uno", "Un solo mes", "Como siempre."], ["varios", "Varios meses de una vez", "Ej. de agosto a diciembre."]] as const).map(([k, t, d]) => (
              <button key={k} type="button" aria-pressed={cuantos === k} disabled={enCurso}
                onClick={() => { setCuantos(k); setFallo(null); }}
                className={`rounded-xl border px-3 py-2 text-left ${cuantos === k ? "border-tinta ring-1 ring-tinta" : "border-sand"}`}>
                <span className="block text-sm font-medium">{t}</span>
                <span className="block text-xs text-taupe">{d}</span>
              </button>
            ))}
          </div>
        </div>
        {cuantos === "varios" ? (
          <div className="flex flex-col gap-3 sm:col-span-2">
            <div className="grid grid-cols-2 gap-3">
              <CampoSelect etiqueta="Desde" value={desdeMes} disabled={enCurso}
                onChange={(e) => { setDesdeMes(e.target.value); setCorrecciones({}); }}>
                {opcionesDeMes.map((m) => <option key={m} value={m}>{nombreDelMesLima(`${m}-15`)} {m.slice(0, 4)}</option>)}
              </CampoSelect>
              <CampoSelect etiqueta="Hasta" value={hastaMes} disabled={enCurso}
                onChange={(e) => { setHastaMes(e.target.value); setCorrecciones({}); }}>
                {opcionesDeMes.map((m) => <option key={m} value={m}>{nombreDelMesLima(`${m}-15`)} {m.slice(0, 4)}</option>)}
              </CampoSelect>
            </div>
            <div className="flex flex-wrap items-center gap-2 text-sm">
              <span className="text-taupe">¿Sabes cuánto pagaste por cada mes?</span>
              {([["total", "Solo sé el total"], ["cada", "Sé el de cada mes"]] as const).map(([k, t]) => (
                <button key={k} type="button" aria-pressed={sabe === k} disabled={enCurso}
                  onClick={() => { setSabe(k); setCorrecciones({}); }}
                  className={`rounded-full border px-3 py-1 text-xs font-medium ${sabe === k ? "border-tinta bg-tinta text-crema" : "border-sand"}`}>{t}</button>
              ))}
            </div>
            {sabe === "total"
              ? <Campo etiqueta="Total que pagaste (S/)" inputMode="decimal" value={total} onChange={(e) => setTotal(e.target.value)} disabled={enCurso} />
              : <Campo etiqueta="Monto de cada mes (S/)" inputMode="decimal" value={cada} onChange={(e) => setCada(e.target.value)} disabled={enCurso} />}
            <div>
              <p className="mb-1 text-sm font-medium">El sistema sacó {reparto.length} {reparto.length === 1 ? "mes" : "meses"}:</p>
              <table className="w-full text-sm">
                <tbody>
                  {reparto.map((x) => (
                    <tr key={x.mes} className="border-t border-sand">
                      <td className="py-1.5">
                        {nombreDelMesLima(`${x.mes}-15`)} {x.mes.slice(0, 4)}
                        <span className={`block text-xs ${x.origen === "manual" ? "text-ambar" : "text-taupe"}`}>
                          {x.origen === "manual" ? `Lo corregiste: «${x.motivo}»` : x.origen === "puesto" ? "El que pusiste" : "El resto del total, repartido"}
                        </span>
                      </td>
                      <td className="py-1.5 text-right tabular-nums">S/ {x.monto.toFixed(2)}</td>
                      <td className="py-1.5 text-right">
                        <Boton variante="sutil" tamano="sm" disabled={enCurso}
                          onClick={() => setCorrigiendo({ mes: x.mes, monto: String(x.monto), motivo: correcciones[x.mes]?.motivo ?? "" })}>Corregir</Boton>
                      </td>
                    </tr>
                  ))}
                  <tr className="border-t border-sand font-medium"><td className="py-1.5">Suma</td><td className="py-1.5 text-right tabular-nums">S/ {sumaDelPago(reparto).toFixed(2)}</td><td /></tr>
                </tbody>
              </table>
              {corrigiendo && (
                <div className="mt-2 flex flex-col gap-2 rounded-xl border border-ambar/40 bg-ambar/10 p-3">
                  <p className="text-sm font-medium">Corregir {nombreDelMesLima(`${corrigiendo.mes}-15`)}</p>
                  <Campo etiqueta="Monto de ese mes (S/)" inputMode="decimal" value={corrigiendo.monto}
                    onChange={(e) => setCorrigiendo({ ...corrigiendo, monto: e.target.value })} />
                  <Campo etiqueta="¿Por qué lo cambias? (mínimo 3 letras)" value={corrigiendo.motivo} placeholder="ej. agosto incluía la matrícula"
                    onChange={(e) => setCorrigiendo({ ...corrigiendo, motivo: e.target.value })} />
                  <div className="flex justify-end gap-2">
                    <Boton tamano="sm" onClick={() => setCorrigiendo(null)}>Cancelar</Boton>
                    <Boton tamano="sm" variante="primario"
                      disabled={corrigiendo.motivo.trim().length < 3 || !(Number(corrigiendo.monto) >= 0) || corrigiendo.monto === ""}
                      onClick={() => {
                        setCorrecciones((c) => ({ ...c, [corrigiendo.mes]: { monto: Number(corrigiendo.monto), motivo: corrigiendo.motivo.trim() } }));
                        setCorrigiendo(null);
                      }}>Guardar</Boton>
                  </div>
                </div>
              )}
              <p className="mt-1 text-xs text-taupe">
                Lo que corrijas se respeta y el resto del total se reparte entre los otros meses. Desarrollo Organizacional
                ve qué meses calculó el sistema y cuáles cambiaste tú. Aprobada, no tendrás que enviar constancia de esos meses.
              </p>
              {problemaAdelantado && (total || cada) && <p className="mt-1 text-xs text-rojo-profundo">{problemaAdelantado}</p>}
            </div>
          </div>
        ) : (
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
        )}
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

/**
 * ¿Le queda algo por hacer en un estudio que ya terminó? Solo una cosa: la
 * constancia RECHAZADA de un pago hecho dentro de la vigencia.
 */
function corregibleTerminado(s: Situacion): boolean {
  return s.vigencia === "terminada" && s.estado_constancia === "rechazada" && s.entrega_id !== null
    && s.fecha_pago_constancia !== null && s.fecha_pago_constancia <= s.vigente_hasta;
}

/**
 * Un estudio que ya terminó: su historial y una sola puerta abierta, corregir
 * la constancia rechazada de un pago hecho DENTRO de la vigencia.
 *
 * Por qué esa y ninguna otra. Ese pago CAYLA ya lo acompañó con el apoyo, y la
 * constancia es su respaldo: cerrarla al día siguiente del fin lo dejaba sin
 * respaldo para siempre. La base ya lo aceptaba —`fn_educacion_enviar_entrega`
 * no mira la vigencia—; el candado era solo de esta pantalla.
 *
 * Una constancia NUEVA, en cambio, no va aquí: un pago posterior al fin no lo
 * acompaña este apoyo, y aprobarla le diría «Aprobada» a quien ya no lo cobra —
 * se leería como «me lo pagan». Para seguir, está la renovación
 * (`SolicitudApoyo`, arriba).
 */
function EstudioTerminado({
  situacion: s, historial, personaId, textoValido, hoy, onCambio,
}: {
  situacion: Situacion;
  historial: Entrega[];
  personaId: string;
  textoValido: string;
  hoy: string;
  onCambio: (texto: string) => Promise<void>;
}) {
  const [corrigiendo, setCorrigiendo] = useState(false);
  const rechazada = corregibleTerminado(s) ? historial.find((e) => e.id === s.entrega_id) ?? null : null;
  const enRevision = s.estado_constancia === "pendiente_revision"
    ? historial.find((e) => e.estado === "pendiente") ?? null : null;

  return (
    <div>
      {rechazada && (
        <div className="mb-3 rounded-xl border border-rojo/30 bg-rojo/5 p-3">
          <p className="font-medium text-rojo-profundo">
            La constancia de tu pago del {fechaCorta(rechazada.fecha_pago)} no se pudo aprobar.
          </p>
          <p className="mt-1">
            Motivo: {rechazada.motivo_categoria ? MOTIVO_RECHAZO_LABELS[rechazada.motivo_categoria] : "—"}
            {rechazada.motivo_comentario && <> · «{rechazada.motivo_comentario}»</>}
          </p>
          <p className="mt-1 text-xs text-taupe">
            Ese pago lo hiciste mientras tu apoyo estaba vigente, así que puedes corregirla aunque el apoyo ya haya terminado.
          </p>
          {!corrigiendo && (
            <Boton variante="primario" className="mt-3 w-full sm:w-auto" onClick={() => setCorrigiendo(true)}>
              Corregir y volver a enviar
            </Boton>
          )}
        </div>
      )}
      {rechazada && corrigiendo && (
        <div className="mb-3">
          <FormularioConstancia
            situacion={s}
            personaId={personaId}
            textoValido={textoValido}
            reemplazaA={rechazada.id}
            hoy={hoy}
            onCancelar={() => setCorrigiendo(false)}
            onEnviada={async () => {
              setCorrigiendo(false);
              await onCambio("Constancia corregida y enviada. Desarrollo Organizacional la va a revisar y te avisamos en tu Bandeja.");
            }}
          />
        </div>
      )}
      {enRevision && (
        <p className="mb-3 text-xs text-taupe">
          Tu constancia del pago del {fechaCorta(enRevision.fecha_pago)} está en revisión. Te avisamos en tu Bandeja cuando termine.
        </p>
      )}
      <Historial titulo={`${s.institucion} · hasta el ${fechaCorta(s.vigente_hasta)}`} entregas={historial} />
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

/**
 * Quien todavía no tiene un apoyo educativo lo pide acá (0461): el mismo
 * formulario que usa DO para dar de alta, sin el monto — eso lo sigue
 * calculando el sistema al aprobar. Mientras está pendiente puede verla y
 * retirarla; si la rechazan, ve el motivo y puede corregir y reenviar.
 *
 * Y quien lo TUVO y ya terminó, lo renueva acá. Hasta octubre de 2026 una
 * solicitud aprobada cuyo apoyo había terminado dejaba esta tarjeta con
 * «Aprobada» y ni un botón, mientras la tarjeta de Info mandaba aquí con
 * «Solicitar apoyo educativo →»: dos puertas a la misma pared. Una solicitud
 * aprobada ya no es algo vivo —el apoyo que nació de ella se ve en su estudio—,
 * así que cuenta igual que no tener ninguna, y la tarjeta ofrece renovar con lo
 * que ya declaró adentro.
 */
function SolicitudApoyo({
  solicitud, ultimoTerminado, personaId, hoy, onCambio, onError,
}: {
  solicitud: Solicitud | null;
  ultimoTerminado: Situacion | null;
  personaId: string;
  hoy: string;
  onCambio: (texto: string) => Promise<void>;
  onError: (texto: string) => void;
}) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const [formulario, setFormulario] = useState<"nueva" | "renovar" | "corregir" | null>(null);
  const [retirando, setRetirando] = useState(false);
  const [confirmarRetiro, setConfirmarRetiro] = useState(false);
  // Adjuntar (o cambiar) el comprobante mientras la solicitud sigue pendiente (0522).
  const [adjuntando, setAdjuntando] = useState(false);
  const [archivoNuevo, setArchivoNuevo] = useState<File | null>(null);
  const [progresoNuevo, setProgresoNuevo] = useState<number | null>(null);
  const [subiendo, setSubiendo] = useState(false);

  async function adjuntar() {
    if (!solicitud || !archivoNuevo) return;
    setSubiendo(true);
    // Una carpeta nueva por subida, como en el formulario: nunca se escribe
    // encima del archivo anterior.
    const ext = archivoNuevo.name.split(".").pop()?.toLowerCase() ?? "bin";
    const ruta = `educacion/${personaId}/solicitudes/${crypto.randomUUID()}/comprobante.${ext}`;
    const errorSubida = await subirArchivoConProgreso(supabase, BUCKET_COMPROBANTES, ruta, archivoNuevo, setProgresoNuevo);
    if (errorSubida) {
      setSubiendo(false);
      onError(`El comprobante no subió: ${errorSubida}`);
      return;
    }
    const { error } = await supabase.rpc("fn_educacion_solicitud_adjuntar", { p_id: solicitud.id, p_ruta: ruta });
    setSubiendo(false);
    setProgresoNuevo(null);
    if (error) { onError(mensajeDeError(error, "adjuntar el comprobante")); return; }
    setAdjuntando(false);
    setArchivoNuevo(null);
    await onCambio("Listo: tu comprobante quedó adjunto. Desarrollo Organizacional lo verá al revisar tu solicitud.");
  }

  async function retirar() {
    if (!solicitud) return;
    setRetirando(true);
    const { error } = await supabase.rpc("fn_educacion_retirar_solicitud", { p_id: solicitud.id });
    setRetirando(false);
    setConfirmarRetiro(false);
    if (error) { onError(mensajeDeError(error, "retirar la solicitud")); return; }
    await onCambio("Retiraste tu solicitud. Puedes enviarla de nuevo cuando quieras.");
  }

  // Sin solicitud viva (nunca pidió, la retiró, o ya se la aprobaron y ese
  // apoyo terminó): renovar el último, la tarjeta vacía, o el formulario si ya
  // lo abrió.
  if (!solicitud || solicitud.estado === "retirada" || solicitud.estado === "aprobada") {
    const u = ultimoTerminado;
    if (formulario === "nueva" || (formulario === "renovar" && u)) {
      const renovando = formulario === "renovar" && u;
      return (
        <FormularioSolicitud
          personaId={personaId}
          hoy={hoy}
          modo={renovando ? "renovar" : "nueva"}
          valoresIniciales={renovando ? {
            institucion: u.institucion,
            beneficiario: u.beneficiario === "hijo" ? "hijo" : "trabajador",
            beneficiario_nombre: u.beneficiario_nombre,
            // El costo no vive en la asignación: sale de lo que ella declaró
            // la última vez, si fue para esta misma institución.
            costo_declarado: solicitud && solicitud.institucion === u.institucion ? solicitud.costo_declarado : undefined,
          } : undefined}
          onCancelar={() => setFormulario(null)}
          onEnviada={async () => {
            setFormulario(null);
            await onCambio("Solicitud enviada. Desarrollo Organizacional la va a revisar y te avisamos en tu Bandeja.");
          }}
        />
      );
    }
    if (u) {
      return (
        <section className="rounded-2xl border border-sand bg-papel p-5 text-sm">
          <p className="text-xs font-medium uppercase tracking-wide text-taupe">Apoyo educativo terminado</p>
          <h2 className="mt-1 font-serif text-xl">{u.institucion}</h2>
          <p className="mt-2">
            Tu apoyo terminó el {fechaCorta(u.vigente_hasta)}: ya no aparece en tus próximas boletas ni recibe constancias nuevas.
          </p>
          <p className="mt-2 text-taupe">
            ¿Sigues estudiando? Renuévalo hasta el fin de tu ciclo. Se pide una sola vez: después, cada mes subes aquí la
            constancia de tu pago, sin volver a pedirlo. Si ya pagaste este mes, adjunta esa constancia en la renovación.
          </p>
          <div className="mt-4 flex flex-col gap-2 sm:flex-row sm:flex-wrap">
            <Boton variante="primario" className="w-full sm:w-auto" onClick={() => setFormulario("renovar")}>
              Sigo estudiando: renovar mi apoyo
            </Boton>
            <Boton variante="sutil" className="w-full sm:w-auto" onClick={() => setFormulario("nueva")}>
              Es otro estudio
            </Boton>
          </div>
        </section>
      );
    }
    return (
      <section className="rounded-2xl border border-sand bg-papel p-5 text-sm">
        <h2 className="mb-1 font-serif text-lg">No tienes una asignación educativa activa</h2>
        <p className="mb-4 text-taupe">
          Si estudias tú o tu hijo o hija y CAYLA cubre parte del costo, pide aquí tu apoyo educativo.
        </p>
        <Boton variante="primario" onClick={() => setFormulario("nueva")}>Solicitar apoyo educativo</Boton>
      </section>
    );
  }

  const estado = ESTADO_SOLICITUD[solicitud.estado];

  return (
    <section className="rounded-2xl border border-sand bg-papel p-5 text-sm">
      <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
        <h2 className="font-serif text-lg">{solicitud.institucion}</h2>
        <Insignia variante={estado.tono}>{estado.etiqueta}</Insignia>
      </div>
      <p className="text-taupe">
        Pediste este apoyo el {fechaCorta(solicitud.enviada_at)} · costo declarado {soles(solicitud.costo_declarado)}
      </p>

      {solicitud.comprobante_url && (
        <Boton variante="enlace" className="mt-2 text-xs" onClick={async () => {
          const error = await abrirArchivoFirmado(supabase, BUCKET_COMPROBANTES, solicitud.comprobante_url!);
          if (error) onError(error);
        }}>
          Ver comprobante que adjuntaste
        </Boton>
      )}

      {solicitud.estado === "pendiente" && !formulario && (
        <>
          <p className="mt-3 text-xs text-taupe">
            Desarrollo Organizacional la está revisando. Te avisamos en tu Bandeja cuando termine.
          </p>

          {!solicitud.comprobante_url && !adjuntando && (
            <div className="mt-3 rounded-xl border border-ambar/40 bg-ambar/10 p-3 text-sm text-tinta">
              Todavía no adjuntaste el comprobante. Sin él, Desarrollo Organizacional no puede aprobar tu solicitud:
              adjúntalo aquí, no hace falta pedirla de nuevo.
            </div>
          )}

          {adjuntando && (
            <div className="mt-3 rounded-xl border border-sand bg-hueso p-3">
              <Campo etiqueta={solicitud.comprobante_url ? "Nuevo comprobante" : "Comprobante"}
                type="file" accept="application/pdf,image/jpeg,image/png"
                onChange={(e) => setArchivoNuevo(e.target.files?.[0] ?? null)} disabled={subiendo} />
              {progresoNuevo !== null && <p className="mt-1 text-xs text-taupe">Subiendo… {progresoNuevo}%</p>}
              <div className="mt-3 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
                <Boton onClick={() => { setAdjuntando(false); setArchivoNuevo(null); }} disabled={subiendo}>Cancelar</Boton>
                <Boton variante="primario" cargando={subiendo} disabled={!archivoNuevo} onClick={() => void adjuntar()}>
                  Adjuntar
                </Boton>
              </div>
            </div>
          )}

          <div className="mt-4 flex flex-col gap-2 sm:flex-row sm:flex-wrap">
            {!adjuntando && (
              <Boton variante={solicitud.comprobante_url ? "sutil" : "primario"} className="w-full sm:w-auto"
                onClick={() => setAdjuntando(true)}>
                {solicitud.comprobante_url ? "Cambiar comprobante" : "Adjuntar comprobante"}
              </Boton>
            )}
            <Boton variante="sutil" className="w-full sm:w-auto" onClick={() => setConfirmarRetiro(true)}>Retirar solicitud</Boton>
          </div>
        </>
      )}

      {solicitud.estado === "rechazada" && !formulario && (
        <>
          <div className="mt-3 rounded-xl border border-rojo/30 bg-rojo/5 p-3 text-sm">
            <p className="font-medium text-rojo-profundo">Motivo: {solicitud.motivo_rechazo}</p>
          </div>
          <Boton variante="primario" className="mt-4" onClick={() => setFormulario("corregir")}>Corregir y volver a enviar</Boton>
        </>
      )}

      {formulario === "corregir" && (
        <FormularioSolicitud
          personaId={personaId}
          hoy={hoy}
          modo="corregir"
          valoresIniciales={solicitud}
          onCancelar={() => setFormulario(null)}
          onEnviada={async () => {
            setFormulario(null);
            await onCambio("Solicitud enviada. Desarrollo Organizacional la va a revisar y te avisamos en tu Bandeja.");
          }}
        />
      )}

      <Modal abierto={confirmarRetiro} onCerrar={() => setConfirmarRetiro(false)} bloqueado={retirando}
        titulo="¿Retirar esta solicitud?" ancho="sm">
        <p className="mb-4 text-sm text-taupe">
          Desarrollo Organizacional ya no la va a revisar. Puedes enviarla de nuevo cuando quieras.
        </p>
        <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <Boton onClick={() => setConfirmarRetiro(false)} disabled={retirando}>Cancelar</Boton>
          <Boton variante="peligro" cargando={retirando} onClick={() => void retirar()}>Retirar solicitud</Boton>
        </div>
      </Modal>
    </section>
  );
}

type ValoresSolicitud = Partial<Pick<Solicitud,
  "institucion" | "beneficiario" | "beneficiario_nombre" | "costo_declarado" | "vigente_desde" | "vigente_hasta" | "nota">>;

const TITULO_SOLICITUD = {
  nueva: "Solicitar apoyo educativo",
  corregir: "Corregir y volver a enviar",
  renovar: "Renovar mi apoyo educativo",
} as const;

function FormularioSolicitud({
  personaId, hoy, modo, valoresIniciales, onCancelar, onEnviada,
}: {
  personaId: string;
  hoy: string;
  modo: keyof typeof TITULO_SOLICITUD;
  valoresIniciales?: ValoresSolicitud;
  onCancelar: () => void;
  onEnviada: () => Promise<void>;
}) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  // El id del envío nace con el formulario, para la carpeta del comprobante.
  const [solicitudId] = useState(() => crypto.randomUUID());
  const [institucion, setInstitucion] = useState(valoresIniciales?.institucion ?? "");
  const [beneficiario, setBeneficiario] = useState<"trabajador" | "hijo">(valoresIniciales?.beneficiario ?? "trabajador");
  const [beneficiarioNombre, setBeneficiarioNombre] = useState(valoresIniciales?.beneficiario_nombre ?? "");
  const [costo, setCosto] = useState(valoresIniciales?.costo_declarado !== undefined ? String(valoresIniciales.costo_declarado) : "");
  // Fechas que nacen con valor, nunca vacías (CLAUDE.md, 2026-08-26). El fin
  // nace en el fin del semestre y no en hoy: ver `finDeCicloSugerido`.
  const desdeInicial = valoresIniciales?.vigente_desde ?? hoy;
  const [desde, setDesde] = useState(desdeInicial);
  const [hasta, setHasta] = useState(valoresIniciales?.vigente_hasta ?? finDeCicloSugerido(desdeInicial));
  // Un estudio de menos de un mes se pregunta una vez antes de enviar; tocar
  // cualquiera de las dos fechas vuelve a preguntar.
  const [avisoCorto, setAvisoCorto] = useState<number | null>(null);
  const [cortoConfirmado, setCortoConfirmado] = useState(false);
  const [nota, setNota] = useState(valoresIniciales?.nota ?? "");
  const [archivo, setArchivo] = useState<File | null>(null);
  const [progreso, setProgreso] = useState<number | null>(null);
  const [enviando, setEnviando] = useState(false);
  const [fallo, setFallo] = useState<string | null>(null);

  async function enviar(aceptaCorto = false) {
    setFallo(null);
    if (institucion.trim().length < 3) { setFallo("Escribe qué institución emite el comprobante."); return; }
    const costoNum = Number(costo);
    if (!costoNum || costoNum <= 0) { setFallo("El costo que dice el comprobante tiene que ser mayor que cero."); return; }
    if (beneficiario === "hijo" && beneficiarioNombre.trim().length < 3) {
      setFallo("Escribe a nombre de quién está el comprobante."); return;
    }
    if (!desde || !hasta) { setFallo("Indica desde cuándo y hasta cuándo dura tu estudio."); return; }
    if (hasta < desde) { setFallo("La fecha de fin es anterior a la de inicio."); return; }
    const dias = diasDeVigencia(desde, hasta);
    if (dias < VIGENCIA_CORTA_DIAS && !cortoConfirmado && !aceptaCorto) { setAvisoCorto(dias); return; }

    setAvisoCorto(null);
    setEnviando(true);

    let comprobanteUrl: string | null = null;
    if (archivo) {
      const ext = archivo.name.split(".").pop()?.toLowerCase() ?? "bin";
      const ruta = `educacion/${personaId}/solicitudes/${solicitudId}/comprobante.${ext}`;
      const errorSubida = await subirArchivoConProgreso(supabase, BUCKET_COMPROBANTES, ruta, archivo, setProgreso);
      if (errorSubida) {
        setEnviando(false);
        setFallo(`El comprobante no subió: ${errorSubida}. Puedes enviar la solicitud sin él y adjuntarlo después.`);
        return;
      }
      comprobanteUrl = ruta;
    }

    const { error } = await supabase.rpc("fn_educacion_solicitar", {
      p_institucion: institucion.trim(),
      p_costo_declarado: costoNum,
      p_beneficiario: beneficiario,
      p_beneficiario_nombre: beneficiario === "hijo" ? beneficiarioNombre.trim() : null,
      p_vigente_desde: desde,
      p_vigente_hasta: hasta,
      p_comprobante_url: comprobanteUrl,
      p_nota: nota.trim() || null,
    });
    setEnviando(false);
    if (error) { setFallo(mensajeDeError(error, "enviar la solicitud")); return; }
    await onEnviada();
  }

  return (
    <div className="mt-4 rounded-2xl border border-sand bg-hueso p-4 sm:p-5">
      <h4 className="font-serif text-lg">{TITULO_SOLICITUD[modo]}</h4>

      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <Campo etiqueta="Institución" value={institucion} placeholder="ej. Instituto San Ignacio"
          onChange={(e) => setInstitucion(e.target.value)} disabled={enviando} />
        <CampoSelect etiqueta="¿De quién es el estudio?" value={beneficiario}
          onChange={(e) => setBeneficiario(e.target.value as "trabajador" | "hijo")} disabled={enviando}>
          <option value="trabajador">De la persona misma</option>
          <option value="hijo">De su hijo o hija</option>
        </CampoSelect>
        {beneficiario === "hijo" && (
          <Campo etiqueta="¿A nombre de quién está el comprobante?" value={beneficiarioNombre}
            onChange={(e) => setBeneficiarioNombre(e.target.value)} disabled={enviando} />
        )}
        <Campo etiqueta="Costo que dice el comprobante" type="number" min="0" step="0.01" inputMode="decimal"
          value={costo} onChange={(e) => setCosto(e.target.value)} disabled={enviando} />
        <Campo etiqueta="Se paga desde" type="date" value={desde}
          onChange={(e) => { setDesde(e.target.value); setAvisoCorto(null); setCortoConfirmado(false); }} disabled={enviando} />
        <Campo etiqueta="Hasta cuándo dura tu estudio" type="date" value={hasta}
          onChange={(e) => { setHasta(e.target.value); setAvisoCorto(null); setCortoConfirmado(false); }} disabled={enviando} />
        {/* La etiqueta vieja decía «Hasta cuándo vale», y se leía como «hasta
            cuándo vale ESTE pago»: un apoyo pedido para todo un ciclo quedó
            registrado por once días. */}
        <p className="text-xs text-taupe sm:col-span-2">
          El fin de tu ciclo, semestre o curso, no el de este mes. El apoyo se pide una sola vez; después, cada mes
          subes la constancia de tu pago sin volver a pedirlo.
        </p>
        <div className="flex flex-col gap-1 sm:col-span-2">
          <Campo etiqueta={modo === "renovar" ? "Constancia de tu último pago (opcional)" : "Comprobante (opcional)"}
            type="file" accept="application/pdf,image/jpeg,image/png"
            onChange={(e) => setArchivo(e.target.files?.[0] ?? null)} disabled={enviando} />
          <span className="text-xs text-taupe">
            Puedes adjuntarlo después, desde tu solicitud pendiente. El monto no lo escribes tú: lo calcula Desarrollo Organizacional al aprobar,
            según tu rango.
          </span>
          {progreso !== null && <span className="text-xs text-taupe">Subiendo… {progreso}%</span>}
        </div>
        <div className="sm:col-span-2">
          <AreaTexto rows={2} value={nota} onChange={(e) => setNota(e.target.value)} disabled={enviando}
            placeholder="Nota para Desarrollo Organizacional (opcional)" aria-label="Nota opcional" />
        </div>
      </div>

      {fallo && <p role="alert" className="mt-3 rounded-xl bg-rojo/10 px-3 py-2 text-sm text-rojo-profundo">{fallo}</p>}

      {avisoCorto !== null && (
        <div role="alert" className="mt-3 rounded-xl border border-ambar/40 bg-ambar/10 px-3 py-3 text-sm text-tinta">
          <p>
            Tu apoyo duraría {avisoCorto === 1 ? "un solo día" : `solo ${avisoCorto} días`}: terminaría el {fechaCorta(hasta)}.
            Esa fecha es el fin de tu estudio, no de este mes. Si estudias más tiempo, cámbiala: el día que termina ya no
            se pueden subir constancias nuevas.
          </p>
          <div className="mt-3 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
            <Boton tamano="sm" onClick={() => setAvisoCorto(null)}>Cambiar la fecha</Boton>
            <Boton tamano="sm" variante="secundario" onClick={() => { setCortoConfirmado(true); void enviar(true); }}>
              Sí, mi estudio dura eso: enviar
            </Boton>
          </div>
        </div>
      )}

      <div className="mt-4 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
        <Boton onClick={onCancelar} disabled={enviando}>Cancelar</Boton>
        <Boton variante="primario" cargando={enviando} onClick={() => void enviar()} disabled={avisoCorto !== null}>
          Enviar para revisión
        </Boton>
      </div>
    </div>
  );
}

export default function MiEducacionPage() {
  return (
    <Suspense fallback={<main className="p-6"><Cargando /></main>}>
      <EducacionContenido />
    </Suspense>
  );
}

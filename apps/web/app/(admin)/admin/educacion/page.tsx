"use client";

import { Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Cargando } from "@/components/cargando";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { useToast } from "@/components/toast";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import { abrirArchivoFirmado } from "@/lib/abrir-archivo-firmado";
import {
  ESTADO_CONSTANCIA, ESTADO_ENTREGA, FRECUENCIAS_PAGO, FRECUENCIA_PAGO_LABELS, MOTIVOS_RECHAZO,
  MOTIVO_RECHAZO_LABELS, TIPOS_CONSTANCIA, TIPO_CONSTANCIA_LABELS, TZ_LIMA, hoyLima, problemaDeArchivo,
  puedeVerPlanilla, sugerirProximaFecha,
  type EstadoConstancia, type EstadoEntrega, type FrecuenciaPago, type MotivoRechazo, type TipoConstancia,
} from "@cayla-dynamic/shared";
import {
  BUCKET_COMPROBANTES, elegido, fechaCorta, subirArchivosDeEntrega, urlDeConstancia, type ArchivoElegido,
} from "@/lib/educacion";
import { enDias } from "@/lib/admin/bandeja-urgencia";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { Insignia } from "@/components/ui/insignia";
import { Modal } from "@/components/ui/modal";
import { Drawer } from "@/components/ui/drawer";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";

// ============================================================================
// Educación — los apoyos y las constancias que los sustentan (0450).
// ----------------------------------------------------------------------------
// DOS COSAS QUE ANTES COMPARTÍAN UNA COLUMNA, AHORA SEPARADAS:
//   BENEFICIO   la asignación: institución, monto, vigencia, calendario de pagos.
//   CONSTANCIA  la evidencia de cada pago: su estado, sus archivos, su revisión.
// La columna «Vigencia» decía a la vez «vence en 0 días» (el beneficio) y «pide
// el papel nuevo» (la constancia), en rojo, para una renovación normal.
//
// EL ESTADO NO SE CALCULA ACÁ: lo contesta fn_educacion_situacion, la misma
// que leen el portal, la Bandeja y el contador del menú.
//
// La asignación por educación (art. 19 f) D.S. 001-97-TR) no es remuneración
// SIEMPRE QUE esté sostenida por un comprobante. Aprobar o rechazar una
// constancia NO cambia lo que se paga (decisión «solo alerta», 2026-09-15).
// ============================================================================

interface Situacion {
  familia_id: string;
  asignacion_id: string;
  persona_id: string;
  persona: string;
  sede: string;
  rango: string;
  institucion: string;
  beneficiario: string;
  beneficiario_nombre: string | null;
  monto: number;
  vigente_desde: string;
  vigente_hasta: string;
  vigencia: "futura" | "vigente" | "por_terminar" | "terminada";
  paga: boolean;
  frecuencia_pago: FrecuenciaPago | null;
  proxima_fecha_pago: string | null;
  dias_para_pago: number | null;
  pago_proximo: boolean;
  estado_constancia: EstadoConstancia;
  fecha_pago_constancia: string | null;
  plazo: string | null;
  dias_para_plazo: number | null;
  entrega_id: string | null;
  entrega_estado: EstadoEntrega | null;
  entrega_enviada_at: string | null;
  entrega_archivos: number | null;
  aprobadas: number;
  aviso_fin_id: string | null;
  aviso_fin_motivo: string | null;
}

interface Pendiente {
  id: string;
  familia_id: string;
  persona_id: string;
  fecha_pago: string;
  enviada_at: string;
  archivos: number;
  es_reenvio: boolean;
}

interface Entrega {
  id: string;
  asignacion_id: string;
  fecha_pago: string;
  tipo: TipoConstancia;
  proxima_fecha_pago: string | null;
  nota: string | null;
  estado: EstadoEntrega;
  origen: "colaboradora" | "do" | "migrada";
  enviada_at: string;
  enviada_por: string | null;
  revisada_at: string | null;
  revisada_por: string | null;
  retirada_at: string | null;
  motivo_categoria: MotivoRechazo | null;
  motivo_comentario: string | null;
  reemplaza_a: string | null;
  archivos: { id: string; ruta: string; nombre: string; tipo_mime: string | null; bytes: number | null }[];
}

/** Lo que el formulario de alta/corrección necesita y la situación no trae. */
interface Asignacion {
  id: string;
  persona_id: string;
  persona: string;
  institucion: string;
  costo_declarado: number;
  beneficiario: "trabajador" | "hijo";
  beneficiario_nombre: string | null;
  comprobante_url: string | null;
  vigente_desde: string;
  vigente_hasta: string;
  nota: string | null;
}

interface Candidato { persona_id: string; persona: string; sede: string; rango: string; tope: number | null }

interface Form {
  personaId: string;
  institucion: string;
  costoDeclarado: string;
  beneficiario: "trabajador" | "hijo";
  beneficiarioNombre: string;
  vigenteDesde: string;
  vigenteHasta: string;
  frecuencia: FrecuenciaPago | "";
  primeraFechaPago: string;
  nota: string;
  motivo: string;
}

const COBERTURA = 75;
const FORM_VACIO: Form = {
  personaId: "", institucion: "", costoDeclarado: "", beneficiario: "trabajador", beneficiarioNombre: "",
  vigenteDesde: "", vigenteHasta: "", frecuencia: "", primeraFechaPago: "", nota: "", motivo: "",
};
// Respaldo si la consulta del límite falla (fn_educacion_limite_comprobante, 0154).
const LIMITE_RESPALDO = { bytes: 10 * 1024 * 1024, tipos: "image/jpeg,image/png,application/pdf" };

const soles = (n: number) =>
  `S/ ${Number(n).toLocaleString("es-PE", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

const MESES_CORTOS = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "set", "oct", "nov", "dic"];
/** "2026-09-05" → "set 2026". */
const mesCorto = (iso: string) => `${MESES_CORTOS[Number(iso.slice(5, 7)) - 1]} ${iso.slice(0, 4)}`;

function fechaHora(ts: string | null): string {
  if (!ts) return "—";
  const f = new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA, day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit", hour12: false,
  }).formatToParts(new Date(ts));
  const p = (t: string) => f.find((x) => x.type === t)?.value ?? "";
  return `${p("day")}/${p("month")}/${p("year")} · ${p("hour")}:${p("minute")}`;
}

type Tarjeta = "pendientes" | "por_vencer" | "vencidas" | "rechazadas" | "pagos";

function EducacionContenido() {
  const router = useRouter();
  const params = useSearchParams();
  const persona = usePersonaActual();
  const rol = persona?.rol ?? null;
  const puedeGestionar = puedeVerPlanilla(rol);
  const { avisar } = useToast();
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const hoy = hoyLima();

  const [situaciones, setSituaciones] = useState<Situacion[]>([]);
  const [pendientes, setPendientes] = useState<Pendiente[]>([]);
  const [asignaciones, setAsignaciones] = useState<Map<string, Asignacion>>(new Map());
  const [liquidadas, setLiquidadas] = useState<Set<string>>(new Set());
  const [candidatos, setCandidatos] = useState<Candidato[]>([]);
  const [limite, setLimite] = useState(LIMITE_RESPALDO);
  const [config, setConfig] = useState({ texto: "", plazo: 5, avisoColab: 7, avisoDo: 7 });
  const [cargando, setCargando] = useState(true);
  const [cargaError, setCargaError] = useState<string | null>(null);

  // Filtros
  const [tarjeta, setTarjeta] = useState<Tarjeta | null>(null);
  const [buscar, setBuscar] = useState("");
  const [sede, setSede] = useState("");
  const [estado, setEstado] = useState<EstadoConstancia | "">("");
  const [periodo, setPeriodo] = useState("");
  const [institucion, setInstitucion] = useState("");
  const [vigencia, setVigencia] = useState<"activas" | "terminada" | "todas">("activas");
  const [verLiquidadas, setVerLiquidadas] = useState(false);

  // Panel lateral
  const [abierta, setAbierta] = useState<string | null>(null);
  const [entregaFoco, setEntregaFoco] = useState<string | null>(null);
  const botonQueAbrio = useRef<HTMLElement | null>(null);
  const botonRegistrar = useRef<HTMLElement | null>(null);

  // Formulario de alta/corrección
  const [mostrandoForm, setMostrandoForm] = useState(false);
  const [editandoId, setEditandoId] = useState<string | null>(null);
  const [form, setForm] = useState<Form>(FORM_VACIO);
  const [archivo, setArchivo] = useState<File | null>(null);
  const [guardando, setGuardando] = useState(false);
  const [progreso, setProgreso] = useState<number | null>(null);
  const [saldo, setSaldo] = useState<number | null | undefined>(undefined);
  const [configAbierta, setConfigAbierta] = useState(false);

  const cargar = useCallback(async () => {
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }

    const [sit, pend, lista, cands, lim, pf, cfg] = await Promise.all([
      supabase.rpc("fn_educacion_situacion"),
      supabase.rpc("fn_educacion_entregas_pendientes"),
      supabase.rpc("fn_educacion_listar"),
      supabase.rpc("fn_educacion_candidatos"),
      supabase.rpc("fn_educacion_limite_comprobante"),
      supabase.rpc("fn_personas_funciones"),
      supabase.from("configuracion").select("clave, valor").like("clave", "educacion_%"),
    ]);
    setSituaciones((sit.data ?? []) as unknown as Situacion[]);
    setPendientes((pend.data ?? []) as unknown as Pendiente[]);
    setAsignaciones(new Map(((lista.data ?? []) as unknown as Asignacion[]).map((a) => [a.id, a])));
    setCandidatos((cands.data ?? []) as unknown as Candidato[]);
    // Quién ya se liquidó (0421/0422): se ocultan por defecto. Si falla, no se oculta a nadie.
    setLiquidadas(new Set(((pf.data ?? []) as unknown as { persona_id: string; liquidada: boolean }[])
      .filter((f) => f.liquidada).map((f) => f.persona_id)));
    const l = (lim.data as { limite_bytes: number; tipos: string[] }[] | null)?.[0];
    if (l) setLimite({ bytes: Number(l.limite_bytes), tipos: l.tipos.join(",") });
    const c = new Map(((cfg.data ?? []) as { clave: string; valor: unknown }[]).map((x) => [x.clave, x.valor]));
    setConfig({
      texto: typeof c.get("educacion_constancias_validas") === "string" ? (c.get("educacion_constancias_validas") as string) : "",
      plazo: Number(c.get("educacion_dias_plazo_antes_cierre") ?? 5),
      avisoColab: Number(c.get("educacion_dias_aviso_colaboradora") ?? 7),
      avisoDo: Number(c.get("educacion_dias_aviso_do") ?? 7),
    });
    setCargaError(sit.error ? mensajeDeError(sit.error, "cargar educación") : null);
    setCargando(false);
  }, [supabase, router]);

  // eslint-disable-next-line react-hooks/set-state-in-effect -- cargar al montar, mismo patrón que el resto del panel.
  useEffect(() => { void cargar(); }, [cargar]);

  // El enlace de la Bandeja: ?entrega=<id> abre el panel de esa entrega; ?familia=<id>, el del estudio.
  const entregaPedida = params.get("entrega");
  const familiaPedida = params.get("familia");
  // ?persona=<id> (ADR 0003): se llega desde otra pantalla a una persona. Manda
  // sobre los demás filtros —si su estudio ya terminó o ya se liquidó, «vigentes»
  // la escondería justo cuando alguien vino a verla.
  const personaPedida = params.get("persona");
  useEffect(() => {
    if (cargando) return;
    if (entregaPedida) {
      const p = pendientes.find((x) => x.id === entregaPedida);
      if (p) {
        // eslint-disable-next-line react-hooks/set-state-in-effect -- abrir el panel que pide la URL, una vez cargados los datos.
        setAbierta(p.familia_id); setEntregaFoco(p.id); return;
      }
      // Ya no está pendiente (alguien la revisó): se busca su estudio igual.
      void supabase.from("educacion_entregas").select("asignaciones_educacion(familia_id)").eq("id", entregaPedida).maybeSingle()
        .then(({ data }) => {
          const familia = (data?.asignaciones_educacion as { familia_id: string } | null)?.familia_id;
          if (familia) { setAbierta(familia); setEntregaFoco(entregaPedida); }
        });
    } else if (familiaPedida) {
      setAbierta(familiaPedida);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cargando, entregaPedida, familiaPedida]);

  // ── Resumen accionable y filtros ─────────────────────────────────────────
  const conteo = {
    pendientes: pendientes.length,
    por_vencer: situaciones.filter((s) => s.estado_constancia === "por_vencer").length,
    vencidas: situaciones.filter((s) => s.estado_constancia === "vencida").length,
    rechazadas: situaciones.filter((s) => s.estado_constancia === "rechazada").length,
    pagos: situaciones.filter((s) => s.pago_proximo).length,
    sinCalendario: situaciones.filter((s) => s.estado_constancia === "sin_calendario" && s.vigencia !== "terminada").length,
  };
  const familiasConPendiente = new Set(pendientes.map((p) => p.familia_id));

  // Nunca una lista escrita a mano de sedes (regla #3): salen de los datos.
  const sedes = useMemo(() => Array.from(new Set(situaciones.map((s) => s.sede))).sort(), [situaciones]);
  const instituciones = useMemo(() => Array.from(new Set(situaciones.map((s) => s.institucion))).sort(), [situaciones]);
  const periodos = useMemo(
    () => Array.from(new Set(situaciones.map((s) => s.fecha_pago_constancia?.slice(0, 7)).filter(Boolean) as string[])).sort().reverse(),
    [situaciones],
  );

  const visibles = situaciones.filter((s) => {
    if (personaPedida) return s.persona_id === personaPedida;
    if (!verLiquidadas && liquidadas.has(s.persona_id)) return false;
    if (tarjeta === "pendientes" && !familiasConPendiente.has(s.familia_id)) return false;
    if (tarjeta === "por_vencer" && s.estado_constancia !== "por_vencer") return false;
    if (tarjeta === "vencidas" && s.estado_constancia !== "vencida") return false;
    if (tarjeta === "rechazadas" && s.estado_constancia !== "rechazada") return false;
    if (tarjeta === "pagos" && !s.pago_proximo) return false;
    if (buscar.trim() && !s.persona.toLowerCase().includes(buscar.trim().toLowerCase())) return false;
    if (sede && s.sede !== sede) return false;
    if (estado && s.estado_constancia !== estado) return false;
    if (periodo && s.fecha_pago_constancia?.slice(0, 7) !== periodo) return false;
    if (institucion && s.institucion !== institucion) return false;
    if (vigencia === "activas" && s.vigencia === "terminada") return false;
    if (vigencia === "terminada" && s.vigencia !== "terminada") return false;
    return true;
  });
  // Lo que pide acción primero; después, por persona.
  const PRIORIDAD: Record<EstadoConstancia, number> = {
    pendiente_revision: 0, vencida: 1, por_vencer: 2, rechazada: 3, falta_enviar: 4, sin_calendario: 5, al_dia: 6,
  };
  visibles.sort((a, b) => PRIORIDAD[a.estado_constancia] - PRIORIDAD[b.estado_constancia] || a.persona.localeCompare(b.persona));

  const hayFiltros = tarjeta || buscar || sede || estado || periodo || institucion || vigencia !== "activas" || verLiquidadas;
  function limpiarFiltros() {
    setTarjeta(null); setBuscar(""); setSede(""); setEstado(""); setPeriodo(""); setInstitucion("");
    setVigencia("activas"); setVerLiquidadas(false);
  }

  const totalMensual = situaciones.filter((s) => s.paga && s.vigente_desde <= hoy).reduce((t, s) => t + Number(s.monto), 0);

  // ── Formulario de alta/corrección (cuerpo de la pantalla anterior) ───────
  const candidato = candidatos.find((c) => c.persona_id === form.personaId) ?? null;
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- sin persona o fecha no hay saldo que pedir: se borra el anterior.
    if (!form.personaId || !form.vigenteDesde) { setSaldo(undefined); return; }
    let vivo = true;
    void supabase.rpc("fn_educacion_saldo", {
      p_persona_id: form.personaId, p_desde: form.vigenteDesde,
      p_hasta: form.vigenteHasta || form.vigenteDesde, p_excluir: editandoId,
    }).then(({ data, error }) => { if (vivo) setSaldo(error ? undefined : (data as number | null)); });
    return () => { vivo = false; };
  }, [supabase, form.personaId, form.vigenteDesde, form.vigenteHasta, editandoId]);

  const costo = Number(form.costoDeclarado) || 0;
  const delPapel = costo > 0 ? Math.round(costo * COBERTURA) / 100 : null;
  const techoLibre = saldo !== undefined ? saldo : (candidato?.tope ?? null);
  const monto = delPapel === null ? 0 : techoLibre === null ? delPapel : Math.min(delPapel, techoLibre);

  function empezarAlta() {
    setEditandoId(null); setArchivo(null); setMostrandoForm(true);
    // Las fechas que bloquean el envío nacen con valor (CLAUDE.md, 2026-08-26).
    const inicioMes = hoy.slice(0, 8) + "01";
    setForm({ ...FORM_VACIO, vigenteDesde: inicioMes, vigenteHasta: inicioMes });
  }
  function empezarEdicion(asignacionId: string) {
    const a = asignaciones.get(asignacionId);
    const s = situaciones.find((x) => x.asignacion_id === asignacionId);
    if (!a) { avisar("error", "No se encontró la asignación para editarla. Recarga la pantalla."); return; }
    setAbierta(null);
    // Se abre desde el otro cajón (que ya se está cerrando): no hay un botón
    // visible al que devolverle el foco, así que no se hereda el de "+ Registrar".
    botonRegistrar.current = null;
    setEditandoId(a.id); setArchivo(null); setMostrandoForm(true);
    setForm({
      personaId: a.persona_id, institucion: a.institucion, costoDeclarado: String(a.costo_declarado),
      beneficiario: a.beneficiario, beneficiarioNombre: a.beneficiario_nombre ?? "",
      vigenteDesde: a.vigente_desde, vigenteHasta: a.vigente_hasta,
      frecuencia: s?.frecuencia_pago ?? "", primeraFechaPago: s?.proxima_fecha_pago ?? "",
      nota: a.nota ?? "", motivo: "",
    });
  }
  function cancelarForm() { setMostrandoForm(false); setEditandoId(null); setForm(FORM_VACIO); setArchivo(null); }

  async function guardar() {
    const inst = form.institucion.trim();
    if (!form.personaId) { avisar("error", "Elige de quién es la asignación."); return; }
    if (inst.length < 3) { avisar("error", "Escribe qué institución emite el comprobante."); return; }
    if (costo <= 0) { avisar("error", "El costo que dice el comprobante tiene que ser mayor que cero."); return; }
    if (monto <= 0) { avisar("error", "No queda techo libre en esas fechas: lo que ya tiene vigente agota el tope de su rango."); return; }
    if (form.beneficiario === "hijo" && form.beneficiarioNombre.trim().length < 3) {
      avisar("error", "Si el comprobante es de un hijo o hija, escribe a nombre de quién está."); return;
    }
    if (!form.vigenteDesde || !form.vigenteHasta) { avisar("error", "Indica desde y hasta cuándo se paga."); return; }
    if (form.vigenteHasta < form.vigenteDesde) { avisar("error", "La fecha de fin es anterior a la de inicio."); return; }
    if (editandoId && form.motivo.trim().length < 3) { avisar("error", "Escribe por qué se corrige. Queda registrado."); return; }

    setGuardando(true);
    const args = {
      p_persona_id: form.personaId, p_institucion: inst, p_costo_declarado: costo, p_beneficiario: form.beneficiario,
      p_vigente_desde: form.vigenteDesde, p_vigente_hasta: form.vigenteHasta,
      p_beneficiario_nombre: form.beneficiarioNombre.trim() || null, p_nota: form.nota.trim() || null,
    };
    const { data: id, error } = await supabase.rpc("fn_educacion_registrar", {
      ...args, p_id: editandoId, p_motivo: form.motivo.trim() || null,
    });
    if (error) { setGuardando(false); avisar("error", mensajeDeError(error, "guardar")); return; }

    if (archivo) {
      const ext = archivo.name.split(".").pop()?.toLowerCase() ?? "bin";
      const ruta = `educacion/${form.personaId}/${id}-${Date.now()}.${ext}`;
      setProgreso(0);
      const errorSubida = await subirArchivoConProgreso(supabase, BUCKET_COMPROBANTES, ruta, archivo, setProgreso);
      setProgreso(null);
      if (errorSubida) {
        setGuardando(false);
        avisar("error", `La asignación se guardó, pero el comprobante no subió (${errorSubida}). Cárgalo desde su panel.`);
        await cargar(); return;
      }
      const { error: e3 } = await supabase.rpc("fn_educacion_registrar", {
        ...args, p_comprobante_url: ruta, p_id: id as string, p_motivo: "Se enlaza el comprobante recién subido",
      });
      if (e3) { setGuardando(false); avisar("error", `El comprobante subió pero no quedó enlazado (${mensajeDeError(e3)}).`); await cargar(); return; }
    }

    // El calendario de pagos va aparte: no mueve plata y no debe abrir vigencia nueva.
    if (form.frecuencia || form.primeraFechaPago) {
      const { error: eCal } = await supabase.rpc("fn_educacion_fijar_calendario", {
        p_asignacion_id: id as string, p_frecuencia: form.frecuencia || null, p_proxima: form.primeraFechaPago || null,
      });
      if (eCal) avisar("error", `Se guardó, pero no el calendario de pagos: ${mensajeDeError(eCal)}`);
    }

    setGuardando(false);
    cancelarForm();
    await cargar();
    avisar("ok", editandoId ? "Cambios guardados." : "Asignación registrada. Entra en el próximo cálculo de planilla si tiene su comprobante.");
  }

  const formulario = (
    <div className="grid gap-3 sm:grid-cols-2">
      <div className="sm:col-span-2">
        <CampoSelect etiqueta="¿De quién es?" value={form.personaId} disabled={editandoId !== null}
          onChange={(e) => setForm({ ...form, personaId: e.target.value })}>
          <option value="">— elige a la persona —</option>
          {candidatos.map((c) => <option key={c.persona_id} value={c.persona_id}>{c.persona} · {c.sede} · rango {c.rango}</option>)}
        </CampoSelect>
      </div>
      <Campo etiqueta="Institución" value={form.institucion} placeholder="ej. Instituto San Ignacio"
        onChange={(e) => setForm({ ...form, institucion: e.target.value })} />
      <CampoSelect etiqueta="¿De quién es el estudio?" value={form.beneficiario}
        onChange={(e) => setForm({ ...form, beneficiario: e.target.value as "trabajador" | "hijo" })}>
        <option value="trabajador">De la persona misma</option>
        <option value="hijo">De su hijo o hija</option>
      </CampoSelect>
      {form.beneficiario === "hijo" && (
        <Campo etiqueta="¿A nombre de quién está el comprobante?" value={form.beneficiarioNombre}
          onChange={(e) => setForm({ ...form, beneficiarioNombre: e.target.value })} />
      )}
      <div className="flex flex-col gap-1">
        <Campo etiqueta="Costo que dice el comprobante" type="number" min="0" step="0.01" inputMode="decimal"
          value={form.costoDeclarado} onChange={(e) => setForm({ ...form, costoDeclarado: e.target.value })} />
      </div>
      <div className="flex flex-col gap-1 text-sm">
        Apoyo mensual
        <div className="rounded-lg border border-dashed bg-hueso px-3 py-2 font-medium">{costo > 0 ? soles(monto) : "—"}</div>
        <span className="text-xs text-taupe">
          {costo <= 0 ? "Se calcula solo: el 75 % del comprobante, sin pasar el techo que le queda en su rango."
            : delPapel !== null && techoLibre !== null && techoLibre < delPapel
              ? `Manda el techo de su rango: el ${COBERTURA} % del comprobante daría ${soles(delPapel)}.`
              : `Es el ${COBERTURA} % de ${soles(costo)}.`}
        </span>
      </div>
      <Campo etiqueta="Se paga desde" type="date" value={form.vigenteDesde}
        onChange={(e) => setForm({ ...form, vigenteDesde: e.target.value })} />
      <Campo etiqueta="Hasta cuándo vale" type="date" value={form.vigenteHasta}
        onChange={(e) => setForm({ ...form, vigenteHasta: e.target.value })} />
      <CampoSelect etiqueta="¿Cada cuánto paga a su institución?" value={form.frecuencia}
        onChange={(e) => setForm({ ...form, frecuencia: e.target.value as FrecuenciaPago | "" })}>
        <option value="">— sin definir —</option>
        {FRECUENCIAS_PAGO.map((f) => <option key={f} value={f}>{FRECUENCIA_PAGO_LABELS[f]}</option>)}
      </CampoSelect>
      <div className="flex flex-col gap-1">
        <Campo etiqueta="Próxima fecha de pago" type="date" value={form.primeraFechaPago}
          onChange={(e) => setForm({ ...form, primeraFechaPago: e.target.value })} />
        <span className="text-xs text-taupe">Opcional. Con ella el sistema avisa antes del pago y pide la constancia después.</span>
      </div>
      <div className="flex flex-col gap-1 sm:col-span-2">
        <Campo etiqueta="Comprobante inicial (opcional)" type="file" accept={limite.tipos}
          onChange={(e) => {
            const f = e.target.files?.[0] ?? null;
            if (f && f.size > limite.bytes) { avisar("error", `«${f.name}» pesa más de lo permitido.`); return; }
            setArchivo(f);
          }} />
        <span className="text-xs text-taupe">
          Queda como constancia aprobada, cargada por ti. Sin ningún comprobante, <strong>no se paga</strong>: es lo que
          hace que este monto no sea remuneración.
        </span>
        {progreso !== null && <span className="text-xs text-taupe">Subiendo… {progreso}%</span>}
      </div>
      {editandoId && (
        <div className="sm:col-span-2">
          <Campo etiqueta="¿Por qué se corrige?" value={form.motivo} placeholder="ej. el comprobante decía 180 y se registró 200"
            onChange={(e) => setForm({ ...form, motivo: e.target.value })} />
        </div>
      )}
      <div className="sm:col-span-2">
        <Campo etiqueta="Nota (opcional)" value={form.nota} onChange={(e) => setForm({ ...form, nota: e.target.value })} />
      </div>
      <div className="flex gap-3 sm:col-span-2">
        <Boton variante="primario" cargando={guardando} onClick={() => void guardar()}>
          {editandoId ? "Guardar cambios" : "Registrar asignación"}
        </Boton>
        <Boton onClick={cancelarForm} disabled={guardando}>Cancelar</Boton>
      </div>
    </div>
  );

  const seleccion = abierta ? situaciones.find((s) => s.familia_id === abierta) ?? null : null;

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-4 sm:p-6">
        <CabeceraPagina
          titulo="Educación"
          accion={puedeGestionar ? (
            <Boton variante="primario"
              onClick={(e) => { botonRegistrar.current = e.currentTarget; empezarAlta(); }}>
              + Registrar asignación
            </Boton>
          ) : undefined}
        />

        {rol === null ? <Cargando /> : !puedeGestionar ? (
          <div className="max-w-2xl rounded-lg bg-ambar/15 px-4 py-3 text-sm text-ambar">
            Solo Desarrollo Organizacional gestiona los apoyos educativos.
          </div>
        ) : (
          <>
            <p className="mb-5 max-w-3xl text-sm text-taupe">
              Gestiona los apoyos educativos y las constancias que los sustentan. Aprobar o rechazar una constancia no
              cambia lo que se paga: es el respaldo de que el apoyo no es remuneración.
            </p>

            {cargaError && (
              <div className="mb-4 max-w-3xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo-profundo">
                {cargaError} <Boton variante="enlace" onClick={() => void cargar()}>Reintentar</Boton>
              </div>
            )}

            {cargando ? <Cargando /> : (
              <>
                {personaPedida && (
                  <div className="mb-4 flex flex-wrap items-center gap-2 rounded-xl border border-sand bg-papel px-3 py-2 text-sm">
                    <span>
                      Mostrando solo los estudios de{" "}
                      <strong>{situaciones.find((s) => s.persona_id === personaPedida)?.persona ?? "esta persona"}</strong>, vigentes o no.
                    </span>
                    <Boton variante="enlace" onClick={() => router.replace("/admin/educacion")}>Ver todas</Boton>
                  </div>
                )}

                {/* ── RESUMEN: solo lo accionable, y cada tarjeta filtra ────────── */}
                <div className="mb-4 grid grid-cols-2 gap-3 lg:grid-cols-5">
                  {([
                    ["pendientes", "Pendientes de revisión", conteo.pendientes, "informativo"],
                    ["vencidas", "Constancias vencidas", conteo.vencidas, "alerta"],
                    ["por_vencer", "Por vencer", conteo.por_vencer, "advertencia"],
                    ["rechazadas", "Rechazadas", conteo.rechazadas, "alerta"],
                    ["pagos", `Pagos en ${config.avisoDo} días`, conteo.pagos, "neutral"],
                  ] as const).map(([clave, etiqueta, n, tono]) => (
                    <button key={clave} type="button" aria-pressed={tarjeta === clave}
                      onClick={() => setTarjeta(tarjeta === clave ? null : clave)}
                      className={`rounded-2xl border p-4 text-left transition-colors ${tarjeta === clave ? "border-tinta bg-papel" : "border-sand bg-papel hover:border-taupe"}`}>
                      <span className="block text-xs uppercase tracking-wide text-taupe">{etiqueta}</span>
                      <span className="mt-1 flex items-center gap-2">
                        <span className="font-serif text-3xl tabular-nums">{n}</span>
                        {n > 0 && tono !== "neutral" && <Insignia variante={tono} tamano="sm">{tono === "alerta" ? "atender" : tono === "advertencia" ? "pronto" : "revisar"}</Insignia>}
                      </span>
                    </button>
                  ))}
                </div>

                <p className="mb-4 text-xs text-taupe">
                  {situaciones.filter((s) => s.paga && s.vigente_desde <= hoy).length} apoyos pagándose · suman {soles(totalMensual)} al mes
                  {conteo.sinCalendario > 0 && (
                    <> · <Boton variante="enlace" className="text-xs" onClick={() => { limpiarFiltros(); setEstado("sin_calendario"); }}>
                      {conteo.sinCalendario} sin calendario de pagos
                    </Boton></>
                  )}
                  {" · "}
                  <Boton variante="enlace" className="text-xs" onClick={() => setConfigAbierta(true)}>Texto y plazos de las constancias</Boton>
                </p>

                {/* ── FILTROS ─────────────────────────────────────────────────── */}
                <div className="mb-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-6">
                  <div className="sm:col-span-2 lg:col-span-2">
                    <Campo etiqueta="Buscar persona" value={buscar} onChange={(e) => setBuscar(e.target.value)} placeholder="Nombre o apellido" />
                  </div>
                  <CampoSelect etiqueta="Sede" value={sede} onChange={(e) => setSede(e.target.value)}>
                    <option value="">Todas</option>
                    {sedes.map((s) => <option key={s} value={s}>{s}</option>)}
                  </CampoSelect>
                  <CampoSelect etiqueta="Estado de la constancia" value={estado} onChange={(e) => setEstado(e.target.value as EstadoConstancia | "")}>
                    <option value="">Todos</option>
                    {(Object.keys(ESTADO_CONSTANCIA) as EstadoConstancia[]).map((k) => <option key={k} value={k}>{ESTADO_CONSTANCIA[k].etiqueta}</option>)}
                  </CampoSelect>
                  <CampoSelect etiqueta="Pago" value={periodo} onChange={(e) => setPeriodo(e.target.value)}>
                    <option value="">Todos</option>
                    {periodos.map((p) => <option key={p} value={p}>{mesCorto(`${p}-01`)}</option>)}
                  </CampoSelect>
                  <CampoSelect etiqueta="Institución" value={institucion} onChange={(e) => setInstitucion(e.target.value)}>
                    <option value="">Todas</option>
                    {instituciones.map((i) => <option key={i} value={i}>{i}</option>)}
                  </CampoSelect>
                  <CampoSelect etiqueta="Beneficio" value={vigencia} onChange={(e) => setVigencia(e.target.value as typeof vigencia)}>
                    <option value="activas">Vigentes y por empezar</option>
                    <option value="terminada">Terminados</option>
                    <option value="todas">Todos</option>
                  </CampoSelect>
                  <label className="flex items-end gap-2 pb-2 text-sm">
                    <input type="checkbox" className="size-4 accent-tinta" checked={verLiquidadas} onChange={(e) => setVerLiquidadas(e.target.checked)} />
                    Incluir personas ya liquidadas
                  </label>
                  {hayFiltros && (
                    <div className="flex items-end pb-2">
                      <Boton variante="enlace" onClick={limpiarFiltros}>Limpiar filtros</Boton>
                    </div>
                  )}
                </div>

                {situaciones.length === 0 ? (
                  <div className="max-w-3xl rounded-2xl border border-sand bg-papel px-5 py-6 text-sm text-taupe">
                    Todavía no hay ningún apoyo educativo registrado.
                  </div>
                ) : visibles.length === 0 ? (
                  <div className="rounded-2xl border border-sand bg-papel px-5 py-6 text-sm text-taupe">
                    Nada coincide con estos filtros. <Boton variante="enlace" onClick={limpiarFiltros}>Limpiar filtros</Boton>
                  </div>
                ) : (
                  <>
                    {/* ── DESKTOP Y TABLET: tabla ───────────────────────────────── */}
                    <div className="hidden overflow-x-auto rounded-2xl border border-sand md:block">
                      <table className="w-full text-sm">
                        <thead className="bg-hueso text-left text-xs uppercase tracking-wide text-taupe">
                          <tr>
                            <th className="px-4 py-2 font-medium" rowSpan={2}>Persona</th>
                            <th className="border-l border-sand px-4 pt-2 font-medium" colSpan={3}>Beneficio</th>
                            <th className="border-l border-sand px-4 pt-2 font-medium" colSpan={3}>Constancia</th>
                            <th className="px-4 py-2" rowSpan={2}><span className="sr-only">Acción</span></th>
                          </tr>
                          <tr className="normal-case tracking-normal">
                            <th className="border-l border-sand px-4 pb-2 font-normal">Institución</th>
                            <th className="px-4 pb-2 font-normal">Apoyo mensual</th>
                            <th className="hidden px-4 pb-2 font-normal lg:table-cell">Vigencia</th>
                            <th className="border-l border-sand px-4 pb-2 font-normal">Pago</th>
                            <th className="hidden px-4 pb-2 font-normal lg:table-cell">Archivos</th>
                            <th className="px-4 pb-2 font-normal">Estado</th>
                          </tr>
                        </thead>
                        <tbody>
                          {visibles.map((s) => {
                            const est = ESTADO_CONSTANCIA[s.estado_constancia];
                            const pend = pendientes.filter((p) => p.familia_id === s.familia_id);
                            return (
                              <tr key={s.familia_id} className={`border-t border-sand ${s.vigencia === "terminada" ? "text-taupe" : ""}`}>
                                <td className="px-4 py-3">
                                  <span className="font-medium">{s.persona}</span>
                                  <span className="block text-xs text-taupe">{s.sede} · {s.rango}</span>
                                </td>
                                <td className="border-l border-sand px-4 py-3">
                                  {s.institucion}
                                  <span className="block text-xs text-taupe">
                                    {s.beneficiario === "hijo" ? (s.beneficiario_nombre ?? "su hijo/a") : "la persona misma"}
                                  </span>
                                </td>
                                <td className="px-4 py-3 tabular-nums">
                                  {soles(s.monto)}
                                  {!s.paga && s.vigencia !== "terminada" && <span className="block text-xs text-taupe">no se paga: sin comprobante</span>}
                                </td>
                                <td className="hidden px-4 py-3 text-xs lg:table-cell">
                                  Desde {fechaCorta(s.vigente_desde)}
                                  <span className={`block ${s.vigencia === "por_terminar" ? "text-ambar" : "text-taupe"}`}>
                                    {s.vigencia === "terminada" ? `terminó el ${fechaCorta(s.vigente_hasta)}` : `hasta ${fechaCorta(s.vigente_hasta)}`}
                                  </span>
                                </td>
                                <td className="border-l border-sand px-4 py-3 text-xs">
                                  {s.fecha_pago_constancia ? fechaCorta(s.fecha_pago_constancia) : "—"}
                                  {s.plazo && s.dias_para_plazo !== null && s.estado_constancia !== "al_dia" && s.estado_constancia !== "pendiente_revision" && (
                                    <span className="block text-taupe">{enDias(s.dias_para_plazo, { futuro: "vence", pasado: "venció" })}</span>
                                  )}
                                  {s.pago_proximo && s.dias_para_pago !== null && (
                                    <span className="block text-taupe">{enDias(s.dias_para_pago, { futuro: "Paga", pasado: "Pagó" })}</span>
                                  )}
                                </td>
                                <td className="hidden px-4 py-3 text-xs lg:table-cell">
                                  {pend.length > 0
                                    ? `${pend.reduce((t, p) => t + p.archivos, 0)} por revisar`
                                    : `${s.aprobadas} aprobada${s.aprobadas === 1 ? "" : "s"}`}
                                </td>
                                <td className="px-4 py-3">
                                  <Insignia variante={est.tono}>{est.etiqueta}</Insignia>
                                  {s.aviso_fin_id && <span className="mt-1 block text-xs text-ambar">avisó que deja de pagar</span>}
                                </td>
                                <td className="px-4 py-3 text-right">
                                  <Boton variante={pend.length > 0 ? "primario" : "secundario"} tamano="sm"
                                    onClick={(e) => { botonQueAbrio.current = e.currentTarget; setEntregaFoco(pend[0]?.id ?? null); setAbierta(s.familia_id); }}>
                                    {pend.length > 0 ? "Revisar →" : "Ver →"}
                                  </Boton>
                                </td>
                              </tr>
                            );
                          })}
                        </tbody>
                      </table>
                    </div>

                    {/* ── CELULAR: tarjetas ─────────────────────────────────────── */}
                    <ul className="flex flex-col gap-3 md:hidden">
                      {visibles.map((s) => {
                        const est = ESTADO_CONSTANCIA[s.estado_constancia];
                        const pend = pendientes.filter((p) => p.familia_id === s.familia_id);
                        return (
                          <li key={s.familia_id} className="rounded-2xl border border-sand bg-papel p-4 text-sm">
                            <div className="flex items-start justify-between gap-2">
                              <div>
                                <p className="font-medium">{s.persona}</p>
                                <p className="text-xs text-taupe">{s.sede} · {s.institucion}</p>
                              </div>
                              <Insignia variante={est.tono}>{est.etiqueta}</Insignia>
                            </div>
                            <dl className="mt-3 grid grid-cols-2 gap-2 text-xs">
                              <div><dt className="text-taupe">Apoyo mensual</dt><dd className="tabular-nums">{soles(s.monto)}</dd></div>
                              <div><dt className="text-taupe">Pago</dt><dd>{s.fecha_pago_constancia ? fechaCorta(s.fecha_pago_constancia) : "—"}</dd></div>
                            </dl>
                            <Boton variante={pend.length > 0 ? "primario" : "secundario"} className="mt-3 w-full"
                              onClick={(e) => { botonQueAbrio.current = e.currentTarget; setEntregaFoco(pend[0]?.id ?? null); setAbierta(s.familia_id); }}>
                              {pend.length > 0 ? "Revisar constancia →" : "Ver →"}
                            </Boton>
                          </li>
                        );
                      })}
                    </ul>
                  </>
                )}
              </>
            )}
          </>
        )}

        <Drawer abierto={seleccion !== null} onCerrar={() => { setAbierta(null); setEntregaFoco(null); }}
          titulo={seleccion ? `${seleccion.persona} · ${seleccion.institucion}` : undefined}
          volverElFocoA={botonQueAbrio} ancho="amplio">
          {seleccion && (
            <PanelEstudio
              key={seleccion.familia_id}
              s={seleccion}
              entregaFoco={entregaFoco}
              miPersonaId={persona?.id ?? null}
              onEditar={() => empezarEdicion(seleccion.asignacion_id)}
              onCambio={async (texto) => { avisar("ok", texto); await cargar(); }}
              onError={(texto) => avisar("error", texto)}
            />
          )}
        </Drawer>

        <Drawer abierto={mostrandoForm} onCerrar={cancelarForm} bloqueado={guardando}
          titulo={editandoId ? "Corregir asignación" : "Registrar asignación"}
          volverElFocoA={botonRegistrar} ancho="amplio">
          {formulario}
        </Drawer>

        <ConfigConstancias abierto={configAbierta} config={config} onCerrar={() => setConfigAbierta(false)}
          onGuardado={async () => { setConfigAbierta(false); avisar("ok", "Configuración guardada."); await cargar(); }}
          onError={(t) => avisar("error", t)} />
      </main>
    </div>
  );
}

// ── EL PANEL DE UN ESTUDIO: beneficio, constancia por revisar, historial ────
function PanelEstudio({
  s, entregaFoco, miPersonaId, onEditar, onCambio, onError,
}: {
  s: Situacion;
  entregaFoco: string | null;
  miPersonaId: string | null;
  onEditar: () => void;
  onCambio: (texto: string) => Promise<void>;
  onError: (texto: string) => void;
}) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const [entregas, setEntregas] = useState<Entrega[] | null>(null);
  const [aprobando, setAprobando] = useState<Entrega | null>(null);
  const [rechazando, setRechazando] = useState<Entrega | null>(null);
  const [trabajando, setTrabajando] = useState(false);
  const [categoria, setCategoria] = useState<MotivoRechazo | "">("");
  const [comentario, setComentario] = useState("");
  const [frecuencia, setFrecuencia] = useState<FrecuenciaPago | "">(s.frecuencia_pago ?? "");
  const [proxima, setProxima] = useState(s.proxima_fecha_pago ?? "");
  const [cargandoAlNombre, setCargandoAlNombre] = useState(false);
  const [cerrando, setCerrando] = useState(false);
  const [hastaCierre, setHastaCierre] = useState(hoyLima());

  const traer = useCallback(async () => {
    const { data, error } = await supabase.rpc("fn_educacion_entregas", { p_familia_id: s.familia_id });
    if (error) { onError(mensajeDeError(error, "leer las constancias")); setEntregas([]); return; }
    setEntregas((data ?? []) as unknown as Entrega[]);
  }, [supabase, s.familia_id, onError]);
  // eslint-disable-next-line react-hooks/set-state-in-effect -- pedir el historial al abrir el panel.
  useEffect(() => { void traer(); }, [traer]);

  const pendientesDe = (entregas ?? []).filter((e) => e.estado === "pendiente");
  const enRevision = pendientesDe.find((e) => e.id === entregaFoco) ?? pendientesDe[0] ?? null;
  const esPropia = miPersonaId !== null && miPersonaId === s.persona_id;

  async function aprobar() {
    if (!aprobando) return;
    setTrabajando(true);
    const { error } = await supabase.rpc("fn_educacion_resolver_entrega", { p_id: aprobando.id, p_aprobar: true });
    setTrabajando(false);
    if (error) { onError(mensajeDeError(error, "aprobar la constancia")); return; }
    setAprobando(null);
    await traer();
    await onCambio(`Constancia de ${s.persona} aprobada.`);
  }

  async function rechazar() {
    if (!rechazando) return;
    if (!categoria) { onError("Elige el motivo del rechazo."); return; }
    if (comentario.trim().length < 3) { onError("Escribe qué tiene que corregir: la integrante lo va a leer."); return; }
    setTrabajando(true);
    const { error } = await supabase.rpc("fn_educacion_resolver_entrega", {
      p_id: rechazando.id, p_aprobar: false, p_categoria: categoria, p_comentario: comentario.trim(),
    });
    setTrabajando(false);
    if (error) { onError(mensajeDeError(error, "rechazar la constancia")); return; }
    setRechazando(null); setCategoria(""); setComentario("");
    await traer();
    await onCambio(`Constancia de ${s.persona} rechazada. Le llega el motivo en su Bandeja.`);
  }

  async function guardarCalendario() {
    setTrabajando(true);
    const { error } = await supabase.rpc("fn_educacion_fijar_calendario", {
      p_asignacion_id: s.asignacion_id, p_frecuencia: frecuencia || null, p_proxima: proxima || null,
    });
    setTrabajando(false);
    if (error) { onError(mensajeDeError(error, "guardar el calendario")); return; }
    await onCambio("Calendario de pagos guardado.");
  }

  async function atenderAviso() {
    if (!s.aviso_fin_id) return;
    setTrabajando(true);
    const { error } = await supabase.rpc("fn_educacion_atender_aviso_fin", { p_id: s.aviso_fin_id, p_respuesta: null });
    setTrabajando(false);
    if (error) { onError(mensajeDeError(error, "marcar el aviso")); return; }
    await onCambio("Aviso marcado como atendido.");
  }

  async function cerrarAsignacion() {
    setTrabajando(true);
    const { error } = await supabase.rpc("fn_educacion_cerrar", {
      p_id: s.asignacion_id, p_hasta: hastaCierre, p_motivo: `Cierre desde Educación (${s.institucion})`,
    });
    setTrabajando(false);
    if (error) { onError(mensajeDeError(error)); return; }
    setCerrando(false);
    if (s.aviso_fin_id) await supabase.rpc("fn_educacion_atender_aviso_fin", { p_id: s.aviso_fin_id, p_respuesta: `Cerrada al ${fechaCorta(hastaCierre)}` });
    await onCambio(`Cerrada al ${fechaCorta(hastaCierre)}. Deja de pagarse en los periodos posteriores.`);
  }

  return (
    <div className="flex flex-col gap-6 text-sm">
      {/* ── BENEFICIO ── */}
      <section>
        <h3 className="mb-2 text-xs font-medium uppercase tracking-wide text-taupe">Beneficio</h3>
        <dl className="grid grid-cols-2 gap-x-4 gap-y-2">
          <div><dt className="text-xs text-taupe">Sede</dt><dd>{s.sede} · rango {s.rango}</dd></div>
          <div><dt className="text-xs text-taupe">Estudia</dt><dd>{s.beneficiario === "hijo" ? (s.beneficiario_nombre ?? "su hijo/a") : "La persona misma"}</dd></div>
          <div><dt className="text-xs text-taupe">Apoyo mensual</dt><dd className="tabular-nums">{soles(s.monto)}{!s.paga && s.vigencia !== "terminada" ? " · no se paga" : ""}</dd></div>
          <div><dt className="text-xs text-taupe">Vigencia</dt><dd>{fechaCorta(s.vigente_desde)} al {fechaCorta(s.vigente_hasta)}</dd></div>
        </dl>
        <div className="mt-3 grid grid-cols-2 gap-2">
          <CampoSelect etiqueta="Paga a su institución" value={frecuencia} onChange={(e) => setFrecuencia(e.target.value as FrecuenciaPago | "")}>
            <option value="">— sin definir —</option>
            {FRECUENCIAS_PAGO.map((f) => <option key={f} value={f}>{FRECUENCIA_PAGO_LABELS[f]}</option>)}
          </CampoSelect>
          <Campo etiqueta="Próximo pago" type="date" value={proxima} onChange={(e) => setProxima(e.target.value)} />
        </div>
        <div className="mt-2 flex flex-wrap gap-2">
          <Boton tamano="sm" cargando={trabajando} onClick={() => void guardarCalendario()}
            disabled={frecuencia === (s.frecuencia_pago ?? "") && proxima === (s.proxima_fecha_pago ?? "")}>Guardar calendario</Boton>
          <Boton tamano="sm" variante="sutil" onClick={onEditar}>Editar asignación</Boton>
          {s.vigencia !== "terminada" && <Boton tamano="sm" variante="peligro" onClick={() => setCerrando(true)}>Cerrar asignación</Boton>}
        </div>
      </section>

      {s.aviso_fin_id && (
        <section className="rounded-xl border border-ambar/40 bg-ambar/10 p-3">
          <p className="font-medium">Avisó que ya no va a pagar este estudio</p>
          <p className="mt-1">«{s.aviso_fin_motivo}»</p>
          <div className="mt-2 flex flex-wrap gap-2">
            <Boton tamano="sm" variante="peligro" onClick={() => setCerrando(true)}>Cerrar asignación</Boton>
            <Boton tamano="sm" cargando={trabajando} onClick={() => void atenderAviso()}>Marcar atendido sin cerrar</Boton>
          </div>
        </section>
      )}

      {/* ── CONSTANCIA POR REVISAR ── */}
      <section>
        <div className="mb-2 flex items-center justify-between gap-2">
          <h3 className="text-xs font-medium uppercase tracking-wide text-taupe">Constancia</h3>
          <Insignia variante={ESTADO_CONSTANCIA[s.estado_constancia].tono}>{ESTADO_CONSTANCIA[s.estado_constancia].etiqueta}</Insignia>
        </div>
        {entregas === null ? <Cargando /> : enRevision ? (
          <div className="rounded-xl border border-sand p-3">
            <dl className="grid grid-cols-2 gap-x-4 gap-y-2">
              <div><dt className="text-xs text-taupe">Pago</dt><dd>{fechaCorta(enRevision.fecha_pago)} · {TIPO_CONSTANCIA_LABELS[enRevision.tipo]}</dd></div>
              <div><dt className="text-xs text-taupe">Enviada</dt><dd>{fechaHora(enRevision.enviada_at)}</dd></div>
              <div><dt className="text-xs text-taupe">Próximo pago declarado</dt><dd>{enRevision.proxima_fecha_pago ? fechaCorta(enRevision.proxima_fecha_pago) : "no lo sabe o fue el último"}</dd></div>
              {enRevision.reemplaza_a && <div><dt className="text-xs text-taupe">Es</dt><dd>una corrección de un envío anterior</dd></div>}
            </dl>
            {enRevision.nota && <p className="mt-2 rounded-lg bg-hueso p-2 text-xs">«{enRevision.nota}»</p>}
            <VisorArchivos archivos={enRevision.archivos} />
            {esPropia ? (
              <p className="mt-3 text-xs text-taupe">Es tu propia constancia: la revisa otra persona de Desarrollo Organizacional.</p>
            ) : (
              <div className="mt-3 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
                <Boton variante="peligro" onClick={() => setRechazando(enRevision)}>Rechazar</Boton>
                <Boton variante="primario" onClick={() => setAprobando(enRevision)}>Aprobar</Boton>
              </div>
            )}
            {pendientesDe.length > 1 && <p className="mt-2 text-xs text-taupe">Hay {pendientesDe.length} constancias pendientes en este estudio; se revisan de a una.</p>}
          </div>
        ) : (
          <p className="text-taupe">
            {s.estado_constancia === "rechazada"
              ? "La última se rechazó; esperando que la integrante envíe la corregida."
              : s.fecha_pago_constancia && s.estado_constancia !== "al_dia"
                ? `Falta la constancia del pago del ${fechaCorta(s.fecha_pago_constancia)}${s.plazo ? `, plazo ${fechaCorta(s.plazo)}` : ""}.`
                : "No hay constancias por revisar."}
          </p>
        )}
        {!cargandoAlNombre ? (
          <Boton variante="enlace" className="mt-2 text-xs" onClick={() => setCargandoAlNombre(true)}>
            Cargar una constancia a su nombre
          </Boton>
        ) : (
          <CargaAlNombre s={s} onCancelar={() => setCargandoAlNombre(false)} onError={onError}
            onListo={async () => { setCargandoAlNombre(false); await traer(); await onCambio("Constancia cargada y aprobada."); }} />
        )}
      </section>

      {/* ── HISTORIAL ── */}
      <section>
        <h3 className="mb-2 text-xs font-medium uppercase tracking-wide text-taupe">Historial</h3>
        {entregas === null ? <Cargando /> : entregas.length === 0 ? (
          <p className="text-taupe">Sin constancias todavía.</p>
        ) : (
          <ul className="divide-y divide-sand">
            {entregas.map((e) => (
              <li key={e.id} className="py-2">
                <details open={e.id === entregaFoco && e.estado !== "pendiente"}>
                  <summary className="flex cursor-pointer list-none flex-wrap items-center justify-between gap-2">
                    <span>Pago del {fechaCorta(e.fecha_pago)} <span className="text-taupe">· {TIPO_CONSTANCIA_LABELS[e.tipo]}{e.reemplaza_a ? " · corrección" : ""}</span></span>
                    <Insignia variante={ESTADO_ENTREGA[e.estado].tono}>{ESTADO_ENTREGA[e.estado].etiqueta}</Insignia>
                  </summary>
                  <div className="mt-2 rounded-xl bg-hueso p-3 text-xs text-taupe">
                    <p>
                      {e.origen === "colaboradora" ? `Enviada por la integrante el ${fechaHora(e.enviada_at)}`
                        : e.origen === "do" ? `Cargada por ${e.enviada_por ?? "Desarrollo Organizacional"} el ${fechaHora(e.enviada_at)}`
                          : "Cargada antes de la revisión de constancias"}
                    </p>
                    {e.revisada_at && e.origen === "colaboradora" && <p>{e.estado === "aprobada" ? "Aprobó" : "Rechazó"} {e.revisada_por ?? "—"} el {fechaHora(e.revisada_at)}</p>}
                    {e.retirada_at && <p>La retiró la integrante el {fechaHora(e.retirada_at)}</p>}
                    {e.estado === "rechazada" && (
                      <p className="mt-1 text-rojo-profundo">{e.motivo_categoria ? MOTIVO_RECHAZO_LABELS[e.motivo_categoria] : ""}{e.motivo_comentario ? `: «${e.motivo_comentario}»` : ""}</p>
                    )}
                    {e.estado !== "pendiente" && <VisorArchivos archivos={e.archivos} compacto />}
                  </div>
                </details>
              </li>
            ))}
          </ul>
        )}
      </section>

      <Modal abierto={aprobando !== null} onCerrar={() => setAprobando(null)} bloqueado={trabajando} titulo="¿Aprobar esta constancia?" ancho="sm">
        {aprobando && (
          <>
            <p className="mb-4 text-sm text-taupe">
              Pago del {fechaCorta(aprobando.fecha_pago)} de {s.persona}. Queda registrado que la aprobaste hoy, y su próximo
              pago pasa a {aprobando.proxima_fecha_pago ? `el ${fechaCorta(aprobando.proxima_fecha_pago)}` : "sin fecha"}.
            </p>
            <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
              <Boton onClick={() => setAprobando(null)} disabled={trabajando}>Cancelar</Boton>
              <Boton variante="primario" cargando={trabajando} onClick={() => void aprobar()}>Aprobar</Boton>
            </div>
          </>
        )}
      </Modal>

      <Modal abierto={rechazando !== null} onCerrar={() => setRechazando(null)} bloqueado={trabajando} titulo="Rechazar constancia" ancho="md">
        {rechazando && (
          <>
            <p className="mb-3 text-sm text-taupe">{s.persona} va a leer el motivo y el comentario en su Bandeja, para corregirla.</p>
            <CampoSelect etiqueta="Motivo *" value={categoria} onChange={(e) => setCategoria(e.target.value as MotivoRechazo | "")}>
              <option value="">— elige el motivo —</option>
              {MOTIVOS_RECHAZO.map((m) => <option key={m} value={m}>{MOTIVO_RECHAZO_LABELS[m]}</option>)}
            </CampoSelect>
            <label className="mt-3 flex flex-col gap-1 text-sm">
              Qué tiene que corregir *
              <AreaTexto rows={3} value={comentario} onChange={(e) => setComentario(e.target.value)}
                placeholder="ej. la foto está cortada y no se ve el monto pagado" />
            </label>
            <div className="mt-4 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
              <Boton onClick={() => setRechazando(null)} disabled={trabajando}>Cancelar</Boton>
              <Boton variante="peligro" cargando={trabajando} onClick={() => void rechazar()}
                disabled={!categoria || comentario.trim().length < 3}>Rechazar constancia</Boton>
            </div>
          </>
        )}
      </Modal>

      <Modal abierto={cerrando} onCerrar={() => setCerrando(false)} bloqueado={trabajando} titulo="Cerrar esta asignación" ancho="sm">
        <p className="mb-4 text-sm text-taupe">
          ¿Hasta qué día se le paga a {s.persona}? La asignación no se borra: sigue sosteniendo lo ya pagado.
        </p>
        <Campo etiqueta="Se paga hasta" type="date" value={hastaCierre} onChange={(e) => setHastaCierre(e.target.value)} />
        <div className="mt-4 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <Boton onClick={() => setCerrando(false)} disabled={trabajando}>Cancelar</Boton>
          <Boton variante="peligro" cargando={trabajando} onClick={() => void cerrarAsignacion()} disabled={!hastaCierre}>Cerrar</Boton>
        </div>
      </Modal>
    </div>
  );
}

// Los archivos de una entrega, uno a la vez, con vista previa de las fotos.
function VisorArchivos({ archivos, compacto = false }: { archivos: Entrega["archivos"]; compacto?: boolean }) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const [i, setI] = useState(0);
  const [url, setUrl] = useState<string | null>(null);
  const actual = archivos[i] ?? null;
  const esImagen = actual ? (actual.tipo_mime ?? "").startsWith("image/") || /\.(jpe?g|png|webp)$/i.test(actual.ruta) : false;

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- un PDF no tiene vista previa: se suelta la de la foto anterior.
    if (compacto || !actual || !esImagen) { setUrl(null); return; }
    let vivo = true;
    void urlDeConstancia(supabase, actual.ruta).then((u) => { if (vivo) setUrl(u); });
    return () => { vivo = false; };
  }, [supabase, actual, esImagen, compacto]);

  if (archivos.length === 0) return <p className="mt-2 text-xs text-taupe">Sin archivos.</p>;

  if (compacto) {
    return (
      <ul className="mt-2 flex flex-wrap gap-2">
        {archivos.map((a, k) => (
          <li key={a.id}>
            <Boton variante="enlace" className="text-xs" onClick={() => void abrirArchivoFirmado(supabase, BUCKET_COMPROBANTES, a.ruta)}>
              {a.nombre || `Archivo ${k + 1}`}
            </Boton>
          </li>
        ))}
      </ul>
    );
  }

  return (
    <div className="mt-3">
      <div className="flex items-center justify-between gap-2 text-xs text-taupe">
        <span className="truncate">Archivo {i + 1} de {archivos.length} · {actual?.nombre}</span>
        <span className="flex shrink-0 gap-1">
          <Boton tamano="sm" variante="sutil" onClick={() => setI((k) => Math.max(0, k - 1))} disabled={i === 0} aria-label="Archivo anterior">←</Boton>
          <Boton tamano="sm" variante="sutil" onClick={() => setI((k) => Math.min(archivos.length - 1, k + 1))} disabled={i === archivos.length - 1} aria-label="Archivo siguiente">→</Boton>
        </span>
      </div>
      <div className="mt-2 flex min-h-48 items-center justify-center overflow-hidden rounded-xl border border-sand bg-hueso">
        {esImagen ? (
          url
            // eslint-disable-next-line @next/next/no-img-element -- imagen de un bucket privado, con URL firmada
            ? <img src={url} alt={actual?.nombre ?? "Constancia"} className="max-h-[60vh] w-auto max-w-full object-contain" />
            : <span className="text-xs text-taupe">Cargando…</span>
        ) : (
          <span className="text-xs text-taupe">PDF · ábrelo para leerlo</span>
        )}
      </div>
      {actual && (
        <Boton variante="enlace" className="mt-1 text-xs" onClick={() => void abrirArchivoFirmado(supabase, BUCKET_COMPROBANTES, actual.ruta)}>
          Abrir en una pestaña
        </Boton>
      )}
    </div>
  );
}

// DO carga la constancia a nombre de alguien: queda aprobada, con su nombre.
function CargaAlNombre({ s, onCancelar, onListo, onError }: {
  s: Situacion; onCancelar: () => void; onListo: () => Promise<void>; onError: (t: string) => void;
}) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const hoy = hoyLima();
  const [entregaId] = useState(() => crypto.randomUUID());
  const inicial = s.fecha_pago_constancia && s.fecha_pago_constancia <= hoy ? s.fecha_pago_constancia : hoy;
  const [fechaPago, setFechaPago] = useState(inicial);
  const [tipo, setTipo] = useState<TipoConstancia>("cuota_mensual");
  const [proxima, setProxima] = useState(sugerirProximaFecha(inicial, s.frecuencia_pago) ?? "");
  const [archivos, setArchivos] = useState<ArchivoElegido[]>([]);
  const [enviando, setEnviando] = useState(false);

  async function enviar() {
    if (archivos.length === 0) { onError("Elige al menos un archivo."); return; }
    setEnviando(true);
    const subida = await subirArchivosDeEntrega(supabase, s.persona_id, entregaId, archivos, () => {},
      (clave, subido) => setArchivos((prev) => prev.map((a) => (a.clave === clave ? { ...a, subido } : a))));
    if (!subida.ok) { setEnviando(false); onError(subida.error); return; }
    const { error } = await supabase.rpc("fn_educacion_enviar_entrega", {
      p_id: entregaId, p_asignacion_id: s.asignacion_id, p_fecha_pago: fechaPago, p_tipo: tipo,
      p_proxima_fecha_pago: proxima || null, p_archivos: subida.archivos, p_nota: null, p_reemplaza_a: null,
    });
    setEnviando(false);
    if (error) { onError(mensajeDeError(error, "cargar la constancia")); return; }
    await onListo();
  }

  return (
    <div className="mt-3 grid gap-2 rounded-xl border border-sand p-3 sm:grid-cols-2">
      <Campo etiqueta="Fecha de pago" type="date" value={fechaPago} max={hoy} onChange={(e) => setFechaPago(e.target.value)} />
      <CampoSelect etiqueta="Tipo" value={tipo} onChange={(e) => setTipo(e.target.value as TipoConstancia)}>
        {TIPOS_CONSTANCIA.map((t) => <option key={t} value={t}>{TIPO_CONSTANCIA_LABELS[t]}</option>)}
      </CampoSelect>
      <Campo etiqueta="Próximo pago (opcional)" type="date" value={proxima} onChange={(e) => setProxima(e.target.value)} />
      <Campo etiqueta="Archivos" type="file" multiple accept="application/pdf,image/*"
        onChange={(e) => {
          const nuevos: ArchivoElegido[] = [];
          for (const f of Array.from(e.target.files ?? [])) {
            const p = problemaDeArchivo({ nombre: f.name, tipo: f.type, bytes: f.size });
            if (p) { onError(p); continue; }
            nuevos.push(elegido(f));
          }
          setArchivos(nuevos.slice(0, 10));
        }} />
      <div className="flex gap-2 sm:col-span-2">
        <Boton variante="primario" tamano="sm" cargando={enviando} onClick={() => void enviar()}>Cargar y aprobar</Boton>
        <Boton tamano="sm" onClick={onCancelar} disabled={enviando}>Cancelar</Boton>
      </div>
    </div>
  );
}

function ConfigConstancias({ abierto, config, onCerrar, onGuardado, onError }: {
  abierto: boolean;
  config: { texto: string; plazo: number; avisoColab: number; avisoDo: number };
  onCerrar: () => void; onGuardado: () => Promise<void>; onError: (t: string) => void;
}) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const [texto, setTexto] = useState(config.texto);
  const [plazo, setPlazo] = useState(String(config.plazo));
  const [avisoColab, setAvisoColab] = useState(String(config.avisoColab));
  const [avisoDo, setAvisoDo] = useState(String(config.avisoDo));
  const [guardando, setGuardando] = useState(false);

  // eslint-disable-next-line react-hooks/set-state-in-effect -- al abrir, arranca con lo guardado.
  useEffect(() => { if (abierto) { setTexto(config.texto); setPlazo(String(config.plazo)); setAvisoColab(String(config.avisoColab)); setAvisoDo(String(config.avisoDo)); } }, [abierto, config]);

  async function guardar() {
    setGuardando(true);
    const { error } = await supabase.rpc("fn_educacion_configurar", {
      p_texto_valido: texto, p_dias_plazo: Number(plazo), p_dias_aviso_colab: Number(avisoColab), p_dias_aviso_do: Number(avisoDo),
    });
    setGuardando(false);
    if (error) { onError(mensajeDeError(error, "guardar la configuración")); return; }
    await onGuardado();
  }

  return (
    <Modal abierto={abierto} onCerrar={onCerrar} bloqueado={guardando} titulo="Texto y plazos de las constancias" ancho="lg">
      <label className="flex flex-col gap-1 text-sm">
        Qué constancias son válidas (lo lee la integrante al subir)
        <AreaTexto rows={4} value={texto} onChange={(e) => setTexto(e.target.value)} />
      </label>
      <div className="mt-3 grid gap-3 sm:grid-cols-3">
        <Campo etiqueta="Vence antes del cierre (días)" type="number" min="0" max="20" value={plazo} onChange={(e) => setPlazo(e.target.value)} />
        <Campo etiqueta="Aviso a la integrante (días)" type="number" min="0" max="30" value={avisoColab} onChange={(e) => setAvisoColab(e.target.value)} />
        <Campo etiqueta="Aviso a DO antes del pago (días)" type="number" min="0" max="30" value={avisoDo} onChange={(e) => setAvisoDo(e.target.value)} />
      </div>
      <div className="mt-4 flex justify-end gap-2">
        <Boton onClick={onCerrar} disabled={guardando}>Cancelar</Boton>
        <Boton variante="primario" cargando={guardando} onClick={() => void guardar()}>Guardar</Boton>
      </div>
    </Modal>
  );
}

export default function EducacionPage() {
  return (
    <Suspense fallback={<Cargando />}>
      <EducacionContenido />
    </Suspense>
  );
}

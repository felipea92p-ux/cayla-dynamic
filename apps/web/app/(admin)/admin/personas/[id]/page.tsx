"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useParams, useRouter, useSearchParams } from "next/navigation";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { ESTADO_CIVIL_LABELS, GENERO_LABELS, GRADO_INSTRUCCION_LABELS, TZ_LIMA, TIPO_VINCULO_LABEL, etiquetaDeCatalogo, hoyLima, puedeMarcarCuentaDeServicio, puedeOperarEquipo, puedeVerIdentidad, puedeVerPlanilla } from "@cayla-dynamic/shared";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { BUCKET_SOLICITUDES_PERFIL, CARAS_DNI, type CaraDni } from "@/lib/foto-dni";
import { abrirArchivoFirmado } from "@/lib/abrir-archivo-firmado";
import { Cargando } from "@/components/cargando";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { GraficoHoras, type DiaGrafico } from "@/components/grafico-horas";
import { MESES, lecturaObjetivos, type ObjetivoItem } from "@/lib/objetivos";
import { RANGO_LABEL, formatSoles } from "@/lib/rangos";
import { useToast } from "@/components/toast";
import { Boton } from "@/components/ui/boton";
import { Campo } from "@/components/ui/campo";
import { Cifra } from "@/components/ui/cifra";
import { Insignia } from "@/components/ui/insignia";
import { Menu, MenuItem } from "@/components/ui/menu";
import { Modal } from "@/components/ui/modal";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { Fila, Tabla, TablaEncabezado, Th } from "@/components/ui/tabla";
import { FirmaEditor } from "./FirmaEditor";
import { ModalRegistrarFalta } from "@/components/disciplina/registrar-falta";
import { puedeRegistrarleConducta } from "@/lib/admin/conducta";

const META_DIA = 7.5; // horas objetivo por día (45h/semana)

function fechaCorta(iso: string | null): string {
  if (!iso) return "—";
  const [y, m, d] = iso.slice(0, 10).split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "long", year: "numeric", timeZone: "UTC" }).format(new Date(Date.UTC(y, m - 1, d)));
}
function selloLima(iso: string): string {
  const d = new Date(iso);
  return isNaN(d.getTime()) ? iso : new Intl.DateTimeFormat("es-PE", { timeZone: TZ_LIMA, day: "2-digit", month: "short", year: "numeric" }).format(d);
}
function inicioMes(): string { return hoyLima().slice(0, 8) + "01"; }
function horaLima(ts: string | null): string {
  if (!ts) return "—";
  return new Intl.DateTimeFormat("es-PE", { timeZone: TZ_LIMA, hour: "2-digit", minute: "2-digit", hour12: true }).format(new Date(ts));
}
function fechaLarga(f: string): string {
  const [y, m, d] = f.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { timeZone: TZ_LIMA, weekday: "short", day: "2-digit", month: "short" }).format(new Date(Date.UTC(y, m - 1, d, 12)));
}
function fmtHoras(h: number): string {
  const hh = Math.floor(h);
  const mm = Math.round((h - hh) * 60);
  return `${hh}h ${String(mm).padStart(2, "0")}m`;
}
const soles = (n: number) => `S/ ${n.toLocaleString("es-PE", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

function Dato({ label, valor }: { label: string; valor: React.ReactNode }) {
  return (
    <div className="flex justify-between gap-3 border-b border-sand/50 py-1.5 text-sm last:border-0">
      <span className="text-taupe">{label}</span>
      <span className="text-right">{valor ?? "—"}</span>
    </div>
  );
}

const NIVEL: Record<string, string> = { verbal: "Llamada verbal", amonestacion: "Amonestación escrita", suspension: "Suspensión", imputacion: "Imputación", despido: "Despido" };
const CAUSAL: Record<string, string> = { tardanza: "Tardanzas", falta: "Faltas", conducta: "Conducta" };
const ESTADO_DOC: Record<string, string> = { borrador: "Borrador", firmado: "Firmado", entregado: "Entregado", anulado: "Anulado", cerrado_sin_entrega: "Cerrado sin entrega" };

// Historial (0428): `correcciones_auditoria` guarda TODO lo que una RPC
// `fn_set_*` audita — desde un cambio de rol hasta una marca corregida a
// mano. Esta pestaña cuenta la carrera de la persona (rol, sede, vínculo,
// contrato...), no su reloj: los campos de marcaje ya tienen su propia
// pantalla (/admin/correcciones) para un público distinto (quién corrige un
// marcaje día a día) con su propia traducción a lenguaje llano
// (`describirCambio` en correcciones/page.tsx, que no aplica acá). Se
// EXCLUYEN por nombre en vez de incluir solo lo conocido: así un `fn_set_*`
// nuevo aparece acá solo, sin tener que acordarse de agregarlo a una lista.
const CAMPO_MARCAJE_EXCLUIR = new Set([
  "timestamp_marca", "auto_cierre_reemplazado", "marcaje_agregado",
  "marcaje_anulado", "marcaje_reactivado", "marcaje_eliminado", "marca_apartada",
]);
const CAMPO_LABEL: Record<string, string> = {
  rol: "Rol",
  sede_base_id: "Sede",
  tipo_vinculo: "Tipo de vínculo",
  cargo: "Cargo",
  fin_contrato: "Fin de contrato",
  retencion_4ta: "Retención de 4ta categoría",
  visible_todas_sedes: "Visible en todas las sedes",
  con_hijos: "Asignación familiar",
  fecha_ingreso: "Fecha de ingreso",
  practicante_modalidad: "Modalidad de practicante",
  regimen_pension: "Régimen de pensión",
  funcion: "Área",
};

interface Persona { id: string; nombres: string; apellidos: string; documento: string | null; funcion: string; sede_base_id: string; fecha_ingreso: string; email: string | null; estado: string; en_planilla: boolean; sueldo_fijo: boolean; personal_direccion: boolean; tipo_vinculo: string; rol: string }
interface Ficha { nombre_dni: string | null; fecha_nacimiento: string | null; estado_civil: string | null; genero: string | null; direccion: string | null; celular: string | null; entidad_bancaria: string | null; numero_cuenta: string | null; grado_instruccion: string | null; hijos_menores: boolean | null; foto_personal_url: string | null; foto_dni_anverso_ruta: string | null; foto_dni_reverso_ruta: string | null }
interface Salario { rango: string; salario_mensual_soles: number; vigente_desde: string; vigente_hasta: string | null }
interface TramoSalarioHist { rango: string; salario_mensual_soles: number; vigente_desde: string; vigente_hasta: string | null; asignado_por: string | null; nota: string | null }
interface DocLite { id: string; correlativo: string | null; tipo_causal: string; nivel: string; estado: string; creado_at: string; firmado_at: string | null }
interface Jornada { fecha: string; entrada_ts: string | null; salida_final_ts: string | null; horas_trabajadas: number | null; minutos_tarde: number | null; minutos_salida_temprana: number | null; horas_extra_detectadas: number | null; estado: string }
interface VacacionesSaldo { aplica: boolean; dias_pendientes: number; records_sin_gozar: number; records_vencidos: number; vence_el: string | null; dias_para_vencer: number | null }
interface ContratoPorVencer { persona_id: string; fecha_fin_contrato: string; dias_restantes: number; ya_vencio: boolean }
interface AuditoriaFila { id: string; campo_modificado: string; valor_anterior: string | null; valor_nuevo: string | null; corregido_at: string; motivo: string; corregido_por: string }
interface HistorialEvento { id: string; fechaOrden: string; fechaMostrar: string; titulo: string; detalle?: string; motivo?: string; quien?: string }

// Seis pestañas (0428, reemplaza "Ficha | Desempeño"). La antigua "Desempeño"
// no medía desempeño: medía asistencia (horas, tardanzas, tiempo adicional).
// Se separa en dos para no seguir construyendo encima de esa mezcla —
// "Desempeño" queda para lo que YA existe de eso (el checklist de objetivos
// del mes, `fn_objetivos_checklist`), no para una pantalla inventada.
type Tab = "resumen" | "asistencia" | "desempeno" | "compensacion" | "documentos" | "historial";
const TABS_VALIDAS: readonly Tab[] = ["resumen", "asistencia", "desempeno", "compensacion", "documentos", "historial"];

// UNA CONSULTA QUE FALLA NO SE PINTA COMO UNA QUE RESPONDIÓ VACÍA.
//
// En esta ficha el vacío se lee como buena noticia —«Sin antecedentes
// disciplinarios. Buena señal.», «Sin ficha cargada», «Sin salario
// asignado»— y quien la abre puede estar decidiendo si conversa o amonesta a
// una integrante. Si la consulta del expediente falla y la pantalla dice lo
// mismo que cuando no hay nada, el falso negativo es silencioso y cae justo
// sobre la persona por la que había que actuar.
//
// Por eso cada sección tiene su propio aviso: dice qué falló, por qué, y —lo
// que de verdad importa— qué NO significa. Tres estados y tres textos:
// cargando, error y vacío.
//
// Va fuera del componente de la página a propósito: definirlo dentro lo
// recrearía en cada render (regla react-hooks/static-components).
function AvisoNoSeCargo({ que, motivo, noSignifica, reintentar }: { que: string; motivo: string; noSignifica: string; reintentar: () => void }) {
  return (
    <div className="rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
      <p>No se pudo cargar {que}: {motivo}</p>
      <p className="mt-1">
        Esto <strong>no</strong> quiere decir que {noSignifica}.{" "}
        <Boton variante="enlace" className="no-print" onClick={reintentar}>Reintentar</Boton>
      </p>
    </div>
  );
}

// Fuera del componente por la misma razón de arriba: definirlo dentro de
// PerfilPersonaPage lo recrearía en cada render (react-hooks/static-components),
// y React desmontaba y volvía a montar los botones en cada cambio de
// pestaña — quien llegaba con teclado hasta una pestaña y pulsaba Enter
// perdía el foco al body y tenía que recorrer la página entera de nuevo.
function TabBtn({ valor, tab, setTab, children }: { valor: Tab; tab: Tab; setTab: (t: Tab) => void; children: React.ReactNode }) {
  return (
    <button
      role="tab"
      aria-selected={tab === valor}
      onClick={() => setTab(valor)}
      className={`-mb-px whitespace-nowrap border-b-2 px-3 py-2 text-sm transition-colors ${
        tab === valor ? "border-rojo font-medium text-tinta" : "border-transparent text-taupe hover:text-tinta"}`}
    >
      {children}
    </button>
  );
}

export default function PerfilPersonaPage() {
  const params = useParams();
  const id = (params?.id as string) ?? "";
  const router = useRouter();
  const searchParams = useSearchParams();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const puede = puedeOperarEquipo(rol);
  // El sueldo solo lo ve DO (la fn_historial_salario ya lo bloquea en BD; aquí ocultamos
  // la sección para que a la encargada no le aparezca "sin salario" — que sería mentira).
  const puedeSalario = puedeVerPlanilla(rol);
  // El DNI es identidad, y la identidad es de DO en todo el sistema — la
  // encargada de sede no lo ve ni lo cancela (mismo criterio que la 0405).
  const puedeIdentidad = puedeVerIdentidad(rol);
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const { avisar } = useToast();

  // Equipo enlaza directo a "?tab=historial" en vez de repetir el timeline
  // acá dentro (ver el comentario del botón "Historial" en equipo/page.tsx).
  // Solo se lee al montar: cambiar de pestaña después no reescribe la URL.
  const [tab, setTab] = useState<Tab>(() => {
    const t = searchParams.get("tab");
    return (TABS_VALIDAS as readonly string[]).includes(t ?? "") ? (t as Tab) : "resumen";
  });

  // ── Datos base (se cargan siempre) ────────────────────────────────────────
  const [persona, setPersona] = useState<Persona | null>(null);
  // ¿Es una estación de retail y no una persona? (0490). null = no se sabe.
  const [cuentaServicio, setCuentaServicio] = useState<boolean | null>(null);
  const [cambiandoServicio, setCambiandoServicio] = useState(false);
  const [guardandoServicio, setGuardandoServicio] = useState(false);
  const [motivoServicio, setMotivoServicio] = useState("");
  const puedeMarcarServicio = puedeMarcarCuentaDeServicio(rol);

  async function cambiarCuentaServicio() {
    if (cuentaServicio === null) return;
    setGuardandoServicio(true);
    const { error } = await supabase.rpc("fn_set_cuenta_de_servicio", {
      p_persona_id: id,
      p_valor: !cuentaServicio,
      p_motivo: motivoServicio.trim() || undefined,
    });
    setGuardandoServicio(false);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    avisar("ok", cuentaServicio
      ? "Vuelve a ser una persona: entra otra vez a la planilla y a las listas del equipo."
      : "Marcada como cuenta de servicio: sale de la planilla, del terminal y de las listas del equipo.");
    setCuentaServicio(!cuentaServicio);
    setCambiandoServicio(false);
    setMotivoServicio("");
  }
  const [ficha, setFicha] = useState<Ficha | null>(null);
  const [sede, setSede] = useState<string>("");
  const [salario, setSalario] = useState<Salario | null>(null);
  const [docs, setDocs] = useState<DocLite[]>([]);
  const [cargando, setCargando] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  // ¿Ese `err` es un fallo (se puede reintentar) o una respuesta legítima («no
  // existe / no tienes permiso»)? Son dos conclusiones distintas y las dos son
  // accionables: ofrecer «Reintentar» sobre la segunda invitaría a insistir
  // contra algo que nunca va a cambiar.
  const [errReintentable, setErrReintentable] = useState(false);
  // ── Cancelación del DNI (0407) ──────────────────────────────────────────
  // Derecho de cancelación de la Ley N.° 29733, el que el texto de
  // consentimiento le promete a la persona. El motivo es obligatorio y va
  // aparte del botón a propósito: acá queda escrito a petición de quién y bajo
  // qué criterio de conservación se borró un documento de identidad.
  //
  // Vive detrás de un Modal desde la 0428 — antes era un bloque siempre
  // visible en la ficha, y una acción excepcional (cancelar un documento de
  // identidad) no debe competir visualmente con la lectura cotidiana de la
  // pantalla. `mostrandoCancelarDni` es el candado del modal, no un booleano
  // más: cerrarlo también limpia el motivo, para no dejarlo a medio escribir
  // si alguien vuelve a abrirlo para otra persona.
  const [mostrandoCancelarDni, setMostrandoCancelarDni] = useState(false);
  const [motivoBorrarDni, setMotivoBorrarDni] = useState("");
  const [borrandoDni, setBorrandoDni] = useState(false);
  function cerrarCancelarDni() {
    if (borrandoDni) return; // mismo candado que Modal.bloqueado: no perder el motivo a medio escribir
    setMostrandoCancelarDni(false);
    setMotivoBorrarDni("");
  }
  // Un error por consulta, porque cada una pinta una sección distinta y el
  // fallo de una no puede vaciar en silencio a las otras tres.
  const [errSede, setErrSede] = useState<string | null>(null);
  const [errFicha, setErrFicha] = useState<string | null>(null);
  const [errSalario, setErrSalario] = useState<string | null>(null);
  const [errDocs, setErrDocs] = useState<string | null>(null);
  const [errVacas, setErrVacas] = useState<string | null>(null);
  const [errContrato, setErrContrato] = useState<string | null>(null);
  // Sube de uno en uno para volver a lanzar la carga desde cualquier
  // «Reintentar». La carga vive en el efecto (no en un callback) para no
  // repetir el patrón que react-hooks/set-state-in-effect ya marca abajo.
  const [intento, setIntento] = useState(0);
  const reintentar = () => setIntento((n) => n + 1);

  /**
   * Cancela el DNI: primero la ficha y la auditoría (la RPC, que es atómica),
   * y con las rutas que devuelve, los archivos del almacén. Ese orden está
   * razonado en la cabecera de la 0407 — al revés, un fallo dejaría la ficha
   * apuntando a archivos que ya no están y nadie se enteraría.
   */
  async function cancelarDni() {
    if (!ficha || motivoBorrarDni.trim() === "") return;
    setBorrandoDni(true);
    try {
      const { data, error } = await supabase.rpc("fn_borrar_dni_de", {
        p_persona_id: id,
        p_motivo: motivoBorrarDni.trim(),
      });
      if (error) { avisar("error", mensajeDeError(error)); return; }

      const rutas = ((data as { ruta: string }[] | null) ?? []).map((r) => r.ruta);
      const { error: eArchivos } = await supabase.storage
        .from(BUCKET_SOLICITUDES_PERFIL).remove(rutas);
      if (eArchivos) {
        // La ficha YA quedó limpia y auditada; lo que falló es el almacén. Se
        // dice tal cual, porque lo que hay que hacer no es repetir todo sino
        // reintentar esa parte — y porque un «no se pudo» a secas dejaría creer
        // que el DNI sigue en la ficha, que es lo contrario de lo que pasó.
        avisar("error", `La ficha quedó limpia y auditada, pero los archivos siguen en el almacén: ${eArchivos.message}`);
      } else {
        avisar("ok", "DNI cancelado: se retiró de la ficha y se borraron los archivos.");
      }
      setMostrandoCancelarDni(false);
      setMotivoBorrarDni("");
      reintentar();
    } finally {
      setBorrandoDni(false);
    }
  }
  /**
   * Abre una cara del DNI YA APROBADO. Hasta aquí la foto solo se podía mirar
   * en /admin/bandeja mientras estaba pendiente: una vez aprobada, la ficha
   * decía «Cargadas y aprobadas» y el único botón al lado era «Cancelar
   * documento» — que borra y no se deshace. Quien entraba a mirar el DNI solo
   * encontraba la acción destructiva.
   *
   * Pasa por `abrirArchivoFirmado` y no por `window.open` tras la firma: el
   * navegador bloquea a ratos la pestaña si la firma tarda (ver ese archivo).
   * 60 segundos alcanzan para que cargue; el enlace no queda vivo dando vueltas.
   * Quién puede leerla lo decide la política del bucket (0403), no esta pantalla.
   */
  async function verCaraDni(ruta: string) {
    const fallo = await abrirArchivoFirmado(supabase, BUCKET_SOLICITUDES_PERFIL, ruta);
    if (fallo) avisar("error", fallo);
  }
  const [incluirSueldo, setIncluirSueldo] = useState(true); // controla si el sueldo entra al PDF
  const [vacas, setVacas] = useState<VacacionesSaldo | null>(null);
  const [contrato, setContrato] = useState<ContratoPorVencer | null>(null);

  useEffect(() => {
    let vivo = true;
    void (async () => {
      setCargando(true); setErr(null); setErrReintentable(false);
      const { data: sesion } = await supabase.auth.getSession();
      if (!sesion.session) { router.replace("/admin/login"); return; }
      const { data: p, error: eP } = await supabase.from("personas")
        .select("id, nombres, apellidos, documento, funcion, sede_base_id, fecha_ingreso, email, estado, en_planilla, sueldo_fijo, personal_direccion, tipo_vinculo, rol")
        .eq("id", id).maybeSingle();
      // La consulta que MANDA en esta pantalla tampoco funde error con vacío.
      // `eP` (la consulta falló) y `!p` (respondió y no hay fila) llevaban el
      // mismo texto, así que una sesión vencida o un corte de red se leían como
      // «esa persona no existe o no tienes permiso para verla»: dos
      // conclusiones falsas, y las dos accionables.
      if (eP) { if (vivo) { setErr(`No se pudo cargar a la persona: ${mensajeDeError(eP)}`); setErrReintentable(true); setCargando(false); } return; }
      if (!p) { if (vivo) { setErr("No se encontró a la persona (o no tienes permiso para verla)."); setCargando(false); } return; }
      if (vivo) setPersona(p as Persona);
      // Cuenta de servicio (0490): aparte y tolerante. Si la columna todavía no
      // existe, queda en null y la ficha no ofrece marcarla — no se cae entera.
      void supabase.from("personas").select("cuenta_de_servicio").eq("id", id).maybeSingle()
        .then(({ data, error }) => {
          if (vivo) setCuentaServicio(error || !data ? null : (data as { cuenta_de_servicio: boolean }).cuenta_de_servicio);
        });
      // Las consultas se miran UNA POR UNA. Antes solo se revisaba la
      // del salario —y su fallo, además, tumbaba la ficha entera—; las otras
      // fallaban en silencio y su sección se pintaba como vacía.
      const [{ data: s, error: eSedes }, { data: dp, error: eFicha }, { data: sal, error: eSal }, { data: dd, error: eDocs }, { data: vac, error: eVac }, { data: contratos, error: eContrato }] = await Promise.all([
        supabase.from("sedes").select("id, codigo"),
        supabase.from("datos_personales")
          .select("nombre_dni, fecha_nacimiento, estado_civil, genero, direccion, celular, entidad_bancaria, numero_cuenta, grado_instruccion, hijos_menores, foto_personal_url, foto_dni_anverso_ruta, foto_dni_reverso_ruta")
          .eq("persona_id", id).maybeSingle(),
        supabase.rpc("fn_historial_salario", { p_persona_id: id }),
        supabase.from("expediente_disciplinario")
          .select("id, correlativo, tipo_causal, nivel, estado, creado_at, firmado_at")
          .eq("persona_id", id).order("creado_at", { ascending: false }),
        // Mismo saldo que ve la propia persona en "Lo mío" (fn_vacaciones_saldo);
        // acá se lee en la ficha para no tener que ir a buscarlo aparte.
        supabase.rpc("fn_vacaciones_saldo", { p_persona_id: id, p_as_of: null }),
        // Ventana de 90 días, igual que el aviso del Dashboard — si no aparece
        // acá, es que no tiene un contrato a plazo fijo por vencer pronto, no
        // que falte el dato.
        supabase.rpc("fn_contratos_por_vencer", { p_dias: 90 }),
      ]);
      const smap = new Map(((s as Array<{ id: string; codigo: string }>) ?? []).map((x) => [x.id, x.codigo]));
      if (vivo) {
        setErrSede(eSedes ? mensajeDeError(eSedes) : null);
        setErrFicha(eFicha ? mensajeDeError(eFicha) : null);
        setErrSalario(eSal ? mensajeDeError(eSal) : null);
        setErrDocs(eDocs ? mensajeDeError(eDocs) : null);
        setErrVacas(eVac ? mensajeDeError(eVac) : null);
        setErrContrato(eContrato ? mensajeDeError(eContrato) : null);
        setSede(smap.get((p as Persona).sede_base_id) ?? "");
        setFicha(eFicha ? null : (dp as Ficha) ?? null);
        const hist = eSal ? [] : (sal as Salario[]) ?? [];
        setSalario(hist.find((x) => !x.vigente_hasta) ?? hist[0] ?? null);
        setDocs(eDocs ? [] : (dd as DocLite[]) ?? []);
        const v = eVac ? null : (vac as VacacionesSaldo | null);
        setVacas(v && v.aplica ? v : null);
        setContrato(eContrato ? null : (((contratos as ContratoPorVencer[] | null) ?? []).find((c) => c.persona_id === id) ?? null));
        setCargando(false);
      }
    })();
    return () => { vivo = false; };
  }, [supabase, router, id, intento]);

  // El nombre con el que se guarda el PDF de la ficha. Ver
  // use-titulo-documento.ts. Lleva el DNI cuando está cargado, porque una ficha
  // personal se archiva por documento de identidad, no por nombre.
  useTituloDocumento(
    persona
      ? [`${persona.nombres} ${persona.apellidos}`, persona.documento, "Ficha personal"]
          .filter(Boolean)
          .join(" — ")
      : null,
  );

  // ── Asistencia + Desempeño (se cargan juntas, solo al abrir su primera
  //    pestaña). Comparten el mismo rango de fechas: Asistencia mide jornadas
  //    dentro del rango, Desempeño mide objetivos del MES que cae en `hasta`.
  //    No se separan en dos cargas — ya estaban resueltas juntas y con su
  //    manejo de error parcial afinado; separarlas hoy sería repetir esa
  //    lógica dos veces para dos pestañas que de todas formas se abren juntas
  //    la mayoría de las veces. ──────────────────────────────────────────────
  const [desde, setDesde] = useState(inicioMes());
  const [hasta, setHasta] = useState(hoyLima());
  const [jornadas, setJornadas] = useState<Jornada[]>([]);
  const [levTard, setLevTard] = useState<Map<string, string>>(new Map());
  const [objetivos, setObjetivos] = useState<ObjetivoItem[]>([]);
  const [cargandoDes, setCargandoDes] = useState(false);
  const [desCargado, setDesCargado] = useState(false);
  const [errDes, setErrDes] = useState<string | null>(null);
  // Lo que se cargó A MEDIAS. Las jornadas mandan —si fallan, ninguna de las
  // dos pestañas tiene nada—, pero las otras tres consultas también se miran:
  // si fallan en silencio, lo que se pinta no es «no había nada», es otra
  // cosa. La peor de las tres son las tardanzas levantadas: sin ellas, una
  // tardanza YA JUSTIFICADA vuelve a verse como tardanza y a contarse en el
  // resumen. Un falso positivo contra una persona es el error que más caro
  // sale acá.
  const [errParcialDes, setErrParcialDes] = useState<string[]>([]);
  // Filtrado por pestaña: el de objetivos es de Desempeño, los otros dos son
  // de Asistencia — mostrar los tres en las dos pestañas haría parecer que
  // Asistencia perdió datos de objetivos, que ni siquiera muestra.
  const errParcialAsistencia = errParcialDes.filter((t) => !t.includes("objetivos"));
  const errParcialDesempeno = errParcialDes.filter((t) => t.includes("objetivos"));

  const cargarDesempeno = useCallback(async () => {
    setCargandoDes(true); setErrDes(null); setErrParcialDes([]);
    const [{ data, error: eJ }, { data: extra, error: eExtra }, { data: objs, error: eObjs }, { data: levData, error: eLev }] = await Promise.all([
      supabase.from("jornadas")
        .select("fecha, entrada_ts, salida_final_ts, horas_trabajadas, minutos_tarde, horas_extra_detectadas, estado")
        .eq("persona_id", id).gte("fecha", desde).lte("fecha", hasta).order("fecha"),
      supabase.rpc("fn_jornadas_extra", { p_desde: desde, p_hasta: hasta, p_persona_id: id }),
      supabase.rpc("fn_objetivos_checklist", { p_anio: Number(hasta.slice(0, 4)), p_mes: Number(hasta.slice(5, 7)), p_persona_id: id }),
      supabase.from("tardanzas_justificadas").select("fecha, motivo").eq("persona_id", id).gte("fecha", desde).lte("fecha", hasta),
    ]);
    if (eJ) { setErrDes(mensajeDeError(eJ)); setCargandoDes(false); return; }
    setErrParcialDes([
      eLev ? `las tardanzas levantadas (${mensajeDeError(eLev)}) — una tardanza YA justificada se está viendo y contando como tardanza` : "",
      eExtra ? `las salidas anticipadas (${mensajeDeError(eExtra)}) — la tarjeta del resumen dice «0 de 0 medidos» y la columna «—», aunque las haya` : "",
      eObjs ? `los objetivos del mes (${mensajeDeError(eObjs)}) — su bloque no aparece, y eso no quiere decir que no tenga` : "",
    ].filter(Boolean));
    setObjetivos(((objs as unknown as ObjetivoItem[] | null) ?? []).slice());
    const filasExtra = (extra as { fecha: string; minutos_salida_temprana: number }[] | null) ?? [];
    const minutosPorFecha = new Map(filasExtra.map((e) => [e.fecha, e.minutos_salida_temprana]));
    const filas = ((data as Omit<Jornada, "minutos_salida_temprana">[] | null) ?? []).map((j) => ({ ...j, minutos_salida_temprana: minutosPorFecha.get(j.fecha) ?? null }));
    setJornadas(filas);
    setLevTard(new Map(((levData as { fecha: string; motivo: string }[] | null) ?? []).map((t) => [t.fecha, t.motivo])));
    setDesCargado(true);
    setCargandoDes(false);
  }, [supabase, id, desde, hasta]);

  // ── Historial (0428, nuevo) ───────────────────────────────────────────────
  // Mezcla dos fuentes que ya existían por separado: `correcciones_auditoria`
  // (quién cambió qué campo de carrera y por qué — mismo query que ya usa
  // /admin/correcciones, solo que sin el filtro de fecha porque acá se quiere
  // TODO el historial de la persona) y `fn_historial_salario` (los tramos de
  // sueldo, misma RPC que ya usa Equipo). No se inventa una tercera fuente:
  // no hay hoy una tabla de "cambios de cargo/sede" aparte de la auditoría.
  const [historial, setHistorial] = useState<HistorialEvento[]>([]);
  const [cargandoHist, setCargandoHist] = useState(false);
  const [histCargado, setHistCargado] = useState(false);
  const [errHist, setErrHist] = useState<string | null>(null);

  const cargarHistorial = useCallback(async () => {
    setCargandoHist(true); setErrHist(null);
    const [{ data: aud, error: eAud }, salRes] = await Promise.all([
      supabase.from("correcciones_auditoria")
        .select("id, campo_modificado, valor_anterior, valor_nuevo, corregido_at, motivo, corregido_por")
        .eq("persona_id", id).order("corregido_at", { ascending: false }).limit(100),
      puedeSalario
        ? supabase.rpc("fn_historial_salario", { p_persona_id: id })
        : Promise.resolve({ data: [] as TramoSalarioHist[], error: null }),
    ]);
    if (eAud) { setErrHist(mensajeDeError(eAud)); setCargandoHist(false); return; }
    const filas = ((aud as AuditoriaFila[] | null) ?? []).filter((f) => !CAMPO_MARCAJE_EXCLUIR.has(f.campo_modificado));
    // Nombre de quién corrigió: se resuelve aparte, sin depender de un embed de
    // PostgREST (el schema cache de este proyecto los tiene trabados para
    // varias relaciones — mismo motivo que ya documenta correcciones/page.tsx).
    const idsQuien = Array.from(new Set(filas.map((f) => f.corregido_por).filter(Boolean)));
    let nombres = new Map<string, string>();
    if (idsQuien.length > 0) {
      const { data: gente } = await supabase.from("personas").select("id, nombres, apellidos").in("id", idsQuien);
      nombres = new Map(((gente as { id: string; nombres: string; apellidos: string }[] | null) ?? []).map((g) => [g.id, `${g.nombres} ${g.apellidos}`]));
    }
    const eventosAuditoria: HistorialEvento[] = filas.map((f) => ({
      id: f.id,
      fechaOrden: f.corregido_at,
      fechaMostrar: selloLima(f.corregido_at),
      titulo: CAMPO_LABEL[f.campo_modificado] ?? f.campo_modificado,
      detalle: f.valor_anterior || f.valor_nuevo ? `${f.valor_anterior ?? "—"} → ${f.valor_nuevo ?? "—"}` : undefined,
      motivo: f.motivo || undefined,
      quien: nombres.get(f.corregido_por),
    }));
    const tramosSal = salRes.error ? [] : ((salRes.data as TramoSalarioHist[] | null) ?? []);
    const eventosSalario: HistorialEvento[] = tramosSal.map((t, i) => ({
      id: `sal-${i}-${t.vigente_desde}`,
      fechaOrden: t.vigente_desde,
      fechaMostrar: fechaCorta(t.vigente_desde),
      titulo: "Salario",
      detalle: `${RANGO_LABEL[t.rango] ?? t.rango} · ${formatSoles(t.salario_mensual_soles)}`,
      motivo: t.nota || undefined,
    }));
    const eventoIngreso: HistorialEvento[] = persona
      ? [{ id: "ingreso", fechaOrden: persona.fecha_ingreso, fechaMostrar: fechaCorta(persona.fecha_ingreso), titulo: "Ingreso a CAYLA" }]
      : [];
    setHistorial([...eventosAuditoria, ...eventosSalario, ...eventoIngreso].sort((a, b) => b.fechaOrden.localeCompare(a.fechaOrden)));
    setHistCargado(true);
    setCargandoHist(false);
  }, [supabase, id, puedeSalario, persona]);

  // Cambiar de pestaña es un evento (un clic), no un cambio de estado externo
  // que haya que "sincronizar" — por eso la carga perezosa de cada pestaña
  // vive acá y no en un useEffect que observe `tab`. Antes sí era un efecto,
  // y react-hooks/set-state-in-effect lo marca con razón: llamar a un
  // setState async dentro del cuerpo de un efecto encadena renders que acá
  // no hacían falta, porque ya se sabe exactamente cuál fue el evento que
  // debía disparar la carga (el clic en la pestaña).
  function irATab(t: Tab) {
    setTab(t);
    if ((t === "asistencia" || t === "desempeno") && !desCargado && !cargandoDes) void cargarDesempeno();
    if (t === "historial" && !histCargado && !cargandoHist) void cargarHistorial();
  }

  // Un día no puede tener más de 24 h: si las tiene, es un AGREGADO del histórico 2025
  // (mes entero en una fecha). Suma al total pero no al promedio ni al gráfico.
  const stats = useMemo(() => {
    const esAgregado = (j: Jornada) => (j.horas_trabajadas ?? 0) > 24;
    const agregados = jornadas.filter(esAgregado);
    const reales = jornadas.filter((j) => !esAgregado(j));
    const totalHoras = jornadas.reduce((s, j) => s + (j.horas_trabajadas ?? 0), 0);
    const horasAgregadas = agregados.reduce((s, j) => s + (j.horas_trabajadas ?? 0), 0);
    const diasTrabajados = reales.filter((j) => (j.horas_trabajadas ?? 0) > 0).length;
    const diasTardeMedidos = jornadas.filter((j) => j.minutos_tarde !== null).length;
    const tardanzas = jornadas.filter((j) => (j.minutos_tarde ?? 0) > 0 && !levTard.has(j.fecha)).length;
    return {
      esAgregado, agregados, totalHoras, horasAgregadas,
      horasReales: totalHoras - horasAgregadas,
      diasTrabajados,
      diasTardeMedidos,
      tardanzas,
      // % de días medidos sin tardanza. Sin días medidos no hay con qué
      // calcularlo — "—" y no "100%", que sería un dato inventado.
      puntualidadPct: diasTardeMedidos > 0 ? Math.round(((diasTardeMedidos - tardanzas) / diasTardeMedidos) * 100) : null,
      diasSalidaMedidos: jornadas.filter((j) => j.minutos_salida_temprana !== null).length,
      salidasTempranas: jornadas.filter((j) => (j.minutos_salida_temprana ?? 0) > 0).length,
      horasExtra: jornadas.reduce((s, j) => s + (j.horas_extra_detectadas ?? 0), 0),
      datosGrafico: reales.map((j) => ({ fecha: j.fecha, horas: j.horas_trabajadas ?? 0 })) as DiaGrafico[],
    };
  }, [jornadas, levTard]);

  const objCumplidos = objetivos.filter((o) => o.cumplido).length;
  const objNivel = lecturaObjetivos(objCumplidos, objetivos.length);
  const objPct = objetivos.length > 0 ? Math.round((objCumplidos / objetivos.length) * 100) : 0;
  const objMesLabel = `${MESES[Number(hasta.slice(5, 7)) - 1]} ${hasta.slice(0, 4)}`;

  function incidencia(j: Jornada): string | null {
    if (j.estado === "auto_cerrada_pendiente") return "Auto-cerrada";
    if (j.entrada_ts && !j.salida_final_ts) return "Sin salida";
    return null;
  }

  // "Mi firma": solo en TU propio perfil, si puedes firmar (admin/líder).
  const esMiPerfil = !!yo && yo.id === id;

  // La segunda puerta a «Registrar una falta» (la otra está en Disciplina,
  // decidido el 2026-10-06): llega con esta persona ya elegida. Solo se ofrece
  // si la base la va a aceptar — a quién se le puede registrar, 0510.
  const [registrandoFalta, setRegistrandoFalta] = useState(false);
  const yoRegistra = useMemo(
    () => (yo ? { id: yo.id, rol: yo.rol, sedeBaseId: yo.sedeBaseId, enPlanilla: yo.enPlanilla } : null), [yo]);
  const personaFija = useMemo(
    () => (persona ? { id: persona.id, nombre: `${persona.nombres} ${persona.apellidos}` } : undefined), [persona]);
  const puedeRegistrarFalta = !!yoRegistra && !!persona && puedeRegistrarleConducta(yoRegistra, persona);

  // Alertas del resumen (0428): solo lo que de verdad exige mirar, no un
  // resumen de todo. Vacaciones vencidas o por vencer en 60 días (mismo
  // umbral que ya pintaba ámbar la sección de abajo) y contrato vencido o por
  // vencer en 30. No incluye los `err*` de carga: esos ya tienen su propio
  // aviso en la sección que falló, y duplicarlos acá los haría parecer una
  // alerta de negocio en vez de un problema de conexión.
  const alertas: string[] = [];
  if (vacas?.records_vencidos) alertas.push(`${vacas.records_vencidos} récord${vacas.records_vencidos === 1 ? "" : "s"} de vacaciones ya vencido${vacas.records_vencidos === 1 ? "" : "s"}.`);
  else if (vacas?.vence_el && (vacas.dias_para_vencer ?? 999) <= 60) alertas.push(`Vacaciones vencen el ${fechaCorta(vacas.vence_el)}.`);
  if (contrato?.ya_vencio) alertas.push(`Contrato vencido el ${fechaCorta(contrato.fecha_fin_contrato)}.`);
  else if (contrato && contrato.dias_restantes <= 30) alertas.push(`Contrato vence el ${fechaCorta(contrato.fecha_fin_contrato)} (${contrato.dias_restantes} días).`);

  if (rol !== null && !puede) {
    return (
      <div className="flex flex-1 flex-col">
        <main className="flex flex-1 items-center justify-center p-6"><p className="max-w-md text-center text-taupe">No tienes permiso para ver perfiles.</p></main>
      </div>
    );
  }

  const nombre = persona ? `${persona.nombres} ${persona.apellidos}` : "";
  const iniciales = persona ? `${persona.nombres[0] ?? ""}${persona.apellidos[0] ?? ""}` : "";
  const tieneFotosDni = !!(ficha?.foto_dni_anverso_ruta || ficha?.foto_dni_reverso_ruta);
  const rutaCaraDni = (cara: CaraDni): string | null =>
    cara === "anverso" ? ficha?.foto_dni_anverso_ruta ?? null : ficha?.foto_dni_reverso_ruta ?? null;

  // ── Bloques reutilizados entre la pestaña interactiva y el PDF ───────────
  // Funciones simples que DEVUELVEN jsx — no componentes (no se usan como
  // `<Algo/>`), así que definirlas acá adentro no las remonta en cada
  // cambio de pestaña como sí le pasaba a TabBtn/AvisoNoSeCargo arriba.
  function bloqueDatosPersonales(conAcciones: boolean) {
    return errFicha ? (
      <AvisoNoSeCargo que="la ficha" motivo={errFicha} noSignifica="esté sin llenar" reintentar={reintentar} />
    ) : ficha ? (
      <div>
        <Dato label="Celular" valor={ficha.celular} />
        <Dato label="Correo" valor={persona?.email} />
        <details className="mt-2">
          <summary className="cursor-pointer text-sm text-tinta hover:underline">Ver información completa</summary>
          <div className="mt-1">
            <Dato label="Dirección" valor={ficha.direccion} />
            <Dato label="Nacimiento" valor={ficha.fecha_nacimiento ? fechaCorta(ficha.fecha_nacimiento) : "—"} />
            <Dato label="Género" valor={etiquetaDeCatalogo(ficha.genero, GENERO_LABELS)} />
            <Dato label="Estado civil" valor={etiquetaDeCatalogo(ficha.estado_civil, ESTADO_CIVIL_LABELS)} />
            <Dato label="Grado de instrucción" valor={etiquetaDeCatalogo(ficha.grado_instruccion, GRADO_INSTRUCCION_LABELS)} />
            <Dato label="Hijos menores" valor={ficha.hijos_menores == null ? "—" : ficha.hijos_menores ? "Sí" : "No"} />
            <Dato label="Banco" valor={ficha.entidad_bancaria} />
            <Dato label="N.° de cuenta" valor={ficha.numero_cuenta} />
            {ficha.foto_personal_url && <Dato label="Foto" valor={<a href={ficha.foto_personal_url} target="_blank" rel="noreferrer" className="text-tinta underline">ver</a>} />}
          </div>
        </details>
        {puedeIdentidad && (
          <div className={conAcciones ? "no-print mt-3 rounded-xl border border-sand bg-hueso p-3" : "mt-3 rounded-xl border border-sand bg-hueso p-3"}>
            <div className="flex items-center justify-between gap-3">
              <Dato label="Fotos del DNI" valor={tieneFotosDni ? "Cargadas y aprobadas" : "—"} />
              {conAcciones && tieneFotosDni && (
                <div className="flex flex-wrap items-center justify-end gap-2">
                  {/* Ver va a la vista y cancelar queda dentro del «•••»: lo
                      cotidiano es mirar el documento, lo excepcional es borrarlo. */}
                  {CARAS_DNI.map((cara) => {
                    const ruta = rutaCaraDni(cara.clave);
                    return ruta ? (
                      <Boton key={cara.clave} variante="secundario" tamano="sm" onClick={() => void verCaraDni(ruta)}>
                        Ver {cara.etiqueta.toLowerCase()}
                      </Boton>
                    ) : null;
                  })}
                  <Menu trigger={({ alternar, abierto }) => (
                    <Boton variante="sutil" tamano="sm" onClick={alternar} aria-haspopup="menu" aria-expanded={abierto} aria-label="Más acciones del DNI">•••</Boton>
                  )}>
                    <MenuItem variante="peligro" onClick={() => setMostrandoCancelarDni(true)}>Cancelar documento</MenuItem>
                  </Menu>
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    ) : (
      <p className="text-sm text-taupe">Sin ficha cargada. <Link href="/admin/datos-personales" className="text-tinta hover:underline">Completar</Link>.</p>
    );
  }

  function bloqueCompensacion() {
    return errSalario ? (
      <AvisoNoSeCargo que="el historial de salario" motivo={errSalario} noSignifica="no tenga sueldo asignado" reintentar={reintentar} />
    ) : salario ? (
      <div>
        <Dato label="Sueldo vigente" valor={<strong>{soles(salario.salario_mensual_soles)}</strong>} />
        <Dato label="Rango" valor={RANGO_LABEL[salario.rango] ?? salario.rango} />
        <Dato label="Desde" valor={selloLima(salario.vigente_desde)} />
      </div>
    ) : (
      <p className="text-sm text-taupe">Sin salario asignado.</p>
    );
  }

  function bloqueVacacionesContrato() {
    return (
      <>
        {errVacas ? (
          <AvisoNoSeCargo que="el saldo de vacaciones" motivo={errVacas} noSignifica="no tenga días pendientes" reintentar={reintentar} />
        ) : vacas ? (
          <div>
            <Dato label="Días pendientes" valor={<strong>{vacas.dias_pendientes} días</strong>} />
            {vacas.vence_el && (
              <Dato
                label="Récord más antiguo vence"
                valor={
                  <span className={(vacas.dias_para_vencer ?? 999) <= 60 ? "font-medium text-ambar" : undefined}>
                    {fechaCorta(vacas.vence_el)}
                    {typeof vacas.dias_para_vencer === "number" && ` (${vacas.dias_para_vencer >= 0 ? `faltan ${vacas.dias_para_vencer} días` : "vencido"})`}
                  </span>
                }
              />
            )}
            {vacas.records_vencidos > 0 && (
              <Dato label="Récords ya vencidos" valor={<span className="text-rojo">{vacas.records_vencidos}</span>} />
            )}
          </div>
        ) : (
          <p className="text-sm text-taupe">Sin días de vacaciones pendientes.</p>
        )}
        {errContrato ? (
          <div className={vacas || errVacas ? "mt-3 border-t border-sand/60 pt-3" : ""}>
            <AvisoNoSeCargo que="el contrato por vencer" motivo={errContrato} noSignifica="no tenga un contrato a plazo fijo por vencer" reintentar={reintentar} />
          </div>
        ) : contrato && (
          <div className={vacas ? "mt-3 border-t border-sand/60 pt-3" : ""}>
            <Dato
              label={contrato.ya_vencio ? "Contrato vencido el" : "Contrato a plazo fijo vence el"}
              valor={
                <span className={contrato.ya_vencio ? "font-medium text-rojo" : "font-medium text-ambar"}>
                  {fechaCorta(contrato.fecha_fin_contrato)}
                  {!contrato.ya_vencio && ` (${contrato.dias_restantes} días)`}
                </span>
              }
            />
          </div>
        )}
      </>
    );
  }

  function bloqueLegajo() {
    return (
      <>
        {puedeRegistrarFalta && (
          <div className="mb-3">
            <Boton tamano="sm" onClick={() => setRegistrandoFalta(true)}>Registrar una falta</Boton>
          </div>
        )}
        {listaLegajo()}
      </>
    );
  }

  function listaLegajo() {
    return errDocs ? (
      <AvisoNoSeCargo que="el legajo disciplinario" motivo={errDocs} noSignifica="no tenga antecedentes" reintentar={reintentar} />
    ) : docs.length === 0 ? (
      <p className="text-sm text-taupe">Sin antecedentes disciplinarios. Buena señal.</p>
    ) : (
      <ul className="divide-y">
        {docs.map((d) => (
          <li key={d.id} className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 py-2 text-sm">
            <span>
              <strong>{NIVEL[d.nivel] ?? d.nivel}</strong> <span className="text-taupe">· {CAUSAL[d.tipo_causal] ?? d.tipo_causal}</span>
              {d.correlativo && <span className="ml-2 text-xs text-taupe">{d.correlativo}</span>}
            </span>
            <span className="flex items-center gap-2 text-xs text-taupe">
              {selloLima(d.firmado_at ?? d.creado_at)}
              <Insignia
                variante={d.estado === "borrador" ? "advertencia" : "neutral"}
                atenuada={d.estado === "anulado" || d.estado === "cerrado_sin_entrega"}
                punto={false}
              >
                {ESTADO_DOC[d.estado] ?? d.estado}
              </Insignia>
              <Link href={`/admin/disciplina/memo/${d.id}`} className="text-tinta hover:underline">ver</Link>
            </span>
          </li>
        ))}
      </ul>
    );
  }

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        <style>{`
          .solo-print{display:none}
          .imprimible{display:none}
          @page{margin:16mm}
          @media print{
            header,.no-print{display:none!important}
            .solo-print{display:flex!important}
            .imprimible{display:block!important}
            body{background:#fff!important}
            main{padding:0!important}
            section{break-inside:avoid;background:#fff!important}
            .colibri{print-color-adjust:exact;-webkit-print-color-adjust:exact}
          }
        `}</style>
        <div className="no-print mb-4 flex flex-wrap items-center justify-between gap-3">
          <button onClick={() => router.back()} className="text-sm text-taupe hover:text-tinta">← Volver</button>
        </div>
        {persona && (
          <div className="solo-print mb-6 items-center gap-3 border-b border-sand pb-4">
            <span className="colibri w-10 text-rojo" aria-hidden />
            <div>
              <div className="font-serif text-xl">Ficha de {ficha?.nombre_dni || nombre}</div>
              <div className="text-xs text-taupe">CAYLA · Dynamic · {new Date().toLocaleDateString("es-PE", { day: "2-digit", month: "long", year: "numeric" })}</div>
            </div>
          </div>
        )}

        {cargando ? (
          <Cargando texto="Cargando el perfil…" />
        ) : err ? (
          <div className="max-w-xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
            <p>{err}</p>
            {errReintentable && (
              <p className="mt-1">
                <Boton variante="enlace" className="no-print" onClick={reintentar}>Reintentar</Boton>
              </p>
            )}
          </div>
        ) : persona && (
          <>
            {/* Cabecera fija del colaborador */}
            <div className="mb-4 flex flex-wrap items-start justify-between gap-4">
              <div className="flex items-center gap-4">
                <div className="flex h-16 w-16 shrink-0 items-center justify-center rounded-full bg-rojo/10 font-serif text-2xl text-rojo">{iniciales.toUpperCase()}</div>
                <div className="min-w-0">
                  <h1 className="font-serif text-2xl leading-tight">{ficha?.nombre_dni || nombre}</h1>
                  <p className="text-sm text-taupe">
                    {persona.funcion} · Sede {errSede ? <span className="text-rojo">no se pudo cargar</span> : sede || "—"}
                    {persona.estado !== "activo" && <Insignia atenuada punto={false} className="ml-2">{persona.estado}</Insignia>}
                    {persona.sueldo_fijo && <Insignia punto={false} className="ml-2">sueldo fijo</Insignia>}
                    {/* Estar marcada como dirección le quita un derecho —no genera
                        sobretiempo, art. 5 del D.S. 007-2002-TR— así que tiene que
                        verse. Se marca por SQL, igual que sueldo_fijo y en_planilla;
                        lo que no puede pasar es que además sea invisible: un permiso
                        que nadie ve es un permiso que nadie audita. */}
                    {persona.personal_direccion && (
                      <span title="Personal de dirección (art. 5, D.S. 007-2002-TR): fuera de la jornada máxima de 48 h, no genera sobretiempo. Sí le corresponde el descanso semanal.">
                        <Insignia punto={false} className="ml-2">dirección</Insignia>
                      </span>
                    )}
                    {!persona.en_planilla && <Insignia variante="advertencia" punto={false} className="ml-2">fuera de planilla</Insignia>}
                    {cuentaServicio && (
                      <span title="Estación de Retail (0490): no es una persona. No se paga, no aparece en el terminal de marcaje ni en las listas del equipo.">
                        <Insignia variante="advertencia" punto={false} className="ml-2">cuenta de servicio</Insignia>
                      </span>
                    )}
                  </p>
                  {/* El motivo va en el CUERPO, no en un `title`. Esta ficha se
                      abre en el iPad de la sede —donde no hay puntero que
                      despliegue un tooltip— y se imprime en PDF, donde un `title`
                      tampoco sale: ahí «no se pudo cargar» quedaba sin porqué. */}
                  {errSede && (
                    <p className="mt-0.5 text-xs text-rojo">
                      No se pudo cargar la sede: {errSede}. Esto <strong>no</strong> quiere decir que no tenga sede asignada.{" "}
                      <Boton variante="enlace" className="no-print" onClick={reintentar}>Reintentar</Boton>
                    </p>
                  )}
                  <p className="mt-0.5 text-xs text-taupe">DNI {persona.documento ?? "—"} · Ingresó {fechaCorta(persona.fecha_ingreso)}</p>
                </div>
              </div>
              <div className="no-print flex items-center gap-2">
                {puedeSalario && (
                  <label className="flex items-center gap-1.5 text-xs text-taupe">
                    <input type="checkbox" checked={incluirSueldo} onChange={(e) => setIncluirSueldo(e.target.checked)} className="h-3.5 w-3.5 accent-tinta" />
                    Incluir sueldo en el PDF
                  </label>
                )}
                <Boton variante="primario" tamano="sm" onClick={() => setTimeout(() => window.print(), 60)}>Descargar PDF</Boton>
                {/* Acciones de bajo uso: esta pantalla solo LEE y consolida —
                    editar, dar de PIN nuevo o registrar una salida escriben por
                    RPCs que ya viven en Equipo, y repetirlas acá sería la misma
                    pregunta resuelta dos veces. El menú manda de vuelta a donde
                    esas acciones ya existen, en vez de reconstruirlas. */}
                <Menu trigger={({ alternar, abierto }) => (
                  <Boton variante="secundario" tamano="sm" onClick={alternar} aria-haspopup="menu" aria-expanded={abierto}>•••</Boton>
                )}>
                  <MenuItem href="/admin/equipo">Editar, PIN o registrar salida (en Equipo)</MenuItem>
                  {puedeMarcarServicio && cuentaServicio !== null && (
                    <MenuItem onClick={() => setCambiandoServicio(true)} variante={cuentaServicio ? "normal" : "peligro"}>
                      {cuentaServicio ? "Es una persona: desmarcar cuenta de servicio" : "No es una persona: marcar como cuenta de servicio"}
                    </MenuItem>
                  )}
                </Menu>
              </div>
            </div>

            {/* Pestañas */}
            <div role="tablist" className="no-print mb-6 flex gap-1 overflow-x-auto border-b border-sand">
              <TabBtn valor="resumen" tab={tab} setTab={irATab}>Resumen</TabBtn>
              <TabBtn valor="asistencia" tab={tab} setTab={irATab}>Asistencia</TabBtn>
              <TabBtn valor="desempeno" tab={tab} setTab={irATab}>Desempeño</TabBtn>
              {puedeSalario && <TabBtn valor="compensacion" tab={tab} setTab={irATab}>Compensación</TabBtn>}
              <TabBtn valor="documentos" tab={tab} setTab={irATab}>Documentos</TabBtn>
              <TabBtn valor="historial" tab={tab} setTab={irATab}>Historial</TabBtn>
            </div>

            {tab === "resumen" && (
              <div className="no-print grid gap-5 lg:grid-cols-2">
                <TarjetaInfo como="section" titulo="Situación laboral">
                  <Dato label="Rol / cargo" valor={persona.funcion} />
                  <Dato label="Sede" valor={errSede ? <span className="text-rojo">no se pudo cargar</span> : sede || "—"} />
                  <Dato label="Tipo de vínculo" valor={TIPO_VINCULO_LABEL[persona.tipo_vinculo as keyof typeof TIPO_VINCULO_LABEL] ?? persona.tipo_vinculo} />
                  <Dato label="Ingreso" valor={fechaCorta(persona.fecha_ingreso)} />
                  <Dato label="En planilla" valor={persona.en_planilla ? "Sí" : "No"} />
                </TarjetaInfo>

                <TarjetaInfo como="section" titulo="Contacto" accion={<Link href="/admin/datos-personales" className="text-xs text-tinta hover:underline">Editar →</Link>}>
                  {bloqueDatosPersonales(false)}
                </TarjetaInfo>

                <TarjetaInfo como="section" titulo="Contrato y vacaciones" accion={<Link href="/admin/contratos" className="text-xs text-tinta hover:underline">Contratos →</Link>}>
                  {bloqueVacacionesContrato()}
                </TarjetaInfo>

                {puedeSalario && (
                  <TarjetaInfo como="section" titulo="Compensación" accion={<Boton variante="enlace" onClick={() => setTab("compensacion")}>Ver más →</Boton>}>
                    {bloqueCompensacion()}
                  </TarjetaInfo>
                )}

                <TarjetaInfo como="section" titulo="Documentación" accion={<Boton variante="enlace" onClick={() => setTab("documentos")}>Ver más →</Boton>}>
                  <Dato label="Legajo disciplinario" valor={errDocs ? <span className="text-rojo">no se pudo cargar</span> : docs.length === 0 ? "Sin antecedentes" : `${docs.length} registro${docs.length === 1 ? "" : "s"}`} />
                  {puedeIdentidad && <Dato label="Fotos del DNI" valor={tieneFotosDni ? "Cargadas y aprobadas" : "—"} />}
                </TarjetaInfo>

                <TarjetaInfo como="section" titulo="Alertas" className="lg:col-span-2">
                  {alertas.length === 0 ? (
                    <p className="text-sm text-taupe">Sin alertas relevantes.</p>
                  ) : (
                    <ul className="space-y-1 text-sm">
                      {alertas.map((a) => (
                        <li key={a} className="flex items-start gap-2 text-ambar"><span aria-hidden>●</span> {a}</li>
                      ))}
                    </ul>
                  )}
                </TarjetaInfo>
              </div>
            )}

            {tab === "asistencia" && (
              <div className="no-print">
                <div className="mb-6 flex flex-wrap items-end gap-4">
                  <Campo etiqueta="Desde" type="date" value={desde} onChange={(e) => setDesde(e.target.value)} />
                  <Campo etiqueta="Hasta" type="date" value={hasta} onChange={(e) => setHasta(e.target.value)} />
                  <Boton variante="primario" tamano="lg" cargando={cargandoDes} onClick={() => void cargarDesempeno()}>
                    Actualizar
                  </Boton>
                </div>

                {errDes && (
                  <div className="mb-6 max-w-2xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
                    No se pudo cargar la asistencia: {errDes}{" "}
                    <Boton variante="enlace" onClick={() => void cargarDesempeno()}>Reintentar</Boton>
                  </div>
                )}

                {errParcialAsistencia.length > 0 && (
                  <div className="mb-6 max-w-2xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
                    <p>El periodo se cargó, pero faltó parte de lo que se muestra:</p>
                    <ul className="mt-1 list-disc pl-5">
                      {errParcialAsistencia.map((t) => <li key={t}>No se pudieron cargar {t}.</li>)}
                    </ul>
                    <Boton variante="enlace" className="mt-1" onClick={() => void cargarDesempeno()}>Reintentar</Boton>
                  </div>
                )}

                {!desCargado && cargandoDes && <Cargando texto="Cargando su asistencia…" />}

                {desCargado && (
                  <>
                    <div className="mb-3 grid grid-cols-2 gap-3 sm:grid-cols-4">
                      {[
                        { label: "Horas trabajadas", valor: fmtHoras(stats.totalHoras) },
                        { label: "Días trabajados", valor: String(stats.diasTrabajados) },
                        { label: "Tardanzas", valor: `${stats.tardanzas} de ${stats.diasTardeMedidos} medidos` },
                        { label: "Tiempo adicional", valor: stats.horasExtra > 0 ? `+${fmtHoras(stats.horasExtra)}` : "—" },
                      ].map((c) => (
                        <Cifra key={c.label} etiqueta={c.label} valor={c.valor} />
                      ))}
                    </div>
                    <div className="mb-6 flex flex-wrap gap-x-6 gap-y-1 text-sm text-taupe">
                      <span>Puntualidad <strong className="text-tinta">{stats.puntualidadPct == null ? "—" : `${stats.puntualidadPct}%`}</strong></span>
                      <span>Salidas anticipadas <strong className="text-tinta">{stats.salidasTempranas} de {stats.diasSalidaMedidos} medidos</strong></span>
                      <span>Promedio por día <strong className="text-tinta">{stats.diasTrabajados ? fmtHoras(stats.horasReales / stats.diasTrabajados) : "—"}</strong></span>
                    </div>

                    {stats.agregados.length > 0 && (
                      <p className="mb-6 max-w-3xl text-xs text-taupe">
                        Incluye <strong>{stats.agregados.length} registro{stats.agregados.length === 1 ? "" : "s"} histórico{stats.agregados.length === 1 ? "" : "s"} de 2025</strong> ({fmtHoras(stats.horasAgregadas)}):
                        el total de un mes completo guardado en una sola fecha, porque en 2025 todavía no había marcaje diario.
                        Suman al <strong>total del periodo</strong> (y la planilla los usó para CTS y gratificación),
                        pero no cuentan como día, así que quedan fuera del promedio y del gráfico.
                      </p>
                    )}

                    <TarjetaInfo titulo="Horas por día" className="mb-8">
                      <GraficoHoras dias={stats.datosGrafico} meta={META_DIA} />
                    </TarjetaInfo>

                    <Tabla>
                      <TablaEncabezado>
                        <Th>Fecha</Th>
                        <Th>Entrada</Th>
                        <Th>Salida</Th>
                        <Th>Horas</Th>
                        <Th>Tardanza</Th>
                        <Th>Sal. antic.</Th>
                        <Th>T. adicional</Th>
                        <Th>Incidencia</Th>
                      </TablaEncabezado>
                      <tbody>
                        {jornadas.length === 0 ? (
                          <tr><td colSpan={8} className="px-4 py-6 text-center text-taupe">Sin jornadas en el periodo.</td></tr>
                        ) : (
                          jornadas.map((j) => {
                            const inc = incidencia(j);
                            return (
                              <Fila key={j.fecha}>
                                <td className="px-4 py-2.5 capitalize">
                                  {fechaLarga(j.fecha)}
                                  {stats.esAgregado(j) && (
                                    <Insignia atenuada punto={false} className="ml-2 whitespace-nowrap normal-case">total del mes · histórico 2025</Insignia>
                                  )}
                                </td>
                                <td className="px-4 py-2.5">{horaLima(j.entrada_ts)}</td>
                                <td className="px-4 py-2.5">{horaLima(j.salida_final_ts)}</td>
                                <td className="px-4 py-2.5">{j.horas_trabajadas != null ? fmtHoras(j.horas_trabajadas) : "—"}</td>
                                <td className="px-4 py-2.5">
                                  {j.minutos_tarde ? (
                                    levTard.has(j.fecha)
                                      ? <span className="text-taupe" title="Tardanza levantada"><s>{j.minutos_tarde} min</s> · levantada</span>
                                      : <span className="font-medium text-rojo">{j.minutos_tarde} min tarde</span>
                                  ) : <span className="text-taupe">—</span>}
                                </td>
                                <td className="px-4 py-2.5">
                                  {j.minutos_salida_temprana ? <span className="text-ambar">{j.minutos_salida_temprana} min</span> : <span className="text-taupe">—</span>}
                                </td>
                                <td className="px-4 py-2.5">
                                  {j.horas_extra_detectadas && j.horas_extra_detectadas > 0 ? <span className="font-medium text-verde">+{fmtHoras(j.horas_extra_detectadas)}</span> : <span className="text-taupe">—</span>}
                                </td>
                                <td className="px-4 py-2.5">
                                  {inc ? (
                                    <Link href={`/admin/correcciones?persona=${id}&fecha=${j.fecha}`} className="font-medium text-rojo underline decoration-rojo/30 underline-offset-2 hover:decoration-rojo">{inc} ›</Link>
                                  ) : <span className="text-taupe">—</span>}
                                </td>
                              </Fila>
                            );
                          })
                        )}
                      </tbody>
                    </Tabla>

                    <div className="mt-6 flex flex-wrap items-center gap-2 text-sm">
                      <span className="py-1 text-taupe">Registro de {persona.nombres}:</span>
                      {/* Desde hoy /admin/horas es la tabla de TODO el equipo y
                          ?persona= abre su panel encima, no recorta la tabla. El
                          enlace ya no promete «solo esta persona» — promete verla
                          al lado de las demás, que es para lo que se usa. */}
                      <Link href={`/admin/horas?persona=${persona.id}`} className="rounded-xl border border-sand bg-papel px-3 py-1 transition-all hover:-translate-y-0.5 hover:border-taupe">Junto al equipo</Link>
                      <Link href={`/admin/incidencias?persona=${persona.id}`} className="rounded-xl border border-sand bg-papel px-3 py-1 transition-all hover:-translate-y-0.5 hover:border-taupe">Incidencias</Link>
                    </div>
                  </>
                )}
              </div>
            )}

            {tab === "desempeno" && (
              <div className="no-print">
                {errParcialDesempeno.length > 0 && (
                  <div className="mb-6 max-w-2xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
                    {errParcialDesempeno.map((t) => <p key={t}>No se pudieron cargar {t}.</p>)}
                    <Boton variante="enlace" className="mt-1" onClick={() => void cargarDesempeno()}>Reintentar</Boton>
                  </div>
                )}
                {!desCargado && cargandoDes && <Cargando texto="Cargando sus objetivos…" />}
                {desCargado && (
                  objetivos.length > 0 ? (
                    <TarjetaInfo
                      titulo={`Objetivos de ${objMesLabel.toLowerCase()}`}
                      accion={
                        <span className="flex items-center gap-2 text-sm">
                          <span className="text-taupe">{objCumplidos}/{objetivos.length} cumplidos</span>
                          {/* Antes esto pintaba «Plus 21%» en verde. Desde la
                              0171 los objetivos no pagan: la etiqueta dice el
                              porcentaje cumplido y el color ya no premia. */}
                          <Insignia punto={false}>{objNivel.etiqueta}</Insignia>
                        </span>
                      }
                      className="max-w-3xl"
                    >
                      <div className="mb-3 h-2 overflow-hidden rounded-full bg-sand">
                        <div className={`h-full rounded-full ${objPct >= 60 ? "bg-verde" : objPct >= 30 ? "bg-ambar" : "bg-rojo"}`} style={{ width: `${objPct}%` }} />
                      </div>
                      <ul className="space-y-1 text-sm">
                        {objetivos.map((o) => (
                          <li key={o.id} className="flex items-start gap-2">
                            {/* text-taupe sin diluir: al 50% de opacidad este círculo
                                quedaba en ~1.8:1 sobre papel, muy por debajo de AA. */}
                            <span className={o.cumplido ? "text-verde" : "text-taupe"}>{o.cumplido ? "✓" : "○"}</span>
                            <span className={o.cumplido ? "text-taupe line-through" : ""}>{o.descripcion}</span>
                          </li>
                        ))}
                      </ul>
                      <p className="mt-3 text-xs text-taupe">Cambia el mes desde la pestaña Asistencia (el rango «Hasta» decide el mes que se lee acá).</p>
                    </TarjetaInfo>
                  ) : (
                    <p className="text-sm text-taupe">
                      Sin objetivos cargados para {objMesLabel.toLowerCase()}. Evaluaciones, competencias y feedback
                      todavía no existen como dato en Dynamic — cuando existan, viven acá y no en Asistencia.
                    </p>
                  )
                )}
              </div>
            )}

            {tab === "compensacion" && puedeSalario && (
              <div className="no-print max-w-xl">
                <TarjetaInfo como="section" titulo="Compensación vigente" accion={<Link href="/admin/planilla" className="text-xs text-tinta hover:underline">Planilla →</Link>}>
                  {bloqueCompensacion()}
                </TarjetaInfo>
                <p className="mt-3 text-sm text-taupe">
                  El historial completo de tramos —con quién lo asignó y por qué— está en la pestaña <Boton variante="enlace" onClick={() => irATab("historial")}>Historial</Boton>.
                </p>
              </div>
            )}

            {tab === "documentos" && (
              <div className="no-print grid gap-5 lg:grid-cols-2">
                <TarjetaInfo como="section" titulo="Datos personales y DNI" accion={<Link href="/admin/datos-personales" className="text-xs text-tinta hover:underline">Editar →</Link>}>
                  {bloqueDatosPersonales(true)}
                </TarjetaInfo>

                <TarjetaInfo como="section" titulo="Otros documentos">
                  <p className="text-sm text-taupe">
                    Declaración de movilidad, política firmada y cargo del bono de cumpleaños se archivan y
                    revisan desde el tablero de Documentación, junto al resto del equipo.
                  </p>
                  <Link href="/admin/documentacion" className="mt-2 inline-block text-sm text-tinta hover:underline">Ir a Documentación →</Link>
                </TarjetaInfo>

                <TarjetaInfo
                  como="section"
                  titulo={<>Legajo disciplinario {docs.length > 0 && <span className="text-sm font-normal text-taupe">· {docs.length}</span>}</>}
                  accion={<Link href="/admin/disciplina" className="text-xs text-tinta hover:underline">Disciplina →</Link>}
                  className="lg:col-span-2"
                >
                  {bloqueLegajo()}
                </TarjetaInfo>

                {esMiPerfil && puedeSalario && (
                  <TarjetaInfo como="section" titulo="Mi firma" className="lg:col-span-2">
                    <p className="mb-3 text-sm text-taupe">Se imprime en los memos disciplinarios leves (amonestación, suspensión) que tú firmes, y en los contratos de trabajo si eres quien firma por la empresa. Despido/imputación van con firma a mano o digital certificada.</p>
                    <FirmaEditor supabase={supabase} nombreOficial={ficha?.nombre_dni || nombre} avisar={avisar} />
                  </TarjetaInfo>
                )}
              </div>
            )}

            {tab === "historial" && (
              <div className="no-print max-w-3xl">
                {errHist && (
                  <div className="mb-6 rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
                    No se pudo cargar el historial: {errHist}{" "}
                    <Boton variante="enlace" onClick={() => void cargarHistorial()}>Reintentar</Boton>
                  </div>
                )}
                {!histCargado && cargandoHist && <Cargando texto="Cargando su historial…" />}
                {histCargado && (
                  historial.length === 0 ? (
                    <p className="text-sm text-taupe">Sin cambios registrados.</p>
                  ) : (
                    <ul className="relative space-y-4 border-l border-sand pl-5">
                      {historial.map((h) => (
                        <li key={h.id} className="relative">
                          <span className="absolute top-1.5 -left-[23px] size-2.5 rounded-full bg-taupe" aria-hidden />
                          <div className="text-xs text-taupe">{h.fechaMostrar}</div>
                          <div className="text-sm font-medium text-tinta">{h.titulo}</div>
                          {h.detalle && <div className="text-sm text-taupe">{h.detalle}</div>}
                          {h.motivo && <div className="mt-0.5 text-xs text-taupe">Motivo: {h.motivo}</div>}
                          {h.quien && <div className="text-xs text-taupe">Por {h.quien}</div>}
                        </li>
                      ))}
                    </ul>
                  )
                )}
                {!puedeSalario && (
                  <p className="mt-4 text-xs text-taupe">Los cambios de sueldo solo los ve Desarrollo Organizacional.</p>
                )}
              </div>
            )}

            {/* Bloque para el PDF de "Descargar PDF" — independiente de la
                pestaña activa a propósito. Con seis pestañas, imprimir "lo que
                está en pantalla" habría dejado fuera lo que no se estuviera
                mirando en ese momento; esto reúne el mismo contenido que
                imprimía la antigua pestaña "Ficha" (datos, compensación,
                vacaciones/contrato, legajo), sin depender de dónde esté
                parada la persona que hace clic en Descargar PDF. */}
            <div className="imprimible">
              <div className="grid gap-5 lg:grid-cols-2">
                <TarjetaInfo como="section" titulo="Datos personales">
                  {bloqueDatosPersonales(false)}
                </TarjetaInfo>
                {puedeSalario && incluirSueldo && (
                  <TarjetaInfo como="section" titulo="Compensación">
                    {bloqueCompensacion()}
                  </TarjetaInfo>
                )}
                <TarjetaInfo como="section" titulo="Vacaciones y contrato">
                  {bloqueVacacionesContrato()}
                </TarjetaInfo>
                <TarjetaInfo
                  como="section"
                  titulo={<>Legajo disciplinario {docs.length > 0 && <span className="text-sm font-normal text-taupe">· {docs.length}</span>}</>}
                  className="lg:col-span-2"
                >
                  {bloqueLegajo()}
                </TarjetaInfo>
              </div>
            </div>
          </>
        )}
      </main>

      <ModalRegistrarFalta
        abierto={registrandoFalta}
        onCerrar={() => setRegistrandoFalta(false)}
        supabase={supabase}
        yo={yoRegistra}
        personaFija={personaFija}
        // El trámite sigue en Disciplina: se aterriza en el borrador recién
        // creado, abierto en su caso (`#doc-ID`).
        onRegistrado={(docId) => router.push(`/admin/disciplina#doc-${docId}`)}
      />

      <Modal
        abierto={mostrandoCancelarDni}
        onCerrar={cerrarCancelarDni}
        titulo="Cancelar el DNI"
        bloqueado={borrandoDni}
      >
        <p className="text-sm text-taupe">
          Retira las fotos de la ficha y las borra del almacén, dejando constancia de quién y por qué. Es el derecho
          de cancelación que la Ley N.° 29733 le promete a la persona en el texto que aceptó al subirlas. Antes de
          hacerlo, comprueba que no haya obligación de conservarlo —el vínculo vigente y su plazo posterior—: eso lo
          decides tú, no el sistema.
        </p>
        <div className="mt-3">
          <Campo
            etiqueta="Motivo (obligatorio)"
            value={motivoBorrarDni}
            onChange={(e) => setMotivoBorrarDni(e.target.value)}
            placeholder="a petición de quién y bajo qué criterio"
          />
        </div>
        <div className="mt-4 flex justify-end gap-2">
          <Boton variante="secundario" onClick={cerrarCancelarDni} disabled={borrandoDni}>Cancelar</Boton>
          <Boton
            variante="peligro"
            onClick={() => void cancelarDni()}
            cargando={borrandoDni}
            disabled={motivoBorrarDni.trim() === ""}
          >
            Cancelar el DNI
          </Boton>
        </div>
      </Modal>

      {/* Cuenta de servicio (0490). Marcar saca de la planilla: por eso se
          confirma, y por eso la base se niega si esta ficha tiene marcajes. */}
      <Modal
        abierto={cambiandoServicio}
        onCerrar={() => { setCambiandoServicio(false); setMotivoServicio(""); }}
        titulo={cuentaServicio ? "Desmarcar cuenta de servicio" : "Marcar como cuenta de servicio"}
        bloqueado={guardandoServicio}
      >
        <p className="text-sm text-taupe">
          {cuentaServicio
            ? "Esta ficha vuelve a tratarse como una persona: entra otra vez a la planilla, al terminal de marcaje de su sede y a todas las listas del equipo."
            : "Úsalo solo para una estación de Retail (una caja o un almacén compartido), nunca para una persona: deja de pagarse, sale del terminal de marcaje y de todas las listas del equipo. Su acceso a Retail no cambia; a Dynamic ya no podrá entrar."}
        </p>
        <div className="mt-3">
          <Campo
            etiqueta="Motivo (opcional)"
            value={motivoServicio}
            onChange={(e) => setMotivoServicio(e.target.value)}
            placeholder={cuentaServicio ? "por qué es una persona" : "qué estación es"}
          />
        </div>
        <div className="mt-4 flex justify-end gap-2">
          <Boton variante="secundario" onClick={() => { setCambiandoServicio(false); setMotivoServicio(""); }} disabled={guardandoServicio}>Cancelar</Boton>
          <Boton
            variante={cuentaServicio ? "primario" : "peligro"}
            onClick={() => void cambiarCuentaServicio()}
            cargando={guardandoServicio}
          >
            {cuentaServicio ? "Es una persona" : "Marcar como cuenta de servicio"}
          </Boton>
        </div>
      </Modal>
    </div>
  );
}

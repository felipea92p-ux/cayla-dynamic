"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { parseAreas, esOperativaEn, AREA_DEFAULT, type Area } from "@/lib/areas";
import { Cargando } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { Campo, CampoCasilla, CampoSelect } from "@/components/ui/campo";
import { Fila, Tabla, TablaEncabezado, Th } from "@/components/ui/tabla";
import {
  TZ_LIMA, esRolEncargada, hoyLima, formatoMinutos, puedeVerTodasLasSedes,
} from "@cayla-dynamic/shared";
import { esperadoDelDia, horarioVigente, type HorarioTramo, type TurnoDia } from "@/lib/admin/jornada-esperada";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { useFiltroGuardado } from "@/lib/admin/use-filtro-guardado";

const REFRESCO_MS = 30_000;
// Mismo Sheet de siempre si la variable de entorno todavía no está puesta en
// Vercel — así este cambio no puede romper el enlace en producción el día que
// se despliegue antes de cargar la variable.
const URL_SHEET_ASISTENCIA =
  process.env.NEXT_PUBLIC_SHEET_ASISTENCIA_URL ??
  "https://docs.google.com/spreadsheets/d/19jhc5IN0LpbyG00jEwqt4ZB420Ob_rVcGRAdXR88riA/edit";
// Corte mañana/tarde de la meta de cobertura — mismo valor fijo que Turnos (14:15).
const CORTE_TARDE = 14.25;
// Margen antes de avisar que una sede entera no marcó nada. No es la tolerancia
// de tardanza (esa es cero: SIN tolerancia, por minuto, según fn_recalcular_jornada) —
// esta es una franja solo de aviso operativo, y avisar al minuto uno generaría
// más ruido que señal con cualquier desfase normal de la mañana. Se reutiliza
// también para decidir, fila por fila, si alguien "sin marcar" ya debía haber
// llegado o si todavía es pronto — mismo criterio, mismo margen.
const MARGEN_ALERTA_SEDE_MIN = 30;


// Día de la semana (0=domingo … 6=sábado) de un ISO — misma convención que
// metas_cobertura.dia_semana en Turnos.
function diaSemanaDe(iso: string): number {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay();
}

// Hora actual de Lima en decimal (13:30 → 13.5), para saber el tramo vigente.
function horaDecimalLimaAhora(): number {
  const p = new Intl.DateTimeFormat("en-GB", { timeZone: TZ_LIMA, hour: "2-digit", minute: "2-digit", hour12: false }).formatToParts(new Date());
  const h = Number(p.find((x) => x.type === "hour")?.value ?? 0) % 24;
  const m = Number(p.find((x) => x.type === "minute")?.value ?? 0);
  return h + m / 60;
}

function horaLima(ts: string | null): string {
  if (!ts) return "—";
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA,
    hour: "2-digit",
    minute: "2-digit",
    hour12: true,
  }).format(new Date(ts));
}

interface FilaPersona {
  personaId: string;
  nombre: string;
  sede: string;
  sedeId: string;
  estado: string;
  entrada: string | null;
  salidaFinal: string | null;
  minutosTarde: number | null;
  salidaTemprana: number | null;
  enPausaSinRetorno: boolean;
  esOperativa: boolean; // cuenta contra la meta de operativas
  esEncargada: boolean; // supervisor_sede o marca es_encargada_piso
  // Vacaciones, descanso médico u otra ausencia de `ausencias` que cubre HOY.
  // Sin esto, alguien de vacaciones se ve idéntico a un "sin marcar" real en
  // la única pantalla que se mira de un vistazo — el mismo riesgo de falso
  // positivo que la 0101 ya resolvió para el semáforo disciplinario, pero acá
  // nadie lo había cerrado porque esta franja no pasa por fn_faltas_resumen.
  ausenciaHoy: { nombre: string; pendiente: boolean } | null;
  // "08:00" si el horario/turno de hoy dice que le tocaba trabajar; null si le
  // tocaba descanso o no se pudo determinar (misma cascada de jornada-esperada.ts).
  entradaEsperadaHoy: string | null;
  // De dónde salió esa respuesta (turno puntual / horario_por_dia / legacy /
  // sin_horario) — solo importa cuando entradaEsperadaHoy es null, para
  // distinguir "hoy descansa" (una respuesta real) de "no hay con qué medirlo"
  // (no es una respuesta). Ver jornada-esperada.ts:estadoDelDia, que ya hace
  // esta misma distinción para Correcciones/Incidencias.
  origenEsperadoHoy: "turno" | "horario" | "legacy" | "sin_horario";
}

// Estados: verde/ámbar cálidos para lo operativo (van por <Insignia>), Rojo
// lleno para la alerta crítica. "auto_cerrada_pendiente" se queda con su
// propio relleno sólido: es la única variante que necesita el rojo lleno
// (Insignia no tiene una "alerta crítica", solo la translúcida) para pesar
// más que las demás en la fila.
const ESTILO_ESTADO: Record<
  string,
  { label: string; variante?: "positivo" | "advertencia"; atenuada?: boolean; clase?: string }
> = {
  abierta: { label: "Presente", variante: "positivo" },
  en_pausa: { label: "En pausa", variante: "advertencia" },
  cerrada: { label: "Salió", atenuada: true },
  auto_cerrada_pendiente: { label: "Auto-cerrada ⚠", clase: "bg-rojo text-crema" },
  revisada: { label: "Salió (revisada)", atenuada: true },
};

// "08:00" → 8.0, para comparar contra horaDecimalLimaAhora().
function horaDecimalDe(hhmm: string): number {
  const [h, m] = hhmm.slice(0, 5).split(":").map(Number);
  return h + (m || 0) / 60;
}
// "08:00" → "8:00 a. m.", para el mensaje de la alerta.
function horaAmPmDe(hhmm: string): string {
  const [h, m] = hhmm.slice(0, 5).split(":").map(Number);
  return new Intl.DateTimeFormat("es-PE", { hour: "numeric", minute: "2-digit", hour12: true, timeZone: "UTC" }).format(
    new Date(Date.UTC(2000, 0, 1, h, m)),
  );
}

// El hallazgo central de la auditoría de sep-2026: "Sin marcar" cubría tres
// situaciones que no tienen nada que ver entre sí — alguien que entra a las
// 4pm siendo la 1pm se veía IGUAL que alguien que debía entrar a las 8am y no
// llegó. El dato para distinguirlas ya existía (entradaEsperadaHoy, calculado
// arriba con la misma cascada que usa el backend); lo que faltaba era usarlo
// acá. "sin_horario" se deja aparte a propósito: ahí no sabemos si le tocaba
// o no, así que no se afirma "descansa hoy" — sería una falsa tranquilidad
// tan peligrosa como el falso positivo que esto viene a arreglar.
type SubEstadoSinMarcar = "aun_no_inicia" | "falta_real" | "descansa" | "desconocido";
function subEstadoSinMarcar(f: FilaPersona, ahoraDecimal: number): SubEstadoSinMarcar {
  if (f.entradaEsperadaHoy) {
    const yaDebiaHaberLlegado = ahoraDecimal >= horaDecimalDe(f.entradaEsperadaHoy) + MARGEN_ALERTA_SEDE_MIN / 60;
    return yaDebiaHaberLlegado ? "falta_real" : "aun_no_inicia";
  }
  return f.origenEsperadoHoy === "sin_horario" ? "desconocido" : "descansa";
}

// La misma celda de estado, compartida entre la tabla de escritorio y las
// tarjetas de celular — para no mantener dos copias del mismo if/else.
function EstadoCelda({ f, linkCorregir, ahoraDecimal }: { f: FilaPersona; linkCorregir: (personaId: string) => string; ahoraDecimal: number }) {
  // "Sin marcar" es ambiguo a propósito en casos límite: puede ser un no-show
  // real o alguien de vacaciones. Sin esto los dos se veían idénticos en la
  // única pantalla que se mira de un vistazo — mismo riesgo de falso positivo
  // que la 0101 ya cerró para el semáforo disciplinario.
  const ausencia = f.estado === "sin_marcar" ? f.ausenciaHoy : null;
  if (ausencia) {
    return (
      <span title={ausencia.pendiente ? "Registrada, todavía sin aprobar" : "Ausencia aprobada que cubre hoy"}>
        <Insignia variante={ausencia.pendiente ? "advertencia" : "neutral"} atenuada={!ausencia.pendiente}>
          {ausencia.nombre}{ausencia.pendiente ? " · por confirmar" : ""}
        </Insignia>
      </span>
    );
  }
  if (f.estado === "sin_marcar") {
    const sub = subEstadoSinMarcar(f, ahoraDecimal);
    if (sub === "aun_no_inicia") {
      return <Insignia variante="informativo">Aún no inicia · entra {horaAmPmDe(f.entradaEsperadaHoy!)}</Insignia>;
    }
    if (sub === "descansa") {
      return <Insignia variante="neutral" atenuada>Descansa hoy</Insignia>;
    }
    if (sub === "falta_real") {
      return (
        <Link href={linkCorregir(f.personaId)} className="transition-opacity hover:opacity-80">
          <Insignia variante="alerta">Sin marcar · le tocaba {horaAmPmDe(f.entradaEsperadaHoy!)}</Insignia>
        </Link>
      );
    }
    // "desconocido": no hay horario contra qué medir. Mismo texto sin pastilla
    // de siempre — es honesto sobre lo que no se sabe, no inventa una
    // tranquilidad que no se puede probar. Taupe entero, no al 50%: así daba
    // 2.1:1 y no se leía, y "no sabemos" también es información.
    return <span className="text-xs text-taupe">Sin marcar</span>;
  }
  const estilo = ESTILO_ESTADO[f.estado] ?? ESTILO_ESTADO.cerrada;
  if (f.estado === "auto_cerrada_pendiente") {
    return (
      <Link href={linkCorregir(f.personaId)} className={`rounded-full px-2 py-0.5 text-xs ${estilo.clase} transition-opacity hover:opacity-80`}>
        {estilo.label} ›
      </Link>
    );
  }
  if (estilo.clase) return <span className={`rounded-full px-2 py-0.5 text-xs ${estilo.clase}`}>{estilo.label}</span>;
  return <Insignia variante={estilo.variante} atenuada={estilo.atenuada}>{estilo.label}</Insignia>;
}

function fechaBonita(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "long", timeZone: "UTC" }).format(new Date(Date.UTC(y, m - 1, d)));
}

// `umbral` nombra el escalón alcanzado desde la 0200 — amonestacion ·
// suspension · imputacion · bloqueado · aviso —, no solo «amonestacion o aviso».
interface TardRow { persona_id: string; nombre: string; sede: string; tardanzas_mes: number; umbral: string; ultima_fecha: string | null; minimo: number | null }
interface FaltaRow { persona_id: string; nombre: string; sede: string; nivel: string }
/** Fila de `fn_memos_recientes_respuesta_sancionado()` (0404). */
interface RespuestaMemoRow {
  id: string; persona: string; correlativo: string | null; tipo_causal: string; nivel: string;
  firmado_at: string | null; rechazado_at: string | null;
}
// Contratos a plazo fijo con fecha de término anotada (0144). `dias_restantes` es
// negativo cuando la fecha ya pasó, y ese es el grupo que duele.
interface ContratoRow { persona_id: string; nombre: string; sede: string; fecha_fin_contrato: string; dias_restantes: number; ya_vencio: boolean }

interface MetaSede { man: number; tar: number; enc: number; }

// Cobertura de una sede en este momento: cuánta gente hay EN PISO ahora vs la
// meta del tramo. Se calcula una sola vez por sede y se reutiliza para
// ordenar, para el resumen global y para la tarjeta — antes esta cuenta vivía
// solo dentro del .map() de render y no se podía usar para decidir el orden.
interface CoberturaSede {
  activos: FilaPersona[];
  opPiso: number;
  encPiso: number;
  metaOp: number;
  metaEnc: number;
  sinMetaOp: boolean;
  sinMetaEnc: boolean;
  faltanOp: boolean;
  faltanEnc: boolean;
  problema: boolean;
  sinMarcarReal: number;
  programadosHoy: number;
  alertaSinEntrada: string | null;
}
function calcularCoberturaSede(deSede: FilaPersona[], meta: MetaSede, tramoTarde: boolean, ahoraDecimal: number): CoberturaSede {
  const activos = deSede.filter((f) => f.estado === "abierta" || f.estado === "en_pausa");
  const metaOp = tramoTarde ? meta.tar : meta.man;
  // Cobertura EN VIVO: "en piso" = solo Presente (abierta). Quien está en
  // pausa/refrigerio no cuenta — no está físicamente cubriendo ahora.
  const opPiso = deSede.filter((f) => f.esOperativa && f.estado === "abierta").length;
  const encPiso = deSede.filter((f) => f.esEncargada && f.estado === "abierta").length;
  const sinMetaOp = metaOp <= 0;
  const sinMetaEnc = meta.enc <= 0;
  const faltanOp = !sinMetaOp && opPiso < metaOp;
  const faltanEnc = !sinMetaEnc && encPiso < meta.enc;
  const sinMarcarReal = deSede.filter(
    (f) => f.estado === "sin_marcar" && !f.ausenciaHoy && subEstadoSinMarcar(f, ahoraDecimal) === "falta_real",
  ).length;
  // Cuántas de las personas asignadas a esta sede tenían HOY un horario/turno
  // real que decía que trabajaban — el denominador que faltaba: "de Y" antes
  // mezclaba a todo el equipo (vacaciones, descansos, quien ya salió) con
  // quien de verdad tenía que estar. Ver hallazgo de la auditoría, Fase 4.
  const programadosHoy = deSede.filter((f) => f.entradaEsperadaHoy !== null && !f.ausenciaHoy).length;

  // Alerta de sede sin actividad: a alguien ya le tocaba entrar (según su
  // horario u horario), con margen, y todavía nadie de la sede marcó nada.
  // Se excluye a quien tiene una ausencia hoy — mandar de vacaciones a todo
  // el equipo de una sede no es "nadie llegó", es que nadie tenía que llegar.
  const entradasEsperadasHoy = deSede
    .filter((f) => !f.ausenciaHoy && f.entradaEsperadaHoy)
    .map((f) => f.entradaEsperadaHoy!)
    .sort();
  const nadieMarcoTodavia = deSede.every((f) => f.entrada === null);
  let alertaSinEntrada: string | null = null;
  if (entradasEsperadasHoy.length > 0 && nadieMarcoTodavia) {
    const primeraEntrada = entradasEsperadasHoy[0];
    const minutosPasados = (ahoraDecimal - horaDecimalDe(primeraEntrada)) * 60;
    if (minutosPasados >= MARGEN_ALERTA_SEDE_MIN) alertaSinEntrada = primeraEntrada;
  }

  return {
    activos, opPiso, encPiso, metaOp, metaEnc: meta.enc, sinMetaOp, sinMetaEnc,
    faltanOp, faltanEnc, problema: faltanOp || faltanEnc, sinMarcarReal, programadosHoy, alertaSinEntrada,
  };
}

// "Faltan 3" / "Falta 1" — concordancia real, no un texto fijo por métrica.
function faltanTexto(n: number): string {
  return n === 1 ? "Falta 1" : `Faltan ${n}`;
}

// Franja de estado en el borde izquierdo de una tarjeta. Es lo que permite
// leer la pantalla bajando la vista sin leer ni un número: rojo = hay que
// actuar, verde = cubierto. Sin sombra ni degradado (regla de la paleta): la
// tarjeta se distingue por tono, no por relieve. Nunca va sola — el mismo
// estado está siempre dicho en texto al lado, para quien no distingue el color.
// "neutral" no pinta nada: sin estado no hay qué señalar, y una franja color
// arena se veía como un borde mal dibujado. La tarjeta conserva su relleno
// izquierdo igual, para que los textos de todas queden alineados.
type TonoFranja = "alerta" | "advertencia" | "positivo" | "neutral";
const COLOR_FRANJA: Record<TonoFranja, string | null> = {
  alerta: "bg-rojo",
  advertencia: "bg-ambar",
  positivo: "bg-verde",
  neutral: null,
};
function Franja({ tono }: { tono: TonoFranja }) {
  const color = COLOR_FRANJA[tono];
  return color && <span aria-hidden className={`absolute inset-y-0 left-0 w-1 ${color}`} />;
}

// Un tile de cobertura (Operativas / Encargadas), protagonista a propósito:
// es la pregunta que de verdad decide si hay que actuar, no un dato al pie.
//
// Se rellena con el color de su estado en vez de ser papel sobre papel: antes
// la tarjeta de la sede y sus dos tiles eran el mismo tono, y lo único que
// decía "falta gente" era el color de un número en trazo fino.
//
// Dos rojos a propósito. El número es texto grande (36px), y ahí WCAG pide
// 3:1: el rojo da 4.49:1 claro y 3.78:1 oscuro sobre este relleno, y se lee
// ROJO. El "Faltan 2" es texto chico, pide 4.5:1, y el rojo en modo oscuro no
// llega — va en rojo-profundo (7.03 / 5.25:1). Se probó el número también en
// rojo-profundo y sobre el relleno cálido se leía café, no alerta.
// El verde va al 8% y no al 10%: al 10% la etiqueta taupe baja a 4.44:1 en
// modo oscuro.
function TileCobertura({ label, n, meta, sinMeta, tramo }: { label: string; n: number; meta: number; sinMeta: boolean; tramo?: string }) {
  const ok = !sinMeta && n >= meta;
  const tono = sinMeta
    ? { caja: "border-sand bg-crema", numero: "text-taupe", texto: "text-taupe" }
    : ok
      ? { caja: "border-verde/30 bg-verde/[0.08]", numero: "text-verde", texto: "text-verde" }
      : { caja: "border-rojo/30 bg-rojo/10", numero: "text-rojo", texto: "text-rojo-profundo" };
  return (
    <div className={`rounded-superficie border px-4 py-3 ${tono.caja}`}>
      <div className="flex items-baseline gap-1.5">
        <span className={`font-serif text-4xl font-medium leading-none tabular-nums ${tono.numero}`}>{n}</span>
        {!sinMeta && <span className="text-lg text-taupe">/ {meta}</span>}
      </div>
      <div className="mt-1.5 text-xs text-taupe">
        {label}{sinMeta ? " · sin meta" : tramo ? ` · meta ${tramo}` : ""}
      </div>
      {!sinMeta && (
        <div className={`mt-1 text-sm font-semibold ${tono.texto}`}>{ok ? "Completo" : faltanTexto(meta - n)}</div>
      )}
    </div>
  );
}

export default function DashboardPage() {
  const router = useRouter();
  const yo = usePersonaActual();
  const esAdmin = puedeVerTodasLasSedes(yo?.rol ?? null);
  const [filas, setFilas] = useState<FilaPersona[]>([]);
  // Fuente de verdad de qué sedes existen: la tabla `sedes`, igual que las
  // demás 14 pantallas del panel — nunca derivada de quién pasó el filtro de
  // personas de abajo. Antes se armaba agrupando `filas` por sede_id, así que
  // una sede sin nadie que cumpliera activo+en_planilla+no_sueldo_fijo
  // desaparecía entera, sin aviso, en vez de mostrarse con "0 de 0".
  const [sedesActivas, setSedesActivas] = useState<{ id: string; codigo: string }[]>([]);
  const [metasPorSede, setMetasPorSede] = useState<Map<string, MetaSede>>(new Map());
  const [actualizado, setActualizado] = useState<string>("");
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [discTard, setDiscTard] = useState<TardRow[]>([]);
  const [discFaltas, setDiscFaltas] = useState<FaltaRow[]>([]);
  const [contratos, setContratos] = useState<ContratoRow[]>([]);
  // El semáforo de "Contratos a plazo fijo" no contestó. Igual que
  // `discNoRespondio` de Disciplina: el artículo 77 convierte un contrato en
  // indefinido con solo que la persona siga trabajando después de la fecha, y
  // ese plazo corre igual aunque esta franja no haya podido mirar.
  const [contratosNoRespondio, setContratosNoRespondio] = useState(false);
  // `turnos`/`horarios_asignados` no contestaron: no se pudo calcular a quién
  // le tocaba entrar hoy, así que la alerta roja de "sede sin marcar" —la
  // única de esta pantalla fuera de Disciplina— no puede dispararse aunque
  // corresponda. Sin esta bandera esa alerta se apaga en silencio.
  const [horarioEsperadoNoRespondio, setHorarioEsperadoNoRespondio] = useState(false);
  // `ausencias` no contestó: alguien de vacaciones puede verse idéntico a un
  // "sin marcar" real mientras esto no se pueda comprobar (mismo riesgo de
  // falso positivo que ya resuelve `ausenciaHoy` cuando la consulta sí responde).
  const [ausenciasNoRespondieron, setAusenciasNoRespondieron] = useState(false);
  const [sinCargo, setSinCargo] = useState(0);
  // El par de consultas de abajo no respondió. Sin esta distinción, si
  // `expediente_adjuntos` falla, `conPapel` queda vacío y TODOS los memos
  // entregados pasarían el filtro de "sin cargo" — se acusaría a quien sí
  // tiene su papel archivado. Mismo riesgo que `discNoRespondio` ya cierra
  // abajo, para esta franja en particular.
  const [sinCargoNoRespondio, setSinCargoNoRespondio] = useState(false);
  /**
   * El semáforo no contestó. NO es lo mismo que «no hay nadie en escalón».
   *
   * Sin esta distinción la franja se borraba entera cuando la RPC fallaba, y la
   * portada quedaba idéntica a un mes tranquilo. Ya pasó: un `drop function` se
   * llevó por delante su GRANT (0204) y la consulta estuvo caída. Los plazos del
   * art. 25 corren igual mientras la pantalla calla, y esta franja es el único
   * sitio donde el aviso no está dentro de un panel plegado.
   */
  const [discNoRespondio, setDiscNoRespondio] = useState(false);
  const [respuestasMemo, setRespuestasMemo] = useState<RespuestaMemoRow[]>([]);

  // Filtros de la pantalla. La búsqueda es de esta visita (nunca se guarda,
  // por la propia regla de useFiltroGuardado); sede/estado/solo-alertas son
  // preferencias de vista y sí se recuerdan entre sesiones, por navegador.
  const [busqueda, setBusqueda] = useState("");
  const [sedeFiltro, setSedeFiltro] = useFiltroGuardado<string>("dashboard.sede", "todas");
  const [estadoFiltro, setEstadoFiltro] = useFiltroGuardado<string>("dashboard.estado", "todos");
  const [soloAlertas, setSoloAlertas] = useFiltroGuardado<boolean>("dashboard.solo_alertas", false);
  // Qué sedes tienen su tabla de personas abierta manualmente (más allá de lo
  // que fuercen los filtros). Por sede, no global: cada una se expande aparte.
  const [detalleAbierto, setDetalleAbierto] = useState<Record<string, boolean>>({});

  // Semáforo disciplinario para la franja (aparte del refresco de asistencia).
  useEffect(() => {
    const sb = createAdminSupabaseClient();
    void (async () => {
      const [{ data: t, error: errT }, { data: f, error: errF }] = await Promise.all([
        sb.rpc("fn_tardanzas_resumen", {}),
        sb.rpc("fn_faltas_resumen", {}),
      ]);
      setDiscNoRespondio(Boolean(errT || errF));
      setDiscTard(Array.isArray(t) ? (t as TardRow[]) : []);
      setDiscFaltas(Array.isArray(f) ? (f as FaltaRow[]) : []);

      // Memos entregados a los que aún les falta el papel firmado.
      //
      // Un memo entregado sin su cargo archivado no se puede probar. Ante una
      // inspección o un reclamo, el expediente que este sistema arma para
      // sostener una decisión se cae justo por ahí: consta que se entregó
      // porque alguien lo marcó, no porque haya una firma de recepción.
      //
      // Vive en el Dashboard y no solo en Disciplina porque el aviso allá
      // estaba dentro de un panel plegado: había que ir a buscarlo sabiendo
      // que existía. Si cualquiera de las dos consultas falla, NO se calcula
      // un número: "0 sin cargo" con `expediente_disciplinario` caída sería
      // ocultar el aviso, y "todos sin cargo" con `expediente_adjuntos`
      // caída sería acusar a quien sí tiene su papel — los dos son peores
      // que decir, sin más, que no se pudo mirar.
      const [
        { data: entregados, error: errEntregados },
        { data: papeles, error: errPapeles },
      ] = await Promise.all([
        sb.from("expediente_disciplinario").select("id").eq("estado", "entregado"),
        sb.from("expediente_adjuntos").select("documento_id"),
      ]);
      if (errEntregados || errPapeles) {
        setSinCargoNoRespondio(true);
        setSinCargo(0);
      } else {
        setSinCargoNoRespondio(false);
        const conPapel = new Set(((papeles as Array<{ documento_id: string }>) ?? []).map((a) => a.documento_id));
        setSinCargo(((entregados as Array<{ id: string }>) ?? []).filter((d) => !conPapel.has(d.id)).length);
      }

      // Quién firmó (o prefirió no firmar) su memo en los últimos 14 días
      // (0404). Falla en silencio a propósito, igual que "Contratos a plazo
      // fijo" más abajo: es informativo, no un aviso de plazo legal corriendo
      // como el resto de esta franja — si la RPC no responde, la tarjeta
      // simplemente no aparece.
      const { data: resp } = await sb.rpc("fn_memos_recientes_respuesta_sancionado", { p_dias: 14 });
      setRespuestasMemo(Array.isArray(resp) ? (resp as RespuestaMemoRow[]) : []);
    })();
  }, []);

  // Contratos a plazo fijo: los que vencen dentro de 30 días y —lo que de verdad
  // importa— los que YA vencieron sin que nadie registrara la salida. La fecha se
  // anota en Equipo; sin este aviso, anotarla solo sirve si alguien se acuerda de
  // ir a mirarla, y el día del vencimiento no lo recuerda nadie.
  //
  // Aparte del refresco de asistencia porque no cambia cada 30 segundos. La RPC
  // ya devuelve vacío (sin error) para quien no es admin ni líder, así que ese
  // caso sigue sin mostrar nada, como corresponde. Pero si la consulta FALLA de
  // verdad (red, RPC caída), esta franja ya no lo calla: el artículo 77
  // convierte un contrato en indefinido con solo que la persona siga
  // trabajando después de la fecha, y ese plazo corre igual aunque la pantalla
  // no haya podido mirar — mismo criterio que `discNoRespondio` en Disciplina.
  useEffect(() => {
    const sb = createAdminSupabaseClient();
    void (async () => {
      // NOVENTA días, no treinta. Veintiún contratos a plazo fijo y **veinte
      // vencen el mismo 31 de diciembre**: con la ventana de 30 el aviso
      // aparecía el 1 de diciembre, dejando un mes —en plena campaña de fin de
      // año— para decidir, redactar y firmar veinte renovaciones.
      //
      // Y el que se pasa no se pasa a medias: el artículo 77 del D.S. 003-97-TR
      // convierte el contrato en indefinido SOLO, sin que nadie lo decida, por
      // el hecho de que la persona siga trabajando después de la fecha.
      const { data, error } = await sb.rpc("fn_contratos_por_vencer", { p_dias: 90 });
      setContratosNoRespondio(Boolean(error));
      setContratos(Array.isArray(data) ? (data as ContratoRow[]) : []);
    })();
  }, []);

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) {
      router.replace("/admin/login");
      return;
    }

    const hoy = hoyLima();
    const diaHoy = diaSemanaDe(hoy);
    // minutos_salida_temprana va por RPC (fn_jornadas_extra) porque el schema cache
    // de PostgREST no expone la columna; el select directo fallaría entero.
    const [
      { data: sedesData, error: errSedes },
      { data: personas, error: errPersonas },
      { data: jornadas, error: errJornadas },
      { data: extras }, // fn_jornadas_extra ya está diseñada para fallar en silencio (ver comentario abajo)
      { data: funciones }, // función + es_encargada_piso (RPC: el schema cache no expone la columna)
      { data: areasRaw, error: errAreas }, // catálogo de áreas (para saber cuáles son operativas)
      { data: metasRaw }, // metas de cobertura de hoy por sede (falla suave: sin meta = neutro)
      // Ausencias SÍ lleva su error: si falla, alguien de vacaciones se vería
      // idéntico a un "sin marcar" real, y eso merece un aviso discreto (ver abajo).
      { data: ausenciasHoy, error: errAusencias },
      { data: tiposAusencia }, // catálogo (nombre + si exige aprobación), para no repetirlo a mano acá
      // Turnos y horarios SÍ llevan su error: de los dos sale `entradaEsperadaHoy`,
      // que alimenta la única alerta roja de esta pantalla fuera de Disciplina
      // ("sede sin marcar"). Si cualquiera de las dos falla, esa alerta no puede
      // dispararse aunque corresponda — y sin la bandera, se apagaría sin aviso.
      { data: turnosHoy, error: errTurnos },
      { data: horariosVigentes, error: errHorarios },
    ] = await Promise.all([
      // Misma consulta que /admin/reporte-sede: la lista de sedes a mostrar
      // nunca se deriva de quién aparece en otra tabla.
      supabase.from("sedes").select("id, codigo").eq("activa", true).order("codigo"),
      supabase
        .from("personas")
        .select("id, nombres, apellidos, rol, sede_base_id, sedes:sede_base_id(codigo)")
        .eq("estado", "activo")
        // `tipo_vinculo = 'practicante'`, no simplemente `not en_planilla`:
        // así un RxH no entra por accidente. Mismo criterio puntual que la
        // 0333 usó para que un practicante dejara de ser invisible en
        // Contratos — acá no toca el escalafón disciplinario
        // (fn_tardanzas_resumen/fn_faltas siguen excluyendo a los
        // practicantes en todo el sistema): esta pantalla solo muestra quién
        // marcó hoy, no genera ninguna sanción.
        .or("en_planilla.eq.true,tipo_vinculo.eq.practicante")
        .eq("sueldo_fijo", false) // quien cobra fijo no marca: no se le mide asistencia
        .order("nombres"),
      supabase
        .from("jornadas")
        .select("persona_id, estado, entrada_ts, salida_final_ts, minutos_tarde, tiene_salida_no_retornada")
        .eq("fecha", hoy),
      supabase.rpc("fn_jornadas_extra", { p_desde: hoy, p_hasta: hoy }),
      supabase.rpc("fn_personas_funciones"),
      supabase.rpc("fn_areas"),
      supabase.from("metas_cobertura").select("sede_id, meta, meta_tarde, meta_encargadas").eq("dia_semana", diaHoy),
      // anulada_at is null: una ausencia anulada no cubre nada. El rango incluye
      // hoy con <= / >=, igual que el `between` que ya usa fn_faltas_resumen.
      supabase.from("ausencias").select("persona_id, tipo, aprobada_at").is("anulada_at", null).lte("fecha_inicio", hoy).gte("fecha_fin", hoy),
      supabase.from("tipos_ausencia").select("codigo, nombre, requiere_aprobacion"),
      supabase.from("turnos").select("persona_id, fecha, hora_entrada, hora_salida, es_descanso").eq("fecha", hoy),
      supabase
        .from("horarios_asignados")
        .select("persona_id, hora_entrada, hora_salida, dias_laborables, horario_por_dia, almuerzo_min_minutos, vigente_desde, vigente_hasta")
        .lte("vigente_desde", hoy)
        .or(`vigente_hasta.is.null,vigente_hasta.gte.${hoy}`),
    ]);

    if (errSedes || errPersonas || errJornadas) {
      setError((errSedes ?? errPersonas ?? errJornadas)!.message);
      setCargando(false);
      return; // no pisa `filas`/`sedesActivas` con datos parciales/vacíos
    }
    setError(null);
    setSedesActivas(sedesData ?? []);
    setAusenciasNoRespondieron(Boolean(errAusencias));
    setHorarioEsperadoNoRespondio(Boolean(errTurnos || errHorarios));

    // Función/área/encargada: si la RPC falla, degradamos a "todos operativos"
    // (misma política que Turnos) — la cobertura puede marcar de más pero la
    // página no se cae. Las metas fallan aún más suave: sin meta = neutro.
    const areasList: Area[] = parseAreas(areasRaw, errAreas);
    const funcionPorPersona = new Map(
      ((funciones as { persona_id: string; funcion: string; es_encargada_piso?: boolean }[] | null) ?? [])
        .map((x) => [x.persona_id, { funcion: x.funcion, enc: Boolean(x.es_encargada_piso) }]),
    );
    setMetasPorSede(new Map(
      ((metasRaw as { sede_id: string; meta: number; meta_tarde: number | null; meta_encargadas: number | null }[] | null) ?? [])
        .map((m) => [m.sede_id, { man: m.meta ?? 0, tar: m.meta_tarde ?? m.meta ?? 0, enc: m.meta_encargadas ?? 0 }]),
    ));

    const jornadaPorPersona = new Map((jornadas ?? []).map((j: any) => [j.persona_id, j]));
    // Solo llegan filas con minutos > 0 y la fecha es fija (hoy), así que basta persona_id → minutos.
    // Si la RPC falla, extras es null y el map queda vacío (sin badge, la página no se rompe).
    const salidaTempranaPorPersona = new Map(
      ((extras as { persona_id: string; fecha: string; minutos_salida_temprana: number }[] | null) ?? []).map(
        (e) => [e.persona_id, e.minutos_salida_temprana],
      ),
    );
    // Nombre + si exige aprobación, por código de tipo ("vacaciones" → "Vacaciones", true/false).
    const nombrePorTipoAusencia = new Map(
      ((tiposAusencia as { codigo: string; nombre: string; requiere_aprobacion: boolean }[] | null) ?? []).map(
        (t) => [t.codigo, { nombre: t.nombre, requiereAprobacion: t.requiere_aprobacion }],
      ),
    );
    // La restricción `ausencias_sin_solape` ya impide que a una persona le
    // cubran dos ausencias el mismo día, así que basta con la última que
    // llegue — no hay que decidir cuál gana.
    const ausenciaPorPersona = new Map(
      ((ausenciasHoy as { persona_id: string; tipo: string; aprobada_at: string | null }[] | null) ?? []).map((a) => {
        const t = nombrePorTipoAusencia.get(a.tipo);
        return [a.persona_id, { nombre: t?.nombre ?? a.tipo, pendiente: Boolean(t?.requiereAprobacion) && !a.aprobada_at }];
      }),
    );

    // Misma cascada de jornada-esperada.ts que Correcciones, Incidencias y Turnos: el
    // turno puntual de hoy manda, y si no hay se cae al horario base vigente.
    const turnoPorPersona = new Map(
      ((turnosHoy as { persona_id: string; fecha: string; hora_entrada: string | null; hora_salida: string | null; es_descanso: boolean }[] | null) ?? [])
        .map((t) => [t.persona_id, t as TurnoDia]),
    );
    const horariosPorPersona = new Map<string, HorarioTramo[]>();
    for (const h of (horariosVigentes as HorarioTramo[] | null) ?? []) {
      const arr = horariosPorPersona.get(h.persona_id) ?? [];
      arr.push(h);
      horariosPorPersona.set(h.persona_id, arr);
    }

    const resultado: FilaPersona[] = (personas ?? []).map((p: any) => {
      const j = jornadaPorPersona.get(p.id);
      const f = funcionPorPersona.get(p.id);
      const turno = turnoPorPersona.get(p.id) ?? null;
      const horario = horarioVigente(horariosPorPersona.get(p.id) ?? [], hoy);
      const esperado = esperadoDelDia(hoy, turno, horario);
      return {
        personaId: p.id,
        nombre: `${p.nombres} ${p.apellidos}`,
        sede: p.sedes?.codigo ?? "?",
        sedeId: p.sede_base_id,
        estado: j?.estado ?? "sin_marcar",
        entrada: j?.entrada_ts ?? null,
        entradaEsperadaHoy: esperado.trabaja ? esperado.entrada : null,
        origenEsperadoHoy: esperado.origen,
        salidaFinal: j?.salida_final_ts ?? null,
        minutosTarde: j?.minutos_tarde ?? null,
        salidaTemprana: salidaTempranaPorPersona.get(p.id) ?? null,
        enPausaSinRetorno: j?.tiene_salida_no_retornada ?? false,
        esOperativa: esOperativaEn(areasList, f?.funcion ?? AREA_DEFAULT),
        esEncargada: esRolEncargada(p.rol) || Boolean(f?.enc),
        ausenciaHoy: ausenciaPorPersona.get(p.id) ?? null,
      };
    });

    setFilas(resultado);
    setActualizado(new Intl.DateTimeFormat("es-PE", { timeZone: TZ_LIMA, hour: "2-digit", minute: "2-digit", second: "2-digit" }).format(new Date()));
    setCargando(false);
  }, [router]);

  useEffect(() => {
    void cargar();
    const t = setInterval(() => void cargar(), REFRESCO_MS);
    // Refrescar también al volver a la pestaña (los navegadores pausan el interval en
    // segundo plano; así un cambio reciente —ej. una persona nueva— aparece al regresar).
    const alVolver = () => { if (document.visibilityState === "visible") void cargar(); };
    document.addEventListener("visibilitychange", alVolver);
    window.addEventListener("focus", alVolver);
    return () => {
      clearInterval(t);
      document.removeEventListener("visibilitychange", alVolver);
      window.removeEventListener("focus", alVolver);
    };
  }, [cargar]);

  const ahoraDecimal = horaDecimalLimaAhora();
  const tramoTarde = ahoraDecimal >= CORTE_TARDE;
  const tramoLabel = tramoTarde ? "tarde" : "mañana";
  const hoy = hoyLima();
  // Un incidente (tardanza, auto-cierre) enlaza directo a Corregir de esa persona/fecha.
  const linkCorregir = (personaId: string) => `/admin/correcciones?persona=${personaId}&fecha=${hoy}`;

  // Alcance por permiso: qué sedes puede ver quien mira la pantalla ahora.
  // `sedes` (la tabla) es visible para cualquier autenticado — es un catálogo
  // de 4 filas que otras ~14 pantallas necesitan completo para todos los
  // roles — pero RLS ya restringe personas/jornadas/turnos/horarios a la
  // sede propia de una encargada (`supervisor_sede`). Sin este filtro, ella
  // vería las otras tres sedes en "0 trabajando de 0": no una fuga de datos
  // (RLS igual le oculta a las personas), pero sí una afirmación falsa —
  // "no hay nadie" en vez de "no tienes permiso para verlo". Se filtra recién
  // cuando `yo` ya cargó, para no mostrarle una pantalla vacía a un admin por
  // un instante.
  const sedesDeAlcance = sedesActivas
    .map((s) => ({ sedeId: s.id, codigo: s.codigo }))
    .filter((s) => !yo || esAdmin || s.sedeId === yo.sedeBaseId);

  // Cobertura de cada sede, calculada una sola vez y reutilizada para ordenar,
  // para el resumen global y para cada tarjeta.
  const coberturaPorSede = new Map<string, CoberturaSede>();
  for (const s of sedesDeAlcance) {
    const deSede = filas.filter((f) => f.sedeId === s.sedeId);
    const meta = metasPorSede.get(s.sedeId) ?? { man: 0, tar: 0, enc: 0 };
    coberturaPorSede.set(s.sedeId, calcularCoberturaSede(deSede, meta, tramoTarde, ahoraDecimal));
  }

  // Orden: primero la sede con cobertura insuficiente (decisión de la
  // auditoría de sep-2026 — antes solo importaba quién tenía más gente
  // trabajando). Empate se resuelve igual que antes: más gente activa ahora,
  // y si sigue empatado, alfabético.
  const sedes = [...sedesDeAlcance].sort((a, b) => {
    const ca = coberturaPorSede.get(a.sedeId)!;
    const cb = coberturaPorSede.get(b.sedeId)!;
    if (ca.problema !== cb.problema) return ca.problema ? -1 : 1;
    return cb.activos.length - ca.activos.length || a.codigo.localeCompare(b.codigo);
  });

  // ---------- Resumen global ----------
  const trabajandoAhoraTotal = filas.filter((f) => f.estado === "abierta" || f.estado === "en_pausa").length;
  const tardanzasHoyTotal = filas.filter((f) => (f.minutosTarde ?? 0) > 0).length;
  const sinMarcarRealTotal = filas.filter(
    (f) => f.estado === "sin_marcar" && !f.ausenciaHoy && subEstadoSinMarcar(f, ahoraDecimal) === "falta_real",
  ).length;
  const sedesBajoMinimo = sedes.filter((s) => coberturaPorSede.get(s.sedeId)!.problema).length;

  // ---------- Disciplina, ya cargada arriba — hoisted para el resumen y el panel único ----------
  // Cualquier escalón alcanzado va en rojo, no solo la amonestación. Comparar
  // contra "amonestacion" dejaba fuera del aviso a quien ya estaba en
  // suspensión o imputación — los casos más urgentes.
  const rojosT = discTard.filter((t) => t.umbral !== "aviso");
  const rojosF = discFaltas.filter((f) => f.nivel === "rojo");
  const casosDisciplina = rojosT.length + rojosF.length + (sinCargo > 0 ? 1 : 0);

  // ---------- Filtros ----------
  function filaCoincideFiltros(f: FilaPersona): boolean {
    if (busqueda && !f.nombre.toLowerCase().includes(busqueda.trim().toLowerCase())) return false;
    if (estadoFiltro !== "todos" && f.estado !== estadoFiltro) return false;
    if (soloAlertas) {
      const esAlerta =
        f.estado === "auto_cerrada_pendiente" ||
        (f.minutosTarde ?? 0) > 0 ||
        (f.estado === "sin_marcar" && !f.ausenciaHoy && subEstadoSinMarcar(f, ahoraDecimal) === "falta_real");
      if (!esAlerta) return false;
    }
    return true;
  }
  const hayFiltrosDeContenido = busqueda !== "" || estadoFiltro !== "todos" || soloAlertas;
  const hayFiltrosActivos = hayFiltrosDeContenido || sedeFiltro !== "todas";
  function limpiarFiltros() {
    setBusqueda("");
    setEstadoFiltro("todos");
    setSoloAlertas(false);
    setSedeFiltro("todas");
  }
  const sedesMostradas = sedeFiltro === "todas" ? sedes : sedes.filter((s) => s.codigo === sedeFiltro);

  // ---------- Requiere atención (cobertura + Disciplina, en un solo panel) ----------
  interface ItemAtencion { key: string; sede: string; texto: string; href?: string; tono: "critico" | "advertencia" }
  const itemsAtencion: ItemAtencion[] = [];
  for (const s of sedes) {
    const cob = coberturaPorSede.get(s.sedeId)!;
    if (cob.alertaSinEntrada) {
      itemsAtencion.push({
        key: `sin-entrada-${s.sedeId}`, sede: s.codigo, tono: "critico",
        texto: `sin marcajes desde las ${horaAmPmDe(cob.alertaSinEntrada)} — nadie ha marcado entrada todavía`,
      });
    }
    if (cob.faltanOp || cob.faltanEnc) {
      const partes: string[] = [];
      if (cob.faltanOp) partes.push(`${cob.metaOp - cob.opPiso} operativa${cob.metaOp - cob.opPiso === 1 ? "" : "s"}`);
      if (cob.faltanEnc) partes.push(`${cob.metaEnc - cob.encPiso} encargada${cob.metaEnc - cob.encPiso === 1 ? "" : "s"}`);
      itemsAtencion.push({ key: `cobertura-${s.sedeId}`, sede: s.codigo, tono: "advertencia", texto: `faltan ${partes.join(" y ")}` });
    }
    if (cob.sinMarcarReal > 0) {
      itemsAtencion.push({
        key: `sinmarcar-${s.sedeId}`, sede: s.codigo, tono: "advertencia",
        texto: `${cob.sinMarcarReal} sin marcar y ya le tocaba`,
      });
    }
  }
  if (discNoRespondio) {
    itemsAtencion.push({
      key: "disc", sede: "Disciplina", href: "/admin/disciplina", tono: "advertencia",
      texto: "el semáforo no respondió — no es que no haya nadie, es que no pudo mirar",
    });
  } else if (casosDisciplina > 0) {
    itemsAtencion.push({
      key: "disc", sede: "Disciplina", href: "/admin/disciplina", tono: "critico",
      texto: `${casosDisciplina} caso${casosDisciplina === 1 ? "" : "s"} requiere${casosDisciplina === 1 ? "" : "n"} revisión`
        + (sinCargoNoRespondio ? " (no se pudo comprobar memos sin cargo)" : ""),
    });
  } else if (sinCargoNoRespondio) {
    itemsAtencion.push({
      key: "disc", sede: "Disciplina", href: "/admin/disciplina", tono: "advertencia",
      texto: "no se pudo comprobar si hay memos entregados sin el cargo firmado",
    });
  }

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6 sm:p-8">
        <div className="mb-6 flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 className="font-serif text-3xl font-medium leading-tight">Asistencia de hoy</h1>
            <p className="mt-1.5 flex items-center gap-2 text-xs text-taupe">
              {cargando && filas.length === 0 ? (
                "Cargando…"
              ) : (
                <>
                  <span className="relative flex h-2 w-2" aria-hidden>
                    <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-verde/60" />
                    <span className="relative inline-flex h-2 w-2 rounded-full bg-verde" />
                  </span>
                  En vivo · actualizado {actualizado} · se refresca cada 30s
                </>
              )}
            </p>
            {/* Honesto sobre el alcance real de "en vivo": Disciplina y Contratos
                no van en el mismo refresco de 30s (cambian una vez al día, no
                cada medio minuto) — decirlo evita la promesa que el título de
                arriba no cumple para esas dos franjas. */}
            <p className="mt-0.5 text-xs text-taupe">Disciplina y Contratos se cargan al abrir la pantalla — recarga para verlos al día.</p>
            {/* Aviso discreto, no un banner: alguien de vacaciones podría verse como
                "sin marcar" mientras esta consulta no responda. Menos grave que
                Contratos o la alerta de sede — por eso no interrumpe la pantalla. */}
            {ausenciasNoRespondieron && (
              <p className="mt-1 text-xs text-ambar" title="Alguien de vacaciones podría verse como 'Sin marcar' mientras esto no se pueda comprobar.">
                ⚠ no se pudo comprobar las ausencias de hoy
              </p>
            )}
          </div>
          <a
            href={URL_SHEET_ASISTENCIA}
            target="_blank"
            rel="noopener noreferrer"
            className="rounded-xl border border-sand bg-papel px-4 py-2 text-sm font-medium text-tinta transition-all hover:-translate-y-0.5 hover:border-taupe"
          >
            Ver en Google Sheets ↗
          </a>
        </div>

        {error && (
          <div className="mb-6 rounded-2xl border border-rojo/20 bg-rojo/[0.06] px-4 py-3 text-sm text-rojo-profundo">
            No se pudo cargar la asistencia de hoy: {error}{" "}
            <Boton variante="enlace" onClick={() => void cargar()}>
              Reintentar
            </Boton>
          </div>
        )}

        {cargando && filas.length === 0 ? (
          <Cargando texto="Cargando la asistencia de hoy…" />
        ) : (
          <>
            {/* FILTROS */}
            <div className="mb-6 flex flex-wrap items-end gap-3 rounded-2xl border border-sand bg-papel p-4">
              <div className="min-w-48 flex-1">
                <Campo
                  etiqueta="Buscar persona"
                  placeholder="Nombre…"
                  value={busqueda}
                  onChange={(e) => setBusqueda(e.target.value)}
                />
              </div>
              {sedes.length > 1 && (
                <CampoSelect etiqueta="Sede" value={sedeFiltro} onChange={(e) => setSedeFiltro(e.target.value)} className="min-w-32">
                  <option value="todas">Todas</option>
                  {sedes.map((s) => <option key={s.sedeId} value={s.codigo}>{s.codigo}</option>)}
                </CampoSelect>
              )}
              <CampoSelect etiqueta="Estado" value={estadoFiltro} onChange={(e) => setEstadoFiltro(e.target.value)} className="min-w-36">
                <option value="todos">Todos</option>
                <option value="abierta">Presente</option>
                <option value="en_pausa">En pausa</option>
                <option value="cerrada">Salió</option>
                <option value="sin_marcar">Sin marcar</option>
                <option value="auto_cerrada_pendiente">Auto-cerrada</option>
              </CampoSelect>
              <div className="pb-2">
                <CampoCasilla etiqueta="Solo alertas" checked={soloAlertas} onChange={(e) => setSoloAlertas(e.target.checked)} />
              </div>
              {hayFiltrosActivos && (
                <Boton variante="enlace" tamano="sm" className="pb-2.5" onClick={limpiarFiltros}>
                  Limpiar filtros
                </Boton>
              )}
            </div>

            {/* RESUMEN GLOBAL. Número grande y con peso: EB Garamond en su peso
                normal tiene el trazo tan fino que un "2" en rojo se leía como
                gris claro a un metro de la pantalla. Rojo y no rojo-profundo:
                a 36px basta 3:1 (5.17 claro, 4.28 oscuro), y rojo-profundo se
                lee café sobre papel. */}
            <div className="mb-6 grid grid-cols-2 gap-px overflow-hidden rounded-2xl border border-sand bg-sand sm:grid-cols-4">
              {[
                { n: trabajandoAhoraTotal, label: "Trabajando ahora", color: trabajandoAhoraTotal > 0 ? "text-verde" : "text-tinta" },
                { n: tardanzasHoyTotal, label: "Tardanzas hoy", color: tardanzasHoyTotal > 0 ? "text-rojo" : "text-tinta" },
                { n: sinMarcarRealTotal, label: "Sin marcar cuando ya debían", color: sinMarcarRealTotal > 0 ? "text-rojo" : "text-verde" },
                { n: sedesBajoMinimo, label: "Sedes bajo mínimo", color: sedesBajoMinimo > 0 ? "text-rojo" : "text-verde" },
              ].map((k) => (
                <div key={k.label} className="bg-papel px-5 py-4">
                  <div className={`font-serif text-4xl font-medium leading-none tabular-nums ${k.color}`}>{k.n}</div>
                  <div className="mt-2 text-sm text-taupe">{k.label}</div>
                </div>
              ))}
            </div>

            {/* REQUIERE ATENCIÓN — cobertura de sedes + Disciplina, un solo lugar */}
            {itemsAtencion.length === 0 ? (
              <div className="relative mb-8 overflow-hidden rounded-2xl border border-sand bg-papel p-5 pl-6">
                <Franja tono="positivo" />
                <div className="etiqueta text-verde">Requiere atención</div>
                <p className="mt-2 text-sm text-taupe">Nada pendiente ahora mismo.</p>
              </div>
            ) : (
              <div className="relative mb-8 overflow-hidden rounded-2xl border border-sand bg-papel p-5 pl-6">
                <Franja tono={itemsAtencion.some((it) => it.tono === "critico") ? "alerta" : "advertencia"} />
                <div className="etiqueta text-rojo-profundo">Requiere atención</div>
                <ul className="mt-1 flex flex-col">
                  {itemsAtencion.map((it) => {
                    // El punto repite el tono de cada fila: antes solo el "Ver →"
                    // lo decía, y las filas sin enlace no tenían ninguno.
                    const contenido = (
                      <span className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 py-2 text-sm">
                        <span className="flex items-baseline gap-2">
                          <span aria-hidden className={`size-2 shrink-0 translate-y-[-1px] rounded-full ${it.tono === "critico" ? "bg-rojo" : "bg-ambar"}`} />
                          <span><strong className="font-semibold">{it.sede}</strong> <span className="text-tinta">{it.texto}</span></span>
                        </span>
                        {it.href && <span className={`text-xs font-semibold ${it.tono === "critico" ? "text-rojo-profundo" : "text-ambar"}`}>Ver →</span>}
                      </span>
                    );
                    return (
                      <li key={it.key} className="border-t border-sand/60 first:border-t-0">
                        {it.href ? (
                          <Link href={it.href} className="-mx-1 block rounded px-1 transition-colors hover:bg-rojo/[0.06]">{contenido}</Link>
                        ) : contenido}
                      </li>
                    );
                  })}
                </ul>
              </div>
            )}

            {/* QUIÉN RESPONDIÓ SU MEMO (0404). Aparte del panel de arriba porque
                no es un plazo legal corriendo — es informativo: alguien ya vio su
                documento y dejó una constancia digital, firmando o prefiriendo no
                hacerlo. Ninguna de las dos reemplaza el trámite físico. */}
            {respuestasMemo.length > 0 && (
              <div className="mb-8 rounded-2xl border border-sand bg-papel p-5 pl-6">
                <div className="mb-2 flex items-center justify-between">
                  <span className="font-serif text-xl font-medium text-tinta">Colaboradores respondieron su memo</span>
                  <Link href="/admin/disciplina" className="text-xs font-medium text-taupe hover:underline">Ver disciplina →</Link>
                </div>
                {respuestasMemo.map((r) => (
                  <Link key={r.id} href={`/admin/disciplina/memo/${r.id}`}
                    className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 border-t border-sand/60 py-2 text-sm transition-colors hover:bg-verde/[0.06]">
                    <span>
                      <strong>{r.persona}</strong>
                      <Insignia variante={r.firmado_at ? "positivo" : "neutral"} className="ml-2">
                        {r.firmado_at ? "firmó digitalmente" : "prefirió no firmar"}
                      </Insignia>
                    </span>
                    <span className="text-xs text-taupe">{fechaBonita((r.firmado_at ?? r.rechazado_at)!.slice(0, 10))}</span>
                  </Link>
                ))}
              </div>
            )}

            {/* CONTRATOS A PLAZO FIJO. Dos grupos, y el importante es el primero:
                quien ya venció y sigue figurando activo. Ese caso no se nota en
                ninguna otra pantalla —la persona aparece normal en asistencia, en
                planilla y en provisiones— y desde la 0162 tampoco en el tablero de
                Documentación. Sin esta franja, la fecha anotada en Equipo solo sirve
                si alguien se acuerda de ir a buscarla. */}
            {(() => {
              // Igual que Disciplina: si la RPC no contestó, la franja NO se
              // calla — dice que no pudo mirar, en vez de parecer un mes tranquilo.
              if (contratosNoRespondio) {
                return (
                  <section className="mb-8 rounded-2xl border border-ambar/30 bg-ambar/[0.06] p-5">
                    <div className="etiqueta text-ambar">Contratos a plazo fijo · no se pudo consultar</div>
                    <p className="mt-2 text-sm text-tinta">
                      No se pudo revisar qué contratos vencen o ya vencieron. El plazo del{" "}
                      <strong>artículo 77</strong> corre igual aunque esta franja no haya podido mirar.
                      Vuelve a cargar, y si sigue igual revisa{" "}
                      <Link href="/admin/equipo" className="underline">Equipo</Link>.
                    </p>
                  </section>
                );
              }
              const vencidos = contratos.filter((c) => c.ya_vencio);
              const porVencer = contratos.filter((c) => !c.ya_vencio);
              if (!vencidos.length && !porVencer.length) return null;
              const enCuantos = (dias: number) =>
                dias <= 0 ? "vence hoy" : dias === 1 ? "vence mañana" : `vence en ${dias} días`;
              // ¿Muchos caen el MISMO día? Veinte líneas seguidas con la misma fecha
              // se leen como veinte avisos sueltos, y el problema no son veinte
              // renovaciones repartidas: es que hay que hacerlas todas esa semana.
              // Se dice de una vez, arriba, antes de la lista.
              const porFecha = new Map<string, number>();
              for (const c of porVencer) porFecha.set(c.fecha_fin_contrato, (porFecha.get(c.fecha_fin_contrato) ?? 0) + 1);
              const [fechaRacimo, cuantos] = [...porFecha.entries()]
                .sort((a, b) => b[1] - a[1])[0] ?? ["", 0];
              const hayRacimo = cuantos >= 3;
              return (
                <div className="relative mb-8 overflow-hidden rounded-2xl border border-sand bg-papel p-5 pl-6">
                  {/* Rojo si alguien ya pasó su fecha (el art. 77 ya corrió);
                      ámbar si solo se acerca. */}
                  <Franja tono={vencidos.length > 0 ? "alerta" : "advertencia"} />
                  <div className="mb-2 flex items-center justify-between">
                    <span className="font-serif text-xl font-medium text-tinta">Contratos a plazo fijo</span>
                    <Link href="/admin/equipo" className="text-xs font-semibold text-rojo-profundo hover:underline">Ver equipo →</Link>
                  </div>
                  {hayRacimo && (
                    <p className="mb-2 rounded-lg bg-rojo/10 px-3 py-2 text-sm text-rojo-profundo">
                      <strong>{cuantos} contratos vencen el mismo día</strong> ({fechaBonita(fechaRacimo)}).
                      No son {cuantos} trámites repartidos: son {cuantos} decisiones, {cuantos} redacciones
                      y {cuantos} firmas en la misma semana. Al que se pase de fecha con la persona
                      todavía trabajando, el <strong>art. 77</strong> lo vuelve indefinido solo.
                    </p>
                  )}
                  {vencidos.map((c) => (
                    <div key={c.persona_id} className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 border-t border-sand/60 py-2 text-sm">
                      <span>
                        <strong>{c.nombre}</strong> <span className="text-taupe">· {c.sede}</span>
                        <Insignia variante="alerta" className="ml-2">
                          terminó el {fechaBonita(c.fecha_fin_contrato)} y sigue activa
                        </Insignia>
                      </span>
                      <span className="text-xs font-semibold text-rojo-profundo">renovar o registrar su salida →</span>
                    </div>
                  ))}
                  {porVencer.map((c) => (
                    <div key={c.persona_id} className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 border-t border-sand/60 py-2 text-sm">
                      <span>
                        <strong>{c.nombre}</strong> <span className="text-taupe">· {c.sede}</span>
                        <Insignia variante="advertencia" className="ml-2">
                          {enCuantos(c.dias_restantes)} · {fechaBonita(c.fecha_fin_contrato)}
                        </Insignia>
                      </span>
                    </div>
                  ))}
                  <p className="border-t border-sand/60 pt-2.5 text-xs text-taupe">
                    {vencidos.length > 0
                      ? "Mientras siga figurando activa sigue marcando, sigue cobrando y sigue acumulando gratificación, CTS y vacaciones. Anotar la fecha no da de baja a nadie: eso se decide y se registra a mano."
                      : "La fecha es lo previsto, no un hecho. Un contrato puede renovarse: esto solo avisa antes de que llegue el día."}
                  </p>
                </div>
              );
            })()}

            {/* !alertaSinEntrada && horarioEsperadoNoRespondio, a nivel global:
                si turnos/horarios fallaron, ninguna sede puede calcular su alerta
                de "sin marcajes" ni su denominador de programados hoy. */}
            {horarioEsperadoNoRespondio && (
              <div className="mb-6 flex items-center gap-2 rounded-2xl border border-ambar/30 bg-ambar/[0.06] px-5 py-3 text-sm text-ambar">
                <span className="flex h-4 w-4 shrink-0 items-center justify-center rounded-full bg-ambar text-[10px] font-bold text-crema">!</span>
                No se pudo comprobar a quién le tocaba entrar hoy — la alerta de sedes sin marcajes y el conteo de &quot;programadas hoy&quot; no están disponibles ahora mismo.
              </div>
            )}

            {sedesMostradas.length === 0 && (
              <p className="rounded-2xl border border-sand bg-papel p-6 text-center text-sm text-taupe">
                No encontramos personas con estos filtros.
              </p>
            )}

            {sedesMostradas.map(({ sedeId, codigo }) => {
              const deSedeCompleta = filas.filter((f) => f.sedeId === sedeId);
              const deSedeMostrada = deSedeCompleta.filter(filaCoincideFiltros);
              const cob = coberturaPorSede.get(sedeId)!;
              // Un solo estado de la sede, del que salen la franja y la pastilla —
              // así no pueden decir cosas distintas. "Sede sin marcajes" también
              // es alerta aunque no tenga meta: nadie llegó y a alguien le tocaba.
              const estadoSede: { tono: TonoFranja; texto: string } =
                cob.problema || cob.alertaSinEntrada
                  ? { tono: "alerta", texto: cob.problema ? "Cobertura insuficiente" : "Sin marcajes" }
                  : cob.sinMetaOp && cob.sinMetaEnc
                    ? { tono: "neutral", texto: "Sin meta configurada" }
                    : { tono: "positivo", texto: "Cobertura correcta" };

              const tablaVisible = hayFiltrosDeContenido || (detalleAbierto[sedeId] ?? false);

              return (
                <section key={sedeId} className="relative mb-8 overflow-hidden rounded-2xl border border-sand bg-papel p-5 pl-6 sm:p-6 sm:pl-7">
                  <Franja tono={estadoSede.tono} />
                  <div className="mb-1 flex flex-wrap items-center justify-between gap-3">
                    <h2 className="font-serif text-2xl font-medium leading-tight">
                      {codigo}{" "}
                      <span className="text-lg font-normal text-taupe">
                        — {cob.activos.length} trabajando de {cob.programadosHoy} programadas hoy
                      </span>
                    </h2>
                    <Insignia
                      variante={estadoSede.tono}
                      atenuada={estadoSede.tono === "neutral"}
                      className="px-3 py-1 font-semibold"
                    >
                      {estadoSede.texto}
                    </Insignia>
                  </div>
                  <p className="mb-4 text-xs text-taupe">
                    {deSedeCompleta.length} en el equipo de la sede — no todas tenían turno hoy.
                  </p>

                  {/* La única alerta que se permite el rojo sagrado en esta pantalla,
                      además de la que ya vive arriba en "Requiere atención": la
                      repetimos acá, junto a la sede, para quien llegó directo a esta
                      tarjeta sin pasar por el resumen. */}
                  {cob.alertaSinEntrada && (
                    <div className="mb-4 flex items-center gap-2 rounded-2xl border border-rojo bg-rojo/[0.06] px-5 py-3 text-sm font-semibold text-rojo-profundo">
                      <span className="flex h-4 w-4 shrink-0 items-center justify-center rounded-full bg-rojo text-[10px] font-bold text-crema">!</span>
                      Sin marcajes desde las {horaAmPmDe(cob.alertaSinEntrada)} — nadie de esta sede ha marcado entrada todavía.
                    </div>
                  )}

                  {/* Cobertura protagonista: es la pregunta que decide si hay que
                      actuar, así que va primero y grande — no al pie como texto. */}
                  <div className="mb-4 grid grid-cols-2 gap-3 sm:max-w-md">
                    <TileCobertura label="Operativas en piso" n={cob.opPiso} meta={cob.metaOp} sinMeta={cob.sinMetaOp} tramo={tramoLabel} />
                    <TileCobertura label="Encargadas" n={cob.encPiso} meta={cob.metaEnc} sinMeta={cob.sinMetaEnc} />
                  </div>

                  <div className="mb-4">
                    <div className="etiqueta text-taupe">Trabajando ahora · {cob.activos.length}</div>
                    <div className="mt-2 flex flex-wrap gap-2">
                      {cob.activos.length === 0 ? (
                        <span className="text-sm text-taupe">Nadie está trabajando actualmente.</span>
                      ) : (
                        // Mismo verde/ámbar que "Presente"/"En pausa" en la tabla de
                        // abajo: antes eran papel sobre papel con borde sand, y no
                        // se distinguía quién estaba en piso de quién en refrigerio
                        // hasta leer el texto al final del nombre.
                        cob.activos.map((f) => {
                          const enPausa = f.estado === "en_pausa";
                          return (
                            <span
                              key={f.personaId}
                              className={`inline-flex items-center gap-2 rounded-full border px-3 py-1 text-sm ${enPausa ? "border-ambar/35 bg-ambar/[0.16]" : "border-verde/30 bg-verde/[0.14]"}`}
                            >
                              <span aria-hidden className={`size-1.5 rounded-full ${enPausa ? "bg-ambar" : "bg-verde"}`} />
                              {f.nombre}
                              {enPausa && <span className="text-ambar">· en pausa</span>}
                            </span>
                          );
                        })
                      )}
                    </div>
                  </div>

                  {tablaVisible ? (
                    <>
                      {deSedeMostrada.length === 0 ? (
                        <p className="text-sm text-taupe">No encontramos personas con estos filtros en esta sede.</p>
                      ) : (
                        <>
                          {/* Escritorio: tabla completa. En celular una tabla de 5 columnas no
                              cabe sin scroll horizontal incómodo, así que de sm hacia abajo se
                              arma la versión en tarjetas de más abajo — mismos datos. */}
                          <div className="hidden sm:block">
                            <Tabla>
                              <TablaEncabezado>
                                <Th>Nombre</Th>
                                <Th>Estado</Th>
                                <Th>Entrada</Th>
                                <Th>Tardanza</Th>
                                <Th>Salida final</Th>
                              </TablaEncabezado>
                              <tbody>
                                {deSedeMostrada.map((f) => (
                                  <Fila key={f.personaId}>
                                    <td className="px-4 py-2.5">{f.nombre}</td>
                                    <td className="px-4 py-2.5">
                                      <EstadoCelda f={f} linkCorregir={linkCorregir} ahoraDecimal={ahoraDecimal} />
                                    </td>
                                    <td className="px-4 py-2.5">{horaLima(f.entrada)}</td>
                                    <td className="px-4 py-2.5">
                                      {f.minutosTarde === null || f.minutosTarde === 0 ? (
                                        <span className="text-taupe/40">—</span>
                                      ) : (
                                        <Link href={linkCorregir(f.personaId)} className="font-semibold text-rojo-profundo underline decoration-rojo/30 underline-offset-2 transition-colors hover:decoration-rojo">
                                          {f.minutosTarde} min tarde
                                        </Link>
                                      )}
                                    </td>
                                    <td className="px-4 py-2.5">
                                      {horaLima(f.salidaFinal)}
                                      {f.salidaTemprana ? (
                                        <Link href={linkCorregir(f.personaId)} className="ml-2 transition-opacity hover:opacity-80">
                                          <Insignia variante="advertencia" tamano="sm">anticip. {formatoMinutos(f.salidaTemprana)}</Insignia>
                                        </Link>
                                      ) : null}
                                    </td>
                                  </Fila>
                                ))}
                              </tbody>
                            </Tabla>
                          </div>

                          {/* Celular: la misma información en tarjetas apiladas, una por persona. */}
                          <div className="flex flex-col gap-2 sm:hidden">
                            {deSedeMostrada.map((f) => (
                              <div key={f.personaId} className="rounded-superficie border border-sand bg-hueso p-4">
                                <div className="mb-2 flex items-center justify-between gap-2">
                                  <span className="font-medium">{f.nombre}</span>
                                  <span className="shrink-0">
                                    <EstadoCelda f={f} linkCorregir={linkCorregir} ahoraDecimal={ahoraDecimal} />
                                  </span>
                                </div>
                                <div className="grid grid-cols-3 gap-x-2 gap-y-1 border-t border-sand pt-2 text-xs">
                                  <span className="text-taupe">Entrada</span>
                                  <span className="text-taupe">Tardanza</span>
                                  <span className="text-taupe">Salida final</span>
                                  <span>{horaLima(f.entrada)}</span>
                                  <span>
                                    {f.minutosTarde === null || f.minutosTarde === 0 ? (
                                      <span className="text-taupe/40">—</span>
                                    ) : (
                                      <Link href={linkCorregir(f.personaId)} className="font-semibold text-rojo-profundo underline decoration-rojo/30 underline-offset-2">
                                        {f.minutosTarde} min
                                      </Link>
                                    )}
                                  </span>
                                  <span>
                                    {horaLima(f.salidaFinal)}
                                    {f.salidaTemprana ? (
                                      <Link href={linkCorregir(f.personaId)} className="ml-1 inline-block">
                                        <Insignia variante="advertencia" tamano="sm">+{formatoMinutos(f.salidaTemprana)}</Insignia>
                                      </Link>
                                    ) : null}
                                  </span>
                                </div>
                              </div>
                            ))}
                          </div>
                        </>
                      )}
                      {!hayFiltrosDeContenido && (
                        <Boton variante="enlace" tamano="sm" className="mt-3" onClick={() => setDetalleAbierto((s) => ({ ...s, [sedeId]: false }))}>
                          Ocultar detalle ↑
                        </Boton>
                      )}
                    </>
                  ) : (
                    <Boton variante="enlace" tamano="sm" onClick={() => setDetalleAbierto((s) => ({ ...s, [sedeId]: true }))}>
                      Ver detalle ↓ ({deSedeCompleta.length} persona{deSedeCompleta.length === 1 ? "" : "s"})
                    </Boton>
                  )}
                </section>
              );
            })}
          </>
        )}
      </main>
    </div>
  );
}

// ============================================================================
// seguros.ts — lo que la pantalla de Seguros decide para dibujar
// ============================================================================
// QUÉ PROMETE
//   Funciones puras sobre lo que devuelven las funciones de la 0528: en qué seguro
//   está cada colaborador, quién tiene un hueco de cobertura, hasta cuándo sigue
//   cubierta una persona contando las renovaciones, en qué va la prima, qué papeleo
//   y qué cambios de seguro faltan, y qué de todo eso entra a la Bandeja. Sin React
//   ni Supabase: se prueba con vitest (`tests/seguros.test.ts`).
//
// QUÉ NO DECIDE
//   Nada de lo que es regla del negocio. Qué seguro le toca a cada persona (su vínculo,
//   o lo que DO le asignó), quién tiene que tener póliza (`hueco`), si una póliza cubre
//   HOY (`cubre_hoy`, con el último día EXCLUSIVO) y qué pasos de un cambio siguen
//   pendientes lo dice la base; aquí solo se lee. Si esto lo recalculara, habría dos
//   respuestas a «¿esta persona tiene seguro?», y esa es justo la pregunta que no puede
//   tener dos. Tampoco conoce los tipos por su nombre: no hay un `if (tipo === "fola")`.
//   El catálogo vive en `seguros_tipos`, y DO puede agregarle tipos.
//
// QUÉ ASUME
//   `vigente_hasta` es EXCLUSIVO: la póliza cubre hasta las 12 M de ese día. Una
//   renovación que empieza el día en que termina la anterior no deja hueco. Las fechas
//   son de calendario de Lima (`AAAA-MM-DD`, sin hora ni huso).
// ============================================================================
import { TIPO_VINCULO_LABEL, type TipoVinculo } from "@cayla-dynamic/shared";
import { diasEntre, diaYMes } from "../bandeja-mia";
import { sinTildes } from "../sin-tildes";

// ── Lo que devuelve la base ─────────────────────────────────────────────────

/** Un tipo de seguro (`fn_seguros_tipos`, 0528). */
export interface TipoSeguro {
  clave: string;
  nombre: string;
  descripcion: string | null;
  /** true: el seguro principal de la persona (uno a la vez). false: va además. */
  principal: boolean;
  /** true: se registra una póliza. false: «por planilla» (EsSalud). */
  con_poliza: boolean;
  aplica_a_vinculos: string[];
  texto_alta: string | null;
  texto_baja: string | null;
  de_sistema: boolean;
  activo: boolean;
  archivado_motivo: string | null;
  personas: number;
  polizas_vigentes: number;
}

/** Una persona y su seguro principal de hoy (`fn_seguros_equipo`, 0528). */
export interface FilaEquipoSeguro {
  persona_id: string;
  persona: string;
  sede: string;
  tipo_vinculo: string;
  practicante_modalidad: string | null;
  activa: boolean;
  tipo: string | null;
  tipo_nombre: string | null;
  origen: "vinculo" | "asignacion" | null;
  asignacion_id: string | null;
  asignacion_desde: string | null;
  asignacion_motivo: string | null;
  /** El que le toca por su vínculo, aunque hoy mande una asignación de DO. Lo dice la base: la pantalla no repite la regla. */
  tipo_automatico: string | null;
  tipo_automatico_nombre: string | null;
  con_poliza: boolean;
  cubre_hoy: boolean | null;
  hueco: boolean;
}

/** Una póliza viva, de cualquier tipo (`fn_seguros_tablero`, 0528). */
export interface Poliza {
  persona_id: string;
  persona: string;
  sede: string;
  persona_activa: boolean;
  producto: string;
  producto_nombre: string;
  producto_principal: boolean;
  poliza_id: string;
  aseguradora: string;
  numero_poliza: string;
  vigente_desde: string;
  vigente_hasta: string;
  cubre_hoy: boolean;
  prima_total: number;
  prima_vence_el: string | null;
  plan: string | null;
  beneficio_enfermedad: number | null;
  beneficio_accidente: number | null;
  renueva_sola: boolean | null;
  pagada_el: string | null;
  firmada_el: string | null;
  factura_recibida_el: string | null;
  nota: string | null;
  archivos: number;
  creada_at: string;
}

/** Un cambio de seguro, con lo que todavía pide (`fn_seguros_cambios`, 0528). */
export interface CambioSeguro {
  id: string;
  persona_id: string;
  persona: string;
  sede: string;
  persona_activa: boolean;
  de_tipo: string | null;
  de_nombre: string | null;
  a_tipo: string | null;
  a_nombre: string | null;
  fecha: string;
  origen: "vinculo" | "asignacion";
  vinculo_antes: string | null;
  vinculo_despues: string | null;
  detalle: string | null;
  baja_pendiente: boolean;
  baja_texto: string;
  baja_hecha_el: string | null;
  baja_nota: string | null;
  alta_pendiente: boolean;
  alta_texto: string;
  alta_hecha_el: string | null;
  alta_nota: string | null;
  creado_at: string;
}

/** El bucket privado de los PDF (0528). */
export const BUCKET_SEGUROS = "polizas-seguro";

/**
 * Cuántos días antes de quedarse sin seguro empieza a avisar. 45: el corredor
 * necesita días para cotizar, y la prima de contado de la póliza de hoy venció
 * 17 días después de emitirse. Es un número elegido, no una regla de ley: es de
 * Felipe cambiarlo.
 */
export const DIAS_AVISO_RENOVACION = 45;

/** Con cuántos días de anticipación a su vencimiento una prima sin pagar entra a la Bandeja. */
export const DIAS_AVISO_PRIMA = 7;

/**
 * Cuántos días de mora aguanta la cobertura: con 30 días calendario sin pagar
 * desde el vencimiento, la cobertura se suspende sola (convenio de pago de
 * Pacífico, cláusula quinta).
 */
export const DIAS_DE_GRACIA_PRIMA = 30;

export type TipoArchivoSeguro = "poliza" | "convenio_pago" | "factura" | "otro";

export const TIPOS_ARCHIVO_SEGURO: readonly { valor: TipoArchivoSeguro; etiqueta: string }[] = [
  { valor: "poliza", etiqueta: "Póliza" },
  { valor: "convenio_pago", etiqueta: "Convenio de pago" },
  { valor: "factura", etiqueta: "Factura" },
  { valor: "otro", etiqueta: "Otro papel" },
];

export function etiquetaTipoArchivo(t: string): string {
  return TIPOS_ARCHIVO_SEGURO.find((x) => x.valor === t)?.etiqueta ?? t;
}

/** «1 día», «3 días». */
export function plural(n: number, uno: string, varios: string): string {
  return `${n} ${n === 1 ? uno : varios}`;
}

/** «Practicantes», «Planilla»… tal como los llama el resto del sistema; un vínculo desconocido se escribe tal cual. */
export function etiquetaVinculo(v: string | null | undefined): string {
  if (!v) return "—";
  return TIPO_VINCULO_LABEL[v as TipoVinculo] ?? v;
}

// ── Fechas ──────────────────────────────────────────────────────────────────

/**
 * `2026-10-01` + 3 meses → `2027-01-01`. El día se recorta al último del mes de
 * llegada (31 de enero + 1 mes = 28 de febrero) en vez de saltar al siguiente.
 * Por partes y en UTC: sin el huso del navegador.
 */
export function sumarMeses(fecha: string, meses: number): string {
  const [y, m, d] = fecha.split("-").map(Number);
  const destino = new Date(Date.UTC(y, m - 1 + meses, 1));
  const ultimo = new Date(Date.UTC(destino.getUTCFullYear(), destino.getUTCMonth() + 1, 0)).getUTCDate();
  return new Date(Date.UTC(destino.getUTCFullYear(), destino.getUTCMonth(), Math.min(d, ultimo))).toISOString().slice(0, 10);
}

// ── La prima ────────────────────────────────────────────────────────────────

export type EstadoPrima = "pagada" | "sin_fecha" | "al_dia" | "por_vencer" | "en_mora" | "suspendida";

/**
 * En qué va la prima de una póliza. Vence EL día indicado: ese día todavía vale,
 * el siguiente ya es mora. `dias` es los que faltan (positivo) o los de mora
 * (negativo, como lo cuentan las demás urgencias de la Bandeja).
 */
export function estadoPrima(
  p: Pick<Poliza, "pagada_el" | "prima_vence_el">,
  hoy: string,
): { estado: EstadoPrima; dias: number | null } {
  if (p.pagada_el) return { estado: "pagada", dias: null };
  if (!p.prima_vence_el) return { estado: "sin_fecha", dias: null };
  const dias = diasEntre(hoy, p.prima_vence_el);
  if (dias >= 0) return { estado: dias <= DIAS_AVISO_PRIMA ? "por_vencer" : "al_dia", dias };
  return { estado: -dias > DIAS_DE_GRACIA_PRIMA ? "suspendida" : "en_mora", dias };
}

// ── El papeleo ──────────────────────────────────────────────────────────────

export type PasoSeguro = "pagada" | "firmada" | "factura";

export const PASOS_SEGURO: readonly { paso: PasoSeguro; etiqueta: string; hecho: string; falta: string }[] = [
  { paso: "pagada", etiqueta: "Prima pagada", hecho: "Prima pagada", falta: "Falta pagar la prima" },
  { paso: "firmada", etiqueta: "Firmada", hecho: "Póliza y convenio de pago firmados", falta: "Falta firmar y devolver la póliza y el convenio de pago" },
  { paso: "factura", etiqueta: "Factura", hecho: "Factura recibida", falta: "Falta la factura" },
];

/** La fecha en que se hizo cada paso, o null si está pendiente. */
export function fechaDelPaso(p: Pick<Poliza, "pagada_el" | "firmada_el" | "factura_recibida_el">, paso: PasoSeguro): string | null {
  return paso === "pagada" ? p.pagada_el : paso === "firmada" ? p.firmada_el : p.factura_recibida_el;
}

/** Los pasos que faltan de UNA póliza, en el orden en que se hacen. */
export function pasosPendientes(p: Pick<Poliza, "pagada_el" | "firmada_el" | "factura_recibida_el">): PasoSeguro[] {
  return PASOS_SEGURO.filter((x) => fechaDelPaso(p, x.paso) === null).map((x) => x.paso);
}

// ── Los cambios de seguro ───────────────────────────────────────────────────

/** «FOLA → EsSalud»: lo que cambió, con «sin seguro» donde no había. */
export function resumenDelCambio(c: Pick<CambioSeguro, "de_nombre" | "a_nombre">): string {
  return `${c.de_nombre ?? "sin seguro"} → ${c.a_nombre ?? "sin seguro"}`;
}

/** Por qué cambió: el vínculo nuevo, o el motivo que escribió DO. */
export function origenDelCambio(c: Pick<CambioSeguro, "origen" | "vinculo_antes" | "vinculo_despues" | "detalle">): string {
  if (c.origen === "vinculo") return `cambió de vínculo: ${etiquetaVinculo(c.vinculo_antes)} → ${etiquetaVinculo(c.vinculo_despues)}`;
  return c.detalle ? `lo cambió DO: «${c.detalle}»` : "lo cambió DO";
}

/** Los pasos de un cambio que todavía piden algo, con su texto. */
export function pasosDelCambio(c: CambioSeguro): { paso: "baja" | "alta"; texto: string }[] {
  const pasos: { paso: "baja" | "alta"; texto: string }[] = [];
  if (c.baja_pendiente) pasos.push({ paso: "baja", texto: c.baja_texto });
  if (c.alta_pendiente) pasos.push({ paso: "alta", texto: c.alta_texto });
  return pasos;
}

// ── Cobertura por persona ───────────────────────────────────────────────────

/**
 * hueco ........... su seguro principal lleva póliza y no tiene ninguna que cubra HOY.
 *                   El caso caro: una persona sin ningún seguro (Ley 28518, art. 52.5,
 *                   para los practicantes).
 * por_vencer ...... cubierta hoy, pero se queda sin seguro en `DIAS_AVISO_RENOVACION`
 *                   días o menos y no hay una renovación que empalme.
 * al_dia .......... su seguro principal lleva póliza y está cubierta, con margen.
 * por_planilla .... su seguro principal no lleva póliza (EsSalud): lo paga la planilla
 *                   y lo declara el contador. No hay nada que registrar.
 * sin_seguro ...... no aplica: honorarios y sin vínculo laboral.
 * baja_pendiente .. ya no está activa y conserva una póliza vigente: hay que pedirle la
 *                   baja a la aseguradora.
 */
export type SituacionSeguro = "hueco" | "por_vencer" | "al_dia" | "por_planilla" | "sin_seguro" | "baja_pendiente";

export type MotivoHueco = "nunca" | "vencida" | "aun_no_empieza";

export interface SeguroDePersona {
  personaId: string;
  persona: string;
  sede: string;
  vinculo: string;
  modalidad: string | null;
  activa: boolean;
  situacion: SituacionSeguro;
  /** Su seguro principal de hoy, o null si no aplica. */
  tipo: { clave: string; nombre: string } | null;
  origen: "vinculo" | "asignacion" | null;
  asignacion: { id: string; desde: string; motivo: string } | null;
  /** El que le tocaría por su vínculo. Si hay asignación, es adonde vuelve con «volver al automático». */
  automatico: { clave: string; nombre: string } | null;
  /** ¿Su seguro principal lleva póliza? */
  conPoliza: boolean;
  /** Las pólizas de su seguro principal, la más reciente primero. */
  polizasPrincipales: Poliza[];
  /** Todas las demás: los complementarios y lo que le quedó de un seguro anterior. */
  otras: Poliza[];
  /** La póliza que habla por su seguro principal: la que cubre hoy; si ninguna, la próxima en empezar; si ninguna, la última que venció. */
  actual: Poliza | null;
  /** Hasta cuándo sigue cubierta sin interrupción (EXCLUSIVO), contando renovaciones que empalman. Null si hoy no cubre nada. */
  cubiertoHasta: string | null;
  /** Días que faltan para quedar sin seguro (si cubre hoy). */
  diasParaQuedarSinSeguro: number | null;
  motivoHueco: MotivoHueco | null;
  /** Si el hueco es por una póliza vencida: hace cuántos días terminó. */
  diasDesdeQueVencio: number | null;
  /** Si el hueco espera una póliza que ya está registrada: cuándo empieza. */
  empiezaEl: string | null;
  /** Todos sus cambios de seguro, el más reciente primero. */
  cambios: CambioSeguro[];
  /** Los que todavía piden algo. */
  cambiosPendientes: CambioSeguro[];
  /** Las pólizas (de cualquier tipo) con un paso del papeleo sin hacer. */
  conPapeleo: Poliza[];
}

/** Hasta dónde llega la cobertura de `actual`, encadenando las pólizas que empiezan antes de que termine la anterior. */
export function cubiertoHasta(actual: Pick<Poliza, "vigente_hasta">, polizas: readonly Pick<Poliza, "vigente_desde" | "vigente_hasta">[]): string {
  let fin = actual.vigente_hasta;
  // Una póliza con `vigente_hasta > fin` y `vigente_desde <= fin` empalma. La vuelta
  // termina: cada una solo puede extender `fin` y el conjunto es finito.
  for (let i = 0; i <= polizas.length; i++) {
    const siguiente = polizas.find((p) => p.vigente_desde <= fin && p.vigente_hasta > fin);
    if (!siguiente) break;
    fin = siguiente.vigente_hasta;
  }
  return fin;
}

function agrupar<T>(xs: readonly T[], clave: (x: T) => string): Map<string, T[]> {
  const m = new Map<string, T[]>();
  for (const x of xs) {
    const k = clave(x);
    const lista = m.get(k);
    if (lista) lista.push(x); else m.set(k, [x]);
  }
  return m;
}

/** Qué tan arriba va una persona en la lista: lo que pide algo primero, y entre eso lo más serio. */
function rangoDeAtencion(p: SeguroDePersona): number {
  if (p.situacion === "hueco") return 0;
  if (p.cambiosPendientes.length > 0) return 1;
  if (p.situacion === "por_vencer") return 2;
  if (p.situacion === "baja_pendiente") return 3;
  if (p.conPapeleo.length > 0) return 4;
  if (p.situacion === "sin_seguro") return 6;
  return 5;
}

/**
 * Junta lo que la base contesta en una fila por persona y resuelve su situación. Hay
 * una por cada fila de `equipo` (las personas activas, y las que ya no lo están pero
 * conservan una póliza que no terminó). Lo que pide atención va primero.
 *
 * Quien ya no está activa y no tiene ninguna póliza que siga corriendo es historia y no
 * sale, aunque `equipo` la traiga: `equipo` y `polizas` son dos consultas, y a medianoche
 * (hora de Lima) una póliza puede vencer entre la una y la otra. Pedir «la baja de una
 * póliza vigente» que ya no lo es sería avisar de algo falso.
 */
export function seguroPorPersona(
  equipo: readonly FilaEquipoSeguro[],
  polizas: readonly Poliza[],
  cambios: readonly CambioSeguro[],
  hoy: string,
): SeguroDePersona[] {
  const polizasDe = agrupar(polizas, (z) => z.persona_id);
  const cambiosDe = agrupar(cambios, (c) => c.persona_id);

  const personas = equipo.map((f): SeguroDePersona | null => {
    const todas = [...(polizasDe.get(f.persona_id) ?? [])].sort(
      (a, b) => b.vigente_desde.localeCompare(a.vigente_desde) || b.poliza_id.localeCompare(a.poliza_id),
    );
    if (!f.activa && !todas.some((z) => z.vigente_hasta > hoy)) return null;
    const principales = f.tipo ? todas.filter((z) => z.producto === f.tipo) : [];
    const otras = todas.filter((z) => z.producto !== f.tipo);

    const cubre = principales.find((z) => z.cubre_hoy) ?? null;
    const proxima = principales.filter((z) => z.vigente_desde > hoy).sort((a, b) => a.vigente_desde.localeCompare(b.vigente_desde))[0] ?? null;
    const ultimaVencida = principales.find((z) => z.vigente_hasta <= hoy) ?? null;
    const actual = cubre ?? proxima ?? ultimaVencida ?? principales[0] ?? null;

    let hasta: string | null = null;
    let dias: number | null = null;
    if (cubre) {
      hasta = cubiertoHasta(cubre, principales);
      dias = diasEntre(hoy, hasta);
    }

    let situacion: SituacionSeguro;
    if (!f.activa) situacion = "baja_pendiente";
    else if (f.tipo === null) situacion = "sin_seguro";
    else if (!f.con_poliza) situacion = "por_planilla";
    else if (f.hueco) situacion = "hueco";
    else if (dias !== null && dias <= DIAS_AVISO_RENOVACION) situacion = "por_vencer";
    else situacion = "al_dia";

    let motivoHueco: MotivoHueco | null = null;
    if (situacion === "hueco") motivoHueco = ultimaVencida ? "vencida" : proxima ? "aun_no_empieza" : "nunca";

    const susCambios = [...(cambiosDe.get(f.persona_id) ?? [])].sort(
      (a, b) => b.fecha.localeCompare(a.fecha) || b.creado_at.localeCompare(a.creado_at) || b.id.localeCompare(a.id),
    );

    return {
      personaId: f.persona_id, persona: f.persona, sede: f.sede, vinculo: f.tipo_vinculo, modalidad: f.practicante_modalidad,
      activa: f.activa, situacion,
      tipo: f.tipo && f.tipo_nombre ? { clave: f.tipo, nombre: f.tipo_nombre } : null,
      origen: f.origen,
      asignacion: f.asignacion_id && f.asignacion_desde ? { id: f.asignacion_id, desde: f.asignacion_desde, motivo: f.asignacion_motivo ?? "" } : null,
      automatico: f.tipo_automatico && f.tipo_automatico_nombre ? { clave: f.tipo_automatico, nombre: f.tipo_automatico_nombre } : null,
      conPoliza: f.con_poliza, polizasPrincipales: principales, otras, actual,
      cubiertoHasta: hasta, diasParaQuedarSinSeguro: dias, motivoHueco,
      diasDesdeQueVencio: motivoHueco === "vencida" && ultimaVencida ? diasEntre(ultimaVencida.vigente_hasta, hoy) : null,
      empiezaEl: motivoHueco === "vencida" || motivoHueco === "aun_no_empieza" ? proxima?.vigente_desde ?? null : null,
      cambios: susCambios,
      cambiosPendientes: susCambios.filter((c) => c.baja_pendiente || c.alta_pendiente),
      // El papeleo de una póliza vencida de quien ya se fue no vuelve a pedir nada.
      conPapeleo: todas.filter((z) => pasosPendientes(z).length > 0 && (f.activa || z.cubre_hoy)),
    };
  }).filter((p): p is SeguroDePersona => p !== null);

  return personas.sort(
    (a, b) => rangoDeAtencion(a) - rangoDeAtencion(b)
      || compararDias(a.diasParaQuedarSinSeguro, b.diasParaQuedarSinSeguro)
      || a.persona.localeCompare(b.persona, "es")
      || a.personaId.localeCompare(b.personaId),
  );
}

/** Los días que faltan, de menos a más; quien no tiene cuenta (hueco, EsSalud) va después de quien sí. */
function compararDias(a: number | null, b: number | null): number {
  if (a === b) return 0;
  if (a === null) return 1;
  if (b === null) return -1;
  return a - b;
}

export interface ResumenSeguros {
  hueco: number;
  por_vencer: number;
  baja_pendiente: number;
  al_dia: number;
  por_planilla: number;
  sin_seguro: number;
  /** Cambios de seguro que todavía piden algún paso (uno por cambio, no por paso). */
  cambios: number;
  /** Pólizas con un paso del papeleo sin hacer. */
  papeleo: number;
}

/** Los totales de las tarjetas de arriba. Una persona cuenta UNA vez por situación. */
export function resumenDeSeguros(personas: readonly SeguroDePersona[]): ResumenSeguros {
  const r: ResumenSeguros = { hueco: 0, por_vencer: 0, baja_pendiente: 0, al_dia: 0, por_planilla: 0, sin_seguro: 0, cambios: 0, papeleo: 0 };
  for (const p of personas) {
    r[p.situacion] += 1;
    r.cambios += p.cambiosPendientes.length;
    r.papeleo += p.conPapeleo.length;
  }
  return r;
}

/**
 * Cuánta gente hay en cada tipo, en el orden del catálogo, más «Sin seguro» (no aplica)
 * al final. Los tipos sin nadie salen igual: que el filtro exista aunque hoy esté vacío.
 */
export function contarPorTipo(
  personas: readonly SeguroDePersona[],
  tipos: readonly Pick<TipoSeguro, "clave" | "nombre" | "principal" | "activo">[],
): { clave: string | null; nombre: string; n: number }[] {
  const cuenta = new Map<string | null, number>();
  for (const p of personas) {
    if (!p.activa) continue;
    cuenta.set(p.tipo?.clave ?? null, (cuenta.get(p.tipo?.clave ?? null) ?? 0) + 1);
  }
  const salida = tipos
    .filter((t) => t.principal && (t.activo || (cuenta.get(t.clave) ?? 0) > 0))
    .map((t) => ({ clave: t.clave as string | null, nombre: t.nombre, n: cuenta.get(t.clave) ?? 0 }));
  // Un tipo principal que ya no está en el catálogo (o archivado) pero tiene gente: sale igual.
  for (const [clave, n] of cuenta) {
    if (clave !== null && !salida.some((s) => s.clave === clave)) {
      const nombre = personas.find((p) => p.tipo?.clave === clave)?.tipo?.nombre ?? clave;
      salida.push({ clave, nombre, n });
    }
  }
  salida.push({ clave: null, nombre: "Sin seguro (no aplica)", n: cuenta.get(null) ?? 0 });
  return salida;
}

// ── Lo que entra a la Bandeja ───────────────────────────────────────────────

export type TipoPendienteSeguro = "sin_poliza" | "por_vencer" | "papeleo" | "baja" | "cambio_baja" | "cambio_alta";

/** Lo que la Bandeja necesita de cada pendiente de seguros, sin la forma que ella pinta. */
export interface PendienteSeguro {
  tipo: TipoPendienteSeguro;
  /** Único: `sin_poliza:<persona>`, `papeleo:<póliza>`, `cambio_baja:<cambio>`… */
  clave: string;
  personaId: string;
  persona: string;
  sede: string;
  polizaId: string | null;
  cambioId: string | null;
  titulo: string;
  detalle: string | null;
  /**
   * Para `sin_poliza`: por qué y hace cuánto. Para `por_vencer`: los días que faltan.
   * Para `cambio_baja` / `cambio_alta`: los días que pasaron desde que cambió.
   */
  motivoHueco: MotivoHueco | null;
  dias: number | null;
  /** Para `papeleo`: en qué va la prima y qué pasos faltan. */
  prima: { estado: EstadoPrima; dias: number | null; venceEl: string | null } | null;
  pasos: PasoSeguro[];
  /** Para `por_vencer`: la fecha en que se queda sin seguro (la EXCLUSIVA). Para un cambio: el día en que cambió. */
  hasta: string | null;
}

/**
 * Qué piden los seguros a DO. Seis cosas:
 *   · sin_poliza: su seguro principal pide póliza y no tiene una que cubra hoy. Lo más serio.
 *   · cambio_baja / cambio_alta: alguien cambió de seguro y falta uno de los dos pasos. UN
 *     pendiente por paso: la baja la pide una persona a la aseguradora o al contador, y el
 *     alta otra vez, y se cierran por separado. EXCEPTO el alta hacia un seguro con póliza
 *     cuando la persona ya figura en `sin_poliza`: es el mismo hecho dicho dos veces («sin
 *     póliza de FOLA» y «dar de alta en FOLA»), y una Bandeja que repite se aprende a ignorar.
 *     Ese alta se funde en la fila del hueco, que cuenta de dónde viene la persona.
 *   · por_vencer: cubierta, pero se queda sin seguro pronto y nada empalma.
 *   · papeleo: UNA fila por póliza con lo que falte de prima, firma y factura juntos. Tres
 *     filas por póliza llenarían la Bandeja de lo que es un solo trámite con el corredor.
 *   · baja: ya no está activa y su póliza sigue vigente.
 * El papeleo solo cuenta para quien está activa o tiene la póliza vigente; una persona que
 * se fue hace meses no vuelve a la Bandeja por una factura vieja.
 */
export function pendientesDeSeguros(personas: readonly SeguroDePersona[], hoy: string): PendienteSeguro[] {
  const items: PendienteSeguro[] = [];
  const vacio = { polizaId: null, cambioId: null, detalle: null, motivoHueco: null, dias: null, prima: null, pasos: [] as PasoSeguro[], hasta: null };

  for (const p of personas) {
    const base = { personaId: p.personaId, persona: p.persona, sede: p.sede };
    const nombre = p.tipo?.nombre ?? "su seguro";

    // El alta de un cambio que la persona ya trae como hueco: se cuenta en la fila del hueco.
    const altaDelHueco = (c: CambioSeguro) => p.situacion === "hueco" && c.alta_pendiente && c.a_tipo === p.tipo?.clave;
    const cambioDelHueco = p.cambiosPendientes.find(altaDelHueco);

    if (p.situacion === "hueco") {
      items.push({
        ...vacio, ...base, tipo: "sin_poliza", clave: `sin_poliza:${p.personaId}`,
        titulo: p.motivoHueco === "nunca" ? `Sin póliza de ${nombre}`
          : p.motivoHueco === "aun_no_empieza" ? `Hoy no tiene póliza de ${nombre} que cubra`
          : `Su póliza de ${nombre} venció y no tiene seguro`,
        detalle: [
          cambioDelHueco ? `Cambió el ${diaYMes(cambioDelHueco.fecha)}: ${resumenDelCambio(cambioDelHueco)}` : null,
          p.empiezaEl ? `La que ya está registrada empieza el ${diaYMes(p.empiezaEl)}` : null,
        ].filter(Boolean).join(" · ") || null,
        motivoHueco: p.motivoHueco, dias: p.diasDesdeQueVencio,
      });
    } else if (p.situacion === "por_vencer" && p.cubiertoHasta) {
      items.push({
        ...vacio, ...base, tipo: "por_vencer", clave: `por_vencer:${p.personaId}`,
        titulo: `Su póliza de ${nombre} está por vencer`,
        detalle: p.actual?.renueva_sola === true ? "La póliza dice que renueva sola: confirmar con el corredor" : "Falta registrar la renovación",
        dias: p.diasParaQuedarSinSeguro, hasta: p.cubiertoHasta,
      });
    } else if (p.situacion === "baja_pendiente") {
      // La que cubre hoy, o si ninguna, la que todavía no empieza: las dos hay que dar de baja.
      const viva = [...p.polizasPrincipales, ...p.otras];
      const z = viva.find((x) => x.cubre_hoy) ?? viva.find((x) => x.vigente_hasta > hoy);
      items.push({
        ...vacio, ...base, tipo: "baja", clave: `baja:${p.personaId}`,
        titulo: z
          ? `Ya no está activa y ${z.cubre_hoy ? `su póliza de ${z.producto_nombre} sigue vigente` : `tiene una póliza de ${z.producto_nombre} por empezar`}`
          : "Ya no está activa y conserva una póliza",
        detalle: "Pedir la baja a la aseguradora",
        polizaId: z?.poliza_id ?? null,
      });
    }

    for (const c of p.cambiosPendientes) {
      const que = `Cambió el ${diaYMes(c.fecha)}: ${resumenDelCambio(c)}`;
      // Cuántos días lleva pendiente; un cambio con fecha de hoy lleva cero, nunca negativo.
      const dias = Math.max(0, diasEntre(c.fecha, hoy));
      if (c.baja_pendiente) {
        items.push({
          ...vacio, ...base, tipo: "cambio_baja", clave: `cambio_baja:${c.id}`, cambioId: c.id,
          titulo: c.baja_texto, detalle: que, dias, hasta: c.fecha,
        });
      }
      if (c.alta_pendiente && !altaDelHueco(c)) {
        items.push({
          ...vacio, ...base, tipo: "cambio_alta", clave: `cambio_alta:${c.id}`, cambioId: c.id,
          titulo: c.alta_texto, detalle: que, dias, hasta: c.fecha,
        });
      }
    }

    for (const z of p.conPapeleo) {
      const pasos = pasosPendientes(z);
      const prima = estadoPrima(z, hoy);
      items.push({
        ...vacio, ...base, tipo: "papeleo", clave: `papeleo:${z.poliza_id}`, polizaId: z.poliza_id,
        titulo: pasos[0] === "pagada" ? `Prima del seguro (${z.producto_nombre}) sin pagar`
          : pasos[0] === "firmada" ? `Póliza del seguro (${z.producto_nombre}) sin firmar`
          : `Falta la factura del seguro (${z.producto_nombre})`,
        detalle: pasos.map((x) => PASOS_SEGURO.find((s) => s.paso === x)!.falta).join(" · "),
        prima: { estado: prima.estado, dias: prima.dias, venceEl: z.prima_vence_el }, pasos,
      });
    }
  }
  return items;
}

// ── Buscar ──────────────────────────────────────────────────────────────────

/** ¿La persona coincide con lo que se escribió en el buscador? Sin tildes ni mayúsculas. */
export function coincideSeguro(p: SeguroDePersona, texto: string): boolean {
  const q = sinTildes(texto.trim());
  if (!q) return true;
  const campos = [
    p.persona, p.sede, etiquetaVinculo(p.vinculo), p.tipo?.nombre,
    ...[...p.polizasPrincipales, ...p.otras].flatMap((z) => [z.numero_poliza, z.aseguradora, z.plan, z.producto_nombre]),
  ];
  return campos.some((c) => c && sinTildes(c).includes(q));
}

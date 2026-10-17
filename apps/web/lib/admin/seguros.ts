// ============================================================================
// seguros.ts — lo que la pantalla de Seguros decide para dibujar
// ============================================================================
// QUÉ PROMETE
//   Funciones puras sobre las filas de `fn_seguros_tablero` (0528): quién tiene
//   un hueco de cobertura, hasta cuándo sigue cubierta una persona contando las
//   renovaciones, en qué va la prima, qué papeleo falta, y qué de todo eso entra
//   a la Bandeja. Sin React ni Supabase: se prueba con vitest
//   (`tests/seguros.test.ts`).
//
// SOLO PRACTICANTES (Felipe, 2026-10-17)
//   FOLA es exclusiva de los practicantes y el seguro del resto del equipo
//   (EsSalud, por planilla) se deja como está: nada de aquí lista, mide ni avisa
//   de quien no sea practicante, salvo para pedir la baja de su póliza si dejó de serlo.
//
// QUÉ NO DECIDE
//   Quién tiene que tener póliza ni si una póliza cubre HOY. Eso lo dice la base
//   (`es_practicante_activo`, `cubre_hoy` y la fila sin póliza); aquí solo se
//   lee. Si esto lo recalculara, habría dos respuestas a «¿esta persona tiene
//   seguro?», y esa es justo la pregunta que no puede tener dos.
//   Tampoco compara el beneficio máximo con las 14 y 30 subvenciones del
//   convenio: eso pide la subvención de cada quien y la 0528 no la lee.
//
// QUÉ ASUME
//   `vigente_hasta` es EXCLUSIVO: la póliza cubre hasta las 12 M de ese día. Una
//   renovación que empieza el día en que termina la anterior no deja hueco.
//   Las fechas son de calendario de Lima (`AAAA-MM-DD`, sin hora ni huso).
// ============================================================================
import { diasEntre, diaYMes } from "../bandeja-mia";
import { sinTildes } from "../sin-tildes";

/** Una fila de `fn_seguros_tablero`: una póliza viva, o —con `poliza_id` null— el hueco de un practicante sin cobertura. */
export interface FilaSeguro {
  persona_id: string;
  persona: string;
  sede: string;
  practicante_modalidad: string | null;
  es_practicante_activo: boolean;
  poliza_id: string | null;
  aseguradora: string | null;
  numero_poliza: string | null;
  vigente_desde: string | null;
  vigente_hasta: string | null;
  cubre_hoy: boolean;
  prima_total: number | null;
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
  creada_at: string | null;
}

/** Una fila que SÍ es una póliza (no el hueco). */
export type Poliza = FilaSeguro & {
  poliza_id: string; numero_poliza: string; aseguradora: string; vigente_desde: string; vigente_hasta: string; prima_total: number;
};

export function esPoliza(f: FilaSeguro): f is Poliza {
  return f.poliza_id !== null;
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
  p: Pick<FilaSeguro, "pagada_el" | "prima_vence_el">,
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
export function fechaDelPaso(p: Pick<FilaSeguro, "pagada_el" | "firmada_el" | "factura_recibida_el">, paso: PasoSeguro): string | null {
  return paso === "pagada" ? p.pagada_el : paso === "firmada" ? p.firmada_el : p.factura_recibida_el;
}

/** Los pasos que faltan de UNA póliza, en el orden en que se hacen. */
export function pasosPendientes(p: Pick<FilaSeguro, "pagada_el" | "firmada_el" | "factura_recibida_el">): PasoSeguro[] {
  return PASOS_SEGURO.filter((x) => fechaDelPaso(p, x.paso) === null).map((x) => x.paso);
}

// ── Cobertura por persona ───────────────────────────────────────────────────

/**
 * hueco ........... practicante activo sin póliza que cubra HOY. El caso caro:
 *                   una persona sin ningún seguro (Ley 28518, art. 52.5).
 * por_vencer ...... cubierta hoy, pero se queda sin seguro en `DIAS_AVISO_RENOVACION`
 *                   días o menos y no hay una renovación que empalme.
 * al_dia .......... cubierta, con margen.
 * baja_pendiente .. ya no es practicante activo y su póliza sigue vigente: hay
 *                   que pedirle la baja a la aseguradora.
 */
export type SituacionSeguro = "hueco" | "por_vencer" | "al_dia" | "baja_pendiente";

export type MotivoHueco = "nunca" | "vencida" | "aun_no_empieza";

export interface SeguroDePersona {
  personaId: string;
  persona: string;
  sede: string;
  modalidad: string | null;
  esPracticanteActivo: boolean;
  situacion: SituacionSeguro;
  /** La póliza que habla por la persona: la que cubre hoy; si ninguna, la próxima en empezar; si ninguna, la última que venció. */
  actual: Poliza | null;
  /** Todas las vivas, la más reciente primero. */
  polizas: Poliza[];
  /** Hasta cuándo sigue cubierta sin interrupción (EXCLUSIVO), contando renovaciones que empalman. Null si hoy no cubre nada. */
  cubiertoHasta: string | null;
  /** Días que faltan para quedar sin seguro (si cubre hoy). Cuenta desde hoy hasta `cubiertoHasta`. */
  diasParaQuedarSinSeguro: number | null;
  motivoHueco: MotivoHueco | null;
  /** Si el hueco es por una póliza vencida: hace cuántos días terminó. */
  diasDesdeQueVencio: number | null;
  /** Si el hueco espera una póliza que ya está registrada: cuándo empieza. */
  empiezaEl: string | null;
}

const RANGO_SITUACION: Record<SituacionSeguro, number> = { hueco: 0, por_vencer: 1, baja_pendiente: 2, al_dia: 3 };

/** Hasta dónde llega la cobertura de `desde`, encadenando las pólizas que empiezan antes de que termine la anterior. */
export function cubiertoHasta(actual: Pick<Poliza, "vigente_hasta">, polizas: readonly Pick<Poliza, "vigente_desde" | "vigente_hasta">[]): string {
  let fin = actual.vigente_hasta;
  // Una póliza con `vigente_hasta > fin` y `vigente_desde <= fin` empalma. La
  // vuelta termina: cada una solo puede extender `fin` y el conjunto es finito.
  for (let i = 0; i <= polizas.length; i++) {
    const siguiente = polizas.find((p) => p.vigente_desde <= fin && p.vigente_hasta > fin);
    if (!siguiente) break;
    fin = siguiente.vigente_hasta;
  }
  return fin;
}

/**
 * Agrupa las filas del tablero por persona y resuelve su situación. Solo salen
 * las personas que piden mirar algo: practicantes activos, y quien dejó de serlo
 * pero conserva una póliza vigente. Una persona que se fue y cuya póliza ya
 * venció es historia, no una fila.
 */
export function seguroPorPersona(filas: readonly FilaSeguro[], hoy: string): SeguroDePersona[] {
  const porPersona = new Map<string, FilaSeguro[]>();
  for (const f of filas) {
    const lista = porPersona.get(f.persona_id);
    if (lista) lista.push(f); else porPersona.set(f.persona_id, [f]);
  }

  const salida: SeguroDePersona[] = [];
  for (const [personaId, lista] of porPersona) {
    const base = lista[0];
    const polizas = lista.filter(esPoliza).sort(
      (a, b) => b.vigente_desde.localeCompare(a.vigente_desde) || b.poliza_id.localeCompare(a.poliza_id),
    );
    const hayHueco = lista.some((f) => f.poliza_id === null);
    const cubre = polizas.find((p) => p.cubre_hoy) ?? null;

    if (!base.es_practicante_activo && !cubre) continue;

    const proxima = [...polizas].filter((p) => p.vigente_desde > hoy).sort((a, b) => a.vigente_desde.localeCompare(b.vigente_desde))[0] ?? null;
    const ultimaVencida = polizas.find((p) => p.vigente_hasta <= hoy) ?? null;
    const actual = cubre ?? proxima ?? ultimaVencida ?? polizas[0] ?? null;

    let hasta: string | null = null;
    let dias: number | null = null;
    if (cubre) {
      hasta = cubiertoHasta(cubre, polizas);
      dias = diasEntre(hoy, hasta);
    }

    let situacion: SituacionSeguro;
    if (!base.es_practicante_activo) situacion = "baja_pendiente";
    else if (hayHueco) situacion = "hueco";
    else if (dias !== null && dias <= DIAS_AVISO_RENOVACION) situacion = "por_vencer";
    else situacion = "al_dia";

    let motivoHueco: MotivoHueco | null = null;
    if (situacion === "hueco") {
      motivoHueco = ultimaVencida ? "vencida" : proxima ? "aun_no_empieza" : "nunca";
    }

    salida.push({
      personaId, persona: base.persona, sede: base.sede, modalidad: base.practicante_modalidad,
      esPracticanteActivo: base.es_practicante_activo, situacion, actual, polizas,
      cubiertoHasta: hasta, diasParaQuedarSinSeguro: dias, motivoHueco,
      diasDesdeQueVencio: motivoHueco === "vencida" && ultimaVencida ? diasEntre(ultimaVencida.vigente_hasta, hoy) : null,
      empiezaEl: motivoHueco === "vencida" || motivoHueco === "aun_no_empieza" ? proxima?.vigente_desde ?? null : null,
    });
  }

  return salida.sort(
    (a, b) => RANGO_SITUACION[a.situacion] - RANGO_SITUACION[b.situacion]
      || (a.diasParaQuedarSinSeguro ?? -1) - (b.diasParaQuedarSinSeguro ?? -1)
      || a.persona.localeCompare(b.persona, "es")
      || a.personaId.localeCompare(b.personaId),
  );
}

/** Los totales de las tarjetas de arriba. Una persona cuenta en UNA sola. */
export function resumenDeSeguros(personas: readonly SeguroDePersona[]): Record<SituacionSeguro, number> {
  const r: Record<SituacionSeguro, number> = { hueco: 0, por_vencer: 0, al_dia: 0, baja_pendiente: 0 };
  for (const p of personas) r[p.situacion] += 1;
  return r;
}

/** Cuántas pólizas vivas tienen un paso del papeleo pendiente. */
export function polizasConPapeleoPendiente(personas: readonly SeguroDePersona[]): number {
  return personas.reduce((n, p) => n + p.polizas.filter((z) => pasosPendientes(z).length > 0).length, 0);
}

// ── Lo que entra a la Bandeja ───────────────────────────────────────────────

export type TipoPendienteSeguro = "sin_poliza" | "por_vencer" | "papeleo" | "baja";

/** Lo que la Bandeja necesita de cada pendiente de seguros, sin la forma que ella pinta. */
export interface PendienteSeguro {
  tipo: TipoPendienteSeguro;
  /** Único: `sin_poliza:<persona>`, `papeleo:<póliza>`… */
  clave: string;
  personaId: string;
  persona: string;
  sede: string;
  polizaId: string | null;
  titulo: string;
  detalle: string | null;
  /** Para `sin_poliza`: por qué y hace cuánto. Para `por_vencer`: los días que faltan. */
  motivoHueco: MotivoHueco | null;
  dias: number | null;
  /** Para `papeleo`: en qué va la prima y qué pasos faltan. */
  prima: { estado: EstadoPrima; dias: number | null; venceEl: string | null } | null;
  pasos: PasoSeguro[];
  /** Para `por_vencer`: la fecha en que se queda sin seguro (la EXCLUSIVA). */
  hasta: string | null;
}

/**
 * Qué piden los seguros a DO. Cuatro cosas, y una fila de cada una —no seis—:
 *   · sin_poliza: un practicante activo sin cobertura hoy. Lo más serio.
 *   · por_vencer: cubierta, pero se queda sin seguro pronto y nada empalma.
 *   · papeleo: UNA fila por póliza con lo que falte de prima, firma y factura
 *     juntos. Tres filas por póliza llenarían la Bandeja de lo que es un solo
 *     trámite con el corredor.
 *   · baja: ya no es practicante y su póliza sigue vigente.
 * El papeleo solo cuenta para practicantes activos o con póliza vigente; una
 * persona que se fue hace meses no vuelve a la Bandeja por una factura vieja.
 */
export function pendientesDeSeguros(personas: readonly SeguroDePersona[], hoy: string): PendienteSeguro[] {
  const items: PendienteSeguro[] = [];
  const vacio = { polizaId: null, detalle: null, motivoHueco: null, dias: null, prima: null, pasos: [] as PasoSeguro[], hasta: null };

  for (const p of personas) {
    const base = { personaId: p.personaId, persona: p.persona, sede: p.sede };

    if (p.situacion === "hueco") {
      items.push({
        ...vacio, ...base, tipo: "sin_poliza", clave: `sin_poliza:${p.personaId}`,
        titulo: p.motivoHueco === "nunca" ? "Practicante sin póliza de seguro"
          : p.motivoHueco === "aun_no_empieza" ? "Hoy no tiene póliza que lo cubra"
          : "Su póliza venció y no tiene seguro",
        detalle: p.empiezaEl ? `La que ya está registrada empieza el ${diaYMes(p.empiezaEl)}` : null,
        motivoHueco: p.motivoHueco, dias: p.diasDesdeQueVencio,
      });
    } else if (p.situacion === "por_vencer" && p.cubiertoHasta) {
      items.push({
        ...vacio, ...base, tipo: "por_vencer", clave: `por_vencer:${p.personaId}`,
        titulo: "Se queda sin seguro pronto",
        detalle: p.actual?.renueva_sola === true ? "La póliza dice que renueva sola: confirmar con el corredor" : "Falta registrar la renovación",
        dias: p.diasParaQuedarSinSeguro, hasta: p.cubiertoHasta,
      });
    } else if (p.situacion === "baja_pendiente") {
      items.push({
        ...vacio, ...base, tipo: "baja", clave: `baja:${p.personaId}`,
        titulo: "Ya no es practicante y su póliza sigue vigente",
        detalle: "Pedir la baja a la aseguradora",
        polizaId: p.actual?.poliza_id ?? null,
      });
    }

    for (const z of p.polizas) {
      const pasos = pasosPendientes(z);
      if (pasos.length === 0) continue;
      // Una póliza vencida hace mucho de quien ya se fue no pide nada.
      if (!p.esPracticanteActivo && !z.cubre_hoy) continue;
      const prima = estadoPrima(z, hoy);
      items.push({
        ...vacio, ...base, tipo: "papeleo", clave: `papeleo:${z.poliza_id}`, polizaId: z.poliza_id,
        titulo: pasos[0] === "pagada" ? "Prima del seguro sin pagar" : pasos[0] === "firmada" ? "Póliza del seguro sin firmar" : "Falta la factura del seguro",
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
  const campos = [p.persona, p.sede, ...p.polizas.flatMap((z) => [z.numero_poliza, z.aseguradora, z.plan])];
  return campos.some((c) => c && sinTildes(c).includes(q));
}

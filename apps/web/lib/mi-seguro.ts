// ============================================================================
// mi-seguro.ts — lo que «Mi seguro» (Lo mío) decide para dibujar
// ============================================================================
// QUÉ PROMETE
//   Funciones puras sobre lo que contestan `fn_mi_seguro` y `fn_mis_polizas` (0530): en
//   qué situación está el seguro de una persona hoy, hasta cuándo sigue cubierta
//   contando las renovaciones que empalman, qué datos de la póliza ya están confirmados,
//   cómo se rotula y se nombra cada archivo, y el texto fijo de «cómo usarlo» de los
//   seguros que lo tienen. También cuál de sus pólizas COMPLEMENTARIAS (Vida Ley) se destaca:
//   un seguro que va además del principal tiene su propia tarjeta y no se confunde con él.
//   Sin React ni Supabase: se prueba con vitest
//   (`tests/mi-seguro.test.ts`).
//
// ES DE TODO EL EQUIPO (Felipe, 2026-10-17)
//   Cada colaborador ve SU seguro, sea cual sea: FOLA con su póliza, EsSalud «por
//   planilla»… La puerta es «es MI póliza», no «hoy estoy en ese seguro»: quien cambió de
//   seguro conserva las pólizas del anterior. Quién es de qué seguro lo dice la base
//   (`fn_seguro_tipo_principal`, 0528); aquí no se vuelve a decidir.
//
// QUÉ NO DECIDE
//   Si una póliza cubre HOY: lo dice la base (`cubre_hoy`), con el mismo cálculo del tablero
//   de DO. Si esto lo recalculara, la persona y DO leerían dos respuestas a «¿tengo seguro
//   hoy?». Tampoco dice si la prima está pagada ni si la cobertura está suspendida por mora
//   (DO lo calcula con `estadoPrima`: más de 30 días sin pagar la prima): esos datos no salen
//   de la base hacia la persona (ver la cabecera de la 0530). Por eso `textoDelResumen`
//   habla de la PÓLIZA —«vigente», «va hasta»— y nunca de que la persona «esté cubierta».
//   Y un seguro SIN póliza (EsSalud) no se explica más de lo que la base sabe: el nombre y que la
//   empresa lo gestiona con la planilla (el texto lo eligió Felipe, 2026-10-17: «se paga por
//   planilla» se leía como un descuento).
//
// POR QUÉ SE PARECE A `seguroPorPersona`
//   `lib/admin/seguros.ts` hace esta misma cuenta para el tablero de DO, sobre muchas
//   personas y con sus datos internos. Aquí es sobre una sola y sin ellos. Las dos tienen
//   que dar la misma respuesta para las mismas pólizas, y `tests/mi-seguro.test.ts` las
//   compara con una batería de casos. Se reutiliza la pieza que no cambia (`cubiertoHasta`) en vez
//   de escribirla otra vez. Lo único que a propósito NO coincide es CUÁNDO se avisa de un
//   vencimiento: DO a los 45 días (`DIAS_AVISO_RENOVACION`), la persona a los 15 (`DIAS_AVISO_PERSONA`).
// ============================================================================
import type { ClienteCayla } from "@cayla-dynamic/database";
import { diasEntre } from "./bandeja-mia";
import { cubiertoHasta, loVeLaPersona, plural, type MotivoHueco } from "./admin/seguros";

/**
 * Cuántos días antes de que termine la póliza se le avisa a la PERSONA. No es el de DO
 * (`DIAS_AVISO_RENOVACION`, 45): DO necesita semanas para renovar con el corredor, y la persona no
 * puede hacer nada con un aviso tan temprano —con una póliza de 92 días el ámbar salía casi la mitad
 * del tiempo—. Quince bastan para que mire si la renovación ya está registrada.
 */
export const DIAS_AVISO_PERSONA = 15;

export type TipoArchivoMio = "poliza" | "convenio_pago";

/** Un archivo que la persona puede abrir. No lleva el nombre con que DO lo subió. */
export interface ArchivoMio {
  id: string;
  tipo: TipoArchivoMio;
  storage_path: string;
  mime: string;
  bytes: number;
}

/** Su seguro principal de hoy: la única fila de `fn_mi_seguro`. */
export interface SeguroPrincipal {
  /** `seguros_tipos.clave`; null si no le corresponde ninguno (honorarios, sin vínculo laboral). */
  tipo: string | null;
  tipo_nombre: string | null;
  /** false = «por planilla» (EsSalud): no hay póliza que ver. También false si no tiene seguro principal. */
  con_poliza: boolean;
  /** Solo si su seguro lleva póliza: si alguna de ese tipo la cubre hoy. null si no lleva. */
  cubre_hoy: boolean | null;
}

/** Una póliza suya, de cualquier seguro, con sus archivos ya leídos. */
export interface PolizaMia {
  poliza_id: string;
  /** `seguros_tipos.clave` del seguro al que pertenece. */
  producto: string;
  /** «FOLA», «Vida Ley»…: como se llama el seguro. */
  producto_nombre: string;
  aseguradora: string;
  numero_poliza: string;
  vigente_desde: string;
  /** EXCLUSIVO: la póliza cubre hasta las 12 del mediodía de este día. */
  vigente_hasta: string;
  cubre_hoy: boolean;
  /** null = el corredor todavía no lo confirmó. */
  plan: string | null;
  beneficio_enfermedad: number | null;
  beneficio_accidente: number | null;
  archivos: ArchivoMio[];
}

/** Una fila de `fn_mis_polizas` tal como llega: `archivos` es un json sin tipar. */
export interface FilaMisPolizas extends Omit<PolizaMia, "archivos"> {
  archivos: unknown;
}

// ── Leer lo que manda la base ───────────────────────────────────────────────

/**
 * `archivos` llega como json. Se leen solo las entradas con la forma esperada y se
 * descarta lo demás en vez de reventar: una fila rara no tiene por qué tumbar la
 * sección entera.
 */
export function archivosDe(valor: unknown): ArchivoMio[] {
  if (!Array.isArray(valor)) return [];
  const salida: ArchivoMio[] = [];
  for (const x of valor) {
    if (!x || typeof x !== "object") continue;
    const a = x as Record<string, unknown>;
    if (typeof a.tipo !== "string" || !loVeLaPersona(a.tipo)) continue;
    if (typeof a.id !== "string" || typeof a.storage_path !== "string") continue;
    salida.push({
      id: a.id,
      tipo: a.tipo as TipoArchivoMio,
      storage_path: a.storage_path,
      mime: typeof a.mime === "string" ? a.mime : "application/pdf",
      bytes: typeof a.bytes === "number" ? a.bytes : 0,
    });
  }
  return salida;
}

export function leerPolizasMias(filas: readonly FilaMisPolizas[]): PolizaMia[] {
  return filas.map((f) => ({ ...f, archivos: archivosDe(f.archivos) }));
}

/**
 * Pide `fn_mi_seguro` y `fn_mis_polizas` a la vez. Nunca lanza: si cualquiera falla,
 * `error` trae un texto para leerse y no se inventa ni «sin seguro» ni «sin póliza».
 */
export async function traerMiSeguro(
  supabase: ClienteCayla,
): Promise<{ principal: SeguroPrincipal | null; polizas: PolizaMia[]; error: string | null }> {
  const [seguro, polizas] = await Promise.all([supabase.rpc("fn_mi_seguro"), supabase.rpc("fn_mis_polizas")]);
  if (seguro.error || polizas.error) {
    return { principal: null, polizas: [], error: "No pudimos leer tu seguro. Vuelve a intentarlo en un momento." };
  }
  const filas = (seguro.data ?? []) as unknown as SeguroPrincipal[];
  return {
    principal: filas[0] ?? null,
    polizas: leerPolizasMias((polizas.data ?? []) as unknown as FilaMisPolizas[]),
    error: null,
  };
}

// ── Cómo está su seguro hoy ─────────────────────────────────────────────────

/**
 * al_dia ........ su seguro principal lleva póliza y hoy tiene una vigente, con margen (o con
 *                 una renovación que empalma). «Vigente» es por fechas: la persona no ve la
 *                 prima, así que no puede saber si la cobertura se suspendió por mora.
 * por_vencer .... vigente hoy, pero se queda sin póliza en `DIAS_AVISO_PERSONA` días o
 *                 menos y no hay una renovación registrada que siga.
 * hueco ......... su seguro principal lleva póliza y hoy no lo cubre ninguna (`motivoHueco`
 *                 dice si nunca tuvo una, si venció o si la registrada aún no empieza).
 * por_planilla .. su seguro principal no lleva póliza (EsSalud): se paga por planilla.
 * sin_seguro .... no le corresponde un seguro principal (honorarios, sin vínculo laboral).
 *
 * Son las mismas situaciones de `SituacionSeguro` en el tablero de DO, sin `baja_pendiente`
 * (esa es una tarea de DO sobre quien ya no está activa).
 */
export type SituacionMiSeguro = "al_dia" | "por_vencer" | "hueco" | "por_planilla" | "sin_seguro";

export interface MiSeguro {
  situacion: SituacionMiSeguro;
  /** Su seguro principal de hoy, o null si no le corresponde ninguno. */
  tipo: { clave: string; nombre: string } | null;
  /** ¿Su seguro principal lleva póliza? */
  conPoliza: boolean;
  /** Las pólizas de su seguro principal, la más reciente primero. */
  principales: PolizaMia[];
  /** Todas las demás: las de otros seguros (complementarios) y las que le quedaron de uno anterior. */
  otras: PolizaMia[];
  /** La que habla por su seguro principal: la que cubre hoy; si ninguna, la próxima en empezar; si ninguna, la última que venció. */
  actual: PolizaMia | null;
  /** Hasta cuándo sigue cubierta sin interrupción (EXCLUSIVO), contando las renovaciones que empalman. Null si hoy no cubre. */
  cubiertoHasta: string | null;
  /** Días que faltan para quedar sin póliza, contados desde hoy. Null si hoy no cubre. */
  diasParaQuedarSinSeguro: number | null;
  motivoHueco: MotivoHueco | null;
  /** Si el hueco es por una póliza vencida: hace cuántos días terminó. */
  diasDesdeQueVencio: number | null;
  /** Si el hueco es por una póliza vencida: el día en que dejó de cubrir (EXCLUSIVO). */
  vencioEl: string | null;
  /** Si el hueco espera una póliza que ya está registrada: cuándo empieza. */
  empiezaEl: string | null;
  /**
   * Si hoy tiene póliza pero la que ya está registrada para después empieza DESPUÉS de donde llega la
   * cobertura continua: cuándo empieza. Entre una y otra hay un hueco, y `diasSinPoliza` lo cuenta.
   */
  empiezaDespuesEl: string | null;
  diasSinPoliza: number | null;
  /** Todas sus pólizas menos `actual`, la más reciente primero: lo que se dibuja debajo. */
  resto: PolizaMia[];
}

export function resolverMiSeguro(
  principal: Pick<SeguroPrincipal, "tipo" | "tipo_nombre" | "con_poliza" | "cubre_hoy"> | null,
  polizas: readonly PolizaMia[],
  hoy: string,
): MiSeguro {
  // Más reciente primero; `poliza_id` desempata para que el orden no dependa de cómo llegaron las filas.
  const todas = [...polizas].sort(
    (a, b) => b.vigente_desde.localeCompare(a.vigente_desde) || b.poliza_id.localeCompare(a.poliza_id),
  );
  const tipo = principal?.tipo && principal.tipo_nombre ? { clave: principal.tipo, nombre: principal.tipo_nombre } : null;
  const conPoliza = tipo !== null && principal?.con_poliza === true;
  const principales = tipo ? todas.filter((z) => z.producto === tipo.clave) : [];
  const otras = todas.filter((z) => z.producto !== tipo?.clave);

  const cubre = principales.find((z) => z.cubre_hoy) ?? null;
  const proxima = principales.filter((z) => z.vigente_desde > hoy)
    .sort((a, b) => a.vigente_desde.localeCompare(b.vigente_desde))[0] ?? null;
  const ultimaVencida = principales.find((z) => z.vigente_hasta <= hoy) ?? null;
  const actual = cubre ?? proxima ?? ultimaVencida ?? principales[0] ?? null;

  let hasta: string | null = null;
  let dias: number | null = null;
  if (cubre) {
    hasta = cubiertoHasta(cubre, principales);
    dias = diasEntre(hoy, hasta);
  }

  let situacion: SituacionMiSeguro;
  if (tipo === null) situacion = "sin_seguro";
  else if (!conPoliza) situacion = "por_planilla";
  // «Lo cubre hoy» lo dice la base; las pólizas solo cuentan cuánto falta.
  else if (principal?.cubre_hoy !== true) situacion = "hueco";
  else if (dias !== null && dias <= DIAS_AVISO_PERSONA) situacion = "por_vencer";
  else situacion = "al_dia";

  // Una póliza ya registrada que empieza después de donde llega la cobertura continua.
  const despues = hasta
    ? principales.filter((z) => z.vigente_desde > hasta).sort((a, b) => a.vigente_desde.localeCompare(b.vigente_desde))[0] ?? null
    : null;

  let motivoHueco: MotivoHueco | null = null;
  if (situacion === "hueco") motivoHueco = ultimaVencida ? "vencida" : proxima ? "aun_no_empieza" : "nunca";

  return {
    situacion, tipo, conPoliza, principales, otras, actual,
    cubiertoHasta: hasta, diasParaQuedarSinSeguro: dias, motivoHueco,
    diasDesdeQueVencio: motivoHueco === "vencida" && ultimaVencida ? diasEntre(ultimaVencida.vigente_hasta, hoy) : null,
    vencioEl: motivoHueco === "vencida" && ultimaVencida ? ultimaVencida.vigente_hasta : null,
    empiezaEl: motivoHueco === "vencida" || motivoHueco === "aun_no_empieza" ? proxima?.vigente_desde ?? null : null,
    empiezaDespuesEl: despues?.vigente_desde ?? null,
    diasSinPoliza: despues && hasta ? diasEntre(hasta, despues.vigente_desde) : null,
    resto: todas.filter((z) => z.poliza_id !== actual?.poliza_id),
  };
}

// ── Lo que dice la tarjeta de arriba ────────────────────────────────────────

export type VarianteResumen = "neutral" | "alerta" | "advertencia" | "positivo";

export interface TextoResumen {
  variante: VarianteResumen;
  /** Lo que dice la insignia. */
  insignia: string;
  titulo: string;
  detalle: string;
}

/** El cierre de las frases que hablan de una vigencia. Sirve igual para una suspensión, una baja o un error de fechas. */
export const SI_NO_CUADRA = "Si la aseguradora te dice otra cosa, avisa a Desarrollo Organizacional.";

/** «La que ya está registrada empieza el 05/11: entre una y otra quedan 4 días sin póliza.» */
function textoDelHueco(seguro: MiSeguro, fecha: (iso: string) => string): string {
  if (!seguro.empiezaDespuesEl) return "";
  const dias = seguro.diasSinPoliza ?? 0;
  return `La que ya está registrada empieza el ${fecha(seguro.empiezaDespuesEl)}` +
    `${dias > 0 ? `: entre una y otra quedan ${plural(dias, "día", "días")} sin póliza` : ""}.`;
}

/**
 * Lo que dice la tarjeta de arriba de «Mi seguro». Vive aquí y no en la pantalla para poder
 * probar lo que NO debe decir.
 *
 * NUNCA AFIRMA COBERTURA. Habla de la PÓLIZA y de sus fechas («vigente», «va hasta»), no de
 * que la persona «esté cubierta». La base sabe si una póliza está vigente por fechas
 * (`cubre_hoy`), pero no si la cobertura se suspendió sola porque la prima lleva más de 30 días
 * sin pagarse (convenio de pago, cláusula quinta): eso lo calcula la pantalla de DO con
 * `estadoPrima`, y a la persona no le llega ni la prima ni su estado. Decirle «tu póliza cubre»
 * a quien tiene la cobertura suspendida es mandarla a una clínica a que se lo nieguen. Por eso
 * las frases con fecha cierran con «si la aseguradora te dice otra cosa, avisa a Desarrollo
 * Organizacional», sin acusar a nadie de lo que la pantalla no sabe.
 *
 * `fecha` formatea un `YYYY-MM-DD` para leerse («17/10/2026»); se recibe para que esto no dependa
 * de nada de la pantalla.
 */
export function textoDelResumen(seguro: MiSeguro, fecha: (iso: string) => string): TextoResumen {
  const nombre = seguro.tipo?.nombre ?? "";
  const hasta = seguro.cubiertoHasta ? fecha(seguro.cubiertoHasta) : null;

  switch (seguro.situacion) {
    case "sin_seguro":
      return {
        variante: "neutral", insignia: "Sin seguro asignado",
        titulo: "No tienes un seguro asignado en el sistema",
        detalle: "Si crees que debería haber uno, avisa a Desarrollo Organizacional.",
      };
    case "por_planilla":
      return {
        variante: "neutral", insignia: "Por planilla",
        titulo: `Tu seguro es ${nombre}`,
        detalle: "La empresa lo gestiona con la planilla; este seguro no tiene póliza ni PDF.",
      };
    case "hueco": {
      const base = { variante: "alerta" as const, insignia: "Sin póliza vigente" };
      if (seguro.motivoHueco === "nunca") {
        // Lo único que el sistema sabe es que DO todavía no la registró: no es una alarma.
        return {
          variante: "advertencia", insignia: "Sin póliza registrada", titulo: "Todavía no tienes una póliza registrada",
          detalle: `Tu seguro es ${nombre} y lleva póliza. Cuando Desarrollo Organizacional la registre, aquí vas a ver su número y tu PDF. Si crees que ya deberías tenerla, avisa a Desarrollo Organizacional.`,
        };
      }
      if (seguro.motivoHueco === "aun_no_empieza") {
        return {
          ...base, titulo: "Hoy no tienes una póliza vigente registrada",
          detalle: `La póliza de ${nombre} que está registrada a tu nombre empieza el ${seguro.empiezaEl ? fecha(seguro.empiezaEl) : "—"}. Hasta entonces, avisa a Desarrollo Organizacional para que lo revise.`,
        };
      }
      // El último día la póliza todavía cubre hasta las 12 del mediodía: decir «terminó» sería falso.
      if (seguro.diasDesdeQueVencio === 0) {
        return {
          variante: "advertencia", insignia: "Termina hoy", titulo: "Tu póliza termina hoy",
          detalle:
            `Tu póliza de ${nombre} va hasta hoy a las 12 del mediodía.` +
            `${seguro.empiezaEl ? ` La que ya está registrada empieza el ${fecha(seguro.empiezaEl)}.` : ""}` +
            " Avisa a Desarrollo Organizacional para que lo revise.",
        };
      }
      const hace = seguro.diasDesdeQueVencio ? ` (hace ${plural(seguro.diasDesdeQueVencio, "día", "días")})` : "";
      return {
        ...base, titulo: "Hoy no tienes una póliza vigente registrada",
        detalle:
          `Tu última póliza de ${nombre} terminó el ${seguro.vencioEl ? fecha(seguro.vencioEl) : "—"}${hace}.` +
          `${seguro.empiezaEl ? ` La que ya está registrada empieza el ${fecha(seguro.empiezaEl)}.` : ""}` +
          " Avisa a Desarrollo Organizacional para que lo revise.",
      };
    }
    case "por_vencer":
      return {
        variante: "advertencia",
        insignia: `Vence en ${plural(seguro.diasParaQuedarSinSeguro ?? 0, "día", "días")}`,
        titulo: "Tu póliza vence pronto",
        detalle:
          `Tu seguro es ${nombre}. Tu póliza va hasta el ${hasta ?? "—"} a las 12 del mediodía.` +
          `${seguro.empiezaDespuesEl ? ` ${textoDelHueco(seguro, fecha)}` : " Todavía no hay otra registrada que siga."} ` +
          "Si se acerca la fecha y no la ves aquí, o si la aseguradora te dice otra cosa, avisa a Desarrollo Organizacional.",
      };
    default:
      return {
        variante: "positivo", insignia: "Vigente",
        titulo: "Tu póliza está vigente",
        detalle:
          `Tu seguro es ${nombre}. Tu póliza va hasta el ${hasta ?? "—"} a las 12 del mediodía.` +
          `${seguro.empiezaDespuesEl
            ? ` ${textoDelHueco(seguro, fecha)}`
            : seguro.cubiertoHasta !== seguro.actual?.vigente_hasta ? " Ya está registrada la renovación que sigue." : ""}` +
          ` ${SI_NO_CUADRA}`,
      };
  }
}

/**
 * ¿El resumen de arriba solo repite lo que la tarjeta de la póliza ya muestra? Pasa cuando la póliza
 * vigente es la única que cuenta: no vence pronto, no hay otra registrada que empiece después ni una
 * renovación que alargue la cobertura. En ese caso la pantalla deja «Vigente» y la fecha en la tarjeta
 * y de la frase del resumen conserva solo lo que no está en otro lado (`SI_NO_CUADRA`). Con cualquier
 * otra situación —vence pronto, un hueco entre pólizas, una renovación— el resumen se muestra entero:
 * es lo que la persona tiene que leer.
 */
export function resumenSoloRepite(seguro: MiSeguro): boolean {
  return seguro.situacion === "al_dia"
    && seguro.actual !== null
    && seguro.actual.cubre_hoy
    && seguro.empiezaDespuesEl === null
    && seguro.cubiertoHasta === seguro.actual.vigente_hasta;
}

// ── Las fechas de una póliza, dichas con honestidad ─────────────────────────

/** ¿Es una fecha `YYYY-MM-DD`? La base exige `vigente_desde` y `vigente_hasta` (0528), pero la pantalla no inventa una si no llegan. */
export function fechaConocida(valor: unknown): valor is string {
  return typeof valor === "string" && /^\d{4}-\d{2}-\d{2}$/.test(valor);
}

export type EstadoVigencia = "vigente" | "por_empezar" | "termina_hoy" | "vencida" | "sin_fecha_de_fin" | "sin_fechas";

/**
 * En qué punto de su vida está una póliza hoy. `cubre_hoy` lo dice la base; las fechas solo sirven para
 * distinguir entre «aún no empieza», «termina hoy» y «venció». Si el papel no trajo una fecha, NO se
 * adivina «Vencida» ni «Vigente»: se dice que falta (ver `textoDeVigencia`).
 */
export function estadoDeVigencia(
  p: Pick<PolizaMia, "cubre_hoy" | "vigente_desde" | "vigente_hasta">,
  hoy: string,
): EstadoVigencia {
  if (!fechaConocida(p.vigente_desde)) return "sin_fechas";
  if (!fechaConocida(p.vigente_hasta)) return "sin_fecha_de_fin";
  if (p.cubre_hoy) return "vigente";
  if (p.vigente_desde > hoy) return "por_empezar";
  if (p.vigente_hasta === hoy) return "termina_hoy";
  return "vencida";
}

/** «Del 01/10/2026 al 01/01/2027, hasta las 12 del mediodía», o lo que el papel sí trae. */
export function textoDeVigencia(
  p: Pick<PolizaMia, "vigente_desde" | "vigente_hasta">,
  fecha: (iso: string) => string,
): string {
  if (!fechaConocida(p.vigente_desde)) return "El papel de la póliza no trae fechas de vigencia. Pídelas a Desarrollo Organizacional.";
  if (!fechaConocida(p.vigente_hasta)) {
    return `Desde el ${fecha(p.vigente_desde)}. El papel de la póliza no trae la fecha en que termina. Pídela a Desarrollo Organizacional.`;
  }
  return `Del ${fecha(p.vigente_desde)} al ${fecha(p.vigente_hasta)}, hasta las 12 del mediodía`;
}

// ── Una póliza que va ADEMÁS del seguro principal ───────────────────────────

/** Una póliza complementaria que cubre hoy, lista para dibujarse con su propia tarjeta. */
export interface PolizaComplementaria {
  poliza: PolizaMia;
  /** Hasta cuándo llega sin interrupción (EXCLUSIVO), contando las renovaciones que empalman. */
  hasta: string;
  dias: number;
  porVencer: boolean;
}

/**
 * Las pólizas de seguros que van ADEMÁS del principal (Vida Ley) y que cubren hoy: una por seguro, la
 * más reciente. Salen de `otras`, así que nunca es la del seguro principal. Cada una tiene su tarjeta
 * y su guía; si no la destacáramos, una persona en EsSalud vería su Vida Ley como una fila más de
 * «Tus pólizas», debajo de un resumen que dice «no hay póliza».
 *
 * Qué seguro es complementario lo dice la guía (`GuiaDeUso.complementario`), no una lista aparte: sin
 * guía, un seguro que DO agregue sigue apareciendo en «Tus pólizas», como hasta ahora.
 */
export function polizasComplementarias(seguro: Pick<MiSeguro, "otras">, hoy: string): PolizaComplementaria[] {
  const salida: PolizaComplementaria[] = [];
  for (const z of seguro.otras) {
    if (!z.cubre_hoy || !Object.hasOwn(GUIAS_DE_USO, z.producto) || !GUIAS_DE_USO[z.producto].complementario) continue;
    if (salida.some((c) => c.poliza.producto === z.producto)) continue;
    if (!fechaConocida(z.vigente_hasta)) continue;
    const hasta = cubiertoHasta(z, seguro.otras.filter((o) => o.producto === z.producto && fechaConocida(o.vigente_hasta)));
    const dias = diasEntre(hoy, hasta);
    salida.push({ poliza: z, hasta, dias, porVencer: dias <= DIAS_AVISO_PERSONA });
  }
  return salida;
}

/**
 * Lo que dice la tarjeta de una póliza complementaria. Mismo molde y misma regla que `textoDelResumen`:
 * habla de la PÓLIZA y de sus fechas, nunca de que la persona «esté cubierta».
 */
export function textoDeComplementaria(c: PolizaComplementaria, fecha: (iso: string) => string): TextoResumen {
  const hasta = fecha(c.hasta);
  if (c.porVencer) {
    return {
      variante: "advertencia", insignia: `Vence en ${plural(c.dias, "día", "días")}`,
      titulo: "Tu póliza vence pronto",
      detalle: `Tu póliza va hasta el ${hasta} a las 12 del mediodía. Si se acerca la fecha y no ves aquí la que sigue, o si la aseguradora te dice otra cosa, avisa a Desarrollo Organizacional.`,
    };
  }
  return {
    variante: "positivo", insignia: "Vigente",
    titulo: "Tu póliza está vigente",
    detalle: `Tu póliza va hasta el ${hasta} a las 12 del mediodía. ${SI_NO_CUADRA}`,
  };
}

// ── Lo que la póliza ya tiene confirmado ────────────────────────────────────

export interface DatoConfirmado {
  etiqueta: string;
  valor: string;
}

/**
 * El plan y los beneficios máximos que el corredor ya confirmó, y NADA de lo que no. Un dato
 * sin confirmar (null) no se muestra ni como «pendiente»: el convenio de FOLA ya promete 14 y
 * 30 subvenciones, y una cifra equivocada —o un «sin confirmar» que se lee como «no cubre»— es
 * peor que callar. `dinero` formatea los soles.
 */
export function datosConfirmados(
  p: Pick<PolizaMia, "plan" | "beneficio_enfermedad" | "beneficio_accidente">,
  dinero: (n: number) => string,
): DatoConfirmado[] {
  const datos: DatoConfirmado[] = [];
  if (p.plan && p.plan.trim() !== "") datos.push({ etiqueta: "Plan", valor: p.plan.trim() });
  if (p.beneficio_enfermedad !== null) datos.push({ etiqueta: "Máximo anual por enfermedad", valor: dinero(p.beneficio_enfermedad) });
  if (p.beneficio_accidente !== null) datos.push({ etiqueta: "Máximo anual por accidente", valor: dinero(p.beneficio_accidente) });
  return datos;
}

// ── Los archivos ────────────────────────────────────────────────────────────

const ROTULO: Record<TipoArchivoMio, string> = { poliza: "Tu póliza", convenio_pago: "Convenio de pago" };

/**
 * Cómo se llama un archivo en pantalla: por su TIPO, nunca por el nombre con que DO lo subió
 * (esa palabra la escribe otra persona y la base ni siquiera la manda). Si hay varios del mismo
 * tipo se numeran: «Tu póliza (2)».
 */
export function rotuloDeArchivo(archivo: ArchivoMio, de: readonly ArchivoMio[]): string {
  const base = ROTULO[archivo.tipo];
  const mismos = de.filter((a) => a.tipo === archivo.tipo);
  if (mismos.length <= 1) return base;
  return `${base} (${mismos.findIndex((a) => a.id === archivo.id) + 1})`;
}

const EXTENSION_POR_MIME: Record<string, string> = {
  "application/pdf": "pdf",
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "image/heic": "heic",
  "image/heif": "heif",
};

/** Solo letras, cifras y guiones, sin tildes: lo que un nombre de archivo aguanta en cualquier equipo. */
function paraNombreDeArchivo(texto: string): string {
  return texto.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^A-Za-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
}

/**
 * El nombre con que se guarda al descargar: `Poliza-FOLA-<número>.pdf`. Solo letras, cifras y
 * guiones: el número lo tecleó DO y podría traer espacios o una barra, que en un nombre de
 * archivo rompen o se leen mal. Sin el nombre de la persona: el archivo queda en sus
 * descargas, a la vista de quien use ese equipo.
 */
export function nombreDeDescarga(
  archivo: ArchivoMio,
  poliza: Pick<PolizaMia, "numero_poliza" | "producto_nombre">,
): string {
  const seguro = paraNombreDeArchivo(poliza.producto_nombre) || "Seguro";
  const numero = paraNombreDeArchivo(poliza.numero_poliza) || "sin-numero";
  // La extensión del mime; si no la conocemos, la de la ruta SOLO si parece una (letras y cifras): nunca un pedazo de ruta.
  const delRuta = archivo.storage_path.split(".").pop() ?? "";
  const extension = EXTENSION_POR_MIME[archivo.mime] ?? (/^[a-z0-9]{2,5}$/.test(delRuta) ? delRuta : "pdf");
  return `${archivo.tipo === "poliza" ? "Poliza" : "Convenio-de-pago"}-${seguro}-${numero}.${extension}`;
}

// ── El texto fijo: cómo usar un seguro ──────────────────────────────────────
// Hay DOS: el de FOLA, que salió del resumen informativo de la póliza de Pacífico (páginas 2 a 5 del
// PDF que tiene Felipe), y el de Vida Ley, del certificado de la póliza de la empresa. NO es la póliza: lo que vale es el PDF, y la pantalla lo
// dice. Si el producto cambia en una renovación hay que volver a leer ese resumen y corregir
// esto; no hay otra copia del texto.
//
// Va por la CLAVE del seguro (`seguros_tipos.clave`) y no por una pregunta del código, porque
// el contenido es de un producto concreto: la clave de FOLA es de sistema y no cambia (0528).
// Un seguro sin entrada aquí —EsSalud, o uno que DO agregue— no muestra guía, y esa es la
// respuesta correcta: no se inventan explicaciones de lo que no se tiene a mano. Lo
// deseable, el día que haga falta una segunda guía, es que viva en el catálogo (una columna de
// `seguros_tipos`) y no en el código.

export interface PasoDeUso {
  clave: string;
  titulo: string;
  texto: string;
}

/** Un teléfono de la aseguradora con lo que sirve para cada cosa: la póliza distingue los dos. */
export interface TelefonoDeUso {
  numero: string;
  uso: string;
}

export interface GuiaDeUso {
  /** De quién son los teléfonos: «Pacífico». */
  aseguradora: string;
  /**
   * true = este seguro va ADEMÁS del principal (Vida Ley): tiene su propia tarjeta y su guía no habla de
   * «baja». false = es uno que la persona usa como principal (FOLA). Es lo que ya dicen
   * `seguros_tipos.principal` y la 0543; se repite aquí porque la guía ya es por producto, y el día que
   * viva en una columna de `seguros_tipos` (ver arriba) esto se lee de ahí.
   */
  complementario: boolean;
  /** En el orden en que se necesitan: primero lo urgente. */
  pasos: readonly PasoDeUso[];
  telefonos: readonly TelefonoDeUso[];
  /** Algunas cosas que la póliza no cubre (no es la lista completa). */
  noCubre: readonly string[];
}

/**
 * Cómo se usa cada seguro con póliza. Hoy FOLA y Vida Ley (los pasos de abajo son de FOLA; ver el aparte de Vida Ley).
 *
 * REVISADA CONTRA LA PÓLIZA (2026-10-19, «Resumen informativo» y tabla de beneficios del PDF de una
 * póliza FOLA de Pacífico). Lo que cambió respecto del resumen anterior, y por qué importa:
 *   · Primero la EMERGENCIA, con el plazo de 24 horas para avisar a Pacífico: la póliza dice que ese
 *     es el máximo para dar el aviso y contar con la cobertura. La guía anterior solo decía «avísale
 *     apenas sepas la fecha», que es para una operación programada.
 *   · «Atención al crédito» ya no dice «basta con mostrar tu DNI»: en la red se paga un deducible fijo
 *     y un coaseguro que dependen de la red de la clínica. NO se escriben montos: no sabemos en qué red
 *     está cada clínica, y una cifra equivocada es peor que mandar a la tabla de beneficios.
 *   · El reembolso es para la atención FUERA de la red, se liquida por el tarifario de Pacífico (puede
 *     devolver menos de lo pagado) y no todo va en original (los resultados, en copia).
 *   · El seguro dura lo que el convenio de prácticas: la póliza cubre «en su calidad de practicante».
 *   · Los dos teléfonos tienen uso propio en la póliza, y ahora se rotulan.
 * El plan y el beneficio máximo siguen SIN decirse: el campo está vacío en la póliza.
 * Va por la clave del seguro; el día que haga falta una segunda guía, lo sano es una columna en
 * `seguros_tipos` (ver docs/estado.md).
 */
export const GUIAS_DE_USO: Readonly<Record<string, GuiaDeUso>> = {
  salud_practicantes: {
    aseguradora: "Pacífico",
    complementario: false,
    pasos: [
      {
        clave: "emergencia",
        titulo: "Si es una emergencia",
        texto:
          "Llama a la Central de Emergencias y Asistencia de Pacífico (su teléfono está en esta pantalla) o ve a una " +
          "clínica de la red con tu documento de identidad. Para contar con la cobertura, el aviso a Pacífico tiene que " +
          "darse dentro de las 24 horas de ocurrida la emergencia. Hasta que te estabilicen no hay deducible ni " +
          "coaseguro; después se aplican los de siempre.",
      },
      {
        clave: "credito",
        titulo: "Atención en la red de Pacífico",
        texto:
          "En una clínica de la red, muestra tu documento de identidad y paga solo el deducible y el porcentaje " +
          "(coaseguro) que te toque según la red a la que pertenezca esa clínica. Los montos están en la tabla de " +
          "beneficios de tu póliza.",
      },
      {
        clave: "hospitalizacion",
        titulo: "Si te van a hospitalizar o a operar",
        texto:
          "La clínica pide a Pacífico una carta de garantía, con un mínimo de 3 días útiles de anticipación (en una " +
          "emergencia no hace falta). Pacífico la da solo si esa atención está cubierta, y la clínica te avisa si salió. " +
          "Avisa a la clínica apenas sepas la fecha.",
      },
      {
        clave: "domicilio",
        titulo: "Médico a domicilio",
        texto:
          "Llama a la Central de Emergencias y Asistencia de Pacífico (Pacífico Asiste). Solo llega a las zonas que " +
          "Pacífico define, que figuran en tu póliza. En Lima atienden las 24 horas; en provincias, de 8 a 20 horas y " +
          "solo medicina general. La visita lleva un deducible. En provincias, una emergencia grave a domicilio se paga " +
          "primero y se pide reembolso.",
      },
      {
        clave: "reembolso",
        titulo: "Si te atendiste fuera de la red",
        texto:
          "Pagas tú y luego pides el reembolso a Pacífico dentro de 90 días calendario desde la atención. Pacífico paga " +
          "según su tarifario, con deducible y coaseguro: puede devolverte menos de lo que pagaste. Lleva la solicitud " +
          "firmada por tu médico, y en original las facturas o recibos, la receta y la orden de exámenes; de los " +
          "resultados, copia.",
      },
      {
        clave: "convenio",
        titulo: "Cuánto dura tu seguro",
        texto:
          "Tu seguro vale mientras formes parte de un convenio de prácticas vigente. Si el convenio termina, el seguro " +
          "también.",
      },
    ],
    telefonos: [
      { numero: "(01) 415-1515", uso: "Emergencias, ambulancia, médico a domicilio y dudas sobre cómo pedir tu atención" },
      { numero: "(01) 513-5000", uso: "Call Center de Pacífico" },
    ],
    noCubre: [
      "Gestación, parto y cesárea",
      "Odontología, salvo por accidente (y sin prótesis)",
      "Salud mental",
      "Preexistencias: lo que ya tenías antes de entrar a la póliza, salvo que ya lo cubriera una póliza anterior de otra aseguradora del país",
      "Enfermedades congénitas",
      "Cirugía estética, salvo por un accidente cubierto",
    ],
  },

  // Seguro de Vida Ley (D. Leg. 688). Sacado del certificado de la póliza de la empresa y de la 0543, no
  // de un resumen del corredor. Lo que NO dice, a propósito: el trámite de un siniestro, los beneficiarios
  // y cualquier teléfono —no se tienen a mano y no se inventan—, y nada de «cubierta» ni de la prima:
  // la persona no ve si está pagada (ver la cabecera). Habla de lo que dice la PÓLIZA. Si el certificado
  // cambia en una renovación hay que volver a leerlo y corregir esto.
  vida_ley: {
    aseguradora: "Pacífico",
    complementario: true,
    pasos: [
      {
        clave: "que_es",
        titulo: "Qué es",
        texto:
          "Es un seguro de vida en grupo que la ley obliga a la empresa a tener para quienes están en planilla. Lo " +
          "paga la empresa: no tiene costo para ti. Va además de tu seguro de salud.",
      },
      {
        clave: "capital",
        titulo: "Qué dice la póliza",
        texto:
          "Por muerte natural, el capital asegurado es de 16 remuneraciones mensuales asegurables. Por muerte " +
          "accidental, y por invalidez total y permanente por accidente, es de 32.",
      },
      {
        clave: "duracion",
        titulo: "Cuánto dura",
        texto: "Sigue mientras estés en planilla y la póliza de la empresa esté al día.",
      },
      {
        clave: "certificado",
        titulo: "Tu certificado",
        texto:
          "Tu certificado es el PDF que aparece arriba, en «Tu póliza»: ábrelo o descárgalo cuando lo necesites. Si " +
          "no lo ves, pídeselo a Desarrollo Organizacional.",
      },
    ],
    telefonos: [],
    noCubre: [],
  },
};

export interface GuiaQueAplica {
  clave: string;
  nombre: string;
  guia: GuiaDeUso;
  /** ¿Va además del seguro principal (Vida Ley)? Entonces su guía no habla de «baja» ni de «tu seguro principal ahora es…». */
  complementario: boolean;
  /**
   * ¿Es el seguro principal de la persona hoy? Si no —pasó de FOLA a EsSalud y la póliza sigue vigente
   * hasta que la aseguradora procese la baja—, la pantalla lo dice junto a la guía para no mostrar dos
   * «tu seguro» distintos sin explicación.
   */
  esPrincipal: boolean;
}

/**
 * Las guías de uso que le sirven HOY a esta persona: una por cada seguro del que tiene una póliza
 * que cubre hoy y del que hay guía. Una póliza vencida o que aún no empieza no se usa, así que
 * no se explica cómo usarla. `principal` es la clave de su seguro principal de hoy (o null).
 */
export function guiasQueAplican(polizas: readonly PolizaMia[], principal: string | null = null): GuiaQueAplica[] {
  const salida: GuiaQueAplica[] = [];
  for (const z of polizas) {
    if (!z.cubre_hoy || salida.some((g) => g.clave === z.producto)) continue;
    // `hasOwn`: la clave la crea DO, y un seguro llamado «constructor» no puede encontrar la guía de otro objeto.
    if (!Object.hasOwn(GUIAS_DE_USO, z.producto)) continue;
    salida.push({ clave: z.producto, nombre: z.producto_nombre, guia: GUIAS_DE_USO[z.producto], complementario: GUIAS_DE_USO[z.producto].complementario, esPrincipal: z.producto === principal });
  }
  return salida;
}

/**
 * Un teléfono de Lima escrito «(01) 415-1515» como enlace para llamar desde el teléfono:
 * `tel:+5114151515` (51 es Perú; el 1, Lima). Si la cuenta saliera mal, tocar el número marcaría
 * OTRO: por eso está aquí y con su prueba.
 */
export function enlaceTelefono(telefono: string): string {
  const cifras = telefono.replace(/\D/g, "").replace(/^0/, "");
  return `tel:+51${cifras}`;
}

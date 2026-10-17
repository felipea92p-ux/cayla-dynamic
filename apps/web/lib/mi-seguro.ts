// ============================================================================
// mi-seguro.ts — lo que «Mi seguro» (Lo mío) decide para dibujar
// ============================================================================
// QUÉ PROMETE
//   Funciones puras sobre lo que contestan `fn_mi_seguro` y `fn_mis_polizas` (0530): en
//   qué situación está el seguro de una persona hoy, hasta cuándo sigue cubierta
//   contando las renovaciones que empalman, qué datos de la póliza ya están confirmados,
//   cómo se rotula y se nombra cada archivo, y el texto fijo de «cómo usarlo» de los
//   seguros que lo tienen. Sin React ni Supabase: se prueba con vitest
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
//   hoy?». Tampoco dice si la prima está pagada ni si la cobertura está suspendida por mora:
//   esos datos no salen de la base hacia la persona (ver la cabecera de la 0530), y «al día»
//   aquí es que la póliza está vigente. Y un seguro SIN póliza (EsSalud) no se explica: lo
//   que se le dice a la persona lo decide Felipe, y por ahora es lo que la base sabe —el
//   nombre y que va por planilla—.
//
// POR QUÉ SE PARECE A `seguroPorPersona`
//   `lib/admin/seguros.ts` hace esta misma cuenta para el tablero de DO, sobre muchas
//   personas y con sus datos internos. Aquí es sobre una sola y sin ellos. Las dos tienen
//   que dar la misma respuesta para las mismas pólizas, y `tests/mi-seguro.test.ts` las
//   compara con una batería de casos. Se reutilizan las piezas que no cambian
//   (`cubiertoHasta`, `DIAS_AVISO_RENOVACION`) en vez de escribirlas otra vez.
// ============================================================================
import type { ClienteCayla } from "@cayla-dynamic/database";
import { diasEntre } from "./bandeja-mia";
import { cubiertoHasta, DIAS_AVISO_RENOVACION, loVeLaPersona, type MotivoHueco } from "./admin/seguros";

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
  /** EXCLUSIVO: la póliza cubre hasta las 12 M de este día. */
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
 * al_dia ........ su seguro principal lleva póliza y hoy lo cubre una, con margen (o con una
 *                 renovación que empalma).
 * por_vencer .... cubierta hoy, pero se queda sin póliza en `DIAS_AVISO_RENOVACION` días o
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
  else if (dias !== null && dias <= DIAS_AVISO_RENOVACION) situacion = "por_vencer";
  else situacion = "al_dia";

  let motivoHueco: MotivoHueco | null = null;
  if (situacion === "hueco") motivoHueco = ultimaVencida ? "vencida" : proxima ? "aun_no_empieza" : "nunca";

  return {
    situacion, tipo, conPoliza, principales, otras, actual,
    cubiertoHasta: hasta, diasParaQuedarSinSeguro: dias, motivoHueco,
    diasDesdeQueVencio: motivoHueco === "vencida" && ultimaVencida ? diasEntre(ultimaVencida.vigente_hasta, hoy) : null,
    vencioEl: motivoHueco === "vencida" && ultimaVencida ? ultimaVencida.vigente_hasta : null,
    empiezaEl: motivoHueco === "vencida" || motivoHueco === "aun_no_empieza" ? proxima?.vigente_desde ?? null : null,
    resto: todas.filter((z) => z.poliza_id !== actual?.poliza_id),
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
  const extension = EXTENSION_POR_MIME[archivo.mime] ?? archivo.storage_path.split(".").pop() ?? "pdf";
  return `${archivo.tipo === "poliza" ? "Poliza" : "Convenio-de-pago"}-${seguro}-${numero}.${extension}`;
}

// ── El texto fijo: cómo usar un seguro ──────────────────────────────────────
// Hoy hay UNO: el de FOLA, que salió del resumen informativo de la póliza de Pacífico (páginas
// 2 a 5 del PDF que tiene Felipe). NO es la póliza: lo que vale es el PDF, y la pantalla lo
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

export interface GuiaDeUso {
  /** De quién son los teléfonos: «Pacífico». */
  aseguradora: string;
  pasos: readonly PasoDeUso[];
  /** Los teléfonos tal cual. No se les asigna un uso (cuál es cuál) porque la nota de donde salen no lo distingue. */
  telefonos: readonly string[];
  /** Lo que la póliza no cubre. */
  noCubre: readonly string[];
}

export const GUIAS_DE_USO: Readonly<Record<string, GuiaDeUso>> = {
  salud_practicantes: {
    aseguradora: "Pacífico",
    pasos: [
      {
        clave: "credito",
        titulo: "Atención al crédito",
        texto: "En la red de Pacífico, la atención es al crédito: basta con mostrar tu DNI.",
      },
      {
        clave: "hospitalizacion",
        titulo: "Si te van a hospitalizar",
        texto:
          "Hace falta una carta de garantía de Pacífico. El proveedor (la clínica) la solicita con 3 días útiles " +
          "de anticipación, salvo en una emergencia: avísale apenas sepas la fecha.",
      },
      {
        clave: "domicilio",
        titulo: "Médico a domicilio",
        texto: "Para un médico a domicilio, usa Pacífico Asiste.",
      },
      {
        clave: "reembolso",
        titulo: "Si pagaste tú una atención cubierta",
        texto: "Puedes pedir el reembolso dentro de 90 días, presentando los documentos originales.",
      },
    ],
    telefonos: ["(01) 415-1515", "(01) 513-5000"],
    noCubre: [
      "Gestación",
      "Odontología, salvo por accidente",
      "Salud mental",
      "Preexistencias: lo que ya tenías antes de entrar a la póliza",
    ],
  },
};

/**
 * Las guías de uso que le sirven HOY a esta persona: una por cada seguro del que tiene una póliza
 * que cubre hoy y del que hay guía. Una póliza vencida o que aún no empieza no se usa, así que
 * no se explica cómo usarla.
 */
export function guiasQueAplican(polizas: readonly PolizaMia[]): { clave: string; nombre: string; guia: GuiaDeUso }[] {
  const salida: { clave: string; nombre: string; guia: GuiaDeUso }[] = [];
  for (const z of polizas) {
    if (!z.cubre_hoy || salida.some((g) => g.clave === z.producto)) continue;
    const guia = GUIAS_DE_USO[z.producto];
    if (guia) salida.push({ clave: z.producto, nombre: z.producto_nombre, guia });
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

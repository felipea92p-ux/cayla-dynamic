// ============================================================================
// bandeja-sistema.ts — la tarjeta «Sistema» de la Bandeja, en palabras
// ----------------------------------------------------------------------------
// PROMETE. Convierte lo que devuelven la base y el despacho de correos —el
// resumen `fn_alertas_despacho_resumen` y la propuesta de
// `fn_alertas_resolver_fallidas` (0548)— en frases para quien no es técnica, y
// decide dos cosas que la pantalla no debe decidir sola: SI hay botón de
// «resolver» y QUÉ recordatorio lo acompaña. La pantalla solo pinta.
//
// ASUME. Nada del navegador ni de Supabase: son funciones puras, se prueban con
// vitest sin levantar nada. La clasificación de por qué falló un envío NO se
// repite aquí: vive en `lib/alertas/causa-del-fallo.ts` y la usa también la
// ruta que despacha (si dos lugares contestaran distinto, la Bandeja diría una
// cosa y el correo haría otra).
//
// POR QUÉ EXISTE. El 2026-10-25 la tarjeta decía «61 avisos por correo no van a
// salir solos» y debajo pegaba el JSON crudo de Resend, dos veces (el mismo 403
// con las llaves en otro orden) más una nota de «sin líder de equipo…». Felipe
// no podía hacer nada desde ahí: ni entender qué arreglar, ni sacar a esos 61
// avisos de la cola una vez arreglado.
//
// LA REGLA DE FONDO. Reenviar sin arreglar la causa del CANAL (remitente, clave
// o límite) no sirve: los avisos vuelven a fallar y cada intento perdido es un
// DÍA —el cron es diario—. Por eso el recordatorio cambia según haya o no causas
// del canal, y no es un texto fijo.
//
// MENOS RUIDO. La tarjeta se ve plegada: una línea (titular, motivo en pocas
// palabras, botón). Las causas completas con su «qué hacer» van en un
// desplegable; aquí vive lo que arma esa línea (`lineaDeCausas`).
// ============================================================================

import { agruparCausas, causaDeNota, type CausaDeFallo, type CausaInfo } from "../alertas/causa-del-fallo";
import type { CuentaBandeja } from "./bandeja-fuentes";
import { esFallaDeRed, mensajeDeError, type ErrorBase } from "./mensaje-error";

// ── El titular ──────────────────────────────────────────────────────────────

/** «61 avisos por correo no van a salir solos» / «1 aviso por correo no va a salir solo». */
export function titularDeLaTarjeta(n: number): string {
  const uno = n === 1;
  return `${n} aviso${uno ? "" : "s"} por correo no va${uno ? "" : "n"} a salir solo${uno ? "" : "s"}`;
}

// ── Las causas ──────────────────────────────────────────────────────────────

/**
 * Una causa por línea, sin repetir. Acepta un resumen viejo (sin
 * `motivos_definitivos`) o `null`: devuelve vacío y la tarjeta cae a su texto
 * de «sin nota del motivo», no se rompe.
 */
export function causasDeLaTarjeta(motivos: readonly string[] | null | undefined): CausaInfo[] {
  return agruparCausas(Array.isArray(motivos) ? motivos.filter((m): m is string => typeof m === "string") : []);
}

/**
 * Las notas que Dynamic NO supo explicar (causa «otra»), sin repetir, para
 * enseñarlas tal cual en un desplegable. Las que sí se reconocen ya tienen su
 * frase; repetir su JSON es justo el muro que se quitó.
 */
export function notasSinExplicar(motivos: readonly string[] | null | undefined, maximo = 3): string[] {
  const vistas = new Set<string>();
  const salida: string[] = [];
  for (const m of Array.isArray(motivos) ? motivos : []) {
    if (typeof m !== "string" || causaDeNota(m).causa !== "otra") continue;
    const texto = m.trim().slice(0, 300);
    if (!texto || vistas.has(texto)) continue;
    vistas.add(texto);
    salida.push(texto);
    if (salida.length >= maximo) break;
  }
  return salida;
}

// ── La línea plegada de la tarjeta ──────────────────────────────────────────

/**
 * La causa en pocas palabras, para la línea que SIEMPRE se ve. La explicación
 * completa y qué hacer (`etiqueta` y `que_hacer`) va en el desplegable. Es un
 * `Record` completo a propósito: una causa nueva en `causa-del-fallo.ts` no
 * compila hasta que alguien le escriba su versión corta aquí.
 */
const CAUSA_CORTA: Record<CausaDeFallo, string> = {
  remitente_sin_verificar: "dominio del remitente sin verificar",
  clave_invalida: "clave de envío rechazada",
  limite_de_envios: "límite de envíos de Resend",
  resend_caido: "Resend no respondió",
  configuracion_faltante: "envío sin configurar",
  sin_destinatario: "nadie con correo a quien avisar",
  rechazo_de_resend: "dirección rechazada por Resend",
  otra: "motivo que Dynamic no reconoce",
};

/**
 * Las causas con las del CANAL primero: son las que bloquean todo el envío, y
 * si la línea plegada solo alcanza a nombrar una, tiene que ser esa. Estable:
 * dentro de cada grupo se respeta el orden de aparición.
 */
export function causasPorPrioridad(causas: readonly CausaInfo[]): CausaInfo[] {
  return [...causas.filter((c) => c.del_canal), ...causas.filter((c) => !c.del_canal)];
}

/**
 * El motivo en una línea: «Motivo: dominio del remitente sin verificar.» con una
 * causa, «Motivo: … y 1 motivo más.» con varias. Sin causas: si hubo fallos, dice
 * que no se guardó el motivo (no calla); si no los hubo (solo atascadas o
 * caducadas), nada. Es la parte que reemplaza a la lista entera cuando la
 * tarjeta está plegada.
 */
export function lineaDeCausas(causas: readonly CausaInfo[], hayFallidas: boolean): string | null {
  const ordenadas = causasPorPrioridad(causas);
  if (ordenadas.length === 0) return hayFallidas ? "No se guardó el motivo." : null;
  const primera = CAUSA_CORTA[ordenadas[0].causa];
  const otras = ordenadas.length - 1;
  return otras === 0 ? `Motivo: ${primera}.` : `Motivo: ${primera} y ${otras} ${otras === 1 ? "motivo más" : "motivos más"}.`;
}

// ── La propuesta de la RPC ──────────────────────────────────────────────────

/** Lo que devuelve `fn_alertas_resolver_fallidas` (0548), ya limpio. */
export interface PropuestaResolucion {
  /** false = solo contó (p_ejecutar=false); true = ya escribió. */
  ejecutado: boolean;
  reencolar: {
    total: number;
    por_tipo: Record<string, number>;
    /**
     * De `total`, cuántos ya habían pasado la ventana de 7 días pero siguen
     * siendo ciertos (un contrato que aún vence, unas vacaciones que aún
     * vencen) y reciben otra semana. La forma vieja de la RPC no lo trae: 0.
     */
    ventana_renovada: number;
  };
  descartar: { total: number; por_motivo: Record<string, number> };
}

function conteo(v: unknown): number {
  const n = typeof v === "number" ? v : Number.NaN;
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0;
}

function mapaDeConteos(v: unknown): Record<string, number> {
  const salida: Record<string, number> = {};
  if (!v || typeof v !== "object" || Array.isArray(v)) return salida;
  for (const [k, n] of Object.entries(v as Record<string, unknown>)) {
    const c = conteo(n);
    if (c > 0) salida[k] = c;
  }
  return salida;
}

/**
 * Lee el JSON de la RPC con desconfianza: devuelve `null` si no tiene la forma
 * (otra versión de la función, una respuesta vacía) en vez de inventar ceros que
 * dirían «no hay nada que resolver» sobre un dato que no llegó. Un `total`
 * ausente se reconstruye del detalle; si ni eso hay, es 0. `ventana_renovada`
 * es opcional (la forma anterior a la que la 0548 le agregó) y nunca pasa del
 * total reencolado, que es de lo que es una parte.
 */
export function leerPropuesta(json: unknown): PropuestaResolucion | null {
  if (!json || typeof json !== "object" || Array.isArray(json)) return null;
  const o = json as Record<string, unknown>;
  const re = o.reencolar;
  const de = o.descartar;
  if (!re || typeof re !== "object" || !de || typeof de !== "object") return null;

  const porTipo = mapaDeConteos((re as Record<string, unknown>).por_tipo);
  const porMotivo = mapaDeConteos((de as Record<string, unknown>).por_motivo);
  const suma = (m: Record<string, number>) => Object.values(m).reduce((a, b) => a + b, 0);
  const totalRe = conteo((re as Record<string, unknown>).total) || suma(porTipo);
  const totalDe = conteo((de as Record<string, unknown>).total) || suma(porMotivo);

  return {
    ejecutado: o.ejecutado === true,
    reencolar: {
      total: totalRe,
      por_tipo: porTipo,
      ventana_renovada: Math.min(conteo((re as Record<string, unknown>).ventana_renovada), totalRe),
    },
    descartar: { total: totalDe, por_motivo: porMotivo },
  };
}

/** ¿Hay algo que hacer? Si no, la ventana lo dice en vez de ofrecer un botón que no hace nada. */
export function hayAlgoQueResolver(p: PropuestaResolucion): boolean {
  return p.reencolar.total > 0 || p.descartar.total > 0;
}

/**
 * Nombres de los tipos de aviso en palabras. Un tipo que aparezca mañana y no
 * esté acá se escribe con sus guiones bajos convertidos en espacios: nunca se
 * oculta ni se cae la ventana por un tipo nuevo.
 */
const TIPO_EN_PALABRAS: Record<string, string> = {
  auto_cierre: "jornadas que se cerraron solas",
  contrato_por_vencer: "contratos por vencer",
  vacaciones_por_vencer: "vacaciones por vencer",
};

/**
 * Por qué se da por cerrado un aviso, en palabras. Mismas claves que escribe la
 * 0548. Cada texto trae su propia preposición («por…», «porque…»): la función
 * que arma la frase no antepone nada, para que un motivo nuevo no salga con un
 * «porque porque».
 */
const MOTIVO_EN_PALABRAS: Record<string, string> = {
  fuera_de_ventana: "por llevar más de 7 días sin salir",
  ya_no_vigente:
    "porque la situación ya cambió: la jornada ya se revisó, o el contrato o las vacaciones ya cambiaron",
};

function sinGuiones(clave: string): string {
  return clave.replace(/_/g, " ").trim();
}

/** «12 de contratos por vencer, 3 de vacaciones por vencer». Vacío si no hay detalle. */
function detalleDeConteos(m: Record<string, number>, nombre: (clave: string) => string, conDe: boolean): string {
  return Object.entries(m)
    .sort((a, b) => b[1] - a[1])
    .map(([k, n]) => `${n}${conDe ? " de" : ""} ${nombre(k)}`)
    .join(", ");
}

/**
 * Lo que la ventana de confirmación dice siempre que se va a cerrar algo. El
 * aviso que se cierra puede seguir siendo cierto (un contrato que vence en cinco
 * días): se pierde el CORREO, no el hecho, y el generador no lo vuelve a crear
 * por ese camino. Tampoco hay botón para deshacerlo desde la pantalla.
 */
export const NOTA_DE_CIERRE =
  "Cerrar un aviso no borra el hecho: el contrato, las vacaciones o el día sin cerrar siguen en su pantalla; " +
  "solo se deja de mandar el correo. Esto no se puede deshacer desde aquí.";

export interface FrasesDeResolucion {
  /** «Se volverán a enviar 40 avisos que todavía sirven.» — null si no hay. */
  reencolar: string | null;
  /** Detalle por tipo, para una línea chica debajo. null si no hay. */
  reencolarDetalle: string | null;
  /** «12 de ellos llevaban más de 7 días y siguen siendo ciertos: se les da otra semana.» — null si no hay. */
  reencolarRenovadas: string | null;
  /** «Se darán por cerrados 21 avisos: ya no se van a mandar por correo.» — null si no hay. */
  descartar: string | null;
  /** Por qué se cierran, en palabras. null si no hay. */
  descartarDetalle: string | null;
  /** Lo que hay que saber antes de cerrar (no se deshace, el hecho sigue). null si no se cierra nada. */
  notaDeCierre: string | null;
  /** true = no hay nada que reintentar ni cerrar. */
  nada: boolean;
}

function avisos(n: number): string {
  return `${n} aviso${n === 1 ? "" : "s"}`;
}

/** La propuesta (todavía no ejecutada) en frases. */
export function frasesDeResolucion(p: PropuestaResolucion): FrasesDeResolucion {
  const re = p.reencolar.total;
  const de = p.descartar.total;
  const renovadas = p.reencolar.ventana_renovada;
  const detalleRe = detalleDeConteos(p.reencolar.por_tipo, (k) => TIPO_EN_PALABRAS[k] ?? sinGuiones(k), true);
  const detalleDe = detalleDeConteos(p.descartar.por_motivo, (k) => MOTIVO_EN_PALABRAS[k] ?? `por «${sinGuiones(k)}»`, false);
  return {
    reencolar: re > 0 ? `Se volverá${re === 1 ? "" : "n"} a enviar ${avisos(re)} que todavía ${re === 1 ? "sirve" : "sirven"}.` : null,
    reencolarDetalle: re > 0 && detalleRe ? detalleRe : null,
    reencolarRenovadas:
      re > 0 && renovadas > 0
        ? renovadas === 1
          ? "1 de ellos llevaba más de 7 días y sigue siendo cierto: se le da otra semana."
          : `${renovadas} de ellos llevaban más de 7 días y siguen siendo ciertos: se les da otra semana.`
        : null,
    descartar:
      de > 0
        ? `Se dará${de === 1 ? "" : "n"} por cerrado${de === 1 ? "" : "s"} ${avisos(de)}: ya no se ${de === 1 ? "va" : "van"} a mandar por correo.`
        : null,
    descartarDetalle: de > 0 && detalleDe ? detalleDe : null,
    notaDeCierre: de > 0 ? NOTA_DE_CIERRE : null,
    nada: re === 0 && de === 0,
  };
}

/** Lo que se avisa DESPUÉS de ejecutar, con las cifras que devolvió la base (no las de la vista previa). */
export function mensajeDeResultado(p: PropuestaResolucion): string {
  const re = p.reencolar.total;
  const de = p.descartar.total;
  // Ya se ejecutó y no hubo nada: la vista previa prometió N y, al confirmar,
  // otra persona de DO ya los había resuelto (la función es idempotente). No es
  // un error: es el mismo resultado visto dos veces, y tiene que sonar así.
  if (re === 0 && de === 0) return "Otra persona ya los resolvió; no había nada pendiente.";
  const partes: string[] = [];
  if (re > 0) partes.push(`${avisos(re)} ${re === 1 ? "saldrá" : "saldrán"} en el próximo despacho`);
  if (de > 0) partes.push(`${avisos(de)} se ${de === 1 ? "dio" : "dieron"} por ${de === 1 ? "cerrado" : "cerrados"}`);
  const frase = partes.join(" y ");
  return frase.charAt(0).toUpperCase() + frase.slice(1) + ".";
}

// ── El recordatorio: arreglar el canal ANTES ────────────────────────────────

export interface Recordatorio {
  /** advertencia = hay una avería del canal sin arreglar; informativo = lo demás. */
  tono: "advertencia" | "informativo";
  texto: string;
}

const PEDIR_AYUDA = "Si no puedes tocar Vercel o Resend, pídeselo a quien administra el sistema.";

function enMinuscula(t: string): string {
  return t.charAt(0).toLowerCase() + t.slice(1);
}

/**
 * El texto que acompaña al botón de confirmar. Cuatro casos, y por eso no es fijo:
 *   · hay causas del CANAL → se nombran, se dicen los pasos (la tarjeta queda
 *     tapada por el velo de la ventana, así que aquí no se puede remitir «a lo
 *     de arriba») y, si TAMBIÉN hay avisos sin a quién llegar, se dice aparte:
 *     arreglar el canal no los arregla (el caso real del 2026-10-25: un 403 de
 *     dominio más «sin líder de equipo con correo»);
 *   · hay causas, pero todas de la fila → no se sabe si el canal anda: se dice
 *     de qué es cada motivo y que reenviar solo sirve si se cargó el correo;
 *   · no se sabe la causa (resumen sin notas) → se pide revisar antes.
 * Ninguno promete cuántos intentos quedan: el despacho corta el lote ante una
 * avería del canal y esa cuenta ya no es de tres.
 */
export function recordatorioDelCanal(causas: readonly CausaInfo[]): Recordatorio {
  const delCanal = causas.filter((c) => c.del_canal);
  const delAviso = causas.filter((c) => !c.del_canal);
  if (delCanal.length > 0) {
    const averias = delCanal.map((c) => enMinuscula(c.etiqueta)).join("; ");
    const pasos = delCanal.map((c) => c.que_hacer).join(" ");
    const aparte =
      delAviso.length > 0
        ? " Además hay avisos que no tienen a quién llegar: arreglar el canal no los arregla, así que carga el correo en Equipo o fallarán igual."
        : "";
    return {
      tono: "advertencia",
      texto:
        `Antes de confirmar, arregla lo que impide enviar: ${averias}. ${pasos} ${PEDIR_AYUDA} ` +
        `Si no se arregla, estos avisos volverán a fallar.${aparte}`,
    };
  }
  if (causas.length > 0) {
    return {
      tono: "informativo",
      texto:
        "Los motivos registrados son de cada aviso, no del envío. Reenviar solo sirve si ya cargaste el correo " +
        "que faltaba en Equipo; si no, volverán a fallar.",
    };
  }
  return {
    tono: "advertencia",
    texto:
      "Dynamic no guardó el motivo de estos fallos. Antes de confirmar, revisa que la clave y el dominio de Resend estén bien; " +
      `si el problema sigue, los avisos volverán a fallar. ${PEDIR_AYUDA}`,
  };
}

// ── ¿Hay botón? ─────────────────────────────────────────────────────────────

/**
 * ¿Existe todavía la función en la base? PostgREST contesta PGRST202 cuando no
 * encuentra la función (aún no se pegó la 0548) y Postgres 42883 cuando no
 * existe con esos argumentos. En los dos casos el botón no se dibuja y la tarjeta
 * funciona igual — `main` se publica sola y la migración se pega a mano, así que
 * este desfase es normal y no un error.
 */
export function funcionNoExiste(error: { code?: string | null; message?: string | null } | null | undefined): boolean {
  if (!error) return false;
  if (error.code === "PGRST202" || error.code === "42883") return true;
  return /could not find the function/i.test(error.message ?? "");
}

/**
 * Lo que dijo la base la última vez que se le preguntó (con `p_ejecutar=false`,
 * que solo cuenta) si hay algo que resolver. La tarjeta lo guarda: el botón se
 * decide con LA RESPUESTA, no solo con que la función exista.
 */
export type SondeoDeLaFuncion =
  | { tipo: "pendiente" }
  | { tipo: "no_existe" }
  | { tipo: "error" }
  | { tipo: "ok"; propuesta: PropuestaResolucion };

/** Lo mínimo del resumen que decide si hay algo que resolver. */
interface ResumenParaBoton {
  fallidas_definitivas?: number | null;
  caducadas?: number | null;
}

/**
 * ¿Se dibuja «Revisar y resolver estos avisos»? Solo si la persona puede, el
 * resumen dice que hay avisos muertos o caducados (las «atascadas» no cuentan:
 * se reintentan solas) y el sondeo no lo contradice:
 *   · pendiente → no se dibuja hasta saber;
 *   · no existe la función (aún no se pegó la 0548) → no;
 *   · la base contestó que no hay nada que reenviar ni cerrar → no: sería un
 *     botón que abre una ventana que dice «nada»;
 *   · la base contestó que sí hay → sí;
 *   · el sondeo falló por otra cosa (red, sesión, un deadlock) → SÍ: no se sabe,
 *     y esconder la salida por un fallo pasajero es peor que ofrecerla; al abrir
 *     se vuelve a preguntar y, si sigue fallando, se dice y se puede reintentar.
 */
export function mostrarBotonResolver(args: {
  puede: boolean;
  sondeo: SondeoDeLaFuncion;
  resumen: ResumenParaBoton | null | undefined;
}): boolean {
  if (!args.puede) return false;
  const r = args.resumen;
  if (conteo(r?.fallidas_definitivas) + conteo(r?.caducadas) <= 0) return false;
  switch (args.sondeo.tipo) {
    case "ok": return hayAlgoQueResolver(args.sondeo.propuesta);
    case "error": return true;
    case "pendiente":
    case "no_existe": return false;
  }
}

// ── Cuando la llamada falla ─────────────────────────────────────────────────

/** Por qué no se pudo hablar con la función: la base contestó un error, la respuesta no tenía la forma, o ni llegó. */
export type FalloDeLaLlamada =
  | { origen: "base"; error: ErrorBase }
  | { origen: "forma" }
  | { origen: "excepcion" };

/**
 * El texto de la ventana cuando la llamada falló. NUNCA pega el mensaje crudo de
 * Postgres («deadlock detected»): solo un `raise exception` nuestro (P0001) ya
 * viene escrito para leerse; lo demás se dice con palabras y con qué hacer.
 * `mensajeDeError` deja pasar un mensaje en inglés si no parece jerga de
 * constraint, así que aquí se le pasa solo el CÓDIGO: o lo traduce, o cae a su
 * frase genérica.
 */
export function textoDeErrorDeLaVentana(fallo: FalloDeLaLlamada, accion: string): string {
  if (fallo.origen === "excepcion") {
    return `No se pudo ${accion}: no hubo respuesta. Revisa tu conexión y reintenta.`;
  }
  if (fallo.origen === "forma") {
    return `No se pudo ${accion}: la respuesta de la base no tuvo la forma esperada. Reintenta; si sigue igual, avisa a Felipe.`;
  }
  const e = fallo.error;
  if (e.code === "P0001") return e.message;
  if (esFallaDeRed(e)) return `No se pudo ${accion}: parece que no hay conexión. Revisa tu internet y reintenta.`;
  // «violates» fuerza la rama genérica de mensajeDeError cuando el código no tiene traducción.
  return mensajeDeError({ message: "violates", code: e.code }, accion);
}

/** El aviso chico de la tarjeta cuando el sondeo falló y aun así se ofrece el botón. */
export const TEXTO_SONDEO_FALLIDO = "No se pudo comprobar si hay avisos que reenviar; puedes abrirlo igual.";

// ── El número del menú, explicado ───────────────────────────────────────────

/**
 * El `title` del bolito de la Bandeja en el menú, con de qué se compone: el 33
 * del menú y el 31 de la casilla «Todo» eran dos números sin relación aparente.
 * Recibe la misma `CuentaBandeja` que suma el total, así que no puede decir una
 * cosa y sumar otra.
 */
export function tituloDelContadorBandeja(c: CuentaBandeja): string {
  if (c.total <= 0) return "Nada pendiente en la Bandeja del equipo";
  const partes = [`${c.tareas} ${c.tareas === 1 ? "fila" : "filas"} de la lista`];
  if (c.sistema > 0) partes.push("1 por los correos de aviso que no salieron");
  if (c.normas > 0) partes.push("1 por las constancias de Normas por recoger");
  return `${c.total} en la Bandeja del equipo: ${partes.join(" + ")}`;
}

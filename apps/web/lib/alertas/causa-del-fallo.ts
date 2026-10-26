// «POR QUÉ FALLÓ UN ENVÍO» — la única definición.
//
// PROMETE: dada una nota de `alertas.nota_fallo` (o la respuesta cruda de
// Resend en el momento de fallar), devuelve la CAUSA, no el texto: dos notas
// con la misma causa dan el mismo resultado aunque Resend haya devuelto el JSON
// con otro orden de llaves, aunque el prefijo diga «intento 1» o «intento 3»,
// o aunque el cuerpo haya quedado cortado a 300 caracteres.
// ASUME: nada del navegador, de Supabase ni de Next. Es una función pura: la
// usan la ruta que despacha los correos (servidor) y la tarjeta de la Bandeja
// (navegador), y las dos tienen que contestar lo mismo.
//
// POR QUÉ EXISTE. El 2026-10-25 la Bandeja mostraba el MISMO 403 dos veces
// porque agrupaba por texto crudo, y la ruta contaba cualquier respuesta no-OK
// como culpa de la fila: 61 avisos gastaron sus tres intentos —tres DÍAS, el
// cron es diario— contra una avería que no era de ninguno de ellos (Resend:
// «The cayla.pe domain is not verified»). Distinguir si el problema es del
// CANAL (todas las filas fallarán igual) o de la FILA (solo esa dirección)
// es lo que permite no matar sesenta filas por una sola avería.
//
// SE NORMALIZA POR LA CAUSA, NO POR EL CÓDIGO HTTP. Un 403 de Resend puede ser
// «dominio no verificado», «solo puedes enviar a tu propio correo» (remitente
// de prueba) o una clave restringida; la acción de Felipe cambia en cada caso,
// y un 403 de otra índole no debe fundirse con ellos. Por eso se lee el mensaje
// del JSON (o, si el cuerpo quedó truncado y ya no parsea, el texto crudo).

export type CausaDeFallo =
  | "remitente_sin_verificar"
  | "clave_invalida"
  | "limite_de_envios"
  | "resend_caido"
  | "configuracion_faltante"
  | "sin_destinatario"
  | "rechazo_de_resend"
  | "otra";

export interface CausaInfo {
  causa: CausaDeFallo;
  /** Qué pasó, en una frase para alguien sin formación técnica. */
  etiqueta: string;
  /** Qué hacer, en una frase. */
  que_hacer: string;
  /**
   * true = la avería es del canal de envío (todas las filas fallarán igual
   * mientras no se arregle): no tiene sentido seguir gastando intentos de otras
   * filas. false = es de esa fila (esa dirección) o no se sabe.
   */
  del_canal: boolean;
  /**
   * Solo cuando la causa es `limite_de_envios`: de qué límite se trata, porque
   * cada uno se arregla distinto. Por segundo = transitorio (basta esperar un
   * segundo); cuota diaria = se renueva a medianoche UTC; cuota mensual = no se
   * renueva hasta el mes siguiente (hay que subir de plan).
   */
  limite?: LimiteDeEnvios;
}

export type LimiteDeEnvios = "por_segundo" | "cuota_diaria" | "cuota_mensual" | "desconocido";

/**
 * La nota que la ruta guarda cuando no hay a quién escribir. Vive acá y no en
 * la ruta para que quien la escribe y quien la reconoce no puedan separarse.
 * Desde la 0359 el vacío exige además que la propia persona no tenga correo, y
 * el texto lo dice (antes decía solo «sin líder de equipo… en esa sede»).
 */
export const NOTA_SIN_DESTINATARIO =
  "sin ningún destinatario con correo (ni líder de equipo activo de la sede ni la propia persona)";

/**
 * Cuando el fetch ni siquiera obtuvo respuesta (red caída, tiempo agotado). La
 * ruta arma la nota con este prefijo y `causaDeNota` lo reconoce.
 */
export const PREFIJO_SIN_RESPUESTA = "Resend no respondió";

/**
 * Lo que la ruta escribe en la nota cuando Resend contestó con un status pero el
 * cuerpo llegó vacío (o se colgó al leerlo). Sin esto, la Bandeja mostraría un
 * «Resend respondió 403: » mudo bajo «motivo que Dynamic no reconoce». Vive aquí
 * por la misma razón que las otras dos: quien lo escribe y quien lo lee.
 */
export const NOTA_CUERPO_NO_RECIBIDO = "(cuerpo no recibido)";

const INFO: Record<CausaDeFallo, Omit<CausaInfo, "causa">> = {
  remitente_sin_verificar: {
    etiqueta: "El dominio del remitente no está verificado en Resend",
    que_hacer:
      "Verifica el dominio en resend.com/domains y confirma que RESEND_FROM (en Vercel) usa exactamente ese dominio; hasta entonces ningún correo sale.",
    del_canal: true,
  },
  clave_invalida: {
    etiqueta: "Resend rechazó la clave de envío (RESEND_API_KEY)",
    que_hacer:
      "Crea una clave nueva con permiso de envío en resend.com/api-keys (la actual es inválida, está suspendida o no puede enviar) y reemplaza RESEND_API_KEY en Vercel; hasta entonces ningún correo sale.",
    del_canal: true,
  },
  limite_de_envios: {
    etiqueta: "Resend frenó los envíos por límite de uso",
    que_hacer:
      "Espera: lo que no salió hoy se reintenta en el siguiente despacho. Si se repite todos los días, revisa el plan de Resend en resend.com/settings/usage.",
    del_canal: true,
  },
  resend_caido: {
    etiqueta: "Resend no respondió (caído, lento o sin conexión)",
    que_hacer:
      "Normalmente se arregla solo: Dynamic lo reintenta en el siguiente despacho. Si pasan varios días, revisa resend.com/status; mientras tanto la Bandeja sigue mostrando el hecho.",
    del_canal: true,
  },
  configuracion_faltante: {
    etiqueta: "El envío de correos está sin configurar o mal configurado (RESEND_API_KEY o RESEND_FROM)",
    que_hacer:
      "Agrega o corrige la variable en Vercel (Settings, Environment Variables) y vuelve a desplegar; hasta entonces ningún correo sale.",
    del_canal: true,
  },
  sin_destinatario: {
    etiqueta: "No hay nadie con correo a quien avisar en esa sede",
    que_hacer:
      "Agrega el correo en Equipo: en la ficha del líder de equipo activo de esa sede o en la de la propia persona; mientras falte, los avisos de esa sede no tienen a quién llegar.",
    del_canal: false,
  },
  rechazo_de_resend: {
    etiqueta: "Resend rechazó esa dirección o ese mensaje",
    que_hacer:
      "Revisa en Equipo que el correo de quien debía recibirlo esté bien escrito; los demás avisos no se ven afectados.",
    del_canal: false,
  },
  otra: {
    etiqueta: "El envío falló por un motivo que Dynamic no reconoce",
    que_hacer:
      "Lee el texto del error en el detalle del aviso; si se repite, compártelo con quien mantiene el sistema.",
    del_canal: false,
  },
};

/**
 * `limite_de_envios` se arregla distinto según el límite, y un texto único
 * decía «espera» también para la cuota mensual, que no se renueva sola. La
 * etiqueta es la misma; cambia lo que hay que hacer.
 */
const QUE_HACER_LIMITE: Record<LimiteDeEnvios, string> = {
  por_segundo:
    "Es transitorio: Resend frenó el ritmo (demasiados envíos por segundo) y lo que no salió hoy sale en el siguiente despacho. Si se repite, otra aplicación comparte la clave: revisa el límite en resend.com/settings/usage.",
  cuota_diaria:
    "Se agotó la cuota diaria de envíos del plan de Resend: se renueva a medianoche UTC (19:00 en Lima) y lo pendiente sale en el siguiente despacho. Si se repite todos los días, sube de plan en resend.com/settings/billing.",
  cuota_mensual:
    "Se agotó la cuota mensual de envíos del plan de Resend: no se renueva hasta el mes siguiente. Sube de plan en resend.com/settings/billing; hasta entonces ningún correo sale.",
  desconocido:
    "Espera: lo que no salió hoy se reintenta en el siguiente despacho. Si se repite todos los días, revisa el plan de Resend en resend.com/settings/usage.",
};

function info(causa: CausaDeFallo, limite?: LimiteDeEnvios): CausaInfo {
  if (causa === "limite_de_envios") {
    const l = limite ?? "desconocido";
    return { causa, ...INFO[causa], que_hacer: QUE_HACER_LIMITE[l], limite: l };
  }
  return { causa, ...INFO[causa] };
}

/** Qué límite de Resend es, por lo que dice el cuerpo. Sin cuerpo (429 mudo) no se adivina. */
function limiteDe(h: string): LimiteDeEnvios {
  if (/monthly_quota|monthly[^"]{0,40}quota|monthly[^"]{0,40}limit/.test(h)) return "cuota_mensual";
  if (/daily_quota|daily[^"]{0,40}quota|daily[^"]{0,40}limit/.test(h)) return "cuota_diaria";
  if (/rate_limit_exceeded|per second|requests per second/.test(h)) return "por_segundo";
  return "desconocido";
}

/** Lo que se puede sacar de un cuerpo de error de Resend, sin importar el orden de llaves. */
function leerCuerpo(cuerpo: string): { name: string; message: string; crudo: string } {
  const crudo = (cuerpo ?? "").trim();
  try {
    const j: unknown = JSON.parse(crudo);
    if (j && typeof j === "object" && !Array.isArray(j)) {
      const o = j as Record<string, unknown>;
      const name = typeof o.name === "string" ? o.name : "";
      const message = typeof o.message === "string" ? o.message : "";
      if (name || message) return { name, message, crudo };
    }
  } catch {
    // Cuerpo truncado a 300 caracteres o texto plano: se reconoce por texto.
  }
  return { name: "", message: "", crudo };
}

/** El núcleo: status (si lo hay) + lo que dijo Resend → causa. Una sola tabla de reglas. */
function clasificar(status: number | null, cuerpo: string, red: boolean): { causa: CausaDeFallo; limite?: LimiteDeEnvios } {
  const { name, message, crudo } = leerCuerpo(cuerpo);
  // Si el JSON parseó, se lee SU mensaje (el orden de llaves no importa). Si no
  // parseó —truncado—, el texto crudo contiene el mensaje igual, a medias.
  const h = (message || name ? `${name} ${message}` : crudo).toLowerCase();

  if (red && status === null) return { causa: "resend_caido" };

  // 1 · Remitente. Mismo problema de fondo (el From no es de un dominio
  //     verificado) con dos redacciones de Resend: la acción es la misma.
  if (
    /domain is not verified|is not verified|verify (a|your) domain|add and verify|testing emails to your own|only send testing|own email address/.test(h)
  ) {
    return { causa: "remitente_sin_verificar" };
  }

  // 2 · Clave. Un 401 siempre es de autenticación; un 403 solo si el mensaje
  //     habla de la clave (un 403 sin ese mensaje NO se asume clave). Resend
  //     documenta varias averías de la clave, todas con la misma salida (otra
  //     clave): inválida (hoy 401 «API key is invalid»; antes 403
  //     invalid_api_key), ausente, restringida, suspendida (403
  //     suspended_api_key —p. ej. por una clave filtrada—), inactiva y sin
  //     permiso de envío. Si una de estas cae a «otra», el lote vuelve a
  //     gastar un intento por fila contra una avería que no es de ninguna.
  if (
    status === 401 ||
    /invalid_api_key|missing_api_key|restricted_api_key|suspended_api_key|invalid_permission|api key is invalid|api key is missing|api key is suspended|api key is not active|restricted to only|missing api key|missing required scopes/.test(h)
  ) {
    return { causa: "clave_invalida" };
  }

  // 3 · Límite de uso.
  if (status === 429 || /rate_limit|rate limit|quota|too many requests/.test(h)) {
    return { causa: "limite_de_envios", limite: limiteDe(h) };
  }

  // 4 · RESEND_FROM mal escrita: 422, pero NO es de una dirección destinataria,
  //     es del remitente que usa toda la tanda.
  if (/invalid_from_address|invalid `?from`? field/.test(h)) return { causa: "configuracion_faltante" };

  // 5 · Resend (o la red) caído.
  if ((status !== null && status >= 500) || /application_error|internal_server_error/.test(h)) {
    return { causa: "resend_caido" };
  }

  // 6 · La petición mal formada o una dirección que Resend no acepta: de la fila.
  if (status === 400 || status === 422) return { causa: "rechazo_de_resend" };

  return { causa: "otra" };
}

/**
 * Para la respuesta de Resend en el momento del envío (la ruta).
 * `red: true` = el fetch no obtuvo respuesta (excepción de red o tiempo agotado).
 */
export function causaDeRespuesta(r: { status: number | null; cuerpo: string; red?: boolean }): CausaInfo {
  const c = clasificar(r.status, r.cuerpo, r.red === true);
  return info(c.causa, c.limite);
}

/**
 * Para `alertas.nota_fallo`. Formas que existen en producción:
 *   «intento 3: Resend respondió 403: {"statusCode":403,"message":"The cayla.pe domain is not verified…","name":"validation_error"}»
 *   «intento 3: sin líder de equipo con correo activo en esa sede»   (0358-0359)
 *   «intento 1: sin encargada con correo activo en esa sede»          (antes del 2026-09-18)
 *   «intento 1: sin ningún destinatario con correo (…)»               (actual)
 *   «intento 2: RESEND_FROM no configurada — …» / «RESEND_API_KEY no configurada»
 *   «intento 1: Resend no respondió (…)»
 */
export function causaDeNota(nota: string): CausaInfo {
  const texto = (nota ?? "").replace(/^\s*intento\s+\d+\s*:\s*/i, "").trim();
  if (!texto) return info("otra");

  // Configuración: se mira antes que nada porque el texto de RESEND_FROM
  // menciona «dominio… verificado» y se confundiría con el remitente.
  if (/RESEND_(API_KEY|FROM)\s+no\s+configurada/i.test(texto)) return info("configuracion_faltante");

  if (/\bsin\s+(encargada|l[ií]der\s+de\s+equipo|ning[uú]n\s+destinatario)\b[^.]*\bcorreo/i.test(texto)) {
    return info("sin_destinatario");
  }

  if (new RegExp(`^${PREFIJO_SIN_RESPUESTA}`, "i").test(texto)) return info("resend_caido");

  const m = /^Resend\s+respondi[óo]\s+(\d{3})\s*:?\s*([\s\S]*)$/i.exec(texto);
  if (m) {
    const c = clasificar(Number(m[1]), m[2], false);
    return info(c.causa, c.limite);
  }

  // Texto que no sigue el formato de la ruta: se intenta por lo que dice.
  const c = clasificar(null, texto, false);
  return info(c.causa, c.limite);
}

/**
 * Causas ÚNICAS, en orden de aparición, SIN conteos. El resumen de la Bandeja
 * solo trae notas distintas (no filas por nota), así que contar sería inventar.
 */
export function agruparCausas(notas: readonly string[]): CausaInfo[] {
  const vistas = new Set<CausaDeFallo>();
  const salida: CausaInfo[] = [];
  for (const n of notas) {
    const c = causaDeNota(n);
    if (vistas.has(c.causa)) continue;
    vistas.add(c.causa);
    salida.push(c);
  }
  return salida;
}

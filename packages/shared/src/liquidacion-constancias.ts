// ============================================================================
// Qué se puede registrar sobre la diferencia real de una liquidación ya pagada
// ============================================================================
//
// QUÉ PROMETE
//   Los catálogos, las etiquetas y la regla de «qué dibujar» de esa decisión,
//   en UN solo sitio. La base (migración 0542) guarda los mismos catálogos en
//   CHECKs; `tests/liquidacion-constancias.test.ts` compara los dos lados, para
//   que no se separen sin que la prueba lo diga.
//
// QUÉ ASUME
//   Que el SENTIDO de la diferencia lo calcula el servidor (`ahora − pagado`:
//   positivo = hoy se le daría más a la persona; negativo = se le pagó de más)
//   y que aquí solo se lee. Nadie elige el sentido.
//
// LO QUE NO ESTÁ AQUÍ, A PROPÓSITO
//   «Ya se pagó por fuera»: pagar una diferencia ya tiene su camino, «Volver a
//   marcarla como pagada», que guarda la fecha real de pago. Y «compensada»:
//   choca con el numeral 29.6 del Reglamento (pagos en exceso: se comunica por
//   escrito y se acuerda la devolución; no se descuenta íntegro sin conformidad).
//
// NO TOCA EL NAVEGADOR NI SUPABASE: se prueba con vitest sin levantar nada.
// ============================================================================

export const SENTIDOS_DIFERENCIA = ["a_favor_persona", "a_favor_cayla"] as const;
export type SentidoDiferencia = (typeof SENTIDOS_DIFERENCIA)[number];

export const DECISIONES_CONSTANCIA = [
  "pagado_es_correcto",
  "no_se_reclama",
  "devolucion_acordada",
  "retirada",
] as const;
export type DecisionConstancia = (typeof DECISIONES_CONSTANCIA)[number];

export const APOYOS_CONSTANCIA = [
  "regla_cambio_despues",
  "dato_de_hoy_mal_cargado",
  "confirmado_por_contador_o_laboralista",
] as const;
export type ApoyoConstancia = (typeof APOYOS_CONSTANCIA)[number];

/** Igual que `char_length(btrim(motivo)) >= 10` de la base. */
export const MOTIVO_MINIMO_CONSTANCIA = 10;

export const ETIQUETA_DECISION: Record<DecisionConstancia, string> = {
  pagado_es_correcto: "Lo pagado era lo correcto cuando se pagó",
  no_se_reclama: "CAYLA decide no reclamar lo pagado de más",
  devolucion_acordada: "Se acordó con la persona devolver lo pagado de más",
  retirada: "Registro retirado",
};

export const ETIQUETA_APOYO: Record<ApoyoConstancia, string> = {
  regla_cambio_despues: "La regla o un parámetro del sistema cambió después del pago",
  dato_de_hoy_mal_cargado: "Un dato de hoy está mal cargado",
  confirmado_por_contador_o_laboralista: "Lo confirmó el contador o el laboralista",
};

/**
 * Qué decisiones se ofrecen según el sentido. Una diferencia a favor de la
 * persona NO se cierra con «no se reclama»: si se le debe, sigue abierta hasta
 * que se pague (por «Volver a marcarla como pagada»).
 */
export function decisionesPara(sentido: SentidoDiferencia): DecisionConstancia[] {
  return sentido === "a_favor_persona"
    ? ["pagado_es_correcto"]
    : ["no_se_reclama", "devolucion_acordada"];
}

/**
 * Lo mismo que exige la base, un poco más estricto a propósito: la base quita
 * espacios, tabuladores y saltos de línea antes de contar (`btrim(motivo, E' \t\r\n')`);
 * `trim()` de JavaScript quita además otros espacios de Unicode. Lo que esto
 * acepte, la base lo acepta.
 */
export function motivoDeConstanciaValido(texto: string): boolean {
  return texto.trim().length >= MOTIVO_MINIMO_CONSTANCIA;
}

/** Una fila de la diferencia, tal como la devuelve `fn_liquidacion_constancia_estado`. */
export interface FilaDiferenciaConstancia {
  concepto: string;
  pagado: number;
  ahora: number;
  diferencia: number;
  centavos: number;
}

/** Una constancia, tal como la arma `fn_liquidacion_constancia_estado`. */
export interface ConstanciaVista {
  id: string;
  decision: DecisionConstancia;
  apoyo: ApoyoConstancia | null;
  motivo: string;
  por: string;
  cuando: string;
  diferencias: FilaDiferenciaConstancia[];
}

/** La fila que devuelve `fn_liquidacion_constancia_estado` (0542). */
export interface EstadoRegistroDiferencia {
  version: number;
  hay_real: boolean;
  sentido: SentidoDiferencia | "mixto" | null;
  filas: FilaDiferenciaConstancia[];
  huella: string | null;
  puede_constatar: boolean;
  motivo_no: string | null;
  cabeza_id: string | null;
  vigente: ConstanciaVista | null;
  anterior: ConstanciaVista | null;
}

export type QueDibujarDeLaConstancia =
  /** Nada nuevo: la pantalla se comporta como antes de la 0542. */
  | "nada"
  /** Hay una constancia que cierra el aviso: se muestra quién, cuándo y por qué. */
  | "vigente"
  /** Hay diferencia real sin cerrar y se puede registrar qué pasó. */
  | "registrar"
  /** Hay diferencia real sin cerrar, pero hoy no se puede registrar (y se dice por qué). */
  | "no_se_puede";

/**
 * Qué dibuja la pantalla, con TRES estados y no dos: «no sé» no es «sin
 * constancia». Si la lectura falló (la 0542 todavía no está pegada, o la base
 * no contestó), o si la respuesta no trae la forma esperada, NO se dibuja nada
 * nuevo: dibujar un botón o un aviso sobre un dato que no se pudo leer sería
 * inventar un estado.
 */
export function queDibujarDeLaConstancia(
  carga: { error: string | null; fila: EstadoRegistroDiferencia | null },
  pagada: boolean,
): QueDibujarDeLaConstancia {
  if (!pagada) return "nada";
  if (carga.error) return "nada";
  const f = carga.fila;
  if (!f || f.hay_real !== true) return "nada";
  if (typeof f.puede_constatar !== "boolean" || !Array.isArray(f.filas)) return "nada";
  if (f.vigente) return "vigente";
  return f.puede_constatar ? "registrar" : "no_se_puede";
}

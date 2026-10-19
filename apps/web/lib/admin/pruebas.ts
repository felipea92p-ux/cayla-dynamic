/**
 * LA PRUEBA DE TRES DÍAS, EN LO QUE UNA PANTALLA NECESITA SABER (0536–0538).
 *
 * QUÉ PROMETE. Textos, orden y reglas de lo que dibujan los paneles de pruebas —la
 * Bandeja, Contratos, las etiquetas «Prueba · 2 de 3»—, en funciones puras que se
 * prueban sin levantar nada. Los DATOS los trae la base (`fn_pruebas_abiertas`,
 * `fn_pruebas_cierres_recientes`); aquí solo se decide cómo se dicen.
 *
 * QUÉ NO HACE. No decide quién puede cerrar una prueba: eso es `puedeDecidirPrueba`
 * (permisos.ts) para dibujar el botón y `fn_prueba_puede_actuar` (la base) para
 * dejar pasar la llamada. Tampoco calcula cuántos días lleva alguien: la base los
 * cuenta de las jornadas cerradas y los entrega ya contados. Esto solo los dice.
 *
 * POR QUÉ LOS TEXTOS DE CONSECUENCIA VIVEN AQUÍ Y NO EN EL BOTÓN. La confirmación
 * de «se retiró» es lo único entre una persona y una hora de trabajo sin pagar
 * (decisión de Felipe, 2026-10-19). Escrita dentro de un componente, nadie la
 * prueba; escrita aquí, `tests/pruebas.test.ts` vigila que SIEMPRE diga que no se
 * paga y cuántas horas son.
 */

import { EMPRESA } from "@cayla-dynamic/shared";

export type SituacionPrueba = "en_curso" | "cumplida" | "vencida";
export type ResultadoCierre = "no_apto" | "retirado";

/** Una fila de `fn_pruebas_abiertas` (0536). */
export interface FilaPrueba {
  prueba_id: string | null;
  persona_id: string;
  nombres: string;
  apellidos: string;
  sede_id: string | null;
  sede_codigo: string | null;
  inicio: string;
  dias_trabajados: number;
  dias_plazo: number;
  situacion: string;
  ultima_jornada: string | null;
  /** false = el trigger no pudo abrirle su fila; `fn_prueba_cerrar` se la crea al vuelo. */
  registrada: boolean;
  horas_marcadas: number;
  /** Ya tiene las dos caras del DNI guardadas. */
  dni_cargado: boolean;
}

/** Una fila de `fn_pruebas_cierres_recientes` (0538). */
export interface CierrePrueba {
  prueba_id: string;
  persona_id: string;
  nombres: string;
  apellidos: string;
  sede_codigo: string | null;
  resultado: string;
  motivo: string | null;
  decidida_por: string | null;
  cerrada_at: string;
  cerrada_fecha: string;
  dias_trabajados: number;
  horas_marcadas: number;
}

export const ETIQUETA_RESULTADO: Record<ResultadoCierre, string> = {
  no_apto: "No fue apto",
  retirado: "Se retiró",
};

/** Cuántas letras, como mínimo, tiene que tener un motivo: la misma regla que `fn_prueba_cerrar`. */
export const MOTIVO_MINIMO = 3;

export function nombreDe(x: { nombres: string; apellidos: string }): string {
  return `${x.nombres} ${x.apellidos}`.trim();
}

export function motivoValido(motivo: string): boolean {
  return motivo.trim().length >= MOTIVO_MINIMO;
}

/** «5,35 h» — con coma, como se escribe en el Perú; sin ceros que sobran. */
export function textoDeHoras(horas: number): string {
  const redondeado = Math.round(horas * 100) / 100;
  return `${String(redondeado).replace(".", ",")} h`;
}

/**
 * La situación de una fila. Se confía en la que dijo la base; solo si llega algo
 * que no se conoce se vuelve a derivar de los días — nunca se inventa una ausencia.
 */
export function situacionDe(f: Pick<FilaPrueba, "situacion" | "dias_trabajados" | "dias_plazo">): SituacionPrueba {
  if (f.situacion === "en_curso" || f.situacion === "cumplida" || f.situacion === "vencida") return f.situacion;
  if (f.dias_trabajados > f.dias_plazo) return "vencida";
  if (f.dias_trabajados === f.dias_plazo) return "cumplida";
  return "en_curso";
}

/**
 * La etiqueta corta que acompaña a una persona de prueba en todo el sistema:
 * «Prueba · 2 de 3». Pasada la prueba dice cuántos días lleva; el color sube de
 * informativo (en curso) a advertencia (toca decidir) y a alerta (se pasó el plazo).
 */
export function etiquetaDePrueba(
  f: Pick<FilaPrueba, "situacion" | "dias_trabajados" | "dias_plazo">,
): { texto: string; variante: "informativo" | "advertencia" | "alerta" } {
  const s = situacionDe(f);
  if (s === "en_curso") return { texto: `Prueba · ${f.dias_trabajados} de ${f.dias_plazo}`, variante: "informativo" };
  if (s === "cumplida") return { texto: `Prueba · ${f.dias_plazo} de ${f.dias_plazo}`, variante: "advertencia" };
  return { texto: `Prueba · ${f.dias_trabajados} días`, variante: "alerta" };
}

/** La frase completa de una fila, para el detalle: qué lleva y qué toca. */
export function textoDelDia(f: FilaPrueba): string {
  const s = situacionDe(f);
  if (s === "en_curso") {
    const faltan = f.dias_plazo - f.dias_trabajados;
    return `Lleva ${f.dias_trabajados} de ${f.dias_plazo} días trabajados · le ${faltan === 1 ? "falta 1 día" : `faltan ${faltan} días`}`;
  }
  if (s === "cumplida") return `Ya trabajó sus ${f.dias_plazo} días · toca decidir: contrato, o darlo de baja`;
  return `Lleva ${f.dias_trabajados} días trabajados, ${f.dias_trabajados - f.dias_plazo} más que el plazo · nadie decidió`;
}

/** ¿Ya puede hacérsele contrato? Solo cuando completó el plazo. */
export function puedeHacerContrato(f: Pick<FilaPrueba, "situacion" | "dias_trabajados" | "dias_plazo">): boolean {
  return situacionDe(f) !== "en_curso";
}

const RANGO_SITUACION: Record<SituacionPrueba, number> = { vencida: 0, cumplida: 1, en_curso: 2 };

/** Primero las vencidas, luego las que tocan decidir, luego las en curso; dentro de cada una, la más antigua. */
export function ordenarPruebas<T extends FilaPrueba>(filas: readonly T[]): T[] {
  return [...filas].sort((a, b) =>
    RANGO_SITUACION[situacionDe(a)] - RANGO_SITUACION[situacionDe(b)]
    || a.inicio.localeCompare(b.inicio)
    || nombreDe(a).localeCompare(nombreDe(b), "es"));
}

/**
 * Lo que la persona que decide tiene que leer ANTES de confirmar. «No apto» y «se
 * retiró» dan de baja con el mismo gesto; lo que cambia es el pago, y por eso lo
 * que cambia es lo primero que se dice.
 */
export function consecuenciaDelCierre(
  resultado: ResultadoCierre,
  f: Pick<FilaPrueba, "dias_trabajados" | "horas_marcadas">,
): { titulo: string; lineas: string[]; peligro: boolean } {
  const trabajado = `${f.dias_trabajados} ${f.dias_trabajados === 1 ? "día" : "días"} · ${textoDeHoras(f.horas_marcadas)}`;
  if (resultado === "retirado") {
    return {
      titulo: "Se retiró por su cuenta",
      peligro: true,
      lineas: [
        `NO se le paga lo trabajado: ${trabajado} marcados.`,
        "Se le da de baja con su último día trabajado.",
        "Queda registrado quién lo decidió y por qué.",
      ],
    };
  }
  return {
    titulo: "No fue apto",
    peligro: false,
    lineas: [
      `Se le paga lo trabajado: ${trabajado}. No cobra asignación familiar.`,
      "Se le da de baja con su último día trabajado.",
      "Queda registrado quién lo decidió y por qué.",
    ],
  };
}

/** El aviso que se muestra al terminar: dice qué quedó escrito, no solo «listo». */
export function mensajeDeCierre(resultado: ResultadoCierre, nombre: string): string {
  return resultado === "retirado"
    ? `${nombre}: se retiró. Quedó dado de baja y su trabajo no se paga.`
    : `${nombre}: no fue apto. Quedó dado de baja y se le pagará lo trabajado.`;
}

/**
 * Cómo se dice un cierre reciente en la Bandeja: «Se retiró · decidió Ana · 1 día,
 * 5,35 h sin pagar». Para «no apto» las horas SÍ se pagan y se dice así.
 */
export function resumenDeCierre(c: CierrePrueba): string {
  const dias = `${c.dias_trabajados} ${c.dias_trabajados === 1 ? "día" : "días"}, ${textoDeHoras(c.horas_marcadas)}`;
  const quien = c.decidida_por ? ` · decidió ${c.decidida_por}` : "";
  return c.resultado === "retirado"
    ? `Se retiró${quien} · ${dias} sin pagar`
    : `No fue apto${quien} · ${dias} a pagar`;
}

/**
 * El texto de la constancia de consentimiento (Ley N.° 29733) que declara quien
 * sube el DNI de otra persona. Va en tercera persona porque la base antepone
 * «Constancia declarada por <quién> al registrar la prueba, en presencia de la
 * persona:». Lo que se guarda es EXACTAMENTE lo que se mostró en la casilla.
 *
 * El plazo viene de la fila (`dias_plazo`), no se escribe aquí: si algún día
 * cambia de tres días, la constancia no queda diciendo otra cosa.
 */
export function textoConsentimientoDni(nombre: string, diasPlazo: number): string {
  return (
    `${nombre} entregó su Documento Nacional de Identidad (DNI) en persona y autorizó a ${EMPRESA.nombre} ` +
    `(RUC ${EMPRESA.ruc}) a tratarlo, junto con sus demás datos personales, con la finalidad de verificar su ` +
    `identidad durante su prueba de ${diasPlazo} días y, si continúa, dejar constancia de su contrato. Estos datos ` +
    `se incorporarán al banco de datos personales de ${EMPRESA.nombre}. Su entrega es necesaria para continuar ` +
    `el proceso. Puede ejercer sus derechos de acceso, rectificación, cancelación y oposición escribiendo a info@cayla.pe.`
  );
}

// ============================================================================
// leer-poliza.ts — entender el texto de una póliza para no volver a teclearla
// ============================================================================
// QUÉ PROMETE
//   Recibe el texto de las páginas de un PDF de póliza (lo que saca pdf.js) y devuelve, por cada
//   póliza que encuentra, lo que el formulario pide: número, vigencia, prima total con IGV, la
//   fecha en que vence el pago, quién es el asegurado y, con cada cosa, los AVISOS de lo que
//   conviene mirar. Y propone a qué persona del sistema corresponde un nombre del papel.
//   Funciones puras, sin pdf.js ni React: se prueban con vitest (`tests/leer-poliza.test.ts`).
//
// QUÉ NO HACE
//   No guarda nada ni decide nada: lo que lee es una PROPUESTA que DO revisa y puede corregir en
//   pantalla antes de registrar. No interpreta lo que no está: un dato que no aparece sale `null`,
//   nunca un valor por defecto; que la pantalla lo pida es cosa de ella.
//
// DE DÓNDE SALE CADA DATO (medido el 2026-10-17 sobre una póliza real de FOLA de Pacífico, 89 páginas)
//   El PDF trae la póliza varias veces, con formas distintas, y NO todas dicen lo mismo de las fechas:
//     · la portada ........... «Fecha de vigencia: 01/10/2026 - 01/01/2027»
//     · las condiciones part. . «VIGENCIA : 01/10/2026 AL 01/01/2027 92 DIAS A LAS 12 M»
//     · el aviso de cobranza y el convenio dicen «01/10/2026 - 31/12/2026»: el ÚLTIMO DÍA cubierto,
//       no el día en que deja de cubrir.
//   El sistema cuenta `vigente_hasta` EXCLUSIVO (la póliza cubre hasta las 12 M de ese día): le
//   corresponde el 01/01/2027, no el 31/12. Por eso aquí solo se leen las dos primeras formas y se
//   IGNORAN las otras dos: tomar el 31/12 dejaría a la persona «sin cubrir» el último día. Si el
//   papel dice «N DIAS», se comprueba que las fechas den N.
//   La prima total con IGV sale de «PRIMA COMERCIAL + INT. + I.G.V. 179.97» (o del «Monto total a
//   pagar» del convenio) y se comprueba contra comercial + intereses + IGV. La fecha de vencimiento
//   del pago, de la tabla del convenio, solo se toma si es UNA cuota: con pago fraccionado el
//   sistema no tiene dónde ponerlas y se deja en blanco con un aviso.
//
// SE ROMPE SI
//   Otra aseguradora imprime otra forma. No hay nada que arreglar «a ojo»: se agrega UNA forma más
//   con un PDF de muestra y su prueba. Mientras tanto, un PDF que no se entiende devuelve cero
//   pólizas y la pantalla dice «regístrala a mano»; no inventa.
// ============================================================================
import { sinTildes } from "../sin-tildes";
import { diasEntre } from "../bandeja-mia";

export interface PolizaLeida {
  /** El número tal como lo imprime el papel. */
  numero: string;
  /** Primer día cubierto (ISO), o null si no se encontró. */
  desde: string | null;
  /** El día en que DEJA de cubrir (ISO, EXCLUSIVO), o null si no se encontró. */
  hasta: string | null;
  /** Prima total con IGV, en soles. */
  prima: number | null;
  /** El día en que vence el pago, si es una sola cuota. */
  primaVenceEl: string | null;
  aseguradora: string | null;
  /** «Seguro de salud practicantes», como lo escribe el papel (solo para mostrar). */
  producto: string | null;
  asegurado: { nombre: string; documento: string } | null;
  /** El día en que la aseguradora la emitió (ISO). */
  emitidaEl: string | null;
  /** Lo que conviene mirar antes de registrarla: lo que no cuadra o no se encontró. */
  avisos: string[];
}

// ── Fechas y montos ─────────────────────────────────────────────────────────

const MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"];

function isoSiExiste(d: number, m: number, a: number): string | null {
  if (!Number.isInteger(d) || !Number.isInteger(m) || !Number.isInteger(a) || a < 1900 || a > 2200) return null;
  const f = new Date(Date.UTC(a, m - 1, d));
  if (f.getUTCFullYear() !== a || f.getUTCMonth() !== m - 1 || f.getUTCDate() !== d) return null;
  return f.toISOString().slice(0, 10);
}

/** «01/10/2026» → «2026-10-01». Una fecha que no existe (31/02) es null, no un día de marzo. */
export function fechaDeTexto(texto: string): string | null {
  const m = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(texto.trim());
  return m ? isoSiExiste(Number(m[1]), Number(m[2]), Number(m[3])) : null;
}

/** «14 de Octubre del 2026» → «2026-10-14». */
function fechaEnPalabras(dia: string, mes: string, anio: string): string | null {
  const i = MESES.indexOf(sinTildes(mes).toLowerCase());
  return i < 0 ? null : isoSiExiste(Number(dia), i + 1, Number(anio));
}

/**
 * «179.97», «1,179.97», «1.179,97» o «179,97» → 179.97. El ÚLTIMO separador es el decimal solo si le siguen
 * una o dos cifras; con tres es de miles («1,179» son mil ciento setenta y nueve). Nada que parezca un
 * monto → null.
 */
export function montoDeTexto(texto: string): number | null {
  const t = texto.trim().replace(/\s/g, "");
  if (!/^\d[\d.,]*$/.test(t)) return null;
  const m = /^(.*)[.,](\d{1,2})$/.exec(t);
  const entera = (m ? m[1] : t).replace(/[.,]/g, "");
  const n = Number(m ? `${entera}.${m[2]}` : entera);
  return Number.isFinite(n) ? n : null;
}

const centimos = (n: number) => Math.round(n * 100);

// ── Lo que se busca en el texto ─────────────────────────────────────────────

const F = String.raw`(\d{1,2}\/\d{1,2}\/\d{4})`;
const NUMERO = /P[óo]liza\s*(?:N[°ºo]\.?|No\.?|n[úu]mero)?\s*:?\s*(\d{5,15})\b/gi;
const VIGENCIA_CONDICIONES = new RegExp(String.raw`VIGENCIA\s*:\s*${F}\s+AL\s+${F}(?:\s+(\d{1,4})\s*D[IÍ]AS)?`, "i");
const VIGENCIA_PORTADA = new RegExp(String.raw`Fecha de vigencia\s*:\s*${F}\s*-\s*${F}`, "i");
const VIGENCIA_EN_PALABRAS = /desde el (\d{1,2}) de ([a-záéíóúñ]+) del? (\d{4}) hasta el (\d{1,2}) de ([a-záéíóúñ]+) del? (\d{4})/i;
const PRIMA_TOTAL = /PRIMA COMERCIAL\s*\+\s*INT\.?\s*\+\s*I\.?G\.?V\.?\s*([\d.,]+)/i;
const MONTO_TOTAL = /Monto total a pagar\s*:?\s*([\d.,]+)/i;
const PRIMA_COMERCIAL = /PRIMA COMERCIAL\s+([\d.,]+)/i;
const INTERESES = /INTERESES\s+([\d.,]+)/i;
// El IGV suelto, no el que va dentro de «PRIMA COMERCIAL + INT. + I.G.V. 179.97».
const IGV = /(?<!\+\s?)I\.G\.V\.\s+([\d.,]+)/i;
const CUOTA = new RegExp(String.raw`(\d+)\/(\d+)\s+${F}\s+\d+\s+([\d.,]+)`, "g");
const ASEGURADO = /\bAsegurado\s*:\s*([^\d:]+?)\s+(\d{6,12})\b/i;
const EMITIDA = /Emitid[oa](?: en [A-Za-záéíóúñ ]+,)? (?:el |a los )?(\d{1,2}) (?:de |d[ií]as del mes de )([a-záéíóúñ]+) del? (\d{4})/i;
const PRODUCTO = /(SEGURO DE [A-ZÁÉÍÓÚÑ ]{3,60}?)\s+P[óo]liza\s*(?:N[°ºo]\.?|No\.?)/;

/** Espacios repetidos a uno y sin espacios antes de un salto: pdf.js separa cada trozo de texto con un espacio. */
function limpiar(texto: string): string {
  return texto.replace(/\r/g, "").replace(/[ \t ]+/g, " ").replace(/ ?\n ?/g, "\n");
}

function aTitulo(texto: string): string {
  const t = texto.replace(/\s+/g, " ").trim().toLowerCase();
  return t.charAt(0).toUpperCase() + t.slice(1);
}

const bien = (n: number) => n.toFixed(2);

// ── Leer ────────────────────────────────────────────────────────────────────

/**
 * Las pólizas que hay en el texto de un PDF, en el orden en que aparecen. Una póliza se reconoce por su
 * número («Póliza N°: 24043267»); lo suyo se busca en las páginas que lo nombran. Una «póliza» de la que no
 * se pudo leer ninguna fecha no se devuelve: un número suelto en medio de las condiciones generales no es
 * una póliza.
 */
export function leerPolizas(paginas: readonly string[]): PolizaLeida[] {
  const limpias = paginas.map(limpiar);
  const numeros: string[] = [];
  for (const p of limpias) {
    for (const m of p.matchAll(NUMERO)) if (!numeros.includes(m[1])) numeros.push(m[1]);
  }

  const salida: PolizaLeida[] = [];
  for (const numero of numeros) {
    const texto = limpias.filter((p) => p.includes(numero)).join("\n");
    const leida = leerUna(numero, texto);
    if (leida.desde !== null || leida.hasta !== null) salida.push(leida);
  }
  return salida;
}

function leerUna(numero: string, texto: string): PolizaLeida {
  const avisos: string[] = [];

  // ── La vigencia: solo las formas que dicen el día en que DEJA de cubrir ──
  let desde: string | null = null;
  let hasta: string | null = null;
  let dias: number | null = null;
  const cond = VIGENCIA_CONDICIONES.exec(texto);
  const portada = VIGENCIA_PORTADA.exec(texto);
  const palabras = VIGENCIA_EN_PALABRAS.exec(texto);
  const deCond = cond ? [fechaDeTexto(cond[1]), fechaDeTexto(cond[2])] as const : null;
  const dePortada = portada ? [fechaDeTexto(portada[1]), fechaDeTexto(portada[2])] as const : null;
  const dePalabras = palabras
    ? [fechaEnPalabras(palabras[1], palabras[2], palabras[3]), fechaEnPalabras(palabras[4], palabras[5], palabras[6])] as const
    : null;
  const elegida = [deCond, dePortada, dePalabras].find((v) => v && v[0] && v[1]) ?? null;
  if (elegida) { desde = elegida[0]; hasta = elegida[1]; }
  if (cond?.[3]) dias = Number(cond[3]);

  if (!elegida) {
    avisos.push("No encontré la vigencia en el papel: escríbela tú.");
  } else {
    const otras = [deCond, dePortada, dePalabras].filter((v) => v && v[0] && v[1] && (v[0] !== desde || v[1] !== hasta));
    if (otras.length > 0) avisos.push("El papel dice dos vigencias distintas: revisa las fechas.");
    if (desde && hasta && hasta <= desde) avisos.push("La vigencia que leí termina antes de empezar: revisa las fechas.");
    else if (desde && hasta && dias !== null && diasEntre(desde, hasta) !== dias) {
      avisos.push(`El papel dice ${dias} días y las fechas que leí dan ${diasEntre(desde, hasta)}: revisa las fechas.`);
    }
  }

  // ── La prima total con IGV ──
  const deCondicionesPrima = PRIMA_TOTAL.exec(texto);
  const deConvenio = MONTO_TOTAL.exec(texto);
  const primaA = deCondicionesPrima ? montoDeTexto(deCondicionesPrima[1]) : null;
  const primaB = deConvenio ? montoDeTexto(deConvenio[1]) : null;
  const prima = primaA ?? primaB;
  if (prima === null) avisos.push("No encontré la prima total: escríbela tú.");
  else {
    if (primaA !== null && primaB !== null && centimos(primaA) !== centimos(primaB)) {
      avisos.push(`La prima dice ${bien(primaA)} en las condiciones y ${bien(primaB)} en el convenio de pago: revisa cuál es.`);
    }
    // Comercial + intereses + IGV tienen que dar el total (con dos céntimos de tolerancia por el redondeo).
    const comercial = PRIMA_COMERCIAL.exec(texto);
    const igv = IGV.exec(texto);
    const intereses = INTERESES.exec(texto);
    if (comercial && igv) {
      const suma = (montoDeTexto(comercial[1]) ?? NaN) + (intereses ? montoDeTexto(intereses[1]) ?? 0 : 0) + (montoDeTexto(igv[1]) ?? NaN);
      if (Number.isFinite(suma) && Math.abs(centimos(suma) - centimos(prima)) > 2) {
        avisos.push(`La prima comercial más el IGV da ${bien(suma)} y el total que leí es ${bien(prima)}: revisa el monto.`);
      }
    }
  }

  // ── El vencimiento del pago: solo si es una cuota ──
  let primaVenceEl: string | null = null;
  const cuotas = [...texto.matchAll(CUOTA)].filter((m) => Number(m[1]) >= 1 && Number(m[2]) >= 1 && Number(m[1]) <= Number(m[2]));
  if (cuotas.length > 0) {
    const enCuantas = Number(cuotas[0][2]);
    if (enCuantas === 1 && cuotas.length === 1) primaVenceEl = fechaDeTexto(cuotas[0][3]);
    else avisos.push(`El pago es en ${enCuantas} cuotas: dejé en blanco cuándo vence la prima, que el sistema guarda como una sola fecha.`);
  }

  // ── Quién, con qué aseguradora, de qué producto ──
  const a = ASEGURADO.exec(texto);
  const asegurado = a ? { nombre: a[1].replace(/\s+/g, " ").trim(), documento: a[2] } : null;
  if (!asegurado) avisos.push("No encontré a quién asegura: elige a la persona tú.");

  const em = EMITIDA.exec(texto);
  const producto = PRODUCTO.exec(texto);

  return {
    numero, desde, hasta, prima, primaVenceEl,
    aseguradora: /PAC[ÍI]FICO/i.test(texto) ? "Pacífico Seguros" : null,
    producto: producto ? aTitulo(producto[1]) : null,
    asegurado,
    emitidaEl: em ? fechaEnPalabras(em[1], em[2], em[3]) : null,
    avisos,
  };
}

// ── A quién corresponde ─────────────────────────────────────────────────────

const PARTICULAS = new Set(["de", "del", "la", "las", "los", "y", "san", "santa"]);

/** Las palabras que cuentan de un nombre: sin tildes (la ñ cuenta como n, como en el buscador), sin mayúsculas, sin «de la». */
export function palabrasDeUnNombre(nombre: string): string[] {
  return sinTildes(nombre).toLowerCase().split(/[^a-z]+/).filter((p) => p.length > 1 && !PARTICULAS.has(p));
}

/**
 * ¿Qué persona es «ESPINOZA SANTIAGO MARIA FERNANDA» —el papel escribe apellidos primero—? Compara las
 * palabras sin importar el orden con el coeficiente de Dice (2·comunes / (a + b)): dos nombres con las
 * mismas palabras dan 1; faltar una de cuatro, 0.86; un nombre de dos palabras contra uno de cuatro,
 * 0.67 y NO alcanza, para que «Ana Pérez» no se tome por «Ana María Pérez Díaz». Solo se propone si hay
 * UNA mejor: si dos personas empatan o casi, no se elige por nadie.
 */
export function emparejarPersona<T extends { id: string; nombre: string }>(
  nombreDelPapel: string,
  personas: readonly T[],
): { persona: T; puntaje: number } | null {
  const buscado = new Set(palabrasDeUnNombre(nombreDelPapel));
  if (buscado.size === 0) return null;
  const puntuadas = personas
    .map((persona) => {
      const suyas = new Set(palabrasDeUnNombre(persona.nombre));
      if (suyas.size === 0) return { persona, puntaje: 0 };
      let comunes = 0;
      for (const p of buscado) if (suyas.has(p)) comunes += 1;
      return { persona, puntaje: (2 * comunes) / (buscado.size + suyas.size) };
    })
    .sort((x, y) => y.puntaje - x.puntaje || x.persona.id.localeCompare(y.persona.id));
  const [mejor, segundo] = puntuadas;
  if (!mejor || mejor.puntaje < 0.8) return null;
  if (segundo && mejor.puntaje - segundo.puntaje < 0.1) return null;
  return mejor;
}

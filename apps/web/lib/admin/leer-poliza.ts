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
//     · el resumen informativo . «desde el 01 de Octubre del 2026 hasta el 01 de Enero del 2027»
//     · el aviso de cobranza y el convenio dicen «01/10/2026 - 31/12/2026»: el ÚLTIMO DÍA cubierto,
//       no el día en que deja de cubrir.
//   El sistema cuenta `vigente_hasta` EXCLUSIVO (la póliza cubre hasta las 12 M de ese día): le
//   corresponde el 01/01/2027, no el 31/12. Por eso:
//     · SOLO la forma de las condiciones particulares está PROBADA: lleva «A LAS 12 M», que dice que
//       esa fecha es el día en que deja de cubrir. Se exige la frase: sin ella la forma no cuenta.
//     · La portada y el resumen informativo no lo dicen (en español, «hasta el 31» suele incluir el
//       31). Se leen como respaldo SI NO HAY una forma probada, y con un aviso que dice de dónde salió
//       la fecha final y que la cotejen: nunca en silencio.
//     · El aviso de cobranza y el convenio se IGNORAN.
//     · Si el papel dice «N DIAS», se comprueba que las fechas den N; si dos formas dicen fechas
//       distintas, se avisa.
//   Cada póliza se busca SOLO en las páginas que nombran su número y ninguno otro. Una página que
//   nombra dos pólizas (una renovación que cita la anterior, un aviso que lista varias) no se usa para
//   ninguna: de lo contrario le prestaría su asegurado, su vigencia y su prima a la que no es. Un número
//   que solo aparece en páginas así no es una póliza de este PDF (es una cita) y no se devuelve.
//   Y solo se reconoce a Pacífico: de otra aseguradora no hay muestra, y lo leído se marca para revisar.
//   La prima total con IGV sale de «PRIMA COMERCIAL + INT. + I.G.V. 179.97» (o del «Monto total a
//   pagar» del convenio) y se comprueba contra comercial + intereses + IGV. La fecha de vencimiento
//   del pago, de la tabla del convenio, solo se toma si es UNA cuota: con pago fraccionado el
//   sistema no tiene dónde ponerlas y se deja en blanco con un aviso.
//
// SE ROMPE SI
//   Otra aseguradora imprime otra forma. No hay nada que arreglar «a ojo»: se agrega UNA forma más
//   con un PDF de muestra y su prueba. Mientras tanto, un PDF que no se entiende devuelve cero
//   pólizas y la pantalla dice «regístrala a mano»; no inventa. Un PDF a medio entender (otra
//   aseguradora que imprime algo parecido) sale CON AVISO, y la pantalla no deja lista una póliza con
//   avisos: DO la mira y la marca.
//
// QUÉ NO CUBRE
//   Un PDF escaneado con capa de texto (OCR) puede traer un dígito mal leído y nadie lo notaría: el
//   documento y la prima se cotejan en pantalla contra la ficha de la persona y el papel, y por eso
//   nada se registra sin que DO lo mire.
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

/** «14 de Octubre del 2026» → «2026-10-14». «Setiembre» es septiembre: así lo escribe medio Perú. */
function fechaEnPalabras(dia: string, mes: string, anio: string): string | null {
  const m = sinTildes(mes).toLowerCase();
  const i = MESES.indexOf(m === "setiembre" ? "septiembre" : m);
  return i < 0 ? null : isoSiExiste(Number(dia), i + 1, Number(anio));
}

/**
 * «179.97», «1,179.97», «1.179,97» o «179,97» → 179.97. El ÚLTIMO separador es el decimal solo si le siguen
 * una o dos cifras; con tres es de miles («1,179» son mil ciento setenta y nueve). Nada que parezca un
 * monto → null.
 */
export function montoDeTexto(texto: string): number | null {
  // Un punto o una coma al final es de la oración, no del monto: «179.97.» no son 17 997 soles.
  const t = texto.trim().replace(/\s/g, "").replace(/[.,]+$/, "");
  if (!/^\d[\d.,]*$/.test(t)) return null;
  const m = /^(.*)[.,](\d{1,2})$/.exec(t);
  const entera = (m ? m[1] : t).replace(/[.,]/g, "");
  const n = Number(m ? `${entera}.${m[2]}` : entera);
  return Number.isFinite(n) ? n : null;
}

const centimos = (n: number) => Math.round(n * 100);

// ── Lo que se busca en el texto ─────────────────────────────────────────────

const F = String.raw`(\d{1,2}\/\d{1,2}\/\d{4})`;
// Un monto: dígitos con separadores EN MEDIO. Sin separador final: «179.97.» es 179.97 y un punto de oración.
const MONTO = String.raw`(\d+(?:[.,]\d+)*)`;
// Sin dos corridas de espacios seguidas que se disputen los mismos caracteres: con miles de saltos de
// línea tras «Póliza», la forma anterior tardaba segundos (backtracking cúbico).
const NUMERO = /P[óo]liza(?:\s*(?:N[°ºo]\.?|No\.?|n[úu]mero))?[\s:]*(\d{5,15})\b/gi;
// «A LAS 12 M» es la prueba de que la fecha final es el día en que DEJA de cubrir: sin esa frase, esta forma no cuenta.
const VIGENCIA_CONDICIONES = new RegExp(String.raw`VIGENCIA\s*:\s*${F}\s+AL\s+${F}(?:\s+(\d{1,4})\s*D[IÍ]AS)?\s+A\s+LAS\s+12\b`, "i");
const VIGENCIA_PORTADA = new RegExp(String.raw`Fecha de vigencia\s*:\s*${F}\s*-\s*${F}`, "i");
const VIGENCIA_EN_PALABRAS = /desde el (\d{1,2}) de ([a-záéíóúñ]+) del? (\d{4}) hasta el (\d{1,2}) de ([a-záéíóúñ]+) del? (\d{4})/i;
const LINEA_DE_PRIMA_TOTAL = String.raw`PRIMA COMERCIAL\s*\+\s*INT\.?\s*\+\s*I\.?G\.?V\.?\s*${MONTO}`;
const PRIMA_TOTAL = new RegExp(LINEA_DE_PRIMA_TOTAL, "i");
const PRIMA_TOTAL_EN_TODO = new RegExp(LINEA_DE_PRIMA_TOTAL, "gi");
const MONTO_TOTAL = new RegExp(String.raw`Monto total a pagar\s*:?\s*${MONTO}`, "i");
const PRIMA_COMERCIAL = new RegExp(String.raw`PRIMA COMERCIAL\s+${MONTO}`, "i");
const INTERESES = new RegExp(String.raw`INTERESES\s+${MONTO}`, "i");
// El IGV suelto: se busca DESPUÉS de quitar la línea «PRIMA COMERCIAL + INT. + I.G.V. 179.97», donde también
// aparece. (Sin lookbehind: Safari anterior a 16.4 no entiende la sintaxis y no cargaría la pantalla entera.)
const IGV = new RegExp(String.raw`I\.G\.V\.\s+${MONTO}`, "i");
const CUOTA = new RegExp(String.raw`(\d+)\/(\d+)\s+${F}\s+\d+\s+${MONTO}`, "g");
// El nombre, de 1 a 120 letras y sin dígitos ni dos puntos, y luego el documento. Acotado: sin tope, miles de
// saltos de línea tras «Asegurado:» costaban segundos.
const ASEGURADO = /\bAsegurado\s*:\s*([^\d:\s](?:[^\d:]{0,118}[^\d:\s])?)\s+(\d{6,12})\b/i;
// Solo lo que de verdad dice Pacífico en su papel (la razón social del convenio y la carta de la portada), no
// cualquier mención de la palabra en una cláusula.
const PACIFICO = /PAC[ÍI]FICO\s+(?:COMPA[ÑN][ÍI]A\s+DE\s+SEGUROS|SEGUROS)|\ben\s+Pac[íi]fico\s+como\s+su\s+compa[ñn][íi]a/i;
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
 * número («Póliza N°: 24043267»); lo suyo se busca SOLO en las páginas que lo nombran y no nombran otro
 * número de póliza: una página que cita a dos (una renovación que menciona la anterior, un aviso que lista
 * varias) no se usa para ninguna, porque le prestaría datos a la que no es. Un número que solo aparece en
 * páginas así es una cita, no una póliza de este PDF. Y una «póliza» de la que no se pudo leer ninguna fecha
 * no se devuelve: un número suelto entre las condiciones generales tampoco es una póliza.
 */
export function leerPolizas(paginas: readonly string[]): PolizaLeida[] {
  const limpias = paginas.map(limpiar);
  const numerosDeCadaPagina = limpias.map((p) => [...new Set([...p.matchAll(NUMERO)].map((m) => m[1]))]);
  const numeros: string[] = [];
  for (const enLaPagina of numerosDeCadaPagina) {
    for (const n of enLaPagina) if (!numeros.includes(n)) numeros.push(n);
  }

  const salida: PolizaLeida[] = [];
  for (const numero of numeros) {
    // El número entero, no un pedazo de otro más largo.
    const entero = new RegExp(`(?:^|\\D)${numero}(?:\\D|$)`);
    const propias = limpias.filter((p, i) => entero.test(p) && numerosDeCadaPagina[i].every((n) => n === numero));
    // Sin páginas propias no hay fechas que leer, y sin fechas no se devuelve: así una cita no es una póliza.
    const leida = leerUna(numero, propias.join("\n"));
    if (leida.desde !== null || leida.hasta !== null) salida.push(leida);
  }
  avisarLasRepetidas(salida);
  return salida;
}

/**
 * Dos pólizas del mismo PDF con el mismo asegurado, las mismas fechas y la misma prima suelen ser la misma
 * leída dos veces (o una contaminada por la otra): las dos se marcan.
 */
function avisarLasRepetidas(lista: PolizaLeida[]): void {
  const aviso = "Otra póliza de este PDF tiene el mismo asegurado, las mismas fechas y la misma prima: revisa que no sea la misma leída dos veces.";
  const mismoAsegurado = (a: PolizaLeida, b: PolizaLeida) =>
    a.asegurado && b.asegurado ? a.asegurado.documento === b.asegurado.documento : a.asegurado === b.asegurado;
  for (let i = 0; i < lista.length; i++) {
    for (let j = i + 1; j < lista.length; j++) {
      const a = lista[i];
      const b = lista[j];
      if (a.desde !== null && a.desde === b.desde && a.hasta === b.hasta && a.prima === b.prima && mismoAsegurado(a, b)) {
        for (const p of [a, b]) if (!p.avisos.includes(aviso)) p.avisos.push(aviso);
      }
    }
  }
}

function leerUna(numero: string, texto: string): PolizaLeida {
  const avisos: string[] = [];

  // ── La vigencia: solo la forma con «A LAS 12 M» está probada; las otras son respaldo, con aviso ──
  let desde: string | null = null;
  let hasta: string | null = null;
  let dias: number | null = null;
  const cond = VIGENCIA_CONDICIONES.exec(texto);
  const portada = VIGENCIA_PORTADA.exec(texto);
  const palabras = VIGENCIA_EN_PALABRAS.exec(texto);
  type Par = readonly [string, string];
  const par = (a: string | null, b: string | null): Par | null => (a && b ? [a, b] : null);
  const deCond = cond ? par(fechaDeTexto(cond[1]), fechaDeTexto(cond[2])) : null;
  const dePortada = portada ? par(fechaDeTexto(portada[1]), fechaDeTexto(portada[2])) : null;
  const dePalabras = palabras
    ? par(fechaEnPalabras(palabras[1], palabras[2], palabras[3]), fechaEnPalabras(palabras[4], palabras[5], palabras[6]))
    : null;
  const elegida = deCond ?? dePortada ?? dePalabras;
  if (elegida) { desde = elegida[0]; hasta = elegida[1]; }
  if (deCond && cond?.[3]) dias = Number(cond[3]);

  if (!elegida) {
    avisos.push("No encontré la vigencia en el papel: escríbela tú.");
  } else {
    if (!deCond) {
      avisos.push(
        `La fecha final salió ${dePortada ? "de la portada" : "del resumen del seguro"}, que no dice «a las 12 M»: no sé si es el último día cubierto `
        + "o el día en que deja de cubrir, y el sistema cuenta el segundo. Cotéjala con el papel.",
      );
    }
    const otras = [deCond, dePortada, dePalabras].filter((v) => v && (v[0] !== desde || v[1] !== hasta));
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
    const igv = IGV.exec(texto.replace(PRIMA_TOTAL_EN_TODO, " "));
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
  const esPacifico = PACIFICO.test(texto);
  if (!esPacifico) {
    avisos.push("No reconocí la aseguradora: este lector solo está probado con pólizas de Pacífico. Revisa cada dato contra el papel.");
  }

  return {
    numero, desde, hasta, prima, primaVenceEl,
    aseguradora: esPacifico ? "Pacífico Seguros" : null,
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

/** El puntaje mínimo para proponer a alguien, y la ventaja mínima sobre la segunda. Ver `emparejarPersona`. */
export const UMBRAL_DE_NOMBRE = 0.85;
export const MARGEN_DE_NOMBRE = 0.1;

/** Cuántas veces aparece cada palabra: «GARCIA GARCIA» no es lo mismo que «García». */
function bolsaDeUnNombre(nombre: string): Map<string, number> {
  const bolsa = new Map<string, number>();
  for (const p of palabrasDeUnNombre(nombre)) bolsa.set(p, (bolsa.get(p) ?? 0) + 1);
  return bolsa;
}

const totalDeLaBolsa = (b: ReadonlyMap<string, number>) => [...b.values()].reduce((a, n) => a + n, 0);

/**
 * ¿Qué persona es «ESPINOZA SANTIAGO MARIA FERNANDA» —el papel escribe apellidos primero—? Compara las
 * palabras sin importar el orden con el coeficiente de Dice sobre BOLSAS (2·comunes / (a + b), contando las
 * repetidas: «Quispe Quispe Ana» no se confunde con «Ana Quispe Mamani»): dos nombres con las mismas
 * palabras dan 1; faltar una de cuatro, 0.86; faltar una de tres, 0.80. Se propone solo con 0.85 o más, así
 * que «Rosa Díaz» NO se toma por «Díaz Rosa María», y solo si hay UNA mejor, con 0.1 de ventaja: si dos
 * personas empatan o casi, no se elige por nadie. Es una propuesta, no una decisión: la ficha se coteja
 * además con el documento del papel (`importar-polizas.ts`).
 */
export function emparejarPersona<T extends { id: string; nombre: string }>(
  nombreDelPapel: string,
  personas: readonly T[],
): { persona: T; puntaje: number } | null {
  const buscado = bolsaDeUnNombre(nombreDelPapel);
  const totalBuscado = totalDeLaBolsa(buscado);
  if (totalBuscado === 0) return null;
  const puntuadas = personas
    .map((persona) => {
      const suyas = bolsaDeUnNombre(persona.nombre);
      const totalSuyas = totalDeLaBolsa(suyas);
      if (totalSuyas === 0) return { persona, puntaje: 0 };
      let comunes = 0;
      for (const [palabra, veces] of buscado) comunes += Math.min(veces, suyas.get(palabra) ?? 0);
      return { persona, puntaje: (2 * comunes) / (totalBuscado + totalSuyas) };
    })
    .sort((x, y) => y.puntaje - x.puntaje || x.persona.id.localeCompare(y.persona.id));
  const [mejor, segundo] = puntuadas;
  // 1e-9: 0.85 se calcula con decimales binarios y 17/20 no siempre llega a 0.85 justo.
  if (!mejor || mejor.puntaje + 1e-9 < UMBRAL_DE_NOMBRE) return null;
  if (segundo && mejor.puntaje - segundo.puntaje + 1e-9 < MARGEN_DE_NOMBRE) return null;
  return mejor;
}

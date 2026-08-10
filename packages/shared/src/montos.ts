// ============================================================================
// montos.ts — leer una cifra de soles que escribió una persona
// ============================================================================
// QUÉ PROMETE  ·  convertir el texto que alguien tecleó en un número de soles,
//                 o decir que no se puede — nunca devolver un número que no
//                 sea el que esa persona quiso decir.
// QUÉ ASUME    ·  que la cifra se escribe en la notación del Perú, que es la
//                 misma que imprime la app: `,` para los miles y `.` para los
//                 céntimos. `Intl.NumberFormat("es-PE").format(8500)` da
//                 exactamente «8,500».
// QUÉ NO HACE  ·  no decide si el monto es razonable, ni si es mayor que cero,
//                 ni lo compara con nada. Eso es de cada pantalla.
//
// ── POR QUÉ EXISTE ──────────────────────────────────────────────────────────
// La pantalla de Planilla leía el monto de «Ya le pagué aparte» así:
//
//     Number(montoTxt.replace(",", "."))
//
// `String.replace` con un string reemplaza SOLO la primera aparición, así que
// el separador de miles caía por el mismo camino que la coma decimal. Medido:
//
//     "8,500"    → 8.5        "1,130" → 1.13
//     "2,000"    → 2          "8,500.00" → NaN
//
// O sea: a alguien se le transfirieron S/8,500 por fuera, DO abre el diálogo y
// teclea 8,500 —tal como se lo acaba de imprimir la propia app— y queda
// registrado un descuento de S/8.50. La planilla vuelve a pagar los S/8,500
// completos. El único aviso decía «ya se le habían pagado S/ 8.50», tan
// parecido a lo esperado que se lee sin releerlo.
//
// Esto no es un dedazo de quien opera: la persona escribió la cifra CORRECTA
// en la notación de su país y el software guardó otra.
//
// ── POR QUÉ RECHAZA EN VEZ DE ADIVINAR ──────────────────────────────────────
// Un parser de dinero que ante la duda elige una interpretación se equivoca en
// silencio, que es el modo de fallo más caro de este sistema. Cuando el texto
// admite dos lecturas, esta función devuelve `ok: false` con una frase que dice
// qué escribir. Un rechazo se ve; un 8.50 donde iban 8,500 no.
//
// ── LA REGLA QUE HACE QUE NO HAYA AMBIGÜEDAD ────────────────────────────────
// Los dígitos que siguen a la coma la desambiguan solos:
//
//     · exactamente 3  →  es separador de MILES   («8,500» son ocho mil quinientos)
//     · 1 o 2          →  es separador DECIMAL    («850,50» son ochocientos cincuenta con cincuenta)
//
// Las dos formas no se solapan nunca, así que no hace falta preguntar. Se
// aceptan las dos porque las dos se escriben de verdad: la primera es la que
// imprime la app, la segunda es la que sale de teclear rápido.
//
// El punto NO recibe el mismo trato. «8.500» se rechaza a propósito: en la
// notación peruana serían ocho soles con cincuenta, y en la europea ocho mil
// quinientos. Ahí sí hay dos lecturas y ninguna pista para elegir, así que se
// pregunta en vez de suponer.
// ============================================================================

/** Lo que devuelve `parsearMontoSoles`: o el número, o el motivo por el que no. */
export type MontoLeido =
  | { ok: true; monto: number }
  | { ok: false; motivo: string };

/** Miles con coma y céntimos con punto: «8,500» · «8,500.00» · «1130» · «1130.50» */
const MILES_Y_CENTIMOS = /^\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?$/;

/** Sin separador de miles: «1130» · «1130.5» · «1130.50» */
const LLANO = /^\d+(?:\.\d{1,2})?$/;

/** La coma usada como decimal, que es lo que ya funcionaba: «850,50» · «850,5» */
const COMA_DECIMAL = /^\d+,\d{1,2}$/;

/**
 * Lee una cifra de soles escrita por una persona.
 *
 * Acepta el símbolo de moneda y los espacios que trae un texto copiado de la
 * pantalla —incluido el espacio duro que mete `Intl.NumberFormat`—, porque
 * quien copia «S/ 8,500.00» no está cometiendo ningún error.
 *
 * No comprueba el signo ni el rango: devuelve el número tal como se escribió.
 * Un monto negativo se rechaza acá solo porque el `-` no forma parte de ninguna
 * de las tres formas aceptadas, y el mensaje lo dice.
 */
export function parsearMontoSoles(texto: string | null | undefined): MontoLeido {
  if (texto === null || texto === undefined) {
    return { ok: false, motivo: "Escribe el monto." };
  }

  // El espacio duro ( ) y el fino ( ) los mete Intl al formatear, así
  // que llegan pegados a cualquier cifra copiada de la propia app.
  const limpio = texto
    .replace(/[\s  ]/g, "")
    .replace(/^S\/\.?/i, "")
    .trim();

  if (limpio === "") {
    return { ok: false, motivo: "Escribe el monto." };
  }

  if (/^[+-]/.test(limpio)) {
    return {
      ok: false,
      motivo: "El monto va sin signo: escribe la cifra sola, por ejemplo 8500 o 8,500.00.",
    };
  }

  if (COMA_DECIMAL.test(limpio)) {
    return { ok: true, monto: Number(limpio.replace(",", ".")) };
  }

  if (MILES_Y_CENTIMOS.test(limpio) || LLANO.test(limpio)) {
    return { ok: true, monto: Number(limpio.replace(/,/g, "")) };
  }

  // A partir de acá no se adivina. Cada mensaje dice qué escribir, porque un
  // «monto inválido» a secas deja a quien opera probando formas al azar sobre
  // un campo que mueve dinero.
  if (/^\d+\.\d{3,}$/.test(limpio)) {
    const [entero, dec] = limpio.split(".");
    return {
      ok: false,
      motivo:
        `«${texto.trim()}» se puede leer de dos maneras y no quiero suponer: ` +
        `¿son ${entero} soles con ${dec.slice(0, 2)}, o ${entero}${dec} soles? ` +
        `Escríbelo como ${entero}.${dec.slice(0, 2)} o como ${entero}${dec}.`,
    };
  }

  if (/[^\d.,]/.test(limpio)) {
    return {
      ok: false,
      motivo: "El monto solo lleva números, comas de miles y un punto para los céntimos — por ejemplo 8,500.00.",
    };
  }

  return {
    ok: false,
    motivo:
      `No entiendo «${texto.trim()}» como una cifra de soles. ` +
      `Escríbela con la coma en los miles y el punto en los céntimos: 8,500.00, o simplemente 8500.`,
  };
}

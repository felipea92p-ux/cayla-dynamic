// cx junta clases condicionales en una sola cadena, y desde acá además hace
// una fusión mínima: cuando dos utilidades de la MISMA familia (mismo eje de
// relleno, mismo radio, mismo color de fondo o de texto) y la MISMA cadena de
// variantes (ambas en reposo, o ambas "hover:", o ambas "even:"...) terminan
// en la lista, deja solo la última.
//
// Hace falta porque en CSS el atributo class no decide nada por sí solo:
// decide la especificidad y, a igualdad de especificidad, el orden en que
// Tailwind generó la hoja — que no tiene por qué coincidir con el orden en
// que se escribieron las clases acá. Sin esto, un className="px-2" sobre un
// <Boton tamano="md"> (que ya trae "px-4") puede no achicarlo: los dos son
// utilidades sueltas de la misma especificidad, y gana la que Tailwind haya
// puesto después en su propia hoja — por azar, desde el punto de vista de
// quien escribe el className.
//
// Deliberadamente acotado a los cuatro grupos donde el problema es real y se
// midió (relleno, radio, fondo de color, texto de color) — cualquier otra
// clase se deja intacta, igual que antes de este cambio:
//
//  - Relleno: se compara por el eje exacto (p/px/py/pt/pr/pb/pl/ps/pe), nunca
//    por "relleno" en general. CampoSelect combina a propósito "px-3 py-2
//    pr-8" en la misma cadena (relleno base + hueco para la flecha del
//    <select>) — si esto colapsara todo relleno a un solo grupo, "pr-8" se
//    comería a "px-3" y el <select> se quedaría sin relleno izquierdo. Esos
//    tres ejes no compiten entre sí; Tailwind ya garantiza que lo específico
//    (pr-8) cae después de lo general (px-3) en su propia hoja.
//  - Radio: mismo criterio con los lados ("rounded-t-*" no compite con
//    "rounded-*" a secas), aunque hoy este código base no mezcla las dos
//    formas en un mismo cx(); es la misma razón que el relleno, dejada lista
//    para cuando alguna de las 49 pantallas que van a consumir esto sí lo
//    necesite.
//  - Fondo y texto: SOLO contra los once --color-* de globals.css
//    (crema/papel/tinta/rojo/rojo-profundo/sand/taupe/verde/ambar/hueso/
//    pizarra, con o sin "/opacidad"). Así "bg-hueso" no se cruza con
//    "bg-[right_0.6rem_center]" ni "bg-no-repeat" (el fondo de flecha de
//    CampoSelect: misma familia de prefijo, otra propiedad CSS por completo)
//    y "text-taupe" no se cruza con "text-xs" (tamaño, no color).
//
//  - Margen y grosor de borde (2026-10-19): mismo criterio que el relleno,
//    por eje o por lado exacto. Se sumaron cuando Turnos le pasó
//    "mb-0 border-b-0" a <Pestanas> (que trae "mb-5 border-b") para meterla
//    en una fila con los controles: el borde se apagó por suerte y el margen
//    no — "mb-5" sale después que "mb-0" en la hoja —, y la raya de la
//    pestaña activa quedó flotando 20 px sobre la línea de la fila. "-mx-4"
//    cuenta como "mx" (el signo no cambia la propiedad) y "border-sand" no
//    es grosor: solo "border", "border-b", "border-b-0", "border-2"…
//
// Lo que esto NO resuelve, a propósito: si la base trae una variante
// estructural — el "even:bg-hueso/50" de la zebra en <Fila> (tabla.tsx) — y
// quien llama pasa un "bg-rojo/10" sin variante para resaltar una fila
// puntual, la zebra sigue ganando en las filas pares. No es un empate de
// orden: "even:bg-hueso/50" compila con una pseudoclase de más
// (":nth-child(even)"), así que tiene más especificidad que un "bg-rojo/10"
// suelto pase lo que pase con el orden de las clases — fusionar texto no
// cambia la especificidad de lo que ya se generó. Ese caso se resuelve en
// quien declara la variante (Fila), no en cx.

type ClaseCx = string | false | null | undefined;

const RAICES_RELLENO = new Set(["p", "px", "py", "pt", "pr", "pb", "pl", "ps", "pe"]);
const RAICES_MARGEN = new Set(["m", "mx", "my", "mt", "mr", "mb", "ml", "ms", "me"]);
// "border", "border-b", "border-b-0", "border-2": grosor. "border-sand" (color) no entra.
const RE_BORDE_GROSOR = /^border(?:-([trblxyse]))?(?:-\d+)?$/;
const LADOS_RADIO =new Set(["t", "r", "b", "l", "s", "e", "tl", "tr", "bl", "br", "ss", "se", "es", "ee"]);

// Los once --color-* de globals.css. El orden de la alternancia no importa:
// el "$" al final exige que no quede nada después del nombre salvo un
// "/opacidad" opcional, así que "rojo" nunca hace match parcial de
// "rojo-profundo".
const TOKENS_COLOR = "crema|papel|tinta|rojo-profundo|rojo|sand|taupe|verde|ambar|hueso|pizarra";
const RE_FONDO_COLOR = new RegExp(`^bg-(?:${TOKENS_COLOR})(?:/\\d{1,3})?$`);
const RE_TEXTO_COLOR = new RegExp(`^text-(?:${TOKENS_COLOR})(?:/\\d{1,3})?$`);

// A qué "familia" pertenece la parte base de una clase (ya sin su cadena de
// variantes) — o null si no es ninguno de los cuatro grupos que cx fusiona,
// en cuyo caso se deja pasar tal cual, como hacía cx antes de este cambio.
function familiaDe(base: string): string | null {
  const guionRaiz = base.indexOf("-");
  const raiz = guionRaiz === -1 ? base : base.slice(0, guionRaiz);
  if (RAICES_RELLENO.has(raiz)) return `relleno:${raiz}`;

  const sinSigno = base.startsWith("-") ? base.slice(1) : base;
  const guionMargen = sinSigno.indexOf("-");
  const raizMargen = guionMargen === -1 ? sinSigno : sinSigno.slice(0, guionMargen);
  if (RAICES_MARGEN.has(raizMargen) && guionMargen !== -1) return `margen:${raizMargen}`;

  const borde = RE_BORDE_GROSOR.exec(base);
  if (borde) return `borde-grosor:${borde[1] ?? "todos"}`;

  if (base === "rounded") return "radio:todos";
  if (base.startsWith("rounded-")) {
    const resto = base.slice("rounded-".length);
    const guionLado = resto.indexOf("-");
    const lado = guionLado === -1 ? null : resto.slice(0, guionLado);
    return lado && LADOS_RADIO.has(lado) ? `radio:${lado}` : "radio:todos";
  }

  if (RE_FONDO_COLOR.test(base)) return "fondo-color";
  if (RE_TEXTO_COLOR.test(base)) return "texto-color";

  return null;
}

// Separa un token en su cadena de variantes ("hover:", "even:", "sm:hover:",
// …) y su clase base, por el ÚLTIMO ":" que no esté dentro de un "[...]" —
// para que una variante arbitraria futura del tipo
// "[&:not(:first-child)]:pt-4" no se corte a la mitad de sus propios
// paréntesis.
function separarVariante(token: string): { variante: string; base: string } {
  let profundidad = 0;
  for (let i = token.length - 1; i >= 0; i--) {
    const c = token[i];
    if (c === "]") profundidad++;
    else if (c === "[") profundidad--;
    else if (c === ":" && profundidad === 0) {
      return { variante: token.slice(0, i + 1), base: token.slice(i + 1) };
    }
  }
  return { variante: "", base: token };
}

export function cx(...clases: ClaseCx[]) {
  const tokens = clases
    .filter((c): c is string => Boolean(c))
    .flatMap((c) => c.split(/\s+/))
    .filter(Boolean);

  // Firma de cada token: cadena de variantes + familia. null = no participa
  // de la fusión, sobrevive siempre (es el comportamiento de antes).
  const firmas = tokens.map((token) => {
    const { variante, base } = separarVariante(token);
    const familia = familiaDe(base);
    return familia ? `${variante}${familia}` : null;
  });

  // Última posición de cada firma: esa es la que gana cuando hay dos o más
  // tokens con la misma firma.
  const ultimaPorFirma = new Map<string, number>();
  firmas.forEach((firma, i) => {
    if (firma) ultimaPorFirma.set(firma, i);
  });

  return tokens.filter((_, i) => firmas[i] === null || ultimaPorFirma.get(firmas[i] as string) === i).join(" ");
}

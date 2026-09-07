/**
 * Genera la imagen de una firma a partir de un nombre escrito, en vez de
 * escanear una firma manuscrita. Sirve para que cualquier colaboradora pueda
 * tener una firma que estampar en su propio contrato sin necesitar cámara ni
 * escáner — algo que `firmas_escaneadas` no cubría porque nació solo para
 * quien firma documentos EN NOMBRE DE LA EMPRESA (ver 0065/0076/0393).
 *
 * El resultado es una data-url PNG en el MISMO formato que ya acepta
 * `fn_set_mi_firma` — a propósito, para poder guardarla tal cual con
 * `supabase.rpc("fn_set_mi_firma", { p_dataurl })` sin ninguna conversión
 * intermedia.
 */

// Mismo ancho al que la pantalla de contratos ya reescala una firma escaneada
// (comentario de la 0076: "una firma real ronda los 20-80 KB" a este ancho).
const ANCHO_PX = 520;
const ALTO_PX = 200;
const TAMANO_FUENTE_INICIAL_PX = 72;
const TAMANO_FUENTE_MINIMO_PX = 24;
const MARGEN_HORIZONTAL_PX = 40;

/**
 * `fontFamily` tiene que ser un nombre YA CARGADO en el documento (el
 * `style.fontFamily` que devuelve `next/font/google`, no un nombre cualquiera
 * de Google Fonts): un canvas no dispara la descarga de una tipografía por sí
 * solo, y dibujar antes de que esté lista se ve con la tipografía por
 * defecto, en silencio, sin ningún error.
 */
export async function generarImagenFirma(nombre: string, fontFamily: string): Promise<string> {
  const texto = nombre.trim();
  if (!texto) throw new Error("Escribe un nombre para generar la firma.");

  const canvas = document.createElement("canvas");
  canvas.width = ANCHO_PX;
  canvas.height = ALTO_PX;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("Este navegador no puede generar la firma.");

  await document.fonts.load(`${TAMANO_FUENTE_INICIAL_PX}px ${fontFamily}`, texto);

  ctx.clearRect(0, 0, ANCHO_PX, ALTO_PX);
  // La firma se imprime siempre sobre el papel claro del contrato (la clase
  // `.hoja` fuerza esa paleta al imprimir — ver CLAUDE.md), nunca en modo
  // oscuro, así que va en tinta fija y no en el token `--color-tinta`.
  ctx.fillStyle = "#1a1a18";
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";

  let tamano = TAMANO_FUENTE_INICIAL_PX;
  ctx.font = `${tamano}px ${fontFamily}`;
  while (ctx.measureText(texto).width > ANCHO_PX - MARGEN_HORIZONTAL_PX && tamano > TAMANO_FUENTE_MINIMO_PX) {
    tamano -= 2;
    ctx.font = `${tamano}px ${fontFamily}`;
  }

  ctx.fillText(texto, ANCHO_PX / 2, ALTO_PX / 2);
  return canvas.toDataURL("image/png");
}

// ── Que la firma corresponda al nombre registrado ───────────────────────────
// Como cuando un bróker (p.ej. Interactive Brokers) exige que la firma de un
// contrato coincida con los datos ya registrados de esa persona: acá tampoco
// vale cualquier texto — tiene que reconocerse como EL NOMBRE de quien firma,
// no una cadena cualquiera ("jsdlaksj").
//
// Espejo EXACTO de `fn_firma_texto_coincide` (migración 0394) — la base vuelve
// a exigir esto mismo al guardar, así que las reglas de acá y las de allá
// tienen que quedar ALINEADAS a mano (no hay forma de compartir código entre
// SQL y TypeScript). Si esta función cambia, esa migración también.

const TILDES: Record<string, string> = { á: "a", é: "e", í: "i", ó: "o", ú: "u", ü: "u", ñ: "n" };

function normalizarTexto(s: string): string {
  return s
    .toLowerCase()
    .replace(/[áéíóúüñ]/g, (c) => TILDES[c] ?? c)
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * La firma sugerida: primer nombre completo, los demás nombres como inicial,
 * y el primer apellido completo — "Felipe M. Diaz" para "Felipe Manuel" /
 * "Diaz Lopez". Es solo un PUNTO DE PARTIDA: `validarFirmaCoincideConNombre`
 * acepta variantes más simples (sin el segundo nombre) y más completas (el
 * nombre entero, o el apellido materno en vez del paterno).
 */
export function sugerirFormatoFirma(nombres: string, apellidos: string): string {
  const [primerNombre, ...restoNombres] = nombres.trim().split(/\s+/).filter(Boolean);
  const [primerApellido] = apellidos.trim().split(/\s+/).filter(Boolean);
  if (!primerNombre || !primerApellido) return `${nombres} ${apellidos}`.trim();
  const iniciales = restoNombres.map((n) => `${n.charAt(0).toUpperCase()}.`).join(" ");
  return [primerNombre, iniciales, primerApellido].filter(Boolean).join(" ");
}

export interface ResultadoValidacionFirma {
  valida: boolean;
  motivo?: string;
}

/**
 * Reglas: 1) cada palabra escrita tiene que reconocerse como un nombre o
 * apellido real, completo o como su inicial (una letra, con o sin punto);
 * 2) el PRIMER nombre tiene que ir completo, su inicial no basta; 3) al menos
 * un apellido tiene que ir completo; 4) sin tildes ni mayúsculas.
 */
export function validarFirmaCoincideConNombre(
  texto: string,
  nombres: string,
  apellidos: string,
): ResultadoValidacionFirma {
  const tokensTexto = normalizarTexto(texto).split(" ").filter(Boolean);
  if (tokensTexto.length === 0) {
    return { valida: false, motivo: "Escribe tu nombre tal como firmas." };
  }

  const tokensNombres = normalizarTexto(nombres).split(" ").filter(Boolean);
  const tokensApellidos = normalizarTexto(apellidos).split(" ").filter(Boolean);
  const tokensReales = [...tokensNombres, ...tokensApellidos];

  let tieneApellido = false;
  for (const tokCrudo of tokensTexto) {
    const tok = tokCrudo.replace(/\.$/, "");
    if (!tok) continue;
    if (tok.length === 1) {
      if (!tokensReales.some((r) => r.startsWith(tok))) {
        return { valida: false, motivo: "Esa firma no corresponde a tu nombre registrado." };
      }
    } else {
      if (!tokensReales.includes(tok)) {
        return { valida: false, motivo: "Esa firma no corresponde a tu nombre registrado." };
      }
      if (tokensApellidos.includes(tok)) tieneApellido = true;
    }
  }

  if (!tokensTexto.includes(tokensNombres[0] ?? "")) {
    return { valida: false, motivo: "Tu primer nombre tiene que ir completo, no solo la inicial." };
  }
  if (!tieneApellido) {
    return { valida: false, motivo: "Tiene que llevar al menos un apellido completo." };
  }

  return { valida: true };
}

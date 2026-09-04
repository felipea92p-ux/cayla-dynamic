// ============================================================================
// clave.ts — Qué contraseña sirve para entrar al panel, en un solo sitio
// ============================================================================
// Está acá y no escrita a mano en cada pantalla por la misma razón que
// `permisos.ts` y `fecha-lima.ts`: es una regla que decide quién puede ver los
// sueldos de todo el equipo, y no puede tener dos versiones.
//
// LO QUE HABÍA ANTES: seis caracteres, sin ninguna otra condición. «111111»
// entraba. Y ése era el ÚNICO candado de las cuentas de admin, líder de DO y
// encargada de sede — las tres que ven la planilla entera, los sueldos por
// persona y el padrón con documentos. No hay segundo factor, no hay lista de
// dispositivos, no hay nada más. Seis dígitos iguales se prueban a mano.
//
// POR QUÉ 12 Y NO 8. Porque la longitud es lo único que de verdad encarece un
// intento por fuerza bruta, y porque estas claves se escriben en un teclado de
// computadora, no en el terminal de una sede. (El terminal marca SIN clave, y
// es a propósito — decisión de Felipe, jul-2026: eso no se toca acá.)
//
// POR QUÉ TRES FAMILIAS Y NO CUATRO. Se piden minúscula, mayúscula y dígito;
// NO se exigen símbolos. Exigir símbolos empuja a la gente a `Cayla2026!` —
// que cumple la regla y es de las primeras que prueba cualquiera— y hace la
// clave imposible de dictar por teléfono, que es exactamente lo que pasa
// cuando alguien pierde el acceso un domingo. Se prefiere longitud.
//
// ⚠️ ESTA REGLA VIVE EN DOS SITIOS Y TIENE QUE DECIR LO MISMO EN LOS DOS.
// El otro es la configuración de Supabase Auth:
//
//     minimum_password_length = 12
//     password_requirements   = "lower_upper_letters_digits"
//
// En local está en `supabase/config.toml`. En PRODUCCIÓN no lo lee nadie de ese
// archivo: se pone a mano en el panel de Supabase (Authentication → Sign In /
// Providers → Password). Mientras no se ponga allá, este archivo protege todos
// los caminos que pasan por nuestras pantallas, pero no protegería a alguien
// que llamara a la API de Supabase directamente.
// ============================================================================

export const LARGO_MINIMO_CLAVE = 12;

/** Palabras que no pueden aparecer dentro de la clave. En minúsculas. */
const PALABRAS_PROHIBIDAS = ["cayla", "dynamic", "clave", "password", "contrasena", "contraseña"];

/**
 * Qué se le pide a una clave, en las palabras con las que se le va a decir.
 * La pantalla las pinta como lista antes de que la persona escriba nada: una
 * regla que solo aparece cuando ya fallaste es una regla que enseña tarde.
 */
export const REQUISITOS_CLAVE = [
  `Al menos ${LARGO_MINIMO_CLAVE} caracteres`,
  "Una minúscula, una mayúscula y un número",
  "Que no sea una repetición ni una seguidilla (111111, abcdefgh…)",
  "Que no lleve tu correo ni el nombre de la empresa",
] as const;

/**
 * Todo lo que le falta a una clave para servir. Lista vacía = sirve.
 *
 * Devuelve TODOS los problemas y no el primero: quien está eligiendo una clave
 * necesita saber qué le falta de una vez, no descubrirlo de a uno por intento.
 *
 * `correo` es opcional y sirve para lo obvio: `felipe@…` con clave `Felipe2026x`
 * no es una clave, es el nombre de la puerta escrito en la llave.
 */
export function problemasDeClave(clave: string, correo?: string | null): string[] {
  const problemas: string[] = [];

  if (clave.length < LARGO_MINIMO_CLAVE) {
    problemas.push(`Tiene ${clave.length} caracteres y hacen falta ${LARGO_MINIMO_CLAVE}.`);
  }
  if (!/[a-z]/.test(clave)) problemas.push("Le falta al menos una letra minúscula.");
  if (!/[A-Z]/.test(clave)) problemas.push("Le falta al menos una letra mayúscula.");
  if (!/[0-9]/.test(clave)) problemas.push("Le falta al menos un número.");

  // Lo que el candado viejo dejaba pasar y da nombre a este arreglo: «111111».
  // Se mira sobre la clave entera, no sobre un tramo: `Aa1111111111` cumpliría
  // las tres familias y el largo, y sigue siendo un número repetido con adorno.
  if (/^(.)\1*$/.test(clave)) {
    problemas.push("Es el mismo carácter repetido.");
  } else if (tieneCorridaLarga(clave)) {
    problemas.push("Tiene una seguidilla o una repetición larga (ej. 123456, aaaaaa, abcdef).");
  }

  const enMinusculas = clave.toLowerCase();
  if (PALABRAS_PROHIBIDAS.some((w) => enMinusculas.includes(w))) {
    problemas.push("Lleva dentro una palabra demasiado esperable (el nombre de la empresa, «clave»…).");
  }

  const usuario = (correo ?? "").split("@")[0]?.toLowerCase() ?? "";
  if (usuario.length >= 4 && enMinusculas.includes(usuario)) {
    problemas.push("Lleva dentro tu propio correo.");
  }

  return problemas;
}

/** Atajo legible para los sitios que solo necesitan el sí o el no. */
export function claveSirve(clave: string, correo?: string | null): boolean {
  return problemasDeClave(clave, correo).length === 0;
}

/**
 * ¿Hay seis o más caracteres seguidos que suben de uno en uno, bajan de uno en
 * uno, o son el mismo? Seis y no cuatro para no castigar una clave por azar:
 * una contraseña generada al vuelo puede traer «2345» sin que eso la debilite.
 */
function tieneCorridaLarga(clave: string): boolean {
  const LARGO = 6;
  if (clave.length < LARGO) return false;
  let iguales = 1;
  let subiendo = 1;
  let bajando = 1;
  for (let i = 1; i < clave.length; i++) {
    const paso = clave.charCodeAt(i) - clave.charCodeAt(i - 1);
    iguales = paso === 0 ? iguales + 1 : 1;
    subiendo = paso === 1 ? subiendo + 1 : 1;
    bajando = paso === -1 ? bajando + 1 : 1;
    if (iguales >= LARGO || subiendo >= LARGO || bajando >= LARGO) return true;
  }
  return false;
}

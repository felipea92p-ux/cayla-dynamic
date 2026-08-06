// Traduce el error de la base a algo que una persona pueda leer y accionar.
//
// EL PROBLEMA. Hoy 43 lugares del panel hacen `texto: error.message` y pintan
// en pantalla lo que devuelva Postgres. A veces está bien y a veces sale esto:
//
//   new row for relation "personas" violates check constraint
//   "personas_cese_coherente"
//
// Quien lo lee no es ingeniera: es una encargada de tienda a la que ese texto
// no le dice qué hizo mal ni qué puede hacer ahora. Y peor, no distingue entre
// "te faltó un dato" y "el sistema está caído".
//
// LA DISTINCIÓN QUE IMPORTA. Las funciones SQL de este proyecto levantan sus
// errores con `raise exception '...'` y esos mensajes están escritos para
// leerse ("Solo un administrador o líder puede registrar un cese", "El último
// día trabajado no puede ser futuro"). Postgres los marca con el código
// `P0001`. Esos se muestran TAL CUAL: traducirlos sería empeorarlos.
//
// El resto —violaciones de constraint, permisos, fallas de conexión— son
// errores de sistema que se filtraron a la pantalla. Esos sí se traducen.

/** La forma mínima del error de Supabase (PostgrestError y sus primos). */
export interface ErrorBase {
  message: string;
  code?: string;
  details?: string | null;
  hint?: string | null;
}

const POR_CODIGO: Record<string, string> = {
  // Nuestros propios `raise exception`: ya vienen escritos para leerse.
  // (se maneja aparte, no acá)

  "23505": "Ya existe un registro igual. Revisa si no lo guardaste antes.",
  "23503": "No se puede hacer eso porque hay otra información que depende de este registro.",
  "23514": "Alguno de los datos no es válido. Revisa las fechas y los números antes de guardar.",
  "23502": "Falta un dato obligatorio.",
  "22P02": "Alguno de los datos tiene un formato que el sistema no entiende.",
  "42501": "No tienes permiso para hacer esto.",
  "42883": "Esta función todavía no está en la base de datos. Avisa a Felipe: falta aplicar una migración.",
  "42P01": "Falta una tabla en la base de datos. Avisa a Felipe: falta aplicar una migración.",
  PGRST301: "Tu sesión venció. Vuelve a entrar.",
  PGRST202: "El sistema no encontró esta función. Avisa a Felipe: falta aplicar una migración.",
  PGRST204: "El sistema no reconoce una columna nueva. Suele arreglarse solo en unos minutos; si no, avisa a Felipe.",
};

// Los constraints con nombre propio, traducidos uno por uno.
//
// POR QUÉ APARTE DEL CÓDIGO. Un `23514` genérico dice "revisa las fechas y los
// números", que es honesto pero inútil: no dice CUÁL fecha ni por qué. Cuando el
// constraint tiene nombre —y en este esquema lo tienen— ese nombre es exactamente
// la regla de negocio que se rompió, y se puede decir en una frase.
//
// Se busca el nombre dentro del mensaje de Postgres porque es donde viene:
//   new row for relation "personas" violates check constraint "personas_fin_contrato_coherente"
const POR_CONSTRAINT: Record<string, string> = {
  personas_fin_contrato_coherente:
    "El contrato no puede terminar antes del día en que la persona ingresó. Revisa la fecha de ingreso en su ficha.",
};

/**
 * Devuelve el texto que se le muestra a la persona.
 *
 * `accion` es lo que se estaba intentando ("guardar el turno", "registrar el
 * cese"). Se antepone para que el aviso diga qué falló, no solo por qué:
 * "No se pudo guardar el turno: no tienes permiso para hacer esto."
 */
export function mensajeDeError(error: ErrorBase | null | undefined, accion?: string): string {
  if (!error) return "";

  // P0001 = `raise exception` de nuestras funciones. Ya está en español y
  // escrito para leerse; anteponerle nada lo empeora.
  if (error.code === "P0001") return error.message;

  // Un constraint con nombre gana al código genérico: dice qué regla se rompió.
  const nombreConstraint = Object.keys(POR_CONSTRAINT).find(
    (n) => error.message.includes(n) || (error.details ?? "").includes(n),
  );
  if (nombreConstraint) {
    const texto = POR_CONSTRAINT[nombreConstraint];
    return accion ? `No se pudo ${accion}: ${texto}` : texto;
  }

  const traducido = error.code ? POR_CODIGO[error.code] : undefined;

  // Sin código conocido: si el mensaje parece nuestro (español, sin jerga de
  // Postgres), se muestra. Si no, se dice algo honesto en vez de inventar.
  const pareceNuestro =
    !traducido &&
    !/violates|constraint|relation|column|syntax error|does not exist|permission denied/i.test(error.message);

  const cuerpo = traducido ?? (pareceNuestro ? error.message : "El sistema no pudo completar la operación. Vuelve a intentarlo; si sigue igual, avisa a Felipe.");

  return accion ? `No se pudo ${accion}: ${cuerpo}` : cuerpo;
}

/**
 * Para el caso de red: Supabase no devuelve `code` cuando no hay conexión.
 * Se separa porque la respuesta correcta es distinta — no es un dato mal
 * puesto, es que no hay internet, y decirlo evita que alguien vuelva a
 * intentar lo mismo cinco veces.
 */
export function esFallaDeRed(error: ErrorBase | null | undefined): boolean {
  if (!error) return false;
  return !error.code && /fetch|network|failed to fetch|load failed/i.test(error.message);
}

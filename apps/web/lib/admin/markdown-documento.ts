/**
 * El markdown de un documento institucional, convertido a bloques.
 *
 * POR QUÉ EXISTE ESTE ARCHIVO Y NO ESTÁ DENTRO DE LA PANTALLA
 *
 * Porque es la parte que se puede equivocar. Pintar un `<strong>` no falla; lo
 * que falla es decidir dónde empieza una tabla, cuándo una lista numerada deja
 * de serlo, o si una fila de guiones es un separador o contenido. Dentro del
 * JSX eso no se puede probar sin montar un navegador —y este repositorio prueba
 * lógica pura con vitest, a propósito—, así que el análisis vive aquí, devuelve
 * datos, y la pantalla solo los dibuja.
 *
 * POR QUÉ NO UNA LIBRERÍA DE MARKDOWN
 *
 * Porque el texto que se pinta es el que vale como prueba de lo que el equipo
 * acusó. Un conversor completo entiende HTML incrustado, enlaces y entidades, y
 * cada una de esas es una forma de que lo que se muestra deje de ser lo que se
 * guardó. Aquí se reconocen seis bloques y tres marcas, y todo lo demás se
 * muestra tal cual: si algún día el documento trae algo que este archivo no
 * entiende, se verá el texto crudo, que es el lado seguro de equivocarse.
 *
 * POR QUÉ DEVUELVE DATOS Y NUNCA HTML
 *
 * El texto viene de la base. Si esto devolviera HTML para inyectar, quien
 * pudiera publicar un documento podría inyectar marcado en la pantalla de quien
 * lo acusa. Devolviendo datos, React lo escapa todo por su cuenta.
 */

/** Una marca de línea. `plano` es texto sin adorno. */
export interface Marca {
  estilo: "plano" | "negrita" | "cursiva" | "codigo";
  texto: string;
}

/**
 * `enCita` marca lo que venía detrás de un «>».
 *
 * No es un adorno: los once modelos de carta del Manual van citados enteros, y
 * dentro llevan tablas y listas. Sin esto, la tabla de tardanzas de un modelo se
 * imprimía con las barras a la vista —«| Fecha | Hora programada |»— justo en la
 * casilla donde hay que escribir los datos.
 */
export type Bloque =
  | { tipo: "espacio" }
  | { tipo: "regla" }
  | { tipo: "encabezado"; nivel: 1 | 2 | 3 | 4; marcas: Marca[] }
  | { tipo: "cita"; marcas: Marca[] }
  | { tipo: "parrafo"; marcas: Marca[] }
  | { tipo: "lista"; ordenada: boolean; items: Marca[][]; enCita: boolean }
  | { tipo: "tabla"; cabecera: Marca[][] | null; filas: Marca[][][]; enCita: boolean };

/**
 * Las tres marcas, en UN solo recorrido.
 *
 * En tres pasadas —una por marca— habría que reconstruir la cadena entre cada
 * una, y ahí es donde un asterisco que vive dentro de un `código` acaba
 * interpretándose como negrita. Con un recorrido, la primera marca que empieza
 * es la que manda y el resto de su tramo ya no se vuelve a mirar.
 */
export function marcasDe(texto: string): Marca[] {
  const marcas: Marca[] = [];
  // `código` va primero en la alternancia para que gane cuando dos marcas
  // empiezan en la misma posición.
  const re = /`([^`]+)`|\*\*([\s\S]+?)\*\*|(?<!\*)\*([^*\n]+)\*(?!\*)/g;
  let ultimo = 0;
  let m: RegExpExecArray | null;
  while ((m = re.exec(texto)) !== null) {
    if (m.index > ultimo) marcas.push({ estilo: "plano", texto: texto.slice(ultimo, m.index) });
    if (m[1] !== undefined) marcas.push({ estilo: "codigo", texto: m[1] });
    else if (m[2] !== undefined) marcas.push({ estilo: "negrita", texto: m[2] });
    else marcas.push({ estilo: "cursiva", texto: m[3] });
    ultimo = m.index + m[0].length;
  }
  if (ultimo < texto.length) marcas.push({ estilo: "plano", texto: texto.slice(ultimo) });
  return marcas;
}

/** Las celdas de una fila, sin las barras de los extremos. */
function celdas(linea: string): string[] {
  return linea.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map((c) => c.trim());
}

/**
 * La fila de guiones que separa la cabecera del cuerpo. Exige al menos un
 * guion: sin eso, `| a | b |` —una fila de contenido de dos celdas vacías de
 * puntuación— se tomaría por separador y la tabla perdería su primera fila.
 */
const SEPARADOR_TABLA = /^\|?[\s:|-]*-[\s:|-]*\|[\s:|-]*$/;

const VINETA = /^[-*+]\s+(.*)$/;
const NUMERADA = /^\d+[.)]\s+(.*)$/;

export function bloquesDe(texto: string): Bloque[] {
  const salida: Bloque[] = [];
  let lista: { ordenada: boolean; items: Marca[][]; enCita: boolean } | null = null;
  let tabla: { cabecera: Marca[][] | null; filas: Marca[][][]; enCita: boolean } | null = null;

  const cerrarLista = () => {
    if (lista) { salida.push({ tipo: "lista", ...lista }); lista = null; }
  };
  const cerrarTabla = () => {
    // Una tabla que solo tuvo cabecera y ninguna fila sigue siendo una tabla:
    // en el cargo de recepción, la cabecera ES la casilla que se rellena a mano.
    if (tabla) { salida.push({ tipo: "tabla", ...tabla }); tabla = null; }
  };

  for (const linea of texto.split("\n")) {
    // El «>» se quita ANTES de decidir qué es la línea. Así una tabla citada
    // sigue siendo una tabla, y no una cita con barras dentro.
    let t = linea.trim();
    let enCita = false;
    if (t.startsWith(">")) {
      enCita = true;
      t = t.replace(/^>\s?/, "").trim();
    }

    // ── Tabla ──────────────────────────────────────────────────────────────
    if (t.startsWith("|")) {
      cerrarLista();
      if (tabla && tabla.enCita !== enCita) cerrarTabla();
      if (SEPARADOR_TABLA.test(t)) {
        if (tabla && tabla.cabecera === null && tabla.filas.length === 1) {
          tabla.cabecera = tabla.filas.shift() ?? null;
        }
        continue;
      }
      if (!tabla) tabla = { cabecera: null, filas: [], enCita };
      tabla.filas.push(celdas(t).map(marcasDe));
      continue;
    }
    // Una línea de cita vacía —el «>» solo— separa párrafos DENTRO del modelo
    // de carta; no cierra la tabla que viene justo después.
    if (enCita && !t) { salida.push({ tipo: "espacio" }); continue; }
    cerrarTabla();

    // ── Lista ──────────────────────────────────────────────────────────────
    // Ojo con el orden: `---` es una regla horizontal, no una viñeta, y hay que
    // descartarlo ANTES de mirar si empieza por guion.
    if (t !== "---") {
      const v = VINETA.exec(t);
      const n = NUMERADA.exec(t);
      if (v || n) {
        const ordenada = n !== null;
        if (lista && (lista.ordenada !== ordenada || lista.enCita !== enCita)) cerrarLista();
        if (!lista) lista = { ordenada, items: [], enCita };
        lista.items.push(marcasDe(v ? v[1] : n![1]));
        continue;
      }
    }
    cerrarLista();

    // ── Lo demás ───────────────────────────────────────────────────────────
    if (!t) { salida.push({ tipo: "espacio" }); continue; }
    if (t === "---") { salida.push({ tipo: "regla" }); continue; }
    const enc = /^(#{1,4})\s+(.*)$/.exec(t);
    if (enc && !enCita) {
      salida.push({ tipo: "encabezado", nivel: enc[1].length as 1 | 2 | 3 | 4, marcas: marcasDe(enc[2]) });
      continue;
    }
    if (enCita) { salida.push({ tipo: "cita", marcas: marcasDe(t) }); continue; }
    salida.push({ tipo: "parrafo", marcas: marcasDe(t) });
  }

  cerrarLista();
  cerrarTabla();
  return salida;
}

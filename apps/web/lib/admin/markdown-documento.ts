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
  // `inicio` es el número con el que arranca una lista ordenada EN EL ORIGEN. Sin
  // él, el navegador renumera desde 1 y la pantalla publica un número de artículo
  // que el documento no dice.
  | { tipo: "lista"; ordenada: boolean; items: Marca[][]; enCita: boolean; inicio: number }
  | { tipo: "tabla"; cabecera: Marca[][] | null; filas: Marca[][][]; enCita: boolean };

/**
 * Las tres marcas, en UN solo recorrido.
 *
 * En tres pasadas —una por marca— habría que reconstruir la cadena entre cada
 * una, y ahí es donde un asterisco que vive dentro de un `código` acaba
 * interpretándose como negrita. Con un recorrido, la primera marca que empieza
 * es la que manda y el resto de su tramo ya no se vuelve a mirar.
 */
/**
 * El escape, resuelto también DENTRO de una negrita o una cursiva.
 *
 * Hace falta porque el contenido de una marca se emite de una pieza y no se
 * vuelve a recorrer —eso es lo que impide que un asterisco de dentro de un
 * `código` se interprete—. La resolución de designación escribe la casilla del
 * nombre en negrita, `**\_\_\_\_**`, así que sin esto la marca salía con las
 * barras a la vista justo en la línea donde se escribe a mano quién es la
 * Delegada contra el Hostigamiento Sexual.
 *
 * NO se aplica al `código`: ahí lo literal es literal, y ese es su trabajo.
 */
function desescapar(texto: string): string {
  return texto.replace(/\\([\\_*`])/g, "$1");
}

export function marcasDe(texto: string): Marca[] {
  const marcas: Marca[] = [];
  // El texto plano se acumula y se vuelca de golpe. Sin el acumulador, un
  // «Nombre: \_\_\_\_» devolvería una marca por cada guion escapado: una lista de
  // trozos donde antes había una cadena.
  let plano = "";
  const volcar = () => {
    if (plano) { marcas.push({ estilo: "plano", texto: plano }); plano = ""; }
  };
  // El ESCAPE va primero: `\*` tiene que dejar de ser un asterisco antes de que
  // la cursiva lo mire. Después `código`, para que gane cuando dos marcas
  // empiezan en la misma posición.
  //
  // POR QUÉ EL ESCAPE. Los documentos escapan el guion bajo —1221 veces entre el
  // Reglamento, la resolución de designación y el cargo de recepción— para pintar
  // las rayas donde se firma a mano. Sin esta rama se leía «Nombre: \_\_\_\_\_\_»
  // en la pantalla donde se deja la constancia, mientras el PDF que se entrega en
  // mano decía «Nombre: ______»: `scripts/reglamento-a-html.py` ya lo resolvía por
  // su lado. Pantalla y papel tienen que decir lo mismo.
  //
  // Solo `\_`, `\*`, `\\` y ``\` ``. NO `\|`: `celdas()` parte la línea por las
  // barras antes de que esto la vea, así que tratarla aquí escondería la barra
  // dejando la celda mal partida. NO `\[`: este analizador no reconoce enlaces y
  // los documentos usan `[ ]` como casilla literal.
  //
  // POR QUÉ LA CURSIVA EXIGE FLANQUEO. `\*([^*\n]+)\*` emparejaba dos asteriscos
  // literales cualesquiera de la misma línea y BORRABA los dos: «pago = salario *
  // horas / (6.5 * días)» —una fórmula que este negocio escribe— se pintaba «pago
  // = salario  horas / (6.5  días)», sin que ninguna prueba lo cazara. Exigiendo
  // que la marca no abra ni cierre sobre un espacio, un asterisco rodeado de
  // espacios ya no puede abrir nada.
  const re = /\\([\\_*`])|`([^`]+)`|\*\*([\s\S]+?)\*\*|(?<!\*)\*(?!\s)([^*\n]*[^\s*])\*(?!\*)/g;
  let ultimo = 0;
  let m: RegExpExecArray | null;
  while ((m = re.exec(texto)) !== null) {
    if (m.index > ultimo) plano += texto.slice(ultimo, m.index);
    if (m[1] !== undefined) plano += m[1];
    else if (m[2] !== undefined) { volcar(); marcas.push({ estilo: "codigo", texto: m[2] }); }
    else if (m[3] !== undefined) { volcar(); marcas.push({ estilo: "negrita", texto: desescapar(m[3]) }); }
    else { volcar(); marcas.push({ estilo: "cursiva", texto: desescapar(m[4]) }); }
    ultimo = m.index + m[0].length;
  }
  if (ultimo < texto.length) plano += texto.slice(ultimo);
  volcar();
  return marcas;
}

/**
 * ¿Esta línea deja una marca a medio abrir?
 *
 * Es la señal INEQUÍVOCA de que la línea siguiente continúa la misma frase: un
 * `**` que abre y no cierra solo puede cerrar más adelante. Es el caso que se vio
 * el 2026-08-17 al publicar la misión y los valores — el documento traía «…hace
 * más daño que un error / grande.**» y la pantalla mostró los asteriscos, porque
 * cada línea era un párrafo distinto y la negrita nunca llegaba a cerrar.
 */
function marcaAbierta(linea: string): boolean {
  const negritas = (linea.match(/\*\*/g) ?? []).length;
  const codigos = (linea.match(/`/g) ?? []).length;
  return negritas % 2 === 1 || codigos % 2 === 1;
}

/**
 * Lo que NUNCA se une a la línea anterior, aunque empiece en minúscula.
 *
 * Son los renglones que el documento puso aparte a propósito: los incisos «a)
 * Central (CCO)» del Reglamento, los romanos, las casillas del formato de queja y
 * las etiquetas «**Fecha:**» de la cabecera de una carta. Unirlos convertiría una
 * enumeración en un párrafo corrido.
 */
const NO_CONTINUA = /^(\*\*[^*]{1,40}:\*\*|[a-zA-Z]\)|[ivxIVX]{1,4}[.)]\s|\[[ xX]?\])/;

/**
 * Un signo con el que ninguna frase EMPIEZA.
 *
 * Si la línea abre con una raya, una coma o un punto y coma, no está empezando
 * nada: está terminando lo de arriba. La prosa de estos documentos usa mucho el
 * inciso con rayas —«Cuando una decisión no esté escrita en ningún manual / —y
 * muchas no lo estarán— la respuesta se busca aquí»—, y sin esta regla esa
 * segunda mitad se quedaba en un párrafo propio, empezando por un guion largo.
 */
const ABRE_CON_PUNTUACION = /^[—–,;:)»…]/;

/** La primera letra de la línea, saltando el marcado que la pueda preceder. */
function empiezaEnMinuscula(linea: string): boolean {
  for (const ch of linea) {
    if (/[a-záéíóúñü]/i.test(ch)) return ch === ch.toLowerCase();
    if (/[*`_"«¿¡(]/.test(ch)) continue;
    return false;
  }
  return false;
}

/**
 * ¿La línea `b` continúa el párrafo que venía en `a`?
 *
 * POR QUÉ NO SE APLICA LA REGLA DE MARKDOWN A SECAS. En markdown, dos líneas
 * seguidas son SIEMPRE el mismo párrafo. Aquí no se puede: lo que se pinta es el
 * texto que ya se acusó, y hay documentos publicados cuya cabecera son cinco
 * renglones sueltos —razón social, versión, régimen, centros de trabajo, quién
 * emite— que unidos quedarían en un párrafo corrido. Se une solo cuando la unión
 * es inequívoca y en la duda se deja como estaba, así que este cambio no puede
 * empeorar ningún documento ya firmado.
 *
 * Medido sobre los diez documentos de `docs/disciplina-tardanzas-faltas/`: de 241
 * pares de líneas de prosa consecutivas, 141 se unen por la señal de minúscula y
 * los otros 100 se quedan como estaban.
 */
function continua(a: string, b: string): boolean {
  if (!b || NO_CONTINUA.test(b)) return false;
  if (marcaAbierta(a)) return true;
  if (ABRE_CON_PUNTUACION.test(b)) return true;
  return empiezaEnMinuscula(b);
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
// El número se CAPTURA, no se descarta: es el que la lista tiene que arrancar.
const NUMERADA = /^(\d{1,2})[.)]\s+(.*)$/;

export function bloquesDe(texto: string): Bloque[] {
  const salida: Bloque[] = [];
  let lista: {
    ordenada: boolean; items: Marca[][]; enCita: boolean; inicio: number;
    /** La línea tal como venía, para poder deshacer una lista de un solo ítem. */
    crudos: string[];
  } | null = null;
  let tabla: { cabecera: Marca[][] | null; filas: Marca[][][]; enCita: boolean } | null = null;
  /**
   * El párrafo que se está juntando. `duro` recuerda si su última línea acabó en
   * el salto forzado de markdown —dos espacios finales—, que el Índice del
   * Reglamento usa en sus doce títulos.
   */
  let parrafo: { lineas: string[]; enCita: boolean; duro: boolean } | null = null;

  const cerrarParrafo = () => {
    if (!parrafo) return;
    // Se une con UN espacio, nunca con «\n»: el visor pinta estos bloques con
    // `whitespace-pre-wrap` para conservar las rachas de espacios de las casillas
    // de firma, y ahí un «\n» sería un salto de línea de verdad.
    const marcas = marcasDe(parrafo.lineas.join(" "));
    salida.push(parrafo.enCita ? { tipo: "cita", marcas } : { tipo: "parrafo", marcas });
    parrafo = null;
  };
  const cerrarLista = () => {
    if (!lista) return;
    // UNA línea numerada suelta no es una lista: es prosa que empieza con un
    // número. El Índice del Reglamento son doce líneas de ese tipo —«5. SELECCIÓN
    // E IGUALDAD…»— y como lista de un ítem el navegador las renumeraba todas a
    // «1.», publicando once números de artículo que el documento no dice. Peor: el
    // resto de números de la misma línea sí sobrevivía, así que el renglón se
    // contradecía a sí mismo. Devuelta a párrafo, el número vuelve a ser el suyo
    // porque va dentro del texto.
    if (lista.ordenada && lista.items.length === 1) {
      const marcas = marcasDe(lista.crudos[0]);
      salida.push(lista.enCita ? { tipo: "cita", marcas } : { tipo: "parrafo", marcas });
    } else {
      const { ordenada, items, enCita, inicio } = lista;
      salida.push({ tipo: "lista", ordenada, items, enCita, inicio });
    }
    lista = null;
  };
  const cerrarTabla = () => {
    // Una tabla que solo tuvo cabecera y ninguna fila sigue siendo una tabla:
    // en el cargo de recepción, la cabecera ES la casilla que se rellena a mano.
    if (tabla) { salida.push({ tipo: "tabla", ...tabla }); tabla = null; }
  };

  for (const linea of texto.split("\n")) {
    // El salto forzado se mide ANTES de recortar, que es lo único que lo borra.
    const duro = / {2,}$/.test(linea.replace(/\r$/, ""));
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
      cerrarParrafo();
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
    if (enCita && !t) { cerrarParrafo(); salida.push({ tipo: "espacio" }); continue; }
    cerrarTabla();

    // ── Lista ──────────────────────────────────────────────────────────────
    // Ojo con el orden: `---` es una regla horizontal, no una viñeta, y hay que
    // descartarlo ANTES de mirar si empieza por guion.
    if (t !== "---") {
      const v = VINETA.exec(t);
      const n = NUMERADA.exec(t);
      if (v || n) {
        cerrarParrafo();
        const ordenada = n !== null;
        if (lista && (lista.ordenada !== ordenada || lista.enCita !== enCita)) cerrarLista();
        if (!lista) lista = { ordenada, items: [], enCita, inicio: ordenada ? Number(n![1]) : 1, crudos: [] };
        lista.items.push(marcasDe(v ? v[1] : n![2]));
        lista.crudos.push(t);
        continue;
      }
    }
    cerrarLista();

    // ── Lo demás ───────────────────────────────────────────────────────────
    // Una línea vacía JUSTO DESPUÉS de un encabezado no deja bloque.
    //
    // No es aseo: el visor pinta cada «espacio» como un div de 8 px, y el
    // markdown siempre deja una línea en blanco entre el «### ARTÍCULO 34» y su
    // primer párrafo. Con ese div en medio, el `break-after-avoid` de la hoja
    // impresa pega el título al div vacío y el salto de página SIGUE cabiendo
    // detrás: el artículo se queda solo al pie de una cara con su texto en la
    // siguiente, que en papel se lee como si faltara algo. El Reglamento tiene 68
    // encabezados de artículo y se imprime para el cargo que se firma.
    //
    // El hueco no se pierde: el encabezado ya trae su `mt-*` y el párrafo su
    // `my-2`.
    if (!t) {
      cerrarParrafo();
      if (salida[salida.length - 1]?.tipo !== "encabezado") salida.push({ tipo: "espacio" });
      continue;
    }
    if (t === "---") { cerrarParrafo(); salida.push({ tipo: "regla" }); continue; }
    const enc = /^(#{1,4})\s+(.*)$/.exec(t);
    if (enc && !enCita) {
      cerrarParrafo();
      salida.push({ tipo: "encabezado", nivel: enc[1].length as 1 | 2 | 3 | 4, marcas: marcasDe(enc[2]) });
      continue;
    }
    // ── Párrafo, juntando lo que sea continuación ──────────────────────────
    // La decisión de unir vive en `continua()`, con su porqué. Aquí solo se
    // aplica: mismo tipo de bloque, la línea anterior sin salto forzado, y la
    // siguiente reconocible como continuación de la frase.
    if (parrafo && parrafo.enCita === enCita && !parrafo.duro
        && continua(parrafo.lineas[parrafo.lineas.length - 1], t)) {
      parrafo.lineas.push(t);
      parrafo.duro = duro;
      continue;
    }
    cerrarParrafo();
    parrafo = { lineas: [t], enCita, duro };
  }

  cerrarParrafo();
  cerrarLista();
  cerrarTabla();
  return salida;
}

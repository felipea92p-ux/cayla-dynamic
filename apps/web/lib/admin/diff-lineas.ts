/**
 * Comparar dos versiones de un documento, línea por línea.
 *
 * POR QUÉ UNA LCS PROPIA Y NO UNA LIBRERÍA
 *
 * El repositorio no trae ninguna dependencia de diff (revisado en
 * package.json), y esta tarea no tiene acceso a instalar una. El problema
 * tampoco lo pide: comparar dos versiones de un reglamento es exactamente el
 * caso de libro de texto de la subsecuencia común más larga (LCS) — encontrar
 * qué líneas sobreviven sin cambios entre dos textos y marcar el resto como
 * quitado o agregado. No hace falta un diff por palabra ni por carácter: estos
 * documentos se editan por artículo, y una línea es la unidad natural.
 *
 * CÓMO FUNCIONA
 *
 * Tabla de programación dinámica: `dp[i][j]` = el largo de la subsecuencia común
 * más larga entre las líneas `a[i..]` y `b[j..]`. Se llena de atrás hacia
 * adelante y después se recorre de adelante hacia atrás para reconstruir la
 * secuencia de líneas iguales/agregadas/quitadas.
 *
 * POR QUÉ UN LÍMITE DE TAMAÑO
 *
 * El Reglamento pesa ~300 KB. Dos versiones de un documento así rondan los
 * miles de líneas cada una, y la tabla completa es `n × m` — con ambos en unos
 * pocos miles de líneas, la tabla cabe cómoda en memoria y se llena en milisegundos.
 * Pero nada impide que alguien pegue, por error, dos documentos enormes y
 * distintos entre sí (no una edición, sino dos textos ajenos) — ahí `n × m`
 * puede llegar a decenas de millones de celdas y colgar la pestaña. Por eso, si
 * el producto de líneas pasa el límite, se usa un camino más simple: alinear el
 * principio y el final que coinciden y marcar todo lo del medio como
 * "quitado" + "agregado", sin intentar encontrar coincidencias parciales ahí
 * dentro. Sigue siendo correcto — nunca inventa una línea que no estaba en
 * ninguno de los dos textos — solo menos prolijo mostrando qué cambió en medio.
 */

export interface LineaDiff {
  tipo: "igual" | "agregada" | "quitada";
  texto: string;
}

/** Por encima de esto, la tabla n×m ya no es segura de construir en el navegador. */
const LIMITE_CELDAS_LCS = 4_000_000;

export function diffLineas(textoAnterior: string, textoNuevo: string): LineaDiff[] {
  const a = textoAnterior.split("\n");
  const b = textoNuevo.split("\n");

  if (a.length * b.length > LIMITE_CELDAS_LCS) {
    return diffLineasSimplificado(a, b);
  }

  return diffLineasLcs(a, b);
}

function diffLineasLcs(a: string[], b: string[]): LineaDiff[] {
  const n = a.length;
  const m = b.length;
  // Tabla achatada en un solo Int32Array: n+1 arrays chicos por separado
  // presionan más al recolector de basura que una sola asignación contigua.
  const dp = new Int32Array((n + 1) * (m + 1));
  const idx = (i: number, j: number) => i * (m + 1) + j;

  for (let i = n - 1; i >= 0; i--) {
    for (let j = m - 1; j >= 0; j--) {
      dp[idx(i, j)] =
        a[i] === b[j]
          ? dp[idx(i + 1, j + 1)] + 1
          : Math.max(dp[idx(i + 1, j)], dp[idx(i, j + 1)]);
    }
  }

  const resultado: LineaDiff[] = [];
  let i = 0;
  let j = 0;
  while (i < n && j < m) {
    if (a[i] === b[j]) {
      resultado.push({ tipo: "igual", texto: a[i] });
      i++;
      j++;
    } else if (dp[idx(i + 1, j)] >= dp[idx(i, j + 1)]) {
      resultado.push({ tipo: "quitada", texto: a[i] });
      i++;
    } else {
      resultado.push({ tipo: "agregada", texto: b[j] });
      j++;
    }
  }
  while (i < n) { resultado.push({ tipo: "quitada", texto: a[i] }); i++; }
  while (j < m) { resultado.push({ tipo: "agregada", texto: b[j] }); j++; }
  return resultado;
}

/** El camino de emergencia para dos textos enormes: solo alinea el principio y
 *  el final que coinciden línea por línea, sin buscar coincidencias en medio. */
function diffLineasSimplificado(a: string[], b: string[]): LineaDiff[] {
  let inicio = 0;
  while (inicio < a.length && inicio < b.length && a[inicio] === b[inicio]) inicio++;

  let finA = a.length - 1;
  let finB = b.length - 1;
  while (finA >= inicio && finB >= inicio && a[finA] === b[finB]) { finA--; finB--; }

  const resultado: LineaDiff[] = [];
  for (let k = 0; k < inicio; k++) resultado.push({ tipo: "igual", texto: a[k] });
  for (let k = inicio; k <= finA; k++) resultado.push({ tipo: "quitada", texto: a[k] });
  for (let k = inicio; k <= finB; k++) resultado.push({ tipo: "agregada", texto: b[k] });
  for (let k = finA + 1; k < a.length; k++) resultado.push({ tipo: "igual", texto: a[k] });
  return resultado;
}

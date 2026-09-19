// ============================================================================
// historial-correcciones.ts — cómo se lee una fila de correcciones_auditoria
// ============================================================================
// QUÉ PROMETE · traducir una fila del libro de correcciones a «qué pasó, de qué
//               día y con qué detalle», en español y en hora de Lima.
// QUÉ ASUME   · que las filas las escribieron las funciones de la base (0009,
//               0081, 0304/0376, 0437…); el vocabulario de campos vive en
//               packages/shared/src/auditoria.ts.
//
// Vive aquí y no dentro de la pantalla para poder probarlo: lo que hay que
// defender es que una marca apartada declarada IMPROCEDENTE no se lea como
// «pendiente», y eso no se ve mirando la pantalla funcionando bien.
// ============================================================================
import {
  RESOLUCION_MARCA_APARTADA, TIPO_MARCA_LABELS, TZ_LIMA, anioLima, fechaLima, rotuloDeCampo, type TipoMarca,
} from "@cayla-dynamic/shared";

// Un timestamptz guardado como texto crudo en la auditoría (ej. "2026-07-18
// 19:15:00+00") o un ISO -> Date. Tolera el espacio en vez de T y offsets
// cortos como "-05". Devuelve null si aun así no parsea.
export function tsAuditoria(s: string | null | undefined): Date | null {
  if (!s) return null;
  const d = new Date(s.trim().replace(" ", "T").replace(/([+-]\d{2})$/, "$1:00"));
  return isNaN(d.getTime()) ? null : d;
}
// Lo mismo -> hora Lima "hh:mm a.m."; si no parsea, muestra el texto crudo.
export function horaTextoLima(s: string | null): string {
  if (!s) return "—";
  const d = tsAuditoria(s);
  if (!d) return s;
  return new Intl.DateTimeFormat("es-PE", { timeZone: TZ_LIMA, hour: "2-digit", minute: "2-digit", hour12: true }).format(d);
}
// Y el DÍA de Lima de ese mismo timestamp, corto: "28 ago." (la abreviatura la
// pone es-PE, con su punto).
//
// El día se pregunta a `fechaLima` —la única que sabe cuándo empieza el día en
// Perú— y recién esa fecha ya resuelta se formatea, en UTC, para que ponerle
// otra vez la zona no la corra un día hacia atrás (el mismo motivo que explica
// `nombreDelMesLima` en fecha-lima.ts).
//
// Lleva el año solo cuando no es el de hoy: el historial trae las últimas 30
// correcciones de la persona, así que puede cruzar un fin de año, y "28 ago" a
// secas dejaría dos días distintos escritos igual. `forzarAnio` existe para el
// caso en que se muestran DOS días juntos y uno de ellos ya lo lleva: ponérselo
// a uno solo deja la pareja asimétrica ("31 dic. 2025 → 1 ene.") justo en el
// cambio de año, que es cuando más falta hace leerlo.
export function diaTextoLima(s: string | null | undefined, forzarAnio = false): string | null {
  const d = tsAuditoria(s);
  if (!d) return null;
  const [y, m, dd] = fechaLima(d).split("-").map(Number);
  const formato: Intl.DateTimeFormatOptions = { day: "numeric", month: "short", timeZone: "UTC" };
  if (forzarAnio || y !== anioLima()) formato.year = "numeric";
  return new Intl.DateTimeFormat("es-PE", formato).format(new Date(Date.UTC(y, m - 1, dd)));
}
// Fila de correcciones_auditoria (el registro de quién cambió qué, cuándo y por qué).
// Sin embeds de PostgREST a propósito: en este repo el schema cache está trabado
// para varias relaciones, así que el nombre de quién corrigió se resuelve aparte
// desde la lista de personas ya cargada (ver `nombrePorId`).
export interface Auditoria {
  id: string;
  campo_modificado: string;
  valor_anterior: string | null;
  valor_nuevo: string | null;
  corregido_at: string;
  motivo: string;
  corregido_por: string; // id de quien hizo el cambio
}
// Qué campos son de marcaje, y cómo se llama cada tema, lo dice
// `packages/shared/src/auditoria.ts` — la misma lista que lee /mio y que una
// prueba compara contra los `insert` de las migraciones. Antes esta pantalla
// tenía la suya, con 7 campos, y `tipo` y `auto_cierre_confirmado` salían como
// «otro sistema» con el nombre crudo de la columna.

// Traduce una fila de auditoría a lenguaje llano: qué acción fue, DE QUÉ DÍA y
// su detalle. El tipo de marcaje ya viene embebido en el valor de
// agregado/eliminado ("entrada @ ts"); para una hora corregida solo cambian las
// horas.
//
// CAMBIO · `cuando` es nuevo (hallazgo 30 de la auditoría del 2026-09-03/04).
// Hasta hoy los casos que sí estaban escritos formateaban solo la HORA del
// timestamp y tiraban el día, aunque el día viniera dentro del mismo valor: el
// 3 de septiembre se corregía la salida del 28 de agosto y el historial decía
// «Hora corregida · 06:00 p. m. → 07:30 p. m.», sin decir qué jornada se había
// tocado. Este historial es el rastro de `correcciones_auditoria`, que existe
// justamente para auditar, y sin la fecha no se puede.
//
// Y peor: `marcaje_anulado` y `auto_cierre_reemplazado` NO tenían rama, así que
// caían al último `return` y mostraban el timestamp CRUDO, en UTC — que para
// cualquier marca de la tarde-noche de Lima nombra el DÍA SIGUIENTE. Anular es,
// además, lo único que hace el botón de esta pantalla: borrar marcas no se hace
// desde la 0081, así que la rama que se había escrito primero (`eliminado`) era
// la única que ninguna pantalla produce. Se enumeran acá por eso: qué escribe
// cada función se lee en la migración, no se supone por el nombre del campo.
//
// El día del marcaje CORREGIDO y el día en que se hizo la corrección son dos
// cosas distintas, y en la fila se ven las dos: esta va pegada a la acción y la
// otra al sello de la derecha, que dice «corregido …» para que no se confundan.
// Una hora que pasó a ser otra. Si las dos caen el mismo día de Lima, ese día se
// dice una vez y va en `cuando`; si la marca se movió de un día a otro —lo que
// cambia DOS jornadas— los dos días van dentro del detalle, cada uno pegado a su
// hora, porque decir «del 28 ago» a secas escondería justo el cambio que importa.
function cambioDeHora(accion: string, tsAntes: string | null, tsDespues: string | null) {
  const diaAntes = diaTextoLima(tsAntes);
  const diaDespues = diaTextoLima(tsDespues);
  if (diaAntes && diaDespues && diaAntes !== diaDespues) {
    // Si uno de los dos ya lleva año (o sea, el movimiento cruza el fin de año),
    // lo llevan los dos: si no, la pareja sale «31 dic. 2025 → 1 ene.».
    const cruzaAnio = /\d{4}/.test(diaAntes) || /\d{4}/.test(diaDespues);
    const antes = cruzaAnio ? diaTextoLima(tsAntes, true)! : diaAntes;
    const despues = cruzaAnio ? diaTextoLima(tsDespues, true)! : diaDespues;
    return {
      accion,
      cuando: null,
      detalle: `${antes}, ${horaTextoLima(tsAntes)} → ${despues}, ${horaTextoLima(tsDespues)}`,
    };
  }
  return {
    accion,
    cuando: diaAntes ?? diaDespues,
    detalle: `${horaTextoLima(tsAntes)} → ${horaTextoLima(tsDespues)}`,
  };
}

export function describirCambio(row: Auditoria): { accion: string; cuando: string | null; detalle: string } {
  const lblTipo = (t?: string | null) => (t && TIPO_MARCA_LABELS[t as TipoMarca]) || t || "marcaje";
  const tsDe = (v: string | null) => (v ?? "").split(" @ ")[1] ?? null;
  if (row.campo_modificado === "timestamp_marca") {
    return cambioDeHora("Hora corregida", row.valor_anterior, row.valor_nuevo);
  }
  // El terminal cambió la salida final que había puesto el auto-cierre por la
  // hora real en que se cerró tienda. Los dos valores traen "tipo @ timestamp",
  // así que antes salían los DOS en UTC crudo — el mismo defecto, por duplicado.
  if (row.campo_modificado === "auto_cierre_reemplazado") {
    return cambioDeHora("Salida final repuesta", tsDe(row.valor_anterior), tsDe(row.valor_nuevo));
  }
  // Cambiar el TIPO de una marca (p. ej. «Salida a almuerzo» → «Salida final»)
  // es lo que decide si un día queda cerrado. Antes caía al final y salía como
  // «tipo · salida_almuerzo → salida_final» con la insignia «otro sistema».
  if (row.campo_modificado === "tipo") {
    return { accion: rotuloDeCampo("tipo"), cuando: null, detalle: `${lblTipo(row.valor_anterior)} → ${lblTipo(row.valor_nuevo)}` };
  }
  // `fn_confirmar_auto_cierre` (0437): valores «pendiente_revision» → «revisada».
  if (row.campo_modificado === "auto_cierre_confirmado") {
    return { accion: rotuloDeCampo("auto_cierre_confirmado"), cuando: null, detalle: "la hora que puso el sistema pasó a ser la salida final del día" };
  }
  if (row.campo_modificado === "marcaje_agregado") {
    const [tipo, ts] = (row.valor_nuevo ?? "").split(" @ ");
    return { accion: "Marcaje agregado", cuando: diaTextoLima(ts), detalle: `${lblTipo(tipo)} a las ${horaTextoLima(ts)}` };
  }
  // Anular es lo que HACE de verdad esta pantalla: desde la 0081 las marcas no
  // se borran, se anulan (el botón de la fila llama a `fn_anular_marcaje`).
  // `valor_anterior` trae "tipo @ timestamp" igual que las de arriba, y
  // `valor_nuevo` es la palabra "anulada" — que no aporta nada al detalle.
  if (row.campo_modificado === "marcaje_anulado") {
    const [tipo, ts] = (row.valor_anterior ?? "").split(" @ ");
    return { accion: "Marcaje anulado", cuando: diaTextoLima(ts), detalle: `${lblTipo(tipo)} de las ${horaTextoLima(ts)}` };
  }
  // Y su vuelta atrás. Acá `valor_anterior` es "anulada: <por qué se anuló>" y
  // `valor_nuevo` el tipo de marca: NO hay timestamp en ninguno de los dos, así
  // que `cuando` va en null a propósito — no es un olvido, es que la fila no
  // guarda el día. Se sigue viendo en la marca misma, arriba, destachada.
  if (row.campo_modificado === "marcaje_reactivado") {
    const motivoAnulacion = (row.valor_anterior ?? "").replace(/^anulada:\s*/i, "").trim();
    return {
      accion: "Marcaje reactivado",
      cuando: null,
      detalle: motivoAnulacion
        ? `${lblTipo(row.valor_nuevo)} — se había anulado por “${motivoAnulacion}”`
        : lblTipo(row.valor_nuevo),
    };
  }
  // Ninguna pantalla borra marcas hoy —`fn_eliminar_marcaje` no la llama nadie
  // desde la 0081—, pero la tabla guarda filas viejas de cuando sí se borraban,
  // y el historial no está acotado por fecha. Se queda por ellas.
  if (row.campo_modificado === "marcaje_eliminado") {
    const [tipo, ts] = (row.valor_anterior ?? "").split(" @ ");
    return { accion: "Marcaje eliminado", cuando: diaTextoLima(ts), detalle: `${lblTipo(tipo)} de las ${horaTextoLima(ts)}` };
  }
  // Marca apartada. Hay dos formas de fila, y las dos existen hoy:
  //  · la de ahora (`fn_marca_apartada_resolver`, 0304/0376): `valor_anterior` =
  //    «tipo del DD/MM/AAAA HH:MM · error del terminal», `valor_nuevo` = cómo se
  //    resolvió (`repuesta` o `improcedente`). Esta pantalla decía «quedó
  //    pendiente de revisión manual» para las dos — incluida `improcedente`, que
  //    significa que NO se registró ningún marcaje y el día se paga como falta.
  //    El comentario de aquí afirmaba que «ya no se escriben así»: era falso.
  //  · la vieja, con el error crudo de Postgres en los dos valores.
  if (row.campo_modificado === "marca_apartada" && row.valor_nuevo && row.valor_nuevo in RESOLUCION_MARCA_APARTADA) {
    // El error del terminal (tras « · ») no se muestra: es ruido técnico.
    const marca = (row.valor_anterior ?? "").split(" · ")[0];
    const [tipo, cuando] = marca.split(" del ");
    return {
      accion: rotuloDeCampo("marca_apartada"),
      cuando: null,
      detalle: `${lblTipo(tipo)}${cuando ? ` del ${cuando}` : ""}: ${RESOLUCION_MARCA_APARTADA[row.valor_nuevo]}`,
    };
  }
  if (row.campo_modificado === "marca_apartada") {
    return { accion: "Marca apartada", cuando: diaTextoLima(row.valor_nuevo) ?? diaTextoLima(row.valor_anterior), detalle: "no se pudo registrar sola; quedó pendiente de revisión manual" };
  }
  // Cualquier otro campo desconocido, o uno cuyo valor es un mensaje técnico
  // (un error de Postgres) en vez de un dato de negocio: se muestra el nombre
  // del campo, nunca el contenido crudo — este historial es para Cayla, no
  // para depurar.
  // Cada valor se juzga por separado: antes bastaba que UNO fuera legible para
  // mostrar los dos, y el otro podía ser el error crudo de Postgres.
  const esTexto = (v: string | null) => !!v && v.length < 80 && !/[{}();]|=>|public\./.test(v);
  const antes = esTexto(row.valor_anterior) ? row.valor_anterior : null;
  const despues = esTexto(row.valor_nuevo) ? row.valor_nuevo : null;
  const detalle = antes || despues
    ? `${antes ?? "—"} → ${despues ?? "—"}`
    : "el detalle técnico no se muestra aquí; queda guardado en la auditoría";
  return { accion: rotuloDeCampo(row.campo_modificado), cuando: null, detalle };
}


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

// ── El horario, dicho como lo diría una persona ──────────────────────────────
// `horarios_asignados` lo escriben dos puertas, y entre las dos dejan CINCO
// formas de valor — se leen en las migraciones, no se suponen:
//  · fn_set_horario_semanal (0440): «vigente desde AAAA-MM-DD: {json}», o con
//    la forma vieja «… : días {1,2,3} 08:00:00–17:00:00», o «sin horario previo».
//  · fn_corregir_horario_pasado (0447): el nuevo es el json a secas, y el
//    anterior un arreglo de tramos {vigente_desde, vigente_hasta,
//    horario_por_dia} o «(sin horario previo en ese rango)».
// Antes caían al último `return` y salían crudos —en /mio, media pantalla de
// {"1": {"e": "08:30", "r": 60, …}} en el celular de la persona— o, en el
// panel, como «el detalle técnico no se muestra aquí»: un cambio de horario
// decide qué se le cuenta como tardanza o falta, y no decía cuál.
const DIAS_CORTOS = ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"];

type Tramo = { e?: string; s?: string; r?: number | string };

// «2026-09-26» → «26 set.». Es una FECHA, no un instante: se formatea en UTC
// para que ponerle zona no la corra al día anterior (pasarla por
// `diaTextoLima` la leería como medianoche UTC = 25 en Lima).
function fechaCorta(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  const formato: Intl.DateTimeFormatOptions = { day: "numeric", month: "short", timeZone: "UTC" };
  if (y !== anioLima()) formato.year = "numeric";
  return new Intl.DateTimeFormat("es-PE", formato).format(new Date(Date.UTC(y, m - 1, d)));
}

const hhmm = (t?: string) => (t ?? "").slice(0, 5);

// {"1": {...}, "2": {...}, "6": {...}} → «lun a vie 08:30–14:00 · sáb 08:30–14:30».
// Agrupa días SEGUIDOS con el mismo horario; el refrigerio se dice una vez si
// es igual para todos, y por grupo si no — si no, un cambio que solo toca el
// refrigerio se leería «X → X», igual antes que después.
export function horarioSemanalEnPalabras(porDia: Record<string, Tramo>): string {
  const dias = Object.keys(porDia).map(Number).filter((n) => n >= 0 && n <= 6);
  // Lunes primero: la semana de CAYLA se piensa de lunes a domingo.
  dias.sort((a, b) => ((a + 6) % 7) - ((b + 6) % 7));
  if (dias.length === 0) return "sin días de trabajo";
  const refri = (t: Tramo) => (t.r === undefined || t.r === null || t.r === "" ? null : Number(t.r));
  const refris = new Set(dias.map((d) => refri(porDia[d])));
  const refriComun = refris.size === 1;

  const grupos: { desde: number; hasta: number; clave: string; tramo: Tramo }[] = [];
  for (const d of dias) {
    const t = porDia[d];
    const clave = `${hhmm(t.e)}|${hhmm(t.s)}|${refriComun ? "" : refri(t)}`;
    const ultimo = grupos[grupos.length - 1];
    if (ultimo && ultimo.clave === clave && (ultimo.hasta + 1) % 7 === d) ultimo.hasta = d;
    else grupos.push({ desde: d, hasta: d, clave, tramo: t });
  }
  const partes = grupos.map(({ desde, hasta, tramo }) => {
    const nombre = desde === hasta ? DIAS_CORTOS[desde]
      : (hasta - desde + 7) % 7 === 1 ? `${DIAS_CORTOS[desde]} y ${DIAS_CORTOS[hasta]}`
      : `${DIAS_CORTOS[desde]} a ${DIAS_CORTOS[hasta]}`;
    const horas = tramo.s ? `${hhmm(tramo.e)}–${hhmm(tramo.s)}` : `desde ${hhmm(tramo.e)}`;
    const r = refri(tramo);
    return `${nombre} ${horas}${!refriComun && r ? ` (${r} min de refrigerio)` : ""}`;
  });
  const r = refriComun ? refri(porDia[dias[0]]) : null;
  return partes.join(" · ") + (r ? `, ${r} min de refrigerio` : "");
}

export function horarioEnPalabras(valor: string | null): string {
  if (!valor || /sin horario previo/i.test(valor)) return "sin horario";
  const conFecha = valor.match(/^vigente desde (\d{4}-\d{2}-\d{2}):\s*([\s\S]*)$/);
  const desde = conFecha ? `desde el ${fechaCorta(conFecha[1])}: ` : "";
  const cuerpo = (conFecha ? conFecha[2] : valor).trim();
  // La forma vieja (sin horario_por_dia): «días {1,2,3} 08:00:00–17:00:00».
  const vieja = cuerpo.match(/^días \{([\d,]*)\} (\S+)–(\S+)$/);
  if (vieja) {
    const porDia = Object.fromEntries(vieja[1].split(",").filter(Boolean).map((d) => [d, { e: vieja[2], s: vieja[3] }]));
    return desde + horarioSemanalEnPalabras(porDia);
  }
  try {
    const json: unknown = JSON.parse(cuerpo);
    if (Array.isArray(json)) {
      const tramos = json as { vigente_desde?: string; horario_por_dia?: Record<string, Tramo> | null }[];
      return tramos
        .map((t) => `${t.vigente_desde ? `desde el ${fechaCorta(t.vigente_desde)}: ` : ""}${t.horario_por_dia ? horarioSemanalEnPalabras(t.horario_por_dia) : "horario anterior"}`)
        .join(" / ") || "sin horario";
    }
    if (json && typeof json === "object") return desde + horarioSemanalEnPalabras(json as Record<string, Tramo>);
  } catch {
    // No es JSON: cae abajo.
  }
  // Una forma que nadie escribe hoy. Mejor no mostrar nada que mostrar llaves.
  return desde + "otro horario";
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
  if (row.campo_modificado === "horarios_asignados") {
    const antes = horarioEnPalabras(row.valor_anterior);
    const despues = horarioEnPalabras(row.valor_nuevo);
    // La 0440 escribe la MISMA vigencia en los dos lados; dicha dos veces,
    // la frase se volvía un trabalenguas en el celular. Se dice una vez.
    const vigencia = despues.match(/^desde el [^:]+: /)?.[0];
    if (vigencia && antes.startsWith(vigencia)) {
      return {
        accion: rotuloDeCampo("horarios_asignados"),
        cuando: null,
        detalle: `${vigencia.slice(0, -2).replace(/^d/, "D")} pasa de ${antes.slice(vigencia.length)} a ${despues.slice(vigencia.length)}`,
      };
    }
    return { accion: rotuloDeCampo("horarios_asignados"), cuando: null, detalle: `${antes} → ${despues}` };
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
  // Un valor que NACE (una firma, un documento) no tiene «antes»: «— → firmado»
  // se leía como si algo se hubiera borrado. Se dice solo lo nuevo.
  const detalle = antes && despues ? `${antes} → ${despues}`
    : despues ? despues
    : antes ? `${antes} → —`
    : "el detalle técnico no se muestra aquí; queda guardado en la auditoría";
  return { accion: rotuloDeCampo(row.campo_modificado), cuando: null, detalle };
}


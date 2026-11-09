// ─────────────────────────────────────────────────────────────────────────────
// «Cómo funciona la disciplina» — la guía que la colaboradora lee en Info.
//
// QUÉ PROMETE
//   El texto de la guía (`/mio/disciplina/como-funciona`), escrito para alguien
//   sin formación legal, con cada regla atada al numeral del Reglamento Interno
//   de Trabajo que la dice. Y la respuesta a una sola pregunta: ¿la versión que
//   esta guía resume es la que rige hoy?
//
// QUÉ ASUME
//   · Que el Reglamento vigente se lee de `fn_documentos_vigentes` (tipo `rit`,
//     columna `etiqueta_version`, 0265): la misma fuente que usa Normas.
//   · Que el plazo REAL de cada persona lo dice Dynamic en sus cargos
//     (`descargo_vence_at`, que calcula `fn_sumar_dias_habiles` de la 0212). La
//     tira de días de abajo es un ejemplo para entender la regla, no una
//     segunda cuenta: no decide el plazo de nadie y por eso no mira feriados.
//
// POR QUÉ ASÍ
//   El 2026-11-09 la guía nació como un artefacto fuera del sistema, y su
//   defecto quedó dicho ese mismo día: un resumen sin versión envejece en
//   silencio cuando sale el Reglamento siguiente, y si dice algo más favorable
//   que el Reglamento, se puede invocar (60.12). Por eso vive aquí y se protege
//   de dos maneras:
//     1. `tests/guia-disciplina.test.ts` lee `docs/reglamento-interno-de-trabajo.md`:
//        falla si una cita apunta a un numeral que no existe y falla si el
//        Reglamento del repositorio sube de versión sin que esta guía lo haga.
//     2. La pantalla compara `REGLAMENTO_RESUMIDO` con el vigente en la base y,
//        si no coinciden, lo dice arriba de todo (`estadoDeLaGuia`).
//   Los textos son datos y no JSX para que esas pruebas puedan recorrerlos.
//
// CÓMO SE ESCRIBE UN TEXTO
//   `**así**` es negrita y `[[19.2 · 57.10]]` es la cita al Reglamento (se dibuja
//   chica, «RIT 19.2 · 57.10»). Nada más: `trozos()` no entiende otra marca.
//
// SE ROMPE SI
//   Alguien cambia una regla aquí sin cambiarla en el Reglamento (la prueba no
//   lo ve: compara números, no frases). Se revisa contra el Reglamento cada vez
//   que este cambie, y al revés.
// ─────────────────────────────────────────────────────────────────────────────

/** La versión del Reglamento que esta guía resume. Se cambia SOLO revisando la guía entera contra la nueva. */
export const REGLAMENTO_RESUMIDO = { etiqueta: "4.0", vigenteDesde: "2026-08-10" } as const;

/** El día en que la guía se revisó por última vez contra el Reglamento y contra lo que hace Dynamic. */
export const GUIA_REVISADA = "2026-11-09";

// ── El texto con marcas ──────────────────────────────────────────────────────

export type Trozo = { tipo: "texto" | "negrita" | "ref"; valor: string };

/** Parte un texto en trozos: texto suelto, `**negrita**` y `[[cita]]`. Una marca sin cerrar queda como texto. */
export function trozos(t: string): Trozo[] {
  const salida: Trozo[] = [];
  const marca = /\*\*(.+?)\*\*|\[\[(.+?)\]\]/g;
  let desde = 0;
  for (const m of t.matchAll(marca)) {
    const i = m.index ?? 0;
    if (i > desde) salida.push({ tipo: "texto", valor: t.slice(desde, i) });
    salida.push(m[1] !== undefined ? { tipo: "negrita", valor: m[1] } : { tipo: "ref", valor: m[2] });
    desde = i + m[0].length;
  }
  if (desde < t.length) salida.push({ tipo: "texto", valor: t.slice(desde) });
  return salida;
}

/** Los numerales citados en un texto: `[[19.2 · 57.10]]` → `["19.2", "57.10"]`. */
export function citasDe(t: string): string[] {
  return trozos(t).filter((x) => x.tipo === "ref").flatMap((x) => x.valor.split("·").map((s) => s.trim()).filter(Boolean));
}

// ── ¿Esta guía resume el Reglamento que rige? ────────────────────────────────

/** «v4.0», «Versión 4.0 », «4» → «4.0». Vacío → null. */
export function normalizarEtiqueta(e: string | null | undefined): string | null {
  if (!e) return null;
  const t = e.trim().toLowerCase().replace(/^(versi[oó]n|v)\.?\s*/, "").trim();
  if (!t) return null;
  return /^\d+$/.test(t) ? `${t}.0` : t;
}

/**
 * `vigente` es la etiqueta del Reglamento que rige («4.1»), o null si la base no la
 * tiene; `desde`, su fecha de vigencia, para poder nombrarlo sin etiqueta.
 */
export type EstadoGuia =
  | { clase: "al_dia"; vigente: string | null }
  | { clase: "desactualizada"; vigente: string | null; desde: string | null }
  | { clase: "sin_saber" };

/**
 * `rit` es la fila del Reglamento que devolvió `fn_documentos_vigentes`, o null si
 * no se pudo leer o no hay Reglamento publicado.
 *
 * Primero manda la etiqueta, porque es lo que el Reglamento dice de sí mismo.
 * Si la base no la tiene —`etiqueta_version` es opcional desde la 0265, y en el
 * entorno local viene vacía—, se compara la fecha de vigencia, que siempre está:
 * sin ese respaldo, este aviso no se encendería nunca. Lo que el respaldo NO
 * distingue: volver a publicar la misma versión (o restaurarla, 0460) le pone
 * una fecha nueva y la guía avisaría de más. Se paga con un aviso de sobra, que
 * solo manda a leer el Reglamento; el error contrario callaría un desfase real.
 *
 * Sin ninguno de los dos datos no se afirma nada: ni «al día» ni «vieja».
 */
export function estadoDeLaGuia(rit: { etiqueta_version: string | null; vigente_desde?: string | null } | null): EstadoGuia {
  if (!rit) return { clase: "sin_saber" };
  const vigente = normalizarEtiqueta(rit.etiqueta_version);
  const desde = rit.vigente_desde?.slice(0, 10) || null;
  if (vigente) {
    return vigente === normalizarEtiqueta(REGLAMENTO_RESUMIDO.etiqueta)
      ? { clase: "al_dia", vigente }
      : { clase: "desactualizada", vigente, desde };
  }
  if (!desde) return { clase: "sin_saber" };
  return desde === REGLAMENTO_RESUMIDO.vigenteDesde
    ? { clase: "al_dia", vigente: null }
    : { clase: "desactualizada", vigente: null, desde };
}

// ── La tira de días hábiles (un ejemplo, no un cálculo) ──────────────────────

const DIA_CORTO = ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"] as const;

export type CeldaTira = { dia: string; clase: "inicio" | "habil" | "fuera" | "vence"; etiqueta: string };

/**
 * Cómo corren `habiles` días hábiles desde el día de la semana `inicio`
 * (0 = domingo). Lunes a viernes cuentan; sábado y domingo no, como en
 * `fn_sumar_dias_habiles`. NO conoce feriados: es la ilustración de la regla.
 */
export function tiraDePlazo(inicio: number, habiles = 2): CeldaTira[] {
  const celdas: CeldaTira[] = [{ dia: DIA_CORTO[inicio], clase: "inicio", etiqueta: "te los comunican" }];
  let contados = 0;
  let d = inicio;
  while (contados < habiles) {
    d = (d + 1) % 7;
    if (d === 0 || d === 6) { celdas.push({ dia: DIA_CORTO[d], clase: "fuera", etiqueta: "no cuenta" }); continue; }
    contados++;
    celdas.push(contados === habiles
      ? { dia: DIA_CORTO[d], clase: "vence", etiqueta: "vence 23:59" }
      : { dia: DIA_CORTO[d], clase: "habil", etiqueta: `día hábil ${contados}` });
  }
  return celdas;
}

/** Los dos ejemplos que se dibujan: un lunes (sin fin de semana en medio) y un jueves (con él). */
export const EJEMPLOS_DE_PLAZO = [
  { titulo: "Si te los comunican un lunes", inicio: 1 },
  { titulo: "Si te los comunican un jueves", inicio: 4 },
] as const;

// ── El contenido ─────────────────────────────────────────────────────────────

export type Tono = "positivo" | "informativo" | "advertencia" | "alerta";

export interface Bloque { titulo: string; texto: string }

export const ESENCIAL: readonly Bloque[] = [
  { titulo: "Nada es automático", texto: "Dynamic detecta, mide y prepara un borrador. Revisarlo, decidir y firmar le toca siempre a una persona. [[52.9]]" },
  { titulo: "Primero te escuchan", texto: "Antes de una amonestación o una suspensión te comunican los cargos y tienes al menos 2 días hábiles para dar tu versión. [[55.2]]" },
  { titulo: "Sin entrega, no cuenta", texto: "Un documento firmado que no te entregaron no pesa como antecedente ni sirve para subir de escalón. [[56.2]]" },
  { titulo: "Una sanción pesa 12 meses", texto: "Una amonestación o una suspensión cuenta como antecedente 12 meses desde el día en que la recibiste. Después queda archivada y ya no agrava nada. [[56.1 · 56.7]]" },
  { titulo: "Nada se sanciona dos veces", texto: "Una tardanza, una falta o un hecho que ya fue sancionado no vuelve a contarse en ningún documento posterior. [[52.5]]" },
  { titulo: "No hay multas", texto: "Lo que no trabajaste no se paga, y eso es todo. No existe ningún descuento extra como castigo. [[17.6 · 54.6]]" },
];

/** La escala del 54.1, de menor a mayor. `noEsSancion` la dibuja punteada. */
export const ESCALA: readonly { nombre: string; noEsSancion?: boolean }[] = [
  { nombre: "Llamada de atención (no es sanción)", noEsSancion: true },
  { nombre: "Amonestación escrita" },
  { nombre: "Suspensión sin goce de haber" },
  { nombre: "Despido, solo por falta grave" },
];

export const SOBRE_LA_ESCALA =
  "La llamada de atención puede quedar en un acta, pero no es sanción, no cuenta como antecedente y no es un escalón [[54.2]]. " +
  "La imputación de cargos tampoco es sanción: es la carta que abre tu derecho a defenderte antes de cualquier decisión grave [[54.3]].";

export interface Escalon { n: number; medida: string; duracion?: string; cuando: string; nota?: string; tono: Tono }

export const TARDANZAS = {
  bajada: "En CAYLA no hay minutos de tolerancia al ingreso. La hora que cuenta es la de tu turno publicado para ese día; si no hay turno, la de tu horario. Siempre en hora de Perú. [[17.1 · 17.2]]",
  reloj: [
    { hora: "07:45:00", que: "Tu hora de ingreso", tarde: false },
    { hora: "07:45:59", que: "Todavía es puntual", tarde: false },
    { hora: "07:46:00", que: "1 minuto de tardanza", tarde: true },
  ],
  noCuenta: [
    "Días sin turno ni horario, tu descanso semanal (en Trujillo es rotativo) y feriados sin turno.",
    "Vacaciones, licencias, permisos, descanso sustitutorio y días de suspensión ya cumplida.",
    "Si tu turno se cargó o se cambió después de empezado el día.",
    "La hora de lactancia acordada al inicio de la jornada.",
    "Las tardanzas por hechos de violencia. [[22]]",
  ],
  noCuentaRef: "[[17.3 · 17.4]]",
  pago: [
    "En CAYLA se pagan las horas trabajadas. Los minutos que no trabajaste simplemente no se pagan. No hay descuento adicional, ni en tu descanso semanal ni en nada más, y tu boleta nunca dirá «descuento por tardanza».",
    "Esto no es una sanción. Por eso tampoco reemplaza a las medidas de la escalera, ni ellas lo reemplazan a él. [[17.6]]",
  ],
  tresHoras: "Una llegada más de 180 minutos después de tu hora suele ser un turno mal cargado. Ese día no cuenta para la escalera ni genera ningún documento hasta que se revise contigo, dentro de los 5 días hábiles siguientes. [[17.5]]",
  justificar: [
    "Pídelo a tu líder de equipo o a Desarrollo Organizacional **dentro de las 48 horas desde que vuelves al trabajo**, no desde que ocurrió.",
    "Si el documento depende de otra persona o entidad (clínica, comisaría, empresa de transporte), basta con probar en ese plazo que ya lo pediste.",
    "Se justifican, entre otras: atención de salud tuya o de un familiar directo a tu cargo, caso fortuito o fuerza mayor (como un paro de transporte), citaciones de autoridad y permisos.",
    "Fuera de plazo pero con un documento válido, se evalúa igual. Si te la rechazan, te lo tienen que decir por escrito y con el motivo.",
    "Si se acepta después de emitido un documento disciplinario, ese día sale del documento y así queda en tu legajo. [[18.5]]",
  ],
  conteo: "Las tardanzas se cuentan por **mes calendario**, del día 1 al último día del mes. No es el periodo de pago, que va del 29 al 28. Cada mes el conteo empieza en cero, pero un antecedente vigente no se borra con el cambio de mes: dura sus 12 meses. [[19.1 · 19.2]]",
  escalera: [
    { n: 0, medida: "Tardanza ocasional", tono: "positivo",
      cuando: "Cuando no llegas a ninguno de los umbrales de abajo. Se registra y **no hay sanción**.",
      nota: "Tu líder de equipo puede conversar contigo y dejar un acta de esa conversación. El acta no es sanción ni antecedente." },
    { n: 1, medida: "Amonestación escrita", tono: "informativo",
      cuando: "**3 tardanzas en un mismo mes**, sin un antecedente vigente por tardanzas." },
    { n: 2, medida: "Primera suspensión", duracion: "1 a 2 días", tono: "advertencia",
      cuando: "**2 o más tardanzas en un mes**, si ya tienes una amonestación por tardanzas vigente." },
    { n: 3, medida: "Segunda suspensión", duracion: "2 a 3 días", tono: "advertencia",
      cuando: "**1 o más tardanzas en un mes**, si ya tienes una suspensión por tardanzas vigente.",
      nota: "Siempre más larga que la primera." },
    { n: 4, medida: "Imputación de cargos", tono: "alerta",
      cuando: "**1 o más tardanzas nuevas** después de recibir la segunda suspensión, mientras esté vigente; o **5 o más tardanzas en 30 días corridos** con una suspensión vigente.",
      nota: "Permite abrir el procedimiento de despido, con al menos 6 días naturales para defenderte. Abrirlo todavía no decide nada. [[57]]" },
  ] satisfies readonly Escalon[],
  escaleraRef: "[[19.2]]",
  noSonDespido: "Para llegar a eso tienen que constar en tu legajo, entregadas, la amonestación y las dos suspensiones; la conducta tiene que haber seguido pese a ellas; y tiene que cumplirse el procedimiento completo con tu descargo. [[19.6 · 57.10]]",
  enDynamic: "Ahí ves cuántas tardanzas llevas en el mes y a partir de cuántas la empresa podría actuar. Contarlas no es sancionar: eso lo decide una persona.",
} as const;

export const INASISTENCIAS = {
  bajada: "Es no venir un día en que, según tu turno o tu horario, te tocaba trabajar. Es injustificada cuando no hay una causa acreditada. [[20.1]]",
  noSon: [
    "Descanso semanal, feriados y días sin jornada programada.",
    "Vacaciones, descanso médico, permisos y licencias.",
    "Suspensión ya cumplida y descanso sustitutorio.",
    "Ausencias por hechos de violencia. [[22]]",
    "Si hay duda sobre si te tocaba venir, el día no se cuenta. [[20.8]]",
  ],
  noSonRef: "[[20.2]]",
  avisaYJustifica: [
    "**Avisa** a tu líder de equipo el mismo día, antes de que empiece tu jornada. Si no pudiste avisar, igual puedes justificar después. [[20.3]]",
    "**Justifica** dentro de las **48 horas desde que vuelves**, ante tu líder de equipo o DO: certificado médico o CITT, constancia de atención, denuncia o citación de autoridad. [[20.4]]",
  ],
  olvidar: "El día se reconstruye con la información que haya, y un día trabajado se paga aunque no haya quedado marcado. Olvidarlo puede ser una falta leve. [[20.6 · 53.1]]",
  salirAntes: "Salir antes sin permiso no es inasistencia: esas horas no se pagan. Si sales dentro de los 15 minutos previos a tu hora de salida, no se registra como incidencia. [[20.7]]",
  pago: "En el pago pasa lo mismo que con las tardanzas: el día no trabajado no suma horas y **no hay descuento adicional**, tampoco del descanso semanal. [[20.5]]",
  conteo: "Aquí no se cuenta por mes. Lo que decide el escalón es si tienes un antecedente vigente por inasistencias.",
  escalera: [
    { n: 1, medida: "Amonestación escrita", tono: "informativo", cuando: "**1 inasistencia injustificada**, sin antecedente vigente." },
    { n: 2, medida: "Suspensión", duracion: "1 a 2 días", tono: "advertencia",
      cuando: "**1 inasistencia injustificada nueva**, en cualquier mes, si tienes una amonestación vigente." },
    { n: 3, medida: "Segunda suspensión", duracion: "2 a 3 días", tono: "advertencia",
      cuando: "**1 inasistencia injustificada nueva**, si tienes una suspensión vigente.", nota: "Siempre más larga que la primera." },
  ] satisfies readonly Escalon[],
  escaleraRef: "[[21.2]]",
  graves: [
    { situacion: "Más de 3 días seguidos sin justificar (abandono)", desde: "Desde el 4.º día" },
    { situacion: "Más de 5 inasistencias en 30 días calendario", desde: "Desde la 6.ª" },
    { situacion: "Más de 15 inasistencias en 180 días calendario", desde: "Desde la 16.ª" },
  ],
  gravesRef: "[[21.5]]",
  gravesDespues: "Solo en estos casos se puede abrir una imputación de cargos por inasistencias. Antes de imputar abandono, la empresa te envía a tu domicilio un requerimiento escrito para que vuelvas o justifiques, con al menos 2 días hábiles desde que lo recibes. Y siempre tienes al menos 6 días naturales para defenderte. [[21.6 · 57.9]]",
} as const;

export interface Gravedad { nombre: string; maximo: string; tono: Tono; ejemplos: readonly string[]; ref: string }

export const CONDUCTA = {
  bajada: "Solo se sanciona lo que está escrito en el catálogo del Reglamento. Lo que no está ahí no se sanciona, salvo que sea una falta grave de la ley. [[52.3 · 53.4]]",
  catalogo: [
    { nombre: "Leves", maximo: "Como máximo, amonestación escrita", tono: "informativo", ref: "[[53.1]]", ejemplos: [
      "Olvidar marcar, si el día se puede reconstruir.",
      "Descuido en el orden o la limpieza del puesto, el taller o la sala de ventas.",
      "No cumplir el estándar de presentación personal.",
      "Usar el celular o redes sociales durante la atención a una clienta, sin perjuicio para el servicio.",
      "No mantener al día tus datos de contacto o de cuenta.",
      "Ausentarte del puesto sin avisar; salir antes sin permiso, si no es reiterado.",
    ] },
    { nombre: "Significativas", maximo: "Amonestación, o suspensión si ya hay antecedente. Nunca despido.", tono: "advertencia", ref: "[[53.2]]", ejemplos: [
      "3 o más amonestaciones por faltas leves en 12 meses.",
      "Tardanzas e inasistencias, según sus escaleras.",
      "No marcar de forma reiterada.",
      "Desobedecer una instrucción lícita de trabajo sin una causa razonable.",
      "No seguir el procedimiento de caja, inventario o cierre, incluido un faltante sin apropiación.",
      "Trato descortés a una clienta, una compañera o un tercero.",
      "Faltar sin causa a una capacitación obligatoria; no reportar un accidente.",
    ] },
    { nombre: "Graves", maximo: "Solo las de la ley. Suspensión o despido, siempre con procedimiento.", tono: "alerta", ref: "[[53.3]]", ejemplos: [
      "Marcar por otra persona o dejar que marquen por ti; manipular el terminal o los registros.",
      "Poner datos falsos en una justificación, una corrección o un descargo.",
      "Disponer de producto o de dinero de caja sin autorización.",
      "Entregar a terceros listas de clientas, precios, diseños, moldes o patrones.",
      "Agresión física o verbal a una compañera o a quien representa a la empresa.",
      "Hostigamiento sexual.",
    ] },
  ] satisfies readonly Gravedad[],
  reincidencia: "**Reincidencia:** repetir la misma falta, o una muy parecida, dentro de los 12 meses desde que recibiste la anterior permite subir un escalón. Solo agrava lo que tiene relación: una amonestación por presentación personal no sirve para suspender por tardanzas. [[56.4 · 56.5]]",
  saltar: "**Saltar un escalón** solo es posible cuando la falta es tan grave que lo justifica por sí sola, y el motivo tiene que quedar escrito en el documento que te entregan. [[54.7]]",
  competencia: [
    { medida: "Llamada de atención y amonestación escrita", quien: "Tu líder de equipo (solo para quienes son de su sede), DO o Gerencia General" },
    { medida: "Suspensión sin goce de haber", quien: "DO o Gerencia General. Tu líder de equipo puede proponerla, pero la impone DO." },
    { medida: "Imputación de cargos", quien: "DO o Gerencia General" },
    { medida: "Carta de despido", quien: "Solo Gerencia General" },
  ],
  competenciaRef: "[[54.4]]",
  competenciaNota: "Un documento firmado por quien no tenía esa facultad no tiene ningún efecto y no cuenta para nada.",
  suspension: [
    "Se comunica por escrito, con los hechos, el criterio usado y **los días concretos** en que se cumple.",
    "**Nunca** cae en tu descanso semanal, en un feriado ni en tus vacaciones.",
    "Topes: 3 días por una falta significativa; 8 por una falta grave que no termina en despido; **15 días en total en 12 meses**.",
    "Esos días no se pagan y no hay otro descuento. Tampoco cuentan como inasistencia.",
    "En CAYLA no existen como castigo: multas, descuentos, traslado de sede, cambio de turno ni rebaja de categoría o de funciones.",
  ],
  suspensionRef: "[[54.5 · 54.6]]",
} as const;

export interface PasoCargos { titulo: string; plazo?: string; parrafos: readonly string[] }

export const CARGOS = {
  bajada: "Esto es lo que pasa, en orden, antes de una amonestación o una suspensión. Cada paso queda registrado con su fecha y su hora. [[55]]",
  pasos: [
    { titulo: "Dynamic detecta un umbral", parrafos: [
      "Le avisa a tu líder de equipo o a DO. Eso no es sanción ni acusación, y no obliga a sancionar. [[52.9]]",
    ] },
    { titulo: "Ves el detalle antes que nada", parrafos: [
      "Antes de emitir cualquier documento te muestran las fechas, horas y minutos que lo motivan. Si algo está mal, pide la corrección o justifica. [[19.5 · 55.8]]",
      "Si dices que una marca no la hiciste tú, esa marca sola no basta: la empresa necesita otra prueba. [[16.3]]",
    ] },
    { titulo: "Te comunican los cargos en tu Info", plazo: "Info › Disciplina", parrafos: [
      "Ahí ves los hechos, la falta que se te atribuye y la medida que podría corresponder. Toca **«Confirmo que los recibí»**.",
      "Confirmar no es aceptar: solo deja constancia de que te llegaron. **El plazo empieza cuando te los comunican**, no cuando confirmas.",
    ] },
    { titulo: "Das tu versión, si quieres", plazo: "Al menos 2 días hábiles", parrafos: [
      "Después de confirmar que los recibiste, escríbela en la misma pantalla, o dila en persona y que quede un acta. Lo que envías ya no se cambia, pero puedes enviar otro escrito mientras el plazo siga abierto.",
      "Si no envías descargo, eso no significa que aceptas los cargos.",
    ] },
    { titulo: "Se lee y se valora por escrito", parrafos: [
      "Recién al vencer el plazo, la persona que decide deja escrito si acoge tu descargo completo, en parte, o por qué no. Esa valoración va en el documento final y en tu legajo. [[19.3 · 55.2]]",
    ] },
    { titulo: "Si se decide una medida, te la entregan", plazo: "Hasta 5 días hábiles", parrafos: [
      "Después de firmada, te la tienen que entregar pronto [[19.4]]. Llega a tu Info: eliges **«Firmar y recibir»** o **«Recibir sin firmar»**. Abrirla no cuenta como recibirla.",
      "También puede entregarse en papel, con cargo de recepción; si no quieres firmar el papel, queda un acta con una testigo [[55.4]]. En cualquier caso, recibir no es aceptar.",
    ] },
    { titulo: "Desde que la recibes corren dos relojes", parrafos: [
      "Uno de **12 meses**, como antecedente; y otro de **5 días hábiles**, para pedir por escrito su reconsideración a Gerencia General, que responde en 10 días hábiles como máximo. [[55.5 · 56.1]]",
    ] },
  ] satisfies readonly PasoCargos[],
  comoSeCuentan: "Días hábiles son **de lunes a viernes, sin feriados**. Sábado y domingo no cuentan, aunque en tu sede se trabaje. El plazo vence a las **23:59 del segundo día hábil**, hora de Perú. Dynamic te muestra la fecha y la hora exactas en tus cargos.",
  feriado: "Si en medio hay un feriado, ese día tampoco cuenta y el plazo se corre un día más.",
  antecedente: "En tu Info, cada documento dice hasta qué fecha cuenta como antecedente. [[56.1 · 56.7]]",
  imputacionRef: "[[57]]",
  imputacion: [
    "La carta se entrega en papel, no por tu Info.",
    "Tienes **al menos 6 días naturales** (incluye fines de semana y feriados) desde que la recibes para presentar tu descargo.",
    "Con la carta te entregan copia de tus registros y de los documentos en que se basa.",
    "Pueden pedirte que no vayas a trabajar durante el trámite, solo por escrito y pagándote todo.",
    "Si no presentas descargo, no se toma como que aceptas. La empresa igual tiene que probar la falta.",
    "El resultado puede ser archivar el caso, una sanción menor o el despido. La causa de la carta no puede cambiar después.",
    "La carta de despido la firma solo Gerencia General. Puedes impugnarla ante el Poder Judicial dentro de 30 días naturales. [[57.11]]",
  ],
} as const;

export interface Plazo { que: string; plazo: string; desde: string; ref: string }

export const PLAZOS: readonly { grupo: string; filas: readonly Plazo[] }[] = [
  { grupo: "Tú haces algo", filas: [
    { que: "Avisar que no vas a ir", plazo: "El mismo día", desde: "Antes de que empiece tu jornada", ref: "[[20.3]]" },
    { que: "Justificar una tardanza o inasistencia", plazo: "48 horas", desde: "Desde que vuelves al trabajo", ref: "[[18.2 · 20.4]]" },
    { que: "Si faltas varios días, comunicar el motivo", plazo: "3.er día hábil", desde: "Desde que empezó la ausencia", ref: "[[57.9]]" },
    { que: "Justificar por hechos de violencia (ante DO, con reserva)", plazo: "5 días hábiles", desde: "Desde que vuelves. Después también se admite.", ref: "[[22.2]]" },
    { que: "Pedir que corrijan un marcaje", plazo: "5 días hábiles", desde: "Desde el hecho, o antes del cierre de planilla si es más tarde", ref: "[[16.6]]" },
  ] },
  { grupo: "Te defiendes", filas: [
    { que: "Descargo ante amonestación o suspensión", plazo: "2 días hábiles", desde: "Desde que te comunican los cargos", ref: "[[55.2]]" },
    { que: "Descargo ante imputación de cargos", plazo: "6 días naturales", desde: "Desde que recibes la carta", ref: "[[57.2]]" },
    { que: "Volver o justificar ante un requerimiento por abandono", plazo: "2 días hábiles", desde: "Desde que lo recibes", ref: "[[57.9]]" },
  ] },
  { grupo: "La empresa responde", filas: [
    { que: "Revisar contigo una diferencia de más de 3 horas", plazo: "5 días hábiles", desde: "Desde ese día", ref: "[[17.5]]" },
    { que: "Entregarte una medida ya firmada", plazo: "5 días hábiles", desde: "Desde la firma", ref: "[[19.4]]" },
    { que: "Responder tu reconsideración", plazo: "10 días hábiles", desde: "Desde que la pides", ref: "[[55.5]]" },
  ] },
  { grupo: "Después de una medida", filas: [
    { que: "Pedir reconsideración a Gerencia General", plazo: "5 días hábiles", desde: "Desde que la recibes", ref: "[[55.5]]" },
    { que: "Impugnar una sanción ante la justicia", plazo: "30 días hábiles", desde: "Desde el día siguiente a recibirla", ref: "[[55.5]]" },
    { que: "Impugnar un despido ante la justicia", plazo: "30 días naturales", desde: "Desde el despido", ref: "[[57.11]]" },
    { que: "Una amonestación o suspensión cuenta como antecedente", plazo: "12 meses", desde: "Desde que la recibiste. Luego queda cancelada.", ref: "[[56.1 · 56.7]]" },
  ] },
  { grupo: "Cómo se cuenta", filas: [
    { que: "Escalones 1 a 3 de tardanzas", plazo: "Mes calendario", desde: "Del día 1 al último del mes, no del 29 al 28", ref: "[[19.1]]" },
    { que: "Escalón 4 de tardanzas, segunda vía", plazo: "30 días corridos", desde: "Hacia atrás desde la última tardanza", ref: "[[19.1]]" },
    { que: "Faltas graves por inasistencias", plazo: "30 y 180 días", desde: "Días calendario, como fija la ley", ref: "[[21.5]]" },
  ] },
];

export const SOBRE_LOS_PLAZOS = "Hábiles: de lunes a viernes, sin feriados. Naturales: todos los días seguidos.";

export const SOBRE_LA_RECONSIDERACION =
  "Pedir reconsideración es voluntario. No detiene la sanción, salvo que Gerencia General lo disponga, y no detiene ni reemplaza el plazo para ir a la Autoridad Inspectiva de Trabajo o al Poder Judicial. [[55.5]]";

export const GARANTIAS: readonly Bloque[] = [
  { titulo: "La duda te favorece.", texto: "Probar la falta le toca a la empresa. Si hay una duda que no se puede resolver, se resuelve a tu favor. [[52.8]]" },
  { titulo: "Puedes ver tu registro.", texto: "Pide ver tus marcas y una copia a tu líder de equipo o a DO, sin dar explicaciones. [[16.7]]" },
  { titulo: "Una marca discutida no basta.", texto: "El terminal no tiene clave. Si dices que una marca no es tuya, hace falta otra prueba para sancionar. [[16.3]]" },
  { titulo: "Lo que se deja pasar no vuelve.", texto: "La empresa tiene que actuar sin demora. Un hecho que se dejó pasar sin razón no puede sancionarse después ni servir de antecedente. [[19.4 · 52.6]]" },
  { titulo: "Una justificación tardía también corrige.", texto: "Si se acepta después de un documento, ese día sale del documento y queda anotado en tu legajo. [[55.8]]" },
  { titulo: "Sin descargo previo, no vale.", texto: "Una amonestación o suspensión impuesta sin darte el plazo de descargo no cuenta como antecedente ni como escalón. [[55.2]]" },
  { titulo: "Solo el Reglamento que recibiste.", texto: "No se te puede sancionar con una versión del Reglamento que no conste que te entregaron. [[60.5]]" },
  { titulo: "Protección ante la violencia.", texto: "Las ausencias y tardanzas por hechos de violencia se justifican ante DO, con reserva, sin explicar más de lo necesario y sin ninguna represalia. [[22]]" },
];

export const PREGUNTAS: readonly { pregunta: string; respuesta: string }[] = [
  { pregunta: "Si firmo el memo, ¿acepto lo que dice?",
    respuesta: "No. Firmar o recibir solo deja constancia de que te llegó. Puedes firmarlo, recibirlo sin firmar y, si no estás de acuerdo, pedir su reconsideración dentro de 5 días hábiles. [[55.4 · 55.5]]" },
  { pregunta: "Si no envío descargo, ¿quiere decir que acepto?",
    respuesta: "No. Dar tu versión es un derecho, no una obligación. Si no la das, la persona que decide igual tiene que valorar el caso por escrito, y la falta la sigue teniendo que probar la empresa. [[55.2 · 57.5]]" },
  { pregunta: "¿El mes nuevo borra mis tardanzas?",
    respuesta: "El conteo del mes sí empieza en cero. Lo que no se borra es un antecedente que ya te entregaron: sigue vigente sus 12 meses, y por eso con una amonestación vigente bastan 2 tardanzas en un mes para el siguiente escalón. [[19.2 · 19.4]]" },
  { pregunta: "¿Me pueden descontar plata por llegar tarde?",
    respuesta: "No como castigo. Solo no se pagan los minutos que no trabajaste, porque en CAYLA se pagan las horas trabajadas. No hay multas ni descuentos extra. [[17.6 · 54.6]]" },
  { pregunta: "¿Me pueden cambiar de sede o de turno como sanción?",
    respuesta: "No. Un traslado, un cambio de turno o una rebaja con finalidad de castigo están prohibidos en el Reglamento. [[54.6]]" },
  { pregunta: "¿Y si esa marca no la hice yo?",
    respuesta: "Dilo. Como el terminal no tiene clave, una marca discutida no puede sostener sola una medida: hace falta otra prueba. Mientras no se corrobore, esa tardanza no se cuenta. [[16.3 · 19.5]]" },
  { pregunta: "¿Me pueden suspender en mi día de descanso?",
    respuesta: "No. Una suspensión nunca cae en tu descanso semanal, en un feriado ni en tus vacaciones, y se te comunica con los días exactos. [[54.5]]" },
  { pregunta: "¿Dónde veo lo que consta de mí?",
    respuesta: "En **Info › Disciplina**: los documentos que te entregaron, hasta cuándo cuenta cada uno, los cargos que te comuniquen y cómo vas este mes. Si te entregaron algo en papel, ahí te pedirá «Lo leí»: leer no es aceptar. El Reglamento completo está en **Publicaciones › Normas**." },
  { pregunta: "Soy practicante o doy servicios por recibo por honorarios. ¿Esto me aplica?",
    respuesta: "No de la misma manera. El Reglamento se aplica a quienes tienen contrato de trabajo, y las prácticas y los servicios por honorarios tienen sus propias reglas [[2.5 · 2.6]]. Pregúntale a Desarrollo Organizacional qué te aplica a ti." },
];

/** Todos los textos de la guía en una lista, para las pruebas (citas y vocabulario). */
export function todosLosTextos(): string[] {
  const t: string[] = [];
  const va = (x: unknown): void => {
    if (typeof x === "string") t.push(x);
    else if (Array.isArray(x)) x.forEach(va);
    else if (x && typeof x === "object") Object.values(x).forEach(va);
  };
  va([ESENCIAL, ESCALA, SOBRE_LA_ESCALA, TARDANZAS, INASISTENCIAS, CONDUCTA, CARGOS, PLAZOS, SOBRE_LOS_PLAZOS,
    SOBRE_LA_RECONSIDERACION, GARANTIAS, PREGUNTAS]);
  return t;
}

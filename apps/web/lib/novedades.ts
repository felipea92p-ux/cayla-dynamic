import { hoyLima, puedeVerNovedad, type AudienciaNovedad } from "@cayla-dynamic/shared";

// ============================================================================
// Novedades del sistema — lo que mejoró en Dynamic, dicho para quien lo usa.
// ============================================================================
//
// QUÉ PROMETE
//   Que cada mejora que alguien del equipo nota al usar el sistema quede
//   escrita aquí, en palabras de quien usa la pantalla, y aparezca en
//   /admin/anuncios. Es una lista escrita a mano: nadie la genera sola.
//
// QUÉ ASUME
//   Que quien fusiona un cambio visible agrega su entrada EN EL MISMO PULL
//   REQUEST. Nada lo obliga —ver «SE ROMPE SI»—; la regla está en CLAUDE.md.
//
// POR QUÉ ESTÁ EN EL CÓDIGO Y NO EN LA TABLA `anuncios`
//   · Sale en el mismo despliegue que la mejora que cuenta, ni antes ni
//     después. Una fila en `anuncios` la pega Felipe a mano, y la migración
//     se pega ANTES de fusionar: el aviso «ya puedes hacer X» estaría en
//     pantalla mientras X todavía no existe.
//   · No cuesta un SQL a producción por cada texto.
//   · `anuncios.publicado_por` exige una persona real: las novedades no las
//     firma nadie de DO, y meterlas ahí mezclaría la voz de la empresa con la
//     del sistema. Por eso van en una sección aparte y con su propia etiqueta.
//
// POR QUÉ NO SE GENERAN DESDE LOS COMMITS
//   Se midió el 2026-09-19: de los 169 commits sin fusiones desde el 15 de
//   septiembre, 42 son «La consulta de qué falta pegar se pone al día sola» y
//   otros 13 son renumeraciones y rescates de migraciones — sin contar pruebas,
//   lint ni documentos. Es bastidores. Lo que el equipo llegó a notar son unas
//   pocas mejoras, y decidir cuáles es criterio de una persona, no de un script.
//
// QUÉ VA Y QUÉ NO VA
//   Va: lo que alguien nota —una pantalla que dice algo nuevo, un error que
//   dejó de pasar, un botón que antes no había—. Se cuenta qué cambió y por
//   qué le sirve a quien lo lee, nunca cómo se hizo.
//   No va: refactores, pruebas, migraciones internas, renumeraciones.
//
//   NUNCA una regla de pago, un descuento, una tardanza o algo disciplinario
//   como forma de avisar. «Leído» en Anuncios es un marcador liviano, sin
//   acuse (ver el encabezado de la 0351): no prueba que nadie se enteró, y
//   la ley exige poder probarlo. Lo que cambie cuánto se le paga a alguien
//   viaja por la Política salarial, que está versionada y se acusa; aquí, como
//   mucho, se avisa que hay algo nuevo que leer allá.
//
//   Sin nombres, sin montos, sin documentos. La audiencia es relevancia, no
//   confidencialidad: este archivo baja al navegador de todo el mundo.
//
// CÓMO SE AGREGA
//   Una entrada nueva ARRIBA de la lista, en el mismo PR que el cambio.
//   `id` = `AAAA-MM-DD-lo-que-cambio`, único y para siempre. `fecha` = el día
//   en que se fusiona (main se publica sola, así que es el día en que llega a
//   producción); si el PR se fusiona otro día, se corrige antes de fusionar.
//   Una entrada publicada no se edita ni se borra: si algo salió mal contado,
//   se agrega otra que lo corrija —el mismo criterio de `anuncios`, que se
//   anulan y no se editan.
//
// «NUEVA» Y «ENTENDIDA»
//   Una novedad está PENDIENTE para una persona si es de los últimos
//   `DIAS_COMO_NUEVA` días Y ella no la marcó como entendida. La marca vive en
//   `novedades_vistas` (0480), por persona y en la base, no en el navegador: en
//   un equipo compartido un «visto» del navegador le ocultaría a la segunda
//   persona lo que nunca vio (la objeción que descartó `localStorage` en la
//   Bandeja, ver `bandeja-mia.ts`).
//   La ventana de días sigue a propósito: sin ella, el día que esto sale cada
//   persona tendría toda la lista pendiente, y quien vuelve de vacaciones
//   encontraría un mes de avisos viejos empujando lo importante.
//
//   Hasta el 2026-09-19 «Nueva» era solo por fecha y no se guardaba nada. Cambió
//   cuando se pidió mostrarlas en «Lo mío», la primera pantalla de cada
//   persona: una tarjeta que ahí no se puede descartar se aprende a ignorar.
//
//   Si la base no responde, o la 0480 aún no está pegada: «Lo mío» calla las
//   novedades —mostrar algo que no se puede descartar es peor que no mostrarlo—
//   y Anuncios las muestra por fecha, sin botón. Ninguna se pierde: siempre
//   quedan en Anuncios.
//
// EL PRIMER PÁRRAFO TIENE QUE VALER SOLO
//   «Lo mío» muestra únicamente el primer párrafo de `queMejoro` (lo demás
//   queda en Anuncios). Si lo que hace útil a la novedad está en el segundo,
//   en «Lo mío» no se ve.
//
// SE ROMPE SI
//   Se fusiona un cambio visible sin su entrada: la sección envejece y, sin
//   decirlo, le cuenta al equipo que nada mejora. Si alguien escribe aquí una
//   regla de pago pensando que «ya se avisó». Y si el formato del id cambia en
//   un solo lado —esta lista o el `check` de `novedades_vistas`—: una novedad
//   legítima dejaría de poder marcarse; `tests/novedades.test.ts` compara las dos.
// ============================================================================

export interface Novedad {
  /**
   * `AAAA-MM-DD-lo-que-cambio`: solo minúsculas, cifras y guiones, hasta 100
   * caracteres (`FORMATO_ID_NOVEDAD`). Único y estable: nunca se reutiliza ni se cambia.
   */
  id: string;
  /** Día de Lima (`2026-09-18`) en que llegó a producción. */
  fecha: string;
  titulo: string;
  /** Qué mejoró, en lenguaje de quien usa la pantalla. Párrafos separados por línea en blanco. */
  queMejoro: string;
  audiencia: AudienciaNovedad;
}

/** Cuántos días una novedad se muestra como «Nueva» desde su fecha. */
export const DIAS_COMO_NUEVA = 14;

/**
 * La forma de un `id`. Es el MISMO patrón del `check` de `novedades_vistas`
 * (0480): la base no conoce la lista, solo rechaza lo que no tiene forma de id.
 */
export const FORMATO_ID_NOVEDAD = /^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9]+(-[a-z0-9]+)*$/;
export const LARGO_MAXIMO_ID_NOVEDAD = 100;

// La más reciente primero. Ver «CÓMO SE AGREGA» arriba.
export const NOVEDADES: readonly Novedad[] = [
  {
    id: "2026-09-28-declaracion-de-ruta-pasaje-y-taxi",
    fecha: "2026-09-28",
    titulo: "Tu declaración de ruta vuelve a preguntar el pasaje y el taxi",
    queMejoro:
      "La declaración de ruta que firmas desde Info tenía menos puntos que el papel de siempre: decía dónde vives " +
      "y cuántos medios de transporte usas, pero no cuánto cuesta cada pasaje ni si a veces tienes que tomar taxi. " +
      "Ahora tiene los cinco puntos del papel: escribes el costo de tu pasaje, el gasto diario se calcula " +
      "solo, y si según tu turno a veces usas taxi, anotas cuánto cuesta y cuántas veces por semana.\n\n" +
      "El taxi es opcional: si no lo usas, déjalo en blanco. Si ya firmaste tu declaración, no tienes que volver a " +
      "hacerlo: sigue vigente tal como la firmaste.",
    audiencia: "todos",
  },
  {
    id: "2026-09-28-reportes-en-info",
    fecha: "2026-09-28",
    titulo: "Nuevo en Info: «Reportes», para contar algo o proponer una mejora",
    queMejoro:
      "En Info hay una sección nueva, «Reportes». Ahí puedes contar algo que pasó con el equipo, con la empresa o con una clienta, proponer una idea de mejora o hacerle una consulta a tu líder, y ver en qué va y qué te respondieron. " +
      "Lo lee solo quien lo gestiona, y antes de enviarlo la pantalla te dice quiénes lo van a leer.\n\n" +
      "Si es algo de tipo sexual, o si hay un riesgo para alguien ahora, márcalo arriba del formulario: va por un camino aparte y con plazos propios, y tu líder no lo ve. " +
      "La persona reportada nunca sabe quién reportó, y cada reporte tiene una fecha límite de respuesta escrita, que ves apenas lo envías.",
    audiencia: "todos",
  },
  {
    id: "2026-09-27-constancia-practicante-descanso-y-subvencion",
    fecha: "2026-09-27",
    titulo: "Tu constancia de subvención ya muestra tu descanso y tu subvención semestral",
    queMejoro:
      "Tu constancia de subvención ya mostraba lo que ganas por tus horas y tu movilidad, pero le faltaban " +
      "los otros dos beneficios que la Ley 28518 (art. 42) también te da: el descanso de 15 días al cumplir " +
      "12 meses continuos de convenio, y una media subvención adicional por cada 6 meses continuos.\n\n" +
      "Ahora, si ya tienes algo acumulado de cualquiera de los dos, lo ves en tu constancia, junto al aporte " +
      "de EsSalud. Sigue siendo algo que pides a Desarrollo Organizacional cuando corresponda — esto solo " +
      "hace que puedas verlo antes de pedirlo.",
    audiencia: "todos",
  },
  {
    id: "2026-09-27-boleta-feriados-especifica-fecha",
    fecha: "2026-09-27",
    titulo: "Tu boleta ahora dice qué feriado se pagó, no solo el monto",
    queMejoro:
      "La línea «Feriados» de tu boleta mostraba solo el monto, sin decir de qué feriado salía ni con qué horas se calculó. " +
      "Ahora, debajo del monto, aparece la fecha de cada feriado pagado con las horas trabajadas y las horas proporcionales que lo componen.\n\n" +
      "El total no cambia: es la misma cifra de siempre, ahora explicada para que puedas comprobarla sin preguntar.",
    audiencia: "todos",
  },
  {
    id: "2026-09-20-dashboard-feriado-sin-turnos-pregunta",
    fecha: "2026-09-20",
    titulo: "Un feriado sin turnos ya no sale en rojo: el Dashboard pregunta si la sede abre",
    queMejoro:
      "En un feriado en que nadie de la sede ha marcado y nadie armó turnos, el Dashboard decía en rojo «Sin marcajes» y «Cobertura insuficiente», y cada persona salía como «Sin marcar · le tocaba 08:00». Pero un feriado puede abrir o no, y el sistema no lo sabe: era una alarma falsa cuando la sede cerraba. " +
      "Ahora sale en ámbar «Feriado · ¿abre hoy?», y cada persona dice «Feriado · le tocaba 08:00», sin enlace para corregir.\n\n" +
      "Si la sede abre, arma sus turnos de ese día en Turnos: con un turno armado el aviso vuelve a ser el de siempre. Y apenas alguien marca la entrada, el Dashboard entiende que la sede abrió y mide su meta como cualquier otro día. " +
      "La Hoja de sede impresa también deja de imprimir «faltan 1» en rojo un feriado sin turnos: dice «Feriado» y que no se sabe si la sede abre.",
    audiencia: "panel",
  },
  {
    id: "2026-09-20-hoja-de-sede-periodo-cerrado-sin-hoy",
    fecha: "2026-09-20",
    titulo: "La Hoja de sede de un periodo cerrado ya no trae un «Hoy» que no le corresponde",
    queMejoro:
      "Al armar la hoja de un periodo que ya terminó —por ejemplo el del 29 al 28 que se archiva—, el recuadro «Hoy» decía «Nadie está trabajando en este momento» y pintaba en rojo la cobertura, con un «faltan» aunque nadie faltara. " +
      "Eran ceros inventados: la hoja solo trae los días del periodo elegido y hoy no estaba entre ellos, y ese rojo quedaba escrito en un papel que se firma y se archiva.\n\n" +
      "Ahora, si el periodo termina antes de hoy, la hoja no dibuja el recuadro «Hoy» y describe solo el periodo; en pantalla una línea lo explica. " +
      "Para ver quién está en piso ahora, deja «Hasta» en hoy o abre el Dashboard.",
    audiencia: "panel",
  },
  {
    id: "2026-09-20-dashboard-sede-sin-turnos-hoy",
    fecha: "2026-09-20",
    titulo: "Un día en que la sede no tiene turnos ya no se lee como una falla",
    queMejoro:
      "Un domingo, las sedes sin turnos aparecían como «Sin meta configurada» —como si faltara configurar algo— y Central salía en rojo con «Cobertura insuficiente» aunque a nadie le tocaba trabajar. " +
      "Ahora el Dashboard pinta en gris «Sin turnos» a la sede sin turnos y con meta 0, la deja al final de la lista y ya no muestra recuadros de ceros. «Sin meta configurada» pasa a «Sin meta hoy».\n\n" +
      "Si una sede tiene meta para hoy y sus horarios y turnos dicen que nadie trabaja, sale en ámbar como «Meta sin turnos», porque los dos datos se contradicen. " +
      "Si no abre ese día de la semana, pon en 0 su meta en Turnos (vale para todos los domingos, por ejemplo); si abre, arma sus turnos. " +
      "Ya no cuenta como «bajo la meta»: a nadie le tocaba venir.\n\n" +
      "Lo mismo vale en otras pantallas: Incidencias ya no avisa «Déficit de líderes» un día en que a nadie de la sede le tocaba trabajar, la Hoja de sede impresa ya no dice «faltan 1» en rojo por eso, y Turnos dice «Sin turnos» en vez de «sin operativas programadas» cuando la meta de ese día es 0. " +
      "Además, «Sedes bajo la meta» dice cuántas sedes se están midiendo hoy («de 2 que se miden hoy»).",
    audiencia: "panel",
  },
  {
    id: "2026-09-19-incidencias-dice-lo-que-no-pudo-mirar",
    fecha: "2026-09-19",
    titulo: "Incidencias avisa cuando no pudo mirar algo, en vez de decir «todo revisado»",
    queMejoro:
      "Antes, si a Incidencias le fallaba una lectura —por ejemplo la de las faltas—, la pantalla podía decir «Todo revisado» sin haber mirado eso. " +
      "Ahora dice qué no pudo comprobar y te pide reintentar antes de dar el periodo por revisado.\n\n" +
      "También cambió: «Marcar como revisadas» en lote ahora te muestra la lista de casos y pide confirmación; en el celular puedes elegir los casos uno por uno; " +
      "el «Déficit de líderes» de Central deja de aparecer cuando hay un administrador a cargo; la sede se lee «Taller · Lima» o «Tienda · Lima», no solo «LIM»; " +
      "y las horas del rastro de un caso salen en hora de Lima.",
    audiencia: "panel",
  },
  {
    id: "2026-09-19-boletas-de-pago-en-tu-cuenta",
    fecha: "2026-09-19",
    titulo: "Ahora puedes ver y guardar tus boletas de pago en Dynamic",
    queMejoro:
      "Desarrollo Organizacional sube la boleta de pago que entrega el contador, y tú la ves y la guardas en «Boletas», dentro de Lo mío. " +
      "Cuando hay una nueva, te aparece el aviso en tu Bandeja y un número junto a «Boletas».\n\n" +
      "Al abrirla puedes pulsar «Confirmar que la recibí»: así queda anotado que la tienes. " +
      "Si algo de tu boleta no cuadra, avisa a Desarrollo Organizacional.",
    audiencia: "todos",
  },
  {
    id: "2026-09-19-correcciones-historial-y-celular",
    fecha: "2026-09-19",
    titulo: "Correcciones: el historial cuenta lo que pasó, y se usa desde el celular",
    queMejoro:
      "El historial de cada persona ahora muestra primero sus correcciones de marcajes, con nombres claros: un cambio de tipo de marca o la confirmación de una salida del auto-cierre ya no aparecen como «otro sistema». Los cambios de horario, contrato o educación siguen ahí, a un toque en «Todo».\n\n" +
      "Cuando una marca que el terminal no pudo registrar se resuelve, el historial dice cómo terminó: se registró con su hora original, o se declaró improcedente.\n\n" +
      "Si algo no se pudo consultar al abrir la pantalla, ahora se avisa con un botón para reintentar, en vez de mostrar listas vacías que se leen como «no hay nada pendiente». Y en el celular la lista de personas y el día abierto ya no se pelean el espacio: se ve una cosa a la vez.",
    audiencia: "panel",
  },
  {
    id: "2026-09-19-anuncios-cuenta-que-mejora",
    fecha: "2026-09-19",
    titulo: "Anuncios ahora también cuenta qué mejora en el sistema",
    queMejoro:
      "Cada vez que Dynamic cambia en algo que se nota al usarlo, lo explicamos en las novedades del sistema, en palabras simples: qué cambió y por qué te sirve.\n\n" +
      "Las encuentras siempre en Anuncios, aparte de los comunicados de Desarrollo Organizacional para que no se confundan. Lo que cambió en los últimos días ya está listado.",
    audiencia: "todos",
  },
  {
    id: "2026-09-18-lider-de-equipo",
    fecha: "2026-09-18",
    titulo: "«Líder de equipo» reemplaza a «encargada» en las pantallas",
    queMejoro:
      "Quien lidera el equipo de una sede tenía dos nombres según la pantalla: en unas decía «líder de equipo» y en otras «encargada». " +
      "Ahora todas dicen «líder de equipo» (o «líder», en los contadores cortos).\n\n" +
      "No cambia el trabajo ni los permisos de nadie, solo la palabra.",
    audiencia: "todos",
  },
  {
    id: "2026-09-18-dashboard-pausa-aparte",
    fecha: "2026-09-18",
    titulo: "El Dashboard separa a quien está en pausa de quien está trabajando",
    queMejoro:
      "Antes, quien salía a refrigerio o a hacer un trámite seguía contando como «trabajando ahora», y el Dashboard podía decir «14 trabajando» con nueve de ellas fuera del piso. " +
      "Ahora «trabajando» cuenta solo a quien está en el piso, y quienes están en pausa aparecen en su propio recuadro.\n\n" +
      "Cada persona en pausa muestra desde qué hora salió y cuánto lleva fuera, y quien lleva más tiempo va primero: así un refrigerio de 40 minutos ya no se ve igual que una salida que nadie cerró hace tres horas. " +
      "La Hoja de sede dice lo mismo, con la hora de salida.",
    audiencia: "panel",
  },
  {
    id: "2026-09-18-dashboard-sede-cerrada",
    fecha: "2026-09-18",
    titulo: "El Dashboard ya no pide meta a una sede que cerró",
    queMejoro:
      "Terminado el horario de una tienda, con todo su equipo ya retirado, el Dashboard seguía marcándola en rojo con «Faltan 8». " +
      "Ahora esa sede pasa a gris y dice «Fuera de horario». Si ya era hora de abrir y nadie llegó, sigue en rojo, como debe ser.\n\n" +
      "Y cuando una meta no se puede cumplir porque es mayor que el equipo de esa sede, la tarjeta lo dice y sugiere corregir la meta en Turnos, en vez de mostrar un faltante que nadie puede resolver.",
    audiencia: "panel",
  },
  {
    id: "2026-09-18-turnos-cobertura",
    fecha: "2026-09-18",
    titulo: "Turnos: la cobertura dice lo que realmente mide",
    queMejoro:
      "Un día con gente programada solo en áreas que no son operativas —una oficina, por ejemplo— decía «sin turnos», aunque los turnos sí estaban dibujados. " +
      "Ahora dice «sin operativas programadas», que es lo que la cobertura cuenta, y los nombres de cada fila ya no se cortan con puntos suspensivos.",
    audiencia: "panel",
  },
];

/**
 * Las novedades que le corresponden a este rol, la más reciente primero.
 * Con el mismo día, se respeta el orden en que están escritas en la lista.
 */
export function novedadesPara(
  rol: string | null | undefined,
  lista: readonly Novedad[] = NOVEDADES,
): Novedad[] {
  return lista
    .filter((n) => puedeVerNovedad(rol, n.audiencia))
    .sort((a, b) => b.fecha.localeCompare(a.fecha));
}

function diasDesde(fecha: string, hoy: string): number {
  const [a, m, d] = fecha.split("-").map(Number);
  const [ha, hm, hd] = hoy.split("-").map(Number);
  return Math.round((Date.UTC(ha, hm - 1, hd) - Date.UTC(a, m - 1, d)) / 86_400_000);
}

/** ¿Se muestra como «Nueva»? Los últimos `DIAS_COMO_NUEVA` días, sin contar el futuro. */
export function esNovedadNueva(n: Novedad, hoy: string = hoyLima()): boolean {
  const dias = diasDesde(n.fecha, hoy);
  return dias >= 0 && dias <= DIAS_COMO_NUEVA;
}

/**
 * ¿Le falta entender esta novedad a la persona? Es la ÚNICA respuesta a esa
 * pregunta: «Lo mío» y Anuncios la usan las dos, para que marcarla en una la
 * apague en la otra.
 *
 * `vistas === null` es «no sé qué entendió» (cargando, o no se pudo leer):
 * decide solo la fecha. Es el modo degradado de Anuncios; «Lo mío» ni llega a
 * preguntar en ese caso, porque calla.
 */
export function esNovedadPendiente(
  n: Novedad,
  vistas: ReadonlySet<string> | null,
  hoy: string = hoyLima(),
): boolean {
  return esNovedadNueva(n, hoy) && (vistas === null || !vistas.has(n.id));
}

/**
 * Las que a esta persona todavía le faltan: de su rol, de los últimos
 * `DIAS_COMO_NUEVA` días y sin marcar como entendidas. Más reciente primero.
 */
export function novedadesPendientes(
  rol: string | null | undefined,
  vistas: ReadonlySet<string>,
  hoy: string = hoyLima(),
  lista: readonly Novedad[] = NOVEDADES,
): Novedad[] {
  return novedadesPara(rol, lista).filter((n) => esNovedadPendiente(n, vistas, hoy));
}

/** Lo único que «Lo mío» muestra de una novedad. Ver «EL PRIMER PÁRRAFO TIENE QUE VALER SOLO». */
export function primerParrafo(n: Novedad): string {
  return n.queMejoro.split("\n\n")[0].trim();
}

/** ¿Tiene más que contar después del primer párrafo? Entonces «Lo mío» invita a leerla completa. */
export function tieneMasQueElPrimerParrafo(n: Novedad): boolean {
  return n.queMejoro.split("\n\n").filter((p) => p.trim() !== "").length > 1;
}

/**
 * `2026-09-18` → «18 set 2026». Se formatea en UTC sobre mediodía: con
 * `new Date("2026-09-18")` a secas el navegador de Lima la mostraría como el 17.
 */
export function fechaDeNovedad(fecha: string): string {
  return new Intl.DateTimeFormat("es-PE", {
    day: "numeric", month: "short", year: "numeric", timeZone: "UTC",
  }).format(new Date(`${fecha}T12:00:00Z`));
}

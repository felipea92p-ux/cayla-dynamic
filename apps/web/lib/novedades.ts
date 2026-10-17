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
    id: "2026-10-17-educacion-meses-anteriores-y-siguientes",
    fecha: "2026-10-17",
    titulo: "En Educación ahora se avanza y se retrocede por los meses",
    queMejoro:
      "La cuadrícula de constancias tiene «← Meses anteriores» y «Meses siguientes →», de seis en seis: puedes " +
      "ir al pasado y volver sin recargar la pantalla, y llegar a los meses que cubre un pago adelantado más allá " +
      "de lo que se ve al abrir.\n\n" +
      "La pantalla trae solo los meses que estás mirando y pide los demás cuando te mueves, así abre más rápido " +
      "aunque haya mucha gente. Mientras un mes llega, sus casillas esperan; si no se pudo traer, se ven con «?» " +
      "y arriba aparece «Reintentar».",
    audiencia: "do",
  },
  {
    id: "2026-10-17-tu-boleta-de-pago-se-firma-desde-dynamic",
    fecha: "2026-10-17",
    titulo: "Tu boleta de pago ahora se firma desde Dynamic",
    queMejoro:
      "Cuando Desarrollo Organizacional publica tu boleta, la abres en «Boletas» y la firmas ahí mismo con la firma " +
      "que ya tienes guardada en tu perfil. Si todavía no tienes una, la creas en ese momento, una sola vez. " +
      "Ya no hace falta firmar un papel.\n\n" +
      "«Firmar» se enciende cuando abres la boleta, y te pide una segunda confirmación antes de quedar firmada. " +
      "Tu firma queda copiada en esa boleta con la fecha y la hora: si más adelante cambias tu firma, las boletas " +
      "que ya firmaste no cambian. Si no puedes firmar desde el sistema, avisa a Desarrollo Organizacional.",
    audiencia: "todos",
  },
  {
    id: "2026-10-17-do-anula-una-boleta-y-la-restablece-en-48-horas",
    fecha: "2026-10-17",
    titulo: "Anular una boleta de pago ahora se puede deshacer durante 48 horas",
    queMejoro:
      "Al anular una boleta ya publicada, la pantalla te muestra a quién y qué estás anulando: el nombre, la sede, " +
      "el periodo, las fechas, la boleta y su constancia de firma. Eliges un motivo de la lista (o escribes otro, de " +
      "al menos 5 letras) y marcas que es la persona correcta.\n\n" +
      "Si te equivocaste, «Restablecer» la devuelve exactamente como estaba, con su firma, durante 48 horas. Pasado " +
      "ese plazo hay que subir una boleta nueva. En «Ver boleta firmada» ves la boleta con la firma de la persona, " +
      "quién y cuándo firmó. La persona ve «En revisión» mientras tanto.",
    audiencia: "do",
  },
  {
    id: "2026-10-17-educacion-pagar-varios-meses-de-una-vez",
    fecha: "2026-10-17",
    titulo: "Si pagaste varios meses de tus estudios de una vez, súbelo una sola vez",
    queMejoro:
      "Al subir tu constancia en Educación ahora puedes elegir «Varios meses de una vez»: pones desde qué mes " +
      "hasta qué mes pagaste y el total (o lo de cada mes), y el sistema reparte los meses. Si un mes no es así, " +
      "lo corriges y escribes por qué. Desarrollo Organizacional la revisa una sola vez y no tendrás que enviar " +
      "constancia de esos meses.\n\n" +
      "También tienes «Tu historial», con todo lo que enviaste y lo que se aprobó o se rechazó, y por qué.",
    audiencia: "todos",
  },
  {
    id: "2026-10-17-educacion-en-pestanas-con-iconos-por-mes",
    fecha: "2026-10-17",
    titulo: "Educación se ordena en pestañas y cada mes se lee con un ícono",
    queMejoro:
      "Educación tiene cuatro pestañas: Constancias, Aprobadas del ciclo, Historial y Cómo funciona. En la " +
      "cuadrícula cada mes es un ícono —aprobada, por revisar, rechazada o falta— con una raya que dice si ese " +
      "mes se pagó el apoyo; al pasar el mouse sale el detalle con la miniatura del comprobante, y el mes en curso " +
      "va sombreado.\n\n" +
      "Se abre en «Solicitaron» (quienes pidieron apoyo); «Todos» suma a quienes no pidieron. Un pago de varios " +
      "meses se ve como una franja y se aprueba una sola vez. El Historial junta todo lo que pasó, por sede, " +
      "persona y fechas, con CSV.",
    audiencia: "do",
  },
  {
    id: "2026-10-17-educacion-aprobadas-del-ciclo-y-rechazar-una-aprobada",
    fecha: "2026-10-17",
    titulo: "En Educación se puede corregir una constancia aprobada por error",
    queMejoro:
      "Antes, una constancia aprobada no se podía corregir. Ahora Educación tiene la sección «Aprobadas en el ciclo de " +
      "pago»: elige un ciclo (del 29 al 28), mira a quién se aprobó y quién lo hizo, con la constancia a la vista, y " +
      "usa «Rechazar…» con el motivo de siempre o «Otro motivo» (mínimo 3 letras, sin máximo). La integrante lo lee " +
      "en su Bandeja y envía otra.\n\n" +
      "El rechazo queda en el historial del estudio, con quién la aprobó, quién la rechazó después y por qué. Antes de " +
      "confirmar, la pantalla avisa si era la única constancia aprobada de ese estudio —entonces el apoyo deja de " +
      "pagarse hasta que se apruebe otra— y no deja rechazarla si el periodo ya se pagó con ella.",
    audiencia: "do",
  },
  {
    id: "2026-10-16-el-bono-de-cumpleanos-en-practicas-va-en-la-boleta",
    fecha: "2026-10-16",
    titulo: "Si estás en prácticas, tu bono de cumpleaños va en tu boleta",
    queMejoro:
      "Tu bono de cumpleaños ahora entra a tu boleta del periodo y se paga al cierre, igual que al resto del " +
      "equipo. Es una corrección: una novedad anterior decía que a quien está en prácticas se lo transfería " +
      "Desarrollo Organizacional y que no iba en una boleta, y ya no es así.\n\n" +
      "Si ya habías pedido tu bono, no tienes que hacer nada.",
    audiencia: "todos",
  },
  {
    id: "2026-10-16-educacion-constancias-por-mes-y-por-sede",
    fecha: "2026-10-16",
    titulo: "En Educación ya se ven las constancias de cada mes, por sede, sin descargar nada",
    queMejoro:
      "La lista de Educación ahora es una cuadrícula: una fila por persona e institución, una columna por mes y, en " +
      "cada casilla, la miniatura de la constancia recibida. Un toque la abre grande —foto o PDF con todas sus hojas— " +
      "con sus datos al lado y los botones Aprobar y Rechazar, sin otra pestaña ni descargar nada. También se puede " +
      "usar desde el celular.\n\n" +
      "La sede va arriba, con el número de estudios de cada una, y las cinco tarjetas de arriba cuentan solo lo que " +
      "estás viendo: si eliges una sede o un mes, las tarjetas y la lista dicen lo mismo. Con las flechas ← → pasas de " +
      "una constancia a otra y con Esc cierras el visor. Con «Todas», cada sede tiene su " +
      "bloque con su resumen. Un guion en un mes es un mes sin constancia, no una falta: lo vencido lo sigue diciendo la " +
      "etiqueta de estado. Si una persona registró el mismo estudio dos veces, sale en una sola línea con sus meses " +
      "seguidos.\n\n" +
      "«Más filtros» suma quién estudia, el tipo de constancia, quién la revisó y un rango de fechas, y lo que eliges " +
      "queda en la dirección: puedes guardarla o pasarla para ver lo mismo. «Descargar» baja el cuadro de lo que ves " +
      "(CSV) y, si eliges un mes, un ZIP con las constancias de esa sede y ese mes.",
    audiencia: "do",
  },
  {
    id: "2026-10-16-educacion-por-grupos-y-cuadro-de-constancias",
    fecha: "2026-10-16",
    titulo: "Educación se puede ver por grupos, con quién no ha pedido nada y un cuadro de constancias",
    queMejoro:
      "En Educación hay pestañas debajo de las tarjetas: Al día, Por revisar, Por completar, Vencidas o rechazadas y " +
      "Sin solicitar. Se agrupa por el estado de la constancia, no por si el apoyo se paga, y «Sin solicitar» lista a " +
      "las personas activas que no tienen ningún apoyo ni una solicitud por revisar, con un botón para registrarles " +
      "uno.\n\n" +
      "Arriba hay dos paneles que se abren: «Cómo funciona», con la regla, el techo por rango y los plazos de la " +
      "constancia, y «Dónde están las constancias», que explica dónde se guardan, qué queda registrado y permite " +
      "descargar un cuadro (CSV) con una fila por constancia y archivo, para una auditoría. La tarjeta «Rechazadas» " +
      "ahora se llama «Constancias rechazadas» y dice «esperando a la integrante» en vez de «atender», porque a Desarrollo " +
      "Organizacional no le toca nada hasta que llegue la corregida; el historial aclara que cuenta solicitudes, no constancias.",
    audiencia: "do",
  },
  {
    id: "2026-10-16-adjuntar-comprobante-a-solicitud-de-apoyo-educativo",
    fecha: "2026-10-16",
    titulo: "Ya puedes adjuntar el comprobante a tu solicitud de apoyo educativo después de enviarla",
    queMejoro:
      "Si enviaste tu solicitud de apoyo educativo sin el comprobante, ya no tienes que retirarla y pedirla de nuevo: " +
      "en Lo mío, Educación, tu solicitud pendiente tiene un botón «Adjuntar comprobante». Desarrollo Organizacional " +
      "lo ve al revisarla, y sin él no puede aprobar.\n\n" +
      "Si te equivocaste de archivo, el mismo botón dice «Cambiar comprobante» y lo reemplaza mientras la solicitud " +
      "siga pendiente. Una vez revisada o retirada, el comprobante ya no se cambia.",
    audiencia: "todos",
  },
  {
    id: "2026-10-13-asistencia-diseno-unificado",
    fecha: "2026-10-13",
    titulo: "Asistencia de hoy se ve más ordenada: números, avisos y sedes con una sola forma",
    queMejoro:
      "Los cuatro números de arriba —trabajando ahora, tardanzas, sin marcar y sedes bajo la meta— ahora son " +
      "casillas, y el estado de cada una lo dice un punto de color junto a su nombre, no el color del número. Lo que " +
      "cuenta cada casilla no cambió: solo la forma de leerla. Si una casilla está en cero, ya no se puede abrir, " +
      "porque no tiene detalle que mostrar.\n\n" +
      "Lo mismo pasa dentro de cada sede: los recuadros «Trabajando ahora» y «En pausa» ya no se pintan de verde y " +
      "de ámbar, llevan un punto; los avisos tienen un tamaño para los de una línea y otro para los que explican; y " +
      "si un filtro no encuentra a nadie, aparece un botón para quitar los filtros. En el celular los cuatro " +
      "números van en dos filas de dos y ocupan algo más de pantalla que antes. Las tablas del panel perdieron las " +
      "franjas alternas: la fila se resalta al pasar el cursor.",
    audiencia: "panel",
  },
  {
    id: "2026-10-13-agregar-marcaje-propone-lo-que-falta",
    fecha: "2026-10-13",
    titulo: "En Correcciones, «Agregar un marcaje faltante» ya propone lo que falta",
    queMejoro:
      "Al abrir el día de alguien, el formulario ya no arranca siempre en «Entrada · 08:00». Propone el marcaje que " +
      "le falta a ese día —por ejemplo «Salida final» si ya tiene su entrada— y la hora que le tocaba según su " +
      "horario. Mientras no la cambies, la etiqueta dice «Hora · según su horario».\n\n" +
      "Revisa la hora antes de agregar: es la de su horario, no necesariamente la real. Si es hoy y todavía no llega " +
      "su hora de salida, no se propone la salida, porque puede que siga trabajando. El tipo y la hora se cambian " +
      "con un clic, como siempre.",
    audiencia: "panel",
  },
  {
    id: "2026-10-13-cumpleanos-en-info",
    fecha: "2026-10-13",
    titulo: "En tu mes de cumpleaños, Info te saluda y te deja firmar tu bono ahí mismo",
    queMejoro:
      "Desde el primer día del mes de tu cumpleaños, Info abre con un saludo del equipo —dieciséis mensajes " +
      "distintos que van cambiando— y, si te corresponde el bono de cumpleaños, con el botón para firmar tu " +
      "constancia sin buscarla en ningún menú. Antes la tarjeta del bono quedaba abajo del Resumen, y a quien " +
      "el sistema no le ofrecía el bono no le decía nada en su mes.\n\n" +
      "Y el bono ya es también para quien está en prácticas: hasta hoy el sistema se lo negaba aunque " +
      "Desarrollo Organizacional lo viera como pendiente. Quedan fuera el periodo de prueba y los contratos " +
      "de menos de una semana. A quien está en prácticas se lo transfiere Desarrollo Organizacional: no va en " +
      "una boleta.",
    audiencia: "todos",
  },
  {
    id: "2026-10-13-planilla-muestra-movilidad-y-educacion-en-su-columna",
    fecha: "2026-10-13",
    titulo: "En Planilla, la movilidad y la educación ya tienen su propia columna",
    queMejoro:
      "En la tabla de cada grupo —también la de Practicantes— ahora hay una columna «Movilidad» y otra «Educación», " +
      "con su suma al pie. Antes esos dos conceptos estaban dentro del total y solo se veían al abrir a la persona, " +
      "en «Cómo se arma su total».\n\n" +
      "Si alguien tiene la asignación por educación registrada pero le falta cargar el comprobante, la celda lo dice " +
      "(«sin comprobante») en vez de quedar en blanco. Pasa el cursor sobre un monto de movilidad para ver la tarifa por día.",
    audiencia: "do",
  },
  {
    id: "2026-10-13-ver-el-cargo-de-cumpleanos-firmado-desde-el-sistema",
    fecha: "2026-10-13",
    titulo: "En Documentación ya se puede abrir el cargo de cumpleaños firmado desde el sistema",
    queMejoro:
      "En «Cargos de cumpleaños», quien firmó su constancia desde «Lo mío» ahora tiene el botón «Ver». Antes su fila " +
      "decía «Firmado» y no había dónde abrir lo firmado: «Ver» solo existía para un papel escaneado.\n\n" +
      "Se abre la constancia con su firma y la fecha en que se firmó, y se puede imprimir o guardar como PDF. " +
      "«Subir otro» sigue en el menú ⋯ de la fila.",
    audiencia: "do",
  },
  {
    id: "2026-10-06-asistencia-de-hoy-se-ve-completa-en-el-telefono",
    fecha: "2026-10-06",
    titulo: "«Asistencia de hoy» ya se ve completa en el teléfono",
    queMejoro:
      "En el teléfono, lo primero que ves ahora es lo que importa: si hay algo urgente y los cuatro números del día " +
      "(trabajando, tardanzas, sin marcar y sedes bajo la meta), todo en la primera pantalla. Antes había que bajar " +
      "más de una pantalla de filtros y botones para llegar al primer dato.\n\n" +
      "El buscador queda arriba, y Sede, Estado y «Solo alertas» están en el botón «Filtros», que te dice cuántos tienes " +
      "activos. «Personalizar» y «Ver en Google Sheets» pasaron al menú ⋯. Cada sede muestra su estado completo con una " +
      "franja de color. Toca una cifra para ver quién es y qué cuenta exactamente. En la computadora todo sigue igual.",
    audiencia: "panel",
  },
  {
    id: "2026-10-06-el-terminal-avisa-cuando-pierde-su-vinculo",
    fecha: "2026-10-06",
    titulo: "El terminal avisa cuando la Mac de la sede pierde su vínculo",
    queMejoro:
      "Si la Mac de una sede se queda sin su vínculo con el sistema, ahora aparece una franja roja fija: «Esta Mac " +
      "perdió su vínculo: las marcas se guardan pero NO se envían». Antes nadie se enteraba, y las marcas terminaban " +
      "apartadas en Correcciones después de seis intentos.\n\n" +
      "Mientras esté así, las marcas se quedan guardadas en la Mac y salen solas al volver a vincularla; ya no se " +
      "apartan. Si ves la franja, avisa a tu líder de equipo: quien tiene las credenciales del terminal usa " +
      "«Volver a vincular» en la misma franja.",
    audiencia: "panel",
  },
  {
    id: "2026-10-06-lo-mio-tiene-una-seccion-disciplina",
    fecha: "2026-10-06",
    titulo: "«Lo mío» tiene una sección nueva: Disciplina",
    queMejoro:
      "En Seguimiento hay una sección nueva, «Disciplina», justo antes de «Historial». Ahí ves tus documentos, " +
      "de a 10 por página, y cómo vas este mes. Los memos que antes estaban en «Historial» ahora están en «Disciplina».\n\n" +
      "Si te entregaron un documento en papel, ahí puedes abrirlo y dejar constancia de que lo leíste. Leerlo no es " +
      "aceptarlo. Si no tienes nada pendiente, la sección te lo dice con un mensaje.\n\n" +
      "En el menú, un número junto a «Disciplina» te avisa cuando hay algo por leer o por recibir.",
    audiencia: "todos",
  },
  {
    id: "2026-10-06-registrar-una-falta-desde-disciplina",
    fecha: "2026-10-06",
    titulo: "Desde Disciplina se puede registrar una falta de conducta",
    queMejoro:
      "En Disciplina hay un botón nuevo, «Registrar una falta», y el mismo botón en la ficha de cada persona. Se elige " +
      "la falta por su nombre corto, con el texto del Reglamento a la vista; se cuenta qué pasó, cuándo y cuándo se " +
      "supo; y queda un borrador que sigue el trámite de siempre: comunicar, firmar y entregar.\n\n" +
      "La líder de equipo la registra para integrantes de su sede; a otra líder la registra Desarrollo Organizacional. " +
      "Desarrollo Organizacional recibe un aviso en su Bandeja, puede tomar el caso y devolverlo con un motivo que lee " +
      "la líder, y ve si la persona ya leyó lo que se le entregó en papel.",
    audiencia: "panel",
  },
  {
    id: "2026-10-06-lo-mio-volver-retrocede",
    fecha: "2026-10-06",
    titulo: "En «Lo mío», «← Volver» y «Cancelar» te devuelven a donde estabas",
    queMejoro:
      "Los botones «← Volver a Info», «← Tus reportes» y «Cancelar» ahora hacen lo mismo que «atrás»: te " +
      "devuelven a donde estabas, en vez de abrir una página más. Si desde Mis días abriste tu boleta y tocas " +
      "«← Volver a Info», regresas a Mis días, no al Resumen; y si tocas «Cancelar» al escribir un reporte y " +
      "luego usas «atrás», ya no vuelves al formulario que acabas de cerrar.\n\n" +
      "Si abriste la pantalla directamente, sin pasar por «Lo mío», el botón te lleva a «Lo mío» como antes.",
    audiencia: "todos",
  },
  {
    id: "2026-10-06-el-alta-pide-el-documento",
    fecha: "2026-10-06",
    titulo: "Dar de alta a alguien ahora pide su documento",
    queMejoro:
      "En Equipo, «Agregar» pide el tipo de documento (DNI, carné de extranjería o pasaporte / PTP) y su número. " +
      "Si ese documento ya lo tiene alguien registrado, el sistema no deja crearla otra vez y dice quién es, con " +
      "«Ver en la lista»; si ya salió, se la reactiva desde su menú. Es lo que evita registrar dos veces a la misma " +
      "persona.\n\n" +
      "Las estaciones de retail se dan de alta marcando «Es una estación de retail»: no llevan documento. Y en Datos " +
      "personales, el documento se corrige eligiendo también su tipo.",
    audiencia: "panel",
  },
  {
    id: "2026-10-06-cargar-mi-documento-desde-lo-mio",
    fecha: "2026-10-06",
    titulo: "Si tu documento no está cargado, ahora lo cargas desde «Lo mío»",
    queMejoro:
      "En «Lo mío › Mis datos › Editar», si tu documento de identidad todavía no figura, puedes elegir el tipo y " +
      "escribir el número. Lo revisa Desarrollo Organizacional antes de guardarse, porque es el número que va en tu " +
      "contrato. Si ya está cargado, se ve como siempre y solo DO lo puede corregir.",
    audiencia: "todos",
  },
  {
    id: "2026-10-06-el-historial-se-pliega-y-se-pagina",
    fecha: "2026-10-06",
    titulo: "El historial de «Lo mío» se pliega, se lee mejor y ya no se corta en 20",
    queMejoro:
      "En «Lo mío › Historial», «Cambios a tu registro» ahora aparece cerrado y dice cuántos cambios hay. Tócalo " +
      "para abrirlo: se ven de 10 en 10, con «Anterior» y «Siguiente». Antes solo salían los 20 más recientes y " +
      "el resto no se podía ver.\n\n" +
      "Un cambio de horario ya no sale como un montón de llaves y comillas: dice, por ejemplo, de lunes a viernes " +
      "de 8:30 a 2:00 y pasa a otro horario, desde qué día y con qué motivo. Además, el contrato, la boleta, " +
      "Movilidad y «Contar algo» ya caben en la pantalla del celular, sin cortarse por el lado.",
    audiencia: "todos",
  },
  {
    id: "2026-10-06-lo-mio-atras-vuelve-a-la-seccion",
    fecha: "2026-10-06",
    titulo: "En «Lo mío», «atrás» te devuelve a la sección en la que estabas",
    queMejoro:
      "Si abres un reporte y usas «atrás» —el botón del navegador o el gesto del teléfono—, vuelves a la lista " +
      "de tus reportes, ya no al Resumen. Lo mismo entre secciones: si pasaste de Mis días a Boletas, «atrás» " +
      "te devuelve a Mis días.\n\n" +
      "Recargar la página te sigue llevando al Resumen, como hasta ahora.",
    audiencia: "todos",
  },
  {
    id: "2026-10-06-datos-personales-ordena-los-pendientes",
    fecha: "2026-10-06",
    titulo: "En Datos personales, los pendientes se pliegan y se recorren en orden",
    queMejoro:
      "La tarjeta de Pendientes ahora se pliega a una sola línea con los nombres: toca uno y se abre su ficha, lista " +
      "para completar. La lista entera, con lo que le falta a cada persona, aparece en el espacio de la ficha cuando " +
      "no tienes a nadie abierto.\n\n" +
      "Al abrir una ficha pendiente, arriba dice en cuál vas («2 de 4») y tiene «Siguiente →» para pasar a la próxima. " +
      "En la lista del equipo, «Por completar» muestra solo a quienes les falta algo. Y los filtros de sede ya no " +
      "muestran sedes donde no hay nadie.",
    audiencia: "panel",
  },
  {
    id: "2026-10-06-el-menu-de-lo-mio-se-ordena-por-temas",
    fecha: "2026-10-06",
    titulo: "El menú de «Lo mío» se ordena por temas y tiene buscador",
    queMejoro:
      "En «Lo mío», las secciones del menú ya no van en una sola lista: están agrupadas en Asistencia, Pago, " +
      "Documentos y Seguimiento. Puedes cerrar los grupos que no usas tocando su título, y el menú se acuerda en " +
      "ese dispositivo. En la computadora, ⌘K (Ctrl+K en Windows) abre un buscador: escribe «sueldo», " +
      "«vacaciones» o «memo» y te lleva a la sección.\n\n" +
      "En el teléfono, el botón «Menú» pasó al café de la paleta, el nombre de la sección queda al centro de la " +
      "barra y el cambio de tema está dentro del menú, junto a la ✕. Si la lista no entra en la pantalla, abajo " +
      "aparece «Más abajo» para que sepas que hay más secciones. «Tus datos» ahora se llama «Mis datos».",
    audiencia: "todos",
  },
  {
    id: "2026-10-06-el-apoyo-educativo-terminado-se-renueva",
    fecha: "2026-10-06",
    titulo: "Si tu apoyo educativo terminó y sigues estudiando, ahora lo renuevas desde tu portal",
    queMejoro:
      "En «Lo mío › Educación», cuando tu apoyo educativo ya terminó, aparece «Sigo estudiando: renovar mi apoyo», " +
      "con tu institución y tus datos ya llenos. Antes esa pantalla mostraba tu solicitud como aprobada y no " +
      "ofrecía ningún botón, así que no había cómo seguir subiendo tus constancias.\n\n" +
      "Si te rechazaron la constancia de un pago que hiciste mientras el apoyo estaba vigente, ahora puedes " +
      "corregirla aunque el apoyo ya haya terminado. Y al pedir el apoyo, la fecha de fin pregunta por el fin de tu " +
      "ciclo o curso, no por el de este mes: se pide una sola vez y después cada mes subes tu constancia.",
    audiencia: "todos",
  },
  {
    id: "2026-10-06-lo-mio-vuelve-a-abrir-en-resumen",
    fecha: "2026-10-06",
    titulo: "Al recargar «Lo mío», vuelves a tu Resumen",
    queMejoro:
      "Si llegabas a «Lo mío» desde un aviso de la Bandeja o desde «← Tus reportes» y luego recargabas la " +
      "página, se volvía a abrir esa misma sección —Reportes, Boletas o Turnos— en vez del Resumen. Ahora el " +
      "aviso te lleva a su sección una sola vez, y al recargar siempre empiezas por el Resumen, donde están tus " +
      "vacaciones, tu periodo de pago y las novedades.",
    audiencia: "todos",
  },
  {
    id: "2026-10-05-el-terminal-ilumina-en-vez-de-ocultar",
    fecha: "2026-10-05",
    titulo: "En el terminal, los estados se iluminan en vez de ocultar a los demás",
    queMejoro:
      "En la pantalla de marcar, los botones grandes de estados que había sobre las casillas pasaron a ser una " +
      "sola píldora fina bajo el selector de sede. Si tocas un estado, se iluminan las personas que están en él " +
      "y las demás se atenúan, pero ninguna desaparece: todas siguen viendo su nombre para marcar.\n\n" +
      "Los estados que nadie tiene ya no se dibujan, así que en una sede chica la píldora es muy corta. Las " +
      "casillas son todas iguales y el estado se ve en el ícono de color de la esquina de la foto; al pasar el " +
      "mouse por ese ícono o por la píldora aparece lo que significa. Tocar el ícono marca, igual que tocar " +
      "cualquier parte de la casilla.",
    audiencia: "todos",
  },
  {
    id: "2026-10-05-el-terminal-muestra-en-que-punto-esta-cada-integrante",
    fecha: "2026-10-05",
    titulo: "El terminal muestra en qué punto del día está cada integrante",
    queMejoro:
      "En la pantalla de marcar, cada casilla ahora dice si la persona está laborando, en refrigerio, en pausa " +
      "(por un trámite, una cita médica u otro motivo), con el turno terminado o sin haber entrado todavía. Se ve " +
      "en el ícono sobre su foto, en el color de la casilla y en la línea con la hora bajo su nombre.\n\n" +
      "Bajo el reloj hay una leyenda que cuenta cuántas personas hay en cada estado. Si tocas uno, la pantalla " +
      "muestra solo a esas personas; vuelve sola a los 20 segundos, o al tocar «Ver todos» o cualquier nombre. " +
      "Marcar funciona igual que siempre.\n\n" +
      "Quien salió y volvió sigue mostrando a qué hora entró, y aparte de cuándo a cuándo estuvo fuera. Si la " +
      "Mac no pudo confirmar el estado del día, las casillas se ven como antes, en vez de mostrar algo dudoso.",
    audiencia: "todos",
  },
  {
    id: "2026-10-04-constancias-con-nombre-completo",
    fecha: "2026-10-04",
    titulo: "Las constancias de Normas y de Política salarial traen el nombre completo del DNI",
    queMejoro:
      "En las hojas de «Constancia de entrega y difusión» —la de cada documento de Normas y la de la Política " +
      "salarial— ahora figura, bajo cada nombre de la lista, el nombre completo tal como consta en el DNI. La " +
      "lista sigue ordenada por apellido, como una nómina.\n\n" +
      "Si a alguien todavía no se le cargó su nombre completo en Datos personales, la pantalla avisa cuántas " +
      "personas faltan antes de imprimir. Si no se pudo leer ese dato, «Imprimir» queda apagado hasta recargar " +
      "la página.",
    audiencia: "do",
  },
  {
    id: "2026-10-04-equipo-avisa-si-ya-esta-registrada",
    fecha: "2026-10-04",
    titulo: "Al agregar a alguien, Equipo avisa si ya está registrada",
    queMejoro:
      "Antes de dar de alta a una persona, Equipo revisa si ya hay alguien con un nombre parecido —aunque esté " +
      "escrito más corto, sin tildes o con los apellidos cruzados— y lo muestra con su sede y su fecha de ingreso. " +
      "Si es la misma, se abre desde la lista; si es otra, se confirma con un clic. Incluye a quien ya salió: " +
      "esa persona se reactiva, no se registra de nuevo.\n\n" +
      "El formulario de alta también cambió: ya no pide Cargo ni Tipo de vínculo, porque nunca se guardaban al " +
      "agregar y la fila nueva salía «Sin cargo». Esos datos se completan después, con «Editar».",
    audiencia: "do",
  },
  {
    id: "2026-10-04-nombre-completo-en-los-papeles",
    fecha: "2026-10-04",
    titulo: "Tu boleta y tus papeles de salida llevan tu nombre completo, como en el DNI",
    queMejoro:
      "La boleta de pago, el certificado de trabajo y la constancia de cese ahora salen con tu nombre completo " +
      "tal como está en tu DNI, y ya no con el nombre corto con el que apareces en el terminal. En el terminal " +
      "sigues viéndote con el nombre corto, para encontrarte rápido.\n\n" +
      "Si el nombre de tu DNI todavía no está cargado en Datos personales, el papel sale con el nombre corto: " +
      "Desarrollo Organizacional lo ve en «Pendientes». En Equipo, los campos de nombre pasan a llamarse " +
      "«Nombre corto» y «Apellido corto», para que no se confundan con el nombre legal.",
    audiencia: "todos",
  },
  {
    id: "2026-10-02-horarios-sin-refrigerio",
    fecha: "2026-10-02",
    titulo: "En Horarios, un horario puede quedar sin refrigerio",
    queMejoro:
      "Quien entra solo en la tarde y ya llega almorzando no tenía cómo quedar bien: el refrigerio solo ofrecía " +
      "60 o 75 minutos y le restaba una hora que nunca toma. Ahora la lista trae «Ninguno» (en el horario por día " +
      "se ve como 0), y el total de la semana cuenta esas horas.\n\n" +
      "Cuando alguien entra pasadas las 13:00 y todavía tiene refrigerio puesto, el editor lo avisa y ofrece " +
      "«Poner sin refrigerio» con un clic. Es solo una sugerencia: no cambia nada hasta que la aceptas.",
    audiencia: "panel",
  },
  {
    id: "2026-10-01-dashboard-nombre-abre-el-dia",
    fecha: "2026-10-01",
    titulo: "En el Dashboard, el nombre de cada persona abre su día",
    queMejoro:
      "En «Sedes», al hacer clic en el nombre de alguien —en «Trabajando ahora», en «En pausa» o en el detalle " +
      "del equipo— se abre Correcciones con esa persona y el día de hoy ya elegidos: ves todas sus marcas, a qué " +
      "hora le tocaba entrar y lo que ya se corrigió.\n\n" +
      "Antes solo se podía llegar ahí desde una tardanza o un estado; para ver el día de quien estaba trabajando " +
      "sin novedad había que ir a Correcciones y buscarla en la lista.",
    audiencia: "panel",
  },
  {
    id: "2026-10-01-archivo-de-la-empresa",
    fecha: "2026-10-01",
    titulo: "Los papeles de la empresa ya tienen su lugar: Empresa → Archivo",
    queMejoro:
      "Hay un renglón nuevo al fondo del menú, «Empresa → Archivo», para los papeles que CAYLA presenta o recibe " +
      "de una autoridad: la inscripción de un banco de datos personales, la constancia de REMYPE, la licencia de " +
      "funcionamiento de cada sede. Se suben en PDF o en foto y se abren con un clic, para tenerlos a la mano el " +
      "día de una inspección.\n\n" +
      "Cada papel dice quién lo emite, de qué sede es, quién lo subió y cuándo. Si le pones fecha de vencimiento, " +
      "la pantalla avisa dos meses antes. Nada se borra: corregir un dato deja la versión anterior en el historial, " +
      "y retirar un papel pide escribir el motivo. Solo lo ve Desarrollo Organizacional.",
    audiencia: "do",
  },
  {
    id: "2026-10-01-nueva-version-de-la-politica-salarial",
    fecha: "2026-10-01",
    titulo: "Hay una versión nueva de la Política salarial para leer y confirmar",
    queMejoro:
      "Desarrollo Organizacional publica hoy una versión nueva de la Política salarial. Al abrir Dynamic verás el aviso «Te falta dejar una " +
      "constancia»: entra con «Leer y dejar constancia», lee el documento y, al final, escribe tu nombre y pulsa " +
      "«Dejar constancia». Se lee en un minuto.\n\n" +
      "Dejar constancia no significa estar de acuerdo con lo que dice: significa que la recibiste y la leíste. " +
      "Si algo no te queda claro, o tienes una discrepancia, puedes plantearla a Desarrollo Organizacional o a la " +
      "Gerencia y recibirás respuesta por escrito. Si cierras el aviso sin firmar, vuelve a salir hasta que dejes " +
      "tu constancia.",
    audiencia: "todos",
  },
  {
    id: "2026-09-30-correcciones-sin-quienes-ya-cesaron",
    fecha: "2026-09-30",
    titulo: "Correcciones ya no lista a quienes dejaron de trabajar",
    queMejoro:
      "La lista de colaboradores de Correcciones mostraba también a quienes ya cesaron, con un «(cesó)» al lado, " +
      "y había que pasar por encima de ellos para llegar a quien sí trabaja. Ahora la lista trae solo a quienes " +
      "siguen activos.\n\n" +
      "Si un día por revisar de alguien que cesó sigue pendiente, sigue apareciendo en los avisos de arriba de " +
      "la pantalla, y desde ahí se abre igual que antes.",
    audiencia: "panel",
  },
  {
    id: "2026-09-30-certificado-de-trabajo-con-recibi",
    fecha: "2026-09-30",
    titulo: "El certificado de trabajo ya trae su línea de «Recibí conforme»",
    queMejoro:
      "Hasta ahora, el certificado de trabajo que se imprime desde Liquidaciones salía solo con la firma de CAYLA: " +
      "no había dónde dejar constancia de que la persona lo recibió, ni de qué día. Como el sistema no archiva " +
      "el papel que se imprime, esa firma era la única forma de probar la entrega dentro de las 48 horas del cese.\n\n" +
      "Ahora, a la izquierda de la firma de CAYLA, hay una línea de «Recibí conforme» con el nombre y el DNI de la " +
      "persona, y un espacio para que escriba a mano la fecha en que lo recibe. Imprime dos copias y guarda en el " +
      "legajo la que firme quien cesó.",
    audiencia: "do",
  },
  {
    id: "2026-09-28-casos-en-el-dashboard",
    fecha: "2026-09-28",
    titulo: "El Dashboard ya cuenta cuántos Casos hay, de qué son y en qué sede",
    queMejoro:
      "Hasta ahora, para saber cuántos reportes había en Casos —y de qué se trataban— había que abrir la Bandeja " +
      "y contarlos a mano. En «Resumen del día», junto a «Pendientes de acción» y «Personal», hay un indicador " +
      "nuevo: «+ Casos». Al agregarlo, se ve cuántos casos hay en los últimos 6 meses, cuántos siguen abiertos, " +
      "cuántos tienen un plazo vencido, y cuántos se eligió reportar sobre cada tema y en cada sede.\n\n" +
      "Son solo números: nadie ve desde aquí quién escribió cada reporte, así que sigue siendo tan confidencial " +
      "como siempre. Se ve lo mismo que ya se puede ver en Casos, uno por uno, solo que sumado.",
    audiencia: "panel",
  },
  {
    id: "2026-09-28-declaracion-de-ruta-se-renueva",
    fecha: "2026-09-28",
    titulo: "Tu declaración de ruta ahora se renueva",
    queMejoro:
      "Si firmaste tu declaración de ruta desde Info en estas últimas semanas, lo hiciste con la versión corta, " +
      "que no preguntaba el costo del pasaje ni el uso de taxi. Ahora vas a ver un aviso para volver a firmarla " +
      "con los cinco puntos: se hace desde Info, en un minuto.\n\n" +
      "Además, desde ahora cada declaración se renueva una vez al año, en la fecha en que la firmaste. " +
      "Mientras no la renueves, tu movilidad se sigue pagando igual.",
    audiencia: "todos",
  },
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
    id: "2026-09-28-estaciones-de-retail-dejan-de-aparecer",
    fecha: "2026-09-28",
    titulo: "Las estaciones de caja y almacén de Retail ya no aparecen como si fueran personas",
    queMejoro:
      "Las cuentas que Retail usa en cada tienda —«ESTACIÓN — Caja Lima», «ESTACIÓN — Almacén Trujillo» y " +
      "las demás— salían en Datos personales como fichas sin completar, en Equipo, en el terminal de marcaje " +
      "de su sede y en las listas de Contratos y Documentación. Ya no: Dynamic las reconoce como cuentas de " +
      "servicio y las deja fuera de todo.\n\n" +
      "Siguen funcionando igual en Retail. Si necesitas revisarlas, están al final de Equipo, en un bloque " +
      "plegado «Cuentas de servicio». Y si alguna vez una ficha se marca así por error, desde su ficha se " +
      "desmarca con el menú «•••».",
    audiencia: "panel",
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

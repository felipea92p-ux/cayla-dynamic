// ============================================================================
// terminos.ts — los términos de uso y los de cada módulo de «Lo mío»
// ============================================================================
// QUÉ PROMETE · para «general» (los términos de uso de Dynamic) y para cada
//               módulo de «Lo mío»: su versión, cuánto pesa (casilla, aviso o
//               «ya tiene su propia constancia»), sus puntos y su texto.
// QUÉ ASUME   · que la libreta `aceptaciones_terminos` (0540) guarda lo que la
//               persona aceptó, con el texto entero: esto es lo que se le
//               MUESTRA, aquello es lo que queda PROBADO.
//
// ⚠ TODOS LOS TEXTOS DE HOY SON BORRADOR, y es lo que manda en este archivo.
// (2026-10-19: antes de este pull request se contrastó cada texto con lo que su
// pantalla de «Lo mío» HACE, y se corrigieron seis que prometían otra cosa —
// Vacaciones y permisos, Disciplina, Movilidad, Educación, Mis datos y
// Objetivos—. Eso arregla lo que dicen; no los vuelve aprobables: falta que los
// lean Desarrollo Organizacional y el laboralista.)
// Los redactó una sesión de desarrollo para poder armar la pantalla; ninguno lo
// ha leído Desarrollo Organizacional ni el laboralista. Una aceptación guarda
// «lo que la persona leyó»: salir con un texto sin validar deja una constancia
// firmada de algo que nadie revisó, y eso es peor que no tener constancia.
//
// Por eso un texto en `borrador` es INVISIBLE para la aplicación:
// `terminosVigentes` no lo devuelve, así que ninguna pantalla lo muestra, ni
// siquiera como aviso, y ningún módulo se bloquea. Para que un texto salga hay
// que cambiar su `estado` a «aprobado» y escribir quién lo aprobó y cuándo —en
// ese mismo cambio, que es una línea en un pull request que se ve y se revisa—.
//
// Un texto APROBADO queda candado: `tests/terminos.test.ts` guarda la huella de
// lo que dice. Cambiar una palabra sin subir `version` pone la prueba en rojo,
// porque quien ya aceptó la v1 aceptó ESA redacción, no la nueva. Subir la
// versión es lo que hace que ese módulo (y solo ese) se vuelva a pedir.
//
// LOS TRES PESOS (decididos con Felipe el 2026-10-19):
//   · `aceptacion`        — casilla obligatoria y constancia en la base. Bloquea
//                           el módulo (los de uso, además, todo «Lo mío»).
//   · `aviso`             — un «Entendido» sin constancia. Se puede dejar para
//                           después: no hay nada que acordar, solo algo que saber.
//   · `constancia_propia` — el módulo YA guarda lo que la persona acepta por su
//                           cuenta (el DNI, la declaración de ruta de Movilidad, la lectura de
//                           un memo, la firma de la boleta). Aquí solo se avisa
//                           y se apunta a esa constancia; una casilla nueva sería
//                           una SEGUNDA fuente para el mismo hecho.
//
// LA LISTA DE MÓDULOS NO SE ESCRIBE UNA SEGUNDA VEZ: la verdad de qué secciones
// existen es `lib/mio-secciones.ts`. `tests/terminos.test.ts` compara las dos y
// se pone en rojo si «Lo mío» gana una sección sin que alguien decida qué
// términos le tocan —aunque la decisión sea «un aviso y nada más»—.
// ============================================================================

export type PesoTerminos = "aceptacion" | "aviso" | "constancia_propia";
export type EstadoTexto = "borrador" | "aprobado";

export interface TerminosModulo {
  /** El nombre con el que se guarda en `aceptaciones_terminos.modulo`: el mismo del menú de «Lo mío». */
  modulo: string;
  /** Cómo se nombra en pantalla. */
  titulo: string;
  peso: PesoTerminos;
  /** Sube cuando cambia la redacción de un texto aprobado. Nunca baja. */
  version: number;
  estado: EstadoTexto;
  /** Quién y cuándo lo aprobó. Obligatorio si `estado` es «aprobado». */
  aprobado?: { por: string; fecha: string };
  /** Lo esencial, en una mirada: de dos a cuatro. */
  puntos: readonly string[];
  /** El texto completo, detrás de «Ver el texto completo». */
  texto: string;
  /** Solo `constancia_propia`: dónde queda lo que la persona acepta de verdad. */
  apuntaA?: string;
}

export const TERMINOS: readonly TerminosModulo[] = [
  {
    modulo: "general", titulo: "Términos de uso de Dynamic", peso: "aceptacion", version: 1, estado: "borrador",
    puntos: [
      "Dynamic registra tus marcajes, ausencias y pagos: de ahí sale tu pago.",
      "Dynamic avisa, nunca sanciona solo. Las decisiones las toman personas.",
      "Tus datos personales los ven solo quienes deben, por su función.",
      "Puedes ver, corregir y pedir información sobre tus datos (Ley N.° 29733).",
    ],
    texto:
      "Dynamic es el sistema de asistencia y planilla de la empresa. Registra tus marcajes, turnos, ausencias y los " +
      "datos que alimentan tu pago. Detecta tardanzas y faltas y las deja documentadas, pero no impone sanciones: " +
      "cualquier medida la decide una persona, con la conversación y la constancia que corresponden. Tus datos " +
      "personales se usan para tu contrato, tu pago y tu seguridad, los ven solo quienes por su función deben verlos, " +
      "y puedes ejercer tus derechos de acceso, rectificación, cancelación y oposición escribiendo a Desarrollo Organizacional.",
  },
  {
    modulo: "resumen", titulo: "Resumen", peso: "aviso", version: 1, estado: "borrador",
    puntos: [
      "Lo que ves aquí es un estimado de tu periodo, no tu boleta final.",
      "Se calcula con tus marcajes hasta hoy.",
      "Si algo no cuadra, avísale a tu líder de equipo.",
    ],
    texto:
      "El Resumen muestra información calculada en vivo a partir de tus marcajes, turnos y ausencias. Los montos y " +
      "fechas pueden cambiar hasta el cierre del periodo. Solo tu boleta oficial tiene valor de pago.",
  },
  {
    modulo: "dias", titulo: "Mis días", peso: "aviso", version: 1, estado: "borrador",
    puntos: [
      "Tus marcajes son el registro de tu asistencia.",
      "Dynamic avisa tardanzas y faltas; nunca sanciona solo, siempre decide una persona.",
      "Si un marcaje está mal, puedes pedir que se corrija, con un motivo.",
    ],
    texto:
      "Los marcajes se conservan y no se borran: una corrección queda registrada junto con quién la hizo y por qué. " +
      "Una tardanza registrada no es una sanción; cualquier medida disciplinaria requiere conversación y constancia.",
  },
  {
    modulo: "turnos", titulo: "Mis turnos", peso: "aviso", version: 1, estado: "borrador",
    puntos: [
      "Tu turno es el horario que tu líder de equipo te asigna.",
      "Un cambio de turno se avisa con anticipación.",
      "Los feriados de tu sede aparecen aquí.",
    ],
    texto:
      "Los turnos pueden ser modificados por tu líder de equipo respetando la jornada máxima legal y el aviso que " +
      "corresponda. Ver un turno aquí no reemplaza la comunicación directa con tu líder de equipo.",
  },
  {
    modulo: "ausencias", titulo: "Vacaciones y permisos", peso: "aceptacion", version: 1, estado: "borrador",
    puntos: [
      "Aquí puedes pedir tus vacaciones: eliges el rango y avisas.",
      "Las vacaciones las aprueba Desarrollo Organizacional, no tu líder de equipo.",
      "Tus permisos y descansos médicos los registra quien corresponde: aquí ves lo que consta y si falta algún documento.",
    ],
    texto:
      "En esta sección puedes pedir vacaciones: la solicitud queda registrada con su fecha y hora y la resuelve " +
      "Desarrollo Organizacional. Los permisos y los descansos médicos los registran las personas autorizadas; aquí ves " +
      "lo que consta de ti y si falta algún documento de respaldo. Al enviar una solicitud confirmas que la " +
      "información es verídica.",
  },
  {
    modulo: "boletas", titulo: "Boletas", peso: "constancia_propia", version: 1, estado: "borrador",
    apuntaA: "la firma de tu boleta, que deja constancia de que la recibiste",
    puntos: [
      "Aquí están tus boletas oficiales.",
      "La boleta es un documento personal: no la compartas.",
      "Si ves un error, avisa a Desarrollo Organizacional antes de firmar.",
    ],
    texto:
      "Las boletas oficiales las emite el contador. Contienen datos remunerativos personales y solo tú, y quienes por " +
      "su función deban verlas, tienen acceso. Lo que dejas por escrito es la firma de cada boleta, no esta pantalla.",
  },
  {
    modulo: "movilidad", titulo: "Movilidad", peso: "constancia_propia", version: 1, estado: "borrador",
    apuntaA: "la firma de tu declaración de ruta",
    puntos: [
      "Esta es tu declaración de ruta y gasto de transporte: dice si ya la firmaste, si toca renovarla o si te falta.",
      "Lo que se te paga lo calcula el sistema con la tarifa de tu sede; tú no escribes ningún monto.",
      "Lo que dejas por escrito es la firma de la declaración, no esta pantalla.",
    ],
    texto:
      "La declaración de ruta y gasto de transporte se firma en pantalla, con el mismo valor que el escaneo. El monto " +
      "lo calcula el sistema con la tarifa vigente de tu sede. La firma deja su propia constancia; este aviso solo la " +
      "anticipa.",
  },
  {
    modulo: "educacion", titulo: "Educación", peso: "aviso", version: 1, estado: "borrador",
    puntos: [
      "Aquí ves el estado de la constancia de estudios de cada apoyo educativo.",
      "Desde aquí vas a donde subes tu constancia, renuevas el apoyo o lo solicitas.",
      "Si tu apoyo terminó, te lo decimos y te llevamos a renovarlo.",
    ],
    texto:
      "Cada apoyo educativo tiene su constancia de estudios, con un plazo. El estado te dice si está al día, por vencer " +
      "o falta enviarla. Las constancias que subes sirven para comprobar tus estudios.",
  },
  {
    modulo: "contrato", titulo: "Contrato", peso: "aviso", version: 1, estado: "borrador",
    puntos: [
      "Aquí lees tu contrato vigente.",
      "Leerlo no es firmarlo: la firma es otro paso, en «Firma».",
      "Puedes imprimirlo o guardarlo.",
    ],
    texto:
      "El contrato es un documento legal entre tú y la empresa. Esta pantalla solo lo muestra; la firma se deja en " +
      "su propia sección con la constancia correspondiente.",
  },
  {
    modulo: "firma", titulo: "Firma", peso: "aceptacion", version: 1, estado: "borrador",
    puntos: [
      "Tu firma dibujada se usa para firmar tus documentos.",
      "Tiene valor de aceptación de su contenido.",
      "Solo tú puedes usarla; si crees que alguien la usó, avisa de inmediato.",
    ],
    texto:
      "La firma registrada se asocia a tu persona y se estampa en los documentos que firmes desde Dynamic. Cada uso " +
      "deja constancia con fecha y hora.",
  },
  {
    modulo: "dni", titulo: "Mi DNI", peso: "constancia_propia", version: 1, estado: "borrador",
    apuntaA: "la casilla de consentimiento que marcas al enviar las fotos (Ley N.° 29733)",
    puntos: [
      "Se piden las fotos de tu DNI (anverso y reverso).",
      "Sirven para verificar tu identidad.",
      "Tu consentimiento queda guardado cuando las envías, con el texto exacto que aceptas.",
    ],
    texto:
      "El consentimiento para tratar los datos de tu DNI se pide en el momento de enviarlas y se guarda palabra por " +
      "palabra. Este aviso solo lo anticipa; no pide una segunda aceptación.",
  },
  {
    modulo: "seguro", titulo: "Mi seguro", peso: "aviso", version: 1, estado: "borrador",
    puntos: [
      "Aquí está el PDF de tu póliza.",
      "Tu seguro depende de tu tipo de contrato.",
      "Para usarlo, lleva tu DNI y la póliza.",
    ],
    texto:
      "La información de la póliza la administra Desarrollo Organizacional. Cada integrante ve únicamente la suya.",
  },
  {
    modulo: "datos", titulo: "Mis datos", peso: "aceptacion", version: 1, estado: "borrador",
    puntos: [
      "Dynamic guarda tus datos personales para tu contrato, tu pago y tu seguridad.",
      "Solo los ven quienes deben por su función.",
      "Esta pantalla solo se lee. Para cambiar tu celular, dirección, contacto de emergencia, estado civil, grado de instrucción, hijos a cargo o cuenta bancaria usa «Editar datos»; lo demás lo corrige Desarrollo Organizacional.",
    ],
    texto:
      "Tratamiento de datos personales conforme a la Ley N.° 29733: finalidad, conservación y derechos de acceso, " +
      "rectificación, cancelación y oposición. Para ejercerlos, escribe a Desarrollo Organizacional.",
  },
  {
    modulo: "objetivos", titulo: "Objetivos", peso: "aviso", version: 1, estado: "borrador",
    puntos: [
      "Tus objetivos los acuerda y los marca tu líder de equipo.",
      "Aquí solo ves el avance: no se marcan desde esta pantalla.",
      "Los objetivos son un acompañamiento y no influyen en tu pago.",
    ],
    texto:
      "Los objetivos son una herramienta de acompañamiento: los acuerda contigo tu líder de equipo y los marca cuando " +
      "los conversan. No influyen en tu pago.",
  },
  {
    modulo: "reportes", titulo: "Reportes", peso: "aceptacion", version: 1, estado: "borrador",
    puntos: [
      "Aquí puedes contar algo que quieras que se atienda.",
      "Se trata con reserva: lo ve quien lo debe gestionar.",
      "Escribe hechos, no suposiciones.",
    ],
    texto:
      "Los reportes pueden contener información sensible sobre terceros. Se tratan con confidencialidad y se " +
      "gestionan por las personas autorizadas. Un reporte hecho de mala fe puede tener consecuencias.",
  },
  {
    modulo: "disciplina", titulo: "Disciplina", peso: "constancia_propia", version: 1, estado: "borrador",
    apuntaA: "la constancia que queda al abrir un documento y al marcar «Lo leí»",
    puntos: [
      "Aquí ves los documentos que te entregaron y cómo vas este mes con tus tardanzas.",
      "Abrir un documento y marcar «Lo leí» deja constancia de que lo leíste, no de que estés de acuerdo.",
      "Dynamic avisa las tardanzas; nunca sanciona solo: lo decide una persona.",
    ],
    texto:
      "La constancia de lectura registra la fecha y la hora en que abriste el documento y, si la das, la de «Lo leí». " +
      "No implica conformidad ni cambia el estado del documento. Esa constancia ya existe en cada documento; este aviso " +
      "solo la explica.",
  },
  {
    modulo: "historial", titulo: "Historial", peso: "aviso", version: 1, estado: "borrador",
    puntos: [
      "Aquí ves cada corrección que se hizo a tus marcajes.",
      "Cada una dice quién la hizo y por qué.",
      "Es solo de lectura.",
    ],
    texto: "El historial es un registro de auditoría. No puede modificarse desde esta pantalla.",
  },
];

/**
 * Lo que la aplicación puede MOSTRAR de un módulo: su entrada si está aprobada,
 * y `null` si no existe o sigue en borrador. Es el único camino hacia la
 * pantalla: así un borrador no sale ni por descuido. El catálogo es un
 * parámetro solo para poder probar el caso «aprobado» sin aprobar nada de verdad.
 */
export function terminosVigentes(
  modulo: string,
  catalogo: readonly TerminosModulo[] = TERMINOS,
): TerminosModulo | null {
  const t = catalogo.find((x) => x.modulo === modulo);
  return t && t.estado === "aprobado" ? t : null;
}

/** ¿Este módulo pide casilla y constancia? Solo si pesa `aceptacion` Y está aprobado. */
export function exigeAceptacion(modulo: string, catalogo: readonly TerminosModulo[] = TERMINOS): boolean {
  return terminosVigentes(modulo, catalogo)?.peso === "aceptacion";
}

/**
 * Lo que la persona TUVO DELANTE, en un solo texto: es lo que se manda a
 * `fn_aceptar_terminos` y lo que se guarda como constancia, y lo que la huella
 * de la prueba candada. Título, puntos y texto completo, en ese orden.
 */
export function textoAceptado(t: TerminosModulo): string {
  return [t.titulo, ...t.puntos.map((p) => `• ${p}`), t.texto].join("\n");
}

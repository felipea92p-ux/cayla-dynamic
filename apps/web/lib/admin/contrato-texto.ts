// El molde del contrato de trabajo — separado de la pantalla a propósito: un
// documento de 13 páginas que alguien con criterio legal necesita poder leer
// cláusula por cláusula no debería vivir enterrado en el estado de un
// componente de React.
//
// QUÉ SE CORRIGIÓ frente al contrato modelo (el de Angie, jul-2026):
//   · Jornada: las horas semanales ya no quedan en blanco.
//   · Sobretiempo: mide contra 48 h SEMANALES (nunca diarias), en ciclos de
//     7 días sin solape, con el recargo 25%/35% — no "conforme a ley" a
//     secas. Ver docs/planilla-anexo-tecnico.md y CLAUDE.md.
//   · RIT: se cita por versión y fecha vigente, no sin versión.
//   · Beneficios: se agregan movilidad, educación y bono de onomástico —
//     los tres están implementados y pagándose (verificado contra
//     fn_planilla_calcular vigente, migración 0263).
//   · Remuneración: la vigente real de cada persona — no se baja nada.
//
// QUÉ NO SE TOCÓ a propósito (son decisiones legales, no defectos técnicos):
//   · La modalidad y causa objetiva (art. 57, D.Leg. 728) se mantienen tal
//     como las tenía el contrato modelo — cambiarlas es una decisión legal,
//     no una corrección de datos. Se deja `causaObjetivaTexto` editable para
//     que se revise caso por caso (p. ej. Central no es tienda).
//   · El período de prueba NO se repite en una renovación: quien ya lo pasó
//     en su contrato original no vuelve a empezar de cero.
//
// Antes de usar esto para firmar contratos reales, alguien con criterio legal
// (el mismo que redactó el contrato de Angie) debería revisar el texto final
// una vez generado para una persona real. Esta pieza construye la
// herramienta; no reemplaza esa revisión.
//
// Lo mismo vale para `documentoConvenio` (0333): se redactó sobre la Ley
// N.° 28518 y su reglamento, con el mismo tono ya usado en la boleta de un
// practicante (PR #98), pero tampoco tuvo revisión legal de un abogado —
// misma seriedad que el contrato de planilla, ni más ni menos.
//
// Y lo mismo vale para la rama `tipo === "indefinido"` (0347): el texto de
// naturaleza/vigencia y de terminación se redactó sobre el régimen general de
// la LPCL (arts. 16, 22-25 y 38 del TUO del D.Leg. 728), pero tampoco tuvo
// revisión legal de un abogado.

import { EMPRESA, maximoSemanalPracticante } from "@cayla-dynamic/shared";

export interface DatosContrato {
  tipo: "nuevo" | "renovacion" | "adendum" | "convenio_practicas" | "indefinido";

  // La persona
  nombreDni: string;
  documento: string;
  direccion: string | null;
  cargo: string;
  email: string | null;
  /**
   * De `datos_personales.genero` (0369). Decide "EL PRACTICANTE" / "LA
   * PRACTICANTE" en el convenio de prácticas y "EL COLABORADOR" / "LA
   * COLABORADORA" en el contrato de trabajo y el adendum, con los participios
   * que concuerdan (ver `segunGenero`) — `null` (dato no cargado) mantiene el
   * femenino por ser el uso previo del documento, no una suposición de género.
   */
  genero: "femenino" | "masculino" | null;

  // El puesto
  sedeNombre: string;
  sedeCodigo: string;
  /**
   * La ciudad donde se celebra el contrato — de `sedes.ciudad` (migración
   * 0279), NO del nombre de la sede. Antes se usaba `sedeNombre` y el
   * documento imprimía «En la ciudad de Tienda TRU». `null` cuando esa sede
   * todavía no tiene ciudad cargada: el contrato lo dice, no la inventa.
   */
  ciudad: string | null;
  causaObjetivaTexto: string;
  funcionesTexto: string;

  /**
   * Solo para `tipo: "convenio_practicas"` (0333). `practicanteModalidad`
   * decide 30h/48h semanales (Ley 28518 art. 44, ver
   * `maximoSemanalPracticante`). `planCapacitacionTexto` reemplaza al Anexo I
   * de funciones: un convenio no tiene "funciones de un cargo", tiene un
   * plan de capacitación específico (art. 15) — hoy solo cubre "actividades
   * principales"; el resto del Anexo I vive en los campos de más abajo
   * (0348).
   */
  practicanteModalidad: "preprofesional" | "profesional" | null;
  planCapacitacionTexto: string;

  /**
   * SOLO PREPROFESIONAL (auditoría 2026-09-14) — cuántas horas semanales se
   * pactaron de verdad, cuando son MENOS que el tope de 30h de su modalidad
   * (art. 44, Ley 28518). `null` en cualquier otro caso (profesional siempre
   * trabaja su jornada completa de 48h; no hay nada que declarar aparte).
   *
   * Decide dos cosas a la vez, y las decide junta para que no puedan
   * desalinearse: el texto de la cláusula QUINTA (JORNADA) y el piso de la
   * subvención de la cláusula SEXTA (SUBVENCIÓN ECONÓMICA). El artículo 45 de
   * la Ley 28518 dice literalmente: la subvención no puede ser inferior a una
   * RMV "cuando la persona en formación cumpla la jornada máxima prevista
   * para cada modalidad formativa" — 30h para preprofesional, no 48h — "para
   * el caso de jornadas... de duración inferior, el pago... es proporcional".
   * Antes de esto, el sistema no tenía dónde guardar "menos de 30h" y por eso
   * exigía siempre una RMV completa, o dejaba el texto diciendo "proporcional"
   * sin decir a qué proporción — las dos cosas a la vez, según qué parte del
   * código se mirara.
   */
  horasSemanalesPactadas: number | null;

  /**
   * La RMV vigente al momento de generar (0333 ya la lee para la pantalla;
   * antes no viajaba hasta acá). Solo se usa para declarar el PISO EXACTO de
   * la subvención cuando `horasSemanalesPactadas` es menor al tope de la
   * modalidad — sin ella, el texto solo puede describir la proporción en
   * palabras, no en soles. `null` cuando no está publicada en el sistema: el
   * texto lo dice, no inventa un monto.
   */
  rmvVigente: number | null;

  /**
   * SOLO PREPROFESIONAL (0348) — el convenio es TRIPARTITO: CAYLA, el centro
   * de formación profesional y la practicante firman los tres (art. 12 y ss.,
   * Ley 28518). El profesional es bipartito (CAYLA + practicante); el centro
   * que la presenta es solo una referencia, no firma. Modelo de origen:
   * `CAYLA_CORP_CONT_202609_ConvenioPracticas.docx` (DO, sep-2026).
   * Vacío no bloquea — un dato ausente se dice ("[completar]"), no se inventa.
   */
  centroFormacionNombre: string | null;
  centroFormacionRuc: string | null;
  centroFormacionDomicilio: string | null;
  /**
   * Antes era un solo campo de texto libre («representante»). Se separó
   * (0399) porque el convenio necesita decir en qué calidad firma esa
   * persona por el centro — "representado por Juan Pérez, en su calidad de
   * Director Académico" — y un campo único dejaba el cargo a discreción de
   * quien tipeaba, o ausente.
   */
  centroFormacionRepresentanteNombre: string | null;
  centroFormacionRepresentanteCargo: string | null;
  /** Preprofesional: qué carrera cursa y en qué ciclo. */
  carreraEspecialidad: string | null;
  cicloAcademico: string | null;
  /** Profesional: "Bachiller en X — Universidad Y, egresado el Z", ya redactado. */
  gradoTituloTexto: string | null;

  /**
   * ANEXO I — Plan Específico de Aprendizaje (0348, ambas modalidades). Antes
   * era un único texto libre (`planCapacitacionTexto`, que sigue existiendo
   * para "actividades principales"); el modelo de DO lo pide como ficha con
   * estos campos propios.
   *
   * Traía además "hito de evaluación — mes 3 / mes 6", quitado (0404): eran
   * meses de calendario fijos sobre un convenio de duración variable —se
   * rompían en cualquier convenio de menos de 6 meses, pidiendo evaluar algo
   * después de que ya había terminado— y sin ningún seguimiento real detrás
   * en el sistema, el campo obligatorio solo empujaba a escribir relleno para
   * poder generar el contrato.
   */
  areaProyecto: string;
  objetivoFormativoGeneral: string;
  supervisorAsignado: string;

  // Plazo — la jornada es siempre de 48h, el máximo legal; no se declara un
  // número calculado del horario, que es solo la disposición operativa de hoy.
  fechaInicio: string; // ISO
  // Ignorado cuando `tipo === "indefinido"` (0347): ese contrato no tiene
  // fecha de término y el documento nunca lo lee. Se deja tipado como string
  // (no string | null) porque en la base SÍ importa que sea NULL para ese
  // tipo — la distinción vive en `contratos_generados.fecha_fin`, no acá.
  fechaFin: string; // ISO
  fechaIngresoOriginal: string; // ISO — para saber si ya pasó el período de prueba

  // Plata
  remuneracionMensual: number;

  // Beneficios nuevos
  cobraMovilidad: boolean;
  movilidadDiaria: number | null;
  bonoOnomastico: number;

  // RIT vigente
  ritVersion: string;
  ritFecha: string; // ya formateada, ej. "10 de agosto de 2026"

  // Anexo IV
  activosPrincipales: string;
  activosLibre: string;

  /**
   * Solo para `tipo: "adendum"`: qué se modifica del contrato vigente. Un
   * adendum NO repite el contrato entero — declara el cambio y deja todo lo
   * demás en pie. Antes el tipo «adendum» solo cambiaba el título y volvía a
   * imprimir el contrato completo debajo, con su plazo y su período de prueba:
   * dos documentos que dicen ser el mismo vínculo con condiciones distintas.
   */
  adendumTexto: string;
  /**
   * Solo para `tipo: "adendum"`: la persona es practicante (0505). Un adendum
   * al contrato de trabajo habla de «vínculo laboral»; el de un practicante
   * modifica un CONVENIO de modalidad formativa (Ley 28518) y no puede sonar
   * a contrato de trabajo — el mismo cuidado que la 0333 puso en el convenio.
   */
  esPracticante: boolean;

  // Quién firma por CAYLA. Sale de `configuracion.firmante_empresa` (0147) más
  // la ficha de esa persona — no escrito a mano acá: la 0147 existe justamente
  // para que quién firma sea un dato administrable y validado.
  firmanteNombre: string;
  firmanteDni: string;
  firmanteCargo: string;
}

/**
 * Activos principales conocidos por sede, como PUNTO DE PARTIDA editable en
 * la pantalla — no una tabla de inventario. No hay tabla de activos hoy (se
 * pidió explícitamente no construirla todavía); esto es un stopgap. Si algún
 * día existe una tabla real de activos por persona, la verdad pasa a vivir
 * ahí y esta constante se retira.
 */
export const ACTIVOS_PRINCIPALES_POR_SEDE: Record<string, string> = {
  CCO: "Equipo de cómputo y mobiliario de oficina asignado en Central.",
  LIM: "Herramientas y equipo del taller asignado en la sede Lima.",
  AQP: "Caja registradora, equipo de cómputo y mobiliario de tienda asignado en la sede Arequipa.",
  TRU: "Caja registradora, equipo de cómputo y mobiliario de tienda asignado en la sede Trujillo.",
};

/**
 * El texto de relleno de "Funciones del cargo" — exportado para que la
 * pantalla pueda comparar contra él exactamente y BLOQUEAR la generación si
 * nadie lo reemplazó. Vive acá, no duplicado en la pantalla, para que las dos
 * comparaciones no puedan desalinearse.
 */
export const FUNCIONES_PLACEHOLDER =
  "[Completar con las funciones específicas del puesto — usar como referencia el Anexo I del contrato anterior de esta persona, si existe.]";

const UNIDADES = ["", "uno", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve"];
const DIECIS = [
  "diez", "once", "doce", "trece", "catorce", "quince",
  "dieciséis", "diecisiete", "dieciocho", "diecinueve",
];
const DECENAS = ["", "", "veinte", "treinta", "cuarenta", "cincuenta", "sesenta", "setenta", "ochenta", "noventa"];
const CENTENAS = [
  "", "ciento", "doscientos", "trescientos", "cuatrocientos", "quinientos",
  "seiscientos", "setecientos", "ochocientos", "novecientos",
];

/**
 * El 21 al 29 se escriben en UNA palabra —«veinticinco»— y no «veinte y cinco».
 * Estaba mal, y no era cosmético: este número es el monto en letras del sueldo,
 * y en un contrato el monto en letras es el que manda si discrepa del que va en
 * cifras. Un sueldo de S/ 1,125.00 salía como «Mil ciento veinte y cinco».
 */
const VEINTIS = [
  "veinte", "veintiuno", "veintidós", "veintitrés", "veinticuatro",
  "veinticinco", "veintiséis", "veintisiete", "veintiocho", "veintinueve",
];

function tresDigitos(n: number): string {
  if (n === 0) return "";
  if (n === 100) return "cien";
  const c = Math.floor(n / 100);
  const resto = n % 100;
  let out = c > 0 ? CENTENAS[c] : "";
  if (resto > 0) {
    if (out) out += " ";
    if (resto < 10) out += UNIDADES[resto];
    else if (resto < 20) out += DIECIS[resto - 10];
    else if (resto < 30) out += VEINTIS[resto - 20];
    else {
      const d = Math.floor(resto / 10);
      const u = resto % 10;
      out += DECENAS[d] + (u > 0 ? ` y ${UNIDADES[u]}` : "");
    }
  }
  return out;
}

/**
 * Delante de «mil», el uno se apocopa: «veintiún mil», «treinta y un mil» —
 * nunca «veintiuno mil». Solo aplica cuando el uno es la última palabra del
 * bloque de millares; «treinta y un mil quinientos uno» conserva el último.
 */
function apocopeAnteMil(texto: string): string {
  if (texto === "uno") return "un";
  if (texto.endsWith("veintiuno")) return `${texto.slice(0, -"veintiuno".length)}veintiún`;
  if (texto.endsWith(" uno")) return `${texto.slice(0, -" uno".length)} un`;
  return texto;
}

/** "1,130.00" → "Mil ciento treinta y 00/100". Soporta hasta 999,999.99. */
export function numeroALetras(monto: number): string {
  const entero = Math.floor(monto);
  const centavos = Math.round((monto - entero) * 100);
  const miles = Math.floor(entero / 1000);
  const resto = entero % 1000;
  let out = "";
  if (miles > 0) {
    out += miles === 1 ? "mil" : `${apocopeAnteMil(tresDigitos(miles))} mil`;
    if (resto > 0) out += " ";
  }
  if (resto > 0 || entero === 0) out += tresDigitos(resto) || "cero";
  const capitalizada = out.charAt(0).toUpperCase() + out.slice(1);
  return `${capitalizada} y ${String(centavos).padStart(2, "0")}/100`;
}

export function formatearFecha(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  const meses = [
    "enero", "febrero", "marzo", "abril", "mayo", "junio",
    "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
  ];
  return `${d} de ${meses[m - 1]} de ${y}`;
}

function soles(n: number): string {
  return n.toLocaleString("es-PE", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

/**
 * `documento_html` se guarda tal cual y se inyecta con `dangerouslySetInnerHTML`
 * en la pantalla — así que todo texto libre que viene de datos de la persona
 * (nombre, dirección, cargo, funciones, activos) se escapa antes de
 * interpolarse. No es que se desconfíe de quien lo carga: es que un nombre con
 * un "&" o una dirección con un "<" no debe poder romper la estructura del
 * documento que se va a imprimir y firmar.
 */
function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function escapado(d: DatosContrato): DatosContrato {
  return {
    ...d,
    nombreDni: escapeHtml(d.nombreDni),
    documento: escapeHtml(d.documento),
    direccion: d.direccion ? escapeHtml(d.direccion) : null,
    cargo: escapeHtml(d.cargo),
    email: d.email ? escapeHtml(d.email) : null,
    sedeNombre: escapeHtml(d.sedeNombre),
    ciudad: d.ciudad ? escapeHtml(d.ciudad) : null,
    causaObjetivaTexto: escapeHtml(d.causaObjetivaTexto),
    funcionesTexto: escapeHtml(d.funcionesTexto),
    planCapacitacionTexto: escapeHtml(d.planCapacitacionTexto),
    centroFormacionNombre: d.centroFormacionNombre ? escapeHtml(d.centroFormacionNombre) : null,
    centroFormacionRuc: d.centroFormacionRuc ? escapeHtml(d.centroFormacionRuc) : null,
    centroFormacionDomicilio: d.centroFormacionDomicilio ? escapeHtml(d.centroFormacionDomicilio) : null,
    centroFormacionRepresentanteNombre: d.centroFormacionRepresentanteNombre
      ? escapeHtml(d.centroFormacionRepresentanteNombre)
      : null,
    centroFormacionRepresentanteCargo: d.centroFormacionRepresentanteCargo
      ? escapeHtml(d.centroFormacionRepresentanteCargo)
      : null,
    carreraEspecialidad: d.carreraEspecialidad ? escapeHtml(d.carreraEspecialidad) : null,
    cicloAcademico: d.cicloAcademico ? escapeHtml(d.cicloAcademico) : null,
    gradoTituloTexto: d.gradoTituloTexto ? escapeHtml(d.gradoTituloTexto) : null,
    areaProyecto: escapeHtml(d.areaProyecto),
    objetivoFormativoGeneral: escapeHtml(d.objetivoFormativoGeneral),
    supervisorAsignado: escapeHtml(d.supervisorAsignado),
    activosPrincipales: escapeHtml(d.activosPrincipales),
    activosLibre: escapeHtml(d.activosLibre),
    adendumTexto: escapeHtml(d.adendumTexto),
    firmanteNombre: escapeHtml(d.firmanteNombre),
    firmanteDni: escapeHtml(d.firmanteDni),
    firmanteCargo: escapeHtml(d.firmanteCargo),
    ritVersion: escapeHtml(d.ritVersion),
    ritFecha: escapeHtml(d.ritFecha),
  };
}

/**
 * Una lista escrita a mano en el textarea, una función por línea, se imprime
 * NUMERADA — no como un párrafo corrido ni con viñetas. Numerada porque un
 * anexo de funciones se cita ("la función 14 del Anexo I") cuando hay que
 * sustentar un incumplimiento, y una viñeta no se puede citar.
 *
 * La numera el HTML (`<ol>`), no quien escribe: si alguien numerara a mano,
 * insertar una función en el medio obligaría a renumerar el resto, y basta
 * que se olvide una para que el anexo tenga dos "12".
 *
 * Una línea que TERMINA EN DOS PUNTOS es un título de sección — la
 * numeración sigue corrida por debajo, igual que el Anexo I del contrato
 * modelo, que agrupaba las funciones por bloque.
 *
 * El texto ya llega escapado (ver `escapado`), así que partir por salto de
 * línea es seguro: `escapeHtml` no toca `\n`. Una sola línea se queda como
 * párrafo, para no cambiar el caso corto que ya existía.
 */
function listaDesdeTexto(texto: string): string {
  const lineas = texto
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l.length > 0);
  if (lineas.length <= 1) return `<p>${texto}</p>`;

  const partes: string[] = [];
  let abierta = false;
  let contados = 0;
  for (const linea of lineas) {
    if (linea.endsWith(":")) {
      if (abierta) {
        partes.push("</ol>");
        abierta = false;
      }
      partes.push(`<p><strong>${linea}</strong></p>`);
      continue;
    }
    if (!abierta) {
      // `start` mantiene la numeración corrida entre secciones: la primera
      // función después de un título no vuelve a empezar en 1.
      partes.push(`<ol start="${contados + 1}">`);
      abierta = true;
    }
    partes.push(`<li>${linea}</li>`);
    contados += 1;
  }
  if (abierta) partes.push("</ol>");
  return partes.join("");
}

/**
 * Un texto libre de varias líneas como PÁRRAFO, no como lista. El objetivo
 * formativo general del Anexo I se escribe en un cuadro de varias líneas
 * —era un renglón, y un párrafo entero se iba de largo sin poder leerse— y
 * un Enter ahí tiene que llegar al papel: dentro de un `<p>` el salto de
 * línea colapsa a un espacio, así que se vuelve `<br/>`. El texto ya llega
 * escapado (ver `escapado`), igual que en `listaDesdeTexto`. Un texto vacío o
 * solo de espacios devuelve "" para que el llamador pueda poner «[completar]».
 */
function parrafoDesdeTexto(texto: string): string {
  return texto
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l.length > 0)
    .join("<br/>");
}

/**
 * El marcador donde la pantalla estampa la firma escaneada justo antes de
 * imprimir. NO viaja dentro de `documento_html`: la 0272 congela el borrador
 * SIN firma a propósito, y meter la imagen en lo congelado convertiría un
 * borrador en algo que parece firmado.
 */
export const MARCADOR_FIRMA_EMPRESA = "<!--FIRMA_EMPRESA-->";

/**
 * El mismo mecanismo que `MARCADOR_FIRMA_EMPRESA`, para la firma de quien
 * suscribe el contrato como persona (0397). Tampoco viaja dentro de
 * `documento_html` — se estampa al mostrar, nunca al guardar.
 */
export const MARCADOR_FIRMA_PERSONA = "<!--FIRMA_PERSONA-->";

/**
 * «en la ciudad de Trujillo» — o, si esa sede todavía no tiene ciudad cargada
 * (0279), lo dice en vez de inventarla. Es la misma regla que la tarifa de
 * movilidad en `/admin/documentacion`: un dato que falta se ve, no se rellena.
 */
function enLaCiudadDe(d: DatosContrato): string {
  return d.ciudad
    ? `la ciudad de ${d.ciudad}`
    : `la ciudad de <strong>[FALTA LA CIUDAD DE LA SEDE ${d.sedeNombre} — cargarla en /admin/sedes]</strong>`;
}

/**
 * Elige la forma masculina o femenina según `datos_personales.genero` (0369),
 * con la misma convención que estrenó el convenio de prácticas (PR #233):
 * `null` —el dato no está cargado— mantiene el femenino, que era el uso previo
 * de todos estos documentos. No es una suposición de género: es no cambiar lo
 * que ya se imprimía cuando no hay dato que lo sostenga.
 */
function segunGenero(d: DatosContrato, masculino: string, femenino: string): string {
  return d.genero === "masculino" ? masculino : femenino;
}

/**
 * Cómo se nombra a la persona en el contrato de trabajo y en el adendum. Hasta
 * la 0369 decía siempre «LA COLABORADORA»: a un hombre le salía impreso,
 * firmado y registrado ante la Autoridad de Trabajo con el género equivocado.
 *
 * Es un término definido en la comparecencia («a quien en adelante se
 * denominará EL COLABORADOR»), y por eso nunca se contrae: «de EL COLABORADOR»,
 * «a EL COLABORADOR» — no «del» ni «al». Es la forma de los modelos de contrato
 * del MTPE con EL TRABAJADOR, y la que ya usa acá el convenio con EL PRACTICANTE.
 */
function etiquetaColaborador(d: DatosContrato): string {
  return segunGenero(d, "EL COLABORADOR", "LA COLABORADORA");
}

/**
 * Marca de lo que Desarrollo Organizacional todavía tiene que escribir en el
 * texto sugerido de la adenda. Mientras quede una, la pantalla no deja generar:
 * una adenda con «[COMPLETAR: número]» impreso y firmado no prueba ninguna póliza.
 */
export const MARCA_POR_COMPLETAR = "[COMPLETAR";

/**
 * El texto sugerido para la adenda que pasa a un practicante del EsSalud al
 * seguro privado FOLA (0504/0505). Dice lo mismo que la cláusula SEGURO del
 * convenio nuevo: cuando una cambia, cambia la otra. Los datos de la póliza no
 * se inventan: quedan como «[COMPLETAR: …]».
 */
export function textoAdendaSeguroPrivado(genero: DatosContrato["genero"]): string {
  const etiqueta = genero === "masculino" ? "EL PRACTICANTE" : "LA PRACTICANTE";
  return (
    `Se modifica la cláusula SEGURO del convenio, que queda redactada así: «LA EMPRESA cubre los riesgos de ` +
    `enfermedad y accidentes de ${etiqueta} mediante un seguro privado contratado a su cargo (Ley N.° 28518, ` +
    `artículo 42.8), con una cobertura no menor a catorce (14) subvenciones mensuales en caso de enfermedad y ` +
    `treinta (30) en caso de accidente, que alcanza también los accidentes ocurridos durante la ejecución de la ` +
    `práctica, vigente desde el ${MARCA_POR_COMPLETAR}: fecha de inicio de la póliza], póliza N.° ` +
    `${MARCA_POR_COMPLETAR}: número] de ${MARCA_POR_COMPLETAR}: aseguradora]. LA EMPRESA no se acoge al régimen ` +
    `de prestaciones de EsSalud a favor de ${etiqueta} (artículo 47 de la misma ley). La prima íntegra es de ` +
    `cargo de LA EMPRESA y no se descuenta de la subvención económica.»`
  );
}

/**
 * Un bloque de firma. Va al pie del contrato Y al pie de cada anexo, como el
 * contrato modelo en papel: un anexo que se separa de su contrato y no lleva
 * firma no se puede atribuir a nadie, y el Anexo IV —el que sostiene el
 * reclamo de devolución de los equipos— es justo el que más se separa.
 *
 * `etiquetaPersona` existe por el convenio de prácticas (0333): a quien firma
 * no se le puede llamar "LA COLABORADORA" en un documento cuyo primer párrafo
 * dice que no es una relación laboral (Ley 28518 art. 47) — sería el mismo
 * error de lenguaje que la 0322 evitó en la boleta. Sin pasarla, sigue el
 * género de la persona (`etiquetaColaborador`), que es lo que quieren el
 * contrato de trabajo y el adendum.
 */
/**
 * `tercero`: SOLO el convenio preprofesional (0348) es tripartito — CAYLA, el
 * centro de formación y la practicante firman los tres (art. 12 y ss., Ley
 * 28518). Todo lo demás (contrato de trabajo, adendum, convenio profesional)
 * sigue firmando entre dos.
 */
function bloqueFirmas(
  d: DatosContrato,
  etiquetaPersona = etiquetaColaborador(d),
  tercero?: { etiqueta: string; nombre: string; ruc: string; representanteNombre: string; representanteCargo: string },
): string {
  return `
    <div class="firmas">
      <div>
        <p class="linea">${MARCADOR_FIRMA_EMPRESA}</p>
        <p><strong>${d.firmanteCargo.toUpperCase()}</strong><br/>${d.firmanteNombre}<br/>DNI N.° ${d.firmanteDni}<br/>${EMPRESA.nombre}</p>
      </div>
      ${
        tercero
          ? `<div>
        <p class="linea">&nbsp;</p>
        <p><strong>${(tercero.representanteCargo || tercero.etiqueta).toUpperCase()}</strong><br/>${tercero.representanteNombre}<br/>${tercero.nombre}<br/>RUC N.° ${tercero.ruc}</p>
      </div>`
          : ""
      }
      <div>
        <p class="linea">${MARCADOR_FIRMA_PERSONA}</p>
        <p><strong>${etiquetaPersona}</strong><br/>${d.nombreDni}<br/>DNI N.° ${d.documento}</p>
      </div>
    </div>`;
}

/**
 * El encabezado de un anexo. Lleva SIEMPRE de quién es y de qué fecha: si las
 * hojas se separan —y se separan, se firman por separado— un anexo anónimo no
 * se puede devolver a su contrato. Antes solo el Anexo IV lo llevaba.
 */
function encabezadoAnexo(d: DatosContrato, titulo: string, subtitulo: string): string {
  return `
    <h2>${titulo}</h2>
    <p class="norma"><em>${subtitulo}</em></p>
    <p class="norma"><em>${d.nombreDni} · DNI N.° ${d.documento} · ${formatearFecha(d.fechaInicio)}</em></p>`;
}

/** El pie que cierra cada anexo: su bloque de firma y el sello de la empresa. */
function pieAnexo(d: DatosContrato, etiquetaPersona?: string): string {
  return `
    ${bloqueFirmas(d, etiquetaPersona)}
    <p class="pie-hoja">${EMPRESA.nombre} · RUC N.° ${EMPRESA.ruc}</p>`;
}

function clausulaJornada(d: DatosContrato): string {
  const colaborador = etiquetaColaborador(d);
  return `
    <h3>QUINTA. JORNADA LABORAL, HORARIOS Y REGISTRO DE ASISTENCIA</h3>
    <p>La jornada laboral es de cuarenta y ocho (48) horas semanales, el máximo
    establecido por el artículo 25 de la Constitución Política del Perú y el Texto
    Único Ordenado del Decreto Legislativo N.° 854, Ley de Jornada de Trabajo,
    Horario y Trabajo en Sobretiempo, aprobado por Decreto Supremo N.° 007-2002-TR.
    Que LA EMPRESA determine, por su sola voluntad y según sus necesidades
    operativas, programar en la práctica un número de horas menor a lo largo de la
    semana no reduce ni modifica esta jornada pactada: LA EMPRESA conserva en todo
    momento la facultad de disponer hasta el máximo de 48 horas semanales aquí
    establecido, sin que ello requiera la suscripción de un nuevo contrato.</p>
    <p>Los horarios de trabajo son rotativos y serán determinados por LA EMPRESA de
    acuerdo a sus requerimientos operativos, pudiendo variar los turnos, los
    horarios de ingreso y salida, el día de descanso, y la distribución de horas a
    lo largo de la semana, dentro del máximo establecido en el párrafo anterior. LA
    EMPRESA comunicará el cuadro de turnos con anticipación razonable.</p>
    <p>El día de descanso semanal es igualmente rotativo y podrá corresponder a
    cualquier día de la semana según la programación establecida por LA EMPRESA
    conforme a sus necesidades operativas, de acuerdo al artículo 2 del Decreto
    Legislativo N.° 713. En todo caso, ${colaborador} gozará de veinticuatro (24)
    horas consecutivas de descanso semanal remunerado, así como del descanso en
    días feriados no laborables conforme a ley.</p>
    <p>El registro de asistencia será obligatorio mediante el sistema designado por
    LA EMPRESA.</p>
    <p>El sobretiempo se computa sobre un <strong>ciclo de siete (7) días
    calendario consecutivos y sin solaparse</strong>, contra un máximo de
    <strong>cuarenta y ocho (48) horas semanales</strong> — nunca contra la jornada
    diaria — conforme al artículo 25 de la Constitución Política del Perú y al
    artículo 14 del Reglamento Interno de Trabajo, versión ${d.ritVersion},
    vigente desde el ${d.ritFecha}. Las horas trabajadas en sobretiempo serán
    voluntarias para ${colaborador} y se remunerarán con un recargo de
    veinticinco por ciento (25%) por las dos primeras horas y treinta y cinco por
    ciento (35%) por las horas restantes, conforme al artículo 10 del Decreto
    Supremo N.° 007-2002-TR, independientemente de que cuenten con autorización
    previa.</p>`;
}

function clausulaRemuneracion(d: DatosContrato): string {
  const colaborador = etiquetaColaborador(d);
  return `
    <h3>SEXTA. REMUNERACIÓN</h3>
    <p>La remuneración mensual base de ${colaborador} es de S/ ${soles(d.remuneracionMensual)}
    (${numeroALetras(d.remuneracionMensual)} soles), no menor a la Remuneración
    Mínima Vital vigente. Sobre esta base, LA EMPRESA abona a ${colaborador} el
    monto proporcional a las horas efectivamente laboradas en cada período, conforme
    al registro de asistencia, sujeto a los descuentos de ley.</p>
    <p>El pago se realizará mediante depósito bancario dentro de los primeros
    cinco (05) días hábiles del mes siguiente al período laborado.</p>
    <p>Los bonos o incentivos variables tendrán carácter discrecional y no
    constituirán derecho adquirido ni remuneración computable, salvo que por su
    naturaleza, habitualidad y condiciones sean calificados como tales por la
    ley.</p>`;
}

function clausulaBeneficios(d: DatosContrato): string {
  const colaborador = etiquetaColaborador(d);
  const movilidad = d.cobraMovilidad
    ? `<li><strong>Movilidad:</strong> LA EMPRESA otorga a ${colaborador} una
       asignación diaria de movilidad conforme a la tarifa vigente para su sede
       (S/ ${soles(d.movilidadDiaria ?? 0)} a la fecha de este contrato), sujeta a la
       política de movilidad de la empresa y al convenio individual de ruta y
       gasto de transporte que ${colaborador} suscribe por separado, conforme al
       artículo 19 inciso e) del Decreto Supremo N.° 001-97-TR y al artículo 28
       del Reglamento Interno de Trabajo.</li>`
    : `<li><strong>Movilidad:</strong> no aplica a ${colaborador} a la fecha de
       este contrato.</li>`;

  return `
    <h3>SÉPTIMA. BENEFICIOS LABORALES</h3>
    <p>El presente contrato se rige por el Régimen Laboral Especial de la Pequeña
    Empresa, conforme al Texto Único Ordenado de la Ley de Impulso al Desarrollo
    Productivo y al Crecimiento Empresarial (Ley MYPE), aprobado por Decreto
    Supremo N.° 013-2013-PRODUCE, y su Reglamento aprobado por Decreto Supremo
    N.° 008-2008-TR, correspondiendo a ${colaborador} los siguientes derechos:</p>
    <ol type="a">
      <li><strong>Compensación por Tiempo de Servicios (CTS):</strong> Equivalente
      a quince (15) remuneraciones diarias por cada año completo de servicios, con
      un tope de noventa (90) remuneraciones diarias, depositada en los plazos
      establecidos por ley.</li>
      <li><strong>Gratificaciones legales:</strong> Dos (2) gratificaciones al
      año, en julio y en diciembre, cada una equivalente al cincuenta por ciento
      (50%) de la remuneración computable. Adicionalmente, LA EMPRESA pagará a ${colaborador} una bonificación extraordinaria equivalente al nueve por ciento
      (9%) de cada gratificación, conforme a la Ley N.° 30334, inafecta a
      contribuciones.</li>
      <li><strong>Vacaciones:</strong> Quince (15) días calendario de descanso
      vacacional por cada año completo de servicios, conforme al régimen laboral
      especial de la pequeña empresa regulado por el Decreto Supremo N.°
      013-2013-PRODUCE, siéndole de aplicación supletoria el Decreto Legislativo
      N.° 713 en lo que corresponda.</li>
      <li><strong>Afiliación a EsSalud:</strong> LA EMPRESA aportará el nueve por
      ciento (9%) de la remuneración mensual de ${colaborador} al Seguro Social
      de Salud (EsSalud).</li>
      <li><strong>Afiliación al sistema previsional:</strong> ${colaborador}
      ejercerá su derecho a elegir entre el Sistema Privado de Pensiones (SPP) o
      el Sistema Nacional de Pensiones (SNP).</li>
      <li><strong>Asignación familiar:</strong> LA EMPRESA otorga a ${colaborador}, como mejora voluntaria por encima de los beneficios mínimos
      del régimen laboral especial de la pequeña empresa, una asignación familiar
      equivalente al diez por ciento (10%) de la Remuneración Mínima Vital
      vigente, en caso de que ${colaborador} acredite tener hijos menores de
      dieciocho (18) años, o mayores con discapacidad. Para tal efecto se toma
      como referencia el parámetro previsto en la Ley N.° 25129. La acreditación
      deberá realizarse mediante la presentación de la partida de nacimiento
      correspondiente ante LA EMPRESA. El derecho a esta asignación se genera a
      partir del mes en que se acredite fehacientemente dicha condición, sin
      efecto retroactivo.</li>
      <li><strong>Seguro de Vida:</strong> ${colaborador} tendrá derecho a
      seguro de vida conforme al Decreto Legislativo N.° 688 y sus normas
      modificatorias, así como al régimen laboral especial de la pequeña empresa
      (Decreto Supremo N.° 013-2013-PRODUCE), en las condiciones y desde el
      momento que determine la ley aplicable.</li>
      ${movilidad}
      <li><strong>Asignación por educación:</strong> LA EMPRESA otorga, conforme
      a su política de asignación por educación vigente, una cobertura parcial de
      los gastos de estudios de ${colaborador} o de sus hijos, contra la
      presentación del comprobante correspondiente y sujeta a los topes y
      condiciones de dicha política. No genera derecho adquirido: rige mientras
      ${colaborador} mantenga vigente el estudio acreditado.</li>
      <li><strong>Bono de onomástico:</strong> LA EMPRESA otorga a ${colaborador}, en el mes de su cumpleaños, un bono de S/ ${soles(d.bonoOnomastico)}
      (monto vigente a la fecha de este contrato, conforme al artículo 19 inciso
      g) del Decreto Supremo N.° 001-97-TR), sujeto a la política de la empresa y
      a la constancia de entrega correspondiente.</li>
    </ol>`;
}

/**
 * ¿Este contrato ESTRENA la relación laboral, o continúa una que ya existe?
 *
 * Vive acá, pegada a `clausulaPeriodoPrueba`, porque es la pregunta que esa
 * cláusula responde — y responderla mal no cambia una etiqueta, cambia lo que
 * la persona firma. Un contrato «nuevo» abre un período de prueba de tres meses
 * en el que «cualquiera de las partes podrá resolver el contrato sin expresión
 * de causa y sin derecho a indemnización»; ponerle eso a quien lleva años
 * trabajando le quita por escrito la estabilidad que el artículo 79 del TUO del
 * D. Leg. 728 ya le reconoce.
 *
 * La pantalla lo decidía por si el generador tenía una fila de esa persona, y
 * el generador se estrenó en agosto de 2026: no tenía fila NADIE, así que las
 * veinte renovaciones de fin de año habrían salido como contratos nuevos.
 * «Tener fila en este sistema» nunca fue la pregunta.
 *
 * `fechaIngreso` ausente ⇒ renovación: sin dato, la opción segura es la que NO
 * le quita un derecho a nadie.
 */
export function tipoQueCorresponde(
  fechaIngreso: string | null | undefined,
  hoy: string,
): "nuevo" | "renovacion" {
  if (!fechaIngreso) return "renovacion";
  return fechaIngreso > hoy ? "nuevo" : "renovacion";
}

function clausulaPeriodoPrueba(d: DatosContrato): string {
  const colaborador = etiquetaColaborador(d);
  if (d.tipo !== "nuevo") {
    // ¿HA CORRIDO DE VERDAD EL PERÍODO DE PRUEBA?
    //
    // Decir «ya superó el período de prueba» es afirmar un HECHO, y el
    // generador lo afirmaba de cualquiera cuya fecha de ingreso fuera anterior
    // a hoy — incluida quien entró hace tres semanas con un contrato corto y
    // recibe el siguiente enseguida. El período de prueba del artículo 10 de la
    // LPCL corre TRES MESES desde el inicio de la relación laboral: renovar no
    // lo reinicia, pero tampoco lo completa.
    //
    // Se mide contra el inicio de ESTE contrato, que es la fecha desde la que
    // el documento habla. Si a esa fecha los tres meses no se han cumplido, el
    // contrato dice la verdad —sigue corriendo, y desde cuándo— en vez de
    // regalar una estabilidad que la ley todavía no reconoce.
    const fin = finDelPeriodoDePrueba(d.fechaIngresoOriginal);
    if (fin > d.fechaInicio) {
      return `
    <h3>TERCERA. PERÍODO DE PRUEBA</h3>
    <p>El período de prueba de tres (3) meses previsto en el artículo 10 del TUO
    del Decreto Legislativo N.° 728 se computa desde el inicio de la relación
    laboral de ${colaborador}, ocurrido el ${formatearFecha(d.fechaIngresoOriginal)},
    y NO se reinicia con la celebración del presente contrato. En consecuencia,
    dicho período culmina el ${formatearFecha(fin)}. Superada esa fecha, ${colaborador} gozará de estabilidad laboral durante la vigencia del presente
    contrato conforme al artículo 79 del mismo cuerpo legal.</p>`;
    }
    return `
    <h3>TERCERA. PERÍODO DE PRUEBA</h3>
    <p>No aplica un nuevo período de prueba: ${colaborador} ya superó el período
    de prueba correspondiente a su vínculo laboral iniciado el
    ${formatearFecha(d.fechaIngresoOriginal)}, y goza de estabilidad laboral
    durante la vigencia del presente contrato conforme al artículo 79 del TUO del
    Decreto Legislativo N.° 728.</p>`;
  }
  return `
    <h3>TERCERA. PERÍODO DE PRUEBA</h3>
    <p>El período de prueba es de tres (3) meses, contados a partir de la fecha
    de inicio del presente contrato. Durante dicho período, cualquiera de las
    partes podrá resolver el contrato sin expresión de causa y sin derecho a
    indemnización. Superado el período de prueba, ${colaborador} gozará de
    estabilidad laboral durante la vigencia del contrato conforme al artículo 79
    del TUO del Decreto Legislativo N.° 728.</p>`;
}

/**
 * El día en que se cumplen los tres meses del artículo 10 de la LPCL.
 *
 * Se calcula sumando meses de calendario, no 90 días: la ley cuenta meses. Y en
 * UTC a propósito — estas son fechas de calendario («2026-08-01»), no instantes,
 * así que construirlas en la hora local del navegador podría correrlas un día.
 */
export function finDelPeriodoDePrueba(fechaIngreso: string): string {
  const d = new Date(`${fechaIngreso}T00:00:00Z`);
  const dia = d.getUTCDate();
  d.setUTCMonth(d.getUTCMonth() + 3);
  // Si el día no existe en el mes destino (31 de noviembre), Date se pasa al
  // mes siguiente; se retrocede al último día del mes que corresponde.
  if (d.getUTCDate() !== dia) d.setUTCDate(0);
  return d.toISOString().slice(0, 10);
}

/**
 * PRIMERA (naturaleza) + SEGUNDA (plazo/vigencia) del contrato de trabajo —
 * la única parte que distingue de verdad un plazo fijo de un indefinido
 * (0347). El resto del cuerpo (jornada, remuneración, beneficios, período de
 * prueba, disciplina, anexos) es el mismo régimen laboral común para
 * cualquiera de los dos, y se reutiliza sin cambios.
 */
function clausulaNaturalezaYPlazo(d: DatosContrato): string {
  if (d.tipo === "indefinido") {
    return `
    <h3>PRIMERA. NATURALEZA</h3>
    <p>El presente contrato se celebra a plazo indeterminado, dentro del régimen general de contratación
    laboral del Texto Único Ordenado del Decreto Legislativo N.° 728, aprobado por Decreto Supremo N.°
    003-97-TR — no requiere causa objetiva ni modalidad temporal alguna.</p>

    <h3>SEGUNDA. VIGENCIA</h3>
    <p>El contrato inicia el ${formatearFecha(d.fechaInicio)}, sin fecha de término, y se mantiene vigente
    en tanto no se extinga por alguna de las causales previstas en el artículo 16 del TUO del Decreto
    Legislativo N.° 728.</p>`;
  }
  return `
    <h3>PRIMERA. NATURALEZA, MODALIDAD Y CAUSA OBJETIVA</h3>
    <p>El presente contrato se celebra bajo la modalidad de Contrato Temporal por Inicio o Incremento de Actividad,
    conforme al artículo 57 del Texto Único Ordenado del Decreto Legislativo N.° 728, aprobado por Decreto Supremo
    N.° 003-97-TR.</p>
    <p>${d.causaObjetivaTexto}</p>
    <p>El vínculo laboral generado por el presente contrato es de duración determinada y no genera estabilidad
    laboral indefinida.</p>

    <h3>SEGUNDA. PLAZO</h3>
    <p>El contrato inicia el ${formatearFecha(d.fechaInicio)} y culmina el ${formatearFecha(d.fechaFin)}, fecha en
    la cual quedará extinguido automáticamente sin necesidad de comunicación previa, salvo renovación expresa por
    escrito.</p>`;
}

/**
 * DÉCIMA OCTAVA — ya no distingue por tipo. Hasta la 0470 el plazo fijo y el
 * convenio de prácticas prometían además "comunicarlo a la Autoridad
 * Administrativa de Trabajo dentro de los quince (15) días naturales": una
 * obligación derogada desde el 2016-11-11 (D. Leg. 1246 modificó el art. 73
 * del D.S. 003-97-TR para plazo fijo, y derogó el último párrafo del art. 46
 * de la Ley 28518 para convenios). Seguir imprimiéndola era prometerle a
 * quien firma un trámite que la empresa ya no hace ni tiene dónde hacer — se
 * declara solo con la Planilla Electrónica, sin esta comunicación aparte.
 */
function clausulaEntregaCopia(d: DatosContrato): string {
  const colaborador = etiquetaColaborador(d);
  return `
    <h3>DÉCIMA OCTAVA. ENTREGA DE COPIA</h3>
    <p>LA EMPRESA entregará a ${colaborador} copia del presente contrato dentro de los tres (3) días hábiles
    siguientes al inicio de la prestación de servicios.</p>`;
}

/** VIGÉSIMA — la indemnización de un indefinido se cuenta por años de servicio (art. 38), no por meses restantes de plazo (art. 76). Ver 0347. */
function clausulaTerminacion(d: DatosContrato): string {
  const colaborador = etiquetaColaborador(d);
  if (d.tipo === "indefinido") {
    return `
    <h3>VIGÉSIMA. TERMINACIÓN</h3>
    <p>El contrato se extingue por las causales previstas en el artículo 16 del TUO del Decreto Legislativo N.°
    728: renuncia voluntaria de ${colaborador} (con treinta (30) días de anticipación, salvo exoneración por LA
    EMPRESA), mutuo disenso, jubilación, invalidez absoluta permanente, o comisión de falta grave u otra causa
    justa de despido debidamente comprobada conforme a los artículos 22 a 25 del mismo cuerpo legal.</p>
    <p>Si LA EMPRESA pusiera fin al contrato sin la existencia de causa justa, corresponderá a ${colaborador} la
    indemnización equivalente a una remuneración y media (1.5) ordinaria mensual por cada año completo de
    servicios, con las fracciones de año computadas por dozavos y treintavos, y con un tope de doce (12)
    remuneraciones, conforme al artículo 38 del TUO del Decreto Legislativo N.° 728.</p>`;
  }
  return `
    <h3>VIGÉSIMA. TERMINACIÓN</h3>
    <p>El contrato finalizará automáticamente en la fecha pactada o podrá resolverse anticipadamente por mutuo
    acuerdo, renuncia voluntaria de ${colaborador} (con treinta (30) días de anticipación), comisión de falta
    grave, o resolución anticipada sin causa justa por parte de LA EMPRESA — caso en el cual corresponderá la
    indemnización equivalente a una remuneración y media (1.5) por cada mes dejado de laborar hasta el término del
    contrato, con el límite de doce (12) remuneraciones, conforme al artículo 76 del TUO del Decreto Legislativo
    N.° 728.</p>`;
}

function clausulaDisciplina(d: DatosContrato): string {
  const colaborador = etiquetaColaborador(d);
  return `
    <h3>DÉCIMA CUARTA. RÉGIMEN DISCIPLINARIO</h3>
    <p>Las sanciones podrán consistir en llamada de atención verbal, amonestación
    escrita, suspensión sin goce de haber o resolución del contrato por falta
    grave, conforme a los artículos 25, 31 y 32 del TUO del Decreto Legislativo
    N.° 728 y al Reglamento Interno de Trabajo, versión ${d.ritVersion}, vigente
    desde el ${d.ritFecha} — cuya entrega y acuse constan, conforme a su artículo
    60, en el sistema Dynamic o por los demás medios ahí previstos.</p>
    <p>Para el caso del procedimiento previo al despido, LA EMPRESA otorgará a ${colaborador}, mediante carta escrita, un plazo no menor a seis (6) días
    naturales para que ejerza su derecho de defensa por escrito respecto a los
    cargos que se le formulen, conforme al artículo 31 del TUO del Decreto
    Legislativo N.° 728. Sin perjuicio de las medidas inmediatas de protección
    operativa que correspondan, el procedimiento previo al despido se cumplirá
    íntegramente en todos los casos.</p>
    <p>Cuando la causa invocada sea de naturaleza relacionada con la capacidad de
    ${colaborador} —en particular, rendimiento deficiente conforme al artículo
    23, inciso b), del TUO del Decreto Legislativo N.° 728—, el plazo otorgado
    será de treinta (30) días naturales para que ${colaborador} demuestre su
    capacidad o corrija su deficiencia, conforme al segundo supuesto del artículo
    31 del mismo cuerpo normativo. En estos casos, LA EMPRESA podrá solicitar el
    concurso de la Autoridad Administrativa de Trabajo conforme al artículo 34 del
    Reglamento aprobado por Decreto Supremo N.° 001-96-TR.</p>`;
}

function anexoIV(d: DatosContrato, etiquetaPersona = etiquetaColaborador(d)): string {
  return `
    <section class="anexo">
    ${encabezadoAnexo(
      d,
      "ANEXO IV — CONSTANCIA DE RECEPCIÓN Y RESPONSABILIDAD DE ACTIVOS",
      d.tipo === "convenio_practicas"
        ? "Cláusula del presente convenio sobre custodia de activos"
        : "Cláusula Octava del presente contrato",
    )}
    <p>${etiquetaPersona} deja constancia de la recepción de los bienes de
    propiedad de LA EMPRESA que se detallan a continuación, correspondientes a
    la sede ${d.sedeNombre} y asignados para el ejercicio de sus funciones y
    bajo su custodia:</p>
    <p><strong>Activos principales de la sede:</strong> ${d.activosPrincipales}</p>
    <p><strong>Ajuste específico para esta persona:</strong></p>
    ${
      d.activosLibre
        ? // Mismo tratamiento que el Anexo I, y por la misma razón: una lista
          // de equipos con su número de serie se cita («el bien 3 del Anexo
          // IV») cuando hay que reclamar la devolución de uno.
          listaDesdeTexto(d.activosLibre)
        : `<p>${etiquetaPersona} no tiene activos adicionales bajo su custodia, más allá de los generales de la sede detallados líneas arriba.</p>`
    }
    <p>Todos los bienes detallados son de propiedad exclusiva de LA EMPRESA y se
    entregan únicamente para el desempeño de las funciones de ${etiquetaPersona}.
    ${etiquetaPersona} se obliga a custodiarlos y conservarlos con la diligencia
    debida, y a devolverlos al término del vínculo por cualquier causa, en buen
    estado de conservación salvo el desgaste natural por uso normal.</p>
    ${pieAnexo(d, etiquetaPersona)}
    </section>`;
}

/**
 * El adendum: un documento CORTO que modifica el contrato vigente y deja todo
 * lo demás en pie. No repite el contrato ni sus anexos — repetirlos crearía dos
 * documentos que dicen ser el mismo vínculo, y el segundo, al llevar su propio
 * plazo y su propio período de prueba, contradiría al primero.
 */
function documentoAdendum(d: DatosContrato): string {
  const esConvenio = d.esPracticante;
  const colaborador = esConvenio
    ? segunGenero(d, "EL PRACTICANTE", "LA PRACTICANTE")
    : etiquetaColaborador(d);
  const documento = esConvenio ? "convenio de modalidad formativa" : "contrato de trabajo";
  const presente = esConvenio ? "documento" : "adendum";
  const modalidad =
    d.practicanteModalidad === "preprofesional"
      ? "prácticas preprofesionales"
      : d.practicanteModalidad === "profesional"
        ? "prácticas profesionales"
        : "prácticas";
  const antecedente = esConvenio
    ? `Ambas partes mantienen vigente un convenio de modalidad formativa (Ley N.° 28518) por el cual ${colaborador}
    realiza ${modalidad} como ${d.cargo} en la sede ${d.sedeNombre}, iniciado el
    ${formatearFecha(d.fechaIngresoOriginal)}.`
    : `Ambas partes mantienen vigente un contrato de trabajo por el cual ${colaborador} se
    desempeña como ${d.cargo} en la sede ${d.sedeNombre}, cuyo vínculo laboral se inició el
    ${formatearFecha(d.fechaIngresoOriginal)}.`;
  return `
  <article class="contrato">
    <header>
      <p class="empresa">${EMPRESA.nombre}</p>
      <p class="ruc">RUC N.° ${EMPRESA.ruc} · Sede ${d.sedeNombre}</p>
      <h1>${esConvenio ? "ADENDA AL CONVENIO DE MODALIDAD FORMATIVA" : "ADENDUM AL CONTRATO DE TRABAJO"}</h1>
    </header>

    <p>En ${enLaCiudadDe(d)}, al ${formatearFecha(d.fechaInicio)}, comparecen de una parte
    ${EMPRESA.nombre}, identificada con R.U.C. N.° ${EMPRESA.ruc}, con domicilio legal en
    ${EMPRESA.domicilio}, debidamente representada por ${d.firmanteNombre}, identificado(a) con
    D.N.I. N.° ${d.firmanteDni}, a quien en adelante se denominará LA EMPRESA; y de la otra parte
    ${d.nombreDni}, ${segunGenero(d, "identificado", "identificada")} con D.N.I. N.° ${d.documento}, a quien en adelante se denominará
    ${colaborador}.</p>

    <h3>PRIMERA. ANTECEDENTE</h3>
    <p>${antecedente}</p>

    <h3>${esConvenio ? "SEGUNDA. OBJETO DE LA ADENDA" : "SEGUNDA. OBJETO DEL ADENDUM"}</h3>
    <p>Por el presente documento, las partes acuerdan modificar el ${esConvenio ? documento : "contrato"} indicado en la
    cláusula precedente en los siguientes términos:</p>
    ${listaDesdeTexto(d.adendumTexto)}

    <h3>TERCERA. VIGENCIA</h3>
    <p>Lo acordado en el presente ${presente} rige desde el ${formatearFecha(d.fechaInicio)}.</p>

    <h3>CUARTA. SUBSISTENCIA DE LO NO MODIFICADO</h3>
    <p>Todas las demás cláusulas del ${documento} y de sus anexos que no hayan sido
    expresamente modificadas por el presente ${presente} mantienen plena vigencia y continúan
    obligando a las partes en sus mismos términos.${
      esConvenio
        ? ` El presente documento no modifica la naturaleza formativa del convenio ni genera relación laboral entre las partes.`
        : ""
    }</p>

    <p>En señal de conformidad, las partes suscriben el presente ${presente} en ${enLaCiudadDe(d)}, el
    ${formatearFecha(d.fechaInicio)}, en tres (3) ejemplares de igual tenor.</p>

    ${bloqueFirmas(d, colaborador)}
    <p class="pie-hoja">${EMPRESA.nombre} · RUC N.° ${EMPRESA.ruc}</p>
  </article>`;
}

/**
 * Los ordinales de las cláusulas del convenio, EN ORDEN. Un preprofesional y
 * un profesional no tienen el mismo número de cláusulas —el preprofesional
 * suma "OBLIGACIONES DEL CENTRO DE FORMACIÓN", que el profesional no lleva
 * (0348, ver `documentoConvenio`)— así que el título de cada cláusula sale de
 * SU POSICIÓN en el arreglo que arma `documentoConvenio`, nunca escrito a
 * mano: escribirlo a mano es exactamente lo que desalinea un "DÉCIMA" con el
 * "9." que un lector cuenta al lado.
 */
const ORDINALES_CONVENIO = [
  "PRIMERA", "SEGUNDA", "TERCERA", "CUARTA", "QUINTA", "SEXTA", "SÉPTIMA",
  "OCTAVA", "NOVENA", "DÉCIMA", "DÉCIMA PRIMERA", "DÉCIMA SEGUNDA",
  "DÉCIMA TERCERA", "DÉCIMA CUARTA", "DÉCIMA QUINTA", "DÉCIMA SEXTA",
  "DÉCIMA SÉTIMA", "DÉCIMA OCTAVA", "DÉCIMA NOVENA",
];

/**
 * El convenio de modalidad formativa (Ley N.° 28518) para tipo_vinculo =
 * 'practicante' (0322/0333) — NO un contrato de trabajo. Documento aparte
 * desde el encabezado, igual que `documentoAdendum`: no es una rama dentro
 * de las cláusulas de planilla, porque casi ninguna le queda bien (0322 y el
 * encabezado de la 0333 detallan por qué). El tono y las cuatro promesas
 * legales centrales —no es contrato de trabajo, jornada según modalidad,
 * es una subvención no una remuneración, no genera beneficios laborales— son
 * las mismas que ya lee la practicante en su "Constancia de subvención"
 * (boleta, PR #98): un documento no puede prometer lo que el otro niega.
 *
 * Reescrito en la 0348 sobre el modelo de referencia de Desarrollo
 * Organizacional (`CAYLA_CORP_CONT_202609_ConvenioPracticas.docx`, sep-2026),
 * que trae la diferencia de fondo que la versión anterior no modelaba: **el
 * preprofesional es TRIPARTITO** —CAYLA, el centro de formación y la
 * practicante firman los tres, art. 12 y ss. de la Ley 28518— y **el
 * profesional es BIPARTITO** —CAYLA y la practicante; el centro que la
 * presenta es solo una referencia, no firma. De ahí en más, las cláusulas se
 * arman en un arreglo común y solo una —OBLIGACIONES DEL CENTRO DE
 * FORMACIÓN— se agrega condicionalmente para el preprofesional; ver
 * `ORDINALES_CONVENIO`.
 */
function documentoConvenio(d: DatosContrato): string {
  const etiquetaPracticante = segunGenero(d, "EL PRACTICANTE", "LA PRACTICANTE");
  const identificadoTexto = segunGenero(d, "identificado", "identificada");
  const horasMax = maximoSemanalPracticante("practicante", d.practicanteModalidad);
  const esPreprofesional = d.practicanteModalidad !== "profesional";
  const modalidadTexto = d.practicanteModalidad === "profesional" ? "PROFESIONALES" : "PREPROFESIONALES";
  const numPartes = esPreprofesional ? "tres (3)" : "dos (2)";

  // ── CUÁNTAS HORAS DE VERDAD, Y QUÉ LE TOCA DE RMV POR ESO (auditoría 2026-09-14) ──
  //
  // El artículo 45 de la Ley 28518 no compara contra 48h a secas: compara
  // contra "la jornada máxima prevista para CADA modalidad formativa" — 30h
  // para preprofesional (art. 44), no 48h. Una preprofesional que cumple sus
  // 30h YA está en el tope de SU modalidad, así que le toca una RMV completa,
  // sin prorratear; el prorrateo del artículo 45 solo aplica a quien trabaja
  // MENOS que el tope de su propia modalidad. Solo el preprofesional admite
  // esto: el profesional siempre se asume a su jornada completa (48h), no hay
  // un caso real hoy de un profesional a tiempo parcial.
  const horasPactadas = esPreprofesional ? (d.horasSemanalesPactadas ?? horasMax) : horasMax;
  const jornadaReducida = esPreprofesional && horasMax !== null && horasPactadas !== null && horasPactadas < horasMax;
  const pisoSubvencion =
    jornadaReducida && d.rmvVigente !== null && horasMax !== null && horasPactadas !== null
      ? (d.rmvVigente * horasPactadas) / horasMax
      : null;

  const horasTexto =
    horasMax === null
      ? `<strong>[FALTA ASIGNAR LA MODALIDAD DE ${etiquetaPracticante} EN EQUIPO — preprofesional (30h) o profesional
        (48h), art. 44 Ley N.° 28518, antes de imprimir este convenio]</strong>`
      : jornadaReducida
        ? `es de ${horasPactadas} horas semanales, dentro del máximo de seis (6) horas diarias y treinta (30) horas
        semanales previsto en el artículo 44 de la Ley N.° 28518 para la modalidad preprofesional`
        : `no excederá de ${
            horasMax === 30 ? "seis (6) horas diarias ni treinta (30) horas semanales" : "ocho (8) horas diarias ni cuarenta y ocho (48) horas semanales"
          }, conforme al artículo 44 de la Ley N.° 28518`;

  const representanteCentroTexto = d.centroFormacionRepresentanteNombre
    ? `${d.centroFormacionRepresentanteNombre}${
        d.centroFormacionRepresentanteCargo ? `, en su calidad de ${d.centroFormacionRepresentanteCargo}` : ""
      }`
    : "[completar]";

  const datosCentro = esPreprofesional
    ? `
    <h3>II. DATOS DEL CENTRO DE FORMACIÓN PROFESIONAL</h3>
    <p>${d.centroFormacionNombre ?? "[completar — razón social del centro de formación]"}, identificado con
    R.U.C. N.° ${d.centroFormacionRuc ?? "[completar]"}, con domicilio en
    ${d.centroFormacionDomicilio ?? "[completar]"}, representado por
    ${representanteCentroTexto}, a quien en adelante se denominará EL CENTRO DE FORMACIÓN
    PROFESIONAL.</p>`
    : "";

  const datosAcademicos = esPreprofesional
    ? `<p>Carrera / especialidad: ${d.carreraEspecialidad ?? "[completar]"}. Ciclo académico:
       ${d.cicloAcademico ?? "[completar]"}.</p>`
    : `<p>${d.gradoTituloTexto ?? "[completar — grado/título y universidad de egreso]"}.</p>`;

  // ── Las cláusulas, en el orden en que se numeran. Ver ORDINALES_CONVENIO. ──
  const clausulas: string[] = [
    `<h3>{{N}}. OBJETO</h3>
    <p>${etiquetaPracticante} realizará su Práctica ${esPreprofesional ? "Preprofesional" : "Profesional"} para
    ${
      esPreprofesional
        ? "aplicar los conocimientos, habilidades y aptitudes adquiridos durante su formación, en una situación real de trabajo. LA EMPRESA colabora con EL CENTRO DE FORMACIÓN PROFESIONAL en esta tarea formativa"
        : "consolidar los aprendizajes adquiridos durante su formación profesional y ejercitar su desempeño en una situación real de trabajo"
    }.</p>`,

    `<h3>{{N}}. ÁREA Y ACTIVIDADES FORMATIVAS</h3>
    <p>${etiquetaPracticante} desarrollará actividades formativas en el área de ${d.areaProyecto || "[completar]"}, en el
    puesto de ${d.cargo}, en la sede ${d.sedeNombre}, conforme al Plan Específico de Aprendizaje que se detalla en
    el ANEXO I, el cual forma parte integrante del presente convenio (Ley N.° 28518, artículo 15).</p>`,

    `<h3>{{N}}. JORNADA</h3>
    <p>La jornada de ${etiquetaPracticante} ${horasTexto}. Los horarios serán determinados por LA EMPRESA de acuerdo a sus
    necesidades operativas, dentro del máximo establecido en este párrafo, y compatibles con las obligaciones
    académicas de ${etiquetaPracticante} cuando corresponda.</p>
    <p>Que LA EMPRESA supervise, oriente y evalúe el desarrollo de las prácticas es parte propia de la modalidad
    formativa (Ley N.° 28518, artículo 8) y no constituye, por sí sola, indicio de subordinación laboral.</p>`,

    `<h3>{{N}}. DURACIÓN</h3>
    <p>El convenio inicia el ${formatearFecha(d.fechaInicio)} y culmina el ${formatearFecha(d.fechaFin)}, fecha en
    la cual quedará extinguido automáticamente sin necesidad de comunicación previa, salvo renovación expresa por
    escrito${esPreprofesional ? ", por un periodo proporcional a la duración de la formación" : ", por un periodo máximo de doce (12) meses"}.</p>
    <p>Las partes dejan constancia de que la duración de la modalidad formativa no debe exceder de doce (12) meses
    continuos, salvo que el centro de formación profesional determine, por norma o reglamento propio, una extensión
    mayor — en cuyo caso deberá sustentarse por escrito. Superar dicho plazo sin sustento arriesga que la relación se
    considere desnaturalizada, con las consecuencias laborales que ello implica.</p>`,

    `<h3>{{N}}. SUBVENCIÓN ECONÓMICA</h3>
    <p>LA EMPRESA otorga a ${etiquetaPracticante} una subvención económica mensual de S/ ${soles(d.remuneracionMensual)}
    (${numeroALetras(d.remuneracionMensual)} soles)${
      jornadaReducida
        ? pisoSubvencion !== null
          ? `, no menor a S/ ${soles(pisoSubvencion)} — monto proporcional de la Remuneración Mínima Vital vigente
             (S/ ${soles(d.rmvVigente as number)}) según las ${horasPactadas} horas semanales pactadas frente al
             máximo de treinta (30) horas de su modalidad`
          : `, no menor al monto proporcional de la Remuneración Mínima Vital vigente según las ${horasPactadas}
             horas semanales pactadas frente al máximo de treinta (30) horas de su modalidad —
             <strong>[FALTA PUBLICAR LA RMV VIGENTE EN EL SISTEMA]</strong>`
        : `, no menor a la Remuneración Mínima Vital vigente${esPreprofesional ? "" : " para una jornada completa"}`
    } (Ley N.° 28518, artículo 45). La subvención económica <strong>no constituye remuneración</strong>, no está
    sujeta a descuentos, aportes ni retención del impuesto a la renta de cuarta ni de quinta categoría. El pago se
    realiza mediante depósito bancario dentro de los primeros cinco (05) días hábiles del mes siguiente al período
    de prácticas.</p>
    <p>Adicionalmente, LA EMPRESA: (a) otorga una subvención adicional equivalente a media (1/2) subvención mensual
    por cada seis (6) meses continuos de duración del convenio; (b) otorga un descanso de quince (15) días
    debidamente subvencionado si la práctica supera los doce (12) meses continuos; y (c) otorga descanso semanal y
    feriados no laborables debidamente subvencionados (Ley N.° 28518, artículos 42.4 y 45).</p>`,

    `<h3>{{N}}. SEGURO</h3>
    <p>LA EMPRESA cubre los riesgos de enfermedad y accidentes de ${etiquetaPracticante} mediante su afiliación a EsSalud
    (Ley N.° 28518, artículo 42.8) — decisión propia de LA EMPRESA, que no le corresponde por defecto a toda
    modalidad formativa. De optar en su lugar por un seguro privado, la cobertura no será menor a catorce (14)
    subvenciones mensuales en caso de enfermedad y treinta (30) en caso de accidente, conforme al artículo 43 de la
    misma ley.</p>`,

    `<h3>{{N}}. OBLIGACIONES DE LA EMPRESA</h3>
    <p>LA EMPRESA se obliga a:</p>
    <ul>
      ${
        esPreprofesional
          ? `<li>Brindar orientación y capacitación técnica dentro del área de formación de ${etiquetaPracticante}.</li>`
          : "<li>Proporcionar la dirección técnica y los medios necesarios para la formación en la actividad materia del convenio.</li>"
      }
      <li>Designar un(a) supervisor(a) que oriente y verifique el cumplimiento del Plan Específico de Aprendizaje.</li>
      ${
        esPreprofesional
          ? "<li>Emitir los informes que requiera EL CENTRO DE FORMACIÓN PROFESIONAL.</li><li>No cobrar suma alguna por la formación recibida.</li>"
          : ""
      }
      <li>Pagar puntualmente la subvención pactada.</li>
      <li>Registrar el presente convenio ante el Ministerio de Trabajo y Promoción del Empleo dentro de los quince (15) días de suscrito.</li>
      <li>Expedir el certificado de prácticas al finalizar el convenio.</li>
    </ul>`,

    `<h3>{{N}}. OBLIGACIONES DE ${etiquetaPracticante}</h3>
    <p>${etiquetaPracticante} se obliga a:</p>
    <ul>
      <li>Desarrollar sus prácticas con disciplina y responsabilidad.</li>
      <li>Cumplir el Plan Específico de Aprendizaje.</li>
      <li>${
        esPreprofesional
          ? "Sujetarse a las disposiciones administrativas internas de LA EMPRESA."
          : "Acatar las disposiciones formativas que le asigne LA EMPRESA y observar las normas y reglamentos internos de LA EMPRESA."
      }</li>
      <li>Guardar reserva sobre la información confidencial de LA EMPRESA a la que tenga acceso durante las prácticas.</li>
    </ul>`,

    `<h3>{{N}}. LO QUE ESTE CONVENIO NO GENERA</h3>
    <p>Por no tratarse de una relación laboral, el presente convenio <strong>no genera</strong> vínculo laboral,
    gratificaciones, Compensación por Tiempo de Servicios (CTS), vacaciones proporcionales, ni aporte a un sistema
    pensionario (AFP u ONP) — salvo que ${etiquetaPracticante} decida afiliarse voluntariamente, en cuyo caso el aporte
    corre por su cuenta (Ley N.° 28518, artículo 47).</p>`,

    `<h3>{{N}}. NO SUJECIÓN AL REGLAMENTO INTERNO DE TRABAJO</h3>
    <p>Conforme al numeral 2.6 del Reglamento Interno de Trabajo de LA EMPRESA (versión ${d.ritVersion}, vigente
    desde el ${d.ritFecha}), ${etiquetaPracticante} no tiene la condición de ${segunGenero(d, "trabajador", "trabajadora")}, no mantiene relación laboral con
    LA EMPRESA y no está comprendida por dicho Reglamento — se rige por el presente convenio y por la Ley N.° 28518.
    Ello no excluye las obligaciones de seguridad y salud en el trabajo, que sí alcanzan a ${etiquetaPracticante} desde el
    primer día conforme al artículo 68 de la Ley N.° 29783, Ley de Seguridad y Salud en el Trabajo.</p>`,

    `<h3>{{N}}. CONDUCTA Y CUSTODIA DE ACTIVOS</h3>
    <p>${etiquetaPracticante} se obliga a mantener conducta ética, respetuosa y acorde a la imagen de LA EMPRESA durante el
    desarrollo de sus prácticas. Los bienes que LA EMPRESA le entregue bajo su custodia se detallan en el
    ANEXO IV — Constancia de Recepción y Responsabilidad de Activos, el cual forma parte integrante del presente
    convenio.</p>`,

    `<h3>{{N}}. USO DE IMAGEN</h3>
    <p>${etiquetaPracticante} autoriza expresamente a LA EMPRESA el uso de su imagen, voz y representación en fotografías o
    videos tomados durante el desarrollo de sus prácticas o en actividades institucionales en la sede
    ${d.sedeNombre}, con fines corporativos o institucionales, sin compensación adicional, respetando siempre su
    dignidad e integridad personal, en los límites de la Ley N.° 29733, Ley de Protección de Datos Personales.</p>`,

    `<h3>{{N}}. CONFIDENCIALIDAD</h3>
    <p>Toda información relacionada con procesos internos, inventarios, proveedores, estrategias comerciales, datos
    de clientes, precios, márgenes, información financiera y cualquier información sensible de LA EMPRESA tiene
    carácter estrictamente confidencial. ${etiquetaPracticante} se obliga a no divulgarla, reproducirla ni utilizarla para
    fines distintos a sus prácticas, durante la vigencia del presente convenio y hasta veinticuatro (24) meses
    después de su culminación.</p>`,

    `<h3>{{N}}. VIDEOVIGILANCIA</h3>
    <p>LA EMPRESA cuenta con sistemas de videovigilancia en las instalaciones del centro de trabajo, debidamente
    señalizados, que operan de forma permanente con fines de seguridad, control operativo y verificación de
    incidencias, conforme a la Ley N.° 29733. ${etiquetaPracticante} declara conocer y aceptar su existencia mediante la
    firma del presente convenio.</p>`,

    // Espeja la cláusula DÉCIMA SÉPTIMA del contrato de trabajo, con las
    // diferencias que impone la Ley N.° 28518: aquí NO hay AFP/ONP —una
    // modalidad formativa no genera aportes previsionales— ni datos
    // «remunerativos», porque la subvención económica no es remuneración y
    // este mismo documento lo subraya dos cláusulas más arriba. Copiar la del
    // contrato tal cual habría metido las dos cosas.
    `<h3>{{N}}. PROTECCIÓN DE DATOS PERSONALES</h3>
    <p>De conformidad con la Ley N.° 29733, Ley de Protección de Datos Personales, y su Reglamento aprobado por
    Decreto Supremo N.° 016-2024-JUS, LA EMPRESA informa a ${etiquetaPracticante} que sus datos personales —incluyendo
    nombre, documento de identidad, domicilio, datos formativos y los relativos a la subvención económica— serán
    incorporados y tratados en los sistemas de LA EMPRESA con las siguientes finalidades exclusivas: (i) gestión del
    presente convenio; (ii) cumplimiento de obligaciones legales ante el Ministerio de Trabajo y Promoción del Empleo,
    EsSalud, el centro de formación profesional y demás autoridades competentes; (iii) comunicaciones internas propias
    de las prácticas; (iv) emisión de constancias, certificados y documentos formativos; y (v) verificación de
    identidad mediante la carga de la copia del Documento Nacional de Identidad (DNI) y constancia de la aceptación de
    los términos del presente convenio.</p>`,

    `<h3>{{N}}. BENEFICIOS ADICIONALES VOLUNTARIOS</h3>
    <p>LA EMPRESA podrá, a su sola discreción, extender a ${etiquetaPracticante} beneficios adicionales no remunerativos
    —como movilidad diaria supeditada a la asistencia o apoyo a estudios— en los mismos términos previstos en el
    artículo 19 del Decreto Supremo N.° 001-97-TR para su personal regular. Su otorgamiento es voluntario, no
    constituye remuneración, no genera derecho adquirido y no modifica la naturaleza formativa ni la ausencia de
    vínculo laboral del presente convenio.</p>`,

    `<h3>{{N}}. DOMICILIO ELECTRÓNICO Y COMUNICACIONES</h3>
    <p>Las partes acuerdan un domicilio electrónico válido para las comunicaciones relacionadas con el presente
    convenio, conforme a los términos del ANEXO III — Domicilio Electrónico y Comunicaciones, el cual forma parte
    integrante del presente convenio.${d.email ? ` El domicilio electrónico de ${etiquetaPracticante} es ${d.email}.` : ""}</p>`,

    `<h3>{{N}}. EXTINCIÓN</h3>
    <p>El convenio se extingue por vencimiento del plazo, mutuo acuerdo, incumplimiento comprobado de las
    obligaciones aquí pactadas, o decisión unilateral de ${etiquetaPracticante}, sin perjuicio de las demás causales
    previstas en el Reglamento. Al no existir relación laboral, la extinción del presente convenio no genera
    indemnización por cese ni beneficios sociales — sin perjuicio de la subvención y demás derechos devengados
    hasta la fecha.</p>`,
  ];

  // OBLIGACIONES DEL CENTRO DE FORMACIÓN: solo el preprofesional la lleva —
  // el profesional no tiene un centro de formación como parte firmante (ver
  // el encabezado de esta función). Se inserta justo después de OBLIGACIONES
  // DE LA PRACTICANTE (índice 7), como NOVENA.
  if (esPreprofesional) {
    clausulas.splice(
      8,
      0,
      `<h3>{{N}}. OBLIGACIONES DEL CENTRO DE FORMACIÓN PROFESIONAL</h3>
    <p>EL CENTRO DE FORMACIÓN PROFESIONAL se obliga a dirigir y supervisar académicamente el desarrollo de las
    prácticas, evaluar y certificar las actividades formativas, y coordinar con LA EMPRESA el monitoreo de
    ${etiquetaPracticante}.</p>`,
    );
  }

  const cuerpoClausulas = clausulas.map((c, i) => c.replace("{{N}}", ORDINALES_CONVENIO[i])).join("\n\n");

  return `
  <article class="contrato">
    <header>
      <p class="empresa">${EMPRESA.nombre}</p>
      <p class="ruc">RUC N.° ${EMPRESA.ruc} · Sede ${d.sedeNombre}</p>
      <h1>CONVENIO DE MODALIDAD FORMATIVA — PRÁCTICAS ${modalidadTexto}</h1>
      <p class="norma">(Ley N.° 28518, Ley sobre Modalidades Formativas Laborales, y su Reglamento aprobado
      por Decreto Supremo N.° 007-2005-TR${esPreprofesional ? " — artículo 12 y siguientes" : ""})</p>
    </header>

    <p>En ${enLaCiudadDe(d)}, al ${formatearFecha(d.fechaInicio)}, se celebra el presente Convenio de
    Modalidad Formativa, que se suscribe por ${esPreprofesional ? "triplicado" : "duplicado"}, entre:</p>

    <h3>I. DATOS DE LA EMPRESA</h3>
    <p>${EMPRESA.nombre}, identificada con R.U.C. N.° ${EMPRESA.ruc}, con domicilio legal en
    ${EMPRESA.domicilio}, debidamente representada por su representante legal, Sr(a). ${d.firmanteNombre},
    identificado(a) con D.N.I. N.° ${d.firmanteDni}, a quien en adelante se denominará LA EMPRESA.</p>
    ${datosCentro}

    <h3>${esPreprofesional ? "III" : "II"}. DATOS DE ${etiquetaPracticante}</h3>
    <p>${d.nombreDni}, ${identificadoTexto} con D.N.I. N.° ${d.documento}${
      d.direccion ? `, con domicilio en ${d.direccion}` : ""
    }, a quien en adelante se denominará ${etiquetaPracticante}.</p>
    ${datosAcademicos}

    <p>Todas las partes declaran expresamente que el presente convenio <strong>no genera relación laboral</strong>
    entre ${etiquetaPracticante} y LA EMPRESA (Ley N.° 28518, artículo 47), y se celebra sin vicios de voluntad.</p>

    ${cuerpoClausulas}

    <p>En señal de conformidad, las partes firman el presente convenio en ${enLaCiudadDe(d)}, el
    ${formatearFecha(d.fechaInicio)}, en ${numPartes} ejemplares de igual tenor.</p>

    ${
      esPreprofesional
        ? bloqueFirmas(d, etiquetaPracticante, {
            etiqueta: "EL CENTRO DE FORMACIÓN PROFESIONAL",
            nombre: d.centroFormacionNombre ?? "[completar]",
            ruc: d.centroFormacionRuc ?? "[completar]",
            representanteNombre: d.centroFormacionRepresentanteNombre ?? "[completar]",
            representanteCargo: d.centroFormacionRepresentanteCargo ?? "",
          })
        : bloqueFirmas(d, etiquetaPracticante)
    }
    <p class="pie-hoja">${EMPRESA.nombre} · RUC N.° ${EMPRESA.ruc}</p>

    <section class="anexo">
      ${encabezadoAnexo(d, "ANEXO I — PLAN ESPECÍFICO DE APRENDIZAJE", `${d.cargo} — Sede ${d.sedeNombre}`)}
      <p><strong>Área / proyecto de destino:</strong> ${d.areaProyecto || "[completar]"}</p>
      <p><strong>Objetivo formativo general:</strong> ${parrafoDesdeTexto(d.objetivoFormativoGeneral) || "[completar]"}</p>
      <p><strong>Actividades principales:</strong></p>
      ${listaDesdeTexto(d.planCapacitacionTexto)}
      <p><strong>Supervisor(a) asignado(a):</strong> ${d.supervisorAsignado || "[completar]"}</p>
      <p><strong>Fecha de inicio / término:</strong> ${formatearFecha(d.fechaInicio)} – ${formatearFecha(d.fechaFin)}</p>
      ${pieAnexo(d, etiquetaPracticante)}
    </section>

    <section class="anexo">
      ${encabezadoAnexo(d, "ANEXO III — DOMICILIO ELECTRÓNICO Y COMUNICACIONES", "Cláusula del presente convenio sobre domicilio electrónico y comunicaciones")}
      <p>LA EMPRESA: info@cayla.pe · ${etiquetaPracticante}: ${d.email ?? "[completar]"}</p>
      <p>Las direcciones consignadas constituyen los domicilios electrónicos válidos para todos los efectos del
      presente convenio, incluidas las comunicaciones sobre el Plan Específico de Aprendizaje y demás documentos
      relacionados con la práctica.</p>
      ${pieAnexo(d, etiquetaPracticante)}
    </section>

    ${anexoIV(d, etiquetaPracticante)}
  </article>`;
}

/** Arma el HTML completo del contrato — el texto que se congela en `contratos_generados.documento_html`. */
export function construirContrato(datosSinEscapar: DatosContrato): string {
  const d = escapado(datosSinEscapar);
  if (d.tipo === "adendum") return documentoAdendum(d);
  if (d.tipo === "convenio_practicas") return documentoConvenio(d);
  const colaborador = etiquetaColaborador(d);

  const esIndefinido = d.tipo === "indefinido";
  const titulo = esIndefinido
    ? "CONTRATO DE TRABAJO A PLAZO INDETERMINADO"
    : "CONTRATO DE TRABAJO SUJETO A MODALIDAD TEMPORAL POR INICIO O INCREMENTO DE ACTIVIDAD";

  return `
  <article class="contrato">
    <header>
      <p class="empresa">${EMPRESA.nombre}</p>
      <p class="ruc">RUC N.° ${EMPRESA.ruc} · Sede ${d.sedeNombre}</p>
      <h1>${titulo}</h1>
      ${
        esIndefinido
          ? ""
          : `<p class="norma">(TUO del Decreto Legislativo N.° 728 — Ley de Productividad y Competitividad Laboral, Art. 57)</p>`
      }
      <p class="norma">Régimen Laboral Especial de la Pequeña Empresa — Texto Único Ordenado de la Ley de Impulso al
      Desarrollo Productivo y al Crecimiento Empresarial (Ley MYPE), aprobado por Decreto Supremo N.° 013-2013-PRODUCE,
      y su Reglamento aprobado por Decreto Supremo N.° 008-2008-TR</p>
    </header>

    <p>En ${enLaCiudadDe(d)}, al ${formatearFecha(d.fechaInicio)}, se celebra el presente Contrato de Trabajo
    ${esIndefinido ? "a Plazo Indeterminado" : "Sujeto a Modalidad Temporal"} entre:</p>

    <h3>I. DATOS DEL EMPLEADOR</h3>
    <p>${EMPRESA.nombre}, identificada con R.U.C. N.° ${EMPRESA.ruc}, con domicilio legal en
    ${EMPRESA.domicilio}, debidamente representada por su representante legal, Sr(a). ${d.firmanteNombre},
    identificado(a) con D.N.I. N.° ${d.firmanteDni}, a quien en adelante se denominará LA EMPRESA.</p>

    <h3>II. DATOS DE ${colaborador}</h3>
    <p>${d.nombreDni}, ${segunGenero(d, "identificado", "identificada")} con D.N.I. N.° ${d.documento}${
      d.direccion ? `, con domicilio en ${d.direccion}` : ""
    }, a quien en adelante se denominará ${colaborador}.</p>

    <p>Ambas partes declaran que celebran el presente contrato conforme a la legislación laboral vigente y sin
    vicios de voluntad.</p>

    ${clausulaNaturalezaYPlazo(d)}

    ${clausulaPeriodoPrueba(d)}

    <h3>CUARTA. CARGO Y FINALIDAD DEL SERVICIO</h3>
    <p>${colaborador} es ${segunGenero(d, "contratado", "contratada")} para desempeñar el cargo de ${d.cargo} en la sede ${d.sedeNombre}.</p>
    <p>Las funciones específicas se encuentran detalladas en el ANEXO I — Funciones del Cargo, el cual forma parte
    integrante del presente contrato.</p>

    ${clausulaJornada(d)}
    ${clausulaRemuneracion(d)}
    ${clausulaBeneficios(d)}

    <h3>OCTAVA. CONDUCTA, PRESENTACIÓN E INTEGRIDAD</h3>
    <p>${colaborador} se obliga a mantener conducta ética, profesional y respetuosa, así como una adecuada
    presentación personal acorde a la imagen de LA EMPRESA. Es responsable del adecuado manejo de la caja, los
    bienes y los recursos que LA EMPRESA le asigne durante su turno para el ejercicio de sus funciones. El
    descuento de importes de su remuneración por faltantes comprobados se sujetará a los límites establecidos por
    la legislación vigente, en particular al límite del treinta por ciento (30%) de la remuneración neta mensual
    previsto en el artículo 648 del Código Procesal Civil, y requerirá la autorización escrita de ${colaborador} o
    resolución judicial.</p>
    <p>Los bienes que LA EMPRESA entrega a ${colaborador} bajo su custodia se detallan en el ANEXO IV —
    Constancia de Recepción y Responsabilidad de Activos, el cual forma parte integrante del presente contrato.</p>

    <h3>NOVENA. USO DE IMAGEN</h3>
    <p>${colaborador} autoriza expresamente a LA EMPRESA el uso de su imagen, voz y representación en fotografías
    o videos tomados durante actividades laborales o promocionales en la sede ${d.sedeNombre}, con fines
    corporativos, institucionales o publicitarios, sin compensación adicional, respetando siempre su dignidad e
    integridad personal, en los límites de la Ley N.° 29733, Ley de Protección de Datos Personales.</p>

    <h3>DÉCIMA. CONFIDENCIALIDAD</h3>
    <p>Toda información relacionada con procesos internos, inventarios, proveedores, estrategias comerciales, datos
    de clientes, precios, márgenes, información financiera y cualquier información sensible de LA EMPRESA tiene
    carácter estrictamente confidencial. ${colaborador} se obliga a no divulgarla, reproducirla ni utilizarla para
    fines distintos a sus funciones, durante la vigencia del contrato y hasta veinticuatro (24) meses después de su
    culminación.</p>

    <h3>DÉCIMA PRIMERA. DEBER DE LEALTAD Y FIDELIDAD</h3>
    <p>Durante la vigencia del presente contrato, ${colaborador} se obliga a actuar en todo momento en interés de
    LA EMPRESA y a abstenerse de favorecer a competidores, desviar clientela o facilitar información reservada o
    estratégica, bajo apercibimiento de falta grave conforme al artículo 25, incisos a) y d), del TUO del Decreto
    Legislativo N.° 728.</p>

    <h3>DÉCIMA SEGUNDA. PROHIBICIÓN DE DECLARACIONES LESIVAS</h3>
    <p>${colaborador} se obliga a abstenerse de emitir o difundir, por cualquier medio, declaraciones falsas o
    realizadas de mala fe con el propósito de dañar la reputación, imagen o intereses de LA EMPRESA. Esta cláusula
    no restringe el derecho de ${colaborador} a formular denuncias de buena fe ante las autoridades competentes.</p>

    <h3>DÉCIMA TERCERA. VIDEOVIGILANCIA</h3>
    <p>LA EMPRESA cuenta con sistemas de videovigilancia en las instalaciones del centro de trabajo, debidamente
    señalizados, que operan de forma permanente con fines de seguridad, control operativo y verificación de
    incidencias, conforme a la Ley N.° 29733. ${colaborador} declara conocer y aceptar su existencia mediante la
    firma del presente contrato.</p>

    ${clausulaDisciplina(d)}

    <h3>DÉCIMA QUINTA. FALTAS GRAVES</h3>
    <p>Se consideran faltas graves aquéllas previstas en el artículo 25 del TUO del Decreto Legislativo N.° 728, así
    como las detalladas en el ANEXO II — Faltas Graves, el cual forma parte integrante del presente contrato.</p>

    <h3>DÉCIMA SEXTA. CAPACITACIÓN Y APRENDIZAJE CONTINUO</h3>
    <p>LA EMPRESA está obligada a proporcionar capacitación conforme al artículo 84 del TUO del Decreto Legislativo
    N.° 728. ${colaborador} está ${segunGenero(d, "obligado", "obligada")} a participar activamente en los programas de capacitación que LA EMPRESA
    organice dentro de la jornada de trabajo; de disponerse fuera de dicha jornada con carácter obligatorio, las
    horas correspondientes se remunerarán como sobretiempo conforme a ley.</p>

    <h3>DÉCIMA SÉPTIMA. PROTECCIÓN DE DATOS PERSONALES</h3>
    <p>De conformidad con la Ley N.° 29733, Ley de Protección de Datos Personales, y su Reglamento aprobado por
    Decreto Supremo N.° 016-2024-JUS, LA EMPRESA informa a ${colaborador} que sus datos personales —incluyendo
    nombre, documento de identidad, domicilio, datos laborales, remunerativos y previsionales— serán incorporados y
    tratados en los sistemas de LA EMPRESA con las siguientes finalidades exclusivas: (i) gestión de la relación
    laboral; (ii) cumplimiento de obligaciones legales ante el Ministerio de Trabajo, SUNAT, EsSalud, AFP/ONP y otras
    autoridades; (iii) comunicaciones internas propias de la relación de trabajo; (iv) emisión de constancias,
    certificados y documentos laborales; y (v) verificación de identidad mediante la carga de la copia del Documento
    Nacional de Identidad (DNI) y constancia de la aceptación de los términos del presente contrato.</p>

    ${clausulaEntregaCopia(d)}

    <h3>DÉCIMA NOVENA. DOMICILIO ELECTRÓNICO Y COMUNICACIONES</h3>
    <p>Las partes acuerdan un domicilio electrónico válido para las comunicaciones de la relación laboral, conforme
    a los términos del ANEXO III — Domicilio Electrónico y Comunicaciones, el cual forma parte integrante del
    presente contrato.${d.email ? ` El domicilio electrónico de ${colaborador} es ${d.email}.` : ""}</p>

    ${clausulaTerminacion(d)}

    <p>En señal de conformidad, las partes firman el presente contrato en ${enLaCiudadDe(d)}, el
    ${formatearFecha(d.fechaInicio)}, en tres (3) ejemplares de igual tenor.</p>

    ${bloqueFirmas(d)}
    <p class="pie-hoja">${EMPRESA.nombre} · RUC N.° ${EMPRESA.ruc}</p>

    <section class="anexo">
      ${encabezadoAnexo(d, "ANEXO I — FUNCIONES DEL CARGO", `${d.cargo} — Sede ${d.sedeNombre}`)}
      ${listaDesdeTexto(d.funcionesTexto)}
      ${pieAnexo(d)}
    </section>

    <section class="anexo">
      ${encabezadoAnexo(d, "ANEXO II — FALTAS GRAVES", "Artículo 25 — TUO Decreto Legislativo N.° 728")}
      <ul>
        <li>Incumplimiento reiterado de obligaciones laborales.</li>
        <li>Desobediencia grave a las instrucciones del empleador.</li>
        <li>Falta de honradez, hurto o apropiación indebida de bienes de la empresa o de terceros.</li>
        <li>Ofensas graves verbales o físicas contra el empleador, sus representantes, compañeros o terceros.</li>
        <li>Negligencia grave en el desempeño de funciones o daño intencional a bienes de la empresa.</li>
        <li>Abandono de puesto sin justificación.</li>
        <li>Divulgación de información confidencial de la empresa a terceros.</li>
        <li>Presentación al centro de trabajo bajo los efectos del alcohol o sustancias psicoactivas.</li>
        <li>Prestar servicios a competidores directos o indirectos de LA EMPRESA, incumpliendo el deber de lealtad y
        fidelidad establecido en la Cláusula Décima Primera del presente contrato.</li>
        <li>Todo acto que, por su gravedad, haga irrazonable la continuidad del vínculo laboral conforme al artículo
        25 del TUO del Decreto Legislativo N.° 728.</li>
      </ul>
      ${pieAnexo(d)}
    </section>

    <section class="anexo">
      ${encabezadoAnexo(d, "ANEXO III — DOMICILIO ELECTRÓNICO Y COMUNICACIONES", "Cláusula Décima Novena del presente contrato")}
      <p>LA EMPRESA: info@cayla.pe · ${colaborador}: ${d.email ?? "[completar]"}</p>
      <p>Las direcciones consignadas constituyen los domicilios electrónicos válidos para todos los efectos de la
      relación laboral, incluida la entrega del Reglamento Interno de Trabajo y demás documentos internos. Se
      exceptúan de esta vía la carta de preaviso de despido y la carta de despido, que se cursan por conducto notarial
      o por vía física con cargo de recepción, conforme a los artículos 31 y 32 del TUO del Decreto Legislativo N.°
      728.</p>
      ${pieAnexo(d)}
    </section>

    ${anexoIV(d)}
  </article>`;
}

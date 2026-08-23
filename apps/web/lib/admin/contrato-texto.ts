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

import { EMPRESA } from "@cayla-dynamic/shared";

export interface DatosContrato {
  tipo: "nuevo" | "renovacion" | "adendum";

  // La persona
  nombreDni: string;
  documento: string;
  direccion: string | null;
  cargo: string;
  email: string | null;

  // El puesto
  sedeNombre: string;
  sedeCodigo: string;
  causaObjetivaTexto: string;
  funcionesTexto: string;

  // Plazo — la jornada es siempre de 48h, el máximo legal; no se declara un
  // número calculado del horario, que es solo la disposición operativa de hoy.
  fechaInicio: string; // ISO
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

  // Firmante por la empresa (siempre Gerencia General, literal en la firma —
  // igual que en el modelo original y en EMPRESA de /admin/documentacion)
  firmanteNombre: string;
  firmanteDni: string;
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
    else {
      const d = Math.floor(resto / 10);
      const u = resto % 10;
      out += DECENAS[d] + (u > 0 ? ` y ${UNIDADES[u]}` : "");
    }
  }
  return out;
}

/** "1,130.00" → "Mil ciento treinta y 00/100". Soporta hasta 999,999.99. */
export function numeroALetras(monto: number): string {
  const entero = Math.floor(monto);
  const centavos = Math.round((monto - entero) * 100);
  const miles = Math.floor(entero / 1000);
  const resto = entero % 1000;
  let out = "";
  if (miles > 0) {
    out += miles === 1 ? "mil" : `${tresDigitos(miles)} mil`;
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
    causaObjetivaTexto: escapeHtml(d.causaObjetivaTexto),
    funcionesTexto: escapeHtml(d.funcionesTexto),
    activosPrincipales: escapeHtml(d.activosPrincipales),
    activosLibre: escapeHtml(d.activosLibre),
    firmanteNombre: escapeHtml(d.firmanteNombre),
    firmanteDni: escapeHtml(d.firmanteDni),
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

function clausulaJornada(d: DatosContrato): string {
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
    Legislativo N.° 713. En todo caso, LA COLABORADORA gozará de veinticuatro (24)
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
    voluntarias para LA COLABORADORA y se remunerarán con un recargo de
    veinticinco por ciento (25%) por las dos primeras horas y treinta y cinco por
    ciento (35%) por las horas restantes, conforme al artículo 10 del Decreto
    Supremo N.° 007-2002-TR, independientemente de que cuenten con autorización
    previa.</p>`;
}

function clausulaRemuneracion(d: DatosContrato): string {
  return `
    <h3>SEXTA. REMUNERACIÓN</h3>
    <p>La remuneración mensual base de LA COLABORADORA es de S/ ${soles(d.remuneracionMensual)}
    (${numeroALetras(d.remuneracionMensual)} soles), no menor a la Remuneración
    Mínima Vital vigente. Sobre esta base, LA EMPRESA abona a LA COLABORADORA el
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
  const movilidad = d.cobraMovilidad
    ? `<li><strong>Movilidad:</strong> LA EMPRESA otorga a LA COLABORADORA una
       asignación diaria de movilidad conforme a la tarifa vigente para su sede
       (S/ ${soles(d.movilidadDiaria ?? 0)} a la fecha de este contrato), sujeta a la
       política de movilidad de la empresa y al convenio individual de ruta y
       gasto de transporte que LA COLABORADORA suscribe por separado, conforme al
       artículo 19 inciso e) del Decreto Supremo N.° 001-97-TR y al artículo 28
       del Reglamento Interno de Trabajo.</li>`
    : `<li><strong>Movilidad:</strong> no aplica a LA COLABORADORA a la fecha de
       este contrato.</li>`;

  return `
    <h3>SÉPTIMA. BENEFICIOS LABORALES</h3>
    <p>El presente contrato se rige por el Régimen Laboral Especial de la Pequeña
    Empresa, conforme al Texto Único Ordenado de la Ley de Impulso al Desarrollo
    Productivo y al Crecimiento Empresarial (Ley MYPE), aprobado por Decreto
    Supremo N.° 013-2013-PRODUCE, y su Reglamento aprobado por Decreto Supremo
    N.° 008-2008-TR, correspondiendo a LA COLABORADORA los siguientes derechos:</p>
    <ol type="a">
      <li><strong>Compensación por Tiempo de Servicios (CTS):</strong> Equivalente
      a quince (15) remuneraciones diarias por cada año completo de servicios, con
      un tope de noventa (90) remuneraciones diarias, depositada en los plazos
      establecidos por ley.</li>
      <li><strong>Gratificaciones legales:</strong> Dos (2) gratificaciones al
      año, en julio y en diciembre, cada una equivalente al cincuenta por ciento
      (50%) de la remuneración computable. Adicionalmente, LA EMPRESA pagará a LA
      COLABORADORA una bonificación extraordinaria equivalente al nueve por ciento
      (9%) de cada gratificación, conforme a la Ley N.° 30334, inafecta a
      contribuciones.</li>
      <li><strong>Vacaciones:</strong> Quince (15) días calendario de descanso
      vacacional por cada año completo de servicios, conforme al régimen laboral
      especial de la pequeña empresa regulado por el Decreto Supremo N.°
      013-2013-PRODUCE, siéndole de aplicación supletoria el Decreto Legislativo
      N.° 713 en lo que corresponda.</li>
      <li><strong>Afiliación a EsSalud:</strong> LA EMPRESA aportará el nueve por
      ciento (9%) de la remuneración mensual de LA COLABORADORA al Seguro Social
      de Salud (EsSalud).</li>
      <li><strong>Afiliación al sistema previsional:</strong> LA COLABORADORA
      ejercerá su derecho a elegir entre el Sistema Privado de Pensiones (SPP) o
      el Sistema Nacional de Pensiones (SNP).</li>
      <li><strong>Asignación familiar:</strong> LA EMPRESA otorga a LA
      COLABORADORA, como mejora voluntaria por encima de los beneficios mínimos
      del régimen laboral especial de la pequeña empresa, una asignación familiar
      equivalente al diez por ciento (10%) de la Remuneración Mínima Vital
      vigente, en caso de que LA COLABORADORA acredite tener hijos menores de
      dieciocho (18) años, o mayores con discapacidad. Para tal efecto se toma
      como referencia el parámetro previsto en la Ley N.° 25129. La acreditación
      deberá realizarse mediante la presentación de la partida de nacimiento
      correspondiente ante LA EMPRESA. El derecho a esta asignación se genera a
      partir del mes en que se acredite fehacientemente dicha condición, sin
      efecto retroactivo.</li>
      <li><strong>Seguro de Vida:</strong> LA COLABORADORA tendrá derecho a
      seguro de vida conforme al Decreto Legislativo N.° 688 y sus normas
      modificatorias, así como al régimen laboral especial de la pequeña empresa
      (Decreto Supremo N.° 013-2013-PRODUCE), en las condiciones y desde el
      momento que determine la ley aplicable.</li>
      ${movilidad}
      <li><strong>Asignación por educación:</strong> LA EMPRESA otorga, conforme
      a su política de asignación por educación vigente, una cobertura parcial de
      los gastos de estudios de LA COLABORADORA o de sus hijos, contra la
      presentación del comprobante correspondiente y sujeta a los topes y
      condiciones de dicha política. No genera derecho adquirido: rige mientras
      LA COLABORADORA mantenga vigente el estudio acreditado.</li>
      <li><strong>Bono de onomástico:</strong> LA EMPRESA otorga a LA
      COLABORADORA, en el mes de su cumpleaños, un bono de S/ ${soles(d.bonoOnomastico)}
      (monto vigente a la fecha de este contrato, conforme al artículo 19 inciso
      g) del Decreto Supremo N.° 001-97-TR), sujeto a la política de la empresa y
      a la constancia de entrega correspondiente.</li>
    </ol>`;
}

function clausulaPeriodoPrueba(d: DatosContrato): string {
  if (d.tipo !== "nuevo") {
    return `
    <h3>TERCERA. PERÍODO DE PRUEBA</h3>
    <p>No aplica un nuevo período de prueba: LA COLABORADORA ya superó el período
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
    indemnización. Superado el período de prueba, LA COLABORADORA gozará de
    estabilidad laboral durante la vigencia del contrato conforme al artículo 79
    del TUO del Decreto Legislativo N.° 728.</p>`;
}

function clausulaDisciplina(d: DatosContrato): string {
  return `
    <h3>DÉCIMA CUARTA. RÉGIMEN DISCIPLINARIO</h3>
    <p>Las sanciones podrán consistir en llamada de atención verbal, amonestación
    escrita, suspensión sin goce de haber o resolución del contrato por falta
    grave, conforme a los artículos 25, 31 y 32 del TUO del Decreto Legislativo
    N.° 728 y al Reglamento Interno de Trabajo, versión ${d.ritVersion}, vigente
    desde el ${d.ritFecha} — cuya entrega y acuse constan, conforme a su artículo
    60, en el sistema Dynamic o por los demás medios ahí previstos.</p>
    <p>Para el caso del procedimiento previo al despido, LA EMPRESA otorgará a LA
    COLABORADORA, mediante carta escrita, un plazo no menor a seis (6) días
    naturales para que ejerza su derecho de defensa por escrito respecto a los
    cargos que se le formulen, conforme al artículo 31 del TUO del Decreto
    Legislativo N.° 728. Sin perjuicio de las medidas inmediatas de protección
    operativa que correspondan, el procedimiento previo al despido se cumplirá
    íntegramente en todos los casos.</p>
    <p>Cuando la causa invocada sea de naturaleza relacionada con la capacidad de
    LA COLABORADORA —en particular, rendimiento deficiente conforme al artículo
    23, inciso b), del TUO del Decreto Legislativo N.° 728—, el plazo otorgado
    será de treinta (30) días naturales para que LA COLABORADORA demuestre su
    capacidad o corrija su deficiencia, conforme al segundo supuesto del artículo
    31 del mismo cuerpo normativo. En estos casos, LA EMPRESA podrá solicitar el
    concurso de la Autoridad Administrativa de Trabajo conforme al artículo 34 del
    Reglamento aprobado por Decreto Supremo N.° 001-96-TR.</p>`;
}

function anexoIV(d: DatosContrato): string {
  return `
    <h2>CONSTANCIA DE RECEPCIÓN Y RESPONSABILIDAD DE ACTIVOS</h2>
    <p><em>Anexo IV — Contrato de Trabajo Sujeto a Modalidad · ${d.nombreDni} ·
    ${formatearFecha(d.fechaInicio)}</em></p>
    <p>Conforme a la Cláusula Octava del presente contrato, LA COLABORADORA deja
    constancia de la recepción de los bienes de propiedad de LA EMPRESA que se
    detallan a continuación, correspondientes a la sede ${d.sedeNombre} y
    asignados para el ejercicio de sus funciones y bajo su custodia:</p>
    <p><strong>Activos principales de la sede:</strong> ${d.activosPrincipales}</p>
    <p><strong>Ajuste específico para esta persona:</strong>
    ${d.activosLibre || "LA COLABORADORA no tiene activos adicionales bajo su custodia, más allá de los generales de la sede detallados líneas arriba."}</p>
    <p>Todos los bienes detallados son de propiedad exclusiva de LA EMPRESA y se
    entregan únicamente para el desempeño de las funciones de LA COLABORADORA. LA
    COLABORADORA se obliga a custodiarlos y conservarlos con la diligencia
    debida, y a devolverlos al extinguirse el vínculo laboral por cualquier
    causa, en buen estado de conservación salvo el desgaste natural por uso
    normal.</p>`;
}

/** Arma el HTML completo del contrato — el texto que se congela en `contratos_generados.documento_html`. */
export function construirContrato(datosSinEscapar: DatosContrato): string {
  const d = escapado(datosSinEscapar);
  const titulo =
    d.tipo === "adendum"
      ? "ADENDUM AL CONTRATO DE TRABAJO"
      : "CONTRATO DE TRABAJO SUJETO A MODALIDAD TEMPORAL POR INICIO O INCREMENTO DE ACTIVIDAD";

  return `
  <article class="contrato">
    <header>
      <p class="empresa">${EMPRESA.nombre}</p>
      <p class="ruc">RUC N.° ${EMPRESA.ruc} · Sede ${d.sedeNombre}</p>
      <h1>${titulo}</h1>
      <p class="norma">(TUO del Decreto Legislativo N.° 728 — Ley de Productividad y Competitividad Laboral, Art. 57)</p>
      <p class="norma">Régimen Laboral Especial de la Pequeña Empresa — Texto Único Ordenado de la Ley de Impulso al
      Desarrollo Productivo y al Crecimiento Empresarial (Ley MYPE), aprobado por Decreto Supremo N.° 013-2013-PRODUCE,
      y su Reglamento aprobado por Decreto Supremo N.° 008-2008-TR</p>
    </header>

    <p>En la ciudad de ${d.sedeNombre}, al ${formatearFecha(d.fechaInicio)}, se celebra el presente Contrato de
    Trabajo Sujeto a Modalidad Temporal entre:</p>

    <h3>I. DATOS DEL EMPLEADOR</h3>
    <p>${EMPRESA.nombre}, identificada con R.U.C. N.° ${EMPRESA.ruc}, con domicilio legal en
    ${EMPRESA.domicilio}, debidamente representada por su representante legal, Sr(a). ${d.firmanteNombre},
    identificado(a) con D.N.I. N.° ${d.firmanteDni}, a quien en adelante se denominará LA EMPRESA.</p>

    <h3>II. DATOS DE LA COLABORADORA</h3>
    <p>${d.nombreDni}, identificada con D.N.I. N.° ${d.documento}${
      d.direccion ? `, con domicilio en ${d.direccion}` : ""
    }, a quien en adelante se denominará LA COLABORADORA.</p>

    <p>Ambas partes declaran que celebran el presente contrato conforme a la legislación laboral vigente y sin
    vicios de voluntad.</p>

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
    escrito.</p>

    ${clausulaPeriodoPrueba(d)}

    <h3>CUARTA. CARGO Y FINALIDAD DEL SERVICIO</h3>
    <p>LA COLABORADORA es contratada para desempeñar el cargo de ${d.cargo} en la sede ${d.sedeNombre}.</p>
    <p>Las funciones específicas se encuentran detalladas en el ANEXO I — Funciones del Cargo, el cual forma parte
    integrante del presente contrato.</p>

    ${clausulaJornada(d)}
    ${clausulaRemuneracion(d)}
    ${clausulaBeneficios(d)}

    <h3>OCTAVA. CONDUCTA, PRESENTACIÓN E INTEGRIDAD</h3>
    <p>LA COLABORADORA se obliga a mantener conducta ética, profesional y respetuosa, así como una adecuada
    presentación personal acorde a la imagen de LA EMPRESA. Es responsable del adecuado manejo de la caja, los
    bienes y los recursos que LA EMPRESA le asigne durante su turno para el ejercicio de sus funciones. El
    descuento de importes de su remuneración por faltantes comprobados se sujetará a los límites establecidos por
    la legislación vigente, en particular al límite del treinta por ciento (30%) de la remuneración neta mensual
    previsto en el artículo 648 del Código Procesal Civil, y requerirá la autorización escrita de LA COLABORADORA o
    resolución judicial.</p>

    <h3>NOVENA. USO DE IMAGEN</h3>
    <p>LA COLABORADORA autoriza expresamente a LA EMPRESA el uso de su imagen, voz y representación en fotografías
    o videos tomados durante actividades laborales o promocionales en la sede ${d.sedeNombre}, con fines
    corporativos, institucionales o publicitarios, sin compensación adicional, respetando siempre su dignidad e
    integridad personal, en los límites de la Ley N.° 29733, Ley de Protección de Datos Personales.</p>

    <h3>DÉCIMA. CONFIDENCIALIDAD</h3>
    <p>Toda información relacionada con procesos internos, inventarios, proveedores, estrategias comerciales, datos
    de clientes, precios, márgenes, información financiera y cualquier información sensible de LA EMPRESA tiene
    carácter estrictamente confidencial. LA COLABORADORA se obliga a no divulgarla, reproducirla ni utilizarla para
    fines distintos a sus funciones, durante la vigencia del contrato y hasta veinticuatro (24) meses después de su
    culminación.</p>

    <h3>DÉCIMA PRIMERA. DEBER DE LEALTAD Y FIDELIDAD</h3>
    <p>Durante la vigencia del presente contrato, LA COLABORADORA se obliga a actuar en todo momento en interés de
    LA EMPRESA y a abstenerse de favorecer a competidores, desviar clientela o facilitar información reservada o
    estratégica, bajo apercibimiento de falta grave conforme al artículo 25, incisos a) y d), del TUO del Decreto
    Legislativo N.° 728.</p>

    <h3>DÉCIMA SEGUNDA. NO DISPARAGEMENT (PROHIBICIÓN DE DECLARACIONES LESIVAS)</h3>
    <p>LA COLABORADORA se obliga a abstenerse de emitir o difundir, por cualquier medio, declaraciones falsas o
    realizadas de mala fe con el propósito de dañar la reputación, imagen o intereses de LA EMPRESA. Esta cláusula
    no restringe el derecho de LA COLABORADORA a formular denuncias de buena fe ante las autoridades competentes.</p>

    <h3>DÉCIMA TERCERA. VIDEOVIGILANCIA</h3>
    <p>LA EMPRESA cuenta con sistemas de videovigilancia en las instalaciones del centro de trabajo, debidamente
    señalizados, que operan de forma permanente con fines de seguridad, control operativo y verificación de
    incidencias, conforme a la Ley N.° 29733. LA COLABORADORA declara conocer y aceptar su existencia mediante la
    firma del presente contrato.</p>

    ${clausulaDisciplina(d)}

    <h3>DÉCIMA QUINTA. FALTAS GRAVES</h3>
    <p>Se consideran faltas graves aquéllas previstas en el artículo 25 del TUO del Decreto Legislativo N.° 728, así
    como las detalladas en el ANEXO II — Faltas Graves, el cual forma parte integrante del presente contrato.</p>

    <h3>DÉCIMA SEXTA. CAPACITACIÓN Y APRENDIZAJE CONTINUO</h3>
    <p>LA EMPRESA está obligada a proporcionar capacitación conforme al artículo 84 del TUO del Decreto Legislativo
    N.° 728. LA COLABORADORA está obligada a participar activamente en los programas de capacitación que LA EMPRESA
    organice dentro de la jornada de trabajo; de disponerse fuera de dicha jornada con carácter obligatorio, las
    horas correspondientes se remunerarán como sobretiempo conforme a ley.</p>

    <h3>DÉCIMA SÉPTIMA. PROTECCIÓN DE DATOS PERSONALES</h3>
    <p>De conformidad con la Ley N.° 29733, LA EMPRESA informa a LA COLABORADORA que sus datos personales serán
    tratados con las finalidades exclusivas de gestión de la relación laboral, cumplimiento de obligaciones legales,
    comunicaciones internas y emisión de constancias. LA COLABORADORA otorga su consentimiento expreso mediante la
    firma del presente contrato.</p>

    <h3>DÉCIMA OCTAVA. ENTREGA DE COPIA Y REGISTRO</h3>
    <p>LA EMPRESA entregará a LA COLABORADORA copia del presente contrato dentro de los tres (3) días hábiles
    siguientes al inicio de la prestación de servicios, y lo comunicará a la Autoridad Administrativa de Trabajo
    para su registro dentro de los quince (15) días naturales siguientes a su suscripción.</p>

    <h3>DÉCIMA NOVENA. DOMICILIO ELECTRÓNICO Y COMUNICACIONES</h3>
    <p>Las partes acuerdan un domicilio electrónico válido para las comunicaciones de la relación laboral, conforme
    a los términos del ANEXO III — Domicilio Electrónico y Comunicaciones, el cual forma parte integrante del
    presente contrato.${d.email ? ` El domicilio electrónico de LA COLABORADORA es ${d.email}.` : ""}</p>

    <h3>VIGÉSIMA. TERMINACIÓN</h3>
    <p>El contrato finalizará automáticamente en la fecha pactada o podrá resolverse anticipadamente por mutuo
    acuerdo, renuncia voluntaria de LA COLABORADORA (con treinta (30) días de anticipación), comisión de falta
    grave, o resolución anticipada sin causa justa por parte de LA EMPRESA — caso en el cual corresponderá la
    indemnización equivalente a una remuneración y media (1.5) por cada mes dejado de laborar hasta el término del
    contrato, con el límite de doce (12) remuneraciones, conforme al artículo 76 del TUO del Decreto Legislativo
    N.° 728.</p>

    <p>En señal de conformidad, las partes firman el presente contrato en la ciudad de ${d.sedeNombre}, el
    ${formatearFecha(d.fechaInicio)}, en tres (3) ejemplares de igual tenor.</p>

    <div class="firmas">
      <div>
        <p class="linea">&nbsp;</p>
        <p><strong>GERENTE GENERAL</strong><br/>${d.firmanteNombre}<br/>DNI N.° ${d.firmanteDni}<br/>${EMPRESA.nombre}</p>
      </div>
      <div>
        <p class="linea">&nbsp;</p>
        <p><strong>LA COLABORADORA</strong><br/>${d.nombreDni}<br/>DNI N.° ${d.documento}</p>
      </div>
    </div>

    <h2>ANEXO I — FUNCIONES DEL CARGO</h2>
    <p><em>${d.cargo} — Sede ${d.sedeNombre}</em></p>
    ${listaDesdeTexto(d.funcionesTexto)}

    <h2>ANEXO II — FALTAS GRAVES</h2>
    <p><em>(Artículo 25 — TUO Decreto Legislativo N.° 728)</em></p>
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

    <h2>ANEXO III — DOMICILIO ELECTRÓNICO Y COMUNICACIONES</h2>
    <p>LA EMPRESA: info@cayla.pe · LA COLABORADORA: ${d.email ?? "[completar]"}</p>
    <p>Las direcciones consignadas constituyen los domicilios electrónicos válidos para todos los efectos de la
    relación laboral, incluida la entrega del Reglamento Interno de Trabajo y demás documentos internos. Se
    exceptúan de esta vía la carta de preaviso de despido y la carta de despido, que se cursan por conducto notarial
    o por vía física con cargo de recepción, conforme a los artículos 31 y 32 del TUO del Decreto Legislativo N.°
    728.</p>

    ${anexoIV(d)}
  </article>`;
}

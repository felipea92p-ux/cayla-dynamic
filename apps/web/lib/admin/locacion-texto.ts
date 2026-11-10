// ============================================================================
// locacion-texto.ts — el molde del contrato de LOCACIÓN DE SERVICIOS
// ============================================================================
// QUÉ PROMETE
//   El texto del contrato que firma quien cobra por recibo por honorarios
//   (RxH), armado con sus datos y listo para congelarse en
//   `contratos_locacion.documento_html` (0615). Puro: sin React ni Supabase, se
//   prueba con vitest (`tests/locacion-texto.test.ts`).
//
// POR QUÉ UN MOLDE APARTE Y NO UNA RAMA MÁS DE `contrato-texto.ts`
//   `contrato-texto.ts` es el contrato de TRABAJO: jornada, remuneración,
//   cargo, periodo de prueba, beneficios. Una locación es un contrato CIVIL
//   (Código Civil, arts. 1764 a 1770) y no puede llevar nada de eso: cargo,
//   horas, sueldo y modalidad son los indicios con que un juez o SUNAFIL
//   declaran que en realidad era un trabajo (art. 4 del D.S. 003-97-TR,
//   primacía de la realidad). Por eso `DatosLocacion` no tiene esos campos: no
//   es que el molde los ignore, es que no hay por dónde metérselos. Decidido
//   con Felipe el 2026-11-10, que había pedido «cargo, horas, sueldo,
//   modalidad» y eligió la locación civil al ver por qué.
//   Lo que sí se comparte con el contrato de trabajo: la empresa, las marcas
//   de firma (las dos firmas se estampan al MOSTRAR, nunca al guardar), y
//   cómo se escriben fechas y montos.
//
// ⚠️ ES UN BORRADOR
//   Mientras `TEXTO_LOCACION_APROBADO` sea `false`, cada documento lleva arriba
//   un aviso visible de borrador, y se imprime con él: un papel sin revisar no
//   puede pasar por definitivo ni por accidente. Cuando el abogado lo apruebe
//   (con los cambios que pida), se cambia la constante en el mismo PR que sus
//   cambios, y se anota quién y cuándo lo aprobó.
//
//   2026-11-10: Felipe dice que el primer borrador «se revisó y quedó acorde a
//   la ley», y pidió una segunda revisión a fondo. Esa segunda revisión cambió
//   el texto —abajo, cláusula por cláusula—, así que la aprobación del primero
//   no cubre este: el revisor tiene que ver lo que cambió antes de aprobarlo.
//
// LO QUE LA SEGUNDA REVISIÓN CAMBIÓ, Y POR QUÉ
//   · No se fecha al día de inicio. Decía «En [ciudad], el [inicio], se
//     celebra…»: un contrato generado hoy para un servicio que empezó en
//     agosto quedaba antedatado. Ahora rige desde el inicio y se celebra
//     cuando firma la persona; Dynamic estampa la fecha y la hora bajo cada
//     firma (`estamparFirmas`).
//   · Resolución recíproca y con prestaciones precisas. Un contrato que la
//     persona no puede negociar es por adhesión (CC 1390), y ahí no vale una
//     facultad de resolver solo a favor de quien lo redactó (CC 1398). Y una
//     cláusula del art. 1430 que no dice QUÉ incumplimiento la activa no opera.
//   · Cesión de derechos expresa. «Corresponden a CAYLA en la medida que lo
//     permita la ley» no cedía casi nada: el D. Leg. 822 exige cada modalidad
//     por escrito, la exclusividad expresa, el territorio y el plazo (arts. 89
//     y 90); sin eso rige la presunción del art. 16 —no exclusiva y solo para
//     lo habitual—. Se cede también el derecho a registrar los diseños
//     (Decisión 486, art. 114).
//   · La autonomía pasa de describir a obligar: CAYLA «no le fija horario ni
//     turnos ni le aplica sanciones». Si en la práctica se los fija, el que
//     incumple es CAYLA; un contrato que describe algo que el propio sistema
//     contradice no defiende a nadie (primacía de la realidad).
//   · Datos personales (Ley 29733, art. 18: informar finalidad, dónde se
//     guardan y cuánto tiempo), comunicaciones por escrito, y el acto de firma
//     descrito tal como lo hace Dynamic: si la persona niega haber firmado,
//     la carga de probarlo es de CAYLA (reglamento de la Ley 27269, art. 2-A).
//   Lo que NO se cambió, a propósito: la forma de pagar `por_horas`
//   («S/ X por un mes completo, en proporción a las horas»). Se le propuso a
//   Felipe escribirla como tarifa por hora —S/ 7.59, lo mismo al año que
//   hoy—, porque «mes completo» no se puede calcular leyendo el contrato (las
//   horas de ese mes, 6.5 × días del periodo, viven solo en la planilla) y en
//   un contrato por adhesión lo oscuro se interpreta a favor de la persona
//   (CC 1401). El 2026-11-10 eligió dejarlo como está, sabiendo que quienes
//   cobran así «trabajan cuando pueden y solo se registran sus horas». No se
//   reabre salvo que lo pida él o el abogado.
// ============================================================================
import { EMPRESA, fechaLima, horaLima } from "@cayla-dynamic/shared";
import {
  escapeHtml,
  formatearFecha,
  MARCADOR_FIRMA_EMPRESA,
  MARCADOR_FIRMA_PERSONA,
  numeroALetras,
  soles,
} from "./contrato-texto";

/** `false` hasta que el abogado apruebe el texto. Ver el encabezado. */
export const TEXTO_LOCACION_APROBADO = false;

/**
 * Cómo se pagan los honorarios: una cuota fija al mes, un monto por todo el servicio, o un monto de referencia
 * por un mes completo que se paga en proporción a las horas de servicio prestadas. La tercera es como se paga hoy
 * a quien cobra por honorarios en CAYLA (dicho por Felipe el 2026-11-10: «los 1500 es la base, pero en base a las
 * horas que trabajen se les pagará»), y el contrato tiene que decir lo que de verdad pasa.
 */
export type PeriodicidadHonorarios = "mensual" | "total" | "por_horas";

export interface DatosLocacion {
  /** El nombre como figura en el DNI (`datos_personales.nombre_dni`). */
  nombreDni: string;
  documento: string;
  /** RUC de quien presta el servicio: lo necesita para emitir el recibo por honorarios. */
  ruc: string | null;
  direccion: string | null;
  /** `datos_personales.genero` (0369); `null` mantiene el femenino, como los demás documentos. */
  genero: "masculino" | "femenino" | null;
  /** El servicio, con las palabras con que se va a reconocer: «Fotografía de producto para la tienda». */
  servicio: string;
  /** Qué entrega o en qué consiste, en concreto. Una línea por punto. */
  entregables: string;
  fechaInicio: string;
  fechaFin: string;
  honorarios: number;
  periodicidad: PeriodicidadHonorarios;
  /** La ciudad donde se firma; `null` si la sede no la tiene cargada (0279). */
  ciudad: string | null;
  /** Días de aviso para resolver el contrato. */
  diasAviso: number;
  firmanteNombre: string;
  firmanteCargo: string;
  firmanteDni: string;
}

function segunGenero(d: DatosLocacion, masculino: string, femenino: string): string {
  return d.genero === "masculino" ? masculino : femenino;
}

/** «EL LOCADOR» o «LA LOCADORA». Es un término definido: nunca se contrae («de EL LOCADOR»). */
export function etiquetaLocador(d: Pick<DatosLocacion, "genero">): string {
  return d.genero === "masculino" ? "EL LOCADOR" : "LA LOCADORA";
}

const COMITENTE = "LA COMITENTE";

/** Un dato que falta se ve, no se rellena (el mismo criterio de la ciudad en el contrato de trabajo). */
function falta(que: string): string {
  return `<strong>[FALTA ${que}]</strong>`;
}

/**
 * Dónde va la fecha y la hora en que firmó cada parte. Como las firmas, se estampan al MOSTRAR: el texto congelado
 * se guarda antes de que la persona firme, así que no puede llevar adentro el momento en que firmó.
 */
export const MARCADOR_FECHA_FIRMA_EMPRESA = "<!--FECHA_FIRMA_EMPRESA-->";
export const MARCADOR_FECHA_FIRMA_PERSONA = "<!--FECHA_FIRMA_PERSONA-->";

/** Lo que dice bajo una firma: cuándo se firmó, en hora de Lima, o que todavía falta. */
export function textoFechaFirma(cuando: string | null): string {
  if (!cuando) return "Pendiente de firma.";
  return `Firmado electrónicamente el ${formatearFecha(fechaLima(cuando))}, a las ${horaLima(cuando)} (hora de Lima).`;
}

export interface FirmasLocacion {
  /** La imagen de la firma de quien firma por CAYLA (`fn_firma_empresa`). */
  empresa: string | null;
  /** La copia de la firma de la persona, congelada al firmar. */
  persona: string | null;
  /** Cuándo se generó el contrato: es cuando firma CAYLA (`registrado_at`). */
  empresaAt: string | null;
  /** Cuándo confirmó su firma la persona (`firma_persona_confirmada_at`). */
  personaAt: string | null;
}

/** Pone las firmas y sus fechas sobre sus marcas. Una firma que falta deja la línea en blanco. */
export function estamparFirmas(html: string, f: FirmasLocacion): string {
  return html
    .replaceAll(MARCADOR_FIRMA_EMPRESA, f.empresa ? `<img src="${f.empresa}" alt="Firma de CAYLA" />` : "&nbsp;")
    .replaceAll(MARCADOR_FIRMA_PERSONA, f.persona ? `<img src="${f.persona}" alt="Firma de quien presta el servicio" />` : "&nbsp;")
    .replaceAll(MARCADOR_FECHA_FIRMA_EMPRESA, textoFechaFirma(f.empresaAt))
    .replaceAll(MARCADOR_FECHA_FIRMA_PERSONA, textoFechaFirma(f.personaAt));
}

/** Las líneas de los entregables como lista; si viene vacío, se dice. */
function listaEntregables(texto: string): string {
  const lineas = texto.split("\n").map((l) => l.trim()).filter(Boolean);
  if (lineas.length === 0) return `<p>${falta("DESCRIBIR QUÉ COMPRENDE EL SERVICIO")}</p>`;
  return `<ol>${lineas.map((l) => `<li>${escapeHtml(l)}</li>`).join("")}</ol>`;
}

/** Arma el contrato. Todo texto que viene de datos se escapa: el resultado se guarda y se inyecta como HTML. */
export function construirLocacion(datos: DatosLocacion): string {
  const d: DatosLocacion = {
    ...datos,
    nombreDni: escapeHtml(datos.nombreDni),
    documento: escapeHtml(datos.documento),
    ruc: datos.ruc ? escapeHtml(datos.ruc) : null,
    direccion: datos.direccion ? escapeHtml(datos.direccion) : null,
    servicio: escapeHtml(datos.servicio),
    ciudad: datos.ciudad ? escapeHtml(datos.ciudad) : null,
    firmanteNombre: escapeHtml(datos.firmanteNombre),
    firmanteCargo: escapeHtml(datos.firmanteCargo),
    firmanteDni: escapeHtml(datos.firmanteDni),
  };
  const locador = etiquetaLocador(d);
  const ciudad = d.ciudad ? `la ciudad de ${d.ciudad}` : `la ciudad de ${falta("LA CIUDAD DE LA SEDE")}`;
  const monto = `S/ ${soles(d.honorarios)} (${numeroALetras(d.honorarios)} soles)`;
  const pago = d.periodicidad === "mensual"
    ? `${monto} por cada mes de servicio, pagaderos dentro de los primeros cinco (5) días hábiles del mes siguiente`
    : d.periodicidad === "por_horas"
      ? `${monto} por un mes completo de servicio, que se pagan en proporción a las horas de servicio efectivamente
    prestadas en cada periodo de pago, dentro de los primeros cinco (5) días hábiles del periodo siguiente`
      : `${monto} por la totalidad del servicio, pagaderos a su conclusión`;

  return `
  <article class="contrato">
    ${TEXTO_LOCACION_APROBADO ? "" : `<p class="borrador"><strong>BORRADOR — pendiente de revisión legal. No firmar.</strong></p>`}
    <header>
      <p class="empresa">${EMPRESA.nombre}</p>
      <p class="ruc">RUC N.° ${EMPRESA.ruc}</p>
      <h1>CONTRATO DE LOCACIÓN DE SERVICIOS</h1>
      <p class="norma">(Código Civil, Libro VII, Sección Segunda, Título IX, Capítulo Segundo — artículos 1764 a 1770)</p>
    </header>

    <p>Conste por el presente documento el Contrato de Locación de Servicios que celebran las partes identificadas en
    la cláusula primera, en los términos y condiciones siguientes:</p>

    <h3>PRIMERA. LAS PARTES</h3>
    <p>${EMPRESA.nombre}, identificada con R.U.C. N.° ${EMPRESA.ruc}, con domicilio legal en ${EMPRESA.domicilio},
    debidamente representada por ${d.firmanteNombre}, identificado(a) con D.N.I. N.° ${d.firmanteDni}, a quien en
    adelante se denominará ${COMITENTE}; y</p>
    <p>${d.nombreDni}, ${segunGenero(d, "identificado", "identificada")} con D.N.I. N.° ${d.documento.trim() || falta("EL DNI")} y R.U.C.
    N.° ${d.ruc ?? falta("EL RUC, NECESARIO PARA EMITIR EL RECIBO POR HONORARIOS")}, con domicilio en
    ${d.direccion ?? falta("EL DOMICILIO")}, a quien en adelante se denominará ${locador}.</p>

    <h3>SEGUNDA. OBJETO</h3>
    <p>${locador} se obliga a prestar a ${COMITENTE} el servicio de <strong>${d.servicio}</strong>, que comprende:</p>
    ${listaEntregables(datos.entregables)}

    <h3>TERCERA. NATURALEZA CIVIL Y AUTONOMÍA</h3>
    <p>El presente es un contrato de locación de servicios de naturaleza civil, regido por los artículos 1764 a 1770
    del Código Civil. ${locador} presta el servicio sin estar ${segunGenero(d, "subordinado", "subordinada")} a
    ${COMITENTE}, con autonomía técnica y organizativa y bajo su propia dirección y responsabilidad: decide cómo
    cumplir lo encargado y responde por su resultado.</p>
    <p>${COMITENTE} no le fija horario ni turnos ni le aplica sanciones o amonestaciones. Las coordinaciones entre
    las partes se refieren al resultado encargado y a la información necesaria para lograrlo. Cuando el servicio deba
    prestarse en un local de ${COMITENTE}, los días y las franjas se acuerdan según la disponibilidad de ${locador},
    que puede proponer cambiarlos. Ante un incumplimiento, ${COMITENTE} solo puede ejercer los remedios previstos en
    este contrato y en el Código Civil.</p>
    <p>${locador} puede prestar servicios a terceros sin necesidad de autorización de ${COMITENTE}, con la sola
    condición de respetar la confidencialidad de la cláusula octava.</p>
    <p>El presente contrato no genera relación laboral entre las partes. ${locador} declara conocer que, por su
    naturaleza, no le corresponden los derechos y beneficios propios de una relación laboral.</p>

    <h3>CUARTA. PLAZO</h3>
    <p>El presente contrato rige del ${formatearFecha(d.fechaInicio)} al ${formatearFecha(d.fechaFin)}. Puede
    renovarse por acuerdo escrito de las partes, con un nuevo contrato.</p>

    <h3>QUINTA. HONORARIOS</h3>
    <p>Por el servicio, ${COMITENTE} pagará a ${locador} honorarios de ${pago}, contra la emisión del recibo por
    honorarios electrónico correspondiente. Los honorarios comprenden toda la retribución por el servicio, incluida
    la cesión de la cláusula novena.</p>
    <p>Los honorarios pactados son montos brutos. De ellos, ${COMITENTE} retiene el Impuesto a la Renta de cuarta
    categoría en los casos y por el porcentaje que establece la ley, salvo que ${locador} le haya acreditado, antes
    del pago, la suspensión de retenciones aprobada por la SUNAT para ese ejercicio.</p>

    <h3>SEXTA. OBLIGACIONES DE ${locador}</h3>
    <ol>
      <li>Prestar el servicio de manera personal y diligente, conforme al artículo 1766 del Código Civil.</li>
      <li>Entregar lo encargado en los plazos acordados con ${COMITENTE} para cada encargo.</li>
      <li>Emitir el recibo por honorarios electrónico por cada pago.</li>
      <li>Cumplir por su cuenta con sus obligaciones tributarias y con su propio seguro de salud y sistema de
      pensiones, conforme a la ley que le resulte aplicable.</li>
    </ol>

    <h3>SÉPTIMA. OBLIGACIONES DE ${COMITENTE}</h3>
    <ol>
      <li>Pagar los honorarios en la forma y el plazo pactados.</li>
      <li>Brindar a ${locador} la información que necesite para prestar el servicio.</li>
      <li>Respetar la autonomía de ${locador} en los términos de la cláusula tercera.</li>
    </ol>

    <h3>OCTAVA. CONFIDENCIALIDAD</h3>
    <p>${locador} guardará reserva sobre la información de ${COMITENTE} a la que acceda por el servicio —diseños,
    colecciones no lanzadas, precios, proveedores, clientas y procesos—, no la usará para fines ajenos al servicio y,
    al término del contrato, devolverá o eliminará la que tenga en su poder. Esta obligación rige durante la vigencia
    del contrato y por dos (2) años después de su término, sin perjuicio de la protección que la ley da al secreto
    empresarial mientras conserve ese carácter.</p>
    <p>Los datos personales de clientas, del equipo y de proveedores de ${COMITENTE} a los que acceda los tratará solo
    para prestar el servicio, sin copiarlos, conservarlos ni comunicarlos a terceros, conforme a la Ley N.° 29733, Ley
    de Protección de Datos Personales.</p>

    <h3>NOVENA. RESULTADOS DEL SERVICIO Y DERECHOS DE AUTOR</h3>
    <p>${locador} cede a ${COMITENTE}, en exclusiva y desde su creación, los derechos patrimoniales sobre los diseños,
    bocetos, patrones, fotografías —incluidas las meras fotografías del artículo 144 del Decreto Legislativo N.° 822—,
    textos y demás resultados que cree al prestar el servicio descrito en la cláusula segunda. La cesión comprende la
    reproducción, la distribución, la comunicación pública —incluida la puesta a disposición por internet—, la
    transformación y la adaptación, también industrial y textil, y la importación, para todo el mundo y por todo el
    plazo de protección que establece la ley.</p>
    <p>${locador} cede también a ${COMITENTE} el derecho a registrar a su nombre los diseños industriales que
    resulten del servicio (Decisión 486 de la Comunidad Andina, artículo 114), y la autoriza a ceder o licenciar a
    terceros los derechos de esta cláusula sin necesidad de un nuevo consentimiento (Decreto Legislativo N.° 822,
    artículo 94).</p>
    <p>La retribución por esta cesión es a tanto alzado y está comprendida en los honorarios de la cláusula quinta
    (Decreto Legislativo N.° 822, artículo 93, literal e). Los derechos morales de ${locador} se mantienen conforme a
    ley; ${locador} autoriza las adaptaciones propias de la producción y la venta de las prendas.</p>

    <h3>DÉCIMA. TÉRMINO ANTICIPADO Y RESOLUCIÓN</h3>
    <p>Cualquiera de las partes puede poner fin al presente contrato antes de su vencimiento, sin expresión de causa,
    con un aviso escrito de ${d.diasAviso} días calendario.</p>
    <p>Además, cualquiera de las partes puede resolverlo de pleno derecho, conforme al artículo 1430 del Código Civil,
    si la otra incumple alguna de estas prestaciones: ${locador}, la reserva de la información y el cuidado de los
    datos personales de la cláusula octava; ${COMITENTE}, el pago de los honorarios dentro de los quince (15) días
    calendario siguientes a su vencimiento. La resolución opera desde que la parte afectada comunica a la otra, por
    escrito, que se vale de esta cláusula. Para cualquier otro incumplimiento rige el artículo 1429 del Código
    Civil.</p>
    <p>En todos los casos, ${COMITENTE} paga los honorarios por el servicio prestado hasta la fecha de término.</p>

    <h3>UNDÉCIMA. DATOS PERSONALES DE ${locador}</h3>
    <p>${COMITENTE} trata los datos personales de ${locador} —los de identificación, su R.U.C., su domicilio, su firma
    y los registros del servicio prestado— para celebrar y ejecutar este contrato, pagar los honorarios y cumplir las
    obligaciones tributarias y legales que de él se deriven, conforme a la Ley N.° 29733, Ley de Protección de Datos
    Personales, y su reglamento. Esos datos se guardan en Dynamic, el sistema de ${COMITENTE}, que funciona sobre
    servicios de proveedores tecnológicos que pueden estar ubicados fuera del Perú, y se conservan mientras dure el
    contrato y, después, durante el tiempo que exijan esas obligaciones y la defensa de los derechos de las partes.
    ${COMITENTE} solo los comunica a la SUNAT y a las demás autoridades que la ley indique.</p>
    <p>${locador} puede ejercer sus derechos de acceso, actualización, inclusión, rectificación, supresión y
    oposición comunicándolo por escrito a ${COMITENTE}, en la forma de la cláusula duodécima.</p>

    <h3>DUODÉCIMA. COMUNICACIONES</h3>
    <p>Las comunicaciones entre las partes, incluidos los avisos de término y de resolución, se hacen por escrito y se
    entregan en los domicilios indicados en la cláusula primera o al correo electrónico que cada parte haya
    comunicado por escrito a la otra. Un cambio de domicilio o de correo surte efecto desde que se comunica a la otra
    parte.</p>

    <h3>DECIMOTERCERA. FIRMA ELECTRÓNICA</h3>
    <p>Las partes celebran el presente contrato por medios electrónicos, conforme a los artículos 141 y 141-A del
    Código Civil y a la Ley N.° 27269, Ley de Firmas y Certificados Digitales, y su reglamento.</p>
    <p>${COMITENTE} firma con la imagen de la firma de su representante registrada en Dynamic, el sistema de
    ${COMITENTE}. ${locador} firma ingresando a Dynamic con su cuenta personal e intransferible, con el texto completo
    del contrato a la vista, y confirmando su firma: con ello se incorpora al documento la imagen de la firma que
    ${locador} registró en el sistema. Las partes reconocen que esa confirmación expresa su voluntad de obligarse,
    igual que una firma manuscrita.</p>
    <p>Dynamic conserva el texto del contrato tal como se generó, sin que ninguna de las partes pueda modificarlo
    después, y registra la fecha y la hora en que firma cada una, que figuran debajo de su firma. El contrato se
    entiende celebrado en la fecha y la hora en que firma ${locador}. Cada parte puede descargar e imprimir el
    contrato firmado.</p>

    <h3>DECIMOCUARTA. LEY APLICABLE Y JURISDICCIÓN</h3>
    <p>En lo no previsto, se aplica el Código Civil. Las partes se someten a la jurisdicción de los jueces de
    ${ciudad}.</p>

    <p>En señal de conformidad, las partes firman el presente contrato por medios electrónicos, en las fechas que
    figuran debajo de sus firmas.</p>

    <div class="firmas">
      <div>
        <p class="linea">${MARCADOR_FIRMA_EMPRESA}</p>
        <p><strong>${COMITENTE}</strong><br/>${EMPRESA.nombre}<br/>${d.firmanteNombre} · ${d.firmanteCargo}<br/>DNI N.° ${d.firmanteDni}</p>
        <p>${MARCADOR_FECHA_FIRMA_EMPRESA}</p>
      </div>
      <div>
        <p class="linea">${MARCADOR_FIRMA_PERSONA}</p>
        <p><strong>${locador}</strong><br/>${d.nombreDni}<br/>DNI N.° ${d.documento.trim() || falta("EL DNI")}</p>
        <p>${MARCADOR_FECHA_FIRMA_PERSONA}</p>
      </div>
    </div>
    <p class="pie-hoja">${EMPRESA.nombre} · RUC N.° ${EMPRESA.ruc}</p>
  </article>`;
}

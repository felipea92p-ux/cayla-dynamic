// ============================================================================
// locacion-texto.ts — el molde del contrato de LOCACIÓN DE SERVICIOS
// ============================================================================
// QUÉ PROMETE
//   El texto del contrato que firma quien cobra por recibo por honorarios
//   (RxH), armado con sus datos y listo para congelarse en
//   `contratos_locacion.documento_html` (0612). Puro: sin React ni Supabase, se
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
//   Nadie con criterio legal revisó este texto todavía. Mientras
//   `TEXTO_LOCACION_APROBADO` sea `false`, cada documento lleva arriba un aviso
//   visible de borrador, y se imprime con él: un papel sin revisar no puede
//   pasar por definitivo ni por accidente. Cuando el abogado lo apruebe (con
//   los cambios que pida), se cambia la constante en el mismo PR que sus
//   cambios, y se anota quién y cuándo lo aprobó.
// ============================================================================
import { EMPRESA } from "@cayla-dynamic/shared";
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

/** Cómo se pagan los honorarios: una cuota al mes, o un monto por todo el servicio. */
export type PeriodicidadHonorarios = "mensual" | "total";

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

    <p>En ${ciudad}, el ${formatearFecha(d.fechaInicio)}, se celebra el presente Contrato de Locación de Servicios entre:</p>

    <h3>PRIMERA. LAS PARTES</h3>
    <p>${EMPRESA.nombre}, identificada con R.U.C. N.° ${EMPRESA.ruc}, con domicilio legal en ${EMPRESA.domicilio},
    debidamente representada por ${d.firmanteNombre}, identificado(a) con D.N.I. N.° ${d.firmanteDni}, a quien en
    adelante se denominará ${COMITENTE}; y</p>
    <p>${d.nombreDni}, ${segunGenero(d, "identificado", "identificada")} con D.N.I. N.° ${d.documento} y R.U.C.
    N.° ${d.ruc ?? falta("EL RUC, NECESARIO PARA EMITIR EL RECIBO POR HONORARIOS")}${
      d.direccion ? `, con domicilio en ${d.direccion}` : ""
    }, a quien en adelante se denominará ${locador}.</p>

    <h3>SEGUNDA. OBJETO</h3>
    <p>${locador} se obliga a prestar a ${COMITENTE} el servicio de <strong>${d.servicio}</strong>, que comprende:</p>
    ${listaEntregables(datos.entregables)}

    <h3>TERCERA. NATURALEZA CIVIL Y AUTONOMÍA</h3>
    <p>El presente es un contrato de locación de servicios de naturaleza civil, regido por los artículos 1764 a 1770
    del Código Civil. ${locador} presta el servicio con autonomía técnica y organizativa, con sus propios medios y
    bajo su propia dirección, organizando su tiempo como considere conveniente para cumplir con lo encargado, sin
    sujeción a horarios ni a turnos fijados por ${COMITENTE}. Puede prestar servicios a terceros mientras ello no
    afecte el cumplimiento de este contrato ni la confidencialidad pactada.</p>
    <p>El presente contrato no genera relación laboral entre las partes. ${locador} declara conocer que, por su
    naturaleza, no le corresponden los derechos y beneficios propios de una relación laboral.</p>

    <h3>CUARTA. PLAZO</h3>
    <p>El servicio se prestará del ${formatearFecha(d.fechaInicio)} al ${formatearFecha(d.fechaFin)}. Puede
    renovarse por acuerdo escrito de las partes, con un nuevo contrato.</p>

    <h3>QUINTA. HONORARIOS</h3>
    <p>Por el servicio, ${COMITENTE} pagará a ${locador} honorarios de ${pago}, contra la emisión del recibo por
    honorarios electrónico correspondiente. ${COMITENTE} efectuará la retención del Impuesto a la Renta de cuarta
    categoría cuando corresponda conforme a ley, salvo que ${locador} acredite la suspensión de retenciones
    aprobada por la SUNAT.</p>

    <h3>SEXTA. OBLIGACIONES DE ${locador}</h3>
    <ol>
      <li>Prestar el servicio de manera personal y diligente, conforme al artículo 1766 del Código Civil.</li>
      <li>Entregar lo encargado en los plazos acordados con ${COMITENTE} para cada trabajo.</li>
      <li>Emitir el recibo por honorarios electrónico por cada pago.</li>
      <li>Cumplir por su cuenta con sus obligaciones tributarias y con su propio seguro de salud y sistema de
      pensiones.</li>
    </ol>

    <h3>SÉPTIMA. OBLIGACIONES DE ${COMITENTE}</h3>
    <ol>
      <li>Pagar los honorarios en la forma y el plazo pactados.</li>
      <li>Brindar a ${locador} la información que necesite para prestar el servicio.</li>
    </ol>

    <h3>OCTAVA. CONFIDENCIALIDAD</h3>
    <p>${locador} guardará reserva sobre la información de ${COMITENTE} a la que acceda por el servicio —diseños,
    colecciones no lanzadas, precios, proveedores, clientas y procesos— durante la vigencia del contrato y por dos
    (2) años después de su término.</p>

    <h3>NOVENA. RESULTADOS DEL SERVICIO</h3>
    <p>Los diseños, patrones, fotografías, textos y demás resultados que ${locador} cree en ejecución de este
    contrato, y sus derechos patrimoniales, corresponden a ${COMITENTE} desde su creación, en la medida que lo
    permita la ley. Los derechos morales de autor se mantienen conforme al Decreto Legislativo N.° 822.</p>

    <h3>DÉCIMA. RESOLUCIÓN</h3>
    <p>Cualquiera de las partes puede resolver el presente contrato con un aviso escrito de ${d.diasAviso}
    días calendario. ${COMITENTE} puede resolverlo de inmediato si ${locador} incumple la confidencialidad pactada.
    En ambos casos se pagarán los honorarios por el servicio efectivamente prestado hasta la fecha de término.</p>

    <h3>UNDÉCIMA. FIRMA ELECTRÓNICA</h3>
    <p>Las partes acuerdan suscribir el presente contrato mediante firma electrónica en el sistema Dynamic de
    ${COMITENTE}, que registra la fecha y la hora de la aceptación de cada una, conforme al artículo 141-A del
    Código Civil y a la Ley N.° 27269, Ley de Firmas y Certificados Digitales. Cada parte puede descargar e
    imprimir el contrato firmado.</p>

    <h3>DUODÉCIMA. LEY APLICABLE Y DOMICILIO</h3>
    <p>En lo no previsto, se aplica el Código Civil. Las partes señalan como domicilios los indicados en la cláusula
    primera y se someten a la jurisdicción de los jueces de ${ciudad}.</p>

    <p>En señal de conformidad, las partes firman el presente contrato en ${ciudad}.</p>

    <div class="firmas">
      <div>
        <p class="linea">${MARCADOR_FIRMA_EMPRESA}</p>
        <p><strong>${COMITENTE}</strong><br/>${EMPRESA.nombre}<br/>${d.firmanteNombre} · ${d.firmanteCargo}<br/>DNI N.° ${d.firmanteDni}</p>
      </div>
      <div>
        <p class="linea">${MARCADOR_FIRMA_PERSONA}</p>
        <p><strong>${locador}</strong><br/>${d.nombreDni}<br/>DNI N.° ${d.documento}</p>
      </div>
    </div>
    <p class="pie-hoja">${EMPRESA.nombre} · RUC N.° ${EMPRESA.ruc}</p>
  </article>`;
}

import { EMPRESA } from "@cayla-dynamic/shared";
import { Marca } from "@/components/marca";

function fechaLarga(iso: string): string {
  return new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "long", year: "numeric" }).format(
    new Date(`${iso}T12:00:00`),
  );
}

/**
 * El cuerpo legal de la constancia: a quién se entrega, cuánto y por qué. Lo
 * usan la hoja firmada (`PapelBono`) y la que se imprime en papel desde
 * admin/documentacion, para que escaneo y firma digital acrediten exactamente
 * la misma causa — y para que el texto no vuelva a existir en dos sitios.
 *
 * DOS VERSIONES, porque la ley es otra.
 *
 *   · PLANILLA. La cláusula no dice «gratificación extraordinaria», «a título
 *     de liberalidad» ni «a discreción», y eso es deliberado: esas palabras
 *     invocan el inciso a) del art. 19, que exige que el pago sea OCASIONAL, y
 *     la Casación 28833-2022 Lima (considerando décimo sétimo) establece que un
 *     pago repetitivo, incluida la periodicidad ANUAL, ya no es extraordinario.
 *     Además «liberalidad» hace el gasto NO DEDUCIBLE por el art. 44 inciso d)
 *     de la Ley del Impuesto a la Renta. El inciso g) no pide nada de eso: solo
 *     pide la CAUSA, que es el onomástico, y está nombrada literalmente.
 *
 *   · PRACTICANTE (0519). Un convenio de modalidad formativa no es relación
 *     laboral (Ley 28518): la persona no es «trabajador», su subvención no es
 *     remuneración, y ni el TUO del D. Leg. 650 ni el D.S. 003-97-TR le
 *     aplican. Citarlos —o llamarla «trabajador»— en un papel firmado sería
 *     dejar por escrito un indicio de subordinación, que es justo lo que
 *     desnaturaliza la modalidad (art. 51 de la misma ley) y lo que el resto
 *     del sistema evita (0119, 0322). La cláusula nueva dice tres cosas y nada
 *     más: es un reconocimiento por el cumpleaños, no forma parte de la
 *     subvención del convenio ni la modifica, y no compromete a repetirla.
 *
 *     ⚠ TEXTO PROVISIONAL: lo redactó Claude el 2026-10-13 y NO lo ha revisado
 *     el contador ni un abogado laboral. Ver las tres preguntas abiertas en el
 *     encabezado de la migración 0519.
 */
export function TextoBono({ practicante, nombre, documento, monto }: {
  practicante: boolean;
  nombre: string;
  documento: string | null;
  /** Ya formateado: «S/ 180.00». */
  monto: string;
}) {
  return (
    <>
      <p className="mb-4">
        {EMPRESA.nombre}, con RUC {EMPRESA.ruc}, hace entrega a <strong>{nombre}</strong>
        {documento ? `, con documento de identidad ${documento},` : ","}
        {practicante
          ? " quien realiza prácticas en la empresa bajo convenio de modalidad formativa (Ley N.° 28518), "
          : " "}
        de la suma de <strong>{monto}</strong> con ocasión de su {practicante ? "cumpleaños" : "onomástico"}.
      </p>

      {practicante ? (
        <p className="mb-4 border-l-2 border-sand pl-4">
          Esta entrega es un reconocimiento de CAYLA con ocasión del cumpleaños.{" "}
          <strong>No forma parte de la subvención económica del convenio</strong>, no la modifica ni la
          reemplaza, y no crea ningún compromiso de repetirla en el futuro.
        </p>
      ) : (
        <p className="mb-4 border-l-2 border-sand pl-4">
          Esta asignación se otorga con ocasión del onomástico del trabajador, conforme al literal g) del artículo
          19 del Texto Único Ordenado del Decreto Legislativo N° 650, aprobado por Decreto Supremo N° 001-97-TR. En
          consecuencia, <strong>no constituye remuneración computable para ningún efecto legal</strong>, de acuerdo
          con el artículo 7 del Decreto Supremo N° 003-97-TR.
        </p>
      )}
    </>
  );
}

/** La hoja de la constancia — mismo texto legal que imprime admin/documentacion,
 *  para que autoservicio y escaneo acrediten exactamente la misma causa.
 *
 *  La usan dos pantallas: «Tu constancia firmada» en /mio/cumpleanos y el «Ver»
 *  de los cargos de cumpleaños en admin/documentacion. Antes vivía solo en la
 *  primera, y por eso quien firmó desde el sistema no tenía NINGÚN papel que
 *  abrir del lado de Desarrollo Organizacional: no hay archivo en storage, la
 *  firma vive en una columna. */
export function PapelBono({ practicante = false, monto, fecha, estadoPago, nombreOficial, documento, firmaPersona, firmaEmpresa, firmanteNombre, firmanteCargo }: {
  /** Es practicante (modalidad formativa, 0519): otro texto, sin normas laborales. */
  practicante?: boolean;
  monto: number | null;
  /** Cuándo la firmó (= cuándo pidió el bono). Null mientras todavía no la firma. */
  fecha: string | null;
  /** Cómo va el pago, para la última frase. Dos fechas, no una: firmarla es PEDIR
   *  el bono (0478) y la transferencia llega después, así que decir «recibida» el
   *  día del pedido afirmaría una entrega que todavía no pasó.
   *
   *  Opcional A PROPÓSITO: quien la abre desde admin/documentacion no tiene a la
   *  mano si ya se transfirió o va en boleta, y sin el dato lo honesto es no decir
   *  nada — nunca «transferencia pendiente» por no saberlo, en un papel que se
   *  archiva. */
  estadoPago?: {
    /** Cuándo DO confirmó la transferencia (0478). Null mientras no la confirma. */
    transferidoEl: string | null;
    /** Va en su boleta de planilla (0479): entonces no hay transferencia aparte que confirmar. */
    enBoleta: boolean;
  };
  nombreOficial: string | null;
  documento: string | null;
  firmaPersona: string | null;
  firmaEmpresa: string | null;
  firmanteNombre: string | null;
  firmanteCargo: string | null;
}) {
  return (
    <div className="hoja rounded-lg border border-sand p-8 text-sm leading-relaxed print:rounded-none print:border-0 print:p-0">
      <div className="mb-6 flex items-start justify-between border-b border-sand pb-4">
        <Marca tono="tinta" isotipo="rojo" />
        <div className="text-right text-xs text-taupe">
          <p>{EMPRESA.nombre}</p>
          <p>RUC {EMPRESA.ruc}</p>
        </div>
      </div>

      <h2 className="mb-6 text-center font-serif text-xl">
        {practicante ? "Entrega por cumpleaños" : "Asignación por cumpleaños"}
      </h2>

      <TextoBono
        practicante={practicante}
        nombre={nombreOficial ?? "—"}
        documento={documento}
        monto={monto != null ? `S/ ${monto.toFixed(2)}` : "S/ —"}
      />

      <p className="mb-10 text-sm text-taupe">
        La presente constancia acredita la entrega y su causa.{" "}
        {fecha ? `Firmada desde el sistema el ${fechaLarga(fecha)}.` : "Se firma desde el sistema."}
        {estadoPago && (
          estadoPago.enBoleta
            ? " Se paga junto con su planilla, en la boleta del periodo."
            : estadoPago.transferidoEl
              ? ` Transferida el ${fechaLarga(estadoPago.transferidoEl)}.`
              : fecha ? " Transferencia pendiente de confirmar." : ""
        )}
      </p>

      <div className="grid grid-cols-2 gap-10 pt-6">
        <div className="text-center">
          <div className="flex h-24 items-end justify-center">
            {firmaPersona && <img src={firmaPersona} alt="" aria-hidden className="block h-24 w-auto max-w-full" />}
          </div>
          <div className="mb-1 border-t border-tinta pt-2 text-xs">{nombreOficial ?? " "}</div>
          <p className="text-xs text-taupe">Recibí conforme</p>
        </div>
        <div className="text-center">
          <div className="flex h-24 items-end justify-center">
            {firmaEmpresa && <img src={firmaEmpresa} alt="" aria-hidden className="block h-24 w-auto max-w-full" />}
          </div>
          <div className="mb-1 border-t border-tinta pt-2 text-xs">{firmanteNombre ?? "—"}</div>
          <p className="text-xs text-taupe">{firmanteCargo ?? "—"} · {EMPRESA.nombre}</p>
        </div>
      </div>
    </div>
  );
}

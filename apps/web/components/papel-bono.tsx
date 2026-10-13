import { EMPRESA } from "@cayla-dynamic/shared";
import { Marca } from "@/components/marca";

function fechaLarga(iso: string): string {
  return new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "long", year: "numeric" }).format(
    new Date(`${iso}T12:00:00`),
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
export function PapelBono({ monto, fecha, estadoPago, nombreOficial, documento, firmaPersona, firmaEmpresa, firmanteNombre, firmanteCargo }: {
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

      <h2 className="mb-6 text-center font-serif text-xl">Asignación por cumpleaños</h2>

      <p className="mb-4">
        {EMPRESA.nombre}, con RUC {EMPRESA.ruc}, hace entrega a <strong>{nombreOficial ?? "—"}</strong>
        {documento ? `, con documento de identidad ${documento},` : ","} de la suma de{" "}
        <strong>{monto != null ? `S/ ${monto.toFixed(2)}` : "S/ —"}</strong> con ocasión de su onomástico.
      </p>

      <p className="mb-4 border-l-2 border-sand pl-4">
        Esta asignación se otorga con ocasión del onomástico del trabajador, conforme al literal g) del artículo
        19 del Texto Único Ordenado del Decreto Legislativo N° 650, aprobado por Decreto Supremo N° 001-97-TR. En
        consecuencia, <strong>no constituye remuneración computable para ningún efecto legal</strong>, de acuerdo
        con el artículo 7 del Decreto Supremo N° 003-97-TR.
      </p>

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

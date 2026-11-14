import { formatSoles } from "@/lib/rangos";
import { Tabla, TablaEncabezado, Th, Fila } from "@/components/ui/tabla";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Boton } from "@/components/ui/boton";
import { EstadoVacio } from "@/components/ui/estado-vacio";
import { descargarCsv, generarCsv } from "@/lib/admin/csv";
import {
  COLUMNAS_CSV_DEPOSITO,
  diaYMes,
  filasCsvDeposito,
  type Deposito,
} from "@/lib/admin/provisiones";

// La pestaña «Depósito»: una sola pregunta, la del contador el día que paga —
// cuánto le deposito a cada persona y cuánto sale en total—. Todo lo demás
// (gratificación, vacaciones, estados) vive en «Por persona».

const mes = (iso: string) =>
  ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"][
    Number(iso.slice(5, 7)) - 1
  ];

/** La ventana anterior del mismo beneficio, en palabras: «mayo» para la CTS de noviembre. */
function anterior(dep: Deposito): string {
  if (dep.beneficio === "CTS") return mes(dep.fechaLegal) === "noviembre" ? "mayo" : "noviembre";
  return mes(dep.fechaLegal) === "diciembre" ? "julio" : "diciembre";
}

export function ListaDeposito({ deposito: dep }: { deposito: Deposito | null }) {
  if (!dep) {
    return (
      <EstadoVacio>
        Del 16 al 31 de diciembre el próximo pago es del año siguiente y todavía no tiene monto.
      </EstadoVacio>
    );
  }

  const queEs = dep.beneficio === "CTS" ? `CTS de ${mes(dep.fechaLegal)}` : `gratificación de ${mes(dep.fechaLegal)}`;
  const corrida = dep.fechaDeposito !== dep.fechaLegal;
  const hayPendiente = dep.totalPendienteAnterior > 0;
  const hayDeMas = dep.filas.some((f) => f.pagadoDeMas > 0);

  const bajar = () =>
    descargarCsv(
      `deposito-${dep.beneficio === "CTS" ? "cts" : "gratificacion"}-${dep.fechaDeposito}.csv`,
      generarCsv(filasCsvDeposito(dep), [...COLUMNAS_CSV_DEPOSITO]),
    );

  return (
    <section className="grid gap-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="text-lg font-medium">
            {dep.beneficio === "CTS" ? "Depósito" : "Pago"} de la {queEs} · {diaYMes(dep.fechaDeposito)}
          </h2>
          <p className="text-sm text-taupe">
            {dep.beneficio === "CTS"
              ? "A la cuenta CTS de cada persona, no en efectivo."
              : "Con la gratificación va su 9 % (Ley 30334)."}{" "}
            {corrida && `El ${diaYMes(dep.fechaLegal)} cae domingo: se deposita el lunes ${diaYMes(dep.fechaDeposito)}.`}{" "}
            Montos acumulados a hoy según lo registrado en el sistema.
          </p>
        </div>
        <Boton variante="secundario" onClick={bajar}>
          Descargar Excel
        </Boton>
      </div>

      <Tabla className="[font-variant-numeric:tabular-nums]">
        <TablaEncabezado>
          <Th>Persona</Th>
          <Th>Sede</Th>
          <Th className="text-right">A depositar</Th>
          {hayPendiente && <Th className="text-right">Quedó de {anterior(dep)} · por decidir</Th>}
        </TablaEncabezado>
        <tbody>
          {dep.filas.map((f) => (
            <Fila key={f.persona_id}>
              <td className="px-4 py-2">{f.nombre}</td>
              <td className="px-4 py-2">{f.sede}</td>
              <td className="px-4 py-2 text-right">
                <span className="font-medium">{formatSoles(f.aDepositar)}</span>
                {f.pagadoDeMas > 0 && (
                  <span className="block text-xs text-pizarra">ya cobró {formatSoles(f.pagadoDeMas)} de más</span>
                )}
              </td>
              {hayPendiente && (
                <td className="px-4 py-2 text-right text-taupe">
                  {f.pendienteAnterior > 0 ? formatSoles(f.pendienteAnterior) : "—"}
                </td>
              )}
            </Fila>
          ))}
        </tbody>
        <tfoot>
          <tr className="border-t-2 border-tinta/30">
            <td className="px-4 py-3 font-medium" colSpan={2}>
              Total que sale del banco
            </td>
            <td className="px-4 py-3 text-right text-lg font-semibold">{formatSoles(dep.total)}</td>
            {hayPendiente && (
              <td className="px-4 py-3 text-right text-taupe">{formatSoles(dep.totalPendienteAnterior)}</td>
            )}
          </tr>
        </tfoot>
      </Tabla>

      {(hayPendiente || hayDeMas) && (
        <BannerAviso variante="informativo" className="max-w-3xl">
          {hayPendiente && (
            <>
              <strong className="font-medium">«Quedó de {anterior(dep)}» no está en el total.</strong> Es lo que el
              sistema calcula que faltó pagar en {anterior(dep)}, pero el sistema cuenta horas reales y el contador el
              mes completo: parte puede ser solo esa diferencia. Se suma al depósito solo lo que el contador confirme.{" "}
            </>
          )}
          {hayDeMas && (
            <>
              A quien ya cobró de más esta vez se le deposita cero; lo cobrado de más no se le resta a nadie.
            </>
          )}
        </BannerAviso>
      )}
    </section>
  );
}

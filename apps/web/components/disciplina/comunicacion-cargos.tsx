import type { ReactNode } from "react";
import { Marca } from "@/components/marca";
import { EMPRESA } from "@cayla-dynamic/shared";
import { areaNombre, type Area } from "@/lib/areas";
import { fechaCorta, fechaLarga, horaLima, type Hecho, type PersonaMemo, type Previa } from "./memo-documento";

// La COMUNICACIÓN DE CARGOS: el papel que se le entrega a la colaboradora ANTES
// de decidir una amonestación o una suspensión (RIT 55.2, 19.3, 21.3). Sigue los
// Modelos 2 y 7 de `docs/manual-procedimiento-disciplinario.md`.
//
// POR QUÉ EXISTE. Desde la 0566 (29-oct-2026) ninguna amonestación se firma sin
// comunicar antes los cargos y esperar dos días hábiles. El botón «Comunicar
// cargos» guardaba la fecha, pero el sistema no daba el papel: el modal decía
// «el documento lo entregas tú». El único documento imprimible de un borrador
// era el MEMO DE LA SANCIÓN —«se le impone AMONESTACIÓN ESCRITA», con su
// «Recibí conforme»—, y el 2026-11-02 eso fue lo que se le entregó a una
// colaboradora como si fueran los cargos, para que lo firmara.
//
// Ese papel equivocado no es un detalle de forma: el 55.2 manda comunicar los
// hechos «antes de imponer», y un documento que ya dice «se le impone» durante
// el plazo de descargo es la prueba de que la decisión estaba tomada antes de
// escucharla. Además, el numeral 54.2 prohíbe dejar constancia disciplinaria por
// medios ajenos al sistema: si Dynamic no da la comunicación, la empresa la
// improvisa.
//
// QUÉ NO HACE. No decide nada ni abre el plazo: el plazo lo abre «Comunicar
// cargos» en Disciplina (`fn_expediente_comunicar_cargos`). Si se imprime antes,
// el papel dice «dos días hábiles desde la recepción»; si se imprime después,
// trae la fecha y la hora exactas en que vence.
//
// NO CARGA NADA, igual que `MemoDocumento`: recibe todo resuelto.

/** Lo que el papel necesita del documento. */
export interface DocCargos {
  id: string;
  tipo_causal: string;
  nivel: string;
  periodo_desde: string | null;
  hechos: Hecho[];
  suspension_dias: number | null;
  cargos_comunicados_at: string | null;
  descargo_vence_at: string | null;
  falta?: { numeral: string; literal: string; texto: string; gravedad: string } | null;
  conocido_el?: string | null;
}

/** Un día citado tal como lo dice hoy la asistencia (`evidenciaDeDocumento`). */
export interface DiaMedido { fecha: string; esperada: string; marco: string; minutos: number | null }

const CAUSAL: Record<string, string> = { tardanza: "tardanzas", falta: "inasistencia injustificada", conducta: "conducta" };

const NIVEL_EN_PROSA: Record<string, string> = {
  amonestacion: "amonestación escrita",
  suspension: "suspensión sin goce de haber",
};

function mesDe(iso: string | null): string {
  if (!iso) return "el periodo indicado";
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { month: "long", year: "numeric", timeZone: "UTC" }).format(new Date(Date.UTC(y, m - 1, d)));
}

/** La calificación conforme al artículo 53 (55.2 la exige con los hechos). */
function Calificacion({ doc }: { doc: DocCargos }) {
  if (doc.tipo_causal === "tardanza") {
    return <>Tardanzas reiteradas, falta significativa del <strong>literal b) del numeral 53.2</strong> del RIT, con la gradación del numeral 19.2.</>;
  }
  if (doc.tipo_causal === "falta") {
    return <>Inasistencia injustificada, falta significativa del <strong>literal c) del numeral 53.2</strong> del RIT, con la gradación del numeral 21.2.</>;
  }
  if (doc.falta) {
    return (
      <>Falta {doc.falta.gravedad} del <strong>literal {doc.falta.literal}) del numeral {doc.falta.numeral}</strong> del RIT:
        «{doc.falta.texto.replace(/\.\s*$/, "")}».</>
    );
  }
  return <>La que consta en su expediente.</>;
}

/** La sanción que podría corresponder, con la norma que la gradúa. */
function SancionPosible({ doc }: { doc: DocCargos }) {
  const t = doc.tipo_causal;
  if (doc.nivel === "suspension") {
    const dias = doc.suspension_dias ? ` de ${doc.suspension_dias} día${doc.suspension_dias === 1 ? "" : "s"}` : "";
    const norma = t === "tardanza" ? "numeral 19.2" : t === "falta" ? "numeral 21.2" : "numeral 54.8";
    return <><strong>Suspensión sin goce de haber{dias}</strong>, conforme al {norma} del RIT y dentro del tope del numeral 54.5.</>;
  }
  const norma = t === "tardanza" ? "literal b) del numeral 19.2" : t === "falta" ? "literal a) del numeral 21.2" : "numeral 54.8";
  return <><strong>Amonestación escrita</strong>, conforme al {norma} del RIT.</>;
}

export function ComunicacionCargos({
  doc, persona, sede, areas, previas, medicion, children,
}: {
  doc: DocCargos;
  persona: PersonaMemo | null;
  sede: string;
  areas: Area[];
  /** Sanciones entregadas de la misma causal en los doce meses previos. */
  previas: Previa[];
  /** Hora programada y hora registrada de cada día citado; vacío en la conducta. */
  medicion: DiaMedido[];
  /** Lo que la pantalla agrega debajo del papel — nunca va impreso. */
  children?: ReactNode;
}) {
  const nombre = persona ? `${persona.nombres} ${persona.apellidos}` : "—";
  const t = doc.tipo_causal;
  const hecho = doc.hechos?.[0];
  const porFecha = new Map(medicion.map((m) => [m.fecha, m]));
  const vence = doc.descargo_vence_at;

  return (
    <div className="memo hoja mx-auto max-w-[760px] rounded-lg border border-sand p-5 sm:p-10 font-serif text-[13px] leading-relaxed text-tinta print:rounded-none print:border-0 print:p-0">
      <div className="mb-4 flex items-start justify-between border-b border-sand pb-3 print:mb-3 print:pb-2">
        <div>
          <Marca tono="tinta" isotipo="rojo" />
          <p className="mt-2 text-xs text-taupe">{EMPRESA.nombre} · RUC {EMPRESA.ruc}</p>
        </div>
        <div className="text-right">
          <p className="font-medium">Comunicación de cargos</p>
          {/* La referencia ata el papel a su expediente en Dynamic: el borrador
              todavía no tiene correlativo, que llega recién al firmar. */}
          <p className="text-taupe">Ref. {doc.id.slice(0, 8).toUpperCase()}</p>
          <p className="text-taupe">{doc.cargos_comunicados_at ? fechaLarga(doc.cargos_comunicados_at) : "Fecha: ______________"}</p>
        </div>
      </div>

      <table className="mb-4 w-full">
        <tbody>
          <tr><td className="w-16 py-0.5 align-top text-taupe">Para:</td><td className="py-0.5"><strong>{nombre}</strong> · DNI {persona?.documento ?? "—"}</td></tr>
          <tr><td className="py-0.5 align-top text-taupe">Área:</td><td className="py-0.5">{persona ? areaNombre(areas, persona.funcion) : "—"} · Sede {sede || "—"}</td></tr>
        </tbody>
      </table>

      <h2 className="font-serif">Asunto: Comunicación de cargos por {CAUSAL[t] ?? t}, previa a cualquier decisión</h2>

      <div className="mt-3 grid gap-3">
        <p>
          Conforme al numeral 55.2 del Reglamento Interno de Trabajo
          {t === "tardanza" ? " y a su numeral 19.3" : t === "falta" ? " y a su numeral 21.3" : ""}, {EMPRESA.nombre} le
          comunica por escrito los hechos que se le atribuyen, <strong>antes de adoptar decisión alguna</strong>. Esta
          comunicación <strong>no es una sanción</strong> ni afirma su responsabilidad: le da la oportunidad de
          defenderse (numeral 52.7 del RIT).
        </p>

        <p><strong>1. Hechos que se le atribuyen.</strong>{" "}
          {t === "tardanza"
            ? <>Registros de ingreso posteriores a su hora programada en {mesDe(doc.periodo_desde)}:</>
            : t === "falta"
              ? <>Días en que, correspondiéndole laborar, no concurrió al centro de trabajo ni registró marca, sin justificación aceptada:</>
              : hecho
                ? <>El día <strong>{fechaLarga(hecho.fecha)}</strong>, según el relato que sigue
                    {doc.conocido_el ? <>, del que {EMPRESA.nombre} tomó conocimiento el {fechaLarga(doc.conocido_el)} (numeral 52.6 del RIT)</> : null}:</>
                : <>Los que constan en su expediente.</>}
        </p>
      </div>

      {t === "conducta" ? (
        hecho?.relato ? (
          <div className="my-3 border-l-2 border-sand pl-3 text-[12px]">
            <p className="text-taupe">Hecho · {fechaCorta(hecho.fecha)}</p>
            <p className="whitespace-pre-line">{hecho.relato}</p>
          </div>
        ) : null
      ) : (doc.hechos?.length ?? 0) > 0 && (
        // El 19.3 pide entregar «el detalle de las fechas, horas y minutos
        // computados»: por eso van la hora programada y la registrada, no solo
        // la fecha. Salen de la asistencia tal como está hoy.
        <table className="my-3 w-full border-collapse text-[12px]">
          <thead>
            <tr className="border-b text-left text-taupe">
              <th className="py-1 font-normal">#</th>
              <th className="py-1 font-normal">Fecha</th>
              <th className="py-1 font-normal">Hora programada</th>
              <th className="py-1 font-normal">Hora registrada</th>
              {t === "tardanza" && <th className="py-1 font-normal">Minutos</th>}
            </tr>
          </thead>
          <tbody>
            {doc.hechos.map((h, i) => {
              const m = porFecha.get(h.fecha);
              return (
                <tr key={h.fecha} className="border-b">
                  <td className="py-1">{i + 1}</td>
                  <td className="py-1">{fechaCorta(h.fecha)}</td>
                  <td className="py-1">{m?.esperada ?? "—"}</td>
                  <td className="py-1">{m?.marco ?? "—"}</td>
                  {t === "tardanza" && <td className="py-1">{h.minutos ?? "—"}′</td>}
                </tr>
              );
            })}
          </tbody>
        </table>
      )}

      <div className="grid gap-3">
        <p><strong>2. Calificación.</strong> <Calificacion doc={doc} /></p>
        <p>
          <strong>3. Sanción que podría corresponder.</strong> <SancionPosible doc={doc} /> Lo que se decida dependerá de
          la evaluación de su descargo.
        </p>
        {previas.length > 0 && (
          <p>
            <strong>4. Antecedente vigente por la misma causa</strong> (numeral 56.1 del RIT):{" "}
            {previas.map((s, i) => (
              <span key={s.correlativo ?? i}>
                {i > 0 ? "; " : ""}
                {NIVEL_EN_PROSA[s.nivel] ?? s.nivel}
                {s.correlativo ? <> N.º {s.correlativo}</> : null}
                {s.entregado_at ? <>, entregada el {fechaLarga(s.entregado_at)}</> : null}
              </span>
            ))}.
          </p>
        )}
        <p>
          <strong>{previas.length > 0 ? "5" : "4"}. Su descargo.</strong> Puede presentarlo por escrito o verbalmente —en
          este último caso se levanta acta—{" "}
          {vence
            ? <>hasta el <strong>{fechaLarga(vence)}, a las {horaLima(vence)} h</strong></>
            : <>dentro de los <strong>dos (2) días hábiles</strong> siguientes a la recepción de esta comunicación</>}{" "}
          (numeral 55.2 del RIT). Mientras ese plazo corra, ningún documento de sanción produce efecto: permanece como
          borrador. Si no presenta descargo, eso no se toma como aceptación de los cargos. Lo que presente se valorará
          por escrito en el documento que se emita y se archivará en su legajo.
        </p>
        {t === "tardanza" && (
          <p>
            Si cuestiona la autoría de alguno de estos registros, dígalo en su descargo: ese registro no se computará
            mientras no se corrobore con un elemento adicional de convicción (numeral 55.7 del RIT).
          </p>
        )}
        {t === "falta" && (
          <p>
            Si alguno de esos días corresponde a una situación del numeral 20.2 del RIT —descanso semanal, feriado, día
            sin jornada programada, vacaciones, descanso médico, permiso o licencia—, indíquelo: en ese caso no se
            computa.
          </p>
        )}
      </div>

      <div className="firma mt-10 grid grid-cols-2 gap-8 text-[12px] print:break-inside-avoid">
        <div>
          {/* Quien comunica firma a mano: el sistema no guarda quién pulsó
              «Comunicar cargos» como firmante, y no se inventa uno. */}
          <div className="h-24" />
          <div className="border-t pt-1">Quien comunica los cargos</div>
          <p className="mt-1 text-taupe">Nombre y cargo: ______________________</p>
        </div>
        <div>
          <div className="h-24 text-taupe">Recibí esta comunicación:</div>
          <div className="border-t pt-1">{nombre} · DNI {persona?.documento ?? "____"}</div>
          <p className="mt-1 text-taupe">Fecha: __________  Hora: ______</p>
        </div>
      </div>
      <p className="mt-6 text-[11px] text-taupe">
        Constancia de negativa a recibir (si aplica): la colaboradora se negó a recibir la presente comunicación.
        Testigo 1: __________________  ·  Testigo 2: __________________
      </p>

      {children}
    </div>
  );
}

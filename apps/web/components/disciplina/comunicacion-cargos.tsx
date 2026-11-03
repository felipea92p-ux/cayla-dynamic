import type { ReactNode } from "react";
import { Marca } from "@/components/marca";
import { EMPRESA } from "@cayla-dynamic/shared";
import { areaNombre, type Area } from "@/lib/areas";
import { fechaCorta, fechaLarga, horaLima, type Hecho, type PersonaMemo, type Previa } from "./memo-documento";

// La COMUNICACIÓN DE CARGOS: lo que la colaboradora recibe ANTES de que se
// decida una amonestación o una suspensión (RIT 55.2, 19.3, 21.3). Sigue los
// Modelos 2 y 7 de `docs/manual-procedimiento-disciplinario.md`.
//
// POR QUÉ EXISTE. Desde la 0566 (29-oct-2026) ninguna amonestación se firma sin
// comunicar antes los cargos y esperar dos días hábiles. «Comunicar cargos»
// guardaba la fecha y Dynamic no mostraba nada: el 2026-11-02 se le entregó a
// una colaboradora el BORRADOR del memo —«se le impone AMONESTACIÓN ESCRITA»—
// para que lo firmara como si fueran los cargos. Un papel que ya impone,
// entregado durante el plazo, es la prueba de que se decidió antes de escucharla.
//
// DESDE LA 0581 SE VE EN SU INFO, NO SE IMPRIME (Felipe, 2026-11-03: «no
// usaremos hojas o imprimir, tiene que verlo en su sistema»). Por eso no tiene
// líneas de firma ni acta de negativa: la constancia es su «Confirmo que los
// recibí», que la pantalla muestra debajo.
//
// LO PINTAN DOS PANTALLAS —su Info y Disciplina— Y NO CARGA NADA: las dos le
// pasan lo que devuelve `fn_cargos_detalle`, que arma todo en la base. Los
// antecedentes y el corte salen de ahí con el criterio de la base (56.1, 56.5,
// 56.6, sin la llamada verbal); la primera versión los buscaba en la pantalla y
// podía citar una verbal como «antecedente vigente» (revisión del 2026-11-03).

/** Un día citado, tal como lo midió la asistencia (`fn_cargos_detalle.medicion`). */
export interface DiaMedido {
  fecha: string;
  entrada_ts: string | null;
  minutos_tarde: number | null;
  entrada_programada: string | null;
  es_descanso: boolean | null;
}

/** Lo que devuelve `fn_cargos_detalle` (0581). */
export interface CargosDetalle {
  id: string;
  tipo_causal: string;
  nivel: string;
  estado: string;
  periodo_desde: string | null;
  periodo_hasta: string | null;
  hechos: Hecho[];
  suspension_dias: number | null;
  cargos_comunicados_at: string | null;
  descargo_vence_at: string | null;
  plazo_vigente: boolean;
  conocido_el: string | null;
  falta: { numeral: string; literal: string; texto: string; gravedad: string } | null;
  persona: (PersonaMemo & { sede_codigo: string | null }) | null;
  previas: Previa[];
  /** 56.6: fecha final del último documento entregado por la misma causa. */
  corte: string | null;
  medicion: DiaMedido[];
  recepcion: { abierto_at: string; recibido_at: string | null } | null;
  descargos: Array<{ texto: string; presentado_at: string }>;
  recomunicado: { antes_comunicados_at: string; antes_vence_at: string; recomunicado_at: string } | null;
}

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

/**
 * El escalón de una suspensión, con su literal y su rango (19.3: «se indica el
 * escalón que correspondería»). Es la segunda si ya tiene una suspensión
 * vigente por la misma causa. No fija los días: el 19.2 c) los gradúa «según
 * el número de tardanzas, su magnitud en minutos y los antecedentes», y eso se
 * decide después del descargo.
 */
export function escalonDeSuspension(tipo: string, previas: readonly Previa[]): string {
  const segunda = previas.some((p) => p.nivel === "suspension");
  if (tipo === "tardanza") {
    return segunda
      ? "segunda suspensión sin goce de haber, de dos (2) a tres (3) días y de mayor duración que la primera, conforme al literal d) del numeral 19.2"
      : "suspensión sin goce de haber de uno (1) a dos (2) días, conforme al literal c) del numeral 19.2";
  }
  if (tipo === "falta") {
    return segunda
      ? "segunda suspensión sin goce de haber, de dos (2) a tres (3) días y de mayor duración que la primera, conforme al literal c) del numeral 21.2"
      : "suspensión sin goce de haber de uno (1) a dos (2) días, conforme al literal b) del numeral 21.2";
  }
  return "suspensión sin goce de haber de hasta tres (3) días, conforme a los numerales 54.8 y 54.5";
}

/** La sanción que podría corresponder, con la norma que la gradúa. */
function sancionPosible(doc: CargosDetalle): string {
  if (doc.nivel === "suspension") return escalonDeSuspension(doc.tipo_causal, doc.previas);
  if (doc.tipo_causal === "tardanza") return "amonestación escrita, conforme al literal b) del numeral 19.2";
  if (doc.tipo_causal === "falta") return "amonestación escrita, conforme al literal a) del numeral 21.2";
  return "amonestación escrita, conforme al numeral 54.8";
}

function Calificacion({ doc }: { doc: CargosDetalle }) {
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

export function ComunicacionCargos({
  doc, areas, children,
}: {
  doc: CargosDetalle;
  areas: Area[];
  /** Lo que la pantalla agrega debajo (la constancia, el descargo). */
  children?: ReactNode;
}) {
  const persona = doc.persona;
  const nombre = persona ? `${persona.nombres} ${persona.apellidos}` : "—";
  const t = doc.tipo_causal;
  const hecho = doc.hechos?.[0];
  const porFecha = new Map(doc.medicion.map((m) => [m.fecha, m]));
  const vence = doc.descargo_vence_at;
  const numPrevias = doc.previas.length > 0 ? 1 : 0;

  return (
    <div className="memo hoja mx-auto max-w-[760px] rounded-lg border border-sand p-5 sm:p-10 font-serif text-[13px] leading-relaxed text-tinta">
      <div className="mb-4 flex items-start justify-between border-b border-sand pb-3">
        <div>
          <Marca tono="tinta" isotipo="rojo" />
          <p className="mt-2 text-xs text-taupe">{EMPRESA.nombre} · RUC {EMPRESA.ruc}</p>
        </div>
        <div className="text-right">
          <p className="font-medium">Comunicación de cargos</p>
          {/* Ata la comunicación a su expediente: el borrador no tiene correlativo hasta que se firma. */}
          <p className="text-taupe">Ref. {doc.id.slice(0, 8).toUpperCase()}</p>
          <p className="text-taupe">{doc.cargos_comunicados_at ? fechaLarga(doc.cargos_comunicados_at) : "Todavía sin comunicar"}</p>
        </div>
      </div>

      <table className="mb-4 w-full">
        <tbody>
          <tr><td className="w-16 py-0.5 align-top text-taupe">Para:</td><td className="py-0.5"><strong>{nombre}</strong> · DNI {persona?.documento ?? "—"}</td></tr>
          <tr><td className="py-0.5 align-top text-taupe">Área:</td><td className="py-0.5">{persona ? areaNombre(areas, persona.funcion) : "—"} · Sede {persona?.sede_codigo ?? "—"}</td></tr>
        </tbody>
      </table>

      <h2 className="font-serif">Asunto: Comunicación de cargos por {CAUSAL[t] ?? t}, previa a cualquier decisión</h2>

      <div className="mt-3 grid gap-3">
        <p>
          Conforme al numeral 55.2 del Reglamento Interno de Trabajo
          {t === "tardanza" ? " y a su numeral 19.3" : t === "falta" ? " y a su numeral 21.3" : ""}, {EMPRESA.nombre} le
          comunica los hechos que se le atribuyen, <strong>antes de adoptar decisión alguna</strong>. Esta comunicación{" "}
          <strong>no es una sanción</strong> ni afirma su responsabilidad: le da la oportunidad de defenderse (numeral 52.7
          del RIT).
        </p>

        <p><strong>1. Hechos que se le atribuyen.</strong>{" "}
          {t === "tardanza"
            ? <>Registros de ingreso posteriores a su hora programada en {mesDe(doc.periodo_desde)}:</>
            : t === "falta"
              ? <>Días en que, correspondiéndole laborar según su horario, no concurrió al centro de trabajo ni registró marca, sin justificación aceptada:</>
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
        // 19.3: «el detalle de las fechas, horas y minutos computados». En una
        // inasistencia no hay hora que mostrar: ese día no hubo jornada.
        <table className="my-3 w-full border-collapse text-[12px]">
          <thead>
            <tr className="border-b text-left text-taupe">
              <th className="py-1 font-normal">#</th>
              <th className="py-1 font-normal">Fecha</th>
              {t === "tardanza" && <>
                <th className="py-1 font-normal">Hora programada</th>
                <th className="py-1 font-normal">Hora registrada</th>
                <th className="py-1 font-normal">Minutos</th>
              </>}
            </tr>
          </thead>
          <tbody>
            {doc.hechos.map((h, i) => {
              const m = porFecha.get(h.fecha);
              // Los minutos son los del documento. Si la asistencia de hoy dice
              // otra cosa, se ve al lado: la hora y los minutos no se contradicen
              // en silencio.
              const hoy = m?.minutos_tarde ?? null;
              return (
                <tr key={`${h.fecha}-${i}`} className="border-b">
                  <td className="py-1">{i + 1}</td>
                  <td className="py-1">{fechaCorta(h.fecha)}</td>
                  {t === "tardanza" && <>
                    <td className="py-1">{m?.entrada_programada ? m.entrada_programada.slice(0, 5) : m?.es_descanso ? "Descanso" : "—"}</td>
                    <td className="py-1">{m?.entrada_ts ? horaLima(m.entrada_ts) : "—"}</td>
                    <td className="py-1">
                      {h.minutos ?? "—"}′{hoy !== null && h.minutos !== undefined && hoy !== h.minutos ? ` (hoy ${hoy}′)` : ""}
                    </td>
                  </>}
                </tr>
              );
            })}
          </tbody>
        </table>
      )}

      <div className="grid gap-3">
        <p><strong>2. Calificación.</strong> <Calificacion doc={doc} /></p>
        <p>
          <strong>3. Sanción que podría corresponder.</strong> {sancionPosible(doc).replace(/^./, (c) => c.toUpperCase())} del
          RIT. Lo que se decida dependerá de la evaluación de su descargo.
        </p>
        {doc.previas.length > 0 && (
          <p>
            <strong>4. Antecedente vigente por la misma causa</strong> (numeral 56.1 del RIT):{" "}
            {doc.previas.map((s, i) => (
              <span key={s.correlativo ?? i}>
                {i > 0 ? "; " : ""}
                {NIVEL_EN_PROSA[s.nivel] ?? "documento"}
                {s.correlativo ? <> N.º {s.correlativo}</> : null}
                {s.entregado_at ? <>, entregada el {fechaLarga(s.entregado_at)}</> : null}
              </span>
            ))}.
          </p>
        )}
        <p>
          <strong>{4 + numPrevias}. Corte del cómputo.</strong>{" "}
          {doc.corte
            ? <>No se computa ningún hecho anterior al {fechaLarga(doc.corte)}, fecha final del último documento entregado por la misma causa (numeral 56.6 del RIT).</>
            : <>No hay un documento entregado anterior por la misma causa (numeral 56.6 del RIT).</>}
        </p>
        <p>
          <strong>{5 + numPrevias}. Su descargo.</strong> Puede presentarlo por escrito, en su Info de Dynamic, o
          verbalmente ante su líder de equipo o Desarrollo Organizacional —en este caso se levanta acta—, dentro de los{" "}
          <strong>dos (2) días hábiles</strong> siguientes a esta comunicación
          {vence ? <>, es decir, <strong>hasta el {fechaLarga(vence)}, a las {horaLima(vence)} h</strong></> : null}{" "}
          (numeral 55.2 del RIT). Mientras ese plazo corra, ningún documento de sanción produce efecto: permanece como
          borrador. Si no presenta descargo, eso no se toma como aceptación de los cargos. Lo que presente se valorará
          por escrito antes de decidir y se archivará en su legajo.
        </p>
        {t === "tardanza" && (
          <p>
            Si cuestiona la autoría o la hora de alguno de estos registros, dígalo en su descargo: ese registro no se
            computará mientras no se corrobore con un elemento adicional de convicción (numerales 16.3, 19.5 y 55.7 del
            RIT). Si alguna de esas fechas corresponde a una situación justificable, puede presentar su justificación
            conforme al artículo 18 del RIT.
          </p>
        )}
        {t === "falta" && (
          <>
            <p>
              No constituyen inasistencia ni se computan el descanso semanal, los feriados, los días sin jornada
              programada, el descanso vacacional aprobado, el descanso médico o el certificado de incapacidad temporal,
              los permisos y licencias autorizados o previstos por ley, los días de suspensión ya cumplida y el descanso
              sustitutorio (numeral 20.2 del RIT). Si alguno de esos días corresponde a una de estas situaciones,
              indíquelo: en ese caso no se computa. La justificación presentada fuera de plazo, con documento idóneo, se
              evalúa igualmente (numeral 20.4 del RIT).
            </p>
            {/* El art. 22 va aparte y a DO: su descargo lo lee su líder de equipo, y
                el 22.2 y el 22.5 dicen que ese motivo no se explica ni se le comunica
                a ella (revisión del 2026-11-03). */}
            <p>
              Si alguno de esos días corresponde a una situación del artículo 22 del RIT, comuníquelo directamente a
              Desarrollo Organizacional, sin dar explicaciones y no en este descargo: ese día no se computa y el motivo
              se mantiene en reserva.
            </p>
          </>
        )}
      </div>

      {children}
    </div>
  );
}

import type { ReactNode } from "react";
import { Marca } from "@/components/marca";
import { EMPRESA, TZ_LIMA } from "@cayla-dynamic/shared";
import { areaNombre, type Area } from "@/lib/areas";

// El memo disciplinario tal como se lee y se imprime. Vive acá y no dentro de la
// pantalla del panel porque lo pintan DOS pantallas: la de Disciplina, donde
// quien lo emite lo revisa e imprime, y la de Info, donde la persona lo lee para
// recibirlo (0486). Un documento legal escrito dos veces es un documento que un
// día dice dos cosas distintas.
//
// NO CARGA NADA: recibe el documento y quienes intervienen ya resueltos. Quién
// firmó y con qué cargo lo resuelve cada pantalla con lo que su sesión puede
// leer —la de Disciplina desde la ficha; la de Info desde `fn_mi_memo`, que
// puede nombrar a quien firmó aunque la RLS de la persona no le deje ver esa
// ficha—. Aquí solo se pinta.

export function fechaCorta(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "long", year: "numeric", timeZone: "UTC" })
    .format(new Date(Date.UTC(y, m - 1, d)));
}
/**
 * Fecha en letras, aceptando tanto una fecha plana (`2026-07-30`) como un
 * instante (`2026-07-30T20:03:00Z`).
 *
 * La distinción NO es cosmética. Un `timestamptz` formateado en UTC se corre un
 * día para cualquier entrega hecha después de las 7 p.m. hora de Lima, y de la
 * fecha de entrega cuelgan los seis días de descargo del art. 31. Una fecha
 * plana, en cambio, ya viene sin huso y hay que fijarla a mediodía UTC para que
 * no retroceda al pintarla.
 */
export function fechaLarga(iso: string): string {
  const fmt = (d: Date, tz: string) =>
    new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "long", year: "numeric", timeZone: tz }).format(d);
  if (iso.length === 10) {
    const [y, m, d] = iso.split("-").map(Number);
    return fmt(new Date(Date.UTC(y, m - 1, d)), "UTC");
  }
  return fmt(new Date(iso), TZ_LIMA);
}
/** El nivel dicho dentro de una frase, en minúscula. */
const NIVEL_EN_PROSA: Record<string, string> = {
  verbal: "llamada verbal de atención",
  amonestacion: "amonestación escrita",
  suspension: "suspensión sin goce de haber",
  imputacion: "imputación de cargos",
  despido: "carta de despido",
};
function mesDe(iso: string | null): string {
  if (!iso) return "";
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { month: "long", year: "numeric", timeZone: "UTC" }).format(new Date(Date.UTC(y, m - 1, d)));
}

export const TITULO: Record<string, string> = {
  verbal: "Acta de llamada verbal de atención",
  amonestacion: "Amonestación escrita",
  suspension: "Suspensión sin goce de haber",
  imputacion: "Imputación de cargos — carta de preaviso",
  despido: "Carta de despido por causa justa",
};
const CAUSAL: Record<string, string> = { tardanza: "tardanzas reiteradas", falta: "inasistencias injustificadas", conducta: "conducta" };

/**
 * Qué inciso del art. 25 de la LPCL corresponde a cada causal.
 *
 * ⚠️ TARDANZA VA POR EL INCISO h), NO POR EL a). Hasta el 2026-08-10 este mapa
 * era un ternario que mandaba la tardanza al a) y todo lo demás al h), y estaba
 * mal en los dos extremos.
 *
 * El h) nombra la conducta literalmente: «…la impuntualidad reiterada, si ha
 * sido acusada por el empleador, siempre que se hayan aplicado sanciones
 * disciplinarias previas de amonestaciones escritas y suspensiones». La Casación
 * de Lambayeque sobre despido por tardanzas razona sobre ese inciso, y
 * `docs/disciplina-tardanzas-faltas/00-normativa-y-diseno.md` §1.3 ya lo decía
 * — eran las plantillas las que estaban equivocadas.
 *
 * Y NO ES SOLO CORRECCIÓN FORMAL: el h) es el camino exigente, porque pide
 * amonestación escrita Y suspensión previas. Imputar por el a) —el genérico de
 * buena fe laboral— teniendo el h) disponible le regala a la otra parte el
 * argumento de que la empresa esquivó los requisitos de la norma específica.
 *
 * `conducta` sí va por el a): es el incumplimiento de obligaciones de trabajo
 * que supone quebrantamiento de la buena fe laboral. Antes caía en el h) por
 * descarte, que habla de ausencias y de impuntualidad — nada que ver.
 */
const INCISO_ART25: Record<string, string> = {
  tardanza: "inciso h)",   // impuntualidad reiterada
  falta: "inciso h)",      // abandono y ausencias injustificadas
  conducta: "inciso a)",   // incumplimiento de obligaciones / buena fe laboral
};

export interface Hecho { fecha: string; minutos?: number }
/** Una sanción anterior de la misma causal, para citarla en la imputación. */
export interface Previa { correlativo: string | null; nivel: string; firmado_at: string | null; entregado_at: string | null }

/** Lo que el papel necesita del documento. */
export interface DocMemo {
  correlativo: string | null; tipo_causal: string; nivel: string; estado: string;
  periodo_desde: string | null; hechos: Hecho[];
  suspension_dias: number | null; suspension_desde: string | null; suspension_hasta: string | null;
  suspension_fechas: string[] | null;
  fecha_cese?: string | null;
  firmado_at: string | null; creado_at: string;
}
/** Lo que el papel necesita de la persona. */
export interface PersonaMemo { nombres: string; apellidos: string; documento: string | null; funcion: string }

function Cuerpo({ doc, previas }: { doc: DocMemo; previas: Previa[] }) {
  const n = doc.hechos?.length ?? 0;
    const t = doc.tipo_causal;
    const nivel = doc.nivel;
    if (nivel === "amonestacion" && t === "tardanza") {
      return (
        <>
          <p>El presente memorándum deja constancia de que, durante el mes de <strong>{mesDe(doc.periodo_desde)}</strong>, usted registró <strong>{n} tardanzas</strong>, superando el umbral b) del artículo 7 del Reglamento Interno de Trabajo de {EMPRESA.nombre} (tres o más tardanzas en un mismo mes calendario), según el detalle de las marcaciones que a continuación se indica.</p>
          <p>Las tardanzas detalladas no han sido objeto de sanción disciplinaria previa. El descuento proporcional por el tiempo no laborado, de haberse aplicado en planilla, tiene naturaleza contraprestativa y es independiente de esta sanción; no la sustituye.</p>
          <p>Por lo expuesto, se le impone <strong>AMONESTACIÓN ESCRITA</strong>, que se incorpora a su legajo como antecedente disciplinario con vigencia de doce (12) meses desde su notificación (numeral 56.1 del RIT). Se le exhorta a corregir su puntualidad. La reincidencia dará lugar a <strong>suspensión sin goce de haber</strong> conforme al literal c) del numeral 19.2 del RIT.</p>
        </>
      );
    }
    if (nivel === "amonestacion" && t === "falta") {
      return (
        <>
          <p>El presente memorándum deja constancia de que, correspondiéndole laborar en la(s) fecha(s) que se detalla(n), usted <strong>no concurrió al centro de trabajo ni registró marca alguna</strong> en el sistema de control de asistencia, sin que exista justificación aceptada dentro del plazo previsto en el numeral 20.4 del RIT.</p>
          <p>La inasistencia injustificada constituye falta conforme al literal c) del numeral 53.2 del RIT y contraviene el deber de asistencia y puntualidad (artículo 20 del RIT). El descuento del día no laborado y de la parte proporcional del descanso semanal es independiente de esta sanción.</p>
          <p>Por lo expuesto, se le impone <strong>AMONESTACIÓN ESCRITA</strong>, incorporada a su legajo por doce (12) meses (numeral 56.1 del RIT). Una nueva inasistencia injustificada dará lugar a <strong>suspensión sin goce de haber</strong> (artículo 8.3-b), y la acumulación de ausencias puede configurar causal de despido conforme al artículo 25-h de la LPCL.</p>
        </>
      );
    }
    if (nivel === "suspension") {
      const art = t === "tardanza" ? "literal c) del numeral 19.2" : "literal b) del numeral 21.2";
      return (
        <>
          <p>Habiendo sido usted <strong>amonestado por escrito con anterioridad</strong> por {CAUSAL[t]}, y habiendo reincidido según el detalle que se indica, se configura el {art} del RIT. Estos hechos son nuevos y posteriores a la sanción previa; no se recuenta ninguno ya sancionado.</p>
          {/* Con las fechas exactas se enumeran una por una; sin ellas se cae al
              rango, que es lo único que había antes de la 0075. Un rango sobre
              días no contiguos afirma algo falso sobre el alcance del castigo. */}
          <p>Por lo expuesto, se le impone <strong>SUSPENSIÓN SIN GOCE DE HABER</strong> por <strong>{doc.suspension_dias} día(s)</strong>
            {doc.suspension_fechas?.length
              ? <>, los días <strong>{doc.suspension_fechas.map(fechaCorta).join(", ")}</strong></>
              : doc.suspension_desde && <>, del <strong>{fechaCorta(doc.suspension_desde)}</strong>{doc.suspension_hasta && <> al <strong>{fechaCorta(doc.suspension_hasta)}</strong></>}</>}
            . Durante ese periodo no deberá concurrir al centro de trabajo ni percibirá remuneración (numeral 54.5 del RIT).</p>
          {/* La vigencia se dice aquí igual que en la amonestación. Sin ella, el
              papel no informa cuánto pesa en el legajo — y de esa vigencia
              depende que la siguiente sanción escale o vuelva a empezar. */}
          <p>Esta sanción se incorpora a su legajo como antecedente disciplinario con vigencia de <strong>doce (12) meses</strong> desde su notificación (numeral 56.1 del RIT).</p>
          <p>Se le advierte que, de persistir, {EMPRESA.nombre} iniciará el procedimiento de despido por causa justa previsto en el artículo 31 de la LPCL.</p>
        </>
      );
    }
    if (nivel === "imputacion") {
      const inc = INCISO_ART25[t] ?? "inciso a)";
      return (
        <>
          <p>En cumplimiento del <strong>artículo 31 de la LPCL</strong>, {EMPRESA.nombre} le <strong>imputa los cargos</strong> que se detallan y le otorga un plazo no menor de <strong>seis (6) días naturales</strong>, contados desde la recepción del presente, para que presente por escrito sus descargos ante la Gerencia General.</p>
          {/* Las sanciones previas van NOMBRADAS, no aludidas. El inciso h) no
              exige que existan: exige que se hayan APLICADO, y eso es lo que hay
              que poder probar. Un documento que dice «las que constan en su
              legajo» obliga a abrir el legajo para saber si el requisito se
              cumple; uno que las enumera se defiende solo. */}
          {previas.length > 0 && (
            <p>
              Constan en su legajo las siguientes sanciones disciplinarias previas por la misma causa,
              todas ellas notificadas y con cargo de recepción archivado:{" "}
              {previas.map((s, i) => (
                <span key={s.correlativo ?? i}>
                  {i > 0 ? "; " : ""}
                  <strong>{NIVEL_EN_PROSA[s.nivel] ?? s.nivel}</strong>
                  {s.correlativo ? <> N.º <strong>{s.correlativo}</strong></> : null}
                  {s.entregado_at ? <>, entregada el {fechaLarga(s.entregado_at)}</>
                    : s.firmado_at ? <>, suscrita el {fechaLarga(s.firmado_at)}</> : null}
                </span>
              ))}.
            </p>
          )}
          <p>Los hechos, referidos a {CAUSAL[t]} y precedidos de las sanciones disciplinarias {previas.length > 0 ? "antes detalladas" : "que constan en su legajo"}, configurarían <strong>falta grave</strong> conforme al artículo <strong>25, {inc}</strong>, de la LPCL, en concordancia con el RIT. La presente imputación no afirma su responsabilidad: garantiza su derecho de defensa.</p>
          <p>La causa aquí imputada vincula una eventual carta de despido y no podrá variarse.</p>
        </>
      );
    }
    if (nivel === "despido") {
      const inc = INCISO_ART25[t] ?? "inciso a)";
      return (
        <>
          <p>Evaluados el historial disciplinario y los descargos presentados —o vencido el plazo sin presentarlos—, {EMPRESA.nombre} concluye que usted ha incurrido en <strong>falta grave</strong> conforme al artículo <strong>25, {inc}</strong>, de la LPCL.</p>
          {/* El art. 32 exige que la carta indique de modo preciso la causa Y LA
              FECHA del cese. Sin fecha, la carta está incompleta — y el hueco no
              se puede rellenar a mano después, porque el documento se imprime
              desde la base. Si falta, se dice en rojo y no se disimula. */}
          <p>
            En consecuencia, y conforme al <strong>artículo 32 de la LPCL</strong>, se comunica la{" "}
            <strong>extinción del contrato de trabajo por causa justa</strong>
            {doc.fecha_cese
              ? <>, con fecha de cese el <strong>{fechaLarga(doc.fecha_cese)}</strong></>
              : <span className="text-rojo"> [FALTA LA FECHA DE CESE — el art. 32 la exige; fíjala en el borrador antes de firmar]</span>}
            . Se procederá a la liquidación de sus beneficios sociales y a la entrega del certificado de trabajo.
          </p>
        </>
      );
    }
    return <p>Documento de {CAUSAL[t]}.</p>;
}

export function MemoDocumento({
  doc, persona, sede, areas, firmante, cargoFirmante, firmaUrl, previas, firmanteIlegible = false, children,
}: {
  doc: DocMemo;
  persona: PersonaMemo | null;
  sede: string;
  areas: Area[];
  /** Nombre de quien lo suscribe; null = «Pendiente de firma». */
  firmante: string | null;
  cargoFirmante: string | null;
  firmaUrl: string | null;
  previas: Previa[];
  /** Firmado, pero la sesión no pudo leer la ficha de quien firma (solo el panel). */
  firmanteIlegible?: boolean;
  /** Lo que la pantalla agrega debajo del papel — nunca va impreso. */
  children?: ReactNode;
}) {
  const nombre = persona ? `${persona.nombres} ${persona.apellidos}` : "—";
  const n = doc.hechos?.length ?? 0;
  const esNivel4 = doc.nivel === "imputacion" || doc.nivel === "despido";

  return (
      <div className="memo hoja mx-auto max-w-[760px] rounded-lg border border-sand p-10 font-serif text-[13px] leading-relaxed text-tinta print:rounded-none print:border-0 print:p-0">
        {esNivel4 && (
          <p className="mb-4 rounded bg-ambar/15 px-3 py-2 text-xs text-ambar print:hidden">
            Documento de Nivel 4. Antes de emitirlo, valídalo con un abogado laboralista y entrégalo en físico o por vía notarial (nunca por correo).
          </p>
        )}
        {doc.estado === "borrador" && (
          // SIN `print:hidden`, y es deliberado. Este aviso llevaba la
          // clase y se borraba justo en el papel: en pantalla ponía
          // «borrador», e impreso no ponía nada. Imprimir un borrador para
          // revisarlo es legítimo y por eso no se deshabilita el botón —
          // lo que no puede pasar es que el papel no diga lo que es.
          <p className="mb-4 rounded border border-ambar/40 bg-ambar/15 px-3 py-2 text-xs text-ambar">
            <strong>BORRADOR — sin numerar y sin firmar.</strong> No tiene validez como
            documento entregado. Fírmalo en la pantalla de Disciplina para asignarle su número.
          </p>
        )}
        {firmanteIlegible && (
          <p className="mb-4 rounded bg-sand/50 px-3 py-2 text-xs text-taupe print:hidden">
            No se pudo leer la ficha de quien firma este documento —lo normal es que sea de
            otra sede—, así que abajo figura el representante legal de la empresa. Si lo
            suscribió otra persona, compruébalo antes de entregarlo.
          </p>
        )}

        <div className="mb-4 flex items-start justify-between border-b border-sand pb-3 print:mb-3 print:pb-2">
          <div>
            <Marca tono="tinta" isotipo="rojo" />
            <p className="mt-2 text-xs text-taupe">{EMPRESA.nombre} · RUC {EMPRESA.ruc}</p>
          </div>
          <div className="text-right">
            <p className="font-medium">{doc.correlativo ?? "BORRADOR — sin numerar"}</p>
            <p className="text-taupe">{fechaCorta((doc.firmado_at ?? doc.creado_at).slice(0, 10))}</p>
          </div>
        </div>

        <table className="mb-4 w-full">
          <tbody>
            <tr><td className="w-16 py-0.5 align-top text-taupe">Para:</td><td className="py-0.5"><strong>{nombre}</strong> · DNI {persona?.documento ?? "—"}</td></tr>
            <tr><td className="py-0.5 align-top text-taupe">Área:</td><td className="py-0.5">{persona ? areaNombre(areas, persona.funcion) : "—"} · Sede {sede || "—"}</td></tr>
            <tr><td className="py-0.5 align-top text-taupe">De:</td><td className="py-0.5">{firmante ? `${firmante}${cargoFirmante ? ` · ${cargoFirmante}` : ""}` : <em>Pendiente de firma</em>}</td></tr>
          </tbody>
        </table>

        <h2 className="font-serif">Asunto: {TITULO[doc.nivel]} por {CAUSAL[doc.tipo_causal]}</h2>
        <div className="mt-3"><Cuerpo doc={doc} previas={previas} /></div>

        {n > 0 && (
          <table className="my-4 w-full border-collapse text-[12px]">
            <thead>
              <tr className="border-b text-left text-taupe">
                <th className="py-1 font-normal">#</th>
                <th className="py-1 font-normal">Fecha</th>
                {doc.tipo_causal === "tardanza" && <th className="py-1 font-normal">Minutos de tardanza</th>}
              </tr>
            </thead>
            <tbody>
              {doc.hechos.map((h, i) => (
                <tr key={i} className="border-b">
                  <td className="py-1">{i + 1}</td>
                  <td className="py-1">{fechaCorta(h.fecha)}</td>
                  {doc.tipo_causal === "tardanza" && <td className="py-1">{h.minutos ?? "—"}′</td>}
                </tr>
              ))}
            </tbody>
          </table>
        )}

        <div className="firma mt-10 grid grid-cols-2 gap-8 text-[12px] print:break-inside-avoid">
          <div>
            <div className="flex h-28 items-end justify-center">
              {firmaUrl && !esNivel4 && (
                <img src={firmaUrl} alt="" aria-hidden className="block h-28 w-auto max-w-full" />
              )}
            </div>
            <div className="border-t pt-1">{firmante ?? "Pendiente de firma"}</div>
            <p className="text-taupe">{cargoFirmante ? `${cargoFirmante} — ${EMPRESA.nombre}` : EMPRESA.nombre}</p>
          </div>
          <div>
            <div className="h-28 text-taupe">Recibí conforme:</div>
            <div className="border-t pt-1">{nombre} · DNI {persona?.documento ?? "____"}</div>
            <p className="mt-1 text-taupe">Fecha: __________  Hora: ______</p>
          </div>
        </div>
        <p className="mt-6 text-[11px] text-taupe">
          Constancia de negativa a recibir (si aplica): el colaborador se negó a recibir el presente documento.
          Testigo 1: __________________  ·  Testigo 2: __________________
        </p>


      {children}
      </div>
  );
}

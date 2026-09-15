"use client";

// El panel de un caso disciplinario: todo lo que hace falta para entender por
// qué alguien aparece en Disciplina ANTES de tocar un documento.
//
// Nació en el rediseño del 2026-09-15 (decisión «revisar primero»). Hasta
// entonces el caso se leía desde un contador —«2 de 3 en setiembre · aviso»—
// y el botón «Generar borrador» estaba en la misma fila, así que se podía
// preparar un documento sin haber visto un solo día de evidencia.
//
// Promete: mostrar la regla que se activó, cada día de evidencia con lo que
// dice HOY la asistencia, los antecedentes y el rastro del documento.
// No promete: decidir nada. Las acciones llegan hechas desde la página
// (`acciones`) porque son las mismas que ofrece la fila; dos listas de
// acciones para el mismo documento terminan ofreciendo cosas distintas.

import { useEffect, useState, type ReactNode, type RefObject } from "react";
import Link from "next/link";
import type { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Drawer } from "@/components/ui/drawer";
import { Insignia } from "@/components/ui/insignia";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { cx } from "@/components/ui/cx";
import {
  NIVEL_DISCIPLINARIO_LABELS, fechaLima, hoyLima, nombreDelMesLima, primeroDeMesLima, rangoDelDiaLima,
} from "@cayla-dynamic/shared";
import {
  antecedentesVigentes, esGradual, etapaDelBorrador, eventosDeObservacion, UMBRAL_FALTAS,
  type Adjunto, type DocDisciplina, type FaltaRow, type SituacionDeteccion, type TardanzaRow, type TipoPapel,
} from "@/lib/admin/disciplina";
import { evidenciaDeDocumento, evidenciaDeTardanzasDelMes, type Evidencia } from "@/lib/admin/disciplina-evidencia";
import { addDias, fechaCorta, selloLima, ultimoDiaDelMes } from "./formato";

type Cliente = ReturnType<typeof createAdminSupabaseClient>;

export type CasoAbierto =
  | { tipo: "tardanza"; personaId: string }
  | { tipo: "falta"; personaId: string }
  | { tipo: "documento"; id: string };

export interface PersonaInfo { nombre: string; sede: string; estado: string; fechaCese: string | null }

export const CAUSAL_LABEL: Record<string, string> = { tardanza: "Tardanzas", falta: "Faltas", conducta: "Conducta" };

/** Cómo se dice en pantalla cada medio de entrega. */
export const MEDIO_ENTREGA: Record<string, string> = {
  fisico: "en mano",
  correo: "por correo",
  notarial: "por conducto notarial",
  acta_negativa: "con acta de negativa a firmar",
};

export const ETIQUETA_PAPEL: Record<TipoPapel, string> = {
  cargo_firmado: "Ver cargo", acta_negativa: "Ver acta de negativa", descargo: "Ver descargo",
};

export const ESTADO_DOCUMENTO: Record<string, { texto: string; variante: "neutral" | "alerta" | "advertencia" | "positivo" | "informativo" }> = {
  borrador: { texto: "Borrador", variante: "informativo" },
  firmado: { texto: "Firmado · por entregar", variante: "advertencia" },
  entregado: { texto: "Entregado", variante: "positivo" },
  anulado: { texto: "Anulado", variante: "neutral" },
  cerrado_sin_entrega: { texto: "Cerrado sin entrega", variante: "neutral" },
};

const ETIQUETA_DESCARGO: Record<string, string> = {
  sin_descargo: "no presentó descargo", total: "descargo acogido", parcial: "descargo acogido en parte", no: "descargo no acogido",
};

const ESCALON_POR_MINIMO: Record<number, string> = {
  3: "sin antecedente vigente",
  2: "tras una amonestación",
  1: "tras una suspensión",
};

export function PanelCaso(props: {
  caso: CasoAbierto | null;
  onCerrar: () => void;
  volverElFocoA: RefObject<HTMLElement | null>;
  /** Mientras hay un Modal abierto encima: Escape no debe cerrar también el panel. */
  bloqueado: boolean;
  supabase: Cliente;
  docs: DocDisciplina[];
  adjuntos: Map<string, Adjunto[]>;
  personas: Map<string, PersonaInfo>;
  tardanza: TardanzaRow | null;
  falta: FaltaRow | null;
  situacion: SituacionDeteccion | null;
  mesTard: string;
  nombresAusencia: Map<string, string>;
  evidenciaPrevia: Evidencia | undefined;
  sinConstancia: string | null;
  exigeDescargo: boolean;
  puedeAnular: boolean;
  acciones: ReactNode;
  editores: ReactNode;
  onVerPapel: (path: string) => void;
}) {
  const { caso } = props;
  const doc = caso?.tipo === "documento" ? props.docs.find((d) => d.id === caso.id) ?? null : null;
  const personaId = caso?.tipo === "documento" ? doc?.persona_id ?? null : caso?.personaId ?? null;
  const persona = personaId ? props.personas.get(personaId) ?? null : null;
  const nombre = persona?.nombre ?? props.tardanza?.nombre ?? props.falta?.nombre ?? "Caso";
  const clave = caso ? `${caso.tipo}:${"id" in caso ? caso.id : caso.personaId}:${props.mesTard}` : "cerrado";

  return (
    <Drawer abierto={caso !== null} onCerrar={props.onCerrar} titulo={nombre}
      volverElFocoA={props.volverElFocoA} bloqueado={props.bloqueado} ancho="amplio">
      {caso && <ContenidoCaso key={clave} {...props} caso={caso} doc={doc} personaId={personaId} persona={persona} />}
    </Drawer>
  );
}

function ContenidoCaso({
  caso, doc, personaId, persona, supabase, docs, adjuntos, personas, tardanza, falta, situacion, mesTard,
  nombresAusencia, evidenciaPrevia, sinConstancia, exigeDescargo, puedeAnular, acciones, editores, onVerPapel,
}: Parameters<typeof PanelCaso>[0] & {
  caso: CasoAbierto; doc: DocDisciplina | null; personaId: string | null; persona: PersonaInfo | null;
}) {
  const [cargada, setCargada] = useState<Evidencia | null>(null);
  const esMesActual = mesTard === primeroDeMesLima();
  const hastaMes = esMesActual ? hoyLima() : ultimoDiaDelMes(mesTard);

  useEffect(() => {
    if (evidenciaPrevia) return;
    let vivo = true;
    const lectura = caso.tipo === "documento" && doc
      ? evidenciaDeDocumento(supabase, doc, docs, nombresAusencia)
      : caso.tipo === "tardanza"
        ? evidenciaDeTardanzasDelMes(supabase, caso.personaId, mesTard, hastaMes, docs, nombresAusencia)
        : null;
    void lectura?.then((e) => { if (vivo) setCargada(e); });
    return () => { vivo = false; };
  }, [caso, doc, docs, supabase, nombresAusencia, mesTard, hastaMes, evidenciaPrevia]);

  const evidencia = evidenciaPrevia ?? cargada;
  const causal = doc?.tipo_causal ?? caso.tipo;
  const cesada = persona?.estado === "inactivo";
  const papeles = doc ? adjuntos.get(doc.id) ?? [] : [];

  // La referencia de los antecedentes: el cierre del periodo que el documento
  // cubre (19.1 c: «doce meses anteriores AL HECHO»), o el cierre de hoy.
  const referencia = rangoDelDiaLima(doc?.periodo_hasta ?? hoyLima()).fin;
  const antecedentes = personaId ? antecedentesVigentes(docs, personaId, causal, referencia, doc?.id) : [];
  const enTramite = personaId
    ? docs.filter((x) => x.persona_id === personaId && x.tipo_causal === causal && x.id !== doc?.id
        && (x.estado === "borrador" || x.estado === "firmado"))
    : [];

  return (
    <div className="grid gap-6 text-sm">
      {/* ── Qué es este caso ─────────────────────────────────────────── */}
      <div className="-mt-2 flex flex-wrap items-center gap-x-3 gap-y-1.5 text-taupe">
        {persona?.sede && <span>Sede <strong className="font-medium text-tinta">{persona.sede}</strong></span>}
        <span>{CAUSAL_LABEL[causal] ?? causal}</span>
        {doc
          ? doc.periodo_desde && <span className="tabular-nums">{fechaCorta(doc.periodo_desde)}{doc.periodo_hasta && doc.periodo_hasta !== doc.periodo_desde ? ` al ${fechaCorta(doc.periodo_hasta)}` : ""}</span>
          : <span>{caso.tipo === "tardanza" ? `${nombreDelMesLima(mesTard)} ${mesTard.slice(0, 4)}` : "Últimos 180 días"}</span>}
        {doc
          ? <Insignia variante={ESTADO_DOCUMENTO[doc.estado]?.variante ?? "neutral"}>{ESTADO_DOCUMENTO[doc.estado]?.texto ?? doc.estado}</Insignia>
          : situacion && <Insignia variante={situacion.variante}>{situacion.etiqueta}</Insignia>}
        {cesada && <Insignia variante="advertencia">Cesó{persona?.fechaCese ? ` el ${fechaCorta(persona.fechaCese)}` : ""}</Insignia>}
      </div>

      {/* ── Alertas: lo que cambia qué se puede hacer ────────────────── */}
      {doc?.estado === "firmado" && cesada && (
        <BannerAviso variante="advertencia" titulo="La persona ya cesó y no consta la entrega" className="p-4">
          <p className="text-tinta">
            El documento se firmó {doc.firmado_at ? `el ${selloLima(doc.firmado_at)}` : ""} y no se registró su entrega.
            Si no se le entregó antes del cese, ciérralo sin entrega: el documento era válido, pero ya no hay a quién
            notificarlo y no cuenta como antecedente. Si sí se le entregó antes, regístralo con esa fecha desde el menú.
          </p>
        </BannerAviso>
      )}
      {doc && evidencia && evidencia.noCuentan > 0 && (
        doc.estado === "borrador" ? (
          <BannerAviso variante="alerta" titulo={`${evidencia.noCuentan} de los ${evidencia.filas.length} días de este borrador ya no se sostienen`} className="p-4">
            <p className="text-tinta">
              La asistencia cambió después de generarlo. Comunicar los cargos o firmar queda bloqueado en esta pantalla:
              {puedeAnular
                ? " anula el borrador y vuelve a generarlo desde «Requieren revisión», si todavía corresponde."
                : " pide a Desarrollo Organizacional que lo anule; si todavía corresponde, se vuelve a generar."}
            </p>
          </BannerAviso>
        ) : doc.estado === "firmado" || doc.estado === "entregado" ? (
          <BannerAviso variante="alerta" titulo={`El documento cita ${evidencia.noCuentan} día${evidencia.noCuentan === 1 ? "" : "s"} que hoy la asistencia ya no sostiene`} className="p-4">
            <p className="text-tinta">
              Probablemente se registró una ausencia o se corrigió algo después de firmar. El documento no se corrige solo:
              decide si corresponde anularlo. Mira la columna «Hoy» abajo.
            </p>
          </BannerAviso>
        ) : null
      )}
      {sinConstancia && (!doc || (doc.estado === "borrador" && doc.nivel !== "imputacion" && doc.nivel !== "despido")) && (
        <BannerAviso variante="alerta" titulo="Sin constancia del Reglamento" className="p-4">
          <p className="text-tinta">
            {doc
              ? "Este documento no se va a poder firmar hasta que se le entregue el Reglamento y quede registrado en Normas — también vale en papel (numeral 60.5)."
              : "Una amonestación o suspensión no se va a poder firmar hasta que se le entregue el Reglamento (numeral 60.5). Resuélvelo antes de empezar: citarla a descargo para nada es hacerle pasar el mal rato."}
          </p>
        </BannerAviso>
      )}
      {caso.tipo === "tardanza" && !esMesActual && (
        <BannerAviso variante="advertencia" titulo="Mes ya cerrado" className="p-4">
          <p className="text-tinta">
            El numeral 19.4 permite documentar un mes concluido, pero una demora injustificada equivale a condonación
            (art. 52). Si no hay motivo para el retraso, no lo emitas. Y emite del mes más viejo al más nuevo (56.6).
          </p>
        </BannerAviso>
      )}

      {/* ── Regla detectada ──────────────────────────────────────────── */}
      <Seccion titulo={doc ? "Documento" : "Regla detectada"}>
        <div className="grid gap-1 rounded-control bg-hueso px-4 py-3">
          {doc ? (
            <>
              <strong className="font-medium">
                {NIVEL_DISCIPLINARIO_LABELS[doc.nivel as keyof typeof NIVEL_DISCIPLINARIO_LABELS] ?? doc.nivel} por {(CAUSAL_LABEL[doc.tipo_causal] ?? doc.tipo_causal).toLowerCase()}
                {doc.correlativo && <span className="font-normal text-taupe"> · {doc.correlativo}</span>}
              </strong>
              <span className="text-taupe">
                {doc.estado === "borrador"
                  ? "Borrador sin número. El sistema lo preparó con las pruebas; quien firma decide si corresponde."
                  : doc.estado === "firmado"
                    ? "Firmado y no entregado: todavía no produce efecto ni cuenta como antecedente (numeral 56.2)."
                    : doc.estado === "entregado"
                      ? "Entregado: cuenta como antecedente doce meses desde su notificación (numeral 56.1)."
                      : "Ya no produce efecto."}
              </span>
            </>
          ) : caso.tipo === "tardanza" && tardanza ? (
            <>
              <strong className="font-medium tabular-nums">
                {tardanza.tardanzas_mes} tardanza{tardanza.tardanzas_mes === 1 ? "" : "s"} medible{tardanza.tardanzas_mes === 1 ? "" : "s"} en {nombreDelMesLima(mesTard)}
                {tardanza.minimo !== null && <span className="font-normal text-taupe"> · su escalón exige {tardanza.minimo}</span>}
              </strong>
              <span className="text-taupe">
                {tardanza.minimo !== null
                  ? `Umbral ${ESCALON_POR_MINIMO[tardanza.minimo] ?? ""} en un mismo mes calendario. El sistema propone el escalón; la decisión es de quien firma.`
                  : "Tiene una imputación de cargos vigente: el siguiente paso lo decide Gerencia tras evaluar sus descargos."}
              </span>
              <span className="text-xs text-taupe">RIT 19.2 · el mes calendario manda; Incidencias cuenta 30 días corridos y puede dar más</span>
            </>
          ) : caso.tipo === "falta" && falta ? (
            <>
              <strong className="font-medium">Inasistencias sin justificar en los últimos 180 días</strong>
              <div className="mt-2 grid gap-2 sm:grid-cols-3">
                <Medidor etiqueta="Seguidas" valor={falta.consecutivas} umbral={UMBRAL_FALTAS.consecutivas} />
                <Medidor etiqueta="En 30 días" valor={falta.en_30} umbral={UMBRAL_FALTAS.en_30} />
                <Medidor etiqueta="En 180 días" valor={falta.en_180} umbral={UMBRAL_FALTAS.en_180} />
              </div>
              <span className="mt-1 text-xs text-taupe">
                Umbral grave art. 25 h) de la LPCL. «En 30 días» es el mayor número de faltas dentro de cualquier ventana de 30 días.
                Este semáforo todavía no descuenta faltas ya sancionadas: mira los antecedentes antes de actuar.
              </span>
            </>
          ) : (
            <span className="text-taupe">Esta persona ya no aparece en el semáforo. Vuelve a cargar la página.</span>
          )}
        </div>
      </Seccion>

      {/* ── Evidencia ────────────────────────────────────────────────── */}
      <Seccion titulo="Evidencia, día por día">
        {caso.tipo === "falta" ? (
          <p className="text-taupe">
            Las fechas exactas se fijan al preparar el borrador y se revisan ahí, con lo que dice hoy la asistencia de
            cada una, antes de comunicar los cargos. Para mirarlas ahora, abre{" "}
            <Link href="/admin/incidencias" className="text-tinta underline underline-offset-2">Incidencias</Link>.
          </p>
        ) : !evidencia ? (
          <p className="text-taupe">Leyendo la asistencia…</p>
        ) : evidencia.filas.length === 0 ? (
          <p className="text-taupe">
            {evidencia.fallo ?? (doc ? "Este documento no cita días concretos." : `Sin tardanzas registradas en ${nombreDelMesLima(mesTard)}.`)}
          </p>
        ) : (
          <>
            {evidencia.fallo && (
              <p className="mb-2 text-rojo-profundo">
                No se pudo leer la asistencia de hoy ({evidencia.fallo}). La columna «Hoy» no está verificada.
              </p>
            )}
            <div className="overflow-x-auto rounded-control border border-sand">
              <table className="w-full min-w-[480px] text-xs">
                <thead className="bg-sand/70 text-left text-taupe">
                  <tr>
                    <th className="px-3 py-2 font-normal">Fecha</th>
                    <th className="px-3 py-2 font-normal">Esperada</th>
                    <th className="px-3 py-2 font-normal">Marcó</th>
                    {causal === "tardanza" && <th className="px-3 py-2 font-normal">Minutos</th>}
                    <th className="px-3 py-2 font-normal">Hoy</th>
                  </tr>
                </thead>
                <tbody className="tabular-nums">
                  {evidencia.filas.map((f) => (
                    <tr key={f.fecha} className="border-t border-sand">
                      <td className={cx("px-3 py-2", !f.hoy.cuenta && "text-taupe line-through")}>{fechaCorta(f.fecha)}</td>
                      <td className={cx("px-3 py-2", !f.hoy.cuenta && "text-taupe")}>{f.esperada}</td>
                      <td className={cx("px-3 py-2", !f.hoy.cuenta && "text-taupe")}>{f.marco}</td>
                      {causal === "tardanza" && (
                        <td className={cx("px-3 py-2", !f.hoy.cuenta && "text-taupe")}>
                          {(f.minutosCitados ?? f.minutosHoy) ?? "—"}′
                        </td>
                      )}
                      <td className="px-3 py-2">
                        <Insignia
                          variante={f.hoy.cuenta ? "neutral" : doc && doc.estado !== "anulado" && doc.estado !== "cerrado_sin_entrega" ? "alerta" : "neutral"}
                          atenuada={!f.hoy.cuenta && !doc}>
                          {f.hoy.etiqueta}
                        </Insignia>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <p className="mt-2 text-xs text-taupe">
              {doc
                ? `El documento cita ${evidencia.filas.length} día${evidencia.filas.length === 1 ? "" : "s"}; hoy se sostienen ${evidencia.filas.length - evidencia.noCuentan}. «Esperada» es el horario con que se midió ese día.`
                : `Cuentan ${evidencia.filas.length - evidencia.noCuentan}; el semáforo dice ${tardanza?.tardanzas_mes ?? "—"}. Si no coinciden, manda el semáforo: es el que usa el generador.`}
            </p>
          </>
        )}
      </Seccion>

      {/* ── Antecedentes ─────────────────────────────────────────────── */}
      <Seccion titulo="Antecedentes">
        {antecedentes.length === 0 && enTramite.length === 0 ? (
          <p className="text-taupe">Sin documentos entregados de esta causal en los doce meses previos.</p>
        ) : (
          <ul className="grid gap-1.5">
            {antecedentes.map((a) => (
              <li key={a.id} className="flex flex-wrap items-baseline gap-x-2">
                <Insignia variante={a.nivel === "verbal" ? "neutral" : "advertencia"} tamano="sm">
                  {NIVEL_DISCIPLINARIO_LABELS[a.nivel as keyof typeof NIVEL_DISCIPLINARIO_LABELS] ?? a.nivel}
                </Insignia>
                <span className="tabular-nums">
                  {a.correlativo ?? "sin número"} · entregado el {fechaCorta(fechaLima(a.entregado_at!))} · vigente hasta el{" "}
                  {fechaCorta(addDias(fechaLima(a.entregado_at!), 365))}
                  {a.nivel === "verbal" && <span className="text-taupe"> · no agrava</span>}
                </span>
              </li>
            ))}
            {enTramite.map((a) => (
              <li key={a.id} className="flex flex-wrap items-baseline gap-x-2 text-taupe">
                <Insignia variante="informativo" tamano="sm">{ESTADO_DOCUMENTO[a.estado]?.texto ?? a.estado}</Insignia>
                <span>
                  {NIVEL_DISCIPLINARIO_LABELS[a.nivel as keyof typeof NIVEL_DISCIPLINARIO_LABELS] ?? a.nivel}
                  {a.correlativo ? ` ${a.correlativo}` : ""} · todavía no cuenta como antecedente
                </span>
              </li>
            ))}
          </ul>
        )}
        <p className="mt-2 text-xs text-taupe">
          Referencia para leer el caso. El escalón lo calcula la base, que además descuenta lo ya sancionado.
        </p>
      </Seccion>

      {/* ── Información relevante ────────────────────────────────────── */}
      {doc && <InformacionDelDocumento doc={doc} papeles={papeles} exigeDescargo={exigeDescargo} editores={editores} onVerPapel={onVerPapel} />}
      {!doc && tardanza && tardanza.sin_medir > 0 && (
        <Seccion titulo="Información relevante">
          <p className="text-taupe">
            Tiene {tardanza.sin_medir} día{tardanza.sin_medir === 1 ? "" : "s"} de más de tres horas tarde que no suman
            al umbral: casi siempre significa que ese día tenía otro turno y se comparó contra el equivocado. Revísalo en Turnos.
          </p>
        </Seccion>
      )}

      {/* ── Historial ────────────────────────────────────────────────── */}
      {doc && <HistorialDelDocumento doc={doc} papeles={papeles} personas={personas} />}

      {/* ── Acciones ─────────────────────────────────────────────────── */}
      <div className="sticky bottom-0 -mx-6 -mb-6 border-t border-sand bg-papel px-6 py-4">{acciones}</div>
    </div>
  );
}

function Seccion({ titulo, children }: { titulo: string; children: ReactNode }) {
  return (
    <section>
      <h3 className="mb-2 text-xs font-medium uppercase tracking-[0.08em] text-taupe">{titulo}</h3>
      {children}
    </section>
  );
}

function Medidor({ etiqueta, valor, umbral }: { etiqueta: string; valor: number; umbral: number }) {
  const pct = Math.min(100, Math.round((valor / umbral) * 100));
  return (
    <div className="grid gap-1">
      <span className="flex items-baseline justify-between text-xs text-taupe">
        {etiqueta}
        <span className="tabular-nums text-tinta">{valor} / {umbral}</span>
      </span>
      <span className="h-1.5 overflow-hidden rounded-full bg-sand" aria-hidden>
        <span className={cx("block h-full", valor >= umbral ? "bg-rojo" : "bg-tinta")} style={{ width: `${pct}%` }} />
      </span>
    </div>
  );
}

function InformacionDelDocumento({
  doc, papeles, exigeDescargo, editores, onVerPapel,
}: {
  doc: DocDisciplina; papeles: Adjunto[]; exigeDescargo: boolean; editores: ReactNode; onVerPapel: (path: string) => void;
}) {
  const notas = eventosDeObservacion(doc.observacion).filter((e) => e.tipo === "nota");
  const etapa = doc.estado === "borrador" ? etapaDelBorrador(doc, exigeDescargo) : null;
  const papelesIlegibles = doc.estado === "anulado" || doc.estado === "cerrado_sin_entrega";
  // Un título sin nada debajo se lee como «falta algo», no como «no hay nada».
  const hayAlgo = (etapa !== null && exigeDescargo && esGradual(doc.nivel)) || editores !== null
    || notas.length > 0 || doc.estado === "entregado" || papeles.length > 0;
  if (!hayAlgo) return null;
  return (
    <Seccion titulo="Información relevante">
      <div className="grid gap-2">
        {etapa && exigeDescargo && esGradual(doc.nivel) && (
          <p className={etapa === "firmar" ? "text-taupe" : "text-tinta"}>
            {etapa === "comunicar"
              ? "Falta comunicarle los cargos por escrito —los hechos con sus fechas, la norma que se le imputa y el detalle de la medición— y darle dos días hábiles para su descargo (art. 55.2 del RIT). Hasta entonces no se puede firmar."
              : etapa === "esperando"
                ? `Cargos comunicados el ${selloLima(doc.cargos_comunicados_at!)} · su plazo de descargo vence el ${doc.descargo_vence_at ? selloLima(doc.descargo_vence_at) : "—"} — firmar antes invalidaría la sanción.`
                : etapa === "valorar"
                  ? `El plazo venció el ${doc.descargo_vence_at ? selloLima(doc.descargo_vence_at) : "—"} · falta dejar por escrito si su descargo se acoge, y hacerlo constar también si no presentó ninguno (art. 19.3 del RIT).`
                  : `Cargos comunicados el ${doc.cargos_comunicados_at ? selloLima(doc.cargos_comunicados_at) : "—"} · ${ETIQUETA_DESCARGO[doc.descargo_acogido ?? ""] ?? doc.descargo_acogido}${doc.descargo_valoracion ? `: ${doc.descargo_valoracion}` : ""}`}
          </p>
        )}
        {etapa && exigeDescargo && esGradual(doc.nivel) && doc.cargos_comunicados_at && (
          // Medido el 2026-09-15: la regla del bucket `expedientes` solo deja
          // subir archivos a documentos firmados o entregados, así que el botón
          // «subir su descargo» que había acá fallaba siempre. Se quitó en vez
          // de ofrecer un error garantizado; el arreglo es de la base (lote 3).
          <p className="text-xs text-taupe">
            El descargo escrito de un borrador todavía no se puede archivar desde el sistema. Guárdalo en papel y
            menciónalo en la valoración.
          </p>
        )}
        {editores}
        {notas.map((n, i) => (
          <p key={i} className="whitespace-pre-line text-taupe">{n.texto}</p>
        ))}
        {doc.estado === "entregado" && (
          <p className="text-taupe">
            Entregado {doc.entregado_at ? `el ${selloLima(doc.entregado_at)}` : ""}
            {doc.medio_entrega && ` ${MEDIO_ENTREGA[doc.medio_entrega] ?? doc.medio_entrega}`}
            {doc.entrega_testigo_nombre && ` · testigo: ${doc.entrega_testigo_nombre}`}
          </p>
        )}
        {doc.nivel === "imputacion" && doc.estado === "entregado" && (
          doc.resuelto_at ? (
            <p className="text-taupe">
              <strong className="font-medium text-tinta">{doc.resuelto_resultado === "despido" ? "Resuelto con despido" : "Archivado sin sancionar"}</strong>
              {" "}el {selloLima(doc.resuelto_at)} — {doc.resuelto_motivo}
            </p>
          ) : (
            <p className="text-rojo-profundo">
              Procedimiento abierto. Tras evaluar sus descargos, registra la decisión: si no, el semáforo seguirá
              pidiéndola durante doce meses.
            </p>
          )
        )}
        {papeles.length > 0 && (
          papelesIlegibles ? (
            <p className="text-xs text-taupe">
              Tiene {papeles.length} papel{papeles.length === 1 ? "" : "es"} archivado{papeles.length === 1 ? "" : "s"}, pero hoy no se
              pueden abrir: la regla de archivos solo abre los de documentos firmados o entregados.
            </p>
          ) : (
            <div className="flex flex-wrap gap-3">
              {papeles.map((a) => (
                <button key={a.id} type="button" onClick={() => onVerPapel(a.storage_path)}
                  className="text-sm font-medium text-tinta underline underline-offset-2 hover:text-taupe">
                  {ETIQUETA_PAPEL[a.tipo] ?? "Ver papel"}
                </button>
              ))}
            </div>
          )
        )}
      </div>
    </Seccion>
  );
}

interface Evento { cuando: string; titulo: string; quien: string | null }

function HistorialDelDocumento({ doc, papeles, personas }: { doc: DocDisciplina; papeles: Adjunto[]; personas: Map<string, PersonaInfo> }) {
  const nombre = (id: string | null) => (id ? personas.get(id)?.nombre ?? null : null);
  const eventos: Evento[] = [{ cuando: doc.creado_at, titulo: "Se generó el borrador", quien: nombre(doc.creado_por) }];
  if (doc.cargos_comunicados_at) eventos.push({ cuando: doc.cargos_comunicados_at, titulo: "Se comunicaron los cargos", quien: null });
  if (doc.firmado_at) eventos.push({ cuando: doc.firmado_at, titulo: `Firmado${doc.correlativo ? ` · ${doc.correlativo}` : ""}`, quien: nombre(doc.firmante_id) });
  if (doc.entregado_at) eventos.push({
    cuando: doc.entregado_at,
    titulo: `Entregado${doc.medio_entrega ? ` ${MEDIO_ENTREGA[doc.medio_entrega] ?? doc.medio_entrega}` : ""}`,
    quien: nombre(doc.entregado_por),
  });
  if (doc.resuelto_at) eventos.push({
    cuando: doc.resuelto_at,
    titulo: doc.resuelto_resultado === "despido" ? "Se resolvió con despido" : "Se archivó sin sancionar",
    quien: nombre(doc.resuelto_por),
  });
  for (const a of papeles) eventos.push({ cuando: a.subido_at, titulo: `Se archivó ${ETIQUETA_PAPEL[a.tipo]?.replace("Ver ", "el ") ?? "un papel"}`, quien: null });
  for (const e of eventosDeObservacion(doc.observacion)) {
    if (e.tipo === "nota" || !e.fecha) continue;
    const titulo = e.tipo === "anulado" ? `Anulado: ${e.texto}` : e.tipo === "reabierto" ? `Vuelto a borrador: ${e.texto}` : `Cerrado sin entrega: ${e.texto}`;
    eventos.push({ cuando: rangoDelDiaLima(e.fecha).inicio, titulo, quien: null });
  }
  eventos.sort((a, b) => Date.parse(b.cuando) - Date.parse(a.cuando));

  return (
    <Seccion titulo="Historial del caso">
      <ol className="grid gap-3 border-l border-sand pl-4">
        {eventos.map((e, i) => (
          <li key={i} className="relative">
            <span className="absolute -left-[21px] top-1.5 size-2 rounded-full bg-taupe" aria-hidden />
            <span className="block text-tinta">{e.titulo}</span>
            <span className="block text-xs text-taupe">
              {selloLima(e.cuando)}{e.quien ? ` · ${e.quien}` : ""}
            </span>
          </li>
        ))}
      </ol>
      <p className="mt-2 text-xs text-taupe">
        Quién anuló, volvió a borrador o cerró sin entrega todavía no se guarda: solo la fecha y el motivo.
      </p>
    </Seccion>
  );
}

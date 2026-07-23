"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { AdminNav } from "../../../nav";

const EMPRESA = { nombre: "CAYLA S.A.C.", ruc: "20605964550", firmante: "Alvarez Pereyra Felipe Miguel", cargo: "Gerencia General" };
const TZ = "America/Lima";

function fechaCorta(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "long", year: "numeric", timeZone: "UTC" })
    .format(new Date(Date.UTC(y, m - 1, d)));
}
function mesDe(iso: string | null): string {
  if (!iso) return "";
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { month: "long", year: "numeric", timeZone: "UTC" }).format(new Date(Date.UTC(y, m - 1, d)));
}

const TITULO: Record<string, string> = {
  verbal: "Acta de llamada verbal de atención",
  amonestacion: "Amonestación escrita",
  suspension: "Suspensión sin goce de haber",
  imputacion: "Imputación de cargos — carta de preaviso",
  despido: "Carta de despido por causa justa",
};
const CAUSAL: Record<string, string> = { tardanza: "tardanzas reiteradas", falta: "inasistencias injustificadas", conducta: "conducta" };

interface Hecho { fecha: string; minutos?: number }
interface Doc {
  id: string; correlativo: string | null; persona_id: string; tipo_causal: string; nivel: string; estado: string;
  periodo_desde: string | null; periodo_hasta: string | null; hechos: Hecho[];
  suspension_dias: number | null; suspension_desde: string | null; suspension_hasta: string | null;
  firmante_id: string | null; firmado_at: string | null; creado_at: string;
}
interface Persona { nombres: string; apellidos: string; documento: string | null; funcion: string; sede_base_id: string }

export default function MemoPage() {
  const params = useParams();
  const id = (params?.id as string) ?? "";
  const router = useRouter();
  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  const [doc, setDoc] = useState<Doc | null>(null);
  const [persona, setPersona] = useState<Persona | null>(null);
  const [sede, setSede] = useState<string>("");
  const [firmante, setFirmante] = useState<string>(EMPRESA.firmante);
  const [firmaUrl, setFirmaUrl] = useState<string | null>(null);
  const [cargando, setCargando] = useState(true);
  const [err, setErr] = useState<string | null>(null);

  const cargar = useCallback(async () => {
    setCargando(true); setErr(null);
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    const { data: d, error: eD } = await supabase.from("expediente_disciplinario")
      .select("id, correlativo, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos, suspension_dias, suspension_desde, suspension_hasta, firmante_id, firmado_at, creado_at")
      .eq("id", id).maybeSingle();
    if (eD || !d) { setErr("No se encontró el documento (o no tienes permiso para verlo)."); setCargando(false); return; }
    const doc = d as unknown as Doc;
    setDoc(doc);
    const ids = [doc.persona_id, doc.firmante_id].filter((x): x is string => Boolean(x));
    const [{ data: ps }, { data: sedes }] = await Promise.all([
      supabase.from("personas").select("id, nombres, apellidos, documento, funcion, sede_base_id").in("id", ids),
      supabase.from("sedes").select("id, codigo"),
    ]);
    const pl = (ps as Array<Persona & { id: string }>) ?? [];
    const p = pl.find((x) => x.id === doc.persona_id) ?? null;
    setPersona(p);
    const f = pl.find((x) => x.id === doc.firmante_id);
    if (f) setFirmante(`${f.nombres} ${f.apellidos}`);
    // Firma escaneada del firmante (solo se muestra en niveles leves; ver render).
    if (doc.firmante_id) {
      const { data: fu } = await supabase.rpc("fn_firma_persona", { p_persona_id: doc.firmante_id });
      setFirmaUrl(typeof fu === "string" && fu.startsWith("data:image") ? fu : null);
    }
    const smap = new Map(((sedes as Array<{ id: string; codigo: string }>) ?? []).map((s) => [s.id, s.codigo]));
    if (p) setSede(smap.get(p.sede_base_id) ?? "");
    setCargando(false);
  }, [supabase, router, id]);

  useEffect(() => { void cargar(); }, [cargar]);

  const nombre = persona ? `${persona.nombres} ${persona.apellidos}` : "—";
  const n = doc?.hechos?.length ?? 0;
  const esNivel4 = doc?.nivel === "imputacion" || doc?.nivel === "despido";

  function Cuerpo() {
    if (!doc) return null;
    const t = doc.tipo_causal;
    const nivel = doc.nivel;
    if (nivel === "amonestacion" && t === "tardanza") {
      return (
        <>
          <p>El presente memorándum deja constancia de que, durante el mes de <strong>{mesDe(doc.periodo_desde)}</strong>, usted registró <strong>{n} tardanzas</strong>, superando el umbral b) del artículo 7 del Reglamento Interno de Trabajo de {EMPRESA.nombre} (tres o más tardanzas en un mismo mes calendario), según el detalle de las marcaciones que a continuación se indica.</p>
          <p>Las tardanzas detalladas no han sido objeto de sanción disciplinaria previa. El descuento proporcional por el tiempo no laborado, de haberse aplicado en planilla, tiene naturaleza contraprestativa y es independiente de esta sanción; no la sustituye.</p>
          <p>Por lo expuesto, se le impone <strong>AMONESTACIÓN ESCRITA</strong>, que se incorpora a su legajo como antecedente disciplinario con vigencia de doce (12) meses desde su notificación (artículo 14.4 del RIT). Se le exhorta a corregir su puntualidad. La reincidencia dará lugar a <strong>suspensión sin goce de haber</strong> conforme al umbral c) del artículo 7 del RIT.</p>
        </>
      );
    }
    if (nivel === "amonestacion" && t === "falta") {
      return (
        <>
          <p>El presente memorándum deja constancia de que, correspondiéndole laborar en la(s) fecha(s) que se detalla(n), usted <strong>no concurrió al centro de trabajo ni registró marca alguna</strong> en el sistema de control de asistencia, sin que exista justificación aceptada dentro del plazo previsto en el artículo 8.2 del RIT.</p>
          <p>La inasistencia injustificada constituye falta conforme al artículo 8.3-a del RIT y contraviene el deber de asistencia y puntualidad (artículo 13-c). El descuento del día no laborado y de la parte proporcional del descanso semanal es independiente de esta sanción.</p>
          <p>Por lo expuesto, se le impone <strong>AMONESTACIÓN ESCRITA</strong>, incorporada a su legajo por doce (12) meses (artículo 14.4 del RIT). Una nueva inasistencia injustificada dará lugar a <strong>suspensión sin goce de haber</strong> (artículo 8.3-b), y la acumulación de ausencias puede configurar causal de despido conforme al artículo 25-h de la LPCL.</p>
        </>
      );
    }
    if (nivel === "suspension") {
      const art = t === "tardanza" ? "umbral c) del artículo 7" : "artículo 8.3-b";
      return (
        <>
          <p>Habiendo sido usted <strong>amonestado por escrito con anterioridad</strong> por {CAUSAL[t]}, y habiendo reincidido según el detalle que se indica, se configura el {art} del RIT. Estos hechos son nuevos y posteriores a la sanción previa; no se recuenta ninguno ya sancionado.</p>
          <p>Por lo expuesto, se le impone <strong>SUSPENSIÓN SIN GOCE DE HABER</strong> por <strong>{doc.suspension_dias} día(s)</strong>{doc.suspension_desde && <>, del <strong>{fechaCorta(doc.suspension_desde)}</strong>{doc.suspension_hasta && <> al <strong>{fechaCorta(doc.suspension_hasta)}</strong></>}</>}. Durante ese periodo no deberá concurrir al centro de trabajo ni percibirá remuneración (artículo 14.2 del RIT).</p>
          <p>Se le advierte que, de persistir, {EMPRESA.nombre} iniciará el procedimiento de despido por causa justa previsto en el artículo 31 de la LPCL.</p>
        </>
      );
    }
    if (nivel === "imputacion") {
      const inc = t === "tardanza" ? "inciso a)" : "inciso h)";
      return (
        <>
          <p>En cumplimiento del <strong>artículo 31 de la LPCL</strong>, {EMPRESA.nombre} le <strong>imputa los cargos</strong> que se detallan y le otorga un plazo no menor de <strong>seis (6) días naturales</strong>, contados desde la recepción del presente, para que presente por escrito sus descargos ante la Gerencia General.</p>
          <p>Los hechos, referidos a {CAUSAL[t]} y precedidos de las sanciones disciplinarias que constan en su legajo, configurarían <strong>falta grave</strong> conforme al artículo <strong>25, {inc}</strong>, de la LPCL, en concordancia con el RIT. La presente imputación no afirma su responsabilidad: garantiza su derecho de defensa.</p>
          <p>La causa aquí imputada vincula una eventual carta de despido y no podrá variarse.</p>
        </>
      );
    }
    if (nivel === "despido") {
      const inc = t === "tardanza" ? "inciso a)" : "inciso h)";
      return (
        <>
          <p>Evaluados el historial disciplinario y los descargos presentados —o vencido el plazo sin presentarlos—, {EMPRESA.nombre} concluye que usted ha incurrido en <strong>falta grave</strong> conforme al artículo <strong>25, {inc}</strong>, de la LPCL.</p>
          <p>En consecuencia, y conforme al <strong>artículo 32 de la LPCL</strong>, se comunica la <strong>extinción del contrato de trabajo por causa justa</strong>. Se procederá a la liquidación de sus beneficios sociales y a la entrega del certificado de trabajo.</p>
        </>
      );
    }
    return <p>Documento de {CAUSAL[t]}.</p>;
  }

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <style>{`@media print { header, .no-print { display: none !important; } .memo { border: 0 !important; margin: 0 !important; padding: 0 !important; max-width: 100% !important; color: #1a1a1a !important; } .memo table, .memo thead, .memo tr, .memo .firma { break-inside: avoid; } } .memo p { margin: 0 0 10px; text-align: justify; } .memo h2 { font-size: 15px; margin: 0 0 4px; } @page { margin: 18mm; }`}</style>
      <main className="flex-1 p-6">
        <div className="no-print mb-4 flex max-w-[760px] items-center justify-between">
          <button onClick={() => router.push("/admin/disciplina")} className="text-sm text-taupe hover:text-tinta">← Volver a Disciplina</button>
          {doc && !err && (
            <button onClick={() => window.print()} className="rounded-lg bg-tinta px-5 py-2 text-sm font-medium text-crema">
              Imprimir / Guardar PDF
            </button>
          )}
        </div>

        {cargando ? (
          <p className="text-sm text-taupe">Cargando…</p>
        ) : err ? (
          <p className="max-w-[760px] rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">{err}</p>
        ) : doc && (
          <div className="memo mx-auto max-w-[760px] rounded-lg border bg-white p-10 font-serif text-[13px] leading-relaxed text-tinta">
            {esNivel4 && (
              <p className="no-print mb-4 rounded bg-amber-100 px-3 py-2 text-xs text-amber-800">
                Documento de Nivel 4. Antes de emitirlo, valídalo con un abogado laboralista y entrégalo en físico o por vía notarial (nunca por correo).
              </p>
            )}
            {doc.estado === "borrador" && (
              <p className="no-print mb-4 rounded bg-sand/50 px-3 py-2 text-xs text-taupe">
                Este es un <strong>borrador sin numerar</strong>. Fírmalo en la pantalla de Disciplina para asignarle su número de documento.
              </p>
            )}

            <div className="mb-4 flex items-start justify-between border-b pb-3">
              <div>
                <p className="font-medium">{EMPRESA.nombre}</p>
                <p className="text-taupe">RUC N.° {EMPRESA.ruc}</p>
              </div>
              <div className="text-right">
                <p className="font-medium">{doc.correlativo ?? "BORRADOR — sin numerar"}</p>
                <p className="text-taupe">{fechaCorta((doc.firmado_at ?? doc.creado_at).slice(0, 10))}</p>
              </div>
            </div>

            <table className="mb-4 w-full">
              <tbody>
                <tr><td className="w-16 py-0.5 align-top text-taupe">Para:</td><td className="py-0.5"><strong>{nombre}</strong> · DNI {persona?.documento ?? "—"}</td></tr>
                <tr><td className="py-0.5 align-top text-taupe">Cargo:</td><td className="py-0.5">{persona?.funcion ?? "—"} · Sede {sede || "—"}</td></tr>
                <tr><td className="py-0.5 align-top text-taupe">De:</td><td className="py-0.5">{firmante} · {EMPRESA.cargo}</td></tr>
              </tbody>
            </table>

            <h2 className="font-serif">Asunto: {TITULO[doc.nivel]} por {CAUSAL[doc.tipo_causal]}</h2>
            <div className="mt-3"><Cuerpo /></div>

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

            <div className="firma mt-10 grid grid-cols-2 gap-8 text-[12px]">
              <div>
                {firmaUrl && !esNivel4 ? (
                  <img src={firmaUrl} alt="" aria-hidden className="mx-auto mb-[-10px] block h-28 object-contain" />
                ) : (
                  <div className="h-14" aria-hidden />
                )}
                <div className="mb-1 border-t pt-1">{firmante}</div>
                <p className="text-taupe">{EMPRESA.cargo} — {EMPRESA.nombre}</p>
              </div>
              <div>
                <div className="mb-1 border-t pt-1">Recibí conforme</div>
                <p className="text-taupe">{nombre} · DNI {persona?.documento ?? "____"}</p>
                <p className="mt-2 text-taupe">Fecha: __________  Hora: ______</p>
              </div>
            </div>
            <p className="mt-6 text-[11px] text-taupe">
              Constancia de negativa a recibir (si aplica): el colaborador se negó a recibir el presente documento.
              Testigo 1: __________________  ·  Testigo 2: __________________
            </p>
          </div>
        )}
      </main>
    </div>
  );
}

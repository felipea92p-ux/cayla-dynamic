"use client";

// La comunicación de cargos de un borrador, lista para imprimir y entregar
// (RIT 55.2). Es el papel que faltaba: hasta el 2026-11-02 el único documento
// imprimible de un borrador era el memo de la sanción, y fue ESE el que se le
// entregó a una colaboradora para que lo firmara durante su plazo de descargo.
// El porqué completo está en `components/disciplina/comunicacion-cargos.tsx`.
//
// Lee lo mismo que la pantalla del memo, menos el firmante (la comunicación no
// la suscribe nadie desde el sistema: se firma a mano) y más la asistencia de
// cada día citado, porque el 19.3 pide entregar la hora programada y la
// registrada, no solo la fecha.

import { useCallback, useEffect, useMemo, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Cargando } from "@/components/cargando";
import { ComunicacionCargos, type DiaMedido, type DocCargos } from "@/components/disciplina/comunicacion-cargos";
import type { PersonaMemo, Previa } from "@/components/disciplina/memo-documento";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Boton } from "@/components/ui/boton";
import { esGradual, type DocDisciplina } from "@/lib/admin/disciplina";
import { evidenciaDeDocumento } from "@/lib/admin/disciplina-evidencia";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { AREAS_FALLBACK, parseAreas, type Area } from "@/lib/areas";

type Doc = DocCargos & {
  persona_id: string; estado: string; creado_at: string;
  falta_rit_version: number | null; falta_numeral: string | null; falta_literal: string | null;
};
type Persona = PersonaMemo & { sede_base_id: string };

export default function ComunicacionCargosPage() {
  const params = useParams();
  const id = (params?.id as string) ?? "";
  const router = useRouter();
  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  const [doc, setDoc] = useState<Doc | null>(null);
  const [persona, setPersona] = useState<Persona | null>(null);
  const [sede, setSede] = useState("");
  const [areas, setAreas] = useState<Area[]>(AREAS_FALLBACK);
  const [previas, setPrevias] = useState<Previa[]>([]);
  const [medicion, setMedicion] = useState<DiaMedido[]>([]);
  const [falloMedicion, setFalloMedicion] = useState<string | null>(null);
  const [cargando, setCargando] = useState(true);
  const [err, setErr] = useState<string | null>(null);

  const cargar = useCallback(async () => {
    setCargando(true); setErr(null);
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    const { data: d, error: eD } = await supabase.from("expediente_disciplinario")
      .select("id, persona_id, tipo_causal, nivel, estado, periodo_desde, hechos, suspension_dias, cargos_comunicados_at, descargo_vence_at, falta_rit_version, falta_numeral, falta_literal, conocido_el, creado_at")
      .eq("id", id).maybeSingle();
    if (eD || !d) { setErr("No se encontró el documento (o no tienes permiso para verlo)."); setCargando(false); return; }
    const doc = d as unknown as Doc;
    // Conducta (0510): el texto de la falta, en la versión del RIT que el
    // documento cita — no en la vigente hoy. Igual que el memo.
    if (doc.tipo_causal === "conducta" && doc.falta_numeral && doc.falta_literal) {
      const { data: f } = await supabase.from("faltas_catalogo").select("numeral, literal, texto, gravedad")
        .eq("rit_version", doc.falta_rit_version ?? 0).eq("numeral", doc.falta_numeral).eq("literal", doc.falta_literal).maybeSingle();
      doc.falta = (f as DocCargos["falta"]) ?? null;
    }
    setDoc(doc);

    const [{ data: p }, { data: sedes }, { data: ar, error: eAr }, { data: prev }, ev] = await Promise.all([
      supabase.from("personas").select("nombres, apellidos, documento, funcion, sede_base_id").eq("id", doc.persona_id).maybeSingle(),
      supabase.from("sedes").select("id, codigo"),
      supabase.rpc("fn_areas"),
      // El antecedente que se invoca: solo lo ENTREGADO de la misma causal en
      // doce meses (56.1, 56.2). La misma consulta que la del memo.
      supabase.from("expediente_disciplinario")
        .select("correlativo, nivel, firmado_at, entregado_at")
        .eq("persona_id", doc.persona_id).eq("tipo_causal", doc.tipo_causal).eq("estado", "entregado").neq("id", doc.id)
        .gte("entregado_at", new Date(Date.now() - 365 * 24 * 3600 * 1000).toISOString())
        .order("entregado_at", { ascending: true }),
      // La hora programada y la registrada de cada día. La conducta no tiene
      // marcaciones y la función devuelve vacío para ella.
      evidenciaDeDocumento(supabase, doc as unknown as DocDisciplina, [], new Map()),
    ]);
    setAreas(parseAreas(ar, eAr));
    setPrevias((prev as Previa[]) ?? []);
    setMedicion(ev.filas.map((f) => ({ fecha: f.fecha, esperada: f.esperada, marco: f.marco, minutos: f.minutosCitados })));
    setFalloMedicion(ev.fallo);
    const per = (p as Persona | null) ?? null;
    setPersona(per);
    const smap = new Map(((sedes as Array<{ id: string; codigo: string }>) ?? []).map((s) => [s.id, s.codigo]));
    if (per) setSede(smap.get(per.sede_base_id) ?? "");
    setCargando(false);
  }, [supabase, router, id]);

  // Cargar al abrir es justamente lo que esta pantalla hace, como la del memo de «Lo mío».
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargar(); }, [cargar]);

  // Mismo criterio que el memo: un papel legal sobre una persona concreta no se
  // guarda como «Dynamic — CAYLA».
  useTituloDocumento(doc && persona ? `Comunicación de cargos — ${persona.nombres} ${persona.apellidos}` : null);

  const nombre = persona ? `${persona.nombres} ${persona.apellidos}` : "la colaboradora";
  const aplica = doc ? esGradual(doc.nivel) : false;

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6 print:p-0">
        <div className="mb-4 flex max-w-[760px] items-center justify-between print:hidden">
          <button onClick={() => router.push("/admin/disciplina")} className="text-sm text-taupe hover:text-tinta">← Volver a Disciplina</button>
          {doc && !err && aplica && (
            <Boton variante="primario" tamano="lg" onClick={() => window.print()}>
              Imprimir / Guardar PDF
            </Boton>
          )}
        </div>

        {cargando ? (
          <Cargando />
        ) : err ? (
          <BannerAviso variante="alerta" className="max-w-[760px]">{err}</BannerAviso>
        ) : doc && !aplica ? (
          <BannerAviso variante="informativo" className="max-w-[760px]">
            La comunicación de cargos previa es para la amonestación y la suspensión (numeral 55.2 del RIT). La
            imputación de cargos ya es, ella misma, la carta que se entrega; la llamada verbal no la necesita.
          </BannerAviso>
        ) : doc && (
          <>
            <div className="mx-auto mb-4 grid max-w-[760px] gap-3 print:hidden">
              <BannerAviso variante="informativo" titulo="Este es el papel que se le entrega ahora">
                <p>
                  Entrégaselo a {nombre} con su firma de recibido. <strong>El memo de la sanción no se le entrega ni
                  se le hace firmar</strong>: sigue en borrador hasta que venza su plazo de descargo, se valore lo que
                  diga y se firme. Recién entonces aparece en «Por entregar», se lo envías a su Info y ahí ella lo ve y
                  lo firma.
                </p>
              </BannerAviso>
              {doc.cargos_comunicados_at === null && doc.estado === "borrador" && (
                <BannerAviso variante="advertencia" enLinea>
                  Todavía no consta en Dynamic que se le comunicaron los cargos. Entrégale este papel y ese mismo día
                  pulsa «Comunicar cargos» en Disciplina; si se lo entregaste otro día, usa «Ya se lo comuniqué» con la
                  fecha real. Su plazo corre desde ahí.
                </BannerAviso>
              )}
              {doc.estado !== "borrador" && (
                <BannerAviso variante="neutral" enLinea>
                  Este documento ya no está en borrador: esto es una copia de la comunicación de cargos, no algo
                  pendiente de entregar.
                </BannerAviso>
              )}
              {falloMedicion && (
                <BannerAviso variante="advertencia" enLinea>
                  No se pudo leer la asistencia ({falloMedicion}), así que las horas salen en «—». El 19.3 del RIT pide
                  entregarlas: vuelve a cargar antes de imprimir.
                </BannerAviso>
              )}
            </div>
            <ComunicacionCargos doc={doc} persona={persona} sede={sede} areas={areas} previas={previas} medicion={medicion} />
          </>
        )}
      </main>
    </div>
  );
}

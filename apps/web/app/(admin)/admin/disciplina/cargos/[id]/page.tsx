"use client";

// Los cargos de un borrador TAL COMO LOS VE ELLA en su Info (RIT 55.2, 0581).
// No se imprime: desde el 2026-11-03 los cargos se comunican por el sistema
// («no usaremos hojas o imprimir, tiene que verlo en su sistema», Felipe).
//
// Lee `fn_cargos_detalle`, la MISMA función que su Info: un documento legal
// armado dos veces termina diciendo dos cosas. Que quien tramita la abra no
// cuenta como que ella la abrió: la función solo registra la apertura de la
// propia persona.

import { useCallback, useEffect, useMemo, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Cargando } from "@/components/cargando";
import { ComunicacionCargos, type CargosDetalle } from "@/components/disciplina/comunicacion-cargos";
import { selloLima } from "@/components/disciplina/formato";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { esGradual } from "@/lib/admin/disciplina";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { AREAS_FALLBACK, parseAreas, type Area } from "@/lib/areas";

export default function CargosComoLosVeElla() {
  const params = useParams();
  const id = (params?.id as string) ?? "";
  const router = useRouter();
  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  const [doc, setDoc] = useState<CargosDetalle | null>(null);
  const [areas, setAreas] = useState<Area[]>(AREAS_FALLBACK);
  const [cargando, setCargando] = useState(true);
  const [err, setErr] = useState<string | null>(null);

  const cargar = useCallback(async () => {
    setCargando(true); setErr(null);
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    const [{ data: d, error: eD }, { data: ar, error: eAr }] = await Promise.all([
      supabase.rpc("fn_cargos_detalle", { p_id: id }),
      supabase.rpc("fn_areas"),
    ]);
    setAreas(parseAreas(ar, eAr));
    if (eD || !d) {
      setErr(eD ? mensajeDeError(eD, "abrir los cargos") : "No se encontró el documento (o no tienes permiso para verlo).");
      setCargando(false);
      return;
    }
    setDoc(d as unknown as CargosDetalle);
    setCargando(false);
  }, [supabase, router, id]);

  // Cargar al abrir es justamente lo que esta pantalla hace, como la del memo de «Lo mío».
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargar(); }, [cargar]);

  const nombre = doc?.persona ? `${doc.persona.nombres} ${doc.persona.apellidos}` : "la colaboradora";

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        <div className="mb-4 flex max-w-[760px] items-center justify-between">
          <button onClick={() => router.push(`/admin/disciplina#doc-${id}`)} className="text-sm text-taupe hover:text-tinta">← Volver a Disciplina</button>
        </div>

        {cargando ? (
          <Cargando />
        ) : err ? (
          <BannerAviso variante="alerta" className="max-w-[760px]">{err}</BannerAviso>
        ) : doc && !esGradual(doc.nivel) ? (
          <BannerAviso variante="informativo" className="max-w-[760px]">
            La comunicación de cargos previa es para la amonestación y la suspensión (numeral 55.2 del RIT). La
            imputación de cargos ya es, ella misma, la carta que se entrega; la llamada verbal no la necesita.
          </BannerAviso>
        ) : doc && (
          <>
            <div className="mx-auto mb-4 grid max-w-[760px] gap-3">
              <BannerAviso variante="informativo" titulo={doc.cargos_comunicados_at ? `Así lo ve ${nombre} en su Info` : "Así lo verá en su Info"}>
                <p>
                  {doc.cargos_comunicados_at
                    ? <>Se le comunicó el {selloLima(doc.cargos_comunicados_at)} y su plazo de descargo {doc.plazo_vigente ? "vence" : "venció"} el {doc.descargo_vence_at ? selloLima(doc.descargo_vence_at) : "—"}.</>
                    : <>Todavía no se le comunica. Al pulsar «Comunicar cargos» en Disciplina le aparece en su Info y desde ese momento corre su plazo.</>}
                  {" "}El memo de la sanción no se le muestra ni lo firma: sigue en borrador hasta que venza su plazo, se
                  valore su descargo y se firme.
                </p>
              </BannerAviso>
              {doc.cargos_comunicados_at && (
                <BannerAviso variante={doc.recepcion?.recibido_at ? "positivo" : "advertencia"} enLinea>
                  {doc.recepcion?.recibido_at
                    ? `Confirmó que los recibió el ${selloLima(doc.recepcion.recibido_at)}.`
                    : doc.recepcion
                      ? `Los abrió el ${selloLima(doc.recepcion.abierto_at)}, pero todavía no confirma que los recibió.`
                      : "Todavía no los abre. Su plazo corre igual: avísale con «Copiar el aviso para ella» en Disciplina."}
                </BannerAviso>
              )}
              {doc.recomunicado && (
                <BannerAviso variante="neutral" enLinea>
                  Su plazo se reabrió el {selloLima(doc.recomunicado.recomunicado_at)}, al llegar los cargos a su Info. Antes
                  se habían comunicado el {selloLima(doc.recomunicado.antes_comunicados_at)}, fuera del sistema.
                </BannerAviso>
              )}
            </div>
            <ComunicacionCargos doc={doc} areas={areas}>
              {doc.descargos.length > 0 && (
                <div className="mt-6 border-t border-sand pt-4 font-sans">
                  <p className="mb-2 text-xs font-medium uppercase tracking-[0.08em] text-taupe">Su descargo, escrito en su Info</p>
                  {doc.descargos.map((x) => (
                    <blockquote key={x.presentado_at} className="mb-2 border-l-2 border-sand pl-3 text-sm">
                      <p className="whitespace-pre-line">{x.texto}</p>
                      <p className="text-xs text-taupe">{selloLima(x.presentado_at)}</p>
                    </blockquote>
                  ))}
                </div>
              )}
            </ComunicacionCargos>
          </>
        )}
      </main>
    </div>
  );
}

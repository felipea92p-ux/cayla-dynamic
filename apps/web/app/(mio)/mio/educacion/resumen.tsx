"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { ESTADO_CONSTANCIA, type EstadoConstancia } from "@cayla-dynamic/shared";
import { Insignia } from "@/components/ui/insignia";
import { enDias } from "@/lib/admin/bandeja-urgencia";
import { fechaCorta } from "@/lib/educacion";

/**
 * La pestaña «Educación» de /mio: una línea por estudio con el estado de su
 * constancia, y el camino a /mio/educacion. Vive aparte de /mio/page.tsx, que
 * ya pasa las tres mil líneas, y pide sus propios datos solo cuando se abre.
 *
 * Filtra por persona de forma explícita: si quien abre /mio es de DO,
 * `fn_educacion_situacion` le devuelve a todo el equipo.
 *
 * Sin estudio activo pero con uno terminado, no dice «no tienes una asignación»:
 * dice cuál terminó y cuándo, y manda a renovarlo. Decir «Solicitar apoyo» a
 * quien ya lo tenía la mandaba a una pantalla que, con la solicitud aprobada,
 * no ofrecía ningún botón.
 */
interface Fila {
  familia_id: string;
  persona_id: string;
  institucion: string;
  vigencia: string;
  vigente_hasta: string;
  estado_constancia: EstadoConstancia;
  plazo: string | null;
  dias_para_plazo: number | null;
}

/**
 * `personaId` es el de quien tiene la pantalla abierta: /mio ya lo sabe, así que se pasa en
 * vez de volver a buscarlo. Buscarlo era una ronda entera (sesión → `personas`) puesta
 * delante de las otras dos, que ahora salen juntas. Mientras llega, se ve «Cargando…».
 */
export function ResumenEducacionMia({ personaId }: { personaId: string | null }) {
  const [filas, setFilas] = useState<Fila[] | null>(null);
  const [terminado, setTerminado] = useState<Fila | null>(null);
  const [renovacionEnRevision, setRenovacionEnRevision] = useState(false);
  const [error, setError] = useState(false);

  useEffect(() => {
    if (!personaId) return;
    let vivo = true;
    const supabase = createAdminSupabaseClient();
    void (async () => {
      // Recién renovado, «Renuévalo →» sería pedirle lo que ya hizo: por eso se mira también
      // la última solicitud, y se pide junto con la situación porque no depende de ella.
      const [sit, { data: sol }] = await Promise.all([
        supabase.rpc("fn_educacion_situacion"),
        supabase.from("educacion_solicitudes").select("estado")
          .eq("persona_id", personaId).order("enviada_at", { ascending: false }).limit(1).maybeSingle(),
      ]);
      if (!vivo) return;
      if (sit.error) { setError(true); setFilas([]); return; }
      const mias = ((sit.data ?? []) as unknown as Fila[]).filter((f) => f.persona_id === personaId);
      setFilas(mias.filter((f) => f.vigencia !== "terminada"));
      // El que terminó más tarde: el mismo que /mio/educacion ofrece renovar.
      setTerminado(mias.filter((f) => f.vigencia === "terminada")
        .reduce<Fila | null>((m, f) => (!m || f.vigente_hasta > m.vigente_hasta ? f : m), null));
      setRenovacionEnRevision(sol?.estado === "pendiente");
    })();
    return () => { vivo = false; };
  }, [personaId]);

  return (
    <section data-tour="mio-educacion-seccion" className="rounded-2xl border border-sand p-5 text-sm">
      <h2 className="mb-1 font-serif text-lg">Educación</h2>
      {filas === null ? (
        <p className="text-taupe">Cargando…</p>
      ) : error ? (
        <p className="text-taupe">No se pudo leer tu apoyo educativo. Vuelve a intentarlo en un momento.</p>
      ) : filas.length === 0 && terminado ? (
        <>
          <p className="text-taupe">
            Tu apoyo en {terminado.institucion} terminó el {fechaCorta(terminado.vigente_hasta)}.
          </p>
          <Link href="/mio/educacion" data-tour="mio-educacion-ir"
            className="mt-3 inline-block text-tinta underline underline-offset-2 hover:text-rojo-profundo">
            {renovacionEnRevision ? "Tu solicitud está en revisión →" : "¿Sigues estudiando? Renuévalo →"}
          </Link>
        </>
      ) : filas.length === 0 ? (
        <>
          <p className="text-taupe">No tienes una asignación educativa activa.</p>
          <Link href="/mio/educacion" data-tour="mio-educacion-ir"
            className="mt-3 inline-block text-tinta underline underline-offset-2 hover:text-rojo-profundo">
            Solicitar apoyo educativo →
          </Link>
        </>
      ) : (
        <>
          <ul className="mt-2 flex flex-col gap-2">
            {filas.map((f) => {
              const est = ESTADO_CONSTANCIA[f.estado_constancia];
              return (
                <li key={f.familia_id} className="flex flex-wrap items-center justify-between gap-2">
                  <span>
                    {f.institucion}
                    {f.plazo && f.dias_para_plazo !== null && (f.estado_constancia === "por_vencer" || f.estado_constancia === "falta_enviar") && (
                      <span className="text-xs text-taupe"> · {enDias(f.dias_para_plazo, { futuro: "vence", pasado: "venció" })}</span>
                    )}
                  </span>
                  <Insignia variante={est.tono}>{est.etiqueta}</Insignia>
                </li>
              );
            })}
          </ul>
          <Link href="/mio/educacion" data-tour="mio-educacion-ir"
            className="mt-3 inline-block text-tinta underline underline-offset-2 hover:text-rojo-profundo">
            Ir a mis constancias →
          </Link>
        </>
      )}
    </section>
  );
}

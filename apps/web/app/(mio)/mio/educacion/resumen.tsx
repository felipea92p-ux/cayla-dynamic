"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { ESTADO_CONSTANCIA, type EstadoConstancia } from "@cayla-dynamic/shared";
import { Insignia } from "@/components/ui/insignia";
import { enDias } from "@/lib/admin/bandeja-urgencia";

/**
 * La pestaña «Educación» de /mio: una línea por estudio con el estado de su
 * constancia, y el camino a /mio/educacion. Vive aparte de /mio/page.tsx, que
 * ya pasa las tres mil líneas, y pide sus propios datos solo cuando se abre.
 *
 * Filtra por persona de forma explícita: si quien abre /mio es de DO,
 * `fn_educacion_situacion` le devuelve a todo el equipo.
 */
interface Fila {
  familia_id: string;
  persona_id: string;
  institucion: string;
  vigencia: string;
  estado_constancia: EstadoConstancia;
  plazo: string | null;
  dias_para_plazo: number | null;
}

export function ResumenEducacionMia() {
  const [filas, setFilas] = useState<Fila[] | null>(null);
  const [error, setError] = useState(false);

  useEffect(() => {
    let vivo = true;
    const supabase = createAdminSupabaseClient();
    void (async () => {
      const { data: sesion } = await supabase.auth.getSession();
      const uid = sesion.session?.user.id;
      if (!uid) return;
      const [{ data: p }, sit] = await Promise.all([
        supabase.from("personas").select("id").eq("auth_user_id", uid).maybeSingle(),
        supabase.rpc("fn_educacion_situacion"),
      ]);
      if (!vivo) return;
      if (sit.error || !p) { setError(true); setFilas([]); return; }
      setFilas(((sit.data ?? []) as unknown as Fila[])
        .filter((f) => f.persona_id === p.id && f.vigencia !== "terminada"));
    })();
    return () => { vivo = false; };
  }, []);

  return (
    <section className="rounded-2xl border border-sand p-5 text-sm">
      <h2 className="mb-1 font-serif text-lg">Educación</h2>
      {filas === null ? (
        <p className="text-taupe">Cargando…</p>
      ) : error ? (
        <p className="text-taupe">No se pudo leer tu apoyo educativo. Vuelve a intentarlo en un momento.</p>
      ) : filas.length === 0 ? (
        <p className="text-taupe">No tienes una asignación educativa activa.</p>
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
          <Link href="/mio/educacion"
            className="mt-3 inline-block text-tinta underline underline-offset-2 hover:text-rojo-profundo">
            Ir a mis constancias →
          </Link>
        </>
      )}
    </section>
  );
}

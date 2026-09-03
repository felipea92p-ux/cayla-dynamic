"use client";

// ============================================================================
// Los anuncios que a esta persona todavía le faltan por leer.
// ============================================================================
//
// Hermano liviano de `AcusesPendientes`, y a propósito distinto de él: aquél
// es un modal que insiste porque la ley exige poder probar que se informó
// (Ley 30709, RIT). Un anuncio ("la planilla cierra el 28") no tiene esa
// exigencia detrás, así que esto NO es un modal, no bloquea nada y no vuelve
// a insistir después de marcarlo leído — se lee, se marca, desaparece de acá
// para siempre (sigue disponible en /admin/anuncios).
//
// Si no hay nada pendiente, no se dibuja nada: un espacio vacío en «Lo mío»
// también es información («no tienes nada por leer»), pero un cascarón vacío
// con un título y sin contenido solo sería ruido.
// ============================================================================

import { useEffect, useState } from "react";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { Boton } from "@/components/ui/boton";

interface AnuncioPendiente {
  id: string;
  titulo: string;
  cuerpo: string;
  sede_codigo: string | null;
}

export function AnunciosWidget() {
  const persona = usePersonaActual();
  const [pendientes, setPendientes] = useState<AnuncioPendiente[]>([]);

  useEffect(() => {
    if (!persona) return;
    let vivo = true;
    const supabase = createAdminSupabaseClient();

    void supabase.rpc("fn_anuncios_vigentes", { p_incluir_anulados: false }).then(({ data }) => {
      if (!vivo) return;
      const lista = ((data as Array<{
        id: string; titulo: string; cuerpo: string; sede_codigo: string | null; mi_leido_at: string | null;
      }> | null) ?? []).filter((a) => !a.mi_leido_at);
      setPendientes(lista.map((a) => ({ id: a.id, titulo: a.titulo, cuerpo: a.cuerpo, sede_codigo: a.sede_codigo })));
    });

    return () => { vivo = false; };
  }, [persona]);

  async function marcarLeido(id: string) {
    // Optimista, igual que en /admin/anuncios: es un marcador liviano, no una
    // escritura cuyo fallo le importe a quien lo mira.
    setPendientes((prev) => prev.filter((a) => a.id !== id));
    await createAdminSupabaseClient().rpc("fn_marcar_anuncio_leido", { p_id: id });
  }

  if (pendientes.length === 0) return null;

  return (
    <section className="mb-6 rounded-2xl border border-sand bg-papel p-4">
      <h2 className="mb-2 text-sm font-medium text-tinta">
        {pendientes.length === 1 ? "Un anuncio para ti" : `${pendientes.length} anuncios para ti`}
      </h2>
      <ul className="space-y-2">
        {pendientes.map((a) => (
          <li key={a.id} className="rounded-xl border border-sand/70 bg-crema p-3">
            <div className="flex flex-wrap items-baseline justify-between gap-2">
              <p className="text-sm font-medium text-tinta">{a.titulo}</p>
              {a.sede_codigo && <span className="text-xs text-taupe">{a.sede_codigo}</span>}
            </div>
            <p className="mt-1 text-xs text-taupe">{a.cuerpo}</p>
            <Boton variante="sutil" tamano="sm" className="mt-2" onClick={() => marcarLeido(a.id)}>
              Marcar como leído
            </Boton>
          </li>
        ))}
      </ul>
      <Link href="/admin/anuncios" className="mt-3 inline-block text-xs text-taupe underline">
        Ver todos los anuncios
      </Link>
    </section>
  );
}

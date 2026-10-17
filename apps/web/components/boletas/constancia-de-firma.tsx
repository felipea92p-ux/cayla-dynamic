"use client";

import { useEffect, useState } from "react";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { fechaHoraLima } from "@/lib/admin/boletas-pantalla";

/**
 * LA CONSTANCIA DE FIRMA DE UNA BOLETA (0532): la firma que la persona copió en
 * esa boleta al firmarla, quién y cuándo.
 *
 * Lo comparten tres sitios —el modal de «Ver boleta firmada», el de anular y el
 * de «Ver anulación»— y por eso vive aparte: «cómo se muestra una firma» tiene
 * una sola respuesta.
 *
 * LA FIRMA ES LA COPIA, no la guardada hoy: `fn_boleta_constancia` devuelve la
 * imagen que se escribió en el acuse al firmar. Si la persona cambió su firma
 * después, aquí se ve la que usó ese día.
 *
 * FONDO CLARO FIJO. Una firma es tinta oscura sobre fondo transparente; sobre el
 * modo oscuro desaparecería. El recuadro usa los tokens `-fija` de `globals.css`
 * (los que NO cambian con el tema), igual que la vista previa de la firma en la
 * ficha de la persona: es un papel, y un papel no se oscurece.
 */

export type Constancia = {
  vista_at: string | null;
  recibida_at: string | null;
  firma: string | null;
};

/** Pide la constancia de una versión. `null` mientras carga; `error` si la base no responde. */
export function useConstancia(supabase: ClienteCayla, versionId: string | null) {
  const [constancia, setConstancia] = useState<Constancia | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!versionId) return;
    let vigente = true;
    void supabase.rpc("fn_boleta_constancia", { p_version_id: versionId }).then(({ data, error: e }) => {
      if (!vigente) return;
      if (e) { setError(e.message); return; }
      const fila = (data ?? [])[0];
      setError(null);
      // Sin fila = todavía no hay acuse (nunca la abrió): es una constancia vacía, no un error.
      setConstancia(fila
        ? { vista_at: fila.vista_at, recibida_at: fila.recibida_at, firma: fila.firma }
        : { vista_at: null, recibida_at: null, firma: null });
    });
    return () => { vigente = false; };
  }, [supabase, versionId]);

  return { constancia, error };
}

export function ConstanciaDeFirma({
  nombre, constancia, error,
}: {
  nombre: string;
  /** `null` = todavía cargando. */
  constancia: Constancia | null;
  error?: string | null;
}) {
  return (
    <section aria-label="Constancia de firma" className="rounded-xl border border-sand bg-hueso p-4">
      <h3 className="mb-2 text-xs font-medium uppercase tracking-wide text-verde">Constancia de firma</h3>
      {error ? (
        <p role="alert" className="text-sm text-rojo-profundo">No pudimos leer la constancia: {error}</p>
      ) : constancia === null ? (
        <p className="text-sm text-taupe">Cargando…</p>
      ) : constancia.firma && constancia.recibida_at ? (
        <>
          <div
            className="flex min-h-24 flex-col items-center justify-end gap-1 rounded-lg border border-sand px-4 pb-2 pt-3"
            style={{ background: "var(--color-crema-fija)", color: "var(--color-tinta-fija)" }}
          >
            {/* eslint-disable-next-line @next/next/no-img-element -- la firma viene como data URL de la base */}
            <img src={constancia.firma} alt={`Firma de ${nombre}`} className="max-h-20 w-auto max-w-full" />
            <span className="block w-4/5 border-t" style={{ borderColor: "var(--color-tinta-fija)" }} />
            <span className="text-xs">{nombre}</span>
          </div>
          <p className="mt-3 text-sm text-tinta">Firmada por {nombre} el {fechaHoraLima(constancia.recibida_at)}.</p>
          <p className="mt-1 text-xs text-taupe">
            La firma es la copia que usó ese día: si cambia su firma después, esta boleta no cambia.
            {constancia.vista_at ? ` La abrió por primera vez el ${fechaHoraLima(constancia.vista_at)}.` : ""}
          </p>
        </>
      ) : constancia.recibida_at ? (
        <p className="text-sm text-tinta">
          {nombre} confirmó que la recibió el {fechaHoraLima(constancia.recibida_at)}, antes de que las boletas se firmaran.
          Esa confirmación no tiene firma.
        </p>
      ) : (
        <p className="text-sm text-tinta">
          Todavía no la firmó.{constancia.vista_at ? ` La abrió por primera vez el ${fechaHoraLima(constancia.vista_at)}.` : " Todavía no la abrió."}
        </p>
      )}
    </section>
  );
}

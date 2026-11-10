"use client";

// ============================================================================
// El contrato de locación generado en Dynamic, para leerlo e imprimirlo (0612)
// ============================================================================
// QUÉ PROMETE
//   Mostrar el documento congelado con las dos firmas estampadas —la de CAYLA,
//   la del firmante configurado (`fn_firma_empresa`), y la de la persona, la
//   copia que se guardó al firmar— y dejar imprimirlo o guardarlo como PDF con
//   su nombre. Lo usan DO (en el panel de cada persona) y la propia persona (en
//   «Lo mío»): una sola pieza para que las dos vean lo mismo.
//
// LAS FIRMAS SE ESTAMPAN AL MOSTRAR, NUNCA AL GUARDAR
//   Igual que el contrato de trabajo: `documento_html` congela el texto
//   pactado, no cómo se ve. Sin firma de la persona, su línea queda en blanco:
//   eso es lo que todavía no firmó. Bajo cada firma va cuándo se firmó, que es
//   lo que dice el contrato que lo hace celebrado (`estamparFirmas`).
// ============================================================================

import { useCallback, useEffect, useState } from "react";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { Cargando } from "@/components/cargando";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Boton } from "@/components/ui/boton";
import { ImprimibleAparte, useImprimirAparte } from "@/components/ui/imprimible-aparte";
import { estamparFirmas } from "@/lib/admin/locacion-texto";
import { mensajeDeError } from "@/lib/admin/mensaje-error";

export function DocumentoLocacion({
  supabase,
  contratoId,
  nombreDelPdf,
  /** Cambia cuando la persona acaba de firmar: vuelve a leer para mostrar su firma. */
  version = 0,
}: {
  supabase: ClienteCayla;
  contratoId: string;
  nombreDelPdf: string;
  version?: number;
}) {
  const [html, setHtml] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [cargando, setCargando] = useState(true);
  const { copia, preparando, imprimir } = useImprimirAparte(html ? nombreDelPdf : null);

  const cargar = useCallback(async () => {
    const [{ data, error: e }, { data: firmaEmpresa }] = await Promise.all([
      supabase.rpc("fn_locacion_documento", { p_id: contratoId }),
      supabase.rpc("fn_firma_empresa"),
    ]);
    const fila = ((data ?? []) as {
      documento_html: string;
      firma_persona: string | null;
      generado_at: string | null;
      firmado_at: string | null;
    }[])[0];
    if (e || !fila) {
      setError(e ? mensajeDeError(e, "abrir el contrato") : "No se encontró el contrato.");
      setHtml(null);
    } else {
      setError(null);
      setHtml(estamparFirmas(fila.documento_html, {
        empresa: typeof firmaEmpresa === "string" ? firmaEmpresa : null,
        persona: fila.firma_persona,
        empresaAt: fila.generado_at,
        personaAt: fila.firmado_at,
      }));
    }
    setCargando(false);
  }, [supabase, contratoId]);

  // `version` vuelve a pedir el documento después de firmar.
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargar(); }, [cargar, version]);

  if (cargando) return <Cargando />;
  if (error || !html) return <BannerAviso enLinea role="alert">{error ?? "No se encontró el contrato."}</BannerAviso>;

  return (
    <div className="space-y-3">
      <div className="flex justify-end">
        <Boton variante="secundario" tamano="sm" onClick={() => void imprimir()} cargando={preparando}>
          Imprimir / Guardar como PDF
        </Boton>
      </div>
      <div
        className="hoja rounded-lg border border-sand p-4 text-sm leading-relaxed sm:p-8"
        dangerouslySetInnerHTML={{ __html: html }}
      />
      <ImprimibleAparte ref={copia}>
        <div className="hoja text-sm leading-relaxed" dangerouslySetInnerHTML={{ __html: html }} />
      </ImprimibleAparte>
    </div>
  );
}

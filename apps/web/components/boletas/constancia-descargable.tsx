"use client";

import { useState, type ReactNode } from "react";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { Cargando } from "@/components/cargando";
import { ImprimibleAparte, useImprimirAparte } from "@/components/ui/imprimible-aparte";
import { useConstancia } from "@/components/boletas/constancia-de-firma";
import { HojaConstanciaBoleta, useDatosDeConstancia, usePaginasDeBoleta } from "@/components/boletas/hoja-constancia-boleta";
import type { TipoBoleta } from "@/lib/boletas";
import type { HojaFirmada } from "@/lib/boletas-archivos";

/**
 * LA CONSTANCIA DE UNA BOLETA FIRMADA, LISTA PARA MIRAR Y DESCARGAR.
 *
 * La usan dos pantallas: DO desde el tablero («Ver boleta firmada») y la
 * persona desde «Lo mío» → Boletas (2026-10-17). Las dos piden lo mismo —la
 * firma (`fn_boleta_constancia`), los datos (`fn_boleta_datos_de_constancia`,
 * 0533) y las hojas— y arman la misma hoja; si cada una lo hiciera por su
 * cuenta, el papel de DO y el de la persona podrían terminar diciendo cosas
 * distintas sobre la misma firma.
 *
 * Devuelve el CONTENIDO (la hoja en pantalla y su copia para imprimir) y lo que
 * necesita el botón «Descargar PDF», que cada pantalla pone en su propio pie.
 * Con `versionId` en `null` no pide nada: así un modal puede llamarla siempre y
 * activarla solo cuando corresponde.
 *
 * No se descarga hasta tener la firma, los datos completos y las hojas (o el
 * aviso de que un PDF no se pudo dibujar): un papel a medio armar no se entrega.
 */
export function useConstanciaDescargable({
  supabase, versionId, hojas, tipo, periodo, version, respaldo, nombreDelPdf,
}: {
  supabase: ClienteCayla;
  versionId: string | null;
  /** Las hojas ya firmadas por quien abre; `null` mientras se piden. */
  hojas: readonly HojaFirmada[] | null;
  tipo: TipoBoleta;
  periodo: { nombre: string; desde: string | null; hasta: string | null };
  version: number | null;
  /** Lo que la pantalla ya sabe, por si la base no contesta los datos. */
  respaldo: { nombre: string; sede: string | null; cargo: string | null };
  /** El nombre con que el navegador propone guardar el PDF. */
  nombreDelPdf: string;
}): { contenido: ReactNode; lista: boolean; preparando: boolean; descargar: () => Promise<void> } {
  const { constancia, error: errorConstancia } = useConstancia(supabase, versionId);
  const { datos, aviso } = useDatosDeConstancia(supabase, versionId, respaldo);
  const { paginas, error: errorPaginas } = usePaginasDeBoleta(versionId ? hojas : null, tipo);
  // La hora de «generada» se fija al abrir: la hoja de la pantalla y la que se
  // imprime tienen que decir lo mismo.
  const [generadaAt] = useState(() => new Date().toISOString());
  const { copia, preparando, imprimir } = useImprimirAparte(versionId ? nombreDelPdf : null);

  const hoja = (enPapel: boolean) => constancia && datos && (
    <HojaConstanciaBoleta
      periodo={periodo}
      version={version}
      datos={datos}
      constancia={constancia}
      paginas={paginas}
      errorPaginas={errorPaginas}
      pdfs={tipo === "pdf" ? (hojas ?? []).map((h) => h.url) : []}
      generadaAt={generadaAt}
      enPapel={enPapel}
    />
  );

  const contenido = errorConstancia ? (
    <p role="alert" className="rounded-control bg-rojo/10 px-3 py-2 text-sm text-rojo-profundo">
      No pudimos leer la constancia de firma: {errorConstancia}
    </p>
  ) : hojas === null || constancia === null || datos === null ? (
    <Cargando texto="Abriendo la boleta…" />
  ) : (
    <>
      {aviso && <p role="alert" className="mb-3 rounded-control bg-ambar/10 px-3 py-2 text-sm text-ambar">{aviso}</p>}
      {hoja(false)}
      <ImprimibleAparte ref={copia}>{hoja(true)}</ImprimibleAparte>
    </>
  );

  const lista = constancia !== null && datos !== null && datos.completos && (paginas !== null || errorPaginas !== null);

  return { contenido, lista, preparando, descargar: imprimir };
}

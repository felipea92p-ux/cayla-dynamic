"use client";

// ============================================================================
// Tus contratos de locación — «Lo mío › Contrato» de quien cobra por honorarios
// ============================================================================
// QUÉ PROMETE
//   Que quien cobra por recibo por honorarios vea en Dynamic el contrato de
//   locación de servicios que firmó, y lo abra, igual que quien está en planilla
//   ve el suyo. Pedido por Felipe el 2026-11-10. Migración 0610:
//   `fn_locaciones_listar` (para quien no es DO devuelve solo lo propio, sin
//   anulados ni motivos internos) y la política de Storage que le deja abrir su
//   escaneo y ningún otro.
//
// QUÉ NO HACE
//   No se firma aquí. Firmar en pantalla necesita que el contrato esté
//   redactado dentro de Dynamic, como el de trabajo, y para la locación todavía
//   no hay un texto aprobado por el abogado: lo que hay es el escaneo de un
//   papel ya firmado.
// ============================================================================

import { useState } from "react";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { abrirArchivoFirmado } from "@/lib/abrir-archivo-firmado";
import { BUCKET_LOCACION, ESTADO_CONTRATO, type ContratoLocacion } from "@/lib/admin/locaciones";
import { isoADiaMesAnio } from "@/lib/admin/planilla/formato";

export function MisLocaciones({
  supabase,
  contratos,
  titulo,
  intro,
}: {
  supabase: ClienteCayla;
  contratos: readonly ContratoLocacion[];
  titulo: string;
  intro: string;
}) {
  const [error, setError] = useState<string | null>(null);

  async function ver(c: ContratoLocacion) {
    setError(null);
    const fallo = await abrirArchivoFirmado(supabase, BUCKET_LOCACION, c.storage_path);
    if (fallo) setError(fallo);
  }

  return (
    <section aria-label={titulo} className="space-y-3 print:hidden">
      <h2 className="font-serif text-lg">{titulo}</h2>
      <p className="text-sm text-taupe">{intro}</p>
      {error && <BannerAviso enLinea role="alert">{error}</BannerAviso>}
      <ul className="space-y-3">
        {contratos.map((c) => {
          const estado = ESTADO_CONTRATO[c.estado];
          return (
            <li key={c.id}>
              <TarjetaInfo className="space-y-1.5 p-4 sm:p-4">
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <p className="font-medium text-tinta">{c.servicio}</p>
                  <Insignia variante={estado.variante} tamano="sm">{estado.texto}</Insignia>
                </div>
                <p className="text-sm text-tinta">
                  Del {isoADiaMesAnio(c.fecha_inicio)} al {isoADiaMesAnio(c.terminado_el ?? c.fecha_fin)}
                  {c.terminado_el && <span className="text-taupe"> (iba hasta el {isoADiaMesAnio(c.fecha_fin)})</span>}
                </p>
                <p className="text-xs text-taupe">Firmado el {isoADiaMesAnio(c.fecha_firma)}</p>
                <div className="pt-1">
                  <Boton variante="enlace" className="text-sm" onClick={() => void ver(c)}>Ver el contrato firmado</Boton>
                </div>
              </TarjetaInfo>
            </li>
          );
        })}
      </ul>
      <p className="text-xs text-taupe">
        Si algo no coincide con lo que firmaste, avisa a Desarrollo Organizacional.
      </p>
    </section>
  );
}

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
// Y LO FIRMA AQUÍ, si se generó en Dynamic (0615)
//   Como el contrato de trabajo desde la 0430: confirmar tu firma ES firmar, y
//   se guarda la copia de tu firma de ese momento. Mientras el texto sea un
//   borrador sin revisión legal (`TEXTO_LOCACION_APROBADO`), se puede leer pero
//   no firmar: el documento mismo dice «No firmar».
//   Un contrato que llegó como escaneo de un papel ya está firmado: se abre.
// ============================================================================

import { useState } from "react";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { abrirArchivoFirmado } from "@/lib/abrir-archivo-firmado";
import { BUCKET_LOCACION, ESTADO_CONTRATO, type ContratoLocacion } from "@/lib/admin/locaciones";
import { TEXTO_LOCACION_APROBADO } from "@/lib/admin/locacion-texto";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { DocumentoLocacion } from "@/components/contratos/documento-locacion";
import { FirmaEditor } from "@/app/(admin)/admin/personas/[id]/FirmaEditor";
import { isoADiaMesAnio } from "@/lib/admin/planilla/formato";

export function MisLocaciones({
  supabase,
  contratos,
  titulo,
  intro,
  nombreOficial,
  alFirmar,
}: {
  supabase: ClienteCayla;
  contratos: readonly ContratoLocacion[];
  titulo: string;
  intro: string;
  /** El nombre como sale del DNI: el que lleva la firma escrita (ver FirmaEditor). */
  nombreOficial: string;
  /** Avisa que se firmó algo, para que la pantalla vuelva a leer. */
  alFirmar: () => void;
}) {
  const [error, setError] = useState<string | null>(null);
  // El contrato generado que se está leyendo, uno a la vez.
  const [abierto, setAbierto] = useState<string | null>(null);
  const [firmando, setFirmando] = useState(false);
  const [aviso, setAviso] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  // Sube después de firmar, para que el documento vuelva a leerse con la firma puesta.
  const [version, setVersion] = useState(0);

  async function firmar(c: ContratoLocacion) {
    setFirmando(true);
    setAviso(null);
    const { error: e } = await supabase.rpc("fn_confirmar_mi_firma_locacion", { p_id: c.id });
    setFirmando(false);
    if (e) { setAviso({ tipo: "error", texto: mensajeDeError(e, "firmar") }); return; }
    setAviso({ tipo: "ok", texto: "Contrato firmado." });
    setVersion((v) => v + 1);
    alFirmar();
  }

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
                <p className="text-xs text-taupe">
                  {c.fecha_firma ? `Firmado el ${isoADiaMesAnio(c.fecha_firma)}` : "Todavía no lo firmaste"}
                </p>
                <div className="pt-1">
                  {c.es_digital ? (
                    <Boton variante="enlace" className="text-sm" onClick={() => setAbierto(abierto === c.id ? null : c.id)}>
                      {abierto === c.id ? "Cerrar" : c.estado === "sin_firmar" ? "Leer y firmar" : "Ver el contrato"}
                    </Boton>
                  ) : (
                    <Boton variante="enlace" className="text-sm" onClick={() => void ver(c)}>Ver el contrato firmado</Boton>
                  )}
                </div>
                {abierto === c.id && (
                  <div className="space-y-3 pt-2">
                    <DocumentoLocacion
                      supabase={supabase}
                      contratoId={c.id}
                      nombreDelPdf={`${nombreOficial} — Contrato de locación`}
                      version={version}
                    />
                    {c.estado === "sin_firmar" && (
                      TEXTO_LOCACION_APROBADO ? (
                        <TarjetaInfo titulo="Tu firma" className="space-y-3">
                          <p className="text-xs text-taupe">
                            Al firmar, tu firma queda en el contrato junto a la de CAYLA, con la fecha de hoy. No hace
                            falta imprimir nada.
                          </p>
                          {aviso && (
                            <p className={`text-xs ${aviso.tipo === "ok" ? "text-verde" : "text-rojo"}`}>{aviso.texto}</p>
                          )}
                          <FirmaEditor
                            supabase={supabase}
                            nombreOficial={nombreOficial}
                            avisar={(tipo, texto) => setAviso({ tipo, texto })}
                            onGuardada={() => setAviso(null)}
                          />
                          <Boton variante="primario" onClick={() => void firmar(c)} cargando={firmando} disabled={firmando}>
                            Firmar este contrato
                          </Boton>
                        </TarjetaInfo>
                      ) : (
                        <BannerAviso enLinea variante="advertencia">
                          Este contrato todavía es un borrador en revisión: todavía no se firma. Desarrollo
                          Organizacional te avisa cuando esté listo.
                        </BannerAviso>
                      )
                    )}
                  </div>
                )}
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

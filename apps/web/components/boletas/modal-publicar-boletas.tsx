"use client";

import { useEffect, useState } from "react";
import { FileText } from "lucide-react";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { Modal } from "@/components/ui/modal";
import { Boton } from "@/components/ui/boton";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { PieDeModal, TACTIL } from "@/components/boletas/pie-de-modal";
import { hojasFirmadasDeVersion } from "@/lib/boletas-archivos";
import { resumenDelDocumento, type FilaTablero } from "@/lib/admin/boletas-pantalla";
import { mensajeDeError } from "@/lib/admin/mensaje-error";

/**
 * PUBLICAR LOS BORRADORES DE UN PERIODO — la última mirada antes de que la
 * persona pueda abrir su boleta.
 *
 * PROMETE: lista CADA borrador con su primera hoja en miniatura y un «Ver», y
 * publica exactamente los que se listaron. Si alguien subió otro borrador
 * mientras este modal estaba abierto, ese NO se publica: nadie lo revisó.
 * Por eso se mandan los ids de las personas (`p_personas`) en vez de «todos los
 * borradores del periodo».
 * ASUME: `fn_boletas_publicar` (0482) solo publica lo que tiene versión y cuyo
 * grupo sigue pagado; devuelve cuántas publicó, que puede ser menos.
 *
 * SE QUEDA MONTADO MIENTRAS SE MIRA UNA BOLETA (`oculto`): al volver de «Ver»
 * las miniaturas ya están, sin pedir de nuevo a la base treinta veces.
 */
type Miniatura = { url: string | null; esPdf: boolean };

export function ModalPublicarBoletas({
  supabase,
  periodoId,
  nombreDelPeriodo,
  borradores,
  oculto,
  onVer,
  onCerrar,
  onPublicadas,
}: {
  supabase: ClienteCayla;
  periodoId: string;
  nombreDelPeriodo: string;
  borradores: readonly FilaTablero[];
  oculto: boolean;
  onVer: (fila: FilaTablero) => void;
  onCerrar: () => void;
  onPublicadas: (publicadas: number, listadas: number) => void;
}) {
  const [miniaturas, setMiniaturas] = useState<Record<string, Miniatura>>({});
  const [publicando, setPublicando] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Se piden una sola vez: la lista de borradores no cambia mientras el modal vive.
  useEffect(() => {
    let vigente = true;
    void Promise.all(borradores.map(async (b) => {
      if (b.version_id === null) return [b.persona_id, { url: null, esPdf: false }] as const;
      const r = await hojasFirmadasDeVersion(supabase, b.version_id, 1800);
      const primera = r.hojas[0];
      return [b.persona_id, { url: primera && b.tipo !== "pdf" ? primera.url : null, esPdf: b.tipo === "pdf" }] as const;
    })).then((pares) => {
      if (vigente) setMiniaturas(Object.fromEntries(pares));
    });
    return () => { vigente = false; };
    // Los borradores se listaron al abrir; volver a pedirlas por un refresco del tablero no aporta.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function publicar() {
    setError(null);
    setPublicando(true);
    const { data, error: e } = await supabase.rpc("fn_boletas_publicar", {
      p_periodo_id: periodoId,
      p_personas: borradores.map((b) => b.persona_id),
    });
    if (e) {
      setPublicando(false);
      setError(mensajeDeError(e));
      return;
    }
    onPublicadas(data ?? 0, borradores.length);
  }

  const n = borradores.length;

  return (
    <Modal
      abierto={!oculto}
      onCerrar={onCerrar}
      titulo="Publicar boletas"
      ancho="lg"
      bloqueado={publicando}
    >
      <p className="text-sm text-tinta">
        Vas a publicar <b className="font-medium">{n} {n === 1 ? "boleta" : "boletas"}</b> de {nombreDelPeriodo}.
        Cada persona podrá abrir la suya.
      </p>
      <BannerAviso variante="advertencia" className="mt-3">
        Antes de publicar, abre cada una con «Ver» y comprueba que es de quien dice ser:
        una boleta en manos equivocadas expone un sueldo.
      </BannerAviso>

      <ul className="mt-3">
        {borradores.map((b) => {
          const mini = miniaturas[b.persona_id];
          return (
            <li key={b.persona_id} className="flex items-center justify-between gap-3 border-t border-sand py-3 first:border-t-0">
              <div className="flex min-w-0 items-center gap-3">
                <div className="flex h-14 w-11 shrink-0 items-center justify-center overflow-hidden rounded-control border border-sand bg-hueso text-taupe">
                  {mini?.url ? (
                    // eslint-disable-next-line @next/next/no-img-element -- miniatura de un bucket privado, no un asset del proyecto
                    <img src={mini.url} alt="" className="h-full w-full object-cover" />
                  ) : mini?.esPdf || b.tipo === "pdf" ? (
                    <FileText size={20} aria-hidden />
                  ) : (
                    <span className="text-[10px]">{mini ? "sin vista" : "…"}</span>
                  )}
                </div>
                <div className="min-w-0">
                  <p className="break-words text-sm text-tinta">{b.nombre}</p>
                  <p className="text-xs text-taupe">{resumenDelDocumento(b) ?? "—"}</p>
                </div>
              </div>
              <Boton tamano="sm" className={`shrink-0 ${TACTIL}`} disabled={publicando} onClick={() => onVer(b)}>Ver</Boton>
            </li>
          );
        })}
      </ul>

      {error && <p role="alert" className="mt-3 rounded-control bg-rojo/10 px-3 py-2 text-sm text-rojo-profundo">{error}</p>}

      <PieDeModal>
        <Boton className={TACTIL} disabled={publicando} onClick={onCerrar}>Todavía no</Boton>
        <Boton variante="primario" className={TACTIL} cargando={publicando} disabled={n === 0} onClick={() => void publicar()}>
          {publicando ? "Publicando…" : `Publicar ${n === 1 ? "la boleta" : `las ${n} boletas`}`}
        </Boton>
      </PieDeModal>
    </Modal>
  );
}

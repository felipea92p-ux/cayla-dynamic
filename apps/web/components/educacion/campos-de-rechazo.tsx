"use client";

import { MOTIVOS_RECHAZO, MOTIVO_RECHAZO_LABELS, type MotivoRechazo } from "@cayla-dynamic/shared";
import { CampoSelect } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";

/**
 * LOS DOS CAMPOS DE UN RECHAZO: el motivo de la lista y qué tiene que corregir.
 *
 * PROMETE: ser LA ÚNICA copia de «qué se le dice a la integrante al rechazar». La usan
 *   el rechazo de una constancia pendiente (`AccionesRevision`) y la reversión de una
 *   aprobación (`AprobadasDelCiclo`, 0525): dos copias acaban contradiciéndose.
 * ASUME: el padre guarda los dos valores y valida con `rechazoIncompleto`
 *   (`lib/admin/educacion-ciclo.ts`): motivo elegido y texto de 3 o más letras, sin máximo.
 * NO HACE: no llama a la base ni dibuja botones.
 */
export function CamposDeRechazo({
  categoria, onCategoria, comentario, onComentario,
}: {
  categoria: MotivoRechazo | "";
  onCategoria: (c: MotivoRechazo | "") => void;
  comentario: string;
  onComentario: (t: string) => void;
}) {
  return (
    <>
      <CampoSelect etiqueta="Motivo *" value={categoria} onChange={(e) => onCategoria(e.target.value as MotivoRechazo | "")}>
        <option value="">— elige el motivo —</option>
        {MOTIVOS_RECHAZO.map((m) => <option key={m} value={m}>{MOTIVO_RECHAZO_LABELS[m]}</option>)}
      </CampoSelect>
      <label className="mt-3 flex flex-col gap-1 text-sm">
        Qué tiene que corregir *
        <AreaTexto rows={3} value={comentario} onChange={(e) => onComentario(e.target.value)}
          placeholder="ej. la foto está cortada y no se ve el monto pagado" />
        <span className="text-xs text-taupe">Mínimo 3 letras; escribe lo que haga falta.</span>
      </label>
    </>
  );
}

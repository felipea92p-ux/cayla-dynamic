"use client";

// ============================================================================
// Los cambios de seguro de una persona: lo que falta cerrar, y lo que ya pasó
// ============================================================================
// QUÉ PROMETE
//   Cuando alguien cambia de seguro (porque cambió de vínculo, o porque DO se lo
//   cambió) quedan DOS pasos fuera de Dynamic: pedir la baja del seguro anterior y dar
//   de alta el nuevo. Aquí se ven, con el texto de cada seguro, y se cierran por
//   separado con la fecha en que se hicieron. Los que ya se cerraron —o que dejaron de
//   hacer falta solos— quedan abajo como historia, con su marca por si hubo que
//   quitarla.
//
// QUÉ NO HACE
//   No decide qué pasos siguen pendientes: la base lo calcula al leer (un paso se cierra
//   solo cuando la póliza ya terminó o ya se registró otra). Aquí solo se pinta.
// ============================================================================

import { Boton } from "@/components/ui/boton";
import { isoADiaMesAnio } from "@/lib/admin/planilla/formato";
import { origenDelCambio, resumenDelCambio, type CambioSeguro } from "@/lib/admin/seguros";

const fecha = isoADiaMesAnio;

type Paso = "baja" | "alta";
export type AlMarcarPasoDeCambio = (c: CambioSeguro, paso: Paso, quitar: boolean) => void;

/** Un paso de un cambio: pendiente, hecho o «ya no hace falta». */
function PasoDeCambio({
  texto, pendiente, hechaEl, nota, onMarcar, onQuitar,
}: {
  texto: string;
  pendiente: boolean;
  hechaEl: string | null;
  nota: string | null;
  onMarcar: () => void;
  onQuitar: () => void;
}) {
  if (hechaEl) {
    return (
      <li className="text-sm">
        <span className="text-tinta">✓ {texto}</span>
        <span className="text-taupe"> — hecho el {fecha(hechaEl)}</span>
        <span className="ml-3 inline-flex flex-wrap gap-x-3">
          <Boton variante="enlace" aria-label={`Cambiar la fecha: ${texto}`} onClick={onMarcar}>Cambiar la fecha</Boton>
          <Boton variante="enlace" aria-label={`Quitar la marca: ${texto}`} onClick={onQuitar}>Quitar la marca</Boton>
        </span>
        {nota && <span className="block text-xs text-taupe">{nota}</span>}
      </li>
    );
  }
  if (pendiente) {
    return (
      <li className="flex flex-wrap items-center gap-x-3 gap-y-1 text-sm">
        <span className="text-tinta">{texto}</span>
        <Boton variante="enlace" aria-label={`Marcar como hecho: ${texto}`} onClick={onMarcar}>Marcar como hecho</Boton>
      </li>
    );
  }
  return <li className="text-sm text-taupe">{texto} — ya no hace falta</li>;
}

function PasosDe({ c, onPaso }: { c: CambioSeguro; onPaso: AlMarcarPasoDeCambio }) {
  return (
    <ul className="space-y-1.5">
      {c.de_tipo && (
        <PasoDeCambio
          texto={c.baja_texto} pendiente={c.baja_pendiente} hechaEl={c.baja_hecha_el} nota={c.baja_nota}
          onMarcar={() => onPaso(c, "baja", false)} onQuitar={() => onPaso(c, "baja", true)}
        />
      )}
      {c.a_tipo && (
        <PasoDeCambio
          texto={c.alta_texto} pendiente={c.alta_pendiente} hechaEl={c.alta_hecha_el} nota={c.alta_nota}
          onMarcar={() => onPaso(c, "alta", false)} onQuitar={() => onPaso(c, "alta", true)}
        />
      )}
    </ul>
  );
}

/** Los cambios que todavía piden un paso, bien a la vista. */
export function CambiosPendientes({ cambios, onPaso }: { cambios: CambioSeguro[]; onPaso: AlMarcarPasoDeCambio }) {
  if (cambios.length === 0) return null;
  return (
    <div className="space-y-3">
      {cambios.map((c) => (
        <div key={c.id} className="rounded-lg border border-ambar/30 bg-ambar/10 px-3 py-3">
          <p className="mb-2 text-sm text-tinta">
            <span className="font-medium">Cambió de seguro el {fecha(c.fecha)}: {resumenDelCambio(c)}.</span>{" "}
            <span className="text-taupe">Motivo: {origenDelCambio(c)}.</span>
          </p>
          <PasosDe c={c} onPaso={onPaso} />
        </div>
      ))}
    </div>
  );
}

/** Los cambios ya cerrados (o que dejaron de hacer falta), plegados: es historia. */
export function CambiosAnteriores({ cambios, onPaso }: { cambios: CambioSeguro[]; onPaso: AlMarcarPasoDeCambio }) {
  if (cambios.length === 0) return null;
  return (
    <details className="text-sm">
      <summary className="cursor-pointer text-taupe">
        {cambios.length === 1 ? "Un cambio de seguro anterior" : `${cambios.length} cambios de seguro anteriores`}
      </summary>
      <div className="mt-2 space-y-3">
        {cambios.map((c) => (
          <div key={c.id} className="rounded-lg border border-sand bg-hueso px-3 py-3">
            <p className="mb-2 text-tinta">
              {fecha(c.fecha)} · {resumenDelCambio(c)} <span className="text-taupe">· {origenDelCambio(c)}</span>
            </p>
            <PasosDe c={c} onPaso={onPaso} />
          </div>
        ))}
      </div>
    </details>
  );
}

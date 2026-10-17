"use client";

// ============================================================================
// Una póliza — sus fechas, su prima, lo que falta del papeleo y qué se puede hacer con ella
// ============================================================================
// QUÉ PROMETE
//   Que se lea de un vistazo hasta cuándo cubre (con el último día EXCLUSIVO: la
//   póliza deja de cubrir ese día a las 12 M), en qué va la prima, y cuáles de los
//   tres pasos del papeleo (prima pagada, póliza firmada, factura) están hechos.
//   Es la misma tarjeta para una póliza de cualquier seguro: el nombre del seguro va
//   en el título.
//
// QUÉ NO HACE
//   No guarda nada: cada botón avisa a quien la pinta (`onPaso`, `onArchivos`, …) y
//   esa pantalla abre el diálogo que corresponde. Tampoco decide si cubre hoy —lo trae
//   la base en `cubre_hoy`— ni en qué va la prima —eso lo calcula `estadoPrima`.
// ============================================================================

import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { isoADiaMesAnio } from "@/lib/admin/planilla/formato";
import { diasEntre } from "@/lib/bandeja-mia";
import { formatSoles } from "@/lib/rangos";
import { estadoPrima, fechaDelPaso, PASOS_SEGURO, plural, type PasoSeguro, type Poliza } from "@/lib/admin/seguros";

const fecha = isoADiaMesAnio;

function InsigniaPrima({ z, hoy }: { z: Poliza; hoy: string }) {
  const { estado, dias } = estadoPrima(z, hoy);
  switch (estado) {
    case "pagada": return <Insignia variante="positivo" tamano="sm">Pagada el {fecha(z.pagada_el!)}</Insignia>;
    case "sin_fecha": return <Insignia variante="neutral" tamano="sm">Sin pagar · sin fecha de vencimiento</Insignia>;
    case "al_dia": return <Insignia variante="neutral" tamano="sm">Sin pagar · vence el {fecha(z.prima_vence_el!)}</Insignia>;
    case "por_vencer": return <Insignia variante="advertencia" tamano="sm">{dias === 0 ? "Vence hoy" : `Vence en ${plural(dias ?? 0, "día", "días")}`}</Insignia>;
    case "en_mora": return <Insignia variante="alerta" tamano="sm">En mora hace {plural(-(dias ?? 0), "día", "días")}</Insignia>;
    default: return <Insignia variante="alerta" tamano="sm">Cobertura suspendida por mora</Insignia>;
  }
}

/** Un dato que el papel no dice y el corredor aún no confirmó: se marca «sin confirmar», no se inventa. */
function SinConfirmar({ etiqueta, valor }: { etiqueta: string; valor: string | null }) {
  return (
    <span className="mr-4 inline-block">
      <span className="text-taupe">{etiqueta}: </span>
      {valor ? <span className="text-tinta">{valor}</span> : <span className="rounded bg-ambar/15 px-1.5 text-ambar">sin confirmar</span>}
    </span>
  );
}

export function TarjetaPoliza({
  z, hoy, destacada, onPaso, onArchivos, onHistorial, onCorregir, onAnular,
}: {
  z: Poliza;
  hoy: string;
  /** La que habla por la persona (cubre hoy, o la próxima): fondo de papel; las demás, hundido. */
  destacada: boolean;
  onPaso: (z: Poliza, paso: PasoSeguro, quitar: boolean) => void;
  onArchivos: (z: Poliza) => void;
  onHistorial: (z: Poliza) => void;
  onCorregir: (z: Poliza) => void;
  onAnular: (z: Poliza) => void;
}) {
  const dias = diasEntre(z.vigente_desde, z.vigente_hasta);
  const faltan = diasEntre(hoy, z.vigente_hasta);
  return (
    <div className={`rounded-xl border px-4 py-4 ${destacada ? "border-sand bg-papel" : "border-sand bg-hueso"}`}>
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="font-medium text-tinta">
            {z.producto_nombre} <span className="font-normal text-taupe">· póliza</span> <span className="font-mono">{z.numero_poliza}</span>
            <span className="font-normal text-taupe"> · {z.aseguradora}</span>
          </p>
          <p className="mt-0.5 text-sm text-taupe">
            Del {fecha(z.vigente_desde)} al {fecha(z.vigente_hasta)} · {plural(dias, "día", "días")}
            {z.cubre_hoy && <> · deja de cubrir el {fecha(z.vigente_hasta)} a las 12 M ({faltan === 1 ? "falta 1 día" : `faltan ${faltan} días`})</>}
          </p>
        </div>
        <div>
          {z.cubre_hoy ? <Insignia variante="positivo" tamano="sm">Cubre hoy</Insignia>
            : z.vigente_desde > hoy ? <Insignia variante="informativo" tamano="sm">Empieza el {fecha(z.vigente_desde)}</Insignia>
            : <Insignia variante="neutral" tamano="sm">Vencida</Insignia>}
        </div>
      </div>

      <div className="mt-3 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm">
        <span className="text-tinta">{formatSoles(z.prima_total)} <span className="text-taupe">con IGV</span></span>
        <InsigniaPrima z={z} hoy={hoy} />
      </div>

      <p className="mt-3 text-sm leading-relaxed">
        <SinConfirmar etiqueta="Plan" valor={z.plan} />
        <SinConfirmar etiqueta="Beneficio por enfermedad" valor={z.beneficio_enfermedad !== null ? formatSoles(z.beneficio_enfermedad) : null} />
        <SinConfirmar etiqueta="por accidente" valor={z.beneficio_accidente !== null ? formatSoles(z.beneficio_accidente) : null} />
        <SinConfirmar etiqueta="Renueva sola" valor={z.renueva_sola === null ? null : z.renueva_sola ? "sí" : "no"} />
      </p>

      <ul className="mt-3 grid grid-cols-1 gap-2 sm:grid-cols-3">
        {PASOS_SEGURO.map((s) => {
          const hecho = fechaDelPaso(z, s.paso);
          return (
            <li key={s.paso} className={`rounded-lg border px-3 py-2 text-sm ${hecho ? "border-verde/30 bg-verde/10" : "border-sand bg-hueso"}`}>
              <p className="text-tinta">{hecho ? "✓ " : ""}{hecho ? s.hecho : s.falta}</p>
              {hecho && <p className="text-xs text-taupe">el {fecha(hecho)}</p>}
              <div className="mt-1 flex flex-wrap gap-x-3">
                <Boton variante="enlace" aria-label={`${hecho ? "Cambiar la fecha de" : "Marcar como hecho"}: ${s.etiqueta.toLowerCase()} de la póliza ${z.numero_poliza}`} onClick={() => onPaso(z, s.paso, false)}>{hecho ? "Cambiar la fecha" : "Marcar como hecho"}</Boton>
                {hecho && <Boton variante="enlace" aria-label={`Quitar la marca de ${s.etiqueta.toLowerCase()} de la póliza ${z.numero_poliza}`} onClick={() => onPaso(z, s.paso, true)}>Quitar la marca</Boton>}
              </div>
            </li>
          );
        })}
      </ul>

      {z.nota && <p className="mt-3 text-sm text-taupe">{z.nota}</p>}

      <div className="mt-3 flex flex-wrap items-center gap-2">
        <Boton variante="primario" tamano="sm" onClick={() => onArchivos(z)}>
          {z.archivos === 0 ? "Adjuntar PDF" : `Archivos (${z.archivos})`}
        </Boton>
        <Boton tamano="sm" onClick={() => onHistorial(z)}>Historial</Boton>
        <Boton tamano="sm" onClick={() => onCorregir(z)}>Corregir datos</Boton>
        <Boton variante="sutil" tamano="sm" onClick={() => onAnular(z)}>Anular</Boton>
      </div>
    </div>
  );
}

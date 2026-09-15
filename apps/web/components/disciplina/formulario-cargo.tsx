"use client";

// El formulario para archivar un papel contra un documento disciplinario: el
// cargo firmado, el acta de la negativa o el descargo.
//
// Vivía dentro de `admin/disciplina/page.tsx` y se abría en línea, debajo de
// la fila. Desde el rediseño del 2026-09-15 se abre en un Modal —con los
// botones en el pie del Modal, que es donde los pone el resto del panel—, así
// que acá quedan solo los campos.
//
// `pideFecha` es la diferencia real entre los casos: cuando esta subida es la
// que marca la entrega, la fecha importa (desde ahí corren los plazos); en un
// documento ya entregado la fecha buena es la registrada y la base no la pisa.
// `fechaMax` existe por la persona cesada: una entrega registrada después del
// cese solo puede ser de un día en que todavía estaba (decisión 2026-09-15).

import { Campo } from "@/components/ui/campo";
import { hoyLima } from "@cayla-dynamic/shared";
import type { TipoPapel } from "@/lib/admin/disciplina";

export const TIPOS_CARGO = "image/jpeg,image/png,image/heic,image/webp,application/pdf";
export const MAX_BYTES_CARGO = 50 * 1024 * 1024;

export const TITULO_PAPEL: Record<TipoPapel, string> = {
  cargo_firmado: "Subir el cargo firmado",
  acta_negativa: "Registrar la negativa a firmar",
  descargo: "Subir su descargo",
};

export function FormularioCargo({
  tipo, pideFecha, entregadoEl, fecha, fechaMax, nota, testigo, progreso,
  alElegirArchivo, alCambiarFecha, alCambiarNota, alCambiarTestigo,
}: {
  tipo: TipoPapel;
  pideFecha: boolean;
  entregadoEl: string | null;
  fecha: string;
  fechaMax?: string;
  nota: string;
  testigo: string;
  progreso: number | null;
  alElegirArchivo: (f: File | null) => void;
  alCambiarFecha: (v: string) => void;
  alCambiarNota: (v: string) => void;
  alCambiarTestigo: (v: string) => void;
}) {
  const esActa = tipo === "acta_negativa";
  return (
    <div className="grid gap-3">
      <p className="text-sm text-taupe">
        {esActa
          ? pideFecha
            ? "El acta suscrita por quien entrega y por un testigo produce los mismos efectos que el cargo firmado (num. 55.4 del RIT). Al guardarla, el documento queda ENTREGADO con esta fecha y desde ahí corren los plazos."
            : "Sube el acta para archivarla en el legajo. La entrega ya registrada no cambia."
          : tipo === "descargo"
            ? "Sube el descargo que presentó por escrito. Se archiva en el legajo junto al documento que lo provocó; no cambia su estado."
            : pideFecha
              ? "Al subir el cargo, el documento queda entregado con esta fecha. Desde ahí corren los plazos de descargo (art. 31)."
              : `Sube el cargo para archivarlo en el legajo. No cambia la entrega ya registrada${entregadoEl ? ` (${entregadoEl})` : ""}.`}
      </p>
      <label htmlFor="papel-archivo" className="grid gap-1 text-sm">
        {esActa ? "Acta de la negativa" : tipo === "descargo" ? "Descargo presentado" : "Cargo firmado"}
        <input id="papel-archivo" type="file" accept={TIPOS_CARGO}
          onChange={(e) => alElegirArchivo(e.target.files?.[0] ?? null)}
          className="rounded-control border border-sand bg-crema px-2 py-1.5 text-xs file:mr-2 file:rounded file:border-0 file:bg-sand file:px-2 file:py-0.5 file:text-xs" />
      </label>
      {pideFecha && (
        <Campo etiqueta="Fecha de entrega" type="date" value={fecha} max={fechaMax ?? hoyLima()}
          onChange={(e) => alCambiarFecha(e.target.value)} />
      )}
      {esActa && (
        <div className="grid gap-1">
          <Campo etiqueta="Testigo del acta — nombre y apellido" value={testigo}
            onChange={(e) => alCambiarTestigo(e.target.value)}
            placeholder="ej. Rosa Quispe Ramírez" />
          <span className="text-xs text-taupe">
            Quien presenció la negativa y firma el acta junto a quien entrega. Puede ser cualquier
            persona presente, esté o no en el sistema.
          </span>
        </div>
      )}
      <Campo
        etiqueta={esActa ? "Qué pasó (obligatorio)" : "Nota (opcional)"}
        value={nota} onChange={(e) => alCambiarNota(e.target.value)}
        placeholder={esActa ? "ej. se le leyó en voz alta y se negó a firmar y a recibir la copia" : tipo === "descargo" ? "ej. entregado en mesa de partes el 14/08" : "ej. recibido en la tienda"} />
      {progreso !== null && (
        <div>
          <div className="h-1.5 w-full overflow-hidden rounded-full bg-sand">
            <div className="h-full bg-tinta transition-[width] duration-200" style={{ width: `${progreso}%` }}
              role="progressbar" aria-valuenow={progreso} aria-valuemin={0} aria-valuemax={100} aria-label="Subiendo el archivo" />
          </div>
          <span className="text-xs text-taupe">Subiendo — {progreso}%</span>
        </div>
      )}
    </div>
  );
}

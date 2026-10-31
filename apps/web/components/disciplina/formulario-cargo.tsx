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
//
// `nivel` llegó con la 0569 por un texto que era FALSO en el caso que más
// cuesta: este formulario afirmaba que el acta de negativa «produce los mismos
// efectos que el cargo firmado (num. 55.4)» también en una imputación o en una
// carta de despido, donde el art. 57.8 dice lo contrario con esas palabras —«el
// acta interna de negativa a firmar no sustituye esta vía»—. Felipe decidió el
// 2026-10-29 avisar y no bloquear, así que el aviso tiene que llegar ANTES del
// clic: el que la base escribe en el expediente llega después, y para entonces
// la entrega ya está registrada.
// `fechaMax` existe por la persona cesada: una entrega registrada después del
// cese solo puede ser de un día en que todavía estaba (decisión 2026-09-15).

import { BannerAviso } from "@/components/ui/banner-aviso";
import { Campo } from "@/components/ui/campo";
import { hoyLima } from "@cayla-dynamic/shared";
import { exigeNotificacionReforzada, type TipoPapel } from "@/lib/admin/disciplina";

export const TIPOS_CARGO = "image/jpeg,image/png,image/heic,image/webp,application/pdf";
export const MAX_BYTES_CARGO = 50 * 1024 * 1024;

export const TITULO_PAPEL: Record<TipoPapel, string> = {
  cargo_firmado: "Subir el cargo firmado",
  acta_negativa: "Registrar la negativa a firmar",
  descargo: "Subir su descargo",
};

export function FormularioCargo({
  tipo, nivel, pideFecha, entregadoEl, fecha, fechaMax, nota, testigo, progreso,
  alElegirArchivo, alCambiarFecha, alCambiarNota, alCambiarTestigo,
}: {
  tipo: TipoPapel;
  /** El nivel del documento al que se le archiva este papel. */
  nivel: string | null;
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
  // El num. 55.4 equipara el acta al cargo firmado, pero el art. 57.8 lo
  // exceptúa justo para estos dos niveles. Decir las dos cosas a la vez sería
  // decir una falsa.
  const actaNoBasta = esActa && exigeNotificacionReforzada(nivel ?? "");
  return (
    <div className="grid gap-3">
      {actaNoBasta && (
        <BannerAviso titulo="Esta acta no reemplaza la notificación" variante="alerta">
          En una carta de imputación o de despido, el acta interna de negativa a firmar
          <strong> no sustituye</strong> la notificación por notario, por juez de paz o, a falta
          de ambos, por la Policía Nacional del Perú (art. 57.8 del RIT, art. 32 de la LPCL).
          Puedes registrarla igual —la entrega queda hecha y el plazo de descargo empieza a
          correr—, y el documento quedará diciendo en su expediente que falta esa notificación.
          Mientras no conste, la entrega se puede discutir, y un despido mal notificado se paga
          como despido arbitrario aunque la falta esté probada.
        </BannerAviso>
      )}
      <p className="text-sm text-taupe">
        {esActa
          ? pideFecha
            ? actaNoBasta
              ? "El acta la suscriben quien entrega y un testigo. Al guardarla, el documento queda ENTREGADO con esta fecha y desde ahí corren los plazos — pero lee el aviso de arriba antes de guardar."
              : "El acta suscrita por quien entrega y por un testigo produce los mismos efectos que el cargo firmado (num. 55.4 del RIT). Al guardarla, el documento queda ENTREGADO con esta fecha y desde ahí corren los plazos."
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

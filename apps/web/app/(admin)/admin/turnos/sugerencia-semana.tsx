"use client";

// ============================================================================
// PropuestaDeLaSemana — el aviso de una propuesta sin guardar (Turnos · Integrada)
// ============================================================================
// Mientras hay una propuesta, la grilla de la Integrada la dibuja en lugar de
// lo guardado; esto dice que NO está guardada, qué cambia, qué avisa el motor
// y cómo publicarla o descartarla. La propuesta sale de
// lib/admin/sugerencia-turnos.ts; publicar es fn_publicar_semana (0586).
// ============================================================================

import Link from "next/link";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Boton } from "@/components/ui/boton";
import { Cifra } from "@/components/ui/cifra";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import type { Propuesta } from "@/lib/admin/sugerencia-turnos";

const coma = (n: number) => String(Math.round(n * 100) / 100).replace(".", ",");

export function PropuestaDeLaSemana({
  propuesta,
  nombres,
  semana,
  cambios,
  publicando,
  notas,
  porAprobar,
  onPublicar,
  onDescartar,
  onGuardarBorrador,
  guardando = false,
  hayBorrador = false,
}: {
  propuesta: Propuesta;
  nombres: Map<string, string>;
  /** «del 9 al 15 de noviembre». */
  semana: string;
  /** Cuántos días-persona cambian respecto de lo guardado. */
  cambios: number;
  publicando: boolean;
  /** Lo que se dice aparte del motor: la venta que no se leyó, el turno propio que no va… */
  notas: string[];
  /** Disponibilidades que esperan a la líder; null si no se pudo saber. */
  porAprobar: number | null;
  onPublicar: () => void;
  onDescartar: () => void;
  /** Guardarla como borrador de la semana (0593), sin publicar; undefined si la 0593 no está. */
  onGuardarBorrador?: () => void;
  guardando?: boolean;
  /** Ya hay un borrador de esta semana: guardar lo reemplaza. */
  hayBorrador?: boolean;
}) {
  const filas = Object.entries(propuesta.resumen).sort((a, b) => (nombres.get(a[0]) ?? "").localeCompare(nombres.get(b[0]) ?? "", "es"));
  const horasCortas = Object.values(propuesta.cobertura).flat().filter((c) => c.enPiso < c.pedia).length;
  return (
    <TarjetaInfo className="space-y-3" titulo={`Propuesta para la semana ${semana}`}>
      <p className="text-sm text-taupe">
        Todavía <strong className="text-tinta">no está guardada</strong>: la grilla de abajo muestra la propuesta. Revísala y
        publícala, o guárdala como borrador para volver a ella; publicar guarda los turnos de esa semana de una sola vez. Respeta la disponibilidad aprobada, las ausencias y
        los horarios fijos, y nadie pasa de su jornada.
      </p>
      <div className="grid gap-3 sm:grid-cols-3">
        <Cifra etiqueta="Días que cambian" valor={String(cambios)} />
        <Cifra etiqueta="Horas con gente corta" valor={String(horasCortas)} tono={horasCortas > 0 ? "advertencia" : "positivo"}
          detalle={horasCortas > 0 ? "con la gente que hay no alcanza" : "la venta queda cubierta"} />
        <Cifra etiqueta="Disponibilidad por aprobar" valor={porAprobar === null ? "—" : String(porAprobar)}
          detalle={porAprobar ? "no entra en la propuesta hasta que la apruebes" : undefined} />
      </div>
      {(propuesta.avisos.length > 0 || notas.length > 0) && (
        <BannerAviso variante="advertencia" titulo="Lo que conviene mirar antes de publicar">
          <ul className="list-disc space-y-0.5 pl-4">
            {[...notas, ...propuesta.avisos].map((a) => <li key={a}>{a}</li>)}
          </ul>
        </BannerAviso>
      )}
      <details className="text-sm">
        <summary className="cursor-pointer text-taupe">Horas de cada persona</summary>
        <ul className="mt-2 grid gap-1 sm:grid-cols-2 lg:grid-cols-3">
          {filas.map(([id, r]) => (
            <li key={id} className="flex justify-between gap-2 border-b border-sand py-1 text-xs">
              <span>{nombres.get(id) ?? "—"}</span>
              <span className={Math.abs(r.horas - r.objetivo) > 0.25 ? "text-ambar" : "text-taupe"}>
                {coma(r.horas)} h de {coma(r.objetivo)} h · {r.dias} días
              </span>
            </li>
          ))}
        </ul>
      </details>
      <div className="flex flex-wrap items-center gap-2">
        <Boton variante="primario" disabled={publicando || cambios === 0} onClick={onPublicar}>
          {publicando ? "Publicando…" : cambios === 0 ? "No hay cambios que publicar" : `Publicar la semana (${cambios} ${cambios === 1 ? "día" : "días"})`}
        </Boton>
        {onGuardarBorrador && (
          <Boton variante="secundario" disabled={publicando || guardando} onClick={onGuardarBorrador}
            title={hayBorrador ? "Reemplaza el borrador guardado de esta semana" : "Guárdala sin publicar: la ves, la comparas y la publicas después"}>
            {guardando ? "Guardando…" : hayBorrador ? "Reemplazar el borrador" : "Guardar como borrador"}
          </Boton>
        )}
        <Boton variante="secundario" disabled={publicando} onClick={onDescartar}>Descartar</Boton>
        <Link href="/admin/disponibilidad" className="text-sm text-taupe underline-offset-2 hover:underline">Ver la disponibilidad del equipo</Link>
      </div>
    </TarjetaInfo>
  );
}

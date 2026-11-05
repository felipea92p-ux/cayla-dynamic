"use client";

// ============================================================================
// BorradorDeLaSemana — el borrador guardado de una semana (Turnos · Integrada, 0593)
// ============================================================================
// Dice que hay un borrador guardado, quién lo dejó y cuándo, y lo compara con
// lo que hoy tiene cada persona (y con la sugerencia, si hay una a la vista):
// horas, días que cambian y si cumple su jornada. Las notas de quien es RxH
// viven aquí —no llevan turno ni se publican—. Publicar es
// fn_turnos_borrador_publicar; la comparación sale de lib/admin/borrador-semana.ts.
// ============================================================================

import { useState } from "react";
import { AreaTexto } from "@/components/ui/area-texto";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Boton } from "@/components/ui/boton";
import { Cifra } from "@/components/ui/cifra";
import { Insignia } from "@/components/ui/insignia";
import { Fila, Tabla, TablaEncabezado, Th } from "@/components/ui/tabla";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { textoCumple, type Cumple } from "@/lib/admin/borrador-semana";

const coma = (n: number) => String(Math.round(n * 100) / 100).replace(".", ",");

export interface FilaComparativa {
  id: string;
  nombre: string;
  ahora: { horas: number; dias: number };
  /** Lo de la sugerencia a la vista; null si no hay sugerencia o no trae a esta persona. */
  sugerido: { horas: number; dias: number } | null;
  borrador: { horas: number; dias: number };
  cambian: number;
  cumple: Cumple;
}

/** La insignia del «cumple»: verde si cumple, ámbar si no, y aparte lo que pasa de 48 h o tiene un día corto. */
export function InsigniaCumple({ cumple }: { cumple: Cumple }) {
  return (
    <span className="flex flex-wrap items-center gap-1">
      <Insignia tamano="sm" variante={cumple.estado === "cumple" ? "positivo" : cumple.estado === "sin_jornada" ? "neutral" : "advertencia"}>
        {textoCumple(cumple)}
      </Insignia>
      {cumple.pasa48 && <Insignia tamano="sm" variante="alerta">pasa de 48 h</Insignia>}
      {cumple.diasCortos.length > 0 && (
        <Insignia tamano="sm" variante="advertencia">
          {cumple.diasCortos.length === 1 ? "un día" : `${cumple.diasCortos.length} días`} de menos de 4 h
        </Insignia>
      )}
    </span>
  );
}

const horasYDias = (x: { horas: number; dias: number }) => `${coma(x.horas)} h · ${x.dias} ${x.dias === 1 ? "día" : "días"}`;

export function BorradorDeLaSemana({
  semana,
  guardado,
  filas,
  notas,
  porPublicar,
  yaLlegaron,
  noVa,
  viendo,
  publicando,
  guardando,
  onVer,
  onPublicar,
  onDescartar,
  onGuardarNotas,
}: {
  /** «del 9 al 15 de noviembre». */
  semana: string;
  /** «por Rosa, el 3 nov a las 18:40». */
  guardado: string;
  filas: FilaComparativa[];
  /** Quien es RxH (o ya tiene nota): su nota de la semana. */
  notas: { id: string; nombre: string; nota: string }[];
  /** Días-persona que cambian respecto de lo publicado y todavía no llegan. */
  porPublicar: number;
  /** Días que cambian pero ya llegaron: no se pueden publicar. */
  yaLlegaron: number;
  /** El turno propio de la líder que no va (lo dice filasParaPublicar). */
  noVa: string | null;
  viendo: boolean;
  publicando: boolean;
  guardando: boolean;
  onVer: () => void;
  onPublicar: () => void;
  onDescartar: () => void;
  onGuardarNotas: (notas: Map<string, string>) => void;
}) {
  // Las notas arrancan en lo guardado. Si el borrador se vuelve a guardar, quien llama cambia la `key` y esto arranca de nuevo.
  const [texto, setTexto] = useState<Map<string, string>>(() => new Map(notas.map((n) => [n.id, n.nota])));
  const notasCambiaron = notas.some((n) => (texto.get(n.id) ?? "").trim() !== n.nota.trim());
  const hayAvisos = filas.some((f) => f.cumple.pasa48 || f.cumple.diasCortos.length > 0);
  const noCumplen = filas.filter((f) => f.cumple.estado === "faltan" || f.cumple.estado === "sobra").length;
  const haySugerido = filas.some((f) => f.sugerido !== null);

  return (
    <TarjetaInfo className="space-y-3" titulo={`Borrador de la semana ${semana}`}>
      <p className="text-sm text-taupe">
        Guardado {guardado}. <strong className="text-tinta">Todavía no está publicado</strong>: el equipo sigue viendo sus turnos de
        siempre hasta que lo publiques. Lo ven solo la líder de equipo de la sede, DO y administración.
      </p>
      <div className="grid gap-3 sm:grid-cols-3">
        <Cifra etiqueta="Días que cambian" valor={String(porPublicar)}
          detalle={yaLlegaron > 0 ? `y ${yaLlegaron} que ya llegaron: esos no se publican` : undefined} />
        <Cifra etiqueta="No cumplen su jornada" valor={String(noCumplen)} tono={noCumplen > 0 ? "advertencia" : "positivo"}
          detalle={noCumplen > 0 ? "les faltan o les sobran horas" : "todas suman sus horas"} />
        <Cifra etiqueta="Personas en el borrador" valor={String(filas.length)} />
      </div>
      {(hayAvisos || noVa) && (
        <BannerAviso variante="advertencia" titulo="Lo que conviene mirar antes de publicar">
          <ul className="list-disc space-y-0.5 pl-4">
            {noVa && <li>{noVa}</li>}
            {filas.filter((f) => f.cumple.pasa48).map((f) => <li key={`48-${f.id}`}>{f.nombre} pasa de 48 h, el máximo legal de la semana.</li>)}
            {filas.filter((f) => f.cumple.diasCortos.length > 0).map((f) => (
              <li key={`4-${f.id}`}>{f.nombre} tiene un día de menos de 4 h: por debajo de 4 h diarias la jornada se considera a tiempo parcial.</li>
            ))}
          </ul>
        </BannerAviso>
      )}
      <Tabla>
        <TablaEncabezado>
          <Th>Persona</Th>
          <Th>Ahora</Th>
          {haySugerido && <Th>Sugerido</Th>}
          <Th>Borrador</Th>
          <Th>Cambian</Th>
          <Th>Su jornada</Th>
        </TablaEncabezado>
        <tbody>
          {filas.map((f) => (
            <Fila key={f.id}>
              <td className="px-4 py-2">{f.nombre}</td>
              <td className="px-4 py-2 text-taupe">{horasYDias(f.ahora)}</td>
              {haySugerido && <td className="px-4 py-2 text-taupe">{f.sugerido ? horasYDias(f.sugerido) : "—"}</td>}
              <td className="px-4 py-2">{horasYDias(f.borrador)}</td>
              <td className="px-4 py-2 text-taupe">{f.cambian === 0 ? "nada" : `${f.cambian} ${f.cambian === 1 ? "día" : "días"}`}</td>
              <td className="px-4 py-2"><InsigniaCumple cumple={f.cumple} /></td>
            </Fila>
          ))}
        </tbody>
      </Tabla>
      {notas.length > 0 && (
        <div className="space-y-2">
          <p className="text-sm text-taupe">
            Notas de la semana. Para quien factura por recibo por honorarios no se arma horario: aquí se anota cuándo se la
            necesita. No se publica y la persona no la ve.
          </p>
          <div className="grid gap-3 sm:grid-cols-2">
            {notas.map((n) => (
              <AreaTexto key={n.id} etiqueta={n.nombre} rows={2} maxLength={300}
                value={texto.get(n.id) ?? ""}
                placeholder={`Cuándo se necesita a ${n.nombre.split(" ")[0]} esta semana`}
                onChange={(e) => { const v = e.target.value; setTexto((m) => new Map(m).set(n.id, v)); }} />
            ))}
          </div>
          {notasCambiaron && (
            <Boton variante="secundario" tamano="sm" disabled={guardando} onClick={() => onGuardarNotas(texto)}>
              {guardando ? "Guardando…" : "Guardar las notas"}
            </Boton>
          )}
        </div>
      )}
      <div className="flex flex-wrap items-center gap-2">
        <Boton variante="primario" disabled={publicando || porPublicar === 0} onClick={onPublicar}>
          {publicando ? "Publicando…" : porPublicar === 0 ? "No hay cambios que publicar" : `Publicar el borrador (${porPublicar} ${porPublicar === 1 ? "día" : "días"})`}
        </Boton>
        <Boton variante="secundario" onClick={onVer}>{viendo ? "Ver lo publicado en la grilla" : "Ver el borrador en la grilla"}</Boton>
        <Boton variante="secundario" disabled={publicando} onClick={onDescartar}>Descartar el borrador</Boton>
      </div>
    </TarjetaInfo>
  );
}

"use client";

// «Frente al periodo anterior» — sale de `fn_planilla_variacion` (0319).
//
// Decisión del 2026-09-15: con el periodo EN CURSO no se comparan montos. El
// día 18 de 30 la pantalla decía en rojo «34 personas con algo que mirar» y
// «−S/ 9,209», y casi todo era que el mes no había terminado: se comparaba
// medio periodo contra uno completo. Mientras corre solo se dice lo que ya es
// cierto a mitad de mes —quién entró y quién salió—; los montos, cuando termina.
//
// No se inventa ninguna normalización (por día, por hora): la función no la
// da, y una cifra «ajustada» que nadie puede reconstruir es peor que ninguna.

import { useState } from "react";
import { formatSoles } from "@/lib/rangos";
import { Boton } from "@/components/ui/boton";
import { CampoCasilla } from "@/components/ui/campo";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { fechaCorta } from "@/lib/admin/planilla/formato";
import type { Avance } from "@/lib/admin/planilla/revision";
import type { AvisoVariacion, ExplicaVariacion, FilaVariacion, Variacion } from "@/lib/admin/planilla/tipos";

// Su fuente de verdad es la migración 0319; si aparece un aviso nuevo, se agrega ahí y aquí.
const AVISO_LABEL: Record<AvisoVariacion, string> = {
  salio: "Ya no aparece",
  entro: "No estaba el periodo anterior",
  cobra_cero: "Cobra S/ 0",
  empieza_a_cobrar: "Empieza a cobrar",
  trabajo_y_no_cobra: "Trabajó y no cobra",
  salto: "Salto",
  cobra_igual_trabajo_menos: "Cobra igual, trabajó menos",
};

const EXPLICA_LABEL: Record<ExplicaVariacion, string> = {
  ceso: "cesó",
  ingreso: "ingresó",
  sueldo_cambio: "le cambió el sueldo",
  mas_ausencias: "más ausencias",
  menos_ausencias: "menos ausencias",
};

/** Los avisos que ya significan algo a mitad de periodo. Los demás dependen de montos que aún se mueven. */
const AVISOS_EN_CURSO: AvisoVariacion[] = ["entro", "salio"];

function TablaDetalle({ filas, soloEstructura }: { filas: FilaVariacion[]; soloEstructura: boolean }) {
  return (
    <div className="mt-3 overflow-x-auto">
      <table className="w-full min-w-[40rem] text-sm">
        <thead>
          <tr className="bg-sand/60 text-left text-xs text-taupe">
            <th className="px-3 py-2 font-normal">Persona</th>
            {!soloEstructura && (
              <>
                <th className="px-3 py-2 text-right font-normal">Anterior</th>
                <th className="px-3 py-2 text-right font-normal">Actual</th>
                <th className="px-3 py-2 text-right font-normal">Diferencia</th>
                <th className="px-3 py-2 text-right font-normal" title="Horas marcadas. Las ausencias pagadas no marcan: una caída a cero puede ser normal.">Horas</th>
              </>
            )}
            <th className="px-3 py-2 font-normal">Qué pasa</th>
          </tr>
        </thead>
        <tbody>
          {filas.map((f) => {
            const avisos = soloEstructura ? f.avisos.filter((a) => AVISOS_EN_CURSO.includes(a)) : f.avisos;
            return (
              <tr key={f.persona_id} className="border-b border-sand/60 align-top">
                <td className="px-3 py-2">
                  <span className="font-medium">{f.nombre}</span>
                  {f.sede && <span className="ml-1.5 text-xs text-taupe">{f.sede}</span>}
                </td>
                {!soloEstructura && (
                  <>
                    <td className="px-3 py-2 text-right tabular-nums text-taupe">{formatSoles(f.total_previo)}</td>
                    <td className="px-3 py-2 text-right tabular-nums">{formatSoles(f.total_actual)}</td>
                    <td className="px-3 py-2 text-right font-medium tabular-nums">
                      {f.delta > 0 ? "+" : ""}{formatSoles(f.delta)}
                      {f.delta_pct !== null && (
                        <span className="ml-1 text-xs font-normal text-taupe">({f.delta_pct > 0 ? "+" : ""}{f.delta_pct}%)</span>
                      )}
                    </td>
                    <td className="px-3 py-2 text-right text-xs tabular-nums text-taupe">
                      {f.horas_previo.toFixed(0)} → {f.horas_actual.toFixed(0)}
                    </td>
                  </>
                )}
                <td className="px-3 py-2">
                  <div className="flex flex-wrap items-center gap-1.5">
                    {avisos.map((a) => (
                      <span key={a} className="rounded-pildora bg-ambar/15 px-2 py-0.5 text-xs text-ambar">
                        {AVISO_LABEL[a] ?? a}
                      </span>
                    ))}
                    {/* La explicación no es un aviso: va en gris, al lado, para descartar el susto sin cambiar de pantalla. */}
                    {f.explica.length > 0 && (
                      <span className="text-xs text-taupe">{f.explica.map((e) => EXPLICA_LABEL[e] ?? e).join(" · ")}</span>
                    )}
                  </div>
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

export function QueCambio({ variacion, avance, fechaFin }: {
  variacion: Variacion | null;
  avance: Avance;
  fechaFin: string;
}) {
  const [detalle, setDetalle] = useState(false);
  const [todas, setTodas] = useState(false);
  if (!variacion || variacion.sin_previo) return null;

  const contra = `${fechaCorta(variacion.previo_desde!)} – ${fechaCorta(variacion.previo_hasta!)}`;
  const previoAbierto = variacion.previo_fuente !== "foto";

  if (avance.estado !== "terminado") {
    const estructura = variacion.filas.filter((f) => f.avisos.some((a) => AVISOS_EN_CURSO.includes(a)));
    const entraron = variacion.filas.filter((f) => f.avisos.includes("entro")).length;
    const salieron = variacion.filas.filter((f) => f.avisos.includes("salio")).length;
    return (
      <TarjetaInfo
        titulo="Frente al periodo anterior"
        accion={estructura.length > 0 ? (
          <Boton variante="enlace" className="text-sm text-taupe" onClick={() => setDetalle((v) => !v)}>
            {detalle ? "Ocultar" : "Ver quiénes →"}
          </Boton>
        ) : undefined}
      >
        <p className="text-sm text-taupe">
          {avance.estado === "en_curso"
            ? `Periodo en curso: día ${avance.transcurridos} de ${avance.dias}.`
            : "El periodo todavía no empieza."}{" "}
          Los montos se comparan con el periodo {contra} cuando este termine ({fechaCorta(fechaFin)}): hoy
          compararían medio periodo contra uno completo.
        </p>
        <p className="mt-2 text-sm">
          {entraron + salieron === 0
            ? "Mismas personas que el periodo anterior."
            : [
                entraron > 0 && `${entraron} ${entraron === 1 ? "persona no estaba" : "personas no estaban"} el periodo anterior`,
                salieron > 0 && `${salieron} ya no ${salieron === 1 ? "aparece" : "aparecen"}`,
              ].filter(Boolean).join(" · ") + "."}
        </p>
        {detalle && <TablaDetalle filas={estructura} soloEstructura />}
      </TarjetaInfo>
    );
  }

  const conAviso = variacion.filas.filter((f) => f.avisos.length > 0);
  const visibles = todas ? variacion.filas : conAviso;
  const r = variacion.resumen;
  const delta = r.total_delta ?? 0;
  return (
    <TarjetaInfo
      titulo="Frente al periodo anterior"
      accion={
        <Boton variante="enlace" className="text-sm text-taupe" onClick={() => setDetalle((v) => !v)}>
          {detalle ? "Ocultar detalle" : "Ver detalle →"}
        </Boton>
      }
    >
      <p className="text-xs text-taupe">
        Contra {contra}
        {previoAbierto ? " · ese periodo sigue abierto: su cifra todavía se puede mover" : " · ya pagado: se compara con lo que se pagó"}
      </p>
      <dl className="mt-3 grid grid-cols-3 gap-3 text-sm">
        <div>
          <dt className="text-xs text-taupe">Actual</dt>
          <dd className="font-medium tabular-nums">{formatSoles(r.total_actual ?? 0)}</dd>
          <dd className="text-xs text-taupe">{r.personas_actual} personas</dd>
        </div>
        <div>
          <dt className="text-xs text-taupe">Anterior</dt>
          <dd className="tabular-nums text-taupe">{formatSoles(r.total_previo ?? 0)}</dd>
          <dd className="text-xs text-taupe">{r.personas_previo} personas</dd>
        </div>
        <div>
          <dt className="text-xs text-taupe">Diferencia</dt>
          <dd className="font-medium tabular-nums">{delta > 0 ? "+" : ""}{formatSoles(delta)}</dd>
        </div>
      </dl>
      {variacion.periodos_de_distinto_largo && (
        <p className="mt-3 rounded-control bg-ambar/15 px-3 py-2 text-xs text-ambar">
          Los dos periodos no duran lo mismo ({variacion.periodo_dias} días contra {variacion.previo_dias}): parte de la
          diferencia es el calendario, no un cambio real.
        </p>
      )}
      <p className="mt-3 text-sm">
        {conAviso.length === 0
          ? "Nadie levanta un aviso frente al periodo anterior."
          : <span className="text-ambar">{conAviso.length === 1 ? "1 persona con algo que mirar" : `${conAviso.length} personas con algo que mirar`}.</span>}
      </p>
      {detalle && (
        <>
          {visibles.length > 0 ? <TablaDetalle filas={visibles} soloEstructura={false} /> : (
            <p className="mt-3 text-sm text-taupe">Nadie levantó un aviso.</p>
          )}
          <div className="mt-3">
            <CampoCasilla
              etiqueta="Mostrar también a quien no levantó ningún aviso"
              checked={todas}
              onChange={(e) => setTodas(e.target.checked)}
            />
          </div>
          <p className="mt-2 text-xs text-taupe">
            Esto no bloquea ni corrige nada. Un aviso con una explicación al lado casi siempre está bien; el que hay que
            mirar es el que aparece solo.
          </p>
        </>
      )}
    </TarjetaInfo>
  );
}

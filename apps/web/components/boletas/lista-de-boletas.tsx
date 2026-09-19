"use client";

import { Boton } from "@/components/ui/boton";
import { Tabla, TablaEncabezado, Th, Fila } from "@/components/ui/tabla";
import { InsigniaDeEstado } from "@/components/boletas/insignia-de-estado";
import { TACTIL } from "@/components/boletas/pie-de-modal";
import { estadoVisible } from "@/lib/boletas";
import { accionesDeFila, fechaHoraLima, resumenDelDocumento, type FilaTablero } from "@/lib/admin/boletas-pantalla";

export type AccionDeBoleta = "subir" | "papel" | "ver" | "editar" | "historial" | "anular";

/**
 * LAS PERSONAS DE UN PERIODO Y LO QUE DO PUEDE HACER CON CADA UNA.
 *
 * En computadora es una tabla; en celular cada persona es una TARJETA apilada
 * con sus datos etiquetados y botones grandes: una tabla de cinco columnas no
 * cabe en 375 px y un scroll horizontal esconde justo la columna de acciones.
 * Las dos vistas se dibujan a la vez y el CSS muestra una (`md:`), así que
 * comparten la MISMA lista de acciones (`accionesDeFila`): «qué puede hacer DO
 * con esta boleta» tiene una sola respuesta.
 */

function Acciones({ fila, grande, onAccion }: { fila: FilaTablero; grande: boolean; onAccion: (a: AccionDeBoleta, f: FilaTablero) => void }) {
  const a = accionesDeFila(fila);
  const ancho = grande ? `flex-1 ${TACTIL}` : "";
  const tamano = grande ? "md" : "sm";
  const hay = a.subir || a.papel || a.ver || a.editar || a.historial || a.anular;
  if (!hay) return <span className="text-xs text-taupe">{estadoVisible(fila) === "sin_pago" ? "Nada que subir todavía" : "—"}</span>;
  return (
    <div className="flex flex-wrap gap-2">
      {a.subir && <Boton variante="primario" tamano={tamano} className={ancho} onClick={() => onAccion("subir", fila)}>Subir boleta</Boton>}
      {a.papel && <Boton variante="primario" tamano={tamano} className={ancho} onClick={() => onAccion("papel", fila)}>Marcar entregada en papel</Boton>}
      {a.ver && <Boton tamano={tamano} className={ancho} onClick={() => onAccion("ver", fila)}>Ver</Boton>}
      {a.editar && <Boton tamano={tamano} className={ancho} onClick={() => onAccion("editar", fila)}>Editar</Boton>}
      {a.historial && <Boton variante="sutil" tamano={tamano} className={ancho} onClick={() => onAccion("historial", fila)}>Historial</Boton>}
      {a.anular && <Boton variante="peligro" tamano={tamano} className={ancho} onClick={() => onAccion("anular", fila)}>Anular</Boton>}
    </div>
  );
}

/** «Vista 13 sept, 14:35» / «Sin abrir», para una boleta publicada; vacío si no aplica. */
function seguimiento(f: FilaTablero): { publicada: string; vista: string; confirmada: string } | null {
  if (f.estado === "publicada") {
    return {
      publicada: fechaHoraLima(f.publicada_at),
      vista: f.vista_at ? fechaHoraLima(f.vista_at) : "Sin abrir",
      confirmada: f.recibida_at ? fechaHoraLima(f.recibida_at) : "Sin confirmar",
    };
  }
  return null;
}

function Persona({ f }: { f: FilaTablero }) {
  return (
    <>
      <p className="break-words font-medium text-tinta">{f.nombre}</p>
      <p className="break-words text-xs text-taupe">
        {f.sede_codigo}{f.cargo ? ` · ${f.cargo}` : ""}
        {!f.tiene_cuenta && " · sin cuenta: se le entrega en papel"}
      </p>
    </>
  );
}

function Dato({ etiqueta, children }: { etiqueta: string; children: React.ReactNode }) {
  return (
    <div className="flex items-baseline justify-between gap-3 border-t border-sand py-2 text-sm">
      <dt className="shrink-0 text-xs text-taupe">{etiqueta}</dt>
      <dd className="min-w-0 break-words text-right text-tinta">{children}</dd>
    </div>
  );
}

export function ListaDeBoletas({ filas, onAccion }: { filas: readonly FilaTablero[]; onAccion: (a: AccionDeBoleta, f: FilaTablero) => void }) {
  return (
    <>
      {/* Computadora */}
      <div className="hidden md:block">
        <Tabla>
          <TablaEncabezado>
            <Th>Persona</Th>
            <Th>Estado</Th>
            <Th>Documento</Th>
            <Th>Publicada · vista · confirmada</Th>
            <Th>Acciones</Th>
          </TablaEncabezado>
          <tbody>
            {filas.map((f) => {
              const s = seguimiento(f);
              const resumen = resumenDelDocumento(f);
              return (
                <Fila key={f.persona_id} className="align-top">
                  <td className="px-4 py-3"><Persona f={f} /></td>
                  <td className="px-4 py-3">
                    <InsigniaDeEstado estado={estadoVisible(f)} />
                    {f.actualizada && f.estado === "publicada" && <p className="mt-1 text-xs text-taupe">Actualizada</p>}
                  </td>
                  <td className="px-4 py-3 text-tinta">
                    {resumen ? <>{resumen}<br /><span className="text-xs text-taupe">versión {f.version_n}</span></> : <span className="text-taupe">—</span>}
                  </td>
                  <td className="px-4 py-3 text-xs text-taupe">
                    {s ? <>{s.publicada}<br />{s.vista}<br />{s.confirmada}</>
                      : f.estado === "papel" ? <>En papel · {fechaHoraLima(f.publicada_at)}</> : "—"}
                  </td>
                  <td className="px-4 py-3"><Acciones fila={f} grande={false} onAccion={onAccion} /></td>
                </Fila>
              );
            })}
          </tbody>
        </Tabla>
      </div>

      {/* Celular */}
      <ul className="space-y-3 md:hidden">
        {filas.map((f) => {
          const s = seguimiento(f);
          const resumen = resumenDelDocumento(f);
          return (
            <li key={f.persona_id} className="rounded-superficie border border-sand bg-papel p-4">
              <div className="mb-2 flex items-start justify-between gap-3">
                <div className="min-w-0"><Persona f={f} /></div>
                <div className="shrink-0 text-right">
                  <InsigniaDeEstado estado={estadoVisible(f)} />
                  {f.actualizada && f.estado === "publicada" && <p className="mt-1 text-xs text-taupe">Actualizada</p>}
                </div>
              </div>
              <dl className="mb-3">
                <Dato etiqueta="Documento">{resumen ? `${resumen} · versión ${f.version_n}` : "—"}</Dato>
                {s && (
                  <>
                    <Dato etiqueta="Publicada">{s.publicada}</Dato>
                    <Dato etiqueta="Vista">{s.vista}</Dato>
                    <Dato etiqueta="Confirmada">{s.confirmada}</Dato>
                  </>
                )}
                {f.estado === "papel" && <Dato etiqueta="En papel">{fechaHoraLima(f.publicada_at)}</Dato>}
              </dl>
              <Acciones fila={f} grande onAccion={onAccion} />
            </li>
          );
        })}
      </ul>
    </>
  );
}

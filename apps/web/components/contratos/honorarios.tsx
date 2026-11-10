"use client";

// ============================================================================
// La pestaña «Recibo por honorarios» de Contratos
// ============================================================================
// QUÉ PROMETE
//   Que Desarrollo Organizacional vea, de cada persona que cobra por recibo por
//   honorarios, si tiene su contrato de locación de servicios firmado y hasta
//   cuándo, de lo más urgente a lo que está al día. Migración 0610:
//   `fn_locaciones_tablero` y `fn_locaciones_listar`.
//
// POR QUÉ ES UNA PESTAÑA APARTE Y NO UNA BANDA MÁS DEL TABLERO
//   El resto de Contratos habla del contrato de TRABAJO: art. 77, copia en 3
//   días hábiles, renovación desde el generador. Nada de eso aplica a una
//   locación, y mezclarlos en la misma lista haría creer que sí. La 0610 lo
//   explica del lado de la base: ni siquiera comparten tabla.
// ============================================================================

import { useCallback, useEffect, useRef, useState } from "react";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { Cargando } from "@/components/cargando";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Boton } from "@/components/ui/boton";
import { Drawer } from "@/components/ui/drawer";
import { EstadoVacio } from "@/components/ui/estado-vacio";
import { Insignia } from "@/components/ui/insignia";
import { ParaAtender } from "@/components/ui/para-atender";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { isoADiaMesAnio } from "@/lib/admin/planilla/formato";
import {
  BANDAS_LOCACION,
  bandaLocacion,
  ESTADO_CONTRATO,
  ESTADO_PERSONA,
  textoPlazo,
  type BandaLocacion,
  type ContratoLocacion,
  type FilaTableroLocacion,
} from "@/lib/admin/locaciones";

/**
 * El tablero de las personas por honorarios. Vive fuera de la pestaña porque la
 * pestaña de Contratos muestra su número rojo aunque no esté abierta. Un fallo
 * NO se ve como «nadie»: se devuelve aparte, para que la pestaña lo diga.
 */
export function useLocacionesTablero(supabase: ClienteCayla) {
  const [filas, setFilas] = useState<FilaTableroLocacion[]>([]);
  const [fallo, setFallo] = useState<string | null>(null);
  const [cargando, setCargando] = useState(true);

  const recargar = useCallback(async () => {
    const { data, error } = await supabase.rpc("fn_locaciones_tablero");
    setFilas((data as FilaTableroLocacion[] | null) ?? []);
    setFallo(error ? mensajeDeError(error, "consultar los contratos por honorarios") : null);
    setCargando(false);
  }, [supabase]);

  // `recargar` solo pone estado después de su `await`: no hay renders en cascada.
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void recargar(); }, [recargar]);

  return { filas, fallo, cargando, recargar };
}

const fecha = (iso: string | null) => (iso ? isoADiaMesAnio(iso) : "—");

export function ContratosHonorarios({
  supabase,
  tablero,
}: {
  supabase: ClienteCayla;
  tablero: ReturnType<typeof useLocacionesTablero>;
}) {
  const [banda, setBanda] = useState<BandaLocacion | null>(null);
  const [abierta, setAbierta] = useState<FilaTableroLocacion | null>(null);
  // El drawer le devuelve el foco a la fila que lo abrió.
  const filaQueAbrio = useRef<HTMLElement | null>(null);

  const { filas, fallo, cargando } = tablero;
  const enBanda = (b: BandaLocacion) => filas.filter((f) => bandaLocacion(f.estado) === b);
  const n = (b: BandaLocacion) => enBanda(b).length;

  if (cargando) return <Cargando />;

  return (
    <div className="space-y-5">
      <p className="max-w-prose text-sm text-taupe">
        Quien cobra por recibo por honorarios no firma un contrato de trabajo: firma un contrato de{" "}
        <strong className="font-medium text-tinta">locación de servicios</strong>. Aquí se guarda ese contrato
        firmado y se avisa cuando falta o se vence.
      </p>

      {fallo && (
        <BannerAviso role="alert" variante="alerta" titulo="No se pudieron consultar los contratos por honorarios">
          <p className="mb-2">Esto no significa que estén al día: significa que no se pudo mirar. ({fallo})</p>
          <Boton variante="secundario" tamano="sm" onClick={() => void tablero.recargar()}>Reintentar</Boton>
        </BannerAviso>
      )}

      {!fallo && filas.length === 0 && (
        <EstadoVacio>Nadie del equipo cobra hoy por recibo por honorarios.</EstadoVacio>
      )}

      {!fallo && filas.length > 0 && (
        <>
          <ParaAtender
            items={[
              { clave: "sin_cubrir", texto: `${n("sin_cubrir")} sin contrato vigente`, n: n("sin_cubrir"), tono: "ambar" },
              { clave: "pronto", texto: `${n("pronto")} vence${n("pronto") === 1 ? "" : "n"} pronto`, n: n("pronto"), tono: "ambar" },
            ]}
            activa={banda}
            alTocar={(clave) => setBanda(banda === clave ? null : (clave as BandaLocacion))}
          />

          {BANDAS_LOCACION.filter((b) => (banda === null || banda === b.clave) && n(b.clave) > 0).map((b) => (
            <section key={b.clave} aria-label={b.titulo}>
              <h2 className="mb-1 flex flex-wrap items-baseline gap-2 font-serif text-lg">
                {b.titulo}
                <span className="font-sans text-xs font-normal text-taupe">
                  {n(b.clave)} {n(b.clave) === 1 ? "persona" : "personas"}
                </span>
              </h2>
              <p className="mb-2 text-xs text-taupe">{b.ayuda}</p>
              <TarjetaInfo className="overflow-hidden p-0 sm:p-0">
                <ul className="divide-y divide-sand">
                  {enBanda(b.clave).map((f) => (
                    <FilaPersona
                      key={f.persona_id}
                      f={f}
                      alAbrir={(el) => { filaQueAbrio.current = el; setAbierta(f); }}
                    />
                  ))}
                </ul>
              </TarjetaInfo>
            </section>
          ))}
        </>
      )}

      <Drawer
        abierto={abierta !== null}
        onCerrar={() => setAbierta(null)}
        titulo={abierta ? `Contratos de locación · ${abierta.persona}` : undefined}
        volverElFocoA={filaQueAbrio}
      >
        {abierta && <Historial supabase={supabase} fila={abierta} />}
      </Drawer>
    </div>
  );
}

function FilaPersona({ f, alAbrir }: { f: FilaTableroLocacion; alAbrir: (el: HTMLElement) => void }) {
  const estado = ESTADO_PERSONA[f.estado];
  const plazo = f.estado === "por_empezar" ? `Empieza el ${fecha(f.fecha_inicio)}` : textoPlazo(f);
  const detalle = [f.servicio, f.sede].filter(Boolean).join(" · ");
  return (
    <li>
      {/* Un botón y no un `<li onClick>`: así la fila se abre también con el teclado. */}
      <button
        type="button"
        onClick={(e) => alAbrir(e.currentTarget)}
        className="flex w-full flex-wrap items-center justify-between gap-x-3 gap-y-1.5 px-4 py-3 text-left transition-colors duration-150 hover:bg-crema/60"
      >
        <span className="min-w-0">
          <span className="block font-medium text-tinta sm:truncate">{f.persona}</span>
          <span className="block text-xs text-taupe sm:truncate">
            {detalle || "Sin contrato registrado"}
            {f.cubierto_hasta && f.estado !== "por_empezar" && ` · hasta el ${fecha(f.cubierto_hasta)}`}
          </span>
        </span>
        <span className="flex shrink-0 flex-wrap items-center gap-2">
          {plazo && (
            <span className={f.estado === "vencido" ? "text-xs font-medium text-ambar" : "text-xs text-taupe"}>{plazo}</span>
          )}
          <Insignia variante={estado.variante} tamano="sm">{estado.texto}</Insignia>
        </span>
      </button>
    </li>
  );
}

/** Todos los contratos de una persona, el más reciente primero, anulados incluidos. */
function Historial({ supabase, fila }: { supabase: ClienteCayla; fila: FilaTableroLocacion }) {
  const [contratos, setContratos] = useState<ContratoLocacion[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [cargando, setCargando] = useState(true);

  const cargar = useCallback(async () => {
    const { data, error: e } = await supabase.rpc("fn_locaciones_listar", { p_persona_id: fila.persona_id });
    setContratos((data as ContratoLocacion[] | null) ?? []);
    setError(e ? mensajeDeError(e, "traer sus contratos") : null);
    setCargando(false);
  }, [supabase, fila.persona_id]);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargar(); }, [cargar]);

  if (cargando) return <Cargando />;
  if (error) return <BannerAviso enLinea role="alert">{error}</BannerAviso>;
  if (contratos.length === 0) {
    return <EstadoVacio>Todavía no hay ningún contrato de locación registrado para {fila.persona}.</EstadoVacio>;
  }

  return (
    <ul className="space-y-3">
      {contratos.map((c) => {
        const estado = ESTADO_CONTRATO[c.estado];
        return (
          <li key={c.id} className={c.estado === "anulado" ? "opacity-70" : undefined}>
            <TarjetaInfo className="space-y-1.5 p-4 sm:p-4">
              <div className="flex flex-wrap items-start justify-between gap-2">
                <p className={`font-medium text-tinta ${c.estado === "anulado" ? "line-through" : ""}`}>{c.servicio}</p>
                <Insignia variante={estado.variante} tamano="sm">{estado.texto}</Insignia>
              </div>
              <p className="text-sm text-tinta">
                Del {fecha(c.fecha_inicio)} al {fecha(c.terminado_el ?? c.fecha_fin)}
                {c.terminado_el && <span className="text-taupe"> (iba hasta el {fecha(c.fecha_fin)})</span>}
              </p>
              <p className="text-xs text-taupe">
                Firmado el {fecha(c.fecha_firma)} · registrado por {c.registrado_por_nombre ?? "—"}
              </p>
              {c.terminado_el && c.terminado_motivo && (
                <p className="text-xs text-taupe">Terminado: {c.terminado_motivo} ({c.terminado_por_nombre ?? "—"})</p>
              )}
              {c.anulado_at && c.anulado_motivo && (
                <p className="text-xs text-taupe">Anulado: {c.anulado_motivo} ({c.anulado_por_nombre ?? "—"})</p>
              )}
            </TarjetaInfo>
          </li>
        );
      })}
    </ul>
  );
}

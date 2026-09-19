"use client";

import { useMemo, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { Modal } from "@/components/ui/modal";
import { useToast } from "@/components/toast";
import { VisorDeHojas } from "@/components/boletas/visor-de-hojas";
import { esBoletaNueva, etiquetaDeHojas, extensionPorMime, type TipoBoleta } from "@/lib/boletas";
import { hojasFirmadasDeVersion, urlDeDescarga, type HojaFirmada } from "@/lib/boletas-archivos";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { fechaCorta, fechaLargaLima } from "@/lib/admin/planilla/formato";
import {
  nombreDeArchivoDeBoleta, nombreDelPeriodo, type FilaMiBoleta,
} from "@/lib/mis-boletas";
import { pesoLegible } from "@/lib/reducir-imagen";

/**
 * La pestaña «Boletas» de /mio: las boletas OFICIALES —las que entrega el
 * contador— de cada periodo pagado, para verlas, guardarlas y confirmar que
 * llegaron. NO es la boleta calculada por el sistema (`/mio/boleta`, «Cómo va tu
 * pago» en el Resumen): esa muestra el periodo en curso; esta es la que vale
 * cuando el periodo ya se pagó.
 *
 * NO PIDE SUS PROPIOS DATOS. /mio ya trae `fn_mis_boletas` para poner el globito
 * en el menú —que tiene que verse ANTES de abrir esta pestaña—, y esta pantalla
 * pinta esa misma lectura. Dos consultas para lo mismo terminarían diciendo
 * cosas distintas (el globito «1» sobre una lista sin ninguna nueva).
 *
 * «VER» ES EL ÚNICO CAMINO PARA ABRIR. La primera apertura queda escrita en la
 * base cuando se piden las hojas por `fn_boleta_partes`, y por eso las hojas se
 * piden SIEMPRE con `hojasFirmadasDeVersion`, nunca firmando la ruta a mano. Lo
 * que queda escrito prueba que se pidieron las hojas, no que se leyeron: el
 * texto de la pantalla no dice más que eso.
 *
 * LO QUE GANA LA BASE. Qué boleta es la vigente, si se puede confirmar y si la
 * persona es la dueña lo decide la base. Si algo cambió mientras la pantalla
 * estaba abierta (DO reemplazó la boleta), la base contesta con un mensaje ya
 * escrito para leerse; aquí se muestra tal cual y se recarga la lista.
 */

type Ocupada = string | null;

/** Una espera corta entre descargas: varios navegadores descartan las que llegan pegadas. */
const ENTRE_DESCARGAS_MS = 700;

function esperar(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

/** Dispara la descarga de una URL que el almacén ya firmó con `download`. */
function dispararDescarga(url: string, nombre: string) {
  const a = document.createElement("a");
  a.href = url;
  a.download = nombre;
  a.rel = "noopener";
  document.body.appendChild(a);
  a.click();
  a.remove();
}

function tipoDe(f: FilaMiBoleta): TipoBoleta | null {
  return f.tipo === "pdf" || f.tipo === "imagen" ? f.tipo : null;
}

export function BoletasMias({
  filas,
  error,
  onRecargar,
}: {
  /** `null` = todavía cargando. */
  filas: FilaMiBoleta[] | null;
  /** El texto ya escrito para la persona si la lectura falló. */
  error: string | null;
  /** Vuelve a leer `fn_mis_boletas`: se llama tras abrir, guardar o confirmar. */
  onRecargar: () => Promise<void>;
}) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const { avisar } = useToast();
  // UNA sola acción a la vez: mientras una boleta se abre, se guarda o se
  // confirma, todos los botones esperan. Dos acciones sobre la misma boleta en
  // paralelo (guardar mientras se confirma) no aportan nada y sí confunden.
  const [ocupada, setOcupada] = useState<Ocupada>(null);
  const [visor, setVisor] = useState<{
    versionId: string; titulo: string; tipo: TipoBoleta; hojas: HojaFirmada[];
  } | null>(null);

  const nuevas = (filas ?? []).filter(esBoletaNueva);

  /** Pide las hojas. Deja escrita la primera apertura y recarga; si falla, dice por qué. */
  async function pedirHojas(f: FilaMiBoleta, segundos: number): Promise<HojaFirmada[] | null> {
    if (!f.version_id) return null;
    const r = await hojasFirmadasDeVersion(supabase, f.version_id, segundos);
    // Se recarga también si falló: si la base ya escribió la apertura antes de
    // que el almacén fallara, la lista tiene que reflejarlo; y si DO reemplazó
    // la boleta, la lista tiene que mostrar la nueva.
    void onRecargar();
    if (r.error) {
      avisar("error", r.error);
      return null;
    }
    return r.hojas;
  }

  async function ver(f: FilaMiBoleta) {
    const tipo = tipoDe(f);
    if (!f.version_id || !tipo) return;
    setOcupada(`ver:${f.version_id}`);
    const hojas = await pedirHojas(f, 300);
    setOcupada(null);
    if (!hojas) return;
    setVisor({
      versionId: f.version_id,
      titulo: `Tu boleta de ${nombreDelPeriodo(f.fecha_fin)}`,
      tipo,
      hojas,
    });
  }

  async function guardar(f: FilaMiBoleta) {
    if (!f.version_id) return;
    setOcupada(`guardar:${f.version_id}`);
    // Guardar también «abre» la boleta: pedir las hojas es lo que deja escrito
    // que la persona la tiene. Las direcciones de esta llamada solo sirven para
    // conocer las rutas; la descarga se firma aparte, con su nombre.
    const hojas = await pedirHojas(f, 60);
    if (!hojas) { setOcupada(null); return; }

    let guardadas = 0;
    for (let i = 0; i < hojas.length; i++) {
      const h = hojas[i];
      const ext = extensionPorMime(h.mime) ?? h.ruta.split(".").pop() ?? "jpg";
      const nombre = nombreDeArchivoDeBoleta(f.fecha_fin, i + 1, hojas.length, ext);
      const url = await urlDeDescarga(supabase, h.ruta, nombre);
      if (!url) break;
      dispararDescarga(url, nombre);
      guardadas++;
      if (i < hojas.length - 1) await esperar(ENTRE_DESCARGAS_MS);
    }
    setOcupada(null);

    if (guardadas === hojas.length) {
      avisar("ok", hojas.length === 1
        ? "Tu boleta se está guardando en tu teléfono o computadora."
        : `Tus ${hojas.length} hojas se están guardando en tu teléfono o computadora.`);
    } else {
      avisar("error", guardadas === 0
        ? "No pudimos guardar tu boleta ahora. Intenta de nuevo en unos minutos, o ábrela con «Ver»."
        : `Se guardaron ${guardadas} de ${hojas.length} hojas. Intenta de nuevo para las que faltan, o ábrelas con «Ver».`);
    }
  }

  async function confirmar(f: FilaMiBoleta) {
    if (!f.version_id) return;
    setOcupada(`confirmar:${f.version_id}`);
    const { error: e } = await supabase.rpc("fn_boleta_confirmar_recibo", { p_version_id: f.version_id });
    setOcupada(null);
    if (e) {
      // El mensaje de la base viene escrito para leerse, incluido el de «tu
      // boleta se actualizó»: `mensajeDeError` lo deja tal cual.
      avisar("error", mensajeDeError(e));
    } else {
      avisar("ok", `Quedó anotado que recibiste tu boleta de ${nombreDelPeriodo(f.fecha_fin, { minuscula: true })}.`);
    }
    await onRecargar();
  }

  const enModal = visor ? (filas ?? []).find((f) => f.version_id === visor.versionId) ?? null : null;
  const puedeConfirmarEnModal = enModal !== null && enModal.estado === "publicada" && !enModal.recibida_at;

  return (
    <section className="rounded-2xl border border-sand p-5 text-sm">
      <h2 className="mb-1 font-serif text-lg">Boletas emitidas</h2>
      <p className="mb-4 text-taupe">
        Son las boletas oficiales que entrega el contador, una por periodo pagado. El cálculo del periodo
        que corre está en el Resumen, en «Cómo va tu pago».
      </p>

      {/* El aviso va ARRIBA de la lista: quien llega desde el globito o desde la
          Bandeja tiene que ver primero lo que vino a buscar, no buscarlo entre
          los periodos viejos. */}
      {nuevas.length > 0 && (
        <div className="mb-4 flex flex-col gap-3 rounded-2xl border border-ambar/40 bg-ambar/[0.07] p-4 sm:flex-row sm:items-center sm:justify-between">
          <p className="text-tinta">
            {nuevas.length === 1
              ? `Tu boleta de ${nombreDelPeriodo(nuevas[0].fecha_fin, { minuscula: true })} ya está disponible.`
              : `Tienes ${nuevas.length} boletas nuevas. La más reciente es la de ${nombreDelPeriodo(nuevas[0].fecha_fin, { minuscula: true })}.`}
          </p>
          <Boton
            variante="primario"
            className="min-h-11 w-full sm:w-auto"
            disabled={ocupada !== null}
            cargando={ocupada === `ver:${nuevas[0].version_id}`}
            onClick={() => void ver(nuevas[0])}
          >
            Abrir boleta
          </Boton>
        </div>
      )}

      {filas === null ? (
        // Sin lista todavía: o está cargando, o la primera lectura falló. Si una
        // recarga falla teniendo ya la lista, se conserva la que se ve: la base
        // rechaza con su mensaje cualquier acción sobre algo que cambió.
        error ? <p className="text-rojo-profundo">{error}</p> : <p className="text-taupe">Cargando…</p>
      ) : filas.length === 0 ? (
        <p className="text-taupe">
          Todavía no hay un periodo pagado con boleta para ti. Cuando se pague uno, aparecerá aquí.
        </p>
      ) : (
        <ul className="flex flex-col gap-3">
          {filas.map((f) => {
            const tipo = tipoDe(f);
            const publicada = f.estado === "publicada" && f.version_id !== null && tipo !== null;
            const nueva = esBoletaNueva(f);
            const vista = Boolean(f.vista_at);
            const confirmada = Boolean(f.recibida_at);
            return (
              <li key={f.periodo_id} className="rounded-2xl border border-sand bg-papel p-4">
                <div className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-x-2 gap-y-1.5">
                      <strong className="font-serif text-base font-medium">{nombreDelPeriodo(f.fecha_fin)}</strong>
                      {publicada && nueva && <Insignia variante="contador" tamano="sm">Nueva</Insignia>}
                      {publicada && confirmada ? (
                        <Insignia variante="positivo" tamano="sm">Confirmada · {fechaLargaLima(f.recibida_at!)}</Insignia>
                      ) : publicada && vista ? (
                        <Insignia variante="informativo" tamano="sm">Vista · {fechaLargaLima(f.vista_at!)}</Insignia>
                      ) : null}
                      {publicada && f.actualizada && <Insignia variante="advertencia" tamano="sm">Actualizada</Insignia>}
                      {f.estado === "papel" && (
                        <Insignia variante="positivo" tamano="sm">
                          Entregada en papel{f.publicada_at ? ` · ${fechaLargaLima(f.publicada_at)}` : ""}
                        </Insignia>
                      )}
                    </div>

                    <p className="mt-1 text-xs text-taupe">
                      Del {fechaCorta(f.fecha_ini)} al {fechaCorta(f.fecha_fin)}
                      {publicada && tipo && f.n_partes > 0
                        ? ` · ${etiquetaDeHojas(tipo, f.n_partes)} · ${pesoLegible(f.bytes)}`
                        : ""}
                    </p>

                    {f.estado === null && (
                      <p className="mt-2 text-taupe">
                        Aún no está publicada. DO la publica cuando el contador la entrega.
                      </p>
                    )}
                    {f.estado === "papel" && (
                      <p className="mt-2 text-taupe">Te la entregaron en papel. No hay nada que abrir aquí.</p>
                    )}
                    {publicada && f.actualizada && !confirmada && (
                      <p className="mt-2 text-xs text-taupe">
                        Desarrollo Organizacional actualizó esta boleta. Ábrela para ver la versión vigente.
                      </p>
                    )}
                  </div>

                  {publicada && (
                    // En teléfono los botones se apilan bajo el periodo y usan todo
                    // el ancho: «Ver» y «Guardar» lado a lado, «Confirmar» debajo.
                    // Cada uno mide 44 px de alto, el mínimo de algo que se toca
                    // con el pulgar.
                    <div className="grid grid-cols-2 gap-2 md:flex md:shrink-0 md:flex-wrap md:justify-end">
                      <Boton
                        variante="secundario"
                        className="min-h-11 w-full md:w-auto"
                        disabled={ocupada !== null}
                        cargando={ocupada === `ver:${f.version_id}`}
                        onClick={() => void ver(f)}
                      >
                        Ver
                      </Boton>
                      <Boton
                        variante="secundario"
                        className="min-h-11 w-full md:w-auto"
                        disabled={ocupada !== null}
                        cargando={ocupada === `guardar:${f.version_id}`}
                        onClick={() => void guardar(f)}
                      >
                        {tipo === "pdf"
                          ? (f.n_partes > 1 ? "Descargar PDFs" : "Descargar PDF")
                          : (f.n_partes > 1 ? "Guardar fotos" : "Guardar foto")}
                      </Boton>
                      {!confirmada && (
                        <Boton
                          variante="primario"
                          className="col-span-2 min-h-11 w-full md:col-span-1 md:w-auto"
                          // Confirmar sin haberla abierto no dice nada: la
                          // constancia sería «la recibí» sobre algo que nunca se
                          // pidió. La base lo permitiría; la pantalla no.
                          disabled={ocupada !== null || !vista}
                          cargando={ocupada === `confirmar:${f.version_id}`}
                          onClick={() => void confirmar(f)}
                        >
                          Confirmar que la recibí
                        </Boton>
                      )}
                      {!confirmada && !vista && (
                        <p className="col-span-2 text-xs text-taupe md:basis-full md:text-right">
                          Ábrela con «Ver» para poder confirmar que la recibiste.
                        </p>
                      )}
                    </div>
                  )}
                </div>
              </li>
            );
          })}
        </ul>
      )}

      <p className="mt-5 text-xs text-taupe">
        Si algo de tu boleta no cuadra, avisa a DO. Un dato mal registrado se corrige y se anota con su
        motivo; no se discute al final del mes.
      </p>

      <Modal
        abierto={visor !== null}
        onCerrar={() => setVisor(null)}
        titulo={visor?.titulo}
        ancho="xl"
        bloqueado={ocupada !== null && ocupada.startsWith("confirmar:")}
      >
        {visor && (
          <>
            <VisorDeHojas hojas={visor.hojas} tipo={visor.tipo} />
            <div className="mt-5 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
              <Boton variante="secundario" className="min-h-11 w-full sm:w-auto" onClick={() => setVisor(null)}>
                Cerrar
              </Boton>
              {puedeConfirmarEnModal && enModal && (
                <Boton
                  variante="primario"
                  className="min-h-11 w-full sm:w-auto"
                  disabled={ocupada !== null}
                  cargando={ocupada === `confirmar:${enModal.version_id}`}
                  onClick={() => void confirmar(enModal)}
                >
                  Confirmar que la recibí
                </Boton>
              )}
            </div>
          </>
        )}
      </Modal>
    </section>
  );
}

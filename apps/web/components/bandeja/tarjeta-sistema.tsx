"use client";

// ============================================================================
// Tarjeta «Sistema» de la Bandeja — la salud del despacho de correos.
// ----------------------------------------------------------------------------
// PROMETE. Dice cuántos avisos por correo no van a salir solos y POR QUÉ, en UNA
// línea que siempre se ve (insignia, titular, el motivo en pocas palabras y el
// botón); y, a quien puede, le ofrece una salida: «Revisar y resolver estos
// avisos» (reenviar los que aún sirven, cerrar los que ya no). Las causas
// completas con su «qué hacer», las atascadas y el último correo enviado van
// plegados en «Ver por qué y qué hacer»: esto es una señal del sistema, no una
// tarea, y empujar la lista de trabajo hacia abajo es lo contrario de «menos
// ruido». La parte que decide y redacta vive en `lib/admin/bandeja-sistema.ts`;
// este archivo solo la pinta y llama a la base.
//
// SE DEGRADA, NO SE ROMPE. La función de la base (`fn_alertas_resolver_fallidas`,
// 0548) se pega a mano ANTES de fusionar, pero `main` se publica sola: puede que
// esta pantalla llegue primero. Si la base contesta «no existe esa función»
// (PGRST202 / 42883) el botón no se dibuja y la tarjeta cuenta lo mismo que
// antes; cualquier otro error se dice con palabras y la tarjeta sigue en pie.
//
// DOS LLAMADAS, NUNCA UNA. Abrir la ventana llama con `p_ejecutar=false` (solo
// cuenta, no escribe) y MUESTRA lo que pasaría; el botón de confirmar es la
// única llamada con `p_ejecutar=true`. Quien confirma ve el número antes de
// escribir, no después.
// ============================================================================

import { useCallback, useEffect, useId, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Boton } from "@/components/ui/boton";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Insignia } from "@/components/ui/insignia";
import { Modal } from "@/components/ui/modal";
import { Cargando } from "@/components/cargando";
import { useToast } from "@/components/toast";
import type { ErrorBase } from "@/lib/admin/mensaje-error";
import { diaLima, type ResumenAlertas } from "@/lib/admin/bandeja-fuentes";
import {
  causasDeLaTarjeta, causasPorPrioridad, frasesDeResolucion, funcionNoExiste, leerPropuesta, lineaDeCausas,
  mensajeDeResultado, mostrarBotonResolver, notasSinExplicar, recordatorioDelCanal, textoDeErrorDeLaVentana,
  TEXTO_SONDEO_FALLIDO, titularDeLaTarjeta,
  type FalloDeLaLlamada, type PropuestaResolucion, type SondeoDeLaFuncion,
} from "@/lib/admin/bandeja-sistema";

/** Lo que devuelve una llamada a la función: la propuesta, o por qué no. */
type Resultado =
  | { tipo: "ok"; propuesta: PropuestaResolucion }
  | { tipo: "no_existe" }
  | { tipo: "error"; fallo: FalloDeLaLlamada };

/**
 * Nunca lanza: una red caída o un cliente que no se pudo crear volverían a abrir()
 * y confirmar() una promesa rechazada, y la ventana se quedaría en «Contando los
 * avisos…» (o bloqueada con «Confirmar» girando) para siempre.
 */
async function llamar(ejecutar: boolean): Promise<Resultado> {
  try {
    const supabase = createAdminSupabaseClient();
    const { data, error } = await supabase.rpc("fn_alertas_resolver_fallidas", { p_ejecutar: ejecutar });
    if (error) return funcionNoExiste(error) ? { tipo: "no_existe" } : { tipo: "error", fallo: { origen: "base", error: error as ErrorBase } };
    const propuesta = leerPropuesta(data);
    // Una respuesta sin la forma esperada no se lee como «no hay nada»: sería afirmar algo que no llegó.
    return propuesta ? { tipo: "ok", propuesta } : { tipo: "error", fallo: { origen: "forma" } };
  } catch {
    return { tipo: "error", fallo: { origen: "excepcion" } };
  }
}

export function TarjetaSistema({
  resumen,
  total,
  puedeResolver,
  onResuelto,
}: {
  resumen: ResumenAlertas;
  /** Avisos con problema (`alertasConProblema`: definitivos + caducados): el número del titular. */
  total: number;
  /** `puedeVerSaludDeAlertas(rol)`. La base lo vuelve a decidir; esto solo decide si se dibuja. */
  puedeResolver: boolean;
  /** Recarga las fuentes de la Bandeja (y avisa al menú) después de resolver. */
  onResuelto: () => void | Promise<void>;
}) {
  const { avisar } = useToast();
  const idDetalle = useId();

  // Lo que dijo la base la última vez que se le preguntó si hay algo que resolver.
  const [sondeo, setSondeo] = useState<SondeoDeLaFuncion>({ tipo: "pendiente" });
  // Sube después de resolver, para volver a preguntar aunque los números del resumen no cambien.
  const [versionSondeo, setVersionSondeo] = useState(0);
  const [verDetalle, setVerDetalle] = useState(false);
  const [abierto, setAbierto] = useState(false);
  const [revisando, setRevisando] = useState(false);
  const [propuesta, setPropuesta] = useState<PropuestaResolucion | null>(null);
  const [errorVentana, setErrorVentana] = useState<string | null>(null);
  const [ejecutando, setEjecutando] = useState(false);

  const definitivas = resumen.fallidas_definitivas ?? 0;
  const caducadas = resumen.caducadas ?? 0;
  const hayMuertos = definitivas + caducadas > 0;

  // Sondeo: ¿existe la función y hay algo que resolver? Se pide con `p_ejecutar=false`,
  // que solo cuenta. Se repite si cambian los números (alguien resolvió desde otro lado).
  useEffect(() => {
    if (!puedeResolver || !hayMuertos) return;
    let vigente = true;
    void llamar(false).then((r) => {
      if (!vigente) return;
      setSondeo(r.tipo === "ok" ? { tipo: "ok", propuesta: r.propuesta } : r.tipo === "no_existe" ? { tipo: "no_existe" } : { tipo: "error" });
    });
    return () => { vigente = false; };
  }, [puedeResolver, hayMuertos, definitivas, caducadas, versionSondeo]);

  const abrir = useCallback(async () => {
    setAbierto(true);
    setRevisando(true);
    setErrorVentana(null);
    setPropuesta(null);
    const r = await llamar(false);
    if (r.tipo === "ok") { setPropuesta(r.propuesta); setSondeo({ tipo: "ok", propuesta: r.propuesta }); }
    else if (r.tipo === "no_existe") { setAbierto(false); setSondeo({ tipo: "no_existe" }); }
    else setErrorVentana(textoDeErrorDeLaVentana(r.fallo, "revisar los avisos"));
    setRevisando(false);
  }, []);

  async function confirmar() {
    if (ejecutando) return;
    setEjecutando(true);
    setErrorVentana(null);
    const r = await llamar(true);
    if (r.tipo === "ok" && r.propuesta.ejecutado) {
      avisar("ok", mensajeDeResultado(r.propuesta));
      setAbierto(false);
      setEjecutando(false);
      setSondeo({ tipo: "pendiente" });
      setVersionSondeo((v) => v + 1);
      await onResuelto();
      return;
    }
    if (r.tipo === "no_existe") { setAbierto(false); setSondeo({ tipo: "no_existe" }); }
    else if (r.tipo === "ok") setErrorVentana("La base no confirmó el cambio y no se hizo nada. Vuelve a revisar.");
    else setErrorVentana(textoDeErrorDeLaVentana(r.fallo, "resolver los avisos"));
    setEjecutando(false);
  }

  const causas = causasPorPrioridad(causasDeLaTarjeta(resumen.motivos_definitivos));
  const sinExplicar = notasSinExplicar(resumen.motivos_definitivos);
  const hayBoton = mostrarBotonResolver({ puede: puedeResolver, sondeo, resumen });
  const frases = propuesta ? frasesDeResolucion(propuesta) : null;
  const recordatorio = recordatorioDelCanal(causas);
  const linea = lineaDeCausas(causas, definitivas > 0);
  const hayAccion = propuesta && frases && !frases.nada;

  return (
    <>
      <BannerAviso enLinea variante="informativo" className="mt-4">
        {/* La línea que siempre se ve. En móvil se parte en renglones; el botón queda con alto táctil. */}
        <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
          <Insignia variante="informativo" tamano="sm" punto={false}>Sistema</Insignia>
          <p className="min-w-0 flex-1 basis-60">
            <strong>{titularDeLaTarjeta(total)}.</strong>
            {linea && <span className="text-taupe"> {linea}</span>}
          </p>
          <div className="flex flex-wrap items-center gap-x-3 gap-y-2 sm:shrink-0">
            <Boton
              variante="enlace"
              className="text-sm text-rojo"
              aria-expanded={verDetalle}
              aria-controls={idDetalle}
              onClick={() => setVerDetalle((v) => !v)}
            >
              {verDetalle ? "Ocultar el detalle" : "Ver por qué y qué hacer"}
            </Boton>
            {hayBoton && (
              <Boton variante="secundario" tamano="sm" className="min-h-10 sm:min-h-0" onClick={() => void abrir()}>
                Revisar y resolver estos avisos
              </Boton>
            )}
          </div>
        </div>

        {sondeo.tipo === "error" && <p className="mt-2 text-xs text-taupe">{TEXTO_SONDEO_FALLIDO}</p>}

        {verDetalle && (
          <div id={idDetalle} className="mt-3 border-t border-pizarra/20 pt-3">
            <ul className="space-y-2">
              {definitivas > 0 && (
                <li>
                  <strong className="text-rojo-profundo">
                    {definitivas} fall{definitivas === 1 ? "ó" : "aron"} tres veces
                  </strong>
                  <span className="text-taupe"> — ya no se reintentan.</span>
                  {causas.length > 0 ? (
                    <ul className="mt-1 list-disc space-y-1 pl-5">
                      {causas.map((c) => (
                        <li key={c.causa}>
                          <strong>{c.etiqueta}.</strong> <span className="text-taupe">{c.que_hacer}</span>
                        </li>
                      ))}
                    </ul>
                  ) : (
                    <span className="mt-1 block text-taupe">
                      Sin nota del motivo: revisa en Sentry el último despacho y la cuenta de Resend (clave <code>RESEND_API_KEY</code> y dominio verificado).
                    </span>
                  )}
                  {sinExplicar.length > 0 && (
                    <details className="mt-1 text-taupe">
                      <summary className="cursor-pointer text-rojo">Ver el texto del error</summary>
                      <ul className="mt-1 list-disc space-y-1 pl-5 break-words">
                        {sinExplicar.map((n) => <li key={n}>{n}</li>)}
                      </ul>
                    </details>
                  )}
                </li>
              )}
              {caducadas > 0 && (
                <li>
                  <strong className="text-ambar">
                    {caducadas} caduc{caducadas === 1 ? "ó" : "aron"} sin salir
                  </strong>
                  <span className="text-taupe"> — más de siete días sin despacho. </span>
                  Ya no se van a mandar solos.{" "}
                  {hayBoton
                    ? "«Revisar y resolver» te muestra cuáles se reenviarían y cuáles se cerrarían, antes de tocar nada."
                    : "Si el aviso todavía importa, hay que darlo a mano."}
                </li>
              )}
              {resumen.atascadas > 0 && (
                <li>
                  <strong className="text-ambar">
                    {resumen.atascadas} qued{resumen.atascadas === 1 ? "ó" : "aron"} a medio despachar
                  </strong>
                  <span className="text-taupe"> hace más de una hora, y no cuentan arriba. </span>
                  Se reintentan solos en el próximo despacho; si vuelve a pasar, revisa en Sentry por qué se corta.
                </li>
              )}
            </ul>

            <p className="mt-2 text-taupe">
              {resumen.despachables} esperando el próximo despacho ·{" "}
              {resumen.ultimo_envio_at
                ? `último correo enviado el ${diaLima(resumen.ultimo_envio_at)}`
                : "todavía no salió ningún correo"}
              {" "}— si esa fecha se aleja, el cron dejó de correr.
            </p>
          </div>
        )}
      </BannerAviso>

      <Modal
        abierto={abierto}
        onCerrar={() => setAbierto(false)}
        titulo="Resolver los avisos por correo que no salieron"
        ancho="lg"
        bloqueado={ejecutando}
      >
        {revisando && <Cargando compacto texto="Contando los avisos…" />}

        {errorVentana && (
          <BannerAviso enLinea variante="alerta" role="alert">{errorVentana}</BannerAviso>
        )}

        {propuesta && frases && (
          frases.nada ? (
            <p className="text-sm text-taupe">
              No hay nada que reenviar ni que cerrar: los avisos que quedan no tienen salida desde aquí.
              Si el aviso todavía importa, hay que darlo a mano.
            </p>
          ) : (
            <div className="space-y-3 text-sm">
              {frases.reencolar && (
                <p>
                  <strong>{frases.reencolar}</strong>
                  {frases.reencolarDetalle && <span className="block text-taupe">{frases.reencolarDetalle}.</span>}
                  {frases.reencolarRenovadas && <span className="block text-taupe">{frases.reencolarRenovadas}</span>}
                </p>
              )}
              {frases.descartar && (
                <p>
                  <strong>{frases.descartar}</strong>
                  {frases.descartarDetalle && <span className="block text-taupe">{frases.descartarDetalle}.</span>}
                </p>
              )}
              {frases.notaDeCierre && <p className="text-taupe">{frases.notaDeCierre}</p>}
              <BannerAviso enLinea variante={recordatorio.tono}>
                {recordatorio.texto}
              </BannerAviso>
            </div>
          )
        )}

        <div className="mt-5 flex justify-end gap-2">
          <Boton onClick={() => setAbierto(false)} disabled={ejecutando}>
            {hayAccion ? "Cancelar" : "Cerrar"}
          </Boton>
          {errorVentana && !revisando && !ejecutando && (
            <Boton onClick={() => void abrir()}>Reintentar</Boton>
          )}
          {hayAccion && (
            <Boton variante="primario" cargando={ejecutando} onClick={() => void confirmar()}>
              Confirmar y resolver
            </Boton>
          )}
        </div>
      </Modal>
    </>
  );
}

"use client";

// /admin/parametros — los números del sistema, con puerta y con rastro (0552).
//
// Qué tiene que responder en diez segundos: qué vale hoy cada número, quién lo
// movió por última vez y por qué, y qué pasaría si se cambiara. Cambiarlo es un
// panel lateral en dos pasos (ver `PanelCambio`); el historial queda abajo, del
// más nuevo al más viejo, con un «volver a este valor» que NO deshace nada: es
// un cambio nuevo, con su propio motivo.
//
// LO QUE ESTA PANTALLA NO HACE, a propósito:
//   · No muestra ni cambia nada de plata (provisiones, sueldos, RMV): eso exige
//     vigencia y vista previa y llega en la rebanada 2.
//   · No deja editar la escalera disciplinaria: es del RIT, y entra atada a una
//     versión del RIT. Lo que fija una norma se muestra aparte y sin botón.
//
// SI LA MIGRACIÓN TODAVÍA NO ESTÁ PEGADA. `main` se publica sola y la 0552 la
// pega Felipe a mano, así que el código puede llegar antes. En vez de un error
// crudo, la pantalla lo dice (PGRST202: la función no existe todavía).

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import {
  ETIQUETA_CLASE_PARAMETRO,
  describirCambioDeParametro,
  fechaLima,
  horaLimaLegible,
  etiquetaQuienCambia,
  puedeCambiarParametro,
  puedeGestionarParametros,
  valorConUnidad,
} from "@cayla-dynamic/shared";
import { Cargando } from "@/components/cargando";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Boton } from "@/components/ui/boton";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { Drawer } from "@/components/ui/drawer";
import { EstadoVacio } from "@/components/ui/estado-vacio";
import { Insignia } from "@/components/ui/insignia";
import { Rotulo } from "@/components/ui/rotulo";
import { Fila, Tabla, TablaEncabezado, Th } from "@/components/ui/tabla";
import { useRolActual } from "@/lib/admin/use-rol";
import { isoADiaMesAnio } from "@/lib/admin/planilla/formato";
import {
  normalizarCambios,
  normalizarParametros,
  repartirParametros,
  type CambioParametro,
  type ParametroFila,
} from "@/lib/admin/parametros";
import { PanelCambio } from "./PanelCambio";

/** «26/10/2026 · 8:40 a. m.» — el día y la hora de Lima en que se cambió. */
function cuandoSeCambio(ts: string): string {
  return `${isoADiaMesAnio(fechaLima(ts))} · ${horaLimaLegible(ts)}`;
}

/** La función aún no existe en la base: la 0552 no está pegada. */
function faltaLaMigracion(error: { code?: string; message: string }): boolean {
  return error.code === "PGRST202" || /could not find the function/i.test(error.message);
}

type Objetivo = { fila: ParametroFila; valorInicial?: string; motivoInicial?: string };

export default function ParametrosPage() {
  const router = useRouter();
  const rol = useRolActual();
  const puedeVer = puedeGestionarParametros(rol);
  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  const [filas, setFilas] = useState<ParametroFila[] | null>(null);
  const [historial, setHistorial] = useState<CambioParametro[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [sinMigracion, setSinMigracion] = useState(false);

  const [objetivo, setObjetivo] = useState<Objetivo | null>(null);
  const [panelAbierto, setPanelAbierto] = useState(false);
  // Un panel nuevo por apertura: así el valor y el motivo de la vez anterior no sobreviven.
  const [aperturas, setAperturas] = useState(0);
  const focoAlAbrir = useRef<HTMLElement | null>(null);

  // Sin sesión no hay panel
  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      if (!data.session) router.replace("/admin/login");
    });
  }, [supabase, router]);

  const cargar = useCallback(async () => {
    if (!puedeVer) return;
    const lista = await supabase.rpc("fn_parametros_listar");
    if (lista.error) {
      if (faltaLaMigracion(lista.error)) setSinMigracion(true);
      else setError(lista.error.message);
      return;
    }
    setSinMigracion(false);
    setError(null);
    setFilas(normalizarParametros(lista.data as unknown as Record<string, unknown>[]));

    const hist = await supabase.rpc("fn_parametros_historial", { p_limite: 50 });
    // El historial se lee aparte: si falla, la lista se sigue viendo y el panel lo dice.
    setHistorial(hist.error ? null : normalizarCambios(hist.data as unknown as Record<string, unknown>[]));
  }, [supabase, puedeVer]);

  useEffect(() => {
    (async () => {
      await cargar();
    })();
  }, [cargar]);

  function abrir(fila: ParametroFila, e: React.MouseEvent<HTMLElement>, valorInicial?: string, motivoInicial?: string) {
    focoAlAbrir.current = e.currentTarget;
    setObjetivo({ fila, valorInicial, motivoInicial });
    setAperturas((n) => n + 1);
    setPanelAbierto(true);
  }

  /** Qué se cambió por última vez, dicho en un renglón y su motivo. */
  function ultimoCambio(f: ParametroFila) {
    if (!f.ultimo_cambio_at) return "Sin cambios desde que existe.";
    return (
      <>
        <div>
          {cuandoSeCambio(f.ultimo_cambio_at)}
          {f.ultimo_origen === "base" ? " · a mano en la base" : f.ultimo_cambio_por ? ` · ${f.ultimo_cambio_por}` : ""}
        </div>
        {f.ultimo_motivo && <div className="mt-0.5">«{f.ultimo_motivo}»</div>}
      </>
    );
  }

  const { editables, fijos } = useMemo(() => repartirParametros(filas ?? []), [filas]);
  const porClave = useMemo(() => new Map((filas ?? []).map((f) => [f.parametro, f])), [filas]);

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        <CabeceraPagina
          titulo="Parámetros"
          descripcion="Los números que mueven el sistema. Cada cambio queda escrito: quién, cuándo, de qué a qué y por qué."
        />

        {rol === null ? (
          <Cargando />
        ) : !puedeVer ? (
          <BannerAviso variante="advertencia">Solo la dirección y Desarrollo Organizacional ven los parámetros.</BannerAviso>
        ) : sinMigracion ? (
          <BannerAviso variante="informativo" titulo="Falta pegar la migración 0552">
            Esta pantalla ya está lista, pero la base todavía no tiene los parámetros. En cuanto se pegue la 0552 en el SQL
            Editor de Supabase, aparecen aquí.
          </BannerAviso>
        ) : error ? (
          <BannerAviso variante="alerta" titulo="No se pudieron leer los parámetros">
            {error}
          </BannerAviso>
        ) : !filas ? (
          <Cargando />
        ) : (
          <div className="flex max-w-5xl flex-col gap-8">
            <section className="flex flex-col gap-2">
              <Rotulo como="h3">Se pueden cambiar</Rotulo>
              {editables.length === 0 ? (
                <EstadoVacio>Todavía no hay parámetros que se puedan cambiar desde acá.</EstadoVacio>
              ) : (
                <Tabla>
                  <TablaEncabezado>
                    <Th>Parámetro</Th>
                    <Th>Hoy</Th>
                    <Th className="hidden md:table-cell">Último cambio</Th>
                    <Th className="hidden md:table-cell" />
                  </TablaEncabezado>
                  <tbody>
                    {editables.map((f) => {
                      const puede = puedeCambiarParametro(rol, f.clase, f.roles_cambia.length > 0 ? f.roles_cambia : null);
                      return (
                        <Fila key={f.parametro}>
                          <td className="max-w-md px-4 py-3 align-top">
                            <div className="font-medium">{f.nombre}</div>
                            <p className="mt-0.5 text-xs text-taupe">{f.descripcion}</p>
                            <div className="mt-1.5">
                              <Insignia tamano="sm" variante="neutral" punto={false}>{ETIQUETA_CLASE_PARAMETRO[f.clase]}</Insignia>
                              {etiquetaQuienCambia(f.roles_cambia) && (
                                <span className="ml-2 text-xs text-taupe">{etiquetaQuienCambia(f.roles_cambia)}</span>
                              )}
                            </div>
                            {/* En celular la columna «Último cambio» no cabe: baja aquí. */}
                            <div className="mt-2 text-xs text-taupe md:hidden">{ultimoCambio(f)}</div>
                          </td>
                          <td className="whitespace-nowrap px-4 py-3 align-top">
                            <div className="font-medium">{valorConUnidad(f.valor_actual, f.unidad)}</div>
                            {f.es_defecto && <div className="text-xs text-taupe">valor de partida</div>}
                            {/* Y el botón sube junto al valor: la última columna queda fuera de la pantalla del teléfono. */}
                            {puede && (
                              <Boton tamano="sm" className="mt-2 md:hidden" onClick={(e) => abrir(f, e)}>
                                Cambiar
                              </Boton>
                            )}
                          </td>
                          <td className="hidden px-4 py-3 align-top text-xs text-taupe md:table-cell">{ultimoCambio(f)}</td>
                          <td className="hidden px-4 py-3 text-right align-top md:table-cell">
                            {puede && (
                              <Boton tamano="sm" onClick={(e) => abrir(f, e)}>
                                Cambiar
                              </Boton>
                            )}
                          </td>
                        </Fila>
                      );
                    })}
                  </tbody>
                </Tabla>
              )}
            </section>

            {fijos.length > 0 && (
              <section className="flex flex-col gap-2">
                <Rotulo como="h3">Los fija una norma</Rotulo>
                <p className="text-sm text-taupe">
                  Se muestran para que se vea qué número usa el sistema y de dónde sale. No se cambian desde acá.
                </p>
                <Tabla>
                  <TablaEncabezado>
                    <Th>Parámetro</Th>
                    <Th>Hoy</Th>
                    <Th>De dónde sale</Th>
                  </TablaEncabezado>
                  <tbody>
                    {fijos.map((f) => (
                      <Fila key={f.parametro}>
                        <td className="max-w-md px-4 py-3 align-top">
                          <div className="font-medium">{f.nombre}</div>
                          <p className="mt-0.5 text-xs text-taupe">{f.descripcion}</p>
                        </td>
                        <td className="whitespace-nowrap px-4 py-3 align-top font-medium">{valorConUnidad(f.valor_actual, f.unidad)}</td>
                        <td className="px-4 py-3 align-top text-xs text-taupe">{f.base ?? "—"}</td>
                      </Fila>
                    ))}
                  </tbody>
                </Tabla>
              </section>
            )}

            <section className="flex flex-col gap-2">
              <Rotulo como="h3">Historial</Rotulo>
              {historial === null ? (
                <BannerAviso variante="advertencia">No se pudo leer el historial. La lista de arriba sí está al día.</BannerAviso>
              ) : historial.length === 0 ? (
                <EstadoVacio>Todavía nadie ha cambiado un parámetro.</EstadoVacio>
              ) : (
                <Tabla>
                  <TablaEncabezado>
                    <Th>Cuándo</Th>
                    <Th>Parámetro</Th>
                    <Th>Cambio</Th>
                    <Th>Quién y por qué</Th>
                    <Th />
                  </TablaEncabezado>
                  <tbody>
                    {historial.map((h) => {
                      const fila = porClave.get(h.parametro);
                      const sePuedeVolver =
                        !!fila && fila.editable && puedeCambiarParametro(rol, fila.clase, fila.roles_cambia.length > 0 ? fila.roles_cambia : null) && fila.valor_actual !== h.valor_anterior;
                      return (
                        <Fila key={h.id}>
                          <td className="whitespace-nowrap px-4 py-3 align-top text-xs text-taupe">{cuandoSeCambio(h.cambiado_at)}</td>
                          <td className="px-4 py-3 align-top">{h.nombre}</td>
                          <td className="whitespace-nowrap px-4 py-3 align-top">
                            {describirCambioDeParametro(h.valor_anterior, h.valor_nuevo, h.unidad)}
                          </td>
                          <td className="px-4 py-3 align-top text-xs">
                            {h.origen === "base" ? (
                              <Insignia tamano="sm" variante="advertencia">A mano en la base</Insignia>
                            ) : (
                              <span>{h.cambiado_por ?? "—"}</span>
                            )}
                            <div className="mt-0.5 text-taupe">«{h.motivo}»</div>
                          </td>
                          <td className="px-4 py-3 text-right align-top">
                            {sePuedeVolver && fila && (
                              <Boton
                                tamano="sm"
                                variante="sutil"
                                onClick={(e) =>
                                  abrir(fila, e, String(h.valor_anterior), `Volver al valor del ${cuandoSeCambio(h.cambiado_at)}`)
                                }
                              >
                                Volver a este valor
                              </Boton>
                            )}
                          </td>
                        </Fila>
                      );
                    })}
                  </tbody>
                </Tabla>
              )}
            </section>
          </div>
        )}
      </main>

      <Drawer
        abierto={panelAbierto}
        onCerrar={() => setPanelAbierto(false)}
        titulo="Cambiar parámetro"
        volverElFocoA={focoAlAbrir}
      >
        {objetivo && (
          <PanelCambio
            key={aperturas}
            fila={objetivo.fila}
            valorInicial={objetivo.valorInicial}
            motivoInicial={objetivo.motivoInicial}
            onCerrar={() => setPanelAbierto(false)}
            onGuardado={() => {
              void cargar();
            }}
          />
        )}
      </Drawer>
    </div>
  );
}

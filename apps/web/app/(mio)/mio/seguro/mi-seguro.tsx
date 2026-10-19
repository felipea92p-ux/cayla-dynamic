"use client";

import { useEffect, useMemo, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { hoyLima } from "@cayla-dynamic/shared";
import { Cargando } from "@/components/cargando";
import { useToast } from "@/components/toast";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { Rotulo } from "@/components/ui/rotulo";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { abrirArchivoFirmado } from "@/lib/abrir-archivo-firmado";
import { BUCKET_SEGUROS } from "@/lib/admin/seguros";
import { isoADiaMesAnio } from "@/lib/admin/planilla/formato";
import {
  datosConfirmados, enlaceTelefono, guiasQueAplican, nombreDeDescarga, resolverMiSeguro, resumenSoloRepite, rotuloDeArchivo,
  SI_NO_CUADRA, textoDelResumen, traerMiSeguro, type ArchivoMio, type GuiaQueAplica, type MiSeguro as MiSeguroCalculado,
  type PolizaMia, type SeguroPrincipal, type TelefonoDeUso, type TextoResumen,
} from "@/lib/mi-seguro";
import { descargarArchivoDeSeguro } from "@/lib/mi-seguro-archivos";
import { formatSoles } from "@/lib/rangos";
import { pesoLegible } from "@/lib/reducir-imagen";

/**
 * La sección «Mi seguro» de /mio: en qué seguro está cada colaborador y, si ese seguro lleva
 * póliza, su número, hasta cuándo la cubre y el PDF de su póliza y de su convenio de pago.
 * Migración 0530. Vive aparte de /mio/page.tsx, que ya pasa las tres mil líneas, y pide sus datos
 * solo cuando se abre.
 *
 * ES DE TODO EL EQUIPO (Felipe, 2026-10-17). Cada colaborador ve el suyo: FOLA con su póliza,
 * EsSalud «lo gestiona la empresa con la planilla», el que DO le asigne. La puerta es «es MI
 * póliza», no «hoy estoy en ese seguro»: quien cambió de seguro conserva las pólizas del anterior y
 * sus PDF. Lo que cada persona puede ver lo decide la base (`fn_mi_seguro`, `fn_mis_polizas` y la
 * política de Storage de la 0530); esta pantalla solo dibuja.
 *
 * UN SEGURO SIN PÓLIZA NO SE EXPLICA. Para EsSalud la pantalla dice solo lo que la base sabe: el
 * nombre del seguro y que lo gestiona la empresa con la planilla, sin póliza ni PDF. El texto lo
 * eligió Felipe; no se inventan explicaciones de lo que no se tiene a mano.
 *
 * LO QUE NO MUESTRA, A PROPÓSITO. El plan y el «máximo anual» mientras el corredor no los
 * confirme (la base manda null y aquí no se pinta ni un «pendiente»), y nada del papeleo de DO:
 * ni la prima, ni si está pagada o firmada. Por eso la pantalla habla de la PÓLIZA —«vigente»,
 * «va hasta»— y no dice que la persona «esté cubierta»: la cobertura puede estar suspendida por
 * mora (prima sin pagar más de 30 días) y eso la persona no lo ve. Un seguro «suspendido»
 * porque DO aún no marcó un pago sería una falsa alarma sobre su salud; uno «cubierto» que no lo
 * está, una negativa en la clínica. El texto está en `textoDelResumen` (`lib/mi-seguro.ts`).
 *
 * EL TEXTO DE «CÓMO USAR» es un resumen de la póliza, no la póliza: lo dice y manda al PDF. Hoy
 * solo existe el de FOLA. Vive en `lib/mi-seguro.ts`.
 */

const fecha = isoADiaMesAnio;

// ── Piezas ──────────────────────────────────────────────────────────────────

/**
 * Los PDF de una póliza: abrir y descargar. `destacar` pinta «Abrir» de la póliza como el botón
 * principal de la pantalla —en la clínica es lo que se viene a buscar—; las demás tarjetas no
 * compiten con él.
 */
function ArchivosDeLaPoliza({
  p, ocupada, onAbrir, onDescargar, avisarSiFalta, destacar,
}: {
  p: PolizaMia; ocupada: string | null; avisarSiFalta: boolean; destacar: boolean;
  onAbrir: (a: ArchivoMio) => void;
  onDescargar: (p: PolizaMia, a: ArchivoMio) => void;
}) {
  if (p.archivos.length === 0) {
    return avisarSiFalta ? (
      <p className="mt-3 text-taupe">
        El PDF de esta póliza todavía no está cargado. Pídeselo a Desarrollo Organizacional.
      </p>
    ) : null;
  }
  return (
    <>
      <ul className="mt-3 divide-y divide-sand border-t border-sand" aria-busy={ocupada !== null}>
        {p.archivos.map((a) => {
          const rotulo = rotuloDeArchivo(a, p.archivos);
          const principal = destacar && a.tipo === "poliza";
          return (
            <li key={a.id} className="flex flex-col gap-2 py-2 sm:flex-row sm:items-center sm:justify-between">
              <span className="min-w-0 text-tinta">
                {rotulo}
                {a.bytes > 0 && <span className="text-taupe"> · {pesoLegible(a.bytes)}</span>}
              </span>
              <span className="grid grid-cols-2 gap-2 sm:flex sm:shrink-0">
                <Boton variante={principal ? "primario" : "secundario"} className="min-h-11 w-full sm:w-auto"
                  aria-label={`Abrir ${rotulo}`}
                  cargando={ocupada === `abrir:${a.id}`} disabled={ocupada !== null}
                  onClick={() => onAbrir(a)}>
                  Abrir
                </Boton>
                <Boton variante="secundario" className="min-h-11 w-full sm:w-auto" aria-label={`Descargar ${rotulo}`}
                  cargando={ocupada === `descargar:${a.id}`} disabled={ocupada !== null}
                  onClick={() => onDescargar(p, a)}>
                  Descargar
                </Boton>
              </span>
            </li>
          );
        })}
      </ul>
      <p className="mt-1 text-xs text-taupe">
        El PDF lleva tus datos personales. Si lo descargas en un equipo que no es solo tuyo, bórralo después.
      </p>
    </>
  );
}

/**
 * LA PÓLIZA QUE CUBRE HOY, PRIMERO (rediseño 2026-10-19). Es lo que la colaboradora viene a buscar,
 * a menudo de pie en la recepción de una clínica con la carta de garantía en la mano: el número en
 * grande y copiable, hasta cuándo es vigente, el PDF a un toque y el teléfono de la aseguradora.
 * Antes el número iba en 14 px dentro de una frase, el primer botón quedaba en el borde de la
 * pantalla y el resumen de arriba repetía la misma vigencia. Esta tarjeta solo se usa cuando hay
 * una póliza vigente; sin ella (EsSalud, sin póliza, vencida) sigue el resumen de siempre.
 *
 * No dice que la persona «esté cubierta»: ver el comentario de la sección sobre la mora.
 */
function CarnePoliza({
  p, hasta, resumen, repite, telefonos, aseguradora, ocupada, onAbrir, onDescargar, onCopiar,
}: {
  p: PolizaMia; hasta: string; resumen: TextoResumen; repite: boolean;
  telefonos: readonly TelefonoDeUso[]; aseguradora: string; ocupada: string | null;
  onAbrir: (a: ArchivoMio) => void;
  onDescargar: (p: PolizaMia, a: ArchivoMio) => void;
  onCopiar: (numero: string) => void;
}) {
  const datos = datosConfirmados(p, formatSoles);
  return (
    <section aria-label="Tu póliza" className="rounded-xl border border-tinta/30 bg-papel px-4 py-4">
      <div className="flex items-start justify-between gap-2">
        <p className="text-base font-medium text-tinta">{p.producto_nombre}</p>
        <Insignia variante={resumen.variante} tamano="sm">{resumen.insignia}</Insignia>
      </div>

      <Rotulo className="mt-4">Número de póliza</Rotulo>
      <div className="mt-1 flex items-center justify-between gap-3">
        <p className="min-w-0 break-all font-mono text-2xl font-medium tracking-wide text-tinta select-all">{p.numero_poliza}</p>
        <Boton variante="secundario" className="min-h-11 shrink-0" aria-label={`Copiar el número de póliza ${p.numero_poliza}`}
          onClick={() => onCopiar(p.numero_poliza)}>
          Copiar
        </Boton>
      </div>
      <p className="mt-1 text-taupe">{p.aseguradora}</p>

      <p className="mt-3 text-tinta">
        Vigente hasta el <span className="font-medium">{fecha(hasta)}</span>
        <span className="text-taupe"> a las 12 del mediodía</span>
      </p>

      {datos.length > 0 && (
        <dl className="mt-2 flex flex-wrap gap-x-5 gap-y-1">
          {datos.map((d) => (
            <div key={d.etiqueta}>
              <dt className="inline text-taupe">{d.etiqueta}: </dt>
              <dd className="inline text-tinta">{d.valor}</dd>
            </div>
          ))}
        </dl>
      )}

      <ArchivosDeLaPoliza p={p} ocupada={ocupada} onAbrir={onAbrir} onDescargar={onDescargar}
        avisarSiFalta destacar />

      {telefonos.length > 0 && (
        <div className="mt-2">
          <Rotulo>Llamar a {aseguradora}</Rotulo>
          {/* Cada número es un blanco para el dedo: sin altura propia quedaba en ~20 px, bajo los 44 del resto.
              La póliza distingue los dos teléfonos, y ahí está lo que sirve cada uno. */}
          <ul>
            {telefonos.map((t) => (
              <li key={t.numero} className="flex flex-wrap items-center gap-x-3">
                <a href={enlaceTelefono(t.numero)} className="inline-flex min-h-11 items-center font-medium text-tinta underline underline-offset-2 hover:text-rojo-profundo">{t.numero}</a>
                <span className="min-w-0 text-xs text-taupe">{t.uso}</span>
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* Si el resumen solo repetía la vigencia, de su frase queda lo que no está arriba: a quién avisar si no cuadra. */}
      {repite ? (
        <p className="mt-2 border-t border-sand pt-3 text-xs text-taupe">{SI_NO_CUADRA}</p>
      ) : (
        <div className="mt-3 border-t border-sand pt-3">
          <p className="font-medium text-tinta">{resumen.titulo}</p>
          <p className="mt-1 text-taupe">{resumen.detalle}</p>
        </div>
      )}
    </section>
  );
}

function Resumen({ seguro }: { seguro: MiSeguroCalculado }) {
  // El texto vive en `lib/mi-seguro.ts` para poder probar lo que NO dice (nunca «cubierto»).
  const t = textoDelResumen(seguro, fecha);
  return (
    <div className="rounded-xl border border-sand bg-papel px-4 py-4">
      <div className="flex flex-wrap items-center gap-2">
        <Insignia variante={t.variante}>{t.insignia}</Insignia>
        <p className="font-medium text-tinta">{t.titulo}</p>
      </div>
      <p className="mt-2 text-taupe">{t.detalle}</p>
    </div>
  );
}

function TarjetaPoliza({
  p, hoy, esActual, ocupada, onAbrir, onDescargar,
}: {
  p: PolizaMia; hoy: string; esActual: boolean; ocupada: string | null;
  onAbrir: (a: ArchivoMio) => void;
  onDescargar: (p: PolizaMia, a: ArchivoMio) => void;
}) {
  const datos = datosConfirmados(p, formatSoles);
  // Todas las tarjetas van sobre `bg-papel`: las insignias de estado se midieron sobre crema y papel, y
  // sobre `hueso` («Vigente» 4.40:1, «Empieza el…» 4.28:1) quedaban bajo el 4.5:1 de WCAG AA. La actual se
  // distingue por su borde, no por el fondo.
  return (
    <div className={`rounded-xl border bg-papel px-4 py-4 ${esActual ? "border-tinta/30" : "border-sand"}`}>
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="font-medium text-tinta">
            {p.producto_nombre}
            <span className="font-normal text-taupe"> · póliza N.º </span>
            <span className="font-mono">{p.numero_poliza}</span>
            <span className="font-normal text-taupe"> · {p.aseguradora}</span>
          </p>
          <p className="mt-0.5 text-taupe">
            Del {fecha(p.vigente_desde)} al {fecha(p.vigente_hasta)}, hasta las 12 del mediodía
          </p>
        </div>
        {p.cubre_hoy ? <Insignia variante="positivo" tamano="sm">Vigente</Insignia>
          : p.vigente_desde > hoy ? <Insignia variante="informativo" tamano="sm">Empieza el {fecha(p.vigente_desde)}</Insignia>
          : p.vigente_hasta === hoy ? <Insignia variante="advertencia" tamano="sm">Termina hoy</Insignia>
          : <Insignia variante="neutral" tamano="sm">Vencida</Insignia>}
      </div>

      {datos.length > 0 && (
        <dl className="mt-3 flex flex-wrap gap-x-5 gap-y-1">
          {datos.map((d) => (
            <div key={d.etiqueta}>
              <dt className="inline text-taupe">{d.etiqueta}: </dt>
              <dd className="inline text-tinta">{d.valor}</dd>
            </div>
          ))}
        </dl>
      )}

      <ArchivosDeLaPoliza p={p} ocupada={ocupada} onAbrir={onAbrir} onDescargar={onDescargar}
        avisarSiFalta={esActual} destacar={false} />
    </div>
  );
}

function ComoUsarlo({ g, nombrePrincipal, sinTelefonos }: { g: GuiaQueAplica; nombrePrincipal: string | null; sinTelefonos: boolean }) {
  const { guia } = g;
  return (
    <TarjetaInfo como="section" titulo={`Cómo usar tu póliza ${g.nombre}`} className="text-sm">
      {/* Con un seguro principal distinto (pasó de FOLA a EsSalud y la póliza sigue vigente hasta la baja) no se
          muestran dos «tu seguro» sin explicar. */}
      {!g.esPrincipal && (
        <p className="mb-2 text-taupe">
          {nombrePrincipal ? `Tu seguro principal ahora es ${nombrePrincipal}. ` : ""}
          Esta póliza sigue registrada hasta que {guia.aseguradora} procese la baja.
        </p>
      )}
      <ul className="mt-3 space-y-3">
        {guia.pasos.map((paso) => (
          <li key={paso.clave}>
            <p className="font-medium text-tinta">{paso.titulo}</p>
            <p className="text-taupe">{paso.texto}</p>
          </li>
        ))}
        {!sinTelefonos && guia.telefonos.length > 0 && (
          <li>
            <p className="font-medium text-tinta">Teléfonos de {guia.aseguradora}</p>
            {/* Cada número es un blanco para el dedo: sin altura propia quedaba en ~20 px, bajo los 44 del resto. */}
            <ul className="text-taupe">
              {guia.telefonos.map((t) => (
                <li key={t.numero} className="flex flex-wrap items-center gap-x-3">
                  <a href={enlaceTelefono(t.numero)} className="inline-flex min-h-11 items-center font-medium text-tinta underline underline-offset-2 hover:text-rojo-profundo">{t.numero}</a>
                  <span className="min-w-0 text-xs">{t.uso}</span>
                </li>
              ))}
            </ul>
          </li>
        )}
      </ul>

      {guia.noCubre.length > 0 && (
        <>
          <h3 className="mb-1 mt-5 font-medium text-tinta">Algunas cosas que NO cubre (no es la lista completa)</h3>
          <ul className="list-disc space-y-0.5 pl-5 text-taupe">
            {guia.noCubre.map((x) => <li key={x}>{x}</li>)}
          </ul>
        </>
      )}

      <p className="mt-5 border-t border-sand pt-3 text-xs text-taupe">
        Esto es un resumen. Lo que vale es tu póliza en PDF; si tienes dudas, llama a {guia.aseguradora} o pregunta
        a Desarrollo Organizacional. {SI_NO_CUADRA}
      </p>
    </TarjetaInfo>
  );
}

// ── La sección ──────────────────────────────────────────────────────────────

export function MiSeguro() {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const { avisar } = useToast();
  const [carga, setCarga] = useState<{ principal: SeguroPrincipal | null; polizas: PolizaMia[]; error: string | null } | null>(null);
  // Cambiarlo vuelve a pedir los datos: el «Reintentar» del error de lectura.
  const [intento, setIntento] = useState(0);
  // UNA sola acción a la vez: mientras un archivo se abre o se baja, los demás botones esperan.
  const [ocupada, setOcupada] = useState<string | null>(null);

  useEffect(() => {
    let vivo = true;
    void traerMiSeguro(supabase).then((r) => { if (vivo) setCarga(r); });
    return () => { vivo = false; };
  }, [supabase, intento]);

  const hoy = hoyLima();
  const seguro = useMemo(() => (carga ? resolverMiSeguro(carga.principal, carga.polizas, hoy) : null), [carga, hoy]);

  async function abrir(a: ArchivoMio) {
    setOcupada(`abrir:${a.id}`);
    try {
      // `abrirArchivoFirmado` abre la pestaña ANTES de esperar la firma, dentro del clic: ver el
      // comentario de ese archivo.
      const fallo = await abrirArchivoFirmado(supabase, BUCKET_SEGUROS, a.storage_path, 120);
      if (fallo) avisar("error", fallo);
    } catch {
      avisar("error", "No se pudo abrir el archivo. Vuelve a intentarlo.");
    } finally {
      setOcupada(null);
    }
  }

  // El número se copia para pegarlo en el portal de la clínica o dictarlo sin leerlo mal. Si el navegador no deja
  // (iPhone sin permiso, página sin HTTPS), el número está en `select-all`: un toque largo lo selecciona.
  async function copiar(numero: string) {
    try {
      await navigator.clipboard.writeText(numero);
      avisar("ok", "Número de póliza copiado.");
    } catch {
      avisar("error", "No se pudo copiar. Mantén apretado el número para copiarlo.");
    }
  }

  async function descargar(p: PolizaMia, a: ArchivoMio) {
    setOcupada(`descargar:${a.id}`);
    try {
      const nombre = nombreDeDescarga(a, p);
      const fallo = await descargarArchivoDeSeguro(supabase, a.storage_path, nombre);
      // Sin este aviso la persona no sabe si bajó, y toca dos veces.
      if (fallo) avisar("error", fallo);
      else avisar("ok", `Descargando «${nombre}»: búscalo en tus descargas.`);
    } catch {
      avisar("error", "No pudimos descargar el archivo. Vuelve a intentarlo.");
    } finally {
      setOcupada(null);
    }
  }

  if (!carga || !seguro) {
    return (
      <TarjetaInfo como="section" titulo="Mi seguro" className="text-sm">
        <Cargando texto="Cargando tu seguro…" />
      </TarjetaInfo>
    );
  }
  if (carga.error) {
    return (
      <TarjetaInfo como="section" titulo="Mi seguro" className="text-sm">
        <div role="alert">
          <BannerAviso variante="alerta" enLinea>{carga.error}</BannerAviso>
        </div>
        <div className="mt-3">
          <Boton variante="secundario" className="min-h-11" onClick={() => { setCarga(null); setIntento((n) => n + 1); }}>
            Reintentar
          </Boton>
        </div>
      </TarjetaInfo>
    );
  }

  const poliza = (p: PolizaMia, esActual: boolean) => (
    <TarjetaPoliza key={p.poliza_id} p={p} hoy={hoy} esActual={esActual} ocupada={ocupada}
      onAbrir={(a) => void abrir(a)} onDescargar={(x, a) => void descargar(x, a)} />
  );
  const guias = guiasQueAplican(carga.polizas, carga.principal?.tipo ?? null);
  const resumen = textoDelResumen(seguro, fecha);
  // Con una póliza vigente va primero SU tarjeta; sin ella, el resumen de siempre.
  const vigente = seguro.actual !== null && seguro.actual.cubre_hoy && seguro.cubiertoHasta !== null ? seguro.actual : null;
  const guiaDeLaVigente = vigente ? guias.find((g) => g.clave === vigente.producto) : undefined;

  return (
    <div className="space-y-4">
      {vigente && seguro.cubiertoHasta ? (
        <CarnePoliza p={vigente} hasta={seguro.cubiertoHasta} resumen={resumen} repite={resumenSoloRepite(seguro)}
          telefonos={guiaDeLaVigente?.guia.telefonos ?? []} aseguradora={guiaDeLaVigente?.guia.aseguradora ?? vigente.aseguradora}
          ocupada={ocupada} onAbrir={(a) => void abrir(a)} onDescargar={(x, a) => void descargar(x, a)}
          onCopiar={(n) => void copiar(n)} />
      ) : (
        <TarjetaInfo como="section" titulo="Mi seguro" className="text-sm">
          <div className="space-y-3">
            <Resumen seguro={seguro} />
            {seguro.actual && poliza(seguro.actual, true)}
          </div>
        </TarjetaInfo>
      )}

      {/* La guía va justo debajo de la póliza: es lo que sigue a «tengo mi número». */}
      {guias.map((g) => (
        <ComoUsarlo key={g.clave} g={g} nombrePrincipal={seguro.tipo?.nombre ?? null}
          // Los teléfonos ya van en la tarjeta de su póliza, arriba: no se repiten.
          sinTelefonos={vigente !== null && g.clave === vigente.producto} />
      ))}

      {seguro.resto.length > 0 && (
        <TarjetaInfo como="section" titulo={seguro.actual ? "Otras pólizas registradas" : "Tus pólizas"} className="text-sm">
          <div className="space-y-3">{seguro.resto.map((p) => poliza(p, false))}</div>
        </TarjetaInfo>
      )}
    </div>
  );
}

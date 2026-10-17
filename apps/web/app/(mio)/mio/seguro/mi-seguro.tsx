"use client";

import { useEffect, useMemo, useState, type ReactNode } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { hoyLima } from "@cayla-dynamic/shared";
import { useToast } from "@/components/toast";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { abrirArchivoFirmado } from "@/lib/abrir-archivo-firmado";
import { BUCKET_SEGUROS } from "@/lib/admin/seguros";
import { isoADiaMesAnio } from "@/lib/admin/planilla/formato";
import {
  COMO_USARLO, NO_CUBRE, TELEFONOS_PACIFICO, datosConfirmados, enlaceTelefono, nombreDeDescarga, resolverMiSeguro,
  rotuloDeArchivo, traerMiSeguro, type ArchivoMio, type MiSeguro, type PolizaMia,
} from "@/lib/mi-seguro";
import { descargarArchivoDeSeguro } from "@/lib/mi-seguro-archivos";
import { formatSoles } from "@/lib/rangos";
import { pesoLegible } from "@/lib/reducir-imagen";

/**
 * La sección «Mi seguro» de /mio: la póliza FOLA de quien está en prácticas —su
 * número, hasta cuándo la cubre, el PDF de su póliza y de su convenio de pago— y
 * cómo usarla. Migración 0530. Vive aparte de /mio/page.tsx, que ya pasa las tres
 * mil líneas, y pide sus datos solo cuando se abre.
 *
 * SOLO PRACTICANTES (Felipe, 2026-10-17). FOLA es exclusiva de ellos; el seguro del
 * resto del equipo (EsSalud, por planilla) no se toca. Quien no es practicante no
 * ve la sección en el menú; si llega por un enlace, ve un renglón que lo dice. La
 * base también lo decide —`fn_mi_seguro` le devuelve vacío—, así que esta puerta es
 * la comodidad, no la seguridad.
 *
 * LO QUE NO MUESTRA, A PROPÓSITO. El plan y el «máximo anual» mientras el corredor
 * no los confirme (la base manda null y aquí no se pinta ni un «pendiente»), y nada
 * del papeleo de DO: ni la prima, ni si está pagada o firmada. «Al día» es que la
 * póliza está vigente, no que la prima esté al corriente. Un seguro «suspendido»
 * porque DO aún no marcó un pago sería una falsa alarma sobre su salud.
 *
 * EL TEXTO DE «CÓMO USARLO» es un resumen de la póliza, no la póliza: lo dice y
 * manda al PDF. Vive en `lib/mi-seguro.ts`.
 */

const fecha = isoADiaMesAnio;
const plural = (n: number, uno: string, varios: string) => `${n} ${n === 1 ? uno : varios}`;

// ── Piezas ──────────────────────────────────────────────────────────────────

function Resumen({ seguro }: { seguro: MiSeguro }) {
  const { situacion, actual } = seguro;
  let insignia: ReactNode;
  let titulo: string;
  let detalle: string;

  if (situacion === "sin_poliza") {
    insignia = <Insignia variante="neutral">Sin póliza registrada</Insignia>;
    titulo = "Todavía no tienes una póliza registrada";
    detalle = "Cuando Desarrollo Organizacional la registre, aquí vas a ver tu número de póliza y tu PDF. Si crees que ya deberías tenerla, avísales.";
  } else if (situacion === "sin_cobertura") {
    insignia = <Insignia variante="alerta">Sin póliza vigente</Insignia>;
    titulo = "Hoy no tienes una póliza vigente registrada";
    detalle = seguro.empiezaEl
      ? `La que está registrada a tu nombre empieza el ${fecha(seguro.empiezaEl)}. Hasta entonces, avisa a Desarrollo Organizacional para que lo revise.`
      : `Tu última póliza dejó de cubrir el ${fecha(actual!.vigente_hasta)}${seguro.diasDesdeQueVencio ? ` (hace ${plural(seguro.diasDesdeQueVencio, "día", "días")})` : ""}. Avisa a Desarrollo Organizacional para que lo revise.`;
  } else if (situacion === "por_vencer") {
    const faltan = seguro.diasParaQuedarSinSeguro ?? 0;
    insignia = <Insignia variante="advertencia">Vence en {plural(faltan, "día", "días")}</Insignia>;
    titulo = "Tu póliza vence pronto";
    detalle = `Deja de cubrir el ${fecha(seguro.cubiertoHasta!)} a las 12 M y todavía no hay otra registrada que siga. Si se acerca la fecha y no la ves aquí, avisa a Desarrollo Organizacional.`;
  } else {
    insignia = <Insignia variante="positivo">Al día</Insignia>;
    titulo = "Tu seguro está al día";
    detalle = `Tu póliza cubre hasta el ${fecha(seguro.cubiertoHasta!)} a las 12 M.${
      seguro.cubiertoHasta !== actual!.vigente_hasta ? " Ya está registrada la renovación que sigue." : ""
    }`;
  }

  return (
    <div className="rounded-xl border border-sand bg-papel px-4 py-4">
      <div className="flex flex-wrap items-center gap-2">
        {insignia}
        <p className="font-medium text-tinta">{titulo}</p>
      </div>
      <p className="mt-2 text-taupe">{detalle}</p>
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
  return (
    <div className={`rounded-xl border border-sand px-4 py-4 ${esActual ? "bg-papel" : "bg-hueso"}`}>
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="font-medium text-tinta">
            Póliza N.º <span className="font-mono">{p.numero_poliza}</span>
            <span className="font-normal text-taupe"> · {p.aseguradora}</span>
          </p>
          <p className="mt-0.5 text-taupe">
            Del {fecha(p.vigente_desde)} al {fecha(p.vigente_hasta)}, hasta las 12 M
          </p>
        </div>
        {p.cubre_hoy ? <Insignia variante="positivo" tamano="sm">Vigente</Insignia>
          : p.vigente_desde > hoy ? <Insignia variante="informativo" tamano="sm">Empieza el {fecha(p.vigente_desde)}</Insignia>
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

      {p.archivos.length > 0 ? (
        <>
          <ul className="mt-3 divide-y divide-sand border-t border-sand">
            {p.archivos.map((a) => (
              <li key={a.id} className="flex flex-col gap-2 py-2 sm:flex-row sm:items-center sm:justify-between">
                <span className="min-w-0 text-tinta">
                  {rotuloDeArchivo(a, p.archivos)}
                  {a.bytes > 0 && <span className="text-taupe"> · {pesoLegible(a.bytes)}</span>}
                </span>
                <span className="grid grid-cols-2 gap-2 sm:flex sm:shrink-0">
                  <Boton variante="secundario" className="min-h-11 w-full sm:w-auto"
                    cargando={ocupada === `abrir:${a.id}`} disabled={ocupada !== null}
                    onClick={() => onAbrir(a)}>
                    Abrir
                  </Boton>
                  <Boton variante="secundario" className="min-h-11 w-full sm:w-auto"
                    cargando={ocupada === `descargar:${a.id}`} disabled={ocupada !== null}
                    onClick={() => onDescargar(p, a)}>
                    Descargar
                  </Boton>
                </span>
              </li>
            ))}
          </ul>
          <p className="mt-1 text-xs text-taupe">
            El PDF lleva tus datos personales. Si lo descargas en un equipo que no es solo tuyo, bórralo después.
          </p>
        </>
      ) : (
        esActual && (
          <p className="mt-3 text-taupe">
            El PDF de esta póliza todavía no está cargado. Pídeselo a Desarrollo Organizacional.
          </p>
        )
      )}
    </div>
  );
}

function ComoUsarlo() {
  return (
    <section className="rounded-2xl border border-sand p-5 text-sm">
      <h2 className="mb-1 font-serif text-lg">Cómo usar tu seguro</h2>
      <ul className="mt-3 space-y-3">
        {COMO_USARLO.map((paso) => (
          <li key={paso.clave}>
            <p className="font-medium text-tinta">{paso.titulo}</p>
            <p className="text-taupe">{paso.texto}</p>
          </li>
        ))}
        <li>
          <p className="font-medium text-tinta">Teléfonos de Pacífico</p>
          <p className="text-taupe">
            {TELEFONOS_PACIFICO.map((t, i) => (
              <span key={t}>
                {i > 0 && " · "}
                <a href={enlaceTelefono(t)} className="text-tinta underline underline-offset-2 hover:text-rojo-profundo">{t}</a>
              </span>
            ))}
          </p>
        </li>
      </ul>

      <h3 className="mb-1 mt-5 font-medium text-tinta">Lo que esta póliza no cubre</h3>
      <ul className="list-disc space-y-0.5 pl-5 text-taupe">
        {NO_CUBRE.map((x) => <li key={x}>{x}</li>)}
      </ul>

      <p className="mt-5 border-t border-sand pt-3 text-xs text-taupe">
        Esto es un resumen. Lo que vale es tu póliza en PDF; si tienes dudas, llama a Pacífico o pregunta a
        Desarrollo Organizacional.
      </p>
    </section>
  );
}

// ── La sección ──────────────────────────────────────────────────────────────

function MiSeguroDePracticante() {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const { avisar } = useToast();
  const [carga, setCarga] = useState<{ polizas: PolizaMia[]; error: string | null } | null>(null);
  // UNA sola acción a la vez: mientras un archivo se abre o se baja, los demás botones esperan.
  const [ocupada, setOcupada] = useState<string | null>(null);

  useEffect(() => {
    let vivo = true;
    void traerMiSeguro(supabase).then((r) => { if (vivo) setCarga(r); });
    return () => { vivo = false; };
  }, [supabase]);

  const hoy = hoyLima();
  const seguro = useMemo(() => (carga ? resolverMiSeguro(carga.polizas, hoy) : null), [carga, hoy]);

  async function abrir(a: ArchivoMio) {
    setOcupada(`abrir:${a.id}`);
    // `abrirArchivoFirmado` abre la pestaña ANTES de esperar la firma, dentro del
    // clic: ver el comentario de ese archivo.
    const fallo = await abrirArchivoFirmado(supabase, BUCKET_SEGUROS, a.storage_path, 120);
    setOcupada(null);
    if (fallo) avisar("error", fallo);
  }

  async function descargar(p: PolizaMia, a: ArchivoMio) {
    setOcupada(`descargar:${a.id}`);
    const fallo = await descargarArchivoDeSeguro(supabase, a.storage_path, nombreDeDescarga(a, p.numero_poliza));
    setOcupada(null);
    if (fallo) avisar("error", fallo);
  }

  if (!carga || !seguro) {
    return (
      <section className="rounded-2xl border border-sand p-5 text-sm">
        <h2 className="mb-1 font-serif text-lg">Mi seguro</h2>
        <p className="text-taupe">Cargando…</p>
      </section>
    );
  }
  if (carga.error) {
    return (
      <section className="rounded-2xl border border-sand p-5 text-sm">
        <h2 className="mb-1 font-serif text-lg">Mi seguro</h2>
        <p className="text-taupe">{carga.error}</p>
      </section>
    );
  }

  const cubierta = seguro.situacion === "al_dia" || seguro.situacion === "por_vencer";
  const poliza = (p: PolizaMia, esActual: boolean) => (
    <TarjetaPoliza key={p.poliza_id} p={p} hoy={hoy} esActual={esActual} ocupada={ocupada}
      onAbrir={(a) => void abrir(a)} onDescargar={(x, a) => void descargar(x, a)} />
  );

  return (
    <div className="space-y-4">
      <section className="rounded-2xl border border-sand p-5 text-sm">
        <h2 className="mb-1 font-serif text-lg">Mi seguro</h2>
        <p className="mb-4 text-taupe">Tu seguro de salud de practicante, con Pacífico.</p>
        <div className="space-y-3">
          <Resumen seguro={seguro} />
          {seguro.actual && poliza(seguro.actual, true)}
          {seguro.otras.length > 0 && (
            <>
              <h3 className="pt-2 font-medium text-tinta">Otras pólizas</h3>
              {seguro.otras.map((p) => poliza(p, false))}
            </>
          )}
        </div>
      </section>

      {cubierta && <ComoUsarlo />}
    </div>
  );
}

/**
 * `esPracticante`: `null` mientras no se sabe todavía (la ficha de la persona se
 * está leyendo). Se pide de afuera porque /mio ya lee `tipo_vinculo` para otras
 * secciones, y esta no tiene por qué leerlo otra vez.
 */
export function MiSeguro({ esPracticante }: { esPracticante: boolean | null }) {
  if (esPracticante === null) {
    return (
      <section className="rounded-2xl border border-sand p-5 text-sm">
        <h2 className="mb-1 font-serif text-lg">Mi seguro</h2>
        <p className="text-taupe">Cargando…</p>
      </section>
    );
  }
  if (!esPracticante) {
    return (
      <section className="rounded-2xl border border-sand p-5 text-sm">
        <h2 className="mb-1 font-serif text-lg">Mi seguro</h2>
        <p className="text-taupe">Esta sección es solo para quienes están en prácticas.</p>
      </section>
    );
  }
  return <MiSeguroDePracticante />;
}

"use client";

import { useEffect, useMemo, useState, type ReactNode } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { hoyLima } from "@cayla-dynamic/shared";
import { useToast } from "@/components/toast";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { abrirArchivoFirmado } from "@/lib/abrir-archivo-firmado";
import { BUCKET_SEGUROS, plural } from "@/lib/admin/seguros";
import { isoADiaMesAnio } from "@/lib/admin/planilla/formato";
import {
  datosConfirmados, enlaceTelefono, guiasQueAplican, nombreDeDescarga, resolverMiSeguro, rotuloDeArchivo,
  traerMiSeguro, type ArchivoMio, type GuiaDeUso, type MiSeguro as MiSeguroCalculado, type PolizaMia,
  type SeguroPrincipal,
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
 * EsSalud «por planilla», el que DO le asigne. La puerta es «es MI póliza», no «hoy estoy en ese
 * seguro»: quien cambió de seguro conserva las pólizas del anterior y sus PDF. Lo que cada
 * persona puede ver lo decide la base (`fn_mi_seguro`, `fn_mis_polizas` y la política de
 * Storage de la 0530); esta pantalla solo dibuja.
 *
 * UN SEGURO SIN PÓLIZA NO SE EXPLICA. Para EsSalud la pantalla dice solo lo que la base sabe: el
 * nombre del seguro y que va por planilla, sin póliza que ver. El texto final lo decide Felipe,
 * y no se inventan explicaciones de lo que no se tiene a mano.
 *
 * LO QUE NO MUESTRA, A PROPÓSITO. El plan y el «máximo anual» mientras el corredor no los
 * confirme (la base manda null y aquí no se pinta ni un «pendiente»), y nada del papeleo de DO:
 * ni la prima, ni si está pagada o firmada. «Al día» es que la póliza está vigente, no que la
 * prima esté al corriente. Un seguro «suspendido» porque DO aún no marcó un pago sería una falsa
 * alarma sobre su salud.
 *
 * EL TEXTO DE «CÓMO USAR» es un resumen de la póliza, no la póliza: lo dice y manda al PDF. Hoy
 * solo existe el de FOLA. Vive en `lib/mi-seguro.ts`.
 */

const fecha = isoADiaMesAnio;

// ── Piezas ──────────────────────────────────────────────────────────────────

function Resumen({ seguro }: { seguro: MiSeguroCalculado }) {
  const nombre = seguro.tipo?.nombre ?? "";
  let insignia: ReactNode;
  let titulo: string;
  let detalle: string;

  switch (seguro.situacion) {
    case "sin_seguro":
      insignia = <Insignia variante="neutral">Sin seguro asignado</Insignia>;
      titulo = "No tienes un seguro asignado en el sistema";
      detalle = "Si crees que debería haber uno, avisa a Desarrollo Organizacional.";
      break;
    case "por_planilla":
      insignia = <Insignia variante="neutral">Por planilla</Insignia>;
      titulo = `Tu seguro es ${nombre}`;
      detalle = "Se paga por planilla y no lleva póliza.";
      break;
    case "hueco":
      insignia = <Insignia variante="alerta">Sin póliza vigente</Insignia>;
      if (seguro.motivoHueco === "nunca") {
        titulo = "Todavía no tienes una póliza registrada";
        detalle = `Tu seguro es ${nombre} y lleva póliza. Cuando Desarrollo Organizacional la registre, aquí vas a ver su número y tu PDF. Si crees que ya deberías tenerla, avísales.`;
      } else if (seguro.motivoHueco === "aun_no_empieza") {
        titulo = "Hoy no tienes una póliza vigente registrada";
        detalle = `La póliza de ${nombre} que está registrada a tu nombre empieza el ${fecha(seguro.empiezaEl!)}. Hasta entonces, avisa a Desarrollo Organizacional para que lo revise.`;
      } else {
        titulo = "Hoy no tienes una póliza vigente registrada";
        detalle =
          `Tu última póliza de ${nombre} dejó de cubrir el ${fecha(seguro.vencioEl!)}` +
          `${seguro.diasDesdeQueVencio ? ` (hace ${plural(seguro.diasDesdeQueVencio, "día", "días")})` : ""}.` +
          `${seguro.empiezaEl ? ` La que ya está registrada empieza el ${fecha(seguro.empiezaEl)}.` : ""}` +
          " Avisa a Desarrollo Organizacional para que lo revise.";
      }
      break;
    case "por_vencer":
      insignia = <Insignia variante="advertencia">Vence en {plural(seguro.diasParaQuedarSinSeguro ?? 0, "día", "días")}</Insignia>;
      titulo = "Tu póliza vence pronto";
      detalle = `Tu seguro es ${nombre}. Deja de cubrir el ${fecha(seguro.cubiertoHasta!)} a las 12 M y todavía no hay otra registrada que siga. Si se acerca la fecha y no la ves aquí, avisa a Desarrollo Organizacional.`;
      break;
    default:
      insignia = <Insignia variante="positivo">Al día</Insignia>;
      titulo = "Tu seguro está al día";
      detalle = `Tu seguro es ${nombre}. Tu póliza cubre hasta el ${fecha(seguro.cubiertoHasta!)} a las 12 M.${
        seguro.cubiertoHasta !== seguro.actual?.vigente_hasta ? " Ya está registrada la renovación que sigue." : ""
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
            {p.producto_nombre}
            <span className="font-normal text-taupe"> · póliza N.º </span>
            <span className="font-mono">{p.numero_poliza}</span>
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

function ComoUsarlo({ nombre, guia }: { nombre: string; guia: GuiaDeUso }) {
  return (
    <section className="rounded-2xl border border-sand p-5 text-sm">
      <h2 className="mb-1 font-serif text-lg">Cómo usar tu seguro ({nombre})</h2>
      <ul className="mt-3 space-y-3">
        {guia.pasos.map((paso) => (
          <li key={paso.clave}>
            <p className="font-medium text-tinta">{paso.titulo}</p>
            <p className="text-taupe">{paso.texto}</p>
          </li>
        ))}
        {guia.telefonos.length > 0 && (
          <li>
            <p className="font-medium text-tinta">Teléfonos de {guia.aseguradora}</p>
            <p className="text-taupe">
              {guia.telefonos.map((t, i) => (
                <span key={t}>
                  {i > 0 && " · "}
                  <a href={enlaceTelefono(t)} className="text-tinta underline underline-offset-2 hover:text-rojo-profundo">{t}</a>
                </span>
              ))}
            </p>
          </li>
        )}
      </ul>

      {guia.noCubre.length > 0 && (
        <>
          <h3 className="mb-1 mt-5 font-medium text-tinta">Lo que esta póliza no cubre</h3>
          <ul className="list-disc space-y-0.5 pl-5 text-taupe">
            {guia.noCubre.map((x) => <li key={x}>{x}</li>)}
          </ul>
        </>
      )}

      <p className="mt-5 border-t border-sand pt-3 text-xs text-taupe">
        Esto es un resumen. Lo que vale es tu póliza en PDF; si tienes dudas, llama a {guia.aseguradora} o pregunta
        a Desarrollo Organizacional.
      </p>
    </section>
  );
}

// ── La sección ──────────────────────────────────────────────────────────────

export function MiSeguro() {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const { avisar } = useToast();
  const [carga, setCarga] = useState<{ principal: SeguroPrincipal | null; polizas: PolizaMia[]; error: string | null } | null>(null);
  // UNA sola acción a la vez: mientras un archivo se abre o se baja, los demás botones esperan.
  const [ocupada, setOcupada] = useState<string | null>(null);

  useEffect(() => {
    let vivo = true;
    void traerMiSeguro(supabase).then((r) => { if (vivo) setCarga(r); });
    return () => { vivo = false; };
  }, [supabase]);

  const hoy = hoyLima();
  const seguro = useMemo(() => (carga ? resolverMiSeguro(carga.principal, carga.polizas, hoy) : null), [carga, hoy]);

  async function abrir(a: ArchivoMio) {
    setOcupada(`abrir:${a.id}`);
    // `abrirArchivoFirmado` abre la pestaña ANTES de esperar la firma, dentro del clic: ver el
    // comentario de ese archivo.
    const fallo = await abrirArchivoFirmado(supabase, BUCKET_SEGUROS, a.storage_path, 120);
    setOcupada(null);
    if (fallo) avisar("error", fallo);
  }

  async function descargar(p: PolizaMia, a: ArchivoMio) {
    setOcupada(`descargar:${a.id}`);
    const fallo = await descargarArchivoDeSeguro(supabase, a.storage_path, nombreDeDescarga(a, p));
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

  const poliza = (p: PolizaMia, esActual: boolean) => (
    <TarjetaPoliza key={p.poliza_id} p={p} hoy={hoy} esActual={esActual} ocupada={ocupada}
      onAbrir={(a) => void abrir(a)} onDescargar={(x, a) => void descargar(x, a)} />
  );
  const guias = guiasQueAplican(carga.polizas);

  return (
    <div className="space-y-4">
      <section className="rounded-2xl border border-sand p-5 text-sm">
        <h2 className="mb-1 font-serif text-lg">Mi seguro</h2>
        <p className="mb-4 text-taupe">En qué seguro estás y, si lleva póliza, lo que necesitas de ella.</p>
        <div className="space-y-3">
          <Resumen seguro={seguro} />
          {seguro.actual && poliza(seguro.actual, true)}
          {seguro.resto.length > 0 && (
            <>
              <h3 className="pt-2 font-medium text-tinta">{seguro.actual ? "Otras pólizas" : "Tus pólizas"}</h3>
              {seguro.resto.map((p) => poliza(p, false))}
            </>
          )}
        </div>
      </section>

      {guias.map((g) => <ComoUsarlo key={g.clave} nombre={g.nombre} guia={g.guia} />)}
    </div>
  );
}

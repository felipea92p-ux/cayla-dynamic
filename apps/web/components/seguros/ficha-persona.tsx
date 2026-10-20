"use client";

// ============================================================================
// La ficha de una persona en Seguros: su seguro de hoy, lo que le falta, y sus pólizas
// ============================================================================
// QUÉ PROMETE
//   Que de un vistazo se vea en qué seguro está esta persona y de dónde sale (su vínculo,
//   o una decisión de DO), si le falta una póliza que la cubra, qué cambios de seguro
//   tiene por cerrar, y sus pólizas: las que corren o van a correr a la vista, las que ya
//   terminaron plegadas.
//
//   Quien no tiene nada que registrar ni cerrar —alguien de planilla, cuyo EsSalud se
//   paga con la planilla— ocupa UNA línea: la lista tiene a todo el equipo y no puede
//   ahogar a las cinco o seis personas que sí piden algo.
//
// QUÉ NO HACE
//   No guarda nada ni abre diálogos: cada botón avisa por `acciones` y la pantalla abre
//   el que corresponde. Tampoco decide la situación de la persona: viene resuelta de
//   `seguroPorPersona`, que a su vez lee lo que dice la base.
// ============================================================================

import { ChevronDown, ChevronUp } from "lucide-react";
import { Boton } from "@/components/ui/boton";
import { BotonIcono } from "@/components/ui/boton-icono";
import { Insignia } from "@/components/ui/insignia";
import { isoADiaMesAnio } from "@/lib/admin/planilla/formato";
import {
  etiquetaVinculo, plural, type PasoSeguro, type Poliza, type SeguroDePersona, type TipoSeguro,
} from "@/lib/admin/seguros";
import { CambiosAnteriores, CambiosPendientes, type AlMarcarPasoDeCambio } from "./cambios-de-seguro";
import type { BaseDePoliza } from "./formulario-poliza";
import { TarjetaPoliza } from "./tarjeta-poliza";

const fecha = isoADiaMesAnio;

const MODALIDAD: Record<string, string> = { profesional: "Profesional", preprofesional: "Preprofesional" };

/** Todo lo que se puede hacer desde una ficha. La pantalla abre el diálogo de cada cosa. */
export interface AccionesFicha {
  registrar: (base: BaseDePoliza) => void;
  renovar: (p: SeguroDePersona) => void;
  cambiarSeguro: (p: SeguroDePersona) => void;
  paso: (z: Poliza, paso: PasoSeguro, quitar: boolean) => void;
  pasoDeCambio: AlMarcarPasoDeCambio;
  archivos: (z: Poliza) => void;
  historial: (z: Poliza) => void;
  corregir: (z: Poliza) => void;
  anular: (z: Poliza) => void;
}

function InsigniaSituacion({ p }: { p: SeguroDePersona }) {
  switch (p.situacion) {
    case "hueco": return <Insignia variante="alerta">Sin póliza vigente</Insignia>;
    case "suspendida": return <Insignia variante="alerta">Cobertura suspendida</Insignia>;
    case "por_vencer": return <Insignia variante="advertencia">Se queda sin póliza en {plural(p.diasParaQuedarSinSeguro ?? 0, "día", "días")}</Insignia>;
    case "baja_pendiente": return <Insignia variante="advertencia">Pedir la baja</Insignia>;
    case "por_planilla": return <Insignia variante="neutral">Sin póliza que registrar</Insignia>;
    case "sin_seguro": return <Insignia variante="neutral">Sin seguro que aplique</Insignia>;
    default: return <Insignia variante="positivo">Cubierto</Insignia>;
  }
}

/** «Seguro: FOLA · por su vínculo», o quién y por qué se lo cambió. */
function LineaSeguro({ p }: { p: SeguroDePersona }) {
  if (!p.tipo) {
    return <>Su vínculo ({etiquetaVinculo(p.vinculo)}) no lleva un seguro de la empresa.</>;
  }
  return (
    <>
      Seguro: <span className="text-tinta">{p.tipo.nombre}</span>
      {p.origen === "asignacion" && p.asignacion
        ? <> · lo asignó DO desde el {fecha(p.asignacion.desde)}: «{p.asignacion.motivo}»{p.automatico && <>. Por su vínculo le tocaría {p.automatico.nombre}</>}</>
        : <> · por su vínculo</>}
    </>
  );
}

function MensajeHueco({ p, hoy }: { p: SeguroDePersona; hoy: string }) {
  const nombre = p.tipo?.nombre ?? "su seguro";
  const ultima = p.polizasPrincipales.find((z) => z.vigente_hasta <= hoy);
  let texto: string;
  if (p.motivoHueco === "aun_no_empieza") {
    texto = `La póliza de ${nombre} que tiene registrada empieza el ${fecha(p.empiezaEl!)}; hasta entonces no tiene una póliza vigente.`;
  } else if (p.motivoHueco === "vencida" && ultima) {
    const d = p.diasDesdeQueVencio ?? 0;
    texto = `Su última póliza de ${nombre} dejó de cubrir ${d === 0 ? "hoy" : `el ${fecha(ultima.vigente_hasta)} (hace ${plural(d, "día", "días")})`}. Hoy no tiene una póliza vigente.`;
    if (p.empiezaEl) texto += ` La que ya está registrada empieza el ${fecha(p.empiezaEl)}.`;
  } else {
    texto = `Todavía no tiene una póliza de ${nombre} registrada.`;
  }
  return (
    <p className="rounded-lg bg-rojo/10 px-3 py-2 text-sm text-rojo-profundo">
      <span className="font-medium">{texto}</span>
      {p.vinculo === "practicante" && " No contratar el seguro de un practicante es infracción por sí sola (Ley 28518, art. 52.5)."}
    </p>
  );
}

function FichaAbierta({
  p, hoy, tipos, acciones, onCerrar,
}: {
  p: SeguroDePersona;
  hoy: string;
  tipos: TipoSeguro[];
  acciones: AccionesFicha;
  onCerrar: () => void;
}) {
  const tipo = tipos.find((t) => t.clave === p.tipo?.clave);
  const hayAdemas = tipos.some((t) => t.activo && t.con_poliza && !t.principal);
  const cabecera = (
    <>
      {p.persona} <span className="font-sans text-sm text-taupe">· {p.sede} · {etiquetaVinculo(p.vinculo)}{p.modalidad && ` · ${MODALIDAD[p.modalidad] ?? p.modalidad}`}</span>
    </>
  );

  // Nada que registrar ni cerrar: una línea.
  const compacta = (p.situacion === "por_planilla" || p.situacion === "sin_seguro")
    && p.cambios.length === 0 && p.polizasPrincipales.length === 0 && p.otras.length === 0;
  if (compacta) {
    return (
      <section className="flex flex-wrap items-center justify-between gap-2 rounded-2xl border border-sand bg-papel px-5 py-3">
        <div className="min-w-0">
          <h2 className="font-serif text-base text-tinta">{cabecera}</h2>
          <p className="text-sm text-taupe"><LineaSeguro p={p} /></p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <InsigniaSituacion p={p} />
          {p.activa && <Boton tamano="sm" onClick={() => acciones.cambiarSeguro(p)}>Cambiar su seguro</Boton>}
          <BotonIcono tamano="md" etiqueta={`Cerrar la ficha de ${p.persona}`} icono={<ChevronUp aria-hidden />} onClick={onCerrar} />
          {p.activa && hayAdemas && <Boton variante="sutil" tamano="sm" onClick={() => acciones.registrar({ personaId: p.personaId, soloAdemas: true })}>Registrar otro seguro</Boton>}
        </div>
      </section>
    );
  }

  // Lo que corre o va a correr, a la vista; lo que ya terminó, plegado. La póliza que habla
  // por la persona sale siempre, aunque esté vencida: es la que explica su hueco.
  const todas = [...p.polizasPrincipales, ...p.otras];
  const viva = (z: Poliza) => z.vigente_hasta > hoy;
  const aLaVista = todas.filter((z) => viva(z) || z.poliza_id === p.actual?.poliza_id);
  const plegadas = todas.filter((z) => !aLaVista.includes(z));
  const cierra = p.cambios.filter((c) => !c.baja_pendiente && !c.alta_pendiente);

  const tarjeta = (z: Poliza, destacada: boolean) => (
    <TarjetaPoliza
      key={z.poliza_id} z={z} hoy={hoy} destacada={destacada}
      onPaso={acciones.paso} onArchivos={acciones.archivos} onHistorial={acciones.historial}
      onCorregir={acciones.corregir} onAnular={acciones.anular}
    />
  );

  return (
    <section className="rounded-2xl border border-sand bg-papel">
      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-sand px-5 py-3">
        <h2 className="font-serif text-lg text-tinta">{cabecera}</h2>
        <span className="flex items-center gap-2">
          <InsigniaSituacion p={p} />
          <BotonIcono tamano="md" etiqueta={`Cerrar la ficha de ${p.persona}`} icono={<ChevronUp aria-hidden />} onClick={onCerrar} />
        </span>
      </div>
      <div className="space-y-3 px-5 py-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <p className="min-w-0 text-sm text-taupe"><LineaSeguro p={p} /></p>
          {p.activa && <Boton tamano="sm" onClick={() => acciones.cambiarSeguro(p)}>Cambiar su seguro</Boton>}
        </div>
        {tipo && !tipo.con_poliza && tipo.descripcion && <p className="text-sm text-taupe">{tipo.descripcion}</p>}

        {p.situacion === "hueco" && <MensajeHueco p={p} hoy={hoy} />}
        {p.situacion === "hueco" && p.tipo && (
          <div>
            <Boton variante="primario" tamano="sm" onClick={() => acciones.registrar({ personaId: p.personaId, producto: p.tipo!.clave })}>
              Registrar su póliza
            </Boton>
          </div>
        )}
        {p.situacion === "suspendida" && (
          <p className="rounded-lg bg-rojo/10 px-3 py-2 text-sm text-rojo-profundo">
            <span className="font-medium">La póliza figura vigente por sus fechas, pero la prima lleva más de 30 días sin pagarse y la cobertura se suspendió sola.</span>{" "}
            Hoy no cubre: paga la prima (convenio de pago, cláusula quinta) y márcala abajo.
          </p>
        )}
        {p.situacion === "por_vencer" && p.cubiertoHasta && (
          <p className="rounded-lg bg-ambar/10 px-3 py-2 text-sm text-ambar">
            Se queda sin póliza vigente el {fecha(p.cubiertoHasta)} y no hay una renovación registrada que empalme.{" "}
            <Boton variante="enlace" onClick={() => acciones.renovar(p)}>Registrar la renovación</Boton>
          </p>
        )}
        {p.situacion === "baja_pendiente" && (
          <p className="rounded-lg bg-ambar/10 px-3 py-2 text-sm text-ambar">
            Ya no está activa y su póliza sigue vigente: pídele la baja a la aseguradora y, cuando la confirme,
            corrige la fecha en que termina la póliza («Corregir datos») para que deje de avisar.
          </p>
        )}

        <CambiosPendientes cambios={p.cambiosPendientes} onPaso={acciones.pasoDeCambio} />

        {aLaVista.map((z) => tarjeta(z, z.poliza_id === p.actual?.poliza_id))}

        {plegadas.length > 0 && (
          <details className="text-sm">
            <summary className="cursor-pointer text-taupe">
              {plegadas.length === 1 ? "Una póliza anterior" : `${plegadas.length} pólizas anteriores`}
            </summary>
            <div className="mt-2 space-y-3">{plegadas.map((z) => tarjeta(z, false))}</div>
          </details>
        )}

        <CambiosAnteriores cambios={cierra} onPaso={acciones.pasoDeCambio} />

        {p.activa && (p.situacion === "al_dia" && p.cubiertoHasta || hayAdemas) && (
          <div className="flex flex-wrap gap-x-4 gap-y-1">
            {p.situacion === "al_dia" && p.cubiertoHasta && (
              <Boton variante="enlace" onClick={() => acciones.renovar(p)}>Registrar una renovación</Boton>
            )}
            {hayAdemas && (
              <Boton variante="enlace" onClick={() => acciones.registrar({ personaId: p.personaId, soloAdemas: true })}>Registrar otro seguro</Boton>
            )}
          </div>
        )}
      </div>
    </section>
  );
}

/** Cuántos pasos o cambios le piden algo a esta persona (lo que se resume en la fila cerrada). */
function pendientesDe(p: SeguroDePersona): number {
  return p.cambiosPendientes.length + p.conPapeleo.length;
}

/**
 * La ficha de una persona, PLEGABLE. Cerrada es UNA línea —nombre, seguro de hoy, situación y, si hay, cuántas cosas
 * le piden algo—; abierta es la ficha completa de siempre. Con 30 personas en 4 sedes, ver todo abierto ahogaba a
 * las pocas que sí piden algo.
 */
export function FichaPersona({
  p, hoy, tipos, acciones, abierta, onAlternar,
}: {
  p: SeguroDePersona;
  hoy: string;
  tipos: TipoSeguro[];
  acciones: AccionesFicha;
  abierta: boolean;
  onAlternar: () => void;
}) {
  if (abierta) return <FichaAbierta p={p} hoy={hoy} tipos={tipos} acciones={acciones} onCerrar={onAlternar} />;
  const pendientes = pendientesDe(p);
  return (
    <button
      type="button"
      aria-expanded={false}
      onClick={onAlternar}
      className="flex w-full items-center justify-between gap-3 rounded-superficie border border-sand bg-papel px-4 py-2.5 text-left transition-colors duration-150 hover:bg-hueso"
    >
      <span className="min-w-0">
        <span className="block truncate font-serif text-base text-tinta">
          {p.persona} <span className="font-sans text-sm text-taupe">· {etiquetaVinculo(p.vinculo)}{p.modalidad && ` · ${MODALIDAD[p.modalidad] ?? p.modalidad}`}</span>
        </span>
        <span className="block truncate text-sm text-taupe">{p.tipo ? `Seguro: ${p.tipo.nombre}` : `Su vínculo (${etiquetaVinculo(p.vinculo)}) no lleva un seguro de la empresa.`}</span>
      </span>
      <span className="flex shrink-0 items-center gap-2">
        {pendientes > 0 && <Insignia variante="advertencia" tamano="sm">{plural(pendientes, "pendiente", "pendientes")}</Insignia>}
        <InsigniaSituacion p={p} />
        <ChevronDown size={16} strokeWidth={1.8} className="text-taupe" aria-hidden />
      </span>
    </button>
  );
}

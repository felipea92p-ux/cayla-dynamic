"use client";

// ============================================================================
// Seguros — en qué seguro está cada colaborador, hasta cuándo está cubierto, y qué falta
// ============================================================================
// QUÉ PROMETE
//   Que Desarrollo Organizacional vea, en un minuto, en qué seguro está cada
//   colaborador, quién NO tiene la póliza que su seguro pide, a quién se le vence
//   pronto, qué papeleo falta (prima, firma, factura), qué cambios de seguro quedan por
//   cerrar y dónde están los PDF. Migración 0528.
//
// UN SEGURO POR VÍNCULO, Y DO PUEDE CAMBIÁRSELO A UNA PERSONA (Felipe, 2026-10-17)
//   El seguro de cada persona sale solo de su vínculo (los practicantes tienen FOLA; la
//   planilla y la prueba, EsSalud, que se paga con la planilla y Dynamic solo muestra).
//   Cuando DO sabe que alguien está en otro, se lo cambia a esa persona. Los seguros no
//   están escritos aquí: viven en una tabla (`seguros_tipos`) y DO agrega los que falten
//   desde «Tipos de seguro». Cuando alguien cambia de seguro —por su vínculo o por DO—
//   quedan dos pendientes: la baja del anterior y el alta del nuevo.
//
// QUÉ ASUME
//   Que la base decide lo que importa: en qué seguro está cada persona, quién tiene que
//   tener póliza (`hueco`), si una póliza cubre hoy (`cubre_hoy`, con el último día
//   EXCLUSIVO), qué pasos de un cambio siguen pendientes y quién puede escribir (solo DO,
//   por funciones). Esta pantalla solo dibuja y pide; `puedeGestionarSeguros` decide si
//   se dibuja. La lógica de agrupar y de qué cuenta como «por vencer» vive en
//   `lib/admin/seguros.ts`, con su prueba.
//
// SOLO ALERTA
//   Nada de aquí cambia lo que cobra o paga nadie ni toca la planilla: la prima se paga
//   a la aseguradora y EsSalud sigue como estaba. La pantalla avisa; las decisiones son
//   de una persona.
// ============================================================================

import { Suspense, useCallback, useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { SlidersHorizontal, X } from "lucide-react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { hoyLima, puedeExportarListaDeAsegurados, puedeGestionarSeguros } from "@cayla-dynamic/shared";
import { Cargando } from "@/components/cargando";
import { ArchivosPoliza, type PolizaHermana } from "@/components/seguros/archivos-poliza";
import { AyudaDeSeguros } from "@/components/seguros/ayuda-de-seguros";
import { CambiarSeguro } from "@/components/seguros/cambiar-seguro";
import { FichaPersona, type AccionesFicha } from "@/components/seguros/ficha-persona";
import { FormularioPoliza, type BaseDePoliza, type OpcionPersona } from "@/components/seguros/formulario-poliza";
import { HistorialPoliza } from "@/components/seguros/historial-poliza";
import { LeerPdfDePoliza } from "@/components/seguros/leer-pdf-de-poliza";
import { ListaDeAsegurados } from "@/components/seguros/lista-de-asegurados";
import { ModalPaso, type PasoPorMarcar } from "@/components/seguros/modal-paso";
import { TiposDeSeguro } from "@/components/seguros/tipos-de-seguro";
import { useToast } from "@/components/toast";
import { AreaTexto } from "@/components/ui/area-texto";
import { Boton } from "@/components/ui/boton";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { Campo } from "@/components/ui/campo";
import { EstadoVacio } from "@/components/ui/estado-vacio";
import { Filtro as FiltroBoton } from "@/components/ui/filtro";
import { Modal } from "@/components/ui/modal";
import { Rotulo } from "@/components/ui/rotulo";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { useRolActual } from "@/lib/admin/use-rol";
import {
  coincideSeguro, contarPorTipo, fechaDelPaso, hermanasDe, plural, resumenDeSeguros, seguroPorPersona, DIAS_AVISO_RENOVACION, PASOS_SEGURO,
  type CambioSeguro, type FilaEquipoSeguro, type PasoSeguro, type Poliza, type SeguroDePersona, type SituacionSeguro, type TipoSeguro,
} from "@/lib/admin/seguros";

/** Qué botón de situación filtra la lista. */
type Filtro = SituacionSeguro | "papeleo" | "cambios";

/**
 * Los dos valores del filtro por seguro que no son un seguro. Llevan «*»: las claves de los
 * seguros salen del nombre en minúsculas, cifras y guiones bajos (`fn_seguro_tipo_crear`),
 * así que un seguro que DO llame «Todos» o «Ninguno» no puede chocar con ellos.
 */
const TODOS = "*todos";
const NINGUNO = "*ninguno";

/** Lo que se está marcando: un paso del papeleo de una póliza, o un paso de un cambio de seguro. */
type PasoAbierto =
  | { cual: "poliza"; z: Poliza; paso: PasoSeguro; quitar: boolean }
  | { cual: "cambio"; c: CambioSeguro; paso: "baja" | "alta"; quitar: boolean };

/** Un filtro puesto, a la vista aunque el panel esté cerrado: se quita con un toque. */
function FiltroPuesto({ etiqueta, onQuitar }: { etiqueta: string; onQuitar: () => void }) {
  return (
    <button
      type="button"
      onClick={onQuitar}
      aria-label={`Quitar el filtro: ${etiqueta}`}
      className="inline-flex items-center gap-1.5 rounded-control border border-tinta bg-tinta px-3 py-1 text-xs font-medium text-crema"
    >
      {etiqueta}
      <X className="size-3" aria-hidden />
    </button>
  );
}

export default function SegurosPage() {
  // `useSearchParams` pide un límite de Suspense para que la página pueda prerenderse.
  return (
    <Suspense fallback={<main className="flex-1 p-6"><Cargando /></main>}>
      <Seguros />
    </Suspense>
  );
}

function Seguros() {
  const router = useRouter();
  // La Bandeja manda aquí con `?persona=<id>`: la pantalla abre ya parada en esa persona.
  const soloPersona = useSearchParams().get("persona");
  const rol = useRolActual();
  const puede = puedeGestionarSeguros(rol);
  const { avisar } = useToast();
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const hoy = hoyLima();

  const [equipo, setEquipo] = useState<FilaEquipoSeguro[]>([]);
  const [polizas, setPolizas] = useState<Poliza[]>([]);
  const [cambios, setCambios] = useState<CambioSeguro[]>([]);
  const [tipos, setTipos] = useState<TipoSeguro[]>([]);
  const [cargando, setCargando] = useState(true);
  const [cargaError, setCargaError] = useState<string | null>(null);
  const [busqueda, setBusqueda] = useState("");
  const [filtro, setFiltro] = useState<Filtro | null>(null);
  const [tipoFiltro, setTipoFiltro] = useState<string>(TODOS);
  // Los filtros viven detrás de un botón y la pantalla abre limpia, sin filas de botones encima de la lista.
  const [filtrosAbiertos, setFiltrosAbiertos] = useState(false);

  const cargar = useCallback(async () => {
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    const [e, z, c, t] = await Promise.all([
      supabase.rpc("fn_seguros_equipo"),
      supabase.rpc("fn_seguros_tablero"),
      supabase.rpc("fn_seguros_cambios", { p_solo_pendientes: false }),
      supabase.rpc("fn_seguros_tipos"),
    ]);
    // Las cuatro o ninguna: una pantalla con la mitad (sin las pólizas, o sin los cambios) diría «sin póliza» donde sí la hay.
    const error = e.error ?? z.error ?? c.error ?? t.error;
    if (error) {
      setCargaError(mensajeDeError(error, "cargar los seguros"));
    } else {
      setEquipo((e.data as FilaEquipoSeguro[] | null) ?? []);
      setPolizas((z.data as Poliza[] | null) ?? []);
      setCambios((c.data as CambioSeguro[] | null) ?? []);
      setTipos((t.data as TipoSeguro[] | null) ?? []);
      setCargaError(null);
    }
    setCargando(false);
  }, [supabase, router]);

  // `cargar` solo pone estado después de sus `await` (la sesión, la base): no
  // hay renders en cascada. Mismo patrón que /admin/archivo.
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { if (puede) void cargar(); }, [puede, cargar]);

  const personas = useMemo(() => seguroPorPersona(equipo, polizas, cambios, hoy), [equipo, polizas, cambios, hoy]);
  const resumen = useMemo(() => resumenDeSeguros(personas), [personas]);
  const personaDelAviso = useMemo(() => (soloPersona ? personas.find((p) => p.personaId === soloPersona) ?? null : null), [personas, soloPersona]);
  const porTipo = useMemo(() => contarPorTipo(personas, tipos), [personas, tipos]);

  // A quién se le puede registrar una póliza: las personas activas, con su seguro principal de hoy.
  const opciones = useMemo<OpcionPersona[]>(
    () => personas.filter((p) => p.activa)
      .map((p) => ({ id: p.personaId, nombre: p.persona, sede: p.sede, tipoPrincipal: p.tipo?.clave ?? null, enPlanilla: p.enPlanilla, vinculo: p.vinculo }))
      .sort((a, b) => a.nombre.localeCompare(b.nombre, "es")),
    [personas],
  );

  // Los botones «Piden la baja» y «Cobertura suspendida» solo existen mientras hay alguien: si se
  // corrige el último caso con ese filtro puesto, el filtro se suelta solo (sin esto la lista quedaba
  // vacía, diciendo «nadie coincide», con ningún botón marcado).
  const filtroVigente = (filtro === "baja_pendiente" && resumen.baja_pendiente === 0) || (filtro === "suspendida" && resumen.suspendida === 0)
    ? null : filtro;

  const visibles = useMemo(() => personas.filter((p) => {
    if (soloPersona && p.personaId !== soloPersona) return false;
    if (!coincideSeguro(p, busqueda)) return false;
    if (tipoFiltro === NINGUNO ? p.tipo !== null : tipoFiltro !== TODOS && p.tipo?.clave !== tipoFiltro) return false;
    if (filtroVigente === null) return true;
    if (filtroVigente === "papeleo") return p.conPapeleo.length > 0;
    if (filtroVigente === "cambios") return p.cambiosPendientes.length > 0;
    return p.situacion === filtroVigente;
  }), [personas, busqueda, filtroVigente, tipoFiltro, soloPersona]);

  // ── Registrar, renovar y corregir una póliza ──────────────────────────
  const [formAbierto, setFormAbierto] = useState(false);
  const [corrigiendo, setCorrigiendo] = useState<Poliza | null>(null);
  const [base, setBase] = useState<BaseDePoliza | null>(null);

  function registrar(b: BaseDePoliza | null) { setCorrigiendo(null); setBase(b); setFormAbierto(true); }
  function renovar(p: SeguroDePersona) {
    const a = p.actual;
    registrar({
      personaId: p.personaId, producto: p.tipo?.clave, aseguradora: a?.aseguradora, numeroPoliza: a?.numero_poliza,
      // Empieza donde termina la cobertura: si se pone el mismo día no hay hueco ni cruce.
      desde: p.cubiertoHasta ?? undefined, prima: a?.prima_total ?? null,
    });
  }

  // ── Archivos e historial ──────────────────────────────────────────────
  const [verArchivos, setVerArchivos] = useState<{ id: string; titulo: string } | null>(null);
  // Las otras pólizas de la misma póliza colectiva: el archivo que se suba puede guardarse también en ellas.
  const hermanasDelArchivo = useMemo<PolizaHermana[]>(() => {
    const z = verArchivos ? polizas.find((x) => x.poliza_id === verArchivos.id) : undefined;
    return z ? hermanasDe(z, polizas).map((h) => ({ id: h.poliza_id, titulo: h.persona })) : [];
  }, [verArchivos, polizas]);
  const [verHistorial, setVerHistorial] = useState<{ id: string; titulo: string } | null>(null);
  const nombreDe = (z: Poliza) => `${z.persona} · ${z.producto_nombre} · póliza ${z.numero_poliza}`;

  // ── Marcar un paso (del papeleo de una póliza, o de un cambio de seguro) ──
  const [paso, setPaso] = useState<PasoAbierto | null>(null);

  const pasoPorMarcar = useMemo<PasoPorMarcar | null>(() => {
    if (!paso) return null;
    if (paso.cual === "poliza") {
      return {
        detalle: `${PASOS_SEGURO.find((s) => s.paso === paso.paso)?.hecho} — ${paso.z.producto_nombre}, póliza ${paso.z.numero_poliza} de ${paso.z.persona}.`,
        quitar: paso.quitar, fechaActual: fechaDelPaso(paso.z, paso.paso), ejemploDeMotivo: "ej. Era el pago de otra póliza",
      };
    }
    return {
      detalle: `${paso.paso === "baja" ? paso.c.baja_texto : paso.c.alta_texto} — ${paso.c.persona}.`,
      quitar: paso.quitar, fechaActual: paso.paso === "baja" ? paso.c.baja_hecha_el : paso.c.alta_hecha_el,
      ejemploDeMotivo: "ej. Lo marqué por error: todavía no llegó la confirmación",
    };
  }, [paso]);

  async function confirmarPaso(fecha: string | null, motivo: string): Promise<string | null> {
    if (!paso) return null;
    const { error } = paso.cual === "poliza"
      ? await supabase.rpc("fn_seguro_marcar_paso", { p_id: paso.z.poliza_id, p_paso: paso.paso, p_fecha: fecha, p_motivo: fecha === null ? motivo : null })
      : await supabase.rpc("fn_seguro_cambio_marcar", { p_id: paso.c.id, p_paso: paso.paso, p_fecha: fecha, p_nota: fecha === null ? motivo : null });
    if (error) return mensajeDeError(error);
    const quito = paso.quitar;
    setPaso(null);
    await cargar();
    avisar("ok", quito ? "Marca quitada. Quedó anotado." : "Listo.");
    return null;
  }

  // ── Anular ────────────────────────────────────────────────────────────
  const [anulando, setAnulando] = useState<Poliza | null>(null);
  const [motivoAnular, setMotivoAnular] = useState("");
  const [msgAnular, setMsgAnular] = useState<string | null>(null);
  const [ocupadoAnular, setOcupadoAnular] = useState(false);

  async function confirmarAnular() {
    if (!anulando) return;
    if (motivoAnular.trim().length < 5) { setMsgAnular("Escribe el motivo (al menos 5 letras)."); return; }
    setOcupadoAnular(true);
    const { error } = await supabase.rpc("fn_seguro_anular", { p_id: anulando.poliza_id, p_motivo: motivoAnular.trim() });
    setOcupadoAnular(false);
    if (error) { setMsgAnular(mensajeDeError(error)); return; }
    setAnulando(null);
    await cargar();
    avisar("ok", "Póliza anulada. No se borró: queda en su historial.");
  }

  // ── Cambiar el seguro de una persona y administrar los tipos ──────────
  const [cambiando, setCambiando] = useState<SeguroDePersona | null>(null);
  const [tiposAbierto, setTiposAbierto] = useState(false);
  const [listaAbierta, setListaAbierta] = useState(false);
  const [leerAbierto, setLeerAbierto] = useState(false);

  const acciones: AccionesFicha = {
    registrar, renovar,
    cambiarSeguro: setCambiando,
    paso: (z, p, quitar) => setPaso({ cual: "poliza", z, paso: p, quitar }),
    pasoDeCambio: (c, p, quitar) => setPaso({ cual: "cambio", c, paso: p, quitar }),
    archivos: (z) => setVerArchivos({ id: z.poliza_id, titulo: nombreDe(z) }),
    historial: (z) => setVerHistorial({ id: z.poliza_id, titulo: nombreDe(z) }),
    corregir: (z) => { setCorrigiendo(z); setBase(null); setFormAbierto(true); },
    anular: (z) => { setAnulando(z); setMotivoAnular(""); setMsgAnular(null); },
  };

  // ── Dibujo ────────────────────────────────────────────────────────────
  if (rol === null) return <main className="flex-1 p-6"><Cargando /></main>;
  if (!puede) {
    return (
      <main className="flex-1 p-6">
        <div className="max-w-2xl rounded-lg bg-ambar/15 px-4 py-3 text-sm text-ambar">
          Los seguros del equipo solo los ve Desarrollo Organizacional.
        </div>
      </main>
    );
  }

  // Los filtros de situación, en el orden de lo más serio a lo menos. El número es el de FILAS que
  // deja ver: una persona cuenta una vez. Qué quiere decir cada uno está en la ayuda del título.
  const situaciones: { clave: Filtro; etiqueta: string; n: number }[] = [
    { clave: "hueco", etiqueta: "Sin póliza vigente", n: resumen.hueco },
    ...(resumen.suspendida > 0 ? [{ clave: "suspendida" as const, etiqueta: "Cobertura suspendida", n: resumen.suspendida }] : []),
    { clave: "por_vencer", etiqueta: `Por vencer (${DIAS_AVISO_RENOVACION} días)`, n: resumen.por_vencer },
    { clave: "cambios", etiqueta: "Cambios por cerrar", n: resumen.cambios },
    { clave: "papeleo", etiqueta: "Papeleo pendiente", n: resumen.papeleo },
    ...(resumen.baja_pendiente > 0 ? [{ clave: "baja_pendiente" as const, etiqueta: "Piden la baja", n: resumen.baja_pendiente }] : []),
    { clave: "al_dia", etiqueta: "Cubiertos", n: resumen.al_dia },
    { clave: "por_planilla", etiqueta: "Sin póliza que registrar", n: resumen.por_planilla },
  ];

  const etiquetaDeSituacion = situaciones.find((f) => f.clave === filtroVigente)?.etiqueta ?? null;
  const etiquetaDeSeguro = tipoFiltro === TODOS ? null : tipoFiltro === NINGUNO ? "Sin seguro (no aplica)" : porTipo.find((t) => t.clave === tipoFiltro)?.nombre ?? tipoFiltro;
  const nFiltros = (etiquetaDeSituacion ? 1 : 0) + (etiquetaDeSeguro ? 1 : 0);
  const limpiarFiltros = () => { setFiltro(null); setTipoFiltro(TODOS); };

  return (
    <main className="flex-1 p-6">
      <CabeceraPagina
        titulo="Seguros"
        descripcion="En qué seguro está cada colaborador y qué falta para que esté cubierto."
        ayuda={<AyudaDeSeguros />}
        accion={!cargaError && (
          <div className="flex flex-wrap gap-2">
            <Boton onClick={() => setLeerAbierto(true)}>Leer PDF de póliza</Boton>
            <Boton onClick={() => setListaAbierta(true)}>Lista de asegurados</Boton>
            <Boton onClick={() => setTiposAbierto(true)}>Tipos de seguro</Boton>
            <Boton variante="primario" onClick={() => registrar(null)}>+ Registrar una póliza</Boton>
          </div>
        )}
      />

      {cargaError && (
        <div className="mb-4 max-w-3xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
          {cargaError} <Boton variante="enlace" onClick={() => void cargar()}>Reintentar</Boton>
        </div>
      )}

      {cargando ? <Cargando /> : !cargaError && (
        <>
          {personas.length === 0 ? (
            <EstadoVacio>Todavía no hay colaboradores en el sistema a quienes mostrarles un seguro.</EstadoVacio>
          ) : (
            <>
              {soloPersona && (
                <div className="mb-4 flex max-w-3xl flex-wrap items-center gap-3 rounded-lg bg-hueso px-4 py-3 text-sm text-tinta">
                  <span>
                    {personaDelAviso
                      ? `Mostrando solo a ${personaDelAviso.persona}, que es a quien lleva el aviso.`
                      : "Esa persona ya no aparece en Seguros: no tiene un seguro ni una póliza vigente que mostrar."}
                  </span>
                  <Boton variante="enlace" onClick={() => router.replace("/admin/seguros")}>Ver a todos</Boton>
                </div>
              )}

              <div className="mb-3 flex flex-wrap items-end gap-3">
                <div className="min-w-44 max-w-md flex-1 basis-40">
                  <Campo etiqueta="Buscar" value={busqueda} onChange={(e) => setBusqueda(e.target.value)} placeholder="Nombre, seguro, número de póliza, aseguradora o sede" />
                </div>
                <Boton
                  variante="secundario" aria-expanded={filtrosAbiertos} aria-controls="filtros-de-seguros"
                  onClick={() => setFiltrosAbiertos((a) => !a)} className="inline-flex items-center gap-1.5"
                >
                  <SlidersHorizontal className="size-4" aria-hidden />
                  Filtros{nFiltros > 0 && <span className="rounded-full bg-tinta px-1.5 text-[11px] leading-4 text-crema">{nFiltros}</span>}
                </Boton>
              </div>

              {nFiltros > 0 && (
                <div className="mb-3 flex flex-wrap items-center gap-2">
                  {etiquetaDeSituacion && <FiltroPuesto etiqueta={etiquetaDeSituacion} onQuitar={() => setFiltro(null)} />}
                  {etiquetaDeSeguro && <FiltroPuesto etiqueta={etiquetaDeSeguro} onQuitar={() => setTipoFiltro(TODOS)} />}
                  <Boton variante="enlace" className="text-sm" onClick={limpiarFiltros}>Limpiar filtros</Boton>
                </div>
              )}

              {filtrosAbiertos && (
                <div id="filtros-de-seguros" className="mb-4 space-y-4 rounded-superficie border border-sand bg-papel p-4">
                  <div>
                    <Rotulo className="mb-2">Situación</Rotulo>
                    <div role="group" aria-label="Filtrar por situación" className="flex flex-wrap gap-2">
                      {situaciones.map((f) => {
                        const activa = filtroVigente === f.clave;
                        return (
                          <FiltroBoton key={f.clave} activo={activa} onClick={() => setFiltro(activa ? null : f.clave)}>
                            {f.etiqueta} · {f.n}
                          </FiltroBoton>
                        );
                      })}
                    </div>
                  </div>
                  <div>
                    <Rotulo className="mb-2">Seguro</Rotulo>
                    <div role="group" aria-label="Filtrar por seguro" className="flex flex-wrap gap-2">
                      <FiltroBoton activo={tipoFiltro === TODOS} onClick={() => setTipoFiltro(TODOS)}>Todos · {personas.length}</FiltroBoton>
                      {porTipo.map((t) => {
                        const clave = t.clave ?? NINGUNO;
                        return <FiltroBoton key={clave} activo={tipoFiltro === clave} onClick={() => setTipoFiltro(clave)}>{t.nombre} · {t.n}</FiltroBoton>;
                      })}
                    </div>
                  </div>
                  <div className="flex justify-end gap-4 text-sm">
                    {nFiltros > 0 && <Boton variante="enlace" onClick={limpiarFiltros}>Limpiar filtros</Boton>}
                    <Boton variante="enlace" onClick={() => setFiltrosAbiertos(false)}>Cerrar</Boton>
                  </div>
                </div>
              )}

              {visibles.length === 0 && (!soloPersona || personaDelAviso) && (
                <p className="text-sm text-taupe">Nadie coincide con ese filtro{busqueda ? ` y con «${busqueda}»` : ""}.</p>
              )}

              <div className="space-y-3">
                {visibles.map((p) => <FichaPersona key={p.personaId} p={p} hoy={hoy} tipos={tipos} acciones={acciones} />)}
              </div>
            </>
          )}
        </>
      )}

      <FormularioPoliza
        abierto={formAbierto}
        onCerrar={() => setFormAbierto(false)}
        supabase={supabase}
        tipos={tipos}
        personas={opciones}
        polizas={polizas}
        corrigiendo={corrigiendo}
        base={base}
        onGuardado={async (id, nueva, titulo) => {
          setFormAbierto(false);
          await cargar();
          if (nueva) {
            avisar("ok", "Póliza registrada. Adjunta ahora el PDF de la póliza y el convenio de pago.");
            setVerArchivos({ id, titulo });
          } else {
            avisar("ok", "Corrección guardada. El historial dice qué decía antes.");
          }
        }}
        onGuardadoVarias={async (registradas, resumen) => {
          setFormAbierto(false);
          await cargar();
          // El PDF es uno solo para todas: se abre el de la primera persona (por nombre) y desde ahí se
          // guarda también en las demás (`hermanas`).
          const primera = [...registradas]
            .map((r) => ({ ...r, nombre: opciones.find((o) => o.id === r.persona_id)?.nombre ?? "" }))
            .sort((a, b) => a.nombre.localeCompare(b.nombre, "es") || a.persona_id.localeCompare(b.persona_id))[0];
          avisar("ok", `Póliza ${resumen.numero} (${resumen.seguro}) registrada a ${plural(registradas.length, "persona", "personas")}. Adjunta ahora el PDF: se guarda en todas.`);
          if (primera) setVerArchivos({ id: primera.poliza_id, titulo: `${primera.nombre} · ${resumen.seguro} · póliza ${resumen.numero}` });
        }}
      />

      <ArchivosPoliza
        abierto={verArchivos !== null}
        onCerrar={() => setVerArchivos(null)}
        supabase={supabase}
        polizaId={verArchivos?.id ?? null}
        titulo={verArchivos?.titulo ?? ""}
        hermanas={hermanasDelArchivo}
        onCambio={() => void cargar()}
      />

      <HistorialPoliza
        abierto={verHistorial !== null}
        onCerrar={() => setVerHistorial(null)}
        supabase={supabase}
        polizaId={verHistorial?.id ?? null}
        titulo={verHistorial?.titulo ?? ""}
      />

      <CambiarSeguro
        persona={cambiando}
        tipos={tipos}
        supabase={supabase}
        hoy={hoy}
        onCerrar={() => setCambiando(null)}
        onListo={(mensaje) => { setCambiando(null); void cargar(); avisar("ok", mensaje); }}
      />

      <LeerPdfDePoliza
        abierto={leerAbierto}
        onCerrar={() => setLeerAbierto(false)}
        supabase={supabase}
        tipos={tipos}
        personas={opciones}
        polizas={polizas}
        hoy={hoy}
        onRegistradas={async (cuantas, fallaron) => {
          await cargar();
          // Un solo aviso: si algunas quedaron y otras no, se dice de las dos (la tarjeta de cada una explica por qué).
          const partes = [
            ...(cuantas > 0 ? [plural(cuantas, "póliza registrada", "pólizas registradas")] : []),
            ...(fallaron > 0 ? [`${plural(fallaron, "no se pudo registrar", "no se pudieron registrar")} (cada tarjeta dice por qué)`] : []),
          ];
          if (partes.length > 0) avisar(fallaron > 0 ? "error" : "ok", `${partes.join("; ")}.`);
        }}
      />

      <ListaDeAsegurados
        abierto={listaAbierta}
        onCerrar={() => setListaAbierta(false)}
        supabase={supabase}
        tipos={tipos}
        inicial={tipoFiltro !== TODOS && tipoFiltro !== NINGUNO ? tipoFiltro : null}
        puedeDescargar={puedeExportarListaDeAsegurados(rol)}
        hoy={hoy}
      />

      <TiposDeSeguro
        abierto={tiposAbierto}
        onCerrar={() => setTiposAbierto(false)}
        supabase={supabase}
        tipos={tipos}
        onCambio={async (mensaje) => { await cargar(); avisar("ok", mensaje); }}
      />

      <ModalPaso paso={pasoPorMarcar} hoy={hoy} onCerrar={() => setPaso(null)} onConfirmar={confirmarPaso} />

      {/* ── Anular ──────────────────────────────────────────────────────── */}
      <Modal
        abierto={anulando !== null}
        onCerrar={() => { if (!ocupadoAnular) setAnulando(null); }}
        bloqueado={ocupadoAnular}
        titulo="Anular una póliza"
        ancho="sm"
      >
        {anulando && (
          <>
            <p className="mb-3 text-sm text-taupe">
              La póliza {anulando.producto_nombre} {anulando.numero_poliza} de {anulando.persona} deja de contar para la
              cobertura y desaparece de esta lista, pero no se borra: queda anulada con tu nombre y este motivo. Úsalo solo
              para una póliza registrada por error. Si cambió un dato, usa «Corregir datos».
            </p>
            <label className="flex flex-col gap-1">
              <span className="text-sm text-taupe">Por qué se anula</span>
              <AreaTexto
                value={motivoAnular}
                onChange={(e) => { setMotivoAnular(e.target.value); setMsgAnular(null); }}
                placeholder="ej. La registré a la persona equivocada"
                className={msgAnular ? "border-rojo" : undefined}
              />
              {msgAnular && <span className="text-xs text-rojo">{msgAnular}</span>}
            </label>
            <div className="mt-4 flex justify-end gap-2">
              <Boton onClick={() => setAnulando(null)} disabled={ocupadoAnular}>Cancelar</Boton>
              <Boton variante="peligro" onClick={() => void confirmarAnular()} cargando={ocupadoAnular}>Sí, anular</Boton>
            </div>
          </>
        )}
      </Modal>
    </main>
  );
}

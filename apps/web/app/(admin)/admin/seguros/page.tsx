"use client";

// ============================================================================
// Seguros — la póliza de salud de los practicantes (FOLA) y quién está cubierto hoy
// ============================================================================
// QUÉ PROMETE
//   Que Desarrollo Organizacional vea, en un minuto, quién de los practicantes
//   tiene seguro HOY, hasta cuándo, qué papeleo falta (prima, firma, factura) y
//   dónde están los PDF —y, sobre todo, quién NO lo tiene—. Migración 0528.
//
// QUÉ ASUME
//   Que la base decide lo que importa: quién tiene que tener póliza
//   (`es_practicante_activo`, y la fila SIN póliza de `fn_seguros_tablero`), si una
//   póliza cubre hoy (`cubre_hoy`, con el último día EXCLUSIVO) y quién puede
//   escribir (solo DO, por funciones). Esta pantalla solo dibuja y pide;
//   `puedeGestionarSeguros` decide si se dibuja. La lógica de agrupar y de qué
//   cuenta como «por vencer» vive en `lib/admin/seguros.ts`, con su prueba.
//
// SOLO ALERTA
//   Nada de aquí cambia lo que cobra o paga nadie ni toca la planilla: la prima se
//   paga a la aseguradora. La pantalla avisa; las decisiones son de una persona.
// ============================================================================

import { Suspense, useCallback, useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { hoyLima, puedeGestionarSeguros } from "@cayla-dynamic/shared";
import { Cargando } from "@/components/cargando";
import { ArchivosPoliza } from "@/components/seguros/archivos-poliza";
import { FormularioPoliza, type BaseDePoliza, type OpcionPersona } from "@/components/seguros/formulario-poliza";
import { HistorialPoliza } from "@/components/seguros/historial-poliza";
import { useToast } from "@/components/toast";
import { AreaTexto } from "@/components/ui/area-texto";
import { Boton } from "@/components/ui/boton";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { Campo } from "@/components/ui/campo";
import { Insignia } from "@/components/ui/insignia";
import { Modal } from "@/components/ui/modal";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { isoADiaMesAnio } from "@/lib/admin/planilla/formato";
import { useRolActual } from "@/lib/admin/use-rol";
import { diasEntre } from "@/lib/bandeja-mia";
import { formatSoles } from "@/lib/rangos";
import {
  coincideSeguro, estadoPrima, fechaDelPaso, pasosPendientes, PASOS_SEGURO, polizasConPapeleoPendiente,
  resumenDeSeguros, seguroPorPersona, DIAS_AVISO_RENOVACION,
  type FilaSeguro, type PasoSeguro, type Poliza, type SeguroDePersona, type SituacionSeguro,
} from "@/lib/admin/seguros";

type Filtro = SituacionSeguro | "papeleo";

const fecha = isoADiaMesAnio;
const plural = (n: number, uno: string, varios: string) => `${n} ${n === 1 ? uno : varios}`;

const MODALIDAD: Record<string, string> = { profesional: "Profesional", preprofesional: "Preprofesional" };

// ── Piezas chicas ───────────────────────────────────────────────────────────

function InsigniaSituacion({ p }: { p: SeguroDePersona }) {
  switch (p.situacion) {
    case "hueco": return <Insignia variante="alerta">Sin seguro hoy</Insignia>;
    case "por_vencer": return <Insignia variante="advertencia">Se queda sin seguro en {plural(p.diasParaQuedarSinSeguro ?? 0, "día", "días")}</Insignia>;
    case "baja_pendiente": return <Insignia variante="advertencia">Pedir la baja</Insignia>;
    default: return <Insignia variante="positivo">Cubierto</Insignia>;
  }
}

function InsigniaPrima({ z, hoy }: { z: Poliza; hoy: string }) {
  const { estado, dias } = estadoPrima(z, hoy);
  switch (estado) {
    case "pagada": return <Insignia variante="positivo" tamano="sm">Pagada el {fecha(z.pagada_el!)}</Insignia>;
    case "sin_fecha": return <Insignia variante="neutral" tamano="sm">Sin pagar · sin fecha de vencimiento</Insignia>;
    case "al_dia": return <Insignia variante="neutral" tamano="sm">Sin pagar · vence el {fecha(z.prima_vence_el!)}</Insignia>;
    case "por_vencer": return <Insignia variante="advertencia" tamano="sm">{dias === 0 ? "Vence hoy" : `Vence en ${plural(dias ?? 0, "día", "días")}`}</Insignia>;
    case "en_mora": return <Insignia variante="alerta" tamano="sm">En mora hace {plural(-(dias ?? 0), "día", "días")}</Insignia>;
    default: return <Insignia variante="alerta" tamano="sm">Cobertura suspendida por mora</Insignia>;
  }
}

function MensajeHueco({ p, hoy }: { p: SeguroDePersona; hoy: string }) {
  const ultima = p.polizas.find((z) => z.vigente_hasta <= hoy);
  let texto: string;
  if (p.motivoHueco === "aun_no_empieza") {
    texto = `La póliza que tiene registrada empieza el ${fecha(p.empiezaEl!)}; hasta entonces no tiene seguro.`;
  } else if (p.motivoHueco === "vencida" && ultima) {
    const d = p.diasDesdeQueVencio ?? 0;
    texto = `Su última póliza dejó de cubrir ${d === 0 ? "hoy" : `el ${fecha(ultima.vigente_hasta)} (hace ${plural(d, "día", "días")})`}. Hoy no tiene seguro.`;
    if (p.empiezaEl) texto += ` La que ya está registrada empieza el ${fecha(p.empiezaEl)}.`;
  } else {
    texto = "Nunca tuvo una póliza registrada. Hoy no tiene ningún seguro.";
  }
  return (
    <p className="rounded-lg bg-rojo/10 px-3 py-2 text-sm text-rojo-profundo">
      <span className="font-medium">{texto}</span> No contratar el seguro de un practicante es infracción por sí sola (Ley 28518, art. 52.5).
    </p>
  );
}

function Sinconfirmar({ etiqueta, valor }: { etiqueta: string; valor: string | null }) {
  return (
    <span className="mr-4 inline-block">
      <span className="text-taupe">{etiqueta}: </span>
      {valor ? <span className="text-tinta">{valor}</span> : <span className="rounded bg-ambar/15 px-1.5 text-ambar">sin confirmar</span>}
    </span>
  );
}

// ── Una póliza ──────────────────────────────────────────────────────────────

function TarjetaPoliza({
  z, hoy, actual, onPaso, onArchivos, onHistorial, onCorregir, onAnular,
}: {
  z: Poliza; hoy: string; actual: boolean;
  onPaso: (z: Poliza, paso: PasoSeguro, quitar: boolean) => void;
  onArchivos: (z: Poliza) => void; onHistorial: (z: Poliza) => void;
  onCorregir: (z: Poliza) => void; onAnular: (z: Poliza) => void;
}) {
  const dias = diasEntre(z.vigente_desde, z.vigente_hasta);
  const faltan = diasEntre(hoy, z.vigente_hasta);
  return (
    <div className={`rounded-xl border px-4 py-4 ${actual ? "border-sand bg-papel" : "border-sand bg-hueso"}`}>
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="font-medium text-tinta">
            Póliza <span className="font-mono">{z.numero_poliza}</span>
            <span className="font-normal text-taupe"> · {z.aseguradora}</span>
          </p>
          <p className="mt-0.5 text-sm text-taupe">
            Del {fecha(z.vigente_desde)} al {fecha(z.vigente_hasta)} · {plural(dias, "día", "días")}
            {z.cubre_hoy && <> · deja de cubrir el {fecha(z.vigente_hasta)} a las 12 M ({faltan === 1 ? "falta 1 día" : `faltan ${faltan} días`})</>}
          </p>
        </div>
        <div>
          {z.cubre_hoy ? <Insignia variante="positivo" tamano="sm">Cubre hoy</Insignia>
            : z.vigente_desde > hoy ? <Insignia variante="informativo" tamano="sm">Empieza el {fecha(z.vigente_desde)}</Insignia>
            : <Insignia variante="neutral" tamano="sm">Vencida</Insignia>}
        </div>
      </div>

      <div className="mt-3 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm">
        <span className="text-tinta">{formatSoles(z.prima_total)} <span className="text-taupe">con IGV</span></span>
        <InsigniaPrima z={z} hoy={hoy} />
      </div>

      <p className="mt-3 text-sm leading-relaxed">
        <Sinconfirmar etiqueta="Plan" valor={z.plan} />
        <Sinconfirmar etiqueta="Beneficio por enfermedad" valor={z.beneficio_enfermedad !== null ? formatSoles(z.beneficio_enfermedad) : null} />
        <Sinconfirmar etiqueta="por accidente" valor={z.beneficio_accidente !== null ? formatSoles(z.beneficio_accidente) : null} />
        <Sinconfirmar etiqueta="Renueva sola" valor={z.renueva_sola === null ? null : z.renueva_sola ? "sí" : "no"} />
      </p>

      <ul className="mt-3 grid grid-cols-1 gap-2 sm:grid-cols-3">
        {PASOS_SEGURO.map((s) => {
          const hecho = fechaDelPaso(z, s.paso);
          return (
            <li key={s.paso} className={`rounded-lg border px-3 py-2 text-sm ${hecho ? "border-verde/30 bg-verde/10" : "border-sand bg-hueso"}`}>
              <p className="text-tinta">{hecho ? "✓ " : ""}{hecho ? s.hecho : s.falta}</p>
              {hecho && <p className="text-xs text-taupe">el {fecha(hecho)}</p>}
              <div className="mt-1 flex flex-wrap gap-x-3">
                <Boton variante="enlace" onClick={() => onPaso(z, s.paso, false)}>{hecho ? "Cambiar la fecha" : "Marcar como hecho"}</Boton>
                {hecho && <Boton variante="enlace" onClick={() => onPaso(z, s.paso, true)}>Quitar la marca</Boton>}
              </div>
            </li>
          );
        })}
      </ul>

      {z.nota && <p className="mt-3 text-sm text-taupe">{z.nota}</p>}

      <div className="mt-3 flex flex-wrap items-center gap-2">
        <Boton variante="primario" tamano="sm" onClick={() => onArchivos(z)}>
          {z.archivos === 0 ? "Adjuntar PDF" : `Archivos (${z.archivos})`}
        </Boton>
        <Boton tamano="sm" onClick={() => onHistorial(z)}>Historial</Boton>
        <Boton tamano="sm" onClick={() => onCorregir(z)}>Corregir datos</Boton>
        <Boton variante="sutil" tamano="sm" onClick={() => onAnular(z)}>Anular</Boton>
      </div>
    </div>
  );
}

// ── La pantalla ─────────────────────────────────────────────────────────────

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

  const [filas, setFilas] = useState<FilaSeguro[]>([]);
  const [cargando, setCargando] = useState(true);
  const [cargaError, setCargaError] = useState<string | null>(null);
  const [busqueda, setBusqueda] = useState("");
  const [filtro, setFiltro] = useState<Filtro | null>(null);

  const cargar = useCallback(async () => {
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    const { data, error } = await supabase.rpc("fn_seguros_tablero");
    setFilas((data as FilaSeguro[] | null) ?? []);
    setCargaError(error ? mensajeDeError(error, "cargar los seguros") : null);
    setCargando(false);
  }, [supabase, router]);

  // `cargar` solo pone estado después de sus `await` (la sesión, la base): no
  // hay renders en cascada. Mismo patrón que /admin/archivo.
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { if (puede) void cargar(); }, [puede, cargar]);

  const personas = useMemo(() => seguroPorPersona(filas, hoy), [filas, hoy]);
  const resumen = useMemo(() => resumenDeSeguros(personas), [personas]);
  const conPapeleo = useMemo(() => polizasConPapeleoPendiente(personas), [personas]);

  // A quién se puede asegurar: los practicantes activos, tengan o no póliza.
  const opciones = useMemo<OpcionPersona[]>(() => {
    const vistos = new Map<string, OpcionPersona>();
    for (const f of filas) if (f.es_practicante_activo && !vistos.has(f.persona_id)) vistos.set(f.persona_id, { id: f.persona_id, nombre: f.persona, sede: f.sede });
    return [...vistos.values()].sort((a, b) => a.nombre.localeCompare(b.nombre, "es"));
  }, [filas]);

  const visibles = useMemo(() => personas.filter((p) => {
    if (soloPersona && p.personaId !== soloPersona) return false;
    if (!coincideSeguro(p, busqueda)) return false;
    if (filtro === null) return true;
    if (filtro === "papeleo") return p.polizas.some((z) => pasosPendientes(z).length > 0);
    return p.situacion === filtro;
  }), [personas, busqueda, filtro, soloPersona]);

  // ── Formulario ────────────────────────────────────────────────────────
  const [formAbierto, setFormAbierto] = useState(false);
  const [corrigiendo, setCorrigiendo] = useState<Poliza | null>(null);
  const [base, setBase] = useState<BaseDePoliza | null>(null);

  function registrar(b: BaseDePoliza | null) { setCorrigiendo(null); setBase(b); setFormAbierto(true); }
  function renovar(p: SeguroDePersona) {
    const a = p.actual;
    registrar({
      personaId: p.personaId, aseguradora: a?.aseguradora, numeroPoliza: a?.numero_poliza,
      // Empieza donde termina la cobertura: si se pone el mismo día no hay hueco ni cruce.
      desde: p.cubiertoHasta ?? undefined, prima: a?.prima_total ?? null,
    });
  }

  // ── Archivos e historial ──────────────────────────────────────────────
  const [verArchivos, setVerArchivos] = useState<{ id: string; titulo: string } | null>(null);
  const [verHistorial, setVerHistorial] = useState<{ id: string; titulo: string } | null>(null);
  const nombreDe = (z: Poliza) => `${z.persona} · póliza ${z.numero_poliza}`;

  // ── Marcar un paso ────────────────────────────────────────────────────
  const [paso, setPaso] = useState<{ z: Poliza; paso: PasoSeguro; quitar: boolean } | null>(null);
  // Nace en HOY y no en "": la fecha bloquea el envío, y un campo así no puede arrancar vacío.
  const [fechaPaso, setFechaPaso] = useState(hoy);
  const [motivoPaso, setMotivoPaso] = useState("");
  const [msgPaso, setMsgPaso] = useState<string | null>(null);
  const [ocupadoPaso, setOcupadoPaso] = useState(false);

  function abrirPaso(z: Poliza, p: PasoSeguro, quitar: boolean) {
    setPaso({ z, paso: p, quitar }); setFechaPaso(fechaDelPaso(z, p) ?? hoy); setMotivoPaso(""); setMsgPaso(null);
  }
  async function confirmarPaso() {
    if (!paso) return;
    if (paso.quitar && motivoPaso.trim().length < 5) { setMsgPaso("Escribe el motivo (al menos 5 letras)."); return; }
    if (!paso.quitar && !fechaPaso) { setMsgPaso("Falta la fecha."); return; }
    setOcupadoPaso(true);
    const { error } = await supabase.rpc("fn_seguro_marcar_paso", {
      p_id: paso.z.poliza_id, p_paso: paso.paso, p_fecha: paso.quitar ? null : fechaPaso,
      p_motivo: paso.quitar ? motivoPaso.trim() : null,
    });
    setOcupadoPaso(false);
    if (error) { setMsgPaso(mensajeDeError(error)); return; }
    setPaso(null);
    await cargar();
    avisar("ok", paso.quitar ? "Marca quitada. Quedó en el historial." : "Listo.");
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

  const fichas: { clave: Filtro; titulo: string; n: number; tono: "alerta" | "advertencia" | "positivo" | "neutral" }[] = [
    { clave: "hueco", titulo: "Sin seguro hoy", n: resumen.hueco, tono: "alerta" },
    { clave: "por_vencer", titulo: `Se quedan sin seguro en ${DIAS_AVISO_RENOVACION} días o menos`, n: resumen.por_vencer, tono: "advertencia" },
    { clave: "papeleo", titulo: "Pólizas con papeleo pendiente", n: conPapeleo, tono: "advertencia" },
    ...(resumen.baja_pendiente > 0 ? [{ clave: "baja_pendiente" as const, titulo: "Piden la baja", n: resumen.baja_pendiente, tono: "advertencia" as const }] : []),
    { clave: "al_dia", titulo: "Cubiertos, con margen", n: resumen.al_dia, tono: "positivo" },
  ];

  return (
    <main className="flex-1 p-6">
      <CabeceraPagina
        titulo="Seguros"
        descripcion={
          <>
            El seguro de salud de los practicantes (la póliza FOLA de Pacífico, que reemplazó a EsSalud): quién está
            cubierto hoy, hasta cuándo, qué papeleo falta y dónde están los PDF. Solo lo ve Desarrollo Organizacional.
            Nada se borra, y nada de aquí cambia lo que cobra nadie: avisa, y la decisión es de una persona.
          </>
        }
        accion={!cargaError && <Boton variante="primario" onClick={() => registrar(null)}>+ Registrar una póliza</Boton>}
      />

      {cargaError && (
        <div className="mb-4 max-w-3xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
          {cargaError} <Boton variante="enlace" onClick={() => void cargar()}>Reintentar</Boton>
        </div>
      )}

      {cargando ? <Cargando /> : !cargaError && (
        <>
          {personas.length === 0 ? (
            <div className="max-w-2xl rounded-2xl border border-sand bg-papel px-6 py-8 text-sm text-taupe">
              <p className="mb-2 text-tinta">Hoy no hay practicantes activos ni pólizas vigentes.</p>
              <p>Cuando alguien pase a modalidad formativa, aparecerá aquí sin póliza hasta que la registres.</p>
            </div>
          ) : (
            <>
              <ul className="mb-5 flex flex-wrap gap-3">
                {fichas.map((f) => {
                  const activa = filtro === f.clave;
                  const color = f.n === 0 ? "text-taupe" : f.tono === "alerta" ? "text-rojo-profundo" : f.tono === "positivo" ? "text-verde" : "text-ambar";
                  return (
                    <li key={f.clave}>
                      <button
                        type="button"
                        aria-pressed={activa}
                        onClick={() => setFiltro(activa ? null : f.clave)}
                        className={`min-w-36 rounded-2xl border px-4 py-3 text-left transition-colors ${activa ? "border-tinta bg-papel" : "border-sand bg-papel hover:border-taupe"}`}
                      >
                        <span className={`block font-serif text-2xl ${color}`}>{f.n}</span>
                        <span className="block max-w-44 text-xs text-taupe">{f.titulo}</span>
                      </button>
                    </li>
                  );
                })}
              </ul>

              {soloPersona && (
                <div className="mb-4 flex max-w-3xl flex-wrap items-center gap-3 rounded-lg bg-hueso px-4 py-3 text-sm text-tinta">
                  <span>Mostrando solo a {personas.find((p) => p.personaId === soloPersona)?.persona ?? "esa persona"}, que es a quien lleva el aviso.</span>
                  <Boton variante="enlace" onClick={() => router.replace("/admin/seguros")}>Ver a todos</Boton>
                </div>
              )}

              <div className="mb-4 max-w-md">
                <Campo etiqueta="Buscar" value={busqueda} onChange={(e) => setBusqueda(e.target.value)} placeholder="Nombre, número de póliza, aseguradora o sede" />
              </div>

              {visibles.length === 0 && <p className="text-sm text-taupe">Nadie coincide con ese filtro{busqueda ? ` y con «${busqueda}»` : ""}.</p>}

              <div className="space-y-4">
                {visibles.map((p) => {
                  const anteriores = p.polizas.filter((z) => z.poliza_id !== p.actual?.poliza_id);
                  return (
                    <section key={p.personaId} className="rounded-2xl border border-sand bg-papel">
                      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-sand px-5 py-3">
                        <h2 className="font-serif text-lg text-tinta">
                          {p.persona} <span className="font-sans text-sm text-taupe">· {p.sede}{p.modalidad && ` · ${MODALIDAD[p.modalidad] ?? p.modalidad}`}</span>
                        </h2>
                        <InsigniaSituacion p={p} />
                      </div>
                      <div className="space-y-3 px-5 py-4">
                        {p.situacion === "hueco" && <MensajeHueco p={p} hoy={hoy} />}
                        {p.situacion === "hueco" && (
                          <div><Boton variante="primario" tamano="sm" onClick={() => registrar({ personaId: p.personaId })}>Registrar su póliza</Boton></div>
                        )}
                        {p.situacion === "por_vencer" && (
                          <p className="rounded-lg bg-ambar/10 px-3 py-2 text-sm text-ambar">
                            Se queda sin seguro el {fecha(p.cubiertoHasta!)} y no hay una renovación registrada que empalme.{" "}
                            <Boton variante="enlace" onClick={() => renovar(p)}>Registrar la renovación</Boton>
                          </p>
                        )}
                        {p.situacion === "baja_pendiente" && (
                          <p className="rounded-lg bg-ambar/10 px-3 py-2 text-sm text-ambar">
                            Ya no es practicante activo y su póliza sigue vigente: pídele la baja a la aseguradora.
                          </p>
                        )}
                        {p.actual && (
                          <TarjetaPoliza
                            z={p.actual} hoy={hoy} actual
                            onPaso={abrirPaso}
                            onArchivos={(z) => setVerArchivos({ id: z.poliza_id, titulo: nombreDe(z) })}
                            onHistorial={(z) => setVerHistorial({ id: z.poliza_id, titulo: nombreDe(z) })}
                            onCorregir={(z) => { setCorrigiendo(z); setBase(null); setFormAbierto(true); }}
                            onAnular={(z) => { setAnulando(z); setMotivoAnular(""); setMsgAnular(null); }}
                          />
                        )}
                        {anteriores.length > 0 && (
                          <details className="text-sm">
                            <summary className="cursor-pointer text-taupe">{anteriores.length === 1 ? "Otra póliza registrada" : `Otras ${anteriores.length} pólizas registradas`}</summary>
                            <div className="mt-2 space-y-3">
                              {anteriores.map((z) => (
                                <TarjetaPoliza
                                  key={z.poliza_id} z={z} hoy={hoy} actual={false}
                                  onPaso={abrirPaso}
                                  onArchivos={(x) => setVerArchivos({ id: x.poliza_id, titulo: nombreDe(x) })}
                                  onHistorial={(x) => setVerHistorial({ id: x.poliza_id, titulo: nombreDe(x) })}
                                  onCorregir={(x) => { setCorrigiendo(x); setBase(null); setFormAbierto(true); }}
                                  onAnular={(x) => { setAnulando(x); setMotivoAnular(""); setMsgAnular(null); }}
                                />
                              ))}
                            </div>
                          </details>
                        )}
                        {p.situacion !== "hueco" && p.situacion !== "baja_pendiente" && p.situacion !== "por_vencer" && p.cubiertoHasta && (
                          <div>
                            <Boton variante="enlace" onClick={() => renovar(p)}>Registrar una renovación</Boton>
                          </div>
                        )}
                      </div>
                    </section>
                  );
                })}
              </div>
            </>
          )}
        </>
      )}

      <FormularioPoliza
        abierto={formAbierto}
        onCerrar={() => setFormAbierto(false)}
        supabase={supabase}
        personas={opciones}
        corrigiendo={corrigiendo}
        base={base}
        onGuardado={async (id, nueva) => {
          setFormAbierto(false);
          await cargar();
          if (nueva) {
            avisar("ok", "Póliza registrada. Adjunta ahora el PDF de la póliza y el convenio de pago.");
            setVerArchivos({ id, titulo: "Póliza recién registrada" });
          } else {
            avisar("ok", "Corrección guardada. El historial dice qué decía antes.");
          }
        }}
      />

      <ArchivosPoliza
        abierto={verArchivos !== null}
        onCerrar={() => setVerArchivos(null)}
        supabase={supabase}
        polizaId={verArchivos?.id ?? null}
        titulo={verArchivos?.titulo ?? ""}
        onCambio={() => void cargar()}
      />

      <HistorialPoliza
        abierto={verHistorial !== null}
        onCerrar={() => setVerHistorial(null)}
        supabase={supabase}
        polizaId={verHistorial?.id ?? null}
        titulo={verHistorial?.titulo ?? ""}
      />

      {/* ── Marcar un paso ──────────────────────────────────────────────── */}
      <Modal
        abierto={paso !== null}
        onCerrar={() => { if (!ocupadoPaso) setPaso(null); }}
        bloqueado={ocupadoPaso}
        titulo={paso ? (paso.quitar ? "Quitar la marca" : "Marcar como hecho") : undefined}
        ancho="sm"
      >
        {paso && (
          <>
            <p className="mb-3 text-sm text-taupe">
              {PASOS_SEGURO.find((s) => s.paso === paso.paso)?.hecho} — póliza {paso.z.numero_poliza} de {paso.z.persona}.
            </p>
            {paso.quitar ? (
              <label className="flex flex-col gap-1">
                <span className="text-sm text-taupe">Por qué se quita la marca</span>
                <AreaTexto
                  value={motivoPaso}
                  onChange={(e) => { setMotivoPaso(e.target.value); setMsgPaso(null); }}
                  placeholder="ej. Era el pago de otra póliza"
                  className={msgPaso ? "border-rojo" : undefined}
                />
                {msgPaso && <span className="text-xs text-rojo">{msgPaso}</span>}
              </label>
            ) : (
              <Campo
                etiqueta="Fecha en que se hizo"
                type="date" value={fechaPaso} max={hoy}
                onChange={(e) => { setFechaPaso(e.target.value); setMsgPaso(null); }}
                error={msgPaso ?? undefined}
              />
            )}
            <div className="mt-4 flex justify-end gap-2">
              <Boton onClick={() => setPaso(null)} disabled={ocupadoPaso}>Cancelar</Boton>
              <Boton variante={paso.quitar ? "peligro" : "primario"} onClick={() => void confirmarPaso()} cargando={ocupadoPaso}>
                {paso.quitar ? "Sí, quitar la marca" : "Guardar"}
              </Boton>
            </div>
          </>
        )}
      </Modal>

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
              La póliza {anulando.numero_poliza} de {anulando.persona} deja de contar para la cobertura y desaparece de
              esta lista, pero no se borra: queda anulada con tu nombre y este motivo. Úsalo solo para una póliza
              registrada por error. Si cambió un dato, usa «Corregir datos».
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

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
import { hoyLima, sumarDias } from "@cayla-dynamic/shared";
import { Cargando } from "@/components/cargando";
import { useToast } from "@/components/toast";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Boton } from "@/components/ui/boton";
import { AreaTexto } from "@/components/ui/area-texto";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { Drawer } from "@/components/ui/drawer";
import { EstadoVacio } from "@/components/ui/estado-vacio";
import { Insignia } from "@/components/ui/insignia";
import { ParaAtender } from "@/components/ui/para-atender";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { abrirArchivoFirmado } from "@/lib/abrir-archivo-firmado";
import { TIPOS_ARCHIVO } from "@/lib/admin/archivo";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { isoADiaMesAnio } from "@/lib/admin/planilla/formato";
import {
  BANDAS_LOCACION,
  bandaLocacion,
  BUCKET_LOCACION,
  ESTADO_CONTRATO,
  ESTADO_PERSONA,
  fechasSugeridas,
  rucDePersonaValido,
  rucDesdeDni,
  textoPlazo,
  textoVinculoActual,
  type BandaLocacion,
  type ContratoLocacion,
  type FilaTableroLocacion,
} from "@/lib/admin/locaciones";
import { registrarContratoLocacion } from "@/lib/admin/locaciones-archivo";
import {
  construirLocacion,
  estamparFirmas,
  TEXTO_LOCACION_APROBADO,
  type DatosLocacion,
  type PeriodicidadHonorarios,
} from "@/lib/admin/locacion-texto";
import { DocumentoLocacion } from "./documento-locacion";

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

/** Quien firma por CAYLA (`configuracion.firmante_empresa`, 0147): lo resuelve la página de Contratos. */
export interface FirmanteCayla {
  nombre: string;
  dni: string;
  cargo: string;
}

export function ContratosHonorarios({
  supabase,
  tablero,
  firmante,
}: {
  supabase: ClienteCayla;
  tablero: ReturnType<typeof useLocacionesTablero>;
  firmante: FirmanteCayla;
}) {
  const [banda, setBanda] = useState<BandaLocacion | null>(null);
  const [abierta, setAbierta] = useState<FilaTableroLocacion | null>(null);
  // Mientras sube un escaneo, el panel no se cierra: se perdería lo escrito y el aviso de si quedó.
  const [ocupado, setOcupado] = useState(false);
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
        <strong className="font-medium text-tinta">locación de servicios</strong>. Aquí se genera y la persona lo
        firma en «Lo mío», o se guarda el escaneo de uno firmado en papel; y se avisa cuando falta o se vence.
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
              { clave: "abierta", texto: `${n("abierta")} con locación abierta`, n: n("abierta"), tono: "ambar" },
              { clave: "sin_cubrir", texto: `${n("sin_cubrir")} sin contrato vigente`, n: n("sin_cubrir"), tono: "ambar" },
              { clave: "firma", texto: `${n("firma")} falta${n("firma") === 1 ? "" : "n"} su firma`, n: n("firma"), tono: "pizarra" },
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
        onCerrar={() => { if (!ocupado) setAbierta(null); }}
        bloqueado={ocupado}
        ancho="amplio"
        titulo={abierta ? `Contratos de locación · ${abierta.persona}` : undefined}
        volverElFocoA={filaQueAbrio}
      >
        {abierta && (
          <Historial
            key={abierta.persona_id}
            supabase={supabase}
            fila={abierta}
            firmante={firmante}
            alCambiar={() => void tablero.recargar()}
            alOcupar={setOcupado}
          />
        )}
      </Drawer>
    </div>
  );
}

function FilaPersona({ f, alAbrir }: { f: FilaTableroLocacion; alAbrir: (el: HTMLElement) => void }) {
  const estado = ESTADO_PERSONA[f.estado];
  const plazo = f.estado === "por_empezar" ? `Empieza el ${fecha(f.fecha_inicio)}`
    : f.estado === "abierta_sin_rxh" ? null
    : textoPlazo(f);
  const detalle = [
    f.estado === "abierta_sin_rxh" ? textoVinculoActual(f.vinculo_actual) : null,
    f.servicio,
    f.sede,
  ].filter(Boolean).join(" · ");
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

/** Todos los contratos de una persona: los que valen primero, los anulados al final. */
function Historial({
  supabase, fila, firmante, alCambiar, alOcupar,
}: {
  supabase: ClienteCayla;
  fila: FilaTableroLocacion;
  firmante: FirmanteCayla;
  /** Avisa que se registró algo, para que el tablero se ponga al día. */
  alCambiar: () => void;
  alOcupar: (ocupado: boolean) => void;
}) {
  const { avisar } = useToast();
  const [contratos, setContratos] = useState<ContratoLocacion[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [cargando, setCargando] = useState(true);
  // Quien no tiene ningún contrato llega aquí a generarlo: el formulario ya está abierto. La otra vía, registrar
  // el escaneo de uno firmado en papel (0610), sigue a un clic.
  const [modo, setModo] = useState<"generar" | "registrar" | null>(fila.estado === "sin_contrato" ? "generar" : null);
  // Un contrato generado se lee aquí mismo, en el panel.
  const [viendo, setViendo] = useState<ContratoLocacion | null>(null);
  // Un contrato a la vez: anular o terminar abre su formulario debajo de esa tarjeta.
  const [accion, setAccion] = useState<{ id: string; tipo: "anular" | "terminar" } | null>(null);
  const yaNoEsRxh = fila.estado === "abierta_sin_rxh";
  // Del historial, no de la fila del tablero: la fila es de cuando se abrió el panel, y después de «Terminar antes»
  // el aviso de «sigue abierta» seguía ahí sobre una locación ya cerrada.
  const quedaAbierta = contratos.some((c) => c.estado === "en_curso" || c.estado === "por_empezar");

  const cargar = useCallback(async () => {
    const { data, error: e } = await supabase.rpc("fn_locaciones_listar", { p_persona_id: fila.persona_id });
    setContratos((data as ContratoLocacion[] | null) ?? []);
    setError(e ? mensajeDeError(e, "traer sus contratos") : null);
    setCargando(false);
  }, [supabase, fila.persona_id]);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargar(); }, [cargar]);

  async function ver(c: ContratoLocacion) {
    const fallo = await abrirArchivoFirmado(supabase, BUCKET_LOCACION, c.storage_path);
    if (fallo) avisar("error", fallo);
  }

  if (cargando) return <Cargando />;

  if (viendo) {
    return (
      <div className="space-y-3">
        <Boton variante="enlace" className="text-sm" onClick={() => setViendo(null)}>← Volver al historial</Boton>
        <p className="text-xs text-taupe">
          {viendo.fecha_firma ? `Firmado el ${fecha(viendo.fecha_firma)}.` : "Todavía sin la firma de la persona: la firma desde «Lo mío › Contrato»."}
        </p>
        <DocumentoLocacion supabase={supabase} contratoId={viendo.id} nombreDelPdf={`${fila.persona} — Contrato de locación`} />
      </div>
    );
  }

  const servicioAnterior = contratos.find((c) => c.estado !== "anulado")?.servicio ?? "";
  const alListo = (texto: string) => {
    setModo(null);
    avisar("ok", texto);
    void cargar();
    alCambiar();
  };

  return (
    <div className="space-y-4">
      {error && <BannerAviso enLinea role="alert">{error}</BannerAviso>}

      {/* Quien ya no cobra por honorarios no recibe contratos nuevos aquí (la base tampoco lo deja): lo que falta es
          cerrar el que quedó abierto. */}
      {yaNoEsRxh ? (quedaAbierta && (
        <BannerAviso enLinea variante="advertencia">
          {fila.persona}: {textoVinculoActual(fila.vinculo_actual).toLowerCase()} y su locación sigue abierta. Con las
          dos cosas a la vez tiene un vínculo civil y otro laboral. Usa «Terminar antes» con el último día en que valió.
        </BannerAviso>
      )) : modo === "generar" ? (
        <FormGenerar
          supabase={supabase}
          fila={fila}
          firmante={firmante}
          servicioAnterior={servicioAnterior}
          alCancelar={() => setModo(null)}
          alOcupar={alOcupar}
          alGenerar={() => alListo("Contrato generado. Falta que la persona lo firme desde «Lo mío».")}
        />
      ) : modo === "registrar" ? (
        <FormRegistrar
          supabase={supabase}
          fila={fila}
          servicioAnterior={servicioAnterior}
          alCancelar={() => setModo(null)}
          alOcupar={alOcupar}
          alRegistrar={() => alListo("Contrato registrado.")}
        />
      ) : (
        <div className="flex flex-wrap gap-2">
          <Boton variante="primario" onClick={() => setModo("generar")}>Generar contrato</Boton>
          <Boton variante="secundario" onClick={() => setModo("registrar")}>Registrar uno firmado en papel</Boton>
        </div>
      )}

      {!error && contratos.length === 0 && modo === null && (
        <EstadoVacio>Todavía no hay ningún contrato de locación registrado para {fila.persona}.</EstadoVacio>
      )}

      {contratos.length > 0 && (
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
                    {c.fecha_firma ? `Firmado el ${fecha(c.fecha_firma)}` : "Sin firmar todavía"}
                    {" · "}{c.es_digital ? "generado en Dynamic" : "escaneo de un papel"} por {c.registrado_por_nombre ?? "—"}
                  </p>
                  {c.terminado_el && c.terminado_motivo && (
                    <p className="text-xs text-taupe">Terminado: {c.terminado_motivo} ({c.terminado_por_nombre ?? "—"})</p>
                  )}
                  {c.anulado_at && c.anulado_motivo && (
                    <p className="text-xs text-taupe">Anulado: {c.anulado_motivo} ({c.anulado_por_nombre ?? "—"})</p>
                  )}
                  <div className="flex flex-wrap gap-x-4 pt-1">
                    <Boton variante="enlace" className="text-xs" onClick={() => (c.es_digital ? setViendo(c) : void ver(c))}>
                      Ver contrato
                    </Boton>
                    {(c.estado === "en_curso" || c.estado === "por_empezar") && (
                      <Boton variante="enlace" className="text-xs" onClick={() => setAccion({ id: c.id, tipo: "terminar" })}>
                        Terminar antes
                      </Boton>
                    )}
                    {c.estado !== "anulado" && c.estado !== "terminado" && (
                      <Boton variante="enlace" className="text-xs" onClick={() => setAccion({ id: c.id, tipo: "anular" })}>
                        Anular registro
                      </Boton>
                    )}
                  </div>
                  {accion?.id === c.id && (
                    <AccionContrato
                      supabase={supabase}
                      contrato={c}
                      tipo={accion.tipo}
                      alCancelar={() => setAccion(null)}
                      alOcupar={alOcupar}
                      alTerminar={(texto) => {
                        setAccion(null);
                        avisar("ok", texto);
                        void cargar();
                        alCambiar();
                      }}
                    />
                  )}
                </TarjetaInfo>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

/** Lo que el contrato necesita de la persona, leído de su ficha al abrir el formulario. */
interface DatosDeLaPersona {
  nombreDni: string;
  documento: string | null;
  direccion: string | null;
  genero: "masculino" | "femenino" | null;
  ciudad: string | null;
  honorarioVigente: number | null;
}

const FORMAS_DE_PAGO: { valor: PeriodicidadHonorarios; texto: string }[] = [
  { valor: "por_horas", texto: "En proporción a las horas de servicio" },
  { valor: "mensual", texto: "Fijos cada mes" },
  { valor: "total", texto: "Un monto por todo el servicio" },
];

/**
 * Generar el contrato de locación (0612). Arma el texto con `construirLocacion` y lo guarda congelado; la persona
 * lo firma después desde «Lo mío». Todo nace con su valor más probable y a la vista: el servicio del contrato
 * anterior, los honorarios vigentes de su ficha, el RUC calculado desde su DNI y la forma de pago con que se le
 * paga hoy (en proporción a las horas). No pide cargo, horas ni sueldo: es una locación civil.
 */
function FormGenerar({
  supabase, fila, firmante, servicioAnterior, alCancelar, alOcupar, alGenerar,
}: {
  supabase: ClienteCayla;
  fila: FilaTableroLocacion;
  firmante: FirmanteCayla;
  servicioAnterior: string;
  alCancelar: () => void;
  alOcupar: (ocupado: boolean) => void;
  alGenerar: () => void;
}) {
  const hoy = hoyLima();
  const sugeridas = fechasSugeridas(fila, hoy);
  const [datos, setDatos] = useState<DatosDeLaPersona | null>(null);
  const [errorDatos, setErrorDatos] = useState<string | null>(null);
  const [servicio, setServicio] = useState(servicioAnterior);
  const [entregables, setEntregables] = useState("");
  const [inicio, setInicio] = useState(sugeridas.inicio);
  const [fin, setFin] = useState(sugeridas.fin);
  const [honorarios, setHonorarios] = useState("");
  const [periodicidad, setPeriodicidad] = useState<PeriodicidadHonorarios>("por_horas");
  const [ruc, setRuc] = useState("");
  const [rucCalculado, setRucCalculado] = useState<string | null>(null);
  const [vistaPrevia, setVistaPrevia] = useState(false);
  const [guardando, setGuardando] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let vivo = true;
    void (async () => {
      const [{ data: p }, { data: dp }, { data: sal }] = await Promise.all([
        supabase.from("personas").select("documento, nombres, apellidos, sede_base_id").eq("id", fila.persona_id).maybeSingle(),
        supabase.from("datos_personales").select("nombre_dni, direccion, genero").eq("persona_id", fila.persona_id).maybeSingle(),
        supabase.from("asignaciones_salario").select("salario_mensual_soles").eq("persona_id", fila.persona_id)
          .is("vigente_hasta", null).limit(1),
      ]);
      const { data: sede } = p?.sede_base_id
        ? await supabase.from("sedes").select("ciudad").eq("id", p.sede_base_id).maybeSingle()
        : { data: null };
      if (!vivo) return;
      if (!p) { setErrorDatos("No se pudo leer su ficha. Vuelve a abrir el panel."); return; }
      const genero = dp?.genero === "masculino" || dp?.genero === "femenino" ? dp.genero : null;
      const honorarioVigente = Number((sal as { salario_mensual_soles: number }[] | null)?.[0]?.salario_mensual_soles ?? 0) || null;
      setDatos({
        nombreDni: dp?.nombre_dni || `${p.nombres} ${p.apellidos}`,
        documento: p.documento,
        direccion: dp?.direccion ?? null,
        genero,
        ciudad: (sede as { ciudad: string | null } | null)?.ciudad ?? null,
        honorarioVigente,
      });
      if (honorarioVigente) setHonorarios((prev) => (prev === "" ? String(honorarioVigente) : prev));
      const calculado = rucDesdeDni(p.documento);
      setRucCalculado(calculado);
      if (calculado) setRuc((prev) => (prev === "" ? calculado : prev));
    })();
    return () => { vivo = false; };
  }, [supabase, fila.persona_id]);

  const monto = Number(honorarios.replace(",", "."));
  const falta = !datos
    ? (errorDatos ?? "Leyendo su ficha…")
    : !firmante.nombre.trim() || !firmante.dni.trim()
      ? "Falta configurar quién firma por CAYLA."
      : !datos.documento?.trim()
        ? "Su ficha no tiene DNI: cárgalo en Equipo antes de generar el contrato."
      : servicio.trim().length < 3
        ? "Escribe qué servicio se contrata."
        : entregables.trim() === ""
          ? "Escribe qué comprende el servicio: una línea por cada cosa que entrega."
          : !inicio || !fin
            ? "Completa las dos fechas."
            : fin < inicio
              ? "El contrato no puede terminar antes de empezar."
              : !(monto > 0)
                ? "Escribe los honorarios."
                : !rucDePersonaValido(ruc)
                  ? "El RUC no cuadra: 11 dígitos que empiezan con 10, con su dígito verificador."
                  : null;

  const datosLocacion: DatosLocacion | null = datos
    ? {
        nombreDni: datos.nombreDni,
        documento: datos.documento ?? "",
        ruc: ruc.trim() || null,
        direccion: datos.direccion,
        genero: datos.genero,
        servicio: servicio.trim(),
        entregables,
        fechaInicio: inicio,
        fechaFin: fin,
        honorarios: monto > 0 ? monto : 0,
        periodicidad,
        ciudad: datos.ciudad,
        diasAviso: 15,
        firmanteNombre: firmante.nombre,
        firmanteCargo: firmante.cargo,
        firmanteDni: firmante.dni,
      }
    : null;

  async function generar() {
    if (falta || !datosLocacion) return;
    setError(null);
    setGuardando(true);
    alOcupar(true);
    const { error: e } = await supabase.rpc("fn_locacion_generar", {
      p_persona_id: fila.persona_id,
      p_servicio: servicio.trim(),
      p_fecha_inicio: inicio,
      p_fecha_fin: fin,
      p_honorarios: monto,
      p_periodicidad: periodicidad,
      p_ruc_locador: ruc.trim(),
      p_documento_html: construirLocacion(datosLocacion),
    });
    setGuardando(false);
    alOcupar(false);
    if (e) { setError(mensajeDeError(e, "generar el contrato")); return; }
    alGenerar();
  }

  return (
    <TarjetaInfo className="space-y-3 p-4 sm:p-4">
      <p className="font-medium text-tinta">Generar contrato de locación de servicios</p>
      {!TEXTO_LOCACION_APROBADO && (
        <BannerAviso enLinea variante="advertencia">
          El texto todavía es un borrador sin revisión legal: lo que generes sale con el aviso «BORRADOR — No firmar»
          y la persona no lo puede firmar hasta que se apruebe.
        </BannerAviso>
      )}
      <Campo
        etiqueta="Servicio que se contrata"
        value={servicio}
        disabled={guardando}
        onChange={(e) => setServicio(e.target.value)}
        placeholder="Ej.: Fotografía de producto para la tienda"
      />
      <AreaTexto
        etiqueta="Qué comprende (una línea por cada cosa que entrega)"
        rows={3}
        value={entregables}
        disabled={guardando}
        onChange={(e) => setEntregables(e.target.value)}
        placeholder={"Fotos de cada colección nueva para la tienda en línea.\nRetoque y entrega en 5 días hábiles."}
      />
      <div className="grid gap-3 sm:grid-cols-2">
        <Campo etiqueta="Empieza" type="date" value={inicio} disabled={guardando} onChange={(e) => setInicio(e.target.value)} />
        <Campo etiqueta="Termina" type="date" value={fin} min={inicio} disabled={guardando} onChange={(e) => setFin(e.target.value)} />
        <Campo
          etiqueta={periodicidad === "total" ? "Honorarios por todo el servicio (S/)" : "Honorarios por un mes completo (S/)"}
          type="number"
          min="0"
          step="0.01"
          value={honorarios}
          disabled={guardando}
          onChange={(e) => setHonorarios(e.target.value)}
        />
        <CampoSelect
          etiqueta="Cómo se pagan"
          value={periodicidad}
          disabled={guardando}
          onChange={(e) => setPeriodicidad(e.target.value as PeriodicidadHonorarios)}
        >
          {FORMAS_DE_PAGO.map((f) => <option key={f.valor} value={f.valor}>{f.texto}</option>)}
        </CampoSelect>
      </div>
      <Campo
        etiqueta="RUC de quien presta el servicio"
        value={ruc}
        inputMode="numeric"
        disabled={guardando}
        onChange={(e) => setRuc(e.target.value.replace(/\D/g, "").slice(0, 11))}
      />
      {rucCalculado && ruc === rucCalculado && (
        <p className="-mt-2 text-xs text-taupe">Calculado desde su DNI: confírmalo con su ficha RUC.</p>
      )}
      {datos && !datos.ciudad && (
        <p className="text-xs text-taupe">Su sede no tiene ciudad cargada: el contrato lo va a decir. Se carga en Sedes.</p>
      )}
      {datos && !datos.direccion && (
        <p className="text-xs text-taupe">Su ficha no tiene domicilio: el contrato lo va a decir. Se carga en Equipo.</p>
      )}
      {error && <BannerAviso enLinea role="alert">{error}</BannerAviso>}
      {falta && !error && <p className="text-xs text-taupe">{falta}</p>}
      <div className="flex flex-wrap justify-end gap-2">
        <Boton onClick={alCancelar} disabled={guardando}>Cancelar</Boton>
        <Boton variante="secundario" onClick={() => setVistaPrevia((v) => !v)} disabled={!datosLocacion}>
          {vistaPrevia ? "Ocultar vista previa" : "Ver cómo queda"}
        </Boton>
        <Boton variante="primario" onClick={() => void generar()} disabled={falta !== null || guardando} cargando={guardando}>
          Generar contrato
        </Boton>
      </div>
      {vistaPrevia && datosLocacion && (
        <div
          className="hoja max-h-[60vh] overflow-y-auto rounded-lg border border-sand p-4 text-sm leading-relaxed"
          dangerouslySetInnerHTML={{ __html: estamparFirmas(construirLocacion(datosLocacion), { empresa: null, persona: null, empresaAt: null, personaAt: null }) }}
        />
      )}
    </TarjetaInfo>
  );
}

/**
 * Registrar el contrato firmado: el escaneo y sus cuatro datos. Las fechas nacen
 * con su valor más probable (`fechasSugeridas`), a la vista y editables: un campo
 * de fecha que arranca vacío y bloquea el envío es la trampa del 2026-08-26.
 */
function FormRegistrar({
  supabase, fila, servicioAnterior, alCancelar, alOcupar, alRegistrar,
}: {
  supabase: ClienteCayla;
  fila: FilaTableroLocacion;
  servicioAnterior: string;
  alCancelar: () => void;
  alOcupar: (ocupado: boolean) => void;
  alRegistrar: () => void;
}) {
  const hoy = hoyLima();
  const sugeridas = fechasSugeridas(fila, hoy);
  const [archivo, setArchivo] = useState<File | null>(null);
  const [servicio, setServicio] = useState(servicioAnterior);
  const [inicio, setInicio] = useState(sugeridas.inicio);
  const [fin, setFin] = useState(sugeridas.fin);
  const [firma, setFirma] = useState(sugeridas.firma);
  const [progreso, setProgreso] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);

  // Lo que falta, dicho antes de pulsar: el botón no se apaga sin decir por qué.
  const falta = !archivo
    ? "Elige el escaneo del contrato firmado."
    : servicio.trim().length < 3
      ? "Escribe qué servicio se contrata."
      : !inicio || !fin || !firma
        ? "Completa las tres fechas."
        : fin < inicio
          ? "El contrato no puede terminar antes de empezar."
          : firma > hoy
            ? "La fecha de firma no puede ser posterior a hoy."
            : null;

  async function guardar() {
    if (falta || !archivo) return;
    setError(null);
    alOcupar(true);
    setProgreso(0);
    const fallo = await registrarContratoLocacion(
      supabase,
      { personaId: fila.persona_id, servicio: servicio.trim(), fechaInicio: inicio, fechaFin: fin, fechaFirma: firma },
      archivo,
      setProgreso,
    );
    setProgreso(null);
    alOcupar(false);
    if (fallo) { setError(fallo); return; }
    alRegistrar();
  }

  const subiendo = progreso !== null;
  return (
    <TarjetaInfo className="space-y-3 p-4 sm:p-4">
      <p className="font-medium text-tinta">Registrar contrato firmado</p>
      <p className="text-xs text-taupe">
        El PDF o la foto del contrato de locación ya firmado por las dos partes. Hasta 50 MB. Una vez registrado no se
        edita: si un dato sale mal, se anula y se registra de nuevo.
      </p>
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-taupe">Contrato escaneado</span>
        <input
          type="file"
          accept={TIPOS_ARCHIVO}
          disabled={subiendo}
          onChange={(e) => setArchivo(e.target.files?.[0] ?? null)}
          className="rounded-control border border-sand bg-hueso px-3 py-2 text-sm file:mr-3 file:cursor-pointer file:rounded file:border-0 file:bg-sand file:px-3 file:py-1 file:text-sm hover:file:bg-taupe hover:file:text-crema"
        />
      </label>
      <Campo
        etiqueta="Servicio que se contrata (como dice el contrato)"
        value={servicio}
        disabled={subiendo}
        onChange={(e) => setServicio(e.target.value)}
        placeholder="Ej.: Fotografía de producto para la tienda"
      />
      {/* Dos columnas y no tres: en los 460 px del panel, tres fechas se cortaban («09/11/202…»). */}
      <div className="grid gap-3 sm:grid-cols-2">
        <Campo etiqueta="Empieza" type="date" value={inicio} disabled={subiendo} onChange={(e) => setInicio(e.target.value)} />
        <Campo etiqueta="Termina" type="date" value={fin} min={inicio} disabled={subiendo} onChange={(e) => setFin(e.target.value)} />
        <Campo etiqueta="Se firmó" type="date" value={firma} max={hoy} disabled={subiendo} onChange={(e) => setFirma(e.target.value)} />
      </div>
      {error && <BannerAviso enLinea role="alert">{error}</BannerAviso>}
      {falta && !error && <p className="text-xs text-taupe">{falta}</p>}
      <div className="flex flex-wrap justify-end gap-2">
        <Boton onClick={alCancelar} disabled={subiendo}>Cancelar</Boton>
        <Boton variante="primario" onClick={() => void guardar()} disabled={falta !== null || subiendo} cargando={subiendo}>
          {subiendo ? `Subiendo… ${Math.round(progreso ?? 0)} %` : "Guardar contrato"}
        </Boton>
      </div>
    </TarjetaInfo>
  );
}

/**
 * Anular un registro equivocado, o terminar una locación antes de su fecha. Las dos piden motivo, que queda
 * junto al contrato; ninguna borra nada. «Terminar» nace con hoy (o con la víspera de empezar, si el contrato
 * todavía no empieza), visible y editable.
 */
function AccionContrato({
  supabase, contrato, tipo, alCancelar, alOcupar, alTerminar,
}: {
  supabase: ClienteCayla;
  contrato: ContratoLocacion;
  tipo: "anular" | "terminar";
  alCancelar: () => void;
  alOcupar: (ocupado: boolean) => void;
  alTerminar: (texto: string) => void;
}) {
  const hoy = hoyLima();
  const vispera = sumarDias(contrato.fecha_inicio, -1);
  const ultimoPosible = sumarDias(contrato.fecha_fin, -1);
  const [fechaFin, setFechaFin] = useState(hoy < contrato.fecha_inicio ? vispera : hoy > ultimoPosible ? ultimoPosible : hoy);
  const [motivo, setMotivo] = useState("");
  const [guardando, setGuardando] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const falta = motivo.trim().length < 5
    ? "Escribe el motivo: queda anotado junto al contrato."
    : tipo === "terminar" && (!fechaFin || fechaFin < vispera || fechaFin > ultimoPosible)
      ? `El último día va del ${fecha(vispera)} al ${fecha(ultimoPosible)}.`
      : null;

  async function confirmar() {
    if (falta) return;
    setError(null);
    setGuardando(true);
    alOcupar(true);
    const { error: e } = tipo === "anular"
      ? await supabase.rpc("fn_locacion_anular", { p_id: contrato.id, p_motivo: motivo.trim() })
      : await supabase.rpc("fn_locacion_terminar", { p_id: contrato.id, p_fecha: fechaFin, p_motivo: motivo.trim() });
    setGuardando(false);
    alOcupar(false);
    if (e) { setError(mensajeDeError(e, tipo === "anular" ? "anular el registro" : "terminar la locación")); return; }
    alTerminar(tipo === "anular" ? "Registro anulado. Sigue en el historial." : "Locación terminada.");
  }

  return (
    <div className="mt-2 space-y-3 border-t border-sand pt-3">
      <p className="text-xs text-taupe">
        {tipo === "anular"
          ? "Anular es para un registro equivocado: otra persona, una fecha o el servicio mal escritos. El contrato deja de contar, pero se queda en el historial con su motivo."
          : "Terminar es para una locación que dejó de valer antes de su fecha: pasó a planilla, cesó o se resolvió."}
      </p>
      {tipo === "terminar" && (
        <Campo
          etiqueta="Último día en que valió"
          type="date"
          value={fechaFin}
          min={vispera}
          max={ultimoPosible}
          disabled={guardando}
          onChange={(e) => setFechaFin(e.target.value)}
        />
      )}
      <AreaTexto
        etiqueta="Motivo"
        value={motivo}
        disabled={guardando}
        onChange={(e) => setMotivo(e.target.value)}
        placeholder={tipo === "anular" ? "Ej.: se registró con la fecha de fin equivocada" : "Ej.: pasó a planilla el 1 de diciembre"}
      />
      {error && <BannerAviso enLinea role="alert">{error}</BannerAviso>}
      {falta && !error && <p className="text-xs text-taupe">{falta}</p>}
      <div className="flex flex-wrap justify-end gap-2">
        <Boton tamano="sm" onClick={alCancelar} disabled={guardando}>Cancelar</Boton>
        <Boton
          tamano="sm"
          variante={tipo === "anular" ? "peligro" : "primario"}
          onClick={() => void confirmar()}
          disabled={falta !== null || guardando}
          cargando={guardando}
        >
          {tipo === "anular" ? "Anular registro" : "Terminar locación"}
        </Boton>
      </div>
    </div>
  );
}

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
import { hoyLima } from "@cayla-dynamic/shared";
import { Cargando } from "@/components/cargando";
import { useToast } from "@/components/toast";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Boton } from "@/components/ui/boton";
import { Campo } from "@/components/ui/campo";
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
  textoPlazo,
  type BandaLocacion,
  type ContratoLocacion,
  type FilaTableroLocacion,
} from "@/lib/admin/locaciones";
import { registrarContratoLocacion } from "@/lib/admin/locaciones-archivo";

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

export function ContratosHonorarios({
  supabase,
  tablero,
}: {
  supabase: ClienteCayla;
  tablero: ReturnType<typeof useLocacionesTablero>;
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
        <strong className="font-medium text-tinta">locación de servicios</strong>. Aquí se guarda ese contrato
        firmado y se avisa cuando falta o se vence.
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
              { clave: "sin_cubrir", texto: `${n("sin_cubrir")} sin contrato vigente`, n: n("sin_cubrir"), tono: "ambar" },
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
        titulo={abierta ? `Contratos de locación · ${abierta.persona}` : undefined}
        volverElFocoA={filaQueAbrio}
      >
        {abierta && (
          <Historial
            key={abierta.persona_id}
            supabase={supabase}
            fila={abierta}
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
  const plazo = f.estado === "por_empezar" ? `Empieza el ${fecha(f.fecha_inicio)}` : textoPlazo(f);
  const detalle = [f.servicio, f.sede].filter(Boolean).join(" · ");
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
  supabase, fila, alCambiar, alOcupar,
}: {
  supabase: ClienteCayla;
  fila: FilaTableroLocacion;
  /** Avisa que se registró algo, para que el tablero se ponga al día. */
  alCambiar: () => void;
  alOcupar: (ocupado: boolean) => void;
}) {
  const { avisar } = useToast();
  const [contratos, setContratos] = useState<ContratoLocacion[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [cargando, setCargando] = useState(true);
  // Quien no tiene ningún contrato llega aquí a registrarlo: el formulario ya está abierto.
  const [registrando, setRegistrando] = useState(fila.estado === "sin_contrato");

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

  return (
    <div className="space-y-4">
      {error && <BannerAviso enLinea role="alert">{error}</BannerAviso>}

      {registrando ? (
        <FormRegistrar
          supabase={supabase}
          fila={fila}
          servicioAnterior={contratos.find((c) => c.estado !== "anulado")?.servicio ?? ""}
          alCancelar={() => setRegistrando(false)}
          alOcupar={alOcupar}
          alRegistrar={() => {
            setRegistrando(false);
            avisar("ok", "Contrato registrado.");
            void cargar();
            alCambiar();
          }}
        />
      ) : (
        <Boton variante="primario" onClick={() => setRegistrando(true)}>Registrar contrato firmado</Boton>
      )}

      {!error && contratos.length === 0 && !registrando && (
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
                    Firmado el {fecha(c.fecha_firma)} · registrado por {c.registrado_por_nombre ?? "—"}
                  </p>
                  {c.terminado_el && c.terminado_motivo && (
                    <p className="text-xs text-taupe">Terminado: {c.terminado_motivo} ({c.terminado_por_nombre ?? "—"})</p>
                  )}
                  {c.anulado_at && c.anulado_motivo && (
                    <p className="text-xs text-taupe">Anulado: {c.anulado_motivo} ({c.anulado_por_nombre ?? "—"})</p>
                  )}
                  <div className="pt-1">
                    <Boton variante="enlace" className="text-xs" onClick={() => void ver(c)}>Ver contrato</Boton>
                  </div>
                </TarjetaInfo>
              </li>
            );
          })}
        </ul>
      )}
    </div>
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

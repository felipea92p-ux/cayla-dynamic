"use client";

// ============================================================================
// Lista de asegurados — quiénes están en un seguro, lista para el contador
// ============================================================================
// QUÉ PROMETE
//   Elegir un seguro y ver quiénes están en él HOY con lo que la aseguradora y el contador piden
//   para emitir el certificado de cada persona (documento, fecha de nacimiento, ingreso, su
//   póliza), y señalar a quien le falta un dato. Para la dirección, además, bajarlo en un CSV.
//   Migración 0528: `fn_seguro_asegurados`. Felipe, 2026-10-17: «que el propio sistema lo jale y
//   no se tenga que rellenar los datos de nuevo».
//
// QUIÉN LA VE Y QUIÉN SE LA LLEVA
//   La ve DO (la base se lo exige): ya ve el documento y la fecha de nacimiento en la ficha de cada
//   persona. El ARCHIVO es otro permiso —ver un dato y llevárselo no son lo mismo—: hoy lo tienen DO y
//   la dirección (`puedeExportarListaDeAsegurados`; Felipe, 2026-10-17: quien trata con la aseguradora y
//   el contador es DO). Si algún día se estrecha, a quien no pueda se le explica por qué no hay botón,
//   para que no crea que falla.
//
// LA REMUNERACIÓN NO VIAJA A LA PANTALLA
//   El seguro de vida la pide («remuneración asegurable»). Solo se trae al DESCARGAR y solo si se
//   marca la casilla: la vista previa se pide sin ella, así que un sueldo nunca queda en el estado
//   de la pantalla ni a la vista de quien no lo necesita.
//
// QUÉ NO HACE
//   No decide quién está en un seguro (lo dice la base) ni da por completo un dato que falta: lo
//   deja VACÍO y señalado, en pantalla y en la columna REVISAR del archivo.
// ============================================================================

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { Cargando } from "@/components/cargando";
import { useToast } from "@/components/toast";
import { Boton } from "@/components/ui/boton";
import { CampoCasilla, CampoSelect } from "@/components/ui/campo";
import { Insignia } from "@/components/ui/insignia";
import { Modal } from "@/components/ui/modal";
import { Fila, Tabla, TablaEncabezado, Th } from "@/components/ui/tabla";
import { descargarCsv, generarCsv } from "@/lib/admin/csv";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { isoADiaMesAnio } from "@/lib/admin/planilla/formato";
import { etiquetaVinculo, plural, type TipoSeguro } from "@/lib/admin/seguros";
import {
  columnasDeLista, datosQueFaltan, etiquetaDeDocumento, filasDeLista, nombreDeArchivoDeLista, resumenDeLista,
  type Asegurado,
} from "@/lib/admin/seguros-asegurados";
import { AvisoDeError } from "./aviso-de-error";

export function ListaDeAsegurados({
  abierto, onCerrar, supabase, tipos, inicial, puedeDescargar, hoy,
}: {
  abierto: boolean;
  onCerrar: () => void;
  supabase: ClienteCayla;
  tipos: TipoSeguro[];
  /** El seguro con el que abre (el que la pantalla tenía filtrado), si lo hay. */
  inicial: string | null;
  /** `puedeExportarListaDeAsegurados`: quién se lleva el archivo (hoy DO y la dirección). */
  puedeDescargar: boolean;
  hoy: string;
}) {
  const [ocupado, setOcupado] = useState(false);
  return (
    <Modal abierto={abierto} onCerrar={() => { if (!ocupado) onCerrar(); }} bloqueado={ocupado} titulo="Lista de asegurados" ancho="xl">
      {/* Se monta de nuevo cada vez que se abre: así nace con el seguro de ahora y pide la lista fresca. */}
      {abierto && <Cuerpo supabase={supabase} tipos={tipos} inicial={inicial} puedeDescargar={puedeDescargar} hoy={hoy} onCerrar={onCerrar} onOcupado={setOcupado} />}
    </Modal>
  );
}

function Cuerpo({
  supabase, tipos, inicial, puedeDescargar, hoy, onCerrar, onOcupado,
}: {
  supabase: ClienteCayla; tipos: TipoSeguro[]; inicial: string | null; puedeDescargar: boolean; hoy: string;
  onCerrar: () => void; onOcupado: (ocupado: boolean) => void;
}) {
  const { avisar } = useToast();
  // Los seguros que pueden tener gente: los vivos y los archivados que todavía cubren a alguien.
  const opciones = tipos.filter((t) => t.activo || t.personas > 0 || t.polizas_vigentes > 0);
  const [clave, setClave] = useState(() => (opciones.some((t) => t.clave === inicial) ? inicial! : opciones[0]?.clave ?? ""));
  const [filas, setFilas] = useState<Asegurado[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [conRemuneracion, setConRemuneracion] = useState(false);
  const [descargando, setDescargando] = useState(false);
  // La respuesta que llega tarde de un seguro que ya no está elegido se descarta.
  const pedido = useRef(0);

  const cargar = useCallback(async (producto: string) => {
    const mio = ++pedido.current;
    const { data, error: e } = await supabase.rpc("fn_seguro_asegurados", { p_producto: producto });
    if (mio !== pedido.current) return;
    if (e) { setError(mensajeDeError(e, "cargar la lista")); return; }
    setFilas((data as Asegurado[] | null) ?? []);
  }, [supabase]);

  // `cargar` solo pone estado después de su `await`: no hay renders en cascada.
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { if (clave) void cargar(clave); }, [clave, cargar]);

  function cambiarSeguro(nuevo: string) {
    setClave(nuevo); setFilas(null); setError(null);
  }
  // «Reintentar» no cambia el seguro, así que el efecto no vuelve a correr solo: se pide a mano.
  function reintentar() {
    setFilas(null); setError(null);
    void cargar(clave);
  }

  const tipo = tipos.find((t) => t.clave === clave);
  const resumen = filas ? resumenDeLista(filas) : null;

  async function descargar() {
    if (!filas || filas.length === 0) return;
    setDescargando(true); onOcupado(true);
    // Se vuelve a pedir AL DESCARGAR: el archivo sale con lo de ahora, y la remuneración viaja solo si se pidió.
    const { data, error: e } = await supabase.rpc("fn_seguro_asegurados", { p_producto: clave, p_con_remuneracion: conRemuneracion });
    setDescargando(false); onOcupado(false);
    if (e) { avisar("error", mensajeDeError(e, "descargar la lista")); return; }
    const lista = (data as Asegurado[] | null) ?? [];
    descargarCsv(nombreDeArchivoDeLista(clave, hoy), generarCsv(filasDeLista(lista, conRemuneracion), columnasDeLista(conRemuneracion)));
    const faltan = resumenDeLista(lista, conRemuneracion).incompletas;
    avisar("ok", `Descargadas ${plural(lista.length, "persona", "personas")}${faltan > 0 ? `; a ${faltan} les falta algún dato (columna REVISAR)` : ""}. `
      + "Lleva documento y fecha de nacimiento: compártelo por un canal que puedas revocar y bórralo al terminar.");
  }

  return (
    <>
      <p className="mb-3 text-sm text-taupe">
        Quiénes están en un seguro hoy, con lo que la aseguradora y el contador piden para emitir el certificado de cada persona.
        Es información personal.
      </p>

      <div className="mb-3 max-w-md">
        <CampoSelect etiqueta="Seguro" value={clave} onChange={(e) => cambiarSeguro(e.target.value)}>
          {opciones.map((t) => <option key={t.clave} value={t.clave}>{t.nombre}{t.principal ? "" : " (va además del principal)"}</option>)}
        </CampoSelect>
        {tipo && (
          <span className="mt-1 block text-xs text-taupe">
            {tipo.principal
              ? `Las personas activas cuyo seguro es ${tipo.nombre}${tipo.con_poliza ? " (tengan ya su póliza o no)" : ""}, y quien conserva una póliza vigente.`
              : `Las personas con una póliza vigente de ${tipo.nombre}.`}
          </span>
        )}
      </div>

      {error ? (
        <div className="mb-3">
          <AvisoDeError mensaje={error} />
          <Boton variante="enlace" onClick={reintentar}>Reintentar</Boton>
        </div>
      ) : filas === null ? <Cargando /> : filas.length === 0 ? (
        <p className="rounded-lg bg-hueso px-3 py-3 text-sm text-taupe">Nadie está en {tipo?.nombre ?? "este seguro"} hoy.</p>
      ) : (
        <>
          <p className="mb-2 text-sm text-tinta" aria-live="polite">
            {plural(resumen!.total, "persona", "personas")}
            {resumen!.inactivas > 0 && <span className="text-taupe"> · {resumen!.inactivas} ya no {resumen!.inactivas === 1 ? "está activa" : "están activas"} (pedir la baja)</span>}
            {resumen!.incompletas > 0 && <span className="text-ambar"> · {resumen!.incompletas} con datos por completar</span>}
          </p>
          {resumen!.incompletas > 0 && (
            <p className="mb-2 text-xs text-taupe">
              Sin documento o sin fecha de nacimiento la aseguradora no emite el certificado de esa persona y queda fuera de la póliza sin que nadie lo note.
              Se completan en <Link href="/admin/datos-personales" className="underline underline-offset-2 hover:text-tinta">Datos personales</Link>.
            </p>
          )}
          <Tabla alturaMaxima="45vh">
            <TablaEncabezado>
              <Th>Persona</Th><Th>Documento</Th><Th>Nacimiento</Th><Th>Ingreso</Th><Th>Sede · vínculo</Th><Th>Póliza</Th>
            </TablaEncabezado>
            <tbody>
              {filas.map((a) => <FilaDeLista key={a.persona_id} a={a} conPoliza={tipo?.con_poliza ?? true} />)}
            </tbody>
          </Tabla>
        </>
      )}

      <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
        <div className="min-w-0 flex-1 text-xs text-taupe">
          {puedeDescargar ? (
            <CampoCasilla
              etiqueta="Incluir la remuneración asegurable (la piden los seguros de vida)"
              checked={conRemuneracion} onChange={(e) => setConRemuneracion(e.target.checked)} disabled={descargando}
            />
          ) : (
            <>Tu cuenta no puede descargar el archivo con documento y fecha de nacimiento. Aquí ves quién falta completar.</>
          )}
        </div>
        <div className="flex gap-2">
          <Boton onClick={onCerrar} disabled={descargando}>Cerrar</Boton>
          {puedeDescargar && (
            <Boton variante="primario" onClick={() => void descargar()} cargando={descargando} disabled={!filas || filas.length === 0}>
              Descargar CSV
            </Boton>
          )}
        </div>
      </div>
    </>
  );
}

const faltaEnAmbar = <span className="text-ambar">falta</span>;

function FilaDeLista({ a, conPoliza }: { a: Asegurado; conPoliza: boolean }) {
  const faltan = datosQueFaltan(a);
  return (
    <Fila>
      <td className="px-4 py-2 align-top">
        <span className="text-tinta">{a.apellidos}, {a.nombres}</span>
        {!a.activa && <Insignia variante="advertencia" tamano="sm" className="ml-1.5">ya no está activa</Insignia>}
      </td>
      <td className="whitespace-nowrap px-4 py-2 align-top">
        {faltan.includes("documento") ? faltaEnAmbar : <><span className="text-taupe">{etiquetaDeDocumento(a.tipo_documento)}</span> {a.documento}</>}
      </td>
      <td className="whitespace-nowrap px-4 py-2 align-top">
        {faltan.includes("fecha_nacimiento") ? faltaEnAmbar : isoADiaMesAnio(a.fecha_nacimiento!)}
      </td>
      <td className="whitespace-nowrap px-4 py-2 align-top text-taupe">{a.fecha_ingreso ? isoADiaMesAnio(a.fecha_ingreso) : "—"}</td>
      <td className="whitespace-nowrap px-4 py-2 align-top text-taupe">{a.sede} · {etiquetaVinculo(a.tipo_vinculo)}</td>
      <td className="whitespace-nowrap px-4 py-2 align-top">
        {a.numero_poliza
          ? <>{a.numero_poliza} <span className="text-taupe">hasta {isoADiaMesAnio(a.vigente_hasta!)}</span></>
          : conPoliza ? <span className="text-ambar">sin póliza vigente</span> : <span className="text-taupe">por planilla</span>}
      </td>
    </Fila>
  );
}

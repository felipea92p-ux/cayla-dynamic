"use client";

// ============================================================================
// Leer el PDF de una póliza — para no volver a teclear lo que el papel ya dice
// ============================================================================
// QUÉ PROMETE
//   Elegir uno o varios PDF de póliza (uno por persona, como los manda el corredor), ver lo que el sistema
//   entendió de cada uno —número, vigencia, prima con IGV, vencimiento del pago, a quién asegura— y
//   registrarlas de una vez, con su PDF guardado en cada una. Felipe, 2026-10-17: «que el propio sistema lo
//   jale y no se tenga que rellenar los datos de nuevo». Cada trimestre llegan los PDF de FOLA de todos los
//   practicantes: antes eran cinco datos por persona a mano.
//
// LO LEÍDO ES UNA PROPUESTA, NUNCA UN REGISTRO
//   Cada póliza se muestra en una tarjeta con sus campos editables. Solo nace seleccionada la que trae número,
//   vigencia y prima Y una persona clara; el resto espera a que DO la complete. Nada se guarda hasta apretar
//   «Registrar». Y se registra con `fn_seguro_registrar`, la misma función y las mismas reglas que el
//   formulario: este diálogo no tiene reglas propias, solo ADELANTA sus rechazos (la persona no está en ese
//   seguro, la póliza se cruza con otra) para que se vean en la tarjeta y no al final.
//
// SE LEE AQUÍ, EN EL NAVEGADOR
//   El PDF lleva documento y fecha de nacimiento del asegurado. Hasta que se registra, su contenido no sale de la
//   computadora de quien lo abrió (`leer-poliza-pdf.ts`). Después se sube a la póliza como cualquier archivo.
//
// SI UNA DE VARIAS FALLA
//   Cada póliza es una llamada aparte (cada una con su persona bloqueada, su evento y su archivo): las que
//   quedaron se marcan «Registrada», la que falló dice por qué y se puede corregir y repetir, y nada se deshace.
//   Si la póliza quedó pero su PDF no subió, se dice así: la póliza no se pierde por un archivo.
//
// QUÉ NO HACE
//   No lee fotos escaneadas (sin texto no hay qué leer: «regístrala a mano»), no inventa lo que no está y no
//   registra la misma póliza dos veces: la que ya existe (misma persona, seguro, número e inicio) sale marcada.
// ============================================================================

import { useState } from "react";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoCasilla, CampoSelect } from "@/components/ui/campo";
import { cx } from "@/components/ui/cx";
import { Insignia } from "@/components/ui/insignia";
import { Modal } from "@/components/ui/modal";
import { problemaDeArchivo } from "@/lib/admin/archivo";
import {
  erroresDeTarjeta, productoSugerido, tarjetaDeLectura, yaRegistrada,
  type EstadoDeTarjeta, type TarjetaDePoliza,
} from "@/lib/admin/importar-polizas";
import { leerPolizas } from "@/lib/admin/leer-poliza";
import { textoDeLasPaginas } from "@/lib/admin/leer-poliza-pdf";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import {
  numeroDeTexto, personasParaPoliza, plural, type Poliza, type TipoSeguro,
} from "@/lib/admin/seguros";
import { adjuntarArchivoAPoliza } from "@/lib/admin/seguros-archivos";
import { pesoLegible } from "@/lib/reducir-imagen";
import { AvisoDeError } from "./aviso-de-error";
import type { OpcionPersona } from "./formulario-poliza";

/** Cuántos PDF a la vez: la empresa tiene unas treinta personas, y cada PDF se lee entero en esta computadora. */
const MAX_ARCHIVOS = 20;

type Tarjeta = TarjetaDePoliza<File>;

export function LeerPdfDePoliza({
  abierto, onCerrar, supabase, tipos, personas, polizas, hoy, onRegistradas,
}: {
  abierto: boolean;
  onCerrar: () => void;
  supabase: ClienteCayla;
  tipos: TipoSeguro[];
  /** A quién se puede asegurar: las personas activas, con su seguro principal de hoy. */
  personas: OpcionPersona[];
  /** Las pólizas vivas: para avisar de la que ya existe y de la que se cruzaría. */
  polizas: Poliza[];
  hoy: string;
  /** Se llama al terminar de registrar, con cuántas quedaron: la pantalla recarga y avisa. El diálogo sigue abierto. */
  onRegistradas: (cuantas: number) => void | Promise<void>;
}) {
  const [ocupado, setOcupado] = useState(false);
  return (
    <Modal abierto={abierto} onCerrar={() => { if (!ocupado) onCerrar(); }} bloqueado={ocupado} titulo="Leer el PDF de una póliza" ancho="xl">
      {/* Se monta de nuevo cada vez que se abre: así nace sin lo que se leyó la vez anterior. */}
      {abierto && (
        <Cuerpo
          supabase={supabase} tipos={tipos} personas={personas} polizas={polizas} hoy={hoy}
          onCerrar={onCerrar} onOcupado={setOcupado} onRegistradas={onRegistradas}
        />
      )}
    </Modal>
  );
}

function Cuerpo({
  supabase, tipos, personas, polizas, hoy, onCerrar, onOcupado, onRegistradas,
}: {
  supabase: ClienteCayla; tipos: TipoSeguro[]; personas: OpcionPersona[]; polizas: Poliza[]; hoy: string;
  onCerrar: () => void; onOcupado: (ocupado: boolean) => void; onRegistradas: (cuantas: number) => void | Promise<void>;
}) {
  const [tarjetas, setTarjetas] = useState<Tarjeta[] | null>(null);
  const [sinLeer, setSinLeer] = useState<{ archivo: string; motivo: string }[]>([]);
  const [leyendo, setLeyendo] = useState<{ hechas: number; total: number } | null>(null);
  const [producto, setProducto] = useState("");
  const [guardarPdf, setGuardarPdf] = useState(true);
  const [registrando, setRegistrando] = useState(false);
  const [aviso, setAviso] = useState<string | null>(null);
  // Cambiar la clave vacía el campo de archivo: sin esto, elegir otra vez el MISMO PDF no dispara nada.
  const [claveInput, setClaveInput] = useState(0);

  const ofrecidos = tipos.filter((t) => t.activo && t.con_poliza);
  const candidatas = personasParaPoliza(producto, tipos, personas);

  // ── Leer ──────────────────────────────────────────────────────────────
  async function leer(elegidos: File[]) {
    setAviso(null);
    if (elegidos.length === 0) return;
    if (elegidos.length > MAX_ARCHIVOS) {
      setAviso(`Elige hasta ${MAX_ARCHIVOS} PDF a la vez (elegiste ${elegidos.length}).`);
      return;
    }
    setLeyendo({ hechas: 0, total: elegidos.length }); onOcupado(true);
    setTarjetas(null); setSinLeer([]);

    const nuevas: Tarjeta[] = [];
    const fallidos: { archivo: string; motivo: string }[] = [];
    try {
      for (let i = 0; i < elegidos.length; i++) {
        const f = elegidos[i];
        try {
          const problema = problemaDeArchivo(f);
          if (problema) fallidos.push({ archivo: f.name, motivo: problema });
          else {
            const lectura = await textoDeLasPaginas(f);
            if (!lectura.ok) fallidos.push({ archivo: f.name, motivo: lectura.motivo });
            else {
              const leidas = leerPolizas(lectura.paginas);
              if (leidas.length === 0) {
                fallidos.push({
                  archivo: f.name,
                  motivo: lectura.paginas.every((p) => p.trim() === "")
                    ? "No tiene texto que se pueda leer (¿es una foto escaneada?). Regístrala a mano."
                    : "No encontré en él los datos de una póliza. Regístrala a mano.",
                });
              } else {
                leidas.forEach((l, n) => nuevas.push(tarjetaDeLectura(f, i, n, l, personas, hoy)));
              }
            }
          }
        } catch {
          // Un PDF raro no puede tirar el lote ni dejar el diálogo bloqueado: se dice por su nombre y sigue el siguiente.
          fallidos.push({ archivo: f.name, motivo: "No se pudo leer. Regístrala a mano." });
        }
        setLeyendo({ hechas: i + 1, total: elegidos.length });
      }
    } finally {
      setLeyendo(null); onOcupado(false);
    }
    setSinLeer(fallidos);
    setTarjetas(nuevas);
    setProducto((actual) => actual || productoSugerido(nuevas, personas, tipos));
    setClaveInput((n) => n + 1);
  }

  // ── Editar una tarjeta ────────────────────────────────────────────────
  function cambiar(clave: string, cambio: Partial<Tarjeta>) {
    setTarjetas((ts) => ts?.map((t) => (t.clave === clave ? { ...t, ...cambio } : t)) ?? null);
  }

  // ── Qué se puede registrar ────────────────────────────────────────────
  const lote = tarjetas ?? [];
  const contexto = { producto, tipos, personas, polizas, lote };
  const vista = lote.map((t) => {
    const registrada = t.estado.tipo === "registrada";
    const yaEsta = !registrada && yaRegistrada(t, producto, polizas);
    const errores = registrada || yaEsta || !t.incluir ? [] : erroresDeTarjeta(t, contexto);
    return { t, registrada, yaEsta, errores };
  });
  const seleccionadas = vista.filter((v) => v.t.incluir && !v.registrada && !v.yaEsta);
  const conErrores = seleccionadas.filter((v) => v.errores.length > 0).length;
  const listas = seleccionadas.length - conErrores;
  const yaRegistradasAhora = vista.filter((v) => v.registrada).length;
  const puedeRegistrar = producto !== "" && listas > 0 && conErrores === 0 && !registrando;

  // ── Registrar ─────────────────────────────────────────────────────────
  async function registrar() {
    setAviso(null); setRegistrando(true); onOcupado(true);
    let hechas = 0;
    try {
      for (const { t, errores, registrada, yaEsta } of vista) {
        if (!t.incluir || registrada || yaEsta || errores.length > 0) continue;
        const { data, error } = await supabase.rpc("fn_seguro_registrar", {
          p_persona_id: t.personaId, p_producto: producto,
          p_aseguradora: t.aseguradora.trim(), p_numero_poliza: t.numero.trim(),
          p_vigente_desde: t.desde, p_vigente_hasta: t.hasta, p_prima_total: numeroDeTexto(t.prima)!,
          p_prima_vence_el: t.primaVence || null, p_plan: null, p_beneficio_enfermedad: null, p_beneficio_accidente: null,
          p_renueva_sola: null, p_nota: t.nota.trim() || null,
        });
        if (error || typeof data !== "string") {
          cambiar(t.clave, { estado: { tipo: "error", mensaje: mensajeDeError(error, "guardar") } });
          continue;
        }
        hechas += 1;
        let estado: EstadoDeTarjeta;
        if (!guardarPdf) estado = { tipo: "registrada", pdf: "omitido" };
        else {
          const subido = await adjuntarArchivoAPoliza(supabase, data, "poliza", t.archivo);
          estado = { tipo: "registrada", pdf: subido.ok ? "guardado" : { error: subido.error } };
        }
        cambiar(t.clave, { estado });
      }
    } finally {
      // Pase lo que pase se desbloquea el diálogo, y la pantalla recarga con lo que SÍ quedó registrado.
      setRegistrando(false); onOcupado(false);
      await onRegistradas(hechas);
    }
  }

  return (
    <>
      <p className="mb-3 text-sm text-taupe">
        Elige el PDF de la póliza —o varios, uno por persona— y el sistema lee el número, la vigencia, la prima y a quién asegura.
        Se lee aquí, en tu computadora: no se sube ni se guarda nada hasta que revises y registres.
      </p>

      {aviso && <AvisoDeError mensaje={aviso} />}

      <label className="mb-3 flex min-w-0 flex-col gap-1">
        <span className="text-sm text-taupe">PDF de la póliza</span>
        <input
          key={claveInput}
          type="file"
          multiple
          accept="application/pdf,.pdf"
          disabled={leyendo !== null || registrando}
          onChange={(e) => void leer([...(e.target.files ?? [])])}
          className="w-full min-w-0 rounded-control border border-sand bg-papel px-3 py-2 text-sm text-tinta file:mr-2 file:rounded file:border-0 file:bg-sand file:px-2 file:py-0.5 file:text-xs file:text-tinta"
        />
      </label>

      {leyendo && <p className="mb-3 text-sm text-taupe" role="status">Leyendo… {leyendo.hechas} de {leyendo.total}</p>}

      {sinLeer.length > 0 && (
        <ul className="mb-3 space-y-1" aria-label="PDF que no se pudieron leer">
          {sinLeer.map((s) => (
            <li key={s.archivo} className="rounded-lg bg-ambar/15 px-3 py-2 text-sm text-ambar">
              <span className="break-words font-medium">{s.archivo}</span>: {s.motivo}
            </li>
          ))}
        </ul>
      )}

      {tarjetas && tarjetas.length > 0 && (
        <>
          <div className="mb-3 max-w-md">
            <CampoSelect
              etiqueta="Seguro de estas pólizas"
              value={producto}
              disabled={registrando || yaRegistradasAhora > 0}
              onChange={(e) => setProducto(e.target.value)}
              error={producto === "" ? "Elige el seguro: el papel no dice cuál es en Dynamic." : undefined}
            >
              <option value="">Elige el seguro</option>
              {ofrecidos.map((t) => <option key={t.clave} value={t.clave}>{t.nombre}{t.principal ? "" : " (va además del principal)"}</option>)}
            </CampoSelect>
          </div>

          <p className="mb-2 text-sm text-tinta" aria-live="polite">
            Leí {plural(tarjetas.length, "póliza", "pólizas")}. Revísalas: lo que dice el papel es una propuesta, y tú eliges a quién va cada una.
          </p>

          <ul className="space-y-3">
            {vista.map((v) => (
              <TarjetaDePdf
                key={v.t.clave} t={v.t} registrada={v.registrada} yaEsta={v.yaEsta} errores={v.errores}
                candidatas={candidatas} producto={producto} bloqueada={registrando}
                onCambio={(c) => cambiar(v.t.clave, c)}
              />
            ))}
          </ul>

          <div className="mt-4">
            <CampoCasilla
              etiqueta="Guardar también el PDF en cada póliza"
              checked={guardarPdf} onChange={(e) => setGuardarPdf(e.target.checked)} disabled={registrando}
            />
          </div>
        </>
      )}

      <div className="mt-5 flex flex-wrap items-center justify-between gap-3">
        <p className="min-w-0 flex-1 text-xs text-taupe">
          {conErrores > 0
            ? `Corrige ${plural(conErrores, "póliza marcada", "pólizas marcadas")} en rojo, o quítales la selección.`
            : yaRegistradasAhora > 0 ? `${plural(yaRegistradasAhora, "póliza registrada", "pólizas registradas")} en esta sesión.` : ""}
        </p>
        <div className="flex gap-2">
          <Boton onClick={onCerrar} disabled={registrando || leyendo !== null}>{yaRegistradasAhora > 0 ? "Listo" : "Cerrar"}</Boton>
          {/* Cuando ya no queda nada por registrar, el botón sobra: «Registrar 0 pólizas» no dice nada. */}
          {tarjetas && tarjetas.length > 0 && !(seleccionadas.length === 0 && yaRegistradasAhora > 0) && (
            <Boton variante="primario" onClick={() => void registrar()} cargando={registrando} disabled={!puedeRegistrar}>
              {registrando ? "Registrando…" : `Registrar ${plural(listas, "póliza", "pólizas")}`}
            </Boton>
          )}
        </div>
      </div>
    </>
  );
}

function TarjetaDePdf({
  t, registrada, yaEsta, errores, candidatas, producto, bloqueada, onCambio,
}: {
  t: Tarjeta; registrada: boolean; yaEsta: boolean; errores: string[];
  candidatas: OpcionPersona[]; producto: string; bloqueada: boolean;
  onCambio: (cambio: Partial<Tarjeta>) => void;
}) {
  const sinEditar = bloqueada || registrada;
  const dias = t.desde && t.hasta && t.hasta > t.desde ? Math.round((Date.parse(t.hasta) - Date.parse(t.desde)) / 86_400_000) : null;
  const e = t.estado;

  return (
    <li className={cx(
      "rounded-xl border px-4 py-3",
      registrada ? "border-verde/40 bg-verde/5" : errores.length > 0 ? "border-rojo/40 bg-papel" : t.incluir && !yaEsta ? "border-tinta/30 bg-papel" : "border-sand bg-hueso",
    )}>
      <div className="flex flex-wrap items-start justify-between gap-2">
        <label className="flex min-w-0 flex-1 items-start gap-2">
          <input
            type="checkbox" className="mt-1 size-4 shrink-0 accent-tinta"
            checked={t.incluir && !yaEsta} disabled={sinEditar || yaEsta}
            onChange={(ev) => onCambio({ incluir: ev.target.checked })}
          />
          <span className="min-w-0">
            <span className="block text-sm text-tinta">
              Póliza {t.leida.numero}{t.leida.producto && <span className="text-taupe"> · {t.leida.producto}</span>}
            </span>
            <span className="block break-words text-xs text-taupe">
              {t.archivo.name} · {pesoLegible(t.archivo.size)}
              {t.leida.asegurado && <> · en el papel: {t.leida.asegurado.nombre} (doc. {t.leida.asegurado.documento})</>}
            </span>
          </span>
        </label>
        {registrada && <Insignia variante="positivo">Registrada</Insignia>}
        {yaEsta && <Insignia variante="neutral">Ya estaba registrada</Insignia>}
        {e.tipo === "error" && <Insignia variante="alerta">No se registró</Insignia>}
      </div>

      {e.tipo === "registrada" && (
        <p className={cx("mt-2 text-sm", typeof e.pdf === "object" ? "text-ambar" : "text-verde")}>
          {e.pdf === "guardado" ? "Registrada, con su PDF guardado."
            : e.pdf === "omitido" ? "Registrada. No se guardó el PDF, como pediste."
            : `Registrada, pero su PDF no se guardó (${e.pdf.error}). Súbelo desde «Adjuntar PDF» en su tarjeta.`}
        </p>
      )}
      {e.tipo === "error" && <p role="alert" className="mt-2 text-sm text-rojo">{e.mensaje}</p>}
      {yaEsta && <p className="mt-2 text-sm text-taupe">Esta póliza ya está en el sistema (mismo seguro, número e inicio): no se vuelve a registrar.</p>}

      {!registrada && !yaEsta && (
        <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2">
          <CampoSelect etiqueta="A quién asegura" value={t.personaId} disabled={sinEditar} onChange={(ev) => onCambio({ personaId: ev.target.value })}>
            <option value="">{producto || candidatas.length > 0 ? "Elige a la persona" : "Elige primero el seguro"}</option>
            {candidatas.map((p) => <option key={p.id} value={p.id}>{p.nombre} · {p.sede}</option>)}
          </CampoSelect>
          <Campo etiqueta="Número de póliza" value={t.numero} disabled={sinEditar} onChange={(ev) => onCambio({ numero: ev.target.value })} />
          <Campo etiqueta="Vigente desde" type="date" value={t.desde} disabled={sinEditar} onChange={(ev) => onCambio({ desde: ev.target.value })} />
          <div>
            <Campo
              etiqueta="Hasta (la póliza deja de cubrir ese día, a las 12 M)" type="date" value={t.hasta} min={t.desde || undefined}
              disabled={sinEditar} onChange={(ev) => onCambio({ hasta: ev.target.value })}
            />
            {dias !== null && <span className="mt-1 block text-xs text-taupe">{dias} días de vigencia.</span>}
          </div>
          <Campo
            etiqueta="Prima total (con IGV), en soles" inputMode="decimal" value={t.prima} disabled={sinEditar}
            onChange={(ev) => onCambio({ prima: ev.target.value })}
          />
          <div>
            <Campo
              etiqueta="La prima vence el (opcional)" type="date" value={t.primaVence} disabled={sinEditar}
              onChange={(ev) => onCambio({ primaVence: ev.target.value })}
            />
            <span className="mt-1 block text-xs text-taupe">Con 30 días de mora desde esa fecha, la cobertura se suspende sola.</span>
          </div>
          <Campo etiqueta="Aseguradora" value={t.aseguradora} disabled={sinEditar} onChange={(ev) => onCambio({ aseguradora: ev.target.value })} />
        </div>
      )}

      {!registrada && !yaEsta && t.leida.avisos.length > 0 && (
        <ul className="mt-3 space-y-0.5" aria-label="Lo que conviene revisar de esta póliza">
          {t.leida.avisos.map((a) => <li key={a} className="text-xs text-ambar">{a}</li>)}
        </ul>
      )}
      {errores.length > 0 && (
        <ul className="mt-3 space-y-0.5" role="alert" aria-label="Lo que impide registrar esta póliza">
          {errores.map((m) => <li key={m} className="text-xs text-rojo">{m}</li>)}
        </ul>
      )}
      {!registrada && !yaEsta && t.nota && <p className="mt-2 text-xs text-taupe">Se guarda con la nota «{t.nota}».</p>}
    </li>
  );
}

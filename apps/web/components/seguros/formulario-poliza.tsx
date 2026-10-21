"use client";

// ============================================================================
// Formulario de una póliza — registrar una nueva, una renovación, o corregir una
// ============================================================================
// QUÉ PROMETE
//   Un solo diálogo para las tres cosas: el seguro y la persona (fijos si se corrige),
//   las fechas de la vigencia, la prima, y lo que el papel no dice y el corredor aún no
//   confirmó (plan, beneficios, si renueva sola), que se puede dejar «sin confirmar».
//   Migración 0528: `fn_seguro_registrar` y `fn_seguro_corregir`.
//
// QUÉ SEGUROS Y QUÉ PERSONAS OFRECE
//   Los seguros que llevan póliza y siguen vivos —EsSalud no está: se paga con la
//   planilla—. Si el seguro es el PRINCIPAL de la persona, solo se ofrece a quienes lo
//   tienen hoy (a alguien de planilla no se le registra una póliza FOLA: primero se le
//   cambia el seguro). Si va además del principal, se ofrece a cualquier persona activa.
//   La base vuelve a comprobarlo; esto solo evita llegar al error.
//
// LAS FECHAS NACEN CON VALOR (CLAUDE.md, regla del 2026-08-26): «Desde» arranca
//   en hoy —o en el día en que termina la póliza que se renueva— y «Hasta» en tres
//   meses después, que es la póliza de hoy (92 días). Un campo de fecha que
//   bloquea el envío no puede arrancar vacío. «Hasta» sigue a «Desde» mientras
//   nadie lo toque, y tres botones lo mueven a 3 meses, 6 meses o un año.
//
// UNA PÓLIZA PARA VARIAS PERSONAS (Felipe, 2026-10-17: «que el propio sistema lo jale y no se
//   tenga que rellenar los datos de nuevo»). Un seguro de vida o una EPS es UNA póliza con un
//   solo número que cubre a todos: en vez de teclearla persona por persona, se eligen las
//   personas en una lista (con el atajo «las de planilla») y se registra a todas de una vez
//   con `fn_seguro_registrar_varias`. TODO O NADA: si a una no se le puede registrar, no se
//   registra a nadie y el mensaje dice con quién falló. La lista ya deja fuera, con el motivo
//   a la vista, a quien tiene una póliza de ese seguro que se cruza con las fechas: la base
//   rechazaría el lote entero por esa sola persona.
//   La PRIMA es la de CADA persona (una fila por persona): el formulario suma «N × prima» para
//   que se vea el total de la póliza y no se escriba el total en cada fila.
//
// QUÉ NO HACE
//   No decide si la póliza se cruza con otra: eso lo decide la base y su mensaje se
//   muestra tal cual. (La lista de varias personas solo ADELANTA ese aviso para no ofrecer
//   a quien se sabe que no se puede.)
// ============================================================================

import { useState } from "react";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { hoyLima } from "@cayla-dynamic/shared";
import { AreaTexto } from "@/components/ui/area-texto";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { BuscadorPersona } from "@/components/ui/buscador-persona";
import { Filtro } from "@/components/ui/filtro";
import { cx } from "@/components/ui/cx";
import { Modal } from "@/components/ui/modal";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { isoADiaMesAnio } from "@/lib/admin/planilla/formato";
import {
  etiquetaVinculo, fechasSospechosas, numeroDeTexto as numero, personasParaPoliza as personasDe, plural, polizaQueSeCruza, sumarMeses,
  type Poliza, type TipoSeguro,
} from "@/lib/admin/seguros";
import { formatSoles } from "@/lib/rangos";
import { sinTildes } from "@/lib/sin-tildes";
import { AvisoDeError } from "./aviso-de-error";

/** A quién se le puede registrar una póliza: una persona activa y su seguro principal de hoy. */
export interface OpcionPersona {
  id: string; nombre: string; sede: string; tipoPrincipal: string | null;
  /** Tal como la base la calcula (planilla y prueba): el atajo «las de planilla» no deduce nada. */
  enPlanilla: boolean;
  /** `personas.tipo_vinculo`, para rotular a cada quien en la lista. */
  vinculo: string;
}

/** Lo que devuelve `fn_seguro_registrar_varias`: una póliza por persona. */
export interface PolizaRegistrada { persona_id: string; poliza_id: string }

type Modo = "una" | "varias";

/** Lo que una pantalla puede adelantar al abrir: renovar copia aseguradora, número y prima. */
export interface BaseDePoliza {
  personaId?: string;
  producto?: string;
  /** «Registrar otro seguro»: ofrece solo los que van ADEMÁS del principal (el principal de la persona ya tiene su botón). */
  soloAdemas?: boolean;
  aseguradora?: string;
  numeroPoliza?: string;
  desde?: string;
  prima?: number | null;
}

interface Form {
  producto: string;
  personaId: string;
  aseguradora: string;
  numero: string;
  desde: string;
  hasta: string;
  prima: string;
  primaVence: string;
  plan: string;
  benEnfermedad: string;
  benAccidente: string;
  renueva: "" | "si" | "no";
  nota: string;
  motivo: string;
}

const ASEGURADORA_POR_DEFECTO = "Pacífico Seguros";

/** Los seguros a los que se les puede registrar una póliza hoy (con `soloAdemas`, solo los que van además del principal). */
function conPoliza(tipos: TipoSeguro[], soloAdemas = false): TipoSeguro[] {
  return tipos.filter((t) => t.activo && t.con_poliza && (!soloAdemas || !t.principal));
}

function formInicial(corrigiendo: Poliza | null, base: BaseDePoliza | null, tipos: TipoSeguro[], personas: OpcionPersona[]): Form {
  if (corrigiendo) {
    return {
      producto: corrigiendo.producto, personaId: corrigiendo.persona_id,
      aseguradora: corrigiendo.aseguradora, numero: corrigiendo.numero_poliza,
      desde: corrigiendo.vigente_desde, hasta: corrigiendo.vigente_hasta, prima: String(corrigiendo.prima_total),
      primaVence: corrigiendo.prima_vence_el ?? "", plan: corrigiendo.plan ?? "",
      benEnfermedad: corrigiendo.beneficio_enfermedad !== null ? String(corrigiendo.beneficio_enfermedad) : "",
      benAccidente: corrigiendo.beneficio_accidente !== null ? String(corrigiendo.beneficio_accidente) : "",
      renueva: corrigiendo.renueva_sola === null ? "" : corrigiendo.renueva_sola ? "si" : "no",
      nota: corrigiendo.nota ?? "", motivo: "",
    };
  }
  const ofrecidos = conPoliza(tipos, base?.soloAdemas);
  // El seguro: el que dice quien abre; si no, el único que hay; si no, el principal de la persona (si lleva póliza).
  const delPersona = base?.personaId ? personas.find((p) => p.id === base.personaId)?.tipoPrincipal ?? null : null;
  const producto = base?.producto
    ?? (ofrecidos.length === 1 ? ofrecidos[0].clave : (delPersona && ofrecidos.some((t) => t.clave === delPersona) ? delPersona : ""));
  const candidatas = producto ? personasDe(producto, tipos, personas) : personas;
  const desde = base?.desde ?? hoyLima();
  return {
    producto,
    personaId: base?.personaId ?? (candidatas.length === 1 ? candidatas[0].id : ""),
    aseguradora: base?.aseguradora ?? ASEGURADORA_POR_DEFECTO, numero: base?.numeroPoliza ?? "",
    desde, hasta: sumarMeses(desde, 3), prima: base?.prima != null ? String(base.prima) : "", primaVence: "",
    plan: "", benEnfermedad: "", benAccidente: "", renueva: "", nota: "", motivo: "",
  };
}

function erroresDe(f: Form, corrigiendo: boolean, modo: Modo, nElegidas: number, hoy: string): Partial<Record<keyof Form, string>> {
  const e: Partial<Record<keyof Form, string>> = {};
  if (!f.producto) e.producto = "Elige el seguro.";
  if (modo === "una" && !f.personaId) e.personaId = "Elige a quién asegura.";
  if (modo === "varias" && nElegidas === 0) e.personaId = "Elige al menos a una persona.";
  if (f.aseguradora.trim().length < 2) e.aseguradora = "Escribe la aseguradora.";
  if (f.numero.trim().length < 3) e.numero = "Escribe el número de la póliza.";
  if (!f.desde) e.desde = "Falta la fecha de inicio.";
  if (!f.hasta) e.hasta = "Falta la fecha en que termina.";
  else if (f.desde && f.hasta <= f.desde) e.hasta = "Tiene que terminar después de empezar.";
  // Un año mal tecleado (20277) no es una póliza: lo dice la base, y aquí se dice antes y junto al campo.
  const sospechas = fechasSospechosas(f, hoy);
  if (sospechas.vigencia && !e.hasta) e.hasta = sospechas.vigencia;
  if (sospechas.primaVence) e.primaVence = sospechas.primaVence;
  const prima = numero(f.prima);
  if (f.prima.trim() === "") e.prima = "Escribe la prima total (con IGV).";
  else if (prima === null || prima < 0) e.prima = "La prima tiene que ser un monto, 0 o más.";
  for (const [campo, texto] of [["benEnfermedad", f.benEnfermedad], ["benAccidente", f.benAccidente]] as const) {
    const n = numero(texto);
    if (texto.trim() !== "" && (n === null || n <= 0)) e[campo] = "Un monto mayor que 0, o déjalo vacío si no está confirmado.";
  }
  if (corrigiendo && f.motivo.trim().length < 5) e.motivo = "Escribe el motivo (al menos 5 letras).";
  return e;
}

export function FormularioPoliza({
  abierto, onCerrar, supabase, tipos, personas, polizas, corrigiendo, base, onGuardado, onGuardadoVarias,
}: {
  abierto: boolean;
  onCerrar: () => void;
  supabase: ClienteCayla;
  /** El catálogo completo: el formulario elige los que llevan póliza. */
  tipos: TipoSeguro[];
  /** A quién se puede asegurar: las personas activas, con su seguro principal de hoy. */
  personas: OpcionPersona[];
  /** Las pólizas vivas: con ellas la lista de «varias personas» deja fuera, con el motivo, a quien se cruzaría. */
  polizas: Poliza[];
  /** La póliza que se corrige, o null si es una nueva. */
  corrigiendo: Poliza | null;
  base: BaseDePoliza | null;
  /** Recibe el id de la póliza, si es nueva y cómo nombrarla («Ana Prueba · FOLA · póliza 24043267»), para abrir sus archivos. */
  onGuardado: (polizaId: string, nueva: boolean, titulo: string) => void;
  /** La misma póliza registrada a varias personas: una fila por cada una, y de qué seguro y número es (para los avisos). */
  onGuardadoVarias: (registradas: PolizaRegistrada[], resumen: { seguro: string; numero: string }) => void;
}) {
  // Mientras guarda, ni Esc ni un clic en el velo cierran el diálogo: si la base contestara un
  // error con el formulario ya desmontado, no quedaría ni el aviso ni lo escrito.
  const [guardando, setGuardando] = useState(false);
  return (
    <Modal
      abierto={abierto}
      onCerrar={() => { if (!guardando) onCerrar(); }}
      bloqueado={guardando}
      titulo={corrigiendo ? "Corregir una póliza" : base?.soloAdemas ? "Registrar otro seguro" : base?.desde ? "Registrar una renovación" : "Registrar una póliza"}
      ancho="lg"
    >
      {/* Se monta de nuevo cada vez que se abre: así el formulario nace con los
          valores de ESA póliza o de ESA persona, sin un efecto que los copie. */}
      {abierto && (
        <Cuerpo
          onCerrar={onCerrar} supabase={supabase} tipos={tipos} personas={personas} polizas={polizas}
          corrigiendo={corrigiendo} base={base} onGuardado={onGuardado} onGuardadoVarias={onGuardadoVarias}
          onGuardando={setGuardando}
        />
      )}
    </Modal>
  );
}

function Cuerpo({
  onCerrar, supabase, tipos, personas, polizas, corrigiendo, base, onGuardado, onGuardadoVarias, onGuardando,
}: Omit<Parameters<typeof FormularioPoliza>[0], "abierto"> & { onGuardando: (guardando: boolean) => void }) {
  const [f, setF] = useState<Form>(() => formInicial(corrigiendo, base, tipos, personas));
  // «Varias personas» solo para una póliza NUEVA y sin una persona ya elegida: renovar, registrar otro
  // seguro a alguien o corregir son siempre de una persona.
  const puedeVarias = corrigiendo === null && !base?.personaId;
  const [modo, setModo] = useState<Modo>("una");
  const [elegidas, setElegidas] = useState<ReadonlySet<string>>(() => new Set());
  const [buscar, setBuscar] = useState("");
  // «Hasta» sigue a «Desde» mientras nadie lo toque.
  const [hastaTocado, setHastaTocado] = useState(corrigiendo !== null);
  const [intento, setIntento] = useState(false);
  const [mensaje, setMensaje] = useState<string | null>(null);
  const [guardando, setGuardando] = useState(false);

  const ofrecidos = conPoliza(tipos, base?.soloAdemas);
  const tipo = tipos.find((t) => t.clave === f.producto);
  const candidatas = f.producto ? personasDe(f.producto, tipos, personas) : personas;

  // En «varias»: quién se cruza con las fechas de hoy del formulario, y quién queda de verdad elegida
  // (las que se cruzan se ignoran aunque estén marcadas: la base rechazaría el lote entero por ellas).
  const cruces = new Map<string, Poliza>();
  if (modo === "varias" && f.producto) {
    for (const p of candidatas) {
      const z = polizaQueSeCruza(polizas, p.id, f.producto, f.desde, f.hasta);
      if (z) cruces.set(p.id, z);
    }
  }
  const efectivas = modo === "varias" ? candidatas.filter((p) => elegidas.has(p.id) && !cruces.has(p.id)) : [];

  const errores = erroresDe(f, corrigiendo !== null, modo, efectivas.length, hoyLima());
  const dias = f.desde && f.hasta && f.hasta > f.desde
    ? Math.round((Date.parse(f.hasta) - Date.parse(f.desde)) / 86_400_000)
    : null;

  // Al corregir, la persona no cambia —aunque ya no esté activa—: su única opción es la de la póliza.
  const opcionesDePersona: OpcionPersona[] = corrigiendo
    ? [{ id: corrigiendo.persona_id, nombre: corrigiendo.persona, sede: corrigiendo.sede, tipoPrincipal: null, enPlanilla: false, vinculo: "" }]
    : candidatas;

  function cambiarProducto(producto: string) {
    // Si la persona elegida no tiene este seguro como principal, se suelta: la base no le aceptaría la póliza.
    const sigue = !producto || personasDe(producto, tipos, personas).some((p) => p.id === f.personaId);
    setF((a) => ({ ...a, producto, personaId: sigue ? a.personaId : "" }));
    setElegidas(new Set());
  }
  function marcar(ids: Iterable<string>) { setElegidas(new Set(ids)); }
  function alternar(id: string, marcada: boolean) {
    setElegidas((a) => { const n = new Set(a); if (marcada) n.add(id); else n.delete(id); return n; });
  }
  function cambiarDesde(desde: string) {
    setF((a) => ({ ...a, desde, hasta: hastaTocado || !desde ? a.hasta : sumarMeses(desde, 3) }));
  }
  function fijarHasta(meses: number) {
    if (!f.desde) return;
    setHastaTocado(true);
    setF((a) => ({ ...a, hasta: sumarMeses(a.desde, meses) }));
  }

  const nombrarPoliza = () =>
    `${personas.find((p) => p.id === f.personaId)?.nombre ?? corrigiendo?.persona ?? "Póliza"} · ${tipo?.nombre ?? corrigiendo?.producto_nombre ?? "seguro"} · póliza ${f.numero.trim()}`;

  async function guardar() {
    setIntento(true); setMensaje(null);
    if (Object.keys(errores).length > 0) return;
    setGuardando(true); onGuardando(true);
    const comunes = {
      p_aseguradora: f.aseguradora.trim(), p_numero_poliza: f.numero.trim(),
      p_vigente_desde: f.desde, p_vigente_hasta: f.hasta, p_prima_total: numero(f.prima)!,
      p_prima_vence_el: f.primaVence || null, p_plan: f.plan.trim() || null,
      p_beneficio_enfermedad: numero(f.benEnfermedad), p_beneficio_accidente: numero(f.benAccidente),
      p_renueva_sola: f.renueva === "" ? null : f.renueva === "si", p_nota: f.nota.trim() || null,
    };
    if (corrigiendo) {
      const { error } = await supabase.rpc("fn_seguro_corregir", { p_id: corrigiendo.poliza_id, ...comunes, p_motivo: f.motivo.trim() });
      setGuardando(false); onGuardando(false);
      if (error) { setMensaje(mensajeDeError(error, "guardar")); return; }
      onGuardado(corrigiendo.poliza_id, false, nombrarPoliza());
      return;
    }
    if (modo === "varias") {
      const { data, error } = await supabase.rpc("fn_seguro_registrar_varias", {
        p_personas: efectivas.map((p) => p.id), p_producto: f.producto, ...comunes,
      });
      setGuardando(false); onGuardando(false);
      if (error || !Array.isArray(data) || data.length === 0) { setMensaje(mensajeDeError(error, "guardar")); return; }
      onGuardadoVarias(data, { seguro: tipo?.nombre ?? "seguro", numero: f.numero.trim() });
      return;
    }
    const { data, error } = await supabase.rpc("fn_seguro_registrar", { p_persona_id: f.personaId, p_producto: f.producto, ...comunes });
    setGuardando(false); onGuardando(false);
    if (error || typeof data !== "string") { setMensaje(mensajeDeError(error, "guardar")); return; }
    onGuardado(data, true, nombrarPoliza());
  }

  const mostrar = <K extends keyof Form>(k: K) => (intento ? errores[k] : undefined);

  return (
    <>
      {corrigiendo && (
        <p className="mb-4 rounded-lg bg-hueso px-3 py-2 text-sm text-taupe">
          Corregir cambia los datos de esta póliza, no la reemplaza: el historial guarda qué decía antes cada campo y por qué lo cambiaste.
        </p>
      )}
      {mensaje && <AvisoDeError mensaje={mensaje} />}
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        {puedeVarias && (
          <div className="flex flex-wrap items-center gap-2 sm:col-span-2" role="group" aria-label="A cuántas personas se les registra">
            <Filtro activo={modo === "una"} onClick={() => setModo("una")}>A una persona</Filtro>
            <Filtro activo={modo === "varias"} onClick={() => setModo("varias")}>A varias, la misma póliza</Filtro>
          </div>
        )}
        <div>
          <CampoSelect
            etiqueta="Seguro"
            value={f.producto}
            disabled={corrigiendo !== null}
            onChange={(e) => cambiarProducto(e.target.value)}
            error={mostrar("producto")}
          >
            <option value="">Elige el seguro</option>
            {(corrigiendo ? tipos.filter((t) => t.clave === corrigiendo.producto) : ofrecidos).map((t) => (
              <option key={t.clave} value={t.clave}>{t.nombre}{t.principal ? "" : " (va además del principal)"}</option>
            ))}
          </CampoSelect>
          {corrigiendo && <span className="mt-1 block text-xs text-taupe">El seguro no se cambia: si está mal, anula la póliza y registra otra.</span>}
        </div>
        {modo === "varias" ? (
          <p className="self-end text-xs text-taupe">
            Un seguro de vida o una EPS suele ser UNA póliza con un solo número que cubre a todos. Se registra a todas las
            personas que elijas de una vez; si a una no se le puede registrar, no se registra a nadie.
          </p>
        ) : (
        <div>
          <BuscadorPersona
            etiqueta="A quién asegura"
            opciones={opcionesDePersona.map((p) => ({ id: p.id, nombre: p.nombre, sede: p.sede }))}
            value={f.personaId}
            // Sin seguro elegido no se sabe a quién se puede ofrecer (el principal solo va a quien lo tiene).
            disabled={corrigiendo !== null || (f.producto === "" && f.personaId === "")}
            placeholder={f.producto || corrigiendo ? "Escribe un nombre…" : "Elige primero el seguro"}
            onChange={(id) => setF({ ...f, personaId: id })}
            error={mostrar("personaId")}
          />
          {corrigiendo && <span className="mt-1 block text-xs text-taupe">La persona no se cambia: si está mal, anula la póliza y registra otra.</span>}
          {!corrigiendo && tipo?.principal && candidatas.length === 0 && (
            <span className="mt-1 block text-xs text-ambar">
              Hoy nadie está en {tipo.nombre}. Para registrarle una póliza a alguien, primero cámbiale el seguro desde su tarjeta («Cambiar su seguro»).
            </span>
          )}
        </div>
        )}
        {modo === "varias" && (
          <ListaDeQuienes
            producto={f.producto} tipo={tipo} candidatas={candidatas} cruces={cruces} elegidas={elegidas}
            efectivas={efectivas.length} buscar={buscar} onBuscar={setBuscar} onMarcar={marcar} onAlternar={alternar}
            error={mostrar("personaId")}
          />
        )}
        <Campo etiqueta="Aseguradora" value={f.aseguradora} onChange={(e) => setF({ ...f, aseguradora: e.target.value })} error={mostrar("aseguradora")} />
        <Campo etiqueta="Número de póliza" value={f.numero} onChange={(e) => setF({ ...f, numero: e.target.value })} placeholder="ej. 24043267" error={mostrar("numero")} />
        <Campo etiqueta="Vigente desde" type="date" value={f.desde} onChange={(e) => cambiarDesde(e.target.value)} error={mostrar("desde")} />
        <div>
          <Campo
            etiqueta="Hasta (la póliza deja de cubrir ese día, a las 12 M)"
            type="date" value={f.hasta} min={f.desde || undefined}
            onChange={(e) => { setHastaTocado(true); setF({ ...f, hasta: e.target.value }); }}
            error={mostrar("hasta")}
          />
          <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-taupe">
            {dias !== null && <span>{dias} días de vigencia.</span>}
            <span>Poner:</span>
            {[[3, "3 meses"], [6, "6 meses"], [12, "1 año"]].map(([m, t]) => (
              <Boton key={m} variante="enlace" onClick={() => fijarHasta(m as number)}>{t}</Boton>
            ))}
          </div>
        </div>
        <div>
          <Campo
            etiqueta={modo === "varias" ? "Prima de CADA persona (con IGV), en soles" : "Prima total (con IGV), en soles"}
            inputMode="decimal" value={f.prima} onChange={(e) => setF({ ...f, prima: e.target.value })} placeholder="ej. 179.97" error={mostrar("prima")}
          />
          {modo === "varias" && <TotalDeLaPoliza n={efectivas.length} prima={numero(f.prima)} />}
        </div>
        <div>
          <Campo etiqueta="La prima vence el (opcional)" type="date" value={f.primaVence} onChange={(e) => setF({ ...f, primaVence: e.target.value })} error={mostrar("primaVence")} />
          <span className="mt-1 block text-xs text-taupe">Si la póliza tiene convenio de pago, con 30 días de mora desde esa fecha la cobertura se suspende sola.</span>
        </div>

        <div className="rounded-lg border border-sand bg-hueso px-3 py-3 sm:col-span-2">
          <p className="mb-2 text-sm text-tinta">Lo que el papel no dice</p>
          <p className="mb-3 text-xs text-taupe">
            El plan y el beneficio máximo no siempre figuran en las condiciones particulares: los confirma el corredor. Déjalos
            vacíos hasta entonces; la pantalla los marca «sin confirmar».
          </p>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <Campo etiqueta="Plan (opcional)" value={f.plan} onChange={(e) => setF({ ...f, plan: e.target.value })} placeholder="ej. Plan 1" />
            <CampoSelect etiqueta="¿Renueva sola?" value={f.renueva} onChange={(e) => setF({ ...f, renueva: e.target.value as Form["renueva"] })}>
              <option value="">Sin confirmar</option>
              <option value="si">Sí, renueva sola</option>
              <option value="no">No, hay que renovarla</option>
            </CampoSelect>
            <Campo etiqueta="Beneficio máximo por enfermedad (opcional)" inputMode="decimal" value={f.benEnfermedad} onChange={(e) => setF({ ...f, benEnfermedad: e.target.value })} error={mostrar("benEnfermedad")} />
            <Campo etiqueta="Beneficio máximo por accidente (opcional)" inputMode="decimal" value={f.benAccidente} onChange={(e) => setF({ ...f, benAccidente: e.target.value })} error={mostrar("benAccidente")} />
          </div>
        </div>

        <label className="flex flex-col gap-1 sm:col-span-2">
          <span className="text-sm text-taupe">Nota (opcional)</span>
          <AreaTexto value={f.nota} onChange={(e) => setF({ ...f, nota: e.target.value })} placeholder="ej. Emitida el 14/10/2026 por el corredor" />
        </label>
        {corrigiendo && (
          <label className="flex flex-col gap-1 sm:col-span-2">
            <span className="text-sm text-taupe">Por qué corriges</span>
            <AreaTexto
              value={f.motivo}
              onChange={(e) => setF({ ...f, motivo: e.target.value })}
              placeholder="ej. El corredor confirmó el plan por escrito"
              className={mostrar("motivo") ? "border-rojo" : undefined}
            />
            {mostrar("motivo") && <span className="text-xs text-rojo">{errores.motivo}</span>}
          </label>
        )}
      </div>
      {!corrigiendo && (
        <p className="mt-4 text-sm text-taupe">
          El PDF de la póliza y el convenio de pago se adjuntan en el paso siguiente, apenas la registres.
        </p>
      )}
      <div className="mt-5 flex justify-end gap-2">
        <Boton onClick={onCerrar} disabled={guardando}>Cancelar</Boton>
        <Boton variante="primario" onClick={() => void guardar()} cargando={guardando}>
          {corrigiendo ? "Guardar la corrección" : modo === "varias" ? `Registrar la póliza a ${plural(efectivas.length, "persona", "personas")}` : "Registrar la póliza"}
        </Boton>
      </div>
    </>
  );
}

/**
 * «19 × S/ 8.95 = S/ 170.05»: el total de la póliza, a la vista. La prima de cada fila es la de ESA persona;
 * sin esta línea es fácil escribir el total de la póliza en cada una y que cualquier suma cuente la póliza
 * diecinueve veces.
 */
function TotalDeLaPoliza({ n, prima }: { n: number; prima: number | null }) {
  const ayuda = "Si solo tienes el total de la póliza, divídelo entre las personas.";
  if (n === 0 || prima === null || prima < 0) return <span className="mt-1 block text-xs text-taupe">Lo que cuesta cada una. {ayuda}</span>;
  return (
    <span className="mt-1 block text-xs text-taupe">
      {n} × {formatSoles(prima)} = <span className="text-tinta">{formatSoles(Math.round(prima * n * 100) / 100)}</span> en total. {ayuda}
    </span>
  );
}

/**
 * La lista de personas de una póliza para varias. Solo ofrece a quien la base le aceptaría el seguro (si es el
 * principal de la persona, a quien lo tiene hoy) y deja a la vista —sin permitir marcarla— a quien ya tiene una
 * póliza de ese seguro que se cruza con las fechas: por esa sola persona la base rechazaría el lote entero.
 */
function ListaDeQuienes({
  producto, tipo, candidatas, cruces, elegidas, efectivas, buscar, onBuscar, onMarcar, onAlternar, error,
}: {
  producto: string;
  tipo: TipoSeguro | undefined;
  candidatas: OpcionPersona[];
  cruces: ReadonlyMap<string, Poliza>;
  elegidas: ReadonlySet<string>;
  efectivas: number;
  buscar: string;
  onBuscar: (texto: string) => void;
  onMarcar: (ids: string[]) => void;
  onAlternar: (id: string, marcada: boolean) => void;
  error: string | undefined;
}) {
  const q = sinTildes(buscar.trim());
  const visibles = q ? candidatas.filter((p) => sinTildes(`${p.nombre} ${p.sede} ${etiquetaVinculo(p.vinculo)}`).includes(q)) : candidatas;
  const libres = candidatas.filter((p) => !cruces.has(p.id));
  const deLaPlanilla = libres.filter((p) => p.enPlanilla);

  return (
    <div className="sm:col-span-2">
      <div className="mb-1 flex flex-wrap items-baseline justify-between gap-2">
        <span className="text-sm text-taupe">A quiénes asegura</span>
        {producto && candidatas.length > 0 && (
          <span className="text-xs text-taupe" aria-live="polite">{efectivas} de {candidatas.length} elegidas</span>
        )}
      </div>
      {!producto ? (
        <p className="rounded-lg bg-hueso px-3 py-2 text-sm text-taupe">Elige primero el seguro: según cuál sea, se ofrece a unas personas o a otras.</p>
      ) : candidatas.length === 0 ? (
        <p className="rounded-lg bg-hueso px-3 py-2 text-sm text-ambar">
          {tipo?.principal
            ? `Hoy nadie está en ${tipo.nombre}. Para registrarle una póliza a alguien, primero cámbiale el seguro desde su tarjeta («Cambiar su seguro»).`
            : "No hay personas activas a quienes asegurar."}
        </p>
      ) : (
        <div className={cx("rounded-lg border", error ? "border-rojo" : "border-sand")}>
          <div className="flex flex-wrap items-center gap-2 border-b border-sand p-2">
            <div className="min-w-40 flex-1">
              <Campo value={buscar} onChange={(e) => onBuscar(e.target.value)} placeholder="Buscar por nombre, sede o vínculo" aria-label="Buscar a quién asegura" className="w-full" />
            </div>
            <Boton tamano="sm" variante="sutil" onClick={() => onMarcar(deLaPlanilla.map((p) => p.id))} disabled={deLaPlanilla.length === 0}>
              Las de planilla ({deLaPlanilla.length})
            </Boton>
            <Boton tamano="sm" variante="sutil" onClick={() => onMarcar(libres.map((p) => p.id))} disabled={libres.length === 0}>Todas</Boton>
            <Boton tamano="sm" variante="sutil" onClick={() => onMarcar([])} disabled={efectivas === 0}>Ninguna</Boton>
          </div>
          <ul className="max-h-64 divide-y divide-sand/60 overflow-y-auto" aria-label="Personas a las que se les registra la póliza">
            {visibles.map((p) => {
              const cruce = cruces.get(p.id);
              return (
                <li key={p.id}>
                  <label className={cx("flex items-start gap-2 px-3 py-2 text-sm", cruce ? "cursor-not-allowed opacity-70" : "cursor-pointer hover:bg-sand/30")}>
                    <input
                      type="checkbox" className="mt-0.5 size-4 shrink-0 accent-tinta"
                      checked={elegidas.has(p.id) && !cruce} disabled={Boolean(cruce)}
                      onChange={(e) => onAlternar(p.id, e.target.checked)}
                    />
                    <span className="min-w-0">
                      <span className="text-tinta">{p.nombre}</span>
                      <span className="text-taupe"> · {p.sede} · {etiquetaVinculo(p.vinculo)}</span>
                      {cruce && (
                        <span className="block text-xs text-ambar">
                          Ya tiene una póliza de este seguro del {isoADiaMesAnio(cruce.vigente_desde)} al {isoADiaMesAnio(cruce.vigente_hasta)} que se cruza con estas fechas.
                        </span>
                      )}
                    </span>
                  </label>
                </li>
              );
            })}
            {visibles.length === 0 && <li className="px-3 py-3 text-sm text-taupe">Nadie coincide con «{buscar.trim()}».</li>}
          </ul>
        </div>
      )}
      {error && <span className="mt-1 block text-xs text-rojo">{error}</span>}
    </div>
  );
}

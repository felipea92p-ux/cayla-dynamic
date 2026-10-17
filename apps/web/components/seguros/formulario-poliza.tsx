"use client";

// ============================================================================
// Formulario de una póliza — registrar una nueva, una renovación, o corregir una
// ============================================================================
// QUÉ PROMETE
//   Un solo diálogo para las tres cosas: la persona (fija si se corrige), las
//   fechas de la vigencia, la prima, y lo que el papel no dice y el corredor aún
//   no confirmó (plan, beneficios, si renueva sola), que se puede dejar «sin
//   confirmar». Migración 0528: `fn_seguro_registrar` y `fn_seguro_corregir`.
//
// LAS FECHAS NACEN CON VALOR (CLAUDE.md, regla del 2026-08-26): «Desde» arranca
//   en hoy —o en el día en que termina la póliza que se renueva— y «Hasta» en tres
//   meses después, que es la póliza de hoy (92 días). Un campo de fecha que
//   bloquea el envío no puede arrancar vacío. «Hasta» sigue a «Desde» mientras
//   nadie lo toque, y tres botones lo mueven a 3 meses, 6 meses o un año.
//
// QUÉ NO HACE
//   No decide si la póliza se cruza con otra ni si la persona es practicante:
//   eso lo decide la base y su mensaje se muestra tal cual.
// ============================================================================

import { useState } from "react";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { hoyLima } from "@cayla-dynamic/shared";
import { AreaTexto } from "@/components/ui/area-texto";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { Modal } from "@/components/ui/modal";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { sumarMeses, type Poliza } from "@/lib/admin/seguros";

export interface OpcionPersona { id: string; nombre: string; sede: string }

/** Lo que una pantalla puede adelantar al abrir: renovar copia aseguradora, número y prima. */
export interface BaseDePoliza {
  personaId?: string;
  aseguradora?: string;
  numeroPoliza?: string;
  desde?: string;
  prima?: number | null;
}

interface Form {
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

function formInicial(corrigiendo: Poliza | null, base: BaseDePoliza | null, personas: OpcionPersona[]): Form {
  if (corrigiendo) {
    return {
      personaId: corrigiendo.persona_id, aseguradora: corrigiendo.aseguradora, numero: corrigiendo.numero_poliza,
      desde: corrigiendo.vigente_desde, hasta: corrigiendo.vigente_hasta, prima: String(corrigiendo.prima_total),
      primaVence: corrigiendo.prima_vence_el ?? "", plan: corrigiendo.plan ?? "",
      benEnfermedad: corrigiendo.beneficio_enfermedad !== null ? String(corrigiendo.beneficio_enfermedad) : "",
      benAccidente: corrigiendo.beneficio_accidente !== null ? String(corrigiendo.beneficio_accidente) : "",
      renueva: corrigiendo.renueva_sola === null ? "" : corrigiendo.renueva_sola ? "si" : "no",
      nota: corrigiendo.nota ?? "", motivo: "",
    };
  }
  const desde = base?.desde ?? hoyLima();
  return {
    personaId: base?.personaId ?? (personas.length === 1 ? personas[0].id : ""),
    aseguradora: base?.aseguradora ?? ASEGURADORA_POR_DEFECTO, numero: base?.numeroPoliza ?? "",
    desde, hasta: sumarMeses(desde, 3), prima: base?.prima != null ? String(base.prima) : "", primaVence: "",
    plan: "", benEnfermedad: "", benAccidente: "", renueva: "", nota: "", motivo: "",
  };
}

/** «179,97» o «179.97» → 179.97; vacío o texto → null. */
function numero(texto: string): number | null {
  const t = texto.trim().replace(",", ".");
  if (t === "") return null;
  const n = Number(t);
  return Number.isFinite(n) ? n : null;
}

function erroresDe(f: Form, corrigiendo: boolean): Partial<Record<keyof Form, string>> {
  const e: Partial<Record<keyof Form, string>> = {};
  if (!f.personaId) e.personaId = "Elige a quién asegura.";
  if (f.aseguradora.trim().length < 2) e.aseguradora = "Escribe la aseguradora.";
  if (f.numero.trim().length < 3) e.numero = "Escribe el número de la póliza.";
  if (!f.desde) e.desde = "Falta la fecha de inicio.";
  if (!f.hasta) e.hasta = "Falta la fecha en que termina.";
  else if (f.desde && f.hasta <= f.desde) e.hasta = "Tiene que terminar después de empezar.";
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
  abierto, onCerrar, supabase, personas, corrigiendo, base, onGuardado,
}: {
  abierto: boolean;
  onCerrar: () => void;
  supabase: ClienteCayla;
  /** A quién se puede asegurar: los practicantes activos. */
  personas: OpcionPersona[];
  /** La póliza que se corrige, o null si es una nueva. */
  corrigiendo: Poliza | null;
  base: BaseDePoliza | null;
  /** Recibe el id de la póliza, si es nueva y cómo nombrarla («Ana Prueba · póliza 24043267»), para abrir sus archivos. */
  onGuardado: (polizaId: string, nueva: boolean, titulo: string) => void;
}) {
  return (
    <Modal
      abierto={abierto}
      onCerrar={onCerrar}
      titulo={corrigiendo ? "Corregir una póliza" : base?.desde ? "Registrar una renovación" : "Registrar una póliza"}
      ancho="lg"
    >
      {/* Se monta de nuevo cada vez que se abre: así el formulario nace con los
          valores de ESA póliza o de ESA persona, sin un efecto que los copie. */}
      {abierto && <Cuerpo onCerrar={onCerrar} supabase={supabase} personas={personas} corrigiendo={corrigiendo} base={base} onGuardado={onGuardado} />}
    </Modal>
  );
}

function Cuerpo({
  onCerrar, supabase, personas, corrigiendo, base, onGuardado,
}: Omit<Parameters<typeof FormularioPoliza>[0], "abierto">) {
  const [f, setF] = useState<Form>(() => formInicial(corrigiendo, base, personas));
  // «Hasta» sigue a «Desde» mientras nadie lo toque.
  const [hastaTocado, setHastaTocado] = useState(corrigiendo !== null);
  const [intento, setIntento] = useState(false);
  const [mensaje, setMensaje] = useState<string | null>(null);
  const [guardando, setGuardando] = useState(false);

  const errores = erroresDe(f, corrigiendo !== null);
  const dias = f.desde && f.hasta && f.hasta > f.desde
    ? Math.round((Date.parse(f.hasta) - Date.parse(f.desde)) / 86_400_000)
    : null;

  function cambiarDesde(desde: string) {
    setF((a) => ({ ...a, desde, hasta: hastaTocado || !desde ? a.hasta : sumarMeses(desde, 3) }));
  }
  function fijarHasta(meses: number) {
    if (!f.desde) return;
    setHastaTocado(true);
    setF((a) => ({ ...a, hasta: sumarMeses(a.desde, meses) }));
  }

  const nombrarPoliza = () => `${personas.find((p) => p.id === f.personaId)?.nombre ?? "Póliza"} · póliza ${f.numero.trim()}`;

  async function guardar() {
    setIntento(true); setMensaje(null);
    if (Object.keys(errores).length > 0) return;
    setGuardando(true);
    const comunes = {
      p_aseguradora: f.aseguradora.trim(), p_numero_poliza: f.numero.trim(),
      p_vigente_desde: f.desde, p_vigente_hasta: f.hasta, p_prima_total: numero(f.prima)!,
      p_prima_vence_el: f.primaVence || null, p_plan: f.plan.trim() || null,
      p_beneficio_enfermedad: numero(f.benEnfermedad), p_beneficio_accidente: numero(f.benAccidente),
      p_renueva_sola: f.renueva === "" ? null : f.renueva === "si", p_nota: f.nota.trim() || null,
    };
    if (corrigiendo) {
      const { error } = await supabase.rpc("fn_seguro_corregir", { p_id: corrigiendo.poliza_id, ...comunes, p_motivo: f.motivo.trim() });
      setGuardando(false);
      if (error) { setMensaje(mensajeDeError(error, "guardar")); return; }
      onGuardado(corrigiendo.poliza_id, false, nombrarPoliza());
      return;
    }
    const { data, error } = await supabase.rpc("fn_seguro_registrar", { p_persona_id: f.personaId, ...comunes });
    setGuardando(false);
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
      {mensaje && (
        <p role="alert" className="mb-3 rounded border border-rojo/30 bg-rojo/10 px-3 py-2 text-sm text-rojo">{mensaje}</p>
      )}
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <div className="sm:col-span-2">
          <CampoSelect
            etiqueta="A quién asegura"
            value={f.personaId}
            disabled={corrigiendo !== null}
            onChange={(e) => setF({ ...f, personaId: e.target.value })}
            error={mostrar("personaId")}
          >
            <option value="">Elige un practicante</option>
            {personas.map((p) => <option key={p.id} value={p.id}>{p.nombre} · {p.sede}</option>)}
          </CampoSelect>
          {corrigiendo && (
            <span className="mt-1 block text-xs text-taupe">La persona no se cambia: si está mal, anula la póliza y registra otra.</span>
          )}
        </div>
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
          <Campo etiqueta="Prima total (con IGV), en soles" inputMode="decimal" value={f.prima} onChange={(e) => setF({ ...f, prima: e.target.value })} placeholder="ej. 179.97" error={mostrar("prima")} />
        </div>
        <div>
          <Campo etiqueta="La prima vence el (opcional)" type="date" value={f.primaVence} onChange={(e) => setF({ ...f, primaVence: e.target.value })} />
          <span className="mt-1 block text-xs text-taupe">Con 30 días de mora desde esa fecha la cobertura se suspende sola.</span>
        </div>

        <div className="rounded-lg border border-sand bg-hueso px-3 py-3 sm:col-span-2">
          <p className="mb-2 text-sm text-tinta">Lo que el papel no dice</p>
          <p className="mb-3 text-xs text-taupe">
            El plan y el beneficio máximo no figuran en las condiciones particulares: los confirma el corredor. Déjalos
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
      <div className="mt-5 flex justify-end gap-2">
        <Boton onClick={onCerrar} disabled={guardando}>Cancelar</Boton>
        <Boton variante="primario" onClick={() => void guardar()} cargando={guardando}>
          {corrigiendo ? "Guardar la corrección" : "Registrar la póliza"}
        </Boton>
      </div>
    </>
  );
}

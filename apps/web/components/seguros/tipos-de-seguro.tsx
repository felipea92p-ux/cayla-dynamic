"use client";

// ============================================================================
// Los tipos de seguro: qué seguros conoce el sistema, y cómo DO agrega uno
// ============================================================================
// QUÉ PROMETE
//   Que la lista de seguros no esté escrita en el código sino en una tabla que DO
//   gestiona desde esta pantalla: ve cuáles hay y cuánta gente tiene cada uno, agrega
//   uno nuevo, le cambia el nombre o los textos de sus avisos, y lo archiva cuando ya
//   no se usa (no se borra: sus pólizas y sus cambios siguen contando lo que pasó).
//   «No se sabe con exactitud qué seguros tienen los demás colaboradores: si no hay
//   uno, que DO agregue el seguro o el tipo» (Felipe, 2026-10-17).
//
// QUÉ NO HACE
//   No decide a quién le toca cada seguro. Uno nuevo no le toca a nadie por su
//   vínculo: se asigna persona por persona («Cambiar su seguro», si es el principal) o
//   se le registra su póliza (si va además). Tampoco valida lo que valida la base —que
//   el nombre no se repita, que un seguro con gente o con pólizas vigentes no se
//   archive—: su mensaje se muestra tal cual.
// ============================================================================

import { useState, type ReactNode } from "react";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { AreaTexto } from "@/components/ui/area-texto";
import { Boton } from "@/components/ui/boton";
import { Campo } from "@/components/ui/campo";
import { Insignia } from "@/components/ui/insignia";
import { Modal } from "@/components/ui/modal";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { etiquetaVinculo, plural, type TipoSeguro } from "@/lib/admin/seguros";

type Vista =
  | { cual: "lista" }
  | { cual: "nuevo" }
  | { cual: "editar"; t: TipoSeguro }
  | { cual: "archivar"; t: TipoSeguro };

export function TiposDeSeguro({
  abierto, onCerrar, supabase, tipos, onCambio,
}: {
  abierto: boolean;
  onCerrar: () => void;
  supabase: ClienteCayla;
  tipos: TipoSeguro[];
  /** Después de agregar, editar, archivar o activar un seguro: quien lo abrió recarga y avisa. */
  onCambio: (mensaje: string) => Promise<void>;
}) {
  const [ocupado, setOcupado] = useState(false);
  return (
    <Modal
      abierto={abierto}
      onCerrar={() => { if (!ocupado) onCerrar(); }}
      bloqueado={ocupado}
      titulo="Tipos de seguro"
      ancho="lg"
    >
      {/* Se monta de nuevo cada vez que se abre: siempre nace en la lista. */}
      {abierto && <Cuerpo onCerrar={onCerrar} supabase={supabase} tipos={tipos} onCambio={onCambio} onOcupado={setOcupado} />}
    </Modal>
  );
}

function Cuerpo({
  onCerrar, supabase, tipos, onCambio, onOcupado,
}: {
  onCerrar: () => void;
  supabase: ClienteCayla;
  tipos: TipoSeguro[];
  onCambio: (mensaje: string) => Promise<void>;
  onOcupado: (ocupado: boolean) => void;
}) {
  const [vista, setVista] = useState<Vista>({ cual: "lista" });
  const [mensaje, setMensaje] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  /** Corre una escritura: si falla, deja el mensaje; si sale, vuelve a la lista y avisa. */
  async function escribir(llamada: () => PromiseLike<{ error: { message: string; code?: string } | null }>, listo: string) {
    setMensaje(null); setOcupado(true); onOcupado(true);
    const { error } = await llamada();
    if (error) { setOcupado(false); onOcupado(false); setMensaje(mensajeDeError(error, "guardar")); return; }
    await onCambio(listo);
    setOcupado(false); onOcupado(false);
    setVista({ cual: "lista" });
  }

  if (vista.cual === "nuevo") {
    return (
      <FormularioTipo
        tipo={null} mensaje={mensaje} ocupado={ocupado}
        onVolver={() => { setMensaje(null); setVista({ cual: "lista" }); }}
        onGuardar={(d) => escribir(
          () => supabase.rpc("fn_seguro_tipo_crear", {
            p_nombre: d.nombre, p_descripcion: d.descripcion, p_principal: d.principal, p_con_poliza: d.conPoliza,
            p_texto_alta: d.textoAlta, p_texto_baja: d.textoBaja,
          }),
          `Seguro «${d.nombre}» agregado.`,
        )}
      />
    );
  }
  if (vista.cual === "editar") {
    const t = vista.t;
    return (
      <FormularioTipo
        tipo={t} mensaje={mensaje} ocupado={ocupado}
        onVolver={() => { setMensaje(null); setVista({ cual: "lista" }); }}
        onGuardar={(d) => escribir(
          () => supabase.rpc("fn_seguro_tipo_editar", {
            p_clave: t.clave, p_nombre: d.nombre, p_descripcion: d.descripcion, p_texto_alta: d.textoAlta, p_texto_baja: d.textoBaja,
          }),
          `Seguro «${d.nombre}» actualizado.`,
        )}
      />
    );
  }
  if (vista.cual === "archivar") {
    const t = vista.t;
    return (
      <Archivar
        tipo={t} mensaje={mensaje} ocupado={ocupado}
        onVolver={() => { setMensaje(null); setVista({ cual: "lista" }); }}
        onArchivar={(motivo) => escribir(
          () => supabase.rpc("fn_seguro_tipo_activar", { p_clave: t.clave, p_activo: false, p_motivo: motivo }),
          `Seguro «${t.nombre}» archivado. No se borró: sus pólizas y sus cambios siguen en el historial.`,
        )}
      />
    );
  }

  return (
    <>
      <p className="mb-4 text-sm text-taupe">
        Estos son los seguros que el sistema conoce. Si un colaborador tiene uno que no está aquí, agrégalo: no se sabe con
        exactitud cuáles tienen los demás, y lo decide Desarrollo Organizacional. Un seguro nuevo no le toca a nadie por su
        vínculo; se asigna persona por persona.
      </p>
      {mensaje && <p role="alert" className="mb-3 rounded border border-rojo/30 bg-rojo/10 px-3 py-2 text-sm text-rojo">{mensaje}</p>}
      <ul className="space-y-3">
        {tipos.map((t) => (
          <li key={t.clave} className={`rounded-xl border border-sand px-4 py-3 ${t.activo ? "bg-papel" : "bg-hueso"}`}>
            <div className="flex flex-wrap items-start justify-between gap-2">
              <p className="font-medium text-tinta">{t.nombre}</p>
              <div className="flex flex-wrap gap-1.5">
                <Insignia variante="informativo" tamano="sm">{t.principal ? "Seguro principal" : "Va además del principal"}</Insignia>
                <Insignia variante="neutral" tamano="sm">{t.con_poliza ? "Lleva póliza" : "Sin póliza (por planilla)"}</Insignia>
                {t.de_sistema && <Insignia tamano="sm">Del sistema</Insignia>}
                {!t.activo && <Insignia variante="advertencia" tamano="sm">Archivado</Insignia>}
              </div>
            </div>
            {t.descripcion && <p className="mt-1 text-sm text-taupe">{t.descripcion}</p>}
            <p className="mt-1 text-xs text-taupe">
              {t.principal ? `${plural(t.personas, "persona", "personas")} en este seguro` : `${plural(t.personas, "persona", "personas")} con una póliza vigente`}
              {t.con_poliza && ` · ${plural(t.polizas_vigentes, "póliza vigente", "pólizas vigentes")}`}
              {t.principal && (t.aplica_a_vinculos.length > 0
                ? ` · le toca por su vínculo a: ${t.aplica_a_vinculos.map(etiquetaVinculo).join(", ")}`
                : " · no le toca a nadie por su vínculo: se asigna con «Cambiar su seguro»")}
            </p>
            {t.archivado_motivo && <p className="mt-1 text-xs text-taupe">Archivado: {t.archivado_motivo}</p>}
            <div className="mt-2 flex flex-wrap gap-2">
              <Boton tamano="sm" onClick={() => { setMensaje(null); setVista({ cual: "editar", t }); }}>Editar</Boton>
              {!t.de_sistema && t.activo && (
                <Boton variante="sutil" tamano="sm" onClick={() => { setMensaje(null); setVista({ cual: "archivar", t }); }}>Archivar</Boton>
              )}
              {!t.de_sistema && !t.activo && (
                <Boton
                  variante="sutil" tamano="sm" disabled={ocupado}
                  onClick={() => void escribir(
                    () => supabase.rpc("fn_seguro_tipo_activar", { p_clave: t.clave, p_activo: true, p_motivo: null }),
                    `Seguro «${t.nombre}» activo otra vez.`,
                  )}
                >
                  Volver a activar
                </Boton>
              )}
            </div>
          </li>
        ))}
      </ul>
      <div className="mt-5 flex justify-between gap-2">
        <Boton onClick={onCerrar}>Cerrar</Boton>
        <Boton variante="primario" onClick={() => { setMensaje(null); setVista({ cual: "nuevo" }); }}>+ Agregar un seguro</Boton>
      </div>
    </>
  );
}

// ── Agregar o editar ────────────────────────────────────────────────────────

type Uso = "principal_con_poliza" | "principal_sin_poliza" | "ademas";

interface DatosTipo {
  nombre: string;
  descripcion: string | null;
  principal: boolean;
  conPoliza: boolean;
  textoAlta: string | null;
  textoBaja: string | null;
}

function Opcion({
  valor, actual, onElegir, titulo, children,
}: { valor: Uso; actual: Uso | ""; onElegir: (u: Uso) => void; titulo: string; children: ReactNode }) {
  return (
    <label className={`flex cursor-pointer items-start gap-2 rounded-lg border px-3 py-2 ${actual === valor ? "border-tinta bg-papel" : "border-sand bg-hueso"}`}>
      <input type="radio" name="uso-del-seguro" className="mt-1 size-4 accent-tinta" checked={actual === valor} onChange={() => onElegir(valor)} />
      <span className="text-sm">
        <span className="block text-tinta">{titulo}</span>
        <span className="block text-xs text-taupe">{children}</span>
      </span>
    </label>
  );
}

function FormularioTipo({
  tipo, mensaje, ocupado, onVolver, onGuardar,
}: {
  /** El seguro que se edita, o null si es uno nuevo. */
  tipo: TipoSeguro | null;
  mensaje: string | null;
  ocupado: boolean;
  onVolver: () => void;
  onGuardar: (d: DatosTipo) => void;
}) {
  const [nombre, setNombre] = useState(tipo?.nombre ?? "");
  const [descripcion, setDescripcion] = useState(tipo?.descripcion ?? "");
  const [uso, setUso] = useState<Uso | "">("");
  const [textoAlta, setTextoAlta] = useState(tipo?.texto_alta ?? "");
  const [textoBaja, setTextoBaja] = useState(tipo?.texto_baja ?? "");
  const [intento, setIntento] = useState(false);

  const errores = {
    nombre: nombre.trim().length < 2 ? "Escribe cómo se llama el seguro (al menos 2 letras)." : nombre.trim().length > 80 ? "Máximo 80 letras." : undefined,
    descripcion: descripcion.length > 500 ? "Máximo 500 letras." : undefined,
    uso: !tipo && uso === "" ? "Elige cómo se usa este seguro." : undefined,
  };
  const ver = <K extends keyof typeof errores>(k: K) => (intento ? errores[k] : undefined);

  function guardar() {
    setIntento(true);
    if (Object.values(errores).some(Boolean)) return;
    onGuardar({
      nombre: nombre.trim(),
      descripcion: descripcion.trim() || null,
      principal: tipo ? tipo.principal : uso !== "ademas",
      conPoliza: tipo ? tipo.con_poliza : uso !== "principal_sin_poliza",
      textoAlta: textoAlta.trim() || null,
      textoBaja: textoBaja.trim() || null,
    });
  }

  return (
    <>
      <p className="mb-3 text-sm text-taupe">
        {tipo
          ? "Cambia cómo se llama o lo que dicen sus avisos. Si es principal, si lleva póliza y a quién le toca no se cambian: cambiaría lo que significa cada fila que ya existe."
          : "Agrega un seguro que el sistema no conocía."}
      </p>
      {mensaje && <p role="alert" className="mb-3 rounded border border-rojo/30 bg-rojo/10 px-3 py-2 text-sm text-rojo">{mensaje}</p>}
      <div className="space-y-3">
        <div>
          <Campo
            etiqueta="Nombre del seguro" value={nombre} onChange={(e) => setNombre(e.target.value)}
            disabled={tipo?.de_sistema} placeholder="ej. Seguro de vida" error={ver("nombre")}
          />
          {tipo?.de_sistema && <span className="mt-1 block text-xs text-taupe">Un seguro del sistema conserva su nombre.</span>}
        </div>
        <label className="flex flex-col gap-1">
          <span className="text-sm text-taupe">Descripción (opcional)</span>
          <AreaTexto value={descripcion} onChange={(e) => setDescripcion(e.target.value)} placeholder="ej. Lo contrata cada persona por su cuenta; presenta la constancia" className={ver("descripcion") ? "border-rojo" : undefined} />
          {ver("descripcion") && <span className="text-xs text-rojo">{errores.descripcion}</span>}
        </label>

        {!tipo && (
          <fieldset className="space-y-2">
            <legend className="mb-1 text-sm text-taupe">Cómo se usa</legend>
            <Opcion valor="principal_con_poliza" actual={uso} onElegir={setUso} titulo="Es el seguro principal de la persona y lleva póliza">
              Uno a la vez, como FOLA. Se asigna persona por persona; sin una póliza que cubra hoy, aparece como «sin seguro».
            </Opcion>
            <Opcion valor="principal_sin_poliza" actual={uso} onElegir={setUso} titulo="Es el seguro principal y se paga con la planilla (sin póliza)">
              Como EsSalud: Dynamic solo lo muestra y deja pendientes la baja y el alta; no hay póliza que registrar.
            </Opcion>
            <Opcion valor="ademas" actual={uso} onElegir={setUso} titulo="Va además del principal">
              Una póliza adicional, por ejemplo un seguro de vida. Se le registra a quien la tenga, sin cambiarle su seguro principal.
            </Opcion>
            {ver("uso") && <span className="block text-xs text-rojo">{errores.uso}</span>}
          </fieldset>
        )}

        <div className="rounded-lg border border-sand bg-hueso px-3 py-3">
          <p className="mb-1 text-sm text-tinta">Qué dicen los avisos cuando alguien cambia de seguro (opcional)</p>
          <p className="mb-3 text-xs text-taupe">Si los dejas vacíos, el sistema escribe uno con el nombre del seguro.</p>
          <div className="grid grid-cols-1 gap-3">
            <Campo etiqueta="Al darle de alta" value={textoAlta} onChange={(e) => setTextoAlta(e.target.value)} placeholder="ej. Registrar su póliza y avisarle al corredor" />
            <Campo etiqueta="Al darle de baja" value={textoBaja} onChange={(e) => setTextoBaja(e.target.value)} placeholder="ej. Pedirle a la aseguradora la baja de su póliza" />
          </div>
        </div>
      </div>
      <div className="mt-5 flex justify-end gap-2">
        <Boton onClick={onVolver} disabled={ocupado}>Volver a la lista</Boton>
        <Boton variante="primario" onClick={guardar} cargando={ocupado}>{tipo ? "Guardar los cambios" : "Agregar el seguro"}</Boton>
      </div>
    </>
  );
}

// ── Archivar ────────────────────────────────────────────────────────────────

function Archivar({
  tipo, mensaje, ocupado, onVolver, onArchivar,
}: {
  tipo: TipoSeguro;
  mensaje: string | null;
  ocupado: boolean;
  onVolver: () => void;
  onArchivar: (motivo: string) => void;
}) {
  const [motivo, setMotivo] = useState("");
  const [intento, setIntento] = useState(false);
  const error = intento && motivo.trim().length < 5 ? "Escribe el motivo (al menos 5 letras)." : undefined;
  return (
    <>
      <p className="mb-3 text-sm text-taupe">
        «{tipo.nombre}» deja de ofrecerse al registrar pólizas o cambiar el seguro de alguien. No se borra: sus pólizas, sus
        asignaciones y sus cambios siguen en el historial. Si todavía hay pólizas vigentes o gente asignada a este seguro,
        la base no deja archivarlo.
      </p>
      {mensaje && <p role="alert" className="mb-3 rounded border border-rojo/30 bg-rojo/10 px-3 py-2 text-sm text-rojo">{mensaje}</p>}
      <label className="flex flex-col gap-1">
        <span className="text-sm text-taupe">Por qué se archiva</span>
        <AreaTexto value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="ej. La empresa dejó de ofrecerlo" className={error ? "border-rojo" : undefined} />
        {error && <span className="text-xs text-rojo">{error}</span>}
      </label>
      <div className="mt-5 flex justify-end gap-2">
        <Boton onClick={onVolver} disabled={ocupado}>Volver a la lista</Boton>
        <Boton variante="peligro" cargando={ocupado} onClick={() => { setIntento(true); if (motivo.trim().length >= 5) onArchivar(motivo.trim()); }}>
          Sí, archivar
        </Boton>
      </div>
    </>
  );
}

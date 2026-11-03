"use client";

// «Disponibilidad del equipo» (0584).
//
// QUÉ PROMETE · que la líder de equipo vea qué días u horas puede trabajar cada
//               persona de su sede, y apruebe o converse lo que le mandaron; y
//               que DO, además, fije la jornada de cada una y registre una
//               disponibilidad por ella. Lo aprobado es lo que lee la
//               sugerencia de turnos (`fn_disponibilidad_vigente`).
// QUÉ ASUME   · la RLS de la 0584 decide qué filas ve cada quien (la líder, su
//               sede; DO, todas), y `fn_puede_resolver_disponibilidad` decide a
//               quién aprueba cada una. La pantalla solo esconde los botones que
//               de todos modos la base rechazaría: si se desincronizan, gana la
//               base y se ve su mensaje.

import { useEffect, useMemo, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { esRolIntegrante, puedeFijarJornada, puedeVerDisponibilidadEquipo, puedeVerTodasLasSedes } from "@cayla-dynamic/shared";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { Cargando } from "@/components/cargando";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { EstadoVacio } from "@/components/ui/estado-vacio";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Boton } from "@/components/ui/boton";
import { Campo } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { Insignia } from "@/components/ui/insignia";
import { Modal } from "@/components/ui/modal";
import { Filtro } from "@/components/ui/filtro";
import { useToast } from "@/components/toast";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { sobretituloDeHoy } from "@/lib/admin/sobretitulo";
import { EditorDisponibilidad, type EnvioDisponibilidad } from "@/components/disponibilidad/editor-disponibilidad";
import { PedidosDelEquipo } from "@/components/pedidos-turno/pedidos-del-equipo";
import {
  MOTIVOS, avisoDeHoras, desdeBloques, diaMes, horasDisponibles, resumenEnPalabras,
  type Bloque, type Motivo, type Ventana,
} from "@/lib/disponibilidad";

interface Persona {
  id: string;
  nombres: string;
  apellidos: string;
  rol: string | null;
  jornada_semanal_horas: number | null;
}

interface Disp {
  id: string;
  persona_id: string;
  tipo: "total" | "parcial";
  motivo: Motivo | null;
  nota: string | null;
  vigente_desde: string;
  vigente_hasta: string | null;
  estado: "enviada" | "aprobada" | "conversar";
  horario_fijo: boolean;
  creada_at: string;
  respuesta: string | null;
  disponibilidad_bloques: Bloque[];
}

const etiquetaMotivo = (m: Motivo | null) => MOTIVOS.find((x) => x.valor === m)?.label ?? null;

function enPalabras(d: Disp): string[] {
  if (d.tipo === "total") return ["Puede cualquier día y hora."];
  const { semana, excepciones } = desdeBloques(d.disponibilidad_bloques);
  return resumenEnPalabras(semana, excepciones, "ella");
}

export default function DisponibilidadDelEquipo() {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const yo = usePersonaActual();
  const toast = useToast();
  const [sedes, setSedes] = useState<{ id: string; nombre: string }[]>([]);
  const [sedeId, setSedeId] = useState<string | null>(null);
  const [personas, setPersonas] = useState<Persona[] | null>(null);
  const [disps, setDisps] = useState<Disp[]>([]);
  const [ventana, setVentana] = useState<Ventana[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [recarga, setRecarga] = useState(0);
  const [registrando, setRegistrando] = useState<Persona | null>(null);
  const [jornadaDe, setJornadaDe] = useState<Persona | null>(null);

  const esDO = puedeFijarJornada(yo?.rol);
  const sedeElegida = sedeId ?? yo?.sedeBaseId ?? null;

  useEffect(() => {
    if (!yo || !puedeVerTodasLasSedes(yo.rol)) return;
    let vivo = true;
    void supabase.from("sedes").select("id, nombre").eq("activa", true).order("nombre")
      .then(({ data }) => { if (vivo) setSedes((data as { id: string; nombre: string }[]) ?? []); });
    return () => { vivo = false; };
  }, [supabase, yo]);

  useEffect(() => {
    if (!sedeElegida) return;
    let vivo = true;
    void (async () => {
      const { data: ps, error: e1 } = await supabase.from("personas")
        .select("id, nombres, apellidos, rol, jornada_semanal_horas")
        .eq("sede_base_id", sedeElegida).eq("estado", "activo").eq("cuenta_de_servicio", false)
        .order("nombres");
      const ids = ((ps as Persona[] | null) ?? []).map((p) => p.id);
      const [{ data: ds, error: e2 }, { data: ven }] = await Promise.all([
        ids.length
          ? supabase.from("disponibilidades")
              .select("id, persona_id, tipo, motivo, nota, vigente_desde, vigente_hasta, estado, horario_fijo, creada_at, respuesta, disponibilidad_bloques(dia_semana, fecha, desde, hasta, estado)")
              .in("persona_id", ids).in("estado", ["enviada", "aprobada", "conversar"])
              .order("creada_at", { ascending: false }).order("id", { ascending: false })
          : Promise.resolve({ data: [], error: null }),
        supabase.rpc("fn_sede_ventana_semanal", { p_sede_id: sedeElegida }),
      ]);
      if (!vivo) return;
      if (e1 || e2) {
        setError(mensajeDeError(e1 ?? e2, "leer la disponibilidad del equipo"));
        return;
      }
      setError(null);
      setPersonas((ps as Persona[]) ?? []);
      setDisps((ds as unknown as Disp[]) ?? []);
      setVentana((ven as Ventana[] | null) ?? []);
    })();
    return () => { vivo = false; };
  }, [supabase, sedeElegida, recarga]);

  if (!yo) return <Cargando />;
  if (!puedeVerDisponibilidadEquipo(yo.rol)) {
    return <BannerAviso variante="informativo">Esta pantalla es de la líder de equipo y de Desarrollo Organizacional.</BannerAviso>;
  }

  const recargar = () => setRecarga((n) => n + 1);
  const pendientes = (personas ?? []).filter((p) => disps.some((d) => d.persona_id === p.id && d.estado === "enviada"));

  return (
    <div className="flex flex-1 flex-col">
    <main className="flex flex-1 flex-col gap-5 p-6">
      <CabeceraPagina
        sobretitulo={sobretituloDeHoy("Asistencia")}
        titulo="Disponibilidad del equipo"
        descripcion="Qué días u horas puede trabajar cada persona. Lo que apruebas es lo que usa la sugerencia de turnos."
      />

      {sedes.length > 1 && (
        <div role="group" aria-label="Sede" className="flex flex-wrap gap-2">
          {sedes.map((s) => (
            <Filtro key={s.id} tamano="sm" activo={s.id === sedeElegida} onClick={() => setSedeId(s.id)}>{s.nombre}</Filtro>
          ))}
        </div>
      )}

      {error && <BannerAviso variante="alerta" role="alert">{error}</BannerAviso>}
      {!personas && !error && <Cargando />}

      {personas && pendientes.length > 0 && (
        <p className="text-sm">
          <strong>{pendientes.length}</strong> {pendientes.length === 1 ? "espera" : "esperan"} tu respuesta.
        </p>
      )}

      {personas && personas.length > 0 && (
        <PedidosDelEquipo supabase={supabase} personas={personas} yoId={yo.id} esDO={esDO} avisar={toast.avisar} />
      )}

      {personas && personas.length === 0 && <EstadoVacio>No hay personas activas en esta sede.</EstadoVacio>}

      {personas && personas.length > 0 && (
        <ul className="flex flex-col gap-3">
          {[...personas]
            .sort((a, b) => Number(pendientes.includes(b)) - Number(pendientes.includes(a)))
            .map((p) => (
              <FilaPersona
                key={p.id}
                persona={p}
                disps={disps.filter((d) => d.persona_id === p.id)}
                ventana={ventana}
                puedeResolver={p.id !== yo.id && (esDO || esRolIntegrante(p.rol))}
                esDO={esDO && p.id !== yo.id}
                supabase={supabase}
                onCambio={recargar}
                onRegistrar={() => setRegistrando(p)}
                onJornada={() => setJornadaDe(p)}
                avisar={toast.avisar}
              />
            ))}
        </ul>
      )}

      {registrando && (
        <ModalRegistrar persona={registrando} ventana={ventana} supabase={supabase}
          onCerrar={() => setRegistrando(null)} onListo={() => { setRegistrando(null); recargar(); }} avisar={toast.avisar} />
      )}
      {jornadaDe && (
        <ModalJornada persona={jornadaDe} supabase={supabase}
          onCerrar={() => setJornadaDe(null)} onListo={() => { setJornadaDe(null); recargar(); }} avisar={toast.avisar} />
      )}
    </main>
    </div>
  );
}

type Avisar = (tipo: "ok" | "error", texto: string) => void;
type Cliente = ReturnType<typeof createAdminSupabaseClient>;

function FilaPersona({
  persona, disps, ventana, puedeResolver, esDO, supabase, onCambio, onRegistrar, onJornada, avisar,
}: {
  persona: Persona; disps: Disp[]; ventana: Ventana[]; puedeResolver: boolean; esDO: boolean;
  supabase: Cliente; onCambio: () => void; onRegistrar: () => void; onJornada: () => void; avisar: Avisar;
}) {
  const [respuesta, setRespuesta] = useState("");
  const [fijo, setFijo] = useState(false);
  const [enviando, setEnviando] = useState(false);
  const vigente = disps.find((d) => d.estado === "aprobada") ?? null;
  const pendiente = disps.find((d) => d.estado === "enviada") ?? null;
  const conversar = !pendiente ? disps.find((d) => d.estado === "conversar") ?? null : null;
  const jornada = persona.jornada_semanal_horas;

  const resolver = async (decision: "aprobar" | "conversar") => {
    if (!pendiente) return;
    setEnviando(true);
    const { error } = await supabase.rpc("fn_disponibilidad_resolver", {
      p_id: pendiente.id, p_decision: decision, p_respuesta: respuesta.trim() || null, p_horario_fijo: fijo,
    });
    setEnviando(false);
    if (error) return avisar("error", mensajeDeError(error));
    avisar("ok", decision === "aprobar" ? `Aprobada. Ya la usa la sugerencia de turnos.` : "Listo: le llega tu mensaje.");
    onCambio();
  };

  const libres = pendiente && pendiente.tipo === "parcial"
    ? horasDisponibles(desdeBloques(pendiente.disponibilidad_bloques).semana, ventana) : null;
  const aviso = avisoDeHoras(libres, jornada, "ella");

  return (
    <TarjetaInfo como="li" titulo={`${persona.nombres} ${persona.apellidos}`}
      accion={pendiente ? <Insignia variante="informativo">Por aprobar</Insignia>
        : vigente?.horario_fijo ? <Insignia>Horario fijo</Insignia> : undefined}>
      <div className="flex flex-col gap-3 text-sm">
        <p className="text-taupe">
          Jornada: {jornada !== null ? <strong className="text-tinta">{jornada} h por semana</strong> : "sin registrar"}
          {esDO && <> · <Boton variante="enlace" onClick={onJornada}>{jornada !== null ? "Cambiar" : "Fijarla"}</Boton></>}
        </p>

        <div>
          <span className="text-xs font-medium uppercase tracking-wide text-taupe">Lo que rige</span>
          {vigente ? (
            <>
              {enPalabras(vigente).map((l) => <p key={l}>{l}</p>)}
              <p className="text-taupe">
                Desde el {diaMes(vigente.vigente_desde)}{vigente.vigente_hasta ? ` hasta el ${diaMes(vigente.vigente_hasta)}` : ""}
                {vigente.motivo ? ` · ${etiquetaMotivo(vigente.motivo)}` : ""}
              </p>
            </>
          ) : <p>Nada registrado: puede cualquier día y hora.</p>}
        </div>

        {conversar && (
          <p className="text-taupe">Le pediste conversarlo: «{conversar.respuesta}».</p>
        )}

        {pendiente && (
          <div className="flex flex-col gap-2 rounded-control bg-hueso p-3">
            <span className="text-xs font-medium uppercase tracking-wide text-taupe">
              Mandó el {diaMes(pendiente.creada_at.slice(0, 10))}{pendiente.motivo ? ` · ${etiquetaMotivo(pendiente.motivo)}` : ""}
            </span>
            {enPalabras(pendiente).map((l) => <p key={l}>{l}</p>)}
            <p className="text-taupe">
              Desde el {diaMes(pendiente.vigente_desde)}{pendiente.vigente_hasta ? ` hasta el ${diaMes(pendiente.vigente_hasta)}` : ", sin fecha de fin"}.
            </p>
            {pendiente.nota && <p className="italic">«{pendiente.nota}»</p>}
            {aviso && <BannerAviso variante="advertencia" enLinea>{aviso}</BannerAviso>}
            {puedeResolver ? (
              <>
                <label className="flex items-start gap-2">
                  <input type="checkbox" checked={fijo} onChange={(e) => setFijo(e.target.checked)} className="mt-1 accent-tinta" />
                  <span>Horario fijo: conserva su horario de siempre y la sugerencia de turnos no la mueve.</span>
                </label>
                <AreaTexto etiqueta="Mensaje para ella (obligatorio si quieres conversarlo)" value={respuesta} rows={2}
                  maxLength={500} onChange={(e) => setRespuesta(e.target.value)} />
                <div className="flex flex-wrap gap-2">
                  <Boton variante="primario" cargando={enviando} onClick={() => void resolver("aprobar")}>Aprobar</Boton>
                  <Boton disabled={enviando || respuesta.trim().length < 5} onClick={() => void resolver("conversar")}>Conversar antes</Boton>
                </div>
              </>
            ) : (
              <p className="text-taupe">La resuelve Desarrollo Organizacional.</p>
            )}
          </div>
        )}

        {esDO && (
          <Boton variante="enlace" className="self-start" onClick={onRegistrar}>Registrar su disponibilidad por ella</Boton>
        )}
      </div>
    </TarjetaInfo>
  );
}

function ModalRegistrar({
  persona, ventana, supabase, onCerrar, onListo, avisar,
}: { persona: Persona; ventana: Ventana[]; supabase: Cliente; onCerrar: () => void; onListo: () => void; avisar: Avisar }) {
  const [enviando, setEnviando] = useState(false);
  const [fijo, setFijo] = useState(false);
  const registrar = async (e: EnvioDisponibilidad) => {
    setEnviando(true);
    const { error } = await supabase.rpc("fn_disponibilidad_registrar", {
      p_persona_id: persona.id, p_tipo: e.tipo, p_motivo: e.motivo, p_desde: e.desde, p_hasta: e.hasta,
      p_bloques: e.bloques as unknown as never, p_horario_fijo: fijo, p_nota: e.nota,
    });
    setEnviando(false);
    if (error) return avisar("error", mensajeDeError(error));
    avisar("ok", "Registrada y aprobada.");
    onListo();
  };
  return (
    <Modal abierto onCerrar={onCerrar} titulo={`Disponibilidad de ${persona.nombres}`} ancho="lg" bloqueado={enviando}>
      <div className="flex flex-col gap-3">
        <p className="text-sm text-taupe">Entra aprobada. Si ella tenía una pendiente, esta la reemplaza.</p>
        <label className="flex items-start gap-2 text-sm">
          <input type="checkbox" checked={fijo} onChange={(e) => setFijo(e.target.checked)} className="mt-1 accent-tinta" />
          <span>Horario fijo: conserva su horario de siempre y la sugerencia de turnos no la mueve.</span>
        </label>
        <EditorDisponibilidad ventana={ventana} jornada={persona.jornada_semanal_horas} quien="ella"
          textoBoton="Registrar y aprobar" enviando={enviando} onEnviar={(e) => void registrar(e)} />
      </div>
    </Modal>
  );
}

function ModalJornada({
  persona, supabase, onCerrar, onListo, avisar,
}: { persona: Persona; supabase: Cliente; onCerrar: () => void; onListo: () => void; avisar: Avisar }) {
  const [horas, setHoras] = useState(String(persona.jornada_semanal_horas ?? 45));
  const [motivo, setMotivo] = useState("");
  const [enviando, setEnviando] = useState(false);
  const n = Number(horas.replace(",", "."));
  const valida = Number.isFinite(n) && n > 0 && n <= 48;
  const guardar = async () => {
    setEnviando(true);
    const { error } = await supabase.rpc("fn_set_jornada", { p_persona_id: persona.id, p_horas: n, p_motivo: motivo.trim() });
    setEnviando(false);
    if (error) return avisar("error", mensajeDeError(error));
    avisar("ok", "Jornada guardada.");
    onListo();
  };
  return (
    <Modal abierto onCerrar={onCerrar} titulo={`Jornada de ${persona.nombres}`} ancho="sm" bloqueado={enviando}>
      <div className="flex flex-col gap-3">
        <p className="text-sm text-taupe">Las horas por semana de su contrato. No cambia su pago: es la referencia de su semana.</p>
        <Campo etiqueta="Horas por semana" inputMode="decimal" value={horas} onChange={(e) => setHoras(e.target.value)}
          error={valida ? undefined : "De más de 0 a 48."} />
        <AreaTexto etiqueta="Motivo" value={motivo} rows={2} onChange={(e) => setMotivo(e.target.value)} />
        <Boton variante="primario" className="self-start" cargando={enviando}
          disabled={!valida || motivo.trim().length < 5} onClick={() => void guardar()}>Guardar</Boton>
      </div>
    </Modal>
  );
}

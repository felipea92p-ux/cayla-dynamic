"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { TIPO_CONSTANCIA_LABELS, type MotivoRechazo } from "@cayla-dynamic/shared";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { fechaCorta } from "@/lib/educacion";
import { fechaHora } from "@/lib/admin/educacion-formato";
import type { AprobadaDelCiclo } from "@/lib/admin/educacion-tipos";
import {
  CICLOS_A_OFRECER, cicloInicial, etiquetaCiclo, rechazoIncompleto, type PeriodoCiclo,
} from "@/lib/admin/educacion-ciclo";
import { Boton } from "@/components/ui/boton";
import { CampoSelect } from "@/components/ui/campo";
import { Insignia } from "@/components/ui/insignia";
import { Modal } from "@/components/ui/modal";
import { Cargando } from "@/components/cargando";
import { LienzoArchivos } from "./lienzo-archivos";
import { CamposDeRechazo } from "./campos-de-rechazo";

/**
 * APROBADAS DEL CICLO — a quién aprobamos en este ciclo de pago, y cómo se corrige un error.
 *
 * PROMETE: listar lo que DO aprobó en un periodo de planilla (29 → 28), con la constancia
 *   a la vista y el botón de rechazarla. Rechazar aquí REVIERTE la aprobación
 *   (`fn_educacion_revertir_aprobacion`, 0525): la constancia queda «Rechazada» con su
 *   motivo, la integrante la ve en su Bandeja y el historial del estudio cuenta quién la
 *   aprobó, quién la revirtió, cuándo y por qué.
 * ASUME: el ciclo es un periodo de `periodos_planilla`, no un mes calendario; «aprobada en
 *   el ciclo» es por el día en que DO aprobó, no por el del pago.
 * NO HACE: no decide si se puede. Antes de confirmar la base dice qué pasaría con el pago
 *   (`apaga_pago`, `bloqueada`, `aviso`) y esta pantalla solo lo muestra: si el pago ya
 *   salió con esa constancia, el botón queda apagado y el aviso dice qué hacer.
 *
 * Decidido por Felipe (2026-10-17): revertir apaga el pago si era la única aprobada, y se
 * bloquea si el periodo ya se pagó con ella.
 */
export function AprobadasDelCiclo({
  miPersonaId, onCambio, onError, plegable = true,
}: {
  miPersonaId: string | null;
  /** Plegada (se abre a pedido) o a la vista, como cuando tiene su propia pestaña. */
  plegable?: boolean;
  /** Avisa cuando la base ya revirtió: quien la montó recarga el resto de la pantalla. */
  onCambio: (texto: string) => void | Promise<void>;
  onError: (texto: string) => void;
}) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const [abierta, setAbierta] = useState(false);
  const [periodos, setPeriodos] = useState<PeriodoCiclo[] | null>(null);
  const [cicloId, setCicloId] = useState<string | null>(null);
  const [filas, setFilas] = useState<AprobadaDelCiclo[] | null>(null);
  const [cargando, setCargando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [verId, setVerId] = useState<string | null>(null);
  const [revirtiendo, setRevirtiendo] = useState<AprobadaDelCiclo | null>(null);
  const [categoria, setCategoria] = useState<MotivoRechazo | "">("");
  const [comentario, setComentario] = useState("");
  const [trabajando, setTrabajando] = useState(false);

  const cargarFilas = useCallback(async (id: string) => {
    setCargando(true);
    setError(null);
    const { data, error: e } = await supabase.rpc("fn_educacion_aprobadas_del_periodo", { p_periodo_id: id });
    setCargando(false);
    if (e) { setError(mensajeDeError(e, "leer las constancias aprobadas")); setFilas(null); return; }
    setFilas((data ?? []) as unknown as AprobadaDelCiclo[]);
  }, [supabase]);

  const iniciar = useCallback(async () => {
    setCargando(true);
    setError(null);
    const { data, error: e } = await supabase
      .from("periodos_planilla").select("id, fecha_ini, fecha_fin, estado")
      .order("fecha_ini", { ascending: false }).limit(CICLOS_A_OFRECER);
    if (e) { setCargando(false); setError(mensajeDeError(e, "leer los periodos de planilla")); return; }
    const lista = (data ?? []) as PeriodoCiclo[];
    setPeriodos(lista);
    const id = cicloInicial(lista);
    setCicloId(id);
    if (id) await cargarFilas(id); else setCargando(false);
  }, [supabase, cargarFilas]);

  function cerrarRechazo() {
    if (trabajando) return;
    setRevirtiendo(null); setCategoria(""); setComentario("");
  }

  async function revertir() {
    if (!revirtiendo) return;
    const falta = rechazoIncompleto(categoria, comentario);
    if (falta) { onError(falta); return; }
    setTrabajando(true);
    const { error: e } = await supabase.rpc("fn_educacion_revertir_aprobacion", {
      p_id: revirtiendo.entrega_id, p_categoria: categoria, p_comentario: comentario.trim(),
    });
    setTrabajando(false);
    if (e) { onError(mensajeDeError(e, "rechazar la constancia aprobada")); return; }
    const quien = revirtiendo.persona;
    setRevirtiendo(null); setCategoria(""); setComentario(""); setVerId(null);
    await onCambio(`La aprobación de ${quien} se revirtió: su constancia quedó rechazada y le llega el motivo en su Bandeja.`);
    if (cicloId) await cargarFilas(cicloId);
  }

  const ciclo = periodos?.find((p) => p.id === cicloId) ?? null;

  // A la vista (en su pestaña) se carga al montarse; plegada, al abrirla.
  // eslint-disable-next-line react-hooks/set-state-in-effect -- cargar al montar, mismo patrón que el resto del panel.
  useEffect(() => { if (!plegable && periodos === null) void iniciar(); }, [plegable, periodos, iniciar]);

  const cuerpo = (
      <div className={plegable ? "mt-3" : ""}>
        {periodos !== null && periodos.length > 0 && (
          <div className="mb-3 max-w-sm">
            <CampoSelect etiqueta="Ciclo de pago" value={cicloId ?? ""}
              onChange={(e) => { setCicloId(e.target.value); setVerId(null); void cargarFilas(e.target.value); }}>
              {periodos.map((p) => <option key={p.id} value={p.id}>{etiquetaCiclo(p)}</option>)}
            </CampoSelect>
          </div>
        )}

        {error && (
          <div className="mb-3 rounded-control bg-rojo/10 px-3 py-2 text-sm text-rojo-profundo">
            {error} <Boton variante="enlace" onClick={() => void (cicloId ? cargarFilas(cicloId) : iniciar())}>Reintentar</Boton>
          </div>
        )}

        {cargando ? <Cargando /> : periodos !== null && periodos.length === 0 ? (
          <p className="text-sm text-taupe">Todavía no hay periodos de planilla.</p>
        ) : filas !== null && filas.length === 0 ? (
          <p className="text-sm text-taupe">
            En este ciclo no se aprobó ninguna constancia.
          </p>
        ) : filas !== null && (
          <>
            {ciclo && (
              <p className="mb-2 text-xs text-taupe">
                Lo aprobado entre el {fechaCorta(ciclo.fecha_ini)} y el {fechaCorta(ciclo.fecha_fin)}. Si rechazas una, pasa al historial.
              </p>
            )}
            <ul className="flex flex-col divide-y divide-sand text-sm">
              {filas.map((f) => {
                const propia = miPersonaId !== null && f.persona_id === miPersonaId;
                const viendo = verId === f.entrega_id;
                return (
                  <li key={f.entrega_id} className="py-3">
                    <div className="flex flex-wrap items-start justify-between gap-2">
                      <div className="min-w-0">
                        <p>
                          <span className="font-medium">{f.persona}</span>
                          <span className="text-taupe">
                            {" "}· {f.sede} · {f.institucion}{f.beneficiario_nombre ? ` (${f.beneficiario_nombre})` : ""}
                          </span>
                        </p>
                        <p className="text-xs text-taupe">
                          Pago del {fechaCorta(f.fecha_pago)} · {TIPO_CONSTANCIA_LABELS[f.tipo]} ·{" "}
                          {f.origen === "do" ? `Cargada y aprobada por ${f.aprobada_por ?? "Desarrollo Organizacional"}`
                            : f.origen === "migrada" ? "Cargada antes de la revisión de constancias"
                              : `Aprobada por ${f.aprobada_por ?? "—"}`}{" "}el {fechaHora(f.aprobada_at)}
                        </p>
                      </div>
                      <div className="flex flex-wrap items-center gap-2">
                        {f.apaga_pago && <Insignia variante="advertencia" tamano="sm">Sostiene el pago</Insignia>}
                        <Boton tamano="sm" aria-expanded={viendo} onClick={() => setVerId(viendo ? null : f.entrega_id)}>
                          {viendo ? "Ocultar constancia" : "Ver constancia"}
                        </Boton>
                        {propia ? (
                          <span className="text-xs text-taupe">Es tu constancia: la revisa otra persona de DO.</span>
                        ) : (
                          <Boton tamano="sm" variante="peligro" onClick={() => setRevirtiendo(f)}>Rechazar…</Boton>
                        )}
                      </div>
                    </div>
                    {viendo && <div className="mt-3"><LienzoArchivos archivos={f.archivos} /></div>}
                  </li>
                );
              })}
            </ul>
          </>
        )}
      </div>
  );

  const modal = (
      <Modal abierto={revirtiendo !== null} onCerrar={cerrarRechazo} bloqueado={trabajando}
        titulo="Rechazar una constancia ya aprobada" ancho="md">
        {revirtiendo && (
          <>
            <p className="mb-3 text-sm text-taupe">
              Pago del {fechaCorta(revirtiendo.fecha_pago)} de {revirtiendo.persona} ({revirtiendo.institucion}).
              Pasa a «Rechazada», {revirtiendo.persona.split(" ")[0]} lee el motivo en su Bandeja y tiene que enviar otra.
              Queda escrito quién la aprobó y quién la rechazó.
            </p>
            <p className={`mb-3 rounded-lg px-3 py-2 text-sm ${
              revirtiendo.bloqueada ? "bg-rojo/10 text-rojo-profundo" : revirtiendo.apaga_pago ? "bg-ambar/15 text-ambar" : "bg-hueso text-taupe"}`}>
              {revirtiendo.aviso}
            </p>
            {!revirtiendo.bloqueada && (
              <CamposDeRechazo categoria={categoria} onCategoria={setCategoria} comentario={comentario} onComentario={setComentario} />
            )}
            <div className="mt-4 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
              <Boton onClick={cerrarRechazo} disabled={trabajando}>Cancelar</Boton>
              <Boton variante="peligro" cargando={trabajando} onClick={() => void revertir()}
                disabled={revirtiendo.bloqueada || rechazoIncompleto(categoria, comentario) !== null}>
                Rechazar constancia
              </Boton>
            </div>
          </>
        )}
      </Modal>
  );

  if (!plegable) return <section>{cuerpo}{modal}</section>;
  return (
    // receta-propia: es un <details> plegable y TarjetaInfo no puede serlo
    <details className="mb-5 rounded-superficie border border-sand bg-papel p-4" open={abierta}
      onToggle={(e) => {
        const abre = e.currentTarget.open;
        setAbierta(abre);
        if (abre && periodos === null) void iniciar();
      }}>
      <summary className="cursor-pointer font-serif text-base">
        Aprobadas en el ciclo de pago
        {filas !== null && <span className="ml-2 text-sm text-taupe">· {filas.length}</span>}
        <span className="block font-sans text-xs text-taupe">
          A quién aprobamos, su constancia a la vista, y rechazar la que no debió aprobarse.
        </span>
      </summary>
      {cuerpo}
      {modal}
    </details>
  );
}

"use client";

// ─────────────────────────────────────────────────────────────────────────────
// Registrar una falta de conducta — el formulario detrás de las dos puertas.
//
// Se abre desde Disciplina («Registrar una falta») y desde la ficha de cada
// persona, que llega con ella ya elegida. Es UN componente porque son dos
// puertas al mismo trámite: dos formularios para lo mismo terminan pidiendo
// cosas distintas (decisión del 2026-10-06, con el prototipo
// `docs/conducta-prototipo-2026-10-06.html`).
//
// Lo que decide: nada. Quién puede registrar a quién, qué falta existe y qué
// fechas valen lo decide `fn_expediente_crear_conducta` (0510). Esto solo no
// ofrece lo que la base va a rechazar y dice qué falta para guardar.
// ─────────────────────────────────────────────────────────────────────────────

import { useEffect, useMemo, useRef, useState } from "react";
import type { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { NIVEL_DISCIPLINARIO_LABELS, fechaLima, hoyLima } from "@cayla-dynamic/shared";
import { Modal } from "@/components/ui/modal";
import { Campo } from "@/components/ui/campo";
import { BuscadorPersona } from "@/components/ui/buscador-persona";
import { useSedesPorId } from "@/lib/admin/use-sedes";
import { AreaTexto } from "@/components/ui/area-texto";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { cx } from "@/components/ui/cx";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import {
  NIVEL_SUGERIDO_CONDUCTA, PREGUNTAS_RELATO, RELATO_MINIMO, citaDeFalta, claveFalta, faltasElegibles,
  puedeRegistrarleConducta, queFaltaParaRegistrar,
  type AntecedentesConducta, type Candidata, type FaltaCatalogo, type NivelConducta, type QuienRegistra,
} from "@/lib/admin/conducta";
import { fechaConAnio } from "./formato";

type Cliente = ReturnType<typeof createAdminSupabaseClient>;

/** Lo que significa cada nivel, en la frase que se lee al elegir. */
const SENTIDO: Record<NivelConducta, string> = {
  verbal: "No es sanción y no agrava (54.2). Queda el acta en su legajo.",
  amonestacion: "Queda doce meses como antecedente, desde que se le entrega (56.1).",
};

export function ModalRegistrarFalta({
  abierto, onCerrar, supabase, yo, personaFija, onRegistrado,
}: {
  abierto: boolean;
  onCerrar: () => void;
  supabase: Cliente;
  yo: QuienRegistra | null;
  /** Desde la ficha: la persona ya viene elegida y no se puede cambiar. */
  personaFija?: { id: string; nombre: string };
  onRegistrado: (id: string) => void;
}) {
  const hoy = hoyLima();
  const sedePorId = useSedesPorId();
  // ── Lo que se lee al abrir ─────────────────────────────────────────────
  const [catalogo, setCatalogo] = useState<FaltaCatalogo[]>([]);
  const [falloCatalogo, setFalloCatalogo] = useState<string | null>(null);
  const [candidatas, setCandidatas] = useState<Array<Candidata & { nombre: string }>>([]);
  const [sinConstancia, setSinConstancia] = useState<Map<string, string>>(new Map());

  // ── Lo que llena ───────────────────────────────────────────────────────
  // Las dos fechas NACEN EN HOY y no en "": un campo de fecha cuyo vacío
  // bloquea el envío no puede arrancar vacío (quinta regla de CLAUDE.md).
  const [personaId, setPersonaId] = useState<string>(personaFija?.id ?? "");
  const [falta, setFalta] = useState<FaltaCatalogo | null>(null);
  const [fechaHecho, setFechaHecho] = useState(hoy);
  const [conocidoEl, setConocidoEl] = useState(hoy);
  const [relato, setRelato] = useState("");
  const [nivel, setNivel] = useState<NivelConducta | null>(NIVEL_SUGERIDO_CONDUCTA);
  const [antecedentes, setAntecedentes] = useState<AntecedentesConducta | null>(null);
  const [estadoAntecedentes, setEstadoAntecedentes] = useState<"nada" | "cargando" | "listo" | "fallo">("nada");
  const [guardando, setGuardando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // La última consulta de antecedentes manda: si se cambia de falta rápido,
  // la respuesta vieja no puede pisar a la nueva.
  const consulta = useRef(0);

  // Al abrir, todo de cero. SOLO al abrir: este efecto no puede depender de
  // nada que cambie mientras se escribe, o cada letra borraría el formulario.
  const personaFijaId = personaFija?.id ?? "";
  useEffect(() => {
    if (!abierto) return;
    /* eslint-disable react-hooks/set-state-in-effect -- reiniciar el formulario al abrirlo es justamente el efecto */
    setPersonaId(personaFijaId); setFalta(null); setFechaHecho(hoyLima()); setConocidoEl(hoyLima());
    setRelato(""); setNivel(NIVEL_SUGERIDO_CONDUCTA); setAntecedentes(null); setEstadoAntecedentes("nada");
    setError(null); setFalloCatalogo(null);
    /* eslint-enable react-hooks/set-state-in-effect */
  }, [abierto, personaFijaId]);

  // Y lo que hace falta leer, aparte: volver a leerlo no borra nada.
  useEffect(() => {
    if (!abierto) return;
    let vivo = true;
    void (async () => {
      const [cat, rot, gente, sc] = await Promise.all([
        supabase.from("faltas_catalogo").select("rit_version, numeral, literal, gravedad, texto, se_registra_a_mano"),
        // Tolerante: sin los nombres cortos (0514 todavía sin pegar) se elige
        // por el número, que es peor pero no impide registrar.
        supabase.from("faltas_rotulos").select("rit_version, numeral, literal, rotulo"),
        personaFija
          ? Promise.resolve({ data: [] as never[], error: null })
          : supabase.from("personas").select("id, nombres, apellidos, rol, sede_base_id, estado, en_planilla")
              .eq("estado", "activo").eq("cuenta_de_servicio", false).order("nombres"),
        supabase.rpc("fn_sin_constancia_del_reglamento"),
      ]);
      if (!vivo) return;
      if (cat.error) { setFalloCatalogo(mensajeDeError(cat.error, "leer el catálogo de faltas del Reglamento")); return; }
      const rotulos = new Map(((rot.data ?? []) as Array<{ rit_version: number; numeral: string; literal: string; rotulo: string }>)
        .map((r) => [`${Number(r.rit_version)}:${r.numeral}.${r.literal}`, r.rotulo]));
      setCatalogo(((cat.data ?? []) as Array<Omit<FaltaCatalogo, "rotulo">>).map((f) => ({
        ...f, rit_version: Number(f.rit_version), rotulo: rotulos.get(`${Number(f.rit_version)}:${f.numeral}.${f.literal}`) ?? null,
      })));
      if (yo && !personaFija) {
        const lista = ((gente.data ?? []) as Array<{ id: string; nombres: string; apellidos: string; rol: string; sede_base_id: string | null; estado: string; en_planilla: boolean }>)
          .map((p) => ({ ...p, nombre: `${p.nombres} ${p.apellidos}` }))
          .filter((p) => puedeRegistrarleConducta(yo, p));
        setCandidatas(lista);
      }
      setSinConstancia(new Map(((sc.data ?? []) as Array<{ persona_id: string; motivo: string }>).map((x) => [x.persona_id, x.motivo])));
    })();
    return () => { vivo = false; };
  }, [abierto, supabase, yo, personaFija]);

  // Lo que corresponde según el RIT, cada vez que cambia a quién, qué o cuándo.
  useEffect(() => {
    if (!abierto || !personaId || !falta || !fechaHecho) {
      /* eslint-disable-next-line react-hooks/set-state-in-effect -- sin los tres datos no hay nada que consultar */
      setEstadoAntecedentes("nada"); return;
    }
    const n = ++consulta.current;
    setEstadoAntecedentes("cargando");
    void supabase.rpc("fn_conducta_antecedentes", {
      p_persona_id: personaId, p_numeral: falta.numeral, p_literal: falta.literal, p_fecha_hecho: fechaHecho,
    }).then(({ data, error: e }) => {
      if (n !== consulta.current) return;
      if (e || !data) { setEstadoAntecedentes("fallo"); return; }
      setAntecedentes(data as unknown as AntecedentesConducta);
      setEstadoAntecedentes("listo");
    });
  }, [abierto, supabase, personaId, falta, fechaHecho]);

  const { leves, significativas } = useMemo(() => faltasElegibles(catalogo), [catalogo]);
  const queFalta = queFaltaParaRegistrar({ personaId: personaId || null, falta, fechaHecho, conocidoEl, relato, nivel }, hoy);
  const faltanLetras = Math.max(0, RELATO_MINIMO - relato.trim().length);
  const motivoSinConstancia = personaId ? sinConstancia.get(personaId) : undefined;

  async function guardar() {
    if (queFalta || !falta) return;
    setGuardando(true); setError(null);
    const { data, error: e } = await supabase.rpc("fn_expediente_crear_conducta", {
      p_persona_id: personaId, p_numeral: falta.numeral, p_literal: falta.literal, p_nivel: nivel!,
      p_fecha_hecho: fechaHecho, p_conocido_el: conocidoEl, p_relato: relato.trim(),
    });
    setGuardando(false);
    // El mensaje de la base es el bueno: dice qué regla del RIT se cruzó.
    if (e || !data) { setError(mensajeDeError(e, "registrar la falta")); return; }
    onRegistrado(data as unknown as string);
  }

  const chip = (f: FaltaCatalogo) => {
    const elegida = falta !== null && claveFalta(falta) === claveFalta(f);
    return (
      <button key={claveFalta(f)} type="button" role="radio" aria-checked={elegida} onClick={() => setFalta(f)}
        title={f.texto}
        className={cx("rounded-full border px-3 py-1.5 text-left text-sm transition-colors",
          elegida ? "border-tinta bg-tinta text-crema" : "border-sand bg-papel text-tinta hover:border-taupe")}>
        {f.rotulo ?? `${f.numeral} ${f.literal})`}
      </button>
    );
  };

  return (
    <Modal abierto={abierto} onCerrar={onCerrar} titulo="Registrar una falta" ancho="lg" bloqueado={guardando}>
      <div className="grid gap-5">
        {falloCatalogo && <BannerAviso variante="alerta" titulo="No se pudo abrir el formulario">{falloCatalogo}</BannerAviso>}

        {/* ── A quién ─────────────────────────────────────────────────── */}
        <div className="grid gap-1.5">
          {personaFija ? (
            <p className="text-sm"><span className="text-taupe">Para:</span> <span className="font-medium">{personaFija.nombre}</span></p>
          ) : (
            <BuscadorPersona
              etiqueta="¿A quién?"
              opciones={candidatas.map((p) => ({ id: p.id, nombre: p.nombre, sede: p.sede_base_id ? sedePorId.get(p.sede_base_id) ?? null : null }))}
              value={personaId}
              onChange={setPersonaId}
            />
          )}
          {!personaFija && (
            <p className="text-xs text-taupe">Solo quien tiene contrato de trabajo. Si eres líder de equipo, solo integrantes de tu sede: a otra líder la amonesta Desarrollo Organizacional.</p>
          )}
          {motivoSinConstancia && (
            <BannerAviso variante="advertencia" titulo="Todavía no firmó la constancia del Reglamento">
              Puedes guardar el borrador, pero no se podrá firmar hasta que Desarrollo Organizacional se la recoja (RIT 60.5).
            </BannerAviso>
          )}
        </div>

        {/* ── Qué pasó ────────────────────────────────────────────────── */}
        <fieldset className="grid gap-2">
          <legend className="mb-1 text-sm font-medium">¿Qué pasó?</legend>
          {[["Leves", leves], ["Significativas", significativas]].map(([titulo, lista]) => (lista as FaltaCatalogo[]).length > 0 && (
            <div key={titulo as string} className="grid gap-1.5">
              <span className="text-xs font-semibold uppercase tracking-wide text-taupe">{titulo as string}</span>
              <div role="radiogroup" aria-label={`Faltas ${(titulo as string).toLowerCase()}`} className="flex flex-wrap gap-1.5">
                {(lista as FaltaCatalogo[]).map(chip)}
              </div>
            </div>
          ))}
          {/* El nombre corto es para elegir; el papel cita esto. Tenerlo a la
              vista es lo que evita elegir por un nombre y acusar de otra cosa. */}
          <div className="rounded-control bg-hueso px-3 py-2 text-sm" aria-live="polite">
            {falta ? (
              <>
                <span className="block text-xs font-semibold uppercase tracking-wide text-taupe">Lo que dirá el papel · {citaDeFalta(falta)} del RIT</span>
                {falta.texto}
              </>
            ) : <span className="text-taupe">Elige una falta para ver qué dice el Reglamento.</span>}
          </div>
        </fieldset>

        {/* ── Cuándo ──────────────────────────────────────────────────── */}
        <div className="grid gap-3 sm:grid-cols-2">
          <Campo etiqueta="¿Cuándo pasó?" type="date" value={fechaHecho} max={hoy} onChange={(e) => setFechaHecho(e.target.value)} />
          <div className="grid gap-1">
            <Campo etiqueta="¿Cuándo te enteraste?" type="date" value={conocidoEl} max={hoy} min={fechaHecho} onChange={(e) => setConocidoEl(e.target.value)} />
            <span className="text-xs text-taupe">Si lo viste tú, es el mismo día. Desde aquí corre el plazo para actuar (52.6).</span>
          </div>
        </div>

        {/* ── El relato ───────────────────────────────────────────────── */}
        <div className="grid gap-1.5">
          <label htmlFor="rf-relato" className="text-sm font-medium">Cuéntalo como se lo contarías a alguien que no estuvo</label>
          <ul className="grid gap-0.5 text-xs text-taupe">
            {PREGUNTAS_RELATO.map((p) => <li key={p}>· {p}</li>)}
          </ul>
          <AreaTexto id="rf-relato" value={relato} rows={4} onChange={(e) => setRelato(e.target.value)}
            placeholder="Hechos, no opiniones: «le dijo … a la clienta, delante de …», no «fue grosera». Es lo que ella va a leer." />
          <span className="text-right text-xs text-taupe">{faltanLetras > 0 ? `Faltan ${faltanLetras} letras` : "✓"}</span>
        </div>

        {/* ── Lo que corresponde ──────────────────────────────────────── */}
        <div className="grid gap-1.5 rounded-control border border-pizarra/35 bg-pizarra/10 px-3 py-2.5 text-sm" aria-live="polite">
          <span className="text-xs font-semibold uppercase tracking-wide text-pizarra">Lo que corresponde</span>
          {estadoAntecedentes === "nada" && <span className="text-taupe">Elige a la persona y la falta para ver sus antecedentes.</span>}
          {estadoAntecedentes === "cargando" && <span className="text-taupe">Revisando sus antecedentes…</span>}
          {estadoAntecedentes === "fallo" && (
            <span className="text-taupe">No se pudieron revisar sus antecedentes ahora. Puedes guardar igual: quien firme los verá en el caso antes de hacerlo (56.3).</span>
          )}
          {estadoAntecedentes === "listo" && antecedentes && (
            <>
              <ul className="grid gap-0.5">
                <li>· {antecedentes.antecedente_vigente
                  ? <>Tiene una <strong>{NIVEL_DISCIPLINARIO_LABELS[antecedentes.antecedente_vigente.nivel as keyof typeof NIVEL_DISCIPLINARIO_LABELS]?.toLowerCase() ?? antecedentes.antecedente_vigente.nivel} vigente por esta misma falta</strong>, entregada el {fechaConAnio(fechaLima(antecedentes.antecedente_vigente.entregado_at))}.</>
                  : "Sin antecedentes vigentes por esta misma falta."}</li>
                <li>· Amonestaciones por faltas leves en los últimos 12 meses: <strong>{antecedentes.amonestaciones_leves_vigentes} de 3</strong>.</li>
              </ul>
              <span>{antecedentes.que_corresponde}</span>
            </>
          )}
        </div>

        {/* ── Qué hace ────────────────────────────────────────────────── */}
        <fieldset className="grid gap-2">
          <legend className="mb-1 text-sm font-medium">¿Qué vas a hacer?</legend>
          <div role="radiogroup" className="grid gap-2 sm:grid-cols-2">
            {(["verbal", "amonestacion"] as const).map((n) => (
              <button key={n} type="button" role="radio" aria-checked={nivel === n} onClick={() => setNivel(n)}
                className={cx("relative grid gap-1 rounded-control border px-3 py-2.5 text-left",
                  nivel === n ? "border-tinta bg-papel ring-1 ring-tinta" : "border-sand bg-papel hover:border-taupe")}>
                <span className="flex items-center gap-2 pr-16 font-medium">
                  <span aria-hidden className={cx("size-3.5 shrink-0 rounded-full border-2", nivel === n ? "border-tinta bg-tinta" : "border-taupe")} />
                  {NIVEL_DISCIPLINARIO_LABELS[n]}
                </span>
                <span className="text-xs text-taupe">{SENTIDO[n]}</span>
                {n === NIVEL_SUGERIDO_CONDUCTA && <Insignia variante="informativo" tamano="sm" className="absolute right-2.5 top-2.5">Sugerido</Insignia>}
              </button>
            ))}
          </div>
        </fieldset>

        {error && <BannerAviso variante="alerta" titulo="No se registró">{error}</BannerAviso>}

        <div className="flex flex-wrap items-center justify-end gap-3 border-t border-sand pt-4">
          {queFalta && <span className="mr-auto text-xs text-taupe">{queFalta}</span>}
          <Boton variante="secundario" onClick={onCerrar} disabled={guardando}>Cancelar</Boton>
          <Boton variante="primario" onClick={() => void guardar()} cargando={guardando} disabled={Boolean(queFalta) || Boolean(falloCatalogo)}>
            Guardar borrador
          </Boton>
        </div>
        <p className="text-xs text-taupe">
          Al guardar queda en Borradores. Después, como hoy: comunicar, firmar y entregar en papel o por su Info.
        </p>
      </div>
    </Modal>
  );
}

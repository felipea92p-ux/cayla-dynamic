"use client";

// ============================================================================
// Ausencias — un solo lugar para «por qué no vino»
// ----------------------------------------------------------------------------
// Absorbe la pantalla de Vacaciones: vacaciones es un tipo de ausencia más, no
// una pantalla aparte. Si fueran dos, tarde o temprano una diría una cosa y la
// otra otra — es el error que este repositorio ya pagó varias veces.
//
// Lo que esta pantalla evita, y es la razón de que exista: hasta la migración
// 0101, un día de permiso concedido se registraba como falta injustificada,
// entraba en el semáforo disciplinario y podía terminar en una carta de
// preaviso de despido por días que la propia empresa concedió.
//
// La regla del pago no la decide esta pantalla: viene del catálogo
// `tipos_ausencia`. Descanso médico y maternidad pagan porque lo manda la ley
// peruana; el resto no paga porque así lo decidió CAYLA.
// ============================================================================

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { AdminNav } from "../nav";
import { Cargando } from "@/components/cargando";
import { useRolActual } from "@/lib/admin/use-rol";
import { TZ_LIMA, puedeOperarEquipo, puedeVerTodasLasSedes } from "@cayla-dynamic/shared";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";

// ── POR QUÉ ESTAS DOS FUNCIONES VAN CON UN NOMBRE SIN TIPAR ──────────────────
//
// `packages/database/src/types.ts` se genera con `pnpm --filter …database
// gen-types`, y hoy NO conoce `fn_ausencias_subsidio` ni
// `fn_ausencia_adjuntar_certificado` porque las crea la 0197.
//
// Regenerarlo arreglaría esto en una línea, pero el archivo lleva tiempo sin
// regenerarse y la versión actual del CLI emite los parámetros opcionales como
// `string | undefined` donde la vieja ponía `string | null`. Medido el
// 2026-08-08: **53 errores en 13 pantallas**, entre ellas planilla y
// liquidaciones. Eso es una tarea propia, no un efecto colateral de agregar un
// campo a Ausencias.
//
// Así que el nombre se pasa sin tipar y SOLO el nombre: los argumentos y lo que
// devuelve siguen comprobados abajo por las interfaces `Subsidio` y por el
// `catch` de cada llamada. Cuando alguien regenere los tipos, esto se borra y
// deja de compilar si se olvida — que es justo lo que se quiere.
type NombreRpcSinTipar = Parameters<ReturnType<typeof createAdminSupabaseClient>["rpc"]>[0];
const RPC_SUBSIDIO = "fn_ausencias_subsidio" as unknown as NombreRpcSinTipar;
const RPC_ADJUNTAR = "fn_ausencia_adjuntar_certificado" as unknown as NombreRpcSinTipar;
// ⇩ 0297 · igual que las dos de arriba: nombre sin tipar hasta que se regeneren
// los tipos. Lo que devuelve lo comprueba `VacacionPorVencer`.
const RPC_POR_VENCER = "fn_vacaciones_por_vencer" as unknown as NombreRpcSinTipar;

function fmt(iso: string | null | undefined): string {
  if (!iso) return "—";
  const [y, m, d] = iso.split("-");
  if (!y || !m || !d) return iso;
  return `${d}/${m}/${y}`;
}
// Hoy en Lima. Con new Date().toISOString() (UTC) a partir de las 19:00 daría mañana.
function hoyLima(): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: TZ_LIMA, year: "numeric", month: "2-digit", day: "2-digit",
  }).format(new Date());
}
function haceMeses(n: number): string {
  const [y, m, d] = hoyLima().split("-").map(Number);
  return new Date(Date.UTC(y, m - 1 - n, d)).toISOString().slice(0, 10);
}

interface Persona { id: string; nombres: string; apellidos: string }
interface Tipo {
  codigo: string; nombre: string; paga: boolean;
  requiere_documento: boolean; requiere_aprobacion: boolean;
}
interface Ausencia {
  id: string; persona_id: string; nombre: string; sede: string;
  tipo: string; tipo_nombre: string; paga: boolean; requiere_aprobacion: boolean;
  fecha_inicio: string; fecha_fin: string; dias: number; motivo: string | null;
  doc_profesional: string | null; doc_colegiatura: string | null; doc_fecha: string | null;
  aprobada: boolean; registrada_tarde: boolean;
  registrada_por_nombre: string | null; registrada_at: string;
  anulada: boolean; anulada_motivo: string | null;
}
interface Alerta {
  persona_id: string; nombre: string; tipo_nombre: string;
  veces: number; ventana_dias: number; umbral: number;
}

/** Días de descanso médico acumulados en el año — el cupo de EsSalud (0197). */
interface Subsidio {
  persona_id: string; nombre: string; dias_calendario: number;
  umbral: number; hay_que_avisar: boolean;
  dias_para_el_umbral: number; sin_certificado: number;
}

export default function AusenciasPage() {
  const router = useRouter();
/** Un récord de vacaciones que vence pronto, o que ya venció (migración 0297).
 *  Es lo único de esta pantalla que tiene FECHA LÍMITE: pasada, el art. 23 del
 *  D. Leg. 713 manda una indemnización de una remuneración entera. */
// CAMBIO 0302 — La forma la manda `fn_vacaciones_por_vencer` de la 0297, que es
// la que quedó viva. En `main` convivían dos implementaciones con firmas
// distintas y llamarla reventaba; la que se fue devolvía
// `nombre · dias_saldo · records_pendientes · ya_vencido`.
//
// OJO CON `vence_el`: acá es el PRÓXIMO récord por vencer, no el más antiguo.
// Los que ya se pasaron se cuentan aparte en `records_vencidos`. Mezclarlos
// haría escribir «ya vencido desde» junto a una fecha futura.
interface VacacionPorVencer {
  persona_id: string;
  persona: string;
  sede: string;
  fecha_ingreso: string;
  dias_pendientes: number;
  records_sin_gozar: number;
  records_vencidos: number;
  vence_el: string;
  dias_para_vencer: number;
}

  const rol = useRolActual();
  const puedeGestionar = puedeOperarEquipo(rol);
  const esDO = puedeVerTodasLasSedes(rol);
  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  const [personas, setPersonas] = useState<Persona[]>([]);
  const [tipos, setTipos] = useState<Tipo[]>([]);
  const [lista, setLista] = useState<Ausencia[]>([]);
  const [alertas, setAlertas] = useState<Alerta[]>([]);
  const [porVencer, setPorVencer] = useState<VacacionPorVencer[]>([]);
  const [cargando, setCargando] = useState(true);
  const [msg, setMsg] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  const [guardando, setGuardando] = useState(false);

  // Formulario
  const [personaId, setPersonaId] = useState("");
  const [tipoCod, setTipoCod] = useState("");
  const [inicio, setInicio] = useState(hoyLima());
  const [fin, setFin] = useState(hoyLima());
  const [motivo, setMotivo] = useState("");
  const [docProf, setDocProf] = useState("");
  const [docColeg, setDocColeg] = useState("");
  const [docFecha, setDocFecha] = useState("");
  const [archivo, setArchivo] = useState<File | null>(null);
  const [progreso, setProgreso] = useState<number | null>(null);
  const [subsidio, setSubsidio] = useState<Subsidio[]>([]);

  const [desde, setDesde] = useState(haceMeses(6));
  const [hasta, setHasta] = useState(haceMeses(-6));

  const tipoSel = tipos.find((t) => t.codigo === tipoCod) ?? null;

  const cargar = useCallback(async () => {
    setCargando(true);
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    const [{ data: p, error: eP }, { data: t }, { data: a, error: eA }, { data: al }, { data: sub }, { data: pv }] = await Promise.all([
      supabase.from("personas").select("id, nombres, apellidos").eq("estado", "activo").order("nombres"),
      supabase.rpc("fn_tipos_ausencia"),
      supabase.rpc("fn_ausencias", { p_desde: desde, p_hasta: hasta }),
      supabase.rpc("fn_ausencias_alerta", {}),
      supabase.rpc(RPC_SUBSIDIO, {}),
      supabase.rpc(RPC_POR_VENCER, {})   // 60 dias por defecto, en la propia funcion (0297),
    ]);
    // Si la carga falla no se pisa la lista con datos parciales: mostrar media
    // lista de ausencias es peor que no mostrar ninguna.
    if (eP || eA) {
      setMsg({ tipo: "error", texto: `No se pudieron cargar las ausencias: ${(eP ?? eA)!.message}` });
      setCargando(false);
      return;
    }
    setPersonas((p as Persona[]) ?? []);
    const tt = (t as unknown as Tipo[]) ?? [];
    setTipos(tt);
    setTipoCod((prev) => prev || tt[0]?.codigo || "");
    setLista((a as unknown as Ausencia[]) ?? []);
    setAlertas((al as unknown as Alerta[]) ?? []);
    setSubsidio((sub as unknown as Subsidio[]) ?? []);
    setPorVencer((pv as unknown as VacacionPorVencer[]) ?? []);
    setCargando(false);
  }, [supabase, router, desde, hasta]);

  useEffect(() => { void cargar(); }, [cargar]);

  async function registrar() {
    if (!personaId) { setMsg({ tipo: "error", texto: "Elige a la persona." }); return; }
    if (!tipoCod) { setMsg({ tipo: "error", texto: "Elige el tipo de ausencia." }); return; }
    if (fin < inicio) { setMsg({ tipo: "error", texto: "La fecha de fin no puede ser anterior a la de inicio." }); return; }
    setGuardando(true);
    setMsg(null);
    const { data: nuevoId, error } = await supabase.rpc("fn_registrar_ausencia", {
      p_persona_id: personaId,
      p_tipo: tipoCod,
      p_fecha_inicio: inicio,
      p_fecha_fin: fin,
      p_motivo: motivo.trim() || null,
      p_doc_profesional: docProf.trim() || null,
      p_doc_colegiatura: docColeg.trim() || null,
      p_doc_fecha: docFecha || null,
    });
    if (error) { setGuardando(false); setMsg({ tipo: "error", texto: error.message }); return; }

    // El certificado, si se eligió uno. Va DESPUÉS porque su ruta lleva dentro
    // el id de la ausencia, que hasta acá no existía.
    //
    // Si la subida falla, la ausencia YA quedó registrada y eso está bien: el
    // registro es lo que evita que esos días cuenten como falta, y perderlo por
    // un archivo que no subió sería el peor intercambio posible. El mensaje lo
    // dice para que nadie crea que no se guardó nada.
    if (archivo && nuevoId) {
      const ext = archivo.name.split(".").pop()?.toLowerCase() ?? "bin";
      const ruta = `certificados/${personaId}/${nuevoId}.${ext}`;
      setProgreso(0);
      const errorSubida = await subirArchivoConProgreso(supabase, "certificados", ruta, archivo, setProgreso);
      setProgreso(null);
      if (errorSubida) {
        setGuardando(false);
        setMsg({ tipo: "error", texto: `La ausencia SÍ quedó registrada, pero el certificado no subió (${errorSubida}). Esos días ya no cuentan como falta; el papel puedes adjuntarlo después.` });
        await cargar();
        return;
      }
      // El `as never` va por lo mismo que el nombre: sin la función en los tipos
      // generados, TypeScript infiere `never` para sus argumentos. Los dos
      // valores son los que la 0197 declara y el servidor los valida igual.
      const { error: eAdj } = await supabase.rpc(RPC_ADJUNTAR, {
        p_ausencia_id: nuevoId, p_storage_path: ruta,
      } as never);
      if (eAdj) {
        setGuardando(false);
        setMsg({ tipo: "error", texto: `La ausencia quedó registrada y el archivo subió, pero no se pudo enlazar (${eAdj.message}).` });
        await cargar();
        return;
      }
    }

    setGuardando(false);
    setMotivo(""); setDocProf(""); setDocColeg(""); setDocFecha(""); setArchivo(null);
    await cargar();
    setMsg({
      tipo: "ok",
      texto: tipoSel?.requiere_aprobacion
        ? "Registrada. Como es un tipo que se paga, queda pendiente de aprobación de Desarrollo Organizacional."
        : "Registrada. Esos días dejan de contar como falta injustificada.",
    });
  }

  async function anular(a: Ausencia) {
    const m = window.prompt(
      `Vas a anular «${a.tipo_nombre}» de ${a.nombre} (${fmt(a.fecha_inicio)} → ${fmt(a.fecha_fin)}).\n\n` +
        "No se borra: queda en el historial con el motivo. ¿Por qué se anula?",
    );
    if (m === null) return;
    if (m.trim().length < 4) { setMsg({ tipo: "error", texto: "El motivo es obligatorio (mínimo 4 caracteres)." }); return; }
    setGuardando(true);
    const { error } = await supabase.rpc("fn_anular_ausencia", { p_id: a.id, p_motivo: m.trim() });
    setGuardando(false);
    if (error) { setMsg({ tipo: "error", texto: error.message }); return; }
    await cargar();
    setMsg({ tipo: "ok", texto: "Ausencia anulada. Esos días vuelven a contarse como antes." });
  }

  async function aprobar(a: Ausencia) {
    if (!window.confirm(
      `Aprobar «${a.tipo_nombre}» de ${a.nombre}, ${a.dias} día${a.dias === 1 ? "" : "s"}.\n\n` +
      "Es un tipo que SE PAGA: al aprobarlo, esos días entran en su planilla.",
    )) return;
    setGuardando(true);
    const { error } = await supabase.rpc("fn_aprobar_ausencia", { p_id: a.id });
    setGuardando(false);
    if (error) { setMsg({ tipo: "error", texto: error.message }); return; }
    await cargar();
    setMsg({ tipo: "ok", texto: "Aprobada." });
  }

  if (rol !== null && !puedeGestionar) {
    return (
      <div className="flex min-h-screen flex-col">
        <AdminNav />
        <main className="flex flex-1 items-center justify-center p-6">
          <p className="max-w-md text-center text-taupe">No tienes permiso para gestionar ausencias.</p>
        </main>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <h1 className="mb-1 font-serif text-2xl">Ausencias</h1>
        <p className="mb-4 max-w-3xl text-xs text-taupe">
          Todos los días que alguien no vino, y por qué — vacaciones incluidas. Un día registrado aquí{" "}
          <strong className="font-medium">deja de contar como falta injustificada</strong> y no alimenta el
          expediente disciplinario. En CAYLA ningún permiso se paga, salvo los dos que la ley obliga a pagar:
          descanso médico con documento y maternidad.
        </p>

        {msg && (
          <div className={`mb-4 max-w-3xl rounded-lg px-4 py-3 text-sm ${msg.tipo === "ok" ? "bg-sand/40 text-tinta" : "bg-rojo/10 text-rojo"}`}>
            {msg.texto}
          </div>
        )}

        {/* ── RÉCORDS DE VACACIONES POR VENCER (0299) ──────────────────────
            VA EN ROJO Y VA PRIMERA, y las dos cosas a propósito.

            El resto de avisos de esta pantalla son «para mirar»: cuentan algo y
            alguien decide. Éste no: tiene FECHA. Pasada esa fecha, el art. 23
            del D. Leg. 713 manda una indemnización de una remuneración entera,
            y ya no hay nada que decidir — solo pagarla.

            Por eso existe: hasta la 0283, esto solo aparecía en la hoja de
            liquidación, o sea el día en que la persona ya se fue y el récord ya
            había vencido. Avisar ahí llega tarde por definición. */}
        {porVencer.length > 0 && (
          <div className="mb-4 max-w-3xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
            <p className="font-medium">Vacaciones que vencen: hay que programarlas.</p>
            <ul className="mt-1 space-y-0.5 text-xs">
              {porVencer.map((v) => (
                <li key={v.persona_id}>
                  <strong className="font-medium">{v.persona}</strong>{" "}
                  {v.records_vencidos > 0 ? (
                    // La fecha NO se pone junto a «ya vencido»: `vence_el` es la del
                    // próximo, no la del que se pasó. Decir «vencido desde el
                    // {fecha futura}» sería falso, y de las dos mitades la urgente es
                    // la que ya se perdió.
                    <>tiene {v.records_vencidos === 1 ? "un récord" : `${v.records_vencidos} récords`} de
                      vacaciones <strong className="font-medium">ya vencido{v.records_vencidos === 1 ? "" : "s"}</strong>
                      {" "}— {v.dias_pendientes} días sin gozar. El siguiente vence el {fmt(v.vence_el)}.</>
                  ) : (
                    <>tiene {v.dias_pendientes} días sin gozar y su récord vence
                      el {fmt(v.vence_el)}, en {v.dias_para_vencer} días.</>
                  )}
                </li>
              ))}
            </ul>
            <p className="mt-1.5 text-xs opacity-80">
              Un récord que vence sin gozarse obliga a pagar una indemnización de una remuneración
              (art. 23, D. Leg. 713). Programar el descanso cuesta cero.
            </p>
          </div>
        )}

        {alertas.length > 0 && (
          <div className="mb-4 max-w-3xl rounded-lg bg-ambar/15 px-4 py-3 text-sm text-ambar">
            <p className="font-medium">Para mirar, no para sancionar:</p>
            <ul className="mt-1 space-y-0.5 text-xs">
              {alertas.map((a) => (
                <li key={`${a.persona_id}-${a.tipo_nombre}`}>
                  <strong className="font-medium">{a.nombre}</strong> lleva {a.veces} veces «{a.tipo_nombre}»
                  en los últimos {a.ventana_dias} días (el aviso salta a partir de {a.umbral}).
                </li>
              ))}
            </ul>
            <p className="mt-1.5 text-xs opacity-80">
              El sistema cuenta y lo dice. Conversar o no es decisión de una persona, siempre.
            </p>
          </div>
        )}

        {/* EL CUPO DE ESSALUD. No es disciplinario y por eso no va en ámbar con
            el aviso de arriba: esto es plata que la empresa puede recuperar, no
            una conducta que mirar. Los primeros 20 días de incapacidad del año
            los paga CAYLA; desde el 21 los subsidia EsSalud, y el reclamo se
            sustenta con el CITT (0197).

            Salta a los 15 y no a los 20 a propósito: un aviso en el día 21 llega
            cuando el gasto ya ocurrió. */}
        {subsidio.some((s) => s.hay_que_avisar) && (
          <div className="mb-4 max-w-3xl rounded-lg bg-tinta/5 px-4 py-3 text-sm">
            <p className="font-medium">EsSalud puede reembolsar parte de esto:</p>
            <ul className="mt-1 space-y-0.5 text-xs">
              {subsidio.filter((s) => s.hay_que_avisar).map((s) => (
                <li key={s.persona_id}>
                  <strong className="font-medium">{s.nombre}</strong> lleva{" "}
                  <strong className="font-medium">{s.dias_calendario} días</strong> de descanso médico este año
                  {s.dias_para_el_umbral > 0
                    ? ` — faltan ${s.dias_para_el_umbral} para los ${s.umbral} que paga CAYLA.`
                    : ` — ya pasó los ${s.umbral}: desde el día ${s.umbral + 1} el subsidio es de EsSalud.`}
                  {s.sin_certificado > 0 && (
                    <span className="block text-taupe">
                      {s.sin_certificado === 1
                        ? "Uno de sus descansos no tiene el certificado adjunto"
                        : `${s.sin_certificado} de sus descansos no tienen el certificado adjunto`}{" "}
                      — sin el CITT no se puede reclamar.
                    </span>
                  )}
                </li>
              ))}
            </ul>
            <p className="mt-1.5 text-xs text-taupe">
              Se cuentan días corridos, domingos incluidos: es como los emite el CITT y como los lleva EsSalud.
              La maternidad no entra — tiene su propio subsidio desde el primer día.
            </p>
          </div>
        )}

        {/* Registrar */}
        <div className="mb-6 grid max-w-4xl gap-3 rounded-2xl border border-sand bg-papel p-5 sm:grid-cols-2">
          <label className="flex flex-col gap-1 text-sm">
            Persona
            <select value={personaId} onChange={(e) => setPersonaId(e.target.value)} className="rounded-lg border bg-crema px-3 py-2">
              <option value="">Elegir…</option>
              {personas.map((p) => (<option key={p.id} value={p.id}>{p.nombres} {p.apellidos}</option>))}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-sm">
            Tipo
            <select value={tipoCod} onChange={(e) => setTipoCod(e.target.value)} className="rounded-lg border bg-crema px-3 py-2">
              {tipos.map((t) => (
                <option key={t.codigo} value={t.codigo}>
                  {t.nombre}{t.paga ? " · se paga" : ""}
                </option>
              ))}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-sm">
            Desde
            <input type="date" value={inicio} onChange={(e) => { setInicio(e.target.value); if (fin < e.target.value) setFin(e.target.value); }} className="rounded-lg border px-3 py-2" />
          </label>
          <label className="flex flex-col gap-1 text-sm">
            Hasta
            <input type="date" value={fin} onChange={(e) => setFin(e.target.value)} className="rounded-lg border px-3 py-2" />
          </label>
          <label className="flex flex-col gap-1 text-sm sm:col-span-2">
            Motivo <span className="text-taupe">(lo que se conversó; queda en su historial)</span>
            <input value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="ej. fallecimiento de familiar directo" className="rounded-lg border px-3 py-2" />
          </label>

          {tipoSel?.requiere_documento && (
            <>
              {/* EMPIEZA POR LA RESPUESTA, y no es un detalle de estilo.
                  Este párrafo decía «Este tipo se paga, así que exige documento»
                  y sólo después, a media frase y en gris, «no se guarda el
                  papel». El 2026-08-08 Felipe leyó la primera mitad y se pasó un
                  rato buscando dónde subirlo. El texto estaba arriba de los
                  campos —eso no era el problema— pero abría mandando a buscar un
                  botón. Quien llega con el certificado en la mano necesita saber
                  QUÉ HACER en la primera línea, no el fundamento. */}
              <p className="text-xs text-taupe sm:col-span-2">
                <strong className="font-medium text-tinta">Lo obligatorio son los tres datos de abajo</strong>{" "}
                — quién firmó, su colegiatura y la fecha. Eso es lo verificable: un número de CMP se comprueba
                contra el registro del Colegio Médico. Subir el certificado es <strong className="font-medium">opcional</strong>,
                y conviene hacerlo si el descanso se alarga: a partir del día 21 del año EsSalud reembolsa, y
                ese reclamo se sustenta con el CITT. Si no tienes ningún documento, regístralo como{" "}
                <strong className="font-medium">Descanso por salud</strong> — no paga, pero tampoco cuenta como falta.
              </p>
              <label className="flex flex-col gap-1 text-sm">
                Profesional o institución
                <input value={docProf} onChange={(e) => setDocProf(e.target.value)} placeholder="ej. Dra. Rojas / Clínica San Pablo" className="rounded-lg border px-3 py-2" />
              </label>
              <label className="flex flex-col gap-1 text-sm">
                N.º de colegiatura (CMP) o de CITT
                <input value={docColeg} onChange={(e) => setDocColeg(e.target.value)} placeholder="ej. CMP 12345" className="rounded-lg border px-3 py-2" />
              </label>
              <label className="flex flex-col gap-1 text-sm">
                Fecha de emisión
                <input type="date" value={docFecha} onChange={(e) => setDocFecha(e.target.value)} className="rounded-lg border px-3 py-2" />
              </label>
              {/* El certificado, OPCIONAL. Va en un almacén propio que solo abren
                  admin y líder de DO: un certificado dice el diagnóstico de una
                  persona, y la encargada de sede necesita saber que no vino y que
                  está justificado, no de qué está enferma (0197). */}
              <label className="flex flex-col gap-1 text-sm sm:col-span-2">
                Certificado o CITT <span className="text-taupe">(opcional — solo lo ven Administración y DO)</span>
                <input
                  type="file"
                  accept=".pdf,.jpg,.jpeg,.png,.heic,.heif,.webp"
                  onChange={(e) => setArchivo(e.target.files?.[0] ?? null)}
                  className="rounded-lg border px-3 py-2 text-sm file:mr-3 file:rounded file:border-0 file:bg-sand file:px-3 file:py-1 file:text-sm"
                />
                {progreso !== null && (
                  <span className="text-xs text-taupe">Subiendo… {progreso}%</span>
                )}
              </label>
            </>
          )}

          <div className="flex items-end gap-3 sm:col-span-2">
            <button onClick={registrar} disabled={guardando} className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50">
              {guardando ? "Guardando…" : "Registrar ausencia"}
            </button>
            {tipoSel && (
              <span className="text-xs text-taupe">
                {tipoSel.paga
                  ? "Se paga · lo aprueba Desarrollo Organizacional antes de entrar en planilla."
                  : "No se paga · esos días no se cobran, pero tampoco son falta."}
              </span>
            )}
          </div>
        </div>

        {/* Rango a mostrar */}
        <div className="mb-3 flex flex-wrap items-end gap-3">
          <label className="flex flex-col gap-1 text-xs text-taupe">
            Desde
            <input type="date" value={desde} onChange={(e) => setDesde(e.target.value)} className="rounded-lg border px-3 py-1.5 text-sm text-tinta" />
          </label>
          <label className="flex flex-col gap-1 text-xs text-taupe">
            Hasta
            <input type="date" value={hasta} onChange={(e) => setHasta(e.target.value)} className="rounded-lg border px-3 py-1.5 text-sm text-tinta" />
          </label>
        </div>

        {cargando ? (
          <Cargando texto="Cargando las ausencias…" />
        ) : lista.length === 0 ? (
          <div className="max-w-2xl rounded-lg bg-sand/40 px-4 py-3 text-sm text-taupe">
            No hay ausencias registradas en ese rango de fechas.
          </div>
        ) : (
          <div className="overflow-x-auto rounded-2xl border border-sand">
            <table className="w-full text-sm">
              <thead className="bg-sand/70 text-left text-taupe">
                <tr>
                  <th className="px-4 py-2 font-normal">Persona</th>
                  <th className="px-4 py-2 font-normal">Tipo</th>
                  <th className="px-4 py-2 font-normal">Fechas</th>
                  <th className="px-4 py-2 text-right font-normal">Días</th>
                  <th className="px-4 py-2 font-normal">Estado</th>
                  <th className="px-4 py-2 font-normal">Acciones</th>
                </tr>
              </thead>
              <tbody>
                {lista.map((a) => (
                  <tr key={a.id} className={`border-t bg-papel ${a.anulada ? "text-taupe/60" : ""}`}>
                    <td className="px-4 py-2">
                      <span className={a.anulada ? "line-through" : ""}>{a.nombre}</span>
                      <div className="text-xs text-taupe">{a.sede}</div>
                    </td>
                    <td className="px-4 py-2">
                      {a.tipo_nombre}
                      {a.paga && <span className="ml-1.5 rounded-full bg-sand px-2 py-0.5 text-xs">se paga</span>}
                      {a.motivo && <div className="text-xs text-taupe">{a.motivo}</div>}
                      {a.doc_colegiatura && (
                        <div className="text-xs text-taupe">
                          {a.doc_profesional} · {a.doc_colegiatura} · {fmt(a.doc_fecha)}
                        </div>
                      )}
                    </td>
                    <td className="px-4 py-2 whitespace-nowrap">
                      {fmt(a.fecha_inicio)} → {fmt(a.fecha_fin)}
                      {a.registrada_tarde && !a.anulada && (
                        <div className="text-xs text-ambar">registrada con más de 15 días de retraso</div>
                      )}
                      <div className="text-xs text-taupe">
                        registró {a.registrada_por_nombre ?? "—"}
                      </div>
                    </td>
                    <td className="px-4 py-2 text-right tabular-nums">{a.dias}</td>
                    <td className="px-4 py-2">
                      {a.anulada ? (
                        <>
                          <span className="rounded-full bg-sand px-2 py-0.5 text-xs">anulada</span>
                          <div className="text-xs text-taupe">{a.anulada_motivo}</div>
                        </>
                      ) : a.requiere_aprobacion && !a.aprobada ? (
                        <span className="rounded-full bg-ambar/20 px-2 py-0.5 text-xs text-ambar">
                          pendiente de aprobar
                        </span>
                      ) : (
                        <span className="rounded-full bg-sand px-2 py-0.5 text-xs">vigente</span>
                      )}
                    </td>
                    <td className="px-4 py-2">
                      {!a.anulada && (
                        <div className="flex flex-wrap gap-2 text-xs">
                          {esDO && a.requiere_aprobacion && !a.aprobada && (
                            <button onClick={() => void aprobar(a)} disabled={guardando} className="rounded border px-2 py-1 hover:bg-sand/50 disabled:opacity-50">
                              Aprobar
                            </button>
                          )}
                          <button onClick={() => void anular(a)} disabled={guardando} className="rounded border border-rojo/30 px-2 py-1 text-rojo hover:bg-rojo/10 disabled:opacity-50">
                            Anular
                          </button>
                        </div>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        <p className="mt-4 max-w-3xl text-xs text-taupe">
          Una ausencia no se borra: se anula con motivo y queda en el historial. Y no se puede registrar ni
          anular nada dentro de un periodo de planilla ya pagado — para eso hay que reabrirlo primero, igual
          que con todo lo demás que toca plata.
        </p>
      </main>
    </div>
  );
}

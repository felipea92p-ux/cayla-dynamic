"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { EMPRESA } from "@cayla-dynamic/shared";
import { Cargando } from "@/components/cargando";
import { Marca } from "@/components/marca";
import { Boton } from "@/components/ui/boton";
import { AreaTexto } from "@/components/ui/area-texto";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { FirmaEditor } from "@/app/(admin)/admin/personas/[id]/FirmaEditor";

/**
 * Tu declaración de ruta y gasto de transporte, en autoservicio (0423).
 *
 * QUÉ REEMPLAZA. Hasta hoy el único camino era admin/documentacion: se
 * imprimía, se firmaba a mano y un admin subía el escaneo. Esta pantalla
 * reemplaza ese trámite entero para quien firma desde acá — decisión de
 * Felipe, 2026-09-12: la firma digital tiene el MISMO valor que el escaneo,
 * no es una confirmación aparte como la del contrato (`/mio/contrato`, que sí
 * sigue dependiendo del papel físico). Desarrollo Organizacional conserva la
 * vía del escaneo para quien no pueda firmar desde acá.
 *
 * EL MONTO NUNCA SE PIDE ACÁ (0425). Lo calcula el servidor con la tarifa
 * vigente de tu sede — nunca un gasto que la persona arme sola.
 *
 * LA HOJA ES EL FORMULARIO (0426). Antes había un formulario aparte —campos
 * `Campo` arriba— y un párrafo suelto abajo explicando lo que se firmaba. A
 * pedido de Felipe, esos campos ahora VIVEN dentro del propio papel: el mismo
 * documento con membrete que ya imprime `admin/documentacion` (mismo texto,
 * mismo orden de los cinco puntos), pero en vez de rayas en blanco para
 * llenar a mano, son inputs. Firmar deja de
 * ser "llenar un formulario y confirmar" para ser "leer el documento, llenar
 * lo que falta y firmarlo" — la misma idea que ya usa `/mio/contrato`.
 *
 * EL PASAJE Y EL TAXI VOLVIERON (0489). La 0425 y la 0426 los habían quitado;
 * se devolvieron para que la hoja digital diga lo mismo que el papel. Son
 * DESCRIPTIVOS: lo que se paga sigue siendo la tarifa de la sede, nunca lo que
 * la persona escribe acá. El gasto diario no se pide — se calcula.
 *
 * UNA VEZ FIRMADA Y AL DÍA, QUEDA FIJA (0425). Ya no hay "Declarar de nuevo":
 * `fn_confirmar_mi_declaracion_ruta` rechaza una segunda firma mientras la
 * vigente siga vigente. Si algo cambió de verdad, se pide una revisión —con
 * un motivo— y le llega a admin/líder, con el mismo mecanismo que ya usa este
 * repositorio para pedir que se revise un día de marcaje (`revisiones_pedidas`,
 * 0257). Sí se puede volver a firmar sola cuando la declaración quedó
 * DESFASADA (cambió la tarifa de la sede): ahí no hay nada que corregir de
 * tu parte, solo una fecha y un monto que actualizar.
 */

interface MiDeclaracion {
  estado: "sin_ruta" | "se_nego" | "ok";
  ruta_firmada_el: string | null;
  ruta_monto: number | null;
  ruta_desfasada: boolean;
  ruta_firma_persona_confirmada_at: string | null;
  ruta_tarifa_vigente: number | null;
}

/** Una solicitud suya de revisión de la declaración de ruta (0425). */
interface MiRevision {
  id: string;
  motivo: string;
  pedida_at: string;
  atendida_at: string | null;
  respuesta: string | null;
}

/** El documento que ya firmó, para poder verlo y descargarlo — no solo el
 *  resumen de una línea que ya trae `MiDeclaracion`. Las cuatro piezas
 *  (distrito/provincia/medios) son `null` si firmó antes de la 0429: esa
 *  fecha vivían solo adentro de `declarada`, y ahí se muestra tal cual. Las
 *  del pasaje y el taxi son `null` si firmó antes de la 0489 — y las del
 *  taxi también cuando declaró que no lo usa. */
interface MiDocumento {
  declarada: string | null;
  firma: string | null;
  distrito: string | null;
  provincia: string | null;
  mediosIda: number | null;
  mediosVuelta: number | null;
  costoPasaje: number | null;
  gastoDiario: number | null;
  costoTaxi: number | null;
  frecuenciaTaxi: number | null;
}

interface Yo {
  id: string;
  nombre: string;
  nombreOficial: string;
  documento: string | null;
  funcion: string | null;
  sedeNombre: string | null;
}

const soles = (n: number) => Number(n).toFixed(2);

/** Lo que cuesta ir y volver en un día: cada medio de ida y de regreso es un
 *  pasaje. La MISMA fórmula con la que `fn_confirmar_mi_declaracion_ruta`
 *  (0489) congela `ruta_gasto_diario` — esto solo la muestra mientras se llena. */
function gastoDiario(ida: string, vuelta: string, pasaje: string): number | null {
  const [i, v, p] = [Number(ida), Number(vuelta), Number(pasaje)];
  if (pasaje.trim() === "" || [i, v, p].some((n) => !Number.isFinite(n) || n < 0)) return null;
  return Math.round((i + v) * p * 100) / 100;
}

function fechaLarga(iso: string): string {
  return new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "long", year: "numeric" }).format(
    new Date(`${iso}T12:00:00`),
  );
}

// Estilo de "raya para llenar", no de campo de formulario: el input vive
// adentro de una oración y no puede parecer una caja aparte, o el documento
// deja de leerse como documento.
const CLASE_INPUT_HOJA =
  "border-b border-tinta bg-transparent px-1 text-center focus:outline-none focus:border-b-2";

function MiMovilidadContenido() {
  const router = useRouter();
  const supabase = createAdminSupabaseClient();

  const [yo, setYo] = useState<Yo | null>(null);
  const [declaracion, setDeclaracion] = useState<MiDeclaracion | null | undefined>(undefined);
  const [miFirma, setMiFirma] = useState<string | null>(null);
  const [miRevision, setMiRevision] = useState<MiRevision | null>(null);
  // El documento completo de lo que ya firmó — para poder verlo y bajarlo en
  // PDF, no solo leer el resumen de una línea. `null` mientras no haya nada
  // firmado todavía.
  const [miDocumento, setMiDocumento] = useState<MiDocumento | null>(null);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // La firma de la empresa (Gerencia General) — igual que /mio/contrato:
  // se muestra siempre, sin importar quién mire, porque es la del cargo, no
  // la de la sesión.
  const [firmaEmpresa, setFirmaEmpresa] = useState<string | null>(null);
  const [firmanteNombre, setFirmanteNombre] = useState<string | null>(null);
  const [firmanteCargo, setFirmanteCargo] = useState<string | null>(null);

  // El formulario arranca abierto salvo que ya haya una declaración firmada
  // y al día: si le falta o quedó vieja, es lo primero que tiene que ver.
  const [formAbierto, setFormAbierto] = useState(false);
  const [distrito, setDistrito] = useState("");
  const [provincia, setProvincia] = useState("Lima");
  const [mediosIda, setMediosIda] = useState("1");
  const [mediosVuelta, setMediosVuelta] = useState("1");
  const [costoPasaje, setCostoPasaje] = useState("");
  // El taxi es opcional: los dos en blanco = no lo usa.
  const [costoTaxi, setCostoTaxi] = useState("");
  const [vecesTaxi, setVecesTaxi] = useState("");
  const [firmando, setFirmando] = useState(false);

  // Ver/descargar la declaración ya firmada (0430) — arranca cerrado para no
  // alargar la pantalla en cada visita; un clic la despliega entera.
  const [verDocumento, setVerDocumento] = useState(false);

  // Formulario de "pedir revisión" — la única puerta que queda una vez que la
  // declaración está vigente y al día.
  const [formRevisionAbierto, setFormRevisionAbierto] = useState(false);
  const [motivoRevision, setMotivoRevision] = useState("");
  const [enviandoRevision, setEnviandoRevision] = useState(false);

  const [aviso, setAviso] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);

  const cargar = useCallback(async () => {
    setCargando(true);
    setError(null);

    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) {
      router.replace("/mio");
      return;
    }
    const { data: sesionAuth } = await supabase.auth.getUser();
    const uid = sesionAuth.user?.id;
    if (!uid) {
      setCargando(false);
      setError("No se pudo leer tu sesión. Vuelve a entrar.");
      return;
    }

    const { data: p } = await supabase
      .from("personas")
      .select("id, nombres, apellidos, documento, funcion, sede_base_id")
      .eq("auth_user_id", uid)
      .maybeSingle();
    if (!p) {
      setCargando(false);
      setError("Tu cuenta todavía no está enlazada con tu ficha. Avisa a Desarrollo Organizacional.");
      return;
    }
    const [{ data: ficha }, { data: sede }] = await Promise.all([
      supabase.from("datos_personales").select("nombre_dni").eq("persona_id", p.id as string).maybeSingle(),
      supabase.from("sedes").select("nombre").eq("id", p.sede_base_id as string).maybeSingle(),
    ]);
    const nombre = `${p.nombres as string} ${p.apellidos as string}`;
    setYo({
      id: p.id as string,
      nombre,
      nombreOficial: (ficha?.nombre_dni as string | null) || nombre,
      documento: (p.documento as string | null) ?? null,
      funcion: (p.funcion as string | null) ?? null,
      sedeNombre: (sede?.nombre as string | null) ?? null,
    });

    // Quién firma por CAYLA — mismo dato que ya usa admin/documentacion
    // (`configuracion.firmante_empresa`), pero acá se muestra siempre: a
    // diferencia de esa pantalla, aquí quien mira nunca es la firmante.
    const { data: cfgFirmante } = await supabase
      .from("configuracion").select("valor").eq("clave", "firmante_empresa").maybeSingle();
    const vf = (cfgFirmante?.valor ?? null) as { persona_id?: string; cargo?: string } | null;
    if (vf?.persona_id) {
      const { data: firmante } = await supabase
        .from("personas").select("nombres, apellidos").eq("id", vf.persona_id).maybeSingle();
      if (firmante) setFirmanteNombre(`${firmante.nombres as string} ${firmante.apellidos as string}`);
    }
    setFirmanteCargo(vf?.cargo ?? null);

    // p_solo_mi_fila => true: la MISMA función que usa el tablero admin, pero
    // pidiendo solo mi fila — necesario incluso si quien pregunta es admin
    // (ver el comentario CAMBIO 0423 en la migración).
    const [{ data: fila, error: eFila }, { data: fu }, { data: revs, error: eRevs }, { data: fe }, { data: docs }] =
      await Promise.all([
        supabase.rpc("fn_documentos_tablero", { p_solo_mi_fila: true }),
        supabase.rpc("fn_mi_firma"),
        // Sin admin de por medio: para una persona que no es admin, esta misma
        // RPC ya devuelve solo lo suyo (0425), igual que fn_documentos_tablero.
        supabase.rpc("fn_movilidad_revisiones_pedidas", { p_solo_pendientes: false }),
        supabase.rpc("fn_firma_empresa"),
        // El documento completo (0429): sin admin de por medio, esta RPC
        // también devuelve solo lo suyo — mismo criterio que las de arriba.
        supabase.rpc("fn_documentos_listar"),
      ]);
    setCargando(false);
    if (eFila) {
      setError(mensajeDeError(eFila, "traer tu declaración de ruta"));
      return;
    }
    const propia = ((fila as MiDeclaracion[] | null) ?? [])[0] ?? null;
    setDeclaracion(propia);
    setFormAbierto(propia === null ? false : propia.estado !== "ok" || propia.ruta_desfasada);
    setMiFirma((fu as string | null) ?? null);
    setFirmaEmpresa((fe as string | null) ?? null);
    // La más reciente primero (fn_movilidad_revisiones_pedidas ya ordena por
    // pedida_at desc); si no falló, aunque venga vacía, es una respuesta real.
    setMiRevision(eRevs ? null : (((revs as MiRevision[] | null) ?? [])[0] ?? null));
    type FilaDoc = {
      tipo: string; vigente: boolean; ruta_declarada: string | null; firma_persona: string | null;
      ruta_distrito: string | null; ruta_provincia: string | null;
      ruta_medios_ida: number | null; ruta_medios_vuelta: number | null;
      ruta_costo_pasaje: number | null; ruta_gasto_diario: number | null;
      ruta_costo_taxi: number | null; ruta_frecuencia_taxi: number | null;
    };
    const miRuta = ((docs as FilaDoc[] | null) ?? []).find((d) => d.tipo === "ruta" && d.vigente);
    setMiDocumento(miRuta ? {
      declarada: miRuta.ruta_declarada,
      firma: miRuta.firma_persona,
      distrito: miRuta.ruta_distrito,
      provincia: miRuta.ruta_provincia,
      mediosIda: miRuta.ruta_medios_ida,
      mediosVuelta: miRuta.ruta_medios_vuelta,
      costoPasaje: miRuta.ruta_costo_pasaje,
      gastoDiario: miRuta.ruta_gasto_diario,
      costoTaxi: miRuta.ruta_costo_taxi,
      frecuenciaTaxi: miRuta.ruta_frecuencia_taxi,
    } : null);
  }, [supabase, router]);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargar(); }, [cargar]);

  useTituloDocumento(yo && miDocumento ? `${yo.nombre} — Declaración de ruta de transporte` : null);

  async function firmar() {
    if (!miFirma) {
      setAviso({ tipo: "error", texto: "Todavía no configuraste tu firma. Bájala aquí abajo antes de confirmar." });
      return;
    }
    setFirmando(true);
    setAviso(null);
    const { error: eFirmar } = await supabase.rpc("fn_confirmar_mi_declaracion_ruta", {
      p_distrito: distrito.trim(),
      p_provincia: provincia.trim(),
      p_medios_ida: Number(mediosIda),
      p_medios_vuelta: Number(mediosVuelta),
      p_costo_pasaje: Number(costoPasaje),
      // En blanco = no usa taxi: se manda null, no 0, para que el servidor no
      // tenga que adivinar si «0» fue una respuesta o un campo sin tocar.
      p_costo_taxi: costoTaxi.trim() === "" ? null : Number(costoTaxi),
      p_frecuencia_taxi: vecesTaxi.trim() === "" ? null : Number(vecesTaxi),
    });
    setFirmando(false);
    if (eFirmar) {
      setAviso({ tipo: "error", texto: mensajeDeError(eFirmar, "firmar tu declaración") });
      return;
    }
    setAviso({ tipo: "ok", texto: "Declaración firmada. Ya no hace falta que imprimas ni subas nada." });
    await cargar();
  }

  async function pedirRevision() {
    if (motivoRevision.trim().length < 5) {
      setAviso({ tipo: "error", texto: "Cuéntanos qué cambió, aunque sea en una línea." });
      return;
    }
    setEnviandoRevision(true);
    const { error: eRevision } = await supabase.rpc("fn_pedir_revision_movilidad", {
      p_motivo: motivoRevision.trim(),
    });
    setEnviandoRevision(false);
    if (eRevision) {
      setAviso({ tipo: "error", texto: mensajeDeError(eRevision, "pedir la revisión") });
      return;
    }
    setAviso({ tipo: "ok", texto: "Pedido. Desarrollo Organizacional lo va a ver." });
    setMotivoRevision("");
    setFormRevisionAbierto(false);
    await cargar();
  }

  if (cargando) {
    return <main className="p-6"><Cargando /></main>;
  }
  if (error) {
    return (
      <main className="p-6">
        <p className="max-w-md rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
          {error} <Boton variante="enlace" onClick={() => void cargar()}>Reintentar</Boton>
        </p>
        <Link href="/mio" className="mt-3 inline-block text-sm text-taupe hover:text-tinta hover:underline">
          ← Volver a Info
        </Link>
      </main>
    );
  }

  const vigenteYAlDia = declaracion != null && declaracion.estado === "ok" && !declaracion.ruta_desfasada;
  const tarifa = declaracion?.ruta_tarifa_vigente ?? null;
  const gasto = gastoDiario(mediosIda, mediosVuelta, costoPasaje);

  return (
    <main className="mx-auto max-w-2xl p-6">
      <Link href="/mio" className="mb-4 inline-block text-sm text-taupe hover:text-tinta hover:underline">
        ← Volver a Info
      </Link>
      <h1 className="mb-1 font-serif text-xl">Declaración de ruta y gasto de transporte</h1>
      <p className="mb-6 text-sm text-taupe">
        Es el papel que sostiene que tu movilidad no paga impuestos ni descuentos (D.S. 001-97-TR, art. 19 e).
        Firmarla acá la reemplaza por completo: no hace falta imprimir, firmar a mano ni escanear nada.
      </p>

      {declaracion === null ? (
        <p className="rounded-lg bg-sand/40 px-4 py-3 text-sm text-taupe">
          Esto no te corresponde por ahora — no aplica a tu tipo de vínculo, o tu contrato ya está por terminar.
          Si crees que es un error, avisa a Desarrollo Organizacional.
        </p>
      ) : (
        <>
          {/* Vive FUERA de la hoja a propósito: si al firmar con éxito
              `cargar()` decide cerrar el formulario (porque ya quedó al día),
              este aviso tiene que seguir en pantalla — adentro desaparecería
              con él antes de que nadie llegue a leerlo. */}
          {aviso && (
            <p className={`mb-4 rounded-lg px-4 py-3 text-sm ${
              aviso.tipo === "ok" ? "bg-verde/10 text-verde" : "bg-rojo/10 text-rojo"}`}
            >
              {aviso.texto}
            </p>
          )}

          {/* ── ESTADO ACTUAL ──────────────────────────────────────────── */}
          <section className="mb-4 rounded-2xl border border-sand p-5 text-sm">
            {declaracion!.estado === "ok" && !declaracion!.ruta_desfasada && (
              <p className="text-verde">
                Firmada el {fechaLarga(declaracion!.ruta_firmada_el!)}, declarando S/{" "}
                {Number(declaracion!.ruta_monto).toFixed(2)} por día efectivamente asistido.
                {declaracion!.ruta_firma_persona_confirmada_at
                  ? " Firma digital."
                  : " Firma escaneada, subida por Desarrollo Organizacional."}
              </p>
            )}
            {declaracion!.estado === "ok" && declaracion!.ruta_desfasada && (
              <p className="text-rojo">
                Firmada el {fechaLarga(declaracion!.ruta_firmada_el!)} declarando S/{" "}
                {Number(declaracion!.ruta_monto).toFixed(2)}, pero hoy tu sede paga S/{" "}
                {Number(declaracion!.ruta_tarifa_vigente).toFixed(2)}. Vuelve a firmarla con el monto vigente.
              </p>
            )}
            {declaracion!.estado === "sin_ruta" && (
              <p className="text-rojo">Todavía te falta firmarla.</p>
            )}
            {declaracion!.estado === "se_nego" && (
              <p className="text-taupe">
                Quedó registrado que se te ofreció firmarla y no lo hiciste. Si cambiaste de opinión, puedes
                firmarla ahora mismo.
              </p>
            )}
            {!vigenteYAlDia && !formAbierto && (
              <Boton variante="primario" tamano="sm" className="mt-3" onClick={() => setFormAbierto(true)}>
                Firmar ahora
              </Boton>
            )}
            {declaracion!.estado === "ok" && miDocumento && !verDocumento && (
              <Boton variante="enlace" className="mt-3 block" onClick={() => setVerDocumento(true)}>
                Ver mi declaración firmada
              </Boton>
            )}
          </section>

          {/* ── MI DECLARACIÓN YA FIRMADA — para ver y descargar (0430) ─────
              Ya no se puede volver a firmar sola una vez vigente y al día
              (0425): esta es la única forma de verla y bajarla en PDF, igual
              que ya hace /mio/contrato con el contrato propio. */}
          {declaracion!.estado === "ok" && miDocumento && verDocumento && (
            <div className="mb-4 rounded-2xl border border-sand p-5">
              <div className="mb-3 flex items-center justify-between print:hidden">
                <h2 className="font-serif text-lg">Tu declaración firmada</h2>
                <div className="flex items-center gap-3">
                  <Boton variante="primario" tamano="sm" onClick={() => window.print()}>
                    Imprimir / Guardar como PDF
                  </Boton>
                  <Boton variante="enlace" onClick={() => setVerDocumento(false)}>Cerrar</Boton>
                </div>
              </div>

              <div className="hoja rounded-lg border border-sand p-8 text-sm leading-relaxed print:rounded-none print:border-0 print:p-0">
                <div className="mb-6 flex items-start justify-between border-b border-sand pb-4">
                  <Marca tono="tinta" isotipo="rojo" />
                  <div className="text-right text-xs text-taupe">
                    <p>{EMPRESA.nombre}</p>
                    <p>RUC {EMPRESA.ruc}</p>
                  </div>
                </div>

                <h2 className="mb-6 text-center font-serif text-xl">
                  Declaración de ruta y gasto de transporte
                </h2>

                <p className="mb-4">
                  Yo, <strong>{yo?.nombreOficial}</strong>, con documento de identidad N.º{" "}
                  <strong>{yo?.documento ?? "—"}</strong>, que desempeño el cargo de{" "}
                  <strong>{yo?.funcion ?? "—"}</strong> en la sede <strong>{yo?.sedeNombre ?? "—"}</strong> de{" "}
                  {EMPRESA.nombre}, declaro lo siguiente respecto de mi traslado diario entre mi domicilio y mi
                  centro de labores:
                </p>

                {miDocumento.distrito ? (
                  // Firmada desde la 0429: las piezas se guardaron aparte, así
                  // que se arma la misma lista que se vio al firmar.
                  <>
                    <ol className="mb-6 list-decimal space-y-2 pl-6">
                      <li>
                        Resido en el distrito de <strong>{miDocumento.distrito}</strong>, provincia de{" "}
                        <strong>{miDocumento.provincia}</strong>.
                      </li>
                      <li>
                        Para llegar a mi centro de labores utilizo <strong>{miDocumento.mediosIda}</strong>{" "}
                        medio(s) de transporte por tramo, y de regreso <strong>{miDocumento.mediosVuelta}</strong>.
                      </li>
                      {/* Pasaje y taxi (0489): solo si se declararon. Lo
                          firmado antes no los tenía, y no se inventan. */}
                      {miDocumento.costoPasaje !== null && (
                        <>
                          <li>
                            El costo de cada pasaje es de S/ <strong>{soles(miDocumento.costoPasaje)}</strong>, de
                            modo que mi gasto diario habitual de ida y vuelta asciende a S/{" "}
                            <strong>{soles(miDocumento.gastoDiario ?? 0)}</strong>.
                          </li>
                          <li>
                            {miDocumento.costoTaxi !== null ? (
                              <>
                                Según el horario de mi turno, en ocasiones debo utilizar taxi u otro medio
                                particular, cuyo costo por viaje asciende aproximadamente a S/{" "}
                                <strong>{soles(miDocumento.costoTaxi)}</strong>. Esto ocurre alrededor de{" "}
                                <strong>{miDocumento.frecuenciaTaxi}</strong> veces por semana.
                              </>
                            ) : (
                              <>No utilizo taxi ni otro medio particular para este traslado.</>
                            )}
                          </li>
                        </>
                      )}
                      <li>
                        Declaro que la información consignada es veraz, y me comprometo a informar a{" "}
                        {EMPRESA.nombre} si cambio de domicilio o de ruta habitual.
                      </li>
                    </ol>
                    <p className="mb-6">
                      Tomo conocimiento de que {EMPRESA.nombre} me otorga una asignación por movilidad de{" "}
                      <strong>
                        S/ {declaracion!.ruta_monto !== null ? Number(declaracion!.ruta_monto).toFixed(2) : "—"} por
                        día efectivamente asistido
                      </strong>
                      , destinada a cubrir dicho traslado; que se abona únicamente por los días en que asisto a
                      laborar, no correspondiendo en caso de inasistencia, licencia o descanso; y que este
                      concepto <strong>no tiene carácter remunerativo</strong>, conforme al artículo 19 inciso e)
                      del Decreto Supremo N.º 001-97-TR.
                    </p>
                  </>
                ) : miDocumento.declarada ? (
                  // Firmada antes de la 0429: esas columnas no existían ese
                  // día, así que se muestra el texto real que se firmó.
                  <p className="mb-6">{miDocumento.declarada}</p>
                ) : (
                  <p className="mb-6 text-taupe">No se guardó el texto de esta declaración.</p>
                )}

                <p className="mb-10 text-xs text-taupe">
                  Suscrito en {yo?.sedeNombre ?? "—"}
                  {declaracion!.ruta_firmada_el && <>, el {fechaLarga(declaracion!.ruta_firmada_el)}</>}.
                </p>

                <div className="grid grid-cols-2 gap-10 pt-6">
                  <div className="text-center">
                    <div className="flex h-24 items-end justify-center">
                      {miDocumento.firma && (
                        <img src={miDocumento.firma} alt="" aria-hidden className="block h-24 w-auto max-w-full" />
                      )}
                    </div>
                    <div className="mb-1 border-t border-tinta pt-2 text-xs">{yo?.nombreOficial}</div>
                    <p className="text-xs text-taupe">DNI {yo?.documento ?? "—————"} · el/la declarante</p>
                  </div>
                  <div className="text-center">
                    <div className="flex h-24 items-end justify-center">
                      {firmaEmpresa && (
                        <img src={firmaEmpresa} alt="" aria-hidden className="block h-24 w-auto max-w-full" />
                      )}
                    </div>
                    <div className="mb-1 border-t border-tinta pt-2 text-xs">{firmanteNombre}</div>
                    <p className="text-xs text-taupe">{firmanteCargo} · {EMPRESA.nombre}</p>
                  </div>
                </div>
                <p className="mt-6 text-center text-xs text-taupe">
                  Firma digital, confirmada desde el sistema
                  {declaracion!.ruta_firmada_el && <> el {fechaLarga(declaracion!.ruta_firmada_el)}</>}.
                </p>
              </div>
            </div>
          )}

          {/* ── VIGENTE Y AL DÍA: la única puerta es pedir revisión ───────── */}
          {vigenteYAlDia && (
            <section className="mb-4 rounded-2xl border border-sand p-5 text-sm">
              <h2 className="mb-1 font-serif text-lg">¿Algo cambió?</h2>
              <p className="mb-3 text-taupe">
                Tu declaración ya está firmada y al día, así que no se puede reemplazar sola. Si te mudaste o
                cambiaste de ruta, contalo acá y Desarrollo Organizacional lo revisa.
              </p>

              {miRevision && !miRevision.atendida_at ? (
                <div className="rounded-lg border border-tinta/20 px-3 py-2">
                  <p className="text-taupe">Pediste una revisión:</p>
                  <p className="mt-1">«{miRevision.motivo}»</p>
                  <p className="mt-2 text-taupe">Todavía sin responder.</p>
                </div>
              ) : (
                <>
                  {miRevision?.atendida_at && (
                    <p className="mb-3 rounded-lg bg-verde/10 px-3 py-2 text-verde">
                      Tu pedido anterior («{miRevision.motivo}») quedó respondido:{" "}
                      {miRevision.respuesta ?? "sin comentario"}
                    </p>
                  )}
                  {formRevisionAbierto ? (
                    <div>
                      <AreaTexto
                        value={motivoRevision}
                        onChange={(e) => setMotivoRevision(e.target.value)}
                        rows={2}
                        placeholder="Ej. me mudé a otro distrito el mes pasado"
                      />
                      <div className="mt-2 flex items-center gap-3">
                        <Boton variante="primario" tamano="sm" cargando={enviandoRevision}
                          onClick={() => void pedirRevision()}>
                          Pedir revisión
                        </Boton>
                        <Boton variante="secundario" tamano="sm" onClick={() => setFormRevisionAbierto(false)}>
                          Cancelar
                        </Boton>
                      </div>
                    </div>
                  ) : (
                    <Boton variante="secundario" tamano="sm" onClick={() => setFormRevisionAbierto(true)}>
                      Pedir revisión
                    </Boton>
                  )}
                </>
              )}
            </section>
          )}

          {/* ── LA HOJA ES EL FORMULARIO (0426) ───────────────────────────── */}
          {formAbierto && (
            <div className="rounded-2xl border border-sand p-5">
              {/* Mismo criterio visual que /mio/contrato y admin/documentacion:
                  el papel sigue el tema en pantalla, y solo se fuerza a la
                  paleta clara al imprimir (ver @media print de globals.css). */}
              <div className="hoja mb-4 rounded-lg border border-sand p-6 text-sm leading-relaxed">
                <div className="mb-6 flex items-start justify-between border-b border-sand pb-4">
                  <Marca tono="tinta" isotipo="rojo" />
                  <div className="text-right text-xs text-taupe">
                    <p>{EMPRESA.nombre}</p>
                    <p>RUC {EMPRESA.ruc}</p>
                  </div>
                </div>

                <h2 className="mb-6 text-center font-serif text-xl">
                  Declaración de ruta y gasto de transporte
                </h2>

                <p className="mb-4">
                  Yo, <strong>{yo?.nombreOficial}</strong>, con documento de identidad N.º{" "}
                  <strong>{yo?.documento ?? "—"}</strong>, que desempeño el cargo de{" "}
                  <strong>{yo?.funcion ?? "—"}</strong> en la sede <strong>{yo?.sedeNombre ?? "—"}</strong>{" "}
                  de {EMPRESA.nombre}, declaro lo siguiente respecto de mi traslado diario entre mi domicilio y
                  mi centro de labores:
                </p>

                <ol className="mb-6 list-decimal space-y-3 pl-6">
                  <li>
                    Resido en el distrito de{" "}
                    <input
                      value={distrito}
                      onChange={(e) => setDistrito(e.target.value)}
                      placeholder="distrito"
                      className={`${CLASE_INPUT_HOJA} w-44`}
                    />
                    , provincia de{" "}
                    <input
                      value={provincia}
                      onChange={(e) => setProvincia(e.target.value)}
                      placeholder="provincia"
                      className={`${CLASE_INPUT_HOJA} w-32`}
                    />
                    .
                  </li>
                  <li>
                    Para llegar a mi centro de labores utilizo{" "}
                    <input
                      type="number" min={0} max={10}
                      value={mediosIda}
                      onChange={(e) => setMediosIda(e.target.value)}
                      className={`${CLASE_INPUT_HOJA} w-12`}
                    />{" "}
                    medio(s) de transporte por tramo, y de regreso{" "}
                    <input
                      type="number" min={0} max={10}
                      value={mediosVuelta}
                      onChange={(e) => setMediosVuelta(e.target.value)}
                      className={`${CLASE_INPUT_HOJA} w-12`}
                    />
                    .
                  </li>
                  <li>
                    El costo de cada pasaje es de S/{" "}
                    <input
                      type="number" min={0} step="0.10" inputMode="decimal"
                      value={costoPasaje}
                      onChange={(e) => setCostoPasaje(e.target.value)}
                      placeholder="0.00"
                      className={`${CLASE_INPUT_HOJA} w-20`}
                    />
                    , de modo que mi gasto diario habitual de ida y vuelta asciende a S/{" "}
                    {/* No se escribe: sale de los medios × el pasaje, igual
                        que lo congela el servidor al firmar. */}
                    <strong>{gasto !== null ? soles(gasto) : "—"}</strong>.
                  </li>
                  <li>
                    Según el horario de mi turno, en ocasiones debo utilizar taxi u otro medio particular,
                    cuyo costo por viaje asciende aproximadamente a S/{" "}
                    <input
                      type="number" min={0} step="0.50" inputMode="decimal"
                      value={costoTaxi}
                      onChange={(e) => setCostoTaxi(e.target.value)}
                      placeholder="0.00"
                      className={`${CLASE_INPUT_HOJA} w-20`}
                    />
                    . Esto ocurre alrededor de{" "}
                    <input
                      type="number" min={0} max={7}
                      value={vecesTaxi}
                      onChange={(e) => setVecesTaxi(e.target.value)}
                      placeholder="0"
                      className={`${CLASE_INPUT_HOJA} w-12`}
                    />{" "}
                    veces por semana.
                    <span className="mt-1 block text-xs text-taupe">
                      Si no usas taxi, deja estos dos en blanco.
                    </span>
                  </li>
                  <li>
                    Declaro que la información consignada es veraz, y me comprometo a informar a{" "}
                    {EMPRESA.nombre} si cambio de domicilio o de ruta habitual.
                  </li>
                </ol>

                <p className="mb-6">
                  Tomo conocimiento de que {EMPRESA.nombre} me otorga una asignación por movilidad de{" "}
                  <strong>S/ {tarifa !== null ? tarifa.toFixed(2) : "—"} por día efectivamente asistido</strong>,
                  destinada a cubrir dicho traslado; que se abona únicamente por los días en que asisto a
                  laborar, no correspondiendo en caso de inasistencia, licencia o descanso; y que este concepto{" "}
                  <strong>no tiene carácter remunerativo</strong>, conforme al artículo 19 inciso e) del Decreto
                  Supremo N.º 001-97-TR.
                </p>

                <p className="mb-10 text-xs text-taupe">
                  Suscrito en {yo?.sedeNombre ?? "—"}, el {fechaLarga(new Date().toISOString().slice(0, 10))}.
                </p>

                <div className="grid grid-cols-2 gap-10 border-t border-sand pt-6">
                  <div>
                    <div className="flex h-16 items-end justify-center">
                      {miFirma && <img src={miFirma} alt="Tu firma" className="max-h-16" />}
                    </div>
                    <p className="border-t border-tinta pt-1 text-center text-xs">{yo?.nombreOficial}</p>
                    <p className="text-center text-xs text-taupe">DNI {yo?.documento ?? "—"} · el/la declarante</p>
                  </div>
                  <div>
                    <div className="flex h-16 items-end justify-center">
                      {firmaEmpresa && <img src={firmaEmpresa} alt="Firma de la empresa" className="max-h-16" />}
                    </div>
                    <p className="border-t border-tinta pt-1 text-center text-xs">{firmanteNombre ?? "—"}</p>
                    <p className="text-center text-xs text-taupe">{firmanteCargo ?? "—"} · {EMPRESA.nombre}</p>
                  </div>
                </div>
              </div>

              <div className="mb-4 border-t border-sand pt-4">
                <h3 className="mb-1 font-serif text-base">Tu firma</h3>
                {yo && (
                  <FirmaEditor
                    supabase={supabase}
                    nombreOficial={yo.nombreOficial}
                    avisar={(tipo, texto) => setAviso({ tipo, texto })}
                    onGuardada={setMiFirma}
                  />
                )}
              </div>

              <div className="flex items-center gap-3">
                <Boton
                  variante="primario"
                  cargando={firmando}
                  disabled={!miFirma || !distrito.trim() || !provincia.trim() || gasto === null}
                  onClick={() => void firmar()}
                >
                  Firmar mi declaración
                </Boton>
              </div>
              {!miFirma && (
                <p className="mt-2 text-xs text-taupe">Configura tu firma arriba antes de poder confirmar.</p>
              )}
            </div>
          )}
        </>
      )}
    </main>
  );
}

export default function MiMovilidadPage() {
  return <MiMovilidadContenido />;
}

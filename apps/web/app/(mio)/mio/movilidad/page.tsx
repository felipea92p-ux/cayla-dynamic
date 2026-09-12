"use client";

import { useCallback, useEffect, useState, type FormEvent } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Cargando } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoCasilla } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
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
 * vigente de tu sede — antes el formulario pedía "costo de cada pasaje" y
 * calculaba un "gasto diario" propio, que podía no coincidir con la tarifa
 * oficial (S/10 Trujillo/Arequipa, S/12 Lima). Felipe decidió quitarlo: lo
 * que se declara es CÓMO te trasladas, nunca cuánto cuesta — eso lo dice la
 * tarifa, siempre.
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

function fechaLarga(iso: string): string {
  return new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "long", year: "numeric" }).format(
    new Date(`${iso}T12:00:00`),
  );
}

function MiMovilidadContenido() {
  const router = useRouter();
  const supabase = createAdminSupabaseClient();

  const [yo, setYo] = useState<{ id: string; nombre: string; nombreOficial: string } | null>(null);
  const [declaracion, setDeclaracion] = useState<MiDeclaracion | null | undefined>(undefined);
  const [miFirma, setMiFirma] = useState<string | null>(null);
  const [miRevision, setMiRevision] = useState<MiRevision | null>(null);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // El formulario arranca abierto salvo que ya haya una declaración firmada
  // y al día: si le falta o quedó vieja, es lo primero que tiene que ver.
  const [formAbierto, setFormAbierto] = useState(false);
  const [distrito, setDistrito] = useState("");
  const [provincia, setProvincia] = useState("Lima");
  const [mediosIda, setMediosIda] = useState("1");
  const [mediosVuelta, setMediosVuelta] = useState("1");
  const [usaTaxi, setUsaTaxi] = useState(false);
  const [firmando, setFirmando] = useState(false);

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
      .from("personas").select("id, nombres, apellidos").eq("auth_user_id", uid).maybeSingle();
    if (!p) {
      setCargando(false);
      setError("Tu cuenta todavía no está enlazada con tu ficha. Avisa a Desarrollo Organizacional.");
      return;
    }
    const { data: ficha } = await supabase
      .from("datos_personales").select("nombre_dni").eq("persona_id", p.id as string).maybeSingle();
    const nombre = `${p.nombres as string} ${p.apellidos as string}`;
    setYo({ id: p.id as string, nombre, nombreOficial: (ficha?.nombre_dni as string | null) || nombre });

    // p_solo_mi_fila => true: la MISMA función que usa el tablero admin, pero
    // pidiendo solo mi fila — necesario incluso si quien pregunta es admin
    // (ver el comentario CAMBIO 0423 en la migración).
    const [{ data: fila, error: eFila }, { data: fu }, { data: revs, error: eRevs }] = await Promise.all([
      supabase.rpc("fn_documentos_tablero", { p_solo_mi_fila: true }),
      supabase.rpc("fn_mi_firma"),
      // Sin admin de por medio: para una persona que no es admin, esta misma
      // RPC ya devuelve solo lo suyo (0425), igual que fn_documentos_tablero.
      supabase.rpc("fn_movilidad_revisiones_pedidas", { p_solo_pendientes: false }),
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
    // La más reciente primero (fn_movilidad_revisiones_pedidas ya ordena por
    // pedida_at desc); si no falló, aunque venga vacía, es una respuesta real.
    setMiRevision(eRevs ? null : (((revs as MiRevision[] | null) ?? [])[0] ?? null));
  }, [supabase, router]);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargar(); }, [cargar]);

  async function firmar(e: FormEvent) {
    e.preventDefault();
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
      p_usa_taxi: usaTaxi,
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
          {/* Vive FUERA del <form> a propósito: si al firmar con éxito
              `cargar()` decide cerrar el formulario (porque ya quedó al día),
              este aviso tiene que seguir en pantalla — adentro del <form>
              desaparecería con él antes de que nadie llegue a leerlo. */}
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
          </section>

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

          {/* ── FORMULARIO DE FIRMA ────────────────────────────────────── */}
          {formAbierto && (
            <form onSubmit={(e) => void firmar(e)} className="rounded-2xl border border-sand p-5">
              <h2 className="mb-3 font-serif text-lg">Tu traslado diario entre tu domicilio y tu centro de labores</h2>

              <div className="mb-4 grid grid-cols-2 gap-3">
                <Campo etiqueta="Distrito donde resides" value={distrito}
                  onChange={(e) => setDistrito(e.target.value)} required />
                <Campo etiqueta="Provincia" value={provincia}
                  onChange={(e) => setProvincia(e.target.value)} required />
              </div>

              <div className="mb-4 grid grid-cols-2 gap-3">
                <Campo etiqueta="Medios de transporte de ida" type="number" min={0} max={10} value={mediosIda}
                  onChange={(e) => setMediosIda(e.target.value)} required />
                <Campo etiqueta="Medios de transporte de vuelta" type="number" min={0} max={10} value={mediosVuelta}
                  onChange={(e) => setMediosVuelta(e.target.value)} required />
              </div>

              <div className="mb-4">
                <CampoCasilla
                  etiqueta="En ocasiones uso taxi u otro medio particular"
                  checked={usaTaxi}
                  onChange={(e) => setUsaTaxi(e.target.checked)}
                />
              </div>

              <p className="mb-4 rounded-lg bg-sand/40 px-3 py-2 text-xs text-taupe">
                Al firmar, tomas conocimiento de que CAYLA te otorga una asignación de S/{" "}
                {declaracion!.ruta_tarifa_vigente !== null ? Number(declaracion!.ruta_tarifa_vigente).toFixed(2) : "—"}{" "}
                por día efectivamente asistido —la tarifa oficial de tu sede, no un cálculo tuyo—, que no
                corresponde en caso de inasistencia, licencia o descanso, y que este concepto no tiene carácter
                remunerativo (art. 19 inciso e del D.S. N.º 001-97-TR). Declaras que la información consignada es
                veraz y te comprometes a informar a CAYLA si cambias de domicilio o de ruta habitual.
              </p>

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
                <Boton type="submit" variante="primario" cargando={firmando} disabled={!miFirma}>
                  Firmar mi declaración
                </Boton>
              </div>
              {!miFirma && (
                <p className="mt-2 text-xs text-taupe">Configura tu firma arriba antes de poder confirmar.</p>
              )}
            </form>
          )}
        </>
      )}
    </main>
  );
}

export default function MiMovilidadPage() {
  return <MiMovilidadContenido />;
}

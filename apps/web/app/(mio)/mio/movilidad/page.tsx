"use client";

import { useCallback, useEffect, useState, type FormEvent } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Cargando } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoCasilla } from "@/components/ui/campo";
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
 * LOS CINCO DATOS DEL FORMULARIO no son un resumen: son los mismos que hoy se
 * llenan a mano en el papel impreso (ver `hoja()` en
 * admin/documentacion/page.tsx). `fn_confirmar_mi_declaracion_ruta` los
 * compone en el mismo texto que hoy queda escrito ahí — para que esta firma
 * sostenga exactamente lo mismo que el escaneo que reemplaza.
 *
 * EL MONTO NUNCA SE PIDE ACÁ. Lo calcula el servidor con la tarifa vigente de
 * tu sede — mismo criterio que usa `fn_documentos_tablero` para decidir si tu
 * declaración quedó desfasada. Pedirlo por formulario dejaría declarar
 * cualquier número desde la consola del navegador.
 */

interface MiDeclaracion {
  estado: "sin_ruta" | "se_nego" | "ok";
  ruta_firmada_el: string | null;
  ruta_monto: number | null;
  ruta_desfasada: boolean;
  ruta_firma_persona_confirmada_at: string | null;
  ruta_tarifa_vigente: number | null;
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
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // El formulario arranca abierto salvo que ya haya una declaración firmada
  // y al día: si le falta o quedó vieja, es lo primero que tiene que ver.
  const [formAbierto, setFormAbierto] = useState(false);
  const [distrito, setDistrito] = useState("");
  const [provincia, setProvincia] = useState("Lima");
  const [mediosIda, setMediosIda] = useState("1");
  const [mediosVuelta, setMediosVuelta] = useState("1");
  const [costoPasaje, setCostoPasaje] = useState("");
  const [usaTaxi, setUsaTaxi] = useState(false);
  const [costoTaxi, setCostoTaxi] = useState("");
  const [frecuenciaTaxi, setFrecuenciaTaxi] = useState("");
  const [firmando, setFirmando] = useState(false);
  const [avisoFirma, setAvisoFirma] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);

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
    const [{ data: fila, error: eFila }, { data: fu }] = await Promise.all([
      supabase.rpc("fn_documentos_tablero", { p_solo_mi_fila: true }),
      supabase.rpc("fn_mi_firma"),
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
  }, [supabase, router]);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargar(); }, [cargar]);

  const gastoDiario = (() => {
    const ida = Number(mediosIda), vuelta = Number(mediosVuelta), costo = Number(costoPasaje);
    if (!Number.isFinite(ida) || !Number.isFinite(vuelta) || !Number.isFinite(costo)) return null;
    return (ida + vuelta) * costo;
  })();

  async function firmar(e: FormEvent) {
    e.preventDefault();
    if (!miFirma) {
      setAvisoFirma({ tipo: "error", texto: "Todavía no configuraste tu firma. Bájala aquí abajo antes de confirmar." });
      return;
    }
    setFirmando(true);
    setAvisoFirma(null);
    const { error: eFirmar } = await supabase.rpc("fn_confirmar_mi_declaracion_ruta", {
      p_distrito: distrito.trim(),
      p_provincia: provincia.trim(),
      p_medios_ida: Number(mediosIda),
      p_medios_vuelta: Number(mediosVuelta),
      p_costo_pasaje: Number(costoPasaje),
      p_usa_taxi: usaTaxi,
      p_costo_taxi: usaTaxi ? Number(costoTaxi) : null,
      p_frecuencia_taxi: usaTaxi ? Number(frecuenciaTaxi) : null,
    });
    setFirmando(false);
    if (eFirmar) {
      setAvisoFirma({ tipo: "error", texto: mensajeDeError(eFirmar, "firmar tu declaración") });
      return;
    }
    setAvisoFirma({ tipo: "ok", texto: "Declaración firmada. Ya no hace falta que imprimas ni subas nada." });
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
          {avisoFirma && (
            <p className={`mb-4 rounded-lg px-4 py-3 text-sm ${
              avisoFirma.tipo === "ok" ? "bg-verde/10 text-verde" : "bg-rojo/10 text-rojo"}`}
            >
              {avisoFirma.texto}
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
            {(declaracion!.estado !== "ok" || declaracion!.ruta_desfasada) ? (
              !formAbierto && (
                <Boton variante="primario" tamano="sm" className="mt-3" onClick={() => setFormAbierto(true)}>
                  Firmar ahora
                </Boton>
              )
            ) : (
              !formAbierto && (
                <Boton variante="secundario" tamano="sm" className="mt-3" onClick={() => setFormAbierto(true)}>
                  Declarar de nuevo (cambié de domicilio o de ruta)
                </Boton>
              )
            )}
          </section>

          {/* ── FORMULARIO ─────────────────────────────────────────────── */}
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

              <div className="mb-2 grid grid-cols-2 gap-3">
                <Campo etiqueta="Costo de cada pasaje (S/)" type="number" min={0} step={0.1} value={costoPasaje}
                  onChange={(e) => setCostoPasaje(e.target.value)} required />
                <div>
                  <label className="mb-1 block text-[11px] font-medium uppercase tracking-wide text-taupe">
                    Gasto diario (calculado)
                  </label>
                  <p className="rounded-lg border border-sand bg-sand/40 px-3 py-2 text-sm text-tinta">
                    {gastoDiario !== null ? `S/ ${gastoDiario.toFixed(2)}` : "—"}
                  </p>
                </div>
              </div>
              <p className="mb-4 text-xs text-taupe">Ida más vuelta, por el costo de cada pasaje.</p>

              <div className="mb-3">
                <CampoCasilla
                  etiqueta="En ocasiones uso taxi u otro medio particular"
                  checked={usaTaxi}
                  onChange={(e) => setUsaTaxi(e.target.checked)}
                />
              </div>
              {usaTaxi && (
                <div className="mb-4 grid grid-cols-2 gap-3">
                  <Campo etiqueta="Costo por viaje (S/)" type="number" min={0} step={0.1} value={costoTaxi}
                    onChange={(e) => setCostoTaxi(e.target.value)} required={usaTaxi} />
                  <Campo etiqueta="Veces por semana" type="number" min={0} max={7} value={frecuenciaTaxi}
                    onChange={(e) => setFrecuenciaTaxi(e.target.value)} required={usaTaxi} />
                </div>
              )}

              <p className="mb-4 rounded-lg bg-sand/40 px-3 py-2 text-xs text-taupe">
                Al firmar, tomas conocimiento de que CAYLA te otorga una asignación de S/{" "}
                {declaracion!.ruta_tarifa_vigente !== null ? Number(declaracion!.ruta_tarifa_vigente).toFixed(2) : "—"}{" "}
                por día efectivamente asistido, que no corresponde en caso de inasistencia, licencia o descanso, y
                que este concepto no tiene carácter remunerativo (art. 19 inciso e del D.S. N.º 001-97-TR).
                Declaras que la información consignada es veraz y te comprometes a informar a CAYLA si cambias de
                domicilio o de ruta habitual.
              </p>

              <div className="mb-4 border-t border-sand pt-4">
                <h3 className="mb-1 font-serif text-base">Tu firma</h3>
                {yo && (
                  <FirmaEditor
                    supabase={supabase}
                    nombreOficial={yo.nombreOficial}
                    avisar={(tipo, texto) => setAvisoFirma({ tipo, texto })}
                    onGuardada={setMiFirma}
                  />
                )}
              </div>

              <div className="flex items-center gap-3">
                <Boton type="submit" variante="primario" cargando={firmando} disabled={!miFirma}>
                  Firmar mi declaración
                </Boton>
                {declaracion!.estado === "ok" && (
                  <Boton variante="secundario" onClick={() => setFormAbierto(false)}>Cancelar</Boton>
                )}
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

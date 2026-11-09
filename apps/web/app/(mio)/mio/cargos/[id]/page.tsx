"use client";

// Tus cargos, tal como te los comunicaron en tu Info (RIT 55.2, 0581).
//
// Es lo que la colaboradora recibe ANTES de que se decida una amonestación o una
// suspensión. Desde el 2026-11-03 llega por el sistema y no en papel («no
// usaremos hojas o imprimir, tiene que verlo en su sistema», Felipe).
//
// LO ÚNICO QUE SE LE PIDE ES CONFIRMAR QUE LOS RECIBIÓ (Felipe: «solo confirmar
// que lo recibió»). Abrir esta pantalla deja la apertura registrada —la hace
// `fn_cargos_detalle`—, y «Confirmo que los recibí» exige esa apertura. Confirmar
// no es aceptar, y no mueve el plazo: el plazo corre desde que se le comunicaron.
//
// EL DESCARGO ES SUYO Y OPCIONAL. Lo escribe aquí mientras corre el plazo; lo
// que envía no se edita ni se borra (si quiere agregar algo, envía otro), y
// quien decide lo lee antes de valorar. Por eso se envía con una segunda
// confirmación: es un escrito de defensa con efecto, no un borrador.

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { EnlaceVolver } from "@/components/enlace-volver";
import { Cargando } from "@/components/cargando";
import { ComunicacionCargos, type CargosDetalle } from "@/components/disciplina/comunicacion-cargos";
import { fechaLarga, horaLima } from "@/components/disciplina/memo-documento";
import { useToast } from "@/components/toast";
import { AreaTexto } from "@/components/ui/area-texto";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Boton } from "@/components/ui/boton";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { AREAS_FALLBACK, parseAreas, type Area } from "@/lib/areas";

const MINIMO = 10;
const MAXIMO = 4000;

export default function MisCargosPage() {
  const params = useParams();
  const id = (params?.id as string) ?? "";
  const router = useRouter();
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const { avisar } = useToast();

  const [doc, setDoc] = useState<CargosDetalle | null>(null);
  const [areas, setAreas] = useState<Area[]>(AREAS_FALLBACK);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [recibiendo, setRecibiendo] = useState(false);
  const [texto, setTexto] = useState("");
  const [confirmandoEnvio, setConfirmandoEnvio] = useState(false);
  const [enviando, setEnviando] = useState(false);

  const cargar = useCallback(async () => {
    setCargando(true);
    setError(null);
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/mio"); return; }
    const [{ data: d, error: eD }, { data: ar, error: eAr }] = await Promise.all([
      supabase.rpc("fn_cargos_detalle", { p_id: id }),
      supabase.rpc("fn_areas"),
    ]);
    setAreas(parseAreas(ar, eAr));
    if (eD) { setError(mensajeDeError(eD, "abrir los cargos")); setCargando(false); return; }
    setDoc((d as unknown as CargosDetalle | null) ?? null);
    setCargando(false);
  }, [supabase, router, id]);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargar(); }, [cargar]);

  async function recibir() {
    setRecibiendo(true);
    const { error: e } = await supabase.rpc("fn_recibir_cargos", { p_id: id });
    setRecibiendo(false);
    if (e) { avisar("error", mensajeDeError(e, "confirmar que los recibiste")); await cargar(); return; }
    avisar("ok", "Quedó anotado que los recibiste.");
    await cargar();
  }

  async function enviarDescargo() {
    setEnviando(true);
    const { error: e } = await supabase.rpc("fn_presentar_descargo", { p_id: id, p_texto: texto });
    setEnviando(false);
    setConfirmandoEnvio(false);
    if (e) { avisar("error", mensajeDeError(e, "enviar tu descargo")); await cargar(); return; }
    setTexto("");
    avisar("ok", "Tu descargo se envió. Se va a leer antes de decidir.");
    await cargar();
  }

  if (cargando) return <main className="p-6"><Cargando /></main>;

  if (error || !doc) {
    return (
      <main className="p-6">
        <p className="max-w-md rounded-lg bg-sand/40 px-4 py-3 text-sm text-taupe">
          {error ?? "No se encontraron estos cargos. Si crees que deberías verlos, avisa a tu líder de equipo o a Desarrollo Organizacional."}
        </p>
        <EnlaceVolver href="/mio" className="mt-3 inline-block text-sm text-taupe hover:text-tinta hover:underline">
          ← Volver a Info
        </EnlaceVolver>
      </main>
    );
  }

  const recibido = doc.recepcion?.recibido_at ?? null;
  const enCurso = doc.estado === "borrador";
  const puedeEscribir = Boolean(recibido) && enCurso && doc.plazo_vigente;
  const largo = texto.trim().length;
  const textoValido = largo >= MINIMO && largo <= MAXIMO;

  return (
    <main className="mx-auto w-full min-w-0 max-w-[760px] px-4 py-6 sm:p-6">
      <div className="mb-4">
        <EnlaceVolver href="/mio" className="text-sm text-taupe hover:text-tinta hover:underline">← Volver a Info</EnlaceVolver>
      </div>

      {!recibido ? (
        <BannerAviso variante="advertencia" titulo="Te comunicaron unos cargos" className="mb-4">
          <p className="mb-3">
            Léelos completos aquí abajo y confirma que los recibiste. Confirmar no es aceptar lo que dicen: solo deja
            constancia de que te llegaron. Todavía no se decidió nada.
          </p>
          {doc.descargo_vence_at && doc.plazo_vigente && (
            <p className="mb-3">
              Si quieres dar tu versión, tienes hasta el {fechaLarga(doc.descargo_vence_at)}, a las{" "}
              {horaLima(doc.descargo_vence_at)} h. Después de confirmar, aquí mismo puedes escribir tu descargo.
            </p>
          )}
          <Boton variante="primario" cargando={recibiendo} onClick={() => void recibir()}>Confirmo que los recibí</Boton>
        </BannerAviso>
      ) : (
        <BannerAviso variante="positivo" enLinea className="mb-4">
          Confirmaste que los recibiste el {fechaLarga(recibido)}, a las {horaLima(recibido)} h.
        </BannerAviso>
      )}

      {/* La guía, en el momento en que más se necesita: qué pasa ahora y cómo corre el plazo. */}
      <p className="mb-4 text-sm">
        <Link href="/mio/disciplina/como-funciona#cargos" className="underline underline-offset-2 hover:text-tinta">
          Qué pasa ahora y cómo se cuenta tu plazo →
        </Link>
      </p>

      {recibido && (
        <section className="mb-4 grid gap-3">
          <h1 className="font-serif text-lg">Tu descargo</h1>
          {doc.descargos.map((x) => (
            <blockquote key={x.presentado_at} className="border-l-2 border-sand pl-3 text-sm">
              <p className="whitespace-pre-line text-tinta">{x.texto}</p>
              <p className="text-xs text-taupe">Lo enviaste el {fechaLarga(x.presentado_at)}, a las {horaLima(x.presentado_at)} h.</p>
            </blockquote>
          ))}
          {puedeEscribir ? (
            <div className="grid gap-2">
              <p className="text-sm text-taupe">
                {doc.descargos.length > 0
                  ? "Si quieres agregar algo, escríbelo y envíalo: lo que ya enviaste no cambia."
                  : `Es opcional. Escribe lo que quieras que se tenga en cuenta antes de decidir. Tienes hasta el ${fechaLarga(doc.descargo_vence_at!)}, a las ${horaLima(doc.descargo_vence_at!)} h.`}
              </p>
              <AreaTexto id="mi-descargo" etiqueta="Lo que quieres decir" rows={5} value={texto}
                onChange={(e) => { setTexto(e.target.value); setConfirmandoEnvio(false); }} maxLength={MAXIMO} />
              {!confirmandoEnvio ? (
                <div>
                  <Boton variante="primario" disabled={!textoValido} onClick={() => setConfirmandoEnvio(true)}
                    title={!textoValido ? `Escribe al menos ${MINIMO} letras.` : undefined}>
                    Enviar mi descargo
                  </Boton>
                </div>
              ) : (
                <div className="grid gap-2 rounded-control border border-sand p-3 text-sm">
                  <p>¿Envías tu descargo? Una vez enviado ya no se puede cambiar; si quieres agregar algo, podrás enviar otro.</p>
                  <div className="flex flex-wrap gap-3">
                    <Boton variante="primario" tamano="sm" cargando={enviando} onClick={() => void enviarDescargo()}>Sí, enviarlo</Boton>
                    <Boton variante="secundario" tamano="sm" disabled={enviando} onClick={() => setConfirmandoEnvio(false)}>Volver</Boton>
                  </div>
                </div>
              )}
            </div>
          ) : (
            <p className="text-sm text-taupe">
              {!enCurso
                ? "Estos cargos ya se resolvieron. Lo que se decidió te llega como un documento aparte en tu Info."
                : `El plazo para tu descargo venció el ${doc.descargo_vence_at ? fechaLarga(doc.descargo_vence_at) : "—"}. Si necesitas decir algo, habla con tu líder de equipo o con Desarrollo Organizacional.`}
              {doc.descargos.length === 0 && enCurso && !doc.plazo_vigente ? " No enviaste descargo: eso no se toma como que aceptas los cargos." : ""}
            </p>
          )}
        </section>
      )}

      <ComunicacionCargos doc={doc} areas={areas} />
    </main>
  );
}

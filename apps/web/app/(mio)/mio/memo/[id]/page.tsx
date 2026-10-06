"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { EnlaceVolver } from "@/components/enlace-volver";
import { Cargando } from "@/components/cargando";
import { MemoDocumento, TITULO, fechaLarga, horaLima, type Hecho } from "@/components/disciplina/memo-documento";
import { useToast } from "@/components/toast";
import { Boton } from "@/components/ui/boton";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { AREAS_FALLBACK, parseAreas, type Area } from "@/lib/areas";
import { FirmaEditor } from "@/app/(admin)/admin/personas/[id]/FirmaEditor";

// Tu documento disciplinario, tal como te lo enviaron a tu Info (0486).
//
// Es LA pantalla donde una persona que vive en otra ciudad recibe un memo, así
// que hace tres cosas que ninguna otra hace juntas: te lo muestra completo (el
// mismo papel que se imprimiría), te deja recibirlo, y te deja guardar una copia.
//
// RECIBIR ES UN ACTO EXPLÍCITO Y ES LA ENTREGA. Abrir esta pantalla no entrega
// nada —puedes leerlo y cerrar—; solo «Firmar y recibir» o «Recibir sin firmar»
// lo entregan, y las dos dejan tu respuesta guardada en el mismo instante. Por
// eso cada una pide una segunda confirmación: un clic de más aquí tiene efecto
// legal, y el error de un clic no es tuyo, es de cómo se diseñó la pantalla.
//
// TODO SALE DE `fn_mi_memo`, no de leer las tablas: esa función es la que nombra
// a quien firmó (tu RLS no te deja leer su ficha, y un papel que dijera que lo
// firmó «Gerencia General» cuando lo firmó tu líder de equipo sería falso) y la
// que garantiza, del lado del servidor, que nunca veas un borrador ni uno que
// nadie te envió.

interface MemoDigital {
  id: string; correlativo: string | null; tipo_causal: string; nivel: string; estado: string;
  periodo_desde: string | null; periodo_hasta: string | null; hechos: Hecho[];
  suspension_dias: number | null; suspension_desde: string | null; suspension_hasta: string | null;
  suspension_fechas: string[] | null;
  firmado_at: string | null; creado_at: string;
  entregado_at: string | null; medio_entrega: string | null; enviado_a_info_at: string | null;
  firma_sancionado: string | null;
  firma_sancionado_confirmada_at: string | null;
  sancionado_rechazo_firma_at: string | null;
  persona: { nombres: string; apellidos: string; documento: string | null; funcion: string; sede_codigo: string | null };
  /** Conducta: la falta citada y cuándo se supo (los trae `fn_mi_memo` desde la 0514). */
  falta?: { numeral: string; literal: string; texto: string; gravedad: string } | null;
  conocido_el?: string | null;
  firmante: { nombre: string; cargo: string | null } | null;
  firma_emisor: string | null;
}

function MiMemoContenido() {
  const params = useParams();
  const id = (params?.id as string) ?? "";
  const router = useRouter();
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const { avisar } = useToast();

  const [memo, setMemo] = useState<MemoDigital | null>(null);
  const [areas, setAreas] = useState<Area[]>(AREAS_FALLBACK);
  const [miFirma, setMiFirma] = useState<string | null>(null);
  const [nombreOficial, setNombreOficial] = useState("");
  // El editor de firma ocupa media pantalla y quien solo quiere recibir sin firmar no lo
  // necesita: arranca plegado y se abre a pedido, para que el documento quede a la vista.
  const [editandoFirma, setEditandoFirma] = useState(false);
  // Qué confirmación está pendiente. Ninguna de las dos entrega hasta el segundo clic.
  const [paso, setPaso] = useState<null | "firmar" | "sin_firmar">(null);
  const [enviando, setEnviando] = useState(false);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const cargar = useCallback(async () => {
    setCargando(true);
    setError(null);
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/mio"); return; }

    const [{ data: m, error: eM }, { data: ar, error: eAr }, { data: mf }, { data: u }] = await Promise.all([
      supabase.rpc("fn_mi_memo", { p_id: id }),
      supabase.rpc("fn_areas"),
      supabase.rpc("fn_mi_firma"),
      supabase.auth.getUser(),
    ]);
    if (eM) { setError(mensajeDeError(eM, "abrir el documento")); setCargando(false); return; }
    // null = no existe, no es tuyo, o todavía no te lo enviaron: la base no distingue, ni esta pantalla.
    setMemo((m as unknown as MemoDigital | null) ?? null);
    setAreas(parseAreas(ar, eAr));
    setMiFirma((mf as string | null) ?? null);

    // `nombre_dni`, no nombres+apellidos: es el que se imprime en la firma
    // tipográfica (ver FirmaEditor) y sale del DNI, no de cómo se escribió la ficha.
    const uid = u.user?.id;
    if (uid) {
      const { data: p } = await supabase.from("personas").select("id, nombres, apellidos").eq("auth_user_id", uid).maybeSingle();
      if (p) {
        const { data: ficha } = await supabase.from("datos_personales").select("nombre_dni").eq("persona_id", p.id).maybeSingle();
        setNombreOficial((ficha?.nombre_dni as string | null) || `${p.nombres as string} ${p.apellidos as string}`);
      }
    }
    setCargando(false);
  }, [supabase, router, id]);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargar(); }, [cargar]);

  // El nombre con el que se guarda el PDF: con el correlativo delante, para que
  // quien guarde varios los tenga en orden y sepa cuál es cuál.
  useTituloDocumento(
    memo
      ? [memo.correlativo, TITULO[memo.nivel] ?? "Documento disciplinario", `${memo.persona.nombres} ${memo.persona.apellidos}`]
          .filter(Boolean).join(" — ")
      : null,
  );

  async function recibir(firmar: boolean) {
    if (!memo) return;
    setEnviando(true);
    const { error: e } = await supabase.rpc("fn_recibir_memo_digital", { p_id: memo.id, p_firmar: firmar });
    setEnviando(false);
    if (e) {
      // Lo que puede haber pasado mientras leías: quien lo emitió lo retiró, o
      // ya lo habías recibido desde otra pestaña. Se recarga para que la
      // pantalla diga la verdad en vez de seguir ofreciendo el botón.
      avisar("error", mensajeDeError(e, "recibir el documento"));
      setPaso(null);
      await cargar();
      return;
    }
    setPaso(null);
    avisar("ok", firmar
      ? "Firmaste y recibiste el documento."
      : "Recibiste el documento. Quedó anotado que prefieres no firmarlo digitalmente.");
    await cargar();
  }

  if (cargando) return <main className="p-6"><Cargando /></main>;

  if (error || !memo) {
    return (
      <main className="p-6">
        <p className="max-w-md rounded-lg bg-sand/40 px-4 py-3 text-sm text-taupe">
          {error ?? "No se encontró este documento. Si crees que deberías verlo, avisa a tu líder de equipo o a Desarrollo Organizacional."}
        </p>
        <EnlaceVolver href="/mio" className="mt-3 inline-block text-sm text-taupe hover:text-tinta hover:underline">
          ← Volver a Info
        </EnlaceVolver>
      </main>
    );
  }

  const porRecibir = memo.estado === "firmado";
  const entregado = memo.estado === "entregado";

  return (
    <main className="mx-auto max-w-[760px] p-6 print:p-0">
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3 print:hidden">
        <EnlaceVolver href="/mio" className="text-sm text-taupe hover:text-tinta hover:underline">← Volver a Info</EnlaceVolver>
        <Boton variante="secundario" tamano="sm" onClick={() => window.print()}>
          Guardar una copia (PDF) o imprimir
        </Boton>
      </div>

      {porRecibir && (
        <section className="mb-4 rounded-lg border border-ambar/40 bg-ambar/[0.07] p-4 print:hidden">
          <h1 className="mb-1 font-serif text-lg">Este documento te está esperando</h1>
          <p className="mb-3 text-sm text-taupe">
            Léelo completo aquí abajo. Cuando confirmes, queda anotado que lo recibiste en ese momento y desde
            entonces cuenta como entregado. Recibirlo no es aceptar lo que dice: puedes firmarlo y presentar tu
            descargo, o recibirlo sin firmar.
          </p>

          {paso === null ? (
            <div className="flex flex-wrap items-center gap-3">
              <Boton variante="primario" disabled={!miFirma} onClick={() => setPaso("firmar")}>Firmar y recibir</Boton>
              <Boton variante="secundario" onClick={() => setPaso("sin_firmar")}>Recibir sin firmar</Boton>
            </div>
          ) : (
            <div className="rounded-lg border border-sand bg-papel p-3 text-sm">
              <p className="mb-3">
                {paso === "firmar"
                  ? "¿Confirmas que recibiste este documento y lo firmas con tu firma guardada?"
                  : "¿Confirmas que recibiste este documento y que prefieres no firmarlo digitalmente?"}
              </p>
              <div className="flex flex-wrap items-center gap-3">
                <Boton variante="primario" tamano="sm" cargando={enviando} onClick={() => void recibir(paso === "firmar")}>
                  Sí, confirmo
                </Boton>
                <Boton variante="secundario" tamano="sm" disabled={enviando} onClick={() => setPaso(null)}>Volver</Boton>
              </div>
            </div>
          )}

          {/* La firma: sin ella «Firmar y recibir» no se puede, y quien no la
              tiene no debería tener que salir de aquí a buscarla. Plegada hasta
              que la pida: el editor entero antes del documento le tapaba lo que
              vino a leer. */}
          <div className="mt-4 border-t border-ambar/25 pt-3">
            {!editandoFirma ? (
              <div className="flex flex-wrap items-center gap-3 text-xs text-taupe">
                {miFirma ? (
                  <>
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={miFirma} alt="Tu firma guardada" className="h-10 w-auto max-w-[140px]" />
                    <span>Esta es la firma que se usaría.</span>
                  </>
                ) : (
                  <span>Para «Firmar y recibir» necesitas tener tu firma guardada. Si prefieres no firmar, puedes recibirlo sin ella.</span>
                )}
                <button type="button" onClick={() => setEditandoFirma(true)} className="underline hover:text-tinta">
                  {miFirma ? "Cambiar mi firma" : "Crear mi firma"}
                </button>
              </div>
            ) : (
              <>
                <FirmaEditor
                  supabase={supabase}
                  nombreOficial={nombreOficial}
                  avisar={avisar}
                  onGuardada={(f) => { setMiFirma(f); setEditandoFirma(false); }}
                />
                <button type="button" onClick={() => setEditandoFirma(false)} className="mt-2 text-xs text-taupe underline hover:text-tinta">
                  Cerrar sin cambiar
                </button>
              </>
            )}
          </div>
        </section>
      )}

      {entregado && (
        <section className="mb-4 rounded-lg border border-verde/40 bg-verde/[0.07] p-4 text-sm print:hidden">
          <p className="font-medium text-verde">
            {memo.entregado_at
              ? `${memo.medio_entrega === "digital" ? "Lo recibiste desde tu Info" : "Te lo entregaron"} el ${fechaLarga(memo.entregado_at)}, ${horaLima(memo.entregado_at)} h.`
              : "Este documento ya está entregado."}
          </p>
          {memo.firma_sancionado_confirmada_at && (
            <p className="mt-1 text-taupe">Lo firmaste digitalmente el {fechaLarga(memo.firma_sancionado_confirmada_at)}.</p>
          )}
          {memo.sancionado_rechazo_firma_at && (
            <p className="mt-1 text-taupe">
              Quedó anotado que prefieres no firmarlo digitalmente (el {fechaLarga(memo.sancionado_rechazo_firma_at)}).
            </p>
          )}
          <p className="mt-1 text-taupe">Si quieres conservarlo, usa «Guardar una copia (PDF)» arriba.</p>
        </section>
      )}

      <MemoDocumento
        doc={{
          correlativo: memo.correlativo, tipo_causal: memo.tipo_causal, nivel: memo.nivel, estado: memo.estado,
          periodo_desde: memo.periodo_desde, hechos: memo.hechos ?? [],
          suspension_dias: memo.suspension_dias, suspension_desde: memo.suspension_desde,
          suspension_hasta: memo.suspension_hasta, suspension_fechas: memo.suspension_fechas,
          firmado_at: memo.firmado_at, creado_at: memo.creado_at,
          falta: memo.falta ?? null, conocido_el: memo.conocido_el ?? null,
        }}
        persona={memo.persona}
        sede={memo.persona.sede_codigo ?? ""}
        areas={areas}
        firmante={memo.firmante?.nombre ?? null}
        cargoFirmante={memo.firmante?.cargo ?? null}
        firmaUrl={memo.firma_emisor}
        previas={[]}
        recepcion={memo.medio_entrega === "digital" && memo.entregado_at
          ? { at: memo.entregado_at, firma: memo.firma_sancionado }
          : null}
      />
    </main>
  );
}

export default function MiMemoPage() {
  return <MiMemoContenido />;
}

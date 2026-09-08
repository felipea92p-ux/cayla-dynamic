"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { Cargando } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { abrirArchivoFirmado } from "@/lib/abrir-archivo-firmado";
import { MARCADOR_FIRMA_EMPRESA, MARCADOR_FIRMA_PERSONA } from "@/lib/admin/contrato-texto";
import { FirmaEditor } from "@/app/(admin)/admin/personas/[id]/FirmaEditor";

// Tu contrato, en autoservicio — mismo criterio que /mio/boleta: siempre el
// propio (`auth_user_id` de la sesión, nunca un id que viaje en la URL), y el
// documento congelado que ya se generó, no uno recalculado con los datos de
// hoy — el sueldo o el cargo pueden haber cambiado desde que se firmó.
//
// `contratos_lectura` (0272) ya deja a cada persona leer sus propias filas de
// `contratos_generados`, así que esta pantalla consulta la tabla directo, sin
// necesitar una función nueva.
//
// EL DESEMPATE («cuál es el vigente» si hay más de uno) copia el de
// `fn_contrato_firmado_vigente_de` (0312): esa función no está concedida a
// `authenticated` a propósito (es SECURITY DEFINER y devolvería la fila de
// CUALQUIER persona), así que acá se repite el mismo criterio —nunca uno
// inventado— contra la propia fila, que la RLS ya deja ver.
//
// LAS DOS FIRMAS SE ESTAMPAN AL MOSTRAR, NUNCA AL GUARDAR — igual que en
// admin/contratos: `documento_html` congela el texto PACTADO, no cómo se ve.
// La de la empresa (0397, `fn_firma_empresa`) ya no depende de que quien mire
// SEA la firmante: es la del cargo, no la de la sesión, así que puede
// mostrarse aquí, donde quien mira es la propia colaboradora. La suya propia
// (`fn_mi_firma`, sin cambios) sale de la misma tabla y función que ya usa el
// editor de admin/personas/[id] — 0397 solo le abrió el guardado a cualquier
// persona, no solo a admin/líder.
function MiContratoContenido() {
  const router = useRouter();
  const supabase = createAdminSupabaseClient();

  const [yo, setYo] = useState<{ id: string; nombre: string; nombreOficial: string } | null>(null);
  const [contrato, setContrato] = useState<{
    id: string;
    tipo: string;
    fecha_inicio: string;
    fecha_fin: string | null;
    fecha_firma: string | null;
    storage_path: string | null;
    documento_html: string | null;
    // Confirmación DIGITAL (0402) de que la firma de abajo va en este
    // contrato — distinta de `fecha_firma`, que sigue siendo el escaneado
    // físico. Se congela al confirmar: si después cambias tu firma general,
    // este contrato sigue mostrando la que confirmaste hasta que vuelvas a
    // confirmar.
    firma_persona_confirmada_at: string | null;
  } | null>(null);
  const [miFirma, setMiFirma] = useState<string | null>(null);
  const [firmaEmpresa, setFirmaEmpresa] = useState<string | null>(null);
  const [avisoFirma, setAvisoFirma] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  const [confirmando, setConfirmando] = useState(false);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);

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
    // `nombre_dni`, no `nombres`+`apellidos`: es el nombre que se imprime en el
    // contrato y en la firma tipográfica (ver FirmaEditor), y sale del DNI, no
    // de cómo se escribió la ficha.
    const { data: ficha } = await supabase
      .from("datos_personales").select("nombre_dni").eq("persona_id", p.id).maybeSingle();
    const nombre = `${p.nombres as string} ${p.apellidos as string}`;
    const yoActual = { id: p.id as string, nombre, nombreOficial: (ficha?.nombre_dni as string | null) || nombre };
    setYo(yoActual);

    const [{ data: c, error: eContrato }, { data: mf }, { data: fe }] = await Promise.all([
      supabase
        .from("contratos_generados")
        .select("id, tipo, fecha_inicio, fecha_fin, fecha_firma, storage_path, documento_html, firma_persona_confirmada_at")
        .eq("persona_id", yoActual.id)
        .is("anulado_at", null)
        .order("generado_at", { ascending: false })
        .order("fecha_inicio", { ascending: false })
        .order("fecha_fin", { ascending: false })
        .order("id", { ascending: false })
        .limit(1)
        .maybeSingle(),
      supabase.rpc("fn_mi_firma"),
      supabase.rpc("fn_firma_empresa"),
    ]);
    setCargando(false);
    if (eContrato) {
      setError(eContrato.message);
      return;
    }
    setContrato(c as typeof contrato);
    setMiFirma((mf as string | null) ?? null);
    setFirmaEmpresa((fe as string | null) ?? null);
  }, [supabase, router]);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargar(); }, [cargar]);

  useTituloDocumento(yo && contrato ? `${yo.nombre} — Contrato` : null);

  async function verEscaneado() {
    if (!contrato?.storage_path) return;
    const fallo = await abrirArchivoFirmado(supabase, "contratos", contrato.storage_path);
    if (fallo) setError(fallo);
  }

  // Paso aparte de "Guardar firma" (que solo configura la imagen, reusable en
  // cualquier documento): esto congela una copia de esa imagen EN ESTE
  // contrato y deja constancia de cuándo, visible para admin/líder tanto en
  // la lista de contratos como al abrir este documento (ver admin/contratos).
  async function confirmarFirma() {
    if (!contrato) return;
    setConfirmando(true);
    const { error: eConfirmar } = await supabase.rpc("fn_confirmar_mi_firma_contrato", { p_contrato_id: contrato.id });
    if (eConfirmar) {
      setAvisoFirma({ tipo: "error", texto: eConfirmar.message });
    } else {
      setContrato((c) => (c ? { ...c, firma_persona_confirmada_at: new Date().toISOString() } : c));
      setAvisoFirma({ tipo: "ok", texto: "Firma confirmada en este contrato." });
    }
    setConfirmando(false);
  }

  if (cargando) {
    return (
      <main className="p-6">
        <Cargando />
      </main>
    );
  }

  if (error) {
    return (
      <main className="p-6">
        <p className="max-w-md rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
          {error}{" "}
          <Boton variante="enlace" onClick={() => void cargar()}>
            Reintentar
          </Boton>
        </p>
        <Link href="/mio" className="mt-3 inline-block text-sm text-taupe hover:text-tinta hover:underline">
          ← Volver a Mi perfil
        </Link>
      </main>
    );
  }

  if (!yo || !contrato || !contrato.documento_html) {
    return (
      <main className="p-6">
        <p className="max-w-md rounded-lg bg-sand/40 px-4 py-3 text-sm text-taupe">
          Todavía no tienes un contrato registrado en el sistema. Si crees que deberías tener uno, avisa a
          Desarrollo Organizacional.
        </p>
        <Link href="/mio" className="mt-3 inline-block text-sm text-taupe hover:text-tinta hover:underline">
          ← Volver a Mi perfil
        </Link>
      </main>
    );
  }

  const html = contrato.documento_html
    .replaceAll(MARCADOR_FIRMA_EMPRESA, firmaEmpresa ? `<img src="${firmaEmpresa}" alt="Firma de la empresa" />` : "&nbsp;")
    .replaceAll(MARCADOR_FIRMA_PERSONA, miFirma ? `<img src="${miFirma}" alt="Tu firma" />` : "&nbsp;");

  return (
    <main className="mx-auto max-w-2xl p-6 print:p-0">
      <div className="mb-6 flex flex-wrap items-center justify-between gap-3 print:hidden">
        <Link href="/mio" className="text-sm text-taupe hover:text-tinta hover:underline">
          ← Volver a Mi perfil
        </Link>
        <div className="flex flex-wrap items-center gap-3">
          {contrato.storage_path && (
            // Nativo a propósito: Boton variante="enlace" no aplica tamaño (solo
            // CHROME, sin TAMANOS), así que quedaría en el cuerpo por defecto —
            // más grande que el "Imprimir" de al lado, con el que hoy alinea en
            // text-sm. Mismo criterio de "no forzar" que ya se aplica en otras
            // pantallas para enlaces cuyo tratamiento no calza en el componente.
            <button onClick={() => void verEscaneado()} className="text-sm text-taupe underline hover:text-tinta">
              Ver el escaneado firmado
            </button>
          )}
          <Boton variante="primario" onClick={() => window.print()}>
            Imprimir / Guardar como PDF
          </Boton>
        </div>
      </div>

      {!contrato.fecha_firma && (
        <p className="mb-4 rounded-lg bg-ambar/[0.08] px-4 py-3 text-sm text-taupe print:hidden">
          Este contrato todavía no ha sido firmado. Lo que ves es el borrador tal como se generó.
        </p>
      )}

      {/* Firmar acá NO reemplaza el escaneado físico — el trámite legal sigue
          siendo el mismo. Es para que la firma que ya generaste (o generes
          ahora) aparezca en el documento que ves y que imprimes, en tu propio
          apartado, en vez de quedar siempre en blanco. */}
      <div className="mb-4 rounded-lg border border-sand bg-papel p-4 print:hidden">
        <h2 className="mb-1 font-serif text-base">Tu firma</h2>
        <p className="mb-3 text-xs text-taupe">
          Aparecerá en tu apartado del contrato de arriba, junto a la de la empresa.
        </p>
        {avisoFirma && (
          <p className={`mb-3 text-xs ${avisoFirma.tipo === "ok" ? "text-verde" : "text-rojo"}`}>{avisoFirma.texto}</p>
        )}
        <FirmaEditor
          supabase={supabase}
          nombreOficial={yo.nombreOficial}
          avisar={(tipo, texto) => setAvisoFirma({ tipo, texto })}
          onGuardada={setMiFirma}
        />

        {/* Aparte de "Guardar firma" de arriba a propósito: guardar la firma
            solo configura la imagen (reusable en cualquier documento futuro);
            esto confirma que ESA imagen va en ESTE contrato puntual, y lo dice
            en admin/contratos — en la lista y al abrir el documento. */}
        <div className="mt-3 border-t border-sand pt-3">
          {contrato.firma_persona_confirmada_at ? (
            <p className="mb-2 text-xs text-verde">
              Confirmaste tu firma en este contrato el{" "}
              {new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "long", year: "numeric" })
                .format(new Date(contrato.firma_persona_confirmada_at))}.
              {" "}Si cambiaste tu firma después, vuelve a confirmar para que se actualice acá.
            </p>
          ) : (
            <p className="mb-2 text-xs text-taupe">Todavía no confirmaste tu firma en este contrato.</p>
          )}
          <button
            onClick={() => void confirmarFirma()}
            disabled={confirmando || !miFirma}
            className="rounded-lg bg-tinta px-3 py-1.5 text-xs font-medium text-crema disabled:opacity-40"
          >
            {confirmando ? "Confirmando…" : "Confirmar mi firma aquí"}
          </button>
        </div>
      </div>

      <div
        className="hoja rounded-lg border border-sand p-8 text-sm leading-relaxed print:rounded-none print:border-0 print:p-0"
        dangerouslySetInnerHTML={{ __html: html }}
      />
    </main>
  );
}

export default function MiContratoPage() {
  return <MiContratoContenido />;
}

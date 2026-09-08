"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { FormEvent } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { EMPRESA } from "@cayla-dynamic/shared";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { Cargando } from "@/components/cargando";
import { abrirArchivoFirmado } from "@/lib/abrir-archivo-firmado";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import { MARCADOR_FIRMA_EMPRESA, MARCADOR_FIRMA_PERSONA } from "@/lib/admin/contrato-texto";
import { FirmaEditor } from "@/app/(admin)/admin/personas/[id]/FirmaEditor";

const TEXTO_CONSENTIMIENTO_DNI =
  `Declaro que el Documento Nacional de Identidad (DNI) que adjunto corresponde a mi persona y autorizo a ` +
  `${EMPRESA.nombre} (RUC ${EMPRESA.ruc}) a tratar este documento y mis demás datos personales con la finalidad ` +
  `de verificar mi identidad y dejar constancia de mi aceptación de los términos del contrato. Estos datos se ` +
  `incorporarán al banco de datos personales de ${EMPRESA.nombre}. Su entrega es necesaria para continuar el ` +
  `proceso; de no autorizarlo, no será posible continuar con la firma del contrato. Puedo ejercer mis derechos ` +
  `de acceso, rectificación, cancelación y oposición escribiendo a info@cayla.pe.`;

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
    tipo: string;
    fecha_inicio: string;
    fecha_fin: string | null;
    fecha_firma: string | null;
    storage_path: string | null;
    documento_html: string | null;
  } | null>(null);
  const [miFirma, setMiFirma] = useState<string | null>(null);
  const [firmaEmpresa, setFirmaEmpresa] = useState<string | null>(null);
  const [avisoFirma, setAvisoFirma] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // ── Consentimiento de DNI (0402) — sin esto no se muestra el editor de firma ─
  const [consentimientoDni, setConsentimientoDni] = useState<{ storagePath: string; aceptadoAt: string } | null>(null);
  const [archivoDni, setArchivoDni] = useState<File | null>(null);
  const [aceptoDni, setAceptoDni] = useState(false);
  const [reemplazandoDni, setReemplazandoDni] = useState(false);
  const [subiendoDni, setSubiendoDni] = useState(false);
  const [errorDni, setErrorDni] = useState<string | null>(null);
  const inputDniRef = useRef<HTMLInputElement>(null);

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

    const [{ data: c, error: eContrato }, { data: mf }, { data: fe }, { data: cd }] = await Promise.all([
      supabase
        .from("contratos_generados")
        .select("tipo, fecha_inicio, fecha_fin, fecha_firma, storage_path, documento_html")
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
      supabase.rpc("fn_mi_consentimiento_dni"),
    ]);
    setCargando(false);
    if (eContrato) {
      setError(eContrato.message);
      return;
    }
    setContrato(c as typeof contrato);
    setMiFirma((mf as string | null) ?? null);
    setFirmaEmpresa((fe as string | null) ?? null);
    const fila = ((cd as { storage_path: string; aceptado_at: string }[] | null) ?? [])[0];
    setConsentimientoDni(fila ? { storagePath: fila.storage_path, aceptadoAt: fila.aceptado_at } : null);
  }, [supabase, router]);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargar(); }, [cargar]);

  useTituloDocumento(yo && contrato ? `${yo.nombre} — Contrato` : null);

  async function verEscaneado() {
    if (!contrato?.storage_path) return;
    const fallo = await abrirArchivoFirmado(supabase, "contratos", contrato.storage_path);
    if (fallo) setError(fallo);
  }

  async function verMiDni() {
    if (!consentimientoDni) return;
    const fallo = await abrirArchivoFirmado(supabase, "dni-consentimiento", consentimientoDni.storagePath);
    if (fallo) setErrorDni(fallo);
  }

  // Requiere el checkbox marcado — es lo que desbloquea el botón, no el archivo
  // por sí solo. Cada subida (también un reemplazo) pide su propio check: el
  // consentimiento anterior no cubre un documento que todavía no se adjuntó.
  async function subirMiDni(e: FormEvent) {
    e.preventDefault();
    if (!yo || !archivoDni || !aceptoDni) return;
    setErrorDni(null);
    setSubiendoDni(true);
    try {
      const ext = archivoDni.name.split(".").pop()?.toLowerCase() || "jpg";
      const ruta = `${yo.id}/${Date.now()}-${Math.round(Math.random() * 1e6)}.${ext}`;
      const fallo = await subirArchivoConProgreso(supabase, "dni-consentimiento", ruta, archivoDni, () => {});
      if (fallo) { setErrorDni(`No se pudo subir tu DNI: ${fallo}`); return; }

      const { error: eRpc } = await supabase.rpc("fn_registrar_mi_dni", { p_storage_path: ruta });
      if (eRpc) { setErrorDni(eRpc.message); return; }

      setConsentimientoDni({ storagePath: ruta, aceptadoAt: new Date().toISOString() });
      setArchivoDni(null);
      setAceptoDni(false);
      setReemplazandoDni(false);
      if (inputDniRef.current) inputDniRef.current.value = "";
    } finally {
      setSubiendoDni(false);
    }
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
          <button onClick={() => void cargar()} className="font-medium underline">
            Reintentar
          </button>
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
            <button onClick={() => void verEscaneado()} className="text-sm text-taupe underline hover:text-tinta">
              Ver el escaneado firmado
            </button>
          )}
          <button
            onClick={() => window.print()}
            className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema hover:bg-rojo-profundo"
          >
            Imprimir / Guardar como PDF
          </button>
        </div>
      </div>

      {!contrato.fecha_firma && (
        <p className="mb-4 rounded-lg bg-ambar/[0.08] px-4 py-3 text-sm text-taupe print:hidden">
          Este contrato todavía no ha sido firmado. Lo que ves es el borrador tal como se generó.
        </p>
      )}

      {/* Verificación de identidad (0402) — Ley N.° 29733: el consentimiento se
          pide AQUÍ, al recolectar el DNI, no solo se menciona en el contrato
          (cláusula DÉCIMA SÉPTIMA). Sin esto marcado y el DNI subido, más abajo
          no aparece el editor de firma: no se puede aceptar el contrato. */}
      <div className="mb-4 rounded-lg border border-sand bg-papel p-4 print:hidden">
        <h2 className="mb-1 font-serif text-base">Verificación de identidad</h2>

        {consentimientoDni && !reemplazandoDni ? (
          <div className="text-sm">
            <p className="text-taupe">
              Subiste tu DNI el{" "}
              {new Date(consentimientoDni.aceptadoAt).toLocaleDateString("es-PE", {
                day: "numeric", month: "long", year: "numeric",
              })}.
            </p>
            <div className="mt-2 flex flex-wrap gap-3">
              <button onClick={() => void verMiDni()} className="text-xs text-taupe underline hover:text-tinta">
                Ver el archivo
              </button>
              <button
                onClick={() => setReemplazandoDni(true)}
                className="text-xs text-taupe underline hover:text-tinta"
              >
                Subir otro
              </button>
            </div>
          </div>
        ) : (
          <form onSubmit={(e) => void subirMiDni(e)}>
            <p className="mb-3 text-xs leading-relaxed text-taupe">{TEXTO_CONSENTIMIENTO_DNI}</p>
            <label className="mb-3 flex items-start gap-2 text-xs text-tinta">
              <input
                type="checkbox"
                checked={aceptoDni}
                onChange={(e) => setAceptoDni(e.target.checked)}
                className="mt-0.5"
                required
              />
              Acepto y autorizo.
            </label>
            <div className="flex flex-wrap items-center gap-3">
              <input
                ref={inputDniRef}
                type="file"
                accept="image/jpeg,image/png,application/pdf"
                onChange={(e) => setArchivoDni(e.target.files?.[0] ?? null)}
                className="text-xs text-taupe"
              />
              <button
                type="submit"
                disabled={!archivoDni || !aceptoDni || subiendoDni}
                className="rounded-lg bg-tinta px-3 py-1.5 text-xs font-medium text-crema hover:bg-rojo-profundo disabled:opacity-40"
              >
                {subiendoDni ? "Subiendo…" : "Subir DNI"}
              </button>
              {consentimientoDni && (
                <button
                  type="button"
                  onClick={() => { setReemplazandoDni(false); setArchivoDni(null); setAceptoDni(false); }}
                  className="text-xs text-taupe underline hover:text-tinta"
                >
                  Cancelar
                </button>
              )}
            </div>
            {errorDni && <p className="mt-2 text-xs text-rojo">{errorDni}</p>}
          </form>
        )}
      </div>

      {/* Firmar acá NO reemplaza el escaneado físico — el trámite legal sigue
          siendo el mismo. Es para que la firma que ya generaste (o generes
          ahora) aparezca en el documento que ves y que imprimes, en tu propio
          apartado, en vez de quedar siempre en blanco. */}
      {consentimientoDni ? (
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
        </div>
      ) : (
        <p className="mb-4 rounded-lg bg-sand/40 px-4 py-3 text-sm text-taupe print:hidden">
          Sube tu DNI y acepta el tratamiento de tus datos personales para poder firmar tu contrato.
        </p>
      )}

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

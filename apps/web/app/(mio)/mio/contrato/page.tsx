"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { Cargando } from "@/components/cargando";
import { abrirArchivoFirmado } from "@/lib/abrir-archivo-firmado";
import { MARCADOR_FIRMA_EMPRESA } from "@/lib/admin/contrato-texto";

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
// LA FIRMA DE LA EMPRESA NO SE ESTAMPA ACÁ. El marcador solo se reemplaza por
// la imagen cuando quien mira ES la firmante configurada (`fn_mi_firma`, ver
// admin/contratos) — nadie más debería poder estampar esa firma, y esta
// pantalla la abre la propia colaboradora, no la firmante.
function MiContratoContenido() {
  const router = useRouter();
  const supabase = createAdminSupabaseClient();

  const [yo, setYo] = useState<{ id: string; nombre: string } | null>(null);
  const [contrato, setContrato] = useState<{
    tipo: string;
    fecha_inicio: string;
    fecha_fin: string | null;
    fecha_firma: string | null;
    storage_path: string | null;
    documento_html: string | null;
  } | null>(null);
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
      .from("personas")
      .select("id, nombres, apellidos")
      .eq("auth_user_id", uid)
      .maybeSingle();
    if (!p) {
      setCargando(false);
      setError("Tu cuenta todavía no está enlazada con tu ficha. Avisa a Desarrollo Organizacional.");
      return;
    }
    const yoActual = { id: p.id as string, nombre: `${p.nombres as string} ${p.apellidos as string}` };
    setYo(yoActual);

    const { data: c, error: eContrato } = await supabase
      .from("contratos_generados")
      .select("tipo, fecha_inicio, fecha_fin, fecha_firma, storage_path, documento_html")
      .eq("persona_id", yoActual.id)
      .is("anulado_at", null)
      .order("generado_at", { ascending: false })
      .order("fecha_inicio", { ascending: false })
      .order("fecha_fin", { ascending: false })
      .order("id", { ascending: false })
      .limit(1)
      .maybeSingle();
    setCargando(false);
    if (eContrato) {
      setError(eContrato.message);
      return;
    }
    setContrato(c as typeof contrato);
  }, [supabase, router]);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargar(); }, [cargar]);

  useTituloDocumento(yo && contrato ? `${yo.nombre} — Contrato` : null);

  async function verEscaneado() {
    if (!contrato?.storage_path) return;
    const fallo = await abrirArchivoFirmado(supabase, "contratos", contrato.storage_path);
    if (fallo) setError(fallo);
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

  const html = contrato.documento_html.replaceAll(MARCADOR_FIRMA_EMPRESA, "&nbsp;");

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

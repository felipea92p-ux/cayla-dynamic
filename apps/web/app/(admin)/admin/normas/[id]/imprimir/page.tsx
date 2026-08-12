"use client";

import { useCallback, useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Cargando } from "@/components/cargando";
import { Documento } from "@/components/documento";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { mensajeDeError } from "@/lib/admin/mensaje-error";

// La hoja de un documento institucional, para imprimirla.
//
// POR QUÉ NO SE GUARDA UN PDF AL LADO DEL TEXTO. Porque serían dos verdades
// sobre el mismo documento: el día que se corrija una coma, el texto cambia y
// el PDF sigue diciendo lo anterior, sin que nadie se entere. Es el problema
// del que veníamos huyendo al sacar el reglamento de Drive.
//
// Acá la hoja se compone del MISMO texto guardado que se lee en pantalla y que
// cada integrante acusa. No pueden desincronizarse porque no hay dos.
//
// PARA QUÉ SIRVE DE VERDAD. El cargo de recepción es un formulario: se imprime
// en blanco, se firma a mano y se escanea de vuelta. Sin esta página, cada
// encargada dependía de que alguien le reenviara un archivo por WhatsApp —y de
// que fuera el archivo bueno.

const EMPRESA = { nombre: "CAYLA S.A.C.", ruc: "20605964550" };

interface Doc {
  id: string;
  version: number;
  titulo: string;
  documento: string;
  vigente_desde: string;
  tipo: string;
}

function fechaLarga(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", {
    day: "2-digit", month: "long", year: "numeric", timeZone: "UTC",
  }).format(new Date(Date.UTC(y, m - 1, d)));
}

export default function ImprimirDocumentoPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const [doc, setDoc] = useState<Doc | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [cargando, setCargando] = useState(true);

  useTituloDocumento(doc?.titulo ?? "Imprimir");

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    const { data, error: e } = await supabase
      .from("documentos_institucionales")
      .select("id, version, titulo, documento, vigente_desde, tipo")
      .eq("id", id)
      .maybeSingle();
    setCargando(false);
    if (e) { setError(mensajeDeError(e, "abrir el documento")); return; }
    if (!data) { setError("Ese documento no existe o ya no está disponible."); return; }
    setDoc(data as Doc);
  }, [id, router]);

  useEffect(() => { void cargar(); }, [cargar]);

  if (cargando) return <Cargando texto="Preparando la hoja…" />;

  if (error || !doc) {
    return (
      <main className="mx-auto max-w-2xl p-6">
        <p className="rounded-2xl border border-sand bg-papel px-4 py-6 text-sm text-taupe">
          {error ?? "No se pudo abrir el documento."}
        </p>
        <button onClick={() => router.push("/admin/normas")}
          className="mt-3 rounded-lg border border-tinta/30 px-3 py-1.5 text-xs text-tinta">
          Volver a Normas
        </button>
      </main>
    );
  }

  return (
    <main className="mx-auto max-w-3xl p-6 print:max-w-none print:p-0">
      {/* La barra desaparece al imprimir: no forma parte del documento. */}
      <div className="mb-5 flex flex-wrap items-center gap-2 print:hidden">
        <button onClick={() => window.print()}
          className="rounded-lg bg-tinta px-3 py-1.5 text-xs font-medium text-crema">
          Imprimir
        </button>
        <button onClick={() => router.push("/admin/normas")}
          className="rounded-lg border border-tinta/30 px-3 py-1.5 text-xs text-tinta">
          Volver
        </button>
        <p className="text-xs text-taupe">
          Para guardarlo como PDF, elige «Guardar como PDF» en el destino de impresión.
        </p>
      </div>

      {/* La cabecera SÍ se imprime, y en cada hoja no: va una vez, arriba. Lleva
          la versión y la fecha de vigencia porque un papel sin versión no dice
          cuál de los textos es — que es justo lo que este sistema arregla. */}
      <header className="mb-6 border-b border-sand pb-4">
        <p className="font-serif text-[11px] uppercase tracking-[0.2em] text-taupe">
          {EMPRESA.nombre} · RUC N.° {EMPRESA.ruc}
        </p>
        <h1 className="mt-2 font-serif text-2xl text-tinta">{doc.titulo}</h1>
        <p className="mt-1 text-xs text-taupe">
          Versión {doc.version} · vigente desde el {fechaLarga(doc.vigente_desde)}
        </p>
      </header>

      <Documento texto={doc.documento} />
    </main>
  );
}

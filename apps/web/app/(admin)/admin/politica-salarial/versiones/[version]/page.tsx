"use client";

import { useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { TZ_LIMA } from "@cayla-dynamic/shared";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { Cargando } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { documentoDesdeGuardado } from "@/lib/politica-salarial";
import { DocumentoVista } from "../../_documento-vista";

// Vista de UNA versión, vigente o histórica — es la prueba tal como se
// congeló (0141), sin los widgets interactivos de "Documento vigente": una
// versión ya publicada no se navega, se archiva.

function fechaLarga(iso: string): string {
  return new Intl.DateTimeFormat("es-PE", { day: "numeric", month: "long", year: "numeric", timeZone: TZ_LIMA }).format(new Date(iso));
}

export default function VersionHistoricaPage() {
  const params = useParams();
  const version = (params?.version as string) ?? "";
  const router = useRouter();
  const persona = usePersonaActual();
  useTituloDocumento(`Versión ${version} · Política salarial`);

  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [fila, setFila] = useState<{ version: number; documento: string; publicada_at: string; notas: string | null } | null>(null);
  const [esVigente, setEsVigente] = useState(false);
  const [firmaUrl, setFirmaUrl] = useState<string | null>(null);

  useEffect(() => {
    if (persona === null) return;
    (async () => {
      const supabase = createAdminSupabaseClient();
      const [r, ultima, f] = await Promise.all([
        supabase.from("politica_salarial").select("version, documento, publicada_at, notas").eq("version", Number(version)).maybeSingle(),
        supabase.from("politica_salarial").select("version").order("version", { ascending: false }).limit(1).maybeSingle(),
        supabase.rpc("fn_mi_firma"),
      ]);
      if (r.error !== null) { setError(mensajeDeError(r.error, "cargar esta versión")); setCargando(false); return; }
      if (!r.data) { setError(`No existe la versión ${version}.`); setCargando(false); return; }
      setFila(r.data as typeof fila);
      setEsVigente(ultima.data?.version === Number(version));
      setFirmaUrl(typeof f.data === "string" && f.data.startsWith("data:image") ? f.data : null);
      setCargando(false);
    })();
  }, [persona, version]);

  if (cargando) return <Cargando />;

  if (error !== null || fila === null) {
    return (
      <main className="mx-auto max-w-2xl px-4 py-8">
        <p className="rounded-superficie border border-sand bg-papel px-4 py-6 text-sm text-taupe">{error}</p>
        <Boton variante="secundario" tamano="sm" className="mt-3" onClick={() => router.push("/admin/politica-salarial/versiones")}>Volver a Versiones</Boton>
      </main>
    );
  }

  const doc = documentoDesdeGuardado(fila.documento);

  return (
    <main className="mx-auto max-w-4xl px-4 py-8 print:max-w-none print:p-0">
      <div className="mb-6 flex flex-wrap items-center justify-between gap-3 print:hidden">
        <div className="flex flex-wrap items-center gap-3">
          <h1 className="font-serif text-xl text-tinta">Versión {fila.version}</h1>
          <Insignia variante={esVigente ? "positivo" : "neutral"}>{esVigente ? "Vigente" : "Histórica"}</Insignia>
          <span className="text-sm text-taupe">publicada el {fechaLarga(fila.publicada_at)}</span>
        </div>
        <div className="flex gap-2">
          <Boton variante="secundario" tamano="sm" onClick={() => window.print()}>Descargar PDF</Boton>
          <Boton variante="sutil" tamano="sm" onClick={() => router.push("/admin/politica-salarial/versiones")}>Volver</Boton>
        </div>
      </div>
      {fila.notas && <p className="mb-4 text-sm text-taupe print:hidden">Notas: {fila.notas}</p>}

      {doc ? (
        <DocumentoVista doc={doc} firmaUrl={firmaUrl} />
      ) : (
        <article className="rounded-superficie border border-sand bg-papel p-6">
          <pre className="whitespace-pre-wrap font-sans text-sm leading-relaxed text-tinta">{fila.documento}</pre>
        </article>
      )}
    </main>
  );
}

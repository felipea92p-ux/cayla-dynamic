"use client";

import { useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { TZ_LIMA, puedeEstamparFirmaDeEmpresa } from "@cayla-dynamic/shared";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { Cargando } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { EstadoVacio } from "@/components/ui/estado-vacio";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { sobretituloDeHoy } from "@/lib/admin/sobretitulo";
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
  const [fila, setFila] = useState<{
    version: number; documento: string; publicada_at: string; notas: string | null; firma_empresa: string | null;
  } | null>(null);
  const [esVigente, setEsVigente] = useState(false);

  useEffect(() => {
    if (persona === null) return;
    (async () => {
      const supabase = createAdminSupabaseClient();
      // La firma de CAYLA es la que se congeló al publicar ESTA versión (0616),
      // no la de quien abre la página (así era antes de la 0398) ni la de hoy
      // (así era hasta la 0616): una versión histórica tiene que mostrar la de
      // su día. Sin firma congelada —publicada antes de que se pudiera probar
      // cuál era— sale la raya en blanco.
      const [r, ultima] = await Promise.all([
        supabase.from("politica_salarial").select("version, documento, publicada_at, notas, firma_empresa").eq("version", Number(version)).maybeSingle(),
        supabase.from("politica_salarial").select("version").order("version", { ascending: false }).limit(1).maybeSingle(),
      ]);
      if (r.error !== null) { setError(mensajeDeError(r.error, "cargar esta versión")); setCargando(false); return; }
      if (!r.data) { setError(`No existe la versión ${version}.`); setCargando(false); return; }
      setFila(r.data as typeof fila);
      setEsVigente(ultima.data?.version === Number(version));
      setCargando(false);
    })();
  }, [persona, version]);

  if (cargando) return <Cargando />;

  if (error !== null || fila === null) {
    return (
      <main className="mx-auto max-w-2xl px-4 py-8">
        <EstadoVacio>{error ?? "No se encontró esa versión."}</EstadoVacio>
        <Boton variante="secundario" tamano="sm" className="mt-3" onClick={() => router.push("/admin/politica-salarial/versiones")}>Volver a Versiones</Boton>
      </main>
    );
  }

  const doc = documentoDesdeGuardado(fila.documento);

  return (
    <main className="flex-1 p-4 pt-6 sm:p-6 print:max-w-none print:p-0">
      <div className="print:hidden">
        <CabeceraPagina
          sobretitulo={sobretituloDeHoy("Publicaciones")}
          titulo={`Versión ${fila.version}`}
          descripcion={
            <span className="inline-flex flex-wrap items-center gap-2">
              <Insignia variante={esVigente ? "positivo" : "neutral"}>{esVigente ? "Vigente" : "Histórica"}</Insignia>
              publicada el {fechaLarga(fila.publicada_at)}
            </span>
          }
          accion={
            <div className="flex gap-2">
              <Boton variante="secundario" tamano="sm" onClick={() => window.print()}>Descargar PDF</Boton>
              <Boton variante="sutil" tamano="sm" onClick={() => router.push("/admin/politica-salarial/versiones")}>Volver</Boton>
            </div>
          }
        />
      </div>
      {fila.notas && <p className="mb-4 text-sm text-taupe print:hidden">Notas: {fila.notas}</p>}

      {doc ? (
        <DocumentoVista doc={doc} firmaUrl={puedeEstamparFirmaDeEmpresa(persona?.rol) ? fila.firma_empresa : null} />
      ) : (
        <TarjetaInfo como="article" className="p-6 sm:p-6">
          <pre className="whitespace-pre-wrap font-sans text-sm leading-relaxed text-tinta">{fila.documento}</pre>
        </TarjetaInfo>
      )}
    </main>
  );
}

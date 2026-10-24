"use client";

import { useCallback, useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Cargando } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { EstadoVacio } from "@/components/ui/estado-vacio";
import { Documento } from "@/components/documento";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { EMPRESA } from "@cayla-dynamic/shared";

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

interface Doc {
  id: string;
  version: number;
  /** La versión que declara el propio documento. Ver `comoSeLlamaLaVersion` en la
   *  pantalla de Normas: manda esta, y el correlativo dice cuántas veces se ha
   *  publicado. En el papel importa el doble, porque este es el que se firma. */
  etiqueta_version: string | null;
  titulo: string;
  documento: string;
  vigente_desde: string;
  tipo: string;
}

/**
 * ¿El documento trae su propio título en la primera línea?
 *
 * Solo MIRA el texto; no lo modifica ni le quita nada. Se usa para decidir si la
 * cabecera de la hoja tiene que poner un título o si sería el segundo.
 */
function abreConTitulo(texto: string): boolean {
  const primera = texto.split("\n").map((l) => l.trim()).find((l) => l !== "") ?? "";
  return /^#\s+\S/.test(primera);
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
      .select("id, version, etiqueta_version, titulo, documento, vigente_desde, tipo")
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
        <EstadoVacio>
          {error ?? "No se pudo abrir el documento."}
        </EstadoVacio>
        <Boton variante="secundario" tamano="sm" className="mt-3" onClick={() => router.push("/admin/normas")}>
          Volver a Normas
        </Boton>
      </main>
    );
  }

  return (
    <main className="mx-auto max-w-3xl p-6 print:max-w-none print:p-0">
      {/* La barra desaparece al imprimir: no forma parte del documento. */}
      <div className="mb-5 flex flex-wrap items-center gap-2 print:hidden">
        <Boton variante="primario" tamano="sm" onClick={() => window.print()}>
          Imprimir
        </Boton>
        <Boton variante="secundario" tamano="sm" onClick={() => router.push("/admin/normas")}>
          Volver
        </Boton>
        <p className="text-xs text-taupe">
          Para guardarlo como PDF, elige «Guardar como PDF» en el destino de impresión.
        </p>
      </div>

      {/* La cabecera SÍ se imprime, y en cada hoja no: va una vez, arriba. Lleva
          la versión y la fecha de vigencia porque un papel sin versión no dice
          cuál de los textos es — que es justo lo que este sistema arregla.

          Y APORTA SOLO LO QUE EL TEXTO NO PUEDE APORTAR. Los seis documentos
          publicados abren con su propio «# TÍTULO», su razón social y su RUC, así
          que la cabecera imprimía una copia de las tres líneas que se pintan
          justo debajo: dos títulos del mismo tamaño, dos veces el RUC y dos
          versiones seguidas. Peor todavía, el título de la cabecera se DERIVA de
          esa primera línea `# ` al publicar, o sea que era literalmente la misma
          cadena dos veces.

          El título solo se imprime cuando el texto no lo trae — que es el caso de
          un documento PEGADO desde un Word o un Canva, la vía que existe para la
          misión y los valores. Y se comprueba sin tocar el texto: filtrar líneas
          de lo que se pinta haría que el acuse apuntara a un documento con partes
          que nadie vio, y eso es justo lo que le da valor a la constancia. */}
      <header className="mb-6 border-b border-sand pb-4">
        {!abreConTitulo(doc.documento) && (
          <>
            <p className="font-serif text-[11px] uppercase tracking-[0.2em] text-taupe">
              {EMPRESA.nombre} · RUC N.° {EMPRESA.ruc}
            </p>
            <h1 className="mt-2 font-serif text-2xl text-tinta">{doc.titulo}</h1>
          </>
        )}
        <p className="text-xs text-taupe">
          {doc.etiqueta_version
            ? `Versión ${doc.etiqueta_version} · ${doc.version}.ª publicación en el sistema`
            : `${doc.version}.ª publicación en el sistema`}
          {" "}· vigente desde el {fechaLarga(doc.vigente_desde)}
        </p>
      </header>

      <Documento texto={doc.documento} />
    </main>
  );
}

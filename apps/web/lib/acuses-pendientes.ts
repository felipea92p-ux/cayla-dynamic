import type { ClienteCayla } from "@cayla-dynamic/database";

/**
 * Qué constancias le faltan a la persona que está mirando.
 *
 * POR QUÉ ESTÁ ACÁ Y NO DENTRO DEL COMPONENTE
 *
 * Lo pregunta la banda de arriba de /mio (`components/acuses-pendientes.tsx`) y
 * lo cuenta la Bandeja (`lib/bandeja-mia.ts`). Si cada una escribiera su propio
 * `requiere_acuse && !mi_acuse_at`, bastaría con que una agregara una condición
 * para que la banda dijera «te falta el RIT» mientras el número dice cero. Es el
 * mismo defecto que la Bandeja vino a evitar: dos puertas para una pregunta.
 *
 * CERO SQL: `fn_politica_salarial_vigente` y `fn_documentos_vigentes` ya
 * devuelven, para quien pregunta, si ELLA acusó. Esto solo las lee.
 */

/** Lo que devuelve `fn_documentos_vigentes`, en lo que aquí importa. */
export interface DocVigente {
  documento_id: string | null;
  titulo: string | null;
  tipo_nombre: string | null;
  requiere_acuse: boolean | null;
  mi_acuse_at: string | null;
}

/** Lo que devuelve `fn_politica_salarial_vigente`, en lo que aquí importa. */
export interface PoliticaVigente {
  version?: number | null;
  mi_acuse?: unknown;
}

export interface AcusePendiente {
  /** Estable entre recargas: `key` de React y desempate del orden. */
  clave: string;
  titulo: string;
  detalle: string;
  href: string;
}

/**
 * Las constancias que faltan, ya resueltas a partir de las dos respuestas.
 * Función pura: recibe lo que vino de la base y no consulta nada.
 */
export function acusesPendientes(
  politica: PoliticaVigente | null,
  documentos: DocVigente[] | null,
): AcusePendiente[] {
  const lista: AcusePendiente[] = [];

  // La política salarial. `mi_acuse` viene null mientras no se haya firmado; y
  // si no hay versión publicada, `version` viene null y no hay nada que pedir —
  // pedir constancia de un documento que no existe sería peor que callar.
  if (politica && politica.version != null && !politica.mi_acuse) {
    lista.push({
      clave: `acuse:politica:${politica.version}`,
      titulo: "Política salarial",
      detalle: "El cuadro de categorías y cómo se decide lo que cobra cada quien.",
      href: "/admin/politica-salarial",
    });
  }

  // Los documentos institucionales (reglamento interno y los que vengan
  // después). Solo los que EXIGEN constancia: hay tipos que se publican para
  // leer y no para firmar, y meterlos aquí convertiría el aviso en ruido.
  for (const d of documentos ?? []) {
    if (d.requiere_acuse === true && !d.mi_acuse_at) {
      lista.push({
        clave: `acuse:doc:${d.documento_id ?? d.titulo ?? "sin-id"}`,
        titulo: d.tipo_nombre ?? d.titulo ?? "Documento",
        detalle: d.titulo ?? "",
        // Al documento CONCRETO, no a la pantalla. Con dos pendientes, dos
        // enlaces al mismo sitio dejan a la persona buscando — y el segundo
        // suele ser un anexo, que va plegado más abajo.
        href: d.documento_id ? `/admin/normas#doc-${d.documento_id}` : "/admin/normas",
      });
    }
  }

  return lista;
}

/** Las dos consultas, para quien no las tenga ya hechas. */
export async function traerAcusesPendientes(supabase: ClienteCayla): Promise<AcusePendiente[]> {
  const [pol, docs] = await Promise.all([
    supabase.rpc("fn_politica_salarial_vigente"),
    supabase.rpc("fn_documentos_vigentes"),
  ]);
  return acusesPendientes(
    pol.data as PoliticaVigente | null,
    docs.data as unknown as DocVigente[] | null,
  );
}

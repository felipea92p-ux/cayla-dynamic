"use client";

import { useCallback, useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Cargando } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { loQueNoSePudo, sePuedeEntregar } from "@/lib/admin/lo-que-no-se-pudo";
import { EMPRESA, TZ_LIMA, avisoNombresDelDni, hoyLima, usaNombreDelDni } from "@cayla-dynamic/shared";

// La hoja de constancias de un documento: quién lo recibió, cuándo y por qué vía.
//
// PARA QUÉ EXISTE. La pantalla de Normas ya dice «19 de 21 han dejado
// constancia», pero eso vive dentro del panel. Lo que se adjunta a un
// requerimiento —o se enseña el día de una visita— es un papel, y hasta hoy ese
// papel había que rehacerlo a mano leyendo la pantalla. Esta hoja es la mitad
// que le faltaba a `imprimir`: aquella prueba QUÉ se comunicó, esta prueba A
// QUIÉN.
//
// POR QUÉ NO RECIBE UNA LISTA DE NOMBRES. Se pidió «la hoja de los 19», y la
// tentación es un parámetro con las personas a incluir. No lo tiene a propósito:
// la población obligada la responde `fn_acuses_documento` —activas y en
// planilla, el mismo criterio que `fn_poblacion_obligada`— y quien falte APARECE
// en la hoja, nombrado. Una hoja cuyo denominador se puede elegir no prueba
// nada: es justo el documento que un inspector sabe descartar, y descartarlo se
// lleva por delante la credibilidad de los 19 que sí firmaron.
//
// Los 19 salen igual, y salen solos: el día que se registre el cese de quien se
// va, la población obligada baja a 19 y la hoja dice 19 de 19 sin que nadie la
// toque. Mientras tanto dice la verdad, que es 19 de 21 con los dos nombres.
//
// Y POR ESO EL BLOQUE DE PENDIENTES DA EL MOTIVO. Un hueco sin explicar se lee
// como descuido. «Contrato hasta el 31/08/2026» o «cese previsto el 31/08/2026»
// —datos que la base ya tiene, no una nota escrita a mano— convierten el hueco
// en un hecho fechado. Eso sostiene mejor el cumplimiento que esconder las filas.

/**
 * La norma que obliga a entregar cada clase de documento.
 *
 * Se escribe acá y no en la base porque es la cita de una ley, no un dato de
 * gestión: no cambia cuando alguien crea un tipo desde la pantalla. Un tipo sin
 * cita sale sin línea legal en vez de con una inventada — es la única forma
 * segura de fallar en un papel que va a leer un inspector.
 */
const BASE_LEGAL: Record<string, string> = {
  rit: "D.S. 039-91-TR: el Reglamento Interno de Trabajo se entrega a cada trabajador dentro de los cinco (5) días naturales de aprobado, dejando constancia escrita de su recepción.",
  politica_hostigamiento:
    "Ley 27942 y su Reglamento (D.S. 014-2019-MIMP): la política de prevención y sanción del hostigamiento sexual laboral es de difusión obligatoria a todo el personal.",
  resolucion_hostigamiento:
    "Ley 27942 y su Reglamento (D.S. 014-2019-MIMP): la designación del órgano competente se comunica por escrito a cada persona.",
  risst: "Art. 74 del D.S. 005-2012-TR: el empleador entrega a cada trabajador el Reglamento Interno de Seguridad y Salud en el Trabajo.",
};

/** La política salarial no es un `documentos_institucionales`: vive en su propia
 *  tabla desde la 0141 y tiene su propia pantalla. Se nombra acá para que quien
 *  busque su hoja en este mismo sitio sepa dónde está. */
const BASE_LEGAL_POLITICA_SALARIAL =
  "Numeral 25.23 del RLGIT (Ley 30709): no basta con tener el cuadro de categorías y la política salarial — hay que acreditar que se informaron.";

interface Doc {
  id: string;
  tipo: string;
  tipo_nombre: string;
  version: number;
  etiqueta_version: string | null;
  titulo: string;
  vigente_desde: string;
  publicado_at: string;
}

interface Fila {
  persona_id: string;
  nombre: string;
  sede: string;
  acusado_at: string | null;
  via: string | null;
  dni: string | null;
  // El nombre completo tal como consta en el DNI (`datos_personales.nombre_dni`).
  // `nombre` es el de nómina («Apellidos, Nombres», del nombre corto): sirve para
  // ordenar y cruzar la lista. Éste identifica a la persona ante quien lea el papel.
  nombre_dni: string | null;
  nombre_declarado: string | null;
  fecha_fin_contrato: string | null;
  fecha_cese: string | null;
}

function selloLima(iso: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (isNaN(d.getTime())) return iso;
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA, day: "2-digit", month: "2-digit", year: "numeric",
    hour: "2-digit", minute: "2-digit", hour12: false,
  }).format(d);
}

/** Fecha plana en UTC: formatearla en zona local corre un día hacia atrás. */
function fechaCorta(iso: string | null): string {
  if (!iso) return "—";
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", {
    day: "2-digit", month: "2-digit", year: "numeric", timeZone: "UTC",
  }).format(new Date(Date.UTC(y, m - 1, d)));
}

function fechaLarga(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", {
    day: "2-digit", month: "long", year: "numeric", timeZone: "UTC",
  }).format(new Date(Date.UTC(y, m - 1, d)));
}

/** Por qué esta persona todavía no consta, cuando la base lo sabe. */
function motivoPendiente(f: Fila): string | null {
  if (f.fecha_cese) return `cese registrado el ${fechaCorta(f.fecha_cese)}`;
  if (f.fecha_fin_contrato) return `contrato vigente hasta el ${fechaCorta(f.fecha_fin_contrato)}`;
  return null;
}

export default function ConstanciasDocumentoPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const [doc, setDoc] = useState<Doc | null>(null);
  const [filas, setFilas] = useState<Fila[]>([]);
  const [error, setError] = useState<string | null>(null);
  // Distinta de `error`: el documento SÍ se abrió y la hoja SÍ se puede ver,
  // pero a algunas filas les falta un dato que la hoja necesita para probar
  // algo (el DNI o el nombre declarado). Mostrarla en blanco como "—" sería
  // un falso negativo silencioso — se vería igual que "esta persona no puso
  // su DNI" en vez de "el sistema no pudo traerlo". Mientras tenga algo, se
  // apaga «Imprimir». Es el mismo par (`loQueNoSePudo` / `sePuedeEntregar`) que
  // ya usa la hoja de la política salarial: dos hojas gemelas que avisaban un
  // fallo de dos maneras distintas eran dos respuestas a la misma pregunta.
  const [noSePudo, setNoSePudo] = useState<string[]>([]);
  const [cargando, setCargando] = useState(true);

  useTituloDocumento(doc ? `Constancias · ${doc.titulo}` : "Constancias");

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }

    const { data: d, error: e1 } = await supabase
      .from("documentos_institucionales")
      .select("id, tipo, version, etiqueta_version, titulo, vigente_desde, publicado_at")
      .eq("id", id)
      .maybeSingle();
    if (e1) { setCargando(false); setError(mensajeDeError(e1, "abrir el documento")); return; }
    if (!d) { setCargando(false); setError("Ese documento no existe o ya no está disponible."); return; }

    const { data: t } = await supabase
      .from("documentos_tipos").select("nombre").eq("codigo", d.tipo).maybeSingle();

    // Quiénes están comprendidas y cuáles ya constan. Es la MISMA función que
    // usa el seguimiento de la pantalla de Normas: dos respuestas distintas a
    // «a quién obliga esto» es exactamente lo que este repositorio prohíbe.
    const { data: acuses, error: e2 } = await supabase
      .rpc("fn_acuses_documento", { p_documento_id: id });
    if (e2) { setCargando(false); setError(mensajeDeError(e2, "leer las constancias")); return; }

    const base = (acuses ?? []) as Array<{
      persona_id: string; nombre: string; sede: string;
      acusado_at: string | null; via: string | null;
    }>;

    // El DNI y la fecha de salida no los devuelve esa función, y en un papel que
    // identifica personas el documento de identidad no es adorno: es lo que
    // distingue a dos apellidos iguales.
    const ids = base.map((b) => b.persona_id);
    const { data: pers, error: e3 } = ids.length
      ? await supabase.from("personas")
          .select("id, nombres, apellidos, documento, fecha_fin_contrato, fecha_cese").in("id", ids)
      : { data: [] as never[], error: null };

    // El nombre que cada quien escribió al dejar constancia. Es lo más cercano a
    // una firma que tiene la vía del sistema, y es lo que convierte el clic en
    // un acto deliberado — por eso va en la hoja.
    const { data: decl, error: e4 } = await supabase
      .from("documentos_acuses").select("persona_id, nombre_declarado").eq("documento_id", id);

    // El nombre completo del DNI: no lo devuelve la función ni vive en `personas`
    // (ahí está el corto). Cuando falla se NOMBRA —abajo, junto a las otras
    // lecturas— y se apaga «Imprimir»: sin esto la hoja saldría con el corto en
    // todas las filas, y eso se lee igual que «nadie tiene su nombre completo».
    const { data: dp, error: e5 } = ids.length
      ? await supabase.from("datos_personales").select("persona_id, nombre_dni").in("persona_id", ids)
      : { data: [] as never[], error: null };

    // Si cualquiera de las dos falló, el DNI o el nombre declarado saldrían en
    // blanco en TODAS las filas — indistinguible de "no lo dejó" cuando en
    // realidad es "no se pudo traer". Se avisa y se apaga Imprimir en vez de
    // dejar que la hoja mienta.
    setNoSePudo(
      loQueNoSePudo([
        { error: e3, que: "el DNI y la fecha de salida de las personas" },
        { error: e4, que: "el nombre declarado de las constancias" },
        { error: e5, que: "el nombre completo del DNI" },
      ]),
    );

    const porId = new Map((pers ?? []).map((p: Record<string, unknown>) => [p.id as string, p]));
    const nombreDniPorPersona = new Map(
      (dp ?? []).map((r: Record<string, unknown>) => [r.persona_id as string, r.nombre_dni as string | null]),
    );
    const porPersona = new Map((decl ?? []).map((a: Record<string, unknown>) => [a.persona_id as string, a.nombre_declarado as string | null]));

    const armadas: Fila[] = base.map((b) => {
      const p = porId.get(b.persona_id) as Record<string, unknown> | undefined;
      // «Apellidos, Nombres» y no «Nombres Apellidos»: una nómina se lee y se
      // cruza por apellido —así vienen la planilla, el T-Registro y el legajo—,
      // y ordenada por nombre de pila la misma lista es incomparable con
      // cualquiera de los tres. La función devuelve el nombre corriente porque
      // en pantalla se busca a la persona, no se coteja una lista.
      const apellidos = p?.apellidos as string | undefined;
      const nombres = p?.nombres as string | undefined;
      return {
        ...b,
        nombre: apellidos && nombres ? `${apellidos}, ${nombres}` : b.nombre,
        dni: (p?.documento as string | null) ?? null,
        nombre_dni: nombreDniPorPersona.get(b.persona_id) ?? null,
        nombre_declarado: porPersona.get(b.persona_id) ?? null,
        fecha_fin_contrato: (p?.fecha_fin_contrato as string | null) ?? null,
        fecha_cese: (p?.fecha_cese as string | null) ?? null,
      };
    });

    // En la hoja mandan las constancias: van numeradas de 1 a N y en orden
    // alfabético, que es como se lee un cargo. Los pendientes bajan a su propio
    // bloque. (La función las devuelve al revés, con los pendientes arriba,
    // porque ahí sirve para trabajar y acá para acreditar.)
    armadas.sort((a, b) => {
      const ca = a.acusado_at ? 0 : 1;
      const cb = b.acusado_at ? 0 : 1;
      if (ca !== cb) return ca - cb;
      return a.nombre.localeCompare(b.nombre, "es");
    });

    setDoc({ ...d, tipo_nombre: (t?.nombre as string) ?? d.tipo } as Doc);
    setFilas(armadas);
    setCargando(false);
  }, [id, router]);

  useEffect(() => { void cargar(); }, [cargar]);

  if (cargando) return <Cargando texto="Reuniendo las constancias…" />;

  if (error || !doc) {
    return (
      <main className="mx-auto max-w-2xl p-6">
        <p className="rounded-superficie border border-sand bg-papel px-4 py-6 text-sm text-taupe">
          {error ?? "No se pudo abrir el documento."}
        </p>
        <Boton variante="secundario" tamano="sm" className="mt-3" onClick={() => router.push("/admin/normas")}>
          Volver a Normas
        </Boton>
      </main>
    );
  }

  const constan = filas.filter((f) => f.acusado_at !== null);
  const pendientes = filas.filter((f) => f.acusado_at === null);
  const total = filas.length;
  // Solo en pantalla, y solo si la lectura contestó: si falló, faltarían todas
  // y este aviso mentiría — ya lo dice el aviso rojo de arriba.
  const avisoNombres = noSePudo.length === 0 ? avisoNombresDelDni(filas.map((f) => f.nombre_dni)) : null;
  const legal = BASE_LEGAL[doc.tipo] ?? null;
  const version = doc.etiqueta_version
    ? `${doc.etiqueta_version} (${doc.version}.ª publicación en el sistema)`
    : `${doc.version}.ª publicación en el sistema`;

  return (
    <main className="hoja mx-auto max-w-4xl p-6 print:max-w-none print:p-0">
      <div className="mb-5 flex flex-wrap items-center gap-2 print:hidden">
        <Boton variante="primario" tamano="sm" onClick={() => window.print()}
          disabled={!sePuedeEntregar(!cargando, noSePudo)}
          title={noSePudo.length > 0 ? `No se pudo traer ${noSePudo.join(", ")}.` : undefined}>
          Imprimir
        </Boton>
        <a href={`/admin/normas/${doc.id}/imprimir`} target="_blank" rel="noopener"
          className="rounded-control border border-tinta/30 px-3 py-1.5 text-xs text-tinta">
          Hoja del documento
        </a>
        <Boton variante="secundario" tamano="sm" onClick={() => router.push("/admin/normas")}>
          Volver
        </Boton>
        <p className="text-xs text-taupe">
          Para guardarlo como PDF, elige «Guardar como PDF» en el destino de impresión.
        </p>
      </div>

      {noSePudo.length > 0 && (
        <p className="mb-5 rounded-control border border-rojo/40 bg-rojo/10 px-4 py-3 text-xs text-rojo">
          No se pudo traer {noSePudo.join(", ")}. Esta hoja no prueba nada mientras falte ese dato:
          recarga la página, y si sigue igual avisa a Felipe.
        </p>
      )}

      {avisoNombres && (
        <p className="mb-5 rounded-control border border-ambar/40 bg-ambar/[0.07] px-4 py-3 text-xs text-tinta print:hidden">
          {avisoNombres}
        </p>
      )}

      <header className="mb-5 border-b border-sand pb-4">
        <p className="font-serif text-[11px] uppercase tracking-[0.2em] text-taupe">
          {EMPRESA.nombre} · RUC N.° {EMPRESA.ruc}
        </p>
        <h1 className="mt-2 font-serif text-2xl text-tinta">
          Constancia de entrega y difusión
        </h1>
        <p className="mt-1 text-sm text-tinta">{doc.tipo_nombre}</p>
      </header>

      <section className="mb-5 rounded-superficie border border-sand bg-crema/40 px-4 py-3 text-xs text-tinta print:rounded-none print:bg-transparent">
        <dl className="grid grid-cols-1 gap-x-6 gap-y-1 sm:grid-cols-2">
          <div><dt className="inline text-taupe">Documento: </dt><dd className="inline">{doc.titulo}</dd></div>
          <div><dt className="inline text-taupe">Versión: </dt><dd className="inline">{version}</dd></div>
          <div><dt className="inline text-taupe">Vigente desde: </dt><dd className="inline">{fechaLarga(doc.vigente_desde)}</dd></div>
          <div><dt className="inline text-taupe">Publicado el: </dt><dd className="inline">{selloLima(doc.publicado_at)}</dd></div>
        </dl>
        {legal && <p className="mt-2 border-t border-sand pt-2 text-taupe">{legal}</p>}
      </section>

      {/* El resumen va ANTES de la tabla y con la fecha de corte pegada al
          número. Un «19 de 19» sin fecha no dice nada: la plantilla cambia, y lo
          que se acredita es el estado en un día concreto. */}
      <section className="mb-5 rounded-superficie border border-tinta/20 px-4 py-3 text-sm text-tinta print:rounded-none">
        <p>
          Al <strong>{fechaLarga(hoyLima())}</strong>, de <strong>{total}</strong>{" "}
          {total === 1 ? "integrante comprendida" : "integrantes comprendidas"} —personal activo y en
          planilla—, <strong>{constan.length}</strong> {constan.length === 1 ? "dejó" : "dejaron"}{" "}
          constancia de haber recibido este documento
          {total > 0 && constan.length === total && <> · <strong>cumplimiento del 100 %</strong></>}.
        </p>
        {pendientes.length > 0 && (
          <p className="mt-1 text-taupe">
            Quedan {pendientes.length} {pendientes.length === 1 ? "pendiente" : "pendientes"}, que se
            detallan al pie de esta hoja.
          </p>
        )}
      </section>

      {/* Tabla nativa a propósito: contenido de un documento que se imprime
          como prueba legal. */}
      <table className="w-full border-collapse text-xs [font-variant-numeric:tabular-nums]">
        <thead>
          <tr className="border-y border-tinta/30 text-left text-taupe">
            <th className="py-1.5 pr-2 font-normal">N.°</th>
            <th className="py-1.5 pr-2 font-normal">Integrante</th>
            <th className="py-1.5 pr-2 font-normal">DNI</th>
            <th className="py-1.5 pr-2 font-normal">Sede</th>
            <th className="py-1.5 pr-2 font-normal">Vía</th>
            <th className="py-1.5 pr-2 font-normal">Fecha y hora</th>
            <th className="py-1.5 font-normal">Nombre declarado</th>
          </tr>
        </thead>
        <tbody>
          {constan.map((f, i) => (
            <tr key={f.persona_id} className="break-inside-avoid border-b border-sand align-top">
              <td className="py-1.5 pr-2 text-taupe">{i + 1}</td>
              <td className="py-1.5 pr-2">
                {f.nombre}
                {usaNombreDelDni(f.nombre_dni) && (
                  <span className="block text-[11px] text-taupe">{f.nombre_dni?.trim()}</span>
                )}
              </td>
              <td className="py-1.5 pr-2">{f.dni ?? "—"}</td>
              <td className="py-1.5 pr-2">{f.sede}</td>
              <td className="py-1.5 pr-2">{f.via === "papel" ? "cargo firmado" : "sistema"}</td>
              <td className="py-1.5 pr-2 whitespace-nowrap">{selloLima(f.acusado_at)}</td>
              <td className="py-1.5">{f.nombre_declarado ?? "—"}</td>
            </tr>
          ))}
          {constan.length === 0 && (
            <tr><td colSpan={7} className="py-3 text-taupe">
              Todavía no consta ninguna entrega de esta versión.
            </td></tr>
          )}
        </tbody>
      </table>

      <p className="mt-2 text-[11px] text-taupe">
        «Sistema»: la constancia la dejó la propia integrante desde el panel, escribiendo su nombre.
        «Cargo firmado»: se le entregó el documento impreso y firmó el cargo, que obra escaneado en
        el legajo. Bajo cada nombre de la lista figura el nombre completo tal como consta en su DNI.
        Las horas son de Lima.
      </p>

      {pendientes.length > 0 && (
        <section className="mt-5 break-inside-avoid rounded-superficie border border-sand px-4 py-3 text-xs print:rounded-none">
          <h2 className="mb-1 font-medium text-tinta">
            Pendientes a la fecha de corte · {pendientes.length}
          </h2>
          <ul className="divide-y divide-sand">
            {pendientes.map((f) => {
              const motivo = motivoPendiente(f);
              return (
                <li key={f.persona_id} className="flex flex-wrap justify-between gap-2 py-1.5">
                  <span>
                    {f.nombre} <span className="text-taupe">· {f.sede}{f.dni ? ` · DNI ${f.dni}` : ""}</span>
                    {usaNombreDelDni(f.nombre_dni) && (
                      <span className="block text-taupe">{f.nombre_dni?.trim()}</span>
                    )}
                  </span>
                  {motivo && <span className="text-taupe">{motivo}</span>}
                </li>
              );
            })}
          </ul>
        </section>
      )}

      <section className="mt-8 break-inside-avoid text-xs text-tinta">
        <p className="text-taupe">
          El texto íntegro de la versión acreditada en esta hoja se adjunta impreso desde el mismo
          registro, sin intermediarios: es el texto congelado que cada integrante leyó al dejar su
          constancia.
        </p>
        <div className="mt-10 w-64 border-t border-tinta/40 pt-1 text-center">
          Desarrollo Organizacional · {EMPRESA.nombre}
        </div>
      </section>
    </main>
  );
}

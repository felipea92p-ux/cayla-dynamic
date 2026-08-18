"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { AdminNav } from "../nav";
import { Cargando } from "@/components/cargando";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import {
  categoriasFueraDeOrden,
  construirDocumento,
  documentoAJson,
  documentoDesdeGuardado,
  type Bloque,
  type Cuadro,
  type Documento,
} from "@/lib/politica-salarial";

// El cuadro de categorías y la política salarial: una sola pantalla que sirve a
// dos personas distintas.
//
//   · Cualquier integrante entra, lee el documento y deja constancia. Eso es lo
//     que cierra el numeral 25.23 del RLGIT — no basta tener la política, hay
//     que probar que se informó.
//   · La Gerencia ve además el botón de publicar y quién falta por acusar.
//
// POR QUÉ UNA SOLA PANTALLA Y NO DOS. Si el documento que lee el equipo se
// armara aparte del que publica la Gerencia, tarde o temprano dirían cosas
// distintas — y el que vale como prueba es el publicado. Acá los dos salen de
// `construirDocumento`, así que no pueden divergir.
//
// POR QUÉ EL ACUSE POR SESIÓN VALE. No se está firmando un contrato: se deja
// constancia de haber sido informado. La Ley 27269 reconoce la firma
// electrónica, y desde el D.S. 009-2011-TR las boletas se entregan sin firma
// física. Lo que se guarda —quién, cuándo y QUÉ VERSIÓN— prueba más que una
// firma a mano, que no dice qué versión se firmó.

const DO = ["admin", "lider_do"];

interface Vigente {
  publicada: boolean;
  version?: number;
  documento?: string;
  publicada_at?: string;
  desactualizada: boolean;
  mi_acuse: { acusado_at: string; nombre: string } | null;
  total_personas?: number;
  total_acuses?: number;
  aviso?: string;
}

interface FilaAcuse {
  persona_id: string;
  nombre: string;
  rango: string | null;
  acusado_at: string | null;
  nombre_declarado: string | null;
}

function fechaLarga(iso: string): string {
  return new Intl.DateTimeFormat("es-PE", {
    day: "numeric",
    month: "long",
    year: "numeric",
    timeZone: "America/Lima",
  }).format(new Date(iso));
}

function fechaHora(iso: string): string {
  return new Intl.DateTimeFormat("es-PE", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "America/Lima",
  }).format(new Date(iso));
}

// Un solo renderizador del documento, para el que se está por publicar y para el
// ya publicado. Tenerlo dos veces era pedir que uno mostrara algo que el otro no
// — y el que vale como prueba es el publicado.
function DocumentoVista({ doc, firmaUrl }: { doc: Documento; firmaUrl: string | null }) {
  return (
    <article className="rounded border border-slate-300 bg-white p-6 print:rounded-none print:border-0 print:p-0">
      <header className="mb-6 border-b border-slate-300 pb-4">
        <h2 className="text-lg font-semibold text-slate-900">{doc.titulo}</h2>
        <p className="text-sm text-slate-600">
          {doc.empresa.nombre} — RUC {doc.empresa.ruc}
        </p>
        <p className="text-sm text-slate-600">{doc.fecha}</p>
      </header>
      {doc.secciones.map((sec, i) => (
        <section key={i} className="mb-6">
          {/* Un título que se queda solo al pie de una hoja manda a la siguiente
              página el texto que anuncia; en papel eso se lee como si faltara. */}
          <h3 className="mb-3 text-base font-semibold text-slate-900 print:break-after-avoid">
            {sec.titulo}
          </h3>
          {sec.bloques.map((b, j) => (
            <BloqueVista key={j} b={b} />
          ))}
        </section>
      ))}
      {/* La firma no se separa nunca del nombre y el cargo que la sostienen: una
          rúbrica suelta en la última hoja no acredita a quién pertenece. */}
      <footer className="mt-10 border-t border-slate-300 pt-6 print:break-inside-avoid">
        {firmaUrl !== null && (
          /* eslint-disable-next-line @next/next/no-img-element */
          <img src={firmaUrl} alt="" className="mb-1 h-16 object-contain" />
        )}
        <p className="text-sm font-medium text-slate-900">{doc.empresa.firmante}</p>
        <p className="text-sm text-slate-600">
          {doc.empresa.cargo} — {doc.empresa.nombre}
        </p>
      </footer>
    </article>
  );
}

function BloqueVista({ b }: { b: Bloque }) {
  if (b.tipo === "parrafo") {
    return <p className="mb-3 text-sm leading-relaxed text-slate-700">{b.texto}</p>;
  }
  if (b.tipo === "destacado") {
    return (
      <p className="mb-4 border-l-4 border-slate-800 bg-slate-50 px-4 py-3 text-sm font-medium leading-relaxed text-slate-900">
        {b.texto}
      </p>
    );
  }
  if (b.tipo === "lista") {
    return (
      <ul className="mb-4 list-disc space-y-1 pl-6 text-sm leading-relaxed text-slate-700">
        {b.items.map((it, i) => (
          <li key={i}>{it}</li>
        ))}
      </ul>
    );
  }
  return (
    <div className="mb-4 overflow-x-auto">
      <table className="w-full border-collapse text-left text-sm">
        <thead>
          <tr>
            {b.cabeceras.map((c, i) => (
              <th
                key={i}
                className="border border-slate-300 bg-slate-100 px-3 py-2 font-semibold text-slate-900"
              >
                {c}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {b.filas.map((fila, i) => (
            <tr key={i}>
              {fila.map((celda, j) => (
                <td
                  key={j}
                  className="border border-slate-300 px-3 py-2 align-top text-slate-700"
                >
                  {celda}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export default function PoliticaSalarialPage() {
  useTituloDocumento("Política salarial");
  const persona = usePersonaActual();
  const esDO = persona !== null && DO.includes(persona.rol);

  const [cuadro, setCuadro] = useState<Cuadro | null>(null);
  const [vigente, setVigente] = useState<Vigente | null>(null);
  const [acuses, setAcuses] = useState<FilaAcuse[]>([]);
  const [firmaUrl, setFirmaUrl] = useState<string | null>(null);
  // ¿Quien tiene la sesión abierta es quien firma por CAYLA? La rúbrica solo se
  // estampa entonces. El NOMBRE de la línea no se toca acá: en una política ya
  // publicada viene congelado dentro del texto emitido, y reescribirlo sería
  // cambiar un documento que ya circuló.
  const [esFirmante, setEsFirmante] = useState(false);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [nombreAcuse, setNombreAcuse] = useState("");
  const [guardando, setGuardando] = useState(false);

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    setError(null);
    const [c, v, f, yo, cfg] = await Promise.all([
      supabase.rpc("fn_cuadro_categorias"),
      supabase.rpc("fn_politica_salarial_vigente"),
      supabase.rpc("fn_mi_firma"),
      supabase.rpc("fn_persona_actual_id"),
      supabase.from("configuracion").select("valor").eq("clave", "firmante_empresa").maybeSingle(),
    ]);
    if (c.error !== null || v.error !== null) {
      setError(mensajeDeError(c.error ?? v.error, "cargar la política salarial"));
      setCargando(false);
      return;
    }
    setCuadro(c.data as unknown as Cuadro);
    setVigente(v.data as unknown as Vigente);
    setFirmaUrl(typeof f.data === "string" && f.data.startsWith("data:image") ? f.data : null);
    // Quién firma por CAYLA vive en `configuracion` desde la 0147. Si la fila
    // no está —migración sin pegar— nadie estampa y el documento sale con el
    // espacio en blanco para firmar a mano, como antes de todo esto.
    const vf = (cfg.data?.valor ?? null) as { persona_id?: string } | null;
    setEsFirmante(Boolean(vf?.persona_id) && vf?.persona_id === yo.data);

    if (persona !== null && DO.includes(persona.rol)) {
      const { data: a } = await supabase.rpc("fn_acuses_politica_salarial");
      setAcuses((a as { personas?: FilaAcuse[] } | null)?.personas ?? []);
    }
    setCargando(false);
  }, [persona]);

  useEffect(() => {
    if (persona === null) return;
    void cargar();
  }, [persona, cargar]);

  useEffect(() => {
    if (persona !== null && nombreAcuse === "") setNombreAcuse(persona.nombreCompleto);
  }, [persona, nombreAcuse]);

  const hoy = useMemo(
    () =>
      new Intl.DateTimeFormat("es-PE", {
        day: "numeric",
        month: "long",
        year: "numeric",
        timeZone: "America/Lima",
      }).format(new Date()),
    [],
  );

  // Lo que se ve en pantalla. Si ya hay una versión publicada y NO está
  // desactualizada, lo que se muestra es exactamente lo que se publicó; el
  // documento en vivo solo se usa para publicar o cuando aún no hay versión.
  const docVivo: Documento | null = useMemo(
    () => (cuadro ? construirDocumento(cuadro, hoy) : null),
    [cuadro, hoy],
  );

  // Las categorías que valen igual o menos que la anterior. Una escala que no
  // sube con la categoría contradice el único criterio que la sostiene ante una
  // inspección, así que se avisa ANTES de publicar y no después.
  const fueraDeOrden = useMemo(
    () => (cuadro ? categoriasFueraDeOrden(cuadro.categorias) : []),
    [cuadro],
  );

  const publicar = async () => {
    if (docVivo === null) return;
    setGuardando(true);
    setError(null);
    setAviso(null);
    const supabase = createAdminSupabaseClient();
    const { data, error: e } = await supabase.rpc("fn_publicar_politica_salarial", {
      p_documento: documentoAJson(docVivo),
      p_notas: null,
    });
    if (e !== null) {
      setError(mensajeDeError(e, "publicar la política salarial"));
    } else {
      setAviso(`Publicada la versión ${String(data)}. Ahora cada integrante deja su constancia.`);
      await cargar();
    }
    setGuardando(false);
  };

  const acusar = async () => {
    setGuardando(true);
    setError(null);
    setAviso(null);
    const supabase = createAdminSupabaseClient();
    const { error: e } = await supabase.rpc("fn_acusar_politica_salarial", {
      p_nombre: nombreAcuse,
    });
    if (e !== null) {
      setError(mensajeDeError(e, "registrar tu constancia"));
    } else {
      setAviso("Gracias. Tu constancia quedó registrada.");
      await cargar();
    }
    setGuardando(false);
  };

  if (cargando) {
    return (
      <>
        <AdminNav />
        <Cargando />
      </>
    );
  }

  const pendientes = acuses.filter((a) => a.acusado_at === null);
  const yaAcusaron = acuses.filter((a) => a.acusado_at !== null);

  return (
    <>
      <div className="print:hidden">
        <AdminNav />
      </div>
      <main className="mx-auto max-w-4xl px-4 py-8 print:max-w-none print:p-0">
        {/* En papel esta cabecera sobra: el documento trae la suya con el título,
            el RUC y la fecha, que es la que vale como ejemplar entregado. */}
        <div className="print:hidden">
          <div className="mb-1 flex flex-wrap items-start justify-between gap-3">
            <h1 className="text-2xl font-semibold text-slate-900">
              Cuadro de categorías y política salarial
            </h1>
            {/* La Ley 30709 pide ENTREGAR este documento a cada integrante, así
                que llevarse una copia no es cosa de la Gerencia: el botón lo ve
                cualquiera que pueda leer la pantalla. */}
            <button
              type="button"
              onClick={() => window.print()}
              className="rounded border border-slate-300 px-3 py-1.5 text-sm font-medium text-slate-800 hover:bg-slate-50"
            >
              Imprimir / Guardar como PDF
            </button>
          </div>
          <p className="mb-6 text-sm text-slate-600">
            Cómo se organiza el trabajo en CAYLA y cómo se determina lo que gana cada persona.
          </p>
        </div>

        {error !== null && (
          <p className="mb-4 rounded border border-red-300 bg-red-50 px-4 py-3 text-sm text-red-800 print:hidden">
            {error}
          </p>
        )}
        {aviso !== null && (
          <p className="mb-4 rounded border border-emerald-300 bg-emerald-50 px-4 py-3 text-sm text-emerald-800 print:hidden">
            {aviso}
          </p>
        )}

        {/* ── La escala se desordenó ──
            Solo lo ve quien puede publicar, y NO entra al documento: un papel
            que se contradice a sí mismo es peor prueba que uno sin publicar. */}
        {esDO && fueraDeOrden.length > 0 && (
          <section className="mb-6 rounded border border-amber-400 bg-amber-50 px-4 py-3 print:hidden">
            <p className="text-sm font-medium text-amber-900">
              La escala no sube con la categoría.
            </p>
            <p className="mt-1 text-sm text-amber-900">
              {fueraDeOrden.length === 1
                ? `${fueraDeOrden[0]} tiene una remuneración declarada igual o menor que la de la categoría anterior.`
                : `Estas categorías tienen una remuneración declarada igual o menor que la de la categoría anterior: ${fueraDeOrden.join(", ")}.`}{" "}
              Ese orden es la única razón por la que una categoría puede pagarse más que otra
              (Ley 30709). Corrige los montos en{" "}
              <strong>categorias_laborales.salario_declarado</strong> antes de publicar.
            </p>
          </section>
        )}

        {/* ── Barra de estado, solo para quien puede publicar ── */}
        {esDO && vigente !== null && (
          <section className="mb-8 rounded border border-slate-300 bg-white p-4 print:hidden">
            {!vigente.publicada ? (
              <>
                <p className="mb-3 text-sm text-slate-800">
                  Todavía no se ha publicado ninguna versión. Hasta publicarla y recoger las
                  constancias, CAYLA sigue incursa en el numeral 25.23 del RLGIT.
                </p>
                <button
                  type="button"
                  onClick={() => void publicar()}
                  disabled={guardando}
                  className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
                >
                  Publicar esta versión
                </button>
              </>
            ) : (
              <>
                <p className="mb-2 text-sm text-slate-800">
                  Versión <strong>{vigente.version}</strong>, publicada el{" "}
                  {vigente.publicada_at !== undefined ? fechaLarga(vigente.publicada_at) : "—"}.{" "}
                  Constancias: <strong>{vigente.total_acuses ?? 0}</strong> de{" "}
                  {vigente.total_personas ?? 0}.{" "}
                  <a href="/admin/politica-salarial/constancias" target="_blank" rel="noopener"
                    className="underline underline-offset-2 hover:text-slate-950">
                    hoja de constancias
                  </a>
                </p>
                {vigente.desactualizada && (
                  <p className="mb-3 rounded border border-amber-300 bg-amber-50 px-3 py-2 text-sm text-amber-900">
                    El cuadro cambió después de publicar: alguna categoría, remuneración o tarifa
                    ya no coincide con el documento que el equipo recibió. Publica una versión
                    nueva — las constancias volverán a pedirse.
                  </p>
                )}
                <button
                  type="button"
                  onClick={() => void publicar()}
                  disabled={guardando}
                  className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
                >
                  {vigente.desactualizada ? "Publicar versión nueva" : "Volver a publicar"}
                </button>
              </>
            )}
          </section>
        )}

        {/* ── El documento ── */}
        {vigente !== null && vigente.publicada && !vigente.desactualizada ? (
          // Lo publicado, tal cual se comunicó. NO se regenera desde las tablas:
          // si se regenerara, cambiar una banda haría que las constancias
          // apuntaran a un texto que nadie leyó.
          //
          // Lo que se muestra sale de lo guardado, no de `docVivo`. Desde que se
          // guarda como JSON se puede pintar con el mismo renderizador de abajo,
          // así que el documento se ve igual antes y después de publicarlo. Las
          // versiones anteriores se guardaron como texto plano: para esas,
          // `documentoDesdeGuardado` devuelve null y se muestran tal cual — se
          // ven peor, pero son las que la gente firmó y no se tocan.
          (() => {
            const publicado = documentoDesdeGuardado(vigente.documento ?? "");
            if (publicado === null) {
              return (
                <article className="rounded border border-slate-300 bg-white p-6 print:rounded-none print:border-0 print:p-0">
                  <pre className="whitespace-pre-wrap font-sans text-sm leading-relaxed text-slate-800">
                    {vigente.documento}
                  </pre>
                </article>
              );
            }
            return <DocumentoVista doc={publicado} firmaUrl={esFirmante ? firmaUrl : null} />;
          })()
        ) : (
          docVivo !== null && (
            <DocumentoVista doc={docVivo} firmaUrl={esFirmante ? firmaUrl : null} />
          )
        )}

        {/* ── La constancia ── */}
        {vigente !== null && vigente.publicada && (
          <section className="mt-8 rounded border border-slate-300 bg-white p-5 print:hidden">
            <h2 className="mb-2 text-base font-semibold text-slate-900">
              Constancia de haber recibido este documento
            </h2>
            {vigente.mi_acuse !== null ? (
              <p className="text-sm text-slate-700">
                Dejaste constancia el {fechaHora(vigente.mi_acuse.acusado_at)} como{" "}
                <strong>{vigente.mi_acuse.nombre}</strong>. No hace falta hacer nada más hasta que
                se publique una versión nueva.
              </p>
            ) : (
              <>
                <p className="mb-3 text-sm text-slate-700">
                  Escribe tu nombre para dejar constancia de que recibiste y leíste este documento.
                  Dejar constancia no significa estar de acuerdo con su contenido: si tienes una
                  discrepancia, puedes plantearla a la Gerencia y recibirás respuesta por escrito.
                </p>
                <div className="flex flex-wrap items-center gap-3">
                  <input
                    type="text"
                    value={nombreAcuse}
                    onChange={(e) => setNombreAcuse(e.target.value)}
                    placeholder="Tu nombre completo"
                    className="min-w-64 flex-1 rounded border border-slate-300 px-3 py-2 text-sm"
                  />
                  <button
                    type="button"
                    onClick={() => void acusar()}
                    disabled={guardando || nombreAcuse.trim() === ""}
                    className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
                  >
                    Dejar constancia
                  </button>
                </div>
              </>
            )}
          </section>
        )}

        {/* ── Quién falta ── */}
        {esDO && acuses.length > 0 && (
          <section className="mt-8 rounded border border-slate-300 bg-white p-5 print:hidden">
            <h2 className="mb-3 text-base font-semibold text-slate-900">
              Quién dejó constancia
            </h2>
            {pendientes.length > 0 && (
              <>
                <p className="mb-2 text-sm font-medium text-amber-900">
                  Falta {pendientes.length === 1 ? "1 persona" : `${pendientes.length} personas`}:
                </p>
                <ul className="mb-4 list-disc space-y-1 pl-6 text-sm text-slate-700">
                  {pendientes.map((a) => (
                    <li key={a.persona_id}>{a.nombre}</li>
                  ))}
                </ul>
              </>
            )}
            {yaAcusaron.length > 0 && (
              <table className="w-full border-collapse text-left text-sm">
                <thead>
                  <tr>
                    <th className="border-b border-slate-300 py-2 font-semibold text-slate-900">
                      Persona
                    </th>
                    <th className="border-b border-slate-300 py-2 font-semibold text-slate-900">
                      Dejó constancia
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {yaAcusaron.map((a) => (
                    <tr key={a.persona_id}>
                      <td className="border-b border-slate-200 py-2 text-slate-700">{a.nombre}</td>
                      <td className="border-b border-slate-200 py-2 text-slate-700">
                        {a.acusado_at !== null ? fechaHora(a.acusado_at) : "—"}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </section>
        )}
      </main>
    </>
  );
}

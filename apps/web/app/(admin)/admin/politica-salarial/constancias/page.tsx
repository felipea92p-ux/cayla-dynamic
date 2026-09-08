"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Cargando } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { loQueNoSePudo, sePuedeEntregar } from "@/lib/admin/lo-que-no-se-pudo";
import { EMPRESA, TZ_LIMA, hoyLima } from "@cayla-dynamic/shared";

// La hoja de constancias del cuadro de categorías y la política salarial.
//
// Es la misma idea que `/admin/normas/[id]/constancias`, y por qué es una
// pantalla aparte y no la misma con un parámetro: la política salarial no vive
// en `documentos_institucionales` —vive en su propia tabla desde la 0141, con
// clave entera y no uuid, sin vía «papel» porque nunca se ofreció esa vía— y no
// tiene historial navegable: la pantalla que la publica solo conoce la versión
// VIGENTE. Forzar las dos por el mismo camino habría dejado un `id` opcional
// mintiendo sobre qué significa.
//
// El criterio de a quién obliga es el mismo (activo y en planilla) porque lo
// dice la misma función en `fn_acuses_politica_salarial`: activas y en
// planilla, igual que `fn_poblacion_obligada`.

const BASE_LEGAL =
  "Numeral 25.23 del RLGIT (Ley 30709): no basta con tener el cuadro de categorías y la política salarial — hay que acreditar que se informaron a cada integrante.";

interface FilaCruda {
  persona_id: string;
  nombre: string;
  rango: string | null;
  acusado_at: string | null;
  nombre_declarado: string | null;
}

interface Fila {
  persona_id: string;
  nombre: string;
  dni: string | null;
  sede: string | null;
  acusado_at: string | null;
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

function fechaCorta(iso: string | null): string {
  if (!iso) return "—";
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", {
    day: "2-digit", month: "2-digit", year: "numeric", timeZone: "UTC",
  }).format(new Date(Date.UTC(y, m - 1, d)));
}

function fechaLarga(iso: string): string {
  const d = new Date(iso);
  return new Intl.DateTimeFormat("es-PE", {
    day: "2-digit", month: "long", year: "numeric", timeZone: TZ_LIMA,
  }).format(d);
}

function motivoPendiente(f: Fila): string | null {
  if (f.fecha_cese) return `cese registrado el ${fechaCorta(f.fecha_cese)}`;
  if (f.fecha_fin_contrato) return `contrato vigente hasta el ${fechaCorta(f.fecha_fin_contrato)}`;
  return null;
}

export default function ConstanciasPoliticaSalarialPage() {
  const router = useRouter();
  const [version, setVersion] = useState<number | null>(null);
  const [publicadaAt, setPublicadaAt] = useState<string | null>(null);
  const [filas, setFilas] = useState<Fila[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [cargando, setCargando] = useState(true);
  // Si `personas`, `sedes` o `politica_salarial` fallan, la fila se sigue
  // llenando con lo que quedó —DNI y sede en blanco, fecha de publicación en
  // blanco, motivo del pendiente perdido— y eso se lee igual que "no tiene
  // dato" en vez de "no se pudo traer". Este papel es la prueba del numeral
  // 25.23 del RLGIT, no un reporte de cortesía: mientras falte algo no se
  // imprime. Mismo par que usa la Hoja de sede (lib/admin/lo-que-no-se-pudo.ts).
  const [noSePudo, setNoSePudo] = useState<string[]>([]);

  useTituloDocumento("Constancias · Política salarial");

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }

    const { data: acusesData, error: e1 } = await supabase.rpc("fn_acuses_politica_salarial");
    if (e1) { setCargando(false); setError(mensajeDeError(e1, "leer las constancias")); return; }

    const acuses = acusesData as { version: number | null; personas: FilaCruda[] } | null;
    const v = acuses?.version ?? null;
    if (v === null) {
      setCargando(false);
      setError("Todavía no se ha publicado ninguna versión de la política salarial.");
      return;
    }

    const { data: pol, error: errPol } = await supabase
      .from("politica_salarial").select("publicada_at").eq("version", v).maybeSingle();

    const base = acuses?.personas ?? [];
    const ids = base.map((b) => b.persona_id);
    const { data: pers, error: errPers } = ids.length
      ? await supabase.from("personas")
          .select("id, nombres, apellidos, documento, sede_base_id, fecha_fin_contrato, fecha_cese")
          .in("id", ids)
      : { data: [] as never[], error: null };

    const sedeIds = Array.from(
      new Set((pers ?? []).map((p: Record<string, unknown>) => p.sede_base_id as string).filter(Boolean))
    );
    const { data: sedes, error: errSedes } = sedeIds.length
      ? await supabase.from("sedes").select("id, codigo").in("id", sedeIds)
      : { data: [] as never[], error: null };
    const codigoPorSede = new Map((sedes ?? []).map((s: Record<string, unknown>) => [s.id as string, s.codigo as string]));

    // El DNI, la sede y el motivo de un pendiente (cese, fin de contrato)
    // salen de `personas`; el código legible de sede, de `sedes`; la fecha de
    // publicación, de `politica_salarial`. Si cualquiera falla, esa columna
    // sale en "—" para las treinta filas y nada en pantalla lo distingue de
    // "no tiene dato".
    setNoSePudo(
      loQueNoSePudo([
        { error: errPol, que: "la fecha de publicación" },
        { error: errPers, que: "el DNI, la sede y el motivo de los pendientes" },
        { error: errSedes, que: "el código de sede" },
      ]),
    );

    const porId = new Map((pers ?? []).map((p: Record<string, unknown>) => [p.id as string, p]));

    const armadas: Fila[] = base.map((b) => {
      const p = porId.get(b.persona_id) as Record<string, unknown> | undefined;
      const apellidos = p?.apellidos as string | undefined;
      const nombres = p?.nombres as string | undefined;
      const sedeId = p?.sede_base_id as string | undefined;
      return {
        persona_id: b.persona_id,
        nombre: apellidos && nombres ? `${apellidos}, ${nombres}` : b.nombre,
        dni: (p?.documento as string | null) ?? null,
        sede: sedeId ? codigoPorSede.get(sedeId) ?? null : null,
        acusado_at: b.acusado_at,
        nombre_declarado: b.nombre_declarado,
        fecha_fin_contrato: (p?.fecha_fin_contrato as string | null) ?? null,
        fecha_cese: (p?.fecha_cese as string | null) ?? null,
      };
    });

    armadas.sort((a, b) => {
      const ca = a.acusado_at ? 0 : 1;
      const cb = b.acusado_at ? 0 : 1;
      if (ca !== cb) return ca - cb;
      return a.nombre.localeCompare(b.nombre, "es");
    });

    setVersion(v);
    setPublicadaAt((pol?.publicada_at as string | undefined) ?? null);
    setFilas(armadas);
    setCargando(false);
  }, [router]);

  useEffect(() => { void cargar(); }, [cargar]);

  if (cargando) return <Cargando texto="Reuniendo las constancias…" />;

  if (error || version === null) {
    return (
      <main className="mx-auto max-w-2xl p-6">
        <p className="rounded-2xl border border-sand bg-papel px-4 py-6 text-sm text-taupe">
          {error ?? "No se pudo abrir la política salarial."}
        </p>
        <Boton variante="secundario" tamano="sm" className="mt-3" onClick={() => router.push("/admin/politica-salarial")}>
          Volver a Política salarial
        </Boton>
      </main>
    );
  }

  const constan = filas.filter((f) => f.acusado_at !== null);
  const pendientes = filas.filter((f) => f.acusado_at === null);
  const total = filas.length;

  return (
    <main className="mx-auto max-w-4xl p-6 print:max-w-none print:p-0">
      <div className="mb-5 flex flex-wrap items-center gap-2 print:hidden">
        {/* Sin todos los datos NO se imprime: el papel es la prueba del
            numeral 25.23 del RLGIT, y un DNI o una sede en blanco por una
            consulta caída se leería como un dato que nunca se tuvo. */}
        <Boton variante="primario" tamano="sm" onClick={() => window.print()}
          disabled={!sePuedeEntregar(!cargando, noSePudo)}
          title={noSePudo.length > 0 ? `No se pudo traer ${noSePudo.join(", ")}.` : undefined}>
          Imprimir
        </Boton>
        <Boton variante="secundario" tamano="sm" onClick={() => router.push("/admin/politica-salarial")}>
          Volver
        </Boton>
        <p className="text-xs text-taupe">
          Para guardarlo como PDF, elige «Guardar como PDF» en el destino de impresión.
        </p>
      </div>

      {/* El aviso SÍ se imprime —no lleva print:hidden— por si alguien fuerza
          ⌘P saltándose el botón deshabilitado: el papel tiene que decir por
          escrito que está incompleto, no salir en blanco y silencio. */}
      {noSePudo.length > 0 && (
        <p className="mb-5 rounded-lg border border-rojo/40 bg-rojo/10 px-4 py-3 text-xs text-rojo">
          No se pudo traer {noSePudo.join(", ")}. Esta hoja no prueba nada mientras falte ese
          dato: recarga la página, y si sigue igual avisa a Felipe.
        </p>
      )}

      <header className="mb-5 border-b border-sand pb-4">
        <p className="font-serif text-[11px] uppercase tracking-[0.2em] text-taupe">
          {EMPRESA.nombre} · RUC N.° {EMPRESA.ruc}
        </p>
        <h1 className="mt-2 font-serif text-2xl text-tinta">
          Constancia de entrega y difusión
        </h1>
        <p className="mt-1 text-sm text-tinta">Cuadro de categorías y política salarial</p>
      </header>

      <section className="mb-5 rounded-xl border border-sand bg-crema/40 px-4 py-3 text-xs text-tinta print:rounded-none print:bg-transparent">
        <dl className="grid grid-cols-1 gap-x-6 gap-y-1 sm:grid-cols-2">
          <div><dt className="inline text-taupe">Documento: </dt><dd className="inline">Cuadro de categorías y política salarial</dd></div>
          <div><dt className="inline text-taupe">Versión: </dt><dd className="inline">{version}</dd></div>
          <div><dt className="inline text-taupe">Publicada el: </dt><dd className="inline">{selloLima(publicadaAt)}</dd></div>
        </dl>
        <p className="mt-2 border-t border-sand pt-2 text-taupe">{BASE_LEGAL}</p>
      </section>

      <section className="mb-5 rounded-xl border border-tinta/20 px-4 py-3 text-sm text-tinta print:rounded-none">
        <p>
          Al <strong>{fechaLarga(hoyLima())}</strong>, de <strong>{total}</strong>{" "}
          {total === 1 ? "integrante comprendida" : "integrantes comprendidas"} —personal activo y en
          planilla—, <strong>{constan.length}</strong> {constan.length === 1 ? "dejó" : "dejaron"}{" "}
          constancia de haber sido informada de esta versión
          {total > 0 && constan.length === total && <> · <strong>cumplimiento del 100 %</strong></>}.
        </p>
        {pendientes.length > 0 && (
          <p className="mt-1 text-taupe">
            Quedan {pendientes.length} {pendientes.length === 1 ? "pendiente" : "pendientes"}, que se
            detallan al pie de esta hoja.
          </p>
        )}
      </section>

      <table className="w-full border-collapse text-xs">
        <thead>
          <tr className="border-y border-tinta/30 text-left text-taupe">
            <th className="py-1.5 pr-2 font-normal">N.°</th>
            <th className="py-1.5 pr-2 font-normal">Integrante</th>
            <th className="py-1.5 pr-2 font-normal">DNI</th>
            <th className="py-1.5 pr-2 font-normal">Sede</th>
            <th className="py-1.5 pr-2 font-normal">Fecha y hora</th>
            <th className="py-1.5 font-normal">Nombre declarado</th>
          </tr>
        </thead>
        <tbody>
          {constan.map((f, i) => (
            <tr key={f.persona_id} className="break-inside-avoid border-b border-sand align-top">
              <td className="py-1.5 pr-2 text-taupe">{i + 1}</td>
              <td className="py-1.5 pr-2">{f.nombre}</td>
              <td className="py-1.5 pr-2">{f.dni ?? "—"}</td>
              <td className="py-1.5 pr-2">{f.sede ?? "—"}</td>
              <td className="py-1.5 pr-2 whitespace-nowrap">{selloLima(f.acusado_at)}</td>
              <td className="py-1.5">{f.nombre_declarado ?? "—"}</td>
            </tr>
          ))}
          {constan.length === 0 && (
            <tr><td colSpan={6} className="py-3 text-taupe">
              Todavía no consta ninguna constancia de esta versión.
            </td></tr>
          )}
        </tbody>
      </table>

      <p className="mt-2 text-[11px] text-taupe">
        La constancia la deja la propia integrante desde el panel, escribiendo su nombre — no hay vía
        en papel para este documento. Las horas son de Lima.
      </p>

      {pendientes.length > 0 && (
        <section className="mt-5 break-inside-avoid rounded-xl border border-sand px-4 py-3 text-xs print:rounded-none">
          <h2 className="mb-1 font-medium text-tinta">
            Pendientes a la fecha de corte · {pendientes.length}
          </h2>
          <ul className="divide-y divide-sand">
            {pendientes.map((f) => {
              const motivo = motivoPendiente(f);
              return (
                <li key={f.persona_id} className="flex flex-wrap justify-between gap-2 py-1.5">
                  <span>{f.nombre} <span className="text-taupe">· {f.sede ?? "—"}{f.dni ? ` · DNI ${f.dni}` : ""}</span></span>
                  {motivo && <span className="text-taupe">{motivo}</span>}
                </li>
              );
            })}
          </ul>
        </section>
      )}

      <section className="mt-8 break-inside-avoid text-xs text-tinta">
        <div className="mt-10 w-64 border-t border-tinta/40 pt-1 text-center">
          Desarrollo Organizacional · {EMPRESA.nombre}
        </div>
      </section>
    </main>
  );
}

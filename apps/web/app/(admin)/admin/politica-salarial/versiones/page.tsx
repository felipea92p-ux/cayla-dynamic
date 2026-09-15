"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { ROLES_DO, TZ_LIMA } from "@cayla-dynamic/shared";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { Cargando } from "@/components/cargando";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { Modal } from "@/components/ui/modal";
import { Tabla, TablaEncabezado, Th, Fila } from "@/components/ui/tabla";
import { SubnavPoliticaSalarial } from "../_subnav";
import {
  construirDocumento,
  documentoAJson,
  documentoDesdeGuardado,
  documentoTieneCambios,
  seccionesCambiadas,
  type Cuadro,
  type Documento,
} from "@/lib/politica-salarial";

// "Versiones y publicación" — separado de "Documento vigente" (Fase 9,
// pregunta 10) para que publicar deje de vivir en medio de la pantalla que
// lee cualquier integrante. Acá vive también el arreglo de la 0456: publicar
// dos veces el mismo contenido ya no crea versión ni reinicia constancias, y
// esta pantalla lo dice ANTES de que se haga clic, no después.

interface FilaVersion {
  version: number;
  publicada_at: string;
  notas: string | null;
  total_acuses: number;
  total_personas: number;
}

function fechaLarga(iso: string): string {
  return new Intl.DateTimeFormat("es-PE", { day: "numeric", month: "long", year: "numeric", timeZone: TZ_LIMA }).format(new Date(iso));
}

export default function VersionesPoliticaSalarialPage() {
  useTituloDocumento("Versiones · Política salarial");
  const persona = usePersonaActual();
  const esDO = persona !== null && ROLES_DO.includes(persona.rol);

  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [cuadro, setCuadro] = useState<Cuadro | null>(null);
  const [versiones, setVersiones] = useState<FilaVersion[]>([]);
  const [modalAbierto, setModalAbierto] = useState(false);
  const [publicando, setPublicando] = useState(false);

  // Comparador de versiones
  const [compIzq, setCompIzq] = useState<number | null>(null);
  const [compDer, setCompDer] = useState<number | null>(null);
  const [cambios, setCambios] = useState<Set<string> | null>(null);
  const [comparando, setComparando] = useState(false);

  // useCallback: la reutiliza `publicar()` para refrescar la lista después de
  // publicar. El efecto de montaje, abajo, pide los mismos datos en línea —
  // llamar desde un efecto a una función que termina en un setState dispara
  // el lint react-hooks/set-state-in-effect (ver admin/objetivos/page.tsx).
  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    setError(null);
    const [c, lista] = await Promise.all([
      supabase.rpc("fn_cuadro_categorias"),
      supabase.from("politica_salarial").select("version, publicada_at, notas").order("version", { ascending: false }),
    ]);
    if (c.error !== null || lista.error !== null) {
      setError(mensajeDeError(c.error ?? lista.error, "cargar las versiones"));
      setCargando(false);
      return;
    }
    setCuadro(c.data as unknown as Cuadro);

    const filas = (lista.data ?? []) as { version: number; publicada_at: string; notas: string | null }[];
    const conAcuses = await Promise.all(
      filas.map(async (f) => {
        const { data } = await supabase.rpc("fn_acuses_politica_salarial", { p_version: f.version });
        const personas = (data as { personas?: { acusado_at: string | null }[] } | null)?.personas ?? [];
        return {
          ...f,
          total_personas: personas.length,
          total_acuses: personas.filter((p) => p.acusado_at !== null).length,
        };
      }),
    );
    setVersiones(conAcuses);
    if (conAcuses.length >= 2) { setCompDer(conAcuses[0].version); setCompIzq(conAcuses[1].version); }
    setCargando(false);
  }, []);

  useEffect(() => {
    const cancelado = { actual: false };
    (async () => {
      const supabase = createAdminSupabaseClient();
      setError(null);
      const [c, lista] = await Promise.all([
        supabase.rpc("fn_cuadro_categorias"),
        supabase.from("politica_salarial").select("version, publicada_at, notas").order("version", { ascending: false }),
      ]);
      if (cancelado.actual) return;
      if (c.error !== null || lista.error !== null) {
        setError(mensajeDeError(c.error ?? lista.error, "cargar las versiones"));
        setCargando(false);
        return;
      }
      setCuadro(c.data as unknown as Cuadro);

      const filas = (lista.data ?? []) as { version: number; publicada_at: string; notas: string | null }[];
      const conAcuses = await Promise.all(
        filas.map(async (f) => {
          const { data } = await supabase.rpc("fn_acuses_politica_salarial", { p_version: f.version });
          const personas = (data as { personas?: { acusado_at: string | null }[] } | null)?.personas ?? [];
          return {
            ...f,
            total_personas: personas.length,
            total_acuses: personas.filter((p) => p.acusado_at !== null).length,
          };
        }),
      );
      if (cancelado.actual) return;
      setVersiones(conAcuses);
      if (conAcuses.length >= 2) { setCompDer(conAcuses[0].version); setCompIzq(conAcuses[1].version); }
      setCargando(false);
    })();
    return () => { cancelado.actual = true; };
  }, []);

  const hoy = useMemo(() => new Intl.DateTimeFormat("es-PE", { day: "numeric", month: "long", year: "numeric", timeZone: TZ_LIMA }).format(new Date()), []);
  const docVivo: Documento | null = useMemo(() => (cuadro ? construirDocumento(cuadro, hoy) : null), [cuadro, hoy]);

  const ultima = versiones[0];
  const [contenidoCambio, setContenidoCambio] = useState<boolean | null>(null);

  const abrirModal = async () => {
    if (!docVivo) return;
    if (ultima) {
      const supabase = createAdminSupabaseClient();
      const { data } = await supabase.from("politica_salarial").select("documento").eq("version", ultima.version).maybeSingle();
      const publicadoDoc = data?.documento ? documentoDesdeGuardado(data.documento as string) : null;
      setContenidoCambio(publicadoDoc ? documentoTieneCambios(docVivo, publicadoDoc) : true);
    } else {
      setContenidoCambio(true);
    }
    setModalAbierto(true);
  };

  const publicar = async () => {
    if (!docVivo) return;
    setPublicando(true); setError(null); setAviso(null);
    const supabase = createAdminSupabaseClient();
    const { data, error: e } = await supabase.rpc("fn_publicar_politica_salarial", { p_documento: documentoAJson(docVivo), p_notas: null });
    if (e !== null) {
      setError(mensajeDeError(e, "publicar la política salarial"));
    } else {
      const r = data as { version: number; nueva: boolean };
      setAviso(r.nueva
        ? `Se publicó la versión ${r.version}. Las constancias se piden de nuevo.`
        : `No había cambios de contenido — sigue siendo la versión ${r.version}. No hizo falta pedir constancias otra vez.`);
      setModalAbierto(false);
      await cargar();
    }
    setPublicando(false);
  };

  const comparar = async () => {
    if (compIzq === null || compDer === null || compIzq === compDer) { setCambios(null); return; }
    setComparando(true);
    const supabase = createAdminSupabaseClient();
    const [a, b] = compIzq > compDer ? [compIzq, compDer] : [compDer, compIzq];
    const [ra, rb] = await Promise.all([
      supabase.from("politica_salarial").select("documento").eq("version", a).maybeSingle(),
      supabase.from("politica_salarial").select("documento").eq("version", b).maybeSingle(),
    ]);
    const da = ra.data?.documento ? documentoDesdeGuardado(ra.data.documento as string) : null;
    const db = rb.data?.documento ? documentoDesdeGuardado(rb.data.documento as string) : null;
    setCambios(da && db ? seccionesCambiadas(da, db) : null);
    setComparando(false);
  };

  if (cargando) return <Cargando />;

  if (persona !== null && !esDO) {
    return (
      <main className="mx-auto max-w-2xl px-4 py-8">
        <p className="rounded-superficie border border-sand bg-papel px-4 py-6 text-sm text-taupe">
          Esta pantalla es solo para quien puede publicar la política salarial.
        </p>
      </main>
    );
  }

  return (
    <main className="mx-auto max-w-4xl px-4 py-8">
      <CabeceraPagina titulo="Versiones y publicación" descripcion="Cada versión queda registrada con su fecha; las anteriores se conservan tal como se comunicaron." />
      <SubnavPoliticaSalarial />

      {error !== null && <p className="mb-4 rounded-control border border-rojo/30 bg-rojo/10 px-4 py-3 text-sm text-rojo">{error}</p>}
      {aviso !== null && <p className="mb-4 rounded-control border border-verde/25 bg-verde/10 px-4 py-3 text-sm text-verde">{aviso}</p>}

      <section className="mb-8 rounded-superficie border border-sand bg-papel p-5">
        <h2 className="mb-2 font-serif text-lg text-tinta">Publicar</h2>
        <p className="mb-4 text-sm text-taupe">
          {ultima ? `Hoy hay ${versiones.length} ${versiones.length === 1 ? "versión publicada" : "versiones publicadas"}, la vigente es la ${ultima.version}.` : "Todavía no se publicó ninguna versión."}
        </p>
        <Boton variante="primario" onClick={() => void abrirModal()} disabled={!docVivo}>
          {ultima ? "Publicar" : "Publicar la primera versión"}
        </Boton>
      </section>

      <Modal abierto={modalAbierto} onCerrar={() => setModalAbierto(false)} titulo="Publicar política salarial" bloqueado={publicando}>
        {contenidoCambio === null ? (
          <Cargando texto="Comparando con lo publicado…" />
        ) : contenidoCambio ? (
          <div className="flex flex-col gap-4">
            <BannerAviso variante="advertencia" titulo={ultima ? `Esto creará la versión ${ultima.version + 1}` : "Esto publicará la primera versión"}>
              <p className="text-sm">
                {ultima
                  ? `El contenido cambió respecto a lo publicado. Las ${ultima.total_personas} personas obligadas van a tener que dejar constancia de nuevo.`
                  : "A partir de acá, cada persona obligada va a poder dejar constancia de haberla recibido."}
              </p>
            </BannerAviso>
            <div className="flex justify-end gap-2">
              <Boton variante="secundario" onClick={() => setModalAbierto(false)}>Cancelar</Boton>
              <Boton variante="primario" onClick={() => void publicar()} cargando={publicando}>Publicar versión nueva</Boton>
            </div>
          </div>
        ) : (
          <div className="flex flex-col gap-4">
            <BannerAviso variante="informativo" titulo="No hay cambios de contenido">
              <p className="text-sm">Lo que se publicaría dice exactamente lo mismo que la versión {ultima?.version}. No se va a crear una versión nueva ni se van a reiniciar las constancias.</p>
            </BannerAviso>
            <div className="flex justify-end gap-2">
              <Boton variante="secundario" onClick={() => setModalAbierto(false)}>Cancelar</Boton>
              <Boton variante="primario" onClick={() => void publicar()} cargando={publicando}>Confirmar de todas formas</Boton>
            </div>
          </div>
        )}
      </Modal>

      <section className="mb-8">
        <h2 className="mb-3 font-serif text-lg text-tinta">Historial</h2>
        <Tabla>
          <TablaEncabezado><Th>Versión</Th><Th>Estado</Th><Th>Publicada</Th><Th>Constancias</Th><Th>Notas</Th><Th></Th></TablaEncabezado>
          <tbody>
            {versiones.map((v, i) => (
              <Fila key={v.version}>
                <td className="px-4 py-2 text-tinta">{v.version}</td>
                <td className="px-4 py-2"><Insignia variante={i === 0 ? "positivo" : "neutral"}>{i === 0 ? "Vigente" : "Histórica"}</Insignia></td>
                <td className="px-4 py-2 text-tinta">{fechaLarga(v.publicada_at)}</td>
                <td className="px-4 py-2 text-tinta">{v.total_acuses} / {v.total_personas}</td>
                <td className="px-4 py-2 text-taupe">{v.notas ?? "—"}</td>
                <td className="px-4 py-2 text-right">
                  <Link href={`/admin/politica-salarial/versiones/${v.version}`} className="text-sm text-taupe underline underline-offset-2 hover:text-tinta">Ver</Link>
                </td>
              </Fila>
            ))}
            {versiones.length === 0 && (
              <Fila><td colSpan={6} className="px-4 py-6 text-center text-sm text-taupe">Sin versiones todavía.</td></Fila>
            )}
          </tbody>
        </Tabla>
      </section>

      {versiones.length >= 2 && (
        <section className="rounded-superficie border border-sand bg-papel p-5">
          <h2 className="mb-3 font-serif text-lg text-tinta">Qué cambió entre dos versiones</h2>
          <div className="mb-4 flex flex-wrap items-center gap-3">
            <select value={compIzq ?? ""} onChange={(e) => setCompIzq(Number(e.target.value))} className="rounded-control border border-sand bg-hueso px-3 py-2 text-sm text-tinta">
              {versiones.map((v) => <option key={v.version} value={v.version}>v{v.version}</option>)}
            </select>
            <span className="font-serif italic text-taupe">vs</span>
            <select value={compDer ?? ""} onChange={(e) => setCompDer(Number(e.target.value))} className="rounded-control border border-sand bg-hueso px-3 py-2 text-sm text-tinta">
              {versiones.map((v) => <option key={v.version} value={v.version}>v{v.version}</option>)}
            </select>
            <Boton variante="secundario" tamano="sm" onClick={() => void comparar()} cargando={comparando}>Comparar</Boton>
          </div>
          {cambios !== null && (
            cambios.size === 0 ? (
              <p className="text-sm text-taupe">Las dos versiones dicen exactamente lo mismo.</p>
            ) : (
              <ul className="list-disc space-y-1 pl-6 text-sm text-tinta">
                {[...cambios].map((t) => <li key={t}>{t}</li>)}
              </ul>
            )
          )}
        </section>
      )}
    </main>
  );
}

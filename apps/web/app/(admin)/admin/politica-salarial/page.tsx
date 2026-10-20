"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { ROLES_DO, TZ_LIMA, puedeEstamparFirmaDeEmpresa } from "@cayla-dynamic/shared";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { Cargando } from "@/components/cargando";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { Boton } from "@/components/ui/boton";
import { Campo } from "@/components/ui/campo";
import { Insignia } from "@/components/ui/insignia";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { Rotulo } from "@/components/ui/rotulo";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { cx } from "@/components/ui/cx";
import { SubnavPoliticaSalarial } from "./_subnav";
import { BloqueVista } from "./_documento-vista";
import {
  NOMBRE_RANGO,
  categoriasFueraDeOrden,
  categoriaSueldoDesalineado,
  construirDocumento,
  documentoDesdeGuardado,
  documentoTieneCambios,
  buscarSecciones,
  seccionSlug,
  type CategoriaCuadro,
  type Cuadro,
  type Documento,
} from "@/lib/politica-salarial";

// El documento se lee acá. Publicar, comparar versiones y editar categorías
// viven en pantallas propias (ver _subnav.tsx) — esta pantalla es "Documento
// vigente" nada más, para que leerlo no obligue a ver controles de Gerencia.
//
// "La escala", "Cómo se aplica cada criterio a cada categoría" y "Las
// categorías" se pintan con widgets propios (matriz+comparador+cards,
// resumen+detalle) en vez del renderizador genérico de bloques, usando el
// CUADRO EN VIVO — que en el caso normal (nada quedó "desactualizado") dice
// exactamente lo mismo que el documento publicado. El resto de las secciones
// —las legales, las que no cambian de forma con los datos— siguen saliendo
// del documento CONGELADO cuando hay uno vigente: esa es la prueba que se
// entregó, y no se regenera.

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

function fechaLarga(iso: string): string {
  return new Intl.DateTimeFormat("es-PE", {
    day: "numeric", month: "long", year: "numeric", timeZone: TZ_LIMA,
  }).format(new Date(iso));
}

function fechaHora(iso: string): string {
  return new Intl.DateTimeFormat("es-PE", {
    day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: TZ_LIMA,
  }).format(new Date(iso));
}

/** Un Set con una clave agregada o quitada, sin mutar el original. */
function alternar<T>(set: Set<T>, clave: T): Set<T> {
  const next = new Set(set);
  if (next.has(clave)) next.delete(clave); else next.add(clave);
  return next;
}

function soles(n: number | string | null | undefined): string {
  if (n === null || n === undefined) return "—";
  const v = typeof n === "string" ? Number(n) : n;
  return Number.isFinite(v) ? `S/ ${v.toFixed(2)}` : "—";
}

// ── El índice ────────────────────────────────────────────────────────────
function IndiceSticky({
  titulos, activo, onIr,
}: { titulos: string[]; activo: string | null; onIr: (t: string) => void }) {
  return (
    <>
      {/* Desktop: columna fija que se desplaza con la página. */}
      <nav className="hidden w-56 shrink-0 lg:block">
        <div className="sticky top-6 flex flex-col gap-0.5 border-l border-sand pl-4">
          {titulos.map((t) => (
            <button
              key={t}
              onClick={() => onIr(t)}
              className={cx(
                "-ml-4 border-l-2 py-1 pl-[14px] text-left text-sm transition-colors duration-150",
                activo === t ? "border-rojo font-medium text-tinta" : "border-transparent text-taupe hover:text-tinta",
              )}
            >
              {t}
            </button>
          ))}
        </div>
      </nav>
      {/* Mobile/tablet: selector desplegable. */}
      <div className="mb-4 lg:hidden">
        <select
          value=""
          onChange={(e) => { if (e.target.value) onIr(e.target.value); }}
          className="w-full rounded-control border border-sand bg-hueso px-3 py-2 text-base text-tinta sm:text-sm"
        >
          <option value="">Ir a una sección…</option>
          {titulos.map((t) => <option key={t} value={t}>{t}</option>)}
        </select>
      </div>
    </>
  );
}

// ── Una sección colapsable con ancla ────────────────────────────────────────
// El ancla es su propio `id` (seccionSlug), no una ref en un Map: alcanza con
// document.getElementById para desplazarse, sin mantener una referencia aparte.
function SeccionColapsable({
  titulo, abierta, onToggle, children,
}: { titulo: string; abierta: boolean; onToggle: () => void; children: React.ReactNode }) {
  return (
    <div id={seccionSlug(titulo)} className="mb-3 scroll-mt-6 rounded-superficie border border-sand bg-papel print:rounded-none print:border-0 print:mb-6">
      <button
        onClick={onToggle}
        className="flex w-full items-center justify-between gap-3 px-5 py-4 text-left print:hidden"
      >
        <h3 className="font-serif text-lg font-medium text-tinta">{titulo}</h3>
        <span className="shrink-0 text-taupe">{abierta ? "−" : "+"}</span>
      </button>
      <div className={cx("px-5 pb-5", !abierta && "hidden", "print:block print:px-0")}>
        <h3 className="mb-3 hidden font-serif text-lg font-medium text-tinta print:block print:break-after-avoid">{titulo}</h3>
        {children}
      </div>
    </div>
  );
}

// ── Matriz de categorías: cards + tabla completa + comparador ──────────────
function MatrizCategorias({ cats, esDO }: { cats: CategoriaCuadro[]; esDO: boolean }) {
  const [izq, setIzq] = useState(cats[1]?.rango ?? cats[0]?.rango ?? "");
  const [der, setDer] = useState(cats[2]?.rango ?? cats[cats.length - 1]?.rango ?? "");
  const factores = cats[0]?.factores.map((f) => f.factor) ?? [];
  const catIzq = cats.find((c) => c.rango === izq);
  const catDer = cats.find((c) => c.rango === der);

  return (
    <div>
      {/* Cards — vistazo rápido */}
      <div className="mb-6 grid grid-cols-2 gap-3 sm:grid-cols-3">
        {cats.map((c) => {
          const desalineado = esDO ? categoriaSueldoDesalineado(c) : null;
          return (
            <div key={c.rango} className="rounded-control border border-sand bg-hueso p-3">
              <div className="font-serif text-base text-tinta">{NOMBRE_RANGO[c.rango] ?? c.rango}</div>
              <div className="mt-0.5 text-sm font-semibold text-rojo">{soles(c.salario_declarado)}</div>
              {desalineado && (
                <div className="mt-1 text-[11px] text-ambar">
                  {desalineado === "por_debajo" ? "Alguien cobra menos de lo declarado" : "Alguien cobra más de lo declarado"}
                </div>
              )}
            </div>
          );
        })}
      </div>

      {/* Tabla completa */}
      {factores.length > 0 && (
        <div className="mb-6 overflow-x-auto rounded-superficie border border-sand">
          <table className="w-full min-w-[560px] border-collapse text-sm">
            <thead>
              <tr>
                <th className="border border-sand bg-hueso px-3 py-2 text-left font-medium text-taupe">Criterio</th>
                {cats.map((c) => <th key={c.rango} className="border border-sand bg-sand/70 px-3 py-2 text-left font-semibold text-tinta">{NOMBRE_RANGO[c.rango] ?? c.rango}</th>)}
              </tr>
            </thead>
            <tbody>
              {factores.map((nombreFactor) => (
                <tr key={nombreFactor}>
                  <th className="border border-sand bg-hueso px-3 py-2 text-left font-medium text-taupe">{nombreFactor}</th>
                  {cats.map((c) => (
                    <td key={c.rango} className="border border-sand px-3 py-2 align-top text-tinta">
                      {c.factores.find((f) => f.factor === nombreFactor)?.nivel ?? "—"}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Comparador */}
      <TarjetaInfo>
        <Rotulo como="div" className="mb-3">Comparar dos categorías</Rotulo>
        <div className="mb-4 flex flex-wrap items-center gap-3">
          <select value={izq} onChange={(e) => setIzq(e.target.value)} className="rounded-control border border-sand bg-hueso px-3 py-2 text-sm text-tinta">
            {cats.map((c) => <option key={c.rango} value={c.rango}>{NOMBRE_RANGO[c.rango] ?? c.rango}</option>)}
          </select>
          <span className="font-serif italic text-taupe">vs</span>
          <select value={der} onChange={(e) => setDer(e.target.value)} className="rounded-control border border-sand bg-hueso px-3 py-2 text-sm text-tinta">
            {cats.map((c) => <option key={c.rango} value={c.rango}>{NOMBRE_RANGO[c.rango] ?? c.rango}</option>)}
          </select>
        </div>
        <div className="flex flex-col gap-2">
          {factores.map((nombreFactor) => (
            <div key={nombreFactor} className="grid grid-cols-1 gap-2 text-sm sm:grid-cols-[1fr_1.3fr_1.3fr]">
              <div className="pt-2 font-medium text-taupe">{nombreFactor}</div>
              <div className="rounded-control bg-hueso px-3 py-2 leading-snug text-tinta">
                {catIzq?.factores.find((f) => f.factor === nombreFactor)?.nivel ?? "—"}
              </div>
              <div className="rounded-control bg-hueso px-3 py-2 leading-snug text-tinta">
                {catDer?.factores.find((f) => f.factor === nombreFactor)?.nivel ?? "—"}
              </div>
            </div>
          ))}
        </div>
      </TarjetaInfo>
    </div>
  );
}

// ── Categorías: resumen siempre visible + detalle expandible por chip ──────
function CategoriasDetalle({ cats }: { cats: CategoriaCuadro[] }) {
  const [abiertos, setAbiertos] = useState<Set<string>>(new Set());
  const toggle = (clave: string) => setAbiertos((prev) => {
    const next = new Set(prev);
    if (next.has(clave)) next.delete(clave); else next.add(clave);
    return next;
  });
  const lineas = (t: string | null) => (t ?? "").split("\n").map((l) => l.trim()).filter(Boolean);

  return (
    <div className="flex flex-col gap-3">
      {cats.map((c) => {
        const nombre = NOMBRE_RANGO[c.rango] ?? c.rango;
        return (
          <div key={c.rango} className="rounded-control border border-sand bg-papel p-4">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <div className="font-serif text-lg text-tinta">{nombre}</div>
                <div className="text-sm text-taupe">{c.proposito}</div>
              </div>
              <div className="whitespace-nowrap text-sm font-semibold text-rojo">{soles(c.salario_declarado)}</div>
            </div>
            <div className="mt-3 flex flex-wrap gap-2">
              {(["funciones", "requisitos", "criterio"] as const).map((campo) => {
                const clave = `${c.rango}:${campo}`;
                const etiqueta = campo === "funciones" ? "Ver funciones" : campo === "requisitos" ? "Ver requisitos" : "¿Por qué vale más?";
                return (
                  <button
                    key={campo}
                    onClick={() => toggle(clave)}
                    className={cx(
                      "rounded-full border px-3 py-1 text-xs font-medium transition-colors duration-150",
                      abiertos.has(clave) ? "border-rojo text-rojo" : "border-sand bg-hueso text-taupe hover:text-tinta",
                    )}
                  >
                    {etiqueta}
                  </button>
                );
              })}
            </div>
            {abiertos.has(`${c.rango}:funciones`) && (
              <ul className="mt-3 list-disc space-y-1 border-t border-sand pl-6 pt-3 text-sm leading-relaxed text-tinta">
                {lineas(c.funciones).map((l, i) => <li key={i}>{l}</li>)}
              </ul>
            )}
            {abiertos.has(`${c.rango}:requisitos`) && (
              <ul className="mt-3 list-disc space-y-1 border-t border-sand pl-6 pt-3 text-sm leading-relaxed text-tinta">
                {lineas(c.requisitos).map((l, i) => <li key={i}>{l}</li>)}
              </ul>
            )}
            {abiertos.has(`${c.rango}:criterio`) && (
              <p className="mt-3 border-t border-sand pt-3 text-sm leading-relaxed text-tinta">{c.criterio}</p>
            )}
          </div>
        );
      })}
    </div>
  );
}

// ── Portal del colaborador ──────────────────────────────────────────────────
function PortalColaborador({ cats, miRango }: { cats: CategoriaCuadro[]; miRango: string }) {
  const [verDiferencias, setVerDiferencias] = useState(false);
  const actual = cats.find((c) => c.rango === miRango);
  const siguiente = actual ? cats.find((c) => c.orden === actual.orden + 1) : undefined;
  if (!actual) return null;

  return (
    <div className="mb-6 rounded-superficie border border-tinta/15 bg-hueso p-5">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div>
          <div className="text-xs font-semibold uppercase tracking-wide text-taupe">Tu categoría</div>
          <div className="mt-1 font-serif text-xl text-tinta">{NOMBRE_RANGO[actual.rango] ?? actual.rango}</div>
          <div className="text-sm font-medium text-rojo">{soles(actual.salario_declarado)}</div>
        </div>
        {siguiente ? (
          <div>
            <div className="text-xs font-semibold uppercase tracking-wide text-taupe">Siguiente categoría</div>
            <div className="mt-1 font-serif text-xl text-tinta">{NOMBRE_RANGO[siguiente.rango] ?? siguiente.rango}</div>
            <button onClick={() => setVerDiferencias((v) => !v)} className="text-sm text-taupe underline underline-offset-2 hover:text-tinta">
              {verDiferencias ? "Ocultar diferencias" : "Ver diferencias →"}
            </button>
          </div>
        ) : (
          <div className="text-sm text-taupe">Ya estás en la categoría más alta de la escala.</div>
        )}
      </div>
      {verDiferencias && siguiente && (
        <div className="mt-4 flex flex-col gap-2 border-t border-sand pt-4">
          {actual.factores.map((f) => (
            <div key={f.factor} className="grid grid-cols-1 gap-2 text-sm sm:grid-cols-[1fr_1.3fr_1.3fr]">
              <div className="pt-2 font-medium text-taupe">{f.factor}</div>
              <div className="rounded-control bg-papel px-3 py-2 leading-snug text-tinta">{f.nivel}</div>
              <div className="rounded-control bg-papel px-3 py-2 leading-snug text-tinta">
                {siguiente.factores.find((sf) => sf.factor === f.factor)?.nivel ?? "—"}
              </div>
            </div>
          ))}
        </div>
      )}
      <p className="mt-4 text-xs text-taupe">
        Esto describe la categoría, no una promesa de ascenso: cómo se cambia de categoría se explica más abajo.
      </p>
    </div>
  );
}

export default function PoliticaSalarialPage() {
  useTituloDocumento("Política salarial");
  const persona = usePersonaActual();
  const esDO = persona !== null && ROLES_DO.includes(persona.rol);

  const [cuadro, setCuadro] = useState<Cuadro | null>(null);
  const [vigente, setVigente] = useState<Vigente | null>(null);
  const [miRango, setMiRango] = useState<string | null>(null);
  // La firma de quien firma por CAYLA (`fn_firma_empresa`), no la de quien mira:
  // sale de la misma fila que el nombre del firmante (0147), así que la firma de
  // una persona no cae bajo el nombre de otra. Antes solo se veía si Felipe
  // tenía la sesión abierta; ahora la ve quien abre el panel con rol que la
  // estampa (Gerencia, DO, líder de equipo).
  const [firmaUrl, setFirmaUrl] = useState<string | null>(null);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  // Derivado de `persona`, no sincronizado por efecto (ver el comentario del
  // efecto de montaje más abajo): mientras la persona no haya editado nada,
  // el campo muestra su nombre completo; en cuanto escribe algo, gana lo que
  // escribió.
  const [nombreAcuseEditado, setNombreAcuseEditado] = useState<string | null>(null);
  const nombreAcuse = nombreAcuseEditado ?? persona?.nombreCompleto ?? "";
  const [guardando, setGuardando] = useState(false);
  const [busqueda, setBusqueda] = useState("");
  const [abiertas, setAbiertas] = useState<Set<string>>(new Set());
  const [seccionActiva, setSeccionActiva] = useState<string | null>(null);

  // useCallback: la reutiliza `acusar()` para refrescar DESPUÉS de mutar.
  // El efecto de montaje, justo abajo, NO LA LLAMA — referenciar desde un
  // efecto una función (useCallback o no) que termina llamando a un setState
  // dispara el lint react-hooks/set-state-in-effect; pide los mismos datos
  // en línea (mismo motivo documentado en admin/objetivos/page.tsx).
  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    setError(null);
    const [c, v, f, r] = await Promise.all([
      supabase.rpc("fn_cuadro_categorias"),
      supabase.rpc("fn_politica_salarial_vigente"),
      supabase.rpc("fn_firma_empresa"),
      supabase.rpc("fn_mi_rango_actual"),
    ]);
    if (c.error !== null || v.error !== null) {
      setError(mensajeDeError(c.error ?? v.error, "cargar la política salarial"));
      setCargando(false);
      return;
    }
    setCuadro(c.data as unknown as Cuadro);
    setVigente(v.data as unknown as Vigente);
    setFirmaUrl(typeof f.data === "string" && f.data.startsWith("data:image") ? f.data : null);
    setMiRango(typeof r.data === "string" ? r.data : null);
    setCargando(false);
  }, []);

  useEffect(() => {
    if (persona === null) return;
    const cancelado = { actual: false };
    (async () => {
      const supabase = createAdminSupabaseClient();
      setError(null);
      const [c, v, f, r] = await Promise.all([
        supabase.rpc("fn_cuadro_categorias"),
        supabase.rpc("fn_politica_salarial_vigente"),
        supabase.rpc("fn_firma_empresa"),
        supabase.rpc("fn_mi_rango_actual"),
      ]);
      if (cancelado.actual) return;
      if (c.error !== null || v.error !== null) {
        setError(mensajeDeError(c.error ?? v.error, "cargar la política salarial"));
        setCargando(false);
        return;
      }
      setCuadro(c.data as unknown as Cuadro);
      setVigente(v.data as unknown as Vigente);
      setFirmaUrl(typeof f.data === "string" && f.data.startsWith("data:image") ? f.data : null);
      setMiRango(typeof r.data === "string" ? r.data : null);
      setCargando(false);
    })();
    return () => { cancelado.actual = true; };
  }, [persona]);

  const hoy = useMemo(
    () => new Intl.DateTimeFormat("es-PE", { day: "numeric", month: "long", year: "numeric", timeZone: TZ_LIMA }).format(new Date()),
    [],
  );

  const docVivo: Documento | null = useMemo(() => (cuadro ? construirDocumento(cuadro, hoy) : null), [cuadro, hoy]);
  const fueraDeOrden = useMemo(() => (cuadro ? categoriasFueraDeOrden(cuadro.categorias) : []), [cuadro]);
  const publicadoDoc: Documento | null = useMemo(() => (vigente?.documento ? documentoDesdeGuardado(vigente.documento) : null), [vigente]);

  const desactualizada = useMemo(() => {
    if (vigente === null || !vigente.publicada) return false;
    if (docVivo === null) return false;
    if (publicadoDoc === null) return vigente.desactualizada;
    return documentoTieneCambios(docVivo, publicadoDoc);
  }, [vigente, docVivo, publicadoDoc]);

  // Lo que se lee: lo publicado (si existe y no quedó desactualizado), o lo
  // vivo. Las secciones de escala/matriz/categorías se re-pintan aparte con
  // el cuadro en vivo (ver comentario arriba del archivo).
  const doc: Documento | null = vigente?.publicada && !desactualizada && publicadoDoc ? publicadoDoc : docVivo;

  // "La escala" no tiene ancla propia: su contenido se muestra fusionado bajo
  // el título de la matriz (ver el mapeo de doc.secciones más abajo), así que
  // un resultado de búsqueda ahí apunta a esa sección en su lugar.
  const resultadosBusqueda = useMemo(() => {
    if (!doc) return [];
    const titulos = buscarSecciones(doc, busqueda).map((t) =>
      t === "La escala" ? "Cómo se aplica cada criterio a cada categoría" : t,
    );
    return [...new Set(titulos)];
  }, [doc, busqueda]);

  const irA = useCallback((titulo: string) => {
    setAbiertas((prev) => new Set(prev).add(titulo));
    setSeccionActiva(titulo);
    requestAnimationFrame(() => {
      document.getElementById(seccionSlug(titulo))?.scrollIntoView({ behavior: "smooth", block: "start" });
    });
  }, []);

  const acusar = async () => {
    setGuardando(true); setError(null); setAviso(null);
    const supabase = createAdminSupabaseClient();
    const { error: e } = await supabase.rpc("fn_acusar_politica_salarial", { p_nombre: nombreAcuse });
    if (e !== null) setError(mensajeDeError(e, "registrar tu constancia"));
    else { setAviso("Gracias. Tu constancia quedó registrada."); await cargar(); }
    setGuardando(false);
  };

  if (cargando) return <Cargando />;

  return (
    <main className="w-full px-6 pb-8 pt-6 print:max-w-none print:p-0">
      <div className="print:hidden">
        <CabeceraPagina
          titulo="Política salarial"
          descripcion="Cómo se organiza el trabajo en CAYLA y cómo se determina lo que gana cada persona."
          accion={<Boton variante="secundario" tamano="sm" onClick={() => window.print()}>Imprimir / Guardar como PDF</Boton>}
        />
        {esDO && <SubnavPoliticaSalarial />}

        {vigente !== null && vigente.publicada && (
          <div className="mb-6 flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-taupe">
            <span>Versión <strong className="text-tinta">{vigente.version}</strong> · publicada el {vigente.publicada_at ? fechaLarga(vigente.publicada_at) : "—"}</span>
            <Insignia variante={desactualizada ? "advertencia" : "positivo"}>{desactualizada ? "Desactualizada" : "Vigente"}</Insignia>
            <span>Constancias: <strong className="text-tinta">{vigente.total_acuses ?? 0}</strong> / {vigente.total_personas ?? 0}</span>
            <Link href="/admin/politica-salarial/constancias" className="underline underline-offset-2 hover:text-tinta">ver constancias</Link>
          </div>
        )}

        {vigente !== null && !vigente.publicada && (
          <BannerAviso variante="alerta" titulo="Todavía no hay ninguna versión publicada" className="mb-6">
            <p className="text-sm">Lo que ves abajo es una vista previa. {esDO ? <Link className="underline" href="/admin/politica-salarial/versiones">Publícala desde Versiones y publicación</Link> : "Avisa a Desarrollo Organizacional."}</p>
          </BannerAviso>
        )}

        {esDO && desactualizada && vigente?.publicada && (
          <BannerAviso variante="advertencia" titulo="El cuadro cambió después de publicar" className="mb-6">
            <p className="text-sm">Alguna categoría, remuneración o tarifa ya no coincide con la versión vigente. <Link className="underline" href="/admin/politica-salarial/versiones">Publica una versión nueva</Link> — las constancias se piden de nuevo.</p>
          </BannerAviso>
        )}

        {esDO && fueraDeOrden.length > 0 && (
          <BannerAviso variante="advertencia" titulo="La escala no sube con la categoría" className="mb-6">
            <p className="text-sm">
              {fueraDeOrden.length === 1 ? `${fueraDeOrden[0]} tiene una remuneración declarada igual o menor que la de la categoría anterior.` : `Estas categorías tienen una remuneración declarada igual o menor que la anterior: ${fueraDeOrden.join(", ")}.`}
              {" "}Corrígelo en <Link className="underline" href="/admin/politica-salarial/categorias">Categorías</Link> antes de publicar.
            </p>
          </BannerAviso>
        )}

        {error !== null && <p className="mb-4 rounded-control border border-rojo/30 bg-rojo/10 px-4 py-3 text-sm text-rojo">{error}</p>}
        {aviso !== null && <p className="mb-4 rounded-control border border-verde/25 bg-verde/10 px-4 py-3 text-sm text-verde">{aviso}</p>}

        <Campo
          type="search"
          placeholder="Buscar en la política…"
          value={busqueda}
          onChange={(e) => setBusqueda(e.target.value)}
          className="mb-2"
        />
        {busqueda.trim() !== "" && (
          <div className="mb-6 rounded-control border border-sand bg-papel p-2">
            {resultadosBusqueda.length === 0 ? (
              <p className="px-2 py-1 text-sm text-taupe">Sin resultados para &ldquo;{busqueda}&rdquo;.</p>
            ) : resultadosBusqueda.map((t) => (
              <button key={t} onClick={() => irA(t)} className="block w-full rounded-control px-2 py-1.5 text-left text-sm text-tinta hover:bg-sand/40">{t}</button>
            ))}
          </div>
        )}
      </div>

      {doc && (
        <div className="flex gap-8">
          <IndiceSticky
            titulos={doc.secciones.map((s) => s.titulo).filter((t) => t !== "La escala")}
            activo={seccionActiva}
            onIr={irA}
          />
          <div className="min-w-0 flex-1">
            {/* Cabecera del documento — se ve siempre, incluso al imprimir */}
            <header className="mb-6 border-b border-sand pb-4">
              <h2 className="font-serif text-lg font-semibold text-tinta">{doc.titulo}</h2>
              <p className="text-sm text-taupe">{doc.empresa.nombre} — RUC {doc.empresa.ruc}</p>
              <p className="text-sm text-taupe">{doc.fecha}</p>
            </header>

            {cuadro && miRango && (
              <div className="print:hidden">
                <PortalColaborador cats={cuadro.categorias} miRango={miRango} />
              </div>
            )}

            {doc.secciones.map((sec) => {
              // "La escala" y la matriz de factores se muestran juntas, una sola vez,
              // bajo el título de la matriz — evita repetir la remuneración dos veces
              // (ver hallazgo de la auditoría, Fase 6).
              if (sec.titulo === "La escala") return null;
              if (sec.titulo === "Cómo se aplica cada criterio a cada categoría") {
                return (
                  <SeccionColapsable
                    key={sec.titulo}
                    titulo={sec.titulo}
                    abierta={abiertas.has(sec.titulo)}
                    onToggle={() => setAbiertas((p) => alternar(p, sec.titulo))}
                  >
                    {cuadro ? <MatrizCategorias cats={cuadro.categorias} esDO={esDO} /> : sec.bloques.map((b, i) => <BloqueVista key={i} b={b} />)}
                  </SeccionColapsable>
                );
              }
              if (sec.titulo === "Las categorías") {
                return (
                  <SeccionColapsable
                    key={sec.titulo}
                    titulo={sec.titulo}
                    abierta={abiertas.has(sec.titulo)}
                    onToggle={() => setAbiertas((p) => alternar(p, sec.titulo))}
                  >
                    {cuadro ? <CategoriasDetalle cats={cuadro.categorias} /> : sec.bloques.map((b, i) => <BloqueVista key={i} b={b} />)}
                  </SeccionColapsable>
                );
              }
              return (
                <SeccionColapsable
                  key={sec.titulo}
                  titulo={sec.titulo}
                  abierta={abiertas.has(sec.titulo)}
                  onToggle={() => setAbiertas((p) => alternar(p, sec.titulo))}
                >
                  {sec.bloques.map((b, i) => <BloqueVista key={i} b={b} />)}
                </SeccionColapsable>
              );
            })}

            <footer className="mt-10 border-t border-sand pt-6 print:break-inside-avoid">
              {firmaUrl !== null && puedeEstamparFirmaDeEmpresa(persona?.rol) && (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={firmaUrl} alt="" className="mb-1 h-16 object-contain" />
              )}
              <p className="text-sm font-medium text-tinta">{doc.empresa.firmante}</p>
              <p className="text-sm text-taupe">{doc.empresa.cargo} — {doc.empresa.nombre}</p>
            </footer>

            {vigente !== null && vigente.publicada && (
              <TarjetaInfo como="section" titulo="Constancia de haber recibido este documento" className="mt-8 print:hidden">
                {vigente.mi_acuse !== null ? (
                  <p className="text-sm text-tinta">
                    Dejaste constancia el {fechaHora(vigente.mi_acuse.acusado_at)} como <strong>{vigente.mi_acuse.nombre}</strong>. No hace falta hacer nada más hasta que se publique una versión nueva.
                  </p>
                ) : (
                  <>
                    <p className="mb-3 text-sm text-tinta">
                      Escribe tu nombre para dejar constancia de que recibiste y leíste este documento. Dejar constancia no significa estar de acuerdo con su contenido: si tienes una discrepancia, puedes plantearla a la Gerencia y recibirás respuesta por escrito.
                    </p>
                    <div className="flex flex-wrap items-center gap-3">
                      <Campo type="text" value={nombreAcuse} onChange={(e) => setNombreAcuseEditado(e.target.value)} placeholder="Tu nombre completo" className="min-w-64 flex-1" />
                      <Boton variante="primario" onClick={() => void acusar()} disabled={guardando || nombreAcuse.trim() === ""} cargando={guardando}>Dejar constancia</Boton>
                    </div>
                  </>
                )}
              </TarjetaInfo>
            )}
          </div>
        </div>
      )}
    </main>
  );
}

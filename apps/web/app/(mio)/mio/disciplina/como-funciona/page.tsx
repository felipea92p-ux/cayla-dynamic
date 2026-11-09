"use client";

// «Cómo funciona la disciplina» — la guía de la colaboradora (2026-11-09).
//
// QUÉ PROMETE · explicar, sin lenguaje legal, cómo se pasa de una tardanza, una
//               inasistencia o una falta de conducta a una medida, con todos los
//               plazos y garantías, y decir arriba de todo qué versión del
//               Reglamento resume y si es la que rige hoy.
// QUÉ ASUME   · que el texto vive en `lib/guia-disciplina.ts` (lo vigila
//               `tests/guia-disciplina.test.ts` contra el Reglamento del repo) y
//               que el Reglamento vigente lo dice `fn_documentos_vigentes`, la
//               misma función de Normas.
// NO HACE     · calcular el plazo de nadie. El plazo real de cada persona está
//               en sus cargos (`/mio/cargos/[id]`); aquí solo se enseña la regla.
//
// Se abre desde la cabecera de Info › Disciplina y desde la pantalla de los
// cargos. No escribe nada en la base y no necesita sesión para leerse: sin
// sesión, solo deja de poder decir si la versión es la vigente.

import { Fragment, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { Check } from "lucide-react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { EnlaceVolver } from "@/components/enlace-volver";
import { fechaLarga } from "@/components/disciplina/memo-documento";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Cifra } from "@/components/ui/cifra";
import { cx } from "@/components/ui/cx";
import { Insignia } from "@/components/ui/insignia";
import { Rotulo } from "@/components/ui/rotulo";
import { Fila, Tabla, TablaEncabezado, Th } from "@/components/ui/tabla";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import {
  CARGOS, CONDUCTA, EJEMPLOS_DE_PLAZO, ESCALA, ESENCIAL, GARANTIAS, GUIA_REVISADA, INASISTENCIAS, PLAZOS, PREGUNTAS,
  REGLAMENTO_RESUMIDO, SOBRE_LA_ESCALA, SOBRE_LA_RECONSIDERACION, SOBRE_LOS_PLAZOS, TARDANZAS, estadoDeLaGuia,
  tiraDePlazo, trozos, type CeldaTira, type Escalon, type EstadoGuia, type Tono,
} from "@/lib/guia-disciplina";

const INDICE = [
  { id: "esencial", nombre: "Lo esencial" },
  { id: "tardanzas", nombre: "Tardanzas" },
  { id: "inasistencias", nombre: "Inasistencias" },
  { id: "conducta", nombre: "Conducta" },
  { id: "cargos", nombre: "Si te comunican cargos" },
  { id: "plazos", nombre: "Plazos" },
  { id: "garantias", nombre: "Tus garantías" },
  { id: "preguntas", nombre: "Preguntas" },
] as const;

// El tono de cada peldaño, en las mismas cuatro palabras que usan BannerAviso e Insignia.
const BORDE: Record<Tono, string> = {
  positivo: "border-l-verde",
  informativo: "border-l-pizarra",
  advertencia: "border-l-ambar",
  alerta: "border-l-rojo",
};
// Escritas enteras y no armadas con `replace`: Tailwind solo genera las clases que lee literales.
const BORDE_ARRIBA: Record<Tono, string> = {
  positivo: "border-t-verde",
  informativo: "border-t-pizarra",
  advertencia: "border-t-ambar",
  alerta: "border-t-rojo",
};
const PELDANO: Record<Tono, string> = {
  positivo: "bg-verde/15 text-verde",
  informativo: "bg-pizarra/15 text-pizarra",
  advertencia: "bg-ambar/15 text-ambar",
  alerta: "bg-rojo/10 text-rojo",
};

/** Un texto de la guía con sus marcas: `**negrita**` y `[[19.2]]` como cita chica. */
function Texto({ t }: { t: string }) {
  return (
    <>
      {trozos(t).map((x, i) =>
        x.tipo === "negrita" ? <b key={i} className="font-semibold">{x.valor}</b>
          : x.tipo === "ref" ? <Cita key={i} numerales={x.valor} />
            : <Fragment key={i}>{x.valor}</Fragment>,
      )}
    </>
  );
}

function Cita({ numerales }: { numerales: string }) {
  return <span className="whitespace-nowrap text-xs font-medium tabular-nums text-taupe">RIT {numerales}</span>;
}

/** Lo que va entre `[[ ]]` de un texto que es solo una cita («[[19.2]]» → «19.2»). */
const sinMarcas = (ref: string) => ref.replace(/^\[\[|\]\]$/g, "");

function Seccion({ id, titulo, bajada, children }: { id: string; titulo: string; bajada?: string; children: React.ReactNode }) {
  return (
    <section id={id} aria-labelledby={`${id}-titulo`} className="grid scroll-mt-4 gap-4 border-t border-sand pt-8">
      <div className="grid gap-1.5">
        <h2 id={`${id}-titulo`} className="font-serif text-2xl leading-tight">{titulo}</h2>
        {bajada && <p className="max-w-prose text-base text-taupe"><Texto t={bajada} /></p>}
      </div>
      {children}
    </section>
  );
}

function Subtitulo({ children, cita }: { children: React.ReactNode; cita?: string }) {
  return (
    <h3 className="mt-2 flex flex-wrap items-baseline gap-x-2 font-serif text-lg">
      {children}
      {cita && <Cita numerales={sinMarcas(cita)} />}
    </h3>
  );
}

function Lista({ items, className }: { items: readonly string[]; className?: string }) {
  return (
    <ul className={cx("grid list-disc gap-1.5 pl-5 marker:text-taupe", className)}>
      {items.map((t) => <li key={t}><Texto t={t} /></li>)}
    </ul>
  );
}

function Escalera({ escalones }: { escalones: readonly Escalon[] }) {
  return (
    <ol className="grid">
      {escalones.map((e) => (
        <li key={e.n}
          className="relative grid grid-cols-[2.25rem_minmax(0,1fr)] gap-3 pb-4 before:absolute before:bottom-0 before:left-[1.07rem] before:top-10 before:w-0.5 before:bg-sand last:pb-0 last:before:hidden">
          <span aria-hidden className={cx("flex size-9 items-center justify-center rounded-full text-base font-semibold tabular-nums", PELDANO[e.tono])}>
            {e.n}
          </span>
          <TarjetaInfo className={cx("min-w-0 border-l-4", BORDE[e.tono])}>
            <p className="flex flex-wrap items-baseline gap-x-2 gap-y-1 font-serif text-lg leading-snug">
              <span className="sr-only">Escalón {e.n}: </span>
              {e.medida}
              {e.duracion && <Insignia variante={e.tono} punto={false}>{e.duracion}</Insignia>}
            </p>
            <p className="mt-1"><Texto t={e.cuando} /></p>
            {e.nota && <p className="mt-1.5 text-taupe"><Texto t={e.nota} /></p>}
          </TarjetaInfo>
        </li>
      ))}
    </ol>
  );
}

const CELDA: Record<CeldaTira["clase"], { caja: string; etiqueta: string }> = {
  inicio: { caja: "border-tinta bg-tinta text-crema", etiqueta: "text-crema/80" },
  habil: { caja: "border-verde/50 bg-papel", etiqueta: "font-medium text-verde" },
  fuera: { caja: "border-dashed border-sand text-taupe", etiqueta: "text-taupe" },
  vence: { caja: "border-2 border-rojo bg-rojo/[0.06]", etiqueta: "font-semibold text-rojo" },
};

function TiraDeDias({ titulo, inicio }: { titulo: string; inicio: number }) {
  const celdas = tiraDePlazo(inicio);
  return (
    <figure className="grid gap-1.5">
      <figcaption className="font-medium">{titulo}</figcaption>
      <ol className="grid auto-cols-fr grid-flow-col gap-1.5">
        {celdas.map((c, i) => (
          <li key={i} className={cx("min-w-0 rounded-control border px-1 py-2 text-center", CELDA[c.clase].caja)}>
            <span className="block font-semibold">{c.dia}</span>
            <span className={cx("block text-[11px] leading-tight", CELDA[c.clase].etiqueta)}>{c.etiqueta}</span>
          </li>
        ))}
      </ol>
    </figure>
  );
}

function Sello({ estado }: { estado: EstadoGuia | "cargando" }) {
  const version = `versión ${REGLAMENTO_RESUMIDO.etiqueta}`;
  const desde = fechaLarga(REGLAMENTO_RESUMIDO.vigenteDesde);
  if (estado !== "cargando" && estado.clase === "desactualizada") {
    const rige = estado.vigente
      ? `la versión ${estado.vigente}`
      : estado.desde ? `otra versión, vigente desde el ${fechaLarga(estado.desde)}` : "otra versión";
    return (
      <BannerAviso variante="advertencia" titulo="Esta guía puede no estar al día con el Reglamento">
        <p>
          Explica la {version}, vigente desde el {desde}, y hoy rige {rige}. Mientras se revisa, ante cualquier
          diferencia vale lo que dice el Reglamento: léelo en{" "}
          <Link href="/admin/normas" className="underline underline-offset-2">Publicaciones › Normas</Link>.
        </p>
      </BannerAviso>
    );
  }
  return (
    <BannerAviso variante="neutral" enLinea>
      Resumen del <b className="font-semibold">Reglamento Interno de Trabajo, {version}</b>, vigente desde el {desde}
      {estado !== "cargando" && estado.clase === "al_dia" ? ", que es la que rige hoy" : ""}. Si algo de esta guía no
      coincide con el Reglamento, vale lo que dice el Reglamento; lo lees completo en{" "}
      <Link href="/admin/normas" className="underline underline-offset-2">Publicaciones › Normas</Link>. Los números como{" "}
      <Cita numerales="19.2" /> dicen en qué artículo está cada regla.
    </BannerAviso>
  );
}

export default function ComoFuncionaLaDisciplinaPage() {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const [estado, setEstado] = useState<EstadoGuia | "cargando">("cargando");

  useEffect(() => {
    let vigente = true;
    void (async () => {
      const { data: sesion } = await supabase.auth.getSession();
      if (!sesion.session) { if (vigente) setEstado({ clase: "sin_saber" }); return; }
      const { data, error } = await supabase.rpc("fn_documentos_vigentes");
      if (!vigente) return;
      // Sin dato no se afirma nada: un error o un Reglamento sin publicar dejan el sello neutro.
      const rit = error ? null
        : ((data ?? []) as { tipo: string; etiqueta_version: string | null; vigente_desde: string | null }[]).find((d) => d.tipo === "rit") ?? null;
      setEstado(estadoDeLaGuia(rit));
    })();
    return () => { vigente = false; };
  }, [supabase]);

  return (
    <main className="mx-auto grid w-full min-w-0 max-w-[760px] gap-8 px-4 py-6 text-sm leading-relaxed sm:p-6 sm:text-[15px]">
      <div className="grid gap-4">
        <EnlaceVolver href="/mio?tab=disciplina" className="text-sm text-taupe hover:text-tinta hover:underline">
          ← Volver a Disciplina
        </EnlaceVolver>
        <header className="grid gap-3">
          <Rotulo>Info · Disciplina</Rotulo>
          <h1 className="font-serif text-3xl leading-tight sm:text-4xl">Cómo funciona la disciplina</h1>
          <p className="max-w-prose text-base">
            Dynamic cuenta las tardanzas y las inasistencias, y avisa. No sanciona. Cualquier sanción la decide una
            persona, después de escucharte y con plazos que tú puedes ver en tu Info.
          </p>
        </header>
        <Sello estado={estado} />
        <nav aria-label="En esta guía">
          <ul className="flex flex-wrap gap-2">
            {INDICE.map((s) => (
              <li key={s.id}>
                <a href={`#${s.id}`} className="inline-block rounded-pildora border border-sand px-3 py-1 text-sm hover:border-taupe">{s.nombre}</a>
              </li>
            ))}
          </ul>
        </nav>
      </div>

      {/* ── Lo esencial ───────────────────────────────────────────────── */}
      <Seccion id="esencial" titulo="Lo esencial"
        bajada="El régimen disciplinario sirve para corregir y para dejar constancia de lo que pasó, no para castigar [[52.10]]. Estas seis reglas valen para todo lo que sigue.">
        <ul className="grid gap-3 sm:grid-cols-2">
          {ESENCIAL.map((b) => (
            <TarjetaInfo key={b.titulo} como="li">
              <h3 className="font-serif text-lg leading-snug">{b.titulo}</h3>
              <p className="mt-1"><Texto t={b.texto} /></p>
            </TarjetaInfo>
          ))}
        </ul>
        <Subtitulo cita="[[54.1]]">Las únicas sanciones que existen</Subtitulo>
        <ol className="flex flex-wrap items-center gap-2">
          {ESCALA.map((e, i) => (
            <li key={e.nombre} className="flex items-center gap-2">
              {i > 0 && <span aria-hidden className="text-taupe">→</span>}
              <Insignia atenuada={e.noEsSancion} punto={false}>{e.nombre}</Insignia>
            </li>
          ))}
        </ol>
        <p className="max-w-prose text-taupe"><Texto t={SOBRE_LA_ESCALA} /></p>
      </Seccion>

      {/* ── Tardanzas ─────────────────────────────────────────────────── */}
      <Seccion id="tardanzas" titulo="Tardanzas" bajada={TARDANZAS.bajada}>
        <div className="grid gap-2 sm:grid-cols-3" role="group" aria-label="Ejemplo con hora de ingreso 07:45">
          {TARDANZAS.reloj.map((r) => (
            <Cifra key={r.hora} tamano="sm" etiqueta={r.que} valor={r.hora} tono={r.tarde ? "alerta" : "positivo"} />
          ))}
        </div>
        <div className="grid gap-3 sm:grid-cols-2">
          <TarjetaInfo>
            <h3 className="font-serif text-lg">Cuándo no se cuenta</h3>
            <Lista items={TARDANZAS.noCuenta} className="mt-2" />
            <p className="mt-2"><Cita numerales={sinMarcas(TARDANZAS.noCuentaRef)} /></p>
          </TarjetaInfo>
          <TarjetaInfo>
            <h3 className="font-serif text-lg">¿Y en tu pago?</h3>
            {TARDANZAS.pago.map((t) => <p key={t} className="mt-2"><Texto t={t} /></p>)}
          </TarjetaInfo>
        </div>
        <BannerAviso variante="advertencia" titulo="Si la diferencia pasa de 3 horas">
          <p><Texto t={TARDANZAS.tresHoras} /></p>
        </BannerAviso>

        <Subtitulo cita="[[18]]">Cómo justificar una tardanza</Subtitulo>
        <Lista items={TARDANZAS.justificar} className="max-w-prose" />

        <Subtitulo cita={TARDANZAS.escaleraRef}>La escalera de tardanzas</Subtitulo>
        <p className="max-w-prose"><Texto t={TARDANZAS.conteo} /></p>
        <Escalera escalones={TARDANZAS.escalera} />
        <BannerAviso variante="informativo" titulo="Las tardanzas solas no son causal de despido">
          <p><Texto t={TARDANZAS.noSonDespido} /></p>
        </BannerAviso>
        <BannerAviso variante="positivo" titulo="En Info › Disciplina: «Cómo vas este mes»">
          <p>{TARDANZAS.enDynamic}</p>
        </BannerAviso>
      </Seccion>

      {/* ── Inasistencias ─────────────────────────────────────────────── */}
      <Seccion id="inasistencias" titulo="Inasistencias" bajada={INASISTENCIAS.bajada}>
        <div className="grid gap-3 sm:grid-cols-2">
          <TarjetaInfo>
            <h3 className="font-serif text-lg">No son inasistencia</h3>
            <Lista items={INASISTENCIAS.noSon} className="mt-2" />
            <p className="mt-2"><Cita numerales={sinMarcas(INASISTENCIAS.noSonRef)} /></p>
          </TarjetaInfo>
          <TarjetaInfo>
            <h3 className="font-serif text-lg">Avisa y justifica</h3>
            {INASISTENCIAS.avisaYJustifica.map((t) => <p key={t} className="mt-2"><Texto t={t} /></p>)}
          </TarjetaInfo>
          <TarjetaInfo>
            <h3 className="font-serif text-lg">Olvidar marcar no es faltar</h3>
            <p className="mt-2"><Texto t={INASISTENCIAS.olvidar} /></p>
          </TarjetaInfo>
          <TarjetaInfo>
            <h3 className="font-serif text-lg">Salir antes tampoco</h3>
            <p className="mt-2"><Texto t={INASISTENCIAS.salirAntes} /></p>
          </TarjetaInfo>
        </div>
        <p className="max-w-prose"><Texto t={INASISTENCIAS.pago} /></p>

        <Subtitulo cita={INASISTENCIAS.escaleraRef}>La escalera de inasistencias</Subtitulo>
        <p className="max-w-prose">{INASISTENCIAS.conteo}</p>
        <Escalera escalones={INASISTENCIAS.escalera} />

        <Subtitulo cita={INASISTENCIAS.gravesRef}>Cuando la ley lo considera falta grave</Subtitulo>
        <Tabla>
          <TablaEncabezado><Th>Situación</Th><Th>Desde cuándo</Th></TablaEncabezado>
          <tbody>
            {INASISTENCIAS.graves.map((g) => (
              <Fila key={g.situacion}>
                <td className="px-4 py-2 align-top">{g.situacion}</td>
                <td className="whitespace-nowrap px-4 py-2 align-top font-semibold">{g.desde}</td>
              </Fila>
            ))}
          </tbody>
        </Tabla>
        <p className="max-w-prose"><Texto t={INASISTENCIAS.gravesDespues} /></p>
      </Seccion>

      {/* ── Conducta ──────────────────────────────────────────────────── */}
      <Seccion id="conducta" titulo="Faltas de conducta" bajada={CONDUCTA.bajada}>
        <div className="grid gap-3 md:grid-cols-3">
          {CONDUCTA.catalogo.map((g) => (
            <TarjetaInfo key={g.nombre} className={cx("min-w-0 border-t-4", BORDE_ARRIBA[g.tono])}>
              <h3 className="font-serif text-xl">{g.nombre}</h3>
              <p className="mt-0.5 text-xs font-medium text-taupe">{g.maximo}</p>
              <Lista items={g.ejemplos} className="mt-3" />
              <p className="mt-2"><Cita numerales={sinMarcas(g.ref)} /></p>
            </TarjetaInfo>
          ))}
        </div>
        <p className="max-w-prose"><Texto t={CONDUCTA.reincidencia} /></p>
        <p className="max-w-prose"><Texto t={CONDUCTA.saltar} /></p>

        <Subtitulo cita={CONDUCTA.competenciaRef}>Quién puede decidir cada medida</Subtitulo>
        <Tabla>
          <TablaEncabezado><Th>Medida</Th><Th>Quién la puede firmar</Th></TablaEncabezado>
          <tbody>
            {CONDUCTA.competencia.map((c) => (
              <Fila key={c.medida}>
                <td className="px-4 py-2 align-top font-medium">{c.medida}</td>
                <td className="px-4 py-2 align-top">{c.quien}</td>
              </Fila>
            ))}
          </tbody>
        </Tabla>
        <p className="max-w-prose text-taupe">{CONDUCTA.competenciaNota}</p>

        <Subtitulo cita={CONDUCTA.suspensionRef}>Reglas de toda suspensión</Subtitulo>
        <Lista items={CONDUCTA.suspension} className="max-w-prose" />
      </Seccion>

      {/* ── Si te comunican cargos ────────────────────────────────────── */}
      <Seccion id="cargos" titulo="Si te comunican cargos" bajada={CARGOS.bajada}>
        <ol className="grid">
          {CARGOS.pasos.map((p, i) => (
            <li key={p.titulo}
              className="relative grid grid-cols-[2.25rem_minmax(0,1fr)] gap-3 pb-5 before:absolute before:bottom-1 before:left-[1.07rem] before:top-10 before:w-0.5 before:bg-sand last:pb-0 last:before:hidden">
              <span aria-hidden className="flex size-9 items-center justify-center rounded-full bg-tinta font-semibold tabular-nums text-crema">{i + 1}</span>
              <div className="min-w-0 pt-1.5">
                <h3 className="flex flex-wrap items-center gap-2 font-semibold">
                  {p.titulo}
                  {"plazo" in p && p.plazo && (
                    <Insignia variante={p.plazo.startsWith("Info") ? "positivo" : "advertencia"} punto={false}>{p.plazo}</Insignia>
                  )}
                </h3>
                {p.parrafos.map((t) => <p key={t} className="mt-1"><Texto t={t} /></p>)}
              </div>
            </li>
          ))}
        </ol>

        <Subtitulo>Cómo se cuentan los 2 días hábiles</Subtitulo>
        <p className="max-w-prose"><Texto t={CARGOS.comoSeCuentan} /></p>
        <div className="grid gap-4">
          {EJEMPLOS_DE_PLAZO.map((e) => <TiraDeDias key={e.inicio} titulo={e.titulo} inicio={e.inicio} />)}
        </div>
        <p className="max-w-prose text-taupe">{CARGOS.feriado}</p>

        <Subtitulo>Cuánto pesa una amonestación o una suspensión</Subtitulo>
        <figure className="grid gap-2" aria-label="Una amonestación o una suspensión pesa 12 meses desde que la recibes; después queda archivada y ya no cuenta.">
          <div aria-hidden className="grid h-3 grid-cols-[3fr_1fr] overflow-hidden rounded-pildora border border-sand">
            <span className="bg-ambar/50" />
            <span className="bg-hueso" />
          </div>
          <figcaption className="grid grid-cols-[3fr_1fr] gap-3 text-xs">
            <span><b className="block font-semibold">12 meses desde que la recibes</b>Puede agravar una medida por la misma causa.</span>
            <span className="text-taupe"><b className="block font-semibold">Después</b>Queda archivada y ya no cuenta.</span>
          </figcaption>
        </figure>
        <p className="max-w-prose"><Texto t={CARGOS.antecedente} /></p>

        <BannerAviso variante="neutral" titulo="Si recibes una imputación de cargos">
          <p className="mb-2">Es otro procedimiento, con más garantías. <Cita numerales={sinMarcas(CARGOS.imputacionRef)} /></p>
          <Lista items={CARGOS.imputacion} />
        </BannerAviso>
      </Seccion>

      {/* ── Plazos ────────────────────────────────────────────────────── */}
      <Seccion id="plazos" titulo="Fechas y plazos de un vistazo" bajada={SOBRE_LOS_PLAZOS}>
        {/* Dos columnas y no tres: en un teléfono la tercera quedaba fuera de la pantalla y solo se veía
            deslizando de lado, cosa que nadie adivina. El «desde cuándo» va debajo de su plazo. */}
        <Tabla>
          <TablaEncabezado><Th>Qué</Th><Th>Plazo y desde cuándo</Th></TablaEncabezado>
          <tbody>
            {PLAZOS.map((g) => (
              <Fragment key={g.grupo}>
                <tr>
                  <th scope="colgroup" colSpan={2} className="bg-hueso px-4 py-1.5 text-left text-xs font-medium text-taupe">{g.grupo}</th>
                </tr>
                {g.filas.map((f) => (
                  <Fila key={f.que}>
                    <td className="w-1/2 px-4 py-2 align-top">
                      {f.que}
                      <span className="block"><Cita numerales={sinMarcas(f.ref)} /></span>
                    </td>
                    <td className="px-4 py-2 align-top">
                      <span className="block font-semibold tabular-nums">{f.plazo}</span>
                      <span className="block text-taupe">{f.desde}</span>
                    </td>
                  </Fila>
                ))}
              </Fragment>
            ))}
          </tbody>
        </Tabla>
        <p className="max-w-prose text-taupe"><Texto t={SOBRE_LA_RECONSIDERACION} /></p>
      </Seccion>

      {/* ── Garantías ─────────────────────────────────────────────────── */}
      <Seccion id="garantias" titulo="Tus garantías" bajada="Esto no depende de la buena voluntad de nadie: lo dice el Reglamento.">
        <ul className="grid gap-x-6 gap-y-3 sm:grid-cols-2">
          {GARANTIAS.map((g) => (
            <li key={g.titulo} className="grid grid-cols-[1.25rem_minmax(0,1fr)] gap-2.5">
              <Check aria-hidden size={18} strokeWidth={2.2} className="mt-0.5 text-verde" />
              <span><b className="block font-semibold">{g.titulo}</b><Texto t={g.texto} /></span>
            </li>
          ))}
        </ul>
      </Seccion>

      {/* ── Preguntas ─────────────────────────────────────────────────── */}
      <Seccion id="preguntas" titulo="Preguntas frecuentes">
        <div className="border-t border-sand">
          {PREGUNTAS.map((p) => (
            <details key={p.pregunta} className="group border-b border-sand">
              <summary className="flex cursor-pointer list-none items-start justify-between gap-3 py-3 font-medium [&::-webkit-details-marker]:hidden">
                {p.pregunta}
                <span aria-hidden className="text-lg leading-none text-taupe group-open:rotate-45 motion-safe:transition-transform">+</span>
              </summary>
              <p className="max-w-prose pb-3"><Texto t={p.respuesta} /></p>
            </details>
          ))}
        </div>
      </Seccion>

      <footer className="grid gap-2 border-t border-sand pt-6">
        <p className="font-serif text-xl leading-snug">¿Tienes dudas? Pregúntale a tu líder de equipo o a Desarrollo Organizacional.</p>
        <p className="text-xs text-taupe">
          Guía revisada el {fechaLarga(GUIA_REVISADA)} contra el Reglamento Interno de Trabajo versión {REGLAMENTO_RESUMIDO.etiqueta}{" "}
          y contra lo que hace hoy Dynamic. No reemplaza al Reglamento ni a tu contrato.
        </p>
      </footer>
    </main>
  );
}

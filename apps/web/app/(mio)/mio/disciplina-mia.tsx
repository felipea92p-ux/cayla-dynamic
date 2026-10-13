"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { hoyLima } from "@cayla-dynamic/shared";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { useToast } from "@/components/toast";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { citaDeFalta } from "@/lib/admin/conducta";
import { fechaLarga, horaLima } from "@/components/disciplina/memo-documento";
import {
  hayAliento, mensajeDeAliento, ordenarParaLaPersona, paginar, porLeer, queFaltaEs, textoComoVas, tituloDe,
  type CuentaMia, type DocMio,
} from "@/lib/mio-disciplina";

/**
 * La sección «Disciplina» de /mio — lo que la persona ve de lo suyo.
 *
 * QUÉ PROMETE · mostrarle, de a 10 y con lo que pide atención primero, sus
 *               documentos disciplinarios; dejarle dar su constancia de lectura
 *               de lo que le entregaron en papel; decirle cómo va este mes con
 *               sus tardanzas; y, cuando no hay nada, un mensaje amable.
 *
 * Decidido el 2026-10-06 con el prototipo `docs/disciplina-mio-prototipo-2026-10-06.html`:
 *   · Sección propia en Seguimiento; los memos salen de «Historial».
 *   · En la lista se ve lo básico —tipo, fecha, la falta por su nombre corto—;
 *     el detalle de lo que pasó va detrás de «Leer el documento». La pantalla
 *     puede verla de reojo cualquiera, y el relato de una sanción no es para eso.
 *   · «Lo leí» se activa DESPUÉS de abrir el documento, y la base lo exige
 *     (`fn_marcar_memo_leido`, 0516): sin apertura registrada no hay constancia.
 *   · Lo recibido por Info NO pide «Lo leí»: recibir ya es la constancia (0486).
 *   · Leer no es aceptar. La constancia no cambia ni el estado del documento ni
 *     desde cuándo cuenta como antecedente.
 *
 * Recibe los datos y no los pide: el menú y el Resumen cuentan lo mismo que
 * esta pantalla, y escrito dos veces el número y la lista acabarían distintos.
 */

/** Lo que `fn_mi_memo` devuelve de un documento, el relato incluido. Solo lo que esta pantalla lee. */
interface Detalle {
  hechos: Array<{ fecha: string; minutos?: number; relato?: string }>;
  conocido_el: string | null;
  falta: { numeral: string; literal: string; texto: string; gravedad: string } | null;
  firmante: { nombre: string; cargo: string | null } | null;
}

type Cliente = ReturnType<typeof createAdminSupabaseClient>;

const SIN_DETALLE = "No se pudo abrir el documento ahora. Vuelve a intentarlo en un rato; si sigue, avisa a tu líder de equipo.";

export function DisciplinaMia({
  supabase, personaId, docs, error, cuenta, onCambio,
}: {
  supabase: Cliente;
  personaId: string;
  /** null mientras carga. */
  docs: DocMio[] | null;
  error: boolean;
  cuenta: CuentaMia | null;
  /** Recargar la lista (y con ella el menú y el Resumen) después de leer o firmar. */
  onCambio: () => void;
}) {
  const { avisar } = useToast();
  const [pagina, setPagina] = useState(0);
  const [salto, setSalto] = useState(0);
  // Lo que se abrió en esta visita, con su detalle. La apertura queda guardada en la
  // base; esto es solo para no volver a pedir lo que ya se leyó.
  const [detalle, setDetalle] = useState<Record<string, Detalle | "cargando" | "fallo">>({});
  const [ocupado, setOcupado] = useState<string | null>(null);

  const ordenados = docs ? ordenarParaLaPersona(docs) : [];
  const pag = paginar(ordenados, pagina);
  const comoVas = textoComoVas(cuenta);

  async function abrir(id: string) {
    setDetalle((d) => ({ ...d, [id]: "cargando" }));
    // Primero la apertura: es lo que hace que «Lo leí» valga algo. Si falla, el detalle no
    // se muestra: abrirlo sin que quede registrado dejaría una constancia imposible de dar.
    const { error: eA } = await supabase.rpc("fn_registrar_apertura_memo", { p_id: id });
    if (eA) { setDetalle((d) => ({ ...d, [id]: "fallo" })); avisar("error", mensajeDeError(eA, "abrir el documento")); return; }
    const { data, error: eM } = await supabase.rpc("fn_mi_memo", { p_id: id });
    if (eM || !data) { setDetalle((d) => ({ ...d, [id]: "fallo" })); return; }
    setDetalle((d) => ({ ...d, [id]: data as unknown as Detalle }));
    onCambio();
  }

  async function loLei(id: string) {
    setOcupado(id);
    const { error: e } = await supabase.rpc("fn_marcar_memo_leido", { p_id: id });
    setOcupado(null);
    if (e) { avisar("error", mensajeDeError(e, "dejar tu constancia")); return; }
    avisar("ok", "Quedó anotado que lo leíste.");
    onCambio();
  }

  async function firmar(id: string) {
    setOcupado(id);
    const { error: e } = await supabase.rpc("fn_firmar_memo_como_sancionado", { p_id: id });
    setOcupado(null);
    if (e) { avisar("error", mensajeDeError(e, "firmar el memo")); return; }
    avisar("ok", "Firma guardada en el memo.");
    onCambio();
  }

  async function preferiNoFirmar(id: string) {
    setOcupado(id);
    const { error: e } = await supabase.rpc("fn_rechazar_firma_memo", { p_id: id });
    setOcupado(null);
    if (e) { avisar("error", mensajeDeError(e, "registrar tu respuesta")); return; }
    avisar("ok", "Quedó anotado que prefieres no firmar digitalmente.");
    onCambio();
  }

  return (
    <div className="grid gap-4 text-sm">
      <header>
        <h2 className="font-serif text-lg">Disciplina</h2>
        <p className="text-taupe">Lo que consta en tu legajo y cómo vas este mes.</p>
      </header>

      {error ? (
        <p className="rounded-2xl border border-sand p-5 text-rojo">
          No se pudo cargar tu disciplina. Vuelve a intentarlo en un rato; si sigue, avisa a tu líder de equipo.
          No significa que no tengas nada: significa que no se pudo mirar.
        </p>
      ) : docs === null ? (
        <p className="text-taupe">Cargando…</p>
      ) : (
        <>
          {hayAliento(docs) && (
            <section className="grid justify-items-center gap-2 rounded-2xl border border-sand bg-papel px-5 py-6 text-center" aria-live="polite">
              <p className="max-w-[34ch] text-balance font-serif text-xl">{mensajeDeAliento(personaId, hoyLima(), salto)}</p>
              <Boton variante="enlace" className="text-xs text-taupe" onClick={() => setSalto((s) => s + 1)}>Ver otro mensaje</Boton>
            </section>
          )}

          {pag.items.length > 0 && (
            <ul className="grid gap-3">
              {pag.items.map((d) => (
                <li key={d.id}>
                  <TarjetaDoc
                    d={d} det={detalle[d.id]} ocupado={ocupado === d.id}
                    onAbrir={() => void abrir(d.id)} onLeido={() => void loLei(d.id)}
                    onFirmar={() => void firmar(d.id)} onNoFirmar={() => void preferiNoFirmar(d.id)}
                  />
                </li>
              ))}
            </ul>
          )}

          {pag.paginas > 1 && (
            <nav aria-label="Páginas de documentos" className="flex items-center justify-between gap-2 border-t border-sand pt-3">
              <Boton variante="secundario" tamano="sm" disabled={pag.pagina === 0} onClick={() => setPagina(pag.pagina - 1)}>← Anterior</Boton>
              <span className="whitespace-nowrap text-xs text-taupe">{pag.desde}–{pag.hasta} de {pag.total}</span>
              <Boton variante="secundario" tamano="sm" disabled={pag.pagina >= pag.paginas - 1} onClick={() => setPagina(pag.pagina + 1)}>Siguiente →</Boton>
            </nav>
          )}

          {comoVas && (
            <section className="grid gap-2 rounded-2xl border border-sand bg-papel p-4">
              <h3 className="text-xs font-semibold uppercase tracking-wide text-taupe">Cómo vas este mes</h3>
              {comoVas.casillas && (
                <div className="flex items-center gap-1.5" aria-hidden>
                  {Array.from({ length: comoVas.casillas.de }, (_, i) => (
                    <i key={i} className={`size-3 rounded-[3px] ${i < comoVas.casillas!.llenas ? "bg-tinta" : "bg-sand"}`} />
                  ))}
                </div>
              )}
              <p className="font-medium">{comoVas.titulo}</p>
              {comoVas.detalle && <p className="text-taupe">{comoVas.detalle}</p>}
            </section>
          )}
        </>
      )}
    </div>
  );
}

// ── Una tarjeta ──────────────────────────────────────────────────────────────

function TarjetaDoc({
  d, det, ocupado, onAbrir, onLeido, onFirmar, onNoFirmar,
}: {
  d: DocMio;
  det: Detalle | "cargando" | "fallo" | undefined;
  ocupado: boolean;
  onAbrir: () => void;
  onLeido: () => void;
  onFirmar: () => void;
  onNoFirmar: () => void;
}) {
  const router = useRouter();
  const titulo = tituloDe(d);
  const faltaCorta = queFaltaEs(d);
  const fecha = d.estado === "por_recibir"
    ? `Enviado a tu Info el ${fechaLarga(d.enviado_a_info_at!)}`
    : `Entregado el ${fechaLarga(d.entregado_at!)}`;
  const abierto = typeof det === "object";
  const lee3 = ["verbal", "amonestacion", "suspension"].includes(d.nivel);

  // Ya no pesa: una sola línea, atenuada. Es lo que el Reglamento ya canceló (56.7).
  if (d.cancelado) {
    return (
      <div className="grid gap-1 rounded-2xl border border-sand p-4 opacity-75">
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <strong className="font-serif text-base font-semibold">{titulo}</strong>
          <Insignia variante="neutral" punto={false}>Ya no pesa</Insignia>
        </div>
        <p className="text-taupe">{fecha}. Cumplió sus doce meses: ya no se cuenta como antecedente (RIT 56.7).</p>
      </div>
    );
  }

  const pendiente = porLeer(d);
  const leido = Boolean(d.leido_at);
  const resuelto = Boolean(d.firma_confirmada_at || d.rechazo_firma_at);

  return (
    <article className={`grid gap-2.5 rounded-2xl border p-4 ${d.estado === "por_recibir" || pendiente ? "border-ambar/50 bg-papel shadow-[inset_3px_0_0_var(--color-ambar)]" : "border-sand bg-papel"}`}>
      <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
        <strong className="font-serif text-lg font-semibold">{titulo}</strong>
        {d.estado === "por_recibir" ? <Insignia variante="advertencia" punto={false}>Por recibir</Insignia>
          : pendiente ? <Insignia variante="advertencia" punto={false}>Por leer</Insignia>
          : leido ? <Insignia variante="positivo" punto={false}>Leído</Insignia>
          : null}
      </div>

      <div className="flex flex-wrap gap-x-4 gap-y-0.5 text-xs text-taupe">
        <span>{fecha}</span>
        {faltaCorta && <span>{faltaCorta}</span>}
        {d.correlativo && <span>{d.correlativo}</span>}
        {d.vigente_hasta && <span>Cuenta como antecedente hasta el {fechaLarga(d.vigente_hasta)}</span>}
      </div>

      {/* Lo recibido por Info: recibir ya fue la constancia, y se lee en su pantalla. */}
      {d.estado === "por_recibir" && (
        <>
          <p className="text-xs text-taupe">
            Ábrelo, léelo y confirma que lo recibiste. Recibirlo no es aceptar lo que dice: puedes firmarlo o recibirlo sin firmar.
          </p>
          <div><Boton variante="primario" tamano="sm" onClick={() => router.push(`/mio/memo/${d.id}`)}>Abrir y recibir</Boton></div>
        </>
      )}

      {d.estado === "entregado" && d.medio_entrega === "digital" && (
        <p className="text-xs text-taupe">
          Lo recibiste por tu Info: esa confirmación ya es tu constancia.{" "}
          <Link href={`/mio/memo/${d.id}`} className="underline hover:text-tinta">Ver el documento</Link>
        </p>
      )}

      {/* Una carta de imputación o de despido se entrega en físico o por vía notarial. */}
      {d.estado === "entregado" && !lee3 && (
        <p className="text-xs text-taupe">Este documento se entregó en físico o por vía notarial: no se abre en pantalla.</p>
      )}

      {/* Lo entregado en papel: el detalle detrás de «Leer», y «Lo leí» después. */}
      {d.estado === "entregado" && lee3 && d.medio_entrega !== "digital" && (
        <>
          {det === "fallo" && <p className="text-xs text-rojo">{SIN_DETALLE}</p>}
          {!abierto && det !== "cargando" && (
            <p className="text-xs text-taupe">El detalle de lo que pasó se ve al abrir el documento.</p>
          )}
          {abierto && <DetalleDelDoc d={d} det={det} />}

          {leido ? (
            <p className="flex items-start gap-1.5 text-xs text-verde">
              <span aria-hidden>✓</span>
              <span>
                Leíste este documento el {fechaLarga(d.leido_at!)}, a las {horaLima(d.leido_at!)}. Leerlo no es aceptarlo.
              </span>
            </p>
          ) : null}

          <div className="flex flex-wrap items-center gap-2">
            {(!abierto || leido) && (
              <Boton variante={leido ? "enlace" : "secundario"} tamano="sm" className={leido ? "text-xs text-taupe" : undefined}
                cargando={det === "cargando"} onClick={onAbrir}>
                {leido ? "Volver a leerlo" : "Leer el documento"}
              </Boton>
            )}
            {pendiente && (
              <>
                <Boton variante="primario" tamano="sm" cargando={ocupado}
                  disabled={!abierto && !d.abierto_at} onClick={onLeido}
                  title={!abierto && !d.abierto_at ? "Ábrelo primero" : undefined}>
                  Lo leí
                </Boton>
                {(abierto || d.abierto_at) && <span className="text-xs text-taupe">Queda anotado con tu nombre, la fecha y la hora.</span>}
              </>
            )}
          </div>

          {/* Firmar es opcional y viene después de leer: evidencia adicional con su propia fecha; no reemplaza el papel. */}
          {leido && !resuelto && (
            <div className="grid gap-1.5 border-t border-sand pt-2.5">
              <p className="text-xs text-taupe">
                Si quieres, también puedes firmarlo acá: es evidencia adicional, con su propia fecha y hora, y no reemplaza el papel.
              </p>
              <div className="flex flex-wrap items-center gap-3">
                <Boton variante="primario" tamano="sm" cargando={ocupado} onClick={onFirmar}>Firmar</Boton>
                <Boton variante="enlace" className="text-xs text-taupe" disabled={ocupado} onClick={onNoFirmar}>
                  Prefiero no firmar digitalmente
                </Boton>
              </div>
            </div>
          )}
          {d.firma_confirmada_at && (
            <p className="text-xs text-verde">Firmaste este documento el {fechaLarga(d.firma_confirmada_at)}.</p>
          )}
          {d.rechazo_firma_at && (
            <p className="text-xs text-taupe">Quedó anotado que preferiste no firmarlo digitalmente, el {fechaLarga(d.rechazo_firma_at)}.</p>
          )}
        </>
      )}

    </article>
  );
}

// ── El detalle: lo que se ve después de abrir ────────────────────────────────

function DetalleDelDoc({ d, det }: { d: DocMio; det: Detalle }) {
  const relato = d.tipo_causal === "conducta" ? det.hechos?.[0] : null;
  const fechas = d.tipo_causal === "conducta" ? [] : (det.hechos ?? []).map((h) => h.fecha);
  return (
    <div className="grid gap-2.5">
      {det.falta && (
        <div className="rounded-lg bg-hueso px-3 py-2">
          <span className="block text-[11px] font-semibold uppercase tracking-wide text-taupe">Qué falta es</span>
          <span className="block">{citaDeFalta(det.falta)} del RIT</span>
          <span className="block text-taupe">«{det.falta.texto.replace(/\.\s*$/, "")}»</span>
        </div>
      )}
      {relato?.relato && (
        <div className="border-l-[3px] border-sand pl-3">
          <span className="block text-[11px] font-semibold uppercase tracking-wide text-taupe">Lo que pasó · {fechaLarga(relato.fecha)}</span>
          <p className="whitespace-pre-line">{relato.relato}</p>
        </div>
      )}
      {fechas.length > 0 && (
        <p><span className="text-taupe">Fechas que cita:</span> {fechas.map((f) => fechaLarga(f)).join(" · ")}</p>
      )}
      <div className="flex flex-wrap gap-x-4 gap-y-0.5 text-xs text-taupe">
        {det.conocido_el && <span>La empresa supo el {fechaLarga(det.conocido_el)}</span>}
        {det.firmante && <span>Firma: {det.firmante.nombre}{det.firmante.cargo ? ` · ${det.firmante.cargo}` : ""}</span>}
      </div>
      <p className="text-xs">
        {d.nivel === "verbal"
          ? "Es un acta de una llamada de atención: no es una sanción y no cuenta como antecedente (RIT 54.2)."
          : d.vigente_hasta
            ? <><strong>Cuenta como antecedente</strong> doce meses desde que te lo entregaron, hasta el {fechaLarga(d.vigente_hasta)} (RIT 56.1).</>
            : null}
      </p>
      <details className="text-xs text-taupe">
        <summary className="cursor-pointer font-semibold text-tinta">Qué puedes hacer si no estás de acuerdo</summary>
        <p className="mt-1.5">
          Leer no es aceptar. Puedes pedir una reconsideración por escrito a Gerencia General dentro de los cinco días hábiles
          siguientes a recibirlo (RIT 55.5), y puedes acudir a la Autoridad Inspectiva de Trabajo.
        </p>
      </details>
      <Link href={`/mio/memo/${d.id}`} className="text-xs text-taupe underline hover:text-tinta">Ver el documento tal como se imprime</Link>
    </div>
  );
}

"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { AdminNav } from "../nav";
import { Cargando } from "@/components/cargando";
import { useToast } from "@/components/toast";
import { useRolActual } from "@/lib/admin/use-rol";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { formatSoles } from "@/lib/rangos";
import { hoyLima, puedeVerPlanilla } from "@cayla-dynamic/shared";
import { Boton } from "@/components/ui/boton";
import { Campo } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { Modal } from "@/components/ui/modal";

// Liquidación por cese. La ley da 48 HORAS desde el cese para pagar (art. 4 del
// D.S. 001-97-TR), así que esta pantalla existe para que ese plazo no dependa de
// que alguien arme la cuenta a mano un viernes por la tarde.
//
// QUÉ MUESTRA Y QUÉ NO. Todas las cesadas con liquidación por resolver, sin
// filtrar por vínculo ni por importe: `fn_liquidaciones_pendientes` no mira
// `tipo_vinculo` ni descarta los totales en cero — comprobado contra `pg_proc`
// el 2026-08-14. Una locadora o alguien de un día de prueba aparece igual, con
// su cero, y eso es correcto: el plazo de 48 horas corre para todas.
//
// ⚠️ Este comentario decía lo contrario —que solo salía quien tiene algo que
// pagar, y que había un contador de «cesadas sin nada que pagar»—. Ninguna de
// las dos cosas existe en el código. Se corrige porque es el mapa que lee quien
// venga a tocar esta pantalla, y un mapa equivocado cuesta más que ninguno.

// Por string, nunca `new Date()`: construir una fecha desde el navegador puede
// correrla un día por zona horaria, y acá una fecha decide un plazo legal.
function fechaLarga(iso: string | null | undefined): string {
  if (!iso) return "—";
  const [y, m, d] = iso.split("-");
  if (!y || !m || !d) return iso;
  return `${d}/${m}/${y}`;
}

interface Pendiente {
  persona_id: string;
  persona: string;
  sede: string;
  fecha_ingreso: string | null;
  fecha_cese: string;
  vence_el: string;
  dias_restantes: number;
  vencido: boolean;
  total: number;
  pagada: boolean;
  descuadra: boolean;
}

interface AvisoVinculo {
  persona_id: string;
  persona: string;
  sede: string;
  tipo_vinculo: string;
  fecha_ingreso: string;
  dias: number;
  cumple_el_mes: string;
  ya_devenga: boolean;
  aviso: string;
}

interface Diferencia {
  concepto: string;
  pagado: number;
  ahora: number;
  diferencia: number;
}

// El desglose que devuelve fn_liquidacion. Se tipa flojo a propósito: es el
// mismo jsonb que se congela, y encorsetarlo obligaría a tocar dos sitios cada
// vez que el cálculo gane una línea.
type Detalle = Record<string, unknown> & {
  persona?: string;
  fecha_ingreso?: string;
  fecha_cese?: string;
  vence_el?: string;
  vencido?: boolean;
  total?: number;
  aviso_periodo?: string | null;
  periodo?: { desde?: string; hasta?: string; monto?: number; detalle?: Record<string, unknown> } | null;
  vacaciones_truncas?: Record<string, unknown>;
  gratificacion_trunca?: Record<string, unknown>;
  cts_trunca?: Record<string, unknown>;
};

const n = (v: unknown): number => (typeof v === "number" ? v : Number(v ?? 0) || 0);
const s = (v: unknown): string | null => (typeof v === "string" ? v : null);

export default function LiquidacionesPage() {
  const router = useRouter();
  const { avisar } = useToast();
  const rol = useRolActual();
  const supabase = createAdminSupabaseClient();

  const [pendientes, setPendientes] = useState<Pendiente[]>([]);
  const [avisos, setAvisos] = useState<AvisoVinculo[]>([]);
  const [cargando, setCargando] = useState(true);
  const [cargaError, setCargaError] = useState<string | null>(null);

  const [abierta, setAbierta] = useState<string | null>(null);
  const [detalle, setDetalle] = useState<Detalle | null>(null);
  const [diferencias, setDiferencias] = useState<Diferencia[]>([]);
  const [diferenciasError, setDiferenciasError] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [nota, setNota] = useState("");
  const [miFirma, setMiFirma] = useState<string | null>(null);

  // Confirmaciones que antes eran window.confirm()/window.prompt(): Felipe
  // aprobó migrar todos los diálogos nativos del panel al Modal compartido
  // (ver CLAUDE.md). Cada uno lleva solo lo que la fila necesitaba para armar
  // el mensaje — no el objeto Pendiente entero, que puede quedar desfasado
  // mientras el modal sigue abierto.
  const [pagoAccion, setPagoAccion] = useState<
    { personaId: string; nombre: string; total: number; yaPagada: boolean } | null
  >(null);
  const [anularAccion, setAnularAccion] = useState<{ personaId: string; nombre: string } | null>(null);
  const [motivoAnular, setMotivoAnular] = useState("");

  const puede = puedeVerPlanilla(rol);

  const cargar = useCallback(async () => {
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }

    const [lista, av] = await Promise.all([
      supabase.rpc("fn_liquidaciones_pendientes"),
      supabase.rpc("fn_avisos_vinculo"),
    ]);
    setPendientes((lista.data as Pendiente[]) ?? []);
    setAvisos((av.data as AvisoVinculo[]) ?? []);
    // Los dos RPC pueden fallar por separado, y los dos alimentan avisos que
    // importan: si `av` falla en silencio, el aviso de vínculo «prueba» —el
    // que habla de beneficios que se están por devengar— desaparece sin que
    // nada lo diga. Antes solo se miraba `lista.error`.
    setCargaError(lista.error?.message ?? av.error?.message ?? null);
    setCargando(false);
  }, [router, supabase]);

  useEffect(() => { void cargar(); }, [cargar]);

  // La firma es la que cada quien subió en su propio perfil (fn_mi_firma) — la
  // misma que ya se usa en los memos leves y en política salarial. Sin firma
  // propia guardada, esto queda en null y las dos vistas simplemente no la
  // muestran: no hay firma genérica de reemplazo.
  useEffect(() => {
    void (async () => {
      const { data } = await supabase.rpc("fn_mi_firma");
      if (typeof data === "string" && data.startsWith("data:image")) setMiFirma(data);
    })();
  }, [supabase]);

  async function cargarDetalle(personaId: string) {
    const [liq, dif] = await Promise.all([
      supabase.rpc("fn_liquidacion", { p_persona_id: personaId }),
      supabase.rpc("fn_liquidacion_diferencias", { p_persona_id: personaId }),
    ]);
    if (liq.error) { avisar("error", mensajeDeError(liq.error)); return; }
    setDetalle(liq.data as Detalle);
    setDiferencias((dif.data as Diferencia[]) ?? []);
    // Antes solo se miraba `liq.error`: si `fn_liquidacion_diferencias`
    // fallaba, `diferencias` quedaba en `[]` y el bloque rojo de abajo
    // simplemente no se dibujaba — indistinguible de «no hay descuadre».
    // Quien está por apretar «Marcar como pagada» necesita saber que esto no
    // se comprobó, no ver un desglose que parece cuadrado por accidente.
    setDiferenciasError(dif.error ? mensajeDeError(dif.error) : null);
  }

  async function abrir(personaId: string) {
    if (abierta === personaId) { setAbierta(null); setDetalle(null); setDiferencias([]); setDiferenciasError(null); return; }
    setAbierta(personaId); setDetalle(null); setDiferencias([]); setDiferenciasError(null); setNota("");
    await cargarDetalle(personaId);
  }

  // Marcar una liquidación como pagada CONGELA una cifra que se le entrega a
  // una persona que ya se fue, y de la que corre un plazo legal de 48 horas. La
  // acción equivalente de Planilla («marcar el periodo como pagado») explica sus
  // consecuencias antes de hacerlo; ésta no preguntaba nada — un clic y ya.
  //
  // Se nombra la persona y el importe EN LA PREGUNTA a propósito: el error que
  // esto previene no es «no quería congelar», es «congelé la de otra persona» o
  // «congelé antes de mirar el desglose». Un «¿seguro?» a secas no lo evita.
  //
  // Antes era window.confirm(): ahora abre el Modal compartido con los mismos
  // dos botones (Sí/Cancelar) — el texto es el mismo, solo cambia el diálogo.
  function abrirPagar(personaId: string, nombre: string, total: number, yaPagada: boolean) {
    setPagoAccion({ personaId, nombre, total, yaPagada });
  }

  async function confirmarPago() {
    if (!pagoAccion) return;
    const { personaId } = pagoAccion;
    setOcupado(true);
    const { data, error } = await supabase.rpc("fn_liquidacion_pagar", {
      p_persona_id: personaId,
      p_nota: nota.trim() || null,
    });
    setOcupado(false);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    setPagoAccion(null);
    await cargar();
    setAbierta(personaId); setDetalle(null); setDiferencias([]); setDiferenciasError(null);
    await cargarDetalle(personaId);
    const v = (data as { version?: number } | null)?.version;
    avisar("ok",
      `Liquidación congelada${v && v > 1 ? ` (versión ${v})` : ""}. La cifra pagada ya no cambia sola: si un recálculo posterior difiere, se avisa.`);
  }

  // ── Deshacer ────────────────────────────────────────────────────────────
  //
  // `fn_liquidacion_anular` EXISTE desde la migración 0251 —se escribió por un
  // caso real de producción: una liquidación de S/1,106.82 congelada por error,
  // cuando del banco solo salieron S/358.73— y ninguna pantalla la llamaba. O
  // sea que el arreglo estaba construido, probado y desplegado, y desde el panel
  // seguía sin haber forma de deshacer nada.
  //
  // No borra: guarda encima una versión en cero con motivo y firma, y los ocho
  // lectores de `liquidacion_pagada` toman siempre la última. El motivo es
  // obligatorio en la base (mínimo 3 caracteres) y acá se pide antes de llamar,
  // para que el rechazo no llegue como un error crudo de Postgres.
  //
  // Antes era window.prompt(): ahora el motivo se escribe en un <AreaTexto>
  // dentro del Modal compartido, con el mismo mínimo de 3 caracteres.
  function abrirAnular(personaId: string, nombre: string) {
    setAnularAccion({ personaId, nombre });
    setMotivoAnular("");
  }

  async function ejecutarAnular() {
    if (!anularAccion) return;
    if (motivoAnular.trim().length < 3) {
      avisar("error", "El motivo es obligatorio: dentro de un año, una fila en cero sin explicación no se puede leer.");
      return;
    }
    const { personaId, nombre } = anularAccion;
    setOcupado(true);
    const { error } = await supabase.rpc("fn_liquidacion_anular", {
      p_persona_id: personaId, p_motivo: motivoAnular.trim(),
    });
    setOcupado(false);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    setAnularAccion(null); setMotivoAnular("");
    await cargar();
    setAbierta(personaId); setDetalle(null); setDiferencias([]); setDiferenciasError(null);
    await cargarDetalle(personaId);
    avisar("ok", `Liquidación de ${nombre} anulada con constancia. Vuelve a marcarla cuando el número esté bien.`);
  }

  if (cargando) return <Cargando />;

  if (!puede) {
    return (
      <div className="flex min-h-screen flex-col">
        <AdminNav />
        <main className="flex-1 p-6">
          <p className="text-sm text-taupe">Esta pantalla es de Desarrollo Organizacional.</p>
        </main>
      </div>
    );
  }

  // Quien está dentro del plazo y aún no se pagó: es lo único urgente de acá.
  const enPlazo = pendientes.filter((p) => !p.pagada && !p.vencido);
  const vencidas = pendientes.filter((p) => !p.pagada && p.vencido);
  const pagadas  = pendientes.filter((p) => p.pagada);
  const avisoUrgente = avisos.filter((a) => a.ya_devenga);

  return (
    <div className="flex min-h-screen flex-col">
      <div className="print:hidden"><AdminNav /></div>

      <main className="flex-1 p-6 print:p-0">
        <div className="print:hidden">
          <h1 className="mb-1 font-serif text-2xl">Liquidaciones</h1>
          <p className="mb-4 max-w-3xl text-sm text-taupe">
            La ley da <strong>48 horas</strong> desde el cese para pagar (art. 4 del D.S. 001-97-TR).
            Acá aparece sola quien tiene algo que pagar, con lo que le queda de plazo. Al marcarla
            como pagada, la cifra se congela: si después el cálculo cambia, el sistema lo dice y no
            mueve el número.
          </p>

          {cargaError && (
            <p className="mb-4 rounded-lg border border-rojo bg-rojo/5 p-3 text-sm text-rojo">
              No se pudo leer la lista: {cargaError}
            </p>
          )}

          {/* ── El aviso del vínculo «prueba» ────────────────────────────────
              Va acá y no en Equipo porque lo que está en juego son beneficios, y
              esta es la pantalla que habla de beneficios. Solo aparece cuando ya
              pasó el mes: antes no cuesta nada y avisar sería ruido. */}
          {avisoUrgente.map((a) => (
            <div key={a.persona_id} className="mb-4 rounded-lg border border-rojo bg-rojo/5 p-3 text-sm">
              <strong className="text-rojo">{a.persona} lleva {a.dias} días como «prueba».</strong>{" "}
              {a.aviso}
            </div>
          ))}

          {/* ── Lo urgente ─────────────────────────────────────────────────── */}
          <Bloque
            titulo="Dentro del plazo"
            vacio="Nadie con liquidación pendiente. El plazo de 48 horas corre desde el cese, así que esto se llena solo el día que alguien cese."
            filas={enPlazo} abierta={abierta} onAbrir={abrir}
            detalle={detalle} diferencias={diferencias} diferenciasError={diferenciasError} nota={nota} setNota={setNota}
            ocupado={ocupado} onPagar={abrirPagar} onAnular={abrirAnular} miFirma={miFirma} urgente
          />

          {vencidas.length > 0 && (
            <Bloque
              titulo={`Pasadas de plazo · ${vencidas.length}`}
              vacio="" filas={vencidas} abierta={abierta} onAbrir={abrir}
              detalle={detalle} diferencias={diferencias} diferenciasError={diferenciasError} nota={nota} setNota={setNota}
              ocupado={ocupado} onPagar={abrirPagar} onAnular={abrirAnular} miFirma={miFirma} urgente
            />
          )}

          {pagadas.length > 0 && (
            <Bloque
              titulo={`Pagadas · ${pagadas.length}`}
              vacio="" filas={pagadas} abierta={abierta} onAbrir={abrir}
              detalle={detalle} diferencias={diferencias} diferenciasError={diferenciasError} nota={nota} setNota={setNota}
              ocupado={ocupado} onPagar={abrirPagar} onAnular={abrirAnular} miFirma={miFirma}
            />
          )}
        </div>

        {/* ── La hoja que se imprime y se firma ──────────────────────────── */}
        {detalle && <Hoja d={detalle} miFirma={miFirma} />}
      </main>

      {/* Modal: congelar (o volver a congelar) la liquidación. Reemplaza el
          window.confirm() que hacía esta misma pregunta en un diálogo nativo
          del navegador — Felipe aprobó migrar todos los diálogos nativos del
          panel a este primitivo (ver CLAUDE.md). Mismo texto, mismos dos
          caminos (Sí/Cancelar), solo cambia el diálogo. */}
      <Modal
        abierto={pagoAccion !== null}
        onCerrar={() => setPagoAccion(null)}
        bloqueado={ocupado}
        titulo={pagoAccion?.yaPagada ? "Volver a marcar como pagada" : "Congelar la liquidación"}
        ancho="sm"
      >
        {pagoAccion && (
          <>
            <p className="mb-4 text-sm text-taupe">
              {pagoAccion.yaPagada ? (
                <>
                  Vas a volver a marcar como pagada la liquidación de{" "}
                  <strong className="text-tinta">{pagoAccion.nombre}</strong> por{" "}
                  {formatSoles(pagoAccion.total)}.
                  <br /><br />
                  Se guarda una copia NUEVA con el cálculo de hoy; la anterior se conserva entera
                  como histórico y queda registrado quién lo hizo.
                </>
              ) : (
                <>
                  Vas a congelar la liquidación de <strong className="text-tinta">{pagoAccion.nombre}</strong>{" "}
                  en {formatSoles(pagoAccion.total)}.
                  <br /><br />
                  Ese es el número que queda para contabilidad: si después el cálculo cambia, el
                  sistema lo dice pero NO mueve la cifra.
                  <br /><br />
                  Si te equivocas, se arregla desde acá mismo: «Anular» deja constancia y la saca
                  de la cuenta, sin borrar nada.
                </>
              )}
            </p>
            <div className="flex justify-end gap-2">
              <Boton onClick={() => setPagoAccion(null)} disabled={ocupado}>Cancelar</Boton>
              <Boton variante="primario" onClick={() => void confirmarPago()} cargando={ocupado}>
                {pagoAccion.yaPagada ? "Volver a marcarla" : "Congelar"}
              </Boton>
            </div>
          </>
        )}
      </Modal>

      {/* Modal: anular una liquidación pagada. Reemplaza el window.prompt()
          que pedía este mismo motivo en un diálogo nativo del navegador —
          misma validación de mínimo 3 caracteres, ahora en un <AreaTexto>
          dentro del Modal compartido (mismo patrón que en correcciones). */}
      <Modal
        abierto={anularAccion !== null}
        onCerrar={() => setAnularAccion(null)}
        bloqueado={ocupado}
        titulo="Anular la liquidación"
        ancho="sm"
      >
        {anularAccion && (
          <>
            <p className="mb-4 text-sm text-taupe">
              Vas a <strong className="text-rojo">ANULAR</strong> la liquidación pagada de{" "}
              <strong className="text-tinta">{anularAccion.nombre}</strong>.
              <br /><br />
              No se borra nada: encima queda una versión en cero, con tu firma y este motivo. La
              cifra deja de contar en Planilla, en el cierre del mes y en la hoja de la persona.
            </p>
            <label className="mb-4 flex flex-col gap-1 text-sm">
              ¿Qué se marcó por error y cómo se sabe? (mínimo 3 caracteres, obligatorio)
              <AreaTexto
                value={motivoAnular}
                onChange={(e) => setMotivoAnular(e.target.value)}
                rows={2}
                autoFocus
                placeholder="ej. se marcó pagada el 10/08 y del banco solo salió el adelanto."
              />
            </label>
            <div className="flex justify-end gap-2">
              <Boton onClick={() => setAnularAccion(null)} disabled={ocupado}>Cancelar</Boton>
              <Boton variante="peligro" onClick={() => void ejecutarAnular()} cargando={ocupado}>
                Anular
              </Boton>
            </div>
          </>
        )}
      </Modal>
    </div>
  );
}

function Bloque({
  titulo, vacio, filas, abierta, onAbrir, detalle, diferencias, diferenciasError, nota, setNota, ocupado, onPagar, onAnular, miFirma, urgente,
}: {
  titulo: string; vacio: string; filas: Pendiente[];
  abierta: string | null; onAbrir: (id: string) => void;
  detalle: Detalle | null; diferencias: Diferencia[]; diferenciasError: string | null;
  nota: string; setNota: (v: string) => void;
  ocupado: boolean;
  onPagar: (id: string, nombre: string, total: number, yaPagada: boolean) => void;
  onAnular: (id: string, nombre: string) => void;
  miFirma: string | null; urgente?: boolean;
}) {
  return (
    <div className="mb-4 overflow-hidden rounded-2xl border border-sand bg-papel">
      <h2 className="border-b bg-sand/50 px-4 py-2 text-sm font-medium">{titulo}</h2>
      {filas.length === 0 ? (
        <p className="px-4 py-4 text-sm text-taupe">{vacio}</p>
      ) : (
        <ul className="divide-y">
          {filas.map((f) => (
            <li key={f.persona_id} className="px-4 py-3 text-sm">
              <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                <span>
                  <strong>{f.persona}</strong>{" "}
                  <span className="text-taupe">· {f.sede} · cesó el {fechaLarga(f.fecha_cese)}</span>
                  {f.descuadra && (
                    <span className="ml-2 rounded bg-rojo/10 px-1.5 py-0.5 text-xs font-medium text-rojo">
                      el cálculo ya no coincide
                    </span>
                  )}
                </span>
                <div className="flex items-center gap-3">
                  <strong className="tabular-nums">{formatSoles(f.total)}</strong>
                  <Boton variante="secundario" tamano="sm" onClick={() => onAbrir(f.persona_id)}>
                    {abierta === f.persona_id ? "Cerrar" : "Ver desglose"}
                  </Boton>
                </div>
              </div>

              {/* El reloj. Se dice en días y con su fecha: «vence el 17/06» se
                  entiende sin hacer una resta mental. */}
              <p className="mt-1 text-xs">
                {f.pagada ? (
                  <span className="text-taupe">pagada · plazo vencía el {fechaLarga(f.vence_el)}</span>
                ) : f.vencido ? (
                  <span className="font-medium text-rojo">
                    pasada de plazo · vencía el {fechaLarga(f.vence_el)}
                  </span>
                ) : (
                  <span className={urgente ? "font-medium text-rojo" : "text-taupe"}>
                    quedan {f.dias_restantes} día{f.dias_restantes === 1 ? "" : "s"} · vence el {fechaLarga(f.vence_el)}
                  </span>
                )}
              </p>

              {abierta === f.persona_id && detalle && (
                <Desglose
                  d={detalle} diferencias={diferencias} diferenciasError={diferenciasError} pagada={f.pagada}
                  nota={nota} setNota={setNota} ocupado={ocupado} miFirma={miFirma}
                  // `detalle.total` — no `f.total` — porque es el número que la
                  // persona acaba de leer en el Desglose de abajo, recién
                  // calculado. `f.total` es el que trajo la lista al montar la
                  // pantalla, y para "volver a marcar pagada" es literalmente el
                  // monto histórico congelado: el diálogo prometía "el cálculo de
                  // HOY" mostrando un número de otra frescura.
                  onPagar={() => onPagar(f.persona_id, f.persona, n(detalle.total), f.pagada)}
                  onAnular={() => onAnular(f.persona_id, f.persona)}
                />
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function Linea({ etiqueta, jsonb }: { etiqueta: string; jsonb: Record<string, unknown> | undefined }) {
  if (!jsonb) return null;
  const aplica = jsonb.aplica !== false;
  const monto = n(jsonb.monto);
  const devengado = jsonb.devengado === undefined ? null : n(jsonb.devengado);
  const yaDep = jsonb.ya_depositado === undefined ? null : n(jsonb.ya_depositado);
  // CAMBIO 0341 · el descuento de AFP de las vacaciones truncas, mostrado y no
  // escondido: un monto más chico sin explicación es indistinguible de un error.
  const montoBruto = jsonb.monto_bruto === undefined ? null : n(jsonb.monto_bruto);
  const descuentoAfp = jsonb.descuento_afp === undefined ? null : n(jsonb.descuento_afp);

  return (
    <tr className="border-t border-sand align-top">
      <td className="py-2 pr-3">
        {etiqueta}
        {!aplica && (
          <span className="block text-xs text-taupe">{s(jsonb.motivo) ?? "no corresponde"}</span>
        )}
        {aplica && (
          <span className="block text-xs text-taupe">
            {s(jsonb.contado_desde) && s(jsonb.hasta) &&
              `del ${fechaLarga(s(jsonb.contado_desde))} al ${fechaLarga(s(jsonb.hasta))}`}
            {jsonb.meses_completos !== undefined &&
              ` · ${n(jsonb.meses_completos)} mes(es) y ${n(jsonb.dias_sueltos)} día(s)`}
            {s(jsonb.formula) && ` · ${s(jsonb.formula)}`}
          </span>
        )}
        {/* Lo ya depositado se muestra restándose, no escondido en el neto: si
            alguien reclama, la hoja tiene que explicar por qué su CTS es menor. */}
        {yaDep !== null && yaDep !== 0 && (
          <span className="block text-xs text-taupe">
            devengado {formatSoles(devengado ?? 0)} − ya depositado {formatSoles(yaDep)}
          </span>
        )}
        {descuentoAfp !== null && descuentoAfp !== 0 && (
          <span className="block text-xs text-taupe">
            bruto {formatSoles(montoBruto ?? 0)} − AFP/ONP {formatSoles(descuentoAfp)}
          </span>
        )}
      </td>
      <td className="py-2 text-right tabular-nums">{formatSoles(monto)}</td>
    </tr>
  );
}

function Desglose({
  d, diferencias, diferenciasError, pagada, nota, setNota, ocupado, onPagar, onAnular, miFirma,
}: {
  d: Detalle; diferencias: Diferencia[]; diferenciasError: string | null; pagada: boolean;
  nota: string; setNota: (v: string) => void; ocupado: boolean;
  onPagar: () => void; onAnular: () => void;
  miFirma: string | null;
}) {
  return (
    <div className="mt-3 rounded-lg border border-sand bg-sand/20 p-3">
      {d.aviso_periodo && (
        <p className="mb-2 rounded border border-rojo/40 bg-rojo/5 p-2 text-xs text-rojo">
          {d.aviso_periodo}
        </p>
      )}

      <table className="w-full text-sm">
        <tbody>
          <tr className="align-top">
            <td className="py-2 pr-3">
              Sueldo del periodo
              <span className="block text-xs text-taupe">
                {d.periodo
                  ? `del ${fechaLarga(d.periodo.desde)} al ${fechaLarga(d.periodo.hasta)} · incluye feriados, movilidad, educación y descuentos`
                  : "no se pudo calcular"}
              </span>
            </td>
            <td className="py-2 text-right tabular-nums">{formatSoles(n(d.periodo?.monto))}</td>
          </tr>
          <Linea etiqueta="Vacaciones truncas"    jsonb={d.vacaciones_truncas} />
          <Linea etiqueta="Gratificación trunca"  jsonb={d.gratificacion_trunca} />
          <Linea etiqueta="CTS trunca"            jsonb={d.cts_trunca} />
          <tr className="border-t-2 border-tinta/20">
            <td className="py-2 font-medium">Total</td>
            <td className="py-2 text-right font-medium tabular-nums">{formatSoles(n(d.total))}</td>
          </tr>
        </tbody>
      </table>

      {diferenciasError ? (
        // Antes, si `fn_liquidacion_diferencias` fallaba, este bloque entero
        // no se dibujaba: la pantalla quedaba igual que cuando SÍ se comprobó
        // y no había descuadre. Ese hueco es el error real — se avisa en vez
        // de dejarlo pasar por «no hay diferencias».
        <div className="mt-3 rounded border border-rojo/40 bg-rojo/5 p-2">
          <p className="text-xs font-medium text-rojo">
            No se pudo comprobar si el cálculo de hoy coincide con lo que se pagó: {diferenciasError}
          </p>
        </div>
      ) : diferencias.length > 0 && (
        <div className="mt-3 rounded border border-rojo/40 bg-rojo/5 p-2">
          <p className="text-xs font-medium text-rojo">
            El cálculo de hoy ya no coincide con lo que se pagó. La cifra pagada NO se cambia:
          </p>
          <ul className="mt-1 text-xs text-rojo">
            {diferencias.map((x) => (
              <li key={x.concepto}>
                {x.concepto}: se pagó {formatSoles(x.pagado)}, hoy daría {formatSoles(x.ahora)}{" "}
                ({x.diferencia > 0 ? "+" : ""}{formatSoles(x.diferencia)})
              </li>
            ))}
          </ul>
          <p className="mt-1 text-xs text-taupe">
            Qué hacer con la diferencia —pagarla, compensarla o dejar constancia— es una decisión
            tuya: el sistema la nombra, no la resuelve.
          </p>
        </div>
      )}

      <div className="mt-3 flex flex-wrap items-center gap-2">
        <Boton variante="secundario" tamano="sm" onClick={() => window.print()}>
          Imprimir hoja para firmar
        </Boton>
        {/* La nota y el botón de congelar sirven en los DOS estados. Antes solo
            se dibujaban con `!pagada`, así que el texto de abajo prometía un
            botón para «volver a marcarla» que no existía: la única frase de la
            pantalla que decía cómo deshacer algo apuntaba a un sitio vacío. */}
        {/* Sin "text-xs" ni "py-1" a propósito: cx() solo fusiona relleno,
            radio y color, no tamaño de letra — pelear el "text-base sm:text-sm"
            propio de Campo desde acá no tiene ganador garantizado. El tamaño
            de Campo ya es el correcto (evita el zoom de Safari al enfocar). */}
        <Campo
          etiqueta="Nota"
          value={nota}
          onChange={(e) => setNota(e.target.value)}
          placeholder="ej. transferencia BCP"
          className="w-48"
        />
        <Boton variante="primario" tamano="sm" onClick={onPagar} disabled={ocupado}>
          {pagada ? "Volver a marcarla como pagada" : "Marcar como pagada"}
        </Boton>
        {pagada && (
          <>
            {/* Deshacer. La base sabe hacerlo desde la 0251 y ninguna pantalla se
                lo pedía. Va en rojo y separado del de congelar porque son cosas
                distintas: uno recalcula, el otro retira la cifra de la cuenta. */}
            <Boton variante="peligro" tamano="sm" onClick={onAnular} disabled={ocupado}>
              Anular — se marcó por error
            </Boton>
            <span className="flex items-center gap-2 text-xs text-taupe">
              {miFirma && <img src={miFirma} alt="Firma" className="h-6 w-auto" />}
              Ya congelada. Volver a marcarla guarda una versión nueva; la anterior queda como histórico.
            </span>
          </>
        )}
      </div>
    </div>
  );
}

// ── La hoja ────────────────────────────────────────────────────────────────
// Solo se ve al imprimir. Lleva el desglose entero porque quien se va suele
// revisar, y un total sin explicar obliga a discutirlo de palabra — además de
// ser lo que hay que exhibir si reclama después.
function Hoja({ d, miFirma }: { d: Detalle; miFirma: string | null }) {
  const hoy = hoyLima();
  return (
    <div className="hidden print:block">
      <h1 className="font-serif text-xl">Liquidación de beneficios sociales</h1>
      <p className="mt-1 text-sm">
        <strong>{s(d.persona)}</strong><br />
        Ingreso: {fechaLarga(s(d.fecha_ingreso))} · Cese: {fechaLarga(s(d.fecha_cese))}
      </p>

      <table className="mt-4 w-full text-sm">
        <tbody>
          <tr className="align-top">
            <td className="py-2 pr-3">
              Sueldo del periodo
              {d.periodo && (
                <span className="block text-xs">
                  del {fechaLarga(d.periodo.desde)} al {fechaLarga(d.periodo.hasta)}
                </span>
              )}
            </td>
            <td className="py-2 text-right tabular-nums">{formatSoles(n(d.periodo?.monto))}</td>
          </tr>
          <Linea etiqueta="Vacaciones truncas"   jsonb={d.vacaciones_truncas} />
          <Linea etiqueta="Gratificación trunca" jsonb={d.gratificacion_trunca} />
          <Linea etiqueta="CTS trunca"           jsonb={d.cts_trunca} />
          <tr className="border-t-2 border-black">
            <td className="py-2 font-medium">Total a pagar</td>
            <td className="py-2 text-right font-medium tabular-nums">{formatSoles(n(d.total))}</td>
          </tr>
        </tbody>
      </table>

      <p className="mt-6 text-xs">
        Declaro haber recibido conforme el monto detallado, correspondiente a la liquidación de mis
        beneficios sociales por el periodo indicado.
      </p>

      <div className="mt-12 flex justify-between text-xs">
        <div>
          <div className="w-56 border-t border-black pt-1">Firma de la integrante</div>
          <div className="mt-1">{s(d.persona)}</div>
        </div>
        <div>
          {miFirma && <img src={miFirma} alt="Firma" className="h-14 w-auto" />}
          <div className="w-56 border-t border-black pt-1">Por CAYLA</div>
          <div className="mt-1">Fecha: {fechaLarga(hoy)}</div>
        </div>
      </div>
    </div>
  );
}

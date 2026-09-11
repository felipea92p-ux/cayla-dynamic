"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Cargando } from "@/components/cargando";
import { useToast } from "@/components/toast";
import { useRolActual } from "@/lib/admin/use-rol";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { formatSoles } from "@/lib/rangos";
import { EMPRESA, hoyLima, puedeVerPlanilla } from "@cayla-dynamic/shared";
import { Boton } from "@/components/ui/boton";
import { Campo } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { Modal } from "@/components/ui/modal";
import { Insignia } from "@/components/ui/insignia";

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

// Lo que devuelve fn_papeles_cese (0400): identidad y tiempo de servicio para
// el certificado de trabajo y la constancia de cese. El motivo de cese viaja
// acá porque le sirve a quien genera el papel en pantalla — pero ningún
// componente de impresión lo muestra: no es lo que corresponde en ninguno de
// los dos documentos.
interface PapelesCese {
  nombre_completo: string;
  documento: string | null;
  genero: "masculino" | "femenino" | null;
  cargo: string | null;
  sede: string | null;
  fecha_ingreso: string;
  fecha_cese: string;
  motivo_cese: string | null;
  tiempo_servicio_anios: number;
  tiempo_servicio_meses: number;
  tiempo_servicio_dias: number;
}

function tiempoDeServicio(p: PapelesCese): string {
  const partes: string[] = [];
  if (p.tiempo_servicio_anios > 0) {
    partes.push(`${p.tiempo_servicio_anios} año${p.tiempo_servicio_anios === 1 ? "" : "s"}`);
  }
  if (p.tiempo_servicio_meses > 0) {
    partes.push(`${p.tiempo_servicio_meses} mes${p.tiempo_servicio_meses === 1 ? "" : "es"}`);
  }
  if (p.tiempo_servicio_dias > 0 || partes.length === 0) {
    partes.push(`${p.tiempo_servicio_dias} día${p.tiempo_servicio_dias === 1 ? "" : "s"}`);
  }
  return partes.join(" y ");
}

// Quién firma el certificado y la constancia por CAYLA NO se escribe acá: vive
// en `configuracion.firmante_empresa` (0147), la misma fuente que ya usa el
// generador de Contratos — validada por trigger, con nombre y DNI resueltos
// desde la ficha de esa persona, nunca un literal en este archivo.
interface FirmanteEmpresa { nombre: string; dni: string | null; cargo: string; personaId: string }

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
  const [firmanteEmpresa, setFirmanteEmpresa] = useState<FirmanteEmpresa | null>(null);
  const [esFirmanteEmpresa, setEsFirmanteEmpresa] = useState(false);

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

  // ── Papeles de salida: certificado de trabajo y constancia de cese ────────
  // Se cargan junto con el desglose de la liquidación, no con un clic aparte:
  // los tres son "los papeles que le corresponden a quien cesó" y hoy ya se
  // buscan juntos en Liquidaciones.
  const [papelesCese, setPapelesCese] = useState<PapelesCese | null>(null);
  const [apreciacion, setApreciacion] = useState("");
  // La vista previa, no la impresión directa. `null` = ningún documento
  // abierto. El mismo mecanismo que ya usan Contratos, la boleta, Política
  // salarial y Documentación — antes esta pantalla era la única que llamaba a
  // `window.print()` a ciegas, sin dejar revisar el papel primero.
  const [modalAbierto, setModalAbierto] =
    useState<"liquidacion" | "certificado" | "constancia" | null>(null);

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

  // Quién certifica y hace constar por CAYLA — para el pie del certificado y
  // la constancia, no para la liquidación (esa sigue siendo "Por CAYLA" con la
  // firma de quien la paga, sin cambios). Un documento que sale de la empresa
  // hacia un banco o un futuro empleador necesita decir QUIÉN certifica, no
  // solo mostrar una firma sin nombre debajo.
  useEffect(() => {
    void (async () => {
      const [cfg, yo] = await Promise.all([
        supabase.from("configuracion").select("valor").eq("clave", "firmante_empresa").maybeSingle(),
        supabase.rpc("fn_persona_actual_id"),
      ]);
      const cfgValor = (cfg.data as { valor: { persona_id?: string; cargo?: string } } | null)?.valor;
      if (!cfgValor?.persona_id) return;
      const { data: ficha } = await supabase
        .from("personas")
        .select("nombres, apellidos, documento")
        .eq("id", cfgValor.persona_id)
        .maybeSingle();
      if (!ficha) return;
      setFirmanteEmpresa({
        nombre: `${ficha.nombres} ${ficha.apellidos}`,
        dni: ficha.documento,
        cargo: cfgValor.cargo ?? "Gerencia General",
        personaId: cfgValor.persona_id,
      });
      // La firma escaneada SOLO se estampa si quien tiene la sesión abierta es
      // la misma persona designada como firmante — igual que Contratos
      // (`esFirmante`). Sin este candado, cualquier líder que abra el
      // documento estamparía SU PROPIA firma debajo del nombre de otra
      // persona: el papel quedaría firmado por alguien que nunca lo firmó.
      setEsFirmanteEmpresa(Boolean(yo.data) && yo.data === cfgValor.persona_id);
    })();
  }, [supabase]);

  async function cargarDetalle(personaId: string) {
    const [liq, dif, papeles] = await Promise.all([
      supabase.rpc("fn_liquidacion", { p_persona_id: personaId }),
      supabase.rpc("fn_liquidacion_diferencias", { p_persona_id: personaId }),
      supabase.rpc("fn_papeles_cese", { p_persona_id: personaId }),
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
    // Sin bloquear la pantalla si esto falla: los papeles de salida son un
    // extra sobre la liquidación, no una condición para verla. Si falla, los
    // dos botones nuevos simplemente no aparecen (quedan detrás de `papelesCese`).
    setPapelesCese(papeles.error ? null : (papeles.data as unknown as PapelesCese));
  }

  async function abrir(personaId: string) {
    if (abierta === personaId) {
      setAbierta(null); setDetalle(null); setDiferencias([]); setDiferenciasError(null); setPapelesCese(null);
      return;
    }
    setAbierta(personaId); setDetalle(null); setDiferencias([]); setDiferenciasError(null); setPapelesCese(null);
    setNota(""); setApreciacion(""); setModalAbierto(null);
    await cargarDetalle(personaId);
  }

  // Abre la vista previa; no imprime todavía. Antes esto llamaba a
  // `window.print()` a ciegas — inconsistente con Contratos, la boleta,
  // Política salarial y Documentación, que sí dejan revisar el papel primero
  // dentro de un recuadro con sus propios botones "Imprimir / Guardar como
  // PDF" y "Cerrar".
  function imprimir(doc: "liquidacion" | "certificado" | "constancia") {
    setModalAbierto(doc);
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

  // El nombre con el que se guarda el PDF. Ver use-titulo-documento.ts: sin
  // esto, los tres papeles de esta pantalla —liquidación, certificado de
  // trabajo, constancia de cese— se guardaban todos como «Dynamic — CAYLA», y
  // son justo los que se entregan a alguien que ya se fue de la empresa.
  useTituloDocumento(
    modalAbierto === "liquidacion" && detalle
      ? `${detalle.persona} — Liquidación de beneficios sociales`
      : modalAbierto === "certificado" && papelesCese
        ? `${papelesCese.nombre_completo} — Certificado de trabajo`
        : modalAbierto === "constancia" && papelesCese
          ? `${papelesCese.nombre_completo} — Constancia de cese`
          : null,
  );

  if (cargando) return <Cargando />;

  if (!puede) {
    return (
      <div className="flex flex-1 flex-col">
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
    <div className="flex flex-1 flex-col">

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
            <p className="mb-4 rounded-control border border-rojo bg-rojo/5 p-3 text-sm text-rojo">
              No se pudo leer la lista: {cargaError}
            </p>
          )}

          {/* ── El aviso del vínculo «prueba» ────────────────────────────────
              Va acá y no en Equipo porque lo que está en juego son beneficios, y
              esta es la pantalla que habla de beneficios. Solo aparece cuando ya
              pasó el mes: antes no cuesta nada y avisar sería ruido. */}
          {avisoUrgente.map((a) => (
            <div key={a.persona_id} className="mb-4 rounded-control border border-rojo bg-rojo/5 p-3 text-sm">
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
            papelesCese={papelesCese} apreciacion={apreciacion} setApreciacion={setApreciacion}
            onImprimir={imprimir}
          />

          {vencidas.length > 0 && (
            <Bloque
              titulo={`Pasadas de plazo · ${vencidas.length}`}
              vacio="" filas={vencidas} abierta={abierta} onAbrir={abrir}
              detalle={detalle} diferencias={diferencias} diferenciasError={diferenciasError} nota={nota} setNota={setNota}
              ocupado={ocupado} onPagar={abrirPagar} onAnular={abrirAnular} miFirma={miFirma} urgente
              papelesCese={papelesCese} apreciacion={apreciacion} setApreciacion={setApreciacion}
              onImprimir={imprimir}
            />
          )}

          {pagadas.length > 0 && (
            <Bloque
              titulo={`Pagadas · ${pagadas.length}`}
              vacio="" filas={pagadas} abierta={abierta} onAbrir={abrir}
              detalle={detalle} diferencias={diferencias} diferenciasError={diferenciasError} nota={nota} setNota={setNota}
              ocupado={ocupado} onPagar={abrirPagar} onAnular={abrirAnular} miFirma={miFirma}
              papelesCese={papelesCese} apreciacion={apreciacion} setApreciacion={setApreciacion}
              onImprimir={imprimir}
            />
          )}
        </div>

        {/* ── La vista previa del documento ────────────────────────────────
            Mismo recuadro que ya usan Contratos, la boleta, Política salarial
            y Documentación: se revisa antes de imprimir, no se manda a
            ciegas. `print:static print:block print:bg-transparent` en el
            fondo y `print:max-h-none ... print:border-0` en la tarjeta son
            los que hacen que, al imprimir de verdad, quede la hoja sola y no
            el recuadro ni el velo oscuro alrededor. */}
        {modalAbierto && (
          <div
            className="fixed inset-0 z-40 flex items-center justify-center bg-black/40 p-4 print:static print:block print:bg-transparent print:p-0"
            onClick={() => setModalAbierto(null)}
          >
            <div
              role="dialog"
              aria-modal="true"
              aria-label={
                modalAbierto === "liquidacion" ? "Liquidación de beneficios sociales"
                : modalAbierto === "certificado" ? "Certificado de trabajo"
                : "Constancia de cese"
              }
              className="flex max-h-[90vh] w-full max-w-3xl flex-col overflow-hidden rounded-flotante border border-sand bg-crema print:max-h-none print:w-auto print:max-w-none print:overflow-visible print:rounded-none print:border-0"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex items-center gap-3 border-b border-sand bg-sand/30 px-4 py-2 print:hidden">
                <button className="rounded bg-tinta px-4 py-2 text-sm text-crema" onClick={() => window.print()}>
                  Imprimir / Guardar como PDF
                </button>
                <button className="text-sm underline" onClick={() => setModalAbierto(null)}>
                  Cerrar
                </button>
              </div>
              <div className="hoja overflow-y-auto p-8 text-sm leading-relaxed print:overflow-visible print:p-0">
                {modalAbierto === "liquidacion" && detalle && <Hoja d={detalle} miFirma={miFirma} />}
                {modalAbierto === "certificado" && papelesCese && (
                  <HojaCertificado
                    p={papelesCese} apreciacion={apreciacion} firmante={firmanteEmpresa}
                    firma={esFirmanteEmpresa ? miFirma : null}
                  />
                )}
                {modalAbierto === "constancia" && papelesCese && (
                  <HojaConstancia
                    p={papelesCese} detalle={detalle} firmante={firmanteEmpresa}
                    firma={esFirmanteEmpresa ? miFirma : null}
                  />
                )}
              </div>
            </div>
          </div>
        )}
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
  papelesCese, apreciacion, setApreciacion, onImprimir,
}: {
  titulo: string; vacio: string; filas: Pendiente[];
  abierta: string | null; onAbrir: (id: string) => void;
  detalle: Detalle | null; diferencias: Diferencia[]; diferenciasError: string | null;
  nota: string; setNota: (v: string) => void;
  ocupado: boolean;
  onPagar: (id: string, nombre: string, total: number, yaPagada: boolean) => void;
  onAnular: (id: string, nombre: string) => void;
  miFirma: string | null; urgente?: boolean;
  papelesCese: PapelesCese | null; apreciacion: string; setApreciacion: (v: string) => void;
  onImprimir: (doc: "liquidacion" | "certificado" | "constancia") => void;
}) {
  return (
    <div className="mb-4 overflow-hidden rounded-superficie border border-sand bg-papel">
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
                    <Insignia variante="alerta" className="ml-2">
                      el cálculo ya no coincide
                    </Insignia>
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
                  papelesCese={papelesCese} apreciacion={apreciacion} setApreciacion={setApreciacion}
                  onImprimir={onImprimir}
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
  papelesCese, apreciacion, setApreciacion, onImprimir,
}: {
  d: Detalle; diferencias: Diferencia[]; diferenciasError: string | null; pagada: boolean;
  nota: string; setNota: (v: string) => void; ocupado: boolean;
  onPagar: () => void; onAnular: () => void;
  miFirma: string | null;
  papelesCese: PapelesCese | null; apreciacion: string; setApreciacion: (v: string) => void;
  onImprimir: (doc: "liquidacion" | "certificado" | "constancia") => void;
}) {
  return (
    <div className="mt-3 rounded-control border border-sand bg-sand/20 p-3">
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
        <Boton variante="secundario" tamano="sm" onClick={() => onImprimir("liquidacion")}>
          Imprimir hoja para firmar
        </Boton>
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
        <Boton variante="primario" tamano="sm" onClick={onPagar} disabled={ocupado} cargando={ocupado}>
          {pagada ? "Volver a marcarla como pagada" : "Marcar como pagada"}
        </Boton>
      </div>

      {/* ── Papeles de salida ─────────────────────────────────────────────
          Van en su propia fila, separados de "marcar pagada/anular": esos
          mueven dinero, estos entregan un documento. El Reglamento Interno
          (num. 59.6) los junta con la liquidación en el mismo plazo legal —
          por eso viven en esta pantalla y no en otra — pero son una acción de
          naturaleza distinta y mezclarlos en una sola fila de botones repite
          el mismo error de sobrecarga visual que ya se corrigió hoy en
          Contratos. */}
      <div className="mt-3 border-t border-sand pt-3">
        <p className="mb-2 text-xs font-medium text-taupe">Papeles de salida</p>
        <div className="flex flex-wrap items-center gap-2">
          <Boton variante="secundario" tamano="sm" onClick={() => onImprimir("certificado")} disabled={!papelesCese}>
            Certificado de trabajo
          </Boton>
          <Boton variante="secundario" tamano="sm" onClick={() => onImprimir("constancia")} disabled={!papelesCese}>
            Constancia de cese
          </Boton>
          <Campo
            etiqueta="Apreciación (opcional)"
            value={apreciacion}
            onChange={(e) => setApreciacion(e.target.value)}
            placeholder="de conducta o rendimiento — va en el certificado"
            className="min-w-[22rem] flex-1"
          />
        </div>
      </div>

      {/* La nota y el botón de congelar sirven en los DOS estados. Antes solo
          se dibujaban con `!pagada`, así que el texto de abajo prometía un
          botón para «volver a marcarla» que no existía: la única frase de la
          pantalla que decía cómo deshacer algo apuntaba a un sitio vacío. */}
      {pagada && (
        <div className="mt-3 flex flex-wrap items-center gap-2 border-t border-sand pt-3">
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
        </div>
      )}
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
    <>
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
          <tr className="border-t-2 border-tinta">
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
          <div className="w-56 border-t border-tinta pt-1">Firma de la integrante</div>
          <div className="mt-1">{s(d.persona)}</div>
        </div>
        <div>
          {miFirma && <img src={miFirma} alt="Firma" className="h-14 w-auto" />}
          <div className="w-56 border-t border-tinta pt-1">Por CAYLA</div>
          <div className="mt-1">Fecha: {fechaLarga(hoy)}</div>
        </div>
      </div>
    </>
  );
}

// ── El certificado de trabajo y la constancia de cese ───────────────────────
//
// Los dos comparten forma —identidad, EMPRESA, firma solo de CAYLA— pero no
// contenido: el certificado prueba QUÉ HIZO (cargo, tiempo de servicio, y a
// pedido, una apreciación); la constancia prueba QUE EL VÍNCULO TERMINÓ, que
// es lo único que un banco necesita para soltar la CTS. Ninguno de los dos
// menciona el motivo del cese — no es su función, y decirlo por escrito en el
// papel que la persona lleva a su próximo trabajo sería exactamente lo que
// estos documentos existen para evitar.

function Identidad({ p }: { p: PapelesCese }) {
  const identificadoTexto = p.genero === "masculino" ? "identificado" : "identificada";
  return (
    <>
      <strong>{p.nombre_completo}</strong>
      {p.documento && <>, {identificadoTexto} con DNI N.° {p.documento},</>}
    </>
  );
}

// El bloque de firma de los dos documentos que salen hacia afuera: el nombre y
// el cargo de quien certifica van SIEMPRE (es lo que hace válido el papel ante
// un tercero); la imagen de la firma solo si quien tiene la sesión abierta es
// esa misma persona (`firma`, ya resuelto por el llamador con `esFirmanteEmpresa`).
function FirmaEmpresa({ firmante, firma }: { firmante: FirmanteEmpresa | null; firma: string | null }) {
  return (
    <div className="text-center text-xs">
      {firma && <img src={firma} alt="Firma" className="mx-auto h-14 w-auto" />}
      <div className="w-56 border-t border-tinta pt-1">{firmante?.nombre ?? "—"}</div>
      {firmante?.dni && <div>DNI N.° {firmante.dni}</div>}
      <div>{firmante?.cargo ?? "Gerencia General"}</div>
      <div>{EMPRESA.nombre}</div>
    </div>
  );
}

function HojaCertificado({
  p, apreciacion, firmante, firma,
}: { p: PapelesCese; apreciacion: string; firmante: FirmanteEmpresa | null; firma: string | null }) {
  const hoy = hoyLima();
  return (
    <>
      <h1 className="text-center font-serif text-xl uppercase">Certificado de trabajo</h1>

      <p className="mt-6 text-sm leading-relaxed">
        {EMPRESA.nombre}, con RUC N.° {EMPRESA.ruc} y domicilio en {EMPRESA.domicilio}:
      </p>

      <p className="mt-4 text-sm font-medium leading-relaxed">CERTIFICA:</p>

      <p className="mt-2 text-sm leading-relaxed">
        Que <Identidad p={p} /> prestó servicios en nuestra empresa bajo el régimen laboral de la
        actividad privada, desde el {fechaLarga(p.fecha_ingreso)} hasta el {fechaLarga(p.fecha_cese)},
        desempeñando el cargo de <strong>{p.cargo ?? "—"}</strong>
        {p.sede && <> en la sede {p.sede}</>}, con un tiempo de servicios de{" "}
        <strong>{tiempoDeServicio(p)}</strong>.
      </p>

      {apreciacion.trim() !== "" && (
        <p className="mt-4 text-sm leading-relaxed">
          A solicitud de la persona interesada, se deja constancia de lo siguiente respecto de su
          conducta y rendimiento durante su vínculo laboral: «{apreciacion.trim()}»
        </p>
      )}

      <p className="mt-4 text-sm leading-relaxed">
        Se expide el presente certificado a solicitud de la parte interesada, para los fines que
        estime convenientes.
      </p>

      <p className="mt-8 text-xs">
        Trujillo, {fechaLarga(hoy)}.
      </p>

      <div className="mt-12 flex justify-end">
        <FirmaEmpresa firmante={firmante} firma={firma} />
      </div>

      <p className="mt-8 text-[10px] text-taupe">
        Conforme al numeral 59.6 a) del Reglamento Interno de Trabajo y a la Tercera Disposición
        Complementaria, Transitoria, Derogatoria y Final del D.S. N.° 001-96-TR.
      </p>
    </>
  );
}

function HojaConstancia({
  p, detalle, firmante, firma,
}: { p: PapelesCese; detalle: Detalle | null; firmante: FirmanteEmpresa | null; firma: string | null }) {
  const hoy = hoyLima();
  const cts = detalle?.cts_trunca as Record<string, unknown> | undefined;
  const yaDepositado = cts?.ya_depositado !== undefined ? n(cts.ya_depositado) : null;

  return (
    <>
      <h1 className="text-center font-serif text-xl uppercase">Constancia de cese</h1>

      <p className="mt-6 text-sm leading-relaxed">
        {EMPRESA.nombre}, con RUC N.° {EMPRESA.ruc} y domicilio en {EMPRESA.domicilio}:
      </p>

      <p className="mt-4 text-sm font-medium leading-relaxed">HACE CONSTAR:</p>

      <p className="mt-2 text-sm leading-relaxed">
        Que el vínculo laboral que mantenía con <Identidad p={p} /> ha concluido con fecha{" "}
        <strong>{fechaLarga(p.fecha_cese)}</strong>, luego de un tiempo de servicios de{" "}
        <strong>{tiempoDeServicio(p)}</strong> (ingreso: {fechaLarga(p.fecha_ingreso)}).
      </p>

      {yaDepositado !== null && yaDepositado > 0 && (
        <p className="mt-4 text-sm leading-relaxed">
          A la fecha de esta constancia, la empresa tiene depositado a su favor{" "}
          {formatSoles(yaDepositado)} por concepto de Compensación por Tiempo de Servicios (CTS).
        </p>
      )}

      <p className="mt-4 text-sm leading-relaxed">
        Se expide la presente constancia para que la persona interesada acredite su cese ante la
        entidad financiera depositaria y proceda al retiro de su Compensación por Tiempo de
        Servicios y sus intereses, conforme al artículo 45 del Decreto Supremo N.° 001-97-TR.
      </p>

      <p className="mt-8 text-xs">
        Trujillo, {fechaLarga(hoy)}.
      </p>

      <div className="mt-12 flex justify-end">
        <FirmaEmpresa firmante={firmante} firma={firma} />
      </div>

      <p className="mt-8 text-[10px] text-taupe">
        Conforme al numeral 59.6 b) del Reglamento Interno de Trabajo y al artículo 45 del
        D.S. N.° 001-97-TR.
      </p>
    </>
  );
}

"use client";

import { Fragment, useCallback, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Cargando } from "@/components/cargando";
import { useToast } from "@/components/toast";
import { useRolActual } from "@/lib/admin/use-rol";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { generarCsv, descargarCsv } from "@/lib/admin/csv";
import { formatSoles } from "@/lib/rangos";
import {
  dondeSePaga, normalizarPeriodosAnteriores, resumenPeriodosAnteriores, type PeriodoAnterior,
} from "@/lib/admin/liquidacion-periodos";
import {
  APOYOS_CONSTANCIA, EMPRESA, ETIQUETA_APOYO, ETIQUETA_DECISION, decisionesPara, fechaLima, hoyLima,
  motivoDeConstanciaValido, nombreCorto, nombreOficial, puedeEstamparFirmaDeEmpresa, puedeVerPlanilla,
  queDibujarDeLaConstancia, usaNombreDelDni,
  type ApoyoConstancia, type DecisionConstancia, type EstadoRegistroDiferencia, type FilaDiferenciaConstancia,
} from "@cayla-dynamic/shared";
import { Boton } from "@/components/ui/boton";
import { Campo } from "@/components/ui/campo";
import { CampoSelect } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { Modal } from "@/components/ui/modal";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { AyudaPantalla } from "@/components/ui/ayuda-pantalla";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { ParaAtender } from "@/components/ui/para-atender";
import { Pestanas } from "@/components/ui/pestanas";
import { sobretituloDeHoy } from "@/lib/admin/sobretitulo";
import { Tabla, TablaEncabezado, Th, Fila } from "@/components/ui/tabla";

// Liquidación por cese. La ley da 48 HORAS desde el cese para pagar (art. 4 del
// D.S. 001-97-TR), así que esta pantalla existe para que ese plazo no dependa de
// que alguien arme la cuenta a mano un viernes por la tarde.
//
// REDISEÑADO 2026-09-15, tras una auditoría funcional/legal/financiera/UX
// completa (ver docs/estado.md). Las tres decisiones de arquitectura, sin
// reabrir ninguna fórmula, ningún plazo legal ni el congelamiento:
//
//   1. TABS POR ESTADO + RESUMEN. Pendientes/Vencidas/Pagadas con conteos
//      reales arriba, y cuatro cifras accionables encima de las tabs.
//   2. VENCIDAS SOLO EN SU TAB. Sin franja permanente: su propio conteo en
//      rojo en la pestaña es la señal.
//   3. DIFERENCIA ESPERADA vs REAL, SOLO DENTRO DEL DESGLOSE.
//      `fn_liquidacion_diferencias` (0454) dice si una diferencia la explica
//      el descuento que el cierre de Planilla obliga a registrar (0244) — el
//      estado normal de casi toda cesada, no una avería — o si es una
//      diferencia de verdad. Se muestra al abrir una liquidación pagada: la
//      esperada en tono neutro, la real en rojo. Hasta el 2026-10-21 la real
//      además encendía una insignia en la fila, una pastilla en «Para
//      atender» y un filtro; se quitaron porque una liquidación ya pagada no
//      tiene cómo cerrar ese aviso —no hay un «dejar constancia»—, así que
//      «3 con diferencias» no bajaba nunca y acababa leyéndose como ruido.
//
// QUÉ MUESTRA Y QUÉ NO. Todas las cesadas con liquidación por resolver, sin
// filtrar por vínculo. `fn_liquidaciones_pendientes` no descarta los totales
// en cero: una locadora o alguien de un día de prueba aparece igual, porque el
// plazo de 48 horas corre para todas — pero quedan fuera de lo urgente (ver
// «Sin nada que cobrar» al pie de Pendientes), a propósito: no compiten
// visualmente con quien sí tiene dinero real en juego.

// Por string, nunca `new Date()`: construir una fecha desde el navegador puede
// correrla un día por zona horaria, y acá una fecha decide un plazo legal.
function fechaLarga(iso: string | null | undefined): string {
  if (!iso) return "—";
  const [y, m, d] = iso.split("-");
  if (!y || !m || !d) return iso;
  return `${d}/${m}/${y}`;
}

function fechaCorta(iso: string | null | undefined): string {
  if (!iso) return "—";
  const [, m, d] = iso.split("-");
  const MES = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];
  const idx = Number(m) - 1;
  if (!d || Number.isNaN(idx) || !MES[idx]) return iso;
  return `${d} ${MES[idx]}`;
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
  descuadra_real: boolean;
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
  origen: "esperada_por_cierre" | "real";
}

interface Sede {
  id: string;
  codigo: string;
  nombre: string;
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
  // Lo agrega `cargarDetalle` desde `fn_liquidacion_periodos_anteriores` (0565),
  // no viene de `fn_liquidacion`: es informativo y NO está dentro de `total`.
  // `null` = no se pudo leer (se dice, no se calla); `[]` = no hay nada anterior.
  periodos_anteriores?: PeriodoAnterior[] | null;
};

// Lo que devuelve fn_papeles_cese (0400): identidad y tiempo de servicio para
// el certificado de trabajo y la constancia de cese. El motivo de cese viaja
// acá porque le sirve a quien genera el papel en pantalla — pero ningún
// componente de impresión lo muestra: no es lo que corresponde en ninguno de
// los dos documentos.
interface PapelesCese {
  // Ojo con el nombre: `fn_papeles_cese` (0400) lo arma como «nombres apellidos»
  // —el corto, el del terminal—, no como el del DNI. Esta pantalla lo REEMPLAZA
  // al cargar (ver `cargarDetalle`) por `datos_personales.nombre_dni`, que es el
  // que un banco compara contra el documento al soltar la CTS. Para cuando
  // llega a un componente de impresión, `nombre_completo` ya es el bueno.
  nombre_completo: string;
  // Lo agrega esta pantalla, no la función: la ficha no tiene cargado el nombre
  // del DNI, así que el papel saldrá con el corto. Se avisa en la vista previa
  // porque estos dos papeles no se corrigen una vez entregados.
  sinNombreDni?: boolean;
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

type Tab = "pendientes" | "vencidas" | "pagadas";

export default function LiquidacionesPage() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const { avisar } = useToast();
  const rol = useRolActual();
  const supabase = createAdminSupabaseClient();

  const [pendientes, setPendientes] = useState<Pendiente[]>([]);
  const [avisos, setAvisos] = useState<AvisoVinculo[]>([]);
  const [sedes, setSedes] = useState<Sede[]>([]);
  const [cargando, setCargando] = useState(true);
  const [cargaError, setCargaError] = useState<string | null>(null);

  // ── Tabs, búsqueda y filtros (Decisión I: tabs por estado + resumen) ──────
  const [tab, setTab] = useState<Tab>("pendientes");
  const [busqueda, setBusqueda] = useState("");
  const [filtroSede, setFiltroSede] = useState("");

  const [abierta, setAbierta] = useState<string | null>(null);
  const [detalle, setDetalle] = useState<Detalle | null>(null);
  const [diferencias, setDiferencias] = useState<Diferencia[]>([]);
  const [diferenciasError, setDiferenciasError] = useState<string | null>(null);
  // Qué pasó con una diferencia real (0542). `null` en cualquiera de los dos
  // es «no sé» —la 0542 todavía no está pegada, o la lectura falló—, y la
  // pantalla se comporta como antes: ver `queDibujarDeLaConstancia`.
  const [constancia, setConstancia] = useState<EstadoRegistroDiferencia | null>(null);
  const [constanciaError, setConstanciaError] = useState<string | null>(null);
  const [registroAccion, setRegistroAccion] =
    useState<{ personaId: string; nombre: string; modo: "registrar" | "corregir" | "retirar" } | null>(null);
  const [registroDecision, setRegistroDecision] = useState<DecisionConstancia | "">("");
  const [registroApoyo, setRegistroApoyo] = useState<ApoyoConstancia | "">("");
  const [registroMotivo, setRegistroMotivo] = useState("");
  const [ocupado, setOcupado] = useState(false);
  const [nota, setNota] = useState("");
  const [miFirma, setMiFirma] = useState<string | null>(null);
  const [firmanteEmpresa, setFirmanteEmpresa] = useState<FirmanteEmpresa | null>(null);
  // La firma de QUIEN FIRMA POR CAYLA (`fn_firma_empresa`, 0398), no la de quien
  // tenga la sesión abierta. `miFirma` queda para la hoja de la liquidación.
  const [firmaEmpresa, setFirmaEmpresa] = useState<string | null>(null);

  // Confirmaciones que antes eran window.confirm()/window.prompt(): Felipe
  // aprobó migrar todos los diálogos nativos del panel al Modal compartido
  // (ver CLAUDE.md). Cada uno lleva solo lo que la fila necesitaba para armar
  // el mensaje — no el objeto Pendiente entero, que puede quedar desfasado
  // mientras el modal sigue abierto.
  const [pagoAccion, setPagoAccion] = useState<
    { personaId: string; nombre: string; total: number; yaPagada: boolean; fechaCese: string; venceEl: string } | null
  >(null);
  // La fecha real de pago (0454): nace en HOY, nunca vacía — la regla de la
  // casa sobre campos de fecha que bloquean el envío (CLAUDE.md, 2026-08-26).
  const [fechaPago, setFechaPago] = useState(hoyLima());
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

    const [lista, av, sedesRes] = await Promise.all([
      supabase.rpc("fn_liquidaciones_pendientes"),
      supabase.rpc("fn_avisos_vinculo"),
      supabase.from("sedes").select("id, codigo, nombre").order("codigo"),
    ]);
    setPendientes((lista.data as Pendiente[]) ?? []);
    setAvisos((av.data as AvisoVinculo[]) ?? []);
    setSedes((sedesRes.data as Sede[]) ?? []);
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
      const [cfg, fe] = await Promise.all([
        supabase.from("configuracion").select("valor").eq("clave", "firmante_empresa").maybeSingle(),
        supabase.rpc("fn_firma_empresa"),
      ]);
      const cfgValor = (cfg.data as { valor: { persona_id?: string; cargo?: string } } | null)?.valor;
      if (!cfgValor?.persona_id) return;
      const [{ data: ficha }, { data: dpFirmante }] = await Promise.all([
        supabase
          .from("personas")
          .select("nombres, apellidos, documento")
          .eq("id", cfgValor.persona_id)
          .maybeSingle(),
        supabase
          .from("datos_personales")
          .select("nombre_dni")
          .eq("persona_id", cfgValor.persona_id)
          .maybeSingle(),
      ]);
      if (!ficha) return;
      setFirmanteEmpresa({
        // Quien certifica firma con su nombre del DNI, igual que quien recibe el
        // papel: un certificado entre «Elida Lizeth Salinas Mamani» y una firma
        // de «Felipe Alvarez» no se ve de la misma empresa.
        nombre: nombreOficial(
          dpFirmante?.nombre_dni as string | null | undefined,
          nombreCorto(ficha.nombres, ficha.apellidos),
        ),
        dni: ficha.documento,
        cargo: cfgValor.cargo ?? "Gerencia General",
        personaId: cfgValor.persona_id,
      });
      // La firma que se estampa es SIEMPRE la de la persona designada como
      // firmante, no la de quien tiene la sesión abierta: `fn_firma_empresa` no
      // recibe parámetros y sale de la misma fila que el nombre impreso, así
      // que nadie estampa SU PROPIA firma debajo del nombre de otra persona.
      // Antes solo se estampaba si el firmante tenía la sesión abierta; con otra
      // cuenta el certificado salía sin firma.
      setFirmaEmpresa(typeof fe.data === "string" && fe.data.startsWith("data:image") ? fe.data : null);
    })();
  }, [supabase]);

  async function cargarDetalle(personaId: string) {
    const [liq, dif, papeles, con, ant] = await Promise.all([
      supabase.rpc("fn_liquidacion", { p_persona_id: personaId }),
      supabase.rpc("fn_liquidacion_diferencias", { p_persona_id: personaId }),
      supabase.rpc("fn_papeles_cese", { p_persona_id: personaId }),
      // De una liquidación sin pagar devuelve cero filas, y barato.
      supabase.rpc("fn_liquidacion_constancia_estado", { p_persona_id: personaId }),
      // Lo que se le debe de periodos ANTERIORES al del cese (0565). Informativo.
      supabase.rpc("fn_liquidacion_periodos_anteriores", { p_persona_id: personaId }),
    ]);
    if (liq.error) { avisar("error", mensajeDeError(liq.error)); return; }
    // Si esto falla —por ejemplo, la 0565 todavía sin pegar— la liquidación se
    // ve igual que siempre, pero se dice que no se comprobó: «no sé» no es «no
    // hay nada anterior», y quien paga solo esta liquidación lo creería.
    setDetalle({
      ...(liq.data as Detalle),
      periodos_anteriores: ant.error ? null : normalizarPeriodosAnteriores(ant.data),
    });
    setDiferencias((dif.data as Diferencia[]) ?? []);
    // Antes solo se miraba `liq.error`: si `fn_liquidacion_diferencias`
    // fallaba, `diferencias` quedaba en `[]` y el bloque rojo de abajo
    // simplemente no se dibujaba — indistinguible de «no hay descuadre».
    // Quien está por apretar «Marcar como pagada» necesita saber que esto no
    // se comprobó, no ver un desglose que parece cuadrado por accidente.
    setDiferenciasError(dif.error ? mensajeDeError(dif.error) : null);
    // «Sin filas» y «falló» no son lo mismo: lo primero es «nada que registrar»,
    // lo segundo es «no sé» y no dibuja nada nuevo (ver queDibujarDeLaConstancia).
    setConstancia(con.error ? null : (((con.data as unknown as EstadoRegistroDiferencia[] | null) ?? [])[0] ?? null));
    setConstanciaError(con.error ? mensajeDeError(con.error) : null);
    // Sin bloquear la pantalla si esto falla: los papeles de salida son un
    // extra sobre la liquidación, no una condición para verla. Si falla, los
    // dos botones nuevos simplemente no aparecen (quedan detrás de `papelesCese`).
    if (papeles.error) { setPapelesCese(null); return; }
    const crudo = papeles.data as unknown as PapelesCese;
    // El nombre del DNI no viaja en `fn_papeles_cese` y esa función no se
    // reescribe por esto: se lee de la ficha, como ya hacen Contratos y el memo.
    // Sin ficha o sin nombre cargado el papel cae al corto, y la vista previa lo
    // dice (`sinNombreDni`) en vez de imprimirlo en silencio.
    const { data: dp } = await supabase
      .from("datos_personales").select("nombre_dni").eq("persona_id", personaId).maybeSingle();
    const nombreDni = (dp?.nombre_dni as string | null | undefined) ?? null;
    setPapelesCese({
      ...crudo,
      nombre_completo: nombreOficial(nombreDni, crudo.nombre_completo),
      sinNombreDni: !usaNombreDelDni(nombreDni),
    });
  }

  async function abrir(personaId: string) {
    if (abierta === personaId) {
      setAbierta(null); setDetalle(null); setDiferencias([]); setDiferenciasError(null); setConstancia(null); setConstanciaError(null); setPapelesCese(null);
      return;
    }
    setAbierta(personaId); setDetalle(null); setDiferencias([]); setDiferenciasError(null); setConstancia(null); setConstanciaError(null); setPapelesCese(null);
    setNota(""); setApreciacion(""); setModalAbierto(null);
    await cargarDetalle(personaId);
  }

  // Deep link desde la Bandeja (?persona=<id>): abre directo la fila de esa
  // persona, en la tab que le corresponde según su estado actual. Se dispara
  // una sola vez, cuando la lista ya cargó — antes de eso no hay en qué tab
  // buscarla.
  useEffect(() => {
    void (async () => {
      const personaId = searchParams.get("persona");
      if (!personaId || cargando || pendientes.length === 0) return;
      const fila = pendientes.find((p) => p.persona_id === personaId);
      if (!fila) return;
      setTab(fila.pagada ? "pagadas" : fila.vencido ? "vencidas" : "pendientes");
      await abrir(personaId);
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cargando, pendientes]);

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
  function abrirPagar(personaId: string, nombre: string, total: number, yaPagada: boolean, fechaCese: string, venceEl: string) {
    setPagoAccion({ personaId, nombre, total, yaPagada, fechaCese, venceEl });
    // Nace en HOY, editable: la fecha real de pago casi siempre ES hoy, y
    // quien registra un pago de otro día la corrige en un clic — nunca
    // arranca vacía (regla de la casa sobre fechas que bloquean el envío).
    setFechaPago(hoyLima());
  }

  async function confirmarPago() {
    if (!pagoAccion) return;
    const { personaId } = pagoAccion;
    setOcupado(true);
    const { data, error } = await supabase.rpc("fn_liquidacion_pagar", {
      p_persona_id: personaId,
      p_nota: nota.trim() || null,
      p_fecha_pago: fechaPago,
    });
    setOcupado(false);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    setPagoAccion(null);
    await cargar();
    setAbierta(personaId); setDetalle(null); setDiferencias([]); setDiferenciasError(null); setConstancia(null); setConstanciaError(null);
    await cargarDetalle(personaId);
    const v = (data as { version?: number } | null)?.version;
    avisar("ok",
      `Liquidación congelada${v && v > 1 ? ` (versión ${v})` : ""}, pagada el ${fechaLarga(fechaPago)}. La cifra ya no cambia sola: si un recálculo posterior difiere de verdad, se avisa.`);
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
  // Decisión IV (fila de solo lectura): esta acción ya no vive en la fila de
  // la tabla — se movió al pie del desglose, para que la tabla de Pagadas no
  // invite a tocar algo ya cerrado con un clic de más.
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
    setAbierta(personaId); setDetalle(null); setDiferencias([]); setDiferenciasError(null); setConstancia(null); setConstanciaError(null);
    await cargarDetalle(personaId);
    avisar("ok", `Liquidación de ${nombre} anulada con constancia. Vuelve a marcarla cuando el número esté bien.`);
  }

  // ── Qué pasó con una diferencia real (0542) ───────────────────────────────
  // La decisión es de una persona: el sistema nombra la diferencia y calcula su
  // sentido, no la resuelve. Aquí solo se junta lo que la pantalla vio —versión,
  // huella, cabeza de la cadena— y se manda tal cual: el servidor lo recalcula y
  // lo rechaza si ya no es lo que da el cálculo.
  function abrirRegistro(modo: "registrar" | "corregir" | "retirar") {
    if (!abierta || !constancia) return;
    const previa = constancia.vigente;
    setRegistroAccion({
      personaId: abierta, modo,
      nombre: pendientes.find((p) => p.persona_id === abierta)?.persona ?? "",
    });
    // Sin opción por defecto al registrar: quien aprieta tiene que elegir. Al
    // corregir se parte de lo que había, pero el motivo se vuelve a escribir.
    setRegistroDecision(modo === "retirar" ? "retirada" : modo === "corregir" && previa ? previa.decision : "");
    setRegistroApoyo(modo === "corregir" && previa?.apoyo ? previa.apoyo : "");
    setRegistroMotivo("");
  }

  async function ejecutarRegistro() {
    if (!registroAccion || !constancia?.huella || !registroDecision) return;
    const { personaId, nombre, modo } = registroAccion;
    if (!motivoDeConstanciaValido(registroMotivo)) {
      avisar("error", "Cuéntalo en al menos 10 caracteres: dentro de un año ese texto es lo único que explica por qué se cerró el aviso.");
      return;
    }
    if (registroDecision === "pagado_es_correcto" && !registroApoyo) {
      avisar("error", "Elige en qué te apoyas para decir que lo pagado era lo correcto.");
      return;
    }
    setOcupado(true);
    const { error } = await supabase.rpc("fn_liquidacion_constatar", {
      p_persona_id: personaId,
      p_version: constancia.version,
      p_huella: constancia.huella,
      p_decision: registroDecision,
      p_apoyo: registroDecision === "pagado_es_correcto" ? registroApoyo : null,
      p_motivo: registroMotivo.trim(),
      p_reemplaza_id: constancia.cabeza_id,
    });
    setOcupado(false);
    if (error) {
      const mensaje = mensajeDeError(error);
      avisar("error", mensaje);
      // Si lo que se vio ya no es lo que hay (el cálculo cambió, hay una versión
      // nueva, o alguien se adelantó) el modal ya no sirve: se cierra y se vuelve
      // a leer, para ver las cifras de ahora.
      if (/cambió mientras mirabas|Otra persona ya registró|versión nueva|Ya no hay una diferencia/.test(mensaje)) {
        setRegistroAccion(null);
        await cargarDetalle(personaId);
      }
      return;
    }
    setRegistroAccion(null);
    await cargarDetalle(personaId);
    avisar("ok", modo === "retirar"
      ? `Registro de ${nombre} retirado: la diferencia vuelve a estar abierta.`
      : `Quedó registrado qué pasó con la diferencia de ${nombre}.`);
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

  // ── Grupos, filtros y resumen (Decisión I y XII) ───────────────────────────
  //
  // «Sin nada que cobrar» (total = 0, sin pagar) queda FUERA de Pendientes y
  // Vencidas: no compite visualmente con quien sí tiene dinero real en juego,
  // pero no desaparece — el plazo de 48h corre igual para esas personas.
  const enPlazo = pendientes.filter((p) => !p.pagada && !p.vencido && p.total > 0);
  const vencidas = pendientes.filter((p) => !p.pagada && p.vencido && p.total > 0);
  const pagadas  = pendientes.filter((p) => p.pagada);
  const sinMonto = pendientes.filter((p) => !p.pagada && p.total === 0);
  const avisoUrgente = avisos.filter((a) => a.ya_devenga);

  const coincideBusqueda = (p: Pendiente) =>
    busqueda.trim() === "" || p.persona.toLowerCase().includes(busqueda.trim().toLowerCase());
  const coincideSede = (p: Pendiente) => filtroSede === "" || p.sede === filtroSede;

  // Sin useMemo a propósito: son unas 30 personas en todo CAYLA y ~20 ceses al
  // año — filtrar en cada render no mide nada, y complicar esto con
  // dependencias de un helper redefinido cada vez no compra nada a cambio.
  const filaFiltrada = (lista: Pendiente[]) =>
    lista.filter((p) => coincideBusqueda(p) && coincideSede(p));

  const visibleEnPlazo = filaFiltrada(enPlazo);
  const visibleVencidas = filaFiltrada(vencidas);
  const visiblePagadas = filaFiltrada(pagadas);

  const hayFiltrosActivos = busqueda.trim() !== "" || filtroSede !== "";
  function limpiarFiltros() {
    setBusqueda(""); setFiltroSede("");
  }

  function exportarCsv() {
    const filas = tab === "pendientes" ? visibleEnPlazo : tab === "vencidas" ? visibleVencidas : visiblePagadas;
    const columnas = tab === "pagadas"
      ? ["Persona", "Sede", "Cesó", "Vence el", "Total", "Pagada", "Cálculo cambió"]
      : ["Persona", "Sede", "Cesó", "Vence el", "Días", "Total"];
    const contenido = generarCsv(
      filas.map((p) => (
        tab === "pagadas"
          ? {
              Persona: p.persona, Sede: p.sede, "Cesó": p.fecha_cese, "Vence el": p.vence_el,
              Total: p.total, Pagada: "sí", "Cálculo cambió": p.descuadra_real ? "sí" : "no",
            }
          : {
              Persona: p.persona, Sede: p.sede, "Cesó": p.fecha_cese, "Vence el": p.vence_el,
              "Días": p.dias_restantes, Total: p.total,
            }
      )),
      columnas,
    );
    descargarCsv(`liquidaciones-${tab}-${hoyLima()}.csv`, contenido);
  }

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

  const listaActiva = tab === "pendientes" ? visibleEnPlazo : tab === "vencidas" ? visibleVencidas : visiblePagadas;
  const registro: RegistroDiferencia = { estado: constancia, error: constanciaError, abrir: abrirRegistro };

  return (
    <div className="flex flex-1 flex-col">

      <main className="flex-1 p-6 print:p-0">
        <div className="print:hidden">
          <CabeceraPagina
            sobretitulo={sobretituloDeHoy("Pago")}
            titulo="Liquidaciones"
            descripcion="Controla pagos de cese, plazos y diferencias posteriores."
            ayuda={
              <AyudaPantalla
                titulo="Cómo se calcula el plazo"
                intro="La ley da 48 horas desde el cese para pagar la liquidación."
                secciones={[
                  { titulo: "El plazo", texto: "Es el último día trabajado más dos días de calendario, sin excepción por fin de semana o feriado (art. 4 del D.S. 001-97-TR)." },
                  { titulo: "Al marcar como pagada", texto: "La cifra se congela y no se mueve. Si después el cálculo de hoy da otra cosa, lo verás al abrir la liquidación pagada." },
                  { titulo: "Vencidas", texto: "Pasado el plazo sin pagar, la liquidación pasa a «Vencidas». Si ya se pagó por fuera, falta anotarlo para que deje de figurar." },
                ]}
              />
            }
            accion={
              <Boton variante="secundario" tamano="sm" onClick={exportarCsv} disabled={listaActiva.length === 0}>
                Exportar CSV
              </Boton>
            }
          />

          {cargaError && (
            <BannerAviso role="alert" variante="alerta" enLinea className="mb-4">
              No se pudo leer la lista: {cargaError}
            </BannerAviso>
          )}

          {/* ── El aviso del vínculo «prueba» (en pantalla: preselección) ────────────────────────────────
              Va acá y no en Equipo porque lo que está en juego son beneficios, y
              esta es la pantalla que habla de beneficios. Solo aparece cuando ya
              pasó el mes: antes no cuesta nada y avisar sería ruido. */}
          {avisoUrgente.map((a) => (
            <BannerAviso key={a.persona_id} variante="alerta" enLinea titulo={`${a.persona} lleva ${a.dias} días como «preselección».`} className="mb-4">
              {a.aviso}
            </BannerAviso>
          ))}

          {/* ── Para atender (Decisión I): lo vencido va primero; tocar una pastilla abre su pestaña ── */}
          <ParaAtender
            items={[
              {
                clave: "vencidas",
                texto: `${vencidas.length} ${vencidas.length === 1 ? "vencida" : "vencidas"}${vencidas.length > 0 ? ` · ${formatSoles(vencidas.reduce((a, p) => a + p.total, 0))}` : ""}`,
                n: vencidas.length,
                tono: "rojo",
              },
              { clave: "pendientes", texto: `${enPlazo.length} en plazo`, n: enPlazo.length, tono: "pizarra" },
            ]}
            activa={tab === "vencidas" ? "vencidas" : null}
            alTocar={(clave) => setTab(clave === "vencidas" ? "vencidas" : "pendientes")}
          />

          {/* ── Búsqueda y filtros, en una fila y sin rótulos encima ───────── */}
          <div className="mb-4 flex flex-wrap items-center gap-2">
            <div className="min-w-48 flex-1 sm:max-w-xs">
              <Campo tamano="sm" aria-label="Buscar persona" value={busqueda} onChange={(e) => setBusqueda(e.target.value)} placeholder="Buscar por nombre o apellido" />
            </div>
            <div className="w-full sm:w-52">
              <CampoSelect tamano="sm" aria-label="Sede" value={filtroSede} onChange={(e) => setFiltroSede(e.target.value)}>
                <option value="">Todas las sedes</option>
                {sedes.map((sd) => <option key={sd.id} value={sd.codigo}>{sd.codigo} — {sd.nombre}</option>)}
              </CampoSelect>
            </div>
            {hayFiltrosActivos && (
              <Boton variante="enlace" className="text-sm text-taupe" onClick={limpiarFiltros}>
                Limpiar filtros
              </Boton>
            )}
          </div>

          {/* ── Pestañas por estado (Decisión I y II: vencidas solo en su pestaña) ── */}
          <Pestanas
            etiqueta="Estado de las liquidaciones"
            pestanas={[
              { clave: "pendientes", texto: `Pendientes · ${enPlazo.length}` },
              { clave: "vencidas", texto: "Vencidas", aviso: vencidas.length },
              { clave: "pagadas", texto: `Pagadas · ${pagadas.length}` },
            ]}
            activa={tab}
            alElegir={(t) => setTab(t as typeof tab)}
          />

          {tab === "pendientes" && (
            <SeccionTabla
              vacio={
                pendientes.length === 0
                  ? { titulo: "Todo al día", texto: "No hay liquidaciones pendientes dentro del plazo." }
                  : hayFiltrosActivos
                    ? { titulo: "Nada con estos filtros", texto: "Prueba a limpiarlos." }
                    : { titulo: "Todo al día", texto: "No hay liquidaciones pendientes dentro del plazo." }
              }
              filas={visibleEnPlazo}
              modo="pendiente"
              abierta={abierta} onAbrir={abrir}
              detalle={detalle} diferencias={diferencias} diferenciasError={diferenciasError}
              nota={nota} setNota={setNota} ocupado={ocupado}
              onPagar={abrirPagar} onAnular={abrirAnular} miFirma={miFirma} registro={registro}
              papelesCese={papelesCese} apreciacion={apreciacion} setApreciacion={setApreciacion}
              onImprimir={imprimir}
            />
          )}

          {tab === "vencidas" && (
            <SeccionTabla
              vacio={{ titulo: "Sin vencidas", texto: "Nadie pasó los 48 horas sin que se le pagara." }}
              filas={visibleVencidas}
              modo="vencida"
              abierta={abierta} onAbrir={abrir}
              detalle={detalle} diferencias={diferencias} diferenciasError={diferenciasError}
              nota={nota} setNota={setNota} ocupado={ocupado}
              onPagar={abrirPagar} onAnular={abrirAnular} miFirma={miFirma} registro={registro}
              papelesCese={papelesCese} apreciacion={apreciacion} setApreciacion={setApreciacion}
              onImprimir={imprimir}
            />
          )}

          {tab === "pagadas" && (
            <SeccionTabla
              vacio={{ titulo: "Sin pagadas todavía", texto: "Acá va quedando el historial." }}
              filas={visiblePagadas}
              modo="pagada"
              abierta={abierta} onAbrir={abrir}
              detalle={detalle} diferencias={diferencias} diferenciasError={diferenciasError}
              nota={nota} setNota={setNota} ocupado={ocupado}
              onPagar={abrirPagar} onAnular={abrirAnular} miFirma={miFirma} registro={registro}
              papelesCese={papelesCese} apreciacion={apreciacion} setApreciacion={setApreciacion}
              onImprimir={imprimir}
            />
          )}

          {/* ── Sin nada que cobrar (Decisión XII) ───────────────────────────
              Fuera de lo urgente a propósito: el plazo de 48h corre igual para
              ellas, pero un total en S/0.00 no debe competir visualmente con
              quien sí tiene dinero real en juego. Colapsado por defecto. */}
          {tab === "pendientes" && sinMonto.length > 0 && (
            <details className="mt-4 rounded-control border border-sand bg-sand/10 text-sm">
              <summary className="cursor-pointer px-4 py-2 text-taupe">
                {sinMonto.length} sin nada que cobrar — el plazo de 48h corre igual
              </summary>
              <Tabla className="rounded-t-none border-t">
                <TablaEncabezado>
                  <Th>Persona</Th><Th>Sede</Th><Th>Cesó</Th><Th className="text-right">Acción</Th>
                </TablaEncabezado>
                <tbody>
                  {sinMonto.map((p) => (
                    <Fila key={p.persona_id}>
                      <td className="px-4 py-2">{p.persona}</td>
                      <td className="px-4 py-2 text-taupe">{p.sede}</td>
                      <td className="px-4 py-2 text-taupe">{fechaCorta(p.fecha_cese)}</td>
                      <td className="px-4 py-2 text-right">
                        <button
                          className="text-rojo underline"
                          onClick={() => abrirPagar(p.persona_id, p.persona, 0, false, p.fecha_cese, p.vence_el)}
                        >
                          Marcar como pagada
                        </button>
                      </td>
                    </Fila>
                  ))}
                </tbody>
              </Tabla>
            </details>
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
              {(modalAbierto === "certificado" || modalAbierto === "constancia") && papelesCese?.sinNombreDni && (
                <BannerAviso
                  variante="advertencia"
                  titulo="Falta el nombre completo del DNI"
                  className="m-4 mb-0 p-3 print:hidden"
                >
                  <p>
                    Este papel saldrá con el nombre corto con el que se ve en el terminal. Un banco compara el
                    nombre contra el DNI al soltar la CTS: carga el nombre completo en Datos personales antes
                    de imprimirlo — una vez entregado, no se puede corregir.
                  </p>
                </BannerAviso>
              )}
              <div className="hoja overflow-y-auto p-8 text-sm leading-relaxed print:overflow-visible print:p-0">
                {modalAbierto === "liquidacion" && detalle && <Hoja d={detalle} miFirma={miFirma} />}
                {modalAbierto === "certificado" && papelesCese && (
                  <HojaCertificado
                    p={papelesCese} apreciacion={apreciacion} firmante={firmanteEmpresa}
                    firma={puedeEstamparFirmaDeEmpresa(rol) ? firmaEmpresa : null}
                  />
                )}
                {modalAbierto === "constancia" && papelesCese && (
                  <HojaConstancia
                    p={papelesCese} detalle={detalle} firmante={firmanteEmpresa}
                    firma={puedeEstamparFirmaDeEmpresa(rol) ? firmaEmpresa : null}
                  />
                )}
              </div>
            </div>
          </div>
        )}
      </main>

      {/* Modal: congelar (o volver a congelar) la liquidación. */}
      <Modal
        abierto={pagoAccion !== null}
        onCerrar={() => setPagoAccion(null)}
        bloqueado={ocupado}
        titulo={pagoAccion?.yaPagada ? "Volver a marcar como pagada" : "Congelar la liquidación"}
        ancho="sm"
      >
        {pagoAccion && (
          <>
            <p className="mb-3 text-sm text-taupe">
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
                  Cesó el {fechaLarga(pagoAccion.fechaCese)} · plazo legal hasta el {fechaLarga(pagoAccion.venceEl)}.
                  <br /><br />
                  El monto quedará congelado como referencia histórica: si después el cálculo cambia,
                  el sistema lo dice pero NO mueve la cifra. Si te equivocas, «Anular» deja constancia
                  y la saca de la cuenta, sin borrar nada.
                </>
              )}
            </p>
            <Campo
              etiqueta="Fecha real de pago"
              type="date"
              value={fechaPago}
              max={hoyLima()}
              onChange={(e) => setFechaPago(e.target.value)}
              className="mb-4 w-44"
            />
            <div className="flex justify-end gap-2">
              <Boton onClick={() => setPagoAccion(null)} disabled={ocupado}>Cancelar</Boton>
              <Boton variante="primario" onClick={() => void confirmarPago()} cargando={ocupado}>
                {pagoAccion.yaPagada ? "Volver a marcarla" : "Congelar"}
              </Boton>
            </div>
          </>
        )}
      </Modal>

      {/* Modal: anular una liquidación pagada. */}
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

      {/* Modal: qué pasó con la diferencia real de una liquidación ya pagada (0542). */}
      <Modal
        abierto={registroAccion !== null}
        onCerrar={() => setRegistroAccion(null)}
        bloqueado={ocupado}
        titulo={registroAccion?.modo === "retirar" ? "Retirar el registro" : "Qué pasó con esta diferencia"}
        ancho="md"
      >
        {registroAccion && constancia && (
          <>
            {registroAccion.modo === "retirar" ? (
              <p className="mb-3 text-sm text-taupe">
                Vas a retirar el registro de la diferencia de{" "}
                <strong className="text-tinta">{registroAccion.nombre}</strong>. La diferencia vuelve a quedar
                abierta. El registro anterior no se borra: queda en el historial.
              </p>
            ) : (
              <>
                <p className="mb-2 text-sm text-taupe">
                  El cálculo de hoy no coincide con la liquidación de{" "}
                  <strong className="text-tinta">{registroAccion.nombre}</strong>:
                </p>
                <LineasDeDiferencia filas={constancia.filas} className="mb-3" />
                {constancia.sentido === "a_favor_persona" && (
                  <p className="mb-3 text-xs text-taupe">
                    Hoy se le daría MÁS que lo que se le pagó. Si esa diferencia se le debe, no la cierres:
                    págala y usa «Volver a marcarla como pagada».
                  </p>
                )}
                {constancia.sentido === "a_favor_cayla" && (
                  <p className="mb-3 text-xs text-taupe">
                    Se le pagó DE MÁS. Según el numeral 29.6 del Reglamento, eso se comunica por escrito con el
                    detalle del cálculo y se acuerda la devolución; no se descuenta de golpe sin su conformidad escrita.
                  </p>
                )}
                {(constancia.sentido === "a_favor_persona" || constancia.sentido === "a_favor_cayla") && (
                  <fieldset className="mb-3 flex flex-col gap-2">
                    <legend className="mb-1 text-sm text-taupe">¿Qué pasó?</legend>
                    {decisionesPara(constancia.sentido).map((d) => (
                      <label key={d} className="flex items-start gap-2 text-sm">
                        <input
                          type="radio"
                          name="registro-decision"
                          className="mt-1 size-4 accent-tinta"
                          checked={registroDecision === d}
                          onChange={() => setRegistroDecision(d)}
                        />
                        {ETIQUETA_DECISION[d]}
                      </label>
                    ))}
                  </fieldset>
                )}
                {registroDecision === "pagado_es_correcto" && (
                  <div className="mb-3">
                    <CampoSelect
                      etiqueta="¿En qué te apoyas?"
                      value={registroApoyo}
                      onChange={(e) => setRegistroApoyo(e.target.value as ApoyoConstancia | "")}
                    >
                      <option value="">Elige…</option>
                      {APOYOS_CONSTANCIA.map((a) => <option key={a} value={a}>{ETIQUETA_APOYO[a]}</option>)}
                    </CampoSelect>
                  </div>
                )}
              </>
            )}
            <label className="mb-4 flex flex-col gap-1 text-sm">
              {registroAccion.modo === "retirar" ? "¿Por qué lo retiras?" : "Cuéntalo"} (mínimo 10 caracteres, obligatorio)
              <AreaTexto
                value={registroMotivo}
                onChange={(e) => setRegistroMotivo(e.target.value)}
                rows={3}
                autoFocus
                placeholder={registroAccion.modo === "retirar"
                  ? "ej. se registró por error: falta confirmarlo con el laboralista."
                  : "ej. la regla de vacaciones truncas cambió después del pago; lo confirmó el contador el 20/10."}
              />
            </label>
            <div className="flex justify-end gap-2">
              <Boton onClick={() => setRegistroAccion(null)} disabled={ocupado}>Cancelar</Boton>
              <Boton
                variante="primario"
                onClick={() => void ejecutarRegistro()}
                cargando={ocupado}
                disabled={
                  !registroDecision || !motivoDeConstanciaValido(registroMotivo)
                  || (registroDecision === "pagado_es_correcto" && !registroApoyo)
                }
              >
                {registroAccion.modo === "retirar" ? "Retirar" : "Guardar"}
              </Boton>
            </div>
          </>
        )}
      </Modal>
    </div>
  );
}

// Lo que baja de la página hasta el desglose para el registro de una diferencia.
interface RegistroDiferencia {
  estado: EstadoRegistroDiferencia | null;
  error: string | null;
  abrir: (modo: "registrar" | "corregir" | "retirar") => void;
}

// Las filas de una diferencia, una por línea y sin tabla: «se pagó X, hoy daría Y».
function LineasDeDiferencia({ filas, className }: { filas: FilaDiferenciaConstancia[]; className?: string }) {
  return (
    <ul className={className}>
      {filas.map((x) => (
        <li key={x.concepto} className="text-sm tabular-nums">
          <span className="text-taupe">{x.concepto}:</span> se pagó {formatSoles(x.pagado)}, hoy daría{" "}
          {formatSoles(x.ahora)} ({x.diferencia > 0 ? "+" : ""}{formatSoles(x.diferencia)})
        </li>
      ))}
    </ul>
  );
}

function SeccionTabla({
  vacio, filas, modo, abierta, onAbrir, detalle, diferencias, diferenciasError, nota, setNota, ocupado,
  onPagar, onAnular, miFirma, registro, papelesCese, apreciacion, setApreciacion, onImprimir,
}: {
  vacio: { titulo: string; texto: string };
  filas: Pendiente[];
  modo: "pendiente" | "vencida" | "pagada";
  abierta: string | null; onAbrir: (id: string) => void;
  detalle: Detalle | null; diferencias: Diferencia[]; diferenciasError: string | null;
  nota: string; setNota: (v: string) => void;
  ocupado: boolean;
  onPagar: (id: string, nombre: string, total: number, yaPagada: boolean, fechaCese: string, venceEl: string) => void;
  onAnular: (id: string, nombre: string) => void;
  miFirma: string | null;
  registro: RegistroDiferencia;
  papelesCese: PapelesCese | null; apreciacion: string; setApreciacion: (v: string) => void;
  onImprimir: (doc: "liquidacion" | "certificado" | "constancia") => void;
}) {
  if (filas.length === 0) {
    return (
      <div className="rounded-superficie border border-dashed border-sand px-4 py-8 text-center text-sm">
        <p className="mb-0.5 font-medium text-verde">✓ {vacio.titulo}</p>
        <p className="text-taupe">{vacio.texto}</p>
      </div>
    );
  }

  return (
    <Tabla>
      <TablaEncabezado>
        <Th>Persona</Th>
        <Th>Sede</Th>
        <Th>Cesó</Th>
        <Th>{modo === "pagada" ? "Plazo" : "Vence"}</Th>
        <Th className="text-right">Monto</Th>
        <Th className="text-right">Acción</Th>
      </TablaEncabezado>
      <tbody>
        {filas.map((f) => (
          <Fragment key={f.persona_id}>
            <Fila>
              <td className="px-4 py-2.5">
                <strong>{f.persona}</strong>
              </td>
              <td className="px-4 py-2.5 text-taupe">{f.sede}</td>
              <td className="px-4 py-2.5 text-taupe">{fechaCorta(f.fecha_cese)}</td>
              <td className="px-4 py-2.5">
                {modo === "pagada" ? (
                  <span className="text-xs text-taupe">plazo vencía el {fechaCorta(f.vence_el)}</span>
                ) : modo === "vencida" ? (
                  <span className="text-xs font-medium text-rojo">
                    {-f.dias_restantes} día{-f.dias_restantes === 1 ? "" : "s"} de atraso
                  </span>
                ) : (
                  <span className="text-xs text-taupe">
                    {f.dias_restantes === 0 ? "vence hoy" : `quedan ${f.dias_restantes} día${f.dias_restantes === 1 ? "" : "s"}`}
                    {" · "}{fechaCorta(f.vence_el)}
                  </span>
                )}
              </td>
              <td className="px-4 py-2.5 text-right font-medium tabular-nums">{formatSoles(f.total)}</td>
              <td className="px-4 py-2.5 text-right">
                <button className="text-sm font-medium text-rojo underline" onClick={() => onAbrir(f.persona_id)}>
                  {abierta === f.persona_id ? "Cerrar" : modo === "pagada" ? "Revisar" : "Revisar →"}
                </button>
              </td>
            </Fila>
            {abierta === f.persona_id && detalle && (
              <tr key={`${f.persona_id}-desglose`}>
                <td colSpan={6} className="bg-crema/50 px-4 py-3">
                  <Desglose
                    d={detalle} diferencias={diferencias} diferenciasError={diferenciasError} pagada={f.pagada}
                    nota={nota} setNota={setNota} ocupado={ocupado} miFirma={miFirma} registro={registro}
                    // `detalle.total` — no `f.total` — porque es el número que la
                    // persona acaba de leer en el Desglose de abajo, recién
                    // calculado. `f.total` es el que trajo la lista al montar la
                    // pantalla, y para "volver a marcar pagada" es literalmente el
                    // monto histórico congelado.
                    onPagar={() => onPagar(f.persona_id, f.persona, n(detalle.total), f.pagada, f.fecha_cese, f.vence_el)}
                    onAnular={() => onAnular(f.persona_id, f.persona)}
                    papelesCese={papelesCese} apreciacion={apreciacion} setApreciacion={setApreciacion}
                    onImprimir={onImprimir}
                  />
                </td>
              </tr>
            )}
          </Fragment>
        ))}
      </tbody>
    </Tabla>
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
  d, diferencias, diferenciasError, pagada, nota, setNota, ocupado, onPagar, onAnular, miFirma, registro,
  papelesCese, apreciacion, setApreciacion, onImprimir,
}: {
  d: Detalle; diferencias: Diferencia[]; diferenciasError: string | null; pagada: boolean;
  nota: string; setNota: (v: string) => void; ocupado: boolean;
  onPagar: () => void; onAnular: () => void;
  miFirma: string | null;
  registro: RegistroDiferencia;
  papelesCese: PapelesCese | null; apreciacion: string; setApreciacion: (v: string) => void;
  onImprimir: (doc: "liquidacion" | "certificado" | "constancia") => void;
}) {
  const esperadas = diferencias.filter((x) => x.origen === "esperada_por_cierre");
  const reales = diferencias.filter((x) => x.origen === "real");
  const que = queDibujarDeLaConstancia({ error: registro.error, fila: registro.estado }, pagada);
  const vigente = registro.estado?.vigente ?? null;
  const anterior = registro.estado?.anterior ?? null;

  return (
    <div className="rounded-control border border-sand bg-papel p-3">
      {d.aviso_periodo && (
        <p className="mb-2 rounded border border-sand bg-hueso p-2 text-xs text-taupe">
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

      {/* Lo que se le debe de periodos ANTERIORES al del cese (0565). Va aparte
          del Total de arriba a propósito: ese dinero sale por la planilla de
          cada periodo, y sumarlo a la liquidación lo pagaría dos veces. */}
      {d.periodos_anteriores === null && (
        <BannerAviso variante="advertencia" enLinea className="mt-3">
          No se pudo comprobar si debe algo de periodos anteriores. No des esta liquidación por todo lo que se le debe.
        </BannerAviso>
      )}
      {d.periodos_anteriores && d.periodos_anteriores.length > 0 && (() => {
        const { totalGeneral } = resumenPeriodosAnteriores(d.periodos_anteriores, n(d.total));
        return (
          <BannerAviso variante="informativo" titulo="También se le debe de periodos anteriores" className="mt-3 p-3">
            <p className="mb-2">
              Esto no está en el total de arriba: se paga por la planilla de cada periodo, no por esta liquidación.
            </p>
            <table className="w-full text-sm">
              <tbody>
                {d.periodos_anteriores.map((pa) => (
                  <tr key={pa.periodo_id} className="align-top">
                    <td className="py-1 pr-3">
                      Periodo del {fechaLarga(pa.fecha_ini)} al {fechaLarga(pa.fecha_fin)}
                      <span className="block text-xs text-taupe">{dondeSePaga(pa.estado)}</span>
                    </td>
                    <td className="py-1 text-right tabular-nums">{formatSoles(pa.total)}</td>
                  </tr>
                ))}
                {/* Una liquidación ya pagada no se «debe»: ahí solo queda la lista. */}
                {!pagada && (
                  <>
                    <tr className="border-t border-sand">
                      <td className="py-1 pr-3">Esta liquidación (periodo del cese y beneficios)</td>
                      <td className="py-1 text-right tabular-nums">{formatSoles(n(d.total))}</td>
                    </tr>
                    <tr className="font-medium">
                      <td className="py-1 pr-3">Se le debe en total, entre planilla y liquidación</td>
                      <td className="py-1 text-right tabular-nums">{formatSoles(totalGeneral)}</td>
                    </tr>
                  </>
                )}
              </tbody>
            </table>
          </BannerAviso>
        );
      })()}

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
      ) : (
        <>
          {/* Decisión III — esperada: tono neutro (pizarra), sin alarmar. Es
              el curso normal de casi toda cesada desde que el cierre de mes
              la alcanza. */}
          {esperadas.length > 0 && (
            <BannerAviso variante="informativo" titulo="Esto es normal, no hace falta revisar" className="mt-3 p-3">
              <p>El sueldo del periodo bajó porque Planilla ya lo descontó al cerrar el mes. El resto del
                cálculo sigue igual. No hay nada que decidir acá.</p>
            </BannerAviso>
          )}
          {/* Decisión III — real: alarma roja, con el concepto que de verdad
              cambió. El sistema la nombra; qué hacer con ella —pagarla,
              compensarla o dejar constancia— sigue siendo una decisión
              humana: nunca se ajusta sola (Decisión XI). */}
          {reales.length > 0 && que !== "vigente" && (
            <BannerAviso variante="alerta" titulo="Revisar — esto no lo explica el cierre del mes" className="mt-3 p-3">
              <table className="w-full">
                <tbody>
                  {reales.map((x) => (
                    <tr key={x.concepto}>
                      <td className="py-0.5 pr-2 text-taupe">{x.concepto}</td>
                      <td className="py-0.5 text-right tabular-nums">
                        se pagó {formatSoles(x.pagado)}, hoy daría {formatSoles(x.ahora)}{" "}
                        ({x.diferencia > 0 ? "+" : ""}{formatSoles(x.diferencia)})
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
              <p className="mt-2 text-xs text-taupe">
                Qué hacer con la diferencia es una decisión tuya: el sistema la nombra, no la resuelve.
                Si se le debe, págala con «Volver a marcarla como pagada»; si no, registra qué pasó.
              </p>
            </BannerAviso>
          )}
          {/* Ya se registró qué pasó (0542): el rojo se calma y queda quién, cuándo y por qué. */}
          {que === "vigente" && vigente && (
            <BannerAviso variante="informativo" titulo="Ya se registró qué pasó con esta diferencia" className="mt-3 p-3">
              <p>
                {ETIQUETA_DECISION[vigente.decision]}.
                {vigente.apoyo ? ` Apoyo: ${ETIQUETA_APOYO[vigente.apoyo].toLowerCase()}.` : ""} Lo registró{" "}
                {vigente.por} el {fechaLarga(fechaLima(vigente.cuando))}.
              </p>
              <p className="mt-1 text-xs text-taupe">«{vigente.motivo}»</p>
              <LineasDeDiferencia filas={vigente.diferencias} className="mt-2" />
              <p className="mt-2 text-xs text-taupe">
                Si el cálculo cambia otra vez, el aviso vuelve solo.
              </p>
              <div className="mt-2 flex flex-wrap gap-2">
                <Boton variante="secundario" tamano="sm" onClick={() => registro.abrir("corregir")} disabled={ocupado}>
                  Corregir
                </Boton>
                <Boton variante="secundario" tamano="sm" onClick={() => registro.abrir("retirar")} disabled={ocupado}>
                  Retirar el registro
                </Boton>
              </div>
            </BannerAviso>
          )}
          {que === "registrar" && (
            <div className="mt-3">
              {anterior && (
                <p className="mb-2 text-xs text-taupe">
                  El {fechaLarga(fechaLima(anterior.cuando))} se había registrado «{ETIQUETA_DECISION[anterior.decision]}»
                  con otras cifras. El cálculo cambió desde entonces; las de ahora son las de arriba:
                  <LineasDeDiferencia filas={anterior.diferencias} className="mt-1" />
                </p>
              )}
              <Boton variante="secundario" tamano="sm" onClick={() => registro.abrir("registrar")} disabled={ocupado}>
                Registrar qué pasó con la diferencia
              </Boton>
            </div>
          )}
          {que === "no_se_puede" && registro.estado?.motivo_no && (
            <p className="mt-2 text-xs text-taupe">{registro.estado.motivo_no}</p>
          )}
        </>
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
          naturaleza distinta. */}
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

      {/* Decisión IV: «Anular» vive acá, no en la fila de la tabla — la tabla
          de Pagadas es de solo lectura, y anular es una acción de alta
          confianza que merece el mismo peso que «Marcar como pagada». */}
      {pagada && (
        <div className="mt-3 flex flex-wrap items-center gap-2 border-t border-sand pt-3">
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
// un tercero); la imagen de la firma es la del firmante configurado (`firma`,
// que el llamador lee con `fn_firma_empresa`), sin importar quién abre el papel.
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

// El «recibí» del certificado. El Reglamento (59.6) obliga a entregarlo dentro
// de las 48 horas del cese, y el sistema no guarda que se entregó ni cuándo —el
// documento se arma en vivo, no se archiva—. La única prueba de esa entrega es
// esta firma y esta fecha, escritas a mano por quien lo recibe. Por eso la fecha
// de recepción es un espacio en blanco y no `hoyLima()`: la que importa es el
// día en que el papel llegó a sus manos, no el día en que se imprimió.
//
// `conFirmaEmpresa` alinea la línea de firma con la de CAYLA cuando esta lleva
// imagen de firma arriba (`h-14`); sin imagen, las dos líneas ya quedan a la
// misma altura y no hace falta reservar nada.
function RecibiConforme({ p, conFirmaEmpresa }: { p: PapelesCese; conFirmaEmpresa: boolean }) {
  return (
    <div className={`text-xs ${conFirmaEmpresa ? "pt-14" : ""}`}>
      <div className="w-56 border-t border-tinta pt-1">Recibí conforme</div>
      <div>{p.nombre_completo}</div>
      {p.documento && <div>DNI N.° {p.documento}</div>}
      <div className="mt-2">
        Fecha de recepción: <span className="inline-block w-32 border-b border-tinta align-baseline" />
      </div>
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

      <div className="mt-12 flex items-start justify-between gap-6">
        <RecibiConforme p={p} conFirmaEmpresa={!!firma} />
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

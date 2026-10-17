// ============================================================================
// boletas-pantalla.ts — lo que la pantalla de DO decide para DIBUJAR
// ============================================================================
//
// QUÉ PROMETE
//   Funciones puras que contestan lo que la pantalla de boletas necesita
//   preguntar: qué botones lleva cada persona, cómo se filtra el tablero, si la
//   casilla «avisar» está marcada o bloqueada, cómo se escribe una fecha de
//   Lima. Nada de React ni de Supabase: se prueban con vitest
//   (tests/boletas-pantalla.test.ts).
//
// QUÉ NO DECIDE
//   Las reglas de la boleta en sí (estados, topes, qué cambia entre versiones)
//   viven en `lib/boletas.ts` y aquí solo se usan. La base es la que manda: si
//   esta pantalla ofrece un botón que la base rechaza, el usuario ve el mensaje
//   de la base, que está escrito para leerse.
//
// POR QUÉ LAS ACCIONES SE DECIDEN ACÁ Y NO EN CADA BOTÓN
//   La tabla (computadora) y las tarjetas (celular) dibujan las mismas acciones.
//   Si cada una las decidiera por su cuenta, «qué puede hacer DO con esta
//   boleta» tendría dos respuestas —el defecto de siempre en este repositorio—.
// ============================================================================

import type { Database } from "@cayla-dynamic/database";
import { TZ_LIMA } from "@cayla-dynamic/shared";
import {
  estadoVisible, etiquetaDeHojas, puedeElegirNoAvisar, sePuedeRestablecer,
  type CambiosDeVersion, type EstadoVisible, type TipoBoleta,
} from "@/lib/boletas";
import { sinTildes } from "@/lib/sin-tildes";
import { pesoLegible } from "@/lib/reducir-imagen";
import { MESES_LARGO, fechaCorta } from "@/lib/admin/planilla/formato";
import type { PeriodoInfo } from "@/lib/admin/planilla/tipos";

/** Una fila de `fn_boletas_tablero`: una persona en un periodo. */
export type FilaTablero = Database["public"]["Functions"]["fn_boletas_tablero"]["Returns"][number];

// ── El tablero ──────────────────────────────────────────────────────────────

/** El orden en que se ofrecen los estados en el filtro: primero lo que pide acción. */
export const ESTADOS_DEL_FILTRO: readonly EstadoVisible[] = [
  "falta", "borrador", "publicada", "vista", "firmada", "confirmada", "papel", "anulada", "sin_pago",
];

export type FiltroTablero = {
  estado: EstadoVisible | "todos";
  sede: string | "todas";
  texto: string;
};

export function filtrarTablero(filas: readonly FilaTablero[], f: FiltroTablero): FilaTablero[] {
  const texto = sinTildes(f.texto.trim());
  return filas.filter((x) => {
    if (f.sede !== "todas" && x.sede_codigo !== f.sede) return false;
    if (f.estado !== "todos" && estadoVisible(x) !== f.estado) return false;
    if (texto && !sinTildes(x.nombre).includes(texto)) return false;
    return true;
  });
}

/**
 * Las sedes que aparecen en el tablero, sin repetir. Se leen de los datos y no
 * de una lista escrita a mano: las sedes se gestionan desde una pantalla, y una
 * lista fija dejó de ser cierta el día que abrió Central.
 */
export function sedesDelTablero(filas: readonly FilaTablero[]): string[] {
  return [...new Set(filas.map((f) => f.sede_codigo))].sort((a, b) => a.localeCompare(b, "es"));
}

// ── Qué puede hacer DO con cada persona ─────────────────────────────────────

export type AccionesFila = {
  /** Subir la boleta digital (persona con cuenta, sin boleta o con la anulada). */
  subir: boolean;
  /** Anotar que se entregó impresa (persona SIN cuenta, sin boleta o con la anulada). */
  papel: boolean;
  ver: boolean;
  editar: boolean;
  historial: boolean;
  /** Solo una boleta ya publicada se anula (la persona ya la ve). */
  anular: boolean;
  /** Ver la boleta con su constancia de firma (0532): quien ya la firmó o confirmó. */
  constancia: boolean;
  /** Restablecer una anulación, mientras corren las 48 horas (0532). */
  restablecer: boolean;
  /** Ver lo que se anuló, con su motivo, su historial y su constancia (0532). */
  anulacion: boolean;
};

const NADA: AccionesFila = {
  subir: false, papel: false, ver: false, editar: false, historial: false, anular: false,
  constancia: false, restablecer: false, anulacion: false,
};

export function accionesDeFila(f: FilaTablero, ahora: Date = new Date()): AccionesFila {
  const e = estadoVisible(f);
  switch (e) {
    case "sin_pago":
      return NADA;
    case "falta":
    case "anulada":
      return {
        ...NADA,
        subir: f.tiene_cuenta,
        papel: !f.tiene_cuenta,
        historial: f.boleta_id !== null,
        // Lo anulado se puede mirar (con su motivo) y, dentro de las 48 horas,
        // restablecer: es lo único que `fn_boleta_restablecer` acepta.
        restablecer: e === "anulada" && sePuedeRestablecer(f.restablecible_hasta, ahora),
        anulacion: e === "anulada" && f.boleta_id !== null,
      };
    case "papel":
      // Se puede ANULAR: si DO marca «papel» por error no debe quedar sin salida.
      // La base ya lo permite, y su propio mensaje lo pide («Anúlala antes de
      // subir una digital», 0482). Solo así una entrega anotada de más se corrige.
      return { ...NADA, historial: f.boleta_id !== null, anular: f.boleta_id !== null };
    case "borrador":
    case "publicada":
    case "vista":
    case "firmada":
    case "confirmada":
      return {
        ...NADA,
        ver: f.version_id !== null,
        editar: f.version_id !== null,
        historial: f.boleta_id !== null,
        anular: f.estado === "publicada",
        constancia: (e === "firmada" || e === "confirmada") && f.version_id !== null,
      };
  }
}

/** Los borradores del periodo: lo que «Publicar» va a soltar. */
export function borradoresDelTablero(filas: readonly FilaTablero[]): FilaTablero[] {
  return filas.filter((f) => estadoVisible(f) === "borrador" && f.version_id !== null);
}

/** «3 fotos · 1.2 MB», «1 PDF · 240 KB». Vacío si la persona no tiene documento. */
export function resumenDelDocumento(f: Pick<FilaTablero, "tipo" | "n_partes" | "bytes">): string | null {
  if (!f.tipo || f.n_partes === 0) return null;
  return `${etiquetaDeHojas(f.tipo as TipoBoleta, f.n_partes)} · ${pesoLegible(f.bytes)}`;
}

// ── La casilla «Avisar y pedir confirmar de nuevo» ──────────────────────────

export type CasillaAvisar = {
  /** Solo se dibuja al editar una boleta ya publicada. */
  visible: boolean;
  marcada: boolean;
  bloqueada: boolean;
  /** La explicación que va junto a la casilla. */
  explicacion: string;
};

/**
 * Espeja `fn_boleta_guardar_version` (0482): con contenido nuevo se avisa
 * SIEMPRE; solo si únicamente se reordenó DO puede elegir no avisar; sin
 * cambios no hay nada que elegir (y la base rechaza guardar).
 */
export function casillaAvisar(o: { publicada: boolean; cambios: CambiosDeVersion; quiereAvisar: boolean }): CasillaAvisar {
  if (!o.publicada) return { visible: false, marcada: true, bloqueada: true, explicacion: "" };
  const puedeElegir = puedeElegirNoAvisar({ publicada: o.publicada, cambios: o.cambios });
  if (o.cambios.contenido) {
    return {
      visible: true, marcada: true, bloqueada: true,
      explicacion: "Cambió el contenido de la boleta (agregaste o quitaste una hoja): a la persona se le avisa siempre.",
    };
  }
  if (puedeElegir) {
    return {
      visible: true, marcada: o.quiereAvisar, bloqueada: false,
      explicacion: "Desmárcala solo si únicamente cambiaste el orden de las hojas: su confirmación anterior se conserva.",
    };
  }
  return {
    visible: true, marcada: o.quiereAvisar, bloqueada: true,
    explicacion: "Haz un cambio en las hojas para poder elegir.",
  };
}

// ── Periodos y fechas ───────────────────────────────────────────────────────

/** «Agosto 2026». El mes y el año de etiqueta los pone `fn_periodos`. */
export function nombreDePeriodo(p: Pick<PeriodoInfo, "mes_etiqueta" | "anio_etiqueta">): string {
  const mes = MESES_LARGO[p.mes_etiqueta - 1] ?? "";
  return `${mes.charAt(0).toUpperCase()}${mes.slice(1)} ${p.anio_etiqueta}`;
}

/** «Agosto 2026 · 29 jul → 28 ago». */
export function etiquetaDePeriodo(p: PeriodoInfo): string {
  return `${nombreDePeriodo(p)} · ${fechaCorta(p.fecha_ini)} → ${fechaCorta(p.fecha_fin)}`;
}

/**
 * El periodo que se abre al entrar: el que pide la dirección (`?periodo=`) si
 * existe; si no, el más reciente que ya está pagado —es donde hay boletas que
 * subir—; y si ninguno lo está, el más reciente.
 */
export function periodoInicial(periodos: readonly PeriodoInfo[], pedido: string | null): string | null {
  if (pedido && periodos.some((p) => p.id === pedido)) return pedido;
  return (periodos.find((p) => p.estado === "pagado") ?? periodos[0])?.id ?? null;
}

/** Un instante como «13 sept, 14:35», en hora de Lima. `—` si no hay fecha. */
export function fechaHoraLima(iso: string | null | undefined): string {
  if (!iso) return "—";
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA, day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", hour12: false,
  }).format(new Date(iso)).replace(/\./g, "");
}

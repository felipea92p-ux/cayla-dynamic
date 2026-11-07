"use client";

// «LAS PANTALLAS SE ENTERAN AL INSTANTE» (2026-11-07, tiempo real lote 1, migración 0604).
//
// QUÉ PROMETE
//   `useAlDia(temas, ponerseAlDia)` llama a `ponerseAlDia` cuando la base avisa que cambió uno de esos temas: medio
//   segundo después de que alguien guardó, en otra pestaña, otra computadora u otra sede. Y también cuando el aviso
//   pudo perderse —al reconectarse el canal, al volver a mirar la pestaña— y cada 5 min como respaldo.
//   `ponerseAlDia` tiene que ser una lectura EN SILENCIO: sin el «Cargando…» que borra la pantalla y sin un aviso de
//   error cada vez. Si devuelve `false` («ahora no pude», p. ej. porque hay otra carga en curso), se reintenta al
//   segundo: un aviso nunca se da por leído si no se leyó.
//
// QUÉ ASUME
//   * El aviso no trae datos (0604): dice CUÁNDO leer, nunca QUÉ. La pantalla vuelve a leer por sus funciones de
//     siempre, que son las que revisan permisos. Si algún día un aviso trajera la fila, esa fila no se pintaría.
//   * El websocket se cae sin avisar: la Mac mini se duerme, el wifi de la tienda parpadea, el navegador congela una
//     pestaña de fondo. Por eso nunca se confía solo en él.
//
// LO QUE NO HACE, A PROPÓSITO
//   * No lee encima de alguien que está escribiendo: espera a que suelte el campo. La meta de cobertura se guarda al
//     salir del campo; leer antes le pisaría lo que tecleó.
//   * No lee con la pestaña escondida, porque nadie la mira: lo anota y lee al volver. El 2026-10-30 tres pestañas
//     ocultas de un terminal hacían el 78 % de las lecturas de marcajes de todo el sistema.
//   * No lee diez veces seguidas: los avisos que llegan juntos se leen una vez, y nunca más de una vez por segundo.
//
// Reemplaza a `lib/admin/turnos-al-dia.ts` (2026-11-02), que hacía lo mismo en Turnos con un aviso entre pestañas del
// mismo navegador y una relectura cada minuto. Aquel archivo decía que si un minuto dejaba de bastar, el paso
// siguiente era Realtime: es esto.

import { useEffect, useRef, useState } from "react";
import { REALTIME_SUBSCRIBE_STATES } from "@supabase/supabase-js";
import { createAdminSupabaseClient, type ClienteCayla } from "@cayla-dynamic/database";

/**
 * Los temas que avisa la base. La verdad está en la base —los triggers de la 0604 y quién puede escuchar cada uno en
 * `fn_tiempo_real_puede_escuchar`—; `tests/tiempo-real.test.ts` compara esta lista con la de esa función.
 */
export const TEMAS = ["asistencia", "horarios", "personas"] as const;
export type Tema = (typeof TEMAS)[number];

/** El respaldo: cada cuánto se vuelve a leer si en ese rato no llegó ningún aviso. */
export const RESPALDO_MS = 5 * 60_000;
/** Cuánto se espera para juntar los avisos que llegan casi a la vez (un guardado que toca dos temas). */
export const ESPERA_RAFAGA_MS = 250;
/** Nunca más de una lectura por segundo, aunque los avisos no paren. */
export const MINIMO_ENTRE_LECTURAS_MS = 1_000;
/** Al volver a la pestaña se lee si la última lectura fue hace al menos esto. */
export const MINIMO_AL_VOLVER_MS = 5_000;
/** Un canal sin nadie que lo escuche se cierra pasado este rato: así navegar entre pantallas no lo cierra y lo reabre. */
export const CIERRE_DIFERIDO_MS = 30_000;

// ─── Cuándo leer (puro, probado en tests/tiempo-real.test.ts) ────────────────────────────────────────────────────

export interface EstadoLectura {
  /** Hay un cambio avisado (o posible) que todavía no se leyó. */
  pendiente: boolean;
  visible: boolean;
  escribiendo: boolean;
  ahora: number;
  ultimaLectura: number;
}

/**
 * En cuántos milisegundos leer, o `null` si toca esperar: nada pendiente, la pestaña escondida o alguien
 * escribiendo. Esperar no pierde nada: queda pendiente, y volver a la pestaña o soltar el campo lo retoma.
 */
export function cuandoLeer(e: EstadoLectura): number | null {
  if (!e.pendiente || !e.visible || e.escribiendo) return null;
  return Math.max(ESPERA_RAFAGA_MS, MINIMO_ENTRE_LECTURAS_MS - (e.ahora - e.ultimaLectura));
}

/** Al volver a mirar la pestaña: ¿pudo haberse perdido algo? Solo si la última lectura no fue recién. */
export function alVolverHayQueLeer(ahora: number, ultimaLectura: number): boolean {
  return ahora - ultimaLectura >= MINIMO_AL_VOLVER_MS;
}

/** El respaldo solo lee si en todo ese rato no se leyó por otro motivo. */
export function tocaElRespaldo(ahora: number, ultimaLectura: number, respaldoMs = RESPALDO_MS): boolean {
  return ahora - ultimaLectura >= respaldoMs - 1_000;
}

/** ¿Hay un campo de texto con el cursor adentro? Un botón o una casilla no cuentan: ahí no se escribe. */
export function hayCampoEnUso(): boolean {
  if (typeof document === "undefined") return false;
  const el = document.activeElement;
  if (!el) return false;
  if (el instanceof HTMLTextAreaElement || el instanceof HTMLSelectElement) return true;
  if (el instanceof HTMLInputElement) return !["button", "checkbox", "radio", "submit", "reset"].includes(el.type);
  return el instanceof HTMLElement && el.isContentEditable;
}

// ─── Los canales: uno por tema y por cliente, compartido por todas las pantallas que lo escuchan ───────────────

/** Lo que este archivo usa del cliente de Supabase. Las pruebas lo imitan sin levantar nada. */
export type ClienteTiempoReal = Pick<ClienteCayla, "channel" | "removeChannel">;

/**
 * Cómo está el canal, para que una pantalla que promete «en vivo» no mienta. `conectando` es el primer instante (o un
 * reintento después de un corte); `sin_conexion`, un corte que la librería está reintentando, o un tema que esta
 * sesión no puede escuchar.
 */
export type Conexion = "conectando" | "conectado" | "sin_conexion";

export interface Escucha {
  /** Llegó un aviso: algo cambió. */
  alAviso: () => void;
  /** El canal quedó escuchando (la primera vez, o de nuevo tras un corte): pudo cambiar algo sin que llegara aviso. */
  alConectar: () => void;
  /** Cambió el estado del canal. Se llama también al empezar a escuchar, con el estado que ya tenía. */
  alCambiarConexion?: (estado: Conexion) => void;
}

interface Canal {
  canal: ReturnType<ClienteTiempoReal["channel"]>;
  escuchas: Set<Escucha>;
  cierre: ReturnType<typeof setTimeout> | null;
  conexion: Conexion;
}

const canalesPorCliente = new WeakMap<ClienteTiempoReal, Map<Tema, Canal>>();
const negadosPorCliente = new WeakMap<ClienteTiempoReal, Set<Tema>>();

/**
 * Empieza a escuchar un tema; devuelve cómo dejar de escucharlo. Todas las pantallas que escuchan el mismo tema con
 * el mismo cliente comparten UN canal: el websocket es uno por pestaña, y cada canal más es una unión que Realtime
 * cobra y limita.
 *
 * Cada vez que el canal queda escuchando —también la PRIMERA— avisa `alConectar`: entre que la pantalla leyó y que el
 * canal quedó abierto pudo guardarse algo, y ese aviso nunca llegó. Como el canal sobrevive a navegar (se cierra
 * diferido), eso pasa una vez por sesión, no en cada pantalla.
 *
 * Si la base dice que esta sesión no puede escuchar el tema (`fn_tiempo_real_puede_escuchar`), no se reintenta: la
 * pantalla sigue con su respaldo, que es lo mismo que tenía antes del tiempo real.
 */
export function escucharTema(cliente: ClienteTiempoReal, tema: Tema, escucha: Escucha): () => void {
  if (negadosPorCliente.get(cliente)?.has(tema)) {
    escucha.alCambiarConexion?.("sin_conexion");
    return () => {};
  }
  let canales = canalesPorCliente.get(cliente);
  if (!canales) {
    canales = new Map();
    canalesPorCliente.set(cliente, canales);
  }
  const mapa = canales;
  let c = mapa.get(tema);
  if (!c) {
    const nuevo: Canal = {
      canal: cliente.channel(`dynamic:${tema}`, { config: { private: true } }),
      escuchas: new Set(),
      cierre: null,
      conexion: "conectando",
    };
    const cambiar = (conexion: Conexion) => {
      if (nuevo.conexion === conexion) return;
      nuevo.conexion = conexion;
      for (const e of [...nuevo.escuchas]) e.alCambiarConexion?.(conexion);
    };
    nuevo.canal
      .on("broadcast", { event: "cambio" }, () => {
        for (const e of [...nuevo.escuchas]) e.alAviso();
      })
      .subscribe((estado, error) => {
        if (estado === REALTIME_SUBSCRIBE_STATES.SUBSCRIBED) {
          cambiar("conectado");
          for (const e of [...nuevo.escuchas]) e.alConectar();
          return;
        }
        cambiar("sin_conexion");
        if (estado === REALTIME_SUBSCRIBE_STATES.CHANNEL_ERROR && /unauthorized/i.test(error?.message ?? "")) {
          let negados = negadosPorCliente.get(cliente);
          if (!negados) {
            negados = new Set();
            negadosPorCliente.set(cliente, negados);
          }
          negados.add(tema);
          if (mapa.get(tema) === nuevo) mapa.delete(tema);
          void cliente.removeChannel(nuevo.canal);
        }
        // Un corte (CLOSED, TIMED_OUT, otro CHANNEL_ERROR) lo reintenta la librería sola; al volver, SUBSCRIBED.
      });
    mapa.set(tema, nuevo);
    c = nuevo;
  }
  const canal = c;
  if (canal.cierre !== null) {
    clearTimeout(canal.cierre);
    canal.cierre = null;
  }
  canal.escuchas.add(escucha);
  escucha.alCambiarConexion?.(canal.conexion);

  return () => {
    canal.escuchas.delete(escucha);
    if (canal.escuchas.size > 0 || canal.cierre !== null) return;
    canal.cierre = setTimeout(() => {
      canal.cierre = null;
      if (canal.escuchas.size > 0 || mapa.get(tema) !== canal) return;
      mapa.delete(tema);
      void cliente.removeChannel(canal.canal);
    }, CIERRE_DIFERIDO_MS);
  };
}

// ─── El hook ───────────────────────────────────────────────────────────────────────────────────────────────────

export interface OpcionesAlDia {
  /** Apagado no escucha ni relee (p. ej. mientras no hay sede elegida). */
  activo?: boolean;
  /** Cada cuánto se relee si no llegó ningún aviso. Una pantalla que lee algo que todavía no avisa lo baja. */
  respaldoMs?: number;
  /** El del panel, salvo que se diga otro (el terminal tiene su propia sesión). */
  cliente?: ClienteTiempoReal;
}

/**
 * Mantiene una pantalla al día: relee en silencio cuando la base avisa un cambio de `temas`, cuando el canal se
 * (re)conecta, al volver a la pestaña y con el respaldo. Ver el encabezado de este archivo. Devuelve cómo está el
 * canal, para la pantalla que muestra «en vivo».
 */
export function useAlDia(temas: readonly Tema[], ponerseAlDia: () => void | boolean, opciones: OpcionesAlDia = {}): Conexion {
  const { activo = true, respaldoMs = RESPALDO_MS, cliente } = opciones;
  const [conexion, setConexion] = useState<Conexion>("conectando");
  const ultima = useRef(ponerseAlDia);
  useEffect(() => {
    ultima.current = ponerseAlDia;
  });
  const clave = [...new Set(temas)].sort().join(",");

  useEffect(() => {
    if (!activo) return;
    const sb = cliente ?? createAdminSupabaseClient();
    let ultimaLectura = Date.now(); // la pantalla acaba de leer por su cuenta al montarse
    let pendiente = false;
    let temporizador: ReturnType<typeof setTimeout> | null = null;

    const estado = (): EstadoLectura => ({
      pendiente,
      visible: document.visibilityState === "visible",
      escribiendo: hayCampoEnUso(),
      ahora: Date.now(),
      ultimaLectura,
    });
    const programar = () => {
      if (temporizador !== null) return;
      const en = cuandoLeer(estado());
      if (en === null) return;
      temporizador = setTimeout(() => {
        temporizador = null;
        // Mientras esperaba pudo esconderse la pestaña o empezar alguien a escribir: entonces sigue pendiente.
        if (cuandoLeer(estado()) === null) return;
        pendiente = false;
        ultimaLectura = Date.now();
        if (ultima.current() === false) marcar(); // no pudo leer: sigue pendiente y se reintenta al segundo
      }, en);
    };
    function marcar() {
      pendiente = true;
      programar();
    }

    const porTema = new Map<Tema, Conexion>();
    const dejar = clave
      .split(",")
      .filter((t): t is Tema => (TEMAS as readonly string[]).includes(t))
      .map((tema) => escucharTema(sb, tema, {
        alAviso: marcar,
        alConectar: marcar,
        alCambiarConexion: (estado) => {
          porTema.set(tema, estado);
          setConexion(conexionDeTodos([...porTema.values()]));
        },
      }));

    const alVolver = () => {
      if (document.visibilityState !== "visible") return;
      if (alVolverHayQueLeer(Date.now(), ultimaLectura)) pendiente = true;
      programar();
    };
    // `focusout` llega antes de que el foco se mueva: se mira en la vuelta siguiente, cuando ya soltó el campo.
    const alSoltarCampo = () => {
      setTimeout(programar, 0);
    };
    const respaldo = setInterval(() => {
      if (document.visibilityState === "visible" && tocaElRespaldo(Date.now(), ultimaLectura, respaldoMs)) marcar();
    }, respaldoMs);

    document.addEventListener("visibilitychange", alVolver);
    window.addEventListener("focus", alVolver);
    document.addEventListener("focusout", alSoltarCampo);
    return () => {
      for (const d of dejar) d();
      document.removeEventListener("visibilitychange", alVolver);
      window.removeEventListener("focus", alVolver);
      document.removeEventListener("focusout", alSoltarCampo);
      clearInterval(respaldo);
      if (temporizador !== null) clearTimeout(temporizador);
    };
  }, [activo, clave, respaldoMs, cliente]);

  return conexion;
}

/** Varios temas juntos: basta uno cortado para que la pantalla no pueda decir «al instante». */
export function conexionDeTodos(estados: Conexion[]): Conexion {
  if (estados.includes("sin_conexion")) return "sin_conexion";
  if (estados.length > 0 && estados.every((e) => e === "conectado")) return "conectado";
  return "conectando";
}

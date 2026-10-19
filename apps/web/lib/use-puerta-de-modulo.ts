"use client";

// ============================================================================
// use-puerta-de-modulo.ts — el estado de «términos primero, guía después»
// ============================================================================
// QUÉ PROMETE · para el módulo que se está viendo, UNA respuesta (`capa`) y si
//               el módulo se puede ver (`bloquea`), más lo que hace falta para
//               dibujar la capa y para resolverla (`aceptar`, `entendido`,
//               `postergar`). La decisión es de `capaActiva`; esto solo lee lo que
//               esa función necesita y se lo da.
// QUÉ ASUME   · que `terminos.ts` manda: sin ningún texto aprobado este hook no
//               consulta la base ni toca el navegador, y devuelve de inmediato
//               «sin capa de términos». Hoy, con todo en borrador, es lo que pasa.
//
// CUANDO ALGO FALLA (Vogels):
//   · No se pudo leer la base  → `lecturaAceptaciones = "error"`: no se muestra la
//     guía ni se bloquea nada; el módulo funciona y se reintenta en la próxima carga.
//   · No se pudo guardar una aceptación → `error` con un texto para la persona; el
//     botón queda disponible para reintentar y NO se marca como aceptada en memoria.
//     Dar por aceptado lo que la base no confirmó sería dejar a alguien usando el
//     módulo sin constancia, creyendo que la tiene.
//   · No hay localStorage → los avisos vuelven a salir; es una ayuda, no un dato.
//
// DOS CLIENTES DE LA MISMA PERSONA (celular y Mac a la vez): la base lo absorbe
// (`fn_aceptar_terminos` contesta «ya estaba»), así que aquí no hay carrera que
// resolver: ambos terminan con la constancia.
// ============================================================================

import { useCallback, useEffect, useMemo, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import {
  TERMINOS, bloqueaElModulo, capaActiva, terminosVigentes, textoAceptado,
  type Capa, type TerminosModulo,
} from "@cayla-dynamic/shared";
import {
  claveDeTerminos, estadoDeCapas, hayTerminosAprobados, llaveDeAviso,
  type LecturaAceptaciones,
} from "@/lib/terminos-mios";

export interface PuertaDeModulo {
  capa: Capa | null;
  /** ¿El módulo no se puede ver todavía? Solo sin términos de uso o con una casilla pendiente. */
  bloquea: boolean;
  /** Lo que hay que dibujar si `capa` es de términos. */
  terminos: TerminosModulo | null;
  enviando: boolean;
  error: string | null;
  /** Deja constancia en la base. `true` si quedó guardada. */
  aceptar: (t: TerminosModulo) => Promise<boolean>;
  /** «Entendido» de un aviso: se recuerda en este navegador. */
  entendido: (t: TerminosModulo) => void;
  /** «Ahora no» de un aviso: no vuelve a salir en esta visita, pero tampoco se recuerda. */
  postergar: (t: TerminosModulo) => void;
}

function leerAvisosVistos(): Set<string> {
  const vistos = new Set<string>();
  for (const t of TERMINOS) {
    if (t.estado !== "aprobado" || t.peso === "aceptacion") continue;
    try {
      if (localStorage.getItem(llaveDeAviso(t)) === "1") vistos.add(claveDeTerminos(t));
    } catch {
      // Sin localStorage el aviso vuelve a salir. Es preferible a no mostrarlo nunca.
    }
  }
  return vistos;
}

/**
 * `listo` = ya hay una persona con sesión (en «Lo mío», `Boolean(yo)`). Sin ella
 * la lectura de la base fallaría por no haber iniciado sesión y se leería como
 * un error de verdad: se quedaría en «error» hasta recargar la página.
 */
export function usePuertaDeModulo(modulo: string, tieneGuia: boolean, listo: boolean): PuertaDeModulo {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const hayAlgo = hayTerminosAprobados();

  const [lectura, setLectura] = useState<LecturaAceptaciones>(hayAlgo ? "cargando" : "lista");
  const [aceptadas, setAceptadas] = useState<ReadonlySet<string>>(() => new Set());
  const [avisosLeidos, setAvisosLeidos] = useState(!hayAlgo);
  const [avisosVistos, setAvisosVistos] = useState<ReadonlySet<string>>(() => new Set());
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!hayAlgo || !listo) return;

    let vigente = true;
    void (async () => {
      // Los avisos viven en el navegador y no esperan a la base: se leen primero,
      // para que un fallo de la red no esconda un aviso que no la necesita.
      setAvisosVistos(leerAvisosVistos());
      setAvisosLeidos(true);

      const { data, error: errorLectura } = await supabase.rpc("fn_mis_aceptaciones_terminos");
      if (!vigente) return;
      if (errorLectura || !data) { setLectura("error"); return; }
      setAceptadas(new Set(data.map((f) => claveDeTerminos(f))));
      setLectura("lista");
    })();
    return () => { vigente = false; };
  }, [hayAlgo, listo, supabase]);

  const estado = estadoDeCapas({
    modulo, tieneGuia, lecturaAceptaciones: lectura, aceptadas, avisosLeidos, avisosVistos,
  });
  const capa = capaActiva(estado);
  const bloquea = bloqueaElModulo(estado);

  const terminos =
    capa === "terminos_de_uso" ? terminosVigentes("general")
    : capa === "terminos_del_modulo" ? terminosVigentes(modulo)
    : null;

  const aceptar = useCallback(async (t: TerminosModulo) => {
    setEnviando(true);
    setError(null);
    const { error: errorGuardado } = await supabase.rpc("fn_aceptar_terminos", {
      p_modulo: t.modulo, p_version: t.version, p_texto: textoAceptado(t),
    });
    setEnviando(false);
    if (errorGuardado) {
      setError("No se pudo guardar tu aceptación. Revisa tu conexión y vuelve a intentarlo.");
      return false;
    }
    setAceptadas((previas) => new Set(previas).add(claveDeTerminos(t)));
    return true;
  }, [supabase]);

  const marcarVisto = useCallback((t: TerminosModulo) => {
    setAvisosVistos((previos) => new Set(previos).add(claveDeTerminos(t)));
  }, []);

  const entendido = useCallback((t: TerminosModulo) => {
    try {
      localStorage.setItem(llaveDeAviso(t), "1");
    } catch {
      // Igual que arriba: si no se puede recordar, volverá a salir. No se pierde nada de verdad.
    }
    marcarVisto(t);
  }, [marcarVisto]);

  return { capa, bloquea, terminos, enviando, error, aceptar, entendido, postergar: marcarVisto };
}

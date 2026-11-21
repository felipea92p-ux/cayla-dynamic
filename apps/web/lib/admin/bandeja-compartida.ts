"use client";

// La Bandeja se lee UNA vez por pestaña, y la comparten el menú, la pantalla, el Dashboard y Equipo.
//
// QUÉ PROMETE
//   Un solo lector (`lib/lector-compartido.ts`) por persona y rol. Quien lo pide recibe siempre el mismo, así que:
//   · el número del menú y la lista de la pantalla salen de LA MISMA lectura: no pueden decir cosas distintas;
//   · al abrir la Bandeja, la pantalla pinta con lo que el menú ya había leído y se confirma con la base detrás;
//   · dos piezas que piden a la vez comparten una sola ronda de consultas.
//
// POR QUÉ (medido en producción, 12 al 17 de noviembre de 2026)
//   Las ~28 consultas de la Bandeja eran el 72 % del tiempo de base de Dynamic, y cada pieza las pedía por su
//   cuenta. La pantalla esperaba a la más lenta —`fn_liquidaciones_vencidas_bandeja`, 0,9 s de media y 4,5 s la
//   peor— aunque el menú acababa de traer exactamente lo mismo para pintar su número.
//
// QUÉ NO HACE
//   No cambia qué se cuenta ni qué se lista: eso sigue en `bandeja-fuentes.ts`. Tampoco vuelve más barata ninguna
//   consulta. Y no guarda nada fuera de la memoria de la pestaña.
//
// SE ROMPE SI
//   La llave deja de llevar a la persona. Dos líderes de equipo tienen el mismo rol y ven sedes distintas: con la
//   llave solo por rol, quien entra después en la misma pestaña vería la Bandeja de quien salió.

import { useCallback, useSyncExternalStore } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { crearLectorCompartido, type Lectura, type LectorCompartido } from "@/lib/lector-compartido";
import { traerFuentesYNormas } from "./bandeja-equipo";
import type { FuentesBandeja } from "./bandeja-fuentes";

/** Una sección de la Bandeja que no respondió, con su error, para que la pantalla lo diga. */
export interface FalloDeFuente {
  que: string;
  error: unknown;
}

export interface ContenidoBandeja {
  fuentes: FuentesBandeja;
  /** Constancias de Normas sin recoger (solo DO; para el resto, 0). */
  constanciasNormas: number;
  fallos: FalloDeFuente[];
}

export type LecturaBandeja = Lectura<ContenidoBandeja>;
export type LectorBandeja = LectorCompartido<ContenidoBandeja>;

/**
 * Dos piezas que se montan en el mismo instante (el menú y la pantalla al entrar) se dan por «la misma entrada».
 * No hay un guardado de por medio: solo evita que la segunda pida otra ronda por haber llegado unos ms después.
 */
export const HOLGURA_MISMA_ENTRADA_MS = 2_000;

/**
 * Hasta qué edad la pantalla Bandeja pinta con lo ya leído mientras confirma detrás. Es el respaldo de `useAlDia`
 * (5 min): con el panel a la vista, el menú nunca tiene una lectura más vieja que eso. Más vieja, espera a la base.
 */
export const EDAD_PARA_PINTAR_MS = 5 * 60_000;

/** Lo que vale un contador sin volver a preguntarlo: lo mismo que el pulso del menú (`use-pulso-contadores.ts`). */
export const EDAD_PARA_CONTAR_MS = 60_000;

let actual: { clave: string; lector: LectorBandeja } | null = null;

/** El lector de esta persona con este rol. `null` mientras no se sabe quién es. */
export function lectorDeLaBandeja(personaId: string | null | undefined, rol: string | null | undefined): LectorBandeja | null {
  if (!personaId || !rol) return null;
  const clave = `${personaId}:${rol}`;
  if (actual === null || actual.clave !== clave) {
    actual = {
      clave,
      lector: crearLectorCompartido(async () => {
        const fallos: FalloDeFuente[] = [];
        const { fuentes, constanciasNormas } = await traerFuentesYNormas(
          createAdminSupabaseClient(), rol, (que, error) => { fallos.push({ que, error }); },
        );
        return { fuentes, constanciasNormas, fallos };
      }),
    };
  }
  return actual.lector;
}

/** Al cerrar sesión: lo leído no espera en memoria a quien entre después. */
export function olvidarLaBandeja(): void {
  actual = null;
}

const SIN_ESCUCHA = () => {};

/** La última lectura de la Bandeja, al día con cada una que llegue, la pida quien la pida. */
export function useLecturaBandeja(lector: LectorBandeja | null): LecturaBandeja | null {
  return useSyncExternalStore(
    useCallback((alCambiar: () => void) => (lector ? lector.escuchar(alCambiar) : SIN_ESCUCHA), [lector]),
    () => lector?.ultima() ?? null,
    () => null,
  );
}

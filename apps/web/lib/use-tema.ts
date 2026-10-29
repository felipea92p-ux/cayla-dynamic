"use client";

// El tema claro/oscuro/sistema. La paleta oscura y las reglas que la aplican
// viven en `globals.css`; este hook solo decide y recuerda CUÁL de las tres
// está activa, y lo refleja en `data-tema` sobre <html>.
//
// "Sistema" no se guarda como valor: es la AUSENCIA de la clave en
// localStorage, y así el CSS ya sabía leerla (`prefers-color-scheme`) antes
// de que este hook existiera. Guardarlo como un tercer string habría hecho
// falta enseñarle a la CSS un tercer estado que no necesita.
//
// Arranca en "sistema" para coincidir con el primer render del servidor —
// donde no hay `localStorage`— y recién se sincroniza con lo guardado DESPUÉS
// de montar, mismo patrón hidratación-segura que `useFiltroGuardado`. Eso NO
// es lo que evita el parpadeo del tema equivocado: eso lo hace el script en
// `app/layout.tsx`, que pone `data-tema` en el <html> antes de que React
// pinte nada. Este hook solo mantiene el botón del selector en sintonía con
// lo que ya se ve en pantalla.
//
// Desde 2026-09-06 hay una CUARTA fuente, por debajo de las dos de arriba:
// la fila `apariencia_tema` de la tabla `configuracion`, editable desde
// /admin/apariencia (ver ese archivo). Es el tema que se aplica cuando
// *nadie* eligió uno a mano en este navegador — así el panel Y el terminal
// de cada sede pueden dejarse en oscuro (o claro) desde un solo lugar, sin
// tocar cada Mac mini. Prioridad completa: elegido a mano > configuración
// global > prefers-color-scheme del sistema > claro por defecto. Pasar el
// cliente de Supabase de la superficie que llama (admin o terminal, cada una
// tiene su propia sesión — ver createAdminSupabaseClient/
// createTerminalSupabaseClient) es lo que activa esta cuarta fuente; sin
// cliente, el hook se comporta exactamente como antes.

import { useCallback, useEffect, useState } from "react";
import type { ClienteCayla } from "@cayla-dynamic/database";

const CLAVE = "cayla-tema";
// Última configuración global conocida, cacheada para que el script
// anti-parpadeo de app/layout.tsx la pueda leer en la próxima carga sin
// esperar la respuesta de red — no es una preferencia personal, se sobra
// escribir en cuanto llega una más nueva.
const CLAVE_CACHE_GLOBAL = "cayla-tema-global";

export type Tema = "claro" | "oscuro" | "sistema";
type TemaGlobal = "claro" | "oscuro" | "automatico";

function aplicarAtributo(tema: Tema) {
  if (tema === "sistema") document.documentElement.removeAttribute("data-tema");
  else document.documentElement.setAttribute("data-tema", tema);
}

// Qué se ve realmente en pantalla con este tema — "sistema" no es un color,
// resuelve al que diga `prefers-color-scheme` del navegador. Sirve para que
// el selector rápido sepa cuándo un clic no va a cambiar nada visible (ver
// SIGUIENTE en selector-tema.tsx): si acabas de elegir "oscuro" a mano y tu
// sistema operativo también prefiere oscuro, pasar a "sistema" deja la
// pantalla exactamente igual — el clic sí corrió, pero parece que no hizo
// nada. Solo llamar en el navegador: matchMedia no existe en el render de
// servidor.
export function apariencia(tema: Tema): "claro" | "oscuro" {
  if (tema !== "sistema") return tema;
  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "oscuro" : "claro";
}

function aplicar(tema: Tema) {
  aplicarAtributo(tema);
  try {
    if (tema === "sistema") localStorage.removeItem(CLAVE);
    else localStorage.setItem(CLAVE, tema);
  } catch {
    // localStorage puede fallar (modo privado, cuota llena) — el tema sigue
    // aplicado en esta pestaña, solo no se acuerda entre visitas.
  }
}

export function useTema(cliente?: ClienteCayla): [Tema, (tema: Tema) => void] {
  const [tema, setTemaState] = useState<Tema>("sistema");

  useEffect(() => {
    let guardado: string | null = null;
    try {
      guardado = localStorage.getItem(CLAVE);
    } catch {
      // sin localStorage no hay nada guardado que leer.
    }

    if (guardado === "claro" || guardado === "oscuro") {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setTemaState(guardado);
      return; // preferencia personal: no hace falta preguntarle a la base.
    }

    if (!cliente) return;
    (async () => {
      try {
        // `getSession()` es local (localStorage/IndexedDB, sin red): evita
        // una consulta que saldría 401 en el terminal sin vincular todavía o
        // en el panel antes de iniciar sesión — casos normales, no errores.
        const { data: sesion } = await cliente.auth.getSession();
        if (!sesion.session) return;

        const { data } = await cliente
          .from("configuracion")
          .select("valor")
          .eq("clave", "apariencia_tema")
          .maybeSingle();
        const global = data?.valor as TemaGlobal | undefined;
        if (global === "claro" || global === "oscuro") {
          // Puede haber más de un <SelectorTema> montado a la vez (p. ej. el
          // cajón móvil y el de escritorio en /mio, cada uno con su propio
          // useTema()). Si mientras esta consulta estaba en vuelo la persona
          // ya eligió un tema a mano —en esta misma instancia o en la otra—,
          // no lo pisamos: sin este reintento, aplicar el global aquí
          // sobrescribiría `data-tema` con el valor viejo delante de sus ojos.
          let personal: string | null = null;
          try {
            personal = localStorage.getItem(CLAVE);
          } catch {
            // sin localStorage no hay preferencia personal que respetar aquí.
          }
          if (personal === "claro" || personal === "oscuro") return;

          aplicarAtributo(global);
          setTemaState(global);
          try {
            localStorage.setItem(CLAVE_CACHE_GLOBAL, global);
          } catch {
            // solo afecta qué tan rápido se ve el tema correcto la próxima vez.
          }
        }
        // "automatico" (o sin fila todavía) deja el tema en "sistema": ya es
        // el comportamiento por defecto, no hace falta tocar nada.
      } catch {
        // sin red no hay forma de saber la configuración global — se queda en
        // "sistema", igual que siempre se comportó este hook.
      }
    })();
  }, [cliente]);

  const setTema = useCallback((t: Tema) => {
    aplicar(t);
    setTemaState(t);
  }, []);

  return [tema, setTema];
}

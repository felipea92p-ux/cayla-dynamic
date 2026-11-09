"use client";

// Tema global (claro/oscuro/automático) para el panel Y el terminal de las 4
// sedes — ver 0378_apariencia_tema_global.sql y lib/use-tema.ts. Sigue
// existiendo el tema PERSONAL de cada quien (el selector de la barra de
// navegación); esto es solo lo que se ve cuando nadie eligió uno a mano.
//
// Con el vidrio, la superficie encendida ya NO sigue esta pantalla: cada
// aparato elige con su botón (lib/vidrio-tema.ts). Desde el 2026-11-09 las dos
// están encendidas en producción, así que hoy no cambia nada: sale del menú
// (`requiere: "tema-global"` en nav-items.ts) y, si alguien entra por la
// dirección, dice exactamente a quién le llega. `quienSigueElTemaGlobal` es la
// única fuente de esa respuesta; los textos de abajo solo la cuentan.
//
// A propósito NO es un selector de color libre: el sistema entero se pinta
// con los 11 --color-* de globals.css, auditados por contraste — dejar
// elegir un hex cualquiera por acá rompería exactamente la garantía que se
// acaba de construir. Elegir entre paletas curadas es lo que hay hoy (claro/
// oscuro, las dos ya verificadas); si mañana existiera una tercera paleta
// vetada, se agrega como una opción más, nunca como un color picker.

import { useCallback, useEffect, useState } from "react";
import { interruptoresVidrio, quienSigueElTemaGlobal } from "@/lib/vidrio";
import { sobretituloDeHoy } from "@/lib/admin/sobretitulo";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { puedeGestionarCatalogos } from "@cayla-dynamic/shared";
import { Cargando } from "@/components/cargando";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { useRolActual } from "@/lib/admin/use-rol";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { useToast } from "@/components/toast";

type TemaGlobal = "claro" | "oscuro" | "automatico";

const OPCIONES: Array<{ valor: TemaGlobal; etiqueta: string; ayuda: string }> = [
  { valor: "claro", etiqueta: "Claro", ayuda: "La paleta cálida de siempre — crema y tinta." },
  { valor: "oscuro", etiqueta: "Oscuro", ayuda: "Misma marca, invertida: papel sobre tinta." },
  {
    valor: "automatico",
    etiqueta: "Automático",
    ayuda: "Sigue el sistema operativo de cada dispositivo (lo que ya pasa hoy, sin esta configuración).",
  },
];

/** Qué decir según quién siga esta configuración. Las cuatro combinaciones existen: cada superficie tiene su interruptor. */
function textosDeAlcance(sigue: { panel: boolean; terminal: boolean }): { descripcion: string; alGuardar: string; nota: string } {
  if (sigue.panel && sigue.terminal) {
    return {
      descripcion: "El tema por defecto para todo el equipo — panel y terminales de marcaje.",
      alGuardar: "Se verá así en el panel y en los terminales de las 4 sedes que no tengan un tema personal elegido.",
      nota:
        "Quien elija un tema a mano en su propio navegador (el selector ☀/🌙 de la barra de navegación) sigue viendo el suyo — " +
        "esto solo decide qué ve quien no tocó nada. Los terminales de marcaje no tienen ese selector, así que siempre siguen esta configuración.",
    };
  }
  if (sigue.terminal) {
    return {
      descripcion: "El tema de los terminales de marcaje de las 4 sedes.",
      alGuardar: "Se verá así en los terminales de las 4 sedes. El panel no cambia: ahí cada aparato elige con su botón ☀/🌙.",
      nota: "En el panel cada computadora y cada teléfono eligen con su botón ☀/🌙, y esto no lo cambia. Los terminales de marcaje sí siguen esta configuración.",
    };
  }
  if (sigue.panel) {
    return {
      descripcion: "El tema por defecto del panel.",
      alGuardar: "Se verá así en el panel para quien no tenga un tema personal elegido. Los terminales no cambian: cada Mac mini elige con su botón ☀/🌙.",
      nota:
        "Quien elija un tema a mano en su propio navegador (el selector ☀/🌙 de la barra de navegación) sigue viendo el suyo — " +
        "esto solo decide qué ve quien no tocó nada. Los terminales de marcaje tienen su propio botón ☀/🌙 y no siguen esta configuración.",
    };
  }
  return {
    descripcion: "Hoy no cambia nada: cada aparato elige claro u oscuro con su botón ☀/🌙.",
    alGuardar: "Quedó guardado, pero hoy no cambia lo que se ve: el panel y los terminales eligen con su propio botón ☀/🌙.",
    nota:
      "El panel y los terminales de marcaje tienen el diseño nuevo: ahí cada computadora, teléfono y Mac mini elige claro u oscuro " +
      "con su botón ☀/🌙, y esta pantalla no lo cambia. Lo que elijas aquí solo se vería si se apagara el diseño nuevo. Por eso ya no está en el menú.",
  };
}

export default function AparienciaPage() {
  const router = useRouter();
  const rol = useRolActual();
  const puedeGestionar = puedeGestionarCatalogos(rol);
  const { avisar } = useToast();
  const textos = textosDeAlcance(quienSigueElTemaGlobal());

  const [temaActual, setTemaActual] = useState<TemaGlobal | null>(null);
  const [cargando, setCargando] = useState(true);
  const [guardandoValor, setGuardandoValor] = useState<TemaGlobal | null>(null);

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) {
      router.replace("/admin/login");
      return;
    }
    const { data } = await supabase
      .from("configuracion")
      .select("valor")
      .eq("clave", "apariencia_tema")
      .maybeSingle();
    setTemaActual((data?.valor as TemaGlobal | undefined) ?? "claro");
    setCargando(false);
  }, [router]);

  useEffect(() => {
    (async () => {
      await cargar();
    })();
  }, [cargar]);

  async function elegir(valor: TemaGlobal) {
    if (valor === temaActual || guardandoValor) return;
    setGuardandoValor(valor);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase
      .from("configuracion")
      .upsert({ clave: "apariencia_tema", valor }, { onConflict: "clave" });
    setGuardandoValor(null);
    if (error) {
      avisar("error", mensajeDeError(error, "guardar la apariencia"));
      return;
    }
    setTemaActual(valor);
    avisar(
      "ok",
      `Apariencia global cambiada a "${OPCIONES.find((o) => o.valor === valor)?.etiqueta}". ${textos.alGuardar}`,
    );
  }

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        <CabeceraPagina
          sobretitulo={interruptoresVidrio().panel ? sobretituloDeHoy("Configuración") : undefined}
          titulo="Apariencia"
          descripcion={textos.descripcion}
        />

        {rol === null || cargando ? (
          <Cargando />
        ) : !puedeGestionar ? (
          <div className="max-w-2xl rounded-control bg-ambar/15 px-4 py-3 text-sm text-ambar">
            Solo administradores y líderes pueden cambiar la apariencia global.
          </div>
        ) : (
          <div className="max-w-2xl">
            <div className="grid gap-3 sm:grid-cols-3">
              {OPCIONES.map((o) => {
                const seleccionada = temaActual === o.valor;
                return (
                  <button
                    key={o.valor}
                    type="button"
                    onClick={() => elegir(o.valor)}
                    disabled={guardandoValor !== null}
                    aria-pressed={seleccionada}
                    className={`flex flex-col gap-1.5 rounded-superficie border p-4 text-left transition-colors duration-150 disabled:opacity-50 ${
                      seleccionada
                        ? "border-rojo bg-papel"
                        : "border-sand bg-papel hover:border-taupe/40"
                    }`}
                  >
                    <span className="flex items-center gap-1.5 text-sm font-medium text-tinta">
                      {o.etiqueta}
                      {guardandoValor === o.valor && (
                        <span className="colibri aletea inline-block size-3.5" aria-hidden />
                      )}
                    </span>
                    <span className="text-xs text-taupe">{o.ayuda}</span>
                    {seleccionada && <span className="etiqueta text-rojo">En uso ahora</span>}
                  </button>
                );
              })}
            </div>

            <p className="mt-6 text-xs text-taupe">{textos.nota}</p>
          </div>
        )}
      </main>
    </div>
  );
}

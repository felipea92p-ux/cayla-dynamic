"use client";

// LA SEMANA DE LA PERSONA, en una fila compacta (2026-10-19): siete días con su frase corta («8 h 03», «25 min tarde»,
// «Sin jornada») que sirven de navegador. Corregir casi nunca es un día suelto: se corrige el lunes y se mira el martes.
// Con el calendario eso eran tres toques y una fecha escrita; aquí es uno.
//
// No es un reporte: la regla de cada frase vive en `lib/admin/semana-persona.ts` (con su prueba), y la verdad de cada
// día sigue siendo la jornada. Si la consulta falla, la fila lo dice y no inventa días.

import { useEffect, useMemo, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { cx } from "@/components/ui/cx";
import { addDias, lunesDeLaSemana } from "@/lib/admin/incidencias";
import { resumenDiaSemana, type JornadaDeLaSemana, type TonoDiaSemana } from "@/lib/admin/semana-persona";

const DIAS_ABR = ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"];
const TONO: Record<TonoDiaSemana, string> = {
  tarde: "text-rojo-profundo",
  ok: "text-verde",
  aviso: "text-ambar",
  neutro: "text-taupe",
};

type Carga =
  | { clave: string; error: true }
  | { clave: string; error: false; jornadas: Map<string, JornadaDeLaSemana>; levantadas: Set<string> };

export function SemanaDePersona({
  personaId,
  fecha,
  hoy,
  refresco,
  onElegir,
}: {
  personaId: string;
  /** El día abierto; la semana es la que lo contiene. */
  fecha: string;
  hoy: string;
  /** Cambia cuando el día abierto se corrige o se recarga: obliga a pedir la semana de nuevo. */
  refresco: string;
  onElegir: (iso: string) => void;
}) {
  const lunes = lunesDeLaSemana(fecha);
  const clave = `${personaId}|${lunes}|${refresco}`;
  const [carga, setCarga] = useState<Carga | null>(null);

  useEffect(() => {
    const supabase = createAdminSupabaseClient();
    const domingo = addDias(lunes, 6);
    let vivo = true;
    void (async () => {
      const [{ data: js, error: e1 }, { data: ls, error: e2 }] = await Promise.all([
        supabase.from("jornadas").select("fecha, estado, horas_trabajadas, minutos_tarde")
          .eq("persona_id", personaId).gte("fecha", lunes).lte("fecha", domingo),
        supabase.from("tardanzas_justificadas").select("fecha")
          .eq("persona_id", personaId).gte("fecha", lunes).lte("fecha", domingo),
      ]);
      if (!vivo) return;
      if (e1 || e2) { setCarga({ clave, error: true }); return; }
      setCarga({
        clave,
        error: false,
        jornadas: new Map(((js as JornadaDeLaSemana[] | null) ?? []).map((j) => [j.fecha, j])),
        levantadas: new Set(((ls as { fecha: string }[] | null) ?? []).map((l) => l.fecha)),
      });
    })();
    return () => { vivo = false; };
  }, [personaId, lunes, clave]);

  const dias = useMemo(() => Array.from({ length: 7 }, (_, i) => addDias(lunes, i)), [lunes]);
  // Mientras llega la semana nueva se sigue mostrando la anterior de la MISMA persona y semana (un refresco no
  // parpadea); si cambió la persona o la semana, no hay nada que mostrar todavía.
  const vigente = carga && carga.clave.startsWith(`${personaId}|${lunes}|`) ? carga : null;

  if (vigente?.error) {
    return <p className="mb-4 text-xs text-taupe">No se pudo cargar la semana de esta persona. Los demás datos sí.</p>;
  }

  return (
    <nav aria-label="Semana de esta persona" className="mb-4 flex gap-1.5 overflow-x-auto [scrollbar-width:none]">
      {dias.map((iso) => {
        const abierto = iso === fecha;
        const resumen = vigente
          ? resumenDiaSemana({ fecha: iso, hoy, jornada: vigente.jornadas.get(iso) ?? null, levantada: vigente.levantadas.has(iso) })
          : null;
        const d = new Date(`${iso}T00:00:00Z`);
        return (
          <button
            key={iso}
            type="button"
            aria-current={abierto ? "date" : undefined}
            onClick={() => onElegir(iso)}
            className={cx(
              "min-w-[5.25rem] flex-1 rounded-control border px-2.5 py-1.5 text-left transition-colors duration-150",
              abierto ? "border-tinta bg-papel" : "border-sand bg-papel/60 hover:border-taupe",
            )}
          >
            <span className="flex items-baseline gap-1 text-xs">
              <span className={cx("font-medium", abierto ? "text-tinta" : "text-taupe")}>{DIAS_ABR[d.getUTCDay()]} {d.getUTCDate()}</span>
              {iso === hoy && <span className="text-[10px] uppercase tracking-wide text-rojo-profundo">hoy</span>}
            </span>
            <span className={cx("mt-0.5 block truncate text-xs", resumen ? TONO[resumen.tono] : "text-taupe/50")}>
              {resumen ? (
                resumen.tachado ? (
                  <>
                    <s>{resumen.texto}</s>{resumen.nota && <span> · {resumen.nota}</span>}
                  </>
                ) : (
                  resumen.texto
                )
              ) : (
                "…"
              )}
            </span>
          </button>
        );
      })}
    </nav>
  );
}

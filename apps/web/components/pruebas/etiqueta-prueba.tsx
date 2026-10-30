"use client";

// ============================================================================
// «Prueba · 2 de 3»: la etiqueta que acompaña a quien está de prueba en el panel.
// ----------------------------------------------------------------------------
// QUÉ PROMETE. UNA sola pieza y UN solo hook para que Equipo, Horas, Planilla y
// Horarios digan lo mismo de la misma persona. Los datos salen de
// `fn_pruebas_abiertas` (0536): cada quien ve lo de su alcance, DO todo y la líder
// de equipo su sede.
//
// QUÉ NO HACE. No decide nada y no cambia ningún pago: solo avisa que esa persona
// está de prueba y en qué día va. Si la consulta falla, no hay etiqueta —el lado
// seguro: una pantalla sin la etiqueta se ve como antes.
//
// POR QUÉ UN HOOK Y NO UNA CONSULTA POR PANTALLA. Cinco pantallas pidiendo lo mismo
// es como se acaba con cinco criterios de «qué es estar de prueba». Aquí hay uno.
// ============================================================================

import { useEffect, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Insignia } from "@/components/ui/insignia";
import { etiquetaDePrueba, type FilaPrueba } from "@/lib/admin/pruebas";

/** Las pruebas abiertas que quien mira puede ver, por persona. Se carga una vez al montar. */
export function usePruebasPorPersona(): Map<string, FilaPrueba> {
  const [pruebas, setPruebas] = useState<Map<string, FilaPrueba>>(new Map());
  useEffect(() => {
    let vigente = true;
    void createAdminSupabaseClient()
      .rpc("fn_pruebas_abiertas")
      .then(({ data, error }) => {
        if (!vigente || error) return;
        setPruebas(new Map(((data as FilaPrueba[] | null) ?? []).map((f) => [f.persona_id, f] as const)));
      });
    return () => { vigente = false; };
  }, []);
  return pruebas;
}

export function EtiquetaPrueba({ fila, className }: { fila: FilaPrueba | undefined | null; className?: string }) {
  if (!fila) return null;
  const e = etiquetaDePrueba(fila);
  return (
    <span className={className} title={`Está en preselección: lleva ${fila.dias_trabajados} de ${fila.dias_plazo} días trabajados`}>
      <Insignia variante={e.variante} tamano="sm" punto={false}>{e.texto}</Insignia>
    </span>
  );
}

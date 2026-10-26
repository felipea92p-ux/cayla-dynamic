"use client";

import { useEffect, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { hoyLima, mesesRecientesLima } from "@cayla-dynamic/shared";
import { resumirCasos, traerResumenCasos, type ResumenCasos } from "@/lib/admin/casos-resumen";

// El indicador opcional «Casos» del Dashboard.
//
// SOLO CONSULTA MIENTRAS `activo`, igual que `usePendientesBandeja`: quien no
// agregó el indicador no paga esa consulta. Trae los últimos 6 meses una sola
// vez — es el tramo más largo que ofrece el detalle— y se refresca cada 5
// minutos: esto no es un tablero en vivo como la asistencia.

const CADA_MS = 5 * 60_000;
const MESES_ATRAS = 6;

export interface EstadoCasosResumen {
  resumen: ResumenCasos | null;
  fallo: boolean;
}

export function useCasosResumen(activo: boolean): EstadoCasosResumen {
  const [estado, setEstado] = useState<EstadoCasosResumen>({ resumen: null, fallo: false });

  useEffect(() => {
    if (!activo) return;
    let vivo = true;
    const desde = mesesRecientesLima(MESES_ATRAS, hoyLima())[MESES_ATRAS - 1];
    async function cargar() {
      const { filas, error } = await traerResumenCasos(createAdminSupabaseClient(), desde);
      if (!vivo) return;
      if (error) { setEstado((e) => ({ ...e, fallo: true })); return; }
      setEstado({ resumen: resumirCasos(filas), fallo: false });
    }
    void cargar();
    const t = setInterval(() => void cargar(), CADA_MS);
    return () => { vivo = false; clearInterval(t); };
  }, [activo]);

  return estado;
}

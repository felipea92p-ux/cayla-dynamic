"use client";

import { useEffect, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { traerFuentesYNormas } from "@/lib/admin/bandeja-equipo";
import { resumenDeLaBandeja, type ResumenPendientes } from "@/lib/admin/pendientes-resumen";

// Los pendientes de la Bandeja para el indicador opcional del Dashboard.
//
// SOLO CONSULTA MIENTRAS `activo`: quien deja el Dashboard con solo asistencia
// (el diseño por defecto) no paga ni una petición de esto. Usa las mismas
// fuentes que el menú y que /admin/bandeja, y por el mismo camino que el menú
// (`traerFuentesYNormas`, que incluye Normas para DO), no una consulta propia.
// El número sale de `resumenDeLaBandeja`, que usa `cuentaDeLaBandeja`: la misma
// cuenta que el menú. Antes sumaba cada correo fallido pero no Normas, y el
// indicador decía un número distinto al del menú para lo mismo.
//
// Se refresca cada 5 minutos —no cada 30 s como la asistencia—: la Bandeja no
// es un tablero en vivo y son varias consultas.

const CADA_MS = 5 * 60_000;

export interface EstadoPendientes {
  resumen: ResumenPendientes | null;
  /** Alguna sección de la Bandeja no respondió: el número puede estar corto. */
  incompleto: boolean;
  /** Ninguna respuesta útil: se dice, no se pinta un cero. */
  fallo: boolean;
}

export function usePendientesBandeja(activo: boolean, rol: string | null | undefined): EstadoPendientes {
  const [estado, setEstado] = useState<EstadoPendientes>({ resumen: null, incompleto: false, fallo: false });

  useEffect(() => {
    if (!activo || !rol) return;
    let vivo = true;
    async function cargar() {
      try {
        const { fuentes: f, constanciasNormas } = await traerFuentesYNormas(createAdminSupabaseClient(), rol);
        if (!vivo) return;
        setEstado({
          resumen: resumenDeLaBandeja(f, constanciasNormas),
          incompleto: f.fallidas.length > 0,
          fallo: false,
        });
      } catch {
        // Conserva lo último bueno: un fallo de red no borra un número que sí se tenía.
        if (vivo) setEstado((e) => ({ ...e, fallo: true }));
      }
    }
    void cargar();
    const t = setInterval(() => void cargar(), CADA_MS);
    return () => { vivo = false; clearInterval(t); };
  }, [activo, rol]);

  return estado;
}

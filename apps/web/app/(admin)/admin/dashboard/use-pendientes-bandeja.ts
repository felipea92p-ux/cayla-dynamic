"use client";

import { useEffect, useMemo, useState } from "react";
import { lectorDeLaBandeja, useLecturaBandeja } from "@/lib/admin/bandeja-compartida";
import { resumenDeLaBandeja, type ResumenPendientes } from "@/lib/admin/pendientes-resumen";

// Los pendientes de la Bandeja para el indicador opcional del Dashboard.
//
// SOLO CONSULTA MIENTRAS `activo`: quien deja el Dashboard con solo asistencia
// (el diseño por defecto) no paga ni una petición de esto. El número sale de
// `resumenDeLaBandeja`, que usa `cuentaDeLaBandeja`: la misma cuenta que el
// menú. Antes sumaba cada correo fallido pero no Normas, y el indicador decía
// un número distinto al del menú para lo mismo.
//
// Desde el 2026-11-17 no trae las fuentes por su cuenta: lee del lector que
// comparte con el menú y con /admin/bandeja (`lib/admin/bandeja-compartida.ts`).
// El menú ya las tiene, así que el indicador sale sin otra ronda de consultas,
// y se mueve con cada lectura nueva, la pida quien la pida.
//
// Sigue preguntando cada 5 minutos —no cada 30 s como la asistencia—, pero la
// pregunta es «¿hay una lectura de menos de 5 minutos?»: si el menú leyó hace
// poco, no sale nada hacia la base.

const CADA_MS = 5 * 60_000;

export interface EstadoPendientes {
  resumen: ResumenPendientes | null;
  /** Alguna sección de la Bandeja no respondió: el número puede estar corto. */
  incompleto: boolean;
  /** Ninguna respuesta útil: se dice, no se pinta un cero. */
  fallo: boolean;
}

export function usePendientesBandeja(
  activo: boolean,
  personaId: string | null | undefined,
  rol: string | null | undefined,
): EstadoPendientes {
  const lector = useMemo(() => (activo ? lectorDeLaBandeja(personaId, rol) : null), [activo, personaId, rol]);
  const lectura = useLecturaBandeja(lector);
  const [fallo, setFallo] = useState(false);

  useEffect(() => {
    if (!lector) return;
    let vivo = true;
    const pedir = () => {
      // Conserva lo último bueno: un fallo de red no borra un número que sí se tenía.
      void lector.pedir(Date.now() - CADA_MS).then(
        () => { if (vivo) setFallo(false); },
        () => { if (vivo) setFallo(true); },
      );
    };
    pedir();
    const t = setInterval(pedir, CADA_MS);
    return () => { vivo = false; clearInterval(t); };
  }, [lector]);

  return useMemo(() => ({
    resumen: lectura ? resumenDeLaBandeja(lectura.valor.fuentes, lectura.valor.constanciasNormas) : null,
    incompleto: (lectura?.valor.fuentes.fallidas.length ?? 0) > 0,
    fallo,
  }), [lectura, fallo]);
}

// Lo que se le debe a una persona cesada de periodos ANTERIORES al de su cese.
//
// Viene de `fn_liquidacion_periodos_anteriores` (0565): uno por periodo de
// planilla completo en el que trabajó y que todavía no se le pagó. Es INFORMATIVO:
// ese dinero sale por la planilla de cada periodo, no por la liquidación, y por
// eso aquí no se suma al total de la liquidación — se suma aparte, en
// `resumenPeriodosAnteriores`, solo para decir cuánto se le debe EN TOTAL.
// Sumarlo al monto de la liquidación lo pagaría dos veces.

export interface PeriodoAnterior {
  periodo_id: string;
  fecha_ini: string;
  fecha_fin: string;
  estado: string;
  total: number;
}

const aCentimos = (v: number): number => Math.round(v * 100);

// El rpc devuelve `numeric` como número o como texto según el cliente: se
// normaliza en un solo sitio, y lo que no se entiende se descarta en vez de
// pintar un monto inventado.
export function normalizarPeriodosAnteriores(crudo: unknown): PeriodoAnterior[] {
  if (!Array.isArray(crudo)) return [];
  const filas: PeriodoAnterior[] = [];
  for (const f of crudo) {
    if (!f || typeof f !== "object") continue;
    const r = f as Record<string, unknown>;
    const total = Number(r.total);
    if (typeof r.periodo_id !== "string" || typeof r.fecha_ini !== "string" || typeof r.fecha_fin !== "string") continue;
    if (!Number.isFinite(total) || total <= 0) continue;
    filas.push({
      periodo_id: r.periodo_id,
      fecha_ini: r.fecha_ini,
      fecha_fin: r.fecha_fin,
      estado: typeof r.estado === "string" ? r.estado : "abierto",
      total,
    });
  }
  return filas.sort((a, b) => a.fecha_ini.localeCompare(b.fecha_ini));
}

// Suma en céntimos: 0.1 + 0.2 no puede aparecer como S/ 0.30000000000000004 en
// una pantalla que dice cuánto se le debe a alguien.
export function resumenPeriodosAnteriores(
  filas: readonly PeriodoAnterior[],
  totalLiquidacion: number,
): { suma: number; totalGeneral: number } {
  const suma = filas.reduce((acc, f) => acc + aCentimos(f.total), 0);
  return { suma: suma / 100, totalGeneral: (suma + aCentimos(totalLiquidacion)) / 100 };
}

// El estado del periodo, dicho como lo que le pasa al dinero. `pagado` aparece
// aquí solo cuando el periodo se pagó a OTROS grupos (el pago es por vínculo,
// 0323) y a esta persona todavía no.
export function dondeSePaga(estado: string): string {
  return estado === "pagado"
    ? "El periodo ya se pagó a otros grupos, pero no al suyo: revísalo en Planilla"
    : "Planilla abierta: se paga al cerrar ese periodo";
}

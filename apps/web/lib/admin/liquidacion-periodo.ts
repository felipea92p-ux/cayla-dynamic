/**
 * ¿Existe ya el periodo de planilla que contiene el día del cese?
 *
 * `fn_liquidacion` calcula el sueldo del periodo llamando a la planilla con el
 * periodo QUE CONTIENE el cese. Si ese periodo todavía no se creó —el cese cae
 * el día siguiente al último cierre, mientras el periodo anterior sigue abierto—
 * no inventa uno: devuelve el sueldo del periodo en 0 (0164, «es un dato que
 * falta, no un cero»). La lista de pendientes solo ve el total, así que esa
 * persona aparecía en «Sin nada que cobrar» y alguien podía marcarla pagada con
 * S/ 0.00 teniendo un día trabajado por pagar (Emily Rico y Milagritos Zárate,
 * ceses del 29/10/2026, con el periodo 28/09–28/10 todavía abierto).
 *
 * Las fechas se comparan como texto ISO (`YYYY-MM-DD`): nunca `new Date()`, que
 * puede correr un día por zona horaria, y aquí un día decide si hay periodo.
 */
export interface PeriodoFechas {
  fecha_ini: string;
  fecha_fin: string;
}

export function haySinPeriodoDelCese(fechaCese: string, periodos: readonly PeriodoFechas[]): boolean {
  return !periodos.some((p) => fechaCese >= p.fecha_ini && fechaCese <= p.fecha_fin);
}

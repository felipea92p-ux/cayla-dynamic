// «Pendientes de acción» del Dashboard: el número de la Bandeja, desglosado por
// módulo. Las filas salen de la MISMA lista que pinta /admin/bandeja
// (`armarPendientes`) y el total, de la MISMA cuenta que el menú
// (`cuentaDeLaBandeja`): el menú y el Dashboard dan un solo número. Ese total
// es mayor que las filas por dos señales que no son filas —los correos con
// problema y las constancias de Normas, una cada una—, y van a «otros».
// Aquí solo se agrupa; no se consulta nada.

import {
  armarPendientes, cuentaDeLaBandeja, ETIQUETA_MODULO, MODULOS_BANDEJA,
  type FuentesBandeja, type ModuloBandeja, type Pendiente,
} from "./bandeja-fuentes";

/** A qué pantalla lleva cada módulo. `Record` completo a propósito: si alguien agrega un módulo a la Bandeja, esto no compila hasta que diga a dónde va. */
export const RUTA_MODULO: Record<ModuloBandeja, string> = {
  contratos: "/admin/contratos",
  correcciones: "/admin/correcciones",
  disciplina: "/admin/disciplina",
  documentacion: "/admin/documentacion",
  feriados: "/admin/feriados",
  educacion: "/admin/educacion",
  ausencias: "/admin/ausencias",
  horarios: "/admin/horarios",
  datos_personales: "/admin/datos-personales",
  liquidaciones: "/admin/liquidaciones",
  seguros: "/admin/seguros",
  casos: "/admin/casos",
  // Las pruebas de tres días se atienden en la Bandeja (la líder de equipo no abre Contratos).
  pruebas: "/admin/bandeja",
};

export interface PendientesDeUnModulo {
  clave: ModuloBandeja;
  etiqueta: string;
  ruta: string;
  n: number;
}

export interface ResumenPendientes {
  /** El mismo número del menú (`cuentaDeLaBandeja`): las filas, más 1 si hay correos con problema y 1 si hay constancias de Normas. */
  total: number;
  /** Los módulos con más pendientes, de mayor a menor. */
  porModulo: PendientesDeUnModulo[];
  /** Lo que no entró en `porModulo`: el resto de módulos y las señales de correo y Normas. */
  otros: number;
}

/**
 * `total` es el número oficial de la Bandeja y no se recalcula aquí: si la
 * suma de los módulos no lo alcanza (el correo y Normas no tienen módulo),
 * la diferencia va a `otros` en vez de perderse.
 */
export function resumirPendientes(pendientes: readonly Pick<Pendiente, "modulo">[], total: number, max = 3): ResumenPendientes {
  const cuenta = new Map<ModuloBandeja, number>();
  for (const p of pendientes) cuenta.set(p.modulo, (cuenta.get(p.modulo) ?? 0) + 1);

  const orden = new Map(MODULOS_BANDEJA.map((m, i) => [m.clave, i]));
  const porModulo = [...cuenta.entries()]
    .map(([clave, n]) => ({ clave, etiqueta: ETIQUETA_MODULO[clave], ruta: RUTA_MODULO[clave], n }))
    // Mayor primero; si empatan, el orden en que la Bandeja pinta sus tarjetas.
    .sort((a, b) => b.n - a.n || (orden.get(a.clave) ?? 0) - (orden.get(b.clave) ?? 0))
    .slice(0, Math.max(0, max));

  const mostrados = porModulo.reduce((s, m) => s + m.n, 0);
  return { total, porModulo, otros: Math.max(0, total - mostrados) };
}

/**
 * El resumen del Dashboard, armado con LA cuenta del menú (`cuentaDeLaBandeja`)
 * y la lista que pinta la pantalla. Es el único sitio donde el Dashboard
 * decide su total: el hook solo trae los datos y se lo pasa.
 */
export function resumenDeLaBandeja(f: FuentesBandeja, constanciasNormas: number, max = 3, hoy?: string): ResumenPendientes {
  return resumirPendientes(armarPendientes(f, { hoy }), cuentaDeLaBandeja(f, constanciasNormas, hoy).total, max);
}

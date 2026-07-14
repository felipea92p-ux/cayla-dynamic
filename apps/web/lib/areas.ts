// Áreas de CAYLA — catálogo DINÁMICO (tabla `areas`, migración 0022), editable
// por Felipe en /admin/areas. Este módulo da los tipos, el fallback local (por
// si la RPC fn_areas falla) y helpers. La columna en la base sigue llamándose
// personas.funcion; "Área" es el nombre de cara al usuario.
// Las áreas OPERATIVAS DE SEDE cuentan para la cobertura de tienda en /admin/turnos.

export interface Area {
  codigo: string;
  nombre: string;
  operativa: boolean;
  activa: boolean;
  orden: number;
}

/** Área por defecto del sistema (altas y degradaciones); no se puede desactivar. */
export const AREA_DEFAULT = "calidad_servicio";

/** Respaldo local = el seed de la 0022. Solo se usa si fn_areas() falla. */
export const AREAS_FALLBACK: Area[] = [
  { codigo: "calidad_servicio", nombre: "Calidad & servicio al cliente", operativa: true, activa: true, orden: 1 },
  { codigo: "taller_produccion", nombre: "Taller y producción", operativa: true, activa: true, orden: 2 },
  { codigo: "estrategia_comercial", nombre: "Estrategia comercial", operativa: false, activa: true, orden: 3 },
  { codigo: "desarrollo_organizacional", nombre: "Desarrollo organizacional", operativa: false, activa: true, orden: 4 },
  { codigo: "experiencia_marca", nombre: "Experiencia, marca y comunidad", operativa: false, activa: true, orden: 5 },
  { codigo: "crecimiento_expansion", nombre: "Crecimiento y expansión", operativa: false, activa: true, orden: 6 },
];

/** Convierte el jsonb de fn_areas() en Area[]; ante error/vacío usa el fallback. */
export function parseAreas(data: unknown, error?: unknown): Area[] {
  if (error || !Array.isArray(data) || data.length === 0) return AREAS_FALLBACK;
  return (data as Area[]).map((a) => ({
    codigo: String(a.codigo),
    nombre: String(a.nombre),
    operativa: Boolean(a.operativa),
    activa: Boolean(a.activa),
    orden: Number(a.orden ?? 100),
  }));
}

// Nombres cortos (celdas/badges) para las áreas sembradas; las nuevas usan su nombre.
const CORTOS: Record<string, string> = {
  calidad_servicio: "Calidad & servicio",
  taller_produccion: "Taller y producción",
  estrategia_comercial: "Comercial",
  desarrollo_organizacional: "Desarrollo org.",
  experiencia_marca: "Marca y comunidad",
  crecimiento_expansion: "Expansión",
};

export function areaCorto(areas: Area[], codigo: string): string {
  if (CORTOS[codigo]) return CORTOS[codigo];
  const nombre = areas.find((a) => a.codigo === codigo)?.nombre ?? codigo;
  return nombre.length > 22 ? nombre.slice(0, 21) + "…" : nombre;
}

export function areaNombre(areas: Area[], codigo: string): string {
  return areas.find((a) => a.codigo === codigo)?.nombre ?? codigo;
}

/** ¿Cuenta para la cobertura de tienda? Código desconocido → sí (mejor sobrecontar que ocultar gente). */
export function esOperativaEn(areas: Area[], codigo: string): boolean {
  const a = areas.find((x) => x.codigo === codigo);
  return a ? a.operativa : true;
}

/** Deriva un código-slug desde el nombre ("Logística & envíos" → "logistica_envios"). */
export function slugDeNombre(nombre: string): string {
  return nombre
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 40);
}

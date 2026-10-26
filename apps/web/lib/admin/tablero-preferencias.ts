// Cómo arma cada persona su Dashboard: qué paneles ve, en qué orden, cuáles
// tiene colapsados y qué indicadores extra agregó. Solo lógica: sin React ni
// Supabase, para poder probarla con vitest.
//
// QUÉ PROMETE
//   Que lo guardado en el navegador nunca rompa la pantalla. Lo que llega de
//   `useFiltroGuardado` es JSON de una versión vieja, a medias o dañado, así
//   que TODO pasa por `normalizarPreferencias`, que siempre devuelve un valor
//   completo y válido.
//
// POR QUÉ MEMOS Y CONTRATOS NO SE PUEDEN OCULTAR (decisión de Felipe,
// 2026-09-19): solo colapsan. Un contrato a plazo fijo que ya venció y sigue
// figurando activo se vuelve indefinido solo (art. 77 del D.S. 003-97-TR), y
// esa franja es la única pantalla donde se ve. Un panel escondido por error
// sería un plazo legal corriendo sin que nadie lo mire. Se hace cumplir aquí
// y no en la pantalla, para que un valor guardado antes tampoco lo oculte.
//
// DÓNDE SE GUARDA: en el navegador de cada persona (`useFiltroGuardado`), como
// «equipo colapsado» de Correcciones. Cambiar de navegador vuelve al diseño
// por defecto; no hay migración ni tabla nueva.

export const PANELES = ["resumen", "sedes", "memos", "contratos"] as const;
export type PanelId = (typeof PANELES)[number];

/** Paneles que solo colapsan: ver el comentario de arriba. */
export const PANELES_NO_OCULTABLES: readonly PanelId[] = ["memos", "contratos"];

/** Indicadores que se pueden agregar al resumen. La asistencia siempre está. */
export const KPIS_EXTRA = ["pendientes", "personal", "casos"] as const;
export type KpiExtra = (typeof KPIS_EXTRA)[number];

export interface PreferenciasTablero {
  orden: PanelId[];
  ocultos: Partial<Record<PanelId, boolean>>;
  colapsados: Partial<Record<PanelId, boolean>>;
  kpisExtra: Partial<Record<KpiExtra, boolean>>;
  /** El panel lateral de alertas oculto del todo (el contador sigue en el encabezado). */
  alertasOcultas: boolean;
}

export const PREFERENCIAS_INICIALES: PreferenciasTablero = {
  orden: [...PANELES],
  ocultos: {},
  colapsados: {},
  kpisExtra: {},
  alertasOcultas: false,
};

const esPanel = (x: unknown): x is PanelId => (PANELES as readonly unknown[]).includes(x);
const esKpiExtra = (x: unknown): x is KpiExtra => (KPIS_EXTRA as readonly unknown[]).includes(x);
const esObjeto = (x: unknown): x is Record<string, unknown> => typeof x === "object" && x !== null && !Array.isArray(x);

/** Deja solo las claves conocidas cuyo valor es exactamente `true`. */
function soloVerdaderos<K extends string>(crudo: unknown, valida: (k: unknown) => k is K): Partial<Record<K, boolean>> {
  const salida: Partial<Record<K, boolean>> = {};
  if (!esObjeto(crudo)) return salida;
  for (const [k, v] of Object.entries(crudo)) if (valida(k) && v === true) salida[k] = true;
  return salida;
}

/**
 * Convierte lo que haya en el almacenamiento en preferencias válidas. Total:
 * nunca lanza. Un panel desconocido se descarta, uno que falta se agrega al
 * final (así un panel nuevo aparece solo), y los que no se pueden ocultar se
 * fuerzan visibles.
 */
export function normalizarPreferencias(crudo: unknown): PreferenciasTablero {
  if (!esObjeto(crudo)) return structuredClone(PREFERENCIAS_INICIALES);

  const vistos = new Set<PanelId>();
  const orden: PanelId[] = [];
  if (Array.isArray(crudo.orden)) {
    for (const p of crudo.orden) if (esPanel(p) && !vistos.has(p)) { vistos.add(p); orden.push(p); }
  }
  for (const p of PANELES) if (!vistos.has(p)) orden.push(p);

  const ocultos = soloVerdaderos(crudo.ocultos, esPanel);
  for (const p of PANELES_NO_OCULTABLES) delete ocultos[p];

  return {
    orden,
    ocultos,
    colapsados: soloVerdaderos(crudo.colapsados, esPanel),
    kpisExtra: soloVerdaderos(crudo.kpisExtra, esKpiExtra),
    alertasOcultas: crudo.alertasOcultas === true,
  };
}

/** Sube (-1) o baja (+1) un panel una posición. En el borde no hace nada. */
export function moverPanel(p: PreferenciasTablero, id: PanelId, direccion: -1 | 1): PreferenciasTablero {
  const i = p.orden.indexOf(id);
  const j = i + direccion;
  if (i < 0 || j < 0 || j >= p.orden.length) return p;
  const orden = [...p.orden];
  [orden[i], orden[j]] = [orden[j], orden[i]];
  return { ...p, orden };
}

/** Oculta o muestra un panel. Los no ocultables se devuelven tal cual. */
export function alternarOculto(p: PreferenciasTablero, id: PanelId): PreferenciasTablero {
  if (PANELES_NO_OCULTABLES.includes(id)) return p;
  const ocultos = { ...p.ocultos };
  if (ocultos[id]) delete ocultos[id]; else ocultos[id] = true;
  return { ...p, ocultos };
}

export function alternarColapsado(p: PreferenciasTablero, id: PanelId): PreferenciasTablero {
  const colapsados = { ...p.colapsados };
  if (colapsados[id]) delete colapsados[id]; else colapsados[id] = true;
  return { ...p, colapsados };
}

export function alternarKpiExtra(p: PreferenciasTablero, k: KpiExtra): PreferenciasTablero {
  const kpisExtra = { ...p.kpisExtra };
  if (kpisExtra[k]) delete kpisExtra[k]; else kpisExtra[k] = true;
  return { ...p, kpisExtra };
}

export function alternarAlertas(p: PreferenciasTablero): PreferenciasTablero {
  return { ...p, alertasOcultas: !p.alertasOcultas };
}

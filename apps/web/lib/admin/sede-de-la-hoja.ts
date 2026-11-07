// ============================================================================
// sede-de-la-hoja.ts — qué sedes ofrece la Hoja de sede y cuál abre
// ============================================================================
// QUÉ PROMETE · dadas las sedes activas, quién entra y el `?sede=` de la
//               dirección, decir qué sedes se ofrecen y cuál se abre. Quien ve
//               solo su sede abre la suya y no se le ofrece otra. Cuando no se
//               puede abrir ninguna, dice por qué.
// QUÉ ASUME   · que `veTodas` sale de `puedeVerTodasLasSedes` (permisos.ts) y
//               `sedeBaseId` de la ficha de quien entra (`usePersonaActual`), y
//               que la lista ya viene solo con sedes activas y ordenada.
//
// POR QUÉ EXISTE (2026-11-07). El menú abre la Hoja de sede sin `?sede=`, y la
// pantalla tomaba la primera sede por código: AQP. Una líder de equipo de TRU o
// de LIM veía Arequipa, y como sus permisos solo le muestran a su gente, la hoja
// salía vacía: «Sin gente asignada a esta sede» y, en «Necesita atención», «Nada
// pendiente en disciplina. Buena señal.». Una tranquilidad falsa sobre un equipo
// que no era el suyo, en un papel que se imprime y se firma.
//
// La forma es la que ya tiene Turnos: DO elige entre todas, y la líder ve la
// suya, sin selector. Ofrecerle las otras tres era ofrecerle tres hojas vacías.
// ============================================================================

export interface SedeElegible {
  id: string;
  codigo: string;
}

export interface QuienEntra {
  /** `puedeVerTodasLasSedes(rol)`: DO y la dirección. */
  veTodas: boolean;
  sedeBaseId: string | null;
}

/** Por qué no se abre ninguna hoja. Cada motivo tiene su frase: «ese código no existe» no es lo mismo que «esa sede no es la tuya». */
export type MotivoSinHoja =
  /** La dirección pedía un código que no está entre las activas. */
  | "no-existe"
  /** La dirección pedía otra sede y quien entra solo ve la suya. */
  | "no-es-tuya"
  /** Quien ve todas, y no hay ninguna activa. */
  | "ninguna-activa"
  /** Quien ve solo la suya, y la suya no está activa (o no tiene). */
  | "sin-sede-propia";

export type SedeDeLaHoja<S extends SedeElegible> =
  | { sedes: S[]; abre: S; sinHoja: null }
  | { sedes: S[]; abre: null; sinHoja: { motivo: MotivoSinHoja; codigo: string | null } };

export function sedeDeLaHoja<S extends SedeElegible>(activas: S[], quien: QuienEntra, pedida: string | null): SedeDeLaHoja<S> {
  const codigo = pedida?.trim().toUpperCase() || null;
  const sedes = quien.veTodas ? activas : activas.filter((s) => s.id === quien.sedeBaseId);

  if (codigo) {
    const abre = sedes.find((s) => s.codigo === codigo);
    if (abre) return { sedes, abre, sinHoja: null };
    // Nunca se contesta con otra sede: la dirección pedía una concreta, y el papel lleva su nombre.
    const existe = activas.some((s) => s.codigo === codigo);
    return { sedes, abre: null, sinHoja: { motivo: existe ? "no-es-tuya" : "no-existe", codigo } };
  }

  const abre = sedes[0];
  if (abre) return { sedes, abre, sinHoja: null };
  return { sedes, abre: null, sinHoja: { motivo: quien.veTodas ? "ninguna-activa" : "sin-sede-propia", codigo: null } };
}

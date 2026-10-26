// El filtro de «Cuentas del equipo»: sede y texto, sobre lo que ya está cargado.
// Son ~30 personas; no hay nada que pedirle a la base.
//
// El texto busca en el nombre Y en el correo: quien abre esta pantalla muchas veces
// llega con un correo en la mano («¿de quién es caylaperu@…?») y no con un nombre.
// Se compara sin tildes ni mayúsculas, y por palabras sueltas: «flores chiara» encuentra
// a «Chiara Flores».

import { sinTildes } from "./sin-tildes";

export interface CuentaFiltrable {
  nombre: string;
  sede: string;
  email: string | null;
}

/**
 * Las sedes que de verdad aparecen entre las cuentas, ordenadas. Salen de los datos y no
 * de una lista escrita a mano: la verdad vive en la tabla `sedes` (ya hubo un
 * `["TRU","LIM","AQP"]` que se volvió falso el día que abrió Central).
 */
export function sedesDe(cuentas: readonly { sede: string }[]): string[] {
  return [...new Set(cuentas.map((c) => c.sede))].sort();
}

/** `sede: null` es «todas». */
export function filtrarCuentas<T extends CuentaFiltrable>(
  cuentas: readonly T[],
  { busca, sede }: { busca: string; sede: string | null },
): T[] {
  const palabras = sinTildes(busca).split(/\s+/).filter(Boolean);
  return cuentas.filter((c) => {
    if (sede !== null && c.sede !== sede) return false;
    if (palabras.length === 0) return true;
    const texto = sinTildes(`${c.nombre} ${c.email ?? ""}`);
    return palabras.every((p) => texto.includes(p));
  });
}

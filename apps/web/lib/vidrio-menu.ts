// ============================================================================
// El menú con vidrio, como datos: filas sueltas y módulos que se abren.
// ============================================================================
//
// QUÉ PROMETE
//   De los grupos que ya existen (`GRUPOS` del panel, `GRUPOS_MIO` de Lo mío) arma las filas del menú: lo que no tiene título queda
//   suelto arriba y cada grupo con título pasa a ser un módulo. Dice en qué módulo está una pantalla y cuánto suman sus números.
//
// QUÉ ASUME
//   Que quien llama ya filtró por rol. Aquí no se vuelve a decidir quién ve qué: el rediseño cambia cómo se dibuja el menú, no lo que
//   cada persona puede abrir.
//
// POR QUÉ UN TIPO PROPIO
//   El panel navega con direcciones y Lo mío cambia de sección sin salir de la pantalla. Una hoja con `href` es un enlace; sin él, un
//   botón. Con eso, un solo menú sirve a los dos y no hay dos dibujos que se separen.
//
// Sin React ni navegador, para probarlo con vitest (tests/vidrio-menu.test.ts).
// ============================================================================

import type { LucideIcon } from "lucide-react";

export type HojaMenu = {
  id: string;
  etiqueta: string;
  /** Lo que dice bajo el ícono con el menú plegado, si `etiqueta` no cabe en 84 px. Solo importa en una fila suelta. */
  corto?: string;
  Icon: LucideIcon;
  href?: string;
  /** Cuántas cosas esperan aquí. En 0 no se dibuja nada. */
  n: number;
  /** Qué significa ese número, con todas las palabras. */
  titulo?: string;
};

export type ModuloMenu = {
  id: string;
  etiqueta: string;
  corto?: string;
  Icon: LucideIcon;
  hojas: readonly HojaMenu[];
};

export type FilaMenu = HojaMenu | ModuloMenu;

export type GrupoDeMenu = {
  label?: string;
  corto?: string;
  Icon?: LucideIcon;
  hojas: readonly HojaMenu[];
};

export const esModulo = (f: FilaMenu): f is ModuloMenu => "hojas" in f;

/** Sin título, sueltas y en su lugar; con título, un módulo. Un grupo sin hojas no dibuja nada. */
export function armarFilas(grupos: readonly GrupoDeMenu[]): FilaMenu[] {
  return grupos
    .filter((g) => g.hojas.length > 0)
    .flatMap((g): FilaMenu[] =>
      g.label
        ? [{ id: g.label, etiqueta: g.label, corto: g.corto, Icon: g.Icon ?? g.hojas[0].Icon, hojas: g.hojas }]
        : [...g.hojas],
    );
}

/** El módulo donde vive esa hoja, o null si está suelta o no aparece en este menú. */
export function moduloDeLaHoja(filas: readonly FilaMenu[], hoja: string | null): string | null {
  if (hoja === null) return null;
  return filas.find((f) => esModulo(f) && f.hojas.some((h) => h.id === hoja))?.id ?? null;
}

export function sumaDelModulo(m: ModuloMenu): number {
  return m.hojas.reduce((suma, h) => suma + h.n, 0);
}

/**
 * Qué dice un módulo cerrado sobre su número. `nota` existe porque en el panel ese número ya está contado en Bandeja, y dos números
 * que parecen sumarse sin que nada lo aclare se leen como un error.
 */
export function tituloDelModulo(m: ModuloMenu, nota?: string): string | undefined {
  const suma = sumaDelModulo(m);
  if (suma === 0) return undefined;
  return `${suma} por atender en ${m.etiqueta}${nota ? `. ${nota}` : ""}`;
}

/**
 * Qué fila lleva la marca de «estás aquí». Es la hoja, salvo que su módulo esté cerrado: una marca escondida no le dice nada a nadie,
 * así que sube a la fila del módulo.
 */
export function claveDeLaActiva(filas: readonly FilaMenu[], hoja: string | null, moduloAbierto: string | null): string | null {
  if (hoja === null) return null;
  const modulo = moduloDeLaHoja(filas, hoja);
  if (modulo !== null) return modulo === moduloAbierto ? `h:${hoja}` : `m:${modulo}`;
  return filas.some((f) => f.id === hoja) ? `h:${hoja}` : null;
}

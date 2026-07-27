// El estado de carga de Dynamic, en un solo lugar.
//
// Hasta el 27-07-2026 esto vivía copiado a mano en cada pantalla: cuatro tenían
// el colibrí aleteando y el resto un "Cargando…" en texto plano. La misma
// espera se veía de dos formas distintas según en qué pantalla estuvieras, y
// nadie lo notaba porque cada archivo, por separado, parecía correcto.
//
// El colibrí que aletea no es decoración: le dice a quien mira que el sistema
// está trabajando y no colgado. Un texto quieto no distingue una cosa de la
// otra. Y `prefers-reduced-motion` ya apaga la animación para quien la tenga
// desactivada (globals.css), así que el aleteo no molesta a nadie.

/** Carga a pantalla o sección completa. El caso normal. */
export function Cargando({ texto = "Cargando…" }: { texto?: string }) {
  return (
    <div className="flex flex-col items-center gap-4 py-20 text-taupe" role="status" aria-live="polite">
      <span className="colibri aletea w-12 text-rojo/70" aria-hidden />
      <span className="text-sm">{texto}</span>
    </div>
  );
}

/** Carga dentro de una tabla: ocupa toda la fila para no romper las columnas. */
export function CargandoFila({ columnas, texto = "Cargando…" }: { columnas: number; texto?: string }) {
  return (
    <tr>
      <td colSpan={columnas} className="px-4 py-10">
        <Cargando texto={texto} />
      </td>
    </tr>
  );
}

/**
 * Cuando no hay nada que mostrar. Distinto de la carga: acá el sistema YA
 * respondió y la respuesta es "no hay". Confundir las dos deja a la persona
 * esperando algo que nunca va a llegar.
 *
 * `pista` es lo que puede hacer al respecto. Sin eso, un estado vacío solo
 * informa; con eso, enseña a usar la pantalla.
 */
export function SinDatos({ texto, pista }: { texto: string; pista?: string }) {
  return (
    <div className="flex flex-col items-center gap-2 py-16 text-center" role="status">
      <span className="colibri w-10 text-sand" aria-hidden />
      <p className="text-sm text-taupe">{texto}</p>
      {pista && <p className="max-w-sm text-xs text-taupe">{pista}</p>}
    </div>
  );
}

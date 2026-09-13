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

/**
 * Carga a pantalla o sección completa. El caso normal.
 *
 * `clase` es el tamaño del texto, y existe por una sola pantalla: el terminal
 * de marcaje, que se mira de pie a un metro de una Mac mini a pantalla
 * completa. Ahí `text-sm` —14 px— no se lee, y la alternativa era copiar el
 * colibrí en el terminal: justo la duplicación que el comentario de arriba
 * cuenta haber tardado meses en deshacer. El valor por defecto es el de
 * siempre, así que ninguna de las pantallas que ya lo usan cambia.
 */
export function Cargando({ texto = "Cargando…", clase = "text-sm" }: { texto?: string; clase?: string }) {
  return (
    <div className="flex flex-col items-center gap-4 py-20 text-taupe" role="status" aria-live="polite">
      <span className="colibri aletea w-12 text-rojo/70" aria-hidden />
      <span className={clase}>{texto}</span>
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

/** El bloque que "respira" mientras carga — la pieza de los esqueletos de abajo. */
function Hueso({ className = "" }: { className?: string }) {
  return <span aria-hidden className={`pulso-carga inline-block rounded bg-sand/70 ${className}`} />;
}

/**
 * El esqueleto de una tabla: la forma de la tabla final, sin sus datos. Para
 * las pantallas donde `<Cargando/>` reemplazaba TODA la tabla por un colibrí
 * solo —Equipo, Desempeño— y la persona perdía de vista dónde iba a aparecer
 * lo que espera, sobre todo si ya conoce la pantalla y sabe qué columna mirar.
 *
 * `anchos` es un ancho de Tailwind por columna (p. ej. `["w-32","w-16"]`):
 * columnas angostas como "Estado" no tienen por qué respirar tan ancho como
 * "Nombre". `franjaFinal` es para Desempeño, la única tabla con una franja de
 * cuadritos —uno por día— después de sus columnas normales.
 */
export function EsqueletoTabla({
  anchos,
  filas = 8,
  franjaFinal,
}: {
  anchos: string[];
  filas?: number;
  franjaFinal?: number;
}) {
  return (
    <div role="status" aria-label="Cargando" className="overflow-hidden rounded-superficie border border-sand bg-papel">
      <table className="w-full text-sm">
        <thead>
          {/* Misma franja que TablaEncabezado (bg-sand/70), sin texto: la
              silueta del esqueleto tiene que incluir el encabezado, porque
              es justo la parte de la tabla real que más se reconoce de un
              vistazo. */}
          <tr className="bg-sand/70">
            {anchos.map((_, j) => (
              <th key={j} className="px-4 py-2" />
            ))}
            {franjaFinal !== undefined && <th className="px-3 py-2" />}
          </tr>
        </thead>
        <tbody>
          {Array.from({ length: filas }).map((_, i) => (
            <tr key={i} className={i > 0 ? "border-t border-sand" : ""}>
              {anchos.map((ancho, j) => (
                <td key={j} className="px-4 py-3"><Hueso className={`h-3.5 ${ancho}`} /></td>
              ))}
              {franjaFinal !== undefined && (
                <td className="px-3 py-3">
                  <div className="flex gap-[3px]">
                    {Array.from({ length: franjaFinal }).map((_, k) => (
                      <Hueso key={k} className="h-4 w-[14px] shrink-0" />
                    ))}
                  </div>
                </td>
              )}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/** Varias `EsqueletoTabla`, cada una con su título — para las pantallas que
 * agrupan su lista en secciones (Incidencias, una por sede). */
export function EsqueletoSecciones({
  secciones = 2,
  anchos,
  filas = 3,
}: {
  secciones?: number;
  anchos: string[];
  filas?: number;
}) {
  return (
    <div role="status" aria-label="Cargando" className="flex flex-col gap-8">
      {Array.from({ length: secciones }).map((_, s) => (
        <div key={s}>
          <Hueso className="mb-3 h-5 w-40" />
          <EsqueletoTabla anchos={anchos} filas={filas} />
        </div>
      ))}
    </div>
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
      {/* text-sand daba 1.16:1 en claro y 1.29:1 en oscuro — invisible contra
          el piso de 3:1 para un gráfico no textual. text-taupe/50 sí lo pasa
          en los dos temas y mantiene el colibrí quieto como par visual del
          que aletea en <Cargando/>. */}
      <span className="colibri w-10 text-taupe/50" aria-hidden />
      <p className="text-sm text-taupe">{texto}</p>
      {pista && <p className="max-w-sm text-xs text-taupe">{pista}</p>}
    </div>
  );
}

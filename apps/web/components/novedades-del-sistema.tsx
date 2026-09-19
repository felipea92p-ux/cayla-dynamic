// ============================================================================
// Novedades del sistema — la sección de /admin/anuncios que cuenta qué mejoró.
// ============================================================================
//
// Va APARTE de los comunicados de DO, con su propio título y su propia
// etiqueta en cada tarjeta («Novedad del sistema»): un comunicado es la voz de
// la empresa, firmado por una persona, con fecha límite a veces; una novedad
// es la voz del sistema, sin firma y sin nada que hacer. Mezclarlas en una sola
// lista haría que las novedades parezcan órdenes, o que los comunicados se
// pierdan entre novedades.
//
// De dónde salen las entradas, y qué va y qué no va en ellas: ver el
// encabezado de `lib/novedades.ts`.
// ============================================================================

import { Insignia } from "@/components/ui/insignia";
import { hoyLima, type AudienciaNovedad } from "@cayla-dynamic/shared";
import { esNovedadNueva, fechaDeNovedad, novedadesPara, type Novedad } from "@/lib/novedades";

/** Cuántas se ven de entrada; el resto queda plegado, como los anuncios anulados. */
const VISIBLES = 6;

const ETIQUETA_AUDIENCIA: Record<AudienciaNovedad, string> = {
  todos: "Para todo el equipo",
  panel: "Para líderes de equipo y DO",
  do: "Solo para DO",
};

function Tarjeta({ n, nueva }: { n: Novedad; nueva: boolean }) {
  return (
    <li className="rounded-2xl border border-sand bg-papel p-4">
      {/* La insignia va FUERA del <h3>: dentro heredaba la serif del título. */}
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
        <h3 className="font-serif text-lg text-tinta">{n.titulo}</h3>
        {nueva && <Insignia variante="informativo">Nueva</Insignia>}
      </div>
      <p className="mt-2 whitespace-pre-wrap text-sm text-tinta">{n.queMejoro}</p>
      <div className="mt-3 flex flex-wrap items-center justify-between gap-2 border-t border-sand/70 pt-3 text-xs text-taupe">
        <span>Novedad del sistema · {fechaDeNovedad(n.fecha)}</span>
        <span>{ETIQUETA_AUDIENCIA[n.audiencia]}</span>
      </div>
    </li>
  );
}

export function NovedadesDelSistema({ rol }: { rol: string | null | undefined }) {
  const lista = novedadesPara(rol);
  const hoy = hoyLima();
  if (lista.length === 0) return null;

  const recientes = lista.slice(0, VISIBLES);
  const anteriores = lista.slice(VISIBLES);

  return (
    <section aria-labelledby="novedades-titulo" className="mt-10">
      <h2 id="novedades-titulo" className="font-serif text-xl text-tinta">Novedades del sistema</h2>
      <p className="mb-4 mt-1 text-sm text-taupe">
        Lo que mejora en Dynamic, explicado para quien lo usa. Cada vez que el sistema cambia en algo que se nota, queda escrito aquí.
      </p>

      <ul className="space-y-3">
        {recientes.map((n) => <Tarjeta key={n.id} n={n} nueva={esNovedadNueva(n, hoy)} />)}
      </ul>

      {anteriores.length > 0 && (
        <details className="mt-4">
          <summary className="cursor-pointer text-sm text-taupe">Anteriores ({anteriores.length})</summary>
          <ul className="mt-3 space-y-3">
            {anteriores.map((n) => <Tarjeta key={n.id} n={n} nueva={esNovedadNueva(n, hoy)} />)}
          </ul>
        </details>
      )}
    </section>
  );
}

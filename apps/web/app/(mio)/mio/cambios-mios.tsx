"use client";

import { useEffect, useState } from "react";
import { ChevronDown } from "lucide-react";
import type { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { TZ_LIMA } from "@cayla-dynamic/shared";
import { Boton } from "@/components/ui/boton";
import { describirCambio, type Auditoria } from "@/lib/admin/historial-correcciones";

/**
 * «Cambios a tu registro», en la pestaña Historial de /mio.
 *
 * QUÉ PROMETE · mostrarle a la persona, de a 10 y de la más reciente a la más
 *               vieja, TODO lo que alguien cambió en su registro y por qué —
 *               traducido con el mismo `describirCambio` que usa Correcciones
 *               en el panel, para que ella y su líder lean la misma frase.
 * QUÉ ASUME   · `auditoria_select_propia` (0003) le deja leer sus filas de
 *               `correcciones_auditoria`; nada más.
 *
 * Plegado por defecto: es lo que ya pasó y está resuelto, se consulta de vez
 * en cuando. El título dice cuántos hay para que sepa si vale la pena abrirlo.
 *
 * Pide su propia página a la base en vez de recibir la lista: antes /mio traía
 * las 20 más recientes y la 21 no existía para ella. Con `range` + `count` no
 * hay tope, y cada página son 10 filas sin importar cuántos años de historial
 * se junten.
 *
 * Si la consulta falla, lo dice — un «nadie corrigió nada» falso sería mentirle
 * sobre su propio registro.
 */

const POR_PAGINA = 10;

type Fila = Auditoria;

function fechaYHora(iso: string): string {
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA, day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", hour12: true,
  }).format(new Date(iso));
}

export function CambiosMios({
  supabase, personaId,
}: {
  supabase: ReturnType<typeof createAdminSupabaseClient>;
  personaId: string;
}) {
  const [pagina, setPagina] = useState(0);
  const [filas, setFilas] = useState<Fila[] | null>(null);
  const [total, setTotal] = useState<number | null>(null);
  const [error, setError] = useState(false);

  // La consulta vive dentro del efecto y no en un callback aparte: así `vivo`
  // descarta la respuesta de una página que ya no es la que se está mirando
  // (dos clics seguidos en «Siguiente» con la red lenta no pueden dejar en
  // pantalla la página 2 después de haber pedido la 3).
  useEffect(() => {
    let vivo = true;
    void (async () => {
      const desde = pagina * POR_PAGINA;
      const { data, count, error: err } = await supabase
        .from("correcciones_auditoria")
        .select("id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_at, corregido_por", { count: "exact" })
        .eq("persona_id", personaId)        // ← explícito, como todo lo de /mio
        .order("corregido_at", { ascending: false })
        // Desempate: una migración que toca a varias personas escribe todas sus
        // filas con el mismo `now()`. Sin esto, entre páginas una fila podría
        // salir dos veces y otra ninguna.
        .order("id", { ascending: false })
        .range(desde, desde + POR_PAGINA - 1);
      if (!vivo) return;
      if (err) { setError(true); return; }
      setError(false);
      setFilas((data as Fila[] | null) ?? []);
      setTotal(count ?? 0);
    })();
    return () => { vivo = false; };
  }, [supabase, personaId, pagina]);

  const paginas = total ? Math.ceil(total / POR_PAGINA) : 0;
  const primera = pagina * POR_PAGINA + 1;
  const ultima = Math.min((pagina + 1) * POR_PAGINA, total ?? 0);

  return (
    <details data-tour="mio-historial-cambios" className="group rounded-2xl border border-sand text-sm">
      <summary className="flex cursor-pointer list-none items-center justify-between gap-3 p-5 [&::-webkit-details-marker]:hidden">
        <span className="min-w-0">
          <span className="block font-serif text-lg">Cambios a tu registro</span>
          <span className="block text-taupe">
            {error ? "No se pudieron cargar."
              : total === null ? "Cargando…"
              : total === 0 ? "Nadie ha cambiado nada de tu registro."
              : total === 1 ? "1 cambio anotado" : `${total} cambios anotados`}
          </span>
        </span>
        <ChevronDown aria-hidden className="size-5 shrink-0 text-taupe transition-transform group-open:rotate-180" />
      </summary>

      <div className="border-t border-sand px-5 pb-5 pt-4">
        <p className="mb-3 text-taupe">
          Cuando alguien corrige un marcaje tuyo, tu horario u otro dato de tu registro, queda anotado acá con el
          motivo.
        </p>

        {error ? (
          <p className="text-rojo">
            No se pudieron cargar tus cambios. Vuelve a intentarlo en un rato; si sigue, avisa a tu líder de equipo.
          </p>
        ) : filas === null ? null : filas.length === 0 ? (
          <p className="text-taupe">Nadie ha cambiado nada de tu registro.</p>
        ) : (
          <>
            <ul className="space-y-3">
              {filas.map((c) => {
                const { accion, cuando, detalle } = describirCambio(c);
                return (
                  <li key={c.id} className="border-t border-sand pt-3 first:border-t-0 first:pt-0">
                    <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-0.5">
                      <span className="font-medium">
                        {accion}
                        {cuando && <span className="font-normal text-taupe"> · del {cuando}</span>}
                      </span>
                      <span className="text-xs text-taupe">{fechaYHora(c.corregido_at)}</span>
                    </div>
                    <p className="break-words text-taupe">{detalle}</p>
                    <p className="mt-0.5 break-words italic">«{c.motivo}»</p>
                  </li>
                );
              })}
            </ul>

            {paginas > 1 && (
              <nav aria-label="Páginas de cambios" className="mt-4 flex items-center justify-between gap-2 border-t border-sand pt-3">
                <Boton variante="secundario" tamano="sm" disabled={pagina === 0}
                  onClick={() => setPagina((p) => p - 1)}>
                  ← Anterior
                </Boton>
                <span className="whitespace-nowrap text-xs text-taupe">{primera}–{ultima} de {total}</span>
                <Boton variante="secundario" tamano="sm" disabled={pagina >= paginas - 1}
                  onClick={() => setPagina((p) => p + 1)}>
                  Siguiente →
                </Boton>
              </nav>
            )}
          </>
        )}
      </div>
    </details>
  );
}

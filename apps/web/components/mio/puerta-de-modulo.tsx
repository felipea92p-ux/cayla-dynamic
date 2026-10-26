"use client";

// ============================================================================
// puerta-de-modulo.tsx — los términos que van antes de la guía en «Lo mío»
// ============================================================================
// Dibuja UNA capa de términos cuando `usePuertaDeModulo` dice que toca: los
// términos de uso (la primera vez, antes de cualquier módulo) o los del módulo.
// La guía NO se dibuja aquí: la lanza el motor de `useRecorridoGuiado` cuando
// `puerta.capa` vale «guia». Aquí solo está lo que la precede.
//
// QUÉ SE VE (maqueta: docs/terminos-y-guia-mio-prototipo-2026-10-19.html)
//   · Con casilla (`aceptacion`): no se cierra con Escape ni con un clic afuera,
//     y «Aceptar y continuar» no se activa hasta marcarla. «Ahora no» saca a la
//     persona del módulo —de vuelta a Resumen—, no la deja verlo sin aceptar.
//     Los términos de uso no tienen «Ahora no»: son la puerta de entrada.
//   · Aviso (`aviso` y `constancia_propia`): «Entendido» lo recuerda en este
//     navegador; «Ahora no» o cerrarlo solo lo guarda para esta visita.
//
// HOY NO SE VE NADA: con todos los textos en borrador `puerta.terminos` es
// siempre `null` y esto no dibuja nada (ver `terminos.ts`).
// ============================================================================

import { useState } from "react";
import { Modal } from "@/components/ui/modal";
import { Boton } from "@/components/ui/boton";
import { Rotulo } from "@/components/ui/rotulo";
import type { TerminosModulo } from "@cayla-dynamic/shared";
import type { PuertaDeModulo } from "@/lib/use-puerta-de-modulo";
import { claveDeTerminos } from "@/lib/terminos-mios";

export function PuertaDeModuloVista({ puerta, onSalir }: {
  puerta: PuertaDeModulo;
  /** A dónde va quien dice «Ahora no» a un módulo que exige aceptar (Resumen). */
  onSalir: () => void;
}) {
  const t = puerta.terminos;
  if (!t || (puerta.capa !== "terminos_de_uso" && puerta.capa !== "terminos_del_modulo")) return null;
  // La `key` reinicia la casilla al pasar de unos términos a otros.
  return <HojaDeTerminos key={claveDeTerminos(t)} t={t} puerta={puerta} onSalir={onSalir} />;
}

function HojaDeTerminos({ t, puerta, onSalir }: { t: TerminosModulo; puerta: PuertaDeModulo; onSalir: () => void }) {
  const [marcada, setMarcada] = useState(false);
  const esUso = t.modulo === "general";
  const exige = t.peso === "aceptacion";

  const rotulo = esUso ? "Antes de empezar" : "Antes de entrar a este módulo";

  return (
    <Modal
      abierto
      titulo={t.titulo}
      ancho="lg"
      bloqueado={exige}
      onCerrar={() => puerta.postergar(t)}
    >
      <Rotulo className="-mt-2 mb-3">
        {rotulo}{exige ? " · con aceptación" : ""}
      </Rotulo>

      <ol className="mb-4 list-decimal space-y-2 pl-5 text-sm text-tinta">
        {t.puntos.map((p) => <li key={p}>{p}</li>)}
      </ol>

      {t.peso === "constancia_propia" && t.apuntaA && (
        <p className="mb-4 text-sm text-taupe">
          Lo que dejas por escrito es {t.apuntaA}. Este aviso no te pide aceptar nada más.
        </p>
      )}

      <details className="mb-4 rounded-control border border-sand bg-crema px-3 py-2 text-sm">
        <summary className="cursor-pointer font-medium text-taupe">Ver el texto completo</summary>
        <p className="mt-2 text-tinta">{t.texto}</p>
        <p className="mt-2 text-xs text-taupe">Versión {t.version}</p>
      </details>

      {exige && (
        <label className="mb-4 flex cursor-pointer items-start gap-3 rounded-control border border-borde-control px-3 py-2.5 text-sm text-tinta">
          <input
            type="checkbox"
            checked={marcada}
            onChange={(e) => setMarcada(e.target.checked)}
            className="mt-0.5 size-5 shrink-0 accent-tinta"
          />
          <span>He leído y acepto{esUso ? " los términos de uso." : " lo de este módulo."}</span>
        </label>
      )}

      {puerta.error && <p role="alert" className="mb-3 text-sm text-rojo">{puerta.error}</p>}

      <div className="flex flex-wrap items-center justify-end gap-2">
        {!esUso && (
          <Boton variante="enlace" onClick={() => (exige ? onSalir() : puerta.postergar(t))}>
            Ahora no
          </Boton>
        )}
        {exige ? (
          <Boton
            variante="primario"
            tamano="lg"
            disabled={!marcada}
            cargando={puerta.enviando}
            onClick={() => { void puerta.aceptar(t); }}
          >
            Aceptar y continuar
          </Boton>
        ) : (
          <Boton variante="primario" tamano="lg" onClick={() => puerta.entendido(t)}>
            Entendido
          </Boton>
        )}
      </div>
    </Modal>
  );
}

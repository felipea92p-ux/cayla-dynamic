"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { Cake } from "lucide-react";
import { puedePedirBono, type MiBono } from "@/lib/mi-bono";
import { formatSoles } from "@/lib/rangos";
import { SALUDOS_CUMPLEANOS, SALUDO_CADA_MS, saludoInicial } from "@/lib/saludos-cumpleanos";

/**
 * El saludo del mes de cumpleaños, arriba de todo en Info (solo el acuse va antes).
 *
 * Quien lo monta decide CUÁNDO (`esMesDeCumpleanos`); esto solo decide qué se
 * dice. El saludo es para todo el mundo; el botón de firmar, solo para quien la
 * base dice que puede pedirlo (`puedePedirBono`, la misma condición que exige
 * `fn_confirmar_mi_bono_cumpleanos`). Nunca un botón que va a fallar.
 *
 * El mensaje cambia solo cada `SALUDO_CADA_MS`, y se puede pasar a mano. Con
 * «reducir movimiento» activado no cambia solo: un texto que se mueve sin que
 * nadie lo pida es justamente lo que esa preferencia pide evitar.
 */
export function SaludoCumpleanos({ nombre, bono, hoy }: { nombre: string; bono: MiBono; hoy: string }) {
  const [i, setI] = useState(() => saludoInicial(hoy));
  const [quieto, setQuieto] = useState(false);

  useEffect(() => {
    const reducir = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
    if (reducir || quieto) return;
    const t = window.setInterval(() => setI((n) => (n + 1) % SALUDOS_CUMPLEANOS.length), SALUDO_CADA_MS);
    return () => window.clearInterval(t);
  }, [quieto]);

  const pedir = puedePedirBono(bono);

  return (
    <section
      aria-label="Tu mes de cumpleaños"
      onMouseEnter={() => setQuieto(true)}
      onMouseLeave={() => setQuieto(false)}
      className="relative mb-6 overflow-hidden rounded-2xl border border-rojo/30 bg-papel p-5 sm:p-6"
    >
      {/* Confeti con los tokens de la casa: sigue al modo oscuro sin tocar nada. */}
      <div aria-hidden className="pointer-events-none absolute inset-0 opacity-60">
        {[
          "left-[6%] top-3 bg-rojo", "left-[18%] bottom-4 bg-ambar", "left-[42%] top-2 bg-verde",
          "right-[30%] bottom-3 bg-pizarra", "right-[14%] top-5 bg-rojo", "right-[5%] bottom-6 bg-taupe",
        ].map((c) => <span key={c} className={`absolute h-1.5 w-1.5 rotate-45 rounded-[1px] ${c}`} />)}
      </div>

      <div className="relative flex items-start gap-4">
        <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-rojo/10 text-rojo">
          <Cake className="h-6 w-6" aria-hidden />
        </div>
        <div className="min-w-0 flex-1">
          <div className="etiqueta text-taupe">Tu mes de cumpleaños</div>
          <h2 className="mt-1 font-serif text-2xl leading-tight text-tinta sm:text-3xl">
            ¡Feliz cumpleaños, {nombre}!
          </h2>
          {/* `aria-live` educado: un lector de pantalla lee el cambio sin cortar lo que estaba leyendo. */}
          <p key={i} aria-live="polite" className="entra-seccion mt-2 min-h-[3rem] text-sm leading-relaxed text-tinta sm:text-base">
            {SALUDOS_CUMPLEANOS[i]}
          </p>

          <div className="mt-4 flex flex-wrap items-center gap-x-5 gap-y-3">
            {pedir && (
              <Link href="/mio/cumpleanos"
                className="inline-flex min-h-11 items-center rounded-full bg-tinta px-5 text-sm font-medium text-crema hover:bg-rojo-profundo">
                Firmar mi bono de cumpleaños{bono.monto != null ? ` · ${formatSoles(bono.monto)}` : ""}
              </Link>
            )}
            <button type="button" onClick={() => setI((n) => (n + 1) % SALUDOS_CUMPLEANOS.length)}
              className="min-h-11 text-sm text-taupe underline underline-offset-2 hover:text-rojo-profundo">
              Otro mensaje ({i + 1} de {SALUDOS_CUMPLEANOS.length})
            </button>
          </div>
          {pedir && (
            <p className="mt-2 text-xs text-taupe">
              Lo firmas con tu firma digital y se suma a tu boleta. Tienes todo el mes.
            </p>
          )}
        </div>
      </div>
    </section>
  );
}

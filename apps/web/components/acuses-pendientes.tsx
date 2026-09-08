"use client";

// ============================================================================
// El aviso que pide dejar constancia de lo que hay pendiente de firmar.
// ============================================================================
//
// POR QUÉ EXISTE. La Ley 30709 obliga a informar la política salarial a cada
// persona y a PODER PROBARLO; el reglamento interno tiene la misma exigencia por
// su lado. Las dos pantallas para firmarlo llevan meses construidas, y aun así
// una integrante que entra por primera vez cae en el Dashboard y no tiene por
// qué saber que le toca ir a buscarlas. Un trámite que depende de que alguien
// adivine dónde está no se completa: no es culpa suya, es del diseño.
//
// QUÉ NO HACE, Y ES DELIBERADO
//
//   · NO bloquea el panel. Se puede cerrar y seguir trabajando. Un aviso que
//     secuestra la pantalla acabaría bloqueando a quien entra a arreglar algo
//     urgente un domingo, y ese precio no lo paga la ley.
//   · NO firma nada por nadie. Lleva a la pantalla donde se firma y ahí la
//     persona lee y decide. El valor probatorio del acuse depende justo de eso.
//   · NO se guarda que lo cerraste. Vuelve a salir en la siguiente visita, y
//     desaparece para siempre en cuanto firmas. Recordar el «ahora no» sería
//     construir la forma de que nunca se firme.
//
// EL AVISO DEL MENÚ, QUE APLICA A MEDIAS. `nav.tsx` dice —con razón— que «un
// aviso que aparece en todos lados deja de ser un aviso», y por eso solo tiene
// un contador. Éste se salta esa regla a propósito y con una condición: solo lo
// ve quien tiene algo pendiente, y deja de verlo el día que lo resuelve. No es
// un adorno permanente; es una tarea con final.
// ============================================================================

import { useEffect, useState } from "react";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { traerAcusesPendientes, type AcusePendiente } from "@/lib/acuses-pendientes";

// QUÉ falta acusar se decide en lib/acuses-pendientes.ts, no acá: la Bandeja
// cuenta lo mismo que este aviso enseña, y dos copias del mismo
// `requiere_acuse && !mi_acuse_at` se separan solas con el tiempo.

export function AcusesPendientes() {
  const persona = usePersonaActual();
  const [pendientes, setPendientes] = useState<AcusePendiente[]>([]);
  const [cerrado, setCerrado] = useState(false);

  useEffect(() => {
    if (!persona) return;
    let vivo = true;
    const supabase = createAdminSupabaseClient();

    void (async () => {
      const lista = await traerAcusesPendientes(supabase);
      if (!vivo) return;
      setPendientes(lista);
    })();

    return () => { vivo = false; };
    // `persona` y no `persona.id`: si cambia la sesión, se vuelve a preguntar.
  }, [persona]);

  if (cerrado || pendientes.length === 0) return null;

  const uno = pendientes.length === 1;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="acuses-titulo"
      className="fixed inset-0 z-50 flex items-end justify-center bg-black/40 p-4 sm:items-center"
    >
      <div className="w-full max-w-lg rounded-2xl border border-taupe/35 bg-papel p-6">
        <h2 id="acuses-titulo" className="font-serif text-xl text-tinta">
          {uno ? "Te falta dejar una constancia" : "Te faltan dos constancias"}
        </h2>

        <p className="mt-2 text-sm text-taupe">
          CAYLA tiene que poder demostrar que te informó de esto, y la única forma
          es que lo dejes tú desde tu propia cuenta. Se lee en un minuto y no
          firmas ningún compromiso: dejas constancia de haber sido informada.
        </p>

        <ul className="mt-4 space-y-2">
          {pendientes.map((x) => (
            <li key={x.clave} className="rounded-xl border border-sand bg-hueso p-3">
              <p className="text-sm font-medium text-tinta">{x.titulo}</p>
              {x.detalle && <p className="mt-0.5 text-xs text-taupe">{x.detalle}</p>}
              {/* Nativo a propósito: es un <Link> de navegación, no un
                  <button> — <Boton> no acepta href (mismo criterio que los
                  <Link> "Ver documento" ya dejados nativos en otras pantallas
                  migradas). */}
              <Link
                href={x.href}
                onClick={() => setCerrado(true)}
                className="mt-2 inline-block rounded-lg bg-tinta px-3 py-1.5 text-xs text-crema hover:bg-tinta/90"
              >
                Leer y dejar constancia
              </Link>
            </li>
          ))}
        </ul>

        {/* Nativo a propósito: arranca en text-taupe y oscurece a text-tinta en
            hover — lo opuesto a <Boton variante="enlace"> (hover:text-taupe).
            Forzarlo invertiría la dirección del único cambio visible. */}
        <button
          onClick={() => setCerrado(true)}
          className="mt-4 text-xs text-taupe underline decoration-taupe/30 underline-offset-2 hover:text-tinta"
        >
          Ahora no — me lo recuerdas la próxima vez
        </button>
      </div>
    </div>
  );
}

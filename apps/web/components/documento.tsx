"use client";

import { useMemo } from "react";
import { bloquesDe, type Marca } from "@/lib/admin/markdown-documento";

// El visor de un documento institucional.
//
// Vive acá y no dentro de la pantalla de Normas porque lo usan DOS sitios: la
// lectura en pantalla —donde cada integrante deja su constancia— y la hoja de
// impresión. Y tienen que pintar exactamente lo mismo: si el papel dijera algo
// distinto de lo que se acusó, el acuse dejaría de probar nada.

/**
 * El documento se guarda como markdown y se pinta sin librería. El análisis
 * —dónde empieza una tabla, cuándo acaba una lista, qué es negrita— vive en
 * `lib/admin/markdown-documento.ts` porque es la parte que se puede equivocar y
 * ahí sí se puede probar. Aquí solo se dibuja.
 *
 * Nunca `dangerouslySetInnerHTML`: el texto viene de la base, y quien pudiera
 * publicar un documento podría inyectar marcado en la pantalla de quien lo
 * acusa. Con nodos de React, React lo escapa todo por su cuenta.
 */
export function Marcado({ marcas }: { marcas: Marca[] }) {
  return (
    <>
      {marcas.map((m, i) =>
        m.estilo === "negrita" ? <strong key={i}>{m.texto}</strong>
        : m.estilo === "cursiva" ? <em key={i}>{m.texto}</em>
        : m.estilo === "codigo" ? <code key={i} className="rounded bg-sand/50 px-1 text-[12px]">{m.texto}</code>
        : <span key={i}>{m.texto}</span>,
      )}
    </>
  );
}

const CLASE_ENCABEZADO: Record<number, string> = {
  1: "mt-2 font-serif text-2xl",
  2: "mt-6 border-b border-sand pb-1 font-serif text-lg",
  3: "mt-5 font-serif text-base font-medium",
  4: "mt-4 font-serif text-sm font-medium",
};

export function Documento({ texto }: { texto: string }) {
  const bloques = useMemo(() => bloquesDe(texto), [texto]);
  return (
    <div className="prose-cayla max-w-none text-[13px] leading-relaxed text-tinta">
      {bloques.map((b, i) => {
        switch (b.tipo) {
          case "espacio":
            return <div key={i} className="h-2" />;
          case "regla":
            return <hr key={i} className="my-4 border-sand" />;
          case "encabezado": {
            const H = (["h1", "h2", "h3", "h4"] as const)[b.nivel - 1];
            return <H key={i} className={CLASE_ENCABEZADO[b.nivel]}><Marcado marcas={b.marcas} /></H>;
          }
          case "cita":
            return (
              <p key={i} className="my-2 border-l-2 border-sand pl-3 text-xs text-taupe">
                <Marcado marcas={b.marcas} />
              </p>
            );
          case "lista": {
            const L = b.ordenada ? "ol" : "ul";
            // `enCita` mantiene el filete a la izquierda: dentro de un modelo de
            // carta, una lista sin él se lee como texto del Manual y no como
            // parte de la carta que se va a firmar.
            return (
              <L key={i} className={`my-2 space-y-0.5 pl-6 ${b.ordenada ? "list-decimal" : "list-disc"}`
                + (b.enCita ? " ml-3 border-l-2 border-sand pl-8 text-xs text-taupe" : "")}>
                {b.items.map((it, j) => <li key={j} className="my-1"><Marcado marcas={it} /></li>)}
              </L>
            );
          }
          case "tabla":
            return (
              // La tabla se desborda dentro de su propia caja: el documento se
              // lee en un panel estrecho y una tabla ancha no puede empujar el
              // texto de al lado fuera de la pantalla.
              <div key={i} className={"my-3 overflow-x-auto"
                + (b.enCita ? " ml-3 border-l-2 border-sand pl-3" : "")}>
                <table className="w-full border-collapse text-[12px]">
                  {b.cabecera && (
                    <thead>
                      <tr>{b.cabecera.map((c, j) => (
                        <th key={j} className="border border-sand bg-sand/40 px-2 py-1 text-left font-medium">
                          <Marcado marcas={c} />
                        </th>
                      ))}</tr>
                    </thead>
                  )}
                  <tbody>
                    {b.filas.map((f, j) => (
                      <tr key={j}>{f.map((c, k) => (
                        <td key={k} className="border border-sand px-2 py-1 align-top">
                          <Marcado marcas={c} />
                        </td>
                      ))}</tr>
                    ))}
                  </tbody>
                </table>
              </div>
            );
          default:
            return <p key={i} className="my-2"><Marcado marcas={b.marcas} /></p>;
        }
      })}
    </div>
  );
}

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

/**
 * La MEDIDA de lectura, dicha una sola vez.
 *
 * Antes no la decidía nadie: `max-w-none` neutralizaba una clase `prose-cayla`
 * que no existe en ningún CSS de este repositorio, así que el ancho lo heredaba
 * la tarjeta —828 px, unos 127 caracteres a 13 px— y el mismo componente se
 * pintaba con cuatro medidas distintas entre la pantalla, los anexos, la hoja de
 * impresión y la vista previa de publicación. El intervalo cómodo para prosa es
 * de 45 a 75 caracteres; `62ch` aterriza en unos 68 y escala solo si algún día
 * cambia el cuerpo.
 *
 * NO se le pone a la tabla: esa necesita todo el ancho y ya se contiene sola.
 */
const MEDIDA = "max-w-[62ch]";

/**
 * `whitespace-pre-wrap` en los bloques de texto seguido.
 *
 * Conserva las RACHAS de espacios, que en estos documentos son contenido: en los
 * modelos de carta del Manual, `____________     ____________` son las dos
 * casillas de firma —quien emite y quien recibe— y el navegador las colapsaba en
 * una sola raya continua, con sus dos rótulos pegados. En una hoja que se imprime
 * en blanco para firmarse a mano, dejaban de leerse dos casillas.
 *
 * Recupera la separación, no la alineación: la letra es proporcional y el
 * documento contó caracteres suponiendo ancho fijo, así que cada rótulo queda
 * junto a su raya y no exactamente debajo. Alinear pediría tocar el texto
 * congelado, o sea la versión que ya se acusó.
 */
const TEXTO_SEGUIDO = `${MEDIDA} whitespace-pre-wrap`;

const CLASE_ENCABEZADO: Record<number, string> = {
  1: `${MEDIDA} mt-2 font-serif text-2xl`,
  2: `${MEDIDA} mt-6 border-b border-sand pb-1 font-serif text-lg`,
  3: `${MEDIDA} mt-5 font-serif text-base font-medium`,
  4: `${MEDIDA} mt-4 font-serif text-sm font-medium`,
};

export function Documento({ texto }: { texto: string }) {
  const bloques = useMemo(() => bloquesDe(texto), [texto]);
  return (
    <div className="text-[13px] leading-relaxed text-tinta">
      {bloques.map((b, i) => {
        switch (b.tipo) {
          case "espacio":
            return <div key={i} className="h-2" />;
          case "regla":
            return <hr key={i} className={`${MEDIDA} my-4 border-sand`} />;
          case "encabezado": {
            const H = (["h1", "h2", "h3", "h4"] as const)[b.nivel - 1];
            return <H key={i} className={CLASE_ENCABEZADO[b.nivel]}><Marcado marcas={b.marcas} /></H>;
          }
          case "cita":
            return (
              <p key={i} className={`${TEXTO_SEGUIDO} my-2 border-l-2 border-sand pl-3 text-xs text-taupe`}>
                <Marcado marcas={b.marcas} />
              </p>
            );
          case "lista": {
            const L = b.ordenada ? "ol" : "ul";
            // `enCita` mantiene el filete a la izquierda: dentro de un modelo de
            // carta, una lista sin él se lee como texto del Manual y no como
            // parte de la carta que se va a firmar.
            //
            // `start` es obligatorio y no un detalle: sin él el navegador renumera
            // desde 1, y en un documento normativo eso publica un número de
            // artículo que el texto no dice.
            return (
              <L key={i} start={b.ordenada ? b.inicio : undefined}
                className={`${MEDIDA} my-2 space-y-0.5 pl-6 ${b.ordenada ? "list-decimal" : "list-disc"}`
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
            return <p key={i} className={`${TEXTO_SEGUIDO} my-2`}><Marcado marcas={b.marcas} /></p>;
        }
      })}
    </div>
  );
}

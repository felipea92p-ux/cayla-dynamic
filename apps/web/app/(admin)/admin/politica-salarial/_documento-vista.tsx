import type { Bloque, Documento } from "@/lib/politica-salarial";

// El renderizador estático del documento — sin colapsables, sin índice, sin
// widgets. Lo usan la vista de una versión histórica (que se muestra tal cual
// se congeló, no como una pantalla para interactuar) y cualquier otro lugar
// que necesite el documento completo de un tirón, como antes de este
// rediseño. La pantalla "Documento vigente" tiene su PROPIA versión
// colapsable con ancla (ver page.tsx) porque ahí sí hace falta navegación —
// pero comparte este mismo BloqueVista para no dibujar una tabla o una lista
// de dos formas distintas.

export function BloqueVista({ b }: { b: Bloque }) {
  if (b.tipo === "parrafo") return <p className="mb-3 text-sm leading-relaxed text-tinta">{b.texto}</p>;
  if (b.tipo === "destacado")
    return <p className="mb-4 border-l-4 border-tinta bg-sand/20 px-4 py-3 text-sm font-medium leading-relaxed text-tinta">{b.texto}</p>;
  if (b.tipo === "lista")
    return (
      <ul className="mb-4 list-disc space-y-1 pl-6 text-sm leading-relaxed text-tinta">
        {b.items.map((it, i) => <li key={i}>{it}</li>)}
      </ul>
    );
  return (
    <div className="mb-4 overflow-x-auto">
      <table className="w-full border-collapse text-left text-sm">
        <thead><tr>{b.cabeceras.map((c, i) => <th key={i} className="border border-sand bg-sand/70 px-3 py-2 font-semibold text-tinta">{c}</th>)}</tr></thead>
        <tbody>{b.filas.map((fila, i) => (
          <tr key={i}>{fila.map((celda, j) => <td key={j} className="border border-sand px-3 py-2 align-top text-tinta">{celda}</td>)}</tr>
        ))}</tbody>
      </table>
    </div>
  );
}

export function DocumentoVista({ doc, firmaUrl }: { doc: Documento; firmaUrl: string | null }) {
  return (
    <article className="rounded-superficie border border-sand bg-papel p-6 print:rounded-none print:border-0 print:p-0">
      <header className="mb-6 border-b border-sand pb-4">
        <h2 className="text-lg font-semibold text-tinta">{doc.titulo}</h2>
        <p className="text-sm text-taupe">{doc.empresa.nombre} — RUC {doc.empresa.ruc}</p>
        <p className="text-sm text-taupe">{doc.fecha}</p>
      </header>
      {doc.secciones.map((sec, i) => (
        <section key={i} className="mb-6">
          <h3 className="mb-3 text-base font-semibold text-tinta print:break-after-avoid">{sec.titulo}</h3>
          {sec.bloques.map((b, j) => <BloqueVista key={j} b={b} />)}
        </section>
      ))}
      <footer className="mt-10 border-t border-sand pt-6 print:break-inside-avoid">
        {firmaUrl !== null && (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={firmaUrl} alt="" className="mb-1 h-16 object-contain" />
        )}
        <p className="text-sm font-medium text-tinta">{doc.empresa.firmante}</p>
        <p className="text-sm text-taupe">{doc.empresa.cargo} — {doc.empresa.nombre}</p>
      </footer>
    </article>
  );
}

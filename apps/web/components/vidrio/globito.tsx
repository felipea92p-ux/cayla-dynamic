// El número junto a una fila del menú: cuántas cosas te piden algo. El de Retail (components/ui/Globito.tsx, con `pide`), ámbar suave junto
// al nombre y, con el menú plegado, lleno sobre la esquina del ícono: eso lo decide la hoja de estilos con `data-lateral`, no este componente.
//
// Con 0 no se dibuja: un cero al lado de cada fila es ruido, y un aviso que siempre está deja de ser aviso. El número se oculta a los lectores
// de pantalla y en su lugar va la frase entera: «Incidencias 2» suena a que hay dos incidencias, no a que dos personas pidieron algo.

export function Globito({ n, etiqueta }: { n: number; etiqueta?: string }) {
  if (!Number.isFinite(n) || n <= 0) return null;
  return (
    <span className="globito">
      <span aria-hidden>{n > 99 ? "99+" : n}</span>
      <span className="sr-only">{etiqueta ?? `${n} por atender`}</span>
    </span>
  );
}

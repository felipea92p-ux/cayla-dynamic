// La misma fila de objetivo (ícono de cumplido/pendiente + descripción +
// indicaciones opcionales) estaba escrita tres veces, carácter por carácter,
// en mio/page.tsx, admin/horas/page.tsx y admin/personas/[id]/page.tsx —
// cada una con "✓"/"○" de texto en vez de un ícono real. Una sola copia.

import { CircleCheck, Circle } from "lucide-react";
import { cx } from "./cx";

export function ItemObjetivo({
  cumplido,
  descripcion,
  indicaciones,
}: {
  cumplido: boolean;
  descripcion: string;
  indicaciones?: string | null;
}) {
  const Icono = cumplido ? CircleCheck : Circle;
  return (
    <li className="flex items-start gap-2">
      <Icono
        size={16}
        strokeWidth={1.8}
        className={cx("mt-0.5 shrink-0", cumplido ? "text-verde" : "text-taupe/50")}
        aria-hidden
      />
      <div>
        <span className={cumplido ? "text-taupe line-through" : ""}>{descripcion}</span>
        {indicaciones && (
          <p className="mt-0.5 whitespace-pre-wrap text-xs text-taupe">{indicaciones}</p>
        )}
      </div>
    </li>
  );
}

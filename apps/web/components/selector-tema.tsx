"use client";

// Un solo botón que rota sistema → claro → oscuro → sistema. Mismo criterio
// que Buscar y Atajos de teclado (icono + `title`, sin desplegable nuevo) —
// tres opciones no justifican un panel flotante propio.

import { Monitor, Moon, Sun, type LucideIcon } from "lucide-react";
import { useTema, type Tema } from "@/lib/use-tema";

const SIGUIENTE: Record<Tema, Tema> = { sistema: "claro", claro: "oscuro", oscuro: "sistema" };
const ICONO: Record<Tema, LucideIcon> = { sistema: Monitor, claro: Sun, oscuro: Moon };
const ETIQUETA: Record<Tema, string> = { sistema: "Sistema", claro: "Claro", oscuro: "Oscuro" };

export function SelectorTema({ className = "" }: { className?: string }) {
  const [tema, setTema] = useTema();
  const Icono = ICONO[tema];
  return (
    <button
      onClick={() => setTema(SIGUIENTE[tema])}
      aria-label={`Tema: ${ETIQUETA[tema]}`}
      title={`Tema: ${ETIQUETA[tema]} (clic para cambiar)`}
      className={`rounded-md border border-sand p-1.5 text-taupe transition hover:border-taupe/40 hover:bg-sand/30 hover:text-rojo active:scale-[0.97] active:text-rojo-profundo ${className}`}
    >
      <Icono size={15} strokeWidth={1.8} aria-hidden />
    </button>
  );
}

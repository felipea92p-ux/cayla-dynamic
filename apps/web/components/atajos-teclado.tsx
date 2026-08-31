"use client";

// Atajos de teclado del panel — para quien vive acá todo el día.
//
// `g` y después una letra salta a una pantalla sin soltar el teclado ni
// mirar el menú, el mismo patrón que Gmail y GitHub. `?` abre esta lista.
// Los dos se apagan solos si el foco está en un campo de texto: nadie quiere
// que escribir "gente" en un buscador dispare un salto de pantalla a mitad
// de la palabra.
//
// Las siete pantallas elegidas son las de uso diario —Asistencia, Equipo,
// Dashboard, Bandeja—. Planilla, Costos y el resto de Gestión son de uso
// mensual y ya están a un ⌘K de distancia; no todas necesitan una letra.
//
// Los rótulos e íconos de la ayuda salen de `grupos` (la misma lista, ya
// filtrada por rol, que usa el resto del menú) — si un día cambia el nombre
// de una pantalla, no hay una segunda copia de esa etiqueta que se pueda
// quedar atrás. Si el atajo apunta a algo que este rol no puede ver, la fila
// simplemente no aparece.

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { X } from "lucide-react";
import type { Item } from "@/app/(admin)/admin/nav";

const ATAJOS: { tecla: string; href: string }[] = [
  { tecla: "d", href: "/admin/dashboard" },
  { tecla: "b", href: "/admin/bandeja" },
  { tecla: "i", href: "/admin/incidencias" },
  { tecla: "c", href: "/admin/correcciones" },
  { tecla: "t", href: "/admin/turnos" },
  { tecla: "h", href: "/admin/horarios" },
  { tecla: "e", href: "/admin/equipo" },
];

const VENTANA_CORDE_MS = 1200;

function enCampoDeTexto(destino: EventTarget | null): boolean {
  if (!(destino instanceof HTMLElement)) return false;
  const etiqueta = destino.tagName;
  return etiqueta === "INPUT" || etiqueta === "TEXTAREA" || etiqueta === "SELECT" || destino.isContentEditable;
}

export function AtajosTeclado({
  grupos,
  abierto,
  setAbierto,
}: {
  grupos: Array<{ label?: string; items: Item[] }>;
  abierto: boolean;
  setAbierto: (v: boolean) => void;
}) {
  const router = useRouter();

  useEffect(() => {
    let esperandoLetra = false;
    let vencimiento: ReturnType<typeof setTimeout> | null = null;

    function alPresionar(e: KeyboardEvent) {
      if (e.metaKey || e.ctrlKey || e.altKey || enCampoDeTexto(e.target)) return;

      if (esperandoLetra) {
        esperandoLetra = false;
        if (vencimiento) clearTimeout(vencimiento);
        const atajo = ATAJOS.find((a) => a.tecla === e.key.toLowerCase());
        if (atajo) { e.preventDefault(); router.push(atajo.href); }
        return;
      }

      if (e.key === "g") {
        e.preventDefault();
        esperandoLetra = true;
        vencimiento = setTimeout(() => { esperandoLetra = false; }, VENTANA_CORDE_MS);
        return;
      }

      if (e.key === "?") {
        e.preventDefault();
        setAbierto(true);
        return;
      }

      if (e.key === "Escape" && abierto) setAbierto(false);
    }

    window.addEventListener("keydown", alPresionar);
    return () => {
      window.removeEventListener("keydown", alPresionar);
      if (vencimiento) clearTimeout(vencimiento);
    };
  }, [abierto, setAbierto, router]);

  const pantallas = grupos.flatMap((g) => g.items);
  const filas = ATAJOS
    .map((a) => ({ tecla: a.tecla, item: pantallas.find((p) => p.href === a.href) }))
    .filter((f): f is { tecla: string; item: Item } => !!f.item);

  if (!abierto) return null;

  return (
    <>
      <div onClick={() => setAbierto(false)} className="fixed inset-0 z-40 bg-tinta/20" aria-hidden />
      <div role="dialog" aria-label="Atajos de teclado"
        className="fixed left-1/2 top-24 z-50 w-[calc(100%-2rem)] max-w-sm -translate-x-1/2 overflow-hidden rounded-xl border border-sand bg-papel shadow-xl">
        <div className="flex items-center justify-between border-b border-sand px-4 py-3">
          <h2 className="font-serif text-lg">Atajos de teclado</h2>
          <button onClick={() => setAbierto(false)} aria-label="Cerrar"
            className="rounded-md p-1 text-taupe transition hover:bg-sand/40 hover:text-tinta">
            <X size={16} strokeWidth={1.8} aria-hidden />
          </button>
        </div>
        <div className="p-2">
          <Fila etiqueta="Buscar"><Tecla>⌘K</Tecla></Fila>
          <Fila etiqueta="Esta ayuda"><Tecla>?</Tecla></Fila>
          {filas.length > 0 && (
            <p className="etiqueta px-3 pb-1 pt-3 text-taupe">Saltar a una pantalla</p>
          )}
          {filas.map((f) => (
            <Fila key={f.item.href} etiqueta={f.item.label} icono={f.item.Icon}>
              <Tecla>g</Tecla>
              <Tecla>{f.tecla}</Tecla>
            </Fila>
          ))}
        </div>
      </div>
    </>
  );
}

function Tecla({ children }: { children: React.ReactNode }) {
  return (
    <kbd className="rounded border border-sand bg-sand/50 px-1.5 py-0.5 font-sans text-xs text-taupe">
      {children}
    </kbd>
  );
}

function Fila({
  etiqueta,
  icono: Icono,
  children,
}: {
  etiqueta: string;
  icono?: Item["Icon"];
  children: React.ReactNode;
}) {
  return (
    <div className="flex items-center justify-between rounded-md px-3 py-2 text-sm">
      <span className="flex items-center gap-2 text-tinta">
        {Icono && <Icono size={15} strokeWidth={1.8} aria-hidden />}
        {etiqueta}
      </span>
      <span className="flex items-center gap-1">{children}</span>
    </div>
  );
}

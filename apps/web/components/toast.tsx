"use client";

// El único aviso de acción del panel — reemplaza los ~20 banners sueltos que
// cada pantalla dibujaba a su manera. La auditoría de la ruta a primer nivel
// midió seis estilos distintos para la misma idea (caja con fondo, texto sin
// caja, borde de color...); esta es la única versión, y vive una sola vez.
//
// `avisar(tipo, texto)` es la misma firma que ya usaban de memoria varias
// pantallas como helper local — migrar es borrar ese helper y este estado, y
// pedir el mismo nombre desde acá.
//
// LOS «OK» SE APAGAN SOLOS; LOS «ERROR» NO. No es una preferencia de forma:
// hoy ningún banner del panel se auto-cierra, así que un error nunca
// desaparecía antes de que alguien lo leyera. Mantener eso para los errores
// —y sólo relajarlo para las confirmaciones, que no hay nada que releer— es
// lo que hace que este cambio sea una mejora y no una forma nueva de perderse
// un fallo.

import { createContext, useCallback, useContext, useRef, useState, type ReactNode } from "react";
import { X } from "lucide-react";

type TipoAviso = "ok" | "error";
type Aviso = { id: number; tipo: TipoAviso; texto: string };

const DURACION_OK_MS = 4500;

const ToastContext = createContext<{ avisar: (tipo: TipoAviso, texto: string) => void } | null>(null);

export function ToastProvider({ children }: { children: ReactNode }) {
  const [avisos, setAvisos] = useState<Aviso[]>([]);
  const idRef = useRef(0);

  const cerrar = useCallback((id: number) => {
    setAvisos((a) => a.filter((x) => x.id !== id));
  }, []);

  const avisar = useCallback((tipo: TipoAviso, texto: string) => {
    const id = ++idRef.current;
    setAvisos((a) => [...a, { id, tipo, texto }]);
    if (tipo === "ok") setTimeout(() => cerrar(id), DURACION_OK_MS);
  }, [cerrar]);

  return (
    <ToastContext.Provider value={{ avisar }}>
      {children}
      {/* Esquina inferior derecha, apilados — no compite con el buscador
          (top-24, centrado) ni con ningún panel lateral existente. */}
      <div aria-live="polite" className="pointer-events-none fixed bottom-4 right-4 z-[60] flex flex-col gap-2">
        {avisos.map((a) => (
          <div key={a.id} role={a.tipo === "error" ? "alert" : "status"}
            className={`pointer-events-auto flex w-80 max-w-[calc(100vw-2rem)] items-start gap-2.5 rounded-control border bg-papel px-4 py-3 text-sm shadow-xl transition ${
              a.tipo === "error" ? "border-rojo/30 text-rojo" : "border-sand text-tinta"}`}>
            <span aria-hidden
              className={`mt-1 h-1.5 w-1.5 shrink-0 rounded-pildora ${a.tipo === "error" ? "bg-rojo" : "bg-verde"}`} />
            <span className="flex-1">{a.texto}</span>
            {/* Nativo a propósito: botón de solo ícono, misma familia que los
                demás cerrar/Tema/Atajos — <Boton> no cubre un ícono suelto. */}
            <button onClick={() => cerrar(a.id)} aria-label="Cerrar aviso"
              className="shrink-0 text-taupe transition hover:text-tinta">
              <X size={14} strokeWidth={1.8} aria-hidden />
            </button>
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  );
}

/** `avisar("ok" | "error", texto)` — el reemplazo de cada `setMensaje({tipo, texto})` local. */
export function useToast() {
  const ctx = useContext(ToastContext);
  if (!ctx) throw new Error("useToast() necesita <ToastProvider> — está montado en app/layout.tsx");
  return ctx;
}

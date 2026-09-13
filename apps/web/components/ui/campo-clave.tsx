"use client";

import { useState, type InputHTMLAttributes } from "react";
import { Eye, EyeOff } from "lucide-react";
import { cx } from "./cx";

type BaseProps = {
  etiqueta?: string;
  /** Mensaje de error, con borde rojo a juego. No valida por sí solo. */
  error?: string;
};

// Igual que <Campo>, con un botón para alternar type="password"/"text". No
// resuelve por sí solo un "correo o contraseña incorrectos": solo ayuda a
// descartar un typo antes de enviar la clave.
//
// No envuelve a <Campo> porque su <label> abarca etiqueta+input+error, y el
// botón necesita quedar posicionado sobre el input solo — mismo motivo por
// el que <CampoSelect> tampoco reusa <Campo> para su flecha.
export function CampoClave({
  etiqueta,
  error,
  id,
  className,
  ...props
}: BaseProps & InputHTMLAttributes<HTMLInputElement>) {
  const [visible, setVisible] = useState(false);
  return (
    <label className="flex flex-col gap-1">
      {etiqueta && <span className="text-sm text-taupe">{etiqueta}</span>}
      <div className="relative">
        <input
          id={id}
          type={visible ? "text" : "password"}
          className={cx(
            "w-full rounded-control border border-sand bg-hueso px-3 py-2 pr-9 text-base text-tinta transition-colors duration-150 placeholder:text-taupe/60 sm:text-sm",
            error && "border-rojo",
            className,
          )}
          {...props}
        />
        <button
          type="button"
          tabIndex={-1}
          onClick={() => setVisible((v) => !v)}
          aria-label={visible ? "Ocultar contraseña" : "Mostrar contraseña"}
          className="absolute inset-y-0 right-0 flex items-center px-3 text-taupe hover:text-tinta"
        >
          {visible ? <EyeOff className="size-4" /> : <Eye className="size-4" />}
        </button>
      </div>
      {error && <span className="text-xs text-rojo">{error}</span>}
    </label>
  );
}

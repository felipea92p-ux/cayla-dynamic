"use client";

import { useState, type InputHTMLAttributes } from "react";
import { Eye, EyeOff } from "lucide-react";
import { cx } from "./cx";

// Un input de contraseña con su ojito de "ver contraseña". El className que
// recibe cada sitio ya trae su propio padding horizontal —lo definen ellos,
// separado en `pl-*`/`pr-*` y no `px-*`, porque el botón vive encima del
// borde derecho y `px-*` lo taparía.
export function CampoClave({ className, ...props }: InputHTMLAttributes<HTMLInputElement>) {
  const [visible, setVisible] = useState(false);
  return (
    <div className="relative">
      <input {...props} type={visible ? "text" : "password"} className={cx("w-full", className)} />
      <button
        type="button"
        tabIndex={-1}
        onClick={() => setVisible((v) => !v)}
        aria-label={visible ? "Ocultar contraseña" : "Mostrar contraseña"}
        className="absolute inset-y-0 right-0 flex items-center px-3 text-taupe hover:text-tinta"
      >
        {visible ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
      </button>
    </div>
  );
}

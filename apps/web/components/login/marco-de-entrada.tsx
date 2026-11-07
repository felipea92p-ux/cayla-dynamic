"use client";

// El marco de Entrar, para las dos pantallas que se abren desde ella: «Olvidé mi clave» y «Nueva clave». Decidido por Felipe el 2026-11-07
// (opción A, mirando las maquetas): las tres pantallas de entrada son una sola puerta. En pantalla ancha, a la izquierda el panel del colibrí ya
// posado —el vuelo es de Entrar y no se repite—; a la derecha, el formulario, con el saludo y el título como en Entrar. En el celular, la marca
// arriba y el formulario, igual que hoy.
//
// Solo con el vidrio. Retail no tiene estas pantallas (allá se le pide la clave a la líder), así que no hay pieza que copiar: se usan las de
// Entrar, con sus mismas clases de app/login-vuelo.css. Entrar sigue con su propio marcado, que es anterior y se ve igual apagado.

import { useSyncExternalStore, type ReactNode } from "react";
import { Colibri } from "@/components/marca";
import { PanelVuelo } from "@/components/login/PanelVuelo";
import { Rotulo } from "@/components/ui/rotulo";
import { saludoDelDia } from "@/lib/login-vuelo";

const sinSuscripcion = () => () => {};

export function MarcoDeEntrada({
  subtitulo,
  titulo,
  texto,
  pie,
  children,
}: {
  /** Lo que va bajo «Dynamic» en el celular: «Recuperar acceso», «Nueva clave». */
  subtitulo: string;
  titulo: string;
  texto?: ReactNode;
  /** El enlace de abajo, donde Entrar pone «¿Olvidaste tu clave?». */
  pie?: ReactNode;
  children: ReactNode;
}) {
  // El saludo depende de la hora: lo pone el navegador, como en Entrar.
  const saludo = useSyncExternalStore(sinSuscripcion, () => saludoDelDia(new Date()), () => null);
  return (
    <div className="login-pagina">
      <PanelVuelo sinVuelo />

      <main className="login-lado">
        <div className="login-form flex flex-col gap-3">
          <div className="login-marca-chica">
            <Colibri tono="rojo" className="w-12" />
            <p className="mt-4 font-serif text-3xl leading-none">Dynamic</p>
            <Rotulo className="mt-2 text-taupe">{subtitulo}</Rotulo>
          </div>

          <div className="mb-3">
            <p className="login-saludo" data-listo={saludo ? "" : undefined}>
              {saludo ?? " "}
            </p>
            <h1 className="login-titulo">{titulo}</h1>
            {texto ? <p className="mt-2 text-sm leading-relaxed text-taupe">{texto}</p> : null}
          </div>

          {children}
        </div>

        {pie ? <p className="login-pie text-sm">{pie}</p> : null}
      </main>
    </div>
  );
}

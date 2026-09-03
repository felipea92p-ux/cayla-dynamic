"use client";

/**
 * La caja de error de un campo — extraída de donde ya se dibujaba a mano, dos
 * veces, con el mismo marcado exacto, en `normas/page.tsx`. No envuelve el
 * `<input>`: cada pantalla arma el suyo con su propia clase base, y forzar un
 * campo genérico aquí no calzaría en todas. Quien la usa sigue escribiendo
 * `aria-invalid`/`aria-describedby`/el borde rojo en su propio input, pasando
 * el mismo `id` que le da a este componente.
 */
export function MensajeCampo({ id, mensaje }: { id: string; mensaje: string | null }) {
  if (!mensaje) return null;
  return (
    <p role="alert" id={id}
      className="mb-2 rounded border border-rojo/30 bg-rojo/10 px-2 py-1.5 text-xs text-rojo">
      {mensaje}
    </p>
  );
}

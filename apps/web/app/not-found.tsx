// Pantalla 404: cuando alguien entra a una dirección que no existe (enlace viejo
// o mal escrito). En vez del 404 crudo de Next, lo devolvemos a terreno conocido.
import Link from "next/link";

export default function NotFound() {
  return (
    <div className="flex min-h-screen flex-1 flex-col items-center justify-center gap-6 bg-crema px-6 text-center text-tinta">
      <span className="colibri w-20 text-taupe/40" aria-hidden />
      <div className="space-y-2">
        <h1 className="font-serif text-3xl">No encontramos esa página</h1>
        <p className="mx-auto max-w-sm text-sm leading-relaxed text-taupe">
          El enlace puede estar viejo o mal escrito. Volvamos a terreno conocido.
        </p>
      </div>
      <Link
        href="/admin/dashboard"
        className="rounded-control bg-tinta px-5 py-2.5 font-medium text-crema transition-colors hover:bg-rojo-profundo"
      >
        Ir al inicio
      </Link>
    </div>
  );
}

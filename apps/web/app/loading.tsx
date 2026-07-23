// Pantalla de carga entre navegaciones: el colibrí aletea mientras llega la
// siguiente pantalla, para que nunca se vea un vacío en blanco al cambiar de vista.
export default function Loading() {
  return (
    <div className="flex min-h-screen flex-1 flex-col items-center justify-center gap-4 bg-crema text-taupe">
      <span className="colibri aletea w-12 text-rojo/70" aria-hidden />
      <span className="text-sm">Cargando…</span>
    </div>
  );
}

import Link from "next/link";

export default function HomePage() {
  return (
    <main className="flex flex-1 flex-col items-center justify-center gap-4 p-8 text-center">
      <h1 className="text-2xl font-semibold">Dynamic — CAYLA</h1>
      <p className="text-taupe">Elige el módulo al que quieres entrar.</p>
      <div className="flex gap-4">
        <Link href="/terminal" className="rounded-lg bg-tinta px-5 py-3 text-crema">
          Terminal de marcaje
        </Link>
        <Link href="/admin" className="rounded-lg border border-sand px-5 py-3">
          Panel de administración
        </Link>
      </div>
    </main>
  );
}

import { SeguirTemaGlobal } from "@/components/seguir-tema-global";
import { RegistrarServiceWorker } from "@/components/registrar-service-worker";
import { Aurora } from "@/components/vidrio/aurora";
import { interruptoresVidrio } from "@/lib/vidrio";

// Con el vidrio del terminal encendido, el tema es de cada Mac mini: arranca en claro y lo cambia el botón de su cabecera
// (lib/vidrio-tema.ts), así que deja de seguir a /admin/apariencia. Apagado, todo sigue como siempre: `SeguirTemaGlobal`
// no dibuja nada, y el HTML es el mismo de hoy.
export default function TerminalLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen flex-1 select-none flex-col bg-crema text-tinta">
      {interruptoresVidrio().terminal ? <Aurora /> : <SeguirTemaGlobal />}
      <RegistrarServiceWorker />
      {children}
    </div>
  );
}

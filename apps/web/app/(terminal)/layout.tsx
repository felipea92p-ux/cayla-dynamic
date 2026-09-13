import { SeguirTemaGlobal } from "@/components/seguir-tema-global";
import { RegistrarServiceWorker } from "@/components/registrar-service-worker";

export default function TerminalLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen flex-1 select-none flex-col bg-crema text-tinta">
      <SeguirTemaGlobal />
      <RegistrarServiceWorker />
      {children}
    </div>
  );
}

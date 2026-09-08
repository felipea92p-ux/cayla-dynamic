import { SeguirTemaGlobal } from "@/components/seguir-tema-global";

export default function TerminalLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen flex-1 select-none flex-col bg-crema text-tinta">
      <SeguirTemaGlobal />
      {children}
    </div>
  );
}

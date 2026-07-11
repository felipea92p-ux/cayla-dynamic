export default function TerminalLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen flex-1 select-none flex-col bg-neutral-950 text-white">
      {children}
    </div>
  );
}

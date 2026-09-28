import { GuardaCuentaDeServicio } from "@/lib/cuenta-de-servicio";

// «Lo mío» no tenía marco propio: cada pantalla se monta sola. Este layout
// existe para una sola cosa, que tiene que valer para TODAS sus pantallas —
// también para la que se abre escribiendo la dirección—: una estación de
// retail con sesión abierta no entra (0490). No pinta nada más.
export default function MioLayout({ children }: { children: React.ReactNode }) {
  return <GuardaCuentaDeServicio>{children}</GuardaCuentaDeServicio>;
}

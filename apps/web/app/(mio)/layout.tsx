import { SeguirRuta } from "@/components/enlace-volver";
import { GuardaCuentaDeServicio } from "@/lib/cuenta-de-servicio";

// «Lo mío» no tenía marco propio: cada pantalla se monta sola. Este layout
// existe para una cosa que tiene que valer para TODAS sus pantallas —también
// para la que se abre escribiendo la dirección—: una estación de retail con
// sesión abierta no entra (0490). Y para una segunda, que por la misma razón
// no puede vivir en una pantalla: `SeguirRuta` anota de dónde llegó cada
// persona, para que «← Volver» pueda ser un «atrás» (lib/volver-atras.ts).
// No pinta nada.
export default function MioLayout({ children }: { children: React.ReactNode }) {
  return (
    <GuardaCuentaDeServicio>
      <SeguirRuta />
      {children}
    </GuardaCuentaDeServicio>
  );
}

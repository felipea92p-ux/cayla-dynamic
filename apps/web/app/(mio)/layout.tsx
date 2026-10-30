import { SeguirRuta } from "@/components/enlace-volver";
import { RegistrarSinConexion } from "@/components/registrar-sin-conexion";
import { AvisoVersionNueva } from "@/components/aviso-version-nueva";
import { GuardaCuentaDeServicio } from "@/lib/cuenta-de-servicio";

// «Lo mío» no tenía marco propio: cada pantalla se monta sola. Este layout
// existe para una cosa que tiene que valer para TODAS sus pantallas —también
// para la que se abre escribiendo la dirección—: una estación de retail con
// sesión abierta no entra (0490). Y para una segunda, que por la misma razón
// no puede vivir en una pantalla: `SeguirRuta` anota de dónde llegó cada
// persona, para que «← Volver» pueda ser un «atrás» (lib/volver-atras.ts).
// Ninguno de los dos pinta nada. Y un tercero, `RegistrarSinConexion`, instala el aviso de «sin internet».
export default function MioLayout({ children }: { children: React.ReactNode }) {
  return (
    <GuardaCuentaDeServicio>
      <SeguirRuta />
      <RegistrarSinConexion />
      <AvisoVersionNueva />
      {children}
    </GuardaCuentaDeServicio>
  );
}

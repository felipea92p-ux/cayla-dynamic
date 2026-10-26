import { MarcoAdmin } from "./admin/nav";
import { RegistrarSinConexion } from "@/components/registrar-sin-conexion";
import { AvisoVersionNueva } from "@/components/aviso-version-nueva";

// El marco del panel (sidebar + barra superior) se monta UNA vez, acá, y no en
// cada pantalla como hasta el 2026-09-07. Esa es la condición para que el
// sidebar no se remonte al navegar: si se remontara, en cada cambio de pantalla
// volvería a leer su plegado de localStorage y parpadearía.
//
// Este layout envuelve también el login, «olvidé mi clave» y «nueva clave»,
// donde todavía no hay sesión a la que preguntarle nada — por eso `MarcoAdmin`
// consulta `RUTAS_SIN_MARCO` y en esas se aparta, dejando pasar la pantalla sola.
export default function AdminLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen flex-1 flex-col bg-crema text-tinta">
      <RegistrarSinConexion />
      <AvisoVersionNueva />
      <MarcoAdmin>{children}</MarcoAdmin>
    </div>
  );
}

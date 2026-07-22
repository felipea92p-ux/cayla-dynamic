import { redirect } from "next/navigation";

// El "Perfil individual" se unificó dentro del perfil de persona (/admin/personas/[id],
// pestaña "Desempeño"). Se entra desde Equipo → clic en un nombre. Esta ruta vieja
// redirige a Equipo para no dejar un duplicado ni un enlace roto.
export default function PerfilRedirect() {
  redirect("/admin/equipo");
}

// Vacaciones se absorbió en Ausencias (migración 0101): vacaciones es un tipo de
// ausencia, no una pantalla aparte. Dos pantallas que responden la misma
// pregunta —«por qué no vino»— acaban diciendo cosas distintas.
//
// Esta ruta se conserva para que los enlaces guardados sigan funcionando.
import { redirect } from "next/navigation";

export default function VacacionesRedirect() {
  redirect("/admin/ausencias");
}

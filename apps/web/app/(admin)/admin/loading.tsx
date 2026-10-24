import { Cargando } from "@/components/cargando";

// Lo que se ve DENTRO del marco del panel mientras llega la pantalla a la que
// se hizo clic.
//
// Sin este archivo, el único `loading.tsx` era el de la raíz (`app/loading.tsx`),
// que queda POR ENCIMA del marco. Un clic en el menú dejaba la pantalla anterior
// quieta —y el menú sin marcar— hasta que la nueva estuviera lista: para quien
// mira, «hice clic y no pasó nada». Con una frontera acá, el marco ya está en su
// sitio, la dirección y el resaltado del menú cambian al instante, y solo el
// contenido espera. Los datos de cada pantalla siguen cargando después, con su
// propio «Cargando…».
export default function CargandoPantalla() {
  return <Cargando />;
}

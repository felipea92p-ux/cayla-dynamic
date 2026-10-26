import { Cargando } from "@/components/cargando";

// Lo que se ve mientras llega una pantalla de «Lo mío» a la que se hizo clic
// (Boleta, Contrato, Movilidad, Bandeja, Editar datos…).
//
// Sin este archivo, el único `loading.tsx` era el de la raíz (`app/loading.tsx`),
// que queda POR ENCIMA de la pantalla: un clic en «Ver mi boleta →» dejaba la
// pantalla anterior quieta, sin ningún cambio, hasta que la nueva estuviera lista.
// Para quien mira es «hice clic y no pasó nada», que es justo lo que se reportó.
// Con una frontera acá, el clic responde al instante y lo que espera es solo el
// contenido. Es el mismo arreglo que ya tiene el panel (`admin/loading.tsx`).
export default function CargandoPantallaMia() {
  return <Cargando />;
}

import { Insignia } from "@/components/ui/insignia";
import { ETIQUETA_ESTADO, type EstadoVisible } from "@/lib/boletas";

// El tono de cada estado lo decide `ETIQUETA_ESTADO` (lib/boletas.ts) y aquí solo
// se traduce al nombre que usa `<Insignia>`: así la pantalla de DO y la de la
// persona no pueden pintar «Confirmada» de dos colores.
const VARIANTE = {
  neutro: "neutral",
  info: "informativo",
  aviso: "advertencia",
  alerta: "alerta",
  ok: "positivo",
} as const;

export function InsigniaDeEstado({ estado }: { estado: EstadoVisible }) {
  const { texto, tono } = ETIQUETA_ESTADO[estado];
  return <Insignia variante={VARIANTE[tono]}>{texto}</Insignia>;
}

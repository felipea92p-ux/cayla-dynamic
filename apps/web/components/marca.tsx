// Identidad CAYLA aplicada a Dynamic. El isotipo es el colibrí de una sola línea
// del manual v3.0, teñido con color plano (sin gradientes ni sombras).

type Tono = "rojo" | "crema" | "tinta" | "sand" | "taupe";

const CLASE_TONO: Record<Tono, string> = {
  rojo: "text-rojo",
  crema: "text-crema",
  tinta: "text-tinta",
  sand: "text-sand",
  taupe: "text-taupe",
};

/** El isotipo solo. `className` controla el ancho (la altura se deriva). */
export function Colibri({
  tono = "rojo",
  className = "w-8",
}: {
  tono?: Tono;
  className?: string;
}) {
  return <span aria-hidden className={`colibri ${CLASE_TONO[tono]} ${className}`} />;
}

/**
 * Lockup de producto: colibrí + "Dynamic" en serif, con "CAYLA" como etiqueta.
 * `tono` define el color del texto (crema en superficies oscuras, tinta en claras).
 */
export function Marca({
  tono = "tinta",
  isotipo = "rojo",
  className = "",
}: {
  tono?: "crema" | "tinta";
  isotipo?: Tono;
  className?: string;
}) {
  const colorTexto = tono === "crema" ? "text-crema" : "text-tinta";
  const colorEtiqueta = tono === "crema" ? "text-crema/60" : "text-taupe";
  return (
    <span className={`flex items-center gap-3 ${className}`}>
      <Colibri tono={isotipo} className="w-10" />
      <span className="flex flex-col leading-none">
        <span className={`font-serif text-xl leading-none ${colorTexto}`}>Dynamic</span>
        <span className={`etiqueta mt-1 leading-none ${colorEtiqueta}`}>CAYLA</span>
      </span>
    </span>
  );
}

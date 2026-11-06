// El título de una pantalla con vidrio, el de Retail (components/ui/EncabezadoPagina.tsx): arriba la línea de dónde y cuándo, después el título
// en 46 px (36 en el teléfono). Recibe lo mismo que `CabeceraPagina`, que es quien lo elige según el interruptor.
//
// QUÉ VA A LA VISTA Y QUÉ NO
//   La frase que explica la pantalla va al «?». Lo que no es una frase —«en vivo», un rango de fechas, un total— se queda a la vista: un dato sirve para
//   decidir, y tenerlo que abrir para verlo sería peor que el párrafo que se quería evitar. Una `descripcion` de texto se toma por frase; quien
//   trae un dato o un aviso escrito como texto lo envuelve, y quien junta los dos los separa con la prop `vidrio`. Lo decide `CabeceraPagina`.

import { isValidElement, type ReactNode } from "react";
import { AyudaPantalla } from "@/components/ui/ayuda-pantalla";
import { AyudaConFrase } from "@/components/vidrio/frase-de-la-cabecera";
import { AyudaCabecera } from "@/components/vidrio/ayuda-cabecera";

export function CabeceraPaginaVidrio({
  sobretitulo,
  titulo,
  frase,
  dato,
  ayuda,
  accion,
  impreso,
}: {
  sobretitulo?: ReactNode;
  titulo: string;
  frase?: string;
  dato?: ReactNode;
  ayuda?: ReactNode;
  accion?: ReactNode;
  /**
   * Lo que sale en el papel: la cabecera de siempre. El estilo del vidrio solo vive en pantalla, y al imprimir este título salía en letra suelta y sin su frase (medido en Movilidad y en
   * el bono). Sin ayuda ni acción: son botones, y una segunda copia le quitaría la referencia a quien espera devolverles el foco.
   */
  impreso?: ReactNode;
}) {
  // Un solo «?»: la frase se lee dentro de la ventana de ayuda. Retail también los juntó (EncabezadoPagina). Quien trae su propia ventana (Seguros,
  // Disciplina) lo declara con `leeLaFrase`, y se encarga de mostrarla arriba de esa ventana.
  const unSoloSigno =
    isValidElement(ayuda) && (ayuda.type === AyudaPantalla || (ayuda.type as { leeLaFrase?: boolean }).leeLaFrase === true);
  // El signo va pegado a la última palabra: en un título largo, en el teléfono, caía solo al renglón de abajo.
  const corte = titulo.lastIndexOf(" ") + 1;
  return (
    <>
    <div className="vidrio-cabecera mb-5 flex flex-wrap items-center justify-between gap-x-10 gap-y-4 sm:mb-8 print:hidden">
      <div className="min-w-0">
        {sobretitulo ? (
          <p className="vidrio-sobretitulo flex min-w-0 items-center gap-3">
            <span aria-hidden className="h-px w-8 shrink-0 bg-taupe" />
            <span className="min-w-0">{sobretitulo}</span>
          </p>
        ) : null}
        {/* receta-propia: esta ES la cabecera de pantalla; CabeceraPagina la elige con el interruptor encendido */}
        <h1 className="vidrio-titulo text-tinta">
          {titulo.slice(0, corte)}
          <span className="whitespace-nowrap">
            {titulo.slice(corte)}
            {frase && !unSoloSigno ? <AyudaCabecera nombre={titulo}>{frase}</AyudaCabecera> : null}
            {ayuda ? (
              <span className="vidrio-titulo-ayuda">{unSoloSigno ? <AyudaConFrase frase={frase ?? null}>{ayuda}</AyudaConFrase> : ayuda}</span>
            ) : null}
          </span>
        </h1>
        {dato ? <div className="mt-2 max-w-2xl text-sm text-taupe">{dato}</div> : null}
      </div>
      {accion ? <div className="max-w-full shrink-0">{accion}</div> : null}
    </div>
    {impreso ? <div className="hidden print:block">{impreso}</div> : null}
    </>
  );
}

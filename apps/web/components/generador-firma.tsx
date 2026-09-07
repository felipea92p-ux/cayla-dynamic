"use client";

import { useMemo, useState, useTransition } from "react";
import { Caveat, Dancing_Script, Great_Vibes } from "next/font/google";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { generarImagenFirma, sugerirFormatoFirma, validarFirmaCoincideConNombre } from "@/lib/firma-generador";
import { Boton } from "./ui/boton";
import { Campo } from "./ui/campo";
import { useToast } from "./toast";

// Tres tipografías cursivas — de next/font/google, para no pedirle nada a
// Google en cada carga (mismo criterio que EB_Garamond/DM_Sans de layout.tsx).
// Cargadas solo acá, no en el layout global: nadie más usa una firma cursiva
// hoy, y este componente todavía no está montado en ninguna pantalla.
const elegante = Dancing_Script({ weight: "600", subsets: ["latin"] });
const natural = Caveat({ weight: "600", subsets: ["latin"] });
const clasica = Great_Vibes({ weight: "400", subsets: ["latin"] });

const ESTILOS = [
  { id: "elegante", etiqueta: "Elegante", clase: elegante.className, familia: elegante.style.fontFamily },
  { id: "natural", etiqueta: "A mano", clase: natural.className, familia: natural.style.fontFamily },
  { id: "clasica", etiqueta: "Clásica", clase: clasica.className, familia: clasica.style.fontFamily },
] as const;

type EstiloId = (typeof ESTILOS)[number]["id"];

/**
 * Genera una firma a partir del nombre escrito y la guarda como "mi firma"
 * (`fn_set_mi_firma` — abierta a cualquier persona desde la 0393, no solo a
 * admin/líder). Esa firma queda lista para estamparse en el contrato de quien
 * la generó.
 *
 * COMO CUANDO UN BRÓKER (p.ej. Interactive Brokers) exige que la firma de un
 * contrato coincida con los datos ya registrados de esa persona: acá tampoco
 * vale cualquier texto. Se sugiere un formato a partir del nombre real
 * (`sugerirFormatoFirma`) y se valida lo que se escriba contra ese mismo
 * nombre (`validarFirmaCoincideConNombre`) — así "jsdlaksj" nunca llega a
 * generarse como firma de nadie. La base vuelve a exigir esto mismo al
 * guardar (0394): esto de acá es la respuesta rápida en pantalla, no la única
 * puerta.
 *
 * Montado hoy en «Mi perfil» (apps/web/app/(mio)/mio/page.tsx) porque el
 * módulo de "mis datos" todavía no existe. Cuando exista, este bloque se muda
 * ahí — el componente no asume nada de dónde vive, así que mudarlo es mover
 * el `<GeneradorFirma />` de sitio, nada más.
 */
export function GeneradorFirma({ nombres, apellidos }: { nombres: string; apellidos: string }) {
  const { avisar } = useToast();
  const sugerencia = useMemo(() => sugerirFormatoFirma(nombres, apellidos), [nombres, apellidos]);
  const [nombre, setNombre] = useState(sugerencia);
  const [tocado, setTocado] = useState(false);
  // La sugerencia llega después (yo se carga aparte, ver mio/page.tsx): si ya
  // se prellenó con una vacía, hay que reemplazarla cuando llegue la de
  // verdad — pero solo mientras nadie haya tocado el campo, para no borrarle
  // a alguien lo que ya escribió. Ajustado EN EL RENDER (no en un efecto): es
  // el patrón que React documenta para "adjusting state when a prop changes"
  // — guardar el valor anterior y comparar, en vez de un useEffect con
  // setState adentro, que dispara un render extra de más.
  const [sugerenciaAnterior, setSugerenciaAnterior] = useState(sugerencia);
  if (sugerencia !== sugerenciaAnterior) {
    setSugerenciaAnterior(sugerencia);
    if (!tocado) setNombre(sugerencia);
  }

  const [estiloId, setEstiloId] = useState<EstiloId>("elegante");
  const [guardando, iniciarGuardado] = useTransition();

  const estilo = useMemo(() => ESTILOS.find((e) => e.id === estiloId) ?? ESTILOS[0], [estiloId]);

  const datosListos = nombres.trim() !== "" && apellidos.trim() !== "";
  const validacion = useMemo(
    () => (datosListos ? validarFirmaCoincideConNombre(nombre, nombres, apellidos) : { valida: false }),
    [nombre, nombres, apellidos, datosListos],
  );
  const mostrarError = datosListos && nombre.trim() !== "" && !validacion.valida;

  function confirmar() {
    const texto = nombre.trim();
    if (!datosListos) {
      avisar("error", "Todavía no se cargaron tus datos. Espera un momento y vuelve a intentar.");
      return;
    }
    const resultado = validarFirmaCoincideConNombre(texto, nombres, apellidos);
    if (!resultado.valida) {
      avisar("error", resultado.motivo ?? "Esa firma no corresponde a tu nombre registrado.");
      return;
    }
    iniciarGuardado(async () => {
      try {
        const dataUrl = await generarImagenFirma(texto, estilo.familia);
        const supabase = createAdminSupabaseClient();
        const { error } = await supabase.rpc("fn_set_mi_firma", { p_dataurl: dataUrl, p_texto_firma: texto });
        if (error) throw error;
        avisar("ok", "Firma guardada.");
      } catch (e) {
        avisar("error", e instanceof Error ? e.message : "No se pudo guardar la firma.");
      }
    });
  }

  return (
    <div className="flex flex-col gap-4 rounded-lg border border-sand bg-papel p-4">
      <div>
        <Campo
          etiqueta="Tu nombre, tal como firmas"
          value={nombre}
          onChange={(e) => {
            setTocado(true);
            setNombre(e.target.value);
          }}
          placeholder="Nombres y apellidos"
          error={mostrarError ? validacion.motivo : undefined}
        />
        {datosListos && !mostrarError && (
          <p className="mt-1.5 text-xs text-taupe">
            Escribe así tu firma: <span className="font-medium text-tinta">{sugerencia}</span>
          </p>
        )}
      </div>

      <div className="flex flex-wrap gap-2">
        {ESTILOS.map((e) => (
          <button
            key={e.id}
            type="button"
            onClick={() => setEstiloId(e.id)}
            className={`rounded-control border px-3 py-1.5 text-xs font-medium transition-colors duration-150 ${
              e.id === estiloId
                ? "border-tinta bg-tinta text-crema"
                : "border-sand text-taupe hover:border-taupe/40"
            }`}
          >
            {e.etiqueta}
          </button>
        ))}
      </div>

      <div className="flex h-32 items-center justify-center rounded-control border border-dashed border-sand bg-hueso px-4">
        {nombre.trim() ? (
          <span className={estilo.clase} style={{ fontSize: 40, color: "var(--color-tinta)" }}>
            {nombre}
          </span>
        ) : (
          <span className="text-xs text-taupe">Escribe tu nombre para ver cómo queda</span>
        )}
      </div>

      <Boton
        variante="primario"
        cargando={guardando}
        disabled={!datosListos || !validacion.valida}
        onClick={confirmar}
        className="self-start"
      >
        Guardar firma
      </Boton>
    </div>
  );
}

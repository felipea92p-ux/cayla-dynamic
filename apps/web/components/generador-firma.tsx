"use client";

import { useMemo, useState, useTransition } from "react";
import { Caveat, Dancing_Script, Great_Vibes } from "next/font/google";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { generarImagenFirma } from "@/lib/firma-generador";
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
 * Montado hoy en «Mi perfil» (apps/web/app/(mio)/mio/page.tsx) porque el
 * módulo de "mis datos" todavía no existe. Cuando exista, este bloque se muda
 * ahí — el componente no asume nada de dónde vive, así que mudarlo es mover
 * el `<GeneradorFirma />` de sitio, nada más.
 */
export function GeneradorFirma({ nombreSugerido = "" }: { nombreSugerido?: string }) {
  const { avisar } = useToast();
  const [nombre, setNombre] = useState(nombreSugerido);
  const [estiloId, setEstiloId] = useState<EstiloId>("elegante");
  const [guardando, iniciarGuardado] = useTransition();

  const estilo = useMemo(() => ESTILOS.find((e) => e.id === estiloId) ?? ESTILOS[0], [estiloId]);

  function confirmar() {
    const texto = nombre.trim();
    if (!texto) {
      avisar("error", "Escribe tu nombre tal como quieres que salga en tu firma.");
      return;
    }
    iniciarGuardado(async () => {
      try {
        const dataUrl = await generarImagenFirma(texto, estilo.familia);
        const supabase = createAdminSupabaseClient();
        const { error } = await supabase.rpc("fn_set_mi_firma", { p_dataurl: dataUrl });
        if (error) throw error;
        avisar("ok", "Firma guardada.");
      } catch (e) {
        avisar("error", e instanceof Error ? e.message : "No se pudo guardar la firma.");
      }
    });
  }

  return (
    <div className="flex flex-col gap-4 rounded-lg border border-sand bg-papel p-4">
      <Campo
        etiqueta="Tu nombre, tal como firmas"
        value={nombre}
        onChange={(e) => setNombre(e.target.value)}
        placeholder="Nombres y apellidos"
      />

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

      <Boton variante="primario" cargando={guardando} onClick={confirmar} className="self-start">
        Guardar firma
      </Boton>
    </div>
  );
}

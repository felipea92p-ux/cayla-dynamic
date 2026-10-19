"use client";

// ============================================================================
// Las dos caras del DNI de quien está de prueba.
// ----------------------------------------------------------------------------
// QUÉ PROMETE. Quien registra la prueba —DO, administración o la líder de la sede
// de esa persona— sube el anverso y el reverso, y quedan en la ficha por la misma
// puerta que cualquier DNI (`fn_prueba_cargar_dni`, 0538): bucket privado, archivos
// congelados al aprobarse, historial y auditoría. La persona de prueba no tiene
// cuenta, así que no puede hacerlo ella desde «Lo mío».
//
// QUÉ NO HACE. No pide nombres, apellidos ni número: ya vienen de Equipo (0513) y
// pedirlos otra vez sería una segunda copia que tarde o temprano dice otra cosa.
//
// POR QUÉ LA CASILLA. «Lo mío» guarda la aceptación de quien sube su propio DNI
// (Ley N.° 29733: el consentimiento se pide al recolectar el dato). Aquí sube otra
// persona, así que la casilla es una DECLARACIÓN de quien registra —que la persona
// le entregó su DNI en mano y autorizó el tratamiento— y la base guarda su texto
// exacto, a nombre de la persona y diciendo quién lo declaró.
// ============================================================================

import { useEffect, useState } from "react";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { Boton } from "@/components/ui/boton";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { useToast } from "@/components/toast";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { textoConsentimientoDni } from "@/lib/admin/pruebas";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import { BUCKET_SOLICITUDES_PERFIL, CARAS_DNI, comprimirFotoDni, rutaNuevaCaraDni, type CaraDni } from "@/lib/foto-dni";

type Elegida = { archivo: File; vista: string } | null;

export function FormularioDniPrueba({
  supabase, personaId, nombre, diasPlazo, yaCargado, alGuardar,
}: {
  supabase: ClienteCayla;
  personaId: string;
  nombre: string;
  diasPlazo: number;
  /** Ya tiene las dos caras guardadas: el formulario se ofrece como «volver a subir». */
  yaCargado: boolean;
  alGuardar: () => void;
}) {
  const { avisar } = useToast();
  const [elegidas, setElegidas] = useState<Record<CaraDni, Elegida>>({ anverso: null, reverso: null });
  const [acepta, setAcepta] = useState(false);
  const [enviando, setEnviando] = useState(false);
  const [abierto, setAbierto] = useState(!yaCargado);
  const [error, setError] = useState<string | null>(null);

  // Las vistas previas son URL de objeto: se sueltan al cambiar de foto y al salir.
  useEffect(() => () => {
    for (const cara of CARAS_DNI) {
      const e = elegidas[cara.clave];
      if (e) URL.revokeObjectURL(e.vista);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- solo al desmontar.
  }, []);

  function elegir(cara: CaraDni, archivo: File | null) {
    setError(null);
    setElegidas((actual) => {
      const previa = actual[cara];
      if (previa) URL.revokeObjectURL(previa.vista);
      return { ...actual, [cara]: archivo ? { archivo, vista: URL.createObjectURL(archivo) } : null };
    });
  }

  async function enviar() {
    const { anverso, reverso } = elegidas;
    if (!anverso || !reverso) { setError("Faltan las dos caras: hay que subir el anverso y el reverso."); return; }
    if (!acepta) { setError("Marca la casilla: es la constancia de que la persona autorizó el tratamiento de su DNI."); return; }
    setError(null);
    setEnviando(true);
    try {
      const subir = async (clave: CaraDni, elegida: { archivo: File }): Promise<string | null> => {
        // JPEG en el navegador: alivia la conexión de la tienda y convierte el HEIC del iPhone
        // en algo que el bucket acepta (si no, rebota con 415 y nadie sabe por qué).
        const comprimida = await comprimirFotoDni(elegida.archivo);
        const ruta = rutaNuevaCaraDni(personaId, clave);
        const fallo = await subirArchivoConProgreso(
          supabase, BUCKET_SOLICITUDES_PERFIL, ruta, new File([comprimida], `dni-${clave}.jpg`, { type: "image/jpeg" }), () => {});
        if (fallo) { setError(`No se pudo subir el ${clave}: ${fallo}`); return null; }
        return ruta;
      };
      const rutaAnverso = await subir("anverso", anverso);
      if (rutaAnverso === null) return;
      const rutaReverso = await subir("reverso", reverso);
      if (rutaReverso === null) return;

      const { error: e } = await supabase.rpc("fn_prueba_cargar_dni", {
        p_persona_id: personaId,
        p_anverso: rutaAnverso,
        p_reverso: rutaReverso,
        p_consentimiento: textoConsentimientoDni(nombre, diasPlazo),
      });
      if (e) { setError(mensajeDeError(e, "guardar el DNI")); return; }

      for (const cara of CARAS_DNI) { const x = elegidas[cara.clave]; if (x) URL.revokeObjectURL(x.vista); }
      setElegidas({ anverso: null, reverso: null });
      setAcepta(false);
      setAbierto(false);
      avisar("ok", `DNI de ${nombre} guardado.`);
      alGuardar();
    } catch {
      setError("Alguna de las imágenes no se pudo procesar. Prueba tomando la foto otra vez.");
    } finally {
      setEnviando(false);
    }
  }

  if (!abierto) {
    return (
      <div className="flex flex-wrap items-center gap-2 text-sm">
        <span className="text-verde">✓ DNI guardado (anverso y reverso)</span>
        <Boton variante="enlace" tamano="sm" onClick={() => setAbierto(true)}>Volver a subirlo</Boton>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="grid gap-3 sm:grid-cols-2">
        {CARAS_DNI.map((cara) => {
          const elegida = elegidas[cara.clave];
          return (
            <div key={cara.clave} className="flex flex-col gap-2 rounded-control border border-sand p-3">
              <div>
                <div className="text-sm font-medium">{cara.etiqueta}</div>
                <div className="text-xs text-taupe">{cara.ayuda}</div>
              </div>
              {elegida ? (
                // eslint-disable-next-line @next/next/no-img-element -- vista previa local de un archivo recién elegido
                <img src={elegida.vista} alt={`${cara.etiqueta} del DNI de ${nombre}`} className="h-32 w-full rounded-control border border-sand bg-hueso object-contain" />
              ) : (
                <div className="flex h-32 items-center justify-center rounded-control border border-dashed border-sand bg-hueso px-3 text-center text-xs text-taupe">
                  Todavía no hay foto
                </div>
              )}
              <label className="flex flex-col gap-1 text-xs text-taupe">
                {elegida ? "Elegir otra" : "Elegir foto"}
                {/* Solo imágenes, y sin `capture`: se puede elegir una de la galería. */}
                <input
                  type="file" accept="image/*" disabled={enviando}
                  data-cara={cara.clave}
                  onChange={(e) => elegir(cara.clave, e.target.files?.[0] ?? null)}
                  className="w-full min-w-0 text-xs file:mr-2 file:rounded-control file:border file:border-sand file:bg-hueso file:px-2 file:py-1 file:text-xs"
                />
              </label>
            </div>
          );
        })}
      </div>

      <label className="flex items-start gap-2 rounded-control bg-hueso px-3 py-2 text-xs text-taupe">
        <input type="checkbox" checked={acepta} disabled={enviando} onChange={(e) => setAcepta(e.target.checked)} className="mt-0.5" />
        <span>
          <span className="font-medium text-tinta">Confirmo, como quien registra la prueba, que:</span>{" "}
          {textoConsentimientoDni(nombre, diasPlazo)}
        </span>
      </label>

      {error && <BannerAviso enLinea variante="alerta">{error}</BannerAviso>}

      <div className="flex flex-wrap gap-2">
        <Boton variante="primario" onClick={() => void enviar()} cargando={enviando}>Guardar el DNI</Boton>
        {yaCargado && <Boton onClick={() => setAbierto(false)} disabled={enviando}>Cancelar</Boton>}
      </div>
    </div>
  );
}

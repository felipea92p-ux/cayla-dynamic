"use client";

// Qué novedades del sistema ya entendió esta persona (`novedades_vistas`, 0480).
//
// Lo usan las dos pantallas donde se ven las novedades —«Lo mío» y Anuncios—, y
// las dos tienen que contestar igual a «¿esta ya la entendí?»: por eso la
// pregunta vive acá y no en cada una. Si cada pantalla guardara su propia
// respuesta, marcarla en una la dejaría pendiente en la otra.
//
// `vistas === null` significa «no sé», y es distinto de «no marqué ninguna»
// (un conjunto vacío). Se queda en `null` mientras carga y si la lectura
// falla —por ejemplo, si esta pantalla llegó a producción antes de que se
// pegara la 0480—. Quien lo usa decide qué hacer sin saber: «Lo mío» calla, y
// Anuncios muestra por fecha. Confundir los dos casos sería tratar un fallo
// como «todas pendientes» y repetirle a alguien lo que ya entendió.

import { useCallback, useEffect, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { useToast } from "@/components/toast";
import { mensajeDeError } from "@/lib/admin/mensaje-error";

/**
 * `activo` es «ya hay una sesión con persona»: sin ella la lectura devolvería un
 * error de permisos que no dice nada de las novedades.
 */
export function useNovedadesVistas(activo: boolean) {
  const { avisar } = useToast();
  const [vistas, setVistas] = useState<ReadonlySet<string> | null>(null);

  useEffect(() => {
    if (!activo) return;
    let vivo = true;
    // La política de la tabla ya limita a las marcas propias: no hace falta filtrar por persona.
    void createAdminSupabaseClient()
      .from("novedades_vistas")
      .select("novedad_id")
      .then(({ data, error }) => {
        if (!vivo || error || !data) return;
        setVistas(new Set(data.map((f) => f.novedad_id)));
      });
    return () => { vivo = false; };
  }, [activo]);

  const marcar = useCallback(async (id: string) => {
    // Optimista: el botón cambia al instante. Pero si la base la rechaza se
    // DESHACE y se avisa: dejarla oculta cuando no quedó guardada sería que la
    // novedad reaparezca mañana sin que nadie entienda por qué.
    setVistas((prev) => (prev ? new Set(prev).add(id) : prev));
    const { error } = await createAdminSupabaseClient().rpc("fn_marcar_novedad_vista", { p_novedad_id: id });
    if (error) {
      setVistas((prev) => {
        if (!prev) return prev;
        const sin = new Set(prev);
        sin.delete(id);
        return sin;
      });
      avisar("error", mensajeDeError(error, "marcar la novedad como entendida"));
    }
  }, [avisar]);

  return { vistas, marcar };
}

"use client";

import { useEffect, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";

export interface PersonaActual {
  id: string;
  rol: string;
  sedeBaseId: string;
  nombreCompleto: string;
  /**
   * Tiene contrato de trabajo (planilla o periodo de prueba). El rol dice qué
   * se abre; esto dice si puede ejercer poder disciplinario (RIT 2.9, 0510):
   * lo consulta `puedeTramitarDisciplina`.
   */
  enPlanilla: boolean;
}

/** Rol de la persona autenticada, o null mientras carga. */
export function useRolActual(): string | null {
  return usePersonaActual()?.rol ?? null;
}

// Quién es la persona de la sesión se pide UNA vez por pestaña y se reparte. Al abrir
// /mio, tres componentes (los acuses, los anuncios y las novedades) llamaban a este
// hook a la vez, y cada uno hacía su propio viaje al servidor de autenticación más su
// propia lectura de `personas`: seis rondas para saber lo mismo. Medido el 2026-10-24.
//
// La respuesta vale unos segundos y no más: alcanza para que varios componentes que
// aparecen juntos compartan el viaje, y es tan corta que un cambio de rol hecho por DO
// se ve en la siguiente pantalla, no «cuando se recargue». Si la lectura falla o no hay
// ficha, no se recuerda nada: el siguiente componente lo intenta de nuevo.
const VIGENCIA_PERSONA_MS = 15_000;
let personaEnCurso: { uid: string; desde: number; promesa: Promise<PersonaActual | null> } | null = null;

type ClienteAdmin = ReturnType<typeof createAdminSupabaseClient>;

async function traerPersonaActual(supabase: ClienteAdmin): Promise<PersonaActual | null> {
  // El id sale del almacén de la sesión, sin viajar a la red. `getUser()` era un viaje
  // entero al servidor de autenticación solo para leer este mismo dato; la base valida
  // el token en cada consulta, así que una sesión que ya no sirve no devuelve ficha.
  const { data } = await supabase.auth.getSession();
  const uid = data.session?.user.id;
  if (!uid) return null;

  if (personaEnCurso && personaEnCurso.uid === uid && Date.now() - personaEnCurso.desde < VIGENCIA_PERSONA_MS) {
    return personaEnCurso.promesa;
  }
  const promesa = (async (): Promise<PersonaActual | null> => {
    const { data: p } = await supabase
      .from("personas")
      .select("id, rol, sede_base_id, nombres, apellidos, en_planilla")
      .eq("auth_user_id", uid)
      .maybeSingle();
    if (!p) return null;
    return {
      id: p.id as string,
      rol: p.rol as string,
      sedeBaseId: p.sede_base_id as string,
      nombreCompleto: `${p.nombres as string} ${p.apellidos as string}`,
      // Sin dato, NO: un vínculo desconocido no puede abrir un poder disciplinario.
      enPlanilla: p.en_planilla === true,
    };
  })();
  const registro = { uid, desde: Date.now(), promesa };
  personaEnCurso = registro;
  const olvidarSiFallo = (r: PersonaActual | null) => { if (r === null && personaEnCurso === registro) personaEnCurso = null; };
  void promesa.then(olvidarSiFallo, () => olvidarSiFallo(null));
  return promesa;
}

/** Datos de la persona autenticada en el panel (id, rol, sede, nombre), o null mientras carga. */
export function usePersonaActual(): PersonaActual | null {
  const [persona, setPersona] = useState<PersonaActual | null>(null);

  useEffect(() => {
    let vivo = true;
    void traerPersonaActual(createAdminSupabaseClient()).then((p) => { if (vivo && p) setPersona(p); });
    return () => { vivo = false; };
  }, []);

  return persona;
}

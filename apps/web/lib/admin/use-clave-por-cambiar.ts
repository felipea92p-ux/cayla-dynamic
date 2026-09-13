"use client";

import { useEffect } from "react";
import { usePathname, useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { clavePorCambiar } from "./mi-clave";

// ============================================================================
// El guardia de «tienes que cambiar tu clave antes de seguir»
// ============================================================================
// POR QUÉ NO BASTA CON REDIRIGIR DESDE EL LOGIN, que fue lo primero que hice:
// una redirección se esquiva escribiendo otra dirección en la barra. Con estas
// cuentas eso no es una travesura — son las que ven la planilla entera, los
// sueldos por persona y el padrón con documentos.
//
// La marca vive en `app_metadata` del token, o sea que la escribe SOLO el
// servidor y viaja con la sesión. `user_metadata` no habría servido: la puede
// escribir la propia persona desde el navegador con `updateUser({ data })`.
//
// Se monta dentro de `MarcoAdmin` (apps/web/app/(admin)/admin/nav.tsx), que
// desde el 2026-09-07 monta el layout del grupo `(admin)` una sola vez. Ese
// layout es un componente de servidor y no ve la sesión, así que no puede hacer
// esto por su cuenta: lo hace el marco, que sí es de cliente. Y solo corre en
// las rutas CON marco — en el login y en «olvidé mi clave» no hay sesión que
// mirar todavía (ver RUTAS_SIN_MARCO en admin/nav-items.ts).
//
// NO se pone en el terminal, y es a propósito: el terminal marca sin clave
// (decisión de Felipe, jul-2026) y no tiene ninguna sesión de persona que
// empujar a ningún sitio.
// ============================================================================

/** Si esta sesión trae la marca puesta, lleva a elegir una clave y no suelta. */
export function useClavePorCambiar(): void {
  const router = useRouter();
  const pathname = usePathname();

  useEffect(() => {
    // La propia pantalla de cambiar la clave queda fuera, obviamente: mandarla
    // a sí misma sería un bucle y nadie podría salir nunca de la marca.
    if (pathname?.startsWith("/admin/nueva-clave")) return;
    let vivo = true;
    void createAdminSupabaseClient()
      .auth.getUser()
      .then(({ data }) => {
        if (vivo && clavePorCambiar(data.user)) {
          router.replace("/admin/nueva-clave?motivo=temporal");
        }
      });
    return () => { vivo = false; };
  }, [router, pathname]);
}

"use client";

// El marco con vidrio del panel. Toma lo que `nav.tsx` ya resolvió —quién entró, qué ve, cuántas cosas esperan— y se lo da al marco. No vuelve
// a decidir nada de eso: solo se monta con el interruptor encendido, así que su consulta de la foto y la sede no corre apagado.
//
// Caída de la base: esa consulta es lo único que este componente pide. Si no responde, la placa se queda con el nombre y el rol, y la sede
// no se muestra. No se pierde nada ni se bloquea el menú.

import { useEffect, useMemo, useState, type ReactNode } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { ROL_LABELS, ROLES_CON_PANEL, ROLES_DO } from "@cayla-dynamic/shared";
import { esActivo, type Grupo } from "@/app/(admin)/admin/nav-items";
import type { Contadores } from "@/components/nav/panel-navegacion";
import type { PersonaActual } from "@/lib/admin/use-rol";
import { urlPublicaFotoPerfil } from "@/lib/foto-perfil";
import { armarFilas, type HojaMenu } from "@/lib/vidrio-menu";
import { MarcoVidrio } from "@/components/vidrio/marco";

/** Una sola frase para las dos filas: el número de un módulo ya está contado en Bandeja, y sumarlos daría de más. */
const NOTA_DE_LA_SUMA = "Ya están contados en Bandeja";

export function MarcoPanelVidrio({
  persona,
  grupos,
  pathname,
  contadores,
  onSalir,
  onBuscar,
  children,
}: {
  persona: PersonaActual | null;
  /** Ya filtrados por rol. */
  grupos: Grupo[];
  pathname: string;
  contadores: Contadores;
  onSalir: () => void;
  onBuscar: () => void;
  children: ReactNode;
}) {
  const [extra, setExtra] = useState<{ fotoUrl: string | null; sede: string | null } | null>(null);
  const id = persona?.id;
  useEffect(() => {
    if (!id) return;
    let vivo = true;
    const supabase = createAdminSupabaseClient();
    supabase
      .from("personas")
      .select("foto_url, sedes!personas_sede_base_id_fkey(nombre)")
      .eq("id", id)
      .maybeSingle()
      .then(
        ({ data }) => {
          if (!vivo || !data) return;
          const sede = (data as unknown as { sedes: { nombre: string } | null }).sedes?.nombre ?? null;
          setExtra({ fotoUrl: urlPublicaFotoPerfil(supabase, (data as { foto_url: string | null }).foto_url), sede });
        },
        () => {},
      );
    return () => {
      vivo = false;
    };
  }, [id]);

  const filas = useMemo(
    () =>
      armarFilas(
        grupos.map((g) => ({
          label: g.label,
          corto: g.corto,
          Icon: g.Icon,
          hojas: g.items.map((it): HojaMenu => {
            const cuenta = it.contador ? contadores[it.contador] : undefined;
            return { id: it.href, etiqueta: it.label, Icon: it.Icon, href: it.href, n: cuenta?.n ?? 0, titulo: cuenta?.titulo };
          }),
        })),
      ),
    [grupos, contadores],
  );
  const activa = grupos.flatMap((g) => g.items).find((it) => esActivo(pathname, it.href))?.href ?? null;

  const rol = persona?.rol ?? "";
  const rolEnPantalla = persona ? (ROL_LABELS[rol] ?? "Integrante") : "";
  const conPanel = ROLES_CON_PANEL.some((r) => r === rol);

  return (
    <MarcoVidrio
      filas={filas}
      activa={activa}
      etiquetaMenu="Navegación principal"
      notaDeSuma={NOTA_DE_LA_SUMA}
      hrefInicio={conPanel ? "/admin/dashboard" : "/mio"}
      persona={
        persona
          ? {
              nombre: persona.nombreCompleto,
              detalle: [rolEnPantalla, extra?.sede].filter(Boolean).join(" · "),
              fotoUrl: extra?.fotoUrl,
            }
          : null
      }
      placaHref="/mio"
      onSalir={onSalir}
      etiquetaBuscador="Buscar"
      onBuscar={onBuscar}
      sede={ROLES_DO.includes(rol) ? null : extra?.sede}
    >
      {children}
    </MarcoVidrio>
  );
}

"use client";

// Los feriados nacionales del AÑO del periodo. Planilla es el único lugar del
// panel donde se agregan o se quitan (la pantalla Feriados gestiona los
// feriados trabajados y el descanso sustitutorio, no el calendario). Salió de
// la cabecera de Planilla el 2026-09-15 porque se leía como un dato del
// periodo, y no lo es: cambia el pago de las cuatro sedes y de todo el año.

import { useCallback, useEffect, useState, type RefObject } from "react";
import type { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { hoyLima } from "@cayla-dynamic/shared";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { useToast } from "@/components/toast";
import { Drawer } from "@/components/ui/drawer";
import { Boton } from "@/components/ui/boton";
import { Campo } from "@/components/ui/campo";
import { Cargando, SinDatos } from "@/components/cargando";
import { fechaCorta } from "@/lib/admin/planilla/formato";
import type { Feriado } from "@/lib/admin/planilla/tipos";

type Supabase = ReturnType<typeof createAdminSupabaseClient>;

/** Nace con una fecha visible (regla de CLAUDE.md): hoy si es del mismo año, si no el 1 de enero. */
function fechaInicial(anio: number): string {
  const hoy = hoyLima();
  return hoy.startsWith(String(anio)) ? hoy : `${anio}-01-01`;
}

export function PanelFeriados({ abierto, onCerrar, volverElFocoA, anio, supabase, onCambio }: {
  abierto: boolean;
  onCerrar: () => void;
  volverElFocoA: RefObject<HTMLElement | null>;
  anio: number;
  supabase: Supabase;
  onCambio: () => Promise<void>;
}) {
  const { avisar } = useToast();
  const [lista, setLista] = useState<Feriado[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [nuevo, setNuevo] = useState({ fecha: fechaInicial(anio), nombre: "" });
  const [guardando, setGuardando] = useState(false);
  const [quitando, setQuitando] = useState<Feriado | null>(null);

  // Se TRAE sin tocar el estado y se APLICA aparte: el efecto de apertura solo escribe desde la respuesta.
  const traer = useCallback(async () => supabase.rpc("fn_feriados", { p_anio: anio }), [supabase, anio]);
  const aplicar = useCallback(({ data, error: e }: { data: unknown; error: { message: string } | null }) => {
    setError(e ? e.message : null);
    setLista(e ? null : ((data as Feriado[] | null) ?? []));
  }, []);
  const cargar = useCallback(async () => aplicar(await traer()), [traer, aplicar]);

  useEffect(() => {
    if (!abierto) return;
    let vigente = true;
    void traer().then((r) => { if (vigente) aplicar(r); });
    return () => { vigente = false; };
  }, [abierto, traer, aplicar]);

  async function agregar() {
    if (!nuevo.fecha || nuevo.nombre.trim().length < 2) {
      avisar("error", "Pon la fecha y el nombre del feriado.");
      return;
    }
    setGuardando(true);
    const { error: e } = await supabase.rpc("fn_set_feriado", { p_fecha: nuevo.fecha, p_nombre: nuevo.nombre.trim() });
    setGuardando(false);
    if (e) { avisar("error", mensajeDeError(e, "guardar el feriado")); return; }
    setNuevo({ fecha: fechaInicial(anio), nombre: "" });
    avisar("ok", "Feriado guardado.");
    await Promise.all([cargar(), onCambio()]);
  }

  async function quitar(f: Feriado) {
    setGuardando(true);
    const { error: e } = await supabase.rpc("fn_quitar_feriado", { p_fecha: f.fecha });
    setGuardando(false);
    setQuitando(null);
    if (e) { avisar("error", mensajeDeError(e, "quitar el feriado")); return; }
    avisar("ok", "Feriado quitado.");
    await Promise.all([cargar(), onCambio()]);
  }

  return (
    <Drawer abierto={abierto} onCerrar={onCerrar} titulo={`Feriados nacionales de ${anio}`} volverElFocoA={volverElFocoA} bloqueado={guardando}>
      <p className="mb-4 text-sm text-taupe">
        Solo feriados nacionales por ley: cada uno paga el proporcional a quien está en planilla, y doble a quien lo trabaja.
        Afecta a las cuatro sedes y a cualquier periodo abierto que lo contenga; en un periodo ya pagado, la base no deja cambiarlo.
      </p>
      {error ? (
        <p className="text-sm text-rojo-profundo">
          No se pudieron cargar los feriados: {error}{" "}
          <Boton variante="enlace" onClick={() => void cargar()}>Reintentar</Boton>
        </p>
      ) : lista === null ? (
        <Cargando />
      ) : lista.length === 0 ? (
        <SinDatos texto="No hay feriados registrados este año." pista="Sin ellos, el pago por feriado no se calcula." />
      ) : (
        <ul className="mb-4">
          {lista.map((f) => (
            <li key={f.fecha} className="border-b border-sand/60 py-2 text-sm">
              <div className="flex items-center justify-between gap-3">
                <span><span className="text-taupe">{fechaCorta(f.fecha)}</span> — {f.nombre}</span>
                <Boton variante="enlace" className="text-xs text-rojo" onClick={() => setQuitando(f)} disabled={guardando}>Quitar</Boton>
              </div>
              {quitando?.fecha === f.fecha && (
                <div className="mt-2 rounded-control border border-rojo/30 bg-rojo/[0.05] p-3">
                  <p className="mb-2">¿Quitar «{f.nombre}»? La planilla dejará de pagarlo como feriado.</p>
                  <div className="flex justify-end gap-2">
                    <Boton tamano="sm" onClick={() => setQuitando(null)} disabled={guardando}>Cancelar</Boton>
                    <Boton tamano="sm" variante="peligro" onClick={() => void quitar(f)} cargando={guardando}>Quitar</Boton>
                  </div>
                </div>
              )}
            </li>
          ))}
        </ul>
      )}
      <div className="grid gap-3 border-t border-sand pt-4">
        <Campo etiqueta="Fecha" type="date" value={nuevo.fecha} onChange={(e) => setNuevo({ ...nuevo, fecha: e.target.value })} />
        <Campo etiqueta="Nombre" value={nuevo.nombre} onChange={(e) => setNuevo({ ...nuevo, nombre: e.target.value })} placeholder="ej. Fiestas Patrias" />
        <div className="flex justify-end">
          <Boton variante="primario" onClick={() => void agregar()} cargando={guardando}>Agregar feriado</Boton>
        </div>
      </div>
    </Drawer>
  );
}

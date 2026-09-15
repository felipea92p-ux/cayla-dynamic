"use client";

import { useCallback, useEffect, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { ROLES_DO } from "@cayla-dynamic/shared";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { Cargando } from "@/components/cargando";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { Boton } from "@/components/ui/boton";
import { Campo } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { Modal } from "@/components/ui/modal";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { SubnavPoliticaSalarial } from "../_subnav";
import { NOMBRE_RANGO, categoriasFueraDeOrden, type CategoriaCuadro, type Cuadro } from "@/lib/politica-salarial";

// Hasta esta pantalla, `salario_declarado` (0145) y el resto del cuadro
// (0140) solo se editaban pegando un UPDATE a mano en el SQL Editor — auditado
// el 2026-09-15: ni siquiera había una pantalla que llamara a `fn_set_categoria`
// para los otros campos. Esto es lo que hace "administrable" al documento que
// pediste, no solo "publicable".

interface Formulario {
  rango: string;
  proposito: string;
  funciones: string;
  requisitos: string;
  criterio: string;
  salario_declarado: string;
}

function aFormulario(c: CategoriaCuadro): Formulario {
  return {
    rango: c.rango,
    proposito: c.proposito ?? "",
    funciones: c.funciones ?? "",
    requisitos: c.requisitos ?? "",
    criterio: c.criterio ?? "",
    salario_declarado: c.salario_declarado !== null && c.salario_declarado !== undefined ? String(c.salario_declarado) : "",
  };
}

function soles(n: number | string | null | undefined): string {
  if (n === null || n === undefined) return "—";
  const v = typeof n === "string" ? Number(n) : n;
  return Number.isFinite(v) ? `S/ ${v.toFixed(2)}` : "—";
}

export default function CategoriasPoliticaSalarialPage() {
  useTituloDocumento("Categorías · Política salarial");
  const persona = usePersonaActual();
  const esDO = persona !== null && ROLES_DO.includes(persona.rol);

  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [cuadro, setCuadro] = useState<Cuadro | null>(null);
  const [editando, setEditando] = useState<Formulario | null>(null);
  const [guardando, setGuardando] = useState(false);

  // useCallback: la reutiliza `guardar()` para refrescar después de editar.
  // El efecto de montaje, abajo, pide el mismo dato en línea — llamar desde
  // un efecto a una función que termina en un setState dispara el lint
  // react-hooks/set-state-in-effect (ver admin/objetivos/page.tsx).
  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    setError(null);
    const { data, error: e } = await supabase.rpc("fn_cuadro_categorias");
    if (e !== null) { setError(mensajeDeError(e, "cargar las categorías")); setCargando(false); return; }
    setCuadro(data as unknown as Cuadro);
    setCargando(false);
  }, []);

  useEffect(() => {
    const cancelado = { actual: false };
    (async () => {
      const supabase = createAdminSupabaseClient();
      setError(null);
      const { data, error: e } = await supabase.rpc("fn_cuadro_categorias");
      if (cancelado.actual) return;
      if (e !== null) { setError(mensajeDeError(e, "cargar las categorías")); setCargando(false); return; }
      setCuadro(data as unknown as Cuadro);
      setCargando(false);
    })();
    return () => { cancelado.actual = true; };
  }, []);

  const guardar = async () => {
    if (editando === null) return;
    const monto = Number(editando.salario_declarado);
    if (editando.salario_declarado.trim() !== "" && (!Number.isFinite(monto) || monto <= 0)) {
      setError("El monto declarado tiene que ser un número mayor a cero.");
      return;
    }
    setGuardando(true); setError(null); setAviso(null);
    const supabase = createAdminSupabaseClient();
    const { error: e } = await supabase.rpc("fn_set_categoria", {
      p_rango: editando.rango,
      p_proposito: editando.proposito,
      p_funciones: editando.funciones,
      p_requisitos: editando.requisitos,
      p_criterio: editando.criterio,
      p_salario_declarado: editando.salario_declarado.trim() === "" ? null : monto,
    });
    if (e !== null) {
      setError(mensajeDeError(e, "guardar la categoría"));
    } else {
      setAviso(`${NOMBRE_RANGO[editando.rango] ?? editando.rango} se actualizó. Publica una versión nueva en Versiones y publicación para que el equipo lo vea.`);
      setEditando(null);
      await cargar();
    }
    setGuardando(false);
  };

  if (cargando) return <Cargando />;

  if (persona !== null && !esDO) {
    return (
      <main className="mx-auto max-w-2xl px-4 py-8">
        <p className="rounded-superficie border border-sand bg-papel px-4 py-6 text-sm text-taupe">
          Esta pantalla es solo para quien puede administrar el cuadro de categorías.
        </p>
      </main>
    );
  }

  const fueraDeOrden = cuadro ? categoriasFueraDeOrden(cuadro.categorias) : [];

  return (
    <main className="mx-auto max-w-4xl px-4 py-8">
      <CabeceraPagina titulo="Categorías" descripcion="Propósito, funciones, requisitos, criterio y monto declarado de cada categoría." />
      <SubnavPoliticaSalarial />

      {error !== null && <p className="mb-4 rounded-control border border-rojo/30 bg-rojo/10 px-4 py-3 text-sm text-rojo">{error}</p>}
      {aviso !== null && <p className="mb-4 rounded-control border border-verde/25 bg-verde/10 px-4 py-3 text-sm text-verde">{aviso}</p>}
      {fueraDeOrden.length > 0 && (
        <p className="mb-4 rounded-control border border-ambar/40 bg-ambar/10 px-4 py-3 text-sm text-ambar">
          La escala no sube con la categoría en: {fueraDeOrden.join(", ")}.
        </p>
      )}

      <div className="flex flex-col gap-3">
        {cuadro?.categorias.map((c) => (
          <div key={c.rango} className="flex flex-wrap items-start justify-between gap-4 rounded-superficie border border-sand bg-papel p-4">
            <div className="min-w-0 flex-1">
              <div className="font-serif text-lg text-tinta">{NOMBRE_RANGO[c.rango] ?? c.rango}</div>
              <p className="mt-1 text-sm text-taupe">{c.proposito || "Sin propósito escrito."}</p>
              <p className="mt-2 text-sm font-medium text-rojo">{soles(c.salario_declarado)} declarado</p>
              {c.salario_min !== null && c.salario_max !== null && (
                <p className="text-xs text-taupe">Sueldos reales hoy: {soles(c.salario_min)} a {soles(c.salario_max)} ({c.personas} {c.personas === 1 ? "persona" : "personas"})</p>
              )}
            </div>
            <Boton variante="secundario" tamano="sm" onClick={() => setEditando(aFormulario(c))}>Editar</Boton>
          </div>
        ))}
      </div>

      <Modal abierto={editando !== null} onCerrar={() => setEditando(null)} titulo={editando ? `Editar ${NOMBRE_RANGO[editando.rango] ?? editando.rango}` : undefined} ancho="lg" bloqueado={guardando}>
        {editando && (
          <form onSubmit={(e) => { e.preventDefault(); void guardar(); }} className="flex flex-col gap-4">
            <Campo
              etiqueta="Monto declarado (S/ mensual)"
              type="number" step="0.01" min="0.01"
              value={editando.salario_declarado}
              onChange={(e) => setEditando({ ...editando, salario_declarado: e.target.value })}
              placeholder="Sin monto declarado"
            />
            <AreaTexto etiqueta="Propósito" rows={2} value={editando.proposito} onChange={(e) => setEditando({ ...editando, proposito: e.target.value })} />
            <AreaTexto etiqueta="Funciones (una por línea)" rows={5} value={editando.funciones} onChange={(e) => setEditando({ ...editando, funciones: e.target.value })} />
            <AreaTexto etiqueta="Requisitos (uno por línea)" rows={3} value={editando.requisitos} onChange={(e) => setEditando({ ...editando, requisitos: e.target.value })} />
            <AreaTexto etiqueta="Por qué vale más que la anterior" rows={3} value={editando.criterio} onChange={(e) => setEditando({ ...editando, criterio: e.target.value })} />
            <div className="flex justify-end gap-2">
              <Boton type="button" variante="secundario" onClick={() => setEditando(null)}>Cancelar</Boton>
              <Boton type="submit" variante="primario" cargando={guardando}>Guardar</Boton>
            </div>
          </form>
        )}
      </Modal>
    </main>
  );
}

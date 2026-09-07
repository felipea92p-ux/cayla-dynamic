"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { Cargando } from "@/components/cargando";
import { BoletaHoja } from "@/components/boleta-hoja";
import { MESES_LARGO, type Fila, type Proyeccion } from "@/app/(admin)/admin/planilla/page";
import { hoyLima } from "@cayla-dynamic/shared";

// Tu boleta, en autoservicio (0339) — SOLO el periodo actual, nunca uno pasado.
//
// POR QUÉ NO HAY PARÁMETROS EN LA URL. La boleta de admin acepta
// `?periodo=&persona=` porque una sola pantalla sirve para mirar a cualquiera
// en cualquier periodo. Esta pantalla es "la mía, la de ahora": siempre la
// propia persona (`fn_persona_actual_id()`, del lado del servidor — nunca un
// id que viaje en la URL) y siempre el periodo que contiene hoy. No hay nada
// que elegir, así que no hay nada que parametrizar.
//
// POR QUÉ SOLO EL PERIODO ACTUAL. Pedido explícito de Felipe (2026-08-31):
// los periodos ya cerrados arrastraron errores de cálculo reales —ya
// corregidos en el código— que su foto congelada (`planilla_pagada_detalle`)
// no siempre recalculó. El periodo actual, en cambio, sale del cálculo en
// vivo con la lógica de HOY. `fn_planilla_calcular_persona` hace cumplir esto
// del lado del servidor (0339): pedir un periodo pasado desde autoservicio se
// rechaza ahí, no aquí — esta pantalla ni siquiera lo intenta.
//
// LA HOJA (BoletaHoja) ES LA MISMA que usa admin/planilla/boleta: mismo
// componente, mismo texto legal, para que nunca pinten dos versiones
// distintas del mismo documento. Ver components/boleta-hoja.tsx.
function MiBoletaContenido() {
  const router = useRouter();
  const supabase = createAdminSupabaseClient();

  const [yo, setYo] = useState<{
    id: string;
    nombre: string;
    documento: string | null;
    fechaIngreso: string | null;
    sueldoBaseLegal: number | null;
  } | null>(null);
  const [periodo, setPeriodo] = useState<{ id: string; fecha_ini: string; fecha_fin: string } | null>(null);
  const [fila, setFila] = useState<(Fila & { sin_datos?: boolean }) | null>(null);
  const [fuente, setFuente] = useState<"foto" | "calculo" | null>(null);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const cargar = useCallback(async () => {
    setCargando(true);
    setError(null);

    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) {
      router.replace("/mio");
      return;
    }

    const { data: sesionAuth } = await supabase.auth.getUser();
    const uid = sesionAuth.user?.id;
    if (!uid) {
      setCargando(false);
      setError("No se pudo leer tu sesión. Vuelve a entrar.");
      return;
    }

    const { data: p } = await supabase
      .from("personas")
      .select("id, nombres, apellidos, documento, fecha_ingreso, sueldo_base_legal")
      .eq("auth_user_id", uid)
      .maybeSingle();
    if (!p) {
      setCargando(false);
      setError("Tu cuenta todavía no está enlazada con tu ficha. Avisa a Desarrollo Organizacional.");
      return;
    }
    const yoActual = {
      id: p.id as string,
      nombre: `${p.nombres as string} ${p.apellidos as string}`,
      documento: (p.documento as string | null) ?? null,
      fechaIngreso: (p.fecha_ingreso as string | null) ?? null,
      sueldoBaseLegal: (p.sueldo_base_legal as number | null) ?? null,
    };
    setYo(yoActual);

    // El periodo de pago en curso. Del 29 al 28, LEÍDO y nunca calculado —
    // mismo criterio que /mio (irAlPeriodoDePago).
    const hoy = hoyLima();
    const { data: per } = await supabase
      .from("periodos_planilla")
      .select("id, fecha_ini, fecha_fin")
      .lte("fecha_ini", hoy).gte("fecha_fin", hoy)
      .maybeSingle();
    if (!per) {
      setCargando(false);
      setPeriodo(null);
      setError("No hay un periodo de pago abierto hoy. Vuelve a intentarlo cuando empiece el siguiente.");
      return;
    }
    const periodoActual = per as { id: string; fecha_ini: string; fecha_fin: string };
    setPeriodo(periodoActual);

    const { data: f, error: eFila } = await supabase.rpc("fn_planilla_calcular_persona", {
      p_persona_id: yoActual.id,
      p_periodo_id: periodoActual.id,
    });
    setCargando(false);
    if (eFila) {
      setError(eFila.message);
      return;
    }
    const { fuente: f2, ...resto } = (f ?? {}) as unknown as Fila & { fuente: "foto" | "calculo"; sin_datos?: boolean };
    setFila(resto as Fila & { sin_datos?: boolean });
    setFuente(f2 ?? null);
  }, [supabase, router]);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargar(); }, [cargar]);

  const sinDatos = fila?.sin_datos === true;

  useTituloDocumento(
    yo && periodo && fila && !sinDatos
      ? `${yo.nombre} — Boleta interna ${MESES_LARGO[Number(periodo.fecha_fin.slice(5, 7)) - 1]} ${periodo.fecha_fin.slice(0, 4)}`
      : null,
  );

  if (cargando) {
    return (
      <main className="p-6">
        <Cargando />
      </main>
    );
  }

  if (error) {
    return (
      <main className="p-6">
        <p className="max-w-md rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
          {error}{" "}
          <button onClick={() => void cargar()} className="font-medium underline">
            Reintentar
          </button>
        </p>
        <Link href="/mio" className="mt-3 inline-block text-sm text-taupe hover:text-tinta hover:underline">
          ← Volver a Lo mío
        </Link>
      </main>
    );
  }

  if (!yo || !periodo || !fila || sinDatos) {
    return (
      <main className="p-6">
        <p className="max-w-md rounded-lg bg-sand/40 px-4 py-3 text-sm text-taupe">
          Todavía no hay datos de tu planilla para este periodo. Si ya deberías tener marcajes, avisa a
          Desarrollo Organizacional.
        </p>
        <Link href="/mio" className="mt-3 inline-block text-sm text-taupe hover:text-tinta hover:underline">
          ← Volver a Lo mío
        </Link>
      </main>
    );
  }

  // `anio_etiqueta`/`mes_etiqueta` se derivan de `fecha_fin` con el mismo
  // criterio que `fn_periodos()` (extract(year/month from fecha_fin)) — nunca
  // con un Date: un date-only string parseado como UTC y leído en hora local
  // puede caer un día antes en Lima (UTC-5). Partir el string es lo mismo
  // cálculo, sin esa trampa.
  // `base_horas` no viene en el jsonb de `fn_planilla_calcular_persona`: es una
  // cifra del periodo, no de la persona, y esa función solo devuelve su fila.
  // Se recalcula acá con la MISMA fórmula del núcleo (0339, `v_dias := (p_fin -
  // p_ini) + 1; v_base := 6.5 * v_dias`) porque `periodo` es la fila real de
  // `periodos_planilla` — no hay margen para que diverja del valor que el
  // servidor ya usó para calcular esta boleta.
  const dias = Math.round(
    (new Date(`${periodo.fecha_fin}T00:00:00Z`).getTime() -
      new Date(`${periodo.fecha_ini}T00:00:00Z`).getTime()) /
      86_400_000,
  ) + 1;

  const proy: Pick<Proyeccion, "estado" | "pagado_at" | "simulacion" | "fecha_ini" | "fecha_fin" | "anio_etiqueta" | "mes_etiqueta" | "base_horas"> = {
    estado: fuente === "foto" ? "pagado" : "abierto",
    pagado_at: null,
    simulacion: false,
    fecha_ini: periodo.fecha_ini,
    fecha_fin: periodo.fecha_fin,
    anio_etiqueta: Number(periodo.fecha_fin.slice(0, 4)),
    mes_etiqueta: Number(periodo.fecha_fin.slice(5, 7)),
    base_horas: 6.5 * dias,
  };

  return (
    <main className="mx-auto max-w-2xl p-6 print:p-0">
      <div className="mb-6 flex items-center justify-between print:hidden">
        <Link href="/mio" className="text-sm text-taupe hover:text-tinta hover:underline">
          ← Volver a Lo mío
        </Link>
        <button
          onClick={() => window.print()}
          className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema hover:bg-rojo-profundo"
        >
          Imprimir / Guardar como PDF
        </button>
      </div>

      <BoletaHoja
        f={fila as Fila}
        proy={proy}
        baseLegal={yo.sueldoBaseLegal}
        documento={yo.documento}
        fechaIngreso={yo.fechaIngreso}
      />
    </main>
  );
}

export default function MiBoletaPage() {
  return <MiBoletaContenido />;
}

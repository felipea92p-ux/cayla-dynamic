"use client";

import { useCallback, useMemo, useRef, useState } from "react";
import type { createAdminSupabaseClient } from "@cayla-dynamic/database";
import {
  NADA_TRAIDO, SELECT_CONSTANCIAS, constanciasPorFamilia, todasLasPaginas, familiaCompleta, filtroDelRango, mesCubierto,
  rangoCubierto, rangosQueFaltan, sumarConstancias, unirRangos,
  type ConstanciasTraidas, type FilaDeConstancia, type Pagina, type RangoDeMeses,
} from "./educacion-carga";
import { mesDe, sumarMeses } from "./educacion-meses";
import type { EntregaDeFamilia } from "./educacion-tipos";

/**
 * LAS CONSTANCIAS DE LA CUADRÍCULA DE EDUCACIÓN, PEDIDAS POR MESES — la mitad que habla con Supabase.
 *
 * PROMETE:
 *   · `asegurarMeses(tramo)`: que estén todas las constancias de esos meses, pidiendo SOLO lo que falta
 *     —ni lo ya traído ni lo que ya está en camino— en una consulta por tramo, no una por estudio.
 *     Devuelve las constancias por estudio cuando están, o null si algo falló.
 *   · `asegurarFamilias(familias)`: la historia ENTERA de unos estudios, para el visor, que recorre todas
 *     sus constancias con las flechas.
 *   · `asegurarApoyo(tramo)`: lo pagado de educación esos meses (`fn_educacion_apoyo_pagado`).
 *   · `recargar(...)`: volver a pedir lo que se está mirando después de aprobar o rechazar, sin vaciar
 *     la cuadrícula mientras llega (no parpadea). Lo demás se olvida y se vuelve a pedir si se visita.
 * ASUME: `educacion-carga.ts` (qué se pide y cómo se lee) y que el permiso lo pone la base.
 * NO HACE: no decide QUÉ meses hacen falta: eso lo dice la pantalla con la ventana y los filtros.
 *
 * UNA CONSULTA QUE FALLA NO ES «SIN CONSTANCIAS». Sus meses quedan marcados con error —la cuadrícula los
 * dibuja con «?», los filtros que miran constancias no esconden a nadie y el CSV y el ZIP se niegan—
 * hasta que `reintentar()` los vuelva a pedir. Mismo criterio que cuando se pedían por estudio.
 *
 * PostgREST corta cada respuesta en `max_rows` SIN avisar: cada tramo se pide por páginas
 * (`todasLasPaginas`, en `educacion-carga.ts`, donde está la medición y su prueba).
 */

type Cliente = ReturnType<typeof createAdminSupabaseClient>;

export type EstadoDeCarga = "listo" | "cargando" | "error";

const solapan = (a: RangoDeMeses, b: RangoDeMeses): boolean => a.desde <= b.hasta && b.desde <= a.hasta;

export function useConstanciasPorMeses(supabase: Cliente, hoy: string) {
  const mesHoy = mesDe(hoy);
  // La fuente de verdad vive en refs —las promesas en vuelo las leen al terminar— y se copia al estado
  // para dibujar.
  const traidasRef = useRef<ConstanciasTraidas>(NADA_TRAIDO);
  const [traidas, setTraidas] = useState<ConstanciasTraidas>(NADA_TRAIDO);
  const vuelo = useRef<{ rango: RangoDeMeses; promesa: Promise<void> }[]>([]);
  const vueloFamilias = useRef(new Map<string, Promise<void>>());
  const [enVuelo, setEnVuelo] = useState<readonly RangoDeMeses[]>([]);
  const [conError, setConError] = useState<readonly RangoDeMeses[]>([]);
  const conErrorRef = useRef<readonly RangoDeMeses[]>([]);
  const [familiasConError, setFamiliasConError] = useState<ReadonlySet<string>>(new Set());
  const familiasConErrorRef = useRef<ReadonlySet<string>>(new Set());
  // Cada `recargar` abre una generación nueva: lo que llegue de una anterior ya es viejo y se descarta.
  const generacion = useRef(0);

  const apoyoRef = useRef<{ montos: Map<string, number>; rangos: RangoDeMeses[] }>({ montos: new Map(), rangos: [] });
  const [apoyo, setApoyo] = useState<{ montos: ReadonlyMap<string, number>; rangos: readonly RangoDeMeses[] }>({ montos: new Map(), rangos: [] });
  const vueloApoyo = useRef<RangoDeMeses[]>([]);

  const aplicar = useCallback((f: (t: ConstanciasTraidas) => ConstanciasTraidas) => {
    traidasRef.current = f(traidasRef.current);
    setTraidas(traidasRef.current);
  }, []);
  const ponerErrores = useCallback((r: readonly RangoDeMeses[]) => { conErrorRef.current = r; setConError(r); }, []);
  const ponerFamiliasConError = useCallback((f: ReadonlySet<string>) => { familiasConErrorRef.current = f; setFamiliasConError(f); }, []);
  const refrescarVuelo = useCallback(() => setEnVuelo(vuelo.current.map((v) => v.rango)), []);

  const pedirFilas = useCallback((filtro: { rango: RangoDeMeses } | { familias: readonly string[] }) =>
    todasLasPaginas<FilaDeConstancia>((desde, hasta) => {
      let q = supabase.from("educacion_entregas").select(SELECT_CONSTANCIAS, { count: desde === 0 ? "exact" : undefined });
      if ("rango" in filtro) {
        const or = filtroDelRango(filtro.rango);
        if (or) q = q.or(or);
      } else {
        q = q.in("asignacion.familia_id", [...filtro.familias]);
      }
      // Un orden estable es lo que hace que las páginas no se pisen ni dejen huecos.
      return q.order("id").range(desde, hasta) as unknown as Pagina<FilaDeConstancia>;
    }), [supabase]);

  /** Trae un tramo que todavía no está ni en camino. */
  const traerTramo = useCallback((rango: RangoDeMeses): Promise<void> => {
    const gen = generacion.current;
    const promesa = (async () => {
      const filas = await pedirFilas({ rango });
      if (gen !== generacion.current) return;
      if (filas === null) {
        ponerErrores(unirRangos([...conErrorRef.current, rango]));
        return;
      }
      aplicar((t) => sumarConstancias(t, filas, { rango }));
      ponerErrores(conErrorRef.current.filter((r) => !(r.desde >= rango.desde && r.hasta <= rango.hasta)));
    })().finally(() => {
      vuelo.current = vuelo.current.filter((v) => v.promesa !== promesa);
      refrescarVuelo();
    });
    vuelo.current = [...vuelo.current, { rango, promesa }];
    refrescarVuelo();
    return promesa;
  }, [pedirFilas, aplicar, ponerErrores, refrescarVuelo]);

  const asegurarMeses = useCallback(async (pedido: RangoDeMeses): Promise<Map<string, EntregaDeFamilia[]> | null> => {
    const yaPedido = [...traidasRef.current.rangos, ...vuelo.current.map((v) => v.rango)];
    const nuevas = rangosQueFaltan(yaPedido, pedido).map(traerTramo);
    const enCamino = vuelo.current.filter((v) => solapan(v.rango, pedido)).map((v) => v.promesa);
    await Promise.all([...nuevas, ...enCamino]);
    return rangoCubierto(traidasRef.current.rangos, pedido) ? constanciasPorFamilia(traidasRef.current) : null;
  }, [traerTramo]);

  const asegurarFamilias = useCallback(async (familias: readonly string[]): Promise<boolean> => {
    const gen = generacion.current;
    const faltan = familias.filter((f) => !familiaCompleta(traidasRef.current, f) && !vueloFamilias.current.has(f));
    if (faltan.length > 0) {
      const promesa = (async () => {
        const filas = await pedirFilas({ familias: faltan });
        if (gen !== generacion.current) return;
        if (filas === null) {
          ponerFamiliasConError(new Set([...familiasConErrorRef.current, ...faltan]));
          return;
        }
        aplicar((t) => sumarConstancias(t, filas, { familias: faltan }));
        ponerFamiliasConError(new Set([...familiasConErrorRef.current].filter((f) => !faltan.includes(f))));
      })().finally(() => { for (const f of faltan) vueloFamilias.current.delete(f); });
      for (const f of faltan) vueloFamilias.current.set(f, promesa);
    }
    await Promise.all(familias.map((f) => vueloFamilias.current.get(f)).filter(Boolean));
    return familias.every((f) => familiaCompleta(traidasRef.current, f));
  }, [pedirFilas, aplicar, ponerFamiliasConError]);

  /**
   * Lo pagado de educación cada mes ya cerrado del tramo. Si falla, el mes se da por traído sin montos:
   * la raya del apoyo no sale, como antes de esta carga por meses. No es un dato que decida nada.
   */
  const asegurarApoyo = useCallback(async (pedido: RangoDeMeses): Promise<void> => {
    const hasta = pedido.hasta < mesHoy ? pedido.hasta : sumarMeses(mesHoy, -1);
    if (hasta < pedido.desde) return;
    const faltan = rangosQueFaltan([...apoyoRef.current.rangos, ...vueloApoyo.current], { desde: pedido.desde, hasta });
    await Promise.all(faltan.map(async (r) => {
      vueloApoyo.current = [...vueloApoyo.current, r];
      const filas = await todasLasPaginas<{ persona_id: string; mes: string; monto: number }>((d, h) =>
        supabase.rpc("fn_educacion_apoyo_pagado", { p_desde: `${r.desde}-01` }, { count: d === 0 ? "exact" : undefined })
          .lt("mes", `${sumarMeses(r.hasta, 1)}-01`).order("persona_id").order("mes").range(d, h) as unknown as Pagina<{ persona_id: string; mes: string; monto: number }>);
      vueloApoyo.current = vueloApoyo.current.filter((x) => x !== r);
      const montos = new Map(apoyoRef.current.montos);
      for (const x of filas ?? []) montos.set(`${x.persona_id}|${mesDe(x.mes)}`, Number(x.monto));
      apoyoRef.current = { montos, rangos: unirRangos([...apoyoRef.current.rangos, r]) };
      setApoyo(apoyoRef.current);
    }));
  }, [supabase, mesHoy]);

  /**
   * Después de aprobar, rechazar o corregir: se vuelve a pedir lo que se está mirando (`rangos`, `familias`)
   * y lo nuevo reemplaza a lo viejo fila por fila, sin vaciar la cuadrícula mientras llega. Los meses y
   * los estudios que NO se están mirando dejan de contar como traídos: se piden de nuevo si se visitan.
   */
  const recargar = useCallback(async (rangos: readonly RangoDeMeses[], familias: readonly string[]): Promise<void> => {
    const gen = ++generacion.current;
    vuelo.current = [];
    vueloFamilias.current.clear();
    refrescarVuelo();
    const tramos = unirRangos(rangos);
    const [porTramo, deFamilias] = await Promise.all([
      Promise.all(tramos.map((rango) => pedirFilas({ rango }))),
      familias.length > 0 ? pedirFilas({ familias }) : Promise.resolve([] as FilaDeConstancia[]),
    ]);
    if (gen !== generacion.current) return;
    const errores = tramos.filter((_, i) => porTramo[i] === null);
    aplicar((t) => {
      let nueva: ConstanciasTraidas = { ...t, rangos: [], familias: new Set() };
      tramos.forEach((rango, i) => { const f = porTramo[i]; if (f) nueva = sumarConstancias(nueva, f, { rango }); });
      if (deFamilias) nueva = sumarConstancias(nueva, deFamilias, { familias });
      return nueva;
    });
    ponerErrores(errores);
    ponerFamiliasConError(deFamilias === null ? new Set(familias) : new Set());
  }, [pedirFilas, aplicar, ponerErrores, ponerFamiliasConError, refrescarVuelo]);

  /** Vuelve a pedir lo que falló. */
  const reintentar = useCallback(() => {
    const tramos = conErrorRef.current;
    const familias = [...familiasConErrorRef.current];
    ponerErrores([]);
    ponerFamiliasConError(new Set());
    for (const r of tramos) void asegurarMeses(r);
    if (familias.length > 0) void asegurarFamilias(familias);
  }, [asegurarMeses, asegurarFamilias, ponerErrores, ponerFamiliasConError]);

  const porFamilia = useMemo(() => constanciasPorFamilia(traidas), [traidas]);

  /** Cómo está un mes de la cuadrícula: sus constancias y, si ya cerró, lo pagado. */
  const estadoDelMes = useCallback((mes: string): EstadoDeCarga => {
    if (conError.some((r) => r.desde <= mes && mes <= r.hasta)) return "error";
    if (!mesCubierto(traidas.rangos, mes)) return "cargando";
    if (mes < mesHoy && !mesCubierto(apoyo.rangos, mes)) return "cargando";
    return "listo";
  }, [conError, traidas.rangos, apoyo.rangos, mesHoy]);

  const estadoDeFamilias = useCallback((familias: readonly string[]): EstadoDeCarga =>
    familias.every((f) => familiaCompleta(traidas, f)) ? "listo"
      : familias.some((f) => familiasConError.has(f)) ? "error" : "cargando",
  [traidas, familiasConError]);

  return {
    traidas, porFamilia, apoyoPagado: apoyo.montos, conError, familiasConError, enVuelo,
    estadoDelMes, estadoDeFamilias, rangoListo: (r: RangoDeMeses) => rangoCubierto(traidas.rangos, r),
    asegurarMeses, asegurarFamilias, asegurarApoyo, recargar, reintentar,
  };
}

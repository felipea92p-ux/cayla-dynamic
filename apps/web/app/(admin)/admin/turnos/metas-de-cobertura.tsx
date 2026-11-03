"use client";

// ============================================================================
// MetasDeCobertura — el editor de la meta de cobertura de una sede (0590)
// ============================================================================
// La PREDETERMINADA (por día de la semana) y las EXCEPCIONES (una campaña,
// diciembre, un feriado: rigen el tiempo que se elija y reemplazan solo los
// días que definen). Cada día, rangos de hora con su personal y sus líderes.
// En tiendas, al lado, lo que pide la venta, para comparar y para «usarlo».
// Manda la meta; un rango sin número deja que mande la venta; 0 = no se exige a
// nadie. La regla vive en lib/admin/metas-cobertura.ts; esto solo dibuja y guarda.
// ============================================================================

import { useEffect, useMemo, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Boton } from "@/components/ui/boton";
import { Campo } from "@/components/ui/campo";
import { Filtro } from "@/components/ui/filtro";
import { Insignia } from "@/components/ui/insignia";
import { Modal } from "@/components/ui/modal";
import { Rotulo } from "@/components/ui/rotulo";
import { useToast } from "@/components/toast";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { esFuncionInexistente } from "@/lib/puestos-resueltos";
import {
  compararHoraPorHora, hhmm, problemaDeRangos, rangosDesdeSugerido, rangosParaGuardar, type RangoMeta,
} from "@/lib/admin/metas-cobertura";

/** Lunes primero, como se piensa la semana; 0 = domingo, como guarda la base. */
const DIAS: { dia: number; corto: string; largo: string }[] = [
  { dia: 1, corto: "Lun", largo: "lunes" }, { dia: 2, corto: "Mar", largo: "martes" }, { dia: 3, corto: "Mié", largo: "miércoles" },
  { dia: 4, corto: "Jue", largo: "jueves" }, { dia: 5, corto: "Vie", largo: "viernes" }, { dia: 6, corto: "Sáb", largo: "sábado" },
  { dia: 0, corto: "Dom", largo: "domingo" },
];
const HORA_DESDE = 8, HORA_HASTA = 22; // la tira de comparación

interface Periodo {
  id: string;
  nombre: string;
  es_predeterminada: boolean;
  vigente_desde: string | null;
  vigente_hasta: string | null;
}
type PorDia = Map<number, RangoMeta[]>;
/** Una copia que se puede editar sin tocar lo leído. */
const copiar = (pd: PorDia | undefined): PorDia => new Map([...(pd ?? new Map<number, RangoMeta[]>())].map(([d, rs]) => [d, rs.map((r) => ({ ...r }))]));

const sumarDias = (iso: string, n: number) => {
  const d = new Date(`${iso}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
};
const sumarMeses = (iso: string, n: number) => {
  const d = new Date(`${iso}T12:00:00Z`);
  d.setUTCMonth(d.getUTCMonth() + n);
  return d.toISOString().slice(0, 10);
};
const fechaCorta = (iso: string) => iso.split("-").reverse().slice(0, 2).join("/");
const aDecimal = (hm: string) => { const [h, m] = hm.split(":").map(Number); return (h ?? 0) + (m ?? 0) / 60; };
/** «Hasta» 00:00 es el cierre del día (24). */
const hastaADecimal = (hm: string) => (hm === "00:00" ? 24 : aDecimal(hm));
const hastaAHHMM = (dec: number) => (dec >= 24 ? "00:00" : hhmm(dec));

export function MetasDeCobertura({
  sedeId, sedeNombre, esTienda, puedeEditar, ventaDe, lunes, onCerrar, onGuardado,
}: {
  sedeId: string;
  sedeNombre: string;
  esTienda: boolean;
  /** Admin y DO cambian la meta; la líder de equipo la ve. */
  puedeEditar: boolean;
  /** Lo que pide la venta (personas) un día de la semana (0 = domingo) a una hora entera; null si no se pudo leer. */
  ventaDe: ((dia: number, hora: number) => number | null) | null;
  /** El lunes de la semana que se mira en Turnos: de ahí arranca una excepción nueva. */
  lunes: string;
  onCerrar: () => void;
  onGuardado: () => void;
}) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const { avisar } = useToast();
  const [periodos, setPeriodos] = useState<Periodo[] | null>(null);
  const [rangos, setRangos] = useState<Map<string, PorDia>>(new Map());
  const [falta0590, setFalta0590] = useState(false);
  const [recarga, setRecarga] = useState(0);
  // Lo que se está editando: una meta existente (su id), «nueva» o nada.
  const [editando, setEditando] = useState<string | "nueva" | null>(null);
  const [nombre, setNombre] = useState("");
  const [desde, setDesde] = useState(lunes);
  const [hasta, setHasta] = useState(sumarDias(lunes, 6));
  const [porDia, setPorDia] = useState<PorDia>(new Map());
  const [diaSel, setDiaSel] = useState(1);
  const [guardando, setGuardando] = useState(false);

  useEffect(() => {
    let vivo = true;
    void (async () => {
      const { data: per, error: e1 } = await supabase.from("metas_cobertura_periodos" as never)
        .select("id, nombre, es_predeterminada, vigente_desde, vigente_hasta")
        .eq("sede_id" as never, sedeId as never).is("anulada_at" as never, null);
      if (!vivo) return;
      if (e1) {
        if (esFuncionInexistente(e1) || e1.code === "42P01" || e1.code === "PGRST205") setFalta0590(true);
        else avisar("error", mensajeDeError(e1, "leer las metas de cobertura"));
        setPeriodos([]);
        return;
      }
      const lista = ((per ?? []) as unknown as Periodo[])
        .sort((a, b) => Number(b.es_predeterminada) - Number(a.es_predeterminada) || (a.vigente_desde ?? "").localeCompare(b.vigente_desde ?? ""));
      const ids = lista.map((p) => p.id);
      const mapa = new Map<string, PorDia>();
      if (ids.length) {
        const { data: ran, error: e2 } = await supabase.from("metas_cobertura_rangos" as never)
          .select("periodo_id, dia_semana, desde_min, hasta_min, personal, lideres").in("periodo_id" as never, ids as never);
        if (!vivo) return;
        if (e2) { avisar("error", mensajeDeError(e2, "leer los rangos de las metas")); }
        for (const r of ((ran ?? []) as unknown as { periodo_id: string; dia_semana: number; desde_min: number; hasta_min: number; personal: number | null; lideres: number | null }[])) {
          const pd = mapa.get(r.periodo_id) ?? new Map<number, RangoMeta[]>();
          pd.set(r.dia_semana, [...(pd.get(r.dia_semana) ?? []), { desde: r.desde_min / 60, hasta: r.hasta_min / 60, personal: r.personal, lideres: r.lideres }]
            .sort((a, b) => a.desde - b.desde));
          mapa.set(r.periodo_id, pd);
        }
      }
      setPeriodos(lista);
      setRangos(mapa);
    })();
    return () => { vivo = false; };
  }, [supabase, sedeId, recarga, avisar]);

  const predeterminada = periodos?.find((p) => p.es_predeterminada) ?? null;
  const excepciones = periodos?.filter((p) => !p.es_predeterminada) ?? [];

  function abrir(p: Periodo | "nueva" | "predeterminada") {
    if (p === "nueva") {
      setEditando("nueva");
      setNombre("");
      setDesde(lunes);
      setHasta(sumarDias(lunes, 6));
      // Arranca copiando la predeterminada: casi siempre la excepción es «lo mismo, pero más».
      setPorDia(copiar(predeterminada ? rangos.get(predeterminada.id) : undefined));
    } else if (p === "predeterminada") {
      setEditando(predeterminada?.id ?? "predeterminada");
      setNombre("Predeterminada");
      setPorDia(copiar(predeterminada ? rangos.get(predeterminada.id) : undefined));
    } else {
      setEditando(p.id);
      setNombre(p.nombre);
      setDesde(p.vigente_desde ?? lunes);
      setHasta(p.vigente_hasta ?? sumarDias(lunes, 6));
      setPorDia(copiar(rangos.get(p.id)));
    }
    setDiaSel(1);
  }

  const esPred = editando !== null && editando !== "nueva" && (editando === "predeterminada" || editando === predeterminada?.id);
  const delDia = porDia.get(diaSel) ?? [];
  const problemas = DIAS.map((d) => ({ d, p: problemaDeRangos(porDia.get(d.dia) ?? []) })).filter((x) => x.p);
  const fechasMal = !esPred && (!desde || !hasta || hasta < desde);

  const cambiarRango = (i: number, cambio: Partial<RangoMeta>) =>
    setPorDia((m) => new Map(m).set(diaSel, (m.get(diaSel) ?? []).map((r, k) => (k === i ? { ...r, ...cambio } : r))));
  const agregarRango = () => setPorDia((m) => {
    const rs = m.get(diaSel) ?? [];
    const ultimo = rs[rs.length - 1];
    const inicio = ultimo ? ultimo.hasta : 9;
    return new Map(m).set(diaSel, [...rs, { desde: Math.min(inicio, 23), hasta: Math.min(24, inicio + 3), personal: null, lideres: null }]);
  });
  const quitarRango = (i: number) => setPorDia((m) => new Map(m).set(diaSel, (m.get(diaSel) ?? []).filter((_, k) => k !== i)));
  const copiarATodos = () => setPorDia((m) => new Map(DIAS.map((d) => [d.dia, (m.get(diaSel) ?? []).map((r) => ({ ...r }))])));
  const vaciarDia = () => setPorDia((m) => { const n = new Map(m); n.delete(diaSel); return n; });
  const usarVenta = () => {
    if (!ventaDe) return;
    const nuevos = rangosDesdeSugerido((h) => ventaDe(diaSel, h), HORA_DESDE, HORA_HASTA, (h) => delDia.find((r) => r.desde <= h && h < r.hasta)?.lideres ?? null);
    setPorDia((m) => new Map(m).set(diaSel, nuevos));
  };

  async function guardar() {
    setGuardando(true);
    const { error } = await supabase.rpc("fn_guardar_meta_cobertura", {
      p_sede_id: sedeId,
      p_periodo_id: editando === "nueva" || editando === "predeterminada" ? null : editando,
      p_nombre: esPred ? "Predeterminada" : (nombre.trim() || "Excepción"),
      p_desde: esPred ? null : desde,
      p_hasta: esPred ? null : hasta,
      p_rangos: rangosParaGuardar(porDia),
    });
    setGuardando(false);
    if (error) { avisar("error", mensajeDeError(error, "guardar la meta")); return; }
    avisar("ok", esPred ? "Listo: la meta predeterminada quedó guardada." : `Listo: «${nombre.trim() || "Excepción"}» rige del ${fechaCorta(desde)} al ${fechaCorta(hasta)}.`);
    setEditando(null);
    setRecarga((n) => n + 1);
    onGuardado();
  }

  async function quitar(p: Periodo) {
    const { error } = await supabase.rpc("fn_anular_meta_cobertura", { p_periodo_id: p.id });
    if (error) { avisar("error", mensajeDeError(error, "quitar la excepción")); return; }
    avisar("ok", `Listo: «${p.nombre}» ya no rige. Esos días vuelven a la predeterminada.`);
    setRecarga((n) => n + 1);
    onGuardado();
  }

  const resumenDia = (pd: PorDia | undefined, dia: number) => {
    const rs = pd?.get(dia) ?? [];
    if (rs.length === 0) return "—";
    return rs.map((r) => `${hhmm(r.desde)}–${hastaAHHMM(r.hasta)} ${r.personal ?? "venta"}${r.lideres ? `+${r.lideres}L` : ""}`).join(" · ");
  };

  const comparacion = esTienda && ventaDe ? compararHoraPorHora(delDia, (h) => ventaDe(diaSel, h), HORA_DESDE, HORA_HASTA) : null;

  return (
    <Modal abierto onCerrar={onCerrar} bloqueado={guardando} ancho="xl" titulo={`Metas de cobertura · ${sedeNombre}`}>
      <div className="space-y-4">
        <p className="text-sm text-taupe">
          Cuánta gente hace falta en piso, por rangos de hora. <strong>Manda la meta.</strong> Un rango sin número deja que mande
          {esTienda ? " lo que pide la venta (compras ÷ ritmo, con su mínimo)" : " lo que se ponga después"}; un 0 dice que ahí no se exige a nadie.
          Una excepción rige el tiempo que elijas y reemplaza solo los días que define; si dos se pisan, manda la más corta.
        </p>
        {falta0590 && (
          <BannerAviso variante="advertencia" className="text-sm">
            Las metas por rangos llegan con la migración 0590, que todavía no está pegada. Mientras tanto Turnos usa la meta de mañana y tarde de siempre.
          </BannerAviso>
        )}

        {editando === null ? (
          <div className="space-y-3">
            <div className="space-y-1">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <Rotulo como="h3">Predeterminada</Rotulo>
                {puedeEditar && !falta0590 && <Boton variante="secundario" tamano="sm" onClick={() => abrir("predeterminada")}>Cambiar</Boton>}
              </div>
              <ul className="space-y-0.5 text-xs">
                {DIAS.map((d) => (
                  <li key={d.dia} className="flex gap-2">
                    <span className="w-10 shrink-0 text-taupe">{d.corto}</span>
                    <span className="tabular-nums">{resumenDia(predeterminada ? rangos.get(predeterminada.id) : undefined, d.dia)}</span>
                  </li>
                ))}
              </ul>
            </div>
            <div className="space-y-1 border-t border-sand pt-3">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <Rotulo como="h3">Excepciones</Rotulo>
                {puedeEditar && !falta0590 && <Boton variante="secundario" tamano="sm" onClick={() => abrir("nueva")}>Nueva excepción</Boton>}
              </div>
              {excepciones.length === 0 && <p className="text-xs text-taupe">Ninguna. Una excepción sirve para una campaña, diciembre o un feriado.</p>}
              <ul className="space-y-2">
                {excepciones.map((p) => {
                  const definidos = DIAS.filter((d) => (rangos.get(p.id)?.get(d.dia) ?? []).length > 0).map((d) => d.corto);
                  return (
                    <li key={p.id} className="flex flex-wrap items-center gap-2 text-sm">
                      <span className="font-medium">{p.nombre}</span>
                      <Insignia variante="neutral" tamano="sm">del {fechaCorta(p.vigente_desde!)} al {fechaCorta(p.vigente_hasta!)}</Insignia>
                      <span className="text-xs text-taupe">{definidos.length ? definidos.join(", ") : "sin días definidos"}</span>
                      {puedeEditar && (
                        <span className="ml-auto flex gap-2">
                          <Boton variante="enlace" onClick={() => abrir(p)}>Editar</Boton>
                          <Boton variante="enlace" onClick={() => void quitar(p)}>Quitar</Boton>
                        </span>
                      )}
                    </li>
                  );
                })}
              </ul>
            </div>
            <div className="flex justify-end">
              <Boton variante="secundario" onClick={onCerrar}>Cerrar</Boton>
            </div>
          </div>
        ) : (
          <div className="space-y-4">
            {!esPred && (
              <div className="grid gap-3 sm:grid-cols-3">
                <Campo etiqueta="Nombre" value={nombre} placeholder="Campaña de fin de año" onChange={(e) => setNombre(e.target.value)} />
                <Campo etiqueta="Desde" type="date" value={desde} onChange={(e) => setDesde(e.target.value || desde)} />
                <Campo etiqueta="Hasta" type="date" value={hasta} min={desde} onChange={(e) => setHasta(e.target.value || hasta)} />
                <div role="group" aria-label="Por cuánto tiempo" className="flex flex-wrap items-center gap-2 sm:col-span-3">
                  <span className="text-xs text-taupe">Rige:</span>
                  <Filtro activo={hasta === desde} onClick={() => setHasta(desde)}>Un día</Filtro>
                  <Filtro activo={hasta === sumarDias(desde, 6)} onClick={() => setHasta(sumarDias(desde, 6))}>Una semana</Filtro>
                  <Filtro activo={hasta === sumarDias(desde, 13)} onClick={() => setHasta(sumarDias(desde, 13))}>Dos semanas</Filtro>
                  <Filtro activo={hasta === sumarDias(sumarMeses(desde, 1), -1)} onClick={() => setHasta(sumarDias(sumarMeses(desde, 1), -1))}>Un mes</Filtro>
                  <Filtro activo={hasta === sumarDias(sumarMeses(desde, 2), -1)} onClick={() => setHasta(sumarDias(sumarMeses(desde, 2), -1))}>Dos meses</Filtro>
                  <span className="text-xs text-taupe">del {fechaCorta(desde)} al {fechaCorta(hasta)}. Para otras fechas, elige el «Hasta».</span>
                </div>
              </div>
            )}

            <div role="group" aria-label="Día de la semana" className="flex flex-wrap gap-1.5">
              {DIAS.map((d) => (
                <Filtro key={d.dia} activo={diaSel === d.dia} onClick={() => setDiaSel(d.dia)}>
                  {d.corto}{(porDia.get(d.dia) ?? []).length ? "" : " ·"}
                </Filtro>
              ))}
            </div>
            {!esPred && delDia.length === 0 && (
              <p className="text-xs text-taupe">Este día no está en la excepción: sigue con la predeterminada. Agrega un rango para cambiarlo.</p>
            )}

            <div className="space-y-2">
              {delDia.map((r, i) => (
                <div key={i} className="flex flex-wrap items-end gap-2">
                  <Campo etiqueta={i === 0 ? "Desde" : undefined} type="time" step={900} value={hhmm(r.desde)}
                    onChange={(e) => e.target.value && cambiarRango(i, { desde: aDecimal(e.target.value) })} />
                  <Campo etiqueta={i === 0 ? "Hasta (00:00 = cierre)" : undefined} type="time" step={900} value={hastaAHHMM(r.hasta)}
                    onChange={(e) => e.target.value && cambiarRango(i, { hasta: hastaADecimal(e.target.value) })} />
                  <Campo etiqueta={i === 0 ? "Personal" : undefined} type="number" min={0} max={50} inputMode="numeric"
                    placeholder={esTienda ? "venta" : "—"} value={r.personal ?? ""} className="w-24"
                    onChange={(e) => cambiarRango(i, { personal: e.target.value === "" ? null : Math.max(0, Math.round(Number(e.target.value))) })} />
                  <Campo etiqueta={i === 0 ? "Líderes" : undefined} type="number" min={0} max={20} inputMode="numeric"
                    placeholder="—" value={r.lideres ?? ""} className="w-20"
                    onChange={(e) => cambiarRango(i, { lideres: e.target.value === "" ? null : Math.max(0, Math.round(Number(e.target.value))) })} />
                  <Boton variante="enlace" onClick={() => quitarRango(i)}>Quitar</Boton>
                </div>
              ))}
              <div className="flex flex-wrap items-center gap-3">
                <Boton variante="secundario" tamano="sm" onClick={agregarRango}>Agregar rango</Boton>
                {esTienda && ventaDe && <Boton variante="enlace" onClick={usarVenta}>Usar lo que pide la venta</Boton>}
                <Boton variante="enlace" onClick={copiarATodos}>Copiar este día a toda la semana</Boton>
                {delDia.length > 0 && <Boton variante="enlace" onClick={vaciarDia}>{esPred ? "Dejar este día sin meta" : "Sacar este día de la excepción"}</Boton>}
              </div>
            </div>

            {comparacion && (
              <div className="space-y-1">
                <Rotulo>Meta y lo que pide la venta, hora por hora (promedio de las últimas 4 semanas)</Rotulo>
                <div className="overflow-x-auto">
                  <table className="text-xs tabular-nums">
                    <tbody>
                      <tr><th className="pr-2 text-left font-normal text-taupe">Hora</th>{comparacion.map((c) => <td key={c.hora} className="px-1.5 text-center text-taupe">{c.hora}</td>)}</tr>
                      <tr><th className="pr-2 text-left font-normal text-taupe">Meta</th>{comparacion.map((c) => <td key={c.hora} className="px-1.5 text-center">{c.meta ?? "·"}</td>)}</tr>
                      <tr><th className="pr-2 text-left font-normal text-taupe">Venta</th>{comparacion.map((c) => <td key={c.hora} className="px-1.5 text-center">{c.sugerido ?? "·"}</td>)}</tr>
                      <tr>
                        <th className="pr-2 text-left font-normal text-taupe">Diferencia</th>
                        {comparacion.map((c) => (
                          <td key={c.hora} className={`px-1.5 text-center ${c.diferencia === null || c.diferencia === 0 ? "text-taupe" : c.diferencia < 0 ? "text-rojo-profundo" : "text-ambar"}`}>
                            {c.diferencia === null ? "·" : c.diferencia > 0 ? `+${c.diferencia}` : c.diferencia}
                          </td>
                        ))}
                      </tr>
                    </tbody>
                  </table>
                </div>
                <p className="text-xs text-taupe">Negativo: la meta pide menos de lo que pide la venta. Positivo: pide más.</p>
              </div>
            )}

            {problemas.length > 0 && (
              <p role="alert" className="text-sm text-rojo-profundo">
                {problemas.map(({ d, p }) => `${d.corto}: ${p}`).join(" ")}
              </p>
            )}
            {fechasMal && <p role="alert" className="text-sm text-rojo-profundo">La excepción termina antes de empezar.</p>}

            <div className="flex justify-end gap-2">
              <Boton variante="secundario" disabled={guardando} onClick={() => setEditando(null)}>Volver</Boton>
              {puedeEditar && (
                <Boton variante="primario" cargando={guardando} disabled={guardando || problemas.length > 0 || fechasMal} onClick={() => void guardar()}>
                  Guardar la meta
                </Boton>
              )}
            </div>
          </div>
        )}
      </div>
    </Modal>
  );
}

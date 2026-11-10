"use client";

// «Cambios de horario» — la línea de tiempo de todo lo que movió el horario de
// una persona o de todo el equipo: horario base, turno de un día, piso o
// almacén, jornada y disponibilidad (lib/historial-horario.ts).
//
// QUÉ ASUME · la RLS de `correcciones_auditoria` (la líder, su sede; DO, todo) y
//             la de `disponibilidades` (0584). La pantalla no filtra permisos:
//             pregunta, y la base devuelve lo que a cada quien le toca ver.
// SOLO LEE  · no cambia nada. Para cambiar un horario está Horarios; un turno,
//             Turnos; una disponibilidad o la jornada, Disponibilidad.

import { useEffect, useMemo, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { hoyLima, puedeVerDisponibilidadEquipo, puedeVerTodasLasSedes, rangoDelDiaLima, sumarDias } from "@cayla-dynamic/shared";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { sobretituloDeHoy } from "@/lib/admin/sobretitulo";
import { Cargando } from "@/components/cargando";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { EstadoVacio } from "@/components/ui/estado-vacio";
import { Filtro } from "@/components/ui/filtro";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { TIPOS, type TipoCambio } from "@/lib/historial-horario";
import { ListaHistorial, useHistorialHorario } from "@/components/historial-horario/historial-horario";

interface Persona { id: string; nombres: string; apellidos: string }

const PERIODOS = [
  { dias: 30, label: "Últimos 30 días" },
  { dias: 90, label: "Últimos 3 meses" },
  { dias: 365, label: "Último año" },
];

const selectClase = "rounded-control border border-borde-control bg-hueso px-3 py-2 text-sm text-tinta";

export default function CambiosDeHorario() {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const yo = usePersonaActual();
  const [sedes, setSedes] = useState<{ id: string; nombre: string }[]>([]);
  const [sedeId, setSedeId] = useState<string | null>(null);
  const [personas, setPersonas] = useState<Persona[] | null>(null);
  const [nombres, setNombres] = useState<Map<string, string>>(new Map());
  const [personaId, setPersonaId] = useState<string>("todas");
  const [tipos, setTipos] = useState<Set<TipoCambio>>(new Set(TIPOS.map((t) => t.valor)));
  const [dias, setDias] = useState(30);

  const sedeElegida = sedeId ?? yo?.sedeBaseId ?? null;
  const desdeIso = rangoDelDiaLima(sumarDias(hoyLima(), -dias)).inicio;

  useEffect(() => {
    if (!yo || !puedeVerTodasLasSedes(yo.rol)) return;
    let vivo = true;
    void supabase.from("sedes").select("id, nombre").eq("activa", true).order("nombre")
      .then(({ data }) => { if (vivo) setSedes((data as { id: string; nombre: string }[]) ?? []); });
    return () => { vivo = false; };
  }, [supabase, yo]);

  useEffect(() => {
    if (!sedeElegida) return;
    let vivo = true;
    void supabase.from("personas").select("id, nombres, apellidos")
      .eq("sede_base_id", sedeElegida).eq("cuenta_de_servicio", false).order("nombres")
      .then(({ data }) => {
        if (!vivo) return;
        const ps = (data as Persona[]) ?? [];
        setPersonas(ps);
        setPersonaId("todas");
      });
    return () => { vivo = false; };
  }, [supabase, sedeElegida]);

  const ids = personas ? (personaId === "todas" ? personas.map((p) => p.id) : [personaId]) : null;
  const historial = useHistorialHorario(supabase, ids, desdeIso, "ella");

  // Los nombres de quien hizo cada cambio: suele ser alguien de otra sede (DO).
  // Se piden aparte; si la RLS no deja leer a esa persona, se dice su papel.
  useEffect(() => {
    const conocidos = new Map((personas ?? []).map((p) => [p.id, `${p.nombres} ${p.apellidos}`]));
    const faltan = [...new Set(historial.entradas.map((e) => e.quien).filter((q): q is string => !!q && !conocidos.has(q)))];
    let vivo = true;
    void (faltan.length
      ? supabase.from("personas").select("id, nombres, apellidos").in("id", faltan)
      : Promise.resolve({ data: [] as Persona[] })
    ).then(({ data }) => {
      if (!vivo) return;
      for (const p of (data as Persona[]) ?? []) conocidos.set(p.id, `${p.nombres} ${p.apellidos}`);
      setNombres(conocidos);
    });
    return () => { vivo = false; };
  }, [supabase, personas, historial.entradas]);

  if (!yo) return <Cargando />;
  if (!puedeVerDisponibilidadEquipo(yo.rol)) {
    return <BannerAviso variante="informativo">Esta pantalla es de la líder de equipo y de Desarrollo Organizacional.</BannerAviso>;
  }

  const visibles = historial.entradas.filter((e) => tipos.has(e.tipo));
  const nombreDe = (id: string) => nombres.get(id) ?? "Desarrollo Organizacional";
  const alternar = (t: TipoCambio) => setTipos((s) => {
    const n = new Set(s);
    if (n.has(t)) n.delete(t); else n.add(t);
    return n.size === 0 ? new Set([t]) : n;
  });

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex flex-1 flex-col gap-5 p-6">
        <CabeceraPagina
          sobretitulo={sobretituloDeHoy("Asistencia")}
          titulo="Cambios de horario"
          descripcion="Todo lo que cambió en el horario de una persona o del equipo: quién, cuándo, de qué a qué."
        />

        <TarjetaInfo>
          <div className="flex flex-col gap-3">
            {sedes.length > 1 && (
              <div role="group" aria-label="Sede" className="flex flex-wrap gap-2">
                {sedes.map((s) => (
                  <Filtro key={s.id} tamano="sm" activo={s.id === sedeElegida} onClick={() => setSedeId(s.id)}>{s.nombre}</Filtro>
                ))}
              </div>
            )}
            <div className="flex flex-wrap items-end gap-3">
              <label className="flex flex-col gap-1">
                <span className="text-sm text-taupe">Persona</span>
                <select className={selectClase} value={personaId} onChange={(e) => setPersonaId(e.target.value)}>
                  <option value="todas">Todo el equipo</option>
                  {(personas ?? []).map((p) => <option key={p.id} value={p.id}>{p.nombres} {p.apellidos}</option>)}
                </select>
              </label>
              <label className="flex flex-col gap-1">
                <span className="text-sm text-taupe">Período</span>
                <select className={selectClase} value={dias} onChange={(e) => setDias(Number(e.target.value))}>
                  {PERIODOS.map((p) => <option key={p.dias} value={p.dias}>{p.label}</option>)}
                </select>
              </label>
            </div>
            <div role="group" aria-label="Qué cambios ver" className="flex flex-wrap gap-2">
              {TIPOS.map((t) => (
                <Filtro key={t.valor} tamano="sm" activo={tipos.has(t.valor)} onClick={() => alternar(t.valor)}>{t.label}</Filtro>
              ))}
            </div>
          </div>
        </TarjetaInfo>

        {historial.error && <BannerAviso variante="alerta" role="alert">{historial.error}</BannerAviso>}
        {(!personas || (historial.cargando && personas.length > 0)) && !historial.error && <Cargando />}
        {personas && personas.length === 0 && <EstadoVacio>No hay personas en esta sede.</EstadoVacio>}
        {personas && personas.length > 0 && !historial.cargando && !historial.error && (
          visibles.length === 0
            ? <EstadoVacio>No hubo cambios de horario en este período.</EstadoVacio>
            : <ListaHistorial entradas={visibles} nombreDe={nombreDe} mostrarPersona={personaId === "todas"} />
        )}
      </main>
    </div>
  );
}

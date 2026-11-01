"use client";

// Cambiar el sueldo de un GRUPO entero (0578): practicantes preprofesionales,
// egresados u honorarios. Solo la dirección.
//
//   1 · el grupo: la lista entera con su sueldo de hoy; vienen marcados los que
//       tienen el sueldo por defecto, y se marca o desmarca a cualquiera;
//   2 · el monto, desde cuándo (inicio del ciclo actual, del siguiente, o hoy) y
//       el motivo, con el aviso de que esto mueve plata;
//   3 · DOBLE confirmación (Felipe: «siempre dar doble confirmación»);
//   4 · hecho: el comunicado queda en borrador solo para esas personas, y se
//       ofrece ir a Anuncios a publicarlo.
//
// La que manda es `fn_sueldo_grupo_cambiar`: RMV, grupo, periodo pagado, rol.

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { hoyLima } from "@cayla-dynamic/shared";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Rotulo } from "@/components/ui/rotulo";
import { Cargando } from "@/components/cargando";
import { useToast } from "@/components/toast";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import {
  avisoDeCambioDePlata,
  opcionesDeVigencia,
  type ClaveVigencia,
  type PeriodoCiclo,
} from "@/lib/admin/cambio-de-plata";

type Grupo = "practicante_preprofesional" | "practicante_profesional" | "rxh";

const GRUPOS: { valor: Grupo; etiqueta: string }[] = [
  { valor: "practicante_preprofesional", etiqueta: "Practicantes preprofesionales" },
  { valor: "practicante_profesional", etiqueta: "Practicantes egresados" },
  { valor: "rxh", etiqueta: "Honorarios" },
];

interface Miembro {
  persona_id: string;
  nombre: string;
  sueldo_actual: number | null;
  es_por_defecto: boolean;
}

type Paso = "formulario" | "confirmar" | "seguro" | "hecho";

function soles(n: number | null): string {
  return n === null ? "—" : `S/ ${n.toLocaleString("es-PE", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

export function PanelSueldoGrupo({ onCerrar }: { onCerrar: () => void }) {
  const { avisar } = useToast();
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const hoy = hoyLima();

  const [grupo, setGrupo] = useState<Grupo>("practicante_preprofesional");
  const [miembros, setMiembros] = useState<Miembro[] | null>(null);
  const [marcados, setMarcados] = useState<Set<string>>(new Set());
  const [periodos, setPeriodos] = useState<PeriodoCiclo[]>([]);
  const [monto, setMonto] = useState("");
  const [vigencia, setVigencia] = useState<ClaveVigencia>("inicio_siguiente");
  const [motivo, setMotivo] = useState("");
  const [paso, setPaso] = useState<Paso>("formulario");
  const [error, setError] = useState<string | null>(null);
  const [guardando, setGuardando] = useState(false);
  const [resultado, setResultado] = useState<{ cambiados: number; anuncio_id: string | null } | null>(null);

  useEffect(() => {
    void supabase
      .from("periodos_planilla")
      .select("fecha_ini, fecha_fin")
      .order("fecha_ini", { ascending: false })
      .limit(6)
      .then(({ data }) => setPeriodos((data ?? []) as PeriodoCiclo[]));
  }, [supabase]);

  useEffect(() => {
    void supabase.rpc("fn_sueldo_grupo_vista_previa", { p_grupo: grupo }).then(({ data, error: e }) => {
      if (e) {
        setError(mensajeDeError(e, "leer el grupo"));
        setMiembros([]);
        return;
      }
      const filas = ((data ?? []) as Record<string, unknown>[]).map((f) => ({
        persona_id: String(f.persona_id),
        nombre: String(f.nombre),
        sueldo_actual: f.sueldo_actual === null || f.sueldo_actual === undefined ? null : Number(f.sueldo_actual),
        es_por_defecto: f.es_por_defecto === true,
      }));
      setMiembros(filas);
      setMarcados(new Set(filas.filter((f) => f.es_por_defecto).map((f) => f.persona_id)));
    });
  }, [supabase, grupo]);

  const opciones = useMemo(() => opcionesDeVigencia(hoy, periodos), [hoy, periodos]);
  const opcion = opciones.find((o) => o.clave === vigencia) ?? opciones[opciones.length - 1] ?? null;
  const montoNumero = Number(monto.replace(",", "."));
  const etiquetaGrupo = GRUPOS.find((g) => g.valor === grupo)?.etiqueta ?? grupo;

  function revisar() {
    if (marcados.size === 0) return setError("Marca al menos a una persona.");
    if (!(montoNumero > 0)) return setError("Escribe el monto nuevo.");
    if (!opcion) return setError("Elige desde cuándo rige.");
    if (motivo.trim().length < 3) return setError("Escribe el motivo: es lo que explica el monto dentro de un año.");
    setError(null);
    setPaso("confirmar");
  }

  async function aplicar() {
    if (!opcion) return;
    setGuardando(true);
    const { data, error: e } = await supabase.rpc("fn_sueldo_grupo_cambiar", {
      p_grupo: grupo,
      p_personas: [...marcados],
      p_monto: montoNumero,
      p_desde: opcion.fecha,
      p_motivo: motivo.trim(),
    });
    setGuardando(false);
    if (e) {
      setError(mensajeDeError(e, "cambiar el sueldo del grupo"));
      setPaso("formulario");
      return;
    }
    const r = (data ?? {}) as { cambiados?: number; anuncio_id?: string | null };
    setResultado({ cambiados: Number(r.cambiados ?? 0), anuncio_id: r.anuncio_id ?? null });
    setPaso("hecho");
    avisar("ok", `Sueldo cambiado a ${r.cambiados ?? 0} ${r.cambiados === 1 ? "persona" : "personas"}. Quedó en el historial.`);
  }

  if (paso === "hecho" && resultado) {
    return (
      <div className="flex flex-col gap-4">
        <BannerAviso variante="informativo" titulo={`Listo: ${resultado.cambiados} ${resultado.cambiados === 1 ? "persona" : "personas"} con el sueldo nuevo`}>
          Los módulos pueden tardar un momento en mostrar el valor nuevo.
        </BannerAviso>
        <BannerAviso variante="advertencia" titulo="Falta publicar el comunicado">
          Quedó un comunicado en BORRADOR solo para las personas a las que les cambió el sueldo. Revísalo y publícalo
          desde Anuncios; hasta entonces nadie lo ve.
        </BannerAviso>
        <div className="flex justify-end gap-2">
          <Boton onClick={onCerrar}>Cerrar</Boton>
          <Link href="/admin/anuncios">
            <Boton variante="primario">Ir a Anuncios a publicarlo</Boton>
          </Link>
        </div>
      </div>
    );
  }

  if (paso === "confirmar" || paso === "seguro") {
    return (
      <div className="flex flex-col gap-4">
        <Rotulo>Revisa antes de confirmar</Rotulo>
        <BannerAviso variante="advertencia" titulo={`${etiquetaGrupo}: ${marcados.size} ${marcados.size === 1 ? "persona" : "personas"} pasan a ${soles(montoNumero)}`}>
          <ul className="list-disc pl-5">
            {avisoDeCambioDePlata(opcion).map((r) => (
              <li key={r}>{r}</li>
            ))}
          </ul>
        </BannerAviso>
        <p className="text-sm text-taupe">Motivo: «{motivo.trim()}»</p>
        {paso === "confirmar" ? (
          <div className="flex justify-end gap-2">
            <Boton onClick={() => setPaso("formulario")}>Volver</Boton>
            <Boton variante="primario" onClick={() => setPaso("seguro")}>Estoy de acuerdo con el cambio</Boton>
          </div>
        ) : (
          <>
            <BannerAviso variante="alerta" titulo="Segunda confirmación">
              ¿Seguro? Se cambia el sueldo de {marcados.size} {marcados.size === 1 ? "persona" : "personas"} desde el{" "}
              {opcion ? opcion.fecha.split("-").reverse().join("/") : ""}.
            </BannerAviso>
            <div className="flex justify-end gap-2">
              <Boton onClick={() => setPaso("formulario")} disabled={guardando}>No, volver</Boton>
              <Boton variante="peligro" cargando={guardando} onClick={aplicar}>Sí, aplicar el cambio</Boton>
            </div>
          </>
        )}
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <CampoSelect etiqueta="Grupo" value={grupo} onChange={(e) => {
          setMiembros(null);
          setError(null);
          setGrupo(e.target.value as Grupo);
        }}>
        {GRUPOS.map((g) => (
          <option key={g.valor} value={g.valor}>{g.etiqueta}</option>
        ))}
      </CampoSelect>

      {miembros === null ? (
        <Cargando />
      ) : miembros.length === 0 ? (
        <p className="text-sm text-taupe">No hay nadie activo en este grupo.</p>
      ) : (
        <fieldset className="flex flex-col gap-1">
          <legend className="text-sm text-taupe">
            Marcados: {marcados.size} de {miembros.length}. Vienen marcados los que tienen el sueldo por defecto.
          </legend>
          {miembros.map((m) => (
            <label key={m.persona_id} className="flex items-center gap-2 text-sm text-tinta">
              <input
                type="checkbox"
                checked={marcados.has(m.persona_id)}
                onChange={(e) => {
                  const nuevo = new Set(marcados);
                  if (e.target.checked) nuevo.add(m.persona_id);
                  else nuevo.delete(m.persona_id);
                  setMarcados(nuevo);
                }}
              />
              <span className="flex-1">{m.nombre}</span>
              <span className="text-taupe">{soles(m.sueldo_actual)}{m.es_por_defecto ? " · por defecto" : ""}</span>
            </label>
          ))}
        </fieldset>
      )}

      <Campo
        etiqueta="Monto nuevo (S/ al mes)"
        inputMode="decimal"
        value={monto}
        onChange={(e) => {
          setMonto(e.target.value);
          setError(null);
        }}
      />

      <fieldset className="flex flex-col gap-2">
        <legend className="text-sm font-medium text-tinta">Desde cuándo rige</legend>
        {opciones.map((o) => (
          <label key={o.clave} className="flex items-start gap-2 text-sm text-tinta">
            <input type="radio" name="vigencia" checked={vigencia === o.clave} onChange={() => setVigencia(o.clave)} />
            <span>
              {o.etiqueta}
              <span className="block text-xs text-taupe">{o.detalle}</span>
            </span>
          </label>
        ))}
      </fieldset>

      <AreaTexto
        etiqueta="Motivo del cambio"
        rows={3}
        value={motivo}
        onChange={(e) => {
          setMotivo(e.target.value);
          setError(null);
        }}
        placeholder="Por qué se cambia. Se guarda con tu nombre y la hora."
      />

      {error && <BannerAviso variante="alerta">{error}</BannerAviso>}

      <div className="flex justify-end gap-2">
        <Boton onClick={onCerrar}>Cancelar</Boton>
        <Boton variante="primario" onClick={revisar}>Revisar el cambio</Boton>
      </div>
    </div>
  );
}

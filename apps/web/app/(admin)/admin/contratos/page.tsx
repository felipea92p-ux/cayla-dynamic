"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { useRolActual } from "@/lib/admin/use-rol";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { AdminNav } from "../nav";
import { Cargando } from "@/components/cargando";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import { hoyLima, puedeGestionarContratos } from "@cayla-dynamic/shared";
import { horarioVigente, horasSemanalesVigentes, type HorarioTramo } from "@/lib/admin/jornada-esperada";
import {
  construirContrato,
  formatearFecha,
  ACTIVOS_PRINCIPALES_POR_SEDE,
  type DatosContrato,
} from "@/lib/admin/contrato-texto";

// Generador de contratos: se elige a la persona, el sistema jala lo que ya
// sabe de ella (DNI, sueldo vigente, horario, sede) y arma el contrato
// completo — listo para imprimir y firmar en físico.
//
// Es la pieza que docs/estado.md ya listaba como pendiente: "Generador de
// contratos — los tres conceptos [movilidad, educación, bono] tienen que
// estar en el contrato de trabajo | nada, pero no existe la pieza."
//
// El texto se persiste en `contratos_generados.documento_html` en el momento
// de generarse (borrador, sin firma) — antes de que exista el escaneo, no
// después — para que quede constancia de qué se imprimió aunque pasen días
// hasta que se firme. Ver migración 0271 y apps/web/lib/admin/contrato-texto.ts.

const EMPRESA = {
  firmanteNombre: "Alvarez Pereyra Felipe Miguel",
  firmanteDni: "47384306",
};

const MAX_BYTES = 50 * 1024 * 1024;

interface Persona {
  id: string;
  nombres: string;
  apellidos: string;
  documento: string | null;
  cargo: string | null;
  sede_base_id: string | null;
  email: string | null;
  fecha_ingreso: string;
  fecha_fin_contrato: string | null;
  cobra_movilidad: boolean;
}
interface Sede {
  id: string;
  nombre: string;
  codigo: string;
}
interface DatoPersonal {
  persona_id: string;
  nombre_dni: string | null;
  direccion: string | null;
}
interface Salario {
  persona_id: string;
  salario_mensual_soles: number;
}
interface Parametro {
  clave: string;
  valor: number;
  sede_codigo: string | null;
}
interface HorarioFila extends HorarioTramo {
  horas_semana_objetivo: number | null;
}
interface ContratoFila {
  id: string;
  persona_id: string;
  persona: string;
  tipo: string;
  cargo: string;
  sede: string | null;
  remuneracion_mensual: number;
  fecha_inicio: string;
  fecha_fin: string;
  horas_semanales: number | null;
  generado_at: string;
  storage_path: string | null;
  fecha_firma: string | null;
  anulado_at: string | null;
  anulado_motivo: string | null;
  vigente: boolean;
}

export default function ContratosPage() {
  const router = useRouter();
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const rol = useRolActual();
  const puede = puedeGestionarContratos(rol);

  const [cargando, setCargando] = useState(true);
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [sedes, setSedes] = useState<Sede[]>([]);
  const [datosPersonales, setDatosPersonales] = useState<DatoPersonal[]>([]);
  const [salarios, setSalarios] = useState<Salario[]>([]);
  const [horarios, setHorarios] = useState<HorarioFila[]>([]);
  const [movilidadTarifas, setMovilidadTarifas] = useState<Parametro[]>([]);
  const [bonoOnomastico, setBonoOnomastico] = useState<number | null>(null);
  const [ritVersion, setRitVersion] = useState<string | null>(null);
  const [ritFecha, setRitFecha] = useState<string | null>(null);
  const [contratos, setContratos] = useState<ContratoFila[]>([]);

  const [personaId, setPersonaId] = useState("");
  const [tipo, setTipo] = useState<"nuevo" | "renovacion">("renovacion");
  const [cargoEditado, setCargoEditado] = useState("");
  const [causaEditada, setCausaEditada] = useState("");
  const [funcionesEditadas, setFuncionesEditadas] = useState("");
  const [activosLibre, setActivosLibre] = useState("");
  const [fechaInicio, setFechaInicio] = useState("");
  const [fechaFin, setFechaFin] = useState("");

  const [generando, setGenerando] = useState(false);
  const [borrador, setBorrador] = useState<{ id: string; html: string } | null>(null);

  const [subiendoPara, setSubiendoPara] = useState<string | null>(null);
  const [archivo, setArchivo] = useState<File | null>(null);
  const [fechaFirma, setFechaFirma] = useState("");
  const [progreso, setProgreso] = useState<number | null>(null);
  const [guardandoFirma, setGuardandoFirma] = useState(false);

  const [anulando, setAnulando] = useState<string | null>(null);
  const [motivoAnular, setMotivoAnular] = useState("");

  const [aviso, setAviso] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);

  const sedeCodigo = useMemo(() => new Map(sedes.map((s) => [s.id, s.codigo])), [sedes]);
  const sedeNombreMap = useMemo(() => new Map(sedes.map((s) => [s.id, s.nombre])), [sedes]);

  // La tarifa de movilidad de una sede: SU fila, o la general. Mismo criterio
  // que usa fn_planilla_calcular y /admin/documentacion — el contrato y la
  // boleta no pueden decir montos distintos.
  const tarifaDeSede = useCallback(
    (sedeBaseId: string | null | undefined): number | null => {
      const codigo = sedeBaseId ? sedeCodigo.get(sedeBaseId) : undefined;
      const suya = codigo ? movilidadTarifas.find((t) => t.sede_codigo === codigo) : undefined;
      const fila = suya ?? movilidadTarifas.find((t) => !t.sede_codigo);
      const valor = fila ? Number(fila.valor) : NaN;
      return Number.isFinite(valor) && valor > 0 ? valor : null;
    },
    [sedeCodigo, movilidadTarifas],
  );

  const cargar = useCallback(async () => {
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) {
      router.replace("/admin/login");
      return;
    }

    const hoy = hoyLima();
    const [ps, ss, dp, sal, hor, params, rit, ctr] = await Promise.all([
      supabase
        .from("personas")
        .select("id, nombres, apellidos, documento, cargo, sede_base_id, email, fecha_ingreso, fecha_fin_contrato, cobra_movilidad")
        .eq("estado", "activo")
        .eq("en_planilla", true)
        .order("apellidos"),
      supabase.from("sedes").select("id, nombre, codigo"),
      supabase.from("datos_personales").select("persona_id, nombre_dni, direccion"),
      supabase.from("asignaciones_salario").select("persona_id, salario_mensual_soles").is("vigente_hasta", null),
      supabase
        .from("horarios_asignados")
        .select(
          "persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida, dias_laborables, horario_por_dia, almuerzo_min_minutos, horas_semana_objetivo",
        ),
      // Movilidad y bono: la fila vigente HOY. Sin fila aplicable, cae a
      // null y el contrato lo dice en vez de inventar un monto — misma
      // regla que /admin/documentacion.
      supabase
        .from("parametros_laborales")
        .select("clave, valor, sede_codigo")
        .in("clave", ["movilidad_diaria", "bono_onomastico"])
        .lte("vigente_desde", hoy)
        .is("vigente_hasta", null),
      // La versión vigente del RIT. Se lee de la tabla, no se escribe a
      // mano: es exactamente el dato que este repo prohíbe hardcodear.
      supabase
        .from("documentos_institucionales")
        .select("version, vigente_desde")
        .eq("tipo", "rit")
        .lte("vigente_desde", hoy)
        .order("vigente_desde", { ascending: false })
        .limit(1),
      supabase.rpc("fn_contratos_listar"),
    ]);

    setPersonas((ps.data as Persona[]) ?? []);
    setSedes((ss.data as Sede[]) ?? []);
    setDatosPersonales((dp.data as DatoPersonal[]) ?? []);
    setSalarios((sal.data as Salario[]) ?? []);
    setHorarios((hor.data as HorarioFila[]) ?? []);

    const paramsData = (params.data as Parametro[]) ?? [];
    setMovilidadTarifas(paramsData.filter((p) => p.clave === "movilidad_diaria"));
    const bono = paramsData.find((p) => p.clave === "bono_onomastico");
    setBonoOnomastico(bono ? Number(bono.valor) : null);

    const ritFila = ((rit.data as { version: number; vigente_desde: string }[] | null) ?? [])[0];
    setRitVersion(ritFila ? String(ritFila.version) : null);
    setRitFecha(ritFila ? formatearFecha(ritFila.vigente_desde) : null);

    setContratos((ctr.data as ContratoFila[]) ?? []);
    setCargando(false);
  }, [supabase, router]);

  useEffect(() => {
    void cargar();
  }, [cargar]);

  // Al cambiar de persona o de tipo, se reponen los campos editables con un
  // punto de partida razonable — y se descarta cualquier borrador anterior,
  // que ya no corresponde a lo que se está editando ahora.
  useEffect(() => {
    const p = personas.find((x) => x.id === personaId);
    setBorrador(null);
    if (!p) return;

    setCargoEditado(p.cargo ?? "");
    const sedeNom = p.sede_base_id ? (sedeNombreMap.get(p.sede_base_id) ?? "") : "";
    setCausaEditada(
      `La causa objetiva determinante de la contratación es la siguiente: LA EMPRESA opera la sede ` +
        `${sedeNom}, que ha experimentado un crecimiento sostenido de su actividad y de atención al ` +
        `público. El volumen actual de operaciones no puede ser absorbido en su totalidad por el personal ` +
        `permanente ya registrado en planillas de LA EMPRESA. En consecuencia, la contratación bajo ` +
        `modalidad temporal resulta necesaria y proporcional a la naturaleza de esta etapa de expansión y ` +
        `consolidación operativa, en los términos del artículo 57 del TUO del Decreto Legislativo N.° 728. ` +
        `[REVISAR antes de imprimir — en especial si la sede es Central, que no es tienda y puede necesitar ` +
        `otra causa objetiva.]`,
    );
    setFuncionesEditadas(
      "[Completar con las funciones específicas del puesto — usar como referencia el Anexo I del contrato anterior de esta persona, si existe.]",
    );
    setActivosLibre("");

    if (tipo === "renovacion" && p.fecha_fin_contrato) {
      const siguiente = new Date(`${p.fecha_fin_contrato}T00:00:00`);
      siguiente.setDate(siguiente.getDate() + 1);
      setFechaInicio(siguiente.toISOString().slice(0, 10));
    } else {
      setFechaInicio(hoyLima());
    }
    setFechaFin("");
  }, [personaId, tipo, personas, sedeNombreMap]);

  // Cualquier edición posterior invalida el borrador ya generado: lo que se
  // imprime tiene que ser exactamente lo que se congeló en la base, nunca una
  // versión editada después de generarlo.
  useEffect(() => {
    setBorrador(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cargoEditado, causaEditada, funcionesEditadas, activosLibre, fechaInicio, fechaFin]);

  const persona = personas.find((p) => p.id === personaId) ?? null;
  const datoPersonal = persona ? (datosPersonales.find((d) => d.persona_id === persona.id) ?? null) : null;
  const salarioVigente = persona
    ? (salarios.find((s) => s.persona_id === persona.id)?.salario_mensual_soles ?? null)
    : null;
  const tramoVigente = persona
    ? horarioVigente(
        horarios.filter((h) => h.persona_id === persona.id),
        hoyLima(),
      )
    : null;
  const horasCalculadas = tramoVigente ? horasSemanalesVigentes(tramoVigente) : null;
  const horasDeclaradas = (tramoVigente as HorarioFila | null)?.horas_semana_objetivo ?? null;
  const horasDiscrepan =
    horasCalculadas?.horas !== null &&
    horasCalculadas?.horas !== undefined &&
    horasDeclaradas !== null &&
    Math.abs(horasCalculadas.horas - horasDeclaradas) > 0.5;

  const sedeCod = persona?.sede_base_id ? (sedeCodigo.get(persona.sede_base_id) ?? "") : "";
  const sedeNom = persona?.sede_base_id ? (sedeNombreMap.get(persona.sede_base_id) ?? "") : "";
  const movilidadTarifa = persona ? tarifaDeSede(persona.sede_base_id) : null;

  const datosParaGenerar: DatosContrato | null =
    persona && datoPersonal?.nombre_dni && persona.documento && salarioVigente !== null && fechaInicio && fechaFin
      ? {
          tipo,
          nombreDni: datoPersonal.nombre_dni,
          documento: persona.documento,
          direccion: datoPersonal.direccion,
          cargo: cargoEditado || persona.cargo || "",
          email: persona.email,
          sedeNombre: sedeNom,
          sedeCodigo: sedeCod,
          causaObjetivaTexto: causaEditada,
          funcionesTexto: funcionesEditadas,
          fechaInicio,
          fechaFin,
          fechaIngresoOriginal: persona.fecha_ingreso,
          horasSemanales: horasCalculadas?.horas ?? null,
          remuneracionMensual: salarioVigente,
          cobraMovilidad: persona.cobra_movilidad,
          movilidadDiaria: movilidadTarifa,
          bonoOnomastico: bonoOnomastico ?? 0,
          ritVersion: ritVersion ?? "[sin publicar en el sistema]",
          ritFecha: ritFecha ?? "[sin publicar en el sistema]",
          activosPrincipales: sedeCod ? (ACTIVOS_PRINCIPALES_POR_SEDE[sedeCod] ?? "") : "",
          activosLibre,
          firmanteNombre: EMPRESA.firmanteNombre,
          firmanteDni: EMPRESA.firmanteDni,
        }
      : null;

  const previewHtml = datosParaGenerar ? construirContrato(datosParaGenerar) : null;

  async function generarBorrador() {
    if (!datosParaGenerar || !persona) {
      setAviso({
        tipo: "error",
        texto: "Faltan datos para generar el contrato: revisa DNI, nombre legal (Ficha personal), sueldo vigente y las fechas.",
      });
      return;
    }
    setGenerando(true);
    const html = construirContrato(datosParaGenerar);
    const { data: id, error } = await supabase.rpc("fn_contrato_registrar", {
      p_persona_id: persona.id,
      p_tipo: tipo,
      p_cargo: datosParaGenerar.cargo,
      p_sede_id: persona.sede_base_id,
      p_remuneracion_mensual: datosParaGenerar.remuneracionMensual,
      p_fecha_inicio: fechaInicio,
      p_fecha_fin: fechaFin,
      p_horas_semanales: datosParaGenerar.horasSemanales,
      p_documento_html: html,
    });
    setGenerando(false);
    if (error || !id) {
      setAviso({ tipo: "error", texto: mensajeDeError(error, "generar el contrato") });
      return;
    }
    setBorrador({ id: id as string, html });
    await cargar();
    setAviso({ tipo: "ok", texto: "Borrador generado. Revísalo, imprímelo y fírmalo; después sube el escaneo desde el historial." });
  }

  function imprimir() {
    window.print();
  }

  function abrirSubida(id: string) {
    setSubiendoPara(id);
    setArchivo(null);
    setFechaFirma(hoyLima());
    setAviso(null);
  }

  async function guardarFirma() {
    if (!subiendoPara) return;
    if (!archivo) {
      setAviso({ tipo: "error", texto: "Falta el escaneo firmado." });
      return;
    }
    if (archivo.size > MAX_BYTES) {
      setAviso({ tipo: "error", texto: `"${archivo.name}" pesa ${(archivo.size / 1048576).toFixed(1)} MB y el máximo es 50 MB.` });
      return;
    }
    if (!fechaFirma) {
      setAviso({ tipo: "error", texto: "Indica en qué fecha se firmó." });
      return;
    }

    setGuardandoFirma(true);
    const ext = archivo.name.split(".").pop()?.toLowerCase() ?? "bin";
    const ruta = `contratos/${subiendoPara}.${ext}`;
    setProgreso(0);
    const fallo = await subirArchivoConProgreso(supabase, "contratos", ruta, archivo, setProgreso);
    setProgreso(null);
    if (fallo) {
      setGuardandoFirma(false);
      setAviso({ tipo: "error", texto: `El archivo no subió (${fallo}). Vuelve a intentarlo.` });
      return;
    }
    const { error } = await supabase.rpc("fn_contrato_registrar", {
      p_id: subiendoPara,
      p_storage_path: ruta,
      p_fecha_firma: fechaFirma,
    });
    setGuardandoFirma(false);
    if (error) {
      setAviso({ tipo: "error", texto: mensajeDeError(error, "registrar la firma") });
      return;
    }
    setSubiendoPara(null);
    await cargar();
    setAviso({ tipo: "ok", texto: "Contrato firmado registrado. La fecha de vencimiento de la persona se actualizó." });
  }

  async function anular() {
    if (!anulando) return;
    if (motivoAnular.trim().length < 3) {
      setAviso({ tipo: "error", texto: "Escribe por qué se anula." });
      return;
    }
    const { error } = await supabase.rpc("fn_contrato_anular", { p_id: anulando, p_motivo: motivoAnular.trim() });
    if (error) {
      setAviso({ tipo: "error", texto: mensajeDeError(error, "anular el contrato") });
      return;
    }
    setAnulando(null);
    setMotivoAnular("");
    await cargar();
    setAviso({ tipo: "ok", texto: "Contrato anulado. Sigue guardado en el historial." });
  }

  async function verDocumento(path: string) {
    const { data, error } = await supabase.storage.from("contratos").createSignedUrl(path, 60);
    if (error || !data) {
      setAviso({ tipo: "error", texto: mensajeDeError(error, "abrir el documento") });
      return;
    }
    window.open(data.signedUrl, "_blank", "noopener");
  }

  useTituloDocumento(persona ? `${persona.nombres} ${persona.apellidos} — Contrato de trabajo` : null);

  if (rol === null || cargando) {
    return (
      <main className="p-6">
        <Cargando />
      </main>
    );
  }
  if (!puede) {
    return (
      <main className="p-6">
        <p className="max-w-md rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
          Solo administradores y líderes pueden generar contratos.
        </p>
      </main>
    );
  }

  const documentoAMostrar = borrador?.html ?? previewHtml;

  return (
    <main className="p-6">
      <div className="print:hidden">
        <AdminNav />
      </div>

      <div className="mx-auto max-w-3xl space-y-6 print:hidden">
        <h1 className="text-xl font-semibold">Generador de contratos</h1>

        {aviso && (
          <p className={`rounded-lg px-4 py-3 text-sm ${aviso.tipo === "error" ? "bg-rojo/10 text-rojo" : "bg-verde/10 text-verde"}`}>
            {aviso.texto}
          </p>
        )}

        <section className="space-y-3 rounded-lg border border-sand p-4">
          <div className="grid grid-cols-2 gap-3">
            <label className="text-sm">
              Persona
              <select
                className="mt-1 w-full rounded border border-sand p-2"
                value={personaId}
                onChange={(e) => setPersonaId(e.target.value)}
              >
                <option value="">— elegir —</option>
                {personas.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.apellidos}, {p.nombres}
                  </option>
                ))}
              </select>
            </label>
            <label className="text-sm">
              Tipo
              <select
                className="mt-1 w-full rounded border border-sand p-2"
                value={tipo}
                onChange={(e) => setTipo(e.target.value as "nuevo" | "renovacion")}
              >
                <option value="renovacion">Renovación</option>
                <option value="nuevo">Nuevo ingreso</option>
              </select>
            </label>
          </div>

          {persona && (
            <>
              <div className="grid grid-cols-2 gap-3">
                <label className="text-sm">
                  Fecha de inicio
                  <input
                    type="date"
                    className="mt-1 w-full rounded border border-sand p-2"
                    value={fechaInicio}
                    onChange={(e) => setFechaInicio(e.target.value)}
                  />
                </label>
                <label className="text-sm">
                  Fecha de fin
                  <input
                    type="date"
                    className="mt-1 w-full rounded border border-sand p-2"
                    value={fechaFin}
                    onChange={(e) => setFechaFin(e.target.value)}
                  />
                </label>
              </div>

              <label className="block text-sm">
                Cargo
                <input
                  className="mt-1 w-full rounded border border-sand p-2"
                  value={cargoEditado}
                  onChange={(e) => setCargoEditado(e.target.value)}
                />
              </label>
              <label className="block text-sm">
                Causa objetiva (revisar antes de imprimir)
                <textarea
                  className="mt-1 w-full rounded border border-sand p-2"
                  rows={4}
                  value={causaEditada}
                  onChange={(e) => setCausaEditada(e.target.value)}
                />
              </label>
              <label className="block text-sm">
                Funciones del cargo (Anexo I)
                <textarea
                  className="mt-1 w-full rounded border border-sand p-2"
                  rows={3}
                  value={funcionesEditadas}
                  onChange={(e) => setFuncionesEditadas(e.target.value)}
                />
              </label>
              <label className="block text-sm">
                Anexo IV — ajuste de activos para esta persona
                <textarea
                  className="mt-1 w-full rounded border border-sand p-2"
                  rows={2}
                  value={activosLibre}
                  onChange={(e) => setActivosLibre(e.target.value)}
                />
              </label>

              <dl className="grid grid-cols-2 gap-2 text-xs text-taupe">
                <div>
                  <dt className="font-semibold">DNI</dt>
                  <dd>{persona.documento ?? "falta"}</dd>
                </div>
                <div>
                  <dt className="font-semibold">Nombre legal</dt>
                  <dd>{datoPersonal?.nombre_dni ?? "falta en Ficha personal"}</dd>
                </div>
                <div>
                  <dt className="font-semibold">Sueldo vigente</dt>
                  <dd>{salarioVigente !== null ? `S/ ${salarioVigente.toFixed(2)}` : "sin asignación vigente"}</dd>
                </div>
                <div>
                  <dt className="font-semibold">Horas semanales</dt>
                  <dd className={horasDiscrepan ? "text-rojo" : ""}>
                    {horasCalculadas?.horas !== null && horasCalculadas?.horas !== undefined
                      ? horasCalculadas.horas
                      : "no se pudo determinar — quedará pendiente en el texto"}
                    {horasDiscrepan && ` (el horario declara ${horasDeclaradas} — revisar antes de imprimir)`}
                  </dd>
                </div>
                <div>
                  <dt className="font-semibold">Movilidad</dt>
                  <dd>
                    {persona.cobra_movilidad
                      ? movilidadTarifa !== null
                        ? `S/ ${movilidadTarifa}/día`
                        : "sin tarifa vigente para su sede"
                      : "no cobra"}
                  </dd>
                </div>
                <div>
                  <dt className="font-semibold">RIT vigente</dt>
                  <dd>{ritVersion ? `v${ritVersion} · ${ritFecha}` : "no publicado en el sistema"}</dd>
                </div>
              </dl>

              <button
                className="rounded bg-tinta px-4 py-2 text-sm text-white disabled:opacity-50"
                disabled={!datosParaGenerar || generando}
                onClick={generarBorrador}
              >
                {generando ? "Generando…" : "Generar borrador"}
              </button>
              {borrador && (
                <button className="ml-2 rounded border border-sand px-4 py-2 text-sm" onClick={imprimir}>
                  Imprimir / Guardar como PDF
                </button>
              )}
            </>
          )}
        </section>

        <section className="space-y-2">
          <h2 className="text-lg font-semibold">Historial</h2>
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="border-b border-sand">
                <th className="py-1">Persona</th>
                <th>Tipo</th>
                <th>Vigencia</th>
                <th>Firma</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {contratos.map((c) => (
                <tr key={c.id} className={`border-b border-sand/50 ${c.anulado_at ? "opacity-50" : ""}`}>
                  <td className="py-1">{c.persona}</td>
                  <td>
                    {c.tipo}
                    {c.vigente ? " · vigente" : ""}
                  </td>
                  <td>
                    {formatearFecha(c.fecha_inicio)} – {formatearFecha(c.fecha_fin)}
                  </td>
                  <td>
                    {c.anulado_at
                      ? `anulado — ${c.anulado_motivo}`
                      : c.storage_path
                        ? `firmado el ${c.fecha_firma}`
                        : "pendiente de firma"}
                  </td>
                  <td className="space-x-2 text-xs">
                    {c.storage_path && (
                      <button className="underline" onClick={() => verDocumento(c.storage_path!)}>
                        Ver escaneo
                      </button>
                    )}
                    {!c.storage_path && !c.anulado_at && (
                      <button className="underline" onClick={() => abrirSubida(c.id)}>
                        Subir firma
                      </button>
                    )}
                    {!c.anulado_at && (
                      <button className="text-rojo underline" onClick={() => setAnulando(c.id)}>
                        Anular
                      </button>
                    )}
                  </td>
                </tr>
              ))}
              {contratos.length === 0 && (
                <tr>
                  <td colSpan={5} className="py-3 text-taupe">
                    Todavía no se generó ningún contrato.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </section>

        {subiendoPara && (
          <section className="space-y-2 rounded-lg border border-sand p-4">
            <p className="text-sm font-semibold">Subir escaneo firmado</p>
            <input type="file" accept="image/*,application/pdf" onChange={(e) => setArchivo(e.target.files?.[0] ?? null)} />
            <label className="block text-sm">
              Fecha de firma
              <input
                type="date"
                className="mt-1 rounded border border-sand p-2"
                value={fechaFirma}
                onChange={(e) => setFechaFirma(e.target.value)}
              />
            </label>
            {progreso !== null && <p className="text-xs">{progreso}%</p>}
            <div className="space-x-2">
              <button
                className="rounded bg-tinta px-3 py-1.5 text-sm text-white disabled:opacity-50"
                disabled={guardandoFirma}
                onClick={guardarFirma}
              >
                Guardar
              </button>
              <button className="text-sm" onClick={() => setSubiendoPara(null)}>
                Cancelar
              </button>
            </div>
          </section>
        )}

        {anulando && (
          <section className="space-y-2 rounded-lg border border-rojo p-4">
            <p className="text-sm font-semibold">Anular contrato</p>
            <textarea
              className="w-full rounded border border-sand p-2 text-sm"
              placeholder="Motivo (mínimo 3 caracteres)"
              value={motivoAnular}
              onChange={(e) => setMotivoAnular(e.target.value)}
            />
            <div className="space-x-2">
              <button className="rounded bg-rojo px-3 py-1.5 text-sm text-white" onClick={anular}>
                Confirmar anulación
              </button>
              <button className="text-sm" onClick={() => setAnulando(null)}>
                Cancelar
              </button>
            </div>
          </section>
        )}
      </div>

      {documentoAMostrar && (
        <div
          className="hoja mx-auto mt-6 max-w-3xl rounded-lg border border-sand p-8 text-sm leading-relaxed print:mt-0 print:max-w-none print:rounded-none print:border-0 print:p-0"
          dangerouslySetInnerHTML={{ __html: documentoAMostrar }}
        />
      )}
    </main>
  );
}

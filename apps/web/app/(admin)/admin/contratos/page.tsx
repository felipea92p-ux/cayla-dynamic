"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { useRolActual } from "@/lib/admin/use-rol";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { AdminNav } from "../nav";
import { Cargando } from "@/components/cargando";
import { AreaTexto } from "@/components/ui/area-texto";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import { abrirArchivoFirmado } from "@/lib/abrir-archivo-firmado";
import { useToast } from "@/components/toast";
import { hoyLima, maximoSemanalPracticante, puedeGestionarContratos } from "@cayla-dynamic/shared";
import {
  construirContrato,
  formatearFecha,
  ACTIVOS_PRINCIPALES_POR_SEDE,
  FUNCIONES_PLACEHOLDER,
  MARCADOR_FIRMA_EMPRESA,
  tipoQueCorresponde,
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
// hasta que se firme. Ver migración 0272 y apps/web/lib/admin/contrato-texto.ts.
//
// LA JORNADA SIEMPRE ES DE 48 HORAS, NUNCA UN NÚMERO CALCULADO DEL HORARIO.
// Decisión de Felipe (2026-08-19): el horario real (hoy 45h en varias sedes)
// es una disposición voluntaria y ajustable de la empresa, no un tope legal —
// el contrato declara el máximo que la ley permite y que CAYLA se reserva el
// derecho de usar, igual que ya mide el sobretiempo `fn_planilla_calcular`
// (contra 48h fijas, nunca contra el horario nominal de cada quien). Por eso
// esta pantalla no lee `horarios_asignados` ni compara contra
// `horas_semana_objetivo`: esa comparación no alimentaba nada del contrato y
// Felipe la encontró más ruidosa que útil.

// Quién firma por CAYLA NO se escribe acá. Vive en `configuracion.firmante_empresa`
// (0147), validado por trigger: tiene que ser una persona activa con rol admin o
// lider_do. Antes estaban el nombre y el DNI de Felipe escritos a mano en este
// archivo — exactamente el tipo de dato que este repositorio prohíbe hardcodear:
// el día que firme otra persona, el contrato saldría con el nombre equivocado y
// nadie se enteraría hasta verlo impreso.
const FIRMANTE_POR_DEFECTO = { nombre: "", dni: "", cargo: "Gerencia General" };

const MAX_BYTES = 50 * 1024 * 1024;

// "2026-07-28" + 1 → "2026-07-29" (aritmética en UTC: sin sorpresas de zona)
// "Proyecto ERP\n" → "Proyecto ERP"; "a\n\n  b" → "a b". Para lo que se imprime
// dentro de una frase: ahí un salto de línea no significa nada y solo estorba.
function unaLinea(texto: string): string {
  return texto.replace(/\s+/g, " ").trim();
}

function sumarDias(iso: string, n: number): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

// "2026-09-04" + 3 meses → "2026-12-03": el día anterior al aniversario, que es
// como se cuenta un plazo de contrato (del 4 de setiembre al 3 de diciembre).
function finDePlazo(inicioIso: string, meses: number): string {
  const [y, m, d] = inicioIso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1 + meses, d - 1)).toISOString().slice(0, 10);
}

interface Persona {
  id: string;
  nombres: string;
  apellidos: string;
  documento: string | null;
  cargo: string | null;
  sede_base_id: string | null;
  // Dónde trabaja de verdad. La movilidad se paga por acá y no por la sede
  // base (0166), así que el contrato tiene que decir la misma tarifa que la
  // boleta: si no, el papel promete un monto y la planilla paga otro.
  sede_fisica_id: string | null;
  email: string | null;
  fecha_ingreso: string;
  fecha_fin_contrato: string | null;
  cobra_movilidad: boolean;
  // Las dos exclusiones que la planilla sí respeta y el contrato no miraba.
  personal_direccion: boolean;
  sueldo_fijo: boolean;
  // Decide qué documento le corresponde (0333): planilla/prueba generan un
  // contrato de trabajo, practicante genera un convenio de modalidad
  // formativa. `en_planilla` es la columna generada — no se recalcula acá.
  en_planilla: boolean;
  tipo_vinculo: string;
  // Solo tiene sentido con tipo_vinculo='practicante' (0324): decide 30h/48h.
  practicante_modalidad: string | null;
}
interface Sede {
  id: string;
  nombre: string;
  codigo: string;
  ciudad: string | null;
}
interface DatoPersonal {
  persona_id: string;
  nombre_dni: string | null;
  direccion: string | null;
  genero: string | null;
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
interface ContratoFila {
  id: string;
  persona_id: string;
  persona: string;
  tipo: string;
  cargo: string;
  sede: string | null;
  remuneracion_mensual: number;
  fecha_inicio: string;
  // NULL cuando tipo="indefinido" (0347): ese documento no tiene fecha de término.
  fecha_fin: string | null;
  horas_semanales: number | null;
  generado_at: string;
  storage_path: string | null;
  fecha_firma: string | null;
  generado_por: string | null;
  copia_entregada_at: string | null;
  comunicado_mtpe_at: string | null;
  anulado_at: string | null;
  anulado_motivo: string | null;
  vigente: boolean;
}

interface FilaTablero {
  persona_id: string;
  persona: string;
  sede: string | null;
  fecha_fin_contrato: string | null;
  dias_restantes: number | null;
  contrato_id: string | null;
  tipo: string | null;
  fecha_firma: string | null;
  copia_entregada_at: string | null;
  comunicado_mtpe_at: string | null;
  copia_vence: string | null;
  mtpe_vence: string | null;
  dias_marcados_despues: number;
  estado: string;
}

/** Cómo se dice cada tipo en pantalla. En la base son «nuevo»/«renovacion». */
const TIPO_CONTRATO: Record<string, string> = {
  nuevo: "Nuevo ingreso",
  renovacion: "Renovación",
  adendum: "Adendum",
  convenio_practicas: "Convenio de prácticas",
  indefinido: "Indefinido",
};

/**
 * Qué significa cada estado, y cuál merece el rojo.
 *
 * `grave` NO quiere decir «hay algo que hacer» — en esta pantalla eso lo dicen
 * todas las filas. Quiere decir que el plazo YA SE PASÓ y cada día que corre
 * cuesta. Al principio, con veinte personas sin contrato todavía, marcar eso
 * como grave pintaba la pantalla entera de rojo, y una pantalla toda roja no
 * avisa de nada: el `rojo` de esta paleta es el acento sagrado, con un máximo
 * de usos por vista.
 */
/** Los estados que se resuelven generando un contrato; el resto, abriendo el suyo. */
const NECESITA_CONTRATO = new Set(["sin_contrato", "vencido", "por_vencer", "desnaturalizado"]);

/**
 * Qué decir de quien NO tiene contrato en este sistema.
 *
 * `fn_contratos_tablero` responde «no hay fila acá», y eso NO es lo mismo que
 * «esta persona no tiene contrato»: el generador se estrenó en agosto de 2026 y
 * todo el equipo venía firmando en papel desde antes. Escribir «sin contrato»
 * al lado de veinte nombres es afirmar algo falso sobre gente real — y encima
 * en la pantalla que se abre para decidir a quién hay que renovarle.
 *
 * Se distingue con `fecha_fin_contrato`, que la persona ya trae puesta: si hay
 * fecha de vencimiento, el contrato existe y está firmado en un archivador; lo
 * que falta es traerlo acá. Si no hay ni fecha ni fila, ahí sí no se sabe de
 * ningún contrato, y eso es lo que hay que decir.
 */
function estadoSinContrato(f: FilaTablero): { texto: string; grave: boolean } {
  if (f.fecha_fin_contrato === null) return { texto: "sin contrato registrado", grave: false };
  return { texto: "en papel, sin registrar acá", grave: false };
}

const ESTADO_TABLERO: Record<string, { texto: string; grave: boolean }> = {
  desnaturalizado: { texto: "marcó después del vencimiento — riesgo art. 77", grave: true },
  vencido: { texto: "contrato vencido", grave: true },
  sin_contrato: { texto: "sin contrato registrado", grave: false },
  sin_firmar: { texto: "pendiente de firma", grave: false },
  sin_vencimiento: { texto: "sin fecha de vencimiento", grave: false },
  por_vencer: { texto: "vence pronto", grave: false },
  tramite_pendiente: { texto: "falta copia o comunicación al MTPE", grave: false },
  ok: { texto: "al día", grave: false },
};

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
  const [movilidadTarifas, setMovilidadTarifas] = useState<Parametro[]>([]);
  const [bonoOnomastico, setBonoOnomastico] = useState<number | null>(null);
  // Piso de la subvención de un convenio de prácticas (Ley 28518, art. 45).
  const [rmvVigente, setRmvVigente] = useState<number | null>(null);
  const [ritVersion, setRitVersion] = useState<string | null>(null);
  const [ritFecha, setRitFecha] = useState<string | null>(null);
  const [firmante, setFirmante] = useState(FIRMANTE_POR_DEFECTO);
  // La firma escaneada de QUIEN ESTÁ USANDO EL PANEL. `fn_mi_firma()` no puede
  // devolver la de otra persona, y eso es deliberado (0076/0147): estampar la
  // firma de Felipe desde la sesión de alguien más es justo lo que esas
  // migraciones existen para impedir.
  const [firmaUrl, setFirmaUrl] = useState<string | null>(null);
  const [esFirmante, setEsFirmante] = useState(false);
  const [contratos, setContratos] = useState<ContratoFila[]>([]);
  // El tablero parte de las PERSONAS, no de los contratos: el historial arranca
  // de `contratos_generados`, así que quien no tiene ninguno es invisible ahí —
  // y con veinte venciendo el mismo día, «¿a quién le falta?» es la pregunta
  // que hay que poder hacer. Ver migración 0287.
  const [tablero, setTablero] = useState<FilaTablero[]>([]);

  const [personaId, setPersonaId] = useState("");
  const [tipo, setTipo] = useState<"nuevo" | "renovacion" | "adendum" | "convenio_practicas" | "indefinido">(
    "renovacion",
  );
  const [cargoEditado, setCargoEditado] = useState("");
  const [causaEditada, setCausaEditada] = useState("");
  const [funcionesEditadas, setFuncionesEditadas] = useState("");
  // Solo para tipo === "convenio_practicas" (0333). Desde la 0348 el
  // preprofesional es TRIPARTITO (CAYLA + centro de formación + practicante,
  // art. 12 y ss. Ley 28518) — estos cuatro son del centro, que solo
  // corresponde a esa modalidad.
  const [planCapacitacionEditado, setPlanCapacitacionEditado] = useState("");
  const [centroFormacionNombreEditado, setCentroFormacionNombreEditado] = useState("");
  const [centroFormacionRucEditado, setCentroFormacionRucEditado] = useState("");
  const [centroFormacionDomicilioEditado, setCentroFormacionDomicilioEditado] = useState("");
  const [centroFormacionRepresentanteEditado, setCentroFormacionRepresentanteEditado] = useState("");
  const [carreraEspecialidadEditada, setCarreraEspecialidadEditada] = useState("");
  const [cicloAcademicoEditado, setCicloAcademicoEditado] = useState("");
  // Solo profesional (0348): "Bachiller en X — Universidad Y, egresado el Z".
  const [gradoTituloTextoEditado, setGradoTituloTextoEditado] = useState("");
  // Convenio elegido A MANO para alguien cuya ficha no dice tipo_vinculo=
  // 'practicante' (0348 — antes solo se podía generar cambiando la ficha
  // primero en Equipo). Sin esto, `persona.practicante_modalidad` sale
  // siempre null para esa persona y no hay de dónde sacar 30h/48h.
  const [modalidadManualEditada, setModalidadManualEditada] = useState<"preprofesional" | "profesional" | "">("");
  // Anexo I — Plan Específico de Aprendizaje (0348, ambas modalidades).
  const [areaProyectoEditado, setAreaProyectoEditado] = useState("");
  const [objetivoFormativoGeneralEditado, setObjetivoFormativoGeneralEditado] = useState("");
  const [supervisorAsignadoEditado, setSupervisorAsignadoEditado] = useState("");
  const [hitoMes3Editado, setHitoMes3Editado] = useState("");
  const [hitoMes6Editado, setHitoMes6Editado] = useState("");
  const [activosLibre, setActivosLibre] = useState("");
  const [adendumEditado, setAdendumEditado] = useState("");
  const [ciudadEditada, setCiudadEditada] = useState("");
  // Sin esto marcado, un Anexo IV vacío es indistinguible de uno olvidado —
  // decisión de Felipe (2026-08-19): un campo vacío no basta, hay que
  // declararlo a propósito.
  const [sinActivosAdicionales, setSinActivosAdicionales] = useState(false);
  const [fechaInicio, setFechaInicio] = useState("");
  const [fechaFin, setFechaFin] = useState("");

  const [generando, setGenerando] = useState(false);
  const [borrador, setBorrador] = useState<{ id: string; html: string } | null>(null);
  // El texto congelado de un contrato del historial, al abrirlo para
  // reimprimirlo. Estado propio y no `borrador`: el efecto que descarta el
  // borrador al editar el formulario no debe cerrar lo que se está mirando.
  const [documentoAbierto, setDocumentoAbierto] = useState<string | null>(null);

  // "Ver / imprimir" abre el documento en una ventana modal en vez de
  // agregarlo al final de la página: con varios contratos en el archivo, cada
  // clic hacía la página más larga en lugar de solo mostrar uno.
  useEffect(() => {
    if (!documentoAbierto) return;
    function alPresionar(e: KeyboardEvent) {
      if (e.key === "Escape") setDocumentoAbierto(null);
    }
    window.addEventListener("keydown", alPresionar);
    return () => window.removeEventListener("keydown", alPresionar);
  }, [documentoAbierto]);

  const [subiendoPara, setSubiendoPara] = useState<string | null>(null);
  const [archivo, setArchivo] = useState<File | null>(null);
  // NACE CON LA FECHA DE HOY, no vacía. Ver la regla en CLAUDE.md: un campo de
  // fecha vacío que bloquea el envío depende de que el navegador entregue el
  // valor, y Safari no siempre lo hace — el 2026-08-26 un descanso médico real
  // no se pudo registrar por eso, con la fecha pintada en el campo y vacía por
  // dentro. Hoy es lo más probable para un papel que se acaba de firmar, se ve
  // en pantalla y se corrige en un clic.
  const [fechaFirma, setFechaFirma] = useState(hoyLima());
  const [progreso, setProgreso] = useState<number | null>(null);
  const [guardandoFirma, setGuardandoFirma] = useState(false);

  const [anulando, setAnulando] = useState<string | null>(null);
  const [motivoAnular, setMotivoAnular] = useState("");

  const { avisar } = useToast();

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
    const [ps, ss, dp, sal, params, rit, ctr, tab, cfg, fichas, firma, yo] = await Promise.all([
      // Sin `.eq("en_planilla", true)`: una practicante también genera un
      // documento acá (su convenio, 0333) aunque `en_planilla` le salga
      // false. Se filtra en el cliente por `en_planilla || tipo_vinculo ===
      // "practicante"` — mismo criterio que ya usa `vinculo.ts` y la boleta,
      // no un `.or()` de PostgREST nuevo que aprender.
      supabase
        .from("personas")
        .select("id, nombres, apellidos, documento, cargo, sede_base_id, sede_fisica_id, email, fecha_ingreso, fecha_fin_contrato, cobra_movilidad, personal_direccion, sueldo_fijo, en_planilla, tipo_vinculo, practicante_modalidad")
        .eq("estado", "activo")
        .order("apellidos"),
      supabase.from("sedes").select("id, nombre, codigo, ciudad"),
      supabase.from("datos_personales").select("persona_id, nombre_dni, direccion, genero"),
      supabase.from("asignaciones_salario").select("persona_id, salario_mensual_soles").is("vigente_hasta", null),
      // Movilidad, bono y RMV: la fila vigente HOY. Sin fila aplicable, cae a
      // null y el contrato lo dice en vez de inventar un monto — misma
      // regla que /admin/documentacion. La RMV es el piso de la subvención
      // de un convenio de prácticas (Ley 28518, art. 45).
      supabase
        .from("parametros_laborales")
        .select("clave, valor, sede_codigo")
        .in("clave", ["movilidad_diaria", "bono_onomastico", "rmv"])
        .lte("vigente_desde", hoy)
        .is("vigente_hasta", null),
      // La versión vigente del RIT. Se lee de la tabla, no se escribe a
      // mano: es exactamente el dato que este repo prohíbe hardcodear.
      supabase
        .from("documentos_institucionales")
        .select("version, etiqueta_version, vigente_desde")
        .eq("tipo", "rit")
        .lte("vigente_desde", hoy)
        .order("vigente_desde", { ascending: false })
        .limit(1),
      supabase.rpc("fn_contratos_listar"),
      supabase.rpc("fn_contratos_tablero"),
      // Quién firma por CAYLA (0147) — dato administrable, no escrito acá.
      supabase.from("configuracion").select("valor").eq("clave", "firmante_empresa").maybeSingle(),
      // Las fichas SIN filtrar por `en_planilla`: quien firma por la empresa no
      // tiene por qué estar en planilla —puede ser accionista— y buscarlo en la
      // lista del desplegable lo dejaría sin nombre ni DNI en el contrato.
      supabase.from("personas").select("id, nombres, apellidos, documento").eq("estado", "activo"),
      // Mi propia firma escaneada. Solo la mía: fn_mi_firma no acepta parámetros.
      supabase.rpc("fn_mi_firma"),
      supabase.rpc("fn_persona_actual_id"),
    ]);

    setPersonas(
      ((ps.data as Persona[]) ?? []).filter((p) => p.en_planilla || p.tipo_vinculo === "practicante"),
    );
    setSedes((ss.data as Sede[]) ?? []);
    setDatosPersonales((dp.data as DatoPersonal[]) ?? []);
    setSalarios((sal.data as Salario[]) ?? []);

    // El firmante: su persona_id y cargo vienen de `configuracion`; su nombre y
    // su DNI, de la ficha de esa persona — no de un literal en este archivo.
    const cfgValor = (cfg.data as { valor: { persona_id?: string; cargo?: string } } | null)?.valor;
    const firmanteId = cfgValor?.persona_id ?? null;
    type Ficha = { id: string; nombres: string; apellidos: string; documento: string | null };
    const fichaFirmante = ((fichas.data as Ficha[]) ?? []).find((p) => p.id === firmanteId);
    setFirmante({
      nombre: fichaFirmante ? `${fichaFirmante.nombres} ${fichaFirmante.apellidos}` : FIRMANTE_POR_DEFECTO.nombre,
      dni: fichaFirmante?.documento ?? FIRMANTE_POR_DEFECTO.dni,
      cargo: cfgValor?.cargo ?? FIRMANTE_POR_DEFECTO.cargo,
    });

    const miFirma = typeof firma.data === "string" ? firma.data : null;
    setFirmaUrl(miFirma?.startsWith("data:image") ? miFirma : null);
    setEsFirmante(Boolean(firmanteId) && firmanteId === (yo.data as string | null));

    const paramsData = (params.data as Parametro[]) ?? [];
    setMovilidadTarifas(paramsData.filter((p) => p.clave === "movilidad_diaria"));
    const bono = paramsData.find((p) => p.clave === "bono_onomastico");
    setBonoOnomastico(bono ? Number(bono.valor) : null);
    const rmv = paramsData.find((p) => p.clave === "rmv");
    setRmvVigente(rmv ? Number(rmv.valor) : null);

    const ritFila = ((rit.data as { version: number; etiqueta_version: string | null; vigente_desde: string }[] | null) ?? [])[0];
    // `version` es un CORRELATIVO interno —cuántas veces se ha publicado un
    // documento de ese tipo—, no la versión editorial. La 0265 lo dejó escrito:
    // «con el Reglamento 4.0 publicado como `version = 1`, el 5.0 será la 2: el
    // desfase de tres se queda para siempre», y por eso agregó `etiqueta_version`.
    // Citándolo mal, los veinte contratos remitirían a un «RIT versión 1» que no
    // existe: el papel que el equipo firmó dice 4.0.
    setRitVersion(ritFila ? String(ritFila.etiqueta_version ?? ritFila.version) : null);
    setRitFecha(ritFila ? formatearFecha(ritFila.vigente_desde) : null);

    setContratos((ctr.data as ContratoFila[]) ?? []);
    setTablero((tab.data as FilaTablero[]) ?? []);
    setCargando(false);
  }, [supabase, router]);

  useEffect(() => {
    void cargar();
  }, [cargar]);

  // EL TIPO SE REPONE AL CAMBIAR DE PERSONA, y esto no es comodidad.
  //
  // Sin este efecto, elegir «generar» en el tablero sobre un ingreso nuevo deja
  // `tipo = "nuevo"`, y al cambiar de persona en el desplegable ese «nuevo» se
  // queda pegado: el efecto de abajo repone cargo, causa, funciones y fechas
  // pero NO el tipo. La siguiente persona —con años de servicio— se llevaría la
  // cláusula TERCERA de contrato nuevo, o sea un período de prueba de tres
  // meses «sin expresión de causa y sin derecho a indemnización». Es el mismo
  // defecto que se cerró el 2026-08-24 por el otro camino; cerrarlo solo en el
  // botón del tablero dejaba esta puerta abierta.
  //
  // Va en su propio efecto y no dentro del de abajo porque aquel depende de
  // `tipo`: escribirlo ahí lo haría dispararse a sí mismo.
  useEffect(() => {
    const p = personas.find((x) => x.id === personaId);
    if (!p) return;
    setTipo(tipoQueCorresponde(p.fecha_ingreso, hoyLima()));
    // `personas` fuera de las dependencias por la misma razón que el efecto de
    // abajo: `cargar()` la devuelve con otra referencia y repondría el tipo
    // que quien usa la pantalla acaba de elegir a mano.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [personaId]);

  // Al cambiar de persona o de tipo, se reponen los campos editables con un
  // punto de partida razonable — y se descarta cualquier borrador anterior,
  // que ya no corresponde a lo que se está editando ahora.
  useEffect(() => {
    const p = personas.find((x) => x.id === personaId);
    setBorrador(null);
    setDocumentoAbierto(null);
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
    setFuncionesEditadas(FUNCIONES_PLACEHOLDER);
    setActivosLibre("");
    setSinActivosAdicionales(false);
    setAdendumEditado("");
    setCiudadEditada("");
    setPlanCapacitacionEditado("");
    setCentroFormacionNombreEditado("");
    setCentroFormacionRucEditado("");
    setCentroFormacionDomicilioEditado("");
    setCentroFormacionRepresentanteEditado("");
    setCarreraEspecialidadEditada("");
    setCicloAcademicoEditado("");
    setGradoTituloTextoEditado("");
    setAreaProyectoEditado("");
    setObjetivoFormativoGeneralEditado("");
    setSupervisorAsignadoEditado("");
    setHitoMes3Editado("");
    setHitoMes6Editado("");
    setModalidadManualEditada("");

    const inicio = tipo === "renovacion" && p.fecha_fin_contrato ? sumarDias(p.fecha_fin_contrato, 1) : hoyLima();
    setFechaInicio(inicio);
    // La fecha de fin NO arranca vacía (regla de la casa del 2026-08-26): su
    // vacío bloquea «Generar borrador», y en Safari un valor tecleado a mano
    // puede verse en pantalla sin llegar nunca al estado de React. El 2026-09-04
    // pasó justo eso con un convenio: 03/12/2026 a la vista y el botón apagado.
    // Nace con el plazo más probable —tres meses para un convenio, un año para
    // un contrato modal— y se cambia en un clic.
    const esConvenioDeEstaPersona = p.tipo_vinculo === "practicante" || tipo === "convenio_practicas";
    setFechaFin(finDePlazo(inicio, esConvenioDeEstaPersona ? 3 : 12));
    // Deliberadamente NO depende de `personas`/`sedeNombreMap`: generar un
    // borrador llama a `cargar()`, que trae esos dos arreglos de nuevo con una
    // referencia distinta aunque el contenido sea el mismo. Si estuvieran acá,
    // cada "Generar borrador" borraba el formulario que se acababa de llenar.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [personaId, tipo]);

  // Cualquier edición posterior invalida el borrador ya generado: lo que se
  // imprime tiene que ser exactamente lo que se congeló en la base, nunca una
  // versión editada después de generarlo.
  useEffect(() => {
    setBorrador(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    cargoEditado,
    causaEditada,
    funcionesEditadas,
    activosLibre,
    sinActivosAdicionales,
    adendumEditado,
    ciudadEditada,
    planCapacitacionEditado,
    centroFormacionNombreEditado,
    centroFormacionRucEditado,
    centroFormacionDomicilioEditado,
    centroFormacionRepresentanteEditado,
    carreraEspecialidadEditada,
    cicloAcademicoEditado,
    gradoTituloTextoEditado,
    areaProyectoEditado,
    objetivoFormativoGeneralEditado,
    supervisorAsignadoEditado,
    hitoMes3Editado,
    hitoMes6Editado,
    modalidadManualEditada,
    fechaInicio,
    fechaFin,
  ]);

  const persona = personas.find((p) => p.id === personaId) ?? null;
  // Una practicante no tiene "nuevo ingreso" ni "renovación" — su único
  // documento es el convenio (0333), y esto NO se resuelve reponiendo `tipo`
  // desde un efecto (ver el de abajo, que solo mira `fecha_ingreso`): es un
  // valor DERIVADO del render, para no encadenar un segundo `setState` por
  // cada cambio de persona. `tipo` sigue siendo la fuente para nuevo/
  // renovación/adendum — elegibles a mano — y esto solo la reemplaza cuando
  // la persona es practicante, sin que quien usa la pantalla tenga que saber
  // por qué el desplegable de tipo desaparece.
  const tipoEfectivo = persona?.tipo_vinculo === "practicante" ? "convenio_practicas" : tipo;
  // La modalidad efectiva: la de la ficha si la persona YA es practicante
  // (0324) — eso no se pisa a mano —, o la elegida en pantalla cuando el
  // convenio se generó eligiéndolo del desplegable para alguien que no está
  // marcado así (0348: antes esto no existía, había que ir a Equipo primero).
  const modalidadEfectiva: "preprofesional" | "profesional" | null =
    persona?.practicante_modalidad === "preprofesional" || persona?.practicante_modalidad === "profesional"
      ? persona.practicante_modalidad
      : modalidadManualEditada || null;
  const datoPersonal = persona ? (datosPersonales.find((d) => d.persona_id === persona.id) ?? null) : null;
  const salarioVigente = persona
    ? (salarios.find((s) => s.persona_id === persona.id)?.salario_mensual_soles ?? null)
    : null;

  const sedeCod = persona?.sede_base_id ? (sedeCodigo.get(persona.sede_base_id) ?? "") : "";
  const sedeNom = persona?.sede_base_id ? (sedeNombreMap.get(persona.sede_base_id) ?? "") : "";
  // La ciudad donde se firma. Viene de la sede cuando la sede ES un local
  // (tienda, taller); Central no lo es —es una clasificación de personal
  // administrativo, y esa gente puede estar en cualquier ciudad (0282)—, así
  // que ahí se elige a mano. Editable siempre: un contrato puede firmarse en
  // otra ciudad por una razón puntual, y eso no debería obligar a tocar la sede.
  const ciudadDeLaSede = persona?.sede_base_id
    ? (sedes.find((s) => s.id === persona.sede_base_id)?.ciudad ?? null)
    : null;
  const ciudadFinal = (ciudadEditada.trim() || ciudadDeLaSede) ?? null;
  const esAdendum = tipoEfectivo === "adendum";
  const esConvenio = tipoEfectivo === "convenio_practicas";
  // Un indefinido no tiene causa objetiva (no es modalidad temporal) ni fecha
  // de fin — comparte todo lo demás con el contrato a plazo fijo (0347).
  const esIndefinido = tipoEfectivo === "indefinido";
  // `coalesce(sede_fisica, sede_base)` — el mismo criterio de
  // `fn_planilla_calcular` (0166). Leerlo solo de la sede base le imprimía a
  // quien tiene base Central y trabaja en AQP la tarifa de Central, que no
  // existe, y el contrato salía prometiendo S/ 0.00 de movilidad.
  const movilidadTarifa = persona ? tarifaDeSede(persona.sede_fisica_id ?? persona.sede_base_id) : null;

  // Un indefinido no exige fechaFin — es justamente lo que no tiene (0347).
  const datosParaGenerar: DatosContrato | null =
    persona &&
    datoPersonal?.nombre_dni &&
    persona.documento &&
    salarioVigente !== null &&
    fechaInicio &&
    (fechaFin || esIndefinido)
      ? {
          tipo: tipoEfectivo,
          nombreDni: datoPersonal.nombre_dni,
          documento: persona.documento,
          direccion: datoPersonal.direccion,
          genero: datoPersonal.genero === "masculino" ? "masculino" : datoPersonal.genero === "femenino" ? "femenino" : null,
          cargo: cargoEditado || persona.cargo || "",
          email: persona.email,
          sedeNombre: sedeNom,
          sedeCodigo: sedeCod,
          ciudad: ciudadFinal,
          causaObjetivaTexto: causaEditada,
          funcionesTexto: funcionesEditadas,
          fechaInicio,
          fechaFin,
          fechaIngresoOriginal: persona.fecha_ingreso,
          remuneracionMensual: salarioVigente,
          cobraMovilidad: persona.cobra_movilidad,
          movilidadDiaria: movilidadTarifa,
          bonoOnomastico: bonoOnomastico ?? 0,
          ritVersion: ritVersion ?? "[sin publicar en el sistema]",
          ritFecha: ritFecha ?? "[sin publicar en el sistema]",
          activosPrincipales: sedeCod ? (ACTIVOS_PRINCIPALES_POR_SEDE[sedeCod] ?? "") : "",
          activosLibre,
          adendumTexto: adendumEditado,
          firmanteNombre: firmante.nombre,
          firmanteDni: firmante.dni,
          firmanteCargo: firmante.cargo,
          practicanteModalidad: modalidadEfectiva,
          planCapacitacionTexto: planCapacitacionEditado,
          centroFormacionNombre: centroFormacionNombreEditado.trim() || null,
          centroFormacionRuc: centroFormacionRucEditado.trim() || null,
          centroFormacionDomicilio: centroFormacionDomicilioEditado.trim() || null,
          centroFormacionRepresentante: centroFormacionRepresentanteEditado.trim() || null,
          carreraEspecialidad: carreraEspecialidadEditada.trim() || null,
          cicloAcademico: cicloAcademicoEditado.trim() || null,
          gradoTituloTexto: gradoTituloTextoEditado.trim() || null,
          // Estos cinco van dentro de una frase o de un «Etiqueta: valor» en
          // un solo párrafo. Desde que se escriben en un AreaTexto admiten
          // Enter, y un Enter final —el gesto natural al terminar— salía como
          // «Proyecto ERP , en el puesto» y un campo con solo «⏎» pasaba por
          // lleno. Se aplanan a una línea, igual que se leerán.
          areaProyecto: unaLinea(areaProyectoEditado),
          objetivoFormativoGeneral: unaLinea(objetivoFormativoGeneralEditado),
          supervisorAsignado: unaLinea(supervisorAsignadoEditado),
          hitoMes3: unaLinea(hitoMes3Editado),
          hitoMes6: unaLinea(hitoMes6Editado),
        }
      : null;

  const previewHtml = datosParaGenerar ? construirContrato(datosParaGenerar) : null;

  // Campos que un olvido puede dejar exactamente iguales a como empezaron — y
  // un campo sin tocar no debe poder imprimirse como si fuera una respuesta.
  // Decisión de Felipe (2026-08-19).
  const bloqueos: string[] = [];
  // Estos cuatro son los que dejan `datosParaGenerar` en null: sin ellos el
  // botón se apaga sin ninguna de las líneas rojas de abajo, y quien llena el
  // formulario de la derecha no tiene forma de saber que el problema está en
  // datos que se cargan en OTRA pantalla. Se ven en el resumen (DNI, Nombre
  // legal, Sueldo base vigente) pero un dato en gris no explica que bloquea.
  if (persona && !persona.documento) {
    bloqueos.push("Carga el DNI en Datos personales — sin DNI no se puede generar el contrato.");
  }
  if (persona && !datoPersonal?.nombre_dni) {
    bloqueos.push('Carga el nombre completo (como en el DNI) en Datos personales — sin él no se puede generar el contrato.');
  }
  if (persona && salarioVigente === null) {
    bloqueos.push("No tiene un sueldo vigente asignado en Equipo — sin sueldo no se puede generar el contrato.");
  }
  if (persona && !fechaInicio) {
    bloqueos.push("Elige la fecha de inicio.");
  }
  if (persona && !esIndefinido && !fechaFin) {
    bloqueos.push("Elige la fecha de fin.");
  }
  if (persona && esAdendum && adendumEditado.trim() === "") {
    bloqueos.push("Escribe qué se modifica del contrato vigente.");
  }
  // Igualdad exacta contra el relleno NO basta: borrar el textarea —el gesto
  // natural antes de escribir— deja "" , que no es el placeholder, y el Anexo I
  // salía en blanco. Un anexo de funciones vacío es el que se cita («la función
  // 14 del Anexo I») el día que haya que sustentar un incumplimiento.
  if (persona && !esAdendum && !esConvenio && (funcionesEditadas.trim() === FUNCIONES_PLACEHOLDER || funcionesEditadas.trim() === "")) {
    bloqueos.push('Completa "Funciones del cargo" — está vacío o sigue con el texto de relleno.');
  }
  // La causa objetiva arranca con una nota dirigida a quien usa el panel. Esa
  // nota entra TAL CUAL a la cláusula PRIMERA (`<p>${d.causaObjetivaTexto}</p>`):
  // un contrato firmado que lleva dentro «[REVISAR antes de imprimir…]» no solo
  // queda en ridículo, debilita justo la cláusula que sustenta la modalidad
  // temporal ante una inspección. Ni un convenio ni un indefinido usan
  // `causaObjetivaTexto` (no tienen causa objetiva — uno no es contrato de
  // trabajo, el otro no es modalidad temporal), así que esta nota de relleno
  // no es asunto suyo.
  if (persona && !esConvenio && !esIndefinido && causaEditada.includes("[REVISAR")) {
    bloqueos.push("Revisa y quita la nota «[REVISAR antes de imprimir…]» de la causa objetiva.");
  }
  // Un beneficio con monto es un monto REAL o no se imprime. Sin tarifa vigente
  // el contrato decía «asignación diaria de movilidad (S/ 0.00)», que promete
  // por escrito un beneficio de cero. Ninguno de los dos aplica a un convenio:
  // movilidad y bono de onomástico son beneficios de planilla (en_planilla),
  // y una practicante no está en planilla (0322).
  if (persona && !esAdendum && !esConvenio && persona.cobra_movilidad && movilidadTarifa === null) {
    bloqueos.push("No hay tarifa de movilidad vigente para su sede: publícala antes de generar el contrato.");
  }
  if (persona && !esAdendum && !esConvenio && !(bonoOnomastico && bonoOnomastico > 0)) {
    bloqueos.push("No hay monto vigente del bono de onomástico: publícalo antes de generar el contrato.");
  }
  // Las dos exclusiones de pago que el texto no sabe describir todavía. El
  // contrato les promete jornada de 48 h con sobretiempo al 25 %/35 % y pago
  // proporcional a las horas; a personal de dirección la ley lo excluye
  // (art. 5, D.S. 007-2002-TR) y a sueldo fijo su pago no depende de horas.
  // Se bloquea en vez de improvisar un texto: un contrato es para firmarlo.
  // Un convenio nunca declara jornada de 48h fija con sobretiempo — su
  // cláusula de jornada ya depende de la modalidad, no de estos dos flags.
  if (persona && !esAdendum && !esConvenio && persona.personal_direccion) {
    bloqueos.push("Está marcada como personal de dirección: el texto de jornada y sobretiempo no le corresponde. Revísalo con criterio legal antes de generar.");
  }
  if (persona && !esAdendum && !esConvenio && persona.sueldo_fijo) {
    bloqueos.push("Cobra sueldo fijo: la cláusula de remuneración proporcional a las horas no le corresponde. Revísalo con criterio legal antes de generar.");
  }
  if (persona && !esAdendum && !esConvenio && activosLibre.trim() === "" && !sinActivosAdicionales) {
    bloqueos.push("Marca la casilla de activos, o completa el ajuste específico del Anexo IV.");
  }
  // ── Lo que sí exige un convenio, y nada de lo anterior sabe pedir ─────────
  if (persona && esConvenio && planCapacitacionEditado.trim() === "") {
    bloqueos.push("Completa el plan de capacitación específico — un convenio no tiene funciones, tiene un plan de capacitación (Ley 28518, art. 15).");
  }
  if (persona && esConvenio && modalidadEfectiva === null) {
    bloqueos.push(
      persona.tipo_vinculo === "practicante"
        ? "Asígnale modalidad (preprofesional o profesional) en Equipo antes de generar su convenio — decide su jornada máxima (30h/48h)."
        : "Elige la modalidad (preprofesional o profesional) — decide su jornada máxima (30h/48h).",
    );
  }
  if (persona && esConvenio && salarioVigente !== null && rmvVigente !== null && salarioVigente < rmvVigente) {
    bloqueos.push(`La subvención (S/ ${salarioVigente.toFixed(2)}) está por debajo de la RMV vigente (S/ ${rmvVigente.toFixed(2)}) — Ley 28518, art. 45: no puede ser menor a jornada completa.`);
  }
  // Estos campos no tenían bloqueo (hallazgo #11, auditoría 2026-09-03/04):
  // vacíos, `contrato-texto.ts` los imprime tal cual como «[completar]» dentro
  // de una cláusula real del convenio o del Anexo I — no en un aparte, sino en
  // el cuerpo que las partes firman. `gradoTituloTexto` queda afuera a
  // propósito: su propia etiqueta en el formulario lo marca "referencial", no
  // una declaración que el centro de formación firme.
  if (persona && esConvenio && modalidadEfectiva === "preprofesional") {
    if (centroFormacionNombreEditado.trim() === "") {
      bloqueos.push("Completa la razón social del centro de formación.");
    }
    if (centroFormacionRucEditado.trim() === "") {
      bloqueos.push("Completa el RUC del centro de formación.");
    }
    if (centroFormacionDomicilioEditado.trim() === "") {
      bloqueos.push("Completa el domicilio del centro de formación.");
    }
    if (centroFormacionRepresentanteEditado.trim() === "") {
      bloqueos.push("Completa el representante del centro de formación.");
    }
    if (carreraEspecialidadEditada.trim() === "") {
      bloqueos.push("Completa la carrera / especialidad de la practicante.");
    }
    if (cicloAcademicoEditado.trim() === "") {
      bloqueos.push("Completa el ciclo académico de la practicante.");
    }
  }
  if (persona && esConvenio && areaProyectoEditado.trim() === "") {
    bloqueos.push("Completa el área / proyecto de destino (Anexo I).");
  }
  if (persona && esConvenio && objetivoFormativoGeneralEditado.trim() === "") {
    bloqueos.push("Completa el objetivo formativo general del Anexo I.");
  }
  if (persona && esConvenio && supervisorAsignadoEditado.trim() === "") {
    bloqueos.push("Completa el/la supervisor(a) asignado(a) del Anexo I.");
  }
  if (persona && esConvenio && hitoMes3Editado.trim() === "") {
    bloqueos.push("Completa el hito de evaluación del mes 3 del Anexo I.");
  }
  if (persona && esConvenio && hitoMes6Editado.trim() === "") {
    bloqueos.push("Completa el hito de evaluación del mes 6 del Anexo I.");
  }
  // La ciudad no bloquea —el documento lo dice en su propio texto— pero avisar
  // acá evita descubrirlo recién al leer el PDF impreso.
  if (persona && !ciudadFinal) {
    bloqueos.push("Escribe la ciudad donde se firma el contrato.");
  }
  // EL TOPE DE LA MODALIDAD. El contrato se emite siempre bajo el art. 57 del
  // TUO del D. Leg. 728 —«inicio o incremento de actividad»—, y esa modalidad
  // tiene un máximo de TRES años; el art. 74 pone cinco al conjunto de
  // contratos sujetos a modalidad con el mismo empleador. Pasado el tope, el
  // art. 77 desnaturaliza el vínculo a indefinido POR LEY, sin que nadie lo
  // decida y sin que nada en el sistema lo dijera: `fn_contratos_desnaturalizados`
  // solo mira quien marcó DESPUÉS de su fecha de fin, no la acumulación.
  //
  // Avisa, no bloquea: renovar pasado el tope puede ser una decisión tomada a
  // sabiendas, y quien la tome tiene que verlo escrito antes de firmar.
  const avisos: string[] = [];
  if (persona && !esAdendum && !esConvenio && !esIndefinido && fechaFin) {
    const anios = (new Date(`${fechaFin}T00:00:00`).getTime() - new Date(`${persona.fecha_ingreso}T00:00:00`).getTime()) / 31_557_600_000;
    if (anios > 5) {
      avisos.push(`Al terminar este contrato acumularía ${anios.toFixed(1)} años a plazo fijo, sobre el tope de CINCO del artículo 74. El vínculo quedaría desnaturalizado a indefinido por el artículo 77.`);
    } else if (anios > 3) {
      avisos.push(`Al terminar este contrato acumularía ${anios.toFixed(1)} años bajo la modalidad del artículo 57, cuyo máximo es de TRES. Conviene cambiar de modalidad o pasar a indefinido.`);
    }
  }
  // El tope del convenio (12 meses continuos, Ley 28518 art. 30 y ss.) tiene
  // una excepción legal real —que el centro de formación determine una
  // extensión mayor— que este sistema no puede verificar solo. Avisa, no
  // bloquea: mismo criterio que ya eligió la 0324 para la jornada 30h/48h
  // ("Dynamic avisa, nunca sanciona solo").
  if (persona && esConvenio && fechaInicio && fechaFin) {
    const meses = (new Date(`${fechaFin}T00:00:00`).getTime() - new Date(`${fechaInicio}T00:00:00`).getTime()) / 2_629_800_000;
    if (meses > 12) {
      avisos.push(`Este convenio duraría ${meses.toFixed(1)} meses, sobre el tope de DOCE meses continuos (Ley 28518, art. 30). Solo es válido si el centro de formación sustenta por escrito una extensión mayor — de lo contrario, arriesga desnaturalización.`);
    }
  }

  async function generarBorrador() {
    if (!datosParaGenerar || !persona) {
      avisar(
        "error",
        "Faltan datos para generar el contrato: revisa DNI, nombre legal (Ficha personal), sueldo vigente y las fechas.",
      );
      return;
    }
    if (bloqueos.length > 0) {
      avisar("error", bloqueos[0]);
      return;
    }
    setGenerando(true);
    const html = construirContrato(datosParaGenerar);
    const { data: id, error } = await supabase.rpc("fn_contrato_registrar", {
      p_persona_id: persona.id,
      p_tipo: datosParaGenerar.tipo,
      p_cargo: datosParaGenerar.cargo,
      p_sede_id: persona.sede_base_id,
      p_remuneracion_mensual: datosParaGenerar.remuneracionMensual,
      p_fecha_inicio: fechaInicio,
      // Un indefinido nunca lleva fecha de fin (0347) — fn_contrato_registrar
      // la rechaza si no es null para ese tipo.
      p_fecha_fin: esIndefinido ? null : fechaFin,
      // La jornada del contrato es siempre 48h (ver contrato-texto.ts); no hay
      // un número calculado del horario que guardar acá.
      p_horas_semanales: null,
      p_documento_html: html,
    });
    setGenerando(false);
    if (error || !id) {
      avisar("error", mensajeDeError(error, "generar el contrato"));
      return;
    }
    setDocumentoAbierto(null);
    setBorrador({ id: id as string, html });
    await cargar();
    avisar("ok", "Borrador generado. Revísalo, imprímelo y fírmalo; después sube el escaneo desde el historial.");
  }

  function imprimir() {
    window.print();
  }

  function abrirSubida(id: string) {
    setSubiendoPara(id);
    setArchivo(null);
    setFechaFirma(hoyLima());
  }

  async function guardarFirma() {
    if (!subiendoPara) return;
    if (!archivo) {
      avisar("error", "Falta el escaneo firmado.");
      return;
    }
    if (archivo.size > MAX_BYTES) {
      avisar("error", `"${archivo.name}" pesa ${(archivo.size / 1048576).toFixed(1)} MB y el máximo es 50 MB.`);
      return;
    }
    if (!fechaFirma) {
      avisar("error", "Indica en qué fecha se firmó.");
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
      avisar("error", `El archivo no subió (${fallo}). Vuelve a intentarlo.`);
      return;
    }
    const { error } = await supabase.rpc("fn_contrato_registrar", {
      p_id: subiendoPara,
      p_storage_path: ruta,
      p_fecha_firma: fechaFirma,
    });
    setGuardandoFirma(false);
    if (error) {
      avisar("error", mensajeDeError(error, "registrar la firma"));
      return;
    }
    setSubiendoPara(null);
    await cargar();
    avisar("ok", "Contrato firmado registrado. La fecha de vencimiento de la persona se actualizó.");
  }

  async function anular() {
    if (!anulando) return;
    if (motivoAnular.trim().length < 3) {
      avisar("error", "Escribe por qué se anula.");
      return;
    }
    const { error } = await supabase.rpc("fn_contrato_anular", { p_id: anulando, p_motivo: motivoAnular.trim() });
    if (error) {
      avisar("error", mensajeDeError(error, "anular el contrato"));
      return;
    }
    setAnulando(null);
    setMotivoAnular("");
    await cargar();
    avisar("ok", "Contrato anulado. Sigue guardado en el historial.");
  }

  /**
   * Abre el texto CONGELADO de un contrato ya generado, para volver a verlo o
   * reimprimirlo. Se lee de la base y no se regenera: reconstruirlo con los
   * datos de hoy daría otro documento —el sueldo o el cargo pueden haber
   * cambiado— y el que vale es el que se imprimió y se firmó.
   */
  async function abrirGenerado(id: string) {
    const { data, error } = await supabase
      .from("contratos_generados")
      .select("documento_html")
      .eq("id", id)
      .maybeSingle();
    if (error || !data) {
      avisar("error", mensajeDeError(error, "abrir el contrato"));
      return;
    }
    setDocumentoAbierto((data as { documento_html: string }).documento_html);
  }

  /** Anota que se entregó la copia o que se comunicó al MTPE. */
  async function marcarTramite(id: string, tramite: "copia" | "mtpe") {
    const { error } = await supabase.rpc("fn_contrato_marcar_tramite", {
      p_id: id,
      p_tramite: tramite,
      p_fecha: hoyLima(),
    });
    if (error) {
      avisar("error", mensajeDeError(error, "anotar el trámite"));
      return;
    }
    await cargar();
    avisar(
      "ok",
      tramite === "copia"
        ? "Anotada la entrega de copia a la colaboradora."
        : "Anotada la comunicación a la Autoridad Administrativa de Trabajo.",
    );
  }

  async function verDocumento(path: string) {
    const fallo = await abrirArchivoFirmado(supabase, "contratos", path);
    if (fallo) avisar("error", fallo);
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

  // Solo quien necesita algo. Un tablero donde casi todas las filas dicen «al
  // día» enseña a ignorarlo — mismo criterio que el tablero de Documentación,
  // que oculta a quien no tiene nada pendiente.
  const pendientes = tablero.filter((f) => f.estado !== "ok");
  // Cuántos son de los que no pueden esperar. Decide si el contador va en rojo:
  // el rojo de esta paleta es el acento sagrado, y gastarlo en «vence en tres
  // meses» lo vuelve invisible el día que diga «desnaturalizado».
  const graves = pendientes.filter((f) => ESTADO_TABLERO[f.estado]?.grave).length;

  // El archivo, agrupado por persona y en el orden en que ya vienen (el más
  // reciente primero). `Map` y no un objeto: conserva el orden de inserción,
  // que es el que decide la consulta.
  //
  // SIN `useMemo`, y a propósito: este bloque vive DESPUÉS de los `return`
  // de «cargando» y «sin permiso», así que un hook acá se salta en esos
  // renders y React revienta con el error 310 —«más hooks que en el render
  // anterior»—, que es lo que pasó al probarlo. Agrupar veinte filas no
  // cuesta nada; el hook sí.
  const porPersona = (() => {
    const m = new Map<string, ContratoFila[]>();
    for (const c of contratos) {
      const previo = m.get(c.persona);
      if (previo) previo.push(c);
      else m.set(c.persona, [c]);
    }
    return [...m.entries()];
  })();

  // `documentoAbierto` (un contrato del historial abierto con "Ver /
  // imprimir") ya no entra acá: se muestra en su propia ventana modal, más
  // abajo. Esto sigue siendo el borrador/previsualización en vivo mientras se
  // arma un contrato nuevo.
  const documentoAMostrar = borrador?.html ?? previewHtml;

  // LA FIRMA SE ESTAMPA AL MOSTRAR, NUNCA AL GUARDAR. Lo que la 0272 congela en
  // `documento_html` es el borrador SIN firmar; meterle la imagen convertiría un
  // borrador en algo que parece un documento ya firmado. Acá solo se reemplaza
  // el marcador para la vista y la impresión.
  //
  // Y solo si quien está usando el panel ES el firmante configurado: `fn_mi_firma`
  // devuelve únicamente la firma propia, así que no hay forma —ni la debe haber—
  // de estampar la de otra persona.
  const puedeEstampar = esFirmante && Boolean(firmaUrl);
  const htmlFinal = documentoAMostrar
    ? documentoAMostrar.replaceAll(
        MARCADOR_FIRMA_EMPRESA,
        puedeEstampar ? `<img src="${firmaUrl}" alt="Firma" />` : "&nbsp;",
      )
    : null;
  const htmlFinalAbierto = documentoAbierto
    ? documentoAbierto.replaceAll(MARCADOR_FIRMA_EMPRESA, puedeEstampar ? `<img src="${firmaUrl}" alt="Firma" />` : "&nbsp;")
    : null;

  return (
    <main className="p-6">
      <div className="print:hidden">
        <AdminNav />
      </div>

      <div className="mx-auto max-w-3xl space-y-6 print:hidden">
        <header>
          <h1 className="font-serif text-2xl">Contratos</h1>
          <p className="text-sm text-taupe">
            El contrato de cada integrante: generarlo, imprimirlo, archivarlo firmado.
          </p>
        </header>

        {/* EL TABLERO VA PRIMERO, Y PARTE DE LAS PERSONAS.
            El historial de abajo arranca de los contratos generados, así que
            quien no tiene ninguno es invisible ahí — y con veinte venciendo el
            mismo día, «¿a quién le falta?» es la pregunta que hay que poder
            hacer al abrir la pantalla, no la que hay que deducir.
            Cada fila lleva su acción: ver un pendiente sin poder resolverlo
            desde ahí obliga a buscar a esa persona a mano en el desplegable. */}
        {pendientes.length > 0 && (
          <section className="rounded-lg border border-sand bg-papel p-4">
            <h2 className="mb-3 font-serif text-lg">
              Necesitan atención{" "}
              <span className={graves > 0 ? "text-rojo" : "text-taupe"}>· {pendientes.length}</span>
            </h2>
            <ul className="divide-y divide-sand/60">
              {pendientes.map((f) => {
                const personaFila = personas.find((p) => p.id === f.persona_id);
                const esPracticanteFila = personaFila?.tipo_vinculo === "practicante";
                const e =
                  f.estado === "sin_contrato"
                    ? estadoSinContrato(f)
                    : (ESTADO_TABLERO[f.estado] ?? { texto: f.estado, grave: false });
                // Para una practicante, `fecha_fin_contrato`/`estado` los mueve
                // el tope legal de 12 meses (0336), no necesariamente lo que
                // dice su convenio — decirlo con las mismas palabras que un
                // contrato vencido ("contrato vencido") confundiría, así que
                // se nombra el tope explícitamente en vez de reusar el texto
                // genérico tal cual.
                const eFinal =
                  esPracticanteFila && f.estado === "vencido"
                    ? { ...e, texto: "superó el tope de 12 meses del convenio (art. 30, Ley 28518)" }
                    : esPracticanteFila && f.estado === "por_vencer"
                      ? { ...e, texto: "se acerca al tope de 12 meses del convenio" }
                      : esPracticanteFila && f.estado === "sin_vencimiento"
                        ? { ...e, texto: "sin fecha de fin en su convenio" }
                        : // Un indefinido nunca debe comunicación al MTPE (0347) — el
                          // texto genérico de "trámite pendiente" menciona esa
                          // comunicación, y ahí mentiría.
                          f.tipo === "indefinido" && f.estado === "tramite_pendiente"
                          ? { ...e, texto: "falta entregar copia a la colaboradora" }
                          : e;
                const tipoFila = esPracticanteFila
                  ? "convenio_practicas"
                  : tipoQueCorresponde(personaFila?.fecha_ingreso, hoyLima());
                return (
                  <li key={f.persona_id} className="flex flex-wrap items-baseline gap-x-3 gap-y-1 py-2">
                    <span className="min-w-0 flex-1 truncate">{f.persona}</span>
                    <span className="text-xs text-taupe">{f.sede}</span>
                    <span className={`text-sm ${eFinal.grave ? "text-rojo" : "text-taupe"}`}>
                      {eFinal.texto}
                      {f.estado === "desnaturalizado" && ` · ${f.dias_marcados_despues} días marcados`}
                      {f.estado === "por_vencer" && f.dias_restantes !== null && ` · ${f.dias_restantes} días`}
                      {/* El de papel también vence, y esa es la fecha que
                          manda mientras no haya uno nuevo firmado. */}
                      {f.estado === "sin_contrato" &&
                        f.fecha_fin_contrato !== null &&
                        ` · vence ${f.fecha_fin_contrato}`}
                    </span>
                    {/* La acción dice lo que hace. Quien ya tiene contrato y
                        lo que le falta es firmarlo o hacer un trámite no
                        necesita generar otro: necesita ABRIR el suyo. Decir
                        «generar» ahí invita a duplicarlo. */}
                    {NECESITA_CONTRATO.has(f.estado) ? (
                      <button
                        className="text-xs text-taupe underline underline-offset-2 hover:text-tinta"
                        onClick={() => {
                          setPersonaId(f.persona_id);
                          setTipo(tipoFila);
                        }}
                      >
                        {tipoFila === "convenio_practicas" ? "generar convenio" : tipoFila === "nuevo" ? "generar" : "renovar"}
                      </button>
                    ) : (
                      <button
                        className="text-xs text-taupe underline underline-offset-2 hover:text-tinta"
                        onClick={() => f.contrato_id && abrirGenerado(f.contrato_id)}
                      >
                        abrir
                      </button>
                    )}
                  </li>
                );
              })}
            </ul>
          </section>
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
              {persona?.tipo_vinculo === "practicante" ? (
                // Una practicante solo tiene un documento posible — no
                // "nuevo ingreso" ni "renovación", que son conceptos de un
                // contrato de trabajo (0333). Se fija sola y no se elige.
                <input
                  className="mt-1 w-full rounded border border-sand bg-crema p-2 text-taupe"
                  value="Convenio de prácticas"
                  disabled
                />
              ) : (
                <select
                  className="mt-1 w-full rounded border border-sand p-2"
                  value={tipo}
                  onChange={(e) =>
                    setTipo(
                      e.target.value as "nuevo" | "renovacion" | "adendum" | "indefinido" | "convenio_practicas",
                    )
                  }
                >
                  <option value="renovacion">Renovación</option>
                  <option value="nuevo">Nuevo ingreso</option>
                  <option value="indefinido">Indefinido</option>
                  {/* Elegible a mano desde la 0348 para alguien que no está
                      marcado tipo_vinculo="practicante" en su ficha — no
                      cambia esa ficha, solo genera el documento (ver el
                      aviso que sale más abajo cuando se elige así). */}
                  <option value="convenio_practicas">Convenio de prácticas</option>
                  <option value="adendum">Adendum</option>
                </select>
              )}
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
                  {esIndefinido ? (
                    <input
                      className="mt-1 w-full rounded border border-sand bg-crema p-2 text-taupe"
                      value="Sin fecha de fin — contrato indefinido"
                      disabled
                    />
                  ) : (
                    <input
                      type="date"
                      className="mt-1 w-full rounded border border-sand p-2"
                      value={fechaFin}
                      onChange={(e) => setFechaFin(e.target.value)}
                    />
                  )}
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
                Ciudad donde se firma
                <input
                  className="mt-1 w-full rounded border border-sand p-2"
                  placeholder={ciudadDeLaSede ?? "Arequipa, Lima o Trujillo"}
                  value={ciudadEditada}
                  onChange={(e) => setCiudadEditada(e.target.value)}
                />
                <span className="mt-1 block text-xs text-taupe">
                  {ciudadDeLaSede
                    ? `Si lo dejas vacío se usa ${ciudadDeLaSede}, la ciudad de la sede ${sedeNom}.`
                    : "Central no tiene una ciudad propia: su gente puede estar en cualquiera, así que hay que elegirla."}
                </span>
              </label>
              {/* Un adendum no repite el contrato ni sus anexos, así que los
                  campos que solo alimentan al contrato no se piden. Un
                  convenio (0333) no tiene causa objetiva ni funciones — tiene
                  un plan de capacitación específico (Ley 28518, art. 15). */}
              {esAdendum ? (
                <label className="block text-sm">
                  Qué se modifica del contrato vigente — una modificación por línea
                  <AreaTexto
                    className="mt-1 w-full rounded border border-sand p-2"
                    rows={4}
                    placeholder="Ej.: Se modifica la Cláusula Sexta, fijando la remuneración mensual base en S/ …"
                    value={adendumEditado}
                    onChange={(e) => setAdendumEditado(e.target.value)}
                  />
                </label>
              ) : esConvenio ? (
                <>
                  {persona.tipo_vinculo === "practicante" ? (
                    <label className="block text-sm">
                      Modalidad
                      <input
                        className="mt-1 w-full rounded border border-sand bg-crema p-2 text-taupe"
                        disabled
                        value={
                          persona.practicante_modalidad === "preprofesional"
                            ? "Preprofesional — 30h/semana (art. 44)"
                            : persona.practicante_modalidad === "profesional"
                              ? "Profesional — 48h/semana (art. 44)"
                              : "Sin asignar — ve a Equipo y elígela primero"
                        }
                      />
                    </label>
                  ) : (
                    <>
                      <label className="block text-sm">
                        Modalidad
                        <select
                          className="mt-1 w-full rounded border border-sand p-2"
                          value={modalidadManualEditada}
                          onChange={(e) => setModalidadManualEditada(e.target.value as "preprofesional" | "profesional" | "")}
                        >
                          <option value="">— elegir —</option>
                          <option value="preprofesional">Preprofesional — 30h/semana (art. 44)</option>
                          <option value="profesional">Profesional — 48h/semana (art. 44)</option>
                        </select>
                      </label>
                      <p className="text-xs text-taupe">
                        {persona.nombres} no está marcada como practicante en su ficha (Equipo) — generar este
                        convenio no cambia eso. Si el vínculo es permanente, márcala allá primero.
                      </p>
                    </>
                  )}
                  {/* El preprofesional es TRIPARTITO (CAYLA + centro de
                      formación + practicante, art. 12 y ss. Ley 28518) — el
                      profesional es bipartito y solo referencia su título
                      (0348). */}
                  {modalidadEfectiva === "preprofesional" ? (
                    <>
                      <div className="grid grid-cols-2 gap-3">
                        <label className="text-sm">
                          Centro de formación — razón social
                          <input
                            className="mt-1 w-full rounded border border-sand p-2"
                            placeholder="Ej.: Universidad Nacional de Trujillo"
                            value={centroFormacionNombreEditado}
                            onChange={(e) => setCentroFormacionNombreEditado(e.target.value)}
                          />
                        </label>
                        <label className="text-sm">
                          Centro de formación — RUC
                          <input
                            className="mt-1 w-full rounded border border-sand p-2"
                            value={centroFormacionRucEditado}
                            onChange={(e) => setCentroFormacionRucEditado(e.target.value)}
                          />
                        </label>
                      </div>
                      <div className="grid grid-cols-2 gap-3">
                        <label className="text-sm">
                          Centro de formación — domicilio
                          <input
                            className="mt-1 w-full rounded border border-sand p-2"
                            value={centroFormacionDomicilioEditado}
                            onChange={(e) => setCentroFormacionDomicilioEditado(e.target.value)}
                          />
                        </label>
                        <label className="text-sm">
                          Centro de formación — representante
                          <input
                            className="mt-1 w-full rounded border border-sand p-2"
                            value={centroFormacionRepresentanteEditado}
                            onChange={(e) => setCentroFormacionRepresentanteEditado(e.target.value)}
                          />
                        </label>
                      </div>
                      <div className="grid grid-cols-2 gap-3">
                        <label className="text-sm">
                          Carrera / especialidad
                          <input
                            className="mt-1 w-full rounded border border-sand p-2"
                            value={carreraEspecialidadEditada}
                            onChange={(e) => setCarreraEspecialidadEditada(e.target.value)}
                          />
                        </label>
                        <label className="text-sm">
                          Ciclo académico
                          <input
                            className="mt-1 w-full rounded border border-sand p-2"
                            value={cicloAcademicoEditado}
                            onChange={(e) => setCicloAcademicoEditado(e.target.value)}
                          />
                        </label>
                      </div>
                    </>
                  ) : (
                    <label className="block text-sm">
                      Grado / título (referencial — no aplica al centro de formación, que no firma en el profesional)
                      <AreaTexto
                        className="mt-1 w-full rounded border border-sand p-2"
                        rows={2}
                        placeholder="Ej.: Bachiller en Ingeniería de Sistemas — UNT, egresado el 15/12/2025"
                        value={gradoTituloTextoEditado}
                        onChange={(e) => setGradoTituloTextoEditado(e.target.value)}
                      />
                    </label>
                  )}
                  <label className="block text-sm">
                    Anexo I — área / proyecto de destino
                    <AreaTexto
                      className="mt-1 w-full rounded border border-sand p-2"
                      rows={2}
                      placeholder="Ej.: Proyecto ERP CAYLA — módulo de inventario"
                      value={areaProyectoEditado}
                      onChange={(e) => setAreaProyectoEditado(e.target.value)}
                    />
                  </label>
                  <label className="block text-sm">
                    Anexo I — objetivo formativo general
                    {/* Un Enter acá llega al papel como salto de línea, no
                        colapsado a un espacio dentro del párrafo del Anexo I
                        (ver parrafoDesdeTexto en contrato-texto). */}
                    <AreaTexto
                      className="mt-1 w-full rounded border border-sand p-2"
                      rows={2}
                      placeholder="Qué debe saber hacer al finalizar"
                      value={objetivoFormativoGeneralEditado}
                      onChange={(e) => setObjetivoFormativoGeneralEditado(e.target.value)}
                    />
                  </label>
                  <label className="block text-sm">
                    Anexo I — actividades principales (una por línea; se numeran solas)
                    <AreaTexto
                      className="mt-1 w-full rounded border border-sand p-2"
                      rows={3}
                      placeholder="Ej.: Apoyo en el desarrollo de módulos del sistema interno de asistencia, bajo supervisión del área de Desarrollo."
                      value={planCapacitacionEditado}
                      onChange={(e) => setPlanCapacitacionEditado(e.target.value)}
                    />
                  </label>
                  <label className="block text-sm">
                    Anexo I — supervisor(a) asignado(a)
                    <input
                      className="mt-1 w-full rounded border border-sand p-2 sm:w-1/2"
                      value={supervisorAsignadoEditado}
                      onChange={(e) => setSupervisorAsignadoEditado(e.target.value)}
                    />
                  </label>
                  <div className="grid gap-3 sm:grid-cols-2">
                    <label className="text-sm">
                      Anexo I — hito de evaluación, mes 3
                      <AreaTexto
                        className="mt-1 w-full rounded border border-sand p-2"
                        rows={2}
                        value={hitoMes3Editado}
                        onChange={(e) => setHitoMes3Editado(e.target.value)}
                      />
                    </label>
                    <label className="text-sm">
                      Anexo I — hito de evaluación, mes 6
                      <AreaTexto
                        className="mt-1 w-full rounded border border-sand p-2"
                        rows={2}
                        value={hitoMes6Editado}
                        onChange={(e) => setHitoMes6Editado(e.target.value)}
                      />
                    </label>
                  </div>
                  <label className="block text-sm">
                    Anexo IV — ajuste de activos para esta persona (uno por línea)
                    <AreaTexto
                      className="mt-1 w-full rounded border border-sand p-2 disabled:opacity-50"
                      rows={2}
                      value={activosLibre}
                      disabled={sinActivosAdicionales}
                      onChange={(e) => setActivosLibre(e.target.value)}
                    />
                  </label>
                  <label className="flex items-center gap-2 text-sm">
                    <input
                      type="checkbox"
                      checked={sinActivosAdicionales}
                      onChange={(e) => {
                        setSinActivosAdicionales(e.target.checked);
                        if (e.target.checked) setActivosLibre("");
                      }}
                    />
                    Confirmo que {persona.nombres} no tiene activos adicionales a su cargo, más allá de los generales
                    de la sede
                  </label>
                </>
              ) : (
                <>
                  {/* Un indefinido no tiene causa objetiva — no es modalidad
                      temporal, no la necesita (0347). */}
                  {!esIndefinido && (
                    <label className="block text-sm">
                      Causa objetiva (revisar antes de imprimir)
                      <AreaTexto
                        className="mt-1 w-full rounded border border-sand p-2"
                        rows={4}
                        value={causaEditada}
                        onChange={(e) => setCausaEditada(e.target.value)}
                      />
                    </label>
                  )}
                  <label className="block text-sm">
                    Funciones del cargo (Anexo I) — una por línea; se numeran solas
                    <AreaTexto
                      className="mt-1 w-full rounded border border-sand p-2"
                      rows={3}
                      value={funcionesEditadas}
                      onChange={(e) => setFuncionesEditadas(e.target.value)}
                    />
                  </label>
                  <label className="block text-sm">
                    Anexo IV — ajuste de activos para esta persona (uno por línea)
                    <AreaTexto
                      className="mt-1 w-full rounded border border-sand p-2 disabled:opacity-50"
                      rows={2}
                      value={activosLibre}
                      disabled={sinActivosAdicionales}
                      onChange={(e) => setActivosLibre(e.target.value)}
                    />
                  </label>
                  <label className="flex items-center gap-2 text-sm">
                    <input
                      type="checkbox"
                      checked={sinActivosAdicionales}
                      onChange={(e) => {
                        setSinActivosAdicionales(e.target.checked);
                        if (e.target.checked) setActivosLibre("");
                      }}
                    />
                    Confirmo que {persona.nombres} no tiene activos adicionales a su cargo, más allá de los generales
                    de la sede
                  </label>
                </>
              )}

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
                  <dt className="font-semibold">Sueldo base vigente</dt>
                  <dd>{salarioVigente !== null ? `S/ ${salarioVigente.toFixed(2)}` : "sin asignación vigente"}</dd>
                </div>
                <div>
                  <dt className="font-semibold">Jornada del {esConvenio ? "convenio" : "contrato"}</dt>
                  <dd>
                    {esConvenio
                      ? (() => {
                          const max = maximoSemanalPracticante("practicante", modalidadEfectiva);
                          return max !== null ? `hasta ${max} horas semanales (art. 44)` : "falta elegir la modalidad";
                        })()
                      : "48 horas semanales (el máximo legal — ver cláusula QUINTA)"}
                  </dd>
                </div>
                <div>
                  <dt className="font-semibold">Movilidad</dt>
                  <dd>
                    {esConvenio
                      ? "no aplica — no está en planilla (0322)"
                      : persona.cobra_movilidad
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
                <div>
                  <dt className="font-semibold">Firma de la empresa</dt>
                  <dd className={puedeEstampar ? "" : "text-rojo"}>
                    {!firmante.nombre
                      ? "sin firmante configurado — cárgalo en Documentación"
                      : puedeEstampar
                        ? `se estampa la de ${firmante.nombre}`
                        : esFirmante
                          ? "no tienes firma escaneada cargada — saldrá la raya en blanco"
                          : `la firma es de ${firmante.nombre}; solo esa persona puede estamparla, saldrá la raya en blanco`}
                  </dd>
                </div>
              </dl>

              {bloqueos.length > 0 && (
                <ul className="list-disc space-y-1 rounded-lg bg-rojo/10 px-4 py-3 pl-8 text-sm text-rojo">
                  {bloqueos.map((b) => (
                    <li key={b}>{b}</li>
                  ))}
                </ul>
              )}

              {/* Avisos: no impiden generar, pero tienen que verse ANTES de
                  firmar. En arena y no en rojo — el rojo es el acento sagrado y
                  ya lo gastan los bloqueos de arriba. */}
              {avisos.length > 0 && (
                <ul className="list-disc space-y-1 rounded-lg border border-taupe/40 bg-sand/40 px-4 py-3 pl-8 text-sm text-taupe">
                  {avisos.map((a) => (
                    <li key={a}>{a}</li>
                  ))}
                </ul>
              )}

              <button
                className="rounded bg-tinta px-4 py-2 text-sm text-crema disabled:opacity-50"
                disabled={!datosParaGenerar || bloqueos.length > 0 || generando}
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
        <section className="space-y-3">
          <h2 className="font-serif text-lg">Archivo</h2>

          {contratos.length === 0 && (
            <p className="text-sm text-taupe">Todavía no se generó ningún contrato.</p>
          )}

          {/* AGRUPADO POR PERSONA, Y LOS ANULADOS PLEGADOS.
              La tabla plana repetía el nombre completo en cada fila —cuatro
              veces para la misma persona— y daba a tres pruebas anuladas el
              mismo peso visual que al contrato de verdad. Lo que importa de
              cada persona es UNO: el vigente. Lo demás es historia, y la
              historia se guarda, no se exhibe. */}
          {porPersona.map(([nombre, filas]) => {
            const vivos = filas.filter((c) => !c.anulado_at);
            const anulados = filas.filter((c) => c.anulado_at);
            return (
              <article key={nombre} className="rounded-lg border border-sand bg-papel p-4">
                <h3 className="mb-2 font-medium">{nombre}</h3>

                {vivos.map((c) => (
                  <div key={c.id} className="space-y-1 border-t border-sand/60 pt-2 first:border-0 first:pt-0">
                    <div className="flex flex-wrap items-baseline gap-x-3 text-sm">
                      <span>
                        {formatearFecha(c.fecha_inicio)} –{" "}
                        {c.fecha_fin ? formatearFecha(c.fecha_fin) : "indeterminado"}
                      </span>
                      <span className="text-xs text-taupe">{TIPO_CONTRATO[c.tipo] ?? c.tipo}</span>
                      <span className={c.storage_path ? "text-xs text-verde" : "text-xs text-taupe"}>
                        {c.storage_path ? `firmado el ${formatearFecha(c.fecha_firma!)}` : "pendiente de firma"}
                      </span>
                    </div>

                    {/* Los dos plazos, solo mientras falten: confirmar en cada
                        fila lo que ya se hizo llena la pantalla de recibos.
                        Un indefinido no se registra ante la Autoridad de
                        Trabajo (0347) — ese trámite no le corresponde. */}
                    {c.fecha_firma &&
                      (!c.copia_entregada_at || (c.tipo !== "indefinido" && !c.comunicado_mtpe_at)) && (
                        <p className="text-xs text-taupe">
                          Falta{" "}
                          {!c.copia_entregada_at &&
                            `entregar copia a ${c.tipo === "convenio_practicas" ? "la practicante" : "la colaboradora"}`}
                          {!c.copia_entregada_at && c.tipo !== "indefinido" && !c.comunicado_mtpe_at && " y "}
                          {c.tipo !== "indefinido" && !c.comunicado_mtpe_at && "comunicar a la Autoridad de Trabajo"}
                        </p>
                      )}

                    <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs">
                      <button className="underline underline-offset-2 hover:text-taupe" onClick={() => abrirGenerado(c.id)}>
                        Ver / imprimir
                      </button>
                      {!c.storage_path && (
                        <button className="underline underline-offset-2 hover:text-taupe" onClick={() => abrirSubida(c.id)}>
                          Subir contrato firmado
                        </button>
                      )}
                      {c.storage_path && (
                        <button className="underline underline-offset-2 hover:text-taupe" onClick={() => verDocumento(c.storage_path!)}>
                          Ver escaneo
                        </button>
                      )}
                      {c.fecha_firma && !c.copia_entregada_at && (
                        <button className="underline underline-offset-2 hover:text-taupe" onClick={() => marcarTramite(c.id, "copia")}>
                          Marcar copia entregada
                        </button>
                      )}
                      {c.fecha_firma && c.tipo !== "indefinido" && !c.comunicado_mtpe_at && (
                        <button className="underline underline-offset-2 hover:text-taupe" onClick={() => marcarTramite(c.id, "mtpe")}>
                          Marcar comunicado al MTPE
                        </button>
                      )}
                      {/* Anular va al final y en taupe: es destructivo, no
                          urgente. En rojo junto a acciones inofensivas se
                          pulsa por error, y el rojo de esta paleta está
                          reservado para lo que de verdad avisa. */}
                      <button className="ml-auto text-taupe underline underline-offset-2 hover:text-rojo" onClick={() => setAnulando(c.id)}>
                        Anular
                      </button>
                    </div>
                    <p className="text-xs text-taupe">
                      Generado el {formatearFecha(c.generado_at.slice(0, 10))}
                      {c.generado_por && ` por ${c.generado_por}`}
                    </p>
                  </div>
                ))}

                {anulados.length > 0 && (
                  <details className="mt-2 border-t border-sand/60 pt-2 text-xs text-taupe">
                    <summary className="cursor-pointer">
                      {anulados.length === 1 ? "1 anulado" : `${anulados.length} anulados`}
                    </summary>
                    <ul className="mt-1 space-y-1">
                      {anulados.map((c) => (
                        <li key={c.id} className="flex flex-wrap items-baseline gap-x-3">
                          <span>{formatearFecha(c.generado_at.slice(0, 10))}</span>
                          <span className="min-w-0 flex-1 truncate">{c.anulado_motivo}</span>
                          <button className="underline underline-offset-2 hover:text-tinta" onClick={() => abrirGenerado(c.id)}>
                            Ver
                          </button>
                        </li>
                      ))}
                    </ul>
                  </details>
                )}
              </article>
            );
          })}
        </section>

        {subiendoPara && (
          <section className="space-y-2 rounded-lg border border-sand p-4">
            <p className="font-serif text-lg">Subir contrato firmado</p>
            <p className="text-sm text-taupe">
              El PDF o la foto del contrato ya firmado por las dos partes. Hasta 50 MB.
            </p>
            <div className="grid gap-3 sm:grid-cols-2">
              <label className="flex flex-col gap-1 text-sm">
                Archivo escaneado
                {/* El estilo `file:` es el de la casa —lo usan Documentación,
                    Educación, Normas, Feriados y Disciplina—. Sin él, el input
                    sale con el control crudo del navegador: no parece pulsable
                    y no se parece a nada más del panel. */}
                <input
                  type="file"
                  accept="image/*,application/pdf"
                  onChange={(e) => setArchivo(e.target.files?.[0] ?? null)}
                  className="rounded-lg border border-sand bg-crema px-3 py-2 text-sm file:mr-3 file:cursor-pointer file:rounded file:border-0 file:bg-sand file:px-3 file:py-1 file:text-sm hover:file:bg-taupe hover:file:text-crema"
                />
              </label>
              <label className="flex flex-col gap-1 text-sm">
                Fecha de firma
                <input
                  type="date"
                  className="rounded-lg border border-sand px-3 py-2 text-sm"
                  value={fechaFirma}
                  max={hoyLima()}
                  onChange={(e) => setFechaFirma(e.target.value)}
                />
              </label>
            </div>
            {progreso !== null && <p className="text-xs">{progreso}%</p>}
            <div className="space-x-2">
              <button
                className="rounded bg-tinta px-3 py-1.5 text-sm text-crema disabled:opacity-50"
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
            <p className="font-serif text-lg">Anular contrato</p>
            <AreaTexto
              className="w-full rounded border border-sand p-2 text-sm"
              placeholder="Motivo (mínimo 3 caracteres)"
              value={motivoAnular}
              onChange={(e) => setMotivoAnular(e.target.value)}
            />
            <div className="space-x-2">
              <button className="rounded bg-rojo px-3 py-1.5 text-sm text-crema" onClick={anular}>
                Confirmar anulación
              </button>
              <button className="text-sm" onClick={() => setAnulando(null)}>
                Cancelar
              </button>
            </div>
          </section>
        )}
      </div>

      {/* Un contrato del historial se ve en una ventana modal, no agregado al
          final de la página: con varios contratos por persona, cada "Ver /
          imprimir" hacía la página más larga en vez de solo mostrar uno. */}
      {documentoAbierto && htmlFinalAbierto && (
        <>
          <div
            className="fixed inset-0 z-40 bg-black/40 print:hidden"
            onClick={() => setDocumentoAbierto(null)}
            aria-hidden
          />
          <div
            role="dialog"
            aria-label="Ver contrato"
            className="fixed inset-3 z-50 overflow-y-auto rounded-lg border border-sand bg-crema shadow-xl sm:inset-6 md:inset-x-auto md:inset-y-6 md:left-1/2 md:w-full md:max-w-3xl md:-translate-x-1/2 print:static print:inset-auto print:z-auto print:w-auto print:max-w-none print:translate-x-0 print:overflow-visible print:rounded-none print:border-0 print:bg-transparent print:shadow-none"
          >
            <div className="sticky top-0 z-10 flex items-center gap-3 border-b border-sand bg-crema px-4 py-3 print:hidden">
              <button className="rounded bg-tinta px-4 py-2 text-sm text-crema" onClick={imprimir}>
                Imprimir / Guardar como PDF
              </button>
              <button className="text-sm underline" onClick={() => setDocumentoAbierto(null)}>
                Cerrar
              </button>
            </div>
            <div
              className="hoja mx-auto max-w-3xl p-8 text-sm leading-relaxed print:mt-0 print:max-w-none print:rounded-none print:border-0 print:p-0"
              dangerouslySetInnerHTML={{ __html: htmlFinalAbierto }}
            />
          </div>
        </>
      )}

      {htmlFinal && (
        <div
          className="hoja mx-auto mt-6 max-w-3xl rounded-lg border border-sand p-8 text-sm leading-relaxed print:mt-0 print:max-w-none print:rounded-none print:border-0 print:p-0"
          dangerouslySetInnerHTML={{ __html: htmlFinal }}
        />
      )}
    </main>
  );
}

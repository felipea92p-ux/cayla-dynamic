"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import bcrypt from "bcryptjs";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { AdminNav } from "../nav";
import { EsqueletoTabla } from "@/components/cargando";
import { useToast } from "@/components/toast";
import { useRolActual } from "@/lib/admin/use-rol";
import { useFiltroGuardado } from "@/lib/admin/use-filtro-guardado";
import { RANGOS, RANGO_LABEL, baseDeclaradaDe, formatSoles } from "@/lib/rangos";
import { type Area, AREA_DEFAULT, AREAS_FALLBACK, parseAreas, areaCorto, esOperativaEn } from "@/lib/areas";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import {
  hoyLima, primeroDeMesLima, rangoDelMesLima, puedeVerPlanilla,
  MOTIVOS_CESE, MOTIVO_CESE_LABELS, etiquetaDeCatalogo, type MotivoCese, type Rol,
} from "@cayla-dynamic/shared";

const ROLES_OPCIONES = [
  { valor: "integrante", label: "Integrante" },
  { valor: "supervisor_sede", label: "Líder de equipo (encargada)" },
  { valor: "lider_do", label: "Líder de Desarrollo Organizacional" },
  { valor: "admin", label: "Admin" },
] as const;

// "2026-07-13" → "13/07/2026" (date str puro; aritmética de string, sin sorpresas de zona).
function fmtFechaDMA(iso: string): string {
  const [y, m, d] = iso.split("-");
  return `${d}/${m}/${y}`;
}

// `primeroDeMesLima` (default de "vigente desde" al asignar salario) vivía acá
// copiado; es el mismo que exporta fecha-lima.ts, así que ahora se importa. Dos
// copias del corte del día son dos versiones de cuándo es hoy en Lima.

interface SalarioVigente {
  rango: string;
  salario: number;
}
interface TramoSalario {
  rango: string;
  salario_mensual_soles: number;
  vigente_desde: string;
  vigente_hasta: string | null;
  asignado_por: string | null;
  nota: string | null;
}

const PIN_TRIVIALES = new Set([
  "0000", "1111", "2222", "3333", "4444", "5555", "6666", "7777", "8888", "9999", "1234", "4321", "0123",
]);

function generarPin(): string {
  let pin: string;
  do {
    const n = new Uint32Array(1);
    crypto.getRandomValues(n);
    pin = String(n[0] % 10000).padStart(4, "0");
  } while (PIN_TRIVIALES.has(pin));
  return pin;
}

interface Sede {
  id: string;
  codigo: string;
  nombre: string;
}

// Qué se muestra en la tabla. "fin_contrato" no es un estado de la persona sino
// una pregunta de trabajo —«¿a quién tengo que renovar o no renovar?»— y vive en
// el mismo desplegable porque es donde se la va a buscar.
type FiltroEstado = "activos" | "inactivos" | "fin_contrato" | "todos";

interface Persona {
  id: string;
  nombres: string;
  apellidos: string;
  rol: string;
  estado: string;
  email: string | null;
  sede_base_id: string;
  funcion: string;
  con_hijos: boolean;
  visible_todas_sedes: boolean;
  // Qué es esta persona para el sistema (0085). Decide si acumula gratificación,
  // CTS y vacaciones, si recibe movilidad y si genera EsSalud (0117 y 0119).
  tipo_vinculo: string;
  // Solo tiene sentido con tipo_vinculo='practicante' (0324): preprofesional
  // (30h/semana) o profesional (48h/semana), art. 44 Ley 28518.
  practicante_modalidad: string | null;
  // Qué ES esta persona para CAYLA: «Socia», «Asesor» (0182). Es lo que se
  // MUESTRA, y no decide ningún permiso — eso sigue siendo `rol`. Vacío = la
  // pantalla cae a la etiqueta del rol, como antes de la 0182.
  cargo: string | null;
  // Cuándo y por qué dejó de trabajar aquí (0086, expuestos por la 0179).
  // `motivo_cese` llega null a quien no sea admin ni líder DO: la función solo
  // se lo entrega a administración, y aquí no se compensa esa ausencia.
  fecha_cese: string | null;
  motivo_cese: string | null;
}


interface FormPersona {
  nombres: string;
  apellidos: string;
  sedeId: string;
  rol: Rol;
  funcion: string; // código de área (ver lib/areas)
  email: string;
  conHijos: boolean; // asignación familiar (S/ 113 fijos por periodo) — se escribe por RPC fn_set_con_hijos
  tipoVinculo: string; // planilla | prueba | rxh | no_trabajador | practicante — se escribe por RPC fn_set_tipo_vinculo
  practicanteModalidad: string; // "" | preprofesional | profesional — solo si tipoVinculo=practicante; se escribe por RPC fn_set_practicante_modalidad
  cargo: string;      // 0182 — cómo se la nombra en pantalla. Vacío = se muestra el rol
  fechaIngreso: string; // decide qué feriados le corresponden — solo edición; se escribe por RPC fn_set_fecha_ingreso
  visibleTodasSedes: boolean; // aparece en el terminal de cualquier sede — se escribe por RPC fn_set_visible_todas_sedes
  // Último día que trabaja por contrato (0144). Es un PLAN, no un cese: vacío es
  // lo normal. Se escribe por RPC fn_set_fin_contrato, y vacío la BORRA (null).
  finContrato: string;
  motivoFinContrato: string; // por qué se fijó o se quitó — va a correcciones_auditoria
  // Retención de renta de 4ta categoría (0245). Solo tiene sentido para `rxh`:
  // la cuarta categoría es del trabajador independiente. Vacío = no se retiene.
  // Se escribe por RPC fn_set_retencion_4ta, que valida el vínculo y audita.
  // No aplica a `practicante` (0322): su subvención no genera renta de 4ta.
  retencion4ta: string;   // "" | automatica | siempre
  constancia4ta: string;  // fecha hasta la que vale su constancia del F.V. 1609
}

const FORM_VACIO: FormPersona = { nombres: "", apellidos: "", sedeId: "", rol: "integrante", funcion: AREA_DEFAULT, email: "", conHijos: false, fechaIngreso: "", visibleTodasSedes: false, tipoVinculo: "planilla", practicanteModalidad: "", cargo: "", finContrato: "", motivoFinContrato: "", retencion4ta: "", constancia4ta: "" };

export default function EquipoPage() {
  const router = useRouter();
  const [sedes, setSedes] = useState<Sede[]>([]);
  const [personas, setPersonas] = useState<Persona[]>([]);
  // Catálogo de áreas (tabla `areas` vía RPC fn_areas; NUNCA por REST — schema cache trabado).
  const [areas, setAreas] = useState<Area[]>(AREAS_FALLBACK);
  // Fecha de ingreso + primera entrada marcada por persona (RPC fn_ingresos; solo admin/lider,
  // devuelve [] para el resto). Decide qué feriados le corresponden a cada persona.
  const [ingresos, setIngresos] = useState<Map<string, { fecha_ingreso: string | null; primera_entrada: string | null }>>(new Map());
  // Último día que trabaja por contrato, por persona (0144). Solo llegan quienes
  // la tienen: vacío es lo normal y no significa que falte un dato.
  const [finesContrato, setFinesContrato] = useState<Map<string, string>>(new Map());
  // ¿Esa lectura fue confiable? Mismo criterio que `funcionesOk` de más abajo: si
  // falló, el editor muestra vacío para todo el mundo, y vacío significa
  // «contrato indefinido». Escribir sobre eso borraría una fecha real, así que
  // con la lectura en duda el campo va deshabilitado.
  const [finesOk, setFinesOk] = useState(false);
  // Retención de 4ta por persona (0245). Se lee aparte y tolerante, por lo mismo
  // que el fin de contrato: si la 0245 todavía no está pegada en producción,
  // pedir columnas inexistentes haría fallar la consulta ENTERA y esta pantalla
  // se quedaría sin nadie. Con la lectura en duda el campo va deshabilitado, para
  // no pisar con «sin retención» una configuración real que no se pudo leer.
  const [retenciones4ta, setRetenciones4ta] = useState<Map<string, { modo: string; hasta: string }>>(new Map());
  const [retencionesOk, setRetencionesOk] = useState(false);
  const [cargando, setCargando] = useState(true);
  const { avisar } = useToast();

  // Filtros. Con ~30 personas y sin ninguno, encontrar a alguien era leer la
  // tabla entera. El de estado arranca en "activos": esconder a quien ya no está
  // en ESTA pantalla no tiene riesgo (en Planilla sí lo tendría, y allí se avisa).
  //
  // Sede, área y estado se acuerdan de la última vez (useFiltroGuardado);
  // `busca` no — es texto de esta visita, no una forma de mirar la pantalla.
  const [busca, setBusca] = useState("");
  const [fSede, setFSede] = useFiltroGuardado("equipo.sede", "todas");
  const [fArea, setFArea] = useFiltroGuardado("equipo.area", "todas");
  const [fEstado, setFEstado] = useFiltroGuardado<FiltroEstado>("equipo.estado", "activos");

  const [mostrandoAlta, setMostrandoAlta] = useState(false);
  const [form, setForm] = useState<FormPersona>(FORM_VACIO);
  const [editandoId, setEditandoId] = useState<string | null>(null);
  const [guardando, setGuardando] = useState(false);
  // Registrar la salida de alguien. Es un panel y no un window.confirm porque un
  // cese son dos datos —el último día y el porqué—, no un sí/no.
  // Los cinco paneles de esta pantalla —alta, edición, salario, historial y
  // salida— se abren ARRIBA, encima de la tabla. Con ~30 filas, quien pulsa un
  // botón desde media lista no ve que abrió nada: la pantalla no cambia donde
  // está mirando, así que vuelve a pulsar creyendo que el botón no responde.
  //
  // No es una peculiaridad que haya que aprender: es un error de diseño, y el
  // que lo comete es quien hizo la pantalla, no quien la usa. Se desplaza sola
  // hasta el panel. `scroll-mt-4` deja un respiro arriba para que no quede
  // pegado al borde.
  const panelRef = useRef<HTMLDivElement | null>(null);
  const [ceseId, setCeseId] = useState<string | null>(null);
  const [ceseForm, setCeseForm] = useState<{ fecha: string; motivo: MotivoCese | "" }>({ fecha: "", motivo: "" });
  const [guardandoCese, setGuardandoCese] = useState(false);

  // Salarios (dato sensible: solo admin/lider_do). Se leen/escriben por RPC.
  // OJO: mientras no estén CARGADOS ("ok") no se permite asignar/editar — si se
  // permitiera, el editor abriría sin saber el salario real y podría pisarlo.
  // El pre-llenado con el monto del rango ya se quitó (ver el diálogo de salario):
  // era la misma trampa que este comentario advertía, viva en otro lugar.
  const rol = useRolActual();
  const puedeSalarios = puedeVerPlanilla(rol);
  const [salariosEstado, setSalariosEstado] = useState<"cargando" | "ok" | "error">("cargando");
  const [salarios, setSalarios] = useState<Record<string, SalarioVigente>>({});
  const [salEditId, setSalEditId] = useState<string | null>(null);
  // El salario arranca VACÍO a propósito: un número por defecto es un número que
  // alguien guarda sin leer. Si la persona ya tiene salario, se carga el suyo.
  const [salForm, setSalForm] = useState({ rango: "colibri", salario: "", vigenteDesde: primeroDeMesLima(), nota: "" });
  // Lo que la persona tenía al abrir el diálogo, para poder mostrar «tenía X → queda Y».
  const [salAnterior, setSalAnterior] = useState<number | null>(null);
  // Primer día del periodo ABIERTO. Es la vigencia correcta: nunca cae dentro de
  // un mes ya pagado, así que no puede alterar una boleta entregada. Se lee de la
  // base y no se calcula, porque los periodos de CAYLA van del 29 al 28 y el
  // primero del mes cae en la mitad de uno.
  const [inicioPeriodo, setInicioPeriodo] = useState<string | null>(null);

  // ¿El monto escrito difiere de la base que declara su rango? Solo para avisar:
  // pisarlo es legítimo cuando se acordó otra cosa (el caso de Felipe), y el aviso
  // es lo que después distingue una excepción pactada de un dato mal puesto.
  const baseDelRango = baseDeclaradaDe(salForm.rango);
  const fueraDeLaBase =
    baseDelRango != null &&
    salForm.salario.trim() !== "" &&
    Number(salForm.salario) !== baseDelRango;
  const [guardandoSal, setGuardandoSal] = useState(false);
  const [histId, setHistId] = useState<string | null>(null);
  const [hist, setHist] = useState<TramoSalario[]>([]);

  // El área ("funcion" en la base) viaja por RPC; si esa carga falló, lo mostrado es
  // el área default y NO debe re-escribirse al guardar una edición (pisaría el área real).
  const [funcionesOk, setFuncionesOk] = useState(false);

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) {
      router.replace("/admin/login");
      return;
    }
    const [{ data: sedesData, error: sedesError }, { data: personasData, error: personasError }, { data: funcionesData, error: funcionesError }, { data: areasData, error: areasError }, { data: ingresosData, error: ingresosError }] = await Promise.all([
      supabase.from("sedes").select("id, codigo, nombre").order("nombre"),
      supabase.from("personas").select("id, nombres, apellidos, rol, estado, email, sede_base_id").order("nombres"),
      supabase.rpc("fn_personas_funciones"),
      supabase.rpc("fn_areas"),
      supabase.rpc("fn_ingresos"),
    ]);
    setAreas(parseAreas(areasData, areasError));
    // Fecha de ingreso (por RPC; solo admin/lider — para el resto llega [] y el Map queda vacío,
    // que es justo lo que la UI espera: nada de fechas de ingreso visibles ni editables).
    setIngresos(
      new Map(
        (ingresosError ? [] : ((ingresosData as { persona_id: string; fecha_ingreso: string | null; primera_entrada: string | null }[] | null) ?? []))
          .map((r) => [r.persona_id, { fecha_ingreso: r.fecha_ingreso, primera_entrada: r.primera_entrada }] as const),
      ),
    );
    if (personasError || sedesError) {
      avisar("error", mensajeDeError((personasError ?? sedesError)!, "cargar el equipo"));
    }
    // Fin de contrato: consulta APARTE y tolerante, no una columna más del select
    // de arriba. Si la 0144 todavía no está aplicada en producción, pedir una
    // columna inexistente haría fallar la consulta ENTERA y esta pantalla se
    // quedaría sin nadie — la de Documentación se defiende igual y por lo mismo.
    // Si falla, simplemente no hay fechas de fin y todo lo demás sigue.
    // Sin filtro de estado a propósito: a quien ya cesó también se le muestra la
    // fecha que tenía, aunque no se pueda editar.
    const { data: finData, error: finError } = await supabase
      .from("personas")
      .select("id, fecha_fin_contrato")
      .not("fecha_fin_contrato", "is", null);
    setFinesOk(!finError);
    setFinesContrato(
      new Map(
        ((finData as { id: string; fecha_fin_contrato: string }[] | null) ?? [])
          .map((f) => [f.id, f.fecha_fin_contrato] as const),
      ),
    );
    // Retención de 4ta (0245): consulta aparte y tolerante, igual que la de
    // arriba y por la misma razón. Sin filtro: llegan también quienes la tienen
    // en blanco, porque «en blanco» es una respuesta —no se le retiene— y no un
    // dato que falte.
    const { data: retData, error: retError } = await supabase
      .from("personas")
      .select("id, retencion_4ta, constancia_4ta_hasta");
    setRetencionesOk(!retError);
    setRetenciones4ta(
      new Map(
        ((retData as { id: string; retencion_4ta: string | null; constancia_4ta_hasta: string | null }[] | null) ?? [])
          .map((r) => [r.id, { modo: r.retencion_4ta ?? "", hasta: r.constancia_4ta_hasta ?? "" }] as const),
      ),
    );
    // "funcion" y "con_hijos" viajan por RPC (el schema cache de PostgREST no expone las columnas).
    // Si la RPC falla, degradamos al área default / sin asignación para todos sin bloquear la página.
    const funciones = new Map(
      (funcionesError ? [] : ((funcionesData as { persona_id: string; funcion: string; con_hijos: boolean; visible_todas_sedes?: boolean; tipo_vinculo?: string; practicante_modalidad?: string | null; cargo?: string | null; fecha_cese?: string | null; motivo_cese?: string | null }[] | null) ?? []))
        .map((f) => [f.persona_id, { funcion: f.funcion, con_hijos: f.con_hijos ?? false, visible_todas_sedes: f.visible_todas_sedes ?? false, tipo_vinculo: f.tipo_vinculo ?? "planilla", practicante_modalidad: f.practicante_modalidad ?? null, cargo: f.cargo ?? null, fecha_cese: f.fecha_cese ?? null, motivo_cese: f.motivo_cese ?? null }] as const),
    );
    setFuncionesOk(!funcionesError);
    setSedes(sedesData ?? []);
    setPersonas(
      ((personasData as Omit<Persona, "funcion" | "con_hijos" | "visible_todas_sedes" | "tipo_vinculo" | "practicante_modalidad" | "fecha_cese" | "motivo_cese">[]) ?? []).map((p) => {
        const extra = funciones.get(p.id);
        return { ...p, funcion: extra?.funcion ?? AREA_DEFAULT, con_hijos: extra?.con_hijos ?? false, visible_todas_sedes: extra?.visible_todas_sedes ?? false, tipo_vinculo: extra?.tipo_vinculo ?? "planilla", practicante_modalidad: extra?.practicante_modalidad ?? null, cargo: extra?.cargo ?? null, fecha_cese: extra?.fecha_cese ?? null, motivo_cese: extra?.motivo_cese ?? null };
      }),
    );
    setCargando(false);
  }, [router, avisar]);

  useEffect(() => {
    void cargar();
  }, [cargar]);

  // Cuál está abierto, no si hay alguno: así también se desplaza al pasar de un
  // panel a otro (de «Editar» de una persona a «Registrar salida» de otra).
  const panelAbierto = mostrandoAlta ? "alta" : editandoId ?? salEditId ?? histId ?? ceseId ?? null;
  useEffect(() => {
    if (panelAbierto) panelRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
  }, [panelAbierto]);

  const cargarSalarios = useCallback(async () => {
    setSalariosEstado("cargando");
    const supabase = createAdminSupabaseClient();
    const { data, error } = await supabase.rpc("fn_salarios_vigentes");
    if (error) {
      setSalariosEstado("error");
      return;
    }
    const map: Record<string, SalarioVigente> = {};
    for (const row of data ?? []) {
      map[row.persona_id] = { rango: row.rango, salario: Number(row.salario_mensual_soles) };
    }
    setSalarios(map);
    setSalariosEstado("ok");
  }, []);

  useEffect(() => {
    if (puedeSalarios) void cargarSalarios();
  }, [puedeSalarios, cargarSalarios]);

  // Se compara sin tildes ni mayúsculas: buscar "nunez" tiene que encontrar a
  // "Núñez". Escribir el apellido con la tilde exacta no puede ser un requisito.
  const sinTildes = (t: string) =>
    t.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();

  // El último día del mes en curso en Lima. Es EL MISMO corte que usa el tablero
  // de Documentación (0162): quien termina contrato ese día o antes deja de
  // aparecer ahí. Se calcula acá una sola vez para que la tabla y el aviso del
  // formulario no puedan discrepar sobre dónde cae la raya.
  const finDeMes = rangoDelMesLima().fin;
  const saleDelTablero = (fecha: string | undefined) => fecha != null && fecha <= finDeMes;

  const visibles = personas.filter((p) => {
    if (fEstado === "activos" && p.estado !== "activo") return false;
    if (fEstado === "inactivos" && p.estado === "activo") return false;
    // Quien tiene fecha de término anotada y sigue trabajando. A quien ya cesó no
    // se le pregunta si se renueva: su contrato ya terminó de hecho.
    if (fEstado === "fin_contrato" && (p.estado !== "activo" || !finesContrato.has(p.id))) return false;
    if (fSede !== "todas" && p.sede_base_id !== fSede) return false;
    if (fArea !== "todas" && p.funcion !== fArea) return false;
    const q = sinTildes(busca.trim());
    if (q && !sinTildes(`${p.nombres} ${p.apellidos}`).includes(q)) return false;
    return true;
  });
  // Con ese filtro el orden alfabético no responde nada: lo que importa es a quién
  // se le vence primero.
  if (fEstado === "fin_contrato") {
    visibles.sort((a, b) => (finesContrato.get(a.id) ?? "").localeCompare(finesContrato.get(b.id) ?? ""));
  }
  const ocultas = personas.length - visibles.length;

  function codigoSede(id: string) {
    return sedes.find((s) => s.id === id)?.codigo ?? "?";
  }

  async function crearPersona() {
    if (!form.nombres.trim() || !form.apellidos.trim() || !form.sedeId) {
      avisar("error", "Nombres, apellidos y sede son obligatorios.");
      return;
    }
    setGuardando(true);
    const pin = generarPin();
    const pinHash = await bcrypt.hash(pin, 10);
    const supabase = createAdminSupabaseClient();
    // Alta por RPC: el insert REST falla entero (PGRST204) si el payload trae "funcion".
    const { data: creada, error } = await supabase.rpc("fn_crear_persona", {
      p_nombres: form.nombres.trim(),
      p_apellidos: form.apellidos.trim(),
      p_sede_base_id: form.sedeId,
      p_rol: form.rol,
      p_funcion: form.funcion,
      p_email: form.email.trim() || null,
      p_pin_hash: pinHash,
    });
    if (error) {
      setGuardando(false);
      avisar("error", mensajeDeError(error, "crear"));
      return;
    }
    // El PIN se muestra UNA sola vez: aunque la asignación familiar falle, el aviso
    // con el PIN no se pierde — solo se le agrega la advertencia.
    let texto = `${form.nombres} ${form.apellidos} agregado(a). Su PIN es ${pin} — anótalo ahora, no se vuelve a mostrar.`;
    let tipoAviso: "ok" | "error" = "ok";
    if (form.conHijos) {
      const nuevaId = (creada as { id: string } | null)?.id;
      const { error: errorHijos } = nuevaId
        ? await supabase.rpc("fn_set_con_hijos", { p_persona_id: nuevaId, p_con_hijos: true })
        : { error: { message: "no se recibió el id de la persona" } };
      if (errorHijos) {
        // Aviso en ROJO para que la falla no pase desapercibida, pero SIEMPRE con
        // el PIN dentro del mismo mensaje (es la única vez que se muestra).
        tipoAviso = "error";
        texto += ` OJO: la asignación familiar no se pudo activar (${errorHijos.message}) — márcala editando a la persona.`;
      }
    }
    setGuardando(false);
    setMostrandoAlta(false);
    setForm(FORM_VACIO);
    await cargar();
    avisar(tipoAviso, texto);
  }

  async function guardarEdicion() {
    if (!editandoId) return;
    // ANTES de escribir nada. La base tiene el mismo candado
    // (`personas_fin_contrato_coherente`) y es la que manda, pero si dejáramos que
    // lo rechace ella, el nombre y el correo ya se habrían guardado y el aviso
    // llegaría después, sin poder decir cuál era la fecha de ingreso.
    // Si la fecha de ingreso no llegó (la RPC fn_ingresos devuelve [] cuando algo
    // falla), no se inventa una validación: pasa, y el rechazo de la base sale
    // traducido por mensajeDeError.
    if (form.finContrato && form.fechaIngreso && form.finContrato < form.fechaIngreso) {
      avisar("error", `El contrato no puede terminar antes de su ingreso (${fmtFechaDMA(form.fechaIngreso)}). Revisa la fecha.`);
      return;
    }
    setGuardando(true);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase
      .from("personas")
      .update({
        nombres: form.nombres.trim(),
        apellidos: form.apellidos.trim(),
        sede_base_id: form.sedeId,
        email: form.email.trim() || null,
      })
      .eq("id", editandoId);
    if (error) {
      setGuardando(false);
      avisar("error", mensajeDeError(error, "guardar"));
      return;
    }
    // Rol: mismo patrón dirty-check, pero por una razón que va más allá de no
    // ensuciar la auditoría. Este campo dejó de viajar en el `update` de arriba
    // porque una fila escrita directo desde el navegador no distingue «esto lo
    // pide un admin» de «esto lo pide cualquiera con la columna abierta» — RLS
    // solo filtraba FILAS, y el desplegable de abajo ofrece «Admin» igual que
    // ofrece «Integrante». `fn_set_rol` reimplementa el escalafón adentro de la
    // base (packages/shared/src/escalafon.ts, la misma regla que ya usa
    // /api/admin/cuentas): quien no es admin nunca puede dar un rol igual o
    // superior al suyo, así que esto no es solo prolijidad de auditoría — es la
    // puerta que faltaba.
    const rolOriginal = personas.find((p) => p.id === editandoId)?.rol;
    if (form.rol !== rolOriginal) {
      const { error: errorRol } = await supabase.rpc("fn_set_rol", {
        p_persona_id: editandoId,
        p_nuevo_rol: form.rol,
      });
      if (errorRol) {
        setGuardando(false);
        avisar("error", `Datos guardados, pero el rol no se pudo cambiar: ${mensajeDeError(errorRol)}`);
        return;
      }
    }
    // El área se guarda por RPC (columna fuera del schema cache) solo si:
    // (a) su carga fue confiable — si falló, el form muestra el default y escribirlo
    //     pisaría el área real (el select va deshabilitado) — y
    // (b) realmente CAMBIÓ — así editar el correo/sede de alguien con un área
    //     desactivada no dispara la validación del server ("Área inválida o inactiva").
    const funcionOriginal = personas.find((p) => p.id === editandoId)?.funcion;
    if (funcionesOk && form.funcion !== funcionOriginal) {
      const { error: errorFuncion } = await supabase.rpc("fn_set_funcion", {
        p_persona_id: editandoId,
        p_funcion: form.funcion,
      });
      if (errorFuncion) {
        setGuardando(false);
        avisar("error", "Datos guardados, pero la función no se pudo cambiar: " + errorFuncion.message);
        return;
      }
    }
    // Cargo (0182): mismo patrón que el área — viaja en fn_personas_funciones, así
    // que solo se escribe si la carga fue confiable y si CAMBIÓ. Escribirlo siempre
    // llenaría la auditoría de filas por editar el correo de alguien.
    const cargoOriginal = personas.find((p) => p.id === editandoId)?.cargo ?? "";
    if (funcionesOk && form.cargo.trim() !== cargoOriginal.trim()) {
      const { error: errorCargo } = await supabase.rpc("fn_set_cargo", {
        p_persona_id: editandoId,
        p_cargo: form.cargo.trim() || null,
      });
      if (errorCargo) {
        setGuardando(false);
        avisar("error", "Datos guardados, pero el cargo no se pudo cambiar: " + errorCargo.message);
        return;
      }
    }
    // Asignación familiar: mismo patrón que el área — con_hijos viaja en la misma RPC
    // (fn_personas_funciones), así que solo se escribe si la carga fue confiable y
    // el valor realmente CAMBIÓ respecto al original.
    const conHijosOriginal = personas.find((p) => p.id === editandoId)?.con_hijos ?? false;
    if (puedeSalarios && funcionesOk && form.conHijos !== conHijosOriginal) {
      const { error: errorHijos } = await supabase.rpc("fn_set_con_hijos", {
        p_persona_id: editandoId,
        p_con_hijos: form.conHijos,
      });
      if (errorHijos) {
        setGuardando(false);
        avisar("error", "Datos guardados, pero la asignación familiar no se pudo cambiar: " + errorHijos.message);
        return;
      }
    }
    // Fecha de ingreso: mismo patrón dirty-check. Viaja por su propia RPC y solo se escribe si
    // se pueden ver salarios (es el único caso donde el campo se muestra), hay una fecha y
    // cambió respecto a la original de esta persona (la del Map de ingresos, no la de `personas`).
    const fechaIngresoOriginal = ingresos.get(editandoId)?.fecha_ingreso ?? "";
    if (puedeSalarios && form.fechaIngreso && form.fechaIngreso !== fechaIngresoOriginal) {
      const { error: errorIngreso } = await supabase.rpc("fn_set_fecha_ingreso", {
        p_persona_id: editandoId,
        p_fecha: form.fechaIngreso,
      });
      if (errorIngreso) {
        setGuardando(false);
        avisar("error", "Datos guardados, pero la fecha de ingreso no se pudo cambiar: " + errorIngreso.message);
        return;
      }
    }
    // Visible en todas las sedes: mismo patrón dirty-check. Viaja por su propia RPC
    // (columna atrapada en el schema cache) y solo se escribe si cambió.
    const visibleOriginal = personas.find((p) => p.id === editandoId)?.visible_todas_sedes ?? false;
    if (funcionesOk && form.visibleTodasSedes !== visibleOriginal) {
      const { error: errorVisible } = await supabase.rpc("fn_set_visible_todas_sedes", {
        p_persona_id: editandoId,
        p_valor: form.visibleTodasSedes,
      });
      if (errorVisible) {
        setGuardando(false);
        avisar("error", "Datos guardados, pero la visibilidad entre sedes no se pudo cambiar: " + errorVisible.message);
        return;
      }
    }
    // Tipo de vínculo: mismo patrón dirty-check. Es el campo con más consecuencias
    // de todo el formulario —decide si la persona acumula gratificación, CTS y
    // vacaciones, si recibe movilidad y si genera EsSalud— así que la RPC deja
    // rastro en correcciones_auditoria por su cuenta (0119). Acá solo se evita
    // escribir cuando no cambió, para no ensuciar esa auditoría.
    const vinculoOriginal = personas.find((p) => p.id === editandoId)?.tipo_vinculo ?? "planilla";
    if (puedeSalarios && funcionesOk && form.tipoVinculo !== vinculoOriginal) {
      const { error: errorVinculo } = await supabase.rpc("fn_set_tipo_vinculo", {
        p_persona_id: editandoId,
        p_tipo: form.tipoVinculo,
      });
      if (errorVinculo) {
        setGuardando(false);
        avisar("error", "Datos guardados, pero el tipo de vínculo no se pudo cambiar: " + errorVinculo.message);
        return;
      }
    }
    // Modalidad de practicante (0324): mismo patrón dirty-check, y va DESPUÉS
    // del cambio de vínculo por la misma razón que la retención de 4ta más
    // abajo — la RPC valida contra el vínculo que ya está escrito en la base,
    // no contra el del form. Si en este mismo guardado la persona DEJÓ de ser
    // practicante, se manda vacío a propósito: la RPC de tipo de vínculo ya
    // limpió la modalidad sola, y forzarla aquí solo repetiría el trabajo.
    const modalidadNueva = form.tipoVinculo === "practicante" ? form.practicanteModalidad : "";
    const modalidadOriginal = personas.find((p) => p.id === editandoId)?.practicante_modalidad ?? "";
    if (puedeSalarios && funcionesOk && modalidadNueva !== modalidadOriginal && form.tipoVinculo === "practicante") {
      const { error: errorModalidad } = await supabase.rpc("fn_set_practicante_modalidad", {
        p_persona_id: editandoId,
        p_modalidad: modalidadNueva || null,
      });
      if (errorModalidad) {
        setGuardando(false);
        avisar("error", "Datos guardados, pero la modalidad de practicante no se pudo cambiar: " + errorModalidad.message);
        return;
      }
    }
    // Fecha de término del contrato: mismo patrón dirty-check. Dos cosas que no
    // son obvias leyendo la llamada:
    //  · VACÍO NO ES "no tocar": es borrarla, que es lo que corresponde cuando el
    //    contrato se renovó. Por eso se manda null explícito y no se omite.
    //  · El motivo va como `undefined` cuando está en blanco para que la función
    //    escriba el suyo por defecto en la auditoría, en vez de una cadena vacía.
    const finOriginal = finesContrato.get(editandoId) ?? "";
    if (puedeSalarios && finesOk && form.finContrato !== finOriginal) {
      const { error: errorFin } = await supabase.rpc("fn_set_fin_contrato", {
        p_persona_id: editandoId,
        p_fecha: form.finContrato || null,
        p_motivo: form.motivoFinContrato.trim() || undefined,
      });
      if (errorFin) {
        setGuardando(false);
        avisar("error", `Datos guardados, pero la fecha de término del contrato no se pudo cambiar: ${mensajeDeError(errorFin)}`);
        return;
      }
    }
    // Retención de renta de 4ta categoría (0245): mismo patrón dirty-check. Dos
    // cosas que no son obvias leyendo la llamada:
    //  · Si en este mismo guardado la persona DEJÓ de ser locadora, se manda
    //    vacío a propósito. La RPC permite borrar la configuración de quien ya no
    //    es rxh —justo para esto— y así no queda un modo de cuarta categoría
    //    colgado de alguien en planilla, que a la vista de una inspección es la
    //    clase de contradicción que hace sospechar del vínculo entero.
    //  · Va DESPUÉS del cambio de vínculo, y tiene que ir después: la RPC valida
    //    contra el vínculo que ya está escrito en la base, no contra el del form.
    const modo4ta = form.tipoVinculo === "rxh" ? form.retencion4ta : "";
    const constancia4ta = form.tipoVinculo === "rxh" ? form.constancia4ta : "";
    const ret4Original = retenciones4ta.get(editandoId) ?? { modo: "", hasta: "" };
    if (
      puedeSalarios && retencionesOk &&
      (modo4ta !== ret4Original.modo || constancia4ta !== ret4Original.hasta)
    ) {
      const { error: errorRet } = await supabase.rpc("fn_set_retencion_4ta", {
        p_persona_id: editandoId,
        p_modo: modo4ta || null,
        p_constancia_hasta: constancia4ta || null,
      });
      if (errorRet) {
        setGuardando(false);
        avisar("error", `Datos guardados, pero la retención de 4ta no se pudo cambiar: ${mensajeDeError(errorRet)}`);
        return;
      }
    }
    setGuardando(false);
    setEditandoId(null);
    setForm(FORM_VACIO);
    await cargar();
    avisar("ok", "Cambios guardados.");
  }

  // ── Salida y reactivación ─────────────────────────────────────────────────
  //
  // Van por las RPC de la 0086 y no por un `update` de `estado`. El update
  // directo que había acá VIOLABA `personas_cese_coherente` —el CHECK exige que
  // quien está inactivo tenga fecha de cese, y quien está activo no la tenga—,
  // así que dar de baja y reactivar fallaban las dos desde que se aplicó esa
  // migración. Comprobado el 2026-08-06 contra el Postgres local: SQLSTATE 23514
  // en los dos casos.
  //
  // Y no se trata solo de que ahora funcione. `fn_cesar_persona` hace tres cosas
  // que un update de una columna no puede hacer: cierra sus tramos de salario y
  // de horario ese día (si no, un salario "vigente" sigue apareciendo años
  // después de que la persona se fue), se niega a aceptar una fecha futura o
  // dentro de un periodo ya pagado, y guarda la fecha de la que viven
  // `fn_grati_trunca`, `fn_cts_trunca` y `fn_vacaciones_truncas`. Sin esa fecha
  // no hay liquidación que calcular.
  function empezarCese(p: Persona) {
    setCeseId(p.id);
    setEditandoId(null);
    setSalEditId(null);
    setHistId(null);
    setMostrandoAlta(false);
    // Si su contrato ya venció, se proponen ESA fecha y ESE motivo: es el caso
    // que el panel viene avisando, y volver a escribirlo a mano invita a
    // equivocarse. En cualquier otro caso el motivo arranca SIN elegir — un
    // motivo por defecto es un motivo que alguien guarda sin leer, y este lo va
    // a leer quien arme su liquidación.
    const fin = finesContrato.get(p.id);
    const yaVencio = fin != null && fin <= hoyLima();
    setCeseForm({ fecha: yaVencio ? fin! : hoyLima(), motivo: yaVencio ? "fin_contrato" : "" });
  }

  async function guardarCese() {
    if (!ceseId) return;
    const p = personas.find((x) => x.id === ceseId);
    if (!ceseForm.fecha) {
      avisar("error", "Falta el último día trabajado.");
      return;
    }
    if (!ceseForm.motivo) {
      avisar("error", "Falta el motivo. Es lo que va a leer quien arme su liquidación y quien conteste una inspección dentro de dos años.");
      return;
    }
    setGuardandoCese(true);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_cesar_persona", {
      p_persona_id: ceseId,
      p_fecha_cese: ceseForm.fecha,
      p_motivo: ceseForm.motivo,
    });
    setGuardandoCese(false);
    if (error) {
      avisar("error", mensajeDeError(error, "registrar la salida"));
      return;
    }
    setCeseId(null);
    await cargar();
    if (puedeSalarios) await cargarSalarios(); // sus tramos se cerraron: ya no tiene salario vigente
    avisar("ok", `${p?.nombres} ${p?.apellidos} figura como inactiva desde el ${fmtFechaDMA(ceseForm.fecha)}. Su historial se conserva.`);
  }

  async function reactivar(p: Persona) {
    if (!window.confirm(
      `¿Reactivar a ${p.nombres} ${p.apellidos}? Se borra su fecha de salida y vuelve a aparecer en el terminal. Ojo: si ya se le pagó una liquidación, volvería a devengar desde su fecha de ingreso original.`
    )) return;
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_reactivar_persona", { p_persona_id: p.id });
    if (error) {
      avisar("error", mensajeDeError(error, "reactivar"));
      return;
    }
    await cargar();
    avisar("ok", `${p.nombres} ${p.apellidos} está activa otra vez. Revísale el salario y el horario: al cesar se cerraron sus tramos.`);
  }

  async function regenerarPin(p: Persona) {
    const pin = generarPin();
    const pinHash = await bcrypt.hash(pin, 10);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.from("personas").update({ pin_hash: pinHash }).eq("id", p.id);
    if (error) {
      avisar("error", mensajeDeError(error, "regenerar el PIN"));
      return;
    }
    avisar("ok", `Nuevo PIN de ${p.nombres} ${p.apellidos}: ${pin} — anótalo ahora, no se vuelve a mostrar.`);
  }

  function empezarEdicion(p: Persona) {
    setEditandoId(p.id);
    setMostrandoAlta(false);
    setSalEditId(null);
    setHistId(null);
    setCeseId(null);
    setForm({
      nombres: p.nombres,
      apellidos: p.apellidos,
      sedeId: p.sede_base_id,
      rol: p.rol as Rol,
      funcion: p.funcion || AREA_DEFAULT,
      email: p.email ?? "",
      conHijos: p.con_hijos,
      tipoVinculo: p.tipo_vinculo ?? "planilla",
      practicanteModalidad: p.practicante_modalidad ?? "",
      cargo: p.cargo ?? "",
      fechaIngreso: ingresos.get(p.id)?.fecha_ingreso ?? "",
      visibleTodasSedes: p.visible_todas_sedes,
      finContrato: finesContrato.get(p.id) ?? "",
      motivoFinContrato: "",
      retencion4ta: retenciones4ta.get(p.id)?.modo ?? "",
      constancia4ta: retenciones4ta.get(p.id)?.hasta ?? "",
    });
  }

  function empezarSalario(p: Persona) {
    if (salariosEstado !== "ok") return; // sin datos cargados no se edita (evita pisar salarios reales)
    const actual = salarios[p.id];
    const rangoInicial = actual?.rango ?? "colibri";
    setSalEditId(p.id);
    setHistId(null);
    setMostrandoAlta(false);
    setEditandoId(null);
    setCeseId(null);
    setSalAnterior(actual?.salario ?? null);
    setSalForm({
      rango: rangoInicial,
      // El suyo si ya lo tiene; si no, la base que declara su rango.
      salario: String(actual?.salario ?? baseDeclaradaDe(rangoInicial) ?? ""),
      // El arranque del periodo abierto. Si todavía no llegó de la base, se cae al
      // primero del mes antes que dejar la fecha vacía.
      vigenteDesde: inicioPeriodo ?? primeroDeMesLima(),
      nota: "",
    });
  }

  // El primer día del periodo ABIERTO, para proponerlo como vigencia. Es de solo
  // lectura y no bloquea nada: si falla, la vigencia cae al primero del mes.
  useEffect(() => {
    if (!puedeSalarios) return;
    void (async () => {
      const supabase = createAdminSupabaseClient();
      const { data, error } = await supabase
        .from("periodos_planilla")
        .select("fecha_ini")
        .neq("estado", "pagado")
        .order("fecha_ini", { ascending: false })
        .limit(1);
      if (!error && data && data.length > 0) setInicioPeriodo(data[0].fecha_ini);
    })();
  }, [puedeSalarios]);

  async function guardarSalario() {
    if (!salEditId) return;
    const monto = Number(salForm.salario);
    if (!Number.isFinite(monto) || monto <= 0) {
      avisar("error", "El salario debe ser un número mayor a 0.");
      return;
    }
    if (!salForm.vigenteDesde) {
      avisar("error", "La fecha de vigencia es obligatoria.");
      return;
    }
    setGuardandoSal(true);
    const supabase = createAdminSupabaseClient();
    // LOS DOS CAMPOS, y en este orden. `salario_mensual_soles` es lo que paga y
    // `sueldo_base_legal` lo que declara: si quedan distintos, la boleta muestra un
    // desglose que no corresponde a nada. Antes esta pantalla solo escribía el
    // primero, así que la base declarada se quedaba donde estaba.
    const { error } = await supabase.rpc("fn_set_salario", {
      p_persona_id: salEditId,
      p_rango: salForm.rango,
      p_salario: monto,
      p_vigente_desde: salForm.vigenteDesde,
      p_nota: salForm.nota.trim() || undefined,
    });
    if (error) {
      setGuardandoSal(false);
      avisar("error", mensajeDeError(error, "guardar el salario"));
      return;
    }

    const { error: eBase } = await supabase.rpc("fn_set_sueldo_base_legal", {
      p_persona_id: salEditId,
      p_monto: monto,
    });
    setGuardandoSal(false);
    if (eBase) {
      // El salario sí quedó. Se dice explícitamente para que nadie crea que no
      // pasó nada y lo vuelva a guardar.
      avisar("error", `El salario se guardó, pero la base declarada no: ${mensajeDeError(eBase, "guardar la base declarada")}`);
      return;
    }
    setSalEditId(null);
    await cargarSalarios();
    avisar("ok", "Salario asignado.");
  }

  async function verHistorial(p: Persona) {
    setSalEditId(null);
    setEditandoId(null);
    setMostrandoAlta(false);
    setCeseId(null);
    const supabase = createAdminSupabaseClient();
    const { data, error } = await supabase.rpc("fn_historial_salario", { p_persona_id: p.id });
    if (error) {
      // no abrir el panel con datos falsos ("Sin registros") cuando en realidad falló
      avisar("error", mensajeDeError(error, "cargar el historial"));
      return;
    }
    setHist((data as TramoSalario[]) ?? []);
    setHistId(p.id);
  }

  const formulario = (modo: "alta" | "edicion") => (
    <div className="mb-6 grid max-w-3xl gap-4 rounded-2xl border border-sand bg-papel p-5 sm:grid-cols-2">
      <label className="flex flex-col gap-1 text-sm">
        Nombres
        <input value={form.nombres} onChange={(e) => setForm({ ...form, nombres: e.target.value })} className="rounded-lg border px-3 py-2" />
      </label>
      <label className="flex flex-col gap-1 text-sm">
        Apellidos
        <input value={form.apellidos} onChange={(e) => setForm({ ...form, apellidos: e.target.value })} className="rounded-lg border px-3 py-2" />
      </label>
      <label className="flex flex-col gap-1 text-sm">
        Sede
        <select value={form.sedeId} onChange={(e) => setForm({ ...form, sedeId: e.target.value })} className="rounded-lg border bg-crema px-3 py-2">
          <option value="">Elegir…</option>
          {/* El nombre, no el código: al dar de alta a alguien se elige
              "Taller LIM", no "LIM". Con dos sedes en Lima no alcanza. */}
          {sedes.map((s) => (
            <option key={s.id} value={s.id}>{s.nombre}</option>
          ))}
        </select>
      </label>
      <label className="flex flex-col gap-1 text-sm">
        Rol
        <select value={form.rol} onChange={(e) => setForm({ ...form, rol: e.target.value as Rol })} className="rounded-lg border bg-crema px-3 py-2">
          {ROLES_OPCIONES.map((r) => (
            <option key={r.valor} value={r.valor}>{r.label}</option>
          ))}
        </select>
      </label>
      {/* CARGO (0182) — va justo debajo del rol a propósito: son la pareja que
          hasta hoy estaba mezclada. El rol de arriba decide qué abre; esto
          decide cómo se la nombra. */}
      <label className="flex flex-col gap-1 text-sm sm:col-span-2">
        Cargo{" "}
        <span className="text-taupe">
          (cómo se la nombra en pantalla: «Socia», «Asesor». Vacío = se muestra el rol.
          No cambia ningún permiso)
        </span>
        <input
          type="text"
          value={form.cargo}
          onChange={(e) => setForm({ ...form, cargo: e.target.value })}
          placeholder="—"
          maxLength={60}
          className="rounded-lg border bg-crema px-3 py-2"
        />
      </label>
      <label className="flex flex-col gap-1 text-sm sm:col-span-2">
        Área{" "}
        <span className="text-taupe">
          {modo === "edicion" && !funcionesOk
            ? "(no se pudo cargar el área actual — deshabilitada para no pisarla)"
            : "(las operativas de sede cuentan para la cobertura de tienda)"}
        </span>
        <select
          value={form.funcion}
          onChange={(e) => setForm({ ...form, funcion: e.target.value })}
          disabled={modo === "edicion" && !funcionesOk}
          className="rounded-lg border bg-crema px-3 py-2 disabled:opacity-50"
        >
          {(() => {
            const activas = areas.filter((a) => a.activa);
            const opciones = activas.map((a) => (
              <option key={a.codigo} value={a.codigo}>{a.nombre}{a.operativa ? " — operativa de sede" : ""}</option>
            ));
            // Caso borde: el área actual de la persona está inactiva o fuera del
            // catálogo — se agrega como opción extra para que el value del select
            // no quede huérfano (se vería vacío y al guardar pisaría el área real).
            if (form.funcion && !activas.some((a) => a.codigo === form.funcion)) {
              const actual = areas.find((a) => a.codigo === form.funcion);
              opciones.push(
                <option key={form.funcion} value={form.funcion}>
                  {(actual?.nombre ?? form.funcion) + " (inactiva)"}
                </option>,
              );
            }
            return opciones;
          })()}
        </select>
      </label>
      <label className="flex flex-col gap-1 text-sm sm:col-span-2">
        Correo (opcional)
        <input type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} className="rounded-lg border px-3 py-2" />
      </label>
      {modo === "edicion" && puedeSalarios && (
        // La fecha de ingreso decide qué feriados le corresponden: un feriado anterior al ingreso
        // no se paga. Se sugiere la primera entrada marcada, pero es editable a mano.
        <label className="flex flex-col gap-1 text-sm sm:col-span-2">
          Fecha de ingreso <span className="text-taupe">(decide qué feriados le corresponden)</span>
          <input
            type="date"
            value={form.fechaIngreso}
            onChange={(e) => setForm({ ...form, fechaIngreso: e.target.value })}
            className="rounded-lg border px-3 py-2"
          />
          {(() => {
            const primera = editandoId ? ingresos.get(editandoId)?.primera_entrada : null;
            if (!primera || primera === form.fechaIngreso) return null;
            return (
              <span className="text-xs text-taupe">
                Primera entrada marcada: {fmtFechaDMA(primera)}{" "}
                <button
                  type="button"
                  onClick={() => setForm({ ...form, fechaIngreso: primera })}
                  className="text-rojo hover:underline"
                >
                  usar
                </button>
              </span>
            );
          })()}
        </label>
      )}
      {modo === "edicion" && puedeSalarios && (() => {
        // UN CONTRATO A PLAZO FIJO SABE CUÁNDO VENCE (0144). Hasta ahora la única
        // forma de llenar esta fecha era pegar SQL a mano, y un dato que depende
        // de que alguien se acuerde de abrir el SQL Editor termina vacío.
        //
        // Es un PLAN, no un hecho: quien tiene fecha sigue activa, sigue marcando
        // y sigue cobrando hasta ese día. El cese —el último día EFECTIVAMENTE
        // trabajado— es otra cosa, se registra con «Desactivar» y no se escribe
        // acá. Que las dos se confundan es el error natural de quien llena esto,
        // así que el texto de abajo lo dice en vez de suponerlo.
        const persona = personas.find((p) => p.id === editandoId);
        const cesada = persona != null && persona.estado !== "activo";
        const finOriginal = editandoId ? finesContrato.get(editandoId) ?? "" : "";
        const antesDelIngreso =
          form.finContrato !== "" && form.fechaIngreso !== "" && form.finContrato < form.fechaIngreso;
        return (
          <div className="flex flex-col gap-1 text-sm sm:col-span-2">
            {/* Misma columna para una practicante (0333): fragmentar "cuándo
                termina esto" en dos campos habría sido peor que reusar uno
                con la etiqueta equivocada. Solo cambia el texto — el candado
                de la base (`fn_set_fin_contrato`) ya funciona igual para
                cualquier tipo_vinculo. */}
            <label className="flex flex-col gap-1">
              <span>
                {form.tipoVinculo === "practicante" ? "Último día de su convenio" : "Último día que trabaja por contrato"}{" "}
                <span className="text-taupe">(el último día que viene, no el siguiente)</span>
              </span>
              <input
                type="date"
                value={form.finContrato}
                // El candado de la base es `personas_fin_contrato_coherente`; esto
                // solo evita que el calendario ofrezca lo que va a ser rechazado.
                min={form.fechaIngreso || undefined}
                disabled={cesada || !finesOk}
                onChange={(e) => setForm({ ...form, finContrato: e.target.value })}
                className="rounded-lg border px-3 py-2 disabled:opacity-50"
              />
            </label>
            <span className="text-xs text-taupe">
              {!finesOk
                ? "No se pudo leer la fecha que tiene guardada, así que el campo está deshabilitado para no pisarla. Recarga la página; si sigue igual, avisa a Felipe."
                : cesada
                  ? form.tipoVinculo === "practicante"
                    ? "Ya está inactiva: su convenio terminó, no hay término que prever."
                    : "Ya está inactiva: su contrato terminó, no hay término que prever."
                  : form.tipoVinculo === "practicante"
                    ? "El convenio de prácticas no es indefinido: siempre tiene un plazo (Ley 28518, art. 30). Anotar la fecha NO la da de baja — sigue activa hasta ese día. Dar de baja es «Desactivar», y va aparte."
                    : "En blanco es lo normal: el contrato indefinido no vence. Anotar la fecha NO la da de baja — sigue activa, sigue marcando y sigue cobrando hasta ese día. Dar de baja es «Desactivar», y va aparte."}
            </span>
            {antesDelIngreso && (
              <span className="text-xs text-rojo">
                El contrato no puede terminar antes de su ingreso ({fmtFechaDMA(form.fechaIngreso)}).
              </span>
            )}
            {/* La consecuencia, mientras se escribe la fecha y no después de
                guardarla: quien la pone tiene que poder decidir sabiéndola. */}
            {!cesada && !antesDelIngreso && saleDelTablero(form.finContrato || undefined) && (
              <span className="rounded-lg bg-ambar/15 px-3 py-2 text-xs text-ambar">
                Con esta fecha sale del tablero de Documentación: ya nadie le va a perseguir la firma
                de su declaración de ruta. Sigue cobrando la movilidad de los días que le queden, así
                que esos días quedan pagados sin el pacto individual que los sostiene — y eso se
                revisa en su liquidación.
              </span>
            )}
            {!cesada && finesOk && form.finContrato !== finOriginal && (
              <label className="mt-1 flex flex-col gap-1">
                <span className="text-xs text-taupe">
                  {form.finContrato === "" ? "Por qué se quita" : "Por qué"} (opcional) — queda en la auditoría
                </span>
                <input
                  value={form.motivoFinContrato}
                  onChange={(e) => setForm({ ...form, motivoFinContrato: e.target.value })}
                  placeholder={
                    form.finContrato === ""
                      ? "ej. el contrato se renovó por 6 meses"
                      : "ej. carta de no renovación entregada el 04/08"
                  }
                  className="rounded-lg border px-3 py-2"
                />
              </label>
            )}
          </div>
        );
      })()}
      {puedeSalarios && (
        // con_hijos llega por la misma RPC que el área: si esa carga falló, en edición
        // se deshabilita para no pisar el valor real con el default (false).
        <label className="flex items-center gap-2 text-sm sm:col-span-2">
          <input
            type="checkbox"
            checked={form.conHijos}
            onChange={(e) => setForm({ ...form, conHijos: e.target.checked })}
            disabled={modo === "edicion" && !funcionesOk}
            className="h-4 w-4 accent-tinta disabled:opacity-50"
          />
          Asignación familiar (tiene hijos) — S/ 113 fijos por periodo
        </label>
      )}
      {puedeSalarios && (
        // EL CAMPO CON MÁS CONSECUENCIAS DEL FORMULARIO. Existe en la base desde la
        // 0085 y hasta la 0119 no se podía elegir desde ninguna pantalla, así que
        // todos quedaban en 'planilla' por defecto. Se muestra la consecuencia
        // debajo del selector, y no en un tooltip, porque quien cambia esto tiene
        // que leerla: pasar a alguien a 'rxh' le apaga la acumulación de sus
        // beneficios y eso no se nota en ninguna otra parte de la pantalla.
        <label className="flex flex-col gap-1 text-sm sm:col-span-2">
          <span>Tipo de vínculo</span>
          <select
            value={form.tipoVinculo}
            onChange={(e) => setForm({ ...form, tipoVinculo: e.target.value })}
            disabled={modo === "edicion" && !funcionesOk}
            className="rounded-lg border border-sand bg-papel px-3 py-2 disabled:opacity-50"
          >
            <option value="planilla">Planilla — contrato de trabajo</option>
            <option value="prueba">Prueba — días de prueba, aún sin contrato</option>
            <option value="rxh">Recibo por honorarios</option>
            <option value="practicante">Practicante — modalidad formativa (Ley 28518)</option>
            <option value="no_trabajador">No trabajador — accionista sin servicios</option>
          </select>
          <span className="text-xs text-taupe">
            {form.tipoVinculo === "planilla"
              ? "Acumula gratificación, CTS y vacaciones. Recibe movilidad y genera EsSalud. Se le mide asistencia y disciplina."
              : form.tipoVinculo === "prueba"
                ? "Días de prueba antes de contratar: se le pagan sus horas y se le mide asistencia, pero NO acumula beneficios (decisión registrada en la 0085). Si se queda, pásala a Planilla — quien trabaja sin estar registrado es infracción muy grave (num. 25.20 del RLGIT)."
                : form.tipoVinculo === "rxh"
                  ? "Locación de servicios: cobra sus horas, pero NO acumula beneficios, NO recibe movilidad y NO genera EsSalud. Tampoco se le mide disciplina — es lo que sostiene que no sea una relación laboral."
                  : form.tipoVinculo === "practicante"
                    ? "Convenio de prácticas (Ley 28518): no es relación laboral. Cobra sus horas y SÍ genera EsSalud, pero NO acumula gratificación, CTS, vacaciones ni AFP, y tampoco se le mide disciplina. Jornada máxima 30h/semana (preprofesional) u 48h/semana (profesional) — el sistema todavía no la hace cumplir sola, revísala al armar su horario."
                    : "Ni asistencia ni beneficios."}
          </span>
        </label>
      )}
      {/* ── LA MODALIDAD DE LA PRACTICANTE (0324) ───────────────────────────
          Solo aparece para quien es practicante, porque solo entonces tiene
          sentido: decide el máximo legal contra el que la pantalla de
          Horarios va a avisar (30h preprofesional, 48h profesional — art. 44,
          Ley 28518). Arranca vacío a propósito, igual que "sin retenerle" en
          la de al lado: no hay una modalidad por defecto razonable, y elegir
          una por la persona sería inventar un dato legal. */}
      {puedeSalarios && form.tipoVinculo === "practicante" && (
        <label className="flex flex-col gap-1 text-sm sm:col-span-2">
          <span>Modalidad</span>
          <select
            value={form.practicanteModalidad}
            onChange={(e) => setForm({ ...form, practicanteModalidad: e.target.value })}
            disabled={modo === "edicion" && !funcionesOk}
            className="rounded-lg border border-sand bg-papel px-3 py-2 disabled:opacity-50"
          >
            <option value="">Sin definir todavía</option>
            <option value="preprofesional">Preprofesional — estudiante, máx. 30h/semana</option>
            <option value="profesional">Profesional — egresada, máx. 48h/semana</option>
          </select>
          <span className="text-xs text-taupe">
            {form.practicanteModalidad === ""
              ? "Sin esto, Horarios no puede avisar si su jornada se pasa del máximo legal — no adivina un número, solo avisa que falta el dato."
              : form.practicanteModalidad === "preprofesional"
                ? "Sigue matriculada; el convenio es con ella, la empresa Y su universidad o instituto (tripartito). No mayor a 6h/día ni 30h/semana."
                : "Ya egresó; el convenio es solo con ella y la empresa. No mayor a 8h/día ni 48h/semana."}
          </span>
        </label>
      )}
      {/* ── LA RETENCIÓN DE CUARTA CATEGORÍA (0245) ─────────────────────────
          Solo aparece para un locador, porque solo un locador emite recibo por
          honorarios. Aparece pegada al tipo de vínculo a propósito: son la misma
          decisión mirada desde dos lados, y quien acaba de pasar a alguien a
          honorarios tiene que decidir esto en el mismo momento.

          POR QUÉ NO LO DECIDE EL SISTEMA SOLO. La regla legal —8 % si el recibo
          supera S/1,500— la sabe la planilla y la aplica sola en modo
          «automática». Lo que el sistema NO puede saber es si la persona pidió
          que se le retenga igual, ni si tiene constancia de suspensión: las dos
          cosas viven en SUNAT y en su decisión, no en esta base. */}
      {puedeSalarios && form.tipoVinculo === "rxh" && (
        <>
          <label className="flex flex-col gap-1 text-sm">
            <span>Retención de Impuesto a la Renta de 4ta</span>
            <select
              value={form.retencion4ta}
              onChange={(e) => setForm({ ...form, retencion4ta: e.target.value })}
              disabled={modo === "edicion" && !retencionesOk}
              className="rounded-lg border border-sand bg-papel px-3 py-2 disabled:opacity-50"
            >
              <option value="">No retenerle</option>
              <option value="automatica">Automática — 8 % solo si el recibo pasa de S/1,500</option>
              <option value="siempre">Siempre — 8 % sea cual sea el monto</option>
            </select>
            <span className="text-xs text-taupe">
              {form.retencion4ta === "automatica"
                ? "La regla legal (art. 74 de la Ley del Impuesto a la Renta): se retiene solo cuando el recibo del mes supera el tope. Por debajo, nada."
                : form.retencion4ta === "siempre"
                  ? "Se retiene aunque el recibo sea chico. Es lo que pide quien factura a varias empresas: se pasa del límite anual, no califica para la suspensión y prefiere adelantar el 8 % antes que pagarlo entero en marzo."
                  : "No se le retiene nada. Ojo: si su recibo pasa de S/1,500 y no tiene constancia de suspensión, retener es obligación de CAYLA — la planilla lo va a avisar."}
            </span>
          </label>
          <label className="flex flex-col gap-1 text-sm">
            <span>Constancia de suspensión — vigente hasta</span>
            <input
              type="date"
              value={form.constancia4ta}
              onChange={(e) => setForm({ ...form, constancia4ta: e.target.value })}
              disabled={modo === "edicion" && !retencionesOk}
              className="rounded-lg border border-sand bg-papel px-3 py-2 disabled:opacity-50"
            />
            <span className="text-xs text-taupe">
              Su constancia del Formulario Virtual 1609. Mientras esté vigente NO se le
              retiene, diga lo que diga el campo de al lado. Dura el año calendario y hay
              que volver a pedirla: cuando vence, manda otra vez lo elegido arriba.
            </span>
          </label>
        </>
      )}
      {modo === "edicion" && puedeSalarios && (
        // Bandera para gente que rota entre locales: aparece en el terminal de CUALQUIER
        // sede, no solo en el de su sede base. Llega/viaja por RPC (schema cache).
        <label className="flex items-start gap-2 text-sm sm:col-span-2">
          <input
            type="checkbox"
            checked={form.visibleTodasSedes}
            onChange={(e) => setForm({ ...form, visibleTodasSedes: e.target.checked })}
            disabled={!funcionesOk}
            className="mt-0.5 h-4 w-4 accent-tinta disabled:opacity-50"
          />
          <span>
            Visible en todas las sedes
            <span className="block text-xs text-taupe">Para quien marca en más de un local. Aparece en el terminal de cualquier sede, no solo en el de su sede base.</span>
          </span>
        </label>
      )}
      <div className="flex gap-3 sm:col-span-2">
        <button
          onClick={modo === "alta" ? crearPersona : guardarEdicion}
          disabled={guardando}
          className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50"
        >
          {guardando ? "Guardando…" : modo === "alta" ? "Agregar (genera PIN)" : "Guardar cambios"}
        </button>
        <button
          onClick={() => { setMostrandoAlta(false); setEditandoId(null); setForm(FORM_VACIO); }}
          className="rounded-lg border px-4 py-2 text-sm"
        >
          Cancelar
        </button>
      </div>
    </div>
  );

  const editorSalario = () => {
    const p = personas.find((x) => x.id === salEditId);
    if (!p) return null;
    return (
      <div className="mb-6 grid max-w-2xl gap-4 rounded-2xl border border-rojo/30 bg-papel p-5 sm:grid-cols-2">
        <p className="text-sm font-medium sm:col-span-2">Salario de {p.nombres} {p.apellidos}</p>
        <label className="flex flex-col gap-1 text-sm">
          Rango
          <select
            value={salForm.rango}
            // Elegir el rango propone SU base declarada. Se puede pisar, y si el
            // monto queda distinto la nota de abajo lo dice — así una excepción
            // pactada se distingue de un dato mal puesto.
            onChange={(e) => setSalForm({
              ...salForm,
              rango: e.target.value,
              salario: String(baseDeclaradaDe(e.target.value) ?? salForm.salario),
            })}
            className="rounded-lg border bg-crema px-3 py-2"
          >
            {RANGOS.map((r) => (
              <option key={r.codigo} value={r.codigo}>{r.label} · {formatSoles(r.baseDeclarada)}</option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-sm">
          Base declarada (S/)
          <input type="number" min="0" step="10" value={salForm.salario}
            onChange={(e) => setSalForm({ ...salForm, salario: e.target.value })}
            className={`rounded-lg border px-3 py-2 ${fueraDeLaBase ? "border-ambar" : ""}`} />
          {/* Lo que va al PLAME y lo que el sistema paga. Se puede pisar cuando se
              acordó otra cosa; el aviso deja constancia de que fue deliberado. */}
          {fueraDeLaBase && (
            <span className="text-[11px] text-ambar">
              Fuera de la base del rango: {RANGO_LABEL[salForm.rango] ?? salForm.rango} declara{" "}
              {formatSoles(baseDeclaradaDe(salForm.rango) ?? 0)}. Convendría escribir el motivo abajo.
            </span>
          )}
          {salAnterior != null && Number(salForm.salario) !== salAnterior && (
            <span className="text-[11px] text-taupe">
              Tenía {formatSoles(salAnterior)} → queda {formatSoles(Number(salForm.salario) || 0)}
              {Number(salForm.salario) < salAnterior && " · le baja"}
            </span>
          )}
          <span className="text-[11px] text-taupe">
            Es lo que se declara y lo que se paga. Lo que recibe de más va por movilidad,
            educación y bono.
          </span>
        </label>
        <label className="flex flex-col gap-1 text-sm">
          Vigente desde
          <input type="date" value={salForm.vigenteDesde} onChange={(e) => setSalForm({ ...salForm, vigenteDesde: e.target.value })} className="rounded-lg border px-3 py-2" />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          Nota (opcional)
          <input value={salForm.nota} onChange={(e) => setSalForm({ ...salForm, nota: e.target.value })} placeholder="ej. ascenso, ajuste anual" className="rounded-lg border px-3 py-2" />
        </label>
        <p className="text-xs text-taupe sm:col-span-2">
          Cambiar el salario cierra el tramo anterior el día previo a la vigencia y abre uno nuevo — los meses ya pagados no se alteran.
        </p>
        <div className="flex gap-3 sm:col-span-2">
          <button onClick={guardarSalario} disabled={guardandoSal} className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50">
            {guardandoSal ? "Guardando…" : "Guardar salario"}
          </button>
          <button onClick={() => setSalEditId(null)} className="rounded-lg border px-4 py-2 text-sm">Cancelar</button>
        </div>
      </div>
    );
  };

  const editorCese = () => {
    const p = personas.find((x) => x.id === ceseId);
    if (!p) return null;
    const fin = finesContrato.get(p.id);
    return (
      <div className="mb-6 grid max-w-2xl gap-4 rounded-2xl border border-rojo/30 bg-papel p-5 sm:grid-cols-2">
        <p className="text-sm font-medium sm:col-span-2">Registrar la salida de {p.nombres} {p.apellidos}</p>
        <label className="flex flex-col gap-1 text-sm">
          Último día trabajado
          <input
            type="date"
            value={ceseForm.fecha}
            // La función rechaza una fecha futura: un cese es un hecho, no un
            // plan. Lo previsto se anota en «Último día que trabaja por contrato».
            max={hoyLima()}
            onChange={(e) => setCeseForm({ ...ceseForm, fecha: e.target.value })}
            className="rounded-lg border px-3 py-2"
          />
          {fin && fin !== ceseForm.fecha && (
            <span className="text-xs text-taupe">
              Su contrato terminaba el {fmtFechaDMA(fin)}{" "}
              <button type="button" onClick={() => setCeseForm({ fecha: fin, motivo: "fin_contrato" })} className="text-rojo hover:underline">
                usar
              </button>
            </span>
          )}
        </label>
        <label className="flex flex-col gap-1 text-sm">
          Motivo
          <select
            value={ceseForm.motivo}
            onChange={(e) => setCeseForm({ ...ceseForm, motivo: e.target.value as MotivoCese })}
            className="rounded-lg border bg-crema px-3 py-2"
          >
            <option value="">Elegir…</option>
            {MOTIVOS_CESE.map((m) => (
              <option key={m} value={m}>{MOTIVO_CESE_LABELS[m]}</option>
            ))}
          </select>
          {ceseForm.motivo === "despido" && (
            <span className="text-[11px] text-ambar">
              Un despido exige carta de preaviso, seis días de descargo y carta de despido (D.S. 003-97-TR).
              Si el contrato simplemente llegó a su fecha, el motivo es «terminó su contrato»: eso no exige
              ninguno de esos papeles.
            </span>
          )}
        </label>
        <p className="text-xs text-taupe sm:col-span-2">
          Esto cierra sus tramos de salario y de horario ese día, y deja de aparecer en el terminal.
          No se borra nada: su historial sostiene los reportes de los periodos que ya pasaron. De esta
          fecha salen su gratificación, su CTS y sus vacaciones truncas, así que tiene que ser el día
          real —ni el de hoy por comodidad, ni el de su carta.
        </p>
        <div className="flex gap-3 sm:col-span-2">
          <button onClick={guardarCese} disabled={guardandoCese} className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50">
            {guardandoCese ? "Guardando…" : "Registrar salida"}
          </button>
          <button onClick={() => setCeseId(null)} className="rounded-lg border px-4 py-2 text-sm">Cancelar</button>
        </div>
      </div>
    );
  };

  const panelHistorial = () => {
    const p = personas.find((x) => x.id === histId);
    if (!p) return null;
    return (
      <div className="mb-6 max-w-2xl rounded-2xl border border-sand bg-papel p-5">
        <div className="mb-2 flex items-center justify-between">
          <p className="text-sm font-medium">Historial de salario — {p.nombres} {p.apellidos}</p>
          <button onClick={() => setHistId(null)} className="text-xs text-taupe hover:underline">Cerrar</button>
        </div>
        {hist.length === 0 ? (
          <p className="text-sm text-taupe">Sin registros todavía.</p>
        ) : (
          <table className="w-full text-sm">
            <thead className="text-left text-taupe">
              <tr>
                <th className="py-1 font-normal">Rango</th>
                <th className="py-1 font-normal">Salario</th>
                <th className="py-1 font-normal">Desde</th>
                <th className="py-1 font-normal">Hasta</th>
                <th className="py-1 font-normal">Asignado por</th>
              </tr>
            </thead>
            <tbody>
              {hist.map((h, i) => (
                <tr key={i} className="border-t">
                  <td className="py-1">{RANGO_LABEL[h.rango] ?? h.rango}</td>
                  <td className="py-1">{formatSoles(Number(h.salario_mensual_soles))}</td>
                  <td className="py-1">{h.vigente_desde}</td>
                  <td className="py-1">{h.vigente_hasta ?? <span className="text-rojo">vigente</span>}</td>
                  <td className="py-1 text-taupe">{h.asignado_por ?? "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    );
  };

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <div className="mb-4 flex items-center justify-between">
          <h1 className="font-serif text-2xl">Equipo</h1>
          {!mostrandoAlta && !editandoId && (
            <div className="flex flex-wrap gap-2">
              <button
                onClick={() => { setMostrandoAlta(true); setForm(FORM_VACIO); setSalEditId(null); setHistId(null); setCeseId(null); }}
                className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema"
              >
                + Agregar persona
              </button>
            </div>
          )}
        </div>

        {puedeSalarios && salariosEstado === "error" && (
          <div className="mb-4 max-w-3xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
            No se pudieron cargar los salarios, así que su edición está deshabilitada (para no pisar
            un salario real con el valor por defecto).{" "}
            <button onClick={() => void cargarSalarios()} className="font-medium underline">
              Reintentar
            </button>
          </div>
        )}

        <div ref={panelRef} className="scroll-mt-4">
          {mostrandoAlta && formulario("alta")}
          {editandoId && formulario("edicion")}
          {ceseId && editorCese()}
          {puedeSalarios && salEditId && editorSalario()}
          {puedeSalarios && histId && panelHistorial()}
        </div>

        {/* Filtros. Todo el filtrado ocurre en el navegador sobre lo que ya está
            cargado: son ~30 personas, no hay nada que pedirle a la base. */}
        {!cargando && (
          <div className="mb-3 flex flex-wrap items-end gap-3">
            <label className="flex flex-col gap-1 text-xs text-taupe">
              Buscar
              <input
                value={busca}
                onChange={(e) => setBusca(e.target.value)}
                placeholder="nombre o apellido"
                className="w-52 rounded-lg border px-3 py-1.5 text-sm text-tinta"
              />
            </label>
            <label className="flex flex-col gap-1 text-xs text-taupe">
              Sede
              <select value={fSede} onChange={(e) => setFSede(e.target.value)} className="rounded-lg border bg-crema px-3 py-1.5 text-sm text-tinta">
                <option value="todas">Todas</option>
                {sedes.map((s) => (<option key={s.id} value={s.id}>{s.nombre}</option>))}
              </select>
            </label>
            <label className="flex flex-col gap-1 text-xs text-taupe">
              Área
              <select value={fArea} onChange={(e) => setFArea(e.target.value)} className="rounded-lg border bg-crema px-3 py-1.5 text-sm text-tinta">
                <option value="todas">Todas</option>
                {areas.filter((a) => a.activa).map((a) => (<option key={a.codigo} value={a.codigo}>{a.nombre}</option>))}
              </select>
            </label>
            <label className="flex flex-col gap-1 text-xs text-taupe">
              Mostrar
              <select value={fEstado} onChange={(e) => setFEstado(e.target.value as FiltroEstado)} className="rounded-lg border bg-crema px-3 py-1.5 text-sm text-tinta">
                <option value="activos">Solo el equipo actual</option>
                <option value="inactivos">Solo quienes ya no están</option>
                {/* Solo para quien ve el dato: a quien no lo ve, esta opción le
                    devolvería una lista vacía sin poder explicarle por qué. */}
                {puedeSalarios && <option value="fin_contrato">Con fin de contrato anotado</option>}
                <option value="todos">Todos</option>
              </select>
            </label>
            {ocultas > 0 && (
              <button
                onClick={() => { setBusca(""); setFSede("todas"); setFArea("todas"); setFEstado("todos"); }}
                className="pb-1.5 text-xs text-taupe underline hover:text-tinta"
              >
                {ocultas === 1 ? "1 persona oculta" : `${ocultas} personas ocultas`} — quitar filtros
              </button>
            )}
          </div>
        )}

        {cargando ? (
          <EsqueletoTabla
            anchos={["w-36", "w-16", "w-20", "w-24", ...(puedeSalarios ? ["w-20"] : []), "w-40", "w-16", "w-24"]}
          />
        ) : visibles.length === 0 ? (
          <div className="max-w-2xl rounded-lg bg-sand/40 px-4 py-3 text-sm text-taupe">
            Ninguna persona coincide con lo que buscas.{" "}
            <button
              onClick={() => { setBusca(""); setFSede("todas"); setFArea("todas"); setFEstado("todos"); }}
              className="font-medium underline"
            >
              Quitar filtros
            </button>
          </div>
        ) : (
          <div className="overflow-x-auto rounded-2xl border border-sand">
            <table className="w-full text-sm">
              <thead className="bg-sand/70 text-left text-taupe">
                <tr>
                  <th className="px-4 py-2 font-normal">Nombre</th>
                  <th className="px-4 py-2 font-normal">Sede</th>
                  <th className="px-4 py-2 font-normal">Rol</th>
                  <th className="px-4 py-2 font-normal">Área</th>
                  {puedeSalarios && <th className="px-4 py-2 font-normal">Salario</th>}
                  <th className="px-4 py-2 font-normal">Correo</th>
                  <th className="px-4 py-2 font-normal">Estado</th>
                  <th className="px-4 py-2 font-normal">Acciones</th>
                </tr>
              </thead>
              <tbody>
                {visibles.map((p) => (
                  <tr key={p.id} className={`border-t bg-papel transition-colors hover:bg-crema ${p.estado === "inactivo" ? "text-taupe" : ""}`}>
                    <td className="px-4 py-2">
                      <button onClick={() => router.push(`/admin/personas/${p.id}`)} className="text-left font-medium text-tinta hover:underline" title="Ver perfil completo">{p.nombres} {p.apellidos}</button>
                      {p.con_hijos && (
                        <span title="Asignación familiar activa" className="ml-1.5 cursor-default text-xs">👶</span>
                      )}
                      {puedeSalarios && ingresos.get(p.id)?.fecha_ingreso && (
                        <div className="text-xs text-taupe">Ingresó: {fmtFechaDMA(ingresos.get(p.id)!.fecha_ingreso!)}</div>
                      )}
                      {/* En ámbar cuando su contrato vence este mes o antes: es el
                          momento en que sale del tablero de Documentación y, si es
                          que no se renueva, cuando hay que registrar su cese. */}
                      {puedeSalarios && finesContrato.has(p.id) && (
                        <div className={`text-xs ${p.estado === "activo" && saleDelTablero(finesContrato.get(p.id)) ? "text-ambar" : "text-taupe"}`}>
                          Contrato hasta: {fmtFechaDMA(finesContrato.get(p.id)!)}
                        </div>
                      )}
                      {/* Cuándo y por qué se fue (0179). Va acá y no en columnas
                          propias para no ensanchar una tabla que ya tiene ocho, y
                          porque solo aplica a quien está inactivo: al equipo activo
                          no le agrega una celda vacía en cada fila. Cierra la
                          secuencia que ya cuentan las dos líneas de arriba:
                          entró · hasta cuándo tenía contrato · cuándo se fue.
                          El motivo llega null si quien mira no es admin ni líder DO
                          —la RPC no se lo entrega— y entonces solo se ve la fecha. */}
                      {p.estado === "inactivo" && p.fecha_cese && (
                        <div className="text-xs text-taupe">
                          Se fue: {fmtFechaDMA(p.fecha_cese)}
                          {p.motivo_cese && (
                            // El texto sale del catálogo también cuando es
                            // `por_revisar`: el desplegable de cese ya lo nombra
                            // así, y dos formas de decir lo mismo en la misma
                            // pantalla se contradicen a la primera. Lo único que
                            // cambia es el ámbar, que dice «esto falta».
                            <> · {p.motivo_cese === "por_revisar"
                              ? <span className="text-ambar" title="Nadie registró por qué se fue. Edita su ficha y elige el motivo real.">
                                  {etiquetaDeCatalogo(p.motivo_cese, MOTIVO_CESE_LABELS)}
                                </span>
                              : etiquetaDeCatalogo(p.motivo_cese, MOTIVO_CESE_LABELS)}</>
                          )}
                        </div>
                      )}
                    </td>
                    <td className="px-4 py-2">{codigoSede(p.sede_base_id)}</td>
                    {/* El CARGO manda sobre la etiqueta del rol (0182). El rol
                        es un permiso —qué pantallas abre— y usarlo como título
                        hacía que tres locadores figuraran como «Líder de equipo
                        (encargada)» y «Admin». Cargo de mando, área, sede, rango
                        y monto fijo son los indicios que desnaturalizan una
                        locación de servicios, y el expediente lo armaba esta
                        misma celda. Sin cargo escrito, se muestra el rol como
                        siempre. */}
                    <td className="px-4 py-2">
                      {p.cargo !== null && p.cargo !== ""
                        ? <span className="whitespace-nowrap">{p.cargo}</span>
                        : (ROLES_OPCIONES.find((r) => r.valor === p.rol)?.label ?? p.rol)}
                    </td>
                    <td className="px-4 py-2">
                      {esOperativaEn(areas, p.funcion)
                        ? <span className="text-taupe">{areaCorto(areas, p.funcion)}</span>
                        : <span className="whitespace-nowrap rounded-full bg-ambar/15 px-2 py-0.5 text-xs text-ambar">{areaCorto(areas, p.funcion)}</span>}
                    </td>
                    {puedeSalarios && (() => {
                      if (salariosEstado !== "ok") {
                        // sin datos confiables no se ofrece Asignar/Editar (evita pisar salarios reales)
                        return (
                          <td className="px-4 py-2 text-xs text-taupe/60">
                            {salariosEstado === "cargando" ? "Cargando…" : "No disponible"}
                          </td>
                        );
                      }
                      const sal = salarios[p.id];
                      return (
                        <td className="px-4 py-2">
                          {sal ? (
                            <span className="whitespace-nowrap">{RANGO_LABEL[sal.rango] ?? sal.rango} · {formatSoles(sal.salario)}</span>
                          ) : (
                            <span className="text-taupe/60">Sin asignar</span>
                          )}
                          <div className="mt-1 flex gap-3 text-xs">
                            <button onClick={() => empezarSalario(p)} className="text-rojo hover:underline">{sal ? "Editar" : "Asignar"}</button>
                            <button onClick={() => verHistorial(p)} className="text-taupe hover:underline">Historial</button>
                          </div>
                        </td>
                      );
                    })()}
                    <td className="px-4 py-2">{p.email ?? <span className="text-taupe/50">—</span>}</td>
                    <td className="px-4 py-2">
                      <span className={`rounded-full px-2 py-0.5 text-xs ${p.estado === "activo" ? "bg-sand text-tinta" : "bg-sand text-taupe"}`}>
                        {p.estado}
                      </span>
                    </td>
                    <td className="px-4 py-2">
                      <div className="flex flex-wrap gap-2 text-xs">
                        <button onClick={() => empezarEdicion(p)} className="rounded border px-2 py-1 hover:bg-sand/50">Editar</button>
                        <button onClick={() => regenerarPin(p)} className="rounded border px-2 py-1 hover:bg-sand/50">Nuevo PIN</button>
                        {p.estado === "activo" ? (
                          // «Registrar salida» y no «Desactivar»: lo que se hace
                          // es anotar un hecho con su fecha y su motivo, no
                          // apagar un interruptor.
                          <button onClick={() => empezarCese(p)} className="rounded border border-rojo/30 px-2 py-1 text-rojo hover:bg-rojo/10">Registrar salida</button>
                        ) : (
                          <button onClick={() => reactivar(p)} className="rounded border px-2 py-1 hover:bg-sand/50">Reactivar</button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        <p className="mt-4 max-w-2xl text-xs text-taupe">
          Al agregar una persona o regenerar un PIN, el PIN aparece una sola vez en el aviso verde —
          anótalo y entrégalo en privado. “Registrar salida” no borra nada: la persona deja de aparecer
          en el terminal pero su historial se conserva, y de la fecha que anotes salen su gratificación,
          su CTS y sus vacaciones truncas. Anotar el fin de contrato es otra cosa y no da de baja a
          nadie: es la fecha prevista de término, y está para avisar antes de que llegue.
        </p>
      </main>
    </div>
  );
}

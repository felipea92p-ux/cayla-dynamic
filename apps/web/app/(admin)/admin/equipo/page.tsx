"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import bcrypt from "bcryptjs";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { AdminNav } from "../nav";
import { Cargando } from "@/components/cargando";
import { useRolActual } from "@/lib/admin/use-rol";
import { RANGOS, RANGO_LABEL, salarioSugerido, formatSoles } from "@/lib/rangos";
import { type Area, AREA_DEFAULT, AREAS_FALLBACK, parseAreas, areaCorto, esOperativaEn } from "@/lib/areas";

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

// YYYY-MM-01 del mes actual en horario de Lima (default de "vigente desde" al asignar salario).
function primeroDeMesLima(): string {
  const partes = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Lima", year: "numeric", month: "2-digit" }).formatToParts(new Date());
  const y = partes.find((p) => p.type === "year")!.value;
  const m = partes.find((p) => p.type === "month")!.value;
  return `${y}-${m}-01`;
}

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
}

type Rol = "integrante" | "supervisor_sede" | "lider_do" | "admin";

interface FormPersona {
  nombres: string;
  apellidos: string;
  sedeId: string;
  rol: Rol;
  funcion: string; // código de área (ver lib/areas)
  email: string;
  conHijos: boolean; // asignación familiar (S/ 113 fijos por periodo) — se escribe por RPC fn_set_con_hijos
  fechaIngreso: string; // decide qué feriados le corresponden — solo edición; se escribe por RPC fn_set_fecha_ingreso
  visibleTodasSedes: boolean; // aparece en el terminal de cualquier sede — se escribe por RPC fn_set_visible_todas_sedes
}

const FORM_VACIO: FormPersona = { nombres: "", apellidos: "", sedeId: "", rol: "integrante", funcion: AREA_DEFAULT, email: "", conHijos: false, fechaIngreso: "", visibleTodasSedes: false };

export default function EquipoPage() {
  const router = useRouter();
  const [sedes, setSedes] = useState<Sede[]>([]);
  const [personas, setPersonas] = useState<Persona[]>([]);
  // Catálogo de áreas (tabla `areas` vía RPC fn_areas; NUNCA por REST — schema cache trabado).
  const [areas, setAreas] = useState<Area[]>(AREAS_FALLBACK);
  // Fecha de ingreso + primera entrada marcada por persona (RPC fn_ingresos; solo admin/lider,
  // devuelve [] para el resto). Decide qué feriados le corresponden a cada persona.
  const [ingresos, setIngresos] = useState<Map<string, { fecha_ingreso: string | null; primera_entrada: string | null }>>(new Map());
  const [cargando, setCargando] = useState(true);
  const [mensaje, setMensaje] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);

  const [mostrandoAlta, setMostrandoAlta] = useState(false);
  const [form, setForm] = useState<FormPersona>(FORM_VACIO);
  const [editandoId, setEditandoId] = useState<string | null>(null);
  const [guardando, setGuardando] = useState(false);

  // Salarios (dato sensible: solo admin/lider_do). Se leen/escriben por RPC.
  // OJO: mientras no estén CARGADOS ("ok") no se permite asignar/editar — si se
  // permitiera, el editor pre-llenaría Colibrí/1320 y podría pisar un salario real.
  const rol = useRolActual();
  const puedeSalarios = rol === "admin" || rol === "lider_do";
  const [salariosEstado, setSalariosEstado] = useState<"cargando" | "ok" | "error">("cargando");
  const [salarios, setSalarios] = useState<Record<string, SalarioVigente>>({});
  const [salEditId, setSalEditId] = useState<string | null>(null);
  const [salForm, setSalForm] = useState({ rango: "colibri", salario: "1320", vigenteDesde: primeroDeMesLima(), nota: "" });
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
      setMensaje({ tipo: "error", texto: `No se pudo cargar el equipo: ${(personasError ?? sedesError)!.message}` });
    }
    // "funcion" y "con_hijos" viajan por RPC (el schema cache de PostgREST no expone las columnas).
    // Si la RPC falla, degradamos al área default / sin asignación para todos sin bloquear la página.
    const funciones = new Map(
      (funcionesError ? [] : ((funcionesData as { persona_id: string; funcion: string; con_hijos: boolean; visible_todas_sedes?: boolean }[] | null) ?? []))
        .map((f) => [f.persona_id, { funcion: f.funcion, con_hijos: f.con_hijos ?? false, visible_todas_sedes: f.visible_todas_sedes ?? false }] as const),
    );
    setFuncionesOk(!funcionesError);
    setSedes(sedesData ?? []);
    setPersonas(
      ((personasData as Omit<Persona, "funcion" | "con_hijos" | "visible_todas_sedes">[]) ?? []).map((p) => {
        const extra = funciones.get(p.id);
        return { ...p, funcion: extra?.funcion ?? AREA_DEFAULT, con_hijos: extra?.con_hijos ?? false, visible_todas_sedes: extra?.visible_todas_sedes ?? false };
      }),
    );
    setCargando(false);
  }, [router]);

  useEffect(() => {
    void cargar();
  }, [cargar]);

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

  function codigoSede(id: string) {
    return sedes.find((s) => s.id === id)?.codigo ?? "?";
  }

  function avisar(tipo: "ok" | "error", texto: string) {
    setMensaje({ tipo, texto });
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
      avisar("error", `No se pudo crear: ${error.message}`);
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
    setGuardando(true);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase
      .from("personas")
      .update({
        nombres: form.nombres.trim(),
        apellidos: form.apellidos.trim(),
        sede_base_id: form.sedeId,
        rol: form.rol,
        email: form.email.trim() || null,
      })
      .eq("id", editandoId);
    if (error) {
      setGuardando(false);
      avisar("error", `No se pudo guardar: ${error.message}`);
      return;
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
    setGuardando(false);
    setEditandoId(null);
    setForm(FORM_VACIO);
    await cargar();
    avisar("ok", "Cambios guardados.");
  }

  async function cambiarEstado(p: Persona, nuevo: "activo" | "inactivo") {
    if (nuevo === "inactivo" && !window.confirm(
      `¿Desactivar a ${p.nombres} ${p.apellidos}? Deja de aparecer en asistencia y no podrá marcar. No se borra nada — puedes reactivarla cuando quieras.`
    )) return;
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase
      .from("personas")
      .update({ estado: nuevo, fecha_estado_cambio: new Date().toISOString() })
      .eq("id", p.id);
    if (error) {
      avisar("error", `No se pudo cambiar el estado: ${error.message}`);
      return;
    }
    await cargar();
    avisar("ok", `${p.nombres} ${p.apellidos} ahora está ${nuevo === "activo" ? "activo(a)" : "inactivo(a)"}.`);
  }

  async function regenerarPin(p: Persona) {
    const pin = generarPin();
    const pinHash = await bcrypt.hash(pin, 10);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.from("personas").update({ pin_hash: pinHash }).eq("id", p.id);
    if (error) {
      avisar("error", `No se pudo regenerar el PIN: ${error.message}`);
      return;
    }
    avisar("ok", `Nuevo PIN de ${p.nombres} ${p.apellidos}: ${pin} — anótalo ahora, no se vuelve a mostrar.`);
  }

  function empezarEdicion(p: Persona) {
    setEditandoId(p.id);
    setMostrandoAlta(false);
    setSalEditId(null);
    setHistId(null);
    setForm({
      nombres: p.nombres,
      apellidos: p.apellidos,
      sedeId: p.sede_base_id,
      rol: p.rol as Rol,
      funcion: p.funcion || AREA_DEFAULT,
      email: p.email ?? "",
      conHijos: p.con_hijos,
      fechaIngreso: ingresos.get(p.id)?.fecha_ingreso ?? "",
      visibleTodasSedes: p.visible_todas_sedes,
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
    setSalForm({
      rango: rangoInicial,
      salario: String(actual?.salario ?? salarioSugerido(rangoInicial) ?? 1320),
      vigenteDesde: primeroDeMesLima(),
      nota: "",
    });
  }

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
    const { error } = await supabase.rpc("fn_set_salario", {
      p_persona_id: salEditId,
      p_rango: salForm.rango,
      p_salario: monto,
      p_vigente_desde: salForm.vigenteDesde,
      p_nota: salForm.nota.trim() || undefined,
    });
    setGuardandoSal(false);
    if (error) {
      avisar("error", `No se pudo guardar el salario: ${error.message}`);
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
    const supabase = createAdminSupabaseClient();
    const { data, error } = await supabase.rpc("fn_historial_salario", { p_persona_id: p.id });
    if (error) {
      // no abrir el panel con datos falsos ("Sin registros") cuando en realidad falló
      avisar("error", `No se pudo cargar el historial: ${error.message}`);
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
            <span className="block text-xs text-taupe/70">Para quien marca en más de un local. Aparece en el terminal de cualquier sede, no solo en el de su sede base.</span>
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
            onChange={(e) => setSalForm({ ...salForm, rango: e.target.value, salario: String(salarioSugerido(e.target.value) ?? salForm.salario) })}
            className="rounded-lg border bg-crema px-3 py-2"
          >
            {RANGOS.map((r) => (
              <option key={r.codigo} value={r.codigo}>{r.label} · {formatSoles(r.salarioSugerido)}</option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-sm">
          Salario mensual (S/)
          <input type="number" min="0" step="10" value={salForm.salario} onChange={(e) => setSalForm({ ...salForm, salario: e.target.value })} className="rounded-lg border px-3 py-2" />
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
                onClick={() => { setMostrandoAlta(true); setForm(FORM_VACIO); setMensaje(null); setSalEditId(null); setHistId(null); }}
                className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema"
              >
                + Agregar persona
              </button>
            </div>
          )}
        </div>

        {mensaje && (
          <div className={`mb-4 max-w-3xl rounded-lg px-4 py-3 text-sm ${mensaje.tipo === "ok" ? "bg-sand/40 text-tinta" : "bg-rojo/10 text-rojo"}`}>
            {mensaje.texto}
          </div>
        )}

        {puedeSalarios && salariosEstado === "error" && (
          <div className="mb-4 max-w-3xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
            No se pudieron cargar los salarios, así que su edición está deshabilitada (para no pisar
            un salario real con el valor por defecto).{" "}
            <button onClick={() => void cargarSalarios()} className="font-medium underline">
              Reintentar
            </button>
          </div>
        )}

        {mostrandoAlta && formulario("alta")}
        {editandoId && formulario("edicion")}
        {puedeSalarios && salEditId && editorSalario()}
        {puedeSalarios && histId && panelHistorial()}

        {cargando ? (
          <Cargando texto="Cargando el equipo…" />
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
                {personas.map((p) => (
                  <tr key={p.id} className={`border-t bg-papel transition-colors hover:bg-crema ${p.estado === "inactivo" ? "text-taupe" : ""}`}>
                    <td className="px-4 py-2">
                      <button onClick={() => router.push(`/admin/personas/${p.id}`)} className="text-left font-medium text-tinta hover:underline" title="Ver perfil completo">{p.nombres} {p.apellidos}</button>
                      {p.con_hijos && (
                        <span title="Asignación familiar activa" className="ml-1.5 cursor-default text-xs">👶</span>
                      )}
                      {puedeSalarios && ingresos.get(p.id)?.fecha_ingreso && (
                        <div className="text-xs text-taupe">Ingresó: {fmtFechaDMA(ingresos.get(p.id)!.fecha_ingreso!)}</div>
                      )}
                    </td>
                    <td className="px-4 py-2">{codigoSede(p.sede_base_id)}</td>
                    <td className="px-4 py-2">{ROLES_OPCIONES.find((r) => r.valor === p.rol)?.label ?? p.rol}</td>
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
                          <button onClick={() => cambiarEstado(p, "inactivo")} className="rounded border border-rojo/30 px-2 py-1 text-rojo hover:bg-rojo/10">Desactivar</button>
                        ) : (
                          <button onClick={() => cambiarEstado(p, "activo")} className="rounded border px-2 py-1 hover:bg-sand/50">Reactivar</button>
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
          anótalo y entrégalo en privado. “Desactivar” no borra nada: la persona deja de aparecer en
          el terminal pero su historial se conserva.
        </p>
      </main>
    </div>
  );
}

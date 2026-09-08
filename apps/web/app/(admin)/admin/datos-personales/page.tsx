"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { TriangleAlert } from "lucide-react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { desacuerdoAsignacionFamiliar, esPrestadorDeServicios, hoyLima, leCorrespondeCuspp, ESTADO_CIVIL_LABELS, ESTADOS_CIVILES, GENERO_LABELS, GENEROS, GRADO_INSTRUCCION_LABELS, GRADOS_INSTRUCCION, puedeExportarPadron, puedeOperarEquipo, puedeVerIdentidad, REGIMEN_PENSION_LABELS, REGIMENES_PENSION, siNoSinDato, VINCULO_DERECHOHABIENTE_LABELS, VINCULOS_DERECHOHABIENTE } from "@cayla-dynamic/shared";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { Cargando } from "@/components/cargando";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { descargarCsv, generarCsv } from "@/lib/admin/csv";
import { useToast } from "@/components/toast";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { Insignia } from "@/components/ui/insignia";
import { Modal } from "@/components/ui/modal";

interface Persona {
  id: string; nombres: string; apellidos: string; documento: string | null;
  sede_base_id: string; email: string | null;
  regimen_pension: string | null;   // CAMBIO 0125
  // Si tiene cuenta de acceso creada. Su correo pasa a ser su login, y la 0198
  // rechaza cambiarlo desde acá.
  auth_user_id: string | null;   // CAMBIO 0198
  // Columna GENERADA en la base: `tipo_vinculo in ('planilla','prueba')`. Se lee
  // en vez de derivarla acá justamente porque es una sola verdad, garantizada
  // por Postgres. Decide qué datos previsionales tiene sentido pedirle a esta
  // persona: a una locadora, ninguno.
  //
  // El tipo admite ausencia a propósito, aunque en la base sea NOT NULL: esta
  // pantalla se despliega por Vercel y el SQL lo pega Felipe a mano, así que hay
  // ventanas en las que el campo no viaja. Nunca se lee con `!`, siempre con
  // `esPrestadorDeServicios` — ver packages/shared/src/vinculo.ts.
  en_planilla: boolean | null | undefined;
}
interface Ficha {
  persona_id: string; nombre_dni: string | null; fecha_nacimiento: string | null; estado_civil: string | null;
  genero: string | null;
  direccion: string | null; celular: string | null; entidad_bancaria: string | null; numero_cuenta: string | null;
  grado_instruccion: string | null; hijos_menores: boolean | null;
  foto_dni_url: string | null; foto_personal_url: string | null; foto_profesional_url: string | null;
  // CAMBIO 0125
  emergencia_nombre: string | null; emergencia_vinculo: string | null; emergencia_telefono: string | null;
  discapacidad: boolean | null; discapacidad_conadis: string | null;
  cuspp: string | null;   // CAMBIO 0198
}
interface Derechohabiente {
  id: string; persona_id: string; nombres: string; apellidos: string;
  documento: string | null; fecha_nacimiento: string | null; vinculo: string;
  essalud: boolean; vida_ley: boolean; vigente_hasta: string | null; nota: string | null;
}
interface Form {
  nombre_dni: string; fecha_nacimiento: string; estado_civil: string; genero: string; direccion: string; celular: string;
  entidad_bancaria: string; numero_cuenta: string; grado_instruccion: string;
  hijos_menores: "" | "si" | "no";
  emergencia_nombre: string; emergencia_vinculo: string; emergencia_telefono: string;
  discapacidad: "" | "si" | "no"; discapacidad_conadis: string;
  cuspp: string;   // CAMBIO 0198
}

const VACIO: Form = {
  nombre_dni: "", fecha_nacimiento: "", estado_civil: "", genero: "", direccion: "", celular: "",
  entidad_bancaria: "", numero_cuenta: "", grado_instruccion: "", hijos_menores: "",
  emergencia_nombre: "", emergencia_vinculo: "", emergencia_telefono: "",
  discapacidad: "", discapacidad_conadis: "", cuspp: "",
};

/**
 * Familiar nuevo. `fecha_nacimiento` NACE EN HOY, no en "" — la fecha de
 * nacimiento de un derechohabiente "hijo" es obligatoria (art. ver validación
 * de guardar()), y un campo de fecha bloqueante que arranca vacío es
 * exactamente el bug que costó cinco despliegues el 2026-08-26 (CLAUDE.md):
 * Safari puede pintar un valor en el input sin disparar el evento que React
 * escucha, dejando el estado en "" mientras la pantalla ya muestra una fecha.
 * "Hoy" es obviamente incorrecto para una fecha de nacimiento —visible y
 * editable en un clic—, pero nunca bloquea el envío por accidente ni dispara
 * el desajuste entre lo que se ve y lo que se manda.
 */
function crearDhVacio() {
  return {
    nombres: "", apellidos: "", vinculo: "hijo", documento: "",
    fecha_nacimiento: hoyLima(), essalud: false, vida_ley: false,
  };
}

export default function DatosPersonalesPage() {
  const router = useRouter();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const puede = puedeOperarEquipo(rol);
  // El DNI y el régimen de pensión los edita SOLO Desarrollo Organizacional: el
  // primero se imprime en memos y contratos, el segundo decide cuánto se le
  // descuenta a la persona. Las funciones de la base los rechazan para la
  // encargada, así que aquí se muestran de solo lectura en vez de dejar que el
  // guardado falle con un error que nadie entiende.
  const puedeIdentidad = puedeVerIdentidad(rol);
  const { avisar } = useToast();

  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [sedes, setSedes] = useState<Map<string, string>>(new Map());
  const [fichas, setFichas] = useState<Map<string, Ficha>>(new Map());
  const [derechos, setDerechos] = useState<Derechohabiente[]>([]);
  const [sel, setSel] = useState<string>("");
  const [form, setForm] = useState<Form>(VACIO);
  // Identidad: viven en `personas`, no en la ficha, y se guardan con su propia
  // función porque cada una deja su rastro de auditoría por separado.
  const [dni, setDni] = useState("");
  const [motivoDni, setMotivoDni] = useState("");
  const [regimen, setRegimen] = useState("");
  // Desde cuándo rige el régimen nuevo. Lo exige la 0277: el descuento lo decide
  // el TRAMO vigente de `asignaciones_regimen_pension`, y un tramo sin principio
  // no se puede leer a una fecha. Llega con el primer día del periodo abierto ya
  // puesto —la misma fecha que la función sugiere cuando rechaza una que cae en
  // un periodo pagado— y se puede cambiar para el caso raro.
  const [regimenDesde, setRegimenDesde] = useState("");
  const [periodoAbiertoIni, setPeriodoAbiertoIni] = useState<string | null>(null);
  // El correo vive en `personas`, no en la ficha: es el usuario de acceso.
  const [email, setEmail] = useState("");
  const [dhNuevo, setDhNuevo] = useState(crearDhVacio());
  const [dhAbierto, setDhAbierto] = useState(false);
  // Qué familiar se está editando. `null` = se está creando uno nuevo. El
  // formulario es el MISMO para las dos cosas: `fn_set_derechohabiente` ya hace
  // upsert según venga `p_id`, así que duplicarlo sería tener dos sitios donde
  // arreglar el próximo campo que falte.
  const [dhEditando, setDhEditando] = useState<string | null>(null);
  // Reemplaza al `window.confirm` nativo (ver CLAUDE.md — Felipe aprobó migrar
  // todos los diálogos nativos al Modal compartido). `null` = modal cerrado.
  const [confirmarCierre, setConfirmarCierre] = useState<{ id: string; nombre: string } | null>(null);
  // `personas.con_hijos` es OTRO campo que el `hijos_menores` de la ficha, y es
  // el que de verdad decide si se paga la asignación familiar mensual
  // (fn_planilla_calcular). Lo escribe la pantalla de Equipo; la ficha escribe
  // el suyo; y nada los mantiene de acuerdo. Se trae aquí solo para poder
  // avisar cuando difieran.
  //
  // `null` significa «no se pudo cargar», y NO es lo mismo que «nadie tiene
  // hijos». La pantalla de Equipo degrada a `false` para todos cuando su RPC
  // falla; copiar eso aquí convertiría un fallo de red en un aviso falso contra
  // cada persona del equipo. Cuando es null, la comprobación no se hace.
  const [conHijos, setConHijos] = useState<Map<string, boolean> | null>(null);
  // Si la carga falló, la pantalla no sabe qué hay de verdad: guardar desde aquí
  // borraría datos. Se bloquea hasta que una recarga vaya bien.
  const [cargaFallida, setCargaFallida] = useState(false);
  const [cargando, setCargando] = useState(true);
  const [guardando, setGuardando] = useState(false);
  const [q, setQ] = useState("");
  const [soloSinFicha, setSoloSinFicha] = useState(false);
  const fichaRef = useRef<HTMLDivElement>(null);

  const cargar = useCallback(async () => {
    setCargando(true);
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    const [
      { data: p, error: eP }, { data: s, error: eS },
      { data: dp, error: eD }, { data: dh, error: eDH },
      { data: fn, error: eFN },
      { data: per, error: ePer },
    ] = await Promise.all([
      supabase.from("personas").select("id, nombres, apellidos, documento, sede_base_id, email, regimen_pension, auth_user_id, en_planilla").eq("estado", "activo").order("nombres"),
      supabase.from("sedes").select("id, codigo"),
      supabase.from("datos_personales").select("persona_id, nombre_dni, fecha_nacimiento, estado_civil, genero, direccion, celular, entidad_bancaria, numero_cuenta, grado_instruccion, hijos_menores, foto_dni_url, foto_personal_url, foto_profesional_url, emergencia_nombre, emergencia_vinculo, emergencia_telefono, discapacidad, discapacidad_conadis, cuspp"),
      supabase.from("derechohabientes").select("id, persona_id, nombres, apellidos, documento, fecha_nacimiento, vinculo, essalud, vida_ley, vigente_hasta, nota").order("apellidos"),
      // `con_hijos` viaja por RPC porque el schema cache de PostgREST no expone
      // esa columna — misma razón que en la pantalla de Equipo.
      supabase.rpc("fn_personas_funciones"),
      // La misma fuente que Planilla y Costos, para que «el periodo abierto» no
      // tenga dos versiones. Solo alimenta la fecha sugerida del régimen.
      supabase.rpc("fn_periodos"),
    ]);

    // Si una consulta falla NO se pisa el estado. Antes se hacía
    // `(dp as Ficha[]) ?? []`, y un fallo de red dejaba el mapa de fichas vacío:
    // la pantalla mostraba a todo el mundo "sin ficha", el formulario salía en
    // blanco, y pulsar Guardar escribía null en TODO — borrando DNI, dirección y
    // número de cuenta de una persona real, sin que nada avisara.
    const fallo = eP ?? eS ?? eD ?? eDH;
    if (fallo) {
      setCargaFallida(true);
      avisar("error", `No se pudieron cargar las fichas: ${fallo.message}. No guardes nada hasta recargar: lo que ves puede no ser lo que hay.`);
      setCargando(false);
      return;
    }
    setCargaFallida(false);
    // A propósito FUERA del corte de arriba: esta RPC solo alimenta un aviso,
    // nunca lo que se guarda. Que se caiga no puede bloquear la ficha entera ni
    // impedir corregir un DNI. Si falla, el mapa queda en null y la
    // comprobación cruzada simplemente no se hace — callarse es correcto,
    // inventar un aviso contra cada persona no lo sería.
    setConHijos(
      eFN
        ? null
        : new Map(
            (((fn as { persona_id: string; con_hijos: boolean | null }[] | null) ?? []))
              .map((x) => [x.persona_id, x.con_hijos === true] as const),
          ),
    );
    // Igual que `conHijos`: fuera del corte de arriba a propósito. Si falla, la
    // fecha del régimen llega vacía y hay que escribirla, que es molesto pero
    // honesto — sugerir una fecha inventada sí sería grave, porque decide a qué
    // periodo se le aplica el descuento nuevo. `fn_periodos` viene ordenada por
    // fecha_fin descendente, así que el primer 'abierto' es el vigente.
    setPeriodoAbiertoIni(
      ePer
        ? null
        : ((per as Array<{ fecha_ini: string; estado: string }> | null) ?? [])
            .find((x) => x.estado === "abierto")?.fecha_ini ?? null,
    );
    setPersonas((p as Persona[]) ?? []);
    setSedes(new Map(((s as Array<{ id: string; codigo: string }>) ?? []).map((x) => [x.id, x.codigo])));
    setFichas(new Map(((dp as Ficha[]) ?? []).map((x) => [x.persona_id, x])));
    setDerechos((dh as Derechohabiente[]) ?? []);
    setCargando(false);
  }, [supabase, router, avisar]);

  useEffect(() => { void cargar(); }, [cargar]);

  // ÚNICA puerta de entrada a la ficha. Nunca `setSel` suelto: quien cambia
  // `sel` sin pasar por acá deja el formulario con los datos de la persona
  // ANTERIOR, y como `fn_set_datos_personales` es un upsert que reemplaza,
  // pulsar Guardar los escribe encima de la ficha equivocada. Pasó de verdad
  // el 2026-08-13: el atajo de «fichas incompletas» llamaba a setSel directo,
  // la ficha se abría con el correo y el DNI en blanco, y guardar intentó
  // borrarle el correo a alguien que sí lo tenía. Lo frenó el candado de la
  // 0198 —que solo cuida el correo—; el resto de la ficha ya se había escrito.
  function seleccionar(id: string, forzarScroll = false) {
    setSel(id); setMotivoDni(""); setDhAbierto(false); setDhNuevo(crearDhVacio()); setDhEditando(null);
    // En móvil la ficha queda debajo de la lista: la traemos a la vista
    // (respetando la preferencia de "reducir movimiento" del sistema).
    // `forzarScroll` es para quien entra desde el bloque de arriba, donde la
    // ficha queda fuera de vista también en pantalla grande.
    if (typeof window !== "undefined" && (forzarScroll || window.innerWidth < 768)) {
      const suave = !window.matchMedia("(prefers-reduced-motion: reduce)").matches;
      setTimeout(() => fichaRef.current?.scrollIntoView({ behavior: suave ? "smooth" : "auto", block: "start" }), 60);
    }
    const persona = personas.find((x) => x.id === id) ?? null;
    setDni(persona?.documento ?? "");
    setRegimen(persona?.regimen_pension ?? "");
    setRegimenDesde(periodoAbiertoIni ?? "");
    setEmail(persona?.email ?? "");
    const f = fichas.get(id);
    setForm(f ? {
      nombre_dni: f.nombre_dni ?? "", fecha_nacimiento: f.fecha_nacimiento ?? "", estado_civil: f.estado_civil ?? "",
      genero: f.genero ?? "",
      direccion: f.direccion ?? "", celular: f.celular ?? "", entidad_bancaria: f.entidad_bancaria ?? "",
      numero_cuenta: f.numero_cuenta ?? "", grado_instruccion: f.grado_instruccion ?? "",
      hijos_menores: f.hijos_menores === true ? "si" : f.hijos_menores === false ? "no" : "",
      emergencia_nombre: f.emergencia_nombre ?? "", emergencia_vinculo: f.emergencia_vinculo ?? "",
      emergencia_telefono: f.emergencia_telefono ?? "",
      discapacidad: f.discapacidad === true ? "si" : f.discapacidad === false ? "no" : "",
      discapacidad_conadis: f.discapacidad_conadis ?? "",
      cuspp: f.cuspp ?? "",
    } : { ...VACIO });
  }

  const personaSel = personas.find((p) => p.id === sel) ?? null;
  const dniCambio = !!personaSel && dni.trim() !== (personaSel.documento ?? "");
  // Escribir el DNI por primera vez no es una corrección: no hay nada que
  // justificar cuando antes no había ningún valor. El motivo solo tiene
  // sentido frente a un DNI que ya existía y se está reemplazando.
  const dniEsCorreccion = dniCambio && (personaSel?.documento ?? "").trim() !== "";
  const regimenCambio = !!personaSel && regimen !== (personaSel.regimen_pension ?? "");
  // Los DOS lados en minúsculas. Antes se bajaba solo el izquierdo, así que un
  // correo guardado con mayúsculas —medidos en producción el 2026-08-10: dos—
  // daba «cambió» para siempre sin que nadie tocara el campo. Cada «Guardar
  // ficha» llamaba entonces a fn_set_email, y si esa persona ya tiene cuenta la
  // 0198 lo rechaza a propósito: la pantalla terminaba en «La ficha se guardó,
  // pero el correo no» y hacía return, así que el aviso de éxito no salía nunca.
  // Un error rojo, permanente y falso, que además no se podía corregir desde acá.
  // Se compara como compara la base: `lower(trim())` contra `lower(trim())`.
  const emailCambio =
    !!personaSel && email.trim().toLowerCase() !== (personaSel.email ?? "").trim().toLowerCase();
  // Tiene acceso creado: su correo es su login y la 0198 rechaza cambiarlo acá.
  const tieneCuenta = personaSel?.auth_user_id != null;
  // El CUSPP solo existe en el sistema PRIVADO de pensiones. ONP no tiene cuenta
  // individual, y quien ya se jubiló no aporta. Se decide por el régimen que se
  // ve en pantalla —no por el guardado— para que el campo aparezca en cuanto se
  // elige la AFP, sin tener que guardar primero.
  //
  // `en_planilla` se suma a la condición (0242): el CUSPP entra al T-Registro de
  // un TRABAJADOR, y una locadora no está en el T-Registro. Su afiliación, si la
  // tiene, no pasa por CAYLA.
  //
  // `|| form.cuspp.trim() !== ""` es el escape, y hace falta: si alguien ya le
  // cargó un código a una locadora, esconder el campo lo dejaría guardado y
  // fuera de la vista, imposible de leer o de borrar desde la pantalla. Un dato
  // que existe pero no se puede ver es peor que un campo de más.
  const esAfp = !esPrestadorDeServicios(personaSel?.en_planilla)
    && regimen !== "" && regimen !== "onp" && regimen !== "jubilada";
  const mostrarCuspp = esAfp || form.cuspp.trim() !== "";

  async function guardar() {
    if (!sel) return;
    if (cargaFallida) {
      avisar("error", "No se guarda: las fichas no llegaron a cargar y guardar ahora borraría los datos que ya existen. Recarga la página.");
      return;
    }
    // El motivo del DNI se exige aquí y no solo en la base, para que el aviso
    // llegue antes de intentar guardar y no como un error del servidor.
    if (dniEsCorreccion && !motivoDni.trim()) {
      avisar("error", "Escribe el motivo del cambio de DNI: ese número se imprime en memos y contratos.");
      return;
    }
    // Por lo mismo, y con más razón: sin fecha el régimen no se puede guardar, y
    // llegar hasta el servidor significaría guardar la ficha y fallar después.
    if (regimenCambio && !regimenDesde) {
      avisar("error", "Escribe desde cuándo rige el régimen de pensión nuevo: esa fecha decide a qué periodo se le aplica el descuento.");
      return;
    }
    setGuardando(true);

    // Las fotos/documentos ya no se editan desde esta pantalla — se cargan por
    // otra vía — pero `fn_set_datos_personales` es un upsert que REEMPLAZA los
    // tres campos en cada llamada (`foto_x_url = excluded.foto_x_url`, sin
    // COALESCE contra lo que ya había: ver la migración 0369). Si se mandara
    // "" o null acá, cada "Guardar ficha" borraría lo que esa otra vía haya
    // cargado. Se manda de vuelta el valor que ya está en la fila, tal cual se
    // cargó, para que guardar el resto de la ficha no lo toque.
    const fichaActual = fichas.get(sel);

    // Los campos de la ficha SIEMPRE se mandan completos: la función de la
    // base es un upsert que reemplaza, no un update parcial. Si se omite uno,
    // se guarda en null.
    const { error } = await supabase.rpc("fn_set_datos_personales", {
      p_persona_id: sel,
      p_nombre_dni: form.nombre_dni.trim() || null,
      p_fecha_nacimiento: form.fecha_nacimiento || null,
      p_estado_civil: form.estado_civil.trim() || null,
      p_genero: form.genero.trim() || null,
      p_direccion: form.direccion.trim() || null,
      p_celular: form.celular.trim() || null,
      p_entidad_bancaria: form.entidad_bancaria.trim() || null,
      p_numero_cuenta: form.numero_cuenta.trim() || null,
      p_grado_instruccion: form.grado_instruccion.trim() || null,
      p_hijos_menores: form.hijos_menores === "" ? null : form.hijos_menores === "si",
      p_foto_dni_url: fichaActual?.foto_dni_url ?? null,
      p_foto_personal_url: fichaActual?.foto_personal_url ?? null,
      p_foto_profesional_url: fichaActual?.foto_profesional_url ?? null,
      p_emergencia_nombre: form.emergencia_nombre.trim() || null,
      p_emergencia_vinculo: form.emergencia_vinculo.trim() || null,
      p_emergencia_telefono: form.emergencia_telefono.trim() || null,
      p_discapacidad: form.discapacidad === "" ? null : form.discapacidad === "si",
      p_discapacidad_conadis: form.discapacidad_conadis.trim() || null,
      p_cuspp: form.cuspp.trim() || null,   // CAMBIO 0198
    });
    if (error) { setGuardando(false); avisar("error", mensajeDeError(error)); return; }

    // Identidad: solo si de verdad cambió, para no ensuciar la auditoría con
    // guardados que no cambian nada.
    if (dniCambio) {
      const { error: eDni } = await supabase.rpc("fn_set_documento", {
        p_persona_id: sel, p_documento: dni.trim(), p_motivo: motivoDni.trim(),
      });
      if (eDni) { setGuardando(false); avisar("error", `La ficha se guardó, pero el DNI no: ${mensajeDeError(eDni)}`); return; }
    }
    if (regimenCambio) {
      // CAMBIO 0277 — Antes esto llamaba a `fn_set_regimen_pension`, que escribía
      // solo `personas.regimen_pension`. Desde la 0261 la planilla lee el TRAMO
      // vigente y cae a esa columna únicamente como respaldo, así que a quien ya
      // tenía tramo el cambio no le movía el descuento — y esta pantalla decía
      // que sí. La función buena escribe el tramo, deja auditoría y se niega si
      // la fecha cae en un periodo pagado.
      const { error: eReg } = await supabase.rpc("fn_cambiar_regimen_pension", {
        p_persona_id: sel, p_regimen: regimen || null,
        p_desde: regimenDesde, p_nota: null,
      });
      if (eReg) { setGuardando(false); avisar("error", `La ficha se guardó, pero el régimen de pensión no: ${mensajeDeError(eReg)}`); return; }
    }
    // El correo va por su propia función (0198): con cuenta creada la base lo
    // rechaza, porque cambiarlo acá no cambiaría el acceso.
    if (emailCambio) {
      const { error: eMail } = await supabase.rpc("fn_set_email", {
        p_persona_id: sel, p_email: email.trim() || null,
      });
      if (eMail) { setGuardando(false); avisar("error", `La ficha se guardó, pero el correo no: ${mensajeDeError(eMail)}`); return; }
    }

    setGuardando(false);
    await cargar();
    setMotivoDni("");
    avisar("ok", regimenCambio ? `Ficha guardada. El régimen nuevo rige desde el ${regimenDesde} y ya cambia lo que se le descuenta.` : "Ficha guardada.");
  }

  async function agregarDerechohabiente() {
    if (!sel) return;
    if (!dhNuevo.nombres.trim() || !dhNuevo.apellidos.trim()) {
      avisar("error", "El nombre y el apellido del familiar son obligatorios.");
      return;
    }
    if (dhNuevo.vinculo === "hijo" && !dhNuevo.fecha_nacimiento) {
      avisar("error", "La fecha de nacimiento de una hija o hijo es obligatoria: es lo que define hasta cuándo lo cubre EsSalud.");
      return;
    }
    setGuardando(true);
    const { error } = await supabase.rpc("fn_set_derechohabiente", {
      p_id: dhEditando, p_persona_id: sel,
      p_nombres: dhNuevo.nombres.trim(), p_apellidos: dhNuevo.apellidos.trim(),
      p_vinculo: dhNuevo.vinculo,
      p_documento: dhNuevo.documento.trim() || null,
      p_fecha_nacimiento: dhNuevo.fecha_nacimiento || null,
      p_essalud: dhNuevo.essalud, p_vida_ley: dhNuevo.vida_ley, p_nota: null,
    });
    setGuardando(false);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    const editaba = dhEditando !== null;
    setDhNuevo(crearDhVacio()); setDhAbierto(false); setDhEditando(null);
    await cargar();
    avisar("ok", editaba ? "Familiar corregido." : "Familiar agregado.");
  }

  /** Carga un familiar ya registrado en el formulario, para corregirlo. */
  function editarDerechohabiente(d: Derechohabiente) {
    setDhEditando(d.id);
    setDhAbierto(true);
    setDhNuevo({
      nombres: d.nombres, apellidos: d.apellidos, vinculo: d.vinculo,
      documento: d.documento ?? "", fecha_nacimiento: d.fecha_nacimiento ?? "",
      essalud: d.essalud, vida_ley: d.vida_ley,
    });
  }

  async function cerrarDerechohabiente(id: string, nombre: string) {
    setGuardando(true);
    const { error } = await supabase.rpc("fn_cerrar_derechohabiente", { p_id: id, p_hasta: null });
    setGuardando(false);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    setConfirmarCierre(null);
    await cargar();
    avisar("ok", `${nombre} quedó cerrado con la fecha de hoy.`);
  }

  const lista = personas.filter((p) =>
    `${p.nombres} ${p.apellidos}`.toLowerCase().includes(q.trim().toLowerCase())
    && (!soloSinFicha || !fichas.has(p.id)));
  const sinFicha = personas.filter((p) => !fichas.has(p.id)).length;
  const misDerechos = derechos.filter((d) => d.persona_id === sel);

  // ── Qué le falta a cada ficha ──────────────────────────────────────────────
  //
  // La lista son los campos que el contador necesita para el T-Registro, y por
  // eso `foto_personal_url` no está: falta una foto y no pasa nada; falta el
  // número de cuenta y esa persona no cobra.
  //
  // Se calcula acá y no en la base a propósito: los datos ya están cargados en
  // esta pantalla, y una consulta más para contar nulos sería una segunda verdad
  // sobre qué es «estar completa».
  const FALTANTES: readonly { clave: string; etiqueta: string }[] = [
    { clave: "documento", etiqueta: "DNI" },
    { clave: "nombre_dni", etiqueta: "nombre según DNI" },
    { clave: "fecha_nacimiento", etiqueta: "nacimiento" },
    { clave: "estado_civil", etiqueta: "estado civil" },
    { clave: "genero", etiqueta: "género" },
    { clave: "grado_instruccion", etiqueta: "instrucción" },
    { clave: "celular", etiqueta: "celular" },
    { clave: "email", etiqueta: "correo" },
    { clave: "direccion", etiqueta: "dirección" },
    { clave: "numero_cuenta", etiqueta: "cuenta" },
    { clave: "regimen_pension", etiqueta: "régimen de pensión" },
  ];

  // Se devuelven DOS listas separadas y no una sola, porque son dos cosas
  // distintas y mezclarlas no se entendía:
  //
  //   `faltan`  campos vacíos. Se leen en cadena: «falta DNI · celular».
  //   `avisos`  datos que SÍ están pero se contradicen entre sí. Cada uno es
  //             una frase entera que dice qué pasa y qué hacer.
  //
  // La primera versión los metía en la misma lista y salía «falta ⚠ asignación
  // familiar sin familiar registrado», que Felipe leyó y no entendió — con
  // razón: ahí no falta un campo llamado «asignación familiar», sobra una
  // contradicción. El error es del diseño, no de quien lo lee.
  const incompletas = useMemo(() => {
    const hoy = new Date().toISOString().slice(0, 10);
    return personas
      .map((p) => {
        const f = fichas.get(p.id);
        const valor: Record<string, unknown> = { ...(f ?? {}), documento: p.documento, email: p.email, regimen_pension: p.regimen_pension };
        const faltan = FALTANTES.filter((c) => {
          const v = valor[c.clave];
          if (v !== null && v !== undefined && String(v).trim() !== "") return false;
          // A una locadora no se le pide el RÉGIMEN DE PENSIÓN. CAYLA no le
          // retiene aporte previsional (0242): si ella aporta, lo hace como
          // independiente y por su cuenta, y ese dato no es de la empresa.
          // Pedirlo era un «falta» que nadie podía completar con sentido.
          if (c.clave === "regimen_pension" && esPrestadorDeServicios(p.en_planilla)) return false;
          return true;
        }).map((c) => c.etiqueta);

        // El CUSPP no es un campo más: solo se le pide a quien está en una
        // AFP. En ONP no hay cuenta individual y quien se jubiló no aporta, así
        // que para ellas no existe. Va acá y no en FALTANTES porque esa lista
        // es fija y esta condición depende del régimen de cada persona.
        //
        // ⇩ Y TAMPOCO a una locadora, por una razón distinta de la del régimen:
        // no es que no tenga cuenta individual, es que su afiliación no pasa por
        // CAYLA. El CUSPP entra al T-Registro de un TRABAJADOR, y un locador no
        // está en el T-Registro. Medido el 2026-08-13: eran dos personas con un
        // «falta CUSPP» permanente que nadie podía completar nunca — el tipo de
        // aviso que enseña a ignorar los avisos.
        if (leCorrespondeCuspp(p.en_planilla, p.regimen_pension)
            && !(f?.cuspp ?? "").trim()) faltan.push("CUSPP");

        const avisos: string[] = [];
        // Un dato imposible se ve igual de bien que uno correcto hasta que el
        // contador lo rechaza. Había uno en producción el 2026-08-08.
        if (f?.fecha_nacimiento && f.fecha_nacimiento > hoy) {
          avisos.push("la fecha de nacimiento está en el futuro — corrígela arriba");
        }
        // Quien cobra asignación familiar tiene que tener a quién declararle.
        // Es la asignación familiar mensual: si no corresponde se está pagando de más, y si
        // corresponde falta el respaldo que la sustenta ante una fiscalización.
        if (f?.hijos_menores === true && !derechos.some((d) => d.persona_id === p.id)) {
          avisos.push("cobra asignación familiar y no tiene ningún hijo registrado — agrégalo en Familiares, más abajo");
        }
        // El caso inverso, que cuesta al revés: hay familiares cargados y la
        // ficha dice que no hay hijos menores, así que NO se le paga la
        // asignación que quizá le corresponde.
        if (f?.hijos_menores === false && derechos.some((d) => d.persona_id === p.id && d.vinculo === "hijo")) {
          avisos.push("tiene hijos registrados pero la ficha dice que no hay menores a cargo — si los hay, le falta cobrar la asignación familiar");
        }
        // Las dos comprobaciones de arriba miran la ficha contra los familiares
        // cargados. Ninguna mira el campo que DE VERDAD paga: `personas.con_hijos`,
        // que escribe la pantalla de Equipo y lee `fn_planilla_calcular`. Son dos
        // campos, en dos tablas, para la misma pregunta, y nada los sincroniza:
        // se puede declarar una cosa al contador y abonar la contraria.
        //
        // Si `conHijos` es null la RPC no cargó, y entonces no se dice nada: un
        // fallo de red no puede convertirse en un aviso contra cada persona.
        // Quién decide qué es un desacuerdo vive en `asignacion-familiar.ts`,
        // con sus pruebas: es la parte que puede producir un aviso FALSO contra
        // una persona real, y eso cuesta más que no avisar. Aquí solo se elige
        // la frase, que sí es asunto de esta pantalla.
        switch (desacuerdoAsignacionFamiliar(conHijos?.get(p.id), f?.hijos_menores)) {
          case "paga_y_declara_que_no":
            avisos.push("se le paga la asignación familiar y esta ficha dice que NO tiene hijos menores — y es esta ficha la que sale en el padrón del contador; cuadra las dos");
            break;
          case "declara_y_no_cobra":
            avisos.push("esta ficha dice que tiene hijos menores y NO se le está pagando la asignación familiar — si le corresponde, actívala en Equipo");
            break;
          case "paga_y_la_ficha_calla":
            avisos.push("se le paga la asignación familiar y esta ficha no lo declara — el padrón saldrá con «SIN DATO» en esa columna");
            break;
        }
        return { p, faltan, avisos, sinFicha: f === undefined };
      })
      .filter((x) => x.faltan.length > 0 || x.avisos.length > 0)
      // Las contradicciones primero: un campo vacío se llena cuando se pueda,
      // pero un dato que se contradice ya está moviendo plata hoy.
      .sort((a, b) => b.avisos.length - a.avisos.length || b.faltan.length - a.faltan.length);
  }, [personas, fichas, derechos, conHijos]);

  // El valor que llega de la base es texto libre: puede traer un código que
  // estas etiquetas todavía no conocen. Se devuelve el crudo en vez de dejar
  // vacía la celda — un dato raro en el CSV se ve y se pregunta; una celda en
  // blanco se lee como «no tiene».
  function etiqueta(mapa: Record<string, string>, valor: string | null): string {
    if (valor === null || valor === "") return "";
    return mapa[valor] ?? valor;
  }

  /** El padrón para el contador. Solo dirección — ver `puedeExportarPadron`. */
  function exportarPadron() {
    const sede = (id: string) => sedes.get(id) ?? "";
    const filas = personas.map((p) => {
      const f = fichas.get(p.id);
      const dh = derechos.filter((d) => d.persona_id === p.id).length;
      return {
        DNI: p.documento ?? "",
        "Nombre segun DNI": f?.nombre_dni ?? `${p.apellidos}, ${p.nombres}`,
        Apellidos: p.apellidos, Nombres: p.nombres, Sede: sede(p.sede_base_id),
        "Fecha nacimiento": f?.fecha_nacimiento ?? "",
        "Estado civil": etiqueta(ESTADO_CIVIL_LABELS, f?.estado_civil ?? null),
        "Grado de instruccion": etiqueta(GRADO_INSTRUCCION_LABELS, f?.grado_instruccion ?? null),
        Celular: f?.celular ?? "", Correo: p.email ?? "", Direccion: f?.direccion ?? "",
        "Regimen pension": etiqueta(REGIMEN_PENSION_LABELS, p.regimen_pension),
        "CUSPP": f?.cuspp ?? "",
        // Tres estados, no dos. El ternario de antes —`f?.hijos_menores ? "SI"
        // : "NO"`— metía en el mismo saco el `false` declarado y el `null` de
        // una ficha que nadie llenó, así que este papel le AFIRMABA al contador
        // que la persona no tiene hijos menores cuando la verdad es que no se
        // sabe. Es la asignación familiar mensual, y el documento que lo
        // niega lo emite CAYLA. Ver `siNoSinDato`.
        "Asignacion familiar": siNoSinDato(f?.hijos_menores),
        Derechohabientes: dh,
        Banco: f?.entidad_bancaria ?? "", Cuenta: f?.numero_cuenta ?? "",
        Discapacidad: siNoSinDato(f?.discapacidad), CONADIS: f?.discapacidad_conadis ?? "",
        "Contacto emergencia": f?.emergencia_nombre ?? "",
        "Telefono emergencia": f?.emergencia_telefono ?? "",
        // Sexo ya se guarda (0369) y sale con el dato real. Nacionalidad el
        // sistema TODAVÍA no la guarda y el T-Registro la pide: va como columna
        // vacía y no omitida — una columna que falta se pasa por alto, una
        // vacía se ve y se llena.
        Sexo: etiqueta(GENERO_LABELS, f?.genero ?? null), Nacionalidad: "",
        REVISAR: incompletas.find((x) => x.p.id === p.id)?.faltan.join(" · ") ?? "",
      };
    });
    // Primero quien necesita corrección: el archivo abre mostrando qué hacer.
    filas.sort((a, b) => (a.REVISAR === "" ? 1 : 0) - (b.REVISAR === "" ? 1 : 0)
      || a.Sede.localeCompare(b.Sede) || a.Apellidos.localeCompare(b.Apellidos));
    descargarCsv(
      `cayla-padron-${new Date().toISOString().slice(0, 10)}.csv`,
      generarCsv(filas, Object.keys(filas[0] ?? {})),
    );
    avisar("ok", `Descargadas ${filas.length} fichas. Lleva DNI, dirección y cuentas bancarias: compártelo por un canal que puedas revocar y bórralo al terminar.`);
  }

  if (rol !== null && !puede) {
    return (
      <div className="flex flex-1 flex-col">
        <main className="flex flex-1 items-center justify-center p-6">
          <p className="max-w-md text-center text-taupe">No tienes permiso para ver datos personales.</p>
        </main>
      </div>
    );
  }

  function campo(label: string, key: keyof Form, tipo: "text" | "date" = "text") {
    return (
      <Campo
        etiqueta={label}
        type={tipo}
        value={form[key]}
        onChange={(e) => setForm((f) => ({ ...f, [key]: e.target.value }))}
      />
    );
  }
  /**
   * Campo de lista cerrada que NO descarta lo que ya estaba escrito.
   *
   * Las fichas anteriores tienen estado civil y grado de instrucción a mano. Si
   * el valor guardado no está en el catálogo, se añade al desplegable como
   * opción propia y marcada, en vez de aparecer vacío: un campo que se ve vacío
   * invita a guardarlo vacío, y ahí se pierde el dato de una persona real.
   *
   * Se queda con su propio <select> en vez de <CampoSelect>: necesita cambiar
   * SOLO el color del borde según `esAntiguo`, y CampoSelect ya trae
   * "border-sand" fijo en su base — dos clases de color de borde a la vez
   * (border-sand + border-ambar) es justo lo que `cx` NO fusiona (ver el
   * comentario de components/ui/cx.ts: solo fondo y texto, nunca borde), así
   * que cuál gana quedaría a la suerte del orden en que Tailwind generó su
   * hoja. Por eso el ternario deja una sola clase de borde a la vez, igual que
   * ya hacía este archivo — solo se corrige el fondo a `bg-hueso` (hallazgo de
   * esta pantalla) y el radio a `rounded-control`, para que se vea igual que
   * el resto de los controles aunque no sea el mismo componente.
   */
  function campoLista(label: string, key: keyof Form, opciones: readonly string[], etiquetas: Record<string, string>) {
    const actual = form[key] as string;
    const esAntiguo = actual !== "" && !opciones.includes(actual);
    return (
      <label className="flex flex-col gap-1">
        <span className="text-sm text-taupe">
          {label}
          {esAntiguo && <span className="ml-1 text-[11px] text-ambar">· valor antiguo, elige uno de la lista</span>}
        </span>
        <select value={actual} onChange={(e) => setForm((f) => ({ ...f, [key]: e.target.value }))}
          className={`rounded-control border ${esAntiguo ? "border-ambar" : "border-sand"} bg-hueso px-3 py-2 text-base text-tinta transition-colors duration-150 sm:text-sm`}>
          <option value="">—</option>
          {esAntiguo && <option value={actual}>{actual} (como estaba)</option>}
          {opciones.map((o) => (
            <option key={o} value={o}>{etiquetas[o] ?? o}</option>
          ))}
        </select>
      </label>
    );
  }
  function campoSiNo(label: string, key: "hijos_menores" | "discapacidad") {
    return (
      <CampoSelect
        etiqueta={label}
        value={form[key]}
        onChange={(e) => setForm((f) => ({ ...f, [key]: e.target.value as "" | "si" | "no" }))}
      >
        <option value="">—</option>
        <option value="si">Sí</option>
        <option value="no">No</option>
      </CampoSelect>
    );
  }

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        <div className="mb-1 flex flex-wrap items-baseline justify-between gap-3">
          <h1 className="font-serif text-2xl">Datos personales</h1>
          {/* Solo dirección: un CSV sale del sistema y ya nadie sabe dónde queda.
              Ver `puedeExportarPadron` para por qué esto es más estrecho que ver
              las mismas fichas en pantalla. */}
          {puedeExportarPadron(rol) && personas.length > 0 && (
            <Boton
              variante="secundario"
              tamano="sm"
              onClick={exportarPadron}
              className="no-print"
              title="Padrón completo para el contador: incluye DNI, dirección y cuentas bancarias"
            >
              Descargar padrón para el contador (CSV)
            </Boton>
          )}
        </div>
        <p className="mb-5 max-w-2xl text-sm text-taupe">
          Ficha personal de cada integrante: DNI, pensión, contacto y familia.
          Datos sensibles — visibles solo para Desarrollo Organizacional, la encargada de tu sede y cada persona sobre sí misma.
        </p>

        {/* ── Qué falta, arriba de todo ─────────────────────────────────────
            Solo se listan las fichas incompletas. Cuando estén todas al día
            este bloque desaparece, y esa ausencia ES la señal de que está
            cerrado — un contador «21 de 21» ocuparía sitio para no decir nada.
            Cada nombre lleva al formulario de esa persona: quien ve el hueco lo
            corrige sin cambiar de pantalla. */}
        {!cargando && incompletas.length > 0 && (
          <BannerAviso
            variante="advertencia"
            className="mb-5 max-w-3xl"
            titulo={
              incompletas.length === 1
                ? "Una ficha está incompleta"
                : `${incompletas.length} fichas están incompletas`
            }
          >
            <p className="mb-3 text-xs text-taupe">
              Son los datos que el contador necesita para el T-Registro. Sin ellos no se puede
              declarar a esa persona ni pagarle por transferencia.
            </p>
            <ul className="space-y-1.5 text-sm">
              {incompletas.map(({ p, faltan, avisos, sinFicha: nueva }) => (
                <li key={p.id}>
                  <div className="flex flex-wrap items-baseline gap-x-2">
                    <button
                      onClick={() => seleccionar(p.id, true)}
                      className="font-medium underline decoration-dotted underline-offset-2"
                    >
                      {p.apellidos}, {p.nombres}
                    </button>
                    {/* Los campos vacíos, en cadena. Si no hay ninguno no se
                        escribe «falta» a secas, que se lee como error. */}
                    {(nueva || faltan.length > 0) && (
                      <span className="text-xs text-taupe">
                        {nueva ? "sin ficha — falta todo" : `falta ${faltan.join(" · ")}`}
                      </span>
                    )}
                  </div>
                  {/* Las contradicciones van en su propia línea y con frase
                      completa: no son un campo vacío más, y la diferencia entre
                      «falta X» y «esto no cuadra» tiene que verse. */}
                  {avisos.map((a) => (
                    <p key={a} className="ml-0.5 mt-0.5 flex items-start gap-1 text-xs text-ambar">
                      <TriangleAlert size={14} strokeWidth={1.8} className="mt-0.5 shrink-0" aria-hidden />
                      {a}
                    </p>
                  ))}
                </li>
              ))}
            </ul>
          </BannerAviso>
        )}

        <div className="grid gap-6 md:grid-cols-[260px_1fr]">
          {/* Lista de personas */}
          <div className="overflow-hidden rounded-superficie border border-sand bg-papel">
            <div className="border-b bg-sand/50 px-3 py-2">
              <div className="flex items-baseline justify-between">
                <h2 className="text-sm font-medium">Equipo {personas.length > 0 && <span className="font-normal text-taupe">· {personas.length}</span>}</h2>
                {sinFicha > 0 && (
                  <button onClick={() => setSoloSinFicha((v) => !v)} aria-pressed={soloSinFicha}
                    className={`rounded-pildora px-2 py-0.5 text-xs transition-colors ${soloSinFicha ? "bg-ambar/25 text-ambar" : "text-ambar hover:bg-ambar/15"}`}>
                    {sinFicha} sin ficha
                  </button>
                )}
              </div>
              <div className="relative mt-2">
                <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar por nombre…"
                  className="w-full rounded-control border bg-crema px-3 py-1.5 pr-8 text-sm" />
                {q && (
                  <button onClick={() => setQ("")} aria-label="Limpiar búsqueda"
                    className="absolute right-2 top-1/2 -translate-y-1/2 leading-none text-taupe hover:text-tinta">×</button>
                )}
              </div>
            </div>
            {cargando ? (
              <Cargando />
            ) : lista.length === 0 ? (
              <p className="px-3 py-4 text-sm text-taupe">Nadie coincide con “{q}”.</p>
            ) : (
              <ul className="max-h-[70vh] divide-y overflow-y-auto">
                {lista.map((p) => (
                  <li key={p.id}>
                    <button onClick={() => seleccionar(p.id)}
                      className={`flex w-full items-center justify-between px-3 py-2 text-left text-sm ${sel === p.id ? "bg-sand/60 font-medium text-tinta" : "hover:bg-sand/30"}`}>
                      <span>{p.nombres} {p.apellidos}</span>
                      <span className="flex items-center gap-1 text-xs text-taupe">
                        {sedes.get(p.sede_base_id)}
                        {!fichas.has(p.id) && <Insignia variante="advertencia" tamano="sm">sin ficha</Insignia>}
                      </span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>

          {/* Ficha */}
          <div ref={fichaRef} className="scroll-mt-4 rounded-superficie border border-sand bg-papel p-5">
            {!personaSel ? (
              <p className="text-sm text-taupe">Elige a alguien de la lista para ver o editar su ficha.</p>
            ) : (
              <>
                <div className="mb-3 flex flex-wrap items-baseline justify-between gap-x-3">
                  <h2 className="font-serif text-lg">{personaSel.nombres} {personaSel.apellidos}</h2>
                  <div className="flex items-center gap-3 text-xs">
                    <span className="text-taupe">{sedes.get(personaSel.sede_base_id)}</span>
                    <Boton variante="enlace" className="text-tinta" onClick={() => router.push(`/admin/personas/${personaSel.id}`)}>Ver perfil →</Boton>
                  </div>
                </div>
                <div className="space-y-4">
                  <section>
                    <p className="mb-2 text-[11px] uppercase tracking-wider text-taupe">Identidad</p>
                    <div className="grid gap-3 sm:grid-cols-2">
                      {/* El DNI vive en `personas` y se guarda con su propia función,
                          porque se imprime en papeles legales y su cambio va a auditoría. */}
                      <label className="flex flex-col gap-1">
                        <span className="text-sm text-taupe">
                          Número de DNI
                          {!puedeIdentidad && <span className="ml-1 text-[11px]">· solo Desarrollo Organizacional</span>}
                        </span>
                        <input value={dni} disabled={!puedeIdentidad}
                          onChange={(e) => setDni(e.target.value)}
                          className={`rounded-control border ${dniCambio ? "border-ambar" : "border-sand"} bg-hueso px-3 py-2 text-base text-tinta transition-colors duration-150 disabled:bg-sand/30 disabled:text-taupe sm:text-sm`} />
                      </label>
                      {campo("Nombre completo (como en el DNI)", "nombre_dni")}
                      {dniEsCorreccion && (
                        <label className="flex flex-col gap-1 text-sm sm:col-span-2">
                          <span className="text-ambar">
                            Motivo del cambio de DNI (obligatorio) — de {personaSel.documento} a {dni.trim()}
                          </span>
                          <input value={motivoDni} onChange={(e) => setMotivoDni(e.target.value)}
                            placeholder="Por ejemplo: corregido contra la constancia de alta del T-Registro"
                            className="rounded-control border border-ambar bg-hueso px-3 py-2 text-base text-tinta transition-colors duration-150 sm:text-sm" />
                          <span className="text-[11px] text-taupe">
                            Este número se imprime en los memos disciplinarios y en los documentos de respaldo, así que el cambio queda registrado con su motivo.
                          </span>
                        </label>
                      )}
                      {campo("Fecha de nacimiento", "fecha_nacimiento", "date")}
                      {campoLista("Género", "genero", GENEROS, GENERO_LABELS)}
                      {campoLista("Estado civil", "estado_civil", ESTADOS_CIVILES, ESTADO_CIVIL_LABELS)}
                      {campoLista("Grado de instrucción", "grado_instruccion", GRADOS_INSTRUCCION, GRADO_INSTRUCCION_LABELS)}
                      {campoSiNo("¿Hijos menores a cargo?", "hijos_menores")}
                    </div>
                  </section>

                  {/* CAMBIO 0125 — El régimen decide la tasa que se le descuenta. */}
                  <section>
                    <p className="mb-2 text-[11px] uppercase tracking-wider text-taupe">Pensión</p>
                    <div className="grid gap-3 sm:grid-cols-2">
                      <label className="flex flex-col gap-1">
                        <span className="text-sm text-taupe">
                          Sistema de pensiones
                          {!puedeIdentidad && <span className="ml-1 text-[11px]">· solo Desarrollo Organizacional</span>}
                        </span>
                        <select value={regimen} disabled={!puedeIdentidad}
                          onChange={(e) => setRegimen(e.target.value)}
                          className={`rounded-control border ${regimenCambio ? "border-ambar" : "border-sand"} bg-hueso px-3 py-2 text-base text-tinta transition-colors duration-150 disabled:bg-sand/30 disabled:text-taupe sm:text-sm`}>
                          <option value="">— todavía no se sabe</option>
                          {REGIMENES_PENSION.map((r) => (
                            <option key={r} value={r}>{REGIMEN_PENSION_LABELS[r]}</option>
                          ))}
                        </select>
                      </label>
                      {/* CAMBIO 0328 — Dos correcciones en tres líneas de texto.
                          La primera: decía que sin régimen «se le descuenta la
                          tasa genérica del 13 %», y no es cierto desde la 0115.
                          El interruptor global `configuracion.tasa_afp` vale 0 a
                          propósito, así que a quien no tiene régimen NO se le
                          descuenta NADA. Decir 13 % hacía que un dato faltante
                          pareciera un dato razonable, y por eso podía quedarse
                          años sin llenar sin que nadie sintiera urgencia.
                          La segunda: se nombra el esquema de comisión, porque es
                          lo que se venía eligiendo sin saber que se elegía. */}
                      <p className="self-end text-[11px] text-taupe">
                        {regimen === ""
                          ? "Mientras esté vacío NO se le descuenta pensión: ni AFP ni ONP. No es un descuento genérico, es cero. Hay que poner el verdadero — sale en su boleta y lo declara el contador."
                          : "Se descuenta de su remuneración asegurable y va a su fondo de pensión — no se queda en CAYLA."}
                      </p>
                      {/* La comisión mixta es el caso normal y hasta la 0328 no se
                          podía ni elegir: quien se afilió al SPP desde 2013 entró
                          a mixta obligatoriamente. Elegir el esquema equivocado no
                          da error en ninguna pantalla — solo retiene de más o de
                          menos cada mes, así que la única defensa es que quien
                          llena la ficha sepa dónde se comprueba. */}
                      {regimen.endsWith("_mixta") || ["profuturo", "prima", "integra", "habitat"].includes(regimen) ? (
                        <p className="self-end text-[11px] text-taupe sm:col-span-2">
                          <b>Mixta o sobre flujo</b> no se adivina por la AFP: es cómo cobra su comisión.
                          En <b>mixta</b> no cobra nada del sueldo (se retiene 11.37 %) y se cobra contra el
                          fondo; en <b>flujo</b> la cobra del sueldo. Quien se afilió desde 2013 está en
                          mixta. Se confirma en AFPnet o en el estado de cuenta de la persona.
                        </p>
                      ) : null}
                      {/* CAMBIO 0277 — La fecha solo aparece cuando hay algo que
                          fechar. Un campo permanente pediría una decisión en cada
                          guardado de ficha, y la mayoría de los guardados no
                          tocan el régimen. */}
                      {regimenCambio && (
                        <label className="flex flex-col gap-1 text-sm sm:col-span-2">
                          <span className="text-taupe">Rige desde</span>
                          <input type="date" value={regimenDesde} disabled={!puedeIdentidad}
                            onChange={(e) => setRegimenDesde(e.target.value)}
                            className="rounded-control border border-ambar bg-hueso px-3 py-2 text-base text-tinta transition-colors duration-150 disabled:bg-sand/30 disabled:text-taupe sm:text-sm" />
                          <span className="text-[11px] text-ambar">
                            {periodoAbiertoIni
                              ? `El descuento cambia desde esta fecha, y queda registrado quién lo cambió. Viene puesta la del periodo abierto (${periodoAbiertoIni}); si eliges una de un periodo ya pagado, la base la rechaza — ese mes ya se pagó con el régimen anterior.`
                              : "No se pudo leer cuál es el periodo abierto, así que hay que escribir la fecha. Tiene que caer fuera de todo periodo ya pagado."}
                          </span>
                        </label>
                      )}
                      {/* El CUSPP solo existe en el sistema PRIVADO: identifica
                          la cuenta individual en la AFP. En ONP no hay cuenta
                          individual, y quien ya se jubiló no aporta. Pedírselo
                          a Raquel sería pedirle un código que no existe — y un
                          campo que no aplica enseña a ignorar los que sí. */}
                      {mostrarCuspp && (
                        <div className="flex flex-col gap-1 sm:col-span-2">
                          <Campo
                            etiqueta="CUSPP · código de su cuenta en la AFP"
                            value={form.cuspp}
                            onChange={(e) => setForm((f) => ({ ...f, cuspp: e.target.value }))}
                            placeholder="Sale en su estado de cuenta o en la app de su AFP"
                            className="font-mono uppercase"
                          />
                          <span className="text-xs text-taupe">
                            {esAfp
                              ? "Obligatorio en el T-Registro. Sin él, el aporte se declara pero puede no llegar a su cuenta."
                              : "Esta persona no está en planilla, así que CAYLA no declara su aporte. El código queda visible para poder corregirlo o borrarlo."}
                          </span>
                        </div>
                      )}
                    </div>
                  </section>

                  <section>
                    <p className="mb-2 text-[11px] uppercase tracking-wider text-taupe">Contacto</p>
                    <div className="grid gap-3 sm:grid-cols-2">
                      {campo("Celular", "celular")}
                      {/* El correo vive en `personas`, no en la ficha, porque es
                          el USUARIO con el que se entra al sistema. Con cuenta
                          creada queda de solo lectura: la 0198 rechaza el cambio
                          en la base, y una caja que acepta texto para después
                          fallar al guardar es peor que una que no deja escribir. */}
                      <div className="flex flex-col gap-1">
                        <span id="campo-correo-label" className="text-sm text-taupe">
                          Correo
                          {tieneCuenta && <span className="ml-1 text-[11px]">· es su usuario para entrar</span>}
                        </span>
                        {/* Sin `etiqueta`: la nota condicional de arriba no es
                            texto plano, y el mensaje de abajo tampoco cabe en
                            el `error` de Campo (no es un error). Se asocia por
                            aria-labelledby en vez de anidar un <label> dentro
                            del que ya trae Campo. */}
                        <Campo
                          aria-labelledby="campo-correo-label"
                          type="email"
                          value={email}
                          onChange={(e) => setEmail(e.target.value)}
                          disabled={!puedeIdentidad || tieneCuenta}
                          placeholder="nombre@correo.com"
                          className="disabled:bg-sand/30 disabled:text-taupe"
                        />
                        {tieneCuenta ? (
                          <span className="text-xs text-taupe">
                            Ya tiene cuenta activa. Cambiarlo acá no cambiaría su acceso —{" "}
                            <a href="/admin/cuentas" className="underline">hazlo desde Cuentas</a>.
                          </span>
                        ) : puedeIdentidad ? (
                          <span className="text-xs text-taupe">
                            Todavía no tiene cuenta. Con el correo cargado se le puede invitar desde Cuentas.
                          </span>
                        ) : null}
                      </div>
                      <div className="sm:col-span-2">
                        <Campo etiqueta="Dirección" value={form.direccion}
                          onChange={(e) => setForm((f) => ({ ...f, direccion: e.target.value }))} />
                      </div>
                    </div>
                  </section>

                  {/* CAMBIO 0125 — A quién llamar si pasa algo. */}
                  <section>
                    <p className="mb-2 text-[11px] uppercase tracking-wider text-taupe">Contacto de emergencia</p>
                    <div className="grid gap-3 sm:grid-cols-3">
                      {campo("Nombre", "emergencia_nombre")}
                      {campo("Vínculo", "emergencia_vinculo")}
                      {campo("Teléfono", "emergencia_telefono")}
                    </div>
                  </section>

                  {/* CAMBIO 0125 — Familiares: EsSalud y Seguro de Vida Ley. */}
                  <section>
                    <div className="mb-2 flex items-baseline justify-between">
                      <p className="text-[11px] uppercase tracking-wider text-taupe">
                        Familiares {misDerechos.length > 0 && <span className="normal-case">· {misDerechos.filter((d) => !d.vigente_hasta).length} vigentes</span>}
                      </p>
                      {/* Siempre abre EN BLANCO. Sin el reset, pulsarlo después de
                          haber estado editando a alguien dejaba sus datos cargados y
                          el próximo «Guardar» pisaba a esa persona en vez de crear
                          un familiar nuevo. */}
                      <Boton
                        variante="enlace"
                        className="text-xs text-tinta"
                        onClick={() => {
                          if (dhAbierto) { setDhAbierto(false); setDhEditando(null); setDhNuevo(crearDhVacio()); }
                          else { setDhEditando(null); setDhNuevo(crearDhVacio()); setDhAbierto(true); }
                        }}
                      >
                        {dhAbierto ? "Cancelar" : "+ Agregar familiar"}
                      </Boton>
                    </div>
                    <p className="mb-2 text-[11px] text-taupe">
                      Dos cosas distintas: <strong>EsSalud</strong> es quien está inscrito ante SUNAT y puede atenderse;
                      <strong> Vida Ley</strong> es a quién le paga la aseguradora si la persona fallece. Sin esa declaración el pago va a un juzgado.
                    </p>

                    {misDerechos.length === 0 ? (
                      <p className="text-sm text-taupe">Sin familiares registrados.</p>
                    ) : (
                      <ul className="divide-y rounded-control border border-sand">
                        {misDerechos.map((d) => (
                          <li key={d.id} className={`flex flex-wrap items-center justify-between gap-2 px-3 py-2 text-sm ${d.vigente_hasta ? "text-taupe" : ""}`}>
                            <span>
                              {d.nombres} {d.apellidos}
                              <span className="ml-2 text-xs text-taupe">
                                {VINCULO_DERECHOHABIENTE_LABELS[d.vinculo as keyof typeof VINCULO_DERECHOHABIENTE_LABELS] ?? d.vinculo}
                                {d.documento && ` · DNI ${d.documento}`}
                                {d.fecha_nacimiento && ` · ${d.fecha_nacimiento}`}
                              </span>
                            </span>
                            <span className="flex items-center gap-2 text-xs">
                              {/* punto={false}: son atributos, no un estado — mismo
                                  criterio que ya usa la vista de autoservicio
                                  (mio/editar) para este mismo par de campos. */}
                              {d.essalud && <Insignia variante="neutral" punto={false}>EsSalud</Insignia>}
                              {d.vida_ley && <Insignia variante="neutral" punto={false}>Vida Ley</Insignia>}
                              {d.vigente_hasta
                                ? <span className="text-taupe">cerrado el {d.vigente_hasta}</span>
                                : <>
                                    {/* Antes solo se podía CERRAR. Un typo en el nombre o el
                                        DNI obligaba a cerrar el registro —dejándolo con los
                                        datos malos para siempre, porque no se borra— y crear
                                        otro. La base ya aceptaba corregir: faltaba el botón. */}
                                    <Boton variante="enlace" tamano="sm" disabled={guardando}
                                      onClick={() => editarDerechohabiente(d)}>editar</Boton>
                                    <Boton variante="peligro" tamano="sm" disabled={guardando}
                                      onClick={() => setConfirmarCierre({ id: d.id, nombre: `${d.nombres} ${d.apellidos}` })}>cerrar</Boton>
                                  </>}
                            </span>
                          </li>
                        ))}
                      </ul>
                    )}

                    {dhAbierto && (
                      <div className="mt-3 rounded-control border border-sand bg-crema/50 p-3">
                        <div className="grid gap-3 sm:grid-cols-2">
                          <Campo etiqueta="Nombres" value={dhNuevo.nombres}
                            onChange={(e) => setDhNuevo((d) => ({ ...d, nombres: e.target.value }))} />
                          <Campo etiqueta="Apellidos" value={dhNuevo.apellidos}
                            onChange={(e) => setDhNuevo((d) => ({ ...d, apellidos: e.target.value }))} />
                          <CampoSelect etiqueta="Vínculo" value={dhNuevo.vinculo}
                            onChange={(e) => setDhNuevo((d) => ({ ...d, vinculo: e.target.value }))}>
                            {VINCULOS_DERECHOHABIENTE.map((v) => (
                              <option key={v} value={v}>{VINCULO_DERECHOHABIENTE_LABELS[v]}</option>
                            ))}
                          </CampoSelect>
                          <div className="flex flex-col gap-1">
                            <span id="campo-dh-documento-label" className="text-sm text-taupe">
                              DNI <span className="text-[11px]">(puede faltar en un recién nacido)</span>
                            </span>
                            <Campo aria-labelledby="campo-dh-documento-label" value={dhNuevo.documento}
                              onChange={(e) => setDhNuevo((d) => ({ ...d, documento: e.target.value }))} />
                          </div>
                          <div className="flex flex-col gap-1">
                            <span id="campo-dh-nacimiento-label" className="text-sm text-taupe">
                              Fecha de nacimiento
                              {dhNuevo.vinculo === "hijo" && <span className="ml-1 text-[11px] text-ambar">· obligatoria</span>}
                            </span>
                            <Campo aria-labelledby="campo-dh-nacimiento-label" type="date" value={dhNuevo.fecha_nacimiento}
                              onChange={(e) => setDhNuevo((d) => ({ ...d, fecha_nacimiento: e.target.value }))} />
                          </div>
                          <div className="flex flex-col gap-2 text-sm sm:self-end">
                            <label className="flex items-center gap-2">
                              <input type="checkbox" checked={dhNuevo.essalud} onChange={(e) => setDhNuevo((d) => ({ ...d, essalud: e.target.checked }))} className="size-4 accent-tinta" />
                              <span>Inscrito en EsSalud</span>
                            </label>
                            <label className="flex items-center gap-2">
                              <input type="checkbox" checked={dhNuevo.vida_ley} onChange={(e) => setDhNuevo((d) => ({ ...d, vida_ley: e.target.checked }))} className="size-4 accent-tinta" />
                              <span>Beneficiario de Vida Ley</span>
                            </label>
                          </div>
                        </div>
                        <div className="mt-3 flex items-center gap-3">
                          <Boton variante="primario" cargando={guardando} onClick={() => void agregarDerechohabiente()}>
                            {dhEditando ? "Guardar cambios" : "Agregar"}
                          </Boton>
                          {/* Cancelar solo al editar: al crear, el propio botón de
                              «Agregar familiar» cierra el formulario, y dos formas de
                              cerrar lo mismo confunden más de lo que ayudan. */}
                          {dhEditando && (
                            <Boton variante="enlace" className="text-taupe" disabled={guardando}
                              onClick={() => { setDhAbierto(false); setDhEditando(null); setDhNuevo(crearDhVacio()); }}>
                              Cancelar
                            </Boton>
                          )}
                        </div>
                      </div>
                    )}
                  </section>

                  <section>
                    <p className="mb-2 text-[11px] uppercase tracking-wider text-taupe">Banco</p>
                    <div className="grid gap-3 sm:grid-cols-2">
                      {campo("Entidad bancaria", "entidad_bancaria")}
                      {campo("N.° de cuenta", "numero_cuenta")}
                    </div>
                  </section>

                  {/* CAMBIO 0125 — El T-Registro lo pregunta, y la deducción de la
                      Ley 29973 exige el certificado del CONADIS, no la declaración. */}
                  <section>
                    <p className="mb-2 text-[11px] uppercase tracking-wider text-taupe">Discapacidad</p>
                    <div className="grid gap-3 sm:grid-cols-2">
                      {campoSiNo("¿Persona con discapacidad?", "discapacidad")}
                      {form.discapacidad === "si" && campo("N.° de certificado CONADIS", "discapacidad_conadis")}
                    </div>
                  </section>
                </div>
                <Boton
                  variante="primario"
                  tamano="lg"
                  cargando={guardando}
                  disabled={cargaFallida}
                  onClick={guardar}
                  className="mt-4"
                >
                  Guardar ficha
                </Boton>
              </>
            )}
          </div>
        </div>

        {/* Reemplaza al `window.confirm` nativo — Felipe aprobó migrar todos
            los diálogos del panel al Modal compartido (ver CLAUDE.md). No
            cambia qué función se llama al confirmar: sigue siendo
            `cerrarDerechohabiente`, solo cambia cómo se pregunta. */}
        <Modal
          abierto={confirmarCierre !== null}
          onCerrar={() => setConfirmarCierre(null)}
          titulo="Cerrar a este familiar"
          ancho="sm"
          bloqueado={guardando}
        >
          <p className="mb-4 text-sm text-taupe">
            ¿Cerrar a {confirmarCierre?.nombre}? No se borra: queda registrado hasta hoy, así que
            el periodo en que estuvo cubierto sigue explicándose.
          </p>
          <div className="flex justify-end gap-2">
            <Boton variante="secundario" tamano="sm" disabled={guardando} onClick={() => setConfirmarCierre(null)}>
              Cancelar
            </Boton>
            <Boton
              variante="peligro"
              tamano="sm"
              cargando={guardando}
              onClick={() => confirmarCierre && void cerrarDerechohabiente(confirmarCierre.id, confirmarCierre.nombre)}
            >
              Sí, cerrar
            </Boton>
          </div>
        </Modal>
      </main>
    </div>
  );
}

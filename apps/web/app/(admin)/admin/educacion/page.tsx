"use client";

import { Fragment, useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Cargando } from "@/components/cargando";
import { useRolActual } from "@/lib/admin/use-rol";
import { useFiltroGuardado } from "@/lib/admin/use-filtro-guardado";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { useToast } from "@/components/toast";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import { abrirArchivoFirmado } from "@/lib/abrir-archivo-firmado";
import { hoyLima, puedeVerPlanilla } from "@cayla-dynamic/shared";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { Insignia } from "@/components/ui/insignia";
import { Modal } from "@/components/ui/modal";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
// "Fila" ya nombra acá la interfaz de una fila de la tabla (línea 20): el
// componente de fila de la tabla compartida entra con alias para no chocar.
import { Tabla, TablaEncabezado, Th, Fila as FilaTabla } from "@/components/ui/tabla";

// La asignación por educación (art. 19 f) D.S. 001-97-TR) no es remuneración
// SIEMPRE QUE esté sostenida por un comprobante. Por eso esta pantalla no deja
// registrar un monto suelto: el comprobante y el costo declarado son parte del
// mismo acto, no un adjunto que se sube después "cuando se pueda".

interface Fila {
  id: string;
  persona_id: string;
  persona: string;
  sede: string;
  rango: string;
  monto: number;
  institucion: string;
  costo_declarado: number;
  cobertura_pct: number;
  beneficiario: "trabajador" | "hijo";
  beneficiario_nombre: string | null;
  comprobante_url: string | null;
  vigente_desde: string;
  // Desde la 0149 nunca es null: toda asignación dice hasta cuándo vale.
  vigente_hasta: string;
  nota: string | null;
  registrada_por: string | null;
  dias_para_vencer: number;
  // Lo calcula la base y no la pantalla: la misma pregunta la hace el contador
  // del menú, y tres copias de "cuándo vence" es como empiezan a discrepar.
  semaforo: "sin_comprobante" | "vencida" | "por_vencer" | "vigente";
  // Lo que de verdad decide si esta fila entra en la planilla.
  paga: boolean;
  // Desde la 0290: cuántos papeles tiene colgados, y cuántos de los meses que ya
  // cobró siguen sin uno. Los meses que no han llegado no cuentan.
  papeles: number;
  meses_sin_papel: number;
}

interface Papel {
  id: string;
  storage_path: string;
  mes_cubierto: string;
  nota: string | null;
  subido_por: string;
  created_at: string;
}

interface Candidato {
  persona_id: string;
  persona: string;
  sede: string;
  rango: string;
  tope: number | null;
}

// Igual criterio que Equipo, Planilla y Ausencias: "activos" no es el estado
// literal de la persona — incluye también a quien cesó pero todavía no se le
// liquida (0421/0422), porque sus comprobantes de estudios ya cargados pueden
// seguir necesitando revisión hasta ese momento.
type FiltroPersonaEstado = "activos" | "inactivos" | "todos";
interface PersonaFacts { fechaCese: string | null; liquidada: boolean }

// Ni `monto` ni `coberturaPct`: el primero lo calcula la base y el segundo es
// 75 % fijo desde la 0149. Pedirlos era pedirle a DO que hiciera una cuenta que
// el sistema ya sabe hacer — y el primer error de cuenta llegaba el primer mes.
interface Form {
  personaId: string;
  institucion: string;
  costoDeclarado: string;
  beneficiario: "trabajador" | "hijo";
  beneficiarioNombre: string;
  vigenteDesde: string;
  vigenteHasta: string;
  nota: string;
  motivo: string;
}

const COBERTURA = 75;

const FORM_VACIO: Form = {
  personaId: "", institucion: "", costoDeclarado: "",
  beneficiario: "trabajador", beneficiarioNombre: "",
  vigenteDesde: "", vigenteHasta: "", nota: "", motivo: "",
};

// Ni el tamaño máximo ni los formatos se escriben acá: los aplica el bucket, así
// que se le preguntan (fn_educacion_limite_comprobante, 0154). Tener la copia
// hacía posible que la pantalla dijera «máximo 50 MB» mientras la base rechazaba
// a los 10, y el error que devuelve storage no habla de tamaño — nadie sabría
// por dónde mirar. Estos valores son solo el respaldo por si la consulta falla.
const LIMITE_RESPALDO = { bytes: 10 * 1024 * 1024, tipos: "image/jpeg,image/png,image/heic,image/webp,application/pdf" };

const mb = (bytes: number) => `${Math.round(bytes / 1048576)} MB`;

const soles = (n: number) =>
  `S/ ${n.toLocaleString("es-PE", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

// "2026-08-04" → "04/08/2026". Aritmética de string: la fecha ya viene como día
// de Lima desde la base, así que construir un Date solo podría estropearla.
const fmtFecha = (iso: string) => { const [y, m, d] = iso.split("-"); return `${d}/${m}/${y}`; };

const MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio",
               "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"];

// "2026-07-01" → "julio 2026". Por la misma razón que fmtFecha: con un Date, un
// primero de mes se puede convertir en el último del anterior según el huso.
const nombreMes = (iso: string) => { const [y, m] = iso.split("-"); return `${MESES[Number(m) - 1]} ${y}`; };

export default function EducacionPage() {
  const router = useRouter();
  const rol = useRolActual();
  const puedeGestionar = puedeVerPlanilla(rol);
  const { avisar } = useToast();

  const [filas, setFilas] = useState<Fila[]>([]);
  const [candidatos, setCandidatos] = useState<Candidato[]>([]);
  const [cargando, setCargando] = useState(true);
  const [cargaError, setCargaError] = useState<string | null>(null);

  const [mostrandoAlta, setMostrandoAlta] = useState(false);
  const [editandoId, setEditandoId] = useState<string | null>(null);
  const [form, setForm] = useState<Form>(FORM_VACIO);
  const [archivo, setArchivo] = useState<File | null>(null);
  const [guardando, setGuardando] = useState(false);
  const [limite, setLimite] = useState(LIMITE_RESPALDO);
  // Cuánto techo le queda libre a esa persona EN LAS FECHAS del formulario.
  // `undefined` = todavía no lo sé · `null` = su rango no tiene techo cargado.
  const [saldo, setSaldo] = useState<number | null | undefined>(undefined);
  // null = no hay subida en curso. 0–100 = porcentaje real, no una animación:
  // un PDF de 40 MB desde la conexión de una tienda tarda minutos, y sin esto la
  // pantalla se ve colgada y alguien la recarga a mitad de camino.
  const [progreso, setProgreso] = useState<number | null>(null);
  const [verSoloVigentes, setVerSoloVigentes] = useState(true);
  const [filtroPersona, setFiltroPersona] = useFiltroGuardado<FiltroPersonaEstado>("educacion.persona_estado", "activos");
  const [personaFacts, setPersonaFacts] = useState<Map<string, PersonaFacts>>(new Map());
  // El detalle de papeles de UNA fila, abierto bajo ella. null = ninguna abierta.
  const [papelesDe, setPapelesDe] = useState<{ fila: Fila; papeles: Papel[]; faltan: string[] } | null>(null);
  const [adjuntando, setAdjuntando] = useState<string | null>(null);

  // Los dos diálogos nativos de esta pantalla (window.prompt para el motivo de
  // quitar un comprobante, y para hasta cuándo cerrar una asignación) pasan al
  // <Modal> compartido — Felipe aprobó migrar todos los diálogos nativos del
  // panel (ver CLAUDE.md). Ninguna de las dos funciones que se llaman cambia.
  const [quitando, setQuitando] = useState<{ fila: Fila; papel: Papel } | null>(null);
  const [motivoQuitar, setMotivoQuitar] = useState("");
  const [quitandoGuardando, setQuitandoGuardando] = useState(false);
  const [cerrando, setCerrando] = useState<Fila | null>(null);
  // Nace con hoy, nunca en "": un campo de fecha que bloquea el envío no puede
  // arrancar vacío (ver CLAUDE.md, 2026-08-26) — es la misma fecha que el
  // window.prompt anterior sugería por defecto.
  const [hastaCierre, setHastaCierre] = useState("");
  const [cerrandoGuardando, setCerrandoGuardando] = useState(false);

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }

    const [lista, cands, lim, pf] = await Promise.all([
      supabase.rpc("fn_educacion_listar"),
      supabase.rpc("fn_educacion_candidatos"),
      supabase.rpc("fn_educacion_limite_comprobante"),
      supabase.rpc("fn_personas_funciones"),
    ]);
    setFilas((lista.data as Fila[]) ?? []);
    setCandidatos((cands.data as Candidato[]) ?? []);
    // Quién ya se liquidó, para el filtro "activos" de abajo (0421/0422). Si
    // falla, no se oculta a nadie — más seguro que ocultar de más.
    setPersonaFacts(new Map(
      ((pf.data as { persona_id: string; fecha_cese: string | null; liquidada: boolean }[] | null) ?? [])
        .map((f) => [f.persona_id, { fechaCese: f.fecha_cese, liquidada: f.liquidada }] as const),
    ));
    // Si la consulta del límite falla se sigue con el respaldo: no poder leer
    // cuánto cabe no es razón para dejar a DO sin la pantalla entera.
    const l = (lim.data as { limite_bytes: number; tipos: string[] }[] | null)?.[0];
    if (l) setLimite({ bytes: Number(l.limite_bytes), tipos: l.tipos.join(",") });
    setCargaError(lista.error?.message ?? cands.error?.message ?? null);
    setCargando(false);
  }, [router]);

  useEffect(() => { void cargar(); }, [cargar]);

  const candidato = useMemo(
    () => candidatos.find((c) => c.persona_id === form.personaId) ?? null,
    [candidatos, form.personaId],
  );

  // El saldo se le PREGUNTA a la base, no se calcula acá. Desde la 0281 el techo
  // del rango se reparte entre las asignaciones que se solapan, así que depende
  // de qué otras filas tenga esa persona en esas fechas — y una segunda copia de
  // esa cuenta en TypeScript es cómo se fabrican las dos cifras que discrepan.
  //
  // Antes esta pantalla mostraba el monto contra el tope BRUTO del rango: a quien
  // ya tenía un estudio vigente le prometía una cifra que la base iba a rechazar.
  useEffect(() => {
    const persona = form.personaId;
    const desde = form.vigenteDesde;
    if (!persona || !desde) { setSaldo(undefined); return; }

    let vigente = true;
    const supabase = createAdminSupabaseClient();
    void supabase
      .rpc("fn_educacion_saldo", {
        p_persona_id: persona,
        p_desde: desde,
        // Sin fecha de fin todavía, se pregunta por ese único día: es el tramo
        // más corto posible, así que nunca promete más techo del que habrá.
        p_hasta: form.vigenteHasta || desde,
        p_excluir: editandoId,
      })
      .then(({ data, error }) => {
        if (!vigente) return;
        setSaldo(error ? undefined : (data as number | null));
      });
    return () => { vigente = false; };
  }, [form.personaId, form.vigenteDesde, form.vigenteHasta, editandoId]);

  // El monto sale de la misma cuenta que hace `fn_educacion_monto` en la base:
  // min(75 % del comprobante, techo que queda libre). Se muestra MIENTRAS se
  // escribe para que la cifra no aparezca por sorpresa al guardar. Si mañana
  // cambia la regla, cambia en la base y esta pantalla queda mostrando otra cosa
  // — por eso el guardado no confía en este número: lo recalcula la función.
  const costo = Number(form.costoDeclarado) || 0;
  const delPapel = costo > 0 ? Math.round(costo * COBERTURA) / 100 : null;
  // Mientras el saldo no ha llegado se usa el tope del rango, que es su límite
  // superior: se puede quedar corto de información, nunca prometer de más.
  const techoLibre = saldo !== undefined ? saldo : (candidato?.tope ?? null);
  const monto = delPapel === null ? 0
    : techoLibre === null ? delPapel
    : Math.min(delPapel, techoLibre);
  const mandaElTecho = delPapel !== null && techoLibre !== null && techoLibre < delPapel;
  // El techo ya lo está usando otro estudio de la misma persona.
  const techoCompartido =
    candidato?.tope != null && saldo != null && saldo < candidato.tope;

  function empezarAlta() {
    setMostrandoAlta(true); setEditandoId(null); setArchivo(null);
    // `vigenteHasta` también nace con la fecha de inicio, no en "" — es
    // obligatoria (ver guardar()), y un campo de fecha bloqueante que arranca
    // vacío es exactamente el bug que costó cinco despliegues el 2026-08-26
    // (CLAUDE.md): Safari puede pintar un valor en el input sin disparar el
    // evento que React escucha, dejando el estado en "" mientras la pantalla
    // ya muestra una fecha. Queda visible y editable en un clic para que la
    // persona la extienda al fin real del ciclo/matrícula.
    const inicioMes = hoyLima().slice(0, 8) + "01";
    setForm({ ...FORM_VACIO, vigenteDesde: inicioMes, vigenteHasta: inicioMes });
  }
  function empezarEdicion(f: Fila) {
    setEditandoId(f.id); setMostrandoAlta(false); setArchivo(null);
    setForm({
      personaId: f.persona_id, institucion: f.institucion,
      costoDeclarado: String(f.costo_declarado),
      beneficiario: f.beneficiario, beneficiarioNombre: f.beneficiario_nombre ?? "",
      vigenteDesde: f.vigente_desde, vigenteHasta: f.vigente_hasta,
      nota: f.nota ?? "", motivo: "",
    });
  }
  function cancelar() { setMostrandoAlta(false); setEditandoId(null); setForm(FORM_VACIO); setArchivo(null); }

  function elegirArchivo(f: File | null) {
    if (f && f.size > limite.bytes) {
      avisar("error", `“${f.name}” pesa ${(f.size / 1048576).toFixed(1)} MB y el máximo es ${mb(limite.bytes)}. Si es una foto, vuelve a tomarla en menor calidad.`);
      return;
    }
    setArchivo(f);
  }

  async function guardar() {
    const institucion = form.institucion.trim();
    if (!form.personaId) { avisar("error", "Elige de quién es la asignación."); return; }
    if (institucion.length < 3) { avisar("error", "Escribe qué institución emite el comprobante."); return; }
    if (costo <= 0) { avisar("error", "El costo que dice el comprobante tiene que ser mayor que cero."); return; }
    if (monto <= 0) {
      avisar("error", "No queda techo libre en esas fechas: lo que ya tiene vigente agota el tope de su rango. Cierra o acorta la otra asignación, o mueve estas fechas.");
      return;
    }
    if (form.beneficiario === "hijo" && form.beneficiarioNombre.trim().length < 3) {
      avisar("error", "Si el comprobante es de un hijo o hija, escribe a nombre de quién está. Sin eso, el papel no se puede atar a quien cobra.");
      return;
    }
    if (!form.vigenteDesde) { avisar("error", "Indica desde cuándo se paga."); return; }
    if (!form.vigenteHasta) { avisar("error", "Indica hasta cuándo vale el comprobante. Una matrícula cubre un ciclo, no la eternidad."); return; }
    if (form.vigenteHasta < form.vigenteDesde) { avisar("error", "La fecha de fin es anterior a la de inicio."); return; }
    if (editandoId && form.motivo.trim().length < 3) {
      avisar("error", "Escribe por qué se corrige. Esto mueve lo que cobra una persona, y queda registrado.");
      return;
    }

    setGuardando(true);
    const supabase = createAdminSupabaseClient();

    // 1) La fila primero: da el id con el que se nombra el archivo, y si algo
    //    falla aquí no queda un archivo huérfano en el bucket.
    // El monto NO viaja: lo calcula la función. Mandarlo desde acá abriría la
    // puerta a que dos versiones de la misma cuenta discrepen.
    const { data: id, error } = await supabase.rpc("fn_educacion_registrar", {
      p_persona_id: form.personaId,
      p_institucion: institucion,
      p_costo_declarado: costo,
      p_beneficiario: form.beneficiario,
      p_vigente_desde: form.vigenteDesde,
      p_vigente_hasta: form.vigenteHasta,
      p_beneficiario_nombre: form.beneficiarioNombre.trim() || null,
      p_nota: form.nota.trim() || null,
      p_id: editandoId,
      p_motivo: form.motivo.trim() || null,
    });
    if (error) { setGuardando(false); avisar("error", mensajeDeError(error, "guardar")); return; }

    // 2) El comprobante, si se eligió uno.
    if (archivo) {
      const ext = archivo.name.split(".").pop()?.toLowerCase() ?? "bin";
      const ruta = `educacion/${form.personaId}/${id}.${ext}`;
      setProgreso(0);
      const errorSubida = await subirArchivoConProgreso(supabase, "comprobantes", ruta, archivo, setProgreso);
      setProgreso(null);
      if (errorSubida) {
        setGuardando(false);
        avisar("error", `La asignación se guardó, pero el comprobante no subió (${errorSubida}). Ábrela con “Editar” y vuelve a intentarlo — sin el papel, el monto no está sustentado.`);
        await cargar();
        return;
      }
      // 3) Enlazar el archivo a la fila.
      const { error: e3 } = await supabase.rpc("fn_educacion_registrar", {
        p_persona_id: form.personaId, p_institucion: institucion,
        p_costo_declarado: costo, p_beneficiario: form.beneficiario,
        p_vigente_desde: form.vigenteDesde, p_vigente_hasta: form.vigenteHasta,
        p_beneficiario_nombre: form.beneficiarioNombre.trim() || null,
        p_nota: form.nota.trim() || null,
        p_comprobante_url: ruta, p_id: id,
        p_motivo: "Se enlaza el comprobante recién subido",
      });
      if (e3) {
        setGuardando(false);
        avisar("error", `El comprobante subió pero no quedó enlazado (${mensajeDeError(e3)}). Ábrela con “Editar” y vuelve a subirlo.`);
        await cargar();
        return;
      }
    }

    setGuardando(false);
    cancelar();
    await cargar();
    avisar(
      "ok",
      !archivo && !(editandoId && filas.find((f) => f.id === editandoId)?.comprobante_url)
        ? "Guardada, pero SIN comprobante: no se paga hasta que subas el papel. Queda en amarillo en la lista."
        : editandoId
          ? "Cambios guardados."
          : "Asignación registrada. Entra en el próximo cálculo de planilla.",
    );
  }

  async function abrirPapel(papel: Papel) {
    // URL firmada de vida corta: el bucket es privado y estos papeles llevan el
    // nombre de una persona (y a veces el de un menor). La pestaña la abre el
    // ayudante dentro del clic — ver por qué en `abrir-archivo-firmado.ts`.
    const fallo = await abrirArchivoFirmado(createAdminSupabaseClient(), "comprobantes", papel.storage_path);
    if (fallo) avisar("error", fallo);
  }

  // Abre —o cierra— el detalle de papeles de una fila. Los meses que faltan los
  // dice la base, no esta pantalla: es la misma cuenta que enciende el aviso y la
  // que suma al contador del menú, y tres copias de una cuenta discrepan.
  async function verPapeles(f: Fila) {
    if (papelesDe?.fila.id === f.id) { setPapelesDe(null); return; }
    await cargarPapeles(f);
  }

  async function cargarPapeles(f: Fila) {
    const supabase = createAdminSupabaseClient();
    const [lista, faltan] = await Promise.all([
      supabase.rpc("fn_educacion_papeles", { p_asignacion_id: f.id }),
      supabase.rpc("fn_educacion_meses_sin_papel", { p_asignacion_id: f.id }),
    ]);
    if (lista.error) { avisar("error", mensajeDeError(lista.error, "leer los comprobantes")); return; }
    setPapelesDe({
      fila: f,
      papeles: (lista.data as Papel[]) ?? [],
      faltan: (faltan.data as string[]) ?? [],
    });
  }

  async function adjuntarPapel(f: Fila, mes: string, archivo: File) {
    if (archivo.size > limite.bytes) {
      avisar("error", `“${archivo.name}” pesa ${(archivo.size / 1048576).toFixed(1)} MB y el máximo es ${mb(limite.bytes)}.`);
      return;
    }
    setAdjuntando(mes);
    const supabase = createAdminSupabaseClient();
    const ext = archivo.name.split(".").pop()?.toLowerCase() ?? "bin";
    // La ruta lleva el mes: dos recibos de la misma asignación no se pisan, y
    // mirando el bucket se sabe qué respalda cada archivo sin abrir la base.
    const ruta = `educacion/${f.persona_id}/${f.id}-${mes.slice(0, 7)}.${ext}`;

    // El archivo primero y la fila después: si la fila fallara, quedaría un
    // archivo suelto en el bucket, que es más barato que una fila que dice tener
    // un papel que no está.
    const errorSubida = await subirArchivoConProgreso(supabase, "comprobantes", ruta, archivo, setProgreso);
    setProgreso(null);
    if (errorSubida) { setAdjuntando(null); avisar("error", `El comprobante no subió: ${errorSubida}`); return; }

    const { error } = await supabase.rpc("fn_educacion_adjuntar_comprobante", {
      p_asignacion_id: f.id, p_storage_path: ruta, p_mes_cubierto: mes, p_nota: null,
    });
    setAdjuntando(null);
    if (error) { avisar("error", mensajeDeError(error, "adjuntar el comprobante")); return; }

    await cargar();
    await cargarPapeles(f);
    avisar("ok", `Comprobante de ${nombreMes(mes)} adjuntado.`);
  }

  function pedirQuitarPapel(f: Fila, papel: Papel) {
    setQuitando({ fila: f, papel });
    setMotivoQuitar("");
  }

  async function confirmarQuitarPapel() {
    if (!quitando) return;
    if (motivoQuitar.trim().length < 3) { avisar("error", "Escribe el motivo: sin él, esa fila se queda sin con qué defenderse."); return; }

    setQuitandoGuardando(true);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_educacion_quitar_comprobante", { p_id: quitando.papel.id, p_motivo: motivoQuitar.trim() });
    setQuitandoGuardando(false);
    if (error) { avisar("error", mensajeDeError(error, "quitar el comprobante")); return; }
    const f = quitando.fila;
    setQuitando(null);
    await cargar();
    await cargarPapeles(f);
    avisar("ok", "Comprobante quitado.");
  }

  function pedirCierre(f: Fila) {
    setCerrando(f);
    setHastaCierre(hoyLima());
  }

  async function confirmarCierre() {
    if (!cerrando) return;
    if (!hastaCierre) { avisar("error", "Indica hasta qué día se le paga."); return; }
    setCerrandoGuardando(true);
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_educacion_cerrar", {
      p_id: cerrando.id, p_hasta: hastaCierre,
      p_motivo: `Cierre manual desde la pantalla de educación (${cerrando.institucion})`,
    });
    setCerrandoGuardando(false);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    const persona = cerrando.persona;
    setCerrando(null);
    await cargar();
    avisar("ok", `Cerrada al ${fmtFecha(hastaCierre)}. Deja de pagarse los periodos posteriores para ${persona}.`);
  }

  // Antes "vigente" era `vigente_hasta === null`. Desde la 0149 toda asignación
  // tiene fecha de fin, así que quien decide es el semáforo que calcula la base.
  const porVigencia = verSoloVigentes ? filas.filter((f) => f.semaforo !== "vencida") : filas;
  // "activos": oculta solo a quien ya se liquidó. Mientras esté cesada y sin
  // liquidar, sigue visible — puede tener un comprobante pendiente de revisar.
  const visibles = porVigencia.filter((f) => {
    const pf = personaFacts.get(f.persona_id);
    const cesada = !!pf?.fechaCese;
    if (filtroPersona === "activos") return !cesada || !pf?.liquidada;
    if (filtroPersona === "inactivos") return cesada;
    return true;
  });
  const ocultasPorPersona = porVigencia.length - visibles.length;
  // El total suma sólo lo que DE VERDAD se paga: una fila sin comprobante existe
  // pero no devenga, y sumarla daría un número que la planilla no va a pagar.
  //
  // Y sólo lo vigente HOY. `paga` mira que la vigencia no haya terminado, pero no
  // que ya haya empezado — daba igual cuando cada persona tenía una sola fila. Con
  // un comprobante repartido en tramos —un plan anual que se devenga mes a mes—
  // sumaría los tres tramos de una misma persona bajo el rótulo «al mes», y ella
  // nunca cobra los tres el mismo mes.
  const hoy = hoyLima();
  const pagaEsteMes = (f: Fila) => f.paga && f.vigente_desde <= hoy;
  const totalMensual = filas.filter(pagaEsteMes).reduce((s, f) => s + Number(f.monto), 0);
  // Mismo criterio que fn_educacion_por_atender en la base (0290): también
  // cuenta a las que ya cobraron un mes sin papel, que era el caso invisible.
  const porAtender = filas.filter(
    (f) => f.semaforo === "sin_comprobante" || f.semaforo === "por_vencer" || f.meses_sin_papel > 0,
  ).length;

  const formulario = (
    <div className="mb-6 grid max-w-3xl gap-3 rounded-2xl border border-sand bg-papel p-5 sm:grid-cols-2">
      <div className="flex flex-col gap-1 sm:col-span-2">
        <CampoSelect
          etiqueta="¿De quién es?"
          value={form.personaId}
          onChange={(e) => setForm({ ...form, personaId: e.target.value })}
          disabled={editandoId !== null}
        >
          <option value="">— elige a la persona —</option>
          {candidatos.map((c) => (
            <option key={c.persona_id} value={c.persona_id}>
              {c.persona} · {c.sede} · rango {c.rango}
            </option>
          ))}
        </CampoSelect>
        {/* El aviso que había acá —«ya tiene una vigente»— preguntaba por una
            columna que la 0149 dejó NOT NULL: devolvía siempre falso y no se
            encendió nunca. Y lo que DO necesita saber tampoco era ése: es cuánto
            techo le queda, que es lo que decide el monto. */}
        {techoCompartido && candidato && (
          <span className="text-xs text-ambar">
            Ya usa {soles(candidato.tope! - saldo!)} de su techo de {soles(candidato.tope!)} en
            esas fechas: quedan {soles(saldo!)}. Dos estudios conviven, pero se reparten el mismo techo.
          </span>
        )}
        {candidato && candidato.tope === null && (
          <span className="text-xs text-ambar">
            El rango “{candidato.rango}” no tiene tope cargado, así que aquí solo manda el comprobante.
          </span>
        )}
      </div>

      <div className="flex flex-col gap-1">
        <Campo
          etiqueta="Institución"
          value={form.institucion}
          onChange={(e) => setForm({ ...form, institucion: e.target.value })}
          placeholder="ej. Instituto San Ignacio"
        />
        <span className="text-xs text-taupe">Tal como aparece en el comprobante.</span>
      </div>

      <div className="flex flex-col gap-1">
        <CampoSelect
          etiqueta="¿De quién es el estudio?"
          value={form.beneficiario}
          onChange={(e) => setForm({ ...form, beneficiario: e.target.value as "trabajador" | "hijo" })}
        >
          <option value="trabajador">De la persona misma</option>
          <option value="hijo">De su hijo o hija</option>
        </CampoSelect>
        <span className="text-xs text-taupe">
          {form.beneficiario === "hijo"
            ? "Archiva también el documento que acredita el vínculo."
            : "Basta la constancia de matrícula a su nombre."}
        </span>
      </div>

      {form.beneficiario === "hijo" && (
        <div className="flex flex-col gap-1">
          <Campo
            etiqueta="¿A nombre de quién está el comprobante?"
            value={form.beneficiarioNombre}
            onChange={(e) => setForm({ ...form, beneficiarioNombre: e.target.value })}
            placeholder="nombre completo del hijo o hija"
          />
          <span className="text-xs text-taupe">
            Sin esto, un papel a nombre de un tercero no tiene cómo atarse a quien cobra —
            que es el hueco por el que estos conceptos se desconocen en una fiscalización.
            No sale en la boleta.
          </span>
        </div>
      )}

      <div className="flex flex-col gap-1">
        <Campo
          etiqueta="Costo que dice el comprobante"
          type="number" min="0" step="0.01" inputMode="decimal"
          value={form.costoDeclarado}
          onChange={(e) => setForm({ ...form, costoDeclarado: e.target.value })}
          placeholder="ej. 200.00"
        />
        <span className="text-xs text-taupe">El importe real del papel, no una estimación.</span>
      </div>

      <div className="flex flex-col gap-1 text-sm">
        ¿Qué parte cubre CAYLA?
        <div className="rounded-lg border border-dashed bg-sand/40 px-3 py-2 text-tinta">
          {COBERTURA}% del comprobante
        </div>
        <span className="text-xs text-taupe">
          Igual para todo el equipo. Cambiarlo caso por caso haría que dos personas con el
          mismo curso cobraran distinto, y eso es lo que un inspector llama trato desigual.
        </span>
      </div>

      {/* El monto no se teclea: es una consecuencia del papel y del rango. Se
          muestra mientras se escribe para que la cifra no aparezca por sorpresa,
          y se explica de dónde sale — si no, parece magia. */}
      <div className="flex flex-col gap-1 text-sm">
        Monto mensual a pagar
        <div className="rounded-lg border border-dashed bg-sand/40 px-3 py-2 font-medium text-tinta">
          {costo > 0 ? soles(monto) : "—"}
        </div>
        <span className="text-xs text-taupe">
          {costo <= 0
            ? "Se calcula solo en cuanto escribas el costo del comprobante."
            : mandaElTecho
              ? techoCompartido
                ? `Es lo que queda del techo del rango ${candidato?.rango} (${soles(candidato!.tope!)}) después de sus otros estudios vigentes: el ${COBERTURA}% del comprobante daría ${soles(delPapel!)}.`
                : `Es el tope del rango ${candidato?.rango}: el ${COBERTURA}% del comprobante daría ${soles(delPapel!)}.`
              : `Es el ${COBERTURA}% de ${soles(costo)}${techoLibre !== null ? `, por debajo del techo que le queda (${soles(techoLibre)})` : ""}.`}
        </span>
      </div>

      <div className="flex flex-col gap-1">
        <Campo
          etiqueta="Se paga desde"
          type="date"
          value={form.vigenteDesde}
          onChange={(e) => setForm({ ...form, vigenteDesde: e.target.value })}
        />
        <span className="text-xs text-taupe">
          Se paga completo en cada periodo que la encuentre vigente al empezar. Si la
          matrícula ya está corriendo, pon el primer día del periodo.
        </span>
      </div>

      <div className="flex flex-col gap-1">
        <Campo
          etiqueta="Hasta cuándo vale el comprobante"
          type="date"
          value={form.vigenteHasta}
          onChange={(e) => setForm({ ...form, vigenteHasta: e.target.value })}
        />
        <span className="text-xs text-taupe">
          El fin del ciclo que cubre este papel. Un mes antes la fila se pone ámbar para
          que puedas pedir el comprobante nuevo; al vencer deja de pagarse sola.
        </span>
      </div>

      <div className="flex flex-col gap-1 sm:col-span-2">
        <Campo
          etiqueta={`Comprobante ${editandoId ? "(subir uno nuevo reemplaza el anterior)" : ""}`}
          type="file"
          accept={limite.tipos}
          onChange={(e) => elegirArchivo(e.target.files?.[0] ?? null)}
          className="file:mr-3 file:rounded file:border-0 file:bg-sand file:px-3 file:py-1 file:text-sm"
        />
        <span className="text-xs text-taupe">
          Foto o PDF de la constancia o boleta, hasta {mb(limite.bytes)}. Puedes guardar sin él si el papel
          todavía no llegó —la fila queda en ámbar— pero <strong>no se paga nada hasta subirlo</strong>:
          es lo que hace que este monto no sea remuneración.
        </span>
        {archivo && progreso === null && (
          <span className="text-xs text-tinta">Elegido: {archivo.name} ({(archivo.size / 1048576).toFixed(1)} MB)</span>
        )}
        {/* Porcentaje real, no una animación: si la subida se detiene, la barra se
            detiene, y eso es información. Una barra que avanza sola mentiría justo
            cuando más importa saber la verdad. */}
        {progreso !== null && (
          <div className="flex flex-col gap-1">
            <div className="h-2 w-full overflow-hidden rounded-full bg-sand">
              <div
                className="h-full bg-tinta transition-[width] duration-200"
                style={{ width: `${progreso}%` }}
                role="progressbar"
                aria-valuenow={progreso}
                aria-valuemin={0}
                aria-valuemax={100}
                aria-label="Subiendo el comprobante"
              />
            </div>
            <span className="text-xs text-taupe">
              Subiendo {archivo?.name} — {progreso}%
              {progreso === 100 && " · guardando…"}
            </span>
          </div>
        )}
      </div>

      {editandoId && (
        <div className="flex flex-col gap-1 sm:col-span-2">
          <Campo
            etiqueta="¿Por qué se corrige?"
            value={form.motivo}
            onChange={(e) => setForm({ ...form, motivo: e.target.value })}
            placeholder="ej. el comprobante decía 180 y se registró 200"
          />
          <span className="text-xs text-taupe">
            Obligatorio: esto mueve lo que cobra una persona. Queda en la auditoría con tu
            nombre. Si cambias el costo o las fechas, se abre una vigencia nueva desde el
            periodo abierto — lo que ya se pagó no se toca.
          </span>
        </div>
      )}

      <div className="sm:col-span-2">
        <Campo
          etiqueta="Nota (opcional)"
          value={form.nota}
          onChange={(e) => setForm({ ...form, nota: e.target.value })}
          placeholder="ej. ciclo agosto–diciembre 2026"
        />
      </div>

      <div className="flex items-end gap-3 sm:col-span-2">
        <Boton variante="primario" onClick={guardar} disabled={guardando}>
          {progreso !== null
            ? `Subiendo… ${progreso}%`
            : guardando
              ? "Guardando…"
              : editandoId
                ? "Guardar cambios"
                : "Registrar asignación"}
        </Boton>
        <Boton onClick={cancelar}>Cancelar</Boton>
      </div>
    </div>
  );

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        <CabeceraPagina
          titulo="Asignación por educación"
          accion={
            puedeGestionar && !cargaError && !mostrandoAlta && !editandoId ? (
              <Boton variante="primario" onClick={empezarAlta}>+ Registrar asignación</Boton>
            ) : undefined
          }
        />

        {rol === null ? (
          <Cargando />
        ) : !puedeGestionar ? (
          <div className="max-w-2xl rounded-lg bg-ambar/15 px-4 py-3 text-sm text-ambar">
            Solo Desarrollo Organizacional gestiona las asignaciones por educación.
          </div>
        ) : (
          <>
            <p className="mb-4 max-w-3xl text-sm text-taupe">
              Lo que CAYLA aporta a los estudios de una integrante o de sus hijos. No es remuneración —
              no paga aportes ni entra en la base de gratificación o CTS— <strong>siempre que el
              comprobante lo sostenga</strong>. Por eso el papel se guarda aquí y no en una carpeta aparte.
            </p>

            {cargaError && (
              <div className="mb-4 max-w-3xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
                No se pudieron cargar las asignaciones: {cargaError}.{" "}
                <Boton variante="enlace" onClick={() => void cargar()}>Reintentar</Boton>
              </div>
            )}

            {(mostrandoAlta || editandoId) && formulario}

            {cargando ? (
              <Cargando />
            ) : filas.length === 0 ? (
              <div className="max-w-3xl rounded-2xl border border-sand bg-papel px-5 py-6 text-sm text-taupe">
                Todavía no hay ninguna asignación cargada. Cada una necesita su comprobante: es lo que
                permite que el pago no cuente como remuneración.
              </div>
            ) : (
              <>
                <div className="mb-3 flex flex-wrap items-center gap-4 text-sm">
                  <label className="flex items-center gap-2">
                    {/* Casilla suelta: no hay CampoCasilla todavía en
                        components/ui/campo.tsx (Fase A no la agregó pese a lo
                        anunciado) — se deja con las clases que ese primitivo
                        va a necesitar (accent-tinta, size-4) para que migrar
                        sea trivial en cuanto exista. Ver 'pendientes'. */}
                    <input
                      type="checkbox"
                      checked={verSoloVigentes}
                      onChange={(e) => setVerSoloVigentes(e.target.checked)}
                      className="size-4 rounded border-sand accent-tinta"
                    />
                    Solo las vigentes
                  </label>
                  <CampoSelect
                    etiqueta="Persona"
                    value={filtroPersona}
                    onChange={(e) => setFiltroPersona(e.target.value as FiltroPersonaEstado)}
                    className="w-56"
                  >
                    <option value="activos">Todos menos los ya liquidados</option>
                    <option value="inactivos">Solo quienes ya cesaron</option>
                    <option value="todos">Todas</option>
                  </CampoSelect>
                  {ocultasPorPersona > 0 && (
                    <Boton
                      variante="enlace"
                      className="text-xs text-taupe"
                      onClick={() => setFiltroPersona("todos")}
                    >
                      {ocultasPorPersona === 1 ? "1 oculta por liquidada" : `${ocultasPorPersona} ocultas por liquidadas`} — ver todas
                    </Boton>
                  )}
                  <span className="text-taupe">
                    Pagando: <strong className="text-tinta">{filas.filter(pagaEsteMes).length}</strong>
                    {porAtender > 0 && (
                      <> · <strong className="text-rojo">{porAtender} por atender</strong></>
                    )}
                    {" · "}suman <strong className="text-tinta">{soles(totalMensual)}</strong> al mes
                  </span>
                </div>

                <Tabla>
                  <TablaEncabezado>
                    <Th>Persona</Th>
                    <Th>Institución</Th>
                    <Th>Estudia</Th>
                    <Th>Mensual</Th>
                    <Th>Sustento</Th>
                    <Th>Vigencia</Th>
                    <Th>Papel</Th>
                    <Th>Acciones</Th>
                  </TablaEncabezado>
                  <tbody>
                    {visibles.map((f) => (
                      <Fragment key={f.id}>
                      <FilaTabla className={f.semaforo === "vencida" ? "text-taupe" : undefined}>
                        <td className="px-4 py-2">
                          {f.persona}
                          <span className="ml-1 text-xs text-taupe">{f.sede} · {f.rango}</span>
                        </td>
                        <td className="px-4 py-2">{f.institucion}</td>
                        <td className="px-4 py-2 text-xs">
                          {f.beneficiario === "hijo" ? (f.beneficiario_nombre ?? "su hijo/a") : "la persona misma"}
                        </td>
                        <td className="px-4 py-2 tabular-nums">{soles(Number(f.monto))}</td>
                        {/* Decir 75% de S/727 cuando se pagan S/90 es decir algo falso:
                            en cuatro de cada cinco filas reales lo que decide es el TECHO
                            del rango, no el porcentaje. La celda dice cuál de los dos ganó
                            — es la misma explicación que el formulario da al escribir, y
                            que en la lista faltaba. */}
                        <td className="px-4 py-2 text-xs text-taupe">
                          {(() => {
                            const delPapel = Math.round(Number(f.costo_declarado) * Number(f.cobertura_pct)) / 100;
                            const mandaElTecho = Number(f.monto) < delPapel - 0.005;
                            // ¿Comparte el techo con otro estudio suyo? Desde la 0281 el
                            // tope del rango se reparte entre las vigencias que se
                            // solapan, y decir «tope del rango cayla» cuando se pagan
                            // S/30 de un techo de S/180 sería decir algo falso.
                            const comparte = filas.some(
                              (o) => o.id !== f.id && o.persona_id === f.persona_id &&
                                o.vigente_desde <= f.vigente_hasta && o.vigente_hasta >= f.vigente_desde);
                            return mandaElTecho ? (
                              <>
                                {comparte ? "techo del rango, repartido" : "tope del rango"}{" "}
                                <strong className="text-tinta">{f.rango}</strong>
                                <span className="block">
                                  el {f.cobertura_pct}% de {soles(Number(f.costo_declarado))} daría {soles(delPapel)}
                                </span>
                              </>
                            ) : (
                              <>{f.cobertura_pct}% de {soles(Number(f.costo_declarado))}</>
                            );
                          })()}
                        </td>
                        <td className="px-4 py-2 text-xs">
                          desde {fmtFecha(f.vigente_desde)}
                          {f.semaforo === "vencida" ? (
                            <span className="block text-taupe">venció el {fmtFecha(f.vigente_hasta)}</span>
                          ) : f.semaforo === "sin_comprobante" ? (
                            <span className="block font-medium text-rojo">
                              falta el comprobante · no se paga
                            </span>
                          ) : f.semaforo === "por_vencer" ? (
                            <span className="block font-medium text-rojo">
                              vence en {f.dias_para_vencer} día{f.dias_para_vencer === 1 ? "" : "s"} · pide el papel nuevo
                            </span>
                          ) : (
                            <span className="block text-tinta">vigente hasta {fmtFecha(f.vigente_hasta)}</span>
                          )}
                        </td>
                        <td className="px-4 py-2">
                          {/* Desde la 0290 una asignación tiene un papel por cada mes
                              que paga, así que acá ya no hay UN comprobante que ver:
                              hay una cuenta, y el detalle se abre debajo. */}
                          {f.papeles > 0 ? (
                            <Boton variante="enlace" className="text-xs" onClick={() => void verPapeles(f)}>
                              {f.papeles} papel{f.papeles === 1 ? "" : "es"}
                            </Boton>
                          ) : (
                            // Antes bg-rojo/10 + text-rojo: ese par no llega a 4.5:1 en
                            // ningún tema (ver comentario de Insignia en
                            // components/ui/insignia.tsx). La variante "alerta" ya
                            // resuelve el contraste con text-rojo-profundo.
                            // <button> nativo a propósito: es solo un reset de chrome
                            // para que la píldora de <Insignia> sea clicable — <Boton>
                            // no tiene una variante sin subrayado ni padding que no
                            // desentone con una insignia.
                            <button
                              onClick={() => void verPapeles(f)}
                              className="rounded-pildora border-0 bg-transparent p-0"
                              title="Sin comprobante, este pago se recategoriza como remuneración en una fiscalización"
                            >
                              <Insignia variante="alerta">falta</Insignia>
                            </button>
                          )}
                          {f.meses_sin_papel > 0 && f.papeles > 0 && (
                            <span className="block text-xs text-ambar">
                              falta{f.meses_sin_papel === 1 ? "" : "n"} {f.meses_sin_papel} mes{f.meses_sin_papel === 1 ? "" : "es"}
                            </span>
                          )}
                        </td>
                        <td className="px-4 py-2">
                          <div className="flex flex-wrap gap-2 text-xs">
                            <Boton variante="secundario" tamano="sm" onClick={() => empezarEdicion(f)}>Editar</Boton>
                            {/* La condición era `!f.vigente_hasta`, y esa columna es NOT NULL
                                desde la 0149 (línea 84): el botón NO se dibujaba nunca. Quien
                                dejaba el instituto en septiembre con la asignación puesta hasta
                                diciembre seguía devengando entre S/90 y S/480 al mes, porque
                                desde la pantalla no había forma de cerrarla salvo deducir que
                                se entra por «Editar». `cerrar()` y fn_educacion_cerrar existían
                                y no los llamaba nadie.
                                El criterio es el mismo del filtro «ver solo vigentes» (línea
                                295), para que no vuelvan a divergir: lo ya vencido no se cierra
                                porque ya está cerrado. */}
                            {f.semaforo !== "vencida" && (
                              <Boton variante="peligro" tamano="sm" onClick={() => pedirCierre(f)}>Cerrar</Boton>
                            )}
                          </div>
                        </td>
                      </FilaTabla>
                      {papelesDe?.fila.id === f.id && (
                        <tr className="border-t bg-sand/20">
                          <td colSpan={8} className="px-4 py-3">
                            <div className="flex flex-col gap-2 text-xs">
                              <span className="font-medium text-tinta">
                                Los papeles de esta asignación, uno por cada mes que paga
                              </span>

                              {papelesDe.papeles.map((papel) => (
                                <div key={papel.id} className="flex flex-wrap items-center gap-3">
                                  <span className="w-36 text-tinta">{nombreMes(papel.mes_cubierto)}</span>
                                  <Boton variante="enlace" onClick={() => void abrirPapel(papel)}>Ver</Boton>
                                  <Boton variante="enlace" className="text-rojo" onClick={() => pedirQuitarPapel(f, papel)}>Quitar</Boton>
                                  <span className="text-taupe">lo subió {papel.subido_por}</span>
                                </div>
                              ))}

                              {papelesDe.faltan.map((mes) => (
                                <div key={mes} className="flex flex-wrap items-center gap-3">
                                  <span className="w-36 text-ambar">{nombreMes(mes)}</span>
                                  {/* <label>+<input type=file> nativo a propósito: acá el
                                      disparador es un enlace de una línea dentro de la fila
                                      del mes, no un campo con su propia etiqueta — <Campo
                                      type="file"> (como el del formulario de alta) trae ese
                                      encabezado y no calza en este layout compacto. */}
                                  <label className="cursor-pointer font-medium underline">
                                    {adjuntando === mes ? `Subiendo… ${progreso ?? 0}%` : "Adjuntar el recibo de este mes"}
                                    <input
                                      type="file"
                                      accept={limite.tipos}
                                      className="hidden"
                                      onChange={(e) => {
                                        const archivo = e.target.files?.[0];
                                        e.target.value = "";
                                        if (archivo) void adjuntarPapel(f, mes, archivo);
                                      }}
                                    />
                                  </label>
                                </div>
                              ))}

                              {papelesDe.faltan.length === 0 && (
                                <span className="text-taupe">
                                  Todos los meses que esta asignación ya cobró tienen su papel. Los que
                                  todavía no llegan se piden cuando llegue su mes.
                                </span>
                              )}
                            </div>
                          </td>
                        </tr>
                      )}
                      </Fragment>
                    ))}
                  </tbody>
                </Tabla>
              </>
            )}
          </>
        )}

        {/* Modal: motivo para quitar un comprobante. Antes era window.prompt —
            no cambia qué función se llama al confirmar, solo cómo se pregunta. */}
        <Modal
          abierto={quitando !== null}
          onCerrar={() => setQuitando(null)}
          bloqueado={quitandoGuardando}
          titulo="Quitar este comprobante"
          ancho="sm"
        >
          {quitando && (
            <>
              <p className="mb-4 text-sm text-taupe">
                Comprobante de {nombreMes(quitando.papel.mes_cubierto)}, de {quitando.fila.persona}.
                El archivo <strong>no se borra</strong> del almacén: solo deja de sostener esta
                asignación. Si era el único, la asignación deja de pagarse hasta que subas otro.
              </p>
              <label className="mb-4 flex flex-col gap-1 text-sm">
                ¿Por qué se quita? (obligatorio)
                <AreaTexto
                  value={motivoQuitar}
                  onChange={(e) => setMotivoQuitar(e.target.value)}
                  rows={2}
                  autoFocus
                  placeholder="ej. el archivo subido no corresponde a este mes"
                />
              </label>
              <div className="flex justify-end gap-3">
                <Boton onClick={() => setQuitando(null)} disabled={quitandoGuardando}>Cancelar</Boton>
                <Boton variante="peligro" onClick={() => void confirmarQuitarPapel()} cargando={quitandoGuardando}>
                  Quitar
                </Boton>
              </div>
            </>
          )}
        </Modal>

        {/* Modal: hasta cuándo se cierra una asignación. Antes era window.prompt
            pidiendo AAAA-MM-DD a mano; el campo de fecha nace con hoy, nunca en
            "" (ver CLAUDE.md sobre fechas que bloquean el envío). */}
        <Modal
          abierto={cerrando !== null}
          onCerrar={() => setCerrando(null)}
          bloqueado={cerrandoGuardando}
          titulo="Cerrar esta asignación"
          ancho="sm"
        >
          {cerrando && (
            <>
              <p className="mb-4 text-sm text-taupe">
                ¿Hasta qué día se le paga la asignación a {cerrando.persona}? La fila{" "}
                <strong>no se borra</strong>: sigue sosteniendo lo que ya se pagó. Solo deja de sumarse
                en los periodos posteriores a la fecha que pongas.
              </p>
              <Campo
                etiqueta="Se paga hasta"
                type="date"
                value={hastaCierre}
                onChange={(e) => setHastaCierre(e.target.value)}
                autoFocus
              />
              <div className="mt-4 flex justify-end gap-3">
                <Boton onClick={() => setCerrando(null)} disabled={cerrandoGuardando}>Cancelar</Boton>
                <Boton variante="peligro" onClick={() => void confirmarCierre()} cargando={cerrandoGuardando}>
                  Cerrar
                </Boton>
              </div>
            </>
          )}
        </Modal>
      </main>
    </div>
  );
}

"use client";

// ============================================================================
// Ausencias — un solo lugar para «por qué no vino»
// ----------------------------------------------------------------------------
// Absorbe la pantalla de Vacaciones: vacaciones es un tipo de ausencia más, no
// una pantalla aparte. Si fueran dos, tarde o temprano una diría una cosa y la
// otra otra — es el error que este repositorio ya pagó varias veces.
//
// Lo que esta pantalla evita, y es la razón de que exista: hasta la migración
// 0101, un día de permiso concedido se registraba como falta injustificada,
// entraba en el semáforo disciplinario y podía terminar en una carta de
// preaviso de despido por días que la propia empresa concedió.
//
// La regla del pago no la decide esta pantalla: viene del catálogo
// `tipos_ausencia`. Descanso médico y maternidad pagan porque lo manda la ley
// peruana; el resto no paga porque así lo decidió CAYLA.
// ============================================================================

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Cargando } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { Tabla, TablaEncabezado, Th, Fila } from "@/components/ui/tabla";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { Modal } from "@/components/ui/modal";
import { useRolActual } from "@/lib/admin/use-rol";
import { useFiltroGuardado } from "@/lib/admin/use-filtro-guardado";
import { hoyLima, puedeOperarEquipo, puedeVerTodasLasSedes } from "@cayla-dynamic/shared";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import { reducirImagen, pesoLegible } from "@/lib/reducir-imagen";
import { useToast } from "@/components/toast";
import { mensajeDeError } from "@/lib/admin/mensaje-error";

// ── AQUÍ VIVÍAN TRES NOMBRES DE FUNCIÓN SIN TIPAR ───────────────────────────
//
// Eran `RPC_SUBSIDIO`, `RPC_ADJUNTAR` y `RPC_POR_VENCER`, tres constantes con
// `as unknown as NombreRpcSinTipar` porque `types.ts` no conocía todavía las
// funciones que crearon la 0197 y la 0299. El comentario que las acompañaba
// prometía: «cuando alguien regenere los tipos, esto se borra y deja de
// compilar si se olvida».
//
// No se cumplió. Los tipos ya conocen las tres —se comprobó el 2026-08-26— y
// esto siguió compilando igual, porque forzar un nombre CORRECTO a la unión de
// todos los nombres nunca falla: el aviso que iba a delatarlo no podía existir.
// Se quedaron tres llamadas sin comprobar y nada lo dijo.
//
// Escritas con su nombre literal, las tres las comprueba el compilador.

function fmt(iso: string | null | undefined): string {
  if (!iso) return "—";
  const [y, m, d] = iso.split("-");
  if (!y || !m || !d) return iso;
  return `${d}/${m}/${y}`;
}
function haceMeses(n: number): string {
  const [y, m, d] = hoyLima().split("-").map(Number);
  return new Date(Date.UTC(y, m - 1 - n, d)).toISOString().slice(0, 10);
}

type FiltroEstado = "todas" | "pendientes" | "vigentes" | "anuladas";
// Igual criterio que Equipo y Planilla, y con la misma etiqueta: "activos" no
// es el estado literal de la persona — incluye también a quien cesó pero
// todavía no se le liquida, porque esa persona puede tener una ausencia por
// registrar o revisar antes de calcular su liquidación (0421/0422).
type FiltroPersonaEstado = "activos" | "inactivos" | "todos";
interface PersonaFacts { fechaCese: string | null; liquidada: boolean }

interface Persona { id: string; nombres: string; apellidos: string }
interface Tipo {
  codigo: string; nombre: string; paga: boolean;
  requiere_documento: boolean; requiere_aprobacion: boolean;
}
interface Ausencia {
  id: string; persona_id: string; nombre: string; sede: string;
  tipo: string; tipo_nombre: string; paga: boolean; requiere_aprobacion: boolean;
  fecha_inicio: string; fecha_fin: string; dias: number; motivo: string | null;
  doc_profesional: string | null; doc_colegiatura: string | null; doc_fecha: string | null;
  aprobada: boolean; registrada_tarde: boolean;
  registrada_por_nombre: string | null; registrada_at: string;
  anulada: boolean; anulada_motivo: string | null;
}
/** La única fila de esta pantalla que pide una acción: se paga, y nadie la
 *  aprobó todavía. Sirve para contar, filtrar y para subirla al principio de
 *  la tabla — antes se perdía a ojo entre un año de registros ya resueltos. */
function esPendiente(a: Ausencia): boolean {
  return a.requiere_aprobacion && !a.aprobada && !a.anulada;
}

interface Alerta {
  persona_id: string; nombre: string; tipo_nombre: string;
  veces: number; ventana_dias: number; umbral: number;
}

/** Días de descanso médico acumulados en el año — el cupo de EsSalud (0197). */
interface Subsidio {
  persona_id: string; nombre: string; dias_calendario: number;
  umbral: number; hay_que_avisar: boolean;
  dias_para_el_umbral: number; sin_certificado: number;
}

/** Un récord de vacaciones que vence pronto, o que ya venció.
 *  Es lo único de esta pantalla que tiene FECHA LÍMITE: pasada, el art. 23 del
 *  D. Leg. 713 manda una indemnización de una remuneración entera.
 *
 *  ⇩ LOS CAMPOS SON LOS DE `fn_vacaciones_por_vencer` DE LA 0297, que es la que
 *  sobrevive. Hubo un momento en que existieron DOS funciones con ese nombre
 *  —la 0299 la creó sin mirar que la 0297 ya estaba— y esta interfaz describía
 *  los campos de la que se retiró en la 0301. Si algún día los nombres no
 *  cuadran y llegan `undefined`, es esto: mirar qué firma responde de verdad. */
interface VacacionPorVencer {
  persona_id: string;
  persona: string;
  sede: string;
  dias_pendientes: number;
  records_sin_gozar: number;
  records_vencidos: number;
  vence_el: string;
  dias_para_vencer: number;
}

export default function AusenciasPage() {
  const router = useRouter();
  const rol = useRolActual();
  const puedeGestionar = puedeOperarEquipo(rol);
  const esDO = puedeVerTodasLasSedes(rol);
  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  const [personas, setPersonas] = useState<Persona[]>([]);
  const [tipos, setTipos] = useState<Tipo[]>([]);
  const [lista, setLista] = useState<Ausencia[]>([]);
  const [alertas, setAlertas] = useState<Alerta[]>([]);
  const [porVencer, setPorVencer] = useState<VacacionPorVencer[]>([]);
  const [cargando, setCargando] = useState(true);
  // Que la carga falla NO es lo mismo que un rango vacío — antes las dos
  // cosas mostraban el mismo texto tranquilizador ("no hay ausencias").
  const [errorCarga, setErrorCarga] = useState<string | null>(null);
  const [errorSubsidio, setErrorSubsidio] = useState<string | null>(null);
  const { avisar } = useToast();
  const [guardando, setGuardando] = useState(false);
  const [filtroEstado, setFiltroEstado] = useState<FiltroEstado>("todas");
  const [filtroPersona, setFiltroPersona] = useFiltroGuardado<FiltroPersonaEstado>("ausencias.persona_estado", "activos");
  const [personaFacts, setPersonaFacts] = useState<Map<string, PersonaFacts>>(new Map());

  // Formulario
  const [personaId, setPersonaId] = useState("");
  const [tipoCod, setTipoCod] = useState("");
  const [inicio, setInicio] = useState(hoyLima());
  const [fin, setFin] = useState(hoyLima());
  const [motivo, setMotivo] = useState("");
  const [docProf, setDocProf] = useState("");
  const [docColeg, setDocColeg] = useState("");
  const [docFecha, setDocFecha] = useState("");
  // LO QUE SE MANDA ES LO QUE SE VE, y por eso hay refs además de estado.
  //
  // El 2026-08-26 el formulario rechazó un descanso médico diciendo que
  // faltaba la fecha de emisión mientras el campo mostraba 26/08/2026 en
  // pantalla. El navegador tenía la fecha; React no: el valor entró sin que el
  // evento llegara al componente (Safari lo hace con `input[type=date]` y con
  // el autorrelleno), así que el estado seguía vacío y la validación —la de
  // acá y la del servidor— pedía un dato que estaba delante de los ojos.
  //
  // Leer del DOM al enviar no puede colar basura: un `input[type=date]`
  // devuelve "" o una fecha válida, nunca texto a medias.
  const refDocProf = useRef<HTMLInputElement>(null);
  const refDocColeg = useRef<HTMLInputElement>(null);
  const refDocFecha = useRef<HTMLInputElement>(null);
  const [archivo, setArchivo] = useState<File | null>(null);
  const [progreso, setProgreso] = useState<number | null>(null);
  const [subsidio, setSubsidio] = useState<Subsidio[]>([]);
  // ausencia → ruta de su certificado en el almacén. Vacío para quien no puede
  // verlos: el almacén solo responde a admin y líder de DO (0197), así que
  // quien no tiene ese permiso recibe una lista vacía y no ve ningún botón.
  // La regla vive en la base, no repetida acá.
  const [certificados, setCertificados] = useState<Record<string, string>>({});
  const [adjuntando, setAdjuntando] = useState<string | null>(null);
  // Un input[type=file] oculto por fila, disparado por un <Boton>. Un solo
  // ref no alcanza: varias filas pueden mostrar "Adjuntar documento" a la
  // vez y cada una necesita apuntar a SU input, no al de la última montada.
  const refsAdjuntar = useRef<Record<string, HTMLInputElement | null>>({});

  const [desde, setDesde] = useState(haceMeses(6));
  const [hasta, setHasta] = useState(haceMeses(-6));

  // Modal de anular (reemplaza window.prompt) y de aprobar (reemplaza
  // window.confirm) — misma llamada al servidor, solo cambia cómo se pregunta.
  const [anulando, setAnulando] = useState<Ausencia | null>(null);
  const [motivoAnular, setMotivoAnular] = useState("");
  const [aprobando, setAprobando] = useState<Ausencia | null>(null);

  const tipoSel = tipos.find((t) => t.codigo === tipoCod) ?? null;

  const pendientesCount = useMemo(() => lista.filter(esPendiente).length, [lista]);

  // Filtra por estado y, encima, sube las pendientes de aprobar al principio
  // sea cual sea el filtro elegido — es la única fila de la tabla que pide
  // una acción, y con doce meses de historial por defecto se perdía entre
  // cientos de filas ya resueltas.
  const porFiltroEstadoYRango = useMemo(() => lista.filter((a) => {
    if (filtroEstado === "pendientes") return esPendiente(a);
    if (filtroEstado === "vigentes") return !a.anulada && !esPendiente(a);
    if (filtroEstado === "anuladas") return a.anulada;
    return true;
  }), [lista, filtroEstado]);

  // "activos" no es el estado literal de la persona: incluye también a quien
  // cesó pero todavía no se le liquida, porque esa ausencia puede seguir
  // sirviendo para auditar o corregir antes de calcular esa liquidación
  // (0421/0422). Solo desaparece cuando la persona ya se liquidó.
  const porPersona = useMemo(() => porFiltroEstadoYRango.filter((a) => {
    const f = personaFacts.get(a.persona_id);
    const cesada = !!f?.fechaCese;
    if (filtroPersona === "activos") return !cesada || !f?.liquidada;
    if (filtroPersona === "inactivos") return cesada;
    return true; // "todos"
  }), [porFiltroEstadoYRango, personaFacts, filtroPersona]);

  // Mismo criterio que Equipo y Planilla: cuántas quedaron afuera del filtro
  // de persona, para el aviso "N ocultas" bajo el selector.
  const ocultasPorPersona = porFiltroEstadoYRango.length - porPersona.length;

  const listaOrdenada = useMemo(
    () => [...porPersona].sort((x, y) => Number(esPendiente(y)) - Number(esPendiente(x))),
    [porPersona],
  );

  // LA FECHA DE EMISIÓN NACE PUESTA, y no es comodidad.
  //
  // El 2026-08-26 un descanso médico real no se pudo registrar: Safari pintaba
  // 26/08/2026 en el campo y no se lo entregaba al formulario — ni por el
  // evento ni leyendo el DOM. Con el campo vacío por dentro, la validación de
  // acá y la del servidor (0101) pedían las dos un dato que estaba en pantalla,
  // y no había salida por ningún lado. Se intentó capturarlo por `onChange`,
  // por `onBlur` y por el valor del DOM; ninguno lo vio.
  //
  // Así que el campo deja de depender de que un evento llegue. Lo que se
  // MUESTRA y lo que se MANDA son este mismo valor: el que la persona escribió
  // si lo escribió, y si no, el primer día del descanso — que es cuando se
  // emite el certificado casi siempre. Visible, editable en un clic, y nunca
  // vacío mientras haya una fecha de inicio.
  const fechaDoc = docFecha || (tipoSel?.requiere_documento ? inicio : "");

  const cargar = useCallback(async () => {
    setCargando(true);
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    const [{ data: p, error: eP }, { data: t }, { data: a, error: eA }, { data: al }, { data: sub, error: eSub }, { data: pv }, { data: pf }] = await Promise.all([
      supabase.from("personas").select("id, nombres, apellidos").eq("estado", "activo").order("nombres"),
      supabase.rpc("fn_tipos_ausencia"),
      supabase.rpc("fn_ausencias", { p_desde: desde, p_hasta: hasta }),
      supabase.rpc("fn_ausencias_alerta", {}),
      supabase.rpc("fn_ausencias_subsidio", {}),
      supabase.rpc("fn_vacaciones_por_vencer", { p_dias: 60, p_as_of: null }),
      supabase.rpc("fn_personas_funciones"),
    ]);
    // Quién ya se liquidó, para el filtro "activos" de la tabla de abajo
    // (0421/0422). Si esto falla, la tabla sigue mostrando a todos —
    // degradar a "no ocultar a nadie" es más seguro que ocultar de más.
    setPersonaFacts(new Map(
      (((pf as { persona_id: string; fecha_cese: string | null; liquidada: boolean }[] | null) ?? []))
        .map((f) => [f.persona_id, { fechaCese: f.fecha_cese, liquidada: f.liquidada }] as const),
    ));
    // Si la carga falla no se pisa la lista con datos parciales: mostrar media
    // lista de ausencias es peor que no mostrar ninguna. Y se distingue del
    // "no hay ausencias" — un fallo de carga no dice que el rango esté vacío.
    if (eP || eA) {
      const msg = mensajeDeError((eP ?? eA) ?? undefined, "cargar las ausencias");
      setErrorCarga(msg);
      avisar("error", msg);
      setCargando(false);
      return;
    }
    setErrorCarga(null);
    setPersonas((p as Persona[]) ?? []);
    const tt = (t as unknown as Tipo[]) ?? [];
    setTipos(tt);
    const ausencias = (a as unknown as Ausencia[]) ?? [];
    setLista(ausencias);

    // QUÉ CERTIFICADOS HAY, preguntándoselo al almacén y no a la tabla.
    //
    // `fn_ausencias` (0101) es anterior a que el certificado existiera (0197) y
    // no devuelve `doc_storage_path`. Se podría reescribir, pero preguntarle al
    // almacén tiene una ventaja que no se pierde: encuentra el archivo aunque
    // la fila no lo tenga anotado, que es justo lo que pasa cuando la subida
    // funciona y el enlace posterior falla — un caso que esta pantalla admite a
    // propósito, porque prefiere registrar la ausencia a perderla por un
    // archivo.
    //
    // Solo se pregunta por las personas que tienen alguna ausencia CON
    // documento en el rango a la vista: son las de descanso médico y
    // maternidad, no las treinta.
    const conDocumento = Array.from(new Set(ausencias.filter((x) => x.doc_colegiatura).map((x) => x.persona_id)));
    if (conDocumento.length > 0) {
      const mapa: Record<string, string> = {};
      await Promise.all(conDocumento.map(async (pid) => {
        const { data: archivos } = await supabase.storage
          .from("certificados").list(`certificados/${pid}`, { limit: 1000 });
        for (const f of archivos ?? []) {
          // El archivo se guarda con el id de la ausencia por nombre.
          mapa[f.name.replace(/\.[^.]+$/, "")] = `certificados/${pid}/${f.name}`;
        }
      }));
      setCertificados(mapa);
    } else {
      setCertificados({});
    }
    setAlertas((al as unknown as Alerta[]) ?? []);
    // Este SÍ se mira: antes fallaba en silencio y el aviso de EsSalud
    // desaparecía sin que nadie lo notara — es plata que la empresa recupera.
    setErrorSubsidio(eSub ? mensajeDeError(eSub, "cargar el aviso de EsSalud") : null);
    setSubsidio((sub as unknown as Subsidio[]) ?? []);
    setPorVencer((pv as unknown as VacacionPorVencer[]) ?? []);
    setCargando(false);
  }, [supabase, router, desde, hasta, avisar]);

  useEffect(() => { void cargar(); }, [cargar]);

  /**
   * Abre el certificado de una ausencia en una pestaña nueva.
   *
   * El almacén es privado: la dirección se firma en el momento y caduca en un
   * minuto. Un certificado dice el diagnóstico de una persona, así que no puede
   * quedar viviendo en una URL que alguien pegue en un chat.
   *
   * La pestaña se abre ANTES de pedir la firma. Si se abriera después, Safari
   * la trata como una ventana emergente no pedida por nadie y la bloquea — el
   * clic ya terminó para cuando llega la respuesta.
   */
  async function verCertificado(a: Ausencia) {
    const ruta = certificados[a.id];
    if (!ruta) return;
    const pestana = window.open("", "_blank");
    const { data, error } = await supabase.storage.from("certificados").createSignedUrl(ruta, 60);
    if (error || !data?.signedUrl) {
      pestana?.close();
      avisar("error", error ? mensajeDeError(error, "abrir el certificado") : "No se pudo abrir el certificado: no hubo respuesta del servidor.");
      return;
    }
    if (pestana) pestana.location.href = data.signedUrl;
    else window.open(data.signedUrl, "_blank");
  }

  /**
   * Adjunta el certificado a una ausencia YA REGISTRADA.
   *
   * Faltaba, y su ausencia convertía en mentira un mensaje que esta pantalla ya
   * daba: cuando la subida falla, dice «el papel puedes adjuntarlo después» —y
   * hasta hoy no había por dónde—. El desenlace es corriente: la ausencia se
   * registra aunque el archivo no suba, a propósito, porque el registro es lo
   * que evita que esos días cuenten como falta.
   *
   * Y hay un segundo camino, el que lo destapó: el archivo se guarda con el id
   * de SU ausencia, así que si una se anula y se registra otra —«me equivoqué,
   * son 2 días»— el papel se queda en la anulada. La nueva nace sin él y no
   * había forma de moverlo.
   *
   * Quién puede lo decide `fn_ausencia_adjuntar_certificado` (0197), que además
   * solo acepta descanso médico y maternidad: no se abre un sitio para guardar
   * papeles de salud fuera del único que se revisa.
   */
  async function adjuntarCertificado(a: Ausencia, archivo: File) {
    setAdjuntando(a.id);
    const paraSubir = await reducirImagen(archivo);
    const ext = paraSubir.name.split(".").pop()?.toLowerCase() ?? "bin";
    const ruta = `certificados/${a.persona_id}/${a.id}.${ext}`;
    const errorSubida = await subirArchivoConProgreso(supabase, "certificados", ruta, paraSubir, setProgreso);
    setProgreso(null);
    if (errorSubida) {
      setAdjuntando(null);
      avisar("error", `El certificado no subió (${errorSubida} · pesaba ${pesoLegible(paraSubir.size)}). La ausencia sigue registrada igual.`);
      return;
    }
    const { error } = await supabase.rpc("fn_ausencia_adjuntar_certificado", {
      p_ausencia_id: a.id, p_storage_path: ruta,
    });
    setAdjuntando(null);
    if (error) { avisar("error", `El archivo subió, pero no se pudo enlazar (${mensajeDeError(error)}).`); return; }
    await cargar();
    avisar("ok", `Certificado adjuntado a la ausencia de ${a.nombre}.`);
  }

  async function registrar() {
    if (!personaId) { avisar("error", "Elige a la persona."); return; }
    if (!tipoCod) { avisar("error", "Elige el tipo de ausencia."); return; }
    if (fin < inicio) { avisar("error", "La fecha de fin no puede ser anterior a la de inicio."); return; }

    // Los mismos tres datos que exige `fn_registrar_ausencia` (0101), pero
    // comprobados acá y DICIENDO CUÁL falta. El aviso del servidor los enumera
    // juntos, y el 2026-08-26 eso costó un rato: los tres campos se veían
    // llenos en pantalla y el aviso seguía listándolos todos, así que no había
    // forma de saber si el que faltaba era el profesional o la fecha. Nombrar
    // el que falta convierte «no me deja» en «ah, esto».
    // El valor visible manda sobre el estado; ver el comentario de los refs.
    const vProf = (docProf || refDocProf.current?.value || "").trim();
    const vColeg = (docColeg || refDocColeg.current?.value || "").trim();
    const vFecha = fechaDoc || refDocFecha.current?.value || "";
    if (vProf !== docProf) setDocProf(vProf);
    if (vColeg !== docColeg) setDocColeg(vColeg);
    if (vFecha !== docFecha) setDocFecha(vFecha);

    if (tipoSel?.requiere_documento) {
      const faltan: string[] = [];
      if (!vProf) faltan.push("el profesional o institución");
      if (!vColeg) faltan.push("el número de colegiatura");
      if (!vFecha) faltan.push("la fecha de emisión");
      if (faltan.length > 0) {
        avisar(
          "error",
          `Falta ${faltan.join(" y ")} — ${tipoSel.nombre} lo exige. Si no tienes ningún documento, regístralo como «Descanso por salud»: no paga, pero tampoco cuenta como falta.`,
        );
        return;
      }
    }

    setGuardando(true);
    const { data: nuevoId, error } = await supabase.rpc("fn_registrar_ausencia", {
      p_persona_id: personaId,
      p_tipo: tipoCod,
      p_fecha_inicio: inicio,
      p_fecha_fin: fin,
      p_motivo: motivo.trim() || null,
      p_doc_profesional: vProf || null,
      p_doc_colegiatura: vColeg || null,
      p_doc_fecha: vFecha || null,
    });
    // El código va entre paréntesis a propósito. Con los tres datos ya
    // comprobados arriba, un rechazo del servidor por «falta el documento» ya
    // no puede ser lo que parece — y sin el código (PGRST202 si la función no
    // responde, 42501 si es permiso) no hay cómo distinguirlo de un aviso que
    // se quedó pegado en pantalla.
    if (error) {
      setGuardando(false);
      avisar("error", error.code ? `${error.message} (${error.code})` : error.message);
      return;
    }

    // El certificado, si se eligió uno. Va DESPUÉS porque su ruta lleva dentro
    // el id de la ausencia, que hasta acá no existía.
    //
    // Si la subida falla, la ausencia YA quedó registrada y eso está bien: el
    // registro es lo que evita que esos días cuenten como falta, y perderlo por
    // un archivo que no subió sería el peor intercambio posible. El mensaje lo
    // dice para que nadie crea que no se guardó nada.
    if (archivo && nuevoId) {
      // La foto se reduce ANTES de subir (ver `reducir-imagen.ts`): una foto de
      // un papel tomada con el celular de la tienda trae más píxeles de los que
      // el papel tiene información, y cada tope que se amplía solo mueve el
      // muro más lejos. Si no es imagen o el navegador no puede, sube la
      // original — ahí se prefiere el papel a los megas.
      const paraSubir = await reducirImagen(archivo);
      const ext = paraSubir.name.split(".").pop()?.toLowerCase() ?? "bin";
      const ruta = `certificados/${personaId}/${nuevoId}.${ext}`;
      setProgreso(0);
      const errorSubida = await subirArchivoConProgreso(supabase, "certificados", ruta, paraSubir, setProgreso);
      setProgreso(null);
      if (errorSubida) {
        setGuardando(false);
        avisar("error", `La ausencia SÍ quedó registrada, pero el certificado no subió (${errorSubida} · pesaba ${pesoLegible(paraSubir.size)}). Esos días ya no cuentan como falta; el papel puedes adjuntarlo después.`);
        await cargar();
        return;
      }
      const { error: eAdj } = await supabase.rpc("fn_ausencia_adjuntar_certificado", {
        p_ausencia_id: nuevoId, p_storage_path: ruta,
      });
      if (eAdj) {
        setGuardando(false);
        avisar("error", `La ausencia quedó registrada y el archivo subió, pero no se pudo enlazar (${mensajeDeError(eAdj)}).`);
        await cargar();
        return;
      }
    }

    setGuardando(false);
    setMotivo(""); setDocProf(""); setDocColeg(""); setDocFecha(""); setArchivo(null);
    await cargar();
    avisar(
      "ok",
      tipoSel?.requiere_aprobacion
        ? "Registrada. Como es un tipo que se paga, queda pendiente de aprobación de Desarrollo Organizacional."
        : "Registrada. Esos días dejan de contar como falta injustificada.",
    );
  }

  // Abre el modal de anular — la llamada real vive en confirmarAnular. Mismo
  // fn_anular_ausencia de siempre: lo único que cambia es cómo se pregunta
  // (ver Modal más abajo), no qué función se ejecuta al confirmar.
  function pedirAnular(a: Ausencia) {
    setAnulando(a);
    setMotivoAnular("");
  }

  async function confirmarAnular() {
    if (!anulando) return;
    const m = motivoAnular.trim();
    if (m.length < 4) { avisar("error", "El motivo es obligatorio (mínimo 4 caracteres)."); return; }
    setGuardando(true);
    const { error } = await supabase.rpc("fn_anular_ausencia", { p_id: anulando.id, p_motivo: m });
    setGuardando(false);
    if (error) { avisar("error", mensajeDeError(error, "anular la ausencia")); return; }
    setAnulando(null);
    await cargar();
    avisar("ok", "Ausencia anulada. Esos días vuelven a contarse como antes.");
  }

  function pedirAprobar(a: Ausencia) {
    setAprobando(a);
  }

  // Mismo fn_aprobar_ausencia de siempre — la confirmación pasa de
  // window.confirm a un Modal con dos botones (Sí/Cancelar).
  async function confirmarAprobar() {
    if (!aprobando) return;
    setGuardando(true);
    const { error } = await supabase.rpc("fn_aprobar_ausencia", { p_id: aprobando.id });
    setGuardando(false);
    if (error) { avisar("error", mensajeDeError(error, "aprobar la ausencia")); return; }
    setAprobando(null);
    await cargar();
    avisar("ok", "Aprobada.");
  }

  if (rol !== null && !puedeGestionar) {
    return (
      <div className="flex flex-1 flex-col">
        <main className="flex flex-1 items-center justify-center p-6">
          <p className="max-w-md text-center text-taupe">No tienes permiso para gestionar ausencias.</p>
        </main>
      </div>
    );
  }

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        <h1 className="mb-1 font-serif text-2xl">Ausencias</h1>
        <p className="mb-4 max-w-3xl text-xs text-taupe">
          Todos los días que alguien no vino, y por qué — vacaciones incluidas. Un día registrado aquí{" "}
          <strong className="font-medium">deja de contar como falta injustificada</strong> y no alimenta el
          expediente disciplinario. En CAYLA ningún permiso se paga, salvo los dos que la ley obliga a pagar:
          descanso médico con documento y maternidad.
        </p>

        {/* ── RÉCORDS DE VACACIONES POR VENCER (0299) ──────────────────────
            VA EN ROJO Y VA PRIMERA, y las dos cosas a propósito.

            El resto de avisos de esta pantalla son «para mirar»: cuentan algo y
            alguien decide. Éste no: tiene FECHA. Pasada esa fecha, el art. 23
            del D. Leg. 713 manda una indemnización de una remuneración entera,
            y ya no hay nada que decidir — solo pagarla.

            Por eso existe: hasta la 0283, esto solo aparecía en la hoja de
            liquidación, o sea el día en que la persona ya se fue y el récord ya
            había vencido. Avisar ahí llega tarde por definición. */}
        {porVencer.length > 0 && (
          <div className="mb-4 max-w-3xl rounded-control border border-sand bg-papel px-4 py-3 text-sm">
            <p className="font-medium text-tinta">Vacaciones que vencen: hay que programarlas.</p>
            {/* Mismo condicional de color que ya usa Bandeja para esta misma
                lista: rojo si el récord YA venció (obliga a indemnizar), ámbar
                si todavía hay margen para programar el descanso — antes las
                dos se pintaban igual, en rojo, y no se distinguía cuál ya
                costaba dinero de cuál todavía se podía evitar gratis. */}
            <ul className="mt-1 space-y-0.5 text-xs">
              {porVencer.map((v) => (
                <li key={v.persona_id} className={v.records_vencidos > 0 ? "text-rojo" : "text-ambar"}>
                  <strong className="font-medium">{v.persona}</strong> ({v.sede}){" "}
                  {v.records_vencidos > 0 ? (
                    <>tiene {v.records_vencidos === 1 ? "un récord" : `${v.records_vencidos} récords`}{" "}
                      <strong className="font-medium">ya vencidos</strong> — {v.dias_pendientes} días sin gozar.</>
                  ) : (
                    <>tiene {v.dias_pendientes} días sin gozar y su récord vence
                      el {fmt(v.vence_el)}, en {v.dias_para_vencer} días.</>
                  )}
                </li>
              ))}
            </ul>
            <p className="mt-1.5 text-xs text-taupe">
              Un récord que vence sin gozarse obliga a pagar una indemnización de una remuneración
              (art. 23, D. Leg. 713). Programar el descanso cuesta cero.
            </p>
          </div>
        )}

        {alertas.length > 0 && (
          <div className="mb-4 max-w-3xl rounded-control bg-ambar/15 px-4 py-3 text-sm text-ambar">
            <p className="font-medium">Para mirar, no para sancionar:</p>
            <ul className="mt-1 space-y-0.5 text-xs">
              {alertas.map((a) => (
                <li key={`${a.persona_id}-${a.tipo_nombre}`}>
                  <strong className="font-medium">{a.nombre}</strong> lleva {a.veces} veces «{a.tipo_nombre}»
                  en los últimos {a.ventana_dias} días (el aviso salta a partir de {a.umbral}).
                </li>
              ))}
            </ul>
            <p className="mt-1.5 text-xs opacity-80">
              El sistema cuenta y lo dice. Conversar o no es decisión de una persona, siempre.
            </p>
          </div>
        )}

        {/* EL CUPO DE ESSALUD. No es disciplinario y por eso no va en ámbar con
            el aviso de arriba: esto es plata que la empresa puede recuperar, no
            una conducta que mirar. Los primeros 20 días de incapacidad del año
            los paga CAYLA; desde el 21 los subsidia EsSalud, y el reclamo se
            sustenta con el CITT (0197).

            Salta a los 15 y no a los 20 a propósito: un aviso en el día 21 llega
            cuando el gasto ya ocurrió. */}
        {errorSubsidio && (
          <div className="mb-4 max-w-3xl rounded-control bg-rojo/10 px-4 py-3 text-sm text-rojo-profundo">
            {errorSubsidio} — esto no quiere decir que nadie tenga descanso médico pendiente de reembolso,
            solo que el aviso no se pudo calcular.{" "}
            <Boton variante="enlace" onClick={() => void cargar()}>Reintentar</Boton>
          </div>
        )}
        {!errorSubsidio && subsidio.some((s) => s.hay_que_avisar) && (
          <div className="mb-4 max-w-3xl rounded-control bg-tinta/5 px-4 py-3 text-sm">
            <p className="font-medium">EsSalud puede reembolsar parte de esto:</p>
            <ul className="mt-1 space-y-0.5 text-xs">
              {subsidio.filter((s) => s.hay_que_avisar).map((s) => (
                <li key={s.persona_id}>
                  <strong className="font-medium">{s.nombre}</strong> lleva{" "}
                  <strong className="font-medium">{s.dias_calendario} días</strong> de descanso médico este año
                  {s.dias_para_el_umbral > 0
                    ? ` — faltan ${s.dias_para_el_umbral} para los ${s.umbral} que paga CAYLA.`
                    : ` — ya pasó los ${s.umbral}: desde el día ${s.umbral + 1} el subsidio es de EsSalud.`}
                  {s.sin_certificado > 0 && (
                    <span className="block text-taupe">
                      {s.sin_certificado === 1
                        ? "Uno de sus descansos no tiene el certificado adjunto"
                        : `${s.sin_certificado} de sus descansos no tienen el certificado adjunto`}{" "}
                      — sin el CITT no se puede reclamar.
                    </span>
                  )}
                </li>
              ))}
            </ul>
            <p className="mt-1.5 text-xs text-taupe">
              Se cuentan días corridos, domingos incluidos: es como los emite el CITT y como los lleva EsSalud.
              La maternidad no entra — tiene su propio subsidio desde el primer día.
            </p>
          </div>
        )}

        {/* Registrar */}
        <div className="mb-6 grid max-w-4xl gap-3 rounded-superficie border border-sand bg-papel p-5 sm:grid-cols-2">
          <CampoSelect etiqueta="Persona" value={personaId} onChange={(e) => setPersonaId(e.target.value)}>
            <option value="">Elegir…</option>
            {personas.map((p) => (<option key={p.id} value={p.id}>{p.nombres} {p.apellidos}</option>))}
          </CampoSelect>
          {/* Tipo NACE VACÍO a propósito. Antes se rellenaba solo con el primer
              tipo del catálogo ("Vacaciones") y la comprobación de más abajo
              nunca podía avisar — el motivo real de este "Elegir…" está en
              `registrar()`, donde se exige `tipoCod`. */}
          <CampoSelect etiqueta="Tipo" value={tipoCod} onChange={(e) => setTipoCod(e.target.value)}>
            <option value="">Elegir…</option>
            {tipos.map((t) => (
              <option key={t.codigo} value={t.codigo}>
                {t.nombre}{t.paga ? " · se paga" : ""}
              </option>
            ))}
          </CampoSelect>
          <Campo
            etiqueta="Desde"
            type="date"
            value={inicio}
            onChange={(e) => { setInicio(e.target.value); if (fin < e.target.value) setFin(e.target.value); }}
          />
          <Campo etiqueta="Hasta" type="date" value={fin} onChange={(e) => setFin(e.target.value)} />
          <div className="sm:col-span-2">
            <Campo
              etiqueta="Motivo (lo que se conversó; queda en su historial)"
              value={motivo}
              onChange={(e) => setMotivo(e.target.value)}
              placeholder="ej. fallecimiento de familiar directo"
            />
          </div>

          {tipoSel?.requiere_documento && (
            <>
              {/* EMPIEZA POR LA RESPUESTA, y no es un detalle de estilo.
                  Este párrafo decía «Este tipo se paga, así que exige documento»
                  y sólo después, a media frase y en gris, «no se guarda el
                  papel». El 2026-08-08 Felipe leyó la primera mitad y se pasó un
                  rato buscando dónde subirlo. El texto estaba arriba de los
                  campos —eso no era el problema— pero abría mandando a buscar un
                  botón. Quien llega con el certificado en la mano necesita saber
                  QUÉ HACER en la primera línea, no el fundamento. */}
              <p className="text-xs text-taupe sm:col-span-2">
                <strong className="font-medium text-tinta">Lo obligatorio son los tres datos de abajo</strong>{" "}
                — quién firmó, su colegiatura y la fecha. Eso es lo verificable: un número de CMP se comprueba
                contra el registro del Colegio Médico. Subir el certificado es <strong className="font-medium">opcional</strong>,
                y conviene hacerlo si el descanso se alarga: a partir del día 21 del año EsSalud reembolsa, y
                ese reclamo se sustenta con el CITT. Si no tienes ningún documento, regístralo como{" "}
                <strong className="font-medium">Descanso por salud</strong> — no paga, pero tampoco cuenta como falta.
              </p>
              {/* Los tres quedan como <input> a mano (no <Campo>, que no es
                  forwardRef): `registrar()` lee `refDocProf/Coleg/Fecha.current`
                  como respaldo cuando Safari pone el valor sin disparar el
                  evento (ver el comentario grande sobre los refs, más arriba).
                  Pasarle un ref a Campo no llegaría al <input> real y ese
                  respaldo dejaría de funcionar en silencio. Comparten la misma
                  cadena base que Campo para no desentonar. */}
              <label className="flex flex-col gap-1 text-sm">
                Profesional o institución
                <input
                  ref={refDocProf}
                  value={docProf}
                  onChange={(e) => setDocProf(e.target.value)}
                  onBlur={(e) => setDocProf(e.currentTarget.value)}
                  placeholder="ej. Dra. Rojas / Clínica San Pablo"
                  className="rounded-control border border-sand bg-hueso px-3 py-2 text-base sm:text-sm text-tinta placeholder:text-taupe/60"
                />
              </label>
              <label className="flex flex-col gap-1 text-sm">
                N.º de colegiatura (CMP) o de CITT
                <input
                  ref={refDocColeg}
                  value={docColeg}
                  onChange={(e) => setDocColeg(e.target.value)}
                  onBlur={(e) => setDocColeg(e.currentTarget.value)}
                  placeholder="ej. CMP 12345"
                  className="rounded-control border border-sand bg-hueso px-3 py-2 text-base sm:text-sm text-tinta placeholder:text-taupe/60"
                />
              </label>
              <label className="flex flex-col gap-1 text-sm">
                Fecha de emisión
                <input
                  ref={refDocFecha}
                  type="date"
                  value={fechaDoc}
                  onChange={(e) => setDocFecha(e.target.value)}
                  onBlur={(e) => setDocFecha(e.currentTarget.value)}
                  className="rounded-control border border-sand bg-hueso px-3 py-2 text-base sm:text-sm text-tinta"
                />
              </label>
              {/* El certificado, OPCIONAL. Va en un almacén propio que solo abren
                  admin y líder de DO: un certificado dice el diagnóstico de una
                  persona, y la encargada de sede necesita saber que no vino y que
                  está justificado, no de qué está enferma (0197).

                  Se queda como <input> a mano (no <Campo>): un selector de
                  archivo lleva el botón "Elegir archivo" del navegador dentro
                  del campo (file:*), algo que Campo no contempla — pero
                  comparte su misma cadena base (borde, radio, fondo) para no
                  desentonar al lado del resto del formulario. */}
              <label className="flex flex-col gap-1 text-sm sm:col-span-2">
                Certificado o CITT <span className="text-taupe">(opcional — solo lo ven Administración y DO)</span>
                <input
                  type="file"
                  accept=".pdf,.jpg,.jpeg,.png,.heic,.heif,.webp"
                  onChange={(e) => setArchivo(e.target.files?.[0] ?? null)}
                  className="rounded-control border border-sand bg-hueso px-3 py-2 text-sm text-tinta file:mr-3 file:rounded file:border-0 file:bg-sand file:px-3 file:py-1 file:text-sm"
                />
                {progreso !== null && (
                  <span className="text-xs text-taupe">Subiendo… {progreso}%</span>
                )}
              </label>
            </>
          )}

          <div className="flex items-end gap-3 sm:col-span-2">
            <Boton variante="primario" cargando={guardando} onClick={registrar}>
              Registrar ausencia
            </Boton>
            {tipoSel && (
              <span className="text-xs text-taupe">
                {tipoSel.paga
                  ? "Se paga · lo aprueba Desarrollo Organizacional antes de entrar en planilla."
                  : "No se paga · esos días no se cobran, pero tampoco son falta."}
              </span>
            )}
          </div>
        </div>

        {/* Rango y estado a mostrar. El filtro de estado existe porque la
            única fila que pide una acción en esta pantalla —pendiente de
            aprobar— no tenía ni contador ni forma de aislarla: con el rango
            por defecto (doce meses) quedaba enterrada entre cientos de filas
            ya resueltas. Aun en "Todas", esas filas se ordenan arriba. */}
        <div className="mb-3 flex flex-wrap items-end gap-3">
          <Campo etiqueta="Desde" type="date" value={desde} onChange={(e) => setDesde(e.target.value)} />
          <Campo etiqueta="Hasta" type="date" value={hasta} onChange={(e) => setHasta(e.target.value)} />
          <CampoSelect
            etiqueta="Estado"
            value={filtroEstado}
            onChange={(e) => setFiltroEstado(e.target.value as FiltroEstado)}
          >
            <option value="todas">Todas</option>
            <option value="pendientes">Pendientes de aprobar</option>
            <option value="vigentes">Vigentes</option>
            <option value="anuladas">Anuladas</option>
          </CampoSelect>
          <CampoSelect
            etiqueta="Persona"
            value={filtroPersona}
            onChange={(e) => setFiltroPersona(e.target.value as FiltroPersonaEstado)}
          >
            <option value="activos">Sin quien ya se liquidó</option>
            <option value="inactivos">Solo quienes ya cesaron</option>
            <option value="todos">Todas</option>
          </CampoSelect>
          {ocultasPorPersona > 0 && (
            <Boton
              variante="enlace"
              className="pb-2 text-xs text-taupe"
              onClick={() => setFiltroPersona("todos")}
            >
              {ocultasPorPersona === 1 ? "1 oculta por liquidada" : `${ocultasPorPersona} ocultas por liquidadas`} — ver todas
            </Boton>
          )}
          {pendientesCount > 0 && (
            <span className="flex items-center gap-1.5 pb-2 text-xs text-taupe">
              <Insignia variante="contador" tamano="sm">{pendientesCount}</Insignia>
              {pendientesCount === 1 ? "pendiente de aprobar" : "pendientes de aprobar"}
            </span>
          )}
        </div>

        {cargando ? (
          <Cargando texto="Cargando las ausencias…" />
        ) : errorCarga ? (
          <div className="max-w-2xl rounded-control bg-rojo/10 px-4 py-3 text-sm text-rojo-profundo">
            <p>No se pudo cargar — esto no quiere decir que no haya ausencias.</p>
            <p className="mt-1 text-xs opacity-80">{errorCarga}</p>
            <Boton variante="secundario" tamano="sm" className="mt-2" onClick={() => void cargar()}>Reintentar</Boton>
          </div>
        ) : listaOrdenada.length === 0 ? (
          <div className="max-w-2xl rounded-control bg-sand/40 px-4 py-3 text-sm text-taupe">
            {lista.length === 0
              ? "No hay ausencias registradas en ese rango de fechas."
              : "No hay ausencias con ese estado en el rango elegido."}
          </div>
        ) : (
          <Tabla className="[font-variant-numeric:tabular-nums]">
            <TablaEncabezado>
              <Th>Persona</Th>
              <Th>Tipo</Th>
              <Th>Fechas</Th>
              <Th className="text-right">Días</Th>
              <Th>Estado</Th>
              <Th>Acciones</Th>
            </TablaEncabezado>
            <tbody>
                {listaOrdenada.map((a) => (
                  <Fila key={a.id} className={a.anulada ? "text-taupe/60" : ""}>
                    <td className="px-4 py-2">
                      <span className={a.anulada ? "line-through" : ""}>{a.nombre}</span>
                      <div className="text-xs text-taupe">{a.sede}</div>
                    </td>
                    <td className="px-4 py-2">
                      {a.tipo_nombre}
                      {/* punto=false: "se paga" es una etiqueta descriptiva, no
                          un estado del semáforo — el mismo caso que el propio
                          comentario de Insignia pone de ejemplo. */}
                      {a.paga && <Insignia className="ml-1.5" punto={false}>se paga</Insignia>}
                      {a.motivo && <div className="text-xs text-taupe">{a.motivo}</div>}
                      {a.doc_colegiatura && (
                        <div className="text-xs text-taupe">
                          {a.doc_profesional} · {a.doc_colegiatura} · {fmt(a.doc_fecha)}
                        </div>
                      )}
                    </td>
                    <td className="px-4 py-2 whitespace-nowrap">
                      {fmt(a.fecha_inicio)} → {fmt(a.fecha_fin)}
                      {a.registrada_tarde && !a.anulada && (
                        <div className="text-xs text-ambar">registrada con más de 15 días de retraso</div>
                      )}
                      <div className="text-xs text-taupe">
                        registró {a.registrada_por_nombre ?? "—"}
                      </div>
                    </td>
                    <td className="px-4 py-2 text-right tabular-nums">{a.dias}</td>
                    <td className="px-4 py-2">
                      {a.anulada ? (
                        <>
                          <Insignia>anulada</Insignia>
                          <div className="text-xs text-taupe">{a.anulada_motivo}</div>
                          {/* El papel sigue existiendo aunque la ausencia se
                              haya anulado, y a veces es justo lo que hay que
                              mirar para entender por qué se anuló. */}
                          {certificados[a.id] && (
                            <Boton variante="secundario" tamano="sm" className="mt-1" onClick={() => void verCertificado(a)}>
                              Ver documento
                            </Boton>
                          )}
                        </>
                      ) : esPendiente(a) ? (
                        <Insignia variante="advertencia">pendiente de aprobar</Insignia>
                      ) : (
                        <Insignia variante="positivo">vigente</Insignia>
                      )}
                    </td>
                    <td className="px-4 py-2">
                      {!a.anulada && (
                        <div className="flex flex-wrap gap-2 text-xs">
                          {certificados[a.id] ? (
                            <Boton variante="secundario" tamano="sm" onClick={() => void verCertificado(a)}>
                              Ver documento
                            </Boton>
                          ) : a.doc_colegiatura ? (
                            // `doc_colegiatura` y no una lista de tipos escrita
                            // acá: solo el descanso médico y la maternidad
                            // exigen esos datos, que es exactamente lo que
                            // `fn_ausencia_adjuntar_certificado` acepta.
                            //
                            // El disparador es un <Boton> (antes era un <label>
                            // a mano con "rounded border px-2 py-1" — no
                            // coincidía ni en radio ni en borde con el resto de
                            // acciones de la fila); el input sigue oculto
                            // detrás, uno por fila para que dos ausencias con
                            // este botón a la vez no compartan el mismo input.
                            <>
                              <Boton
                                variante="secundario"
                                tamano="sm"
                                disabled={adjuntando !== null}
                                onClick={() => refsAdjuntar.current[a.id]?.click()}
                              >
                                {adjuntando === a.id ? `Subiendo… ${progreso ?? 0}%` : "Adjuntar documento"}
                              </Boton>
                              <input
                                ref={(el) => { refsAdjuntar.current[a.id] = el; }}
                                type="file"
                                accept=".pdf,.jpg,.jpeg,.png,.heic,.heif,.webp"
                                className="hidden"
                                onChange={(e) => {
                                  const f = e.target.files?.[0];
                                  e.target.value = "";   // para poder reintentar con el mismo archivo
                                  if (f) void adjuntarCertificado(a, f);
                                }}
                              />
                            </>
                          ) : null}
                          {esDO && esPendiente(a) && (
                            <Boton variante="secundario" tamano="sm" onClick={() => pedirAprobar(a)} disabled={guardando}>
                              Aprobar
                            </Boton>
                          )}
                          <Boton variante="peligro" tamano="sm" onClick={() => pedirAnular(a)} disabled={guardando}>
                            Anular
                          </Boton>
                        </div>
                      )}
                    </td>
                  </Fila>
                ))}
              </tbody>
          </Tabla>
        )}

        <p className="mt-4 max-w-3xl text-xs text-taupe">
          Una ausencia no se borra: se anula con motivo y queda en el historial. Y no se puede registrar ni
          anular nada dentro de un periodo de planilla ya pagado — para eso hay que reabrirlo primero, igual
          que con todo lo demás que toca plata.
        </p>

        {/* Modal: anular (reemplaza window.prompt). Mismo fn_anular_ausencia
            de siempre — ver confirmarAnular. */}
        <Modal
          abierto={anulando !== null}
          onCerrar={() => setAnulando(null)}
          titulo="Anular ausencia"
          bloqueado={guardando}
        >
          {anulando && (
            <>
              <p className="mb-3 text-sm text-taupe">
                Vas a anular «{anulando.tipo_nombre}» de {anulando.nombre} ({fmt(anulando.fecha_inicio)} →{" "}
                {fmt(anulando.fecha_fin)}). No se borra: queda en el historial con el motivo.
              </p>
              <AreaTexto
                etiqueta="¿Por qué se anula? (obligatorio)"
                value={motivoAnular}
                onChange={(e) => setMotivoAnular(e.target.value)}
                rows={2}
                autoFocus
                placeholder="ej. se registró el tipo equivocado"
              />
              <div className="mt-4 flex justify-end gap-2">
                <Boton variante="secundario" onClick={() => setAnulando(null)} disabled={guardando}>
                  Cancelar
                </Boton>
                <Boton variante="peligro" cargando={guardando} onClick={() => void confirmarAnular()}>
                  Anular
                </Boton>
              </div>
            </>
          )}
        </Modal>

        {/* Modal: aprobar (reemplaza window.confirm). Mismo fn_aprobar_ausencia
            de siempre — ver confirmarAprobar. */}
        <Modal
          abierto={aprobando !== null}
          onCerrar={() => setAprobando(null)}
          titulo="Aprobar ausencia"
          ancho="sm"
          bloqueado={guardando}
        >
          {aprobando && (
            <>
              <p className="mb-4 text-sm text-taupe">
                Aprobar «{aprobando.tipo_nombre}» de {aprobando.nombre}, {aprobando.dias}{" "}
                día{aprobando.dias === 1 ? "" : "s"}. Es un tipo que{" "}
                <strong className="font-medium text-tinta">SE PAGA</strong>: al aprobarlo, esos días entran
                en su planilla.
              </p>
              <div className="flex justify-end gap-2">
                <Boton variante="secundario" onClick={() => setAprobando(null)} disabled={guardando}>
                  Cancelar
                </Boton>
                <Boton variante="primario" cargando={guardando} onClick={() => void confirmarAprobar()}>
                  Sí, aprobar
                </Boton>
              </div>
            </>
          )}
        </Modal>
      </main>
    </div>
  );
}

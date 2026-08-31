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
import { AdminNav } from "../nav";
import { Cargando } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { Tabla, TablaEncabezado, Th } from "@/components/ui/tabla";
import { useRolActual } from "@/lib/admin/use-rol";
import { hoyLima, puedeOperarEquipo, puedeVerTodasLasSedes } from "@cayla-dynamic/shared";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import { reducirImagen, pesoLegible } from "@/lib/reducir-imagen";
import { useToast } from "@/components/toast";

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
  const { avisar } = useToast();
  const [guardando, setGuardando] = useState(false);

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

  const [desde, setDesde] = useState(haceMeses(6));
  const [hasta, setHasta] = useState(haceMeses(-6));

  const tipoSel = tipos.find((t) => t.codigo === tipoCod) ?? null;

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
    const [{ data: p, error: eP }, { data: t }, { data: a, error: eA }, { data: al }, { data: sub }, { data: pv }] = await Promise.all([
      supabase.from("personas").select("id, nombres, apellidos").eq("estado", "activo").order("nombres"),
      supabase.rpc("fn_tipos_ausencia"),
      supabase.rpc("fn_ausencias", { p_desde: desde, p_hasta: hasta }),
      supabase.rpc("fn_ausencias_alerta", {}),
      supabase.rpc("fn_ausencias_subsidio", {}),
      supabase.rpc("fn_vacaciones_por_vencer", { p_dias: 60, p_as_of: null }),
    ]);
    // Si la carga falla no se pisa la lista con datos parciales: mostrar media
    // lista de ausencias es peor que no mostrar ninguna.
    if (eP || eA) {
      avisar("error", `No se pudieron cargar las ausencias: ${(eP ?? eA)!.message}`);
      setCargando(false);
      return;
    }
    setPersonas((p as Persona[]) ?? []);
    const tt = (t as unknown as Tipo[]) ?? [];
    setTipos(tt);
    setTipoCod((prev) => prev || tt[0]?.codigo || "");
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
      avisar("error", `No se pudo abrir el certificado (${error?.message ?? "sin respuesta"}).`);
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
    if (error) { avisar("error", `El archivo subió, pero no se pudo enlazar (${error.message}).`); return; }
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
        avisar("error", `La ausencia quedó registrada y el archivo subió, pero no se pudo enlazar (${eAdj.message}).`);
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

  async function anular(a: Ausencia) {
    const m = window.prompt(
      `Vas a anular «${a.tipo_nombre}» de ${a.nombre} (${fmt(a.fecha_inicio)} → ${fmt(a.fecha_fin)}).\n\n` +
        "No se borra: queda en el historial con el motivo. ¿Por qué se anula?",
    );
    if (m === null) return;
    if (m.trim().length < 4) { avisar("error", "El motivo es obligatorio (mínimo 4 caracteres)."); return; }
    setGuardando(true);
    const { error } = await supabase.rpc("fn_anular_ausencia", { p_id: a.id, p_motivo: m.trim() });
    setGuardando(false);
    if (error) { avisar("error", error.message); return; }
    await cargar();
    avisar("ok", "Ausencia anulada. Esos días vuelven a contarse como antes.");
  }

  async function aprobar(a: Ausencia) {
    if (!window.confirm(
      `Aprobar «${a.tipo_nombre}» de ${a.nombre}, ${a.dias} día${a.dias === 1 ? "" : "s"}.\n\n` +
      "Es un tipo que SE PAGA: al aprobarlo, esos días entran en su planilla.",
    )) return;
    setGuardando(true);
    const { error } = await supabase.rpc("fn_aprobar_ausencia", { p_id: a.id });
    setGuardando(false);
    if (error) { avisar("error", error.message); return; }
    await cargar();
    avisar("ok", "Aprobada.");
  }

  if (rol !== null && !puedeGestionar) {
    return (
      <div className="flex min-h-screen flex-col">
        <AdminNav />
        <main className="flex flex-1 items-center justify-center p-6">
          <p className="max-w-md text-center text-taupe">No tienes permiso para gestionar ausencias.</p>
        </main>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
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
          <div className="mb-4 max-w-3xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
            <p className="font-medium">Vacaciones que vencen: hay que programarlas.</p>
            <ul className="mt-1 space-y-0.5 text-xs">
              {porVencer.map((v) => (
                <li key={v.persona_id}>
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
            <p className="mt-1.5 text-xs opacity-80">
              Un récord que vence sin gozarse obliga a pagar una indemnización de una remuneración
              (art. 23, D. Leg. 713). Programar el descanso cuesta cero.
            </p>
          </div>
        )}

        {alertas.length > 0 && (
          <div className="mb-4 max-w-3xl rounded-lg bg-ambar/15 px-4 py-3 text-sm text-ambar">
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
        {subsidio.some((s) => s.hay_que_avisar) && (
          <div className="mb-4 max-w-3xl rounded-lg bg-tinta/5 px-4 py-3 text-sm">
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
        <div className="mb-6 grid max-w-4xl gap-3 rounded-2xl border border-sand bg-papel p-5 sm:grid-cols-2">
          <label className="flex flex-col gap-1 text-sm">
            Persona
            <select value={personaId} onChange={(e) => setPersonaId(e.target.value)} className="rounded-lg border bg-crema px-3 py-2">
              <option value="">Elegir…</option>
              {personas.map((p) => (<option key={p.id} value={p.id}>{p.nombres} {p.apellidos}</option>))}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-sm">
            Tipo
            <select value={tipoCod} onChange={(e) => setTipoCod(e.target.value)} className="rounded-lg border bg-crema px-3 py-2">
              {tipos.map((t) => (
                <option key={t.codigo} value={t.codigo}>
                  {t.nombre}{t.paga ? " · se paga" : ""}
                </option>
              ))}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-sm">
            Desde
            <input type="date" value={inicio} onChange={(e) => { setInicio(e.target.value); if (fin < e.target.value) setFin(e.target.value); }} className="rounded-lg border px-3 py-2" />
          </label>
          <label className="flex flex-col gap-1 text-sm">
            Hasta
            <input type="date" value={fin} onChange={(e) => setFin(e.target.value)} className="rounded-lg border px-3 py-2" />
          </label>
          <label className="flex flex-col gap-1 text-sm sm:col-span-2">
            Motivo <span className="text-taupe">(lo que se conversó; queda en su historial)</span>
            <input value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="ej. fallecimiento de familiar directo" className="rounded-lg border px-3 py-2" />
          </label>

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
              <label className="flex flex-col gap-1 text-sm">
                Profesional o institución
                <input ref={refDocProf} value={docProf} onChange={(e) => setDocProf(e.target.value)} onBlur={(e) => setDocProf(e.currentTarget.value)} placeholder="ej. Dra. Rojas / Clínica San Pablo" className="rounded-lg border px-3 py-2" />
              </label>
              <label className="flex flex-col gap-1 text-sm">
                N.º de colegiatura (CMP) o de CITT
                <input ref={refDocColeg} value={docColeg} onChange={(e) => setDocColeg(e.target.value)} onBlur={(e) => setDocColeg(e.currentTarget.value)} placeholder="ej. CMP 12345" className="rounded-lg border px-3 py-2" />
              </label>
              <label className="flex flex-col gap-1 text-sm">
                Fecha de emisión
                <input ref={refDocFecha} type="date" value={fechaDoc} onChange={(e) => setDocFecha(e.target.value)} onBlur={(e) => setDocFecha(e.currentTarget.value)} className="rounded-lg border px-3 py-2" />
              </label>
              {/* El certificado, OPCIONAL. Va en un almacén propio que solo abren
                  admin y líder de DO: un certificado dice el diagnóstico de una
                  persona, y la encargada de sede necesita saber que no vino y que
                  está justificado, no de qué está enferma (0197). */}
              <label className="flex flex-col gap-1 text-sm sm:col-span-2">
                Certificado o CITT <span className="text-taupe">(opcional — solo lo ven Administración y DO)</span>
                <input
                  type="file"
                  accept=".pdf,.jpg,.jpeg,.png,.heic,.heif,.webp"
                  onChange={(e) => setArchivo(e.target.files?.[0] ?? null)}
                  className="rounded-lg border px-3 py-2 text-sm file:mr-3 file:rounded file:border-0 file:bg-sand file:px-3 file:py-1 file:text-sm"
                />
                {progreso !== null && (
                  <span className="text-xs text-taupe">Subiendo… {progreso}%</span>
                )}
              </label>
            </>
          )}

          <div className="flex items-end gap-3 sm:col-span-2">
            <Boton variante="primario" onClick={registrar} disabled={guardando}>
              {guardando ? "Guardando…" : "Registrar ausencia"}
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

        {/* Rango a mostrar */}
        <div className="mb-3 flex flex-wrap items-end gap-3">
          <label className="flex flex-col gap-1 text-xs text-taupe">
            Desde
            <input type="date" value={desde} onChange={(e) => setDesde(e.target.value)} className="rounded-lg border px-3 py-1.5 text-sm text-tinta" />
          </label>
          <label className="flex flex-col gap-1 text-xs text-taupe">
            Hasta
            <input type="date" value={hasta} onChange={(e) => setHasta(e.target.value)} className="rounded-lg border px-3 py-1.5 text-sm text-tinta" />
          </label>
        </div>

        {cargando ? (
          <Cargando texto="Cargando las ausencias…" />
        ) : lista.length === 0 ? (
          <div className="max-w-2xl rounded-lg bg-sand/40 px-4 py-3 text-sm text-taupe">
            No hay ausencias registradas en ese rango de fechas.
          </div>
        ) : (
          <Tabla>
            <TablaEncabezado>
              <Th>Persona</Th>
              <Th>Tipo</Th>
              <Th>Fechas</Th>
              <Th className="text-right">Días</Th>
              <Th>Estado</Th>
              <Th>Acciones</Th>
            </TablaEncabezado>
            <tbody>
                {lista.map((a) => (
                  <tr key={a.id} className={`border-t bg-papel ${a.anulada ? "text-taupe/60" : ""}`}>
                    <td className="px-4 py-2">
                      <span className={a.anulada ? "line-through" : ""}>{a.nombre}</span>
                      <div className="text-xs text-taupe">{a.sede}</div>
                    </td>
                    <td className="px-4 py-2">
                      {a.tipo_nombre}
                      {a.paga && <Insignia className="ml-1.5">se paga</Insignia>}
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
                      ) : a.requiere_aprobacion && !a.aprobada ? (
                        <Insignia variante="advertencia">pendiente de aprobar</Insignia>
                      ) : (
                        <Insignia>vigente</Insignia>
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
                            <label className="cursor-pointer rounded border px-2 py-1 hover:bg-sand/50">
                              {adjuntando === a.id ? `Subiendo… ${progreso ?? 0}%` : "Adjuntar documento"}
                              <input
                                type="file"
                                accept=".pdf,.jpg,.jpeg,.png,.heic,.heif,.webp"
                                className="hidden"
                                disabled={adjuntando !== null}
                                onChange={(e) => {
                                  const f = e.target.files?.[0];
                                  e.target.value = "";   // para poder reintentar con el mismo archivo
                                  if (f) void adjuntarCertificado(a, f);
                                }}
                              />
                            </label>
                          ) : null}
                          {esDO && a.requiere_aprobacion && !a.aprobada && (
                            <Boton variante="secundario" tamano="sm" onClick={() => void aprobar(a)} disabled={guardando}>
                              Aprobar
                            </Boton>
                          )}
                          <Boton variante="peligro" tamano="sm" onClick={() => void anular(a)} disabled={guardando}>
                            Anular
                          </Boton>
                        </div>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
          </Tabla>
        )}

        <p className="mt-4 max-w-3xl text-xs text-taupe">
          Una ausencia no se borra: se anula con motivo y queda en el historial. Y no se puede registrar ni
          anular nada dentro de un periodo de planilla ya pagado — para eso hay que reabrirlo primero, igual
          que con todo lo demás que toca plata.
        </p>
      </main>
    </div>
  );
}

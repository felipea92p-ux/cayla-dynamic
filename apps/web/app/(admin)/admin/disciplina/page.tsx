"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { Cargando } from "@/components/cargando";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { useToast } from "@/components/toast";
import { instanteEntrega } from "@/lib/admin/instante-entrega";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import { abrirArchivoFirmado } from "@/lib/abrir-archivo-firmado";
import {
  NIVEL_DISCIPLINARIO_CORTO, NIVEL_DISCIPLINARIO_LABELS, TZ_LIMA, hoyLima, puedeOperarEquipo,
  rangoDelDiaLima, rangoDelMesLima, mesesRecientesLima, nombreDelMesLima, nombreDelMesLimaTitulo,
  primeroDeMesLima,
} from "@cayla-dynamic/shared";


// Fechas planas: se formatean en UTC para que no se corran un día por zona horaria.
function fechaCorta(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "short", timeZone: "UTC" })
    .format(new Date(Date.UTC(y, m - 1, d)));
}
function addDias(iso: string, n: number): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}
function selloLima(iso: string): string {
  const d = new Date(iso);
  if (isNaN(d.getTime())) return iso;
  return new Intl.DateTimeFormat("es-PE", { timeZone: TZ_LIMA, day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", hour12: true }).format(d);
}

// El mes de este semáforo dejó de ser una constante: se elige.
//
// Era `date_trunc('month', fn_hoy_lima())` escrito en la pantalla, y decía la
// verdad mientras el sistema solo supo contar el mes en curso. El numeral 19.4
// dice que el cierre del mes no impide emitir un documento por hechos de un mes
// ya concluido, así que ahora el mes viaja como estado y se nombra con
// `nombreDelMesLima`, que vive en `fecha-lima.ts` con el resto del calendario
// de Lima.

// Las etiquetas de la escala viven en packages/shared desde la 0200: las
// necesitan también el Dashboard y el Reporte por sede.
/** Los niveles que pasan por el descargo previo del art. 55.2 del RIT. La
 *  imputación y el despido NO: siguen el procedimiento del art. 57, con el
 *  plazo del art. 31 de la LPCL, que es otro y más largo. */
const esGradual = (nivel: string) => nivel === "amonestacion" || nivel === "suspension";

const ETIQUETA_DESCARGO: Record<string, string> = {
  sin_descargo: "no presentó descargo",
  total: "acogido",
  parcial: "acogido en parte",
  no: "no acogido",
};

const NIVEL_LABEL: Record<string, string> = NIVEL_DISCIPLINARIO_LABELS;
const CAUSAL_LABEL: Record<string, string> = { tardanza: "Tardanzas", falta: "Faltas", conducta: "Conducta" };

// `sin_medir` son los días cuya tardanza pasa de tres horas. No suman al umbral
// legal —con una medición dudosa no se sanciona— pero hasta la 0189 no existían
// para nadie: se guardaban como NULL y las tres consultas los leían como «no
// hubo tardanza». Quien llegaba tres horas tarde desaparecía de esta pantalla.
//
// `umbral` (desde la 0200) ya no es «amonestacion o aviso»: nombra el escalón
// ALCANZADO — amonestacion · suspension · imputacion · bloqueado · aviso. Y
// `minimo` es cuántas tardanzas exige el escalón de ESA persona, que depende de
// su historial: 3 sin antecedente, 2 tras una amonestación, 1 tras una
// suspensión. Antes la pantalla pedía 3 a todo el mundo y no mostraba a quien
// ya había cruzado el suyo.
interface TardanzaRow {
  persona_id: string; nombre: string; sede: string; tardanzas_mes: number;
  umbral: string; sin_medir: number; minimo: number | null; nivel_siguiente: string;
}
interface FaltaRow { persona_id: string; nombre: string; sede: string; consecutivas: number; en_30: number; en_180: number; nivel: string; }
interface Hecho { fecha: string; minutos?: number; }
/** Quién puede suscribir un documento concreto (fn_expediente_firmantes, mig. 0074). */
interface Firmante { persona_id: string; nombre: string; cargo: string; tiene_firma: boolean; }
interface Adjunto {
  id: string;
  documento_id: string;
  storage_path: string;
  tipo: TipoPapel;
  nota: string | null;
  subido_at: string;
}

const MAX_BYTES_CARGO = 50 * 1024 * 1024;
const TIPOS_CARGO = "image/jpeg,image/png,image/heic,image/webp,application/pdf";

/** Los tres papeles que pueden colgar de un documento (mig. 0206). */
type TipoPapel = "cargo_firmado" | "acta_negativa" | "descargo";

/** Cómo se dice en pantalla cada medio de entrega. */
const MEDIO_ENTREGA: Record<string, string> = {
  fisico: "en mano",
  correo: "por correo",
  notarial: "por conducto notarial",
  acta_negativa: "acta de negativa a firmar",
};

const NOMBRE_ARCHIVO: Record<TipoPapel, string> = {
  cargo_firmado: "cargo", acta_negativa: "acta", descargo: "descargo",
};
const FALTA_PAPEL: Record<TipoPapel, string> = {
  cargo_firmado: "Falta el cargo firmado.",
  acta_negativa: "Falta el acta de la negativa. Sin el papel con el testigo no queda constancia de que se ofreció.",
  descargo: "Falta el descargo. Es el papel que prueba que la persona pudo defenderse dentro del plazo del art. 31.",
};
const ETIQUETA_PAPEL: Record<TipoPapel, string> = {
  cargo_firmado: "Ver cargo", acta_negativa: "Ver acta de negativa", descargo: "Ver descargo",
};

interface Doc {
  id: string; persona_id: string; tipo_causal: string; nivel: string; estado: string;
  periodo_desde: string | null; periodo_hasta: string | null; hechos: Hecho[];
  suspension_dias: number | null; suspension_desde: string | null; suspension_hasta: string | null;
  suspension_fechas: string[] | null;
  /** Fecha de cese declarada en la carta de despido (art. 32 LPCL, mig. 0205). */
  fecha_cese: string | null;
  // Cómo terminó el procedimiento del art. 31 (mig. 0206). Mientras esto sea
  // null, una imputación entregada sigue pidiendo una decisión — y el semáforo
  // sigue diciendo «decide Gerencia».
  resuelto_at: string | null; resuelto_resultado: string | null; resuelto_motivo: string | null;
  // El descargo previo del art. 55.2 del RIT (mig. 0210). Mientras
  // `cargos_comunicados_at` sea null, el borrador no se puede firmar: la
  // omisión del descargo INVALIDA la sanción, y una sanción inválida no se
  // nota al firmarla — se nota el día que alguien la discute.
  cargos_comunicados_at: string | null; descargo_vence_at: string | null;
  descargo_acogido: string | null; descargo_valoracion: string | null;
  correlativo: string | null; creado_at: string; firmado_at: string | null;
  entregado_at: string | null; medio_entrega: string | null; entrega_testigo_nombre: string | null;
  /** El rastro del trámite: cuándo se comunicaron los cargos y —si se
   *  declararon después (mig. 0266)— quién lo declaró y cómo consta. Se lee en
   *  la fila del borrador porque es lo que hay que mirar ANTES de firmar. */
  observacion: string | null;
}

/**
 * El formulario para archivar el papel de una entrega.
 *
 * Vive acá y no dentro de cada sección porque el mismo trámite aparece en dos
 * momentos: cuando el memo está firmado y aún no se entrega, y cuando ya se
 * entregó por otra vía y falta archivar el cargo. Estaba escrito solo en el
 * primero, así que en "Entregados" el botón abría un aviso sin selector de
 * archivo — parecía que el sistema no dejaba subirlo.
 *
 * `pideFecha` es la única diferencia real entre los dos casos: en un documento
 * ya entregado la fecha buena es la registrada y la base no la pisa.
 */
function FormularioCargo({
  tipo, pideFecha, entregadoEl, fecha, progreso, ocupado,
  alElegirArchivo, alCambiarFecha, alCambiarNota, nota, testigo, alCambiarTestigo, alGuardar, alCancelar,
}: {
  tipo: TipoPapel; pideFecha: boolean; entregadoEl: string | null;
  fecha: string; nota: string; testigo: string; progreso: number | null; ocupado: boolean;
  alElegirArchivo: (f: File | null) => void;
  alCambiarFecha: (v: string) => void;
  alCambiarNota: (v: string) => void;
  alCambiarTestigo: (v: string) => void;
  alGuardar: () => void; alCancelar: () => void;
}) {
  return (
    <div className="mt-3 rounded-lg border border-sand bg-sand/20 p-3">
      <p className="mb-2 text-xs text-taupe">
        {tipo === "acta_negativa"
          ? pideFecha
            ? "El acta suscrita por quien entrega y por un testigo produce los mismos efectos que el cargo firmado (num. 55.4 del RIT). Al subirla el documento queda ENTREGADO con esta fecha, y desde ahí corren los plazos."
            : "Sube el acta para archivarla en el legajo. La entrega ya registrada no cambia."
          : tipo === "descargo"
            ? "Sube el descargo que presentó por escrito. Se archiva en el legajo junto al memo que lo provocó; no cambia el estado del documento."
          : pideFecha
            ? "Al subir el cargo, el documento queda entregado con esta fecha. Desde ahí corren los plazos de descargo (art. 31)."
            : `Sube el cargo para archivarlo en el legajo. No cambia la entrega ya registrada${entregadoEl ? ` (${entregadoEl})` : ""}.`}
      </p>
      <div className="grid gap-2 sm:grid-cols-2">
        <label className="flex flex-col gap-1 text-xs">
          {tipo === "acta_negativa" ? "Acta de la negativa" : tipo === "descargo" ? "Descargo presentado" : "Cargo firmado"}
          <input type="file" accept={TIPOS_CARGO}
            onChange={(e) => alElegirArchivo(e.target.files?.[0] ?? null)}
            className="rounded border bg-crema px-2 py-1 text-xs file:mr-2 file:rounded file:border-0 file:bg-sand file:px-2 file:py-0.5 file:text-xs" />
        </label>
        {pideFecha && (
          <label className="flex flex-col gap-1 text-xs">
            Fecha de entrega
            <input type="date" value={fecha} max={hoyLima()}
              onChange={(e) => alCambiarFecha(e.target.value)}
              className="rounded border px-2 py-1 text-xs" />
          </label>
        )}
        {tipo === "acta_negativa" && (
          <label className="flex flex-col gap-1 text-xs sm:col-span-2">
            Testigo del acta — nombre y apellido
            <input value={testigo} onChange={(e) => alCambiarTestigo(e.target.value)}
              placeholder="ej. Rosa Quispe Ramírez"
              className="rounded border px-2 py-1 text-xs" />
            <span className="text-taupe">
              Quien presenció la negativa y firma el acta junto a quien entrega. Puede ser
              cualquier persona presente, esté o no en el sistema.
            </span>
          </label>
        )}
        <label className="flex flex-col gap-1 text-xs sm:col-span-2">
          Nota (opcional)
          <input value={nota} onChange={(e) => alCambiarNota(e.target.value)}
            placeholder={tipo === "acta_negativa" ? "ej. se le leyó en voz alta y se negó también a recibir la copia" : tipo === "descargo" ? "ej. entregado en mesa de partes el 14/08" : "ej. recibido en la tienda"}
            className="rounded border px-2 py-1 text-xs" />
        </label>
      </div>
      {progreso !== null && (
        <div className="mt-2">
          <div className="h-1.5 w-full overflow-hidden rounded-full bg-sand">
            <div className="h-full bg-tinta transition-[width] duration-200"
              style={{ width: `${progreso}%` }}
              role="progressbar" aria-valuenow={progreso} aria-valuemin={0} aria-valuemax={100}
              aria-label="Subiendo el cargo" />
          </div>
          <span className="text-xs text-taupe">Subiendo — {progreso}%</span>
        </div>
      )}
      <div className="mt-2 flex items-center gap-2">
        <button onClick={alGuardar} disabled={ocupado}
          className="rounded-lg bg-tinta px-3 py-1 text-xs font-medium text-crema disabled:opacity-40">
          {progreso !== null ? `Subiendo… ${progreso}%` : "Guardar"}
        </button>
        <button onClick={alCancelar}
          className="rounded-lg border px-3 py-1 text-xs">Cancelar</button>
      </div>
    </div>
  );
}

export default function DisciplinaPage() {
  const router = useRouter();
  const yo = usePersonaActual();
  const rol = yo?.rol ?? null;
  const puede = puedeOperarEquipo(rol);
  const { avisar } = useToast();

  const [tardanzas, setTardanzas] = useState<TardanzaRow[]>([]);
  const [faltas, setFaltas] = useState<FaltaRow[]>([]);
  // «No hay nadie» y «no pude mirar» son cosas distintas y hasta hoy se
  // imprimían con la misma frase. En esta pantalla esa confusión es la peor
  // que puede haber: da por revisado lo que no se revisó.
  const [falloTard, setFalloTard] = useState(false);
  const [falloFaltas, setFalloFaltas] = useState(false);
  const [docs, setDocs] = useState<Doc[]>([]);
  const [nombres, setNombres] = useState<Map<string, string>>(new Map());
  const [cargando, setCargando] = useState(true);
  const [resaltado, setResaltado] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState<string | null>(null);
  const [medio, setMedio] = useState<Record<string, string>>({});

  // ── El cargo firmado ────────────────────────────────────────────────────
  const [adjuntos, setAdjuntos] = useState<Map<string, Adjunto[]>>(new Map());
  // Tres papeles distintos cuelgan del mismo documento y hasta la 0206 esto era
  // un booleano `negativa`. Con el descargo del art. 31 ya son tres, y un
  // booleano con tres valores posibles es cómo se cuela el tercero en la rama
  // del segundo.
  const [subiendoCargo, setSubiendoCargo] = useState<{ id: string; tipo: TipoPapel } | null>(null);
  const [archivoCargo, setArchivoCargo] = useState<File | null>(null);
  const [fechaEntrega, setFechaEntrega] = useState("");
  const [notaCargo, setNotaCargo] = useState("");
  const [testigoCargo, setTestigoCargo] = useState("");
  const [progresoCargo, setProgresoCargo] = useState<number | null>(null);
  // ── «Ya se lo comuniqué»: qué día ────────────────────────────────────────
  // Qué borrador tiene abierto el panel para declarar una comunicación pasada,
  // y el día elegido. `fechaCargos` NACE EN HOY y no en "": un campo de fecha
  // cuyo vacío bloquea el envío no puede arrancar vacío (la quinta regla de
  // CLAUDE.md, la que costó cinco despliegues el 2026-08-26). Y es el mismo
  // valor que pinta el campo y que viaja al servidor — no se lee del DOM,
  // porque Safari puede poner el valor sin disparar el evento que React
  // escucha.
  const [declarando, setDeclarando] = useState<string | null>(null);
  const [fechaCargos, setFechaCargos] = useState(hoyLima());
  const [verCerrados, setVerCerrados] = useState(false);
  // Quién puede suscribir CADA documento. Se pregunta por documento y no una
  // vez para todos porque la respuesta depende del nivel y de la sede: una
  // encargada puede firmar una amonestación verbal o escrita de SU tienda,
  // pero no una suspensión ni la de otra sede (fn_expediente_firmantes, 0074).
  // Antes se usaba fn_firmantes_disponibles, que solo listaba admin y líder DO:
  // la delegación existía en la base pero la pantalla no la ofrecía.
  //
  // Desde la 0214 la lista aplica el art. 54.4 del RIT entero, y por eso hay un
  // caso en que sale VACÍA a propósito: la carta de despido solo la suscribe la
  // Gerencia General, y en persona. Si quien mira es Desarrollo Organizacional,
  // no hay firmante que ofrecerle — puede instruir el expediente y preparar el
  // borrador, pero no firmarlo ni delegar esa firma.
  const [firmantes, setFirmantes] = useState<Record<string, Firmante[]>>({});
  // Quién no tiene constancia del Reglamento vigente (numeral 60.5, mig. 0228).
  // Se avisa ANTES de empezar el procedimiento: citar a alguien a descargo y
  // después no poder firmar es hacerle pasar el mal rato para nada.
  const [sinConstancia, setSinConstancia] = useState<Map<string, string>>(new Map());
  /** Si la empresa exige el descargo previo del art. 55.2 antes de firmar
   *  (mig. 0268). Arranca en `true` y solo baja a `false` si la configuración
   *  lo dice: una lectura fallida no puede hacer aparecer un botón de firmar
   *  que la base va a rechazar. */
  const [exigeDescargo, setExigeDescargo] = useState(true);
  const [firmanteElegido, setFirmanteElegido] = useState<Record<string, string>>({});
  /**
   * El mes sobre el que se mira y se documenta la impuntualidad, como
   * `2026-08-01`. Por defecto el mes en curso, que es lo único que existía
   * hasta hoy.
   *
   * Deja de ser una constante porque el numeral 19.4 dice que el cierre del mes
   * no impide emitir el documento por hechos de un mes ya concluido, y hasta
   * hoy el sistema lo impedía: el día 1 el contador de todos volvía a cero y el
   * mes anterior se volvía indocumentable para siempre. Doce veces al año.
   */
  const [mesTard, setMesTard] = useState<string>(primeroDeMesLima());
  const borradoresRef = useRef<HTMLDivElement>(null);

  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  const cargar = useCallback(async () => {
    setCargando(true);
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    const [{ data: t, error: eT }, { data: f, error: eF }, { data: d, error: eD }, { data: p }] = await Promise.all([
      // Para el mes en curso, sin argumentos: es el camino de siempre. Para uno
      // cerrado, `p_as_of` en su último día, que es como esta función sabe
      // mirar hacia atrás desde la 0067.
      supabase.rpc("fn_tardanzas_resumen",
        mesTard === primeroDeMesLima() ? {} : { p_as_of: rangoDelMesLima(mesTard).fin }),
      supabase.rpc("fn_faltas_resumen", {}),
      supabase.from("expediente_disciplinario")
        .select("id, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos, suspension_dias, suspension_desde, suspension_hasta, suspension_fechas, fecha_cese, resuelto_at, resuelto_resultado, resuelto_motivo, correlativo, creado_at, firmado_at, entregado_at, medio_entrega, entrega_testigo_nombre, cargos_comunicados_at, descargo_vence_at, descargo_acogido, descargo_valoracion, observacion")
        // ⇩ Entra "entregado": antes desaparecía al entregarse, así que subías el
        //   cargo y no veías que hubiera quedado. Y no había dónde consultar el
        //   papel de una entrega de hace dos meses.
        .in("estado", ["borrador", "firmado", "entregado"])
        .order("creado_at", { ascending: false }),
      supabase.from("personas").select("id, nombres, apellidos"),
    ]);
    // Los TRES errores, no solo el del legajo.
    //
    // Hasta hoy solo se miraba `eD`. Si fn_tardanzas_resumen fallaba, `t` venía
    // undefined, la lista quedaba vacía y la pantalla imprimía «Nadie con
    // tardanzas relevantes este mes» — que es lo mismo que dice cuando de
    // verdad no hay nadie. Un falso negativo MUDO, en la pantalla cuyo único
    // trabajo es no dejar pasar a nadie. Es la misma forma del hallazgo A12:
    // la Hoja de sede imprimiéndose en ceros cuando una consulta falla.
    //
    // El aviso nombra la sección para que se sepa QUÉ no se pudo mirar: un
    // «error al cargar» genérico deja igual de ciego que el silencio.
    const fallos = [
      eT ? mensajeDeError(eT, "cargar el semáforo de tardanzas") : null,
      eF ? mensajeDeError(eF, "cargar el semáforo de faltas") : null,
      eD ? mensajeDeError(eD, "cargar el legajo") : null,
    ].filter(Boolean);
    if (fallos.length) avisar("error", fallos.join(" · "));
    setFalloTard(!!eT);
    setFalloFaltas(!!eF);
    // El doble casteo no es pereza: `packages/database/src/types.ts` es un
    // archivo GENERADO y todavía describe la firma anterior de
    // fn_tardanzas_resumen, sin `sin_medir`. Regenerarlo con el CLI de hoy
    // reordena las 4.400 líneas del archivo entero, así que se dejó para cuando
    // toque actualizarlo (anotado en la 0184). Es la misma forma que ya usan
    // memo/[id], provisiones, politica-salarial y feriados por lo mismo.
    setTardanzas(Array.isArray(t) ? (t as unknown as TardanzaRow[]) : []);
    setFaltas(Array.isArray(f) ? (f as FaltaRow[]) : []);
    const lista = Array.isArray(d) ? (d as unknown as Doc[]) : [];
    setDocs(lista);
    setNombres(new Map(((p as Array<{ id: string; nombres: string; apellidos: string }>) ?? []).map((x) => [x.id, `${x.nombres} ${x.apellidos}`])));

    // Los firmantes posibles de cada borrador. Solo para borradores: un
    // documento ya firmado no cambia de firmante. Si alguna consulta falla, esa
    // fila se queda sin desplegable y se firma con la sesión actual — el mismo
    // comportamiento de antes, nunca un error en pantalla.
    // Los cargos ya archivados, para poder consultarlos sin salir del sistema.
    // Consulta aparte y tolerante: si la tabla no fuera legible, la pantalla
    // sigue funcionando sin los adjuntos en vez de quedarse en blanco.
    const { data: adj } = await supabase
      .from("expediente_adjuntos")
      .select("id, documento_id, storage_path, tipo, nota, subido_at")
      .order("subido_at", { ascending: false });
    const porDoc = new Map<string, Adjunto[]>();
    for (const a of (adj as Adjunto[]) ?? []) {
      porDoc.set(a.documento_id, [...(porDoc.get(a.documento_id) ?? []), a]);
    }
    setAdjuntos(porDoc);

    const borradores = lista.filter((x) => x.estado === "borrador");
    const pares = await Promise.all(
      borradores.map(async (x) => {
        const { data: fs } = await supabase.rpc("fn_expediente_firmantes", { p_id: x.id });
        return [x.id, Array.isArray(fs) ? (fs as Firmante[]) : []] as const;
      }),
    );
    setFirmantes(Object.fromEntries(pares));

    // La política del descargo previo (mig. 0268). Misma forma que la base:
    // solo `false` exacto releva del trámite; ausente o raro, se exige.
    const { data: cfg } = await supabase
      .from("configuracion").select("valor").eq("clave", "disciplina_descargo_previo").maybeSingle();
    setExigeDescargo((cfg as { valor: unknown } | null)?.valor !== false);

    // Consulta aparte y tolerante: si fallara, la pantalla sigue funcionando
    // sin el aviso — la base frena igual, que es donde tiene que frenar.
    const { data: sc } = await supabase.rpc("fn_sin_constancia_del_reglamento");
    setSinConstancia(new Map(
      ((sc as { persona_id: string; motivo: string }[]) ?? []).map((x) => [x.persona_id, x.motivo]),
    ));
    setCargando(false);
  }, [supabase, router, mesTard, avisar]);

  useEffect(() => { void cargar(); }, [cargar]);

  // Atajo desde la alerta del Dashboard: si el hash apunta a una persona
  // (#tard-ID o #falta-ID), baja hasta su fila en el semáforo y la resalta.
  useEffect(() => {
    if (cargando) return;
    const hash = typeof window !== "undefined" ? window.location.hash.slice(1) : "";
    if (!hash) return;
    // El aviso del Dashboard («N memos sin el cargo archivado») apunta acá. Los
    // entregados están plegados por defecto: aterrizar y no ver nada es igual a
    // no haber avisado.
    if (hash === "entregados") setVerCerrados(true);
    const el = document.getElementById(hash);
    if (!el) return;
    const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
    el.scrollIntoView({ behavior: reduce ? "auto" : "smooth", block: "center" });
    setResaltado(hash);
    const t = setTimeout(() => setResaltado(null), 2800);
    return () => clearTimeout(t);
  }, [cargando]);

  async function generar(tipo: "tardanza" | "falta", personaId: string) {
    setOcupado(personaId);
    // Las dos RPC dejaron de tener la misma forma: el generador de tardanzas
    // recibe el mes que se documenta y el de faltas no, porque la escala de
    // faltas no se cuenta por mes calendario.
    const { error } = tipo === "tardanza"
      ? await supabase.rpc("fn_expediente_generar_tardanza",
          { p_persona_id: personaId, p_mes: mesTard })
      : await supabase.rpc("fn_expediente_generar_falta", { p_persona_id: personaId });
    setOcupado(null);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    await cargar();
    avisar("ok", "Borrador generado. Revísalo abajo y fírmalo cuando esté listo.");
    const suave = typeof window !== "undefined" && !window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    setTimeout(() => borradoresRef.current?.scrollIntoView({ behavior: suave ? "smooth" : "auto", block: "start" }), 80);
  }

  /**
   * Comunicar los cargos: el acto que abre el plazo de descargo del art. 55.2
   * del RIT. Hasta que no ocurre, el borrador no se puede firmar.
   *
   * Va con confirmación porque el plazo NO se reabre: una vez comunicado,
   * comunicado. Si se hace por error hay que anular el borrador y generar otro.
   */
  async function comunicarCargos(d: Doc) {
    if (!window.confirm(
      `¿Comunicar los cargos a ${nombres.get(d.persona_id) ?? "esta persona"}?\n\n` +
      "Se abre el plazo de dos días hábiles para que presente su descargo, y hasta " +
      "que venza no se podrá firmar. El plazo no se reabre.\n\n" +
      "Antes de continuar: entrégale por escrito los hechos con sus fechas, la norma " +
      "que se le imputa y el detalle de la medición. El sistema guarda la fecha; el " +
      "documento lo entregas tú.",
    )) return;
    setOcupado(d.id);
    const { data, error } = await supabase.rpc("fn_expediente_comunicar_cargos", {
      p_id: d.id, p_dias: 2, p_nota: null,
    });
    setOcupado(null);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    await cargar();
    // Sin punto final: `selloLima` ya termina en «p. m.» y el punto detrás se
    // lee «p. m..».
    avisar("ok", `Cargos comunicados · su plazo de descargo vence el ${selloLima(String(data))}`);
  }

  /**
   * Registrar una comunicación de cargos que YA OCURRIÓ, con su fecha real
   * (mig. 0266).
   *
   * Existe por los borradores que quedaron atrapados mientras esta pantalla no
   * tuvo el botón de arriba: sus cargos se comunicaron de verdad, pero el
   * sistema no tenía dónde anotarlo. Volver a comunicarlos daría dos días de
   * plazo para un descargo que la persona ya tuvo ocasión de dar.
   *
   * No adelanta nada: la base sigue exigiendo que el plazo de ESA fecha haya
   * vencido y que el descargo esté valorado. Lo único que cambia es de dónde
   * sale la fecha — del reloj, o de alguien que declara y firma con su nombre.
   *
   * EL DÍA SE ELIGE EN UN CALENDARIO, NO SE TECLEA (hallazgo 34 de la
   * auditoría del 2026-09-03/04). Se pedía con `window.prompt` diciendo
   * «AAAA-MM-DD», y quien escribía 04/09/2026 —el formato normal en Perú— o se
   * equivocaba en un dígito no veía ningún error: `instanteEntrega` arma un
   * `Date` inválido y su `toISOString()` revienta DENTRO de los argumentos del
   * RPC, o sea después de `setOcupado(d.id)` y fuera de todo `catch`. La fila
   * se quedaba con los botones apagados hasta recargar la página, sin decir
   * por qué. Es la misma forma del bug de fecha más caro del repositorio.
   *
   * Por eso, además del campo, la llamada va envuelta en try/catch/finally:
   * pase lo que pase, la fila vuelve a su estado normal con un mensaje.
   */
  function abrirDeclaracion(d: Doc) {
    setDeclarando(d.id);
    setFechaCargos(hoyLima());
  }

  async function declararCargos(d: Doc) {
    // El día sale del estado que pinta el campo, no del DOM ni de un prompt.
    const dia = fechaCargos;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dia)) {
      avisar("error", "Elige en el calendario el día en que se le comunicaron los cargos.");
      return;
    }
    if (dia > hoyLima()) {
      avisar("error", "Ese día todavía no llega: los cargos no pudieron comunicarse en el futuro.");
      return;
    }
    const constancia = window.prompt(
      "¿Cómo consta esa comunicación? Quién se la hizo, dónde y quién más estaba delante.\n\n" +
      "Queda escrito en el expediente con tu nombre y la fecha de hoy. Si fue verbal, " +
      "dilo: es más débil que un cargo firmado y el expediente tiene que decirlo así.",
    );
    if (!constancia || constancia.trim().length < 15) {
      avisar("error", "Falta decir cómo consta, y con detalle: va a ser la única prueba de que esa comunicación existió.");
      return;
    }
    setOcupado(d.id);
    // El `finally` es lo que impide que la fila quede congelada: cualquier
    // fallo entre acá y el final —incluido uno al construir los argumentos—
    // devuelve los botones a su sitio con un mensaje, en vez de dejarlos
    // apagados sin explicación hasta recargar.
    //
    // Y dentro del `try` va SOLO la llamada. Lo que pasa después —refrescar la
    // lista, avisar— ya ocurre con la comunicación escrita, así que un fallo
    // ahí no puede decir «no se pudo registrar»: mandaría a repetirlo, o sea a
    // teclear la constancia entera otra vez para que la base la rechace por
    // estar ya comunicada.
    let vence: string;
    try {
      // `instanteEntrega` fija el mediodía de Lima para un día pasado y nunca
      // devuelve un instante futuro — el mismo problema que ya resolvía al
      // archivar un cargo.
      const { data, error } = await supabase.rpc("fn_expediente_declarar_cargos_comunicados", {
        p_id: d.id, p_fecha: instanteEntrega(dia, null), p_constancia: constancia.trim(), p_dias: 2,
      });
      if (error) { avisar("error", mensajeDeError(error, "registrar la comunicación")); return; }
      vence = String(data);
    } catch {
      avisar("error", "No se pudo registrar la comunicación. Vuelve a elegir el día en el calendario y repítelo; si sigue igual, avisa a Felipe.");
      return;
    } finally {
      setOcupado(null);
    }
    // Desde acá ya está escrito. Si refrescar falla, se dice eso y no otra cosa.
    setDeclarando(null);
    const plazo = `Comunicación registrada · su plazo de descargo venció o vence el ${selloLima(vence)}`;
    try {
      await cargar();
      avisar("ok", plazo);
    } catch {
      avisar("ok", `${plazo}. La lista no se pudo actualizar: recarga la página para verla al día.`);
    }
  }

  /**
   * La valoración escrita del descargo, que el art. 19.3 exige que diga si se
   * acogió y —cuando no— por qué. Sin ella no se puede firmar, aunque no se
   * haya presentado ningún descargo: que no lo haya también hay que hacerlo
   * constar.
   */
  async function valorarDescargo(d: Doc, acogido: string) {
    let valoracion: string | null = null;
    if (acogido === "parcial" || acogido === "no") {
      valoracion = window.prompt(
        acogido === "no"
          ? "¿Por qué no se acoge el descargo? Queda escrito en el documento (art. 19.3)."
          : "¿Qué parte se acoge y qué parte no? Queda escrito en el documento (art. 19.3).",
      );
      if (!valoracion || valoracion.trim().length < 10) {
        avisar("error", "Hace falta el motivo, y con algo de detalle: es lo que se lee si alguien discute la sanción.");
        return;
      }
    }
    setOcupado(d.id);
    const { error } = await supabase.rpc("fn_expediente_valorar_descargo", {
      p_id: d.id, p_acogido: acogido, p_valoracion: valoracion,
    });
    setOcupado(null);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    await cargar();
    avisar("ok", acogido === "total"
      ? "Descargo acogido. Si ya no corresponde sancionar, anula el borrador."
      : "Valoración guardada. Ya se puede firmar.");
  }

  async function firmar(id: string) {
    const elegido = firmanteElegido[id];
    const f = elegido ? (firmantes[id] ?? []).find((x) => x.persona_id === elegido) : null;
    // El cargo va en el aviso a propósito: es lo que se va a imprimir en el
    // documento, y quien firma tiene que verlo antes de que sea definitivo.
    const aviso = f
      ? `¿Firmar este documento como ${f.nombre} (${f.cargo})? Le asigna su número oficial y deja de ser un borrador. Después podrás entregarlo o, si hizo falta, anularlo.`
      : "¿Firmar este documento? Le asigna su número oficial y deja de ser un borrador. Después podrás entregarlo o, si hizo falta, anularlo.";
    if (!window.confirm(aviso)) return;
    setOcupado(id);
    const { data, error } = await supabase.rpc("fn_expediente_firmar", { p_id: id, p_firmante_id: elegido ?? null });
    setOcupado(null);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    await cargar();
    avisar("ok", `Firmado — documento ${data ?? ""}. Ya puedes entregarlo.`);
  }

  async function abrirCargo(id: string, tipo: TipoPapel) {
    setSubiendoCargo({ id, tipo });
    setArchivoCargo(null);
    setFechaEntrega(hoyLima());
    setNotaCargo("");
    setTestigoCargo("");
  }

  async function guardarCargo() {
    if (!subiendoCargo) return;
    // La fecha solo se pide cuando esta subida es la que marca la entrega: en un
    // documento ya entregado la fecha buena es la registrada, y en un acta de
    // negativa no hay entrega que fechar.
    const doc = docs.find((x) => x.id === subiendoCargo.id) ?? null;
    // El acta de negativa ENTREGA (num. 55.4: «produce los mismos efectos que
    // el cargo firmado»). Hasta hoy solo se archivaba y el documento se quedaba
    // en "firmado" — o sea sin efectos, sin plazos y sin contar para el
    // escalón siguiente. La negativa a firmar salía gratis.
    const actaEntrega = subiendoCargo.tipo === "acta_negativa" && doc?.estado === "firmado";
    const pideFecha = (subiendoCargo.tipo === "cargo_firmado" && doc?.estado === "firmado") || actaEntrega;
    if (!archivoCargo) {
      avisar("error", FALTA_PAPEL[subiendoCargo.tipo]);
      return;
    }
    if (archivoCargo.size > MAX_BYTES_CARGO) {
      avisar("error", `“${archivoCargo.name}” pesa ${(archivoCargo.size / 1048576).toFixed(1)} MB y el máximo es 50 MB.`);
      return;
    }
    if (pideFecha && !fechaEntrega) {
      avisar("error", "Indica la fecha de entrega: desde ahí corren los plazos de descargo.");
      return;
    }
    // La base lo rechaza igual, pero enterarse después de subir el archivo es
    // una vuelta entera para escribir un nombre.
    if (actaEntrega && !testigoCargo.trim()) {
      avisar("error", "Escribe el nombre del testigo: el acta la suscriben quien entrega y un testigo (num. 55.4 del RIT). Sin testigo no hay acta, y sin acta no hay entrega.");
      return;
    }

    setOcupado(subiendoCargo.id);
    // El archivo va a "<id del documento>/…": es lo que valida
    // fn_expediente_puede_adjuntar, así que no hay forma de colgarlo del memo
    // equivocado.
    const ext = archivoCargo.name.split(".").pop()?.toLowerCase() ?? "bin";
    const ruta = `${subiendoCargo.id}/${NOMBRE_ARCHIVO[subiendoCargo.tipo]}-${Date.now()}.${ext}`;

    setProgresoCargo(0);
    const fallo = await subirArchivoConProgreso(supabase, "expedientes", ruta, archivoCargo, setProgresoCargo);
    setProgresoCargo(null);
    if (fallo) {
      setOcupado(null);
      avisar("error", `El archivo no subió (${fallo}). Vuelve a intentarlo.`);
      return;
    }

    // La fecha de entrega solo viaja si esta subida es la que marca la entrega.
    // La función la ignoraría igual en un documento ya entregado, pero mandarla
    // la somete a validaciones que no vienen al caso y podrían rechazar el
    // archivado de un papel perfectamente válido.
    const { error } = await supabase.rpc("fn_expediente_adjuntar", {
      p_documento_id: subiendoCargo.id,
      p_path: ruta,
      p_tipo: subiendoCargo.tipo,
      // Solo el cargo firmado entrega por esta vía: fn_expediente_adjuntar
      // marca 'fisico', que es lo que un papel firmado significa. El acta se
      // entrega abajo, con su medio propio y su testigo.
      p_fecha_entrega: pideFecha && !actaEntrega ? instanteEntrega(fechaEntrega, doc?.firmado_at ?? null) : null,
      p_nota: notaCargo.trim() || null,
    });
    if (error) {
      setOcupado(null);
      avisar("error", mensajeDeError(error));
      return;
    }

    // Segundo paso, y en este orden a propósito: si esto falla, el acta ya está
    // archivada y el documento sigue en "firmado" — el estado de siempre, del
    // que se sale reintentando. Al revés dejaría un documento entregado cuyo
    // acta no está en ninguna parte.
    if (actaEntrega) {
      const { error: falloEntrega } = await supabase.rpc("fn_expediente_entregar", {
        p_id: subiendoCargo.id,
        p_medio: "acta_negativa",
        p_fecha: instanteEntrega(fechaEntrega, doc?.firmado_at ?? null),
        p_testigo_nombre: testigoCargo.trim(),
      });
      if (falloEntrega) {
        setOcupado(null);
        await cargar();
        avisar("error", `El acta quedó archivada, pero el documento NO se marcó entregado (${mensajeDeError(falloEntrega)}). Vuelve a intentarlo desde «entregar sin papel».`);
        return;
      }
    }
    setOcupado(null);

    setSubiendoCargo(null);
    await cargar();
    avisar("ok", subiendoCargo.tipo === "acta_negativa"
        ? actaEntrega
          ? "Acta archivada y documento ENTREGADO. La negativa a firmar produce los mismos efectos que la firma (num. 55.4), así que desde hoy corren los plazos y cuenta para el escalón siguiente."
          : "Acta de negativa archivada contra el documento."
        : subiendoCargo.tipo === "descargo"
          ? "Descargo archivado en el legajo. Es la pieza que prueba que se respetó el plazo del art. 31."
          : pideFecha
            ? "Cargo archivado y documento marcado como entregado. Ya no hace falta guardarlo en ninguna carpeta."
            : "Cargo archivado contra el documento. La fecha de entrega registrada no cambió.");
  }

  /**
   * Cerrar el procedimiento del art. 31 diciendo qué se resolvió (mig. 0206).
   *
   * NO es anular. Anular borra un documento que sí se entregó y sí produjo
   * efectos; resolver lo deja donde está y solo anota la decisión. Mientras no
   * se resuelva, el semáforo seguirá pidiendo esa decisión durante doce meses.
   */
  async function resolver(d: Doc, resultado: "archivado" | "despido") {
    const que = resultado === "archivado"
      ? "ARCHIVAR el procedimiento sin sancionar"
      : "dejar constancia de que se resolvió con DESPIDO";
    const motivo = window.prompt(
      `Vas a ${que}.\n\n`
      + "Explica la decisión (mínimo 10 caracteres). Es lo que sostiene el expediente si alguien lo revisa:\n\n"
      + (resultado === "despido"
        ? "Ojo: esto solo ANOTA la decisión. La carta de despido se redacta, se firma y se entrega aparte."
        : "El documento sigue entregado y sigue contando como antecedente doce meses."),
    );
    if (!motivo || motivo.trim().length < 10) return;
    setOcupado(d.id);
    // ⚠️ ESTE COMENTARIO YA NO ERA VERDAD, y se corrige el 2026-08-14. Decía que
    // `packages/database/src/types.ts` no conocía `fn_expediente_resolver` y que
    // regenerarlo rompía Ausencias, Correcciones y Datos personales. Lo primero
    // es falso desde que alguien regeneró: está en `types.ts:3531`, con la
    // convención correcta. Lo segundo pudo ser cierto entonces y hoy no se puede
    // comprobar sin volver a medirlo.
    //
    // Importa porque este comentario es el manual que va a leer quien choque con
    // el siguiente error de tipos, y le estaba diciendo que no regenerara.
    const { error } = await supabase.rpc("fn_expediente_resolver", {
      p_id: d.id, p_resultado: resultado, p_motivo: motivo.trim(),
    });
    setOcupado(null);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    await cargar();
    avisar("ok", resultado === "archivado"
      ? "Procedimiento archivado. El semáforo deja de pedir una decisión ya tomada."
      : "Anotado que se resolvió con despido. La carta se emite aparte.");
  }

  async function verAdjunto(path: string) {
    // URL firmada de vida corta: el bucket es privado y estos papeles son los
    // más delicados del sistema.
    const fallo = await abrirArchivoFirmado(supabase, "expedientes", path);
    if (fallo) avisar("error", fallo);
  }

  async function entregar(id: string) {
    const m = medio[id] ?? "fisico";
    setOcupado(id);
    const { error } = await supabase.rpc("fn_expediente_entregar", { p_id: id, p_medio: m });
    setOcupado(null);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    await cargar();
    avisar("ok", "Marcado como entregado. Guarda el cargo firmado en el legajo.");
  }

  /**
   * Fijar los días de una suspensión.
   *
   * Los días de suspensión son días LABORABLES DE ESA PERSONA (mig. 0075). Tres
   * días desde un jueves, trabajando de lunes a viernes, son jueves, viernes y
   * lunes: se salta el descanso, no se lo regala. Una suspensión sin goce que
   * cae en el día libre no es una sanción — la persona no deja de trabajar nada
   * ni deja de cobrar nada.
   *
   * Esta función sumaba días de CALENDARIO. El 25/07/2026 eso convirtió una
   * suspensión de tres días en una de uno, porque cayó en sábado, y el memo
   * impreso declaró tres. El cálculo vive ahora en la base y no acá: decide
   * cuánto deja de cobrar una persona y no puede depender de qué pantalla lo
   * pida.
   *
   * El camino viejo se conserva SOLO como red: si `fn_expediente_set_suspension`
   * no existe en esta base —la 0075 se aplicó a mano y su estado en producción
   * no está confirmado— la pantalla seguiría pudiendo fijar los días, pero
   * diciendo en voz alta que el rango puede incluir descansos. Sin esa red, una
   * base sin la 0075 dejaría la suspensión sin poder editarse.
   */
  async function guardarDias(d: Doc, dias: number, desdeElegido?: string) {
    if (dias < 1) return;
    // La fecha la puede fijar quien tramita. Antes solo se podía cambiar el
    // NÚMERO de días: el día de inicio quedaba como lo dejó el generador del
    // borrador, y si la firma se retrasaba, la suspensión caía en días ya
    // trabajados. Es el defecto que obligó a anular la T-02/0001 en julio.
    const desde = desdeElegido ?? d.suspension_desde ?? addDias(hoyLima(), 1);
    setOcupado(d.id);

    const { data, error } = await supabase.rpc("fn_expediente_set_suspension", {
      p_id: d.id, p_dias: dias, p_desde: desde,
    });

    // PGRST202 = PostgREST no encuentra la función. Cualquier otro error es un
    // error de verdad y se muestra tal cual.
    if (error && error.code !== "PGRST202") {
      setOcupado(null);
      avisar("error", mensajeDeError(error));
      return;
    }

    if (!error) {
      setOcupado(null);
      const fechas = (data as Array<{ fecha: string }> | null)?.map((x) => x.fecha) ?? [];
      const salta = fechas.length > 1
        && addDias(fechas[0], fechas.length - 1) !== fechas[fechas.length - 1];
      await cargar();
      if (fechas.length) {
        avisar("ok", salta
          ? `Suspensión fijada en ${fechas.map(fechaCorta).join(", ")} — se saltan sus días de descanso, que no cuentan como sanción.`
          // Sin punto final: `fechaCorta` ya termina en punto («18-ago.») y el
          // segundo se lee como una errata.
          : `Suspensión fijada en ${fechas.map(fechaCorta).join(", ")}`);
      }
      return;
    }

    // Red: esta base no tiene la 0075.
    const { error: eViejo } = await supabase.rpc("fn_expediente_editar_borrador", {
      p_id: d.id, p_suspension_dias: dias, p_suspension_desde: desde, p_suspension_hasta: addDias(desde, dias - 1),
    });
    setOcupado(null);
    if (eViejo) { avisar("error", mensajeDeError(eViejo)); return; }
    await cargar();
    avisar("error", "Días fijados por CALENDARIO: falta aplicar la migración 0075 en esta base. "
      + "Comprueba a mano que ninguno caiga en su día de descanso — si cae, la suspensión no se cumple ese día y el memo diría algo falso.");
  }

  /** La fecha de cese que declarará la carta de despido (art. 32 LPCL, mig. 0205). */
  async function guardarFechaCese(d: Doc, fecha: string) {
    if (!fecha || fecha === d.fecha_cese) return;
    setOcupado(d.id);
    const { error } = await supabase.rpc("fn_expediente_editar_borrador", {
      p_id: d.id, p_fecha_cese: fecha,
    });
    setOcupado(null);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    await cargar();
    avisar("ok", `Fecha de cese fijada en ${fechaCorta(fecha)}. Es la que imprimirá la carta.`);
  }

  // Volver un memo firmado a borrador para cambiar quién lo suscribe (mig. 0131).
  // Solo mientras no se haya entregado: una vez entregado se anula, no se reabre.
  async function reabrirParaCambiarFirmante(id: string) {
    if (!window.confirm(
      "¿Volver este memo a borrador para cambiar quién lo firma?\n\n" +
      "Pierde su número oficial actual; al volver a firmarlo se le asigna uno nuevo. " +
      "Solo se puede mientras no se haya entregado.",
    )) return;
    setOcupado(id);
    const { error } = await supabase.rpc("fn_expediente_reabrir", { p_id: id });
    setOcupado(null);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    await cargar();
    avisar("ok", "Vuelto a borrador. Arriba, en Borradores, elige el firmante correcto y fírmalo de nuevo.");
  }

  /**
   * Anular un documento.
   *
   * `entregado` decide el aviso, y la diferencia es real: anular un BORRADOR no
   * lo ha visto nadie; anular algo ENTREGADO retira un papel que una persona ya
   * tiene en la mano, y hay que decírselo. El sistema no puede hacer esa parte.
   *
   * Se ofrece también en «Entregados» y no solo en «Borradores» porque a veces
   * el defecto se descubre después. Pasó el 2026-08-13: una imputación de cargos
   * emitida saltándose el escalón d) del art. 19.2 del RIT, entregada tres días
   * antes de que nadie lo viera. La base siempre lo permitió —
   * `fn_expediente_anular` no mira el estado— pero la pantalla no lo ofrecía, así
   * que el único camino visible era «archivar sin sancionar», que NO es lo mismo:
   * archivar deja el escalón en «imputación» y perpetúa el salto; anular lo
   * devuelve al peldaño que de verdad tocaba.
   */
  async function anular(id: string, entregado = false) {
    if (entregado && !window.confirm(
      "Este documento YA SE ENTREGÓ y la persona lo tiene.\n\n"
      + "Anularlo lo deja sin efecto y queda el rastro con tu motivo, pero el sistema "
      + "no puede avisarle: tendrás que comunicárselo tú por escrito.\n\n"
      + "¿Continuar?",
    )) return;
    const motivo = window.prompt(
      entregado
        ? "Motivo de la anulación. Explica POR QUÉ se anula — si fue un defecto del documento o una decisión de la empresa, porque de eso depende que los antecedentes anteriores sigan contando:"
        : "Motivo de la anulación (queda registrado en el documento):",
    );
    if (!motivo || motivo.trim().length < 3) return;
    setOcupado(id);
    const { error } = await supabase.rpc("fn_expediente_anular", { p_id: id, p_motivo: motivo.trim() });
    setOcupado(null);
    if (error) { avisar("error", mensajeDeError(error)); return; }
    await cargar();
    avisar("ok", entregado
      ? "Documento anulado. Queda el rastro con tu motivo — ahora comunícaselo a la persona por escrito."
      : "Documento anulado.");
  }

  const borradores = docs.filter((d) => d.estado === "borrador");
  const entregados = docs.filter((d) => d.estado === "entregado");
  const firmados = docs.filter((d) => d.estado === "firmado");
  // Con qué causal ya tiene un borrador esperando firma. El generador de la
  // base ya lo rechaza (`fn_expediente_generar_tardanza`/`_falta`: "Ya hay un
  // borrador... pendiente"), pero el botón de acá seguía ofreciéndose igual —
  // pulsarlo solo podía terminar en ese error. Mismo principio que ya se
  // aplica a `bloqueado` más abajo: no se ofrece un botón que solo puede dar
  // error.
  const pendientePorCausal = new Set(borradores.map((d) => `${d.persona_id}:${d.tipo_causal}`));

  /**
   * El rango de días que el Reglamento admite para ESTE documento.
   *
   * El numeral 54.5 topa toda suspensión en tres días. Sobre ese techo, la
   * escala de impuntualidad gradúa: la primera es de uno a dos (19.2 c) y la
   * segunda tiene que ser MAYOR que la primera (19.2 d). La escala de faltas no
   * gradúa —tiene un solo peldaño de suspensión— así que ahí solo rige el techo.
   *
   * Es la misma cuenta que hace `fn_expediente_set_suspension` (mig. 0294), y se
   * repite acá con un fin distinto: que el campo OFREZCA lo que se puede pedir,
   * en vez de dejar teclear un número que vuelve rechazado. Un `max` de HTML no
   * impide nada por sí solo —no hay formulario que validar, hay un `onBlur` que
   * llama a la RPC— así que esto es el letrero, y la base es el candado.
   */
  function rangoSuspension(d: Doc): { min: number; max: number; previa: number | null } {
    // La referencia es el CIERRE DEL PERIODO QUE ESTE DOCUMENTO CUBRE, no «hoy».
    //
    // El numeral 19.1 c) dice que el antecedente agrava si fue notificado dentro
    // de los doce meses anteriores AL HECHO QUE SE EVALÚA. Documentando un mes
    // ya cerrado —que desde el art. 19.4 se puede— una suspensión entregada
    // DESPUÉS de ese mes no puede graduar unos hechos que, cuando ocurrieron, no
    // la tenían encima. Medirlo contra `Date.now()` le sumaba un día sin goce a
    // alguien por un atraso de la empresa en entregar el documento anterior.
    //
    // El instante sale de `rangoDelDiaLima`: el desfase de Lima no se escribe
    // a mano en ningún sitio fuera de `fecha-lima.ts`.
    // Sin periodo declarado —un borrador que aún no lo tiene— la referencia es
    // el cierre de HOY en Lima, no `Date.now()`: el instante del navegador no
    // es el corte del día de este sistema, y además `Date.now()` en render es
    // impuro y el linter lo rechaza con razón.
    const ref = Date.parse(rangoDelDiaLima(d.periodo_hasta ?? hoyLima()).fin);
    const doceMeses = ref - 365 * 24 * 60 * 60 * 1000;
    const dias = docs
      .filter((x) => x.persona_id === d.persona_id && x.tipo_causal === d.tipo_causal
        && x.nivel === "suspension" && x.estado === "entregado" && x.id !== d.id
        && x.entregado_at !== null
        && Date.parse(x.entregado_at) >= doceMeses
        && Date.parse(x.entregado_at) <= ref)
      .map((x) => x.suspension_dias ?? 0);
    const previa = dias.length ? Math.max(...dias) : null;
    if (d.tipo_causal !== "tardanza") return { min: 1, max: 3, previa };
    if (previa === null) return { min: 1, max: 2, previa };
    return { min: Math.min(previa + 1, 3), max: 3, previa };
  }

  if (rol !== null && !puede) {
    return (
      <div className="flex flex-1 flex-col">
        <main className="flex flex-1 items-center justify-center p-6">
          <p className="max-w-md text-center text-taupe">No tienes permiso para el módulo disciplinario.</p>
        </main>
      </div>
    );
  }

  /** Si el plazo de descargo sigue corriendo. Se mira contra el reloj del
 *  navegador solo para PINTAR: quien decide es la base, que rechaza la firma
 *  mientras el plazo no haya vencido. Si los dos discreparan por unos minutos,
 *  el peor caso es un botón que aparece y da error, no una sanción inválida. */
const plazoAbierto = (d: Doc) =>
  d.descargo_vence_at !== null && new Date(d.descargo_vence_at) > new Date();

function fechasDe(h: Hecho[]): string {
    if (!Array.isArray(h) || h.length === 0) return "—";
    return h.map((x) => fechaCorta(x.fecha) + (x.minutos != null ? ` (${x.minutos}′)` : "")).join(" · ");
  }

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6">
        <h1 className="mb-1 font-serif text-2xl">Disciplina</h1>
        <p className="mb-5 max-w-2xl text-sm text-taupe">
          El sistema detecta quién cruzó un umbral y <strong>arma el borrador del memo</strong> con las pruebas puestas;
          tú lo revisas y firmas. Tardanza y falta van <strong>separadas</strong>: pesan distinto en la escala.
        </p>

        {/* Semáforo de tardanzas */}
        <div className="mb-6 max-w-3xl overflow-hidden rounded-2xl border border-sand bg-papel">
          <div className="border-b bg-sand/50 px-4 py-2">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <h2 className="text-sm font-medium">
                Tardanzas — {nombreDelMesLimaTitulo(mesTard)} {mesTard.slice(0, 4)}
                {!cargando && tardanzas.length > 0 && <span className="font-normal text-taupe"> · {tardanzas.length}</span>}
              </h2>
              {/* Sin este selector el arreglo del generador no se alcanza desde
                  ningún sitio: el botón de abajo está deshabilitado cuando el
                  contador del mes es 0, y el día 1 —el caso que se arregla— es
                  0 para todo el mundo. */}
              <label className="flex items-center gap-1 text-xs text-taupe">
                Mes
                <select value={mesTard} onChange={(e) => setMesTard(e.target.value)}
                  className="rounded border bg-crema px-2 py-1 text-xs text-tinta">
                  {mesesRecientesLima().map((m) => (
                    <option key={m} value={m}>
                      {nombreDelMesLimaTitulo(m)} {m.slice(0, 4)}{m === primeroDeMesLima() ? " · en curso" : ""}
                    </option>
                  ))}
                </select>
              </label>
            </div>
            {/* El umbral NO es el mismo para todas: depende del escalón en el
                que esté cada quien (RIT art. 7 b/c/d). Decir «3» aquí, como
                decía hasta la 0200, era falso para quien arrastra un
                antecedente vigente — y esa es justamente la gente por la que
                hay que actuar antes. */}
            {/* «El mes» tenía que decir MES CALENDARIO. Incidencias cuenta el
                patrón de tardanzas sobre 30 días corridos, así que las dos
                pantallas dan números distintos para la misma persona el mismo
                día —una tardanza del mes pasado entra en una y no en la otra— y
                el que gobierna el papel es este: el art. 19.2-b del RIT dice
                «en un mismo mes calendario» y la carta cita ese texto. Sin
                nombrar el periodo, la diferencia se lee como que una de las dos
                está rota. */}
            <p className="mt-0.5 text-xs text-taupe">
              Umbral RIT art. 19.2: <strong>3</strong> en el <strong>mes calendario</strong> sin
              antecedente · <strong>2</strong> tras una amonestación · <strong>1</strong> tras una
              suspensión. Cada fila dice el suyo.
              {" "}Cada mes se cuenta por separado; Incidencias avisa sobre los últimos 30 días
              corridos, así que ahí el número puede ser mayor que acá.
            </p>
            {/* Documentar hacia atrás es un derecho del numeral 19.4 y a la vez
                la única forma NUEVA de hacer daño que abre este cambio: hasta
                hoy era imposible. Las dos advertencias que lo acotan no las
                puede decidir el código, así que se dicen acá. */}
            {mesTard !== primeroDeMesLima() && (
              <p className="mt-2 rounded-lg bg-ambar/10 px-3 py-2 text-xs text-ambar">
                Estás mirando un <strong>mes ya cerrado</strong>. El numeral 19.4 permite emitir el
                documento por hechos de un mes concluido, pero el art. 52 dice que una demora
                injustificada equivale a condonación — y un hecho condonado no sustenta sanción ni
                se valora como antecedente. Si no hay motivo para el retraso, no lo emitas.
                {" "}Y por el numeral 56.6: <strong>emite del mes más viejo al más nuevo</strong>.
                Entregado un documento, los meses anteriores ya no se pueden documentar.
              </p>
            )}
          </div>
          {cargando ? (
            <Cargando />
          ) : falloTard ? (
            <p className="px-4 py-6 text-sm text-rojo">
              No se pudo leer el semáforo de tardanzas. <strong>Esto NO significa que no haya nadie</strong> —
              significa que no se pudo mirar. Vuelve a cargar la página; si sigue igual, avisa antes de dar el mes por revisado.
            </p>
          ) : tardanzas.length === 0 ? (
            <p className="px-4 py-6 text-sm text-taupe">Nadie con tardanzas relevantes en {nombreDelMesLima(mesTard)}.</p>
          ) : (
            <ul className="divide-y">
              {tardanzas.map((t) => (
                <li key={t.persona_id} id={`tard-${t.persona_id}`} className={`flex flex-wrap items-center justify-between gap-3 scroll-mt-24 px-4 py-3 text-sm transition-colors ${resaltado === `tard-${t.persona_id}` ? "bg-rojo/10" : ""}`}>
                  <span>
                    <strong>{t.nombre}</strong> <span className="text-taupe">· {t.sede}</span>
                    {t.tardanzas_mes > 0 && (
                      <span className={`ml-2 rounded-full px-2 py-0.5 text-xs ${t.umbral === "aviso" ? "bg-ambar/15 text-ambar" : "bg-rojo/10 text-rojo"}`}>
                        {t.tardanzas_mes}
                        {t.umbral === "aviso"
                          ? ` de ${t.minimo} en ${nombreDelMesLima(mesTard)} · aviso`
                          : t.umbral === "bloqueado"
                            ? " · imputación vigente, decide Gerencia"
                            : ` · corresponde ${NIVEL_DISCIPLINARIO_CORTO[t.umbral as keyof typeof NIVEL_DISCIPLINARIO_CORTO] ?? t.umbral}`}
                      </span>
                    )}
                    {t.sin_medir > 0 && (
                      <span
                        className="ml-2 rounded-full bg-sand px-2 py-0.5 text-xs text-taupe"
                        title="Entró más de tres horas después de su hora. Casi siempre significa que ese día tenía otro turno y el sistema comparó contra el equivocado. No cuenta para el umbral legal: míralo tú."
                      >
                        {t.sin_medir} sin medir
                      </span>
                    )}
                  </span>
                  {/* Desde la 0189 esta lista incluye a quien tiene SOLO días sin medir.
                      Sobre esa persona no hay nada que imputar —el expediente se arma
                      únicamente con tardanzas medibles— así que ofrecerle el botón sería
                      prometer un documento que saldría vacío. */}
                  {/* Con una imputación vigente el generador se niega siempre
                      («decide Gerencia»). Ofrecer un botón que solo puede dar
                      error enseña a ignorar los errores de esta pantalla. */}
                  <button onClick={() => generar("tardanza", t.persona_id)}
                    disabled={ocupado === t.persona_id || t.tardanzas_mes === 0 || t.umbral === "bloqueado" || pendientePorCausal.has(`${t.persona_id}:tardanza`)}
                    title={pendientePorCausal.has(`${t.persona_id}:tardanza`)
                      ? "Ya hay un borrador de tardanza pendiente para esta persona. Revísalo en «Borradores pendientes» antes de generar otro."
                      : t.tardanzas_mes === 0
                      ? "Sus únicos días son de más de tres horas: no se puede imputar sobre una medición dudosa. Revisa su turno de esos días."
                      : t.umbral === "bloqueado"
                        ? "Ya tiene una imputación de cargos vigente. El siguiente paso es evaluar sus descargos (art. 31) y lo decide Gerencia, no el sistema."
                        : t.umbral === "aviso"
                          ? `Aún no llega a su umbral: lleva ${t.tardanzas_mes} en ${nombreDelMesLima(mesTard)} y su escalón exige ${t.minimo}.`
                          : undefined}
                    className="rounded-lg border border-tinta/30 px-3 py-1 text-xs text-tinta hover:bg-sand/40 disabled:opacity-40">
                    {ocupado === t.persona_id ? "Generando…" : "Generar borrador"}
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>

        {/* Semáforo de faltas */}
        <div className="mb-6 max-w-3xl overflow-hidden rounded-2xl border border-sand bg-papel">
          <div className="border-b bg-sand/50 px-4 py-2">
            <h2 className="text-sm font-medium">Faltas — últimos 180 días{!cargando && faltas.length > 0 && <span className="font-normal text-taupe"> · {faltas.length}</span>}</h2>
            <p className="mt-0.5 text-xs text-taupe">Umbrales art. 25-h: 4 consecutivas · 6 en 30 días · 16 en 180 días.</p>
          </div>
          {cargando ? (
            <Cargando />
          ) : falloFaltas ? (
            <p className="px-4 py-6 text-sm text-rojo">
              No se pudo leer el semáforo de faltas. <strong>Esto NO significa que no haya nadie.</strong>{" "}
              Vuelve a cargar la página; si sigue igual, avisa antes de dar el periodo por revisado.
            </p>
          ) : faltas.length === 0 ? (
            <p className="px-4 py-6 text-sm text-taupe">Nadie en umbral de faltas. Buena señal.</p>
          ) : (
            <ul className="divide-y">
              {faltas.map((f) => (
                <li key={f.persona_id} id={`falta-${f.persona_id}`} className={`flex flex-wrap items-center justify-between gap-3 scroll-mt-24 px-4 py-3 text-sm transition-colors ${resaltado === `falta-${f.persona_id}` ? "bg-rojo/10" : ""}`}>
                  <span>
                    <strong>{f.nombre}</strong> <span className="text-taupe">· {f.sede}</span>
                    <span className={`ml-2 rounded-full px-2 py-0.5 text-xs ${f.nivel === "rojo" ? "bg-rojo/10 text-rojo" : "bg-ambar/15 text-ambar"}`}>
                      {f.consecutivas} consec · {f.en_30} en 30d · {f.en_180} en 180d
                    </span>
                  </span>
                  <button onClick={() => generar("falta", f.persona_id)}
                    disabled={ocupado === f.persona_id || pendientePorCausal.has(`${f.persona_id}:falta`)}
                    title={pendientePorCausal.has(`${f.persona_id}:falta`)
                      ? "Ya hay un borrador de falta pendiente para esta persona. Revísalo en «Borradores pendientes» antes de generar otro."
                      : undefined}
                    className="rounded-lg border border-tinta/30 px-3 py-1 text-xs text-tinta hover:bg-sand/40 disabled:opacity-40">
                    {ocupado === f.persona_id ? "Generando…" : "Generar borrador"}
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>

        {/* Borradores pendientes de firma */}
        <div ref={borradoresRef} className="mb-6 max-w-3xl scroll-mt-4 overflow-hidden rounded-2xl border border-sand bg-papel">
          <h2 className="border-b bg-sand/50 px-4 py-2 text-sm font-medium">
            Borradores pendientes {borradores.length > 0 && <span className="font-normal text-taupe">· {borradores.length}</span>}
          </h2>
          {borradores.length === 0 ? (
            <p className="px-4 py-6 text-sm text-taupe">No hay borradores por firmar.</p>
          ) : (
            <ul className="divide-y">
              {borradores.map((d) => (
                <li key={d.id} className="px-4 py-3 text-sm">
                  <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                    <span><strong>{nombres.get(d.persona_id) ?? "—"}</strong> <span className="text-taupe">· {CAUSAL_LABEL[d.tipo_causal]} · {NIVEL_LABEL[d.nivel]}</span></span>
                    <div className="flex items-center gap-2">
                      {(firmantes[d.id] ?? []).length > 0 && (
                        <select
                          value={firmanteElegido[d.id]
                            ?? (firmantes[d.id] ?? []).find((f) => f.persona_id === yo?.id)?.persona_id
                            ?? (firmantes[d.id] ?? [])[0]?.persona_id
                            ?? ""}
                          onChange={(e) => setFirmanteElegido((m) => ({ ...m, [d.id]: e.target.value }))}
                          className="rounded-lg border border-sand bg-papel px-2 py-1 text-xs text-tinta"
                          title="Quién firma este documento">
                          {(firmantes[d.id] ?? []).map((f) => (
                            <option key={f.persona_id} value={f.persona_id}>
                              {f.nombre} · {f.cargo}{f.tiene_firma ? "" : " (sin firma escaneada)"}
                            </option>
                          ))}
                        </select>
                      )}
                      <button onClick={() => router.push(`/admin/disciplina/memo/${d.id}`)}
                        className="rounded-lg border border-tinta/30 px-3 py-1 text-xs text-tinta hover:bg-sand/40">Ver memo</button>
                      {/* El botón que sale es el del paso que toca, y en una
                          amonestación o una suspensión los tres primeros NO son
                          Firmar: comunicar los cargos, esperar el plazo y
                          valorar el descargo (arts. 55.2 y 19.3 del RIT).

                          Esto faltaba. La base lo exige desde la 0212 y las dos
                          funciones de pantalla se escribieron entonces, pero el
                          JSX no: «Firmar» salía siempre y la base lo rechazaba
                          con un error que no tenía cómo cumplirse desde acá.

                          La imputación y el despido no pasan por esta cascada —
                          siguen el procedimiento del art. 57, con el plazo del
                          art. 31 de la LPCL, que es otro y más largo. */}
                      {exigeDescargo && esGradual(d.nivel) && d.cargos_comunicados_at === null ? (
                        <>
                          <button onClick={() => void comunicarCargos(d)} disabled={ocupado === d.id}
                            title="Art. 55.2 del RIT: antes de una amonestación o una suspensión hay que comunicarle los cargos y darle su plazo de descargo."
                            className="rounded-lg bg-tinta px-3 py-1 text-xs font-medium text-crema disabled:opacity-40">
                            {ocupado === d.id ? "Comunicando…" : "Comunicar cargos"}
                          </button>
                          {/* Para lo que ya ocurrió. En texto pequeño y al lado,
                              no como botón: el camino normal es comunicar hoy;
                              este es la excepción de quien ya lo hizo y no tuvo
                              dónde anotarlo. */}
                          <button onClick={() => abrirDeclaracion(d)} disabled={ocupado === d.id}
                            title="Registrar una comunicación que ya ocurrió, con la fecha en que ocurrió. El plazo se cuenta desde esa fecha, no desde hoy."
                            className="text-xs text-taupe underline disabled:opacity-40">ya se lo comuniqué</button>
                        </>
                      ) : exigeDescargo && esGradual(d.nivel) && plazoAbierto(d) ? (
                        <span className="text-xs text-taupe">Esperando su descargo</span>
                      ) : exigeDescargo && esGradual(d.nivel) && d.descargo_acogido === null ? (
                        /* Las cuatro salidas salen de ETIQUETA_DESCARGO y no de
                           una lista escrita acá: son las mismas que acepta
                           fn_expediente_valorar_descargo. */
                        <select value="" disabled={ocupado === d.id}
                          onChange={(e) => { if (e.target.value) void valorarDescargo(d, e.target.value); }}
                          title="Art. 19.3 del RIT: hay que dejar por escrito si el descargo se acoge, aunque no se haya presentado ninguno."
                          className="rounded-lg border border-tinta/30 bg-papel px-2 py-1 text-xs text-tinta disabled:opacity-40">
                          <option value="">Valorar el descargo…</option>
                          {Object.entries(ETIQUETA_DESCARGO).map(([valor, etiqueta]) => (
                            <option key={valor} value={valor}>{etiqueta}</option>
                          ))}
                        </select>
                      ) : (
                        /* Sin nadie a quien ofrecer, firmar solo produciría un
                           error de la base. Es el caso del art. 54.4 c): DO ve
                           el borrador del despido porque lo instruye, pero la
                           carta la suscribe la Gerencia General en persona.
                           Se compara con `=== 0` y no con `?? []` a propósito:
                           la clave ausente es «todavía no se preguntó», y ahí el
                           botón se deja pasar para que decida la base. */
                        <button onClick={() => firmar(d.id)}
                          disabled={ocupado === d.id || firmantes[d.id]?.length === 0}
                          title={firmantes[d.id]?.length === 0
                            ? `Un documento de nivel ${NIVEL_LABEL[d.nivel].toLowerCase()} no lo puedes suscribir tú (art. 54.4 del Reglamento).`
                            : "Firmar este documento"}
                          className="rounded-lg bg-tinta px-3 py-1 text-xs font-medium text-crema disabled:opacity-40">Firmar</button>
                      )}
                      {/* El descargo previo también se archiva, y contra el
                          borrador: la 0212 abrió esa puerta en
                          fn_expediente_puede_recibir_descargo y hasta ahora solo
                          la imputación entregada tenía dónde subirlo. */}
                      {esGradual(d.nivel) && d.cargos_comunicados_at !== null
                        && !(adjuntos.get(d.id) ?? []).some((a) => a.tipo === "descargo") && (
                        <button onClick={() => void abrirCargo(d.id, "descargo")} disabled={ocupado === d.id}
                          className="text-xs text-taupe underline disabled:opacity-40">subir su descargo</button>
                      )}
                      {(adjuntos.get(d.id) ?? []).filter((a) => a.tipo === "descargo").map((a) => (
                        <button key={a.id} onClick={() => void verAdjunto(a.storage_path)}
                          className="text-xs font-medium underline">Ver descargo</button>
                      ))}
                      <button onClick={() => anular(d.id)} disabled={ocupado === d.id}
                        className="rounded border border-rojo/30 px-2 py-0.5 text-xs text-rojo hover:bg-rojo/10 disabled:opacity-40">Anular</button>
                    </div>
                  </div>
                  <p className="mt-1 text-xs text-taupe">Hechos: {fechasDe(d.hechos)}</p>
                  {/* En qué punto del art. 55.2 está este borrador, escrito en
                      la fila. Sin esta línea, uno que hoy no se puede firmar se
                      ve igual que uno que sí, y el porqué solo aparecía al
                      pulsar Firmar — cuando ya no había nada que hacer. */}
                  {exigeDescargo && esGradual(d.nivel) && (
                    <p className={`mt-1 text-xs ${d.descargo_acogido === null ? "text-rojo" : "text-taupe"}`}>
                      {d.cargos_comunicados_at === null
                        ? "Falta comunicarle los cargos por escrito —los hechos con sus fechas, la norma que se le imputa y el detalle de la medición— y darle dos días hábiles para su descargo (art. 55.2 del RIT). Hasta entonces no se puede firmar."
                        /* Los sellos nunca cierran la frase: `selloLima`
                           termina en «p. m.» y un punto detrás se lee «p. m..». */
                        : plazoAbierto(d)
                          ? `Cargos comunicados el ${selloLima(d.cargos_comunicados_at)} · su plazo de descargo vence el ${d.descargo_vence_at ? selloLima(d.descargo_vence_at) : "—"} — firmar antes invalidaría la sanción.`
                          : d.descargo_acogido === null
                            ? `El plazo venció el ${d.descargo_vence_at ? selloLima(d.descargo_vence_at) : "—"} · falta dejar por escrito si su descargo se acoge, y hacerlo constar también si no presentó ninguno (art. 19.3 del RIT).`
                            /* «descargo» no se antepone a `sin_descargo`: su
                               etiqueta ya es una frase entera y saldría
                               «descargo no presentó descargo». */
                            : `Cargos comunicados el ${selloLima(d.cargos_comunicados_at)} · ${d.descargo_acogido === "sin_descargo" ? "" : "descargo "}${ETIQUETA_DESCARGO[d.descargo_acogido] ?? d.descargo_acogido}${d.descargo_valoracion ? `: ${d.descargo_valoracion}` : ""}`}
                    </p>
                  )}
                  {/* Lo que se declaró, a la vista de quien va a firmar. Una
                      comunicación declarada dice de quién es la palabra que la
                      sostiene, y eso hay que poder leerlo ANTES de la firma, no
                      encontrarlo en la base el día que alguien la discuta. */}
                  {d.observacion && (
                    <p className="mt-1 whitespace-pre-line text-xs text-taupe">{d.observacion}</p>
                  )}
                  {/* Numeral 60.5: sin constancia del Reglamento no se puede
                      fundar una amonestación ni una suspensión. Se avisa acá,
                      en el borrador, y no al pulsar Firmar: lo que no se puede
                      deshacer es haberla citado a descargo para nada.
                      La imputación y el despido no lo llevan — se fundan en el
                      art. 25 de la LPCL, que rige por ley y no por entrega. */}
                  {sinConstancia.has(d.persona_id) && d.nivel !== "imputacion" && d.nivel !== "despido" && (
                    <p className="mt-1 rounded border border-rojo/30 bg-rojo/5 px-2 py-1 text-xs text-rojo">
                      Sin constancia del Reglamento. Este documento no se va a poder firmar hasta
                      que se le entregue y quede registrada en Normas — también vale en papel.
                    </p>
                  )}
                  {/* El art. 32 de la LPCL exige que la carta de despido diga
                      la causa Y la fecha de cese. Se fija acá, en el borrador,
                      porque después de firmar el documento ya no se edita. */}
                  {d.nivel === "despido" && (
                    <label className="mt-1 flex flex-wrap items-center gap-2 text-xs text-taupe">
                      Fecha de cese (art. 32):
                      <input type="date" defaultValue={d.fecha_cese ?? ""}
                        onBlur={(e) => guardarFechaCese(d, e.target.value)}
                        className="rounded border px-2 py-1" />
                      {!d.fecha_cese && (
                        <span className="text-rojo">sin fecha, la carta saldría incompleta</span>
                      )}
                    </label>
                  )}
                  {d.nivel === "suspension" && (() => {
                    const r = rangoSuspension(d);
                    const fuera = d.suspension_dias !== null
                      && (d.suspension_dias < r.min || d.suspension_dias > r.max);
                    return (
                    <label className="mt-1 flex flex-wrap items-center gap-2 text-xs text-taupe">
                      Días de suspensión:
                      {/* El campo ofrece SOLO lo que el Reglamento admite para
                          este documento, que no es siempre 1-3: la primera por
                          tardanzas es de 1 a 2 (19.2 c) y la segunda tiene que
                          ser mayor que la primera (19.2 d). El candado de verdad
                          está en la base (mig. 0294) — un `max` de HTML no
                          impide escribir ni enviar, porque acá no hay formulario
                          que validar sino un `onBlur` que llama a la RPC.
                          `onWheel` con blur porque un `<input type="number">`
                          cambia de valor con la rueda del mouse cuando el cursor
                          pasa por encima al hacer scroll: no es como llegó el 10
                          de agosto —ese se tecleó a propósito, probando— pero
                          sigue siendo una forma de mover días de sueldo sin
                          querer. */}
                      <input type="number" min={r.min} max={r.max} defaultValue={d.suspension_dias ?? r.min}
                        onWheel={(e) => e.currentTarget.blur()}
                        onBlur={(e) => guardarDias(d, Number(e.target.value))}
                        className={`w-16 rounded border px-2 py-1 ${fuera ? "border-rojo text-rojo" : ""}`} />
                      <span className={fuera ? "text-rojo" : undefined}>
                        {r.min === r.max ? `solo ${r.min}` : `de ${r.min} a ${r.max}`}
                        {r.previa !== null
                          ? ` · su anterior fue de ${r.previa}, y el numeral 19.2 d) pide que ésta sea mayor`
                          : d.tipo_causal === "tardanza"
                            ? " · es la primera, y el numeral 19.2 c) la topa en dos"
                            : " · numeral 54.5"}
                      </span>
                      {fuera && (
                        <span className="text-rojo">
                          Los {d.suspension_dias} de ahora quedan fuera de ese rango: corrígelo antes de firmar.
                        </span>
                      )}
                      {/* Desde cuándo. El sistema propone, pero la fecha la
                          decide quien tramita: entre generar el borrador y
                          firmarlo pueden pasar días, y una suspensión fijada
                          para una fecha ya trabajada no sanciona nada. */}
                      desde:
                      <input type="date" defaultValue={d.suspension_desde ?? ""} min={hoyLima()}
                        onBlur={(e) => e.target.value && e.target.value !== d.suspension_desde
                          && guardarDias(d, d.suspension_dias ?? 1, e.target.value)}
                        className="rounded border px-2 py-1" />
                      {/* Las fechas una por una cuando se saltan un descanso:
                          «del 23 al 27» sobre días no contiguos mete en la
                          sanción dos días que la persona sí tenía libres. */}
                      {d.suspension_fechas?.length
                        ? <span>{d.suspension_fechas.map(fechaCorta).join(", ")}</span>
                        : d.suspension_desde && <span>del {fechaCorta(d.suspension_desde)}{d.suspension_hasta ? ` al ${fechaCorta(d.suspension_hasta)}` : ""}</span>}
                      {/* La suspensión que ya pasó no suspende. Se avisa en el
                          borrador porque después de firmar el documento ya no
                          se edita, y corregirlo cuesta una anulación. */}
                      {(d.suspension_fechas?.[0] ?? d.suspension_desde ?? "9999-12-31") <= hoyLima() && (
                        <span className="text-rojo">
                          esos días ya empezaron: si firmas hoy, la sanción no tendría efecto real
                        </span>
                      )}
                    </label>
                    );
                  })()}
                  {/* El día de una comunicación que YA ocurrió. Panel en la
                      fila, con el mismo aire que el de subir un papel: el día
                      se elige en un calendario en vez de teclearse en un
                      `prompt`, que es lo que dejaba la fila congelada cuando
                      alguien escribía 04/09/2026. Nace en hoy, se corrige en
                      un clic, y no admite un día futuro. */}
                  {declarando === d.id && (
                    <div className="mt-3 rounded-lg border border-sand bg-sand/20 p-3">
                      <p className="mb-2 text-xs text-taupe">
                        ¿Qué día se le comunicaron los cargos a {nombres.get(d.persona_id) ?? "esta persona"}?
                        Desde ese día corren los dos días hábiles de descargo; si todavía no han pasado,
                        el documento seguirá sin poder firmarse. Al continuar se te pedirá cómo consta esa
                        comunicación.
                      </p>
                      <label className="flex flex-col gap-1 text-xs">
                        Día de la comunicación
                        <input type="date" value={fechaCargos} max={hoyLima()}
                          onChange={(e) => setFechaCargos(e.target.value)}
                          className="w-44 rounded border px-2 py-1 text-xs" />
                      </label>
                      <div className="mt-2 flex items-center gap-2">
                        <button onClick={() => void declararCargos(d)} disabled={ocupado === d.id}
                          className="rounded-lg bg-tinta px-3 py-1 text-xs font-medium text-crema disabled:opacity-40">
                          {ocupado === d.id ? "Registrando…" : "Continuar"}
                        </button>
                        <button onClick={() => setDeclarando(null)}
                          className="rounded-lg border px-3 py-1 text-xs">Cancelar</button>
                      </div>
                    </div>
                  )}
                  {subiendoCargo?.id === d.id && (
                    <FormularioCargo
                      tipo={subiendoCargo.tipo}
                      /* Un borrador no tiene entrega que fechar: lo que se
                         archiva acá es el descargo previo, no el cargo. */
                      pideFecha={false}
                      entregadoEl={null}
                      fecha={fechaEntrega} nota={notaCargo} testigo={testigoCargo}
                      progreso={progresoCargo} ocupado={ocupado === d.id}
                      alElegirArchivo={setArchivoCargo}
                      alCambiarFecha={setFechaEntrega}
                      alCambiarNota={setNotaCargo} alCambiarTestigo={setTestigoCargo}
                      alGuardar={() => void guardarCargo()}
                      alCancelar={() => setSubiendoCargo(null)}
                    />
                  )}
                </li>
              ))}
            </ul>
          )}
        </div>

        {/* Firmados — pendientes de entrega */}
        {firmados.length > 0 && (
          <div className="max-w-3xl overflow-hidden rounded-2xl border border-sand bg-papel">
            <h2 className="border-b bg-sand/50 px-4 py-2 text-sm font-medium">Firmados — por entregar · {firmados.length}</h2>
            <ul className="divide-y">
              {firmados.map((d) => (
                <li key={d.id} className="px-4 py-3 text-sm">
                  <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                    <span>
                      <strong>{nombres.get(d.persona_id) ?? "—"}</strong>{" "}
                      <span className="text-taupe">· {CAUSAL_LABEL[d.tipo_causal]} · {NIVEL_LABEL[d.nivel]} · {d.correlativo}</span>
                    </span>
                    <div className="flex items-center gap-2">
                      <button onClick={() => router.push(`/admin/disciplina/memo/${d.id}`)}
                        className="rounded-lg border border-tinta/30 px-3 py-1 text-xs text-tinta hover:bg-sand/40">Ver memo</button>
                      {/* El camino que deja evidencia es el fácil. Marcar
                          entregado sin papel sigue siendo posible —una entrega
                          por correo certificado es válida y su cargo llega
                          días después— pero deja de ser el atajo. */}
                      <button onClick={() => void abrirCargo(d.id, "cargo_firmado")} disabled={ocupado === d.id}
                        className="rounded-lg bg-tinta px-3 py-1 text-xs font-medium text-crema disabled:opacity-40">
                        Subir cargo firmado
                      </button>
                      <button onClick={() => void abrirCargo(d.id, "acta_negativa")} disabled={ocupado === d.id}
                        className="text-xs text-taupe underline disabled:opacity-40">se negó a firmar</button>
                      <details className="text-xs text-taupe">
                        <summary className="cursor-pointer">entregar sin papel</summary>
                        <div className="mt-2 flex items-center gap-2">
                          <select value={medio[d.id] ?? "fisico"} onChange={(e) => setMedio((m) => ({ ...m, [d.id]: e.target.value }))}
                            className="rounded border bg-crema px-2 py-1 text-xs">
                            <option value="fisico">Físico</option>
                            <option value="correo">Correo</option>
                            <option value="notarial">Notarial</option>
                          </select>
                          <button onClick={() => entregar(d.id)} disabled={ocupado === d.id}
                            className="rounded-lg border border-tinta/30 px-3 py-1 text-xs text-tinta hover:bg-sand/40 disabled:opacity-40">Marcar entregado</button>
                        </div>
                        <p className="mt-1 max-w-xs">
                          El cargo se puede subir después: no pisa la fecha de entrega que quede acá.
                        </p>
                      </details>
                      <button onClick={() => reabrirParaCambiarFirmante(d.id)} disabled={ocupado === d.id}
                        className="rounded-lg border border-taupe/30 px-3 py-1 text-xs text-taupe hover:bg-sand/40 disabled:opacity-40">Cambiar firmante</button>
                    </div>
                  </div>
                  {/* La firma, no la creación del borrador: de la firma cuelgan
                      los plazos, y entre una y otra pueden pasar días. */}
                  <p className="mt-1 text-xs text-taupe">Firmado {selloLima(d.firmado_at ?? d.creado_at)}</p>

                  {subiendoCargo?.id === d.id && (
                    <FormularioCargo
                      tipo={subiendoCargo.tipo}
                      pideFecha={subiendoCargo.tipo === "cargo_firmado" || subiendoCargo.tipo === "acta_negativa"}
                      entregadoEl={null}
                      fecha={fechaEntrega} nota={notaCargo} testigo={testigoCargo}
                      progreso={progresoCargo} ocupado={ocupado === d.id}
                      alElegirArchivo={setArchivoCargo}
                      alCambiarFecha={setFechaEntrega}
                      alCambiarNota={setNotaCargo} alCambiarTestigo={setTestigoCargo}
                      alGuardar={() => void guardarCargo()}
                      alCancelar={() => setSubiendoCargo(null)}
                    />
                  )}
                </li>
              ))}
            </ul>
          </div>
        )}

        {/* ── Entregados ──────────────────────────────────────────────────
            Antes desaparecían al entregarse: subías el cargo y no veías que
            hubiera quedado, y para consultar el papel de una entrega de hace
            dos meses no había ningún sitio. Plegado por defecto para que la
            pantalla siga enfocada en lo que falta hacer. */}
        {entregados.length > 0 && (
          <div id="entregados" className="mt-4 max-w-3xl scroll-mt-4 overflow-hidden rounded-2xl border border-sand bg-papel">
            <button onClick={() => setVerCerrados((v) => !v)}
              className="flex w-full items-center justify-between border-b bg-sand/50 px-4 py-2 text-left text-sm font-medium">
              <span>Entregados · {entregados.length}</span>
              <span className="text-xs font-normal text-taupe">
                {entregados.filter((d) => (adjuntos.get(d.id) ?? []).length === 0).length > 0 && (
                  <span className="text-rojo">
                    {entregados.filter((d) => (adjuntos.get(d.id) ?? []).length === 0).length} sin cargo archivado ·{" "}
                  </span>
                )}
                {verCerrados ? "ocultar" : "ver"}
              </span>
            </button>
            {verCerrados && (
              <ul className="divide-y">
                {entregados.map((d) => {
                  const papeles = adjuntos.get(d.id) ?? [];
                  return (
                    <li key={d.id} className="px-4 py-3 text-sm">
                      <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                        <span>
                          <strong>{nombres.get(d.persona_id) ?? "—"}</strong>{" "}
                          <span className="text-taupe">· {CAUSAL_LABEL[d.tipo_causal]} · {NIVEL_LABEL[d.nivel]} · {d.correlativo}</span>
                        </span>
                        <div className="flex flex-wrap items-center gap-2">
                          <button onClick={() => router.push(`/admin/disciplina/memo/${d.id}`)}
                            className="rounded-lg border border-tinta/30 px-3 py-1 text-xs text-tinta hover:bg-sand/40">Ver memo</button>
                          {papeles.map((a) => (
                            <button key={a.id} onClick={() => void verAdjunto(a.storage_path)}
                              className="text-xs font-medium underline">
                              {ETIQUETA_PAPEL[a.tipo as TipoPapel] ?? "Ver papel"}
                            </button>
                          ))}
                          {!papeles.some((a) => a.tipo === "cargo_firmado" || a.tipo === "acta_negativa") && (
                            <button onClick={() => void abrirCargo(d.id, "cargo_firmado")}
                              className="rounded-lg border border-rojo/40 px-3 py-1 text-xs text-rojo">Subir cargo</button>
                          )}
                          {/* Solo la imputación abre un plazo de descargo, así que
                              solo ella lo pide. La base rechaza lo demás igual. */}
                          {d.nivel === "imputacion" && !papeles.some((a) => a.tipo === "descargo") && (
                            <button onClick={() => void abrirCargo(d.id, "descargo")}
                              className="rounded-lg border border-tinta/30 px-3 py-1 text-xs text-tinta hover:bg-sand/40">
                              Subir su descargo
                            </button>
                          )}
                          {/* Cerrar el procedimiento. Sin esto el semáforo pide la
                              misma decisión durante doce meses. */}
                          {d.nivel === "imputacion" && !d.resuelto_at && (
                            <>
                              <button onClick={() => void resolver(d, "archivado")} disabled={ocupado === d.id}
                                className="rounded-lg border border-tinta/30 px-3 py-1 text-xs text-tinta hover:bg-sand/40 disabled:opacity-40">
                                Archivar sin sancionar
                              </button>
                              <button onClick={() => void resolver(d, "despido")} disabled={ocupado === d.id}
                                className="rounded-lg border border-rojo/40 px-3 py-1 text-xs text-rojo hover:bg-rojo/10 disabled:opacity-40">
                                Se resolvió con despido
                              </button>
                            </>
                          )}
                          {/* Anular NO es lo mismo que archivar, y por eso está
                              aparte y en texto pequeño: archivar cierra un
                              procedimiento que se siguió bien; anular retira un
                              documento que no debió emitirse. */}
                          <button onClick={() => anular(d.id, true)} disabled={ocupado === d.id}
                            title="Retira el documento por un defecto propio. Distinto de archivar: anular devuelve el escalón al peldaño anterior."
                            className="text-xs text-taupe underline disabled:opacity-40">
                            anular
                          </button>
                        </div>
                      </div>
                      <p className="mt-1 text-xs text-taupe">
                        Entregado {d.entregado_at ? selloLima(d.entregado_at) : "—"}
                        {d.medio_entrega && ` · ${MEDIO_ENTREGA[d.medio_entrega] ?? d.medio_entrega}`}
                        {d.entrega_testigo_nombre && ` · testigo: ${d.entrega_testigo_nombre}`}
                        {!papeles.some((a) => a.tipo === "cargo_firmado" || a.tipo === "acta_negativa") && (
                          <span className="text-rojo"> · sin el papel archivado</span>
                        )}
                      </p>
                      {d.nivel === "imputacion" && (
                        d.resuelto_at ? (
                          <p className="mt-1 text-xs text-taupe">
                            <strong>{d.resuelto_resultado === "despido" ? "Resuelto con despido" : "Archivado sin sancionar"}</strong>
                            {" "}el {selloLima(d.resuelto_at)} — {d.resuelto_motivo}
                          </p>
                        ) : (
                          <p className="mt-1 text-xs text-rojo">
                            Procedimiento abierto. Tras evaluar sus descargos, ciérralo con uno de los dos botones —
                            si no, el semáforo seguirá pidiendo esta decisión durante doce meses.
                          </p>
                        )
                      )}
                      {subiendoCargo?.id === d.id && (
                        <FormularioCargo
                          tipo={subiendoCargo.tipo}
                          pideFecha={false}
                          entregadoEl={d.entregado_at ? selloLima(d.entregado_at) : null}
                          fecha={fechaEntrega} nota={notaCargo} testigo={testigoCargo}
                          progreso={progresoCargo} ocupado={ocupado === d.id}
                          alElegirArchivo={setArchivoCargo}
                          alCambiarFecha={setFechaEntrega}
                          alCambiarNota={setNotaCargo} alCambiarTestigo={setTestigoCargo}
                          alGuardar={() => void guardarCargo()}
                          alCancelar={() => setSubiendoCargo(null)}
                        />
                      )}
                    </li>
                  );
                })}
              </ul>
            )}
          </div>
        )}
      </main>
    </div>
  );
}

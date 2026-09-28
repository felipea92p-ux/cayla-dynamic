"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Cargando } from "@/components/cargando";
import { Marca } from "@/components/marca";
import { Boton } from "@/components/ui/boton";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { EMPRESA, TZ_LIMA, type Rol } from "@cayla-dynamic/shared";
import { AREAS_FALLBACK, areaNombre, parseAreas, type Area } from "@/lib/areas";

/**
 * El representante legal de CAYLA. NO vive en `EMPRESA` (packages/shared) y esa
 * separación es la misma que ordena todo este archivo.
 *
 * La razón social y el RUC son IDENTIDAD de la empresa: dicen lo mismo en
 * cualquier papel que CAYLA emita, así que se unificaron el 2026-08-19. Quién
 * SUSCRIBE, en cambio, depende del documento: `fn_expediente_puede_actuar` deja
 * a una encargada firmar un memo verbal o de amonestación de su sede. Una
 * constante compartida que se llamara «el firmante» invitaría a imprimir
 * gerencia encima de esa firma — el defecto que este archivo ya corrigió dos
 * veces, y que en un documento disciplinario se paga el día que alguien lo
 * discute.
 *
 * Se usa en UN solo caso, y no es un valor por defecto: cuando el memo consta
 * firmado pero RLS impide leer la ficha de quien lo firmó (ver el bloque de
 * carga). En un borrador sin firmar no se rellena nada.
 */
const REPRESENTANTE_LEGAL = { nombre: "Alvarez Pereyra Felipe Miguel", cargo: "Gerencia General" };

function fechaCorta(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "long", year: "numeric", timeZone: "UTC" })
    .format(new Date(Date.UTC(y, m - 1, d)));
}
/**
 * Fecha en letras, aceptando tanto una fecha plana (`2026-07-30`) como un
 * instante (`2026-07-30T20:03:00Z`).
 *
 * La distinción NO es cosmética. Un `timestamptz` formateado en UTC se corre un
 * día para cualquier entrega hecha después de las 7 p.m. hora de Lima, y de la
 * fecha de entrega cuelgan los seis días de descargo del art. 31. Una fecha
 * plana, en cambio, ya viene sin huso y hay que fijarla a mediodía UTC para que
 * no retroceda al pintarla.
 */
function fechaLarga(iso: string): string {
  const fmt = (d: Date, tz: string) =>
    new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "long", year: "numeric", timeZone: tz }).format(d);
  if (iso.length === 10) {
    const [y, m, d] = iso.split("-").map(Number);
    return fmt(new Date(Date.UTC(y, m - 1, d)), "UTC");
  }
  return fmt(new Date(iso), TZ_LIMA);
}
/** El nivel dicho dentro de una frase, en minúscula. */
const NIVEL_EN_PROSA: Record<string, string> = {
  verbal: "llamada verbal de atención",
  amonestacion: "amonestación escrita",
  suspension: "suspensión sin goce de haber",
  imputacion: "imputación de cargos",
  despido: "carta de despido",
};
function mesDe(iso: string | null): string {
  if (!iso) return "";
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { month: "long", year: "numeric", timeZone: "UTC" }).format(new Date(Date.UTC(y, m - 1, d)));
}

const TITULO: Record<string, string> = {
  verbal: "Acta de llamada verbal de atención",
  amonestacion: "Amonestación escrita",
  suspension: "Suspensión sin goce de haber",
  imputacion: "Imputación de cargos — carta de preaviso",
  despido: "Carta de despido por causa justa",
};
const CAUSAL: Record<string, string> = { tardanza: "tardanzas reiteradas", falta: "inasistencias injustificadas", conducta: "conducta" };

/**
 * Qué inciso del art. 25 de la LPCL corresponde a cada causal.
 *
 * ⚠️ TARDANZA VA POR EL INCISO h), NO POR EL a). Hasta el 2026-08-10 este mapa
 * era un ternario que mandaba la tardanza al a) y todo lo demás al h), y estaba
 * mal en los dos extremos.
 *
 * El h) nombra la conducta literalmente: «…la impuntualidad reiterada, si ha
 * sido acusada por el empleador, siempre que se hayan aplicado sanciones
 * disciplinarias previas de amonestaciones escritas y suspensiones». La Casación
 * de Lambayeque sobre despido por tardanzas razona sobre ese inciso, y
 * `docs/disciplina-tardanzas-faltas/00-normativa-y-diseno.md` §1.3 ya lo decía
 * — eran las plantillas las que estaban equivocadas.
 *
 * Y NO ES SOLO CORRECCIÓN FORMAL: el h) es el camino exigente, porque pide
 * amonestación escrita Y suspensión previas. Imputar por el a) —el genérico de
 * buena fe laboral— teniendo el h) disponible le regala a la otra parte el
 * argumento de que la empresa esquivó los requisitos de la norma específica.
 *
 * `conducta` sí va por el a): es el incumplimiento de obligaciones de trabajo
 * que supone quebrantamiento de la buena fe laboral. Antes caía en el h) por
 * descarte, que habla de ausencias y de impuntualidad — nada que ver.
 */
const INCISO_ART25: Record<string, string> = {
  tardanza: "inciso h)",   // impuntualidad reiterada
  falta: "inciso h)",      // abandono y ausencias injustificadas
  conducta: "inciso a)",   // incumplimiento de obligaciones / buena fe laboral
};

interface Hecho { fecha: string; minutos?: number }
/** Una sanción anterior de la misma causal, para citarla en la imputación. */
interface Previa { correlativo: string | null; nivel: string; firmado_at: string | null; entregado_at: string | null }
interface Doc {
  id: string; correlativo: string | null; persona_id: string; tipo_causal: string; nivel: string; estado: string;
  periodo_desde: string | null; periodo_hasta: string | null; hechos: Hecho[];
  suspension_dias: number | null; suspension_desde: string | null; suspension_hasta: string | null;
  // Las fechas EXACTAS (mig. 0075). Cuando la suspensión se salta un descanso
  // los días dejan de ser contiguos —jueves, viernes y lunes— e imprimir «del
  // 23 al 27» mete en la sanción dos días en los que la persona sí podía estar
  // en su casa. Es el caso real del 25/07/2026: el memo declaró tres días y el
  // efecto fue uno.
  suspension_fechas: string[] | null;
  /** Fecha de cese DECLARADA en la carta (art. 32 LPCL, mig. 0205). */
  fecha_cese: string | null;
  firmante_id: string | null; firmado_at: string | null; creado_at: string;
  // Constancia digital DEL SANCIONADO (0404) — distinta de la firma de arriba,
  // que es de quien EMITE. Nunca reemplaza el «Recibí conforme» en físico.
  firma_sancionado: string | null;
  firma_sancionado_confirmada_at: string | null;
  sancionado_rechazo_firma_at: string | null;
}
interface Persona { nombres: string; apellidos: string; documento: string | null; funcion: string; sede_base_id: string; rol: string }

export default function MemoPage() {
  const params = useParams();
  const id = (params?.id as string) ?? "";
  const router = useRouter();
  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  const [doc, setDoc] = useState<Doc | null>(null);
  const [persona, setPersona] = useState<Persona | null>(null);
  // Las sanciones anteriores de la MISMA causal, para enumerarlas en la
  // imputación. El inciso h) del art. 25 no pide que existan: pide que se hayan
  // aplicado, y la Casación de Lambayeque manda probarlo. Decir «las que
  // constan en su legajo» obliga a quien lea el papel a ir a buscar el legajo;
  // nombrarlas hace que el documento se sostenga solo.
  // ── LAS CITAS DE ESTE MEMO SON DEL RIT v4.0, Y ESO HAY QUE COMPROBARLO ──
  //
  // Hasta el 2026-08-15 citaban la versión 3.0, y el v4.0 renumeró el articulado
  // entero. No eran citas «un poco viejas»: apuntaban a artículos que hoy dicen
  // otra cosa. El memo invocaba el «artículo 14.4» para la vigencia de doce
  // meses del antecedente —el 14 del v4.0 es SOBRETIEMPO— y el «artículo 7»
  // para la escalera de tardanzas —el 7 es PERIODO DE PRUEBA—.
  //
  // Un descargo que abra el Reglamento por donde el memo le dice encuentra otra
  // materia, y a partir de ahí el documento entero deja de merecer crédito.
  //
  // El mapeo, verificado uno por uno contra docs/reglamento-interno-de-trabajo.md:
  //   14.4 → 56.1   vigencia de doce meses del antecedente
  //   14.2 → 54.5   límites de la suspensión sin goce
  //    7 c) → 19.2 c)  primera suspensión por tardanzas
  //   8.3-a → 53.2 c)  la inasistencia injustificada como falta
  //   8.3-b → 21.2 b)  segundo umbral de inasistencias
  //   8.2  → 20.4   plazo de cuarenta y ocho horas para justificar
  //   13-c → art. 20  inasistencias
  //
  // Si mañana sale una versión 5.0, esto se revisa ANTES de emitir nada.

  const [previas, setPrevias] = useState<Previa[]>([]);
  const [areas, setAreas] = useState<Area[]>(AREAS_FALLBACK);
  const [sede, setSede] = useState<string>("");
  // ⚠️ ARRANCAN EN null, NO en la constante de la empresa, y es el punto entero.
  //
  // Un BORRADOR tiene `firmante_id` en null por definición: nadie lo ha firmado
  // todavía. Con el representante legal puesto por defecto, el papel salía
  // impreso «De: Alvarez Pereyra Felipe Miguel · Gerencia General» y con la
  // misma línea bajo la firma — un documento disciplinario afirmando que lo
  // suscribió Gerencia General cuando no lo suscribió nadie. Eso no es un
  // defecto de estilo: es el papel que se le entrega a una persona y el que
  // aguanta o no cuando alguien lo discute.
  //
  // Sin firmante NO se inventa uno: se imprime «Pendiente de firma» (ver render).
  const [firmante, setFirmante] = useState<string | null>(null);
  // El cargo impreso sale de QUIÉN firmó, no de una constante. Estaba fijo en
  // "Gerencia General": como fn_expediente_puede_actuar sí deja a una encargada
  // suscribir un memo verbal o de amonestación de su sede, el papel salía
  // diciendo que lo firmó Gerencia General. Un documento disciplinario que
  // miente sobre quién lo suscribió se cae si alguien lo discute.
  const [cargoFirmante, setCargoFirmante] = useState<string | null>(null);
  // Firmado, pero no se pudo leer la fila de quien firma. Es distinto de «no
  // hay firmante» y no se trata igual: ver el bloque de carga.
  const [firmanteIlegible, setFirmanteIlegible] = useState(false);
  const [firmaUrl, setFirmaUrl] = useState<string | null>(null);
  const [cargando, setCargando] = useState(true);
  const [err, setErr] = useState<string | null>(null);

  const cargar = useCallback(async () => {
    setCargando(true); setErr(null);
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    const { data: d, error: eD } = await supabase.from("expediente_disciplinario")
      .select("id, correlativo, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos, suspension_dias, suspension_desde, suspension_hasta, suspension_fechas, fecha_cese, firmante_id, firmado_at, creado_at, firma_sancionado, firma_sancionado_confirmada_at, sancionado_rechazo_firma_at")
      .eq("id", id).maybeSingle();
    if (eD || !d) { setErr("No se encontró el documento (o no tienes permiso para verlo)."); setCargando(false); return; }
    const doc = d as unknown as Doc;
    setDoc(doc);
    const ids = [doc.persona_id, doc.firmante_id].filter((x): x is string => Boolean(x));
    // Las áreas se piden a la BASE, no a una lista escrita acá: el catálogo se
    // gestiona desde /admin/areas y una constante local envejecería sola. Si la
    // consulta falla, `parseAreas` cae al respaldo del seed — nunca al código
    // crudo. Hasta hoy el memo imprimía `persona.funcion` tal cual, así que el
    // papel que se entrega a una persona decía «Cargo: calidad_servicio», con
    // guion bajo. En un documento que puede acabar ante un inspector, eso no es
    // un detalle de estilo.
    const [{ data: ps }, { data: sedes }, { data: ar, error: eAr }] = await Promise.all([
      supabase.from("personas").select("id, nombres, apellidos, documento, funcion, sede_base_id, rol").in("id", ids),
      supabase.from("sedes").select("id, codigo"),
      supabase.rpc("fn_areas"),
    ]);
    setAreas(parseAreas(ar, eAr));

    // Las sanciones previas de la MISMA causal, vigentes (12 meses), en orden.
    //
    // Solo las ENTREGADAS. El numeral 56.2 es terminante: «Un documento firmado
    // por la Empresa y no entregado no está vigente, no agrava, no habilita el
    // escalón siguiente y no constituye sanción disciplinaria previa para los
    // efectos del literal h) del artículo 25 de la LPCL».
    //
    // Antes se aceptaban `firmado` y `entregado`. La carta de imputación NOMBRA
    // sus previas una por una, así que una firmada y no entregada colada ahí
    // hacía que el documento afirmara por escrito un hecho falso sobre el
    // requisito mismo que tiene que probar. Y el estado intermedio no es
    // hipotético: la pantalla de Disciplina tiene una sección entera de
    // «Firmados — por entregar».
    // Solo firmadas o entregadas: un borrador no sancionó nada y citarlo sería
    // afirmar en un documento legal algo que no ocurrió.
    const { data: prev } = await supabase.from("expediente_disciplinario")
      .select("correlativo, nivel, firmado_at, entregado_at")
      .eq("persona_id", doc.persona_id)
      .eq("tipo_causal", doc.tipo_causal)
      .eq("estado", "entregado")
      .neq("id", doc.id)
      .gte("firmado_at", new Date(Date.now() - 365 * 24 * 3600 * 1000).toISOString())
      .order("firmado_at", { ascending: true });
    setPrevias((prev as Previa[]) ?? []);
    const pl = (ps as Array<Persona & { id: string }>) ?? [];
    const p = pl.find((x) => x.id === doc.persona_id) ?? null;
    setPersona(p);
    const f = pl.find((x) => x.id === doc.firmante_id);
    if (f) {
      setFirmante(`${f.nombres} ${f.apellidos}`);
      // fn_cargo_de_rol vive en la base (mig. 0074) para que el panel y
      // cualquier otro consumidor impriman exactamente el mismo cargo. Si la
      // función aún no está aplicada, el cargo se queda en null y el papel sale
      // con el NOMBRE de quien firma y sin cargo debajo. Antes caía al valor de
      // la empresa, que a una encargada le imprimía «Gerencia General»: es
      // preferible no decir el cargo que decir uno falso.
      // `f.rol` viaja como texto desde la consulta; la RPC lo espera con el tipo
      // del enum. El cast va contra `Rol` de shared —no contra una lista escrita
      // acá— para que el día que se agregue un rol esto siga diciendo la verdad.
      const { data: cargo } = await supabase.rpc("fn_cargo_de_rol", { p_rol: f.rol as Rol });
      if (typeof cargo === "string" && cargo) setCargoFirmante(cargo);
    } else if (doc.firmante_id) {
      // FIRMADO, pero su fila no vino en la consulta. El caso normal es RLS:
      // `personas_select_supervisor` solo expone la sede propia, así que una
      // encargada que imprime un memo SUYO suscrito por gerencia no puede leer
      // la fila de gerencia. Ese flujo es legítimo y existe a propósito — la
      // firma escaneada se pide por documento justamente para permitirlo.
      //
      // Aquí SÍ se cae al representante legal, y no es lo mismo que inventarlo
      // en un borrador: consta que el documento está firmado, solo no podemos
      // nombrar a quien lo firmó. Se avisa en pantalla (no en el papel) para
      // que quien imprime pueda comprobarlo si el memo no era de gerencia.
      setFirmante(REPRESENTANTE_LEGAL.nombre);
      setCargoFirmante(REPRESENTANTE_LEGAL.cargo);
      setFirmanteIlegible(true);
    }
    // Firma escaneada de quien suscribe ESTE documento. Se pide por documento y
    // no por persona: así la encargada de una sede puede imprimir un memo suyo
    // firmado por gerencia, sin poder pedir la firma de gerencia a secas. La
    // función decide a qué documentos se les estampa: verbal, amonestación,
    // suspensión e imputación (0487). La carta de despido la firma Gerencia a
    // mano y la función no la entrega. La pantalla NO repite esa regla: si lo
    // hiciera, cambiar la función no bastaría para cambiar el papel.
    if (doc.firmante_id) {
      const { data: fu } = await supabase.rpc("fn_firma_de_memo", { p_doc_id: id });
      setFirmaUrl(typeof fu === "string" && fu.startsWith("data:image") ? fu : null);
    }
    const smap = new Map(((sedes as Array<{ id: string; codigo: string }>) ?? []).map((s) => [s.id, s.codigo]));
    if (p) setSede(smap.get(p.sede_base_id) ?? "");
    setCargando(false);
  }, [supabase, router, id]);

  useEffect(() => { void cargar(); }, [cargar]);

  // El nombre con el que se guarda el PDF. En un memo de disciplina importa más
  // que en cualquier otro documento del sistema: son papeles legales sobre una
  // persona concreta, y guardarlos todos como «Dynamic — CAYLA» en la misma
  // carpeta es cómo se acaba entregando el memo de alguien a otra persona.
  // Lleva el correlativo delante cuando existe, para que ordenen solos.
  useTituloDocumento(
    doc && persona
      ? [
          doc.correlativo,
          TITULO[doc.nivel] ?? "Documento disciplinario",
          `${persona.nombres} ${persona.apellidos}`,
        ]
          .filter(Boolean)
          .join(" — ")
      : null,
  );

  const nombre = persona ? `${persona.nombres} ${persona.apellidos}` : "—";
  const n = doc?.hechos?.length ?? 0;
  const esNivel4 = doc?.nivel === "imputacion" || doc?.nivel === "despido";

  function Cuerpo() {
    if (!doc) return null;
    const t = doc.tipo_causal;
    const nivel = doc.nivel;
    if (nivel === "amonestacion" && t === "tardanza") {
      return (
        <>
          <p>El presente memorándum deja constancia de que, durante el mes de <strong>{mesDe(doc.periodo_desde)}</strong>, usted registró <strong>{n} tardanzas</strong>, superando el umbral b) del artículo 7 del Reglamento Interno de Trabajo de {EMPRESA.nombre} (tres o más tardanzas en un mismo mes calendario), según el detalle de las marcaciones que a continuación se indica.</p>
          <p>Las tardanzas detalladas no han sido objeto de sanción disciplinaria previa. El descuento proporcional por el tiempo no laborado, de haberse aplicado en planilla, tiene naturaleza contraprestativa y es independiente de esta sanción; no la sustituye.</p>
          <p>Por lo expuesto, se le impone <strong>AMONESTACIÓN ESCRITA</strong>, que se incorpora a su legajo como antecedente disciplinario con vigencia de doce (12) meses desde su notificación (numeral 56.1 del RIT). Se le exhorta a corregir su puntualidad. La reincidencia dará lugar a <strong>suspensión sin goce de haber</strong> conforme al literal c) del numeral 19.2 del RIT.</p>
        </>
      );
    }
    if (nivel === "amonestacion" && t === "falta") {
      return (
        <>
          <p>El presente memorándum deja constancia de que, correspondiéndole laborar en la(s) fecha(s) que se detalla(n), usted <strong>no concurrió al centro de trabajo ni registró marca alguna</strong> en el sistema de control de asistencia, sin que exista justificación aceptada dentro del plazo previsto en el numeral 20.4 del RIT.</p>
          <p>La inasistencia injustificada constituye falta conforme al literal c) del numeral 53.2 del RIT y contraviene el deber de asistencia y puntualidad (artículo 20 del RIT). El descuento del día no laborado y de la parte proporcional del descanso semanal es independiente de esta sanción.</p>
          <p>Por lo expuesto, se le impone <strong>AMONESTACIÓN ESCRITA</strong>, incorporada a su legajo por doce (12) meses (numeral 56.1 del RIT). Una nueva inasistencia injustificada dará lugar a <strong>suspensión sin goce de haber</strong> (artículo 8.3-b), y la acumulación de ausencias puede configurar causal de despido conforme al artículo 25-h de la LPCL.</p>
        </>
      );
    }
    if (nivel === "suspension") {
      const art = t === "tardanza" ? "literal c) del numeral 19.2" : "literal b) del numeral 21.2";
      return (
        <>
          <p>Habiendo sido usted <strong>amonestado por escrito con anterioridad</strong> por {CAUSAL[t]}, y habiendo reincidido según el detalle que se indica, se configura el {art} del RIT. Estos hechos son nuevos y posteriores a la sanción previa; no se recuenta ninguno ya sancionado.</p>
          {/* Con las fechas exactas se enumeran una por una; sin ellas se cae al
              rango, que es lo único que había antes de la 0075. Un rango sobre
              días no contiguos afirma algo falso sobre el alcance del castigo. */}
          <p>Por lo expuesto, se le impone <strong>SUSPENSIÓN SIN GOCE DE HABER</strong> por <strong>{doc.suspension_dias} día(s)</strong>
            {doc.suspension_fechas?.length
              ? <>, los días <strong>{doc.suspension_fechas.map(fechaCorta).join(", ")}</strong></>
              : doc.suspension_desde && <>, del <strong>{fechaCorta(doc.suspension_desde)}</strong>{doc.suspension_hasta && <> al <strong>{fechaCorta(doc.suspension_hasta)}</strong></>}</>}
            . Durante ese periodo no deberá concurrir al centro de trabajo ni percibirá remuneración (numeral 54.5 del RIT).</p>
          {/* La vigencia se dice aquí igual que en la amonestación. Sin ella, el
              papel no informa cuánto pesa en el legajo — y de esa vigencia
              depende que la siguiente sanción escale o vuelva a empezar. */}
          <p>Esta sanción se incorpora a su legajo como antecedente disciplinario con vigencia de <strong>doce (12) meses</strong> desde su notificación (numeral 56.1 del RIT).</p>
          <p>Se le advierte que, de persistir, {EMPRESA.nombre} iniciará el procedimiento de despido por causa justa previsto en el artículo 31 de la LPCL.</p>
        </>
      );
    }
    if (nivel === "imputacion") {
      const inc = INCISO_ART25[t] ?? "inciso a)";
      return (
        <>
          <p>En cumplimiento del <strong>artículo 31 de la LPCL</strong>, {EMPRESA.nombre} le <strong>imputa los cargos</strong> que se detallan y le otorga un plazo no menor de <strong>seis (6) días naturales</strong>, contados desde la recepción del presente, para que presente por escrito sus descargos ante la Gerencia General.</p>
          {/* Las sanciones previas van NOMBRADAS, no aludidas. El inciso h) no
              exige que existan: exige que se hayan APLICADO, y eso es lo que hay
              que poder probar. Un documento que dice «las que constan en su
              legajo» obliga a abrir el legajo para saber si el requisito se
              cumple; uno que las enumera se defiende solo. */}
          {previas.length > 0 && (
            <p>
              Constan en su legajo las siguientes sanciones disciplinarias previas por la misma causa,
              todas ellas notificadas y con cargo de recepción archivado:{" "}
              {previas.map((s, i) => (
                <span key={s.correlativo ?? i}>
                  {i > 0 ? "; " : ""}
                  <strong>{NIVEL_EN_PROSA[s.nivel] ?? s.nivel}</strong>
                  {s.correlativo ? <> N.º <strong>{s.correlativo}</strong></> : null}
                  {s.entregado_at ? <>, entregada el {fechaLarga(s.entregado_at)}</>
                    : s.firmado_at ? <>, suscrita el {fechaLarga(s.firmado_at)}</> : null}
                </span>
              ))}.
            </p>
          )}
          <p>Los hechos, referidos a {CAUSAL[t]} y precedidos de las sanciones disciplinarias {previas.length > 0 ? "antes detalladas" : "que constan en su legajo"}, configurarían <strong>falta grave</strong> conforme al artículo <strong>25, {inc}</strong>, de la LPCL, en concordancia con el RIT. La presente imputación no afirma su responsabilidad: garantiza su derecho de defensa.</p>
          <p>La causa aquí imputada vincula una eventual carta de despido y no podrá variarse.</p>
        </>
      );
    }
    if (nivel === "despido") {
      const inc = INCISO_ART25[t] ?? "inciso a)";
      return (
        <>
          <p>Evaluados el historial disciplinario y los descargos presentados —o vencido el plazo sin presentarlos—, {EMPRESA.nombre} concluye que usted ha incurrido en <strong>falta grave</strong> conforme al artículo <strong>25, {inc}</strong>, de la LPCL.</p>
          {/* El art. 32 exige que la carta indique de modo preciso la causa Y LA
              FECHA del cese. Sin fecha, la carta está incompleta — y el hueco no
              se puede rellenar a mano después, porque el documento se imprime
              desde la base. Si falta, se dice en rojo y no se disimula. */}
          <p>
            En consecuencia, y conforme al <strong>artículo 32 de la LPCL</strong>, se comunica la{" "}
            <strong>extinción del contrato de trabajo por causa justa</strong>
            {doc.fecha_cese
              ? <>, con fecha de cese el <strong>{fechaLarga(doc.fecha_cese)}</strong></>
              : <span className="text-rojo"> [FALTA LA FECHA DE CESE — el art. 32 la exige; fíjala en el borrador antes de firmar]</span>}
            . Se procederá a la liquidación de sus beneficios sociales y a la entrega del certificado de trabajo.
          </p>
        </>
      );
    }
    return <p>Documento de {CAUSAL[t]}.</p>;
  }

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6 print:p-0">
        <div className="mb-4 flex max-w-[760px] items-center justify-between print:hidden">
          <button onClick={() => router.push("/admin/disciplina")} className="text-sm text-taupe hover:text-tinta">← Volver a Disciplina</button>
          {doc && !err && (
            <Boton variante="primario" tamano="lg" onClick={() => window.print()}>
              Imprimir / Guardar PDF
            </Boton>
          )}
        </div>

        {cargando ? (
          <Cargando />
        ) : err ? (
          <p className="max-w-[760px] rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">{err}</p>
        ) : doc && (
          <div className="memo hoja mx-auto max-w-[760px] rounded-lg border border-sand p-10 font-serif text-[13px] leading-relaxed text-tinta print:rounded-none print:border-0 print:p-0">
            {esNivel4 && (
              <p className="mb-4 rounded bg-ambar/15 px-3 py-2 text-xs text-ambar print:hidden">
                Documento de Nivel 4. Antes de emitirlo, valídalo con un abogado laboralista y entrégalo en físico o por vía notarial (nunca por correo).
              </p>
            )}
            {doc.estado === "borrador" && (
              // SIN `print:hidden`, y es deliberado. Este aviso llevaba la
              // clase y se borraba justo en el papel: en pantalla ponía
              // «borrador», e impreso no ponía nada. Imprimir un borrador para
              // revisarlo es legítimo y por eso no se deshabilita el botón —
              // lo que no puede pasar es que el papel no diga lo que es.
              <p className="mb-4 rounded border border-ambar/40 bg-ambar/15 px-3 py-2 text-xs text-ambar">
                <strong>BORRADOR — sin numerar y sin firmar.</strong> No tiene validez como
                documento entregado. Fírmalo en la pantalla de Disciplina para asignarle su número.
              </p>
            )}
            {firmanteIlegible && (
              <p className="mb-4 rounded bg-sand/50 px-3 py-2 text-xs text-taupe print:hidden">
                No se pudo leer la ficha de quien firma este documento —lo normal es que sea de
                otra sede—, así que abajo figura el representante legal de la empresa. Si lo
                suscribió otra persona, compruébalo antes de entregarlo.
              </p>
            )}

            <div className="mb-4 flex items-start justify-between border-b border-sand pb-3 print:mb-3 print:pb-2">
              <div>
                <Marca tono="tinta" isotipo="rojo" />
                <p className="mt-2 text-xs text-taupe">{EMPRESA.nombre} · RUC {EMPRESA.ruc}</p>
              </div>
              <div className="text-right">
                <p className="font-medium">{doc.correlativo ?? "BORRADOR — sin numerar"}</p>
                <p className="text-taupe">{fechaCorta((doc.firmado_at ?? doc.creado_at).slice(0, 10))}</p>
              </div>
            </div>

            <table className="mb-4 w-full">
              <tbody>
                <tr><td className="w-16 py-0.5 align-top text-taupe">Para:</td><td className="py-0.5"><strong>{nombre}</strong> · DNI {persona?.documento ?? "—"}</td></tr>
                <tr><td className="py-0.5 align-top text-taupe">Área:</td><td className="py-0.5">{persona ? areaNombre(areas, persona.funcion) : "—"} · Sede {sede || "—"}</td></tr>
                <tr><td className="py-0.5 align-top text-taupe">De:</td><td className="py-0.5">{firmante ? `${firmante}${cargoFirmante ? ` · ${cargoFirmante}` : ""}` : <em>Pendiente de firma</em>}</td></tr>
              </tbody>
            </table>

            <h2 className="font-serif">Asunto: {TITULO[doc.nivel]} por {CAUSAL[doc.tipo_causal]}</h2>
            <div className="mt-3"><Cuerpo /></div>

            {n > 0 && (
              <table className="my-4 w-full border-collapse text-[12px]">
                <thead>
                  <tr className="border-b text-left text-taupe">
                    <th className="py-1 font-normal">#</th>
                    <th className="py-1 font-normal">Fecha</th>
                    {doc.tipo_causal === "tardanza" && <th className="py-1 font-normal">Minutos de tardanza</th>}
                  </tr>
                </thead>
                <tbody>
                  {doc.hechos.map((h, i) => (
                    <tr key={i} className="border-b">
                      <td className="py-1">{i + 1}</td>
                      <td className="py-1">{fechaCorta(h.fecha)}</td>
                      {doc.tipo_causal === "tardanza" && <td className="py-1">{h.minutos ?? "—"}′</td>}
                    </tr>
                  ))}
                </tbody>
              </table>
            )}

            <div className="firma mt-10 grid grid-cols-2 gap-8 text-[12px] print:break-inside-avoid">
              <div>
                <div className="flex h-28 items-end justify-center">
                  {firmaUrl && (
                    <img src={firmaUrl} alt="" aria-hidden className="block h-28 w-auto max-w-full" />
                  )}
                </div>
                <div className="border-t pt-1">{firmante ?? "Pendiente de firma"}</div>
                <p className="text-taupe">{cargoFirmante ? `${cargoFirmante} — ${EMPRESA.nombre}` : EMPRESA.nombre}</p>
              </div>
              <div>
                <div className="h-28 text-taupe">Recibí conforme:</div>
                <div className="border-t pt-1">{nombre} · DNI {persona?.documento ?? "____"}</div>
                <p className="mt-1 text-taupe">Fecha: __________  Hora: ______</p>
              </div>
            </div>
            <p className="mt-6 text-[11px] text-taupe">
              Constancia de negativa a recibir (si aplica): el colaborador se negó a recibir el presente documento.
              Testigo 1: __________________  ·  Testigo 2: __________________
            </p>

            {/* Constancia DIGITAL del sancionado (0404) — solo en pantalla,
                nunca en el papel: el «Recibí conforme» de arriba sigue en
                blanco para la firma física, que es la que de verdad prueba la
                entrega. Esto es evidencia adicional, no un reemplazo. */}
            {!esNivel4 && (doc.firma_sancionado_confirmada_at || doc.sancionado_rechazo_firma_at) && (
              <div className="mt-4 rounded-lg border border-sand bg-papel p-3 text-xs text-taupe print:hidden">
                {doc.firma_sancionado_confirmada_at ? (
                  <>
                    <p className="mb-2 text-verde">
                      {nombre} confirmó su firma digital el {fechaLarga(doc.firma_sancionado_confirmada_at)}.
                    </p>
                    {doc.firma_sancionado && (
                      <img src={doc.firma_sancionado} alt={`Firma digital de ${nombre}`} className="block h-16 w-auto max-w-full" />
                    )}
                  </>
                ) : (
                  <p>
                    {nombre} dejó constancia de que prefiere no firmar digitalmente, el{" "}
                    {fechaLarga(doc.sancionado_rechazo_firma_at!)}.
                  </p>
                )}
              </div>
            )}
          </div>
        )}
      </main>
    </div>
  );
}

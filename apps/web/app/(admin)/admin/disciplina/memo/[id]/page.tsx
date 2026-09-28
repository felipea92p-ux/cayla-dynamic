"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Cargando } from "@/components/cargando";
import { MemoDocumento, TITULO, fechaLarga, type Hecho, type Previa } from "@/components/disciplina/memo-documento";
import { Boton } from "@/components/ui/boton";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { type Rol } from "@cayla-dynamic/shared";
import { AREAS_FALLBACK, parseAreas, type Area } from "@/lib/areas";

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
  /** Cómo se entregó y cuándo (0486): con `digital`, el papel lleva el recibido de la persona. */
  medio_entrega: string | null;
  entregado_at: string | null;
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
      .select("id, correlativo, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos, suspension_dias, suspension_desde, suspension_hasta, suspension_fechas, fecha_cese, firmante_id, firmado_at, creado_at, firma_sancionado, firma_sancionado_confirmada_at, sancionado_rechazo_firma_at, medio_entrega, entregado_at")
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
    // función también deja fuera imputación y despido, que no llevan firma
    // escaneada (ver render).
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
  const esNivel4 = doc?.nivel === "imputacion" || doc?.nivel === "despido";


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
          <MemoDocumento
            doc={doc}
            persona={persona}
            sede={sede}
            areas={areas}
            firmante={firmante}
            cargoFirmante={cargoFirmante}
            firmaUrl={firmaUrl}
            previas={previas}
            firmanteIlegible={firmanteIlegible}
            recepcion={doc.medio_entrega === "digital" && doc.entregado_at ? { at: doc.entregado_at, firma: doc.firma_sancionado } : null}
          >
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
          </MemoDocumento>
        )}
      </main>
    </div>
  );
}

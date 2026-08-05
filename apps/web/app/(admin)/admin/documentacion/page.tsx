"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { useRolActual } from "@/lib/admin/use-rol";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { AdminNav } from "../nav";
import { Cargando } from "@/components/cargando";
import { Marca } from "@/components/marca";
import { hoyLima, puedeGestionarCatalogos } from "@cayla-dynamic/shared";

// Documentación de CAYLA: eliges el documento y la persona, y sale listo para
// imprimir y firmar con sus datos ya puestos.
//
// POR QUÉ EXISTE. Todo el trabajo del 2026-07-28/29 sobre la estructura
// remunerativa depende de papeles firmados que hasta ahora no existían. Un
// concepto no remunerativo sin su documento de respaldo no es un concepto: es un
// monto que alguien decidió. Y el caso que más se cita en contra —Exp. 1038-2019—
// declaró remuneración una movilidad justamente por «ausencia de criterios
// objetivos», no por el monto.
//
// El sustento no puede vivir en la cabeza de Felipe ni en un Word suelto. Vive
// aquí, sale con los datos de la persona y con fecha, y se archiva firmado.
const EMPRESA = {
  nombre: "CAYLA S.A.C.",
  ruc: "20605964550",
  firmante: "Alvarez Pereyra Felipe Miguel",
  cargo: "Gerencia General",
};

// La tarifa se LEE del sistema y no se escribe aquí: si alguien la cambia y el
// documento dijera otra cosa, el papel contradiría a la boleta — que es
// exactamente lo que no queremos.
//
// Desde la 0118 vive en `parametros_laborales`, VERSIONADA por vigencia, y no en
// `configuracion`. El cambio importa para este documento más que para cualquier
// otra pantalla: acá se lee la tarifa VIGENTE HOY, que es la que hay que firmar.
// Si mañana sube el pasaje y se abre una fila nueva, este documento saldrá con la
// tarifa nueva y el anterior seguirá describiendo correctamente el periodo que
// cubrió — que es justamente por lo que se versionó.
const TARIFA_POR_DEFECTO = 10;

type TipoDoc = "ruta" | "politica" | "bono";

const DOCS: { id: TipoDoc; titulo: string; para: string; necesitaPersona: boolean }[] = [
  {
    id: "ruta",
    titulo: "Declaración de ruta y gasto de transporte",
    para: "La firma cada integrante. Es el criterio objetivo que sostiene el monto de movilidad.",
    necesitaPersona: true,
  },
  {
    id: "politica",
    titulo: "Política de movilidad supeditada a asistencia",
    para: "La emite CAYLA, una sola vez. Debe tener fecha anterior al primer pago de movilidad.",
    necesitaPersona: false,
  },
  {
    id: "bono",
    titulo: "Asignación por cumpleaños — constancia de entrega",
    para: "La firma quien la recibe, en el mes de su onomástico. Es lo que acredita la causa del pago.",
    necesitaPersona: true,
  },
];

// El monto del bono, decidido con Felipe el 2026-07-31 tras comparar cinco
// alternativas. Igual para todos y sin condición de antigüedad: escalarlo por
// rango o atarlo al tiempo de servicio lo devuelve a ser remuneración.
const BONO_CUMPLEANOS = 180;

interface Persona {
  id: string;
  nombres: string;
  apellidos: string;
  documento: string | null;
  funcion: string;
  sede_base_id: string;
  fecha_ingreso: string;
  // DERIVADA de tipo_vinculo (0085), no se escribe: es false para 'rxh' y
  // 'no_trabajador'. Decide quién viene desmarcado — ver `cargar()`.
  en_planilla: boolean;
  tipo_vinculo: string;
}

// Cómo se llama en pantalla cada vínculo, para que quien mira la lista entienda
// POR QUÉ alguien viene desmarcado en vez de tener que acordarse.
const ETIQUETA_VINCULO: Record<string, string> = {
  rxh: "recibo por honorarios",
  no_trabajador: "no trabajador",
};

// Una tarifa de movilidad vigente. `sede_codigo` en null es la general — la que
// aplica a una sede que no tiene fila propia. Los campos son opcionales porque
// si la 0130 no está pegada la consulta devuelve filas sin `sede_codigo` y el
// documento tiene que seguir saliendo igual que antes.
// El documento lo lee gente de fuera de CAYLA — un inspector, un abogado. «AQP»
// no le dice nada; «Arequipa» sí.
const SEDE_CIUDAD: Record<string, string> = {
  AQP: "Arequipa",
  TRU: "Trujillo",
  LIM: "Lima",
  CCO: "Central",
};

interface TarifaSede {
  valor: number;
  sustento: string | null;
  sede_codigo?: string | null;
}

function fechaLarga(iso: string): string {
  const [y, m, d] = iso.slice(0, 10).split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", {
    day: "numeric", month: "long", year: "numeric", timeZone: "UTC",
  }).format(new Date(Date.UTC(y, m - 1, d)));
}

// Una línea para llenar a mano. Los documentos que se firman tienen que poder
// completarse con lapicero: la persona declara su ruta en el momento, delante de
// quien se lo entrega, y no antes en una pantalla.
function Linea({ ancho = "12rem" }: { ancho?: string }) {
  return <span className="inline-block border-b border-tinta align-bottom" style={{ width: ancho }} />;
}

export default function DocumentacionPage() {
  const router = useRouter();
  const rol = useRolActual();
  const puede = puedeGestionarCatalogos(rol);
  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  const [tipo, setTipo] = useState<TipoDoc>("ruta");
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [sedes, setSedes] = useState<Map<string, string>>(new Map());
  const [personaId, setPersonaId] = useState<string>("");
  const [tarifa, setTarifa] = useState<number>(TARIFA_POR_DEFECTO);
  const [sustento, setSustento] = useState<string | null>(null);
  const [cargando, setCargando] = useState(true);
  // Quién NO recibe el documento. Se guarda la exclusión y no la inclusión a
  // propósito: el caso normal es que lo reciba todo el equipo, así que una
  // persona nueva entra sola en la lista sin que nadie tenga que acordarse.
  const [excluidos, setExcluidos] = useState<Set<string>>(new Set());
  const [firmaUrl, setFirmaUrl] = useState<string | null>(null);
  const [tarifas, setTarifas] = useState<TarifaSede[]>([]);
  // persona_id → fecha de término del contrato, para quien ya la tiene fijada.
  const [finContrato, setFinContrato] = useState<Map<string, string>>(new Map());

  const cargar = useCallback(async () => {
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    const [{ data: ps }, { data: ss }, { data: cfg }] = await Promise.all([
      supabase.from("personas")
        .select("id, nombres, apellidos, documento, funcion, sede_base_id, fecha_ingreso, en_planilla, tipo_vinculo")
        .eq("estado", "activo").order("apellidos"),
      supabase.from("sedes").select("id, nombre, codigo"),
      // La tarifa vigente hoy. Si la 0118 no está pegada esto devuelve vacío y se
      // queda el valor por defecto: el documento sigue saliendo, nunca se rompe
      // por no poder leer un parámetro.
      supabase.from("parametros_laborales")
        .select("valor, vigente_desde, sustento, sede_codigo")
        .eq("clave", "movilidad_diaria")
        .lte("vigente_desde", new Date().toISOString().slice(0, 10))
        .is("vigente_hasta", null)
        .order("vigente_desde", { ascending: false }),
    ]);
    const lista = (ps as Persona[]) ?? [];
    setPersonas(lista);

    // Quién tiene ya fecha de término de contrato. Va en consulta APARTE y no
    // en el select de arriba a propósito: si la 0138 todavía no está pegada en
    // producción, pedir una columna inexistente haría fallar la consulta entera
    // y la pantalla se quedaría sin nadie. Así, si falla, simplemente no hay
    // nadie con fin de contrato y el documento sigue saliendo — mismo criterio
    // que la tarifa de movilidad de acá arriba.
    const { data: fin } = await supabase
      .from("personas")
      .select("id, fecha_fin_contrato")
      .eq("estado", "activo")
      .not("fecha_fin_contrato", "is", null);
    const porVencer = new Map(
      ((fin as { id: string; fecha_fin_contrato: string }[] | null) ?? [])
        .map((f) => [f.id, f.fecha_fin_contrato]),
    );
    setFinContrato(porVencer);
    setSedes(new Map(((ss as { id: string; nombre: string; codigo: string }[]) ?? [])
      .map((s) => [s.id, s.nombre || s.codigo])));

    // Quiénes salen desmarcados de entrada. Son dos motivos distintos:
    //
    //  · Quien imprime el documento es quien lo FIRMA, así que no puede además
    //    declarar haberlo recibido.
    //  · Quien no está en planilla —recibo por honorarios y accionistas— no
    //    recibe movilidad ni bono de cumpleaños, que es de lo único que tratan
    //    los tres documentos de esta pantalla. Un locador firmando el cargo de
    //    una política de movilidad es peor que un papel de más: es un indicio
    //    de subordinación en un vínculo que por definición no la tiene, y esa
    //    es exactamente la prueba que se usa para desnaturalizar un contrato
    //    civil. La 0085 ya dejó la respuesta lista en `en_planilla`, que es
    //    derivada de tipo_vinculo — así un quinto tipo de vínculo entra bien
    //    solo, sin tocar esta línea.
    //
    // DESMARCADOS, NO AUSENTES: la decisión de quién recibe sigue siendo humana
    // (esa fue la decisión del 2026-08-02, y el caso que la motivó —alguien que
    // se va a fin de mes— no está en ninguna columna). Lo que cambia es que el
    // sistema ya no propone lo incorrecto. Quien mira la lista puede volver a
    // marcarlos, y el papel impreso solo lleva a los que quedaron marcados.
    const fuera = new Set(lista.filter((p) => !p.en_planilla).map((p) => p.id));
    // Y quien tiene fecha de término de contrato ya fijada: se va, así que no
    // firma un documento que regirá cuando ya no esté. Este era justamente el
    // caso que el comentario de más abajo daba por indeducible («alguien que se
    // va a fin de mes, y eso no está en ninguna columna») — desde la 0138 SÍ
    // está en una columna, así que ya no hace falta acordarse.
    for (const id of porVencer.keys()) fuera.add(id);
    const { data: yo } = await supabase.rpc("fn_persona_actual_id");
    if (typeof yo === "string") fuera.add(yo);
    setExcluidos(fuera);

    // La firma escaneada de quien está imprimiendo. Si no tiene, el documento
    // sale con la línea en blanco para firmar a mano, como hasta ahora.
    const { data: fu } = await supabase.rpc("fn_mi_firma");
    setFirmaUrl(typeof fu === "string" && fu.startsWith("data:image") ? fu : null);

    // ⇩ Desde la 0130 la tarifa es POR SEDE, porque el pasaje no cuesta lo mismo
    // en las tres ciudades. La política tiene que decir las tres: un documento
    // que afirma un monto único mientras el sistema paga otro es peor que no
    // tener documento.
    const filas = (cfg as TarifaSede[] | null) ?? [];
    setTarifas(filas);
    const general = filas.find((f) => !f.sede_codigo) ?? filas[0];
    const monto = Number(general?.valor);
    if (Number.isFinite(monto) && monto > 0) setTarifa(monto);
    // El sustento viaja pegado a la tarifa en la base (0118). Se muestra en el
    // documento en lugar de repetirlo en el código: así el papel dice
    // exactamente lo que la fila que se está aplicando dice.
    if (general?.sustento) setSustento(general.sustento);
    setCargando(false);
  }, [supabase, router]);

  useEffect(() => { void cargar(); }, [cargar]);

  const persona = personas.find((p) => p.id === personaId);
  const nombre = persona ? `${persona.nombres} ${persona.apellidos}` : "";
  const doc = DOCS.find((d) => d.id === tipo)!;

  useTituloDocumento(
    tipo === "politica"
      ? "Política de movilidad supeditada a asistencia — CAYLA"
      : nombre
        ? `${nombre} — Declaración de ruta de transporte`
        : null,
  );

  if (rol === null || cargando) {
    return <main className="p-6"><Cargando /></main>;
  }
  if (!puede) {
    return (
      <main className="p-6">
        <p className="max-w-md rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
          Solo administradores y líderes pueden generar documentación.
        </p>
      </main>
    );
  }

  // Los días laborables TEÓRICOS de un mes son 26 o 27. Los ASISTIDOS no: se
  // midieron 78 meses-persona de 2026 el 2026-08-01 y el promedio real fue 23.6
  // — 22.2 en Arequipa, 23.9 en Trujillo, 24.6 en Lima. Ninguna sede llega a 26.
  //
  // Se usa 24 porque el documento tiene que decir una cifra que la gente vaya a
  // reconocer en su boleta. Prometer el equivalente de 26 días en un papel que
  // firman, cuando casi nadie los alcanza, es crear una expectativa que el
  // sistema no va a cumplir ningún mes.
  //
  // La constante existe para que el número y el texto no puedan desalinearse:
  // antes el cálculo usaba 26 y la frase decía «24 días», así que el documento
  // afirmaba que 10 × 24 = 260. Felipe lo detectó el 2026-08-02.
  const DIAS_REFERENCIA = 24;
  const mensual = tarifa * DIAS_REFERENCIA;

  // Las tarifas que tienen sede propia, ordenadas. Si está vacío es que la 0130
  // no está pegada y el documento cae al monto único de siempre.
  const porSede = tarifas
    .filter((t) => Boolean(t.sede_codigo))
    .sort((a, b) => (a.sede_codigo ?? "").localeCompare(b.sede_codigo ?? ""));

  // Quiénes reciben el documento y firman el cargo.
  const reciben = personas.filter((p) => !excluidos.has(p.id));

  return (
    <>
      <div className="print:hidden"><AdminNav /></div>

      <main className="mx-auto max-w-3xl p-6 print:max-w-none print:p-0">
        {/* Controles — no se imprimen */}
        <div className="mb-6 print:hidden">
          <h1 className="mb-1 font-serif text-2xl">Documentación</h1>
          <p className="mb-4 text-sm text-taupe">
            Elige el documento, la persona, e imprime. Sale con sus datos y con la fecha de hoy.
          </p>

          <div className="mb-4 grid gap-3 sm:grid-cols-2">
            <label className="block text-sm">
              <span className="mb-1 block text-taupe">Documento</span>
              <select
                value={tipo}
                onChange={(e) => setTipo(e.target.value as TipoDoc)}
                className="w-full rounded-lg border px-3 py-2"
              >
                {DOCS.map((d) => <option key={d.id} value={d.id}>{d.titulo}</option>)}
              </select>
            </label>

            {doc.necesitaPersona && (
              <label className="block text-sm">
                <span className="mb-1 block text-taupe">Persona</span>
                <select
                  value={personaId}
                  onChange={(e) => setPersonaId(e.target.value)}
                  className="w-full rounded-lg border px-3 py-2"
                >
                  <option value="">Elige a quién…</option>
                  {personas.map((p) => (
                    <option key={p.id} value={p.id}>{p.apellidos}, {p.nombres}</option>
                  ))}
                </select>
              </label>
            )}
          </div>

          {/* Quién firma el cargo. Se muestra solo en la política, que es el
              documento que recibe todo el equipo a la vez.

              POR QUÉ SIGUE HABIENDO LISTA. El 2026-08-02 se decidió no filtrar
              automáticamente porque los dos casos a excluir —un locador, y
              alguien que se va a fin de mes— no se podían deducir del sistema.
              Hoy sí se pueden: `en_planilla` (0085) cubre al locador y
              `fecha_fin_contrato` (0138) cubre a quien se va. Así que el sistema
              ya PROPONE bien y vienen desmarcados. La lista se queda porque la
              decisión final sigue siendo humana y porque un desmarcado que no se
              puede volver a marcar es una decisión escondida, no una ayuda. */}
          {!doc.necesitaPersona && personas.length > 0 && (
            <details className="mb-4 rounded-lg border border-sand p-3">
              <summary className="cursor-pointer text-sm">
                Quiénes reciben el documento —{" "}
                <strong>{reciben.length} de {personas.length}</strong>
              </summary>
              <p className="mt-2 text-xs text-taupe">
                Vienen desmarcados quien firma —no declara haber recibido lo que emite—,
                quien no está en planilla, porque no cobra movilidad ni bono de cumpleaños,
                y quien ya tiene fecha de término de contrato. Revisa la lista igual: la
                decisión final es tuya.
              </p>
              <div className="mt-3 grid gap-1 sm:grid-cols-2">
                {personas.map((p) => (
                  <label key={p.id} className="flex items-center gap-2 text-sm">
                    <input
                      type="checkbox"
                      checked={!excluidos.has(p.id)}
                      onChange={() =>
                        setExcluidos((prev) => {
                          const s = new Set(prev);
                          if (s.has(p.id)) s.delete(p.id);
                          else s.add(p.id);
                          return s;
                        })
                      }
                    />
                    <span>
                      {p.apellidos}, {p.nombres}
                      {ETIQUETA_VINCULO[p.tipo_vinculo] && (
                        <em className="ml-1 not-italic text-taupe">
                          — {ETIQUETA_VINCULO[p.tipo_vinculo]}
                        </em>
                      )}
                      {finContrato.has(p.id) && (
                        <em className="ml-1 not-italic text-taupe">
                          — su contrato termina el{" "}
                          {finContrato.get(p.id)!.split("-").reverse().join("/")}
                        </em>
                      )}
                    </span>
                  </label>
                ))}
              </div>
            </details>
          )}

          <p className="mb-4 rounded-lg bg-sand/40 px-4 py-3 text-sm text-taupe">{doc.para}</p>

          <button
            onClick={() => window.print()}
            disabled={doc.necesitaPersona && !persona}
            className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema hover:bg-rojo-profundo disabled:opacity-40"
          >
            Imprimir / Guardar como PDF
          </button>
          <span className="ml-3 text-xs text-taupe">
            Al imprimir, desmarca «Encabezados y pies de página».
          </span>
        </div>

        {/* ── El documento ── */}
        {(!doc.necesitaPersona || persona) && (
          <div className="hoja rounded-lg border border-sand p-8 text-sm leading-relaxed print:rounded-none print:border-0 print:p-0">
            <div className="mb-6 flex items-start justify-between border-b border-sand pb-4">
              <Marca tono="tinta" isotipo="rojo" />
              <div className="text-right text-xs text-taupe">
                <p>{EMPRESA.nombre}</p>
                <p>RUC {EMPRESA.ruc}</p>
              </div>
            </div>

            {tipo === "ruta" && persona && (
              <>
                <h2 className="mb-6 text-center font-serif text-xl">
                  Declaración de ruta y gasto de transporte
                </h2>

                <p className="mb-4">
                  Yo, <strong>{nombre}</strong>, con documento de identidad N.º{" "}
                  {persona.documento ? <strong>{persona.documento}</strong> : <Linea ancho="8rem" />}, que
                  desempeño el cargo de <strong>{persona.funcion}</strong> en la sede{" "}
                  <strong>{sedes.get(persona.sede_base_id) ?? "—"}</strong> de {EMPRESA.nombre},
                  declaro lo siguiente respecto de mi traslado diario entre mi domicilio y mi
                  centro de labores:
                </p>

                {/* Se llena a mano, delante de quien entrega el documento. Es el
                    dato que convierte el monto en criterio objetivo, y tiene que
                    salir de la persona, no de una pantalla. */}
                <ol className="mb-6 list-decimal space-y-3 pl-6">
                  <li>
                    Resido en el distrito de <Linea ancho="14rem" />, provincia de{" "}
                    <Linea ancho="10rem" />.
                  </li>
                  <li>
                    Para llegar a mi centro de labores utilizo <Linea ancho="3rem" /> medio(s) de
                    transporte por tramo, y de regreso <Linea ancho="3rem" />.
                  </li>
                  <li>
                    El costo de cada pasaje es de S/ <Linea ancho="4rem" />, de modo que mi gasto
                    diario habitual de ida y vuelta asciende a S/ <Linea ancho="4rem" />.
                  </li>
                  <li>
                    Según el horario de mi turno, en ocasiones debo utilizar taxi u otro medio
                    particular, cuyo costo por viaje asciende aproximadamente a S/{" "}
                    <Linea ancho="4rem" />. Esto ocurre alrededor de <Linea ancho="3rem" /> veces
                    por semana.
                  </li>
                  <li>
                    Declaro que la información consignada es veraz, y me comprometo a informar a
                    CAYLA S.A.C. si cambio de domicilio o de ruta habitual.
                  </li>
                </ol>

                <p className="mb-6">
                  Tomo conocimiento de que CAYLA S.A.C. me otorga una asignación por movilidad de{" "}
                  <strong>S/ {tarifa.toFixed(2)} por día efectivamente asistido</strong>, destinada
                  a cubrir dicho traslado; que se abona únicamente por los días en que asisto a
                  laborar, no correspondiendo en caso de inasistencia, licencia o descanso; y que
                  este concepto <strong>no tiene carácter remunerativo</strong>, conforme al
                  artículo 19 inciso e) del Decreto Supremo N.º 001-97-TR.
                </p>

                <p className="mb-10 text-xs text-taupe">
                  Suscrito en {sedes.get(persona.sede_base_id) ?? "—"}, el {fechaLarga(hoyLima())}.
                </p>

                <div className="grid grid-cols-2 gap-10 pt-6">
                  <div className="text-center">
                    <div className="mb-1 border-t border-tinta pt-2 text-xs">
                      {nombre}
                    </div>
                    <p className="text-xs text-taupe">
                      DNI {persona.documento ?? "—————"} · el/la declarante
                    </p>
                  </div>
                  <div className="text-center">
                    <div className="mb-1 border-t border-tinta pt-2 text-xs">
                      {EMPRESA.firmante}
                    </div>
                    <p className="text-xs text-taupe">{EMPRESA.cargo} · {EMPRESA.nombre}</p>
                  </div>
                </div>
              </>
            )}

            {tipo === "bono" && (
              <>
                <h2 className="mb-6 text-center font-serif text-xl">
                  Asignación por cumpleaños
                </h2>

                <p className="mb-4">
                  {EMPRESA.nombre}, con RUC {EMPRESA.ruc}, hace entrega a{" "}
                  <strong>{persona ? `${persona.nombres} ${persona.apellidos}` : "—"}</strong>
                  {persona?.documento ? `, con documento de identidad ${persona.documento},` : ","}{" "}
                  de la suma de <strong>S/ {BONO_CUMPLEANOS.toFixed(2)}</strong> con ocasión de su
                  onomástico.
                </p>

                {/* LA CLÁUSULA. No dice «gratificación extraordinaria» ni «a título de
                    liberalidad» ni «a discreción», y eso es deliberado: esas palabras
                    invocan el inciso a) del art. 19, que exige que el pago sea OCASIONAL
                    — y la Casación 28833-2022 Lima (considerando décimo sétimo) establece
                    que un pago repetitivo, incluida la periodicidad ANUAL, ya no es
                    extraordinario. Además «liberalidad» hace el gasto NO DEDUCIBLE por el
                    art. 44 inciso d) de la Ley del Impuesto a la Renta.
                    El inciso g) no pide nada de eso: solo pide la CAUSA, que es el
                    onomástico, y está nombrada literalmente en la norma. */}
                <p className="mb-4 border-l-2 border-sand pl-4">
                  Esta asignación se otorga con ocasión del onomástico del trabajador, conforme
                  al literal g) del artículo 19 del Texto Único Ordenado del Decreto Legislativo
                  N° 650, aprobado por Decreto Supremo N° 001-97-TR. En consecuencia,{" "}
                  <strong>no constituye remuneración computable para ningún efecto legal</strong>,
                  de acuerdo con el artículo 7 del Decreto Supremo N° 003-97-TR.
                </p>

                <p className="mb-6 text-sm text-taupe">
                  La presente constancia acredita la entrega y su causa. Se archiva firmada por
                  el trabajador.
                </p>

                <div className="mt-16 grid grid-cols-2 gap-12">
                  <div className="text-center">
                    <div className="mb-1 border-t border-tinta pt-2 text-xs">
                      {persona ? `${persona.nombres} ${persona.apellidos}` : "\u00a0"}
                    </div>
                    <p className="text-xs text-taupe">Recibí conforme</p>
                  </div>
                  <div className="text-center">
                    <div className="mb-1 border-t border-tinta pt-2 text-xs">
                      {EMPRESA.firmante}
                    </div>
                    <p className="text-xs text-taupe">{EMPRESA.cargo} · {EMPRESA.nombre}</p>
                  </div>
                </div>
              </>
            )}

            {tipo === "politica" && (
              <>
                <h2 className="mb-6 text-center font-serif text-xl">
                  Política de movilidad supeditada a asistencia
                </h2>

                <p className="mb-4">
                  {EMPRESA.nombre}, con RUC {EMPRESA.ruc}, establece la presente política, aplicable
                  a todo su personal sujeto al régimen laboral de la actividad privada en sus sedes
                  de Trujillo, Lima y Arequipa.
                </p>

                <p className="mb-2 font-medium">Primera — Objeto y monto</p>
                {porSede.length > 0 ? (
                  <>
                    <p className="mb-3">
                      CAYLA otorga a su personal una asignación por movilidad{" "}
                      <strong>por cada día efectivamente asistido</strong>, destinada
                      exclusivamente a cubrir el traslado desde su domicilio hasta su centro de
                      labores y su retorno. El monto se fija por sede, porque el costo del
                      pasaje difiere entre las ciudades donde CAYLA opera:
                    </p>
                    <table className="mb-4 w-full max-w-sm text-xs">
                      <tbody>
                        {porSede.map((t) => (
                          <tr key={t.sede_codigo}>
                            <td className="border-b border-sand py-1.5">
                              {SEDE_CIUDAD[t.sede_codigo ?? ""] ?? t.sede_codigo}
                            </td>
                            <td className="border-b border-sand py-1.5 text-right font-medium">
                              S/ {Number(t.valor).toFixed(2)} por día
                            </td>
                            <td className="border-b border-sand py-1.5 text-right text-taupe">
                              S/ {(Number(t.valor) * DIAS_REFERENCIA).toFixed(2)} en{" "}
                              {DIAS_REFERENCIA} días
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </>
                ) : (
                  <p className="mb-4">
                    CAYLA otorga a su personal una asignación por movilidad de{" "}
                    <strong>S/ {tarifa.toFixed(2)} por día efectivamente asistido</strong> —
                    equivalente a S/ {mensual.toFixed(2)} en un mes de {DIAS_REFERENCIA} días
                    asistidos — destinada exclusivamente a cubrir el traslado desde su domicilio
                    hasta su centro de labores y su retorno.
                  </p>
                )}

                <p className="mb-2 font-medium">Segunda — Supeditación a la asistencia</p>
                <p className="mb-4">
                  La asignación se devenga <strong>únicamente por los días en que el trabajador
                  asiste efectivamente a laborar</strong>. No corresponde en caso de inasistencia,
                  licencia, descanso médico, vacaciones ni descanso semanal. El cálculo se realiza
                  de forma automática sobre los días con jornada registrada, sin intervención
                  manual.
                </p>

                <p className="mb-2 font-medium">Tercera — Criterio del monto único</p>
                {/* Este es el párrafo que sostiene el monto, y el argumento es de
                    Felipe, no mío: el costo real varía de forma impredecible. La
                    norma admite expresamente el monto fijo pactado justamente por
                    eso. Sin este párrafo, el monto es «arbitrio del empleador» —
                    la frase exacta por la que el Exp. 1038-2019 reclasificó una
                    movilidad íntegra. */}
                <p className="mb-4">
                  El monto se establece de forma <strong>fija y uniforme</strong> porque el costo
                  real del traslado varía de manera impredecible según la ruta, el horario del
                  turno y el medio de transporte disponible: el personal utiliza en unos casos dos
                  medios de transporte por tramo, y en otros taxi o servicio particular cuando el
                  horario del turno lo exige. El artículo 19 inciso e) del Decreto Supremo N.º
                  001-97-TR admite expresamente esta modalidad al señalar que{" "}
                  <em>«se incluye en este concepto el monto fijo que el empleador otorgue por pacto
                  individual o convención colectiva»</em>. El monto se sustenta en las
                  declaraciones de ruta y gasto suscritas por el personal, que forman parte de
                  esta política y se conservan en el legajo de cada trabajador.
                </p>

                <p className="mb-2 font-medium">Cuarta — Naturaleza no remunerativa</p>
                <p className="mb-4">
                  Conforme al artículo 19 inciso e) del Decreto Supremo N.º 001-97-TR, la presente
                  asignación <strong>no tiene carácter remunerativo</strong> y no se considera para
                  el cálculo de la compensación por tiempo de servicios, gratificaciones legales,
                  vacaciones ni aportaciones a la seguridad social. Se deja constancia de que sí se
                  encuentra afecta a la retención del impuesto a la renta de quinta categoría
                  cuando corresponda.
                </p>

                <p className="mb-2 font-medium">Quinta — No sustituye ningún concepto</p>
                {/* La cláusula más importante del documento. La reduccion de
                    remuneracion para sustituirla por conceptos no remunerativos
                    es lo que hace nula la maniobra (Art. 26.2 de la Constitución;
                    Art. 10 de la Ley 28051 para el caso de alimentación). Dejarlo
                    dicho por escrito, y que sea VERDAD, es lo que separa esta
                    política de un reetiquetado. */}
                <p className="mb-4">
                  Esta asignación se otorga <strong>en adición</strong> a la remuneración y a los
                  demás conceptos que el trabajador percibe, y{" "}
                  <strong>no sustituye, reduce ni reemplaza</strong> ninguno de ellos. Su
                  otorgamiento no ha implicado la disminución de ningún concepto remunerativo
                  previamente percibido.
                </p>

                <p className="mb-2 font-medium">Sexta — Revisión</p>
                <p className="mb-6">
                  El monto se revisará cuando varíen las tarifas del transporte público en las
                  ciudades donde CAYLA opera, o cuando cambien las condiciones de los turnos.
                </p>

                <p className="mb-10 text-xs text-taupe">
                  Emitida el {fechaLarga(hoyLima())}.
                </p>

                <div className="mb-10 w-1/2 text-center">
                  {/* La firma escaneada de quien imprime, si la tiene cargada. El
                      alto fijo mantiene la línea en su sitio aunque no haya firma:
                      así el documento se ve igual con y sin ella, y quien no la
                      tenga simplemente firma a mano sobre la raya. */}
                  <div className="flex h-24 items-end justify-center">
                    {firmaUrl && (
                      <img src={firmaUrl} alt="" aria-hidden className="block h-24 w-auto max-w-full" />
                    )}
                  </div>
                  <div className="mb-1 border-t border-tinta pt-2 text-xs">{EMPRESA.firmante}</div>
                  <p className="text-xs text-taupe">{EMPRESA.cargo} · {EMPRESA.nombre}</p>
                </div>

                <div className="break-inside-avoid border-t border-sand pt-4">
                  <p className="mb-3 font-medium">Cargo de recepción</p>
                  <p className="mb-4 text-xs text-taupe">
                    Declaro haber recibido copia de la presente política y tomado conocimiento de
                    su contenido.
                  </p>
                  <table className="w-full text-xs">
                    <thead className="text-left text-taupe">
                      <tr>
                        <th className="border-b border-sand py-1 font-normal">Nombre</th>
                        <th className="border-b border-sand py-1 font-normal">DNI</th>
                        <th className="border-b border-sand py-1 font-normal">Fecha</th>
                        <th className="border-b border-sand py-1 font-normal">Firma</th>
                      </tr>
                    </thead>
                    {/* Sin recorte: van todos. Antes se cortaba en 12 y había que
                        imprimir dos veces; ahora la tabla se parte sola entre hojas
                        porque las filas llevan break-inside-avoid y el encabezado se
                        repite con thead. Un cargo incompleto no sirve de nada. */}
                    <tbody>
                      {reciben.map((p) => (
                        <tr key={p.id} className="break-inside-avoid">
                          <td className="border-b border-sand py-3">{p.apellidos}, {p.nombres}</td>
                          <td className="border-b border-sand py-3">{p.documento ?? ""}</td>
                          <td className="border-b border-sand py-3" />
                          <td className="border-b border-sand py-3" />
                        </tr>
                      ))}
                    </tbody>
                  </table>
                  <p className="mt-3 text-xs text-taupe">
                    {reciben.length} {reciben.length === 1 ? "persona" : "personas"}.
                  </p>
                </div>
              </>
            )}
          </div>
        )}
      </main>
    </>
  );
}

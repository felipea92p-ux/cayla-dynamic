"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { useRolActual } from "@/lib/admin/use-rol";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { AdminNav } from "../nav";
import { Cargando } from "@/components/cargando";
import { Marca } from "@/components/marca";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import { hoyLima, rangoDelMesLima, puedeGestionarCatalogos } from "@cayla-dynamic/shared";

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
//
// ⇩ 2026-08-05 · AQUÍ HABÍA UN `TARIFA_POR_DEFECTO = 10` Y ESE ERA EL BUG.
//
// La declaración de Taller LIM salía impresa con S/ 10.00 mientras la planilla
// le pagaba S/ 12.00, que es lo que la 0142 fijó para Lima. Dos causas encadenadas:
//
//   1. La pantalla leía SIEMPRE la fila general (`sede_codigo` nulo) y nunca la
//      de la sede de la persona. La general vale 0.00 desde la 0118 —nace
//      apagada a propósito—, así que la lectura fallaba el «> 0»…
//   2. …y caía a este 10 escrito a mano, que se veía perfectamente creíble.
//
// Un valor por defecto convirtió «no tengo el dato» en «el dato es 10». Por eso
// ya no hay ninguno: sin fila aplicable, la tarifa es `null` y el documento lo
// dice en vez de imprimir una cifra. Es la misma regla que el resto del repo
// —nada de listas ni montos escritos a mano cuando el dato vive en una tabla—,
// y acá pesa más que en ninguna pantalla, porque este papel se firma.

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
    para: "La emite CAYLA, una sola vez. Va fechada el día en que empezó a pagarse movilidad: rige desde ahí en adelante.",
    necesitaPersona: false,
  },
  {
    id: "bono",
    titulo: "Asignación por cumpleaños — constancia de entrega",
    para: "La firma quien la recibe, en el mes de su onomástico. Es lo que acredita la causa del pago.",
    necesitaPersona: true,
  },
];

// EL MONTO DEL BONO NO ESTÁ ESCRITO ACÁ, Y ESE ES EL PUNTO.
//
// Se decidió con Felipe el 2026-07-31 tras comparar cinco alternativas: igual
// para todos y sin condición de antigüedad, porque escalarlo por rango o atarlo
// al tiempo de servicio lo devuelve a ser remuneración.
//
// Desde la 0165 la verdad vive en `parametros_laborales` (clave
// `bono_onomastico`), versionada por `vigente_desde` — la misma fila dice cuánto
// vale y desde cuándo rige la política.
//
// ⇩ 2026-08-06 · ACÁ HUBO UN `BONO_POR_DEFECTO = 180` Y SE BORRÓ.
//
// Era un respaldo por si la 0165 no estaba pegada, y hoy acertaba: el bono es
// 180 para todo el mundo, así que el número de respaldo era el correcto. La
// razón de sacarlo es la de mañana, no la de hoy.
//
// El día que el monto cambie —se cierra la fila de 180 y se abre la de 200— basta
// que la nueva quede mal fechada, o que se cierre una sin abrir la otra, para que
// la consulta vuelva vacía y la constancia se imprima con 180. Alguien firmaría
// «recibí S/ 180.00» habiendo cobrado otra cosa, en un papel que se ve
// perfectamente normal. Es exactamente lo que pasó con la movilidad: el código
// decía 10, la base no contestaba, y Taller LIM firmaba S/ 10.00 mientras cobraba
// S/ 12.00.
//
// Un valor de respaldo convierte «no tengo el dato» en «el dato es 180». En un
// documento que se firma, eso no es tolerancia a fallos: es una afirmación falsa
// con rúbrica. Sin fila aplicable, `bonoMonto` es null y la constancia NO SE
// IMPRIME — dice qué falta, igual que la declaración de ruta.

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

// El bloque de firma de los tres documentos: el espacio de la rúbrica, la raya,
// el nombre y el cargo. Vive en un solo sitio a propósito — antes estaba escrito
// tres veces y solo una de las tres estampaba la firma escaneada, así que la
// política salía firmada y la declaración de ruta con la raya en blanco.
//
// El alto del espacio es FIJO y el mismo con imagen y sin ella. Sin eso, en un
// documento de dos columnas la que lleva firma empujaría su raya hacia abajo y
// el papel saldría con las dos firmas descuadradas.
function BloqueFirma({ imagen, nombre, pie }: {
  imagen?: string | null;
  nombre: string;
  pie: string;
}) {
  return (
    <div className="text-center">
      <div className="flex h-24 items-end justify-center">
        {imagen && (
          <img src={imagen} alt="" aria-hidden className="block h-24 w-auto max-w-full" />
        )}
      </div>
      <div className="mb-1 border-t border-tinta pt-2 text-xs">{nombre}</div>
      <p className="text-xs text-taupe">{pie}</p>
    </div>
  );
}

interface FilaTablero {
  persona_id: string;
  persona: string;
  sede: string;
  fecha_ingreso: string | null;
  ruta_id: string | null;
  ruta_firmada_el: string | null;
  ruta_monto: number | null;
  ruta_negativa: boolean;
  ruta_desfasada: boolean;
  bono_id: string | null;
  bono_anio: number | null;
  bono_firmada_el: string | null;
  bono_mes: number | null;
  // Lo calcula la 0161. Los tres estados que exigen acción son 'este_mes',
  // 'vencido' y 'sin_fecha'; los otros tres significan «no hay nada que hacer»
  // y por eso se pintan en gris.
  bono_estado: "ok" | "sin_fecha" | "no_aplica" | "este_mes" | "vencido" | "proximo" | null;
  estado: "sin_ruta" | "se_nego" | "ok";
}

// Qué exige acción de Desarrollo Organizacional y qué no. Se escribe una vez
// acá y no repartido en cada `if` de la tabla: el día que se agregue un estado,
// se decide en un solo lugar de qué lado cae.
const BONO_PENDIENTE = new Set(["este_mes", "vencido"]);

const MES_LARGO = [
  "enero", "febrero", "marzo", "abril", "mayo", "junio",
  "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
];

// Lo que dice el panel de subida según el papel que se está archivando. Va en
// una tabla y no en tres `if` dentro del render porque son el mismo formulario
// diciendo tres cosas distintas: el día que se agregue un cuarto documento, se
// agrega una fila acá y el panel ya sabe atenderlo.
const ETIQUETA_SUBIDA: Record<TipoDoc, {
  titulo: string;
  deQue: string;
  archivo: string;
  fecha: string;
  ayuda: string;
  ejemploNota: string;
}> = {
  ruta: {
    titulo: "Subir la declaración firmada",
    deQue: "de la declaración",
    archivo: "Declaración firmada",
    fecha: "Fecha en que se firmó",
    ayuda: "El monto se guarda solo, con la tarifa vigente de su sede. No hace falta transcribir la ruta: el escaneo ya la dice.",
    ejemploNota: "ej. firmada en la tienda",
  },
  politica: {
    titulo: "Subir la política de movilidad firmada",
    deQue: "de la política",
    archivo: "Política firmada",
    fecha: "Fecha en que se firmó",
    ayuda: "Es un solo documento para toda la empresa, sin persona. Viene con la fecha en que empezó a pagarse movilidad, que es la que sale impresa en el papel: déjala así. Si la cambias por una posterior, el sistema lo va a seguir avisando — un documento fechado después de los pagos que justifica no los justifica.",
    ejemploNota: "ej. firmada junto con el reglamento interno",
  },
  bono: {
    titulo: "Subir el cargo de la asignación por cumpleaños",
    deQue: "del cargo",
    archivo: "Cargo firmado",
    fecha: "Fecha en que se entregó y firmó",
    ayuda: "El año del bono sale de esta fecha, no del día de hoy: un cargo de diciembre que se sube en enero sigue siendo el del año que pasó.",
    ejemploNota: "ej. entregado en efectivo con el sueldo",
  },
};

interface EstadoPolitica {
  id: string | null;
  cargada: boolean;
  fecha_firma: string | null;
  primer_pago: string | null;
  llego_tarde: boolean;
  storage_path: string | null;
}

const MAX_BYTES_DOC = 50 * 1024 * 1024;
const TIPOS_DOC = "image/jpeg,image/png,image/heic,image/webp,application/pdf";

export default function DocumentacionPage() {
  const router = useRouter();
  const rol = useRolActual();
  const puede = puedeGestionarCatalogos(rol);
  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  const [tipo, setTipo] = useState<TipoDoc>("ruta");
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [sedes, setSedes] = useState<Map<string, string>>(new Map());
  // sede_base_id → CÓDIGO de la sede. Va aparte de `sedes`, que guarda el nombre
  // para imprimir («Taller LIM»), porque las tarifas se buscan por código («LIM»).
  // Tenerlas en un solo mapa fue justamente el bug: se comparaba `sede_codigo`
  // contra el nombre, no coincidía nunca y todo el mundo cobraba la tarifa
  // general. Dos preguntas distintas, dos mapas distintos.
  const [sedeCodigo, setSedeCodigo] = useState<Map<string, string>>(new Map());
  const [personaId, setPersonaId] = useState<string>("");
  // La tarifa GENERAL (la fila sin sede). `null` cuando no hay ninguna aplicable
  // — que es el estado real hoy, porque la general vale 0.00 desde la 0118.
  const [tarifa, setTarifa] = useState<number | null>(null);
  const [sustento, setSustento] = useState<string | null>(null);
  const [cargando, setCargando] = useState(true);
  // Quién NO recibe el documento. Se guarda la exclusión y no la inclusión a
  // propósito: el caso normal es que lo reciba todo el equipo, así que una
  // persona nueva entra sola en la lista sin que nadie tenga que acordarse.
  const [excluidos, setExcluidos] = useState<Set<string>>(new Set());
  const [firmaUrl, setFirmaUrl] = useState<string | null>(null);
  // ¿Quien tiene la sesión abierta es quien firma por CAYLA? Hoy hay cuatro
  // cuentas admin y una sola persona firma los documentos de la empresa.
  const [esFirmante, setEsFirmante] = useState(false);
  // El nombre y el cargo que se imprimen. Salen de la ficha de esa persona
  // (0147) y no de un texto escrito acá: así el nombre impreso y la firma
  // estampada no pueden ser de dos personas distintas. Arrancan con la
  // constante de siempre por si la 0147 aún no está pegada en producción.
  const [firmanteNombre, setFirmanteNombre] = useState(EMPRESA.firmante);
  const [firmanteCargo, setFirmanteCargo] = useState(EMPRESA.cargo);
  const [tarifas, setTarifas] = useState<TarifaSede[]>([]);
  // El monto del bono, leído de `parametros_laborales` (0165). `null` mientras no
  // haya fila vigente — y `null` significa «no hay monto», nunca «pon el de
  // siempre». Mismo criterio que `tarifa` con la movilidad.
  const [bonoMonto, setBonoMonto] = useState<number | null>(null);
  // persona_id → fecha de término del contrato, para quien ya la tiene fijada.
  const [finContrato, setFinContrato] = useState<Map<string, string>>(new Map());

  // ── El tablero de firmas ────────────────────────────────────────────────
  const [tablero, setTablero] = useState<FilaTablero[]>([]);
  const [politica, setPolitica] = useState<EstadoPolitica | null>(null);
  // Qué se está subiendo. `que` decide todo lo demás: la política no lleva
  // persona, el bono no lleva monto y solo la ruta admite negativa. Antes esto
  // era un `{personaId, negativa}` y el tipo iba fijo en «ruta» dentro del
  // guardado — por eso solo se podía subir uno de los tres documentos.
  const [subiendo, setSubiendo] = useState<
    { que: TipoDoc; personaId: string | null; negativa: boolean } | null
  >(null);
  const [archivoDoc, setArchivoDoc] = useState<File | null>(null);
  const [fechaFirma, setFechaFirma] = useState("");
  const [notaDoc, setNotaDoc] = useState("");
  const [progresoDoc, setProgresoDoc] = useState<number | null>(null);
  const [guardandoDoc, setGuardandoDoc] = useState(false);
  const [avisoDoc, setAvisoDoc] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  const panelRef = useRef<HTMLDivElement>(null);
  // Las hojas que se imprimen de una vez. `null` = modo normal, una sola hoja:
  // la de la persona elegida arriba. Se llena, se imprime y se vacía; no es un
  // modo en el que la pantalla se quede.
  const [lote, setLote] = useState<Persona[] | null>(null);
  // persona_id → sede donde TRABAJA, que es a dónde hay que llevarle el papel.
  // Distinta de su sede base solo para quien tenga sede física declarada (0166):
  // Estefany figura en Central y trabaja dentro de la tienda de Arequipa, así que
  // su declaración va en el sobre de Arequipa y no en uno aparte.
  const [sedeDeReparto, setSedeDeReparto] = useState<Map<string, string>>(new Map());

  // LA TARIFA QUE LE TOCA A UNA PERSONA. Primero la fila de SU sede; si su sede
  // no tiene fila propia, la general. Es el MISMO orden de preferencia que usan
  // `fn_planilla_calcular` (0142) y `fn_documentos_tablero` (0157), y por eso se
  // escribe una sola vez acá: el monto que se firma en el papel y el que se paga
  // en la boleta no pueden salir de dos lecturas distintas del mismo parámetro.
  //
  // Devuelve `null` cuando no hay ninguna fila aplicable, o cuando la que hay
  // vale cero — que es como nace la general en la 0118. `null` significa «esta
  // sede no tiene tarifa», y quien lo recibe tiene que DECIRLO, nunca rellenarlo
  // con un número: una declaración firmada con una cifra inventada no sostiene
  // la movilidad, la desmiente.
  function tarifaDeSede(sedeBaseId: string | null | undefined): number | null {
    const codigo = sedeBaseId ? sedeCodigo.get(sedeBaseId) : undefined;
    const suya = codigo ? tarifas.find((t) => t.sede_codigo === codigo) : undefined;
    const fila = suya ?? tarifas.find((t) => !t.sede_codigo);
    const valor = Number(fila?.valor);
    return Number.isFinite(valor) && valor > 0 ? valor : null;
  }

  // Imprimir el documento de una persona es poner la pantalla en él y llamar a
  // imprimir: la maquinaria que ya existía no se toca.
  // Imprimir de una vez las hojas que faltan. El flujo real nunca fue de a uno:
  // se saca el lote, se reparte por sede, y vuelve firmado en días distintos.
  // Un botón por fila obligaba a veinte pasadas por el diálogo de impresión, y
  // a la vigésima nadie recuerda cuáles ya sacó.
  function imprimirLote(que: TipoDoc, filas: FilaTablero[]) {
    const candidatas = filas
      .map((f) => personas.find((per) => per.id === f.persona_id))
      .filter((per): per is Persona => Boolean(per));

    // El bono necesita su monto, y sin él ninguna hoja acredita nada: eso frena
    // el lote entero porque le falta a todo el mundo a la vez.
    if (que === "bono" && bonoMonto === null) {
      setAvisoDoc({ tipo: "error", texto:
        "No hay monto de bono de onomástico vigente en el sistema, así que las constancias " +
        "saldrían sin la suma que acredita. Fíjalo en parámetros laborales (bono_onomastico)." });
      return;
    }

    // La tarifa, en cambio, falta PERSONA POR PERSONA. Se sacan las que sí se
    // pueden y se dice quién quedó fuera: frenar las diecinueve buenas por una
    // sin tarifa es cambiar un problema de una persona por uno de veinte.
    const fuera = que === "ruta"
      ? candidatas.filter((per) => tarifaDeSede(per.sede_base_id) === null)
      : [];
    const quienes = candidatas.filter((per) => !fuera.includes(per));

    if (quienes.length === 0) {
      setAvisoDoc({ tipo: "error", texto:
        "Ninguna de estas personas tiene tarifa de movilidad vigente en su sede, así que no " +
        "hay ninguna declaración que imprimir." });
      return;
    }

    // Agrupadas por la sede a la que hay que llevarlas. Sin esto salen en el
    // orden del tablero —TRU, AQP y CCO mezcladas— y hay que separar dieciséis
    // hojas a mano mirando el encabezado de cada una. Una hoja en el sobre
    // equivocado es una persona que no firma, y no se descubre hasta que
    // alguien pregunta por ella.
    const ordenadas = [...quienes].sort((a, b) => {
      const sedeA = sedeCodigo.get(sedeDeReparto.get(a.id) ?? a.sede_base_id) ?? "";
      const sedeB = sedeCodigo.get(sedeDeReparto.get(b.id) ?? b.sede_base_id) ?? "";
      // Dentro de cada sede, por apellido: así el taco se recorre igual que la
      // lista de la pantalla y se puede ir tachando.
      return sedeA.localeCompare(sedeB) || a.apellidos.localeCompare(b.apellidos);
    });

    setTipo(que);
    setLote(ordenadas);
    // `window.print()` congela la pestaña con lo que haya pintado en ese
    // instante: sin ceder el turno al navegador para que renderice las hojas
    // nuevas, se imprimiría lo que había antes. No es un retardo de adorno.
    setTimeout(() => {
      window.print();
      // Se vacía SIEMPRE, aunque se cancele el diálogo. Un lote que se queda
      // puesto deja la pantalla con veinte documentos uno debajo de otro, y
      // quien lo vea va a pensar que algo se rompió.
      setLote(null);
    }, 80);

    // Cuántas van a cada sede, en el mismo orden en que salen impresas: así el
    // taco se corta contando, sin mirar hoja por hoja de quién es.
    const porSedeDelLote = new Map<string, number>();
    for (const per of ordenadas) {
      const cod = sedeCodigo.get(sedeDeReparto.get(per.id) ?? per.sede_base_id) ?? "?";
      porSedeDelLote.set(cod, (porSedeDelLote.get(cod) ?? 0) + 1);
    }
    const desglose = [...porSedeDelLote].map(([cod, n]) => `${cod} ${n}`).join(" · ");

    setAvisoDoc(fuera.length === 0
      ? { tipo: "ok", texto:
          `${ordenadas.length} ${ordenadas.length === 1 ? "hoja" : "hojas"} a la impresora, `
          + `agrupadas por sede: ${desglose}.` }
      : { tipo: "error", texto:
          `Se imprimieron ${ordenadas.length} (${desglose}). Quedaron fuera ${fuera.length}: ` +
          fuera.map((per) => `${per.nombres} ${per.apellidos}`).join(", ") +
          " — su sede no tiene tarifa de movilidad vigente, así que su declaración saldría sin monto." });
  }

  function imprimirFila(personaId: string, que: TipoDoc) {
    setLote(null);
    // Salvo cuando el papel saldría con el monto equivocado. La declaración de
    // ruta es lo que hace que la movilidad no sea remuneración; si la sede de
    // esta persona no tiene tarifa, no hay monto que declarar y el documento no
    // se imprime. Se frena ACÁ y no solo en el render porque desde el tablero se
    // imprime a ciegas: el botón dispara `window.print()` sin que nadie mire.
    const ficha = personas.find((p) => p.id === personaId);
    // La constancia del bono, por lo mismo: acredita la entrega de una suma, y
    // sin suma no acredita nada. Va antes que la de ruta porque no depende de la
    // ficha de la persona — falta el parámetro para todo el mundo a la vez.
    if (que === "bono" && bonoMonto === null) {
      setAvisoDoc({ tipo: "error", texto:
        "No hay monto de bono de onomástico vigente en el sistema, así que la constancia " +
        "saldría sin la suma que acredita. Fíjalo en parámetros laborales (bono_onomastico) " +
        "y vuelve a imprimir." });
      return;
    }
    if (que === "ruta" && ficha && tarifaDeSede(ficha.sede_base_id) === null) {
      setAvisoDoc({ tipo: "error", texto:
        `La sede ${sedes.get(ficha.sede_base_id) ?? "de esta persona"} no tiene tarifa de movilidad vigente, ` +
        "así que su declaración saldría sin monto. Créala en parámetros laborales y vuelve a imprimir." });
      return;
    }
    setTipo(que);
    setPersonaId(personaId);
    // El render tiene que haber corrido con la persona puesta antes de imprimir.
    setTimeout(() => window.print(), 60);
  }

  function abrirSubida(que: TipoDoc, personaId: string | null, negativa = false) {
    setSubiendo({ que, personaId, negativa });
    setArchivoDoc(null);
    setNotaDoc("");
    // La política llega con la fecha del papel que se imprimió, no con la de
    // hoy. Proponer hoy era empujar al error: el formulario ofrecía de entrada
    // el único valor que el propio sistema iba a marcar en rojo.
    setFechaFirma(que === "politica" ? fechaDeLaPolitica : hoyLima());
    setAvisoDoc(null);
    // El formulario es uno solo y vive arriba; el botón que lo abre puede estar
    // veinte filas más abajo. Sin esto, quien hace clic en la última fila no ve
    // que pasó nada y vuelve a hacer clic.
    setTimeout(() => panelRef.current?.scrollIntoView({ behavior: "smooth", block: "center" }), 30);
  }

  // Abrir en una pestaña lo que ya está archivado. Sin esto, quien sube un
  // escaneo no tiene forma de comprobar que subió el archivo correcto — y el
  // error de subir el papel equivocado es invisible hasta que lo pide un
  // inspector. La URL se firma al momento y dura un minuto: el bucket es
  // privado y así sigue siéndolo.
  async function verDocumento(path: string) {
    const { data, error } = await supabase.storage.from("documentos").createSignedUrl(path, 60);
    if (error || !data) {
      setAvisoDoc({ tipo: "error", texto: mensajeDeError(error, "abrir el documento") });
      return;
    }
    window.open(data.signedUrl, "_blank", "noopener");
  }

  async function guardarDocumento() {
    if (!subiendo) return;
    if (!archivoDoc) {
      setAvisoDoc({ tipo: "error", texto: subiendo.negativa
        ? "Falta el acta de la negativa. Sin el papel con el testigo, no queda constancia de que se ofreció."
        : `Falta el archivo ${ETIQUETA_SUBIDA[subiendo.que].deQue} firmado.` });
      return;
    }
    if (archivoDoc.size > MAX_BYTES_DOC) {
      setAvisoDoc({ tipo: "error", texto: `“${archivoDoc.name}” pesa ${(archivoDoc.size / 1048576).toFixed(1)} MB y el máximo es 50 MB.` });
      return;
    }
    if (!fechaFirma) {
      setAvisoDoc({ tipo: "error", texto: "Indica en qué fecha se firmó (o en qué fecha se dejó constancia de la negativa)." });
      return;
    }

    setGuardandoDoc(true);
    // El monto viene puesto con la tarifa de SU sede: es lo que el documento
    // imprimió. En una negativa no viaja monto — no se firmó nada. El bono lleva
    // su monto fijo, y la política no lleva ninguno: no promete una cifra a
    // nadie en particular, describe la regla.
    const fila = tablero.find((f) => f.persona_id === subiendo.personaId);
    const persona = personas.find((p) => p.id === subiendo.personaId);
    // Antes acá se buscaba `t.sede_codigo === sedes.get(...)`, o sea el código
    // «LIM» contra el nombre «Taller LIM»: no coincidía nunca y el monto que se
    // archivaba era el general, no el de la sede. El mismo defecto que en el
    // documento impreso, y por eso ahora los dos llaman a la misma función.
    const tarifaSede = tarifaDeSede(persona?.sede_base_id);
    const monto = subiendo.negativa || subiendo.que === "politica"
      ? null
      : subiendo.que === "bono" ? bonoMonto : tarifaSede;

    // El año solo lo lleva el bono, y es el de la FIRMA, no el de hoy: si el
    // cargo de diciembre se sube el 3 de enero, sigue siendo el bono del año que
    // pasó. Guardarlo como el de hoy dejaría al año viejo pendiente para siempre
    // y al nuevo firmado sin haberse entregado.
    const anio = subiendo.que === "bono" ? Number(fechaFirma.slice(0, 4)) : null;

    const { data: id, error } = await supabase.rpc("fn_documento_registrar", {
      p_tipo: subiendo.que,
      p_fecha_firma: fechaFirma,
      p_persona_id: subiendo.personaId,
      p_monto_declarado: monto,
      p_anio: anio,
      p_es_negativa: subiendo.negativa,
      p_nota: notaDoc.trim() || null,
    });
    if (error || !id) {
      setGuardandoDoc(false);
      setAvisoDoc({ tipo: "error", texto: mensajeDeError(error, "guardar") });
      return;
    }

    const ext = archivoDoc.name.split(".").pop()?.toLowerCase() ?? "bin";
    const ruta = `documentos/${id}.${ext}`;
    setProgresoDoc(0);
    const fallo = await subirArchivoConProgreso(supabase, "documentos", ruta, archivoDoc, setProgresoDoc);
    setProgresoDoc(null);
    if (fallo) {
      setGuardandoDoc(false);
      setAvisoDoc({ tipo: "error", texto: `El registro se guardó pero el archivo no subió (${fallo}). Vuelve a intentarlo desde su fila.` });
      await cargar();
      return;
    }
    await supabase.rpc("fn_documento_registrar", {
      p_tipo: subiendo.que, p_fecha_firma: fechaFirma, p_persona_id: subiendo.personaId,
      p_storage_path: ruta, p_id: id,
    });

    const quien = fila?.persona ?? "la persona";
    setGuardandoDoc(false);
    setSubiendo(null);
    await cargar();
    setAvisoDoc({ tipo: "ok", texto: subiendo.negativa
      ? `Negativa registrada para ${quien}. Queda constancia de que se ofreció; no habilita el pago de movilidad.`
      : subiendo.que === "politica"
        ? "Política de movilidad archivada. Ya sostiene a todo el equipo."
        : subiendo.que === "bono"
          ? `Cargo del bono de ${quien} archivado.`
          : `Declaración de ${quien} archivada.` });
  }

  const cargar = useCallback(async () => {
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }
    const [{ data: ps }, { data: ss }, { data: cfg }] = await Promise.all([
      supabase.from("personas")
        .select("id, nombres, apellidos, documento, funcion, sede_base_id, fecha_ingreso, en_planilla, tipo_vinculo")
        .eq("estado", "activo").order("apellidos"),
      supabase.from("sedes").select("id, nombre, codigo"),
      // La tarifa vigente hoy. Si la 0118 no está pegada esto devuelve vacío, y
      // entonces la pantalla lo dice en vez de inventar un monto.
      //
      // ⇩ `hoyLima()` Y NO `new Date()`. Acá decía
      // `new Date().toISOString().slice(0, 10)`, que es la fecha en UTC — cinco
      // horas por delante de Lima. O sea que desde las 7 de la tarde hora de Perú
      // esta consulta ya creía que era mañana, y una tarifa programada para
      // mañana se habría impreso esa misma noche: alguien firmando un monto que
      // ese día todavía no le correspondía.
      //
      // Es la regla que el CLAUDE.md se ganó juntando 32 copias del huso horario
      // repartidas por el código: el corte del día vive en `fecha-lima.ts` y en
      // ningún otro lado. Veinticinco líneas más abajo la consulta del bono ya lo
      // hacía bien — dos respuestas a «¿qué día es hoy?» en la misma función.
      supabase.from("parametros_laborales")
        .select("valor, vigente_desde, sustento, sede_codigo")
        .eq("clave", "movilidad_diaria")
        .lte("vigente_desde", hoyLima())
        .is("vigente_hasta", null)
        .order("vigente_desde", { ascending: false }),
    ]);
    const lista = (ps as Persona[]) ?? [];
    setPersonas(lista);

    // El tablero y el estado de la política, en consultas aparte y tolerantes:
    // si la 0157 todavía no está pegada en producción, la pantalla sigue
    // imprimiendo — que es lo que hacía antes de que existiera el tablero.
    // Mismo criterio que la tarifa y el fin de contrato de acá arriba.
    const [tab, pol] = await Promise.all([
      supabase.rpc("fn_documentos_tablero"),
      supabase.rpc("fn_documentos_estado_politica"),
    ]);
    setTablero((tab.data as FilaTablero[]) ?? []);
    setPolitica(((pol.data as EstadoPolitica[]) ?? [])[0] ?? null);

    // El monto del bono, en consulta aparte por lo mismo que el tablero: si la
    // 0165 todavía no está pegada, que falle ESTA consulta y no las demás.
    //
    // Pero «tolerante» acá NO significa inventar el monto. Se GUARDA lo que hay,
    // incluido «no hay»: sin fila vigente queda en null y la constancia no se
    // imprime. La pantalla se degrada a «no puedo emitir este papel y te digo por
    // qué», nunca a «emito el papel con la cifra que me acuerdo».
    const { data: bono } = await supabase
      .from("parametros_laborales")
      .select("valor")
      .eq("clave", "bono_onomastico")
      .lte("vigente_desde", hoyLima())
      .is("vigente_hasta", null)
      .order("vigente_desde", { ascending: false })
      .limit(1);
    const montoBono = Number((bono as { valor: number }[] | null)?.[0]?.valor);
    setBonoMonto(Number.isFinite(montoBono) && montoBono > 0 ? montoBono : null);

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

    // Dónde trabaja cada quien. Consulta APARTE y tolerante por lo mismo que la
    // de arriba: si la 0166 no está pegada, pedir `sede_fisica_id` en el select
    // principal haría fallar la consulta entera y la pantalla se quedaría sin
    // nadie. Así, si falla, simplemente todos se reparten por su sede base.
    const { data: fisicas } = await supabase
      .from("personas")
      .select("id, sede_fisica_id")
      .eq("estado", "activo")
      .not("sede_fisica_id", "is", null);
    setSedeDeReparto(new Map(
      ((fisicas as { id: string; sede_fisica_id: string }[] | null) ?? [])
        .map((f) => [f.id, f.sede_fisica_id]),
    ));
    const listaSedes = (ss as { id: string; nombre: string; codigo: string }[]) ?? [];
    // El NOMBRE para imprimir y el CÓDIGO para buscar su tarifa. Ver `tarifaDeSede`.
    setSedes(new Map(listaSedes.map((s) => [s.id, s.nombre || s.codigo])));
    setSedeCodigo(new Map(listaSedes.map((s) => [s.id, s.codigo])));

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
    // Y quien TERMINA CONTRATO ESTE MES O ANTES: se va, así que no firma un
    // documento que regirá cuando ya no esté. Este era justamente el caso que el
    // comentario de más abajo daba por indeducible («alguien que se va a fin de
    // mes, y eso no está en ninguna columna») — desde la 0144 SÍ está en una
    // columna, así que ya no hace falta acordarse.
    //
    // EL CORTE ES «ESTE MES», el mismo que usa el tablero desde la 0162, y no
    // «tiene fecha de fin». Hasta el 2026-08-06 esta pantalla desmarcaba a
    // cualquiera con fecha, y eso hacía que el sistema se contradijera sobre la
    // misma persona el mismo día: a quien tiene contrato hasta diciembre el
    // tablero le pedía la firma y esta lista la sacaba del reparto. En una lista
    // de ~30 casillas, un desmarcado de más no se revisa — y esa persona cobra
    // movilidad cinco meses más, así que necesita el papel que la sostiene.
    const finDeMes = rangoDelMesLima().fin;
    for (const [id, fecha] of porVencer) if (fecha <= finDeMes) fuera.add(id);
    const { data: yo } = await supabase.rpc("fn_persona_actual_id");
    if (typeof yo === "string") fuera.add(yo);
    setExcluidos(fuera);

    // QUIÉN FIRMA POR CAYLA. Sale de `configuracion` desde la 0147, guardado
    // como la PERSONA y no como su nombre. De ahí salen las dos cosas: el
    // nombre que se imprime bajo la raya y la respuesta a «¿soy yo?». Como las
    // dos vienen de la misma fila, no pueden contradecirse — antes eran un
    // texto fijo y una sesión abierta, y bastaba que otra admin imprimiera para
    // que saliera su rúbrica bajo el nombre de Felipe.
    //
    // Si la fila no está —la 0147 sin pegar todavía— se queda la constante de
    // siempre y la raya sale en blanco. El documento nunca deja de imprimirse
    // por no poder leer un parámetro; mismo criterio que la tarifa de movilidad.
    const { data: cfgFirmante } = await supabase
      .from("configuracion").select("valor").eq("clave", "firmante_empresa").maybeSingle();
    const vf = (cfgFirmante?.valor ?? null) as { persona_id?: string; cargo?: string } | null;
    const firmanteId = vf?.persona_id ?? null;
    // El trigger de la 0147 garantiza que esa persona está activa, así que tiene
    // que estar en `lista` — que son las activas.
    const fichaFirmante = firmanteId ? lista.find((p) => p.id === firmanteId) : undefined;
    if (fichaFirmante) setFirmanteNombre(`${fichaFirmante.apellidos} ${fichaFirmante.nombres}`);
    if (vf?.cargo) setFirmanteCargo(vf.cargo);
    setEsFirmante(Boolean(firmanteId) && firmanteId === yo);

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
    // Se GUARDA lo que hay, incluido «no hay». Antes, cuando la general valía 0,
    // este `if` no entraba y quedaba en pie el 10 escrito a mano: el papel decía
    // una cifra que la base nunca había dicho.
    setTarifa(Number.isFinite(monto) && monto > 0 ? monto : null);
    // El sustento viaja pegado a la tarifa en la base (0118). Se muestra en el
    // documento en lugar de repetirlo en el código: así el papel dice
    // exactamente lo que la fila que se está aplicando dice.
    if (general?.sustento) setSustento(general.sustento);
    setCargando(false);
  }, [supabase, router]);

  useEffect(() => { void cargar(); }, [cargar]);

  const persona = personas.find((p) => p.id === personaId);
  const nombre = persona ? `${persona.nombres} ${persona.apellidos}` : "";

  // La rúbrica que de verdad se imprime. Hacen falta las dos cosas: tener firma
  // cargada Y ser quien la línea nombra. Si falta cualquiera de las dos el
  // documento sale con la raya en blanco, que es como salía antes — nunca se
  // rompe, solo deja de estamparse.
  const firmaEstampada = esFirmante ? firmaUrl : null;
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
  const mensual = tarifa === null ? null : tarifa * DIAS_REFERENCIA;

  // La tarifa de quien está seleccionado. Es la que se imprime en SU declaración
  // y la que se archiva cuando sube el escaneo — el mismo número por el mismo
  // camino, para que el papel y el registro no puedan discrepar.
  const tarifaPersona = persona ? tarifaDeSede(persona.sede_base_id) : null;

  // Las tarifas que tienen sede propia, ordenadas. Si está vacío es que la 0130
  // no está pegada y el documento cae al monto único de siempre.
  const porSede = tarifas
    .filter((t) => Boolean(t.sede_codigo))
    .sort((a, b) => (a.sede_codigo ?? "").localeCompare(b.sede_codigo ?? ""));

  // Quiénes reciben el documento y firman el cargo.
  const reciben = personas.filter((p) => !excluidos.has(p.id));

  // ── La fecha de la política, que NO es hoy ──────────────────────────────
  // Se imprimía con `hoyLima()`, y eso hacía que la pantalla se contradijera
  // sola: sacabas la política, salía «Emitida el 5 de agosto», la firmabas, la
  // subías, y el propio sistema la marcaba en rojo por ser posterior al primer
  // pago. Te daba a imprimir el documento que iba a rechazar.
  //
  // Y el papel nacía inválido para lo que tiene que cubrir: una política emitida
  // en agosto no justifica la movilidad que se viene pagando desde el 29 de
  // julio. La fecha correcta es la del día en que empezó a pagarse — desde ahí
  // rige, hacia adelante.
  //
  // Si ya hay una firmada, manda SU fecha: reimprimirla no puede cambiarle la
  // fecha al documento que ya está archivado. Y si no se sabe cuándo empezó a
  // pagarse (no hay tarifa vigente), cae a hoy, que es lo que hacía siempre.
  const fechaDeLaPolitica = politica?.fecha_firma ?? politica?.primer_pago ?? hoyLima();

  // A quién hay que perseguirle el cargo del bono. Se cuenta una sola vez y se
  // usa en el resumen y en el aviso: dos conteos del mismo hecho es la forma
  // más barata de que la pantalla se contradiga a sí misma.
  const bonoPendientes = tablero.filter((f) => BONO_PENDIENTE.has(f.bono_estado ?? ""));
  const bonoEsteMes = bonoPendientes.filter((f) => f.bono_estado === "este_mes");
  // Quién sale en el apartado del bono: quien tiene algo pendiente y quien ya
  // firmó este año. Los demás —cumple en octubre, entró después, sin fecha
  // cargada— no aparecen: son 'nada que hacer' y llenaban la tabla de filas que
  // solo enseñaban a ignorarla.
  const bonoRelevantes = tablero.filter(
    (f) => BONO_PENDIENTE.has(f.bono_estado ?? "") || f.bono_estado === "ok");
  const rutasPendientes = tablero.filter((f) => f.estado !== "ok");

  // ── La hoja de un documento ─────────────────────────────────────────────
  // Esto vivía escrito directamente en el `return`, atado a la ÚNICA persona
  // elegida en el desplegable. Por eso no se podía imprimir un lote: no había
  // forma de pedir la misma hoja para veinte personas sin duplicar 378 líneas.
  //
  // Es una función que devuelve JSX, no un componente. Un componente definido
  // dentro de otro se vuelve a montar en cada render —React lo trata como un
  // tipo nuevo cada vez— y aquí eso significaría que el documento parpadea
  // mientras se escribe en el formulario de arriba.
  //
  // Lo único que cambia entre una hoja y otra es la persona y su tarifa. Todo lo
  // demás —el firmante, el logo, la política, los textos legales— es igual para
  // las veinte, y por eso sigue saliendo del closure en vez de viajar como
  // parámetro: veinte props que nunca cambian solo esconden las dos que sí.
  function hoja(quien: Persona | null | undefined) {
    const tarifaSuya = quien ? tarifaDeSede(quien.sede_base_id) : null;
    return (
      <div className="hoja rounded-lg border border-sand p-8 text-sm leading-relaxed print:rounded-none print:border-0 print:p-0">
        <div className="mb-6 flex items-start justify-between border-b border-sand pb-4">
          <Marca tono="tinta" isotipo="rojo" />
          <div className="text-right text-xs text-taupe">
            <p>{EMPRESA.nombre}</p>
            <p>RUC {EMPRESA.ruc}</p>
          </div>
        </div>

        {/* SIN TARIFA NO HAY DECLARACIÓN. Este documento existe para dejar
            por escrito un monto pactado; si la sede de la persona no tiene
            tarifa vigente, no hay monto que pactar y lo único honesto es
            decirlo. Antes salía con un valor por defecto de S/ 10.00 y se
            firmaba así: un pacto individual por una cifra que la base nunca
            fijó es peor que no tener papel, porque deja constancia escrita
            de que el monto lo decidió alguien y no un criterio —que es
            exactamente lo que el Exp. 1038-2019 usó para reclasificar una
            movilidad entera. */}
        {tipo === "ruta" && quien && tarifaSuya === null && (
          <div className="rounded-lg border border-rojo bg-rojo/5 p-4 text-sm">
            <p className="mb-2">
              <strong className="text-rojo">
                La sede {sedes.get(quien.sede_base_id) ?? "de esta persona"} no tiene
                tarifa de movilidad vigente.
              </strong>
            </p>
            <p className="mb-2">
              Por eso no se puede emitir su declaración de ruta: el documento tiene que
              decir cuánto se le paga por día, y ese número sale de{" "}
              <code>parametros_laborales</code>, no de esta pantalla.
            </p>
            <p className="text-taupe">
              Crea la tarifa de esa sede —con su sustento, como las de Arequipa, Trujillo
              y Lima— y vuelve a entrar. Mientras no exista, la planilla tampoco le está
              pagando movilidad a esta persona.
            </p>
          </div>
        )}

        {tipo === "ruta" && quien && tarifaSuya !== null && (
          <>
            <h2 className="mb-6 text-center font-serif text-xl">
              Declaración de ruta y gasto de transporte
            </h2>

            <p className="mb-4">
              Yo, <strong>{nombre}</strong>, con documento de identidad N.º{" "}
              {quien.documento ? <strong>{quien.documento}</strong> : <Linea ancho="8rem" />}, que
              desempeño el cargo de <strong>{quien.funcion}</strong> en la sede{" "}
              <strong>{sedes.get(quien.sede_base_id) ?? "—"}</strong> de {EMPRESA.nombre},
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
              {/* LA TARIFA DE SU SEDE, no la general. Acá decía `tarifa` a
                  secas y por eso Taller LIM firmaba S/ 10.00 mientras la
                  planilla le pagaba los S/ 12.00 de la 0142. */}
              <strong>S/ {tarifaSuya.toFixed(2)} por día efectivamente asistido</strong>, destinada
              a cubrir dicho traslado; que se abona únicamente por los días en que asisto a
              laborar, no correspondiendo en caso de inasistencia, licencia o descanso; y que
              este concepto <strong>no tiene carácter remunerativo</strong>, conforme al
              artículo 19 inciso e) del Decreto Supremo N.º 001-97-TR.
            </p>

            <p className="mb-10 text-xs text-taupe">
              {/* La fecha va en blanco y NO con `hoyLima()`. Se imprimen veinte
                  declaraciones de una vez y se reparten a cuatro sedes: quien firma
                  el jueves en Arequipa lo hace sobre un papel impreso el lunes, y
                  con la fecha impresa ese documento afirmaría un día en el que nadie
                  firmó. La escribe de su puño quien firma, que es quien sabe cuándo. */}
              Suscrito en {sedes.get(quien.sede_base_id) ?? "—"}, el <Linea ancho="9rem" />.
            </p>

            <div className="grid grid-cols-2 gap-10 pt-6">
              {/* La declarante firma a mano, delante de quien le entrega el
                  papel: es su declaración, no puede venir prefirmada. */}
              <BloqueFirma
                nombre={nombre}
                pie={`DNI ${quien.documento ?? "—————"} · el/la declarante`}
              />
              <BloqueFirma
                imagen={firmaEstampada}
                nombre={firmanteNombre}
                pie={`${firmanteCargo} · ${EMPRESA.nombre}`}
              />
            </div>
          </>
        )}

        {/* SIN MONTO NO HAY CONSTANCIA. Este papel acredita una entrega de
            dinero y su causa; si el sistema no sabe cuánto se entrega, no hay
            nada que acreditar. Mismo criterio que la declaración de ruta, y
            por el mismo motivo: la constancia se firma, y una cifra puesta
            por el código en vez de por la base es una afirmación que nadie
            decidió. */}
        {tipo === "bono" && bonoMonto === null && (
          <div className="rounded-lg border border-rojo bg-rojo/5 p-4 text-sm">
            <p className="mb-2">
              <strong className="text-rojo">
                No hay monto de bono de onomástico vigente en el sistema.
              </strong>
            </p>
            <p className="mb-2">
              Por eso no se puede emitir la constancia: el documento acredita la entrega
              de una suma, y esa suma sale de <code>parametros_laborales</code> con la
              clave <code>bono_onomastico</code>, no de esta pantalla.
            </p>
            <p className="text-taupe">
              Si acabas de cambiar el monto, revisa que la fila nueva tenga su{" "}
              <code>vigente_desde</code> puesto y que no haya quedado cerrada con{" "}
              <code>vigente_hasta</code>. Mientras no exista una fila vigente, el sistema
              no sabe cuánto se entrega.
            </p>
          </div>
        )}

        {tipo === "bono" && bonoMonto !== null && (
          <>
            <h2 className="mb-6 text-center font-serif text-xl">
              Asignación por cumpleaños
            </h2>

            <p className="mb-4">
              {EMPRESA.nombre}, con RUC {EMPRESA.ruc}, hace entrega a{" "}
              <strong>{quien ? `${quien.nombres} ${quien.apellidos}` : "—"}</strong>
              {quien?.documento ? `, con documento de identidad ${quien.documento},` : ","}{" "}
              de la suma de <strong>S/ {bonoMonto.toFixed(2)}</strong> con ocasión de su
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

            {/* Este papel no llevaba NINGUNA fecha, y un cargo de entrega sin fecha
                acredita la mitad de lo que tiene que acreditar: prueba que se
                entregó, no cuándo. Y el «cuándo» es lo que decide a qué ejercicio
                pertenece el bono y si se entregó en el mes del onomástico, que es la
                causa que lo vuelve no remunerativo. Va en blanco por lo mismo que la
                declaración de ruta: la escribe quien recibe, el día que recibe. */}
            <p className="mb-6">
              Entregada y recibida el <Linea ancho="9rem" />.
            </p>

            <div className="mt-16 grid grid-cols-2 gap-12">
              {/* Quien recibe el bono firma al recibirlo: esa firma es la
                  prueba de la entrega, así que no puede ir impresa. */}
              <BloqueFirma
                nombre={quien ? `${quien.nombres} ${quien.apellidos}` : "\u00a0"}
                pie="Recibí conforme"
              />
              <BloqueFirma
                imagen={firmaEstampada}
                nombre={firmanteNombre}
                pie={`${firmanteCargo} · ${EMPRESA.nombre}`}
              />
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
            ) : tarifa !== null ? (
              <p className="mb-4">
                CAYLA otorga a su personal una asignación por movilidad de{" "}
                <strong>S/ {tarifa.toFixed(2)} por día efectivamente asistido</strong> —
                equivalente a S/ {mensual!.toFixed(2)} en un mes de {DIAS_REFERENCIA} días
                asistidos — destinada exclusivamente a cubrir el traslado desde su domicilio
                hasta su centro de labores y su retorno.
              </p>
            ) : (
              /* Ni tarifas por sede ni tarifa general: no hay política que
                 emitir. Mismo criterio que la declaración de ruta — un
                 documento de empresa que afirma un monto inventado obliga a
                 las 22 personas a la vez. */
              <p className="mb-4 rounded-lg border border-rojo bg-rojo/5 p-3 text-rojo print:hidden">
                No hay ninguna tarifa de movilidad vigente en el sistema, así que esta
                política no puede afirmar un monto. Créala en parámetros laborales antes de
                emitirla.
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
              Emitida el {fechaLarga(fechaDeLaPolitica)}.
            </p>

            <div className="mb-10 w-1/2">
              <BloqueFirma
                imagen={firmaEstampada}
                nombre={firmanteNombre}
                pie={`${firmanteCargo} · ${EMPRESA.nombre}`}
              />
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
    );
  }

  return (
    <>
      <div className="print:hidden"><AdminNav /></div>

      <main className="mx-auto max-w-3xl p-6 print:max-w-none print:p-0">
        {/* Controles — no se imprimen */}
        <div className="mb-6 print:hidden">
          <h1 className="mb-1 font-serif text-2xl">Documentación</h1>
          <p className="mb-4 text-sm text-taupe">
            Imprime la declaración de cada integrante, recoge la firma y súbela acá. El papel
            firmado es lo que sostiene que la movilidad no sea remuneración.
          </p>

          {/* ── La política de empresa ──────────────────────────────────────
              Va arriba y en rojo porque su ausencia afecta a las 22 personas a
              la vez, no a una. Y porque el error caro —firmarla DESPUÉS de haber
              empezado a pagar— es invisible a ojo y el sistema sí puede verlo:
              un documento fechado en septiembre no justifica los pagos de agosto,
              y encima lo deja por escrito. */}
          {politica && (!politica.cargada || politica.llego_tarde) && (
            <div className="mb-4 rounded-lg border border-rojo bg-rojo/5 p-3 text-sm">
              {!politica.cargada ? (
                <>
                  <strong className="text-rojo">Falta la política de movilidad de CAYLA.</strong>{" "}
                  Es un solo documento, lo firmas tú, y sostiene a todo el equipo.{" "}
                  {politica.primer_pago && (
                    // Decía «anterior al 29 de julio» y el cálculo acepta el 29:
                    // `fecha_firma > primer_pago`. El texto pedía una fecha que
                    // el sistema no exige, y encima la equivocada — la política
                    // rige DESDE el día en que empezó a pagarse la movilidad.
                    <>Va fechada el <strong>{fechaLarga(politica.primer_pago)}</strong>, que es
                    cuando empezó a pagarse movilidad: rige desde ese día en adelante. Sale
                    impresa con esa fecha.</>
                  )}
                </>
              ) : (
                <>
                  <strong className="text-rojo">La política está firmada después del primer pago.</strong>{" "}
                  Se firmó el {fechaLarga(politica.fecha_firma!)} y la movilidad se paga desde el{" "}
                  {fechaLarga(politica.primer_pago!)}. Un documento posterior a los pagos que
                  justifica no los justifica — y queda por escrito.
                </>
              )}
              {/* Sin este botón el aviso se podía leer pero no cerrar: decía qué
                  falta y no dejaba resolverlo en la misma pantalla. */}
              <div className="mt-2 flex flex-wrap items-center gap-3">
                <button onClick={() => { setTipo("politica"); setTimeout(() => window.print(), 60); }}
                  className="text-xs font-medium underline">Imprimir</button>
                <button onClick={() => abrirSubida("politica", null)}
                  className="rounded-lg border border-rojo px-3 py-1 text-xs font-medium text-rojo">
                  {politica.cargada ? "Subir otra" : "Subir la política firmada"}
                </button>
              </div>
            </div>
          )}

          {/* Cuando está bien no grita, pero sigue estando a la mano: si no se
              puede abrir lo archivado, nadie descubre que subió el papel
              equivocado hasta que lo pide un inspector. */}
          {politica?.cargada && !politica.llego_tarde && (
            <div className="mb-4 flex flex-wrap items-center gap-3 rounded-lg border border-sand px-3 py-2 text-sm text-taupe">
              <span>
                Política de movilidad firmada el{" "}
                <strong className="text-tinta">{fechaLarga(politica.fecha_firma!)}</strong>.
              </span>
              {politica.storage_path && (
                <button onClick={() => void verDocumento(politica.storage_path!)}
                  className="text-xs font-medium underline">Ver</button>
              )}
              <button onClick={() => abrirSubida("politica", null)}
                className="text-xs underline">Reemplazar</button>
            </div>
          )}

          {/* ── El bono del mes ─────────────────────────────────────────────
              El cargo del onomástico se olvida por calendario, no por descuido:
              se entrega una vez al año y en diciembre nadie recuerda si alguien
              firmó en agosto. Por eso el aviso es del MES, no de la persona. */}
          {bonoPendientes.length > 0 && (
            <div className="mb-4 rounded-lg border border-sand bg-sand/20 p-3 text-sm">
              {bonoEsteMes.length > 0 && (
                <div>
                  <strong className="text-tinta">
                    {bonoEsteMes.length === 1 ? "Cumple años este mes" : `Cumplen años este mes: ${bonoEsteMes.length}`}
                  </strong>{" "}
                  — {bonoEsteMes.map((f) => f.persona).join(" · ")}.{" "}
                  {/* Sin monto en la base, el aviso deja de decir cuánto entregar
                      y pasa a decir qué falta. Nombrar una cifra acá y otra en el
                      papel es la contradicción que este archivo existe para
                      evitar. */}
                  {bonoMonto === null ? (
                    <>Falta fijar el monto del bono en parámetros laborales
                    (<code>bono_onomastico</code>): hasta entonces la constancia no se
                    puede emitir.</>
                  ) : (
                    <>Imprime su constancia, entrega los S/ {bonoMonto.toFixed(2)} y
                    sube el cargo firmado.</>
                  )}
                </div>
              )}
              {bonoPendientes.length > bonoEsteMes.length && (
                <div className={bonoEsteMes.length > 0 ? "mt-2" : ""}>
                  <strong className="text-rojo">
                    {bonoPendientes.length - bonoEsteMes.length} sin cargo de un mes que ya pasó.
                  </strong>{" "}
                  Un pago sin el papel que dice por qué se hizo es un pago sin causa acreditada.
                </div>
              )}
            </div>
          )}

          {/* ── El panel de subida ──────────────────────────────────────────
              Uno solo para los tres documentos, y fuera del tablero. Estaba
              dentro, y por eso la política —que se sube desde el aviso de
              arriba— habría abierto un formulario invisible el día que el
              tablero venga vacío. Un formulario que existe pero no se ve es
              peor que uno que falta: quien lo usa cree que hizo clic mal. */}
          {avisoDoc && !subiendo && (
            <div className={`mb-4 rounded-lg border px-3 py-2 text-sm ${
              avisoDoc.tipo === "ok" ? "border-sand text-tinta" : "border-rojo text-rojo"}`}>
              {avisoDoc.texto}
            </div>
          )}

          {subiendo && (
            <div ref={panelRef} className="mb-6 rounded-lg border border-sand bg-sand/20 p-4">
              <h3 className="mb-1 text-sm font-medium">
                {subiendo.negativa ? "Registrar una negativa a firmar" : ETIQUETA_SUBIDA[subiendo.que].titulo}
                {/* La política no es de nadie: ponerle un nombre al lado la
                    haría parecer un documento personal, que es exactamente
                    la confusión que la 0157 diseñó para hacer imposible. */}
                {subiendo.personaId && (
                  <>{" — "}{tablero.find((f) => f.persona_id === subiendo.personaId)?.persona}</>
                )}
              </h3>
              <p className="mb-3 text-xs text-taupe">
                {subiendo.negativa
                  ? "Sube el acta con testigo. Queda constancia de que se ofreció firmar, pero NO habilita el pago de movilidad: sin pacto individual el monto deja de ser no remunerativo."
                  : ETIQUETA_SUBIDA[subiendo.que].ayuda}
              </p>

              <div className="grid gap-3 sm:grid-cols-2">
                <label className="flex flex-col gap-1 text-sm">
                  {subiendo.negativa ? "Acta de la negativa" : ETIQUETA_SUBIDA[subiendo.que].archivo}
                  <input type="file" accept={TIPOS_DOC}
                    onChange={(e) => setArchivoDoc(e.target.files?.[0] ?? null)}
                    className="rounded-lg border bg-crema px-3 py-2 text-sm file:mr-3 file:rounded file:border-0 file:bg-sand file:px-3 file:py-1 file:text-sm" />
                </label>
                <label className="flex flex-col gap-1 text-sm">
                  {subiendo.negativa ? "Fecha de la negativa" : ETIQUETA_SUBIDA[subiendo.que].fecha}
                  <input type="date" value={fechaFirma} max={hoyLima()}
                    onChange={(e) => setFechaFirma(e.target.value)}
                    className="rounded-lg border px-3 py-2" />
                </label>
                <label className="flex flex-col gap-1 text-sm sm:col-span-2">
                  Nota (opcional)
                  <input value={notaDoc} onChange={(e) => setNotaDoc(e.target.value)}
                    placeholder={subiendo.negativa
                      ? "ej. presente la encargada de TRU como testigo"
                      : ETIQUETA_SUBIDA[subiendo.que].ejemploNota}
                    className="rounded-lg border px-3 py-2" />
                </label>
              </div>

              {progresoDoc !== null && (
                <div className="mt-3">
                  <div className="h-2 w-full overflow-hidden rounded-full bg-sand">
                    <div className="h-full bg-tinta transition-[width] duration-200"
                      style={{ width: `${progresoDoc}%` }}
                      role="progressbar" aria-valuenow={progresoDoc} aria-valuemin={0} aria-valuemax={100}
                      aria-label="Subiendo el documento" />
                  </div>
                  <span className="text-xs text-taupe">Subiendo — {progresoDoc}%</span>
                </div>
              )}

              {/* El error de guardar sale junto al botón que lo produjo. Antes
                  salía en la cabecera del tablero, a media pantalla de distancia
                  del formulario que había fallado. */}
              {avisoDoc && (
                <div className={`mt-3 text-sm ${avisoDoc.tipo === "ok" ? "text-tinta" : "text-rojo"}`}>
                  {avisoDoc.texto}
                </div>
              )}

              <div className="mt-3 flex items-center gap-3">
                <button onClick={() => void guardarDocumento()} disabled={guardandoDoc}
                  className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50">
                  {progresoDoc !== null ? `Subiendo… ${progresoDoc}%` : guardandoDoc ? "Guardando…" : "Guardar"}
                </button>
                <button onClick={() => setSubiendo(null)} className="rounded-lg border px-4 py-2 text-sm">
                  Cancelar
                </button>
              </div>
            </div>
          )}

          {/* ── Los dos apartados ──────────────────────────────────────────
              Antes era UNA tabla con las dos cosas, y cada fila llevaba cinco
              controles: veinte filas por cinco son cien botones en pantalla.
              Peor, los dos «Imprimir» eran idénticos —mismo texto, mismo
              tamaño— y solo el orden decía cuál sacaba la declaración de ruta y
              cuál la constancia del onomástico. Si hay que adivinar cuál es
              cuál, el diseño falló.

              Ahora cada papel tiene su apartado, y se abre el que se está
              trabajando. `<details>` nativo y no un desplegable propio: se abre
              con teclado, lo lee un lector de pantalla y al imprimir el
              navegador ya sabe qué hacer con él. */}
          {tablero.length > 0 && (
            <div className="mb-6 space-y-3">

              {/* ── Declaraciones de ruta ────────────────────────────────── */}
              <details open={rutasPendientes.length > 0} className="rounded-lg border border-sand">
                <summary className="flex cursor-pointer flex-wrap items-baseline justify-between gap-2 px-4 py-3">
                  <span className="font-medium">Declaraciones de ruta</span>
                  <span className="text-sm text-taupe">
                    <strong className="text-tinta">{tablero.filter((f) => f.estado === "ok").length}</strong>
                    {" de "}{tablero.length} firmadas
                    {tablero.some((f) => f.estado === "se_nego") && (
                      <> · <strong className="text-rojo">{tablero.filter((f) => f.estado === "se_nego").length} se negaron</strong></>
                    )}
                  </span>
                </summary>

                {/* El botón del lote va DENTRO del apartado y no en la cabecera:
                    un `<summary>` con un botón adentro traga el clic —abre y
                    cierra el desplegable en vez de imprimir— y con teclado es
                    peor todavía. */}
                {rutasPendientes.length > 0 && (
                  <div className="flex flex-wrap items-center gap-3 border-t border-sand px-4 py-2">
                    <button onClick={() => imprimirLote("ruta", rutasPendientes)}
                      className="rounded-lg bg-tinta px-3 py-1.5 text-xs font-medium text-crema">
                      Imprimir las {rutasPendientes.length} que faltan
                    </button>
                    <span className="text-xs text-taupe">
                      Sale una hoja por persona, cada una en su página.
                    </span>
                  </div>
                )}

                <div className="overflow-x-auto border-t border-sand">
                  <table className="w-full text-sm">
                    <thead className="text-left text-xs text-taupe">
                      <tr className="border-b border-sand">
                        <th className="px-4 py-2 font-normal">Integrante</th>
                        <th className="px-4 py-2 font-normal">Sede</th>
                        <th className="px-4 py-2 font-normal">Su declaración</th>
                        <th className="px-4 py-2 font-normal"></th>
                      </tr>
                    </thead>
                    <tbody>
                      {tablero.map((f) => (
                        <tr key={f.persona_id} className="border-t border-sand">
                          <td className="px-4 py-2">{f.persona}</td>
                          <td className="px-4 py-2 text-xs text-taupe">{f.sede}</td>
                          <td className="px-4 py-2">
                            {f.estado === "sin_ruta" ? (
                              <span className="font-medium text-rojo">falta firmar</span>
                            ) : f.estado === "se_nego" ? (
                              <span className="font-medium text-rojo">
                                se negó a firmar · no cobra movilidad
                              </span>
                            ) : (
                              <>
                                <span className="text-tinta">firmada el {fechaLarga(f.ruta_firmada_el!)}</span>
                                {f.ruta_desfasada && (
                                  <span className="block text-xs text-rojo">
                                    declara S/ {Number(f.ruta_monto).toFixed(2)} y hoy se paga otra tarifa —
                                    conviene volver a firmarla
                                  </span>
                                )}
                              </>
                            )}
                          </td>
                          <td className="px-4 py-2">
                            <div className="flex flex-wrap items-center justify-end gap-3">
                              <button onClick={() => imprimirFila(f.persona_id, "ruta")}
                                className="text-xs font-medium underline">Imprimir</button>
                              <button onClick={() => abrirSubida("ruta", f.persona_id)}
                                className="rounded-lg border px-3 py-1 text-xs font-medium">
                                {f.estado === "ok" ? "Subir otra" : "Subir firmada"}
                              </button>
                              {f.estado === "sin_ruta" && (
                                // Discreto a propósito: registrar una negativa no debería
                                // ser tan fácil como registrar una firma.
                                <button onClick={() => abrirSubida("ruta", f.persona_id, true)}
                                  className="text-xs text-taupe underline">se negó</button>
                              )}
                            </div>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </details>

              {/* ── Cargos de cumpleaños ─────────────────────────────────────
                  Solo lista a quien tiene algo que hacer. Las veinte filas
                  completas con «cumple en octubre» repetido no informaban: el
                  90% del año la respuesta es «nada que hacer», y una lista que
                  casi siempre dice eso deja de leerse. */}
              <details open={bonoPendientes.length > 0} className="rounded-lg border border-sand">
                <summary className="flex cursor-pointer flex-wrap items-baseline justify-between gap-2 px-4 py-3">
                  <span className="font-medium">Cargos de cumpleaños</span>
                  <span className="text-sm text-taupe">
                    {bonoPendientes.length === 0
                      ? "nada pendiente"
                      : <><strong className="text-rojo">{bonoPendientes.length}</strong> por entregar o firmar</>}
                  </span>
                </summary>

                {bonoPendientes.length > 0 && (
                  <div className="flex flex-wrap items-center gap-3 border-t border-sand px-4 py-2">
                    <button onClick={() => imprimirLote("bono", bonoPendientes)}
                      className="rounded-lg bg-tinta px-3 py-1.5 text-xs font-medium text-crema">
                      Imprimir las {bonoPendientes.length} que faltan
                    </button>
                    <span className="text-xs text-taupe">
                      Solo de quien ya cumplió o cumple este mes.
                    </span>
                  </div>
                )}

                <div className="overflow-x-auto border-t border-sand">
                  <table className="w-full text-sm">
                    <thead className="text-left text-xs text-taupe">
                      <tr className="border-b border-sand">
                        <th className="px-4 py-2 font-normal">Integrante</th>
                        <th className="px-4 py-2 font-normal">Sede</th>
                        <th className="px-4 py-2 font-normal">Su cargo</th>
                        <th className="px-4 py-2 font-normal"></th>
                      </tr>
                    </thead>
                    <tbody>
                      {bonoRelevantes.map((f) => (
                        <tr key={f.persona_id} className="border-t border-sand">
                          <td className="px-4 py-2">{f.persona}</td>
                          <td className="px-4 py-2 text-xs text-taupe">{f.sede}</td>
                          <td className="px-4 py-2">
                            {f.bono_estado === "ok" ? (
                              <span className="text-tinta">firmado el {fechaLarga(f.bono_firmada_el!)}</span>
                            ) : f.bono_estado === "este_mes" ? (
                              <span className="font-medium text-tinta">cumple este mes — entregar y firmar</span>
                            ) : (
                              <span className="font-medium text-rojo">
                                cumplió en {MES_LARGO[(f.bono_mes ?? 1) - 1]} y no hay cargo
                              </span>
                            )}
                          </td>
                          <td className="px-4 py-2">
                            <div className="flex flex-wrap items-center justify-end gap-3">
                              <button onClick={() => imprimirFila(f.persona_id, "bono")}
                                className="text-xs font-medium underline">Imprimir</button>
                              <button onClick={() => abrirSubida("bono", f.persona_id)}
                                className="rounded-lg border px-3 py-1 text-xs font-medium">
                                {f.bono_estado === "ok" ? "Subir otro" : "Subir cargo"}
                              </button>
                            </div>
                          </td>
                        </tr>
                      ))}
                      {bonoRelevantes.length === 0 && (
                        <tr className="border-t border-sand">
                          <td colSpan={4} className="px-4 py-3 text-sm text-taupe">
                            Nadie tiene el cargo pendiente. Aquí van apareciendo en el mes de su
                            onomástico.
                          </td>
                        </tr>
                      )}
                    </tbody>
                  </table>
                </div>
              </details>

            </div>
          )}

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
              `fecha_fin_contrato` (0144) cubre a quien se va. Así que el sistema
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
                y quien termina contrato este mes. A quien termina más adelante SÍ se le
                entrega: hasta ese día cobra movilidad, así que hasta ese día necesita el
                papel. Revisa la lista igual: la decisión final es tuya.
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

          {/* QUÉ VA A SALIR EN LA LÍNEA DE FIRMA, antes de gastar papel.
              Sin este aviso el estampado falla en silencio: quien imprime ve la
              raya en blanco y no tiene forma de saber si es porque no cargó su
              firma, porque no es la persona que el documento nombra, o porque la
              pantalla está rota. Las tres se ven idénticas en el papel. */}
          {!cargando && (
            <p className="mb-4 text-xs text-taupe">
              {firmaEstampada
                ? `Tu firma escaneada saldrá impresa en la línea de ${firmanteCargo}.`
                : esFirmante
                  ? "No tienes una firma escaneada cargada: el documento sale con la línea en blanco para firmar a mano."
                  : `La línea de firma dice ${firmanteNombre}, y esa no es tu cuenta: el documento sale con la raya en blanco. La firma de una persona no se estampa bajo el nombre de otra.`}
            </p>
          )}

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

        {/* ── El documento ──
            Una hoja, o el lote entero. En modo lote cada hoja arranca en su
            propia página: sin eso, la declaración de la segunda persona
            empezaría a media hoja de la primera y ninguna de las dos serviría
            para firmar. */}
        {lote
          ? lote.map((quien) => (
              <div key={quien.id} className="hoja-suelta">{hoja(quien)}</div>
            ))
          : (!doc.necesitaPersona || persona) && hoja(persona)}
      </main>
    </>
  );
}

import type { ClienteCayla } from "@cayla-dynamic/database";
import { fechaLima, hoyLima } from "@cayla-dynamic/shared";
import { loQueNoSePudo } from "./admin/lo-que-no-se-pudo";

/**
 * La Bandeja de cada persona — «qué te respondieron».
 *
 * POR QUÉ EXISTE ESTE ARCHIVO Y NO VIVE DENTRO DE LA PANTALLA
 *
 * El número del botón «Bandeja» lo pinta /mio y la lista la pinta
 * /mio/bandeja: dos pantallas distintas contestando la misma pregunta. Si cada
 * una contara por su cuenta, el día que alguien cambie qué es «nuevo» solo
 * cambiaría una — y el botón diría 3 mientras la lista muestra 2. Es el mismo
 * defecto de fondo que este repositorio ya persiguió en el SQL (dos funciones
 * hermanas respondiendo distinto a «cuál es el vigente»); acá se corta antes
 * de que exista, con una sola función que devuelve las listas Y el contador.
 *
 * QUÉ JUNTA, Y QUÉ NO
 *
 * Tres cosas que la persona pidió y alguien tenía que contestarle:
 *   · el cambio de su ficha, con sus documentos  (solicitudes_cambio_perfil, 0399)
 *   · sus vacaciones                              (solicitudes_vacaciones, 0330)
 *   · que se revisara un día suyo                 (revisiones_pedidas, 0257)
 *
 * NO junta los acuses pendientes, los anuncios ni «Necesita que hagas algo»:
 * esos tres ya se pintan solos arriba en /mio, y son cosas que ella tiene que
 * hacer, no respuestas que recibió. Dos puertas para la misma pregunta es
 * exactamente lo que esta pantalla vino a evitar.
 *
 * Y NO junta el expediente disciplinario, aunque `exp_select_propia` lo
 * permita: esa policy no filtra por estado, así que incluiría BORRADORES —
 * avisarle de una sanción que nadie decidió entregar todavía es peor que no
 * avisarle nada. Mismo criterio que ya tomó /mio.
 *
 * CERO SQL: las tres fuentes ya dejan a cada persona leer lo suyo. Esta
 * función solo las fusiona.
 */

/**
 * Cuántos días una respuesta sigue contando como novedad.
 *
 * No hay «leído» guardado en ninguna parte a propósito (decisión de Felipe,
 * 2026-09-08): guardarlo exigiría una migración, y las dos alternativas sin
 * migración son peores. Un «leído» en el navegador se pierde al cambiar de
 * equipo y, en una computadora compartida, puede dejarle OCULTO a la segunda
 * persona un mensaje que nunca vio — esconder el rechazo de un cambio de
 * cuenta bancaria es peor que repetirlo.
 *
 * Lo que este número hace, y hay que saberlo al tocarlo: el contador no se
 * apaga al leer, caduca solo. Se prefiere un número que insiste de más a uno
 * que calla de menos.
 */
export const DIAS_NOVEDAD = 14;

export type OrigenBandeja = "perfil" | "vacaciones" | "revision";

/**
 * `atendido` es de las revisiones y no es lo mismo que `aprobado`: a un pedido
 * de revisar un día no se le dice que sí o que no, se le contesta qué se hizo.
 */
export type EstadoBandeja = "aprobado" | "rechazado" | "atendido" | "pendiente";

export interface MensajeBandeja {
  /** Estable entre recargas: sirve de `key` de React y de desempate del orden. */
  clave: string;
  origen: OrigenBandeja;
  estado: EstadoBandeja;
  /** La fecha de Lima del hecho: cuándo respondieron, o cuándo lo pediste si sigue abierto. */
  fecha: string;
  titulo: string;
  /** Lo que escribió Desarrollo Organizacional. `null` cuando no escribió nada — nunca un texto inventado. */
  respuesta: string | null;
  detalle: string | null;
  /** Solo las respuestas recientes. Lo pendiente NUNCA es novedad: lo pediste tú. */
  nuevo: boolean;
  /** A dónde lleva «Verlo →», o `null` si no hay a dónde ir de verdad. */
  ir: string | null;
}

/** Una solicitud de cambio de ficha. Tal como la devuelve `fn_mis_solicitudes_perfil()`. */
export interface FilaPerfil {
  id: string;
  etiqueta: string;
  estado: string;
  creada_at: string;
  resuelta_at: string | null;
  motivo: string | null;
}

/** Un pedido de vacaciones, de `solicitudes_vacaciones`. */
export interface FilaVacacion {
  id: string;
  fecha_inicio: string;
  fecha_fin: string;
  estado: string;
  pedida_at: string;
  resuelta_at: string | null;
  respuesta: string | null;
}

/** Un pedido de revisar un día, de `revisiones_pedidas`. */
export interface FilaRevision {
  id: string;
  fecha: string;
  pedida_at: string;
  atendida_at: string | null;
  respuesta: string | null;
}

export interface FuentesBandeja {
  perfil: FilaPerfil[];
  vacaciones: FilaVacacion[];
  revisiones: FilaRevision[];
}

export interface Bandeja {
  /** Lo que ya te contestaron, lo más reciente arriba. */
  respuestas: MensajeBandeja[];
  /** Lo que pediste y sigue sin respuesta, lo más viejo arriba: eso es lo que más espera. */
  esperando: MensajeBandeja[];
  /** Cuántas respuestas son novedad. El botón de /mio pinta ESTE número, no uno suyo. */
  nuevas: number;
}

const MESES = [
  "enero", "febrero", "marzo", "abril", "mayo", "junio",
  "julio", "agosto", "setiembre", "octubre", "noviembre", "diciembre",
];

/** `2026-10-05` → «5 de octubre». La forma en que lo diría ella, no la del ISO. */
export function diaYMes(iso: string): string {
  const [, m, d] = iso.split("-");
  return `${Number(d)} de ${MESES[Number(m) - 1]}`;
}

/** «el 5 de octubre», «del 5 al 9 de octubre», «del 28 de setiembre al 3 de octubre». */
function rangoDeFechas(ini: string, fin: string): string {
  if (ini === fin) return `el ${diaYMes(ini)}`;
  const [, mi] = ini.split("-");
  const [, mf] = fin.split("-");
  // Mismo mes: no se repite el nombre del mes dos veces en la misma frase.
  if (mi === mf) return `del ${Number(ini.split("-")[2])} al ${diaYMes(fin)}`;
  return `del ${diaYMes(ini)} al ${diaYMes(fin)}`;
}

/**
 * Días entre dos fechas de Lima. Por `Date.UTC` sobre las partes, nunca
 * restando dos `new Date(iso)`: eso mete el huso del navegador en una cuenta
 * que ya está resuelta en fecha de Lima, y se corre un día.
 */
function diasEntre(desde: string, hasta: string): number {
  const [ay, am, ad] = desde.split("-").map(Number);
  const [by, bm, bd] = hasta.split("-").map(Number);
  return Math.round((Date.UTC(by, bm - 1, bd) - Date.UTC(ay, am - 1, ad)) / 86_400_000);
}

/** «hoy», «ayer», «hace 6 días» — cómo se cuenta el tiempo en una frase. */
function haceCuanto(fecha: string, hoy: string): string {
  const dias = diasEntre(fecha, hoy);
  if (dias <= 0) return "hoy";
  if (dias === 1) return "ayer";
  return `hace ${dias} días`;
}

/**
 * El instante que ordena el hilo, en milisegundos.
 *
 * `resuelta_at` es obligatorio en cuanto el estado deja de ser «pendiente»
 * (lo exigen `chk_solicitud_perfil_resuelta_completa` y su gemela de
 * vacaciones), así que la reserva a la fecha del pedido no debería usarse
 * nunca. Está igual porque el desenlace importa: sin ella, una fila con el
 * dato faltante DESAPARECERÍA del hilo, y perder un rechazo es peor que
 * mostrarlo un poco fuera de sitio.
 */
function instanteDe(resuelta: string | null, pedida: string): number {
  return Date.parse(resuelta ?? pedida);
}

export function armarBandeja(fuentes: FuentesBandeja, hoy: string = hoyLima()): Bandeja {
  const respuestas: { m: MensajeBandeja; instante: number }[] = [];
  const esperando: { m: MensajeBandeja; instante: number }[] = [];

  const esNueva = (fecha: string) => diasEntre(fecha, hoy) <= DIAS_NOVEDAD;

  for (const f of fuentes.perfil) {
    const clave = `perfil:${f.id}`;
    if (f.estado === "pendiente") {
      const fecha = fechaLima(f.creada_at);
      esperando.push({
        instante: Date.parse(f.creada_at),
        m: {
          clave, origen: "perfil", estado: "pendiente", fecha,
          titulo: `Pediste cambiar «${f.etiqueta}»`,
          respuesta: null,
          detalle: `Lo pediste ${haceCuanto(fecha, hoy)}. Desarrollo Organizacional todavía no responde.`,
          nuevo: false,
          ir: "/mio/editar",
        },
      });
      continue;
    }
    // «reemplazada» se salta: es lo que le pasa a una propuesta cuando mandas
    // otra sobre el mismo campo. Nadie te contestó nada, así que no es un
    // mensaje — anunciarlo sería ruido que enseña a saltarse la bandeja.
    if (f.estado !== "aprobado" && f.estado !== "rechazado") continue;

    const fecha = fechaLima(f.resuelta_at ?? f.creada_at);
    respuestas.push({
      instante: instanteDe(f.resuelta_at, f.creada_at),
      m: {
        clave, origen: "perfil", estado: f.estado === "aprobado" ? "aprobado" : "rechazado", fecha,
        titulo: `Tu cambio de «${f.etiqueta}» fue ${f.estado === "aprobado" ? "aprobado" : "rechazado"}`,
        // El motivo es OBLIGATORIO en un rechazo (chk_solicitud_perfil_rechazo_con_motivo),
        // y es lo único que le dice qué corregir para volver a intentarlo.
        respuesta: f.motivo?.trim() || null,
        detalle: f.estado === "aprobado"
          ? "Ya está aplicado en tu ficha."
          : "Puedes volver a pedirlo con el documento que falta.",
        nuevo: esNueva(fecha),
        ir: "/mio/editar",
      },
    });
  }

  for (const f of fuentes.vacaciones) {
    const clave = `vacaciones:${f.id}`;
    const rango = rangoDeFechas(f.fecha_inicio, f.fecha_fin);
    if (f.estado === "pendiente") {
      const fecha = fechaLima(f.pedida_at);
      esperando.push({
        instante: Date.parse(f.pedida_at),
        m: {
          clave, origen: "vacaciones", estado: "pendiente", fecha,
          titulo: `Pediste vacaciones ${rango}`,
          respuesta: null,
          detalle: `Lo pediste ${haceCuanto(fecha, hoy)}. Desarrollo Organizacional todavía no responde.`,
          nuevo: false,
          ir: null,
        },
      });
      continue;
    }
    // «cancelada» se salta: la cancelaste tú. No es una respuesta.
    if (f.estado !== "aprobada" && f.estado !== "rechazada") continue;

    const fecha = fechaLima(f.resuelta_at ?? f.pedida_at);
    respuestas.push({
      instante: instanteDe(f.resuelta_at, f.pedida_at),
      m: {
        clave, origen: "vacaciones", estado: f.estado === "aprobada" ? "aprobado" : "rechazado", fecha,
        titulo: `Tus vacaciones ${rango} fueron ${f.estado === "aprobada" ? "aprobadas" : "rechazadas"}`,
        respuesta: f.respuesta?.trim() || null,
        detalle: f.estado === "aprobada" ? "Ya están cargadas en tu calendario." : null,
        nuevo: esNueva(fecha),
        ir: null,
      },
    });
  }

  for (const f of fuentes.revisiones) {
    const clave = `revision:${f.id}`;
    if (!f.atendida_at) {
      const fecha = fechaLima(f.pedida_at);
      esperando.push({
        instante: Date.parse(f.pedida_at),
        m: {
          clave, origen: "revision", estado: "pendiente", fecha,
          titulo: `Pediste que se revise tu ${diaYMes(f.fecha)}`,
          respuesta: null,
          detalle: `Lo pediste ${haceCuanto(fecha, hoy)}. Todavía no lo revisan.`,
          nuevo: false,
          ir: null,
        },
      });
      continue;
    }

    const fecha = fechaLima(f.atendida_at);
    respuestas.push({
      instante: Date.parse(f.atendida_at),
      m: {
        clave, origen: "revision", estado: "atendido", fecha,
        titulo: `Revisamos tu ${diaYMes(f.fecha)}`,
        // Puede venir vacía: la columna es opcional, solo `atendida_por` es
        // obligatoria. Se dice que se revisó igual — el silencio también es
        // una respuesta, y ocultarlo dejaría el pedido colgado para siempre.
        respuesta: f.respuesta?.trim() || null,
        detalle: f.respuesta?.trim() ? null : "Se revisó, sin nota escrita.",
        nuevo: esNueva(fecha),
        ir: null,
      },
    });
  }

  // EL DESEMPATE. `clave` es un ancla, no un criterio: son uuid y no significan
  // nada. Va DESPUÉS del único criterio real (cuándo te respondieron), así que
  // solo puede disparar en un empate exacto — y ese empate SÍ ocurre acá:
  // Desarrollo Organizacional aprueba varias de una sentada y las filas de esa
  // transacción comparten `resuelta_at` al microsegundo. Sin ancla, cuál sale
  // primero lo decidiría el orden en que volvieron las tres consultas.
  respuestas.sort((a, b) => b.instante - a.instante || (a.m.clave < b.m.clave ? 1 : a.m.clave > b.m.clave ? -1 : 0));
  // Lo que espera se ordena al revés: arriba lo que lleva más tiempo sin
  // respuesta, que es lo que de verdad hay que reclamar.
  esperando.sort((a, b) => a.instante - b.instante || (a.m.clave < b.m.clave ? -1 : a.m.clave > b.m.clave ? 1 : 0));

  const lista = respuestas.map((r) => r.m);
  return {
    respuestas: lista,
    esperando: esperando.map((r) => r.m),
    // El contador se deriva de la misma lista que se pinta. No puede discrepar.
    nuevas: lista.filter((m) => m.nuevo).length,
  };
}

/**
 * Cuántas filas se traen de cada fuente. Sin filtro de fechas y con un tope
 * fijo, igual que las otras listas de /mio: un filtro por fecha escondería
 * una respuesta vieja que nunca se leyó, y el tope se aplica sobre el orden
 * descendente, así que lo que se descarta es siempre lo más antiguo.
 */
const LIMITE = 100;

/**
 * Las tres consultas de la Bandeja, en un solo sitio.
 *
 * Vive acá y no dentro de cada pantalla por la misma razón que `armarBandeja`:
 * el botón de /mio y la lista de /mio/bandeja tienen que leer LO MISMO, no solo
 * contarlo igual. Si cada una escribiera sus consultas, bastaría con que una
 * agregara un filtro para que el número dejara de corresponder a la lista.
 *
 * ⚠ EL FILTRO POR `persona_id` ES EXPLÍCITO EN LAS TRES, Y NO ES REDUNDANTE.
 * La RLS de estas tablas devuelve «lo tuyo» a una integrante, pero /mio también
 * la abren encargadas y DO, y para ellas otras policies devuelven la sede
 * entera o a todo el mundo. Esta pantalla ya cometió ese error una vez
 * (2026-08-12): le mostró a una encargada el nombre y las horas de otra
 * persona, en la pantalla que se llama «lo mío». La RLS es la red de abajo,
 * nunca el mecanismo.
 *
 * Y acá no es una precaución teórica: MEDIDO el 2026-09-08 contra la base,
 * simulando la sesión de una encargada de LIM, `revisiones_pedidas` tiene una
 * TERCERA policy —`revisiones_select_supervisor`— que le abre las revisiones de
 * toda su sede: 3 personas, de las cuales ella es 1. Sin este `.eq()`, su
 * propia Bandeja le diría «Pediste que se revise tu 3 de setiembre» sobre el
 * día de otra persona. Las otras dos tablas hoy no tienen esa policy; que la
 * respuesta dependa de quién pregunta es exactamente lo que el filtro corta.
 */
export async function traerBandeja(
  supabase: ClienteCayla,
  personaId: string,
  hoy: string = hoyLima(),
): Promise<{ bandeja: Bandeja; noSePudo: string[] }> {
  const [perfil, catalogo, vacaciones, revisiones] = await Promise.all([
    supabase.from("solicitudes_cambio_perfil")
      .select("id, campo, estado, creada_at, resuelta_at, motivo")
      .eq("persona_id", personaId)
      .order("creada_at", { ascending: false })
      .limit(LIMITE),
    supabase.from("catalogo_campos_perfil").select("campo, etiqueta"),
    supabase.from("solicitudes_vacaciones")
      .select("id, fecha_inicio, fecha_fin, estado, pedida_at, resuelta_at, respuesta")
      .eq("persona_id", personaId)
      .order("pedida_at", { ascending: false })
      .limit(LIMITE),
    supabase.from("revisiones_pedidas")
      .select("id, fecha, pedida_at, atendida_at, respuesta")
      .eq("persona_id", personaId)
      .order("pedida_at", { ascending: false })
      .limit(LIMITE),
  ]);

  const etiquetas = new Map(
    ((catalogo.data ?? []) as { campo: string; etiqueta: string }[]).map((c) => [c.campo, c.etiqueta] as const),
  );

  const bandeja = armarBandeja({
    // Si el catálogo no vino, se cae al nombre técnico del campo. Feo, pero el
    // mensaje sigue entero y sigue diciendo la verdad — por eso esta consulta
    // NO entra en `noSePudo`: un aviso rojo por una etiqueta menos enseñaría a
    // ignorar el aviso el día que falte algo de verdad.
    perfil: ((perfil.data ?? []) as { campo: string }[] as (FilaPerfil & { campo: string })[])
      .map((f) => ({ ...f, etiqueta: etiquetas.get(f.campo) ?? f.campo })),
    vacaciones: (vacaciones.data ?? []) as unknown as FilaVacacion[],
    revisiones: (revisiones.data ?? []) as unknown as FilaRevision[],
  }, hoy);

  return {
    bandeja,
    // Una consulta que falló y se pinta como lista vacía dice «no tienes
    // mensajes», que es una afirmación y no un hueco. Ver lib/admin/lo-que-no-se-pudo.ts.
    noSePudo: loQueNoSePudo([
      { error: perfil.error, que: "tus pedidos de cambio de ficha" },
      { error: vacaciones.error, que: "tus pedidos de vacaciones" },
      { error: revisiones.error, que: "tus pedidos de revisar un día" },
    ]),
  };
}

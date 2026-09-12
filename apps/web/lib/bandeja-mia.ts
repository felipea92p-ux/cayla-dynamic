import type { ClienteCayla } from "@cayla-dynamic/database";
import { fechaLima, hoyLima } from "@cayla-dynamic/shared";
import { loQueNoSePudo } from "./admin/lo-que-no-se-pudo";
import { traerAcusesPendientes, type AcusePendiente } from "./acuses-pendientes";
import { ordenarContratoVigente } from "./mi-contrato";

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
 * DOS cosas distintas, y la diferencia entre ellas es la que ordena todo este
 * archivo:
 *
 *   PENDIENTES — lo que depende de ella y NO CADUCA. Un contrato sin firmar
 *   sigue contando el día 90 igual que el día 1; deja de contar cuando lo
 *   firma, no cuando lo mira.
 *     · su contrato, mientras no confirme su firma   (contratos_generados, 0402)
 *     · un memo disciplinario por firmar             (fn_mis_memos, 0404)
 *     · la política salarial y el RIT sin acusar     (Ley 30709)
 *     · días con el marcaje incompleto del periodo que se le va a pagar
 *
 *   RESPUESTAS — lo que pidió y alguien le contestó. Eso sí caduca a los
 *   DIAS_NOVEDAD, porque no hay nada que hacer con ello:
 *     · el cambio de su ficha, con sus documentos  (solicitudes_cambio_perfil, 0399)
 *     · sus vacaciones                              (solicitudes_vacaciones, 0330)
 *     · que se revisara un día suyo                 (revisiones_pedidas, 0257)
 *
 * POR QUÉ LOS PENDIENTES NO CADUCAN, Y POR QUÉ ESO RESUELVE «LO LEÍDO»
 *
 * Hasta el 2026-09-08 no se guardaba en ninguna parte si una persona ya había
 * visto su bandeja, y se decidió no guardarlo: un «leído» en el navegador se
 * pierde al cambiar de equipo y, en una Mac compartida, puede dejarle OCULTO a
 * la segunda persona un mensaje que nunca vio.
 *
 * La decisión sigue en pie, y esta versión la aprovecha en vez de pelearse con
 * ella: para lo que hay que FIRMAR, «leído» es «firmado», y eso YA está
 * guardado —`firma_persona_confirmada_at`, `mi_acuse_at`— desde antes. No hace
 * falta una tabla nueva ni una migración: el sistema no necesita saber si lo
 * miraste, necesita saber si lo hiciste.
 *
 * QUÉ SIGUE SIN JUNTAR
 *
 * Los anuncios, que no piden nada de vuelta. Y el expediente disciplinario
 * crudo, aunque `exp_select_propia` lo permita: esa policy no filtra por
 * estado, así que incluiría BORRADORES —avisarle de una sanción que nadie
 * decidió entregar todavía es peor que no avisarle nada—. Por eso los memos
 * entran por `fn_mis_memos()`, que ya filtra `estado = 'entregado'`.
 *
 * LO QUE SIGUE PINTÁNDOSE ARRIBA EN /mio, Y ES A PROPÓSITO
 *
 * La banda de acuses y el recuadro ámbar «Necesita que hagas algo» se quedan
 * donde están (decisión de Felipe, 2026-09-08). La Bandeja no los reemplaza:
 * los CUENTA y los enlaza, para que el aviso viaje con la persona a cualquier
 * pantalla. No duplica ningún formulario — es el mismo criterio con el que se
 * construyó la Bandeja del panel.
 *
 * CERO SQL: todas las fuentes ya dejan a cada persona leer lo suyo. Esta
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
 * Lo que este número hace, y hay que saberlo al tocarlo: una RESPUESTA no se
 * apaga al leerla, caduca sola. Se prefiere un número que insiste de más a uno
 * que calla de menos.
 *
 * ⚠ NO se aplica a los PENDIENTES. Un contrato sin firmar no caduca a los 14
 * días: caduca cuando se firma. Caducar ahí sería apagar el aviso justo cuando
 * lleva más tiempo sin resolverse.
 */
export const DIAS_NOVEDAD = 14;

export type OrigenBandeja =
  // Lo que pediste y te contestaron.
  | "perfil" | "vacaciones" | "revision"
  // Lo que depende de ti. No caduca.
  | "contrato" | "memo" | "acuse" | "marcaje" | "ruta";

/**
 * `atendido` es de las revisiones y no es lo mismo que `aprobado`: a un pedido
 * de revisar un día no se le dice que sí o que no, se le contesta qué se hizo.
 */
export type EstadoBandeja =
  | "aprobado" | "rechazado" | "atendido" | "pendiente"
  /** Depende de una firma tuya: el contrato, un memo, una constancia. */
  | "por_firmar"
  /** Depende de que pidas que se corrija: un día con el marcaje incompleto. */
  | "por_arreglar";

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
  /**
   * ¿Cuenta en el número del botón?
   *
   * Para una RESPUESTA: solo si es reciente (ver DIAS_NOVEDAD).
   * Para un PENDIENTE: siempre, hasta que se resuelva.
   * Para lo que estás ESPERANDO: nunca — lo pediste tú, ya sabes que existe.
   */
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

/** El contrato vigente de la persona, de `contratos_generados` (RLS 0272). */
export interface FilaContrato {
  id: string;
  tipo: string;
  fecha_inicio: string;
  fecha_fin: string | null;
  generado_at: string;
  /** La confirmación DIGITAL de su firma (0402). Null = todavía le falta. */
  firma_persona_confirmada_at: string | null;
}

/** Un memo disciplinario ya entregado, de `fn_mis_memos()` (0404). */
export interface FilaMemo {
  id: string;
  nivel: string;
  entregado_at: string | null;
  firma_sancionado_confirmada_at: string | null;
  sancionado_rechazo_firma_at: string | null;
}

/** Un día del periodo abierto cuyo marcaje quedó incompleto. */
export interface FilaMarcaje {
  fecha: string;
  /** `estado_jornada` de la base. */
  estado: string;
  horas_trabajadas: number | null;
}

/** El periodo de pago abierto hoy, de `periodos_planilla`. */
export interface PeriodoAbierto {
  fecha_ini: string;
  fecha_fin: string;
}

/**
 * Su propia declaración de ruta, de `fn_documentos_tablero(p_solo_mi_fila =>
 * true)` (0423) — la MISMA función que usa el tablero de Documentación, pero
 * pidiendo solo su fila en vez de la de todo el equipo. `null` cuando no le
 * corresponde: no está en planilla, es quien firma por CAYLA, o su contrato
 * ya termina este mes o antes (mismas exclusiones que el tablero admin).
 */
export interface FilaMovilidad {
  estado: "sin_ruta" | "se_nego" | "ok";
  ruta_firmada_el: string | null;
  ruta_monto: number | null;
  ruta_desfasada: boolean;
}

export interface FuentesBandeja {
  perfil: FilaPerfil[];
  vacaciones: FilaVacacion[];
  revisiones: FilaRevision[];
  /** El contrato vigente, o null si no tiene ninguno. */
  contrato: FilaContrato | null;
  memos: FilaMemo[];
  /** Ya resueltos por lib/acuses-pendientes.ts: acá solo se pintan. */
  acuses: AcusePendiente[];
  /** Días del periodo abierto, sin filtrar: el criterio de «incompleto» vive acá. */
  marcajes: FilaMarcaje[];
  /** Sin periodo abierto no hay nada que arreglar a tiempo: los marcajes se ignoran. */
  periodo: PeriodoAbierto | null;
  /** Su declaración de ruta. Ver `FilaMovilidad`. */
  movilidad: FilaMovilidad | null;
}

export interface Bandeja {
  /** Lo que depende de ti y no caduca, lo más urgente arriba. */
  pendientes: MensajeBandeja[];
  /** Lo que ya te contestaron, lo más reciente arriba. */
  respuestas: MensajeBandeja[];
  /** Lo que pediste y sigue sin respuesta, lo más viejo arriba: eso es lo que más espera. */
  esperando: MensajeBandeja[];
  /**
   * El número del botón «Bandeja»: los pendientes enteros más las respuestas
   * recientes. Sale de las MISMAS listas que se pintan, así que no puede
   * discrepar de ellas.
   */
  avisos: number;
}

/**
 * ¿Este memo le falta firmar?
 *
 * Se exporta porque /mio pinta el mismo aviso en su recuadro ámbar. Escrito dos
 * veces, un día uno de los dos dejaría de contar los verbales.
 *
 * Los tres niveles son los que llevan firma del sancionado; una «anotación» no.
 * Y `sancionado_rechazo_firma_at` cuenta como cerrado: negarse a firmar es una
 * respuesta con valor legal (queda el acta), no un pendiente eterno.
 */
export function esMemoPorFirmar(m: FilaMemo): boolean {
  return ["verbal", "amonestacion", "suspension"].includes(m.nivel)
    && !m.firma_sancionado_confirmada_at
    && !m.sancionado_rechazo_firma_at;
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

/**
 * En qué orden aprietan los pendientes. No es una preferencia de forma: es lo
 * que decide qué ve primero alguien que abre la Bandeja con cuatro cosas.
 *
 *   memo     · corre el plazo para presentar su descargo. Es el único con un
 *              reloj legal en contra de ELLA.
 *   contrato · es el papel que sostiene la relación. Sin su firma, lo que se
 *              pactó no está probado por ninguna de las dos partes.
 *   ruta     · sostiene que su movilidad no pague impuestos ni descuentos
 *              (0423). Menos urgente que el contrato —no define la relación
 *              entera— pero es plata suya de por medio, así que va antes que
 *              las obligaciones que son de la empresa.
 *   acuse    · obligación legal de la EMPRESA (Ley 30709, RIT). Importa, pero
 *              quien queda expuesta si falta no es ella.
 *   marcaje  · se arregla mientras el periodo siga abierto, y hasta entonces
 *              no hay nada perdido.
 */
const PESO_PENDIENTE: Record<string, number> = { memo: 0, contrato: 1, ruta: 2, acuse: 3, marcaje: 4 };

export function armarBandeja(fuentes: FuentesBandeja, hoy: string = hoyLima()): Bandeja {
  const respuestas: { m: MensajeBandeja; instante: number }[] = [];
  const esperando: { m: MensajeBandeja; instante: number }[] = [];
  const pendientes: { m: MensajeBandeja; instante: number }[] = [];

  const esNueva = (fecha: string) => diasEntre(fecha, hoy) <= DIAS_NOVEDAD;

  // ── LO QUE DEPENDE DE TI ────────────────────────────────────────────────
  // Todos entran con `nuevo: true` y ninguno mira DIAS_NOVEDAD: no caducan.

  // El contrato. UNO, el vigente — cuál es lo decide lib/mi-contrato.ts, el
  // mismo criterio que abre /mio/contrato, para que la Bandeja no señale un
  // papel distinto del que la pantalla enseña.
  if (fuentes.contrato && !fuentes.contrato.firma_persona_confirmada_at) {
    const c = fuentes.contrato;
    const fecha = fechaLima(c.generado_at);
    pendientes.push({
      instante: Date.parse(c.generado_at),
      m: {
        clave: `contrato:${c.id}`, origen: "contrato", estado: "por_firmar", fecha,
        titulo: "Tu contrato está esperando tu firma",
        respuesta: null,
        detalle: c.fecha_fin
          ? `Del ${diaYMes(c.fecha_inicio)} al ${diaYMes(c.fecha_fin)}. Léelo entero y confirma tu firma; hasta que lo hagas seguirá acá.`
          : `Desde el ${diaYMes(c.fecha_inicio)}, sin fecha de término. Léelo entero y confirma tu firma; hasta que lo hagas seguirá acá.`,
        nuevo: true,
        ir: "/mio/contrato",
      },
    });
  }

  // La declaración de ruta y gasto de transporte (0423). Igual que el
  // contrato: mientras no la firme, sigue contando — no caduca. Y si ya la
  // firmó pero con una tarifa que quedó vieja, se le avisa igual: es la
  // misma alerta que ya pinta el tablero de Documentación para DO, solo que
  // acá le llega a ELLA, que es quien puede arreglarlo firmando de nuevo.
  if (fuentes.movilidad && (fuentes.movilidad.estado === "sin_ruta" || fuentes.movilidad.ruta_desfasada)) {
    const mov = fuentes.movilidad;
    const desfasada = mov.estado !== "sin_ruta" && mov.ruta_desfasada;
    pendientes.push({
      instante: desfasada && mov.ruta_firmada_el ? Date.parse(`${mov.ruta_firmada_el}T00:00:00Z`) : 0,
      m: {
        clave: "ruta:declaracion", origen: "ruta", estado: "por_firmar",
        fecha: desfasada && mov.ruta_firmada_el ? mov.ruta_firmada_el : hoy,
        titulo: desfasada
          ? "Tu declaración de ruta quedó desactualizada"
          : "Falta tu declaración de ruta y gasto de transporte",
        respuesta: null,
        detalle: desfasada
          ? `La firmaste declarando S/ ${Number(mov.ruta_monto).toFixed(2)} y hoy se paga otra tarifa. Vuelve a firmarla con el monto vigente.`
          : "Sostiene que tu movilidad no pague impuestos ni descuentos. Fírmala desde el sistema — no hace falta imprimir ni escanear nada.",
        nuevo: true,
        ir: "/mio/movilidad",
      },
    });
  }

  // Los memos. GENÉRICO a propósito: ni el nivel ni el motivo van acá — esta
  // tarjeta puede verla de reojo cualquiera que pase cerca de la pantalla, y el
  // detalle recién se ve al entrar al documento. Mismo criterio que /mio.
  for (const m of fuentes.memos.filter(esMemoPorFirmar)) {
    const fecha = m.entregado_at ? fechaLima(m.entregado_at) : hoy;
    pendientes.push({
      instante: m.entregado_at ? Date.parse(m.entregado_at) : Date.parse(`${hoy}T00:00:00Z`),
      m: {
        clave: `memo:${m.id}`, origen: "memo", estado: "por_firmar", fecha,
        titulo: "Tienes un documento por revisar y firmar",
        respuesta: null,
        detalle: "Está en Info, en la pestaña «Historial». Firmarlo no es aceptar lo que dice: puedes firmarlo y presentar tu descargo, o dejar constancia de que te niegas a firmar.",
        nuevo: true,
        ir: "/mio",
      },
    });
  }

  // Las constancias de ley. Ya vienen resueltas: acá no se decide qué exige
  // acuse (eso vive en lib/acuses-pendientes.ts, que es lo que también lee la
  // banda de arriba de /mio).
  for (const a of fuentes.acuses) {
    pendientes.push({
      // Sin fecha propia: lo que importa no es cuándo se publicó, sino que te
      // falta. Se ordenan entre sí por su clave, que es estable.
      instante: 0,
      m: {
        clave: a.clave, origen: "acuse", estado: "por_firmar", fecha: hoy,
        titulo: `Te falta dejar constancia: ${a.titulo}`,
        respuesta: null,
        detalle: a.detalle
          ? `${a.detalle} No firmas ningún compromiso: dejas constancia de haber sido informada.`
          : "No firmas ningún compromiso: dejas constancia de haber sido informada.",
        nuevo: true,
        ir: a.href,
      },
    });
  }

  // Los días con el marcaje incompleto, EN UN SOLO MENSAJE y contando 1.
  //
  // Uno por día haría que un mes malo se comiera el número entero y tapara el
  // contrato sin firmar, que aprieta mucho más. Es una sola tarea —«pide que
  // revisen tus días»— y así la presenta también el recuadro ámbar de /mio.
  //
  // Y SOLO DEL PERIODO QUE SE VA A PAGAR. Fuera de él ya no hay nada que
  // arreglar a tiempo, así que avisar sería pedirle algo que no puede hacer.
  // Por eso este número puede no coincidir con el del recuadro de /mio, que
  // habla del rango de fechas que la persona está mirando: son dos preguntas
  // distintas, y el texto de acá dice cuál contesta.
  if (fuentes.periodo) {
    const { fecha_ini, fecha_fin } = fuentes.periodo;
    const rotos = fuentes.marcajes
      .filter((j) => j.fecha >= fecha_ini && j.fecha <= fecha_fin)
      // El mismo criterio que `estadoDelDia` (lib/admin/jornada-esperada.ts):
      // sin horas o cerrada por el sistema es un día que hay que revisar.
      .filter((j) => j.estado === "auto_cerrada_pendiente" || j.horas_trabajadas === null)
      // Su jornada de HOY todavía abierta no es un día roto: está trabajando.
      .filter((j) => !(j.fecha === hoy && (j.estado === "abierta" || j.estado === "en_pausa")))
      .map((j) => j.fecha)
      .sort();

    if (rotos.length > 0) {
      pendientes.push({
        instante: Date.parse(`${rotos[0]}T00:00:00Z`),
        m: {
          clave: "marcaje:periodo", origen: "marcaje", estado: "por_arreglar", fecha: rotos[0],
          titulo: `${rotos.length} día${rotos.length === 1 ? "" : "s"} con el marcaje incompleto`,
          respuesta: null,
          detalle: `${rotos.map(diaYMes).join(", ")}. Falta la salida o la puso el sistema, así que las horas de ${rotos.length === 1 ? "ese día" : "esos días"} no son las que trabajaste. Se arregla mientras el periodo del ${diaYMes(fecha_ini)} al ${diaYMes(fecha_fin)} siga abierto; después ya no.`,
          nuevo: true,
          ir: "/mio",
        },
      });
    }
  }

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

  // Los pendientes se ordenan por lo que aprietan (ver PESO_PENDIENTE) y, a
  // igual peso, por antigüedad: lo que lleva más tiempo sin firmarse, arriba.
  // `clave` cierra como ancla, igual que en las otras dos listas.
  pendientes.sort((a, b) =>
    (PESO_PENDIENTE[a.m.origen] ?? 9) - (PESO_PENDIENTE[b.m.origen] ?? 9)
    || a.instante - b.instante
    || (a.m.clave < b.m.clave ? -1 : a.m.clave > b.m.clave ? 1 : 0));

  const lista = respuestas.map((r) => r.m);
  const porHacer = pendientes.map((r) => r.m);
  return {
    pendientes: porHacer,
    respuestas: lista,
    esperando: esperando.map((r) => r.m),
    // El contador se deriva de las MISMAS listas que se pintan. No puede
    // discrepar de ellas: los pendientes enteros, más las respuestas recientes.
    avisos: porHacer.length + lista.filter((m) => m.nuevo).length,
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
  const [perfil, catalogo, vacaciones, revisiones, contrato, memos, acuses, periodo, movilidad] = await Promise.all([
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
    // EL CONTRATO VIGENTE. Uno solo, y el mismo que abre /mio/contrato: el
    // orden vive en lib/mi-contrato.ts. Sin `documento_html` a propósito — acá
    // solo hace falta saber SI le falta firmar, y ese campo pesa 40 KB.
    ordenarContratoVigente(
      supabase.from("contratos_generados")
        .select("id, tipo, fecha_inicio, fecha_fin, generado_at, firma_persona_confirmada_at")
        .eq("persona_id", personaId)
        .is("anulado_at", null),
    ).limit(1).maybeSingle(),
    // `fn_mis_memos()` (0404) ya filtra `estado = 'entregado'`: nunca un
    // borrador. Ver el encabezado de este archivo.
    supabase.rpc("fn_mis_memos"),
    traerAcusesPendientes(supabase),
    // El periodo que se le va a pagar. LEÍDO, nunca calculado: va del 29 al 28
    // y eso vive en la tabla (CLAUDE.md).
    supabase.from("periodos_planilla").select("fecha_ini, fecha_fin")
      .lte("fecha_ini", hoy).gte("fecha_fin", hoy).maybeSingle(),
    // Su propia declaración de ruta (0423). `p_solo_mi_fila => true` es lo que
    // hace seguro reusar la función del tablero admin: sin ese argumento,
    // alguien con rol admin o líder que abra su PROPIA bandeja vería la fila
    // de cualquier compañera (la primera que devuelva el orden), no la suya.
    supabase.rpc("fn_documentos_tablero", { p_solo_mi_fila: true }),
  ]);

  // Las jornadas del periodo, solo si hay periodo abierto. Va en su propia
  // ronda porque necesita las fechas de la consulta anterior; son ~30 filas.
  const per = (periodo.data ?? null) as PeriodoAbierto | null;
  const marcajes = per
    ? await supabase.from("jornadas")
        .select("fecha, estado, horas_trabajadas")
        .eq("persona_id", personaId)
        .gte("fecha", per.fecha_ini).lte("fecha", per.fecha_fin)
    : null;

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
    contrato: (contrato.data ?? null) as unknown as FilaContrato | null,
    memos: ((memos.data ?? []) as unknown as FilaMemo[]),
    acuses,
    marcajes: ((marcajes?.data ?? []) as unknown as FilaMarcaje[]),
    periodo: per,
    movilidad: ((movilidad.data ?? []) as FilaMovilidad[])[0] ?? null,
  }, hoy);

  return {
    bandeja,
    // Una consulta que falló y se pinta como lista vacía dice «no tienes
    // mensajes», que es una afirmación y no un hueco. Ver lib/admin/lo-que-no-se-pudo.ts.
    // Una consulta que falló y se pinta como lista vacía dice «no tienes nada
    // pendiente», y acá eso puede ser el contrato sin firmar.
    //
    // Los ACUSES no entran en esta lista, y es la misma excepción que ya hacía
    // el catálogo de etiquetas: `traerAcusesPendientes` devuelve [] si algo
    // falla, y la banda de arriba de /mio sigue avisando por su cuenta — un
    // aviso rojo de más enseñaría a ignorarlo el día que falte algo de verdad.
    noSePudo: loQueNoSePudo([
      { error: perfil.error, que: "tus pedidos de cambio de ficha" },
      { error: vacaciones.error, que: "tus pedidos de vacaciones" },
      { error: revisiones.error, que: "tus pedidos de revisar un día" },
      { error: contrato.error, que: "tu contrato" },
      { error: memos.error, que: "tus documentos por firmar" },
      { error: marcajes?.error ?? null, que: "tus días del periodo" },
      { error: movilidad.error, que: "tu declaración de ruta" },
    ]),
  };
}

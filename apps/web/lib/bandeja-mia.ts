import type { ClienteCayla } from "@cayla-dynamic/database";
import {
  MOTIVO_RECHAZO_LABELS, constanciaPedidaAntesDelPago, constanciaPideAlgoALaIntegrante, fechaLima, hoyLima,
  type EstadoConstancia, type MotivoRechazo,
} from "@cayla-dynamic/shared";
import { loQueNoSePudo } from "./admin/lo-que-no-se-pudo";
import { traerAcusesPendientes, type AcusePendiente } from "./acuses-pendientes";
import { ordenarContratoVigente } from "./mi-contrato";
import { puedePedirBono, traerMiBono, type MiBono } from "./mi-bono";
import { formatSoles } from "./rangos";
import { esBoletaNueva } from "./boletas";
import { nombreDelPeriodo, traerMisBoletas, type FilaMiBoleta } from "./mis-boletas";
import { fechaEnPalabras, traerMisReportes, tituloDeReporte, type FilaMiReporte } from "./reportes";

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
 *     · un memo que le enviaron a su Info y aún no recibió  (fn_mis_memos_por_recibir, 0486)
 *     · la política salarial y el RIT sin acusar     (Ley 30709)
 *     · días con el marcaje incompleto del periodo que se le va a pagar
 *     · su boleta oficial publicada y todavía sin abrir  (fn_mis_boletas, 0482)
 *
 *   RESPUESTAS — lo que pidió y alguien le contestó. Eso sí caduca a los
 *   DIAS_NOVEDAD, porque no hay nada que hacer con ello:
 *     · el cambio de su ficha, con sus documentos  (solicitudes_cambio_perfil, 0399)
 *     · sus vacaciones                              (solicitudes_vacaciones, 0330)
 *     · que se revisara un día suyo                 (revisiones_pedidas, 0257)
 *
 * POR QUÉ LOS PENDIENTES NO CADUCAN, Y CÓMO SE MARCA «LO LEÍDO»
 *
 * Para lo que hay que FIRMAR, «leído» es «firmado», y eso YA está guardado
 * —`firma_persona_confirmada_at`, `mi_acuse_at`— desde antes: no hace falta
 * ninguna tabla para los PENDIENTES, el sistema no necesita saber si lo
 * miraste, necesita saber si lo hiciste.
 *
 * Para las RESPUESTAS sí hay un «visto» guardado, desde la 0473: reusa
 * `bandeja_vistos` (0436), la misma tabla que ya usaba /admin/bandeja. Hasta
 * entonces se había decidido explícitamente NO guardarlo (2026-09-08) — la
 * objeción de ese día era un «leído» en el NAVEGADOR, que se pierde al
 * cambiar de equipo y, en una computadora compartida, puede dejarle OCULTO a
 * la segunda persona un mensaje que nunca vio. Esa objeción no alcanza a
 * `bandeja_vistos`: es una fila en el servidor atada a `persona_id`, no al
 * navegador, y /mio ya exige sesión propia (a diferencia del terminal de
 * marcaje, que marca sin PIN a propósito) — así que el mismo riesgo que hizo
 * descartar el `localStorage` no existe acá. Ver `fueVista` más abajo y
 * `marcarVistoComo` de `MensajeBandeja`.
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
 * Cuántos días una respuesta sigue contando como novedad SI NADIE LA VIO.
 *
 * Desde la 0473 una respuesta se apaga apenas se marca vista en
 * `bandeja_vistos` (ver `fueVista` en `armarBandeja`) — pero si la persona
 * nunca vuelve a abrir su Bandeja, este número es el que igual la apaga sola.
 * Es un techo, no el único mecanismo: se prefiere un número que insiste de
 * más a uno que calla de menos, para el caso en que «visto» nunca llegue a
 * escribirse (la escritura es best-effort desde el cliente, ver
 * bandeja/page.tsx — si falla, esto sigue siendo la única red).
 *
 * ⚠ NO se aplica a los PENDIENTES. Un contrato sin firmar no caduca a los 14
 * días: caduca cuando se firma. Caducar ahí sería apagar el aviso justo cuando
 * lleva más tiempo sin resolverse.
 */
export const DIAS_NOVEDAD = 14;

export type OrigenBandeja =
  // Lo que pediste y te contestaron.
  | "perfil" | "vacaciones" | "revision" | "revision-movilidad"
  // La constancia de tus estudios (0450): es las dos cosas — te contestan si
  // se aprobó, y depende de ti subirla cuando pagas.
  | "educacion"
  // Lo que depende de ti. No caduca.
  | "contrato" | "memo" | "acuse" | "marcaje" | "ruta" | "bono"
  // Su boleta oficial publicada, sin abrir (0482). Deja de contar cuando la abre.
  | "boleta"
  // Te lo hicieron a ti — no lo pediste, así que no hay nada "esperando" para
  // este origen — pero caduca igual que una respuesta: un turno ya guardado
  // no es algo que quede pendiente de hacer.
  | "turno"
  // Sus reportes (0483/0488): lo que le respondieron y no leyó, y lo que sigue
  // abierto esperando respuesta.
  | "reporte";

/**
 * `atendido` es de las revisiones y no es lo mismo que `aprobado`: a un pedido
 * de revisar un día no se le dice que sí o que no, se le contesta qué se hizo.
 */
export type EstadoBandeja =
  | "aprobado" | "rechazado" | "atendido" | "pendiente"
  /** Depende de una firma tuya: el contrato, un memo, una constancia. */
  | "por_firmar"
  /** Depende de que pidas que se corrija: un día con el marcaje incompleto. */
  | "por_arreglar"
  /** Te dejaron algo para abrir y todavía no lo abriste: tu boleta oficial. */
  | "por_ver";

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
  /**
   * Cómo marcarla como vista en `bandeja_vistos` (0436, extendida por la
   * 0473) para que dejar de ser «nuevo» sobreviva a la próxima carga, sin
   * depender de que la persona vuelva a abrir la pantalla antes de que
   * caduquen sola los DIAS_NOVEDAD. `null` en los PENDIENTES —no caducan
   * nunca, y su insignia ni se pinta, ver `Tarjeta` en bandeja/page.tsx— y en
   * lo que está ESPERANDO —nunca es «nuevo»—: ninguno de los dos necesita
   * marcarse.
   */
  marcarVistoComo: { tipo: string; itemId: string } | null;
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

/**
 * Un cambio de turno que le hicieron, de `correcciones_auditoria` (0298) —
 * filtrado a `campo_modificado = 'turnos.horario'`. Préstamo de
 * infraestructura, no su propósito original: esa tabla es el libro de
 * auditoría de correcciones, y acá se reusa su RLS de lectura propia
 * (`auditoria_select_propia`) en vez de escribir una tabla de avisos nueva.
 * No guarda la fecha del turno como columna propia — solo cuándo se guardó el
 * cambio (`corregido_at`) — así que `motivo` (una frase ya armada por
 * `fn_set_turno`/`fn_set_descanso`/`fn_quitar_turno`) es la única fuente del
 * día exacto que cambió; se resume igual, sin parsearlo, porque ya dice todo
 * lo que hay que decir.
 */
export interface FilaTurno {
  id: string;
  valor_anterior: string;
  valor_nuevo: string;
  corregido_at: string;
  motivo: string;
}

/** Un pedido de revisión de la declaración de ruta, de `movilidad_revisiones_pedidas` (0425). */
export interface FilaRevisionMovilidad {
  id: string;
  motivo: string;
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

/**
 * Un memo que se envió a su Info y todavía no recibió, de
 * `fn_mis_memos_por_recibir()` (0486). Solo `id` y desde cuándo: ni el nivel ni
 * el motivo viajan acá, porque esta tarjeta la ve de reojo cualquiera que pase
 * cerca de la pantalla. El detalle recién existe al abrir el documento.
 */
export interface FilaMemoPorRecibir {
  id: string;
  enviado_a_info_at: string;
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
  /** 0492 — incompleta (versión corta, sin pasaje) o vencida (un año). Sin la
   *  0492 pegada no llega, y se lee como «al día». */
  ruta_por_renovar?: "incompleta" | "vencida" | null;
}

/** Una constancia de estudios suya (0450), de `educacion_entregas`, con su estudio. */
export interface FilaEducacionEntrega {
  id: string;
  familia_id: string;
  institucion: string;
  fecha_pago: string;
  estado: "pendiente" | "aprobada" | "rechazada" | "retirada";
  origen: "colaboradora" | "do" | "migrada";
  enviada_at: string;
  revisada_at: string | null;
  motivo_categoria: MotivoRechazo | null;
  motivo_comentario: string | null;
}

/** Un estudio suyo y en qué está su constancia, tal como lo contesta `fn_educacion_situacion` (0450). */
export interface FilaEducacionSituacion {
  familia_id: string;
  persona_id: string;
  institucion: string;
  estado_constancia: EstadoConstancia;
  fecha_pago_constancia: string | null;
  plazo: string | null;
}

/**
 * Una boleta oficial suya, de `fn_mis_boletas()` (0482). Solo lo que hace falta
 * para decidir si está «nueva» y cómo llamarla: quién la abrió y cuándo es un
 * hecho que la base ya guarda (`vista_at`), así que no hay tabla de «vistos»
 * para esto, igual que con un contrato sin firmar.
 */
export type FilaBoletaBandeja = Pick<FilaMiBoleta, "boleta_id" | "fecha_fin" | "estado" | "vista_at" | "publicada_at">;

export interface FuentesBandeja {
  perfil: FilaPerfil[];
  vacaciones: FilaVacacion[];
  revisiones: FilaRevision[];
  /** El contrato vigente, o null si no tiene ninguno. */
  contrato: FilaContrato | null;
  memos: FilaMemo[];
  /** Memos enviados a su Info que todavía no recibió (0486). Opcional: sin él, no se dice nada. */
  memosPorRecibir?: FilaMemoPorRecibir[];
  /** Ya resueltos por lib/acuses-pendientes.ts: acá solo se pintan. */
  acuses: AcusePendiente[];
  /** Días del periodo abierto, sin filtrar: el criterio de «incompleto» vive acá. */
  marcajes: FilaMarcaje[];
  /** Sin periodo abierto no hay nada que arreglar a tiempo: los marcajes se ignoran. */
  periodo: PeriodoAbierto | null;
  /** Su declaración de ruta. Ver `FilaMovilidad`. */
  movilidad: FilaMovilidad | null;
  /** Sus pedidos de revisión de esa declaración (0425). */
  revisionesMovilidad: FilaRevisionMovilidad[];
  /** Cambios de turno que le hicieron. Ver `FilaTurno`. */
  turnos: FilaTurno[];
  /**
   * Su bono de cumpleaños (0478), de `fn_mi_bono_cumpleanos`. NO del
   * `bono_estado` del tablero: ese no distingue un pedido ya hecho pero todavía
   * sin pagar de uno entregado (0478/0479). Opcional: sin él no se dice nada
   * del bono.
   */
  bono?: MiBono | null;
  /**
   * Está en modalidad formativa (`tipo_vinculo = 'practicante'`). Solo cambia la
   * palabra con la que se nombra lo que cobra: su boleta paga una «subvención»,
   * no una planilla (0521). Opcional: sin él se asume que no.
   */
  practicante?: boolean;
  /** Sus boletas oficiales (0482). Opcional: sin ellas, no se dice nada de boletas. */
  boletas?: FilaBoletaBandeja[];
  /** Sus reportes (0488), de `fn_reportes_mios`. Opcional: sin ellos, no se dice nada de reportes. */
  reportes?: FilaMiReporte[];
  /** Sus constancias de estudios (0450). Opcional: quien no estudia no trae nada. */
  educacionEntregas?: FilaEducacionEntrega[];
  /** Sus estudios y en qué está cada constancia (0450). */
  educacionSituacion?: FilaEducacionSituacion[];
  /**
   * Qué claves de `bandeja_vistos` (0436/0473) ya marcó ella misma, como
   * `"<tipo_item>:<item_id>"` — igual que ya lo lee `/admin/bandeja`. Falla
   * suave si la consulta no vino: un Set vacío hace que todo se vea «nuevo»,
   * que es el lado seguro (nunca esconde una respuesta real).
   */
  vistos: Set<string>;
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

/** `10` → «octubre». Con la ortografía de acá: «setiembre». */
export function nombreDelMes(mes: number): string {
  return MESES[mes - 1] ?? "";
}

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
export function diasEntre(desde: string, hasta: string): number {
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
 *   bono     · pedir su bono de cumpleaños (0477/0478), en el mes de su
 *              onomástico o después. Mismo criterio que la ruta —plata
 *              suya— justo después, porque a diferencia de la ruta no
 *              sostiene un pago que se repite cada periodo.
 *   acuse    · obligación legal de la EMPRESA (Ley 30709, RIT). Importa, pero
 *              quien queda expuesta si falta no es ella.
 *   marcaje  · se arregla mientras el periodo siga abierto, y hasta entonces
 *              no hay nada perdido.
 */
//   educacion · la constancia de su apoyo educativo (0450). Como la ruta, es
//              plata suya de por medio, pero no le cambia el pago de este mes
//              (decisión «solo alerta»): va justo después.
//   boleta   · su boleta oficial publicada (0482). Es un aviso de «ya puedes
//              verla», no algo que se pierda o caduque: va al final, después de
//              lo que tiene un plazo.
const PESO_PENDIENTE: Record<string, number> = { memo: 0, contrato: 1, ruta: 2, bono: 2.2, educacion: 2.5, acuse: 3, marcaje: 4, boleta: 5 };

export function armarBandeja(fuentes: FuentesBandeja, hoy: string = hoyLima()): Bandeja {
  const respuestas: { m: MensajeBandeja; instante: number }[] = [];
  const esperando: { m: MensajeBandeja; instante: number }[] = [];
  const pendientes: { m: MensajeBandeja; instante: number }[] = [];

  const esNueva = (fecha: string) => diasEntre(fecha, hoy) <= DIAS_NOVEDAD;
  // «Visto» en bandeja_vistos: una vez que se marca, deja de ser «nuevo»
  // aunque todavía no pasen los DIAS_NOVEDAD — ver el campo `vistos` de
  // FuentesBandeja y `marcarVistoComo` de MensajeBandeja.
  const fueVista = (tipo: string, itemId: string) => fuentes.vistos.has(`${tipo}:${itemId}`);

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
        marcarVistoComo: null,
      },
    });
  }

  // La declaración de ruta y gasto de transporte (0423). Igual que el
  // contrato: mientras no la firme, sigue contando — no caduca. Y si ya la
  // firmó pero con una tarifa que quedó vieja, se le avisa igual: es la
  // misma alerta que ya pinta el tablero de Documentación para DO, solo que
  // acá le llega a ELLA, que es quien puede arreglarlo firmando de nuevo.
  // Y desde la 0492, si quedó por renovar (incompleta o vencida): también la
  // arregla ELLA firmando de nuevo. La desfasada manda si coinciden.
  const porRenovar = fuentes.movilidad?.estado === "ok" && !fuentes.movilidad.ruta_desfasada
    ? (fuentes.movilidad.ruta_por_renovar ?? null) : null;
  if (fuentes.movilidad && (fuentes.movilidad.estado === "sin_ruta" || fuentes.movilidad.ruta_desfasada || porRenovar)) {
    const mov = fuentes.movilidad;
    const desfasada = mov.estado !== "sin_ruta" && mov.ruta_desfasada;
    const yaFirmada = desfasada || porRenovar !== null;
    pendientes.push({
      instante: yaFirmada && mov.ruta_firmada_el ? Date.parse(`${mov.ruta_firmada_el}T00:00:00Z`) : 0,
      m: {
        clave: "ruta:declaracion", origen: "ruta", estado: "por_firmar",
        fecha: yaFirmada && mov.ruta_firmada_el ? mov.ruta_firmada_el : hoy,
        titulo: desfasada
          ? "Tu declaración de ruta quedó desactualizada"
          : porRenovar === "incompleta"
            ? "Renueva tu declaración de ruta: ahora tiene los cinco puntos"
            : porRenovar === "vencida"
              ? "Renueva tu declaración de ruta: ya pasó un año"
              : "Falta tu declaración de ruta y gasto de transporte",
        respuesta: null,
        detalle: desfasada
          ? `La firmaste declarando S/ ${Number(mov.ruta_monto).toFixed(2)} y hoy se paga otra tarifa. Vuelve a firmarla con el monto vigente.`
          : porRenovar === "incompleta"
            ? "La firmaste con la versión corta, que no preguntaba el costo del pasaje ni el uso de taxi. Vuelve a firmarla; tu movilidad se sigue pagando igual mientras tanto."
            : porRenovar === "vencida"
              ? "Se renueva una vez al año para confirmar tu ruta. Vuelve a firmarla; tu movilidad se sigue pagando igual mientras tanto."
              : "Sostiene que tu movilidad no pague impuestos ni descuentos. Fírmala desde el sistema — no hace falta imprimir ni escanear nada.",
        nuevo: true,
        ir: "/mio/movilidad",
        marcarVistoComo: null,
      },
    });
  }

  // El bono de cumpleaños (0477/0478). Pedirlo ES firmar su constancia, así
  // que le toca a ELLA en el mes de su onomástico, o después si se le pasó.
  // Qué le toca lo decide `fn_mi_bono_cumpleanos` —la misma función que es la
  // puerta del pedido—, no el tablero: por eso acá no hay regla, solo lectura.
  if (fuentes.bono && puedePedirBono(fuentes.bono)) {
    const b = fuentes.bono;
    const monto = b.monto !== null ? `${formatSoles(b.monto)}. ` : "";
    pendientes.push({
      instante: 0,
      m: {
        clave: "bono:pedir", origen: "bono", estado: "por_firmar", fecha: hoy,
        titulo: "Pide tu bono de cumpleaños",
        respuesta: null,
        detalle: b.estado === "vencido"
          ? `${monto}Ya pasó tu cumpleaños y todavía no lo pides: aún estás a tiempo.`
          : `${monto}Es el mes de tu cumpleaños. Lo pides firmando tu constancia.`,
        nuevo: true,
        ir: "/mio/cumpleanos",
        marcarVistoComo: null,
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
        marcarVistoComo: null,
      },
    });
  }

  // Los memos ENVIADOS a su Info que todavía no recibió (0486). Es lo mismo que
  // un memo por firmar para la Bandeja —algo que depende de ella y no caduca—,
  // con una diferencia que importa: ESTE todavía no está entregado, y solo su
  // confirmación lo entrega. Por eso el texto le pide RECIBIRLO, no firmarlo:
  // firmar es opcional, recibir es lo que cuenta.
  //
  // GENÉRICO, igual que arriba: ni el nivel ni el motivo.
  for (const m of fuentes.memosPorRecibir ?? []) {
    pendientes.push({
      instante: Date.parse(m.enviado_a_info_at),
      m: {
        clave: `memo-recibir:${m.id}`, origen: "memo", estado: "por_firmar", fecha: fechaLima(m.enviado_a_info_at),
        titulo: "Tienes un documento por recibir",
        respuesta: null,
        detalle: "Ábrelo, léelo y confirma que lo recibiste. Recibirlo no es aceptar lo que dice: puedes firmarlo y presentar tu descargo, o recibirlo sin firmar.",
        nuevo: true,
        ir: `/mio/memo/${m.id}`,
        marcarVistoComo: null,
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
        marcarVistoComo: null,
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
          marcarVistoComo: null,
        },
      });
    }
  }

  // Su boleta oficial publicada y sin abrir (0482). Cuenta hasta que la abre —
  // `vista_at` ya está guardado—, y NO caduca a los DIAS_NOVEDAD: una boleta sin
  // abrir a los 20 días es justo la que más hay que seguir avisando. Una por
  // periodo, con el mes en el título: dos boletas sin abrir son dos avisos.
  for (const b of fuentes.boletas ?? []) {
    if (!esBoletaNueva(b) || !b.boleta_id) continue;
    pendientes.push({
      instante: b.publicada_at ? Date.parse(b.publicada_at) : 0,
      m: {
        clave: `boleta:${b.boleta_id}`, origen: "boleta", estado: "por_ver",
        fecha: b.publicada_at ? fechaLima(b.publicada_at) : hoy,
        titulo: `Tu boleta de ${nombreDelPeriodo(b.fecha_fin, { conAnio: false, minuscula: true })} ya está disponible`,
        respuesta: null,
        detalle: "Es la boleta oficial que entregó el contador. Ábrela en «Boletas»; seguirá acá hasta que la abras.",
        nuevo: true,
        ir: "/mio?tab=boletas",
        marcarVistoComo: null,
      },
    });
  }

  // Sus reportes (0488). Lo que le escribieron o el cierre, sin leer, cuenta
  // hasta que abre el reporte —abrirlo lo deja escrito en la base— y NO caduca
  // a los DIAS_NOVEDAD, por lo mismo que la boleta: una respuesta sobre algo
  // que ella contó es justo la que no puede perderse. Lo que sigue abierto sin
  // nada nuevo va a «esperando», con la fecha en que le tienen que responder.
  for (const r of fuentes.reportes ?? []) {
    const clave = `reporte:${r.id}`;
    const nombre = `${tituloDeReporte(r.tipo, r.via).toLowerCase()} (${r.codigo})`;
    if (r.sin_leer > 0) {
      const cuando = r.cerrado_at ?? r.ultimo_mensaje_at ?? r.creado_at;
      respuestas.push({
        instante: Date.parse(cuando),
        m: {
          clave, origen: "reporte", estado: "atendido", fecha: fechaLima(cuando),
          titulo: r.estado === "cerrado" ? `Respondieron y cerraron tu reporte: ${nombre}` : `Te respondieron en tu reporte: ${nombre}`,
          respuesta: null,
          detalle: "Ábrelo para leer la respuesta; seguirá acá hasta que lo abras.",
          nuevo: true,
          ir: `/mio/reportes/${r.id}`,
          marcarVistoComo: null,
        },
      });
      continue;
    }
    if (r.estado === "cerrado") continue;
    const fecha = fechaLima(r.creado_at);
    esperando.push({
      instante: Date.parse(r.creado_at),
      m: {
        clave, origen: "reporte", estado: "pendiente", fecha,
        titulo: `Enviaste un reporte: ${nombre}`,
        respuesta: null,
        detalle: r.respuesta_vence_at
          ? `Lo enviaste ${haceCuanto(fecha, hoy)}. Te responden por escrito a más tardar el ${fechaEnPalabras(r.respuesta_vence_at)}.`
          : `Lo enviaste ${haceCuanto(fecha, hoy)}. Sigue en curso.`,
        nuevo: false,
        ir: `/mio/reportes/${r.id}`,
        marcarVistoComo: null,
      },
    });
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
          marcarVistoComo: null,
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
        nuevo: esNueva(fecha) && !fueVista("solicitud_perfil", f.id),
        ir: "/mio/editar",
        marcarVistoComo: { tipo: "solicitud_perfil", itemId: f.id },
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
          marcarVistoComo: null,
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
        nuevo: esNueva(fecha) && !fueVista("solicitud_vacacion", f.id),
        ir: null,
        marcarVistoComo: { tipo: "solicitud_vacacion", itemId: f.id },
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
          marcarVistoComo: null,
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
        nuevo: esNueva(fecha) && !fueVista("revision", f.id),
        ir: null,
        marcarVistoComo: { tipo: "revision", itemId: f.id },
      },
    });
  }

  // Pedidos de revisión de la declaración de ruta (0425) — mismo molde que
  // `revisiones` de arriba, sobre una tabla distinta: no hay "fecha del día
  // que se revisa", solo el motivo que escribió y cuándo lo pidió.
  for (const f of fuentes.revisionesMovilidad) {
    const clave = `revision-movilidad:${f.id}`;
    if (!f.atendida_at) {
      const fecha = fechaLima(f.pedida_at);
      esperando.push({
        instante: Date.parse(f.pedida_at),
        m: {
          clave, origen: "revision-movilidad", estado: "pendiente", fecha,
          titulo: "Pediste una revisión de tu declaración de ruta",
          respuesta: null,
          detalle: `Lo pediste ${haceCuanto(fecha, hoy)}: «${f.motivo}». Todavía no lo revisan.`,
          nuevo: false,
          ir: "/mio/movilidad",
          marcarVistoComo: null,
        },
      });
      continue;
    }

    const fecha = fechaLima(f.atendida_at);
    respuestas.push({
      instante: Date.parse(f.atendida_at),
      m: {
        clave, origen: "revision-movilidad", estado: "atendido", fecha,
        titulo: "Revisamos tu declaración de ruta",
        respuesta: f.respuesta?.trim() || null,
        detalle: f.respuesta?.trim() ? null : "Se revisó, sin nota escrita.",
        nuevo: esNueva(fecha) && !fueVista("revision_movilidad", f.id),
        ir: "/mio/movilidad",
        marcarVistoComo: { tipo: "revision_movilidad", itemId: f.id },
      },
    });
  }

  // Su bono de cumpleaños, después de pedirlo (0478). Mientras DO no confirme
  // la transferencia, lo está ESPERANDO: lo pidió ella, así que nunca es
  // «nuevo». Cuando DO la confirma pasa a respuesta — solo si lo pidió desde
  // el sistema: un cargo en papel lo firmó con el dinero en la mano, no hay
  // nada que avisarle.
  //
  // Esa respuesta NO cuenta en el número del botón, a diferencia de las
  // demás. No por criterio: `bandeja_vistos` no tiene un tipo para marcarla
  // vista, y agregarlo reescribe `fn_bandeja_marcar_visto`, que está en
  // producción y la están ensanchando otras ramas. Sin «visto», contarla
  // dejaría el número en 1 durante DIAS_NOVEDAD aunque ya la haya leído — y
  // un contador que no baja enseña a no mirarlo. La ve igual en la lista, en
  // Info y en /mio/cumpleanos.
  if (fuentes.bono?.estado === "pedido" && fuentes.bono.pedido_el) {
    const b = fuentes.bono;
    const pedidoEl = fuentes.bono.pedido_el;
    esperando.push({
      instante: Date.parse(`${pedidoEl}T00:00:00Z`),
      m: {
        clave: `bono:${b.documento_id}`, origen: "bono", estado: "pendiente", fecha: pedidoEl,
        titulo: "Pediste tu bono de cumpleaños",
        respuesta: null,
        detalle: `Lo pediste ${haceCuanto(pedidoEl, hoy)}. Desarrollo Organizacional todavía no confirma la transferencia.`,
        nuevo: false,
        ir: "/mio/cumpleanos",
        marcarVistoComo: null,
      },
    });
  } else if (fuentes.bono?.estado === "en_boleta" && fuentes.bono.pedido_el) {
    // Desde la 0479 este es el camino normal: al firmar, el bono entra a su
    // boleta y ya no hay nadie a quien esperar — solo la fecha de la planilla.
    // Sigue en «esperando» y no en «pendientes» por lo mismo que `pedido`: no
    // hay nada que ella deba hacer, así que no cuenta en el botón.
    const b = fuentes.bono;
    const pedidoEl = fuentes.bono.pedido_el;
    esperando.push({
      instante: Date.parse(`${pedidoEl}T00:00:00Z`),
      m: {
        clave: `bono:${b.documento_id}`, origen: "bono", estado: "pendiente", fecha: pedidoEl,
        titulo: "Tu bono de cumpleaños va en tu boleta",
        respuesta: null,
        detalle: `Lo pediste ${haceCuanto(pedidoEl, hoy)}. ${b.monto !== null ? `${formatSoles(b.monto)} ya ` : "Ya "}está en tu boleta${
          b.periodo_fin ? ` del periodo que cierra el ${diaYMes(b.periodo_fin)}` : ""} y se paga junto con ${
          fuentes.practicante ? "tu subvención" : "tu planilla"}.`,
        nuevo: false,
        ir: "/mio/cumpleanos",
        marcarVistoComo: null,
      },
    });
  } else if (fuentes.bono?.estado === "entregado" && fuentes.bono.via === "boleta" && fuentes.bono.periodo_fin) {
    // Pagado con la planilla. No hay «día en que se transfirió»: la planilla no
    // lo guarda por persona, así que se dice el periodo que la pagó.
    const b = fuentes.bono;
    const periodoFin = fuentes.bono.periodo_fin;
    respuestas.push({
      instante: Date.parse(`${periodoFin}T00:00:00Z`),
      m: {
        clave: `bono:${b.documento_id}`, origen: "bono", estado: "atendido", fecha: periodoFin,
        titulo: `Tu bono de cumpleaños se pagó con ${fuentes.practicante ? "tu subvención" : "tu planilla"}`,
        respuesta: null,
        detalle: `${b.monto !== null ? `${formatSoles(b.monto)} · ` : ""}en tu boleta del periodo que cerró el ${diaYMes(periodoFin)}.`,
        nuevo: false,
        ir: "/mio/cumpleanos",
        marcarVistoComo: null,
      },
    });
  } else if (fuentes.bono?.estado === "entregado" && fuentes.bono.pedido_el && fuentes.bono.entregado_el) {
    const b = fuentes.bono;
    const entregadoEl = fuentes.bono.entregado_el;
    respuestas.push({
      instante: Date.parse(`${entregadoEl}T00:00:00Z`),
      m: {
        clave: `bono:${b.documento_id}`, origen: "bono", estado: "atendido", fecha: entregadoEl,
        titulo: "Te transfirieron tu bono de cumpleaños",
        respuesta: null,
        detalle: `${b.monto !== null ? `${formatSoles(b.monto)} · ` : ""}transferido el ${diaYMes(entregadoEl)}.`,
        nuevo: false,
        ir: "/mio/cumpleanos",
        marcarVistoComo: null,
      },
    });
  }

  // Cambios de turno que le hicieron (0298). No los pidió — alguien con
  // permiso le cambió el horario — así que no hay nada "esperando": entran
  // directo como respuesta, y caducan igual que las demás a los DIAS_NOVEDAD.
  for (const f of fuentes.turnos) {
    const fecha = fechaLima(f.corregido_at);
    respuestas.push({
      instante: Date.parse(f.corregido_at),
      m: {
        clave: `turno:${f.id}`, origen: "turno", estado: "atendido", fecha,
        titulo: `Tu turno cambió: ${f.valor_anterior} → ${f.valor_nuevo}`,
        respuesta: null,
        detalle: f.motivo,
        nuevo: esNueva(fecha) && !fueVista("cambio_turno", f.id),
        ir: "/mio?tab=turnos",
        marcarVistoComo: { tipo: "cambio_turno", itemId: f.id },
      },
    });
  }

  // ── LAS CONSTANCIAS DE ESTUDIOS (0450) ─────────────────────────────────
  // Lo que envió y espera, lo que le contestaron, y lo que depende de ella.
  // Solo lo que envió ELLA: lo que carga DO a su nombre no contesta nada que
  // haya pedido, y anunciarlo sería ruido.
  const rechazoReciente = new Set<string>();
  for (const f of fuentes.educacionEntregas ?? []) {
    if (f.origen !== "colaboradora") continue;
    const clave = `educacion:${f.id}`;
    const ir = `/mio/educacion?familia=${f.familia_id}`;
    if (f.estado === "pendiente") {
      const fecha = fechaLima(f.enviada_at);
      esperando.push({
        instante: Date.parse(f.enviada_at),
        m: {
          clave, origen: "educacion", estado: "pendiente", fecha,
          titulo: `Enviaste la constancia de tu pago a ${f.institucion}`,
          respuesta: null,
          detalle: `La enviaste ${haceCuanto(fecha, hoy)}. Desarrollo Organizacional todavía no la revisa.`,
          nuevo: false,
          ir,
          marcarVistoComo: null,
        },
      });
      continue;
    }
    // «retirada» se salta: la retiraste tú. No es una respuesta.
    if ((f.estado !== "aprobada" && f.estado !== "rechazada") || !f.revisada_at) continue;

    const fecha = fechaLima(f.revisada_at);
    const aprobada = f.estado === "aprobada";
    if (!aprobada && esNueva(fecha)) rechazoReciente.add(f.familia_id);
    respuestas.push({
      instante: Date.parse(f.revisada_at),
      m: {
        clave, origen: "educacion", estado: aprobada ? "aprobado" : "rechazado", fecha,
        titulo: `Tu constancia del pago del ${diaYMes(f.fecha_pago)} fue ${aprobada ? "aprobada" : "rechazada"}`,
        // En un rechazo la categoría y el comentario son obligatorios (0450):
        // son lo único que le dice qué corregir.
        respuesta: aprobada ? null : [
          f.motivo_categoria ? MOTIVO_RECHAZO_LABELS[f.motivo_categoria] : null,
          f.motivo_comentario?.trim() || null,
        ].filter(Boolean).join(": ") || null,
        detalle: aprobada
          ? `${f.institucion}. No tienes que hacer nada más con este pago.`
          : "Corrígela y vuelve a enviarla desde Educación. Lo que cobras este mes no cambia.",
        nuevo: esNueva(fecha) && !fueVista("entrega_educacion", f.id),
        ir,
        marcarVistoComo: { tipo: "entrega_educacion", itemId: f.id },
      },
    });
  }

  for (const s of fuentes.educacionSituacion ?? []) {
    if (!constanciaPideAlgoALaIntegrante(s.estado_constancia)) continue;
    // Un rechazo reciente ya está arriba como respuesta, con su motivo y su
    // enlace: contarlo también como pendiente sería avisar dos veces de lo mismo.
    if (s.estado_constancia === "rechazada" && rechazoReciente.has(s.familia_id)) continue;
    // 0526: un apoyo mensual la pide desde el día 1 del mes, con el pago todavía por venir. «Pago
    // del 15» diría que ya pagó, y «hace N días» no se cuenta contra una fecha que no llegó.
    const anticipada = constanciaPedidaAntesDelPago(s, hoy);
    const pago = s.fecha_pago_constancia
      ? `${anticipada ? "Pagas el" : "Pago del"} ${diaYMes(s.fecha_pago_constancia)}. `
      : "";
    const plazo = s.plazo ? `Tienes hasta el ${diaYMes(s.plazo)}. ` : "";
    pendientes.push({
      instante: s.plazo ? Date.parse(`${s.plazo}T00:00:00Z`) : 0,
      m: {
        clave: `educacion-constancia:${s.familia_id}`, origen: "educacion", estado: "por_arreglar",
        fecha: s.fecha_pago_constancia && !anticipada ? s.fecha_pago_constancia : hoy,
        titulo: s.estado_constancia === "rechazada"
          ? `Corrige la constancia de ${s.institucion}`
          : s.estado_constancia === "vencida"
            ? `Pasó el plazo de tu constancia de ${s.institucion}`
            : anticipada
              ? `Este mes toca la constancia de tu pago a ${s.institucion}`
              : `Sube la constancia de tu pago a ${s.institucion}`,
        respuesta: null,
        detalle: `${pago}${plazo}Es el respaldo de tu apoyo educativo; subirla no cambia lo que cobras.`,
        nuevo: true,
        ir: `/mio/educacion?familia=${s.familia_id}`,
        marcarVistoComo: null,
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
  const [perfil, catalogo, vacaciones, revisiones, contrato, memos, acuses, periodo, movilidad, revisionesMovilidad, turnos,
    educacionEntregas, educacionSituacion, vistos, bono, boletas, memosPorRecibir, reportes, ficha] =
    await Promise.all([
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
    // Sus propios pedidos de revisión de esa declaración (0425). Sin admin de
    // por medio, esta misma RPC ya devuelve solo lo suyo — mismo criterio que
    // fn_documentos_tablero con p_solo_mi_fila.
    supabase.rpc("fn_movilidad_revisiones_pedidas", { p_solo_pendientes: false }),
    // Cambios de turno que le hicieron (0298). El `.eq("persona_id", …)` de
    // acá es el mismo freno que ya explica el encabezado de esta función:
    // `auditoria_select_supervisor` le abre a una encargada toda su sede, así
    // que sin este filtro su propia Bandeja podría mostrarle el turno de otra
    // persona como si fuera el suyo.
    supabase.from("correcciones_auditoria")
      .select("id, valor_anterior, valor_nuevo, corregido_at, motivo")
      .eq("persona_id", personaId)
      .eq("campo_modificado", "turnos.horario")
      .order("corregido_at", { ascending: false })
      .limit(LIMITE),
    // Sus constancias de estudios (0450). El `.eq` sobre la persona de la
    // asignación es el mismo freno de arriba: si quien abre /mio es de DO, la
    // RLS de educacion_entregas le abre las de todo el equipo.
    supabase.from("educacion_entregas")
      .select("id, fecha_pago, estado, origen, enviada_at, revisada_at, motivo_categoria, motivo_comentario, asignaciones_educacion!inner(persona_id, institucion, familia_id)")
      .eq("asignaciones_educacion.persona_id", personaId)
      .order("enviada_at", { ascending: false })
      .limit(LIMITE),
    // En qué está cada estudio suyo: la misma función que lee el panel de DO,
    // filtrada abajo por persona por la misma razón.
    supabase.rpc("fn_educacion_situacion"),
    // Qué ya marcó como visto ella misma (0436, extendida por la 0473). El
    // `.eq` es cinturón y tirantes: `bandeja_vistos` hoy solo tiene una
    // policy de lectura (la propia, sin excepción para admin ni líder — ver
    // 0436), así que no hay una segunda policy que ensanche esto como sí
    // pasa con `revisiones_pedidas` o `correcciones_auditoria` arriba, pero
    // el filtro explícito no cuesta nada y evita tener que recordarlo si eso
    // cambia. Falla suave: sin esto, todo se ve «nuevo», el lado seguro.
    supabase.from("bandeja_vistos").select("tipo_item, item_id").eq("persona_id", personaId),
    // Su bono de cumpleaños (0478). La función ya contesta solo por quien
    // pregunta (`fn_persona_actual_id`), sin excepción para DO.
    traerMiBono(supabase),
    // Sus boletas oficiales (0482). La función contesta solo por quien
    // pregunta, sin excepción para DO: no hace falta filtro de persona.
    traerMisBoletas(supabase),
    // Los memos que le enviaron a su Info y todavía no recibió (0486). La función
    // contesta solo por quien pregunta y devuelve únicamente los enviados: un
    // borrador, o un firmado que nadie envió, sigue siendo invisible para ella.
    supabase.rpc("fn_mis_memos_por_recibir"),
    // Sus reportes (0488). Igual: `fn_reportes_mios` contesta solo por quien pregunta.
    traerMisReportes(supabase),
    // Su vínculo (0521): solo para nombrar bien lo que cobra. Falla suave: sin él
    // se dice «planilla», que es lo que decía antes — y NO entra en `noSePudo`,
    // por lo mismo que las etiquetas del catálogo.
    supabase.from("personas").select("tipo_vinculo").eq("id", personaId).maybeSingle(),
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
    memosPorRecibir: ((memosPorRecibir.data ?? []) as unknown as FilaMemoPorRecibir[]),
    acuses,
    marcajes: ((marcajes?.data ?? []) as unknown as FilaMarcaje[]),
    periodo: per,
    movilidad: ((movilidad.data ?? []) as FilaMovilidad[])[0] ?? null,
    revisionesMovilidad: (revisionesMovilidad.data ?? []) as unknown as FilaRevisionMovilidad[],
    turnos: (turnos.data ?? []) as unknown as FilaTurno[],
    educacionEntregas: ((educacionEntregas.data ?? []) as unknown as (Omit<FilaEducacionEntrega, "familia_id" | "institucion"> & {
      asignaciones_educacion: { familia_id: string; institucion: string };
    })[]).map(({ asignaciones_educacion: a, ...e }) => ({ ...e, familia_id: a.familia_id, institucion: a.institucion })),
    educacionSituacion: ((educacionSituacion.data ?? []) as unknown as FilaEducacionSituacion[])
      .filter((s) => s.persona_id === personaId),
    bono: bono.bono,
    practicante: (ficha.data as { tipo_vinculo?: string } | null)?.tipo_vinculo === "practicante",
    boletas: boletas.filas,
    reportes: reportes.filas,
    vistos: new Set(
      ((vistos.data ?? []) as { tipo_item: string; item_id: string }[])
        .map((v) => `${v.tipo_item}:${v.item_id}`),
    ),
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
      // Si la 0486 no está pegada esto lo dice a gritos, como con las boletas: un
      // documento por recibir que no se muestra es peor que un aviso de más.
      { error: memosPorRecibir.error, que: "tus documentos por recibir" },
      { error: marcajes?.error ?? null, que: "tus días del periodo" },
      { error: movilidad.error, que: "tu declaración de ruta" },
      { error: revisionesMovilidad.error, que: "tus pedidos de revisión de esa declaración" },
      { error: turnos.error, que: "tus cambios de turno" },
      { error: educacionEntregas.error, que: "tus constancias de estudios" },
      { error: educacionSituacion.error, que: "tu apoyo educativo" },
      { error: bono.error, que: "tu bono de cumpleaños" },
      // Solo importa que haya fallado: para no pintar «no tienes nada» sobre una
      // boleta que sí hay. (Si la 0482 no está pegada, esto lo dice a gritos.)
      { error: boletas.error, que: "tus boletas" },
      { error: reportes.error, que: "tus reportes" },
    ]),
  };
}

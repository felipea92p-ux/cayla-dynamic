/**
 * Provisiones — cómo se LEE lo que entrega `fn_provisiones` (vigente: 0428).
 *
 * QUÉ PROMETE
 *   Traduce el jsonb de la base a lo que la pantalla tiene que decir: el estado
 *   de cada ventana, el próximo desembolso, el calendario, los filtros y las
 *   filas del CSV. NO recalcula ningún monto que la base ya calcula: los saldos,
 *   los totales por beneficio y `gran_total` se leen, nunca se rehacen.
 *
 * QUÉ ASUME
 *   La forma del jsonb desde la 0428 (con `be_s1`/`be_s2` de la 0372 y los
 *   `*_monto_pagado` de la 0123/0273). Montos redondeados a céntimos. Fechas ISO
 *   «AAAA-MM-DD», comparadas como texto — nunca `new Date()`, que corre un día
 *   según la zona del navegador.
 *
 * POR QUÉ VIVE ACÁ Y NO DENTRO DE LA PÁGINA
 *   `fn_grati_cts_periodo` autocompleta el pago real de gratificación y CTS con
 *   este mismo jsonb. Una regla como «qué está vencido» o «cuánto sale el 15» no
 *   puede tener una versión escondida en un componente que nadie prueba: se
 *   prueba aquí, sin navegador (tests/provisiones.test.ts).
 */

// ── Forma del jsonb de fn_provisiones ────────────────────────────────────────

export type VentanaClave = "grati_s1" | "grati_s2" | "cts_may" | "cts_nov";

export interface ProvPersona {
  persona_id: string;
  nombre: string;
  sede: string;
  fecha_ingreso: string;
  // ⇩ 0428 ⇩ Un practicante (Ley 28518) no devenga gratificación, CTS ni
  // vacaciones y aun así ocupa una fila. Sin este dato su cero se leería igual
  // que el de alguien recién ingresado que «aún no devengó».
  tipo_vinculo?: string;
  grati_s1: number;
  grati_s2: number;
  grati_total: number;
  // ⇩ 0134 · 0372 ⇩ La bonificación extraordinaria de la Ley 30334: el 9 % que,
  // en vez de ir a EsSalud, se le paga a la persona con la gratificación. Desde
  // la 0372 lleva su propia cuenta por ventana.
  be_s1?: number;
  be_s2?: number;
  be_total: number;
  tasa_be: number;
  cts_may: number;
  cts_nov: number;
  cts_total: number;
  // ⇩ 0123 · 0158 · 0273 ⇩ Cada celda es devengado − cobrado. El monto cobrado
  // viaja aparte para poder decir «pagado» en vez de un cero que se lee como
  // «no le tocaba nada».
  grati_s1_pagada?: boolean;
  grati_s2_pagada?: boolean;
  cts_may_pagada?: boolean;
  cts_nov_pagada?: boolean;
  grati_s1_monto_pagado?: number | null;
  grati_s2_monto_pagado?: number | null;
  cts_may_monto_pagado?: number | null;
  cts_nov_monto_pagado?: number | null;
  vac: number;
  vac_pagada?: boolean;
  vac_monto_pagado?: number | null;
  vac_dias: number;
  proximo_aniversario: string;
  // La única definición del número: grati + bonificación + CTS + vacaciones,
  // sumadas ya redondeadas. Se lee; no se vuelve a sumar acá (ver 2026-08-19).
  gran_total: number;
  // ⇩ 0365 ⇩ Quien devenga y no tiene tramo en `asignaciones_salario` sale con
  // reservas cortas o en cero. Esto lo dice; no cambia ningún monto.
  sin_salario_vigente?: boolean;
  dias_sin_salario?: number;
}

export interface ProvData {
  as_of: string;
  factores: { gratificacion?: number; cts?: number; vacaciones?: number; sexto_cts?: number };
  proximo: { fecha: string | null; tipo: string | null; ref: VentanaClave | null };
  grati_s1_pago: string;
  grati_s2_pago: string;
  cts_may_pago: string;
  cts_nov_pago: string;
  grati_s1_periodo: string;
  grati_s2_periodo: string;
  cts_may_periodo: string;
  cts_nov_periodo: string;
  personas: ProvPersona[];
  personas_sin_salario?: number;
}

/** Una fila del libro de desembolsos (`desembolsos_beneficios`, 0155). */
export interface DesembolsoLibro {
  persona_id: string;
  ventana: string;
  anio: number;
  monto: number;
  fecha_pago: string;
  origen: string;
  nota: string | null;
  created_at: string;
}

// ── Utilidades de forma ──────────────────────────────────────────────────────

// Menos de medio céntimo es ruido de coma flotante al sumar dos montos ya
// redondeados, no plata.
const EPS = 0.005;
const redondear = (n: number) => Math.round(n * 100) / 100;
const MESES_CORTOS = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];
const MESES = [
  "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
  "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre",
];

/** "2026-11-15" → "15 nov 2026" (por texto: nunca new Date()). */
export function fechaCorta(iso: string | null | undefined): string {
  if (!iso) return "—";
  const [y, m, d] = iso.split("-");
  const mes = MESES_CORTOS[Number(m) - 1];
  if (!y || !mes || !d) return iso;
  return `${Number(d)} ${mes} ${y}`;
}

const anioDe = (iso: string) => iso.slice(0, 4);

export const esPracticante = (p: ProvPersona) => p.tipo_vinculo === "practicante";

// ── Lo que devenga una practicante (0467) ────────────────────────────────────
//
// Viene de `fn_subvenciones_practicante`, una función APARTE de fn_provisiones.
// Son los dos pagos de la Ley 28518 art. 42 —media subvención por cada 6 meses
// continuos, y 15 días de descanso al cumplir 12— que no son gratificación, CTS
// ni vacaciones (art. 47) y que por eso no viven en el mismo cálculo.
//
// Por lo mismo, el `gran_total` que manda fn_provisiones para una practicante
// es CERO y sigue siendo correcto. El saldo que muestra la pantalla para ella
// es `total_saldo` de aquí: dos funciones, dos números, y la pantalla dice cuál
// está mirando.

export interface SubvPersona {
  persona_id: string;
  nombre: string;
  sede: string;
  fecha_ingreso: string;
  /** La subvención mensual vigente al corte. null = no hay tramo cargado. */
  subvencion_mensual: number | null;
  sin_subvencion: boolean;
  semestres_cumplidos: number;
  semestre_desde: string;
  semestre_hasta: string;
  /** Cuándo cae el próximo hito de 6 meses. */
  proximo_hito: string;
  media_sub_devengado: number;
  media_sub_pagado: number | null;
  media_sub_saldo: number;
  /** El día en que cumple 12 meses y el descanso queda ganado. */
  descanso_cumple: string;
  descanso_ganado: boolean;
  descanso_devengado: number;
  descanso_pagado: number | null;
  descanso_saldo: number;
  total_saldo: number;
}

export interface SubvData {
  as_of: string;
  factor_media_subvencion: number;
  factor_descanso: number;
  personas: SubvPersona[];
}

/** undefined = leyendo · null = no se pudo leer · objeto = leído */
export type Subvenciones = SubvData | null | undefined;

export function subvencionDe(s: Subvenciones, p: ProvPersona): SubvPersona | null {
  if (!s) return null;
  return s.personas.find((x) => x.persona_id === p.persona_id) ?? null;
}

/**
 * El saldo de una fila. Para una practicante son sus dos conceptos; para el
 * resto, el `gran_total` que calcula la base. Nunca se mezclan en una suma:
 * son dos cuentas distintas, de dos funciones distintas.
 */
export function saldoDeFila(p: ProvPersona, s: Subvenciones): number {
  if (esPracticante(p)) return subvencionDe(s, p)?.total_saldo ?? 0;
  return p.gran_total;
}

export interface TotalesSubvenciones {
  media: number;
  descanso: number;
  total: number;
  personas: number;
}

/** Suma de las practicantes visibles; devuelve null si no hay ninguna. */
export function totalesSubvenciones(personas: ProvPersona[], s: Subvenciones): TotalesSubvenciones | null {
  const filas = personas.map((p) => subvencionDe(s, p)).filter((x): x is SubvPersona => x !== null);
  if (!filas.length) return null;
  return {
    media: redondear(filas.reduce((a, x) => a + x.media_sub_saldo, 0)),
    descanso: redondear(filas.reduce((a, x) => a + x.descanso_saldo, 0)),
    total: redondear(filas.reduce((a, x) => a + x.total_saldo, 0)),
    personas: filas.length,
  };
}

// ── Las cuatro ventanas del año que la base calcula ──────────────────────────

export interface Ventana {
  clave: VentanaClave;
  beneficio: "Gratificación" | "CTS";
  /** Mes en que se paga: "Julio". */
  mes: string;
  /** Qué meses cubre, como lo manda la base: "ene–jun". */
  periodo: string;
  /** Último día que acumula. Hasta ahí el saldo crece. */
  cierre: string;
  /** Fecha legal de pago o depósito. */
  pago: string;
}

/**
 * Las ventanas son las del AÑO DE LA FECHA DE CORTE, igual que en la base
 * (`v_y` en fn_provisiones). Por eso el cierre se arma con ese año.
 */
export function ventanasDe(d: ProvData): Ventana[] {
  const y = anioDe(d.as_of);
  const periodo = (s: string) => s.replace("-", "–");
  const mes = (iso: string) => MESES[Number(iso.slice(5, 7)) - 1] ?? "—";
  return [
    { clave: "cts_may", beneficio: "CTS", mes: mes(d.cts_may_pago), periodo: periodo(d.cts_may_periodo), cierre: `${y}-04-30`, pago: d.cts_may_pago },
    { clave: "grati_s1", beneficio: "Gratificación", mes: mes(d.grati_s1_pago), periodo: periodo(d.grati_s1_periodo), cierre: `${y}-06-30`, pago: d.grati_s1_pago },
    { clave: "cts_nov", beneficio: "CTS", mes: mes(d.cts_nov_pago), periodo: periodo(d.cts_nov_periodo), cierre: `${y}-10-31`, pago: d.cts_nov_pago },
    { clave: "grati_s2", beneficio: "Gratificación", mes: mes(d.grati_s2_pago), periodo: periodo(d.grati_s2_periodo), cierre: `${y}-12-31`, pago: d.grati_s2_pago },
  ];
}

/** El 9 % pendiente que corresponde a una ventana (solo gratificación). */
export function bonificacionDe(p: ProvPersona, clave: VentanaClave): number {
  if (clave === "grati_s1") return p.be_s1 ?? 0;
  if (clave === "grati_s2") return p.be_s2 ?? 0;
  return 0;
}

/**
 * Lo que falta de una ventana. En gratificación incluye su 9 %: se paga el
 * mismo día, así que para saber cuánto sale del banco van juntos.
 */
export function saldoVentana(p: ProvPersona, clave: VentanaClave): number {
  return redondear(p[clave] + bonificacionDe(p, clave));
}

/** Lo ya cobrado de la ventana (planilla o libro, la mayor — decisión de la 0158). */
export function pagadoVentana(p: ProvPersona, clave: VentanaClave): number {
  const campo = `${clave}_monto_pagado` as const;
  return p[campo] ?? 0;
}

/**
 * Lo devengado, sin el 9 %. No viaja en el jsonb, pero se deduce sin rehacer
 * nada: la base arma cada celda como devengado − cobrado.
 */
export function devengadoVentana(p: ProvPersona, clave: VentanaClave): number {
  return redondear(p[clave] + pagadoVentana(p, clave));
}

/**
 * La columna «Gratificación» de la tabla: la gratificación y su 9 % juntos.
 * Con ella, Gratificación + CTS + Vacaciones es exactamente `gran_total`, y el
 * total vuelve a cuadrar con lo que se ve (la regla del 2026-08-19).
 */
export function gratiConBonificacion(p: ProvPersona): number {
  return redondear(p.grati_total + p.be_total);
}

// ── Estados ──────────────────────────────────────────────────────────────────

export type EstadoVentana =
  | "no_aplica"
  | "pagado_de_mas"
  | "vencido"
  | "pago_parcial"
  | "pagado"
  | "acumulando"
  | "sin_monto";

// La clave interna sigue siendo `vencido` (la usan los filtros y las pruebas),
// pero la pantalla no lo dice así: quien la lee es quien PAGA, y para él una
// ventana cuya fecha ya pasó no es algo «vencido» —que suena a plazo perdido
// por otro— sino plata que se debe. Pedido por Felipe el 2026-10-10.
export const ETIQUETA_ESTADO_VENTANA: Record<EstadoVentana, string> = {
  no_aplica: "No aplica",
  pagado_de_mas: "Pagado de más",
  vencido: "Se debe",
  pago_parcial: "Pago parcial · se debe el resto",
  pagado: "Pagado",
  acumulando: "Acumulando",
  sin_monto: "Sin monto",
};

/**
 * El estado de una ventana a la fecha de corte.
 *
 * «Vencido» es que la fecha de pago YA PASÓ y todavía queda saldo. El mismo
 * día del pago no está vencido: todavía se puede pagar ese día.
 *
 * El negativo se dice «pagado de más» y no se esconde (decisión de la 0158,
 * prueba 124). La pantalla no sabe POR QUÉ: puede ser un depósito legítimo del
 * contador, una base incompleta o un adelanto anotado en otra ventana. Por eso
 * el detalle muestra de dónde sale, y no un diagnóstico inventado.
 */
export function estadoVentana(p: ProvPersona, v: Ventana, asOf: string): EstadoVentana {
  if (esPracticante(p)) return "no_aplica";
  const saldo = saldoVentana(p, v.clave);
  const pagado = pagadoVentana(p, v.clave);
  if (saldo < -EPS) return "pagado_de_mas";
  if (asOf > v.pago) {
    if (saldo > EPS) return pagado > EPS ? "pago_parcial" : "vencido";
    return pagado > EPS ? "pagado" : "sin_monto";
  }
  return "acumulando";
}

export function estadoVacaciones(p: ProvPersona): EstadoVentana {
  if (esPracticante(p)) return "no_aplica";
  return p.vac < -EPS ? "pagado_de_mas" : "acumulando";
}

export type EstadoFila = "sin_tramo" | "vencido" | "pagado_de_mas" | "al_dia" | "no_aplica";

export const ETIQUETA_ESTADO_FILA: Record<EstadoFila, string> = {
  sin_tramo: "Salario sin cargar",
  vencido: "Se le debe",
  pagado_de_mas: "Pagado de más",
  al_dia: "Al día",
  no_aplica: "No aplica",
};

/**
 * Lo que requiere mirar a esta persona, del más grave al menos.
 *
 * «Salario sin cargar» cubre los dos avisos de la 0365: no tener tramo a la
 * fecha de corte, y haber tenido días sin tramo dentro del año que reserva.
 * Con solo el primero, quien tuvo un hueco salía «Al día» al lado de un panel
 * que decía «240 días sin salario cargado» — medido en el laboratorio el
 * 2026-09-15. Un «Al día» que no lo es es el falso positivo más caro de esta
 * pantalla: es el que hace que nadie mire.
 */
export function estadosFila(p: ProvPersona, d: ProvData): EstadoFila[] {
  if (esPracticante(p)) return ["no_aplica"];
  const ventanas = ventanasDe(d);
  const estados = ventanas.map((v) => estadoVentana(p, v, d.as_of));
  const out: EstadoFila[] = [];
  if (p.sin_salario_vigente || (p.dias_sin_salario ?? 0) > 0) out.push("sin_tramo");
  if (estados.some((e) => e === "vencido" || e === "pago_parcial")) out.push("vencido");
  if (estados.includes("pagado_de_mas") || estadoVacaciones(p) === "pagado_de_mas") out.push("pagado_de_mas");
  return out.length ? out : ["al_dia"];
}

// ── Próximo desembolso ───────────────────────────────────────────────────────

export interface ProximoDesembolso {
  fecha: string;
  clave: VentanaClave;
  beneficio: "Gratificación" | "CTS";
  /** Hasta cuándo acumula; null cuando la ventana no es del año de corte. */
  cierre: string | null;
  /**
   * false entre el 16 y el 31 de diciembre. La base apunta entonces al pago de
   * mayo del año SIGUIENTE, pero sus cuatro ventanas siguen siendo las del año
   * de corte: leer `cts_may` daría la CTS de mayo que ya pasó. En ese tramo no
   * hay monto que mostrar, y se dice en vez de inventarlo (defecto C2 de la
   * auditoría del 2026-09-15; el arreglo de fondo va en su propia migración).
   */
  fiable: boolean;
}

export function proximoDesembolso(d: ProvData): ProximoDesembolso | null {
  const { fecha, ref } = d.proximo ?? {};
  if (!fecha || !ref) return null;
  const fiable = anioDe(fecha) === anioDe(d.as_of);
  const v = ventanasDe(d).find((x) => x.clave === ref);
  return {
    fecha,
    clave: ref,
    beneficio: ref.startsWith("grati") ? "Gratificación" : "CTS",
    cierre: fiable && v ? v.cierre : null,
    fiable,
  };
}

/** Lo acumulado a hoy de la próxima ventana, para una persona. */
export function montoProximo(p: ProvPersona, d: ProvData): number | null {
  const prox = proximoDesembolso(d);
  if (!prox || !prox.fiable || esPracticante(p)) return null;
  return saldoVentana(p, prox.clave);
}

/**
 * Cuánto va acumulado para la próxima fecha, sumando a todo el equipo.
 *
 * Suma solo los saldos POSITIVOS, a propósito: si a una persona se le depositó
 * de más, eso no achica el depósito que hay que hacerle a otra. Neteado, el
 * número diría que sale del banco menos de lo que sale.
 */
export function totalProximo(personas: ProvPersona[], d: ProvData): number | null {
  const prox = proximoDesembolso(d);
  if (!prox || !prox.fiable) return null;
  return redondear(personas.reduce((a, p) => a + Math.max(montoProximo(p, d) ?? 0, 0), 0));
}

// ── Resumen y calendario ─────────────────────────────────────────────────────

export interface ResumenProvisiones {
  gratificacion: number;
  cts: number;
  vacaciones: number;
  /** Suma de `gran_total` de cada fila, tal como lo entrega la base. */
  total: number;
  /** Cuánto de ese total son pagos de más (negativo o cero). */
  ajustes: number;
}

export function resumen(personas: ProvPersona[]): ResumenProvisiones {
  let gratificacion = 0, cts = 0, vacaciones = 0, total = 0, ajustes = 0;
  for (const p of personas) {
    gratificacion += gratiConBonificacion(p);
    cts += p.cts_total;
    vacaciones += p.vac;
    total += p.gran_total;
    for (const clave of ["grati_s1", "grati_s2", "cts_may", "cts_nov"] as const) {
      ajustes += Math.min(saldoVentana(p, clave), 0);
    }
    ajustes += Math.min(p.vac, 0);
  }
  return {
    gratificacion: redondear(gratificacion),
    cts: redondear(cts),
    vacaciones: redondear(vacaciones),
    total: redondear(total),
    ajustes: redondear(ajustes),
  };
}

export interface EntradaCalendario {
  ventana: Ventana | null;
  fecha: string;
  beneficio: "Gratificación" | "CTS";
  /** null cuando no hay un monto fiable que mostrar (16–31 dic). */
  monto: number | null;
  personas: { persona_id: string; nombre: string; monto: number }[];
}

export interface Calendario {
  /** Fecha de pago pasada y saldo pendiente, de las más viejas a las recientes. */
  vencidos: EntradaCalendario[];
  /** Fechas que vienen, en orden. */
  proximos: EntradaCalendario[];
  /** Vacaciones acumuladas: no tienen una fecha común, se pagan al gozarlas. */
  vacaciones: number;
}

export function calendario(d: ProvData, personas: ProvPersona[]): Calendario {
  const conDerecho = personas.filter((p) => !esPracticante(p));
  const vencidos: EntradaCalendario[] = [];
  const proximos: EntradaCalendario[] = [];

  for (const v of ventanasDe(d)) {
    if (d.as_of > v.pago) {
      const debe = conDerecho
        .filter((p) => {
          const e = estadoVentana(p, v, d.as_of);
          return e === "vencido" || e === "pago_parcial";
        })
        .map((p) => ({ persona_id: p.persona_id, nombre: p.nombre, monto: saldoVentana(p, v.clave) }));
      if (debe.length) {
        vencidos.push({
          ventana: v, fecha: v.pago, beneficio: v.beneficio,
          monto: redondear(debe.reduce((a, x) => a + x.monto, 0)), personas: debe,
        });
      }
    } else {
      const acumulan = conDerecho
        .map((p) => ({ persona_id: p.persona_id, nombre: p.nombre, monto: saldoVentana(p, v.clave) }))
        .filter((x) => x.monto > EPS);
      proximos.push({
        ventana: v, fecha: v.pago, beneficio: v.beneficio,
        monto: redondear(acumulan.reduce((a, x) => a + x.monto, 0)), personas: acumulan,
      });
    }
  }

  // Del 16 al 31 de diciembre ya pasaron las cuatro ventanas del año: el
  // próximo pago es del año siguiente y la base todavía no lo calcula.
  const prox = proximoDesembolso(d);
  if (!proximos.length && prox && !prox.fiable) {
    proximos.push({ ventana: null, fecha: prox.fecha, beneficio: prox.beneficio, monto: null, personas: [] });
  }

  vencidos.sort((a, b) => (a.fecha < b.fecha ? -1 : 1));
  proximos.sort((a, b) => (a.fecha < b.fecha ? -1 : 1));
  const vacaciones = redondear(conDerecho.reduce((a, p) => a + Math.max(p.vac, 0), 0));
  return { vencidos, proximos, vacaciones };
}

// ── Filtros ──────────────────────────────────────────────────────────────────

export interface FiltrosProvisiones {
  texto: string;
  sede: string;
  estado: EstadoFila | "";
}

export const FILTROS_VACIOS: FiltrosProvisiones = { texto: "", sede: "", estado: "" };

const sinTildes = (s: string) => s.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase();

export function filtrar(personas: ProvPersona[], d: ProvData, f: FiltrosProvisiones): ProvPersona[] {
  const texto = sinTildes(f.texto.trim());
  return personas.filter(
    (p) =>
      (!texto || sinTildes(p.nombre).includes(texto)) &&
      (!f.sede || p.sede === f.sede) &&
      (!f.estado || estadosFila(p, d).includes(f.estado)),
  );
}

export const hayFiltros = (f: FiltrosProvisiones) => Boolean(f.texto.trim() || f.sede || f.estado);

// ── Pagos del libro, por ventana ─────────────────────────────────────────────

// Las siete ventanas que admite el libro: las cinco de siempre y las dos que
// agregó la 0467 para modalidad formativa.
export type VentanaLibro =
  | VentanaClave
  | "vacaciones"
  | "subvencion_semestral"
  | "descanso_practicante";

export interface PagosDeVentana {
  /** Lo que la base da por cobrado. */
  total: number;
  /** Las filas del libro de esa ventana y ese año, de la más vieja a la más nueva. */
  filas: DesembolsoLibro[];
  /**
   * Lo cobrado que el libro no explica. Sale de un movimiento de planilla: la
   * base, cuando lo encuentra, da por pagada la ventana COMPLETA (0123).
   */
  porPlanilla: number;
}

/**
 * `totalConocido` lo pasan las ventanas que NO viven en el jsonb de
 * fn_provisiones —las dos de modalidad formativa (0467)—, cuyo monto cobrado
 * viene de `fn_subvenciones_practicante`. Para las otras cinco se deduce aquí.
 */
export function pagosDe(
  p: ProvPersona,
  ventana: VentanaLibro,
  anio: number,
  libro: DesembolsoLibro[],
  totalConocido?: number,
): PagosDeVentana {
  const total =
    totalConocido ??
    (ventana === "vacaciones"
      ? (p.vac_monto_pagado ?? 0)
      : ventana === "subvencion_semestral" || ventana === "descanso_practicante"
        ? 0
        : pagadoVentana(p, ventana));
  const filas = libro
    .filter((l) => l.persona_id === p.persona_id && l.ventana === ventana && l.anio === anio)
    .sort((a, b) => (a.fecha_pago < b.fecha_pago ? -1 : 1));
  const enLibro = filas.reduce((a, l) => a + Number(l.monto), 0);
  return { total, filas, porPlanilla: redondear(Math.max(total - enLibro, 0)) };
}

export const ETIQUETA_ORIGEN: Record<string, string> = {
  plame: "PLAME",
  transferencia: "Transferencia",
  otro: "Otro",
};

// ── CSV ──────────────────────────────────────────────────────────────────────

/**
 * Las 18 columnas que el CSV ya tenía, EN EL MISMO ORDEN Y CON LOS MISMOS
 * VALORES. El contador trabaja con este archivo: cambiarle una columna de
 * sitio o de significado le rompe la plantilla sin que nada avise.
 *
 * Eso incluye `proximo_pago_monto`, que sigue siendo el saldo de la ventana
 * sin el 9 % —como siempre fue—. El monto con el 9 % se ve en la pantalla.
 */
export const COLUMNAS_CSV_ANTERIORES = [
  "nombre",
  "sede",
  "fecha_ingreso",
  "grati_julio_ene_jun",
  "grati_diciembre_jul_dic",
  "grati_total",
  "bonificacion_extraordinaria",
  "cts_mayo_nov_abr",
  "cts_noviembre_may_oct",
  "cts_total",
  "vacaciones",
  "vacaciones_dias",
  "proximo_aniversario",
  "gran_total",
  "proximo_pago_monto",
  "proximo_pago_fecha",
  "sin_tramo_salario",
  "dias_sin_salario",
] as const;

/**
 * El CSV cubre las cinco ventanas que calcula `fn_provisiones`, no las siete
 * del libro: las dos de modalidad formativa (0467) salen de otra función y no
 * tienen columna aquí. Tipo propio para que agregar una ventana al libro no
 * obligue a inventarle una columna al archivo del contador.
 */
type VentanaCsv = VentanaClave | "vacaciones";

const PREFIJO_CSV: Record<VentanaCsv, string> = {
  grati_s1: "grati_julio",
  grati_s2: "grati_diciembre",
  cts_may: "cts_mayo",
  cts_nov: "cts_noviembre",
  vacaciones: "vacaciones",
};
const VENTANAS_LIBRO: VentanaCsv[] = ["grati_s1", "grati_s2", "cts_may", "cts_nov", "vacaciones"];

/** Las columnas nuevas, siempre DESPUÉS de las anteriores. */
export const COLUMNAS_CSV_NUEVAS = [
  "fecha_corte",
  "tipo_vinculo",
  "estado",
  "bonificacion_julio",
  "bonificacion_diciembre",
  ...VENTANAS_LIBRO.flatMap((v) => [
    `${PREFIJO_CSV[v]}_pagado`,
    `${PREFIJO_CSV[v]}_fecha_pago`,
    `${PREFIJO_CSV[v]}_via`,
  ]),
];

export const COLUMNAS_CSV = [...COLUMNAS_CSV_ANTERIORES, ...COLUMNAS_CSV_NUEVAS];

/**
 * `libro` en null significa que no se pudo leer. Entonces las columnas de
 * fecha y vía dicen «no disponible» y NO quedan vacías: una celda vacía se lee
 * como «no hubo pago», que es justo lo que no sabemos.
 */
export function filasCsv(d: ProvData, personas: ProvPersona[], libro: DesembolsoLibro[] | null) {
  const ref = d.proximo?.ref ?? null;
  const anio = Number(anioDe(d.as_of));
  return personas.map((p) => {
    const fila: Record<string, unknown> = {
      nombre: p.nombre,
      sede: p.sede,
      fecha_ingreso: p.fecha_ingreso,
      grati_julio_ene_jun: p.grati_s1,
      grati_diciembre_jul_dic: p.grati_s2,
      grati_total: p.grati_total,
      bonificacion_extraordinaria: p.be_total,
      cts_mayo_nov_abr: p.cts_may,
      cts_noviembre_may_oct: p.cts_nov,
      cts_total: p.cts_total,
      vacaciones: p.vac,
      vacaciones_dias: p.vac_dias,
      proximo_aniversario: p.proximo_aniversario,
      gran_total: p.gran_total,
      proximo_pago_monto: ref ? p[ref] : "",
      proximo_pago_fecha: d.proximo?.fecha ?? "",
      sin_tramo_salario: p.sin_salario_vigente ? "sí" : "",
      dias_sin_salario: (p.dias_sin_salario ?? 0) > 0 ? p.dias_sin_salario : "",

      fecha_corte: d.as_of,
      tipo_vinculo: p.tipo_vinculo ?? "",
      estado: estadosFila(p, d).map((e) => ETIQUETA_ESTADO_FILA[e]).join(" / "),
      bonificacion_julio: p.be_s1 ?? "",
      bonificacion_diciembre: p.be_s2 ?? "",
    };
    for (const v of VENTANAS_LIBRO) {
      const pre = PREFIJO_CSV[v];
      const pagos = libro ? pagosDe(p, v, anio, libro) : null;
      const total = v === "vacaciones" ? (p.vac_monto_pagado ?? 0) : pagadoVentana(p, v);
      fila[`${pre}_pagado`] = total > 0 ? total : "";
      if (total <= 0) {
        fila[`${pre}_fecha_pago`] = "";
        fila[`${pre}_via`] = "";
      } else if (!pagos) {
        fila[`${pre}_fecha_pago`] = "no disponible";
        fila[`${pre}_via`] = "no disponible";
      } else {
        const vias = [...new Set(pagos.filas.map((l) => ETIQUETA_ORIGEN[l.origen] ?? l.origen))];
        if (pagos.porPlanilla > 0) vias.push("Planilla");
        fila[`${pre}_fecha_pago`] = pagos.filas.map((l) => l.fecha_pago).join(" · ");
        fila[`${pre}_via`] = vias.join(" + ");
      }
    }
    return fila;
  });
}

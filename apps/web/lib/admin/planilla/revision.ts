// Qué hay que mirar antes de pagar un periodo — dicho UNA vez.
//
// QUÉ PROMETE. Dadas TODAS las filas del periodo (nunca las filtradas), el
// estado de sus grupos y lo que ya se sabe de cada persona, responde: cuánto
// suma cada grupo, cómo se arma el total de cada persona, qué frena el pago,
// qué conviene revisar, qué periodos siguen pendientes y en qué punto va este.
//
// QUÉ ASUME. Las filas tienen la forma de `fn_proyeccion_periodo`. Un
// `tipo_vinculo` ausente o desconocido cae en «planilla», el mismo defecto que
// usa `fn_planilla_congelar` en la base.
//
// QUÉ NO HACE. No decide nada que la base no decida. Lo único que se llama
// «bloquea» son los dos frenos que ya existen en `fn_planilla_congelar`
// (0243/0244 y 0284/0326), con su misma condición: la pantalla los adelanta
// para que el error se lea como una instrucción y no como una falla, pero quien
// frena de verdad sigue siendo la base. Todo lo demás es «revisar» o
// «informa» — salvo que la persona ya cesó dentro del periodo: ahí «revisar»
// se apaga, porque no queda a quién corregirle un dato (ver «frenos y avisos»
// en planilla-revision.test.ts, 2026-10-28).
//
// Por qué existe (auditoría 2026-09-15, hallazgo C2): hasta hoy la pantalla
// contaba, sumaba y habilitaba el botón de pago sobre las filas FILTRADAS,
// mientras la base congelaba al grupo completo. Separar «lo que se ve» de «lo
// que es el periodo» empieza por que ninguna cuenta de acá reciba un filtro.

import { TIPOS_VINCULO, esPrestadorDeServicios, type TipoVinculo } from "@cayla-dynamic/shared";
import { formatSoles } from "@/lib/rangos";
import { diasEntre, fechaCorta } from "./formato";
import type { Fila, GrupoPago, Liquidada, PeriodoInfo } from "./tipos";

// ── Grupos ───────────────────────────────────────────────────────────────────

export function grupoDe(f: Pick<Fila, "tipo_vinculo">): TipoVinculo {
  return TIPOS_VINCULO.includes(f.tipo_vinculo as TipoVinculo) ? (f.tipo_vinculo as TipoVinculo) : "planilla";
}

/**
 * La llave de UNA fila, no de una persona. Alguien que cambió de grupo a mitad
 * del periodo (cesó de RxH y quedó en planilla, o al revés) aparece con DOS
 * filas en el mismo periodo — misma persona, distinto tipo_vinculo, distintos
 * total/descuentos. Un mapa indexado solo por persona_id no puede guardar las
 * dos: la segunda pisa a la primera, y da igual desde cuál de las dos filas
 * se pregunte, siempre se recibe la que quedó guardada al final.
 *
 * Caso real (jul-2026, RxH): así fue como un "Ya le pagué aparte" registrado
 * correctamente en la fila de RxH de una persona no destrababa su pago — el
 * diálogo de cierre seguía leyendo el hallazgo de su OTRA fila (Planilla), que
 * nunca se tocó. Toda estructura que junte hallazgos por persona tiene que
 * usar esta llave, no `persona_id` a secas.
 */
export function claveFila(f: Pick<Fila, "persona_id" | "tipo_vinculo">): string {
  return `${f.persona_id}:${grupoDe(f)}`;
}

/** Siempre las cinco claves, aunque un grupo no tenga a nadie. */
export function agruparPorGrupo(filas: Fila[]): Map<TipoVinculo, Fila[]> {
  const m = new Map<TipoVinculo, Fila[]>(TIPOS_VINCULO.map((g) => [g, [] as Fila[]]));
  for (const f of filas) m.get(grupoDe(f))!.push(f);
  return m;
}

// ── Totales ──────────────────────────────────────────────────────────────────

export interface Totales {
  personas: number;
  horas: number;
  pago_base: number;
  feriados: number;
  asignacion: number;
  /** Movilidad por asistencia y asignación por educación: conceptos propios del
   *  total (0110 / 0120), que la tabla de Planilla muestra en su columna. */
  movilidad: number;
  educacion: number;
  bonos: number;
  descuentos: number;
  /** Lo que se transfiere a las personas. */
  total: number;
  pension: number;
  essalud: number;
  retencion_4ta: number;
  /** El total + pensión (AFP/ONP) + EsSalud + retención de 4ta: lo que sale de
   *  la cuenta de CAYLA. No incluye provisiones, que se pagan después. */
  sale_del_banco: number;
  provision_gratificacion: number;
  provision_cts: number;
  provision_vacaciones: number;
  provision_total: number;
}

export function sumarFilas(filas: Fila[]): Totales {
  const t: Totales = {
    personas: filas.length, horas: 0, pago_base: 0, feriados: 0, asignacion: 0, movilidad: 0, educacion: 0,
    bonos: 0, descuentos: 0,
    total: 0, pension: 0, essalud: 0, retencion_4ta: 0, sale_del_banco: 0,
    provision_gratificacion: 0, provision_cts: 0, provision_vacaciones: 0, provision_total: 0,
  };
  for (const f of filas) {
    t.horas += f.horas_mes;
    t.pago_base += f.pago_base;
    t.feriados += f.monto_feriados;
    t.asignacion += f.asignacion_familiar;
    // Opcionales (`?? 0`) por lo mismo que pensión y EsSalud: una base sin la
    // 0110 o la 0120 pegadas no manda la clave, y `undefined` sumaría «NaN».
    t.movilidad += f.monto_movilidad ?? 0;
    t.educacion += f.monto_educacion ?? 0;
    t.bonos += f.bonos;
    t.descuentos += f.descuentos;
    t.total += f.total;
    // Opcionales (`?? 0`): una base sin la 0110, 0116 o 0245 pegadas no manda la
    // clave, y entonces esta cifra vale lo mismo que el total en vez de «NaN».
    t.pension += f.descuento_afp ?? 0;
    t.essalud += f.aporte_essalud ?? 0;
    t.retencion_4ta += f.retencion_4ta ?? 0;
    t.provision_gratificacion += f.provision_gratificacion;
    t.provision_cts += f.provision_cts;
    t.provision_vacaciones += f.provision_vacaciones;
    t.provision_total += f.provision_total;
  }
  t.sale_del_banco = t.total + t.pension + t.essalud + t.retencion_4ta;
  return t;
}

// ── Cómo se arma el total de una persona ────────────────────────────────────

export interface LineaDesglose {
  clave: string;
  etiqueta: string;
  monto: number;
  signo: 1 | -1;
  /** De dónde sale, en una línea, cuando no es obvio. */
  origen?: string;
}

const redondear = (n: number) => Math.round(n * 100) / 100;

/**
 * Las partidas del total en el MISMO orden y con la MISMA aritmética que el
 * `total` de `fn_planilla_calcular_nucleo` (y que el CHECK `chk_foto_cuadra`):
 *   + pago_base + feriados + plus + asignación + movilidad + educación + bonos
 *   + recargo de sobretiempo + recargo de descanso semanal
 *   − pensión − descuentos − retención de 4ta
 *
 * Devuelve además si las líneas suman el total. Si mañana una migración mete
 * una partida nueva en el total y esta lista no se entera, la persona vería un
 * desglose que no cuadra; `cuadra` convierte ese silencio en un aviso.
 */
export function desgloseDe(f: Fila): { lineas: LineaDesglose[]; diferencia: number; cuadra: boolean } {
  const suma: LineaDesglose[] = [
    {
      clave: "pago_base", etiqueta: "Pago base", monto: f.pago_base, signo: 1,
      origen: f.sueldo_fijo
        ? "Sueldo fijo del periodo"
        : "Horas registradas × salario de su rango (incluye vacaciones y descanso médico pagados)",
    },
    { clave: "feriados", etiqueta: "Feriados", monto: f.monto_feriados, signo: 1 },
    { clave: "plus", etiqueta: "Plus", monto: f.monto_plus, signo: 1 },
    { clave: "asignacion_familiar", etiqueta: "Asignación familiar", monto: f.asignacion_familiar, signo: 1 },
    {
      clave: "movilidad", etiqueta: "Movilidad", monto: f.monto_movilidad ?? 0, signo: 1,
      origen: f.movilidad_diaria ? `${formatSoles(f.movilidad_diaria)} por día trabajado` : undefined,
    },
    {
      clave: "educacion", etiqueta: "Educación", monto: f.monto_educacion ?? 0, signo: 1,
      origen: f.instituciones_educacion ?? undefined,
    },
    { clave: "bonos", etiqueta: "Bonos", monto: f.bonos, signo: 1 },
    {
      clave: "sobretiempo", etiqueta: "Recargo por sobretiempo", monto: f.monto_sobretiempo ?? 0, signo: 1,
      origen: f.horas_sobretiempo ? `${f.horas_sobretiempo} h sobre las 48 semanales` : undefined,
    },
    {
      clave: "descanso_semanal", etiqueta: "Recargo por descanso semanal trabajado",
      monto: f.monto_descanso_semanal ?? 0, signo: 1,
    },
  ];
  const resta: LineaDesglose[] = [
    {
      clave: "pension", etiqueta: "Pensión (AFP / ONP)", monto: f.descuento_afp ?? 0, signo: -1,
      origen: f.regimen_pension && f.tasa_afp ? `${f.regimen_pension} · ${f.tasa_afp} %` : undefined,
    },
    { clave: "descuentos", etiqueta: "Descuentos", monto: f.descuentos, signo: -1 },
    {
      clave: "retencion_4ta", etiqueta: "Retención de 4ta categoría", monto: f.retencion_4ta ?? 0, signo: -1,
      origen: f.retencion_4ta_base ? `8 % sobre ${formatSoles(f.retencion_4ta_base)}` : undefined,
    },
  ];
  const todas = [...suma, ...resta];
  const calculado = todas.reduce((a, l) => a + l.signo * l.monto, 0);
  const diferencia = redondear(f.total - calculado);
  return {
    // El pago base siempre se muestra: un cero ahí es justo lo que hay que ver.
    lineas: todas.filter((l) => l.clave === "pago_base" || Math.abs(l.monto) >= 0.005),
    diferencia,
    cuadra: Math.abs(diferencia) < 0.015,
  };
}

// ── Cese respecto del periodo ────────────────────────────────────────────────

/**
 * «Ya no está» decía el estado de HOY. En julio, alguien que cesó en septiembre
 * salía como «ya no está», y eso no dice nada del periodo que se revisa.
 */
export type Cese =
  | { tipo: "durante" | "antes" | "despues"; fecha: string }
  | { tipo: "sin_fecha" }
  | null;

export function ceseRespectoDelPeriodo(
  estado: string,
  fechaCese: string | null | undefined,
  ini: string,
  fin: string,
): Cese {
  if (fechaCese) {
    if (fechaCese < ini) return { tipo: "antes", fecha: fechaCese };
    if (fechaCese > fin) return estado === "activo" ? null : { tipo: "despues", fecha: fechaCese };
    return { tipo: "durante", fecha: fechaCese };
  }
  return estado === "activo" ? null : { tipo: "sin_fecha" };
}

export function textoCese(c: Cese): string | null {
  if (!c) return null;
  switch (c.tipo) {
    case "durante": return `Cesó el ${fechaCorta(c.fecha)}`;
    case "antes": return `Cesó antes del periodo (${fechaCorta(c.fecha)})`;
    case "despues": return `Cesó después (${fechaCorta(c.fecha)})`;
    case "sin_fecha": return "Inactiva, sin fecha de cese";
  }
}

// ── Hallazgos por persona ────────────────────────────────────────────────────

export type Severidad = "bloquea" | "revisar" | "informa";

export type CodigoHallazgo =
  | "dias_sin_confirmar"
  | "liquidacion_sin_descuento"
  | "sin_salario"
  | "feriado_sin_salario"
  | "sin_horario"
  | "no_marco"
  | "sin_regimen_pension"
  | "retencion_4ta_sin_configurar"
  | "desglose_no_cuadra"
  | "ceso_en_periodo";

export interface Hallazgo {
  codigo: CodigoHallazgo;
  severidad: Severidad;
  texto: string;
  /** Adónde se va a resolverlo, si no se resuelve en esta pantalla. */
  resolverEn?: { etiqueta: string; href: string };
}

/**
 * La liquidación ya pagó parte de este mes: ¿está cubierto aquí? Es la MISMA
 * condición que el freno de `fn_planilla_congelar` desde la 0244 —los
 * descuentos cubren lo que la liquidación pagó de este mes—, no «la fila quedó
 * en cero», que era la de la 0243.
 */
export function liquidacionResuelta(f: Fila, liq: Liquidada): boolean {
  return f.total <= 0 || f.descuentos >= liq.cobro_del_periodo;
}

export function hallazgosDePersona(
  f: Fila,
  ctx: { liquidada?: Liquidada | null; cese?: Cese },
): Hallazgo[] {
  const h: Hallazgo[] = [];

  if (f.dias_pendientes > 0) {
    h.push({
      codigo: "dias_sin_confirmar", severidad: "bloquea",
      texto: `${f.dias_pendientes} ${f.dias_pendientes === 1 ? "día" : "días"} con la salida puesta por el sistema, sin confirmar`,
      resolverEn: { etiqueta: "Correcciones", href: "/admin/correcciones" },
    });
  }
  if (ctx.liquidada && !liquidacionResuelta(f, ctx.liquidada)) {
    const falta = Math.max(0, ctx.liquidada.cobro_del_periodo - f.descuentos);
    h.push({
      codigo: "liquidacion_sin_descuento", severidad: "bloquea",
      texto: `Ya cobró su liquidación el ${fechaCorta(ctx.liquidada.pagada_el)} — falta descontar ${formatSoles(falta)} con «Ya le pagué aparte»`,
    });
  }
  if (f.horas_sin_salario > 0 || f.salario_ref === null) {
    h.push({
      codigo: "sin_salario", severidad: "revisar",
      texto: f.horas_sin_salario > 0
        ? `${f.horas_sin_salario} h sin salario asignado: se pagan S/ 0`
        : "Sin salario asignado",
      resolverEn: { etiqueta: "Equipo", href: "/admin/equipo" },
    });
  }
  if (f.feriados_sin_salario > 0) {
    h.push({
      codigo: "feriado_sin_salario", severidad: "revisar",
      texto: `${f.feriados_sin_salario} feriado(s) sin salario ese día: no se pudo calcular`,
      resolverEn: { etiqueta: "Equipo", href: "/admin/equipo" },
    });
  }
  // Mismas tres situaciones que distinguía `razonDelCero` desde la 0100: de
  // vacaciones es inofensivo y NO es hallazgo; las otras dos sí.
  if (f.total <= 0 && f.horas_mes <= 0 && f.dias_vacaciones <= 0) {
    if (f.dias_laborables === 0) {
      h.push({
        codigo: "sin_horario", severidad: "revisar",
        texto: "Sin horario asignado: el sistema no sabe qué días le tocaba venir",
        resolverEn: { etiqueta: "Horarios", href: "/admin/horarios" },
      });
    } else {
      h.push({
        codigo: "no_marco", severidad: "revisar",
        texto: `No marcó ningún día, y le tocaban ${f.dias_laborables}`,
      });
    }
  }
  // Se excluye a quien por su vínculo no tiene régimen (locadores,
  // practicantes): ahí la ausencia es la regla, no un dato que falte.
  if (f.tasa_es_del_regimen === false && f.tipo_vinculo !== "practicante" && !esPrestadorDeServicios(f.en_planilla)) {
    h.push({
      codigo: "sin_regimen_pension", severidad: "revisar",
      texto: "Sin régimen de pensión: su aporte de este mes quedó en S/ 0",
      resolverEn: { etiqueta: "Datos personales", href: "/admin/datos-personales" },
    });
  }
  if (f.retencion_4ta_sin_configurar) {
    h.push({
      codigo: "retencion_4ta_sin_configurar", severidad: "revisar",
      texto: "Su recibo pasa de S/ 1,500 y no tiene configurada la retención de 4ta",
      resolverEn: { etiqueta: "Equipo", href: "/admin/equipo" },
    });
  }
  const d = desgloseDe(f);
  if (!d.cuadra) {
    h.push({
      codigo: "desglose_no_cuadra", severidad: "revisar",
      texto: `Las partidas no suman el total (diferencia ${formatSoles(d.diferencia)}): avisar antes de pagar`,
    });
  }
  if (ctx.cese && ctx.cese.tipo !== "despues") {
    h.push({ codigo: "ceso_en_periodo", severidad: "informa", texto: textoCese(ctx.cese)! });
  }
  // Quien ya se fue no tiene nada que "resolver": un régimen de pensión sin
  // cargar, un salario sin asignar o un feriado sin tramo dejan de ser una
  // tarea pendiente en cuanto la persona cesó — no hay a quién corregirle el
  // dato. Lo que sí sigue (bloquea, y el propio aviso de cese) se queda:
  // cerrar bien la cuenta de quien se fue importa igual que la de quien sigue.
  if (ctx.cese && ctx.cese.tipo !== "despues") {
    return h.filter((x) => x.severidad !== "revisar");
  }
  return h;
}

export const ORDEN_SEVERIDAD: Record<Severidad, number> = { bloquea: 0, revisar: 1, informa: 2 };

/** Un hallazgo agrupado: qué pasa y a quiénes. */
export interface HallazgoAgrupado {
  codigo: CodigoHallazgo;
  severidad: Severidad;
  // `grupo` es de ESTA fila, no "el grupo de esta persona" — alguien con dos
  // filas en el periodo puede aparecer aquí dos veces, una por cada una.
  personas: { persona_id: string; nombre: string; texto: string; grupo: TipoVinculo }[];
  resolverEn?: { etiqueta: string; href: string };
}

export function agruparHallazgos(porPersona: { fila: Fila; hallazgos: Hallazgo[] }[]): HallazgoAgrupado[] {
  const m = new Map<CodigoHallazgo, HallazgoAgrupado>();
  for (const { fila, hallazgos } of porPersona) {
    for (const x of hallazgos) {
      const g = m.get(x.codigo) ?? { codigo: x.codigo, severidad: x.severidad, personas: [], resolverEn: x.resolverEn };
      g.personas.push({ persona_id: fila.persona_id, nombre: fila.nombre, texto: x.texto, grupo: grupoDe(fila) });
      m.set(x.codigo, g);
    }
  }
  return [...m.values()].sort(
    (a, b) => ORDEN_SEVERIDAD[a.severidad] - ORDEN_SEVERIDAD[b.severidad] || a.codigo.localeCompare(b.codigo),
  );
}

// ── Periodos ─────────────────────────────────────────────────────────────────

/**
 * Los periodos abiertos ANTERIORES a este (terminan antes de que empiece), del
 * más antiguo al más nuevo. Esto no mira «hoy»: al pagar septiembre importa
 * que agosto siga abierto aunque la pregunta se haga en diciembre.
 */
export function periodosAnterioresSinPagar(lista: PeriodoInfo[], actual: PeriodoInfo): PeriodoInfo[] {
  return lista
    .filter((p) => p.id !== actual.id && p.estado !== "pagado" && p.fecha_fin < actual.fecha_ini)
    .sort((a, b) => a.fecha_fin.localeCompare(b.fecha_fin));
}

/** Todos los periodos que ya terminaron y siguen sin pagar, del más antiguo al más nuevo. */
export function periodosVencidosSinPagar(lista: PeriodoInfo[], hoy: string): PeriodoInfo[] {
  return lista
    .filter((p) => p.estado !== "pagado" && p.fecha_fin < hoy)
    .sort((a, b) => a.fecha_fin.localeCompare(b.fecha_fin));
}

/**
 * CAMBIO 2026-09-12 (decisión de Felipe), traída tal cual desde page.tsx: se
 * abre el periodo sin pagar que CONTIENE a hoy; si ninguno lo contiene, el más
 * antiguo sin pagar. Con dos vencidos a la vez, abrir en el más viejo hacía ver
 * «Sin horario asignado» a quien ingresó después de ese periodo.
 */
export function periodoInicialSugerido(lista: PeriodoInfo[], hoy: string): PeriodoInfo | null {
  const deHoy = lista.find((p) => p.estado !== "pagado" && p.fecha_ini <= hoy && hoy <= p.fecha_fin);
  return deHoy ?? periodosVencidosSinPagar(lista, hoy)[0] ?? null;
}

export type Avance =
  | { estado: "por_empezar"; dias: number }
  | { estado: "en_curso"; transcurridos: number; dias: number }
  | { estado: "terminado"; dias: number };

export function avanceDelPeriodo(ini: string, fin: string, hoy: string): Avance {
  const dias = diasEntre(ini, fin);
  if (hoy < ini) return { estado: "por_empezar", dias };
  if (hoy > fin) return { estado: "terminado", dias };
  return { estado: "en_curso", transcurridos: diasEntre(ini, hoy), dias };
}

/**
 * Cómo se lee el estado del periodo a partir de sus grupos. No es un estado
 * nuevo de la base: en la base el periodo es `abierto` o `pagado`, y «pagado
 * en parte» es solo la lectura de que algunos grupos con gente ya se pagaron.
 */
export type LecturaEstado = "pagado" | "pagado_en_parte" | "vencido" | "abierto";

export function lecturaDelEstado(periodo: PeriodoInfo, grupos: GrupoPago[] | null, hoy: string): LecturaEstado {
  if (periodo.estado === "pagado") return "pagado";
  const conGente = (grupos ?? []).filter((g) => g.personas > 0);
  if (conGente.some((g) => g.estado === "pagado")) return "pagado_en_parte";
  return periodo.fecha_fin < hoy ? "vencido" : "abierto";
}

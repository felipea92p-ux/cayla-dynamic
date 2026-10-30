import type { TipoVinculo } from "@cayla-dynamic/shared";

// Forma de los datos que devuelven las funciones de Planilla (fn_periodos,
// fn_proyeccion_periodo, fn_simular_planilla, fn_planilla_variacion…). Salió
// de `admin/planilla/page.tsx` el 2026-09-15: las dos boletas —panel y «Lo
// mío»— y la hoja de boleta importaban estos tipos desde un archivo de
// página. Los comentarios viajaron intactos: documentan de qué migración sale
// cada clave.

// ── Tipos (forma del jsonb de fn_periodos / fn_proyeccion_periodo / fn_simular_planilla) ──
export interface PeriodoInfo {
  id: string;
  fecha_ini: string;
  fecha_fin: string;
  estado: "abierto" | "pagado";
  pagado_at: string | null;
  anio_etiqueta: number;
  mes_etiqueta: number;
}
// Una fila por persona cuya cifra pagada ya no coincide con el cálculo de hoy.
// Sale de fn_planilla_foto_diferencias (0096): el sistema lo DICE, no lo corrige solo.
export interface Desvio {
  persona_id: string;
  nombre: string;
  total_foto: number | null;
  total_ahora: number | null;
  diferencia: number;
}
// ── Qué cambió respecto al mes pasado (0319) ────────────────────────────────
// Sale de `fn_planilla_variacion`. Los dos lados se los pide esa función a
// `fn_proyeccion_periodo`, así que un periodo ya pagado se compara por lo que se
// PAGÓ —su foto congelada— y no por lo que se recalcularía hoy.
//
// Las etiquetas viven aquí y no en `packages/shared/labels.ts` a propósito: no
// son un catálogo de la base que otra pantalla pueda necesitar, son los códigos
// que devuelve esa función y solo los pinta este panel. Su fuente de verdad es
// la migración 0319; si aparece un aviso nuevo, se agrega ahí y aquí.
export type AvisoVariacion =
  | "salio"
  | "entro"
  | "cobra_cero"
  | "empieza_a_cobrar"
  | "trabajo_y_no_cobra"
  | "salto"
  | "cobra_igual_trabajo_menos";

export type ExplicaVariacion = "ceso" | "ingreso" | "sueldo_cambio" | "mas_ausencias" | "menos_ausencias";


export interface FilaVariacion {
  persona_id: string;
  nombre: string;
  sede: string | null;
  total_actual: number;
  total_previo: number;
  delta: number;
  delta_pct: number | null;
  horas_actual: number;
  horas_previo: number;
  ausencias_actual: number;
  ausencias_previo: number;
  avisos: AvisoVariacion[];
  explica: ExplicaVariacion[];
}

export interface Variacion {
  sin_previo: boolean;
  periodo_desde: string;
  periodo_hasta: string;
  periodo_dias?: number;
  previo_desde?: string;
  previo_hasta?: string;
  previo_dias?: number;
  previo_estado?: "abierto" | "pagado";
  previo_fuente?: string;
  periodos_de_distinto_largo?: boolean;
  resumen: {
    personas_actual: number;
    personas_previo: number;
    entraron?: number;
    salieron?: number;
    total_actual?: number;
    total_previo?: number;
    total_delta?: number;
    horas_actual?: number;
    horas_previo?: number;
  };
  filas: FilaVariacion[];
}

export interface Feriado {
  fecha: string;
  nombre: string;
}
export interface FeriadoDetalle {
  fecha: string;
  horas_trabajadas: number;
  proporcional_horas: number;
  antes_ingreso: boolean;
  /** Desde la 0505 · el feriado cae después de su cese: no corresponde, igual
   *  que uno anterior al ingreso. Opcional porque sin la 0505 pegada no llega. */
  despues_cese?: boolean;
  /** Desde la 0276 · lo que ese feriado devengó, SIN redondear. Quien lo
   *  muestre redondea: la boleta lo mete crudo en la base de provisión. */
  monto?: number;
}
export interface Movimiento {
  id: string;
  tipo: "bono" | "descuento";
  concepto: string;
  monto: number;
}
export interface Fila {
  persona_id: string;
  nombre: string;
  sede: string;
  estado: string;
  rango: string | null;
  salario_ref: number | null;
  // Si NO está en planilla —locador por honorarios— la fila no muestra la
  // categoría de la escala: la escala es de trabajadores, y decir que ocupa una
  // es parte de lo que desnaturaliza una locación de servicios (0182). El dato
  // de `rango` se conserva porque es de donde sale cuánto se le transfiere.
  en_planilla: boolean | null;
  // Ya viaja en el JSON de fn_planilla_calcular desde la 0117; se expone acá
  // (0322) para que la boleta pueda distinguir a un practicante de un RxH —
  // los dos tienen en_planilla=false, pero no son el mismo documento.
  tipo_vinculo: string | null;
  horas_mes: number;
  dias_trabajados: number;
  dias_pendientes: number;
  horas_sin_salario: number;
  dias_vacaciones: number;   // 0100 — por qué está en cero
  dias_laborables: number;   // 0100 — 0 = no tiene horario asignado
  pago_base: number;
  // Desglose legal del pago base (0104, recalculado por la 0105). NULL cuando
  // falta la básica legal o la puntuación del mes: entonces la boleta no parte
  // la fila. basica_legal_prop + complemento_variable === pago_base, siempre.
  basica_legal_prop: number | null;
  complemento_variable: number | null;
  // 0105 — puntuación de rendimiento del mes (0–100) y la etiqueta que se eligió
  // para el concepto ESE mes. La etiqueta es un dato, no código: puede cambiar de
  // un periodo a otro y cada pago guarda con qué nombre se emitió.
  // El defecto es 100, y al 100% la fórmula devuelve el salario del rango: por eso
  // activar esto no le mueve el sueldo a nadie. rendimiento_por_defecto distingue
  // «nadie lo ha puntuado» de «alguien escribió 100».
  sueldo_base_legal: number | null;
  rendimiento_pct: number | null;
  rendimiento_por_defecto: boolean | null;
  complemento_etiqueta: string | null;
  fecha_ingreso: string;
  feriados_detalle: FeriadoDetalle[];
  monto_feriados: number;
  feriados_no_corresponde: number;
  objetivos_cumplidos: number | null;
  objetivos_total: number | null;
  monto_plus: number;
  bajo_desempeno: boolean;
  feriados_sin_salario: number;
  con_hijos: boolean;
  asignacion_familiar: number;
  // Los dos términos que la 0110 metió en el 'total' y que hasta el 2026-07-31
  // NO estaban declarados aquí ni impresos en la boleta. Eso hacía que el total
  // no cuadrara con sus propias líneas: la boleta de Danixa sumaba S/76.67 en lo
  // visible y remataba en S/71.84, con S/4.83 de descuento de pensión aplicados
  // y sin una línea que los nombrara. Son opcionales porque una base sin la 0110
  // pegada no los devuelve, y `undefined > 0` es false, así que la boleta
  // simplemente no dibuja la fila en vez de escribir «S/ NaN».
  monto_movilidad?: number;
  movilidad_diaria?: number;
  // La 0120 metió la educación en el 'total' del SQL y la boleta no la imprimía:
  // el mismo agujero que la 0110 abrió con la movilidad, y con la misma
  // consecuencia — un dinero que se paga y que la persona no puede explicar.
  // `instituciones_educacion` viene de la 0150 y trae los nombres separados por
  // ' · ' cuando hay más de un comprobante vigente.
  monto_educacion?: number;
  instituciones_educacion?: string | null;
  // Los dos de la 0236, con los que la boleta explica un cero en vez de borrar la
  // línea. Opcionales y leídos con `?? false`: una base sin la 0236 pegada no los
  // devuelve, y entonces la boleta se comporta como antes — no dibuja la fila —
  // en vez de escribir una explicación falsa.
  educacion_registrada?: boolean;
  educacion_sin_comprobante?: boolean;
  descuento_afp?: number;
  tasa_afp?: number;
  regimen_pension?: string | null;
  tasa_es_del_regimen?: boolean;
  // El aporte de EsSalud que paga CAYLA (0116). NO se descuenta al trabajador y no
  // entra en 'total': el 9% es íntegramente de cargo del empleador (Ley 26790 art. 6).
  // 'essalud_es_piso' es true cuando la persona devengó MENOS que la RMV y el aporte
  // salió del piso legal, no de su sueldo — sin ese dato la cifra no se puede explicar
  // (alguien que ganó S/36.96 genera S/101.70 de EsSalud).
  base_essalud?: number;
  aporte_essalud?: number;
  essalud_tasa?: number;
  essalud_es_piso?: boolean;
  bonos: number;
  descuentos: number;
  movimientos: Movimiento[];
  provision_gratificacion: number;
  // Ley 30334: el 9 % que ya no va a EsSalud y se le entrega a la persona. Llega
  // opcional porque una base sin la 0134 aplicada no manda la clave, y la boleta
  // tiene que seguir saliendo igual que antes en vez de imprimir «NaN».
  provision_bonif_extraordinaria?: number;
  provision_cts: number;
  provision_vacaciones: number;
  provision_total: number;
  // Sobretiempo (0185): SOLO el recargo del 25 % / 35 %, no la hora completa —
  // las horas ya están dentro de pago_base. `horas_sobretiempo` son las horas
  // que excedieron las 48 semanales; `monto_sobretiempo` es lo que cuesta el
  // recargo sobre ellas. Opcionales porque una base sin la 0185 pegada no manda
  // las claves, y la boleta tiene que seguir saliendo igual que antes.
  monto_sobretiempo?: number;
  horas_sobretiempo?: number;
  sobretiempo_desde?: string | null;
  sobretiempo_hasta?: string | null;
  // El mismo recargo de arriba, partido en 25 % y 35 % (0349) — lo pidió el
  // contador para conciliar contra los códigos 0105/0106 de la PLAME.
  // `monto_sobretiempo_25 + monto_sobretiempo_35` siempre suma exacto
  // `monto_sobretiempo`; ver el comentario de la migración para el porqué.
  // Opcionales por lo mismo que el resto: una base sin la 0349 pegada no
  // manda las claves, y la boleta tiene que seguir saliendo igual que antes.
  monto_sobretiempo_25?: number;
  monto_sobretiempo_35?: number;
  horas_sobretiempo_25?: number;
  horas_sobretiempo_35?: number;
  // Descanso semanal trabajado (0280): también SOLO el recargo —el 100 % del
  // art. 3 del D. Leg. 713—, porque las horas de ese día ya están en pago_base.
  // `descanso_semanal_dias` es cuántas veces se cerró un ciclo de siete días
  // sin descansar, no cuántos días se trabajó. Opcionales por lo mismo que las
  // de la 0185: una base sin la 0280 pegada no manda las claves y la boleta
  // tiene que seguir saliendo igual que antes.
  monto_descanso_semanal?: number;
  descanso_semanal_dias?: number;
  descanso_semanal_desde?: string | null;
  descanso_semanal_hasta?: string | null;
  // Retención de renta de cuarta categoría (0245), solo para quien cobra por
  // recibo por honorarios. `retencion_4ta_base` es el importe por el que tiene
  // que emitir su recibo —NO el total, que ya es el neto— y por eso viaja: sin
  // él la boleta no puede decirle a un locador por cuánto facturar.
  // `retencion_4ta_sin_configurar` es el aviso: pasa el tope y nadie eligió modo.
  // Todas opcionales, como las de la 0185 y la 0236: una base sin la 0245 pegada
  // no manda las claves y la pantalla se comporta exactamente como antes.
  // ¿Su pago depende de las horas que registre? (0250). Es de PRESENTACIÓN: no
  // mueve un céntimo — `pago_base` ya se calcula distinto desde la 0047. Viaja
  // para que la boleta pueda distinguir dos locadores que cobran al revés y
  // dejar de ponerles la misma etiqueta.
  sueldo_fijo?: boolean;
  // Los días de descanso médico que asume CAYLA (0254). Son de PRESENTACIÓN:
  // el importe YA está dentro de `pago_base` —igual que los de vacaciones desde
  // la 0177— y no se suma otra vez en ningún sitio. Viajan para que la boleta
  // pueda sacarlos a su propia línea, porque si no, la de básica promete «por
  // tus horas del periodo» sobre un importe que incluye días que no se
  // trabajaron. Opcionales: sin la 0254 pegada, la boleta se comporta como antes.
  monto_descanso_medico?: number;
  dias_descanso_medico_pagados?: number;
  retencion_4ta?: number;
  retencion_4ta_base?: number;
  retencion_4ta_modo?: string | null;
  retencion_4ta_constancia_hasta?: string | null;
  retencion_4ta_sin_configurar?: boolean;
  total: number; // ya incluye + asignación + movilidad + sobretiempo − pensión + bonos − descuentos − retención de 4ta
}
export interface FactoresProvision {
  gratificacion: number;
  cts: number;
  vacaciones: number;
}
// Lo que una practicante lleva devengado de los dos beneficios propios de la
// Ley 28518 art. 42 — media subvención por cada 6 meses continuos, y 15 días
// de descanso al cumplir 12 (0465/0467). VIVEN FUERA de `Fila` a propósito:
// no salen de fn_proyeccion_periodo/fn_planilla_calcular_persona (el cálculo
// del pago del periodo) sino de una función APARTE, `fn_subvenciones_
// practicante` (admin) / `fn_mis_subvenciones_practicante` (autoservicio,
// 0485) — mezclarlo en `Fila` sugeriría que es parte del mismo cálculo, y no
// lo es: son dos relojes distintos que nunca se suman entre sí.
export interface SubvencionPracticante {
  sinSubvencion: boolean;
  mediaSubSaldo: number;
  semestreHasta: string;
  descansoSaldo: number;
  descansoGanado: boolean;
  descansoCumple: string;
}
// El estado de pago de UN grupo (tipo_vinculo) dentro del periodo — 0323.
// Sale de fn_proyeccion_periodo (clave 'grupos'), siempre las 5 aunque un
// grupo no tenga a nadie ese periodo: `personas` en 0 es la señal de que la
// pestaña está vacía, no que falte el dato.
export interface GrupoPago {
  grupo: TipoVinculo;
  estado: "abierto" | "pagado";
  pagado_at: string | null;
  pagado_por_nombre: string | null;
  personas: number;
}
// El checklist personal de Felipe para ir pagando persona por persona durante
// el mes — NUNCA el pago oficial del grupo (GrupoPago, arriba). Sale de
// fn_pago_personas_estado (0562): el último evento de cada persona en este
// periodo. `monto` es el que se congeló AL MARCAR, no el de hoy — la pantalla
// compara los dos para avisar si una corrección lo movió después.
export interface EstadoPagoPersona {
  persona_id: string;
  grupo: TipoVinculo;
  marcado: boolean;
  monto: number;
  marcado_at: string | null;
  marcado_por_nombre: string | null;
}
// Un evento de la bitácora completa de una persona (planilla_pago_persona_eventos,
// 0562) — para el historial que se ve al abrir «Ver historial» en su check.
export interface EventoPagoPersona {
  tipo: "marcado" | "desmarcado";
  monto: number;
  motivo: string | null;
  creado_at: string;
  creado_por_nombre: string | null;
}
export interface Proyeccion {
  periodo_id?: string;
  estado?: "abierto" | "pagado";
  pagado_at?: string | null;
  simulacion: boolean;
  fecha_ini: string;
  fecha_fin: string;
  anio_etiqueta: number;
  mes_etiqueta: number;
  dias: number;
  base_horas: number;
  feriados: Feriado[];
  factores_provision: FactoresProvision;
  asignacion_monto: number;
  filas: Fila[];
}
// Grati/CTS que toca en el periodo, calculado por fn_grati_cts_periodo.
// CAMBIO 0346 — beConcepto y el campo be de porPersona: el 9% de Ley 30334,
// del mismo monto de grati, para registrarse como movimiento aparte.
export interface GratiCts {
  gratiAplica: boolean;
  gratiConcepto: string;
  ctsAplica: boolean;
  ctsConcepto: string;
  beConcepto: string;
  porPersona: Record<string, { grati: number; cts: number; be: number }>;
}

// Una liquidación YA PAGADA de alguien que cesó dentro de este periodo, tal
// como la devuelve fn_liquidaciones_del_periodo (0210).
//
// `cobro_del_periodo` es la parte que SE SOLAPA con la planilla: el sueldo del
// mes que esa liquidación ya cubrió. El resto del total son las truncas, que la
// planilla no calcula y por tanto no duplica.
export interface Liquidada {
  cobro_del_periodo: number;
  total_liquidacion: number;
  pagada_el: string;
  fecha_cese: string;
}

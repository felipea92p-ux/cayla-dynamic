// ============================================================================
// importar-polizas.ts — de lo que dice el papel a pólizas listas para registrar
// ============================================================================
// QUÉ PROMETE
//   Las reglas de la pantalla «Leer PDF de póliza»: cómo se arma cada tarjeta a partir de lo que el
//   lector entendió (`leer-poliza.ts`), qué seguro proponer, y qué le falta o le sobra a una tarjeta
//   antes de poder registrarla. Funciones puras, sin React ni Supabase: se prueban con vitest
//   (`tests/importar-polizas.test.ts`).
//
// QUÉ NO DECIDE
//   Nada de lo que decide la base. Aquí solo se ADELANTAN sus rechazos (la persona no está en ese seguro,
//   la póliza se cruza con otra) para que DO los vea en la tarjeta y no al final del lote: la base los vuelve
//   a comprobar al registrar, y su mensaje se muestra tal cual.
//
// UNA TARJETA ES UNA PROPUESTA
//   Nada de lo leído se registra sin que DO lo mire. Una tarjeta nace SELECCIONADA solo si el papel trajo
//   número, vigencia y prima, y si la persona se pudo proponer con claridad; si no, nace sin seleccionar y
//   dice qué falta.
//
// LAS FECHAS NACEN CON VALOR (CLAUDE.md, regla del 2026-08-26: un campo de fecha cuyo vacío bloquea el envío
//   no puede arrancar en «»). Si el papel no trae una fecha, la tarjeta nace con «hoy» y «tres meses después»
//   —lo mismo que el formulario— y con el aviso del lector, y sin seleccionar.
// ============================================================================
import type { PolizaLeida } from "./leer-poliza";
import { emparejarPersona } from "./leer-poliza";
import { isoADiaMesAnio } from "./planilla/formato";
import { fechasSospechosas, numeroDeTexto, polizaQueSeCruza, sumarMeses, type Poliza, type TipoSeguro } from "./seguros";

/** Lo mínimo que hace falta saber de una persona para proponérsela a un papel. */
export interface PersonaParaEmparejar { id: string; nombre: string; tipoPrincipal: string | null }

/** Qué pasó con el PDF de una póliza ya registrada: se guardó, no se pidió guardarlo, o falló (la póliza sí quedó). */
export type PdfDeTarjeta = "guardado" | "omitido" | { error: string };

export type EstadoDeTarjeta =
  | { tipo: "pendiente" }
  | { tipo: "registrada"; pdf: PdfDeTarjeta }
  | { tipo: "error"; mensaje: string };

/** Una póliza leída de un PDF, con lo que DO puede corregir antes de registrarla. */
export interface TarjetaDePoliza<A extends { name: string } = File> {
  /** Único dentro de la pantalla: qué archivo y cuál póliza de él. */
  clave: string;
  archivo: A;
  leida: PolizaLeida;
  incluir: boolean;
  personaId: string;
  numero: string;
  desde: string;
  hasta: string;
  /** Texto del campo: «179.97». */
  prima: string;
  primaVence: string;
  aseguradora: string;
  nota: string;
  estado: EstadoDeTarjeta;
}

/** La tarjeta de la póliza `n` que se leyó del archivo número `posicion` de los que se eligieron. */
export function tarjetaDeLectura<A extends { name: string }>(
  archivo: A,
  posicion: number,
  n: number,
  leida: PolizaLeida,
  personas: readonly PersonaParaEmparejar[],
  hoy: string,
): TarjetaDePoliza<A> {
  const sugerida = leida.asegurado ? emparejarPersona(leida.asegurado.nombre, personas)?.persona.id ?? "" : "";
  const desde = leida.desde ?? hoy;
  const hasta = leida.hasta ?? sumarMeses(desde, 3);
  const completa = leida.numero.trim().length >= 3 && leida.desde !== null && leida.hasta !== null && leida.prima !== null;
  return {
    clave: `${posicion}:${n}`,
    archivo,
    leida,
    incluir: completa && sugerida !== "",
    personaId: sugerida,
    numero: leida.numero,
    desde,
    hasta,
    prima: leida.prima === null ? "" : String(leida.prima),
    primaVence: leida.primaVenceEl ?? "",
    aseguradora: leida.aseguradora ?? "",
    nota: leida.emitidaEl ? `Emitida el ${isoADiaMesAnio(leida.emitidaEl)}` : "",
    estado: { tipo: "pendiente" },
  };
}

/**
 * El seguro al que probablemente van las tarjetas: el seguro principal de las personas propuestas, si todas
 * comparten UNO que lleva póliza (FOLA para cuatro practicantes). Si no hay acuerdo —o son de planilla, cuyo
 * seguro no lleva póliza—, no se adivina: lo elige DO.
 */
export function productoSugerido(
  tarjetas: readonly Pick<TarjetaDePoliza<{ name: string }>, "personaId">[],
  personas: readonly PersonaParaEmparejar[],
  tipos: readonly Pick<TipoSeguro, "clave" | "activo" | "con_poliza">[],
): string {
  const claves = new Set<string>();
  for (const t of tarjetas) {
    const p = personas.find((x) => x.id === t.personaId);
    if (p?.tipoPrincipal) claves.add(p.tipoPrincipal);
  }
  if (claves.size !== 1) return "";
  const [clave] = [...claves];
  const tipo = tipos.find((x) => x.clave === clave);
  return tipo && tipo.activo && tipo.con_poliza ? clave : "";
}

/**
 * ¿Esta persona ya tiene registrada ESTA póliza? Mismo seguro, mismo número y mismo día de inicio: es volver a
 * leer un PDF que ya se registró, y se deja fuera sin culpar a nadie.
 */
export function yaRegistrada(
  t: Pick<TarjetaDePoliza<{ name: string }>, "personaId" | "numero" | "desde">,
  producto: string,
  polizas: readonly Pick<Poliza, "persona_id" | "producto" | "numero_poliza" | "vigente_desde">[],
): boolean {
  if (!t.personaId || !producto) return false;
  return polizas.some((z) => z.persona_id === t.personaId && z.producto === producto
    && z.numero_poliza.trim().toLowerCase() === t.numero.trim().toLowerCase() && z.vigente_desde === t.desde);
}

export interface ContextoDeTarjeta {
  /** Hoy (Lima): una vigencia que termina a más de diez años de hoy es un año mal tecleado. */
  hoy: string;
  producto: string;
  tipos: readonly Pick<TipoSeguro, "clave" | "nombre" | "principal">[];
  personas: readonly PersonaParaEmparejar[];
  polizas: readonly Pick<Poliza, "persona_id" | "producto" | "vigente_desde" | "vigente_hasta">[];
  /** Las demás tarjetas del lote: dos de la misma persona que se cruzan se detendrían una a la otra. */
  lote: readonly Pick<TarjetaDePoliza<{ name: string }>, "clave" | "incluir" | "personaId" | "desde" | "hasta" | "estado">[];
}

/**
 * Lo que impide registrar esta tarjeta, con el motivo escrito para leerse. Vacío = se puede. Son los mismos
 * rechazos que el formulario y la base (campos obligatorios, la persona tiene que estar en ese seguro, la póliza
 * no puede cruzarse con otra de la misma persona).
 */
export function erroresDeTarjeta(t: TarjetaDePoliza<{ name: string }>, ctx: ContextoDeTarjeta): string[] {
  const e: string[] = [];
  const persona = ctx.personas.find((p) => p.id === t.personaId);
  const tipo = ctx.tipos.find((x) => x.clave === ctx.producto);

  if (!t.personaId) e.push("Elige a quién asegura.");
  else if (tipo?.principal && persona && persona.tipoPrincipal !== ctx.producto) {
    e.push(`Su seguro hoy es otro: no se le registra una póliza de ${tipo.nombre}. Si debe cambiar, cámbiale el seguro primero.`);
  }
  if (t.numero.trim().length < 3) e.push("Escribe el número de la póliza.");
  if (!t.desde || !t.hasta) e.push("Faltan las fechas de la vigencia.");
  else if (t.hasta <= t.desde) e.push("La vigencia tiene que terminar después de empezar.");
  // Lo mismo que rechaza la base: un año mal tecleado no es una póliza (y un PDF raro puede traerlo).
  const sospechas = fechasSospechosas({ desde: t.desde, hasta: t.hasta, primaVence: t.primaVence }, ctx.hoy);
  if (sospechas.vigencia) e.push(sospechas.vigencia);
  if (sospechas.primaVence) e.push(sospechas.primaVence);
  const prima = numeroDeTexto(t.prima);
  if (t.prima.trim() === "") e.push("Escribe la prima total (con IGV).");
  else if (prima === null || prima < 0) e.push("La prima tiene que ser un monto, 0 o más.");
  if (t.aseguradora.trim().length < 2) e.push("Escribe la aseguradora.");

  if (t.personaId && ctx.producto && t.desde && t.hasta && t.hasta > t.desde) {
    const cruce = polizaQueSeCruza(ctx.polizas, t.personaId, ctx.producto, t.desde, t.hasta);
    if (cruce) {
      e.push(`Ya tiene una póliza de este seguro del ${isoADiaMesAnio(cruce.vigente_desde)} al ${isoADiaMesAnio(cruce.vigente_hasta)} que se cruza con esas fechas.`);
    }
    const choca = ctx.lote.find((o) => o.clave !== t.clave && o.incluir && o.estado.tipo !== "registrada" && o.personaId === t.personaId
      && o.desde < t.hasta && t.desde < o.hasta);
    if (choca) e.push("Otra póliza de esta lista es de la misma persona y se cruza con ésta: deja una.");
  }
  return e;
}

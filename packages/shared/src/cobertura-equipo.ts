// Quién cuenta en la cobertura de una sede. Una sola definición, para el
// Dashboard, Turnos y el Reporte de sede.
//
// QUÉ PROMETE
//   Que las tres pantallas respondan igual a «¿esta persona cuenta como
//   personal operativo? ¿y como líder?». Hasta el 2026-09-19 la respuesta estaba
//   escrita en cada pantalla y solo el Dashboard y el Reporte coincidían; Turnos
//   tenía su propia versión, con un `rol === "supervisor_sede"` suelto.
//
// LA REGLA
//   OPERATIVA  = su área es operativa  Y  no está de prueba.
//   LÍDER      = rol de encargada  O  la marca `es_encargada_piso` (0040)
//                O  (es administrador  Y  la sede es de tipo `central`).
//
// POR QUÉ EL ÁREA MANDA, Y QUIÉN QUEDA FUERA (2026-10-20, decidido por Felipe)
//   Cuenta quien trabaja en un área operativa, sea practicante, de planilla o del
//   cargo que sea: el vínculo no decide nada. Lo único que no cuenta, aunque su área
//   sí lo sea, es quien está de PRUEBA (`tipo_vinculo = 'prueba'`, 0536): suma recién
//   cuando deja de estarlo. El sistema se adapta a la gente que hay con un solo mando:
//   qué áreas son operativas se marca en la pantalla de Áreas, no aquí.
//
//   Esto REVIERTE dos reglas anteriores, y conviene saberlo:
//     · 2026-09-19: «el practicante cuenta aunque su área sea de oficina». Ya no: si su
//       área no es operativa, no suma. En OTRU (practicantes en áreas de oficina) hay
//       que marcar esas áreas como operativas en Áreas para que sigan sumando.
//     · 2026-10-19: «quien está de prueba también cuenta». Ya no: la prueba dura tres
//       días trabajados y no hay con qué saber para qué puesto se prueba a alguien.
//
// POR QUÉ EL ADMINISTRADOR SOLO CUENTA EN UNA CENTRAL
//   En CCO manda un administrador y no hay a quién más contar como líder. Pero
//   en una tienda, contar como líder a cualquier administrador que pase
//   declararía «cubierta» una tienda sin encargada: un falso negativo, el error
//   que más cuesta. Se deriva del TIPO de la sede, no de su código, así que una
//   oficina nueva se comporta igual sin tocar esta función. En una tienda o
//   taller, el administrador que de verdad está en piso sigue contando con la
//   marca `es_encargada_piso` (0040).
//
// QUÉ CUENTA CONTRA LA META DE «OPERATIVAS» (`cuentaEnMetaOp`, 2026-10-21, Felipe)
//   En una tienda o un taller, la persona operativa. En una CENTRAL, cualquiera del
//   equipo que esté en la sede (menos quien está de prueba): una oficina no tiene
//   «piso» que cubrir con gente de áreas operativas, y su meta es cuántas personas
//   hay en la sede. Antes, Oficina TRU (cuatro practicantes en áreas de oficina y
//   una líder) decía «meta por revisar» todos los días, porque su meta de 4 se
//   medía contra operativas que ahí no existen — y la única salida era marcar sus
//   áreas como operativas en Áreas, que son un catálogo de toda la empresa.
//   `operativa` NO cambia: sigue diciendo «su área es operativa», y es lo que usa el
//   aviso de «marcó sin horario» (un administrador de Central sin horario es normal).
//   Una pregunta distinta, una respuesta distinta: no se funden en un solo booleano.
//
// QUÉ ASUME
//   `areaOperativa` ya resuelto por quien llama (viene del catálogo de áreas y
//   no es asunto de esta función), y `sedeTipo` tal como está en `sedes.tipo`
//   (0099). Un tipo desconocido se trata como tienda: nunca cuenta de más.
//
// Sin React ni Supabase: se prueba con vitest.

import { esRolAdministrativo, esRolEncargada } from "./permisos";

export interface PersonaParaCobertura {
  rol: string | null | undefined;
  tipoVinculo: string | null | undefined;
  /** La marca `personas.es_encargada_piso` (0040). */
  esEncargadaPiso: boolean;
  /** ¿Su área está marcada como operativa en el catálogo de áreas? */
  areaOperativa: boolean;
}

export interface CuentaEnCobertura {
  /** Su área es operativa y no está de prueba. */
  operativa: boolean;
  /** Cuenta contra la meta que la pantalla llama «operativas»: la persona operativa y, en una central, cualquiera del equipo. */
  cuentaEnMetaOp: boolean;
  lider: boolean;
}

/** ¿La sede es una central (administración, oficina)? Es `sedes.tipo`, no el código: una oficina nueva se comporta igual. */
export function esSedeCentral(sedeTipo: string | null | undefined): boolean {
  return sedeTipo === "central";
}

/** El vínculo de quien está haciendo su prueba (CHECK de `personas.tipo_vinculo`, 0322): no suma cobertura hasta dejar de estarlo. */
export const VINCULO_DE_PRUEBA = "prueba";

/** ¿Esta persona está de prueba? Equipo lo usa para decir por qué no suma. */
export function estaDePrueba(tipoVinculo: string | null | undefined): boolean {
  return tipoVinculo === VINCULO_DE_PRUEBA;
}

export function cuentaEnCobertura(
  p: PersonaParaCobertura,
  sedeTipo: string | null | undefined,
): CuentaEnCobertura {
  const operativa = p.areaOperativa && !estaDePrueba(p.tipoVinculo);
  return {
    operativa,
    cuentaEnMetaOp: operativa || (esSedeCentral(sedeTipo) && !estaDePrueba(p.tipoVinculo)),
    lider:
      esRolEncargada(p.rol) ||
      p.esEncargadaPiso ||
      (esSedeCentral(sedeTipo) && esRolAdministrativo(p.rol)),
  };
}

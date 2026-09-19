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
//   OPERATIVA  = su área es operativa  O  es practicante.
//   LÍDER      = rol de encargada  O  la marca `es_encargada_piso` (0040)
//                O  (es administrador  Y  la sede es de tipo `central`).
//
// POR QUÉ EL PRACTICANTE CUENTA
//   Es una decisión del negocio, no un descuido del sistema (2026-09-19): «practicante»
//   es la etiqueta que pide la ley, pero quien lo es cumple una función en su
//   área y sí tapa el hueco de piso. Antes se decidía solo por el ÁREA de la
//   persona, y los cuatro practicantes de OTRU —áreas de oficina— daban «0 de 4»
//   aunque estuvieran trabajando.
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
  operativa: boolean;
  lider: boolean;
}

export function cuentaEnCobertura(
  p: PersonaParaCobertura,
  sedeTipo: string | null | undefined,
): CuentaEnCobertura {
  return {
    operativa: p.areaOperativa || p.tipoVinculo === "practicante",
    lider:
      esRolEncargada(p.rol) ||
      p.esEncargadaPiso ||
      (sedeTipo === "central" && esRolAdministrativo(p.rol)),
  };
}

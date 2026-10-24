// ============================================================================
// Una misma pregunta que ya está viajando no se vuelve a hacer
// ============================================================================
//
// QUÉ PROMETE
//   Si dos sitios piden lo mismo mientras la primera respuesta todavía no
//   llega, la base recibe UNA consulta y los dos reciben esa respuesta. En
//   cuanto llega, la clave se libera: la siguiente petición va de nuevo a la
//   base. No guarda nada «por si acaso» — no es una caché.
//
// POR QUÉ EXISTE
//   Al abrir /mio, la pantalla pide sus boletas, sus reportes, su bono y su
//   declaración de ruta para dibujar el menú, y a la vez la Bandeja pide LOS
//   MISMOS cuatro para contar sus avisos (`traerBandeja`). Medido el 2026-10-24
//   con un Supabase simulado, la apertura hacía 64 consultas y diez de ellas
//   eran la misma pregunta hecha dos veces. Unificar las dos lecturas en una
//   sola habría cambiado de sitio el cálculo del número —y el comentario de
//   `cargarAvisosDeBandeja` explica por qué eso no se hace—; esto deja cada
//   cálculo donde está y solo evita el viaje repetido.
//
// QUÉ ASUME
//   Que la consulta es de LA PERSONA DE LA SESIÓN y no lleva parámetros que la
//   distingan: la clave es solo el nombre. Dos personas no comparten pestaña,
//   así que dentro de una pestaña la clave identifica la misma pregunta. Una
//   consulta con parámetros (un rango, un id) NO debe pasar por aquí.
//
// SE ROMPE SI
//   Alguien comparte así una escritura. Una lectura que se hace DESPUÉS de
//   guardar algo (`onRecargar`) arranca una consulta nueva porque la anterior
//   ya terminó; pero un `insert` o un `rpc` que modifica jamás se comparte.
// ============================================================================

const enVuelo = new Map<string, Promise<unknown>>();

export function compartirMientrasVuela<T>(clave: string, pedir: () => PromiseLike<T>): Promise<T> {
  const previa = enVuelo.get(clave);
  if (previa) return previa as Promise<T>;
  const nueva: Promise<T> = Promise.resolve(pedir()).finally(() => {
    if (enVuelo.get(clave) === nueva) enVuelo.delete(clave);
  });
  enVuelo.set(clave, nueva);
  return nueva;
}

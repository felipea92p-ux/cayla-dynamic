// Una lectura cara que varias piezas de la misma pestaña necesitan a la vez se hace UNA vez.
//
// QUÉ PROMETE
//   `pedir(frescaDesde)` devuelve una lectura que SALIÓ hacia la base en `frescaDesde` o después. Si ya hay una así
//   guardada, la entrega sin ir a la base; si hay una en vuelo que sirve, se suma a ella; si la que está en vuelo
//   salió antes de lo pedido, todas las que lleguen mientras tanto comparten UNA sola lectura que sale al terminar
//   esa. Nunca hay dos lecturas en vuelo: las lecturas se publican en el orden en que salieron, así que la última
//   publicada es siempre la más nueva.
//
// QUÉ ASUME
//   Que `leer` devuelve el estado de la base en algún instante entre que sale y que vuelve. Por eso la edad de una
//   lectura se cuenta desde que SALIÓ (`pedidaEn`): es lo único que se puede afirmar sin mirar la base. Quien acaba
//   de guardar algo pide con `frescaDesde = ahora` y recibe una lectura que salió después de su guardado.
//
// POR QUÉ EXISTE (2026-11-17)
//   El menú del panel, la pantalla Bandeja, el indicador del Dashboard y Equipo pedían cada uno las mismas ~28
//   consultas de la Bandeja. Medido en producción (pg_stat_statements, 12 al 17 de noviembre): esas consultas eran
//   el 72 % del tiempo de base de Dynamic, y la pantalla Bandeja esperaba de 0,9 a 4,5 s a la más lenta aunque el
//   menú acababa de leer lo mismo. Ver `lib/admin/bandeja-compartida.ts`.
//
// SE ROMPE SI
//   Alguien comparte un lector entre dos personas (la segunda vería lo de la primera hasta la lectura siguiente).
//   El lector no sabe de quién es lo que guarda: la llave la pone quien lo crea.
//
// Sin React, sin Supabase y sin reloj propio: se prueba en `tests/lector-compartido.test.ts`.

/** Lo leído y cuándo salió la lectura hacia la base. */
export interface Lectura<T> {
  valor: T;
  /** El instante en que la lectura SALIÓ. Lo que trae es de ese instante o posterior. */
  pedidaEn: number;
}

export interface LectorCompartido<T> {
  /**
   * Una lectura que salió en `frescaDesde` o después. Sin argumento: «acabo de cambiar algo, quiero verlo».
   * Con `ahora - N`: «me sirve una de hasta N ms».
   */
  pedir(frescaDesde?: number): Promise<Lectura<T>>;
  /** La última lectura publicada, o `null` si todavía no llegó ninguna. No va a la base. */
  ultima(): Lectura<T> | null;
  /** Avisa de cada lectura nueva. Devuelve cómo dejar de escuchar. */
  escuchar(alLlegar: (lectura: Lectura<T>) => void): () => void;
}

export function crearLectorCompartido<T>(leer: () => Promise<T>, ahora: () => number = () => Date.now()): LectorCompartido<T> {
  let ultima: Lectura<T> | null = null;
  let enVuelo: { pedidaEn: number; promesa: Promise<Lectura<T>> } | null = null;
  // La lectura que saldrá cuando termine la que está en vuelo. Es una sola para todos los que la esperan.
  let siguiente: Promise<Lectura<T>> | null = null;
  const escuchas = new Set<(lectura: Lectura<T>) => void>();

  function lanzar(): Promise<Lectura<T>> {
    const pedidaEn = ahora();
    // `new Promise` y no `leer().then`: si `leer` revienta antes de devolver su promesa, cae aquí igual.
    const promesa = new Promise<T>((listo) => listo(leer())).then(
      (valor) => {
        const lectura: Lectura<T> = { valor, pedidaEn };
        ultima = lectura;
        enVuelo = null;
        // Copia: quien escucha puede dejar de escuchar dentro de su propio aviso.
        for (const avisar of [...escuchas]) avisar(lectura);
        return lectura;
      },
      (error: unknown) => {
        enVuelo = null;
        throw error;
      },
    );
    // Quien pide sin esperar la respuesta (`void pedir()`) no deja un rechazo sin atender. La promesa que se
    // entrega sigue rechazando para quien sí la espera.
    promesa.catch(() => {});
    enVuelo = { pedidaEn, promesa };
    return promesa;
  }

  function pedir(frescaDesde: number = ahora()): Promise<Lectura<T>> {
    if (ultima !== null && ultima.pedidaEn >= frescaDesde) return Promise.resolve(ultima);
    if (enVuelo === null) return lanzar();
    if (enVuelo.pedidaEn >= frescaDesde) return enVuelo.promesa;
    if (siguiente === null) {
      const espera = enVuelo.promesa.then(() => {}, () => {}).then(() => {
        siguiente = null;
        return lanzar();
      });
      espera.catch(() => {});
      siguiente = espera;
    }
    return siguiente;
  }

  return {
    pedir,
    ultima: () => ultima,
    escuchar(alLlegar) {
      escuchas.add(alLlegar);
      return () => {
        escuchas.delete(alLlegar);
      };
    },
  };
}

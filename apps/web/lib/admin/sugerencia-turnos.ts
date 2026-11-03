// ============================================================================
// sugerencia-turnos.ts — La propuesta de turnos de una semana (2026-11-03)
// ============================================================================
// PROMETE: dada la gente de una sede, lo que pidió la venta de cada hora (el
//          promedio de las últimas 4 semanas), su disponibilidad aprobada y su
//          jornada, proponer para cada persona y cada día una entrada y una
//          salida o un día libre, de modo que el piso quede cubierto donde más
//          se vende. Es una PROPUESTA: no guarda nada; la líder la revisa y la
//          publica.
// ASUME:   horas en MINUTOS desde la medianoche de Lima. Quién cuenta en piso y
//          quién es líder ya lo decidió `cuentaEnCobertura`. Lo que pide la venta
//          ya se pasó a personas con `ventaPedia` (repeticion.ts) — aquí llega
//          hecho, por cuarto de hora.
// NO HACE: leer la base ni decidir el ritmo o el mínimo (Parámetros, 0585), ni la
//          disponibilidad (0584, Lo mío). No crea sobretiempo: nadie pasa de 48 h
//          ni de su jornada.
//
// LAS REGLAS (decididas con Felipe, 2026-11-02 y 2026-11-03)
//   · Mueve la entrada, la salida y el día libre. Cada día es UN turno corrido:
//     nunca un turno partido.
//   · «No puedo» nunca se pisa. «Prefiero no» se respeta si alcanza la gente; si
//     no, se usa y se avisa. «Prefiero trabajar» (0591) cuenta un poco a favor de
//     poner a esa persona ahí —BONO_PREFIERE_TRABAJAR—, mucho menos que cubrir un
//     hueco de la venta o que respetar un «prefiero no»: desempata, no manda.
//     «Horario fijo» deja ese día como estaba.
//   · Cada persona mantiene sus días de trabajo por semana y las horas de su
//     jornada (la que fijó DO; si no hay, las de su horario de siempre).
//   · Primero los picos: faltar gente en piso pesa más que sobrar, y sobrar
//     pesa menos donde más se vende. Tres horas seguidas cortas pesan mucho más
//     que una hora suelta («no un hueco de 3 horas en el día»).
//   · Siempre una líder en piso, si la sede pide líderes.
//   · Rota: repetir exactamente el turno de la semana anterior cuesta un poco.
//
// CÓMO: recocido simulado (la misma búsqueda con la que se armó la grilla de TRU
// del 2026-11-02), con semilla fija: la misma entrada da SIEMPRE la misma
// propuesta. Cada paso cambia el turno de un día de una persona o le mueve el día
// libre, y solo se vuelve a medir ese día.
// ============================================================================

export type Min = number; // minutos desde la medianoche

export interface Turno { entrada: Min; salida: Min }

export interface Bloque { desde: Min; hasta: Min; estado: "no_puede" | "prefiere_no" | "prefiere_trabajar" }

export interface DiaSugerencia {
  fecha: string;
  /** Ventana de atención de la sede ese día; null = no se atiende. */
  abre: Min | null;
  cierra: Min | null;
  /** Personas que pide la venta en el cuarto de hora que empieza en `min`. */
  pedia: (min: Min) => number;
  /** Compras promedio de la hora entera de `min` (pesa cuánto duele que sobre). */
  compras: (min: Min) => number;
  /** Líderes que pide la sede ese día (0 = no se exige). */
  metaLideres: number;
}

export interface PersonaSugerencia {
  id: string;
  nombre: string;
  cuenta: boolean;
  lider: boolean;
  /** Horas netas por semana que tiene que sumar (jornada de DO, o las de su horario). */
  objetivoHoras: number;
  /** Cuántos días trabaja por semana. */
  diasTrabajo: number;
  /** Minutos de refrigerio que se descuentan de cada día trabajado. */
  refrigerioMin: number;
  /** Lo que tiene hoy cada fecha (turno puntual u horario base); null = descansa. */
  actual: Record<string, Turno | null>;
  /** Fechas con «horario fijo»: no se mueven. */
  fijos: ReadonlySet<string>;
  /** Restricciones aprobadas por fecha. */
  bloques: Record<string, readonly Bloque[]>;
  /** Su turno del mismo día de la semana anterior, por índice de día (0 = lunes). */
  anterior?: readonly (Turno | null)[];
}

export interface Propuesta {
  turnos: Record<string, Record<string, Turno | null>>;
  /** Por persona: horas netas y días de la propuesta. */
  resumen: Record<string, { horas: number; dias: number; objetivo: number }>;
  /** Por fecha y hora entera: operativas en el peor cuarto y lo que pedía la venta. */
  cobertura: Record<string, { hora: number; enPiso: number; pedia: number }[]>;
  avisos: string[];
  costo: number;
}

const PASO: Min = 15;
const MAX_SEMANA_MIN: Min = 48 * 60;
/**
 * Cuánto baja el costo de un día en que la persona trabaja justo en horas que
 * prefiere trabajar (proporcional a cuánto de su turno cae ahí). Para dimensionarlo:
 * un «prefiero no» pisado cuesta 150, una hora de diferencia con su jornada 300 y
 * repetir el turno de la semana pasada 6. 30 alcanza para desempatar entre dos
 * propuestas igual de buenas, y no para dejar un hueco de cobertura.
 */
export const BONO_PREFIERE_TRABAJAR = 30;
const MIN_NETO: Min = 4 * 60;
const MAX_NETO: Min = 9 * 60;
const nombreDia = (fecha: string) =>
  ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"][new Date(`${fecha}T12:00:00Z`).getUTCDay()];
const hhmm = (m: Min) => `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;

/** Generador con semilla (mulberry32): la misma semilla, la misma propuesta. */
function aleatorio(semilla: number): () => number {
  let a = semilla >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function semillaDe(texto: string): number {
  let h = 2166136261;
  for (let i = 0; i < texto.length; i++) h = Math.imul(h ^ texto.charCodeAt(i), 16777619);
  return h >>> 0;
}

const cruza = (t: Turno, b: { desde: Min; hasta: Min }) => t.entrada < b.hasta && b.desde < t.salida;

/** Qué parte del turno (0 a 1) cae dentro de un bloque. */
const fraccionDentro = (t: Turno, b: { desde: Min; hasta: Min }) =>
  Math.max(0, Math.min(t.salida, b.hasta) - Math.max(t.entrada, b.desde)) / Math.max(1, t.salida - t.entrada);

/** Los turnos posibles de una persona un día: dentro de la ventana, de 15 en 15, del largo que le cabe, sin pisar un «no puedo». */
function opcionesDelDia(p: PersonaSugerencia, d: DiaSugerencia): Turno[] {
  if (d.abre === null || d.cierra === null) return [];
  const promedio = p.diasTrabajo > 0 ? (p.objetivoHoras * 60) / p.diasTrabajo : 7 * 60;
  const netoMin = Math.max(MIN_NETO, Math.round((promedio - 90) / 30) * 30);
  const netoMax = Math.min(MAX_NETO, Math.round((promedio + 90) / 30) * 30);
  const prohibidos = (p.bloques[d.fecha] ?? []).filter((b) => b.estado === "no_puede");
  const out: Turno[] = [];
  for (let neto = netoMin; neto <= netoMax; neto += 30) {
    const largo = neto + p.refrigerioMin;
    for (let e = d.abre; e + largo <= d.cierra; e += PASO) {
      const t = { entrada: e, salida: e + largo };
      if (!prohibidos.some((b) => cruza(t, b))) out.push(t);
    }
  }
  return out;
}

const neto = (t: Turno | null, refrigerio: Min) => (t ? Math.max(0, t.salida - t.entrada - refrigerio) : 0);

export function sugerirSemana(args: {
  dias: readonly DiaSugerencia[];
  personas: readonly PersonaSugerencia[];
  semilla: number;
  iteraciones?: number;
}): Propuesta {
  const { dias, personas } = args;
  const iteraciones = args.iteraciones ?? 40000;
  const azar = aleatorio(args.semilla);
  const D = dias.length;

  // Cuartos de hora de la ventana de cada día, con lo que pide la venta y lo que pesa sobrar.
  const slots = dias.map((d) => {
    if (d.abre === null || d.cierra === null) return [] as { m: Min; N: number; peso: number }[];
    const out: { m: Min; N: number; peso: number }[] = [];
    for (let m = d.abre; m < d.cierra; m += PASO) out.push({ m, N: d.pedia(m), peso: 1.6 / (0.6 + d.compras(m)) });
    return out;
  });
  const opciones = personas.map((p) => dias.map((d) => opcionesDelDia(p, d)));

  // Estado: el turno de cada persona cada día. Arranca en lo que tiene hoy (si cae en la ventana y no pisa un «no puedo»).
  const G: (Turno | null)[][] = personas.map((p, i) =>
    dias.map((d, j) => {
      const a = p.actual[d.fecha] ?? null;
      if (p.fijos.has(d.fecha)) return a;
      if (!a) return null;
      if (opciones[i][j].length === 0) return null;
      const valido = opciones[i][j].some((o) => o.entrada === a.entrada && o.salida === a.salida);
      return valido ? a : opciones[i][j][Math.floor(opciones[i][j].length / 2)];
    }),
  );
  const bloqueado = personas.map((p) => dias.map((d) => p.fijos.has(d.fecha)));

  const costoDia = (j: number): number => {
    let c = 0, corrida = 0;
    for (const s of slots[j]) {
      let n = 0, l = 0;
      for (let i = 0; i < personas.length; i++) {
        const t = G[i][j];
        if (t && t.entrada <= s.m && s.m < t.salida) {
          if (personas[i].cuenta) n++;
          if (personas[i].lider) l++;
        }
      }
      if (n < s.N) {
        c += 3 * (s.N - n) ** 2;
        corrida++;
        if (corrida > 8) c += 20; // pasadas las dos horas seguidas cortas, cada cuarto más duele más
      } else {
        corrida = 0;
        if (n > s.N) c += (n - s.N) ** 2 * s.peso;
      }
      if (dias[j].metaLideres > 0 && l === 0) c += 80;
    }
    for (let i = 0; i < personas.length; i++) {
      const t = G[i][j];
      if (!t) continue;
      const bloques = personas[i].bloques[dias[j].fecha] ?? [];
      for (const b of bloques) if (b.estado === "prefiere_no" && cruza(t, b)) c += 150;
      // Con varios bloques que prefiere trabajar el mismo día, cuenta el que más de su turno cubre (no se suman).
      let gusto = 0;
      for (const b of bloques) if (b.estado === "prefiere_trabajar") gusto = Math.max(gusto, fraccionDentro(t, b));
      c -= BONO_PREFIERE_TRABAJAR * gusto;
      const ant = personas[i].anterior?.[j];
      if (ant && ant.entrada === t.entrada && ant.salida === t.salida) c += 6;
    }
    return c;
  };
  const costoPersona = (i: number): number => {
    const p = personas[i];
    const horas = G[i].reduce((a, t) => a + neto(t, p.refrigerioMin), 0);
    const diasT = G[i].filter(Boolean).length;
    let c = 5 * Math.abs(horas - p.objetivoHoras * 60); // 300 por hora de diferencia
    c += 800 * Math.abs(diasT - p.diasTrabajo);
    if (horas > MAX_SEMANA_MIN) c += 100000; // nunca sobretiempo
    return c;
  };

  const porDia = dias.map((_, j) => costoDia(j));
  const porPersona = personas.map((_, i) => costoPersona(i));
  let total = porDia.reduce((a, b) => a + b, 0) + porPersona.reduce((a, b) => a + b, 0);
  let mejor = total;
  let mejorG = G.map((f) => [...f]);
  let T = 60;

  const libres = personas.map((_, i) => i).filter((i) => dias.some((_, j) => !bloqueado[i][j] && opciones[i][j].length > 0));
  if (libres.length > 0 && D > 0) {
    for (let it = 0; it < iteraciones; it++) {
      const i = libres[Math.floor(azar() * libres.length)];
      const movibles = dias.map((_, j) => j).filter((j) => !bloqueado[i][j]);
      if (movibles.length === 0) continue;
      const cambios: { j: number; antes: Turno | null }[] = [];
      if (azar() < 0.65) {
        const trabajados = movibles.filter((j) => G[i][j] && opciones[i][j].length > 0);
        if (trabajados.length === 0) continue;
        const j = trabajados[Math.floor(azar() * trabajados.length)];
        cambios.push({ j, antes: G[i][j] });
        G[i][j] = opciones[i][j][Math.floor(azar() * opciones[i][j].length)];
      } else {
        const trabaja = movibles.filter((j) => G[i][j]);
        const descansa = movibles.filter((j) => !G[i][j] && opciones[i][j].length > 0);
        if (trabaja.length === 0 || descansa.length === 0) continue;
        const a = trabaja[Math.floor(azar() * trabaja.length)];
        const b = descansa[Math.floor(azar() * descansa.length)];
        cambios.push({ j: a, antes: G[i][a] }, { j: b, antes: G[i][b] });
        G[i][b] = opciones[i][b][Math.floor(azar() * opciones[i][b].length)];
        G[i][a] = null;
      }
      const diasTocados = [...new Set(cambios.map((x) => x.j))];
      const nuevosDia = diasTocados.map((j) => costoDia(j));
      const nuevoPersona = costoPersona(i);
      const delta = nuevosDia.reduce((a, c, k) => a + c - porDia[diasTocados[k]], 0) + nuevoPersona - porPersona[i];
      if (delta <= 0 || azar() < Math.exp(-delta / T)) {
        diasTocados.forEach((j, k) => { porDia[j] = nuevosDia[k]; });
        porPersona[i] = nuevoPersona;
        total += delta;
        if (total < mejor - 1e-9) { mejor = total; mejorG = G.map((f) => [...f]); }
      } else {
        for (const x of [...cambios].reverse()) G[i][x.j] = x.antes;
      }
      T = Math.max(0.3, T * 0.9998);
    }
  }

  // ── El resultado, con palabras ──
  const turnos: Propuesta["turnos"] = {};
  const resumen: Propuesta["resumen"] = {};
  personas.forEach((p, i) => {
    turnos[p.id] = Object.fromEntries(dias.map((d, j) => [d.fecha, mejorG[i][j]]));
    resumen[p.id] = {
      horas: Math.round((mejorG[i].reduce((a, t) => a + neto(t, p.refrigerioMin), 0) / 60) * 100) / 100,
      dias: mejorG[i].filter(Boolean).length,
      objetivo: p.objetivoHoras,
    };
  });

  const cobertura: Propuesta["cobertura"] = {};
  const avisos: string[] = [];
  dias.forEach((d, j) => {
    const horas = new Map<number, { enPiso: number; pedia: number }>();
    for (const s of slots[j]) {
      const n = personas.filter((p, i) => p.cuenta && mejorG[i][j] && mejorG[i][j]!.entrada <= s.m && s.m < mejorG[i][j]!.salida).length;
      const h = Math.floor(s.m / 60);
      const prev = horas.get(h);
      horas.set(h, { enPiso: prev ? Math.min(prev.enPiso, n) : n, pedia: prev ? Math.max(prev.pedia, s.N) : s.N });
    }
    cobertura[d.fecha] = [...horas].map(([hora, v]) => ({ hora, ...v }));
    // Las horas cortas, juntas en tramos: «el sábado de 17:00 a 19:00 falta 1 persona en piso».
    let ini: number | null = null, falta = 0;
    const cerrar = (fin: number) => {
      if (ini !== null) avisos.push(`El ${nombreDia(d.fecha)} de ${hhmm(ini * 60)} a ${hhmm(fin * 60)} ${falta === 1 ? "falta 1 persona" : `faltan ${falta} personas`} en piso.`);
      ini = null; falta = 0;
    };
    for (const c of cobertura[d.fecha]) {
      if (c.enPiso < c.pedia) { if (ini === null) ini = c.hora; falta = Math.max(falta, c.pedia - c.enPiso); }
      else cerrar(c.hora);
    }
    cerrar((cobertura[d.fecha].at(-1)?.hora ?? 0) + 1);
  });
  personas.forEach((p, i) => {
    dias.forEach((d, j) => {
      const t = mejorG[i][j];
      if (t && (p.bloques[d.fecha] ?? []).some((b) => b.estado === "prefiere_no" && cruza(t, b))) {
        avisos.push(`${p.nombre} trabaja el ${nombreDia(d.fecha)} en horas que prefiere no: no alcanzaba la gente.`);
      }
    });
    const r = resumen[p.id];
    if (Math.abs(r.horas - p.objetivoHoras) > 0.25) {
      avisos.push(`${p.nombre} queda con ${String(r.horas).replace(".", ",")} h de ${String(p.objetivoHoras).replace(".", ",")} h: con su disponibilidad no le caben todas.`);
    }
  });

  return { turnos, resumen, cobertura, avisos, costo: Math.round(mejor) };
}

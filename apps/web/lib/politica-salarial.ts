// El documento «Cuadro de categorías y política salarial» de CAYLA.
//
// ── POR QUÉ ESTE ARCHIVO Y NO PROSA EN LA PANTALLA ──────────────────────────
//
// El documento se pinta en pantalla Y se congela como texto plano al publicarlo
// (migración 0141). Si cada formato se escribiera por separado, tarde o temprano
// uno diría algo que el otro no — y el que vale como prueba es el congelado.
//
// Por eso acá el documento es una ESTRUCTURA, y hay dos renderizadores que la
// recorren: uno a JSX y otro a texto. Cambiar una frase la cambia en los dos.
//
// ── LO QUE ESTE DOCUMENTO TIENE QUE CUMPLIR ─────────────────────────────────
//
// Ley 30709 y su reglamento (D.S. 002-2018-TR): todo empleador privado, sin
// umbral de tamaño, debe tener un cuadro de categorías y funciones y una
// política salarial con criterios objetivos, e INFORMARLOS al trabajador.
// No tenerlos: infracción muy grave, numeral 25.22 del RLGIT.
// No informarlos: numeral 25.23.
//
// ── LA REGLA QUE ORDENA TODA LA REDACCIÓN ───────────────────────────────────
//
// El papel no puede decir nada que la planilla desmienta. Por eso las bandas, el
// tope de educación, las tarifas de movilidad, la cantidad de personas por
// categoría y la brecha entre el sueldo más alto y el más bajo NO se escriben
// acá: llegan calculadas de `fn_cuadro_categorias()`, que las lee de
// `asignaciones_salario`, `topes_educacion_rango` y `parametros_laborales`. Si
// mañana cambia un sueldo o un pasaje, cambia el documento — y el sistema avisa
// que hay que publicarlo de nuevo.

export interface FactorCategoria {
  factor: string;
  nivel: string;
}

export interface CategoriaCuadro {
  rango: string;
  orden: number;
  proposito: string | null;
  funciones: string | null;
  requisitos: string | null;
  criterio: string | null;
  personas: number;
  /** Lo que la empresa DECLARA que vale la categoría. Es lo que se publica. */
  salario_declarado: number | string | null;
  /**
   * El mínimo y el máximo que hoy cobra quien está en la categoría, ya filtrado
   * a planilla (0145). NO se publica: sirve para que la pantalla de
   * administración avise si alguien quedó por debajo del monto declarado.
   */
  salario_min: number | string | null;
  salario_max: number | string | null;
  tope_educacion: number | string | null;
  factores: FactorCategoria[];
}

export interface TarifaMovilidad {
  sede: string | null;
  valor: number | string;
}

export interface Cuadro {
  categorias: CategoriaCuadro[];
  movilidad: TarifaMovilidad[];
  brecha: number | string | null;
}

export type Bloque =
  | { tipo: "parrafo"; texto: string }
  | { tipo: "lista"; items: string[] }
  | { tipo: "tabla"; cabeceras: string[]; filas: string[][] }
  | { tipo: "destacado"; texto: string };

export interface Seccion {
  titulo: string;
  bloques: Bloque[];
}

export interface Documento {
  titulo: string;
  empresa: { nombre: string; ruc: string; firmante: string; cargo: string };
  fecha: string;
  secciones: Seccion[];
}

// Los nombres que se leen en pantalla. El código en la base es otro (histórico)
// y no se toca: renombrar una clave que ya está en tramos de salario firmados
// rompería la trazabilidad a cambio de nada.
export const NOMBRE_RANGO: Record<string, string> = {
  colibri: "Colibrí",
  cayla: "Cayla",
  support: "Support",
  aurora: "Aurora",
  oraculo: "Oráculo",
  archicaylo: "ArchiCayla",
};

const NOMBRE_SEDE: Record<string, string> = {
  AQP: "Arequipa",
  TRU: "Trujillo",
  LIM: "Lima",
  CCO: "Central",
};

// Las seis áreas del catálogo (tabla `areas`, migración 0022). Entran al
// documento como SEGUNDO EJE: dos personas de la misma categoría en áreas
// distintas hacen cosas distintas y valen lo mismo. Decirlo explícitamente es lo
// que sostiene que una Cayla de tienda y una de taller estén en la misma
// categoría — que es justo lo que una inspección pregunta.
export const AREAS_DOC: string[] = [
  "Calidad y servicio al cliente",
  "Taller y producción",
  "Estrategia comercial",
  "Desarrollo organizacional",
  "Experiencia, marca y comunidad",
  "Crecimiento y expansión",
];

/**
 * Días de asistencia que se asumen para la referencia mensual aproximada.
 *
 * Es 24 por decisión de Felipe (2026-08-04) y coincide con su simulación: un mes
 * típico de lunes a sábado. NO es una promesa — la movilidad se paga por día
 * efectivamente asistido, y el documento lo dice con esas palabras. Vive acá como
 * constante para que la cifra y la prosa no puedan divergir: el error de decir
 * «S/260 en un mes de 24 días» ya se cometió una vez.
 */
export const DIAS_REFERENCIA = 24;

const soles = (n: number | string | null | undefined): string => {
  if (n === null || n === undefined) return "—";
  const v = typeof n === "string" ? Number(n) : n;
  return Number.isFinite(v) ? `S/ ${v.toFixed(2)}` : "—";
};

const num = (n: number | string | null | undefined): number | null => {
  if (n === null || n === undefined) return null;
  const v = typeof n === "string" ? Number(n) : n;
  return Number.isFinite(v) ? v : null;
};

/**
 * Lo que el documento publica como remuneración de una categoría.
 *
 * Es el monto DECLARADO, no lo que cobra quien hoy está en ella. Hasta la 0145
 * esto devolvía el mínimo y el máximo de los sueldos vigentes, y como el filtro
 * no excluía a los locadores, un honorario alto empujaba el máximo de una
 * categoría por encima de la siguiente: el documento publicado llegó a decir
 * que ArchiCayla (la más alta) valía S/1500 y Oráculo S/1800.
 *
 * Una categoría sin monto declarado dice «—» en vez de inventarlo con los
 * sueldos reales, que es de donde venía el error.
 */
function remuneracion(c: CategoriaCuadro): string {
  const declarado = num(c.salario_declarado);
  if (declarado !== null) return soles(declarado);

  // Sin monto declarado se vuelve al comportamiento anterior, y es a propósito.
  //
  // La pantalla y la base se publican por caminos distintos: el despliegue de
  // Vercel y el SQL pegado a mano. Uno de los dos llega siempre primero. Si esta
  // pantalla exigiera la columna `salario_declarado`, desplegar antes de aplicar
  // la 0145 dejaría el documento —que es una obligación legal viva— mostrando
  // «—» en las seis filas hasta que alguien corriera el SQL.
  //
  // Degradarse a lo de antes no pierde ningún dato y no rompe nada: el documento
  // sigue diciendo algo cierto, solo que menos bueno, durante los minutos que
  // separan un paso del otro. El orden deja de importar.
  if (c.personas === 0) return "Sin personas asignadas hoy";
  const min = soles(c.salario_min);
  const max = soles(c.salario_max);
  return min === max ? min : `${min} a ${max}`;
}

/**
 * Las categorías cuyo monto declarado NO supera al de la categoría anterior.
 *
 * La escala tiene que subir con la categoría: es la única razón por la que una
 * remuneración puede ser mayor que otra ante una inspección (Ley 30709). Si se
 * desordena, la pantalla lo avisa —decisión de Felipe: avisar, no bloquear— y
 * el aviso NO entra al documento: un papel que se declara incoherente a sí
 * mismo es peor prueba que uno sin publicar.
 */
export function categoriasFueraDeOrden(cats: CategoriaCuadro[]): string[] {
  const ordenadas = [...cats].sort((a, b) => a.orden - b.orden);
  const fuera: string[] = [];
  for (let i = 1; i < ordenadas.length; i++) {
    const previa = num(ordenadas[i - 1].salario_declarado);
    const actual = num(ordenadas[i].salario_declarado);
    if (previa === null || actual === null) continue;
    if (actual <= previa) {
      fuera.push(NOMBRE_RANGO[ordenadas[i].rango] ?? ordenadas[i].rango);
    }
  }
  return fuera;
}

/** Las líneas de un campo de texto multilínea, sin vacías. */
function lineas(txt: string | null): string[] {
  return (txt ?? "").split("\n").map((l) => l.trim()).filter(Boolean);
}

/** La tarifa de movilidad más baja y la más alta, para la referencia. */
function rangoMovilidad(tarifas: TarifaMovilidad[]): { min: number; max: number } | null {
  const vals = tarifas.map((t) => num(t.valor)).filter((v): v is number => v !== null && v > 0);
  if (vals.length === 0) return null;
  return { min: Math.min(...vals), max: Math.max(...vals) };
}

export function construirDocumento(cuadro: Cuadro, fecha: string): Documento {
  const cats = [...cuadro.categorias].sort((a, b) => a.orden - b.orden);
  const factores = cats[0]?.factores.map((f) => f.factor) ?? [];
  const movil = rangoMovilidad(cuadro.movilidad ?? []);

  const secciones: Seccion[] = [];

  // ── 1 ─────────────────────────────────────────────────────────────────────
  secciones.push({
    titulo: "Para qué sirve este documento",
    bloques: [
      {
        tipo: "parrafo",
        texto:
          "Este documento explica cómo CAYLA organiza el trabajo en categorías, qué se espera de cada una, " +
          "y cómo se determina lo que gana cada persona. No hay criterios reservados: lo que decide una " +
          "remuneración está escrito acá y es el mismo para todo el equipo.",
      },
      {
        tipo: "parrafo",
        texto:
          "Se entrega a cada integrante al ingresar, cada vez que cambia de categoría y cada vez que cambia " +
          "el esquema remunerativo, conforme a la Ley 30709 y su reglamento, el Decreto Supremo 002-2018-TR.",
      },
      {
        tipo: "destacado",
        texto:
          "Si algo de este documento no te queda claro, o crees que no se está aplicando como dice, " +
          "puedes plantearlo directamente a la Gerencia. Preguntar no tiene consecuencia alguna.",
      },
    ],
  });

  // ── 2 ─────────────────────────────────────────────────────────────────────
  secciones.push({
    titulo: "Los seis criterios que determinan el valor de un puesto",
    bloques: [
      {
        tipo: "parrafo",
        texto:
          "CAYLA valora los puestos por lo que exigen, no por quién los ocupa. Son seis criterios, y se " +
          "aplican igual a todas las áreas y a todas las sedes:",
      },
      {
        tipo: "tabla",
        cabeceras: ["Criterio", "Qué mide"],
        filas: [
          ["Autonomía", "Cuánta supervisión necesita para hacer su trabajo."],
          ["Personas a cargo", "Por el trabajo de cuántas personas responde."],
          ["Responsabilidad económica", "Qué recursos, metas o presupuesto maneja."],
          ["Horizonte de sus decisiones", "A qué plazo tienen efecto las decisiones que toma."],
          ["Conocimiento requerido", "Qué hay que saber para ocupar el puesto."],
          ["Complejidad de lo que resuelve", "Qué tipo de problema le toca resolver."],
        ],
      },
      {
        tipo: "parrafo",
        texto:
          "Ninguno de estos criterios se refiere a la persona: ni a su sexo, ni a su edad, ni a su " +
          "antigüedad, ni a su situación familiar. Se refieren al puesto.",
      },
    ],
  });

  // ── 3 · la matriz de factores ─────────────────────────────────────────────
  if (factores.length > 0) {
    secciones.push({
      titulo: "Cómo se aplica cada criterio a cada categoría",
      bloques: [
        {
          tipo: "tabla",
          cabeceras: ["Criterio", ...cats.map((c) => NOMBRE_RANGO[c.rango] ?? c.rango)],
          filas: factores.map((nombreFactor) => [
            nombreFactor,
            ...cats.map((c) => c.factores.find((f) => f.factor === nombreFactor)?.nivel ?? "—"),
          ]),
        },
        {
          tipo: "parrafo",
          texto:
            "Leída de izquierda a derecha, cada fila muestra por qué una categoría vale más que la anterior. " +
            "Esa progresión es la única razón por la que las remuneraciones se diferencian.",
        },
      ],
    });
  }

  // ── 4 · la escala, de un vistazo ──────────────────────────────────────────
  secciones.push({
    titulo: "La escala",
    bloques: [
      // La columna «Personas hoy» se quitó a propósito el 2026-08-07, por dos
      // razones que se refuerzan entre sí:
      //
      //   1. IDENTIFICA PERSONAS. Support, Aurora y ArchiCayla tienen una sola
      //      persona cada una. En un equipo de ~22, todos saben quién es — y la
      //      columna de al lado dice cuánto gana. Este documento se entrega a
      //      todo el equipo con acuse de recibo: sería comunicar formalmente el
      //      sueldo de tres personas identificables. Contradice, además, lo que
      //      la propia sección de igualdad dice: que los criterios son públicos
      //      y las remuneraciones individuales viven en cada contrato.
      //
      //   2. ENVEJECE MAL. El documento se CONGELA al publicarse (0141). Las
      //      otras columnas son decisiones —la escala, los topes— y siguen
      //      siendo ciertas. Esta es una foto: al día siguiente de una
      //      contratación el texto entregado con constancia dice un número
      //      falso, y ya no hay forma de corregirlo sin republicar y volver a
      //      pedir las constancias.
      //
      // El dato sigue disponible para la Gerencia en /admin/equipo. Lo que se
      // quitó es su publicación, no su existencia.
      {
        tipo: "tabla",
        cabeceras: ["Categoría", "Remuneración", "Apoyo a estudios, hasta"],
        filas: cats.map((c) => [
          NOMBRE_RANGO[c.rango] ?? c.rango,
          remuneracion(c),
          c.tope_educacion !== null && c.tope_educacion !== undefined
            ? `${soles(c.tope_educacion)} al mes`
            : "—",
        ]),
      },
      {
        tipo: "parrafo",
        texto:
          "La remuneración de cada integrante es la establecida en su contrato de trabajo. Esta escala " +
          "describe los niveles vigentes y se aplica a las nuevas incorporaciones, a los cambios de " +
          "categoría y a los ajustes que la empresa acuerde. Ninguna remuneración se reduce por aplicar " +
          "esta escala.",
      },
      {
        tipo: "destacado",
        texto:
          "Ninguna categoría puede quedar por debajo de la remuneración mínima vital. Cuando la mínima " +
          "vital suba, las categorías que queden debajo se reajustan a la nueva mínima, sin necesidad de " +
          "publicar una versión nueva de este documento.",
      },
    ],
  });

  // ── 5 · las categorías, una por una ───────────────────────────────────────
  const bloquesCats: Bloque[] = [
    {
      tipo: "parrafo",
      texto:
        "Las categorías agrupan puestos de valor equivalente. Dos personas de la misma categoría pueden " +
        "hacer trabajos distintos —una en tienda y otra en taller— y estar correctamente en la misma " +
        "categoría, porque lo que se compara es el nivel de exigencia, no la tarea.",
    },
  ];
  for (const c of cats) {
    const nombre = NOMBRE_RANGO[c.rango] ?? c.rango;
    bloquesCats.push({ tipo: "destacado", texto: `${nombre} — ${c.proposito ?? ""}`.trim() });
    if (lineas(c.funciones).length > 0) {
      bloquesCats.push({ tipo: "parrafo", texto: "Funciones:" });
      bloquesCats.push({ tipo: "lista", items: lineas(c.funciones) });
    }
    if (lineas(c.requisitos).length > 0) {
      bloquesCats.push({ tipo: "parrafo", texto: "Para estar en esta categoría:" });
      bloquesCats.push({ tipo: "lista", items: lineas(c.requisitos) });
    }
    if (c.criterio) {
      bloquesCats.push({
        tipo: "parrafo",
        texto: `Por qué esta categoría se remunera por encima de la anterior: ${c.criterio}`,
      });
    }
  }
  secciones.push({ titulo: "Las categorías", bloques: bloquesCats });

  // ── 6 · las áreas ─────────────────────────────────────────────────────────
  secciones.push({
    titulo: "Las áreas",
    bloques: [
      {
        tipo: "parrafo",
        texto:
          "Cada persona pertenece además a un área. El área describe QUÉ hace; la categoría describe CUÁNTO " +
          "exige el puesto. Las categorías son las mismas en todas las áreas y en todas las sedes:",
      },
      { tipo: "lista", items: AREAS_DOC },
      {
        tipo: "parrafo",
        texto:
          "Cambiar de área no cambia por sí solo la categoría ni la remuneración. Solo un cambio de " +
          "categoría las modifica.",
      },
    ],
  });

  // ── 7 · ascensos ──────────────────────────────────────────────────────────
  secciones.push({
    titulo: "Cómo se cambia de categoría",
    bloques: [
      {
        tipo: "destacado",
        texto: "Se asciende a quien ya está haciendo el trabajo de la categoría siguiente.",
      },
      {
        tipo: "parrafo",
        texto:
          "No se asciende por prometer que se podrá, ni por llevar mucho tiempo. Se asciende cuando la " +
          "persona ya viene demostrando, de manera sostenida, lo que la categoría siguiente exige. Las tres " +
          "condiciones se cumplen a la vez:",
      },
      {
        tipo: "lista",
        items: [
          "Demuestra las competencias exigidas por la categoría a la que aspira.",
          "Aprobó su evaluación de desempeño.",
          "Cumplió los objetivos que se le asignaron.",
        ],
      },
      {
        tipo: "parrafo",
        texto:
          "El cambio de categoría no es automático ni tiene un plazo comprometido, y requiere que la " +
          "posición exista y que la empresa pueda sostenerla. Lo propone la jefatura directa y lo confirma " +
          "la Gerencia: nunca decide una sola persona.",
      },
      {
        tipo: "destacado",
        texto:
          "A quien no asciende se le entrega por escrito qué le faltó y qué tendría que demostrar. " +
          "Nadie se queda sin saber por qué.",
      },
      {
        tipo: "parrafo",
        texto:
          "Quedarse en una categoría no es un problema ni una señal de nada. Hay personas que serán " +
          "excelentes en su categoría durante años, y eso también se reconoce y se agradece.",
      },
    ],
  });

  // ── 8 · evaluación ────────────────────────────────────────────────────────
  secciones.push({
    titulo: "Cómo se evalúa el desempeño",
    bloques: [
      {
        tipo: "parrafo",
        texto:
          "Hay una conversación corta cada tres meses y una evaluación completa una vez al año. La " +
          "completa es la que decide los cambios de categoría. Cualquier integrante puede además solicitar " +
          "una conversación de desempeño cuando lo considere necesario.",
      },
      { tipo: "parrafo", texto: "Se evalúan tres cosas, y son las mismas para todas las categorías:" },
      {
        tipo: "tabla",
        cabeceras: ["Eje", "Qué se mira"],
        filas: [
          ["Cumplimiento", "Hace lo que le corresponde, a tiempo y bien hecho."],
          ["Resultados", "Logra los objetivos que se le asignaron para el periodo."],
          ["Equipo", "Cómo trabaja con las demás personas y cómo trata a la clienta."],
        ],
      },
      {
        tipo: "parrafo",
        texto:
          "Lo que cambia entre categorías no son los ejes sino la exigencia: en Colibrí, «Cumplimiento» es " +
          "seguir el procedimiento; en Aurora, es que su área entera cumpla.",
      },
      {
        tipo: "parrafo",
        texto:
          "Toda evaluación queda por escrito, la firma quien evalúa y quien es evaluada, y la persona puede " +
          "dejar registrada su discrepancia en el mismo documento.",
      },
    ],
  });

  // ── 9 · igualdad ──────────────────────────────────────────────────────────
  const brecha = num(cuadro.brecha);
  const bloquesIgualdad: Bloque[] = [
    {
      tipo: "destacado",
      texto:
        "CAYLA no aplica aumentos discrecionales. Toda variación de remuneración responde a un cambio de " +
        "categoría o a un ajuste general de la escala, y ambos se rigen por los criterios objetivos de " +
        "este documento.",
    },
    {
      tipo: "parrafo",
      texto:
        "Las categorías se denominan de forma neutra y agrupan puestos de igual valor con independencia " +
        "del sexo de quien los ocupa. Ninguna persona percibe una remuneración distinta a la de otra de su " +
        "misma categoría por razones ajenas a los criterios aquí descritos.",
    },
  ];
  if (brecha !== null) {
    bloquesIgualdad.push({
      tipo: "parrafo",
      texto:
        "CAYLA mantiene deliberadamente estrecha la distancia entre la remuneración más alta y la más " +
        `baja de la empresa. A la fecha de este documento, esa proporción es de ${brecha.toFixed(2)} a 1.`,
    });
  }
  bloquesIgualdad.push({
    tipo: "parrafo",
    texto:
      "Cualquier integrante que considere que su remuneración no corresponde a los criterios de este " +
      "documento puede plantearlo a la Gerencia y recibirá una respuesta por escrito.",
  });
  secciones.push({ titulo: "Igualdad de remuneración", bloques: bloquesIgualdad });

  // ── 10 · conceptos no remunerativos ───────────────────────────────────────
  const filasMovil = (cuadro.movilidad ?? [])
    .filter((t) => (num(t.valor) ?? 0) > 0)
    .map((t) => [
      t.sede ? (NOMBRE_SEDE[t.sede] ?? t.sede) : "General",
      `${soles(t.valor)} por día asistido`,
      `${soles((num(t.valor) ?? 0) * DIAS_REFERENCIA)} con ${DIAS_REFERENCIA} días`,
    ]);

  const bloquesConceptos: Bloque[] = [
    {
      tipo: "parrafo",
      texto:
        "Además de la remuneración, CAYLA otorga los conceptos siguientes. No son remuneración: no se " +
        "computan para gratificaciones, compensación por tiempo de servicios ni aportes, y así se " +
        "declaran en la planilla electrónica.",
    },
    {
      tipo: "destacado",
      texto:
        "Apoyo a los estudios. CAYLA cubre el 75 % de lo que pagas de estudios —tuyos o de tus hijos—, " +
        "hasta el tope de tu categoría. Contra comprobante.",
    },
    {
      tipo: "parrafo",
      texto:
        "El tope no es un monto que se entrega: es un techo. Si tu pensión mensual es de S/ 200, recibes " +
        "S/ 150, que es el 75 %. Si tu pensión es de S/ 800 y tu tope es S/ 480, recibes S/ 480. Y si no " +
        "estás estudiando ni tienes hijos estudiando, este apoyo no aplica — por eso dos personas de la " +
        "misma categoría pueden recibir montos distintos por este concepto.",
    },
  ];

  if (filasMovil.length > 0) {
    bloquesConceptos.push({
      tipo: "parrafo",
      texto:
        "Movilidad. Un monto por cada día efectivamente asistido, para cubrir el traslado. Varía por " +
        "ciudad porque el pasaje no cuesta lo mismo en todas, y cubre cuatro tramos diarios: ida y vuelta " +
        "con el retorno a almorzar. Si no hay asistencia, no hay movilidad.",
    });
    bloquesConceptos.push({
      tipo: "tabla",
      cabeceras: ["Sede", "Tarifa", "Referencia mensual"],
      filas: filasMovil,
    });
  }

  bloquesConceptos.push({
    tipo: "destacado",
    texto:
      "Asignación por cumpleaños. S/ 180, UNA SOLA VEZ AL AÑO, en el mes de tu cumpleaños. No es un " +
      "monto mensual y no se prorratea: se entrega completo, ese mes y ninguno más.",
  });

  bloquesConceptos.push({
    tipo: "tabla",
    cabeceras: ["Concepto", "Base legal"],
    filas: [
      ["Movilidad supeditada a asistencia", "D.S. 001-97-TR, art. 19 inciso e"],
      ["Apoyo a los estudios", "D.S. 001-97-TR, art. 19 inciso f"],
      ["Asignación por cumpleaños", "D.S. 001-97-TR, art. 19 inciso d"],
      ["Viáticos por viaje, contra comprobante", "D.S. 001-97-TR, art. 19 inciso i"],
    ],
  });

  bloquesConceptos.push({
    tipo: "parrafo",
    texto:
      "Estos conceptos se otorgan por decisión de la empresa y podrán ser revisados o modificados por " +
      "ella. Su otorgamiento no genera derecho adquirido ni se incorpora a la remuneración, conforme al " +
      "artículo 19 del Decreto Supremo 001-97-TR.",
  });

  bloquesConceptos.push({
    tipo: "destacado",
    texto:
      "Ningún aumento de remuneración se compensa reduciendo estos conceptos, ni a la inversa. Son " +
      "cosas distintas y se deciden por separado.",
  });

  // ── 10 · jornada, horario y cálculo ───────────────────────────────────────
  // Va ANTES de los conceptos no remunerativos: primero qué se pide (la
  // jornada), después qué se gana por eso, y al final qué se recibe además.
  //
  // ⚠️ La distinción entre JORNADA ORDINARIA (48 h) y HORARIO PROGRAMADO (45 h)
  // no es cosmética. El sobretiempo se mide contra la jornada ordinaria, no
  // contra el horario (D.S. 007-2002-TR art. 9). Declarar 45 h como jornada
  // convertiría las horas 46 a 48 en sobretiempo con recargo del 25 % / 35 %.
  // Los contratos y el RIT dicen 48 h — confirmado por Felipe el 2026-08-07.
  // No cambiar estas cifras sin revisar contratos, RIT y el art. de jornada del
  // RIT v3.2 (docs/disciplina-tardanzas-faltas/08-rit-v3.2-jornada-y-sobretiempo.md).
  secciones.push({
    titulo: "La jornada y cómo se calcula tu remuneración",
    bloques: [
      {
        tipo: "parrafo",
        texto:
          "La jornada ordinaria de trabajo en CAYLA es de cuarenta y ocho (48) horas semanales, que es el " +
          "máximo que permite el artículo 25 de la Constitución. Es la jornada que figura en tu contrato de trabajo.",
      },
      { tipo: "destacado", texto: "El horario que CAYLA te programa es de 45 horas semanales." },
      {
        tipo: "parrafo",
        texto:
          "Esas tres horas de diferencia no son un descuido ni un saldo pendiente: son tiempo que la empresa " +
          "decide no ocupar. Tres horas por semana son unas trece al mes, más de un día y medio de trabajo, y " +
          "existen para que puedas estudiar, descansar, ver a tu familia y tener una vida fuera del trabajo.",
      },
      {
        tipo: "parrafo",
        texto:
          "Este horario reducido se otorga por decisión de la empresa. Conforme al artículo 6 del Decreto " +
          "Supremo 007-2002-TR, corresponde a CAYLA establecer y modificar el horario de trabajo dentro de la " +
          "jornada ordinaria pactada. Su otorgamiento no constituye condición más beneficiosa, no genera " +
          "derecho adquirido y no modifica la jornada establecida en tu contrato de trabajo. Por esa misma " +
          "razón, el sobretiempo se cuenta desde la hora 49 de la semana y no desde la 46: el umbral es la " +
          "jornada ordinaria de cuarenta y ocho horas que figura en tu contrato, no el horario que se programa.",
      },
      {
        tipo: "parrafo",
        texto:
          "Tu día de descanso. Tienes como mínimo un día de descanso a la semana, siempre, conforme al " +
          "artículo 1 del Decreto Legislativo 713. En las sedes que atienden todos los días, ese día puede " +
          "rotar: una semana te toca uno y otra semana otro, según el rol de turnos. El artículo 2 del mismo " +
          "decreto permite expresamente estos regímenes alternativos, y así se organiza el trabajo sin que " +
          "nadie se quede sin su descanso.",
      },
      {
        tipo: "parrafo",
        texto:
          "A la fecha de este documento la distribución es la siguiente. Es la situación vigente, no un " +
          "compromiso permanente: puede modificarse por campaña o por necesidad de la operación, respetando " +
          "siempre el día de descanso semanal y la jornada ordinaria pactada.",
      },
      {
        tipo: "tabla",
        cabeceras: ["Sede", "Distribución vigente"],
        filas: [
          ["Tienda TRU", "6 días, con descanso semanal rotativo"],
          ["Taller LIM", "Lunes a viernes"],
          ["Tienda AQP", "Lunes a sábado"],
        ],
      },
      {
        tipo: "parrafo",
        texto:
          "La tabla describe cómo se organizan las tiendas y el taller. Central no es tienda —ahí están " +
          "administración y Desarrollo Organizacional— y su horario se pacta en cada contrato. En todos los " +
          "casos, el horario que te aplica a ti es el que figura en tu contrato de trabajo: esta tabla no " +
          "reemplaza lo pactado individualmente.",
      },
      {
        tipo: "parrafo",
        texto:
          "Cómo se calcula lo que cobras. Tu remuneración se calcula sobre las horas que efectivamente " +
          "registras. No es una cifra que alguien decida cada mes: sale del registro de tu propia asistencia.",
      },
      {
        tipo: "destacado",
        texto:
          "La remuneración de tu categoría corresponde al horario completo del periodo. Si en un periodo " +
          "registras menos horas —por inasistencia, por un horario reducido acordado, o por haber ingresado o " +
          "cesado dentro del periodo—, se paga la parte proporcional que corresponda. Es la misma regla para " +
          "todas las personas y para todas las categorías.",
      },
      {
        tipo: "parrafo",
        texto:
          "El periodo de pago va del 29 de un mes al 28 del siguiente. Por eso tu boleta no coincide " +
          "exactamente con el mes del calendario.",
      },
      {
        tipo: "parrafo",
        texto:
          "Feriados. Si trabajas un día feriado se te paga triple: el día feriado que te corresponde, las " +
          "horas que trabajaste, y una vez más esas horas como sobretasa, conforme al artículo 8 del Decreto " +
          "Legislativo 713. La única excepción es que se acuerde contigo, previamente y por escrito, un día de " +
          "descanso sustitutorio. Ese día debe ser uno en el que te correspondía trabajar: un día libre " +
          "otorgado sobre tu descanso semanal no sustituye nada, y en ese caso la sobretasa se paga igual.",
      },
      // ── Sobretiempo ───────────────────────────────────────────────────────
      // Se escribe en positivo y no como concesión, porque eso es lo que es: el
      // sistema lo detecta y lo paga SOLO, sin que nadie tenga que reclamarlo ni
      // llevar la cuenta. La mayoría de empresas paga horas extras cuando el
      // trabajador las pide y las puede probar.
      //
      // En julio de 2026 Felipe pidió no mencionarlo («podríamos perjudicarnos»).
      // Cambió de criterio al mandar programarlo, y desde la migración 0185 se
      // paga en automático. Callarlo ahora sería peor que no tenerlo: la línea
      // «Sobretiempo» aparece en la boleta, y un documento que se presenta como
      // completo pierde fuerza el día que se le encuentra un hueco.
      {
        tipo: "parrafo",
        texto:
          "Sobretiempo. Si en una semana superas las 48 horas de la jornada ordinaria, esas horas de más se " +
          "pagan con recargo: 25 % las dos primeras horas de cada día y 35 % las siguientes, conforme al " +
          "artículo 10 del Decreto Supremo 007-2002-TR. La semana se cuenta como un ciclo de siete días " +
          "corridos, no de lunes a domingo, siguiendo el criterio del Informe 027-2021-MTPE/14 de la " +
          "Dirección General de Trabajo.",
      },
      {
        tipo: "destacado",
        texto:
          "No tienes que pedirlo ni llevar la cuenta. El sistema lo calcula solo a partir de tus marcaciones, " +
          "cada periodo, y aparece en tu boleta con el detalle del día y de las horas. Lo habitual es que las " +
          "horas extras se paguen cuando el trabajador las reclama y puede probarlas; acá se detectan solas.",
      },
      {
        tipo: "parrafo",
        texto:
          "Como el horario que CAYLA programa es de 45 horas, superar las 48 es excepcional y ocurre cuando " +
          "cubres a una compañera o en una campaña. También puedes acordar por escrito que esas horas se " +
          "compensen con un descanso equivalente en lugar de cobrarlas, conforme al mismo artículo 10. Esa " +
          "decisión es tuya y se conversa caso por caso: nunca se aplica sola.",
      },
      // ── Aportes ───────────────────────────────────────────────────────────
      // Va acá y no en la sección de beneficios porque es la contracara de lo
      // anterior: quien acaba de leer que el sobretiempo y el feriado se pagan
      // tiene que saber que también se declaran. Es la parte que convierte «te
      // pagamos bien» en «te pagamos bien y queda registrado».
      {
        tipo: "parrafo",
        texto:
          "Todo lo que cobras se declara. Tu remuneración, tus feriados y tu sobretiempo forman parte de la " +
          "base sobre la que CAYLA aporta a EsSalud y sobre la que se retiene tu aporte previsional a la AFP " +
          "o la ONP. No hay una parte de tu sueldo que quede fuera de la planilla electrónica.",
      },
      {
        tipo: "destacado",
        texto:
          "Esto importa para tu futuro, no solo para el mes: la base declarada es la que determina tu pensión, " +
          "tu cobertura de salud y el monto de tu gratificación, tu CTS y tus vacaciones. Se calculan sobre tu " +
          "sueldo completo, no sobre una parte de él.",
      },
      // ── El neto que baja ─────────────────────────────────────────────────
      // Se dice ACÁ y no se deja para la conversación de entrega, por decisión
      // de Felipe (2026-08-08). Desde la migración 0193 el feriado y el
      // sobretiempo entran a la base de aportes, así que el descuento
      // previsional sube y el neto de cada persona baja entre S/9 y S/50.
      //
      // Si se enteran por la boleta del 28, la explicación llega tarde y suena a
      // excusa. Dicho antes, es una decisión de la empresa de declarar completo.
      {
        tipo: "parrafo",
        texto:
          "Qué cambia desde este periodo. Hasta ahora tus feriados y tu sobretiempo se te pagaban, pero no " +
          "formaban parte de esa base. Desde este periodo sí. Como consecuencia, tu aporte a la AFP o a la ONP " +
          "sube un poco y vas a ver un neto algo menor en tu boleta.",
      },
      {
        tipo: "destacado",
        texto:
          "Ese monto no se queda en CAYLA: va íntegro a tu fondo de pensión, que es tuyo. Y al declarar más, " +
          "sube también lo que la empresa aporta a tu EsSalud y la base con la que se calculan tu gratificación, " +
          "tu CTS y tus vacaciones.",
      },
      {
        tipo: "parrafo",
        texto:
          "Hay dos conceptos que la ley reconoce expresamente como no remunerativos y que por eso no forman " +
          "parte de esa base: la movilidad supeditada a la asistencia y el apoyo a estudios, ambos previstos " +
          "en el artículo 19 del Decreto Supremo 001-97-TR. Son adicionales a tu remuneración, no parte de " +
          "ella, y en la sección siguiente se explica cada uno.",
      },
      {
        tipo: "parrafo",
        texto:
          "Tu asistencia queda registrada. Tu entrada y tu salida se registran digitalmente, con la hora " +
          "exacta, en el terminal de tu sede. Cualquier corrección posterior queda guardada con el motivo y " +
          "con el nombre de quien la hizo.",
      },
      {
        tipo: "destacado",
        texto:
          "Esto es una garantía tuya: lo que cobras se puede verificar contra un registro que nadie puede " +
          "modificar en silencio.",
      },
    ],
  });

  secciones.push({ titulo: "Lo que se recibe además de la remuneración", bloques: bloquesConceptos });

  // ── 11 · la referencia mensual ────────────────────────────────────────────
  // Va DESPUÉS de los conceptos, y no antes, para que se lea sabiendo que la
  // movilidad depende de la asistencia y que el apoyo a estudios es un tope.
  if (movil !== null) {
    secciones.push({
      titulo: "Cuánto significa esto al mes",
      bloques: [
        {
          tipo: "parrafo",
          texto:
            `La tabla siguiente es una REFERENCIA APROXIMADA, calculada con ${DIAS_REFERENCIA} días de ` +
            "asistencia y suponiendo que la persona usa todo el apoyo a estudios de su categoría. No es " +
            "una promesa ni un monto garantizado: la movilidad depende de los días efectivamente " +
            "asistidos, y el apoyo a estudios, de lo que cada persona pague y compruebe.",
        },
        {
          tipo: "tabla",
          cabeceras: [
            "Categoría",
            "Remuneración",
            "Movilidad, hasta",
            "Estudios, hasta",
            "Referencia mensual",
          ],
          filas: cats
            // El monto declarado, igual que en la tabla de la escala: las dos
            // hablan de la misma categoría y no pueden dar cifras distintas.
            .filter((c) => num(c.salario_declarado) !== null)
            .map((c) => {
              const sueldo = num(c.salario_declarado) ?? 0;
              const educ = num(c.tope_educacion) ?? 0;
              const movMax = movil.max * DIAS_REFERENCIA;
              const movMin = movil.min * DIAS_REFERENCIA;
              return [
                NOMBRE_RANGO[c.rango] ?? c.rango,
                soles(sueldo),
                movMin === movMax ? soles(movMax) : `${soles(movMin)} a ${soles(movMax)}`,
                soles(educ),
                `hasta ${soles(sueldo + movMax + educ)}`,
              ];
            }),
        },
        {
          tipo: "parrafo",
          texto:
            "A esa referencia hay que restarle el aporte a tu sistema de pensiones, que se descuenta solo " +
            "de la remuneración y no de los apoyos. Y aparte, en el mes de tu cumpleaños, se suman los " +
            "S/ 180 de la asignación por cumpleaños.",
        },
      ],
    });
  }

  // ── 12 · compromisos ──────────────────────────────────────────────────────
  secciones.push({
    titulo: "Lo que CAYLA se compromete a sostener",
    bloques: [
      {
        tipo: "parrafo",
        texto:
          "Este documento exige cosas al equipo. Es justo que diga también qué se compromete a sostener la " +
          "empresa:",
      },
      {
        tipo: "lista",
        items: [
          "Que los criterios de remuneración sean públicos y los mismos para todas las personas.",
          "Que la remuneración se pague completa y a tiempo.",
          "Que toda evaluación se entregue por escrito, incluso cuando el resultado no sea el esperado.",
          "Que a quien no asciende se le explique por escrito qué le faltó.",
          "Que exista una vía directa a la Gerencia para plantear cualquier discrepancia, sin consecuencia por hacerlo.",
          "Que ninguna categoría quede por debajo de la remuneración mínima vital.",
          "Que las condiciones de trabajo y los horarios se acuerden con claridad y por escrito.",
          "Que los feriados y las sobretasas se paguen conforme a ley.",
          "Que tu asistencia quede registrada de forma verificable, y que toda corrección deje constancia de quién la hizo y por qué.",
        ],
      },
      {
        tipo: "parrafo",
        texto:
          "Estos compromisos describen cómo CAYLA administra su política salarial. No constituyen " +
          "condiciones más beneficiosas ni modifican los contratos de trabajo vigentes.",
      },
    ],
  });

  // ── 13 · vigencia ─────────────────────────────────────────────────────────
  secciones.push({
    titulo: "Vigencia y actualización",
    bloques: [
      {
        tipo: "parrafo",
        texto:
          "Este documento rige desde la fecha de su publicación y se mantiene vigente hasta que se publique " +
          "una versión posterior. Se revisa cuando cambia la estructura de categorías, cuando cambia el " +
          "esquema remunerativo y, en todo caso, al menos una vez al año.",
      },
      {
        tipo: "parrafo",
        texto:
          "Cada versión queda registrada en el sistema con su fecha, y cada integrante deja constancia de " +
          "haberla recibido. Las versiones anteriores se conservan tal como fueron comunicadas.",
      },
    ],
  });

  return {
    titulo: "Cuadro de categorías y funciones · Política salarial",
    empresa: {
      nombre: "CAYLA S.A.C.",
      ruc: "20605964550",
      firmante: "Alvarez Pereyra Felipe Miguel",
      cargo: "Gerencia General",
    },
    fecha,
    secciones,
  };
}

/**
 * El documento como texto plano. Es lo que se congela al publicar (0141) y lo
 * que se le muestra a un inspector: tiene que poder leerse tal cual dentro de
 * cinco años, sin depender de que la pantalla siga existiendo.
 */
// ============================================================================
// Cómo se congela el documento al publicarlo
// ============================================================================
// La 0141 exige guardar el documento ENTERO como texto y no regenerarlo: si se
// regenerara desde las tablas, cambiar una banda haría que todas las constancias
// viejas apuntaran a un texto que nadie leyó.
//
// Ese requisito se cumple igual guardando JSON —también es texto, también es
// inmutable— y con una ventaja grande: conserva la ESTRUCTURA. La pantalla lo
// vuelve a `Documento` y lo pinta con el mismo renderizador que usa antes de
// publicar, así que se ve idéntico las dos veces.
//
// Antes se guardaba texto plano (`documentoATexto`), y el documento publicado se
// mostraba en un <pre>: títulos en mayúsculas, tablas con `|`, guiones de
// subrayado. Un documento que 22 personas tienen que leer y entender no puede
// verse peor DESPUÉS de publicarlo que antes.
//
// `documentoATexto` se conserva por dos motivos: las versiones ya publicadas con
// ese formato tienen que seguir leyéndose, y sigue siendo la forma correcta de
// volcar el documento a texto llano cuando haga falta (copiar, imprimir sin
// estilos, adjuntar en un correo).
export function documentoAJson(doc: Documento): string {
  return JSON.stringify(doc);
}

/**
 * Recupera el documento guardado. Devuelve `null` cuando lo almacenado no es
 * JSON — que es el caso de las versiones publicadas antes de este cambio, y la
 * señal de que hay que mostrarlas como texto llano.
 */
export function documentoDesdeGuardado(guardado: string): Documento | null {
  const t = guardado.trim();
  if (!t.startsWith("{")) return null;
  try {
    const d = JSON.parse(t);
    // Se comprueba la forma, no solo que el JSON sea válido: un texto que
    // empiece con `{` y parsee no es necesariamente un documento.
    if (
      typeof d?.titulo === "string" &&
      Array.isArray(d?.secciones) &&
      typeof d?.empresa?.nombre === "string"
    ) {
      return d as Documento;
    }
    return null;
  } catch {
    return null;
  }
}

export function documentoATexto(doc: Documento): string {
  const out: string[] = [];
  out.push(doc.titulo.toUpperCase());
  out.push(`${doc.empresa.nombre} — RUC ${doc.empresa.ruc}`);
  out.push(`Fecha: ${doc.fecha}`);
  out.push("");

  for (const sec of doc.secciones) {
    out.push("");
    out.push(sec.titulo.toUpperCase());
    out.push("-".repeat(sec.titulo.length));
    for (const b of sec.bloques) {
      if (b.tipo === "parrafo") {
        out.push(b.texto);
        out.push("");
      } else if (b.tipo === "destacado") {
        out.push(`>> ${b.texto}`);
        out.push("");
      } else if (b.tipo === "lista") {
        for (const it of b.items) out.push(`  · ${it}`);
        out.push("");
      } else {
        out.push(b.cabeceras.join(" | "));
        for (const fila of b.filas) out.push(fila.join(" | "));
        out.push("");
      }
    }
  }

  out.push("");
  out.push(`${doc.empresa.firmante}`);
  out.push(`${doc.empresa.cargo} — ${doc.empresa.nombre}`);
  return out.join("\n");
}

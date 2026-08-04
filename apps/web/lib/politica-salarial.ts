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

function banda(c: CategoriaCuadro): string {
  if (c.personas === 0) return "Sin personas asignadas hoy";
  const min = soles(c.salario_min);
  const max = soles(c.salario_max);
  return min === max ? min : `${min} a ${max}`;
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
      {
        tipo: "tabla",
        cabeceras: ["Categoría", "Remuneración", "Apoyo a estudios, hasta", "Personas hoy"],
        filas: cats.map((c) => [
          NOMBRE_RANGO[c.rango] ?? c.rango,
          banda(c),
          c.tope_educacion !== null && c.tope_educacion !== undefined
            ? `${soles(c.tope_educacion)} al mes`
            : "—",
          String(c.personas),
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
            .filter((c) => num(c.salario_min) !== null)
            .map((c) => {
              const sueldo = num(c.salario_min) ?? 0;
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

// ============================================================================
// politica-salarial.test.ts — El aviso de escala desordenada
// ============================================================================
// `categoriasFueraDeOrden` es el único freno que queda cuando la escala del
// cuadro de categorías se desordena: Felipe decidió avisar en pantalla y NO
// bloquear la carga en la base. Un aviso que no salta es lo mismo que no tener
// aviso, y esto es lo que evita repetir lo que se publicó en producción el
// 2026-08-04 — ArchiCayla (la categoría más alta) a S/1500 debajo de Oráculo a
// S/1800.
//
// La lógica vive solo en el navegador, así que ninguna prueba pgTAP la alcanza.
// Vive acá y en ningún otro sitio: no hay gemelo en SQL que pueda separarse.
// ============================================================================
import { describe, it, expect } from "vitest";
import {
  categoriasFueraDeOrden,
  construirDocumento,
  documentoAJson,
  documentoDesdeGuardado,
  type CategoriaCuadro,
  type Cuadro,
} from "@/lib/politica-salarial";

/** Una categoría con lo mínimo que mira la función. El resto no interviene. */
const cat = (rango: string, orden: number, declarado: number | null): CategoriaCuadro => ({
  rango,
  orden,
  proposito: null,
  funciones: null,
  requisitos: null,
  criterio: null,
  personas: 0,
  salario_declarado: declarado,
  salario_min: null,
  salario_max: null,
  tope_educacion: null,
  factores: [],
});

/** La escala acordada el 2026-08-04, en orden. */
const escalaBuena = [
  cat("colibri", 1, 1130),
  cat("cayla", 2, 1185),
  cat("support", 3, 1260),
  cat("aurora", 4, 1360),
  cat("oraculo", 5, 1440),
  cat("archicaylo", 6, 1500),
];

describe("categoriasFueraDeOrden — el aviso de la escala", () => {
  it("con la escala acordada no avisa nada", () => {
    expect(categoriasFueraDeOrden(escalaBuena)).toEqual([]);
  });

  it("detecta el caso real de producción: la categoría más alta por debajo de la anterior", () => {
    const rota = [
      cat("colibri", 1, 1130),
      cat("cayla", 2, 1185),
      cat("support", 3, 1260),
      cat("aurora", 4, 1360),
      cat("oraculo", 5, 1800),
      cat("archicaylo", 6, 1500), // lo que se publicó y no debía
    ];
    expect(categoriasFueraDeOrden(rota)).toEqual(["ArchiCayla"]);
  });

  it("dos categorías iguales también avisan: valer lo mismo no justifica dos categorías", () => {
    const empatadas = [cat("colibri", 1, 1130), cat("cayla", 2, 1130)];
    expect(categoriasFueraDeOrden(empatadas)).toEqual(["Cayla"]);
  });

  it("nombra todas las que están fuera de orden, no solo la primera", () => {
    const muyRota = [
      cat("colibri", 1, 1500),
      cat("cayla", 2, 1185),
      cat("support", 3, 1100),
      cat("aurora", 4, 1360),
    ];
    expect(categoriasFueraDeOrden(muyRota)).toEqual(["Cayla", "Support"]);
  });

  it("no se confía del orden en que llegan: las ordena por su número de categoría", () => {
    const desordenadas = [...escalaBuena].reverse();
    expect(categoriasFueraDeOrden(desordenadas)).toEqual([]);
  });

  it("una categoría sin monto declarado no dispara el aviso ni arrastra a la siguiente", () => {
    // Falla abierto a propósito: «todavía no se cargó» no es lo mismo que «está
    // mal cargado», y un aviso por un dato ausente entrena a ignorar los avisos.
    const conHueco = [
      cat("colibri", 1, 1130),
      cat("cayla", 2, null),
      cat("support", 3, 1260),
    ];
    expect(categoriasFueraDeOrden(conHueco)).toEqual([]);
  });
});

// ============================================================================
// La escala se publica aunque la categoría esté vacía
// ============================================================================
// El 2026-08-04 el documento en producción decía, en la fila de Oráculo:
//
//     Oráculo | Sin personas asignadas hoy | S/ 420.00 al mes
//
// Una categoría sin nadie SIGUE valiendo lo que la empresa declaró: el cuadro
// describe los puestos que existen, no quién los ocupa hoy. Y es justo la fila
// que más importa que tenga monto, porque es la que alguien va a leer cuando
// pregunte cuánto se gana si asciende ahí.
//
// Venía de armar la remuneración con los sueldos reales: sin personas no había
// sueldos, y sin sueldos no había nada que mostrar.
// ============================================================================
describe("la escala publica el monto aunque la categoría esté vacía", () => {
  const cuadro = (): Cuadro => ({
    categorias: [
      { ...cat("colibri", 1, 1130), personas: 13 },
      { ...cat("oraculo", 5, 1440), personas: 0 }, // vacía hoy
      { ...cat("archicaylo", 6, 1500), personas: 1 },
    ],
    movilidad: [],
    brecha: null,
  });

  /** Las filas de la tabla titulada «La escala». */
  const filasEscala = (): string[][] => {
    const doc = construirDocumento(cuadro(), "2026-08-04");
    const seccion = doc.secciones.find((s) => s.titulo === "La escala");
    const tabla = seccion?.bloques.find((b) => b.tipo === "tabla");
    if (tabla === undefined || tabla.tipo !== "tabla") throw new Error("no hay tabla de escala");
    return tabla.filas;
  };

  it("una categoría con 0 personas muestra su monto, no «sin personas asignadas»", () => {
    const oraculo = filasEscala().find((f) => f[0] === "Oráculo");
    expect(oraculo?.[1]).toBe("S/ 1440.00");
  });

  // El 2026-08-07 se quitó la columna «Personas hoy» de la tabla publicada.
  // Con Support, Aurora y ArchiCayla en una sola persona cada una, el conteo
  // junto al monto revelaba el sueldo de tres personas identificables en un
  // documento que se entrega a todo el equipo con acuse. Y como el texto se
  // congela al publicarse (0141), el número quedaba falso a la primera
  // contratación. El dato sigue en /admin/equipo; lo que se quitó es publicarlo.
  it("la tabla NO publica cuántas personas hay en cada categoría", () => {
    const doc = construirDocumento(cuadro(), "2026-08-07");
    const seccion = doc.secciones.find((s) => s.titulo === "La escala");
    const tabla = seccion?.bloques.find((b) => b.tipo === "tabla");
    if (tabla === undefined || tabla.tipo !== "tabla") throw new Error("no hay tabla de escala");
    expect(tabla.cabeceras).not.toContain("Personas hoy");
    expect(tabla.cabeceras).toHaveLength(3);
    expect(tabla.filas.every((f) => f.length === 3)).toBe(true);
  });

  it("las categorías con gente muestran su monto declarado, no el sueldo de nadie", () => {
    const filas = filasEscala();
    expect(filas.find((f) => f[0] === "Colibrí")?.[1]).toBe("S/ 1130.00");
    expect(filas.find((f) => f[0] === "ArchiCayla")?.[1]).toBe("S/ 1500.00");
  });

  it("si la base todavía no tiene la columna, no muestra «—»: vuelve a lo de antes", () => {
    // Desplegar la pantalla antes de aplicar la 0145 no puede dejar el documento
    // legal en blanco. Sin monto declarado se degrada al comportamiento viejo.
    const sinColumna: Cuadro = {
      categorias: [
        { ...cat("colibri", 1, null), personas: 13, salario_min: 1130, salario_max: 1130 },
      ],
      movilidad: [],
      brecha: null,
    };
    const doc = construirDocumento(sinColumna, "2026-08-04");
    const seccion = doc.secciones.find((s) => s.titulo === "La escala");
    const tabla = seccion?.bloques.find((b) => b.tipo === "tabla");
    if (tabla === undefined || tabla.tipo !== "tabla") throw new Error("no hay tabla de escala");
    expect(tabla.filas[0]?.[1]).toBe("S/ 1130.00");
  });

  it("la categoría vacía también aparece en la referencia mensual", () => {
    // La otra tabla del documento filtraba por el sueldo real, así que una
    // categoría sin gente desaparecía de ahí sin que nadie lo notara.
    const conMovilidad: Cuadro = { ...cuadro(), movilidad: [{ sede: null, valor: 10 }] };
    const doc = construirDocumento(conMovilidad, "2026-08-04");
    const seccion = doc.secciones.find((s) => s.titulo === "Cuánto significa esto al mes");
    const tabla = seccion?.bloques.find((b) => b.tipo === "tabla");
    if (tabla === undefined || tabla.tipo !== "tabla") throw new Error("no hay tabla de referencia");
    expect(tabla.filas.map((f) => f[0])).toContain("Oráculo");
  });
  it("declara jornada ordinaria de 48 h y horario programado de 45 h", () => {
    const doc = construirDocumento(cuadro(), "2026-08-07");
    const sec = doc.secciones.find((s) => s.titulo === "La jornada y cómo se calcula tu remuneración");
    expect(sec).toBeDefined();
    const texto = (sec?.bloques ?? []).map((b) => ("texto" in b ? b.texto : "")).join(" ");
    // La distinción entre las dos cifras es lo que evita que las horas 46 a 48
    // se vuelvan sobretiempo con recargo. Si alguien las iguala, esto salta.
    expect(texto).toContain("cuarenta y ocho (48) horas semanales");
    expect(texto).toContain("45 horas semanales");
    expect(texto).toContain("no constituye condición más beneficiosa");
  });

  it("aclara que la remuneración de la categoría es por el horario completo", () => {
    const doc = construirDocumento(cuadro(), "2026-08-07");
    const sec = doc.secciones.find((s) => s.titulo === "La jornada y cómo se calcula tu remuneración");
    const texto = (sec?.bloques ?? []).map((b) => ("texto" in b ? b.texto : "")).join(" ");
    // Sin esta frase, el documento promete que ninguna categoría baja de la RMV
    // mientras el sistema paga por horas: dos afirmaciones que se contradicen
    // para quien trabaja menos del horario completo.
    expect(texto).toContain("corresponde al horario completo del periodo");
    expect(texto).toContain("parte proporcional");
  });

  it("la jornada va antes de los conceptos no remunerativos", () => {
    const doc = construirDocumento(cuadro(), "2026-08-07");
    const titulos = doc.secciones.map((s) => s.titulo);
    const iJornada = titulos.indexOf("La jornada y cómo se calcula tu remuneración");
    const iConceptos = titulos.indexOf("Lo que se recibe además de la remuneración");
    expect(iJornada).toBeGreaterThan(-1);
    expect(iJornada).toBeLessThan(iConceptos);
  });
});

// ============================================================================
// El documento publicado se ve igual que el que se va a publicar
// ============================================================================
// La 0141 congela el documento como texto para que las constancias apunten a
// algo inmutable. Pero se guardaba texto PLANO —títulos en mayúsculas, tablas
// con `|`, guiones de subrayado— y la pantalla lo mostraba en un <pre>: el
// documento se veía peor DESPUÉS de publicarlo que antes.
//
// Guardarlo como JSON cumple lo mismo —también es texto, también es inmutable—
// y conserva la estructura, así que se pinta con el mismo renderizador. Estas
// pruebas fijan las dos mitades: que el viaje de ida y vuelta no pierda nada, y
// que lo publicado con el formato viejo se siga pudiendo leer.
// ============================================================================
describe("cómo se congela el documento al publicarlo", () => {
  const cuadroPropio = (): Cuadro => ({
    categorias: [
      { ...cat("colibri", 1, 1130), personas: 13 },
      { ...cat("cayla", 2, 1185), personas: 5 },
      { ...cat("archicaylo", 6, 1500), personas: 1 },
    ],
    movilidad: [{ sede: "LIM", valor: 12 }],
    brecha: 1.33,
  });
  const doc = () => construirDocumento(cuadroPropio(), "2026-08-07");

  it("guardar y recuperar devuelve el mismo documento, sin perder nada", () => {
    const original = doc();
    const recuperado = documentoDesdeGuardado(documentoAJson(original));
    expect(recuperado).toEqual(original);
  });

  it("conserva las tablas como tablas, no como texto con barras", () => {
    const recuperado = documentoDesdeGuardado(documentoAJson(doc()));
    const escala = recuperado?.secciones.find((s) => s.titulo === "La escala");
    const tabla = escala?.bloques.find((b) => b.tipo === "tabla");
    expect(tabla?.tipo).toBe("tabla");
  });

  it("una versión guardada con el formato viejo devuelve null, para mostrarla tal cual", () => {
    // Las que la gente ya firmó se siguen leyendo como se firmaron: no se tocan.
    expect(documentoDesdeGuardado("CUADRO DE CATEGORÍAS\n----\nTexto plano")).toBeNull();
  });

  it("un JSON que no es un documento tampoco pasa", () => {
    // Empieza con `{` y parsea, pero no tiene la forma: no alcanza con que sea
    // JSON válido para tratarlo como documento.
    expect(documentoDesdeGuardado('{"algo":1}')).toBeNull();
    expect(documentoDesdeGuardado("{ roto")).toBeNull();
  });
});

// ============================================================================
// El documento no puede convertir el horario de 45 h en la jornada pactada
// ============================================================================
// Felipe lo levantó el 2026-08-08, al decidir reforzar en el documento que CAYLA
// programa 45 horas cuando la ley permite 48: «cuidado, las legales y las de
// contrato siguen siendo 48 horas, que nunca nos juegue en contra».
//
// El riesgo es real y de dos filos. Cuanto más se destaca el beneficio, más se
// parece a una condición consolidada — y si alguien llegara a sostener que la
// jornada pactada de CAYLA son 45 h, las horas 46, 47 y 48 pasarían a ser
// sobretiempo con recargo del 25 % / 35 % para todo el equipo, todas las semanas.
//
// Por eso el documento tiene que decir SIEMPRE tres cosas juntas, y estas
// pruebas no dejan que se caiga ninguna al reescribir la sección:
//
//   1. la jornada ordinaria es 48 y es la del contrato;
//   2. el horario de 45 es una decisión de la empresa, sin derecho adquirido;
//   3. el sobretiempo se cuenta desde la hora 49, no desde la 46.
//
// Las tres se ganan por escrito, no por omisión: un documento que solo callara
// el punto 3 seguiría siendo cierto y sería mucho más fácil de discutir.
describe("la sección de jornada se blinda sola", () => {
  // Fixture propio: `cuadro()` vive dentro de otro describe y no se ve desde
  // acá. Esta sección no depende de las categorías, así que basta una.
  const cuadroMinimo = (): Cuadro => ({
    categorias: [{ ...cat("colibri", 1, 1130), personas: 13 }],
    movilidad: [],
    brecha: null,
  });

  const jornada = (): string => {
    const doc = construirDocumento(cuadroMinimo(), "2026-08-08");
    const s = doc.secciones.find((x) => x.titulo.includes("jornada"));
    if (s === undefined) throw new Error("no hay sección de jornada");
    return s.bloques
      .map((b) => (b.tipo === "parrafo" || b.tipo === "destacado" ? b.texto : ""))
      .join(" ");
  };

  it("dice que la jornada ordinaria es de 48 horas y que es la del contrato", () => {
    const t = jornada();
    expect(t).toContain("cuarenta y ocho (48) horas semanales");
    expect(t).toContain("Es la jornada que figura en tu contrato de trabajo");
  });

  it("dice que el horario de 45 NO es condición más beneficiosa ni derecho adquirido", () => {
    const t = jornada();
    expect(t).toContain("no constituye condición más beneficiosa");
    expect(t).toContain("no genera derecho adquirido");
    expect(t).toContain("no modifica la jornada establecida en tu contrato");
  });

  it("dice que el sobretiempo empieza en la hora 49, no en la 46", () => {
    // Esta es la que se puede perder al reescribir «para que quede más corto»,
    // y es la que traduce el blindaje jurídico a algo operativo.
    expect(jornada()).toContain("desde la hora 49 de la semana y no desde la 46");
  });

  it("nunca llama «jornada» a las 45 horas: eso es el HORARIO", () => {
    // La palabra importa. «Jornada de 45 horas» es exactamente la frase que
    // convertiría las horas 46 a 48 en sobretiempo.
    const t = jornada().toLowerCase();
    expect(t).not.toContain("jornada de 45");
    expect(t).not.toContain("jornada ordinaria es de 45");
    expect(t).not.toContain("jornada de cuarenta y cinco");
  });

  it("y avisa del cambio en el neto antes de que llegue la boleta", () => {
    const t = jornada();
    expect(t).toContain("un neto algo menor");
    expect(t).toContain("no se queda en CAYLA");
  });
});


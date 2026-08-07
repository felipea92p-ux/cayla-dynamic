// ============================================================================
// mensaje-error.test.ts — Los mensajes que sí tienen que llegar enteros
// ============================================================================
// `mensajeDeError` decide qué texto ve una persona cuando algo falla. Hace UNA
// distinción, y de esa distinción depende que el terminal siga siendo usable:
//
//   · Los mensajes que escribimos nosotros en las funciones SQL llegan con el
//     código P0001. Están en español y dicen qué hacer. Pasan TAL CUAL.
//   · Todo lo demás —constraints, permisos, sintaxis— es Postgres hablando
//     solo. Se traduce, porque «violates foreign key constraint» no le dice
//     nada a la encargada de TRU y de paso publica cómo se llaman las tablas.
//
// POR QUÉ ESTE ARCHIVO. El 2026-08-05 las cuatro rutas de API pasaron a usar
// esta función. Si alguien "simplifica" la rama P0001, el kiosco deja de decir
// «no hay una salida final de hoy para reabrir» y empieza a decir «el sistema
// no pudo completar la operación» — y quien está parada ahí tiene que llamar a
// la encargada para averiguar algo que la pantalla sabía.
//
// Los cinco primeros casos son los mensajes REALES de fn_reabrir_dia, copiados
// de la función. Si cambian allá, esta prueba se cae y hay que mirarlos.
// ============================================================================
import { describe, it, expect } from "vitest";
import { mensajeDeError, esFallaDeRed } from "../apps/web/lib/admin/mensaje-error";

const MENSAJES_DEL_KIOSCO = [
  "El motivo del regreso es obligatorio.",
  "Esta operación solo se hace desde una terminal activa.",
  "No hay una salida final de hoy para reabrir.",
  "Esa marca es de otra sede: se reabre desde la terminal donde se marcó.",
  "Ese día cae en un periodo ya PAGADO: reabrirlo alteraría una planilla pagada. Reabre el periodo primero.",
];

describe("los mensajes escritos para una persona llegan enteros", () => {
  for (const texto of MENSAJES_DEL_KIOSCO) {
    it(`pasa tal cual: «${texto.slice(0, 45)}…»`, () => {
      expect(mensajeDeError({ message: texto, code: "P0001" })).toBe(texto);
    });
  }

  it("no le antepone «no se pudo» aunque se le pase una acción", () => {
    // Anteponer algo a un mensaje ya redactado lo empeora: quedaría
    // «No se pudo reabrir el día: No hay una salida final de hoy para reabrir.»
    const texto = "No hay una salida final de hoy para reabrir.";
    expect(mensajeDeError({ message: texto, code: "P0001" }, "reabrir el día")).toBe(texto);
  });

  // ⇩ Esta comprobación existe porque las cinco de arriba NO alcanzan.
  // Se descubrió desactivando la rama P0001 a propósito: las cinco seguían en
  // verde, porque un mensaje en español y sin jerga vuelve a salir entero por
  // el otro camino de la función. Verificaban el resultado, no el mecanismo —
  // y el día que el mecanismo se rompa de verdad no avisarían.
  //
  // El texto es artificial a propósito: lleva una palabra que el filtro de jerga
  // bloquea. Solo la rama P0001 puede dejarlo pasar. Si alguien la quita, esta
  // se cae sola.
  it("un mensaje nuestro pasa aunque contenga una palabra de la lista negra", () => {
    const texto = "Esa fecha no existe en el calendario: column no es una fecha válida.";
    expect(mensajeDeError({ message: texto, code: "P0001" })).toBe(texto);
  });
});

describe("lo que Postgres dice solo, no sale a la pantalla", () => {
  const CRUDOS = [
    { code: "23503", message: 'insert or update on table "personas" violates foreign key constraint "personas_sede_base_id_fkey"' },
    { code: "23505", message: 'duplicate key value violates unique constraint "idx_asignaciones_educacion_unica"' },
    { code: "42501", message: "permission denied for table planilla_periodos" },
    { code: "42P01", message: 'relation "topes_educacion_rango" does not exist' },
  ];

  for (const err of CRUDOS) {
    it(`no filtra el detalle del código ${err.code}`, () => {
      const salida = mensajeDeError(err);
      expect(salida).not.toBe(err.message);
      // Lo que no puede salir: nombres de tablas, de constraints, ni la jerga.
      expect(salida).not.toMatch(/violates|constraint|relation|permission denied/i);
      expect(salida.length).toBeGreaterThan(0);
    });
  }

  it("un error sin código y con jerga tampoco se muestra crudo", () => {
    const salida = mensajeDeError({ message: 'column "sueldo_base_legal" does not exist' });
    expect(salida).not.toMatch(/column|does not exist/i);
  });

  it("pero un mensaje sin código y sin jerga sí se muestra: suele ser nuestro", () => {
    const texto = "Ya existe una asignación vigente para esa persona.";
    expect(mensajeDeError({ message: texto })).toBe(texto);
  });
});

describe("un constraint con nombre dice qué regla se rompió", () => {
  // El texto EXACTO que devuelve Postgres al rechazar una fecha de fin de contrato
  // anterior al ingreso. Es lo que veía quien llenaba ese campo desde la pantalla
  // de Equipo antes de traducirlo.
  const CRUDO = {
    code: "23514",
    message:
      'new row for relation "personas" violates check constraint "personas_fin_contrato_coherente"',
  };

  it("no muestra el nombre del constraint ni la jerga", () => {
    const salida = mensajeDeError(CRUDO);
    expect(salida).not.toMatch(/violates|constraint|relation|personas_/i);
  });

  it("dice cuál es la regla, no «revisa las fechas y los números»", () => {
    // El 23514 genérico es honesto e inútil: no dice QUÉ fecha está mal. Si
    // alguien quita la traducción por nombre, esta prueba se cae.
    expect(mensajeDeError(CRUDO)).toMatch(/no puede terminar antes/i);
  });

  it("y sigue anteponiendo la acción que se intentaba", () => {
    expect(mensajeDeError(CRUDO, "guardar")).toMatch(/^No se pudo guardar: /);
  });

  it("un 23514 de un constraint sin traducción sigue cayendo en el texto genérico", () => {
    const otro = {
      code: "23514",
      message: 'new row for relation "personas" violates check constraint "personas_movilidad_con_motivo"',
    };
    expect(mensajeDeError(otro)).not.toMatch(/no puede terminar antes/i);
    expect(mensajeDeError(otro)).not.toMatch(/violates|constraint/i);
  });

  // El constraint del cese: es el que abre el comentario de mensaje-error.ts como
  // ejemplo de lo que NO se puede mostrar, y el que hacía fallar «Desactivar»
  // hasta el 2026-08-06.
  it("el del cese dice qué falta, no cómo se llama", () => {
    const cese = {
      code: "23514",
      message: 'new row for relation "personas" violates check constraint "personas_cese_coherente"',
    };
    expect(mensajeDeError(cese)).toMatch(/último día trabajado/i);
    expect(mensajeDeError(cese)).not.toMatch(/violates|constraint|personas_/i);
  });
});

describe("quedarse sin internet no se confunde con un dato mal puesto", () => {
  it("reconoce la falla de red", () => {
    expect(esFallaDeRed({ message: "Failed to fetch" })).toBe(true);
  });

  it("y no marca como red un error que sí tiene código", () => {
    expect(esFallaDeRed({ message: "Failed to fetch", code: "23505" })).toBe(false);
  });
});

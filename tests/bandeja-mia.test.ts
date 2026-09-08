// ============================================================================
// bandeja-mia.test.ts — El buzón de respuestas de cada persona
// ============================================================================
// La Bandeja junta en un hilo tres cosas que hasta hoy vivían cada una en su
// rincón: la solicitud de cambio de perfil (0399, con sus documentos), la de
// vacaciones (0330) y la petición de revisar un día (0257). Ninguna de las tres
// se le anunciaba a la persona: había que acordarse de volver a la pantalla
// donde la pediste para ver si te contestaron.
//
// QUÉ SE PRUEBA ACÁ, Y POR QUÉ NO SE VE MIRANDO LA PANTALLA
//
// 1. EL EMPATE. Desarrollo Organizacional aprueba varias solicitudes de una
//    sentada, y las resueltas en la misma transacción comparten `resuelta_at`
//    al microsegundo. Sin desempate, cuál sale primero lo decide el orden en
//    que llegaron las tres consultas — o sea el azar de la red. Es la misma
//    familia de defectos que las migraciones 0386-0389 cerraron en el SQL, y
//    aparece igual acá arriba en cuanto se fusionan tres hilos.
//
// 2. EL CONTADOR. El número del botón «Bandeja» y la marca «nuevo» de cada
//    tarjeta salen de la MISMA función a propósito: dos definiciones de
//    «nuevo» que puedan separarse es el defecto de fondo, no el síntoma.
//
// 3. LO PENDIENTE NUNCA ES NUEVO. Un pedido que hiciste tú no es una novedad
//    para ti; ponerlo en el contador enseña a ignorar el contador.
// ============================================================================
import { describe, expect, it } from "vitest";
import { armarBandeja, DIAS_NOVEDAD } from "@/lib/bandeja-mia";

const HOY = "2026-09-08";

/** Un instante de Lima, para no escribir la conversión a mano en cada caso. */
function enLima(fecha: string, hora = "10:00"): string {
  return `${fecha}T${hora}:00-05:00`;
}

const VACIO = { perfil: [], vacaciones: [], revisiones: [] };

describe("armarBandeja", () => {
  it("sin nada que decir, no dice nada — y el contador es cero", () => {
    const b = armarBandeja(VACIO, HOY);
    expect(b.respuestas).toEqual([]);
    expect(b.esperando).toEqual([]);
    expect(b.nuevas).toBe(0);
  });

  it("un rechazo trae el motivo íntegro, que es lo único que explica el no", () => {
    const b = armarBandeja({
      ...VACIO,
      perfil: [{
        id: "p1", etiqueta: "Cuenta bancaria", estado: "rechazado",
        creada_at: enLima("2026-09-01"), resuelta_at: enLima("2026-09-07"),
        motivo: "La carátula está a nombre de otra persona.",
      }],
    }, HOY);

    expect(b.respuestas).toHaveLength(1);
    expect(b.respuestas[0].estado).toBe("rechazado");
    expect(b.respuestas[0].titulo).toContain("Cuenta bancaria");
    expect(b.respuestas[0].respuesta).toBe("La carátula está a nombre de otra persona.");
  });

  it("una aprobación no inventa un texto que nadie escribió", () => {
    const b = armarBandeja({
      ...VACIO,
      perfil: [{
        id: "p1", etiqueta: "Celular", estado: "aprobado",
        creada_at: enLima("2026-09-01"), resuelta_at: enLima("2026-09-07"), motivo: null,
      }],
    }, HOY);

    expect(b.respuestas[0].estado).toBe("aprobado");
    expect(b.respuestas[0].respuesta).toBeNull();
  });

  it("ordena por cuándo TE RESPONDIERON, no por cuándo lo pediste", () => {
    const b = armarBandeja({
      perfil: [{
        id: "p1", etiqueta: "Celular", estado: "aprobado",
        creada_at: enLima("2026-08-01"), resuelta_at: enLima("2026-09-07"), motivo: null,
      }],
      vacaciones: [{
        id: "v1", fecha_inicio: "2026-10-05", fecha_fin: "2026-10-09", estado: "aprobada",
        pedida_at: enLima("2026-09-05"), resuelta_at: enLima("2026-09-06"), respuesta: null,
      }],
      revisiones: [],
    }, HOY);

    // El perfil se pidió cinco semanas antes que las vacaciones y se respondió
    // un día después: manda la respuesta.
    expect(b.respuestas.map((m) => m.origen)).toEqual(["perfil", "vacaciones"]);
  });

  it("dos respuestas del mismo instante no dependen del orden en que llegaron", () => {
    // DO aprueba las dos de una sentada: mismo `resuelta_at` al microsegundo.
    const mismoInstante = enLima("2026-09-07", "16:30");
    const fuentes = {
      perfil: [
        {
          id: "aaaa", etiqueta: "Celular", estado: "aprobado",
          creada_at: enLima("2026-09-01"), resuelta_at: mismoInstante, motivo: null,
        },
        {
          id: "bbbb", etiqueta: "Dirección", estado: "aprobado",
          creada_at: enLima("2026-09-01"), resuelta_at: mismoInstante, motivo: null,
        },
      ],
      vacaciones: [{
        id: "zzzz", fecha_inicio: "2026-10-05", fecha_fin: "2026-10-09", estado: "aprobada",
        pedida_at: enLima("2026-09-01"), resuelta_at: mismoInstante, respuesta: null,
      }],
      revisiones: [],
    };

    const derecho = armarBandeja(fuentes, HOY).respuestas.map((m) => m.clave);
    // La misma pregunta con las listas al revés — que es lo que pasa cuando las
    // tres consultas vuelven en otro orden.
    const alReves = armarBandeja(
      { ...fuentes, perfil: [...fuentes.perfil].reverse() },
      HOY,
    ).respuestas.map((m) => m.clave);

    expect(derecho).toEqual(alReves);
  });

  it("lo que sigue pendiente va a «esperando», nunca al hilo de respuestas", () => {
    const b = armarBandeja({
      ...VACIO,
      vacaciones: [{
        id: "v1", fecha_inicio: "2026-10-05", fecha_fin: "2026-10-09", estado: "pendiente",
        pedida_at: enLima("2026-09-06"), resuelta_at: null, respuesta: null,
      }],
    }, HOY);

    expect(b.respuestas).toEqual([]);
    expect(b.esperando).toHaveLength(1);
    expect(b.esperando[0].estado).toBe("pendiente");
  });

  it("lo pendiente NUNCA cuenta como nuevo, ni pedido hoy mismo", () => {
    const b = armarBandeja({
      ...VACIO,
      revisiones: [{
        id: "r1", fecha: "2026-09-08", pedida_at: enLima(HOY), atendida_at: null, respuesta: null,
      }],
    }, HOY);

    expect(b.esperando[0].nuevo).toBe(false);
    expect(b.nuevas).toBe(0);
  });

  it("la novedad caduca sola: el último día adentro cuenta, el siguiente ya no", () => {
    const alBorde = "2026-08-25";   // 14 días antes de HOY
    const pasado = "2026-08-24";    // 15 — ya no

    const dentro = armarBandeja({
      ...VACIO,
      perfil: [{
        id: "p1", etiqueta: "Celular", estado: "aprobado",
        creada_at: enLima("2026-08-20"), resuelta_at: enLima(alBorde), motivo: null,
      }],
    }, HOY);
    const fuera = armarBandeja({
      ...VACIO,
      perfil: [{
        id: "p1", etiqueta: "Celular", estado: "aprobado",
        creada_at: enLima("2026-08-20"), resuelta_at: enLima(pasado), motivo: null,
      }],
    }, HOY);

    expect(DIAS_NOVEDAD).toBe(14);
    expect(dentro.respuestas[0].nuevo).toBe(true);
    expect(dentro.nuevas).toBe(1);
    expect(fuera.respuestas[0].nuevo).toBe(false);
    expect(fuera.nuevas).toBe(0);
  });

  it("«reemplazada» y «cancelada» no son respuestas: nadie le contestó nada", () => {
    const b = armarBandeja({
      perfil: [{
        id: "p1", etiqueta: "Celular", estado: "reemplazada",
        creada_at: enLima("2026-09-01"), resuelta_at: enLima("2026-09-06"), motivo: null,
      }],
      vacaciones: [{
        id: "v1", fecha_inicio: "2026-10-05", fecha_fin: "2026-10-09", estado: "cancelada",
        pedida_at: enLima("2026-09-01"), resuelta_at: enLima("2026-09-06"), respuesta: null,
      }],
      revisiones: [],
    }, HOY);

    expect(b.respuestas).toEqual([]);
    expect(b.esperando).toEqual([]);
    expect(b.nuevas).toBe(0);
  });

  it("el contador y la marca de cada tarjeta no pueden discrepar", () => {
    const b = armarBandeja({
      perfil: [{
        id: "p1", etiqueta: "Celular", estado: "aprobado",
        creada_at: enLima("2026-08-01"), resuelta_at: enLima("2026-09-07"), motivo: null,
      }],
      vacaciones: [{
        id: "v1", fecha_inicio: "2026-07-05", fecha_fin: "2026-07-09", estado: "rechazada",
        pedida_at: enLima("2026-06-20"), resuelta_at: enLima("2026-06-25"),
        respuesta: "Ya hay dos personas fuera esa semana.",
      }],
      revisiones: [{
        id: "r1", fecha: "2026-09-02", pedida_at: enLima("2026-09-03"),
        atendida_at: enLima("2026-09-04"), respuesta: "Se agregó tu salida de las 17:30.",
      }],
    }, HOY);

    expect(b.nuevas).toBe(b.respuestas.filter((m) => m.nuevo).length);
    expect(b.nuevas).toBe(2); // el perfil y la revisión; las vacaciones son de junio
  });

  it("una revisión atendida dice qué día se revisó, que es lo que ella pidió", () => {
    const b = armarBandeja({
      ...VACIO,
      revisiones: [{
        id: "r1", fecha: "2026-09-02", pedida_at: enLima("2026-09-03"),
        atendida_at: enLima("2026-09-04"), respuesta: "Se agregó tu salida de las 17:30.",
      }],
    }, HOY);

    expect(b.respuestas[0].titulo).toContain("2 de setiembre");
    expect(b.respuestas[0].respuesta).toBe("Se agregó tu salida de las 17:30.");
  });
});

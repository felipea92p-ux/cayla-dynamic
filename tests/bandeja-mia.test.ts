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
//
// 4. LO QUE DEPENDE DE ELLA NO CADUCA (2026-09-08). Un contrato sin firmar,
//    un memo por firmar, una constancia de ley y los días con el marcaje roto
//    entran por otra puerta: cuentan desde el primer día y siguen contando el
//    día 90. «Leído» ahí no es «lo miré», es «lo firmé» — y eso ya estaba
//    guardado desde antes, así que esta parte no necesitó ninguna migración.
//    La prueba que importa es la que comprueba que NO caducan: si algún día
//    alguien les aplica DIAS_NOVEDAD «por consistencia», el aviso se apagaría
//    justo cuando lleva tres meses sin resolverse.
// ============================================================================
import { describe, expect, it } from "vitest";
import { armarBandeja, DIAS_NOVEDAD } from "@/lib/bandeja-mia";

const HOY = "2026-09-08";

/** Un instante de Lima, para no escribir la conversión a mano en cada caso. */
function enLima(fecha: string, hora = "10:00"): string {
  return `${fecha}T${hora}:00-05:00`;
}

const VACIO = {
  perfil: [], vacaciones: [], revisiones: [],
  contrato: null, memos: [], acuses: [], marcajes: [], periodo: null,
};

describe("armarBandeja", () => {
  it("sin nada que decir, no dice nada — y el contador es cero", () => {
    const b = armarBandeja(VACIO, HOY);
    expect(b.respuestas).toEqual([]);
    expect(b.esperando).toEqual([]);
    expect(b.avisos).toBe(0);
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
      ...VACIO,
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
      ...VACIO,
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
    expect(b.avisos).toBe(0);
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
    expect(dentro.avisos).toBe(1);
    expect(fuera.respuestas[0].nuevo).toBe(false);
    expect(fuera.avisos).toBe(0);
  });

  it("«reemplazada» y «cancelada» no son respuestas: nadie le contestó nada", () => {
    const b = armarBandeja({
      ...VACIO,
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
    expect(b.avisos).toBe(0);
  });

  it("el contador y la marca de cada tarjeta no pueden discrepar", () => {
    const b = armarBandeja({
      ...VACIO,
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

    expect(b.avisos).toBe(b.respuestas.filter((m) => m.nuevo).length);
    expect(b.avisos).toBe(2); // el perfil y la revisión; las vacaciones son de junio
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

  // ── LO QUE DEPENDE DE ELLA ───────────────────────────────────────────────

  it("un contrato sin confirmar la firma es un pendiente, y su enlace lleva a firmarlo", () => {
    const b = armarBandeja({
      ...VACIO,
      contrato: {
        id: "c1", tipo: "convenio_practicas",
        fecha_inicio: "2026-12-08", fecha_fin: "2027-03-07",
        generado_at: enLima("2026-09-08"), firma_persona_confirmada_at: null,
      },
    }, HOY);

    expect(b.pendientes).toHaveLength(1);
    expect(b.pendientes[0].origen).toBe("contrato");
    expect(b.pendientes[0].estado).toBe("por_firmar");
    expect(b.pendientes[0].ir).toBe("/mio/contrato");
    expect(b.avisos).toBe(1);
    // Y no se cuela en el hilo de respuestas: nadie le respondió nada.
    expect(b.respuestas).toEqual([]);
  });

  it("el contrato firmado desaparece — «leído» es «firmado», no «lo miré»", () => {
    const b = armarBandeja({
      ...VACIO,
      contrato: {
        id: "c1", tipo: "indefinido",
        fecha_inicio: "2026-04-01", fecha_fin: null,
        generado_at: enLima("2026-04-01"),
        firma_persona_confirmada_at: enLima("2026-04-02"),
      },
    }, HOY);

    expect(b.pendientes).toEqual([]);
    expect(b.avisos).toBe(0);
  });

  it("lo que depende de ella NO caduca: a los tres meses sigue contando", () => {
    // Muy por fuera de DIAS_NOVEDAD. Una respuesta de esta fecha ya no contaría;
    // un contrato sin firmar sí, y esa diferencia es el corazón del cambio.
    const haceTresMeses = enLima("2026-06-05");
    expect(DIAS_NOVEDAD).toBeLessThan(90);

    const b = armarBandeja({
      ...VACIO,
      contrato: {
        id: "c1", tipo: "nuevo", fecha_inicio: "2026-06-05", fecha_fin: "2026-12-04",
        generado_at: haceTresMeses, firma_persona_confirmada_at: null,
      },
    }, HOY);

    expect(b.pendientes).toHaveLength(1);
    expect(b.pendientes[0].nuevo).toBe(true);
    expect(b.avisos).toBe(1);
  });

  it("el memo por firmar no dice de qué es: cualquiera puede ver esa pantalla de reojo", () => {
    const b = armarBandeja({
      ...VACIO,
      memos: [{
        id: "m1", nivel: "suspension", entregado_at: enLima("2026-09-05"),
        firma_sancionado_confirmada_at: null, sancionado_rechazo_firma_at: null,
      }],
    }, HOY);

    expect(b.pendientes).toHaveLength(1);
    expect(b.pendientes[0].origen).toBe("memo");
    // Ni el nivel ni la causa aparecen en el título ni en el detalle.
    const texto = `${b.pendientes[0].titulo} ${b.pendientes[0].detalle ?? ""}`.toLowerCase();
    expect(texto).not.toContain("suspensi");
  });

  it("negarse a firmar CIERRA el memo: es una respuesta con valor legal, no un pendiente eterno", () => {
    const b = armarBandeja({
      ...VACIO,
      memos: [
        {
          id: "m1", nivel: "amonestacion", entregado_at: enLima("2026-09-05"),
          firma_sancionado_confirmada_at: null, sancionado_rechazo_firma_at: enLima("2026-09-06"),
        },
        // Una anotación no lleva firma del sancionado: nunca es un pendiente.
        {
          id: "m2", nivel: "anotacion", entregado_at: enLima("2026-09-05"),
          firma_sancionado_confirmada_at: null, sancionado_rechazo_firma_at: null,
        },
      ],
    }, HOY);

    expect(b.pendientes).toEqual([]);
  });

  it("los días con el marcaje incompleto van en UN mensaje, y solo los del periodo abierto", () => {
    const b = armarBandeja({
      ...VACIO,
      periodo: { fecha_ini: "2026-08-29", fecha_fin: "2026-09-27" },
      marcajes: [
        // Dentro del periodo y rotos: estos dos cuentan.
        { fecha: "2026-09-02", estado: "auto_cerrada_pendiente", horas_trabajadas: 7 },
        { fecha: "2026-09-04", estado: "cerrada", horas_trabajadas: null },
        // Dentro del periodo y sano.
        { fecha: "2026-09-05", estado: "cerrada", horas_trabajadas: 8 },
        // Roto pero de un periodo ya cerrado: no hay nada que arreglar a tiempo.
        { fecha: "2026-08-11", estado: "cerrada", horas_trabajadas: null },
        // Su jornada de HOY, todavía abierta: está trabajando, no está roto.
        { fecha: HOY, estado: "abierta", horas_trabajadas: null },
      ],
    }, HOY);

    expect(b.pendientes).toHaveLength(1);
    expect(b.pendientes[0].origen).toBe("marcaje");
    expect(b.pendientes[0].titulo).toBe("2 días con el marcaje incompleto");
    expect(b.pendientes[0].detalle).toContain("2 de setiembre");
    expect(b.pendientes[0].detalle).toContain("4 de setiembre");
    expect(b.pendientes[0].detalle).not.toContain("11 de agosto");
    // UN mensaje, y por tanto UN aviso: un mes malo no puede comerse el número
    // entero y tapar el contrato sin firmar, que aprieta mucho más.
    expect(b.avisos).toBe(1);
  });

  it("sin periodo de pago abierto no se avisa de marcajes: ya no se pueden arreglar", () => {
    const b = armarBandeja({
      ...VACIO,
      periodo: null,
      marcajes: [{ fecha: "2026-09-04", estado: "cerrada", horas_trabajadas: null }],
    }, HOY);

    expect(b.pendientes).toEqual([]);
  });

  it("el memo va antes que el contrato, y el contrato antes que la constancia", () => {
    // El orden no es estético: es lo que ve primero quien abre con cuatro cosas.
    // El memo corre un plazo legal en contra de ELLA; la constancia es una
    // obligación de la empresa; el marcaje espera al cierre del periodo.
    const b = armarBandeja({
      ...VACIO,
      periodo: { fecha_ini: "2026-08-29", fecha_fin: "2026-09-27" },
      marcajes: [{ fecha: "2026-09-04", estado: "cerrada", horas_trabajadas: null }],
      acuses: [{ clave: "acuse:politica:3", titulo: "Política salarial", detalle: "", href: "/admin/politica-salarial" }],
      contrato: {
        id: "c1", tipo: "nuevo", fecha_inicio: "2026-09-01", fecha_fin: "2027-02-28",
        generado_at: enLima("2026-09-01"), firma_persona_confirmada_at: null,
      },
      memos: [{
        id: "m1", nivel: "verbal", entregado_at: enLima("2026-09-06"),
        firma_sancionado_confirmada_at: null, sancionado_rechazo_firma_at: null,
      }],
    }, HOY);

    expect(b.pendientes.map((m) => m.origen)).toEqual(["memo", "contrato", "acuse", "marcaje"]);
    expect(b.avisos).toBe(4);
  });

  it("el número suma las dos cosas: lo que falta hacer y lo que respondieron estos días", () => {
    const b = armarBandeja({
      ...VACIO,
      contrato: {
        id: "c1", tipo: "nuevo", fecha_inicio: "2026-09-01", fecha_fin: "2027-02-28",
        generado_at: enLima("2026-09-01"), firma_persona_confirmada_at: null,
      },
      perfil: [{
        id: "p1", etiqueta: "Celular", estado: "aprobado",
        creada_at: enLima("2026-08-30"), resuelta_at: enLima("2026-09-07"), motivo: null,
      }],
      // De junio: ya caducó, no suma.
      vacaciones: [{
        id: "v1", fecha_inicio: "2026-07-05", fecha_fin: "2026-07-09", estado: "rechazada",
        pedida_at: enLima("2026-06-20"), resuelta_at: enLima("2026-06-25"), respuesta: "No.",
      }],
    }, HOY);

    expect(b.avisos).toBe(b.pendientes.length + b.respuestas.filter((m) => m.nuevo).length);
    expect(b.avisos).toBe(2);
  });
});

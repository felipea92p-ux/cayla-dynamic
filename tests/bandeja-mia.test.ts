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
import {
  armarBandeja, DIAS_NOVEDAD, type FilaBoletaBandeja, type FilaEducacionEntrega, type FilaEducacionSituacion,
} from "@/lib/bandeja-mia";
import { mostrarBonoEnInfo, puedePedirBono, type MiBono } from "@/lib/mi-bono";

const HOY = "2026-09-08";

/** Un instante de Lima, para no escribir la conversión a mano en cada caso. */
function enLima(fecha: string, hora = "10:00"): string {
  return `${fecha}T${hora}:00-05:00`;
}

const VACIO = {
  perfil: [], vacaciones: [], revisiones: [],
  contrato: null, memos: [], acuses: [], marcajes: [], periodo: null,
  movilidad: null, revisionesMovilidad: [], turnos: [],
  vistos: new Set<string>(),
};

// ── Las constancias de estudios (0450) ─────────────────────────────────────
// Lo que importa acá no es que aparezcan: es que un mismo rechazo NO avise dos
// veces (como respuesta y como pendiente), y que lo que carga DO a su nombre no
// se le anuncie como si ella hubiera pedido algo.
describe("armarBandeja · constancias de estudios", () => {
  const entrega = (x: Partial<FilaEducacionEntrega>): FilaEducacionEntrega => ({
    id: "e1", familia_id: "f1", institucion: "UPN", fecha_pago: "2026-09-05",
    estado: "aprobada", origen: "colaboradora",
    enviada_at: enLima("2026-09-05"), revisada_at: enLima("2026-09-07"),
    motivo_categoria: null, motivo_comentario: null, ...x,
  });
  const estudio = (x: Partial<FilaEducacionSituacion>): FilaEducacionSituacion => ({
    familia_id: "f1", persona_id: "yo", institucion: "UPN",
    estado_constancia: "al_dia", fecha_pago_constancia: null, plazo: null, ...x,
  });

  it("una aprobada reciente es una respuesta que lleva a ese estudio", () => {
    const b = armarBandeja({ ...VACIO, educacionEntregas: [entrega({})] }, HOY);
    expect(b.respuestas).toHaveLength(1);
    expect(b.respuestas[0].estado).toBe("aprobado");
    expect(b.respuestas[0].ir).toBe("/mio/educacion?familia=f1");
    expect(b.avisos).toBe(1);
  });

  it("un rechazo reciente avisa UNA vez, con categoría y comentario como respuesta", () => {
    const b = armarBandeja({
      ...VACIO,
      educacionEntregas: [entrega({ estado: "rechazada", motivo_categoria: "ilegible", motivo_comentario: "No se ve el monto" })],
      educacionSituacion: [estudio({ estado_constancia: "rechazada", fecha_pago_constancia: "2026-09-05" })],
    }, HOY);
    expect(b.respuestas).toHaveLength(1);
    expect(b.respuestas[0].respuesta).toBe("No se lee: No se ve el monto");
    expect(b.pendientes).toHaveLength(0);
    expect(b.avisos).toBe(1);
  });

  it("un rechazo viejo ya no es novedad, pero la corrección sigue pendiente", () => {
    const b = armarBandeja({
      ...VACIO,
      educacionEntregas: [entrega({ estado: "rechazada", revisada_at: enLima("2026-07-01"), motivo_categoria: "otro", motivo_comentario: "Falta el sello" })],
      educacionSituacion: [estudio({ estado_constancia: "rechazada", fecha_pago_constancia: "2026-06-30" })],
    }, HOY);
    expect(b.respuestas[0].nuevo).toBe(false);
    expect(b.pendientes).toHaveLength(1);
    expect(b.pendientes[0].origen).toBe("educacion");
    expect(b.avisos).toBe(1);
  });

  it("una constancia por subir depende de ella y no caduca", () => {
    const b = armarBandeja({
      ...VACIO,
      educacionSituacion: [estudio({ estado_constancia: "vencida", fecha_pago_constancia: "2026-05-05", plazo: "2026-05-22" })],
    }, HOY);
    expect(b.pendientes).toHaveLength(1);
    expect(b.pendientes[0].estado).toBe("por_arreglar");
    expect(b.pendientes[0].nuevo).toBe(true);
  });

  // 0526: el apoyo mensual pide la constancia del mes desde el día 1, con el pago todavía por venir.
  it("una constancia pedida antes del pago no dice que ya pagó, y pide algo igual", () => {
    const hoy = HOY;
    const futuro = "2026-09-28"; // un pago de este mismo mes (HOY es el 8), todavía por venir
    const b = armarBandeja({
      ...VACIO,
      educacionSituacion: [estudio({ estado_constancia: "falta_enviar", fecha_pago_constancia: futuro, plazo: futuro })],
    }, hoy);
    expect(b.pendientes).toHaveLength(1);
    expect(b.pendientes[0].titulo).toBe("Este mes toca la constancia de tu pago a UPN");
    expect(b.pendientes[0].detalle).toContain("Pagas el");
    expect(b.pendientes[0].detalle).not.toContain("Pago del");
    // «cuándo lo pediste» no puede ser una fecha que no llegó.
    expect(b.pendientes[0].fecha).toBe(hoy);
    expect(b.pendientes[0].nuevo).toBe(true);
  });

  it("la que ya pagó y falta la constancia sigue diciendo «Pago del»", () => {
    const b = armarBandeja({
      ...VACIO,
      educacionSituacion: [estudio({ estado_constancia: "falta_enviar", fecha_pago_constancia: "2026-05-05", plazo: "2026-05-22" })],
    }, HOY);
    expect(b.pendientes[0].titulo).toBe("Sube la constancia de tu pago a UPN");
    expect(b.pendientes[0].detalle).toContain("Pago del");
    expect(b.pendientes[0].fecha).toBe("2026-05-05");
  });

  it("al día o pendiente de revisión no le piden nada", () => {
    const b = armarBandeja({
      ...VACIO,
      educacionSituacion: [estudio({ estado_constancia: "al_dia" }), estudio({ familia_id: "f2", estado_constancia: "pendiente_revision" })],
    }, HOY);
    expect(b.pendientes).toHaveLength(0);
  });

  it("lo que carga DO a su nombre no se le anuncia", () => {
    const b = armarBandeja({ ...VACIO, educacionEntregas: [entrega({ origen: "do" })] }, HOY);
    expect(b.respuestas).toHaveLength(0);
    expect(b.avisos).toBe(0);
  });

  it("la que envió y espera revisión no suma al contador", () => {
    const b = armarBandeja({
      ...VACIO, educacionEntregas: [entrega({ estado: "pendiente", revisada_at: null })],
    }, HOY);
    expect(b.esperando).toHaveLength(1);
    expect(b.avisos).toBe(0);
  });
});

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

  // ── Un memo enviado a su Info (0486) ───────────────────────────────────────
  // ENVIAR NO ENTREGA: el memo todavía no es suyo hasta que ella lo confirma, y
  // lo único que la Bandeja puede hacer es decirle que hay algo esperándola.
  it("un memo enviado a su Info aparece como pendiente, sin decir de qué es, y lleva a abrirlo", () => {
    const b = armarBandeja({
      ...VACIO,
      memosPorRecibir: [{ id: "m9", enviado_a_info_at: enLima("2026-09-05") }],
    }, HOY);

    expect(b.pendientes).toHaveLength(1);
    expect(b.pendientes[0].origen).toBe("memo");
    expect(b.pendientes[0].titulo).toBe("Tienes un documento por recibir");
    expect(b.pendientes[0].ir).toBe("/mio/memo/m9");
    // Esta tarjeta la ve de reojo cualquiera que pase cerca de la pantalla.
    const texto = `${b.pendientes[0].titulo} ${b.pendientes[0].detalle ?? ""}`.toLowerCase();
    for (const palabra of ["suspensi", "amonesta", "tardanza", "inasistencia", "sanci", "falta"]) {
      expect(texto).not.toContain(palabra);
    }
    expect(b.avisos).toBe(1);
  });

  it("le pide RECIBIRLO, no firmarlo: firmar es opcional y recibir es lo que entrega", () => {
    const b = armarBandeja({
      ...VACIO,
      memosPorRecibir: [{ id: "m9", enviado_a_info_at: enLima("2026-09-05") }],
    }, HOY);

    expect(b.pendientes[0].titulo.toLowerCase()).toContain("recibir");
    expect(b.pendientes[0].titulo.toLowerCase()).not.toContain("firmar");
    // Y dice que puede recibirlo sin firmarlo: si no, «firmar» se lee obligatorio.
    expect(b.pendientes[0].detalle).toContain("sin firmar");
  });

  it("un memo por recibir NO caduca: sigue contando a los 90 días", () => {
    const b = armarBandeja({
      ...VACIO,
      memosPorRecibir: [{ id: "m9", enviado_a_info_at: enLima("2026-06-10") }],
    }, HOY);

    expect(b.pendientes).toHaveLength(1);
    expect(b.avisos).toBe(1);
  });

  it("uno por recibir y uno ya entregado por firmar son dos avisos, no uno", () => {
    const b = armarBandeja({
      ...VACIO,
      memosPorRecibir: [{ id: "m9", enviado_a_info_at: enLima("2026-09-05") }],
      memos: [{
        id: "m1", nivel: "amonestacion", entregado_at: enLima("2026-09-01"),
        firma_sancionado_confirmada_at: null, sancionado_rechazo_firma_at: null,
      }],
    }, HOY);

    expect(b.pendientes).toHaveLength(2);
    expect(new Set(b.pendientes.map((m) => m.clave)).size).toBe(2);
    expect(b.avisos).toBe(2);
  });

  it("sin la fuente no dice nada: con la 0486 sin pegar, el resto de la Bandeja sigue igual", () => {
    // VACIO no trae `memosPorRecibir` a propósito.
    expect(armarBandeja({ ...VACIO }, HOY).pendientes).toEqual([]);
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

  it("un cambio de turno entra directo como respuesta — no lo pidió, así que nunca espera", () => {
    const b = armarBandeja({
      ...VACIO,
      turnos: [{
        id: "t1", valor_anterior: "08:00–17:00", valor_nuevo: "09:00–18:00",
        corregido_at: enLima("2026-09-06"),
        motivo: "Turno del 16/09/2026 cambiado desde la pantalla de Turnos.",
      }],
    }, HOY);

    expect(b.esperando).toEqual([]);
    expect(b.respuestas).toHaveLength(1);
    expect(b.respuestas[0].origen).toBe("turno");
    expect(b.respuestas[0].titulo).toBe("Tu turno cambió: 08:00–17:00 → 09:00–18:00");
    expect(b.respuestas[0].detalle).toBe("Turno del 16/09/2026 cambiado desde la pantalla de Turnos.");
  });

  it("un cambio de turno caduca igual que cualquier otra respuesta", () => {
    const alBorde = "2026-08-25"; // 14 días antes de HOY
    const pasado = "2026-08-24"; // 15 — ya no

    const dentro = armarBandeja({
      ...VACIO,
      turnos: [{ id: "t1", valor_anterior: "(sin turno)", valor_nuevo: "09:00–18:00", corregido_at: enLima(alBorde), motivo: "…" }],
    }, HOY);
    const fuera = armarBandeja({
      ...VACIO,
      turnos: [{ id: "t1", valor_anterior: "(sin turno)", valor_nuevo: "09:00–18:00", corregido_at: enLima(pasado), motivo: "…" }],
    }, HOY);

    expect(dentro.respuestas[0].nuevo).toBe(true);
    expect(dentro.avisos).toBe(1);
    expect(fuera.respuestas[0].nuevo).toBe(false);
    expect(fuera.avisos).toBe(0);
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

// ── «VISTO» (0473) ──────────────────────────────────────────────────────────
// El mecanismo es el mismo `bandeja_vistos` que ya usa /admin/bandeja (0436),
// extendido para que /mio/bandeja también lo use — sin depender de que exista
// un enlace «Verlo →», que ni vacaciones ni una revisión de un día tienen.
//
// Lo que importa defender: cada origen se marca con el `tipo_item` que de
// verdad acepta `fn_bandeja_marcar_visto`, NO con `origen` — son cadenas
// distintas a propósito («revision-movilidad» adentro de bandeja-mia.ts,
// «revision_movilidad» en bandeja_vistos), y confundirlas dejaría el «visto»
// escribiéndose bajo un tipo que la función rechaza.
describe("armarBandeja · visto (0473)", () => {
  it("una revisión de ruta atendida es «nuevo» hasta que su clave está en vistos", () => {
    const fuentes = {
      ...VACIO,
      revisionesMovilidad: [{
        id: "r1", motivo: "no me cuadra el monto",
        pedida_at: enLima("2026-09-07"), atendida_at: enLima("2026-09-08"),
        respuesta: "atendido de prueba",
      }],
    };

    const sinVisto = armarBandeja(fuentes, HOY).respuestas[0];
    expect(sinVisto.nuevo).toBe(true);
    expect(sinVisto.marcarVistoComo).toEqual({ tipo: "revision_movilidad", itemId: "r1" });

    const conVisto = armarBandeja(
      { ...fuentes, vistos: new Set(["revision_movilidad:r1"]) },
      HOY,
    ).respuestas[0];
    expect(conVisto.nuevo).toBe(false);
  });

  it("un cambio de turno se marca con 'cambio_turno', no con el origen 'turno'", () => {
    const fuentes = {
      ...VACIO,
      turnos: [{
        id: "t1", valor_anterior: "9:00-18:00", valor_nuevo: "10:00-19:00",
        corregido_at: enLima("2026-09-06"), motivo: "cambio de cobertura",
      }],
    };

    const { respuestas } = armarBandeja(fuentes, HOY);
    expect(respuestas[0].marcarVistoComo).toEqual({ tipo: "cambio_turno", itemId: "t1" });
    expect(respuestas[0].nuevo).toBe(true);

    const vista = armarBandeja({ ...fuentes, vistos: new Set(["cambio_turno:t1"]) }, HOY).respuestas[0];
    expect(vista.nuevo).toBe(false);
  });

  it("vistos con un tipo o un id que no coincide no apaga la insignia", () => {
    const fuentes = {
      ...VACIO,
      revisionesMovilidad: [{
        id: "r1", motivo: "m", pedida_at: enLima("2026-09-07"), atendida_at: enLima("2026-09-08"), respuesta: null,
      }],
      vistos: new Set(["revision_movilidad:otro-id", "revision:r1"]),
    };

    expect(armarBandeja(fuentes, HOY).respuestas[0].nuevo).toBe(true);
  });

  it("un pendiente nunca marca vistoComo: no caduca y su insignia no se pinta de todos modos", () => {
    const b = armarBandeja({
      ...VACIO,
      contrato: {
        id: "c1", tipo: "indefinido", fecha_inicio: "2026-01-01", fecha_fin: null,
        generado_at: enLima("2026-09-08"), firma_persona_confirmada_at: null,
      },
    }, HOY);

    expect(b.pendientes[0].marcarVistoComo).toBeNull();
    expect(b.pendientes[0].nuevo).toBe(true);
  });
});

// ── El bono de cumpleaños (0477/0478/0479) ──────────────────────────────────
// Pedirlo es firmar su constancia; desde la 0479 el bono entra a su boleta, y
// solo si no había periodo abierto queda para que DO lo transfiera. Lo que se
// defiende:
//   · le toca a ELLA solo en su mes, o después si se le pasó — y lo decide
//     `fn_mi_bono_cumpleanos`, no el `bono_estado` del tablero (que se lo
//     ofrecería a una practicante);
//   · pedido, deja de ser pendiente y pasa a «esperando», que nunca cuenta;
//   · transferido, es respuesta — pero sin número en el botón (ver el
//     comentario en armarBandeja: no hay forma de marcarla vista).
describe("armarBandeja · bono de cumpleaños", () => {
  const bono = (x: Partial<MiBono>): MiBono => ({
    estado: "este_mes", mes_cumpleanos: 9, anio: 2026, monto: 180,
    documento_id: null, pedido_el: null, entregado_el: null, ...x,
  });

  it.each(["este_mes", "vencido"] as const)("%s: pedirlo le toca a ella, y lleva a /mio/cumpleanos", (estado) => {
    const b = armarBandeja({ ...VACIO, bono: bono({ estado }) }, HOY);
    expect(b.pendientes).toHaveLength(1);
    expect(b.pendientes[0].clave).toBe("bono:pedir");
    expect(b.pendientes[0].ir).toBe("/mio/cumpleanos");
    expect(b.pendientes[0].detalle).toContain("S/");
    expect(b.avisos).toBe(1);
  });

  it.each(["proximo", "sin_fecha", "no_aplica"] as const)("%s: no le pide nada", (estado) => {
    const b = armarBandeja({ ...VACIO, bono: bono({ estado }) }, HOY);
    expect(b.pendientes).toHaveLength(0);
    expect(b.esperando).toHaveLength(0);
    expect(b.respuestas).toHaveLength(0);
    expect(b.avisos).toBe(0);
  });

  it("el bono_estado del tablero ya no manda: sin `bono`, nada", () => {
    const b = armarBandeja({
      ...VACIO,
      movilidad: { estado: "ok", ruta_firmada_el: "2026-08-01", ruta_monto: 10, ruta_desfasada: false },
    }, HOY);
    expect(b.pendientes.filter((m) => m.origen === "bono")).toHaveLength(0);
  });

  it("pedido: pasa a esperando, con la fecha del pedido, y no cuenta", () => {
    const b = armarBandeja({
      ...VACIO, bono: bono({ estado: "pedido", documento_id: "d1", pedido_el: "2026-09-06" }),
    }, HOY);
    expect(b.pendientes).toHaveLength(0);
    expect(b.esperando).toHaveLength(1);
    expect(b.esperando[0].detalle).toContain("hace 2 días");
    expect(b.avisos).toBe(0);
  });

  it("en la boleta: esperando, con el periodo que la paga, y no cuenta", () => {
    const b = armarBandeja({
      ...VACIO,
      bono: bono({
        estado: "en_boleta", documento_id: "d1", pedido_el: "2026-09-06",
        via: "boleta", periodo_fin: "2026-09-28",
      }),
    }, HOY);
    expect(b.pendientes).toHaveLength(0);
    expect(b.esperando).toHaveLength(1);
    expect(b.esperando[0].titulo).toBe("Tu bono de cumpleaños va en tu boleta");
    expect(b.esperando[0].detalle).toContain("28 de setiembre");
    expect(b.esperando[0].detalle).toContain("tu planilla");
    expect(b.esperando[0].detalle).not.toContain("transfer");
    expect(b.avisos).toBe(0);
  });

  it("practicante (0521): el bono va en su boleta y se nombra «subvención», nunca «planilla»", () => {
    const b = armarBandeja({
      ...VACIO, practicante: true,
      bono: bono({
        estado: "en_boleta", documento_id: "d1", pedido_el: "2026-09-06",
        via: "boleta", periodo_fin: "2026-09-28",
      }),
    }, HOY);
    expect(b.esperando).toHaveLength(1);
    expect(b.esperando[0].detalle).toContain("tu subvención");
    expect(b.esperando[0].detalle).not.toContain("planilla");
    expect(b.esperando[0].detalle).not.toContain("transfer");
  });

  it("practicante, ya pagado: la respuesta tampoco dice «planilla»", () => {
    const b = armarBandeja({
      ...VACIO, practicante: true,
      bono: bono({
        estado: "entregado", documento_id: "d1", pedido_el: "2026-09-06",
        entregado_el: null, via: "boleta", periodo_fin: "2026-09-28",
      }),
    }, HOY);
    const r = b.respuestas.find((m) => m.origen === "bono");
    expect(r?.titulo).toBe("Tu bono de cumpleaños se pagó con tu subvención");
  });

  it("en la boleta, sin periodo_fin (base anterior a la 0479): no se rompe ni inventa fecha", () => {
    const b = armarBandeja({
      ...VACIO, bono: bono({ estado: "en_boleta", documento_id: "d1", pedido_el: "2026-09-06" }),
    }, HOY);
    expect(b.esperando).toHaveLength(1);
    expect(b.esperando[0].detalle).not.toContain("periodo que cierra");
  });

  it("pagado con la planilla: respuesta con el periodo (sin día de transferencia inventado)", () => {
    const b = armarBandeja({
      ...VACIO,
      bono: bono({
        estado: "entregado", documento_id: "d1", pedido_el: "2026-09-06",
        entregado_el: null, via: "boleta", periodo_fin: "2026-09-28",
      }),
    }, HOY);
    expect(b.respuestas).toHaveLength(1);
    expect(b.respuestas[0].titulo).toBe("Tu bono de cumpleaños se pagó con tu planilla");
    expect(b.respuestas[0].detalle).toContain("28 de setiembre");
    expect(b.respuestas[0].detalle).toContain("S/");
    expect(b.respuestas[0].nuevo).toBe(false);
    expect(b.avisos).toBe(0);
  });

  it("transferido tras pedirlo: respuesta con fecha y monto, sin número en el botón", () => {
    const b = armarBandeja({
      ...VACIO,
      bono: bono({ estado: "entregado", documento_id: "d1", pedido_el: "2026-09-06", entregado_el: "2026-09-07" }),
    }, HOY);
    expect(b.respuestas).toHaveLength(1);
    expect(b.respuestas[0].titulo).toBe("Te transfirieron tu bono de cumpleaños");
    expect(b.respuestas[0].detalle).toContain("7 de setiembre");
    expect(b.respuestas[0].nuevo).toBe(false);
    expect(b.avisos).toBe(0);
  });

  it("entregado en papel (sin pedido): no hay nada que avisarle", () => {
    const b = armarBandeja({
      ...VACIO, bono: bono({ estado: "entregado", documento_id: "d1", entregado_el: "2026-09-02" }),
    }, HOY);
    expect(b.respuestas).toHaveLength(0);
    expect(b.esperando).toHaveLength(0);
  });
});

// ── Cuándo va la tarjeta del bono en Info (0478) ────────────────────────────
describe("mostrarBonoEnInfo", () => {
  const b = (estado: MiBono["estado"], mes = 9): MiBono => ({
    estado, mes_cumpleanos: mes, anio: 2026, monto: 180, documento_id: null, pedido_el: null, entregado_el: null,
  });

  it("va cuando hay algo que hacer o que esperar", () => {
    for (const e of ["este_mes", "vencido", "pedido", "en_boleta"] as const) expect(mostrarBonoEnInfo(b(e), HOY)).toBe(true);
  });

  it("entregado: solo en el mes de su cumpleaños", () => {
    expect(mostrarBonoEnInfo(b("entregado", 9), HOY)).toBe(true);
    expect(mostrarBonoEnInfo(b("entregado", 3), HOY)).toBe(false);
  });

  it("nunca por algo que todavía no le toca", () => {
    for (const e of ["proximo", "sin_fecha", "no_aplica"] as const) expect(mostrarBonoEnInfo(b(e), HOY)).toBe(false);
    expect(mostrarBonoEnInfo(null, HOY)).toBe(false);
  });

  it("el botón se habilita con la misma condición que exige la base", () => {
    expect(puedePedirBono(b("este_mes"))).toBe(true);
    expect(puedePedirBono(b("vencido"))).toBe(true);
    for (const e of ["pedido", "en_boleta", "entregado", "proximo", "sin_fecha", "no_aplica"] as const) {
      expect(puedePedirBono(b(e))).toBe(false);
    }
  });
});

// ── Su boleta oficial (0482) ────────────────────────────────────────────────
// Publicada y sin abrir es un PENDIENTE: depende de ella y no caduca. Deja de
// contar cuando `vista_at` se escribe —el hecho ya está en la base, como la
// firma de un contrato—, no a los DIAS_NOVEDAD ni cuando la «marca como vista»
// la pantalla: por eso `marcarVistoComo` es null. Lo que se defiende:
//   · sin abrir cuenta; abierta, en papel o sin publicar, no;
//   · a los tres meses sin abrir SIGUE contando (la boleta que más hay que
//     seguir avisando es la que lleva tiempo sin abrirse);
//   · el mes del título sale de `fecha_fin` (el periodo del 29 al 28 se llama
//     por el mes en que termina) y el enlace lleva a la sección Boletas.
describe("armarBandeja · boleta oficial (0482)", () => {
  const boleta = (x: Partial<FilaBoletaBandeja>): FilaBoletaBandeja => ({
    boleta_id: "b1", fecha_fin: "2026-08-28", estado: "publicada",
    vista_at: null, publicada_at: enLima("2026-09-05"), ...x,
  });

  it("publicada y sin abrir es un pendiente que cuenta, con su mes y su enlace", () => {
    const b = armarBandeja({ ...VACIO, boletas: [boleta({})] }, HOY);
    expect(b.pendientes).toHaveLength(1);
    const m = b.pendientes[0];
    expect(m.origen).toBe("boleta");
    expect(m.estado).toBe("por_ver");
    expect(m.titulo).toBe("Tu boleta de agosto ya está disponible");
    expect(m.ir).toBe("/mio?tab=boletas");
    expect(m.nuevo).toBe(true);
    expect(m.marcarVistoComo).toBeNull();
    expect(b.avisos).toBe(1);
  });

  it("el mes es el de fecha_fin: el periodo que termina en setiembre se llama septiembre", () => {
    const b = armarBandeja({ ...VACIO, boletas: [boleta({ fecha_fin: "2026-09-28" })] }, HOY);
    expect(b.pendientes[0].titulo).toBe("Tu boleta de septiembre ya está disponible");
  });

  it("abierta (vista_at escrito) deja de contar", () => {
    const b = armarBandeja({ ...VACIO, boletas: [boleta({ vista_at: enLima("2026-09-06") })] }, HOY);
    expect(b.pendientes).toHaveLength(0);
    expect(b.avisos).toBe(0);
  });

  it("sin publicar (estado null) o entregada en papel no le piden nada", () => {
    const b = armarBandeja({
      ...VACIO,
      boletas: [boleta({ estado: null, boleta_id: null, publicada_at: null }), boleta({ boleta_id: "b2", estado: "papel" })],
    }, HOY);
    expect(b.pendientes).toHaveLength(0);
    expect(b.avisos).toBe(0);
  });

  it("no caduca: a los tres meses sin abrir sigue contando", () => {
    const b = armarBandeja({
      ...VACIO,
      boletas: [boleta({ publicada_at: enLima("2026-06-05") })],
    }, HOY);
    expect(b.pendientes).toHaveLength(1);
    expect(b.avisos).toBe(1);
  });

  it("dos boletas sin abrir son dos avisos, la más vieja arriba", () => {
    const b = armarBandeja({
      ...VACIO,
      boletas: [
        boleta({ boleta_id: "b2", fecha_fin: "2026-08-28", publicada_at: enLima("2026-09-05") }),
        boleta({ boleta_id: "b1", fecha_fin: "2026-07-28", publicada_at: enLima("2026-08-05") }),
      ],
    }, HOY);
    expect(b.pendientes.map((m) => m.clave)).toEqual(["boleta:b1", "boleta:b2"]);
    expect(b.avisos).toBe(2);
  });

  it("va después de lo que tiene plazo: el marcaje roto y el contrato sin firmar", () => {
    const b = armarBandeja({
      ...VACIO,
      boletas: [boleta({})],
      contrato: {
        id: "c1", tipo: "indefinido", fecha_inicio: "2026-01-01", fecha_fin: null,
        generado_at: enLima("2026-09-01"), firma_persona_confirmada_at: null,
      },
      periodo: { fecha_ini: "2026-08-29", fecha_fin: "2026-09-28" },
      marcajes: [{ fecha: "2026-09-02", estado: "auto_cerrada_pendiente", horas_trabajadas: null }],
    }, HOY);
    expect(b.pendientes.map((m) => m.origen)).toEqual(["contrato", "marcaje", "boleta"]);
  });

  it("sin `boletas` no se dice nada de boletas", () => {
    const b = armarBandeja({ ...VACIO }, HOY);
    expect(b.pendientes.filter((m) => m.origen === "boleta")).toHaveLength(0);
  });
});

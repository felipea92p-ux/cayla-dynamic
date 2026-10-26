// ============================================================================
// bandeja-sistema.test.ts — la tarjeta «Sistema» deja de ser un muro de JSON
// ============================================================================
// Lo que se defiende acá:
//
// 1. UNA LÍNEA POR CAUSA. El 2026-10-25 la tarjeta mostraba el mismo 403 de
//    Resend dos veces porque agrupaba por texto crudo (las llaves del JSON
//    venían en otro orden). Aquí se agrupa por causa.
// 2. LA PROPUESTA SE LEE CON DESCONFIANZA. Una respuesta sin la forma esperada
//    es null, no «cero avisos»: afirmaría que no hay nada sobre un dato que no
//    llegó.
// 3. EL BOTÓN NO APARECE SI LA FUNCIÓN NO EXISTE (la 0548 se pega a mano y
//    `main` se publica sola) ni si no hay avisos muertos ni si no se puede.
// 4. EL RECORDATORIO CAMBIA SEGÚN HAYA UNA AVERÍA DEL CANAL, y en el caso real
//    (avería del canal + avisos sin destinatario) nombra las dos cosas.
// 5. EL BOTÓN SE DECIDE CON LA RESPUESTA DE LA BASE, no solo con que la función
//    exista: si dice «nada que resolver», no se ofrece una ventana vacía.
// 6. LA TARJETA PLEGADA CABE EN UNA LÍNEA: el motivo se resume (`lineaDeCausas`).
// 7. EL TEXTO NO MIENTE: cerrar un aviso no borra el hecho, y un fallo de la base
//    nunca pega «deadlock detected» en la cara de quien no es técnica.
// ============================================================================
import { describe, expect, it } from "vitest";
import {
  causasDeLaTarjeta, causasPorPrioridad, frasesDeResolucion, funcionNoExiste, hayAlgoQueResolver, leerPropuesta, lineaDeCausas,
  mensajeDeResultado, mostrarBotonResolver, NOTA_DE_CIERRE, notasSinExplicar, recordatorioDelCanal, textoDeErrorDeLaVentana,
  tituloDelContadorBandeja, titularDeLaTarjeta, type PropuestaResolucion,
} from "../apps/web/lib/admin/bandeja-sistema";

const NOTA_403_A =
  'intento 3: Resend respondió 403: {"statusCode":403,"message":"The cayla.pe domain is not verified. Please, add and verify your domain.","name":"validation_error"}';
// El MISMO 403, con las llaves en otro orden y el prefijo de otro intento.
const NOTA_403_B =
  'intento 1: Resend respondió 403: {"name":"validation_error","message":"The cayla.pe domain is not verified. Please, add and verify your domain.","statusCode":403}';
const NOTA_SIN_LIDER = "intento 3: sin líder de equipo con correo activo en esa sede";

describe("titularDeLaTarjeta", () => {
  it("concuerda en singular y plural", () => {
    expect(titularDeLaTarjeta(61)).toBe("61 avisos por correo no van a salir solos");
    expect(titularDeLaTarjeta(1)).toBe("1 aviso por correo no va a salir solo");
  });
});

describe("causasDeLaTarjeta", () => {
  it("el mismo 403 con las llaves en otro orden es UNA sola línea", () => {
    const causas = causasDeLaTarjeta([NOTA_403_A, NOTA_403_B, NOTA_SIN_LIDER]);
    expect(causas.map((c) => c.causa)).toEqual(["remitente_sin_verificar", "sin_destinatario"]);
  });

  it("un resumen viejo sin motivos no rompe: no hay causas", () => {
    expect(causasDeLaTarjeta(undefined)).toEqual([]);
    expect(causasDeLaTarjeta(null)).toEqual([]);
  });

  it("ignora lo que no es texto en vez de tirar la pantalla", () => {
    expect(causasDeLaTarjeta([NOTA_403_A, 7 as unknown as string, null as unknown as string]).map((c) => c.causa))
      .toEqual(["remitente_sin_verificar"]);
  });
});

describe("notasSinExplicar", () => {
  it("solo devuelve lo que no se reconoce, sin repetir y cortado a 300", () => {
    const rara = "algo nunca visto " + "x".repeat(400);
    const notas = notasSinExplicar([NOTA_403_A, rara, rara, NOTA_SIN_LIDER]);
    expect(notas).toHaveLength(1);
    expect(notas[0]).toHaveLength(300);
  });
  it("sin motivos, nada", () => {
    expect(notasSinExplicar(undefined)).toEqual([]);
  });
});

describe("leerPropuesta", () => {
  it("lee la forma de la 0548", () => {
    const p = leerPropuesta({
      ejecutado: false,
      reencolar: { total: 40, por_tipo: { contrato_por_vencer: 30, vacaciones_por_vencer: 10 } },
      descartar: { total: 21, por_motivo: { fuera_de_ventana: 12, ya_no_vigente: 9 } },
    });
    expect(p).toEqual({
      ejecutado: false,
      reencolar: { total: 40, por_tipo: { contrato_por_vencer: 30, vacaciones_por_vencer: 10 }, ventana_renovada: 0 },
      descartar: { total: 21, por_motivo: { fuera_de_ventana: 12, ya_no_vigente: 9 } },
    });
  });

  it("la forma vieja, sin ventana_renovada, se sigue leyendo (como 0); la nueva se respeta y nunca pasa del total", () => {
    const base = { ejecutado: false, descartar: { total: 0, por_motivo: {} } };
    expect(leerPropuesta({ ...base, reencolar: { total: 10, por_tipo: {} } })?.reencolar.ventana_renovada).toBe(0);
    expect(leerPropuesta({ ...base, reencolar: { total: 10, por_tipo: {}, ventana_renovada: 4 } })?.reencolar.ventana_renovada).toBe(4);
    expect(leerPropuesta({ ...base, reencolar: { total: 3, por_tipo: {}, ventana_renovada: 9 } })?.reencolar.ventana_renovada).toBe(3);
    expect(leerPropuesta({ ...base, reencolar: { total: 3, por_tipo: {}, ventana_renovada: "mucho" } })?.reencolar.ventana_renovada).toBe(0);
  });

  it("una respuesta sin la forma esperada es null, NO «cero avisos»", () => {
    expect(leerPropuesta(null)).toBeNull();
    expect(leerPropuesta("hola")).toBeNull();
    expect(leerPropuesta([])).toBeNull();
    expect(leerPropuesta({ ejecutado: false })).toBeNull();
  });

  it("un total ausente se reconstruye del detalle; basura numérica es cero", () => {
    const p = leerPropuesta({
      ejecutado: true,
      reencolar: { por_tipo: { auto_cierre: 3, otro: 2 } },
      descartar: { total: -4, por_motivo: { x: "mucho", y: Number.NaN } },
    });
    expect(p?.reencolar.total).toBe(5);
    expect(p?.descartar.total).toBe(0);
    expect(p?.descartar.por_motivo).toEqual({});
    expect(p?.ejecutado).toBe(true);
  });
});

describe("frasesDeResolucion", () => {
  const propuesta = leerPropuesta({
    ejecutado: false,
    reencolar: { total: 40, por_tipo: { contrato_por_vencer: 30, vacaciones_por_vencer: 10 } },
    descartar: { total: 21, por_motivo: { fuera_de_ventana: 12, ya_no_vigente: 9 } },
  })!;

  it("dice lo que se reenvía y lo que se cierra, en palabras", () => {
    const f = frasesDeResolucion(propuesta);
    expect(f.reencolar).toBe("Se volverán a enviar 40 avisos que todavía sirven.");
    expect(f.reencolarDetalle).toBe("30 de contratos por vencer, 10 de vacaciones por vencer");
    expect(f.reencolarRenovadas).toBeNull();
    expect(f.descartar).toBe("Se darán por cerrados 21 avisos: ya no se van a mandar por correo.");
    expect(f.descartarDetalle).toContain("12 por llevar más de 7 días sin salir");
    expect(f.descartarDetalle).toContain("9 porque la situación ya cambió");
    expect(f.nada).toBe(false);
  });

  it("NO dice que los avisos cerrados «ya no sirven»: el hecho puede seguir vigente, solo se pierde el correo", () => {
    const f = frasesDeResolucion(propuesta);
    expect(f.descartar).not.toMatch(/ya no sirven?/);
    expect(f.notaDeCierre).toBe(NOTA_DE_CIERRE);
    expect(NOTA_DE_CIERRE).toContain("no borra el hecho");
    expect(NOTA_DE_CIERRE).toContain("no se puede deshacer");
  });

  it("la nota de cierre solo sale cuando algo se cierra", () => {
    const soloReenviar = { ejecutado: false, reencolar: { total: 2, por_tipo: {}, ventana_renovada: 0 }, descartar: { total: 0, por_motivo: {} } };
    expect(frasesDeResolucion(soloReenviar).notaDeCierre).toBeNull();
  });

  it("el motivo no se escribe con «porque porque»: cada motivo trae su propia preposición", () => {
    const f = frasesDeResolucion(propuesta);
    expect(f.descartarDetalle).not.toMatch(/porque porque|por porque|porque por /);
  });

  it("los vigentes que pasaron la ventana se dicen aparte: siguen siendo ciertos y reciben otra semana", () => {
    const f = frasesDeResolucion({ ...propuesta, reencolar: { ...propuesta.reencolar, ventana_renovada: 12 } });
    expect(f.reencolarRenovadas).toBe("12 de ellos llevaban más de 7 días y siguen siendo ciertos: se les da otra semana.");
    const uno = frasesDeResolucion({ ...propuesta, reencolar: { ...propuesta.reencolar, ventana_renovada: 1 } });
    expect(uno.reencolarRenovadas).toBe("1 de ellos llevaba más de 7 días y sigue siendo cierto: se le da otra semana.");
  });

  it("el detalle va del grupo más grande al más chico, no en el orden en que llegó el JSON", () => {
    const f = frasesDeResolucion({
      ejecutado: false,
      reencolar: { total: 13, por_tipo: { vacaciones_por_vencer: 3, auto_cierre: 10 }, ventana_renovada: 0 },
      descartar: { total: 10, por_motivo: { ya_no_vigente: 2, fuera_de_ventana: 8 } },
    });
    expect(f.reencolarDetalle).toBe("10 de jornadas que se cerraron solas, 3 de vacaciones por vencer");
    expect(f.descartarDetalle!.indexOf("8 por llevar")).toBeLessThan(f.descartarDetalle!.indexOf("2 porque"));
  });

  it("no suelta claves técnicas aunque aparezca un tipo o un motivo nuevo", () => {
    const f = frasesDeResolucion({
      ejecutado: false,
      reencolar: { total: 2, por_tipo: { tipo_nuevo_raro: 2 }, ventana_renovada: 0 },
      descartar: { total: 1, por_motivo: { motivo_nuevo: 1 } },
    });
    expect(f.reencolarDetalle).toBe("2 de tipo nuevo raro");
    expect(f.descartarDetalle).toBe("1 por «motivo nuevo»");
    expect(`${f.reencolarDetalle}${f.descartarDetalle}`).not.toContain("_");
  });

  it("singular", () => {
    const f = frasesDeResolucion({ ejecutado: false, reencolar: { total: 1, por_tipo: {}, ventana_renovada: 0 }, descartar: { total: 1, por_motivo: {} } });
    expect(f.reencolar).toBe("Se volverá a enviar 1 aviso que todavía sirve.");
    expect(f.descartar).toBe("Se dará por cerrado 1 aviso: ya no se va a mandar por correo.");
    expect(f.reencolarDetalle).toBeNull();
  });

  it("si no hay nada que reintentar ni cerrar, lo dice", () => {
    const vacia: PropuestaResolucion = { ejecutado: false, reencolar: { total: 0, por_tipo: {}, ventana_renovada: 0 }, descartar: { total: 0, por_motivo: {} } };
    expect(frasesDeResolucion(vacia).nada).toBe(true);
    expect(frasesDeResolucion(vacia).reencolar).toBeNull();
    expect(hayAlgoQueResolver(vacia)).toBe(false);
    expect(hayAlgoQueResolver(propuesta)).toBe(true);
  });

  it("solo hay algo que cerrar: tampoco es «nada»", () => {
    const p: PropuestaResolucion = { ejecutado: false, reencolar: { total: 0, por_tipo: {}, ventana_renovada: 0 }, descartar: { total: 3, por_motivo: { fuera_de_ventana: 3 } } };
    expect(frasesDeResolucion(p).nada).toBe(false);
    expect(frasesDeResolucion(p).reencolar).toBeNull();
  });
});

describe("mensajeDeResultado", () => {
  it("usa las cifras de lo ejecutado", () => {
    const p = leerPropuesta({
      ejecutado: true,
      reencolar: { total: 40, por_tipo: {} },
      descartar: { total: 1, por_motivo: {} },
    })!;
    expect(mensajeDeResultado(p)).toBe("40 avisos saldrán en el próximo despacho y 1 aviso se dio por cerrado.");
  });
  it("sin nada tras ejecutar, no suena a error: otra persona ya los había resuelto", () => {
    expect(mensajeDeResultado(leerPropuesta({ ejecutado: true, reencolar: { total: 0 }, descartar: { total: 0 } })!))
      .toBe("Otra persona ya los resolvió; no había nada pendiente.");
  });
});

describe("recordatorioDelCanal", () => {
  it("con una avería del canal, advierte que hay que arreglarla ANTES y nombra cuál", () => {
    const r = recordatorioDelCanal(causasDeLaTarjeta([NOTA_403_A]));
    expect(r.tono).toBe("advertencia");
    expect(r.texto).toContain("Antes de confirmar");
    expect(r.texto).toContain("dominio del remitente no está verificado");
    // Trae los pasos: la tarjeta queda tapada por el velo de la ventana.
    expect(r.texto).toContain("resend.com/domains");
    expect(r.texto).toContain("RESEND_FROM");
    // Sin avisos sin destinatario, no habla de Equipo.
    expect(r.texto).not.toContain("Equipo");
  });

  it("el caso REAL (403 de dominio + sin destinatario) nombra las dos cosas: arreglar el dominio no arregla lo otro", () => {
    const r = recordatorioDelCanal(causasDeLaTarjeta([NOTA_403_A, NOTA_SIN_LIDER]));
    expect(r.tono).toBe("advertencia");
    expect(r.texto).toContain("dominio del remitente no está verificado");
    expect(r.texto).toContain("resend.com/domains");
    expect(r.texto).toContain("Además hay avisos que no tienen a quién llegar");
    expect(r.texto).toContain("Equipo");
    expect(r.texto).toContain("volverán a fallar");
  });

  it("dice a quién pedírselo si no se puede tocar Vercel o Resend (DO no administra el servidor)", () => {
    const r = recordatorioDelCanal(causasDeLaTarjeta([NOTA_403_A]));
    expect(r.texto).toContain("Si no puedes tocar Vercel o Resend, pídeselo a quien administra el sistema");
  });

  it("no repite «Antes de confirmar» ni promete cuántos intentos quedan", () => {
    for (const notas of [[NOTA_403_A], [NOTA_403_A, NOTA_SIN_LIDER], [NOTA_SIN_LIDER], []]) {
      const t = recordatorioDelCanal(causasDeLaTarjeta(notas)).texto;
      expect(t.match(/Antes de confirmar/g)?.length ?? 0).toBeLessThanOrEqual(1);
      expect(t).not.toMatch(/tres intentos|tres días/i);
    }
  });

  it("si todo es de la fila, no asusta con el canal ni afirma que el envío funciona", () => {
    const r = recordatorioDelCanal(causasDeLaTarjeta([NOTA_SIN_LIDER]));
    expect(r.tono).toBe("informativo");
    expect(r.texto).toContain("Equipo");
    expect(r.texto).not.toContain("Resend");
    expect(r.texto).not.toMatch(/funciona/);
    expect(r.texto).toContain("son de cada aviso, no del envío");
  });

  it("sin motivos guardados, pide revisar el canal igual", () => {
    const r = recordatorioDelCanal([]);
    expect(r.tono).toBe("advertencia");
    expect(r.texto).toContain("no guardó el motivo");
  });
});

describe("funcionNoExiste", () => {
  it("reconoce que la 0548 aún no está pegada", () => {
    expect(funcionNoExiste({ code: "PGRST202", message: "x" })).toBe(true);
    expect(funcionNoExiste({ code: "42883", message: "function does not exist" })).toBe(true);
    expect(funcionNoExiste({ message: "Could not find the function public.fn_alertas_resolver_fallidas(p_ejecutar) in the schema cache" })).toBe(true);
  });
  it("cualquier otro error NO es «no existe»", () => {
    expect(funcionNoExiste({ code: "42501", message: "permission denied" })).toBe(false);
    expect(funcionNoExiste({ code: "P0001", message: "Solo un administrador" })).toBe(false);
    expect(funcionNoExiste(null)).toBe(false);
    expect(funcionNoExiste(undefined)).toBe(false);
  });
});

describe("mostrarBotonResolver", () => {
  const conMuertos = { fallidas_definitivas: 61, caducadas: 0 };
  const algo: PropuestaResolucion = { ejecutado: false, reencolar: { total: 12, por_tipo: {}, ventana_renovada: 0 }, descartar: { total: 49, por_motivo: {} } };
  const nada: PropuestaResolucion = { ejecutado: false, reencolar: { total: 0, por_tipo: {}, ventana_renovada: 0 }, descartar: { total: 0, por_motivo: {} } };
  const ok = { tipo: "ok", propuesta: algo } as const;

  it("aparece con permiso, avisos muertos o caducados y una respuesta que dice que hay algo", () => {
    expect(mostrarBotonResolver({ puede: true, sondeo: ok, resumen: conMuertos })).toBe(true);
    expect(mostrarBotonResolver({ puede: true, sondeo: ok, resumen: { fallidas_definitivas: 0, caducadas: 2 } })).toBe(true);
  });
  it("no aparece si la base contestó que no hay nada que reenviar ni cerrar (sería una ventana vacía)", () => {
    expect(mostrarBotonResolver({ puede: true, sondeo: { tipo: "ok", propuesta: nada }, resumen: conMuertos })).toBe(false);
  });
  it("aparece si solo hay algo que CERRAR, o solo algo que reenviar", () => {
    const soloCerrar: PropuestaResolucion = { ...nada, descartar: { total: 3, por_motivo: {} } };
    const soloReenviar: PropuestaResolucion = { ...nada, reencolar: { total: 3, por_tipo: {}, ventana_renovada: 0 } };
    expect(mostrarBotonResolver({ puede: true, sondeo: { tipo: "ok", propuesta: soloCerrar }, resumen: conMuertos })).toBe(true);
    expect(mostrarBotonResolver({ puede: true, sondeo: { tipo: "ok", propuesta: soloReenviar }, resumen: conMuertos })).toBe(true);
  });
  it("si el sondeo falló por algo que no es «no existe» (red, sesión, deadlock), se ofrece igual: esconder la salida por un fallo pasajero es peor", () => {
    expect(mostrarBotonResolver({ puede: true, sondeo: { tipo: "error" }, resumen: conMuertos })).toBe(true);
  });
  it("no aparece si la función no existe todavía, ni mientras no se sabe", () => {
    expect(mostrarBotonResolver({ puede: true, sondeo: { tipo: "no_existe" }, resumen: conMuertos })).toBe(false);
    expect(mostrarBotonResolver({ puede: true, sondeo: { tipo: "pendiente" }, resumen: conMuertos })).toBe(false);
  });
  it("no aparece sin permiso", () => {
    expect(mostrarBotonResolver({ puede: false, sondeo: ok, resumen: conMuertos })).toBe(false);
  });
  it("no aparece si lo único pendiente se reintenta solo (atascadas) o el resumen es viejo", () => {
    expect(mostrarBotonResolver({ puede: true, sondeo: ok, resumen: { fallidas_definitivas: 0, caducadas: 0 } })).toBe(false);
    expect(mostrarBotonResolver({ puede: true, sondeo: ok, resumen: {} })).toBe(false);
    expect(mostrarBotonResolver({ puede: true, sondeo: ok, resumen: null })).toBe(false);
  });
});

describe("lineaDeCausas — el motivo en la tarjeta plegada", () => {
  it("una causa: su versión corta, sin lista", () => {
    expect(lineaDeCausas(causasDeLaTarjeta([NOTA_403_A]), true)).toBe("Motivo: dominio del remitente sin verificar.");
  });
  it("varias causas: la del CANAL primero aunque llegue después, y cuántas más hay", () => {
    expect(lineaDeCausas(causasDeLaTarjeta([NOTA_SIN_LIDER, NOTA_403_A]), true)).toBe("Motivo: dominio del remitente sin verificar y 1 motivo más.");
    const tres = causasDeLaTarjeta([NOTA_SIN_LIDER, NOTA_403_A, "intento 1: Resend respondió 429: rate_limit_exceeded"]);
    expect(lineaDeCausas(tres, true)).toMatch(/y 2 motivos más\.$/);
  });
  it("sin causas: si hubo fallos lo dice (no calla); si no hubo, nada", () => {
    expect(lineaDeCausas([], true)).toBe("No se guardó el motivo.");
    expect(lineaDeCausas([], false)).toBeNull();
  });
  it("las causas del canal van antes que las de la fila, respetando el orden dentro de cada grupo", () => {
    const orden = causasPorPrioridad(causasDeLaTarjeta([NOTA_SIN_LIDER, NOTA_403_A])).map((c) => c.causa);
    expect(orden).toEqual(["remitente_sin_verificar", "sin_destinatario"]);
  });
});

describe("textoDeErrorDeLaVentana — un fallo se dice con palabras", () => {
  it("un deadlock de Postgres NO se pega crudo", () => {
    const t = textoDeErrorDeLaVentana({ origen: "base", error: { message: "deadlock detected", code: "40P01" } }, "revisar los avisos");
    expect(t).not.toContain("deadlock");
    expect(t).toContain("No se pudo revisar los avisos");
  });
  it("lo que nuestras funciones levantan a propósito (P0001) sí se muestra tal cual", () => {
    expect(textoDeErrorDeLaVentana({ origen: "base", error: { message: "Solo un administrador o líder puede resolver avisos", code: "P0001" } }, "resolver los avisos"))
      .toBe("Solo un administrador o líder puede resolver avisos");
  });
  it("un código conocido se traduce; sin conexión se dice que no hay conexión", () => {
    expect(textoDeErrorDeLaVentana({ origen: "base", error: { message: "permission denied", code: "42501" } }, "resolver los avisos")).toContain("No tienes permiso");
    expect(textoDeErrorDeLaVentana({ origen: "base", error: { message: "TypeError: Failed to fetch" } }, "revisar los avisos")).toContain("no hay conexión");
  });
  it("una respuesta sin la forma esperada y una excepción tienen cada una su frase", () => {
    expect(textoDeErrorDeLaVentana({ origen: "forma" }, "revisar los avisos")).toContain("forma esperada");
    expect(textoDeErrorDeLaVentana({ origen: "excepcion" }, "revisar los avisos")).toContain("no hubo respuesta");
  });
});

describe("tituloDelContadorBandeja — el número del menú, explicado", () => {
  it("dice de dónde sale: las filas más una unidad por correo y una por Normas", () => {
    expect(tituloDelContadorBandeja({ tareas: 31, sistema: 1, normas: 1, total: 33 }))
      .toBe("33 en la Bandeja del equipo: 31 filas de la lista + 1 por los correos de aviso que no salieron + 1 por las constancias de Normas por recoger");
  });
  it("sin señales de sistema, solo las filas", () => {
    expect(tituloDelContadorBandeja({ tareas: 1, sistema: 0, normas: 0, total: 1 })).toBe("1 en la Bandeja del equipo: 1 fila de la lista");
  });
  it("sin nada, lo dice", () => {
    expect(tituloDelContadorBandeja({ tareas: 0, sistema: 0, normas: 0, total: 0 })).toBe("Nada pendiente en la Bandeja del equipo");
  });
});

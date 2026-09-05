// ============================================================================
// jornada-en-curso.test.ts — La noche que cruza la medianoche
// ============================================================================
// El terminal decidía qué ofrecer mirando solo las marcas de HOY. A las 00:30
// «hoy» está vacío, así que a quien acababa de cerrar tienda le ofrecía
// «Entrada» — y con eso abría un día fantasma que el auto-cierre remataba en 22
// horas. Su salida real nunca llegaba a existir (C4, migración 0240).
//
// Lo que se prueba aquí es la regla del TURNO, no la del calendario. Y sobre
// todo la trampa: pasarle el día de ayer completo rompería el caso normal,
// porque `determinarSiguienteAccion` responde «cerrado» en cuanto ve un
// salida_final.
// ============================================================================
import { describe, expect, it } from "vitest";
import { jornadaEnCursoPorPersona, marcasDeLaJornadaEnCurso } from "@/lib/terminal/jornada-en-curso";
import {
  TOPE_JORNADA_CRUZA_MEDIANOCHE_HORAS,
  determinarSiguienteAccion,
  type MarcajeDelDia,
} from "@cayla-dynamic/shared";

const entrada = (t: string): MarcajeDelDia => ({ tipo: "entrada", timestamp: t });
const salidaFinal = (t: string): MarcajeDelDia => ({ tipo: "salida_final", timestamp: t });
const salidaAlmuerzo = (t: string): MarcajeDelDia => ({ tipo: "salida_almuerzo", timestamp: t });

// Todas las pruebas de abajo salvo las del tope ocurren DENTRO de las 16 h: el
// reloj se pasa explícito para que ninguna dependa de cuándo se ejecuten.
const HORA = 60 * 60 * 1000;
const ms = (t: string) => Date.parse(t);

describe("marcasDeLaJornadaEnCurso", () => {
  it("a las 00:30, con la jornada de ayer sin cerrar, sigue siendo la de ayer", () => {
    const ayer = [entrada("2026-08-04T20:00:00Z")];
    expect(marcasDeLaJornadaEnCurso(ayer, [], ms("2026-08-05T05:30:00Z"))).toEqual(ayer);
  });

  it("y entonces el terminal le ofrece SALIR, no entrar — que es todo el arreglo", () => {
    const ayer = [entrada("2026-08-04T20:00:00Z")];
    const accion = determinarSiguienteAccion(
      marcasDeLaJornadaEnCurso(ayer, [], ms("2026-08-05T05:30:00Z")),
    );
    expect(accion.modo).not.toBe("cerrado");
    // Con una entrada sin salida, lo siguiente es alguna forma de salida.
    expect(JSON.stringify(accion)).toContain("salida");
  });

  it("si ayer cerró normal, hoy empieza de cero — la trampa que rompe el caso común", () => {
    // Pasarle el día de ayer entero haría que determinarSiguienteAccion dijera
    // «ya registraste tu salida final de hoy» a alguien que llega por la mañana.
    const ayer = [entrada("2026-08-04T14:00:00Z"), salidaFinal("2026-08-04T23:00:00Z")];
    expect(marcasDeLaJornadaEnCurso(ayer, [], ms("2026-08-05T13:00:00Z"))).toEqual([]);
    expect(
      determinarSiguienteAccion(marcasDeLaJornadaEnCurso(ayer, [], ms("2026-08-05T13:00:00Z"))),
    ).toEqual({
      modo: "unico", tipo: "entrada",
    });
  });

  it("en cuanto marca algo hoy, la noche terminó y manda lo de hoy", () => {
    const ayer = [entrada("2026-08-04T20:00:00Z")];           // quedó abierta
    const hoy = [entrada("2026-08-05T14:00:00Z")];
    expect(marcasDeLaJornadaEnCurso(ayer, hoy, ms("2026-08-05T14:30:00Z"))).toEqual(hoy);
  });

  it("una pausa de ayer sin retorno también sigue en curso", () => {
    // No solo la entrada: si salió a refrigerio y no volvió antes de medianoche,
    // esa jornada sigue siendo la suya.
    const ayer = [entrada("2026-08-04T20:00:00Z"), salidaAlmuerzo("2026-08-05T02:00:00Z")];
    expect(marcasDeLaJornadaEnCurso(ayer, [], ms("2026-08-05T02:30:00Z"))).toEqual(ayer);
  });

  it("sin nada ayer ni hoy, no hay jornada en curso", () => {
    expect(marcasDeLaJornadaEnCurso([], [], ms("2026-08-05T14:00:00Z"))).toEqual([]);
  });
});

// ============================================================================
// Y LA MITAD QUE FALTABA: A QUÉ JORNADA PERTENECE CADA MARCA
// ============================================================================
// `marcasDeLaJornadaEnCurso` ya estaba probada, y decide bien. Lo que nadie
// probaba es lo que le llega: el reparto entre «ayer» y «hoy». Vivía dentro de
// `cargarMarcajesHoyPorPersona`, que hace red, y repartía por la fecha de
// CALENDARIO del `timestamp_marca`.
//
// Ahí estaba el defecto. Quien cierra tienda a las 00:30 tiene su salida
// guardada con `fecha_jornada` del día anterior —eso lo hace bien la 0240— pero
// por calendario esa salida cae en el cubo de HOY. Al marcar su entrada de la
// mañana, la máquina de estados veía un `salida_final` y respondía «cerrado»:
// el terminal le decía «Ya cerraste tu día. ¿Volviste a entrar?» a alguien que
// acababa de llegar, y el único botón hacia adelante ANULABA la salida real de
// anoche.
//
// Medido contra el Postgres local: 9,50 h y S/109,62 perdidos, y el día anterior
// reabierto sin entrada. La otra mitad del arreglo vive en la migración 0317.
// ============================================================================
const dia = (ts: string) => ts.slice(0, 10); // el «calendario» para estas pruebas

describe("jornadaEnCursoPorPersona", () => {
  const ANA = "ana";

  it("la salida de las 00:30 pertenece a AYER, aunque el calendario diga hoy", () => {
    // Entra el 25 a las 15:00 y cierra tienda a las 00:30 del 26. La salida
    // lleva fecha_jornada del 25 — que es lo que la 0240 guarda.
    const filas = [
      { persona_id: ANA, tipo: "entrada" as const, timestamp_marca: "2026-08-25T20:00:00Z", fecha_jornada: null },
      { persona_id: ANA, tipo: "salida_final" as const, timestamp_marca: "2026-08-26T05:30:00Z", fecha_jornada: "2026-08-25" },
    ];
    // Todavía no ha marcado nada del 26: no hay jornada en curso, y por eso el
    // terminal le va a ofrecer ENTRADA.
    const mapa = jornadaEnCursoPorPersona(filas, "2026-08-26", dia, ms("2026-08-26T14:00:00Z"));
    expect(mapa.get(ANA) ?? []).toEqual([]);
    expect(determinarSiguienteAccion(mapa.get(ANA) ?? [])).toEqual({ modo: "unico", tipo: "entrada" });
  });

  it("y tras marcar su entrada de la mañana, el terminal NO dice «ya cerraste»", () => {
    // Éste es el caso que costaba S/109,62: con el reparto por calendario, la
    // salida de las 00:30 entraba aquí y la respuesta era «cerrado».
    const filas = [
      { persona_id: ANA, tipo: "entrada" as const, timestamp_marca: "2026-08-25T20:00:00Z", fecha_jornada: null },
      { persona_id: ANA, tipo: "salida_final" as const, timestamp_marca: "2026-08-26T05:30:00Z", fecha_jornada: "2026-08-25" },
      { persona_id: ANA, tipo: "entrada" as const, timestamp_marca: "2026-08-26T13:00:00Z", fecha_jornada: null },
    ];
    const enCurso = jornadaEnCursoPorPersona(filas, "2026-08-26", dia, ms("2026-08-26T14:00:00Z")).get(ANA) ?? [];
    expect(enCurso).toHaveLength(1);
    expect(enCurso[0].tipo).toBe("entrada");
    expect(determinarSiguienteAccion(enCurso).modo).not.toBe("cerrado");
  });

  it("sin fecha_jornada manda el calendario: el caso NORMAL, no el defensivo", () => {
    // Las entradas no llevan `fecha_jornada`. Si el `??` se leyera como un
    // adorno defensivo y alguien lo quitara, dejaría de funcionar lo corriente.
    const filas = [
      { persona_id: ANA, tipo: "entrada" as const, timestamp_marca: "2026-08-26T14:00:00Z", fecha_jornada: null },
    ];
    const enCurso = jornadaEnCursoPorPersona(filas, "2026-08-26", dia, ms("2026-08-26T14:00:00Z")).get(ANA) ?? [];
    expect(enCurso).toHaveLength(1);
  });

  it("no se rompe el caso que arregló la 0240: a las 00:30 sin cerrar, sigue la de ayer", () => {
    // La trampa al revés. Si esto se rompiera, a quien cierra tienda a la
    // medianoche se le ofrecería ENTRADA y volvería el día fantasma.
    const filas = [
      { persona_id: ANA, tipo: "entrada" as const, timestamp_marca: "2026-08-25T20:00:00Z", fecha_jornada: null },
    ];
    // 00:30 de Lima = 05:30Z. Nueve horas y media después de su entrada: bien
    // dentro de las 16 h, que es cuando esto tiene que seguir cumpliéndose.
    const enCurso = jornadaEnCursoPorPersona(filas, "2026-08-26", dia, ms("2026-08-26T05:30:00Z")).get(ANA) ?? [];
    expect(enCurso).toHaveLength(1);
    expect(JSON.stringify(determinarSiguienteAccion(enCurso))).toContain("salida");
  });

  it("cada persona por su cuenta: la noche de una no mueve la de la otra", () => {
    const filas = [
      { persona_id: "ana", tipo: "salida_final" as const, timestamp_marca: "2026-08-26T05:30:00Z", fecha_jornada: "2026-08-25" },
      { persona_id: "bea", tipo: "entrada" as const, timestamp_marca: "2026-08-26T14:00:00Z", fecha_jornada: null },
    ];
    const mapa = jornadaEnCursoPorPersona(filas, "2026-08-26", dia, ms("2026-08-26T14:00:00Z"));
    expect(mapa.get("ana") ?? []).toEqual([]);
    expect(mapa.get("bea") ?? []).toHaveLength(1);
  });
});

// ============================================================================
// EL TOPE DE 16 HORAS — el borde donde el navegador y el servidor se separaban
// ============================================================================
// `fn_registrar_marcaje` solo adopta la jornada de ayer si la marca llega dentro
// de las 16 h desde `j.entrada_ts`. Este archivo no tenía esa condición, así que
// pasado el tope las dos mitades decían cosas distintas: la pantalla ofrecía un
// menú de SALIDAS y el servidor esperaba una `entrada`. Cualquier botón que la
// persona pulsara lo rechazaba el servidor, y no había ningún otro que pulsar.
//
// No es teórico: `fn_auto_cierre` corre cada 15 minutos y decide por su cuenta,
// así que existe una franja real —hasta un cuarto de hora— en la que la jornada
// pasó las 16 h y todavía nadie la ha cerrado. Ahí dentro, quien fuera a marcar
// se quedaba sin poder hacerlo.
// ============================================================================
describe("el tope de 16 horas, igual que en fn_registrar_marcaje", () => {
  const ENTRADA = "2026-08-25T20:00:00Z";
  const ayer = [entrada(ENTRADA)];

  it("una hora ANTES del tope, la jornada de ayer sigue siendo la suya", () => {
    const casi = ms(ENTRADA) + (TOPE_JORNADA_CRUZA_MEDIANOCHE_HORAS - 1) * HORA;
    expect(marcasDeLaJornadaEnCurso(ayer, [], casi)).toEqual(ayer);
  });

  it("justo EN el tope todavía cuenta — el servidor usa <=, no <", () => {
    const justo = ms(ENTRADA) + TOPE_JORNADA_CRUZA_MEDIANOCHE_HORAS * HORA;
    expect(marcasDeLaJornadaEnCurso(ayer, [], justo)).toEqual(ayer);
  });

  it("un minuto DESPUÉS ya no, y el terminal ofrece ENTRADA — que es lo que el servidor acepta", () => {
    const pasado = ms(ENTRADA) + TOPE_JORNADA_CRUZA_MEDIANOCHE_HORAS * HORA + 60_000;
    expect(marcasDeLaJornadaEnCurso(ayer, [], pasado)).toEqual([]);
    // Lo que importa no es que devuelva vacío: es que el único botón que la
    // pantalla ofrece sea el que el servidor va a aceptar.
    expect(determinarSiguienteAccion(marcasDeLaJornadaEnCurso(ayer, [], pasado))).toEqual({
      modo: "unico", tipo: "entrada",
    });
  });

  it("el tope se mide contra la ENTRADA, no contra la última marca", () => {
    // Salió a refrigerio 15 h después de entrar y no volvió. Midiendo contra esa
    // pausa quedarían 31 h de ventana; el servidor mide contra `j.entrada_ts`.
    const conPausa = [entrada(ENTRADA), salidaAlmuerzo("2026-08-26T11:00:00Z")];
    const pasado = ms(ENTRADA) + 17 * HORA;
    expect(marcasDeLaJornadaEnCurso(conPausa, [], pasado)).toEqual([]);
  });

  it("sin entrada de ayer no hay jornada que adoptar, igual que exige el servidor", () => {
    // `fn_registrar_marcaje` pide `j.entrada_ts is not null`. Una jornada sin
    // entrada no se adopta ni dentro del plazo: ofrecerle salidas sería ofrecerle
    // un botón que el servidor rechaza.
    const soloPausa = [salidaAlmuerzo("2026-08-25T22:00:00Z")];
    expect(marcasDeLaJornadaEnCurso(soloPausa, [], ms("2026-08-25T22:30:00Z"))).toEqual([]);
  });

  it("y el tope no le gana a lo de hoy: si ya marcó hoy, manda hoy", () => {
    const hoy = [entrada("2026-08-26T14:00:00Z")];
    const muyPasado = ms(ENTRADA) + 40 * HORA;
    expect(marcasDeLaJornadaEnCurso(ayer, hoy, muyPasado)).toEqual(hoy);
  });
});

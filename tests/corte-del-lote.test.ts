import { describe, expect, it } from "vitest";
import { causaDeRespuesta } from "@/lib/alertas/causa-del-fallo";
import {
  CAIDAS_SEGUIDAS_PARA_CORTAR, decidirCorte, FALLOS_SEGUIDOS_PARA_CORTAR, rachaNueva, type ResultadoParaCorte,
} from "@/lib/alertas/corte-del-lote";
import { esperaPorSegundo, LIMITE_BLANDO_MS } from "@/lib/alertas/ritmo-del-despacho";

// La decisión de cortar el lote, sin la ruta: cada regla con su caso.

const ok: ResultadoParaCorte = { ok: true };
const falla = (status: number | null, cuerpo = "", red = false): ResultadoParaCorte => ({ ok: false, causa: causaDeRespuesta({ status, cuerpo, red }) });

const DOMINIO = falla(403, '{"message":"The cayla.pe domain is not verified.","name":"validation_error"}');
const CLAVE = falla(401, '{"message":"API key is invalid","name":"validation_error"}');
const CAIDA = falla(500, "boom");
const RED = falla(null, "", true);
const OTRA = falla(403, '{"message":"Access denied for this resource","name":"forbidden"}');
const RECHAZO = falla(422, '{"message":"Invalid `to` field.","name":"validation_error"}');
const LIMITE = falla(429, '{"name":"daily_quota_exceeded","message":"daily quota"}');

describe("decidirCorte", () => {
  it("las constantes que el resto del sistema cuenta", () => {
    expect(FALLOS_SEGUIDOS_PARA_CORTAR).toBe(3);
    expect(CAIDAS_SEGUIDAS_PARA_CORTAR).toBe(2);
    expect(LIMITE_BLANDO_MS).toBe(45_000);
  });

  it("un éxito nunca corta", () => {
    expect(decidirCorte(rachaNueva(), ok)).toEqual({ corta: false });
  });

  it.each([["dominio sin verificar", DOMINIO], ["clave inválida", CLAVE]])(
    "%s: corta a la primera y devuelve el intento",
    (_n, r) => {
      expect(decidirCorte(rachaNueva(), r)).toEqual({ corta: true, razon: "canal", devolverIntento: true });
    },
  );

  it("configuración faltante corta a la primera y devuelve el intento", () => {
    const r: ResultadoParaCorte = { ok: false, causa: causaDeRespuesta({ status: 422, cuerpo: '{"name":"invalid_from_address","message":"Invalid `from` field."}' }) };
    expect(decidirCorte(rachaNueva(), r)).toEqual({ corta: true, razon: "canal", devolverIntento: true });
  });

  it("límite de envíos corta a la primera SIN devolver el intento", () => {
    expect(decidirCorte(rachaNueva(), LIMITE)).toEqual({ corta: true, razon: "canal", devolverIntento: false });
  });

  it("Resend caído: la primera sigue, la segunda seguida corta, y nunca devuelve el intento", () => {
    const racha = rachaNueva();
    expect(decidirCorte(racha, CAIDA)).toEqual({ corta: false });
    expect(decidirCorte(racha, RED)).toEqual({ corta: true, razon: "canal", devolverIntento: false });
  });

  it("una caída, un éxito y otra caída: no cortan", () => {
    const racha = rachaNueva();
    expect(decidirCorte(racha, CAIDA).corta).toBe(false);
    expect(decidirCorte(racha, ok).corta).toBe(false);
    expect(decidirCorte(racha, CAIDA).corta).toBe(false);
  });

  it("una caída, un fallo de fila y otra caída: no son «seguidas»", () => {
    const racha = rachaNueva();
    decidirCorte(racha, CAIDA);
    decidirCorte(racha, RECHAZO);
    expect(decidirCorte(racha, CAIDA).corta).toBe(false);
  });

  it("disyuntor: la tercera causa de fila IGUAL y seguida corta, sin devolver el intento", () => {
    const racha = rachaNueva();
    expect(decidirCorte(racha, OTRA).corta).toBe(false);
    expect(decidirCorte(racha, OTRA).corta).toBe(false);
    expect(decidirCorte(racha, OTRA)).toEqual({ corta: true, razon: "disyuntor", devolverIntento: false });
  });

  it("disyuntor: un éxito reinicia la cuenta", () => {
    const racha = rachaNueva();
    decidirCorte(racha, OTRA); decidirCorte(racha, OTRA);
    decidirCorte(racha, ok);
    expect(decidirCorte(racha, OTRA).corta).toBe(false);
    expect(decidirCorte(racha, OTRA).corta).toBe(false);
    expect(decidirCorte(racha, OTRA).corta).toBe(true);
  });

  it("disyuntor: causas de fila distintas se reinician entre sí", () => {
    const racha = rachaNueva();
    decidirCorte(racha, OTRA); decidirCorte(racha, RECHAZO);
    expect(decidirCorte(racha, OTRA).corta).toBe(false);
    expect(decidirCorte(racha, OTRA).corta).toBe(false);
    expect(decidirCorte(racha, OTRA).corta).toBe(true);
  });

  it("disyuntor: también cuenta el rechazo de Resend (422) repetido", () => {
    const racha = rachaNueva();
    decidirCorte(racha, RECHAZO); decidirCorte(racha, RECHAZO);
    expect(decidirCorte(racha, RECHAZO)).toMatchObject({ corta: true, razon: "disyuntor" });
  });

  it("una caída de Resend entre dos fallos de fila rompe la racha de la fila", () => {
    const racha = rachaNueva();
    decidirCorte(racha, OTRA); decidirCorte(racha, OTRA);
    decidirCorte(racha, CAIDA);
    expect(decidirCorte(racha, OTRA).corta).toBe(false);
  });

  it("«sin destinatario» ni suma ni reinicia", () => {
    const sinDestino: ResultadoParaCorte = { ok: false, causa: { causa: "sin_destinatario", etiqueta: "x", que_hacer: "y", del_canal: false } };
    const racha = rachaNueva();
    decidirCorte(racha, OTRA); decidirCorte(racha, OTRA);
    expect(decidirCorte(racha, sinDestino)).toEqual({ corta: false });
    expect(decidirCorte(racha, OTRA).corta).toBe(true); // sigue siendo la tercera
  });
});

describe("esperaPorSegundo", () => {
  it("usa retry-after con techo de 2 s y 1 s por defecto", () => {
    expect(esperaPorSegundo("1")).toBe(1000);
    expect(esperaPorSegundo("2")).toBe(2000);
    expect(esperaPorSegundo("30")).toBe(2000);
    expect(esperaPorSegundo("0.5")).toBe(500);
    for (const raro of [null, undefined, "", "   ", "0", "-3", "Wed, 21 Oct 2026 07:28:00 GMT", "abc"]) {
      expect(esperaPorSegundo(raro)).toBe(1000);
    }
  });
});

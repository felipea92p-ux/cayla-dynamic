import { describe, it, expect } from "vitest";
import {
  agruparCausas, causaDeNota, causaDeRespuesta,
  NOTA_CUERPO_NO_RECIBIDO, NOTA_SIN_DESTINATARIO, PREFIJO_SIN_RESPUESTA,
  type CausaDeFallo,
} from "@/lib/alertas/causa-del-fallo";

// Los dos cuerpos reales del 403 de Resend del 2026-10-25: el mismo error con
// las llaves en distinto orden. La Bandeja los mostraba como dos causas.
const JSON_A = '{"statusCode":403,"message":"The cayla.pe domain is not verified. Please, add and verify your domain on https://resend.com/domains","name":"validation_error"}';
const JSON_B = '{"name":"validation_error","message":"The cayla.pe domain is not verified. Please, add and verify your domain on https://resend.com/domains","statusCode":403}';

const SOLO_PROPIO =
  'You can only send testing emails to your own email address (alguien.con.un.correo.muy.largo.de.verdad@un-dominio-largo-de-ejemplo.com.pe). ' +
  "To send emails to other recipients, please verify a domain at resend.com/domains, and change the `from` address to an address using this domain.";

describe("causaDeNota: la causa, no el texto", () => {
  it("los dos 403 con llaves en distinto orden y distinto intento dan la MISMA causa", () => {
    const a = causaDeNota(`intento 3: Resend respondió 403: ${JSON_A}`);
    const b = causaDeNota(`intento 1: Resend respondió 403: ${JSON_B}`);
    expect(a.causa).toBe("remitente_sin_verificar");
    expect(b).toEqual(a);
    expect(a.del_canal).toBe(true);
  });

  it("«solo tu propio correo» y «dominio no verificado» son la misma causa (misma acción de Felipe)", () => {
    const solo = causaDeNota(`intento 2: Resend respondió 403: ${JSON.stringify({ statusCode: 403, message: SOLO_PROPIO, name: "validation_error" })}`);
    expect(solo.causa).toBe("remitente_sin_verificar");
  });

  it("«solo tu propio correo» se reconoce por sí mismo, aunque el cuerpo no llegue a la cláusula de verificar un dominio", () => {
    const corto = '{"statusCode":403,"message":"You can only send testing emails to your own email address (a@b.pe).","name":"validation_error"}';
    expect(causaDeNota(`intento 1: Resend respondió 403: ${corto}`).causa).toBe("remitente_sin_verificar");
    expect(causaDeNota(`intento 1: Resend respondió 403: ${corto.slice(0, 90)}`).causa).toBe("remitente_sin_verificar");
  });

  it("un 403 de otra índole NO se funde con el remitente", () => {
    const otro = causaDeNota('intento 1: Resend respondió 403: {"statusCode":403,"message":"Access denied for this resource","name":"forbidden"}');
    expect(otro.causa).toBe("otra");
    expect(otro.causa).not.toBe(causaDeNota(`intento 1: Resend respondió 403: ${JSON_A}`).causa);
    expect(otro.del_canal).toBe(false);
  });

  it("un 403 que habla de la clave es clave inválida, no remitente", () => {
    expect(causaDeNota('intento 1: Resend respondió 403: {"statusCode":403,"message":"API key is invalid","name":"invalid_api_key"}').causa).toBe("clave_invalida");
  });

  it("el cuerpo truncado a 300 caracteres (ya no parsea) se reconoce por texto", () => {
    const largo = JSON.stringify({ statusCode: 403, message: SOLO_PROPIO, name: "validation_error" });
    expect(largo.length).toBeGreaterThan(300);
    const cortado = largo.slice(0, 300);
    expect(() => JSON.parse(cortado)).toThrow();
    expect(causaDeNota(`intento 3: Resend respondió 403: ${cortado}`).causa).toBe("remitente_sin_verificar");

    // El de «dominio no verificado», cortado a mitad del mensaje, también.
    const mitad = JSON_A.slice(0, 80);
    expect(() => JSON.parse(mitad)).toThrow();
    expect(causaDeNota(`intento 3: Resend respondió 403: ${mitad}`).causa).toBe("remitente_sin_verificar");
  });

  it.each<[string, CausaDeFallo, boolean]>([
    ['intento 1: Resend respondió 401: {"statusCode":401,"message":"Missing API key.","name":"missing_api_key"}', "clave_invalida", true],
    ["intento 1: Resend respondió 401: ", "clave_invalida", true],
    ['intento 1: Resend respondió 429: {"statusCode":429,"message":"Too many requests.","name":"rate_limit_exceeded"}', "limite_de_envios", true],
    ["intento 1: Resend respondió 429: ", "limite_de_envios", true],
    ["intento 1: Resend respondió 500: Internal Server Error", "resend_caido", true],
    ["intento 2: Resend respondió 502: <html>Bad Gateway</html>", "resend_caido", true],
    [`intento 1: ${PREFIJO_SIN_RESPUESTA} (sin respuesta tras 10 s)`, "resend_caido", true],
    [`intento 1: ${PREFIJO_SIN_RESPUESTA} (error de red: fetch failed)`, "resend_caido", true],
    ['intento 1: Resend respondió 422: {"statusCode":422,"message":"Invalid `to` field. The email address needs to be valid.","name":"validation_error"}', "rechazo_de_resend", false],
    ["intento 1: Resend respondió 400: algo raro", "rechazo_de_resend", false],
    ['intento 1: Resend respondió 422: {"statusCode":422,"message":"Invalid `from` field. The email address needs to follow the `email@example.com` or `Name <email@example.com>` format.","name":"invalid_from_address"}', "configuracion_faltante", true],
    ["intento 1: RESEND_API_KEY no configurada", "configuracion_faltante", true],
    ["intento 1: RESEND_FROM no configurada — sin un dominio propio verificado en Resend, el remitente de prueba no entrega a destinatarios reales", "configuracion_faltante", true],
  ])("%s -> %s", (nota, causa, delCanal) => {
    const c = causaDeNota(nota);
    expect(c.causa).toBe(causa);
    expect(c.del_canal).toBe(delCanal);
  });

  it("vacío o sin sentido es «otra», y no del canal", () => {
    for (const n of ["", "   ", "intento 2:", "algo que nadie previó"]) {
      const c = causaDeNota(n);
      expect(c.causa).toBe("otra");
      expect(c.del_canal).toBe(false);
    }
  });

  it("sin destinatario: reconoce la redacción vieja, la intermedia y la actual", () => {
    for (const n of [
      "intento 3: sin encargada con correo activo en esa sede",
      "intento 3: sin líder de equipo con correo activo en esa sede",
      `intento 1: ${NOTA_SIN_DESTINATARIO}`,
    ]) {
      const c = causaDeNota(n);
      expect(c.causa).toBe("sin_destinatario");
      expect(c.del_canal).toBe(false);
    }
  });

  it("la nota que escribe la ruta se reconoce a sí misma", () => {
    expect(causaDeNota(`intento 1: ${NOTA_SIN_DESTINATARIO}`).causa).toBe("sin_destinatario");
    expect(causaDeNota(`intento 1: ${PREFIJO_SIN_RESPUESTA} (sin respuesta tras 10 s)`).causa).toBe("resend_caido");
  });

  it("toda causa trae etiqueta y que_hacer escritos para una persona", () => {
    const todas: CausaDeFallo[] = ["remitente_sin_verificar", "clave_invalida", "limite_de_envios", "resend_caido", "configuracion_faltante", "sin_destinatario", "rechazo_de_resend", "otra"];
    const notas = [
      `Resend respondió 403: ${JSON_A}`, "Resend respondió 401: ", "Resend respondió 429: ", "Resend respondió 500: ",
      "RESEND_FROM no configurada", NOTA_SIN_DESTINATARIO, "Resend respondió 422: x", "",
    ];
    expect(notas.map((n) => causaDeNota(n).causa)).toEqual(todas);
    for (const n of notas) {
      const c = causaDeNota(n);
      expect(c.etiqueta.length).toBeGreaterThan(10);
      expect(c.que_hacer.length).toBeGreaterThan(10);
    }
  });
});

describe("causaDeRespuesta: lo que ve la ruta en el momento del envío", () => {
  it("los dos 403 dan la misma causa que sus notas", () => {
    expect(causaDeRespuesta({ status: 403, cuerpo: JSON_A }).causa).toBe("remitente_sin_verificar");
    expect(causaDeRespuesta({ status: 403, cuerpo: JSON_B })).toEqual(causaDeRespuesta({ status: 403, cuerpo: JSON_A }));
    expect(causaDeRespuesta({ status: 403, cuerpo: JSON.stringify({ message: SOLO_PROPIO }) }).causa).toBe("remitente_sin_verificar");
  });

  it("error de red o tiempo agotado (sin status) es Resend caído, del canal", () => {
    const c = causaDeRespuesta({ status: null, cuerpo: "", red: true });
    expect(c.causa).toBe("resend_caido");
    expect(c.del_canal).toBe(true);
  });

  it("401, 429, 500/502, 422 y vacío", () => {
    expect(causaDeRespuesta({ status: 401, cuerpo: "" }).causa).toBe("clave_invalida");
    expect(causaDeRespuesta({ status: 429, cuerpo: "" }).causa).toBe("limite_de_envios");
    expect(causaDeRespuesta({ status: 500, cuerpo: "" }).causa).toBe("resend_caido");
    expect(causaDeRespuesta({ status: 502, cuerpo: "<html>" }).causa).toBe("resend_caido");
    const r422 = causaDeRespuesta({ status: 422, cuerpo: '{"message":"Invalid `to` field.","name":"validation_error"}' });
    expect(r422.causa).toBe("rechazo_de_resend");
    expect(r422.del_canal).toBe(false);
    expect(causaDeRespuesta({ status: null, cuerpo: "" }).causa).toBe("otra");
  });

  it("un 403 sin mensaje reconocible NO es remitente ni clave", () => {
    expect(causaDeRespuesta({ status: 403, cuerpo: "" }).causa).toBe("otra");
  });
});

// Las averías de la clave que documenta Resend (https://resend.com/docs/api-reference/errors).
// Todas se arreglan igual —otra clave—, y todas fallan igual en CADA fila: si una cae
// en «otra», el lote vuelve a gastar un intento por fila contra una avería ajena.
describe("la clave de envío: todas las formas en que Resend la rechaza", () => {
  it.each<[string, number, string]>([
    ["401 validation_error «API key is invalid» (la forma ACTUAL en el envío)", 401, '{"statusCode":401,"message":"API key is invalid","name":"validation_error"}'],
    ["400 «API key is invalid» (otros endpoints)", 400, '{"statusCode":400,"message":"API key is invalid","name":"validation_error"}'],
    ["403 invalid_api_key (la forma antigua)", 403, '{"statusCode":403,"message":"API key is invalid","name":"invalid_api_key"}'],
    ["401 missing_api_key", 401, '{"statusCode":401,"message":"Missing API key in the authorization header.","name":"missing_api_key"}'],
    ["403 suspended_api_key (clave filtrada y suspendida)", 403, '{"statusCode":403,"message":"This API key is suspended","name":"suspended_api_key"}'],
    ["403 «This API key is suspended» (sin name)", 403, '{"statusCode":403,"message":"This API key is suspended"}'],
    ["403 «API key is not active» (sin name)", 403, '{"statusCode":403,"message":"API key is not active"}'],
    ["403 restricted_api_key", 403, '{"statusCode":403,"message":"API key is not active","name":"restricted_api_key"}'],
    ["401 restricted_api_key «restricted to only send emails»", 401, '{"statusCode":401,"message":"This API key is restricted to only send emails.","name":"restricted_api_key"}'],
    ["403 invalid_permission", 403, '{"statusCode":403,"message":"This API key does not have permission to send emails.","name":"invalid_permission"}'],
    ["403 «missing required scopes»", 403, '{"statusCode":403,"message":"Your key is missing required scopes: emails:send","name":"forbidden"}'],
  ])("%s -> clave_invalida, del canal (en la respuesta y en la nota)", (_nombre, status, cuerpo) => {
    const r = causaDeRespuesta({ status, cuerpo });
    expect(r.causa).toBe("clave_invalida");
    expect(r.del_canal).toBe(true);
    expect(causaDeNota(`intento 2: Resend respondió ${status}: ${cuerpo}`).causa).toBe("clave_invalida");
  });

  it("si el cuerpo quedó cortado pero el name de la clave ya se leía, se reconoce por texto", () => {
    const cortado = '{"statusCode":403,"name":"suspended_api_key","message":"This API ke';
    expect(() => JSON.parse(cortado)).toThrow();
    expect(causaDeRespuesta({ status: 403, cuerpo: cortado }).causa).toBe("clave_invalida");
  });

  it("un 403 que no habla de la clave sigue sin asumirse clave", () => {
    expect(causaDeRespuesta({ status: 403, cuerpo: '{"statusCode":403,"message":"Access denied for this resource","name":"forbidden"}' }).causa).toBe("otra");
  });
});

describe("el límite de envíos: por segundo, cuota diaria y cuota mensual se arreglan distinto", () => {
  const SEGUNDO = '{"statusCode":429,"message":"Too many requests. Please limit the number of requests per second.","name":"rate_limit_exceeded"}';
  const DIARIA = '{"statusCode":429,"message":"You have reached your daily email sending quota.","name":"daily_quota_exceeded"}';
  const MENSUAL = '{"statusCode":429,"message":"You have reached your monthly email sending quota.","name":"monthly_quota_exceeded"}';

  it.each<[string, string, string]>([
    ["por segundo", SEGUNDO, "por_segundo"],
    ["diaria", DIARIA, "cuota_diaria"],
    ["mensual", MENSUAL, "cuota_mensual"],
    ["429 sin cuerpo", "", "desconocido"],
  ])("%s -> limite_de_envios con limite=%s, del canal", (_n, cuerpo, limite) => {
    for (const c of [causaDeRespuesta({ status: 429, cuerpo }), causaDeNota(`intento 1: Resend respondió 429: ${cuerpo}`)]) {
      expect(c.causa).toBe("limite_de_envios");
      expect(c.del_canal).toBe(true);
      expect(c.limite).toBe(limite);
    }
  });

  it("cada límite dice algo distinto que hacer: por segundo transitorio, diaria a medianoche UTC, mensual sube de plan", () => {
    const qh = (cuerpo: string) => causaDeRespuesta({ status: 429, cuerpo }).que_hacer;
    expect(qh(SEGUNDO)).toMatch(/transitorio/i);
    expect(qh(DIARIA)).toMatch(/medianoche UTC/);
    expect(qh(MENSUAL)).toMatch(/mes siguiente/);
    expect(qh(MENSUAL)).toMatch(/resend\.com\/settings\/billing/);
    expect(qh(MENSUAL)).not.toMatch(/^Espera/);
    expect(new Set([qh(SEGUNDO), qh(DIARIA), qh(MENSUAL), qh("")]).size).toBe(4);
  });

  it("solo la causa del límite lleva el campo `limite`", () => {
    expect(causaDeRespuesta({ status: 403, cuerpo: JSON_A }).limite).toBeUndefined();
    expect(causaDeRespuesta({ status: 500, cuerpo: "" }).limite).toBeUndefined();
  });
});

describe("el cuerpo que no llegó", () => {
  it("la nota «(cuerpo no recibido)» no cambia la causa que da el status", () => {
    expect(NOTA_CUERPO_NO_RECIBIDO).toBe("(cuerpo no recibido)");
    expect(causaDeNota(`intento 1: Resend respondió 403: ${NOTA_CUERPO_NO_RECIBIDO}`).causa).toBe("otra");
    expect(causaDeNota(`intento 1: Resend respondió 401: ${NOTA_CUERPO_NO_RECIBIDO}`).causa).toBe("clave_invalida");
    expect(causaDeNota(`intento 1: Resend respondió 502: ${NOTA_CUERPO_NO_RECIBIDO}`).causa).toBe("resend_caido");
    expect(causaDeNota(`intento 1: Resend respondió 429: ${NOTA_CUERPO_NO_RECIBIDO}`).limite).toBe("desconocido");
  });
});

describe("agruparCausas", () => {
  it("el caso de la captura: dos 403 (distinto orden de llaves) + un «sin líder» = 2 causas, en orden de aparición", () => {
    const grupos = agruparCausas([
      `intento 3: Resend respondió 403: ${JSON_A}`,
      `intento 3: Resend respondió 403: ${JSON_B}`,
      "intento 3: sin líder de equipo con correo activo en esa sede",
    ]);
    expect(grupos.map((g) => g.causa)).toEqual(["remitente_sin_verificar", "sin_destinatario"]);
  });

  it("respeta el orden de aparición y no repite", () => {
    const g = agruparCausas(["intento 1: sin encargada con correo", `intento 1: Resend respondió 403: ${JSON_A}`, `intento 2: ${NOTA_SIN_DESTINATARIO}`]);
    expect(g.map((x) => x.causa)).toEqual(["sin_destinatario", "remitente_sin_verificar"]);
  });

  it("sin notas, sin causas", () => {
    expect(agruparCausas([])).toEqual([]);
  });
});

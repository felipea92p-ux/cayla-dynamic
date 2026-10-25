import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// La ruta que despacha los correos de `alertas`, probada con una base y un
// Resend de mentira: lo que importa es QUÉ HACE el lote cuando el canal falla,
// no cómo se ve el JSON.

const { captureMessage, captureException, ahoraMs, esperarMs } = vi.hoisted(() => ({
  captureMessage: vi.fn(),
  captureException: vi.fn(),
  // El reloj y la espera de la ruta, sustituibles: un lote de 45 s no se prueba
  // esperando 45 s, ni un 429 «por segundo» esperando un segundo de verdad.
  ahoraMs: vi.fn<() => number>(),
  esperarMs: vi.fn<(ms: number) => Promise<void>>(),
}));
// Ruta hacia el paquete de la app, no el nombre pelado: `@sentry/nextjs` solo
// está instalado en apps/web, y desde tests/ el nombre no se resuelve, así que
// el mock quedaría registrado con un id que la ruta nunca importa.
vi.mock("../apps/web/node_modules/@sentry/nextjs", () => ({ captureMessage, captureException }));
vi.mock("@/lib/alertas/ritmo-del-despacho", async (original) => ({
  ...(await original<typeof import("@/lib/alertas/ritmo-del-despacho")>()),
  ahoraMs,
  esperarMs,
}));

const rpc = vi.fn();
vi.mock("@cayla-dynamic/database", () => ({ createServiceRoleClient: () => ({ rpc }) }));

interface Fila {
  alerta_id: string; tipo: string; payload: Record<string, unknown>;
  persona_nombre: string; sede_codigo: string; destinatarios: string[]; destinatarios_nombres: string[];
  intentos: number; estado_previo: string;
}
const fila = (n: number, extra: Partial<Fila> = {}): Fila => ({
  alerta_id: `a${n}`, tipo: "auto_cierre", payload: { fecha: "2026-10-20" }, persona_nombre: `Persona ${n}`,
  sede_codigo: "TRU", destinatarios: ["lider@cayla.pe"], destinatarios_nombres: ["Líder"], intentos: 0, estado_previo: "pendiente", ...extra,
});

function base(filas: Fila[], devolverIntento: () => Promise<unknown> = async () => ({ data: null, error: null })) {
  rpc.mockImplementation(async (nombre: string) => {
    if (nombre === "fn_alertas_email_pendientes") return { data: filas, error: null };
    if (nombre === "fn_alertas_reservar") return { data: true, error: null };
    if (nombre === "fn_alertas_devolver_intento") return devolverIntento();
    return { data: null, error: null };
  });
}

const JSON_403 = '{"statusCode":403,"message":"The cayla.pe domain is not verified. Please, add and verify your domain on https://resend.com/domains","name":"validation_error"}';
const respuesta = (status: number, cuerpo: string, headers: Record<string, string> = {}) => new Response(cuerpo, { status, headers });
const JSON_401 = '{"statusCode":401,"message":"API key is invalid","name":"validation_error"}';
const JSON_SUSPENDIDA = '{"statusCode":403,"message":"This API key is suspended","name":"suspended_api_key"}';
const JSON_SEGUNDO = '{"statusCode":429,"message":"Too many requests. Please limit the number of requests per second.","name":"rate_limit_exceeded"}';
const JSON_DIARIA = '{"statusCode":429,"message":"You have reached your daily email sending quota.","name":"daily_quota_exceeded"}';
const JSON_MENSUAL = '{"statusCode":429,"message":"You have reached your monthly email sending quota.","name":"monthly_quota_exceeded"}';
// Un 403 que Dynamic no sabe leer: cae en «otra», causa de FILA.
const JSON_DESCONOCIDO = '{"statusCode":403,"message":"Access denied for this resource","name":"forbidden"}';
const JSON_422 = '{"statusCode":422,"message":"Invalid `to` field.","name":"validation_error"}';

async function despachar() {
  vi.resetModules();
  const { GET } = await import("@/app/api/alertas-encargadas/route");
  const res = await GET(new Request("http://x/api/alertas-encargadas", { headers: { authorization: "Bearer secreto" } }));
  return { status: res.status, json: await res.json() };
}

const llamadasA = (nombre: string) => rpc.mock.calls.filter((c) => c[0] === nombre);

beforeEach(() => {
  vi.stubEnv("CRON_SECRET", "secreto");
  vi.stubEnv("RESEND_API_KEY", "re_test");
  vi.stubEnv("RESEND_FROM", "Dynamic <avisos@cayla.pe>");
  captureMessage.mockReset(); captureException.mockReset(); rpc.mockReset();
  ahoraMs.mockReset(); ahoraMs.mockImplementation(() => Date.now());
  esperarMs.mockReset(); esperarMs.mockResolvedValue(undefined);
});
afterEach(() => {
  vi.unstubAllEnvs(); vi.unstubAllGlobals(); vi.useRealTimers();
});

describe("ruta de alertas por correo: una avería de canal no mata N filas", () => {
  it("403 de dominio sin verificar: gasta el intento de UNA fila, corta el lote y avisa UNA vez", async () => {
    base([fila(1), fila(2), fila(3)]);
    const fetchMock = vi.fn().mockImplementation(async () => respuesta(403, JSON_403));
    vi.stubGlobal("fetch", fetchMock);

    const { status, json } = await despachar();

    expect(status).toBe(200);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(llamadasA("fn_alertas_reservar")).toHaveLength(1); // las otras dos NO gastan intento
    const marcas = llamadasA("fn_marcar_alerta_resultado");
    expect(marcas).toHaveLength(1);
    expect(marcas[0][1]).toMatchObject({ p_id: "a1", p_exito: false });
    expect(marcas[0][1].p_nota).toMatch(/^intento 1: Resend respondió 403/);
    expect(json.cortadoPorCanal).toEqual({ causa: "remitente_sin_verificar", sinIntentar: 2 });
    expect(json).toMatchObject({ procesadas: 3, enviadas: 0, fallidas: 1 });

    const errores = captureMessage.mock.calls.filter((c) => c[1]?.level === "error");
    expect(errores).toHaveLength(1);
    expect(errores[0][0]).toMatch(/dominio del remitente no está verificado/);
    expect(errores[0][0]).toMatch(/2 aviso\(s\) quedaron sin intentar/);
    // y no suena además el warning genérico por la misma avería
    expect(captureMessage.mock.calls.filter((c) => c[1]?.level === "warning")).toHaveLength(0);
  });

  it("una caída de red NO aborta el lote con 500: es «Resend caído», y corta a la SEGUNDA fila seguida", async () => {
    base([fila(1), fila(2), fila(3)]);
    const fetchMock = vi.fn().mockRejectedValue(new TypeError("fetch failed"));
    vi.stubGlobal("fetch", fetchMock);

    const { status, json } = await despachar();

    expect(status).toBe(200);
    expect(fetchMock).toHaveBeenCalledTimes(2); // la primera es «fallo de fila»; la segunda confirma la avería
    expect(json.cortadoPorCanal).toEqual({ causa: "resend_caido", sinIntentar: 1 });
    expect(llamadasA("fn_marcar_alerta_resultado")[0][1].p_nota).toMatch(/^intento 1: Resend no respondió \(error de red: fetch failed\)/);
    expect(captureException).not.toHaveBeenCalled();
  });

  it("el tiempo agotado REAL (DOMException TimeoutError, como lo lanza AbortSignal.timeout) se dice como tal, y el fetch lleva un límite de tiempo", async () => {
    base([fila(1)]);
    const fetchMock = vi.fn().mockRejectedValue(new DOMException("The operation was aborted due to timeout", "TimeoutError"));
    vi.stubGlobal("fetch", fetchMock);

    const { json } = await despachar();

    expect(fetchMock.mock.calls[0][1].signal).toBeInstanceOf(AbortSignal);
    expect(llamadasA("fn_marcar_alerta_resultado")[0][1].p_nota).toMatch(/sin respuesta tras 10 s/);
    expect(json).toMatchObject({ fallidas: 1, cortadoPorCanal: null }); // una sola caída no corta
  });

  it("un fallo de FILA (422) no corta: sigue con la siguiente y avisa como warning", async () => {
    base([fila(1), fila(2)]);
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(respuesta(422, '{"statusCode":422,"message":"Invalid `to` field.","name":"validation_error"}'))
      .mockResolvedValueOnce(respuesta(200, "{}"));
    vi.stubGlobal("fetch", fetchMock);

    const { json } = await despachar();

    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(json).toMatchObject({ enviadas: 1, fallidas: 1, cortadoPorCanal: null });
    expect(captureMessage.mock.calls.filter((c) => c[1]?.level === "error")).toHaveLength(0);
    expect(captureMessage.mock.calls.filter((c) => c[1]?.level === "warning")).toHaveLength(1);
  });

  it("sin destinatario: nota con la verdad, no corta, y no llama a Resend", async () => {
    base([fila(1, { destinatarios: [] }), fila(2)]);
    const fetchMock = vi.fn().mockImplementation(async () => respuesta(200, "{}"));
    vi.stubGlobal("fetch", fetchMock);

    const { json } = await despachar();

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(llamadasA("fn_marcar_alerta_resultado")[0][1].p_nota).toBe(
      "intento 1: sin ningún destinatario con correo (ni líder de equipo activo de la sede ni la propia persona)",
    );
    expect(json).toMatchObject({ sinDestinatario: 1, enviadas: 1, cortadoPorCanal: null });
  });

  it("RESEND_FROM sin configurar corta en la primera fila sin llamar a Resend", async () => {
    vi.stubEnv("RESEND_FROM", "");
    base([fila(1), fila(2), fila(3)]);
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    const { json } = await despachar();

    expect(fetchMock).not.toHaveBeenCalled();
    expect(json.cortadoPorCanal).toEqual({ causa: "configuracion_faltante", sinIntentar: 2 });
  });
});

describe("ruta de alertas por correo: los días se cuentan al ENVIAR", () => {
  function correoEnviado(fetchMock: ReturnType<typeof vi.fn>): { subject: string; text: string } {
    return JSON.parse(fetchMock.mock.calls[0][1].body);
  }

  it("contrato: una fila generada con «12 días» que sale 4 días después dice 8", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2026-10-28T15:00:00Z")); // 10:00 en Lima
    base([fila(1, {
      tipo: "contrato_por_vencer",
      payload: { persona: "Ana Pérez", sede: "TRU", fecha_fin_contrato: "2026-11-05", dias_restantes: 12 },
    })]);
    const fetchMock = vi.fn().mockImplementation(async () => respuesta(200, "{}"));
    vi.stubGlobal("fetch", fetchMock);

    await despachar();

    const c = correoEnviado(fetchMock);
    expect(c.subject).toBe("Dynamic: el contrato de Ana Pérez vence en 8 días");
    expect(c.text).toContain("vence el 2026-11-05 — en 8 días.");
    expect(c.text).not.toMatch(/12/);
  });

  it("el día en Lima, no en UTC: a las 21:00 de Lima ya es el día siguiente en UTC y NO debe contar", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2026-10-29T02:00:00Z")); // 28-oct 21:00 en Lima
    base([fila(1, {
      tipo: "contrato_por_vencer",
      payload: { persona: "Ana", sede: "TRU", fecha_fin_contrato: "2026-10-29", dias_restantes: 3 },
    })]);
    const fetchMock = vi.fn().mockImplementation(async () => respuesta(200, "{}"));
    vi.stubGlobal("fetch", fetchMock);

    await despachar();

    expect(correoEnviado(fetchMock).subject).toBe("Dynamic: el contrato de Ana vence mañana");
  });

  it("vacaciones cuya fecha ya pasó mientras la fila esperaba: pide revisar, no afirma", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2026-10-28T15:00:00Z"));
    base([fila(1, {
      tipo: "vacaciones_por_vencer",
      payload: { persona: "Luis", sede: "LIM", records_vencidos: 0, vence_el: "2026-10-26", dias_para_vencer: 5, dias_pendientes: 20 },
    })]);
    const fetchMock = vi.fn().mockImplementation(async () => respuesta(200, "{}"));
    vi.stubGlobal("fetch", fetchMock);

    await despachar();

    const c = correoEnviado(fetchMock);
    expect(c.subject).toBe("Dynamic: el plazo de vacaciones de Luis ya venció");
    expect(c.text).toContain("venció el 2026-10-26 — hace 2 días");
    expect(c.text).toContain("Revisa en Ausencias si ya las gozó");
  });

  it("vacaciones con récords ya vencidos desde que se generó: el asunto de siempre", async () => {
    base([fila(1, {
      tipo: "vacaciones_por_vencer",
      payload: { persona: "Luis", sede: "LIM", records_vencidos: 2, vence_el: "2027-03-01", dias_para_vencer: 100, dias_pendientes: 50 },
    })]);
    const fetchMock = vi.fn().mockImplementation(async () => respuesta(200, "{}"));
    vi.stubGlobal("fetch", fetchMock);

    await despachar();

    const c = correoEnviado(fetchMock);
    expect(c.subject).toBe("Dynamic: Luis ya tiene vacaciones vencidas");
    expect(c.text).toContain("ya tenía 2 récord(s) de vacaciones vencido(s)");
  });

  it("sin fecha en el payload cae al número que trae, como antes", async () => {
    base([fila(1, {
      tipo: "contrato_por_vencer",
      payload: { persona: "Ana", sede: "TRU", dias_restantes: 9 },
    })]);
    const fetchMock = vi.fn().mockImplementation(async () => respuesta(200, "{}"));
    vi.stubGlobal("fetch", fetchMock);

    await despachar();

    expect(correoEnviado(fetchMock).subject).toBe("Dynamic: el contrato de Ana vence en 9 días");
  });
});

describe("ruta de alertas por correo: la clave y el límite, según lo que documenta Resend", () => {
  it("401 «API key is invalid» (la forma actual de Resend en el envío) es clave inválida: corta y devuelve el intento", async () => {
    base([fila(1), fila(2), fila(3)]);
    vi.stubGlobal("fetch", vi.fn().mockImplementation(async () => respuesta(401, JSON_401)));

    const { json } = await despachar();

    expect(json.cortadoPorCanal).toEqual({ causa: "clave_invalida", sinIntentar: 2 });
    expect(llamadasA("fn_alertas_devolver_intento")).toEqual([["fn_alertas_devolver_intento", { p_id: "a1" }]]);
  });

  it("403 suspended_api_key (clave filtrada y suspendida) corta a la primera: antes caía en «otra» y mataba las 61 filas", async () => {
    base([fila(1), fila(2), fila(3)]);
    const fetchMock = vi.fn().mockImplementation(async () => respuesta(403, JSON_SUSPENDIDA));
    vi.stubGlobal("fetch", fetchMock);

    const { json } = await despachar();

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(json.cortadoPorCanal).toEqual({ causa: "clave_invalida", sinIntentar: 2 });
    expect(llamadasA("fn_alertas_reservar")).toHaveLength(1);
  });

  it("429 «por segundo»: espera lo que dice retry-after (techo 2 s) y reintenta UNA vez; si sale, el lote sigue", async () => {
    base([fila(1), fila(2)]);
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(respuesta(429, JSON_SEGUNDO, { "retry-after": "1" }))
      .mockImplementation(async () => respuesta(200, "{}"));
    vi.stubGlobal("fetch", fetchMock);

    const { json } = await despachar();

    expect(esperarMs).toHaveBeenCalledTimes(1);
    expect(esperarMs).toHaveBeenCalledWith(1000);
    expect(fetchMock).toHaveBeenCalledTimes(3); // fila 1 dos veces, fila 2 una
    expect(json).toMatchObject({ enviadas: 2, fallidas: 0, cortadoPorCanal: null });
    expect(llamadasA("fn_marcar_alerta_resultado").every((c) => c[1].p_exito === true)).toBe(true);
  });

  it.each<[string | undefined, number]>([[undefined, 1000], ["5", 2000], ["0.5", 500]])(
    "429 por segundo con retry-after=%s espera %i ms",
    async (retryAfter, esperado) => {
      base([fila(1)]);
      vi.stubGlobal("fetch", vi.fn()
        .mockResolvedValueOnce(respuesta(429, JSON_SEGUNDO, retryAfter ? { "retry-after": retryAfter } : {}))
        .mockImplementation(async () => respuesta(200, "{}")));

      await despachar();

      expect(esperarMs).toHaveBeenCalledWith(esperado);
    },
  );

  it("429 «por segundo» que SIGUE tras el reintento: corta el lote, sin devolver el intento", async () => {
    base([fila(1), fila(2), fila(3)]);
    const fetchMock = vi.fn().mockImplementation(async () => respuesta(429, JSON_SEGUNDO));
    vi.stubGlobal("fetch", fetchMock);

    const { json } = await despachar();

    expect(fetchMock).toHaveBeenCalledTimes(2); // un envío y UN reintento, no más
    expect(esperarMs).toHaveBeenCalledTimes(1);
    expect(json.cortadoPorCanal).toEqual({ causa: "limite_de_envios", sinIntentar: 2 });
    expect(llamadasA("fn_alertas_devolver_intento")).toHaveLength(0);
  });

  it.each([["diaria", JSON_DIARIA], ["mensual", JSON_MENSUAL]])(
    "429 de cuota %s: no espera ni reintenta, corta a la primera y el aviso dice qué hacer",
    async (_nombre, cuerpo) => {
      base([fila(1), fila(2)]);
      const fetchMock = vi.fn().mockImplementation(async () => respuesta(429, cuerpo));
      vi.stubGlobal("fetch", fetchMock);

      const { json } = await despachar();

      expect(fetchMock).toHaveBeenCalledTimes(1);
      expect(esperarMs).not.toHaveBeenCalled();
      expect(json.cortadoPorCanal).toEqual({ causa: "limite_de_envios", sinIntentar: 1 });
      expect(llamadasA("fn_alertas_devolver_intento")).toHaveLength(0);
    },
  );
});

describe("ruta de alertas por correo: devolver el intento solo cuando la fila no tuvo culpa", () => {
  it("dominio sin verificar: devuelve el intento de ESA fila, después de marcarla fallida", async () => {
    base([fila(1), fila(2)]);
    vi.stubGlobal("fetch", vi.fn().mockImplementation(async () => respuesta(403, JSON_403)));

    await despachar();

    const orden = rpc.mock.calls.map((c) => c[0]);
    expect(orden.indexOf("fn_alertas_devolver_intento")).toBeGreaterThan(orden.indexOf("fn_marcar_alerta_resultado"));
    expect(llamadasA("fn_alertas_devolver_intento")).toEqual([["fn_alertas_devolver_intento", { p_id: "a1" }]]);
  });

  it("RESEND_FROM sin configurar: también la devuelve", async () => {
    vi.stubEnv("RESEND_FROM", "");
    base([fila(1), fila(2)]);
    vi.stubGlobal("fetch", vi.fn());

    await despachar();

    expect(llamadasA("fn_alertas_devolver_intento")).toHaveLength(1);
  });

  it("el límite de envíos y la caída de Resend NO la devuelven (la fila pudo tener culpa)", async () => {
    base([fila(1), fila(2)]);
    vi.stubGlobal("fetch", vi.fn().mockImplementation(async () => respuesta(500, "boom")));
    await despachar();
    expect(llamadasA("fn_alertas_devolver_intento")).toHaveLength(0);
  });

  it("si la 0548 todavía no está pegada (PGRST202 o 42883) la ruta sigue como hoy, sin ruido", async () => {
    for (const code of ["PGRST202", "42883"]) {
      rpc.mockReset(); captureException.mockReset(); captureMessage.mockReset();
      base([fila(1), fila(2)], async () => ({ data: null, error: { code, message: "Could not find the function public.fn_alertas_devolver_intento" } }));
      vi.stubGlobal("fetch", vi.fn().mockImplementation(async () => respuesta(403, JSON_403)));

      const { status, json } = await despachar();

      expect(status).toBe(200);
      expect(json.cortadoPorCanal).toEqual({ causa: "remitente_sin_verificar", sinIntentar: 1 });
      expect(captureException).not.toHaveBeenCalled();
    }
  });

  it("cualquier otro error de esa función va a Sentry como excepción, sin abortar el lote", async () => {
    base([fila(1), fila(2)], async () => ({ data: null, error: { code: "42501", message: "permission denied" } }));
    vi.stubGlobal("fetch", vi.fn().mockImplementation(async () => respuesta(403, JSON_403)));

    const { status, json } = await despachar();

    expect(status).toBe(200);
    expect(json.cortadoPorCanal).toEqual({ causa: "remitente_sin_verificar", sinIntentar: 1 });
    expect(captureException).toHaveBeenCalledTimes(1);
    expect(String(captureException.mock.calls[0][0])).toMatch(/fn_alertas_devolver_intento falló para a1: permission denied/);
    // y el aviso de la avería sale igual
    expect(captureMessage.mock.calls.filter((c) => c[1]?.level === "error")).toHaveLength(1);
  });

  it("si la llamada lanza en vez de devolver error, tampoco aborta el lote", async () => {
    base([fila(1), fila(2)], async () => { throw new Error("red caída"); });
    vi.stubGlobal("fetch", vi.fn().mockImplementation(async () => respuesta(403, JSON_403)));

    const { status } = await despachar();

    expect(status).toBe(200);
    expect(captureException).toHaveBeenCalledTimes(1);
  });
});

describe("ruta de alertas por correo: caídas de Resend y disyuntor", () => {
  it("una sola respuesta 5xx NO corta (puede ser una fila envenenada): se sigue y avisa como warning", async () => {
    base([fila(1), fila(2), fila(3)]);
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(respuesta(500, '{"statusCode":500,"message":"An unexpected error occurred.","name":"application_error"}'))
      .mockImplementation(async () => respuesta(200, "{}"));
    vi.stubGlobal("fetch", fetchMock);

    const { json } = await despachar();

    expect(fetchMock).toHaveBeenCalledTimes(3);
    expect(json).toMatchObject({ enviadas: 2, fallidas: 1, cortadoPorCanal: null });
    expect(captureMessage.mock.calls.filter((c) => c[1]?.level === "error")).toHaveLength(0);
    expect(captureMessage.mock.calls.filter((c) => c[1]?.level === "warning")).toHaveLength(1);
  });

  it("dos 5xx SEGUIDAS cortan en la segunda, sin devolver el intento", async () => {
    base([fila(1), fila(2), fila(3), fila(4)]);
    const fetchMock = vi.fn().mockImplementation(async () => respuesta(503, '{"statusCode":503,"message":"API is temporarily unavailable","name":"service_unavailable"}'));
    vi.stubGlobal("fetch", fetchMock);

    const { json } = await despachar();

    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(json.cortadoPorCanal).toEqual({ causa: "resend_caido", sinIntentar: 2 });
    expect(llamadasA("fn_alertas_devolver_intento")).toHaveLength(0);
  });

  it("dos 5xx NO seguidas (hay un éxito en medio) no cortan", async () => {
    base([fila(1), fila(2), fila(3)]);
    vi.stubGlobal("fetch", vi.fn()
      .mockResolvedValueOnce(respuesta(500, "x"))
      .mockResolvedValueOnce(respuesta(200, "{}"))
      .mockResolvedValueOnce(respuesta(500, "x")));

    const { json } = await despachar();

    expect(json).toMatchObject({ enviadas: 1, fallidas: 2, cortadoPorCanal: null });
  });

  it("disyuntor: 3 fallos seguidos de una causa que Dynamic no reconoce se tratan como avería del canal", async () => {
    base([fila(1), fila(2), fila(3), fila(4), fila(5)]);
    const fetchMock = vi.fn().mockImplementation(async () => respuesta(403, JSON_DESCONOCIDO));
    vi.stubGlobal("fetch", fetchMock);

    const { json } = await despachar();

    expect(fetchMock).toHaveBeenCalledTimes(3);
    expect(json.cortadoPorCanal).toEqual({ causa: "otra", sinIntentar: 2 });
    expect(llamadasA("fn_alertas_devolver_intento")).toHaveLength(0);
    const errores = captureMessage.mock.calls.filter((c) => c[1]?.level === "error");
    expect(errores).toHaveLength(1);
    expect(errores[0][0]).toMatch(/3 envíos seguidos fallaron por lo mismo/);
    expect(errores[0][0]).toMatch(/2 aviso\(s\) quedaron sin intentar/);
    expect(captureMessage.mock.calls.filter((c) => c[1]?.level === "warning")).toHaveLength(0);
  });

  it("disyuntor: dos fallos, un éxito y dos fallos más NO cortan (el éxito reinicia la cuenta)", async () => {
    base([fila(1), fila(2), fila(3), fila(4), fila(5), fila(6)]);
    vi.stubGlobal("fetch", vi.fn()
      .mockResolvedValueOnce(respuesta(403, JSON_DESCONOCIDO))
      .mockResolvedValueOnce(respuesta(403, JSON_DESCONOCIDO))
      .mockResolvedValueOnce(respuesta(200, "{}"))
      .mockResolvedValueOnce(respuesta(403, JSON_DESCONOCIDO))
      .mockResolvedValueOnce(respuesta(403, JSON_DESCONOCIDO))
      .mockResolvedValueOnce(respuesta(200, "{}")));

    const { json } = await despachar();

    expect(json).toMatchObject({ enviadas: 2, fallidas: 4, cortadoPorCanal: null });
  });

  it("disyuntor: causas de fila DISTINTAS en medio no cuentan como «lo mismo»", async () => {
    base([fila(1), fila(2), fila(3)]);
    vi.stubGlobal("fetch", vi.fn()
      .mockResolvedValueOnce(respuesta(403, JSON_DESCONOCIDO))
      .mockResolvedValueOnce(respuesta(422, JSON_422))
      .mockResolvedValueOnce(respuesta(403, JSON_DESCONOCIDO)));

    const { json } = await despachar();

    expect(json).toMatchObject({ fallidas: 3, cortadoPorCanal: null });
  });

  it("disyuntor: los «sin destinatario» no pasan por Resend, así que no suman ni reinician", async () => {
    base([fila(1), fila(2), fila(3, { destinatarios: [] }), fila(4), fila(5)]);
    const fetchMock = vi.fn().mockImplementation(async () => respuesta(403, JSON_DESCONOCIDO));
    vi.stubGlobal("fetch", fetchMock);

    const { json } = await despachar();

    // a1, a2 y a4 son los tres seguidos: el sin destinatario (a3) no los interrumpe ni cuenta como cuarto.
    expect(fetchMock).toHaveBeenCalledTimes(3);
    expect(json).toMatchObject({ sinDestinatario: 1, fallidas: 3, cortadoPorCanal: { causa: "otra", sinIntentar: 1 } });
  });
});

describe("ruta de alertas por correo: el cuerpo que no llegó", () => {
  it("un 403 con cuerpo vacío deja la nota «cuerpo no recibido» (no un «Resend respondió 403: » mudo)", async () => {
    base([fila(1)]);
    vi.stubGlobal("fetch", vi.fn().mockImplementation(async () => respuesta(403, "")));

    await despachar();

    expect(llamadasA("fn_marcar_alerta_resultado")[0][1].p_nota).toBe("intento 1: Resend respondió 403: (cuerpo no recibido)");
  });

  it("si el cuerpo se cuelga y vence el tiempo al leerlo, es lo mismo", async () => {
    base([fila(1)]);
    const colgada = { ok: false, status: 403, headers: new Headers(), text: () => Promise.reject(new DOMException("timeout", "TimeoutError")) };
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(colgada));

    await despachar();

    expect(llamadasA("fn_marcar_alerta_resultado")[0][1].p_nota).toBe("intento 1: Resend respondió 403: (cuerpo no recibido)");
  });
});

describe("ruta de alertas por correo: tope de tiempo del lote", () => {
  /** Cada envío «tarda» `msPorEnvio` en el reloj de mentira. */
  function relojQueAvanza(msPorEnvio: number) {
    let t = 0;
    ahoraMs.mockImplementation(() => t);
    return vi.fn().mockImplementation(async () => { t += msPorEnvio; return respuesta(200, "{}"); });
  }

  it("pasados 45 s deja de reservar, responde con cortadoPorTiempo y avisa aparte, como warning", async () => {
    base([fila(1), fila(2), fila(3), fila(4), fila(5)]);
    const fetchMock = relojQueAvanza(20_000);
    vi.stubGlobal("fetch", fetchMock);

    const { status, json } = await despachar();

    expect(status).toBe(200);
    expect(fetchMock).toHaveBeenCalledTimes(3); // 20 s, 40 s, 60 s: en la vuelta 4 ya pasó de 45 s
    expect(llamadasA("fn_alertas_reservar")).toHaveLength(3); // las dos que sobran NO gastan intento
    expect(json).toMatchObject({ procesadas: 5, enviadas: 3, cortadoPorCanal: null, cortadoPorTiempo: { sinIntentar: 2 } });

    const avisos = captureMessage.mock.calls.filter((c) => /por tiempo/.test(c[0]));
    expect(avisos).toHaveLength(1);
    expect(avisos[0][0]).toMatch(/2 aviso\(s\) salen mañana/);
    expect(avisos[0][1].level).toBe("warning");
    // separado del aviso de canal: no suena ningún error
    expect(captureMessage.mock.calls.filter((c) => c[1]?.level === "error")).toHaveLength(0);
  });

  it("justo 45 000 ms todavía cabe (el corte es cuando se pasa, no cuando se llega)", async () => {
    base([fila(1), fila(2), fila(3)]);
    const fetchMock = relojQueAvanza(22_500); // tras 2 envíos: exactamente 45 000
    vi.stubGlobal("fetch", fetchMock);

    const { json } = await despachar();

    expect(fetchMock).toHaveBeenCalledTimes(3);
    expect(json.cortadoPorTiempo).toBeNull();
  });

  it("un lote que cabe no avisa nada por tiempo", async () => {
    base([fila(1), fila(2)]);
    vi.stubGlobal("fetch", relojQueAvanza(1_000));

    const { json } = await despachar();

    expect(json.cortadoPorTiempo).toBeNull();
    expect(captureMessage.mock.calls.filter((c) => /por tiempo/.test(c[0]))).toHaveLength(0);
  });
});

describe("ruta de alertas por correo: los correos que salen tarde no afirman de más", () => {
  function correoEnviado(fetchMock: ReturnType<typeof vi.fn>): { subject: string; text: string } {
    return JSON.parse(fetchMock.mock.calls[0][1].body);
  }
  async function enviar(f: Fila) {
    base([f]);
    const fetchMock = vi.fn().mockImplementation(async () => respuesta(200, "{}"));
    vi.stubGlobal("fetch", fetchMock);
    await despachar();
    return correoEnviado(fetchMock);
  }
  const ahora = (iso: string) => { vi.useFakeTimers({ toFake: ["Date"] }); vi.setSystemTime(new Date(iso)); };

  it("contrato que ya venció: dice que el aviso salió con retraso y pide confirmar en Contratos", async () => {
    ahora("2026-10-28T15:00:00Z");
    const c = await enviar(fila(1, { tipo: "contrato_por_vencer", payload: { persona: "Ana Pérez", sede: "TRU", fecha_fin_contrato: "2026-10-20", dias_restantes: 5 } }));
    expect(c.subject).toBe("Dynamic: el contrato de Ana Pérez venció hace 8 días");
    expect(c.text).toContain("venció el 2026-10-20 — hace 8 días. Este aviso salió con retraso: antes de actuar, confirma en Contratos si ya se renovó.");
  });

  it("contrato que todavía vence: NO lleva la advertencia de retraso", async () => {
    ahora("2026-10-28T15:00:00Z");
    const c = await enviar(fila(1, { tipo: "contrato_por_vencer", payload: { persona: "Ana", sede: "TRU", fecha_fin_contrato: "2026-11-05", dias_restantes: 12 } }));
    expect(c.text).not.toMatch(/retraso/);
  });

  it("vacaciones con récords vencidos: «Al generarse este aviso», lo que la norma PREVÉ (no «castiga») y confirmar antes de actuar", async () => {
    const c = await enviar(fila(1, { tipo: "vacaciones_por_vencer", payload: { persona: "Luis Soto", sede: "LIM", records_vencidos: 2, vence_el: "2027-03-01", dias_para_vencer: 100, dias_pendientes: 50 } }));
    expect(c.text).toContain("Al generarse este aviso, Luis Soto (LIM) ya tenía 2 récord(s) de vacaciones vencido(s)");
    expect(c.text).toContain("el art. 23 del D. Leg. 713 prevé una indemnización de una remuneración entera.");
    expect(c.text).toContain("Confirma en Ausencias que sigue así antes de actuar.");
    expect(c.text).not.toMatch(/castiga/);
  });

  it("vacaciones cuya fecha pasó mientras la fila esperaba: tampoco «castiga»", async () => {
    ahora("2026-10-28T15:00:00Z");
    const c = await enviar(fila(1, { tipo: "vacaciones_por_vencer", payload: { persona: "Luis", sede: "LIM", records_vencidos: 0, vence_el: "2026-10-26", dias_pendientes: 20 } }));
    expect(c.text).toContain("prevé una indemnización de una remuneración entera");
    expect(c.text).not.toMatch(/castiga/);
  });

  it("vacaciones sin vence_el ni dias_pendientes: no deja un verbo sin complemento ni un guion suelto", async () => {
    const c = await enviar(fila(1, { tipo: "vacaciones_por_vencer", payload: { persona: "Luis Soto", sede: "LIM" } }));
    expect(c.text).toContain("Las vacaciones de Luis Soto (LIM) vencen pronto (no se pudo calcular la fecha exacta).");
    expect(c.text).toContain("Tiene varios día(s) pendientes en total.");
    expect(c.text).not.toContain("Tiene —");
  });

  it("el cierre automático y el aviso genérico conservan su texto exacto", async () => {
    const auto = await enviar(fila(1, { tipo: "auto_cierre", payload: { fecha: "2026-10-20" }, persona_nombre: "Ana" }));
    expect(auto.subject).toBe("Dynamic: la jornada de Ana quedó sin cerrar (2026-10-20)");
    expect(auto.text).toBe(
      "Dynamic cerró sola la jornada de Ana el 2026-10-20 porque no se registró una salida.\n\n" +
      "Revísala en Correcciones antes de que se pague así: https://cayla-dynamic.vercel.app/admin/correcciones?fecha=2026-10-20\n\n" +
      "Este correo es un aviso automático — no es necesario responderlo.",
    );

    const generico = await enviar(fila(2, { tipo: "algo_nuevo", payload: { fecha: "2026-10-20" }, persona_nombre: "Ana" }));
    expect(generico.subject).toBe("Dynamic: aviso de Ana");
    expect(generico.text).toBe(
      'Hay un aviso pendiente de tipo "algo_nuevo" para Ana (2026-10-20). Revísalo en el panel: https://cayla-dynamic.vercel.app/admin/correcciones?fecha=2026-10-20',
    );
  });
});

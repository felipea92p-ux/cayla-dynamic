import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import {
  TEMAS,
  cuandoLeer,
  alVolverHayQueLeer,
  tocaElRespaldo,
  escucharTema,
  conexionDeTodos,
  ESPERA_RAFAGA_MS,
  MINIMO_ENTRE_LECTURAS_MS,
  MINIMO_AL_VOLVER_MS,
  RESPALDO_MS,
  CIERRE_DIFERIDO_MS,
  type ClienteTiempoReal,
} from "@/lib/tiempo-real";

// Tiempo real, lote 1 (2026-11-07, migración 0604). Lo que se prueba es CUÁNDO vuelve a leer una pantalla y cómo se
// comparten los canales; qué lee sigue siendo de la pantalla. Que la base avise de verdad lo prueba la pgTAP 491.

describe("cuandoLeer", () => {
  const base = { pendiente: true, visible: true, escribiendo: false, ahora: 100_000, ultimaLectura: 0 };

  it("con un aviso pendiente lee enseguida, esperando solo lo justo para juntar los avisos de una ráfaga", () => {
    expect(cuandoLeer(base)).toBe(ESPERA_RAFAGA_MS);
  });

  it("sin nada pendiente no lee", () => {
    expect(cuandoLeer({ ...base, pendiente: false })).toBeNull();
  });

  it("con la pestaña escondida espera: nadie la mira (al volver lee)", () => {
    expect(cuandoLeer({ ...base, visible: false })).toBeNull();
  });

  it("mientras alguien escribe espera: leer le pisaría lo que tecleó", () => {
    expect(cuandoLeer({ ...base, escribiendo: true })).toBeNull();
  });

  it("nunca dos lecturas en menos de un segundo, aunque los avisos no paren", () => {
    expect(cuandoLeer({ ...base, ultimaLectura: base.ahora - 100 })).toBe(MINIMO_ENTRE_LECTURAS_MS - 100);
    expect(cuandoLeer({ ...base, ultimaLectura: base.ahora })).toBe(MINIMO_ENTRE_LECTURAS_MS);
  });
});

describe("al volver y el respaldo", () => {
  it("al volver a la pestaña relee si la última lectura no fue recién", () => {
    expect(alVolverHayQueLeer(MINIMO_AL_VOLVER_MS, 0)).toBe(true);
    expect(alVolverHayQueLeer(MINIMO_AL_VOLVER_MS - 1, 0)).toBe(false);
  });

  it("el respaldo solo lee si en todo ese rato nadie leyó por otro motivo", () => {
    expect(tocaElRespaldo(RESPALDO_MS, 0)).toBe(true);
    expect(tocaElRespaldo(RESPALDO_MS, 60_000)).toBe(false);
  });
});

// Un cliente de mentira con lo único que el archivo usa: `channel` y `removeChannel`.
function clienteFalso() {
  const canales: {
    topic: string;
    opciones: unknown;
    alAviso?: () => void;
    alEstado?: (estado: string, error?: Error) => void;
  }[] = [];
  const quitados: string[] = [];
  const cliente = {
    channel(topic: string, opciones: unknown) {
      const c: (typeof canales)[number] = { topic, opciones };
      canales.push(c);
      const canal = {
        on(_tipo: string, _filtro: unknown, cb: () => void) {
          c.alAviso = cb;
          return canal;
        },
        subscribe(cb: (estado: string, error?: Error) => void) {
          c.alEstado = cb;
          return canal;
        },
        topic,
      };
      return canal;
    },
    removeChannel(canal: { topic: string }) {
      quitados.push(canal.topic);
      return Promise.resolve("ok");
    },
  } as unknown as ClienteTiempoReal;
  return { cliente, canales, quitados };
}

describe("escucharTema", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it("pide un canal PRIVADO llamado dynamic:<tema> (la política de la 0604 solo deja escuchar los privados)", () => {
    const { cliente, canales } = clienteFalso();
    escucharTema(cliente, "asistencia", { alAviso() {}, alConectar() {} });
    expect(canales).toHaveLength(1);
    expect(canales[0].topic).toBe("dynamic:asistencia");
    expect(canales[0].opciones).toEqual({ config: { private: true } });
  });

  it("dos pantallas que escuchan el mismo tema comparten UN canal, y el aviso les llega a las dos", () => {
    const { cliente, canales } = clienteFalso();
    const a = { alAviso: vi.fn(), alConectar: vi.fn() };
    const b = { alAviso: vi.fn(), alConectar: vi.fn() };
    escucharTema(cliente, "horarios", a);
    escucharTema(cliente, "horarios", b);
    expect(canales).toHaveLength(1);
    canales[0].alAviso!();
    expect(a.alAviso).toHaveBeenCalledTimes(1);
    expect(b.alAviso).toHaveBeenCalledTimes(1);
  });

  it("al quedar escuchando —la primera vez y tras cada corte— avisa que pudo perderse algo", () => {
    const { cliente, canales } = clienteFalso();
    const e = { alAviso: vi.fn(), alConectar: vi.fn() };
    escucharTema(cliente, "personas", e);
    canales[0].alEstado!("SUBSCRIBED");
    canales[0].alEstado!("CLOSED");
    canales[0].alEstado!("SUBSCRIBED");
    expect(e.alConectar).toHaveBeenCalledTimes(2);
    expect(e.alAviso).not.toHaveBeenCalled();
  });

  it("navegar no cierra el canal: sin nadie que lo escuche, se cierra recién pasado el diferido", () => {
    const { cliente, canales, quitados } = clienteFalso();
    const dejar = escucharTema(cliente, "asistencia", { alAviso() {}, alConectar() {} });
    dejar();
    vi.advanceTimersByTime(CIERRE_DIFERIDO_MS - 1);
    escucharTema(cliente, "asistencia", { alAviso() {}, alConectar() {} }); // la pantalla siguiente
    vi.advanceTimersByTime(CIERRE_DIFERIDO_MS * 2);
    expect(canales).toHaveLength(1);
    expect(quitados).toEqual([]);
  });

  it("sí se cierra cuando de verdad nadie lo escucha", () => {
    const { cliente, quitados } = clienteFalso();
    const dejar = escucharTema(cliente, "asistencia", { alAviso() {}, alConectar() {} });
    dejar();
    vi.advanceTimersByTime(CIERRE_DIFERIDO_MS);
    expect(quitados).toEqual(["dynamic:asistencia"]);
  });

  it("si la base dice que esta sesión no puede escuchar, no lo reintenta para siempre", () => {
    const { cliente, canales, quitados } = clienteFalso();
    escucharTema(cliente, "asistencia", { alAviso() {}, alConectar() {} });
    canales[0].alEstado!("CHANNEL_ERROR", new Error("Unauthorized: You do not have permissions to read from this Channel topic"));
    expect(quitados).toEqual(["dynamic:asistencia"]);
    escucharTema(cliente, "asistencia", { alAviso() {}, alConectar() {} });
    expect(canales).toHaveLength(1);
  });

  it("un corte cualquiera no cuenta como «no puede»: lo reintenta la librería", () => {
    const { cliente, canales, quitados } = clienteFalso();
    escucharTema(cliente, "asistencia", { alAviso() {}, alConectar() {} });
    canales[0].alEstado!("CHANNEL_ERROR", new Error("socket closed"));
    canales[0].alEstado!("TIMED_OUT");
    expect(quitados).toEqual([]);
  });
});

describe("el estado del canal, para no decir «en vivo» si no lo es", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it("empieza conectando, pasa a conectado, y un corte lo deja sin conexión hasta que vuelve", () => {
    const { cliente, canales } = clienteFalso();
    const estados: string[] = [];
    escucharTema(cliente, "asistencia", { alAviso() {}, alConectar() {}, alCambiarConexion: (e) => estados.push(e) });
    canales[0].alEstado!("SUBSCRIBED");
    canales[0].alEstado!("TIMED_OUT");
    canales[0].alEstado!("SUBSCRIBED");
    expect(estados).toEqual(["conectando", "conectado", "sin_conexion", "conectado"]);
  });

  it("quien llega a un canal ya abierto se entera en el acto de cómo está", () => {
    const { cliente, canales } = clienteFalso();
    escucharTema(cliente, "horarios", { alAviso() {}, alConectar() {} });
    canales[0].alEstado!("SUBSCRIBED");
    const estados: string[] = [];
    escucharTema(cliente, "horarios", { alAviso() {}, alConectar() {}, alCambiarConexion: (e) => estados.push(e) });
    expect(estados).toEqual(["conectado"]);
  });

  it("un tema que esta sesión no puede escuchar queda sin conexión, también para quien llega después", () => {
    const { cliente, canales } = clienteFalso();
    const a: string[] = [];
    escucharTema(cliente, "personas", { alAviso() {}, alConectar() {}, alCambiarConexion: (e) => a.push(e) });
    canales[0].alEstado!("CHANNEL_ERROR", new Error("Unauthorized: You do not have permissions to read from this Channel topic"));
    const b: string[] = [];
    escucharTema(cliente, "personas", { alAviso() {}, alConectar() {}, alCambiarConexion: (e) => b.push(e) });
    expect(a.at(-1)).toBe("sin_conexion");
    expect(b).toEqual(["sin_conexion"]);
  });

  it("varios temas juntos: basta uno cortado para no ser «al instante»", () => {
    expect(conexionDeTodos(["conectado", "conectado"])).toBe("conectado");
    expect(conexionDeTodos(["conectado", "conectando"])).toBe("conectando");
    expect(conexionDeTodos(["conectado", "sin_conexion"])).toBe("sin_conexion");
    expect(conexionDeTodos([])).toBe("conectando");
  });
});

// La lista de temas del navegador tiene que ser la misma que la base deja escuchar. Si no, una pantalla escucharía
// un tema que nadie puede oír —y se quedaría con el respaldo de 5 min sin que nadie lo note—, o la base avisaría a
// un tema que ninguna pantalla sabe pedir.
describe("los temas coinciden con la base", () => {
  it("TEMAS es exactamente lo que deja escuchar la última versión de fn_tiempo_real_puede_escuchar", () => {
    const dir = path.resolve(import.meta.dirname, "..", "supabase", "migrations");
    const archivo = readdirSync(dir)
      .filter((f) => /^\d{4}_.*\.sql$/.test(f))
      .sort()
      .filter((f) => /function\s+(public\.)?fn_tiempo_real_puede_escuchar\s*\(/i.test(readFileSync(path.join(dir, f), "utf8")))
      .at(-1);
    expect(archivo).toBeDefined();
    const sql = readFileSync(path.join(dir, archivo!), "utf8");
    const cuerpo = sql.slice(sql.search(/function\s+(public\.)?fn_tiempo_real_puede_escuchar\s*\(/i));
    const hasta = cuerpo.indexOf("$$;");
    const temas = [...cuerpo.slice(0, hasta).matchAll(/'dynamic:([a-z_]+)'/g)].map((m) => m[1]);
    expect([...new Set(temas)].sort()).toEqual([...TEMAS].sort());
  });
});

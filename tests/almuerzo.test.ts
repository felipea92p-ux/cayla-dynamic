import { describe, expect, it } from "vitest";
import {
  almuerzosPorDia, estadoDelDia, horasAntesDeAlmorzar, llaveDia, minutosDeAlmuerzo, sePaso,
} from "@/lib/admin/almuerzo";

// Lima es UTC-5: 13:02 en Lima = 18:02 UTC.
const marca = (persona_id: string, tipo: string, utc: string) => ({ persona_id, tipo, timestamp_marca: `${utc}Z` });

describe("almuerzosPorDia", () => {
  it("mide de la salida al retorno, en el día de Lima", () => {
    const m = almuerzosPorDia([
      marca("a", "salida_almuerzo", "2026-10-16T18:02:00"),
      marca("a", "retorno_almuerzo", "2026-10-16T19:01:00"),
    ]);
    expect(m.get(llaveDia("a", "2026-10-16"))?.minutos).toBe(59);
  });

  it("una marca de la noche de Lima (ya otro día en UTC) cae en el día de Lima", () => {
    // 19:30 en Lima = 00:30 UTC del día siguiente.
    const m = almuerzosPorDia([marca("a", "salida_almuerzo", "2026-10-17T00:30:00")]);
    expect([...m.keys()]).toEqual([llaveDia("a", "2026-10-16")]);
  });

  it("sin retorno todavía: hay salida y no hay minutos", () => {
    const m = almuerzosPorDia([marca("a", "salida_almuerzo", "2026-10-16T18:02:00")]);
    const a = m.get(llaveDia("a", "2026-10-16"))!;
    expect(a.volvioTs).toBeNull();
    expect(a.minutos).toBeNull();
  });

  it("un retorno sin salida no es un almuerzo", () => {
    expect(almuerzosPorDia([marca("a", "retorno_almuerzo", "2026-10-16T19:01:00")]).size).toBe(0);
  });

  it("cuenta el primer par: el retorno es el primero que viene DESPUÉS de la salida", () => {
    const m = almuerzosPorDia([
      marca("a", "retorno_almuerzo", "2026-10-16T16:00:00"), // suelto, antes de salir: no es el de este almuerzo
      marca("a", "salida_almuerzo", "2026-10-16T18:00:00"),
      marca("a", "retorno_almuerzo", "2026-10-16T19:00:00"),
      marca("a", "salida_almuerzo", "2026-10-16T21:00:00"),
      marca("a", "retorno_almuerzo", "2026-10-16T21:30:00"),
    ]);
    expect(m.get(llaveDia("a", "2026-10-16"))?.minutos).toBe(60);
  });

  it("separa a las personas y los días, e ignora otros tipos de marca", () => {
    const m = almuerzosPorDia([
      marca("a", "entrada", "2026-10-16T13:55:00"),
      marca("a", "salida_almuerzo", "2026-10-16T18:00:00"),
      marca("b", "salida_almuerzo", "2026-10-16T18:10:00"),
      marca("a", "salida_almuerzo", "2026-10-17T18:00:00"),
    ]);
    expect(m.size).toBe(3);
  });
});

describe("estado y minutos", () => {
  const sin = { salioTs: "2026-10-16T18:00:00Z", volvioTs: null, minutos: null };
  const con = { salioTs: "2026-10-16T18:00:00Z", volvioTs: "2026-10-16T19:05:00Z", minutos: 65 };

  it("terminó si hay salida final, aunque no haya vuelto del almuerzo", () => {
    expect(estadoDelDia({ salidaTs: "2026-10-16T23:00:00Z", almuerzo: sin })).toBe("termino");
  });
  it("almuerza si salió y no volvió; trabaja si no ha salido o ya volvió", () => {
    expect(estadoDelDia({ salidaTs: null, almuerzo: sin })).toBe("almorzando");
    expect(estadoDelDia({ salidaTs: null, almuerzo: con })).toBe("trabajando");
    expect(estadoDelDia({ salidaTs: null, almuerzo: null })).toBe("trabajando");
  });
  it("minutos de almuerzo: los reales si volvió, los que lleva si sigue, null si no almorzó", () => {
    expect(minutosDeAlmuerzo(con, "2026-10-16T21:00:00Z")).toBe(65);
    expect(minutosDeAlmuerzo(sin, "2026-10-16T18:45:00Z")).toBe(45);
    expect(minutosDeAlmuerzo(null, "2026-10-16T18:45:00Z")).toBeNull();
  });
  it("«se pasó» solo se dice con un tiempo permitido real", () => {
    expect(sePaso(65, 60)).toBe(true);
    expect(sePaso(60, 60)).toBe(false);
    expect(sePaso(90, 0)).toBe(false);     // refrigerio 0 en el horario: no hay vara
    expect(sePaso(90, null)).toBe(false);
    expect(sePaso(null, 60)).toBe(false);
  });
  it("horas antes de almorzar: de la entrada a la salida a almorzar", () => {
    expect(horasAntesDeAlmorzar("2026-10-16T13:56:00Z", con)).toBeCloseTo(4.067, 2);
    expect(horasAntesDeAlmorzar(null, con)).toBeNull();
    expect(horasAntesDeAlmorzar("2026-10-16T13:56:00Z", null)).toBeNull();
  });
});

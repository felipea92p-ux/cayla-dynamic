import { describe, expect, it } from "vitest";
import {
  avisoAlAgregar, dosSalidasFinales, salidaDelSistema, sePuedeConfirmar, type MarcaDelDia,
} from "@/lib/admin/salida-del-sistema";

// Las mismas situaciones que la prueba pgTAP 492: la pantalla tiene que decir
// lo mismo que la base hace desde la 0605.
const marca = (id: string, tipo: string, hora: string, extra: Partial<MarcaDelDia> = {}): MarcaDelDia => ({
  id, tipo, origen: "terminal", estado_revision: "normal", anulada_at: null,
  timestamp_marca: `2026-07-14T${hora}:00-05:00`, ...extra,
});
const entrada = marca("e", "entrada", "09:00");
const delSistema = marca("s", "salida_final", "18:00", { origen: "auto_cierre", estado_revision: "pendiente_revision" });
const confirmada = { ...delSistema, estado_revision: "revisada" };
const real = (hora: string) => marca("r", "salida_final", hora, { origen: "admin_correccion", estado_revision: "revisada" });

describe("avisoAlAgregar", () => {
  it("agregar la salida final de un día que cerró el sistema: la del sistema se retira sola", () => {
    expect(avisoAlAgregar("salida_final", [entrada, delSistema])).toEqual({ clase: "se_retira", sistema: delSistema });
  });

  it("si DO ya la confirmó, la base lo rechaza: la pantalla lo dice antes", () => {
    expect(avisoAlAgregar("salida_final", [entrada, confirmada])?.clase).toBe("confirmada");
  });

  it("otra marca que no es la salida final no toca la del sistema", () => {
    expect(avisoAlAgregar("salida_almuerzo", [entrada, delSistema])).toBeNull();
  });

  it("un día sin auto-cierre no tiene nada que avisar", () => {
    expect(avisoAlAgregar("salida_final", [entrada])).toBeNull();
  });

  it("una salida del sistema ya anulada no cuenta", () => {
    expect(avisoAlAgregar("salida_final", [entrada, { ...delSistema, anulada_at: "2026-07-15T10:00:00Z" }])).toBeNull();
  });
});

describe("dosSalidasFinales", () => {
  it("salió antes que la hora del sistema: hoy se paga la del sistema, la más tardía", () => {
    const r = dosSalidasFinales([entrada, delSistema, real("16:00")]);
    expect(r?.otra.id).toBe("r");
    expect(r?.pagada.id).toBe("s");
  });

  it("salió después: se paga la real", () => {
    expect(dosSalidasFinales([entrada, delSistema, real("20:00")])?.pagada.id).toBe("r");
  });

  it("con una sola salida no hay nada que elegir", () => {
    expect(dosSalidasFinales([entrada, delSistema])).toBeNull();
    expect(dosSalidasFinales([entrada, real("18:00")])).toBeNull();
  });
});

describe("sePuedeConfirmar", () => {
  it("se puede confirmar la del sistema si es la única salida final", () => {
    expect(sePuedeConfirmar(delSistema, [entrada, delSistema])).toBe(true);
  });

  it("no, si el día ya tiene otra salida final activa (la base también lo rechaza)", () => {
    expect(sePuedeConfirmar(delSistema, [entrada, delSistema, real("16:00")])).toBe(false);
  });

  it("una salida real ya anulada no lo impide", () => {
    expect(sePuedeConfirmar(delSistema, [entrada, delSistema, { ...real("16:00"), anulada_at: "x" }])).toBe(true);
  });
});

describe("salidaDelSistema", () => {
  it("devuelve la del auto-cierre, no la de una persona", () => {
    expect(salidaDelSistema([entrada, real("16:00"), delSistema])?.id).toBe("s");
  });
});

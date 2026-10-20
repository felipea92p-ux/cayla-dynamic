// ============================================================================
// historial-correcciones.test.ts — el historial no dice lo contrario de lo que pasó
// ============================================================================
// Una marca que el terminal apartó y DO declaró «improcedente» significa que NO
// se registra ningún marcaje y el día se paga como si la persona no hubiera
// venido. Hasta este arreglo el historial la mostraba como «quedó pendiente de
// revisión manual» —sin decir nada de la resolución— porque el comentario del
// código creía que esas filas ya no se escribían. `fn_marca_apartada_resolver`
// (0304/0376) las sigue escribiendo.
// ============================================================================
import { describe, expect, it } from "vitest";
import { esCampoDeMarcaje } from "@cayla-dynamic/shared";
import { describirCambio, horarioEnPalabras, type Auditoria } from "@/lib/admin/historial-correcciones";

const fila = (campo: string, anterior: string | null, nuevo: string | null): Auditoria => ({
  id: "x", campo_modificado: campo, valor_anterior: anterior, valor_nuevo: nuevo,
  corregido_at: "2026-09-15T13:33:00Z", motivo: "motivo de prueba", corregido_por: "p",
});

describe("marca apartada", () => {
  const anterior = "entrada del 15/09/2026 08:15 · Could not choose the best candidate function between: public.fn_registrar_marcaje(p_persona_id => uuid";

  it("improcedente se dice improcedente, con lo que significa, y no lo llama pendiente", () => {
    const { detalle } = describirCambio(fila("marca_apartada", anterior, "improcedente"));
    expect(detalle).toMatch(/improcedente/);
    expect(detalle).toMatch(/no se registró ningún marcaje/);
    expect(detalle).not.toMatch(/pendiente/);
  });

  it("repuesta dice que se registró con su hora original", () => {
    const { detalle } = describirCambio(fila("marca_apartada", anterior, "repuesta"));
    expect(detalle).toMatch(/se registró después, con su hora original/);
  });

  it("no enseña el error técnico del terminal", () => {
    const { detalle } = describirCambio(fila("marca_apartada", anterior, "improcedente"));
    expect(detalle).not.toMatch(/candidate|fn_registrar_marcaje|public\./);
    expect(detalle).toMatch(/Entrada del 15\/09\/2026 08:15/);
  });

  it("una fila vieja (sin resolución) sigue leyéndose sin mostrar el error crudo", () => {
    const { detalle } = describirCambio(fila("marca_apartada", "error: {json}", "otro error (x)"));
    expect(detalle).toMatch(/pendiente de revisión manual/);
  });
});

describe("campos de marcaje que antes salían crudos", () => {
  it("cambiar el tipo dice de qué a qué, con sus nombres", () => {
    const r = describirCambio(fila("tipo", "salida_almuerzo", "salida_final"));
    expect(r.accion).toBe("Tipo de marca corregido");
    expect(r.detalle).toBe("Salida a almuerzo → Salida final");
  });

  it("confirmar el auto-cierre no muestra «pendiente_revision → revisada»", () => {
    const r = describirCambio(fila("auto_cierre_confirmado", "pendiente_revision", "revisada"));
    expect(r.accion).toBe("Salida del auto-cierre confirmada");
    expect(r.detalle).not.toMatch(/pendiente_revision|revisada/);
  });

  it("un campo desconocido con un error de Postgres no muestra el error", () => {
    const r = describirCambio(fila("campo_raro", "select * from public.x;", "y"));
    expect(r.detalle).not.toMatch(/select|public\./);
    expect(r.accion).toBe("Campo raro");
  });
});

describe("hora corregida", () => {
  it("dice el día y las dos horas en hora de Lima", () => {
    // 12:47 UTC = 07:47 Lima → 07:45 Lima
    const r = describirCambio(fila("timestamp_marca", "2026-08-01 12:47:00+00", "2026-08-01 12:45:00+00"));
    expect(r.accion).toBe("Hora corregida");
    expect(r.detalle).toMatch(/07:47/);
    expect(r.detalle).toMatch(/07:45/);
  });
});

// El caso de la captura del 2026-10-06: en /mio el cambio de horario salía como
// el JSON crudo de `horario_por_dia`, media pantalla de llaves en el celular.
describe("horario cambiado", () => {
  const antes = 'vigente desde 2026-09-26: {"1": {"e": "08:30", "r": 60, "s": "14:00"}, "2": {"e": "08:30", "r": 60, "s": "14:00"}, "3": {"e": "08:30", "r": 60, "s": "14:00"}, "4": {"e": "08:30", "r": 60, "s": "14:00"}, "5": {"e": "08:30", "r": 60, "s": "14:00"}, "6": {"e": "08:30", "r": 60, "s": "14:30"}}';
  const despues = 'vigente desde 2026-09-26: {"1": {"e": "08:30", "r": 60, "s": "18:00"}, "2": {"e": "08:30", "r": 60, "s": "18:00"}, "6": {"e": "08:30", "r": 60, "s": "18:00"}}';

  it("se lee en días y horas, sin una sola llave", () => {
    const { accion, detalle } = describirCambio(fila("horarios_asignados", antes, despues));
    expect(accion).toBe("Horario cambiado");
    expect(detalle).not.toMatch(/[{}"]/);
    expect(detalle).toContain("lun a vie 08:30–14:00 · sáb 08:30–14:30");
    expect(detalle).toContain("lun y mar 08:30–18:00 · sáb 08:30–18:00");
    expect(detalle).toContain("60 min de refrigerio");
    // La vigencia es la misma en los dos lados: se dice una sola vez.
    expect(detalle).toMatch(/^Desde el 26 set\. pasa de lun a vie/);
    expect(detalle.match(/26 set/g)).toHaveLength(1);
  });

  it("un valor que nace no se lee como si algo se hubiera borrado", () => {
    const { accion, detalle } = describirCambio(fila("documento_firmado", null, "ruta · firmado digitalmente el 2026-10-06"));
    expect(accion).toBe("Documento firmado");
    expect(detalle).toBe("ruta · firmado digitalmente el 2026-10-06");
  });

  it("la fecha de vigencia no se corre al día anterior", () => {
    expect(horarioEnPalabras(antes)).toMatch(/^desde el 26 set/);
  });

  it("un cambio que solo toca el refrigerio no se lee igual antes y después", () => {
    const a = horarioEnPalabras('{"1": {"e": "09:00", "r": 45, "s": "18:00"}, "2": {"e": "09:00", "r": 60, "s": "18:00"}}');
    expect(a).toContain("45 min");
    expect(a).toContain("60 min");
  });

  it("entiende las otras formas que escriben la 0440 y la 0447", () => {
    expect(horarioEnPalabras("sin horario previo")).toBe("sin horario");
    expect(horarioEnPalabras("(sin horario previo en ese rango)")).toBe("sin horario");
    expect(horarioEnPalabras("vigente desde 2026-08-01: días {1,2,3} 08:00:00–17:00:00")).toContain("lun a mié 08:00–17:00");
    const tramos = horarioEnPalabras('[{"vigente_desde": "2026-09-01", "vigente_hasta": null, "horario_por_dia": {"0": {"e": "10:00", "s": "19:00"}}}]');
    expect(tramos).toContain("dom 10:00–19:00");
    expect(horarioEnPalabras("algo que nadie escribe {")).not.toMatch(/[{}]/);
  });
});

describe("tardanza levantada (0541)", () => {
  it("dice el día perdonado, el motivo y que la hora real no se tocó", () => {
    const r = describirCambio(fila("tardanza_levantada", "2026-10-19", "fuerza_mayor"));
    expect(r.accion).toBe("Tardanza levantada");
    expect(r.cuando).toMatch(/19/);
    expect(r.detalle).toMatch(/fuerza mayor/);
    expect(r.detalle).toMatch(/la hora real no se tocó/);
  });

  it("quitar el perdón dice que la tardanza vuelve a contar", () => {
    const r = describirCambio(fila("tardanza_levantamiento_quitado", "2026-10-19", "salud"));
    expect(r.accion).toBe("Perdón de la tardanza quitado");
    expect(r.detalle).toMatch(/vuelve a contar/);
  });

  it("es una corrección de marcaje: se ve en la vista «Marcajes» y no en «otros temas»", () => {
    expect(esCampoDeMarcaje("tardanza_levantada")).toBe(true);
    expect(esCampoDeMarcaje("tardanza_levantamiento_quitado")).toBe(true);
  });
});

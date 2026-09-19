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
import { describirCambio, type Auditoria } from "@/lib/admin/historial-correcciones";

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
    expect(r.accion).toBe("campo raro");
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

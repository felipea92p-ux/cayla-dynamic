// ============================================================================
// boletas-pantalla.test.ts — lo que la pantalla de DO decide para dibujar
// ============================================================================
// Cuida tres cosas que, si fallan, la pantalla MIENTE: qué botones lleva cada
// persona (uno de más ofrece algo que la base rechaza; uno de menos deja una
// boleta sin poder subirse), si la casilla «avisar» ofrece elegir donde la base
// lo va a ignorar, y que los filtros no escondan a alguien.
// ============================================================================
import { describe, it, expect } from "vitest";
import {
  accionesDeFila, borradoresDelTablero, casillaAvisar, fechaHoraLima, filtrarTablero,
  nombreDePeriodo, periodoInicial, resumenDelDocumento, sedesDelTablero, type FilaTablero,
} from "@/lib/admin/boletas-pantalla";
import { cambiosEntreVersiones } from "@/lib/boletas";
import type { PeriodoInfo } from "@/lib/admin/planilla/tipos";

function fila(o: Partial<FilaTablero> = {}): FilaTablero {
  return {
    persona_id: "p1", nombre: "Ana Quispe", cargo: "Vendedora", sede_codigo: "TRU", tipo_vinculo: "planilla",
    tiene_cuenta: true, grupo_pagado: true, boleta_id: null, estado: "falta",
    version_id: null, version_n: null, tipo: null, n_partes: 0, bytes: 0, actualizada: false,
    publicada_at: null, vista_at: null, recibida_at: null,
    firmada: false, anulada_at: null, anulada_motivo: null, restablecible_hasta: null, ...o,
  };
}

const conBoleta = (estado: string, o: Partial<FilaTablero> = {}) =>
  fila({ estado, boleta_id: "b1", version_id: "v1", version_n: 1, tipo: "imagen", n_partes: 2, bytes: 1_200_000, ...o });

describe("accionesDeFila", () => {
  it("sin boleta y con cuenta: subir; sin historial (no hay boleta)", () => {
    const a = accionesDeFila(fila());
    expect(a).toMatchObject({ subir: true, papel: false, ver: false, editar: false, historial: false, anular: false });
  });

  it("sin boleta y SIN cuenta: en cambio, anotar el papel", () => {
    const a = accionesDeFila(fila({ tiene_cuenta: false }));
    expect(a).toMatchObject({ subir: false, papel: true });
  });

  it("periodo sin pagar: ninguna acción", () => {
    const a = accionesDeFila(fila({ grupo_pagado: false }));
    expect(Object.values(a).every((x) => x === false)).toBe(true);
  });

  it("anulada: se puede volver a subir, y su historial se puede mirar", () => {
    const a = accionesDeFila(conBoleta("anulada"));
    expect(a).toMatchObject({ subir: true, historial: true, ver: false, editar: false, anular: false });
  });

  it("anulada dentro de las 48 horas: además se puede restablecer; vencido el plazo, ya no", () => {
    const ahora = new Date("2026-10-18T12:00:00Z");
    const dentro = conBoleta("anulada", { anulada_at: "2026-10-17T15:00:00Z", restablecible_hasta: "2026-10-19T15:00:00Z" });
    const vencida = conBoleta("anulada", { anulada_at: "2026-10-10T15:00:00Z", restablecible_hasta: "2026-10-12T15:00:00Z" });
    const vieja = conBoleta("anulada"); // anterior a la 0532: la base no sabe a qué volvería
    expect(accionesDeFila(dentro, ahora)).toMatchObject({ restablecer: true, anulacion: true, subir: true });
    expect(accionesDeFila(vencida, ahora)).toMatchObject({ restablecer: false, anulacion: true, subir: true });
    expect(accionesDeFila(vieja, ahora)).toMatchObject({ restablecer: false, anulacion: true });
  });

  it("la constancia es solo de quien ya firmó (o confirmó antes de la firma)", () => {
    expect(accionesDeFila(conBoleta("publicada", { vista_at: "x", recibida_at: "y", firmada: true }))).toMatchObject({ constancia: true, anular: true });
    expect(accionesDeFila(conBoleta("publicada", { vista_at: "x", recibida_at: "y" }))).toMatchObject({ constancia: true });
    expect(accionesDeFila(conBoleta("publicada", { vista_at: "x" }))).toMatchObject({ constancia: false });
    expect(accionesDeFila(conBoleta("publicada"))).toMatchObject({ constancia: false });
    expect(accionesDeFila(conBoleta("borrador"))).toMatchObject({ constancia: false });
  });

  it("borrador: ver, editar e historial, pero NO anular (la persona no la ve)", () => {
    expect(accionesDeFila(conBoleta("borrador"))).toMatchObject({ ver: true, editar: true, historial: true, anular: false });
  });

  it("publicada o vista: todas, con anular", () => {
    for (const extra of [{}, { vista_at: "2026-09-02T15:00:00Z" }]) {
      expect(accionesDeFila(conBoleta("publicada", extra))).toMatchObject({ ver: true, editar: true, historial: true, anular: true });
    }
  });

  it("firmada o confirmada: se mira con su firma, no con «Ver» a secas", () => {
    const recibida = { vista_at: "2026-09-02T15:00:00Z", recibida_at: "2026-09-02T16:00:00Z" };
    for (const extra of [recibida, { ...recibida, firmada: true }]) {
      expect(accionesDeFila(conBoleta("publicada", extra))).toMatchObject({
        constancia: true, ver: false, editar: true, historial: true, anular: true,
      });
    }
  });

  it("papel: el historial y anularla, para corregir una entrega anotada por error", () => {
    const a = accionesDeFila(fila({ estado: "papel", boleta_id: "b1", tiene_cuenta: false }));
    expect(a).toMatchObject({ historial: true, anular: true, subir: false, papel: false, ver: false, editar: false });
  });
});

describe("filtrarTablero y sedes", () => {
  const filas = [
    fila({ persona_id: "1", nombre: "Ana Quispe", sede_codigo: "TRU" }),
    conBoleta("borrador", { persona_id: "2", nombre: "Rosa Huamán", sede_codigo: "AQP" }),
    fila({ persona_id: "3", nombre: "Luis Mendoza", sede_codigo: "LIM", grupo_pagado: false }),
  ];

  it("busca sin importar tildes ni mayúsculas", () => {
    expect(filtrarTablero(filas, { estado: "todos", sede: "todas", texto: "huaman" }).map((f) => f.persona_id)).toEqual(["2"]);
    expect(filtrarTablero(filas, { estado: "todos", sede: "todas", texto: "  QUISPE " }).map((f) => f.persona_id)).toEqual(["1"]);
  });

  it("filtra por el estado que se DIBUJA, no por el de la base", () => {
    expect(filtrarTablero(filas, { estado: "falta", sede: "todas", texto: "" }).map((f) => f.persona_id)).toEqual(["1"]);
    expect(filtrarTablero(filas, { estado: "sin_pago", sede: "todas", texto: "" }).map((f) => f.persona_id)).toEqual(["3"]);
    expect(filtrarTablero(filas, { estado: "borrador", sede: "todas", texto: "" }).map((f) => f.persona_id)).toEqual(["2"]);
  });

  it("filtra por sede y las sedes salen de los datos", () => {
    expect(filtrarTablero(filas, { estado: "todos", sede: "LIM", texto: "" })).toHaveLength(1);
    expect(sedesDelTablero(filas)).toEqual(["AQP", "LIM", "TRU"]);
  });

  it("los borradores listados para publicar son solo los que tienen versión", () => {
    expect(borradoresDelTablero(filas).map((f) => f.persona_id)).toEqual(["2"]);
    expect(borradoresDelTablero([fila({ estado: "borrador", boleta_id: "b", version_id: null })])).toEqual([]);
  });
});

describe("casillaAvisar", () => {
  it("un borrador no ofrece la casilla: no hay a quién avisar", () => {
    expect(casillaAvisar({ publicada: false, cambios: cambiosEntreVersiones(["a"], ["a", "b"]), quiereAvisar: true }).visible).toBe(false);
  });

  it("si cambió el contenido queda marcada y bloqueada, y lo explica", () => {
    const c = casillaAvisar({ publicada: true, cambios: cambiosEntreVersiones(["a"], ["a", "nueva:h1"]), quiereAvisar: false });
    expect(c).toMatchObject({ visible: true, marcada: true, bloqueada: true });
    expect(c.explicacion).toMatch(/siempre/);
  });

  it("solo si únicamente se reordenó se puede elegir, y respeta lo elegido", () => {
    const cambios = cambiosEntreVersiones(["a", "b"], ["b", "a"]);
    expect(casillaAvisar({ publicada: true, cambios, quiereAvisar: true })).toMatchObject({ marcada: true, bloqueada: false });
    expect(casillaAvisar({ publicada: true, cambios, quiereAvisar: false })).toMatchObject({ marcada: false, bloqueada: false });
  });

  it("sin cambios está bloqueada: no hay nada que elegir", () => {
    const c = casillaAvisar({ publicada: true, cambios: cambiosEntreVersiones(["a"], ["a"]), quiereAvisar: true });
    expect(c).toMatchObject({ visible: true, bloqueada: true });
  });
});

describe("periodos y fechas", () => {
  const p = (id: string, estado: "abierto" | "pagado"): PeriodoInfo =>
    ({ id, fecha_ini: "2026-08-29", fecha_fin: "2026-09-28", estado, pagado_at: null, anio_etiqueta: 2026, mes_etiqueta: 9 });
  const lista = [p("nuevo", "abierto"), p("medio", "pagado"), p("viejo", "pagado")];

  it("abre el que pide la dirección si existe", () => {
    expect(periodoInicial(lista, "viejo")).toBe("viejo");
  });

  it("si no, el más reciente ya pagado, que es donde hay boletas que subir", () => {
    expect(periodoInicial(lista, null)).toBe("medio");
    expect(periodoInicial(lista, "no-existe")).toBe("medio");
  });

  it("si ninguno está pagado, el más reciente; sin periodos, ninguno", () => {
    expect(periodoInicial([p("a", "abierto"), p("b", "abierto")], null)).toBe("a");
    expect(periodoInicial([], null)).toBeNull();
  });

  it("el nombre del periodo sale de la etiqueta de mes y año", () => {
    expect(nombreDePeriodo(p("x", "pagado"))).toBe("Septiembre 2026");
  });

  it("la fecha se escribe en hora de Lima, no en la del navegador", () => {
    // 19:35 UTC es 14:35 en Lima (UTC-5, sin horario de verano).
    expect(fechaHoraLima("2026-09-13T19:35:00Z")).toMatch(/13.*14:35/);
    // A las 02:00 UTC de un día ya es la noche del anterior en Lima.
    expect(fechaHoraLima("2026-09-14T02:00:00Z")).toMatch(/13.*21:00/);
    expect(fechaHoraLima(null)).toBe("—");
  });

  it("resume el documento con su cantidad y su peso; sin documento, nada", () => {
    expect(resumenDelDocumento({ tipo: "imagen", n_partes: 3, bytes: 1_572_864 })).toBe("3 fotos · 1.5 MB");
    expect(resumenDelDocumento({ tipo: "pdf", n_partes: 1, bytes: 245_760 })).toBe("1 PDF · 240 KB");
    expect(resumenDelDocumento({ tipo: null, n_partes: 0, bytes: 0 })).toBeNull();
  });
});

// ============================================================================
// liquidacion-constancias.test.ts — qué se registra sobre una diferencia real
// ============================================================================
// Dos cosas que no pueden separarse sin que alguien lo note:
//   1. Los catálogos de aquí y los CHECK de la migración 0542 (decisiones,
//      apoyos, sentidos, motivo mínimo). Si uno cambia y el otro no, una
//      decisión que la pantalla ofrece se rechaza en la base —o al revés—.
//   2. Qué dibuja la pantalla. Con TRES estados: «no sé» (la lectura falló, o la
//      0542 todavía no está pegada) NO es «sin constancia», y no puede dibujar
//      un botón ni un aviso.
// ============================================================================
import { describe, it, expect } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import {
  APOYOS_CONSTANCIA, DECISIONES_CONSTANCIA, ETIQUETA_APOYO, ETIQUETA_DECISION,
  MOTIVO_MINIMO_CONSTANCIA, SENTIDOS_DIFERENCIA,
  decisionesPara, motivoDeConstanciaValido, queDibujarDeLaConstancia,
  type EstadoRegistroDiferencia,
} from "@cayla-dynamic/shared";

/** La última migración que define la tabla: si otra cambia el CHECK, esa manda. */
function sqlDeLaTabla(): string {
  const carpeta = path.resolve(import.meta.dirname, "../supabase/migrations");
  const definen = readdirSync(carpeta)
    .filter((f) => f.endsWith(".sql"))
    .sort()
    .filter((f) => readFileSync(path.join(carpeta, f), "utf8").includes("create table if not exists liquidacion_constancias"));
  expect(definen.length).toBeGreaterThan(0);
  return readFileSync(path.join(carpeta, definen[definen.length - 1]), "utf8");
}

/** Los valores de `<columna> ... check (<columna> in ('a', 'b'))` — sin comentarios SQL. */
function valoresDelCheck(sql: string, columna: string): string[] {
  const sinComentarios = sql.replace(/--.*$/gm, "");
  const m = sinComentarios.match(new RegExp(`${columna}\\s+text[^,]*?check\\s*\\(\\s*${columna}\\s+in\\s*\\(([^)]*)\\)`, "s"));
  expect(m, `no encontré el CHECK de ${columna} en la migración`).not.toBeNull();
  return [...m![1].matchAll(/'([^']+)'/g)].map((x) => x[1]);
}

describe("los catálogos de la pantalla y los CHECK de la 0542 son los mismos", () => {
  const sql = sqlDeLaTabla();

  it("decisiones", () => {
    expect([...valoresDelCheck(sql, "decision")].sort()).toEqual([...DECISIONES_CONSTANCIA].sort());
  }, 30_000);

  it("apoyos", () => {
    expect([...valoresDelCheck(sql, "apoyo")].sort()).toEqual([...APOYOS_CONSTANCIA].sort());
  }, 30_000);

  it("sentidos", () => {
    expect([...valoresDelCheck(sql, "sentido")].sort()).toEqual([...SENTIDOS_DIFERENCIA].sort());
  }, 30_000);

  it("el motivo mínimo es el de la base", () => {
    // btrim con espacio, tabulador, retorno y salto de línea: diez saltos de línea no son un motivo.
    expect(sql).toContain(`char_length(btrim(motivo, E' \\t\\r\\n')) >= ${MOTIVO_MINIMO_CONSTANCIA}`);
  }, 30_000);

  it("toda decisión y todo apoyo tienen etiqueta en español, y ninguna queda vacía", () => {
    for (const d of DECISIONES_CONSTANCIA) expect(ETIQUETA_DECISION[d].trim().length).toBeGreaterThan(5);
    for (const a of APOYOS_CONSTANCIA) expect(ETIQUETA_APOYO[a].trim().length).toBeGreaterThan(5);
  });

  it("el vocabulario de la casa: ninguna etiqueta dice empleado, jefe, sucursal ni RRHH", () => {
    const todas = [...Object.values(ETIQUETA_DECISION), ...Object.values(ETIQUETA_APOYO)].join(" ");
    expect(todas).not.toMatch(/\b(empleado|empleada|jefe|jefa|sucursal|rrhh)\b/i);
  });
});

describe("qué decisiones se ofrecen según el sentido", () => {
  it("a favor de la persona: solo «lo pagado era lo correcto» — nunca «no se reclama»", () => {
    expect(decisionesPara("a_favor_persona")).toEqual(["pagado_es_correcto"]);
  });

  it("a favor de CAYLA: no se reclama o devolución acordada — nunca «lo pagado era lo correcto»", () => {
    expect(decisionesPara("a_favor_cayla")).toEqual(["no_se_reclama", "devolucion_acordada"]);
  });

  it("«retirada» no se ofrece como una decisión de registrar: se llega por «Retirar»", () => {
    for (const s of SENTIDOS_DIFERENCIA) expect(decisionesPara(s)).not.toContain("retirada");
  });
});

describe("el motivo: lo que acepta la pantalla, la base lo acepta", () => {
  it("rechaza vacío, espacios y menos de 10 caracteres", () => {
    for (const malo of ["", "          ", "corto", "123456789", "  123456789  ", "\n\n\n\n\n\n\n\n\n\n"]) {
      expect(motivoDeConstanciaValido(malo)).toBe(false);
    }
  });

  it("acepta 10 caracteres reales", () => {
    expect(motivoDeConstanciaValido("1234567890")).toBe(true);
    expect(motivoDeConstanciaValido("  la regla cambió después del pago  ")).toBe(true);
  });
});

describe("qué dibuja la pantalla: tres estados, no dos", () => {
  const fila = (parcial: Partial<EstadoRegistroDiferencia> = {}): EstadoRegistroDiferencia => ({
    version: 1, hay_real: true, sentido: "a_favor_persona",
    filas: [{ concepto: "Vacaciones truncas", pagado: 250, ahora: 310.5, diferencia: 60.5, centavos: 6050 }],
    huella: "a".repeat(32), puede_constatar: true, motivo_no: null, cabeza_id: null,
    vigente: null, anterior: null, ...parcial,
  });
  const vigente = {
    id: "x", decision: "pagado_es_correcto" as const, apoyo: "regla_cambio_despues" as const,
    motivo: "la regla cambió después del pago", por: "Ana Prueba", cuando: "2026-10-21T10:00:00Z", diferencias: [],
  };

  it("una liquidación que no está pagada no dibuja nada", () => {
    expect(queDibujarDeLaConstancia({ error: null, fila: fila() }, false)).toBe("nada");
  });

  it("«no sé» NO es «sin constancia»: si la lectura falló no se dibuja ni botón ni aviso", () => {
    expect(queDibujarDeLaConstancia({ error: "Could not find the function", fila: null }, true)).toBe("nada");
    expect(queDibujarDeLaConstancia({ error: "timeout", fila: fila() }, true)).toBe("nada");
  });

  it("sin fila (la persona no tiene liquidación vigente) no dibuja nada", () => {
    expect(queDibujarDeLaConstancia({ error: null, fila: null }, true)).toBe("nada");
  });

  it("sin diferencia real no dibuja nada", () => {
    expect(queDibujarDeLaConstancia({ error: null, fila: fila({ hay_real: false, filas: [], puede_constatar: false }) }, true)).toBe("nada");
  });

  it("una respuesta con otra forma (columna ausente, filas que no son arreglo) no dibuja nada", () => {
    const sinColumna = { ...fila() } as Partial<EstadoRegistroDiferencia>;
    delete sinColumna.puede_constatar;
    expect(queDibujarDeLaConstancia({ error: null, fila: sinColumna as EstadoRegistroDiferencia }, true)).toBe("nada");
    expect(queDibujarDeLaConstancia({ error: null, fila: fila({ filas: null as unknown as [] }) }, true)).toBe("nada");
  });

  it("con diferencia real sin cerrar y que se puede registrar: ofrece registrar", () => {
    expect(queDibujarDeLaConstancia({ error: null, fila: fila() }, true)).toBe("registrar");
  });

  it("con una constancia vigente: la muestra, aunque ya no se pueda constatar otra", () => {
    expect(queDibujarDeLaConstancia({ error: null, fila: fila({ vigente }) }, true)).toBe("vigente");
    expect(queDibujarDeLaConstancia({ error: null, fila: fila({ vigente, puede_constatar: false }) }, true)).toBe("vigente");
  });

  it("con diferencia real que hoy no se puede registrar (mixta, cese cambiado): lo dice, no ofrece el botón", () => {
    expect(queDibujarDeLaConstancia({
      error: null,
      fila: fila({ puede_constatar: false, sentido: "mixto", motivo_no: "Las diferencias van en sentidos opuestos" }),
    }, true)).toBe("no_se_puede");
  });
});

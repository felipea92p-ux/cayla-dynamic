// ============================================================================
// seguros-archivos.test.ts — poner un PDF en una póliza, o en varias (0528)
// ============================================================================
// Lo que importa cuidar:
//   · el archivo va PRIMERO y la fila después: si el registro falla, el huérfano se
//     intenta borrar; y si la subida falla, no se registra nada;
//   · la copia a otra póliza de la misma colectiva es un OBJETO NUEVO (cada fila tiene el
//     suyo: un índice único lo exige) con la misma extensión, y si no se puede registrar,
//     también se limpia;
//   · nada de esto lanza: devuelve el texto del fallo para que la pantalla lo diga.
// ============================================================================
import { describe, it, expect, vi, beforeEach } from "vitest";
import type { ClienteCayla } from "@cayla-dynamic/database";

const subir = vi.fn();
vi.mock("@/lib/subir-archivo", () => ({ subirArchivoConProgreso: (...a: unknown[]) => subir(...a) }));

import { adjuntarArchivoAPoliza, copiarArchivoAPoliza } from "@/lib/admin/seguros-archivos";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

interface Falso {
  cliente: ClienteCayla;
  copy: ReturnType<typeof vi.fn>;
  remove: ReturnType<typeof vi.fn>;
  rpc: ReturnType<typeof vi.fn>;
}

/** Un cliente de Supabase con solo lo que estas funciones tocan. */
function cliente(o: { copyError?: string; rpcError?: { message: string; code?: string } } = {}): Falso {
  const copy = vi.fn().mockResolvedValue({ error: o.copyError ? { message: o.copyError } : null });
  const remove = vi.fn().mockResolvedValue({ error: null });
  const rpc = vi.fn().mockResolvedValue({ error: o.rpcError ?? null });
  const c = { storage: { from: vi.fn(() => ({ copy, remove })) }, rpc } as unknown as ClienteCayla;
  return { cliente: c, copy, remove, rpc };
}

const pdf = (nombre = "Cayla, Ana, FOLA 24043267.pdf", contenido = "%PDF-1.4 x") => new File([contenido], nombre, { type: "application/pdf" });

beforeEach(() => { subir.mockReset(); subir.mockResolvedValue(null); });

describe("subir un archivo a una póliza", () => {
  it("lo sube a una ruta <uuid>.pdf —sin el nombre de nadie— y lo registra con su nombre original", async () => {
    const f = cliente();
    const r = await adjuntarArchivoAPoliza(f.cliente, "z1", "poliza", pdf());
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.ruta).toMatch(new RegExp(`${UUID.source.slice(1, -1)}\\.pdf$`));
    expect(r.ruta).not.toMatch(/Ana|FOLA|Cayla/);
    expect(subir).toHaveBeenCalledWith(f.cliente, "polizas-seguro", r.ruta, expect.any(File), expect.any(Function));
    expect(f.rpc).toHaveBeenCalledWith("fn_seguro_adjuntar", {
      p_poliza_id: "z1", p_tipo: "poliza", p_storage_path: r.ruta, p_nombre_archivo: "Cayla, Ana, FOLA 24043267.pdf",
    });
    expect(f.remove).not.toHaveBeenCalled();
  });

  it("un archivo vacío ni se sube ni se registra", async () => {
    const f = cliente();
    const r = await adjuntarArchivoAPoliza(f.cliente, "z1", "poliza", pdf("vacio.pdf", ""));
    expect(r).toEqual({ ok: false, error: "«vacio.pdf» está vacío." });
    expect(subir).not.toHaveBeenCalled();
    expect(f.rpc).not.toHaveBeenCalled();
  });

  it("si el archivo no subió, no queda ninguna fila y se dice por qué", async () => {
    subir.mockResolvedValue("sin conexión");
    const f = cliente();
    const r = await adjuntarArchivoAPoliza(f.cliente, "z1", "poliza", pdf());
    expect(r).toEqual({ ok: false, error: "El archivo no subió (sin conexión). Vuelve a intentarlo." });
    expect(f.rpc).not.toHaveBeenCalled();
  });

  it("si subió y no se pudo registrar, el huérfano se borra y el mensaje de la base se muestra tal cual", async () => {
    const f = cliente({ rpcError: { message: "Esa póliza ya no existe.", code: "P0001" } });
    const r = await adjuntarArchivoAPoliza(f.cliente, "z1", "poliza", pdf());
    expect(r).toEqual({ ok: false, error: "Esa póliza ya no existe." });
    expect(f.remove).toHaveBeenCalledTimes(1);
    const [rutas] = f.remove.mock.calls[0];
    expect(rutas).toHaveLength(1);
    expect(rutas[0]).toMatch(/\.pdf$/);
  });

  it("informa el avance mientras sube", async () => {
    subir.mockImplementation(async (_c, _b, _r, _f, alAvanzar: (n: number) => void) => { alAvanzar(40); alAvanzar(100); return null; });
    const avances: number[] = [];
    await adjuntarArchivoAPoliza(cliente().cliente, "z1", "poliza", pdf(), (n) => avances.push(n));
    expect(avances).toEqual([0, 40, 100]);
  });
});

describe("copiar el archivo a otra póliza de la misma colectiva", () => {
  it("copia dentro del almacén a un objeto NUEVO con la misma extensión, y lo registra con el nombre original", async () => {
    const f = cliente();
    const fallo = await copiarArchivoAPoliza(f.cliente, "11111111-2222-3333-4444-555555555555.pdf", "z2", "convenio_pago", "Convenio.pdf");
    expect(fallo).toBeNull();
    const [origen, destino] = f.copy.mock.calls[0];
    expect(origen).toBe("11111111-2222-3333-4444-555555555555.pdf");
    expect(destino).toMatch(/^[0-9a-f-]{36}\.pdf$/);
    expect(destino).not.toBe(origen);
    expect(f.rpc).toHaveBeenCalledWith("fn_seguro_adjuntar", {
      p_poliza_id: "z2", p_tipo: "convenio_pago", p_storage_path: destino, p_nombre_archivo: "Convenio.pdf",
    });
  });

  it("una foto se copia con su extensión: la política de Storage exige <uuid>.<ext>", async () => {
    const f = cliente();
    await copiarArchivoAPoliza(f.cliente, "11111111-2222-3333-4444-555555555555.jpg", "z2", "poliza", "foto.jpg");
    expect(f.copy.mock.calls[0][1]).toMatch(/^[0-9a-f-]{36}\.jpg$/);
  });

  it("cada copia es un objeto distinto: dos pólizas nunca comparten ruta", async () => {
    const f = cliente();
    await copiarArchivoAPoliza(f.cliente, "11111111-2222-3333-4444-555555555555.pdf", "z2", "poliza", "a.pdf");
    await copiarArchivoAPoliza(f.cliente, "11111111-2222-3333-4444-555555555555.pdf", "z3", "poliza", "a.pdf");
    expect(f.copy.mock.calls[0][1]).not.toBe(f.copy.mock.calls[1][1]);
  });

  it("si no se pudo copiar, no registra nada y dice por qué", async () => {
    const f = cliente({ copyError: "Object not found" });
    const fallo = await copiarArchivoAPoliza(f.cliente, "11111111-2222-3333-4444-555555555555.pdf", "z2", "poliza", "a.pdf");
    expect(fallo).toBe("No se pudo copiar el archivo (Object not found).");
    expect(f.rpc).not.toHaveBeenCalled();
  });

  it("si copió y no se pudo registrar, borra la copia y deja el mensaje de la base", async () => {
    const f = cliente({ rpcError: { message: "Esa póliza ya no existe.", code: "P0001" } });
    const fallo = await copiarArchivoAPoliza(f.cliente, "11111111-2222-3333-4444-555555555555.pdf", "z2", "poliza", "a.pdf");
    expect(fallo).toBe("Esa póliza ya no existe.");
    expect(f.remove).toHaveBeenCalledWith([f.copy.mock.calls[0][1]]);
  });
});

// ============================================================================
// abrir-archivo-firmado.test.ts — abrir un papel de un bucket privado (lo usan seis pantallas)
// ============================================================================
// Lo que se cuida:
//   · que la pestaña se abra ANTES de esperar la firma (si no, el navegador la toma por una ventana
//     emergente) y que se cierre si la firma falla, para no dejar una pestaña en blanco;
//   · que lo que llega a la pantalla esté en español y diga qué hacer: el mensaje de Storage
//     («fetch failed», «Object not found») es técnico, en inglés y no le sirve a quien lo lee;
//   · que un navegador que bloquea la pestaña lo diga, en vez de no hacer nada.
// ============================================================================
import { afterEach, describe, expect, it, vi } from "vitest";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { abrirArchivoFirmado } from "@/lib/abrir-archivo-firmado";

const clienteQueFirma = (resultado: { data: { signedUrl: string } | null; error: { message: string } | null }) =>
  ({ storage: { from: () => ({ createSignedUrl: async () => resultado }) } }) as unknown as ClienteCayla;

function ventana(pestana: unknown) {
  const abrir = vi.fn(() => pestana);
  vi.stubGlobal("window", { open: abrir });
  return abrir;
}

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe("abrir un archivo firmado", () => {
  it("si la firma falla, devuelve un texto en español, sin el detalle técnico, y cierra la pestaña vacía", async () => {
    const close = vi.fn();
    const abrir = ventana({ close, opener: "algo", location: { href: "" } });
    vi.spyOn(console, "error").mockImplementation(() => {});

    for (const detalle of ["fetch failed", "Object not found"]) {
      const mensaje = await abrirArchivoFirmado(clienteQueFirma({ data: null, error: { message: detalle } }), "polizas-seguro", "a.pdf");
      expect(mensaje).toMatch(/^No se pudo abrir el archivo\./);
      expect(mensaje).toMatch(/Revisa tu conexión/);
      expect(mensaje).not.toContain(detalle);
    }
    // La pestaña se abrió primero (dentro del clic) y se cerró al fallar.
    expect(abrir).toHaveBeenCalledWith("about:blank", "_blank");
    expect(close).toHaveBeenCalledTimes(2);
  });

  it("si no hay error pero tampoco dirección, falla igual de claro", async () => {
    ventana({ close: vi.fn(), opener: null, location: { href: "" } });
    const mensaje = await abrirArchivoFirmado(clienteQueFirma({ data: null, error: null }), "b", "a.pdf");
    expect(mensaje).toMatch(/^No se pudo abrir el archivo\./);
    expect(mensaje).not.toMatch(/sin URL/);
  });

  it("con la firma, manda la pestaña a la dirección, la suelta de la página y devuelve null", async () => {
    const pestana = { close: vi.fn(), opener: "pagina", location: { href: "" } };
    ventana(pestana);
    const r = await abrirArchivoFirmado(clienteQueFirma({ data: { signedUrl: "https://x.test/f.pdf?token=1" }, error: null }), "b", "a.pdf");
    expect(r).toBeNull();
    expect(pestana.location.href).toBe("https://x.test/f.pdf?token=1");
    expect(pestana.opener).toBeNull();
    expect(pestana.close).not.toHaveBeenCalled();
  });

  it("si el navegador bloquea la pestaña, lo dice con todas sus letras", async () => {
    ventana(null);
    const r = await abrirArchivoFirmado(clienteQueFirma({ data: { signedUrl: "https://x.test/f.pdf" }, error: null }), "b", "a.pdf");
    expect(r).toMatch(/bloqueó la ventana/);
    expect(r).toMatch(/ventanas emergentes/);
  });
});

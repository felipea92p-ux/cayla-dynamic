import { describe, expect, it, vi } from "vitest";
import {
  cerrarSesionAProposito,
  cerrarSesionSinAcceso,
  estaCerrandoAProposito,
  reaccionASesion,
  mensajeSinAcceso,
  motivoSinAcceso,
  type MotivoSinAcceso,
} from "@/lib/cuenta-de-servicio";

// Quién NO debe quedarse en el panel, y cómo se le cierra la puerta.
//
// Nace del 2026-11-08: en la Mac mini de TRU el panel estaba abierto con una
// cuenta sin ficha en `personas` (la del terminal, por todo lo que se veía). El
// menú salía con «Info» y «Publicaciones», Correcciones decía «0 colaboradores»
// y «Nada pendiente» mientras el terminal avisaba de 4 marcas sin registrar.
// Ninguna consulta fallaba: la RLS le devuelve cero filas a quien no es nadie.

type Respuesta = { data: unknown; error: unknown };

/** Un cliente de mentira que contesta lo que se le diga por tabla y anota cómo se cerró la sesión. */
function cliente(respuestas: Record<string, Respuesta>) {
  const consultadas: string[] = [];
  const signOut = vi.fn(async (_o?: { scope?: string }) => ({ error: null }));
  const c = {
    consultadas,
    signOut,
    auth: { signOut },
    from(tabla: string) {
      consultadas.push(tabla);
      const r = respuestas[tabla] ?? { data: null, error: { message: `sin respuesta para ${tabla}` } };
      const cadena = { select: () => cadena, eq: () => cadena, maybeSingle: async () => r };
      return cadena;
    },
  };
  return c;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any -- el cliente real es un tipo enorme; aquí solo importan tres métodos.
const comoCliente = (c: ReturnType<typeof cliente>) => c as any;

describe("motivoSinAcceso", () => {
  it("una persona activa de verdad pasa, y no se pregunta por terminales", async () => {
    const c = cliente({ personas: { data: { cuenta_de_servicio: false, estado: "activo" }, error: null } });
    expect(await motivoSinAcceso(comoCliente(c), "u1")).toBeNull();
    expect(c.consultadas).toEqual(["personas"]);
  });

  it("la cuenta del terminal: sin ficha en personas, con fila en terminales", async () => {
    const c = cliente({
      personas: { data: null, error: null },
      terminales: { data: { id: "t1" }, error: null },
    });
    expect(await motivoSinAcceso(comoCliente(c), "u1")).toBe("terminal");
  });

  it("un usuario sin ficha y que tampoco es terminal", async () => {
    const c = cliente({
      personas: { data: null, error: null },
      terminales: { data: null, error: null },
    });
    expect(await motivoSinAcceso(comoCliente(c), "u1")).toBe("sin_ficha");
  });

  it("si la lectura de personas FALLA, no se deja fuera a nadie", async () => {
    const c = cliente({ personas: { data: null, error: { message: "Load failed" } } });
    expect(await motivoSinAcceso(comoCliente(c), "u1")).toBeNull();
    expect(c.consultadas).toEqual(["personas"]);
  });

  it("si la lectura de terminales FALLA, tampoco", async () => {
    const c = cliente({
      personas: { data: null, error: null },
      terminales: { data: null, error: { message: "Load failed" } },
    });
    expect(await motivoSinAcceso(comoCliente(c), "u1")).toBeNull();
  });

  it("estación de Retail y baja siguen como antes", async () => {
    const servicio = cliente({ personas: { data: { cuenta_de_servicio: true, estado: "activo" }, error: null } });
    expect(await motivoSinAcceso(comoCliente(servicio), "u1")).toBe("servicio");
    const baja = cliente({ personas: { data: { cuenta_de_servicio: false, estado: "inactivo" }, error: null } });
    expect(await motivoSinAcceso(comoCliente(baja), "u1")).toBe("baja");
  });

  it("sin usuario no pregunta nada", async () => {
    const c = cliente({});
    expect(await motivoSinAcceso(comoCliente(c), undefined)).toBeNull();
    expect(c.consultadas).toEqual([]);
  });
});

describe("cerrarSesionSinAcceso", () => {
  // `signOut()` a secas es global: con la cuenta del terminal desvincularía la
  // Mac mini de la sede, y con una estación de Retail sacaría a la caja.
  it.each<[MotivoSinAcceso, string]>([
    ["terminal", "local"],
    ["sin_ficha", "local"],
    ["servicio", "local"],
    ["baja", "global"],
  ])("%s cierra en alcance %s", async (motivo, alcance) => {
    const c = cliente({});
    await cerrarSesionSinAcceso(comoCliente(c), motivo);
    expect(c.signOut).toHaveBeenCalledWith({ scope: alcance });
  });
});

describe("mensajeSinAcceso", () => {
  it("cada motivo tiene su frase, y la del terminal dice que el terminal sigue funcionando", () => {
    const motivos: MotivoSinAcceso[] = ["servicio", "baja", "terminal", "sin_ficha"];
    const frases = motivos.map(mensajeSinAcceso);
    expect(new Set(frases).size).toBe(4);
    expect(mensajeSinAcceso("terminal")).toMatch(/no se desvinculó/);
    expect(mensajeSinAcceso("terminal")).not.toMatch(/encargad|jefe|empleado/i);
  });
});

// 2026-11-23: a un administrador, con Equipo abierto, le salió «No tienes permiso»
// al dar de alta. Los permisos estaban bien: la sesión se había cerrado sola y la
// petición salió como `anon`. Desde entonces la guarda lo dice en vez de dejar que
// cada pantalla falle con un error equivocado.
describe("reaccionASesion", () => {
  it("la sesión se cerró sin que nadie lo pidiera: se avisa", () => {
    expect(reaccionASesion("SIGNED_OUT", null, "u1", false)).toBe("avisar");
  });

  it("«Cerrar sesión» a propósito no avisa: va directo al login", () => {
    expect(reaccionASesion("SIGNED_OUT", null, "u1", true)).toBeNull();
  });

  it("volvió a entrar la misma cuenta (en otra pestaña): el aviso se va y lo escrito sigue", () => {
    expect(reaccionASesion("SIGNED_IN", "u1", "u1", false)).toBe("quitar_aviso");
  });

  it("entró OTRA cuenta: se recarga, para no guardar lo de una a nombre de otra", () => {
    expect(reaccionASesion("SIGNED_IN", "u2", "u1", false)).toBe("recargar");
  });

  it("abrir la pantalla o renovar el token no avisa nada", () => {
    expect(reaccionASesion("INITIAL_SESSION", "u1", null, false)).toBe("quitar_aviso");
    expect(reaccionASesion("TOKEN_REFRESHED", "u1", "u1", false)).toBe("quitar_aviso");
    expect(reaccionASesion("INITIAL_SESSION", null, null, false)).toBeNull();
  });
});

describe("cerrarSesionAProposito", () => {
  it("sin alcance usa el de supabase-js, como hacía «Cerrar sesión»", async () => {
    const c = cliente({});
    await cerrarSesionAProposito(comoCliente(c));
    expect(c.signOut).toHaveBeenCalledWith();
  });

  it("la marca vale MIENTRAS dura signOut (ahí llega el SIGNED_OUT) y se quita al terminar", async () => {
    let duranteElCierre: boolean | undefined;
    const signOut = vi.fn(async () => { duranteElCierre = estaCerrandoAProposito(); return { error: null }; });
    // eslint-disable-next-line @typescript-eslint/no-explicit-any -- ver comoCliente.
    await cerrarSesionAProposito({ auth: { signOut } } as any);
    expect(duranteElCierre).toBe(true);
    expect(estaCerrandoAProposito()).toBe(false);
  });

  it("si signOut falla, la marca tampoco queda puesta: la próxima salida que nadie pidió avisa", async () => {
    const signOut = vi.fn(async () => { throw new Error("red"); });
    // eslint-disable-next-line @typescript-eslint/no-explicit-any -- ver comoCliente.
    await expect(cerrarSesionAProposito({ auth: { signOut } } as any)).rejects.toThrow("red");
    expect(estaCerrandoAProposito()).toBe(false);
  });
});

// ============================================================================
// sesion-del-terminal.test.ts — «se desloguea a ratos» no era un logout
// ============================================================================
// El 2026-08-13 el terminal volvía a pedir «Vincular este dispositivo» varias
// veces al día, sin que nadie tocara nada. No se desvinculaba: `getSession()`
// contesta `session: null` en DOS casos que no se parecen,
//
//     no hay ninguna sesión guardada  →  { session: null, error: null }
//     el token venció y el refresco no pudo salir a la red
//                                     →  { session: null, error: retryable }
//
// y las dos pantallas del terminal leían solo la sesión. En el segundo caso las
// credenciales SIGUEN en el disco —auth-js solo las borra cuando el servidor
// rechaza el refresh token, no cuando falla la red— y lo que tocaba era seguir
// marcando contra la caché, que es para lo que existe la cola offline.
//
// El token de acceso dura una hora, así que basta con que el internet de la
// tienda parpadee en el minuto equivocado. Y el `conTope` que ya había no lo
// cubría: solo salva del CUELGUE, y este fallo contesta rápido.
//
// Lo que se fija acá es la asimetría, que es lo que importa: ante la duda, el
// terminal NO manda a vincular. Una vinculación de más deja a la sede sin poder
// marcar; un veredicto «no se pudo saber» de más no cuesta nada, porque la
// pantalla de marcaje ya sabe trabajar sin red.
// ============================================================================
import { describe, expect, it } from "vitest";
import { AuthApiError, AuthRetryableFetchError } from "@supabase/supabase-js";
import { veredictoDeSesion } from "@/lib/terminal/sesion";

describe("veredictoDeSesion", () => {
  it("con sesión viva, el terminal está vinculado", () => {
    expect(veredictoDeSesion({ session: { access_token: "x" }, error: null })).toBe("vinculado");
  });

  it("sin sesión y sin error, de verdad hay que vincular el dispositivo", () => {
    expect(veredictoDeSesion({ session: null, error: null })).toBe("sin_vincular");
  });

  it("EL CASO: el refresco no pudo salir a la red — no se sabe, y no se vincula", () => {
    const sinRed = new AuthRetryableFetchError("Failed to fetch", 0);
    expect(veredictoDeSesion({ session: null, error: sinRed })).toBe("no_se_pudo_saber");
  });

  it("si el servidor RECHAZA el refresh token, sí hay que volver a vincular", () => {
    // Este es el caso en que auth-js sí borra las credenciales del disco: no hay
    // nada que preservar, y quedarse en la pantalla de marcaje solo conseguiría
    // que cada marca se encolara para ser rechazada.
    const rechazado = new AuthApiError("Invalid Refresh Token: Already Used", 400, "refresh_token_already_used");
    expect(veredictoDeSesion({ session: null, error: rechazado })).toBe("sin_vincular");
  });

  it("si no contestó a tiempo, tampoco se sabe", () => {
    expect(veredictoDeSesion(null)).toBe("no_se_pudo_saber");
  });
});

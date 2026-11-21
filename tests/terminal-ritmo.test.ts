// ============================================================================
// terminal-ritmo.test.ts — cuánto espera el terminal después de cada toque
// ============================================================================
// La regla de `lib/terminal/ritmo.ts` (2026-11-17): la buena noticia no detiene
// la fila; la mala sí, y más tiempo. Antes cada marca costaba 3 s de cuenta
// atrás más 2,5 s de «Listo» a pantalla completa (5,8 s medidos en el
// navegador); ahora son 2 s de cuenta atrás y la lista vuelve en el acto.
//
// Lo que más importa probar es lo que haría volver la espera SIN que nada
// falle: un reloj subido, o un «Listo» que vuelve a ocupar la pantalla. Y la
// otra mitad: que por ganar velocidad no se acorte un rechazo ni desaparezca la
// ventana para cancelar.
//
// La segunda parte lee las dos pantallas como texto. No reemplaza a mirarlas
// en el navegador (se midieron: ver el encabezado de ritmo.ts); vigila que
// nadie vuelva a escribir un reloj propio al lado del que ya existe.
// ============================================================================
import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";
import {
  SEGUNDOS_AVISO_LISTO,
  SEGUNDOS_AVISO_LISTO_CON_DETALLE,
  SEGUNDOS_CONFIRMACION,
  SEGUNDOS_MENSAJE_ALERTA,
  planDeMensaje,
} from "@/lib/terminal/ritmo";

describe("planDeMensaje", () => {
  it("la buena noticia no ocupa la pantalla: la lista queda libre para quien sigue", () => {
    expect(planDeMensaje("ok", false)).toEqual({ ocupaLaPantalla: false, segundos: SEGUNDOS_AVISO_LISTO });
  });

  it("con una segunda línea que leer se queda más, y tampoco ocupa la pantalla", () => {
    const plan = planDeMensaje("ok", true);
    expect(plan.ocupaLaPantalla).toBe(false);
    expect(plan.segundos).toBe(SEGUNDOS_AVISO_LISTO_CON_DETALLE);
    expect(plan.segundos).toBeGreaterThan(planDeMensaje("ok", false).segundos);
  });

  it("un rechazo SÍ ocupa la pantalla, con o sin segunda línea", () => {
    expect(planDeMensaje("alerta", false)).toEqual({ ocupaLaPantalla: true, segundos: SEGUNDOS_MENSAJE_ALERTA });
    expect(planDeMensaje("alerta", true)).toEqual({ ocupaLaPantalla: true, segundos: SEGUNDOS_MENSAJE_ALERTA });
  });

  it("la mala noticia espera más que la buena", () => {
    expect(planDeMensaje("alerta", false).segundos).toBeGreaterThan(planDeMensaje("ok", true).segundos);
  });
});

describe("los relojes", () => {
  it("la cuenta atrás no pasa de los 2 s que pidió Felipe", () => {
    expect(SEGUNDOS_CONFIRMACION).toBeLessThanOrEqual(2);
  });

  it("y sigue existiendo: es la única ventana para cancelar un toque en el nombre equivocado", () => {
    expect(SEGUNDOS_CONFIRMACION).toBeGreaterThanOrEqual(1);
    // La pantalla cuenta en segundos enteros: con medio segundo mostraría «0s» desde el principio.
    expect(Number.isInteger(SEGUNDOS_CONFIRMACION)).toBe(true);
  });

  it("un rechazo no se acortó por ganar velocidad", () => {
    expect(SEGUNDOS_MENSAJE_ALERTA).toBeGreaterThanOrEqual(8);
  });

  it("el «Listo» da tiempo de leerse", () => {
    expect(SEGUNDOS_AVISO_LISTO).toBeGreaterThanOrEqual(3);
  });
});

const MARCAR = path.resolve(import.meta.dirname, "../apps/web/app/(terminal)/terminal/marcar");
const pagina = readFileSync(path.join(MARCAR, "page.tsx"), "utf8");
const componentes = readFileSync(path.join(MARCAR, "components.tsx"), "utf8");
const hojasRetratos = readFileSync(path.join(MARCAR, "hojas-retratos.tsx"), "utf8");
const retratos = readFileSync(path.join(MARCAR, "retratos.tsx"), "utf8");
const estilosRetratos = readFileSync(path.resolve(MARCAR, "../../../estilos/vidrio/terminal-retratos.css"), "utf8");

/** El cuerpo de una función exportada o interna, hasta la siguiente del mismo nivel. */
function cuerpoDe(fuente: string, firma: string): string {
  const desde = fuente.indexOf(firma);
  expect(desde, `no encontré «${firma}»`).toBeGreaterThanOrEqual(0);
  const resto = fuente.slice(desde + firma.length);
  const hasta = resto.search(/\n(export )?(async )?function |\n {2}(async )?function /);
  return hasta === -1 ? resto : resto.slice(0, hasta);
}

describe("la pantalla de marcar usa ese ritmo y no uno propio", () => {
  it("no vuelve a escribir sus relojes a mano", () => {
    expect(pagina).not.toMatch(/const SEGUNDOS_(CONFIRMACION|MENSAJE\w*|AVISO\w*)\s*=/);
    expect(pagina).toContain("segundosTotal={SEGUNDOS_CONFIRMACION}");
  });

  it("todo mensaje pasa por mostrarMensaje, y es el plan el que decide si ocupa la pantalla", () => {
    // Un solo lugar arma la pantalla de mensaje: un segundo camino es el que se queda con el reloj viejo.
    expect(pagina.match(/setPantalla\("mensaje"\)/g)).toHaveLength(1);
    const cuerpo = cuerpoDe(pagina, "function mostrarMensaje(");
    expect(cuerpo).toContain("planDeMensaje(tono, detalle !== null)");
    const guarda = cuerpo.indexOf("if (!plan.ocupaLaPantalla)");
    const pantalla = cuerpo.indexOf('setPantalla("mensaje")');
    expect(guarda).toBeGreaterThanOrEqual(0);
    // La buena noticia sale ANTES de llegar a la pantalla completa.
    expect(pantalla).toBeGreaterThan(guarda);
    expect(cuerpo.slice(guarda, pantalla)).toContain("volverALista();");
    expect(cuerpo.slice(guarda, pantalla)).toContain("return;");
  });

  it("un «Listo» anterior no se queda flotando sobre un rechazo", () => {
    const cuerpo = cuerpoDe(pagina, "function mostrarMensaje(");
    expect(cuerpo).toContain("setAvisoListo(null);");
  });
});

describe("el aviso «Listo»", () => {
  // Dentro de cada caso y no aquí arriba: si la función no existe, tiene que fallar ese caso, no el archivo entero.
  const aviso = () => cuerpoDe(componentes, "export function AvisoListo(");

  it("no ocupa lugar ni recibe toques: la grilla no se mueve bajo el dedo de quien sigue", () => {
    expect(aviso()).toContain("pointer-events-none");
    expect(aviso()).toMatch(/className="[^"]*\bfixed\b/);
  });

  it("lo anuncia un lector de pantalla sin interrumpir", () => {
    expect(aviso()).toContain('role="status"');
  });
});

// En la pantalla de retratos el «Listo» sale dentro de la isla. Otro dibujo, los mismos cuidados.
describe("el «Listo» de la isla, en la pantalla de retratos", () => {
  /** El bloque de una regla del CSS, por su selector exacto. */
  const regla = (selector: string) => {
    const desde = estilosRetratos.indexOf(`[data-vidrio="terminal"] ${selector} {`);
    expect(desde, `no encontré la regla «${selector}»`).toBeGreaterThanOrEqual(0);
    return estilosRetratos.slice(desde, estilosRetratos.indexOf("}", desde));
  };

  it("no ocupa lugar ni recibe toques: la isla mide lo mismo y ningún retrato se mueve bajo el dedo de quien sigue", () => {
    expect(regla(".tr-listo")).toContain("position: absolute;");
    expect(regla(".tr-listo")).toContain("pointer-events: none;");
    // Lo de siempre se esconde SIN dejar de ocupar su lugar: con `display: none` la isla cambiaría de tamaño.
    expect(regla(".tr-isla[data-listo] > :not(.tr-listo)")).toContain("visibility: hidden;");
  });

  it("sigue a la vista aunque la persona siguiente ya haya abierto su hoja", () => {
    const z = (bloque: string) => Number(/z-index: (\d+);/.exec(bloque)?.[1]);
    expect(z(regla(".tr-isla[data-listo]"))).toBeGreaterThan(z(regla(".tr-capa")));
  });

  it("lo anuncia un lector de pantalla sin interrumpir, desde una región que ya existía", () => {
    const cuerpo = cuerpoDe(retratos, "function ListoDeIsla(");
    expect(cuerpo).toContain('role="status"');
    expect(cuerpo).toContain('aria-live="polite"');
    // La región se dibuja siempre y es su contenido el que aparece: no `{listo && <div role="status">`.
    expect(cuerpo.indexOf('role="status"')).toBeLessThan(cuerpo.indexOf("{listo && ("));
  });

  it("es el mismo aviso con el mismo reloj: la pantalla le pasa el de siempre y no lo dibuja dos veces", () => {
    expect(pagina).toContain("listo={avisoListo}");
    expect(pagina.match(/<AvisoListo /g)).toHaveLength(1);
  });
});

describe("la cuenta atrás, una vez que la marca salió", () => {
  const cuenta = () => cuerpoDe(componentes, "export function ConfirmacionToast(");

  it("no ofrece cancelar lo que ya no se puede cancelar, ni confirmar dos veces", () => {
    expect(cuenta().match(/disabled=\{enviando\}/g)).toHaveLength(2);
  });

  it("dice que está enviando, no «Confirmando en 0s…»", () => {
    expect(cuenta()).toContain('enviando ? "Enviando…"');
  });
});

// La pantalla de retratos dibuja la misma cuenta atrás como un anillo alrededor de la foto. Cambia el dibujo, no la
// regla: lo que protege de una marca cancelada que igual cuenta para el pago tiene que seguir ahí.
describe("el anillo de la pantalla de retratos, una vez que la marca salió", () => {
  const anillo = () => cuerpoDe(hojasRetratos, "export function HojaAnillo(");

  it("no ofrece cancelar lo que ya no se puede cancelar, ni confirmar dos veces", () => {
    expect(anillo().match(/disabled=\{enviando\}/g)).toHaveLength(2);
    expect(anillo()).toContain("if (yaConfirmoRef.current) return;");
  });

  it("dice que está enviando", () => {
    expect(anillo()).toContain('enviando ? "Enviando…"');
  });

  it("espera lo que diga el ritmo, no un número propio", () => {
    expect(anillo()).toContain("segundosTotal * 1000");
    expect(pagina.match(/segundosTotal=\{SEGUNDOS_CONFIRMACION\}/g)).toHaveLength(2);
  });

  it("no muestra la hora de la marca antes de que la base la selle", () => {
    // La hora que cuenta la pone el servidor; el reloj de la Mac puede estar corrido.
    expect(anillo()).not.toMatch(/toLocaleTimeString|Intl\.DateTimeFormat|new Date\(/);
  });
});

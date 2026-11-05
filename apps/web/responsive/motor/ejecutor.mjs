// Recorre pantalla × escenario × viewport. GENÉRICO: la preparación de cada escenario es de la pantalla (`responsive/pantallas/`) y la detección
// es de `deteccion.mjs`. La sesión y el candado de la red son los mismos de `tema/`: no hay una segunda forma de entrar a Dynamic.

import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { porClave } from "../../tema/cuentas.mjs";
import { abrirPantalla } from "../../tema/motor/pagina.mjs";
import { abrirContexto, abrirNavegador } from "../../tema/motor/sesion.mjs";
import { analizarEnPagina, SELECTORES_POR_DEFECTO } from "./deteccion.mjs";
import { resolverViewports } from "../matriz-viewports.mjs";

const ESCENARIO_POR_DEFECTO = [{ id: "inicial", nombre: "Estado inicial", preparar: null }];

/**
 * @param {import('../pantallas/registro.mjs').Pantalla[]} pantallas
 * @param {{ baseURL: string, apiURL: string, dirSalida: string, capturasTodas?: boolean, headed?: boolean, tolerancia?: number }} opciones
 */
export async function ejecutarVerificacion(pantallas, opciones) {
  const { baseURL, apiURL, dirSalida, capturasTodas = false, headed = false, tolerancia = 1 } = opciones;
  const dirCapturas = join(dirSalida, "capturas");
  mkdirSync(dirCapturas, { recursive: true });

  const navegador = await abrirNavegador({ headed });
  const fuera = new Set();
  // Un contexto por cuenta, y aparte el de celular: un celular se emula desde que se crea el contexto, no al cambiarle el tamaño.
  const contextos = new Map();
  const contextoDe = async (cuenta, viewport) => {
    const clave = `${cuenta.clave}|${viewport.w < 700}`;
    if (!contextos.has(clave)) contextos.set(clave, await abrirContexto(navegador, cuenta, { baseUrl: baseURL, apiUrl: apiURL, tema: "claro", viewport: { width: viewport.w, height: viewport.h }, fuera }));
    return contextos.get(clave);
  };

  const resultados = [];
  const inicio = Date.now();
  try {
    for (const pantalla of pantallas) {
      const cuenta = porClave(pantalla.cuenta);
      if (!cuenta) throw new Error(`La pantalla ${pantalla.id} pide la cuenta «${pantalla.cuenta}», que no existe.`);
      const escenarios = pantalla.escenarios?.length ? pantalla.escenarios : ESCENARIO_POR_DEFECTO;
      for (const escenario of escenarios) {
        for (const viewport of resolverViewports(escenario.viewports ?? pantalla.viewports)) {
          const contexto = await contextoDe(cuenta, viewport);
          process.stdout.write(`  ${pantalla.id} · ${escenario.id} · ${viewport.id}\n`);
          resultados.push(await correrUnCaso({ contexto, baseURL, pantalla, cuenta, escenario, viewport, tolerancia, capturasTodas, dirCapturas }));
        }
      }
    }
  } finally {
    for (const contexto of contextos.values()) await contexto.close().catch(() => {});
    await navegador.close().catch(() => {});
  }
  return { resultados, duracionMs: Date.now() - inicio, fuera };
}

async function correrUnCaso({ contexto, baseURL, pantalla, cuenta, escenario, viewport, tolerancia, capturasTodas, dirCapturas }) {
  const entrada = { pantalla, escenario, viewport, ok: true, overflowGlobal: null, clipping: [], advertencia: null, screenshot: null, error: null, sesionPerdida: false };
  const pagina = await contexto.newPage();
  try {
    await pagina.setViewportSize({ width: viewport.w, height: viewport.h });
    const { ruta: final, termino } = await abrirPantalla(pagina, `${baseURL}${pantalla.ruta}`, { esperaMs: 500 });
    // Sin esto, una sesión que no valió mide el login y pasa en verde: en un formulario de dos campos nada se sale.
    if (final !== pantalla.ruta) {
      entrada.sesionPerdida = !!cuenta.correo && /\/(login|vincular)$/.test(final);
      throw new Error(`se esperaba ${pantalla.ruta} y la app mandó a ${final}`);
    }
    if (!termino) throw new Error("seguía en «Cargando…»");

    if (escenario.preparar) await escenario.preparar(pagina, { viewport, pantalla, escenario });
    await pagina.waitForTimeout(150); // las animaciones cortas de un modal o un cajón

    const analisis = await pagina.evaluate(analizarEnPagina, {
      selectoresClave: [...SELECTORES_POR_DEFECTO, ...(pantalla.elementosClave || []), ...(escenario.elementosClave || [])],
      selectoresExclusion: [...(pantalla.exclusiones || []), ...(escenario.exclusiones || [])],
      ambito: escenario.ambito ?? pantalla.ambito ?? null,
      limite: escenario.limite ?? pantalla.limite ?? null,
      tolerancia,
    });
    entrada.overflowGlobal = analisis.overflowGlobal;
    entrada.clipping = analisis.clipping;
    entrada.advertencia = analisis.advertencia || null;
    entrada.ok = analisis.clipping.length === 0;

    if (!entrada.ok || capturasTodas) {
      const ruta = join(dirCapturas, `${pantalla.id.replace(/\./g, "-")}-${escenario.id}-${viewport.id}-${entrada.ok ? "PASS" : "FAIL"}.png`);
      await pagina.screenshot({ path: ruta });
      entrada.screenshot = ruta;
    }
  } catch (e) {
    entrada.ok = false;
    entrada.error = e instanceof Error ? e.message.split("\n")[0] : String(e);
  } finally {
    await pagina.close();
  }
  return entrada;
}

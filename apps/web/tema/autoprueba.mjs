#!/usr/bin/env node
/**
 * ¿Los medidores siguen viendo lo que dicen ver? Una regla de la casa: un freno se prueba con un caso que DEBE bloquear, porque el que solo se prueba con
 * lo que debe pasar puede estar roto y seguir dando verde. Aquí cada detector recibe una página de mentira con defectos conocidos y excepciones
 * conocidas, y tiene que encontrar EXACTAMENTE esos.
 *
 *   npx pnpm --filter @cayla-dynamic/web medidores:autoprueba
 *
 * No toca ningún servidor ni ninguna base: la página nace y muere en el navegador. Hay que correrla después de cambiar `motor/escaner-en-pagina.js`
 * o `responsive/motor/deteccion.mjs`. No va en vitest porque necesita Chrome. Sale con 0 si todo cuadra, con 1 si algo no.
 */

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { analizarEnPagina, SELECTORES_POR_DEFECTO } from "../responsive/motor/deteccion.mjs";
import { abrirNavegador } from "./motor/sesion.mjs";

const AQUI = dirname(fileURLToPath(import.meta.url));
const ESCANER = readFileSync(join(AQUI, "motor", "escaner-en-pagina.js"), "utf8");

const SUPERFICIE = "width:400px;height:200px";
const PAGINA_DE_CONTRASTE = `<!doctype html>
<html data-tema="oscuro"><head><style>
  :root { --color-crema:#1c1a16; --color-papel:#26221d; --color-tinta:#ede7db; --color-crema-fija:#f5f0e8; }
  body { margin:0; background:var(--color-crema); color:var(--color-tinta); }
</style></head><body>
  <p>Se lee bien</p>
  <p style="color:#6b6b6b">No se lee</p>
  <p style="color:#6b6b6b;font-size:30px">Grande con 3 alcanza</p>
  <button disabled style="color:#333">Deshabilitado queda exento</button>
  <a href="#" style="position:absolute;width:1px;height:1px;padding:8px 16px;overflow:hidden;clip-path:inset(50%);color:#1c1a16">Recortado a la vista queda exento</a>
  <span aria-hidden="true" style="color:#777">›</span>
  <span aria-hidden="true" style="color:#444">·</span>
  <kbd aria-hidden="true" style="color:#777">/</kbd>
  <div style="background:linear-gradient(#fff,#000)"><span style="color:var(--color-tinta)">Sobre degradado</span></div>
  <em style="background:linear-gradient(#fff,#eee);-webkit-background-clip:text;background-clip:text;color:transparent">Pintada por un degradado</em>
  <div id="mancha" class="suelta" style="background:#fff;${SUPERFICIE}"></div>
  <div class="hoja"><div style="background:#fff;${SUPERFICIE}"></div></div>
  <div class="contrato"><div style="background:#fff;${SUPERFICIE}"></div></div>
  <div class="firma-tinta" style="background:#fff;${SUPERFICIE}"></div>
  <div style="background:var(--color-crema-fija);${SUPERFICIE}"></div>
  <div style="background:var(--color-papel);${SUPERFICIE}"></div>
  <div class="tarjeta-invertida" style="background:var(--color-tinta);${SUPERFICIE}"></div>
  <div class="vidrio-claro" style="background:linear-gradient(rgba(237,231,219,.84),rgba(237,231,219,.97));${SUPERFICIE}"></div>
  <div title="elegida: chica, como un botón" style="background:var(--color-tinta);width:250px;height:80px"></div>
  <div style="background:#fff;width:40px;height:40px"></div>
  <div id="velo-malo" style="position:fixed;inset:0;background:rgba(255,255,255,.4);pointer-events:none"></div>
  <div style="position:fixed;inset:0;background:rgba(0,0,0,.4);pointer-events:none"></div>
</body></html>`;

const PAGINA_DE_RESPONSIVE = `<!doctype html>
<html><body style="margin:0">
  <button>Cabe</button>
  <button style="display:block;width:900px">Se sale</button>
  <div style="overflow-x:auto;width:300px"><button style="width:900px">Se llega desplazando</button></div>
  <button style="display:none;width:900px">Oculto</button>
  <div hidden><button style="width:900px">Dentro de hidden</button></div>
  <div aria-hidden="true"><a href="#" style="display:block;width:900px">Dentro de aria-hidden</a></div>
  <div inert><button style="width:900px">Dentro de inert</button></div>
  <div data-fuera-de-pantalla><button style="width:900px">Fuera de pantalla a propósito</button></div>
</body></html>`;

// El detalle de una liquidación: lo que va adentro de una tabla que corre de lado se salta, salvo que el escenario pida verlo sin deslizar.
const paginaDelDetalle = (anchoTabla) => `<!doctype html>
<html><body style="margin:0"><main>
  <div style="overflow-x:auto"><table data-tira style="width:${anchoTabla};border-spacing:0">
    <tr data-detalle><td style="width:80%">Total</td><td>S/ 1,000.00</td></tr>
  </table></div>
</main></body></html>`;

let fallas = 0;
function revisar(nombre, real, esperado) {
  const a = JSON.stringify(real);
  const b = JSON.stringify(esperado);
  if (a === b) console.log(`  ok    ${nombre}`);
  else {
    fallas++;
    console.log(`  FALLA ${nombre}\n        esperaba ${b}\n        encontró ${a}`);
  }
}

const navegador = await abrirNavegador();
try {
  const pagina = await navegador.newPage({ viewport: { width: 1000, height: 800 } });

  console.log("Auditoría de contraste, en oscuro:");
  await pagina.setContent(PAGINA_DE_CONTRASTE);
  await pagina.addScriptTag({ content: ESCANER });
  let r = await pagina.evaluate(() => window.__temaEscanear());
  revisar("lee el tema de <html>", r.tema, "oscuro");
  // «/» es una tecla: su color pasaría como gráfico (3:1) pero sigue siendo texto, así que tiene que aparecer. El «›» del mismo color no.
  revisar("el contraste encuentra justo el texto ilegible, la tecla y el gráfico por debajo de 3:1", r.contrastes.map((h) => h.texto).sort(), ["No se lee", "·", "/"].sort());
  revisar("el gráfico se mide contra 3 y lo demás contra 4.5", r.contrastes.map((h) => h.umbral).sort(), [3, 4.5, 4.5]);
  revisar("cuenta lo que no puede medir: un texto sobre un degradado y una letra recortada de uno, sin darla por ilegible", r.sobreDegradado, 2);
  revisar(
    "cinco manchas: el blanco suelto, el de dentro de .hoja y .contrato, la tarjeta de tinta invertida y la de vidrio claro; no el papel, ni la crema fija, ni lo chico",
    r.manchas.map((m) => m.donde.match(/(hoja|contrato|suelta|tarjeta-invertida|vidrio-claro)/)?.[0] ?? m.donde).sort(),
    ["suelta", "hoja", "contrato", "tarjeta-invertida", "vidrio-claro"].sort(),
  );
  revisar("lo claro de .firma-tinta no cuenta, pero se anota", r.manchasExentas.length, 1);
  revisar("un solo velo: el que aclara, no el que oscurece", r.velos.length, 1);

  // El fondo del vidrio (la aurora) es una capa fija, a pantalla completa, pintada con degradados. No es un velo ni una mancha: leer degradados
  // para las tarjetas no puede volverla una de las dos.
  await pagina.setContent(`<!doctype html><html data-tema="oscuro"><body style="margin:0;background:#1c1a16">
    <div style="position:fixed;inset:0;background:radial-gradient(rgba(237,231,219,.9),transparent 70%);pointer-events:none"></div></body></html>`);
  await pagina.addScriptTag({ content: ESCANER });
  r = await pagina.evaluate(() => window.__temaEscanear());
  revisar("la aurora fija con degradado no es velo ni mancha", [r.velos.length, r.manchas.length], [0, 0]);

  console.log("Auditoría de contraste, en claro:");
  await pagina.setContent(PAGINA_DE_CONTRASTE.replace('data-tema="oscuro"', 'data-tema="claro"'));
  await pagina.addScriptTag({ content: ESCANER });
  r = await pagina.evaluate(() => window.__temaEscanear());
  revisar("lee el tema de <html>", r.tema, "claro");
  revisar("manchas y velos solo se buscan en oscuro", [r.manchas.length, r.manchasExentas.length, r.velos.length], [0, 0, 0]);

  console.log("Verificación de responsive, a 375 px:");
  await pagina.setViewportSize({ width: 375, height: 812 });
  await pagina.setContent(PAGINA_DE_RESPONSIVE);
  const d = await pagina.evaluate(analizarEnPagina, { selectoresClave: SELECTORES_POR_DEFECTO, selectoresExclusion: [], ambito: null, limite: null, tolerancia: 1 });
  revisar("encuentra justo el botón que se sale", d.clipping.map((c) => c.texto), ["Se sale"]);
  revisar("mide cuánto se sale", d.clipping.map((c) => c.exceso), [525]);

  console.log("Verificación de responsive, lo que tiene que verse sin deslizar:");
  const delDetalle = (extra) => pagina.evaluate(analizarEnPagina, { selectoresClave: ["td"], selectoresExclusion: [], ambito: "[data-detalle]", limite: null, tolerancia: 1, ...extra });
  await pagina.setContent(paginaDelDetalle("900px"));
  revisar("sin límite, el monto dentro de la tira se salta: se llega deslizando", (await delDetalle({})).clipping.length, 0);
  const sinDeslizar = await delDetalle({ limite: "main" });
  revisar("con límite y ámbito, el mismo monto cuenta como fuera de vista", sinDeslizar.clipping.map((c) => c.texto), ["Total", "S/ 1,000.00"]);
  revisar("y dice contra qué se midió", sinDeslizar.clipping[0]?.contra, "contenedor:main");
  await pagina.setContent(paginaDelDetalle("100%"));
  revisar("si la tabla cabe, no hay nada que señalar", (await delDetalle({ limite: "main" })).clipping.length, 0);
  const sinAmbito = await delDetalle({ limite: "main", ambito: "[data-no-existe]" });
  revisar("un ámbito que no aparece se dice: no es lo mismo que no encontrar nada", sinAmbito.advertencia, 'ámbito "[data-no-existe]" no encontrado en el DOM');
} finally {
  await navegador.close();
}

console.log(fallas ? `\n${fallas} comprobaciones fallaron: este medidor no está viendo lo que dice ver.` : "\nTodo cuadra: los detectores encuentran lo que deben y nada más.");
process.exit(fallas ? 1 : 0);

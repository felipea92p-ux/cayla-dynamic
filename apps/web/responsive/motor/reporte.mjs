// Formatea los resultados de `ejecutor.mjs` para la consola y los vuelca a `reporte.md` y `reporte.json`.

import { writeFileSync } from "node:fs";
import { join, relative } from "node:path";

/** Agrupa por pantalla → escenario, en el orden en que se corrieron. */
function agrupar(resultados) {
  const grupos = [];
  const indice = new Map();
  for (const r of resultados) {
    const clave = `${r.pantalla.id}::${r.escenario.id}`;
    let g = indice.get(clave);
    if (!g) {
      g = { pantalla: r.pantalla, escenario: r.escenario, items: [] };
      indice.set(clave, g);
      grupos.push(g);
    }
    g.items.push(r);
  }
  return grupos;
}

/** La señal de «la página entera se mueve de lado». Se informa y no decide sola: el veredicto lo da el elemento que de verdad se sale. */
const seMueveDeLado = (r) => !!r.overflowGlobal && r.overflowGlobal.scrollWidthDoc > r.overflowGlobal.clientWidth + 1;

const estadoDe = (r) => (r.error ? "ERROR" : r.ok ? "PASS" : "FAIL");

function bloqueFalla(r, dirSalida) {
  if (r.error) return `ERROR [${r.viewport.id}]: ${r.error}`;
  const lineas = [];
  for (const c of r.clipping) {
    lineas.push(`FAIL [${r.viewport.id}]: ${c.selector}${c.texto ? ` — "${c.texto}"` : ""} (${c.tipo}) se sale ${c.exceso}px por la ${c.lado}, contra ${c.contra}`);
  }
  if (r.screenshot) lineas.push(`  Captura: ${relative(dirSalida, r.screenshot)}`);
  if (r.advertencia) lineas.push(`  Advertencia: ${r.advertencia}`);
  return lineas.join("\n");
}

export function imprimirReporte(resultados, { dirSalida }) {
  console.log("\nVERIFICACIÓN DE RESPONSIVE\n");
  for (const g of agrupar(resultados)) {
    console.log(`${g.pantalla.modulo} / ${g.pantalla.nombre} / ${g.escenario.nombre}`);
    for (const r of g.items) console.log(`  ${r.viewport.id.padEnd(10)} ${estadoDe(r)}${seMueveDeLado(r) ? "  (la página se mueve de lado)" : ""}`);
    const fallas = g.items.filter((r) => !r.ok);
    if (fallas.length) {
      console.log("");
      for (const r of fallas) console.log(bloqueFalla(r, dirSalida).replace(/^/gm, "  "));
    }
    console.log("");
  }
  const pasan = resultados.filter((r) => r.ok).length;
  const errores = resultados.filter((r) => r.error).length;
  const fallan = resultados.length - pasan - errores;
  console.log(`RESULTADO: ${pasan} PASS · ${fallan} FAIL · ${errores} ERROR · ${resultados.filter(seMueveDeLado).length} con la página moviéndose de lado`);
  return { pasan, fallan, errores, exitoso: fallan === 0 && errores === 0 };
}

export function guardarReporte(resultados, { dirSalida, duracionMs, seleccion }) {
  const grupos = agrupar(resultados).map((g) => ({
    pantalla: g.pantalla.id,
    modulo: g.pantalla.modulo,
    nombre: g.pantalla.nombre,
    cuenta: g.pantalla.cuenta,
    escenario: g.escenario.id,
    casos: g.items.map((r) => ({
      viewport: r.viewport.id,
      ok: r.ok,
      seMueveDeLado: seMueveDeLado(r),
      overflowGlobal: r.overflowGlobal,
      clipping: r.clipping,
      advertencia: r.advertencia,
      screenshot: r.screenshot ? relative(dirSalida, r.screenshot) : null,
      error: r.error,
    })),
  }));
  const pasan = resultados.filter((r) => r.ok).length;
  const errores = resultados.filter((r) => r.error).length;
  const fallan = resultados.length - pasan - errores;
  const conMovimiento = resultados.filter(seMueveDeLado).length;
  const json = { generadoEn: new Date().toISOString(), seleccion, duracionMs, totales: { pasan, fallan, errores, conMovimiento, total: resultados.length }, grupos };
  writeFileSync(join(dirSalida, "reporte.json"), JSON.stringify(json, null, 2));

  const md = [
    "# Verificación de responsive",
    "",
    `Generado: ${json.generadoEn} · Selección: \`${seleccion}\` · Duración: ${(duracionMs / 1000).toFixed(1)}s`,
    "",
    `**${pasan} PASS · ${fallan} FAIL · ${errores} ERROR** de ${resultados.length} casos. En ${conMovimiento} la página entera se mueve de lado (señal: no decide el veredicto).`,
    "",
    ...grupos.flatMap((g) => [
      `## ${g.modulo} / ${g.nombre} / ${g.escenario} (${g.cuenta})`,
      "",
      "| Viewport | Resultado | Se mueve de lado |",
      "|---|---|---|",
      ...g.casos.map((c) => `| ${c.viewport} | ${c.error ? "ERROR" : c.ok ? "PASS" : "FAIL"} | ${c.seMueveDeLado ? `sí (${c.overflowGlobal.scrollWidthDoc} sobre ${c.overflowGlobal.clientWidth} px)` : ""} |`),
      "",
      ...g.casos
        .filter((c) => !c.ok)
        .flatMap((c) => [
          `**${c.error ? "ERROR" : "FAIL"} ${c.viewport}**${c.error ? ` — ${c.error}` : ""}${c.screenshot ? ` — \`${c.screenshot}\`` : ""}`,
          ...c.clipping.map((cl) => `- \`${cl.selector}\` se sale ${cl.exceso}px por la ${cl.lado} (contra ${cl.contra})`),
          "",
        ]),
    ]),
  ].join("\n");
  writeFileSync(join(dirSalida, "reporte.md"), md);
}

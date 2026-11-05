// Arma el reporte de una corrida. Un texto que no se lee es un defecto en cualquiera de los dos temas: el reporte separa dónde falla, porque
// eso dice qué hay que arreglar (lo que falla en un solo tema suele ser un token de ese tema), pero no perdona a ninguno.

import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const linea = (h) => `  - **${h.ratio}** (${h.grafico ? "gráfico, " : ""}mín. ${h.umbral}) «${h.texto}» ${h.color} sobre ${h.fondo}${h.imagen ? " ⚠ sobre imagen o degradado: este número no lo cuenta" : ""} — \`${h.donde}\``;

export function resumirVisita(v) {
  const oscuros = v.oscuro?.contrastes ?? [];
  const claros = v.claro?.contrastes ?? [];
  const enClaro = new Set(claros.map((h) => h.clave));
  const enOscuro = new Set(oscuros.map((h) => h.clave));
  return {
    soloOscuro: oscuros.filter((h) => !enClaro.has(h.clave)),
    soloClaro: claros.filter((h) => !enOscuro.has(h.clave)),
    enLosDos: oscuros.filter((h) => enClaro.has(h.clave)),
    manchas: v.oscuro?.manchas ?? [],
    exentas: v.oscuro?.manchasExentas ?? [],
    velos: v.oscuro?.velos ?? [],
    sobreDegradado: Math.max(v.claro?.sobreDegradado ?? 0, v.oscuro?.sobreDegradado ?? 0),
    textos: Math.max(v.claro?.textosAnalizados ?? 0, v.oscuro?.textosAnalizados ?? 0),
  };
}

/** Los pares de color que más fallan: casi siempre se arreglan en un token, no pantalla por pantalla. */
function paresQueMasFallan(visitas) {
  const pares = new Map();
  for (const v of visitas) {
    for (const tema of ["claro", "oscuro"]) {
      for (const h of v[tema]?.contrastes ?? []) {
        const clave = `${tema}: ${h.color} sobre ${h.fondo}`;
        const p = pares.get(clave) ?? { clave, veces: 0, peor: Infinity, ejemplo: h.texto };
        p.veces++;
        p.peor = Math.min(p.peor, h.ratio);
        pares.set(clave, p);
      }
    }
  }
  return [...pares.values()].sort((a, b) => b.veces - a.veces).slice(0, 15);
}

export function escribirReporte(dirSalida, visitas, meta) {
  mkdirSync(dirSalida, { recursive: true });
  const filas = [];
  const detalle = [];
  const totales = { soloOscuro: 0, soloClaro: 0, enLosDos: 0, manchas: 0, exentas: 0, velos: 0, sobreDegradado: 0, textos: 0, medidas: 0, sinMedir: 0 };
  for (const v of visitas) {
    if (v.estado !== "ok") {
      totales.sinMedir++;
      filas.push(`| ${v.cuenta} | ${v.titulo} | ${v.estado} | | | | | | | |`);
      continue;
    }
    totales.medidas++;
    const r = resumirVisita(v);
    for (const k of ["soloOscuro", "soloClaro", "enLosDos", "manchas", "exentas", "velos"]) totales[k] += r[k].length;
    totales.sobreDegradado += r.sobreDegradado;
    totales.textos += r.textos;
    const malos = r.soloOscuro.length + r.soloClaro.length + r.enLosDos.length + r.manchas.length + r.velos.length;
    filas.push(`| ${v.cuenta} | ${v.titulo} | ${malos ? "falla" : "bien"} | ${r.textos} | ${r.soloOscuro.length} | ${r.soloClaro.length} | ${r.enLosDos.length} | ${r.manchas.length} | ${r.velos.length} | ${r.sobreDegradado} |`);
    if (!malos && !v.errores.length && !r.exentas.length) continue;
    detalle.push(`### ${v.cuenta} · ${v.titulo}\n`);
    if (v.captura) detalle.push(`Captura: \`${v.captura}\`\n`);
    const lista = (titulo, hs) => hs.length && detalle.push(`**${titulo} (${hs.length}):**\n${[...hs].sort((a, b) => a.ratio - b.ratio).slice(0, 30).map(linea).join("\n")}\n`);
    lista("Contraste que falla solo en oscuro", r.soloOscuro);
    lista("Contraste que falla solo en claro", r.soloClaro);
    lista("Contraste que falla en los dos temas (colores del oscuro)", r.enLosDos);
    if (r.manchas.length) detalle.push(`**Manchas claras (${r.manchas.length}):**\n${r.manchas.slice(0, 15).map((m) => `  - ${m.fondo} ${m.tam} — \`${m.donde}\``).join("\n")}\n`);
    if (r.exentas.length) detalle.push(`**Claras a propósito, no cuentan (${r.exentas.length}):**\n${r.exentas.slice(0, 15).map((m) => `  - ${m.fondo} ${m.tam} — \`${m.donde}\``).join("\n")}\n`);
    if (r.velos.length) detalle.push(`**Velos que aclaran (${r.velos.length}):**\n${r.velos.map((m) => `  - ${m.fondo} sobre una página ${m.pagina} — \`${m.donde}\``).join("\n")}\n`);
    if (v.errores.length) detalle.push(`**Errores de consola:** ${v.errores.slice(0, 4).map((e) => "`" + e.slice(0, 120) + "`").join(" · ")}\n`);
  }
  const hallazgos = totales.soloOscuro + totales.soloClaro + totales.enLosDos + totales.manchas + totales.velos;
  const pares = paresQueMasFallan(visitas.filter((v) => v.estado === "ok"));
  const md = [
    `# Auditoría de contraste — ${meta.cuando}`,
    "",
    `Base: ${meta.baseUrl} · viewport ${meta.ancho}×${meta.alto} · ${totales.medidas} pantallas medidas, ${totales.sinMedir} sin medir · **${hallazgos} hallazgos**`,
    "",
    `Contraste: ${totales.soloOscuro} solo en oscuro · ${totales.soloClaro} solo en claro · ${totales.enLosDos} en los dos. Manchas: ${totales.manchas} (${totales.exentas} claras a propósito no cuentan). Velos: ${totales.velos}.`,
    "",
    "«Sobre degradado» cuenta los textos que este escáner midió sin ver su fondo real: solo suma colores planos. Esos los mide `tests/vidrio-contraste.test.ts`.",
    "",
    "| Cuenta | Pantalla | | Textos | Solo oscuro | Solo claro | En los dos | Manchas | Velos | Sobre degradado |",
    "|---|---|---|---|---|---|---|---|---|---|",
    ...filas,
    "",
    ...(pares.length ? ["## Los pares de color que más fallan", "", "| Par | Veces | Peor | Ejemplo |", "|---|---|---|---|", ...pares.map((p) => `| ${p.clave} | ${p.veces} | ${p.peor} | «${p.ejemplo}» |`), ""] : []),
    ...detalle,
  ].join("\n");
  writeFileSync(join(dirSalida, "reporte.md"), md);
  writeFileSync(join(dirSalida, "reporte.json"), JSON.stringify({ meta, totales, hallazgos, pares, visitas }, null, 1));
  return { hallazgos, totales, md };
}

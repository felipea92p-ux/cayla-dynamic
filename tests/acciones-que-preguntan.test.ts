// ============================================================================
// acciones-que-preguntan.test.ts — lo que no se deshace no ocurre de un clic
// ============================================================================
// El caso que la originó (2026-11-07): tres botones del panel actuaban al primer
// clic, sin preguntar. «Anular» un comunicado (Anuncios) no tiene vuelta atrás;
// «Resetear contraseña» (Cuentas) deja sin servir la clave de esa persona en el
// acto, y la temporal solo vive en esa pantalla; «Desactivar» un área (Áreas) no
// preguntaba, mientras que «Desactivar» una sede sí. Un clic en la fila de al lado
// bastaba.
//
// Lo que se defiende: cada una de esas acciones se llama SOLO desde una función
// `confirmar…`, que es la que dispara el «Sí, …» del <Modal>. Un botón que la
// llame directo vuelve a abrir el defecto, y esta prueba lo dice.
//
// Las pruebas de esta casa no dibujan pantallas (vitest corre en node), así que
// se lee el código: la llamada y la función que la contiene. Es un escáner de
// texto, no un compilador; si alguien llama la acción por otro nombre, no la ve.
// ============================================================================

import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

const RAIZ = path.resolve(import.meta.dirname, "..");
const leer = (pantalla: string) => readFileSync(path.join(RAIZ, `apps/web/app/(admin)/admin/${pantalla}/page.tsx`), "utf8");

/** Cada lugar donde se llama la acción, con el nombre de la función que lo contiene (la `function` más cercana hacia arriba). */
function llamadas(fuente: string, llamada: RegExp): { linea: number; dentroDe: string }[] {
  const lineas = fuente.split("\n");
  const salida: { linea: number; dentroDe: string }[] = [];
  let dentroDe = "(ninguna)";
  lineas.forEach((texto, i) => {
    const declara = texto.match(/^\s*(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s+(\w+)/);
    if (declara) dentroDe = declara[1];
    if (llamada.test(texto) && !declara) salida.push({ linea: i + 1, dentroDe });
  });
  return salida;
}

const CASOS = [
  { pantalla: "anuncios", accion: "Anular un comunicado", llamada: /\banular\(/ },
  { pantalla: "areas", accion: "Desactivar un área", llamada: /\bcambiarActiva\([^)]*,\s*false\)/ },
  { pantalla: "sedes", accion: "Desactivar una sede", llamada: /\bcambiarActiva\([^)]*,\s*false\)/ },
  { pantalla: "cuentas", accion: "Resetear una contraseña", llamada: /\baccion\([^)]*,\s*"resetear"\)/ },
];

describe("lo que no se deshace pregunta antes", () => {
  for (const { pantalla, accion, llamada } of CASOS) {
    it(`${accion} (${pantalla}) solo sale de su «Sí, …»`, () => {
      const fuente = leer(pantalla);
      const sitios = llamadas(fuente, llamada);
      // Que exista al menos una: si la acción se renombró, esta prueba ya no mira nada y tiene que decirlo.
      expect(sitios.length, `no encontré dónde se llama «${accion}» en ${pantalla}`).toBeGreaterThan(0);
      for (const s of sitios) {
        expect(s.dentroDe, `${pantalla}/page.tsx:${s.linea} llama «${accion}» fuera de una función confirmar…`).toMatch(/^confirmar/);
      }
    });

    it(`${accion} (${pantalla}) tiene su aviso con «Cancelar»`, () => {
      const fuente = leer(pantalla);
      expect(fuente).toMatch(/<Modal[\s\S]*?Cancelar[\s\S]*?<\/Modal>/);
      expect(fuente).toMatch(/onClick=\{\(\) => void confirmar\w+\(\)\}/);
    });
  }
});

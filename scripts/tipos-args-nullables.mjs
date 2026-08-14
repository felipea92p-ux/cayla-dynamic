#!/usr/bin/env node
// ============================================================================
// tipos-args-nullables.mjs — el parche que `supabase gen types` necesita
// ============================================================================
//
// QUÉ ARREGLA
//   `supabase gen types typescript` declara los parámetros de cada función así:
//
//       fn_set_fin_contrato: { Args: { p_persona_id: string; p_fecha: string } }
//
//   Y eso es FALSO para este esquema. `p_fecha` acepta NULL —vacío significa
//   «borra la fecha de fin de contrato», y la pantalla de Equipo manda null a
//   propósito— pero el tipo generado no lo permite. TypeScript no tiene forma de
//   expresar «obligatorio pero anulable» y el generador elige mal.
//
//   El resultado, medido el 2026-08-14: correr `gen-types` deja **63 errores de
//   tipos en diez pantallas**, y el repositorio deja de compilar. El comando que
//   el propio hook de pre-push recomienda rompía el build.
//
//   Hasta hoy se convivía con eso agregando las columnas y las funciones nuevas
//   A MANO al archivo generado —hay comentarios dentro que lo dicen— y no
//   corriendo nunca el generador. Eso funciona hasta que alguien lo corre.
//
// QUÉ HACE
//   Recorre los bloques `Args: { … }` de `Functions:` y le agrega `| null` a
//   cada parámetro que no lo tenga. Nada más: no toca `Row`, ni `Insert`, ni
//   `Update`, ni `Returns`, ni los enums.
//
// POR QUÉ TODOS Y NO UNA LISTA
//   Una lista de excepciones habría que mantenerla, y el día que se quede corta
//   vuelve el mismo problema con la forma de un descuido. Además el riesgo de
//   pasarse es bajo y del lado seguro: permitir null donde el SQL no lo acepta
//   solo mueve el rechazo de la compilación al servidor, que lo rechaza igual y
//   con un mensaje en castellano. Al revés —prohibirlo donde sí se acepta— es lo
//   que rompe el build hoy.
//
// CÓMO SE USA
//   No se llama a mano: `npx pnpm --filter @cayla-dynamic/database gen-types` lo
//   corre solo, después de generar.
// ============================================================================

import { readFileSync, writeFileSync } from "node:fs";

const ARCHIVO = process.argv[2] ?? "packages/database/src/types.ts";
const original = readFileSync(ARCHIVO, "utf8");

let parcheadas = 0;

// `Args: { … }` viene de DOS formas según cuántos parámetros tenga la función:
// en una línea (`Args: { p_id: string; p_fecha: string }`) o repartido en
// varias. El `[^{}]*` cubre las dos y a la vez garantiza que no se entra en un
// objeto anidado — hoy no los hay, y si algún día aparece uno, este parche
// simplemente no lo toca en vez de romperlo.
const nuevo = original.replace(/Args: \{([^{}]*)\}/g, (todo, dentro) => {
  const parcheado = dentro.replace(
    // nombre[?]: tipo — el tipo termina donde empieza el separador (`;`, coma,
    // salto de línea) o el cierre del objeto.
    /([A-Za-z_][A-Za-z0-9_]*)(\??): ([^;\n]+?)(?=\s*(?:;|\n|$))/g,
    (par, nombre, opcional, tipo) => {
      if (tipo.includes("| null")) return par;
      parcheadas++;
      return `${nombre}${opcional}: ${tipo} | null`;
    },
  );
  return `Args: {${parcheado}}`;
});

writeFileSync(ARCHIVO, nuevo, "utf8");
console.log(`tipos-args-nullables: ${parcheadas} parámetro(s) admiten null en ${ARCHIVO}`);

// ============================================================================
// sin-punto-medio.test.ts — Ningún texto que se ve separa datos con «·»
// ============================================================================
// Felipe, 2026-11-24 (en Retail; la tienda ya los quitó todos, cayla-retail#2021): el punto medio amontona
// datos distintos en una línea y no dice dónde termina uno y empieza el otro. No se cambia por otro signo
// («|», «—», «/»): cada dato va en su pieza. Dos partes de una frase, con coma o «y»; quién y cuándo, el
// nombre arriba y la fecha abajo en chico; un dato con su rótulo, «Rótulo: valor» o el rótulo arriba; varios
// valores sueltos, en chips. La decisión y el cómo: docs/adr/0007-sin-punto-medio.md.
//
// Se hace por módulos del menú, empezando por Asistencia como muestra. Por eso MODULOS es una lista que
// SOLO CRECE: el día que Felipe apruebe otro grupo se agregan sus rutas aquí y la prueba lo vigila desde ese
// commit. Quitar una ruta de la lista es apagar el freno para esa pantalla.
//
// Lo que mira es lo que el código DIBUJA o ESCRIBE: textos entre comillas, plantillas `…` y el texto suelto
// de JSX, leídos con el analizador de TypeScript (no con expresiones regulares). Los comentarios no cuentan:
// ahí el «·» no lo ve nadie. Si una línea de verdad necesita el signo —porque lee un dato que la base ya guarda
// así, por ejemplo—, se declara en esa línea o en la de arriba:
//     // punto-medio-permitido: <por qué>
// El motivo es obligatorio. Quedan fuera los papeles que se imprimen o descargan (constancias, boletas): no
// están en esta lista y se tratan aparte, porque son documentos.
// ============================================================================
import { describe, expect, it } from "vitest";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import ts from "typescript";

const RAIZ = path.resolve(__dirname, "..");
const WEB = "apps/web";
const ADMIN = `${WEB}/app/(admin)/admin`;

/** Un módulo del menú y todo lo que dibuja: sus carpetas de pantalla y lo que solo él usa. */
type Modulo = { nombre: string; desde: string; rutas: readonly string[] };

// SOLO CRECE. Una carpeta cubre todo lo que tiene adentro.
const MODULOS: readonly Modulo[] = [
  {
    nombre: "Asistencia",
    desde: "2026-11-27",
    rutas: [
      `${ADMIN}/incidencias`,
      `${ADMIN}/correcciones`,
      `${ADMIN}/turnos`,
      `${ADMIN}/disponibilidad`,
      `${ADMIN}/cambios-de-horario`,
      `${ADMIN}/horarios`,
      `${ADMIN}/horas`,
      `${ADMIN}/ausencias`,
      // Lo que solo usan estas pantallas (o que se cambió igual para todas las que lo usan).
      `${WEB}/components/incidencias`,
      `${WEB}/components/historial-horario`,
      `${WEB}/components/pedidos-turno`,
      `${WEB}/components/cambios-turno`,
      `${WEB}/components/disponibilidad`,
      `${WEB}/lib/admin/borrador-semana.ts`,
      `${WEB}/lib/admin/calendario-ausencias.ts`,
      `${WEB}/lib/admin/cobertura-tramos.ts`,
      `${WEB}/lib/admin/cobertura-turnos.ts`,
      `${WEB}/lib/admin/historial-correcciones.ts`,
      `${WEB}/lib/admin/incidencias.ts`,
      `${WEB}/lib/admin/marcaje-faltante.ts`,
      `${WEB}/lib/admin/prueba-en-feriado.ts`,
      `${WEB}/lib/admin/repeticion.ts`,
      `${WEB}/lib/admin/revision-turnos.ts`,
      `${WEB}/lib/admin/semana-persona.ts`,
      `${WEB}/lib/admin/sugerencia-entrada.ts`,
      `${WEB}/lib/admin/sugerencia-turnos.ts`,
      `${WEB}/lib/disponibilidad.ts`,
      `${WEB}/lib/historial-horario.ts`,
      // El sobretítulo de TODAS las pantallas del panel («Asistencia» y la fecha): compartido, y su cambio vale igual en todas.
      `${WEB}/lib/admin/sobretitulo.ts`,
      `${WEB}/components/vidrio/hora-lima.tsx`,
      // Cómo se nombra un campo del libro de correcciones (Correcciones, Cambios de horario y «Lo mío»).
      "packages/shared/src/auditoria.ts",
      // Cómo se nombra una sede («Tienda Arequipa»): lo usa todo el sistema, y el nombre es el mismo en todas partes.
      "packages/shared/src/sedes.ts",
    ],
  },
];

const PUNTO_MEDIO = /·|\\u00b7|\\xb7|&middot;|&#183;|&#xb7;/i;
const PERMISO = /punto-medio-permitido:\s*(\S.*)?$/;

function archivosDe(ruta: string): string[] {
  const absoluta = path.join(RAIZ, ruta);
  if (!statSync(absoluta).isDirectory()) return [ruta];
  return readdirSync(absoluta, { withFileTypes: true }).flatMap((e) => {
    if (e.name === "node_modules" || e.name === ".next") return [];
    const hija = `${ruta}/${e.name}`;
    if (e.isDirectory()) return archivosDe(hija);
    return /\.tsx?$/.test(e.name) && !/\.test\.tsx?$/.test(e.name) ? [hija] : [];
  });
}

const TEXTOS = new Set([
  ts.SyntaxKind.StringLiteral,
  ts.SyntaxKind.NoSubstitutionTemplateLiteral,
  ts.SyntaxKind.TemplateHead,
  ts.SyntaxKind.TemplateMiddle,
  ts.SyntaxKind.TemplateTail,
  ts.SyntaxKind.JsxText,
]);

/** Las líneas (desde 1) cuyo texto visible lleva un punto medio, sin las que lo declaran a propósito. */
function puntosVisibles(codigo: string, nombre = "x.tsx"): { linea: number; texto: string }[] {
  const fuente = ts.createSourceFile(nombre, codigo, ts.ScriptTarget.Latest, true, nombre.endsWith("x") ? ts.ScriptKind.TSX : ts.ScriptKind.TS);
  const lineas = codigo.split("\n");
  const halladas = new Set<number>();
  const visitar = (n: ts.Node) => {
    if (TEXTOS.has(n.kind)) {
      const crudo = n.getText(fuente);
      const m = PUNTO_MEDIO.exec(crudo);
      if (m) halladas.add(fuente.getLineAndCharacterOfPosition(n.getStart(fuente) + m.index).line + 1);
    }
    ts.forEachChild(n, visitar);
  };
  visitar(fuente);
  const permitida = (l: number) => [lineas[l - 1], lineas[l - 2] ?? ""].some((x) => PERMISO.test(x));
  return [...halladas]
    .sort((a, b) => a - b)
    .filter((l) => !permitida(l))
    .map((l) => ({ linea: l, texto: lineas[l - 1].trim() }));
}

describe("ningún texto que se ve separa datos con «·» (Felipe, 2026-11-24)", () => {
  for (const m of MODULOS) {
    const archivos = [...new Set(m.rutas.flatMap(archivosDe))];

    it(`${m.nombre}: ninguna pantalla lo dibuja`, () => {
      const conPunto = archivos.flatMap((a) =>
        puntosVisibles(readFileSync(path.join(RAIZ, a), "utf8"), a).map((p) => `${a}:${p.linea}  ${p.texto}`),
      );
      expect(conPunto, "Separa con piezas o con una frase («entró a las 9:12, 14 min tarde»), nunca con «·» ni con otro signo.").toEqual([]);
    });

    it(`${m.nombre}: todo lo que vigila existe (renombrar una carpeta no puede apagar el freno en silencio)`, () => {
      for (const r of m.rutas) expect(existsSync(path.join(RAIZ, r)), r).toBe(true);
      expect(archivos.length).toBeGreaterThan(m.rutas.length);
    });

    it(`${m.nombre}: cada excepción dice por qué`, () => {
      const sinMotivo = archivos.flatMap((a) =>
        readFileSync(path.join(RAIZ, a), "utf8")
          .split("\n")
          .flatMap((l, i) => {
            const p = PERMISO.exec(l);
            return p && !p[1] ? [`${a}:${i + 1}`] : [];
          }),
      );
      expect(sinMotivo).toEqual([]);
    });
  }

  // Un freno se prueba con lo que DEBE frenar, no solo con lo que debe dejar pasar.
  it("el detector caza el punto en JSX, en comillas, en plantillas y escrito como entidad o escape", () => {
    const codigo = [
      'const a = <p>{nombre} · {sede}</p>;',
      'const b = "se paga · ley";',
      'const c = `${x} · ${y}`;',
      'const d = <p>Hora &middot; 9:00</p>;',
      'const e = "a\\u00b7b";',
      'const f = <Campo etiqueta="Hora · según su horario" />;',
    ].join("\n");
    expect(puntosVisibles(codigo).map((p) => p.linea)).toEqual([1, 2, 3, 4, 5, 6]);
  });

  it("y deja pasar los comentarios y las líneas declaradas con su motivo", () => {
    const codigo = [
      "// «Asistencia · lunes»: así se veía antes",
      "/* a · b */",
      "const a = <p>{/* nombre · sede */}{nombre}</p>;",
      "// punto-medio-permitido: la base guarda «tipo · error» y aquí solo se lee",
      'const b = valor.split(" · ")[0];',
      'const c = "sin punto";',
    ].join("\n");
    expect(puntosVisibles(codigo)).toEqual([]);
  });
});

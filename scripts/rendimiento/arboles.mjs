#!/usr/bin/env node
/**
 * Escáner de ÁRBOLES DE DECISIÓN (skill `skill-analisis-arboles-decision`).
 *
 * QUÉ PROMETE. Por cada función de `apps/web/lib` (y donde se le indique) mide la forma de su lógica condicional y marca:
 *   · compleja     complejidad ciclomática (caminos independientes) por encima del umbral (por defecto 15);
 *   · profunda     anidamiento de control (if/for/while/switch/try dentro de otro) de 4 o más niveles;
 *   · escalera     una cadena `if / else if` de 5 o más eslabones → candidata a TABLA de decisión;
 *   · reevalua     la misma condición escrita dos o más veces en la misma función → calcularla una vez y nombrarla;
 *   · sin-guardas  función con CC ≥ 10 y ni una cláusula de guarda (`if (…) return`) en su primer nivel → falta poda anticipada;
 *   · else-sobra   un `else` después de un bloque que ya termina en return/throw → se puede aplanar;
 *   · ternario-anidado  `a ? b : c ? d : e`.
 *
 * QUÉ ASUME. Mide FORMA, no velocidad: con cuatro sedes y unas 30 personas, evaluar 40 reglas cuesta microsegundos. El valor de aplanar es que
 * el caso borde deje de esconderse (corrección y mantenimiento). Es AST, pero no sabe de negocio: un `escalera` puede ser legítimo.
 * NO ve las RPC de Postgres (donde vive el árbol real de la planilla): eso se audita leyendo `supabase/migrations/*.sql`.
 *
 * USO   node scripts/rendimiento/arboles.mjs [--dir apps/web/lib] [--archivo lib/x.ts] [--top 25] [--umbral 15] [--json] [--estricto]
 */
import { join, resolve } from "node:path";
import { RAIZ, WEB, cargarTS, leer, leerArgs, lineaDe, listarFuentes, parsear, rel, tabla } from "./comun.mjs";

export const UMBRALES = { cc: 15, profundidad: 4, escalera: 5, guardas: 10, repetida: 2 };

/** Texto normalizado (sin espacios) de una condición, para detectar repetidas. */
const normalizar = (t) => t.replace(/\s+/g, "");

/** Analiza un texto y devuelve una fila por función. Pura: sin disco. */
export function analizarTexto(texto, nombre = "x.ts", umbrales = UMBRALES) {
  const ts = cargarTS();
  const sf = parsear(texto, nombre);
  const K = ts.SyntaxKind;
  const filas = [];

  const esFuncion = (n) =>
    ts.isFunctionDeclaration(n) || ts.isMethodDeclaration(n) || ts.isArrowFunction(n) || ts.isFunctionExpression(n);

  const nombreDe = (n) => {
    if (n.name && ts.isIdentifier(n.name)) return n.name.text;
    const p = n.parent;
    if (p && ts.isVariableDeclaration(p) && ts.isIdentifier(p.name)) return p.name.text;
    if (p && ts.isPropertyAssignment(p) && ts.isIdentifier(p.name)) return p.name.text;
    return `(anónima L${lineaDe(sf, n)})`;
  };

  const terminaEnSalida = (stmt) => {
    if (!stmt) return false;
    if (ts.isReturnStatement(stmt) || ts.isThrowStatement(stmt)) return true;
    if (ts.isBlock(stmt) && stmt.statements.length) return terminaEnSalida(stmt.statements[stmt.statements.length - 1]);
    return false;
  };

  const medir = (fn) => {
    let cc = 1;
    let profMax = 0;
    let escaleraMax = 0;
    let elseSobra = 0;
    let ternAnidado = 0;
    const condiciones = new Map();

    const cuentaCondicion = (expr) => {
      const t = normalizar(expr.getText(sf));
      if (t.length < 12) return; // `a`, `!x`: demasiado corto para ser una regla repetida
      condiciones.set(t, (condiciones.get(t) ?? 0) + 1);
    };

    const visitar = (n, prof, dentroDeElseIf) => {
      // No bajamos a funciones anidadas: se miden por separado.
      if (n !== fn && esFuncion(n)) return;
      let profHijo = prof;
      switch (n.kind) {
        case K.IfStatement: {
          cc++;
          // Largo de la cadena solo si NO es un `else if` (se cuenta desde la cabeza).
          if (!dentroDeElseIf) {
            let largo = 1;
            let cur = n;
            while (cur.elseStatement && ts.isIfStatement(cur.elseStatement)) { largo++; cur = cur.elseStatement; }
            escaleraMax = Math.max(escaleraMax, largo);
          }
          cuentaCondicion(n.expression);
          if (n.elseStatement && terminaEnSalida(n.thenStatement)) elseSobra++;
          if (!dentroDeElseIf) profHijo = prof + 1; else profHijo = prof; // un `else if` no es un nivel más
          profMax = Math.max(profMax, profHijo);
          visitar(n.expression, profHijo, false);
          visitar(n.thenStatement, profHijo, false);
          if (n.elseStatement) visitar(n.elseStatement, prof, ts.isIfStatement(n.elseStatement));
          return;
        }
        case K.ForStatement: case K.ForInStatement: case K.ForOfStatement: case K.WhileStatement: case K.DoStatement:
          cc++; profHijo = prof + 1; profMax = Math.max(profMax, profHijo); break;
        case K.SwitchStatement: profHijo = prof + 1; profMax = Math.max(profMax, profHijo); break;
        case K.CaseClause: cc++; break;
        case K.TryStatement: profHijo = prof + 1; profMax = Math.max(profMax, profHijo); break;
        case K.CatchClause: cc++; break;
        case K.ConditionalExpression:
          cc++;
          if (ts.isConditionalExpression(n.whenFalse) || ts.isConditionalExpression(n.whenTrue)) ternAnidado++;
          cuentaCondicion(n.condition);
          break;
        case K.BinaryExpression: {
          const op = n.operatorToken.kind;
          if (op === K.AmpersandAmpersandToken || op === K.BarBarToken || op === K.QuestionQuestionToken) cc++;
          break;
        }
        default: break;
      }
      ts.forEachChild(n, (h) => visitar(h, profHijo, false));
    };
    ts.forEachChild(fn.body ?? fn, (h) => visitar(h, 0, false));

    // Guardas de primer nivel: `if (…) return/throw` directamente en el cuerpo de la función.
    let guardas = 0;
    if (fn.body && ts.isBlock(fn.body)) {
      for (const s of fn.body.statements) if (ts.isIfStatement(s) && !s.elseStatement && terminaEnSalida(s.thenStatement)) guardas++;
    }
    const repetidas = [...condiciones.entries()].filter(([, v]) => v >= umbrales.repetida).map(([k, v]) => ({ condicion: k.slice(0, 60), veces: v }));
    return { cc, profMax, escaleraMax, elseSobra, ternAnidado, guardas, repetidas };
  };

  const recorrer = (n) => {
    if (esFuncion(n) && (n.body ?? false)) {
      const m = medir(n);
      const banderas = [];
      if (m.cc >= umbrales.cc) banderas.push("compleja");
      if (m.profMax >= umbrales.profundidad) banderas.push("profunda");
      if (m.escaleraMax >= umbrales.escalera) banderas.push("escalera");
      if (m.repetidas.length) banderas.push("reevalua");
      // Solo si además hay anidamiento real: una lista plana de avisos independientes no necesita guardas (calibrado 2026-10-03: 153 → ruido).
      if (m.cc >= umbrales.guardas && m.guardas === 0 && m.profMax >= 3 && ts.isBlock(n.body)) banderas.push("sin-guardas");
      if (m.elseSobra >= 2) banderas.push("else-sobra");
      if (m.ternAnidado >= 3) banderas.push("ternario-anidado"); // 1–2 ternarios en cadena se leen bien; 3 o más no (calibrado 2026-10-03)
      if (banderas.length) {
        filas.push({
          funcion: nombreDe(n), linea: lineaDe(sf, n), cc: m.cc, profundidad: m.profMax, escalera: m.escaleraMax,
          guardas: m.guardas, repetidas: m.repetidas, banderas,
          // Puntaje: ordena por dolor de mantenimiento, no por tamaño.
          puntaje: m.cc + m.profMax * 4 + (m.escaleraMax >= umbrales.escalera ? m.escaleraMax : 0) + m.repetidas.length * 3 + banderas.length * 2,
        });
      }
    }
    ts.forEachChild(n, recorrer);
  };
  recorrer(sf);
  return filas;
}

export function escanear({ dir = join(WEB, "lib"), archivo = null, umbrales = UMBRALES } = {}) {
  const archivos = archivo ? [resolve(RAIZ, archivo.startsWith("lib/") ? `apps/web/${archivo}` : archivo)] : listarFuentes(dir);
  const todo = [];
  for (const f of archivos) for (const fila of analizarTexto(leer(f), f, umbrales)) todo.push({ archivo: rel(f), ...fila });
  return { archivosLeidos: archivos.length, hallazgos: todo.sort((a, b) => b.puntaje - a.puntaje) };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const a = leerArgs(process.argv.slice(2));
  const umbrales = { ...UMBRALES, ...(a.umbral ? { cc: Number(a.umbral) } : {}) };
  const r = escanear({ dir: a.dir ? resolve(RAIZ, a.dir) : undefined, archivo: a.archivo || null, umbrales });
  const top = Number(a.top ?? 25);
  if (a.json) console.log(JSON.stringify(r, null, 2));
  else {
    console.log(`Árboles de decisión — ${r.archivosLeidos} archivos, ${r.hallazgos.length} funciones con banderas (umbral CC ≥ ${umbrales.cc})\n`);
    console.log(tabla(["archivo:línea", "función", "CC", "prof", "escalera", "banderas"],
      r.hallazgos.slice(0, top).map((h) => [`${h.archivo}:${h.linea}`, h.funcion, h.cc, h.profundidad, h.escalera, h.banderas.join(", ")])));
  }
  if (a.estricto && r.hallazgos.length) process.exit(1);
}

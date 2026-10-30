#!/usr/bin/env bash
# Prueba de `receta-suelta.sh` contra un repositorio de mentira.
#
#   scripts/hooks/probar-receta-suelta.sh [ruta/a/receta-suelta.sh]
#
# POR QUÉ EXISTE. `lint-de-lo-nuevo.sh` se escribió CUATRO veces antes de
# funcionar, y las cuatro fallaba en silencio dando el push por bueno: una ruta
# de packages/ que hacía abortar a eslint, las rutas sin xargs, un corchete que
# es carácter de patrón, un echo que interpretaba los \n. Ninguna daba error;
# todas devolvían «todo bien». Un freno que no frena se ve idéntico a uno que
# funciona, así que este se prueba con lo que DEBE bloquear antes que con lo que
# debe pasar.
#
# Tres grupos de casos:
#   · BLOQUEA  — la receta suelta de cada una de las nueve familias, más las
#                formas en que llega (cadena en varias líneas, plantilla con
#                ${…}, en un archivo que ya existía, tras un apóstrofo suelto
#                que confunde al escáner).
#   · PASA     — el mismo código con el componente; una caja legítima que NO es
#                la receta (radio de 8 px, borde punteado, fondo hueso, tarjeta
#                que es un enlace, ventana flotante, papel impreso); comentarios;
#                lo excluido (components/ui, el terminal); la salida legítima
#                `receta-propia:`; y los pushes sin un .tsx.
#   · HUNK     — el que decide si el freno es vivible: una línea que YA tenía la
#                receta y solo cambió NO cuenta, pero una que se suma sí.
#
# Corre cada caso con CADA intérprete que haya (sh, bash de Apple 3.2, zsh, dash
# y la ruta directa por el shebang, que es como lo llama pre-push) y mira el
# código de salida, el mensaje, y que no salga ningún error del intérprete.
#
# No toca el repo real: todo ocurre en un directorio temporal, con la
# configuración global de git apagada (si no, el `core.hooksPath` de esta Mac
# dispararía el pre-push verdadero con cada push de la prueba).

set -u

AQUI="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${1:-$AQUI/receta-suelta.sh}"
[ -f "$SCRIPT" ] || { echo "No existe $SCRIPT" >&2; exit 2; }
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=prueba GIT_AUTHOR_EMAIL=prueba@example.invalid
export GIT_COMMITTER_NAME=prueba GIT_COMMITTER_EMAIL=prueba@example.invalid

BIEN=0
MAL=0

ADMIN="apps/web/app/(admin)/admin"

# ── Armado ───────────────────────────────────────────────────────────────────
# `origin/main` trae una pantalla vieja con UNA tarjeta a mano (línea 3), un
# componente de ui y el terminal. Es el árbol real en chiquito: deuda vieja que
# NO debe molestar a nadie.
montar() {
  rm -rf "$TMP/origin.git" "$TMP/work"
  git init -q --bare -b main "$TMP/origin.git"
  git init -q -b main "$TMP/work"
  (
    cd "$TMP/work" || exit 1
    git remote add origin "$TMP/origin.git"
    mkdir -p "$ADMIN/viejo" apps/web/components/ui "apps/web/app/(terminal)" supabase/migrations
    cat > "$ADMIN/viejo/page.tsx" <<'EOF'
export default function Viejo() {
  return (
    <div className="rounded-superficie border border-sand bg-papel p-4">
      <p>hola</p>
    </div>
  );
}
EOF
    echo "export const x = 1;" > apps/web/components/ui/cx.ts
    echo "x" > supabase/migrations/0001_base.sql
    git add -A
    git commit -q -m base
    git push -q origin main
    git checkout -q -b mia
  )
}

# escribir «ruta»  (el contenido llega por la entrada estándar)
escribir() {
  (
    cd "$TMP/work" || exit 1
    mkdir -p "$(dirname "$1")"
    cat > "$1"
  )
}

confirmar() {
  (
    cd "$TMP/work" || exit 1
    git add -A
    git commit -q --allow-empty -m "mia"
  )
}

# ── Ejecución y veredicto ────────────────────────────────────────────────────
correr() {
  SALIDA="$(cd "$TMP/work" && "$@" 2>&1)"
  CODIGO=$?
}

# evaluar «caso» «código esperado» «+texto que debe salir» «-texto que NO debe salir»…
# `printf '%s'` y no `echo`: la salida lleva barras invertidas que `echo` interpreta.
evaluar() {
  local caso="$1" esperado="$2" falla="" patron
  shift 2
  [ "$CODIGO" = "$esperado" ] || falla="$falla código $CODIGO (esperaba $esperado);"
  for patron in "$@"; do
    case "$patron" in
      +*) printf '%s' "$SALIDA" | grep -qF -- "${patron#+}" || falla="$falla falta «${patron#+}»;" ;;
      -*) if printf '%s' "$SALIDA" | grep -qF -- "${patron#-}"; then falla="$falla sobra «${patron#-}»;"; fi ;;
    esac
  done
  if printf '%s' "$SALIDA" | grep -qE 'invalid option|command not found|syntax error|bad substitution|unbound variable|not an identifier|Traceback|Error:'; then
    falla="$falla error del intérprete;"
  fi

  if [ -z "$falla" ]; then
    BIEN=$((BIEN + 1))
    printf '  \033[32m✓\033[0m %-56s %s\n' "$caso" "$INTERPRETE"
  else
    MAL=$((MAL + 1))
    printf '  \033[31m✗\033[0m %-56s %s\n' "$caso" "$INTERPRETE"
    printf '      %s\n' "$falla"
    printf '%s\n' "$SALIDA" | sed 's/^/      │ /'
  fi
}

# Corre el caso con cada intérprete. Lo armado en $TMP/work no se toca entre uno
# y otro: receta-suelta.sh solo lee.
con_cada_interprete() {
  local caso="$1" esperado="$2" i
  shift 2
  for i in $INTERPRETES; do
    INTERPRETE="$i"
    if [ "$i" = "directo" ]; then
      correr "$SCRIPT"
    else
      correr "$i" "$SCRIPT"
    fi
    evaluar "$caso" "$esperado" "$@"
  done
}

INTERPRETES="/bin/sh /bin/bash"
command -v zsh >/dev/null 2>&1 && INTERPRETES="$INTERPRETES zsh"
command -v dash >/dev/null 2>&1 && INTERPRETES="$INTERPRETES dash"
OTRO_BASH="$(command -v bash || true)"
if [ -n "$OTRO_BASH" ] && [ "$OTRO_BASH" != "/bin/bash" ]; then INTERPRETES="$INTERPRETES $OTRO_BASH"; fi
[ -x "$SCRIPT" ] && INTERPRETES="$INTERPRETES directo"

echo "Probando $SCRIPT"
echo "  python: $(python3 --version 2>&1)   bash de Apple: $(/bin/bash --version | head -1 | cut -c1-40)"

# ── 0 · Nada de bash 4+ (los comentarios se ignoran: este mismo archivo cita lo prohibido) ──
PROHIBIDO='declare -A|local -A|typeset -A|mapfile|readarray|\$\{[A-Za-z_]+(,,|\^\^)\}|\|&|&>>|coproc'
USOS="$(grep -vE '^[[:space:]]*#' "$SCRIPT" | grep -nE "$PROHIBIDO" || true)"
if [ -z "$USOS" ]; then
  BIEN=$((BIEN + 1))
  printf '  \033[32m✓\033[0m %s\n' "receta-suelta.sh no usa nada de bash 4+"
else
  MAL=$((MAL + 1))
  printf '  \033[31m✗\033[0m %s\n' "usa algo que el bash 3.2 de Apple no tiene:"
  printf '%s\n' "$USOS" | sed 's/^/      │ /'
fi

# ═════════════════════════════════════════════════════════════════════════════
echo
echo "── BLOQUEA ──"

# 1 · La tarjeta a mano en un archivo nuevo: el caso que motivó el freno.
montar
escribir "apps/web/components/educacion/barra.tsx" <<'EOF'
export function Barra() {
  return (
    <div id="mas-filtros" className="grid gap-3 rounded-superficie border border-sand bg-papel p-4 sm:grid-cols-2">
      <p>filtros</p>
    </div>
  );
}
EOF
confirmar
con_cada_interprete "tarjeta a mano (archivo nuevo)" 1 \
  "+Este push agrega la receta suelta" "+Tarjeta, vacío o tabla" "+barra.tsx:3" "+<TarjetaInfo>" "+receta-propia:"

# 2 · La misma, con la sintaxis vieja del radio (rounded-2xl).
montar
escribir "$ADMIN/nuevo/page.tsx" <<'EOF'
export default function Nuevo() {
  return <section className="mb-6 rounded-2xl border border-sand bg-papel p-5"><p>x</p></section>;
}
EOF
confirmar
con_cada_interprete "tarjeta con rounded-2xl" 1 "+nuevo/page.tsx:2" "+<TarjetaInfo>"

# 3 · «No hay nada» escrito como caja → <EstadoVacio>.
montar
escribir "$ADMIN/vacio/page.tsx" <<'EOF'
export default function Vacio() {
  return <p className="rounded-superficie border border-sand bg-papel px-4 py-6 text-sm text-taupe">No hay nada.</p>;
}
EOF
confirmar
con_cada_interprete "vacío a mano → EstadoVacio" 1 "+vacio/page.tsx:2" "+<EstadoVacio>"

# 4 · Tabla con su envoltorio a mano → <Tabla>.
montar
escribir "$ADMIN/tabla/page.tsx" <<'EOF'
export default function T() {
  return (
    <div className="overflow-x-auto rounded-superficie border border-sand bg-papel">
      <table className="w-full text-sm"></table>
    </div>
  );
}
EOF
confirmar
con_cada_interprete "envoltorio de tabla → Tabla" 1 "+tabla/page.tsx:3" "+<Tabla>"

# 5 · La cifra: un número en serif grande con tabular-nums.
montar
escribir "$ADMIN/cifras/page.tsx" <<'EOF'
export default function C({ n }: { n: number }) {
  return <span className="block font-serif text-2xl tabular-nums text-tinta">{n}</span>;
}
EOF
confirmar
con_cada_interprete "cifra con tabular-nums" 1 "+Cifra escrita a mano" "+cifras/page.tsx:2" "+<Cifra>"

# 6 · La cifra SIN tabular-nums, pero cuyo único hijo es una expresión.
montar
escribir "$ADMIN/cifras2/page.tsx" <<'EOF'
export default function C({ n }: { n: number }) {
  return <div className="font-serif text-2xl">{n}</div>;
}
EOF
confirmar
con_cada_interprete "cifra cuyo hijo es solo {expresión}" 1 "+Cifra escrita a mano" "+cifras2/page.tsx:2"

# 7 · El filtro: un <button> con aria-pressed (el atributo en OTRA línea que la etiqueta).
montar
escribir "$ADMIN/filtros/page.tsx" <<'EOF'
export default function F({ activo }: { activo: boolean }) {
  return (
    <button
      type="button"
      aria-pressed={activo}
      onClick={() => {}}
    >
      Todos
    </button>
  );
}
EOF
confirmar
con_cada_interprete "<button aria-pressed> (en otra línea)" 1 "+Filtro o pestaña escritos a mano" "+filtros/page.tsx:5"

# 8 · El filtro por su receta visual: tinta/crema en un ternario, sin aria-pressed.
montar
escribir "$ADMIN/filtros2/page.tsx" <<'EOF'
export default function F({ activo }: { activo: boolean }) {
  return (
    <button type="button" className={`rounded-full border px-3 py-1 text-xs ${activo ? "border-tinta bg-tinta text-crema" : "border-sand"}`}>
      Hoy
    </button>
  );
}
EOF
confirmar
con_cada_interprete "<button> que se enciende con tinta/crema" 1 "+Filtro o pestaña escritos a mano" "+filtros2/page.tsx:3" "+<Filtro>"

# 9 · El aviso a mano.
montar
escribir "$ADMIN/aviso/page.tsx" <<'EOF'
export default function A() {
  return <div className="mb-4 rounded-control border border-ambar/40 bg-ambar/10 px-4 py-3 text-sm">Ojo.</div>;
}
EOF
confirmar
con_cada_interprete "aviso a mano (borde y fondo ámbar)" 1 "+Aviso escrito a mano" "+aviso/page.tsx:2" "+<BannerAviso>"

# 10 · El rótulo con la clase .etiqueta.
montar
escribir "$ADMIN/rotulo/page.tsx" <<'EOF'
export default function R() {
  return <p className="etiqueta mb-2 text-taupe">Acciones</p>;
}
EOF
confirmar
con_cada_interprete "rótulo con la clase etiqueta" 1 "+Rótulo escrito con la clase .etiqueta" "+rotulo/page.tsx:2"

# 11 · El título de pantalla.
montar
escribir "$ADMIN/titulo/page.tsx" <<'EOF'
export default function T() {
  return (
    <div>
      <h1 className="mb-1 font-serif text-2xl">Titulo</h1>
    </div>
  );
}
EOF
confirmar
con_cada_interprete "<h1 font-serif> en una pantalla de admin" 1 "+Título de pantalla escrito a mano" "+titulo/page.tsx:4" "+<CabeceraPagina>"

# 12 · El encabezado de tabla, las franjas y la fila a mano.
montar
escribir "$ADMIN/filas/page.tsx" <<'EOF'
export default function T() {
  return (
    <table>
      <thead className="bg-sand/70 text-left"><tr><th>a</th></tr></thead>
      <tbody>
        <tr className="border-t border-sand even:bg-hueso/50"><td>1</td></tr>
      </tbody>
    </table>
  );
}
EOF
confirmar
con_cada_interprete "thead bg-sand/70, franjas y fila a mano" 1 \
  "+Fila o encabezado de tabla" "+filas/page.tsx:4" "+filas/page.tsx:6" "+<TablaEncabezado>" "+sin franjas"

# 13 · El estado de carga como texto.
montar
escribir "$ADMIN/carga/page.tsx" <<'EOF'
export default function C() {
  return <main className="p-6"><p className="text-sm text-taupe">Cargando…</p></main>;
}
EOF
confirmar
con_cada_interprete "«Cargando…» como texto de un elemento" 1 "+Estado de carga escrito a mano" "+carga/page.tsx:2" "+<Cargando />"

# 14 · El cajón por la derecha.
montar
escribir "$ADMIN/cajon/page.tsx" <<'EOF'
export default function C() {
  return (
    <aside className="fixed inset-y-0 right-0 z-50 w-full max-w-[460px] border-l border-sand bg-crema">x</aside>
  );
}
EOF
confirmar
con_cada_interprete "cajón fixed inset-y-0 right-0" 1 "+Cajón lateral escrito a mano" "+cajon/page.tsx:3" "+<Drawer>"

# 15 · La cadena repartida en varias líneas de un cx(): lo que un grep por línea no ve.
montar
escribir "$ADMIN/cx/page.tsx" <<'EOF'
import { cx } from "@/components/ui/cx";
export default function C({ x }: { x: boolean }) {
  return (
    <div
      className={cx(
        "rounded-superficie border border-sand bg-papel p-4",
        x && "mb-4",
      )}
    >
      hola
    </div>
  );
}
EOF
confirmar
con_cada_interprete "receta dentro de un cx() de varias líneas" 1 "+cx/page.tsx:6"

# 16 · La plantilla con ${…} y una cadena anidada.
montar
escribir "$ADMIN/plantilla/page.tsx" <<'EOF'
export default function P({ x }: { x: boolean }) {
  return <div className={`mb-4 rounded-2xl border border-sand bg-papel p-5 ${x ? "opacity-50" : ""}`}>hola</div>;
}
EOF
confirmar
con_cada_interprete "receta dentro de una plantilla con \${…}" 1 "+plantilla/page.tsx:2"

# 17 · Un apóstrofo suelto en texto JSX no debe cegar al escáner para lo que viene después.
montar
escribir "$ADMIN/apostrofo/page.tsx" <<'EOF'
export default function A() {
  return (
    <div>
      <p>Esto no es l'equipo ni d'otro lado</p>
      <div className="mb-4 rounded-superficie border border-sand bg-papel p-4">x</div>
    </div>
  );
}
EOF
confirmar
con_cada_interprete "tarjeta tras un apóstrofo suelto en el texto" 1 "+apostrofo/page.tsx:5"

# 18 · Una tarjeta NUEVA en un archivo que ya tenía una vieja: se cita la nueva, no la vieja.
montar
cat >> "$TMP/work/$ADMIN/viejo/page.tsx" <<'EOF'
export function Otra() {
  return <section className="mt-4 rounded-superficie border border-sand bg-papel p-5">otra</section>;
}
EOF
confirmar
con_cada_interprete "una tarjeta más en un archivo viejo" 1 "+viejo/page.tsx:9" "-viejo/page.tsx:3  →"

# ═════════════════════════════════════════════════════════════════════════════
echo
echo "── PASA ──"

# 19 · El mismo código usando los componentes.
montar
escribir "$ADMIN/limpio/page.tsx" <<'EOF'
import { TarjetaInfo, Cifra, Filtro, BannerAviso, Rotulo, RotuloEstado, EstadoVacio, CabeceraPagina, Tabla, Drawer } from "@/components/ui";
import { Cargando } from "@/components/cargando";
export default function Limpio({ activo }: { activo: boolean }) {
  return (
    <>
      <CabeceraPagina titulo="Limpio" />
      <TarjetaInfo titulo="Resumen"><Cifra etiqueta="Gente" valor={3} /></TarjetaInfo>
      <Filtro activo={activo} onClick={() => {}}>Hoy</Filtro>
      <BannerAviso variante="advertencia" enLinea>Ojo.</BannerAviso>
      <Rotulo>Acciones</Rotulo>
      <RotuloEstado tono="alerta">Críticas</RotuloEstado>
      <EstadoVacio>Nada.</EstadoVacio>
      <Tabla><tbody /></Tabla>
      <Cargando />
      <Drawer abierto onCerrar={() => {}} volverElFocoA={{ current: null }}>x</Drawer>
    </>
  );
}
EOF
confirmar
con_cada_interprete "el mismo código, con los componentes" 0 "-Este push agrega" "-✗"

# 20 · Cajas legítimas que NO son la receta: tienen que pasar.
montar
escribir "$ADMIN/legitimas/page.tsx" <<'EOF'
import Link from "next/link";
export default function L({ inicial, n }: { inicial: string; n: number }) {
  return (
    <>
      <div className="rounded-control border border-sand bg-papel px-3 py-2">radio de 8 px: una caja chica, no una tarjeta</div>
      <div className="rounded-superficie border border-dashed border-sand p-6">zona para soltar archivos</div>
      <div className="rounded-superficie border border-sand bg-hueso p-4">panel hundido dentro de una tarjeta</div>
      <div className="fixed z-40 w-[300px] rounded-superficie border border-sand bg-papel p-3 shadow-lg">ventana flotante</div>
      <div className="rounded-2xl border border-sand bg-papel p-6 print:rounded-none print:border-0 print:p-0">papel que se imprime</div>
      <Link href="/x" className="block rounded-superficie border border-sand bg-papel p-4 hover:bg-hueso">tarjeta que es un enlace</Link>
      <p className="font-serif text-3xl leading-none">Dynamic</p>
      <span className="flex h-full w-full items-center justify-center bg-sand font-serif text-2xl text-taupe">{inicial}</span>
      <span className="inline-flex rounded-full border border-ambar/40 bg-ambar/10 px-2 py-0.5 text-xs">insignia</span>
      <button className="rounded-control bg-tinta px-4 py-2 text-crema">Guardar (botón primario, no se enciende)</button>
      <Campo etiqueta="Nombre" />
      <p>{n > 0 ? "Cargando…" : "—"}</p>
      <h2 className="font-serif text-2xl">Un h2 no es el título de la pantalla</h2>
    </>
  );
}
EOF
confirmar
con_cada_interprete "cajas legítimas fuera de la receta" 0 "-Este push agrega" "-✗"

# 21 · La receta dentro de comentarios: el CLAUDE.md y los componentes la citan para explicarla.
montar
escribir "$ADMIN/comentada/page.tsx" <<'EOF'
// El envoltorio "rounded-superficie border border-sand bg-papel p-4" es <TarjetaInfo>.
/* font-serif text-2xl tabular-nums era la cifra a mano */
export default function C() {
  return (
    <div>
      {/* <p className="etiqueta mb-2 text-taupe">Acciones</p> */}
      {/*
        <div className="rounded-superficie border border-sand bg-papel p-4">viejo</div>
      */}
      <p>hola</p>
    </div>
  );
}
EOF
confirmar
con_cada_interprete "la receta citada en comentarios" 0 "-Este push agrega" "-✗"

# 22 · components/ui y el terminal son la casa de las recetas, no su infracción.
montar
escribir "apps/web/components/ui/tarjeta-nueva.tsx" <<'EOF'
export function Nueva() { return <div className="rounded-superficie border border-sand bg-papel p-4">x</div>; }
EOF
escribir "apps/web/app/(terminal)/terminal/page.tsx" <<'EOF'
export default function T() { return <p className="etiqueta mb-2 text-taupe">Entrada</p>; }
EOF
confirmar
con_cada_interprete "components/ui y (terminal) quedan fuera" 0 "-Este push agrega" "-✗"

# 23 · La salida legítima, con motivo, en la línea de arriba.
montar
escribir "$ADMIN/detalles/page.tsx" <<'EOF'
export default function D() {
  return (
    // receta-propia: es un <details> y TarjetaInfo no puede serlo
    <details className="mb-5 rounded-2xl border border-sand bg-papel p-4">x</details>
  );
}
EOF
confirmar
con_cada_interprete "receta-propia: con motivo, arriba" 0 "-Este push agrega" "-✗"

# 24 · Con el motivo en la misma línea (comentario JSX al final).
montar
escribir "$ADMIN/detalles2/page.tsx" <<'EOF'
export default function D() {
  return <details className="rounded-2xl border border-sand bg-papel p-4">{/* receta-propia: acordeón nativo, otra pieza */}x</details>;
}
EOF
confirmar
con_cada_interprete "receta-propia: con motivo, en la misma línea" 0 "-Este push agrega" "-✗"

# 25 · Sin motivo de verdad, la salida no vale: sigue bloqueando.
montar
escribir "$ADMIN/sinmotivo/page.tsx" <<'EOF'
export default function D() {
  return (
    // receta-propia: x
    <details className="mb-5 rounded-2xl border border-sand bg-papel p-4">x</details>
  );
}
EOF
confirmar
con_cada_interprete "receta-propia: sin motivo NO vale" 1 "+sinmotivo/page.tsx:4"

# 26 · Un push sin ningún .tsx (aquí, puro SQL): sale callado.
montar
escribir "supabase/migrations/0002_nueva.sql" <<'EOF'
select 1;
EOF
confirmar
con_cada_interprete "un push de puro SQL" 0 "-Este push agrega" "-✗" "-Python"

# 27 · La receta en un .ts o fuera de apps/web: no es de este freno.
montar
escribir "apps/web/lib/clases.ts" <<'EOF'
export const TARJETA = "rounded-superficie border border-sand bg-papel p-4";
EOF
escribir "packages/shared/src/x.tsx" <<'EOF'
export const X = () => <div className="rounded-superficie border border-sand bg-papel p-4">x</div>;
EOF
confirmar
con_cada_interprete "un .ts y un archivo fuera de apps/web" 0 "-Este push agrega" "-✗"

# 28 · Un documento (clase `hoja`): su tipografía de papel no es la del panel.
montar
escribir "apps/web/components/documento-nuevo.tsx" <<'EOF'
export function Doc({ nombre }: { nombre: string }) {
  return (
    <div className="hoja text-tinta">
      <p className="etiqueta text-taupe">Constancia</p>
      <p className="font-serif text-2xl">{nombre}</p>
    </div>
  );
}
EOF
confirmar
con_cada_interprete "un documento con la clase hoja" 0 "-Este push agrega" "-✗"

# 29 · El <h1> de un login, de una pantalla de Lo mío y de un papel impreso: no son el título del panel.
montar
escribir "$ADMIN/login/page.tsx" <<'EOF'
export default function L() { return <h1 className="font-serif text-3xl leading-none">Dynamic</h1>; }
EOF
escribir "apps/web/app/(mio)/mio/otra/page.tsx" <<'EOF'
export default function L() { return <h1 className="mt-3 font-serif text-2xl">Bandeja</h1>; }
EOF
escribir "$ADMIN/normas/imprimir/page.tsx" <<'EOF'
export default function L() { return <h1 className="mt-2 font-serif text-2xl text-tinta">Norma</h1>; }
EOF
confirmar
con_cada_interprete "<h1> de login, Lo mío e imprimir" 0 "-Este push agrega" "-✗"

# ═════════════════════════════════════════════════════════════════════════════
echo
echo "── HUNK: solo cuenta lo que se SUMA ──"

# 30 · Un hotfix que toca el className de una tarjeta vieja (p-4 → p-5): no es una tarjeta nueva.
montar
(cd "$TMP/work" && sed -i.bak 's/bg-papel p-4/bg-papel p-5/' "$ADMIN/viejo/page.tsx" && rm "$ADMIN/viejo/page.tsx.bak")
confirmar
con_cada_interprete "tocar una tarjeta vieja (p-4 → p-5)" 0 "-Este push agrega" "-✗"

# 31 · Un hotfix en OTRA línea del archivo que tiene la tarjeta vieja.
montar
(cd "$TMP/work" && sed -i.bak 's/<p>hola<\/p>/<p>hola, mundo<\/p>/' "$ADMIN/viejo/page.tsx" && rm "$ADMIN/viejo/page.tsx.bak")
confirmar
con_cada_interprete "tocar otra línea del archivo viejo" 0 "-Este push agrega" "-✗"

# 32 · Tocar la tarjeta vieja Y sumar una igual en otra parte: sale una de más, y se cita la nueva.
montar
(cd "$TMP/work" && sed -i.bak 's/bg-papel p-4/bg-papel p-5/' "$ADMIN/viejo/page.tsx" && rm "$ADMIN/viejo/page.tsx.bak")
cat >> "$TMP/work/$ADMIN/viejo/page.tsx" <<'EOF'
export function Otra() {
  return <section className="mt-4 rounded-superficie border border-sand bg-papel p-5">otra</section>;
}
EOF
confirmar
con_cada_interprete "tocar la vieja y sumar una nueva" 1 "+viejo/page.tsx:9" "-viejo/page.tsx:3  →"

# 33 · Mover la pantalla de sitio sin tocarla: git ve un renombrado, no una tarjeta nueva.
montar
(cd "$TMP/work" && mkdir -p "$ADMIN/viejo-movido" && git mv "$ADMIN/viejo/page.tsx" "$ADMIN/viejo-movido/page.tsx")
confirmar
con_cada_interprete "renombrar un archivo con una receta vieja" 0 "-Este push agrega" "-✗"

# 34 · Quitar una tarjeta vieja y no sumar nada.
montar
escribir "$ADMIN/viejo/page.tsx" <<'EOF'
export default function Viejo() {
  return (
    <div>
      <p>hola</p>
    </div>
  );
}
EOF
confirmar
con_cada_interprete "migrar una tarjeta vieja (quitarla)" 0 "-Este push agrega" "-✗"

# ═════════════════════════════════════════════════════════════════════════════
echo
echo "── ENTORNO ──"

# 35 · Sin Python 3, el freno lo DICE y deja pasar: no bloquea por lo que tenga instalado la máquina.
montar
escribir "$ADMIN/nuevo/page.tsx" <<'EOF'
export default function Nuevo() {
  return <section className="mb-6 rounded-2xl border border-sand bg-papel p-5"><p>x</p></section>;
}
EOF
confirmar
SINPY="$TMP/sinpython"
mkdir -p "$SINPY"
for b in git grep dirname sh; do ln -sf "$(command -v "$b")" "$SINPY/$b"; done
SALIDA="$(cd "$TMP/work" && PATH="$SINPY" /bin/sh "$SCRIPT" 2>&1)"; CODIGO=$?
INTERPRETE="sin python"
evaluar "sin Python 3: lo dice y deja pasar" 0 "+este push NO se revisó" "-Este push agrega"

# 36 · Sin origin/main (un clon recién hecho, otra rama): no hay con qué comparar y no frena.
montar
escribir "$ADMIN/nuevo/page.tsx" <<'EOF'
export default function Nuevo() {
  return <section className="mb-6 rounded-2xl border border-sand bg-papel p-5"><p>x</p></section>;
}
EOF
confirmar
for i in $INTERPRETES; do
  INTERPRETE="$i"
  if [ "$i" = "directo" ]; then correr env LINT_BASE=no-existe "$SCRIPT"; else correr env LINT_BASE=no-existe "$i" "$SCRIPT"; fi
  evaluar "sin base con la que comparar" 0 "-Este push agrega"
done

echo
if [ "$MAL" -eq 0 ]; then
  printf '\033[32m%s bien, ninguna mal.\033[0m\n' "$BIEN"
  exit 0
fi
printf '\033[31m%s bien, %s mal.\033[0m\n' "$BIEN" "$MAL"
exit 1

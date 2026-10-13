#!/usr/bin/env bash
# Mediciones de solo lectura para /revision-dynamic. No escribe nada, no toca la base.
# Se corre desde la raíz del repo o desde cualquier worktree:  bash .claude/skills/revision-dynamic/medir.sh
#
# Existe para que los números de un informe se puedan reproducir. El 2026-10-13 una
# primera pasada dijo «7 de 151 archivos con foco visible» y «16 archivos con color
# suelto»: las dos cifras eran falsas (hay un :focus-visible global, y los 16 eran
# velos de modal intencionales). Por eso cada cifra lleva al lado QUÉ NO CUENTA.
set -u
RAIZ="$(git rev-parse --show-toplevel)"
cd "$RAIZ/apps/web" || exit 1
TSX=(--include='*.tsx')
PAGES=$(find app -name page.tsx)
NP=$(echo "$PAGES" | wc -l | tr -d ' ')

echo "## 1. Superficies (pantallas = page.tsx)"
for g in '(admin)' '(mio)' '(terminal)'; do
  printf '%-12s pages=%-3s loading.tsx=%-2s error.tsx=%s\n' "$g" \
    "$(find "app/$g" -name page.tsx | wc -l | tr -d ' ')" \
    "$(find "app/$g" -name loading.tsx | wc -l | tr -d ' ')" \
    "$(find "app/$g" -name error.tsx | wc -l | tr -d ' ')"
done
echo "raíz: loading.tsx=$(ls app/loading.tsx 2>/dev/null | wc -l | tr -d ' ') error.tsx=$(ls app/error.tsx 2>/dev/null | wc -l | tr -d ' ') global-error=$(ls app/global-error.tsx 2>/dev/null | wc -l | tr -d ' ')"

echo; echo "## 2. Rendimiento estructural"
echo "pages con 'use client':        $(grep -lE "^.use client" $PAGES | wc -l | tr -d ' ') de $NP"
echo "pages con useEffect:           $(grep -l 'useEffect' $PAGES | wc -l | tr -d ' ') de $NP   (aprox. de «piden datos en el cliente»; confirmar con supabase.rpc/from dentro)"
echo "next/dynamic o lazy():         $(grep -rlE 'next/dynamic|React\.lazy|[^a-zA-Z]lazy\(' app components "${TSX[@]}" | wc -l | tr -d ' ')"
echo "Suspense:                      $(grep -rl 'Suspense' app components "${TSX[@]}" | wc -l | tr -d ' ')"
echo "setInterval/channel (sondeo):  $(grep -rlE 'setInterval|\.channel\(' app lib components --include='*.ts' "${TSX[@]}" | wc -l | tr -d ' ') archivos; realtime(.channel)=$(grep -rl '\.channel(' app lib components --include='*.ts' "${TSX[@]}" | wc -l | tr -d ' ')"
echo "pausa con pestaña oculta:      $(grep -rlE 'visibilityState|document\.hidden' app lib components --include='*.ts' "${TSX[@]}" | wc -l | tr -d ' ') archivos"
echo "las 12 pages más largas (líneas):"
find app -name page.tsx -exec wc -l {} + | grep -v ' total$' | sort -rn | head -12 | sed 's/^/  /'
echo "NO MIDE: peso real del bundle ni LCP. Eso exige 'next build' (First Load JS por ruta) y navegador."

echo; echo "## 3. Estética — adopción del sistema de diseño"
echo "archivos que importan cada primitivo:"
for p in boton tabla insignia area-texto modal cabecera-pagina campo drawer hoja-inferior banner-aviso; do
  printf '  %-16s %s\n' "$p" "$(grep -rlE "components/ui/$p" app components lib | wc -l | tr -d ' ')"
done
echo "botones: <Boton>=$(grep -rE '<Boton\b' app components "${TSX[@]}" | wc -l | tr -d ' ') (con cargando=$(grep -rE 'cargando=' app components "${TSX[@]}" | wc -l | tr -d ' ')) vs <button> crudos=$(grep -rE '<button\b' app components "${TSX[@]}" | wc -l | tr -d ' ')  (crudos legítimos: íconos, pestañas, filas clicables; revisar solo los de acción primaria)"
echo "colores Tailwind por defecto (SIN contar: bg-black/NN = velo de modal; print:bg-white = papel impreso; líneas de comentario):"
grep -rnE '\b(bg|text|border|ring|from|to)-(white|black|slate|gray|zinc|neutral|stone|amber|red|green|blue|yellow|emerald|rose|sky|indigo|violet|orange)(-[0-9]+)?(/[0-9]+)?\b' app components "${TSX[@]}" \
  | grep -vE 'bg-black/[0-9]+|print:(bg|text|border)-(white|black)' | grep -vE ':[0-9]+:\s*(\{?/\*|//|\*)' | cut -c1-120 | sed 's/^/  /'
echo "  (esperado: solo FirmaEditor.tsx = vista previa de firma, excepción documentada en CLAUDE.md)"
echo "hex sueltos en tsx: $(grep -rlE '#[0-9a-fA-F]{6}\b' app components "${TSX[@]}" | wc -l | tr -d ' ') archivos"
echo "radios en uso (rounded-lg = control y rounded-2xl = superficie son el MISMO valor con otro nombre):"
for r in rounded-control rounded-superficie rounded-flotante rounded-pildora rounded-lg rounded-2xl rounded-xl rounded-md rounded-full; do
  printf '  %-18s %s\n' "$r" "$(grep -rhoE "\b$r\b" app components "${TSX[@]}" | wc -l | tr -d ' ')"
done
echo "  fuera de escala de verdad (xl=12px, md=6px): revisar si son intencionales"
echo "z-index en uso:"; grep -rhoE 'z-(\[[0-9]+\]|[0-9]+)' app components "${TSX[@]}" | sort | uniq -c | sort -rn | sed 's/^/  /'
echo "tokens --color-* definidos en @theme: $(awk '/@theme/{f=1} f&&/--color-/{n++} /^}/{if(f){exit}} END{print n+0}' app/globals.css)  (CLAUDE.md dice trece; el catorceavo es el alias --color-borde-control, no un color nuevo)"
echo "foco global: $(grep -c ':focus-visible {' app/globals.css) regla(s) en globals.css  → NO contar focus-visible por archivo"

echo; echo "## 4. Dinamismo y feedback"
echo "@keyframes en globals.css:  $(grep -c '@keyframes' app/globals.css)"
echo "prefers-reduced-motion:     css=$(grep -c 'prefers-reduced-motion' app/globals.css)  tsx=$(grep -rlE 'motion-reduce|prefers-reduced-motion' app components "${TSX[@]}" | wc -l | tr -d ' ') archivos"
echo "archivos con transition:    $(grep -rl 'transition' app components "${TSX[@]}" | wc -l | tr -d ' ')"
echo "useOptimistic/useTransition: $(grep -rlE 'useOptimistic|useTransition|startTransition' app components "${TSX[@]}" | wc -l | tr -d ' ')"
echo "hooks de movimiento propios: $(ls lib/use-salida-animada.ts lib/use-tema.ts 2>/dev/null | wc -l | tr -d ' ') (use-salida-animada, use-tema)"

echo; echo "## 5. Intuitivo y accesible"
echo "archivos con aria-:         $(grep -rl 'aria-' app components "${TSX[@]}" | wc -l | tr -d ' ') de $(find app components -name '*.tsx' | wc -l | tr -d ' ') tsx"
echo "archivos responsivos (sm|md|lg:): $(grep -rlE '\b(sm|md|lg):' app components "${TSX[@]}" | wc -l | tr -d ' ')"
echo "<img> sin next/image:       $(grep -rn '<img' app components "${TSX[@]}" | wc -l | tr -d ' ') usos (firmas/DNI/vistas de blob: next/image NO aplica, no es hallazgo)"
echo "grupos de menú / ítems:     $(grep -cE '^\s*\{ label:|label:' 'app/(admin)/admin/nav-items.ts') líneas con label en nav-items.ts"

echo; echo "## 6. Herramientas de medición que NO existen hoy (hueco, no hallazgo de pantalla)"
for t in playwright axe-core lighthouse bundle-analyzer web-vitals; do
  printf '  %-16s %s\n' "$t" "$(grep -lE "\"[^\"]*$t[^\"]*\"" package.json ../../package.json 2>/dev/null | wc -l | tr -d ' ') menciones en package.json"
done
echo "  vitest: $(find ../../tests -name '*.test.ts*' 2>/dev/null | wc -l | tr -d ' ') archivos de prueba en tests/ (entorno node: no hay prueba de interfaz en navegador)"

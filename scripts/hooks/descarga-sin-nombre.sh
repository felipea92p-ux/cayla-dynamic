#!/bin/sh
# Una pantalla que imprime/descarga un PDF sin fijar el nombre del documento.
#
# POR QUÉ EXISTE
#
# El nombre con el que el navegador sugiere guardar un PDF es el título del
# documento (document.title) EN EL MOMENTO de imprimir. Sin fijarlo, cualquier
# pantalla que llama a window.print() se guarda como «Dynamic — CAYLA» —el
# título fijo del sitio, igual para cualquier persona y cualquier papel. Ya
# existe useTituloDocumento() (apps/web/lib/admin/use-titulo-documento.ts) para
# esto exacto, decidido con Felipe el 2026-07-28 tras ver que todas sus
# boletas se guardaban con el mismo nombre.
#
# El 2026-09-10 apareció el mismo bug en Liquidaciones: sus tres papeles
# —liquidación, certificado de trabajo, constancia de cese— llevaban meses sin
# el hook. Son justo los documentos que se entregan a alguien que ya se fue de
# la empresa, y confundir el de una persona con el de otra al entregarlos no
# es un detalle cosmético. La pantalla es más nueva que la convención: quien la
# escribió no tenía forma de saber que el patrón existía, salvo por memoria.
#
# Es la misma historia que ya escribió DOS veces este archivo de hooks:
# `rol === "admin"` suelto y "America/Lima" suelto también estaban en
# CLAUDE.md antes de tener guardián, y la auditoría de agosto igual encontró
# 10 y 3 copias sueltas respectivamente. Un documento es memoria; con varias
# sesiones trabajando en paralelo, la memoria dura lo que dura una tarde.
#
# POR QUÉ MIRA EL ARCHIVO ENTERO, Y NO SOLO LO QUE EL PUSH AGREGA LÍNEA POR
# LÍNEA (a diferencia de reglas-de-la-casa.sh). Lo que hay que comprobar acá
# —¿este archivo llama a window.print() sin tener useTituloDocumento() en
# algún lado?— es una propiedad del ARCHIVO, no de una línea: el hook puede
# vivir a cientos de líneas de la llamada a imprimir. Mirar solo el diff de
# líneas dejaría pasar el caso real: alguien agrega una pantalla nueva entera,
# y "agregar una pantalla entera" son puras líneas `+`, así que igual se vería
# completo ahí — pero si alguien SOLO le agrega un botón de imprimir a una
# pantalla ya existente, el diff de líneas no alcanzaría a ver si el resto del
# archivo ya tenía el hook o no. Por eso este freno toma la lista de archivos
# que el push TOCA (nuevos o modificados, no borrados) y lee cada uno ENTERO
# en la versión que se empuja (`git show HEAD:archivo`), nunca del disco.
#
# SOLO LOS ARCHIVOS QUE EL PUSH TOCA, y esa es la razón de que sirva: hoy
# (2026-09-10, ya con Liquidaciones arreglada) no queda ningún archivo del
# repositorio con este defecto, así que partir de todo el árbol o solo de lo
# que cambia da el mismo resultado ahora — pero si alguna vez vuelve a quedar
# deuda vieja sin tocar, escanear el repo entero fallaría en TODOS los push
# sin relación, y un freno que chilla siempre se desactiva a la semana.
#
# BLOQUEA, no avisa: habla de lo que SALE hacia GitHub, no de lo que hay a
# medio escribir en el disco.
#
# Para saltarlo en una urgencia real:  git push --no-verify

BASE="${LINT_BASE:-origin/main}"
git rev-parse --verify --quiet "$BASE" >/dev/null 2>&1 || exit 0

RAIZ=$(git rev-parse --show-toplevel)
cd "$RAIZ" || exit 0

ARCHIVOS=$(git diff --name-only --diff-filter=d "$BASE...HEAD" -- '*.tsx' '*.ts' 2>/dev/null)
[ -z "$ARCHIVOS" ] && exit 0

HALLAZGOS=$(printf '%s\n' "$ARCHIVOS" | while IFS= read -r archivo; do
  [ -z "$archivo" ] && continue
  # El propio hook: su comentario explica window.print() en prosa sin llamarlo,
  # y no tiene sentido exigirle que se use a sí mismo.
  [ "$archivo" = "apps/web/lib/admin/use-titulo-documento.ts" ] && continue

  CONTENIDO=$(git show "HEAD:$archivo" 2>/dev/null) || continue
  printf '%s\n' "$CONTENIDO" | grep -q 'window\.print(' || continue
  printf '%s\n' "$CONTENIDO" | grep -q 'useTituloDocumento(' && continue

  LINEA=$(printf '%s\n' "$CONTENIDO" | grep -n 'window\.print(' | head -1 | cut -d: -f1)
  printf '%s:%s\n' "$archivo" "$LINEA"
done)

[ -z "$HALLAZGOS" ] && exit 0

echo ""
echo "  ✗ Este push agrega o modifica una pantalla que llama a window.print()"
echo "    sin fijar el nombre con el que se guarda el documento."
echo ""
printf '%s\n' "$HALLAZGOS" | while IFS= read -r linea; do
  echo "    $linea"
done
echo ""
echo "    Sin esto, el PDF se guarda como «Dynamic — CAYLA» —el título fijo del"
echo "    sitio— para cualquier persona y cualquier papel. Pasó con las boletas"
echo "    (2026-07-28) y con Liquidaciones (2026-09-10)."
echo ""
echo "    Qué hacer: agrega useTituloDocumento(...) con el nombre de la persona"
echo "    y el tipo de documento — mismo patrón que ya usan boleta, contrato,"
echo "    memo y ficha personal (apps/web/lib/admin/use-titulo-documento.ts)."
echo ""
echo "    En una urgencia real:  git push --no-verify"
echo ""
exit 1

#!/bin/sh
# Las dos reglas del CLAUDE.md que hoy se cumplen de memoria, verificadas.
#
# POR QUÉ EXISTE
#
# La auditoría de agosto de 2026 encontró DIEZ comparaciones de `rol` contra un
# literal fuera de `permisos.ts` y TRES `"America/Lima"` fuera de
# `fecha-lima.ts`. Las dos reglas están escritas en el CLAUDE.md, y las dos se
# escribieron después de un trabajo grande: la primera tras juntar 35 copias de
# la misma condición de permiso, la segunda tras juntar 32 del huso horario.
#
# O sea que el documento no falló por estar mal escrito. Falló porque un
# documento es memoria, y la memoria de un equipo con cuatro sesiones en
# paralelo dura lo que dura una tarde con prisa. Lo que faltaba no era prosa:
# era que alguien preguntara.
#
# SOLO MIRA LO QUE EL PUSH AGREGA, y esa es la razón de que sirva.
#
# Comparar el árbol entero encontraría las trece que ya están y fallaría en
# TODOS los push, incluidos los que no tienen nada que ver. Un freno que chilla
# siempre se desactiva a la semana — es la misma lección que `numeracion.sh`
# lleva escrita en su cabecera, y la misma que se pagó tres veces el día que se
# escribió lo de `types.ts`.
#
# Así que la deuda vieja no molesta a nadie, y una regla nueva no puede entrar.
# La deuda se paga en su propio lote, no a costa de que este freno mienta.
#
# BLOQUEA, no avisa. Aquí no hay ambigüedad: esto habla de lo que SALE de esta
# máquina hacia GitHub, no de lo que hay en el disco a medio escribir. Es
# exactamente la distinción que el pre-push ya tiene escrita para `types.ts`.
#
# Para saltarlo en una urgencia real:  git push --no-verify

BASE="origin/main"
git rev-parse --verify --quiet "$BASE" >/dev/null 2>&1 || exit 0

HALLAZGOS=$(git diff --unified=0 "$BASE...HEAD" -- '*.ts' '*.tsx' 2>/dev/null | awk '
  /^\+\+\+ b\// { archivo = substr($0, 7); next }
  /^@@ / {
    # @@ -viejo +nuevo,cuantas @@  → nos quedamos con el primer número de +nuevo
    split($3, p, ",");  linea = substr(p[1], 2) + 0;  next
  }
  /^\+/ {
    texto = substr($0, 2)
    limpio = texto
    sub(/^[ \t]*/, "", limpio)

    # Los comentarios no son código: el propio CLAUDE.md cita `rol === "admin"`
    # para explicar la regla, y un guardián que castiga al que la explica es
    # peor que no tenerlo.
    esComentario = (limpio ~ /^(\/\/|\*|\/\*)/)

    if (!esComentario) {
      if (archivo !~ /permisos\.ts$/ && texto ~ /[^a-zA-Z_]rol[ \t]*[!=]==[ \t]*["'"'"']/)
        print "rol|" archivo "|" linea "|" limpio
      if (archivo !~ /fecha-lima\.ts$/ && texto ~ /"America\/Lima"/)
        print "lima|" archivo "|" linea "|" limpio
    }
    linea++
  }
')

[ -z "$HALLAZGOS" ] && exit 0

echo ""
echo "  ✗ Este push agrega código que rompe una regla del CLAUDE.md."
echo ""

echo "$HALLAZGOS" | grep '^rol|' | while IFS='|' read -r _ archivo linea texto; do
  echo "    $archivo:$linea"
  echo "      $texto"
done | head -30

if echo "$HALLAZGOS" | grep -q '^rol|'; then
  echo ""
  echo "    «Nunca comparar rol contra un string literal fuera de permisos.ts.»"
  echo "    Un rol === \"admin\" suelto en una pantalla es un permiso que nadie va"
  echo "    a encontrar el día que haya que cambiarlo. La regla se escribió tras"
  echo "    juntar 35 copias de la misma condición."
  echo ""
  echo "    Qué hacer: agrega la función que falta en packages/shared/src/permisos.ts"
  echo "    y úsala. Si de verdad no es un permiso sino un filtro por sede, di eso"
  echo "    en el nombre (puedeVerOtrasSedes, esDeSuSede) y vivirá igual ahí."
  echo ""
fi

echo "$HALLAZGOS" | grep '^lima|' | while IFS='|' read -r _ archivo linea texto; do
  echo "    $archivo:$linea"
  echo "      $texto"
done | head -30

if echo "$HALLAZGOS" | grep -q '^lima|'; then
  echo ""
  echo "    «Nunca escribir \"America/Lima\" fuera de fecha-lima.ts.»"
  echo "    El corte del día decide a qué fecha se le paga un marcaje: no puede"
  echo "    tener dos versiones. La regla se escribió tras juntar 32 copias."
  echo ""
  echo "    Qué hacer: usa hoyLima(), fechaLima(), rangoDelDiaLima() o"
  echo "    rangoDelMesLima() de @cayla-dynamic/shared. Si te falta una función,"
  echo "    agrégala AHÍ — que es justo lo que hace que la regla siga valiendo."
  echo ""
fi

echo "    En una urgencia real:  git push --no-verify"
echo ""
exit 1

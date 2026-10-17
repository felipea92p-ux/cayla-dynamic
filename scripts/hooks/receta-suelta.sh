#!/bin/sh
# La receta suelta de una pieza que ya tiene componente. Solo lo nuevo.
#
# POR QUÉ EXISTE
#
# El ADR 0004 (docs/adr/0004-diseno-unificado.md, 2026-10-13) decidió UNA forma
# para cada pieza del panel y construyó los componentes en apps/web/components/ui.
# El primer inventario contó unos 130 recuadros de tarjeta contra 9 usos de
# <TarjetaInfo>, seis formas de dibujar «un número y su etiqueta», cuatro
# tablas y cuatro tamaños de título. Los componentes cierran la puerta de
# adelante; este freno cierra la de atrás: el 2026-10-17, cuatro días después,
# ya habían aparecido siete archivos nuevos con la tarjeta escrita a mano
# (components/educacion/* y components/boletas/hoja-constancia-boleta.tsx).
# Nadie lo hizo mal a propósito: la pantalla de al lado tiene la receta vieja,
# y copiarla es lo que cuesta menos.
#
# Es la misma historia que ya escribieron `rol === "admin"`, "America/Lima" y
# el nombre del PDF: la regla estaba escrita, la memoria de un equipo con
# varias sesiones en paralelo dura lo que dura una tarde, y lo que faltaba no
# era prosa sino que alguien preguntara.
#
# QUÉ BUSCA — nueve familias, medidas el 2026-10-17 sobre las 152 pantallas y
# componentes del panel (RECETA_TODO=1 las cuenta sin frenar nada):
#
#   tarjeta  rounded-2xl|superficie + border-sand + bg-papel    → <TarjetaInfo>,
#            (<EstadoVacio> si es un «no hay nada»; <Tabla> si lleva overflow-x-auto)
#   cifra    font-serif + text-2xl|3xl|4xl en un número         → <Cifra>
#   filtro   <button aria-pressed> a mano, o un <button> que se enciende con
#            bg-tinta + text-crema en un ternario               → <Filtro> / <Cifra onClick>
#   banner   borde y fondo del MISMO color (rojo/ámbar/verde/pizarra) con radio
#            de caja, que no sea inline                         → <BannerAviso>
#   rotulo   la clase `etiqueta`                                → <Rotulo>, <RotuloEstado>,
#            `sobretitulo`, `titulo`
#   titulo   <h1 font-serif> en una pantalla de (admin)         → <CabeceraPagina>
#   tabla    <thead>/<tr> con bg-sand/70, franjas even:/odd:,
#            <tr border-t border-sand>                          → <TablaEncabezado>, <Fila>
#   carga    «Cargando…» como texto de un elemento              → <Cargando />, <CargandoFila>
#   cajon    fixed inset-y-0 right-0                            → <Drawer>
#
# El detalle de cada receta —qué tokens, qué se exime y por qué— está en
# receta-suelta.py. La deuda, el 2026-10-17 y ya con la migración de Lo mío,
# Personas, Casos, Normas y Política salarial dentro (#552), en ese orden:
# 69 + 16 + 29 + 79 + 20 + 16 + 20 + 20 + 1 = 270 recetas en 82 archivos.
#
# EL SEGUNDO BARRIDO (lo que el ADR pidió antes de poner el freno: «un freno
# sobre un inventario incompleto bloquea lo equivocado»). Se buscaron cuatro
# familias que el primer inventario pudo no ver. Resultado:
#
#   · ESTADOS DE CARGA — ENTRA. Ya había componente desde el 27-jul-2026
#     (components/cargando.tsx, fuera de ui y por eso invisible al ADR): 36
#     usos de <Cargando /> contra 20 «Cargando…» a mano, 5 de ellos dentro de
#     un Suspense. Esqueletos a mano: cero (animate-pulse no aparece en ningún
#     lado), así que de esa mitad no hay nada que vigilar.
#   · CAJONES — ENTRA, solo el de la derecha. <Drawer> y <HojaInferior> existen;
#     a mano hay uno (horas/page.tsx, fixed inset-y-0 right-0) y dos del menú
#     por la izquierda (nav/), que son otra cosa y no se tocan.
#   · AVISOS EMERGENTES — NO ENTRA, y es buena noticia. useToast() ya es «el
#     único aviso de acción del panel» (components/toast.tsx): ni un solo
#     `fixed bottom-` suelto fuera de él. Lo que antes eran banners de resultado
#     ya cae en la familia banner.
#   · PESTAÑAS — NO ENTRA. El ADR las unió con los filtros (decisión 10) pero
#     de las 5 tablist del panel, 4 son pestañas SUBRAYADAS (ausencias,
#     disciplina, personas/[id], planilla) y solo 1 es un segmentado
#     (provisiones): <Filtro> no es el destino de las 4. Bloquear sin destino
#     es bloquear lo equivocado. Falta una decisión: ¿<Filtro> con otra cara,
#     o una <Pestanas>? Queda en el ADR como pendiente.
#
# Y lo que se dejó fuera adrede:
#   · <Insignia> y <Modal>: son anteriores al ADR; ampliar es barato si se pide.
#   · rounded-lg / rounded-xl: es la regla de la escala de radios, otra regla.
#   · «text-xs font-medium text-taupe» (la receta de <Rotulo>): es el texto
#     chico de todo el panel; un freno ahí chillaría siempre.
#   · el terminal y components/ui: ADR 0004, «el terminal queda fuera».
#   · components/cargando.tsx y components/toast.tsx: son la casa de dos recetas.
#
# SOLO LO QUE EL PUSH AGREGA, y esa es la razón de que sirva. Quedan 270 recetas
# a mano (y, contadas con un criterio más ancho, 166 tarjetas en 61 archivos y
# 241 <button>): exigirlas frenaría todos los push, incluidos los que no tienen
# nada que ver, y en una semana se estaría usando --no-verify por costumbre. Es
# la lección de numeracion.sh, reglas-de-la-casa.sh y lint-de-lo-nuevo.sh, que
# llevan escrita en su cabecera.
#
# Y «agrega» quiere decir MÁS recetas, no una línea distinta. Se compara por
# hunk del diff: si una línea que ya tenía la receta solo cambió (un hotfix que
# toca el className de una tarjeta vieja en una pantalla de planilla), no cuenta.
# Un freno que castiga el arreglo de un error de plata por una tarjeta que no
# escribió es un freno que se salta. Lo que SÍ cuenta: un archivo nuevo, y una
# receta que aparece donde no había ninguna. Lo que no ve: mover una tarjeta de
# un archivo a otro cuenta como nueva (se dice con receta-propia: o se migra).
#
# MEDIDO CONTRA LA HISTORIA (2026-10-17): cada merge de main simulado como un push
# contra su primer padre, con  LINT_BASE="$sha^1" RECETA_HEAD="$sha" ./receta-suelta.sh
#   · los últimos 30 merges: 6 habrían frenado (20 %). Los 6 sumaban recetas
#     de verdad —los 4 del rediseño de Educación, las modales de Boletas y la
#     tarjeta de cumpleaños—; ninguno era un arreglo.
#   · los últimos 30 commits sueltos: 1 (las modales de Boletas).
#   · los últimos 150 merges (15-sep → 17-oct): 36 (24 %). De 175 hallazgos,
#     9 (5 %) eran código MOVIDO a otro archivo, no escrito: ese es el falso
#     positivo que se acepta y que se resuelve con `receta-propia:` o migrando.
#     Comparar por hunk sacó a 3 pushes que solo tocaban una línea vieja.
#   · el #552 (la migración de cinco secciones, que quitó 71 recetas) pasa.
#
# BLOQUEA, no avisa: esto habla de lo que SALE hacia GitHub, no de lo que hay a
# medio escribir en el disco; lee cada archivo de git (HEAD:ruta), nunca del
# disco, así que los cambios sin commitear no lo mueven.
#
# LA SALIDA LEGÍTIMA. Una caja que de verdad no es ninguna de estas (un
# <details>, un papel que se imprime) se declara en la misma línea o en una de
# las dos de arriba, con el motivo:
#
#     {/* receta-propia: es un <details> y TarjetaInfo no puede serlo */}
#
# El motivo es obligatorio (más de diez caracteres) y se busca con grep. No es
# un permiso para copiar la receta porque «casi sirve»: eso es corregir el
# componente. Existe porque la alternativa es --no-verify, que además se salta
# el typecheck, las pruebas y la numeración, y no deja huella.
#
# LÍMITES, dichos para que nadie descubra que el freno ve menos de lo que cree:
#   · Es un escáner de cadenas y etiquetas, no un compilador. Una receta partida
#     en dos cadenas de un cx() («rounded-superficie border», «bg-papel p-5») no
#     se ve; una cadena armada con una variable, tampoco.
#   · Una tarjeta con el borde condicional (`border ${x ? "border-tinta" : "border-sand"}`)
#     no tiene `border-sand` literal y no se ve.
#   · Un <Link> o <button> con forma de tarjeta no cuenta como tarjeta.
#   · Un archivo con la clase `hoja` (un documento) queda exento de cifra,
#     rótulo y tabla, porque ahí la tipografía de papel no es la del panel.
#   · No compara contra el diseño: que uses <TarjetaInfo> no dice que lo uses bien.
#
# Se probó con scripts/hooks/probar-receta-suelta.sh: casos que DEBEN bloquear,
# casos que deben pasar, la salida legítima, y los hunks de una línea vieja.
# Se escribió por eso: lint-de-lo-nuevo.sh se escribió cuatro veces dando el
# push por bueno, y los cuatro fallos eran silenciosos.
#
# Medir la deuda sin frenar nada:
#     RECETA_TODO=1 RECETA_RESUMEN=1 python3 scripts/hooks/receta-suelta.py
#
# Para saltarlo en una urgencia real:  git push --no-verify

# Antes del `cd`: con la ruta relativa con la que pre-push nos llama, después del
# `cd` ya no apuntaría a nada.
AQUI=$(cd "$(dirname "$0")" && pwd)

BASE="${LINT_BASE:-origin/main}"
git rev-parse --verify --quiet "$BASE" >/dev/null 2>&1 || exit 0

RAIZ=$(git rev-parse --show-toplevel)
cd "$RAIZ" || exit 0

# Ni un .tsx de apps/web que el push toque, ni nada que mirar: sale en un parpadeo,
# que es lo normal (la mayoría de los push son SQL).
git diff --name-only --diff-filter=AMR "$BASE...${RECETA_HEAD:-HEAD}" -- 'apps/web/*.tsx' 2>/dev/null | grep -q . || exit 0

# Un Python que ARRANQUE, no uno que exista en el PATH. Mismo motivo y mismo
# arreglo que lint-de-lo-nuevo.sh y fecha-que-bloquea.sh (2026-09-28): en Windows
# `python3` y `python` existen siempre como acceso directo de la Microsoft Store.
# Sin Python se avisa y se deja pasar: este freno bloquea por una receta suelta,
# no por lo que tenga instalado la máquina de quien empuja.
PY=""
for candidato in python3 python; do
  if "$candidato" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 6) else 1)' >/dev/null 2>&1; then PY="$candidato"; break; fi
done
if [ -z "$PY" ]; then
  echo "  ⚠ No hay Python 3 en esta máquina; este freno corrió pero este push NO se revisó."
  exit 0
fi

exec "$PY" "$AQUI/receta-suelta.py"

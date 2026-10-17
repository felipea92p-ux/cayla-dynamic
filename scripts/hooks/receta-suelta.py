#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
El analizador de receta-suelta.sh. Se llama desde ahí (que decide si hay un
Python que arranque); no se corre a mano salvo para MEDIR la deuda:

    RECETA_TODO=1 python3 scripts/hooks/receta-suelta.py     # todo el árbol como si fuera nuevo
    RECETA_TODO=1 RECETA_RESUMEN=1 python3 …                 # solo cuántas por familia

Qué hace, en una frase: lee cada archivo .tsx que el push toca, encuentra las
cadenas de clases y las etiquetas JSX que escribió a mano la receta de una pieza
que ya tiene componente en apps/web/components/ui, y bloquea si el push AGREGA
más de las que quita. El porqué, las familias y lo que se dejó fuera están en
la cabecera de receta-suelta.sh.

Por qué un escáner y no un grep: una receta es un CONJUNTO de clases dentro de
UNA cadena («rounded-superficie border border-sand bg-papel»), y el diff de
líneas no sabe dónde empieza ni dónde termina una cadena, ni si está en un
comentario, ni de qué etiqueta es el className. Este escáner recorre el archivo
entero respetando comillas, plantillas (`…${…}…`) y comentarios, y le pone a
cada cadena su etiqueta JSX y lo que había justo antes (un `?`, un `&&`…).
"""
import bisect
import os
import re
import subprocess
import sys

BASE = os.environ.get("LINT_BASE", "origin/main")
CABEZA = os.environ.get("RECETA_HEAD", "HEAD")
TODO = bool(os.environ.get("RECETA_TODO"))
SOLO_RESUMEN = bool(os.environ.get("RECETA_RESUMEN"))

# Lo que NO se juzga. `components/ui` es donde viven las recetas (de ahí salen,
# no pueden ser su propia infracción) y el terminal conserva su estilo propio
# (ADR 0004, «el terminal queda fuera»). Los otros dos son la casa de dos
# familias que NO están en ui pero son su única definición: el estado de carga
# y el aviso emergente.
EXCLUIDOS = (
    "apps/web/components/ui/",
    "apps/web/app/(terminal)/",
    "apps/web/components/cargando.tsx",
    "apps/web/components/toast.tsx",
)

# Las pantallas de verdad. Un <h1> suelto en un login, en un error o en un papel
# impreso NO es el título de una pantalla del panel.
# «Lo mío» (mio) no cuenta: tiene su propia cabecera, pensada para el celular, y
# ninguna de sus pantallas usa <CabeceraPagina> (medido el 2026-10-17: 0 de 18).
PANTALLA = re.compile(r"^apps/web/app/\(admin\)/.+/page\.tsx$")
NO_ES_PANTALLA = re.compile(r"/(login|nueva-clave|olvide-clave|imprimir|constancias)/")

# Un elemento que se toca no es una tarjeta ni un aviso, aunque lleve su caja.
INTERACTIVOS = {"a", "button", "label", "summary", "input", "select", "textarea", "Link"}

SALIDA_PERMITIDA = re.compile(r"receta-propia:\s*(\S.{10,})")


# ── git ──────────────────────────────────────────────────────────────────────
def git(*args):
    try:
        r = subprocess.run(["git"] + list(args), stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, timeout=60)
    except Exception:
        return None
    if r.returncode != 0:
        return None
    return r.stdout.decode("utf-8", "replace").replace("\r\n", "\n")


# ── el escáner ───────────────────────────────────────────────────────────────
class Lit(object):
    """Una cadena entre comillas o una plantilla, con su contexto."""
    __slots__ = ("linea", "texto", "antes", "tag", "attr", "obj")

    def __init__(self, linea, texto, antes, obj):
        self.linea, self.texto, self.antes, self.obj = linea, texto, antes, obj
        self.tag = obj.nombre if obj else None
        self.attr = obj.attr_actual if obj else None


class Tag(object):
    """Una etiqueta JSX de apertura: <button …>, <h1 …>, <Link …/>."""
    __slots__ = ("nombre", "linea", "attrs", "fin", "autocierre", "attr_actual")

    def __init__(self, nombre, linea):
        self.nombre, self.linea = nombre, linea
        self.attrs = {}            # nombre del atributo → línea donde aparece
        self.fin = 0               # posición justo después del `>`
        self.autocierre = False
        self.attr_actual = None


NOMBRE_TAG = re.compile(r"[A-Za-z][A-Za-z0-9_.\-:]*")
NOMBRE_ATTR = re.compile(r"[A-Za-z_$][A-Za-z0-9_$:\-]*")
INTERESANTE = re.compile(r"//|/\*|[\"'`{}<]")
ESPACIOS = re.compile(r"\s+")


class Escaneo(object):
    def __init__(self, texto):
        self.t = texto
        self.n = len(texto)
        self.saltos = [i for i, c in enumerate(texto) if c == "\n"]
        self.lits = []
        self.tags = []
        self.pila = []
        self.ult = ""   # los últimos caracteres de CÓDIGO (sin espacios ni comentarios)
        self.codigo(0, None)

    def linea_de(self, pos):
        return bisect.bisect_left(self.saltos, pos) + 1

    def _avanzar_ult(self, segmento):
        s = ESPACIOS.sub("", segmento)
        if s:
            self.ult = (self.ult + s)[-3:]

    def registrar(self, linea, texto, antes):
        self.lits.append(Lit(linea, texto, antes, self.pila[-1] if self.pila else None))
        self.ult = (self.ult + '"')[-3:]

    def es_apertura(self, i):
        t = self.t
        if i + 1 >= self.n or not t[i + 1].isalpha():
            return False
        if i > 0 and (t[i - 1].isalnum() or t[i - 1] in "_$.)]"):
            return False          # un genérico (useState<…>, Array<…>) o una comparación
        return True

    def codigo(self, i, cierre):
        """Recorre código hasta la `}` que cierra (si `cierre` es '}'), o hasta el final."""
        t, n = self.t, self.n
        prof = 0
        while i < n:
            m = INTERESANTE.search(t, i)
            if not m:
                self._avanzar_ult(t[i:])
                return n
            self._avanzar_ult(t[i:m.start()])
            i = m.start()
            c = t[i]
            if t.startswith("//", i):
                j = t.find("\n", i)
                i = n if j < 0 else j
            elif t.startswith("/*", i):
                j = t.find("*/", i + 2)
                i = n if j < 0 else j + 2
            elif c in "\"'":
                i = self.cadena(i)
            elif c == "`":
                i = self.plantilla(i)
            elif c == "{":
                prof += 1
                self.ult = (self.ult + "{")[-3:]
                i += 1
            elif c == "}":
                if prof == 0 and cierre == "}":
                    return i + 1
                prof = max(0, prof - 1)
                self.ult = (self.ult + "}")[-3:]
                i += 1
            else:  # '<'
                if self.es_apertura(i):
                    i = self.etiqueta(i)
                else:
                    self.ult = (self.ult + "<")[-3:]
                    i += 1
        return n

    def cadena(self, i):
        t, n = self.t, self.n
        q = t[i]
        antes = self.ult
        j = i + 1
        while j < n and t[j] != q and t[j] != "\n":
            if t[j] == "\\":
                j += 1
            j += 1
        if j < n and t[j] == q:
            self.registrar(self.linea_de(i), t[i + 1:j], antes)
            return j + 1
        return j      # sin cerrar (un apóstrofo en texto JSX): seguimos desde el salto de línea

    def plantilla(self, i):
        t, n = self.t, self.n
        antes = self.ult
        linea = self.linea_de(i)
        partes = []
        j = i + 1
        while j < n:
            c = t[j]
            if c == "\\":
                partes.append(" ")
                j += 2
                continue
            if c == "`":
                break
            if c == "$" and j + 1 < n and t[j + 1] == "{":
                partes.append(" ")
                self.ult = (self.ult + "{")[-3:]
                j = self.codigo(j + 2, "}")
                continue
            partes.append(c)
            j += 1
        self.registrar(linea, "".join(partes), antes)
        return j + 1

    def cadena_jsx(self, k):
        """El valor entre comillas de un atributo JSX: puede cruzar líneas."""
        t = self.t
        q = t[k]
        e = t.find(q, k + 1)
        if e < 0:
            return self.n
        self.registrar(self.linea_de(k), t[k + 1:e], "=")
        return e + 1

    def etiqueta(self, i):
        t, n = self.t, self.n
        m = NOMBRE_TAG.match(t, i + 1)
        tag = Tag(m.group(0), self.linea_de(i))
        self.tags.append(tag)
        self.pila.append(tag)
        j = m.end()
        tag.fin = n
        while j < n:
            c = t[j]
            if c.isspace():
                j += 1
            elif t.startswith("/>", j):
                tag.autocierre = True
                j += 2
                tag.fin = j
                break
            elif c == ">":
                j += 1
                tag.fin = j
                break
            elif c == "{":
                self.ult = "{"
                j = self.codigo(j + 1, "}")
            elif c in "\"'":
                j = self.cadena_jsx(j)
            else:
                ma = NOMBRE_ATTR.match(t, j)
                if not ma:
                    j += 1
                    continue
                nom = ma.group(0)
                if nom not in tag.attrs:
                    tag.attrs[nom] = self.linea_de(ma.start())
                j = ma.end()
                k = j
                while k < n and t[k].isspace():
                    k += 1
                if k < n and t[k] == "=":
                    k += 1
                    while k < n and t[k].isspace():
                        k += 1
                    tag.attr_actual = nom
                    if k < n and t[k] in "\"'":
                        j = self.cadena_jsx(k)
                    elif k < n and t[k] == "{":
                        self.ult = "="
                        j = self.codigo(k + 1, "}")
                    else:
                        j = k
                    tag.attr_actual = None
        self.pila.pop()
        self.ult = (self.ult + ">")[-3:]
        return j


# ── las reglas ───────────────────────────────────────────────────────────────
# Cada familia dice qué pieza usar y por qué. El texto sale tal cual en el
# mensaje del bloqueo.
FAMILIAS = {
    "tarjeta": (
        "Tarjeta, vacío o tabla escritos a mano",
        "El recuadro «rounded-superficie border border-sand bg-papel» ya es un componente: "
        "<TarjetaInfo> (con `titulo` serif 18 px), <EstadoVacio> si solo dice que no hay nada, "
        "<Tabla> si envuelve una <table>. Había ~130 copias contra 9 usos del componente; cada "
        "copia hereda el margen que le tocó.",
    ),
    "cifra": (
        "Cifra escrita a mano",
        "«Un número y su etiqueta» es <Cifra etiqueta=… valor=… tono=…> (decisiones 1 y 2): el "
        "número siempre en tinta y el significado en un punto de color junto a la etiqueta. "
        "Había seis formas de dibujarla.",
    ),
    "filtro": (
        "Filtro o pestaña escritos a mano",
        "Un botón que se enciende y se apaga es <Filtro activo=… tamano=…> (decisión 10): lleva "
        "`aria-pressed` solo y la esquina de botón, no de píldora. Una cifra que también filtra "
        "es <Cifra onClick=…>.",
    ),
    "banner": (
        "Aviso escrito a mano",
        "El aviso con borde y fondo de color es <BannerAviso variante=… titulo=…> (decisión 9); "
        "`enLinea` para el de una línea. Había ~59 con esquinas de 8, 12 y 16 px.",
    ),
    "rotulo": (
        "Rótulo escrito con la clase .etiqueta",
        "`.etiqueta` hacía cuatro trabajos (decisiones 11 a 14). Según cuál sea el tuyo: "
        "`sobretitulo` de <CabeceraPagina>, `titulo` de <TarjetaInfo>, <Rotulo> para el nombre "
        "de una sub-sección, <RotuloEstado> para un grupo con color.",
    ),
    "titulo": (
        "Título de pantalla escrito a mano",
        "Es <CabeceraPagina titulo=… descripcion=… accion=…> (decisión 6): 28 px, peso medio, "
        "y el margen de abajo ya resuelto para celular.",
    ),
    "tabla": (
        "Fila o encabezado de tabla escritos a mano",
        "El encabezado es <TablaEncabezado> y la fila es <Fila> (línea superior y resalte al "
        "pasar el cursor). Sin franjas alternas: la decisión 5 las quitó.",
    ),
    "carga": (
        "Estado de carga escrito a mano",
        "Es <Cargando /> (o <CargandoFila columnas=…> dentro de una tabla) de "
        "components/cargando.tsx: el colibrí que aletea le dice a quien espera que el sistema "
        "trabaja y no está colgado; un texto quieto no.",
    ),
    "cajon": (
        "Cajón lateral escrito a mano",
        "El panel que entra por la derecha es <Drawer> (reusa useSalidaAnimada y useFocoAtrapado, "
        "así que atrapa el foco y lo devuelve). Uno a mano no hace ninguna de las dos cosas.",
    ),
}
ORDEN_FAMILIAS = ["tarjeta", "cifra", "filtro", "banner", "rotulo", "titulo", "tabla", "carga", "cajon"]

TONOS = ("rojo", "ambar", "verde", "pizarra")
RADIO_SUPERFICIE = ("rounded-2xl", "rounded-superficie")
RADIO_CAJA = re.compile(r"^rounded-(md|lg|xl|2xl|3xl|control|superficie)$")
TIPOGRAFICO_GRANDE = re.compile(r"^text-(2xl|3xl|4xl)$")
CLASE_MINUSCULA = re.compile(r"^[a-z0-9:\[\]\-_/.!()%#]+$")
CARGANDO = re.compile(r"(^|>)\s*Cargando(…|\.\.\.)\s*(<|$)")
ES_DOCUMENTO = re.compile(r"(^|[\s\"'`])hoja([\s\"'`]|$)")


class Hit(object):
    __slots__ = ("linea", "familia", "pieza", "firma")

    def __init__(self, linea, familia, pieza, firma):
        self.linea, self.familia, self.pieza, self.firma = linea, familia, pieza, firma


def es_impreso(tk):
    """Una clase `print:` que no sea ocultarse indica un papel, no una pantalla."""
    return any(x.startswith("print:") and x != "print:hidden" for x in tk)


def hits_de(ruta, texto):
    if not texto:
        return []
    esc = Escaneo(texto)
    documento = any(ES_DOCUMENTO.search(l.texto) for l in esc.lits)
    hits = []
    lineas = texto.split("\n")

    def poner(linea, familia, pieza, firma):
        # Una línea cuenta una vez por familia: una fila con franjas Y con borde
        # superior es una sola fila a mano, no dos.
        if any(h.linea == linea and h.familia == familia for h in hits):
            return
        hits.append(Hit(linea, familia, pieza, firma))

    for l in esc.lits:
        tk = set(l.texto.split())
        if not tk:
            continue
        interactivo = l.tag in INTERACTIVOS
        impreso = es_impreso(tk)

        # ── tarjeta / vacío / tabla ──
        if ({"border", "border-sand", "bg-papel"} <= tk and tk & set(RADIO_SUPERFICIE)
                and not impreso and not interactivo
                and not (tk & {"border-dashed", "fixed", "absolute"})):
            if "overflow-x-auto" in tk:
                pieza = "<Tabla>"
            elif (tk & {"py-6", "py-8", "py-10", "py-12"}) and (tk & {"text-taupe", "text-center"}):
                pieza = "<EstadoVacio>"
            else:
                pieza = "<TarjetaInfo>"
            poner(l.linea, "tarjeta", pieza, " ".join(sorted(tk)))

        # ── aviso ──
        if ("border" in tk and not impreso and not interactivo
                and any(RADIO_CAJA.match(x) for x in tk)
                and not (tk & {"inline-flex", "inline-block", "inline"})):
            for tono in TONOS:
                if (any(x.startswith("border-%s/" % tono) for x in tk)
                        and any(x.startswith("bg-%s/" % tono) for x in tk)):
                    poner(l.linea, "banner", "<BannerAviso>", tono)
                    break

        # ── cifra ── (un número con la tipografía de cifra, no un título ni un avatar)
        if (not documento and not impreso and "font-serif" in tk
                and any(TIPOGRAFICO_GRANDE.match(x) for x in tk)
                and not (tk & {"rounded-full", "rounded-pildora", "justify-center", "place-items-center"})
                and l.tag in ("span", "div", "p", "dd", "strong", "b")):
            obj = l.obj
            hijo_numero = bool(obj is not None and not obj.autocierre
                               and re.match(r"\s*\{[^{}<>]*\}\s*</", esc.t[obj.fin:obj.fin + 400]))
            if "tabular-nums" in tk or hijo_numero:
                poner(l.linea, "cifra", "<Cifra>", " ".join(sorted(tk)))

        # ── filtro (un <button> que se enciende con bg-tinta + text-crema) ──
        if (l.tag == "button" and l.antes.endswith(("?", ":", "&&"))
                and {"bg-tinta", "text-crema"} <= tk and not impreso):
            poner(l.linea, "filtro", "<Filtro> (o <Boton> si no filtra nada)", "ternario tinta/crema")

        # ── rótulo ──
        if (not documento and "etiqueta" in tk
                and (l.tag is not None
                     or (len(tk) >= 2 and all(CLASE_MINUSCULA.match(x) for x in tk)))):
            poner(l.linea, "rotulo", "<Rotulo> / <RotuloEstado> / sobretitulo / titulo", "clase etiqueta")

        # ── cajón ──
        if {"fixed", "inset-y-0", "right-0"} <= tk:
            poner(l.linea, "cajon", "<Drawer>", "fixed inset-y-0 right-0")

        # ── tabla: encabezado, franjas y fila ──
        if l.tag in ("thead", "tr") and "bg-sand/70" in tk and not documento:
            poner(l.linea, "tabla", "<TablaEncabezado>", "bg-sand/70")
        if any(x.startswith(("even:bg-", "odd:bg-")) for x in tk) and not documento:
            poner(l.linea, "tabla", "<Fila> (sin franjas)", "franjas alternas")
        if l.tag == "tr" and {"border-t", "border-sand"} <= tk and not documento:
            poner(l.linea, "tabla", "<Fila>", "border-t border-sand")

        # ── título de pantalla ──
        if (l.tag == "h1" and "font-serif" in tk and not documento and PANTALLA.match(ruta)
                and not NO_ES_PANTALLA.search(ruta)):
            poner(l.linea, "titulo", "<CabeceraPagina>", "h1 serif")

    # ── filtro: aria-pressed en un <button> a mano ──
    for g in esc.tags:
        if g.nombre == "button" and "aria-pressed" in g.attrs:
            poner(g.attrs["aria-pressed"], "filtro", "<Filtro> / <Cifra onClick=…>", "aria-pressed")

    # ── estado de carga: «Cargando…» como texto de un elemento ──
    # Se mira la línea tal cual (menos comentarios de línea entera): el texto JSX no
    # tiene comillas, así que una cadena «Cargando…» dentro de un ternario no cuenta.
    en_bloque = False
    for no, linea in enumerate(lineas, 1):
        s = linea.strip()
        if en_bloque:
            if "*/" in s:
                en_bloque = False
            continue
        if s.startswith("/*") and "*/" not in s:
            en_bloque = True
            continue
        if s.startswith(("//", "*", "/*", "{/*")):
            continue
        if ruta.endswith("app/loading.tsx"):
            continue
        if CARGANDO.search(s):
            poner(no, "carga", "<Cargando /> / <CargandoFila>", "Cargando…")
    return hits


# ── el diff ──────────────────────────────────────────────────────────────────
RE_HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


def hunks_de(rutas):
    d = git("diff", "-M", "--unified=0", "%s...%s" % (BASE, CABEZA), "--", *rutas)
    if d is None:
        return None
    hs = []
    for l in d.split("\n"):
        m = RE_HUNK.match(l)
        if m:
            a = int(m.group(1)); b = 1 if m.group(2) is None else int(m.group(2))
            c = int(m.group(3)); dd = 1 if m.group(4) is None else int(m.group(4))
            hs.append((a, b, c, dd))
    return hs


def con_salida_permitida(lineas, linea):
    """¿La línea del hallazgo, o una de las dos de arriba, dice `receta-propia: <motivo>`?"""
    for k in (linea, linea - 1, linea - 2):
        if 1 <= k <= len(lineas) and SALIDA_PERMITIDA.search(lineas[k - 1]):
            return True
    return False


def excluido(ruta):
    return any(ruta.startswith(p) if p.endswith("/") else ruta == p for p in EXCLUIDOS)


def main():
    todos = []   # (ruta, Hit, texto de la línea)

    if TODO:
        listado = git("ls-files", "apps/web") or ""
        for ruta in listado.split("\n"):
            if not ruta.endswith(".tsx") or excluido(ruta):
                continue
            try:
                with open(ruta, encoding="utf-8") as f:
                    texto = f.read().replace("\r\n", "\n")
            except Exception:
                continue
            lineas = texto.split("\n")
            for h in hits_de(ruta, texto):
                todos.append((ruta, h, lineas[h.linea - 1].strip()))
    else:
        if git("rev-parse", "--verify", "--quiet", BASE) is None:
            return 0
        estado = git("diff", "--name-status", "-M", "--diff-filter=AMR",
                     "%s...%s" % (BASE, CABEZA), "--", "apps/web")
        if not estado:
            return 0
        base_fusion = (git("merge-base", BASE, CABEZA) or BASE).strip()
        for fila in estado.split("\n"):
            partes = fila.split("\t")
            if len(partes) < 2:
                continue
            nuevo = partes[-1]
            viejo = partes[1] if partes[0].startswith("R") and len(partes) >= 3 else None
            if not nuevo.endswith(".tsx") or excluido(nuevo):
                continue
            texto = git("show", "%s:%s" % (CABEZA, nuevo))
            if texto is None:
                continue
            antes = ""
            if partes[0].startswith("M"):
                antes = git("show", "%s:%s" % (base_fusion, nuevo)) or ""
            elif viejo:
                antes = git("show", "%s:%s" % (base_fusion, viejo)) or ""
            nuevos, viejos = hits_de(nuevo, texto), hits_de(nuevo, antes)
            if not nuevos:
                continue
            hs = hunks_de([viejo, nuevo] if viejo else [nuevo])
            if hs is None:
                continue
            lineas = texto.split("\n")
            for (a, b, c, d) in hs:
                en_nuevas = [h for h in nuevos if c <= h.linea < c + d]
                en_viejas = [h for h in viejos if a <= h.linea < a + b]
                for fam in FAMILIAS:
                    nf = [h for h in en_nuevas if h.familia == fam]
                    vf = [h for h in en_viejas if h.familia == fam]
                    exceso = len(nf) - len(vf)
                    if exceso <= 0:
                        continue
                    # Primero los que no se parecen a ninguno de los que se quitaron:
                    # son los que de verdad llegaron nuevos.
                    firmas_viejas = [h.firma for h in vf]
                    sin_par = []
                    for h in nf:
                        if h.firma in firmas_viejas:
                            firmas_viejas.remove(h.firma)
                        else:
                            sin_par.append(h)
                    elegidos = (sin_par + [h for h in nf if h not in sin_par])[:exceso]
                    for h in elegidos:
                        if not con_salida_permitida(lineas, h.linea):
                            todos.append((nuevo, h, lineas[h.linea - 1].strip()))

    if SOLO_RESUMEN:
        cuenta, archivos = {}, {}
        for ruta, h, _ in todos:
            cuenta[h.familia] = cuenta.get(h.familia, 0) + 1
            archivos.setdefault(h.familia, set()).add(ruta)
        for fam in ORDEN_FAMILIAS:
            print("%-8s %4d en %3d archivos" % (fam, cuenta.get(fam, 0), len(archivos.get(fam, ()))))
        return 0

    if not todos:
        return 0

    todos.sort(key=lambda x: (ORDEN_FAMILIAS.index(x[1].familia), x[0], x[1].linea))
    print("")
    print("  \033[31m✗ Este push agrega la receta suelta de piezas que ya tienen componente.\033[0m")
    print("    (ADR 0004 · docs/adr/0004-diseno-unificado.md)")
    vistas = []
    mostradas = 0
    for fam in ORDEN_FAMILIAS:
        grupo = [x for x in todos if x[1].familia == fam]
        if not grupo:
            continue
        titulo, porque = FAMILIAS[fam]
        print("")
        print("    \033[1m%s\033[0m  ·  %d" % (titulo, len(grupo)))
        for ruta, h, linea in grupo:
            if not TODO and mostradas >= 24:
                break
            mostradas += 1
            print("      %s:%d  →  %s" % (ruta, h.linea, h.pieza))
            print("        %s" % (linea if len(linea) <= 110 else linea[:107] + "…"))
        vistas.append((titulo, porque))
    if not TODO and len(todos) > mostradas:
        print("")
        print("    … y %d más." % (len(todos) - mostradas))
    print("")
    for titulo, porque in vistas:
        print("    · %s" % porque)
    print("")
    print("    Si el componente «casi sirve»: se corrige el componente, no se copia la receta.")
    print("    Si de verdad ninguno sirve (un <details>, un papel impreso), dilo ahí mismo, con")
    print("    el motivo, en la línea o en una de las dos de arriba:")
    print("")
    print("      {/* receta-propia: es un <details> y TarjetaInfo no puede serlo */}")
    print("")
    print("    Solo se juzga lo que este push AGREGA; una línea vieja que solo cambió no cuenta.")
    print("    En una urgencia real:  git push --no-verify")
    print("")
    return 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Convierte el Reglamento Interno de Trabajo a un HTML listo para imprimir.

POR QUÉ HTML Y NO .docx
  El ejemplar maquetado solo sirve para tres cosas: firmarlo, presentarlo ante
  la Autoridad Administrativa de Trabajo y entregarlo en papel. Para eso hace
  falta que salga IGUAL en cualquier ordenador — y un .docx depende de que las
  tipografías estén instaladas en la máquina que lo abre. Este HTML las lleva
  incrustadas, así que se abre en cualquier navegador y se imprime a PDF con
  ⌘P sin instalar nada.

DE DÓNDE SALEN LOS COLORES Y LAS TIPOGRAFÍAS
  De `apps/web/app/globals.css` y de la caché de compilación de Next, que es
  donde vive la identidad real de CAYLA. No se copian a mano a este archivo:
  se leen. Si mañana cambia la paleta de la aplicación, este documento la
  hereda al regenerarse — y si se hubieran escrito aquí, no.

USO
  python3 scripts/reglamento-a-html.py                              → el Reglamento
  python3 scripts/reglamento-a-html.py manual-procedimiento-disciplinario
  python3 scripts/reglamento-a-html.py --todos                      → los seis

  El argumento es el nombre del archivo en `docs/`, sin `.md`. Sirve para el
  Reglamento y para los cinco documentos satélite, que comparten la misma
  cabecera —título, razón social, RUC y líneas de «**Clave:** valor»— y por
  eso se maquetan igual.

POR QUÉ EL ÍNDICE SE CONSTRUYE DE DOS MANERAS
  El Reglamento se organiza en TÍTULOS con ARTÍCULOS dentro, y su índice tiene
  dos niveles. Los satélites son documentos planos, con secciones numeradas a
  secas. Un índice de dos niveles sobre un documento plano sale vacío, y uno
  plano sobre el Reglamento sale con 68 entradas sin agrupar: se elige según
  lo que el documento tenga dentro, no según cuál sea.
"""
import base64
import glob
import html
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSS_APP = os.path.join(RAIZ, "apps", "web", "app", "globals.css")

PREDETERMINADO = "reglamento-interno-de-trabajo"

# Los seis documentos del expediente. El Reglamento primero: es el que manda,
# y los otros cinco derivan de él (numeral 47 del propio Reglamento).
TODOS = [
    PREDETERMINADO,
    "manual-procedimiento-disciplinario",
    "politica-prevencion-hostigamiento-sexual",
    "resolucion-designacion-hostigamiento",
    "formato-queja-hostigamiento-sexual",
    "cargo-recepcion-reglamento",
]

# Por debajo de esto, un índice estorba más de lo que ayuda: el cargo de
# recepción cabe en una hoja.
MINIMO_PARA_INDICE = 6


def paleta() -> dict:
    """Lee los colores de la aplicación. Si falta el archivo, para: prefiero no
    generar el documento a generarlo con una identidad inventada."""
    if not os.path.exists(CSS_APP):
        sys.exit(f"No encuentro {CSS_APP}: de ahí salen los colores de CAYLA.")
    t = open(CSS_APP, encoding="utf-8").read()
    c = dict(re.findall(r"--color-([a-z-]+):\s*(#[0-9a-fA-F]{3,8})", t))
    faltan = [k for k in ("crema", "papel", "tinta", "rojo", "sand", "taupe") if k not in c]
    if faltan:
        sys.exit(f"A globals.css le faltan colores: {faltan}")
    return c


def fuentes() -> str:
    """Incrusta EB Garamond y DM Sans desde la caché de Next, con sus
    unicode-range originales: así los acentos y la ñ salen bien."""
    reglas = []
    vistos = set()
    for archivo in glob.glob(os.path.join(RAIZ, "apps/web/.next/**/*.css"), recursive=True):
        texto = open(archivo, encoding="utf-8", errors="ignore").read()
        for m in re.finditer(r"@font-face\s*\{([^}]*)\}", texto):
            bloque = m.group(1)
            fam = re.search(r"font-family:\s*'?([^;']+)'?", bloque)
            src = re.search(r"url\(([^)]*\.woff2)\)", bloque)
            if not fam or not src or "Fallback" in fam.group(1):
                continue
            familia = fam.group(1).strip()
            if familia not in ("EB Garamond", "DM Sans"):
                continue
            # La url es relativa al CSS que la declara («../media/x.woff2»),
            # no absoluta desde /_next. Resolverla mal deja el documento sin
            # tipografías y sin decir por qué.
            ruta = os.path.normpath(os.path.join(os.path.dirname(archivo), src.group(1)))
            if not os.path.exists(ruta) or ruta in vistos:
                continue
            vistos.add(ruta)
            b64 = base64.b64encode(open(ruta, "rb").read()).decode()
            cuerpo = bloque.replace(src.group(0), f"url(data:font/woff2;base64,{b64}) format('woff2')")
            reglas.append("@font-face{" + cuerpo + "}")
    if not reglas:
        sys.exit("No encontré las tipografías compiladas. Corre `npx pnpm build` primero.")
    return "\n".join(reglas)


def en_linea(t: str) -> str:
    """Negritas y cursivas. El resto del markdown se escapa."""
    t = html.escape(t)
    t = re.sub(r"\\_", "_", t)
    t = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", t)
    t = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<em>\1</em>", t)
    return t


def cuerpo_html(md: str) -> tuple:
    """Devuelve (portada, indice, articulado)."""
    partes = md.split("\n---\n", 2)
    cabecera = partes[0]
    # El Reglamento lleva un índice ESCRITO A MANO entre su primer y su segundo
    # «---». Ese bloque se descarta a propósito, porque `indice()` lo reconstruye
    # del articulado. Los satélites no tienen índice escrito: ahí el segundo
    # bloque es su PRIMERA SECCIÓN, y descartarlo la borraba del documento
    # impreso sin decir nada — el cargo de recepción salía sin su tabla de
    # firma, y el formato de queja sin el aviso de que no es obligatorio. Por
    # eso se decide mirando si ese bloque es el índice, no contando separadores.
    if len(partes) > 2 and re.match(r"\s*##\s+Índice\s*$", partes[1].split("\n\n")[0]):
        resto = partes[2]
    else:
        resto = "\n---\n".join(partes[1:]) if len(partes) > 1 else md

    # ── Portada, de las líneas «**Clave:** valor» de la cabecera ────────────
    datos = re.findall(r"\*\*([^*]+):\*\*\s*(.+)", cabecera)
    version = re.search(r"\*\*Versión ([\d.]+)\*\*\s*—\s*(.+)", cabecera)
    nota = re.findall(r"(?m)^>\s?(.*)$", cabecera)
    # La razón social y el RUC van SIEMPRE, y aparte: son la línea que
    # identifica el documento ante la autoridad, y en el markdown no llevan
    # dos puntos, así que el barrido de «**Clave:** valor» no las veía.
    razon = re.search(r"\*\*(CAYLA[^*]*)\*\*\s*·\s*(RUC[^\n]*)", cabecera)
    # El título sale del propio documento, del «# » de su primera línea. Antes
    # estaba escrito aquí, y con eso los cinco satélites habrían salido todos
    # titulados «Reglamento Interno de Trabajo».
    h1 = re.search(r"(?m)^#\s+(.+)$", cabecera)
    titulo = h1.group(1).strip() if h1 else "Documento"
    portada = ['<section class="portada">',
               '<div class="marca">CAYLA</div>',
               f'<h1>{en_linea(titulo)}</h1>']
    if razon:
        portada.append(f'<p class="razon">{html.escape(razon.group(1).strip())}'
                       f'<span>{html.escape(razon.group(2).strip())}</span></p>')
    if version:
        portada.append(f'<p class="version">Versión {version.group(1)} · {en_linea(version.group(2))}</p>')
    portada.append('<dl class="ficha">')
    for k, v in datos:
        if k.startswith("Versión"):
            continue
        portada.append(f"<dt>{html.escape(k)}</dt><dd>{en_linea(v)}</dd>")
    portada.append("</dl>")
    if nota:
        portada.append('<p class="sustituye">' + en_linea(" ".join(n for n in nota if n.strip())) + "</p>")
    portada.append("</section>")

    # ── Articulado ──────────────────────────────────────────────────────────
    salida, buffer_cita, buffer_tabla = [], [], []
    def cerrar_cita():
        if buffer_cita:
            salida.append("<blockquote>" + " ".join(buffer_cita) + "</blockquote>")
            buffer_cita.clear()

    def cerrar_tabla():
        """Una tabla de markdown, a <table>. Sin esto sus filas salían como
        párrafos con las barras a la vista («| **Nombre y apellidos** | |»), que
        en un cargo que se firma a mano es la casilla donde va el nombre."""
        if not buffer_tabla:
            return
        filas = [[c.strip() for c in f.strip().strip("|").split("|")]
                 for f in buffer_tabla
                 if not re.fullmatch(r"[\s|:-]+", f)]
        buffer_tabla.clear()
        if not filas:
            return
        cuerpo = []
        for f in filas:
            celdas = "".join(f'<td>{en_linea(c)}</td>' for c in f)
            cuerpo.append(f"<tr>{celdas}</tr>")
        salida.append('<table class="campos">' + "".join(cuerpo) + "</table>")

    for linea in resto.split("\n"):
        t = linea.rstrip()
        if t.lstrip().startswith("|"):
            cerrar_cita(); buffer_tabla.append(t.lstrip()); continue
        cerrar_tabla()
        if not t.strip():
            cerrar_cita(); continue
        if t.strip() == "---":
            cerrar_cita(); continue
        if t.startswith("> "):
            buffer_cita.append(en_linea(t[2:])); continue
        cerrar_cita()
        if t.startswith("## TÍTULO"):
            texto = t[3:].strip()
            rom, _, nom = texto.partition("—")
            salida.append(f'<h2 class="titulo"><span class="rom">{html.escape(rom.strip())}</span>'
                          f'<span class="nom">{html.escape(nom.strip())}</span></h2>')
        elif t.startswith("## "):
            salida.append(f'<h2 class="seccion">{en_linea(t[3:])}</h2>')
        elif t.startswith("### "):
            salida.append(f"<h3>{en_linea(t[4:])}</h3>")
        elif t.startswith("# "):
            continue
        else:
            salida.append(f"<p>{en_linea(t)}</p>")
    cerrar_cita()
    cerrar_tabla()
    return "\n".join(portada), titulo, "\n".join(salida)


def indice(articulado: str) -> str:
    """Se construye recorriendo el articulado ya montado. Copiarlo del markdown
    lo dejaría desactualizado el día que se inserte un artículo.

    Dos formas, según lo que el documento tenga dentro: de dos niveles cuando
    hay TÍTULOS, y plano cuando solo hay secciones. Se decide mirando el texto
    y no el nombre del archivo, porque el día que un satélite crezca hasta
    tener títulos, hereda el índice bueno sin tocar nada."""
    if '<h2 class="titulo">' not in articulado:
        return indice_plano(articulado)
    filas, titulo = [], None
    for m in re.finditer(r'<h2 class="titulo"><span class="rom">([^<]*)</span>'
                         r'<span class="nom">([^<]*)</span></h2>|<h3>([^<]*)</h3>', articulado):
        if m.group(1) is not None:
            if titulo:
                filas.append(titulo)
            titulo = {"rom": m.group(1), "nom": m.group(2), "arts": []}
        elif titulo is not None:
            t = re.sub(r"^ARTÍCULO\s+", "", m.group(3)).replace(".-", ".", 1)
            titulo["arts"].append(t)
    if titulo:
        filas.append(titulo)
    out = ['<section class="indice"><h2 class="seccion">Índice</h2>']
    for f in filas:
        out.append(f'<div class="idx-tit"><span>{f["rom"]}</span> {f["nom"]}</div>')
        out.append('<ul class="idx-arts">' +
                   "".join(f"<li>{a}</li>" for a in f["arts"]) + "</ul>")
    out.append("</section>")
    return "\n".join(out)


def indice_plano(articulado: str) -> str:
    """El índice de un documento sin títulos: una entrada por sección.

    Devuelve cadena vacía si hay pocas secciones. Un índice de tres líneas
    sobre un documento de dos páginas ocupa más de lo que orienta."""
    secciones = re.findall(r'<h2 class="seccion">([^<]*)</h2>', articulado)
    if len(secciones) < MINIMO_PARA_INDICE:
        return ""
    out = ['<section class="indice"><h2 class="seccion">Índice</h2>',
           '<ul class="idx-arts idx-plano">']
    out += [f"<li>{s}</li>" for s in secciones]
    out.append("</ul></section>")
    return "\n".join(out)


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    if "--todos" in sys.argv:
        for slug in TODOS:
            generar(slug)
        return
    generar(args[0] if args else PREDETERMINADO)


def generar(slug: str) -> None:
    slug = slug.removesuffix(".md")
    ruta = os.path.join(RAIZ, "docs", slug + ".md")
    salida = os.path.join(RAIZ, "docs", slug + ".html")
    if not os.path.exists(ruta):
        sys.exit(f"No encuentro {ruta}.")
    md = open(ruta, encoding="utf-8").read()
    c = paleta()
    portada, titulo, articulado = cuerpo_html(md)
    # El mismo tratamiento que recibe el <h1>, y por la misma razón: al título
    # le llegan las barras de escape del markdown (`\_\_\_\_`) y le podría
    # llegar un «&» o un «<», que en el <head> no rompen a la vista — rompen
    # el documento entero sin decir nada.
    titulo = re.sub(r"<[^>]+>", "", en_linea(titulo))

    doc = f"""<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<title>{titulo} — CAYLA S.A.C.</title>
<style>
{fuentes()}

:root {{
  --crema: {c['crema']}; --papel: {c['papel']}; --tinta: {c['tinta']};
  --rojo: {c['rojo']}; --rojo-hondo: {c.get('rojo-profundo', c['rojo'])};
  --sand: {c['sand']}; --taupe: {c['taupe']};
}}
* {{ box-sizing: border-box; }}
html {{ background: var(--sand); }}
body {{
  margin: 0; background: var(--papel); color: var(--tinta);
  font-family: 'EB Garamond', Georgia, serif;
  font-size: 11.2pt; line-height: 1.62; text-align: justify;
  hyphens: auto; -webkit-hyphens: auto;
}}
.hoja {{ max-width: 17.4cm; margin: 0 auto; padding: 2.4cm 0 3cm; }}

/* ── Portada ─────────────────────────────────────────────────────────── */
.portada {{
  background: var(--crema); margin: -2.4cm -2cm 2.4cm; padding: 4.5cm 2.6cm 3.4cm;
  border-bottom: 3px solid var(--rojo); text-align: left;
}}
.marca {{
  font-family: 'DM Sans', system-ui, sans-serif; font-weight: 500;
  letter-spacing: .42em; font-size: 10pt; color: var(--rojo); margin-bottom: 2.6cm;
}}
.portada h1 {{
  font-family: 'EB Garamond', Georgia, serif; font-weight: 500;
  font-size: 30pt; line-height: 1.1; margin: 0 0 .5cm; color: var(--tinta);
}}
.razon {{
  font-family: 'DM Sans', system-ui, sans-serif; font-size: 11pt; font-weight: 500;
  margin: 0 0 .18cm; color: var(--tinta);
}}
.razon span {{ display: block; font-weight: 400; font-size: 9.4pt; color: var(--taupe); margin-top: .08cm; }}
.version {{
  font-family: 'DM Sans', system-ui, sans-serif; font-size: 9.6pt;
  color: var(--rojo-hondo); margin: 0 0 2.2cm; letter-spacing: .02em;
}}
.ficha {{ display: grid; grid-template-columns: 4.6cm 1fr; gap: .34cm 0; margin: 0 0 1.6cm; }}
.ficha dt {{
  font-family: 'DM Sans', system-ui, sans-serif; font-size: 8.4pt;
  text-transform: uppercase; letter-spacing: .1em; color: var(--taupe); padding-top: .07cm;
}}
.ficha dd {{ margin: 0; font-size: 10.6pt; }}
.sustituye {{
  border-left: 2px solid var(--rojo); padding-left: .55cm; margin: 0;
  font-size: 9.8pt; color: var(--taupe); text-align: left;
}}

/* ── Títulos y artículos ─────────────────────────────────────────────── */
h2.titulo {{
  break-before: page; page-break-before: always;
  margin: 0 0 1.1cm; padding-bottom: .28cm; border-bottom: 2px solid var(--rojo);
  font-family: 'DM Sans', system-ui, sans-serif; font-weight: 500;
}}
h2.titulo .rom {{
  display: block; font-size: 8.6pt; letter-spacing: .2em;
  text-transform: uppercase; color: var(--rojo); margin-bottom: .12cm;
}}
h2.titulo .nom {{ display: block; font-size: 15pt; color: var(--tinta); letter-spacing: -.01em; }}
h2.seccion {{
  break-before: page; page-break-before: always;
  font-family: 'DM Sans', system-ui, sans-serif; font-weight: 500; font-size: 13pt;
  color: var(--rojo); border-bottom: 1px solid var(--sand);
  padding-bottom: .2cm; margin: 0 0 .8cm;
}}
h3 {{
  font-family: 'DM Sans', system-ui, sans-serif; font-weight: 500; font-size: 10.4pt;
  letter-spacing: .012em; color: var(--tinta); margin: .95cm 0 .3cm;
  break-after: avoid; page-break-after: avoid;
}}
p {{ margin: 0 0 .42cm; orphans: 3; widows: 3; }}
strong {{ font-weight: 600; }}
blockquote {{
  margin: .5cm 0; padding: .34cm .6cm; background: var(--crema);
  border-left: 2px solid var(--sand); font-size: 10.2pt; color: var(--taupe);
  text-align: left; break-inside: avoid;
}}

/* ── Tablas de campos ────────────────────────────────────────────────────
   Son casillas que se rellenan a mano, no cuadros de datos: por eso la
   segunda columna va vacía y ancha, y la fila entera no se parte de página. */
table.campos {{
  width: 100%; border-collapse: collapse; margin: .6cm 0 .7cm;
  font-size: 10.6pt; text-align: left; break-inside: avoid;
}}
table.campos td {{
  border: 1px solid var(--sand); padding: .3cm .34cm;
  vertical-align: bottom; text-align: left;
}}
table.campos td:first-child {{ width: 7.4cm; color: var(--taupe); }}
table.campos tr {{ break-inside: avoid; }}

/* ── Índice ─────────────────────────────────────────────────────────── */
.indice {{ break-after: page; page-break-after: always; }}
.indice .seccion {{ break-before: auto; page-break-before: auto; }}
.idx-tit {{
  font-family: 'DM Sans', system-ui, sans-serif; font-size: 9.4pt; font-weight: 500;
  margin: .55cm 0 .12cm; color: var(--tinta); break-after: avoid;
}}
.idx-tit span {{ color: var(--rojo); letter-spacing: .08em; margin-right: .2cm; }}
.idx-arts {{
  list-style: none; margin: 0 0 0 .5cm; padding: 0;
  font-size: 9.6pt; color: var(--taupe); columns: 2; column-gap: 1cm;
}}
.idx-arts li {{ margin: 0 0 .1cm; break-inside: avoid; text-align: left; }}

/* ── Impresión ───────────────────────────────────────────────────────── */
@page {{ size: A4; margin: 18mm 20mm 20mm; }}
@media print {{
  html, body {{ background: #fff; }}
  .hoja {{ max-width: none; padding: 0; }}
  .portada {{ margin: -18mm -20mm 1.4cm; padding: 5cm 20mm 3cm; break-after: page; }}
  .aviso {{ display: none; }}
}}

/* ── Aviso, solo en pantalla ─────────────────────────────────────────── */
.aviso {{
  position: fixed; right: 1rem; bottom: 1rem; max-width: 21rem; z-index: 9;
  background: var(--tinta); color: var(--crema); padding: .8rem 1rem;
  border-radius: .55rem; font-family: 'DM Sans', system-ui, sans-serif;
  font-size: .78rem; line-height: 1.5; text-align: left;
}}
.aviso b {{ color: #fff; }}
</style></head>
<body>
<div class="hoja">
{portada}
{indice(articulado)}
{articulado}
</div>
<div class="aviso">
  <b>Para el PDF:</b> ⌘P → Destino «Guardar como PDF». Activa
  «Encabezados y pies de página» si quieres la numeración del navegador.
  Las tipografías van incrustadas: sale igual en cualquier ordenador.
</div>
</body></html>"""
    open(salida, "w", encoding="utf-8").write(doc)
    print(f"→ {os.path.relpath(salida, RAIZ)}  ({len(doc)/1024:.0f} KB)")


if __name__ == "__main__":
    main()

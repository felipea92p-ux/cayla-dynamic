// Formidable · oficio visual — se pega ENTERO en `javascript_tool` con la pantalla ya cargada (panel visible: oculto mide 0).
// Devuelve un objeto con lo que FALLA (etiqueta: Medido). No toca la página. Umbrales y fuentes: referencia/oficio-visual.md.
(() => {
  if (!innerWidth || !innerHeight) return { error: 'El panel está oculto: la página mide 0×0 y toda medición sería falsa. Ábrelo y repite.' };
  const px = (v) => Math.round(v * 10) / 10;
  const vis = (el) => {
    const r = el.getBoundingClientRect(), s = getComputedStyle(el);
    return r.width > 0 && r.height > 0 && s.display !== 'none' && s.visibility !== 'hidden' && s.opacity !== '0';
  };
  const todos = [...document.body.querySelectorAll('*')].filter(vis);
  const marca = (el) => (el.getAttribute('aria-label') || el.textContent || el.tagName).trim().replace(/\s+/g, ' ').slice(0, 40);
  const pista = (el) => `${el.tagName.toLowerCase()}${el.className && typeof el.className === 'string' ? '.' + el.className.trim().split(/\s+/)[0] : ''} «${marca(el)}»`;

  // ── 1-2 · blancos de puntero (24 mínimo / 32 objetivo con mouse; 44 con dedo)
  const tactil = matchMedia('(pointer: coarse)').matches;
  const minimo = tactil ? 44 : 24, objetivo = tactil ? 44 : 32;
  const interactivos = todos.filter((e) => e.matches('a[href],button,input:not([type=hidden]),select,textarea,[role=button],[role=tab],[role=menuitem],[role=checkbox],[role=switch],[tabindex]:not([tabindex="-1"])'));
  // Un enlace o botón EN LÍNEA dentro de una frase está exento (WCAG 2.5.8): no se cuenta como blanco pequeño.
  const enLinea = (e) => /^inline/.test(getComputedStyle(e).display) && [...(e.parentElement?.childNodes || [])].some((n) => n.nodeType === 3 && n.textContent.trim().length > 3);
  const blancos = interactivos.filter((e) => !enLinea(e)).map((e) => ({ e, r: e.getBoundingClientRect() }));
  const blancosBajoMinimo = blancos.filter(({ r }) => Math.min(r.width, r.height) < minimo).slice(0, 12).map(({ e, r }) => `${pista(e)} ${px(r.width)}×${px(r.height)}`);
  const blancosBajoObjetivo = blancos.filter(({ r }) => Math.min(r.width, r.height) >= minimo && r.height < objetivo).length;

  // ── 3 · contraste del texto contra su fondo real (aprox.: compone alfa hacia arriba; ignora imágenes de fondo)
  // Chrome devuelve oklab(...), color-mix(...) y otros formatos que un regex no lee (un piloto marcó 67 falsos contrastes de 1,1:1):
  // se convierte TODO color por un canvas de 1×1, que sí los entiende, a {r,g,b,a} en sRGB.
  const cx = Object.assign(document.createElement('canvas'), { width: 1, height: 1 }).getContext('2d', { willReadFrequently: true }), memo = new Map();
  const rgba = (c) => {
    if (!memo.has(c)) { cx.clearRect(0, 0, 1, 1); cx.fillStyle = '#000'; cx.fillStyle = c; cx.fillRect(0, 0, 1, 1); const d = cx.getImageData(0, 0, 1, 1).data; memo.set(c, { r: d[0], g: d[1], b: d[2], a: d[3] / 255 }); }
    return memo.get(c);
  };
  const sobre = (f, b) => ({ r: f.r * f.a + b.r * (1 - f.a), g: f.g * f.a + b.g * (1 - f.a), b: f.b * f.a + b.b * (1 - f.a), a: 1 });
  const lum = ({ r, g, b }) => { const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; }; return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b); };
  const fondo = (el) => {
    const pila = []; let n = el, imagen = false;
    while (n && n.nodeType === 1) { const s = getComputedStyle(n); if (s.backgroundImage !== 'none') imagen = true; pila.push(rgba(s.backgroundColor)); n = n.parentElement; }
    let acc = { r: 255, g: 255, b: 255, a: 1 };
    for (let i = pila.length - 1; i >= 0; i--) acc = sobre(pila[i], acc);
    return { acc, imagen };
  };
  const conTexto = todos.filter((e) => [...e.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim()));
  const pocoContraste = [];
  for (const e of conTexto) {
    const s = getComputedStyle(e), { acc, imagen } = fondo(e);
    if (imagen) continue;
    const fg = sobre(rgba(s.color), acc), L1 = lum(fg), L2 = lum(acc);
    const ratio = (Math.max(L1, L2) + 0.05) / (Math.min(L1, L2) + 0.05);
    const grande = parseFloat(s.fontSize) >= 24 || (parseFloat(s.fontSize) >= 18.66 && parseInt(s.fontWeight) >= 700);
    if (ratio < (grande ? 3 : 4.5)) pocoContraste.push(`${pista(e)} ${ratio.toFixed(2)}:1`);
  }

  // ── 6 · tamaños de texto
  const tamanos = {};
  conTexto.forEach((e) => { const t = Math.round(parseFloat(getComputedStyle(e).fontSize)); tamanos[t] = (tamanos[t] || 0) + 1; });
  const textoChico = conTexto.filter((e) => parseFloat(getComputedStyle(e).fontSize) < 12).slice(0, 10).map((e) => `${pista(e)} ${getComputedStyle(e).fontSize}`);

  // ── 7 · alineación: dos bordes izquierdos que «casi» coinciden (1–3 px) son un defecto
  const lefts = {};
  [...conTexto, ...interactivos].filter((e) => getComputedStyle(e).display !== 'inline').forEach((e) => { const l = Math.round(e.getBoundingClientRect().left); (lefts[l] ||= []).push(e); });
  const ls = Object.keys(lefts).map(Number).sort((a, b) => a - b), casi = [];
  for (let i = 0; i < ls.length; i++) for (let j = i + 1; j < ls.length && ls[j] - ls[i] <= 3; j++)
    if (ls[j] - ls[i] >= 1 && (lefts[ls[i]].length >= 2 || lefts[ls[j]].length >= 2))
      casi.push(`${ls[i]}px(${lefts[ls[i]].length}) vs ${ls[j]}px(${lefts[ls[j]].length}): ${pista((lefts[ls[i]].length < lefts[ls[j]].length ? lefts[ls[i]] : lefts[ls[j]])[0])}`);

  // ── 8 · espaciado vertical entre hermanos: múltiplo de 2 px (Tailwind v4: pasos de 4 px y medios pasos de 2, 6, 10, 14)
  const huecos = {};
  todos.forEach((p) => {
    const hijos = [...p.children].filter((c) => vis(c) && getComputedStyle(c).position !== 'absolute' && getComputedStyle(c).display !== 'inline' && c.getBoundingClientRect().height >= 12);
    for (let i = 1; i < hijos.length; i++) {
      const g = hijos[i].getBoundingClientRect().top - hijos[i - 1].getBoundingClientRect().bottom;
      if (g > 0.5 && g <= 64 && Math.abs(g / 2 - Math.round(g / 2)) > 0.12) { const k = px(g); huecos[k] = (huecos[k] || 0) + 1; }
    }
  });

  // ── 10 · alturas desiguales en una misma fila de controles + radios distintos
  const filas = {};
  blancos.filter(({ e }) => e.matches('button,input,select,[role=button]')).forEach(({ e, r }) => { (filas[Math.round((r.top + r.height / 2) / 8)] ||= []).push(r.height); });
  const filasDesiguales = Object.values(filas).filter((h) => h.length > 1 && Math.max(...h) - Math.min(...h) > 2).length;
  const radios = new Set();
  todos.forEach((e) => { const rd = getComputedStyle(e).borderTopLeftRadius; if (rd && rd !== '0px' && e.getBoundingClientRect().width > 24) radios.add(rd); });

  // ── 11 · rojo (token --color-rojo #b8412d y rojo-profundo #8b2a1f): máx. 2 por pantalla
  const esRojo = (c) => { const k = rgba(c); return k.a > 0.5 && [[184, 65, 45], [139, 42, 31]].some(([r, g, b]) => Math.abs(k.r - r) <= 2 && Math.abs(k.g - g) <= 2 && Math.abs(k.b - b) <= 2); };
  const rojos = todos.filter((e) => { const s = getComputedStyle(e); return esRojo(s.color) && [...e.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim()) || esRojo(s.backgroundColor) || esRojo(s.borderTopColor) && parseFloat(s.borderTopWidth) > 0; });

  // ── 13 · sombras y 2 · acción primaria
  const sombras = todos.filter((e) => getComputedStyle(e).boxShadow !== 'none').length;
  const primarias = todos.filter((e) => e.matches('button.bg-tinta, a.bg-tinta')).length;

  const fallas = {
    blancosBajoMinimo: blancosBajoMinimo.length, pocoContraste: pocoContraste.length, textoChico: textoChico.length,
    bordesCasiAlineados: casi.length, huecosFueraDeEscala: Object.keys(huecos).length, filasConAlturasDesiguales: filasDesiguales,
    radiosDistintosSobre3: radios.size > 3 ? radios.size : 0, rojosSobre2: rojos.length > 2 ? rojos.length : 0,
  };
  return {
    viewport: { ancho: innerWidth, alto: innerHeight, puntero: tactil ? 'grueso (44 px)' : 'fino (24 mín, 32 objetivo)' },
    fallasPorComprobacion: fallas,
    comprobacionesQueFallan: Object.values(fallas).filter(Boolean).length, de: Object.keys(fallas).length,
    detalle: {
      blancosBajoMinimo, blancosBajoObjetivo, pocoContraste: pocoContraste.slice(0, 12), textoChico,
      tamanosDeTexto: tamanos, tamanosDistintos: Object.keys(tamanos).length,
      bordesCasiAlineados: casi.slice(0, 12), huecosFueraDeEscala: huecos, radios: [...radios],
      rojosVisibles: rojos.length, sombras, accionesPrimarias: primarias,
    },
    nota: 'Medido. Faltan a mano (Observado): foco con Tab, Enter/Esc, jerarquía y colores sueltos en el código.',
  };
})()

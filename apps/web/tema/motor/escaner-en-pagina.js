// El escáner que corre DENTRO de la página (lo inyecta `cli.mjs` con `addScriptTag`). Define `window.__temaEscanear()`. Traído de CAYLA Retail.
// Mide en el tema que esté puesto en <html data-tema>: (1) el contraste WCAG de cada texto contra su fondo REAL —compuesto capa
// por capa—, y el de cada símbolo gráfico («›», «·») contra el piso de un gráfico; (2) «manchas claras»: superficies grandes que en
// oscuro siguen claras y no son un documento ni un relleno invertido a propósito; (3) «velos claros»: una capa fija que cubre la pantalla
// y en oscuro la aclara en vez de oscurecerla.
// Solo ve colores planos: un degradado o una imagen se cuentan en `sobreDegradado` y los mide `tests/vidrio-contraste.test.ts`.
// No lleva `export`: es un script clásico para que `addScriptTag({ content })` lo evalúe tal cual.

(() => {
  const lienzo = document.createElement("canvas");
  lienzo.width = lienzo.height = 1;
  const ctx = lienzo.getContext("2d", { willReadFrequently: true });
  const memo = new Map();

  /** Cualquier color CSS (rgb, color-mix, oklab…) → [r,g,b,a]. Pinta el color sobre negro y sobre blanco y despeja el alfa:
   *  sobre negro = a·C, sobre blanco = a·C + (1−a)·255 (`getImageData` ya devuelve sin premultiplicar, y así no se pierde precisión). */
  function leer(css) {
    if (memo.has(css)) return memo.get(css);
    const sobreFondo = (fondo) => {
      ctx.globalCompositeOperation = "source-over";
      ctx.fillStyle = fondo;
      ctx.fillRect(0, 0, 1, 1);
      ctx.fillStyle = css;
      ctx.fillRect(0, 0, 1, 1);
      return ctx.getImageData(0, 0, 1, 1).data;
    };
    const n = sobreFondo("#000");
    const b = sobreFondo("#fff");
    const a = 1 - (b[0] - n[0] + (b[1] - n[1]) + (b[2] - n[2])) / (3 * 255);
    const r = a <= 0.004 ? [0, 0, 0, 0] : [Math.min(255, n[0] / a), Math.min(255, n[1] / a), Math.min(255, n[2] / a), Math.min(1, a)];
    memo.set(css, r);
    return r;
  }
  const sobre = ([r, g, b, a], [R, G, B, A]) => {
    const sal = a + A * (1 - a);
    return sal === 0 ? [0, 0, 0, 0] : [(r * a + R * A * (1 - a)) / sal, (g * a + G * A * (1 - a)) / sal, (b * a + B * A * (1 - a)) / sal, sal];
  };
  const canal = (c) => {
    const x = c / 255;
    return x <= 0.03928 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4;
  };
  const lum = ([r, g, b]) => 0.2126 * canal(r) + 0.7152 * canal(g) + 0.0722 * canal(b);
  const contraste = (a, b) => {
    const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p);
    return (x + 0.05) / (y + 0.05);
  };
  const hex = ([r, g, b]) => "#" + [r, g, b].map((v) => Math.round(v).toString(16).padStart(2, "0")).join("");

  const RUIDO = /^(h-|w-|px-|py-|p-|m|gap|flex|grid|items|justify|min-|max-|sm:|lg:|md:|xl:|text-(xs|sm|base|lg|\[)|font|leading|tracking|truncate|whitespace|relative|absolute|anim-|transition|duration|ease|cursor|select|overflow|shrink|grow|basis|col-|row-|space-|divide-|order-|z-|inset|top-|left-|right-|bottom-|size-|aspect-|tabular|sr-only|hidden|block|inline|border(-[trblxy])?$|rounded|shadow|opacity|group|peer|data-|aria-|\[)/;
  function camino(el) {
    const partes = [];
    for (let e = el; e && e.nodeType === 1 && partes.length < 4; e = e.parentElement) {
      const c = [...e.classList].filter((k) => !RUIDO.test(k)).slice(0, 3);
      partes.unshift(e.tagName.toLowerCase() + (c.length ? "." + c.join(".") : ""));
    }
    return partes.join(" > ");
  }

  function fondoDeLaPagina() {
    const h = leer(getComputedStyle(document.documentElement).backgroundColor);
    const b = leer(getComputedStyle(document.body).backgroundColor);
    let f = b[3] > 0 ? b : h;
    if (f[3] < 0.999) f = sobre(f, [255, 255, 255, 1]);
    return f;
  }

  /**
   * El fondo efectivo de un elemento: sus capas de color, de adentro hacia afuera, sobre el fondo de la página.
   * Con `punto` (el centro del texto) usa el ORDEN REAL DE PINTURA (`elementsFromPoint`) en vez de recorrer solo los ancestros:
   * la píldora activa de un control segmentado es un elemento que se desliza DETRÁS del botón, no su ancestro, y mirando solo
   * ancestros el texto parecía estar sobre el fondo del contenedor (falsos 1.3:1). Sin punto (fuera de pantalla), solo ancestros.
   */
  function fondoEfectivo(el, punto) {
    let acum = [0, 0, 0, 0];
    let hayImagen = false;
    let capas = null;
    if (punto && punto[0] >= 0 && punto[1] >= 0 && punto[0] < innerWidth && punto[1] < innerHeight) {
      const pila = document.elementsFromPoint(punto[0], punto[1]);
      const i = pila.indexOf(el);
      if (i >= 0) capas = pila.slice(i); // lo que está en el elemento y POR DEBAJO de él
    }
    if (capas) {
      for (const e of capas) {
        const cs = getComputedStyle(e);
        if (cs.backgroundImage !== "none") hayImagen = true;
        const c = leer(cs.backgroundColor);
        if (c[3] > 0) acum = sobre(acum, c);
        if (acum[3] >= 0.999) break;
      }
      if (acum[3] < 0.999) acum = sobre(acum, fondoDeLaPagina());
      return { fondo: acum, hayImagen };
    }
    for (let e = el; e; e = e.parentElement) {
      const cs = getComputedStyle(e);
      if (cs.backgroundImage !== "none") hayImagen = true;
      const c = leer(cs.backgroundColor);
      if (c[3] > 0) acum = sobre(acum, c);
      if (acum[3] >= 0.999) break;
    }
    if (acum[3] < 0.999) acum = sobre(acum, fondoDeLaPagina());
    return { fondo: acum, hayImagen };
  }

  function opacidadHeredada(el) {
    let o = 1;
    for (let e = el; e; e = e.parentElement) o *= parseFloat(getComputedStyle(e).opacity);
    return o;
  }

  /** Un control deshabilitado queda exento de contraste (WCAG 1.4.3). */
  const deshabilitado = (el) => !!el.closest(":disabled, [aria-disabled='true'], [data-disabled]");

  /**
   * Un símbolo que el código le ocultó al lector y que no trae ni una letra ni un dígito («›», «→», «·», «×») es un GRÁFICO, no texto:
   * su piso es 3:1 (WCAG 1.4.11), no el 4.5:1 del texto (un adorno puro ni siquiera tiene exigencia, WCAG 1.4.3). Sigue siendo texto:
   *  · lo que tiene letras o dígitos, aunque esté oculto. Se mira la pieza entera y no el nodo: React parte «+{n}» en «+» y «30».
   *  · una tecla (`<kbd>`, el «⌘K» del buscador): dice qué apretar, y se lee.
   */
  const esGrafico = (el) =>
    !/[\p{L}\p{N}]/u.test(el.textContent) && !el.closest("kbd") && !!el.closest('[aria-hidden="true"]');

  window.__temaEscanear = function escanear({ minimo = 4.5 } = {}) {
    const tema = document.documentElement.getAttribute("data-tema") || "(sin atributo)";
    // Para `elementsFromPoint`: que cuenten también los elementos con `pointer-events: none` (como una píldora decorativa).
    const abrirPunteros = document.createElement("style");
    abrirPunteros.textContent = "* { pointer-events: auto !important; }";
    document.head.appendChild(abrirPunteros);
    const contrastes = [];
    const vistos = new Set();
    let analizados = 0;
    let sobreDegradado = 0;

    const textos = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
      acceptNode: (n) => (n.nodeValue.trim() && n.parentElement && !/^(SCRIPT|STYLE|NOSCRIPT)$/.test(n.parentElement.tagName) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT),
    });
    for (let n = textos.nextNode(); n; n = textos.nextNode()) {
      const el = n.parentElement;
      const cs = getComputedStyle(el);
      if (cs.visibility === "hidden" || cs.display === "none") continue;
      const caja = el.getBoundingClientRect();
      if (caja.width < 2 || caja.height < 2) continue;
      if (parseFloat(cs.fontSize) < 1 || deshabilitado(el)) continue;
      const op = opacidadHeredada(el);
      if (op < 0.05) continue;
      const rango = document.createRange();
      rango.selectNodeContents(n);
      const caja2 = rango.getBoundingClientRect();
      // Una letra sin color propio la pinta un degradado recortado a su forma (`background-clip: text`, el «transforma.» del login). Medirla como
      // tinta transparente da un 1:1 falso, y un falso positivo enseña a no creerle al medidor: se cuenta como lo que no se puede medir aquí.
      const relleno = cs.webkitTextFillColor || cs.color;
      if (leer(relleno)[3] === 0) {
        analizados++;
        sobreDegradado++;
        continue;
      }
      const { fondo, hayImagen } = fondoEfectivo(el, [caja2.left + caja2.width / 2, caja2.top + caja2.height / 2]);
      let tinta = leer(relleno);
      tinta = sobre([tinta[0], tinta[1], tinta[2], tinta[3] * op], fondo);
      const ratio = contraste(tinta, fondo);
      analizados++;
      if (hayImagen) sobreDegradado++;
      const px = parseFloat(cs.fontSize);
      const grande = px >= 24 || (px >= 18.66 && parseInt(cs.fontWeight, 10) >= 700);
      const grafico = esGrafico(el);
      // El texto grande (WCAG 1.4.3) y el gráfico (WCAG 1.4.11) comparten el piso de 3:1.
      const umbral = grande || grafico ? 3 : minimo;
      if (ratio >= umbral) continue;
      const donde = camino(el);
      const texto = n.nodeValue.trim().slice(0, 40);
      const clave = `${donde}|${texto}|${hex(tinta)}|${hex(fondo)}`;
      if (vistos.has(clave)) continue;
      vistos.add(clave);
      contrastes.push({ tipo: "contraste", clave: `${donde}|${texto}`, ratio: +ratio.toFixed(2), umbral, ...(grafico && { grafico }), texto, color: hex(tinta), fondo: hex(fondo), imagen: hayImagen, donde });
    }

    const manchas = [];
    const manchasExentas = [];
    const velos = [];
    if (tema === "oscuro") {
      const pagina = fondoDeLaPagina();
      // Claras a propósito, según `globals.css`: los documentos (`.hoja`, `.contrato`) y el recuadro de la firma (`.firma-tinta`). No cuentan como
      // defecto, pero se anotan aparte en vez de callarlos: en pantalla un documento sigue el tema, así que algo claro ahí dentro merece una mirada.
      // La imagen de `.contrato .linea img` ya queda fuera por ser una imagen, y el recuadro de `--color-crema-fija` por ser un token.
      const CLARAS_A_PROPOSITO = ".hoja, .contrato, .firma-tinta";
      // Una superficie clara que ES un token del sistema (el relleno de `tinta` invertido, el verde de «hecho», la crema fija…) es una decisión
      // del diseño; un blanco escrito a mano NO coincide con ningún token. Se recogen los `--color-*` de las hojas.
      const raiz = getComputedStyle(document.documentElement);
      const nombres = new Set();
      // Tailwind publica su propia paleta (`--color-white`, `--color-gray-100`…): NO son tokens de CAYLA, y un `bg-white` coincidiría con ella.
      const PALETA_DE_TAILWIND = /^--color-(white|black|(slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose)-\d+)$/;
      // Los tokens viven DENTRO de `@layer theme { … }` y de `@media screen { … }`: hay que bajar por los grupos de reglas.
      const recorrer = (reglas) => {
        for (const regla of reglas) {
          if (regla.style) for (const prop of regla.style) if (prop.startsWith("--color-") && !PALETA_DE_TAILWIND.test(prop)) nombres.add(prop);
          if (regla.cssRules) recorrer(regla.cssRules);
        }
      };
      for (const hoja of document.styleSheets) {
        try {
          recorrer(hoja.cssRules);
        } catch {
          /* hoja de otro origen: no se puede leer */
        }
      }
      const tokens = [...nombres].map((n) => leer(raiz.getPropertyValue(n).trim() || "#000")).filter((c) => c[3] > 0.99);
      const cercano = (a, b) => Math.abs(a[0] - b[0]) + Math.abs(a[1] - b[1]) + Math.abs(a[2] - b[2]) < 12;
      const esToken = (c) => tokens.some((t) => cercano(c, t));
      for (const el of document.body.querySelectorAll("*")) {
        if (el.closest("img, canvas, video, svg")) continue;
        const cs = getComputedStyle(el);
        if (cs.visibility === "hidden" || cs.display === "none") continue;
        const caja = el.getBoundingClientRect();
        const c = leer(cs.backgroundColor);
        if (c[3] < 0.05) continue;
        // Un velo: capa fija que cubre (casi) toda la pantalla. En oscuro debe oscurecer; si queda más claro que la página, aclara.
        if (cs.position === "fixed" && caja.width >= innerWidth * 0.9 && caja.height >= innerHeight * 0.9) {
          if (opacidadHeredada(el) < 0.05) continue; // un velo cerrado (opacidad 0) no se ve: se audita abierto, con su escenario
          const compuesto = sobre(c, pagina);
          if (lum(compuesto) > lum(pagina) + 0.01) velos.push({ tipo: "velo-claro", clave: camino(el), fondo: hex(compuesto), pagina: hex(pagina), donde: camino(el) });
          continue;
        }
        if (c[3] < 0.5) continue;
        // Una SUPERFICIE (tarjeta, panel), no una barra de gráfico ni un botón: 100×60 como mínimo y 9.000 px² de área.
        if (caja.width * caja.height < 9000 || caja.width < 100 || caja.height < 60) continue;
        const compuesto = sobre(c, fondoEfectivo(el.parentElement || el).fondo);
        if (esToken(compuesto)) continue;
        // Un relleno de color (un estado, una insignia) es una mezcla de un token y rara vez pasa de 0.6; un blanco o gris claro escrito a mano, sí.
        if (lum(compuesto) > 0.6) (el.closest(CLARAS_A_PROPOSITO) ? manchasExentas : manchas).push({ tipo: "mancha-clara", clave: camino(el), fondo: hex(compuesto), tam: `${Math.round(caja.width)}x${Math.round(caja.height)}`, donde: camino(el) });
      }
    }
    abrirPunteros.remove();
    return { tema, textosAnalizados: analizados, sobreDegradado, contrastes, manchas, manchasExentas, velos };
  };
})();

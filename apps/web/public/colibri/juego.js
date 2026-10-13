// ============================================================================
// juego.js — el colibrí de CAYLA: tres juegos cortos, un solo motor
// ============================================================================
// QUÉ PROMETE
//   Un juego de reflejos que se puede jugar SIN internet. Lo usan dos sitios y
//   por eso vive acá, suelto de React: la página «sin conexión»
//   (`/sin-conexion.html`, que el service worker sirve cuando no hay red) y el
//   easter egg del buscador. Si cada uno tuviera su copia, un día el juego de
//   las sedes y el del panel dirían cosas distintas — y el de las sedes es el
//   que no se puede arreglar a distancia, porque se guarda en el navegador.
//
//   Es un módulo ES sin dependencias, en `public/` para que el service worker
//   pueda guardarlo en la caché y la página lo cargue sin pasar por el empaquetador
//   de Next (que sin red tampoco existe). Está escrito para poder probarse con
//   vitest: TODA la lógica (movimiento, choques, cuándo aparece cada obstáculo)
//   es pura y recibe su azar de fuera; lo único que toca el navegador es
//   `montar()`, al final.
//
// LOS TRES JUEGOS, Y CUÁL TOCA
//   `elegirVariante` sortea con 50 % / 40 % / 10 % (pedido de Felipe,
//   2026-10-13). El orden está escrito en `VARIANTES`.
//     vuelo   — el colibrí vuela; mantén pulsado para subir, suelta para bajar.
//               Esquiva carretes de hilo (en el suelo) y agujas (en el aire).
//     salto   — el del dinosaurio: pulsa para saltar los carretes.
//     flappy  — pulsa para aletear entre columnas de hilo.
//
// QUÉ NO HACE, A PROPÓSITO
//   No manda nada a ninguna parte: ni puntajes, ni quién jugó. El mejor puntaje
//   vive en el `localStorage` del propio navegador, y si no se puede escribir
//   ahí el juego sigue igual. Es un descanso, no una métrica; y nada de esto
//   puede tocar un marcaje, una planilla ni la sesión.
//
// POR QUÉ LAS CAJAS DE CHOQUE SON MÁS CHICAS QUE EL DIBUJO
//   El colibrí es una silueta con el ala extendida; chocar por la punta del ala
//   se siente injusto. La caja de choque es el cuerpo, y eso se compensa solo:
//   un juego que mata por un píxel enseña a quien juega a desconfiar de él.
// ============================================================================

export const MUNDO = { ancho: 640, alto: 240, suelo: 204 };

/** Orden y pesos del sorteo: 50 % vuelo, 40 % salto, 10 % flappy. */
export const VARIANTES = [
  { id: "vuelo", peso: 50 },
  { id: "salto", peso: 40 },
  { id: "flappy", peso: 10 },
];

const PAJARO = { x: 70, ancho: 46, alto: 31 };

const FISICA = {
  vuelo: { sube: 190, baja: 170, aceleracion: 1400 },
  salto: { gravedad: 1900, impulso: 640 },
  flappy: { gravedad: 900, impulso: 290 },
};

// ---------------------------------------------------------------- azar y cajas

/** Generador con semilla (mulberry32): el mismo número da la misma partida, que es lo que permite probarlo. */
export function crearRng(semilla) {
  let a = semilla >>> 0;
  return function rng() {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Sortea un juego según `VARIANTES`. `rng()` devuelve un número en [0, 1). */
export function elegirVariante(rng = Math.random) {
  const total = VARIANTES.reduce((s, v) => s + v.peso, 0);
  let r = rng() * total;
  for (const v of VARIANTES) {
    if (r < v.peso) return v.id;
    r -= v.peso;
  }
  return VARIANTES[0].id;
}

export function esVariante(valor) {
  return VARIANTES.some((v) => v.id === valor);
}

/** ¿Se tocan dos cajas {x, y, w, h}? Bordes que solo se rozan no cuentan. */
export function chocan(a, b) {
  return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
}

/** La caja con la que el colibrí choca: el cuerpo, no la punta del ala. */
export function cajaDelPajaro(p) {
  return { x: p.x + 9, y: p.y + 7, w: p.w - 18, h: p.h - 14 };
}

// ---------------------------------------------------------------- la partida

const VELOCIDAD_INICIAL = { vuelo: 200, salto: 230, flappy: 150 };
const VELOCIDAD_TOPE = { vuelo: 400, salto: 440, flappy: 210 };
const ACELERACION = { vuelo: 5, salto: 6, flappy: 2 };

/** Una partida nueva. No avanza sola: se la hace avanzar con `paso`. */
export function crearJuego(variante, rng) {
  const sobreSuelo = MUNDO.suelo - PAJARO.alto;
  return {
    variante,
    rng,
    t: 0,
    distancia: 0,
    puntos: 0,
    vivo: true,
    velocidad: VELOCIDAD_INICIAL[variante],
    pajaro: {
      x: PAJARO.x,
      y: variante === "flappy" ? MUNDO.alto / 2 - PAJARO.alto / 2 : variante === "salto" ? sobreSuelo : 70,
      vy: 0,
      w: PAJARO.ancho,
      h: PAJARO.alto,
    },
    obstaculos: [],
    // Distancia que falta para el próximo obstáculo; el primero tarda un poco más, para que dé tiempo de entender qué hay que hacer.
    falta: 420,
    ultimoCentro: MUNDO.alto / 2,
    columnas: 0,
  };
}

const SUBPASO = 1 / 120;

/**
 * Hace avanzar la partida `dt` segundos. `entrada.pulsado` es «el dedo/la tecla
 * está abajo ahora»; `entrada.pulso` es «hubo un toque desde el paso anterior»
 * — son distintos a propósito: un toque más corto que un cuadro no se ve en
 * `pulsado`, y para saltar o aletear hace falta el toque, no el estado.
 */
export function paso(j, dt, entrada) {
  if (!j.vivo) return j;
  const restante = Math.min(Math.max(dt, 0), 0.05);
  let pulso = !!entrada.pulso;
  // Los pasos internos son de 1/120 s sin importar cuánto dure el cuadro: así la partida no depende de lo rápido que sea el aparato.
  const n = Math.max(1, Math.round(restante / SUBPASO));
  const h = restante / n;
  for (let i = 0; i < n && j.vivo; i++) {
    avanzar(j, h, { pulsado: !!entrada.pulsado || pulso, pulso });
    pulso = false; // el toque se gasta una sola vez
  }
  return j;
}

function avanzar(j, h, entrada) {
  const p = j.pajaro;
  const tope = MUNDO.suelo - p.h;

  if (j.variante === "vuelo") {
    const f = FISICA.vuelo;
    const objetivo = entrada.pulsado ? -f.sube : f.baja;
    const delta = f.aceleracion * h;
    p.vy = p.vy < objetivo ? Math.min(p.vy + delta, objetivo) : Math.max(p.vy - delta, objetivo);
    p.y = Math.min(Math.max(p.y + p.vy * h, 0), tope);
  } else if (j.variante === "salto") {
    const f = FISICA.salto;
    const enElSuelo = p.y >= tope;
    if (entrada.pulso && enElSuelo) p.vy = -f.impulso;
    p.vy += f.gravedad * h;
    p.y += p.vy * h;
    if (p.y >= tope) {
      p.y = tope;
      p.vy = 0;
    }
  } else {
    const f = FISICA.flappy;
    if (entrada.pulso) p.vy = -f.impulso;
    p.vy += f.gravedad * h;
    p.y += p.vy * h;
    if (p.y < 0) {
      p.y = 0;
      p.vy = 0;
    }
    // En este juego el suelo y el cielo sí matan; en los otros dos el suelo es solo suelo.
    if (p.y + p.h > MUNDO.alto) j.vivo = false;
  }

  j.t += h;
  j.velocidad = Math.min(VELOCIDAD_TOPE[j.variante], VELOCIDAD_INICIAL[j.variante] + ACELERACION[j.variante] * j.t);
  const dx = j.velocidad * h;
  j.distancia += dx;
  for (const o of j.obstaculos) o.x -= dx;
  j.obstaculos = j.obstaculos.filter((o) => o.x + o.w > -20);

  j.falta -= dx;
  if (j.falta <= 0) aparecer(j);

  const caja = cajaDelPajaro(p);
  for (const o of j.obstaculos) {
    if (chocan(caja, o)) j.vivo = false;
    // Cada columna de flappy cuenta una vez, cuando el colibrí ya la dejó atrás.
    if (o.puntua && !o.contada && o.x + o.w < p.x) {
      o.contada = true;
      j.columnas += 1;
    }
  }
  j.puntos = j.variante === "flappy" ? j.columnas : Math.floor(j.distancia / 12);
}

/** Cuánto aire se deja después de un obstáculo: lo que tarda el colibrí en reaccionar, más el ancho del obstáculo que acaba de pasar. */
function separacion(j, ancho, minimo, variable) {
  return j.velocidad * (minimo + j.rng() * variable) + ancho;
}

function aparecer(j) {
  const rng = j.rng;
  if (j.variante === "vuelo") {
    if (rng() < 0.5) {
      const h = 30 + Math.round(rng() * 14);
      const w = 22 + Math.round(rng() * 8);
      j.obstaculos.push({ tipo: "carrete", x: MUNDO.ancho, y: MUNDO.suelo - h, w, h });
      j.falta = separacion(j, w, 0.8, 0.8);
    } else {
      const w = 70 + Math.round(rng() * 50);
      const y = 16 + Math.round(rng() * (MUNDO.suelo - 70 - 16));
      j.obstaculos.push({ tipo: "aguja", x: MUNDO.ancho, y, w, h: 8 });
      j.falta = separacion(j, w, 0.8, 0.8);
    }
  } else if (j.variante === "salto") {
    // Uno, dos o tres carretes pegados. Cuantos más, más ancho: y la separación sube con el ancho, porque saltar algo ancho dura más.
    const r = rng();
    const n = r < 0.55 ? 1 : r < 0.85 ? 2 : 3;
    const w = n * 26 + (n - 1) * 4;
    const h = 32 + Math.round(rng() * 14);
    j.obstaculos.push({ tipo: "carretes", x: MUNDO.ancho, y: MUNDO.suelo - h, w, h, cuantos: n });
    j.falta = separacion(j, w, 0.8, 0.9);
  } else {
    const hueco = Math.max(80, 96 - Math.floor(j.columnas / 4) * 2);
    const w = 26;
    // El centro nunca salta más de 75 px respecto de la columna anterior: si no, habría pares de columnas imposibles de cruzar.
    const margen = 20 + hueco / 2;
    const centro = clamp(
      j.ultimoCentro + (rng() * 2 - 1) * 75,
      margen,
      MUNDO.alto - margen,
    );
    j.ultimoCentro = centro;
    const arribaH = centro - hueco / 2;
    const abajoY = centro + hueco / 2;
    j.obstaculos.push({ tipo: "columna", x: MUNDO.ancho, y: 0, w, h: arribaH, puntua: true });
    j.obstaculos.push({ tipo: "columna", x: MUNDO.ancho, y: abajoY, w, h: MUNDO.alto - abajoY });
    j.falta = 215;
  }
}

function clamp(v, a, b) {
  return Math.min(Math.max(v, a), b);
}

// ---------------------------------------------------------------- el dibujo

const COLORES_POR_DEFECTO = {
  tinta: "#1a1a18",
  rojo: "#b8412d",
  taupe: "#805c4c",
  sand: "#e8e0d0",
  crema: "#f5f0e8",
};

/** Lee los colores del tema vivo (claro u oscuro) de la página que aloja el juego. */
export function leerColores(doc = document) {
  const estilo = doc.defaultView.getComputedStyle(doc.documentElement);
  const c = {};
  for (const k of Object.keys(COLORES_POR_DEFECTO)) {
    c[k] = estilo.getPropertyValue(`--color-${k}`).trim() || COLORES_POR_DEFECTO[k];
  }
  return c;
}

function dibujarJuego(ctx, j, colores, ave) {
  ctx.clearRect(0, 0, MUNDO.ancho, MUNDO.alto);

  if (j.variante !== "flappy") {
    ctx.strokeStyle = colores.taupe;
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(0, MUNDO.suelo + 1);
    ctx.lineTo(MUNDO.ancho, MUNDO.suelo + 1);
    ctx.stroke();
    // Unas puntadas que corren con el suelo, para que se note la velocidad.
    ctx.strokeStyle = colores.sand;
    ctx.lineWidth = 3;
    const corrido = j.distancia % 40;
    for (let x = -corrido; x < MUNDO.ancho; x += 40) {
      ctx.beginPath();
      ctx.moveTo(x, MUNDO.suelo + 12);
      ctx.lineTo(x + 14, MUNDO.suelo + 12);
      ctx.stroke();
    }
  }

  for (const o of j.obstaculos) {
    if (o.tipo === "carrete") carrete(ctx, o.x, o.y, o.w, o.h, colores);
    else if (o.tipo === "carretes") {
      const uno = (o.w - (o.cuantos - 1) * 4) / o.cuantos;
      for (let i = 0; i < o.cuantos; i++) carrete(ctx, o.x + i * (uno + 4), o.y, uno, o.h, colores);
    } else if (o.tipo === "aguja") aguja(ctx, o, colores);
    else columna(ctx, o, colores);
  }

  const p = j.pajaro;
  // El aleteo: el cuerpo se aplasta un poco y se estira; con el colibrí quieto (antes de empezar) igual vibra, que es lo suyo.
  const aleteo = j.vivo ? 1 + Math.sin(j.t * 38) * 0.07 : 1;
  const inclinacion = clamp(p.vy / 900, -0.4, 0.4);
  ctx.save();
  ctx.translate(p.x + p.w / 2, p.y + p.h / 2);
  ctx.rotate(inclinacion);
  ctx.scale(1, aleteo);
  if (ave) ctx.drawImage(ave, -p.w / 2, -p.h / 2, p.w, p.h);
  else {
    ctx.fillStyle = colores.rojo;
    ctx.fillRect(-p.w / 2, -p.h / 2, p.w, p.h);
  }
  ctx.restore();

  ctx.fillStyle = colores.tinta;
  ctx.font = "600 15px system-ui, sans-serif";
  ctx.textAlign = "right";
  ctx.fillText(String(j.puntos).padStart(4, "0"), MUNDO.ancho - 14, 24);
}

function carrete(ctx, x, y, w, h, c) {
  // El cuerpo del carrete (el hilo), y las dos tapas.
  ctx.fillStyle = c.rojo;
  ctx.fillRect(x + 3, y + 4, w - 6, h - 8);
  ctx.fillStyle = c.taupe;
  ctx.fillRect(x, y, w, 5);
  ctx.fillRect(x, y + h - 5, w, 5);
}

function aguja(ctx, o, c) {
  // Una aguja horizontal, con su ojal a la derecha (por donde se mete el hilo) y un hilo que le cuelga.
  ctx.strokeStyle = c.tinta;
  ctx.lineWidth = 3;
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.moveTo(o.x, o.y + 4);
  ctx.lineTo(o.x + o.w, o.y + 4);
  ctx.stroke();
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.ellipse(o.x + o.w - 8, o.y + 4, 6, 2.5, 0, 0, Math.PI * 2);
  ctx.stroke();
  ctx.strokeStyle = c.rojo;
  ctx.beginPath();
  ctx.moveTo(o.x + o.w - 8, o.y + 4);
  ctx.bezierCurveTo(o.x + o.w + 10, o.y + 14, o.x + o.w + 4, o.y + 22, o.x + o.w + 16, o.y + 26);
  ctx.stroke();
}

function columna(ctx, o, c) {
  ctx.fillStyle = c.taupe;
  ctx.fillRect(o.x + o.w / 2 - 2, o.y, 4, o.h);
  // Un nudo en la boca del hueco, para que se vea por dónde se pasa.
  ctx.fillStyle = c.rojo;
  const boca = o.y === 0 ? o.y + o.h : o.y;
  ctx.fillRect(o.x, boca - (o.y === 0 ? 8 : 0), o.w, 8);
}

/** El colibrí teñido del color pedido (la imagen es una silueta roja y sobre fondo transparente). */
function tenirAve(imagen, color, ancho, alto, doc) {
  const lienzo = doc.createElement("canvas");
  const r = 2;
  lienzo.width = ancho * r;
  lienzo.height = alto * r;
  const c = lienzo.getContext("2d");
  c.drawImage(imagen, 0, 0, lienzo.width, lienzo.height);
  c.globalCompositeOperation = "source-in";
  c.fillStyle = color;
  c.fillRect(0, 0, lienzo.width, lienzo.height);
  return lienzo;
}

// ---------------------------------------------------------------- el navegador

const TEXTOS = {
  vuelo: "Mantén pulsado para subir · suelta para bajar",
  salto: "Pulsa para saltar los carretes",
  flappy: "Pulsa para aletear entre los hilos",
};

function leerMejor(variante) {
  try {
    return Number(localStorage.getItem(`cayla-colibri-mejor-${variante}`)) || 0;
  } catch {
    return 0;
  }
}

function guardarMejor(variante, puntos) {
  try {
    localStorage.setItem(`cayla-colibri-mejor-${variante}`, String(puntos));
  } catch {
    // Sin dónde guardar (navegación privada, almacenamiento lleno): el juego sigue igual, solo que sin récord.
  }
}

/**
 * Pone el juego en un `<canvas>`. Devuelve `{ detener }`; quien lo monta tiene
 * que llamarlo al irse, o el juego sigue escuchando el teclado.
 *
 * opciones.variante   fuerza un juego («vuelo» | «salto» | «flappy»); sin ella se sortea en cada partida.
 * opciones.imagen     ruta de la silueta del colibrí (por defecto /colibri.png).
 */
export function montar(canvas, opciones = {}) {
  const doc = canvas.ownerDocument;
  const ventana = doc.defaultView;
  const ctx = canvas.getContext("2d");
  const forzada = esVariante(opciones.variante) ? opciones.variante : null;

  canvas.width = MUNDO.ancho * 2;
  canvas.height = MUNDO.alto * 2;
  ctx.scale(2, 2);
  canvas.setAttribute("role", "img");
  canvas.setAttribute("aria-label", "Juego del colibrí. Se juega con el teclado (espacio o flecha arriba) o tocando la pantalla.");

  let colores = leerColores(doc);
  let imagen = null;
  let ave = null;
  const cargar = new ventana.Image();
  cargar.onload = () => {
    imagen = cargar;
    ave = tenirAve(imagen, colores.rojo, PAJARO.ancho, PAJARO.alto, doc);
  };
  cargar.src = opciones.imagen || "/colibri.png";

  let estado = "listo"; // listo | jugando | terminado
  let juego = null;
  let variante = forzada ?? elegirVariante();
  let mejor = leerMejor(variante);
  let pulsado = false;
  let pulso = false;
  let cuadro = 0;
  let anterior = null;
  let vivo = true;

  function nueva() {
    colores = leerColores(doc);
    if (imagen) ave = tenirAve(imagen, colores.rojo, PAJARO.ancho, PAJARO.alto, doc);
    variante = forzada ?? elegirVariante();
    mejor = leerMejor(variante);
    juego = crearJuego(variante, crearRng((Math.random() * 4294967296) >>> 0));
  }
  nueva();

  function tocar() {
    if (estado === "listo") {
      estado = "jugando";
      anterior = null;
    } else if (estado === "terminado") {
      nueva();
      estado = "jugando";
      anterior = null;
    }
    pulsado = true;
    pulso = true;
  }

  const enCampo = (e) => {
    const t = e.target;
    return t && t.nodeType === 1 && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.tagName === "SELECT" || t.isContentEditable);
  };
  const teclaDelJuego = (e) => e.code === "Space" || e.code === "ArrowUp" || e.code === "KeyW";

  function alBajarTecla(e) {
    if (!teclaDelJuego(e) || enCampo(e) || e.metaKey || e.ctrlKey || e.altKey) return;
    // La barra espaciadora y la flecha desplazan la página; mientras el juego está a la vista, no.
    e.preventDefault();
    if (e.repeat) return;
    tocar();
  }
  function alSubirTecla(e) {
    if (teclaDelJuego(e)) pulsado = false;
  }
  function alBajarPuntero(e) {
    e.preventDefault();
    tocar();
  }
  function alSubirPuntero() {
    pulsado = false;
  }
  function alOcultar() {
    anterior = null; // al volver a la pestaña no se suma el tiempo que estuvo oculta
  }
  ventana.addEventListener("keydown", alBajarTecla);
  ventana.addEventListener("keyup", alSubirTecla);
  canvas.addEventListener("pointerdown", alBajarPuntero);
  ventana.addEventListener("pointerup", alSubirPuntero);
  ventana.addEventListener("pointercancel", alSubirPuntero);
  doc.addEventListener("visibilitychange", alOcultar);

  function texto(linea, y, grande) {
    ctx.fillStyle = grande ? colores.tinta : colores.taupe;
    ctx.font = grande ? "600 22px Georgia, serif" : "14px system-ui, sans-serif";
    ctx.textAlign = "center";
    ctx.fillText(linea, MUNDO.ancho / 2, y);
  }

  function cuadroNuevo(ahora) {
    if (!vivo) return;
    const dt = anterior === null ? 0 : (ahora - anterior) / 1000;
    anterior = ahora;
    if (estado === "jugando" && !doc.hidden) {
      paso(juego, dt, { pulsado, pulso });
      pulso = false;
      if (!juego.vivo) {
        estado = "terminado";
        if (juego.puntos > mejor) {
          mejor = juego.puntos;
          guardarMejor(variante, mejor);
        }
      }
    }
    // Antes de empezar el colibrí aletea en su sitio, sin avanzar la partida.
    if (estado === "listo") juego.t += dt;
    dibujarJuego(ctx, juego, colores, ave);
    if (estado === "listo") {
      texto("Pulsa para empezar", 96, true);
      texto(TEXTOS[variante], 124, false);
    } else if (estado === "terminado") {
      texto("Se enredó en el hilo", 92, true);
      texto(`${juego.puntos} puntos · mejor: ${mejor}`, 120, false);
      texto("Pulsa para volver a volar", 144, false);
    }
    cuadro = ventana.requestAnimationFrame(cuadroNuevo);
  }
  cuadro = ventana.requestAnimationFrame(cuadroNuevo);

  return {
    detener() {
      vivo = false;
      ventana.cancelAnimationFrame(cuadro);
      ventana.removeEventListener("keydown", alBajarTecla);
      ventana.removeEventListener("keyup", alSubirTecla);
      canvas.removeEventListener("pointerdown", alBajarPuntero);
      ventana.removeEventListener("pointerup", alSubirPuntero);
      ventana.removeEventListener("pointercancel", alSubirPuntero);
      doc.removeEventListener("visibilitychange", alOcultar);
    },
  };
}

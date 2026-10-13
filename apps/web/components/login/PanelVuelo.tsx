"use client";

/**
 * La mitad izquierda del login: «El vuelo vivo» (Felipe 2026-10-13; maqueta `docs/maquetas/login-2026-10/`, `?v=C4`).
 *
 * El colibrí aparece dibujándose en Trujillo y aleteando, salta a Arequipa y a Lima (flota un instante y cada ojal se rellena con
 * una onda), da la vuelta, cruza por detrás del lema tiñendo «transforma.» y sube a su lugar: flota, dos aleteos que se apagan en la
 * pose del logo y el hilo da un tirón. Corre UNA vez al entrar, sin rebote (excepción aprobada en ADR-0136, act. 2026-10-13); el
 * aleteo dura lo que dura el vuelo y se detiene. Con `prefers-reduced-motion`, o si la ventana cambia de tamaño a medio vuelo, se
 * ve terminado. Solo en pantallas anchas (lg); en el celular el login es el formulario con la marca arriba.
 * La geometría y la línea de tiempo viven en `lib/login-vuelo.ts`; los estilos, en `app/estilos/login.css`.
 */

import { useEffect, useId, useRef } from "react";
import { useRafagaDeClics } from "@/lib/use-rafaga-de-clics";
import {
  COLA_DEL_AVE,
  LINEA_DE_TIEMPO,
  TRAZOS_DEL_AVE,
  aleteo,
  alaDelAve,
  estadoDelVuelo,
  meceo,
  poseDelAve,
  tintaDeLaPalabra,
  trazoDelVuelo,
  type Punto,
} from "@/lib/login-vuelo";

// Las tres CIUDADES donde CAYLA tiene tiendas, en el orden en que el hilo las cose. Es una pieza de marca, no un dato: no dice dónde hay
// una sede en el sistema (Central, por ejemplo, no es tienda y no aparece). El login se ve antes de entrar y no puede leer `sedes`; la
// verdad de qué sedes existen está en la tabla, nunca aquí.
const SEDES = [
  { codigo: "TRU", nombre: "Trujillo" },
  { codigo: "AQP", nombre: "Arequipa" },
  { codigo: "LIM", nombre: "Lima" },
];

export function PanelVuelo() {
  const mascaraId = `hilo-${useId().replace(/:/g, "")}`;
  // Easter egg: cinco clics seguidos sobre el colibrí lo hacen revolotear. Ver docs/easter-eggs.md.
  const { activo: travieso, alClic } = useRafagaDeClics();
  const panelRef = useRef<HTMLDivElement>(null);
  const aveRef = useRef<SVGSVGElement>(null);
  const alaRef = useRef<SVGPathElement>(null);
  const alaBajoRef = useRef<SVGPathElement>(null);
  const lienzoRef = useRef<SVGSVGElement>(null);
  const hiloRef = useRef<SVGPathElement>(null);
  const mascaraRef = useRef<SVGPathElement>(null);
  const palabraRef = useRef<HTMLElement>(null);
  const ojalesRef = useRef<(HTMLElement | null)[]>([]);

  useEffect(() => {
    const panel = panelRef.current;
    const ave = aveRef.current;
    const ala = alaRef.current;
    const alaBajo = alaBajoRef.current;
    const lienzo = lienzoRef.current;
    const hilo = hiloRef.current;
    const mascara = mascaraRef.current;
    const palabra = palabraRef.current;
    const ojales = ojalesRef.current.filter((o): o is HTMLElement => o !== null);
    if (!panel || !ave || !ala || !alaBajo || !lienzo || !hilo || !mascara || !palabra || ojales.length === 0) return;
    const trazos = [...ave.querySelectorAll("path")];

    let cuadro = 0;
    let largo = 0;
    let segunda = 0;
    let tercera = 0;
    let destino: Punto = { x: 0, y: 0 };
    let cajaPalabra = { x: 0, y: 0, ancho: 1, alto: 1 };

    /** Mide el panel y arma el recorrido. Devuelve false si el panel no se ve (celular). */
    const medir = () => {
      const caja = panel.getBoundingClientRect();
      if (caja.width === 0) return false;
      const rel = (el: Element) => {
        const r = el.getBoundingClientRect();
        return { x: r.left - caja.left, y: r.top - caja.top, ancho: r.width, alto: r.height };
      };
      const centro = (el: Element): Punto => {
        const r = rel(el);
        return { x: r.x + r.ancho / 2, y: r.y + r.alto / 2 };
      };
      ave.style.transform = "none";
      const r = rel(ave);
      destino = { x: r.x + r.ancho * COLA_DEL_AVE.x, y: r.y + r.alto * COLA_DEL_AVE.y };
      cajaPalabra = rel(palabra);
      const sedes = ojales.map(centro);
      const d = trazoDelVuelo({ ancho: caja.width, alto: caja.height, sedes, destino });
      lienzo.setAttribute("viewBox", `0 0 ${caja.width} ${caja.height}`);
      hilo.setAttribute("d", d);
      mascara.setAttribute("d", d);
      largo = hilo.getTotalLength();
      // El hilo va recto de la primera sede a la última: lo que mide hasta cada una es su distancia en x.
      segunda = sedes[1].x - sedes[0].x;
      tercera = sedes[sedes.length - 1].x - sedes[0].x;
      return true;
    };

    const ponerAla = (angulo: number, alargue: number) => {
      const [a, b] = alaDelAve(angulo, alargue);
      ala.setAttribute("d", a);
      alaBajo.setAttribute("d", b);
    };
    const pintarHilo = (recorrido: number, tiron: number) => {
      mascara.style.strokeDasharray = `${largo} ${largo}`;
      mascara.style.strokeDashoffset = String(largo - recorrido);
      // El tirón: la costura corre medio patrón (6 + 7) y queda tensa.
      hilo.style.strokeDashoffset = String(-13 * tiron);
    };
    const coser = (cuantas: number) =>
      ojales.forEach((o, i) => {
        if (i < cuantas && !o.hasAttribute("data-cosido")) o.setAttribute("data-cosido", "");
      });
    const pintarPalabra = (t: number) => palabra.style.setProperty("--login-tinta", `${(t * 100).toFixed(1)}%`);

    const terminar = () => {
      cancelAnimationFrame(cuadro);
      if (!medir()) return;
      ave.style.transform = "none";
      trazos.forEach((p) => (p.style.strokeDashoffset = "0"));
      ponerAla(0, 1);
      pintarHilo(largo, 0);
      coser(ojales.length);
      pintarPalabra(1);
      panel.setAttribute("data-llego", "");
    };

    const alCambiarTamano = () => terminar();
    window.addEventListener("resize", alCambiarTamano);

    const quieto = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (quieto || !medir()) {
      terminar();
      return () => window.removeEventListener("resize", alCambiarTamano);
    }

    let pose = { giro: 1, inclinacion: 0 };
    let fase = 0;
    let tinta = 0;
    let inicio: number | null = null;
    let anterior: number | null = null;
    const [desdeGran, hastaGran] = LINEA_DE_TIEMPO.granVuelo;

    const paso = (ahora: number) => {
      inicio ??= ahora;
      const ms = ahora - inicio;
      const dt = anterior === null ? 0 : (ahora - anterior) / 1000;
      anterior = ahora;
      const e = estadoDelVuelo(ms, { largo, segunda, tercera });
      if (e.terminado) return terminar();

      const p = hilo.getPointAtLength(e.recorrido);
      const q = hilo.getPointAtLength(Math.min(largo, e.recorrido + 2));
      pose = poseDelAve(pose, { dx: q.x - p.x, dy: q.y - p.y }, e, Math.min(1, Math.max(0, (ms - desdeGran) / (hastaGran - desdeGran))));
      fase += dt * e.frecuencia * 2 * Math.PI;
      const { angulo, largo: alargue } = aleteo(fase, e.amplitud);
      ponerAla(angulo, alargue);
      trazos.forEach((t) => (t.style.strokeDashoffset = String(1 - e.dibujado)));
      ave.style.transform = `translate(${p.x - destino.x}px, ${p.y - destino.y + meceo(ms, e.flota)}px) rotate(${pose.inclinacion * Math.sign(pose.giro)}deg) scale(${e.escala * pose.giro}, ${e.escala})`;
      // El ave tiñe «transforma.» al pasar por detrás (se mide desde el centro de su cuerpo, no desde la cola).
      tinta = tintaDeLaPalabra(tinta, { x: p.x, y: p.y - 60 * e.escala }, cajaPalabra, dt, ms > hastaGran);
      pintarPalabra(tinta);
      pintarHilo(e.recorrido, e.tiron);
      coser(e.cosidas);
      cuadro = requestAnimationFrame(paso);
    };
    panel.setAttribute("data-volando", "");
    cuadro = requestAnimationFrame(paso);

    return () => {
      cancelAnimationFrame(cuadro);
      window.removeEventListener("resize", alCambiarTamano);
    };
  }, []);

  return (
    <div ref={panelRef} className="login-panel" aria-hidden>
      <p className="login-panel-marca">
        <span>CAYLA</span>
        <small>Dynamic</small>
      </p>

      <svg ref={lienzoRef} className="login-hilo">
        <defs>
          <mask id={mascaraId} maskUnits="userSpaceOnUse">
            <path ref={mascaraRef} className="login-hilo-mascara" />
          </mask>
        </defs>
        <path ref={hiloRef} className="login-hilo-trazo" mask={`url(#${mascaraId})`} />
      </svg>

      {/* El colibrí de la marca (los trazos de IsotipoCayla); el ala son los dos primeros y aletea. */}
      <svg ref={aveRef} className="login-ave" viewBox="0 0 223 150" onClick={alClic} data-travieso={travieso ? "" : undefined}>
        <path ref={alaRef} d={TRAZOS_DEL_AVE[0]} pathLength={1} />
        <path ref={alaBajoRef} d={TRAZOS_DEL_AVE[1]} pathLength={1} />
        <path d={TRAZOS_DEL_AVE[2]} pathLength={1} />
        <path d={TRAZOS_DEL_AVE[3]} pathLength={1} />
      </svg>

      <p className="login-lema">
        Donde el estilo <em ref={palabraRef}>transforma.</em>
      </p>

      <ul className="login-sedes">
        {SEDES.map((s, i) => (
          <li key={s.codigo}>
            <i
              ref={(el) => {
                ojalesRef.current[i] = el;
              }}
              className="login-ojal"
            />
            <small>{s.codigo}</small>
            <b>{s.nombre}</b>
          </li>
        ))}
      </ul>
    </div>
  );
}

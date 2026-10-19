"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { etiquetaDePrueba, type TipoMarca } from "@cayla-dynamic/shared";
import { createTerminalSupabaseClient } from "@cayla-dynamic/database";
import { Cargando } from "@/components/cargando";
import type { RosterEntry } from "@/lib/terminal/offline-db";
import type { ClavePresencia, PresenciaCasilla } from "@/lib/terminal/presencia";
import { inicialesDe, urlPublicaFotoPerfil } from "@/lib/foto-perfil";
import {
  ConEtiqueta,
  ESTILO_PRESENCIA,
  REPOSO_PRESENCIA,
  etiquetaDePresencia,
  type EstiloPresencia,
} from "./presencia-visual";

// Estilos compartidos de la superficie clara del terminal (crema, líneas finas Sand).
//
// El radio usa los tokens con nombre de globals.css (2026-09-06): `rounded-control`
// es el mismo 8px que ya tenían 480 usos de `rounded-lg` en el resto de la casa —
// estas casillas y botones vivían en `rounded-xl` (12px), la única de las tres
// escalas del terminal que no tenía nombre. Sustitución mecánica, sin sorpresas:
// 4px menos de esquina, nada que cambie el layout.
//
// El borde y el relleno de TILE sí cambian de verdad, medidos con la fórmula de
// contraste WCAG: `border-sand` sobre `crema` daba 1.16:1 y `bg-sand/35` 1.05:1
// — muy por debajo del 3:1 que pide WCAG 1.4.11 para el límite de un control. A
// un metro de una Mac mini, eso es una nube de nombres sin nada que diga "esto
// es un botón". `border-borde-control` (globals.css, 2026-09-06: alias de taupe,
// 5.21:1 sobre crema, ya definido justo para este caso — "Campo, CampoSelect y
// Boton puedan pedir border-borde-control") reemplaza a `border-sand` acá,
// primer uso real del token. Con `bg-papel` (superficie elevada) en vez del
// mismo sand diluido, la casilla se despega del fondo aun sin tocarla. El
// hover/active mueve el BORDE a rojo, no solo la opacidad del relleno: una
// opacidad no se nota a un metro, un color sí. `cursor-pointer` explícito en
// los tres porque Tailwind v4 dejó de ponerlo solo en los `<button>` — la casa
// entera lo necesita (ver `globals.css`), pero eso no toca este archivo; acá
// se repone donde se puede.
const TILE =
  "cursor-pointer rounded-control border border-borde-control bg-papel transition-colors hover:border-rojo hover:bg-sand active:scale-95";
// La tarjeta que SÍ dice en qué punto del día está la persona: un solo botón, igual
// que la de siempre —tocar en cualquier parte marca, el ícono de la foto incluido—.
// El color lo pone `REPOSO_PRESENCIA` o, si el estado está iluminado desde la
// píldora, el del estado. Al presionar, el borde se va a rojo y la caja se encoge,
// igual que en TILE: es el feedback que se ve a un metro de la pantalla.
const CAJA_PRESENCIA =
  "cursor-pointer rounded-control border-[1.5px] transition-all hover:border-rojo active:scale-95";
const BTN_PRIMARIO =
  "cursor-pointer rounded-control bg-rojo px-5 py-3 font-medium text-crema transition-colors hover:bg-rojo-profundo active:scale-95";
const BTN_SECUNDARIO =
  "cursor-pointer rounded-control border border-sand px-5 py-3 text-tinta transition-colors hover:bg-sand/50";
// Salidas de emergencia (Cancelar, "otra salida"): en un kiosco NINGÚN objetivo
// debería bajar de 44-48px, ni siquiera el que se toca poco — sobre todo el que
// se toca con prisa y arrepentimiento, cuando alguien tocó "Me voy" por error y
// busca cómo volver. El peso visual se mantiene bajo con el color (taupe,
// subrayado), nunca reduciendo la caja que hay que acertar con el dedo.
const BTN_ENLACE =
  "cursor-pointer min-h-12 rounded-control px-5 py-3 text-sm text-taupe underline transition-colors hover:text-tinta active:scale-95";

// Selector de sede discreto. El terminal abre en SU sede; esto deja cambiarla
// (para quien viaja entre tiendas). Si solo hay una sede visible, no se muestra.
export function SelectorSede({
  sedes,
  activa,
  onCambiar,
}: {
  sedes: Array<{ codigo: string; nombre: string }>;
  activa: string | null;
  onCambiar: (codigo: string) => void;
}) {
  if (sedes.length <= 1) return null;
  return (
    <div className="flex items-center gap-3">
      <span className="etiqueta text-taupe">Sede</span>
      <div className="flex gap-1 rounded-pildora border border-sand p-1">
        {sedes.map((s) => (
          <button
            key={s.codigo}
            onClick={() => onCambiar(s.codigo)}
            className={`cursor-pointer rounded-pildora px-4 py-1.5 text-sm transition-colors ${
              activa === s.codigo ? "bg-tinta text-crema" : "text-taupe hover:text-tinta"
            }`}
          >
            {s.nombre}
          </button>
        ))}
      </div>
    </div>
  );
}

/**
 * En qué punto está la lista de personas de la sede.
 *
 * Existe porque una lista vacía significaba TRES cosas distintas y la pantalla
 * las contaba como una sola: «esta sede no tiene gente», «todavía estoy
 * cargando» y «no la pude cargar». Quien lo veía era una integrante a las ocho
 * de la mañana, justo después de un reinicio de la Mac mini o de un corte de
 * red, sin nadie de soporte al lado — y lo que leía era «Nadie en esta sede
 * todavía», o sea que se había borrado el equipo entero.
 */
export type EstadoRoster = "cargando" | "listo" | "error";

export function NombreGrid({
  roster,
  estado,
  presencia,
  resaltado = null,
  onSeleccionar,
  onReintentar,
}: {
  roster: RosterEntry[];
  estado: EstadoRoster;
  /**
   * En qué punto del día está cada persona (ver `lib/terminal/presencia.ts`),
   * ya calculado. Opcional a propósito: sin él, la grilla es la de siempre —todas
   * las casillas iguales—. Quien llama lo omite mientras NO pudo confirmar el
   * estado de hoy contra el servidor: un mapa vacío significa «todavía no lo
   * sé», no «nadie ha entrado», y pintar a todo el equipo como «sin entrada»
   * sería acusar de más (el peor error de este sistema).
   */
  presencia?: Map<string, PresenciaCasilla>;
  /**
   * El estado iluminado desde la píldora de arriba: quienes lo tienen se destacan
   * y los demás se atenúan. Ilumina, no oculta —nadie pierde su nombre de la
   * pantalla—. Sin `presencia` no hace nada.
   */
  resaltado?: ClavePresencia | null;
  onSeleccionar: (persona: RosterEntry) => void;
  onReintentar: () => void;
}) {
  if (roster.length === 0) {
    // El colibrí que aletea es el estado de carga de toda la casa
    // (`components/cargando.tsx`) y no uno nuevo para el terminal: lo que
    // distingue «trabajando» de «colgado» es el movimiento, y esa pieza ya
    // existe. Un segundo spinner acá sería la copia que ese archivo cuenta
    // haber tardado meses en juntar.
    if (estado === "cargando") {
      // En `text-2xl` y no en el `text-sm` de siempre: esto se lee de pie, a un
      // metro de una Mac mini a pantalla completa, y era el único de los tres
      // estados que se había quedado en 14 px — justo el que se mira a las ocho
      // de la mañana. El tamaño es una prop del componente de la casa, no una
      // copia suya acá.
      return <Cargando texto="Cargando el equipo de la sede…" clase="font-serif text-2xl" />;
    }

    // El error no comparte texto con el vacío ni con la carga, y dice qué
    // hacer. Se llega acá con `fuente === "ninguna"` (lib/terminal/roster.ts),
    // o sea cuando NO contestó ni el servidor ni la copia local que el terminal
    // guarda para trabajar sin red: no es «hoy no vino nadie», es que esta Mac
    // no tiene la lista.
    if (estado === "error") {
      return (
        <div className="flex max-w-xl flex-col items-center gap-5 text-center">
          <span aria-hidden className="text-5xl">⚠️</span>
          <p className="font-serif text-3xl text-rojo" role="alert">
            No se pudo cargar el equipo de esta sede.
          </p>
          {/* Le dice qué hacer con su hora, no solo que hoy no puede marcar: lo
              que registra este sistema alimenta el pago, y quien lee esto está
              sola a las ocho de la mañana. Sin esa frase se va a trabajar sin
              marca de entrada y sin saber que su llegada hay que apuntarla.
              Y la máquina se llama «esta Mac» en las dos frases: cuatro líneas
              más arriba «equipo» son las personas de la sede. */}
          <p className="text-xl text-taupe">
            Esta Mac no pudo leer la lista, ni del servidor ni de su copia guardada. Si hay internet
            en la tienda, toca «Volver a intentar». Si sigue igual, hoy no se puede marcar en esta
            Mac: <strong className="text-tinta">anota tu hora de llegada y dísela a tu líder de equipo</strong>,
            que la registra desde el panel. Tus horas no se pierden.
          </p>
          <button onClick={onReintentar} className={`${BTN_PRIMARIO} py-4 text-xl`}>
            Volver a intentar
          </button>
        </div>
      );
    }

    return <p className="font-serif text-2xl text-taupe">Nadie en esta sede todavía.</p>;
  }

  return (
    // `max-w-2xl` + tope en 3 columnas eran una grilla pensada para un
    // teléfono: en un monitor de sede de 1920px la lista ocupaba un tercio de
    // la pantalla y la fila 13 caía por debajo del borde sin que nada avisara
    // que había más gente. `lg:`/`xl:` dejan que el ancho del monitor sume
    // columnas en vez de apilar filas.
    <div className="grid w-full max-w-5xl grid-cols-2 content-start gap-3 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
      {roster.map((persona) => {
        const pres = presencia?.get(persona.id);

        // Sin estado confirmado: la casilla de siempre, un solo botón, sin nada
        // que decir de nadie.
        if (!pres) {
          return (
            <button
              key={persona.id}
              onClick={() => onSeleccionar(persona)}
              className={`${TILE} flex flex-col items-center gap-2 px-4 py-5 font-serif text-xl`}
            >
              <AvatarPersona persona={persona} />
              <span>
                {persona.nombres} {persona.apellidos}
              </span>
              <EtiquetaDePrueba persona={persona} />
            </button>
          );
        }

        const estilo = ESTILO_PRESENCIA[pres.clave];
        const etiqueta = etiquetaDePresencia(pres.clave);
        const nombre = `${persona.nombres} ${persona.apellidos}`;
        const encendida = resaltado === pres.clave;
        const atenuada = resaltado !== null && !encendida;
        return (
          <button
            key={persona.id}
            type="button"
            onClick={() => onSeleccionar(persona)}
            // El estado ya no se dice con una palabra en la tarjeta —lo dicen el
            // ícono de la foto y, al pasar el mouse, su etiqueta—, así que quien
            // usa lector de pantalla lo escucha acá completo.
            aria-label={`${nombre}${textoDePrueba(persona) ? `, ${textoDePrueba(persona)}` : ""}: ${etiqueta}, ${pres.detalle}${pres.detalle2 ? `, ${pres.detalle2}` : ""}`}
            className={`${CAJA_PRESENCIA} ${encendida ? estilo.iluminada : REPOSO_PRESENCIA} ${
              atenuada ? "opacity-30" : ""
            } flex flex-col items-center gap-1 px-3 pb-4 pt-5 text-center font-serif text-xl`}
          >
            <AvatarPersona persona={persona} presencia={estilo} etiqueta={etiqueta} />
            <span className={estilo.apagada ? "text-taupe" : undefined}>{nombre}</span>
            <EtiquetaDePrueba persona={persona} />
            <span className="font-sans text-sm text-taupe">{pres.detalle}</span>
            {pres.detalle2 && <span className="font-sans text-sm text-taupe">{pres.detalle2}</span>}
          </button>
        );
      })}
    </div>
  );
}

/** «Prueba · 2 de 3», o null si la persona no está de prueba (0539). */
function textoDePrueba(persona: RosterEntry): string | null {
  if (typeof persona.pruebaDias !== "number" || typeof persona.pruebaPlazo !== "number") return null;
  return etiquetaDePrueba({ dias_trabajados: persona.pruebaDias, dias_plazo: persona.pruebaPlazo }).texto;
}

const TONO_PRUEBA = {
  informativo: "bg-pizarra/15 text-pizarra",
  advertencia: "bg-ambar/15 text-ambar",
  alerta: "bg-rojo/10 text-rojo-profundo",
} as const;

/**
 * La etiqueta de prueba junto al nombre (0539): quien marca ve, de un vistazo, que esa persona está
 * de prueba y en qué día va. Solo INFORMA: marcar sigue siendo tocar la casilla, sin pedir nada más.
 * No importa `Insignia` a propósito —el kiosco no carga los componentes del panel—; las tres tintas
 * son las mismas de esa pieza.
 */
function EtiquetaDePrueba({ persona }: { persona: RosterEntry }) {
  if (typeof persona.pruebaDias !== "number" || typeof persona.pruebaPlazo !== "number") return null;
  const e = etiquetaDePrueba({ dias_trabajados: persona.pruebaDias, dias_plazo: persona.pruebaPlazo });
  return (
    <span className={`rounded-pildora px-2 py-0.5 font-sans text-xs font-medium ${TONO_PRUEBA[e.variante]}`}>
      {e.texto}
    </span>
  );
}

/**
 * La foto que cada quien sube desde «Lo mío» (0381), o sus iniciales mientras
 * no haya subido ninguna — nunca un hueco vacío ni un ícono de imagen rota.
 * Ayuda a no tocar a la persona equivocada por apuro, sobre todo con nombres
 * parecidos, pero NO es una prueba de identidad: el terminal sigue marcando
 * sin PIN, a propósito (decisión de Felipe, jul-2026).
 */
function AvatarPersona({
  persona,
  presencia,
  etiqueta,
}: {
  persona: RosterEntry;
  presencia?: EstiloPresencia | null;
  /** La palabra del estado: es lo que sale al pasar el mouse por el ícono. */
  etiqueta?: string;
}) {
  // El cliente es un singleton cacheado por storageKey (client.ts): pedirlo
  // acá no crea una conexión nueva por cada tile de la grilla.
  const supabase = useMemo(() => createTerminalSupabaseClient(), []);
  const url = urlPublicaFotoPerfil(supabase, persona.fotoUrl);
  // La promesa del comentario de arriba ("nunca un hueco vacío ni un ícono de
  // imagen rota") solo se cumplía cuando `fotoUrl` era null. Sin `onError`,
  // el día en que la foto no carga —sin internet, que es justo el escenario
  // para el que existe la copia offline del roster, o porque el objeto del
  // bucket se borró— el navegador pinta su ícono de imagen rota, y desaparece
  // la ayuda para no tocar el nombre equivocado exactamente cuando el
  // terminal está funcionando de memoria.
  const [fotoFallo, setFotoFallo] = useState(false);

  // Quien ya terminó o hoy no trabaja se ve apagado: ahí no hay nada que hacer.
  const apagada = presencia?.apagada ? "opacity-50" : "";

  const foto =
    url && !fotoFallo ? (
      // eslint-disable-next-line @next/next/no-img-element -- foto de un bucket externo, no un asset local
      <img
        src={url}
        alt=""
        className={`h-full w-full rounded-pildora object-cover ${apagada}`}
        onError={() => setFotoFallo(true)}
      />
    ) : (
      <span
        className={`flex h-full w-full items-center justify-center rounded-pildora bg-sand text-lg text-taupe ${apagada}`}
      >
        {inicialesDe(persona.nombres, persona.apellidos)}
      </span>
    );

  return (
    <span className={`relative block h-14 w-14 shrink-0 ${presencia ? "mb-2" : ""}`}>
      {foto}
      {/* El ícono solo INFORMA: dice el estado, y su palabra sale al pasar el mouse.
          No es un control —tocarlo marca, como tocar cualquier parte de la tarjeta—:
          el filtro vive únicamente en la píldora de arriba. */}
      {presencia && (
        <ConEtiqueta texto={etiqueta ?? ""} className="absolute -bottom-2 -right-2">
          <InsigniaDeEstado presencia={presencia} />
        </ConEtiqueta>
      )}
    </span>
  );
}

/**
 * El círculo del estado, en la esquina de la foto. Su borde es del color del
 * FONDO de la tarjeta (`--anillo`), así que parece recortado de la foto en vez de
 * pegado encima.
 */
function InsigniaDeEstado({ presencia }: { presencia: EstiloPresencia }) {
  const Icono = presencia.Icono;
  return (
    <span
      className={`grid h-7 w-7 place-items-center rounded-pildora border-2 border-[var(--anillo)] ${presencia.punto}`}
    >
      <Icono size={15} strokeWidth={2.5} aria-hidden />
    </span>
  );
}

type OpcionSalida = { tipo: TipoMarca; motivoRequerido: boolean; label: string };

// Menú de salida asertivo: una acción principal sugerida (grande), la otra opción
// principal como secundaria, y las salidas por motivo escondidas bajo "otra salida".
//
// `neutra` cubre el caso en que NI refrigerio NI salida final tienen sentido
// ahora mismo (ej. entró hace 1h) — ver sugerirSalidaPrincipal en shared. Ahí
// se invierte qué es prominente: "otra salida" (personal/trámite/médico/otro)
// sube arriba ya expandida, y principal/secundaria bajan a enlaces chicos.
// Nada se oculta en ningún caso, solo cambia qué se ve grande.
export function SelectorSalida({
  nombre,
  principal,
  secundaria,
  otras,
  neutra = false,
  aviso,
  onElegir,
  onCancelar,
}: {
  nombre: string;
  principal: OpcionSalida;
  secundaria: OpcionSalida | null;
  otras: OpcionSalida[];
  neutra?: boolean;
  /**
   * Para el único caso en que este menú no es una sugerencia sino un
   * respaldo: no se pudo confirmar el estado de la persona (ver
   * `estado-dia.ts` → `confirmarEstadoPuntual`) y se le pide elegir a mano en
   * vez de arriesgar una suposición. Sin esto, la pantalla es indistinguible
   * del menú de salida de siempre, y nada explica por qué de golpe aparece
   * "Entrada" junto a las salidas.
   */
  aviso?: string;
  onElegir: (tipo: TipoMarca, motivoRequerido: boolean) => void;
  onCancelar: () => void;
}) {
  const [mostrarOtras, setMostrarOtras] = useState(false);

  if (neutra) {
    return (
      <div className="flex flex-1 flex-col items-center justify-center gap-6 p-8">
        <p className="font-serif text-2xl">{nombre}</p>
        <div className="flex w-full max-w-sm flex-col gap-3">
          {otras.map((op) => (
            <button
              key={op.tipo}
              onClick={() => onElegir(op.tipo, op.motivoRequerido)}
              className={`${TILE} px-5 py-4 text-lg text-left`}
            >
              {op.label}
            </button>
          ))}
          <div className="mt-2 flex justify-center gap-4">
            <button
              onClick={() => onElegir(principal.tipo, principal.motivoRequerido)}
              className="text-sm text-taupe underline"
            >
              {principal.label}
            </button>
            {secundaria && (
              <button
                onClick={() => onElegir(secundaria.tipo, secundaria.motivoRequerido)}
                className="text-sm text-taupe underline"
              >
                {secundaria.label}
              </button>
            )}
          </div>
        </div>
        <button onClick={onCancelar} className="text-sm text-taupe underline">
          Cancelar
        </button>
      </div>
    );
  }

  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-6 p-8">
      <p className="font-serif text-2xl">{nombre}</p>
      {aviso && (
        <p className="max-w-sm rounded-control bg-ambar/10 px-4 py-3 text-center text-sm text-tinta" role="alert">
          {aviso}
        </p>
      )}
      <div className="flex w-full max-w-sm flex-col gap-3">
        <button
          onClick={() => onElegir(principal.tipo, principal.motivoRequerido)}
          className={`${BTN_PRIMARIO} py-5 text-xl`}
        >
          {principal.label}
        </button>
        {secundaria && (
          <button
            onClick={() => onElegir(secundaria.tipo, secundaria.motivoRequerido)}
            className={`${TILE} px-5 py-4 text-lg`}
          >
            {secundaria.label}
          </button>
        )}
        {mostrarOtras ? (
          <div className="mt-1 flex flex-col gap-2">
            {otras.map((op) => (
              <button
                key={op.tipo}
                onClick={() => onElegir(op.tipo, op.motivoRequerido)}
                className={`${TILE} px-5 py-3 text-left`}
              >
                {op.label}
              </button>
            ))}
          </div>
        ) : (
          <button onClick={() => setMostrarOtras(true)} className={`mt-1 ${BTN_ENLACE}`}>
            Otra salida (personal, médico, trámite…)
          </button>
        )}
      </div>
      <button onClick={onCancelar} className={BTN_ENLACE}>
        Cancelar
      </button>
    </div>
  );
}

export function FormularioMotivoOtro({
  onConfirmar,
  onCancelar,
}: {
  onConfirmar: (motivo: string) => void;
  onCancelar: () => void;
}) {
  const [motivo, setMotivo] = useState("");
  const valido = motivo.trim().length >= 3;

  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-4 p-8">
      <p className="font-serif text-xl">Cuéntanos brevemente el motivo</p>
      <textarea
        value={motivo}
        onChange={(e) => setMotivo(e.target.value)}
        rows={3}
        className="w-full max-w-sm rounded-control border border-sand bg-crema p-3 text-tinta outline-none placeholder:text-taupe/60 focus:border-taupe"
        placeholder="Ej: trámite bancario personal"
      />
      {/* La regla para habilitar "Continuar" (3 letras, línea de abajo) no se
          anunciaba en ningún lado: el botón apagado no decía qué faltaba, y
          quien escribía "ok" se quedaba mirando algo que parecía roto. */}
      <p className="-mt-2 w-full max-w-sm text-left text-sm text-taupe">
        Escribe al menos 3 letras para continuar.
      </p>
      <div className="flex gap-3">
        <button onClick={onCancelar} className={BTN_SECUNDARIO}>
          Cancelar
        </button>
        <button
          disabled={!valido}
          onClick={() => onConfirmar(motivo.trim())}
          className={`${BTN_PRIMARIO} disabled:opacity-50`}
        >
          Continuar
        </button>
      </div>
    </div>
  );
}

export function ConfirmacionToast({
  texto,
  segundosTotal,
  onConfirmar,
  onCancelar,
}: {
  texto: string;
  segundosTotal: number;
  onConfirmar: () => void;
  onCancelar: () => void;
}) {
  const [segundosRestantes, setSegundosRestantes] = useState(segundosTotal);
  // Arranca en el 100% del ancho y, un instante después de montar, pasa al
  // 0% con una transición CSS de `segundosTotal` segundos — el navegador
  // interpola el ancho solo, sin depender de que el re-render de cada
  // segundo caiga justo a tiempo. El paso por `requestAnimationFrame` es
  // necesario: si el 0% se pidiera en el MISMO render que el 100% inicial,
  // el navegador nunca llega a pintar el punto de partida y no hay nada que
  // animar.
  const [vaciando, setVaciando] = useState(false);
  const yaConfirmoRef = useRef(false);
  const confirmarUnaVez = () => {
    if (yaConfirmoRef.current) return;
    yaConfirmoRef.current = true;
    onConfirmar();
  };

  useEffect(() => {
    const id = requestAnimationFrame(() => setVaciando(true));
    return () => cancelAnimationFrame(id);
  }, []);

  useEffect(() => {
    if (segundosRestantes <= 0) {
      confirmarUnaVez();
      return;
    }
    const t = setTimeout(() => setSegundosRestantes((s) => s - 1), 1000);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [segundosRestantes]);

  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-6 p-8 text-center">
      <p className="font-serif text-3xl">{texto}</p>
      {/*
       * El reloj se DIBUJA, no se lee: antes lo único que avisaba de la
       * cuenta atrás era este mismo texto en 16px, taupe, bajo una pregunta
       * de 30px — quien duda pierde la duda contra el reloj sin darse cuenta
       * de que hay un reloj corriendo. La barra se vacía a la misma
       * velocidad con la que baja `segundosRestantes` (comparten
       * `segundosTotal`), así que la lectura visual y la numérica cuentan la
       * misma historia.
       */}
      <div className="w-full max-w-xs">
        <div className="h-2 overflow-hidden rounded-pildora bg-sand" aria-hidden>
          <div
            className="h-full rounded-pildora bg-rojo"
            style={{
              width: vaciando ? "0%" : "100%",
              transition: vaciando ? `width ${segundosTotal}s linear` : "none",
            }}
          />
        </div>
        <p className="mt-2 text-sm text-taupe" aria-live="polite">
          Confirmando en {segundosRestantes}s…
        </p>
      </div>
      {/* Cancelar con el mismo ancho, relleno y peso de letra que Confirmar:
          este es el único momento en que cancelar es gratis, y hasta acá
          las dos cajas medían lo mismo (`px-5 py-3` en las dos) pero
          "Confirmar ahora" ganaba con un rojo sólido contra un simple
          contorno — la única diferencia que debería quedar es esa, de
          color, no de tamaño. */}
      <div className="flex w-full max-w-xs gap-3">
        <button onClick={onCancelar} className={`${BTN_SECUNDARIO} flex-1 py-4 text-lg font-medium`}>
          Cancelar
        </button>
        <button onClick={confirmarUnaVez} className={`${BTN_PRIMARIO} flex-1 py-4 text-lg`}>
          Confirmar ahora
        </button>
      </div>
    </div>
  );
}

// Día ya cerrado (marcó salida final). En vez de un callejón sin salida, muestra su
// historial del día y ofrece reabrir si de verdad volvió a entrar.
export function PantallaCerrado({
  nombre,
  historial,
  onVolviAEntrar,
  onCancelar,
}: {
  nombre: string;
  historial: Array<{ label: string; hora: string }>;
  onVolviAEntrar: () => void;
  onCancelar: () => void;
}) {
  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-6 p-8 text-center">
      <p className="font-serif text-2xl">{nombre}</p>
      {/* Tarjeta, no botón: usa `rounded-superficie` (el token de "tarjetas y
          el contenedor de Tabla"), no `rounded-control` como TILE/BTN_* de
          arriba. */}
      <div className="w-full max-w-sm rounded-superficie border border-sand bg-sand/25 px-5 py-4 text-left">
        <div className="etiqueta mb-2 text-taupe">Tu día de hoy</div>
        <ul className="flex flex-col gap-1.5 text-sm">
          {historial.map((h, i) => (
            <li key={i} className="flex justify-between gap-4">
              <span className="text-tinta">{h.label}</span>
              <span className="text-taupe">{h.hora}</span>
            </li>
          ))}
        </ul>
      </div>
      <p className="text-lg">Ya cerraste tu día. ¿Volviste a entrar?</p>
      <div className="flex w-full max-w-sm flex-col gap-3">
        <button onClick={onVolviAEntrar} className={`${BTN_PRIMARIO} py-5 text-xl`}>
          Sí, volví a entrar
        </button>
        <button onClick={onCancelar} className={BTN_SECUNDARIO}>
          No, ya me voy
        </button>
      </div>
    </div>
  );
}

// Solo aparece cuando el propio terminal ve que hoy no hay ninguna salida a
// refrigerio marcada y la persona está cerrando su día (ver 0353) — nunca en
// cada salida.
export function ConfirmarRefrigerio({
  nombre,
  onElegir,
  onCancelar,
}: {
  nombre: string;
  onElegir: (trabajoCorrido: boolean) => void;
  onCancelar: () => void;
}) {
  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-6 p-8 text-center">
      <p className="font-serif text-2xl">{nombre}</p>
      <p className="max-w-sm text-lg">
        Hoy no marcaste una salida a refrigerio. ¿Trabajaste corrido, sin parar a almorzar?
      </p>
      <div className="flex w-full max-w-sm flex-col gap-3">
        <button onClick={() => onElegir(true)} className={`${BTN_PRIMARIO} py-5 text-xl`}>
          Sí, trabajé corrido
        </button>
        <button onClick={() => onElegir(false)} className={`${TILE} px-5 py-4 text-lg`}>
          No, sí almorcé — se me olvidó marcar
        </button>
      </div>
      <button onClick={onCancelar} className={BTN_ENLACE}>
        Cancelar
      </button>
    </div>
  );
}

const MOTIVOS_REENTRADA = ["Seguiré laborando", "Solicitud del equipo", "Mi turno aún no termina"];

export function MotivoReentrada({
  onElegir,
  onCancelar,
}: {
  onElegir: (motivo: string) => void;
  onCancelar: () => void;
}) {
  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-6 p-8">
      <p className="font-serif text-2xl">¿Por qué volviste a entrar?</p>
      <div className="flex w-full max-w-sm flex-col gap-3">
        {MOTIVOS_REENTRADA.map((m) => (
          <button key={m} onClick={() => onElegir(m)} className={`${TILE} px-5 py-4 text-lg`}>
            {m}
          </button>
        ))}
      </div>
      <button onClick={onCancelar} className={BTN_ENLACE}>
        Cancelar
      </button>
    </div>
  );
}

/**
 * El cartel que ve la persona antes de darse la vuelta.
 *
 * `tono` existe porque hasta el 2026-08-10 un rechazo del servidor se pintaba
 * EXACTAMENTE igual que un «Listo»: mismo tamaño, mismo color, mismos dos
 * segundos y medio. Cambiar solo el texto habría dejado el arreglo a medias —
 * en una pantalla que se limpia sola, lo que distingue una buena noticia de una
 * mala es sobre todo el color, y quien marca lo mira de reojo mientras guarda
 * el celular.
 */
export function PantallaMensaje({ mensaje, tono = "ok" }: { mensaje: string; tono?: "ok" | "alerta" }) {
  const alerta = tono === "alerta";
  return (
    <div className={`flex flex-1 flex-col items-center justify-center gap-4 p-8 text-center ${alerta ? "bg-rojo/[0.06]" : ""}`}>
      {alerta && <span aria-hidden className="text-5xl">⚠️</span>}
      <p className={`font-serif text-3xl ${alerta ? "font-medium text-rojo" : ""}`} role={alerta ? "alert" : undefined}>
        {mensaje}
      </p>
    </div>
  );
}

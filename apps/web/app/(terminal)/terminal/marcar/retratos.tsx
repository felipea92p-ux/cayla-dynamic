"use client";

import { useEffect, useId, useLayoutEffect, useMemo, useRef, useState, useSyncExternalStore, type CSSProperties, type ReactNode } from "react";
import { Check, ChevronDown, ChevronsUpDown, MapPin, TriangleAlert, Undo2, Warehouse } from "lucide-react";
import { TZ_LIMA, etiquetaDePrueba } from "@cayla-dynamic/shared";
import { createTerminalSupabaseClient } from "@cayla-dynamic/database";
import { Colibri } from "@/components/marca";
import type { RosterEntry } from "@/lib/terminal/offline-db";
import { ORDEN_PRESENCIA, type ClavePresencia, type PresenciaCasilla } from "@/lib/terminal/presencia";
import { acomodarRetratos, type Acomodo } from "@/lib/terminal/acomodo";
import { inicialesDe, urlPublicaFotoPerfil } from "@/lib/foto-perfil";
import { NombreGrid, type EstadoRoster } from "./components";
import { ESTILO_PRESENCIA, etiquetaDePresencia } from "./presencia-visual";

// La pantalla de nombres en retratos (Felipe, 2026-11-21). Solo existe con el vidrio del terminal encendido: sus clases
// `tr-…` no tienen ninguna regla sin el atributo (estilos/vidrio/terminal-retratos.css), y marcar/page.tsx solo la dibuja
// si `interruptoresVidrio().terminal`. Apagado, la pantalla es la de casillas de marcar/components.tsx, sin tocar.
//
// AQUÍ NO HAY NINGUNA REGLA DE MARCAJE. Estas piezas reciben lo mismo que recibían las de antes —el equipo, en qué punto
// del día está cada quien, qué pasa al tocar— y solo le ponen otra cara. Qué se ofrece a quién y qué se registra sigue
// viviendo en marcar/page.tsx y en lib/terminal.

/** La marca del terminal: el colibrí, «CAYLA» y para qué sirve esta pantalla. */
export function MarcaTerminal() {
  return (
    <div className="tr-marca">
      <Colibri tono="rojo" className="w-11" />
      <span className="flex flex-col">
        <span className="tr-marca-palabra">CAYLA</span>
        <span className="etiqueta tr-marca-bajada">Terminal de marcaje</span>
      </span>
    </div>
  );
}

// El reloj de la isla. Mismos formatos y misma zona horaria que `components/reloj.tsx`: la hora de Lima, no la del
// navegador, y `TZ_LIMA` viene de `fecha-lima.ts` (CLAUDE.md: esa zona no se escribe en ningún otro sitio).
const fHora = new Intl.DateTimeFormat("es-PE", { timeZone: TZ_LIMA, hour: "2-digit", minute: "2-digit", hour12: false });
const fDia = new Intl.DateTimeFormat("es-PE", { timeZone: TZ_LIMA, weekday: "long" });
const fFecha = new Intl.DateTimeFormat("es-PE", { timeZone: TZ_LIMA, day: "numeric", month: "long" });
const fSegundo = new Intl.DateTimeFormat("en-US", { timeZone: TZ_LIMA, second: "2-digit" });

// El reloj es algo de fuera de React que cambia cada segundo: se lee con `useSyncExternalStore`, que es para eso. El
// servidor no sabe qué hora es en la sede, así que su foto es «sin hora»: pintar la suya haría saltar el texto al cargar.
function suscribirAlSegundo(avisar: () => void) {
  const t = window.setInterval(avisar, 1000);
  return () => window.clearInterval(t);
}
const segundoDeAhora = () => Math.floor(Date.now() / 1000);
const sinHora = () => null;

function RelojDeIsla() {
  const instante = useSyncExternalStore(suscribirAlSegundo, segundoDeAhora, sinHora);
  const ahora = instante === null ? null : new Date(instante * 1000);
  const segundo = ahora ? Number(fSegundo.format(ahora)) : 0;
  return (
    <>
      <div className="tr-reloj">
        <span className="tr-hora font-serif">{ahora ? fHora.format(ahora) : " "}</span>
        <span className="tr-segundos" aria-hidden>
          <i style={{ height: `${(segundo / 60) * 100}%` }} />
        </span>
      </div>
      <span className="tr-isla-raya" aria-hidden />
      <div>
        <div className="tr-dia font-serif">{ahora ? fDia.format(ahora) : " "}</div>
        <div className="tr-fecha">{ahora ? fFecha.format(ahora) : " "}</div>
      </div>
    </>
  );
}

/**
 * La isla: hora, fecha y sede. Es lo único de la pantalla de nombres que flota, y por eso lo único con desenfoque.
 * `sede` es lo que va en el tercer tramo: el selector, o el nombre a secas si el terminal solo ve una sede.
 *
 * Y es donde sale el «Listo» de una marca que quedó bien (`listo`): la isla entera pasa a decirlo unos segundos y
 * vuelve sola a la hora. Tocarla lo quita antes (`onCerrarListo`), para quien venía a cambiar de sede.
 */
export function IslaTerminal({
  sede,
  listo = null,
  onCerrarListo,
}: {
  sede: ReactNode;
  listo?: { texto: string; detalle: string | null } | null;
  onCerrarListo?: () => void;
}) {
  return (
    <div className="tr-isla" data-listo={listo ? "" : undefined} onPointerDown={listo ? onCerrarListo : undefined}>
      <RelojDeIsla />
      <span className="tr-isla-raya" aria-hidden />
      <div className="tr-isla-sede">
        <MapPin size={21} strokeWidth={1.8} aria-hidden />
        {sede}
      </div>
      <ListoDeIsla listo={listo} />
    </div>
  );
}

/**
 * La buena noticia de una marca, dentro de la isla. Es el `AvisoListo` de la pantalla de casillas con otro dibujo, y
 * guarda sus tres cuidados, que no son adorno:
 *   · No ocupa lugar: va ENCIMA de la isla, que no cambia de tamaño. Si empujara algo, los retratos se moverían bajo
 *     el dedo de la persona siguiente justo al aparecer y al irse, y un toque caería en el nombre de al lado.
 *   · No tapa ningún nombre ni recibe toques: la isla está sobre la grilla, no en ella. Lo único que cubre es el
 *     selector de sede, que mientras tanto no se ve ni se puede tocar; un toque en la isla quita el aviso.
 *   · Nombra siempre a la persona, y sigue a la vista —por encima del velo— aunque la siguiente ya esté marcando.
 *
 * La región que lo anuncia existe siempre, vacía: un lector de pantalla solo anuncia lo que cambia dentro de una
 * región que ya conocía. La mala noticia NO pasa por aquí: sigue ocupando la pantalla entera.
 */
function ListoDeIsla({ listo }: { listo: { texto: string; detalle: string | null } | null }) {
  return (
    <div className="tr-listo" role="status" aria-live="polite">
      {listo && (
        <>
          <span className="tr-listo-visto" aria-hidden>
            <Check size={22} strokeWidth={2.6} />
          </span>
          <div className="tr-listo-texto">
            <p className="tr-listo-frase font-serif">{listo.texto}</p>
            {listo.detalle && (
              <p className="tr-listo-detalle">
                <Warehouse size={16} strokeWidth={2} aria-hidden />
                {listo.detalle}
              </p>
            )}
          </div>
        </>
      )}
    </div>
  );
}

/**
 * Qué sede se está viendo, y la lista para cambiarla. El terminal abre en SU sede; esto deja ver otra a quien está de
 * visita, igual que las píldoras de la pantalla de casillas: elegir una sede llama a `onCambiar`, nada más. Con una sola
 * sede a la vista no hay nada que elegir y se muestra su nombre.
 *
 * Es una lista propia y no un `<select>` del navegador: el menú del sistema en una Mac tiene opciones de 22 px de alto,
 * y aquí nada que se toque mide menos de 48.
 */
export function SedeDeIsla({
  sedes,
  activa,
  sedeDeLaMac,
  onCambiar,
}: {
  sedes: Array<{ codigo: string; nombre: string }>;
  activa: string | null;
  /** El código de la sede de este terminal: en la lista lleva «Esta Mac». */
  sedeDeLaMac: string | null;
  onCambiar: (codigo: string) => void;
}) {
  const [abierta, setAbierta] = useState(false);
  const caja = useRef<HTMLDivElement>(null);
  const idLista = useId();
  const nombre = sedes.find((s) => s.codigo === activa)?.nombre ?? "…";

  // Abierta, se cierra al tocar fuera o con Escape: una lista que se queda abierta tapa los primeros retratos.
  useEffect(() => {
    if (!abierta) return;
    const alTocar = (e: PointerEvent) => {
      if (!caja.current?.contains(e.target as Node)) setAbierta(false);
    };
    const alTeclear = (e: KeyboardEvent) => {
      if (e.key === "Escape") setAbierta(false);
    };
    document.addEventListener("pointerdown", alTocar);
    document.addEventListener("keydown", alTeclear);
    return () => {
      document.removeEventListener("pointerdown", alTocar);
      document.removeEventListener("keydown", alTeclear);
    };
  }, [abierta]);

  if (sedes.length <= 1) {
    return (
      <div className="tr-sede">
        <div className="etiqueta tr-sede-rotulo">Estás viendo</div>
        <div className="tr-sede-nombre font-serif">{nombre}</div>
      </div>
    );
  }

  return (
    <div className="tr-sede" ref={caja}>
      <div className="etiqueta tr-sede-rotulo">Estás viendo</div>
      <button
        type="button"
        className="tr-sede-boton"
        aria-haspopup="listbox"
        aria-expanded={abierta}
        aria-controls={idLista}
        aria-label={`Estás viendo ${nombre}. Cambiar de sede`}
        onClick={() => setAbierta((a) => !a)}
      >
        <span>{nombre}</span>
        <ChevronsUpDown size={18} strokeWidth={2} aria-hidden />
      </button>
      {abierta && (
        <div className="tr-sede-lista" role="listbox" id={idLista} aria-label="Sede">
          {sedes.map((s) => {
            const elegida = s.codigo === activa;
            return (
              <button
                key={s.codigo}
                type="button"
                role="option"
                aria-selected={elegida}
                className="tr-sede-opcion"
                onClick={() => {
                  setAbierta(false);
                  if (!elegida) onCambiar(s.codigo);
                }}
              >
                <span className="tr-sede-opcion-nombre">{s.nombre}</span>
                {s.codigo === sedeDeLaMac && <span className="tr-sede-opcion-nota">Esta Mac</span>}
                {elegida && <Check size={18} strokeWidth={2.5} aria-hidden />}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

/**
 * El aviso de que la lista NO es la de esta sede. Sin él, quien llega a marcar después de una visita no encuentra su
 * nombre y no sabe por qué. El botón hace lo mismo que elegir la sede de la Mac en la lista de arriba.
 */
export function AvisoOtraSede({ viendo, casa, onVolver }: { viendo: string; casa: string; onVolver: () => void }) {
  return (
    <div className="tr-aviso-sede" role="status">
      <span className="tr-aviso-sede-texto">
        <TriangleAlert size={21} strokeWidth={1.9} aria-hidden />
        <span>
          Estás viendo <strong>{viendo}</strong>. Esta Mac es de {casa}.
        </span>
      </span>
      <button type="button" className="tr-aviso-sede-boton" onClick={onVolver}>
        <Undo2 size={18} strokeWidth={2.25} aria-hidden />
        Volver a {casa}
      </button>
    </div>
  );
}

/**
 * El título y la leyenda. Cada estado que existe es una gota con su ícono, su palabra y cuánta gente hay en él; un
 * estado en cero NO se dibuja (en una sede de cuatro personas la leyenda sería casi puro cero). Tocar uno ilumina a
 * quienes lo tienen y atenúa al resto; volver a tocarlo lo apaga. Ilumina, no oculta: nadie pierde su nombre de la
 * pantalla. Sin `conteos` —todavía no se confirmó el estado de hoy— no hay leyenda: no se dice nada de nadie.
 */
export function TituloYLeyenda({
  integrantes,
  conteos,
  resaltado,
  onResaltar,
}: {
  integrantes: number;
  conteos?: Record<ClavePresencia, number>;
  resaltado: ClavePresencia | null;
  onResaltar: (clave: ClavePresencia | null) => void;
}) {
  return (
    // En una pantalla ancha la leyenda sube a la fila del título (terminal-retratos.css): son 60 px más de alto para los
    // retratos, que es justo lo que le falta a una sede de más de veinte personas.
    <div className="tr-titulo-fila">
      <div>
        <h1 className="tr-titulo font-serif">Encuentra tu nombre</h1>
        <p className="tr-bajada">
          Toca tu retrato para registrar tu marcaje
          {integrantes > 0 && ` · ${integrantes} ${integrantes === 1 ? "integrante" : "integrantes"}, en orden alfabético`}
        </p>
      </div>
      {conteos && integrantes > 0 && (
        <div className="tr-leyenda" role="group" aria-label="Estados">
          {ORDEN_PRESENCIA.filter((c) => conteos[c] > 0).map((c) => {
            const e = ESTILO_PRESENCIA[c];
            const Icono = e.Icono;
            const activo = resaltado === c;
            const etiqueta = etiquetaDePresencia(c);
            return (
              <button
                key={c}
                type="button"
                className="tr-chip"
                aria-pressed={activo}
                aria-label={`${etiqueta}: ${conteos[c]}`}
                onClick={() => onResaltar(activo ? null : c)}
              >
                <span className={`tr-chip-circulo ${e.texto}`}>
                  <Icono size={14} strokeWidth={2.5} aria-hidden />
                </span>
                <span>{etiqueta}</span>
                <span className="tr-chip-cuenta">{conteos[c]}</span>
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

/**
 * La foto que cada quien sube desde «Lo mío» (0381), o sus iniciales mientras no haya subido ninguna: nunca un hueco ni
 * un ícono de imagen rota. Si la foto no carga —sin internet, que es justo cuando el terminal trabaja de memoria— vuelve
 * a las iniciales (`onError`), igual que en la pantalla de casillas. NO es una prueba de identidad: se marca sin PIN.
 */
export function FotoRetrato({ persona, className = "" }: { persona: RosterEntry; className?: string }) {
  // El cliente es un singleton cacheado: pedirlo aquí no abre una conexión por cada retrato.
  const supabase = useMemo(() => createTerminalSupabaseClient(), []);
  const url = urlPublicaFotoPerfil(supabase, persona.fotoUrl);
  const [fallo, setFallo] = useState(false);
  return (
    <span className={`tr-retrato ${className}`} aria-hidden>
      {url && !fallo ? (
        // eslint-disable-next-line @next/next/no-img-element -- foto de un bucket externo, no un asset local
        <img src={url} alt="" onError={() => setFallo(true)} />
      ) : (
        <span className="tr-iniciales font-serif">{inicialesDe(persona.nombres, persona.apellidos)}</span>
      )}
    </span>
  );
}

/** «Preselección · 2 de 3», o null si la persona no está en preselección (0539). Solo informa: marcar es lo mismo. */
function textoDePreseleccion(persona: RosterEntry): string | null {
  if (typeof persona.pruebaDias !== "number" || typeof persona.pruebaPlazo !== "number") return null;
  return etiquetaDePrueba({ dias_trabajados: persona.pruebaDias, dias_plazo: persona.pruebaPlazo }).texto;
}

// Mientras la pantalla no se ha medido se dibuja para la Mac mini de 1920×1080: es el caso de todas las sedes menos una
// excepción, y la primera medida llega antes del primer pintado (`useLayoutEffect`).
const ESPACIO_SIN_MEDIR = { ancho: 1808, alto: 744 };

/**
 * La grilla de retratos. Recibe exactamente lo que recibía `NombreGrid` y hace lo mismo al tocar: llamar a
 * `onSeleccionar`. Lo único propio es el tamaño: mide el espacio que le dejaron y le pregunta a
 * `lib/terminal/acomodo.ts` cuántas columnas y qué alto de retrato, para que el equipo entre completo.
 */
export function GrillaRetratos({
  roster,
  estado,
  presencia,
  resaltado = null,
  onSeleccionar,
  onReintentar,
}: {
  roster: RosterEntry[];
  estado: EstadoRoster;
  /** En qué punto del día está cada persona. Ausente mientras no se confirmó contra el servidor: no se pinta ningún estado. */
  presencia?: Map<string, PresenciaCasilla>;
  resaltado?: ClavePresencia | null;
  onSeleccionar: (persona: RosterEntry) => void;
  onReintentar: () => void;
}) {
  const zona = useRef<HTMLDivElement>(null);
  const [espacio, setEspacio] = useState(ESPACIO_SIN_MEDIR);

  useLayoutEffect(() => {
    const el = zona.current;
    if (!el) return;
    const medir = () => {
      const ancho = el.clientWidth;
      const alto = el.clientHeight;
      // Una medida de cero es una pantalla que todavía no se pintó, no una pantalla sin espacio.
      if (ancho > 0 && alto > 0) setEspacio((antes) => (antes.ancho === ancho && antes.alto === alto ? antes : { ancho, alto }));
    };
    medir();
    const observador = new ResizeObserver(medir);
    observador.observe(el);
    return () => observador.disconnect();
  }, []);

  // Si alguien salió y volvió, su casilla lleva un segundo renglón; se reserva en todas para que las filas no bailen.
  const hayDosRenglones = useMemo(() => {
    if (!presencia) return false;
    for (const p of presencia.values()) if (p.detalle2) return true;
    return false;
  }, [presencia]);

  const acomodo: Acomodo = useMemo(
    () => acomodarRetratos(roster.length, espacio.ancho, espacio.alto, { segundaLinea: hayDosRenglones }),
    [roster.length, espacio, hayDosRenglones],
  );

  // Cargando, sin poder cargar o sin nadie: los tres textos ya existen y dicen qué hacer (sobre todo el del error, que
  // le explica a quien está sola a las ocho qué hacer con su hora). No se copian: los dibuja la pieza que los tiene.
  if (roster.length === 0) {
    return (
      <main className="tr-zona" ref={zona}>
        <div className="tr-zona-centro">
          <NombreGrid roster={roster} estado={estado} onSeleccionar={onSeleccionar} onReintentar={onReintentar} />
        </div>
      </main>
    );
  }

  const medidas = {
    "--tr-ancho": `${acomodo.ancho}px`,
    "--tr-foto": `${acomodo.foto}px`,
    "--tr-letra": `${acomodo.letraNombre}px`,
    "--tr-nombre-alto": `${Math.ceil(acomodo.letraNombre * 1.15)}px`,
    "--tr-separacion": `${acomodo.separacion}px`,
    // El ancho exacto de las columnas: con él la última fila, si queda incompleta, se centra (Felipe, 2026-11-03).
    "--tr-ancho-grilla": `${acomodo.columnas * acomodo.ancho + (acomodo.columnas - 1) * acomodo.separacion}px`,
  } as CSSProperties;

  return (
    <>
      <main className="tr-zona" ref={zona} aria-label="Integrantes de la sede">
        <div className="tr-grilla" data-desliza={acomodo.desliza} style={medidas}>
          {roster.map((persona) => {
            const pres = presencia?.get(persona.id);
            const estilo = pres ? ESTILO_PRESENCIA[pres.clave] : null;
            const Icono = estilo?.Icono;
            const etiqueta = pres ? etiquetaDePresencia(pres.clave) : null;
            const nombre = `${persona.nombres} ${persona.apellidos}`;
            const preseleccion = textoDePreseleccion(persona);
            const encendida = !!pres && resaltado === pres.clave;
            const atenuada = !!pres && resaltado !== null && !encendida;
            return (
              <button
                key={persona.id}
                type="button"
                onClick={() => onSeleccionar(persona)}
                className="tr-casilla"
                // El estado se dice con ícono y hora, y la palabra vive en la leyenda: quien usa lector de pantalla lo
                // escucha aquí completo, igual que en la pantalla de casillas.
                aria-label={
                  pres
                    ? `${nombre}${preseleccion ? `, ${preseleccion}` : ""}: ${etiqueta}${pres.ubicacion === "almacen" ? ", en almacén" : ""}, ${pres.detalle}${pres.detalle2 ? `, ${pres.detalle2}` : ""}`
                    : `${nombre}${preseleccion ? `, ${preseleccion}` : ""}`
                }
                data-prueba={preseleccion ? true : undefined}
                data-apagada={estilo?.apagada || undefined}
                data-encendida={encendida || undefined}
                data-atenuada={atenuada || undefined}
                style={encendida && estilo ? ({ "--c": estilo.tono } as CSSProperties) : undefined}
              >
                {preseleccion && (
                  <span className="tr-cinta" aria-hidden>
                    {preseleccion}
                  </span>
                )}
                {pres?.ubicacion === "almacen" && (
                  <span className="tr-almacen" aria-hidden>
                    <Warehouse size={18} strokeWidth={2.25} />
                  </span>
                )}
                <FotoRetrato persona={persona} />
                <span className="tr-nombre font-serif">{persona.nombres}</span>
                <span className="tr-apellidos">{persona.apellidos}</span>
                <span className="tr-linea" data-lineas={acomodo.renglones}>
                  {pres && estilo && Icono && (
                    <>
                      <Icono size={15} strokeWidth={2.5} className={estilo.texto} aria-hidden />
                      <span className={`tr-linea-texto ${estilo.texto}`}>
                        {pres.detalle}
                        {pres.detalle2 && <span className="tr-linea-extra">{pres.detalle2}</span>}
                      </span>
                    </>
                  )}
                </span>
              </button>
            );
          })}
        </div>
      </main>
      {acomodo.desliza && (
        <div className="tr-desliza">
          Desliza para ver a todo el equipo
          <ChevronDown size={16} strokeWidth={2.25} aria-hidden />
        </div>
      )}
    </>
  );
}

/** El pie: un recordatorio y de qué sede es esta Mac, que con el cambio de sede deja de ser obvio. */
export function PieRetratos({ sedeDeLaMac }: { sedeDeLaMac: string | null }) {
  return (
    <footer className="tr-pie">
      <span>Selecciona únicamente tu nombre antes de marcar</span>
      {sedeDeLaMac && <span>Terminal · {sedeDeLaMac}</span>}
    </footer>
  );
}

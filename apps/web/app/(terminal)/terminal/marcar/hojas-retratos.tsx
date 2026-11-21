"use client";

import { useId, useState, type ReactNode } from "react";
import { ArrowRight, Footprints, LogIn, LogOut, Store, Undo2, Utensils, Warehouse, X, type LucideIcon } from "lucide-react";
import type { TipoMarca } from "@cayla-dynamic/shared";
import type { RosterEntry } from "@/lib/terminal/offline-db";
import type { PresenciaCasilla } from "@/lib/terminal/presencia";
import type { OpcionAlmacen } from "./components";
import { ESTILO_PRESENCIA } from "./presencia-visual";
import { FotoRetrato } from "./retratos";

// Las hojas de marcar de la pantalla de retratos (Felipe, 2026-11-21): «Tu momento» y la de quien ya cerró su día.
// Solo existen con el vidrio del terminal encendido (estilos/vidrio/terminal-retratos.css).
//
// SON LAS MISMAS PREGUNTAS CON OTRA CARA. Cada una recibe lo que recibía su gemela de marcar/components.tsx
// (`SelectorSalida`, `PantallaCerrado`) y ofrece exactamente las mismas opciones, con los mismos textos y en el mismo
// orden: la principal sugerida, la otra, el almacén y las salidas por motivo. Qué se sugiere y qué pasa al tocar lo
// decide marcar/page.tsx. Lo único nuevo es que se ve A QUIÉN se le está preguntando —su foto y cómo va su día—: se
// marca sin PIN, y esa es la última oportunidad de notar que se tocó el nombre de otra persona.

type OpcionSalida = { tipo: TipoMarca; motivoRequerido: boolean; label: string };

/** El ícono de cada marca: el mismo dibujo que ya tiene su estado en la grilla, para no aprender dos idiomas. */
const ICONO_DE_MARCA: Partial<Record<TipoMarca, LucideIcon>> = {
  entrada: LogIn,
  salida_final: LogOut,
  salida_almuerzo: Utensils,
  retorno_almuerzo: Undo2,
  salida_personal: Footprints,
  retorno_personal: Undo2,
  salida_tramite: Footprints,
  retorno_tramite: Undo2,
  salida_medico: Footprints,
  retorno_medico: Undo2,
  salida_otro: Footprints,
  retorno_otro: Undo2,
};

function Opcion({
  Icono,
  titulo,
  nota,
  principal = false,
  onClick,
}: {
  Icono: LucideIcon;
  titulo: string;
  nota?: string;
  principal?: boolean;
  onClick: () => void;
}) {
  return (
    <button type="button" className="tr-opcion" data-principal={principal || undefined} onClick={onClick}>
      <Icono size={23} strokeWidth={1.9} aria-hidden />
      <span>
        {titulo}
        {nota && <small>{nota}</small>}
      </span>
    </button>
  );
}

/** La hoja con su título y su ✕, que hace lo mismo que «Cancelar». Quién es va siempre a la izquierda. */
function Hoja({
  titulo,
  persona,
  onCancelar,
  hoy,
  children,
}: {
  titulo: string;
  persona: RosterEntry;
  onCancelar: () => void;
  /** Lo que va bajo «Tu día de hoy». */
  hoy: ReactNode;
  children: ReactNode;
}) {
  const idTitulo = useId();
  return (
    <div className="tr-hoja" role="dialog" aria-modal="true" aria-labelledby={idTitulo}>
      <div className="tr-hoja-cabeza">
        <h2 id={idTitulo} className="font-serif">
          {titulo}
        </h2>
        <button type="button" className="tr-cerrar" aria-label="Cerrar" onClick={onCancelar}>
          <X size={21} strokeWidth={2} aria-hidden />
        </button>
      </div>
      <div className="tr-momento">
        <section className="tr-perfil">
          <FotoRetrato persona={persona} className="tr-perfil-foto" />
          <h3 className="font-serif">{persona.nombres}</h3>
          <p className="tr-perfil-apellidos">{persona.apellidos}</p>
          {hoy && (
            <>
              <div className="etiqueta tr-perfil-rotulo">Tu día de hoy</div>
              {hoy}
            </>
          )}
        </section>
        <section className="tr-opciones">{children}</section>
      </div>
    </div>
  );
}

/**
 * «Tu momento»: el menú de salida de siempre, asertivo. Una acción principal sugerida (grande), la otra como
 * secundaria, el almacén, y las salidas por motivo bajo «Otra salida».
 *
 * `neutra` cubre el caso en que NI refrigerio NI salida final tienen sentido ahora (ej. entró hace 1 h): las salidas
 * por motivo suben arriba ya abiertas, y principal/secundaria bajan a enlaces. Nada se oculta en ningún caso, solo
 * cambia qué se ve grande. Es la misma regla de `SelectorSalida`; ver `sugerirSalidaPrincipal` en shared.
 */
export function HojaTuMomento({
  persona,
  presencia,
  principal,
  secundaria,
  otras,
  neutra = false,
  aviso,
  almacen,
  onElegir,
  onCancelar,
}: {
  persona: RosterEntry;
  /** En qué punto del día está, si se sabe: es lo que se muestra bajo «Tu día de hoy». */
  presencia?: PresenciaCasilla;
  principal: OpcionSalida;
  secundaria: OpcionSalida | null;
  otras: OpcionSalida[];
  neutra?: boolean;
  /**
   * Para el único caso en que este menú no es una sugerencia sino un respaldo: no se pudo confirmar el estado de la
   * persona y se le pide elegir a mano. Sin esto nada explica por qué de golpe aparece «Entrada» junto a las salidas.
   */
  aviso?: string;
  /** «Voy a almacén» / «Vuelvo a tienda» (0580). Ausente cuando no aplica. NO es un marcaje. */
  almacen?: OpcionAlmacen;
  onElegir: (tipo: TipoMarca, motivoRequerido: boolean) => void;
  onCancelar: () => void;
}) {
  const [mostrarOtras, setMostrarOtras] = useState(false);
  const estilo = presencia ? ESTILO_PRESENCIA[presencia.clave] : null;
  const IconoEstado = estilo?.Icono;

  const hoy =
    presencia || almacen?.estado ? (
      <div className="tr-perfil-hoy">
        {presencia && estilo && IconoEstado && (
          <p className={estilo.texto}>
            <IconoEstado size={17} strokeWidth={2.5} aria-hidden />
            {presencia.detalle}
          </p>
        )}
        {presencia?.detalle2 && <p>{presencia.detalle2}</p>}
        {almacen?.estado && (
          <p className="text-azul" role="status">
            <Warehouse size={17} strokeWidth={2.25} aria-hidden />
            {almacen.estado}
          </p>
        )}
      </div>
    ) : null;

  // Una sola opción que cambia según dónde está: el terminal nunca ofrece las dos a la vez (el doble marcado se
  // previene por diseño, como en los marcajes).
  const opcionAlmacen = almacen ? (
    almacen.enAlmacen ? (
      <Opcion Icono={Store} titulo="Vuelvo a tienda" nota="Sigues en tu turno" onClick={almacen.onVuelvoTienda} />
    ) : (
      <Opcion Icono={Warehouse} titulo="Voy a almacén" nota="Para quedarte un rato, no para traer algo" onClick={almacen.onVoyAlmacen} />
    )
  ) : null;

  const porMotivo = otras.map((op) => (
    <Opcion key={op.tipo} Icono={ICONO_DE_MARCA[op.tipo] ?? ArrowRight} titulo={op.label} onClick={() => onElegir(op.tipo, op.motivoRequerido)} />
  ));

  return (
    <Hoja titulo="Tu momento" persona={persona} onCancelar={onCancelar} hoy={hoy}>
      <div className="etiqueta tr-opciones-rotulo">¿Qué vas a marcar?</div>
      {aviso && (
        <p className="terminal-aviso tr-opciones-aviso" role="alert">
          {aviso}
        </p>
      )}
      {neutra ? (
        <>
          {opcionAlmacen}
          {porMotivo}
          <div className="tr-opciones-enlaces">
            <button type="button" className="tr-enlace" onClick={() => onElegir(principal.tipo, principal.motivoRequerido)}>
              {principal.label}
            </button>
            {secundaria && (
              <button type="button" className="tr-enlace" onClick={() => onElegir(secundaria.tipo, secundaria.motivoRequerido)}>
                {secundaria.label}
              </button>
            )}
          </div>
        </>
      ) : (
        <>
          <Opcion
            principal
            Icono={ICONO_DE_MARCA[principal.tipo] ?? ArrowRight}
            titulo={principal.label}
            onClick={() => onElegir(principal.tipo, principal.motivoRequerido)}
          />
          {secundaria && (
            <Opcion
              Icono={ICONO_DE_MARCA[secundaria.tipo] ?? ArrowRight}
              titulo={secundaria.label}
              onClick={() => onElegir(secundaria.tipo, secundaria.motivoRequerido)}
            />
          )}
          {opcionAlmacen}
          {mostrarOtras ? (
            porMotivo
          ) : (
            <button type="button" className="tr-enlace" onClick={() => setMostrarOtras(true)}>
              Otra salida (personal, médico, trámite…)
            </button>
          )}
        </>
      )}
      <button type="button" className="tr-cancelar" onClick={onCancelar}>
        Cancelar
      </button>
    </Hoja>
  );
}

/**
 * Día ya cerrado (marcó salida final). En vez de un callejón sin salida, muestra su historial del día y ofrece reabrir
 * si de verdad volvió a entrar. Las mismas dos respuestas que `PantallaCerrado`, con los mismos textos.
 */
export function HojaCerrado({
  persona,
  historial,
  onVolviAEntrar,
  onCancelar,
}: {
  persona: RosterEntry;
  historial: Array<{ label: string; hora: string }>;
  onVolviAEntrar: () => void;
  onCancelar: () => void;
}) {
  const hoy =
    historial.length > 0 ? (
      <ul className="tr-perfil-historial">
        {historial.map((h, i) => (
          <li key={i}>
            <span>{h.label}</span>
            <span>{h.hora}</span>
          </li>
        ))}
      </ul>
    ) : null;

  return (
    <Hoja titulo="Tu momento" persona={persona} onCancelar={onCancelar} hoy={hoy}>
      <div className="etiqueta tr-opciones-rotulo">Tu jornada de hoy</div>
      <p className="tr-pregunta font-serif">Ya cerraste tu día. ¿Volviste a entrar?</p>
      <Opcion principal Icono={LogIn} titulo="Sí, volví a entrar" onClick={onVolviAEntrar} />
      <button type="button" className="tr-cancelar" onClick={onCancelar}>
        No, ya me voy
      </button>
    </Hoja>
  );
}

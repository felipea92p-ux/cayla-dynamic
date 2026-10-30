"use client";

import { useRef, useState } from "react";
import { Boton } from "@/components/ui/boton";
import { Campo } from "@/components/ui/campo";
import { HojaInferior } from "@/components/ui/hoja-inferior";
import { OPCIONES_FILTRO_ESTADO } from "@/lib/admin/asistencia-hoy";

// Los filtros del Dashboard en celular. Hasta el 2026-10-06 eran la misma caja
// de escritorio apilada —Buscar, Sede, Estado y «Solo alertas», 310 px de alto—
// y quien abría la pantalla en el teléfono tenía que bajar más de una pantalla
// antes de ver un solo dato.
//
// Aquí queda una sola fila: el buscador (lo que más se usa: «¿está fulana?») y un
// botón «Filtros» con un contador. Sede, Estado y «Solo alertas» viven en una
// hoja que sube desde abajo. El contador existe porque un filtro escondido es un
// filtro olvidado: sin él, alguien con «Solo alertas» prendido de ayer creería
// que la pantalla muestra a todo el mundo. Los filtros de sede, estado y alertas
// se recuerdan entre visitas (useFiltroGuardado), así que el olvido es real.
//
// El buscador NO cuenta en el contador: ya está a la vista, con su texto.
//
// Escritorio no usa esto: ahí la caja de filtros sigue a la vista, en la página.
// El estado (busqueda, sede, estado, alertas) es el mismo de la pantalla, así que
// agrandar la ventana no pierde nada.

interface Props {
  busqueda: string;
  alBuscar: (texto: string) => void;
  /** La verdad de qué sedes existen está en la tabla `sedes`; esto solo las pinta. */
  sedes: { codigo: string; texto: string }[];
  sedeFiltro: string;
  alCambiarSede: (codigo: string) => void;
  estadoFiltro: string;
  alCambiarEstado: (valor: string) => void;
  soloAlertas: boolean;
  alCambiarSoloAlertas: (activo: boolean) => void;
  alLimpiar: () => void;
}

function Chip({ activo, onClick, children }: { activo: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      aria-pressed={activo}
      onClick={onClick}
      // 44 px de alto en total (py-2.5 + text-sm): el mínimo cómodo para el pulgar.
      className={`rounded-full border px-4 py-2.5 text-sm transition-colors ${activo ? "border-tinta bg-tinta text-crema" : "border-taupe text-tinta hover:bg-sand/50"}`}
    >
      {children}
    </button>
  );
}

export function FiltrosCelular({
  busqueda, alBuscar, sedes, sedeFiltro, alCambiarSede, estadoFiltro, alCambiarEstado,
  soloAlertas, alCambiarSoloAlertas, alLimpiar,
}: Props) {
  const [abierta, setAbierta] = useState(false);
  // Quién abrió la hoja, para devolverle el foco al cerrarla (mismo patrón que Equipo).
  const focoAlAbrir = useRef<HTMLElement | null>(null);
  const activos = (sedeFiltro !== "todas" ? 1 : 0) + (estadoFiltro !== "todos" ? 1 : 0) + (soloAlertas ? 1 : 0);

  return (
    <div className="mb-4 flex items-stretch gap-2 sm:hidden">
      <div className="min-w-0 flex-1">
        <Campo
          type="search"
          aria-label="Buscar persona"
          placeholder="Buscar persona…"
          value={busqueda}
          onChange={(e) => alBuscar(e.target.value)}
        />
      </div>
      <Boton
        variante="secundario"
        onClick={(e) => { focoAlAbrir.current = e.currentTarget; setAbierta(true); }}
        aria-haspopup="dialog"
        className="flex shrink-0 items-center gap-2 bg-papel"
      >
        Filtros
        {activos > 0 && (
          <span aria-label={`${activos} activo${activos === 1 ? "" : "s"}`} className="rounded-full bg-tinta px-2 text-xs leading-5 text-crema">
            {activos}
          </span>
        )}
      </Boton>

      <HojaInferior
        abierto={abierta}
        onCerrar={() => setAbierta(false)}
        titulo="Filtros"
        volverElFocoA={focoAlAbrir}
        accion={activos > 0 ? <Boton variante="enlace" tamano="sm" onClick={alLimpiar}>Limpiar</Boton> : undefined}
      >
        {sedes.length > 1 && (
          <section className="mb-5">
            <h3 className="mb-2 text-sm text-taupe">Sede</h3>
            <div className="flex flex-wrap gap-2">
              <Chip activo={sedeFiltro === "todas"} onClick={() => alCambiarSede("todas")}>Todas</Chip>
              {sedes.map((s) => (
                <Chip key={s.codigo} activo={sedeFiltro === s.codigo} onClick={() => alCambiarSede(s.codigo)}>{s.texto}</Chip>
              ))}
            </div>
          </section>
        )}

        <section className="mb-5">
          <h3 className="mb-2 text-sm text-taupe">Estado</h3>
          <div className="flex flex-wrap gap-2">
            <Chip activo={estadoFiltro === "todos"} onClick={() => alCambiarEstado("todos")}>Todos</Chip>
            {OPCIONES_FILTRO_ESTADO.map((o) => (
              <Chip key={o.valor} activo={estadoFiltro === o.valor} onClick={() => alCambiarEstado(o.valor)}>{o.etiqueta}</Chip>
            ))}
          </div>
        </section>

        {/* Un interruptor y no una casilla: una casilla de 16 px es un blanco
            demasiado chico para el pulgar, y todo el renglón es el botón. */}
        <button
          type="button"
          role="switch"
          aria-checked={soloAlertas}
          onClick={() => alCambiarSoloAlertas(!soloAlertas)}
          className="flex w-full items-center justify-between border-t border-sand py-3 text-left text-base text-tinta"
        >
          Solo alertas
          <span aria-hidden className={`relative inline-block h-6 w-10 rounded-full transition-colors ${soloAlertas ? "bg-verde" : "bg-sand"}`}>
            <span className={`absolute top-0.5 size-5 rounded-full bg-papel transition-[left] ${soloAlertas ? "left-[1.125rem]" : "left-0.5"}`} />
          </span>
        </button>

        <Boton variante="primario" onClick={() => setAbierta(false)} className="mt-3 w-full py-3 text-base">
          Ver resultados
        </Boton>
      </HojaInferior>
    </div>
  );
}

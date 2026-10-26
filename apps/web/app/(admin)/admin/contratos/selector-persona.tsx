"use client";

// EL SELECTOR DE PERSONA del generador de contratos (2026-10-19).
//
// Era un desplegable con todos los nombres en fila: con 30 personas obliga a recorrerlos con la vista y no
// dice nada de quién necesita un documento. Quien genera contratos casi siempre llega con una pregunta
// («¿a quién le falta?», «¿quién es de Arequipa?», «busco a Gaby»), así que el selector deja contestarla:
// buscador, sede, y la situación del contrato de cada quien en la propia fila.
//
// La lista NO está a la vista de entrada: flota debajo del buscador y solo cuando se empieza a buscar o a
// filtrar (escribir, o tocar sede/situación). Con alguien ya elegido se muestra como una fila con «Cambiar».
//
// No decide nada de negocio: recibe la situación ya calculada (la del tablero) y solo la muestra y filtra.

import { useEffect, useMemo, useRef, useState } from "react";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { sinTildes } from "@/lib/admin/sin-tildes";

export interface OpcionPersona {
  id: string;
  /** «Apellidos, Nombres», como se ordena y se busca. */
  nombre: string;
  sede: string | null;
  /** Qué documento tiene hoy, en palabras («Nuevo ingreso»); null si ninguno. */
  tipoTexto: string | null;
  /** La insignia de la fila: «Sin registrar», «Vence pronto», «Al día»… */
  situacionTexto: string;
  situacionVariante: "neutral" | "alerta" | "advertencia" | "positivo" | "informativo";
  /** Clave de filtro de situación (ver FILTROS_SITUACION). */
  situacion: "sin_contrato" | "atender" | "al_dia";
}

const FILTROS_SITUACION: { clave: OpcionPersona["situacion"] | ""; texto: string }[] = [
  { clave: "", texto: "Cualquier situación" },
  { clave: "sin_contrato", texto: "Sin contrato" },
  { clave: "atender", texto: "Por atender" },
  { clave: "al_dia", texto: "Al día" },
];

export function SelectorPersona({
  opciones,
  value,
  onChange,
  disabled,
}: {
  opciones: OpcionPersona[];
  value: string;
  onChange: (id: string) => void;
  /** Un borrador es de quien es: al editarlo no se cambia la persona. */
  disabled?: boolean;
}) {
  const [busca, setBusca] = useState("");
  const [sede, setSede] = useState("");
  const [situacion, setSituacion] = useState<OpcionPersona["situacion"] | "">("");
  const [abierta, setAbierta] = useState(false);
  const [cambiando, setCambiando] = useState(false);
  const caja = useRef<HTMLDivElement>(null);

  // Las sedes salen de las personas que hay, no de una lista escrita a mano.
  const sedes = useMemo(
    () => [...new Set(opciones.map((o) => o.sede).filter((x): x is string => Boolean(x)))].sort(),
    [opciones],
  );

  // Clic fuera o Escape cierran la lista flotante, igual que el menú «•••».
  useEffect(() => {
    if (!abierta) return;
    const fuera = (e: MouseEvent) => {
      if (caja.current && !caja.current.contains(e.target as Node)) setAbierta(false);
    };
    const tecla = (e: KeyboardEvent) => {
      if (e.key === "Escape") setAbierta(false);
    };
    document.addEventListener("mousedown", fuera);
    document.addEventListener("keydown", tecla);
    return () => {
      document.removeEventListener("mousedown", fuera);
      document.removeEventListener("keydown", tecla);
    };
  }, [abierta]);

  const q = sinTildes(busca.trim());
  const visibles = opciones.filter(
    (o) =>
      (q === "" || sinTildes(o.nombre).includes(q)) &&
      (sede === "" || o.sede === sede) &&
      (situacion === "" || o.situacion === situacion),
  );

  function elegir(id: string) {
    onChange(id);
    setAbierta(false);
    setCambiando(false);
    setBusca("");
    setSede("");
    setSituacion("");
  }

  const elegida = opciones.find((o) => o.id === value);

  // Con alguien elegido: una fila y «Cambiar». La búsqueda reaparece solo si se pide.
  if (elegida && !cambiando) {
    return (
      <div className="space-y-1">
        <span className="text-sm text-taupe">Persona</span>
        <div className="flex items-center justify-between gap-3 rounded-control border border-sand bg-hueso px-3 py-2">
          <span className="min-w-0">
            <span className="block truncate text-sm font-medium text-tinta">{elegida.nombre}</span>
            <span className="block truncate text-xs text-taupe">
              {[elegida.sede, elegida.tipoTexto].filter(Boolean).join(" · ") || "—"}
            </span>
          </span>
          <span className="flex shrink-0 items-center gap-2">
            <Insignia variante={elegida.situacionVariante} tamano="sm">{elegida.situacionTexto}</Insignia>
            {!disabled && (
              <Boton variante="enlace" className="text-xs text-taupe" onClick={() => setCambiando(true)}>
                Cambiar
              </Boton>
            )}
          </span>
        </div>
      </div>
    );
  }

  return (
    <div ref={caja} className="relative space-y-2">
      <span className="text-sm text-taupe">Persona</span>
      <div className="flex flex-wrap items-center gap-2">
        <div className="min-w-44 flex-1">
          <Campo
            tamano="sm"
            aria-label="Buscar persona por nombre"
            aria-expanded={abierta}
            placeholder="Buscar por nombre"
            value={busca}
            disabled={disabled}
            autoFocus={cambiando}
            onChange={(e) => {
              setBusca(e.target.value);
              setAbierta(true);
            }}
            onKeyDown={(e) => {
              // Una sola coincidencia: Enter la elige, sin tener que apuntar con el mouse.
              if (e.key === "Enter" && abierta && visibles.length === 1) {
                e.preventDefault();
                elegir(visibles[0].id);
              }
            }}
          />
        </div>
        <div className="w-full sm:w-36">
          <CampoSelect
            tamano="sm"
            aria-label="Filtrar por sede"
            value={sede}
            disabled={disabled}
            onChange={(e) => {
              setSede(e.target.value);
              setAbierta(true);
            }}
          >
            <option value="">Todas las sedes</option>
            {sedes.map((s) => (
              <option key={s} value={s}>{s}</option>
            ))}
          </CampoSelect>
        </div>
        <div className="w-full sm:w-44">
          <CampoSelect
            tamano="sm"
            aria-label="Filtrar por situación del contrato"
            value={situacion}
            disabled={disabled}
            onChange={(e) => {
              setSituacion(e.target.value as OpcionPersona["situacion"] | "");
              setAbierta(true);
            }}
          >
            {FILTROS_SITUACION.map((f) => (
              <option key={f.clave} value={f.clave}>{f.texto}</option>
            ))}
          </CampoSelect>
        </div>
      </div>

      {abierta && (
        <div className="absolute left-0 right-0 top-full z-30 mt-1 max-h-72 overflow-y-auto rounded-control border border-sand bg-papel shadow-lg">
          {visibles.length === 0 ? (
            <p className="px-4 py-3 text-sm text-taupe">No hay personas con estos filtros.</p>
          ) : (
            <ul className="divide-y divide-sand" role="listbox" aria-label="Personas">
              {visibles.map((o) => (
                <li key={o.id} role="option" aria-selected={o.id === value}>
                  <button
                    type="button"
                    onClick={() => elegir(o.id)}
                    className="flex w-full items-center justify-between gap-3 px-4 py-2.5 text-left transition-colors duration-150 hover:bg-crema/60"
                  >
                    <span className="min-w-0">
                      <span className="block truncate text-sm text-tinta">{o.nombre}</span>
                      <span className="block truncate text-xs text-taupe">
                        {[o.sede, o.tipoTexto].filter(Boolean).join(" · ") || "—"}
                      </span>
                    </span>
                    <Insignia variante={o.situacionVariante} tamano="sm">{o.situacionTexto}</Insignia>
                  </button>
                </li>
              ))}
            </ul>
          )}
          <p className="border-t border-sand px-4 py-1.5 text-xs text-taupe">
            {visibles.length} de {opciones.length} personas
          </p>
        </div>
      )}
    </div>
  );
}

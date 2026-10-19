"use client";

// EL SELECTOR DE PERSONA del generador de contratos (2026-10-19).
//
// Era un desplegable con todos los nombres en fila: con 30 personas obliga a recorrerlos con la vista y no
// dice nada de quién necesita un documento. Quien genera contratos casi siempre llega con una pregunta
// («¿a quién le falta?», «¿quién es de Arequipa?», «busco a Gaby»), así que el selector deja contestarla:
// buscador, sede, y la situación del contrato de cada quien en la propia fila.
//
// No decide nada de negocio: recibe la situación ya calculada (la del tablero) y solo la muestra y filtra.

import { useMemo, useState } from "react";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { EstadoVacio } from "@/components/ui/estado-vacio";
import { Insignia } from "@/components/ui/insignia";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { cx } from "@/components/ui/cx";
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

  // Las sedes salen de las personas que hay, no de una lista escrita a mano.
  const sedes = useMemo(
    () => [...new Set(opciones.map((o) => o.sede).filter((x): x is string => Boolean(x)))].sort(),
    [opciones],
  );

  const q = sinTildes(busca.trim());
  const visibles = opciones.filter(
    (o) =>
      (q === "" || sinTildes(o.nombre).includes(q)) &&
      (sede === "" || o.sede === sede) &&
      (situacion === "" || o.situacion === situacion),
  );
  const hayFiltro = q !== "" || sede !== "" || situacion !== "";

  return (
    <div className="space-y-2">
      <span className="text-sm text-taupe">Persona</span>
      <div className="flex flex-wrap items-center gap-2">
        <div className="min-w-44 flex-1">
          <Campo
            tamano="sm"
            aria-label="Buscar persona por nombre"
            placeholder="Buscar por nombre"
            value={busca}
            disabled={disabled}
            onChange={(e) => setBusca(e.target.value)}
            onKeyDown={(e) => {
              // Una sola coincidencia: Enter la elige, sin tener que apuntar con el mouse.
              if (e.key === "Enter" && visibles.length === 1) {
                e.preventDefault();
                onChange(visibles[0].id);
              }
            }}
          />
        </div>
        <div className="w-full sm:w-36">
          <CampoSelect tamano="sm" aria-label="Filtrar por sede" value={sede} disabled={disabled} onChange={(e) => setSede(e.target.value)}>
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
            onChange={(e) => setSituacion(e.target.value as OpcionPersona["situacion"] | "")}
          >
            {FILTROS_SITUACION.map((f) => (
              <option key={f.clave} value={f.clave}>{f.texto}</option>
            ))}
          </CampoSelect>
        </div>
      </div>

      {visibles.length === 0 ? (
        <EstadoVacio>No hay personas con estos filtros.</EstadoVacio>
      ) : (
        <TarjetaInfo className="max-h-72 overflow-y-auto p-0 sm:p-0">
          <ul className="divide-y divide-sand" role="listbox" aria-label="Personas" aria-disabled={disabled}>
            {visibles.map((o) => {
              const elegida = o.id === value;
              return (
                <li key={o.id} role="option" aria-selected={elegida}>
                  <button
                    type="button"
                    disabled={disabled}
                    onClick={() => onChange(o.id)}
                    className={cx(
                      "flex w-full items-center justify-between gap-3 px-4 py-2.5 text-left transition-colors duration-150 disabled:cursor-not-allowed",
                      elegida ? "bg-rojo/5" : "hover:bg-crema/60 disabled:hover:bg-transparent",
                    )}
                  >
                    <span className="min-w-0">
                      <span className={cx("block truncate text-sm text-tinta", elegida && "font-medium")}>{o.nombre}</span>
                      <span className="block truncate text-xs text-taupe">
                        {[o.sede, o.tipoTexto].filter(Boolean).join(" · ") || "—"}
                      </span>
                    </span>
                    <Insignia variante={o.situacionVariante} tamano="sm">{o.situacionTexto}</Insignia>
                  </button>
                </li>
              );
            })}
          </ul>
        </TarjetaInfo>
      )}
      {hayFiltro && (
        <p className="text-xs text-taupe">
          {visibles.length} de {opciones.length} personas
        </p>
      )}
    </div>
  );
}

"use client";

// El buscador (⌘K) del panel: salta a cualquier pantalla o a la ficha de
// alguien del equipo sin pasar por el menú. Vive suelto de `nav.tsx` —que
// decide CUÁNDO se abre y con qué pantallas cuenta— para no mezclar "qué ve
// cada rol" (ahí, ya resuelto) con "cómo se busca dentro de eso" (acá).

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { Search, UserRound, X } from "lucide-react";
import type { Item } from "@/app/(admin)/admin/nav";

// Sin tildes ni mayúsculas, igual que el filtro de Equipo: buscar "nunez"
// tiene que encontrar a "Núñez". No se comparte un helper por esto solo —cada
// pantalla que lo necesita ya lo escribe en dos líneas— así que acá también.
function sinTildes(t: string): string {
  return t.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase();
}

type PersonaResultado = { id: string; nombres: string; apellidos: string; estado: string };

type Fila =
  | { tipo: "pantalla"; item: Item }
  | { tipo: "persona"; persona: PersonaResultado };

export function BuscadorGlobal({
  grupos,
  abierto,
  onCerrar,
}: {
  grupos: Array<{ label?: string; items: Item[] }>;
  abierto: boolean;
  onCerrar: () => void;
}) {
  const router = useRouter();
  const [consulta, setConsulta] = useState("");
  const [indice, setIndice] = useState(0);
  const [personas, setPersonas] = useState<PersonaResultado[]>([]);
  // Sin un tercer valor "cargando": mientras la consulta no vuelva, "sin-cargar"
  // ya dice exactamente eso — no hace falta un setState extra solo para marcar
  // que empezó, que es lo que un efecto no debería hacer de forma directa.
  const [personasEstado, setPersonasEstado] = useState<"sin-cargar" | "ok" | "error">("sin-cargar");

  // Cada apertura arranca en blanco. No se recuerda la última búsqueda, igual
  // que el filtro de Equipo no recuerda la anterior — y se ajusta durante el
  // render (el patrón que React documenta para esto), no en un efecto: acá no
  // hay nada que sincronizar con el exterior, solo un valor que depende de si
  // `abierto` acaba de cambiar.
  const [abiertoAntes, setAbiertoAntes] = useState(abierto);
  if (abierto !== abiertoAntes) {
    setAbiertoAntes(abierto);
    if (abierto) { setConsulta(""); setIndice(0); }
  }

  // Las personas se cargan una sola vez, la primera vez que alguien abre el
  // buscador — no en cada pantalla del panel, que sería una consulta que casi
  // nadie usa. RLS decide qué fila llega: a quien no le toca ver a nadie, esto
  // simplemente vuelve vacío, y esa es la única regla de permiso que hace falta
  // acá — no se vuelve a decidir el rol.
  useEffect(() => {
    if (!abierto || personasEstado !== "sin-cargar") return;
    let vivo = true;
    void createAdminSupabaseClient()
      .from("personas")
      .select("id, nombres, apellidos, estado")
      .order("nombres")
      .then(({ data, error }) => {
        if (!vivo) return;
        if (error) { setPersonasEstado("error"); return; }
        setPersonas((data ?? []) as PersonaResultado[]);
        setPersonasEstado("ok");
      });
    return () => { vivo = false; };
  }, [abierto, personasEstado]);

  useEffect(() => {
    if (!abierto) return;
    function alPresionar(e: KeyboardEvent) {
      if (e.key === "Escape") onCerrar();
    }
    window.addEventListener("keydown", alPresionar);
    return () => window.removeEventListener("keydown", alPresionar);
  }, [abierto, onCerrar]);

  const pantallas = useMemo(() => grupos.flatMap((g) => g.items), [grupos]);

  const q = sinTildes(consulta.trim());
  // Sin nada escrito: todas las pantallas, para hojear — y ninguna persona,
  // que con ~30 nombres sin filtrar no ayuda a nadie a llegar más rápido.
  const pantallasFiltradas = q ? pantallas.filter((it) => sinTildes(it.label).includes(q)) : pantallas;
  const personasFiltradas = q ? personas.filter((p) => sinTildes(`${p.nombres} ${p.apellidos}`).includes(q)) : [];

  const filas: Fila[] = [
    ...pantallasFiltradas.map((item): Fila => ({ tipo: "pantalla", item })),
    ...personasFiltradas.map((persona): Fila => ({ tipo: "persona", persona })),
  ];
  // La búsqueda puede acortar la lista después de que las flechas ya bajaron
  // más lejos; sin este tope, ⏎ apuntaría a una fila que ya no existe.
  const indiceValido = Math.min(indice, Math.max(filas.length - 1, 0));

  function ir(fila: Fila) {
    router.push(fila.tipo === "pantalla" ? fila.item.href : `/admin/personas/${fila.persona.id}`);
    onCerrar();
  }

  if (!abierto) return null;

  return (
    <>
      <div onClick={onCerrar} className="fixed inset-0 z-40 bg-black/20" aria-hidden />
      <div role="dialog" aria-label="Buscar en Dynamic"
        className="fixed left-1/2 top-24 z-50 w-[calc(100%-2rem)] max-w-lg -translate-x-1/2 overflow-hidden rounded-xl border border-sand bg-papel shadow-xl">
        <div className="flex items-center gap-2.5 border-b border-sand px-4 py-3">
          <Search size={17} strokeWidth={1.8} className="shrink-0 text-taupe" aria-hidden />
          <input
            autoFocus
            value={consulta}
            onChange={(e) => { setConsulta(e.target.value); setIndice(0); }}
            onKeyDown={(e) => {
              if (e.key === "ArrowDown") { e.preventDefault(); setIndice((i) => Math.min(i + 1, filas.length - 1)); }
              else if (e.key === "ArrowUp") { e.preventDefault(); setIndice((i) => Math.max(i - 1, 0)); }
              else if (e.key === "Enter" && filas[indiceValido]) { e.preventDefault(); ir(filas[indiceValido]); }
            }}
            placeholder="Buscar una pantalla o a alguien del equipo…"
            aria-label="Buscar"
            className="w-full bg-transparent text-sm text-tinta placeholder:text-taupe focus:outline-none"
          />
          <button onClick={onCerrar} aria-label="Cerrar buscador"
            className="shrink-0 rounded-md p-1 text-taupe transition hover:bg-sand/40 hover:text-tinta">
            <X size={16} strokeWidth={1.8} aria-hidden />
          </button>
        </div>

        <div className="max-h-[60vh] overflow-y-auto p-2">
          {filas.length === 0 ? (
            <p className="px-3 py-6 text-center text-sm text-taupe">
              {q ? `Nada con «${consulta.trim()}».` : "Escribe para buscar, o elige una pantalla."}
            </p>
          ) : (
            filas.map((fila, i) => {
              const primeraDelGrupo = i === 0 || filas[i - 1].tipo !== fila.tipo;
              const seleccionada = i === indiceValido;
              const key = fila.tipo === "pantalla" ? fila.item.href : `persona-${fila.persona.id}`;
              return (
                <div key={key}>
                  {primeraDelGrupo && (
                    <p className="etiqueta px-3 py-1.5 text-taupe">
                      {fila.tipo === "pantalla" ? "Pantallas" : "Equipo"}
                    </p>
                  )}
                  <button
                    onClick={() => ir(fila)}
                    onMouseEnter={() => setIndice(i)}
                    className={`flex w-full items-center gap-2.5 rounded-md px-3 py-2 text-left text-sm transition ${
                      seleccionada ? "bg-sand/50 text-rojo" : "text-tinta hover:bg-sand/30 hover:text-rojo"}`}
                  >
                    {fila.tipo === "pantalla" ? (
                      <fila.item.Icon size={16} strokeWidth={1.8} className="shrink-0" aria-hidden />
                    ) : (
                      <UserRound size={16} strokeWidth={1.8} className="shrink-0" aria-hidden />
                    )}
                    <span className="truncate">
                      {fila.tipo === "pantalla" ? fila.item.label : `${fila.persona.nombres} ${fila.persona.apellidos}`}
                    </span>
                    {fila.tipo === "persona" && fila.persona.estado !== "activo" && (
                      <span className="ml-auto shrink-0 text-xs text-taupe">inactiva</span>
                    )}
                  </button>
                </div>
              );
            })
          )}
          {q && personasEstado === "sin-cargar" && (
            <p className="px-3 py-2 text-xs text-taupe">Buscando en el equipo…</p>
          )}
        </div>

        <div className="flex items-center justify-end gap-3 border-t border-sand px-4 py-2 text-[11px] text-taupe">
          <span>↑↓ moverse</span>
          <span>↵ ir</span>
          <span>esc cerrar</span>
        </div>
      </div>
    </>
  );
}

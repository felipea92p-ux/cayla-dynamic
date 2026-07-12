"use client";

import { useEffect, useRef, useState } from "react";
import type { TipoMarca } from "@cayla-dynamic/shared";
import type { RosterEntry } from "@/lib/terminal/offline-db";

// Estilos compartidos de la superficie clara del terminal (crema, líneas finas Sand).
const TILE = "rounded-xl border border-sand bg-sand/35 transition-colors hover:bg-sand/70 active:scale-95";
const BTN_PRIMARIO = "rounded-xl bg-rojo px-5 py-3 font-medium text-crema transition-colors hover:bg-rojo-profundo active:scale-95";
const BTN_SECUNDARIO = "rounded-xl border border-sand px-5 py-3 text-tinta transition-colors hover:bg-sand/50";

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
      <div className="flex gap-1 rounded-full border border-sand p-1">
        {sedes.map((s) => (
          <button
            key={s.codigo}
            onClick={() => onCambiar(s.codigo)}
            className={`rounded-full px-4 py-1.5 text-sm transition-colors ${
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

export function NombreGrid({
  roster,
  onSeleccionar,
}: {
  roster: RosterEntry[];
  onSeleccionar: (persona: RosterEntry) => void;
}) {
  if (roster.length === 0) {
    return <p className="text-taupe">Nadie en esta sede todavía.</p>;
  }

  return (
    <div className="grid w-full max-w-2xl grid-cols-2 gap-3 sm:grid-cols-3">
      {roster.map((persona) => (
        <button
          key={persona.id}
          onClick={() => onSeleccionar(persona)}
          className={`${TILE} px-4 py-6 font-serif text-xl`}
        >
          {persona.nombres} {persona.apellidos}
        </button>
      ))}
    </div>
  );
}

export function TecladoPin({
  nombre,
  onCompletar,
  onCancelar,
  error,
}: {
  nombre: string;
  onCompletar: (pin: string) => void;
  onCancelar: () => void;
  error: string | null;
}) {
  const [pin, setPin] = useState("");

  useEffect(() => {
    setPin("");
  }, [error]);

  function tocar(digito: string) {
    if (pin.length >= 4) return;
    const siguiente = pin + digito;
    setPin(siguiente);
    if (siguiente.length === 4) {
      onCompletar(siguiente);
    }
  }

  function borrar() {
    setPin((p) => p.slice(0, -1));
  }

  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-6">
      <p className="font-serif text-2xl">{nombre}</p>
      <p className="text-sm text-taupe">Ingresa tu PIN de 4 dígitos</p>
      <div className="flex gap-3">
        {[0, 1, 2, 3].map((i) => (
          <div
            key={i}
            className={`h-4 w-4 rounded-full border border-sand ${i < pin.length ? "bg-tinta" : "bg-transparent"}`}
          />
        ))}
      </div>
      {error && <p className="text-sm text-rojo">{error}</p>}
      <div className="grid grid-cols-3 gap-3">
        {["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"].map((d, i) =>
          d === "" ? (
            <div key={i} />
          ) : (
            <button
              key={i}
              onClick={() => (d === "⌫" ? borrar() : tocar(d))}
              className={`${TILE} h-16 w-16 rounded-full text-xl`}
            >
              {d}
            </button>
          ),
        )}
      </div>
      <button onClick={onCancelar} className="text-sm text-taupe underline">
        Cancelar
      </button>
    </div>
  );
}

export function SelectorSalida({
  nombre,
  opciones,
  onElegir,
  onCancelar,
}: {
  nombre: string;
  opciones: Array<{ tipo: TipoMarca; motivoRequerido: boolean; label: string }>;
  onElegir: (tipo: TipoMarca, motivoRequerido: boolean) => void;
  onCancelar: () => void;
}) {
  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-6 p-8">
      <p className="font-serif text-2xl">{nombre}</p>
      <p className="text-sm text-taupe">¿A qué sales?</p>
      <div className="grid w-full max-w-sm grid-cols-1 gap-3">
        {opciones.map((op) => (
          <button
            key={op.tipo}
            onClick={() => onElegir(op.tipo, op.motivoRequerido)}
            className={`${TILE} px-5 py-4 text-left text-lg`}
          >
            {op.label}
          </button>
        ))}
      </div>
      <button onClick={onCancelar} className="text-sm text-taupe underline">
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
        className="w-full max-w-sm rounded-lg border border-sand bg-crema p-3 text-tinta outline-none placeholder:text-taupe/60 focus:border-taupe"
        placeholder="Ej: trámite bancario personal"
      />
      <div className="flex gap-3">
        <button onClick={onCancelar} className={BTN_SECUNDARIO}>
          Cancelar
        </button>
        <button
          disabled={!valido}
          onClick={() => onConfirmar(motivo.trim())}
          className={`${BTN_PRIMARIO} disabled:opacity-40`}
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
  const yaConfirmoRef = useRef(false);
  const confirmarUnaVez = () => {
    if (yaConfirmoRef.current) return;
    yaConfirmoRef.current = true;
    onConfirmar();
  };

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
      <p className="text-taupe">Confirmando en {segundosRestantes}s…</p>
      <div className="flex gap-3">
        <button onClick={onCancelar} className={BTN_SECUNDARIO}>
          Cancelar
        </button>
        <button onClick={confirmarUnaVez} className={BTN_PRIMARIO}>
          Confirmar ahora
        </button>
      </div>
    </div>
  );
}

export function PantallaMensaje({ mensaje }: { mensaje: string }) {
  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-4 p-8 text-center">
      <p className="font-serif text-3xl">{mensaje}</p>
    </div>
  );
}

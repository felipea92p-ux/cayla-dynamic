"use client";

import { useEffect, useRef, useState } from "react";
import type { TipoMarca } from "@cayla-dynamic/shared";
import type { RosterEntry } from "@/lib/terminal/offline-db";

export function NombreGrid({
  roster,
  onSeleccionar,
}: {
  roster: RosterEntry[];
  onSeleccionar: (persona: RosterEntry) => void;
}) {
  if (roster.length === 0) {
    return <p className="text-neutral-400">Cargando roster…</p>;
  }

  return (
    <div className="grid w-full max-w-2xl grid-cols-2 gap-3 sm:grid-cols-3">
      {roster.map((persona) => (
        <button
          key={persona.id}
          onClick={() => onSeleccionar(persona)}
          className="rounded-xl bg-neutral-800 px-4 py-6 text-lg font-medium hover:bg-neutral-700 active:scale-95"
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
      <p className="text-xl">{nombre}</p>
      <p className="text-sm text-neutral-400">Ingresa tu PIN de 4 dígitos</p>
      <div className="flex gap-3">
        {[0, 1, 2, 3].map((i) => (
          <div
            key={i}
            className={`h-4 w-4 rounded-full border ${i < pin.length ? "bg-white" : "bg-transparent"}`}
          />
        ))}
      </div>
      {error && <p className="text-sm text-red-400">{error}</p>}
      <div className="grid grid-cols-3 gap-3">
        {["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"].map((d, i) =>
          d === "" ? (
            <div key={i} />
          ) : (
            <button
              key={i}
              onClick={() => (d === "⌫" ? borrar() : tocar(d))}
              className="h-16 w-16 rounded-full bg-neutral-800 text-xl hover:bg-neutral-700 active:scale-95"
            >
              {d}
            </button>
          ),
        )}
      </div>
      <button onClick={onCancelar} className="text-sm text-neutral-400 underline">
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
      <p className="text-xl">{nombre}</p>
      <p className="text-sm text-neutral-400">¿A qué sales?</p>
      <div className="grid w-full max-w-sm grid-cols-1 gap-3">
        {opciones.map((op) => (
          <button
            key={op.tipo}
            onClick={() => onElegir(op.tipo, op.motivoRequerido)}
            className="rounded-xl bg-neutral-800 px-5 py-4 text-left text-lg hover:bg-neutral-700 active:scale-95"
          >
            {op.label}
          </button>
        ))}
      </div>
      <button onClick={onCancelar} className="text-sm text-neutral-400 underline">
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
      <p className="text-lg">Cuéntanos brevemente el motivo</p>
      <textarea
        value={motivo}
        onChange={(e) => setMotivo(e.target.value)}
        rows={3}
        className="w-full max-w-sm rounded-lg bg-neutral-800 p-3 text-white outline-none"
        placeholder="Ej: trámite bancario personal"
      />
      <div className="flex gap-3">
        <button onClick={onCancelar} className="rounded-lg border border-neutral-600 px-4 py-2">
          Cancelar
        </button>
        <button
          disabled={!valido}
          onClick={() => onConfirmar(motivo.trim())}
          className="rounded-lg bg-white px-4 py-2 font-medium text-black disabled:opacity-40"
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
      <p className="text-2xl font-semibold">{texto}</p>
      <p className="text-neutral-400">Confirmando en {segundosRestantes}s…</p>
      <div className="flex gap-3">
        <button onClick={onCancelar} className="rounded-lg border border-neutral-600 px-5 py-3">
          Cancelar
        </button>
        <button onClick={confirmarUnaVez} className="rounded-lg bg-white px-5 py-3 font-medium text-black">
          Confirmar ahora
        </button>
      </div>
    </div>
  );
}

export function PantallaMensaje({ mensaje }: { mensaje: string }) {
  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-4 p-8 text-center">
      <p className="text-2xl">{mensaje}</p>
    </div>
  );
}

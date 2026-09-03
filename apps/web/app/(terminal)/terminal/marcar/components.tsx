"use client";

import { useEffect, useRef, useState } from "react";
import type { MarcajeDelDia, TipoMarca } from "@cayla-dynamic/shared";
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
  marcajesHoy,
  onSeleccionar,
}: {
  roster: RosterEntry[];
  // Solo para el punto de la esquina (¿ya marcó algo hoy?) — la decisión real
  // de qué le toca a continuación sigue viviendo en `siguienteAccionPara`,
  // que se consulta recién al tocar el tile. Este mapa nunca decide nada.
  marcajesHoy: Map<string, MarcajeDelDia[]>;
  onSeleccionar: (persona: RosterEntry) => void;
}) {
  if (roster.length === 0) {
    return <p className="text-taupe">Nadie en esta sede todavía.</p>;
  }

  return (
    <div className="flex w-full max-w-2xl flex-col items-center gap-3">
      <div className="flex items-center gap-5 text-xs text-taupe">
        <span className="flex items-center gap-1.5">
          <span aria-hidden className="h-2.5 w-2.5 rounded-full bg-verde" />
          Ya marcó hoy
        </span>
        <span className="flex items-center gap-1.5">
          <span aria-hidden className="h-2.5 w-2.5 rounded-full border border-sand" />
          Aún no marca
        </span>
      </div>
      <div className="grid w-full grid-cols-2 gap-3 sm:grid-cols-3">
        {roster.map((persona) => {
          const yaMarco = (marcajesHoy.get(persona.id)?.length ?? 0) > 0;
          return (
            <button
              key={persona.id}
              onClick={() => onSeleccionar(persona)}
              className={`${TILE} relative px-4 py-6 font-serif text-xl`}
            >
              {persona.nombres} {persona.apellidos}
              <span
                aria-hidden
                className={`absolute right-3 top-3 h-2.5 w-2.5 rounded-full ${
                  yaMarco ? "bg-verde" : "border border-sand"
                }`}
              />
            </button>
          );
        })}
      </div>
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

type OpcionSalida = { tipo: TipoMarca; motivoRequerido: boolean; label: string };

// Menú de salida asertivo: una acción principal sugerida (grande), la otra opción
// principal como secundaria, y las salidas por motivo escondidas bajo "otra salida".
export function SelectorSalida({
  nombre,
  principal,
  secundaria,
  otras,
  onElegir,
  onCancelar,
}: {
  nombre: string;
  principal: OpcionSalida;
  secundaria: OpcionSalida | null;
  otras: OpcionSalida[];
  onElegir: (tipo: TipoMarca, motivoRequerido: boolean) => void;
  onCancelar: () => void;
}) {
  const [mostrarOtras, setMostrarOtras] = useState(false);
  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-6 p-8">
      <p className="font-serif text-2xl">{nombre}</p>
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
          <button onClick={() => setMostrarOtras(true)} className="mt-1 text-sm text-taupe underline">
            Otra salida (personal, médico, trámite…)
          </button>
        )}
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
      <div className="w-full max-w-sm rounded-xl border border-sand bg-sand/25 px-5 py-4 text-left">
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
      <button onClick={onCancelar} className="text-sm text-taupe underline">
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
      <span
        aria-hidden
        className={`flex h-20 w-20 items-center justify-center rounded-full ${
          alerta ? "bg-rojo/15" : "bg-verde/15"
        }`}
      >
        {alerta ? (
          <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" className="text-rojo">
            <path d="M12 3 2 20h20L12 3Z" />
            <path d="M12 9v5" />
            <circle cx="12" cy="17" r="0.6" fill="currentColor" stroke="none" />
          </svg>
        ) : (
          <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round" className="text-verde">
            <path d="M20 6 9 17l-5-5" />
          </svg>
        )}
      </span>
      <p className={`font-serif text-3xl ${alerta ? "font-medium text-rojo" : ""}`} role={alerta ? "alert" : undefined}>
        {mensaje}
      </p>
    </div>
  );
}

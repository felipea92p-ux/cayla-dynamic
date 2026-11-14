"use client";

import { useState } from "react";
import { formatSoles } from "@/lib/rangos";
import { Boton } from "@/components/ui/boton";
import { Campo } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { fechaCorta, type DecisionAplicada } from "@/lib/admin/provisiones";

// La decisión sobre una ventana ya vencida (0618), dentro del panel de la persona.
//
// Dos cosas, y nada más: decir lo que ya se decidió —cuánto se reconoce, por qué
// y qué calculaba el sistema— y, a la dirección, dejarle registrar o cambiar esa
// decisión. El monto que se pide es el TOTAL que la empresa reconoce para la
// ventana, no «lo que falta»: lo que falta lo saca la pantalla restando lo ya
// depositado, así un depósito posterior no obliga a volver acá.

export type Decidir = (monto: number, motivo: string) => Promise<string | null>;

export function DecisionVentana({
  decision,
  depositado,
  puedeDecidir,
  onDecidir,
}: {
  decision: DecisionAplicada | null;
  /** Lo ya depositado en esa ventana, según el libro. */
  depositado: number;
  puedeDecidir: boolean;
  onDecidir: Decidir;
}) {
  const [abierto, setAbierto] = useState(false);
  const [monto, setMonto] = useState("");
  const [motivo, setMotivo] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [guardando, setGuardando] = useState(false);

  const valor = Number(monto.replace(",", "."));
  const montoValido = monto.trim() !== "" && Number.isFinite(valor) && valor >= 0;
  const falta = montoValido ? Math.max(Math.round((valor - depositado) * 100) / 100, 0) : null;

  async function guardar() {
    if (!montoValido) return setError("Escribe el monto total que se reconoce para esta fecha (puede ser 0).");
    if (motivo.trim().length < 10) return setError("Escribe el motivo de la decisión (al menos 10 letras).");
    setGuardando(true);
    setError(null);
    const fallo = await onDecidir(valor, motivo.trim());
    setGuardando(false);
    if (fallo) return setError(fallo);
    setAbierto(false);
    setMonto("");
    setMotivo("");
  }

  return (
    <div className="grid gap-2 border-t border-sand pt-3 text-sm">
      {decision && (
        <p className="text-taupe">
          <strong className="font-medium text-tinta">Decidido el {fechaCorta(decision.fecha.slice(0, 10))}:</strong> se
          reconocen {formatSoles(decision.reconocido)} para esta fecha. {decision.motivo}{" "}
          {decision.exceso > 0 && `Se depositaron ${formatSoles(decision.exceso)} más de lo reconocido; no se reclaman. `}
          El sistema calculaba un saldo de {formatSoles(decision.saldoDelSistema)}.
        </p>
      )}
      {puedeDecidir && !abierto && (
        <Boton variante="secundario" tamano="sm" className="justify-self-start" onClick={() => setAbierto(true)}>
          {decision ? "Cambiar la decisión" : "Decidir cuánto se reconoce"}
        </Boton>
      )}
      {puedeDecidir && abierto && (
        <div className="grid gap-3">
          <Campo
            etiqueta="Monto total que se reconoce para esta fecha (S/)"
            inputMode="decimal"
            value={monto}
            onChange={(e) => setMonto(e.target.value)}
            placeholder="0.00"
          />
          <p className="text-xs text-taupe">
            Ya se depositaron {formatSoles(depositado)}.
            {falta !== null && ` Con este monto, faltaría depositar ${formatSoles(falta)}.`}
          </p>
          <AreaTexto
            etiqueta="Motivo (queda escrito con tu nombre y la fecha)"
            value={motivo}
            onChange={(e) => setMotivo(e.target.value)}
            rows={2}
          />
          {error && <p className="text-sm text-rojo-profundo">{error}</p>}
          <div className="flex gap-2">
            <Boton variante="primario" tamano="sm" onClick={guardar} disabled={guardando}>
              {guardando ? "Guardando…" : "Registrar la decisión"}
            </Boton>
            <Boton variante="secundario" tamano="sm" onClick={() => setAbierto(false)} disabled={guardando}>
              Cancelar
            </Boton>
          </div>
        </div>
      )}
    </div>
  );
}

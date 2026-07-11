"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import {
  TIPO_MARCA_LABELS,
  type MarcajeDelDia,
  type TipoMarca,
} from "@cayla-dynamic/shared";
import { createTerminalSupabaseClient } from "@cayla-dynamic/database";
import { type RosterEntry, encolarMarcaje } from "@/lib/terminal/offline-db";
import { cargarRoster } from "@/lib/terminal/roster";
import { cargarMarcajesHoyPorPersona, siguienteAccionPara } from "@/lib/terminal/estado-dia";
import { verificarPin } from "@/lib/terminal/pin";
import { leerInfoTerminalCacheada, refrescarInfoTerminal, type TerminalInfo } from "@/lib/terminal/terminal-info";
import { iniciarSincronizacionPeriodica } from "@/lib/terminal/sync";
import {
  ConfirmacionToast,
  FormularioMotivoOtro,
  NombreGrid,
  PantallaMensaje,
  SelectorSalida,
  TecladoPin,
} from "./components";

type Pantalla = "lista" | "pin" | "elegir_salida" | "motivo_otro" | "confirmando" | "mensaje";

const SEGUNDOS_CONFIRMACION = 3;
const SEGUNDOS_MENSAJE = 2.5;

export default function MarcarPage() {
  const router = useRouter();
  const [terminal, setTerminal] = useState<TerminalInfo | null>(null);
  const [roster, setRoster] = useState<RosterEntry[]>([]);
  const marcajesHoyRef = useRef<Map<string, MarcajeDelDia[]>>(new Map());

  const [pantalla, setPantalla] = useState<Pantalla>("lista");
  const [personaActual, setPersonaActual] = useState<RosterEntry | null>(null);
  const [errorPin, setErrorPin] = useState<string | null>(null);
  const [intentosPin, setIntentosPin] = useState(0);
  const [opciones, setOpciones] = useState<Array<{ tipo: TipoMarca; motivoRequerido: boolean; label: string }>>([]);
  const [accionPendiente, setAccionPendiente] = useState<{ tipo: TipoMarca; motivoOtro?: string } | null>(null);
  const [mensaje, setMensaje] = useState("");

  const cargarTodo = useCallback(async () => {
    const [rosterData, marcajes] = await Promise.all([cargarRoster(), cargarMarcajesHoyPorPersona()]);
    setRoster(rosterData);
    marcajesHoyRef.current = marcajes;
  }, []);

  useEffect(() => {
    const supabase = createTerminalSupabaseClient();
    supabase.auth.getSession().then(async ({ data }) => {
      if (!data.session) {
        router.replace("/terminal/vincular");
        return;
      }
      const info = leerInfoTerminalCacheada() ?? (await refrescarInfoTerminal());
      setTerminal(info);
      await cargarTodo();
    });

    const detener = iniciarSincronizacionPeriodica();
    return detener;
  }, [router, cargarTodo]);

  function volverALista() {
    setPantalla("lista");
    setPersonaActual(null);
    setErrorPin(null);
    setIntentosPin(0);
    setOpciones([]);
    setAccionPendiente(null);
    void cargarTodo();
  }

  function seleccionarPersona(persona: RosterEntry) {
    setPersonaActual(persona);
    setErrorPin(null);
    setPantalla("pin");
  }

  async function onPinCompletado(pin: string) {
    if (!personaActual) return;
    const ok = await verificarPin(pin, personaActual.pinHash);
    if (!ok) {
      const intentos = intentosPin + 1;
      setIntentosPin(intentos);
      if (intentos >= 5) {
        setMensaje("Demasiados intentos. Vuelve a intentar en un momento.");
        setPantalla("mensaje");
        setTimeout(volverALista, 4000);
        return;
      }
      setErrorPin("PIN incorrecto, intenta de nuevo.");
      return;
    }

    const marcajesHoy = marcajesHoyRef.current.get(personaActual.id) ?? [];
    const accion = siguienteAccionPara(marcajesHoy);

    if (accion.modo === "cerrado") {
      setMensaje(accion.mensaje);
      setPantalla("mensaje");
      setTimeout(volverALista, SEGUNDOS_MENSAJE * 1000);
      return;
    }

    if (accion.modo === "unico") {
      prepararConfirmacion({ tipo: accion.tipo });
      return;
    }

    setOpciones(
      accion.opciones.map((op) => ({ ...op, label: TIPO_MARCA_LABELS[op.tipo] })),
    );
    setPantalla("elegir_salida");
  }

  function elegirTipoSalida(tipo: TipoMarca, motivoRequerido: boolean) {
    if (motivoRequerido) {
      setAccionPendiente({ tipo });
      setPantalla("motivo_otro");
      return;
    }
    prepararConfirmacion({ tipo });
  }

  function confirmarMotivoOtro(motivo: string) {
    if (!accionPendiente) return;
    prepararConfirmacion({ tipo: accionPendiente.tipo, motivoOtro: motivo });
  }

  function prepararConfirmacion(accion: { tipo: TipoMarca; motivoOtro?: string }) {
    setAccionPendiente(accion);
    setPantalla("confirmando");
  }

  async function confirmarMarcaje() {
    if (!personaActual || !accionPendiente || !terminal) return;

    const entry = {
      clientUuid: crypto.randomUUID(),
      personaId: personaActual.id,
      terminalId: terminal.id,
      tipo: accionPendiente.tipo,
      motivoOtro: accionPendiente.motivoOtro,
      timestampCliente: new Date().toISOString(),
      intentos: 0,
    };

    // Optimista: refleja el marcaje localmente ya mismo para que el siguiente
    // tap (de esta u otra persona) vea el estado correcto sin esperar red.
    const lista = marcajesHoyRef.current.get(personaActual.id) ?? [];
    lista.push({ tipo: entry.tipo, timestamp: entry.timestampCliente });
    marcajesHoyRef.current.set(personaActual.id, lista);

    let sincronizadoAhora = false;
    if (navigator.onLine) {
      const supabase = createTerminalSupabaseClient();
      const { error } = await supabase.rpc("fn_registrar_marcaje", {
        p_persona_id: entry.personaId,
        p_tipo: entry.tipo,
        p_timestamp_cliente: entry.timestampCliente,
        p_client_uuid: entry.clientUuid,
        p_origen: "terminal",
        p_terminal_id: entry.terminalId,
        p_motivo_otro: entry.motivoOtro,
      });
      sincronizadoAhora = !error;
      if (error) await encolarMarcaje(entry);
    } else {
      await encolarMarcaje(entry);
    }

    setMensaje(
      `Listo — ${TIPO_MARCA_LABELS[entry.tipo]} de ${personaActual.nombres}${
        sincronizadoAhora ? "" : " (se sincronizará cuando vuelva la conexión)"
      }`,
    );
    setPantalla("mensaje");
    setTimeout(volverALista, SEGUNDOS_MENSAJE * 1000);
  }

  return (
    <div className="flex flex-1 flex-col">
      <header className="flex items-center justify-between border-b border-neutral-800 px-6 py-4">
        <span className="font-semibold">Dynamic — CAYLA</span>
        <span className="text-neutral-400">{terminal?.sedeNombre ?? "…"}</span>
      </header>

      <main className="flex flex-1 flex-col items-center justify-center p-6">
        {pantalla === "lista" && <NombreGrid roster={roster} onSeleccionar={seleccionarPersona} />}

        {pantalla === "pin" && personaActual && (
          <TecladoPin
            nombre={`${personaActual.nombres} ${personaActual.apellidos}`}
            onCompletar={onPinCompletado}
            onCancelar={volverALista}
            error={errorPin}
          />
        )}

        {pantalla === "elegir_salida" && personaActual && (
          <SelectorSalida
            nombre={`${personaActual.nombres} ${personaActual.apellidos}`}
            opciones={opciones}
            onElegir={elegirTipoSalida}
            onCancelar={volverALista}
          />
        )}

        {pantalla === "motivo_otro" && (
          <FormularioMotivoOtro onConfirmar={confirmarMotivoOtro} onCancelar={volverALista} />
        )}

        {pantalla === "confirmando" && personaActual && accionPendiente && (
          <ConfirmacionToast
            texto={`¿Confirmas ${TIPO_MARCA_LABELS[accionPendiente.tipo]} de ${personaActual.nombres}?`}
            segundosTotal={SEGUNDOS_CONFIRMACION}
            onConfirmar={confirmarMarcaje}
            onCancelar={volverALista}
          />
        )}

        {pantalla === "mensaje" && <PantallaMensaje mensaje={mensaje} />}
      </main>
    </div>
  );
}

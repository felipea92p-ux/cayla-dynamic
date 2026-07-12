"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import {
  TIPO_MARCA_LABELS,
  sugerirSalidaPrincipal,
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
import { Marca } from "@/components/marca";
import { RelojCentral } from "@/components/reloj";
import {
  ConfirmacionToast,
  FormularioMotivoOtro,
  NombreGrid,
  PantallaMensaje,
  SelectorSalida,
  SelectorSede,
  TecladoPin,
} from "./components";

type Pantalla = "lista" | "pin" | "elegir_salida" | "motivo_otro" | "confirmando" | "mensaje";

type OpcionSalida = { tipo: TipoMarca; motivoRequerido: boolean; label: string };
type SalidaConfig = { principal: OpcionSalida; secundaria: OpcionSalida | null; otras: OpcionSalida[] };

// Etiquetas amables para las dos acciones principales del menú de salida.
const LABEL_PRINCIPAL: Partial<Record<TipoMarca, string>> = {
  salida_almuerzo: "Salgo a refrigerio",
  salida_final: "Me voy — salida final",
};

const SEGUNDOS_CONFIRMACION = 3;
const SEGUNDOS_MENSAJE = 2.5;

export default function MarcarPage() {
  const router = useRouter();
  const [terminal, setTerminal] = useState<TerminalInfo | null>(null);
  const [roster, setRoster] = useState<RosterEntry[]>([]);
  const [sedeSeleccionada, setSedeSeleccionada] = useState<string | null>(null);
  const marcajesHoyRef = useRef<Map<string, MarcajeDelDia[]>>(new Map());

  const [pantalla, setPantalla] = useState<Pantalla>("lista");
  const [personaActual, setPersonaActual] = useState<RosterEntry | null>(null);
  const [errorPin, setErrorPin] = useState<string | null>(null);
  const [intentosPin, setIntentosPin] = useState(0);
  const [salidaConfig, setSalidaConfig] = useState<SalidaConfig | null>(null);
  const [accionPendiente, setAccionPendiente] = useState<{ tipo: TipoMarca; motivoOtro?: string; clientUuid?: string } | null>(null);
  const [mensaje, setMensaje] = useState("");
  const confirmandoRef = useRef(false); // evita doble-envío del mismo marcaje

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
      // Preferir info fresca (trae el ajuste de PIN actualizado); usar caché solo sin conexión.
      const info = (typeof navigator !== "undefined" && navigator.onLine
        ? await refrescarInfoTerminal()
        : null) ?? leerInfoTerminalCacheada();
      setTerminal(info);
      // Sede por defecto: la del terminal; un ?sede=CODIGO en la URL la sobreescribe.
      const paramSede =
        typeof window !== "undefined"
          ? new URLSearchParams(window.location.search).get("sede")?.toUpperCase()
          : null;
      setSedeSeleccionada((actual) => actual ?? paramSede ?? info?.sedeCodigo ?? null);
      await cargarTodo();
    });

    const detener = iniciarSincronizacionPeriodica();
    return detener;
  }, [router, cargarTodo]);

  function volverALista() {
    confirmandoRef.current = false;
    setPantalla("lista");
    setPersonaActual(null);
    setErrorPin(null);
    setIntentosPin(0);
    setSalidaConfig(null);
    setAccionPendiente(null);
    void cargarTodo();
  }

  function seleccionarPersona(persona: RosterEntry) {
    setPersonaActual(persona);
    setErrorPin(null);
    // En terminales de confianza (sin PIN) se salta directo a la acción.
    // Solo se salta si el terminal lo pide EXPLÍCITAMENTE (por seguridad, ante duda se pide PIN).
    if (terminal && terminal.requierePin === false) {
      continuarConPersona(persona);
      return;
    }
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
    continuarConPersona(personaActual);
  }

  // Determina y presenta la siguiente acción de la persona (tras autenticar, o directo si el terminal no pide PIN).
  function continuarConPersona(persona: RosterEntry) {
    const marcajesHoy = marcajesHoyRef.current.get(persona.id) ?? [];
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

    // Menú de salida simplificado: 1 acción sugerida (según hora + si ya almorzó hoy),
    // la otra principal como secundaria, y el resto de motivos bajo "otra salida".
    const mk = (tipo: TipoMarca, motivoRequerido: boolean, label?: string): OpcionSalida => ({
      tipo,
      motivoRequerido,
      label: label ?? TIPO_MARCA_LABELS[tipo],
    });
    const yaAlmorzo = marcajesHoy.some((m) => m.tipo === "salida_almuerzo");
    const sugerida = sugerirSalidaPrincipal(marcajesHoy, new Date());
    const almuerzo = mk("salida_almuerzo", false, LABEL_PRINCIPAL.salida_almuerzo);
    const final = mk("salida_final", false, LABEL_PRINCIPAL.salida_final);
    const principal = sugerida === "salida_almuerzo" ? almuerzo : final;
    const secundaria = yaAlmorzo ? null : sugerida === "salida_almuerzo" ? final : almuerzo;
    const otras: OpcionSalida[] = [
      mk("salida_personal", false),
      mk("salida_tramite", false),
      mk("salida_medico", false),
      mk("salida_otro", true),
      ...(yaAlmorzo ? [almuerzo] : []),
    ];
    setSalidaConfig({ principal, secundaria, otras });
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
    // el client_uuid se fija AL PREPARAR: si por algo se envía dos veces, el
    // servidor lo reconoce como el mismo marcaje (idempotencia) y no duplica.
    setAccionPendiente({ ...accion, clientUuid: crypto.randomUUID() });
    setPantalla("confirmando");
  }

  async function confirmarMarcaje() {
    if (!personaActual || !accionPendiente || !terminal) return;
    if (confirmandoRef.current) return; // ya se está procesando este marcaje
    confirmandoRef.current = true;

    const entry = {
      clientUuid: accionPendiente.clientUuid ?? crypto.randomUUID(),
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

  // Sedes presentes en el roster (para el selector) y roster filtrado a la sede activa.
  const sedesDisponibles = useMemo(() => {
    const mapa = new Map<string, string>();
    for (const p of roster) mapa.set(p.sedeCodigo, p.sedeNombre);
    return [...mapa.entries()]
      .map(([codigo, nombre]) => ({ codigo, nombre }))
      .sort((a, b) => a.nombre.localeCompare(b.nombre));
  }, [roster]);

  const rosterFiltrado = useMemo(
    () => (sedeSeleccionada ? roster.filter((p) => p.sedeCodigo === sedeSeleccionada) : roster),
    [roster, sedeSeleccionada],
  );

  const sedeActivaNombre =
    sedesDisponibles.find((s) => s.codigo === sedeSeleccionada)?.nombre ?? terminal?.sedeNombre ?? "…";

  return (
    <div className="flex flex-1 flex-col">
      <header className="flex items-center justify-between border-b border-sand px-6 py-4">
        <Marca tono="tinta" isotipo="rojo" />
        <span className="etiqueta text-taupe">{sedeActivaNombre}</span>
      </header>

      <main className="flex flex-1 flex-col items-center justify-center p-6">
        {pantalla === "lista" && (
          <div className="flex flex-1 flex-col items-center justify-center gap-8">
            <RelojCentral />
            <SelectorSede
              sedes={sedesDisponibles}
              activa={sedeSeleccionada}
              onCambiar={setSedeSeleccionada}
            />
            <NombreGrid roster={rosterFiltrado} onSeleccionar={seleccionarPersona} />
          </div>
        )}

        {pantalla === "pin" && personaActual && (
          <TecladoPin
            nombre={`${personaActual.nombres} ${personaActual.apellidos}`}
            onCompletar={onPinCompletado}
            onCancelar={volverALista}
            error={errorPin}
          />
        )}

        {pantalla === "elegir_salida" && personaActual && salidaConfig && (
          <SelectorSalida
            nombre={`${personaActual.nombres} ${personaActual.apellidos}`}
            principal={salidaConfig.principal}
            secundaria={salidaConfig.secundaria}
            otras={salidaConfig.otras}
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

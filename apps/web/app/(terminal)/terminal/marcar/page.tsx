"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { TIPO_MARCA_LABELS, TZ_LIMA, sugerirSalidaPrincipal, type MarcajeDelDia, type TipoMarca } from "@cayla-dynamic/shared";
import { createTerminalSupabaseClient } from "@cayla-dynamic/database";
import {
  type RosterEntry,
  encolarMarcaje,
  eliminarDeOutbox,
  marcarComoRechazadaPorServidor,
  obtenerDescartadas,
  obtenerPendientes,
} from "@/lib/terminal/offline-db";
import { sincronizarApartadas } from "@/lib/terminal/apartadas";
import { enviarMarcaje } from "@/lib/terminal/enviar-marcaje";
import { conTope, topeDeRed } from "@/lib/terminal/tope-de-red";
import { cargarRoster } from "@/lib/terminal/roster";
import { cargarMarcajesHoyPorPersona, siguienteAccionPara } from "@/lib/terminal/estado-dia";
import { veredictoDeSesion } from "@/lib/terminal/sesion";
import { leerInfoTerminalCacheada, refrescarInfoTerminal, type TerminalInfo } from "@/lib/terminal/terminal-info";
import { iniciarSincronizacionPeriodica } from "@/lib/terminal/sync";
import {
  DESFASE_AVISO_SEG, DESFASE_GRAVE_SEG, leerDesfaseCacheado, medirDesfase, textoDesfase,
  type MedidaDesfase,
} from "@/lib/terminal/reloj-servidor";
import { Marca } from "@/components/marca";
import { RelojCentral } from "@/components/reloj";
import {
  ConfirmacionToast,
  ConfirmarRefrigerio,
  FormularioMotivoOtro,
  MotivoReentrada,
  NombreGrid,
  PantallaCerrado,
  PantallaMensaje,
  SelectorSalida,
  SelectorSede,
  type EstadoRoster,
} from "./components";

type Pantalla =
  | "lista"
  | "elegir_salida"
  | "motivo_otro"
  | "confirmar_refrigerio"
  | "confirmando"
  | "mensaje"
  | "cerrado"
  | "motivo_reentrada";

type OpcionSalida = { tipo: TipoMarca; motivoRequerido: boolean; label: string };
type SalidaConfig = { principal: OpcionSalida; secundaria: OpcionSalida | null; otras: OpcionSalida[] };

// Etiquetas amables para las dos acciones principales del menú de salida.
const LABEL_PRINCIPAL: Partial<Record<TipoMarca, string>> = {
  salida_almuerzo: "Salgo a refrigerio",
  salida_final: "Me voy — salida final",
};

const SEGUNDOS_CONFIRMACION = 3;
const SEGUNDOS_MENSAJE = 2.5;
// Un rechazo se queda MÁS TIEMPO en pantalla. Dos segundos y medio bastan
// para leer «Listo»; no bastan para leer que no quedó registrada, entenderlo
// y decidir ir a buscar a la encargada. El que trae mala noticia espera.
const SEGUNDOS_MENSAJE_ALERTA = 8;

function horaCorta(iso: string): string {
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA,
    hour: "2-digit",
    minute: "2-digit",
    hour12: true,
  }).format(new Date(iso));
}

function historialDelDia(marks: MarcajeDelDia[]): Array<{ label: string; hora: string }> {
  return [...marks]
    .sort((a, b) => a.timestamp.localeCompare(b.timestamp))
    .map((m) => ({ label: TIPO_MARCA_LABELS[m.tipo], hora: horaCorta(m.timestamp) }));
}

// ¿Llega a "salida final" sin haber marcado NUNCA una salida a refrigerio hoy?
// (0353). No es "salió a almorzar y no volvió" —ese caso el propio candado de
// esta función ya lo bloquea antes: tras un salida_almuerzo sin retorno,
// fn_siguiente_tipo_esperado exige retorno_almuerzo, y salida_final ni
// siquiera llega a ofrecerse. Lo único que SÍ es alcanzable desde acá es que
// nunca haya salido: entrada → (todo el turno) → salida_final derecho.
// Solo mira los marcajes de HOY que el terminal ya tiene cargados — no hace
// ninguna llamada nueva al servidor.
function nuncaMarcoRefrigerio(marcajesHoy: MarcajeDelDia[]): boolean {
  return !marcajesHoy.some((m) => m.tipo === "salida_almuerzo");
}

export default function MarcarPage() {
  const router = useRouter();
  const [terminal, setTerminal] = useState<TerminalInfo | null>(null);
  const [roster, setRoster] = useState<RosterEntry[]>([]);
  // Un roster vacío no dice por qué está vacío, y la grilla lo contaba siempre
  // como «Nadie en esta sede todavía» — también durante el arranque, que es
  // justo cuando alguien lo lee (tras reiniciar la Mac mini o un corte de red)
  // y entiende que se borró el equipo. Esta bandera separa los tres casos.
  const [estadoRoster, setEstadoRoster] = useState<EstadoRoster>("cargando");
  const [sedeSeleccionada, setSedeSeleccionada] = useState<string | null>(null);
  const marcajesHoyRef = useRef<Map<string, MarcajeDelDia[]>>(new Map());

  const [pantalla, setPantalla] = useState<Pantalla>("lista");
  const [personaActual, setPersonaActual] = useState<RosterEntry | null>(null);
  const [salidaConfig, setSalidaConfig] = useState<SalidaConfig | null>(null);
  const [historialCerrado, setHistorialCerrado] = useState<Array<{ label: string; hora: string }>>([]);
  const [pendientesSinEnviar, setPendientesSinEnviar] = useState(0);
  const [marcasApartadas, setMarcasApartadas] = useState(0);
  const [accionPendiente, setAccionPendiente] = useState<{
    tipo: TipoMarca; motivoOtro?: string; clientUuid?: string; confirmoSinRefrigerio?: boolean;
  } | null>(null);
  const [mensaje, setMensaje] = useState("");
  const [tonoMensaje, setTonoMensaje] = useState<"ok" | "alerta">("ok");
  // El reloj de ESTA Mac contra el del servidor. Arranca con la última medida
  // guardada: un reloj corrido no se arregla al recargar la página, y que el
  // aviso desapareciera al reiniciar convertiría un problema permanente en uno
  // intermitente — o sea, invisible.
  const [desfase, setDesfase] = useState<MedidaDesfase | null>(null);
  const confirmandoRef = useRef(false); // evita doble-envío del mismo marcaje

  const cargarTodo = useCallback(async () => {
    try {
      const [rosterCargado, marcajes] = await Promise.all([cargarRoster(), cargarMarcajesHoyPorPersona()]);
      setRoster(rosterCargado.entradas);
      marcajesHoyRef.current = marcajes;
      // EL ERROR LO DECLARA LA FUENTE, NO EL `catch`, y esa es la mitad que
      // faltaba: `cargarRoster` no lanza NUNCA por red ni por un 500 —devuelve
      // la copia guardada en las cinco salidas de fallo—, así que una Mac recién
      // reiniciada, sin caché y sin router, resolvía con `[]` y esta pantalla lo
      // declaraba "listo": «Nadie en esta sede todavía», justo la mentira que
      // este estado existe para quitar. Solo `fuente === "ninguna"` significa
      // que no contestó ni el servidor ni la copia local.
      setEstadoRoster(rosterCargado.fuente === "ninguna" ? "error" : "listo");
    } catch {
      // El `catch` queda para lo que sí lanza: IndexedDB (navegación privada,
      // almacenamiento bloqueado). Un refresco que falla con la lista YA en
      // pantalla no la borra ni asusta a nadie: se sigue marcando con lo que
      // hay. Solo se declara error cuando no hemos llegado a tener nada.
      setEstadoRoster((previo) => (previo === "listo" ? "listo" : "error"));
    }
  }, []);

  // El arranque entero, extraído del efecto para que «Volver a intentar» pueda
  // repetirlo. Antes el botón solo llamaba a `cargarTodo`, y el error también
  // puede nacer acá arriba —la sesión, la ficha del terminal—: reintentar sin
  // rehacer esa parte volvía a la lista vacía sin haber arreglado lo que falló.
  //
  // Devuelve la promesa en vez de ser `async`/`await` a propósito: con `await`,
  // el linter de la casa lee la llamada del efecto de abajo como un setState
  // síncrono dentro de un efecto y la marca. Encadenando `.then`, que es la
  // forma que este arranque ya tenía, no hay setState hasta que la red conteste
  // — y era verdad en las dos versiones.
  const arrancar = useCallback(() => {
    const supabase = createTerminalSupabaseClient();
    // getSession() ES LA PRIMERA LLAMADA DE RED DEL ARRANQUE, aunque no lo parezca:
    // cuando el token guardado está vencido, auth-js sale a renovarlo, y no acepta
    // señal de aborto. De ahí el `conTope` en vez de un `.abortSignal()`.
    //
    // El respaldo es SIN_RESPUESTA y no `{ session: null }`, y esa distinción es
    // todo el punto: «no hay sesión» manda a vincular el dispositivo, «no hubo
    // respuesta» tiene que seguir con la caché. Confundirlas mandaría a la sede a
    // una pantalla de vinculación por un corte de red, con el terminal ya vinculado.
    //
    // Y EL TOPE SOLO CUBRE LA MITAD, que es lo que se descubrió el 2026-08-13
    // persiguiendo un terminal que «se deslogueaba a ratos»: cuando el refresco
    // falla RÁPIDO —la red contesta que no hay red— `getSession()` no se cuelga,
    // contesta enseguida `{ session: null, error }` y esta condición lo leía como
    // «no está vinculado». Las credenciales seguían en el disco. Por eso el
    // veredicto mira el error y no solo la sesión (`lib/terminal/sesion.ts`).
    const SIN_RESPUESTA = Symbol("sin respuesta");
    return conTope(supabase.auth.getSession(), SIN_RESPUESTA).then(async (respuesta) => {
      const veredicto =
        respuesta === SIN_RESPUESTA
          ? "no_se_pudo_saber"
          : veredictoDeSesion({ session: respuesta.data.session, error: respuesta.error });
      if (veredicto === "sin_vincular") {
        router.replace("/terminal/vincular");
        return;
      }
      // La config fresca del servidor manda; sin conexión se usa la caché tal cual.
      // Antes esta línea tenía que neutralizar a mano el `requierePin` de la caché,
      // porque el respaldo del cliente caía en `true` y una red intermitente podía
      // hacer aparecer un teclado de PIN. Desde que el PIN se retiró del terminal
      // (0375) no hay nada que neutralizar: la ficha ya no trae esa bandera.
      const fresca =
        typeof navigator !== "undefined" && navigator.onLine ? await refrescarInfoTerminal() : null;
      const cache = leerInfoTerminalCacheada();
      const info = fresca ?? cache;
      setTerminal(info);
      // Sede por defecto: la del terminal; un ?sede=CODIGO en la URL la sobreescribe.
      const paramSede =
        typeof window !== "undefined"
          ? new URLSearchParams(window.location.search).get("sede")?.toUpperCase()
          : null;
      setSedeSeleccionada((actual) => actual ?? paramSede ?? info?.sedeCodigo ?? null);
      await cargarTodo();
    })
    // Si el arranque se cae ANTES de llegar a `cargarTodo` —la ficha del
    // terminal, la sesión— la grilla se quedaba en «cargando» para siempre, que
    // es la misma mentira de antes con otra cara: una pantalla que promete que
    // ya viene. Se declara el error, y el botón de reintentar es la salida.
    .catch(() => setEstadoRoster((previo) => (previo === "listo" ? "listo" : "error")));
  }, [router, cargarTodo]);

  useEffect(() => {
    void arrancar();
    const detener = iniciarSincronizacionPeriodica();
    return detener;
  }, [arrancar]);

  // El desfase del reloj: la última medida guardada primero —para que el aviso
  // esté en pantalla desde el primer segundo— y una medición nueva enseguida.
  // Se repite cada diez minutos: un reloj no se descuadra de golpe, y preguntar
  // más seguido solo añade tráfico a una sede con mala conexión.
  useEffect(() => {
    setDesfase(leerDesfaseCacheado());
    const medir = () => { void medirDesfase().then((m) => { if (m) setDesfase(m); }); };
    medir();
    const t = setInterval(medir, 10 * 60 * 1000);
    return () => clearInterval(t);
  }, []);

  // Vigila cuántas marcas quedan sin enviar al servidor (para el aviso visible).
  //
  // Y TAMBIÉN LAS APARTADAS, que es lo que faltaba: la cola deja de reintentar una
  // marca tras seis fallos y la aparta en vez de borrarla —«una marca que una
  // persona hizo de verdad jamás se destruye»—, pero hasta hoy `obtenerDescartadas`
  // no la llamaba NADIE en todo el repositorio. O sea que se conservaba y no se
  // veía: el contador «sin enviar» las excluye, así que al apartarse la última
  // bajaba a cero y la pantalla decía que estaba todo enviado. Una marca guardada
  // que nadie sabe que existe se pierde igual que una borrada, solo que más tarde.
  useEffect(() => {
    const revisar = () =>
      Promise.all([obtenerPendientes(), obtenerDescartadas()])
        .then(([p, d]) => {
          setPendientesSinEnviar(p.length);
          setMarcasApartadas(d.length);
        })
        .catch(() => {});
    revisar();
    const t = setInterval(revisar, 4000);
    return () => clearInterval(t);
  }, []);

  // Y las sube al servidor, que es lo que las saca de este navegador (0304).
  //
  // Va en su propio intervalo y mucho más lento que el contador de arriba: ese
  // solo mira IndexedDB y puede correr cada cuatro segundos sin costar nada;
  // este habla con el servidor. Cada dos minutos alcanza de sobra para algo que
  // resuelve una persona a mano.
  //
  // También es lo único que hace bajar el aviso rojo: cuando alguien resuelve la
  // marca desde Correcciones, la siguiente pasada la borra de la cola. No hay
  // botón para silenciarlo, a propósito.
  useEffect(() => {
    const sincronizar = () => { void sincronizarApartadas().catch(() => {}); };
    sincronizar();
    const t = setInterval(sincronizar, 120000);
    return () => clearInterval(t);
  }, []);

  // Refresca la lista de personas cuando alguien vuelve a mirar el terminal (foco)
  // y cada 2 min. Así una persona recién agregada en el panel aparece sola, sin que
  // nadie tenga que recargar la página. Offline no hace nada (cargarRoster ya cae a
  // la caché); mid-marcaje es inofensivo (solo actualiza la lista de fondo).
  useEffect(() => {
    const refrescar = () => { if (typeof navigator === "undefined" || navigator.onLine) void cargarTodo(); };
    const onVisibilidad = () => { if (document.visibilityState === "visible") refrescar(); };
    document.addEventListener("visibilitychange", onVisibilidad);
    window.addEventListener("focus", refrescar);
    const iv = window.setInterval(refrescar, 120_000);
    return () => {
      document.removeEventListener("visibilitychange", onVisibilidad);
      window.removeEventListener("focus", refrescar);
      window.clearInterval(iv);
    };
  }, [cargarTodo]);

  function volverALista() {
    confirmandoRef.current = false;
    setPantalla("lista");
    setPersonaActual(null);
    setSalidaConfig(null);
    setAccionPendiente(null);
    void cargarTodo();
  }

  // Tocar un nombre marca. Sin paso intermedio, y es una decisión, no un descuido:
  // el control real es que la Mac mini está a la vista de todo el equipo, y lo que
  // se prioriza es que marcar sea instantáneo (Felipe, jul-2026 y 2026-09-04).
  function seleccionarPersona(persona: RosterEntry) {
    setPersonaActual(persona);
    continuarConPersona(persona);
  }

  // Determina y presenta la siguiente acción de la persona.
  function continuarConPersona(persona: RosterEntry) {
    const marcajesHoy = marcajesHoyRef.current.get(persona.id) ?? [];
    const accion = siguienteAccionPara(marcajesHoy);

    if (accion.modo === "cerrado") {
      // En vez de un callejón sin salida, muestra el historial y ofrece reabrir.
      setHistorialCerrado(historialDelDia(marcajesHoy));
      setPantalla("cerrado");
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
    if (
      tipo === "salida_final" &&
      personaActual &&
      nuncaMarcoRefrigerio(marcajesHoyRef.current.get(personaActual.id) ?? [])
    ) {
      setAccionPendiente({ tipo });
      setPantalla("confirmar_refrigerio");
      return;
    }
    prepararConfirmacion({ tipo });
  }

  function confirmarMotivoOtro(motivo: string) {
    if (!accionPendiente) return;
    prepararConfirmacion({ tipo: accionPendiente.tipo, motivoOtro: motivo });
  }

  function confirmarRefrigerio(trabajoCorrido: boolean) {
    if (!accionPendiente) return;
    prepararConfirmacion({ tipo: accionPendiente.tipo, confirmoSinRefrigerio: trabajoCorrido });
  }

  // Reabre el día (tras salida final) vía la ruta segura del servidor.
  async function reabrirDia(motivo: string) {
    if (!personaActual) return;
    const supabase = createTerminalSupabaseClient();
    // También con tope: getSession sale a la red cuando el token está vencido, y
    // sin él esta pantalla se quedaba colgada antes incluso de intentar el fetch.
    // Si no contesta se sigue sin token: la ruta responderá 401 y la persona verá
    // «No se pudo reabrir», que es un final y no un cuelgue.
    const data = await conTope(
      supabase.auth.getSession().then((r) => r.data),
      { session: null },
    );
    let ok = false;
    try {
      const res = await fetch("/api/reabrir-dia", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${data.session?.access_token ?? ""}`,
        },
        body: JSON.stringify({ personaId: personaActual.id, motivo }),
        // Con tope, como todo lo demás: sin él, esta pantalla se quedaba en
        // «confirmando» para siempre y el guardia de doble envío no se soltaba.
        signal: topeDeRed(),
      });
      ok = res.ok;
    } catch {
      ok = false;
    }
    setMensaje(
      ok
        ? `Listo, ${personaActual.nombres} — tu día está abierto de nuevo.`
        : "No se pudo reabrir. Intenta otra vez o avisa a tu encargada.",
    );
    setPantalla("mensaje");
    setTimeout(volverALista, SEGUNDOS_MENSAJE * 1000);
  }

  function prepararConfirmacion(accion: { tipo: TipoMarca; motivoOtro?: string; confirmoSinRefrigerio?: boolean }) {
    // el client_uuid se fija AL PREPARAR: si por algo se envía dos veces, el
    // servidor lo reconoce como el mismo marcaje (idempotencia) y no duplica.
    setAccionPendiente({ ...accion, clientUuid: crypto.randomUUID() });
    setPantalla("confirmando");
  }

  async function confirmarMarcaje() {
    // Sin persona o sin acción no hay nada que marcar: eso no es un fallo, es
    // que no se pulsó nada.
    if (!personaActual || !accionPendiente) return;

    // LA FICHA DEL TERMINAL SÍ ES UN FALLO, Y HAY QUE DECIRLO.
    //
    // `terminalId` es obligatorio para componer la marca, así que sin la ficha
    // no se puede enviar ni encolar. Antes esto salía por el mismo `return` mudo
    // de la línea de arriba: no mandaba, no encolaba y no decía una palabra, y
    // la pantalla de confirmación se iba sola a los 3 segundos. La persona veía
    // exactamente lo mismo que cuando todo va bien, y su marca no quedaba en
    // ningún sitio.
    //
    // Es la única forma en que este sistema pierde una marca, y contradice lo
    // que sync.ts promete por escrito: «una marca que una persona hizo de verdad
    // jamás se destruye». Callarse es lo peor que se puede hacer acá: quien
    // marcó se va tranquilo y el hueco aparece a fin de mes, cuando ya nadie
    // recuerda ese día.
    if (!terminal) {
      setMensaje(
        `${personaActual.nombres}: este equipo no terminó de configurarse y tu marca NO quedó ` +
          `registrada. Avisa a tu encargada ahora — no te vayas creyendo que marcaste.`,
      );
      setPantalla("mensaje");
      setTimeout(volverALista, SEGUNDOS_MENSAJE * 1000);
      return;
    }

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
      confirmoSinRefrigerio: accionPendiente.confirmoSinRefrigerio,
    };

    // Optimista: refleja el marcaje localmente ya mismo para que el siguiente
    // tap (de esta u otra persona) vea el estado correcto sin esperar red.
    const lista = marcajesHoyRef.current.get(personaActual.id) ?? [];
    lista.push({ tipo: entry.tipo, timestamp: entry.timestampCliente });
    marcajesHoyRef.current.set(personaActual.id, lista);

    // LA MARCA SE GUARDA ANTES DE INTENTAR ENVIARLA, siempre, haya red o no.
    //
    // Antes se encolaba solo dentro del `if (error)`, o sea DESPUÉS de que el
    // envío fallara — y un envío colgado no falla: no vuelve nunca. Con
    // `navigator.onLine` en true y la red muerta, esa marca no llegaba a la cola
    // y no quedaba en ningún sitio, mientras la pantalla decía «Listo». Guardar
    // primero cuesta unos milisegundos de IndexedDB; perder una marca le cuesta
    // el día a una persona.
    let encolada = false;
    try {
      await encolarMarcaje(entry);
      encolada = true;
    } catch {
      // Sin almacén local no hay red de seguridad, pero el envío se intenta
      // igual: que falle IndexedDB no es motivo para no registrar la marca.
    }

    let sincronizadoAhora = false;
    // `llego` distingue «el servidor la rechazó» de «no llegué a preguntarle», y
    // esa diferencia es la que esta pantalla tiraba a la basura leyendo solo
    // `ok`. Las dos acababan en el mismo cartel:
    //
    //     Listo — Entrada de Mateo (se sincronizará cuando vuelva la conexión)
    //
    // Para un corte de red eso es verdad: la marca está en la cola y va a
    // salir. Para un RECHAZO es mentira, y de la peor clase — el servidor ya
    // dijo que no y volverá a decirlo en cada reintento hasta que la cola la
    // descarte a los seis. La persona se va convencida de que marcó, el día se
    // le cierra solo y cobra las horas que le invente el auto-cierre.
    let rechazadaPorElServidor = false;
    if (navigator.onLine) {
      const { ok, error, llego } = await enviarMarcaje(createTerminalSupabaseClient(), entry);
      sincronizadoAhora = ok;
      rechazadaPorElServidor = !ok && llego;
      // Marcarlo YA, no esperar a que sync.ts acumule 6 fallos confirmados
      // (minuto y medio) para enterarse de algo que este intento ya sabe.
      // Sigue en la cola y se sigue reintentando; lo único que cambia de
      // inmediato es que deja de contar como "de hoy" (ver offline-db.ts).
      if (rechazadaPorElServidor && encolada) {
        try {
          await marcarComoRechazadaPorServidor(entry.clientUuid, error ?? "sin detalle");
        } catch {
          // Sin almacén local no hay bandera que poner; el mensaje en pantalla
          // ya avisó del rechazo de todos modos.
        }
      }
    }

    // De la cola sale solo lo que el servidor confirmó.
    if (sincronizadoAhora && encolada) {
      try {
        await eliminarDeOutbox(entry.clientUuid);
      } catch {
        // Se queda en la cola: el reintento la mandará otra vez y
        // fn_registrar_marcaje la reconoce por su client_uuid sin duplicarla.
      }
    }

    // El texto NO empieza por «Listo» cuando no lo está. Es lo único que la
    // persona lee antes de darse la vuelta, y en una pantalla que se limpia a
    // los pocos segundos no hay una segunda oportunidad de decírselo.
    setMensaje(
      rechazadaPorElServidor
        ? `No quedó registrada — el sistema no aceptó esta marca de ${personaActual.nombres}. `
          + "Avisa a tu encargada ANTES de irte: no se va a arreglar sola."
        : `Listo — ${TIPO_MARCA_LABELS[entry.tipo]} de ${personaActual.nombres}${
            sincronizadoAhora ? "" : " (se sincronizará cuando vuelva la conexión)"
          }`,
    );
    setTonoMensaje(rechazadaPorElServidor ? "alerta" : "ok");
    setPantalla("mensaje");
    setTimeout(volverALista, (rechazadaPorElServidor ? SEGUNDOS_MENSAJE_ALERTA : SEGUNDOS_MENSAJE) * 1000);
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
    () =>
      (sedeSeleccionada ? roster.filter((p) => p.sedeCodigo === sedeSeleccionada) : roster)
        // orden alfabético estable: la caché offline (IndexedDB getAll) devuelve
        // por id, no por nombre, así que se reordena acá siempre.
        .slice()
        .sort((a, b) => `${a.nombres} ${a.apellidos}`.localeCompare(`${b.nombres} ${b.apellidos}`, "es")),
    [roster, sedeSeleccionada],
  );

  const sedeActivaNombre =
    sedesDisponibles.find((s) => s.codigo === sedeSeleccionada)?.nombre ?? terminal?.sedeNombre ?? "…";

  return (
    <div className="flex flex-1 flex-col">
      <header className="flex items-center justify-between border-b border-sand px-6 py-4">
        <Marca tono="tinta" isotipo="rojo" />
        <div className="flex items-center gap-3">
          {pendientesSinEnviar > 0 && (
            <span className="rounded-full bg-ambar/15 px-3 py-1 text-xs font-medium text-ambar">
              ⟳ {pendientesSinEnviar} sin enviar
            </span>
          )}
          {/* Las apartadas ya NO se reintentan solas: si nadie las ve, no vuelven.
              Por eso van en rojo y con instrucción, no en ámbar como las de arriba
              —que se van a enviar solas en cuanto haya red— y por eso el texto
              nombra a la encargada: es la única acción que resuelve esto. */}
          {marcasApartadas > 0 && (
            <span className="rounded-full bg-rojo/15 px-3 py-1 text-xs font-medium text-rojo">
              ⚠ {marcasApartadas} sin registrar — avisa a tu encargada
            </span>
          )}
          {/* El reloj corrido va DESPUÉS de los avisos de la cola y antes del
              nombre de la sede: no es urgente como una marca sin registrar
              —nadie tiene que hacer nada ahora mismo— pero sí permanente, y
              quien mira el terminal es quien puede avisar de que hay que
              corregirlo. Nunca bloquea: se sigue marcando igual. */}
          {desfase && Math.abs(desfase.segundos) >= DESFASE_AVISO_SEG && (
            <span
              className={`rounded-full px-3 py-1 text-xs font-medium ${
                Math.abs(desfase.segundos) >= DESFASE_GRAVE_SEG
                  ? "bg-rojo/15 text-rojo"
                  : "bg-ambar/15 text-ambar"
              }`}
              title={
                Math.abs(desfase.segundos) >= DESFASE_GRAVE_SEG
                  ? "Con este desfase una marca puede caer en el día equivocado y pagarse en otra jornada. Avisa para que corrijan la fecha y hora de esta Mac."
                  : "Las tardanzas se miden por minuto, así que este desfase puede inventar o borrar una. Avisa para que corrijan la hora de esta Mac."
              }
            >
              🕐 {textoDesfase(desfase.segundos)} — avisa a tu encargada
            </span>
          )}
          <span className="etiqueta text-taupe">{sedeActivaNombre}</span>
        </div>
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
            <NombreGrid
              roster={rosterFiltrado}
              estado={estadoRoster}
              onSeleccionar={seleccionarPersona}
              onReintentar={() => { setEstadoRoster("cargando"); void arrancar(); }}
            />
          </div>
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

        {pantalla === "cerrado" && personaActual && (
          <PantallaCerrado
            nombre={`${personaActual.nombres} ${personaActual.apellidos}`}
            historial={historialCerrado}
            onVolviAEntrar={() => setPantalla("motivo_reentrada")}
            onCancelar={volverALista}
          />
        )}

        {pantalla === "motivo_reentrada" && personaActual && (
          <MotivoReentrada onElegir={reabrirDia} onCancelar={volverALista} />
        )}

        {pantalla === "motivo_otro" && (
          <FormularioMotivoOtro onConfirmar={confirmarMotivoOtro} onCancelar={volverALista} />
        )}

        {pantalla === "confirmar_refrigerio" && personaActual && (
          <ConfirmarRefrigerio
            nombre={`${personaActual.nombres} ${personaActual.apellidos}`}
            onElegir={confirmarRefrigerio}
            onCancelar={volverALista}
          />
        )}

        {pantalla === "confirmando" && personaActual && accionPendiente && (
          <ConfirmacionToast
            texto={`¿Confirmas ${TIPO_MARCA_LABELS[accionPendiente.tipo]} de ${personaActual.nombres}?`}
            segundosTotal={SEGUNDOS_CONFIRMACION}
            onConfirmar={confirmarMarcaje}
            onCancelar={volverALista}
          />
        )}

        {pantalla === "mensaje" && <PantallaMensaje mensaje={mensaje} tono={tonoMensaje} />}
      </main>
    </div>
  );
}

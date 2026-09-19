"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { parseAreas, esOperativaEn, AREA_DEFAULT, type Area } from "@/lib/areas";
import { Cargando } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { Campo, CampoCasilla, CampoSelect } from "@/components/ui/campo";
import { Fila, Tabla, TablaEncabezado, Th } from "@/components/ui/tabla";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import {
  TZ_LIMA, esRolEncargada, hoyLima, formatoMinutos, puedeVerTodasLasSedes,
} from "@cayla-dynamic/shared";
import { esperadoDelDia, horarioVigente, type HorarioTramo, type TurnoDia } from "@/lib/admin/jornada-esperada";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { useFiltroGuardado } from "@/lib/admin/use-filtro-guardado";
import {
  calcularCoberturaSede, enPausaAhora, faltanTexto, fechaConDia, fechaCorta, llegoTarde, loQueFalta,
  sinMarcarYaLeTocaba, subEstadoSinMarcar, textoEquipoDelDia, textoSinMarcar, trabajandoAhora,
  type CoberturaSede, type FilaPersona, type MetaSede,
} from "@/lib/admin/asistencia-hoy";
import { esFallaDeRed, mensajeDeError } from "@/lib/admin/mensaje-error";

const REFRESCO_MS = 30_000;
// Mismo Sheet de siempre si la variable de entorno todavía no está puesta en
// Vercel — así este cambio no puede romper el enlace en producción el día que
// se despliegue antes de cargar la variable.
const URL_SHEET_ASISTENCIA =
  process.env.NEXT_PUBLIC_SHEET_ASISTENCIA_URL ??
  "https://docs.google.com/spreadsheets/d/19jhc5IN0LpbyG00jEwqt4ZB420Ob_rVcGRAdXR88riA/edit";
// Corte mañana/tarde de la meta de cobertura — mismo valor fijo que Turnos (14:15).
const CORTE_TARDE = 14.25;
// Ventana de «Respuestas a memos». Una sola constante para la consulta y para el
// título de la franja: si la una cambiara sin la otra, el título mentiría.
const DIAS_RESPUESTAS_MEMO = 14;


// Día de la semana (0=domingo … 6=sábado) de un ISO — misma convención que
// metas_cobertura.dia_semana en Turnos.
function diaSemanaDe(iso: string): number {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay();
}

// Hora actual de Lima en decimal (13:30 → 13.5), para saber el tramo vigente.
function horaDecimalLimaAhora(): number {
  const p = new Intl.DateTimeFormat("en-GB", { timeZone: TZ_LIMA, hour: "2-digit", minute: "2-digit", hour12: false }).formatToParts(new Date());
  const h = Number(p.find((x) => x.type === "hour")?.value ?? 0) % 24;
  const m = Number(p.find((x) => x.type === "minute")?.value ?? 0);
  return h + m / 60;
}

function horaLima(ts: string | null): string {
  if (!ts) return "—";
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA,
    hour: "2-digit",
    minute: "2-digit",
    hour12: true,
  }).format(new Date(ts));
}


// Estados: verde/ámbar cálidos para lo operativo (van por <Insignia>), Rojo
// lleno para la alerta crítica. "auto_cerrada_pendiente" se queda con su
// propio relleno sólido: es la única variante que necesita el rojo lleno
// (Insignia no tiene una "alerta crítica", solo la translúcida) para pesar
// más que las demás en la fila.
const ESTILO_ESTADO: Record<
  string,
  { label: string; variante?: "positivo" | "advertencia"; atenuada?: boolean; clase?: string }
> = {
  // «Trabajando» y no «Presente»: es exactamente lo que cuenta el resumen de
  // arriba («Trabajando ahora»). Con dos palabras para el mismo estado, la fila
  // decía «Presente» donde el número decía «trabajando», y quien está en pausa
  // —también presente en la sede, en cierto sentido— quedaba en el medio.
  abierta: { label: "Trabajando", variante: "positivo" },
  en_pausa: { label: "En pausa", variante: "advertencia" },
  cerrada: { label: "Salió", atenuada: true },
  auto_cerrada_pendiente: { label: "Auto-cerrada ⚠", clase: "bg-rojo text-crema" },
  revisada: { label: "Salió (revisada)", atenuada: true },
};

// "08:00" → "8:00 a. m.", para el mensaje de la alerta.
function horaAmPmDe(hhmm: string): string {
  const [h, m] = hhmm.slice(0, 5).split(":").map(Number);
  return new Intl.DateTimeFormat("es-PE", { hour: "numeric", minute: "2-digit", hour12: true, timeZone: "UTC" }).format(
    new Date(Date.UTC(2000, 0, 1, h, m)),
  );
}


// La misma celda de estado, compartida entre la tabla de escritorio y las
// tarjetas de celular — para no mantener dos copias del mismo if/else.
function EstadoCelda({ f, linkCorregir, ahoraDecimal }: { f: FilaPersona; linkCorregir: (personaId: string) => string; ahoraDecimal: number }) {
  // "Sin marcar" es ambiguo a propósito en casos límite: puede ser un no-show
  // real o alguien de vacaciones. Sin esto los dos se veían idénticos en la
  // única pantalla que se mira de un vistazo — mismo riesgo de falso positivo
  // que la 0101 ya cerró para el semáforo disciplinario.
  const ausencia = f.estado === "sin_marcar" ? f.ausenciaHoy : null;
  if (ausencia) {
    return (
      <span title={ausencia.pendiente ? "Registrada, todavía sin aprobar" : "Ausencia aprobada que cubre hoy"}>
        <Insignia variante={ausencia.pendiente ? "advertencia" : "neutral"} atenuada={!ausencia.pendiente}>
          {ausencia.nombre}{ausencia.pendiente ? " · por confirmar" : ""}
        </Insignia>
      </span>
    );
  }
  if (f.estado === "sin_marcar") {
    const sub = subEstadoSinMarcar(f, ahoraDecimal);
    if (sub === "aun_no_inicia") {
      return <Insignia variante="informativo">Aún no inicia · entra {horaAmPmDe(f.entradaEsperadaHoy!)}</Insignia>;
    }
    if (sub === "descansa") {
      return <Insignia variante="neutral" atenuada>Descansa hoy</Insignia>;
    }
    if (sub === "falta_real") {
      return (
        <Link href={linkCorregir(f.personaId)} className="transition-opacity hover:opacity-80">
          <Insignia variante="alerta">Sin marcar · le tocaba {horaAmPmDe(f.entradaEsperadaHoy!)}</Insignia>
        </Link>
      );
    }
    // "desconocido": no hay horario contra qué medir. Mismo texto sin pastilla
    // de siempre — es honesto sobre lo que no se sabe, no inventa una
    // tranquilidad que no se puede probar. Taupe entero, no al 50%: así daba
    // 2.1:1 y no se leía, y "no sabemos" también es información.
    return <span className="text-xs text-taupe">Sin marcar</span>;
  }
  const estilo = ESTILO_ESTADO[f.estado] ?? ESTILO_ESTADO.cerrada;
  if (f.estado === "auto_cerrada_pendiente") {
    return (
      <Link href={linkCorregir(f.personaId)} className={`rounded-full px-2 py-0.5 text-xs ${estilo.clase} transition-opacity hover:opacity-80`}>
        {estilo.label} ›
      </Link>
    );
  }
  if (estilo.clase) return <span className={`rounded-full px-2 py-0.5 text-xs ${estilo.clase}`}>{estilo.label}</span>;
  return <Insignia variante={estilo.variante} atenuada={estilo.atenuada}>{estilo.label}</Insignia>;
}

// La tabla de personas de una sede: filas en escritorio, tarjetas en celular.
// Un solo componente para que cualquier lista de personas de esta pantalla se
// vea y se corrija igual — cada fila con tardanza o auto-cierre enlaza a
// Correcciones de esa persona ese día. `conSede` agrega la columna cuando la
// lista mezcla sedes (el detalle de un número del resumen).
function TablaPersonas({ filas, linkCorregir, ahoraDecimal, conSede = false }: { filas: FilaPersona[]; linkCorregir: (personaId: string) => string; ahoraDecimal: number; conSede?: boolean }) {
  return (
    <>
      {/* Escritorio: tabla completa. En celular una tabla de 5 columnas no
          cabe sin scroll horizontal incómodo, así que de sm hacia abajo se
          arma la versión en tarjetas de más abajo — mismos datos. */}
      <div className="hidden sm:block">
        <Tabla>
          <TablaEncabezado>
            <Th>Nombre</Th>
            {conSede && <Th>Sede</Th>}
            <Th>Estado</Th>
            <Th>Entrada</Th>
            <Th>Tardanza</Th>
            <Th>Salida final</Th>
          </TablaEncabezado>
          <tbody>
            {filas.map((f) => (
              <Fila key={f.personaId}>
                <td className="px-4 py-2.5">{f.nombre}</td>
                {conSede && <td className="px-4 py-2.5 text-taupe">{f.sede}</td>}
                <td className="px-4 py-2.5">
                  <EstadoCelda f={f} linkCorregir={linkCorregir} ahoraDecimal={ahoraDecimal} />
                </td>
                {/* nowrap en horas y tardanza: con la columna Sede, "08:00 a. m." se
                    partía en dos líneas por debajo de ~900 px. */}
                <td className="whitespace-nowrap px-4 py-2.5">{horaLima(f.entrada)}</td>
                <td className="whitespace-nowrap px-4 py-2.5">
                  {f.minutosTarde === null || f.minutosTarde === 0 ? (
                    <span className="text-taupe/40">—</span>
                  ) : (
                    <Link href={linkCorregir(f.personaId)} className="font-semibold text-rojo-profundo underline decoration-rojo/30 underline-offset-2 transition-colors hover:decoration-rojo">
                      {formatoMinutos(f.minutosTarde)} tarde
                    </Link>
                  )}
                </td>
                <td className="whitespace-nowrap px-4 py-2.5">
                  {horaLima(f.salidaFinal)}
                  {f.salidaTemprana ? (
                    <Link href={linkCorregir(f.personaId)} className="ml-2 transition-opacity hover:opacity-80">
                      <Insignia variante="advertencia" tamano="sm">{formatoMinutos(f.salidaTemprana)} antes</Insignia>
                    </Link>
                  ) : null}
                </td>
              </Fila>
            ))}
          </tbody>
        </Tabla>
      </div>

      {/* Celular: la misma información en tarjetas apiladas, una por persona. */}
      <div className="flex flex-col gap-2 sm:hidden">
        {filas.map((f) => (
          <div key={f.personaId} className="rounded-superficie border border-sand bg-hueso p-4">
            <div className="mb-2 flex items-center justify-between gap-2">
              <span className="font-medium">
                {f.nombre}
                {conSede && <span className="font-normal text-taupe"> · {f.sede}</span>}
              </span>
              <span className="shrink-0">
                <EstadoCelda f={f} linkCorregir={linkCorregir} ahoraDecimal={ahoraDecimal} />
              </span>
            </div>
            <div className="grid grid-cols-3 gap-x-2 gap-y-1 border-t border-sand pt-2 text-xs">
              <span className="text-taupe">Entrada</span>
              <span className="text-taupe">Tardanza</span>
              <span className="text-taupe">Salida final</span>
              <span>{horaLima(f.entrada)}</span>
              <span>
                {f.minutosTarde === null || f.minutosTarde === 0 ? (
                  <span className="text-taupe/40">—</span>
                ) : (
                  <Link href={linkCorregir(f.personaId)} className="font-semibold text-rojo-profundo underline decoration-rojo/30 underline-offset-2">
                    {formatoMinutos(f.minutosTarde)}
                  </Link>
                )}
              </span>
              <span>
                {horaLima(f.salidaFinal)}
                {f.salidaTemprana ? (
                  <Link href={linkCorregir(f.personaId)} className="ml-1 inline-block">
                    <Insignia variante="advertencia" tamano="sm">{formatoMinutos(f.salidaTemprana)} antes</Insignia>
                  </Link>
                ) : null}
              </span>
            </div>
          </div>
        ))}
      </div>
    </>
  );
}

// `umbral` nombra el escalón alcanzado desde la 0200 — amonestacion ·
// suspension · imputacion · bloqueado · aviso —, no solo «amonestacion o aviso».
interface TardRow { persona_id: string; nombre: string; sede: string; tardanzas_mes: number; umbral: string; ultima_fecha: string | null; minimo: number | null }
interface FaltaRow { persona_id: string; nombre: string; sede: string; nivel: string }
/** Fila de `fn_memos_recientes_respuesta_sancionado()` (0404). */
interface RespuestaMemoRow {
  id: string; persona: string; correlativo: string | null; tipo_causal: string; nivel: string;
  firmado_at: string | null; rechazado_at: string | null;
}
// Contratos a plazo fijo con fecha de término anotada (0144). `dias_restantes` es
// negativo cuando la fecha ya pasó, y ese es el grupo que duele.
interface ContratoRow { persona_id: string; nombre: string; sede: string; fecha_fin_contrato: string; dias_restantes: number; ya_vencio: boolean }


// Los cuatro números del resumen. Cada uno abre su detalle debajo al hacer clic.
type ClaveResumen = "trabajando" | "tardanzas" | "sin_marcar" | "bajo_minimo";


// Franja de estado en el borde izquierdo de una tarjeta. Es lo que permite
// leer la pantalla bajando la vista sin leer ni un número: rojo = hay que
// actuar, verde = cubierto. Sin sombra ni degradado (regla de la paleta): la
// tarjeta se distingue por tono, no por relieve. Nunca va sola — el mismo
// estado está siempre dicho en texto al lado, para quien no distingue el color.
// "neutral" no pinta nada: sin estado no hay qué señalar, y una franja color
// arena se veía como un borde mal dibujado. La tarjeta conserva su relleno
// izquierdo igual, para que los textos de todas queden alineados.
type TonoFranja = "alerta" | "advertencia" | "positivo" | "neutral";
const COLOR_FRANJA: Record<TonoFranja, string | null> = {
  alerta: "bg-rojo",
  advertencia: "bg-ambar",
  positivo: "bg-verde",
  neutral: null,
};
function Franja({ tono }: { tono: TonoFranja }) {
  const color = COLOR_FRANJA[tono];
  return color && <span aria-hidden className={`absolute inset-y-0 left-0 w-1 ${color}`} />;
}

// Un tile de cobertura (Operativas / Encargadas), protagonista a propósito:
// es la pregunta que de verdad decide si hay que actuar, no un dato al pie.
//
// Se rellena con el color de su estado en vez de ser papel sobre papel: antes
// la tarjeta de la sede y sus dos tiles eran el mismo tono, y lo único que
// decía "falta gente" era el color de un número en trazo fino.
//
// Dos rojos a propósito. El número es texto grande (36px), y ahí WCAG pide
// 3:1: el rojo da 4.49:1 claro y 3.78:1 oscuro sobre este relleno, y se lee
// ROJO. El "Faltan 2" es texto chico, pide 4.5:1, y el rojo en modo oscuro no
// llega — va en rojo-profundo (7.03 / 5.25:1). Se probó el número también en
// rojo-profundo y sobre el relleno cálido se leía café, no alerta.
// El verde va al 8% y no al 10%: al 10% la etiqueta taupe baja a 4.44:1 en
// modo oscuro.
function TileCobertura({ label, n, meta, sinMeta, tramo }: { label: string; n: number; meta: number; sinMeta: boolean; tramo?: string }) {
  const ok = !sinMeta && n >= meta;
  const tono = sinMeta
    ? { caja: "border-sand bg-crema", numero: "text-taupe", texto: "text-taupe" }
    : ok
      ? { caja: "border-verde/30 bg-verde/[0.08]", numero: "text-verde", texto: "text-verde" }
      : { caja: "border-rojo/30 bg-rojo/10", numero: "text-rojo", texto: "text-rojo-profundo" };
  return (
    <div className={`rounded-superficie border px-4 py-3 ${tono.caja}`}>
      <div className="flex items-baseline gap-1.5">
        <span className={`font-serif text-4xl font-medium leading-none tabular-nums ${tono.numero}`}>{n}</span>
        {!sinMeta && <span className="text-lg text-taupe">/ {meta}</span>}
      </div>
      <div className="mt-1.5 text-xs text-taupe">
        {label}{sinMeta ? " · sin meta" : tramo ? ` · meta ${tramo}` : ""}
      </div>
      {!sinMeta && (
        <div className={`mt-1 text-sm font-semibold ${tono.texto}`}>{ok ? "Completo" : faltanTexto(meta - n)}</div>
      )}
    </div>
  );
}

export default function DashboardPage() {
  const router = useRouter();
  const yo = usePersonaActual();
  const esAdmin = puedeVerTodasLasSedes(yo?.rol ?? null);
  const [filas, setFilas] = useState<FilaPersona[]>([]);
  // Fuente de verdad de qué sedes existen: la tabla `sedes`, igual que las
  // demás 14 pantallas del panel — nunca derivada de quién pasó el filtro de
  // personas de abajo. Antes se armaba agrupando `filas` por sede_id, así que
  // una sede sin nadie que cumpliera activo+en_planilla+no_sueldo_fijo
  // desaparecía entera, sin aviso, en vez de mostrarse con "0 de 0".
  const [sedesActivas, setSedesActivas] = useState<{ id: string; codigo: string }[]>([]);
  const [metasPorSede, setMetasPorSede] = useState<Map<string, MetaSede>>(new Map());
  const [actualizado, setActualizado] = useState<string>("");
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [discTard, setDiscTard] = useState<TardRow[]>([]);
  const [discFaltas, setDiscFaltas] = useState<FaltaRow[]>([]);
  const [contratos, setContratos] = useState<ContratoRow[]>([]);
  // El semáforo de "Contratos a plazo fijo" no contestó. Igual que
  // `discNoRespondio` de Disciplina: el artículo 77 convierte un contrato en
  // indefinido con solo que la persona siga trabajando después de la fecha, y
  // ese plazo corre igual aunque esta franja no haya podido mirar.
  const [contratosNoRespondio, setContratosNoRespondio] = useState(false);
  // `turnos`/`horarios_asignados` no contestaron: no se pudo calcular a quién
  // le tocaba entrar hoy, así que la alerta roja de "sede sin marcar" —la
  // única de esta pantalla fuera de Disciplina— no puede dispararse aunque
  // corresponda. Sin esta bandera esa alerta se apaga en silencio.
  const [horarioEsperadoNoRespondio, setHorarioEsperadoNoRespondio] = useState(false);
  // `ausencias` no contestó: alguien de vacaciones puede verse idéntico a un
  // "sin marcar" real mientras esto no se pueda comprobar (mismo riesgo de
  // falso positivo que ya resuelve `ausenciaHoy` cuando la consulta sí responde).
  const [ausenciasNoRespondieron, setAusenciasNoRespondieron] = useState(false);
  const [sinCargo, setSinCargo] = useState(0);
  // El par de consultas de abajo no respondió. Sin esta distinción, si
  // `expediente_adjuntos` falla, `conPapel` queda vacío y TODOS los memos
  // entregados pasarían el filtro de "sin cargo" — se acusaría a quien sí
  // tiene su papel archivado. Mismo riesgo que `discNoRespondio` ya cierra
  // abajo, para esta franja en particular.
  const [sinCargoNoRespondio, setSinCargoNoRespondio] = useState(false);
  /**
   * El semáforo no contestó. NO es lo mismo que «no hay nadie en escalón».
   *
   * Sin esta distinción la franja se borraba entera cuando la RPC fallaba, y la
   * portada quedaba idéntica a un mes tranquilo. Ya pasó: un `drop function` se
   * llevó por delante su GRANT (0204) y la consulta estuvo caída. Los plazos del
   * art. 25 corren igual mientras la pantalla calla, y esta franja es el único
   * sitio donde el aviso no está dentro de un panel plegado.
   */
  const [discNoRespondio, setDiscNoRespondio] = useState(false);
  const [respuestasMemo, setRespuestasMemo] = useState<RespuestaMemoRow[]>([]);

  // Filtros de la pantalla. La búsqueda es de esta visita (nunca se guarda,
  // por la propia regla de useFiltroGuardado); sede/estado/solo-alertas son
  // preferencias de vista y sí se recuerdan entre sesiones, por navegador.
  const [busqueda, setBusqueda] = useState("");
  const [sedeFiltro, setSedeFiltro] = useFiltroGuardado<string>("dashboard.sede", "todas");
  const [estadoFiltro, setEstadoFiltro] = useFiltroGuardado<string>("dashboard.estado", "todos");
  const [soloAlertas, setSoloAlertas] = useFiltroGuardado<boolean>("dashboard.solo_alertas", false);
  // Qué sedes tienen su tabla de personas abierta manualmente (más allá de lo
  // que fuercen los filtros). Por sede, no global: cada una se expande aparte.
  const [detalleAbierto, setDetalleAbierto] = useState<Record<string, boolean>>({});
  // Qué número del resumen tiene su detalle abierto. No se guarda entre visitas
  // a propósito: abrir mañana la pantalla y encontrarla mostrando solo las
  // tardanzas de ayer haría creer que no hay nada más.
  const [resumenAbierto, setResumenAbierto] = useState<ClaveResumen | null>(null);

  // Semáforo disciplinario para la franja (aparte del refresco de asistencia).
  useEffect(() => {
    const sb = createAdminSupabaseClient();
    void (async () => {
      const [{ data: t, error: errT }, { data: f, error: errF }] = await Promise.all([
        sb.rpc("fn_tardanzas_resumen", {}),
        sb.rpc("fn_faltas_resumen", {}),
      ]);
      setDiscNoRespondio(Boolean(errT || errF));
      setDiscTard(Array.isArray(t) ? (t as TardRow[]) : []);
      setDiscFaltas(Array.isArray(f) ? (f as FaltaRow[]) : []);

      // Memos entregados a los que aún les falta el papel firmado.
      //
      // Un memo entregado sin su cargo archivado no se puede probar. Ante una
      // inspección o un reclamo, el expediente que este sistema arma para
      // sostener una decisión se cae justo por ahí: consta que se entregó
      // porque alguien lo marcó, no porque haya una firma de recepción.
      //
      // Vive en el Dashboard y no solo en Disciplina porque el aviso allá
      // estaba dentro de un panel plegado: había que ir a buscarlo sabiendo
      // que existía. Si cualquiera de las dos consultas falla, NO se calcula
      // un número: "0 sin cargo" con `expediente_disciplinario` caída sería
      // ocultar el aviso, y "todos sin cargo" con `expediente_adjuntos`
      // caída sería acusar a quien sí tiene su papel — los dos son peores
      // que decir, sin más, que no se pudo mirar.
      const [
        { data: entregados, error: errEntregados },
        { data: papeles, error: errPapeles },
      ] = await Promise.all([
        sb.from("expediente_disciplinario").select("id").eq("estado", "entregado"),
        sb.from("expediente_adjuntos").select("documento_id"),
      ]);
      if (errEntregados || errPapeles) {
        setSinCargoNoRespondio(true);
        setSinCargo(0);
      } else {
        setSinCargoNoRespondio(false);
        const conPapel = new Set(((papeles as Array<{ documento_id: string }>) ?? []).map((a) => a.documento_id));
        setSinCargo(((entregados as Array<{ id: string }>) ?? []).filter((d) => !conPapel.has(d.id)).length);
      }

      // Quién firmó (o prefirió no firmar) su memo en los últimos 14 días
      // (0404). Falla en silencio a propósito, igual que "Contratos a plazo
      // fijo" más abajo: es informativo, no un aviso de plazo legal corriendo
      // como el resto de esta franja — si la RPC no responde, la tarjeta
      // simplemente no aparece.
      const { data: resp } = await sb.rpc("fn_memos_recientes_respuesta_sancionado", { p_dias: DIAS_RESPUESTAS_MEMO });
      setRespuestasMemo(Array.isArray(resp) ? (resp as RespuestaMemoRow[]) : []);
    })();
  }, []);

  // Contratos a plazo fijo: los que vencen dentro de 30 días y —lo que de verdad
  // importa— los que YA vencieron sin que nadie registrara la salida. La fecha se
  // anota en Equipo; sin este aviso, anotarla solo sirve si alguien se acuerda de
  // ir a mirarla, y el día del vencimiento no lo recuerda nadie.
  //
  // Aparte del refresco de asistencia porque no cambia cada 30 segundos. La RPC
  // ya devuelve vacío (sin error) para quien no es admin ni líder, así que ese
  // caso sigue sin mostrar nada, como corresponde. Pero si la consulta FALLA de
  // verdad (red, RPC caída), esta franja ya no lo calla: el artículo 77
  // convierte un contrato en indefinido con solo que la persona siga
  // trabajando después de la fecha, y ese plazo corre igual aunque la pantalla
  // no haya podido mirar — mismo criterio que `discNoRespondio` en Disciplina.
  useEffect(() => {
    const sb = createAdminSupabaseClient();
    void (async () => {
      // NOVENTA días, no treinta. Veintiún contratos a plazo fijo y **veinte
      // vencen el mismo 31 de diciembre**: con la ventana de 30 el aviso
      // aparecía el 1 de diciembre, dejando un mes —en plena campaña de fin de
      // año— para decidir, redactar y firmar veinte renovaciones.
      //
      // Y el que se pasa no se pasa a medias: el artículo 77 del D.S. 003-97-TR
      // convierte el contrato en indefinido SOLO, sin que nadie lo decida, por
      // el hecho de que la persona siga trabajando después de la fecha.
      const { data, error } = await sb.rpc("fn_contratos_por_vencer", { p_dias: 90 });
      setContratosNoRespondio(Boolean(error));
      setContratos(Array.isArray(data) ? (data as ContratoRow[]) : []);
    })();
  }, []);

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) {
      router.replace("/admin/login");
      return;
    }

    const hoy = hoyLima();
    const diaHoy = diaSemanaDe(hoy);
    // minutos_salida_temprana va por RPC (fn_jornadas_extra) porque el schema cache
    // de PostgREST no expone la columna; el select directo fallaría entero.
    const [
      { data: sedesData, error: errSedes },
      { data: personas, error: errPersonas },
      { data: jornadas, error: errJornadas },
      { data: extras }, // fn_jornadas_extra ya está diseñada para fallar en silencio (ver comentario abajo)
      { data: funciones }, // función + es_encargada_piso (RPC: el schema cache no expone la columna)
      { data: areasRaw, error: errAreas }, // catálogo de áreas (para saber cuáles son operativas)
      { data: metasRaw }, // metas de cobertura de hoy por sede (falla suave: sin meta = neutro)
      // Ausencias SÍ lleva su error: si falla, alguien de vacaciones se vería
      // idéntico a un "sin marcar" real, y eso merece un aviso discreto (ver abajo).
      { data: ausenciasHoy, error: errAusencias },
      { data: tiposAusencia }, // catálogo (nombre + si exige aprobación), para no repetirlo a mano acá
      // Turnos y horarios SÍ llevan su error: de los dos sale `entradaEsperadaHoy`,
      // que alimenta la única alerta roja de esta pantalla fuera de Disciplina
      // ("sede sin marcar"). Si cualquiera de las dos falla, esa alerta no puede
      // dispararse aunque corresponda — y sin la bandera, se apagaría sin aviso.
      { data: turnosHoy, error: errTurnos },
      { data: horariosVigentes, error: errHorarios },
    ] = await Promise.all([
      // Misma consulta que /admin/reporte-sede: la lista de sedes a mostrar
      // nunca se deriva de quién aparece en otra tabla.
      supabase.from("sedes").select("id, codigo").eq("activa", true).order("codigo"),
      supabase
        .from("personas")
        .select("id, nombres, apellidos, rol, sede_base_id, sedes:sede_base_id(codigo)")
        .eq("estado", "activo")
        // `tipo_vinculo = 'practicante'`, no simplemente `not en_planilla`:
        // así un RxH no entra por accidente. Mismo criterio puntual que la
        // 0333 usó para que un practicante dejara de ser invisible en
        // Contratos — acá no toca el escalafón disciplinario
        // (fn_tardanzas_resumen/fn_faltas siguen excluyendo a los
        // practicantes en todo el sistema): esta pantalla solo muestra quién
        // marcó hoy, no genera ninguna sanción.
        .or("en_planilla.eq.true,tipo_vinculo.eq.practicante")
        .eq("sueldo_fijo", false) // quien cobra fijo no marca: no se le mide asistencia
        .order("nombres"),
      supabase
        .from("jornadas")
        .select("persona_id, estado, entrada_ts, salida_final_ts, minutos_tarde, tiene_salida_no_retornada")
        .eq("fecha", hoy),
      supabase.rpc("fn_jornadas_extra", { p_desde: hoy, p_hasta: hoy }),
      supabase.rpc("fn_personas_funciones"),
      supabase.rpc("fn_areas"),
      supabase.from("metas_cobertura").select("sede_id, meta, meta_tarde, meta_encargadas").eq("dia_semana", diaHoy),
      // anulada_at is null: una ausencia anulada no cubre nada. El rango incluye
      // hoy con <= / >=, igual que el `between` que ya usa fn_faltas_resumen.
      supabase.from("ausencias").select("persona_id, tipo, aprobada_at").is("anulada_at", null).lte("fecha_inicio", hoy).gte("fecha_fin", hoy),
      supabase.from("tipos_ausencia").select("codigo, nombre, requiere_aprobacion"),
      supabase.from("turnos").select("persona_id, fecha, hora_entrada, hora_salida, es_descanso").eq("fecha", hoy),
      supabase
        .from("horarios_asignados")
        .select("persona_id, hora_entrada, hora_salida, dias_laborables, horario_por_dia, almuerzo_min_minutos, vigente_desde, vigente_hasta")
        .lte("vigente_desde", hoy)
        .or(`vigente_hasta.is.null,vigente_hasta.gte.${hoy}`),
    ]);

    if (errSedes || errPersonas || errJornadas) {
      // Con la traducción de la casa, no el `.message` crudo: quien mira este
      // banner administra personas, no lee «TypeError: Failed to fetch». Y el
      // corte de red se dice aparte —como en el login—, porque la respuesta
      // correcta es otra: no es un dato mal puesto, es que no hay conexión.
      const fallo = errSedes ?? errPersonas ?? errJornadas;
      setError(
        esFallaDeRed(fallo)
          ? "No se pudo cargar la asistencia de hoy: no hay conexión con el sistema. Intenta de nuevo en un momento."
          : mensajeDeError(fallo, "cargar la asistencia de hoy"),
      );
      setCargando(false);
      return; // no pisa `filas`/`sedesActivas` con datos parciales/vacíos
    }
    setError(null);
    setSedesActivas(sedesData ?? []);
    setAusenciasNoRespondieron(Boolean(errAusencias));
    setHorarioEsperadoNoRespondio(Boolean(errTurnos || errHorarios));

    // Función/área/encargada: si la RPC falla, degradamos a "todos operativos"
    // (misma política que Turnos) — la cobertura puede marcar de más pero la
    // página no se cae. Las metas fallan aún más suave: sin meta = neutro.
    const areasList: Area[] = parseAreas(areasRaw, errAreas);
    const funcionPorPersona = new Map(
      ((funciones as { persona_id: string; funcion: string; es_encargada_piso?: boolean }[] | null) ?? [])
        .map((x) => [x.persona_id, { funcion: x.funcion, enc: Boolean(x.es_encargada_piso) }]),
    );
    setMetasPorSede(new Map(
      ((metasRaw as { sede_id: string; meta: number; meta_tarde: number | null; meta_encargadas: number | null }[] | null) ?? [])
        .map((m) => [m.sede_id, { man: m.meta ?? 0, tar: m.meta_tarde ?? m.meta ?? 0, enc: m.meta_encargadas ?? 0 }]),
    ));

    const jornadaPorPersona = new Map((jornadas ?? []).map((j: any) => [j.persona_id, j]));
    // Solo llegan filas con minutos > 0 y la fecha es fija (hoy), así que basta persona_id → minutos.
    // Si la RPC falla, extras es null y el map queda vacío (sin badge, la página no se rompe).
    const salidaTempranaPorPersona = new Map(
      ((extras as { persona_id: string; fecha: string; minutos_salida_temprana: number }[] | null) ?? []).map(
        (e) => [e.persona_id, e.minutos_salida_temprana],
      ),
    );
    // Nombre + si exige aprobación, por código de tipo ("vacaciones" → "Vacaciones", true/false).
    const nombrePorTipoAusencia = new Map(
      ((tiposAusencia as { codigo: string; nombre: string; requiere_aprobacion: boolean }[] | null) ?? []).map(
        (t) => [t.codigo, { nombre: t.nombre, requiereAprobacion: t.requiere_aprobacion }],
      ),
    );
    // La restricción `ausencias_sin_solape` ya impide que a una persona le
    // cubran dos ausencias el mismo día, así que basta con la última que
    // llegue — no hay que decidir cuál gana.
    const ausenciaPorPersona = new Map(
      ((ausenciasHoy as { persona_id: string; tipo: string; aprobada_at: string | null }[] | null) ?? []).map((a) => {
        const t = nombrePorTipoAusencia.get(a.tipo);
        return [a.persona_id, { nombre: t?.nombre ?? a.tipo, pendiente: Boolean(t?.requiereAprobacion) && !a.aprobada_at }];
      }),
    );

    // Misma cascada de jornada-esperada.ts que Correcciones, Incidencias y Turnos: el
    // turno puntual de hoy manda, y si no hay se cae al horario base vigente.
    const turnoPorPersona = new Map(
      ((turnosHoy as { persona_id: string; fecha: string; hora_entrada: string | null; hora_salida: string | null; es_descanso: boolean }[] | null) ?? [])
        .map((t) => [t.persona_id, t as TurnoDia]),
    );
    const horariosPorPersona = new Map<string, HorarioTramo[]>();
    for (const h of (horariosVigentes as HorarioTramo[] | null) ?? []) {
      const arr = horariosPorPersona.get(h.persona_id) ?? [];
      arr.push(h);
      horariosPorPersona.set(h.persona_id, arr);
    }

    const resultado: FilaPersona[] = (personas ?? []).map((p: any) => {
      const j = jornadaPorPersona.get(p.id);
      const f = funcionPorPersona.get(p.id);
      const turno = turnoPorPersona.get(p.id) ?? null;
      const horario = horarioVigente(horariosPorPersona.get(p.id) ?? [], hoy);
      const esperado = esperadoDelDia(hoy, turno, horario);
      return {
        personaId: p.id,
        nombre: `${p.nombres} ${p.apellidos}`,
        sede: p.sedes?.codigo ?? "?",
        sedeId: p.sede_base_id,
        estado: j?.estado ?? "sin_marcar",
        entrada: j?.entrada_ts ?? null,
        entradaEsperadaHoy: esperado.trabaja ? esperado.entrada : null,
        origenEsperadoHoy: esperado.origen,
        salidaFinal: j?.salida_final_ts ?? null,
        minutosTarde: j?.minutos_tarde ?? null,
        salidaTemprana: salidaTempranaPorPersona.get(p.id) ?? null,
        enPausaSinRetorno: j?.tiene_salida_no_retornada ?? false,
        esOperativa: esOperativaEn(areasList, f?.funcion ?? AREA_DEFAULT),
        esEncargada: esRolEncargada(p.rol) || Boolean(f?.enc),
        ausenciaHoy: ausenciaPorPersona.get(p.id) ?? null,
      };
    });

    setFilas(resultado);
    setActualizado(new Intl.DateTimeFormat("es-PE", { timeZone: TZ_LIMA, hour: "2-digit", minute: "2-digit", second: "2-digit" }).format(new Date()));
    setCargando(false);
  }, [router]);

  useEffect(() => {
    void cargar();
    const t = setInterval(() => void cargar(), REFRESCO_MS);
    // Refrescar también al volver a la pestaña (los navegadores pausan el interval en
    // segundo plano; así un cambio reciente —ej. una persona nueva— aparece al regresar).
    const alVolver = () => { if (document.visibilityState === "visible") void cargar(); };
    document.addEventListener("visibilitychange", alVolver);
    window.addEventListener("focus", alVolver);
    return () => {
      clearInterval(t);
      document.removeEventListener("visibilitychange", alVolver);
      window.removeEventListener("focus", alVolver);
    };
  }, [cargar]);

  const ahoraDecimal = horaDecimalLimaAhora();
  const tramoTarde = ahoraDecimal >= CORTE_TARDE;
  // «de la mañana», no «mañana»: «meta mañana» se lee como la meta de MAÑANA (el
  // día siguiente). Y a la 1:48 p. m. sigue siendo la meta de la mañana: el corte
  // es a las 14:15, igual que en Turnos.
  const tramoLabel = tramoTarde ? "de la tarde" : "de la mañana";
  const hoy = hoyLima();
  // Un incidente (tardanza, auto-cierre) enlaza directo a Corregir de esa persona/fecha.
  const linkCorregir = (personaId: string) => `/admin/correcciones?persona=${personaId}&fecha=${hoy}`;

  // Alcance por permiso: qué sedes puede ver quien mira la pantalla ahora.
  // `sedes` (la tabla) es visible para cualquier autenticado — es un catálogo
  // de 4 filas que otras ~14 pantallas necesitan completo para todos los
  // roles — pero RLS ya restringe personas/jornadas/turnos/horarios a la
  // sede propia de una encargada (`supervisor_sede`). Sin este filtro, ella
  // vería las otras tres sedes en "0 trabajando de 0": no una fuga de datos
  // (RLS igual le oculta a las personas), pero sí una afirmación falsa —
  // "no hay nadie" en vez de "no tienes permiso para verlo". Se filtra recién
  // cuando `yo` ya cargó, para no mostrarle una pantalla vacía a un admin por
  // un instante.
  const sedesDeAlcance = sedesActivas
    .map((s) => ({ sedeId: s.id, codigo: s.codigo }))
    .filter((s) => !yo || esAdmin || s.sedeId === yo.sedeBaseId);

  // Cobertura de cada sede, calculada una sola vez y reutilizada para ordenar,
  // para el resumen global y para cada tarjeta.
  const coberturaPorSede = new Map<string, CoberturaSede>();
  for (const s of sedesDeAlcance) {
    const deSede = filas.filter((f) => f.sedeId === s.sedeId);
    const meta = metasPorSede.get(s.sedeId) ?? { man: 0, tar: 0, enc: 0 };
    coberturaPorSede.set(s.sedeId, calcularCoberturaSede(deSede, meta, tramoTarde, ahoraDecimal));
  }

  // Orden: primero la sede con cobertura insuficiente (decisión de la
  // auditoría de sep-2026 — antes solo importaba quién tenía más gente
  // trabajando). Empate se resuelve igual que antes: más gente trabajando
  // ahora, y si sigue empatado, alfabético.
  const sedes = [...sedesDeAlcance].sort((a, b) => {
    const ca = coberturaPorSede.get(a.sedeId)!;
    const cb = coberturaPorSede.get(b.sedeId)!;
    if (ca.problema !== cb.problema) return ca.problema ? -1 : 1;
    return cb.trabajando.length - ca.trabajando.length || a.codigo.localeCompare(b.codigo);
  });

  // ---------- Resumen global ----------
  // El número de cada tarjeta ES el largo de la lista que abre al hacer clic —
  // no una cuenta aparte—, así "10 tardanzas" y las filas del detalle no pueden
  // salir de dos reglas distintas. Orden del detalle: por sede y, dentro, por
  // nombre (el orden en que ya llegan las personas).
  const porSede = (a: FilaPersona, b: FilaPersona) => a.sede.localeCompare(b.sede);
  const personasDelResumen: Record<Exclude<ClaveResumen, "bajo_minimo">, FilaPersona[]> = {
    trabajando: filas.filter((f) => trabajandoAhora(f.estado)).sort(porSede),
    tardanzas: filas.filter(llegoTarde).sort(porSede),
    sin_marcar: filas.filter((f) => sinMarcarYaLeTocaba(f, ahoraDecimal)).sort(porSede),
  };
  // Quien está en pausa NO cuenta en «Trabajando ahora» (no está en el piso),
  // pero tampoco desaparece: se dice al lado, para que en pleno refrigerio el
  // número bajo no parezca gente que no vino.
  const enPausaTotal = filas.filter((f) => enPausaAhora(f.estado)).length;
  const sedesBajoMinimo = sedes.filter((s) => coberturaPorSede.get(s.sedeId)!.problema);
  const resumen: { clave: ClaveResumen; label: string; n: number; color: string; nota?: string }[] = [
    {
      clave: "trabajando", label: "Trabajando ahora", n: personasDelResumen.trabajando.length,
      color: personasDelResumen.trabajando.length > 0 ? "text-verde" : "text-tinta",
      nota: enPausaTotal > 0 ? `y ${enPausaTotal} en pausa` : undefined,
    },
    { clave: "tardanzas", label: "Tardanzas hoy", n: personasDelResumen.tardanzas.length, color: personasDelResumen.tardanzas.length > 0 ? "text-rojo" : "text-tinta" },
    // Tres frases distintas para lo mismo («sin marcar cuando ya debían», «sin
    // marcar y ya le tocaba», la insignia de la fila): ahora dicen lo mismo, con
    // verbo — «ya les tocaba entrar».
    { clave: "sin_marcar", label: "Sin marcar y ya les tocaba entrar", n: personasDelResumen.sin_marcar.length, color: personasDelResumen.sin_marcar.length > 0 ? "text-rojo" : "text-verde" },
    // «Bajo la meta», no «bajo mínimo»: Turnos, los recuadros de cada sede y la
    // pastilla dicen «meta». «Mínimo» era una tercera palabra para lo mismo.
    { clave: "bajo_minimo", label: "Sedes bajo la meta", n: sedesBajoMinimo.length, color: sedesBajoMinimo.length > 0 ? "text-rojo" : "text-verde" },
  ];
  const resumenDetalle = resumen.find((k) => k.clave === resumenAbierto) ?? null;

  // ---------- Disciplina, ya cargada arriba — hoisted para el resumen y el panel único ----------
  // Cualquier escalón alcanzado va en rojo, no solo la amonestación. Comparar
  // contra "amonestacion" dejaba fuera del aviso a quien ya estaba en
  // suspensión o imputación — los casos más urgentes.
  const rojosT = discTard.filter((t) => t.umbral !== "aviso");
  const rojosF = discFaltas.filter((f) => f.nivel === "rojo");
  const casosDisciplina = rojosT.length + rojosF.length + (sinCargo > 0 ? 1 : 0);

  // ---------- Filtros ----------
  function filaCoincideFiltros(f: FilaPersona): boolean {
    if (busqueda && !f.nombre.toLowerCase().includes(busqueda.trim().toLowerCase())) return false;
    if (estadoFiltro !== "todos" && f.estado !== estadoFiltro) return false;
    if (soloAlertas) {
      const esAlerta = f.estado === "auto_cerrada_pendiente" || llegoTarde(f) || sinMarcarYaLeTocaba(f, ahoraDecimal);
      if (!esAlerta) return false;
    }
    return true;
  }
  const hayFiltrosDeContenido = busqueda !== "" || estadoFiltro !== "todos" || soloAlertas;
  const hayFiltrosActivos = hayFiltrosDeContenido || sedeFiltro !== "todas";
  function limpiarFiltros() {
    setBusqueda("");
    setEstadoFiltro("todos");
    setSoloAlertas(false);
    setSedeFiltro("todas");
  }
  const sedesMostradas = sedeFiltro === "todas" ? sedes : sedes.filter((s) => s.codigo === sedeFiltro);
  // Desde el detalle de "Sedes bajo la meta" a la tarjeta de esa sede. Primero se
  // quita el filtro de sede —si la tenía oculta, la tarjeta no existe— y se baja
  // en el cuadro siguiente, cuando React ya la pintó. Un <a href="#…"> saltaba
  // antes de eso y no llegaba a ningún lado.
  function irASede(codigo: string) {
    setSedeFiltro("todas");
    const suave = !window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    requestAnimationFrame(() =>
      document.getElementById(`sede-${codigo}`)?.scrollIntoView({ behavior: suave ? "smooth" : "auto", block: "start" }),
    );
  }

  // ---------- Requiere atención (cobertura + Disciplina, en un solo panel) ----------
  interface ItemAtencion { key: string; sede: string; texto: string; href?: string; tono: "critico" | "advertencia" }
  const itemsAtencion: ItemAtencion[] = [];
  for (const s of sedes) {
    const cob = coberturaPorSede.get(s.sedeId)!;
    if (cob.alertaSinEntrada) {
      itemsAtencion.push({
        key: `sin-entrada-${s.sedeId}`, sede: s.codigo, tono: "critico",
        texto: `sin marcajes desde las ${horaAmPmDe(cob.alertaSinEntrada)} — nadie ha marcado entrada todavía`,
      });
    }
    if (cob.faltanOp || cob.faltanEnc) {
      // «Hay N en pausa» porque «faltan 4 operativas» no dice si no vinieron o
      // si están en el refrigerio — y a la hora de almuerzo es lo segundo.
      itemsAtencion.push({
        key: `cobertura-${s.sedeId}`, sede: s.codigo, tono: "advertencia",
        texto: `faltan ${loQueFalta(cob)} en piso` + (cob.enPausa.length > 0 ? ` — hay ${cob.enPausa.length} en pausa` : ""),
      });
    }
    if (cob.sinMarcarReal > 0) {
      itemsAtencion.push({
        key: `sinmarcar-${s.sedeId}`, sede: s.codigo, tono: "advertencia",
        texto: textoSinMarcar(cob.sinMarcarReal),
      });
    }
  }
  if (discNoRespondio) {
    itemsAtencion.push({
      key: "disc", sede: "Disciplina", href: "/admin/disciplina", tono: "advertencia",
      texto: "el semáforo no respondió — no es que no haya nadie, es que no pudo mirar",
    });
  } else if (casosDisciplina > 0) {
    itemsAtencion.push({
      key: "disc", sede: "Disciplina", href: "/admin/disciplina", tono: "critico",
      texto: `${casosDisciplina} caso${casosDisciplina === 1 ? "" : "s"} requiere${casosDisciplina === 1 ? "" : "n"} revisión`
        + (sinCargoNoRespondio ? " (no se pudo comprobar memos sin cargo)" : ""),
    });
  } else if (sinCargoNoRespondio) {
    itemsAtencion.push({
      key: "disc", sede: "Disciplina", href: "/admin/disciplina", tono: "advertencia",
      texto: "no se pudo comprobar si hay memos entregados sin el cargo firmado",
    });
  }

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-6 sm:p-8">
        <CabeceraPagina
          titulo="Asistencia de hoy"
          descripcion={
            <>
              <div className="flex items-center gap-2">
                {cargando && filas.length === 0 ? (
                  "Cargando…"
                ) : error ? (
                  // Si el último refresco falló, «en vivo» sería mentira: los
                  // números de abajo son de la última vez que sí respondió.
                  <>
                    <span className="inline-flex h-2 w-2 rounded-full bg-ambar" aria-hidden />
                    {fechaConDia(hoy)} · sin actualizar{actualizado ? ` — estos datos son de las ${actualizado}` : ""}
                  </>
                ) : (
                  <>
                    <span className="relative flex h-2 w-2" aria-hidden>
                      <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-verde/60" />
                      <span className="relative inline-flex h-2 w-2 rounded-full bg-verde" />
                    </span>
                    {/* La fecha, porque «hoy» sin fecha no dice de qué día son los números
                        (una captura de esta pantalla no se puede fechar después). */}
                    {fechaConDia(hoy)} · en vivo · actualizado {actualizado} · se refresca cada 30s
                  </>
                )}
              </div>
              {/* Honesto sobre el alcance real de "en vivo": Disciplina y Contratos
                  no van en el mismo refresco de 30s (cambian una vez al día, no
                  cada medio minuto) — decirlo evita la promesa que el título de
                  arriba no cumple para esas dos franjas. */}
              <div className="mt-0.5 text-taupe">Disciplina y Contratos se cargan al abrir la pantalla — recarga para verlos al día.</div>
              {/* Aviso discreto, no un banner: alguien de vacaciones podría verse como
                  "sin marcar" mientras esta consulta no responda. Menos grave que
                  Contratos o la alerta de sede — por eso no interrumpe la pantalla. */}
              {ausenciasNoRespondieron && (
                <div className="mt-1 text-ambar" title="Alguien de vacaciones podría verse como 'Sin marcar' mientras esto no se pueda comprobar.">
                  ⚠ No se pudieron comprobar las ausencias de hoy
                </div>
              )}
            </>
          }
          accion={
            <a
              href={URL_SHEET_ASISTENCIA}
              target="_blank"
              rel="noopener noreferrer"
              className="rounded-control border border-sand bg-papel px-4 py-2 text-sm font-medium text-tinta transition-all hover:-translate-y-0.5 hover:border-taupe"
            >
              Ver en Google Sheets ↗
            </a>
          }
        />

        {error && (
          <div className="mb-6 rounded-2xl border border-rojo/20 bg-rojo/[0.06] px-4 py-3 text-sm text-rojo-profundo">
            {error}{" "}
            <Boton variante="enlace" onClick={() => void cargar()}>
              Reintentar
            </Boton>
          </div>
        )}

        {cargando && filas.length === 0 ? (
          <Cargando texto="Cargando la asistencia de hoy…" />
        ) : (
          <>
            {/* FILTROS */}
            <div className="mb-6 flex flex-wrap items-end gap-3 rounded-2xl border border-sand bg-papel p-4">
              <div className="min-w-48 flex-1">
                <Campo
                  etiqueta="Buscar persona"
                  placeholder="Nombre…"
                  value={busqueda}
                  onChange={(e) => setBusqueda(e.target.value)}
                />
              </div>
              {sedes.length > 1 && (
                <CampoSelect etiqueta="Sede" value={sedeFiltro} onChange={(e) => setSedeFiltro(e.target.value)} className="min-w-32">
                  <option value="todas">Todas</option>
                  {sedes.map((s) => <option key={s.sedeId} value={s.codigo}>{s.codigo}</option>)}
                </CampoSelect>
              )}
              <CampoSelect etiqueta="Estado" value={estadoFiltro} onChange={(e) => setEstadoFiltro(e.target.value)} className="min-w-36">
                <option value="todos">Todos</option>
                <option value="abierta">Trabajando</option>
                <option value="en_pausa">En pausa</option>
                <option value="cerrada">Salió</option>
                <option value="sin_marcar">Sin marcar</option>
                <option value="auto_cerrada_pendiente">Auto-cerrada</option>
              </CampoSelect>
              <div className="pb-2">
                <CampoCasilla etiqueta="Solo alertas" checked={soloAlertas} onChange={(e) => setSoloAlertas(e.target.checked)} />
              </div>
              {hayFiltrosActivos && (
                <Boton variante="enlace" tamano="sm" className="pb-2.5" onClick={limpiarFiltros}>
                  Limpiar filtros
                </Boton>
              )}
            </div>

            {/* RESUMEN GLOBAL. Número grande y con peso: EB Garamond en su peso
                normal tiene el trazo tan fino que un "2" en rojo se leía como
                gris claro a un metro de la pantalla. Rojo y no rojo-profundo:
                a 36px basta 3:1 (5.17 claro, 4.28 oscuro), y rojo-profundo se
                lee café sobre papel. */}
            {/* Cada número es un botón que abre su detalle justo debajo, y un
                segundo clic lo cierra. En cero no se puede abrir: no hay nada
                que mostrar, y un botón que abre una lista vacía enseña que
                hacer clic no sirve. El contorno de foco va hacia adentro
                (outline-offset negativo): el contenedor recorta lo que sale.
                `flex-col justify-start` porque un <button> centra su contenido
                en vertical, y la tarjeta con la etiqueta en dos líneas dejaba
                su número más arriba que las otras tres. */}
            <div className={`${resumenDetalle ? "mb-3" : "mb-6"} grid grid-cols-2 gap-px overflow-hidden rounded-2xl border border-sand bg-sand sm:grid-cols-4`}>
              {resumen.map((k) => {
                const abierto = resumenAbierto === k.clave;
                return (
                  <button
                    key={k.clave}
                    type="button"
                    disabled={k.n === 0}
                    aria-expanded={k.n === 0 ? undefined : abierto}
                    aria-controls="detalle-resumen"
                    aria-label={`${k.label}: ${k.n}${k.nota ? `, ${k.nota}` : ""}`}
                    onClick={() => setResumenAbierto(abierto ? null : k.clave)}
                    className={`flex flex-col justify-start px-5 py-4 text-left transition-colors focus-visible:outline-offset-[-3px] disabled:cursor-default ${abierto ? "bg-hueso" : "bg-papel enabled:hover:bg-crema"}`}
                  >
                    {/* <span> y no <div>: dentro de un <button> HTML solo admite
                        contenido de frase. */}
                    <span className="flex items-start justify-between gap-2">
                      <span className={`font-serif text-4xl font-medium leading-none tabular-nums ${k.color}`}>{k.n}</span>
                      {k.n > 0 && (
                        <span aria-hidden className={`text-xs ${abierto ? "font-medium text-tinta" : "text-taupe"}`}>{abierto ? "Cerrar ↑" : "Ver ↓"}</span>
                      )}
                    </span>
                    <span className="mt-2 block text-sm text-taupe">{k.label}</span>
                    {k.nota && <span className="mt-0.5 block text-xs font-medium text-ambar">{k.nota}</span>}
                  </button>
                );
              })}
            </div>

            {/* DETALLE DEL NÚMERO ABIERTO. De todas las sedes a la vista, sin
                los filtros de más arriba: el número tampoco los aplica, y si la
                lista los aplicara, al "10" le respondería una lista de 3. */}
            {resumenDetalle && (
              <section id="detalle-resumen" className="mb-8 rounded-2xl border border-sand bg-papel p-5">
                <div className="mb-3 flex flex-wrap items-baseline justify-between gap-2">
                  <h2 className="font-serif text-xl font-medium">
                    {resumenDetalle.label} <span className="text-taupe">· {resumenDetalle.n}</span>
                  </h2>
                  <Boton variante="enlace" tamano="sm" onClick={() => setResumenAbierto(null)}>
                    Cerrar ↑
                  </Boton>
                </div>
                {resumenDetalle.clave === "bajo_minimo" ? (
                  // Sedes, no personas: el detalle es qué le falta a cada una, y
                  // un enlace a su tarjeta de más abajo, que ya tiene todo.
                  sedesBajoMinimo.length === 0 ? (
                    <p className="text-sm text-taupe">Ninguna sede está bajo la meta ahora mismo.</p>
                  ) : (
                    <ul className="flex flex-col">
                      {sedesBajoMinimo.map((s) => (
                        <li key={s.sedeId} className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 border-t border-sand/60 py-2 text-sm first:border-t-0">
                          <span><strong className="font-semibold">{s.codigo}:</strong> faltan {loQueFalta(coberturaPorSede.get(s.sedeId)!)} en piso</span>
                          <Boton variante="enlace" tamano="sm" className="text-xs font-semibold text-rojo-profundo" onClick={() => irASede(s.codigo)}>
                            Ver sede ↓
                          </Boton>
                        </li>
                      ))}
                    </ul>
                  )
                ) : personasDelResumen[resumenDetalle.clave].length === 0 ? (
                  // Posible sin cerrar: el refresco de 30 s puede dejar en cero
                  // una lista que estaba abierta.
                  <p className="text-sm text-taupe">Nadie ahora mismo.</p>
                ) : (
                  <TablaPersonas filas={personasDelResumen[resumenDetalle.clave]} linkCorregir={linkCorregir} ahoraDecimal={ahoraDecimal} conSede />
                )}
              </section>
            )}

            {/* REQUIERE ATENCIÓN — cobertura de sedes + Disciplina, un solo lugar */}
            {itemsAtencion.length === 0 ? (
              <div className="relative mb-8 overflow-hidden rounded-2xl border border-sand bg-papel p-5 pl-6">
                <Franja tono="positivo" />
                <div className="etiqueta text-verde">Requiere atención</div>
                <p className="mt-2 text-sm text-taupe">Nada pendiente ahora mismo.</p>
              </div>
            ) : (
              <div className="relative mb-8 overflow-hidden rounded-2xl border border-sand bg-papel p-5 pl-6">
                <Franja tono={itemsAtencion.some((it) => it.tono === "critico") ? "alerta" : "advertencia"} />
                <div className="etiqueta text-rojo-profundo">Requiere atención</div>
                <ul className="mt-1 flex flex-col">
                  {itemsAtencion.map((it) => {
                    // El punto repite el tono de cada fila: antes solo el "Ver →"
                    // lo decía, y las filas sin enlace no tenían ninguno.
                    const contenido = (
                      <span className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 py-2 text-sm">
                        <span className="flex items-baseline gap-2">
                          <span aria-hidden className={`size-2 shrink-0 translate-y-[-1px] rounded-full ${it.tono === "critico" ? "bg-rojo" : "bg-ambar"}`} />
                          <span><strong className="font-semibold">{it.sede}:</strong> <span className="text-tinta">{it.texto}</span></span>
                        </span>
                        {it.href && <span className={`text-xs font-semibold ${it.tono === "critico" ? "text-rojo-profundo" : "text-ambar"}`}>Ver →</span>}
                      </span>
                    );
                    return (
                      <li key={it.key} className="border-t border-sand/60 first:border-t-0">
                        {it.href ? (
                          <Link href={it.href} className="-mx-1 block rounded px-1 transition-colors hover:bg-rojo/[0.06]">{contenido}</Link>
                        ) : contenido}
                      </li>
                    );
                  })}
                </ul>
              </div>
            )}

            {/* QUIÉN RESPONDIÓ SU MEMO (0404). Aparte del panel de arriba porque
                no es un plazo legal corriendo — es informativo: alguien ya vio su
                documento y dejó una constancia digital, firmando o prefiriendo no
                hacerlo. Ninguna de las dos reemplaza el trámite físico. */}
            {respuestasMemo.length > 0 && (
              <div className="mb-8 rounded-2xl border border-sand bg-papel p-5 pl-6">
                <div className="mb-2 flex items-center justify-between">
                  <span className="font-serif text-xl font-medium text-tinta">
                    Respuestas a memos <span className="text-taupe">· últimos {DIAS_RESPUESTAS_MEMO} días</span>
                  </span>
                  <Link href="/admin/disciplina" className="text-xs font-medium text-taupe hover:underline">Ver disciplina →</Link>
                </div>
                {respuestasMemo.map((r) => (
                  <Link key={r.id} href={`/admin/disciplina/memo/${r.id}`}
                    className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 border-t border-sand/60 py-2 text-sm transition-colors hover:bg-verde/[0.06]">
                    <span>
                      <strong>{r.persona}</strong>
                      <Insignia variante={r.firmado_at ? "positivo" : "neutral"} className="ml-2">
                        {r.firmado_at ? "firmó digitalmente" : "prefirió no firmar"}
                      </Insignia>
                    </span>
                    <span className="text-xs text-taupe">{fechaCorta((r.firmado_at ?? r.rechazado_at)!.slice(0, 10))}</span>
                  </Link>
                ))}
              </div>
            )}

            {/* CONTRATOS A PLAZO FIJO. Dos grupos, y el importante es el primero:
                quien ya venció y sigue figurando activo. Ese caso no se nota en
                ninguna otra pantalla —la persona aparece normal en asistencia, en
                planilla y en provisiones— y desde la 0162 tampoco en el tablero de
                Documentación. Sin esta franja, la fecha anotada en Equipo solo sirve
                si alguien se acuerda de ir a buscarla. */}
            {(() => {
              // Igual que Disciplina: si la RPC no contestó, la franja NO se
              // calla — dice que no pudo mirar, en vez de parecer un mes tranquilo.
              if (contratosNoRespondio) {
                return (
                  <section className="mb-8 rounded-2xl border border-ambar/30 bg-ambar/[0.06] p-5">
                    <div className="etiqueta text-ambar">Contratos a plazo fijo · no se pudo consultar</div>
                    <p className="mt-2 text-sm text-tinta">
                      No se pudo revisar qué contratos vencen o ya vencieron. El plazo del{" "}
                      <strong>artículo 77</strong> corre igual aunque esta franja no haya podido mirar.
                      Vuelve a cargar, y si sigue igual revisa{" "}
                      <Link href="/admin/equipo" className="underline">Equipo</Link>.
                    </p>
                  </section>
                );
              }
              const vencidos = contratos.filter((c) => c.ya_vencio);
              const porVencer = contratos.filter((c) => !c.ya_vencio);
              if (!vencidos.length && !porVencer.length) return null;
              const enCuantos = (dias: number) =>
                dias <= 0 ? "vence hoy" : dias === 1 ? "vence mañana" : `vence en ${dias} días`;
              // ¿Muchos caen el MISMO día? Veinte líneas seguidas con la misma fecha
              // se leen como veinte avisos sueltos, y el problema no son veinte
              // renovaciones repartidas: es que hay que hacerlas todas esa semana.
              // Se dice de una vez, arriba, antes de la lista.
              const porFecha = new Map<string, number>();
              for (const c of porVencer) porFecha.set(c.fecha_fin_contrato, (porFecha.get(c.fecha_fin_contrato) ?? 0) + 1);
              const [fechaRacimo, cuantos] = [...porFecha.entries()]
                .sort((a, b) => b[1] - a[1])[0] ?? ["", 0];
              const hayRacimo = cuantos >= 3;
              return (
                <div className="relative mb-8 overflow-hidden rounded-2xl border border-sand bg-papel p-5 pl-6">
                  {/* Rojo si alguien ya pasó su fecha (el art. 77 ya corrió);
                      ámbar si solo se acerca. */}
                  <Franja tono={vencidos.length > 0 ? "alerta" : "advertencia"} />
                  <div className="mb-2 flex items-center justify-between">
                    <span className="font-serif text-xl font-medium text-tinta">Contratos a plazo fijo</span>
                    <Link href="/admin/equipo" className="text-xs font-semibold text-rojo-profundo hover:underline">Ver equipo →</Link>
                  </div>
                  {hayRacimo && (
                    <p className="mb-2 rounded-lg bg-rojo/10 px-3 py-2 text-sm text-rojo-profundo">
                      <strong>{cuantos} contratos vencen el mismo día</strong> ({fechaCorta(fechaRacimo)}).
                      No son {cuantos} trámites repartidos: son {cuantos} decisiones, {cuantos} redacciones
                      y {cuantos} firmas en la misma semana. Al que se pase de fecha con la persona
                      todavía trabajando, el <strong>art. 77</strong> lo vuelve indefinido solo.
                    </p>
                  )}
                  {vencidos.map((c) => (
                    <div key={c.persona_id} className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 border-t border-sand/60 py-2 text-sm">
                      <span>
                        <strong>{c.nombre}</strong> <span className="text-taupe">· {c.sede}</span>
                        <Insignia variante="alerta" className="ml-2">
                          terminó el {fechaCorta(c.fecha_fin_contrato)} y sigue de alta
                        </Insignia>
                      </span>
                      <span className="text-xs font-semibold text-rojo-profundo">renovar o registrar su salida →</span>
                    </div>
                  ))}
                  {porVencer.map((c) => (
                    <div key={c.persona_id} className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 border-t border-sand/60 py-2 text-sm">
                      <span>
                        <strong>{c.nombre}</strong> <span className="text-taupe">· {c.sede}</span>
                        <Insignia variante="advertencia" className="ml-2">
                          {enCuantos(c.dias_restantes)} · {fechaCorta(c.fecha_fin_contrato)}
                        </Insignia>
                      </span>
                    </div>
                  ))}
                  <p className="border-t border-sand/60 pt-2.5 text-xs text-taupe">
                    {vencidos.length > 0
                      ? "Mientras siga de alta sigue marcando, sigue cobrando y sigue acumulando gratificación, CTS y vacaciones. Anotar la fecha no da de baja a nadie: eso se decide y se registra a mano."
                      : "La fecha es lo previsto, no un hecho. Un contrato puede renovarse: esto solo avisa antes de que llegue el día."}
                  </p>
                </div>
              );
            })()}

            {/* !alertaSinEntrada && horarioEsperadoNoRespondio, a nivel global:
                si turnos/horarios fallaron, ninguna sede puede calcular su alerta
                de "sin marcajes" ni su denominador de programados hoy. */}
            {horarioEsperadoNoRespondio && (
              <div className="mb-6 flex items-center gap-2 rounded-2xl border border-ambar/30 bg-ambar/[0.06] px-5 py-3 text-sm text-ambar">
                <span className="flex h-4 w-4 shrink-0 items-center justify-center rounded-full bg-ambar text-[10px] font-bold text-crema">!</span>
                No se pudo comprobar a quién le tocaba entrar hoy — la alerta de sedes sin marcajes y el conteo de &quot;programadas hoy&quot; no están disponibles ahora mismo.
              </div>
            )}

            {sedesMostradas.length === 0 && (
              <p className="rounded-2xl border border-sand bg-papel p-6 text-center text-sm text-taupe">
                No encontramos personas con estos filtros.
              </p>
            )}

            {sedesMostradas.map(({ sedeId, codigo }) => {
              const deSedeCompleta = filas.filter((f) => f.sedeId === sedeId);
              const deSedeMostrada = deSedeCompleta.filter(filaCoincideFiltros);
              const cob = coberturaPorSede.get(sedeId)!;
              // Un solo estado de la sede, del que salen la franja y la pastilla —
              // así no pueden decir cosas distintas. "Sede sin marcajes" también
              // es alerta aunque no tenga meta: nadie llegó y a alguien le tocaba.
              const estadoSede: { tono: TonoFranja; texto: string } =
                cob.problema || cob.alertaSinEntrada
                  ? { tono: "alerta", texto: cob.problema ? "Cobertura insuficiente" : "Sin marcajes" }
                  : cob.sinMetaOp && cob.sinMetaEnc
                    ? { tono: "neutral", texto: "Sin meta configurada" }
                    : { tono: "positivo", texto: "Cobertura correcta" };

              const tablaVisible = hayFiltrosDeContenido || (detalleAbierto[sedeId] ?? false);

              return (
                <section key={sedeId} id={`sede-${codigo}`} className="relative mb-8 scroll-mt-24 overflow-hidden rounded-2xl border border-sand bg-papel p-5 pl-6 sm:p-6 sm:pl-7">
                  <Franja tono={estadoSede.tono} />
                  <div className="mb-1 flex flex-wrap items-center justify-between gap-3">
                    <h2 className="font-serif text-2xl font-medium leading-tight">
                      {codigo}{" "}
                      {/* «N trabajando ahora · M en pausa», no «N de M programadas»:
                          el N cuenta a cualquiera que esté en el piso y el M solo a
                          quien tenía turno, así que la razón podía salir «5 de 4».
                          Cuántas les tocaba venir se dice abajo, con sus palabras. */}
                      <span className="text-lg font-normal text-taupe">
                        — {cob.trabajando.length} trabajando ahora
                        {cob.enPausa.length > 0 && <> · <span className="text-ambar">{cob.enPausa.length} en pausa</span></>}
                      </span>
                    </h2>
                    <Insignia
                      variante={estadoSede.tono}
                      atenuada={estadoSede.tono === "neutral"}
                      className="px-3 py-1 font-semibold"
                    >
                      {estadoSede.texto}
                    </Insignia>
                  </div>
                  <p className="mb-4 text-xs text-taupe">
                    {textoEquipoDelDia(cob.programadosHoy, deSedeCompleta.length)}
                  </p>

                  {/* La única alerta que se permite el rojo sagrado en esta pantalla,
                      además de la que ya vive arriba en "Requiere atención": la
                      repetimos acá, junto a la sede, para quien llegó directo a esta
                      tarjeta sin pasar por el resumen. */}
                  {cob.alertaSinEntrada && (
                    <div className="mb-4 flex items-center gap-2 rounded-2xl border border-rojo bg-rojo/[0.06] px-5 py-3 text-sm font-semibold text-rojo-profundo">
                      <span className="flex h-4 w-4 shrink-0 items-center justify-center rounded-full bg-rojo text-[10px] font-bold text-crema">!</span>
                      Sin marcajes desde las {horaAmPmDe(cob.alertaSinEntrada)} — nadie de esta sede ha marcado entrada todavía.
                    </div>
                  )}

                  {/* Cobertura protagonista: es la pregunta que decide si hay que
                      actuar, así que va primero y grande — no al pie como texto. */}
                  <div className="mb-4 grid grid-cols-2 gap-3 sm:max-w-md">
                    <TileCobertura label="Operativas en piso" n={cob.opPiso} meta={cob.metaOp} sinMeta={cob.sinMetaOp} tramo={tramoLabel} />
                    <TileCobertura label="Líderes en piso" n={cob.encPiso} meta={cob.metaEnc} sinMeta={cob.sinMetaEnc} />
                  </div>

                  {/* Recuadro verde claro de "Trabajando ahora": estuvo desde julio y
                      el commit 8aae5710 (15-sep) lo cambió por una línea de texto
                      suelta. Era lo que se buscaba primero al abrir la pantalla, así
                      que vuelve. Sin nadie trabajando no se pinta de verde: verde es
                      "hay gente en piso", y un recuadro verde que dice "nadie"
                      afirmaría lo contrario de lo que escribe. Al 15% y no al 6% de
                      antes: es el mismo relleno de la insignia "Trabajando", y con el
                      verde retonado el 2026-09-06 el 6% ya se leía gris. La etiqueta
                      verde encima da 5.27:1 claro y 4.91:1 oscuro. */}
                  <div
                    className={`mb-4 rounded-superficie border px-4 py-3 ${cob.trabajando.length > 0 ? "border-verde/30 bg-verde/15" : "border-sand bg-crema"}`}
                  >
                    <div className={`etiqueta ${cob.trabajando.length > 0 ? "text-verde" : "text-taupe"}`}>Trabajando ahora · {cob.trabajando.length}</div>
                    <div className="mt-2 flex flex-wrap gap-2">
                      {cob.trabajando.length === 0 ? (
                        <span className="text-sm text-taupe">Nadie está trabajando en este momento.</span>
                      ) : (
                        // Pastillas en papel sobre el verde, como antes.
                        cob.trabajando.map((f) => (
                          <span
                            key={f.personaId}
                            className="inline-flex items-center gap-2 rounded-full border border-verde/25 bg-papel px-3 py-1 text-sm"
                          >
                            <span aria-hidden className="size-1.5 rounded-full bg-verde" />
                            {f.nombre}
                          </span>
                        ))
                      )}
                    </div>
                  </div>

                  {/* «En pausa», aparte y no dentro de «Trabajando ahora». Hasta el
                      2026-09-18 quien había salido a refrigerio, a un trámite o al
                      médico iba en el recuadro verde con una etiqueta ámbar, y el
                      número de arriba lo contaba como trabajando: en pleno almuerzo
                      una sede entera fuera decía «4 trabajando». Sigue a la vista
                      —si no, un equipo en refrigerio parecería gente que no vino—
                      pero no como trabajando.
                      Relleno al 10%: la etiqueta ámbar encima da 5.89:1 en claro y
                      5.22:1 en oscuro (midiendo con la misma fórmula que el verde).
                      Las pastillas quedan en papel: ámbar sobre relleno ámbar daba
                      4.26:1 en modo oscuro, y sobre papel da 6.17:1. */}
                  {cob.enPausa.length > 0 && (
                    <div className="mb-4 rounded-superficie border border-ambar/30 bg-ambar/10 px-4 py-3">
                      <div className="etiqueta text-ambar">En pausa · {cob.enPausa.length}</div>
                      <div className="mt-2 flex flex-wrap gap-2">
                        {cob.enPausa.map((f) => (
                          <span
                            key={f.personaId}
                            className="inline-flex items-center gap-2 rounded-full border border-ambar/45 bg-papel px-3 py-1 text-sm"
                          >
                            <span aria-hidden className="size-1.5 rounded-full bg-ambar" />
                            {f.nombre}
                          </span>
                        ))}
                      </div>
                    </div>
                  )}

                  {tablaVisible ? (
                    <>
                      {deSedeMostrada.length === 0 ? (
                        <p className="text-sm text-taupe">No encontramos personas con estos filtros en esta sede.</p>
                      ) : (
                        <TablaPersonas filas={deSedeMostrada} linkCorregir={linkCorregir} ahoraDecimal={ahoraDecimal} />
                      )}
                      {!hayFiltrosDeContenido && (
                        <Boton variante="enlace" tamano="sm" className="mt-3" onClick={() => setDetalleAbierto((s) => ({ ...s, [sedeId]: false }))}>
                          Ocultar detalle ↑
                        </Boton>
                      )}
                    </>
                  ) : (
                    <Boton variante="enlace" tamano="sm" onClick={() => setDetalleAbierto((s) => ({ ...s, [sedeId]: true }))}>
                      Ver detalle ↓ ({deSedeCompleta.length} persona{deSedeCompleta.length === 1 ? "" : "s"})
                    </Boton>
                  )}
                </section>
              );
            })}
          </>
        )}
      </main>
    </div>
  );
}

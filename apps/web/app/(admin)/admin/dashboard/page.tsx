"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
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
import { Cifra } from "@/components/ui/cifra";
import { Filtro } from "@/components/ui/filtro";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { Menu, MenuItem } from "@/components/ui/menu";
import {
  TZ_LIMA, cuentaEnCobertura, etiquetaDeSede, hoyLima, formatoMinutos, puedeVerTodasLasSedes,
} from "@cayla-dynamic/shared";
import { esFeriadoSinTurno, esperadoDelDia, horarioVigente, SEDE_SIN_TURNOS, type HorarioTramo, type TurnoDia } from "@/lib/admin/jornada-esperada";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { useFiltroGuardado } from "@/lib/admin/use-filtro-guardado";
import {
  calcularCoberturaSede, causaMetaImposible, coincideConFiltroDeEstado, enPausaAhora, faltanTexto, fechaConDia, fechaCorta, llegoTarde, loQueFalta,
  minutosDesde, porPausaMasLarga, sinMarcarYaLeTocaba, subEstadoSinMarcar, textoDesglose, textoEquipoDelDia,
  diaDeLaSemanaEnPlural, metaDelDiaTexto, OPCIONES_FILTRO_ESTADO, textoFueraDeHorario, textoLiderEnLasDosMetas, textoMetaPorRevisar, textoMetaSinTurnos, textoSinHorario, textoPausa, textoPausaDesde, textoSinMarcar, trabajandoAhora,
  type CoberturaSede, type FilaPersona, type MetaSede,
} from "@/lib/admin/asistencia-hoy";
import { traerPausasAbiertas } from "@/lib/admin/pausas-abiertas";
import { traerSiEsFeriado } from "@/lib/admin/feriado-de-hoy";
import { esFallaDeRed, mensajeDeError } from "@/lib/admin/mensaje-error";
import {
  KPIS_EXTRA, PANELES_NO_OCULTABLES, alternarAlertas, alternarColapsado, alternarKpiExtra, alternarOculto,
  moverPanel, normalizarPreferencias, PREFERENCIAS_INICIALES, type KpiExtra, type PanelId,
} from "@/lib/admin/tablero-preferencias";
import { PanelColapsable } from "./panel-colapsable";
import { PanelAtencionBanner, PanelAtencionLateral } from "./panel-atencion";
import { FiltrosCelular } from "./filtros-celular";
import { usePendientesBandeja } from "./use-pendientes-bandeja";
import { useCasosResumen } from "./use-casos-resumen";
import { useRefrescoLento } from "./use-refresco-lento";

const REFRESCO_MS = 30_000;
// Los catálogos casi fijos (sedes, áreas, tipos de ausencia) no cambian cada 30 s: se
// piden al abrir y se vuelven a pedir cada 10 minutos. Recargar la pantalla los trae
// al instante (la caché vive solo mientras la pestaña está abierta), así que reactivar
// una sede y recargar la muestra enseguida. Las metas de cobertura NO entran aquí:
// se editan en Turnos y se siguen pidiendo en cada ciclo.
const CATALOGOS_MS = 10 * 60_000;
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
    // Feriado sin turno: le tocaba por su horario y la hora ya pasó, pero la base no se lo
    // exige (no es falta). Neutro y sin enlace a Correcciones: no hay nada que corregir.
    if (sub === "feriado") {
      return <Insignia variante="neutral">Feriado · le tocaba {horaAmPmDe(f.entradaEsperadaHoy!)}</Insignia>;
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
  // En pausa: cuánto lleva, para no confundir un refrigerio de 40 minutos con un
  // retorno que nadie marcó hace tres horas. La hora exacta va en el `title`.
  if (f.estado === "en_pausa" && f.pausa) {
    return (
      <span title={textoPausa(f.pausa)}>
        <Insignia variante={estilo.variante}>{estilo.label} · {formatoMinutos(minutosDesde(f.pausa.desde))}</Insignia>
      </span>
    );
  }
  return <Insignia variante={estilo.variante} atenuada={estilo.atenuada}>{estilo.label}</Insignia>;
}

// La tabla de personas de una sede: filas en escritorio, tarjetas en celular.
// Un solo componente para que cualquier lista de personas de esta pantalla se
// vea y se corrija igual — cada fila con tardanza o auto-cierre enlaza a
// Correcciones de esa persona ese día. `conSede` agrega la columna cuando la
// lista mezcla sedes (el detalle de un número del resumen).
// El nombre de cada persona abre su día en Correcciones: ahí está el
// historial completo de marcas, lo que se le esperaba y lo que se corrigió.
// No se arma aquí una segunda vista del día —sería otra copia de «qué pasó
// ese día» que tarde o temprano contaría distinto que Correcciones—; se
// reusa el mismo enlace `?persona=…&fecha=…` que ya llevan el estado y la
// tardanza. Dashboard y Correcciones los ven los mismos roles (`SEDE` en
// nav-items.ts), así que el enlace nunca lleva a una puerta cerrada.
function NombreAlDia({ f, linkCorregir }: { f: FilaPersona; linkCorregir: (personaId: string) => string }) {
  return (
    <Link href={linkCorregir(f.personaId)} title={`Ver el día de ${f.nombre} en Correcciones`}
      className="underline-offset-2 hover:underline">
      {f.nombre}
    </Link>
  );
}

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
                <td className="px-4 py-2.5">
                  <NombreAlDia f={f} linkCorregir={linkCorregir} />
                </td>
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
                <NombreAlDia f={f} linkCorregir={linkCorregir} />
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
//
// Fuera de horario (la sede ya cerró o aún no abre, y no queda nadie) el tile se
// apaga a neutro y no dice «Faltan N»: la meta no se está midiendo, y un rojo ahí
// afirmaba una falta que no existe. Ver fueraDeHorarioDeHoy.
//
// Ámbar y «Meta por revisar» cuando la meta no se puede cumplir aunque vengan todos
// (`porRevisar`): ahí «Faltan 4» era cierto pero nadie podía hacer nada, y un rojo
// que no se apaga viniendo a trabajar enseña a ignorar los rojos. Ver `gravedad`.
function TileCobertura({ label, n, meta, sinMeta, tramo, fueraDeHorario = false, porRevisar = false }: { label: string; n: number; meta: number; sinMeta: boolean; tramo?: string; fueraDeHorario?: boolean; porRevisar?: boolean }) {
  const ok = !sinMeta && n >= meta;
  const sinMedir = fueraDeHorario && !sinMeta && !ok;
  const tono = sinMeta || sinMedir
    ? { caja: "border-sand bg-crema", numero: "text-taupe", texto: "text-taupe" }
    : ok
      ? { caja: "border-verde/30 bg-verde/[0.08]", numero: "text-verde", texto: "text-verde" }
      : porRevisar
        ? { caja: "border-ambar/30 bg-ambar/10", numero: "text-ambar", texto: "text-ambar" }
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
        <div className={`mt-1 text-sm font-semibold ${tono.texto}`}>{ok ? "Completo" : sinMedir ? "Fuera de horario" : porRevisar ? "Meta por revisar" : faltanTexto(meta - n)}</div>
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
  const [sedesActivas, setSedesActivas] = useState<{ id: string; codigo: string; nombre: string; tipo: string; ciudad: string | null }[]>([]);
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
  // `metas_cobertura` no contestó: todas las sedes reciben meta 0, y decir de una sede sin
  // turnos «no tiene meta para este día» sería afirmar lo que no se sabe. Se comporta como
  // `horarioEsperadoNoRespondio`: sin meta confiable, ninguna sede se declara «Sin turnos».
  const [metasNoRespondieron, setMetasNoRespondieron] = useState(false);
  // `ausencias` no contestó: alguien de vacaciones puede verse idéntico a un
  // "sin marcar" real mientras esto no se pueda comprobar (mismo riesgo de
  // falso positivo que ya resuelve `ausenciaHoy` cuando la consulta sí responde).
  const [ausenciasNoRespondieron, setAusenciasNoRespondieron] = useState(false);
  // `marcajes` no contestó al pedir DESDE CUÁNDO está en pausa cada quien: sus
  // nombres se muestran igual, sin hora, y el recuadro lo dice. Que falle no es
  // «nadie tiene pausa» (ver pausas-abiertas.ts).
  const [pausasNoRespondieron, setPausasNoRespondieron] = useState(false);
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
  // Qué sedes tienen su tarjeta desplegada. De ESTA visita, no se guarda: abrir
  // mañana con la tarjeta de ayer desplegada haría creer que es lo único que hay.
  const [sedesAbiertas, setSedesAbiertas] = useState<Record<string, boolean>>({});
  // El tablero de cada persona (orden, colapsados, ocultos, indicadores extra):
  // se guarda en su navegador, como «equipo colapsado» de Correcciones. Lo
  // guardado puede venir viejo o dañado, así que SIEMPRE pasa por normalizar.
  const [prefsCrudas, setPrefsCrudas] = useFiltroGuardado<unknown>("dashboard.tablero", null);
  const prefs = useMemo(() => normalizarPreferencias(prefsCrudas), [prefsCrudas]);
  const [personalizando, setPersonalizando] = useState(false);
  const pendientesBandeja = usePendientesBandeja(prefs.kpisExtra.pendientes === true, yo?.rol);
  const casosResumen = useCasosResumen(prefs.kpisExtra.casos === true);
  // La categoría con más casos, para escalar las barras de «Por categoría» — se
  // saca aquí y no dentro del `.map()` de la lista para que TS no pierda el
  // `resumen` que ya se comprobó no-nulo antes de entrar a esa rama.
  const maxCategoriaCasos = casosResumen.resumen?.porCategoria[0]?.total ?? 0;
  const catalogos = useRef<{ en: number; sedes: unknown; areas: unknown; tipos: unknown } | null>(null);

  // Semáforo disciplinario para la franja (aparte del refresco de asistencia).
  const cargarDisciplina = useCallback(async () => {
    const sb = createAdminSupabaseClient();
    await (async () => {
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
        // `.neq("medio_entrega", "digital")`: una entrega por Info (0486) no tiene
        // papel que archivar —su constancia es la confirmación de la persona, en
        // la misma fila—. Es la misma regla que `pendientesDeEntregado`, repetida
        // acá porque esta franja pide a la base solo los ids. Un entregado siempre
        // tiene medio (chk_entregado_completo), así que el `<>` no pierde filas.
        sb.from("expediente_disciplinario").select("id").eq("estado", "entregado").neq("medio_entrega", "digital"),
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
  useRefrescoLento(cargarDisciplina);

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
  const cargarContratos = useCallback(async () => {
    const sb = createAdminSupabaseClient();
    await (async () => {
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
  useRefrescoLento(cargarContratos);

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) {
      router.replace("/admin/login");
      return;
    }

    const hoy = hoyLima();
    const diaHoy = diaSemanaDe(hoy);
    const pedirSedes = () => supabase.from("sedes").select("id, codigo, nombre, tipo, ciudad").eq("activa", true).order("codigo");
    const pedirAreas = () => supabase.rpc("fn_areas");
    const pedirTiposAusencia = () => supabase.from("tipos_ausencia").select("codigo, nombre, requiere_aprobacion");
    const guardado = catalogos.current && Date.now() - catalogos.current.en < CATALOGOS_MS ? catalogos.current : null;
    // minutos_salida_temprana va por RPC (fn_jornadas_extra) porque el schema cache
    // de PostgREST no expone la columna; el select directo fallaría entero.
    const [
      { data: sedesData, error: errSedes },
      { data: personas, error: errPersonas },
      { data: jornadas, error: errJornadas },
      { data: extras }, // fn_jornadas_extra ya está diseñada para fallar en silencio (ver comentario abajo)
      { data: funciones }, // función + es_encargada_piso (RPC: el schema cache no expone la columna)
      { data: areasRaw, error: errAreas }, // catálogo de áreas (para saber cuáles son operativas)
      { data: metasRaw, error: errMetas }, // metas de cobertura de hoy por sede (falla suave: sin meta = neutro; ver `metasNoRespondieron`)
      // Ausencias SÍ lleva su error: si falla, alguien de vacaciones se vería
      // idéntico a un "sin marcar" real, y eso merece un aviso discreto (ver abajo).
      { data: ausenciasHoy, error: errAusencias },
      { data: tiposAusencia, error: errTipos }, // catálogo (nombre + si exige aprobación), para no repetirlo a mano acá
      // Turnos y horarios SÍ llevan su error: de los dos sale `entradaEsperadaHoy`,
      // que alimenta la única alerta roja de esta pantalla fuera de Disciplina
      // ("sede sin marcar"). Si cualquiera de las dos falla, esa alerta no puede
      // dispararse aunque corresponda — y sin la bandera, se apagaría sin aviso.
      { data: turnosHoy, error: errTurnos },
      { data: horariosVigentes, error: errHorarios },
      // ¿Hoy es feriado? Solo SUAVIZA una alarma (ver `esFeriadoSinTurno`), así que si la
      // consulta falla no hace falta bandera: cae a «no es feriado» y la alarma vuelve a ser
      // la roja de siempre. Una duda cae hacia la alarma, no hacia el silencio.
      feriadoHoy,
    ] = await Promise.all([
      // Misma consulta que /admin/reporte-sede: la lista de sedes a mostrar
      // nunca se deriva de quién aparece en otra tabla.
      guardado ? (guardado.sedes as Awaited<ReturnType<typeof pedirSedes>>) : pedirSedes(),
      supabase
        .from("personas")
        .select("id, nombres, apellidos, rol, sede_base_id, sedes:sede_base_id(codigo)")
        .eq("estado", "activo").eq("cuenta_de_servicio", false)
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
      guardado ? (guardado.areas as Awaited<ReturnType<typeof pedirAreas>>) : pedirAreas(),
      supabase.from("metas_cobertura").select("sede_id, meta, meta_tarde, meta_encargadas").eq("dia_semana", diaHoy),
      // anulada_at is null: una ausencia anulada no cubre nada. El rango incluye
      // hoy con <= / >=, igual que el `between` que ya usa fn_faltas_resumen.
      supabase.from("ausencias").select("persona_id, tipo, aprobada_at").is("anulada_at", null).lte("fecha_inicio", hoy).gte("fecha_fin", hoy),
      guardado ? (guardado.tipos as Awaited<ReturnType<typeof pedirTiposAusencia>>) : pedirTiposAusencia(),
      supabase.from("turnos").select("persona_id, fecha, hora_entrada, hora_salida, es_descanso").eq("fecha", hoy),
      supabase
        .from("horarios_asignados")
        .select("persona_id, hora_entrada, hora_salida, dias_laborables, horario_por_dia, almuerzo_min_minutos, vigente_desde, vigente_hasta")
        .lte("vigente_desde", hoy)
        .or(`vigente_hasta.is.null,vigente_hasta.gte.${hoy}`),
      traerSiEsFeriado(supabase, hoy),
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
    if (!guardado && !errAreas && !errTipos) {
      catalogos.current = {
        en: Date.now(),
        sedes: { data: sedesData, error: errSedes },
        areas: { data: areasRaw, error: errAreas },
        tipos: { data: tiposAusencia, error: errTipos },
      };
    }
    setAusenciasNoRespondieron(Boolean(errAusencias));

    // Función/área/encargada: si la RPC falla, degradamos a "todos operativos"
    // (misma política que Turnos) — la cobertura puede marcar de más pero la
    // página no se cae. Las metas fallan aún más suave: sin meta = neutro.
    const areasList: Area[] = parseAreas(areasRaw, errAreas);
    const funcionPorPersona = new Map(
      ((funciones as { persona_id: string; funcion: string; es_encargada_piso?: boolean; tipo_vinculo?: string | null }[] | null) ?? [])
        .map((x) => [x.persona_id, { funcion: x.funcion, enc: Boolean(x.es_encargada_piso), vinculo: x.tipo_vinculo ?? null }]),
    );
    // Quién cuenta en la cobertura depende del TIPO de la sede (en una central
    // el administrador hace de líder), así que se busca por sede base.
    const tipoDeSede = new Map((sedesData ?? []).map((s) => [s.id, s.tipo]));
    const metasNuevas = new Map(
      ((metasRaw as { sede_id: string; meta: number; meta_tarde: number | null; meta_encargadas: number | null }[] | null) ?? [])
        .map((m) => [m.sede_id, { man: m.meta ?? 0, tar: m.meta_tarde ?? m.meta ?? 0, enc: m.meta_encargadas ?? 0 }] as const),
    );

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
      const cuenta = cuentaEnCobertura(
        {
          rol: p.rol,
          tipoVinculo: f?.vinculo ?? null,
          esEncargadaPiso: Boolean(f?.enc),
          areaOperativa: esOperativaEn(areasList, f?.funcion ?? AREA_DEFAULT),
        },
        tipoDeSede.get(p.sede_base_id) ?? null,
      );
      return {
        personaId: p.id,
        nombre: `${p.nombres} ${p.apellidos}`,
        sede: p.sedes?.codigo ?? "?",
        sedeId: p.sede_base_id,
        estado: j?.estado ?? "sin_marcar",
        entrada: j?.entrada_ts ?? null,
        entradaEsperadaHoy: esperado.trabaja ? esperado.entrada : null,
        salidaEsperadaHoy: esperado.trabaja ? esperado.salida : null,
        origenEsperadoHoy: esperado.origen,
        // Sin turnos u horarios no se sabe quién tiene turno explícito: todos parecerían
        // «sin turno» y se suavizaría una alarma que quizá corresponde. Ahí, la de siempre.
        feriadoSinTurnoHoy: esFeriadoSinTurno(feriadoHoy.esFeriado && !errTurnos && !errHorarios, esperado),
        salidaFinal: j?.salida_final_ts ?? null,
        minutosTarde: j?.minutos_tarde ?? null,
        salidaTemprana: salidaTempranaPorPersona.get(p.id) ?? null,
        enPausaSinRetorno: j?.tiene_salida_no_retornada ?? false,
        esOperativa: cuenta.operativa,
        esEncargada: cuenta.lider,
        ausenciaHoy: ausenciaPorPersona.get(p.id) ?? null,
      };
    });

    // Desde cuándo está en pausa cada quien: una consulta chica, solo de los que
    // la base ya marcó «en pausa». Va después del cálculo de arriba porque hace
    // falta saber QUIÉNES son. Si falla, las filas quedan sin hora —no se
    // esconden— y `pausasNoRespondieron` lo avisa.
    const { porPersona: pausas, fallo: fallaronPausas } = await traerPausasAbiertas(
      supabase,
      resultado.filter((f) => enPausaAhora(f.estado)).map((f) => f.personaId),
      hoy,
    );
    setPausasNoRespondieron(fallaronPausas);

    // Sedes, metas y «los horarios llegaron» se guardan JUNTO a `filas`, no antes del `await`
    // de arriba: la pantalla los cruza (una sede sin turnos, con o sin meta, sale de las tres
    // cosas), y con una consulta de pausas en medio pintaba un instante metas y horarios de
    // este ciclo con las filas del anterior —todas sin horario tras un ciclo caído: «Sin
    // turnos» de una tienda que sí abre—. Revisión del 2026-09-20.
    setSedesActivas(sedesData ?? []);
    setMetasPorSede(metasNuevas);
    setMetasNoRespondieron(Boolean(errMetas));
    setHorarioEsperadoNoRespondio(Boolean(errTurnos || errHorarios));
    setFilas(resultado.map((f) => ({ ...f, pausa: pausas.get(f.personaId) ?? null })));
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
    // `etiqueta` es la única forma de decir una sede (packages/shared/src/sedes.ts):
    // «Taller · Lima» y «Tienda · Lima» no se pueden confundir; el código viaja
    // aparte porque es lo que las separa si dos comparten título.
    .map((s) => ({ sedeId: s.id, codigo: s.codigo, etiqueta: etiquetaDeSede(s) }))
    .filter((s) => !yo || esAdmin || s.sedeId === yo.sedeBaseId);

  // Cobertura de cada sede, calculada una sola vez y reutilizada para ordenar,
  // para el resumen global y para cada tarjeta.
  //
  // «Nadie tiene turno hoy» solo es un hecho si los turnos y horarios llegaron: si la
  // consulta falló, o aún no ha llegado nada, todas las filas vienen sin horario y eso
  // diría «hoy no abre» de una tienda que sí abre. Y «esta sede no tiene meta para hoy»
  // solo es un hecho si las metas llegaron. Sin ellos, cada sede se mide como siempre:
  // contra su meta.
  const horarioConocido = !horarioEsperadoNoRespondio && !metasNoRespondieron && !(cargando && filas.length === 0);
  const coberturaPorSede = new Map<string, CoberturaSede>();
  for (const s of sedesDeAlcance) {
    const deSede = filas.filter((f) => f.sedeId === s.sedeId);
    const meta = metasPorSede.get(s.sedeId) ?? { man: 0, tar: 0, enc: 0 };
    coberturaPorSede.set(s.sedeId, calcularCoberturaSede(deSede, meta, tramoTarde, ahoraDecimal, horarioConocido));
  }

  // Orden: primero la sede con cobertura insuficiente (decisión de la
  // auditoría de sep-2026 — antes solo importaba quién tenía más gente
  // trabajando). Empate se resuelve igual que antes: más gente trabajando
  // ahora, y si sigue empatado, alfabético.
  const sedes = [...sedesDeAlcance].sort((a, b) => {
    const ca = coberturaPorSede.get(a.sedeId)!;
    const cb = coberturaPorSede.get(b.sedeId)!;
    // Primero el rojo (falta gente que podría venir), luego el ámbar (una meta por
    // revisar en Turnos), luego las que operan sin novedad, y al final las que hoy no
    // abren: sin esto, una sede cerrada podía quedar ANTES de una que abre a las 10 y
    // aún no ha llegado nadie, porque las dos tienen 0 trabajando.
    const rango = (c: CoberturaSede) => (c.noAbreHoy ? 3 : c.gravedad === "alerta" ? 0 : c.gravedad === "revisar" ? 1 : 2);
    if (rango(ca) !== rango(cb)) return rango(ca) - rango(cb);
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
  // Solo las que les falta gente que SÍ podría venir: las de meta imposible no se
  // arreglan con asistencia, y contadas aquí dejarían este número en rojo todos los
  // días por un dato de Turnos. Esas van en «Requiere atención», en ámbar.
  const sedesBajoMinimo = sedes.filter((s) => coberturaPorSede.get(s.sedeId)!.gravedad === "alerta");
  // «Bajo la meta: 1» junto a cinco sedes se lee como «1 de 5»; un domingo son 1 de las
  // 2 que se miden. «Se miden» y no «con turnos» ni «que abren»: cuenta las sedes que NO
  // se apagaron (gris o ámbar), que es lo que puede estar bajo la meta. Una sede sin
  // horario cargado y con meta sigue midiéndose, aunque nadie tenga turno. Solo se dice
  // cuando alguna sede se apagó, para no repetir en un día normal lo evidente.
  const sedesQueSeMiden = sedes.filter((s) => { const c = coberturaPorSede.get(s.sedeId)!; return !(c.noAbreHoy || c.metaSinTurnos || c.feriadoSinConfirmar); }).length;
  const notaSedesQueSeMiden = sedesQueSeMiden === sedes.length
    ? undefined
    : sedesQueSeMiden === 0 ? "ninguna se mide hoy" : `de ${sedesQueSeMiden} que se ${sedesQueSeMiden === 1 ? "mide" : "miden"} hoy`;
  // `corto` es lo que cabe en el celular, donde los cuatro números van en una fila de
  // ~70 px cada uno. El `label` completo se sigue leyendo al tocar (encabezado del
  // detalle) y en el aria-label del botón: «Sin marcar» solo, sin «y ya les tocaba
  // entrar», es la frase que acusaría a quien aún no tenía que haber llegado.
  const resumen: { clave: ClaveResumen; label: string; corto: string; n: number; color: string; nota?: string; notaSuave?: boolean }[] = [
    {
      clave: "trabajando", label: "Trabajando ahora", corto: "Trabajando", n: personasDelResumen.trabajando.length,
      color: personasDelResumen.trabajando.length > 0 ? "text-verde" : "text-tinta",
      nota: enPausaTotal > 0 ? `y ${enPausaTotal} en pausa` : undefined,
    },
    { clave: "tardanzas", label: "Tardanzas hoy", corto: "Tardanzas", n: personasDelResumen.tardanzas.length, color: personasDelResumen.tardanzas.length > 0 ? "text-rojo" : "text-tinta" },
    // Tres frases distintas para lo mismo («sin marcar cuando ya debían», «sin
    // marcar y ya le tocaba», la insignia de la fila): ahora dicen lo mismo, con
    // verbo — «ya les tocaba entrar».
    { clave: "sin_marcar", label: "Sin marcar y ya les tocaba entrar", corto: "Sin marcar", n: personasDelResumen.sin_marcar.length, color: personasDelResumen.sin_marcar.length > 0 ? "text-rojo" : "text-verde" },
    // «Bajo la meta», no «bajo mínimo»: Turnos, los recuadros de cada sede y la
    // pastilla dicen «meta». «Mínimo» era una tercera palabra para lo mismo.
    { clave: "bajo_minimo", label: "Sedes bajo la meta", corto: "Bajo meta", n: sedesBajoMinimo.length, color: sedesBajoMinimo.length > 0 ? "text-rojo" : "text-verde", nota: notaSedesQueSeMiden, notaSuave: true },
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
    if (!coincideConFiltroDeEstado(f.estado, estadoFiltro)) return false;
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
  // Cada panel recibe de aquí su forma de colapsar, subir, bajar y ocultar. Las
  // reglas (qué no se puede ocultar) viven en tablero-preferencias.ts.
  const panelProps = (id: PanelId, titulo: string, frescura: string) => {
    const i = prefs.orden.indexOf(id);
    return {
      id, titulo, frescura, orden: i, personalizando,
      colapsado: prefs.colapsados[id] === true,
      alAlternar: () => setPrefsCrudas(alternarColapsado(prefs, id)),
      oculto: prefs.ocultos[id] === true,
      puedeOcultar: !PANELES_NO_OCULTABLES.includes(id),
      puedeSubir: i > 0, puedeBajar: i < prefs.orden.length - 1,
      alSubir: () => setPrefsCrudas(moverPanel(prefs, id, -1)),
      alBajar: () => setPrefsCrudas(moverPanel(prefs, id, 1)),
      alOcultar: () => setPrefsCrudas(alternarOculto(prefs, id)),
    };
  };
  const panelVisible = (id: PanelId) => personalizando || prefs.ocultos[id] !== true;
  const ausentesHoy = filas.filter((f) => f.ausenciaHoy).length;

  // Desde el detalle de "Sedes bajo la meta" a la tarjeta de esa sede. Primero se
  // quita el filtro de sede —si la tenía oculta, la tarjeta no existe— y se baja
  // en el cuadro siguiente, cuando React ya la pintó. Un <a href="#…"> saltaba
  // antes de eso y no llegaba a ningún lado.
  function irASede(codigo: string) {
    setSedeFiltro("todas");
    const destino = sedes.find((x) => x.codigo === codigo);
    if (destino) setSedesAbiertas((a) => ({ ...a, [destino.sedeId]: true }));
    if (prefs.colapsados.sedes) setPrefsCrudas(alternarColapsado(prefs, "sedes"));
    const suave = !window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    requestAnimationFrame(() =>
      document.getElementById(`sede-${codigo}`)?.scrollIntoView({ behavior: suave ? "smooth" : "auto", block: "start" }),
    );
  }

  // ---------- Requiere atención (cobertura + Disciplina, en un solo panel) ----------
  interface ItemAtencion { key: string; sede: string; texto: string; href?: string; accion?: string; tono: "critico" | "advertencia" }
  const itemsAtencion: ItemAtencion[] = [];
  for (const s of sedes) {
    const cob = coberturaPorSede.get(s.sedeId)!;
    if (cob.alertaSinEntrada) {
      itemsAtencion.push({
        key: `sin-entrada-${s.sedeId}`, sede: s.etiqueta.texto, tono: "critico", href: "/admin/incidencias", accion: "Ver incidencias",
        texto: `sin marcajes desde las ${horaAmPmDe(cob.alertaSinEntrada)} — nadie ha marcado entrada todavía`,
      });
    }
    if (cob.gravedad === "revisar") {
      // Faltan metas imposibles, o hay meta y nadie con turno (`metaSinTurnos`): no se pide
      // que venga nadie, se pide revisar el dato.
      itemsAtencion.push({
        key: `cobertura-${s.sedeId}`, sede: s.etiqueta.texto, tono: "advertencia", href: "/admin/turnos",
        // En un feriado sin confirmar no hay una meta que revisar: hay una pregunta, y si la
        // respuesta es «abre», lo que se hace es armar los turnos de hoy.
        accion: cob.feriadoSinConfirmar ? "Ver turnos" : "Revisar meta",
        texto: textoMetaPorRevisar(cob),
      });
    } else if (cob.faltanOp || cob.faltanEnc) {
      // «Hay N en pausa» porque «faltan 4 operativas» no dice si no vinieron o
      // si están en el refrigerio — y a la hora de almuerzo es lo segundo.
      // Y si la meta no se puede cumplir con el equipo que hay, se dice: sin eso,
      // «faltan 1 líder» parece que alguien no vino, y no es así.
      const imposibles = [
        cob.faltanOp ? causaMetaImposible("operativas", cob.metaOp, cob.equipoOperativas)?.resumen : undefined,
        cob.faltanEnc ? causaMetaImposible("lideres", cob.metaEnc, cob.equipoLideres)?.resumen : undefined,
      ].filter(Boolean);
      itemsAtencion.push({
        key: `cobertura-${s.sedeId}`, sede: s.etiqueta.texto, tono: "advertencia", href: "/admin/turnos", accion: "Ver turnos",
        texto: `faltan ${loQueFalta(cob)} en piso`
          + (cob.enPausa.length > 0 ? ` — hay ${cob.enPausa.length} en pausa` : "")
          + (imposibles.length > 0 ? ` — ${imposibles.join(" y ")}` : ""),
      });
    }
    if (cob.sinMarcarReal > 0) {
      itemsAtencion.push({
        key: `sinmarcar-${s.sedeId}`, sede: s.etiqueta.texto, tono: "advertencia", href: "/admin/correcciones", accion: "Corregir marcas",
        texto: textoSinMarcar(cob.sinMarcarReal),
      });
    }
  }
  if (discNoRespondio) {
    itemsAtencion.push({
      key: "disc", sede: "Disciplina", href: "/admin/disciplina", accion: "Ver disciplina", tono: "advertencia",
      texto: "el semáforo no respondió — no es que no haya nadie, es que no pudo mirar",
    });
  } else if (casosDisciplina > 0) {
    itemsAtencion.push({
      key: "disc", sede: "Disciplina", href: "/admin/disciplina", accion: "Ver disciplina", tono: "critico",
      texto: `${casosDisciplina} caso${casosDisciplina === 1 ? "" : "s"} requiere${casosDisciplina === 1 ? "" : "n"} revisión`
        + (sinCargoNoRespondio ? " (no se pudo comprobar memos sin cargo)" : ""),
    });
  } else if (sinCargoNoRespondio) {
    itemsAtencion.push({
      key: "disc", sede: "Disciplina", href: "/admin/disciplina", accion: "Ver disciplina", tono: "advertencia",
      texto: "no se pudo comprobar si hay memos entregados sin el cargo firmado",
    });
  }

  return (
    <div className="flex flex-1 flex-col">
      <main className="flex-1 p-4 sm:p-8">
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
                    {/* Celular: una línea («… · en vivo · 05:59 p. m.»). Los segundos y el «se
                        refresca cada 30s» siguen en el menú ⋯ y en el escritorio; la fecha se queda
                        siempre, por la razón de arriba. */}
                    <span className="hidden sm:inline">{fechaConDia(hoy)} · en vivo · actualizado {actualizado} · se refresca cada 30s</span>
                    <span className="sm:hidden">{fechaConDia(hoy)} · en vivo · {actualizado.replace(/^(\d{1,2}:\d{2}):\d{2}/, "$1")}</span>
                  </>
                )}
              </div>
              {/* Honesto sobre el alcance real de "en vivo": Disciplina y Contratos
                  no van en el mismo refresco de 30s (cambian una vez al día, no
                  cada medio minuto) — decirlo evita la promesa que el título de
                  arriba no cumple para esas dos franjas. */}
              <div className="mt-0.5 hidden text-taupe sm:block">Disciplina, memos y contratos se actualizan cada 5 minutos.</div>
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
            <>
            {/* Celular: «Personalizar» y «Ver en Google Sheets» pasan a un menú ⋯. Eran dos
                controles que compiten con el título y que casi nadie toca desde el teléfono
                (lo personalizado se guarda por navegador). El aviso de que Disciplina, memos y
                contratos se refrescan cada 5 min también vive aquí: el «en vivo» de arriba no
                los incluye y ese matiz no se pierde, solo se mueve. */}
            <div className="sm:hidden">
              <Menu trigger={({ abierto, alternar }) => (
                <button
                  type="button"
                  onClick={alternar}
                  aria-haspopup="menu"
                  aria-expanded={abierto}
                  aria-label="Más opciones"
                  className="flex size-10 items-center justify-center rounded-full border border-sand bg-papel text-xl leading-none text-tinta transition-colors hover:border-taupe/40 hover:bg-sand/50 active:scale-[0.97]"
                >
                  ⋯
                </button>
              )}>
                <MenuItem onClick={() => setPersonalizando((v) => !v)}>
                  {personalizando ? "Terminar de personalizar" : "Personalizar tablero"}
                </MenuItem>
                <a
                  href={URL_SHEET_ASISTENCIA}
                  target="_blank"
                  rel="noopener noreferrer"
                  role="menuitem"
                  className="block w-full px-3 py-2 text-left text-sm text-tinta transition-colors duration-150 hover:bg-sand/50 focus:bg-sand/50 focus:outline-none"
                >
                  Ver en Google Sheets ↗
                </a>
                <div className="mt-1 w-64 border-t border-sand px-3 py-2 text-xs text-taupe">
                  Esta pantalla se refresca cada 30 s. Disciplina, memos y contratos, cada 5 minutos.
                </div>
              </Menu>
            </div>
            <div className="hidden flex-wrap items-center gap-3 sm:flex">
              {prefs.alertasOcultas && (
                <span className="hidden xl:block">
                  <Boton variante="secundario" tamano="sm" onClick={() => setPrefsCrudas(alternarAlertas(prefs))}>
                    ⟨ Alertas
                    {itemsAtencion.some((it) => it.tono === "critico") && (
                      <span className="ml-1.5 rounded-full bg-rojo px-2 py-0.5 text-crema">{itemsAtencion.filter((it) => it.tono === "critico").length}</span>
                    )}
                  </Boton>
                </span>
              )}
              <Boton variante={personalizando ? "primario" : "secundario"} tamano="sm" aria-pressed={personalizando} onClick={() => setPersonalizando((v) => !v)}>
                {personalizando ? "Listo" : "Personalizar"}
              </Boton>
              <a
                href={URL_SHEET_ASISTENCIA}
                target="_blank"
                rel="noopener noreferrer"
                className="text-sm text-taupe underline underline-offset-4 transition-colors hover:text-tinta"
              >
                Ver en Google Sheets ↗
              </a>
            </div>
            </>
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
            {/* FILTROS. Celular: buscador + botón «Filtros» (la hoja vive en el componente).
                Desde 640 px, la caja de siempre. Comparten el mismo estado. */}
            <FiltrosCelular
              busqueda={busqueda}
              alBuscar={setBusqueda}
              sedes={sedes.map((s) => ({ codigo: s.codigo, texto: s.etiqueta.texto }))}
              sedeFiltro={sedeFiltro}
              alCambiarSede={setSedeFiltro}
              estadoFiltro={estadoFiltro}
              alCambiarEstado={setEstadoFiltro}
              soloAlertas={soloAlertas}
              alCambiarSoloAlertas={setSoloAlertas}
              alLimpiar={limpiarFiltros}
            />
            <div className="mb-6 hidden flex-wrap items-end gap-3 rounded-2xl border border-sand bg-papel p-4 sm:flex">
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
                  {sedes.map((s) => <option key={s.sedeId} value={s.codigo}>{s.etiqueta.texto}</option>)}
                </CampoSelect>
              )}
              <CampoSelect etiqueta="Estado" value={estadoFiltro} onChange={(e) => setEstadoFiltro(e.target.value)} className="min-w-36">
                <option value="todos">Todos</option>
                {OPCIONES_FILTRO_ESTADO.map((o) => <option key={o.valor} value={o.valor}>{o.etiqueta}</option>)}
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

            <div className={prefs.alertasOcultas ? "" : "xl:grid xl:grid-cols-[minmax(0,1fr)_20rem] xl:items-start xl:gap-6"}>
              {/* Los paneles van en una columna flex y se ordenan con `order`: el
                  contenido de cada uno se queda escrito donde está. */}
              <div className="flex min-w-0 flex-col">
                {itemsAtencion.length > 0 && (
                  <div style={{ order: -3 }} className="mb-4 sm:mb-6 xl:hidden">
                    <PanelAtencionBanner items={itemsAtencion} />
                  </div>
                )}
                {/* Celular: una fila que se desliza de lado (no se parte en tres líneas) y que va
                    DESPUÉS del resumen, no antes: lo primero son los números. `max-sm:order-1!`
                    gana al `order` en línea de aquí, y deja a los atajos entre el resumen (0) y las
                    sedes (1), que ya están en ese orden por defecto — si alguien reordena sus
                    paneles en «Personalizar», los atajos se quedan donde él los puso. */}
                <nav style={{ order: -2 }} aria-label="Atajos" className="mb-4 flex items-center gap-2 overflow-x-auto [scrollbar-width:none] max-sm:order-1! sm:mb-6 sm:flex-wrap sm:overflow-visible">
                  <span className="hidden text-xs text-taupe sm:inline">Atajos:</span>
                  {[
                    { href: "/admin/ausencias", texto: "Registrar ausencia" },
                    { href: "/admin/turnos", texto: "Ver turnos" },
                    esAdmin ? { href: "/admin/documentacion", texto: "Aprobar documentos" } : { href: "/admin/correcciones", texto: "Corregir marcas" },
                  ].map((a) => (
                    <Link key={a.href} href={a.href} className="shrink-0 whitespace-nowrap rounded-control border border-sand bg-papel px-3 py-1.5 text-sm font-medium text-tinta transition-colors hover:border-taupe">{a.texto}</Link>
                  ))}
                </nav>
                {personalizando && (
                  <div style={{ order: -1 }} className="mb-6 flex flex-wrap items-center justify-between gap-2 rounded-control border border-dashed border-pizarra bg-pizarra/10 px-3 py-2 text-sm">
                    <span><strong>Personalizar:</strong> reordena con ↑ ↓, oculta lo que no uses y agrega indicadores en «Resumen del día». Se guarda en este navegador.</span>
                    <Boton variante="enlace" tamano="sm" onClick={() => setPrefsCrudas(PREFERENCIAS_INICIALES)}>Restablecer diseño</Boton>
                  </div>
                )}

            {panelVisible("resumen") && (
              <PanelColapsable {...panelProps("resumen", "Resumen del día", "en vivo · cada 30 s")}>
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
            {/* Celular: esta fila solo aparece al «Personalizar» (menú ⋯). Es configuración del
                tablero, no información del día, y ocupaba una línea en cada visita. */}
            <div className={`mb-3 flex-wrap items-center gap-2 sm:flex ${personalizando ? "flex" : "hidden"}`} role="group" aria-label="Indicadores visibles">
              <span className="text-xs text-taupe">Indicadores:</span>
              <Filtro activo disabled tamano="sm" className="cursor-default">Asistencia</Filtro>
              {KPIS_EXTRA.map((k: KpiExtra) => {
                const activo = prefs.kpisExtra[k] === true;
                return (
                  <Filtro key={k} activo={activo} tamano="sm" onClick={() => setPrefsCrudas(alternarKpiExtra(prefs, k))}>
                    {activo ? "✓ " : "+ "}{k === "pendientes" ? "Pendientes de acción" : k === "personal" ? "Personal" : "Casos"}
                  </Filtro>
                );
              })}
            </div>
            {/* Celular: los cuatro números en UNA fila de ~75 px (antes un 2×2 de ~230 px), con
                la etiqueta corta. El 2×2 gastaba un cuarto de pantalla en cuatro cifras. */}
            <div className={resumenDetalle ? "mb-3" : "mb-4 sm:mb-6"}>
            <div className="grid grid-cols-4 gap-px overflow-hidden rounded-2xl border border-sand bg-sand">
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
                    className={`flex flex-col justify-start py-2 pr-1.5 pl-2.5 text-left transition-colors focus-visible:outline-offset-[-3px] disabled:cursor-default sm:px-5 sm:py-4 ${abierto ? "bg-hueso" : "bg-papel enabled:hover:bg-crema"}`}
                  >
                    {/* <span> y no <div>: dentro de un <button> HTML solo admite
                        contenido de frase. */}
                    <span className="flex items-start justify-between gap-2">
                      <span className={`font-serif text-[1.75rem] font-medium leading-none tabular-nums sm:text-4xl ${k.color}`}>{k.n}</span>
                      {k.n > 0 && (
                        <span aria-hidden className={`hidden text-xs sm:inline ${abierto ? "font-medium text-tinta" : "text-taupe"}`}>{abierto ? "Cerrar ↑" : "Ver ↓"}</span>
                      )}
                    </span>
                    <span className="mt-1 block text-[0.6875rem] leading-tight text-taupe sm:mt-2 sm:text-sm">
                      <span className="sm:hidden">{k.corto}</span>
                      <span className="hidden sm:inline">{k.label}</span>
                    </span>
                    {/* Ámbar es «mira esto»; la nota de cuántas sedes abren solo informa. */}
                    {k.nota && <span className={`mt-0.5 hidden text-xs sm:block ${k.notaSuave ? "text-taupe" : "font-medium text-ambar"}`}>{k.nota}</span>}
                  </button>
                );
              })}
            </div>
            {/* Las notas («y 2 en pausa», «de 3 que se miden hoy») no caben en una casilla de 70 px,
                pero son información que corrige una lectura: sin ellas, «Trabajando 4» en pleno
                refrigerio parece gente que no vino. En celular van en una línea bajo la fila,
                solo cuando existen. */}
            {resumen.some((k) => k.nota) && (
              <p className="mt-2 px-1 text-xs text-taupe sm:hidden">
                {resumen.filter((k) => k.nota).map((k) => `${k.label} ${k.nota}`).join(" · ")}
              </p>
            )}
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
                          <span><strong className="font-semibold">{s.etiqueta.texto}:</strong> faltan {loQueFalta(coberturaPorSede.get(s.sedeId)!)} en piso</span>
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

            {prefs.kpisExtra.personal && (
              <TarjetaInfo
                className="mt-3"
                titulo="Personal"
                accion={<Link href="/admin/equipo" className="text-xs text-taupe hover:underline">Equipo →</Link>}
              >
                <div className="grid grid-cols-3 gap-2">
                  <Cifra etiqueta="Equipo que marca asistencia" valor={filas.length} />
                  <Cifra etiqueta="Ausentes hoy" valor={ausentesHoy} />
                  <Cifra etiqueta="Contratos por vencer" valor={contratos.length} tono={contratos.length > 0 ? "advertencia" : undefined} />
                </div>
                <p className="mt-3 text-xs text-taupe">Cuenta a quien marca asistencia: no incluye recibos por honorarios ni sueldo fijo.</p>
              </TarjetaInfo>
            )}

            {prefs.kpisExtra.pendientes && (
              <TarjetaInfo
                className="mt-3"
                titulo="Pendientes de acción"
                accion={<Link href="/admin/bandeja" className="text-xs text-taupe hover:underline">Bandeja{pendientesBandeja.resumen ? ` · ${pendientesBandeja.resumen.total}` : ""} →</Link>}
              >
                {pendientesBandeja.fallo && !pendientesBandeja.resumen ? (
                  <p className="text-sm text-ambar">No se pudieron traer los pendientes de la Bandeja. Vuelve a cargar la pantalla.</p>
                ) : !pendientesBandeja.resumen ? (
                  <p className="text-sm text-taupe">Cargando pendientes…</p>
                ) : pendientesBandeja.resumen.total === 0 ? (
                  <p className="text-sm text-taupe">Nada pendiente en la Bandeja.</p>
                ) : (
                  <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                    {pendientesBandeja.resumen.porModulo.map((m) => (
                      <Cifra key={m.clave} href={m.ruta} etiqueta={m.etiqueta} valor={m.n} />
                    ))}
                    {pendientesBandeja.resumen.otros > 0 && (
                      <Cifra href="/admin/bandeja" etiqueta="Otros" valor={pendientesBandeja.resumen.otros} />
                    )}
                  </div>
                )}
                {(pendientesBandeja.incompleto || (pendientesBandeja.fallo && pendientesBandeja.resumen)) && (
                  <p className="mt-3 text-xs text-ambar">Alguna sección de la Bandeja no respondió: este número puede estar corto.</p>
                )}
              </TarjetaInfo>
            )}

            {prefs.kpisExtra.casos && (
              <TarjetaInfo
                className="mt-3"
                titulo="Casos"
                accion={<Link href="/admin/casos" className="text-xs text-taupe hover:underline">Casos →</Link>}
              >
                {casosResumen.fallo && !casosResumen.resumen ? (
                  <p className="text-sm text-ambar">No se pudo traer el resumen de casos. Vuelve a cargar la pantalla.</p>
                ) : !casosResumen.resumen ? (
                  <p className="text-sm text-taupe">Cargando casos…</p>
                ) : casosResumen.resumen.total === 0 ? (
                  <p className="text-sm text-taupe">Nada que gestionar en Casos en los últimos 6 meses.</p>
                ) : (
                  <>
                    <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                      <Cifra etiqueta="Últimos 6 meses" valor={casosResumen.resumen.total} />
                      <Cifra etiqueta="Abiertos ahora" valor={casosResumen.resumen.abiertos} />
                      <Cifra etiqueta="Con un plazo vencido" valor={casosResumen.resumen.vencidos} tono={casosResumen.resumen.vencidos > 0 ? "alerta" : undefined} />
                      <Cifra etiqueta="Cerrados" valor={casosResumen.resumen.cerrados} />
                    </div>

                    <div className="mt-4 grid gap-5 sm:grid-cols-2">
                      <div>
                        <span className="mb-2 block text-xs font-medium text-taupe">Por categoría</span>
                        <ul className="flex flex-col gap-2">
                          {casosResumen.resumen.porCategoria.map((c) => (
                            <li key={c.tipo}>
                              <div className="flex items-baseline justify-between gap-2 text-xs">
                                <span>{c.etiqueta}</span>
                                <span className="font-semibold tabular-nums">{c.total}</span>
                              </div>
                              <span aria-hidden className="mt-1 block h-1.5 overflow-hidden rounded-full bg-sand">
                                <span
                                  className="block h-full bg-taupe"
                                  style={{ width: `${Math.round((c.total / maxCategoriaCasos) * 100)}%` }}
                                />
                              </span>
                            </li>
                          ))}
                        </ul>
                      </div>
                      <div>
                        <span className="mb-2 block text-xs font-medium text-taupe">Por sede</span>
                        <ul className="flex flex-col">
                          {casosResumen.resumen.porSede.map((s) => (
                            <li key={s.sedeCodigo} className="flex items-center justify-between gap-2 border-t border-sand/60 py-1.5 text-xs first:border-t-0">
                              <span className="font-medium">{s.sedeCodigo}</span>
                              <span className="flex items-center gap-2 text-taupe">
                                {s.abiertos} abierto{s.abiertos === 1 ? "" : "s"}
                                {s.vencidos > 0 && (
                                  <Insignia variante="alerta" tamano="sm">{s.vencidos} vencido{s.vencidos === 1 ? "" : "s"}</Insignia>
                                )}
                              </span>
                            </li>
                          ))}
                        </ul>
                      </div>
                    </div>

                    <p className="mt-4 text-xs text-taupe">
                      Cuenta casos, no personas: nadie ve quién reportó desde este indicador.
                    </p>
                  </>
                )}
              </TarjetaInfo>
            )}
              </PanelColapsable>
            )}

            {panelVisible("sedes") && (
              <PanelColapsable {...panelProps("sedes", "Sedes", "en vivo · cada 30 s")}>
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

            {sedesMostradas.length > 0 && (
            <div className="overflow-hidden rounded-2xl border border-sand bg-papel">
            {sedesMostradas.map(({ sedeId, codigo, etiqueta }) => {
              const deSedeCompleta = filas.filter((f) => f.sedeId === sedeId);
              const deSedeMostrada = deSedeCompleta.filter(filaCoincideFiltros);
              const cob = coberturaPorSede.get(sedeId)!;
              // Un solo estado de la sede, del que salen la franja y la pastilla —
              // así no pueden decir cosas distintas. "Sede sin marcajes" también
              // es alerta aunque no tenga meta: nadie llegó y a alguien le tocaba.
              // «Sin cobertura que medir» y no «Sin meta hoy» cuando la sede no
              // tiene a nadie de un área operativa: lo segundo se lee como una tarea
              // pendiente, y en una sede de solo administración no hay nada que configurar.
              // «Sin turnos» (gris) es lo que dice una sede a la que hoy no le toca trabajar a
              // nadie y que tampoco tiene meta para hoy: ese día no se labora y no hay nada que
              // medir. Antes decía «Sin meta configurada», que pedía configurar algo que se
              // dejó en 0 a propósito (2026-09-20: tres sedes decían eso un domingo). Se dice
              // «sin turnos» y no «cerrada» porque es lo que el sistema sabe (la palabra la
              // eligió Felipe, y es la misma de Turnos: SEDE_SIN_TURNOS).
              // «Sin meta hoy» queda para quien SÍ tiene gente hoy y no tiene meta EN NINGÚN TRAMO
              // (una tienda que abre a las 14:00 tiene meta de tarde: por la mañana dice «Sin meta de
              // la mañana», que sí es cierto); y no dice
              // «configurada» porque en Turnos un 0 puesto a propósito y uno nunca tocado se ven
              // igual, y afirmar que falta configurar algo podía ser falso.
              // Con meta y sin turnos (`metaSinTurnos`) los datos se contradicen: ámbar, y se
              // arregla en Turnos — no es «falta gente», porque a nadie le tocaba venir.
              // «Fuera de horario» solo si hay una meta que de otro modo se leería roja:
              // en una sede sin meta el letrero no aporta, y cambiar de «Sin cobertura
              // que medir» a «Fuera de horario» según la hora sería ruido. Va después
              // de la alerta de «Sin marcajes»: si nadie marcó en todo el día, cerrar la
              // tienda no lo apaga.
              const hayMeta = !cob.sinMetaOp || !cob.sinMetaEnc;
              // Rojo solo si falta gente que podría venir, o nadie marcó en todo el día.
              // Una meta imposible es ámbar «Meta por revisar»: se arregla en Turnos.
              const estadoSede: { tono: TonoFranja; texto: string } =
                cob.gravedad === "alerta" || cob.alertaSinEntrada
                  ? { tono: "alerta", texto: cob.gravedad === "alerta" ? "Cobertura insuficiente" : "Sin marcajes" }
                  : cob.metaSinTurnos
                    ? { tono: "advertencia", texto: "Meta sin turnos" }
                    : cob.feriadoSinConfirmar
                      ? { tono: "advertencia", texto: "Feriado · ¿abre hoy?" }
                      : cob.gravedad === "revisar"
                        ? { tono: "advertencia", texto: "Meta por revisar" }
                        : cob.noAbreHoy
                          ? { tono: "neutral", texto: SEDE_SIN_TURNOS }
                          : cob.fueraDeHorario && hayMeta
                            ? { tono: "neutral", texto: "Fuera de horario" }
                            : cob.sinMetaOp && cob.sinMetaEnc
                              ? { tono: "neutral", texto: cob.equipoOperativas === 0 ? "Sin cobertura que medir" : cob.hayMetaHoy ? `Sin meta ${tramoLabel}` : "Sin meta hoy" }
                              : { tono: "positivo", texto: "Cobertura correcta" };
              const fueraDeHorarioVisible = cob.fueraDeHorario !== null && hayMeta;
              // «Sin horario» se apaga si la consulta de turnos u horarios falló: entonces
              // TODAS las filas llegan sin horario, y el aviso acusaría a cada quien que marcó.
              const aviso = {
                lider: textoLiderEnLasDosMetas(cob.lideresEnAmbasMetas),
                desglose: textoDesglose(cob.desgloseProgramadas),
                sinHorario: horarioEsperadoNoRespondio ? null : textoSinHorario(cob.marcaronSinHorario.map((f) => f.nombre)),
              };
              // Con la sede sin turnos, dos recuadros de «0 · sin meta» (o «0 / 1 · Falta 1» contra
              // una meta que nadie puede cubrir porque a nadie le toca) no informan: la fila y una
              // frase dicen lo que pasa.
              // «Apagada» = gris (`noAbreHoy`: sin turnos y sin meta, haya o no respuesta clara de
              // descanso: no hay nada que alarmar) o ámbar (`metaSinTurnos`: hay meta y la respuesta
              // clara es que nadie trabaja). Una sede sin turnos, con meta y SIN respuesta clara
              // —todos sin horario— no se apaga: sigue en rojo, y sus recuadros son la explicación
              // de ese rojo.
              // Y en un feriado sin confirmar (`feriadoSinConfirmar`) también: «0 / 2 · Faltan 2»
              // contra una meta de un día en que quizá la sede ni abre sería el mismo rojo que
              // esa pregunta viene a evitar.
              const apagada = cob.noAbreHoy || cob.metaSinTurnos || cob.feriadoSinConfirmar;
              const mostrarTileOperativas = !apagada && !(cob.equipoOperativas === 0 && cob.sinMetaOp);
              const mostrarTileLideres = !apagada && !(cob.equipoLideres === 0 && cob.sinMetaEnc);
              const causasMeta = [
                { quien: "Personal operativo", causa: causaMetaImposible("operativas", cob.metaOp, cob.equipoOperativas) },
                { quien: "Líderes", causa: causaMetaImposible("lideres", cob.metaEnc, cob.equipoLideres) },
              ].flatMap((c) => (c.causa ? [{ quien: c.quien, detalle: c.causa.detalle }] : []));

              const tablaVisible = hayFiltrosDeContenido || (detalleAbierto[sedeId] ?? false);
              // La lista es lo primero que se lee; la tarjeta completa se despliega. Con
              // un filtro de contenido activo se despliega sola: quien busca a alguien
              // no debería tener que abrir cada sede para encontrarla.
              const abierta = hayFiltrosDeContenido || (sedesAbiertas[sedeId] ?? false);
              // `pct` null = no hay meta contra qué llenar una barra: una barra vacía se lee como «0 %
              // cubierto», que es lo contrario de «no se mide». Y una sede que hoy no abre no dice
              // nada en esta columna: «0 trabajando ahora» es ruido donde a nadie le toca.
              const resumenCob: { texto: string; pct: number | null } | null = cob.noAbreHoy
                ? null
                : cob.metaSinTurnos
                  ? { texto: `Meta de ${metaDelDiaTexto(cob)} · sin turnos`, pct: null }
                  : cob.feriadoSinConfirmar
                    ? { texto: "Feriado · sin turnos armados", pct: null }
                  : !cob.sinMetaOp
                    ? { texto: `${cob.opPiso} / ${cob.metaOp} operativas`, pct: Math.min(100, Math.round((cob.opPiso / cob.metaOp) * 100)) }
                    : !cob.sinMetaEnc
                      ? { texto: `${cob.encPiso} / ${cob.metaEnc} líderes`, pct: Math.min(100, Math.round((cob.encPiso / cob.metaEnc) * 100)) }
                      : { texto: `${cob.trabajando.length} trabajando ahora`, pct: null };
              const colorBarra = estadoSede.tono === "alerta" ? "bg-rojo" : estadoSede.tono === "advertencia" ? "bg-ambar" : estadoSede.tono === "positivo" ? "bg-verde" : "bg-taupe/40";
              const tardanzasSede = deSedeCompleta.filter(llegoTarde).length;

              return (
                <section key={sedeId} id={`sede-${codigo}`} className="scroll-mt-24 border-t border-sand first:border-t-0">
                  <button
                    type="button"
                    onClick={() => setSedesAbiertas((a) => ({ ...a, [sedeId]: !(a[sedeId] ?? false) }))}
                    aria-expanded={abierta}
                    aria-controls={`sede-${codigo}-detalle`}
                    className={`relative block w-full px-4 py-3 text-left transition-colors sm:grid sm:grid-cols-[minmax(0,1.5fr)_minmax(0,1fr)_auto_auto] sm:items-center sm:gap-x-4 sm:gap-y-2 sm:px-5 ${cob.noAbreHoy ? "bg-hueso/40 hover:bg-hueso/70" : "hover:bg-hueso/60"}`}
                  >
                    {/* CELULAR. Franja de color a la izquierda (rojo/ámbar/verde se lee antes que
                        cualquier palabra), y debajo, en este orden: nombre, el estado COMPLETO en su
                        pastilla, cuánta gente hay contra la meta, y a quién le tocaba hoy. Antes el
                        nombre se partía en tres líneas («Tienda · / Trujillo / (TRU)») y la pastilla
                        quedaba apretada contra la flecha: el mismo grid de escritorio, estrechado.
                        La franja nunca va sola: el estado está dicho también en texto. */}
                    <span className="sm:hidden">
                      <Franja tono={estadoSede.tono} />
                      <span className="flex items-center justify-between gap-3">
                        <span className="min-w-0">
                          <span className={cob.noAbreHoy ? "font-medium text-taupe" : "font-semibold"}>{etiqueta.titulo}</span>{" "}
                          <span className="text-xs text-taupe">({codigo})</span>
                        </span>
                        <span aria-hidden className="text-taupe">{abierta ? "▴" : "▾"}</span>
                      </span>
                      <span className="mt-1.5 block">
                        <Insignia variante={estadoSede.tono} atenuada={estadoSede.tono === "neutral"} className="px-3 py-1 font-semibold">{estadoSede.texto}</Insignia>
                      </span>
                      {resumenCob && (
                        <span className="mt-2 block">
                          <span className="text-sm">{resumenCob.texto}{cob.enPausa.length > 0 && <span className="text-ambar"> · {cob.enPausa.length} en pausa</span>}</span>
                          {resumenCob.pct !== null && (
                            <span aria-hidden className="mt-1 block h-1.5 overflow-hidden rounded-full bg-sand"><span className={`block h-full ${colorBarra}`} style={{ width: `${resumenCob.pct}%` }} /></span>
                          )}
                        </span>
                      )}
                      <span className="mt-1.5 block text-xs text-taupe">{textoEquipoDelDia(cob.programadosHoy, deSedeCompleta.length, cob.feriadoSinConfirmar)}</span>
                    </span>

                    {/* ESCRITORIO: las cuatro columnas de siempre. `contents` hace que sus hijos
                        sean las celdas del grid del botón. */}
                    <span className="hidden sm:contents">
                    <span className="min-w-0">
                      {/* Una sede que hoy no abre baja de volumen: nombre sin negrita y en taupe, sobre
                          el fondo «hundido» (hueso). Menos tinta, no menos contraste: sigue siendo texto
                          taupe legible, el mismo de todo lo secundario de esta pantalla. */}
                      <span className={cob.noAbreHoy ? "font-medium text-taupe" : "font-semibold"}>{etiqueta.titulo}</span>{" "}
                      <span className="text-xs text-taupe">({codigo})</span>
                      <span className="block text-xs text-taupe">{textoEquipoDelDia(cob.programadosHoy, deSedeCompleta.length, cob.feriadoSinConfirmar)}</span>
                    </span>
                    {resumenCob ? (
                      <span>
                        <span className="text-sm">{resumenCob.texto}{cob.enPausa.length > 0 && <span className="text-ambar"> · {cob.enPausa.length} en pausa</span>}</span>
                        {resumenCob.pct !== null && (
                          <span aria-hidden className="mt-1 block h-1.5 overflow-hidden rounded-full bg-sand"><span className={`block h-full ${colorBarra}`} style={{ width: `${resumenCob.pct}%` }} /></span>
                        )}
                      </span>
                    ) : (
                      // Sin contenido, pero la celda queda en la cuadrícula para que la pastilla siga
                      // alineada con la de las otras filas.
                      <span aria-hidden />
                    )}
                    <span>
                      {tardanzasSede > 0
                        ? <Insignia variante="alerta">{tardanzasSede} tarde</Insignia>
                        // «sin tardanzas» confirma algo cuando había quién llegara tarde; en una sede sin turnos nadie podía.
                        : !apagada && <span className="text-xs text-taupe">sin tardanzas</span>}
                    </span>
                    <span className="flex items-center gap-2">
                      <Insignia variante={estadoSede.tono} atenuada={estadoSede.tono === "neutral"} className="px-3 py-1 font-semibold">{estadoSede.texto}</Insignia>
                      <span aria-hidden className="text-taupe">{abierta ? "▴" : "▾"}</span>
                    </span>
                    </span>
                  </button>
                  {abierta && (
                  <div id={`sede-${codigo}-detalle`} className="border-t border-dashed border-sand bg-hueso/40 px-4 py-3 sm:px-5 sm:py-4 sm:pl-6">
                  {/* La frase «a N de las M personas les tocaba» vive en la fila, que siempre está a la
                      vista: repetirla al abrir el detalle era decir lo mismo dos veces seguidas. */}
                  {/* Quien marcó sin horario no entra en «les tocaba a N»: sin esta línea,
                      la cuenta de arriba dice 10 de 12 cuando trabajaron 11. */}
                  {aviso.sinHorario && <p className="mb-4 text-xs text-ambar">{aviso.sinHorario}</p>}

                  {/* Por qué la fila está en gris o en ámbar: sin esto, quien no sabe qué es «Sin turnos»
                      tendría que adivinarlo. Dice los dos lados y dónde se arregla. */}
                  {cob.noAbreHoy && (
                    <p className="mb-4 text-xs text-taupe">
                      Hoy no hay nada que medir: nadie tiene turno y esta sede no tiene meta para este día. La meta de cada día se define en Turnos.
                    </p>
                  )}
                  {cob.metaSinTurnos && (
                    <p className="mb-4 text-xs text-taupe">
                      <strong className="font-semibold text-tinta">Meta sin turnos:</strong> {textoMetaSinTurnos(cob)}. {esAdmin
                        ? <>Si esta sede no abre los {diaDeLaSemanaEnPlural(hoy)}, pon en 0 su meta de ese día en Turnos: vale para todos los {diaDeLaSemanaEnPlural(hoy)}. Si abre, arma sus turnos.</>
                        : <>Si esta sede no abre los {diaDeLaSemanaEnPlural(hoy)}, pídele a un administrador que ponga en 0 su meta de ese día: vale para todos los {diaDeLaSemanaEnPlural(hoy)}. Si abre, arma sus turnos.</>}
                    </p>
                  )}

                  {/* El feriado sin confirmar es una PREGUNTA, no una alarma: ámbar, y dice las dos
                      salidas. El rojo de abajo queda para lo que sí es una falla. */}
                  {cob.feriadoSinConfirmar && (
                    <div className="mb-4 rounded-2xl border border-ambar/60 bg-ambar/[0.06] px-5 py-3 text-sm text-tinta">
                      <strong className="font-semibold">Feriado:</strong> nadie de esta sede ha marcado todavía y hoy no hay turnos armados, así que no se sabe si abre.
                      Si abre, arma sus turnos de hoy en Turnos; si hoy cierra, no hace falta hacer nada.
                    </div>
                  )}

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
                  {/* Un tile que dice «0 · sin meta» en una sede donde ese grupo no
                      existe no informa nada, y en Central (solo administración) se
                      leía como que algo estaba sin configurar. Se muestra solo si
                      hay meta, o si hay gente que la pueda cubrir. */}
                  {(mostrarTileOperativas || mostrarTileLideres) && (
                    <div className={`mb-4 grid gap-3 sm:max-w-md ${mostrarTileOperativas && mostrarTileLideres ? "grid-cols-2" : "grid-cols-1 sm:max-w-[13.5rem]"}`}>
                      {mostrarTileOperativas && (
                        <TileCobertura label="Personal operativo en piso" n={cob.opPiso} meta={cob.metaOp} sinMeta={cob.sinMetaOp} tramo={tramoLabel} fueraDeHorario={fueraDeHorarioVisible} porRevisar={cob.metaOpImposible} />
                      )}
                      {mostrarTileLideres && (
                        <TileCobertura label="Líderes en piso" n={cob.encPiso} meta={cob.metaEnc} sinMeta={cob.sinMetaEnc} fueraDeHorario={fueraDeHorarioVisible} porRevisar={cob.metaEncImposible} />
                      )}
                    </div>
                  )}
                  {/* Por qué los recuadros están apagados: sin esto, un gris sin
                      explicación se lee como un dato que falta. */}
                  {fueraDeHorarioVisible && cob.fueraDeHorario && (
                    <p className="mb-4 text-xs text-taupe">
                      {textoFueraDeHorario(cob.fueraDeHorario, horaAmPmDe(cob.fueraDeHorario.hora))}
                    </p>
                  )}
                  {/* Una líder de tienda es de un área operativa Y líder: los dos
                      recuadros pueden sumar más que la gente que hay en piso. */}
                  {aviso.lider && mostrarTileOperativas && mostrarTileLideres && (
                    <p className="mb-4 text-xs text-taupe">{aviso.lider}</p>
                  )}
                  {/* Por qué una meta no se puede cumplir por más gente que venga:
                      no cambia el color —ver causaMetaImposible— pero dice qué arreglar. */}
                  {causasMeta.map((c) => (
                    <p key={c.quien} className="mb-4 text-xs text-taupe">
                      <strong className="font-semibold text-tinta">{c.quien}:</strong> {c.detalle}
                    </p>
                  ))}

                  {/* Recuadro verde claro de "Trabajando ahora": estuvo desde julio y
                      el commit 8aae5710 (15-sep) lo cambió por una línea de texto
                      suelta. Era lo que se buscaba primero al abrir la pantalla, así
                      que vuelve. Sin nadie trabajando no se pinta de verde: verde es
                      "hay gente en piso", y un recuadro verde que dice "nadie"
                      afirmaría lo contrario de lo que escribe. Al 15% y no al 6% de
                      antes: es el mismo relleno de la insignia "Trabajando", y con el
                      verde retonado el 2026-09-06 el 6% ya se leía gris. La etiqueta
                      verde encima da 5.27:1 claro y 4.91:1 oscuro. */}
                  {/* Sin turnos hoy nadie marcó, así que este recuadro diría siempre «0 · Nadie está trabajando». */}
                  {!apagada && (
                  <div
                    className={`mb-4 rounded-superficie border px-4 py-3 ${cob.trabajando.length > 0 ? "border-verde/30 bg-verde/15" : "border-sand bg-crema"}`}
                  >
                    <div className={`etiqueta ${cob.trabajando.length > 0 ? "text-verde" : "text-taupe"}`}>Trabajando ahora · {cob.trabajando.length}</div>
                    <div className="mt-2 flex flex-wrap gap-2">
                      {cob.trabajando.length === 0 ? (
                        // Un 0 en piso es igual de 0 en un cambio de turno, tras el cierre o con
                        // una falta real: el desglose dice cuál de los tres. Reemplaza a «Nadie
                        // está trabajando», que repetía por tercera vez el 0 que ya dicen el
                        // título de la sede y la etiqueta de este recuadro.
                        <span className="text-sm text-taupe">{aviso.desglose ?? "Nadie está trabajando en este momento."}</span>
                      ) : (
                        // Pastillas en papel sobre el verde, como antes.
                        cob.trabajando.map((f) => (
                          <Link
                            key={f.personaId}
                            href={linkCorregir(f.personaId)}
                            title={`Ver el día de ${f.nombre} en Correcciones`}
                            className="inline-flex items-center gap-2 rounded-full border border-verde/25 bg-papel px-3 py-1 text-sm transition-colors hover:border-verde hover:bg-verde/15"
                          >
                            <span aria-hidden className="size-1.5 rounded-full bg-verde" />
                            {f.nombre}
                          </Link>
                        ))
                      )}
                    </div>
                  </div>
                  )}

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
                      {/* Quien lleva más tiempo fuera va primero: es a quien hay que
                          mirar. Cada quien dice desde cuándo y cuánto lleva —un
                          refrigerio de 40 minutos se ve distinto de un retorno que
                          nadie marcó hace tres horas—; sin dato, solo el nombre. */}
                      <div className="mt-2 flex flex-wrap gap-2">
                        {[...cob.enPausa].sort(porPausaMasLarga).map((f) => (
                          <Link
                            key={f.personaId}
                            href={linkCorregir(f.personaId)}
                            title={`Ver el día de ${f.nombre} en Correcciones`}
                            className="inline-flex items-start gap-2 rounded-superficie border border-ambar/45 bg-papel px-3 py-1.5 text-sm transition-colors hover:border-ambar hover:bg-ambar/15"
                          >
                            <span aria-hidden className="mt-1.5 size-1.5 shrink-0 rounded-full bg-ambar" />
                            <span>
                              {f.nombre}
                              {f.pausa && (
                                <span className="block text-xs text-taupe">
                                  {/* La duración no se parte: en celular «3h 20m» quedaba como «3h» / «20m». */}
                                  {textoPausaDesde(f.pausa)} · <span className="whitespace-nowrap">{formatoMinutos(minutosDesde(f.pausa.desde))}</span>
                                </span>
                              )}
                            </span>
                          </Link>
                        ))}
                      </div>
                      {pausasNoRespondieron && (
                        <p className="mt-2 text-xs text-ambar">No se pudo comprobar desde cuándo están en pausa.</p>
                      )}
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
                      {/* «del equipo», como la frase de arriba («10 de las 12 personas del
                          equipo»): el detalle lista a todo el equipo, no solo a quien le tocaba hoy. */}
                      Ver detalle ↓ ({deSedeCompleta.length} persona{deSedeCompleta.length === 1 ? "" : "s"} del equipo)
                    </Boton>
                  )}
                  </div>
                  )}
                </section>
              );
            })}
            </div>
            )}
              </PanelColapsable>
            )}

            {/* QUIÉN RESPONDIÓ SU MEMO (0404). Aparte del panel de arriba porque
                no es un plazo legal corriendo — es informativo: alguien ya vio su
                documento y dejó una constancia digital, firmando o prefiriendo no
                hacerlo. Ninguna de las dos reemplaza el trámite físico. */}
            {respuestasMemo.length > 0 && panelVisible("memos") && (
              <PanelColapsable {...panelProps("memos", "Respuestas a memos", "se actualiza cada 5 min")}>
              <div className="rounded-2xl border border-sand bg-papel p-5 pl-6">
                <div className="mb-2 flex items-center justify-between">
                  <span className="text-xs text-taupe">Últimos {DIAS_RESPUESTAS_MEMO} días</span>
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
              </PanelColapsable>
            )}

            {/* CONTRATOS A PLAZO FIJO. Dos grupos, y el importante es el primero:
                quien ya venció y sigue figurando activo. Ese caso no se nota en
                ninguna otra pantalla —la persona aparece normal en asistencia, en
                planilla y en provisiones— y desde la 0162 tampoco en el tablero de
                Documentación. Sin esta franja, la fecha anotada en Equipo solo sirve
                si alguien se acuerda de ir a buscarla. */}
            {(contratosNoRespondio || contratos.length > 0) && panelVisible("contratos") && (
              <PanelColapsable {...panelProps("contratos", "Contratos a plazo fijo", "se actualiza cada 5 min")}>
              {(() => {
              // Igual que Disciplina: si la RPC no contestó, la franja NO se
              // calla — dice que no pudo mirar, en vez de parecer un mes tranquilo.
              if (contratosNoRespondio) {
                return (
                  <section className="rounded-2xl border border-ambar/30 bg-ambar/[0.06] p-5">
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
                <div className="relative overflow-hidden rounded-2xl border border-sand bg-papel p-5 pl-6">
                  {/* Rojo si alguien ya pasó su fecha (el art. 77 ya corrió);
                      ámbar si solo se acerca. */}
                  <Franja tono={vencidos.length > 0 ? "alerta" : "advertencia"} />
                  <div className="mb-2 flex items-center justify-between">
                    <span />
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
              </PanelColapsable>
            )}
              </div>

              {!prefs.alertasOcultas && (
                <aside className="hidden xl:sticky xl:top-4 xl:block">
                  <PanelAtencionLateral items={itemsAtencion} alOcultar={() => setPrefsCrudas(alternarAlertas(prefs))} />
                </aside>
              )}
            </div>
          </>
        )}
      </main>
    </div>
  );
}

"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { useRolActual } from "@/lib/admin/use-rol";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { Cargando } from "@/components/cargando";
import { AreaTexto } from "@/components/ui/area-texto";
import { AyudaPantalla } from "@/components/ui/ayuda-pantalla";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Boton } from "@/components/ui/boton";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { EstadoVacio } from "@/components/ui/estado-vacio";
import { ParaAtender } from "@/components/ui/para-atender";
import { Pestanas } from "@/components/ui/pestanas";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { bandaDe, ORDEN_BANDAS, racimoDeVencimientos, TEXTO_BANDA, type Banda } from "@/lib/admin/contratos-bandas";
import { sobretituloDeHoy } from "@/lib/admin/sobretitulo";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { Modal } from "@/components/ui/modal";
import { BotonIcono } from "@/components/ui/boton-icono";
import { Insignia } from "@/components/ui/insignia";
import { Menu, MenuItem } from "@/components/ui/menu";
import { ChevronDown, ChevronUp, Eye, EyeOff } from "lucide-react";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { vigentesAl } from "@/lib/admin/parametro-vigente";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import { abrirArchivoFirmado } from "@/lib/abrir-archivo-firmado";
import { useToast } from "@/components/toast";
import { hoyLima, maximoSemanalPracticante, puedeEstamparFirmaDeEmpresa, puedeGestionarContratos } from "@cayla-dynamic/shared";
import {
  construirContrato,
  formatearFecha,
  ACTIVOS_PRINCIPALES_POR_SEDE,
  FUNCIONES_PLACEHOLDER,
  MARCADOR_FIRMA_EMPRESA,
  MARCADOR_FIRMA_PERSONA,
  tipoQueCorresponde,
  type DatosContrato,
} from "@/lib/admin/contrato-texto";

// Generador de contratos: se elige a la persona, el sistema jala lo que ya
// sabe de ella (DNI, sueldo vigente, horario, sede) y arma el contrato
// completo — listo para imprimir y firmar en físico.
//
// Es la pieza que docs/estado.md ya listaba como pendiente: "Generador de
// contratos — los tres conceptos [movilidad, educación, bono] tienen que
// estar en el contrato de trabajo | nada, pero no existe la pieza."
//
// El texto se persiste en `contratos_generados.documento_html` en el momento
// de generarse (borrador, sin firma) — antes de que exista el escaneo, no
// después — para que quede constancia de qué se imprimió aunque pasen días
// hasta que se firme. Ver migración 0272 y apps/web/lib/admin/contrato-texto.ts.
//
// LA JORNADA SIEMPRE ES DE 48 HORAS, NUNCA UN NÚMERO CALCULADO DEL HORARIO.
// Decisión de Felipe (2026-08-19): el horario real (hoy 45h en varias sedes)
// es una disposición voluntaria y ajustable de la empresa, no un tope legal —
// el contrato declara el máximo que la ley permite y que CAYLA se reserva el
// derecho de usar, igual que ya mide el sobretiempo `fn_planilla_calcular`
// (contra 48h fijas, nunca contra el horario nominal de cada quien). Por eso
// esta pantalla no lee `horarios_asignados` ni compara contra
// `horas_semana_objetivo`: esa comparación no alimentaba nada del contrato y
// Felipe la encontró más ruidosa que útil.

// Quién firma por CAYLA NO se escribe acá. Vive en `configuracion.firmante_empresa`
// (0147), validado por trigger: tiene que ser una persona activa con rol admin o
// lider_do. Antes estaban el nombre y el DNI de Felipe escritos a mano en este
// archivo — exactamente el tipo de dato que este repositorio prohíbe hardcodear:
// el día que firme otra persona, el contrato saldría con el nombre equivocado y
// nadie se enteraría hasta verlo impreso.
const FIRMANTE_POR_DEFECTO = { nombre: "", dni: "", cargo: "Gerencia General" };

const MAX_BYTES = 50 * 1024 * 1024;

// "2026-07-28" + 1 → "2026-07-29" (aritmética en UTC: sin sorpresas de zona)
// "Proyecto ERP\n" → "Proyecto ERP"; "a\n\n  b" → "a b". Para lo que se imprime
// dentro de una frase: ahí un salto de línea no significa nada y solo estorba.
function unaLinea(texto: string): string {
  return texto.replace(/\s+/g, " ").trim();
}

// Buscar «Gutierrez» tiene que encontrar a «Gutiérrez»: quien escribe con prisa
// no pone la tilde, y media plantilla lleva una en el apellido. Mismo
// normalizador que /admin/horas y que el buscador global.
function sinTildes(t: string): string {
  return t.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase();
}

function sumarDias(iso: string, n: number): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

// "2026-09-04" + 3 meses → "2026-12-03": el día anterior al aniversario, que es
// como se cuenta un plazo de contrato (del 4 de setiembre al 3 de diciembre).
function finDePlazo(inicioIso: string, meses: number): string {
  const [y, m, d] = inicioIso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1 + meses, d - 1)).toISOString().slice(0, 10);
}

/**
 * El mismo tope que ya calcula `fn_contratos_tablero` (0336) para una
 * practicante: `fecha_ingreso + 12 meses` exactos — NO "el día antes del
 * aniversario" (esa cuenta es `finDePlazo`, para el plazo de un contrato, otra
 * pregunta). Se repite acá, con la misma fórmula, para que el aviso que ve
 * quien está eligiendo la fecha de fin diga lo mismo que el tablero va a decir
 * después: medido desde el ingreso real, no desde el inicio de ESTE convenio
 * (0336 decidió con Felipe no sumar convenios anteriores: la practicante es
 * continua desde que ingresó, no entra y sale del estatus).
 */
function topeConvenioDoceMeses(fechaIngresoIso: string): string {
  const [y, m, d] = fechaIngresoIso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1 + 12, d)).toISOString().slice(0, 10);
}

// ── ¿Se pisan dos periodos? ─────────────────────────────────────────────────
// Un documento sin fecha de fin —el indefinido— no termina nunca, así que se
// compara contra un tope imposible. Las fechas ISO se ordenan igual como texto
// que como fecha, así que basta comparar cadenas.
//
// ESTA REGLA VIVE DOS VECES, y a propósito: acá para AVISAR antes de que
// alguien llene ocho campos, y dentro de `fn_contrato_registrar` /
// `fn_contrato_editar` (migración 0388), que son las que de verdad mandan —
// esta pantalla no es la única puerta a esa función. Si cambia una, cambia la
// otra: el mismo trato que `jornada-esperada.ts` tiene con
// `fn_recalcular_jornada`.
const SIN_FIN = "9999-12-31";
function seSolapan(aIni: string, aFin: string | null, bIni: string, bFin: string | null): boolean {
  return aIni <= (bFin ?? SIN_FIN) && bIni <= (aFin ?? SIN_FIN);
}

/**
 * Lo que se tecleó en el formulario, tal cual, para poder volver a abrirlo.
 *
 * `documento_html` guarda el RESULTADO —el papel que se imprime—, no las
 * respuestas que lo produjeron: la causa objetiva, las funciones, los cinco
 * datos del centro de formación, el Anexo I. Sin esta foto, «editar»
 * obligaría a reescribir veinte campos para corregir una fecha, y nadie
 * corrige una fecha a ese precio: volvería a generar otro documento, que es
 * justo el duplicado que esta migración viene a impedir.
 *
 * Nace con la 0388, así que un borrador anterior la tiene en null — la
 * pantalla lo dice al abrirlo en vez de fingir que los textos son los suyos.
 */
// `type` y no `interface` a propósito: solo un alias de tipo recibe la firma
// de índice implícita que `Json` exige, y sin ella esto no se puede mandar
// como parámetro jsonb a la función.
type DatosFormulario = {
  cargo: string;
  ciudad: string;
  causa: string;
  funciones: string;
  activosLibre: string;
  sinActivosAdicionales: boolean;
  adendum: string;
  modalidadManual: string;
  // Solo preprofesional (auditoría 2026-09-14, hallazgo #1): cuántas horas
  // semanales se pactaron, cuando son MENOS que el tope de 30h de su
  // modalidad. "" = a la jornada completa de su modalidad (30h) — el mismo
  // comportamiento que tenía el sistema antes de que este campo existiera.
  horasSemanalesConvenio: string;
  planCapacitacion: string;
  centroFormacionNombre: string;
  centroFormacionRuc: string;
  centroFormacionDomicilio: string;
  centroFormacionRepresentanteNombre: string;
  centroFormacionRepresentanteCargo: string;
  carreraEspecialidad: string;
  cicloAcademico: string;
  gradoTituloTexto: string;
  areaProyecto: string;
  objetivoFormativoGeneral: string;
  supervisorAsignado: string;
};

interface Persona {
  id: string;
  nombres: string;
  apellidos: string;
  documento: string | null;
  cargo: string | null;
  sede_base_id: string | null;
  // Dónde trabaja de verdad. La movilidad se paga por acá y no por la sede
  // base (0166), así que el contrato tiene que decir la misma tarifa que la
  // boleta: si no, el papel promete un monto y la planilla paga otro.
  sede_fisica_id: string | null;
  email: string | null;
  fecha_ingreso: string;
  fecha_fin_contrato: string | null;
  cobra_movilidad: boolean;
  // Las dos exclusiones que la planilla sí respeta y el contrato no miraba.
  personal_direccion: boolean;
  sueldo_fijo: boolean;
  // Decide qué documento le corresponde (0333): planilla/prueba generan un
  // contrato de trabajo, practicante genera un convenio de modalidad
  // formativa. `en_planilla` es la columna generada — no se recalcula acá.
  en_planilla: boolean;
  tipo_vinculo: string;
  // Solo tiene sentido con tipo_vinculo='practicante' (0324): decide 30h/48h.
  practicante_modalidad: string | null;
}
interface Sede {
  id: string;
  nombre: string;
  codigo: string;
  ciudad: string | null;
}
interface DatoPersonal {
  persona_id: string;
  nombre_dni: string | null;
  direccion: string | null;
  genero: string | null;
}
interface Salario {
  persona_id: string;
  salario_mensual_soles: number;
}
interface Parametro {
  clave: string;
  valor: number;
  sede_codigo: string | null;
  vigente_desde: string;
  vigente_hasta: string | null;
}
interface ContratoFila {
  id: string;
  persona_id: string;
  persona: string;
  tipo: string;
  cargo: string;
  sede: string | null;
  remuneracion_mensual: number;
  fecha_inicio: string;
  // NULL cuando tipo="indefinido" (0347): ese documento no tiene fecha de término.
  fecha_fin: string | null;
  horas_semanales: number | null;
  generado_at: string;
  storage_path: string | null;
  fecha_firma: string | null;
  generado_por: string | null;
  copia_entregada_at: string | null;
  comunicado_mtpe_at: string | null;
  anulado_at: string | null;
  anulado_motivo: string | null;
  // Un borrador se puede corregir en su sitio (0388). Que se corrigió, y quién,
  // no se deduce: se anota, como todo lo que toca un documento que se firma.
  editado_at: string | null;
  editado_por: string | null;
  vigente: boolean;
  // Confirmación digital del colaborador (0402) — distinta de `fecha_firma`,
  // que sigue siendo el escaneado físico. Null = todavía no confirmó.
  firma_persona_confirmada_at: string | null;
}

interface FilaTablero {
  persona_id: string;
  persona: string;
  sede: string | null;
  fecha_fin_contrato: string | null;
  dias_restantes: number | null;
  contrato_id: string | null;
  tipo: string | null;
  fecha_firma: string | null;
  copia_entregada_at: string | null;
  comunicado_mtpe_at: string | null;
  copia_vence: string | null;
  mtpe_vence: string | null;
  dias_marcados_despues: number;
  estado: string;
}

/** Cómo se dice cada tipo en pantalla. En la base son «nuevo»/«renovacion». */
const TIPO_CONTRATO: Record<string, string> = {
  nuevo: "Nuevo ingreso",
  renovacion: "Renovación",
  adendum: "Adendum",
  convenio_practicas: "Convenio de prácticas",
  indefinido: "Indefinido",
};

/** El orden en que se ofrecen las tarjetas del paso 1 — el mismo que ya
 * traía el `<select>` de "Tipo" antes del rediseño, con "Renovación" primero
 * porque es el caso más frecuente (es también el valor inicial de `tipo`). */
const ORDEN_TIPOS = ["renovacion", "nuevo", "indefinido", "convenio_practicas", "adendum"] as const;

/** Una frase que explica cada tarjeta de tipo, para elegir sin adivinar. */
const DESCRIPCION_TIPO: Record<string, string> = {
  renovacion: "Renueva las condiciones de una relación que ya vence.",
  nuevo: "El primer contrato de trabajo para esta persona.",
  indefinido: "A plazo indeterminado, sin fecha de fin ni causa objetiva.",
  convenio_practicas: "Formaliza la etapa formativa de una practicante.",
  adendum: "Modifica una cláusula puntual de un contrato ya firmado.",
};

/**
 * Qué significa cada estado, y cuál merece el rojo.
 *
 * `grave` NO quiere decir «hay algo que hacer» — en esta pantalla eso lo dicen
 * todas las filas. Quiere decir que el plazo YA SE PASÓ y cada día que corre
 * cuesta. Al principio, con veinte personas sin contrato todavía, marcar eso
 * como grave pintaba la pantalla entera de rojo, y una pantalla toda roja no
 * avisa de nada: el `rojo` de esta paleta es el acento sagrado, con un máximo
 * de usos por vista.
 */
/**
 * El nombre CORTO de cada estado, para la insignia de la tabla.
 *
 * `ESTADO_TABLERO` guarda frases que explican («marcó después del vencimiento —
 * riesgo art. 77»); eso sirve para una lista con espacio, pero dentro de una
 * insignia de una columna estrecha se desborda y tapa lo de al lado — pasó al
 * probarlo. La frase completa sigue viviendo en el visor, que es donde hay
 * sitio para leerla.
 */
const ETIQUETA_CORTA: Record<string, string> = {
  desnaturalizado: "Riesgo art. 77",
  vencido: "Vencido",
  sin_contrato: "Sin registrar",
  sin_firmar: "Sin firmar",
  sin_vencimiento: "Sin vencimiento",
  por_vencer: "Vence pronto",
  tramite_pendiente: "Falta la copia",
  ok: "Vigente",
};

/**
 * «06 mar 2026». La fecha corta de la línea de tiempo.
 *
 * `formatearFecha` da «6 de marzo de 2026», que en la columna estrecha de los
 * hitos ocupa tres renglones y rompe la lectura vertical de las fechas — se vio
 * al probarlo. Acá lo que importa es alinear seis fechas para leerlas de un
 * vistazo, no la prosa.
 */
const MES_CORTO = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "set", "oct", "nov", "dic"];
function fechaCorta(iso: string): string {
  const [y, m, d] = iso.split("-");
  return `${d} ${MES_CORTO[Number(m) - 1]} ${y}`;
}

/** «en 9 días» · «hace 6 días» · «—». Lo que se lee en la columna Vence. */
function venceTexto(f: FilaTablero): { texto: string; alerta: boolean } {
  if (f.fecha_fin_contrato === null) return { texto: "—", alerta: false };
  if (f.dias_restantes === null) return { texto: formatearFecha(f.fecha_fin_contrato), alerta: false };
  if (f.dias_restantes < 0) {
    const d = Math.abs(f.dias_restantes);
    return { texto: d === 1 ? "hace 1 día" : `hace ${d} días`, alerta: true };
  }
  if (f.dias_restantes === 0) return { texto: "hoy", alerta: true };
  return { texto: f.dias_restantes === 1 ? "en 1 día" : `en ${f.dias_restantes} días`, alerta: false };
}

/**
 * Qué decir de quien NO tiene contrato en este sistema.
 *
 * `fn_contratos_tablero` responde «no hay fila acá», y eso NO es lo mismo que
 * «esta persona no tiene contrato»: el generador se estrenó en agosto de 2026 y
 * todo el equipo venía firmando en papel desde antes. Escribir «sin contrato»
 * al lado de veinte nombres es afirmar algo falso sobre gente real — y encima
 * en la pantalla que se abre para decidir a quién hay que renovarle.
 *
 * Se distingue con `fecha_fin_contrato`, que la persona ya trae puesta: si hay
 * fecha de vencimiento, el contrato existe y está firmado en un archivador; lo
 * que falta es traerlo acá. Si no hay ni fecha ni fila, ahí sí no se sabe de
 * ningún contrato, y eso es lo que hay que decir.
 */
function estadoSinContrato(f: FilaTablero): { texto: string; grave: boolean } {
  if (f.fecha_fin_contrato === null) return { texto: "sin contrato registrado", grave: false };
  return { texto: "en papel, sin registrar acá", grave: false };
}

const ESTADO_TABLERO: Record<string, { texto: string; grave: boolean }> = {
  desnaturalizado: { texto: "marcó después del vencimiento — riesgo art. 77", grave: true },
  vencido: { texto: "contrato vencido", grave: true },
  sin_contrato: { texto: "sin contrato registrado", grave: false },
  sin_firmar: { texto: "pendiente de firma", grave: false },
  sin_vencimiento: { texto: "sin fecha de vencimiento", grave: false },
  por_vencer: { texto: "vence pronto", grave: false },
  tramite_pendiente: { texto: "falta entregar copia", grave: false },
  ok: { texto: "al día", grave: false },
};

// Explica el número de "Riesgo de continuidad" sin repetir la jerga legal en
// la tarjeta misma — la tarjeta solo tiene sitio para una palabra.
const EXPLICACION_ART_77 =
  "Si alguien sigue marcando asistencia después de vencido su contrato, el artículo 77 del D. Leg. 728 " +
  "convierte su vínculo en indefinido por ley, sin que nadie lo decida.";

/** Color de la insignia de estado en la tabla compacta, con el mismo criterio
 * de uso del color que pide CLAUDE.md: rojo solo para lo que ya cuesta plata
 * (vencido / riesgo art. 77), ámbar para trámite a medias, verde para lo que
 * está bien, y el resto en tonos neutros — nunca "todo en rojo". */
function variantePorEstado(estado: string): "neutral" | "alerta" | "advertencia" | "positivo" | "informativo" {
  if (estado === "desnaturalizado" || estado === "vencido") return "alerta";
  if (estado === "tramite_pendiente" || estado === "por_vencer") return "advertencia";
  if (estado === "sin_contrato") return "informativo";
  if (estado === "sin_firmar") return "neutral";
  return "positivo"; // ok, sin_vencimiento
}

/**
 * El punto de partida de los campos editables para una persona.
 *
 * Vive acá, y devuelve el objeto entero, porque hay DOS caminos que necesitan
 * la misma respuesta: elegir a alguien en el desplegable, y abrir para editar
 * un borrador anterior a la 0388 —que no guardó lo que se tecleó— y por tanto
 * tiene que empezar de cero. Escritos por separado, el día que se agregue un
 * campo nuevo uno de los dos se queda sin reponerlo, y el formulario arrastra
 * al documento siguiente lo que quedó del anterior.
 */
/** Una fila de la lista por urgencia: quién, qué documento y vigencia, cuánto falta, su estado y su acción. */
function FilaContrato({ v }: {
  v: { persona: string; documento: string; vigencia: string; sede: string | null; estadoLabel: string; estadoVariante: "neutral" | "alerta" | "advertencia" | "positivo" | "informativo";
       vence: string; venceAlerta: boolean; titulo: string; onClickRow: () => void; acciones: React.ReactNode };
}) {
  const detalle = [v.documento !== "—" ? v.documento : null, v.vigencia !== "—" ? v.vigencia : null, v.sede].filter(Boolean).join(" · ");
  return (
    <li
      onClick={v.onClickRow}
      title={v.titulo}
      className="flex cursor-pointer flex-wrap items-center justify-between gap-x-3 gap-y-1.5 px-4 py-3 transition-colors duration-150 hover:bg-crema/60"
    >
      <div className="min-w-0">
        <p className="truncate font-medium text-tinta">{v.persona}</p>
        <p className="truncate text-xs text-taupe">{detalle}</p>
      </div>
      <div className="flex shrink-0 items-center gap-2">
        {v.vence !== "—" && (
          <span className={v.venceAlerta ? "text-xs font-medium text-rojo-profundo" : "text-xs text-taupe"}>{v.vence}</span>
        )}
        <Insignia variante={v.estadoVariante} tamano="sm">{v.estadoLabel}</Insignia>
        <span onClick={(e) => e.stopPropagation()}>{v.acciones}</span>
      </div>
    </li>
  );
}

function camposIniciales(p: Persona, sedeNombre: string, sedeCiudad: string | null): DatosFormulario {
  return {
    cargo: p.cargo ?? "",
    // Prellenada de verdad, no solo como placeholder (pedido de Felipe,
    // 2026-09-07): Central no tiene ciudad propia y se queda vacía a
    // propósito — su gente puede estar en cualquiera, así que se elige a mano.
    ciudad: sedeCiudad ?? "",
    causa:
      `La causa objetiva determinante de la contratación es la siguiente: LA EMPRESA opera la sede ` +
      `${sedeNombre}, que ha experimentado un crecimiento sostenido de su actividad y de atención al ` +
      `público. El volumen actual de operaciones no puede ser absorbido en su totalidad por el personal ` +
      `permanente ya registrado en planillas de LA EMPRESA. En consecuencia, la contratación bajo ` +
      `modalidad temporal resulta necesaria y proporcional a la naturaleza de esta etapa de expansión y ` +
      `consolidación operativa, en los términos del artículo 57 del TUO del Decreto Legislativo N.° 728. ` +
      `[REVISAR antes de imprimir — en especial si la sede es Central, que no es tienda y puede necesitar ` +
      `otra causa objetiva.]`,
    funciones: FUNCIONES_PLACEHOLDER,
    activosLibre: "",
    sinActivosAdicionales: false,
    adendum: "",
    modalidadManual: "",
    horasSemanalesConvenio: "",
    planCapacitacion: "",
    centroFormacionNombre: "",
    centroFormacionRuc: "",
    centroFormacionDomicilio: "",
    centroFormacionRepresentanteNombre: "",
    centroFormacionRepresentanteCargo: "",
    carreraEspecialidad: "",
    cicloAcademico: "",
    gradoTituloTexto: "",
    areaProyecto: "",
    objetivoFormativoGeneral: "",
    supervisorAsignado: "",
  };
}

export default function ContratosPage() {
  const router = useRouter();
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const rol = useRolActual();
  const puede = puedeGestionarContratos(rol);

  const [cargando, setCargando] = useState(true);
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [sedes, setSedes] = useState<Sede[]>([]);
  const [datosPersonales, setDatosPersonales] = useState<DatoPersonal[]>([]);
  const [salarios, setSalarios] = useState<Salario[]>([]);
  const [movilidadTarifas, setMovilidadTarifas] = useState<Parametro[]>([]);
  const [bonoOnomastico, setBonoOnomastico] = useState<number | null>(null);
  // Piso de la subvención de un convenio de prácticas (Ley 28518, art. 45).
  const [rmvVigente, setRmvVigente] = useState<number | null>(null);
  const [ritVersion, setRitVersion] = useState<string | null>(null);
  const [ritFecha, setRitFecha] = useState<string | null>(null);
  const [firmante, setFirmante] = useState(FIRMANTE_POR_DEFECTO);
  // La firma escaneada de QUIEN FIRMA POR CAYLA (`fn_firma_empresa`, 0398), no
  // la de quien tenga la sesión abierta. Es la misma fila que da el nombre
  // impreso (`firmante_empresa`, 0147), así que el nombre y la rúbrica no
  // pueden contradecirse aunque el contrato lo abra DO o la Gerencia: nunca sale
  // la firma de una persona bajo el nombre de otra. Antes se estampaba solo si
  // quien miraba ERA el firmante, y para el resto salía la raya en blanco.
  const [firmaUrl, setFirmaUrl] = useState<string | null>(null);
  const [contratos, setContratos] = useState<ContratoFila[]>([]);
  // `fn_contratos_listar` no filtra por `estado`: el historial de quien ya
  // cesó se queda en `contratos_generados` a propósito (no se borra), pero el
  // Archivo es una pantalla operativa — nada que hacer con el contrato de
  // alguien que ya no está. `personasActivasIds` es la ficha SIN el filtro de
  // `en_planilla`/practicante que sí aplica `personas` (línea ~687), porque
  // un RxH activo sin ese filtro igual merece verse aquí si tiene contrato.
  const [personasActivasIds, setPersonasActivasIds] = useState<Set<string>>(new Set());
  // El tablero parte de las PERSONAS, no de los contratos: el historial arranca
  // de `contratos_generados`, así que quien no tiene ninguno es invisible ahí —
  // y con veinte venciendo el mismo día, «¿a quién le falta?» es la pregunta
  // que hay que poder hacer. Ver migración 0287.
  const [tablero, setTablero] = useState<FilaTablero[]>([]);
  // ¿Falló la lectura del tablero o del historial? Distinto de «no hay nada»: sin esto, un error se veía como una
  // lista vacía y contadores en cero —y con ellos desaparecía el aviso del art. 77, justo lo que NO puede callarse—.
  // El Dashboard ya hacía lo mismo con `contratosNoRespondio`.
  const [falloTablero, setFalloTablero] = useState(false);
  const [falloHistorial, setFalloHistorial] = useState(false);

  const [personaId, setPersonaId] = useState("");
  const [tipo, setTipo] = useState<"nuevo" | "renovacion" | "adendum" | "convenio_practicas" | "indefinido">(
    "renovacion",
  );
  // El paso del generador (rediseño, Fase 2). Guarda el ID del paso, no un
  // índice: los pasos cambian de forma según el tipo de documento (ver
  // `pasosGenerador` más abajo), así que un índice numérico apuntaría a un
  // paso distinto apenas cambia el tipo. Si el id guardado no existe en la
  // lista vigente, el render cae al primero — no hace falta un efecto que lo
  // corrija.
  const [paso, setPaso] = useState("persona");
  const [cargoEditado, setCargoEditado] = useState("");
  const [causaEditada, setCausaEditada] = useState("");
  const [funcionesEditadas, setFuncionesEditadas] = useState("");
  // Solo para tipo === "convenio_practicas" (0333). Desde la 0348 el
  // preprofesional es TRIPARTITO (CAYLA + centro de formación + practicante,
  // art. 12 y ss. Ley 28518) — estos cuatro son del centro, que solo
  // corresponde a esa modalidad.
  const [planCapacitacionEditado, setPlanCapacitacionEditado] = useState("");
  const [centroFormacionNombreEditado, setCentroFormacionNombreEditado] = useState("");
  const [centroFormacionRucEditado, setCentroFormacionRucEditado] = useState("");
  const [centroFormacionDomicilioEditado, setCentroFormacionDomicilioEditado] = useState("");
  const [centroFormacionRepresentanteNombreEditado, setCentroFormacionRepresentanteNombreEditado] = useState("");
  const [centroFormacionRepresentanteCargoEditado, setCentroFormacionRepresentanteCargoEditado] = useState("");
  const [carreraEspecialidadEditada, setCarreraEspecialidadEditada] = useState("");
  const [cicloAcademicoEditado, setCicloAcademicoEditado] = useState("");
  // Solo profesional (0348): "Bachiller en X — Universidad Y, egresado el Z".
  const [gradoTituloTextoEditado, setGradoTituloTextoEditado] = useState("");
  // Convenio elegido A MANO para alguien cuya ficha no dice tipo_vinculo=
  // 'practicante' (0348 — antes solo se podía generar cambiando la ficha
  // primero en Equipo). Sin esto, `persona.practicante_modalidad` sale
  // siempre null para esa persona y no hay de dónde sacar 30h/48h.
  const [modalidadManualEditada, setModalidadManualEditada] = useState<"preprofesional" | "profesional" | "">("");
  // Solo preprofesional (auditoría 2026-09-14, hallazgo #1): cuántas horas
  // semanales se pactaron de verdad, cuando son MENOS que el tope de 30h de
  // su modalidad. Texto libre y no number: así puede arrancar vacío (= "a las
  // 30h completas de su modalidad", el comportamiento de siempre) en vez de
  // forzar un 0 o un 30 que nadie tecleó.
  const [horasConvenioEditadas, setHorasConvenioEditadas] = useState("");
  // Identifica a la persona como practicante DESDE QUE SE GENERA el convenio,
  // no desde que se firma — a diferencia de un contrato de trabajo, que sí
  // necesita el papel firmado para ser real, la decisión de traer a alguien
  // como practicante ya se tomó antes de sentarse a redactarle el convenio.
  // Solo aplica mientras la ficha (Equipo) todavía no dice tipo_vinculo=
  // practicante — si ya lo dice, no hay nada que aplicar.
  const [aplicarModalidadFicha, setAplicarModalidadFicha] = useState(true);
  // Anexo I — Plan Específico de Aprendizaje (0348, ambas modalidades).
  const [areaProyectoEditado, setAreaProyectoEditado] = useState("");
  const [objetivoFormativoGeneralEditado, setObjetivoFormativoGeneralEditado] = useState("");
  const [supervisorAsignadoEditado, setSupervisorAsignadoEditado] = useState("");
  const [activosLibre, setActivosLibre] = useState("");
  const [adendumEditado, setAdendumEditado] = useState("");
  const [ciudadEditada, setCiudadEditada] = useState("");
  // Sin esto marcado, un Anexo IV vacío es indistinguible de uno olvidado —
  // decisión de Felipe (2026-08-19): un campo vacío no basta, hay que
  // declararlo a propósito.
  const [sinActivosAdicionales, setSinActivosAdicionales] = useState(false);
  const [fechaInicio, setFechaInicio] = useState("");
  const [fechaFin, setFechaFin] = useState("");

  const [generando, setGenerando] = useState(false);
  const [borrador, setBorrador] = useState<{ id: string; html: string } | null>(null);
  // El texto congelado de un contrato del historial, al abrirlo para
  // reimprimirlo. Estado propio y no `borrador`: el efecto que descarta el
  // borrador al editar el formulario no debe cerrar lo que se está mirando.
  const [documentoAbierto, setDocumentoAbierto] = useState<string | null>(null);
  // La firma que el colaborador confirmó en ESTE contrato (0402), congelada al
  // momento de confirmar — no la firma general de la persona, que puede haber
  // cambiado después. Un valor viejo acá no se ve nunca solo: `htmlFinalModal`
  // (más abajo) solo lo usa cuando `documentoAbierto` también está puesto, y
  // `abrirGenerado` siempre escribe los dos juntos — no hace falta limpiarlo
  // por separado en cada cierre del visor.
  const [firmaPersonaAbierta, setFirmaPersonaAbierta] = useState<string | null>(null);

  const [subiendoPara, setSubiendoPara] = useState<string | null>(null);
  const [archivo, setArchivo] = useState<File | null>(null);
  // NACE CON LA FECHA DE HOY, no vacía. Ver la regla en CLAUDE.md: un campo de
  // fecha vacío que bloquea el envío depende de que el navegador entregue el
  // valor, y Safari no siempre lo hace — el 2026-08-26 un descanso médico real
  // no se pudo registrar por eso, con la fecha pintada en el campo y vacía por
  // dentro. Hoy es lo más probable para un papel que se acaba de firmar, se ve
  // en pantalla y se corrige en un clic.
  const [fechaFirma, setFechaFirma] = useState(hoyLima());
  const [progreso, setProgreso] = useState<number | null>(null);
  const [guardandoFirma, setGuardandoFirma] = useState(false);

  const [anulando, setAnulando] = useState<string | null>(null);
  const [motivoAnular, setMotivoAnular] = useState("");

  // EL BORRADOR QUE SE ESTÁ CORRIGIENDO EN SU SITIO (0388).
  //
  // No nulo = el formulario dejó de generar documentos nuevos y está editando
  // este. Se guarda la fila entera y no solo el id porque de ella salen las
  // fechas y el tipo con los que se repuebla el formulario, y porque hay que
  // poder decir en pantalla cuál es sin volver a buscarlo en la lista.
  const [editando, setEditando] = useState<ContratoFila | null>(null);
  const [guardandoEdicion, setGuardandoEdicion] = useState(false);
  // Un borrador anterior a la 0388 no guardó lo que se tecleó. Se puede editar
  // igual —fechas, cargo, tipo— pero los textos largos vuelven a arrancar en su
  // relleno, y eso hay que DECIRLO: reimprimir creyendo que se conservaron
  // sería peor que no poder editarlo.
  const [edicionSinFoto, setEdicionSinFoto] = useState(false);

  // Filtra LAS DOS listas de la izquierda a la vez —lo pendiente y el archivo—,
  // que es como se busca de verdad: no se pregunta «¿está en pendientes o en el
  // archivo?», se pregunta «¿qué pasa con Danitza?». Con ~30 personas activas y
  // varios contratos por cabeza, eso se respondía recorriendo la pantalla.
  const [busca, setBusca] = useState("");
  // ?persona=<id> — llega desde la Bandeja (una revisión de contrato pedida).
  // Se aplica UNA vez: escribe su nombre en el buscador y abre «todos», porque
  // su contrato puede estar «al día» y el filtro de pendientes lo escondería.
  // El ref evita que cada `cargar()` posterior pise lo que se escribió.
  const personaUrlAplicada = useRef(false);
  // Los dos filtros de la tabla. `filtroEstado` arranca en «pendientes» y no en
  // «todos» a propósito: una tabla donde casi todas las filas dicen «al día»
  // enseña a ignorarla, que es el mismo criterio con el que el tablero viejo
  // escondía a quien no tenía nada pendiente. La diferencia es que ahora los
  // demás se pueden ver con un clic, en vez de no existir.
  const [filtroSede, setFiltroSede] = useState("");
  // Además de una clave real de ESTADO_TABLERO, admite tres sentinelas que
  // no existen en la base: "pendientes" (default), "todos", "vigentes" (une
  // ok + sin_vencimiento) y "archivados" (cambia la FUENTE de datos: deja de
  // leer el tablero y lee los contratos anulados). Ninguno inventa un estado
  // nuevo del lado del servidor — solo reagrupan, del lado del cliente,
  // estados que `fn_contratos_tablero` ya entrega.
  // Qué banda de urgencia se está mirando (la elige una pastilla de «Para atender»); `null` = todas.
  const [bandaElegida, setBandaElegida] = useState<Banda | null>(null);
  // El aviso del art. 77 arranca en una línea; la explicación legal se abre a pedido.
  const [art77Abierto, setArt77Abierto] = useState(false);
  const [filtroEstado, setFiltroEstado] = useState<"pendientes" | "todos" | "vigentes" | "archivados" | string>(
    "pendientes",
  );
  // Nuevo (rediseño): filtrar por tipo de documento. Las opciones se leen de
  // lo que ya hay en pantalla (tablero + contratos), nunca de una lista
  // escrita a mano — mismo criterio que `sedesEnTablero`.
  const [filtroTipo, setFiltroTipo] = useState("");
  // EL CONTRATO QUE SE ESTÁ MIRANDO EN EL VISOR — se guarda su ID, no la fila.
  //
  // Marcar «copia entregada» desde el visor llama a `cargar()`, que trae la
  // lista de nuevo; con una copia de la fila guardada aquí, el visor seguiría
  // mostrando «falta» sobre un trámite que se acaba de anotar. Derivarlo del id
  // lo deja siempre fresco sin un efecto que lo sincronice — y sin un
  // `setState` dentro de un efecto, que es lo que el linter caza.
  const [detalleId, setDetalleId] = useState<string | null>(null);

  // EL GENERADOR SE VE COMO SU PROPIA PANTALLA, no como una sección más de
  // la página (rediseño, pedido explícito de Felipe: "se tiene que ver
  // principalmente la ventana del contrato"). Sigue siendo la misma página
  // de Next.js —no hay ruta propia todavía—, pero mientras esto es true se
  // dibuja como una superposición a pantalla completa que tapa el listado,
  // igual que pedía la spec original ("abrir una página dedicada... no un
  // modal pequeño"). Cerrarla NUNCA borra lo tecleado: solo dejar de verlo.
  const [generadorAbierto, setGeneradorAbierto] = useState(false);

  // DE DÓNDE SE TRAJERON LOS CAMPOS DE ABAJO, si se trajeron de un documento
  // anterior de la misma persona (ver el efecto que llama a
  // `traerDelAnteriorSiHay`). Solo para mostrar el aviso — no participa en
  // ninguna validación.
  const [prellenoAnterior, setPrellenoAnterior] = useState<{ tipo: string; generado_at: string } | null>(null);

  const { avisar } = useToast();

  /** Vuelca al formulario los veinte campos editables, de una sola vez. */
  function aplicarCampos(d: DatosFormulario) {
    setCargoEditado(d.cargo);
    setCiudadEditada(d.ciudad);
    setCausaEditada(d.causa);
    setFuncionesEditadas(d.funciones);
    setActivosLibre(d.activosLibre);
    setSinActivosAdicionales(d.sinActivosAdicionales);
    setAdendumEditado(d.adendum);
    setModalidadManualEditada(
      d.modalidadManual === "preprofesional" || d.modalidadManual === "profesional" ? d.modalidadManual : "",
    );
    // `?? ""`: un borrador de antes de este campo no lo tiene en su
    // `datos_formulario` guardado — mismo caso que ya vive en `edicionSinFoto`,
    // a nivel de un campo en vez del objeto entero.
    setHorasConvenioEditadas(d.horasSemanalesConvenio ?? "");
    setPlanCapacitacionEditado(d.planCapacitacion);
    setCentroFormacionNombreEditado(d.centroFormacionNombre);
    setCentroFormacionRucEditado(d.centroFormacionRuc);
    setCentroFormacionDomicilioEditado(d.centroFormacionDomicilio);
    setCentroFormacionRepresentanteNombreEditado(d.centroFormacionRepresentanteNombre);
    setCentroFormacionRepresentanteCargoEditado(d.centroFormacionRepresentanteCargo);
    setCarreraEspecialidadEditada(d.carreraEspecialidad);
    setCicloAcademicoEditado(d.cicloAcademico);
    setGradoTituloTextoEditado(d.gradoTituloTexto);
    setAreaProyectoEditado(d.areaProyecto);
    setObjetivoFormativoGeneralEditado(d.objetivoFormativoGeneral);
    setSupervisorAsignadoEditado(d.supervisorAsignado);
  }

  /**
   * La foto de lo que hay ahora en el formulario, para guardarla junto al
   * documento. Es la que permite volver a abrirlo tal cual meses después —ver
   * `DatosFormulario`— y la que hace que corregir una fecha cueste un clic en
   * vez de reescribir el convenio entero.
   */
  function camposActuales(): DatosFormulario {
    return {
      cargo: cargoEditado,
      ciudad: ciudadEditada,
      causa: causaEditada,
      funciones: funcionesEditadas,
      activosLibre,
      sinActivosAdicionales,
      adendum: adendumEditado,
      modalidadManual: modalidadManualEditada,
      horasSemanalesConvenio: horasConvenioEditadas,
      planCapacitacion: planCapacitacionEditado,
      centroFormacionNombre: centroFormacionNombreEditado,
      centroFormacionRuc: centroFormacionRucEditado,
      centroFormacionDomicilio: centroFormacionDomicilioEditado,
      centroFormacionRepresentanteNombre: centroFormacionRepresentanteNombreEditado,
      centroFormacionRepresentanteCargo: centroFormacionRepresentanteCargoEditado,
      carreraEspecialidad: carreraEspecialidadEditada,
      cicloAcademico: cicloAcademicoEditado,
      gradoTituloTexto: gradoTituloTextoEditado,
      areaProyecto: areaProyectoEditado,
      objetivoFormativoGeneral: objetivoFormativoGeneralEditado,
      supervisorAsignado: supervisorAsignadoEditado,
    };
  }

  /**
   * Trae el Anexo I / plan formativo del documento anterior VIVO de esta
   * persona, de la misma familia (contrato de trabajo o convenio), para no
   * obligar a re-escribirlo desde cero en cada renovación.
   *
   * Hallazgo de la auditoría 2026-09-14: `datos_formulario` guarda esto desde
   * la 0388, pero solo se leía al EDITAR un borrador propio (`empezarEdicion`)
   * — nunca al generar uno nuevo, aunque `FUNCIONES_PLACEHOLDER` le pide
   * explícitamente a quien usa la pantalla ir a buscarlo a mano ("usar como
   * referencia el Anexo I del contrato anterior de esta persona, si existe").
   *
   * Un adendum no tiene familia de la que traer nada (su `datos_formulario`
   * solo guarda `adendum`) y no participa. La causa objetiva NO se trae: es
   * la decisión legal más sensible del documento (ver el encabezado de
   * `contrato-texto.ts`) y una anterior puede haber quedado desactualizada;
   * se prefiere que arranque siempre en el texto de partida a revisar, nunca
   * en un texto viejo que parezca ya revisado.
   */
  async function traerDelAnteriorSiHay(
    personaIdBuscada: string,
    tipoBuscado: "nuevo" | "renovacion" | "adendum" | "convenio_practicas" | "indefinido",
  ) {
    const familia: string[] =
      tipoBuscado === "convenio_practicas"
        ? ["convenio_practicas"]
        : tipoBuscado === "adendum"
          ? []
          : ["nuevo", "renovacion", "indefinido"];
    if (familia.length === 0) return null;

    const { data, error } = await supabase
      .from("contratos_generados")
      .select("tipo, generado_at, datos_formulario")
      .eq("persona_id", personaIdBuscada)
      .is("anulado_at", null)
      .in("tipo", familia)
      .order("generado_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (error || !data) return null;
    return data as { tipo: string; generado_at: string; datos_formulario: DatosFormulario | null };
  }

  const sedeCodigo = useMemo(() => new Map(sedes.map((s) => [s.id, s.codigo])), [sedes]);
  const sedeNombreMap = useMemo(() => new Map(sedes.map((s) => [s.id, s.nombre])), [sedes]);
  const sedeCiudadMap = useMemo(() => new Map(sedes.map((s) => [s.id, s.ciudad])), [sedes]);

  // Sugerencias para "Cargo" y "Ciudad donde se firma": lo que YA se usó en el
  // sistema, no una lista escrita a mano (regla de la casa) — si mañana
  // alguien crea un cargo nuevo, aparece solo. Siguen siendo campos libres:
  // el `<datalist>` sugiere, nunca restringe a lo que ya existe.
  //
  // El cargo actual de `personas` (2026-09-07) se quedaba corto a propósito
  // de la pregunta: la mayoría de colaboradoras no tiene `cargo` propio —sin
  // él se les muestra el rol (0182)— así que solo aparecían los tres o cuatro
  // puestos de jefatura que sí lo tienen escrito. `contratos` (`fn_contratos_listar`)
  // ya trae el cargo con el que se generó CADA contrato de la historia, de
  // cualquier persona, activa o no: esa es la lista completa de puestos que
  // la empresa ha usado de verdad.
  //
  // Excluye los anulados a propósito (2026-09-07): un borrador de PRUEBA —con
  // "asdf" o cualquier relleno en Cargo— se descarta anulándolo, nunca
  // borrándolo (regla de la casa), así que sin este filtro cada prueba deja
  // basura permanente en esta lista. Un contrato anulado sigue siendo el
  // registro de lo que se pactó (no se toca su texto), solo deja de contar
  // como "un cargo que la empresa usa".
  const cargosExistentes = useMemo(
    () =>
      Array.from(
        new Set(
          [...personas.map((p) => p.cargo), ...contratos.filter((c) => !c.anulado_at).map((c) => c.cargo)]
            .map((c) => c?.trim())
            .filter((c): c is string => !!c),
        ),
      ).sort(),
    [personas, contratos],
  );
  const ciudadesExistentes = useMemo(
    () => Array.from(new Set(sedes.map((s) => s.ciudad?.trim()).filter((c): c is string => !!c))).sort(),
    [sedes],
  );

  // La tarifa de movilidad de una sede: SU fila, o la general. Mismo criterio
  // que usa fn_planilla_calcular y /admin/documentacion — el contrato y la
  // boleta no pueden decir montos distintos.
  const tarifaDeSede = useCallback(
    (sedeBaseId: string | null | undefined): number | null => {
      const codigo = sedeBaseId ? sedeCodigo.get(sedeBaseId) : undefined;
      const suya = codigo ? movilidadTarifas.find((t) => t.sede_codigo === codigo) : undefined;
      const fila = suya ?? movilidadTarifas.find((t) => !t.sede_codigo);
      const valor = fila ? Number(fila.valor) : NaN;
      return Number.isFinite(valor) && valor > 0 ? valor : null;
    },
    [sedeCodigo, movilidadTarifas],
  );

  const cargar = useCallback(async () => {
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) {
      router.replace("/admin/login");
      return;
    }

    const hoy = hoyLima();
    const [ps, ss, dp, sal, params, rit, ctr, tab, cfg, fichas, firma] = await Promise.all([
      // Sin `.eq("en_planilla", true)`: una practicante también genera un
      // documento acá (su convenio, 0333) aunque `en_planilla` le salga
      // false. Se filtra en el cliente por `en_planilla || tipo_vinculo ===
      // "practicante"` — mismo criterio que ya usa `vinculo.ts` y la boleta,
      // no un `.or()` de PostgREST nuevo que aprender.
      supabase
        .from("personas")
        .select("id, nombres, apellidos, documento, cargo, sede_base_id, sede_fisica_id, email, fecha_ingreso, fecha_fin_contrato, cobra_movilidad, personal_direccion, sueldo_fijo, en_planilla, tipo_vinculo, practicante_modalidad")
        .eq("estado", "activo").eq("cuenta_de_servicio", false)
        .order("apellidos"),
      supabase.from("sedes").select("id, nombre, codigo, ciudad"),
      supabase.from("datos_personales").select("persona_id, nombre_dni, direccion, genero"),
      supabase.from("asignaciones_salario").select("persona_id, salario_mensual_soles").is("vigente_hasta", null),
      // Movilidad, bono y RMV: la fila vigente HOY. Sin fila aplicable, cae a
      // null y el contrato lo dice en vez de inventar un monto — misma
      // regla que /admin/documentacion. La RMV es el piso de la subvención
      // de un convenio de prácticas (Ley 28518, art. 45).
      //
      // «Vigente» es la condición de la planilla —`vigente_desde <= hoy` y
      // (`vigente_hasta` nula o `>= hoy`)—, NO «la fila abierta»: con `.is(null)`,
      // cerrar la RMV vieja (vigente_hasta = víspera) y abrir la nueva con fecha
      // futura dejaba la pantalla sin RMV hasta el día del cambio, y con las dos
      // abiertas se quedaba con la primera que llegara. Ver parametro-vigente.ts.
      supabase
        .from("parametros_laborales")
        .select("clave, valor, sede_codigo, vigente_desde, vigente_hasta")
        .in("clave", ["movilidad_diaria", "bono_onomastico", "rmv"])
        .lte("vigente_desde", hoy)
        .or(`vigente_hasta.is.null,vigente_hasta.gte.${hoy}`)
        .order("vigente_desde", { ascending: false }),
      // La versión vigente del RIT. Se lee de la tabla, no se escribe a
      // mano: es exactamente el dato que este repo prohíbe hardcodear.
      supabase
        .from("documentos_institucionales")
        .select("version, etiqueta_version, vigente_desde")
        .eq("tipo", "rit")
        .lte("vigente_desde", hoy)
        .order("vigente_desde", { ascending: false })
        .limit(1),
      supabase.rpc("fn_contratos_listar"),
      supabase.rpc("fn_contratos_tablero"),
      // Quién firma por CAYLA (0147) — dato administrable, no escrito acá.
      supabase.from("configuracion").select("valor").eq("clave", "firmante_empresa").maybeSingle(),
      // Las fichas SIN filtrar por `en_planilla`: quien firma por la empresa no
      // tiene por qué estar en planilla —puede ser accionista— y buscarlo en la
      // lista del desplegable lo dejaría sin nombre ni DNI en el contrato.
      supabase.from("personas").select("id, nombres, apellidos, documento").eq("estado", "activo").eq("cuenta_de_servicio", false),
      // La firma escaneada de quien firma por CAYLA. No recibe parámetros: nadie
      // puede pedir «la firma de fulano», solo la del firmante configurado.
      supabase.rpc("fn_firma_empresa"),
    ]);

    setPersonas(
      ((ps.data as Persona[]) ?? []).filter((p) => p.en_planilla || p.tipo_vinculo === "practicante"),
    );
    setSedes((ss.data as Sede[]) ?? []);
    setDatosPersonales((dp.data as DatoPersonal[]) ?? []);
    setSalarios((sal.data as Salario[]) ?? []);

    // El firmante: su persona_id y cargo vienen de `configuracion`; su nombre y
    // su DNI, de la ficha de esa persona — no de un literal en este archivo.
    const cfgValor = (cfg.data as { valor: { persona_id?: string; cargo?: string } } | null)?.valor;
    const firmanteId = cfgValor?.persona_id ?? null;
    type Ficha = { id: string; nombres: string; apellidos: string; documento: string | null };
    const fichasActivas = (fichas.data as Ficha[]) ?? [];
    const fichaFirmante = fichasActivas.find((p) => p.id === firmanteId);
    setPersonasActivasIds(new Set(fichasActivas.map((p) => p.id)));
    setFirmante({
      nombre: fichaFirmante ? `${fichaFirmante.nombres} ${fichaFirmante.apellidos}` : FIRMANTE_POR_DEFECTO.nombre,
      dni: fichaFirmante?.documento ?? FIRMANTE_POR_DEFECTO.dni,
      cargo: cfgValor?.cargo ?? FIRMANTE_POR_DEFECTO.cargo,
    });

    const firmaEmpresa = typeof firma.data === "string" ? firma.data : null;
    setFirmaUrl(firmaEmpresa?.startsWith("data:image") ? firmaEmpresa : null);

    const paramsData = vigentesAl((params.data as Parametro[]) ?? [], hoy);
    setMovilidadTarifas(paramsData.filter((p) => p.clave === "movilidad_diaria"));
    const bono = paramsData.find((p) => p.clave === "bono_onomastico");
    setBonoOnomastico(bono ? Number(bono.valor) : null);
    const rmv = paramsData.find((p) => p.clave === "rmv");
    setRmvVigente(rmv ? Number(rmv.valor) : null);

    const ritFila = ((rit.data as { version: number; etiqueta_version: string | null; vigente_desde: string }[] | null) ?? [])[0];
    // `version` es un CORRELATIVO interno —cuántas veces se ha publicado un
    // documento de ese tipo—, no la versión editorial. La 0265 lo dejó escrito:
    // «con el Reglamento 4.0 publicado como `version = 1`, el 5.0 será la 2: el
    // desfase de tres se queda para siempre», y por eso agregó `etiqueta_version`.
    // Citándolo mal, los veinte contratos remitirían a un «RIT versión 1» que no
    // existe: el papel que el equipo firmó dice 4.0.
    setRitVersion(ritFila ? String(ritFila.etiqueta_version ?? ritFila.version) : null);
    setRitFecha(ritFila ? formatearFecha(ritFila.vigente_desde) : null);

    setFalloHistorial(!!ctr.error);
    setFalloTablero(!!tab.error);
    setContratos((ctr.data as ContratoFila[]) ?? []);
    setTablero((tab.data as FilaTablero[]) ?? []);
    if (!personaUrlAplicada.current) {
      personaUrlAplicada.current = true;
      const pid = new URLSearchParams(window.location.search).get("persona");
      const fila = pid ? ((tab.data as FilaTablero[]) ?? []).find((f) => f.persona_id === pid) : undefined;
      if (fila) { setBusca(fila.persona); setFiltroEstado("todos"); }
    }
    setCargando(false);
  }, [supabase, router]);

  useEffect(() => {
    void cargar();
  }, [cargar]);

  // EL TIPO SE REPONE AL CAMBIAR DE PERSONA, y esto no es comodidad.
  //
  // Sin este efecto, elegir «generar» en el tablero sobre un ingreso nuevo deja
  // `tipo = "nuevo"`, y al cambiar de persona en el desplegable ese «nuevo» se
  // queda pegado: el efecto de abajo repone cargo, causa, funciones y fechas
  // pero NO el tipo. La siguiente persona —con años de servicio— se llevaría la
  // cláusula TERCERA de contrato nuevo, o sea un período de prueba de tres
  // meses «sin expresión de causa y sin derecho a indemnización». Es el mismo
  // defecto que se cerró el 2026-08-24 por el otro camino; cerrarlo solo en el
  // botón del tablero dejaba esta puerta abierta.
  //
  // Va en su propio efecto y no dentro del de abajo porque aquel depende de
  // `tipo`: escribirlo ahí lo haría dispararse a sí mismo.
  useEffect(() => {
    const p = personas.find((x) => x.id === personaId);
    if (!p) return;
    // Al abrir un borrador para corregirlo, el tipo es EL SUYO —el del papel que
    // ya se imprimió— y no el que le tocaría hoy a esa persona. Los dos efectos
    // de repoblado se apartan mientras dure la edición: `editando` se fija en el
    // mismo lote de `setState` que `personaId`, así que cuando este efecto corre
    // ya lo ve puesto.
    if (editando) return;
    setTipo(tipoQueCorresponde(p.fecha_ingreso, hoyLima()));
    // `personas` fuera de las dependencias por la misma razón que el efecto de
    // abajo: `cargar()` la devuelve con otra referencia y repondría el tipo
    // que quien usa la pantalla acaba de elegir a mano.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [personaId]);

  // Al cambiar de persona o de tipo, se reponen los campos editables con un
  // punto de partida razonable — y se descarta cualquier borrador anterior,
  // que ya no corresponde a lo que se está editando ahora.
  useEffect(() => {
    const p = personas.find((x) => x.id === personaId);
    setBorrador(null);
    // Nuevo sujeto (persona) o nuevo documento (tipo) = vuelve al primer paso
    // del stepper. Si ya estaba en "persona" no cambia nada; si estaba más
    // adelante, seguir ahí mostraría el paso 3 de un documento que recién
    // empieza.
    setPaso("persona");
    setPrellenoAnterior(null);
    // Acá NO se cierra el visor, y hace falta decir por qué: hasta el
    // 2026-09-08 sí lo hacía, por precaución. Era precaución muerta —mientras
    // el visor está abierto, su scrim tapa el desplegable de persona, así que
    // este efecto no puede correr con un documento a la vista— y desde que el
    // borrador corregido se abre en el visor pasó a ser dañina: `guardarEdicion`
    // limpia la persona en el mismo lote, así que este efecto se disparaba
    // después y cerraba de golpe el documento recién abierto. Quien cambia de
    // contexto a propósito ya lo cierra: `empezarEdicion` y `cancelarEdicion`.
    if (!p) return;
    // Ver el efecto de arriba: editar repuebla el formulario con lo que se
    // tecleó aquel día, y este efecto lo borraría entero un instante después.
    if (editando) return;

    aplicarCampos(
      camposIniciales(
        p,
        p.sede_base_id ? (sedeNombreMap.get(p.sede_base_id) ?? "") : "",
        p.sede_base_id ? (sedeCiudadMap.get(p.sede_base_id) ?? null) : null,
      ),
    )

    const inicio = tipo === "renovacion" && p.fecha_fin_contrato ? sumarDias(p.fecha_fin_contrato, 1) : hoyLima();
    setFechaInicio(inicio);
    // La fecha de fin NO arranca vacía (regla de la casa del 2026-08-26): su
    // vacío bloquea «Generar borrador», y en Safari un valor tecleado a mano
    // puede verse en pantalla sin llegar nunca al estado de React. El 2026-09-04
    // pasó justo eso con un convenio: 03/12/2026 a la vista y el botón apagado.
    // Nace con el plazo más probable —tres meses para un convenio, un año para
    // un contrato modal— y se cambia en un clic.
    const esConvenioDeEstaPersona = p.tipo_vinculo === "practicante" || tipo === "convenio_practicas";
    setFechaFin(finDePlazo(inicio, esConvenioDeEstaPersona ? 3 : 12));

    // TRAER EL ANEXO I / PLAN FORMATIVO DEL DOCUMENTO ANTERIOR, SI HAY (hallazgo
    // de la auditoría 2026-09-14, ver `traerDelAnteriorSiHay`). Async y con
    // bandera de cancelación: si la persona o el tipo cambian de nuevo antes de
    // que responda, esta respuesta ya no es de nadie y no debe escribir sobre
    // el formulario que se está mostrando ahora. Cada `set...` usa la forma
    // funcional y solo pisa el valor si sigue siendo el de partida (nadie
    // tecleó nada todavía) — así una respuesta lenta nunca borra lo que quien
    // usa la pantalla ya empezó a escribir.
    let cancelado = false;
    const tipoParaBuscar = p.tipo_vinculo === "practicante" ? "convenio_practicas" : tipo;
    void traerDelAnteriorSiHay(p.id, tipoParaBuscar).then((anterior) => {
      if (cancelado || !anterior?.datos_formulario) return;
      const d = anterior.datos_formulario;
      if (tipoParaBuscar === "convenio_practicas") {
        // La modalidad decide la jornada y el piso de la subvención (art. 44/45
        // Ley 28518) — sin traerla, el resto de campos se prellenaba pero el
        // convenio seguía sin poder calcular ninguna de las dos. Si la ficha
        // (Equipo) YA dice `practicante_modalidad`, `modalidadEfectiva` la usa
        // primero (ver su cálculo más arriba) y esto queda sin efecto visible.
        if (d.modalidadManual === "preprofesional" || d.modalidadManual === "profesional") {
          const modalidadAnterior = d.modalidadManual;
          setModalidadManualEditada((prev) => (prev === "" ? modalidadAnterior : prev));
        }
        // `?.trim()` y no un acceso directo: un `datos_formulario` de antes de
        // este campo (auditoría 2026-09-14) simplemente no lo tiene.
        if (d.horasSemanalesConvenio?.trim())
          setHorasConvenioEditadas((prev) => (prev === "" ? d.horasSemanalesConvenio : prev));
        if (d.planCapacitacion?.trim()) setPlanCapacitacionEditado((prev) => (prev === "" ? d.planCapacitacion : prev));
        if (d.centroFormacionNombre?.trim())
          setCentroFormacionNombreEditado((prev) => (prev === "" ? d.centroFormacionNombre : prev));
        if (d.centroFormacionRuc?.trim()) setCentroFormacionRucEditado((prev) => (prev === "" ? d.centroFormacionRuc : prev));
        if (d.centroFormacionDomicilio?.trim())
          setCentroFormacionDomicilioEditado((prev) => (prev === "" ? d.centroFormacionDomicilio : prev));
        if (d.centroFormacionRepresentanteNombre?.trim())
          setCentroFormacionRepresentanteNombreEditado((prev) => (prev === "" ? d.centroFormacionRepresentanteNombre : prev));
        if (d.centroFormacionRepresentanteCargo?.trim())
          setCentroFormacionRepresentanteCargoEditado((prev) => (prev === "" ? d.centroFormacionRepresentanteCargo : prev));
        if (d.carreraEspecialidad?.trim()) setCarreraEspecialidadEditada((prev) => (prev === "" ? d.carreraEspecialidad : prev));
        if (d.cicloAcademico?.trim()) setCicloAcademicoEditado((prev) => (prev === "" ? d.cicloAcademico : prev));
        if (d.areaProyecto?.trim()) setAreaProyectoEditado((prev) => (prev === "" ? d.areaProyecto : prev));
        if (d.objetivoFormativoGeneral?.trim())
          setObjetivoFormativoGeneralEditado((prev) => (prev === "" ? d.objetivoFormativoGeneral : prev));
        if (d.supervisorAsignado?.trim()) setSupervisorAsignadoEditado((prev) => (prev === "" ? d.supervisorAsignado : prev));
      } else if (d.funciones?.trim() && d.funciones !== FUNCIONES_PLACEHOLDER) {
        setFuncionesEditadas((prev) => (prev === FUNCIONES_PLACEHOLDER ? d.funciones : prev));
      }
      if (d.activosLibre?.trim()) setActivosLibre((prev) => (prev === "" ? d.activosLibre : prev));
      setPrellenoAnterior({ tipo: anterior.tipo, generado_at: anterior.generado_at });
    });

    // Deliberadamente NO depende de `personas`/`sedeNombreMap`/`sedeCiudadMap`
    // (generar un borrador llama a `cargar()`, que trae esos tres arreglos de
    // nuevo con otra referencia, y repoblaría el formulario a medio llenar) ni
    // de `editando` (ya se lee arriba con un `return` temprano; no hace falta
    // volver a correr este efecto solo porque cambie) ni de
    // `traerDelAnteriorSiHay` (estable entre renders salvo por `contratos`,
    // que tampoco debe reiniciar el formulario en cada `cargar()`).
    return () => {
      cancelado = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [personaId, tipo]);

  // Cualquier edición posterior invalida el borrador ya generado: lo que se
  // imprime tiene que ser exactamente lo que se congeló en la base, nunca una
  // versión editada después de generarlo.
  useEffect(() => {
    setBorrador(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    cargoEditado,
    causaEditada,
    funcionesEditadas,
    activosLibre,
    sinActivosAdicionales,
    adendumEditado,
    ciudadEditada,
    planCapacitacionEditado,
    centroFormacionNombreEditado,
    centroFormacionRucEditado,
    centroFormacionDomicilioEditado,
    centroFormacionRepresentanteNombreEditado,
    centroFormacionRepresentanteCargoEditado,
    carreraEspecialidadEditada,
    cicloAcademicoEditado,
    gradoTituloTextoEditado,
    areaProyectoEditado,
    objetivoFormativoGeneralEditado,
    supervisorAsignadoEditado,
    modalidadManualEditada,
    fechaInicio,
    fechaFin,
  ]);

  const persona = personas.find((p) => p.id === personaId) ?? null;
  // Una practicante no tiene "nuevo ingreso" ni "renovación" — su único
  // documento es el convenio (0333), y esto NO se resuelve reponiendo `tipo`
  // desde un efecto (ver el de abajo, que solo mira `fecha_ingreso`): es un
  // valor DERIVADO del render, para no encadenar un segundo `setState` por
  // cada cambio de persona. `tipo` sigue siendo la fuente para nuevo/
  // renovación/adendum — elegibles a mano — y esto solo la reemplaza cuando
  // la persona es practicante, sin que quien usa la pantalla tenga que saber
  // por qué el desplegable de tipo desaparece.
  const tipoEfectivo = persona?.tipo_vinculo === "practicante" ? "convenio_practicas" : tipo;
  // La modalidad efectiva: la de la ficha si la persona YA es practicante
  // (0324) — eso no se pisa a mano —, o la elegida en pantalla cuando el
  // convenio se generó eligiéndolo del desplegable para alguien que no está
  // marcado así (0348: antes esto no existía, había que ir a Equipo primero).
  const modalidadEfectiva: "preprofesional" | "profesional" | null =
    persona?.practicante_modalidad === "preprofesional" || persona?.practicante_modalidad === "profesional"
      ? persona.practicante_modalidad
      : modalidadManualEditada || null;
  // Solo tiene sentido para preprofesional — el profesional siempre se asume
  // a su jornada completa de 48h (ver contrato-texto.ts). `null` = a las 30h
  // completas de su modalidad, el mismo comportamiento que tenía el sistema
  // antes de este campo (auditoría 2026-09-14, hallazgo #1).
  const horasConvenioNumero =
    modalidadEfectiva === "preprofesional" && horasConvenioEditadas.trim() !== ""
      ? Number(horasConvenioEditadas)
      : null;
  const datoPersonal = persona ? (datosPersonales.find((d) => d.persona_id === persona.id) ?? null) : null;
  const salarioVigente = persona
    ? (salarios.find((s) => s.persona_id === persona.id)?.salario_mensual_soles ?? null)
    : null;

  const sedeCod = persona?.sede_base_id ? (sedeCodigo.get(persona.sede_base_id) ?? "") : "";
  const sedeNom = persona?.sede_base_id ? (sedeNombreMap.get(persona.sede_base_id) ?? "") : "";
  // La ciudad donde se firma. Viene de la sede cuando la sede ES un local
  // (tienda, taller); Central no lo es —es una clasificación de personal
  // administrativo, y esa gente puede estar en cualquier ciudad (0282)—, así
  // que ahí se elige a mano. Editable siempre: un contrato puede firmarse en
  // otra ciudad por una razón puntual, y eso no debería obligar a tocar la sede.
  const ciudadDeLaSede = persona?.sede_base_id
    ? (sedes.find((s) => s.id === persona.sede_base_id)?.ciudad ?? null)
    : null;
  const ciudadFinal = (ciudadEditada.trim() || ciudadDeLaSede) ?? null;
  const esAdendum = tipoEfectivo === "adendum";
  const esConvenio = tipoEfectivo === "convenio_practicas";
  // Un indefinido no tiene causa objetiva (no es modalidad temporal) ni fecha
  // de fin — comparte todo lo demás con el contrato a plazo fijo (0347).
  const esIndefinido = tipoEfectivo === "indefinido";

  /**
   * LOS PASOS DEL STEPPER (rediseño, Fase 2). Cada tipo de documento tiene su
   * propia forma — un adendum no tiene "Funciones y activos", un convenio no
   * tiene "Causa objetiva" — así que la lista se arma según `tipoEfectivo`,
   * nunca fija. Ninguno de estos pasos agrega un campo nuevo: cada uno
   * agrupa exactamente los campos que el formulario largo ya mostraba juntos
   * antes del rediseño (ver más abajo, en el render).
   */
  const pasosGenerador: { id: string; etiqueta: string }[] = !persona
    ? [{ id: "persona", etiqueta: "Persona y documento" }]
    : esAdendum
      ? [
          { id: "persona", etiqueta: "Persona y documento" },
          { id: "vigencia", etiqueta: "Vigencia" },
          { id: "contenido", etiqueta: "Qué se modifica" },
          { id: "revision", etiqueta: "Revisión" },
        ]
      : esConvenio
        ? [
            { id: "persona", etiqueta: "Persona y documento" },
            { id: "vigencia", etiqueta: "Vigencia" },
            { id: "academico", etiqueta: "Datos académicos" },
            { id: "plan", etiqueta: "Plan formativo y activos" },
            { id: "revision", etiqueta: "Revisión" },
          ]
        : [
            { id: "persona", etiqueta: "Persona y documento" },
            { id: "vigencia", etiqueta: "Vigencia" },
            // Un indefinido no tiene causa objetiva (0347) — el paso no
            // existe para él, no se muestra vacío.
            ...(esIndefinido ? [] : [{ id: "causa", etiqueta: "Causa objetiva" }]),
            { id: "funciones", etiqueta: "Funciones y activos" },
            { id: "revision", etiqueta: "Revisión" },
          ];
  // `paso` guarda el id, así que si cambió el tipo y ese id ya no existe en
  // la lista vigente, cae al primero — sin efecto que lo corrija (ver la
  // declaración de `paso` más arriba).
  const indicePaso = Math.max(
    0,
    pasosGenerador.findIndex((p) => p.id === paso),
  );
  const pasoActual = pasosGenerador[indicePaso]?.id ?? "persona";

  /**
   * El Anexo IV de activos, rediseñado como dos opciones en vez de una
   * casilla suelta con un textarea al lado (spec §13) — usado igual en
   * "Plan formativo y activos" (convenio) y en "Funciones y activos" (el
   * resto). Es el MISMO estado de siempre (`sinActivosAdicionales`,
   * `activosLibre`) y la MISMA validación (`bloqueos`, sin tocar); solo
   * cambia cómo se elige.
   *
   * Ninguna de las dos opciones nace marcada: `sinActivosAdicionales` arranca
   * en `false` (ver `camposIniciales`) por una regla de Felipe que sigue
   * vigente acá — declarar "no tiene activos" es una decisión activa, nunca
   * un default silencioso. Mientras no se decide nada, el textarea queda
   * visible y vacío, que es precisamente lo que capturan los bloqueos.
   */
  function renderActivos(nombrePersona: string) {
    return (
      <div>
        <span className="text-sm text-taupe">Activos asignados</span>
        <div className="mt-1 grid gap-2 sm:grid-cols-2">
          <label
            className={`flex cursor-pointer items-center gap-2 rounded-lg border p-3 text-sm transition-colors duration-150 ${
              sinActivosAdicionales ? "border-rojo bg-rojo/5" : "border-sand hover:bg-hueso/60"
            }`}
          >
            <input
              type="radio"
              name="activos-asignados"
              className="accent-tinta"
              checked={sinActivosAdicionales}
              onChange={() => {
                setSinActivosAdicionales(true);
                setActivosLibre("");
              }}
            />
            No tiene activos adicionales
          </label>
          <label
            className={`flex cursor-pointer items-center gap-2 rounded-lg border p-3 text-sm transition-colors duration-150 ${
              !sinActivosAdicionales ? "border-rojo bg-rojo/5" : "border-sand hover:bg-hueso/60"
            }`}
          >
            <input
              type="radio"
              name="activos-asignados"
              className="accent-tinta"
              checked={!sinActivosAdicionales}
              onChange={() => setSinActivosAdicionales(false)}
            />
            Tiene activos específicos
          </label>
        </div>
        {!sinActivosAdicionales && (
          <AreaTexto
            etiqueta={`Activos de ${nombrePersona} — uno por línea`}
            className="mt-2"
            rows={2}
            value={activosLibre}
            onChange={(e) => setActivosLibre(e.target.value)}
          />
        )}
      </div>
    );
  }

  // `coalesce(sede_fisica, sede_base)` — el mismo criterio de
  // `fn_planilla_calcular` (0166). Leerlo solo de la sede base le imprimía a
  // quien tiene base Central y trabaja en AQP la tarifa de Central, que no
  // existe, y el contrato salía prometiendo S/ 0.00 de movilidad.
  const movilidadTarifa = persona ? tarifaDeSede(persona.sede_fisica_id ?? persona.sede_base_id) : null;

  // ── LO QUE YA TIENE, Y QUE HACE QUE ESTE DOCUMENTO SOBRE ──────────────────
  //
  // El accidente que esto cierra está en el archivo: el 4 de setiembre de 2026
  // la misma persona quedó con DOS convenios idénticos —mismo tipo, mismas
  // fechas, los dos sin firmar—, porque nada en esta pantalla distinguía
  // «generar el suyo» de «generar uno más». Un documento sin firmar no es un
  // documento: es un borrador, y un borrador se corrige, no se duplica. Que
  // haya dos con el mismo periodo no es desorden de archivo — es dos papeles
  // que dicen a la vez qué se le debe a una persona.
  //
  // Los anulados no cuentan: anular es exactamente cómo dice este sistema «este
  // ya no vale» (acá nada se borra, se marca). Y el que se está editando
  // tampoco se cuenta contra sí mismo.
  // El que se acaba de generar tampoco cuenta contra sí mismo: `borrador.id`
  // es su id desde que `generarBorrador` lo guarda, y el formulario sigue
  // mostrando la misma persona/tipo/fechas para poder imprimirlo — sin este
  // descarte, el candado de arriba se disparaba contra el documento que
  // acababa de crear, como si fuera un segundo borrador. `borrador` se pone en
  // null en cuanto se toca cualquier campo (ver el efecto de arriba), así que
  // esto deja de aplicar apenas se intenta generar uno de verdad.
  const vivosDeLaPersona = persona
    ? contratos.filter(
        (c) => c.persona_id === persona.id && !c.anulado_at && c.id !== editando?.id && c.id !== borrador?.id,
      )
    : [];
  // CAMBIO (0430): antes medía `!c.storage_path` («sin escaneo»). Con la firma
  // digital, un contrato puede estar firmado y vigente SIN escaneo — medido
  // así, ese contrato ya firmado se seguía contando como "borrador" y esta
  // pantalla ofrecía editarlo o lo trataba como duplicado de un tipo que en
  // realidad ya estaba cerrado. El criterio real de "sigue siendo un
  // borrador" siempre fue `fecha_firma is null`, el mismo que ya usa el
  // servidor (`fn_contrato_firmado_vigente_de`, 0312).
  const borradoresVivos = vivosDeLaPersona.filter((c) => !c.fecha_firma);
  const borradorMismoTipo = borradoresVivos.find((c) => c.tipo === tipoEfectivo) ?? null;
  // El solape mira TAMBIÉN los firmados: dos papeles que cubren los mismos días
  // son el problema, esté uno firmado o no. El adendum queda fuera por los dos
  // lados — no define un vínculo, MODIFICA el que ya existe, así que se monta
  // sobre su contrato por definición y solaparse es lo que le toca.
  //
  // AL CORREGIR, LA PANTALLA AFLOJA IGUAL QUE EL SERVIDOR, y esto no es un
  // detalle: con dos borradores pisados —el caso que motiva todo esto— cada uno
  // pisa al otro, así que exigir aquí lo mismo que al generar dejaría los dos
  // sin poder arreglarse. La trampa se cerraría justo sobre los datos que esto
  // viene a rescatar, y se descubrió mirándolo en el navegador con los dos
  // convenios delante. `fn_contrato_editar` mide contra los FIRMADOS y nada
  // más; aquí, lo mismo — y "firmado" (0430) es `fecha_firma`, no `storage_path`.
  const candidatosASolape = vivosDeLaPersona.filter(
    (c) => c.tipo !== "adendum" && (!editando || c.fecha_firma !== null),
  );
  const solapado =
    persona && !esAdendum && fechaInicio && (fechaFin || esIndefinido)
      ? (candidatosASolape.find((c) =>
          seSolapan(c.fecha_inicio, c.fecha_fin, fechaInicio, esIndefinido ? null : fechaFin),
        ) ?? null)
      : null;

  /** «Convenio de prácticas del 3/09/2026 al 3/12/2026», para nombrar uno en una frase. */
  function describir(c: ContratoFila): string {
    const t = TIPO_CONTRATO[c.tipo] ?? c.tipo;
    return c.fecha_fin
      ? `${t} del ${formatearFecha(c.fecha_inicio)} al ${formatearFecha(c.fecha_fin)}`
      : `${t} desde el ${formatearFecha(c.fecha_inicio)}`;
  }

  // Un indefinido no exige fechaFin — es justamente lo que no tiene (0347).
  const datosParaGenerar: DatosContrato | null =
    persona &&
    datoPersonal?.nombre_dni &&
    persona.documento &&
    salarioVigente !== null &&
    fechaInicio &&
    (fechaFin || esIndefinido)
      ? {
          tipo: tipoEfectivo,
          nombreDni: datoPersonal.nombre_dni,
          documento: persona.documento,
          direccion: datoPersonal.direccion,
          genero: datoPersonal.genero === "masculino" ? "masculino" : datoPersonal.genero === "femenino" ? "femenino" : null,
          cargo: cargoEditado || persona.cargo || "",
          email: persona.email,
          sedeNombre: sedeNom,
          sedeCodigo: sedeCod,
          ciudad: ciudadFinal,
          causaObjetivaTexto: causaEditada,
          funcionesTexto: funcionesEditadas,
          fechaInicio,
          fechaFin,
          fechaIngresoOriginal: persona.fecha_ingreso,
          remuneracionMensual: salarioVigente,
          cobraMovilidad: persona.cobra_movilidad,
          movilidadDiaria: movilidadTarifa,
          bonoOnomastico: bonoOnomastico ?? 0,
          ritVersion: ritVersion ?? "[sin publicar en el sistema]",
          ritFecha: ritFecha ?? "[sin publicar en el sistema]",
          activosPrincipales: sedeCod ? (ACTIVOS_PRINCIPALES_POR_SEDE[sedeCod] ?? "") : "",
          activosLibre,
          adendumTexto: adendumEditado,
          firmanteNombre: firmante.nombre,
          firmanteDni: firmante.dni,
          firmanteCargo: firmante.cargo,
          practicanteModalidad: modalidadEfectiva,
          horasSemanalesPactadas: horasConvenioNumero,
          rmvVigente,
          planCapacitacionTexto: planCapacitacionEditado,
          centroFormacionNombre: centroFormacionNombreEditado.trim() || null,
          centroFormacionRuc: centroFormacionRucEditado.trim() || null,
          centroFormacionDomicilio: centroFormacionDomicilioEditado.trim() || null,
          centroFormacionRepresentanteNombre: centroFormacionRepresentanteNombreEditado.trim() || null,
          centroFormacionRepresentanteCargo: centroFormacionRepresentanteCargoEditado.trim() || null,
          carreraEspecialidad: carreraEspecialidadEditada.trim() || null,
          cicloAcademico: cicloAcademicoEditado.trim() || null,
          gradoTituloTexto: gradoTituloTextoEditado.trim() || null,
          // Estos cinco van dentro de una frase o de un «Etiqueta: valor» en
          // un solo párrafo. Desde que se escriben en un AreaTexto admiten
          // Enter, y un Enter final —el gesto natural al terminar— salía como
          // «Proyecto ERP , en el puesto» y un campo con solo «⏎» pasaba por
          // lleno. Se aplanan a una línea, igual que se leerán.
          areaProyecto: unaLinea(areaProyectoEditado),
          objetivoFormativoGeneral: unaLinea(objetivoFormativoGeneralEditado),
          supervisorAsignado: unaLinea(supervisorAsignadoEditado),
        }
      : null;

  // Campos que un olvido puede dejar exactamente iguales a como empezaron — y
  // un campo sin tocar no debe poder imprimirse como si fuera una respuesta.
  // Decisión de Felipe (2026-08-19).
  const bloqueos: string[] = [];
  // ── Los dos candados contra el duplicado (0388) ───────────────────────────
  // Van primero: si uno de estos dos habla, ninguno de los de abajo importa —
  // el documento entero sobra. Se dicen igual acá aunque la tarjeta de arriba
  // ya los explique con botones, porque esta lista es la que apaga el botón y
  // la que se lee cuando se llegó al final del formulario sin mirar arriba.
  //
  // Quien manda de verdad no es esto: es `fn_contrato_registrar`, que rechaza
  // lo mismo aunque la llamada no venga de esta pantalla.
  // El candado del borrador duplicado es SOLO al generar: corregir no crea nada,
  // y el otro borrador —que sigue anunciado en la tarjeta de arriba, con su
  // «Anular» al lado— es un problema aparte, no una razón para no poder tocar
  // este.
  if (persona && !editando && borradorMismoTipo) {
    bloqueos.push(
      `${persona.nombres} ya tiene un ${(TIPO_CONTRATO[borradorMismoTipo.tipo] ?? borradorMismoTipo.tipo).toLowerCase()} sin firmar (${describir(borradorMismoTipo)}). Edítalo o anúlalo — no se generan dos.`,
    );
  }
  if (persona && solapado) {
    bloqueos.push(
      `Estas fechas se pisan con un documento que sigue vigente: ${describir(solapado)}${solapado.fecha_firma ? ", ya firmado" : ", sin firmar"}. Cambia las fechas, o anúlalo si ya no vale.`,
    );
  }
  // Estos cuatro son los que dejan `datosParaGenerar` en null: sin ellos el
  // botón se apaga sin ninguna de las líneas rojas de abajo, y quien llena el
  // formulario de la derecha no tiene forma de saber que el problema está en
  // datos que se cargan en OTRA pantalla. Se ven en el resumen (DNI, Nombre
  // legal, Sueldo base vigente) pero un dato en gris no explica que bloquea.
  if (persona && !persona.documento) {
    bloqueos.push("Carga el DNI en Datos personales — sin DNI no se puede generar el contrato.");
  }
  if (persona && !datoPersonal?.nombre_dni) {
    bloqueos.push('Carga el nombre completo (como en el DNI) en Datos personales — sin él no se puede generar el contrato.');
  }
  // El domicilio del trabajador va en la cláusula de identificación de las
  // partes ("...con domicilio en X..."), en el contrato general y en el
  // convenio por igual. Sin este candado se imprimía sin esa frase, sin que
  // nadie lo notara antes de firmar — igual que pasaba con el correo. El
  // adendum no lo necesita: no repite la identificación de las partes.
  if (persona && !esAdendum && !datoPersonal?.direccion) {
    bloqueos.push("Carga el domicilio en Datos personales — el contrato debe consignar el domicilio del trabajador.");
  }
  // El Anexo III (Domicilio Electrónico) fija el correo de LA COLABORADORA o
  // LA PRACTICANTE como domicilio válido para notificaciones — incluida la
  // entrega del RIT en el contrato general. Sin este candado se imprimía
  // como "[completar]" sin que nadie lo notara antes de firmar. El adendum
  // no lo necesita: modifica un contrato que ya lo tiene, no repite anexos.
  if (persona && !esAdendum && !persona.email) {
    bloqueos.push("Carga el correo electrónico en Equipo — el Anexo III (Domicilio Electrónico) lo necesita para notificaciones válidas.");
  }
  if (persona && salarioVigente === null) {
    bloqueos.push("No tiene un sueldo vigente asignado en Equipo — sin sueldo no se puede generar el contrato.");
  }
  if (persona && !fechaInicio) {
    bloqueos.push("Elige la fecha de inicio.");
  }
  if (persona && !esIndefinido && !fechaFin) {
    bloqueos.push("Elige la fecha de fin.");
  }
  // El input ya trae `min={fechaInicio}`, pero eso no borra un valor que
  // quedó cargado ANTES de mover la fecha de inicio — hace falta el mismo
  // candado acá, con un mensaje que diga cuál de las dos fechas está mal (el
  // error del servidor no lo dice).
  if (persona && !esIndefinido && fechaInicio && fechaFin && fechaFin < fechaInicio) {
    bloqueos.push("La fecha de fin no puede ser anterior a la fecha de inicio.");
  }
  if (persona && esAdendum && adendumEditado.trim() === "") {
    bloqueos.push("Escribe qué se modifica del contrato vigente.");
  }
  // Igualdad exacta contra el relleno NO basta: borrar el textarea —el gesto
  // natural antes de escribir— deja "" , que no es el placeholder, y el Anexo I
  // salía en blanco. Un anexo de funciones vacío es el que se cita («la función
  // 14 del Anexo I») el día que haya que sustentar un incumplimiento.
  if (persona && !esAdendum && !esConvenio && (funcionesEditadas.trim() === FUNCIONES_PLACEHOLDER || funcionesEditadas.trim() === "")) {
    bloqueos.push('Completa "Funciones del cargo" — está vacío o sigue con el texto de relleno.');
  }
  // La causa objetiva arranca con una nota dirigida a quien usa el panel. Esa
  // nota entra TAL CUAL a la cláusula PRIMERA (`<p>${d.causaObjetivaTexto}</p>`):
  // un contrato firmado que lleva dentro «[REVISAR antes de imprimir…]» no solo
  // queda en ridículo, debilita justo la cláusula que sustenta la modalidad
  // temporal ante una inspección. Ni un convenio ni un indefinido usan
  // `causaObjetivaTexto` (no tienen causa objetiva — uno no es contrato de
  // trabajo, el otro no es modalidad temporal), así que esta nota de relleno
  // no es asunto suyo.
  if (persona && !esConvenio && !esIndefinido && causaEditada.includes("[REVISAR")) {
    bloqueos.push("Revisa y quita la nota «[REVISAR antes de imprimir…]» de la causa objetiva.");
  }
  // Un beneficio con monto es un monto REAL o no se imprime. Sin tarifa vigente
  // el contrato decía «asignación diaria de movilidad (S/ 0.00)», que promete
  // por escrito un beneficio de cero. Ninguno de los dos aplica a un convenio:
  // movilidad y bono de onomástico son beneficios de planilla (en_planilla),
  // y una practicante no está en planilla (0322).
  if (persona && !esAdendum && !esConvenio && persona.cobra_movilidad && movilidadTarifa === null) {
    bloqueos.push("No hay tarifa de movilidad vigente para su sede: publícala antes de generar el contrato.");
  }
  if (persona && !esAdendum && !esConvenio && !(bonoOnomastico && bonoOnomastico > 0)) {
    bloqueos.push("No hay monto vigente del bono de onomástico: publícalo antes de generar el contrato.");
  }
  // Las dos exclusiones de pago que el texto no sabe describir todavía. El
  // contrato les promete jornada de 48 h con sobretiempo al 25 %/35 % y pago
  // proporcional a las horas; a personal de dirección la ley lo excluye
  // (art. 5, D.S. 007-2002-TR) y a sueldo fijo su pago no depende de horas.
  // Se bloquea en vez de improvisar un texto: un contrato es para firmarlo.
  // Un convenio nunca declara jornada de 48h fija con sobretiempo — su
  // cláusula de jornada ya depende de la modalidad, no de estos dos flags.
  if (persona && !esAdendum && !esConvenio && persona.personal_direccion) {
    bloqueos.push("Está marcada como personal de dirección: el texto de jornada y sobretiempo no le corresponde. Revísalo con criterio legal antes de generar.");
  }
  if (persona && !esAdendum && !esConvenio && persona.sueldo_fijo) {
    bloqueos.push("Cobra sueldo fijo: la cláusula de remuneración proporcional a las horas no le corresponde. Revísalo con criterio legal antes de generar.");
  }
  // CAMBIO — el Anexo IV se imprime igual para un convenio (contrato-texto.ts
  // incluye anexoIV(d, "LA PRACTICANTE") también ahí), con el mismo fallback
  // silencioso a "no tiene activos adicionales" si el campo llega vacío. Antes
  // esta validación excluía `esConvenio` a propósito, así que ese texto se
  // podía imprimir sin que nadie lo hubiera confirmado.
  if (persona && !esAdendum && activosLibre.trim() === "" && !sinActivosAdicionales) {
    bloqueos.push("Marca la casilla de activos, o completa el ajuste específico del Anexo IV.");
  }
  // ── Lo que sí exige un convenio, y nada de lo anterior sabe pedir ─────────
  if (persona && esConvenio && planCapacitacionEditado.trim() === "") {
    bloqueos.push("Completa el plan de capacitación específico — un convenio no tiene funciones, tiene un plan de capacitación (Ley 28518, art. 15).");
  }
  if (persona && esConvenio && modalidadEfectiva === null) {
    bloqueos.push(
      persona.tipo_vinculo === "practicante"
        ? "Asígnale modalidad (preprofesional o profesional) en Equipo antes de generar su convenio — decide su jornada máxima (30h/48h)."
        : "Elige la modalidad (preprofesional o profesional) — decide su jornada máxima (30h/48h).",
    );
  }
  // CAMBIO (auditoría 2026-09-14, hallazgo #1): antes exigía SIEMPRE una RMV
  // completa, para cualquier modalidad. El artículo 45 de la Ley 28518 compara
  // contra "la jornada máxima prevista para CADA modalidad formativa" — 30h
  // para preprofesional (art. 44), no 48h — y solo prorratea a quien trabaja
  // MENOS que el tope de SU propia modalidad. Mismo cálculo que hace el texto
  // del convenio (`documentoConvenio`, contrato-texto.ts) para no poder
  // decirse a sí mismo dos cosas distintas.
  if (
    persona &&
    esConvenio &&
    modalidadEfectiva === "preprofesional" &&
    horasConvenioEditadas.trim() !== "" &&
    !(Number(horasConvenioEditadas) > 0 && Number(horasConvenioEditadas) <= 30)
  ) {
    bloqueos.push("Las horas semanales pactadas deben ser un número mayor que 0 y hasta 30 — el tope de la modalidad preprofesional (art. 44, Ley 28518).");
  }
  const pisoSubvencion =
    modalidadEfectiva === "preprofesional" && horasConvenioNumero !== null && rmvVigente !== null
      ? (rmvVigente * horasConvenioNumero) / 30
      : rmvVigente;
  if (persona && esConvenio && salarioVigente !== null && pisoSubvencion !== null && salarioVigente < pisoSubvencion) {
    bloqueos.push(
      horasConvenioNumero !== null && horasConvenioNumero < 30
        ? `La subvención (S/ ${salarioVigente.toFixed(2)}) está por debajo del piso proporcional a sus ${horasConvenioNumero} horas semanales pactadas (S/ ${pisoSubvencion.toFixed(2)} de la RMV vigente) — Ley 28518, art. 45.`
        : `La subvención (S/ ${salarioVigente.toFixed(2)}) está por debajo de la RMV vigente (S/ ${pisoSubvencion.toFixed(2)}) — Ley 28518, art. 45: le corresponde completa a quien cumple la jornada máxima de su modalidad.`,
    );
  }
  // Estos campos no tenían bloqueo (hallazgo #11, auditoría 2026-09-03/04):
  // vacíos, `contrato-texto.ts` los imprime tal cual como «[completar]» dentro
  // de una cláusula real del convenio o del Anexo I — no en un aparte, sino en
  // el cuerpo que las partes firman. `gradoTituloTexto` queda afuera a
  // propósito: su propia etiqueta en el formulario lo marca "referencial", no
  // una declaración que el centro de formación firme.
  if (persona && esConvenio && modalidadEfectiva === "preprofesional") {
    if (centroFormacionNombreEditado.trim() === "") {
      bloqueos.push("Completa la razón social del centro de formación.");
    }
    if (centroFormacionRucEditado.trim() === "") {
      bloqueos.push("Completa el RUC del centro de formación.");
    }
    if (centroFormacionDomicilioEditado.trim() === "") {
      bloqueos.push("Completa el domicilio del centro de formación.");
    }
    if (centroFormacionRepresentanteNombreEditado.trim() === "") {
      bloqueos.push("Completa el nombre del representante del centro de formación.");
    }
    if (centroFormacionRepresentanteCargoEditado.trim() === "") {
      bloqueos.push("Completa el cargo del representante del centro de formación.");
    }
    if (carreraEspecialidadEditada.trim() === "") {
      bloqueos.push("Completa la carrera / especialidad de la practicante.");
    }
    if (cicloAcademicoEditado.trim() === "") {
      bloqueos.push("Completa el ciclo académico de la practicante.");
    }
  }
  if (persona && esConvenio && areaProyectoEditado.trim() === "") {
    bloqueos.push("Completa el área / proyecto de destino (Anexo I).");
  }
  if (persona && esConvenio && objetivoFormativoGeneralEditado.trim() === "") {
    bloqueos.push("Completa el objetivo formativo general del Anexo I.");
  }
  if (persona && esConvenio && supervisorAsignadoEditado.trim() === "") {
    bloqueos.push("Completa el/la supervisor(a) asignado(a) del Anexo I.");
  }
  // La ciudad no bloquea —el documento lo dice en su propio texto— pero avisar
  // acá evita descubrirlo recién al leer el PDF impreso.
  if (persona && !ciudadFinal) {
    bloqueos.push("Escribe la ciudad donde se firma el contrato.");
  }
  // EL TOPE DE LA MODALIDAD. El contrato se emite siempre bajo el art. 57 del
  // TUO del D. Leg. 728 —«inicio o incremento de actividad»—, y esa modalidad
  // tiene un máximo de TRES años; el art. 74 pone cinco al conjunto de
  // contratos sujetos a modalidad con el mismo empleador. Pasado el tope, el
  // art. 77 desnaturaliza el vínculo a indefinido POR LEY, sin que nadie lo
  // decida y sin que nada en el sistema lo dijera: `fn_contratos_desnaturalizados`
  // solo mira quien marcó DESPUÉS de su fecha de fin, no la acumulación.
  //
  // Avisa, no bloquea: renovar pasado el tope puede ser una decisión tomada a
  // sabiendas, y quien la tome tiene que verlo escrito antes de firmar.
  const avisos: string[] = [];
  if (persona && !esAdendum && !esConvenio && !esIndefinido && fechaFin) {
    const anios = (new Date(`${fechaFin}T00:00:00`).getTime() - new Date(`${persona.fecha_ingreso}T00:00:00`).getTime()) / 31_557_600_000;
    if (anios > 5) {
      avisos.push(`Al terminar este contrato acumularía ${anios.toFixed(1)} años a plazo fijo, sobre el tope de CINCO del artículo 74. El vínculo quedaría desnaturalizado a indefinido por el artículo 77.`);
    } else if (anios > 3) {
      avisos.push(`Al terminar este contrato acumularía ${anios.toFixed(1)} años bajo la modalidad del artículo 57, cuyo máximo es de TRES. Conviene cambiar de modalidad o pasar a indefinido.`);
    }
  }
  // El tope del convenio (12 meses continuos, Ley 28518 art. 30 y ss.) tiene
  // una excepción legal real —que el centro de formación determine una
  // extensión mayor— que este sistema no puede verificar solo. Avisa, no
  // bloquea: mismo criterio que ya eligió la 0324 para la jornada 30h/48h
  // ("Dynamic avisa, nunca sanciona solo").
  //
  // CAMBIO (auditoría 2026-09-14): antes medía solo la duración de ESTE
  // tramo (`fechaFin - fechaInicio`), así que una renovación corta después de
  // convenios anteriores largos salía "dentro del tope" aunque lo acumulado
  // ya lo hubiera pasado — el mismo defecto que el tablero (0336) ya había
  // cerrado, pero sin que este aviso lo heredara. Ahora usa la misma fórmula
  // que `fn_contratos_tablero`: el tope se mide desde `fecha_ingreso`, no
  // desde el inicio de este convenio puntual.
  if (persona && esConvenio && fechaFin) {
    const tope = topeConvenioDoceMeses(persona.fecha_ingreso);
    if (fechaFin > tope) {
      avisos.push(`La fecha de fin (${formatearFecha(fechaFin)}) supera el tope legal de doce meses continuos desde su ingreso (${formatearFecha(persona.fecha_ingreso)} → tope ${formatearFecha(tope)}), el mismo cálculo que usa el tablero. Solo es válido si el centro de formación sustenta por escrito una extensión mayor (Ley 28518, art. 30) — de lo contrario, arriesga desnaturalización.`);
    }
  }

  async function generarBorrador() {
    if (!datosParaGenerar || !persona) {
      avisar(
        "error",
        "Faltan datos para generar el contrato: revisa DNI, nombre legal (Ficha personal), sueldo vigente y las fechas.",
      );
      return;
    }
    if (bloqueos.length > 0) {
      avisar("error", bloqueos[0]);
      return;
    }
    setGenerando(true);
    const html = construirContrato(datosParaGenerar);
    const { data: id, error } = await supabase.rpc("fn_contrato_registrar", {
      p_persona_id: persona.id,
      p_tipo: datosParaGenerar.tipo,
      p_cargo: datosParaGenerar.cargo,
      p_sede_id: persona.sede_base_id,
      p_remuneracion_mensual: datosParaGenerar.remuneracionMensual,
      p_fecha_inicio: fechaInicio,
      // Un indefinido nunca lleva fecha de fin (0347) — fn_contrato_registrar
      // la rechaza si no es null para ese tipo.
      p_fecha_fin: esIndefinido ? null : fechaFin,
      // La jornada de un contrato de trabajo es siempre 48h (ver
      // contrato-texto.ts); no hay un número calculado del horario que
      // guardar acá. Solo el convenio preprofesional declara algo distinto de
      // su tope de modalidad (auditoría 2026-09-14, hallazgo #1) — y solo
      // cuando de verdad se pactó menos: `null` sigue significando "a su
      // jornada completa", igual que antes de este campo.
      p_horas_semanales: esConvenio ? horasConvenioNumero : null,
      p_documento_html: html,
      // La foto de lo tecleado, para poder reabrir este borrador y corregirlo
      // (0388) en vez de generar otro al lado.
      p_datos_formulario: camposActuales(),
    });
    setGenerando(false);
    if (error || !id) {
      avisar("error", mensajeDeError(error, "generar el contrato"));
      return;
    }
    // Identificar a la persona como practicante nace AQUÍ, al generar el
    // convenio — no al firmarlo. Solo aplica cuando la modalidad se eligió a
    // mano (la ficha todavía no dice tipo_vinculo=practicante): si ya lo dice,
    // `modalidadManualEditada` ni se muestra y esto no tiene nada que hacer.
    // Usa las mismas funciones guardián de Equipo (0324), así que el cambio
    // queda auditado en correcciones_auditoria igual que uno hecho a mano.
    let avisoModalidad = "";
    if (datosParaGenerar.tipo === "convenio_practicas" && aplicarModalidadFicha && modalidadManualEditada) {
      const { error: errorVinculo } = await supabase.rpc("fn_set_tipo_vinculo", {
        p_persona_id: persona.id,
        p_tipo: "practicante",
      });
      const { error: errorModalidad } = errorVinculo
        ? { error: errorVinculo }
        : await supabase.rpc("fn_set_practicante_modalidad", {
            p_persona_id: persona.id,
            p_modalidad: modalidadManualEditada,
          });
      avisoModalidad = errorVinculo || errorModalidad
        ? ` Ojo: no se pudo aplicar la modalidad a su ficha (${mensajeDeError(errorVinculo ?? errorModalidad, "actualizar Equipo")}) — hazlo a mano en Equipo.`
        : ` Se marcó a ${persona.nombres} ${persona.apellidos} como practicante ${modalidadManualEditada} en su ficha, así que Incidencias ya avisa contra su tope de horas.`;
    }
    // Se abre en el visor, que desde el 2026-09-08 es el único sitio donde se
    // ve un contrato. Sin firma del colaborador: acaba de nacer, nadie la ha
    // confirmado todavía.
    setFirmaPersonaAbierta(null);
    setDocumentoAbierto(html);
    setBorrador({ id: id as string, html });
    await cargar();
    avisar(
      "ok",
      `Borrador generado. Revísalo, imprímelo y fírmalo; después sube el escaneo desde el historial.${avisoModalidad}`,
    );
  }

  /**
   * Abre un borrador para corregirlo EN SU SITIO, sin generar otro.
   *
   * Solo un borrador. Un contrato con escaneo firmado NO se edita nunca: lo que
   * vale es el papel que las dos partes firmaron, y cambiarle el texto por
   * detrás dejaría al sistema diciendo una cosa y al archivador otra. Para
   * corregir algo firmado están las dos puertas de siempre — el adendum, que
   * modifica sin negar, y la anulación con motivo. `fn_contrato_editar` lo
   * rechaza igual aunque alguien llegue por otro camino.
   */
  async function empezarEdicion(c: ContratoFila) {
    const { data, error } = await supabase
      .from("contratos_generados")
      .select("datos_formulario")
      .eq("id", c.id)
      .maybeSingle();
    if (error || !data) {
      avisar("error", mensajeDeError(error, "abrir el borrador"));
      return;
    }
    const foto = (data as { datos_formulario: DatosFormulario | null }).datos_formulario;
    const p = personas.find((x) => x.id === c.persona_id);
    if (!p) {
      avisar("error", "Esa persona ya no está activa: su borrador no se puede editar.");
      return;
    }

    setDocumentoAbierto(null);
    setBorrador(null);
    setGeneradorAbierto(true);
    // `editando` se fija ANTES que `personaId`/`tipo` en el mismo lote, así que
    // los dos efectos de repoblado ya lo ven puesto y se apartan.
    setEditando(c);
    setEdicionSinFoto(foto === null);
    setPersonaId(c.persona_id);
    setTipo(c.tipo as "nuevo" | "renovacion" | "adendum" | "convenio_practicas" | "indefinido");
    setFechaInicio(c.fecha_inicio);
    setFechaFin(c.fecha_fin ?? "");
    aplicarCampos(
      foto ??
        camposIniciales(
          p,
          p.sede_base_id ? (sedeNombreMap.get(p.sede_base_id) ?? "") : "",
          p.sede_base_id ? (sedeCiudadMap.get(p.sede_base_id) ?? null) : null,
        ),
    );
    avisar("ok", "Borrador abierto para editar. Al guardar se reemplaza su texto — no se crea otro.");
  }

  /** Sale del modo edición y deja el formulario limpio, sin persona elegida. */
  function cancelarEdicion() {
    setEditando(null);
    setEdicionSinFoto(false);
    setPersonaId("");
    setBorrador(null);
    setDocumentoAbierto(null);
    setGeneradorAbierto(false);
  }

  async function guardarEdicion() {
    if (!editando || !datosParaGenerar || !persona) {
      avisar("error", "Faltan datos para guardar: revisa DNI, nombre legal, sueldo vigente y las fechas.");
      return;
    }
    if (bloqueos.length > 0) {
      avisar("error", bloqueos[0]);
      return;
    }
    setGuardandoEdicion(true);
    const html = construirContrato(datosParaGenerar);
    // `fn_contrato_editar` (0388) no recibe `p_horas_semanales` — cambiarle la
    // firma es una migración, fuera del alcance acordado para el hallazgo #1
    // (auditoría 2026-09-14). El texto que se reimprime SÍ queda correcto
    // (`html` ya usa las horas de `datosParaGenerar`) y `datos_formulario` SÍ
    // guarda el número tecleado para la próxima vez que se reabra o se reuse
    // — lo único que no se actualiza es la columna `contratos_generados.
    // horas_semanales`, que hoy no lee nadie más. Si el día de mañana algo
    // más empieza a leerla, esto necesita su propia migración.
    const { error } = await supabase.rpc("fn_contrato_editar", {
      p_id: editando.id,
      p_tipo: datosParaGenerar.tipo,
      p_cargo: datosParaGenerar.cargo,
      p_remuneracion_mensual: datosParaGenerar.remuneracionMensual,
      p_fecha_inicio: fechaInicio,
      p_fecha_fin: esIndefinido ? null : fechaFin,
      p_documento_html: html,
      p_datos_formulario: camposActuales(),
    });
    setGuardandoEdicion(false);
    if (error) {
      avisar("error", mensajeDeError(error, "guardar el borrador"));
      return;
    }
    setEditando(null);
    setEdicionSinFoto(false);
    setPersonaId("");
    // Igual que al generar: el aviso dice «vuelve a imprimirlo», así que el
    // documento corregido se abre en el visor en vez de mandar a buscarlo al
    // archivo. Sin firma del colaborador: si alguna vez la confirmó, ese
    // contrato ya no sería un borrador y no se estaría corrigiendo.
    setFirmaPersonaAbierta(null);
    setDocumentoAbierto(html);
    await cargar();
    avisar("ok", "Borrador corregido. Vuelve a imprimirlo antes de firmarlo — el anterior ya no vale.");
  }

  function imprimir() {
    window.print();
  }

  function abrirSubida(id: string) {
    setSubiendoPara(id);
    setArchivo(null);
    setFechaFirma(hoyLima());
  }

  async function guardarFirma() {
    if (!subiendoPara) return;
    // Se lee ANTES de llamar al servidor: después de `cargar()` el contrato
    // ya viene con el escaneo puesto, y el mensaje de abajo necesita saber
    // cómo estaba ANTES de esta acción.
    const yaFirmado = contratos.find((c) => c.id === subiendoPara)?.fecha_firma != null;
    if (!archivo) {
      avisar("error", "Falta el escaneo firmado.");
      return;
    }
    if (archivo.size > MAX_BYTES) {
      avisar("error", `"${archivo.name}" pesa ${(archivo.size / 1048576).toFixed(1)} MB y el máximo es 50 MB.`);
      return;
    }
    if (!fechaFirma) {
      avisar("error", "Indica en qué fecha se firmó.");
      return;
    }
    // Nada comparaba `fechaFirma` contra la vigencia del propio documento
    // (hallazgo de la auditoría 2026-09-14): un tipeo de año quedaba
    // guardado tal cual, sin ninguna señal. Un mes de margen antes del
    // inicio cubre el caso normal —firmar unos días antes de empezar—; después
    // del fin, ninguno: firmar un documento después de su propio término no
    // tiene un caso legítimo que este sistema conozca.
    const contratoASubir = contratos.find((c) => c.id === subiendoPara);
    if (contratoASubir && fechaFirma < sumarDias(contratoASubir.fecha_inicio, -30)) {
      avisar(
        "error",
        `La fecha de firma (${formatearFecha(fechaFirma)}) es más de un mes anterior al inicio del documento (${formatearFecha(contratoASubir.fecha_inicio)}). Revisa que sea la fecha correcta.`,
      );
      return;
    }
    if (contratoASubir?.fecha_fin && fechaFirma > contratoASubir.fecha_fin) {
      avisar(
        "error",
        `La fecha de firma (${formatearFecha(fechaFirma)}) es posterior al término del documento (${formatearFecha(contratoASubir.fecha_fin)}). Revisa que sea la fecha correcta.`,
      );
      return;
    }

    setGuardandoFirma(true);
    const ext = archivo.name.split(".").pop()?.toLowerCase() ?? "bin";
    const ruta = `contratos/${subiendoPara}.${ext}`;
    setProgreso(0);
    const fallo = await subirArchivoConProgreso(supabase, "contratos", ruta, archivo, setProgreso);
    setProgreso(null);
    if (fallo) {
      setGuardandoFirma(false);
      avisar("error", `El archivo no subió (${fallo}). Vuelve a intentarlo.`);
      return;
    }
    const { error } = await supabase.rpc("fn_contrato_registrar", {
      p_id: subiendoPara,
      p_storage_path: ruta,
      p_fecha_firma: fechaFirma,
    });
    setGuardandoFirma(false);
    if (error) {
      avisar("error", mensajeDeError(error, "registrar la firma"));
      return;
    }
    setSubiendoPara(null);
    await cargar();
    avisar(
      "ok",
      yaFirmado
        ? "Escaneo de respaldo guardado. La fecha de firma sigue siendo la de la firma digital."
        : "Contrato firmado registrado. La fecha de vencimiento de la persona se actualizó.",
    );
  }

  async function anular() {
    if (!anulando) return;
    if (motivoAnular.trim().length < 3) {
      avisar("error", "Escribe por qué se anula.");
      return;
    }
    const { error } = await supabase.rpc("fn_contrato_anular", { p_id: anulando, p_motivo: motivoAnular.trim() });
    if (error) {
      avisar("error", mensajeDeError(error, "anular el contrato"));
      return;
    }
    // Si lo que se acaba de anular es justo lo que se estaba editando, el
    // formulario deja de tener sujeto: se sale de la edición en vez de guardar
    // cambios sobre un documento que ya no vale.
    if (editando?.id === anulando) cancelarEdicion();
    setAnulando(null);
    setMotivoAnular("");
    await cargar();
    avisar("ok", "Contrato anulado. Sigue guardado en el historial.");
  }

  /**
   * Abre el texto CONGELADO de un contrato ya generado, para volver a verlo o
   * reimprimirlo. Se lee de la base y no se regenera: reconstruirlo con los
   * datos de hoy daría otro documento —el sueldo o el cargo pueden haber
   * cambiado— y el que vale es el que se imprimió y se firmó.
   */
  async function abrirGenerado(id: string) {
    const { data, error } = await supabase
      .from("contratos_generados")
      .select("documento_html, firma_persona")
      .eq("id", id)
      .maybeSingle();
    if (error || !data) {
      avisar("error", mensajeDeError(error, "abrir el contrato"));
      return;
    }
    const fila = data as { documento_html: string; firma_persona: string | null };
    setDocumentoAbierto(fila.documento_html);
    setFirmaPersonaAbierta(fila.firma_persona);
  }

  /**
   * Anota que se entregó la copia. `fn_contrato_marcar_tramite` todavía
   * acepta 'mtpe' (columna que se deja sin borrar, 0470), pero la pantalla ya
   * no ofrece marcarlo: comunicar el contrato al MTPE dejó de ser trámite de
   * nadie desde el D. Leg. 1246.
   */
  async function marcarTramite(id: string, tramite: "copia") {
    const { error } = await supabase.rpc("fn_contrato_marcar_tramite", {
      p_id: id,
      p_tramite: tramite,
      p_fecha: hoyLima(),
    });
    if (error) {
      avisar("error", mensajeDeError(error, "anotar el trámite"));
      return;
    }
    await cargar();
    avisar(
      "ok",
      tramite === "copia"
        ? "Anotada la entrega de copia a la colaboradora."
        : "Anotada la comunicación a la Autoridad Administrativa de Trabajo.",
    );
  }

  async function verDocumento(path: string) {
    const fallo = await abrirArchivoFirmado(supabase, "contratos", path);
    if (fallo) avisar("error", fallo);
  }

  /**
   * El menú "•••" de una fila de la tabla compacta. Cada opción llama a una
   * función que YA EXISTÍA (abrirGenerado, empezarEdicion, verDocumento,
   * abrirSubida, setDetalleId, setAnulando) — este menú no agrega ninguna
   * acción nueva, solo las agrupa: antes eran enlaces de texto sueltos por
   * fila en la sección "Archivo", ver más abajo.
   *
   * "Descargar" no es una acción nueva tampoco: es `verDocumento`, la misma
   * que antes decía "Ver escaneo" — abre el PDF/imagen firmado que se subió,
   * y desde ahí el navegador lo guarda. No hay, hoy, una función de servidor
   * distinta para "descargar el borrador sin firmar": eso se resuelve
   * imprimiendo a PDF desde "Ver / imprimir", como ya era.
   */
  function accionesContrato(c: ContratoFila) {
    const anulado = Boolean(c.anulado_at);
    return (
      <Menu
        trigger={({ alternar }) => (
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation();
              alternar();
            }}
            aria-label={`Más acciones para ${c.persona}`}
            className="rounded-control px-2 py-1 text-taupe transition-colors duration-150 hover:bg-sand/60 hover:text-tinta"
          >
            •••
          </button>
        )}
      >
        <MenuItem onClick={() => abrirGenerado(c.id)}>Ver / imprimir</MenuItem>
        {!anulado && !c.fecha_firma && <MenuItem onClick={() => empezarEdicion(c)}>Editar</MenuItem>}
        {!anulado && c.storage_path && (
          <MenuItem onClick={() => verDocumento(c.storage_path!)}>Descargar</MenuItem>
        )}
        {!anulado && !c.storage_path && (
          <MenuItem onClick={() => abrirSubida(c.id)}>
            {c.fecha_firma ? "Adjuntar escaneo de respaldo" : "Subir documento firmado"}
          </MenuItem>
        )}
        <MenuItem onClick={() => setDetalleId(c.id)}>Ver historial</MenuItem>
        {!anulado && (
          <MenuItem variante="peligro" onClick={() => setAnulando(c.id)}>
            Anular
          </MenuItem>
        )}
      </Menu>
    );
  }

  /**
   * El botón visible de cada fila de la lista por urgencia: la acción que ESA banda pide, para no
   * esconderla en el menú «•••» (que sigue teniendo lo demás). Ninguna es acción nueva: «Renovar» abre
   * el mismo generador que «Generar», con la persona y el tipo ya puestos; «Subir firmado» y
   * «Copia entregada» son las funciones de siempre. Las filas «al día» no llevan botón: no hay nada
   * que hacer hoy.
   */
  function accionPrincipal(estado: string, personaIdFila: string, c: ContratoFila, tipoFila: typeof tipo) {
    const boton = (texto: string, alTocar: () => void) => (
      <Boton variante="sutil" tamano="sm" onClick={(ev) => { ev.stopPropagation(); alTocar(); }}>
        {texto}
      </Boton>
    );
    const alGenerador = () => {
      setPersonaId(personaIdFila);
      setTipo(tipoFila === "nuevo" ? "renovacion" : tipoFila);
      irAlGenerador();
    };
    switch (estado) {
      case "desnaturalizado":
      case "vencido":
        return boton("Regularizar", alGenerador);
      case "por_vencer":
        return boton("Renovar", alGenerador);
      case "sin_firmar":
        return boton("Subir firmado", () => abrirSubida(c.id));
      case "tramite_pendiente":
        return boton("Copia entregada", () => void marcarTramite(c.id, "copia"));
      default:
        return null;
    }
  }

  /**
   * "+ Nuevo documento" y "Generar" (cuando alguien del tablero no tiene
   * contrato todavía) llevan los dos al mismo sitio: el generador, mostrado
   * como su propia pantalla — ver `generadorAbierto`.
   */
  function irAlGenerador() {
    setGeneradorAbierto(true);
  }

  function limpiarFiltros() {
    setBusca("");
    setFiltroSede("");
    setFiltroTipo("");
    setFiltroEstado("pendientes");
    setBandaElegida(null);
  }

  // Escape cierra el modal del documento, igual que en `components/ui/modal`.
  // Este no usa ese componente porque el suyo es de ancho fijo y no sabe nada
  // de impresión, y acá lo que se abre se manda a papel.
  useEffect(() => {
    if (!documentoAbierto) return;
    const alPulsar = (e: KeyboardEvent) => {
      if (e.key === "Escape") setDocumentoAbierto(null);
    };
    document.addEventListener("keydown", alPulsar);
    return () => document.removeEventListener("keydown", alPulsar);
  }, [documentoAbierto]);

  useTituloDocumento(persona ? `${persona.nombres} ${persona.apellidos} — Contrato de trabajo` : null);

  if (rol === null || cargando) {
    return (
      <main className="p-6">
        <Cargando />
      </main>
    );
  }
  if (!puede) {
    return (
      <main className="p-6">
        <p className="max-w-md rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
          Solo administradores y líderes pueden generar contratos.
        </p>
      </main>
    );
  }

  // Solo quien necesita algo. Un tablero donde casi todas las filas dicen «al
  // día» enseña a ignorarlo — mismo criterio que el tablero de Documentación,
  // que oculta a quien no tiene nada pendiente.
  const pendientes = tablero.filter((f) => f.estado !== "ok");

  // El buscador. Con el campo vacío pasa todo, así que la pantalla sin filtrar
  // es exactamente la de antes.
  const filtro = sinTildes(busca.trim());
  const coincide = (texto: string | null | undefined) =>
    filtro === "" || sinTildes(texto ?? "").includes(filtro);
  const pendientesVisibles = pendientes.filter((f) => coincide(f.persona) || coincide(f.sede));

  // Cuántos son de los que no pueden esperar. Decide si el contador va en rojo:
  // el rojo de esta paleta es el acento sagrado, y gastarlo en «vence en tres
  // meses» lo vuelve invisible el día que diga «desnaturalizado».
  //
  // Se cuenta sobre LO VISIBLE, no sobre el total: el número que está al lado
  // es el de las filas que se ven, y pintarlo de rojo por una urgencia que el
  // filtro acaba de esconder señalaría a quien no es.
  const graves = pendientesVisibles.filter((f) => ESTADO_TABLERO[f.estado]?.grave).length;

  // ── LOS CUATRO CONTADORES ─────────────────────────────────────────────────
  // Se cuentan sobre el tablero ENTERO, no sobre lo filtrado: son el estado del
  // mes, no de la búsqueda. Cada uno es también un botón que filtra la tabla —
  // ver un número sin poder abrir lo que hay detrás obliga a adivinar el filtro.
  //
  // «Riesgo art. 77» va primero y es el único en rojo, porque es el único que
  // cuesta plata: quien siguió marcando después de su vencimiento queda con
  // vínculo indefinido POR LEY (art. 77 del TUO del D. Leg. 728), sin que nadie
  // lo decida. Los otros tres son trámites; este es una contingencia.
  const cuenta = (e: string) => tablero.filter((f) => f.estado === e).length;
  // Las etiquetas cambian de redacción (rediseño), NUNCA de clave ni de
  // cálculo: "Riesgo art. 77" pasa a "Riesgo de continuidad" con el ⓘ que la
  // explica (se pinta más abajo), y "Sin escaneado" pasa a "Pendientes de
  // firma" — NO a "pendiente de archivo firmado" como pedía el prompt
  // original: `sin_firmar` mide falta de FIRMA (ni escaneo ni firma digital
  // confirmada, ver el comentario de `ContratoFila.fecha_firma`), no falta de
  // escaneo — un contrato puede estar firmado por autoservicio digital sin
  // ningún PDF subido. Llamarlo "archivo firmado" habría sido más confuso que
  // el texto que reemplaza, no más claro.
  // «Para atender»: cuántos hay en cada banda de urgencia, sobre el tablero ENTERO (no sobre lo filtrado: es el
  // estado del mes, no de la búsqueda). Cada pastilla filtra la lista a esa banda.
  const nBanda = (b: Banda) => tablero.filter((f) => bandaDe(f) === b).length;
  const nParaAtender = tablero.filter((f) => bandaDe(f) !== "al_dia").length;
  const nArt77 = cuenta("desnaturalizado");
  // La lista ya está mostrando solo a quienes pasaron el plazo: el ojo pasa a «quitar el filtro».
  const soloArt77 = bandaElegida === "paso" && filtroEstado === "pendientes";

  // Las sedes que de verdad aparecen, para el desplegable. Se leen del tablero
  // y no de una lista escrita a mano: la regla de la casa es que una lista de
  // algo que vive en una tabla no se escribe: se pregunta.
  const sedesEnTablero = [...new Set(tablero.map((f) => f.sede).filter((x): x is string => Boolean(x)))].sort();
  // Mismo criterio para el nuevo filtro de Tipo: se lee de lo que ya hay
  // (tablero + archivo), no de TIPO_CONTRATO completo — un tipo que nadie
  // usó todavía no debería aparecer como opción vacía en el desplegable.
  const tiposEnDatos = [
    ...new Set([...tablero.map((f) => f.tipo), ...contratos.map((c) => c.tipo)].filter((t): t is string => Boolean(t))),
  ].sort();

  // ── LAS FILAS DE LA TABLA ─────────────────────────────────────────────────
  // Parten del TABLERO, no del archivo de contratos: quien no tiene ninguno
  // generado es invisible en el archivo, y «¿a quién le falta?» es justo la
  // pregunta que se abre esta pantalla a responder.
  // Siempre la fila viva: si se anula o desaparece de la lista, el visor se
  // cierra solo en vez de quedarse enseñando algo que ya no existe.
  const detalle = detalleId ? (contratos.find((c) => c.id === detalleId) ?? null) : null;

  // "archivados" no filtra el tablero: cambia la fuente entera (ver más
  // abajo, filasArchivadas). El tablero en sí no tiene nada que mostrar ahí,
  // así que se trata como "sin filas" para no repetir el tablero completo
  // detrás de la lista de anulados.
  const filas = (filtroEstado === "archivados" ? [] : tablero)
    .filter((f) => (coincide(f.persona) || coincide(f.sede)))
    .filter((f) => filtroSede === "" || f.sede === filtroSede)
    .filter((f) => filtroTipo === "" || f.tipo === filtroTipo)
    .filter((f) => {
      if (filtroEstado === "todos") return true;
      // «Para atender» y «Al día» se reparten TODO el tablero por banda (ver contratos-bandas.ts): «en papel» es
      // historia, no urgencia, así que ya no infla lo que pide atención.
      if (filtroEstado === "pendientes") return bandaDe(f) !== "al_dia";
      if (filtroEstado === "vigentes") return bandaDe(f) === "al_dia";
      return f.estado === filtroEstado;
    })
    .filter((f) => bandaElegida === null || bandaDe(f) === bandaElegida)
    // Lo urgente arriba: primero lo grave, después por cuántos días quedan.
    .sort((a, b) => {
      const g = Number(ESTADO_TABLERO[b.estado]?.grave ?? false) - Number(ESTADO_TABLERO[a.estado]?.grave ?? false);
      if (g !== 0) return g;
      const da = a.dias_restantes ?? 99999;
      const db = b.dias_restantes ?? 99999;
      return da - db;
    });

  // LA PESTAÑA "ARCHIVADOS": los contratos anulados de gente activa — el
  // mismo conjunto que hoy vive plegado dentro de "Archivo" (más abajo), solo
  // que aquí se muestra como filas de la tabla compacta en vez de una lista
  // por persona. No es un estado nuevo: `anulado_at` ya existe y ya se usa.
  const filasArchivadas =
    filtroEstado === "archivados"
      ? contratos
          .filter((c) => c.anulado_at && personasActivasIds.has(c.persona_id))
          .filter((c) => coincide(c.persona) || coincide(c.sede))
          .filter((c) => filtroSede === "" || c.sede === filtroSede)
          .filter((c) => filtroTipo === "" || c.tipo === filtroTipo)
          .sort((a, b) => (b.anulado_at ?? "").localeCompare(a.anulado_at ?? ""))
      : [];

  /**
   * Las filas de LA TABLA COMPACTA, en un solo formato — vengan del tablero
   * (persona con o sin contrato) o del archivo de anulados (pestaña
   * "Archivados"). Una sola pasada calcula lo que necesitan las dos vistas
   * —tabla de escritorio y tarjetas de celular—, para que no puedan divergir.
   */
  const filasVista =
    filtroEstado === "archivados"
      ? filasArchivadas.map((c) => ({
          key: c.id,
          persona: c.persona,
          documento: TIPO_CONTRATO[c.tipo] ?? c.tipo,
          vigencia: `${formatearFecha(c.fecha_inicio)} – ${c.fecha_fin ? formatearFecha(c.fecha_fin) : "indeterminado"}`,
          sede: c.sede,
          estadoLabel: "Anulado",
          estadoVariante: "informativo" as const,
          banda: null as Banda | null,
          vence: "—",
          venceAlerta: false,
          fechaFin: null as string | null,
          titulo: c.anulado_motivo ? `Anulado: ${c.anulado_motivo}` : "Anulado",
          onClickRow: () => setDetalleId(c.id),
          acciones: accionesContrato(c),
        }))
      : filas.map((f) => {
          const personaFila = personas.find((p) => p.id === f.persona_id);
          const esPracticanteFila = personaFila?.tipo_vinculo === "practicante";
          const e =
            f.estado === "sin_contrato"
              ? estadoSinContrato(f)
              : (ESTADO_TABLERO[f.estado] ?? { texto: f.estado, grave: false });
          // Para una practicante, `fecha_fin_contrato`/`estado` los mueve el
          // tope legal de 12 meses (0336), no lo que dice su convenio: decirlo
          // con las palabras de un contrato vencido confundiría.
          const estadoLabel =
            esPracticanteFila && f.estado === "vencido"
              ? "Pasó 12 meses"
              : esPracticanteFila && f.estado === "por_vencer"
                ? "Cerca del tope"
                : esPracticanteFila && f.estado === "sin_vencimiento"
                  ? "Sin fecha fin"
                  : // BUG cerrado: `ETIQUETA_CORTA.sin_contrato` ("Sin
                      // registrar") tapaba la distinción que `estadoSinContrato`
                      // ya calculaba en `e.texto` — alguien con un contrato
                      // firmado EN PAPEL antes de que este generador existiera
                      // (`fecha_fin_contrato` puesto a mano, sin fila en
                      // `contratos_generados`) se veía IDÉNTICO a alguien sin
                      // ningún contrato. La fila no tiene nada que mostrar
                      // igual —no hay escaneo que ver: nunca se subió ninguno,
                      // por eso "Generar" sigue siendo la única acción—, pero
                      // el badge no puede mentir diciendo "Sin registrar" de
                      // dos personas en situaciones distintas.
                      f.estado === "sin_contrato" && f.fecha_fin_contrato !== null
                      ? "En papel"
                      : (ETIQUETA_CORTA[f.estado] ?? e.texto);
          const tipoFila = esPracticanteFila
            ? "convenio_practicas"
            : tipoQueCorresponde(personaFila?.fecha_ingreso, hoyLima());
          const contrato = f.contrato_id ? contratos.find((x) => x.id === f.contrato_id) : undefined;
          // La cuenta regresiva ("en 9 días" / "hace 6 días") ya no tiene su
          // propia columna —"Vigencia" ahora muestra la fecha exacta, no el
          // relativo—, pero sigue siendo la forma más rápida de sentir la
          // urgencia: se guarda en el `title` de la fila, un hover de
          // distancia en vez de una columna que en la tabla compacta no cabe.
          const v = venceTexto(f);
          // La fila entera abre el detalle; quien no tiene contrato todavía no
          // tiene detalle que abrir, así que se le prepara el formulario, que
          // es lo único que se puede hacer con ella.
          const onClickRow = () => {
            if (contrato) setDetalleId(contrato.id);
            else {
              setPersonaId(f.persona_id);
              setTipo(tipoFila);
              irAlGenerador();
            }
          };
          return {
            key: f.persona_id,
            persona: f.persona,
            documento: f.tipo ? (TIPO_CONTRATO[f.tipo] ?? f.tipo) : "—",
            vigencia: contrato
              ? `${formatearFecha(contrato.fecha_inicio)} – ${contrato.fecha_fin ? formatearFecha(contrato.fecha_fin) : "indeterminado"}`
              : f.fecha_fin_contrato
                ? `hasta ${formatearFecha(f.fecha_fin_contrato)}`
                : "—",
            sede: f.sede,
            estadoLabel,
            estadoVariante: variantePorEstado(f.estado),
            banda: bandaDe(f) as Banda | null,
            // «hace 6 días» / «en 9 días»: la urgencia a simple vista, ahora a la vista en la fila y no en un title.
            vence: v.texto,
            venceAlerta: v.alerta,
            fechaFin: f.fecha_fin_contrato,
            titulo: v.texto === "—" ? e.texto : `${e.texto} · vence ${v.texto}`,
            onClickRow,
            acciones: contrato ? (
              <span className="inline-flex items-center gap-1">
                {accionPrincipal(f.estado, f.persona_id, contrato, tipoFila)}
                {accionesContrato(contrato)}
              </span>
            ) : (
              <Boton
                variante="sutil"
                tamano="sm"
                onClick={(ev) => {
                  ev.stopPropagation();
                  onClickRow();
                }}
              >
                Generar
              </Boton>
            ),
          };
        });

  // El archivo, agrupado por persona y en el orden en que ya vienen (el más
  // reciente primero). `Map` y no un objeto: conserva el orden de inserción,
  // que es el que decide la consulta.
  //
  // SIN `useMemo`, y a propósito: este bloque vive DESPUÉS de los `return`
  // de «cargando» y «sin permiso», así que un hook acá se salta en esos
  // renders y React revienta con el error 310 —«más hooks que en el render
  // anterior»—, que es lo que pasó al probarlo. Agrupar veinte filas no
  // cuesta nada; el hook sí.
  const porPersona = (() => {
    const m = new Map<string, ContratoFila[]>();
    for (const c of contratos) {
      // Quien ya cesó no aparece: su historial sigue en la base, pero esta
      // pantalla es para gestionar contratos de quien sigue en la empresa.
      if (!personasActivasIds.has(c.persona_id)) continue;
      const previo = m.get(c.persona);
      if (previo) previo.push(c);
      else m.set(c.persona, [c]);
    }
    return [...m.entries()];
  })();

  const porPersonaVisible = porPersona.filter(([nombre]) => coincide(nombre));

  // UN SOLO SITIO DONDE SE VE UN CONTRATO: el visor de "Ver / imprimir".
  //
  // Hasta el 2026-09-08 había dos. El documento también se pintaba EN LÍNEA al
  // final de la página —el borrador recién generado, y la vista previa mientras
  // se llenaba el formulario—, así que bajando por el archivo aparecía de
  // pronto un contrato entero entre la lista y el pie, sin que nadie lo hubiera
  // pedido. Decisión de Felipe: quitarlo.
  //
  // Con él se va la vista previa mientras se teclea, y no hace falta: un
  // borrador se corrige EN SU SITIO (0388) sin generar otro, así que el ciclo
  // «generar → leerlo → corregirlo» ya existía y no deja documentos de más. Y
  // la nota «[REVISAR antes de imprimir…]» de la causa objetiva la caza
  // `bloqueos`, que impide generar hasta quitarla — nunca dependió de que
  // alguien leyera la vista previa.
  //
  // A cambio, el documento se ABRE SOLO en el visor apenas se genera o se
  // corrige un borrador: si no, «Borrador generado, revísalo» dejaría sin nada
  // que revisar hasta ir a buscarlo al archivo.
  //
  // Y de paso desaparece un riesgo que tenía la vista en línea: `imprimir()`
  // manda a papel la página entera, así que con las dos superficies en el DOM
  // —alguien elegido en el formulario y un contrato del archivo abierto—
  // salían DOS contratos del mismo tirón, uno detrás del otro, para firmar.

  // LA FIRMA SE ESTAMPA AL MOSTRAR, NUNCA AL GUARDAR. Lo que la 0272 congela en
  // `documento_html` es el borrador SIN firmar; meterle la imagen convertiría un
  // borrador en algo que parece un documento ya firmado. Acá solo se reemplaza
  // el marcador para la vista y la impresión.
  //
  // Y siempre la del firmante configurado, no la de quien mira: `fn_firma_empresa`
  // no recibe parámetros, así que no hay forma —ni la debe haber— de estampar la
  // de otra persona. Se estampa por defecto a quien abre el panel con el rol que
  // corresponde (Gerencia, DO, líder de equipo).
  const puedeEstampar = puedeEstamparFirmaDeEmpresa(rol) && Boolean(firmaUrl);
  // La del colaborador (0402) es distinta: no depende de quién mira el panel,
  // sino de si ESE contrato puntual ya tiene una firma confirmada congelada.
  // Por eso recibe la imagen como parámetro en vez de leerla de un estado
  // global como `firmaUrl` — cada contrato trae la suya, o ninguna.
  const estampar = (html: string, firmaPersona?: string | null) =>
    html
      .replaceAll(MARCADOR_FIRMA_EMPRESA, puedeEstampar ? `<img src="${firmaUrl}" alt="Firma" />` : "&nbsp;")
      .replaceAll(MARCADOR_FIRMA_PERSONA, firmaPersona ? `<img src="${firmaPersona}" alt="Firma del colaborador" />` : "&nbsp;");
  // Un borrador recién generado o recién corregido llega acá con
  // `firmaPersonaAbierta` en null: todavía no tiene fila de la que leer una
  // confirmación del colaborador, así que solo se estampa la de la empresa.
  const htmlFinalModal = documentoAbierto ? estampar(documentoAbierto, firmaPersonaAbierta) : null;

  return (
    <main className="p-6">
          {/* EL GENERADOR ES SU PROPIA PANTALLA, no una sección de esta
              página. `fixed inset-0` la superpone entera y tapa el listado
              — lo primero y casi único que se ve mientras se crea o edita un
              documento es esta ventana, tal como pedía la spec original
              ("abrir una página dedicada... no un modal pequeño") y como lo
              confirmó Felipe al ver la Fase 2: "se tiene que ver
              principalmente la ventana del contrato". Sigue siendo la misma
              página de Next.js por dentro —no hay ruta `/admin/contratos/nuevo`
              todavía—, así que cerrarla es instantáneo y nunca pierde lo
              tecleado: solo dejar de verlo (`generadorAbierto`), no un
              `unmount`. */}
          {generadorAbierto && (
            // `top-16` en vez de `inset-0`: el header del panel es
            // `sticky top-0 z-30` de `h-16` (64px) — por debajo de esa altura
            // esta ventana queda tapada por él (z-30 > z-20) y lo de arriba
            // ("← Volver", el título) no se ve. Se deja el header visible a
            // propósito —sigue siendo el panel, no una app aparte— y esta
            // ventana ocupa todo lo de abajo.
            <div className="fixed inset-x-0 top-16 bottom-0 z-20 overflow-y-auto bg-crema">
              <div className="mx-auto max-w-4xl space-y-4 p-6">
                {/* VOLVER: cierra la ventana sin tocar nada de lo tecleado —
                    reabrir (Editar, o el mismo botón "+ Nuevo documento" si
                    hay una persona elegida) retoma exactamente donde quedó. */}
                <button
                  type="button"
                  onClick={() => setGeneradorAbierto(false)}
                  className="flex items-center gap-1.5 text-sm text-taupe transition-colors duration-150 hover:text-tinta"
                >
                  ← Volver a Contratos
                </button>

                <section id="generador" className="min-w-0 space-y-4">
                  {/* ENCABEZADO DEL PASO: para quién, qué documento, cuánto
                      falta. */}
                  <div className="space-y-2">
                    <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                      <div>
                        <p className="font-serif text-xl">
                          {editando
                            ? `Editando: ${TIPO_CONTRATO[editando.tipo] ?? editando.tipo}`
                            : persona
                              ? (TIPO_CONTRATO[tipoEfectivo] ?? tipoEfectivo)
                              : "Nuevo documento"}
                        </p>
                        {persona && (
                          <p className="text-sm text-taupe">
                            {persona.nombres} {persona.apellidos} · Paso {indicePaso + 1} de {pasosGenerador.length}
                          </p>
                        )}
                      </div>
                      {persona && (
                        <span className="text-sm font-medium tabular-nums text-taupe">
                          {Math.round(((indicePaso + 1) / pasosGenerador.length) * 100)}%
                        </span>
                      )}
                    </div>
                    {persona && (
                      <div className="h-1.5 w-full overflow-hidden rounded-pildora bg-sand">
                        <div
                          className="h-full rounded-pildora bg-tinta transition-all duration-300"
                          style={{ width: `${((indicePaso + 1) / pasosGenerador.length) * 100}%` }}
                        />
                      </div>
                    )}
                  </div>

                  {/* Sin persona todavía no hay `<nav>` (más abajo): con un
                      solo hijo, un grid de dos columnas lo ubicaría solo en
                      la PRIMERA (13rem) por las reglas de auto-placement, y
                      la tarjeta del paso 1 saldría angosta. La plantilla de
                      columnas se activa recién cuando sí hay dos hijos. */}
                  <div className={`grid gap-4 ${persona ? "sm:grid-cols-[13rem_1fr]" : ""}`}>
              {/* LA LISTA DE PASOS. Salta libremente entre los ya visitados y
                  los que faltan — no hay nada que "desbloquear": el único
                  candado real sigue siendo `bloqueos`, que se ve completo en
                  Revisión y apaga el botón final, exactamente como antes. */}
              {persona && (
                <nav aria-label="Pasos del documento" className="hidden sm:block">
                  <ol className="space-y-1">
                    {pasosGenerador.map((p, i) => {
                      const activo = p.id === pasoActual;
                      return (
                        <li key={p.id}>
                          <button
                            type="button"
                            onClick={() => setPaso(p.id)}
                            aria-current={activo ? "step" : undefined}
                            className={`flex w-full items-center gap-2 rounded-control px-2 py-2 text-left text-sm transition-colors duration-150 ${
                              activo
                                ? "border border-rojo/40 bg-rojo/5 font-medium text-tinta"
                                : "border border-transparent text-taupe hover:bg-sand/40"
                            }`}
                          >
                            <span
                              className={`flex size-5 shrink-0 items-center justify-center rounded-pildora text-[11px] ${
                                activo ? "bg-tinta text-crema" : "bg-sand text-taupe"
                              }`}
                            >
                              {i + 1}
                            </span>
                            {p.etiqueta}
                          </button>
                        </li>
                      );
                    })}
                  </ol>
                </nav>
              )}

              <div className="min-w-0 space-y-3 rounded-lg border border-sand bg-papel p-4">
                {/* PASO — PERSONA Y DOCUMENTO */}
                {pasoActual === "persona" && (
                  <>
                    <CampoSelect
                      id="generador-persona"
                      etiqueta="Persona"
                      className="disabled:bg-crema disabled:text-taupe"
                      value={personaId}
                      // Un borrador es de quien es. Cambiarle la persona no
                      // sería corregirlo, sería otro documento — y para eso
                      // está generar.
                      disabled={editando !== null}
                      onChange={(e) => setPersonaId(e.target.value)}
                    >
                      <option value="">— elegir —</option>
                      {personas.map((p) => (
                        <option key={p.id} value={p.id}>
                          {p.apellidos}, {p.nombres}
                        </option>
                      ))}
                    </CampoSelect>

                    {persona?.tipo_vinculo === "practicante" ? (
                      // Una practicante solo tiene un documento posible — no
                      // "nuevo ingreso" ni "renovación", que son conceptos de
                      // un contrato de trabajo (0333). Se fija sola y no se
                      // elige.
                      <Campo
                        etiqueta="Tipo"
                        className="disabled:bg-crema disabled:text-taupe"
                        value="Convenio de prácticas"
                        disabled
                      />
                    ) : (
                      <div>
                        <span className="text-sm text-taupe">Tipo de documento</span>
                        <div className="mt-1 grid gap-2 sm:grid-cols-2">
                          {ORDEN_TIPOS.map((clave) => {
                            const activo = tipo === clave;
                            return (
                              <button
                                key={clave}
                                type="button"
                                // Un borrador es de su tipo. Cambiarlo a media
                                // edición no sería corregirlo — mismo criterio
                                // que bloquea la Persona de al lado.
                                disabled={editando !== null}
                                onClick={() => setTipo(clave)}
                                className={`rounded-lg border p-3 text-left transition-colors duration-150 disabled:cursor-not-allowed disabled:opacity-60 ${
                                  activo ? "border-rojo bg-rojo/5" : "border-sand hover:bg-hueso/60"
                                }`}
                              >
                                <span className="block text-sm font-medium text-tinta">{TIPO_CONTRATO[clave]}</span>
                                <span className="block text-xs text-taupe">{DESCRIPCION_TIPO[clave]}</span>
                              </button>
                            );
                          })}
                        </div>
                      </div>
                    )}

                    {/* EDITANDO: lo que se ve tiene que decir que esto NO va a
                        crear nada. Sin esta banda el paso es idéntico al de
                        generar, y el botón final sería la única pista —
                        demasiado tarde. */}
                    {editando && (
                      <div className="rounded-lg border border-pizarra/50 bg-pizarra/10 px-3 py-2 text-sm">
                        <p className="font-medium">Editando un borrador, no generando otro.</p>
                        <p className="mt-1 text-xs text-taupe">
                          {describir(editando)} · generado el {formatearFecha(editando.generado_at.slice(0, 10))}. Al
                          guardar se reemplaza su texto; el archivo conserva el mismo documento.
                        </p>
                        {edicionSinFoto && (
                          <p className="mt-2 text-xs">
                            Se generó antes de que se guardara lo tecleado, así que los textos largos vuelven a
                            arrancar en su relleno. <strong>Revísalos antes de guardar.</strong>
                          </p>
                        )}
                        <Boton variante="enlace" className="mt-2 text-xs" onClick={cancelarEdicion}>
                          Cancelar edición
                        </Boton>
                      </div>
                    )}

                    {/* SE TRAJO DEL DOCUMENTO ANTERIOR (hallazgo de la
                        auditoría 2026-09-14): el Anexo I / plan formativo no
                        arrancó en blanco ni en el relleno — se trajo del
                        último documento vivo de esta persona. Aviso, no
                        silencio: es justo lo que evita que un dato viejo se
                        cuele como si ya estuviera revisado hoy. */}
                    {!editando && prellenoAnterior && (
                      <div className="rounded-lg border border-sand bg-hueso px-3 py-2 text-sm text-taupe">
                        Se trajeron algunos campos del{" "}
                        {(TIPO_CONTRATO[prellenoAnterior.tipo] ?? prellenoAnterior.tipo).toLowerCase()} anterior de{" "}
                        {persona?.nombres}, generado el {formatearFecha(prellenoAnterior.generado_at.slice(0, 10))}.{" "}
                        <strong className="text-tinta">Revísalos antes de generar.</strong>
                      </div>
                    )}

                    {/* LO QUE YA TIENE SIN FIRMAR, CON LAS DOS SALIDAS AL LADO.
                        Decirlo solo en Revisión obliga a llegar hasta el final
                        para enterarse. Acá se corrige o se anula desde donde
                        se descubrió, apenas se elige a la persona. */}
                    {persona && borradoresVivos.length > 0 && (
                      <div className="rounded-lg border border-taupe/40 bg-sand/40 px-3 py-2 text-sm">
                        <p className="font-medium">
                          {persona.nombres} ya tiene{" "}
                          {borradoresVivos.length === 1 ? "un documento" : `${borradoresVivos.length} documentos`} sin
                          firmar.
                        </p>
                        <ul className="mt-1 space-y-1">
                          {borradoresVivos.map((c) => (
                            <li key={c.id} className="flex flex-wrap items-baseline gap-x-3 text-xs">
                              <span className="min-w-0 flex-1">{describir(c)}</span>
                              <button
                                className="underline underline-offset-2 hover:text-tinta"
                                onClick={() => empezarEdicion(c)}
                              >
                                Editar
                              </button>
                              <button
                                className="underline underline-offset-2 hover:text-rojo"
                                onClick={() => setAnulando(c.id)}
                              >
                                Anular
                              </button>
                            </li>
                          ))}
                        </ul>
                        <p className="mt-2 text-xs text-taupe">
                          Un documento sin firmar se corrige; no se genera otro al lado.
                        </p>
                      </div>
                    )}
                  </>
                )}

                {/* PASO — VIGENCIA (todos los tipos, adendum incluido: un
                    adendum también declara desde cuándo rige y dónde se
                    firma). */}
                {pasoActual === "vigencia" && persona && (
                  <>
                    <div className="grid gap-3 sm:grid-cols-2">
                      <Campo
                        etiqueta="Fecha de inicio"
                        type="date"
                        value={fechaInicio}
                        onChange={(e) => setFechaInicio(e.target.value)}
                      />
                      {esIndefinido ? (
                        <Campo
                          etiqueta="Fecha de fin"
                          className="disabled:bg-crema disabled:text-taupe"
                          value="Sin fecha de fin — contrato indefinido"
                          disabled
                        />
                      ) : (
                        <Campo
                          etiqueta="Fecha de fin"
                          type="date"
                          value={fechaFin}
                          min={fechaInicio || undefined}
                          onChange={(e) => setFechaFin(e.target.value)}
                        />
                      )}
                    </div>
                    <Campo
                      etiqueta="Cargo"
                      list="cargos-existentes"
                      value={cargoEditado}
                      onChange={(e) => setCargoEditado(e.target.value)}
                    />
                    <datalist id="cargos-existentes">
                      {cargosExistentes.map((c) => (
                        <option key={c} value={c} />
                      ))}
                    </datalist>
                    <Campo
                      etiqueta="Ciudad donde se firma"
                      list="ciudades-existentes"
                      placeholder={ciudadDeLaSede ?? "Arequipa, Lima o Trujillo"}
                      value={ciudadEditada}
                      onChange={(e) => setCiudadEditada(e.target.value)}
                    />
                    <datalist id="ciudades-existentes">
                      {ciudadesExistentes.map((c) => (
                        <option key={c} value={c} />
                      ))}
                    </datalist>
                    <span className="-mt-2 block text-xs text-taupe">
                      {ciudadDeLaSede
                        ? `Rellenada con ${ciudadDeLaSede}, la ciudad de la sede ${sedeNom} — cámbiala si corresponde otra.`
                        : "Central no tiene una ciudad propia: su gente puede estar en cualquiera, así que hay que elegirla."}
                    </span>
                  </>
                )}

                {/* PASO — QUÉ SE MODIFICA (solo adendum). Un adendum no repite
                    el contrato ni sus anexos, así que no pide nada más. */}
                {pasoActual === "contenido" && persona && (
                  <AreaTexto
                    etiqueta="Qué se modifica del contrato vigente — una modificación por línea"
                    rows={8}
                    placeholder="Ej.: Se modifica la Cláusula Sexta, fijando la remuneración mensual base en S/ …"
                    value={adendumEditado}
                    onChange={(e) => setAdendumEditado(e.target.value)}
                  />
                )}

                {/* PASO — DATOS ACADÉMICOS (solo convenio). El preprofesional
                    es TRIPARTITO (CAYLA + centro de formación + practicante,
                    art. 12 y ss. Ley 28518) — el profesional es bipartito y
                    solo referencia su título (0348). */}
                {pasoActual === "academico" && persona && esConvenio && (
                  <>
                    {persona.tipo_vinculo === "practicante" ? (
                      <Campo
                        etiqueta="Modalidad"
                        className="disabled:bg-crema disabled:text-taupe"
                        disabled
                        value={
                          persona.practicante_modalidad === "preprofesional"
                            ? "Preprofesional — 30h/semana (art. 44)"
                            : persona.practicante_modalidad === "profesional"
                              ? "Profesional — 48h/semana (art. 44)"
                              : "Sin asignar — ve a Equipo y elígela primero"
                        }
                      />
                    ) : (
                      <>
                        <CampoSelect
                          etiqueta="Modalidad"
                          value={modalidadManualEditada}
                          onChange={(e) =>
                            setModalidadManualEditada(e.target.value as "preprofesional" | "profesional" | "")
                          }
                        >
                          <option value="">— elegir —</option>
                          <option value="preprofesional">Preprofesional — 30h/semana (art. 44)</option>
                          <option value="profesional">Profesional — 48h/semana (art. 44)</option>
                        </CampoSelect>
                        <p className="text-xs text-taupe">
                          {persona.nombres} no está marcada como practicante en su ficha (Equipo) todavía.
                        </p>
                        {modalidadManualEditada && (
                          <label className="flex items-start gap-2 rounded-lg border border-sand bg-hueso p-2 text-xs">
                            <input
                              type="checkbox"
                              className="mt-0.5"
                              checked={aplicarModalidadFicha}
                              onChange={(e) => setAplicarModalidadFicha(e.target.checked)}
                            />
                            <span>
                              Al generar, marcar a {persona.nombres} como practicante {modalidadManualEditada} en su
                              ficha (Equipo) — activa el aviso de{" "}
                              {maximoSemanalPracticante("practicante", modalidadManualEditada)}h/semana en Incidencias
                              (art. 44, Ley 28518).
                            </span>
                          </label>
                        )}
                      </>
                    )}
                    {/* SOLO PREPROFESIONAL (auditoría 2026-09-14, hallazgo
                        #1): el profesional siempre se asume a su jornada
                        completa de 48h (contrato-texto.ts). Vacío = a las 30h
                        completas de su modalidad — el mismo comportamiento
                        que tenía el sistema antes de este campo. El artículo
                        45 de la Ley 28518 solo prorratea el piso de la RMV
                        contra estas horas cuando son MENOS que el tope de la
                        modalidad (30h), nunca contra 48h. */}
                    {modalidadEfectiva === "preprofesional" && (
                      <Campo
                        etiqueta="Horas semanales pactadas — vacío si son las 30 completas (art. 44)"
                        type="number"
                        min={1}
                        max={30}
                        step={1}
                        placeholder="30"
                        value={horasConvenioEditadas}
                        onChange={(e) => setHorasConvenioEditadas(e.target.value)}
                      />
                    )}
                    {modalidadEfectiva === "preprofesional" ? (
                      <>
                        <div className="grid gap-3 sm:grid-cols-2">
                          <Campo
                            etiqueta="Centro de formación — razón social"
                            placeholder="Ej.: Universidad Nacional de Trujillo"
                            value={centroFormacionNombreEditado}
                            onChange={(e) => setCentroFormacionNombreEditado(e.target.value)}
                          />
                          <Campo
                            etiqueta="Centro de formación — RUC"
                            value={centroFormacionRucEditado}
                            onChange={(e) => setCentroFormacionRucEditado(e.target.value)}
                          />
                        </div>
                        <div className="grid gap-3 sm:grid-cols-2">
                          <Campo
                            etiqueta="Centro de formación — domicilio"
                            value={centroFormacionDomicilioEditado}
                            onChange={(e) => setCentroFormacionDomicilioEditado(e.target.value)}
                          />
                          <Campo
                            etiqueta="Representante del centro — nombre"
                            value={centroFormacionRepresentanteNombreEditado}
                            onChange={(e) => setCentroFormacionRepresentanteNombreEditado(e.target.value)}
                          />
                        </div>
                        <div className="grid gap-3 sm:grid-cols-2">
                          <Campo
                            etiqueta="Representante del centro — cargo"
                            placeholder="Ej.: Director Académico"
                            value={centroFormacionRepresentanteCargoEditado}
                            onChange={(e) => setCentroFormacionRepresentanteCargoEditado(e.target.value)}
                          />
                          <Campo
                            etiqueta="Carrera / especialidad"
                            value={carreraEspecialidadEditada}
                            onChange={(e) => setCarreraEspecialidadEditada(e.target.value)}
                          />
                        </div>
                        <Campo
                          etiqueta="Ciclo académico"
                          className="sm:w-1/2"
                          value={cicloAcademicoEditado}
                          onChange={(e) => setCicloAcademicoEditado(e.target.value)}
                        />
                      </>
                    ) : (
                      <AreaTexto
                        etiqueta="Grado / título (referencial — no aplica al centro de formación, que no firma en el profesional)"
                        rows={2}
                        placeholder="Ej.: Bachiller en Ingeniería de Sistemas — UNT, egresado el 15/12/2025"
                        value={gradoTituloTextoEditado}
                        onChange={(e) => setGradoTituloTextoEditado(e.target.value)}
                      />
                    )}
                  </>
                )}

                {/* PASO — PLAN FORMATIVO Y ACTIVOS (solo convenio): Anexo I +
                    el mismo Anexo IV de activos que usa la rama no-convenio. */}
                {pasoActual === "plan" && persona && esConvenio && (
                  <>
                    <AreaTexto
                      etiqueta="Anexo I — área / proyecto de destino"
                      rows={2}
                      placeholder="Ej.: Proyecto ERP CAYLA — módulo de inventario"
                      value={areaProyectoEditado}
                      onChange={(e) => setAreaProyectoEditado(e.target.value)}
                    />
                    <AreaTexto
                      etiqueta="Anexo I — objetivo formativo general"
                      rows={2}
                      placeholder="Qué debe saber hacer al finalizar"
                      value={objetivoFormativoGeneralEditado}
                      onChange={(e) => setObjetivoFormativoGeneralEditado(e.target.value)}
                    />
                    <AreaTexto
                      etiqueta="Anexo I — actividades principales (una por línea; se numeran solas)"
                      rows={3}
                      placeholder="Ej.: Apoyo en el desarrollo de módulos del sistema interno de asistencia, bajo supervisión del área de Desarrollo."
                      value={planCapacitacionEditado}
                      onChange={(e) => setPlanCapacitacionEditado(e.target.value)}
                    />
                    <Campo
                      etiqueta="Anexo I — supervisor(a) asignado(a)"
                      className="sm:w-1/2"
                      value={supervisorAsignadoEditado}
                      onChange={(e) => setSupervisorAsignadoEditado(e.target.value)}
                    />
                    {renderActivos(persona.nombres)}
                  </>
                )}

                {/* PASO — CAUSA OBJETIVA (nuevo/renovación/indefinido, salvo
                    indefinido: 0347). */}
                {pasoActual === "causa" && persona && (
                  <AreaTexto
                    etiqueta="Causa objetiva (revisar antes de imprimir)"
                    rows={9}
                    value={causaEditada}
                    onChange={(e) => setCausaEditada(e.target.value)}
                  />
                )}

                {/* PASO — FUNCIONES Y ACTIVOS (nuevo/renovación/indefinido). */}
                {pasoActual === "funciones" && persona && (
                  <>
                    <AreaTexto
                      etiqueta="Funciones del cargo (Anexo I) — una por línea; se numeran solas"
                      rows={5}
                      value={funcionesEditadas}
                      onChange={(e) => setFuncionesEditadas(e.target.value)}
                    />
                    {renderActivos(persona.nombres)}
                  </>
                )}

                {/* PASO — REVISIÓN. Resumen de solo lectura, agrupado por
                    sección, cada una con su "Editar →" — y ahí mismo, al
                    final, el botón real de generar/guardar (los mismos de
                    siempre, misma condición `disabled`). */}
                {pasoActual === "revision" && persona && (
                  <>
                    <div className="space-y-3">
                      <div className="rounded-lg border border-sand p-3">
                        <div className="flex items-center justify-between gap-2">
                          <h3 className="font-serif text-base">Documento</h3>
                          <Boton variante="enlace" className="text-xs" onClick={() => setPaso("persona")}>
                            Editar →
                          </Boton>
                        </div>
                        <dl className="mt-2 grid grid-cols-2 gap-2 text-sm">
                          <div>
                            <dt className="text-xs text-taupe">Persona</dt>
                            <dd>
                              {persona.nombres} {persona.apellidos}
                            </dd>
                          </div>
                          <div>
                            <dt className="text-xs text-taupe">Tipo</dt>
                            <dd>{TIPO_CONTRATO[tipoEfectivo] ?? tipoEfectivo}</dd>
                          </div>
                        </dl>
                      </div>

                      <div className="rounded-lg border border-sand p-3">
                        <div className="flex items-center justify-between gap-2">
                          <h3 className="font-serif text-base">Vigencia</h3>
                          <Boton variante="enlace" className="text-xs" onClick={() => setPaso("vigencia")}>
                            Editar →
                          </Boton>
                        </div>
                        <dl className="mt-2 grid grid-cols-2 gap-2 text-sm">
                          <div>
                            <dt className="text-xs text-taupe">Inicio</dt>
                            <dd>{fechaInicio ? formatearFecha(fechaInicio) : "—"}</dd>
                          </div>
                          <div>
                            <dt className="text-xs text-taupe">Fin</dt>
                            <dd>{esIndefinido ? "indeterminado" : fechaFin ? formatearFecha(fechaFin) : "—"}</dd>
                          </div>
                          <div>
                            <dt className="text-xs text-taupe">Cargo</dt>
                            <dd>{cargoEditado || "—"}</dd>
                          </div>
                          <div>
                            <dt className="text-xs text-taupe">Ciudad</dt>
                            <dd>{ciudadFinal || "—"}</dd>
                          </div>
                        </dl>
                      </div>

                      {esAdendum && (
                        <div className="rounded-lg border border-sand p-3">
                          <div className="flex items-center justify-between gap-2">
                            <h3 className="font-serif text-base">Qué se modifica</h3>
                            <Boton variante="enlace" className="text-xs" onClick={() => setPaso("contenido")}>
                              Editar →
                            </Boton>
                          </div>
                          <p className="mt-2 whitespace-pre-line text-sm">{adendumEditado || "—"}</p>
                        </div>
                      )}

                      {esConvenio && (
                        <>
                          <div className="rounded-lg border border-sand p-3">
                            <div className="flex items-center justify-between gap-2">
                              <h3 className="font-serif text-base">Información académica</h3>
                              <Boton variante="enlace" className="text-xs" onClick={() => setPaso("academico")}>
                                Editar →
                              </Boton>
                            </div>
                            {modalidadEfectiva === "preprofesional" ? (
                              <dl className="mt-2 grid grid-cols-2 gap-2 text-sm">
                                <div>
                                  <dt className="text-xs text-taupe">Centro de formación</dt>
                                  <dd>{centroFormacionNombreEditado || "—"}</dd>
                                </div>
                                <div>
                                  <dt className="text-xs text-taupe">RUC</dt>
                                  <dd>{centroFormacionRucEditado || "—"}</dd>
                                </div>
                                <div>
                                  <dt className="text-xs text-taupe">Carrera</dt>
                                  <dd>{carreraEspecialidadEditada || "—"}</dd>
                                </div>
                                <div>
                                  <dt className="text-xs text-taupe">Ciclo</dt>
                                  <dd>{cicloAcademicoEditado || "—"}</dd>
                                </div>
                                <div>
                                  <dt className="text-xs text-taupe">Horas semanales pactadas</dt>
                                  <dd>{horasConvenioEditadas ? `${horasConvenioEditadas}h` : "30h (completas)"}</dd>
                                </div>
                              </dl>
                            ) : (
                              <p className="mt-2 text-sm">{gradoTituloTextoEditado || "—"}</p>
                            )}
                          </div>
                          <div className="rounded-lg border border-sand p-3">
                            <div className="flex items-center justify-between gap-2">
                              <h3 className="font-serif text-base">Plan formativo</h3>
                              <Boton variante="enlace" className="text-xs" onClick={() => setPaso("plan")}>
                                Editar →
                              </Boton>
                            </div>
                            <dl className="mt-2 space-y-2 text-sm">
                              <div>
                                <dt className="text-xs text-taupe">Área / proyecto</dt>
                                <dd>{areaProyectoEditado || "—"}</dd>
                              </div>
                              <div>
                                <dt className="text-xs text-taupe">Supervisor(a)</dt>
                                <dd>{supervisorAsignadoEditado || "—"}</dd>
                              </div>
                              <div>
                                <dt className="text-xs text-taupe">Activos</dt>
                                <dd>{sinActivosAdicionales ? "sin activos adicionales" : activosLibre || "—"}</dd>
                              </div>
                            </dl>
                          </div>
                        </>
                      )}

                      {!esAdendum && !esConvenio && (
                        <div className="rounded-lg border border-sand p-3">
                          <div className="flex items-center justify-between gap-2">
                            <h3 className="font-serif text-base">
                              {esIndefinido ? "Funciones y activos" : "Causa objetiva y funciones"}
                            </h3>
                            <Boton
                              variante="enlace"
                              className="text-xs"
                              onClick={() => setPaso(esIndefinido ? "funciones" : "causa")}
                            >
                              Editar →
                            </Boton>
                          </div>
                          <dl className="mt-2 space-y-2 text-sm">
                            {!esIndefinido && (
                              <div>
                                <dt className="text-xs text-taupe">Causa objetiva</dt>
                                <dd className="line-clamp-2">{causaEditada || "—"}</dd>
                              </div>
                            )}
                            <div>
                              <dt className="text-xs text-taupe">Funciones</dt>
                              <dd className="line-clamp-2">{funcionesEditadas || "—"}</dd>
                            </div>
                            <div>
                              <dt className="text-xs text-taupe">Activos</dt>
                              <dd>{sinActivosAdicionales ? "sin activos adicionales" : activosLibre || "—"}</dd>
                            </div>
                          </dl>
                        </div>
                      )}

                      {/* DATOS AUTOMÁTICOS: exactamente el mismo bloque de
                          antes, en modo lectura — ninguno se pide dentro del
                          documento porque ya son datos de otra pantalla
                          (spec §10). "Editar →" no existe acá a propósito: no
                          hay nada que editar EN ESTE formulario, cada uno se
                          corrige donde vive de verdad. */}
                      <div className="rounded-lg border border-sand p-3">
                        <h3 className="font-serif text-base">Datos automáticos del colaborador</h3>
                        <dl className="mt-2 grid grid-cols-2 gap-2 text-xs text-taupe">
                          <div>
                            <dt className="font-semibold">DNI</dt>
                            <dd>{persona.documento ?? "falta"}</dd>
                          </div>
                          <div>
                            <dt className="font-semibold">Nombre legal</dt>
                            <dd>{datoPersonal?.nombre_dni ?? "falta en Ficha personal"}</dd>
                          </div>
                          <div>
                            <dt className="font-semibold">Domicilio</dt>
                            <dd className={datoPersonal?.direccion ? "" : "text-rojo"}>
                              {datoPersonal?.direccion ?? "falta — cárgalo en Datos personales"}
                            </dd>
                          </div>
                          <div>
                            <dt className="font-semibold">Correo (Anexo III)</dt>
                            <dd className={persona.email ? "" : "text-rojo"}>
                              {persona.email ?? "falta — cárgalo en Equipo"}
                            </dd>
                          </div>
                          <div>
                            <dt className="font-semibold">Sueldo base vigente</dt>
                            <dd className="tabular-nums">
                              {salarioVigente !== null ? `S/ ${salarioVigente.toFixed(2)}` : "sin asignación vigente"}
                            </dd>
                          </div>
                          <div>
                            <dt className="font-semibold">Jornada del {esConvenio ? "convenio" : "contrato"}</dt>
                            <dd>
                              {esConvenio
                                ? (() => {
                                    const max = maximoSemanalPracticante("practicante", modalidadEfectiva);
                                    return max !== null
                                      ? `hasta ${max} horas semanales (art. 44)`
                                      : "falta elegir la modalidad";
                                  })()
                                : "48 horas semanales (el máximo legal — ver cláusula QUINTA)"}
                            </dd>
                          </div>
                          <div>
                            <dt className="font-semibold">Movilidad</dt>
                            <dd className="tabular-nums">
                              {esConvenio
                                ? "no aplica — no está en planilla (0322)"
                                : persona.cobra_movilidad
                                  ? movilidadTarifa !== null
                                    ? `S/ ${movilidadTarifa}/día`
                                    : "sin tarifa vigente para su sede"
                                  : "no cobra"}
                            </dd>
                          </div>
                          <div>
                            <dt className="font-semibold">RIT vigente</dt>
                            <dd>{ritVersion ? `v${ritVersion} · ${ritFecha}` : "no publicado en el sistema"}</dd>
                          </div>
                          <div>
                            <dt className="font-semibold">Firma de la empresa</dt>
                            <dd className={puedeEstampar ? "" : "text-rojo"}>
                              {!firmante.nombre
                                ? "sin firmante configurado — cárgalo en Documentación"
                                : puedeEstampar
                                  ? `se estampa la de ${firmante.nombre}`
                                  : firmaUrl
                                    ? "tu rol no estampa la firma de la empresa — saldrá la raya en blanco"
                                    : `${firmante.nombre} todavía no tiene su firma guardada en «Mi firma» — saldrá la raya en blanco`}
                            </dd>
                          </div>
                        </dl>
                      </div>
                    </div>

                    {bloqueos.length > 0 && (
                      <ul className="list-disc space-y-1 rounded-lg bg-rojo/10 px-4 py-3 pl-8 text-sm text-rojo">
                        {bloqueos.map((b) => (
                          <li key={b}>{b}</li>
                        ))}
                      </ul>
                    )}

                    {/* Avisos: no impiden generar, pero tienen que verse ANTES
                        de firmar. En arena y no en rojo — el rojo es el
                        acento sagrado y ya lo gastan los bloqueos de arriba. */}
                    {avisos.length > 0 && (
                      <ul className="list-disc space-y-1 rounded-lg border border-taupe/40 bg-sand/40 px-4 py-3 pl-8 text-sm text-taupe">
                        {avisos.map((a) => (
                          <li key={a}>{a}</li>
                        ))}
                      </ul>
                    )}

                    <div className="flex flex-wrap items-center gap-2 pt-1">
                      {editando ? (
                        <Boton
                          variante="primario"
                          disabled={!datosParaGenerar || bloqueos.length > 0 || guardandoEdicion}
                          cargando={guardandoEdicion}
                          onClick={guardarEdicion}
                        >
                          Guardar cambios
                        </Boton>
                      ) : (
                        <Boton
                          variante="primario"
                          disabled={!datosParaGenerar || bloqueos.length > 0 || generando}
                          cargando={generando}
                          onClick={generarBorrador}
                        >
                          Generar borrador
                        </Boton>
                      )}
                      {editando && (
                        <Boton variante="enlace" className="text-sm" onClick={cancelarEdicion}>
                          Cancelar
                        </Boton>
                      )}
                      {/* Reabre en el visor el borrador recién generado, por si
                          se cerró. Ya no imprime directo: lo que sale por la
                          impresora es lo que el visor tenga abierto. */}
                      {borrador && (
                        <Boton
                          variante="secundario"
                          onClick={() => {
                            setFirmaPersonaAbierta(null);
                            setDocumentoAbierto(borrador.html);
                          }}
                        >
                          Ver / imprimir
                        </Boton>
                      )}
                    </div>
                  </>
                )}

                {/* BARRA INFERIOR: Anterior / Continuar. Ahora que el
                    generador es su propia pantalla con scroll propio, esto sí
                    se pega de verdad al pie del viewport (spec §22) — queda
                    accesible aunque el paso sea largo. */}
                {persona && (
                  <div className="sticky bottom-0 -mx-4 flex items-center justify-between gap-3 border-t border-sand bg-papel px-4 py-3">
                    {indicePaso > 0 ? (
                      <Boton variante="secundario" onClick={() => setPaso(pasosGenerador[indicePaso - 1].id)}>
                        ← Anterior
                      </Boton>
                    ) : (
                      <span />
                    )}
                    {pasoActual !== "revision" && (
                      <Boton variante="primario" onClick={() => setPaso(pasosGenerador[indicePaso + 1].id)}>
                        Continuar →
                      </Boton>
                    )}
                  </div>
                )}
              </div>
            </div>
                </section>
              </div>
            </div>
          )}

      <div className="mx-auto max-w-6xl space-y-6 print:hidden">
        <CabeceraPagina
          sobretitulo={sobretituloDeHoy("Personas")}
          titulo="Contratos"
          descripcion="Quién necesita un contrato, una renovación o una firma, de lo más urgente a lo que está al día."
          ayuda={
            <AyudaPantalla
              titulo="Cómo funciona Contratos"
              intro="Cada persona está en la banda que le toca según su contrato; la lista va de lo más urgente a lo que está al día. Abrir una fila muestra su documento."
              secciones={[
                { titulo: "Ya pasó el plazo", texto: "El contrato terminó y la persona sigue marcando asistencia. Pasada la fecha con la persona todavía trabajando, el art. 77 del D. Leg. 728 lo vuelve indefinido por ley, sin que nadie lo decida. Es lo único en rojo." },
                { titulo: "Vence pronto", texto: "Termina en los próximos 60 días (la misma ventana que usa Equipo). Si varios vencen el mismo día, la pantalla lo dice: son decisiones, redacciones y firmas en la misma semana." },
                { titulo: "Falta firma o copia", texto: "El contrato existe pero no está firmado (ni escaneado ni confirmado por la persona), o falta entregarle su copia." },
                { titulo: "Sin contrato registrado", texto: "No hay ni documento ni fecha de fin anotada: no se sabe de ningún contrato." },
                { titulo: "Al día", texto: "Vigentes, sin vencimiento, y los firmados en papel antes de que existiera el generador (marcados «En papel»): son historia, no urgencia." },
                { titulo: "Quién entra", texto: "Desarrollo Organizacional y dirección; firma por CAYLA quien está configurado como firmante. Una líder de equipo no tiene esta pantalla." },
              ]}
            />
          }
          accion={<Boton variante="primario" onClick={irAlGenerador}>+ Nuevo documento</Boton>}
        />

        {/* Antes el generador vivía en medio de esta columna, entre el
            listado y el archivo — con la Fase 2 pasó a ser su propia
            pantalla (`generadorAbierto`, declarada como hijo directo de
            `<main>`, ANTES de este `<div>`): así un `margin` de `space-y-*`
            en un ancestro no le desplaza el `inset-0` — un `position:fixed`
            con `inset:0` y `margin` distinto de auto SÍ se deja empujar por
            ese margin, es una de las pocas propiedades que actúa igual en
            fixed que en flujo normal. Quedan en una sola columna el listado
            y el historial, que es el orden de siempre. */}
        <div className="space-y-6">
          <div className="min-w-0 space-y-6">
            {/* El buscador vive DENTRO de la barra de filtros compacta, más
                abajo (rediseño) — filtra las mismas dos fuentes que antes
                (tablero y archivo), sin tildes. */}
            {/* Un fallo de lectura NO se ve como «nada pendiente»: el plazo del art. 77 corre igual aunque esta lista
                no haya podido mirar. */}
            {falloTablero && (
              <BannerAviso role="alert" variante="alerta" titulo="No se pudieron consultar los contratos">
                <p className="mb-2">
                  Esto no significa que no haya nada pendiente: significa que no se pudo mirar. El plazo del{" "}
                  <strong>artículo 77</strong> corre igual aunque esta lista no haya podido revisarlo.
                </p>
                <Boton variante="secundario" tamano="sm" onClick={() => void cargar()}>Reintentar</Boton>
              </BannerAviso>
            )}
            {falloHistorial && !falloTablero && (
              <BannerAviso enLinea role="alert">
                No se pudo traer el historial de documentos: la lista de personas sí cargó, pero «Archivados» y las acciones de cada fila pueden estar incompletas.{" "}
                <Boton variante="enlace" onClick={() => void cargar()}>Reintentar</Boton>
              </BannerAviso>
            )}

            {/* EL ART. 77 va primero y con título cuando existe: es lo único que cuesta plata (la persona que sigue
                marcando después de su vencimiento queda con vínculo indefinido POR LEY). */}
            {nArt77 > 0 && (
              <BannerAviso enLinea variante="alerta">
                <div className="flex items-center justify-between gap-3">
                  <p>
                    <b className="font-medium text-rojo-profundo">
                      {nArt77} {nArt77 === 1 ? "persona siguió" : "personas siguieron"} marcando después de vencer su contrato
                    </b>
                  </p>
                  <div className="flex shrink-0 items-center gap-1.5">
                    {/* Ojo = «mostrarme quiénes»; ojo tachado = «ya lo estoy viendo, quitar el filtro». */}
                    <BotonIcono
                      etiqueta={soloArt77 ? "Quitar el filtro" : "Ver quiénes"}
                      icono={soloArt77 ? <EyeOff aria-hidden /> : <Eye aria-hidden />}
                      onClick={() => {
                        if (soloArt77) { setBandaElegida(null); return; }
                        setFiltroEstado("pendientes");
                        setBandaElegida("paso");
                      }}
                    />
                    <BotonIcono
                      etiqueta={art77Abierto ? "Ocultar por qué importa" : "Por qué importa"}
                      icono={art77Abierto ? <ChevronUp aria-hidden /> : <ChevronDown aria-hidden />}
                      aria-expanded={art77Abierto}
                      onClick={() => setArt77Abierto(!art77Abierto)}
                    />
                  </div>
                </div>
                {art77Abierto && <p className="mt-2">{EXPLICACION_ART_77}</p>}
              </BannerAviso>
            )}

            {!falloTablero && tablero.length > 0 && (
              <>
                <Pestanas
                  etiqueta="Secciones de Contratos"
                  pestanas={[
                    { clave: "pendientes", texto: "Para atender", aviso: nParaAtender },
                    { clave: "vigentes", texto: "Al día" },
                    { clave: "todos", texto: "Todos" },
                    { clave: "archivados", texto: "Archivados" },
                  ]}
                  activa={filtroEstado === "sin_firmar" ? "pendientes" : filtroEstado}
                  alElegir={(clave) => { setFiltroEstado(clave); setBandaElegida(null); }}
                />

                {(filtroEstado === "pendientes" || filtroEstado === "todos") && (
                  <ParaAtender
                    items={[
                      { clave: "paso", texto: `${nBanda("paso")} ya pasó el plazo`, n: nBanda("paso"), tono: "rojo" },
                      { clave: "pronto", texto: `${nBanda("pronto")} vence${nBanda("pronto") === 1 ? "" : "n"} pronto`, n: nBanda("pronto"), tono: "ambar" },
                      { clave: "firma", texto: `${nBanda("firma")} falta${nBanda("firma") === 1 ? "" : "n"} firma o copia`, n: nBanda("firma"), tono: "pizarra" },
                      { clave: "sin_contrato", texto: `${nBanda("sin_contrato")} sin contrato`, n: nBanda("sin_contrato"), tono: "neutro" },
                    ]}
                    activa={bandaElegida}
                    alTocar={(clave) => setBandaElegida(bandaElegida === clave ? null : (clave as Banda))}
                  />
                )}

                {/* Filtros compactos, sin rótulos y con campos «sm». La sede y el tipo se leen de lo que ya hay en
                    pantalla, no de una lista escrita a mano. */}
                <TarjetaInfo className="flex flex-wrap items-center gap-2 p-3 sm:p-3">
                  <div className="min-w-48 flex-1">
                    <Campo tamano="sm" aria-label="Buscar por nombre o sede" value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Buscar persona" />
                  </div>
                  <div className="w-full sm:w-44">
                    <CampoSelect tamano="sm" value={filtroSede} onChange={(e) => setFiltroSede(e.target.value)} aria-label="Filtrar por sede">
                      <option value="">Todas las sedes</option>
                      {sedesEnTablero.map((sd) => (<option key={sd} value={sd}>{sd}</option>))}
                    </CampoSelect>
                  </div>
                  <div className="w-full sm:w-48">
                    <CampoSelect tamano="sm" value={filtroTipo} onChange={(e) => setFiltroTipo(e.target.value)} aria-label="Filtrar por tipo">
                      <option value="">Todos los tipos</option>
                      {tiposEnDatos.map((t) => (<option key={t} value={t}>{TIPO_CONTRATO[t] ?? t}</option>))}
                    </CampoSelect>
                  </div>
                  {(busca || filtroSede || filtroTipo || bandaElegida !== null || filtroEstado === "sin_firmar") && (
                    <Boton variante="enlace" className="text-xs text-taupe" onClick={limpiarFiltros}>Limpiar</Boton>
                  )}
                </TarjetaInfo>

                {filasVista.length === 0 ? (
                  <EstadoVacio accion={(busca || filtroSede || filtroTipo || bandaElegida !== null)
                    ? <Boton variante="secundario" tamano="sm" onClick={limpiarFiltros}>Limpiar filtros</Boton>
                    : undefined}>
                    {filtroEstado === "archivados"
                      ? "No hay documentos archivados todavía."
                      : filtroEstado === "pendientes" && !(busca || filtroSede || filtroTipo || bandaElegida !== null)
                        ? "Todo al día: no hay contratos que atender."
                        : "No encontramos contratos con estos filtros."}
                  </EstadoVacio>
                ) : filtroEstado === "archivados" ? (
                  <TarjetaInfo className="overflow-hidden p-0 sm:p-0">
                    <ul className="divide-y divide-sand">{filasVista.map((v) => <FilaContrato key={v.key} v={v} />)}</ul>
                  </TarjetaInfo>
                ) : (
                  <div className="grid gap-5">
                    {ORDEN_BANDAS.filter((b) => filasVista.some((v) => v.banda === b)).map((b) => {
                      const dentro = filasVista.filter((v) => v.banda === b);
                      const racimo = b === "pronto" ? racimoDeVencimientos(dentro.map((v) => v.fechaFin)) : null;
                      return (
                        <section key={b} aria-label={TEXTO_BANDA[b].titulo}>
                          <h2 className="mb-1 flex flex-wrap items-baseline gap-2 font-serif text-lg">
                            {TEXTO_BANDA[b].titulo}
                            <span className="font-sans text-xs font-normal text-taupe">{dentro.length} {dentro.length === 1 ? "persona" : "personas"}</span>
                          </h2>
                          <p className="mb-2 text-xs text-taupe">{TEXTO_BANDA[b].ayuda}</p>
                          {racimo && (
                            <BannerAviso enLinea className="mb-2">
                              <strong>{racimo.cuantos} contratos vencen el mismo día</strong> ({formatearFecha(racimo.fecha)}): son {racimo.cuantos} decisiones,
                              redacciones y firmas en la misma semana.
                            </BannerAviso>
                          )}
                          <TarjetaInfo className="overflow-hidden p-0 sm:p-0">
                            <ul className="divide-y divide-sand">{dentro.map((v) => <FilaContrato key={v.key} v={v} />)}</ul>
                          </TarjetaInfo>
                        </section>
                      );
                    })}
                  </div>
                )}
              </>
            )}
          </div>

          {/* HISTORIAL COMPLETO, PLEGADO POR DEFECTO (rediseño).
              La tabla compacta de arriba ya muestra el documento VIGENTE de
              cada persona — el que importa para decidir hoy. Esto es lo que
              queda atrás: convenios y contratos anteriores ya reemplazados
              por uno nuevo, con quién los generó y cuándo se corrigieron. Es
              información secundaria a propósito (spec §24: "no debe competir
              con estado, tipo y vigencia"), así que arranca cerrada. */}
          <details className="min-w-0 space-y-3">
            <summary className="cursor-pointer list-none font-serif text-lg marker:content-['']">
              Historial completo por persona
              {porPersona.length > 0 && (
                <span className="text-taupe">
                  {" "}
                  · {filtro ? `${porPersonaVisible.length} de ${porPersona.length}` : porPersona.length}
                </span>
              )}
            </summary>

            {contratos.length === 0 && (
              <p className="text-sm text-taupe">Todavía no se generó ningún contrato.</p>
            )}
            {contratos.length > 0 && porPersonaVisible.length === 0 && (
              <p className="text-sm text-taupe">Nada del archivo coincide con «{busca.trim()}».</p>
            )}

            {/* AGRUPADO POR PERSONA, Y LOS ANULADOS PLEGADOS.
                La tabla plana repetía el nombre completo en cada fila —cuatro
                veces para la misma persona— y daba a tres pruebas anuladas el
                mismo peso visual que al contrato de verdad. Lo que importa de
                cada persona es UNO: el vigente. Lo demás es historia, y la
                historia se guarda, no se exhibe. */}
            {porPersonaVisible.map(([nombre, filas]) => {
              const vivos = filas.filter((c) => !c.anulado_at);
              const anulados = filas.filter((c) => c.anulado_at);
              return (
                <article key={nombre} className="rounded-lg border border-sand bg-papel p-4">
                  <h3 className="mb-2 font-medium">{nombre}</h3>

                  {vivos.map((c) => (
                    <div key={c.id} className="space-y-1 border-t border-sand/60 pt-2 first:border-0 first:pt-0">
                      <div className="flex flex-wrap items-baseline gap-x-3 text-sm">
                        <span>
                          {formatearFecha(c.fecha_inicio)} –{" "}
                          {c.fecha_fin ? formatearFecha(c.fecha_fin) : "indeterminado"}
                        </span>
                        <span className="text-xs text-taupe">{TIPO_CONTRATO[c.tipo] ?? c.tipo}</span>
                        {/* CAMBIO (0430): "firmado" es `fecha_firma`, no
                            `storage_path` — un contrato puede estar firmado
                            por autoservicio digital sin ningún escaneo. */}
                        <span className={c.fecha_firma ? "text-xs text-verde" : "text-xs text-taupe"}>
                          {c.fecha_firma ? `firmado el ${formatearFecha(c.fecha_firma)}` : "pendiente de firma"}
                        </span>
                        {c.firma_persona_confirmada_at && (
                          <span className="text-xs text-taupe">
                            firma digital confirmada el {formatearFecha(c.firma_persona_confirmada_at.slice(0, 10))}
                          </span>
                        )}
                      </div>

                      {/* Solo mientras falte: confirmar en cada fila lo que ya
                          se hizo llena la pantalla de recibos. Comunicar el
                          contrato a la Autoridad de Trabajo ya no es un
                          trámite de nadie (0470, D. Leg. 1246) — lo único que
                          puede faltar acá es la copia. */}
                      {c.fecha_firma && !c.copia_entregada_at && (
                        <p className="text-xs text-taupe">
                          Falta entregar copia a {c.tipo === "convenio_practicas" ? "la practicante" : "la colaboradora"}
                        </p>
                      )}

                      <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs">
                        <Boton variante="enlace" onClick={() => abrirGenerado(c.id)}>
                          Ver / imprimir
                        </Boton>
                        {/* Editar solo mientras sea un borrador. Una vez
                            firmado —con escaneo o por autoservicio digital
                            (0430)— manda lo que se firmó: se corrige con un
                            adendum o se anula, nunca reescribiendo por detrás
                            lo que ya se firmó. */}
                        {!c.fecha_firma && (
                          <Boton variante="enlace" onClick={() => empezarEdicion(c)}>
                            Editar
                          </Boton>
                        )}
                        {/* "Subir escaneo" sigue disponible aunque ya esté
                            firmado por autoservicio digital: DO puede seguir
                            adjuntando uno de respaldo (0430) — solo deja de
                            ofrecerse cuando YA hay un escaneo guardado. */}
                        {!c.storage_path && (
                          <Boton variante="enlace" onClick={() => abrirSubida(c.id)}>
                            {c.fecha_firma ? "Adjuntar escaneo de respaldo" : "Subir contrato firmado"}
                          </Boton>
                        )}
                        {c.storage_path && (
                          <Boton variante="enlace" onClick={() => verDocumento(c.storage_path!)}>
                            Ver escaneo
                          </Boton>
                        )}
                        {c.fecha_firma && !c.copia_entregada_at && (
                          <Boton variante="enlace" onClick={() => marcarTramite(c.id, "copia")}>
                            Marcar copia entregada
                          </Boton>
                        )}
                        {/* Anular va al final y en taupe: es destructivo, no
                            urgente. En rojo junto a acciones inofensivas se
                            pulsa por error, y el rojo de esta paleta está
                            reservado para lo que de verdad avisa. Se queda como
                            <button> nativo: su hover (taupe → rojo) no es el que
                            trae <Boton variante="enlace"> (hover:text-taupe), y
                            forzar los dos hover en la misma clase deja el color
                            final librado al orden de generación de Tailwind. */}
                        <button className="ml-auto text-taupe underline underline-offset-2 hover:text-rojo" onClick={() => setAnulando(c.id)}>
                          Anular
                        </button>
                      </div>
                      <p className="text-xs text-taupe">
                        Generado el {formatearFecha(c.generado_at.slice(0, 10))}
                        {c.generado_por && ` por ${c.generado_por}`}
                        {/* Que un documento cambió después de generarse se dice,
                            no se deduce del archivo de auditoría. */}
                        {c.editado_at &&
                          ` · editado el ${formatearFecha(c.editado_at.slice(0, 10))}${c.editado_por ? ` por ${c.editado_por}` : ""}`}
                      </p>
                    </div>
                  ))}

                  {anulados.length > 0 && (
                    <details className="mt-2 border-t border-sand/60 pt-2 text-xs text-taupe">
                      <summary className="cursor-pointer">
                        {anulados.length === 1 ? "1 anulado" : `${anulados.length} anulados`}
                      </summary>
                      <ul className="mt-1 space-y-1">
                        {anulados.map((c) => (
                          <li key={c.id} className="flex flex-wrap items-baseline gap-x-3">
                            <span>{formatearFecha(c.generado_at.slice(0, 10))}</span>
                            <span className="min-w-0 flex-1 truncate">{c.anulado_motivo}</span>
                            <button className="underline underline-offset-2 hover:text-tinta" onClick={() => abrirGenerado(c.id)}>
                              Ver
                            </button>
                          </li>
                        ))}
                      </ul>
                    </details>
                  )}
                </article>
              );
            })}
          </details>
        </div>

        {/* LOS DOS PANELES DE ACCIÓN SON MODALES desde que la pantalla se
            partió en dos columnas. Como sección al pie de una de ellas, quien
            pulsaba «Subir contrato firmado» en una fila cualquiera del archivo
            no veía aparecer nada: el panel se abría fuera de la pantalla. */}
        <Modal
          abierto={subiendoPara !== null}
          onCerrar={() => setSubiendoPara(null)}
          bloqueado={guardandoFirma}
          titulo={
            contratos.find((c) => c.id === subiendoPara)?.fecha_firma
              ? "Adjuntar escaneo de respaldo"
              : "Subir contrato firmado"
          }
          ancho="lg"
        >
          {/* CAMBIO (0430): este contrato puede llegar aquí ya firmado por
              autoservicio digital. La fecha que se pida abajo no va a mover
              nada en ese caso —el servidor protege la fecha legal de firma,
              nunca la pisa un escaneo que llega después—, así que se avisa
              en vez de dejar que quien sube el archivo crea que está fijando
              la fecha de firma. */}
          {contratos.find((c) => c.id === subiendoPara)?.fecha_firma ? (
            <p className="mb-4 text-sm text-taupe">
              Este contrato ya está firmado —por autoservicio digital, el{" "}
              {formatearFecha(contratos.find((c) => c.id === subiendoPara)!.fecha_firma!)}—. Esto solo guarda un
              escaneo de respaldo; la fecha de firma no cambia.
            </p>
          ) : (
            <p className="mb-4 text-sm text-taupe">
              El PDF o la foto del contrato ya firmado por las dos partes. Hasta 50 MB.
            </p>
          )}
          <div className="mb-4 grid gap-3 sm:grid-cols-2">
            <label className="flex flex-col gap-1 text-sm">
              Archivo escaneado
              {/* El estilo `file:` es el de la casa —lo usan Documentación,
                  Educación, Normas, Feriados y Disciplina—. Sin él, el input
                  sale con el control crudo del navegador: no parece pulsable
                  y no se parece a nada más del panel. */}
              <input
                type="file"
                accept="image/*,application/pdf"
                onChange={(e) => setArchivo(e.target.files?.[0] ?? null)}
                className="rounded-control border border-sand bg-hueso px-3 py-2 text-sm file:mr-3 file:cursor-pointer file:rounded file:border-0 file:bg-sand file:px-3 file:py-1 file:text-sm hover:file:bg-taupe hover:file:text-crema"
              />
            </label>
            <Campo etiqueta="Fecha de firma" type="date" value={fechaFirma} max={hoyLima()} onChange={(e) => setFechaFirma(e.target.value)} />
          </div>
          {progreso !== null && <p className="mb-2 text-xs tabular-nums">{progreso}%</p>}
          <div className="flex justify-end gap-2">
            <Boton onClick={() => setSubiendoPara(null)}>Cancelar</Boton>
            <Boton variante="primario" onClick={guardarFirma} disabled={guardandoFirma} cargando={guardandoFirma}>
              Guardar
            </Boton>
          </div>
        </Modal>

        <Modal abierto={anulando !== null} onCerrar={() => setAnulando(null)} titulo="Anular contrato" ancho="sm">
          <AreaTexto
            className="mb-1 w-full"
            placeholder="Motivo (mínimo 3 caracteres)"
            value={motivoAnular}
            onChange={(e) => setMotivoAnular(e.target.value)}
            maxLength={250}
          />
          <p className="mb-4 text-right text-xs text-taupe">{motivoAnular.length}/250</p>
          <div className="flex justify-end gap-2">
            <Boton onClick={() => setAnulando(null)}>Cancelar</Boton>
            <Boton variante="peligro" onClick={anular}>Confirmar anulación</Boton>
          </div>
        </Modal>
      </div>

      {/* "Ver / imprimir" un contrato del historial, en un modal flotante y no
          pegado al final de la página: uno del historial puede tener ocho
          páginas, y antes había que bajar hasta el fondo —con el tablero y la
          lista todavía arriba— para verlo. Los botones van ARRIBA del
          documento y no abajo, por lo mismo: buscarlos al final de ocho
          páginas obliga a recorrerlas enteras.

          Al IMPRIMIR el modal deja de serlo: las clases `print:` lo devuelven
          al flujo de la página y le quitan el alto máximo y el scroll propio.
          Sin eso saldría del papel una sola hoja recortada a 90vh, que es
          exactamente lo que no puede pasar con un documento que se firma.

          El scrim es `bg-black/40` y no `bg-tinta/NN` —ver CLAUDE.md: `tinta`
          se aclara en modo oscuro, así que aclararía el fondo en vez de
          oscurecerlo—, y el z-index es el mismo `z-40` del modal compartido. */}
      {/* EL VISOR DE UN CONTRATO. Los datos que lo definen y, debajo, su
          historia — que no hay que inventar: cada evento YA se guarda. El
          escaneo, la copia, el MTPE, la anulación con su motivo, y desde la
          0388 también quién corrigió el borrador antes de firmarlo.

          Se cierra antes de imprimir para no dejar dos modales apilados: el
          documento se abre en el suyo, que ya existe. */}
      {detalle && (
        <div
          className="fixed inset-0 z-30 flex items-center justify-center bg-black/40 p-4 print:hidden"
          onClick={() => setDetalleId(null)}
        >
          <div
            role="dialog"
            aria-modal="true"
            aria-label={`Contrato de ${detalle.persona}`}
            className="flex max-h-[90vh] w-full max-w-2xl flex-col overflow-y-auto rounded-flotante border border-sand bg-papel p-5"
            onClick={(e) => e.stopPropagation()}
          >
            {(() => {
              const c = detalle;
              const vive = !c.anulado_at;
              // Mismo criterio de color que la tabla compacta de la lista
              // (variantePorEstado): "pendiente de firma" es neutral (cálido,
              // discreto — no es un problema todavía), "anulado" es
              // informativo. El mismo estado tiene que verse igual acá y allá.
              const insignia: { texto: string; variante: "neutral" | "informativo" | "alerta" | "advertencia" | "positivo" } = c.anulado_at
                ? { texto: "Anulado", variante: "informativo" }
                // CAMBIO (0430): "firmado" es `fecha_firma`, no `storage_path`.
                : !c.fecha_firma
                  ? { texto: "Pendiente de firma", variante: "neutral" }
                  : c.fecha_fin && c.fecha_fin < hoyLima()
                    ? { texto: "Vencido", variante: "alerta" }
                    : !c.copia_entregada_at
                      ? { texto: "Trámite pendiente", variante: "advertencia" }
                      : { texto: "Vigente", variante: "positivo" };
              // La historia, de lo más reciente a lo más antiguo. Solo eventos
              // que de verdad ocurrieron: una línea de tiempo con huecos
              // rellenados a ojo deja de servir para sustentar nada.
              const hitos: { fecha: string; texto: string; alerta?: boolean }[] = [];
              hitos.push({
                fecha: c.generado_at.slice(0, 10),
                texto: `Contrato generado${c.generado_por ? ` · ${c.generado_por}` : ""}`,
              });
              if (c.editado_at) {
                hitos.push({
                  fecha: c.editado_at.slice(0, 10),
                  texto: `Borrador corregido antes de firmarse${c.editado_por ? ` · ${c.editado_por}` : ""}`,
                });
              }
              // CAMBIO (0430): "Escaneado subido" solo si de verdad hay un
              // escaneo — un contrato puede firmarse sin ninguno.
              if (c.fecha_firma) {
                hitos.push({
                  fecha: c.fecha_firma,
                  texto: c.storage_path ? "Escaneado subido, contrato activado" : "Contrato firmado digitalmente",
                });
              }
              // Distinta de la de arriba cuando SÍ hay escaneo: es la
              // confirmación digital de la colaboradora, no el trámite del
              // escaneado físico. Cuando NO hay escaneo, la de arriba ya lo
              // dice — se omite acá para no repetir la misma fecha dos veces.
              if (c.firma_persona_confirmada_at && c.storage_path) {
                hitos.push({
                  fecha: c.firma_persona_confirmada_at.slice(0, 10),
                  texto: "Colaboradora confirmó su firma digital en el contrato",
                });
              }
              if (c.copia_entregada_at) hitos.push({ fecha: c.copia_entregada_at, texto: "Copia entregada a la colaboradora" });
              if (c.comunicado_mtpe_at) hitos.push({ fecha: c.comunicado_mtpe_at, texto: "Comunicado a la Autoridad de Trabajo" });
              if (c.fecha_fin && c.fecha_fin < hoyLima() && !c.anulado_at) {
                hitos.push({ fecha: c.fecha_fin, texto: "Vencimiento detectado · sistema", alerta: true });
              }
              if (c.anulado_at) {
                hitos.push({ fecha: c.anulado_at.slice(0, 10), texto: `Anulado: ${c.anulado_motivo}`, alerta: true });
              }
              hitos.sort((x, y) => (x.fecha < y.fecha ? 1 : x.fecha > y.fecha ? -1 : 0));

              return (
                <>
                  <div className="mb-4 flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <h2 className="font-serif text-xl">{c.persona}</h2>
                      <p className="text-sm text-taupe">
                        {TIPO_CONTRATO[c.tipo] ?? c.tipo}
                        {c.sede && ` · ${c.sede}`} ·{" "}
                        {c.fecha_fin
                          ? `${formatearFecha(c.fecha_inicio)} – ${formatearFecha(c.fecha_fin)}`
                          : `desde ${formatearFecha(c.fecha_inicio)}, sin fecha de término`}
                      </p>
                    </div>
                    <Insignia variante={insignia.variante} className="shrink-0">
                      {insignia.texto}
                    </Insignia>
                  </div>

                  <div className="mb-4 grid gap-4 sm:grid-cols-[minmax(0,11rem)_minmax(0,1fr)]">
                    <div className="rounded-2xl bg-hueso p-4 text-center">
                      {/* CAMBIO (0430): el título dice si está FIRMADO
                          (fecha_firma) — "Sin escaneado" ya no significa "sin
                          firmar", puede estar firmado por autoservicio
                          digital y no tener ningún escaneo. */}
                      <p className="font-serif text-base">
                        {c.fecha_firma ? "Firmado" : "Sin firmar"}
                      </p>
                      <p className="mb-3 text-xs text-taupe">
                        {c.fecha_firma
                          ? formatearFecha(c.fecha_firma) + (c.storage_path ? "" : " · sin escaneo")
                          : "todavía sin firmar"}
                      </p>
                      {c.storage_path && (
                        <Boton variante="secundario" tamano="sm" className="mb-1.5 w-full bg-papel" onClick={() => verDocumento(c.storage_path!)}>
                          Ver escaneo
                        </Boton>
                      )}
                      <Boton
                        variante="secundario"
                        tamano="sm"
                        className="w-full bg-papel"
                        onClick={() => {
                          setDetalleId(null);
                          void abrirGenerado(c.id);
                        }}
                      >
                        Ver / imprimir
                      </Boton>
                    </div>

                    <dl className="grid grid-cols-2 gap-x-3 gap-y-1 self-start text-sm">
                      <dt className="text-taupe">Cargo</dt>
                      <dd className="text-right">{c.cargo}</dd>
                      <dt className="text-taupe">Remuneración</dt>
                      <dd className="text-right tabular-nums">S/ {Number(c.remuneracion_mensual).toFixed(2)}</dd>
                      <dt className="text-taupe">Copia entregada</dt>
                      <dd className={`text-right ${c.copia_entregada_at ? "text-verde" : "text-taupe"}`}>
                        {c.copia_entregada_at ? formatearFecha(c.copia_entregada_at) : "falta"}
                      </dd>
                      {/* Ningún tipo se registra ante la Autoridad de Trabajo
                          (0470, D. Leg. 1246): ese trámite no le corresponde
                          a nadie desde 2016. Solo se muestra si ya quedó una
                          fecha anotada de antes — no como algo pendiente. */}
                      {c.comunicado_mtpe_at && (
                        <>
                          <dt className="text-taupe">MTPE</dt>
                          <dd className="text-right text-taupe">{formatearFecha(c.comunicado_mtpe_at)}</dd>
                        </>
                      )}
                      <dt className="text-taupe">Generado por</dt>
                      <dd className="text-right">{c.generado_por ?? "—"}</dd>
                    </dl>
                  </div>

                  <div className="mb-4 border-t border-sand pt-3">
                    <p className="mb-2 font-serif text-base">Su historia</p>
                    <ul className="space-y-1">
                      {hitos.map((h, i) => (
                        <li key={`${h.fecha}-${i}`} className="flex gap-3 text-sm">
                          <span className="w-[5.5rem] shrink-0 tabular-nums text-xs text-taupe">{fechaCorta(h.fecha)}</span>
                          <span className={h.alerta ? "text-rojo" : ""}>{h.texto}</span>
                        </li>
                      ))}
                    </ul>
                  </div>

                  <div className="flex flex-wrap items-center gap-2 border-t border-sand pt-3">
                    {/* CAMBIO (0430): "editable" es "sin firmar" (fecha_firma),
                        no "sin escaneo". */}
                    {vive && !c.fecha_firma && (
                      <Boton
                        variante="primario"
                        onClick={() => {
                          setDetalleId(null);
                          void empezarEdicion(c);
                        }}
                      >
                        Editar
                      </Boton>
                    )}
                    {vive && !c.storage_path && (
                      <Boton
                        variante="secundario"
                        onClick={() => {
                          setDetalleId(null);
                          abrirSubida(c.id);
                        }}
                      >
                        {c.fecha_firma ? "Adjuntar escaneo de respaldo" : "Subir firmado"}
                      </Boton>
                    )}
                    {vive && c.fecha_firma && !c.copia_entregada_at && (
                      <Boton variante="secundario" onClick={() => void marcarTramite(c.id, "copia")}>
                        Marcar copia entregada
                      </Boton>
                    )}
                    <Boton variante="enlace" className="ml-auto text-sm" onClick={() => setDetalleId(null)}>
                      Cerrar
                    </Boton>
                    {/* Se queda nativo, igual que su gemelo del archivo: el
                        hover taupe → rojo no coincide con el de <Boton
                        variante="enlace"> y forzarlo deja el color final
                        librado al orden de generación de Tailwind. */}
                    {vive && (
                      <button
                        className="ml-4 text-sm text-taupe underline underline-offset-2 hover:text-rojo"
                        onClick={() => {
                          setDetalleId(null);
                          setAnulando(c.id);
                        }}
                      >
                        Anular
                      </button>
                    )}
                  </div>
                </>
              );
            })()}
          </div>
        </div>
      )}

      {htmlFinalModal && (
        <div
          className="fixed inset-0 z-40 flex items-center justify-center bg-black/40 p-4 print:static print:block print:bg-transparent print:p-0"
          onClick={() => setDocumentoAbierto(null)}
        >
          <div
            role="dialog"
            aria-modal="true"
            aria-label="Contrato generado"
            className="flex max-h-[90vh] w-full max-w-3xl flex-col overflow-hidden rounded-flotante border border-sand bg-crema print:max-h-none print:w-auto print:max-w-none print:overflow-visible print:rounded-none print:border-0"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center gap-3 border-b border-sand bg-sand/30 px-4 py-2 print:hidden">
              <Boton variante="primario" onClick={imprimir}>
                Imprimir / Guardar como PDF
              </Boton>
              <Boton variante="enlace" onClick={() => setDocumentoAbierto(null)}>
                Cerrar
              </Boton>
            </div>
            <div
              className="hoja overflow-y-auto p-8 text-sm leading-relaxed print:overflow-visible print:p-0"
              dangerouslySetInnerHTML={{ __html: htmlFinalModal }}
            />
          </div>
        </div>
      )}
    </main>
  );
}

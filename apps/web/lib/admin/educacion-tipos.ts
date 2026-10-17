import type {
  EstadoConstancia, EstadoEntrega, FrecuenciaPago, MotivoRechazo, TipoConstancia,
} from "@cayla-dynamic/shared";

/**
 * LAS FORMAS DE LO QUE DEVUELVE EDUCACIÓN (0450).
 *
 * Viven acá y no dentro de `page.tsx` porque ya no las usa una sola pieza: la
 * lista, la cuadrícula de meses, el visor y el panel de cada estudio leen las
 * mismas filas. Un archivo `page.tsx` de Next no puede exportar nada más que la
 * página, así que dejarlas ahí obligaba a copiarlas.
 *
 * NO HACE NADA: son solo tipos. Lo que significan los estados lo dice
 * `packages/shared/src/educacion.ts`, y el estado de cada estudio lo contesta la
 * base (`fn_educacion_situacion`), no estas formas.
 */

/** Una fila de `fn_educacion_situacion`: UN ESTUDIO (una familia de asignaciones). */
export interface Situacion {
  familia_id: string;
  asignacion_id: string;
  persona_id: string;
  persona: string;
  sede: string;
  rango: string;
  institucion: string;
  beneficiario: string;
  beneficiario_nombre: string | null;
  monto: number;
  vigente_desde: string;
  vigente_hasta: string;
  vigencia: "futura" | "vigente" | "por_terminar" | "terminada";
  paga: boolean;
  frecuencia_pago: FrecuenciaPago | null;
  proxima_fecha_pago: string | null;
  dias_para_pago: number | null;
  pago_proximo: boolean;
  estado_constancia: EstadoConstancia;
  fecha_pago_constancia: string | null;
  plazo: string | null;
  dias_para_plazo: number | null;
  entrega_id: string | null;
  entrega_estado: EstadoEntrega | null;
  entrega_enviada_at: string | null;
  entrega_archivos: number | null;
  aprobadas: number;
  aviso_fin_id: string | null;
  aviso_fin_motivo: string | null;
}

/** Una constancia que espera revisión (`fn_educacion_entregas_pendientes`). */
export interface Pendiente {
  id: string;
  familia_id: string;
  persona_id: string;
  fecha_pago: string;
  enviada_at: string;
  archivos: number;
  es_reenvio: boolean;
}

export interface ArchivoDeEntrega {
  id: string;
  ruta: string;
  nombre: string;
  tipo_mime: string | null;
  bytes: number | null;
}

/** Una fila de `fn_educacion_entregas`: una constancia con sus archivos. */
export interface Entrega {
  id: string;
  asignacion_id: string;
  fecha_pago: string;
  tipo: TipoConstancia;
  proxima_fecha_pago: string | null;
  nota: string | null;
  estado: EstadoEntrega;
  origen: "colaboradora" | "do" | "migrada";
  enviada_at: string;
  enviada_por: string | null;
  revisada_at: string | null;
  revisada_por: string | null;
  retirada_at: string | null;
  motivo_categoria: MotivoRechazo | null;
  motivo_comentario: string | null;
  reemplaza_a: string | null;
  archivos: ArchivoDeEntrega[];
}

/** Una constancia con el estudio al que pertenece: `fn_educacion_entregas` se pide por familia. */
export interface EntregaDeFamilia extends Entrega {
  familia_id: string;
}

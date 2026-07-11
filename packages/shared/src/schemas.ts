import { z } from "zod";
import { SEDES, TIPOS_MARCA, ROLES } from "./enums";

export const sedeCodigoSchema = z.enum(SEDES);
export const rolSchema = z.enum(ROLES);
export const tipoMarcaSchema = z.enum(TIPOS_MARCA);

export const pinSchema = z
  .string()
  .length(4)
  .regex(/^\d{4}$/, "El PIN debe ser exactamente 4 dígitos");

/** Payload que el terminal envía (online u offline-encolado) para registrar un marcaje. */
export const registrarMarcajeInputSchema = z
  .object({
    clientUuid: z.string().uuid(),
    personaId: z.string().uuid(),
    terminalId: z.string().uuid(),
    tipo: tipoMarcaSchema,
    motivoOtro: z.string().min(3).max(280).optional(),
    timestampCliente: z.string().datetime(),
  })
  .refine((data) => (data.tipo === "salida_otro" ? !!data.motivoOtro : true), {
    message: "motivoOtro es obligatorio cuando tipo es salida_otro",
    path: ["motivoOtro"],
  });

export type RegistrarMarcajeInput = z.infer<typeof registrarMarcajeInputSchema>;

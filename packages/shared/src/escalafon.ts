// ============================================================================
// escalafon.ts — Quién puede actuar sobre la cuenta de quién
// ============================================================================
// PROMETE: dados el rol de quien pide y el rol de la persona objetivo, responde
//          si la operación sobre esa CUENTA (crear, resetear clave, cambiar rol)
//          está permitida.
// ASUME:   que quien llama ya fue autenticado y su rol se leyó de la base, no
//          del cuerpo de la petición.
// NO HACE: permisos sobre datos (eso es RLS), ni sobre marcajes o planilla.
//
// Vive fuera de la ruta HTTP a propósito: es la única parte de /api/admin/cuentas
// que es una regla de negocio pura, y aquí se puede probar sin levantar Next ni
// Supabase. La ruta se queda con lo que sí es suyo — leer la sesión y escribir.
//
// El porqué de que sea un escalafón y no un `if` por acción: la ruta comprobaba
// solo que quien llamara fuera admin o lider_do, y NADA sobre el objetivo. Con
// eso un líder DO podía resetear la clave del admin y recibirla en la respuesta.
// Un `if` por acción habría arreglado las tres de hoy y se habría olvidado en la
// cuarta; una sola función que las tres consultan, no.
// ============================================================================

export const RANGO: Record<string, number> = {
  admin: 3,
  lider_do: 2,
  supervisor_sede: 1,
  integrante: 0,
};

/**
 * Solo se actúa sobre alguien estrictamente por debajo en el escalafón.
 * El admin es el techo del sistema y alcanza a todos, incluido otro admin —
 * si no, dos administradores podrían quedar mutuamente bloqueados el día que
 * uno pierda su clave.
 *
 * Un rol desconocido (una columna con dato viejo, un rol nuevo que nadie mapeó
 * aquí) NIEGA. Se prefiere una encargada que no puede resetear una clave a un
 * rol sin mapear que resulta poder cambiar la del admin.
 */
export function puedeActuarSobre(rolQuienLlama: string, rolObjetivo: string): boolean {
  const yo = RANGO[rolQuienLlama] ?? -1;
  const otro = RANGO[rolObjetivo] ?? -1;
  if (yo < 0 || otro < 0) return false;
  if (yo === RANGO.admin) return true;
  return yo > otro;
}

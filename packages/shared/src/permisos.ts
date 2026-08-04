import type { Rol } from "./enums";

/**
 * QUIÉN PUEDE QUÉ — el único lugar donde se decide.
 *
 * Antes de agosto de 2026 esta regla estaba escrita a mano en 35 sitios, como
 * `rol === "admin" || rol === "lider_do"`. Agregar un rol nuevo, o dejar que una
 * encargada vea una pantalla más, obligaba a acordarse de veinte archivos. Uno
 * se olvida, y el olvido no se ve en la pantalla: se ve cuando alguien mira un
 * sueldo que no le tocaba.
 *
 * Las funciones se nombran por LO QUE AUTORIZAN, no por el rol que las cumple.
 * `puedeVerPlanilla` dice qué se abre; `esAdmin` no dice nada, y por eso invita
 * a reutilizarlo donde no corresponde.
 *
 * ── Ojo: esto NO es la seguridad del sistema ──
 * La seguridad de verdad vive en Postgres (RLS + los guards `SECURITY DEFINER`,
 * ver `fn_es_admin_o_lider` en la migración 0078). Esto de acá decide qué se
 * DIBUJA. Si las dos se desincronizan, la base gana: la pantalla mostrará un
 * botón que devuelve error, que es el lado seguro de equivocarse. Nunca al
 * revés — no confiar en estas funciones para proteger un dato.
 */

/** Desarrollo Organizacional: la dirección y quien lleva DO. Ve todo. */
const DO: readonly Rol[] = ["admin", "lider_do"];

/** DO + la encargada de una sede, que opera el día a día de su equipo. */
const DO_Y_ENCARGADA: readonly Rol[] = ["admin", "lider_do", "supervisor_sede"];

type RolPosible = Rol | string | null | undefined;

/**
 * Guard null-safe, igual que en Postgres: un rol desconocido, vacío o `null`
 * NO pasa. Si la sesión todavía no cargó el rol, la respuesta es "no puede" —
 * la pantalla parpadea, que es preferible a mostrar un sueldo por un instante.
 */
function tiene(lista: readonly Rol[], rol: RolPosible): boolean {
  return typeof rol === "string" && (lista as readonly string[]).includes(rol);
}

/**
 * Plata: sueldos, planilla, boletas, provisiones, costos.
 * Solo DO. Una encargada de sede no ve lo que gana su equipo.
 */
export function puedeVerPlanilla(rol: RolPosible): boolean {
  return tiene(DO, rol);
}

/**
 * Identidad: DNI, cuenta bancaria, dirección, derechohabientes.
 * Solo DO — es el dato con el que se abre una cuenta a nombre de otra persona.
 */
export function puedeVerIdentidad(rol: RolPosible): boolean {
  return tiene(DO, rol);
}

/**
 * Los catálogos que definen cómo se comporta el sistema entero: sedes, áreas,
 * feriados, cuentas del panel, documentación. Solo DO — un feriado mal puesto
 * en una sede cambia el pago de las cuatro.
 */
export function puedeGestionarCatalogos(rol: RolPosible): boolean {
  return tiene(DO, rol);
}

/**
 * El día a día del equipo: correcciones de marcaje, horarios, turnos,
 * ausencias, disciplina, ficha (sin identidad). DO y la encargada de sede.
 *
 * Que la encargada esté acá NO significa que vea todas las sedes: el alcance por
 * sede es otra regla, y va aparte en cada pantalla (`sede_base_id === yo.sede`).
 * Permiso y alcance son dos preguntas distintas — mezclarlas fue lo que hizo
 * falta desenredar.
 */
export function puedeOperarEquipo(rol: RolPosible): boolean {
  return tiene(DO_Y_ENCARGADA, rol);
}

/**
 * ALCANCE, no permiso: quién ve las cuatro sedes y quién solo la suya.
 *
 * Se pregunta junto con `puedeOperarEquipo`, pero es otra cosa. La encargada de
 * AQP puede corregir un marcaje (permiso) — de su gente (alcance). Tenerlas
 * separadas es lo que evita que abrir un permiso abra también las otras sedes
 * sin que nadie lo haya pedido.
 */
export function puedeVerTodasLasSedes(rol: RolPosible): boolean {
  return tiene(DO, rol);
}

/**
 * Las mismas listas, para filtrar datos que vienen de la base (`.in("rol", …)`,
 * `.includes(p.rol)`). Van tipadas como `string` a propósito: el rol que llega de
 * Postgres es texto libre, y exigirle el tipo `Rol` obligaría a un cast en cada
 * llamada — un cast que mentiría si algún día la base trae un rol que este
 * código todavía no conoce.
 */
export const ROLES_CON_PANEL: readonly Rol[] = DO_Y_ENCARGADA;

/** Los roles de DO, para filtrar listas (p. ej. "a quién puedo corregirle el marcaje"). */
export const ROLES_DO: readonly string[] = DO;

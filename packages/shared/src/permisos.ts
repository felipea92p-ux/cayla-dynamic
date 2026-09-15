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
 * Dar de alta, editar la ficha completa, regenerar el PIN, registrar una
 * salida o reactivar a alguien — las cinco escrituras de `/admin/equipo`.
 *
 * Hoy la lista es la misma que `puedeVerPlanilla`, pero se nombra aparte por
 * la misma razón que `puedeGestionarContratos`: esto no es "ver plata", es
 * "administrar personas", y son preguntas distintas aunque hoy las conteste
 * el mismo rol. Espeja la RLS real de esa pantalla — `personas_update_admin_lider`
 * (0003) y el guard `fn_es_admin_o_lider()` que repiten `fn_crear_persona`
 * (0300), `fn_regenerar_pin` (0364), `fn_cesar_persona` (0415) y
 * `fn_reactivar_persona` (0327) — no una preferencia de pantalla.
 *
 * La encargada de sede SÍ puede ABRIR `/admin/equipo` (`puedeOperarEquipo`):
 * ve el padrón de su gente, su sede, su área, su correo. Lo que no puede es
 * escribir nada ahí — ninguna de las cinco RPC la deja pasar — así que
 * mostrarle esos cinco botones no es ofrecerle una acción, es ofrecerle un
 * error garantizado. El error es del diseño, no de ella: la pantalla no debe
 * dibujar lo que sabe de antemano que va a fallar.
 */
export function puedeAdministrarEquipo(rol: RolPosible): boolean {
  return tiene(DO, rol);
}

/**
 * Generar y ver los contratos de trabajo: junta identidad (DNI, dirección) y
 * plata (sueldo) en un solo documento, así que no es ni `puedeVerIdentidad`
 * ni `puedeVerPlanilla` por separado ni `puedeGestionarCatalogos` (esa es
 * para sedes/áreas/feriados/documentación, no para datos personales). Hoy
 * equivale a DO — igual que las dos que junta — pero se nombra por lo que
 * autoriza, no por copiar esa lista: si el día de mañana `puedeVerIdentidad`
 * se abre a otro rol para otra pantalla, esta no debe abrirse con ella sin
 * que alguien lo haya decidido a propósito acá.
 */
export function puedeGestionarContratos(rol: RolPosible): boolean {
  return tiene(DO, rol);
}

/**
 * Publicar o anular un anuncio del tablón de Desarrollo Organizacional. Hoy
 * equivale a DO, igual que `puedeGestionarCatalogos` — pero es una pregunta
 * distinta ("quién habla en nombre de la empresa a las cuatro sedes") y se
 * nombra aparte por la misma razón que `puedeGestionarContratos`: que hoy
 * compartan lista no significa que deban compartir nombre.
 */
export function puedeGestionarAnuncios(rol: RolPosible): boolean {
  return tiene(DO, rol);
}

/**
 * Ver si el despacho de avisos por correo está sano: cuántos quedaron
 * atascados, cuáles fallaron tres veces, cuáles caducaron sin salir. Es una
 * pregunta de operación del sistema, no del equipo: la encargada de una sede
 * no tiene cómo arreglar una clave de Resend, así que mostrárselo sería
 * ruido. Hoy equivale a DO —igual que `puedeGestionarAnuncios`— y se nombra
 * aparte por la misma razón: que hoy compartan lista no significa que deban
 * compartir nombre. Del lado de la base lo decide `fn_alertas_despacho_resumen`
 * con `fn_es_admin_o_lider()`; esto solo decide si se dibuja la tarjeta.
 */
export function puedeVerSaludDeAlertas(rol: RolPosible): boolean {
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
 * Anular un documento disciplinario: dejar sin efecto un memo por un defecto
 * propio, incluso uno ya entregado.
 *
 * Es más estrecho que `puedeOperarEquipo`, que es el permiso de la pantalla:
 * la encargada tramita amonestaciones de su sede, pero `fn_expediente_anular`
 * (0058) solo deja anular a DO. Hasta el rediseño del 2026-09-15 el botón
 * «Anular» se le dibujaba igual a la encargada, y pulsarlo solo podía dar
 * error. Se nombra aparte y no con `puedeAdministrarEquipo` porque la pregunta
 * es otra: quién retira una sanción, no quién da de alta a una persona.
 */
export function puedeAnularDocumentoDisciplinario(rol: RolPosible): boolean {
  return tiene(DO, rol);
}

/** Solo la encargada de sede — no DO. Ver `esRolEncargada` más abajo. */
const SOLO_ENCARGADA: readonly Rol[] = ["supervisor_sede"];

/**
 * Es el rol de encargada de sede — no si hoy actúa como tal en una pantalla
 * (eso puede sumar una marca local, `es_encargada_piso`), sino si el rol en
 * base es ese. Para esa pregunta puntual, no la de permiso.
 */
export function esRolEncargada(rol: RolPosible): boolean {
  return tiene(SOLO_ENCARGADA, rol);
}

/** Solo integrante — ni DO ni encargada. Objetivos la usa para decidir a
 * quién puede gestionar una encargada de sede: a sus integrantes, nunca a
 * otra encargada (esos los gestiona DO). */
const SOLO_INTEGRANTE: readonly Rol[] = ["integrante"];

export function esRolIntegrante(rol: RolPosible): boolean {
  return tiene(SOLO_INTEGRANTE, rol);
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
 * Sacar del sistema el padrón COMPLETO: DNI, dirección, celular y número de
 * cuenta bancaria de todo el equipo, en un archivo.
 *
 * Es el único permiso más estrecho que `puedeVerIdentidad`, y la diferencia no
 * es el dato sino su forma. DO ve esas fichas en pantalla porque las administra;
 * un CSV es otra cosa: sale del sistema, se copia, se reenvía y ya nadie sabe
 * dónde está. Ver un dato y poder llevárselo son dos permisos distintos.
 *
 * Solo `admin` — la dirección. Quien lleva DO edita las fichas todos los días y
 * no necesita descargarlas; el archivo se genera para un trámite concreto (el
 * padrón para el contador) y esa decisión es de dirección.
 */
export function puedeExportarPadron(rol: RolPosible): boolean {
  return tiene(SOLO_DIRECCION, rol);
}

/** Solo la dirección. Ver arriba por qué esto no es lo mismo que DO. */
const SOLO_DIRECCION: readonly Rol[] = ["admin"];

/**
 * Bajarse en CSV el rastro de asistencia: el resumen de jornadas, los marcajes
 * crudos y el libro de correcciones de un rango de fechas.
 *
 * Ninguno de los tres lleva un MONTO —ni sueldo, ni cuenta bancaria—, así que no
 * es `puedeVerPlanilla`: es el día a día del equipo, y hoy equivale a
 * `puedeOperarEquipo`, que es también el permiso de la pantalla hermana
 * (`/admin/correcciones`, que pinta ese mismo libro persona por persona).
 *
 * Ojo con el libro de correcciones, porque su nombre engaña: desde la 0119 no
 * registra solo marcajes. Ahí caen los cambios de vínculo, de régimen de
 * pensión, de retención de 4ta, de rol, de sede base y las altas de documentos
 * firmados, cada uno con su valor anterior, su valor nuevo y su motivo — y una
 * corrección de DNI (`personas.documento`, 0344) deja el número en
 * `valor_nuevo`. Aun así esto NO es `puedeVerIdentidad`, y la razón es
 * incómoda: la RLS de `correcciones_auditoria` ya le entrega esas filas a la
 * encargada de su sede, y la pantalla hermana ya se las pinta. Estrechar solo el
 * CSV no taparía nada; el día que se decida taparlo se tapa en la RLS y en las
 * dos pantallas, no acá.
 *
 * Se nombra aparte igual, por la misma razón que `puedeExportarPadron` existe al
 * lado de `puedeVerIdentidad`: ver un dato en pantalla y poder llevárselo son dos
 * preguntas distintas. Un archivo sale del sistema, se reenvía y ya nadie sabe
 * dónde está — el día que alguien decida que el rastro crudo solo se lo lleva
 * DO, se cambia acá y en
 * `ROLES_EXPORTAN_ASISTENCIA`, que es de donde el menú saca a quién le pinta el
 * renglón.
 *
 * La encargada de sede sí puede: es el archivo que pide una inspección para su
 * tienda, y el alcance —solo su gente— no lo decide esto sino la RLS de
 * `jornadas`, `marcajes` y `correcciones_auditoria` (0003). Permiso y alcance
 * son dos preguntas distintas, como en `puedeOperarEquipo`.
 */
export function puedeExportarAsistencia(rol: RolPosible): boolean {
  return tiene(DO_Y_ENCARGADA, rol);
}

/**
 * Las mismas listas, para filtrar datos que vienen de la base (`.in("rol", …)`,
 * `.includes(p.rol)`). Van tipadas como `string` a propósito: el rol que llega de
 * Postgres es texto libre, y exigirle el tipo `Rol` obligaría a un cast en cada
 * llamada — un cast que mentiría si algún día la base trae un rol que este
 * código todavía no conoce.
 */
export const ROLES_CON_PANEL: readonly Rol[] = DO_Y_ENCARGADA;

/**
 * Quiénes ven el renglón «Exportar CSV» del menú. Es la lista de
 * `puedeExportarAsistencia`, que es quien decide de verdad dentro de la
 * pantalla; existe porque el menú filtra por lista y no por función, y sin ella
 * el día que ese permiso se estreche el renglón seguiría pintándose para quien
 * ya no puede — un clic hasta un «no tienes permiso». Hoy coincide con
 * `ROLES_CON_PANEL`, y `tests/permisos.test.ts` se pone rojo si la lista y la
 * función dejan de decir lo mismo.
 */
export const ROLES_EXPORTAN_ASISTENCIA: readonly Rol[] = DO_Y_ENCARGADA;

/** Los roles de DO, para filtrar listas (p. ej. "a quién puedo corregirle el marcaje"). */
export const ROLES_DO: readonly string[] = DO;

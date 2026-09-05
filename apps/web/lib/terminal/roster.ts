import { createTerminalSupabaseClient } from "@cayla-dynamic/database";
import { guardarRoster, obtenerRoster, type RosterEntry } from "./offline-db";
import { topeDeRed } from "./tope-de-red";

export type FuenteRoster = "servidor" | "cache" | "ninguna";

export interface RosterCargado {
  entradas: RosterEntry[];
  fuente: FuenteRoster;
}

/**
 * DE DÓNDE SALIÓ LA LISTA — y por qué el valor de retorno tiene que decirlo.
 *
 * Esta función se traga toda falla —sin red, error del servidor, la promesa
 * abortada por el tope, `data` nulo— y devuelve la copia guardada, que es
 * justo lo que el terminal necesita para seguir marcando en una sede con mala
 * conexión. Pero al aplanar los cinco desenlaces a un array, «no pude preguntar
 * y no tenía nada guardado» llegaba a la pantalla con la misma cara que «esta
 * sede no tiene gente»: un array vacío. La grilla lo pintaba como «Nadie en
 * esta sede todavía», que es exactamente la mentira que el terminal NO puede
 * decirle a una integrante a las ocho de la mañana.
 *
 * Y no se puede deducir desde la pantalla: cuando el array llega allá, si el
 * servidor contestó o no ya se perdió acá dentro. Por eso viaja `fuente`.
 *
 * `"servidor"` NO significa «vinieron filas»: significa que la consulta se
 * resolvió sin error. Una sede que de verdad todavía no tiene a nadie —un
 * terminal recién vinculado, antes de cargar el equipo— contesta cero filas con
 * un 200 limpio, y eso SÍ es una respuesta: ahí «Nadie en esta sede todavía» es
 * cierto, y por eso ese texto sigue siendo alcanzable. Se cuela en ese mismo
 * saco el terminal DESACTIVADO (ver el comentario de más abajo), que también
 * contesta cero filas; se prefirió así antes que marcar como avería una sede
 * legítimamente vacía — «los falsos positivos son el peor error».
 */
async function respaldoLocal(): Promise<RosterCargado> {
  const entradas = await obtenerRoster();
  return { entradas, fuente: entradas.length > 0 ? "cache" : "ninguna" };
}

/**
 * Lee de `terminal_roster` (vista, 0285) y NO de `personas`, y esa es la mitad
 * del arreglo que no se ve desde aquí.
 *
 * Mientras esto leía `personas`, pedía cuatro campos con toda la educación —pero
 * el token que viaja en la Mac mini alcanzaba la fila entera, y ahí están el DNI
 * y la remuneración. No era un fallo de la policy: **RLS filtra filas, no
 * columnas**, así que ninguna policy podía arreglarlo. La única forma de que ese
 * token no llegue al sueldo es que la superficie que puede leer no lo tenga.
 *
 * La vista sigue acotando a la sede del terminal exactamente como antes: lleva
 * dentro la misma condición de la 0008, y `fn_sede_actual_terminal()` devuelve
 * null a cualquier sesión que no sea un terminal activo.
 *
 * Devuelve `RosterCargado` —lista MÁS de dónde salió— y no un array pelado: ver
 * `respaldoLocal` justo arriba para por qué esa distinción tiene que llegar a la
 * pantalla.
 */
export async function cargarRoster(): Promise<RosterCargado> {
  if (typeof navigator !== "undefined" && !navigator.onLine) {
    return respaldoLocal();
  }

  const supabase = createTerminalSupabaseClient();
  // Con tope y dentro de un try, por lo mismo que terminal-info.ts: sin él, una
  // red colgada dejaba esta promesa pendiente para siempre y la caché de abajo
  // —que existe justo para eso— no llegaba a usarse nunca. Y al abortar,
  // postgrest lanza en vez de devolver { error }.
  let data: unknown[] | null = null;
  try {
    const res = await supabase
      .from("terminal_roster")
      .select("id, nombres, apellidos, sede_codigo, sede_nombre, foto_url")
      .abortSignal(topeDeRed())
      .order("nombres");
    if (res.error) return respaldoLocal();
    data = res.data;
  } catch {
    return respaldoLocal();
  }

  if (!data) {
    return respaldoLocal();
  }

  // UNA RESPUESTA VACÍA NO BORRA LA CACHÉ, y esto es un caso real, no teórico:
  // `guardarRoster` empieza por vaciar el almacén, así que un 200 con cero filas
  // dejaba al terminal sin roster también para cuando volviera a estar offline.
  //
  // Y la forma de llegar ahí la fabrica el propio sistema: la vista acota a la
  // sede del terminal AUTENTICADO, de modo que desactivar un terminal
  // —exactamente lo que la 0202 obliga a hacer antes de borrar su cuenta— lo deja
  // devolviendo cero filas con un 200 limpio. Nadie va a marcar en un terminal
  // desactivado, pero tampoco tiene por qué perder lo que ya tenía guardado.
  //
  // La fuente es "servidor" aunque las filas salgan de la caché: lo que se está
  // diciendo con eso no es de dónde vienen los nombres, es que SÍ hubo respuesta
  // — y por tanto la pantalla no debe hablar de avería.
  if (data.length === 0) {
    return { entradas: await obtenerRoster(), fuente: "servidor" };
  }

  // La vista trae la sede ya resuelta en dos columnas, así que se acabó el
  // desempaquetado del join anidado que PostgREST devolvía a veces como objeto
  // y a veces como array de uno.
  const roster: RosterEntry[] = data.map((p: any) => ({
    id: p.id,
    nombres: p.nombres,
    apellidos: p.apellidos,
    sedeCodigo: p.sede_codigo ?? "?",
    sedeNombre: p.sede_nombre ?? "?",
    fotoUrl: p.foto_url ?? null,
  }));
  await guardarRoster(roster);
  return { entradas: roster, fuente: "servidor" };
}

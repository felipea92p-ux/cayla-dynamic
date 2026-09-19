import { hoyLima, puedeVerNovedad, type AudienciaNovedad } from "@cayla-dynamic/shared";

// ============================================================================
// Novedades del sistema — lo que mejoró en Dynamic, dicho para quien lo usa.
// ============================================================================
//
// QUÉ PROMETE
//   Que cada mejora que alguien del equipo nota al usar el sistema quede
//   escrita aquí, en palabras de quien usa la pantalla, y aparezca en
//   /admin/anuncios. Es una lista escrita a mano: nadie la genera sola.
//
// QUÉ ASUME
//   Que quien fusiona un cambio visible agrega su entrada EN EL MISMO PULL
//   REQUEST. Nada lo obliga —ver «SE ROMPE SI»—; la regla está en CLAUDE.md.
//
// POR QUÉ ESTÁ EN EL CÓDIGO Y NO EN LA TABLA `anuncios`
//   · Sale en el mismo despliegue que la mejora que cuenta, ni antes ni
//     después. Una fila en `anuncios` la pega Felipe a mano, y la migración
//     se pega ANTES de fusionar: el aviso «ya puedes hacer X» estaría en
//     pantalla mientras X todavía no existe.
//   · No cuesta un SQL a producción por cada texto.
//   · `anuncios.publicado_por` exige una persona real: las novedades no las
//     firma nadie de DO, y meterlas ahí mezclaría la voz de la empresa con la
//     del sistema. Por eso van en una sección aparte y con su propia etiqueta.
//
// POR QUÉ NO SE GENERAN DESDE LOS COMMITS
//   Se midió el 2026-09-19: de los 169 commits sin fusiones desde el 15 de
//   septiembre, 42 son «La consulta de qué falta pegar se pone al día sola» y
//   otros 13 son renumeraciones y rescates de migraciones — sin contar pruebas,
//   lint ni documentos. Es bastidores. Lo que el equipo llegó a notar son unas
//   pocas mejoras, y decidir cuáles es criterio de una persona, no de un script.
//
// QUÉ VA Y QUÉ NO VA
//   Va: lo que alguien nota —una pantalla que dice algo nuevo, un error que
//   dejó de pasar, un botón que antes no había—. Se cuenta qué cambió y por
//   qué le sirve a quien lo lee, nunca cómo se hizo.
//   No va: refactores, pruebas, migraciones internas, renumeraciones.
//
//   NUNCA una regla de pago, un descuento, una tardanza o algo disciplinario
//   como forma de avisar. «Leído» en Anuncios es un marcador liviano, sin
//   acuse (ver el encabezado de la 0351): no prueba que nadie se enteró, y
//   la ley exige poder probarlo. Lo que cambie cuánto se le paga a alguien
//   viaja por la Política salarial, que está versionada y se acusa; aquí, como
//   mucho, se avisa que hay algo nuevo que leer allá.
//
//   Sin nombres, sin montos, sin documentos. La audiencia es relevancia, no
//   confidencialidad: este archivo baja al navegador de todo el mundo.
//
// CÓMO SE AGREGA
//   Una entrada nueva ARRIBA de la lista, en el mismo PR que el cambio.
//   `id` = `AAAA-MM-DD-lo-que-cambio`, único y para siempre. `fecha` = el día
//   en que se fusiona (main se publica sola, así que es el día en que llega a
//   producción); si el PR se fusiona otro día, se corrige antes de fusionar.
//   Una entrada publicada no se edita ni se borra: si algo salió mal contado,
//   se agrega otra que lo corrija —el mismo criterio de `anuncios`, que se
//   anulan y no se editan.
//
// POR QUÉ «NUEVA» SE CALCULA POR FECHA Y NO SE GUARDA POR PERSONA
//   Guardar quién leyó cada novedad pide una tabla, su migración pegada a
//   mano y sus pruebas —para algo que ningún trámite necesita saber—. Con la
//   fecha basta, funciona igual sin conexión, y no tiene el defecto de un
//   «leído» guardado en el navegador: en un equipo compartido le ocultaría a
//   la segunda persona lo que nunca vio (la misma objeción que descartó
//   `localStorage` en la Bandeja, ver `bandeja-mia.ts`). El precio: quien la
//   leyó ayer la sigue viendo «Nueva» hasta que pasen los días.
//
// SE ROMPE SI
//   Se fusiona un cambio visible sin su entrada: la sección envejece y, sin
//   decirlo, le cuenta al equipo que nada mejora. Y si alguien escribe aquí
//   una regla de pago pensando que «ya se avisó».
// ============================================================================

export interface Novedad {
  /** `AAAA-MM-DD-lo-que-cambio`. Único y estable: nunca se reutiliza ni se cambia. */
  id: string;
  /** Día de Lima (`2026-09-18`) en que llegó a producción. */
  fecha: string;
  titulo: string;
  /** Qué mejoró, en lenguaje de quien usa la pantalla. Párrafos separados por línea en blanco. */
  queMejoro: string;
  audiencia: AudienciaNovedad;
}

/** Cuántos días una novedad se muestra como «Nueva» desde su fecha. */
export const DIAS_COMO_NUEVA = 14;

// La más reciente primero. Ver «CÓMO SE AGREGA» arriba.
export const NOVEDADES: readonly Novedad[] = [
  {
    id: "2026-09-19-anuncios-cuenta-que-mejora",
    fecha: "2026-09-19",
    titulo: "Anuncios ahora también cuenta qué mejora en el sistema",
    queMejoro:
      "Cada vez que Dynamic cambia en algo que se nota al usarlo, lo explicamos aquí en palabras simples: qué cambió y por qué te sirve.\n\n" +
      "Va aparte de los comunicados de Desarrollo Organizacional, para que no se confundan. Lo que cambió en los últimos días ya está listado abajo.",
    audiencia: "todos",
  },
  {
    id: "2026-09-18-lider-de-equipo",
    fecha: "2026-09-18",
    titulo: "«Líder de equipo» reemplaza a «encargada» en las pantallas",
    queMejoro:
      "Quien lidera el equipo de una sede tenía dos nombres según la pantalla: en unas decía «líder de equipo» y en otras «encargada». " +
      "Ahora todas dicen «líder de equipo» (o «líder», en los contadores cortos).\n\n" +
      "No cambia el trabajo ni los permisos de nadie, solo la palabra.",
    audiencia: "todos",
  },
  {
    id: "2026-09-18-dashboard-pausa-aparte",
    fecha: "2026-09-18",
    titulo: "El Dashboard separa a quien está en pausa de quien está trabajando",
    queMejoro:
      "Antes, quien salía a refrigerio o a hacer un trámite seguía contando como «trabajando ahora», y el Dashboard podía decir «14 trabajando» con nueve de ellas fuera del piso. " +
      "Ahora «trabajando» cuenta solo a quien está en el piso, y quienes están en pausa aparecen en su propio recuadro.\n\n" +
      "Cada persona en pausa muestra desde qué hora salió y cuánto lleva fuera, y quien lleva más tiempo va primero: así un refrigerio de 40 minutos ya no se ve igual que una salida que nadie cerró hace tres horas. " +
      "La Hoja de sede dice lo mismo, con la hora de salida.",
    audiencia: "panel",
  },
  {
    id: "2026-09-18-dashboard-sede-cerrada",
    fecha: "2026-09-18",
    titulo: "El Dashboard ya no pide meta a una sede que cerró",
    queMejoro:
      "Terminado el horario de una tienda, con todo su equipo ya retirado, el Dashboard seguía marcándola en rojo con «Faltan 8». " +
      "Ahora esa sede pasa a gris y dice «Fuera de horario». Si ya era hora de abrir y nadie llegó, sigue en rojo, como debe ser.\n\n" +
      "Y cuando una meta no se puede cumplir porque es mayor que el equipo de esa sede, la tarjeta lo dice y sugiere corregir la meta en Turnos, en vez de mostrar un faltante que nadie puede resolver.",
    audiencia: "panel",
  },
  {
    id: "2026-09-18-turnos-cobertura",
    fecha: "2026-09-18",
    titulo: "Turnos: la cobertura dice lo que realmente mide",
    queMejoro:
      "Un día con gente programada solo en áreas que no son operativas —una oficina, por ejemplo— decía «sin turnos», aunque los turnos sí estaban dibujados. " +
      "Ahora dice «sin operativas programadas», que es lo que la cobertura cuenta, y los nombres de cada fila ya no se cortan con puntos suspensivos.",
    audiencia: "panel",
  },
];

/**
 * Las novedades que le corresponden a este rol, la más reciente primero.
 * Con el mismo día, se respeta el orden en que están escritas en la lista.
 */
export function novedadesPara(
  rol: string | null | undefined,
  lista: readonly Novedad[] = NOVEDADES,
): Novedad[] {
  return lista
    .filter((n) => puedeVerNovedad(rol, n.audiencia))
    .sort((a, b) => b.fecha.localeCompare(a.fecha));
}

function diasDesde(fecha: string, hoy: string): number {
  const [a, m, d] = fecha.split("-").map(Number);
  const [ha, hm, hd] = hoy.split("-").map(Number);
  return Math.round((Date.UTC(ha, hm - 1, hd) - Date.UTC(a, m - 1, d)) / 86_400_000);
}

/** ¿Se muestra como «Nueva»? Los últimos `DIAS_COMO_NUEVA` días, sin contar el futuro. */
export function esNovedadNueva(n: Novedad, hoy: string = hoyLima()): boolean {
  const dias = diasDesde(n.fecha, hoy);
  return dias >= 0 && dias <= DIAS_COMO_NUEVA;
}

/**
 * `2026-09-18` → «18 set 2026». Se formatea en UTC sobre mediodía: con
 * `new Date("2026-09-18")` a secas el navegador de Lima la mostraría como el 17.
 */
export function fechaDeNovedad(fecha: string): string {
  return new Intl.DateTimeFormat("es-PE", {
    day: "numeric", month: "short", year: "numeric", timeZone: "UTC",
  }).format(new Date(`${fecha}T12:00:00Z`));
}

// La lista de pantallas del panel, y nada más. Vive suelta de `nav.tsx` porque
// la consumen cuatro cosas que no deben conocerse entre sí: el sidebar, el
// cajón de teléfono, el buscador (⌘K) y el modal de atajos (?). Cuando todo
// esto vivía en `nav.tsx`, mover la barra al layout habría creado un ciclo
// —layout → nav → panel → nav— así que el dato se separó del dibujo.
//
// Acá NO hay JSX ni estado: es data y dos funciones puras. Por eso se puede
// probar con vitest en entorno node, que es el único que este repo tiene.

import {
  LayoutDashboard, Inbox, TriangleAlert, PencilLine, CalendarClock, Clock, Gauge,
  Users, IdCard, TreePalm, Gavel, ReceiptText, PiggyBank, Target, LayoutGrid, KeyRound,
  Building2, FileDown, FileText, FileSignature, CalendarCheck, Coins, Scale, GraduationCap, HandCoins,
  BookText, UserRound, ScrollText, Megaphone, Palette, MessagesSquare, Archive, ShieldCheck, FileStack, SlidersHorizontal,
  type LucideIcon,
} from "lucide-react";
import { ROLES_CON_PANEL, ROLES_DO, ROLES_EXPORTAN_ASISTENCIA, ROLES_GESTIONAN_BOLETAS } from "@cayla-dynamic/shared";

// Qué renglones del menú ve cada quien. Las listas vienen de `permisos.ts` — el
// menú no vuelve a decidir quién es DO, solo lo consulta.
const DO = ROLES_DO;
const SEDE = ROLES_CON_PANEL;

// Los contadores del menú, por nombre. Antes la condición estaba escrita a
// mano contra el `href` y repetida SEIS veces (tres en la barra de escritorio y
// tres en el cajón); si alguien cambiaba una ruta, cinco copias se quedaban
// atrás en silencio. Ahora el ítem dice cuál le toca y el panel lo pinta una vez.
export type Contador = "educacion" | "vacaciones" | "revisiones" | "mio" | "bandeja";

export type Item = {
  href: string;
  label: string;
  Icon: LucideIcon;
  roles?: readonly string[];
  contador?: Contador;
  /**
   * Una condición que el rol no alcanza a decir. Hoy una sola: «casos», que
   * se ve si `fn_ve_casos` (0488) dice que sí — la Gerencia General es una
   * MARCA, no un rol, y de los admins solo ella gestiona reportes.
   */
  requiere?: "casos";
};

export type Grupo = { label?: string; items: Item[] };

// Siete grupos, no cinco (2026-09-07). Los tres movimientos y su porqué:
//
//   · «Ausencias» pasa de Nómina a Asistencia. Su propia pantalla se presenta
//     como «todos los días que alguien no vino, y por qué», la opera la
//     encargada (`puedeOperarEquipo`) y era el ÚNICO ítem de rol SEDE dentro de
//     un grupo entero de rol DO: para una encargada, «Nómina» tenía un solo
//     renglón y no se leía como nómina.
//
//   · «Publicaciones» es un grupo nuevo con las TRES únicas entradas que van sin
//     `roles`. No es casualidad que sean tres: la Ley 30709 obliga a informar la
//     política salarial a todo el equipo y el RIT hay que entregarlo y poder
//     probarlo. Estaban repartidas en tres grupos distintos, así que una
//     integrante veía cuatro renglones sueltos sin ninguna lógica visible.
//     Juntas, su menú entero pasa a ser «Lo mío» + estos tres.
//
//   · «Apariencia» baja de la cabecera a Configuración. Estaba junto a Dashboard
//     y Bandeja, que se miran varias veces al día, siendo que es un ajuste que
//     se toca una vez. Comparte permiso (`puedeGestionarCatalogos`) y frecuencia
//     con Áreas, Sedes y Cuentas.
//
//   · «Nómina» pasa a llamarse «Pago». `git grep -niI "nómina"` en todo el
//     repo daba tres coincidencias en total, y las otras dos eran un
//     comentario ajeno y el nombre de una migración: en todo lo demás la casa
//     dice «planilla» y «pago» (periodos_planilla, fn_planilla_calcular,
//     docs/planilla-anexo-tecnico.md, y CLAUDE.md con «lo que registra este
//     sistema alimenta el pago»). El menú era el único sitio con la palabra
//     que no se usa en ningún otro lado, justo encima de un renglón que
//     nombra lo mismo con la palabra de la casa («Planilla»).
//
// Lo que NO cambió: ninguna URL, ningún `roles`, ningún nombre de pantalla.
//
// Ocho desde el 2026-10-01: «Empresa», con un solo renglón, «Archivo» (0503).
// Ninguno de los siete le servía, y cada uno por una razón concreta: Personas es
// de papeles de alguien y este es de CAYLA; Publicaciones es lo que TODO el
// equipo tiene que poder abrir, y esto lo ve solo DO; Configuración cambia cómo
// funciona el sistema, y ahí nadie busca una constancia durante una inspección.
// Se llama «Archivo» y no «Documentos» porque «Documentación» (Personas) ya es
// otra cosa —los pactos que firma cada persona— y en el buscador (⌘K) las dos
// saldrían juntas al escribir «docu».
export const GRUPOS: Grupo[] = [
  { items: [
    // «Lo mío» va sin `roles` y va PRIMERO: es lo único de este menú que habla de
    // quien lo está mirando. Para una integrante es su pantalla —sus días, sus
    // horas, sus tardanzas— y para DO es la suya, que también la tiene.
    // El ÚNICO contador de este menú que habla de quien lo mira, no del equipo:
    // su contrato sin firmar, su constancia de ley pendiente, sus días con el
    // marcaje incompleto. Sale de lib/bandeja-mia.ts, la misma función que pinta
    // el número del botón «Bandeja» de /mio — no hay una segunda cuenta.
    //
    // Se salta la vara de los otros tres («¿tiene fecha límite y cuesta plata
    // pasarla?») a propósito y por la misma excepción que ya se escribió para el
    // aviso de acuses: solo lo ve quien tiene algo pendiente, y deja de verlo el
    // día que lo resuelve. No es un adorno permanente; es una tarea con final.
    // Sin él, quien trabaja todo el día en el panel no se entera nunca de que
    // tiene su propio contrato sin firmar.
    { href: "/mio", label: "Info", Icon: UserRound, contador: "mio" },
    // Con `roles` desde el 2026-09-04. Antes iba sin filtro, así que una
    // integrante con cuenta —las hay: se les invita para que acusen la política
    // salarial (Ley 30709)— aterrizaba aquí y veía un tablero de encargada que su
    // propia RLS le devuelve casi vacío. No era una fuga; era una pantalla que no
    // es suya y que se lee como que el sistema no tiene datos.
    { href: "/admin/dashboard", label: "Dashboard", Icon: LayoutDashboard, roles: SEDE },
    // Junta en una sola vista las nueve secciones de abajo (educación,
    // ausencias, incidencias, y seis más que fueron llegando después: sin
    // horario vigente, revisión de ruta, revisión de contrato, solicitudes de
    // vacaciones, solicitudes de cambio de perfil, salud del despacho de
    // avisos) — mismas RPC, mismo criterio de "pendiente" que cada una ya usa
    // por su cuenta.
    //
    // SÍ lleva contador propio desde el 2026-09-12 (`lib/admin/bandeja-equipo.ts`),
    // y es la excepción a la regla que este comentario tenía escrita: «un aviso
    // que aparece en todos lados deja de ser aviso». Esa regla seguía siendo
    // cierta para las TRES secciones originales, que ya avisaban cada una en su
    // propio renglón — pero de las nueve de hoy, solo esas tres avisaban en
    // algún lado. Las otras seis no encendían nada: alguien podía tener una
    // solicitud de vacaciones o una declaración de ruta esperando y no
    // enterarse sin entrar a mirar. El bolito de acá es la ÚNICA señal de esas
    // seis, no una cuarta copia de las tres que ya tienen la suya.
    { href: "/admin/bandeja", label: "Bandeja", Icon: Inbox, roles: SEDE, contador: "bandeja" },
  ] },
  { label: "Asistencia", items: [
    { href: "/admin/incidencias", label: "Incidencias", Icon: TriangleAlert, roles: SEDE, contador: "revisiones" },
    { href: "/admin/correcciones", label: "Correcciones", Icon: PencilLine, roles: SEDE },
    { href: "/admin/turnos", label: "Turnos", Icon: CalendarClock, roles: SEDE },
    { href: "/admin/horarios", label: "Horarios", Icon: Clock, roles: SEDE },
    // La ruta sigue siendo /admin/horas —hay enlaces vivos— pero el nombre no
    // decía lo que hay ahí: el desempeño de TODO el equipo, sin entrar a nadie.
    // Con «Horas» el camino que se usaba era Equipo → persona → ficha → pestaña.
    { href: "/admin/horas", label: "Desempeño", Icon: Gauge, roles: SEDE },
    // Llegó desde Nómina (ver el porqué arriba). Es el único renglón de este
    // grupo que también toca plata, pero lo que se hace acá es registrar días.
    { href: "/admin/ausencias", label: "Ausencias", Icon: TreePalm, roles: SEDE, contador: "vacaciones" },
  ] },
  { label: "Personas", items: [
    { href: "/admin/equipo", label: "Equipo", Icon: Users, roles: SEDE },
    { href: "/admin/datos-personales", label: "Datos personales", Icon: IdCard, roles: SEDE },
    { href: "/admin/contratos", label: "Contratos", Icon: ScrollText, roles: DO },
    { href: "/admin/documentacion", label: "Documentación", Icon: FileSignature, roles: DO },
    // En qué seguro está cada colaborador y qué póliza le falta (0528): FOLA para
    // los practicantes, EsSalud —por planilla— para el resto, y los que DO agregue.
    // Va junto a Contratos y Documentación porque es el mismo tipo de cosa: un
    // papel POR PERSONA con su estado de firma. No va en Pago aunque cueste plata:
    // la prima se paga a la aseguradora y no pasa por la planilla. Sin contador
    // propio: lo que pide (alguien sin póliza, una por vencer, un paso del papeleo,
    // un cambio de seguro por cerrar) ya lo cuenta la Bandeja, y un aviso en dos
    // sitios deja de ser aviso.
    { href: "/admin/seguros", label: "Seguros", Icon: ShieldCheck, roles: DO },
    { href: "/admin/objetivos", label: "Objetivos", Icon: Target, roles: SEDE },
    // «Casos» (Reportes, 0483/0488; plan, decisión 21). Aquí y no en el grupo
    // «Reportes», que son informes: este nombre evita que un ítem y un grupo
    // digan lo mismo con dos sentidos. Va ANTES de Disciplina, no después: un
    // reporte no es una falta, y el orden no debe sugerir que lleva a una.
    { href: "/admin/casos", label: "Casos", Icon: MessagesSquare, roles: SEDE, requiere: "casos" },
    { href: "/admin/disciplina", label: "Disciplina", Icon: Gavel, roles: SEDE },
  ] },
  { label: "Pago", items: [
    { href: "/admin/planilla", label: "Planilla", Icon: ReceiptText, roles: DO },
    // Las boletas OFICIALES del contador (0482), con renglón propio desde el
    // 2026-10-16. Hasta entonces la única puerta era el botón «Boletas del
    // periodo» dentro de Planilla: se agrandó una vez porque nadie lo
    // encontraba, y aun así DO volvió a preguntar dónde estaba. El problema no
    // era el tamaño del botón, era que había que saber que vive DENTRO de otra
    // pantalla. Va justo debajo de Planilla porque es lo que sigue a cerrarla.
    // Sin `?periodo=`, la pantalla abre el último periodo pagado (`periodoInicial`).
    { href: "/admin/planilla/boletas", label: "Boletas", Icon: FileStack, roles: ROLES_GESTIONAN_BOLETAS },
    { href: "/admin/provisiones", label: "Provisiones", Icon: PiggyBank, roles: DO },
    { href: "/admin/costos", label: "Costos", Icon: Coins, roles: DO },
    { href: "/admin/liquidaciones", label: "Liquidaciones", Icon: HandCoins, roles: DO },
    { href: "/admin/educacion", label: "Educación", Icon: GraduationCap, roles: DO, contador: "educacion" },
    // Se queda en Nómina y no en Asistencia, aunque lo que se registra sea un día
    // de descanso: existe por el pago. El compensatorio es lo que quita la
    // sobretasa del 100 % del feriado trabajado (art. 9, D. Leg. 713).
    { href: "/admin/feriados", label: "Feriados", Icon: CalendarCheck, roles: DO },
  ] },
  // Las tres pantallas que TODO el equipo tiene que poder abrir. Ninguna lleva
  // `roles`, y no es un olvido: es la obligación legal de informar y de poder
  // probar que se informó. Un menú que solo ve DO no entrega nada.
  { label: "Publicaciones", items: [
    { href: "/admin/politica-salarial", label: "Política salarial", Icon: Scale },
    { href: "/admin/normas", label: "Normas", Icon: BookText },
    // Sin contador propio, por la misma regla de los tres de arriba: un anuncio
    // no tiene fecha límite que cueste plata pasarla.
    { href: "/admin/anuncios", label: "Anuncios", Icon: Megaphone },
  ] },
  { label: "Reportes", items: [
    { href: "/admin/reporte-sede", label: "Hoja de sede", Icon: FileText, roles: SEDE },
    // Con `roles` desde el 2026-09-04 (hallazgo 26). Iba sin filtro, así que una
    // integrante con cuenta —las hay, para acusar la política salarial— veía
    // «Exportar CSV» y entraba. No era una fuga: la RLS de `jornadas`, `marcajes`
    // y `correcciones_auditoria` solo le devuelve lo suyo. Era una pantalla que
    // no es suya y que se lee como que el sistema no tiene datos. La lista es la
    // de `puedeExportarAsistencia`, que es quien decide de verdad dentro de la
    // pantalla; hoy coincide con SEDE, pero se nombra aparte para que estrechar
    // el permiso apague también el renglón.
    { href: "/admin/exportar", label: "Exportar CSV", Icon: FileDown, roles: ROLES_EXPORTAN_ASISTENCIA },
  ] },
  // Lo que la empresa presenta o recibe de una autoridad: inscripciones,
  // licencias, REMYPE. Va al fondo, junto a Configuración, por frecuencia —se
  // abre pocas veces al año—, aunque el día que se abre sea urgente.
  { label: "Empresa", items: [
    { href: "/admin/archivo", label: "Archivo", Icon: Archive, roles: DO },
  ] },
  { label: "Configuración", items: [
    { href: "/admin/areas", label: "Áreas", Icon: LayoutGrid, roles: DO },
    { href: "/admin/sedes", label: "Sedes", Icon: Building2, roles: DO },
    // `roles: SEDE`, no `DO`. Estuvo en `DO` desde el 2026-09-04 por un
    // supuesto que no era cierto: el comentario de entonces decía que la
    // pantalla "se degrada sola... o sea que el renglón solo llevaba a una
    // puerta cerrada" para quien no gestiona catálogos. Pero
    // `admin/cuentas/page.tsx` tiene esa rama para "no admin" desde que se
    // creó, el 2026-07-12 (`4d71fd8`) — no lleva a una puerta cerrada, lleva a
    // "Mi cuenta": solo cambiar la propia contraseña, sin la gestión de
    // equipo. Gatearlo a DO dejó a cualquier encargada de sede sin ningún
    // camino en la interfaz para cambiar su propia clave (hallazgo del
    // 2026-09-07, `docs/estado.md`) — sí podía entrar por URL directa, pero
    // ni el menú, ni el buscador (⌘K) ni los atajos, que comparten esta
    // lista, se lo ofrecían.
    { href: "/admin/cuentas", label: "Cuentas", Icon: KeyRound, roles: SEDE },
    // El tema global (claro/oscuro) de panel Y terminal — no un color libre,
    // ver apps/web/app/(admin)/admin/apariencia/page.tsx. Mismo permiso que
    // el resto de este grupo: es un catálogo del sistema, no un dato de una
    // persona.
    { href: "/admin/apariencia", label: "Apariencia", Icon: Palette, roles: DO },
    // Los números del sistema que DO puede cambiar sin pedir código (0552): días
    // de prueba, horas del auto-cierre, el aviso de descanso médico. Cada cambio
    // deja quién, cuándo y por qué. Va en Configuración y no en Pago aunque a
    // futuro entren parámetros de plata: lo que se abre aquí es el CATÁLOGO, y
    // el pago se sigue mirando en Planilla. Mismo permiso que el grupo; lo
    // normativo lo separa `puedeCambiarParametro`, no el menú.
    { href: "/admin/parametros", label: "Parámetros", Icon: SlidersHorizontal, roles: DO },
  ] },
];

// Cualquier sub-ruta cuelga de su pantalla: /admin/planilla/boleta resalta
// "Planilla", /admin/normas/[id]/imprimir resalta "Normas", /mio/boleta
// resalta "Mi perfil". Hasta el 2026-09-11 esto no existía y seis sub-rutas
// (boleta de planilla, memo de disciplina, imprimir/constancias de normas,
// constancias de política salarial, boleta de "lo mío") dejaban el menú sin
// nada resaltado — un caso general, no seis excepciones para enumerar a mano.
//
// Y cuando dos renglones cuelgan uno del otro, gana el más específico
// (2026-10-16): /admin/planilla/boletas es un renglón propio Y una sub-ruta de
// /admin/planilla, así que la regla de arriba encendía los dos a la vez. No se
// resuelve con un `if` para Boletas: se resuelve preguntando si otro renglón
// del menú reclama la ruta con más precisión. Así /admin/planilla/boleta (la
// del sistema, sin renglón propio) sigue resaltando «Planilla», y el día que
// otra sub-ruta gane su renglón no hace falta tocar esto.
const RUTAS_DEL_MENU: readonly string[] = GRUPOS.flatMap((g) => g.items.map((i) => i.href));

export function esActivo(pathname: string, href: string): boolean {
  if (!coincide(pathname, href)) return false;
  return !RUTAS_DEL_MENU.some((otra) => otra.startsWith(href + "/") && coincide(pathname, otra));
}

function coincide(pathname: string, href: string): boolean {
  if (pathname === href) return true;
  if (pathname.startsWith(href + "/")) return true;
  // El perfil de una persona (/admin/personas/[id]) se entra desde Equipo, así
  // que mientras estás en él, resaltamos "Equipo" para no dejar la ubicación
  // huérfana — son rutas hermanas, no una cuelga de la otra, así que la regla
  // general de arriba no lo cubre.
  if (href === "/admin/equipo" && pathname.startsWith("/admin/personas")) return true;
  // Vacaciones se absorbió en Ausencias (0101); el enlace viejo sigue llevando allí.
  if (href === "/admin/ausencias" && pathname === "/admin/vacaciones") return true;
  return false;
}

// Las rutas del grupo `(admin)` que NO llevan marco (sidebar + barra superior).
//
// Existe porque el marco pasó a vivir en `(admin)/layout.tsx`, y ese layout
// envuelve también el login y «nueva clave», donde todavía no hay sesión a la
// que preguntarle nada — que era exactamente la razón por la que antes cada
// pantalla renderizaba `<AdminNav/>` a mano. Las cuatro últimas son
// redirecciones: dibujarles un menú alrededor sería pintar un marco que se
// desmonta en el mismo instante.
export const RUTAS_SIN_MARCO: readonly string[] = [
  "/admin", // redirige a /admin/dashboard o a /admin/login
  "/admin/login",
  "/admin/olvide-clave",
  "/admin/nueva-clave",
  "/admin/perfil", // redirige a /admin/equipo
  "/admin/vacaciones", // redirige a /admin/ausencias
];

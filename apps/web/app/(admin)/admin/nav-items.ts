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
  BookText, UserRound, ScrollText, Megaphone, Palette,
  type LucideIcon,
} from "lucide-react";
import { ROLES_CON_PANEL, ROLES_DO, ROLES_EXPORTAN_ASISTENCIA } from "@cayla-dynamic/shared";

// Qué renglones del menú ve cada quien. Las listas vienen de `permisos.ts` — el
// menú no vuelve a decidir quién es DO, solo lo consulta.
const DO = ROLES_DO;
const SEDE = ROLES_CON_PANEL;

// Los tres contadores del menú, por nombre. Antes la condición estaba escrita a
// mano contra el `href` y repetida SEIS veces (tres en la barra de escritorio y
// tres en el cajón); si alguien cambiaba una ruta, cinco copias se quedaban
// atrás en silencio. Ahora el ítem dice cuál le toca y el panel lo pinta una vez.
export type Contador = "educacion" | "vacaciones" | "revisiones" | "mio";

export type Item = {
  href: string;
  label: string;
  Icon: LucideIcon;
  roles?: readonly string[];
  contador?: Contador;
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
    { href: "/mio", label: "Mi perfil", Icon: UserRound, contador: "mio" },
    // Con `roles` desde el 2026-09-04. Antes iba sin filtro, así que una
    // integrante con cuenta —las hay: se les invita para que acusen la política
    // salarial (Ley 30709)— aterrizaba aquí y veía un tablero de encargada que su
    // propia RLS le devuelve casi vacío. No era una fuga; era una pantalla que no
    // es suya y que se lee como que el sistema no tiene datos.
    { href: "/admin/dashboard", label: "Dashboard", Icon: LayoutDashboard, roles: SEDE },
    // Junta en una sola vista los tres contadores de abajo (educación,
    // ausencias, incidencias) — mismas RPC, mismo criterio de "por atender"
    // que cada una ya usa por su cuenta. No lleva contador propio: sería un
    // cuarto número compitiendo con los tres que ya explica, y el criterio de
    // esta casa es que un aviso que aparece en todos lados deja de ser aviso.
    { href: "/admin/bandeja", label: "Bandeja", Icon: Inbox, roles: SEDE },
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
    { href: "/admin/objetivos", label: "Objetivos", Icon: Target, roles: SEDE },
    { href: "/admin/disciplina", label: "Disciplina", Icon: Gavel, roles: SEDE },
  ] },
  { label: "Pago", items: [
    { href: "/admin/planilla", label: "Planilla", Icon: ReceiptText, roles: DO },
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
  { label: "Configuración", items: [
    { href: "/admin/areas", label: "Áreas", Icon: LayoutGrid, roles: DO },
    { href: "/admin/sedes", label: "Sedes", Icon: Building2, roles: DO },
    // Con `roles` desde el 2026-09-04, por lo mismo que «Exportar CSV»: iba sin
    // filtro, y la pantalla ya se degrada sola con `puedeGestionarCatalogos`, o
    // sea que el renglón solo llevaba a una puerta cerrada — también desde el
    // buscador (⌘K) y desde los atajos, que consumen esta misma lista.
    { href: "/admin/cuentas", label: "Cuentas", Icon: KeyRound, roles: DO },
    // El tema global (claro/oscuro) de panel Y terminal — no un color libre,
    // ver apps/web/app/(admin)/admin/apariencia/page.tsx. Mismo permiso que
    // el resto de este grupo: es un catálogo del sistema, no un dato de una
    // persona.
    { href: "/admin/apariencia", label: "Apariencia", Icon: Palette, roles: DO },
  ] },
];

// El perfil de una persona (/admin/personas/[id]) se entra desde Equipo, así que
// mientras estás en él, resaltamos "Equipo" para no dejar la ubicación huérfana.
export function esActivo(pathname: string, href: string): boolean {
  if (pathname === href) return true;
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

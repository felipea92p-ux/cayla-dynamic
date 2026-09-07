"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { useClavePorCambiar } from "@/lib/admin/use-clave-por-cambiar";
import { Marca } from "@/components/marca";
import { AcusesPendientes } from "@/components/acuses-pendientes";
import { BuscadorGlobal } from "@/components/buscador-global";
import { AtajosTeclado } from "@/components/atajos-teclado";
import { SelectorTema } from "@/components/selector-tema";
import { Insignia } from "@/components/ui/insignia";
import {
  LayoutDashboard, Inbox, TriangleAlert, PencilLine, CalendarClock, Clock, Gauge,
  Users, IdCard, TreePalm, Gavel, ReceiptText, PiggyBank, Target, LayoutGrid, KeyRound,
  Building2, FileDown, FileText, FileSignature, CalendarCheck, Coins, Scale, GraduationCap, HandCoins,
  BookText, UserRound, ScrollText, Keyboard, Megaphone, Palette,
  LogOut, Menu, Search, X, type LucideIcon,
} from "lucide-react";
import { ROLES_CON_PANEL, ROLES_DO, ROLES_EXPORTAN_ASISTENCIA, puedeOperarEquipo } from "@cayla-dynamic/shared";

// Qué renglones del menú ve cada quien. Las listas vienen de `permisos.ts` — el
// menú no vuelve a decidir quién es DO, solo lo consulta.
const DO = ROLES_DO;
const SEDE = ROLES_CON_PANEL;

export type Item = { href: string; label: string; Icon: LucideIcon; roles?: readonly string[] };

const GRUPOS: Array<{ label?: string; items: Item[] }> = [
  { items: [
    // «Lo mío» va sin `roles` y va PRIMERO: es lo único de este menú que habla de
    // quien lo está mirando. Para una integrante es su pantalla —sus días, sus
    // horas, sus tardanzas— y para DO es la suya, que también la tiene.
    { href: "/mio", label: "Lo mío", Icon: UserRound },
    // Con `roles` desde hoy. Antes iba sin filtro, así que una integrante con
    // cuenta —las hay: se les invita para que acusen la política salarial (Ley
    // 30709)— aterrizaba aquí y veía un tablero de encargada que su propia RLS
    // le devuelve casi vacío. No era una fuga; era una pantalla que no es suya y
    // que se lee como que el sistema no tiene datos.
    { href: "/admin/dashboard", label: "Dashboard", Icon: LayoutDashboard, roles: SEDE },
    // Junta en una sola vista los tres contadores de abajo (educación,
    // ausencias, incidencias) — mismas RPC, mismo criterio de "por atender"
    // que cada una ya usa por su cuenta. No lleva contador propio: sería un
    // cuarto número compitiendo con los tres que ya explica, y el criterio de
    // esta casa es que un aviso que aparece en todos lados deja de ser aviso.
    { href: "/admin/bandeja", label: "Bandeja", Icon: Inbox, roles: SEDE },
  ] },
  { label: "Asistencia", items: [
    { href: "/admin/incidencias", label: "Incidencias", Icon: TriangleAlert, roles: SEDE },
    { href: "/admin/correcciones", label: "Correcciones", Icon: PencilLine, roles: SEDE },
    { href: "/admin/turnos", label: "Turnos", Icon: CalendarClock, roles: SEDE },
    { href: "/admin/horarios", label: "Horarios", Icon: Clock, roles: SEDE },
    // La ruta sigue siendo /admin/horas —hay enlaces vivos— pero el nombre no
    // decía lo que hay ahí: el desempeño de TODO el equipo, sin entrar a nadie.
    // Con «Horas» el camino que se usaba era Equipo → persona → ficha → pestaña.
    { href: "/admin/horas", label: "Desempeño", Icon: Gauge, roles: SEDE },
  ] },
  { label: "Personas", items: [
    { href: "/admin/equipo", label: "Equipo", Icon: Users, roles: SEDE },
    { href: "/admin/datos-personales", label: "Datos personales", Icon: IdCard, roles: SEDE },
    // Decide el 21 % del salario de referencia del mes (plus de objetivos,
    // supabase/migrations/0024_planilla.sql): sigue siendo un acto de gestión
    // de equipo, no de tesorería, así que se queda acá y no en «Pago».
    { href: "/admin/objetivos", label: "Objetivos", Icon: Target, roles: SEDE },
    { href: "/admin/disciplina", label: "Disciplina", Icon: Gavel, roles: SEDE },
    { href: "/admin/documentacion", label: "Documentación", Icon: FileSignature, roles: DO },
    { href: "/admin/contratos", label: "Contratos", Icon: ScrollText, roles: DO },
  ] },
  // El único grupo con rótulo que una integrante ve en toda su vida en el
  // panel: tres documentos que le toca leer y acusar, no personas que ella
  // administre. Antes vivían dentro de «Personas» sin `roles`, y el único
  // rótulo que esa persona llegaba a leer le decía algo que no era cierto.
  { label: "Para todo el equipo", items: [
    // Sin `roles` a propósito: la Ley 30709 obliga a INFORMAR la política salarial
    // a todo el equipo, y un menú que solo ve la gerencia no informa a nadie.
    { href: "/admin/politica-salarial", label: "Política salarial", Icon: Scale },
    // Por lo mismo, y con más razón: el Reglamento Interno hay que entregarlo a
    // todo el mundo y poder probarlo. Un menú que solo ve DO no entrega nada.
    { href: "/admin/normas", label: "Normas", Icon: BookText },
    // Sin `roles`, mismo criterio que Normas: el comunicado es PARA las cuatro
    // sedes, así que el menú que lleva a leerlo no puede verlo solo DO. Sin
    // contador propio, por la misma regla de arriba: un anuncio no tiene fecha
    // límite que cueste plata pasarla.
    { href: "/admin/anuncios", label: "Anuncios", Icon: Megaphone },
  ] },
  // «Pago», no «Nómina»: es la palabra que ya usa el resto de la casa
  // (periodos_planilla, fn_planilla_calcular, docs/planilla-anexo-tecnico.md)
  // y no compite con el nombre de ningún renglón de adentro.
  { label: "Pago", items: [
    { href: "/admin/planilla", label: "Planilla", Icon: ReceiptText, roles: DO },
    { href: "/admin/provisiones", label: "Provisiones", Icon: PiggyBank, roles: DO },
    { href: "/admin/costos", label: "Costos", Icon: Coins, roles: DO },
    { href: "/admin/liquidaciones", label: "Liquidaciones", Icon: HandCoins, roles: DO },
    { href: "/admin/educacion", label: "Educación", Icon: GraduationCap, roles: DO },
    { href: "/admin/ausencias", label: "Ausencias", Icon: TreePalm, roles: SEDE },
  ] },
  // Catálogos y controles del sistema, todo DO: desaparece entero para la
  // encargada, que no crea sedes ni cuentas de otra gente.
  { label: "Configuración", items: [
    { href: "/admin/sedes", label: "Sedes", Icon: Building2, roles: DO },
    { href: "/admin/areas", label: "Áreas", Icon: LayoutGrid, roles: DO },
    { href: "/admin/feriados", label: "Feriados", Icon: CalendarCheck, roles: DO },
    // Con `roles` desde hoy, por lo mismo que «Exportar CSV» de abajo: iba sin
    // filtro, y la pantalla ya se degrada sola con `puedeGestionarCatalogos`, o
    // sea que el renglón solo llevaba a una puerta cerrada — también desde el
    // buscador (Cmd+K) y desde los atajos, que consumen esta misma lista.
    { href: "/admin/cuentas", label: "Cuentas", Icon: KeyRound, roles: DO },
    // El tema global (claro/oscuro) de panel Y terminal — no un color libre,
    // ver apps/web/app/(admin)/admin/apariencia/page.tsx. Mismo permiso que
    // el resto de este grupo: es un catálogo del sistema, no un dato de una
    // persona.
    { href: "/admin/apariencia", label: "Apariencia", Icon: Palette, roles: DO },
  ] },
  // Lo que le queda a «Gestión» después de sacarle los catálogos: un informe de
  // uso diario y una descarga, las dos cosas que sí ve la encargada de sede.
  { label: "Informes", items: [
    { href: "/admin/reporte-sede", label: "Hoja de sede", Icon: FileText, roles: SEDE },
    // Con `roles` desde hoy (hallazgo 26). Iba sin filtro, así que una integrante
    // con cuenta —las hay, para acusar la política salarial— veía «Exportar CSV»
    // y entraba. No era una fuga: la RLS de `jornadas`, `marcajes` y
    // `correcciones_auditoria` solo le devuelve lo suyo. Era una pantalla que no
    // es suya y que se lee como que el sistema no tiene datos, igual que pasaba
    // con el Dashboard. La lista es la de `puedeExportarAsistencia`, que es quien
    // decide de verdad dentro de la pantalla; hoy coincide con `SEDE`, pero se
    // nombra aparte para que estrechar el permiso apague también el renglón.
    { href: "/admin/exportar", label: "Exportar CSV", Icon: FileDown, roles: ROLES_EXPORTAN_ASISTENCIA },
  ] },
];

// Una regla, no una lista de excepciones: cualquier ruta hija (boleta, memo
// disciplinario, constancias de normas o de política salarial…) resalta el
// renglón del que cuelga, igual que la ruta exacta.
function esActivo(pathname: string, href: string): boolean {
  if (pathname === href || pathname.startsWith(`${href}/`)) return true;
  // El perfil de una persona (/admin/personas/[id]) se entra desde Equipo: es
  // una redirección conceptual, no una ruta hija de /admin/equipo, así que no
  // la cubre la regla de arriba y necesita su propio caso.
  if (href === "/admin/equipo" && pathname.startsWith("/admin/personas")) return true;
  return false;
}

export function AdminNav() {
  const pathname = usePathname();
  const router = useRouter();
  // Antes que cualquier otra cosa: si esta cuenta entró con una clave que le
  // dictaron o con una que ya no cumple la política, de acá no se pasa. Va en la
  // barra porque es lo único que dibujan las 24 pantallas del panel — el layout
  // del grupo `(admin)` corre en el servidor y no ve la sesión.
  useClavePorCambiar();
  const persona = usePersonaActual();
  const rol = persona?.rol ?? null;
  const [abierto, setAbierto] = useState(false);
  // TRES contadores, y ninguno más. El comentario original decía «el único, y a
  // propósito: un aviso que aparece en todos lados deja de ser un aviso». Esa
  // regla sigue en pie; lo que pasó es que aparecieron dos cosas más que cumplen
  // la MISMA vara, y la vara es exigente: algo que, si nadie lo mira a tiempo,
  // cuesta plata y después ya no tiene arreglo.
  //
  //   Educación   · asignaciones sin comprobante o por vencer: un pago sin
  //                 sustento, o alguien que deja de cobrar.
  //   Ausencias   · récords de vacaciones que vencen dentro de 60 días: pasado
  //                 el plazo, el art. 23 del D. Leg. 713 manda una remuneración
  //                 entera de indemnización y ese día ya no tiene arreglo.
  //   Incidencias · revisiones pedidas (0257). La ÚNICA lista del panel que no
  //                 la generó el sistema mirando datos, sino una persona que
  //                 estuvo ahí ese día y dice que su marcaje está mal. Si el
  //                 periodo cierra con el reclamo sin leer, ya es plata mal
  //                 pagada y hay que reabrir el mes para arreglarlo.
  //
  // Antes de agregar un cuarto: la pregunta no es «¿es importante?», es «¿tiene
  // fecha límite y cuesta plata pasarla?». Casi nada la pasa.
  const [educacionPorAtender, setEducacionPorAtender] = useState(0);
  const [vacacionesPorAtender, setVacacionesPorAtender] = useState(0);
  const [revisionesPendientes, setRevisionesPendientes] = useState(0);
  const [buscadorAbierto, setBuscadorAbierto] = useState(false);
  const [ayudaAbierta, setAyudaAbierta] = useState(false);

  useEffect(() => { setAbierto(false); }, [pathname]);

  // Escape cierra el menú del teléfono, igual que ya cierra el buscador y los
  // atajos: los tres desplegables de esta barra tienen que responder al mismo
  // gesto. Tocar fuera lo cierra la capa de fondo que se dibuja más abajo.
  useEffect(() => {
    if (!abierto) return;
    function alPresionar(e: KeyboardEvent) {
      if (e.key === "Escape") setAbierto(false);
    }
    window.addEventListener("keydown", alPresionar);
    return () => window.removeEventListener("keydown", alPresionar);
  }, [abierto]);

  // ⌘K / Ctrl+K abre el buscador desde cualquier pantalla del panel, escribiendo
  // o no. No se guarda "cerrado antes" en ningún lado: cada apertura arranca
  // igual, como Equipo arranca su propio filtro en blanco cada vez.
  useEffect(() => {
    function alPresionar(e: KeyboardEvent) {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setBuscadorAbierto(true);
      }
    }
    window.addEventListener("keydown", alPresionar);
    return () => window.removeEventListener("keydown", alPresionar);
  }, []);

  useEffect(() => {
    if (!ROLES_DO.includes(rol ?? "")) { setEducacionPorAtender(0); return; }
    let vivo = true;
    void createAdminSupabaseClient()
      .rpc("fn_educacion_por_atender")
      .then(({ data }) => { if (vivo) setEducacionPorAtender(Number(data) || 0); });
    return () => { vivo = false; };
  }, [rol, pathname]);

  // La de vacaciones la ve también la encargada: es quien arma el calendario de
  // su tienda. La función ya devuelve solo lo que a cada rol le toca, así que
  // acá no se vuelve a decidir quién ve qué.
  useEffect(() => {
    if (!puedeOperarEquipo(rol)) { setVacacionesPorAtender(0); return; }
    let vivo = true;
    void createAdminSupabaseClient()
      .rpc("fn_vacaciones_por_atender")
      .then(({ data }) => { if (vivo) setVacacionesPorAtender(Number(data) || 0); });
    return () => { vivo = false; };
  }, [rol, pathname]);

  // Las revisiones pedidas las ve quien puede atenderlas: encargada de sede y
  // DO, o sea los mismos roles que ven Incidencias. No lleva función de conteo
  // propia porque `fn_revisiones_pedidas(true)` YA devuelve solo las pendientes
  // — el contador es su largo. Una función aparte sería una segunda definición
  // de «pendiente» que podría separarse de la primera.
  useEffect(() => {
    // Mismo predicado que la de vacaciones: ROLES_CON_PANEL y puedeOperarEquipo
    // son el mismo conjunto (DO_Y_ENCARGADA, permisos.ts:89,132). Se pregunta por
    // la función y no por la lista, que es lo que manda la primera regla de
    // packages/shared — y de paso se evita el cast.
    if (!puedeOperarEquipo(rol)) { setRevisionesPendientes(0); return; }
    let vivo = true;
    void createAdminSupabaseClient()
      .rpc("fn_revisiones_pedidas", { p_solo_pendientes: true })
      .then(({ data }) => {
        if (vivo) setRevisionesPendientes(Array.isArray(data) ? data.length : 0);
      });
    return () => { vivo = false; };
  }, [rol, pathname]);

  async function cerrarSesion() {
    const supabase = createAdminSupabaseClient();
    await supabase.auth.signOut();
    router.replace("/admin/login");
  }

  const visible = (it: Item) => !it.roles || (rol !== null && it.roles.includes(rol));
  const grupos = GRUPOS
    .map((g) => ({ ...g, items: g.items.filter(visible) }))
    .filter((g) => g.items.length > 0);

  return (
    <header className="border-b border-sand">
      <div className="flex items-start justify-between gap-4 px-4 py-3 sm:px-6">
        <div className="flex min-w-0 flex-1 items-start gap-6 xl:gap-8">
          <Marca tono="tinta" isotipo="rojo" />
          {/* Barra horizontal — desktop. Envuelve en tantas líneas como haga
              falta (nunca esconde ítems con scroll), y el bloque de acciones de
              la derecha va con `items-start` en el contenedor: por defecto un
              flex-row estira a sus hijos a la misma altura, así que con
              `items-center` el bloque de acciones (nombre, cerrar sesión,
              buscar) quedaba centrado a media altura del nav ya envuelto y se
              montaba sobre las filas del medio. Con `items-start` cada bloque
              usa solo su propia altura: el nav crece hacia abajo cuantas filas
              necesite y las acciones se quedan arriba, sin pisarse. */}
          <nav aria-label="Menú principal" className="hidden min-w-0 flex-wrap items-center gap-x-2 gap-y-1.5 text-sm xl:flex">
            {grupos.map((g, gi) => {
              const idRotulo = `nav-grupo-${gi}`;
              return (
                <div key={gi} role={g.label ? "group" : undefined} aria-labelledby={g.label ? idRotulo : undefined}
                  className="flex shrink-0 flex-wrap items-center gap-x-0.5">
                  {gi > 0 && <span aria-hidden className="mx-1.5 h-3.5 w-px shrink-0 bg-sand" />}
                  {g.label && (
                    <span id={idRotulo} className="etiqueta shrink-0 pr-1 text-taupe">{g.label}</span>
                  )}
                  {g.items.map((it) => (
                    <Link key={it.href} href={it.href}
                      className={`flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded-md px-2 py-1 transition active:scale-[0.97] ${
                        esActivo(pathname, it.href) ? "bg-sand/60 font-medium text-tinta" : "text-taupe hover:bg-sand/40 hover:text-rojo active:bg-sand/60 active:text-rojo-profundo"}`}>
                      <it.Icon size={15} strokeWidth={1.8} aria-hidden />
                      {it.label}
                      {it.href === "/admin/educacion" && educacionPorAtender > 0 && (
                        <span title={`${educacionPorAtender} asignación(es) sin comprobante o por vencer`}>
                          <Insignia variante="contador" tamano="sm" className="ml-0.5">{educacionPorAtender}</Insignia>
                        </span>
                      )}
                      {it.href === "/admin/ausencias" && vacacionesPorAtender > 0 && (
                        <span title={`${vacacionesPorAtender} récord(s) de vacaciones que vencen dentro de 60 días`}>
                          <Insignia variante="contador" tamano="sm" className="ml-0.5">{vacacionesPorAtender}</Insignia>
                        </span>
                      )}
                      {it.href === "/admin/incidencias" && revisionesPendientes > 0 && (
                        <span title={`${revisionesPendientes} persona(s) pidieron que se revise un día suyo`}>
                          <Insignia variante="contador" tamano="sm" className="ml-0.5">{revisionesPendientes}</Insignia>
                        </span>
                      )}
                    </Link>
                  ))}
                </div>
              );
            })}
          </nav>
        </div>

        <div className="flex shrink-0 items-center gap-3">
          {persona && (
            <span className="hidden text-sm text-taupe xl:inline" title="Sesión activa">
              {persona.nombreCompleto}
            </span>
          )}
          <button onClick={cerrarSesion}
            className="hidden items-center gap-1.5 text-sm text-taupe transition hover:text-rojo active:scale-[0.97] active:text-rojo-profundo xl:flex">
            <LogOut size={15} strokeWidth={1.8} aria-hidden /> Cerrar sesión
          </button>
          <button onClick={() => setBuscadorAbierto(true)} aria-label="Buscar"
            className="flex items-center gap-1.5 rounded-md border border-sand px-2.5 py-1.5 text-sm text-taupe transition hover:border-taupe/40 hover:bg-sand/30 hover:text-rojo active:scale-[0.97] active:text-rojo-profundo">
            <Search size={15} strokeWidth={1.8} aria-hidden />
            <span className="hidden xl:inline">Buscar</span>
            <kbd className="hidden rounded border border-sand bg-sand/50 px-1 font-sans text-[10px] text-taupe xl:inline">⌘K</kbd>
          </button>
          <button onClick={() => setAyudaAbierta(true)} aria-label="Atajos de teclado" title="Atajos de teclado (?)"
            className="hidden rounded-md border border-sand p-1.5 text-taupe transition hover:border-taupe/40 hover:bg-sand/30 hover:text-rojo active:scale-[0.97] active:text-rojo-profundo xl:flex">
            <Keyboard size={15} strokeWidth={1.8} aria-hidden />
          </button>
          <SelectorTema />
          <button onClick={() => setAbierto((a) => !a)}
            aria-label={abierto ? "Cerrar menú" : "Abrir menú"} aria-expanded={abierto}
            className="rounded-lg border border-sand p-2 text-tinta transition hover:border-taupe/40 hover:bg-sand/40 active:scale-[0.97] active:bg-sand/60 xl:hidden">
            {abierto ? <X size={20} strokeWidth={1.8} /> : <Menu size={20} strokeWidth={1.8} />}
          </button>
        </div>
      </div>

      {/* Menú desplegable móvil — vertical, con títulos de grupo e íconos.
          La capa de fondo cierra al tocar fuera (mismo patrón que
          buscador-global.tsx); el <nav> queda `relative` con fondo propio
          para dibujarse POR ENCIMA de esa capa en vez de por debajo, que es
          donde cae por defecto un elemento sin posicionar frente a uno fijo.
          `max-h-[70vh] overflow-y-auto` evita que una encargada (18
          renglones) o un admin (27) tengan que desplazarse por todo el menú
          para volver a alcanzar el botón X, que vive arriba, fuera de este
          bloque. */}
      {abierto && (
        <>
          <div onClick={() => setAbierto(false)} aria-hidden className="fixed inset-0 z-40 bg-black/40 xl:hidden" />
          <nav aria-label="Menú principal, móvil"
            className="relative z-50 max-h-[70vh] overflow-y-auto border-t border-sand bg-crema px-4 pb-4 pt-1 sm:px-6 xl:hidden">
            {grupos.map((g, gi) => {
              const idRotulo = `nav-grupo-movil-${gi}`;
              return (
                <div key={gi} role={g.label ? "group" : undefined} aria-labelledby={g.label ? idRotulo : undefined}>
                  {g.label && (
                    <p id={idRotulo} className="etiqueta px-3 pb-1 pt-3 text-taupe">{g.label}</p>
                  )}
                  <div className="grid gap-0.5">
                    {g.items.map((it) => (
                      <Link key={it.href} href={it.href}
                        className={`flex items-center gap-2.5 rounded-lg px-3 py-2.5 text-sm transition active:scale-[0.97] ${
                          esActivo(pathname, it.href)
                            ? "bg-sand/60 font-medium text-tinta"
                            : "text-taupe hover:bg-sand/40 hover:text-rojo active:bg-sand/60 active:text-rojo-profundo"}`}>
                        <it.Icon size={17} strokeWidth={1.8} aria-hidden />
                        {it.label}
                        {it.href === "/admin/educacion" && educacionPorAtender > 0 && (
                          <Insignia variante="contador" tamano="sm" className="ml-auto">{educacionPorAtender}</Insignia>
                        )}
                        {it.href === "/admin/ausencias" && vacacionesPorAtender > 0 && (
                          <Insignia variante="contador" tamano="sm" className="ml-auto">{vacacionesPorAtender}</Insignia>
                        )}
                        {it.href === "/admin/incidencias" && revisionesPendientes > 0 && (
                          <Insignia variante="contador" tamano="sm" className="ml-auto">{revisionesPendientes}</Insignia>
                        )}
                      </Link>
                    ))}
                  </div>
                </div>
              );
            })}
            {persona && (
              <p className="mt-3 px-3 text-xs text-taupe" title="Sesión activa">
                Sesión: {persona.nombreCompleto}
              </p>
            )}
            <button onClick={cerrarSesion}
              className="mt-2 flex w-full items-center gap-2.5 rounded-lg border border-sand px-3 py-2.5 text-left text-sm text-taupe transition hover:border-rojo/30 hover:text-rojo active:scale-[0.97] active:text-rojo-profundo">
              <LogOut size={17} strokeWidth={1.8} aria-hidden /> Cerrar sesión
            </button>
          </nav>
        </>
      )}
      {/* Va aquí y no en el layout porque el layout envuelve también el login y
          «nueva clave», donde todavía no hay sesión a la que preguntarle nada.
          Este menú, en cambio, solo lo pinta una pantalla real del panel. */}
      <AcusesPendientes />
      <BuscadorGlobal grupos={grupos} abierto={buscadorAbierto} onCerrar={() => setBuscadorAbierto(false)} />
      <AtajosTeclado grupos={grupos} abierto={ayudaAbierta} setAbierto={setAyudaAbierta} />
    </header>
  );
}

"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { Marca } from "@/components/marca";
import { AcusesPendientes } from "@/components/acuses-pendientes";
import { BuscadorGlobal } from "@/components/buscador-global";
import {
  LayoutDashboard, TriangleAlert, PencilLine, CalendarClock, Clock, Gauge,
  Users, IdCard, TreePalm, Gavel, ReceiptText, PiggyBank, Target, LayoutGrid, KeyRound,
  Building2, FileDown, FileText, FileSignature, CalendarCheck, Coins, Scale, GraduationCap, HandCoins,
  BookText, UserRound, ScrollText,
  LogOut, Menu, Search, X, type LucideIcon,
} from "lucide-react";
import { ROLES_CON_PANEL, ROLES_DO, puedeOperarEquipo } from "@cayla-dynamic/shared";

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
    { href: "/admin/objetivos", label: "Objetivos", Icon: Target, roles: SEDE },
    { href: "/admin/disciplina", label: "Disciplina", Icon: Gavel, roles: SEDE },
    { href: "/admin/documentacion", label: "Documentación", Icon: FileSignature, roles: DO },
    { href: "/admin/contratos", label: "Contratos", Icon: ScrollText, roles: DO },
    // Sin `roles` a propósito: la Ley 30709 obliga a INFORMAR la política salarial
    // a todo el equipo, y un menú que solo ve la gerencia no informa a nadie.
    { href: "/admin/politica-salarial", label: "Política salarial", Icon: Scale },
    // Por lo mismo, y con más razón: el Reglamento Interno hay que entregarlo a
    // todo el mundo y poder probarlo. Un menú que solo ve DO no entrega nada.
    { href: "/admin/normas", label: "Normas", Icon: BookText },
  ] },
  { label: "Nómina", items: [
    { href: "/admin/planilla", label: "Planilla", Icon: ReceiptText, roles: DO },
    { href: "/admin/provisiones", label: "Provisiones", Icon: PiggyBank, roles: DO },
    { href: "/admin/costos", label: "Costos", Icon: Coins, roles: DO },
    { href: "/admin/liquidaciones", label: "Liquidaciones", Icon: HandCoins, roles: DO },
    { href: "/admin/educacion", label: "Educación", Icon: GraduationCap, roles: DO },
    { href: "/admin/ausencias", label: "Ausencias", Icon: TreePalm, roles: SEDE },
    { href: "/admin/feriados", label: "Feriados", Icon: CalendarCheck, roles: DO },
  ] },
  { label: "Gestión", items: [
    { href: "/admin/areas", label: "Áreas", Icon: LayoutGrid, roles: DO },
    { href: "/admin/sedes", label: "Sedes", Icon: Building2, roles: DO },
    { href: "/admin/reporte-sede", label: "Hoja de sede", Icon: FileText, roles: SEDE },
    { href: "/admin/cuentas", label: "Cuentas", Icon: KeyRound },
    { href: "/admin/exportar", label: "Exportar CSV", Icon: FileDown },
  ] },
];

// El perfil de una persona (/admin/personas/[id]) se entra desde Equipo, así que
// mientras estás en él, resaltamos "Equipo" para no dejar la ubicación huérfana.
function esActivo(pathname: string, href: string): boolean {
  if (pathname === href) return true;
  if (href === "/admin/equipo" && pathname.startsWith("/admin/personas")) return true;
  // Vacaciones se absorbió en Ausencias (0101); el enlace viejo sigue llevando allí.
  if (href === "/admin/ausencias" && pathname === "/admin/vacaciones") return true;
  return false;
}

export function AdminNav() {
  const pathname = usePathname();
  const router = useRouter();
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

  useEffect(() => { setAbierto(false); }, [pathname]);

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
      <div className="flex items-center justify-between px-4 py-3 sm:px-6">
        <div className="flex min-w-0 items-center gap-6 xl:gap-8">
          <Marca tono="tinta" isotipo="rojo" />
          {/* Barra horizontal — desktop. Grupos separados por un divisor sutil. */}
          <nav className="hidden flex-wrap items-center gap-x-2 gap-y-1 text-sm xl:flex">
            {grupos.map((g, gi) => (
              <div key={gi} className="flex items-center gap-x-0.5">
                {gi > 0 && <span aria-hidden className="mx-1.5 h-3.5 w-px bg-sand" />}
                {g.items.map((it) => (
                  <Link key={it.href} href={it.href}
                    className={`flex items-center gap-1.5 rounded-md px-2 py-1 transition active:scale-[0.97] ${
                      esActivo(pathname, it.href) ? "bg-sand/60 font-medium text-tinta" : "text-taupe hover:bg-sand/40 hover:text-rojo active:bg-sand/60 active:text-rojo-profundo"}`}>
                    <it.Icon size={15} strokeWidth={1.8} aria-hidden />
                    {it.label}
                    {it.href === "/admin/educacion" && educacionPorAtender > 0 && (
                      <span
                        className="ml-0.5 rounded-full bg-rojo px-1.5 text-[10px] font-medium leading-4 text-crema"
                        title={`${educacionPorAtender} asignación(es) sin comprobante o por vencer`}
                      >
                        {educacionPorAtender}
                      </span>
                    )}
                    {it.href === "/admin/ausencias" && vacacionesPorAtender > 0 && (
                      <span
                        className="ml-0.5 rounded-full bg-rojo px-1.5 text-[10px] font-medium leading-4 text-crema"
                        title={`${vacacionesPorAtender} récord(s) de vacaciones que vencen dentro de 60 días`}
                      >
                        {vacacionesPorAtender}
                      </span>
                    )}
                    {it.href === "/admin/incidencias" && revisionesPendientes > 0 && (
                      <span
                        className="ml-0.5 rounded-full bg-rojo px-1.5 text-[10px] font-medium leading-4 text-crema"
                        title={`${revisionesPendientes} persona(s) pidieron que se revise un día suyo`}
                      >
                        {revisionesPendientes}
                      </span>
                    )}
                  </Link>
                ))}
              </div>
            ))}
          </nav>
        </div>

        <div className="flex items-center gap-3">
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
          <button onClick={() => setAbierto((a) => !a)}
            aria-label={abierto ? "Cerrar menú" : "Abrir menú"} aria-expanded={abierto}
            className="rounded-lg border border-sand p-2 text-tinta transition hover:border-taupe/40 hover:bg-sand/40 active:scale-[0.97] active:bg-sand/60 xl:hidden">
            {abierto ? <X size={20} strokeWidth={1.8} /> : <Menu size={20} strokeWidth={1.8} />}
          </button>
        </div>
      </div>

      {/* Menú desplegable móvil — vertical, con títulos de grupo e íconos. */}
      {abierto && (
        <nav className="border-t border-sand px-4 pb-4 pt-1 sm:px-6 xl:hidden">
          {grupos.map((g, gi) => (
            <div key={gi}>
              {g.label && (
                <p className="px-3 pb-1 pt-3 text-[11px] uppercase tracking-wider text-taupe">{g.label}</p>
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
                      <span className="ml-auto rounded-full bg-rojo px-2 text-xs font-medium leading-5 text-crema">
                        {educacionPorAtender}
                      </span>
                    )}
                    {it.href === "/admin/ausencias" && vacacionesPorAtender > 0 && (
                      <span className="ml-auto rounded-full bg-rojo px-2 text-xs font-medium leading-5 text-crema">
                        {vacacionesPorAtender}
                      </span>
                    )}
                    {it.href === "/admin/incidencias" && revisionesPendientes > 0 && (
                      <span className="ml-auto rounded-full bg-rojo px-2 text-xs font-medium leading-5 text-crema">
                        {revisionesPendientes}
                      </span>
                    )}
                  </Link>
                ))}
              </div>
            </div>
          ))}
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
      )}
      {/* Va aquí y no en el layout porque el layout envuelve también el login y
          «nueva clave», donde todavía no hay sesión a la que preguntarle nada.
          Este menú, en cambio, solo lo pinta una pantalla real del panel. */}
      <AcusesPendientes />
      <BuscadorGlobal grupos={grupos} abierto={buscadorAbierto} onCerrar={() => setBuscadorAbierto(false)} />
    </header>
  );
}

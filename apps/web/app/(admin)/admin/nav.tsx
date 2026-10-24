"use client";

// El marco del panel: sidebar a la izquierda, barra superior arriba, y la
// pantalla adentro.
//
// Hasta el 2026-09-07 esto era una BARRA HORIZONTAL que cada una de las ~30
// pantallas renderizaba a mano (`<AdminNav/>`, a veces dos y tres veces por
// archivo, una por cada rama de retorno temprano). Con treinta renglones, esa
// barra envolvía en tres o cuatro filas y se comía ~145px de alto en todas las
// pantallas; por debajo de 1280px desaparecía entera dentro de una hamburguesa,
// que es un ancho de portátil normal. Ya se había intentado arreglar con scroll
// horizontal (688e8e5) y se revirtió el mismo día (21591a7) porque escondía
// ítems.
//
// Ahora vive UNA vez, en `(admin)/layout.tsx`. Eso es lo que permite que el
// sidebar no se remonte al navegar — si se remontara perdería el plegado y
// volvería a leer localStorage, o sea un parpadeo por pantalla. Y es también
// por lo que existe `RUTAS_SIN_MARCO`: ese layout envuelve también al login y a
// «nueva clave», donde todavía no hay sesión a la que preguntarle nada.
//
// Lo que NO cambió: los contadores siguen consultándose igual, con las mismas
// RPC y las mismas dependencias `[rol, pathname]` — refrescarse en cada
// navegación es su único mecanismo de actualización, y un contador de
// Incidencias en frío es un reclamo sin leer con el periodo cerrándose.

import { useEffect, useRef, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { useClavePorCambiar } from "@/lib/admin/use-clave-por-cambiar";
import { traerBandeja } from "@/lib/bandeja-mia";
import { contarBandejaEquipoPendiente } from "@/lib/admin/bandeja-equipo";
import { EVENTO_CAMBIO_BANDEJA } from "@/lib/admin/bandeja-urgencia";
import { useGruposCerrados, useNavColapsado } from "@/lib/use-nav-colapsado";
import { Marca } from "@/components/marca";
import { AcusesPendientes } from "@/components/acuses-pendientes";
import { BuscadorGlobal } from "@/components/buscador-global";
import { AtajosTeclado } from "@/components/atajos-teclado";
import { ColibriViajero } from "@/components/colibri-viajero";
import { SelectorTema } from "@/components/selector-tema";
import { SaludoHora } from "@/components/nav/saludo-hora";
import { SidebarAdmin } from "@/components/nav/sidebar-admin";
import { CajonAdmin } from "@/components/nav/cajon-admin";
import type { Contadores } from "@/components/nav/panel-navegacion";
import { GRUPOS, RUTAS_SIN_MARCO, type Item } from "./nav-items";
import { GuardaCuentaDeServicio } from "@/lib/cuenta-de-servicio";
import { ROLES_DO, puedeOperarEquipo } from "@cayla-dynamic/shared";
import { Keyboard, LogOut, Menu, Search } from "lucide-react";

/**
 * El marco del panel. Lo monta `(admin)/layout.tsx` una sola vez.
 *
 * Se parte en dos porque los ganchos no pueden ser condicionales: en las rutas
 * sin sesión no queremos que corra el guardia de clave ni las tres consultas de
 * contadores, y la única forma limpia de no correrlos es no montar el
 * componente que los tiene.
 */
export function MarcoAdmin({ children }: { children: React.ReactNode }) {
  const pathname = usePathname() ?? "";
  if (RUTAS_SIN_MARCO.includes(pathname)) return <>{children}</>;
  // Una estación de retail con sesión abierta no pasa del marco (0490).
  return (
    <GuardaCuentaDeServicio>
      <MarcoConChrome pathname={pathname}>{children}</MarcoConChrome>
    </GuardaCuentaDeServicio>
  );
}

function MarcoConChrome({ pathname, children }: { pathname: string; children: React.ReactNode }) {
  const router = useRouter();
  // Antes que cualquier otra cosa: si esta cuenta entró con una clave que le
  // dictaron o con una que ya no cumple la política, de acá no se pasa.
  useClavePorCambiar();
  const persona = usePersonaActual();
  const rol = persona?.rol ?? null;

  // «Casos» no lo decide el rol: la Gerencia General es una marca (0483). Se
  // pregunta a la base una vez por persona. Mientras no contesta, el ítem no
  // se pinta: aparecer y desaparecer sería peor que llegar un instante tarde.
  const [veCasos, setVeCasos] = useState(false);
  useEffect(() => {
    if (!persona?.id) return;
    let vivo = true;
    createAdminSupabaseClient().rpc("fn_ve_casos").then(
      ({ data }) => { if (vivo) setVeCasos(data === true); },
      () => {},
    );
    return () => { vivo = false; };
  }, [persona?.id]);

  const { modo, expandido, alternar } = useNavColapsado();
  const { cerrados, alternarGrupo } = useGruposCerrados();
  const [cajonAbierto, setCajonAbierto] = useState(false);
  const hamburguesa = useRef<HTMLButtonElement>(null);

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
  // Antes de agregar un cuarto DE EQUIPO: la pregunta no es «¿es importante?»,
  // es «¿tiene fecha límite y cuesta plata pasarla?». Casi nada la pasa.
  //
  // El de «Info» (2026-09-08) no compite con estos tres y por eso entra:
  // los tres de arriba hablan del EQUIPO —lo que a esta persona le toca
  // atender— y aquel habla de ELLA: su contrato sin firmar, su constancia de
  // ley pendiente. Quien pasa el día en el panel no tenía forma de enterarse.
  //
  // El de «Bandeja» (2026-09-12) tampoco compite con estos tres, por una razón
  // distinta a la de «Info»: no es un CUARTO criterio, es la UNIÓN de todos.
  // `/admin/bandeja` junta hoy nueve secciones (ver lib/admin/bandeja-equipo.ts)
  // y solo tres —las de arriba— tenían aviso en algún renglón del menú. Las
  // otras seis (sin horario vigente, revisión de ruta, revisión de contrato,
  // solicitudes de vacaciones, solicitudes de cambio de perfil, salud del
  // despacho de avisos) no encendían nada en ningún lado: pasaban la MISMA
  // vara de arriba —cuestan plata o un plazo legal si nadie las mira a
  // tiempo— y aun así eran invisibles fuera de esa pantalla. El bolito de
  // Bandeja es la única señal de esas seis; que también sume las tres de
  // arriba no es una copia, es que la Bandeja de verdad las contiene.
  const [educacionPorAtender, setEducacionPorAtender] = useState(0);
  const [vacacionesPorAtender, setVacacionesPorAtender] = useState(0);
  const [revisionesPendientes, setRevisionesPendientes] = useState(0);
  const [misAvisos, setMisAvisos] = useState(0);
  const [bandejaPendiente, setBandejaPendiente] = useState(0);
  const [buscadorAbierto, setBuscadorAbierto] = useState(false);
  const [ayudaAbierta, setAyudaAbierta] = useState(false);
  // Resolver algo DENTRO de la Bandeja no cambia el pathname, así que los dos
  // contadores que dependen de lo que ahí se resuelve (Bandeja e Incidencias)
  // se quedaban con el número viejo hasta navegar. La Bandeja avisa con un
  // evento y esto solo vuelve a disparar las MISMAS consultas — no cambia qué
  // se cuenta.
  const [cambiosEnBandeja, setCambiosEnBandeja] = useState(0);
  useEffect(() => {
    const alCambiar = () => setCambiosEnBandeja((n) => n + 1);
    window.addEventListener(EVENTO_CAMBIO_BANDEJA, alCambiar);
    return () => window.removeEventListener(EVENTO_CAMBIO_BANDEJA, alCambiar);
  }, []);

  // Al navegar, el cajón se cierra. Se ajusta durante el render y no en un
  // efecto —el patrón que React documenta para esto y que `buscador-global.tsx`
  // ya usa con `abiertoAntes`— porque acá no hay nada que sincronizar con el
  // exterior: solo un valor que depende de si el pathname acaba de cambiar.
  // Tocar un renglón ya lo cierra por su cuenta (`onNavegar`); esto cubre lo
  // demás, como volver con el botón atrás del navegador.
  const [pathnameAnterior, setPathnameAnterior] = useState(pathname);
  if (pathname !== pathnameAnterior) {
    setPathnameAnterior(pathname);
    setCajonAbierto(false);
  }

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

  // Quién tiene derecho a cada contador. Se calcula acá arriba, una vez, y no
  // dentro de cada efecto poniendo el número en cero: reponer el cero era un
  // `setState` síncrono dentro del efecto (tres veces), y además dejaba pasar
  // un fotograma con el número viejo de la sesión anterior antes de borrarlo.
  // Derivado, el número simplemente no existe para quien no lo puede ver.
  const veEducacion = ROLES_DO.includes(rol ?? "");
  // La de vacaciones la ve también la encargada: es quien arma el calendario de
  // su tienda. La función ya devuelve solo lo que a cada rol le toca, así que
  // acá no se vuelve a decidir quién ve qué.
  const veEquipo = puedeOperarEquipo(rol);

  useEffect(() => {
    if (!veEducacion) return;
    let vivo = true;
    void createAdminSupabaseClient()
      .rpc("fn_educacion_por_atender")
      .then(({ data }) => { if (vivo) setEducacionPorAtender(Number(data) || 0); });
    return () => { vivo = false; };
  }, [veEducacion, pathname]);

  useEffect(() => {
    if (!veEquipo) return;
    let vivo = true;
    void createAdminSupabaseClient()
      .rpc("fn_vacaciones_por_atender")
      .then(({ data }) => { if (vivo) setVacacionesPorAtender(Number(data) || 0); });
    return () => { vivo = false; };
  }, [veEquipo, pathname]);

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
    if (!veEquipo) return;
    let vivo = true;
    void createAdminSupabaseClient()
      .rpc("fn_revisiones_pedidas", { p_solo_pendientes: true })
      .then(({ data }) => {
        if (vivo) setRevisionesPendientes(Array.isArray(data) ? data.length : 0);
      });
    return () => { vivo = false; };
  }, [veEquipo, pathname, cambiosEnBandeja]);

  // El total de la Bandeja del equipo (ver lib/admin/bandeja-equipo.ts): la
  // unión de las nueve secciones que esa pantalla junta, no solo las tres de
  // arriba. Se gatea con `veEquipo` porque es la misma condición con la que el
  // propio ítem «Bandeja» decide si se pinta (`roles: SEDE` en nav-items.ts);
  // dentro de la función cada sección vuelve a preguntar su propio permiso,
  // así que una encargada sin acceso a Educación no la cuenta dos veces.
  useEffect(() => {
    if (!veEquipo) return;
    let vivo = true;
    void contarBandejaEquipoPendiente(createAdminSupabaseClient(), rol)
      .then((n) => { if (vivo) setBandejaPendiente(n); });
    return () => { vivo = false; };
  }, [veEquipo, rol, pathname, cambiosEnBandeja]);

  // Lo suyo. Sale de `traerBandeja`, la MISMA función que pinta el número del
  // botón «Bandeja» de /mio: el menú del panel y esa pantalla no pueden decir
  // dos números distintos de lo mismo.
  //
  // Sin `roles`, como el propio ítem «Info»: todo el mundo tiene un
  // contrato y una constancia que dejar, incluida DO. Y falla en silencio —si
  // no se pudo contar, el renglón sale sin número—, igual que en /mio.
  useEffect(() => {
    const id = persona?.id;
    if (!id) return;
    let vivo = true;
    void traerBandeja(createAdminSupabaseClient(), id)
      .then(({ bandeja }) => { if (vivo) setMisAvisos(bandeja.avisos); });
    return () => { vivo = false; };
  }, [persona?.id, pathname]);

  async function cerrarSesion() {
    const supabase = createAdminSupabaseClient();
    await supabase.auth.signOut();
    router.replace("/admin/login");
  }

  const visible = (it: Item) =>
    (!it.roles || (rol !== null && it.roles.includes(rol)))
    && (it.requiere !== "casos" || veCasos);
  const grupos = GRUPOS
    .map((g) => ({ ...g, items: g.items.filter(visible) }))
    .filter((g) => g.items.length > 0);

  // Los textos son los mismos `title` que llevaban los badges de la barra vieja.
  // El `? … : 0` es lo que reemplaza al viejo «reponer el cero» de cada efecto:
  // quien no tiene el permiso no ve el número, aunque lo tuviera en memoria de
  // una sesión anterior en esta misma pestaña.
  const educacion = veEducacion ? educacionPorAtender : 0;
  const vacaciones = veEquipo ? vacacionesPorAtender : 0;
  const revisiones = veEquipo ? revisionesPendientes : 0;
  const bandeja = veEquipo ? bandejaPendiente : 0;

  const contadores: Contadores = {
    educacion: {
      n: educacion,
      titulo: `${educacion} en Educación: constancias por revisar o vencidas, estudios sin calendario y avisos de fin`,
    },
    vacaciones: {
      n: vacaciones,
      titulo: `${vacaciones} récord(s) de vacaciones que vencen dentro de 60 días`,
    },
    revisiones: {
      n: revisiones,
      titulo: `${revisiones} persona(s) pidieron que se revise un día suyo`,
    },
    bandeja: {
      n: bandeja,
      titulo: `${bandeja} cosa(s) pendiente(s) en la Bandeja del equipo`,
    },
    mio: {
      n: misAvisos,
      titulo: `${misAvisos} cosa(s) tuyas: lo que te falta hacer y lo que te respondieron`,
    },
  };

  return (
    <div className="flex w-full flex-1">
      {/* Con treinta enlaces por delante del contenido en el DOM, tabular desde
          el inicio pasaba por los treinta antes de llegar a la página. */}
      <a
        href="#contenido"
        className="sr-only rounded-control bg-tinta px-4 py-2 text-sm text-crema focus:not-sr-only focus:fixed focus:left-4 focus:top-4 focus:z-[70]"
      >
        Saltar al contenido
      </a>

      <SidebarAdmin
        grupos={grupos}
        pathname={pathname}
        contadores={contadores}
        modo={modo}
        expandido={expandido}
        onAlternar={alternar}
        cerrados={cerrados}
        onAlternarGrupo={alternarGrupo}
      />

      <CajonAdmin
        abierto={cajonAbierto}
        onCerrar={() => setCajonAbierto(false)}
        grupos={grupos}
        pathname={pathname}
        contadores={contadores}
        nombre={persona?.nombreCompleto}
        onCerrarSesion={cerrarSesion}
        volverElFocoA={hamburguesa}
        cerrados={cerrados}
        onAlternarGrupo={alternarGrupo}
      />

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="sticky top-0 z-30 flex h-16 shrink-0 items-center gap-3 border-b border-sand bg-crema px-4 sm:px-6 md:grid md:grid-cols-[1fr_auto_1fr] print:hidden">
          {/* IZQUIERDA: en teléfono, el menú y la marca; en todos, el buscador. */}
          <div className="flex min-w-0 items-center gap-3 md:justify-self-start">
            {/* Un cuadrado RELLENO en tinta, no uno con borde `sand`, desde el
                2026-09-11: el borde sand da 1.16:1 sobre crema y a la vista era
                un icono flotando — se probó con gente en el menú de «Lo mío»,
                que es la misma receta, y no lo encontraban. Se cambian los dos a
                la vez porque son la misma pieza vista desde dos superficies. */}
            <button
              ref={hamburguesa}
              onClick={() => setCajonAbierto(true)}
              aria-label="Abrir menú"
              aria-expanded={cajonAbierto}
              className="rounded-control bg-tinta p-2 text-crema transition-colors duration-150 hover:bg-rojo active:scale-[0.97] md:hidden"
            >
              <Menu size={20} strokeWidth={1.8} aria-hidden />
            </button>

            {/* De 768px para arriba la marca vive en la cabecera del sidebar; acá
                solo aparece cuando ese sidebar no está. */}
            <Marca tono="tinta" isotipo="rojo" className="md:hidden" />

            <button
              onClick={() => setBuscadorAbierto(true)}
              aria-label="Buscar"
              className="flex items-center gap-1.5 rounded-control border border-sand px-2.5 py-1.5 text-sm text-taupe transition-colors duration-150 hover:border-taupe/40 hover:bg-sand/30 hover:text-rojo active:scale-[0.97] active:text-rojo-profundo"
            >
              <Search size={15} strokeWidth={1.8} aria-hidden />
              <span className="hidden sm:inline">Buscar</span>
              <kbd className="hidden rounded border border-sand bg-sand/50 px-1 font-sans text-[10px] text-taupe sm:inline">⌘K</kbd>
            </button>
          </div>

          {/* CENTRO: el saludo. Debajo de 768px no cabe y se esconde. */}
          <SaludoHora nombreCompleto={persona?.nombreCompleto} className="hidden md:block" />

          {/* DERECHA: atajos, modo claro/oscuro y, al final, cerrar sesión: la
              acción que se hace una vez al día va donde menos se pulsa por
              descuido, después de lo que se toca a cada rato. */}
          <div className="ml-auto flex shrink-0 items-center gap-2 md:justify-self-end">
            <button
              onClick={() => setAyudaAbierta(true)}
              aria-label="Atajos de teclado"
              title="Atajos de teclado (?)"
              className="hidden rounded-control border border-sand p-1.5 text-taupe transition-colors duration-150 hover:border-taupe/40 hover:bg-sand/30 hover:text-rojo active:scale-[0.97] active:text-rojo-profundo md:flex"
            >
              <Keyboard size={15} strokeWidth={1.8} aria-hidden />
            </button>
            <SelectorTema />
            <button
              onClick={cerrarSesion}
              className="hidden items-center gap-1.5 rounded-control border border-sand px-2.5 py-1.5 text-sm text-taupe transition-colors duration-150 hover:border-taupe/40 hover:bg-sand/30 hover:text-rojo active:scale-[0.97] active:text-rojo-profundo md:flex"
            >
              <LogOut size={15} strokeWidth={1.8} aria-hidden /> Cerrar sesión
            </button>
          </div>
        </header>

        <AcusesPendientes />

        <div id="contenido" tabIndex={-1} className="flex min-w-0 flex-1 flex-col outline-none">
          {children}
        </div>
      </div>

      <BuscadorGlobal grupos={grupos} abierto={buscadorAbierto} onCerrar={() => setBuscadorAbierto(false)} />
      <AtajosTeclado grupos={grupos} abierto={ayudaAbierta} setAbierto={setAyudaAbierta} />
      <ColibriViajero />
    </div>
  );
}

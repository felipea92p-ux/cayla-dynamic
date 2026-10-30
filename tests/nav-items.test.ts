// ============================================================================
// nav-items.test.ts — La estructura del menú, comprobada
// ============================================================================
// El menú se rehízo el 2026-09-07 (5 grupos → 7, barra superior → sidebar) y
// esa lista no la protegía nada: el repo no tiene ninguna prueba de interfaz,
// así que lo único que la miraba era el typecheck, y el typecheck no sabe que
// «Normas» tiene que verla todo el equipo.
//
// Lo que se prueba acá es exactamente lo que un rediseño puede romper EN
// SILENCIO — sin error de tipos, sin pantalla en blanco, sin que nadie se dé
// cuenta hasta que alguien reclame que no encuentra algo. Sobre todo la
// primera: quitarle el filtro de rol equivocado a una de esas tres pantallas
// es incumplir la Ley 30709 o la obligación de entregar el RIT.
// ============================================================================
import { describe, it, expect } from "vitest";
import { GRUPOS, esActivo, RUTAS_SIN_MARCO, type Item } from "@/app/(admin)/admin/nav-items";
import { ROLES_CON_PANEL, ROLES_DO, ROLES_GESTIONAN_BOLETAS } from "@cayla-dynamic/shared";

const TODOS: Item[] = GRUPOS.flatMap((g) => g.items);

describe("las tres pantallas que la ley obliga a mostrarle a todo el equipo", () => {
  // Ley 30709 (política salarial) y la obligación de entregar el Reglamento
  // Interno. Un menú que solo ve DO no informa a nadie ni prueba nada.
  const OBLIGATORIAS = ["/admin/politica-salarial", "/admin/normas", "/admin/anuncios"];

  for (const href of OBLIGATORIAS) {
    it(`${href} va sin filtro de rol`, () => {
      const item = TODOS.find((i) => i.href === href);
      expect(item, `${href} desapareció del menú`).toBeDefined();
      expect(item?.roles, `${href} se quedó con un filtro de rol`).toBeUndefined();
    });
  }

  it("y las tres viven juntas en «Publicaciones» — es lo que hace legible el menú de una integrante", () => {
    const grupo = GRUPOS.find((g) => g.label === "Publicaciones");
    expect(grupo).toBeDefined();
    expect(grupo?.items.map((i) => i.href).sort()).toEqual([...OBLIGATORIAS].sort());
  });

  it("una integrante ve «Lo mío» y esas tres, y nada más", () => {
    const rol = "integrante";
    const visibles = TODOS.filter((i) => !i.roles || i.roles.includes(rol));
    expect(visibles.map((i) => i.href)).toEqual([
      "/mio",
      "/admin/politica-salarial",
      "/admin/normas",
      "/admin/anuncios",
    ]);
  });
});

describe("la lista no tiene agujeros", () => {
  it("no hay dos renglones con la misma ruta", () => {
    const hrefs = TODOS.map((i) => i.href);
    expect(new Set(hrefs).size, `rutas repetidas: ${hrefs.length} renglones, ${new Set(hrefs).size} rutas`).toBe(hrefs.length);
  });

  it("ningún renglón se quedó sin etiqueta ni sin ícono", () => {
    for (const item of TODOS) {
      expect(item.label.trim(), `${item.href} sin etiqueta`).not.toBe("");
      expect(item.Icon, `${item.href} sin ícono`).toBeTruthy();
    }
  });

  it("son ocho grupos y treinta y cinco pantallas", () => {
    expect(GRUPOS).toHaveLength(8);
    expect(TODOS).toHaveLength(35);
  });

  it("solo el primer grupo va sin título — los otros siete se anuncian", () => {
    expect(GRUPOS[0].label).toBeUndefined();
    for (const g of GRUPOS.slice(1)) expect(g.label).toBeTruthy();
  });

  it("ningún grupo quedó vacío", () => {
    for (const g of GRUPOS) expect(g.items.length, `${g.label ?? "(sin título)"} vacío`).toBeGreaterThan(0);
  });
});

describe("los contadores", () => {
  // La vara para un contador DE EQUIPO está escrita en nav.tsx y es exigente: no
  // es «¿es importante?», es «¿tiene fecha límite y cuesta plata pasarla?».
  //
  // El de «Mi perfil» (2026-09-08) no compite con esos tres y por eso no los
  // vuelve cuatro: los tres hablan del EQUIPO —lo que a esta persona le toca
  // atender— y aquel habla de ELLA, de su contrato sin firmar y su constancia de
  // ley pendiente. La prueba conserva la vara separando las dos familias, en vez
  // de subir el número y perder lo que vigilaba.
  //
  // El de «Bandeja» (2026-09-12) tampoco entra acá, y por una tercera razón:
  // no es una pantalla más que pasa la vara con su propio criterio de
  // «pendiente» — es la UNIÓN de las nueve secciones de Bandeja, tres de las
  // cuales son justamente estas tres. Tiene su propia prueba abajo, separada
  // por la misma razón que ya separaba a «Mi perfil»: sumarlo acá perdería la
  // cuenta de "tres, y ninguna más" que esta prueba existe para vigilar.
  it("los del equipo son exactamente tres, en las pantallas que los saben atender", () => {
    const deEquipo = TODOS.filter((i) => i.contador && i.href.startsWith("/admin/") && i.href !== "/admin/bandeja");
    expect(deEquipo.map((i) => [i.href, i.contador])).toEqual([
      ["/admin/incidencias", "revisiones"],
      ["/admin/ausencias", "vacaciones"],
      ["/admin/educacion", "educacion"],
    ]);
  });

  it("el único contador que habla de quien mira el menú es el de «Mi perfil»", () => {
    const propios = TODOS.filter((i) => i.contador && !i.href.startsWith("/admin/"));
    expect(propios.map((i) => [i.href, i.contador])).toEqual([["/mio", "mio"]]);
  });

  // Ver lib/admin/bandeja-equipo.ts: la Bandeja junta hoy nueve secciones y
  // solo tres tenían aviso en algún otro renglón del menú. Esta prueba solo
  // vigila que el renglón siga llevando el contador y que sea el suyo propio
  // —no uno de los tres de arriba reetiquetado—; la cuenta de qué suma vive en
  // bandeja-equipo.ts, no en la estructura del menú.
  it("«Bandeja» lleva su propio contador, distinto de los tres que ya suma", () => {
    const item = TODOS.find((i) => i.href === "/admin/bandeja");
    expect(item?.contador).toBe("bandeja");
  });

  it("ninguna pantalla lleva dos contadores ni repite el de otra", () => {
    const nombres = TODOS.flatMap((i) => (i.contador ? [i.contador] : []));
    expect(new Set(nombres).size).toBe(nombres.length);
  });
});

describe("dónde quedó cada renglón después de reagrupar", () => {
  const grupoDe = (href: string) => GRUPOS.find((g) => g.items.some((i) => i.href === href))?.label;

  it("«Ausencias» está en Asistencia, no en Pago — la opera la encargada, no DO", () => {
    expect(grupoDe("/admin/ausencias")).toBe("Asistencia");
    const pago = GRUPOS.find((g) => g.label === "Pago");
    // Todo lo que quedó en Pago es de DO. Si algún día vuelve a colarse un
    // renglón de rol SEDE, para una encargada el grupo entero es un solo ítem.
    // Se compara el contenido y no la referencia: «Boletas» trae su propia
    // lista (ROLES_GESTIONAN_BOLETAS), que hoy dice lo mismo que DO.
    for (const item of pago?.items ?? []) expect([...(item.roles ?? [])].sort(), item.href).toEqual([...ROLES_DO].sort());
  });

  it("«Boletas» vive en Pago, justo debajo de Planilla, con la lista de quien entrega boletas", () => {
    expect(grupoDe("/admin/planilla/boletas")).toBe("Pago");
    const pago = GRUPOS.find((g) => g.label === "Pago")?.items.map((i) => i.href) ?? [];
    expect(pago.indexOf("/admin/planilla/boletas")).toBe(pago.indexOf("/admin/planilla") + 1);
    expect(TODOS.find((i) => i.href === "/admin/planilla/boletas")?.roles).toBe(ROLES_GESTIONAN_BOLETAS);
  });

  it("la líder de equipo no ve «Boletas»: es lo que cobra su equipo", () => {
    const item = TODOS.find((i) => i.href === "/admin/planilla/boletas");
    expect(item?.roles?.includes("supervisor_sede")).toBe(false);
    expect(item?.roles?.includes("lider_do")).toBe(true);
  });

  it("«Apariencia» está en Configuración, con lo demás que se toca una vez al año", () => {
    expect(grupoDe("/admin/apariencia")).toBe("Configuración");
  });

  it("«Archivo» vive en Empresa y solo lo ve DO: guarda papeles con el DNI del representante (0503)", () => {
    expect(grupoDe("/admin/archivo")).toBe("Empresa");
    expect(TODOS.find((i) => i.href === "/admin/archivo")?.roles).toBe(ROLES_DO);
  });

  it("«Seguros» vive en Personas, junto a los demás papeles por persona, y solo lo ve DO: el PDF lleva DNI (0528)", () => {
    expect(grupoDe("/admin/seguros")).toBe("Personas");
    expect(TODOS.find((i) => i.href === "/admin/seguros")?.roles).toBe(ROLES_DO);
  });

  it("«Parámetros» está en Configuración y solo lo ve DO: cada cambio mueve cómo funciona el sistema (0552)", () => {
    expect(grupoDe("/admin/parametros")).toBe("Configuración");
    expect(TODOS.find((i) => i.href === "/admin/parametros")?.roles).toBe(ROLES_DO);
  });

  it("la cabecera sin título son las tres pantallas de mirar a diario", () => {
    expect(GRUPOS[0].items.map((i) => i.href)).toEqual(["/mio", "/admin/dashboard", "/admin/bandeja"]);
  });

  it("«Asistencia» es entera de rol SEDE: es el grupo que la encargada usa todos los días", () => {
    const asistencia = GRUPOS.find((g) => g.label === "Asistencia");
    for (const item of asistencia?.items ?? []) expect(item.roles).toBe(ROLES_CON_PANEL);
  });
});

describe("qué renglón se resalta", () => {
  it("la ruta exacta", () => {
    expect(esActivo("/admin/planilla", "/admin/planilla")).toBe(true);
    expect(esActivo("/admin/planilla", "/admin/costos")).toBe(false);
  });

  it("la ficha de una persona resalta «Equipo», que es por donde se entra", () => {
    expect(esActivo("/admin/personas/abc-123", "/admin/equipo")).toBe(true);
  });

  it("el enlace viejo de vacaciones resalta «Ausencias», que se lo absorbió (0101)", () => {
    expect(esActivo("/admin/vacaciones", "/admin/ausencias")).toBe(true);
  });

  // Las dos rutas cuelgan una de la otra; sin la regla del más específico,
  // en Boletas se encendían «Planilla» y «Boletas» a la vez.
  const activosEn = (pathname: string) => TODOS.filter((i) => esActivo(pathname, i.href)).map((i) => i.href);

  it("en Boletas se resalta solo «Boletas», no también «Planilla»", () => {
    expect(activosEn("/admin/planilla/boletas")).toEqual(["/admin/planilla/boletas"]);
  });

  it("la boleta del sistema (/admin/planilla/boleta, sin renglón propio) sigue resaltando «Planilla»", () => {
    expect(activosEn("/admin/planilla/boleta")).toEqual(["/admin/planilla"]);
    expect(activosEn("/admin/planilla")).toEqual(["/admin/planilla"]);
  });

  it("ninguna ruta del menú enciende dos renglones a la vez", () => {
    for (const item of TODOS) expect(activosEn(item.href), item.href).toEqual([item.href]);
  });
});

describe("las rutas sin marco", () => {
  it("son las que no tienen sesión a la que preguntarle nada, más las redirecciones", () => {
    expect([...RUTAS_SIN_MARCO].sort()).toEqual([
      "/admin",
      "/admin/login",
      "/admin/nueva-clave",
      "/admin/olvide-clave",
      "/admin/perfil",
      "/admin/vacaciones",
    ]);
  });

  it("ninguna de ellas está en el menú — sería un renglón que lleva a un marco que se desmonta", () => {
    for (const href of RUTAS_SIN_MARCO) {
      expect(TODOS.some((i) => i.href === href), `${href} está en el menú Y en la lista sin marco`).toBe(false);
    }
  });
});

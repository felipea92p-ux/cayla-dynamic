// ============================================================================
// permisos.test.ts — Quién ve qué, comprobado
// ============================================================================
// Estas reglas vivían escritas a mano en 35 sitios, así que no había forma de
// probarlas: había que abrir veinte pantallas con veinte sesiones distintas.
// Ahora que viven en un solo archivo, la regla que importa —una encargada de
// sede NO ve sueldos— se comprueba en un segundo y en cada push.
// ============================================================================
import { describe, it, expect } from "vitest";
import {
  puedeVerPlanilla, puedeVerIdentidad, puedeGestionarCatalogos,
  puedeOperarEquipo, puedeVerTodasLasSedes, puedeExportarPadron,
  puedeVerSaludDeAlertas, puedeExportarAsistencia, puedeAnularDocumentoDisciplinario,
  puedeTramitarDisciplina, recibeAvisoDeConductaRegistrada, recibeAvisoDeLecturaPendiente,
  puedeVerNovedad, puedeGestionarBoletas, puedeMarcarCuentaDeServicio, puedeGestionarArchivo,
  puedeEstamparFirmaDeEmpresa,
  ROLES, ROLES_CON_PANEL, ROLES_DO, ROLES_EXPORTAN_ASISTENCIA,
} from "@cayla-dynamic/shared";

describe("la firma de quien firma por CAYLA se estampa por defecto, a quien abre el panel", () => {
  it("Gerencia, DO y la líder de equipo: exactamente los roles con panel", () => {
    for (const rol of ROLES) {
      expect(puedeEstamparFirmaDeEmpresa(rol)).toBe((ROLES_CON_PANEL as readonly string[]).includes(rol));
    }
    expect(puedeEstamparFirmaDeEmpresa("admin")).toBe(true);
    expect(puedeEstamparFirmaDeEmpresa("lider_do")).toBe(true);
    expect(puedeEstamparFirmaDeEmpresa("supervisor_sede")).toBe(true);
  });

  it("quien solo marca no la ve estampada", () => {
    expect(puedeEstamparFirmaDeEmpresa("integrante")).toBe(false);
  });

  it("sin rol, vacío o desconocido: null nunca pasa", () => {
    for (const rol of [null, undefined, "", "contador"]) {
      expect(puedeEstamparFirmaDeEmpresa(rol)).toBe(false);
    }
  });
});

describe("las novedades del sistema le llegan a quien las puede usar", () => {
  it("«panel» sigue exactamente la lista de quienes ven el panel — si esa cambia, esta cae", () => {
    for (const rol of ROLES) {
      expect(puedeVerNovedad(rol, "panel")).toBe((ROLES_CON_PANEL as readonly string[]).includes(rol));
    }
  });

  it("«do» es solo DO: la líder de equipo no lee sobre planilla", () => {
    for (const rol of ROLES) {
      expect(puedeVerNovedad(rol, "do")).toBe(ROLES_DO.includes(rol));
    }
    expect(puedeVerNovedad("supervisor_sede", "do")).toBe(false);
  });

  it("«todos» llega a los cuatro roles, incluso con el rol sin cargar", () => {
    for (const rol of [...ROLES, null, undefined, ""]) {
      expect(puedeVerNovedad(rol, "todos")).toBe(true);
    }
  });

  it("sin rol, un rol vacío o desconocido nunca abre «panel» ni «do»", () => {
    for (const rol of [null, undefined, "", "contador"]) {
      expect(puedeVerNovedad(rol, "panel")).toBe(false);
      expect(puedeVerNovedad(rol, "do")).toBe(false);
    }
  });
});

describe("marcar una cuenta de servicio es de DO: la saca de la planilla (0490)", () => {
  it("la líder de equipo no marca: fn_set_cuenta_de_servicio exige fn_es_admin_o_lider", () => {
    expect(puedeMarcarCuentaDeServicio("supervisor_sede")).toBe(false);
    expect(puedeMarcarCuentaDeServicio("integrante")).toBe(false);
  });
  it("gerencia y la líder de DO sí", () => {
    expect(puedeMarcarCuentaDeServicio("admin")).toBe(true);
    expect(puedeMarcarCuentaDeServicio("lider_do")).toBe(true);
  });
  it("sin rol cargado, no", () => {
    expect(puedeMarcarCuentaDeServicio(null)).toBe(false);
  });
});

describe("anular un documento disciplinario es de DO, aunque la encargada lo tramite", () => {
  it("la encargada no anula: fn_expediente_anular se lo rechaza (0058)", () => {
    expect(puedeAnularDocumentoDisciplinario("supervisor_sede")).toBe(false);
  });
  it("gerencia y la líder de DO sí", () => {
    expect(puedeAnularDocumentoDisciplinario("admin")).toBe(true);
    expect(puedeAnularDocumentoDisciplinario("lider_do")).toBe(true);
  });
  it("sin rol cargado, no", () => {
    expect(puedeAnularDocumentoDisciplinario(null)).toBe(false);
  });
});

describe("disciplina: mirar, tramitar y recibir el aviso son tres preguntas (0510, 0515)", () => {
  it("tramitar: DO siempre; la líder solo con contrato de trabajo (RIT 2.9)", () => {
    expect(puedeTramitarDisciplina("lider_do", false)).toBe(true);
    expect(puedeTramitarDisciplina("admin", false)).toBe(true);
    expect(puedeTramitarDisciplina("supervisor_sede", true)).toBe(true);
    expect(puedeTramitarDisciplina("supervisor_sede", false)).toBe(false);
    expect(puedeTramitarDisciplina("supervisor_sede", null)).toBe(false);
    expect(puedeTramitarDisciplina("integrante", true)).toBe(false);
  });
  it("el aviso de una falta registrada es solo para la líder DO: los admin lo ven en Disciplina, no se les empuja", () => {
    expect(recibeAvisoDeConductaRegistrada("lider_do")).toBe(true);
    expect(recibeAvisoDeConductaRegistrada("admin")).toBe(false);
    expect(recibeAvisoDeConductaRegistrada("supervisor_sede")).toBe(false);
    expect(recibeAvisoDeConductaRegistrada(null)).toBe(false);
  });
  it("el aviso de «nadie leyó lo que se le entregó» también es solo de la líder DO", () => {
    expect(recibeAvisoDeLecturaPendiente("lider_do")).toBe(true);
    expect(recibeAvisoDeLecturaPendiente("admin")).toBe(false);
    expect(recibeAvisoDeLecturaPendiente("supervisor_sede")).toBe(false);
    expect(recibeAvisoDeLecturaPendiente("integrante")).toBe(false);
    expect(recibeAvisoDeLecturaPendiente(undefined)).toBe(false);
  });
  it("y tomar el caso (DO y admin) es más ancho que recibir el aviso: si alguien los iguala, esto cae", () => {
    expect(puedeAnularDocumentoDisciplinario("admin")).toBe(true);
    expect(recibeAvisoDeConductaRegistrada("admin")).toBe(false);
  });
});

describe("la encargada de sede opera a su equipo, pero no ve la plata", () => {
  it("no ve planilla, ni provisiones, ni costos", () => {
    expect(puedeVerPlanilla("supervisor_sede")).toBe(false);
  });
  it("no ve DNI ni cuenta bancaria", () => {
    expect(puedeVerIdentidad("supervisor_sede")).toBe(false);
  });
  it("no sube ni ve las boletas de pago del equipo (0482)", () => {
    expect(puedeGestionarBoletas("supervisor_sede")).toBe(false);
  });
  it("no ve el Archivo de la empresa: la constancia de un banco de datos lleva el DNI del representante (0503)", () => {
    expect(puedeGestionarArchivo("supervisor_sede")).toBe(false);
  });
  it("no crea sedes, áreas ni feriados — eso cambia el pago de las cuatro sedes", () => {
    expect(puedeGestionarCatalogos("supervisor_sede")).toBe(false);
  });
  it("sí corrige marcajes, horarios y turnos de su gente", () => {
    expect(puedeOperarEquipo("supervisor_sede")).toBe(true);
  });
  it("pero solo de SU sede: el alcance es otra pregunta y responde que no", () => {
    expect(puedeVerTodasLasSedes("supervisor_sede")).toBe(false);
  });
  it("no ve la salud del despacho de avisos por correo: no tiene cómo arreglar Resend", () => {
    expect(puedeVerSaludDeAlertas("supervisor_sede")).toBe(false);
  });
  it("sí se baja el CSV de asistencia — es lo que pide una inspección de su tienda", () => {
    expect(puedeExportarAsistencia("supervisor_sede")).toBe(true);
  });
});

describe("quien solo marca no entra al panel", () => {
  for (const permiso of [puedeVerPlanilla, puedeVerIdentidad, puedeGestionarCatalogos, puedeOperarEquipo, puedeVerTodasLasSedes, puedeVerSaludDeAlertas, puedeExportarAsistencia, puedeGestionarBoletas, puedeGestionarArchivo]) {
    it(`integrante: ${permiso.name} = false`, () => {
      expect(permiso("integrante")).toBe(false);
    });
  }
});

describe("DO ve todo", () => {
  for (const rol of ["admin", "lider_do"]) {
    it(`${rol} pasa las cinco puertas`, () => {
      expect(puedeVerPlanilla(rol)).toBe(true);
      expect(puedeVerIdentidad(rol)).toBe(true);
      expect(puedeGestionarCatalogos(rol)).toBe(true);
      expect(puedeOperarEquipo(rol)).toBe(true);
      expect(puedeVerTodasLasSedes(rol)).toBe(true);
    });
    it(`${rol} ve la salud del despacho de avisos por correo (0362)`, () => {
      expect(puedeVerSaludDeAlertas(rol)).toBe(true);
    });
    it(`${rol} se baja el CSV de asistencia (hallazgo 26)`, () => {
      expect(puedeExportarAsistencia(rol)).toBe(true);
    });
    it(`${rol} sube y publica las boletas oficiales (0482)`, () => {
      expect(puedeGestionarBoletas(rol)).toBe(true);
    });
    it(`${rol} custodia el Archivo de la empresa (0503)`, () => {
      expect(puedeGestionarArchivo(rol)).toBe(true);
    });
  }
});

describe("null no pasa como autorizado", () => {
  // La misma regla que en Postgres (`is not true`, guards de la 0078): mientras
  // la sesión carga, el rol es null. Un `null` que pasara mostraría un sueldo
  // durante el parpadeo inicial de la pantalla.
  for (const raro of [null, undefined, "", "rrhh", "ADMIN", "Admin", "gerente"]) {
    it(`rol ${JSON.stringify(raro)} → no puede`, () => {
      expect(puedeVerPlanilla(raro)).toBe(false);
      expect(puedeOperarEquipo(raro)).toBe(false);
      expect(puedeVerSaludDeAlertas(raro)).toBe(false);
      expect(puedeExportarAsistencia(raro)).toBe(false);
      expect(puedeGestionarBoletas(raro)).toBe(false);
      expect(puedeGestionarArchivo(raro)).toBe(false);
    });
  }
});

describe("las listas para filtrar en la base coinciden con las funciones", () => {
  // Si alguien agrega un rol a una lista y se olvida de la función (o al revés),
  // la pantalla y la consulta discreparían en silencio. Esto lo impide.
  it("ROLES_DO son exactamente los que ven planilla", () => {
    expect([...ROLES_DO].sort()).toEqual(["admin", "lider_do"]);
    for (const r of ROLES_DO) expect(puedeVerPlanilla(r)).toBe(true);
  });
  it("ROLES_CON_PANEL son exactamente los que operan al equipo", () => {
    expect([...ROLES_CON_PANEL].sort()).toEqual(["admin", "lider_do", "supervisor_sede"]);
    for (const r of ROLES_CON_PANEL) expect(puedeOperarEquipo(r)).toBe(true);
  });
  // El menú filtra «Exportar CSV» con ROLES_EXPORTAN_ASISTENCIA y la pantalla
  // decide con `puedeExportarAsistencia`. Mientras digan lo mismo no hay renglón
  // que lleve a un «no tienes permiso», ni permiso escondido a quien sí lo
  // tiene. Se recorre `ROLES` entero —la lista exhaustiva de `enums.ts`— y no
  // solo la lista: así se cierran las DOS direcciones. Comprobar únicamente que
  // los de la lista pueden dejaría pasar el caso contrario —ensanchar la función
  // sin ensanchar la lista— que es justo la divergencia silenciosa que esto
  // existe para cazar.
  it("ROLES_EXPORTAN_ASISTENCIA son exactamente los que se bajan el CSV de asistencia", () => {
    expect([...ROLES_EXPORTAN_ASISTENCIA].sort()).toEqual(["admin", "lider_do", "supervisor_sede"]);
    for (const r of ROLES) {
      expect(puedeExportarAsistencia(r)).toBe(ROLES_EXPORTAN_ASISTENCIA.includes(r));
    }
  });
});

// ============================================================================
// Llevarse los datos no es lo mismo que verlos
// ============================================================================
// `puedeExportarPadron` es el único permiso más estrecho que `puedeVerIdentidad`,
// y la tentación es fundirlos: quien ya ve el DNI en pantalla «igual lo podría
// copiar». La diferencia no es el dato, es su forma. Una ficha en pantalla se
// mira; un CSV con veintiún DNI, direcciones y cuentas bancarias sale del
// sistema, se reenvía por WhatsApp y termina en la carpeta de Descargas de
// alguien. Ver y poder llevarse son dos permisos distintos.
//
// Se decidió el 2026-08-08, al construir la descarga del padrón para el contador.
describe("el padrón completo solo se lo lleva la dirección", () => {
  it("la dirección sí puede descargarlo", () => {
    expect(puedeExportarPadron("admin")).toBe(true);
  });

  it("quien lleva DO edita esas fichas todos los días y NO puede descargarlas", () => {
    // No es desconfianza: es que el archivo se genera para un trámite concreto
    // y esa decisión es de dirección. Si esto se pone en true, que sea a
    // propósito y no porque «total, ya las ve».
    expect(puedeVerIdentidad("lider_do")).toBe(true);
    expect(puedeExportarPadron("lider_do")).toBe(false);
  });

  it("la encargada de sede no, y tampoco veía las fichas", () => {
    expect(puedeExportarPadron("supervisor_sede")).toBe(false);
  });

  it("una integrante no", () => {
    expect(puedeExportarPadron("integrante")).toBe(false);
  });

  it("y un rol vacío, nulo o desconocido tampoco — null nunca pasa", () => {
    expect(puedeExportarPadron(null)).toBe(false);
    expect(puedeExportarPadron(undefined)).toBe(false);
    expect(puedeExportarPadron("")).toBe(false);
    expect(puedeExportarPadron("contador")).toBe(false);
  });

  it("es MÁS estrecho que ver identidad: si alguien los iguala, esto cae", () => {
    const roles = ["admin", "lider_do", "supervisor_sede", "integrante"];
    const ve = roles.filter((r) => puedeVerIdentidad(r));
    const baja = roles.filter((r) => puedeExportarPadron(r));
    expect(baja.length).toBeLessThan(ve.length);
    expect(ve).toEqual(expect.arrayContaining(baja));
  });
});

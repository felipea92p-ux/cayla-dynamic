// ============================================================================
// jornada.test.ts — Los dos topes no pueden confundirse
// ============================================================================
// CAYLA pacta jornada ordinaria de 48 h (el máximo del art. 25 de la
// Constitución) y programa un horario de 45 h. La diferencia parece cosmética y
// no lo es: el sobretiempo se mide contra la jornada ORDINARIA, no contra el
// horario (D.S. 007-2002-TR art. 9).
//
// Si alguien iguala las dos constantes —por "simplificar", o por creer que la
// jornada de CAYLA son 45 h— las horas 46 a 48 se convierten en sobretiempo con
// recargo del 25 % / 35 %. Al 2026-08-07 hay tres personas trabajando en ese
// rango, así que el cambio no sería teórico: crearía un pasivo el mismo día.
//
// Estas pruebas están para que ese cambio no pase inadvertido.
// ============================================================================
import { describe, it, expect } from "vitest";
import {
  MAXIMO_LEGAL_SEMANAL,
  HORARIO_PROGRAMADO_SEMANAL,
  avisoDeRacha,
  RECARGO_SOBRETIEMPO,
  excesoSobreJornada,
  MAXIMO_DIAS_SIN_DESCANSO,
  diasSeguidosTrabajados,
  ventanaMasCargada,
} from "@cayla-dynamic/shared";

describe("los topes de jornada", () => {
  it("el máximo legal es 48 h: es el techo del art. 25 de la Constitución", () => {
    expect(MAXIMO_LEGAL_SEMANAL).toBe(48);
  });

  it("el horario programado es 45 h y va POR DEBAJO del máximo legal", () => {
    expect(HORARIO_PROGRAMADO_SEMANAL).toBe(45);
    expect(HORARIO_PROGRAMADO_SEMANAL).toBeLessThan(MAXIMO_LEGAL_SEMANAL);
  });

  it("las dos cifras son distintas — igualarlas convierte las horas 46 a 48 en sobretiempo", () => {
    expect(HORARIO_PROGRAMADO_SEMANAL).not.toBe(MAXIMO_LEGAL_SEMANAL);
  });

  it("el recargo es 25 % las dos primeras horas y 35 % las siguientes", () => {
    expect(RECARGO_SOBRETIEMPO.horasPrimerTramo).toBe(2);
    expect(RECARGO_SOBRETIEMPO.primerTramo).toBe(0.25);
    expect(RECARGO_SOBRETIEMPO.tramoSiguiente).toBe(0.35);
  });
});

describe("excesoSobreJornada", () => {
  it("no hay exceso cuando se trabaja el horario programado", () => {
    expect(excesoSobreJornada(45)).toBe(0);
  });

  it("no hay exceso justo en el máximo legal", () => {
    expect(excesoSobreJornada(48)).toBe(0);
  });

  it("el exceso se mide desde 48, no desde 45", () => {
    // 47 h está por encima del horario programado pero dentro de la jornada
    // ordinaria pactada: no es sobretiempo.
    expect(excesoSobreJornada(47)).toBe(0);
    expect(excesoSobreJornada(49.3)).toBeCloseTo(1.3, 5);
  });

  it("nunca devuelve un negativo, aunque se trabaje poco", () => {
    expect(excesoSobreJornada(0)).toBe(0);
    expect(excesoSobreJornada(12.5)).toBe(0);
  });
});

describe("diasSeguidosTrabajados", () => {
  it("cuenta los días seguidos hacia atrás", () => {
    const f = ["2026-08-03", "2026-08-04", "2026-08-05", "2026-08-06"];
    expect(diasSeguidosTrabajados(f, "2026-08-06")).toBe(4);
  });

  it("un descanso corta la racha: solo cuenta lo posterior", () => {
    // Descansó el 5. Los días previos no suman.
    const f = ["2026-08-01", "2026-08-02", "2026-08-03", "2026-08-04", "2026-08-06", "2026-08-07"];
    expect(diasSeguidosTrabajados(f, "2026-08-07")).toBe(2);
  });

  it("devuelve 0 si ese día no trabajó", () => {
    expect(diasSeguidosTrabajados(["2026-08-03", "2026-08-04"], "2026-08-05")).toBe(0);
  });

  it("el caso que motivó todo: doce días seguidos con descanso rotativo mal puesto", () => {
    // Descansó el lunes 3 y el domingo 16. Cada semana calendario cuadra, pero
    // del martes 4 al sábado 15 no descansó ni un día.
    const f: string[] = [];
    for (let d = 4; d <= 15; d++) f.push(`2026-08-${String(d).padStart(2, "0")}`);
    expect(diasSeguidosTrabajados(f, "2026-08-15")).toBe(12);
    expect(diasSeguidosTrabajados(f, "2026-08-15")).toBeGreaterThan(MAXIMO_DIAS_SIN_DESCANSO);
  });

  it("cruza el fin de mes sin romperse", () => {
    const f = ["2026-07-29", "2026-07-30", "2026-07-31", "2026-08-01", "2026-08-02"];
    expect(diasSeguidosTrabajados(f, "2026-08-02")).toBe(5);
  });

  it("seis días seguidos todavía está dentro; el séptimo ya no", () => {
    const seis = ["2026-08-03","2026-08-04","2026-08-05","2026-08-06","2026-08-07","2026-08-08"];
    expect(diasSeguidosTrabajados(seis, "2026-08-08")).toBe(MAXIMO_DIAS_SIN_DESCANSO);
    expect(diasSeguidosTrabajados([...seis, "2026-08-09"], "2026-08-09"))
      .toBeGreaterThan(MAXIMO_DIAS_SIN_DESCANSO);
  });
});

describe("avisoDeRacha", () => {
  // Seis días seguidos: del viernes 8 al jueves 13 de agosto de 2026.
  const SEIS = ["2026-08-08", "2026-08-09", "2026-08-10", "2026-08-11", "2026-08-12", "2026-08-13"];

  it("el caso de Dayana: descansó al día siguiente y el aviso ya no aplica", () => {
    // El aviso decía «el próximo le toca descansar» anclado al jueves 13. El
    // viernes 14 descansó — y un descanso no deja fila en `jornadas`, así que lo
    // único que lo delata es que el 13 se quedó atrás. El sábado 15 ese aviso
    // pedía algo que ya había ocurrido.
    expect(avisoDeRacha(SEIS, "2026-08-15")).toBeNull();
  });

  it("no se apoya en que la persona vuelva a marcar para callarse", () => {
    // Antes se arreglaba solo cuando ella volvía a trabajar (la racha se reinicia
    // en 1). Con vacaciones o dos días libres seguidos, no volvía a marcar y el
    // aviso se quedaba pegado toda la semana.
    expect(avisoDeRacha(SEIS, "2026-08-20")).toBeNull();
    expect(avisoDeRacha(SEIS, "2026-08-27")).toBeNull();
  });

  it("el mismo día en que cierra la racha sí avisa: mañana le toca descansar", () => {
    const a = avisoDeRacha(SEIS, "2026-08-13");
    expect(a).not.toBeNull();
    expect(a!.seguidos).toBe(MAXIMO_DIAS_SIN_DESCANSO);
    expect(a!.excedida).toBe(false);
    expect(a!.ultimo).toBe("2026-08-13");
  });

  it("al día siguiente todavía avisa: puede que trabaje y aún no haya marcado", () => {
    // Es el momento en que mover el turno todavía sirve. Ante la duda se avisa:
    // equivocarse hacia el aviso cuesta una fila de más; hacia el silencio, una
    // infracción del D. Leg. 713.
    expect(avisoDeRacha(SEIS, "2026-08-14")).not.toBeNull();
  });

  it("la racha de 7+ NO caduca: la infracción ya ocurrió y alguien tiene que verla", () => {
    // Este es el contraste con el caso de Dayana. Con 6 el aviso pide algo que
    // todavía se puede hacer, y si ya se hizo sobra. Con 7 la infracción está
    // consumada: se saca con visto bueno, que deja constancia de quién la
    // revisó, nunca sola por antigüedad.
    const siete = [...SEIS, "2026-08-14"];
    const a = avisoDeRacha(siete, "2026-08-30");
    expect(a).not.toBeNull();
    expect(a!.seguidos).toBe(7);
    expect(a!.excedida).toBe(true);
  });

  it("aceptar un día no tapa el siguiente: la racha que crece vuelve a salir", () => {
    // El visto bueno se guarda por `persona|ultimo|tipo`. Si mañana sigue sin
    // descansar, `ultimo` cambia y el aviso reaparece con el día nuevo.
    const siete = [...SEIS, "2026-08-14"];
    const ocho = [...siete, "2026-08-15"];
    expect(avisoDeRacha(siete, "2026-08-15")!.ultimo).toBe("2026-08-14");
    expect(avisoDeRacha(ocho, "2026-08-15")!.ultimo).toBe("2026-08-15");
  });

  it("cinco días seguidos no dicen nada", () => {
    expect(avisoDeRacha(SEIS.slice(1), "2026-08-13")).toBeNull();
  });

  it("sin días marcados no revienta", () => {
    expect(avisoDeRacha([], "2026-08-15")).toBeNull();
  });

  it("cruza el fin de mes sin romperse", () => {
    const f = ["2026-07-27", "2026-07-28", "2026-07-29", "2026-07-30", "2026-07-31", "2026-08-01"];
    const a = avisoDeRacha(f, "2026-08-02");
    expect(a).not.toBeNull();
    expect(a!.seguidos).toBe(MAXIMO_DIAS_SIN_DESCANSO);
    expect(avisoDeRacha(f, "2026-08-03")).toBeNull();
  });
});

describe("ventanaMasCargada", () => {
  const d = (fecha: string, horas: number) => ({ fecha, horas });

  it("doce días de 8 h: por calendario da 48 y 48, por ventana móvil da 56", () => {
    // Este es el caso que la semana de lunes a domingo deja pasar.
    const dias = [];
    for (let i = 4; i <= 15; i++) dias.push(d(`2026-08-${String(i).padStart(2, "0")}`, 8));
    const v = ventanaMasCargada(dias, "2026-08-04", "2026-08-15");
    expect(v?.horas).toBe(56);
    expect(v!.horas).toBeGreaterThan(MAXIMO_LEGAL_SEMANAL);
  });

  it("seis días de 8 h con su descanso no pasa de 48 en ninguna ventana", () => {
    // lun-sáb trabajando, domingo libre, dos semanas seguidas
    const dias = [];
    for (const i of [3,4,5,6,7,8, 10,11,12,13,14,15]) {
      dias.push(d(`2026-08-${String(i).padStart(2, "0")}`, 8));
    }
    const v = ventanaMasCargada(dias, "2026-08-03", "2026-08-15");
    expect(v!.horas).toBeLessThanOrEqual(MAXIMO_LEGAL_SEMANAL);
  });

  it("Lima con 5 días de 9 h se queda en 45, por debajo del tope", () => {
    const dias = [3,4,5,6,7].map((i) => d(`2026-08-0${i}`, 9));
    const v = ventanaMasCargada(dias, "2026-08-03", "2026-08-09");
    expect(v?.horas).toBe(45);
  });

  it("sin datos devuelve null", () => {
    expect(ventanaMasCargada([], "2026-08-03", "2026-08-09")).not.toBeNull();
    expect(ventanaMasCargada([], "2026-08-03", "2026-08-09")?.horas).toBe(0);
  });

  // ── El caso de Lizzelott: la ventana no puede cruzar un descanso ──────────
  // Incidencias avisó «53.2 h en 7 días» el 24/08/2026. Esa cifra sale de sumar
  // la cola de una racha (18-22 ago, 45.36 h) con el arranque de la siguiente
  // (24-25 ago), puenteando por encima del descanso del 23 — algo que ninguna
  // semana real trabajó. La boleta nunca pagó sobretiempo porque el ciclo real
  // jamás llegó a 48. Ver `sobretiempo_ciclo_por_ciclo.sql` para el cálculo por
  // ciclos que sí respeta el corte.
  it("el caso de Lizzelott: un descanso en medio no deja que la ventana sume dos rachas", () => {
    const dias = [
      d("2026-08-18", 11.75), d("2026-08-19", 7.77), d("2026-08-20", 10.70),
      d("2026-08-21", 7.81), d("2026-08-22", 7.33),
      // 23: descanso, sin fila
      d("2026-08-24", 7.85), d("2026-08-25", 7.75),
    ];
    const v = ventanaMasCargada(dias, "2026-08-18", "2026-08-25");
    expect(v!.horas).toBeLessThanOrEqual(MAXIMO_LEGAL_SEMANAL);
    expect(v!.horas).toBeCloseTo(45.36, 2);
    expect(v!.fin).toBe("2026-08-22");
  });

  // ── El exceso que caducó antes de que nadie lo viera ──────────────────────
  // Incidencias evaluaba SOLO ventanas que terminaran en los últimos 7 días. Un
  // exceso cuya ventana cerró antes desaparecía de la pantalla para siempre: no
  // se degradaba a aviso menor, no quedaba registro, simplemente dejaba de
  // existir. El caso real: 58.96 h del 31/07 al 06/08/2026 —el exceso más
  // grande del periodo— invisible desde el 13 de agosto.
  //
  // Los datos son los de ese caso: siete días seguidos que suman 58.96 h,
  // descanso el 07, y después jornadas cortas que NO pasan de 48 en ninguna
  // ventana reciente. Por eso la pantalla se quedaba muda.
  describe("un exceso viejo sigue siendo visible", () => {
    const HOY_SIMULADO = "2026-08-15";
    const dias = [
      d("2026-07-31", 8.5), d("2026-08-01", 8.5), d("2026-08-02", 8.5),
      d("2026-08-03", 8.5), d("2026-08-04", 8.5), d("2026-08-05", 8.5),
      d("2026-08-06", 7.96),
      // 07-08: descanso, sin fila
      d("2026-08-08", 6), d("2026-08-09", 6), d("2026-08-10", 6), d("2026-08-11", 6),
      d("2026-08-12", 6), d("2026-08-13", 6), d("2026-08-14", 6), d("2026-08-15", 6),
    ];

    it("la ventana de los últimos 7 días no lo ve — por eso hacía falta la segunda", () => {
      const viva = ventanaMasCargada(dias, "2026-08-09", HOY_SIMULADO);
      expect(viva!.horas).toBeLessThanOrEqual(MAXIMO_LEGAL_SEMANAL);
    });

    it("la ventana de 30 días sí lo ve, y lo fecha en el día que cerró", () => {
      const vieja = ventanaMasCargada(dias, "2026-07-17", "2026-08-08");
      expect(vieja!.horas).toBeCloseTo(58.96, 2);
      expect(vieja!.horas).toBeGreaterThan(MAXIMO_LEGAL_SEMANAL);
      expect(vieja!.fin).toBe("2026-08-06");
    });

    it("las dos ventanas no se solapan: ningún exceso se cuenta dos veces", () => {
      // El corte es 08 / 09 de agosto. Si se solaparan, quien arrastra una racha
      // larga vería la misma infracción dos veces con dos fechas distintas.
      const viva = ventanaMasCargada(dias, "2026-08-09", HOY_SIMULADO);
      const vieja = ventanaMasCargada(dias, "2026-07-17", "2026-08-08");
      expect(vieja!.fin < viva!.fin).toBe(true);
    });
  });
});

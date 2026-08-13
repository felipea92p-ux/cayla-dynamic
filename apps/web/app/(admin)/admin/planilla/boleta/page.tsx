"use client";

import { Suspense, useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { useRolActual } from "@/lib/admin/use-rol";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { RANGO_LABEL, formatSoles } from "@/lib/rangos";
import { Cargando } from "@/components/cargando";
import { Marca } from "@/components/marca";
import {
  MESES_LARGO,
  fechaCorta,
  fechaLima,
  fmtHoras,
  type Fila,
  type Proyeccion,
} from "../page";
import {
  TZ_LIMA,
  esPrestadorDeServicios,
  nombreDelDocumentoDePago,
  puedeVerPlanilla,
} from "@cayla-dynamic/shared";

// Boleta INTERNA de CAYLA: resumen para que la persona vea cómo se calculó su
// sueldo del mes, e imprimirlo/entregarlo (Ctrl+P → Guardar como PDF). NO es
// la boleta oficial PLAME — ver el texto de valor al pie, decidido con Felipe
// el 2026-07-14 (formato lista, sin montos porque AFP varía por fondo).
//
// DESDE EL 2026-08-08 ESTA PANTALLA IMPRIME DOS DOCUMENTOS DISTINTOS, no uno con
// filas de menos. Quien está en planilla recibe la boleta interna de siempre;
// quien presta servicios por honorarios recibe un «Detalle de servicios
// prestados», con su propio encabezado, su propio cierre y su propio texto legal.
// El interruptor es uno solo —`esLocador`, más abajo— y sale de `en_planilla`,
// que la base ya calcula sola desde `tipo_vinculo`: no hay una segunda lista de
// nombres que mantener.
//
// La razón no es de redacción. Un documento que CAYLA emite todos los meses
// llamando «remuneración» a un honorario, contando los días que «te tocaba
// venir» y mandándote a consultar «con tu líder de equipo» es prueba escrita de
// subordinación, y pesa más en una inspección que el contrato firmado. Lo que se
// arregla acá no es el vocabulario: es lo que el papel declara.

function fechaHoyLima(): string {
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA, day: "numeric", month: "long", year: "numeric",
  }).format(new Date());
}

// «168.94 h» no se lee: son 168 h y 56 min. Vive solo aquí a propósito —
// fmtHoras (compartido con Planilla) sigue dando centésimas porque ahí son una
// tabla de trabajo y sirven para cuadrar. Esto es un documento para la persona.
function fmtHorasHumano(n: number): string {
  const h = Math.floor(n);
  const min = Math.round((n - h) * 60);
  if (min === 0) return `${h} h`;
  if (min === 60) return `${h + 1} h`;
  return `${h} h ${min} min`;
}

// Por qué el pago base no es el sueldo completo. Los datos ya existían —la 0100
// los expone justamente para que un cero no quede sin explicar—, lo que faltaba
// era decírselo a la persona en su propia boleta. Decidido con Felipe 2026-07-28.
//
// La redacción es deliberadamente distinta a la de Planilla: ahí dice «sin
// salario asignado — asígnale rango en Equipo» porque es una pantalla para
// administrar. Aquí lo mismo se cuenta sin pedirle a la persona que arregle
// nada, que no es su trabajo.
// Nada se imprime si el dato no vino. Suena obvio, pero aquí hay una trampa que
// costó un susto: las migraciones de este proyecto se pegan a mano en producción,
// así que el frontend puede desplegarse ANTES de que existan los campos. Un campo
// ausente llega como undefined, y en JavaScript `undefined > 0` es false (bien)
// pero `undefined === 0` también es false (mal): sin la guarda de typeof, la rama
// else escribía «undefined de undefined días» en un documento de pago.
// Por eso aquí se comprueba typeof number, no !== null.
function num(v: number | null | undefined): number | null {
  return typeof v === "number" && Number.isFinite(v) ? v : null;
}

function contextoPagoBase(f: Fila): string[] {
  const partes: string[] = [];
  const laborables = num(f.dias_laborables);
  const trabajados = num(f.dias_trabajados);
  const vacaciones = num(f.dias_vacaciones);
  const sinSalario = num(f.horas_sin_salario);

  // A QUIEN PRESTA UN SERVICIO NO SE LE CUENTAN LOS DÍAS QUE «LE TOCABA VENIR».
  // Las tres primeras frases de esta función miden asistencia contra un horario
  // esperado, y eso es exactamente lo que un locador no tiene. La que salía
  // impresa era la peor de las tres: «no hay horario asignado, así que el sistema
  // no sabe qué días te tocaba venir» — un documento firmado por CAYLA diciendo
  // que espera que alguien venga determinados días es un indicio de subordinación
  // por escrito, en el único papel que esa persona se lleva a casa.
  // Los días de vacaciones tampoco: no devenga vacaciones desde la 0196.
  //
  // La advertencia de horas SIN TARIFA sí se queda, y a propósito: es dinero que
  // se trabajó y no se pudo pagar. Callarlo en el documento que la persona usa
  // para emitir su recibo le esconde lo que se le debe.
  if (f.en_planilla === false) {
    if (sinSalario !== null && sinSalario > 0) {
      partes.push(`${fmtHoras(sinSalario)} sin tarifa asignada, que no se pudieron pagar`);
    }
    return partes;
  }

  if (laborables === 0) {
    partes.push("no hay horario asignado, así que el sistema no sabe qué días te tocaba venir");
  } else if (laborables !== null && trabajados !== null && trabajados <= laborables) {
    partes.push(`${trabajados} de ${laborables} días que te tocaba trabajar`);
  } else if (trabajados !== null) {
    // «21 de 10 días» es lo que salía antes, y no significa nada. Pasa cuando el
    // horario asignado cubre menos días de los que la persona vino de verdad —
    // normalmente porque su horario está mal configurado. La boleta no es el
    // sitio para destapar eso: dice los días que trabajó, que es un hecho, y el
    // desajuste se revisa en Horarios. Visto en producción el 2026-07-28 con una
    // persona a la que el sistema le contaba 10 laborables y trabajó 21.
    partes.push(`${trabajados} días trabajados`);
  }
  if (vacaciones !== null && vacaciones > 0) {
    partes.push(`${vacaciones} de vacaciones`);
  }
  if (sinSalario !== null && sinSalario > 0) {
    partes.push(`${fmtHoras(sinSalario)} sin tarifa asignada, que no se pudieron pagar`);
  }
  return partes;
}

function BoletaContenido() {
  const router = useRouter();
  const params = useSearchParams();
  const rol = useRolActual();
  const puedeVer = puedeVerPlanilla(rol);

  const periodoId = params.get("periodo");
  const personaId = params.get("persona");

  const [proy, setProy] = useState<Proyeccion | null>(null);
  const [baseLegal, setBaseLegal] = useState<number | null>(null);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const cargar = useCallback(async () => {
    if (!periodoId || !personaId) return;
    setCargando(true);
    setError(null);
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) {
      router.replace("/admin/login");
      return;
    }
    const { data, error: e } = await supabase.rpc("fn_proyeccion_periodo", { p_periodo_id: periodoId });
    setCargando(false);
    if (e) {
      setError(e.message);
      return;
    }
    setProy(data as unknown as Proyeccion);

    // La base legal contractual (0103) es un atributo de la PERSONA, no un
    // resultado del cálculo, así que se lee de personas y no de
    // fn_proyeccion_periodo — que son 320 líneas muy testeadas y no hacía falta
    // tocar. La política personas_select_admin_lider (0003) ya permite leerla.
    // Si falla, la boleta sigue funcionando sin esa línea: es información
    // añadida, no un requisito para mostrar el pago.
    const { data: persona } = await supabase
      .from("personas")
      .select("sueldo_base_legal")
      .eq("id", personaId)
      .maybeSingle();
    setBaseLegal(persona?.sueldo_base_legal ?? null);
  }, [periodoId, personaId, router]);

  useEffect(() => {
    void cargar();
  }, [cargar]);

  // El nombre con el que se guarda el PDF. Ver use-titulo-documento.ts para el
  // por qué; aquí solo se arma el texto. Acepta null mientras cargan los datos,
  // que es lo que permite llamarlo arriba sin romper el orden de los hooks.
  const filaTitulo = proy?.filas.find((x) => x.persona_id === personaId);
  useTituloDocumento(
    proy && filaTitulo
      ? `${filaTitulo.nombre} — ${
          filaTitulo.en_planilla === false ? "Servicios prestados" : "Boleta interna"
        } ${MESES_LARGO[proy.mes_etiqueta - 1]} ${proy.anio_etiqueta}`
      : null,
  );

  if (!periodoId || !personaId) {
    return (
      <main className="p-6">
        <p className="max-w-md rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
          Falta el periodo o la persona. Abre la boleta desde el botón{" "}
          <Link href="/admin/planilla" className="underline">
            🧾 Ver boleta
          </Link>{" "}
          de la tabla de Planilla.
        </p>
      </main>
    );
  }

  if (rol === null || cargando) {
    return (
      <main className="p-6">
        <Cargando />
      </main>
    );
  }

  if (!puedeVer) {
    return (
      <main className="p-6">
        <p className="max-w-md rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
          Solo administradores y líderes pueden generar boletas.
        </p>
      </main>
    );
  }

  if (error) {
    return (
      <main className="p-6">
        <p className="max-w-md rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
          No se pudo cargar el periodo: {error}{" "}
          <button onClick={() => void cargar()} className="font-medium underline">
            Reintentar
          </button>
        </p>
      </main>
    );
  }

  const f: Fila | undefined = proy?.filas.find((x) => x.persona_id === personaId);

  if (!proy || !f) {
    return (
      <main className="p-6">
        <p className="max-w-md rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
          No se encontró a esa persona en este periodo.{" "}
          <Link href="/admin/planilla" className="underline">
            Volver a Planilla
          </Link>
        </p>
      </main>
    );
  }

  // ── QUIÉN RECIBE ESTE PAPEL ────────────────────────────────────────────────
  // Hasta el 2026-08-08 esta pantalla imprimía UN solo documento para todos, y
  // ese documento hablaba el idioma de un contrato de trabajo: «boleta»,
  // «remuneración básica», «total a recibir este mes», «consulta con tu líder de
  // equipo». A quien presta un servicio por honorarios eso no le describe nada —
  // y peor: es CAYLA por escrito llamando trabajadora a una relación que no lo
  // es, en el único papel que esa persona se lleva. En una inspección, el
  // documento que la empresa emite todos los meses pesa más que el contrato.
  //
  // La pregunta la responde `packages/shared/src/vinculo.ts`, no esta pantalla:
  // son nueve las que van a hacerla, y este repositorio ya juntó 35 copias de la
  // misma condición de permiso antes de aprenderlo. Ahí está también el porqué
  // de que un dato ausente NO convierta a nadie en locador.
  const esLocador = esPrestadorDeServicios(f.en_planilla);

  const totalObj = f.objetivos_total ?? 10;
  // pctObj y nivelPlus se fueron con la fila del «Incentivo Variable por Metas»
  // (2026-08-01). Traducían el porcentaje de objetivos a la escala del plus
  // —«100% (21%)»— y eso solo tenía sentido dentro de esa fila. Si el plus vuelve
  // a mostrarse con su detalle, se recuperan de git.
  const bonos = f.movimientos?.filter((m) => m.tipo === "bono") ?? [];
  const descuentos = f.movimientos?.filter((m) => m.tipo === "descuento") ?? [];

  // Los dos términos que la 0110 metió en el 'total' del SQL. Hasta el
  // 2026-07-31 la boleta los ignoraba, y por eso el total no cuadraba con sus
  // propias líneas. Se leen con ?? 0 para que una base sin la 0110 pegada siga
  // dando el mismo resultado que antes.
  const movilidad = f.monto_movilidad ?? 0;
  const educacion = f.monto_educacion ?? 0;

  // ── Por qué la educación vale cero (0236) ────────────────────────────────
  // Hasta el 2026-08-12 esta fila se pintaba bajo `educacion > 0`, así que un
  // cero no imprimía «S/0.00»: no imprimía nada. Siete personas cobraron cero
  // durante un mes con su asignación vigente y su comprobante cargado, y la
  // boleta no daba pie ni para preguntar. Un concepto que desaparece cuando
  // falla es peor que uno que sale mal — el que sale mal se reclama el mismo día.
  //
  // `?? false` para que una base sin la 0236 pegada siga sin dibujar la fila en
  // vez de escribir una explicación que no puede sostener.
  const educacionRegistrada = f.educacion_registrada ?? false;
  const educacionSinPapel = f.educacion_sin_comprobante ?? false;
  const pension = f.descuento_afp ?? 0;
  const aporteEssalud = f.aporte_essalud ?? 0;

  // El recargo del sobretiempo (0185). Mismo criterio que la movilidad: entra en
  // el 'total' del SQL, así que si la boleta no lo imprime el total deja de
  // cuadrar con sus líneas. `?? 0` para que una base sin la 0185 pegada no dibuje
  // la fila en vez de escribir «S/ NaN».
  const sobretiempo = f.monto_sobretiempo ?? 0;
  const diasSobretiempo =
    f.sobretiempo_desde && f.sobretiempo_hasta
      ? f.sobretiempo_desde === f.sobretiempo_hasta
        ? fechaCorta(f.sobretiempo_desde)
        : `${fechaCorta(f.sobretiempo_desde)} al ${fechaCorta(f.sobretiempo_hasta)}`
      : null;

  // Subtotal ganado: todo lo que suma, antes de restar. Solo se muestra si hay
  // algo que restar — sin eso sería idéntico al total y solo agregaría ruido.
  // Decidido con Felipe el 2026-07-28: cuando el descuento es grande (un adelanto,
  // por ejemplo), sin esta línea la persona ve solo el neto y no reconoce que sí
  // ganó su sueldo completo. Suma los mismos campos ya redondeados que usa el
  // 'total' de fn_proyeccion_periodo, así el desglose cuadra al céntimo.
  const subtotalGanado =
    f.pago_base +
    f.monto_feriados +
    sobretiempo +
    f.asignacion_familiar +
    f.monto_plus +
    movilidad +
    educacion +
    bonos.reduce((suma, m) => suma + m.monto, 0);

  // La pensión también es una resta, así que también justifica el subtotal.
  const hayRestas = descuentos.length > 0 || pension > 0;

  // ¿Esta boleta es definitiva o todavía se mueve? Antes no se decía en ningún
  // lado, así que alguien podía imprimirla, guardarla, y después recibir otro
  // monto. Para un periodo ya pagado NO decimos «definitiva»: decimos la fecha
  // en que se pagó, que es un hecho. (fn_proyeccion_periodo recalcula en vivo y
  // no lee la foto congelada de la 0096, así que afirmar «definitiva» sería
  // prometer algo que esta pantalla no puede garantizar.)
  // 'estado' es opcional en Proyeccion: si no viene, no inventamos sello.
  const sello =
    proy.simulacion
      ? { texto: "Simulación — no es un pago real", alerta: true }
      : proy.estado === "pagado"
        ? { texto: `Pagada${proy.pagado_at ? ` el ${fechaCorta(proy.pagado_at)}` : ""}`, alerta: false }
        : proy.estado === "abierto"
          ? {
              // Para un locador el corte no es «el mes»: es el periodo del 29 al
              // 28 contra el que va a emitir su recibo. Decirle «mes» lo manda a
              // fecharlo mal.
              texto: esLocador
                ? "Provisional — el periodo aún no cierra"
                : "Provisional — el mes aún no cierra",
              alerta: true,
            }
          : null;

  const contexto = contextoPagoBase(f);

  // EL DESGLOSE «BÁSICA + RENDIMIENTO EXTRAORDINARIO» YA NO SE CALCULA AQUÍ.
  // Quitado a pedido de Felipe el 2026-07-31. El «Rendimiento Extraordinario»
  // fue una etiqueta de emergencia para poder pagar un mes, no un concepto real
  // de la estructura salarial, y dejarlo impreso describía como «variable, no
  // permanente» algo que en la práctica se paga todos los meses — que es
  // exactamente el argumento que un inspector usa para reclasificarlo como
  // remuneración permanente. Los campos siguen existiendo en la base y en la
  // pantalla de Planilla; lo que se retira es imprimirlos en la boleta.
  //
  // La cifra del pago NO cambia: basica_legal_prop + complemento_variable era
  // igual a pago_base por construcción, así que mostrar pago_base en una sola
  // fila da el mismo monto y el total sigue cuadrando al céntimo.

  const pendientes = num(f.dias_pendientes) ?? 0;
  const avisoPendientes =
    pendientes > 0
      ? pendientes === 1
        ? "Queda 1 día por confirmar: este monto todavía puede cambiar."
        : `Quedan ${pendientes} días por confirmar: este monto todavía puede cambiar.`
      : null;

  return (
    <main className="mx-auto max-w-2xl p-6 print:p-0">
      {/* Barra de acciones — no se imprime */}
      <div className="mb-6 flex items-center justify-between print:hidden">
        <Link href="/admin/planilla" className="text-sm text-taupe hover:text-tinta hover:underline">
          ← Volver a Planilla
        </Link>
        <button
          onClick={() => window.print()}
          className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema hover:bg-rojo-profundo"
        >
          Imprimir / Guardar como PDF
        </button>
      </div>

      {/* ── Boleta ── */}
      {/* La clase `hoja` no pinta nada en pantalla: existe solo para que las
          reglas de @media print de globals.css puedan apretar el interlineado y
          los rellenos de las celdas sin repetir quince variantes print: aquí. */}
      <div className="hoja rounded-lg border border-sand p-8 print:rounded-none print:border-0 print:p-0">
        <div className="mb-6 flex items-start justify-between border-b border-sand pb-4 print:mb-4 print:pb-3">
          <Marca tono="tinta" isotipo="rojo" />
          <div className="text-right">
            <p className="etiqueta text-taupe">{nombreDelDocumentoDePago(f.en_planilla)}</p>
            <p className="font-serif text-lg">
              {MESES_LARGO[proy.mes_etiqueta - 1]} {proy.anio_etiqueta}
            </p>
            {sello && (
              <p
                className={`mt-1 inline-block rounded px-2 py-0.5 text-xs font-medium ${
                  sello.alerta ? "bg-rojo/10 text-rojo" : "bg-verde/10 text-verde"
                }`}
              >
                {sello.texto}
              </p>
            )}
            <p className="text-xs text-taupe">
              {fechaCorta(proy.fecha_ini)} → {fechaCorta(proy.fecha_fin)}
            </p>
          </div>
        </div>

        <div className="mb-6 print:mb-4">
          <p className="font-serif text-2xl">{f.nombre}</p>
          {/* EL PELDAÑO DE LA ESCALA NO SE IMPRIME EN EL PAPEL DE UN LOCADOR.
              La decisión ya estaba tomada —la 0182 lo quitó de la tabla de
              Planilla, con este argumento: la escala es de trabajadores, y decir
              que alguien ocupa una categoría dentro de ella es parte de lo que
              desnaturaliza una locación de servicios— pero se aplicó solo en la
              pantalla de gestión. El documento que se imprime y se entrega
              seguía diciendo «Colibrí». Encontrado el 2026-08-08 mirando la hoja
              renderizada, no leyendo el código: en el código las dos pantallas
              parecen distintas y nada las conecta.
              El rango se sigue usando para saber cuánto se le transfiere; lo que
              no se hace es escribírselo encima. */}
          <p className="text-sm text-taupe">
            {esLocador
              ? f.sede
              : `${f.sede} · ${f.rango ? (RANGO_LABEL[f.rango] ?? f.rango) : "sin rango"}`}
          </p>

          {/* EL POTENCIAL MÁXIMO DEL RANGO YA NO SE IMPRIME AQUÍ.
              Decidido con Felipe el 2026-07-28, y la razón no es el número: es
              el consentimiento. La boleta es unilateral —nadie la firma—, así
              que un «potencial máximo» impreso cada mes crea una expectativa que
              el integrante nunca aceptó, y eso es lo que se presentaría como
              promesa incumplida. El mismo número, en el convenio firmado, es un
              entendimiento mutuo documentado, que es lo que el Art. 19 necesita.
              De paso desaparecen dos problemas: que la cifra se podía superar
              (el plus por metas es 21% ENCIMA del rango) y el desmentido que
              había que poner en el pie para explicarla.
              El potencial sigue existiendo en Planilla, para gestión interna. */}
          {baseLegal !== null && (
            <dl className="mt-3 space-y-1 text-sm">
              {/* «(mes completo)» no es decoración: sin eso, esta cifra y la fila
                  del desglose se llamaban IGUAL y mostraban montos distintos
                  (1,130.00 aquí y 947.41 abajo). Quien lo leyera rápido pensaba
                  que había un error. Ahora una dice «mes completo» y la otra
                  «proporcional», y se entienden sin explicación. */}
              <div className="flex justify-between gap-4">
                <dt className="font-medium">
                  {esLocador
                    ? "Honorarios pactados (mes completo)"
                    : "Remuneración Básica Legal (mes completo)"}
                </dt>
                <dd className="font-medium">{formatSoles(baseLegal)}</dd>
              </div>
            </dl>
          )}
        </div>

        {/* Detalle del pago */}
        <table className="mb-6 w-full text-sm print:mb-4">
          <tbody>
            {/* UNA SOLA FILA PARA EL PAGO DEL PERIODO.
                Antes esto se partía en «Básica legal proporcional» +
                «Rendimiento Extraordinario». Se unificó el 2026-07-31 a pedido
                de Felipe: el Rendimiento fue una salida de emergencia para poder
                pagar un mes, y una etiqueta de emergencia no debería quedar
                impresa como si fuera parte de la estructura salarial.
                El monto es idéntico — las dos filas de antes sumaban pago_base
                por construcción, así que el total no se movió ni un céntimo.
                El «(mes completo)» de la cifra de arriba sigue siendo lo que
                distingue esa referencia de esta fila proporcional. */}
            <tr className="border-t border-sand">
              <td className="py-2">
                {esLocador
                  ? `Honorarios por las horas prestadas (${fmtHorasHumano(f.horas_mes)})`
                  : `Remuneración Básica proporcional (${fmtHorasHumano(f.horas_mes)})`}
                {/* La sublínea de un locador NO compara contra «el mes completo».
                    Esa comparación es la que insinúa un sueldo mensual del que
                    este mes se pagó una parte, y quien factura por hora no tiene
                    tal cosa: tiene las horas que prestó. */}
                {esLocador ? (
                  <span className="block text-xs text-taupe">
                    Horas prestadas en el periodo
                  </span>
                ) : (
                  baseLegal !== null && (
                    <span className="block text-xs text-taupe">
                      por tus horas del periodo · el mes completo son{" "}
                      {formatSoles(baseLegal)}
                    </span>
                  )
                )}
                {contexto.length > 0 && (
                  <span className="block text-xs text-taupe">{contexto.join(" · ")}</span>
                )}
                {avisoPendientes && (
                  <span className="block text-xs text-rojo">{avisoPendientes}</span>
                )}
              </td>
              <td className="py-2 text-right align-top">{formatSoles(f.pago_base)}</td>
            </tr>
            {f.monto_feriados > 0 && (
              <tr className="border-t border-sand">
                <td className="py-2">Feriados</td>
                <td className="py-2 text-right">{formatSoles(f.monto_feriados)}</td>
              </tr>
            )}
            {/* Sobretiempo (0185). Se imprime el RECARGO, que es lo que esta línea
                agrega: las horas en sí ya están cobradas dentro del pago base. Sin
                decirlo, «6 h de sobretiempo = S/10.66» se lee como si la hora
                valiera S/1.78 y la persona no puede reconocer su propio pago.
                También se dicen los días: el recargo se mide contra las 48 horas
                SEMANALES, así que sin la fecha nadie puede rehacer la cuenta. */}
            {sobretiempo > 0 && (
              <tr className="border-t border-sand">
                <td className="py-2">
                  Sobretiempo
                  <span className="block text-xs text-taupe">
                    {fmtHorasHumano(f.horas_sobretiempo ?? 0)} por encima de las 48 de la
                    semana{diasSobretiempo && ` · ${diasSobretiempo}`} · se paga el recargo
                    (25 % las 2 primeras horas de cada día, 35 % las demás); las horas
                    mismas ya están en el pago base
                  </span>
                </td>
                <td className="py-2 text-right align-top">{formatSoles(sobretiempo)}</td>
              </tr>
            )}
            {f.asignacion_familiar > 0 && (
              <tr className="border-t border-sand">
                <td className="py-2">Asignación familiar 👶</td>
                <td className="py-2 text-right">{formatSoles(f.asignacion_familiar)}</td>
              </tr>
            )}
            {/* La 0110 metió la movilidad en el 'total' del SQL y nadie la imprimía:
                el total no cuadraba con sus propias líneas. Se dice cuántos días y a
                qué tarifa porque es lo que sostiene el concepto — la movilidad es no
                remunerativa SOLO si está supeditada a la asistencia (Art. 19 e),
                D.S. 001-97-TR), y la multiplicación impresa es la prueba de que lo
                está. Un monto pelado, sin días, se lee como sueldo con otro nombre. */}
            {movilidad > 0 && (
              <tr className="border-t border-sand">
                <td className="py-2">
                  Movilidad por asistencia
                  <span className="block text-xs text-taupe">
                    {f.dias_laborables != null && f.movilidad_diaria
                      ? `${Math.round(movilidad / f.movilidad_diaria)} días marcados × ${formatSoles(f.movilidad_diaria)}`
                      : "por tus días efectivamente asistidos"}
                  </span>
                </td>
                <td className="py-2 text-right align-top">{formatSoles(movilidad)}</td>
              </tr>
            )}
            {/* Mismo caso que la movilidad, descubierto el 2026-08-04: la 0120 la
                metía en el 'total' y ninguna línea la nombraba. Se imprime la
                institución porque es lo que sostiene el concepto — la asignación
                por educación es no remunerativa por el inciso f) del Art. 19, y
                un monto pelado sin decir de qué estudio sale se lee como sueldo
                con otro nombre. El nombre del hijo NO se imprime: identifica al
                estudio, no al menor. */}
            {/* ⇩ CAMBIO 0236 ⇩ La fila también sale en cero, y dice por qué. Solo
                cuando la persona TIENE una asignación que se solapa con el
                periodo: para quien no estudia, una línea en cero sería ruido y
                no transparencia. */}
            {(educacion > 0 || educacionRegistrada) && (
              <tr className="border-t border-sand">
                <td className="py-2">
                  Asignación por educación
                  <span className="block text-xs text-taupe">
                    {educacion > 0
                      ? f.instituciones_educacion
                        ? `${f.instituciones_educacion} · contra comprobante`
                        : "contra el comprobante archivado"
                      : educacionSinPapel
                        ? "tu asignación está registrada, pero todavía falta cargar el comprobante · no se paga hasta tenerlo"
                        : "tu asignación no está vigente en este periodo · consúltalo con Desarrollo Organizacional"}
                  </span>
                </td>
                <td className="py-2 text-right align-top">{formatSoles(educacion)}</td>
              </tr>
            )}
            {/* EL «INCENTIVO VARIABLE POR METAS (NO PERMANENTE)» SALE DE LA BOLETA.
                Pedido de Felipe el 2026-08-01, y por la misma razón que salió el
                «Rendimiento Extraordinario» el día anterior: un concepto que se
                describe a sí mismo como «no permanente» impreso todos los meses es
                el argumento que un inspector usa para sostener lo contrario. Y
                cuando el plus era cero —el caso de todos los meses en que no se
                registran objetivos— la fila solo imprimía un guion y una
                explicación de por qué no había nada.

                PERO EL MONTO NO SE OCULTA. Si el plus llegara a ser mayor que cero,
                la fila SÍ aparece: `monto_plus` está dentro del 'total' que calcula
                el SQL, y una boleta cuyo total incluye algo que no se imprime es
                exactamente el descuadre que Felipe encontró el 2026-08-01 con el
                descuento de pensión (S/76.67 en las líneas, S/71.84 en el total).
                No se repite ese error para ahorrar una fila.

                Lo que cambia cuando aparece es el NOMBRE: se llama por lo que es
                —un incentivo por metas— sin la autodescripción de «no permanente»,
                que era la parte que hacía daño. */}
            {f.monto_plus > 0 && (
              <tr className="border-t border-sand">
                <td className="py-2">
                  Incentivo por metas
                  {f.objetivos_cumplidos !== null && (
                    <span className="block text-xs text-taupe">
                      {f.objetivos_cumplidos}/{totalObj} cumplidos
                    </span>
                  )}
                </td>
                <td className="py-2 text-right align-top">{formatSoles(f.monto_plus)}</td>
              </tr>
            )}
            {bonos.map((m) => (
              <tr key={m.id} className="border-t border-sand">
                {/* Sin el prefijo «Bono — », a propósito (2026-07-28). La
                    gratificación y la CTS se guardan como tipo='bono' —la tabla
                    movimientos_planilla solo tiene 'bono' y 'descuento', sin
                    categoría—, así que el prefijo escribía «Bono — Gratificación»
                    y seguía llamando bono a un derecho de ley. El concepto ya
                    lleva su nombre, y que suma se ve en el signo + y en el verde.
                    Para los descuentos el prefijo se queda: ahí no hay riesgo
                    legal y ayuda a leer por qué se resta. */}
                <td className="py-2 text-verde">{m.concepto}</td>
                <td className="py-2 text-right text-verde">+{formatSoles(m.monto)}</td>
              </tr>
            ))}
            {hayRestas && (
              <tr className="border-t border-tinta/30">
                <td className="py-2 font-medium">Subtotal ganado</td>
                <td className="py-2 text-right font-medium">{formatSoles(subtotalGanado)}</td>
              </tr>
            )}
            {/* EL DESCUENTO DE PENSIÓN, que el 'total' venía restando sin imprimirlo.
                Es el que produjo el descuadre que Felipe vio el 2026-08-01: la boleta
                sumaba 76.67 en lo visible y remataba en 71.84, con 4.83 de pensión
                aplicados y sin una línea que los nombrara.
                Se dice el régimen y la tasa porque el descuento varía por persona
                (12.84% a 13.06% según la AFP), y sin eso el monto no se puede verificar.
                Y se aclara que no se queda en CAYLA: va al fondo de la persona. */}
            {pension > 0 && (
              <tr className="border-t border-sand">
                <td className="py-2 text-rojo">
                  Descuento —{" "}
                  {f.regimen_pension === "onp"
                    ? "ONP"
                    : f.regimen_pension
                      ? `AFP ${f.regimen_pension.charAt(0).toUpperCase()}${f.regimen_pension.slice(1)}`
                      : "Pensión"}
                  {f.tasa_afp ? ` (${(f.tasa_afp * 100).toFixed(2)}%)` : ""}
                  <span className="block text-xs text-rojo/70">
                    va a tu fondo de pensión — no se queda en CAYLA
                  </span>
                </td>
                <td className="py-2 text-right align-top text-rojo">−{formatSoles(pension)}</td>
              </tr>
            )}
            {/* Y EL CASO CONTRARIO: quien ya se jubiló no aporta, así que su
                descuento es cero — y con la condición de arriba su boleta no
                decía NADA de pensión. Es la misma falla que el comentario de
                arriba describe, del otro lado: allá el total restaba algo que no
                se imprimía; acá no resta nada y tampoco se imprime por qué.

                Un silencio así es ambiguo entre tres cosas muy distintas: «no
                aporta porque está jubilada» (una decisión), «se nos olvidó
                descontarle» (un error) y «no tiene régimen cargado» (un dato que
                falta). La 0190 se tomó el trabajo de distinguirlas en la base
                —por eso `jubilada` es un valor y no un campo vacío— y dejarlo
                fuera de la boleta lo deshacía justo donde lo lee la persona.

                Y le pasa a ella sola: todas sus compañeras tienen esa línea. Sin
                esto, comparar dos boletas sugiere que a la suya le falta algo.

                No entra en `hayRestas` a propósito: no resta nada, así que un
                «Subtotal ganado» idéntico al total sería ruido. Y va en color
                normal, no en rojo: el rojo en esta boleta significa «esto te lo
                quitan». */}
            {pension === 0 && f.regimen_pension === "jubilada" && (
              <tr className="border-t border-sand">
                <td className="py-2">
                  Pensión — no se te descuenta
                  <span className="block text-xs text-tinta/60">
                    ya te jubilaste, así que no aportas al sistema de pensiones
                  </span>
                </td>
                <td className="py-2 text-right align-top">{formatSoles(0)}</td>
              </tr>
            )}
            {descuentos.map((m) => (
              <tr key={m.id} className="border-t border-sand">
                <td className="py-2 text-rojo">Descuento — {m.concepto}</td>
                <td className="py-2 text-right text-rojo">−{formatSoles(m.monto)}</td>
              </tr>
            ))}
            {/* El cierre de un locador no es «lo que vas a recibir»: es la cifra
                por la que tiene que emitir su recibo. Sin decirlo, esta hoja
                parecía el documento del pago — y el documento del pago es el
                recibo por honorarios que emite él, no este papel. */}
            <tr className="border-t-2 border-tinta">
              <td className="py-3 font-serif text-lg">
                {esLocador ? "Total del periodo" : "Total a recibir este mes"}
                {esLocador && (
                  <span className="block font-sans text-xs font-normal text-taupe">
                    emite tu recibo por honorarios por este importe
                  </span>
                )}
              </td>
              <td className="py-3 text-right align-top font-serif text-lg font-bold">
                {formatSoles(f.total)}
              </td>
            </tr>
          </tbody>
        </table>

        {/* ── LO QUE CAYLA PAGA ADEMÁS ─────────────────────────────────────────
            Pedido de Felipe el 2026-07-31: «quiero que todo integrante de CAYLA vea
            todo lo que pagamos». Estas cifras existían en la base y no se imprimían
            en ninguna parte.

            TRES DECISIONES DE DISEÑO, y ninguna es estética:

            1. VA FUERA DE LA TABLA DEL PAGO, en su propio bloque y con su propio
               encabezado. El D.S. 001-98-TR pide que los descuentos se distingan; acá
               el riesgo es el inverso —que alguien lea el EsSalud como algo que se le
               resta— así que la separación física y la leyenda «no se descuenta de tu
               sueldo» son el resguardo. Nada de esto entra en el total.

            2. LOS MONTOS VAN COMO NÚMEROS, no como prosa. Si el objetivo es que
               valoren lo que la empresa hace, un párrafo no lo logra. Y las tres
               provisiones son honestas: la gratificación trunca, la CTS trunca y las
               vacaciones truncas se pagan proporcionalmente al cesar, así que el
               acumulado ES lo que le corresponde a la persona.

            3. NO SE IMPRIME EL TOTAL NI EL «X% MÁS». Decidido con Felipe: las cuatro
               líneas transmiten el mensaje, y una cifra única de «lo que nos cuestas»
               se vuelve punto de referencia en la próxima conversación de sueldo y no
               se puede desmostrar. Es el mismo criterio por el que el 2026-07-28 salió
               de la boleta el «potencial máximo del rango».

            La leyenda dice «acumulado a la fecha · se paga según ley» y no un monto
            futuro prometido, por la misma razón que el potencial máximo salió de acá:
            una cifra impresa cada mes en un documento que nadie firma crea una
            expectativa que después se reclama. */}
        {/* Y NUNCA PARA UN LOCADOR, aunque los números vinieran distintos de cero.
            Desde la 0199 sus cuatro cifras son 0 y el bloque ya no se dibujaba
            solo, así que este `!esLocador` no cambia nada HOY. Está porque la
            condición de antes preguntaba por los montos, y un monto puede volver:
            basta que alguien le encienda una bandera de la 0196 por error, o que
            un cálculo futuro le genere EsSalud, para que un papel de CAYLA vuelva
            a decirle a un locador «CAYLA paga por ti tu seguro de salud y tu
            gratificación» — que es, en una palabra, la definición de trabajador.
            La regla se dice por lo que la persona ES, no por lo que le salió. */}
        {!esLocador && (aporteEssalud > 0 || f.provision_total > 0) && (
          <div className="mb-6 rounded-lg bg-arena/60 p-4 print:mb-4">
            <p className="text-xs font-semibold uppercase tracking-wide text-tinta">
              Además, CAYLA paga por ti
            </p>
            <p className="mb-3 text-xs text-taupe">
              Aporte de la empresa — <strong>no se descuenta de tu sueldo.</strong>
            </p>
            <table className="w-full text-sm">
              <tbody>
                {aporteEssalud > 0 && (
                  <tr className="border-t border-sand">
                    <td className="py-2">
                      EsSalud {f.essalud_tasa ? `${(f.essalud_tasa * 100).toFixed(0)}%` : ""}
                      <span className="block text-xs text-taupe">
                        tu seguro de salud · lo paga CAYLA completo
                        {/* Sin esta aclaración el número es inexplicable en un mes de
                            pocas horas: la ley fija un piso —la base no puede ser menor
                            a la RMV, y no se prorratea por días (D.S. 009-97-SA, mod.
                            D.S. 020-2006-TR)—, así que quien devengó S/36.96 genera
                            S/101.70 igual. Quien lea su boleta va a hacer la división
                            y no le va a cuadrar; mejor decirlo. */}
                        {f.essalud_es_piso && (
                          <>
                            {" "}
                            · calculado sobre el mínimo legal de{" "}
                            {f.base_essalud ? formatSoles(f.base_essalud) : "la RMV"}, que no
                            baja aunque el mes tenga menos horas
                          </>
                        )}
                      </span>
                    </td>
                    <td className="py-2 text-right align-top">{formatSoles(aporteEssalud)}</td>
                  </tr>
                )}
                {f.provision_gratificacion > 0 && (
                  <tr className="border-t border-sand">
                    <td className="py-2">
                      Gratificación — la parte de este mes
                      <span className="block text-xs text-taupe">
                        se guarda cada mes y se paga completa en julio y diciembre, según ley
                      </span>
                    </td>
                    <td className="py-2 text-right align-top">
                      {formatSoles(f.provision_gratificacion)}
                    </td>
                  </tr>
                )}
                {/* Ley 30334. Va pegada a la gratificación porque sale de ella:
                    es el 9 % que el empleador ya no aporta a EsSalud sobre la
                    gratificación y que, por mandato del art. 3, se le entrega a la
                    persona. En el PLAME es el código 0312, separado del 0406 — y
                    la boleta tiene que decir lo mismo que el PLAME. */}
                {(f.provision_bonif_extraordinaria ?? 0) > 0 && (
                  <tr className="border-t border-sand">
                    <td className="py-2">
                      Bonificación extraordinaria — la parte de este mes
                      <span className="block text-xs text-taupe">
                        9 % de la gratificación, que la Ley 30334 manda entregarte junto con
                        ella
                      </span>
                    </td>
                    <td className="py-2 text-right align-top">
                      {formatSoles(f.provision_bonif_extraordinaria ?? 0)}
                    </td>
                  </tr>
                )}
                {f.provision_cts > 0 && (
                  <tr className="border-t border-sand">
                    <td className="py-2">
                      CTS — la parte de este mes
                      <span className="block text-xs text-taupe">
                        se guarda cada mes y se deposita completa en mayo y noviembre, según ley
                      </span>
                    </td>
                    <td className="py-2 text-right align-top">{formatSoles(f.provision_cts)}</td>
                  </tr>
                )}
                {f.provision_vacaciones > 0 && (
                  <tr className="border-t border-sand">
                    <td className="py-2">
                      Vacaciones — la parte de este mes
                      <span className="block text-xs text-taupe">
                        se guardan cada mes y son 15 días al año, según ley
                      </span>
                    </td>
                    <td className="py-2 text-right align-top">
                      {formatSoles(f.provision_vacaciones)}
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
            {/* Antes decía «los montos acumulados son a la fecha», y no era cierto: estas
                tres cifras son la PARTE DE ESTE MES —(pago base + feriados) × su factor—,
                no el acumulado. Quien comparaba su boleta contra la pantalla de Provisiones
                veía dos números distintos para lo que parecía lo mismo. Corregido el
                2026-08-01, después de que Felipe lo notara en la boleta de Danitza. */}
            <p className="mt-3 text-xs text-taupe">
              Son <strong>las partes de este mes</strong>. Se van sumando mes a mes y se
              pagan completas en las fechas de ley.
            </p>
          </div>
        )}

        {/* ── Aclaración y Deslinde Legal ──────────────────────────────────────
            Reemplaza la nota simple anterior. Decidido con Felipe 2026-07-28.
            Los dos puntos de VALOR (lo que cubre CAYLA, y que grati/CTS/vacaciones
            siguen acumulándose) se conservan: eran una decisión del 2026-07-14 y
            son lo único de este bloque que juega a favor de quien lo lee.
            Las cifras se toman de los datos de la persona, NUNCA se escriben a
            mano: un deslinde que cita un monto que no coincide con el desglose de
            arriba se vuelve prueba en contra. Si un dato falta, el punto se omite. */}
        {/* ── LA VERSIÓN DEL LOCADOR ───────────────────────────────────────────
            El bloque de abajo es un deslinde: existe para acotar lo que la
            empresa NO promete dentro de una relación laboral. Aplicado a quien
            presta un servicio no solo sobra — miente, porque sus cuatro puntos
            hablan de remuneración computable, boleta PLAME y beneficios sociales.

            Este dice lo contrario, y en positivo: qué relación es esta, quién
            organiza el tiempo, cuál es el documento oficial, y —recién al final,
            como consecuencia y no como recorte— por qué no hay grati, CTS,
            vacaciones ni feriados. El orden importa: si la ausencia de beneficios
            va primero, el papel se lee como una lista de lo que se le quita.

            NINGUNA CIFRA. Mismo criterio que el otro bloque: un deslinde que cita
            un monto que no coincide con el recibo de la persona se vuelve prueba
            en contra. El impuesto de cuarta se nombra sin porcentaje a propósito
            —depende de su suspensión de retenciones, que es trámite suyo. */}
        {esLocador ? (
          <div className="mb-6 rounded-lg bg-sand/40 p-4 text-sm print:mb-3 print:break-inside-avoid print:p-3">
            <p className="mb-3 font-medium">Sobre este documento</p>
            <ul className="list-disc space-y-2 pl-5">
              <li>
                <span className="font-medium">Es una locación de servicios.</span> Lo acordado
                entre CAYLA y quien presta el servicio es un contrato de locación de servicios
                (Código Civil, artículos 1764 y siguientes). No es un contrato de trabajo.
              </li>
              <li>
                <span className="font-medium">Tú organizas tu propio tiempo.</span> No estás
                sujeto a horario, jornada ni fiscalización de asistencia. Las horas de esta hoja
                son las que tú mismo registraste, y sirven para calcular tus honorarios: no son
                un control de asistencia.
              </li>
              <li>
                <span className="font-medium">El documento oficial es tu recibo por honorarios.</span>{" "}
                Esta hoja es un detalle interno de CAYLA para que veas cómo salió el importe. Lo
                que sustenta la operación ante SUNAT es el recibo por honorarios electrónico que
                emites tú.
              </li>
              <li>
                <span className="font-medium">
                  Por eso aquí no hay gratificación, CTS, vacaciones ni feriados.
                </span>{" "}
                Son derechos propios de un contrato de trabajo. No se están dejando de pagar: no
                corresponden a esta relación.
              </li>
              <li>
                <span className="font-medium">Impuesto a la renta:</span> el de cuarta categoría
                es de cargo del prestador. CAYLA retiene únicamente cuando la ley lo exige.
              </li>
            </ul>
          </div>
        ) : (
        <div className="mb-6 rounded-lg bg-sand/40 p-4 text-sm print:mb-3 print:break-inside-avoid print:p-3">
          <p className="mb-3 font-medium">Aclaración y Deslinde Legal de Remuneración</p>
          <ul className="mb-3 list-disc space-y-2 pl-5">
            {/* SIN CIFRA, y remitiendo al PLAME. Decidido con Felipe el 2026-07-28.
                Antes afirmaba «el único sueldo ordinario fijo asciende a S/ X».
                Se quitó el monto porque esta hoja no puede garantizar que coincida
                con el documento oficial de cada persona, y una cifra que se
                contradiga con el PLAME convierte esta boleta en prueba en contra.
                El PLAME es la autoridad y aquí se dice así. */}
            <li>
              <span className="font-medium">Remuneración básica:</span> el sueldo ordinario fijo y
              garantizado es el que figura como remuneración básica en tu boleta oficial PLAME. Los
              importes de esta hoja son un desglose interno de cómo se compone tu pago del mes.
            </li>
            {/* ANTES ESTE PUNTO ERA FALSO, y por eso se reescribió: decía que
                «los montos adicionales» eran incentivos variables no computables,
                y entre esos adicionales están la asignación familiar, los feriados
                y la gratificación — que son DERECHOS DE LEY, no incentivos, y sí
                son computables. Un documento firmado por la empresa que
                mischaracteriza lo obligatorio es exactamente lo que se usa en
                contra. Ahora se nombra qué es variable y se dice que el resto no.
                Que la empresa demuestre saber distinguir es lo que hace creíble
                el amparo del Art. 19; meterlo todo en el mismo saco lo destruye. */}
            <li>
              <span className="font-medium">Carácter variable de algunos conceptos:</span> el{" "}
              <span className="font-medium">Rendimiento Extraordinario</span> y el{" "}
              <span className="font-medium">Incentivo Variable por Metas</span> son variables, se
              evalúan mes a mes, no tienen carácter permanente y no forman parte de la remuneración
              computable (Art. 19 del D.S. 001-97-TR).
            </li>
            <li>
              <span className="font-medium">Lo demás son derechos de ley:</span> los feriados, la
              asignación familiar, la gratificación, la CTS y las vacaciones te corresponden por
              ley y se pagan como tales. No son incentivos ni dependen de tu rendimiento.
            </li>
            <li>
              <span className="font-medium">Efecto fiscal y laboral:</span> la boleta oficial para
              efectos de SUNAT, SUNAFIL, aportes de ley y beneficios sociales es exclusivamente la
              emitida en el sistema PLAME. Esta es una boleta interna de CAYLA.
            </li>
          </ul>
          {/* La asignación familiar SALE de esta lista. Aquí van los APORTES que
              CAYLA asume para que no se le descuenten a la persona; la asignación
              familiar es lo contrario — es plata que se le SUMA, y aparece como
              tal en el desglose de arriba. Decir «no se descuenta de tu sueldo»
              insinuaba que podría descontarse, que no tiene sentido. Ya figura
              donde le toca: en el punto de los derechos de ley. */}
          <p className="mb-1">
            <span className="text-verde">✓</span>{" "}
            <span className="font-medium">EsSalud y AFP:</span> los cubre CAYLA, no se descuentan de
            tu sueldo.
          </p>
          <p>
            <span className="text-verde">✓</span>{" "}
            <span className="font-medium">Gratificación, CTS y vacaciones:</span> se siguen acumulando
            y se pagan en sus fechas. Si este mes ya te tocó alguna, la verás arriba en el desglose.
            {/* Antes decía «la verás arriba como bono». Dejó de ser cierto el
                2026-07-28, cuando la gratificación pasó a llamarse por su nombre
                y se le quitó el prefijo «Bono —»: ya no aparece como bono en
                ninguna parte, así que el pie contradecía a la tabla. */}
          </p>
        </div>
        )}

        {/* «Consulta con tu líder de equipo» NO puede ir en el papel de un
            locador: es la frase más subordinante del documento — dice, por
            escrito y firmado por la empresa, que esa persona tiene a alguien
            arriba a quien reportarle. Y además es falsa: no lo tiene. Se le
            escribe a la administración, que es con quien trata de verdad. */}
        <p className="text-xs text-taupe">
          {esLocador
            ? "¿Algo no cuadra? Avísanos antes de emitir tu recibo."
            : "¿Algo no cuadra o tienes dudas? Consulta con tu líder de equipo."}{" "}
          Generada el {fechaHoyLima()}.
        </p>
      </div>
    </main>
  );
}

export default function BoletaPage() {
  return (
    <Suspense fallback={<main className="p-6"><Cargando /></main>}>
      <BoletaContenido />
    </Suspense>
  );
}

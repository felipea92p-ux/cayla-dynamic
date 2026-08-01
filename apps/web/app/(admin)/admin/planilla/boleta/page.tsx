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

// Boleta INTERNA de CAYLA: resumen para que la persona vea cómo se calculó su
// sueldo del mes, e imprimirlo/entregarlo (Ctrl+P → Guardar como PDF). NO es
// la boleta oficial PLAME — ver el texto de valor al pie, decidido con Felipe
// el 2026-07-14 (formato lista, sin montos porque AFP varía por fondo).

function fechaHoyLima(): string {
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: "America/Lima", day: "numeric", month: "long", year: "numeric",
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
  const puedeVer = rol === "admin" || rol === "lider_do";

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
      ? `${filaTitulo.nombre} — Boleta interna ${MESES_LARGO[proy.mes_etiqueta - 1]} ${proy.anio_etiqueta}`
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
  const pension = f.descuento_afp ?? 0;
  const aporteEssalud = f.aporte_essalud ?? 0;

  // Subtotal ganado: todo lo que suma, antes de restar. Solo se muestra si hay
  // algo que restar — sin eso sería idéntico al total y solo agregaría ruido.
  // Decidido con Felipe el 2026-07-28: cuando el descuento es grande (un adelanto,
  // por ejemplo), sin esta línea la persona ve solo el neto y no reconoce que sí
  // ganó su sueldo completo. Suma los mismos campos ya redondeados que usa el
  // 'total' de fn_proyeccion_periodo, así el desglose cuadra al céntimo.
  const subtotalGanado =
    f.pago_base +
    f.monto_feriados +
    f.asignacion_familiar +
    f.monto_plus +
    movilidad +
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
          ? { texto: "Provisional — el mes aún no cierra", alerta: true }
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
            <p className="etiqueta text-taupe">Boleta interna de pago</p>
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
          <p className="text-sm text-taupe">
            {f.sede} · {f.rango ? (RANGO_LABEL[f.rango] ?? f.rango) : "sin rango"}
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
                <dt className="font-medium">Remuneración Básica Legal (mes completo)</dt>
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
                Remuneración Básica proporcional ({fmtHorasHumano(f.horas_mes)})
                {baseLegal !== null && (
                  <span className="block text-xs text-taupe">
                    por tus horas del periodo · el mes completo son{" "}
                    {formatSoles(baseLegal)}
                  </span>
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
            {descuentos.map((m) => (
              <tr key={m.id} className="border-t border-sand">
                <td className="py-2 text-rojo">Descuento — {m.concepto}</td>
                <td className="py-2 text-right text-rojo">−{formatSoles(m.monto)}</td>
              </tr>
            ))}
            <tr className="border-t-2 border-tinta">
              <td className="py-3 font-serif text-lg">Total a recibir este mes</td>
              <td className="py-3 text-right font-serif text-lg font-bold">{formatSoles(f.total)}</td>
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
        {(aporteEssalud > 0 || f.provision_total > 0) && (
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

        <p className="text-xs text-taupe">
          ¿Algo no cuadra o tienes dudas? Consulta con tu líder de equipo. Generada el {fechaHoyLima()}.
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

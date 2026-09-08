import { RANGO_LABEL, formatSoles } from "@/lib/rangos";
import { Marca } from "@/components/marca";
import {
  MESES_LARGO,
  fechaCorta,
  fmtHoras,
  type Fila,
  type Proyeccion,
} from "@/app/(admin)/admin/planilla/page";
import {
  EMPRESA,
  TZ_LIMA,
  esPrestadorDeServicios,
  nombreDelDocumentoDePago,
  nombreRegimenPension,
} from "@cayla-dynamic/shared";

// El PAPEL de la boleta — la parte que dos pantallas tienen que pintar
// exactamente igual: la boleta interna de Planilla (admin) y el autoservicio
// de "Lo mío" (self-service, 0339). Vive acá, fuera de las dos, por la misma
// razón que Documento vive en components/ y no dentro de Normas: si las dos
// pintaran una copia separada, divergirían la primera vez que alguien
// corrigiera un texto legal en una sin acordarse de la otra — y estas
// cláusulas se han corregido muchas veces (grep "CAMBIO" en este archivo, o
// en su historia si ya se movieron).
//
// EXTRAÍDO MECÁNICAMENTE de admin/planilla/boleta/page.tsx (antes de la
// extracción), sin retipear una palabra del texto legal: cortado con `sed -n`
// y verificado con `diff` contra el original — cualquier diferencia que no
// sea la firma de función o el nombre de los props es un error de esta
// extracción, no una mejora.

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

export interface BoletaHojaProps {
  f: Fila;
  proy: Pick<Proyeccion, "estado" | "pagado_at" | "simulacion" | "fecha_ini" | "fecha_fin" | "anio_etiqueta" | "mes_etiqueta" | "base_horas">;
  baseLegal: number | null;
  documento: string | null;
  fechaIngreso: string | null;
}

export function BoletaHoja({ f, proy, baseLegal, documento, fechaIngreso }: BoletaHojaProps) {
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
  //
  // CAMBIO 0322 (completado): un practicante tiene `en_planilla=false`, así que
  // `esPrestadorDeServicios` también lo marcaría `true` — pero un convenio de
  // modalidad formativa (Ley 28518) no es una locación de servicios, y llamarlo
  // así en un papel que la persona se lleva es tan falso como llamarlo
  // "trabajador". Se excluye acá con `!esPracticante`, y tiene su PROPIA rama de
  // copy más abajo (label del pago, deslinde legal, bloque de EsSalud) en vez de
  // heredar la de un locador.
  const esPracticante = f.tipo_vinculo === "practicante";
  const esLocador = esPrestadorDeServicios(f.en_planilla) && !esPracticante;

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
  // El desglose 25 %/35 % (0349), a pedido del contador — sostiene los
  // códigos 0105/0106 de la PLAME. `undefined` y no `?? 0` a propósito: una
  // boleta de un periodo ya congelado antes de la 0349 no trae estas claves,
  // y ahí hay que caer al texto genérico de siempre, no imprimir "25 %: S/0".
  const sobretiempo25 = f.monto_sobretiempo_25;
  const sobretiempo35 = f.monto_sobretiempo_35;
  const tieneDesgloseSobretiempo =
    sobretiempo25 !== undefined && sobretiempo35 !== undefined;
  // ⇩ CAMBIO 0280 ⇩ El recargo por trabajar el día de descanso semanal (art. 3
  // del D. Leg. 713). Va aquí y no dentro del sobretiempo aunque los dos se
  // midan sobre la misma racha de días: aquél paga por pasar de 48 horas, este
  // por no haber descansado. Se pueden dar juntos o por separado.
  //
  // `?? 0` por lo mismo que arriba: una base sin la 0280 pegada no dibuja la
  // fila, en vez de escribir «S/ NaN».
  const descansoSemanal = f.monto_descanso_semanal ?? 0;
  const diasDescansoSemanal =
    f.descanso_semanal_desde && f.descanso_semanal_hasta
      ? f.descanso_semanal_desde === f.descanso_semanal_hasta
        ? fechaCorta(f.descanso_semanal_desde)
        : `${fechaCorta(f.descanso_semanal_desde)} y ${fechaCorta(f.descanso_semanal_hasta)}`
      : null;
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
    descansoSemanal +
    f.asignacion_familiar +
    f.monto_plus +
    movilidad +
    educacion +
    bonos.reduce((suma, m) => suma + m.monto, 0);

  // La retención de renta de cuarta (0245). Mismo criterio que la pensión y el
  // sobretiempo: entra en el 'total' del SQL, así que si la boleta no la imprime
  // el total deja de cuadrar con sus líneas — y este es el peor sitio donde eso
  // podría pasar, porque un locador CONTRASTA esta hoja contra su recibo.
  // ¿Su pago depende de las horas que registre? (0250). `?? false` para que una
  // base sin la 0250 pegada se comporte exactamente como antes — etiquetando por
  // horas, que es lo que hacía — en vez de afirmar un monto fijo que no sabe.
  const sueldoFijo = f.sueldo_fijo ?? false;

  // ── LA TARIFA POR HORA DE UN LOCADOR SIN MONTO FIJO ─────────────────────────
  // Reintroducido: este bloque existió un rato el 2026-08-08 y se perdió al
  // extraer esta hoja a su propio componente desde una copia que todavía no lo
  // tenía. Sin él, la cabecera de arriba imprimía «Honorarios pactados (mes
  // completo) — S/ X» a un locador que cobra por hora — un monto mensual fijo,
  // que es justo el indicio de laboralidad que el resto de la hoja evita. Y la
  // hoja se contradecía a sí misma: la fila de detalle, más abajo, ya decía bien
  // «Honorarios por las horas prestadas».
  //
  // SALE DE `f.salario_ref`, NO DE `baseLegal` (que es `sueldo_base_legal`). Los
  // dos suelen coincidir por diseño (ver `lib/rangos.ts`), pero el pago lo
  // calcula `fn_planilla_calcular` con `salario_ref`. Si algún día difieren,
  // usar el otro daría una tarifa que no reproduce el total de la propia hoja.
  //
  // CUATRO DECIMALES, y no dos: a S/ 8.93 la hora, 27 h 30 min dan S/ 245.58 y
  // la hoja remata en S/ 245.66. Ocho céntimos bastan para que alguien piense
  // que le descontaron algo; con S/ 8.9330 la multiplicación cierra.
  //
  // Solo aplica sin `sueldoFijo`: quien tiene un monto fijo pactado (0250) SÍ
  // tiene un «mes completo» real que mostrar, y esa frase se queda igual.
  const tarifaHora =
    esLocador && !sueldoFijo && f.salario_ref !== null && proy.base_horas > 0
      ? f.salario_ref / proy.base_horas
      : null;
  // ⇩ CAMBIO 0254 ⇩ Los días de descanso médico que asume CAYLA van DENTRO de
  // `pago_base` —igual que los de vacaciones desde la 0177— porque sacarlos a un
  // concepto propio obligaría a tocar la tabla congelada y `chk_foto_cuadra`.
  // Pero dentro no se pueden quedar CALLADOS: la línea de arriba dice «por tus
  // horas del periodo» y traía un importe que incluye días que no trabajó. Medido
  // en producción con un caso real: 25 h 55 min y S/274.27, donde S/121.90 eran
  // cuatro días de baja. Quien lee su boleta no puede cuadrar eso.
  //
  // Así que la fila de básica se queda con lo trabajado y el descanso médico sale
  // aparte. La suma es idéntica al céntimo: solo se reparte en dos líneas.
  //
  // `?? 0` para que una base sin la 0254 pegada se comporte exactamente como
  // antes — sin fila y sin restar nada.
  const descansoMedico = num(f.monto_descanso_medico) ?? 0;
  const diasDescansoMedico = num(f.dias_descanso_medico_pagados) ?? 0;
  const pagoTrabajado = (num(f.pago_base) ?? 0) - descansoMedico;
  const retencion4ta = f.retencion_4ta ?? 0;
  // El importe por el que tiene que emitir el recibo. Es la base, no el total:
  // el total ya lleva la retención descontada. Sin la 0245 pegada la clave no
  // viene y cae al total, que es lo que esta hoja decía antes.
  const importeDelRecibo = f.retencion_4ta_base ?? f.total;

  // La pensión también es una resta, así que también justifica el subtotal.
  const hayRestas = descuentos.length > 0 || pension > 0 || retencion4ta > 0;

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
      <div className="hoja rounded-lg border border-sand p-8 print:rounded-none print:border-0 print:p-0">
        <div className="mb-6 flex items-start justify-between border-b border-sand pb-4 print:mb-4 print:pb-3">
          {/* ── QUIÉN EMITE ESTE PAPEL (auditoría del 2026-08-19) ──────────────
              La cabecera imprimía el lockup de producto «Dynamic / CAYLA» y
              nada más: ni razón social ni RUC. Un documento de pago que no
              identifica al empleador no acredita nada por sí solo — y para un
              locador pesa doble, porque su «Detalle de servicios prestados» es
              el único comprobante que tiene de para quién trabajó.
              El RUC sale de `packages/shared/src/empresa.ts`, que existe para
              que no haya una novena copia escrita a mano. */}
          <div>
            <Marca tono="tinta" isotipo="rojo" />
            <p className="mt-2 text-xs text-taupe">
              {EMPRESA.nombre} · RUC {EMPRESA.ruc}
            </p>
          </div>
          <div className="text-right">
            <p className="etiqueta text-taupe">{nombreDelDocumentoDePago(f.en_planilla, f.tipo_vinculo)}</p>
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
          {/* A QUIÉN SE LE PAGA. Faltaba el documento de identidad: sin él, dos
              personas con nombres parecidos producen dos papeles indistinguibles
              y ninguno de los dos prueba nada. La fecha de ingreso va al lado
              porque es el dato del que cuelgan la antigüedad y los beneficios, y
              porque es lo primero que se mira en un reclamo. */}
          {(documento || fechaIngreso) && (
            <p className="text-sm text-taupe">
              {documento ? `Doc. ${documento}` : null}
              {documento && fechaIngreso ? " · " : null}
              {fechaIngreso ? `Ingreso ${fechaCorta(fechaIngreso)}` : null}
            </p>
          )}
          <p className="text-sm text-taupe">
            {/* CAMBIO 0322: la escala de sueldo es de trabajadores, igual que
                para un locador (ver el comentario de arriba, 0182) — un
                practicante tampoco ocupa un peldaño de esa escala. */}
            {esLocador || esPracticante
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
          {/* A UN LOCADOR SIN MONTO FIJO SE LE DICE SU TARIFA, NO UN SUELDO
              MENSUAL. Ver el cálculo y el porqué de los cuatro decimales donde
              se define `tarifaHora`, más arriba. */}
          {tarifaHora !== null ? (
            <dl className="mt-3 space-y-1 text-sm">
              <div className="flex justify-between gap-4">
                <dt className="font-medium">Tarifa por hora</dt>
                <dd className="font-medium">S/ {tarifaHora.toFixed(4)}</dd>
              </div>
            </dl>
          ) : (
            baseLegal !== null && (
              <dl className="mt-3 space-y-1 text-sm">
                {/* «(mes completo)» no es decoración: sin eso, esta cifra y la fila
                    del desglose se llamaban IGUAL y mostraban montos distintos
                    (1,130.00 aquí y 947.41 abajo). Quien lo leyera rápido pensaba
                    que había un error. Ahora una dice «mes completo» y la otra
                    «proporcional», y se entienden sin explicación. */}
                <div className="flex justify-between gap-4">
                  <dt className="font-medium">
                    {/* CAMBIO 0322: ni "honorarios" (locador) ni "remuneración"
                        (trabajador) — un practicante cobra una SUBVENCIÓN
                        económica (art. 45, Ley 28518), que es su propio término
                        legal y no un sinónimo de los otros dos. */}
                    {esPracticante
                      ? "Subvención pactada (mes completo)"
                      : esLocador
                        ? "Honorarios pactados (mes completo)"
                        : "Remuneración Básica Legal (mes completo)"}
                  </dt>
                  <dd className="font-medium">{formatSoles(baseLegal)}</dd>
                </div>
              </dl>
            )
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
                {/* ⇩ CAMBIO 0250 ⇩ Un locador con monto fijo NO cobra por horas,
                    y decirle que sí describe su contrato al revés en un papel
                    que se le entrega. Con cero horas marcadas quedaba además
                    «(0 h) …… S/ 652.17», que se lee como un error de cálculo
                    aunque el número esté bien. */}
                {/* CAMBIO 0322: la misma razón que la fila de arriba —
                    "subvención", no "honorarios" ni "remuneración". */}
                {esPracticante
                  ? `Subvención por las horas del periodo (${fmtHorasHumano(f.horas_mes)})`
                  : esLocador
                    ? sueldoFijo
                      ? "Honorarios del mes (monto fijo pactado)"
                      : `Honorarios por las horas prestadas (${fmtHorasHumano(f.horas_mes)})`
                    : `Remuneración Básica proporcional (${fmtHorasHumano(f.horas_mes)})`}
                {/* La sublínea de un locador NO compara contra «el mes completo».
                    Esa comparación es la que insinúa un sueldo mensual del que
                    este mes se pagó una parte, y quien factura por hora no tiene
                    tal cosa: tiene las horas que prestó. */}
                {esLocador ? (
                  <span className="block text-xs text-taupe">
                    {sueldoFijo
                      ? "Lo pactado por el mes — no depende de las horas que registres"
                      : "Horas prestadas en el periodo"}
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
              <td className="py-2 text-right align-top">{formatSoles(pagoTrabajado)}</td>
            </tr>

            {/* ⇩ CAMBIO 0254 ⇩ El descanso médico, con su nombre.
                No es un concepto nuevo del cálculo: es la parte de `pago_base`
                que no se trabajó, sacada a su propia línea para que la de arriba
                deje de prometer «por tus horas» sobre un importe que incluye
                días de baja. La suma de las dos es exactamente `pago_base`. */}
            {descansoMedico > 0 && (
              <tr className="border-t border-sand">
                <td className="py-2">
                  Descanso médico
                  <span className="block text-xs text-taupe">
                    {diasDescansoMedico}{" "}
                    {diasDescansoMedico === 1 ? "día" : "días"} con certificado ·
                    CAYLA asume los primeros 20 días de incapacidad del año
                  </span>
                </td>
                <td className="py-2 text-right align-top">
                  {formatSoles(descansoMedico)}
                </td>
              </tr>
            )}
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
                SEMANALES, así que sin la fecha nadie puede rehacer la cuenta.
                Desde la 0349, si la fila trae el desglose, se ve el 25 % y el 35 %
                aparte —lo pidió el contador, para conciliar contra la PLAME—; si
                no (boleta de un periodo congelado antes de esa migración), se ve
                el texto genérico de siempre. */}
            {sobretiempo > 0 && (
              <tr className="border-t border-sand">
                <td className="py-2">
                  Sobretiempo
                  <span className="block text-xs text-taupe">
                    {fmtHorasHumano(f.horas_sobretiempo ?? 0)} por encima de las 48 de la
                    semana{diasSobretiempo && ` · ${diasSobretiempo}`}; las horas mismas ya
                    están en el pago base
                  </span>
                  {tieneDesgloseSobretiempo ? (
                    <span className="block text-xs text-taupe">
                      Recargo 25 % ({fmtHorasHumano(f.horas_sobretiempo_25 ?? 0)}):{" "}
                      {formatSoles(sobretiempo25 ?? 0)} · Recargo 35 % (
                      {fmtHorasHumano(f.horas_sobretiempo_35 ?? 0)}): {formatSoles(sobretiempo35 ?? 0)}
                    </span>
                  ) : (
                    <span className="block text-xs text-taupe">
                      se paga el recargo (25 % las 2 primeras horas de cada día, 35 % las demás)
                    </span>
                  )}
                </td>
                <td className="py-2 text-right align-top">{formatSoles(sobretiempo)}</td>
              </tr>
            )}
            {/* Descanso semanal trabajado (0280). Se dice QUÉ DÍA, y no es
                cosmético: la persona tiene que poder mirar su calendario y
                reconocer que ese día no descansó. Un recargo del 100 % sin
                fecha es un número que nadie puede comprobar.
                Y se imprime el RECARGO, igual que el sobretiempo: las horas de
                ese día ya están cobradas dentro del pago base. */}
            {descansoSemanal > 0 && (
              <tr className="border-t border-sand">
                <td className="py-2">
                  Descanso semanal trabajado
                  <span className="block text-xs text-taupe">
                    {(f.descanso_semanal_dias ?? 0) === 1
                      ? "trabajaste 7 días seguidos sin descansar"
                      : `${f.descanso_semanal_dias} veces trabajaste 7 días seguidos sin descansar`}
                    {diasDescansoSemanal && ` · ${diasDescansoSemanal}`} · la ley manda pagar
                    ese día con un recargo del 100 % (art. 3 del D. Leg. 713); las horas
                    mismas ya están en el pago base
                  </span>
                </td>
                <td className="py-2 text-right align-top">{formatSoles(descansoSemanal)}</td>
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
                  {/* CAMBIO 0328 · el nombre se pide a `shared`. Armarlo aquí con
                      charAt(0).toUpperCase() alcanzaba mientras hubo un solo
                      código por AFP; con `integra_mixta` imprimía «AFP
                      Integra_mixta» en el documento que la persona firma. Y el
                      esquema de comisión importa justo en esta línea: es lo que
                      permite cotejar la boleta contra el estado de cuenta de la
                      AFP, que es donde el error de la 0114 se habría visto un
                      año antes. */}
                  {nombreRegimenPension(f.regimen_pension) ?? "Pensión"}
                  {f.tasa_afp ? ` (${(f.tasa_afp * 100).toFixed(2)}%)` : ""}
                  {/* CAMBIO del 2026-08-19 · antes decía «va a tu fondo de
                      pensión». De ese porcentaje solo el 10 % entra a la cuenta
                      individual: el resto es comisión de la AFP y prima del
                      seguro de invalidez y sobrevivencia. De cada S/100
                      retenidos a alguien en AFP, unos S/77 van a su fondo. Decir
                      que va entero al fondo no era un matiz: era el número con
                      el que la persona calcula lo que tendrá al jubilarse.
                      En ONP no hay cuenta individual —es un fondo común—, así
                      que la frase tampoco valía ahí. */}
                  <span className="block text-xs text-rojo/70">
                    {f.regimen_pension === "onp"
                      ? "se remite a la ONP — no se queda en CAYLA"
                      : "se remite a tu AFP — no se queda en CAYLA. Incluye tu aporte al fondo, la comisión y la prima del seguro"}
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
            {/* LA RETENCIÓN DE CUARTA CATEGORÍA (0245).
                Se dice que NO se queda en CAYLA por lo mismo que la pensión: es
                lo primero que se piensa al ver una resta, y acá además es falso
                de una forma que importa — ese dinero se declara a nombre de la
                persona y se le acredita contra su impuesto del año. Quien no lo
                sabe cree que le pagaron menos.

                Y se imprime el porcentaje, no solo el monto, para que se pueda
                verificar contra el recibo sin hacer cuentas. */}
            {retencion4ta > 0 && (
              <tr className="border-t border-sand">
                <td className="py-2 text-rojo">
                  Retención — Impuesto a la Renta de 4ta categoría
                  <span className="block text-xs text-rojo/70">
                    8 % de {formatSoles(importeDelRecibo)} — CAYLA lo paga a SUNAT a tu nombre,
                    no se queda acá
                  </span>
                </td>
                <td className="py-2 text-right align-top text-rojo">−{formatSoles(retencion4ta)}</td>
              </tr>
            )}
            {/* El cierre de un locador no es «lo que vas a recibir»: es la cifra
                por la que tiene que emitir su recibo. Sin decirlo, esta hoja
                parecía el documento del pago — y el documento del pago es el
                recibo por honorarios que emite él, no este papel. */}
            {/* CON RETENCIÓN, ESTE NÚMERO DEJA DE SER EL DEL RECIBO.
                La hoja decía «emite tu recibo por honorarios por este importe»
                apuntando al total, y eso era cierto mientras no se retenía nada.
                Con la 0245 el total es el NETO —lo que se transfiere— y el
                recibo se emite por el BRUTO. Seguir apuntando al total haría que
                el locador facturara de menos justo por el monto retenido, y la
                retención declarada no cuadraría con ningún recibo. */}
            <tr className="border-t-2 border-tinta">
              <td className="py-3 font-serif text-lg">
                {esLocador && retencion4ta === 0 ? "Total del periodo" : "Total a recibir este mes"}
                {esLocador && (
                  <span className="block font-sans text-xs font-normal text-taupe">
                    {retencion4ta > 0
                      ? `emite tu recibo por honorarios por ${formatSoles(importeDelRecibo)} — con la retención marcada, te queda esto`
                      : "emite tu recibo por honorarios por este importe"}
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
        ) : esPracticante ? (
          // ── LA VERSIÓN DEL PRACTICANTE (0322) ──────────────────────────────
          // Ni la del locador (le sobra Código Civil 1764, "tú organizas tu
          // tiempo" es FALSO —el convenio SÍ fija una jornada— y "emites tu
          // recibo" también, porque un practicante no emite nada) ni la del
          // trabajador (le sobra PLAME como boleta oficial y "remuneración
          // computable": una subvención no lo es). Cinco puntos, con la misma
          // regla de las otras dos versiones: sin cifras, y los derechos que
          // el sistema todavía no calcula solo se dicen igual — omitirlos
          // sería negarle a la persona un derecho real por una limitación de
          // esta pantalla, y eso pesa distinto que un adorno de más.
          <div className="mb-6 rounded-lg bg-sand/40 p-4 text-sm print:mb-3 print:break-inside-avoid print:p-3">
            <p className="mb-3 font-medium">Sobre este documento</p>
            <ul className="list-disc space-y-2 pl-5">
              <li>
                <span className="font-medium">Es un convenio de modalidad formativa.</span> Lo
                acordado entre CAYLA y quien hace sus prácticas se rige por la Ley N.° 28518,
                Ley sobre Modalidades Formativas Laborales. No es un contrato de trabajo.
              </li>
              <li>
                <span className="font-medium">Tu jornada la fija el convenio</span> — hasta 30
                horas semanales si tus prácticas son preprofesionales, hasta 48 si son
                profesionales (art. 44). Que alguien supervise tus prácticas es parte de la
                modalidad formativa, no un indicio de que esto sea otra cosa.
              </li>
              <li>
                <span className="font-medium">Este documento es tu constancia de subvención.</span>{" "}
                No emites ningún recibo: CAYLA te declara ante SUNAT en su propio registro de
                personal en formación, distinto al de un trabajador o un locador.
              </li>
              <li>
                <span className="font-medium">
                  Por eso aquí no hay gratificación, CTS, vacaciones ni aporte a tu pensión.
                </span>{" "}
                Son derechos propios de un contrato de trabajo (art. 47). Si tus prácticas
                superan los 12 meses continuos sí te corresponde un descanso de 15 días, y media
                subvención adicional por cada 6 meses continuos — son derechos tuyos aunque este
                sistema todavía no los calcule solo: pídelos si se cumplen.
              </li>
              <li>
                <span className="font-medium">Tu subvención no genera retención de impuesto a la renta.</span>{" "}
                No es remuneración de cuarta ni de quinta categoría (art. 47).
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
          {/* ── LA CONTRADICCIÓN QUE ESTO QUITA (auditoría del 2026-08-19) ──────
              Esta línea decía «EsSalud y AFP: los cubre CAYLA, no se descuentan
              de tu sueldo» en la MISMA hoja que imprime el descuento de pensión
              con su monto en rojo, unas líneas más arriba. Dos afirmaciones
              opuestas sobre la misma plata, en el documento que la persona se
              lleva a casa.

              Y las dos mitades no eran igual de falsas: EsSalud SÍ lo paga
              CAYLA —es aporte del empleador, 9 %, y no toca el sueldo—, pero la
              pensión SÍ se le descuenta a la persona, entre 12.84 % y 13.06 %
              según la AFP. Juntarlas en una frase hacía que la parte cierta
              avalara la falsa.

              Se separan, y la de pensión se dice como es: no se queda en CAYLA,
              pero tampoco va entera a su fondo. */}
          <p className="mb-1">
            <span className="text-verde">✓</span>{" "}
            <span className="font-medium">EsSalud:</span> lo paga CAYLA aparte de tu sueldo — son 9 %
            sobre tu remuneración y no se te descuentan.
          </p>
          {pension > 0 && (
            <p className="mb-1">
              <span className="text-verde">✓</span>{" "}
              <span className="font-medium">Pensión:</span> esto sí sale de tu sueldo, y lo verás
              arriba en rojo. No se queda en CAYLA: se remite al sistema de pensiones. La mayor parte
              va a tu cuenta individual; el resto es la comisión de la administradora y la prima del
              seguro.
            </p>
          )}
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
  );
}

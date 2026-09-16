import type { ReactNode } from "react";
import { formatSoles } from "@/lib/rangos";
import { cx } from "@/components/ui/cx";
import { Insignia } from "@/components/ui/insignia";
import { Estados } from "./TablaProvisiones";
import {
  ETIQUETA_ESTADO_VENTANA,
  ETIQUETA_ORIGEN,
  bonificacionDe,
  devengadoVentana,
  esPracticante,
  estadoVacaciones,
  estadoVentana,
  fechaCorta,
  gratiConBonificacion,
  montoProximo,
  pagadoVentana,
  pagosDe,
  proximoDesembolso,
  subvencionDe,
  ventanasDe,
  type DesembolsoLibro,
  type EstadoVentana,
  type ProvData,
  type ProvPersona,
  type Subvenciones,
  type Ventana,
  type VentanaClave,
  type VentanaLibro,
} from "@/lib/admin/provisiones";

// El detalle de una persona: qué ya se pagó, qué se está acumulando, qué falta
// y cuándo toca. Cada ventana separa Devengado / Pagado / Saldo en su propia
// casilla; antes las tres cosas iban en una sola cadena («pagado 15/07 ·
// S/332.44» debajo de un saldo) que había que descifrar.
//
// Solo muestra lo que la base respalda: «Devengado» se deduce sin rehacer nada
// (la base arma cada celda como devengado − cobrado), y la fecha y la vía de
// cada pago salen del libro de desembolsos, leído aparte.

type Libro = DesembolsoLibro[] | null | undefined;

const VARIANTE: Record<EstadoVentana, "advertencia" | "informativo" | "positivo" | "neutral"> = {
  no_aplica: "neutral",
  pagado_de_mas: "informativo",
  vencido: "advertencia",
  pago_parcial: "advertencia",
  pagado: "positivo",
  acumulando: "neutral",
  sin_monto: "neutral",
};

const pct = (x: number) => `${(x * 100).toLocaleString("es-PE", { maximumFractionDigits: 2 })} %`;

export function DetallePersona({
  data,
  persona: p,
  libro,
  subvenciones,
}: {
  data: ProvData;
  persona: ProvPersona;
  libro: Libro;
  /** Lo que devenga una practicante (0467). Viene de otra función. */
  subvenciones: Subvenciones;
}) {
  const anio = Number(data.as_of.slice(0, 4));
  const vinculo = esPracticante(p) ? "Practicante" : "Planilla";

  const cabecera = (
    <div className="grid gap-2">
      <p className="text-sm text-taupe">
        {p.sede} · {vinculo} · ingresó el {fechaCorta(p.fecha_ingreso)} · al {fechaCorta(data.as_of)}
      </p>
      <Estados persona={p} data={data} />
      {p.sin_salario_vigente && (
        <p className="text-sm text-rojo-profundo">
          Sin tramo de salario vigente: sus reservas salen cortas o en cero, no porque no le toquen. El salario
          se asigna en Equipo.
        </p>
      )}
      {(p.dias_sin_salario ?? 0) > 0 && (
        <p className="text-sm text-rojo-profundo">
          {p.dias_sin_salario} {p.dias_sin_salario === 1 ? "día" : "días"} del año que reserva sin salario
          cargado: esos días no suman.
        </p>
      )}
    </div>
  );

  if (esPracticante(p)) {
    const s = subvencionDe(subvenciones, p);
    return (
      <div className="grid gap-6 [font-variant-numeric:tabular-nums]">
        {cabecera}
        <p className="text-sm">
          Por la Ley 28518, una modalidad formativa <strong className="font-medium">no genera</strong>{" "}
          gratificación, CTS ni vacaciones de trabajador (art. 47). Sí genera estos dos pagos (art. 42), y por
          eso ocupa una fila como cualquier otra persona.
        </p>

        {s === null ? (
          <p className="text-sm text-rojo-profundo">
            No se pudieron leer sus subvenciones. Los montos de esta persona no se están mostrando; vuelve a
            cargar la pantalla.
          </p>
        ) : (
          <>
            {s.sin_subvencion && (
              <p className="text-sm text-rojo-profundo">
                Sin subvención mensual cargada: sus dos conceptos salen en cero, no porque no le toquen. Se
                asigna en Equipo, igual que un salario.
              </p>
            )}

            <Seccion
              titulo="Media subvención"
              total={s.media_sub_saldo}
              nota="Media subvención mensual por cada 6 meses continuos de convenio (Ley 28518, art. 42)."
            >
              <div className="grid gap-3 rounded-control border border-sand p-3">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <h4 className="font-medium">
                    Semestre en curso{" "}
                    <span className="font-normal text-taupe">
                      · {fechaCorta(s.semestre_desde)} → {fechaCorta(s.semestre_hasta)}
                    </span>
                  </h4>
                  <Insignia variante="neutral" atenuada>
                    {s.semestres_cumplidos === 0
                      ? "primer semestre"
                      : `${s.semestres_cumplidos} ${s.semestres_cumplidos === 1 ? "hito cumplido" : "hitos cumplidos"}`}
                  </Insignia>
                </div>
                <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm sm:grid-cols-3">
                  <Dato etiqueta="Subvención mensual">
                    {s.subvencion_mensual === null ? "—" : formatSoles(s.subvencion_mensual)}
                  </Dato>
                  <Dato etiqueta="Devengado">{formatSoles(s.media_sub_devengado)}</Dato>
                  <Dato etiqueta="Pagado">
                    <Pagos p={p} ventana="subvencion_semestral" anio={anio} libro={libro} monto={s.media_sub_pagado ?? 0} />
                  </Dato>
                  <Dato etiqueta="Saldo" className={cx("font-semibold", s.media_sub_saldo < 0 && "text-pizarra")}>
                    {formatSoles(s.media_sub_saldo)}
                  </Dato>
                  <Dato etiqueta="Próximo hito">{fechaCorta(s.proximo_hito)}</Dato>
                </dl>
              </div>
            </Seccion>

            <Seccion
              titulo="Descanso de 15 días"
              total={s.descanso_saldo}
              nota="15 días subvencionados al cumplir 12 meses continuos. Se pagan aunque el convenio termine sin gozarlos."
            >
              <div className="grid gap-3 rounded-control border border-sand p-3">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <h4 className="font-medium">
                    Cumple el año el{" "}
                    <span className="font-normal text-taupe">{fechaCorta(s.descanso_cumple)}</span>
                  </h4>
                  <Insignia variante={s.descanso_ganado ? "positivo" : "neutral"} atenuada={!s.descanso_ganado}>
                    {s.descanso_ganado ? "Ganado" : "Acumulando"}
                  </Insignia>
                </div>
                <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm sm:grid-cols-3">
                  <Dato etiqueta="Devengado">{formatSoles(s.descanso_devengado)}</Dato>
                  <Dato etiqueta="Pagado">
                    <Pagos p={p} ventana="descanso_practicante" anio={anio} libro={libro} monto={s.descanso_pagado ?? 0} />
                  </Dato>
                  <Dato etiqueta="Saldo" className={cx("font-semibold", s.descanso_saldo < 0 && "text-pizarra")}>
                    {formatSoles(s.descanso_saldo)}
                  </Dato>
                </dl>
                {!s.descanso_ganado && (
                  <p className="text-xs text-taupe">
                    Se reserva mes a mes para que el día 365 el dinero ya esté guardado. Si el convenio termina
                    antes de los 12 meses, este saldo no se paga.
                  </p>
                )}
              </div>
            </Seccion>

            <section className="grid gap-2 border-t border-sand pt-4">
              <div className="flex items-baseline justify-between gap-3">
                <span className="font-medium">Saldo total</span>
                <span className="font-serif text-2xl">{formatSoles(s.total_saldo)}</span>
              </div>
              <p className="text-sm text-taupe">
                No entra en el «Saldo total» de gratificación, CTS y vacaciones del resto del equipo: son
                conceptos distintos, de otra ley y con otra fecha de pago.
              </p>
            </section>
          </>
        )}
      </div>
    );
  }

  const ventanas = ventanasDe(data);
  const ventana = (c: VentanaClave) => ventanas.find((v) => v.clave === c)!;
  const prox = proximoDesembolso(data);
  const mp = montoProximo(p, data);

  return (
    <div className="grid gap-7 [font-variant-numeric:tabular-nums]">
      {cabecera}

      <Seccion titulo="Gratificación" total={gratiConBonificacion(p)} nota="Incluye el 9 % de cada ventana.">
        <BloqueVentana p={p} v={ventana("grati_s1")} data={data} libro={libro} anio={anio} />
        <BloqueVentana p={p} v={ventana("grati_s2")} data={data} libro={libro} anio={anio} />
      </Seccion>

      <Seccion titulo="Bonificación extraordinaria" total={p.be_total} nota="Ya está sumada en la gratificación de arriba.">
        <p className="text-sm text-taupe">
          El {pct(p.tasa_be)} de la gratificación (Ley 30334): lo que iría a EsSalud se le paga a la persona, el
          mismo día que la gratificación y en movimiento propio.
        </p>
        <dl className="grid grid-cols-2 gap-x-4 text-sm">
          <Dato etiqueta="Pendiente de julio">{formatSoles(p.be_s1 ?? 0)}</Dato>
          <Dato etiqueta="Pendiente de diciembre">{formatSoles(p.be_s2 ?? 0)}</Dato>
        </dl>
      </Seccion>

      <Seccion titulo="CTS" total={p.cts_total} nota="Se deposita en la cuenta CTS del banco, no en efectivo.">
        <BloqueVentana p={p} v={ventana("cts_may")} data={data} libro={libro} anio={anio} />
        <BloqueVentana p={p} v={ventana("cts_nov")} data={data} libro={libro} anio={anio} />
      </Seccion>

      <Seccion titulo="Vacaciones" total={p.vac}>
        <BloqueVacaciones p={p} libro={libro} anio={anio} />
      </Seccion>

      <section className="grid gap-2 border-t border-sand pt-4">
        <div className="flex items-baseline justify-between gap-3">
          <span className="font-medium">Saldo total</span>
          <span className="font-serif text-2xl">{formatSoles(p.gran_total)}</span>
        </div>
        {prox && (
          <p className="text-sm text-taupe">
            Próximo desembolso: {prox.beneficio} el {fechaCorta(prox.fecha)}
            {mp !== null ? ` · ${formatSoles(mp)} acumulado a hoy` : " · el monto aparece el 1 de enero"}.
          </p>
        )}
        {libro === null && (
          <p className="text-xs text-rojo-profundo">
            No se pudo leer el libro de desembolsos: se ven los montos pagados, sin la fecha ni la vía de cada
            pago.
          </p>
        )}
      </section>
    </div>
  );
}

function Seccion({
  titulo,
  total,
  nota,
  children,
}: {
  titulo: string;
  total: number;
  nota?: string;
  children: ReactNode;
}) {
  return (
    <section className="grid gap-3">
      <div className="flex items-baseline justify-between gap-3 border-b border-sand pb-1">
        <h3 className="font-serif text-lg">{titulo}</h3>
        <span className={cx("font-semibold", total < 0 && "text-pizarra")}>{formatSoles(total)}</span>
      </div>
      {nota && <p className="-mt-1 text-xs text-taupe">{nota}</p>}
      {children}
    </section>
  );
}

function Dato({ etiqueta, children, className }: { etiqueta: string; children: ReactNode; className?: string }) {
  return (
    <div className={cx("min-w-0", className)}>
      <dt className="text-xs text-taupe">{etiqueta}</dt>
      <dd>{children}</dd>
    </div>
  );
}

function BloqueVentana({ p, v, data, libro, anio }: { p: ProvPersona; v: Ventana; data: ProvData; libro: Libro; anio: number }) {
  const estado = estadoVentana(p, v, data.as_of);
  const saldo = p[v.clave];
  const nueve = bonificacionDe(p, v.clave);
  const esGrati = v.beneficio === "Gratificación";
  return (
    <div className="grid gap-3 rounded-control border border-sand p-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h4 className="font-medium">
          {v.mes} {anio} <span className="font-normal text-taupe">· {v.periodo}</span>
        </h4>
        <Insignia variante={VARIANTE[estado]} atenuada={estado === "acumulando" || estado === "sin_monto"}>
          {ETIQUETA_ESTADO_VENTANA[estado]}
        </Insignia>
      </div>
      <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm sm:grid-cols-3">
        <Dato etiqueta="Devengado">{formatSoles(devengadoVentana(p, v.clave))}</Dato>
        <Dato etiqueta="Pagado">
          <Pagos p={p} ventana={v.clave} anio={anio} libro={libro} />
        </Dato>
        <Dato etiqueta="Saldo" className={cx("font-semibold", saldo < 0 && "text-pizarra")}>
          {formatSoles(saldo)}
        </Dato>
        {esGrati && <Dato etiqueta="9 % pendiente">{formatSoles(nueve)}</Dato>}
        <Dato etiqueta={estado === "acumulando" ? `Se paga · acumula hasta ${fechaCorta(v.cierre)}` : "Fecha de pago"}>
          {fechaCorta(v.pago)}
        </Dato>
      </dl>
      {estado === "pagado_de_mas" && <Origen />}
    </div>
  );
}

function BloqueVacaciones({ p, libro, anio }: { p: ProvPersona; libro: Libro; anio: number }) {
  const estado = estadoVacaciones(p);
  const pagado = p.vac_monto_pagado ?? 0;
  const [y, resto] = [p.proximo_aniversario.slice(0, 4), p.proximo_aniversario.slice(4)];
  const desde = `${Number(y) - 1}${resto}`;
  return (
    <div className="grid gap-3 rounded-control border border-sand p-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h4 className="font-medium">
          Desde el {fechaCorta(desde)} <span className="font-normal text-taupe">· último aniversario</span>
        </h4>
        <Insignia variante={VARIANTE[estado]} atenuada={estado === "acumulando"}>
          {ETIQUETA_ESTADO_VENTANA[estado]}
        </Insignia>
      </div>
      <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm sm:grid-cols-3">
        <Dato etiqueta="Devengado">{formatSoles(Math.round((p.vac + pagado) * 100) / 100)}</Dato>
        <Dato etiqueta={`Pagado en ${anio}`}>
          <Pagos p={p} ventana="vacaciones" anio={anio} libro={libro} />
        </Dato>
        <Dato etiqueta="Saldo" className={cx("font-semibold", p.vac < 0 && "text-pizarra")}>
          {formatSoles(p.vac)}
        </Dato>
        <Dato etiqueta="Días acumulados">{p.vac_dias.toFixed(1)}</Dato>
        <Dato etiqueta="Próximo aniversario">{fechaCorta(p.proximo_aniversario)}</Dato>
      </dl>
      <p className="text-xs text-taupe">Se pagan cuando se gozan; no tienen una fecha común.</p>
      {estado === "pagado_de_mas" && <Origen vacaciones />}
    </div>
  );
}

function Pagos({
  p,
  ventana,
  anio,
  libro,
  monto,
}: {
  p: ProvPersona;
  ventana: VentanaLibro;
  anio: number;
  libro: Libro;
  /** Lo cobrado, cuando no viaja en el jsonb de fn_provisiones: las dos
   *  ventanas de modalidad formativa lo traen de su propia función (0467). */
  monto?: number;
}) {
  // Las dos ventanas de modalidad formativa (0467) no viven en el jsonb de
  // fn_provisiones: su cobrado llega en `monto`, desde la otra función.
  const esDeModalidadFormativa = ventana === "subvencion_semestral" || ventana === "descanso_practicante";
  const total =
    monto ??
    (esDeModalidadFormativa ? 0 : ventana === "vacaciones" ? (p.vac_monto_pagado ?? 0) : pagadoVentana(p, ventana));
  if (total <= 0) return <>—</>;
  if (!libro) return <>{formatSoles(total)}</>;
  const pagos = pagosDe(p, ventana, anio, libro, total);
  return (
    <>
      {formatSoles(pagos.total)}
      {pagos.filas.map((f) => (
        <span key={`${f.fecha_pago}-${f.created_at}-${f.monto}`} className="block text-xs text-taupe">
          {fechaCorta(f.fecha_pago)} · {ETIQUETA_ORIGEN[f.origen] ?? f.origen} · {formatSoles(Number(f.monto))}
          {f.nota ? ` · ${f.nota}` : ""}
        </span>
      ))}
      {pagos.porPlanilla > 0 && (
        <span className="block text-xs text-taupe">
          registrado en planilla{pagos.filas.length ? ` · ${formatSoles(pagos.porPlanilla)}` : ""}
        </span>
      )}
    </>
  );
}

// El sistema no sabe por qué un pago superó lo devengado, así que no lo
// adivina: lista las causas posibles en el orden en que conviene revisarlas.
// Medidas en la auditoría del 2026-09-15; la tercera nace en el modal
// «Adelanto de beneficio» de Planilla, que archiva la CTS por semestre
// calendario (arreglo pendiente, en su propio lote).
function Origen({ vacaciones = false }: { vacaciones?: boolean }) {
  return (
    <div className="rounded-control bg-pizarra/[0.08] p-3">
      <p className="text-sm font-medium text-pizarra">Por qué puede salir en negativo</p>
      <p className="mb-1 text-xs text-taupe">El sistema no sabe cuál es: conviene revisarlo en este orden.</p>
      <ul className="list-disc space-y-0.5 pl-5 text-xs text-tinta">
        {vacaciones ? (
          <>
            <li>El pago corresponde al periodo de aniversario anterior: el libro lo cuenta por año calendario.</li>
            <li>Se pagaron más días de los acumulados en este periodo.</li>
          </>
        ) : (
          <>
            <li>Faltan días en la base de ese periodo: jornadas sin marcaje o sin tramo de salario.</li>
            <li>El depósito se calculó sobre otra base (por ejemplo, la del contador): entonces es un ajuste legítimo.</li>
            <li>Un adelanto quedó anotado en esta ventana y correspondía a otra.</li>
          </>
        )}
      </ul>
    </div>
  );
}

import type { ReactNode } from "react";
import { formatSoles } from "@/lib/rangos";
import { Tabla, TablaEncabezado, Th, Fila } from "@/components/ui/tabla";
import { Insignia } from "@/components/ui/insignia";
import {
  ETIQUETA_ESTADO_FILA,
  esPracticante,
  estadosFila,
  fechaCorta,
  gratiConBonificacion,
  montoProximo,
  proximoDesembolso,
  resumen,
  saldoDeFila,
  subvencionDe,
  totalProximo,
  totalesSubvenciones,
  type EstadoFila,
  type ProvData,
  type ProvPersona,
  type Subvenciones,
} from "@/lib/admin/provisiones";

export type AbrirPersona = (persona: ProvPersona, origen: HTMLElement) => void;

const VARIANTE: Record<EstadoFila, "alerta" | "advertencia" | "informativo" | "neutral"> = {
  sin_tramo: "alerta",
  vencido: "advertencia",
  pagado_de_mas: "informativo",
  al_dia: "neutral",
  no_aplica: "neutral",
};

/**
 * El estado de una fila.
 *
 * Una practicante NO lleva los estados de gratificación/CTS/vacaciones —esos
 * conceptos no le corresponden por ley— sino los suyos: que su modalidad es
 * formativa, y si le falta la subvención cargada, que es lo único que puede
 * dejar su reserva en cero por descuido nuestro.
 */
export function Estados({
  persona: p,
  data,
  subvenciones,
}: {
  persona: ProvPersona;
  data: ProvData;
  subvenciones?: Subvenciones;
}) {
  if (esPracticante(p)) {
    const s = subvencionDe(subvenciones, p);
    return (
      <span className="flex flex-wrap gap-1">
        <Insignia variante="informativo">Modalidad formativa</Insignia>
        {s?.sin_subvencion && <Insignia variante="alerta">Subvención sin cargar</Insignia>}
      </span>
    );
  }
  return (
    <span className="flex flex-wrap gap-1">
      {estadosFila(p, data).map((e) => (
        <Insignia key={e} variante={VARIANTE[e]} atenuada={e === "al_dia" || e === "no_aplica"}>
          {ETIQUETA_ESTADO_FILA[e]}
        </Insignia>
      ))}
    </span>
  );
}

// Un negativo no se esconde (decisión de la 0158) y tampoco se deja solo: dice
// que es un pago de más y que el detalle explica de dónde sale.
function Monto({ n, sub }: { n: number; sub?: ReactNode }) {
  if (n < 0) {
    return (
      <>
        <span className="text-pizarra">{formatSoles(n)}</span>
        <span className="block text-xs text-pizarra">pagado de más · ver origen</span>
      </>
    );
  }
  return (
    <>
      {formatSoles(n)}
      {sub && <span className="block text-xs text-taupe">{sub}</span>}
    </>
  );
}

/** Lo que una practicante no devenga por ley: se dice con palabras, no con un cero. */
function NoAplica() {
  return <span className="text-taupe italic">No aplica</span>;
}

const soloDiaMes = (iso: string) => fechaCorta(iso).replace(/ \d{4}$/, "");

// La tabla principal. Ocho columnas de dinero y estado; el detalle por ventana
// vive en el panel lateral.
//
// «Gratificación» lleva su 9 % adentro para que Gratificación + CTS +
// Vacaciones sea exactamente el «Saldo total» que manda la base (la regla del
// 2026-08-19: un total que no cuadra con lo que se ve enseña a desconfiar).
//
// CAMBIO 0465 — las practicantes dejaron la sección plegada y entran a la
// tabla, con lo que la ley SÍ les da: media subvención por cada 6 meses y el
// descanso de 15 días al cumplir el año (Ley 28518 art. 42), y «No aplica» —no
// un cero— en gratificación y CTS (art. 47). Su saldo sale de otra función,
// `fn_subvenciones_practicante`, así que la columna «Media subvención» está
// vacía para todos los demás: son dos cuentas distintas y no se suman entre sí.
export function TablaProvisiones({
  data,
  personas,
  subvenciones,
  onAbrir,
  vacio,
}: {
  data: ProvData;
  personas: ProvPersona[];
  subvenciones: Subvenciones;
  onAbrir: AbrirPersona;
  vacio: ReactNode;
}) {
  if (personas.length === 0) {
    return (
      <div className="rounded-superficie border border-sand bg-papel px-4 py-10 text-center text-sm text-taupe">
        {vacio}
      </div>
    );
  }

  const conDerecho = personas.filter((p) => !esPracticante(p));
  const prox = proximoDesembolso(data);
  const r = resumen(conDerecho);
  const subv = totalesSubvenciones(personas, subvenciones);
  const totalProx = totalProximo(conDerecho, data);
  const cuandoProx = prox?.fiable ? `acumulado · ${soloDiaMes(prox.fecha)}` : undefined;
  const hayProxNegativo = conDerecho.some((p) => (montoProximo(p, data) ?? 0) < 0);
  const sinMontoProx = "Del 16 al 31 de diciembre el próximo pago es del año siguiente y todavía no tiene monto.";
  const saldoTotal = Math.round((r.total + (subv?.total ?? 0)) * 100) / 100;

  return (
    <>
      <div className="hidden md:block">
        <Tabla alturaMaxima="70vh" className="[font-variant-numeric:tabular-nums]">
          <TablaEncabezado>
            <Th>Persona</Th>
            <Th>Sede</Th>
            <Th className="text-right">Gratificación</Th>
            <Th className="text-right">CTS</Th>
            <Th className="text-right">Vacaciones</Th>
            <Th className="text-right">Media subvención</Th>
            <Th className="text-right">Próximo pago</Th>
            <Th className="text-right">Saldo total</Th>
            <Th>Estado</Th>
            <Th>
              <span className="sr-only">Detalle</span>
            </Th>
          </TablaEncabezado>
          <tbody>
            {personas.map((p) => {
              const s = subvencionDe(subvenciones, p);
              const practicante = esPracticante(p);
              const mp = montoProximo(p, data);
              return (
                <Fila key={p.persona_id} className="cursor-pointer" onClick={(e) => onAbrir(p, e.currentTarget)}>
                  <td className="px-4 py-2 align-top">
                    {/* El botón es la puerta del teclado; el clic en la fila, la del ratón. */}
                    <button
                      type="button"
                      className="text-left font-medium underline-offset-2 hover:underline"
                      onClick={(e) => {
                        e.stopPropagation();
                        onAbrir(p, e.currentTarget);
                      }}
                    >
                      {p.nombre}
                    </button>
                    {/* CAMBIO 0365 — quien hoy tiene tramo pero tuvo un hueco en el año
                        también reservó de menos; sin este texto no se ve en ningún sitio. */}
                    {!practicante && !p.sin_salario_vigente && (p.dias_sin_salario ?? 0) > 0 && (
                      <span className="block text-xs text-rojo-profundo">
                        {p.dias_sin_salario} {p.dias_sin_salario === 1 ? "día" : "días"} sin salario cargado
                      </span>
                    )}
                  </td>
                  <td className="px-4 py-2 align-top">{p.sede}</td>

                  {/* Gratificación y CTS: por ley no le tocan a una practicante. */}
                  <td className="px-4 py-2 text-right align-top">
                    {practicante ? (
                      <NoAplica />
                    ) : (
                      <Monto
                        n={gratiConBonificacion(p)}
                        sub={p.be_total ? `incl. 9 % ${formatSoles(p.be_total)}` : undefined}
                      />
                    )}
                  </td>
                  <td className="px-4 py-2 text-right align-top">
                    {practicante ? <NoAplica /> : <Monto n={p.cts_total} />}
                  </td>

                  {/* Vacaciones · para una practicante, su descanso de 15 días. */}
                  <td className="px-4 py-2 text-right align-top">
                    {practicante ? (
                      s ? (
                        <Monto
                          n={s.descanso_saldo}
                          sub={s.descanso_ganado ? "descanso ganado" : `descanso al ${soloDiaMes(s.descanso_cumple)}`}
                        />
                      ) : (
                        <span className="text-taupe">—</span>
                      )
                    ) : (
                      <Monto n={p.vac} sub={`${p.vac_dias.toFixed(1)} días`} />
                    )}
                  </td>

                  {/* Media subvención · solo modalidad formativa. */}
                  <td className="px-4 py-2 text-right align-top">
                    {!practicante ? (
                      <span className="text-taupe">—</span>
                    ) : s ? (
                      <Monto n={s.media_sub_saldo} sub={`hito ${soloDiaMes(s.proximo_hito)}`} />
                    ) : (
                      <span className="text-taupe">—</span>
                    )}
                  </td>

                  <td className="px-4 py-2 text-right align-top">
                    {practicante ? (
                      s ? (
                        <Monto n={s.media_sub_saldo} sub={soloDiaMes(s.proximo_hito)} />
                      ) : (
                        <span className="text-taupe">—</span>
                      )
                    ) : mp === null ? (
                      <span className="text-taupe" title={prox ? sinMontoProx : undefined}>
                        —
                      </span>
                    ) : (
                      <Monto n={mp} sub={cuandoProx} />
                    )}
                  </td>
                  <td className="bg-sand/30 px-4 py-2 text-right align-top font-semibold">
                    {formatSoles(saldoDeFila(p, subvenciones))}
                  </td>
                  <td className="px-4 py-2 align-top">
                    <Estados persona={p} data={data} subvenciones={subvenciones} />
                  </td>
                  <td className="px-3 py-2 text-right align-top text-taupe" aria-hidden>
                    ›
                  </td>
                </Fila>
              );
            })}
          </tbody>
          <tfoot>
            <tr className="border-t border-taupe/40 bg-sand/50 font-medium">
              <td className="px-4 py-2" colSpan={2}>
                Total · {personas.length} {personas.length === 1 ? "persona" : "personas"}
                {subv && (
                  <span className="block text-xs font-normal text-taupe">
                    incluye {subv.personas} en modalidad formativa
                  </span>
                )}
              </td>
              <td className="px-4 py-2 text-right">{formatSoles(r.gratificacion)}</td>
              <td className="px-4 py-2 text-right">{formatSoles(r.cts)}</td>
              <td className="px-4 py-2 text-right">
                {formatSoles(r.vacaciones)}
                {subv && (
                  <span className="block text-xs font-normal text-taupe">
                    + {formatSoles(subv.descanso)} de descanso
                  </span>
                )}
              </td>
              <td className="px-4 py-2 text-right">{subv ? formatSoles(subv.media) : "—"}</td>
              <td className="px-4 py-2 text-right">
                {totalProx === null ? "—" : formatSoles(totalProx)}
                {hayProxNegativo && (
                  <span className="block text-xs font-normal text-taupe">sin descontar pagos de más</span>
                )}
              </td>
              <td className="px-4 py-2 text-right font-semibold">{formatSoles(saldoTotal)}</td>
              <td className="px-4 py-2" colSpan={2} />
            </tr>
          </tfoot>
        </Tabla>
      </div>

      {/* En el teléfono la matriz no se comprime: una tarjeta por persona. */}
      <ul className="grid gap-3 md:hidden [font-variant-numeric:tabular-nums]">
        {personas.map((p) => {
          const s = subvencionDe(subvenciones, p);
          const practicante = esPracticante(p);
          const mp = montoProximo(p, data);
          return (
            <li key={p.persona_id}>
              <button
                type="button"
                onClick={(e) => onAbrir(p, e.currentTarget)}
                className="grid w-full gap-2 rounded-superficie border border-sand bg-papel p-4 text-left"
              >
                <span className="flex items-baseline justify-between gap-3">
                  <span className="font-medium">
                    {p.nombre} <span className="text-xs font-normal text-taupe">{p.sede}</span>
                  </span>
                  <span className="font-semibold">{formatSoles(saldoDeFila(p, subvenciones))}</span>
                </span>
                <Estados persona={p} data={data} subvenciones={subvenciones} />
                <span className="grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
                  {practicante ? (
                    <>
                      <Dato etiqueta="Media subvención" valor={s ? formatSoles(s.media_sub_saldo) : "—"} />
                      <Dato etiqueta="Descanso" valor={s ? formatSoles(s.descanso_saldo) : "—"} />
                      <Dato etiqueta="Gratificación y CTS" valor="No aplica" />
                      <Dato etiqueta="Próximo hito" valor={s ? soloDiaMes(s.proximo_hito) : "—"} />
                    </>
                  ) : (
                    <>
                      <Dato etiqueta="Gratificación" valor={formatSoles(gratiConBonificacion(p))} />
                      <Dato etiqueta="CTS" valor={formatSoles(p.cts_total)} />
                      <Dato etiqueta="Vacaciones" valor={formatSoles(p.vac)} />
                      <Dato
                        etiqueta="Próximo pago"
                        valor={mp === null || !prox ? "—" : `${formatSoles(mp)} · ${soloDiaMes(prox.fecha)}`}
                      />
                    </>
                  )}
                </span>
              </button>
            </li>
          );
        })}
      </ul>
    </>
  );
}

function Dato({ etiqueta, valor }: { etiqueta: string; valor: string }) {
  return (
    <span className="min-w-0">
      <span className="block text-xs text-taupe">{etiqueta}</span>
      <span className={valor.startsWith("-") ? "text-pizarra" : undefined}>{valor}</span>
    </span>
  );
}
